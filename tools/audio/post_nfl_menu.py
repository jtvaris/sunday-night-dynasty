#!/usr/bin/env python3
"""Master + measure + score the NFL-broadcast MENU round.

The mirror image of `post_nfl_dash.py`. `analyze_nfl_menu.py` already measured
the raw ACE-Step returns, but it deliberately writes nothing: it answers "is
this file usable", not "is this the take". Two things were still missing before
anything from this round could ship —

  1. a MASTER. The raw returns sit between -11.3 and -15.3 LUFS and carry up to
     1.7 s of ACE-Step tail padding. Everything already in the bundle is
     -16 LUFS / -1.5 dBTP with the dead air trimmed off a measured RMS
     envelope, so an unmastered take would jump out of the rotation on level
     alone. Same chain as post_music.py, imported rather than re-derived.
  2. a SCORE. The dash round has one; this round did not, so the two halves of
     the same job could not be ranked the same way.

WHAT THE SCORE IS — same disclaimer as the dash round, inverted brief. Nobody
in this loop can listen, so the 1-5 is not a judgement of whether the music is
good. It is the measured answer to "does this behave like a title-screen
anthem", which is the OPPOSITE shape from an underscore: a menu theme is
*supposed* to arc.

  peak_pos    where the loudest moment sits. An anthem lands its fanfare late;
              a take that peaks in bar 2 has already spent itself.
  build_db    last third minus first third. Should be positive — the dash
              round penalises exactly this.
  intro       first 3 s against the body. The menu fades in under a still
              screen, so a quiet opening is the brief.
  band_mid    200-2000 Hz is where brass lives. A take that is all sub-200 is
              a pad wash and a take that is all 4 kHz+ is a cymbal wash;
              neither is a fanfare.
  bpm_err     a march ordered at 124 BPM that came back at 78 is a failed
              prompt, measured octave-aware so half/double-time is not a
              fake miss.

Measured on the MASTER, not the raw return, so the numbers describe what would
actually ship (this is what stops `march_drive`'s 1.65 s of head silence from
reading as a beautifully quiet intro).

As with the dash round: a FILTER, not a ranking. Round 3 of generate_music.py
proved the take the metrics liked least was the one the user approved, so every
deduction is printed as a reason that can be overruled by an ear.

Usage:
    python3 post_nfl_menu.py
"""

from __future__ import annotations

import json
import re
import statistics
from pathlib import Path

import audio_common as ac
import post_music as pm
import analyze_nfl_menu as an
import score_nfl_menu as sn

ROOT = Path(__file__).resolve().parent
GEN = ROOT / "gen_nfl_menu"

ac.TARGET_I, ac.TARGET_TP = -16.0, -1.5

# The brief asked for 90-120 s anthems; the two menu themes already shipped are
# 103.7 s and 99.0 s.
BRIEF_MIN_S, BRIEF_MAX_S = 88.0, 125.0


def score(m: dict) -> tuple[float, list[str]]:
    """5.0 minus measured reasons it would not work as a menu anthem."""
    s, why = 5.0, []

    pk = m.get("peak_pos") or 0
    if pk < 0.35:
        s -= 1; why.append(f"peaks at {pk:.0%} — spent before it starts")
    elif pk < 0.45:
        s -= 0.5; why.append(f"peaks early, {pk:.0%}")

    b = m.get("build_db")
    b = 0.0 if b is None else b
    if b < -2.5:
        s -= 1; why.append(f"decays {b:+.1f} dB — ends smaller than it opens")
    elif b < 0:
        s -= 0.5; why.append(f"flat-to-down, {b:+.1f} dB")

    intro = m.get("intro_vs_body_db")
    intro = 0.0 if intro is None else intro
    if intro > 0.5:
        s -= 1; why.append(f"opens at full blast ({intro:+.1f} dB over body)")
    elif intro > -1.0:
        s -= 0.5; why.append(f"no quiet intro ({intro:+.1f} dB)")

    mid = m.get("band_mid_pct") or 0
    if mid < 25:
        s -= 1; why.append(f"thin through the brass band, {mid:.0f}% mid")
    elif mid < 35:
        s -= 0.5; why.append(f"{mid:.0f}% mid — brass sits back")

    low = m.get("band_low_pct") or 0
    if low >= 75:
        s -= 0.5; why.append(f"{low:.0f}% below 200 Hz — bottom-heavy")

    hi = m.get("band_high_pct") or 0
    if hi > 15:
        s -= 0.5; why.append(f"{hi:.0f}% above 4 kHz — cymbal wash")

    err = m.get("bpm_err")
    if err is not None:
        if err > 15:
            s -= 1; why.append(f"came back {err:.0f} BPM off the order")
        elif err > 8:
            s -= 0.5; why.append(f"{err:.0f} BPM off the order")

    arc = m.get("arc_db") or 0
    if arc > 18:
        s -= 1; why.append(f"{arc:.0f} dB arc — quiet passages will vanish")
    elif arc > 12:
        s -= 0.5; why.append(f"{arc:.0f} dB arc")

    lra = m.get("LRA") or 0
    if lra > 9:
        s -= 0.5; why.append(f"LRA {lra:.1f}")

    d = m.get("duration") or 0
    if not (BRIEF_MIN_S <= d <= BRIEF_MAX_S):
        s -= 0.5; why.append(f"{d:.0f}s outside the {BRIEF_MIN_S:.0f}-"
                             f"{BRIEF_MAX_S:.0f}s brief")

    return max(1.0, min(5.0, s)), why


def main() -> None:
    metas = []
    for lane_dir in sorted(GEN.iterdir()):
        if lane_dir.is_dir() and lane_dir.name != "__pycache__":
            metas += sorted(lane_dir.glob("*.json"))
    if not metas:
        raise SystemExit("no takes — run generate_nfl_menu.py first")

    rows = []
    for mp in metas:
        meta = json.loads(mp.read_text())
        src = mp.parent / meta["file"]
        stem = meta["stem"]

        raw_dur = pm.probe_dur(src)
        t0, t1 = pm.trim_window(src)

        pre = f"atrim=start={t0}:end={t1},asetpts=N/SR/TB"
        chain = ac.master_chain(src, pre_filter=pre)["chain"]
        wav = GEN / f"{stem}.wav"
        p = ac.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", str(src), "-map", "0:a:0", "-vn", "-af", chain,
                    "-ar", "48000", "-ac", "2", "-c:a", "pcm_s24le", str(wav)])
        if p.returncode != 0:
            raise RuntimeError(f"{stem}: {p.stderr[-600:]}")

        prev = GEN / f"{stem}.m4a"
        p = ac.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", str(wav), "-vn", "-map", "0:a:0",
                    "-c:a", "aac", "-b:a", "192k", str(prev)])
        if p.returncode != 0:
            raise RuntimeError(f"{stem} preview: {p.stderr[-600:]}")

        loud = ac.measure(wav)
        want = re.search(r"(\d+)\s*BPM", meta["prompt"])
        want = float(want.group(1)) if want else 100.0
        dur = pm.probe_dur(wav)

        m = {
            "stem": stem, "lane": meta["style"], "seed": meta["seed"],
            "prompt": meta["prompt"], "round": meta["round"],
            "model": meta["model"], "prediction_id": meta.get("prediction_id"),
            "predict_time": meta.get("predict_time"),
            "requested_duration": meta["requested_duration"],
            "raw_duration": round(raw_dur, 2),
            "lead_silence_s": round(t0, 2),
            "tail_silence_s": round(raw_dur - t1, 2),
            "duration": round(dur, 2),
            "LUFS": loud.get("I"), "dBTP": loud.get("TP"), "LRA": loud.get("LRA"),
        }
        m.update(pm.spectral(wav))
        m.update(pm.structure(wav))
        m.update(an.intro(wav))
        m.update(sn.measure(wav, want, dur))
        m["score"], m["reasons"] = score(m)
        m["files"] = {"raw": str(src.relative_to(ROOT)),
                      "master_wav": str(wav.relative_to(ROOT)),
                      "preview_m4a": str(prev.relative_to(ROOT))}
        rows.append(m)
        print(f"  {stem:<26} {m['duration']:6.1f}s  {m['LUFS']!s:>6} LUFS  "
              f"peak@{(m.get('peak_pos') or 0):.2f}  "
              f"build {m.get('build_db')!s:>5}  intro {m.get('intro_vs_body_db')!s:>5}  "
              f"mid {m.get('band_mid_pct')!s:>5}%  bpm±{m.get('bpm_err')!s:>4}  "
              f"-> {m['score']}")

    rows.sort(key=lambda r: (-r["score"], r["stem"]))

    tsv = GEN / "candidates_nfl_menu.tsv"
    hdr = ["lane", "file", "seed", "duration_s", "LUFS", "LRA", "centroid_hz",
           "peak_pos", "build_db", "intro_vs_body_db", "band_mid_pct",
           "bpm_octave_fit", "bpm_want", "tail_silence_s", "score", "reason",
           "prompt"]
    lines = ["\t".join(hdr)]
    for r in rows:
        reason = "; ".join(r["reasons"]) if r["reasons"] else \
            "builds late off a quiet open with brass body — clean anthem fit"
        lines.append("\t".join(str(x) for x in [
            r["lane"], r["files"]["preview_m4a"], r["seed"],
            f"{r['duration']:.2f}", r["LUFS"], r["LRA"], r["centroid_hz"],
            r.get("peak_pos"), r.get("build_db"), r.get("intro_vs_body_db"),
            r.get("band_mid_pct"), r.get("bpm_octave_fit"), r.get("bpm_want"),
            f"{r['tail_silence_s']:.2f}", r["score"], reason, r["prompt"]]))
    tsv.write_text("\n".join(lines) + "\n")

    gpu = sum(r.get("predict_time") or 0 for r in rows)
    out = {"round": rows[0]["round"], "gpu_seconds": round(gpu, 1),
           "rate_usd_per_s": 0.000975, "spend_usd": round(gpu * 0.000975, 4),
           "takes": rows}
    (GEN / "metrics.json").write_text(json.dumps(out, indent=2))
    print(f"\nGPU {gpu:.1f}s  ->  ${gpu * 0.000975:.4f}")
    print(f"wrote {tsv.name} + metrics.json")


if __name__ == "__main__":
    main()
