#!/usr/bin/env python3
"""Master the music experiment takes and measure them.

Stage 2 for `generate_music.py`. Raw model output -> reviewable candidates:

  1. trim dead air      windows read off a 50 ms RMS envelope, not guessed
  2. loudness           two-pass loudnorm to -16 LUFS / -1.5 dBTP, 48 kHz
                        stereo. NOTE this is 2 LU louder than the SFX target
                        (-18) in audio_common: music sits under UI at a fixed
                        level, and -16 LUFS is the streaming/game-music norm.
  3. loops only         seamless wrap via the same `acrossfade` fold-back that
                        ship_audio.py uses for the crowd bed, then the wrap
                        discontinuity is MEASURED rather than assumed
  4. analysis           spectral + structural proxies, because nobody here can
                        listen to these; see `structure()`

Outputs gen_music/<style>/<stem>.wav (24-bit master) + .m4a (review preview)
and gen_music/manifest.json.

Usage:
    python3 post_music.py                 # every raw take, manifest rewritten
    python3 post_music.py r3_             # only stems containing "r3_",
                                          # merged into the existing manifest

The filter form exists because mastering is not free: the ambient-loop seam
search renders up to 54 candidate folds per loop, so a full re-run costs
minutes to re-derive results that are already in the manifest and are
byte-identical (every step here is deterministic). Filtering keeps a new
round's turnaround proportional to the new round.
"""

from __future__ import annotations

import array
import json
import math
import re
import statistics
import subprocess
import sys
from pathlib import Path

import audio_common as ac

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "gen_music_raw"
OUT = ROOT / "gen_music"

# Music target — deliberately different from audio_common's -18 LUFS SFX
# target. audio_common reads these at call time, so patching them here is
# what retargets loudnorm.
ac.TARGET_I = -16.0
ac.TARGET_TP = -1.5
TARGET_I, TARGET_TP = -16.0, -1.5

LOOP_XFADE = 2.0    # seconds folded back onto the head of an ambient loop
TRIM_PAD = 0.05     # keep a hair either side of the detected window

# Round-1 caveat, now enforced. `ambient_downtempo_take1_loop` came out
# click-free but with its last 200 ms 7.8 dB LOUDER than its first 200 ms, so
# it would audibly "drop" on every wrap. A step-free seam is necessary but not
# sufficient: level continuity has to be measured too.
#
# The fix is a search, not a filter. The crossfade point is a free parameter —
# where you fold the tail back decides which two moments of the take end up
# adjacent — so if the default fold lands on a drum hit, try other folds and
# other tail cuts until the head and tail match. Baseline is tried FIRST and
# kept when it passes, so a loop that was already fine stays byte-identical.
LOOP_MAX_LVL_DB = 3.0                                   # head/tail delta ceiling
LOOP_MIN_S = 40.0                                       # brief floor for a loop
LOOP_XFADE_GRID = (2.0, 1.5, 2.5, 3.0, 1.0, 4.0)
LOOP_CUT_GRID = (0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0, 5.0)


def probe_dur(p: Path) -> float:
    return float(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", str(p)], capture_output=True, text=True).stdout.strip())


def trim_window(path: Path) -> tuple[float, float]:
    """First/last frame carrying real signal, off a 50 ms RMS envelope.

    Threshold is relative to the track's own peak so a quiet ambient bed is
    not mistaken for silence, with an absolute floor so a noisy-but-empty
    lead-in does not count as content.
    """
    env, fs = ac.envelope(path, frame_ms=50)
    dur = probe_dur(path)
    if not env:
        return 0.0, dur
    peak = max(env)
    thr = max(peak - 40.0, -55.0)
    live = [i for i, v in enumerate(env) if v >= thr]
    if not live:
        return 0.0, dur
    t0 = max(0.0, live[0] * fs - TRIM_PAD)
    t1 = min(dur, (live[-1] + 1) * fs + TRIM_PAD)
    return round(t0, 3), round(t1, 3)


def spectral(path: Path) -> dict:
    p = ac.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-map", "0:a:0",
                "-af", "aformat=channel_layouts=mono,aspectralstats=measure=centroid+flatness,"
                       "ametadata=print:file=-", "-f", "null", "-"])
    cent, flat = [], []
    for line in p.stdout.splitlines():
        m = re.search(r"lavfi\.aspectralstats\.1\.centroid=([\d.]+)", line)
        if m:
            cent.append(float(m.group(1)))
        m = re.search(r"lavfi\.aspectralstats\.1\.flatness=([\d.]+)", line)
        if m:
            flat.append(float(m.group(1)))
    return {"centroid_hz": round(statistics.median(cent)) if cent else None,
            "flatness": round(statistics.median(flat), 4) if flat else None}


def structure(path: Path) -> dict:
    """Does the track actually have an ARC, or is it a flat wall of sound?

    A menu theme that "builds to a peak" should show (a) its loudest moment
    late, and (b) a real spread between its quiet and loud sections. A track
    that is uniformly loud from bar 1 has no arc no matter how epic the
    instruments are, and will feel exhausting under a menu.
    """
    env, fs = ac.envelope(path, frame_ms=250)
    if len(env) < 8:
        return {}
    n = len(env)
    # 4-frame (1 s) moving average so a single cymbal crash is not "the peak"
    sm = [statistics.mean(env[max(0, i - 3):i + 1]) for i in range(n)]
    pk = max(range(n), key=lambda i: sm[i])
    third = max(1, n // 3)
    first_third = statistics.mean(env[:third])
    last_third = statistics.mean(env[-third:])
    ordered = sorted(env)
    p10 = ordered[int(0.10 * (n - 1))]
    p95 = ordered[int(0.95 * (n - 1))]
    return {
        "peak_pos": round(pk / (n - 1), 3),        # 0 = opens loudest, 1 = ends loudest
        "build_db": round(last_third - first_third, 1),
        "arc_db": round(p95 - p10, 1),             # depth of the dynamic arc
    }


def _samples(path: Path) -> tuple[list[array.array], int]:
    """De-interleaved 16-bit samples per channel."""
    p = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0",
         "-f", "s16le", "-acodec", "pcm_s16le", "-"],
        capture_output=True)
    a = array.array("h")
    a.frombytes(p.stdout[:len(p.stdout) // 2 * 2])
    ch = int(subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=channels", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True).stdout.strip() or 2)
    return [a[c::ch] for c in range(ch)], ch


def seam(path: Path) -> dict:
    """Measure the wrap discontinuity of a file played on `numberOfLoops = -1`.

    The click you hear at a bad loop point is a sample-value JUMP between the
    last sample and the first. So: compare that jump against the jumps the
    waveform makes anyway. If the wrap step is no bigger than the steps
    occurring all over the file, it is by definition inaudible — there is
    nothing there that the signal does not already do a thousand times.

    Reported in dBFS, plus the headroom between them (negative = clean).
    Level continuity across the wrap is reported separately, because a
    perfectly step-free wrap can still audibly "duck" if the tail is quieter
    than the head.
    """
    chans, _ = _samples(path)
    FS = 32768.0
    out = {}
    worst_step, worst_p999 = -200.0, -200.0
    for ci, x in enumerate(chans):
        if len(x) < 1000:
            continue
        step = abs(x[0] - x[-1])
        diffs = [abs(x[i + 1] - x[i]) for i in range(len(x) - 1)]
        diffs.sort()
        p999 = diffs[int(0.999 * (len(diffs) - 1))]
        mx = diffs[-1]
        db = lambda v: 20 * math.log10(max(v, 1e-9) / FS)
        worst_step = max(worst_step, db(step))
        worst_p999 = max(worst_p999, db(p999))
        out[f"ch{ci}"] = {"wrap_step_dbfs": round(db(step), 1),
                          "interior_p999_dbfs": round(db(p999), 1),
                          "interior_max_dbfs": round(db(mx), 1)}
    # level match across the wrap: RMS of the last 200 ms vs the first 200 ms
    n = int(0.2 * 48000)
    def rms(seq):
        s = sum(float(v) * v for v in seq) / max(1, len(seq))
        return 20 * math.log10(max(math.sqrt(s), 1e-9) / FS)
    head = rms(chans[0][:n])
    tail = rms(chans[0][-n:])
    out["wrap_step_dbfs"] = round(worst_step, 1)
    out["interior_p999_dbfs"] = round(worst_p999, 1)
    # negative => the wrap jump is smaller than the waveform's own 99.9th
    # percentile jump => no click
    out["headroom_db"] = round(worst_step - worst_p999, 1)
    out["level_match_db"] = round(tail - head, 1)
    out["verdict"] = "clean" if worst_step - worst_p999 <= 0 else (
        "marginal" if worst_step - worst_p999 <= 6 else "CLICK")
    return out


def render(src: Path, t0: float, t1: float, dst: Path, chain: str,
           codec: list[str]) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    p = ac.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-ss", f"{t0}", "-t", f"{t1 - t0}", "-i", str(src),
                "-map", "0:a:0", "-vn", "-af", chain,
                "-ar", "48000", "-ac", "2", *codec, str(dst)])
    if p.returncode != 0:
        raise RuntimeError(f"{dst.name}: {p.stderr[-600:]}")


def loop_render(src: Path, dst: Path, xfade: float, tail_cut: float = 0.0) -> float:
    """Fold the tail back onto the head so the file wraps seamlessly.

    Input 0 = body [xfade, end]; input 1 = the pre-roll [0, xfade]. acrossfade
    fades the body's tail out under the pre-roll's fade-in, so the output's
    final sample lands on src[xfade] — which is exactly the output's first
    sample. Output length = src_len - xfade.

    Run on the ALREADY-normalised file so the crossfade is the last thing that
    touches the samples; a loudnorm limiter acting after the blend could
    reshape the very seam we are trying to make exact.

    `tail_cut` drops that many seconds off the END of the body before the fold.
    It is the second knob in the seam search: it changes WHICH moment of the
    take the pre-roll fades in over, without moving the loop's start point.
    """
    dur = probe_dur(src)
    body = dur - tail_cut - xfade
    p = ac.run([
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-ss", f"{xfade}", "-t", f"{body}", "-i", str(src),
        "-ss", "0", "-t", f"{xfade}", "-i", str(src),
        "-filter_complex",
        # qsin = equal power: keeps level through the blend instead of the
        # ~3 dB mid-dip a linear fade would give on uncorrelated material
        f"[0:a][1:a]acrossfade=d={xfade}:c1=qsin:c2=qsin[a]",
        "-map", "[a]", "-ar", "48000", "-ac", "2", "-c:a", "pcm_s24le", str(dst)])
    if p.returncode != 0:
        raise RuntimeError(f"{dst.name}: {p.stderr[-600:]}")
    return body


def best_loop(src: Path, dst: Path) -> dict:
    """Pick the fold that wraps both click-free AND level-continuous.

    Tries the round-1 baseline (2.0 s fold, no tail cut) first and stops there
    if it already satisfies |head-vs-tail| < 3 dB — so previously-approved
    loops are not silently re-cut. Otherwise it walks the (xfade, tail_cut)
    grid and keeps the smallest level delta that still has a clean seam and
    stays above the 40 s floor.
    """
    tmp = dst.with_suffix(".try.wav")
    tried: list[dict] = []
    best: dict | None = None
    try:
        for x in LOOP_XFADE_GRID:
            for cut in LOOP_CUT_GRID:
                dur = loop_render(src, tmp, x, cut)
                if dur < LOOP_MIN_S:
                    continue
                s = seam(tmp)
                cand = {"xfade_s": x, "tail_cut_s": cut, "duration": round(dur, 2),
                        "level_match_db": s["level_match_db"],
                        "headroom_db": s["headroom_db"], "verdict": s["verdict"]}
                tried.append(cand)
                clean = s["verdict"] == "clean"
                lvl = abs(s["level_match_db"])
                # rank: clean seams first, then smallest level mismatch
                key = (0 if clean else 1, lvl)
                if best is None or key < (0 if best["verdict"] == "clean" else 1,
                                          abs(best["level_match_db"])):
                    best = cand
                if x == LOOP_XFADE_GRID[0] and cut == 0.0 and clean \
                        and lvl < LOOP_MAX_LVL_DB:
                    best = cand
                    raise StopIteration
    except StopIteration:
        pass
    finally:
        tmp.unlink(missing_ok=True)

    if best is None:
        raise RuntimeError(f"{dst.name}: no loop window >= {LOOP_MIN_S}s")
    dur = loop_render(src, dst, best["xfade_s"], best["tail_cut_s"])
    baseline = next((t for t in tried
                     if t["xfade_s"] == LOOP_XFADE and t["tail_cut_s"] == 0.0), None)
    return {"chosen": best, "baseline": baseline, "searched": len(tried),
            "duration": dur,
            "repointed": bool(baseline and baseline != best)}


def main() -> None:
    filters = [a for a in sys.argv[1:] if not a.startswith("-")]
    metas = sorted(RAW.glob("*/*.json"))
    if not metas:
        raise SystemExit("no raw takes — run generate_music.py first")
    if filters:
        metas = [m for m in metas if any(f in m.stem for f in filters)]
        if not metas:
            raise SystemExit(f"no raw takes match {filters}")
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = []

    for mp in metas:
        meta = json.loads(mp.read_text())
        src = mp.parent / meta["file"]
        stem, style, kind = meta["stem"], meta["style"], meta["kind"]
        outdir = OUT / style
        outdir.mkdir(parents=True, exist_ok=True)

        t0, t1 = trim_window(src)
        raw_dur = probe_dur(src)

        # loudness measured over the TRIMMED window, else leading silence
        # drags the integrated reading down and the take comes out hot
        pre = f"atrim=start={t0}:end={t1},asetpts=N/SR/TB"
        plan = ac.master_chain(src, pre_filter=pre)
        # master_chain's chain already contains the atrim; render from 0
        chain = plan["chain"]

        wav = outdir / f"{stem}.wav"
        p = ac.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", str(src), "-map", "0:a:0", "-vn", "-af", chain,
                    "-ar", "48000", "-ac", "2", "-c:a", "pcm_s24le", str(wav)])
        if p.returncode != 0:
            raise RuntimeError(f"{stem}: {p.stderr[-600:]}")

        entry = {
            "stem": stem, "style": style, "kind": kind,
            "round": meta.get("round", 1),
            "model": meta["model"], "version": meta["version"],
            "seed": meta["seed"], "prompt": meta["prompt"],
            "predict_time": meta.get("predict_time"),
            "prediction_id": meta.get("prediction_id"),
            "raw_file": str(src.relative_to(ROOT)),
            "raw_duration": round(raw_dur, 2),
            "trim": [t0, t1],
            "trimmed_s": round(raw_dur - (t1 - t0), 2),
        }

        if kind == "ambient_loop":
            looped = outdir / f"{stem}_loop.wav"
            sr = best_loop(wav, looped)
            entry["loop"] = {
                "file": str(looped.relative_to(ROOT)),
                "xfade_s": sr["chosen"]["xfade_s"],
                "tail_cut_s": sr["chosen"]["tail_cut_s"],
                "duration": round(sr["duration"], 2),
                "windows_tried": sr["searched"],
                "repointed": sr["repointed"],
                "baseline": sr["baseline"],    # what the round-1 fold would give
                "seam_before": seam(wav),      # straight trim, no fold-back
                "seam_after": seam(looped),    # after the chosen crossfade
            }
            final = looped
        else:
            final = wav

        m = ac.measure(final)
        entry["duration"] = round(probe_dur(final), 2)
        entry["LUFS"] = m.get("I")
        entry["dBTP"] = m.get("TP")
        entry["LRA"] = m.get("LRA")
        entry.update(spectral(final))
        entry.update(structure(final))

        prev = outdir / f"{stem}.m4a"
        p = ac.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                    "-i", str(final), "-vn", "-map", "0:a:0",
                    "-c:a", "aac", "-b:a", "192k", str(prev)])
        if p.returncode != 0:
            raise RuntimeError(f"{stem} preview: {p.stderr[-600:]}")

        entry["files"] = {"master_wav": str(final.relative_to(ROOT)),
                          "preview_m4a": str(prev.relative_to(ROOT))}
        manifest.append(entry)
        print(f"  {stem:<32} {entry['duration']:6.2f}s  {entry['LUFS']!s:>6} LUFS  "
              f"{entry['dBTP']!s:>5} dBTP  trimmed {entry['trimmed_s']:.2f}s"
              + (f"  seam {entry['loop']['seam_after']['verdict']}"
                 f" lvl {entry['loop']['seam_after']['level_match_db']:+.1f}dB"
                 + ("  RE-POINTED" if entry["loop"]["repointed"] else "")
                 if kind == "ambient_loop" else ""))

    man_p = OUT / "manifest.json"
    if filters and man_p.exists():
        # Merge: keep every entry the filter did not touch, in its original
        # order, so a partial re-run never silently shrinks the manifest that
        # ship_music.py and music_licenses_block.py read.
        fresh = {e["stem"]: e for e in manifest}
        merged = [fresh.pop(e["stem"], e) for e in json.loads(man_p.read_text())]
        merged += [e for e in manifest if e["stem"] in fresh]
        manifest = merged
    man_p.write_text(json.dumps(manifest, indent=2))
    print(f"\nwrote {man_p}  ({len(manifest)} candidates)")


if __name__ == "__main__":
    main()
