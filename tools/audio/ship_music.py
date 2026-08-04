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
SIZE_BUDGET_MB = 65.0

# canonical ship name -> source stem in gen_music/manifest.json.
# A loop's source is its `_loop` edit, not the straight master; SHIP resolves
# that from the manifest `kind`, so the stem here is always the take name.
#
# Contexts are the seven the game actually distinguishes. Two shipped files
# are deliberately reused across playlists (see MusicDirector) rather than
# shipped twice under two names — the duplicate bytes are not worth the
# tidier table.
SHIP: dict[str, list[tuple[str, str]]] = {
    # ROUND 3 RESTYLE. The three round-2 cinematic menu themes are retired from
    # the bundle in favour of two grand synth-lead anthems; they stay in
    # gen_music/ for the user's listening pass. Two, not three, is what the
    # brief asked for — the title screen is the shortest-dwell context in the
    # game and a third take mostly buys bundle bytes.
    "menu": [
        ("music_menu_theme_a", "menu_grand_r3_piano"),
        ("music_menu_theme_b", "menu_grand_r3_soar"),
    ],
    # The five ambient LOOPS are untouched — they were already the mellow,
    # unobtrusive half of this context and the user asked to keep them. What
    # changed is the mid-track set: the four round-2 `bed_*` entries were the
    # same 165-175 s cinematic cues as the menu themes, which is too eventful
    # for the screen a player stares at longest. They are replaced by three
    # dark downtempo pieces at 60-75 BPM.
    "dashboard": [
        ("music_dashboard_loop_a", "ambient_downtempo_take1"),     # approved r1
        ("music_dashboard_loop_b", "ambient_lofi_take1"),          # approved r1
        ("music_dashboard_loop_c", "ambient_downtempo_r2_take2"),
        ("music_dashboard_loop_d", "ambient_downtempo_r2_take3"),
        ("music_dashboard_loop_e", "ambient_lofi_r2_take2"),
        ("music_dashboard_bed_a", "dashboard_dark_r3_ember"),
        ("music_dashboard_bed_b", "dashboard_dark_r3_late"),
        ("music_dashboard_bed_c", "dashboard_dark_r3_slowpulse"),
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


def extra_keep() -> set[str]:
    """Files in DEST that another shipper owns and this one must not retire."""
    other = ROOT / "shipped_nfl_theme.json"
    if not other.exists():
        return set()
    return {f"{s['name']}.m4a" for s in json.loads(other.read_text())}


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

    # Retire whatever the SHIP table no longer names. Without this the bundle
    # only ever grows: a replaced track keeps its old file sitting in
    # Resources/, counted against the size budget, invisible to this report,
    # and — because Resources/ is a PBXFileSystemSynchronizedRootGroup — still
    # copied into the app. The gen_music/ masters are the archive; the bundle
    # is not.
    # ...but this script is no longer the only one writing to DEST. The
    # NFL-broadcast rounds ship through ship_nfl_theme.py, whose takes are not
    # in gen_music/manifest.json and so can never appear in SHIP above. Without
    # this keep-list the next run here would silently delete them and the menu
    # and dashboard playlists in MusicDirector would start logging missing
    # tracks. Each shipper owns its own set; neither retires the other's.
    keep = {f"{name}.m4a" for rows in SHIP.values() for name, _ in rows}
    keep |= extra_keep()
    retired = sorted(p for p in DEST.glob("*.m4a") if p.name not in keep)
    for p in retired:
        print(f"  retired      {p.name:<26} {p.stat().st_size/1e6:5.2f} MB "
              f"-> gen_music/ only")
        if not dry:
            p.unlink()

    mb = total_bytes / 1e6
    print(f"\n{len(shipped)} files, {sum(s['duration'] for s in shipped)/60:.1f} min, "
          f"{mb:.1f} MB  (budget {SIZE_BUDGET_MB} MB)"
          + (f", {len(retired)} retired" if retired else ""))
    if mb > SIZE_BUDGET_MB:
        print(f"  !! OVER BUDGET by {mb - SIZE_BUDGET_MB:.1f} MB")
    if not dry:
        (ROOT / "shipped_music.json").write_text(json.dumps(shipped, indent=2))
        print(f"wrote {ROOT/'shipped_music.json'}")


if __name__ == "__main__":
    main()
