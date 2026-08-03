#!/usr/bin/env python3
"""Stage 3 for music: mastered candidates -> the app bundle.

`post_music.py` leaves 24-bit WAV masters in gen_music/. Those are archive
format — ~9 MB per minute, which would be most of an app download for one
menu theme. This script encodes the SHIP set to AAC and writes it to
dynasty/dynasty/Resources/Audio/Music/ under canonical, context-first names.

Why AAC 160 kbps and not the ship-format WAV the SFX use:
  - the SFX are one-shots measured in hundreds of milliseconds; music is
    measured in minutes, so the 8-9x saving is the difference between a 60 MB
    music budget and a 500 MB one
  - AVAudioPlayer decodes m4a natively on iOS with hardware assist, so a
    long track costs no more CPU than a wav
  - the ACE-Step source is *already* a 320 kbps MP3 (the model returns no
    lossless option), so a lossless ship format would preserve nothing that
    was not already lost upstream. Stable Audio Open does return WAV, but its
    files are the short ambient loops where the bitrate matters least.

Naming is `music_<context>_<slot>.m4a`. The context is the first thing in the
name because that is how MusicDirector.swift groups them, and a file whose
name does not say which playlist it belongs to is a file that silently rots
out of that playlist.

Usage:  python3 ship_music.py [--dry-run]
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import audio_common as ac

ROOT = Path(__file__).resolve().parent
GEN = ROOT / "gen_music"
DEST = ROOT.parent.parent / "dynasty" / "dynasty" / "Resources" / "Audio" / "Music"

BITRATE = "160k"
SIZE_BUDGET_MB = 60.0

# canonical ship name -> source stem in gen_music/manifest.json.
# A loop's source is its `_loop` edit, not the straight master; SHIP resolves
# that from the manifest `kind`, so the stem here is always the take name.
#
# Contexts are the seven the game actually distinguishes. Two shipped files
# are deliberately reused across playlists (see MusicDirector) rather than
# shipped twice under two names — the duplicate bytes are not worth the
# tidier table.
SHIP: dict[str, list[tuple[str, str]]] = {
    "menu": [
        ("music_menu_theme_a", "orchestral_cinematic_take1"),      # approved r1
        ("music_menu_theme_b", "orchestral_cinematic_take2"),      # approved r1
        ("music_menu_theme_c", "menu_theme_r2_take1"),
    ],
    "dashboard": [
        ("music_dashboard_loop_a", "ambient_downtempo_take1"),     # approved r1
        ("music_dashboard_loop_b", "ambient_lofi_take1"),          # approved r1
        ("music_dashboard_loop_c", "ambient_downtempo_r2_take2"),
        ("music_dashboard_loop_d", "ambient_downtempo_r2_take3"),
        ("music_dashboard_loop_e", "ambient_lofi_r2_take2"),
        ("music_dashboard_bed_a", "orchestral_cinematic_r2_strings"),
        ("music_dashboard_bed_b", "orchestral_cinematic_r2_noble"),
        ("music_dashboard_bed_c", "dark_hybrid_r2_slow"),
        ("music_dashboard_bed_d", "dark_hybrid_r2_atmos"),
    ],
    "draft": [
        ("music_draft_a", "cue_draft_room_take1"),
        ("music_draft_b", "cue_draft_room_take2"),
        ("music_draft_c", "cue_draft_room_take3"),
    ],
    "gameday": [
        ("music_gameday_a", "dark_hybrid_take1"),                  # approved r1
        ("music_gameday_b", "dark_hybrid_take2"),                  # approved r1
        ("music_gameday_c", "dark_hybrid_r2_aggro"),
        ("music_gameday_d", "dark_hybrid_r2_drive"),
        ("music_gameday_e", "gameday_build_take1"),
    ],
    # Three, not four. Shipping all 28 candidates came to 62.9 MB against a
    # 60 MB budget, and the brief's rule is to trim track count before quality.
    # Playoffs was the one context carrying more than it was speced for (the
    # brief asked for 2-3 darker/tenser cinematic cues), so
    # `orchestral_cinematic_r2_percussive` stays a candidate in gen_music/
    # instead of shipping — it is the swap-in if one of these three is rejected.
    "playoffs": [
        ("music_playoffs_a", "orchestral_cinematic_r2_dark"),
        ("music_playoffs_b", "dark_hybrid_r2_crossover"),
        ("music_playoffs_c", "playoffs_dark_take1"),
    ],
    "championship": [
        ("music_championship_a", "cue_championship_take1"),
        ("music_championship_b", "orchestral_cinematic_r2_brass"),
    ],
    "offseason": [
        ("music_offseason_loop_a", "ambient_lofi_r2_take3"),
        ("music_offseason_loop_b", "ambient_downtempo_r2_take4"),
    ],
}


def probe_dur(p: Path) -> float:
    return float(subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", str(p)], capture_output=True, text=True).stdout.strip())


def main() -> None:
    dry = "--dry-run" in sys.argv
    man = {m["stem"]: m for m in json.loads((GEN / "manifest.json").read_text())}

    missing = [stem for rows in SHIP.values() for _, stem in rows if stem not in man]
    if missing:
        raise SystemExit("missing from manifest: " + ", ".join(missing))

    if not dry:
        DEST.mkdir(parents=True, exist_ok=True)

    shipped: list[dict] = []
    total_bytes = 0
    for context, rows in SHIP.items():
        for name, stem in rows:
            m = man[stem]
            src = ROOT / m["files"]["master_wav"]
            dst = DEST / f"{name}.m4a"
            if not dry:
                p = ac.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                            "-i", str(src), "-map", "0:a:0", "-vn",
                            "-c:a", "aac", "-b:a", BITRATE,
                            "-ar", "48000", "-ac", "2",
                            "-movflags", "+faststart", str(dst)])
                if p.returncode != 0:
                    raise RuntimeError(f"{name}: {p.stderr[-600:]}")
                size = dst.stat().st_size
                dur = probe_dur(dst)
                meas = ac.measure(dst)
            else:
                size, dur, meas = 0, m["duration"], {}
            total_bytes += size
            shipped.append({
                "context": context, "name": name, "source_stem": stem,
                "round": m.get("round", 1), "kind": m["kind"],
                "model": m["model"], "seed": m["seed"], "prompt": m["prompt"],
                "duration": round(dur, 2), "bytes": size,
                "LUFS": meas.get("I"), "dBTP": meas.get("TP"),
                "loop": m.get("loop", {}).get("seam_after", {}).get("level_match_db")
                        if m["kind"] == "ambient_loop" else None,
            })
            print(f"  {context:<13} {name:<26} {dur:6.1f}s  {size/1e6:5.2f} MB  "
                  f"{meas.get('I')} LUFS")

    mb = total_bytes / 1e6
    print(f"\n{len(shipped)} files, {sum(s['duration'] for s in shipped)/60:.1f} min, "
          f"{mb:.1f} MB  (budget {SIZE_BUDGET_MB} MB)")
    if mb > SIZE_BUDGET_MB:
        print(f"  !! OVER BUDGET by {mb - SIZE_BUDGET_MB:.1f} MB")
    if not dry:
        (ROOT / "shipped_music.json").write_text(json.dumps(shipped, indent=2))
        print(f"wrote {ROOT/'shipped_music.json'}")


if __name__ == "__main__":
    main()
