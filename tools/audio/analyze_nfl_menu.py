#!/usr/bin/env python3
"""Listen-check the gen_nfl_menu round without shipping anything.

Reuses post_music.py's measurement helpers (same RMS envelope, same trim
window definition) so the numbers mean the same thing they mean in the
round-1..3 review pages. Adds the two checks this round specifically needs:

  * SILENCE TRAP — ACE-Step likes to pad the tail (and sometimes the head)
    with digital silence when the requested duration exceeds what it wanted
    to write. A take that is mostly silence is a dud, and a take with a
    silent tail needs a trim point recorded before it can ship.
  * INTRO CLEANLINESS — the menu fades in under a still screen, so a take
    that opens at full blast is worse than one that opens under its own
    average level.

Nothing is written except a JSON report; no audio is modified.
"""

from __future__ import annotations

import json
import re
import statistics
import subprocess
from pathlib import Path

import audio_common as ac
import post_music as pm

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "gen_nfl_menu"


def loudness(p: Path) -> dict:
    """Integrated LUFS + true peak, via one ebur128 pass."""
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(p),
         "-af", "ebur128=peak=true", "-f", "null", "-"],
        capture_output=True, text=True)
    txt = r.stderr
    def grab(label: str):
        m = re.findall(rf"{label}:\s*(-?[\d.]+|-inf)", txt)
        return float(m[-1]) if m and m[-1] != "-inf" else None
    return {"lufs": grab("I"), "lra": grab("LRA"), "peak_dbtp": grab("Peak")}


def silence_spans(p: Path, thresh_db: float = -55.0, min_s: float = 0.8) -> list:
    """Every span quieter than `thresh_db` for at least `min_s`."""
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-nostats", "-i", str(p),
         "-af", f"silencedetect=noise={thresh_db}dB:d={min_s}", "-f", "null", "-"],
        capture_output=True, text=True)
    starts = [float(m) for m in re.findall(r"silence_start:\s*(-?[\d.]+)", r.stderr)]
    ends = [float(m) for m in re.findall(r"silence_end:\s*([\d.]+)", r.stderr)]
    dur = pm.probe_dur(p)
    spans = []
    for i, s in enumerate(starts):
        e = ends[i] if i < len(ends) else dur
        spans.append([round(max(0.0, s), 2), round(e, 2)])
    return spans


def intro(p: Path) -> dict:
    """How loud the first 3 s are relative to the body of the track."""
    env, fs = ac.envelope(p, frame_ms=250)
    if len(env) < 20:
        return {}
    n3 = max(1, int(3.0 / fs))
    head = statistics.mean(env[:n3])
    body = statistics.median(env)
    return {"intro_vs_body_db": round(head - body, 1)}


def main() -> None:
    rows = []
    for lane_dir in sorted(OUT.iterdir()):
        if not lane_dir.is_dir():
            continue
        for meta_p in sorted(lane_dir.glob("*.json")):
            meta = json.loads(meta_p.read_text())
            audio = lane_dir / meta["file"]
            dur = pm.probe_dur(audio)
            t0, t1 = pm.trim_window(audio)
            row = {
                "lane": meta["style"], "stem": meta["stem"],
                "file": str(audio.relative_to(ROOT)),
                "seed": meta["seed"], "requested_s": meta["requested_duration"],
                "actual_s": round(dur, 2),
                "content_s": round(t1 - t0, 2),
                "trim": [t0, t1],
                "head_dead_s": round(t0, 2),
                "tail_dead_s": round(dur - t1, 2),
                "gpu_s": meta.get("predict_time"),
                **pm.structure(audio), **pm.spectral(audio),
                **loudness(audio), **intro(audio),
                "silence_spans": silence_spans(audio),
                "prompt": meta["prompt"],
            }
            rows.append(row)

    rows.sort(key=lambda r: (r["lane"], r["stem"]))
    (OUT / "analysis.json").write_text(json.dumps(rows, indent=2))

    hdr = (f"{'stem':<24}{'act':>7}{'cont':>7}{'head':>6}{'tail':>6}"
           f"{'peak@':>7}{'build':>7}{'arc':>6}{'LUFS':>7}{'intro':>7}{'cent':>7}")
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        print(f"{r['stem']:<24}{r['actual_s']:>7.1f}{r['content_s']:>7.1f}"
              f"{r['head_dead_s']:>6.2f}{r['tail_dead_s']:>6.2f}"
              f"{(r.get('peak_pos') or 0):>7.2f}{(r.get('build_db') or 0):>7.1f}"
              f"{(r.get('arc_db') or 0):>6.1f}{(r.get('lufs') or 0):>7.1f}"
              f"{(r.get('intro_vs_body_db') or 0):>7.1f}"
              f"{(r.get('centroid_hz') or 0):>7d}")
        if r["silence_spans"]:
            print(f"    silence: {r['silence_spans']}")
    print(f"\nwrote {OUT.name}/analysis.json")


if __name__ == "__main__":
    main()
