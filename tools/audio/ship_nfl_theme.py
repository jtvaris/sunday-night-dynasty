#!/usr/bin/env python3
"""Stage 3 for the NFL-broadcast rounds: mastered candidates -> the app bundle.

`post_nfl_menu.py` / `post_nfl_dash.py` leave 24-bit WAV masters in
gen_nfl_menu/ and gen_nfl_dash/. Those are archive format (~9 MB per minute).
This encodes the SHIP set to AAC and writes it into
dynasty/dynasty/Resources/Audio/Music/, exactly the way `ship_music.py` does
for rounds 1-3 — same 160 kbps / 48 kHz / stereo / +faststart, for the same
reasons documented there, because these files join that rotation and a
bitrate mismatch inside one playlist is an audible inconsistency, not a saving.

WHY THIS IS NOT JUST A NEW BLOCK IN ship_music.py. That script owns a RETIRE
step: anything in Resources/Audio/Music not named by its SHIP table is deleted,
which is what stops a replaced track from rotting in the bundle. Its table is
resolved against gen_music/manifest.json, and these takes are not in that
manifest — they come from two different rounds with their own metrics.json.
Rather than fake manifest rows, the two shippers stay separate and
`ship_music.py` reads this script's output as a keep-list (see EXTRA_KEEP
there), so neither one can silently delete the other's files.

Names are the source stems verbatim. Round 1-3 used `music_<context>_<slot>`;
these keep `nfl_<context>_<character>` so a file in Resources/ is traceable to
one row of one round's metrics.json — the slot letters in the older set are
exactly what made `shipped_music.json` necessary to answer "which take is
music_gameday_d".

Usage:  python3 ship_nfl_theme.py [--dry-run]
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import audio_common as ac

ROOT = Path(__file__).resolve().parent
DEST = ROOT.parent.parent / "dynasty" / "dynasty" / "Resources" / "Audio" / "Music"

BITRATE = "160k"

# context -> source stems, in score order. Picked by the round scores in
# gen_nfl_*/metrics.json; the reason each one is here is carried in that file
# and reprinted on review_nfl_theme.html, so this table stays a list of names.
#
# MENU took the top 3 of 8 and landed on three different lanes by itself
# (orchestral 5.0, hybrid 5.0, march 3.5) — no tie-break needed.
# DASHBOARD took the only three takes that scored a clean 5.0. Two of them are
# the same `ambient` lane; the tie-break toward variety never triggered because
# nothing else reached 5.0. `nfl_dash_fanfare_a` (4.0) is the swap-in if the
# ear wants more of the brass DNA on that screen.
SHIP: dict[str, list[tuple[str, Path]]] = {}

ROUNDS = {"menu": ROOT / "gen_nfl_menu" / "metrics.json",
          "dashboard": ROOT / "gen_nfl_dash" / "metrics.json"}

PICKS = {
    "menu": ["nfl_menu_orch_fanfare", "nfl_menu_hybrid_gleam", "nfl_menu_march_drive"],
    "dashboard": ["nfl_dash_ambient_a", "nfl_dash_ambient_b", "nfl_dash_strings_a"],
}


def probe_dur(p: Path) -> float:
    return float(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", str(p)], capture_output=True, text=True).stdout.strip())


def main() -> None:
    dry = "--dry-run" in sys.argv

    takes: dict[str, dict] = {}
    for ctx, path in ROUNDS.items():
        if not path.exists():
            raise SystemExit(f"missing {path} — run the round's post_*.py first")
        for t in json.loads(path.read_text())["takes"]:
            t["_round_file"] = path
            takes[t["stem"]] = t

    missing = [s for names in PICKS.values() for s in names if s not in takes]
    if missing:
        raise SystemExit("not in any round's metrics.json: " + ", ".join(missing))

    if not dry:
        DEST.mkdir(parents=True, exist_ok=True)

    shipped: list[dict] = []
    total = 0
    for ctx, names in PICKS.items():
        for stem in names:
            t = takes[stem]
            wav = t["files"]["master_wav"]
            src = ROOT / wav if "/" in wav else t["_round_file"].parent / wav
            if not src.exists():
                raise SystemExit(f"{stem}: master missing at {src}")
            dst = DEST / f"{stem}.m4a"
            if not dry:
                p = ac.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                            "-i", str(src), "-map", "0:a:0", "-vn",
                            "-c:a", "aac", "-b:a", BITRATE,
                            "-ar", "48000", "-ac", "2",
                            "-movflags", "+faststart", str(dst)])
                if p.returncode != 0:
                    raise RuntimeError(f"{stem}: {p.stderr[-600:]}")
                size, dur, meas = dst.stat().st_size, probe_dur(dst), ac.measure(dst)
            else:
                size, dur, meas = 0, t["duration"], {}
            total += size
            shipped.append({
                "context": ctx, "name": stem, "source_stem": stem,
                "lane": t["lane"], "round": t.get("round"), "model": t["model"],
                "seed": t["seed"], "prompt": t["prompt"],
                "score": t.get("score"), "reasons": t.get("reasons"),
                "duration": round(dur, 2), "bytes": size,
                "LUFS": meas.get("I"), "dBTP": meas.get("TP"),
            })
            print(f"  {ctx:<10} {stem:<26} {dur:6.1f}s  {size/1e6:5.2f} MB  "
                  f"{meas.get('I')} LUFS  score {t.get('score')}")

    other = sorted(p for p in DEST.glob("*.m4a")
                   if p.name not in {f"{s['name']}.m4a" for s in shipped})
    other_mb = sum(p.stat().st_size for p in other) / 1e6
    print(f"\n{len(shipped)} new files, {total/1e6:.2f} MB")
    print(f"{len(other)} pre-existing files, {other_mb:.2f} MB")
    print(f"folder total {(total/1e6) + other_mb:.2f} MB")

    if not dry:
        (ROOT / "shipped_nfl_theme.json").write_text(json.dumps(shipped, indent=2))
        print(f"wrote {ROOT/'shipped_nfl_theme.json'}")


if __name__ == "__main__":
    main()
