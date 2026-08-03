#!/usr/bin/env python3
"""Stage-2 Job 2 post-processing — turn raw Stable Audio takes into game assets.

Stable Audio Open always hands back a ~47.55 s / 44.1 kHz window and pads the
unused remainder with digital silence, so every take needs trimming before it
is worth anything. Two trim strategies:

  one-shot  locate the loudest 10 ms frame, walk outwards to the surrounding
            silence, keep a short pre-roll and the natural decay tail. This
            beats a plain `silenceremove` because several takes contain a
            faint pre-echo blip *before* the real transient (the pilot tackle
            had a -39 dB tick at 0.1 s and the actual hit at 0.9 s) — anchoring
            on the peak and stopping at the silence gap drops the blip.

  bed       keep the swell shape: strip only the trailing silence, cap to the
            conditioned length, gentle fades.

Then: pad to >=0.6 s so EBU R128 gating has a valid block, single linear gain
to -18 LUFS / -1.5 dBTP ceiling (see audio_common), 48 kHz stereo, three
flavours per take. Writes gen/manifest.json.
"""

from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
from pathlib import Path

import audio_common as ac

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "gen_raw"
OUT = ROOT / "gen"

# stem-prefix -> (kind, max_seconds)
PROFILE = {
    "kick_punt": ("oneshot", 2.0),
    "kick_place": ("oneshot", 2.0),
    "catch": ("oneshot", 2.0),
    "throw_whoosh": ("oneshot", 1.5),
    "tackle_impact": ("oneshot", 2.5),
    "whistle": ("oneshot", 2.2),
    "shouts": ("oneshot", 2.5),
    "crowd_boo_extra": ("bed", 10.0),
    "crowd_gasp_extra": ("bed", 7.0),
    "crowd_chant_extra": ("bed", 10.0),
}
# per-take overrides where the take differs from its category default
TAKE_OVERRIDE = {
    "double": ("oneshot", 3.0),    # whistle double-blast needs room for blast 2
    "cadence": ("oneshot", 5.0),   # multi-syllable shout
}

SILENCE = -95.0


def window_oneshot(env: list[float], fs: float, max_s: float) -> tuple[float, float]:
    peak = max(env)
    pk = env.index(peak)
    # walk back to the silence that precedes the transient
    thr_start = max(peak - 35.0, SILENCE)
    i = pk
    while i > 0 and env[i - 1] > thr_start:
        i -= 1
    start = max(0, i - 3)                      # ~30 ms pre-roll
    # walk forward until it has been quiet for 80 ms straight
    thr_end = max(peak - 50.0, SILENCE)
    j, quiet = pk, 0
    while j < len(env) - 1:
        j += 1
        if env[j] < thr_end:
            quiet += 1
            if quiet >= 8:
                break
        else:
            quiet = 0
    end = min(len(env) - 1, j + 5)             # ~50 ms tail
    t0, t1 = start * fs, end * fs
    return t0, min(t1, t0 + max_s)


def window_bed(env: list[float], fs: float, max_s: float) -> tuple[float, float]:
    peak = max(env)
    thr = max(peak - 45.0, SILENCE)
    last = 0
    for k, v in enumerate(env):
        if v > thr:
            last = k
    first = 0
    for k, v in enumerate(env):
        if v > thr:
            first = k
            break
    t0 = max(0.0, first * fs - 0.05)
    t1 = min((last + 30) * fs, t0 + max_s)     # +300 ms tail
    return t0, t1


def profile_for(stem: str, cat: str) -> tuple[str, float]:
    for key, prof in TAKE_OVERRIDE.items():
        if key in stem:
            return prof
    return PROFILE[cat]


def process(raw: Path, cat: str) -> dict | None:
    stem = raw.stem
    meta_p = raw.with_suffix(".json")
    meta = json.loads(meta_p.read_text()) if meta_p.exists() else {}
    kind, max_s = profile_for(stem, cat)

    env, fs = ac.envelope(raw, frame_ms=10, limit_s=20.0)
    if not env or max(env) < -70:
        return {"stem": stem, "category": cat, "status": "silent", "meta": meta}

    t0, t1 = (window_oneshot if kind == "oneshot" else window_bed)(env, fs, max_s)
    dur = max(0.05, t1 - t0)

    fade_in = 0.003 if kind == "oneshot" else 0.03
    fade_out = min(0.03 if kind == "oneshot" else 0.30, dur / 3)

    # trim -> fades -> pad so R128 has a full gating block to chew on
    trim = (f"atrim=start={t0:.3f}:end={t1:.3f},asetpts=PTS-STARTPTS,"
            f"afade=t=in:st=0:d={fade_in:.3f},"
            f"afade=t=out:st={max(0, dur - fade_out):.3f}:d={fade_out:.3f}")
    pad = f",apad=whole_dur={max(dur, ac.MIN_MEASURE_S):.3f}"

    tmpdir = Path(tempfile.mkdtemp(prefix="sfx_"))
    try:
        stage = tmpdir / "stage.wav"
        p = ac.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", str(raw), "-map", "0:a:0", "-af", trim + pad,
                    "-ar", str(ac.RATE), "-ac", "2", "-c:a", "pcm_f32le", str(stage)])
        if p.returncode != 0:
            raise RuntimeError(p.stderr[-600:])

        before = ac.measure(stage)
        plan = ac.gain_plan(before)
        if not plan["ok"]:
            return {"stem": stem, "category": cat, "status": "silent", "meta": meta}

        af = f"volume={plan['gain_db']}dB"
        files = ac.encode_set(stage, OUT / cat, stem, af)
        ship = Path(files["ship_wav_16bit"])
        after = ac.measure(ship)
        info = ac.probe(ship)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)

    return {
        "stem": stem, "category": cat, "status": "ok", "kind": kind,
        "trim": {"start_s": round(t0, 3), "end_s": round(t1, 3),
                 "duration_s": round(info["duration"], 3)},
        "gain_db": plan["gain_db"], "bound_by": plan["bound_by"],
        "in_LUFS": before.get("I"), "in_TP_dBTP": before.get("TP"),
        "out_LUFS": after.get("I"), "out_TP_dBTP": after.get("TP"),
        "out": info,
        "prompt": meta.get("prompt"), "negative_prompt": meta.get("negative_prompt"),
        "seed": meta.get("seed"), "seconds_total": meta.get("seconds_total"),
        "model": meta.get("model"), "version": meta.get("version"),
        "predict_time": meta.get("predict_time"),
        "prediction_id": meta.get("prediction_id"),
        "files": {k: str(Path(v).relative_to(ROOT)) for k, v in files.items()},
    }


def main() -> None:
    results = []
    for catdir in sorted(RAW.iterdir()):
        if not catdir.is_dir():
            continue
        cat = catdir.name
        if cat not in PROFILE:
            continue
        for raw in sorted(catdir.glob("*.wav")):
            if "_pilot" in raw.stem:
                continue
            r = process(raw, cat)
            if r:
                results.append(r)
                if r["status"] == "ok":
                    print(f"[ok]   {cat:18s} {r['stem']:34s} "
                          f"{r['trim']['duration_s']:5.2f}s  "
                          f"{r['in_LUFS']} -> {r['out_LUFS']} LUFS  "
                          f"TP {r['out_TP_dBTP']}  ({r['bound_by']})")
                else:
                    print(f"[{r['status'].upper()}] {cat:18s} {r['stem']}")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "manifest.json").write_text(json.dumps(results, indent=2))
    ok = sum(1 for r in results if r["status"] == "ok")
    print(f"\n{ok}/{len(results)} usable -> {OUT/'manifest.json'}")


if __name__ == "__main__":
    main()
