#!/usr/bin/env python3
"""Do MusicDirector's playlists and the shipped files still agree?

The one failure this catches is silent by construction: `MusicDirector`
deliberately does *not* stall a playlist on a missing file — it logs in DEBUG,
drops the pick and schedules the next one — so a track that has rotted out of
Resources/Audio/Music costs you a gap in the rotation on device and nothing at
all at build time. Two separate shippers now write into that folder
(`ship_music.py`, `ship_nfl_theme.py`), each with its own retire policy, which
is exactly the shape of problem that goes unnoticed for a month.

Checks, in order of how much they would hurt:
  1. every `(file, plays)` entry in every context resolves to a real .m4a
  2. no file is named by two contexts under different spellings, and no two
     ship names differ only by case (the sim is case-insensitive, a device
     bundle is not)
  3. reports files in the folder that no context plays — dead bundle weight,
     not an error
  4. reports the bundle size against the music budget

Parses the Swift by regex on purpose: the alternative is building the app,
which is the thing this is meant to run instead of.

Usage:  python3 verify_playlists.py
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
APP = ROOT.parent.parent / "dynasty" / "dynasty"
SWIFT = APP / "UI" / "Common" / "MusicDirector.swift"
MUSIC = APP / "Resources" / "Audio" / "Music"
BUDGET_MB = 65.0

CASE_RE = re.compile(r"case\s+\.(\w+):")
ENTRY_RE = re.compile(r'\("([A-Za-z0-9_]+)",\s*(\d+)\)')


def playlists(text: str) -> dict[str, list[tuple[str, int]]]:
    """`entries` only — sliced off the computed property, not the whole file.

    Bounded to that one property so `gapRange` and `levelTrim`, which repeat
    the same `case .menu:` labels, cannot leak in.
    """
    start = text.index("var entries:")
    end = text.index("var gapRange:", start)
    body = text[start:end]
    out: dict[str, list[tuple[str, int]]] = {}
    ctx = None
    for line in body.splitlines():
        m = CASE_RE.search(line)
        if m:
            ctx = m.group(1)
            out.setdefault(ctx, [])
        if ctx:
            for f, p in ENTRY_RE.findall(line):
                out[ctx].append((f, int(p)))
    return out


def main() -> int:
    text = SWIFT.read_text()
    lists = playlists(text)
    on_disk = {p.stem: p for p in sorted(MUSIC.glob("*.m4a"))}
    fail = 0

    for ctx, entries in lists.items():
        missing = [f for f, _ in entries if f not in on_disk]
        flag = "MISSING " + ", ".join(missing) if missing else "ok"
        print(f"  {ctx:<13} {len(entries):>2} entries  {flag}")
        fail += len(missing)

    named = {f for e in lists.values() for f, _ in e}
    lower: dict[str, list[str]] = {}
    for n in set(on_disk) | named:
        lower.setdefault(n.lower(), []).append(n)
    clashes = {k: v for k, v in lower.items() if len(v) > 1}
    if clashes:
        fail += len(clashes)
        print(f"\n  CASE COLLISION: {clashes}")

    unplayed = sorted(set(on_disk) - named)
    if unplayed:
        print(f"\n  {len(unplayed)} bundled but never played: {', '.join(unplayed)}")

    mb = sum(p.stat().st_size for p in on_disk.values()) / 1e6
    print(f"\n  {len(on_disk)} files, {mb:.2f} MB"
          + (f"  (over the {BUDGET_MB:.0f} MB budget by {mb - BUDGET_MB:.2f} MB)"
             if mb > BUDGET_MB else f"  (budget {BUDGET_MB:.0f} MB)"))

    print("\nPASS" if not fail else f"\nFAIL — {fail} problem(s)")
    return 1 if fail else 0


if __name__ == "__main__":
    sys.exit(main())
