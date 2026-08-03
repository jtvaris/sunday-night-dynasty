#!/usr/bin/env python3
"""Stage 2.5 for music: is this candidate SHIPPABLE, and does it do its job?

Two questions, deliberately separate.

**Decode sanity** is a defect check and is pass/fail. It asks whether the file
will actually play correctly on a device: does the AAC preview decode
end-to-end without an error, is it the length the master says it is, is there
a hole of silence in the middle, is one stereo channel dead, is it clipped,
does it carry a DC offset. None of this is taste — a file that fails here is
broken regardless of how good the music is, and nobody in this pipeline can
hear it, so it has to be measured.

**Role fit** is a ranking, not a gate, and it only works because the round-3
brief states the structural requirement in so many words. The menu theme is
specified to *build* ("nostalgic triumphant build"), so a late peak and a real
dynamic arc are the brief restated in numbers. The dashboard bed is specified
to stay out of the way ("darker, slower, a bit mellow"), so the same metrics
are inverted: a flat arc and a dark spectral centroid are what "background"
means when you cannot listen.

This is the round-2 lesson applied rather than ignored. Round 2 ranked *style*
by these proxies and got it wrong, because "which of these two epic cues is
better" is not a thing a centroid knows. Round 3 uses them only where the
brief itself asked for a measurable property.

Usage:
    python3 verify_music.py r3_                  # sanity + both role scores
    python3 verify_music.py --role menu r3_      # rank for the menu role only
"""

from __future__ import annotations

import json
import math
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
GEN = ROOT / "gen_music"

# Decode-sanity thresholds.
DUR_TOL_S = 0.20          # m4a vs master; AAC's encoder delay is ~20 ms
SILENCE_DB = -50.0        # what counts as "nothing there"
SILENCE_MIN_S = 2.5       # an interior hole this long is a defect, not a rest
CH_BALANCE_DB = 20.0      # one channel this far under the other is a dead side
DC_MAX = 0.02             # |DC offset| in full-scale units
CLIP_MAX = 8              # flat-topped sample runs tolerated


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def astats(path: Path) -> dict:
    """Per-channel stats from ffmpeg's astats, keyed `<n>.<Field>`."""
    p = run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
             "-map", "0:a:0", "-af", "astats=measure_overall=none",
             "-f", "null", "-"])
    out: dict[str, float] = {}
    ch = 0
    for line in p.stderr.splitlines():
        m = re.match(r"\[Parsed_astats.*\] Channel: (\d+)", line)
        if m:
            ch = int(m.group(1))
            continue
        m = re.match(r"\[Parsed_astats.*\] ([A-Za-z_ ]+?):\s*(-?[\d.inf]+)", line)
        if m:
            try:
                out[f"{ch}.{m.group(1).strip()}"] = float(m.group(2))
            except ValueError:
                pass
    return out


def interior_silence(path: Path, dur: float) -> float:
    """Longest silent window that is NOT the head or the tail, in seconds.

    Lead-in and fade-out silence is normal and already trimmed by post_music;
    a gap in the MIDDLE is a generation artefact — the model dropping out —
    and would read on a menu as the music having crashed.
    """
    p = run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-map", "0:a:0",
             "-af", f"silencedetect=noise={SILENCE_DB}dB:d={SILENCE_MIN_S}",
             "-f", "null", "-"])
    worst = 0.0
    start = None
    for line in p.stderr.splitlines():
        m = re.search(r"silence_start: (-?[\d.]+)", line)
        if m:
            start = float(m.group(1))
        m = re.search(r"silence_end: ([\d.]+) \| silence_duration: ([\d.]+)", line)
        if m and start is not None:
            end, length = float(m.group(1)), float(m.group(2))
            # ignore a window that touches either edge of the file
            if start > 0.5 and end < dur - 0.5:
                worst = max(worst, length)
            start = None
    return round(worst, 2)


def probe_dur(p: Path) -> float:
    return float(run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                      "-of", "csv=p=0", str(p)]).stdout.strip() or 0)


def sanity(entry: dict) -> dict:
    """Decode-level defect check on the shippable (m4a) rendition."""
    master = ROOT / entry["files"]["master_wav"]
    prev = ROOT / entry["files"]["preview_m4a"]
    fails: list[str] = []

    p = run(["ffmpeg", "-v", "error", "-i", str(prev), "-map", "0:a:0",
             "-f", "null", "-"])
    decode_err = p.stderr.strip()
    if p.returncode != 0 or decode_err:
        fails.append(f"decode:{decode_err[:80] or p.returncode}")

    d_prev, d_mast = probe_dur(prev), probe_dur(master)
    if abs(d_prev - d_mast) > DUR_TOL_S:
        fails.append(f"duration {d_prev:.2f}!={d_mast:.2f}")

    hole = interior_silence(master, d_mast)
    if hole:
        fails.append(f"silent hole {hole}s")

    st = astats(master)
    rms = [st.get(f"{c}.RMS level dB") for c in (1, 2)]
    balance = None
    if all(v is not None and math.isfinite(v) for v in rms):
        balance = round(abs(rms[0] - rms[1]), 1)
        if balance > CH_BALANCE_DB:
            fails.append(f"channel balance {balance} dB")
    dc = max(abs(st.get(f"{c}.DC offset", 0.0)) for c in (1, 2))
    if dc > DC_MAX:
        fails.append(f"DC offset {dc:.3f}")
    clips = max(st.get(f"{c}.Flat factor", 0.0) for c in (1, 2))
    if clips > CLIP_MAX:
        fails.append(f"flat factor {clips:.1f}")

    return {"ok": not fails, "fails": fails, "hole_s": hole,
            "balance_db": balance, "dc": round(dc, 4),
            "flat_factor": round(clips, 1),
            "peak_db": round(max(st.get(f"{c}.Peak level dB", -99.0)
                                 for c in (1, 2)), 1)}


def menu_score(e: dict) -> float:
    """Higher = closer to "slow heroic build that peaks late".

    peak_pos  weight 3 — the brief's "build" is literally where the peak is
    build_db  weight 2 — the last third louder than the first
    arc_db    weight 1 — normalised at 12 dB; a flat anthem is not an anthem
    """
    return (3 * e["peak_pos"]
            + 2 * max(0.0, min(1.0, (e["build_db"] + 2) / 8))
            + 1 * max(0.0, min(1.0, e["arc_db"] / 12)))


def dash_score(e: dict) -> float:
    """Higher = closer to "dark, mellow, does not pull focus".

    Everything is inverted from `menu_score` on purpose: the failure mode of a
    dashboard bed is that it is INTERESTING. Centroid is normalised at 4 kHz
    (the brightest thing in the round-3 set) and dominates, because "darker"
    was the user's first word.
    """
    return (3 * max(0.0, 1 - e["centroid_hz"] / 4000)
            + 2 * max(0.0, 1 - abs(e["build_db"]) / 4)
            + 1 * max(0.0, 1 - e["arc_db"] / 15))


def main() -> None:
    args = sys.argv[1:]
    role = None
    if "--role" in args:
        i = args.index("--role")
        role = args[i + 1]
        del args[i:i + 2]
    filters = args or [""]

    man = json.loads((GEN / "manifest.json").read_text())
    picked = [e for e in man if any(f in e["stem"] for f in filters)]
    if not picked:
        raise SystemExit(f"nothing matches {filters}")

    rows = []
    for e in sorted(picked, key=lambda x: x["stem"]):
        s = sanity(e)
        rows.append((e, s))
        print(f"  {e['stem']:<30} {'PASS' if s['ok'] else 'FAIL':<5} "
              f"peak {s['peak_db']:+6.1f} dBFS  bal {str(s['balance_db']):>5} dB  "
              f"dc {s['dc']:.4f}  flat {s['flat_factor']:5.1f}  hole {s['hole_s']}s"
              + ("   " + "; ".join(s["fails"]) if s["fails"] else ""))

    clean = [e for e, s in rows if s["ok"]]
    for name, fn in (("menu", menu_score), ("dashboard", dash_score)):
        if role and role != name:
            continue
        print(f"\n  role fit — {name} (decode-clean candidates only)")
        for e in sorted(clean, key=fn, reverse=True):
            print(f"    {fn(e):5.2f}  {e['stem']:<30} peak@{e['peak_pos']:.2f} "
                  f"build {e['build_db']:+.1f} arc {e['arc_db']:.1f} "
                  f"cent {e['centroid_hz']} Hz")


if __name__ == "__main__":
    main()
