#!/usr/bin/env python3
"""Ship the approved sound set into the app bundle.

Stage 3 of the audio pipeline. Reads the two approval lists
(`selections_round1.tsv` = processed Sonniss crowd, `selections_round2.tsv` =
Stable Audio Open generations) and renders every cue to its canonical
`dynasty/dynasty/Resources/Audio/<name>.wav`, trimmed, faded and format-matched
to what `AudioDirector` loads with `AVAudioPlayer(contentsOf:)`.

Rerunnable: it is the ONLY thing that writes Resources/Audio — no manual ffmpeg
one-offs. Delete a file and re-run to get it back bit-identical.

Format policy (25 MB budget for the whole shipped set)
-----------------------------------------------------
Everything is 16-bit PCM WAV at 48 kHz. `AVAudioPlayer` has no format
assumptions (see `AudioDirector.assetURL` / `preload`), so sample rate and
channel count are free to choose per cue; the budget is what constrains us:

* one-shot SFX  -> MONO. Point-source transients (impacts, whistle, voice).
  Stereo buys nothing on a 0.3 s thud and doubles the file.
* crowd reactions -> STEREO. The cheer/boo/gasp/chant swells are the headline
  feature; the width is the whole point of using real stadium recordings.
* crowd bed      -> MONO. It is by far the biggest file (80 s) and plays at
  15-60 % of master under everything else, where centre-placement is
  inaudible. Trading its width for 7.7 MB is what lets the reactions stay
  stereo and the loop stay long enough not to feel like a loop.

Trim policy
-----------
Windows are explicit, not auto-detected: every one was read off an RMS
envelope of the source (0.1 s hop for one-shots, 0.5-2 s for crowd) so the
result is deterministic and reviewable. Fades are asymmetric on purpose —
a 0.3 s fade-IN would destroy an impact transient, so one-shots get a 5 ms
de-click in and a short decay out.

The bed is a crossfade loop: `acrossfade` blends the tail of the body back
into the PRE-ROLL that precedes the window start, so the last sample of the
output continues into the first one and `numberOfLoops = -1` is seamless.

Usage:
    python3 tools/audio/ship_audio.py            # render + verify
    python3 tools/audio/ship_audio.py --verify   # verify only, no writes
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass, field

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
DEST = os.path.join(REPO, "dynasty", "dynasty", "Resources", "Audio")

SAMPLE_RATE = 48000
BUDGET_MB = 25.0

# The retro procedural cues from `tools/asset-pipeline/generate_audio.sh`.
# Three survive the recorded pass and stay in the bundle:
#   snap       - the C->QB tick has no recorded equivalent in the approved set
#   td_horn    - ditto the stadium air horn
#   crowd_loop - the bed fallback in AudioDirector.preload(); cheap insurance
#                against a checkout where ship_audio.py has not been run,
#                where the alternative is a match with no crowd at all.
LEGACY_KEEP = {"snap.wav", "td_horn.wav", "crowd_loop.wav"}
# Fully superseded by recorded takes — deleted so they stop costing bundle
# space and stop muddying the licence ledger.
LEGACY_RETIRED = {
    "catch_pop.wav", "hit_big.wav", "hit_light.wav",
    "kick_thump.wav", "whistle.wav", "crowd_swell.wav",
}


@dataclass
class Cue:
    """One shipped file: a window out of one approved source."""
    out: str                    # canonical name, no extension
    src: str                    # path relative to tools/audio/
    start: float                # window start in the source, seconds
    dur: float                  # window length, seconds
    fade_in: float = 0.005
    fade_out: float = 0.06
    stereo: bool = False
    # Bed only: seconds of crossfade folded back onto the head so the file
    # loops seamlessly. Needs `start >= loop_xfade` worth of pre-roll.
    loop_xfade: float = 0.0
    note: str = ""


# --------------------------------------------------------------------------
# The set. Order here is the order of the report table.
# --------------------------------------------------------------------------

# One-shot SFX — Stable Audio Open takes. Every one is a transient at t=0
# (verified on a 0.1 s RMS envelope), so the window is "from the top, until
# the decay hits the room floor".
SFX: list[Cue] = [
    Cue("sfx_catch_1", "gen/catch/catch_take2_v2.wav", 0.00, 0.35, fade_out=0.10),
    Cue("sfx_catch_2", "gen/catch/catch_take3.wav", 0.00, 0.40, fade_out=0.12),
    Cue("sfx_catch_3", "gen/catch/catch_take4.wav", 0.00, 0.30, fade_out=0.10),
    Cue("sfx_catch_4", "gen/catch/catch_take6.wav", 0.00, 0.35, fade_out=0.10),

    Cue("sfx_kick_place_1", "gen/kick_place/kick_place_take2.wav", 0.00, 0.45, fade_out=0.14),
    # take3 is one boot followed by 1.5 s of room tone — keep the boot.
    Cue("sfx_kick_place_2", "gen/kick_place/kick_place_take3.wav", 0.00, 0.40, fade_out=0.12),
    Cue("sfx_kick_place_3", "gen/kick_place/kick_place_take6.wav", 0.00, 0.45, fade_out=0.14),

    Cue("sfx_kick_punt_1", "gen/kick_punt/kick_punt_take1.wav", 0.00, 0.45, fade_out=0.14),
    Cue("sfx_kick_punt_2", "gen/kick_punt/kick_punt_take3.wav", 0.00, 0.35, fade_out=0.10),

    # The whoosh peaks 0.1 s in — start at 0 so the air build-up survives.
    Cue("sfx_throw_1", "gen/throw_whoosh/throw_whoosh_take4.wav", 0.00, 0.40, fade_out=0.14),
    Cue("sfx_throw_2", "gen/throw_whoosh/throw_whoosh_take6.wav", 0.00, 0.30, fade_out=0.10),

    # take1 has a SECOND hit at 1.70 s; the window drops it so the cue is one
    # clean pop. take3's 0.0 + 0.3 pair is a single pad-then-ground tackle.
    Cue("sfx_tackle_1", "gen/tackle_impact/tackle_impact_take1.wav", 0.00, 0.45, fade_out=0.14),
    Cue("sfx_tackle_2", "gen/tackle_impact/tackle_impact_take3.wav", 0.00, 0.60, fade_out=0.16),

    Cue("sfx_whistle_1", "gen/whistle/whistle_take5.wav", 0.00, 0.95, fade_in=0.008, fade_out=0.12),
    Cue("sfx_cadence_1", "gen/shouts/shouts_cadence1.wav", 0.00, 3.05, fade_in=0.010, fade_out=0.18),
    Cue("sfx_grunt_1", "gen/shouts/shouts_grunt1.wav", 0.00, 0.40, fade_out=0.12),
    Cue("sfx_grunt_2", "gen/shouts/shouts_grunt3.wav", 0.00, 0.30, fade_out=0.10),
]

# Crowd reactions — stereo, trimmed to their best arc. Sonniss captures get a
# hand-picked window out of a long recording; the Stable Audio takes get their
# rise-peak-decay with the dead air either side removed.
CROWD: list[Cue] = [
    # cheer_1 -> _3 run smallest -> biggest; CrowdReactor picks by magnitude.
    Cue("crowd_cheer_1", "approved/crowd_cheer/crowd_cheer_forum_swell.wav",
        0.00, 5.60, fade_in=0.12, fade_out=0.90, stereo=True,
        note="applause bed with a natural decay; the S swell"),
    Cue("crowd_cheer_2", "approved/crowd_cheer/crowd_cheer_rosebowl_surge.wav",
        0.45, 7.10, fade_in=0.20, fade_out=1.00, stereo=True,
        note="rise at 0.5, second peak at 6.75 — the M swell"),
    Cue("crowd_cheer_3", "approved/crowd_cheer/crowd_cheer_rosebowl_encore.wav",
        154.20, 5.80, fade_in=0.25, fade_out=0.60, stereo=True,
        note="the loudest arc in 160 s: -24 -> -15.7 dB with a real decay"),

    Cue("crowd_boo_1", "approved/crowd_boo/crowd_boo_stadium.wav",
        11.60, 6.20, fade_in=0.25, fade_out=1.20, stereo=True,
        note="swell -25 -> -16 -> -25 dB, the cleanest boo in the take"),
    Cue("crowd_boo_2", "gen/crowd_boo_extra/crowd_boo_extra_take1.wav",
        1.20, 5.50, fade_in=0.15, fade_out=1.20, stereo=True),
    Cue("crowd_boo_3", "gen/crowd_boo_extra/crowd_boo_extra_take2.wav",
        0.30, 5.70, fade_in=0.15, fade_out=1.20, stereo=True),
    Cue("crowd_boo_4", "gen/crowd_boo_extra/crowd_boo_extra_take3.wav",
        0.70, 5.80, fade_in=0.15, fade_out=1.20, stereo=True),

    Cue("crowd_gasp_1", "approved/crowd_gasp/crowd_gasp_reaction.wav",
        0.20, 4.20, fade_in=0.10, fade_out=1.00, stereo=True,
        note="20-person reaction; short and dry, sits under a big hit"),
    Cue("crowd_gasp_2", "gen/crowd_gasp_extra/crowd_gasp_extra_take1.wav",
        0.25, 2.80, fade_in=0.06, fade_out=0.70, stereo=True),
    Cue("crowd_gasp_3", "gen/crowd_gasp_extra/crowd_gasp_extra_take4.wav",
        0.40, 3.80, fade_in=0.08, fade_out=0.90, stereo=True),

    # The Sonniss chant runs on a ~4 s cycle (peaks at 3/7/11/15/19 s) — take
    # two whole cycles so the burst does not stop mid-word.
    Cue("crowd_chant_1", "approved/crowd_chant/crowd_chant_stadium.wav",
        8.00, 8.00, fade_in=0.20, fade_out=0.60, stereo=True,
        note="two full chant cycles"),
    Cue("crowd_chant_2", "gen/crowd_chant_extra/crowd_chant_extra_take2.wav",
        1.80, 5.20, fade_in=0.20, fade_out=0.90, stereo=True),
    Cue("crowd_chant_3", "gen/crowd_chant_extra/crowd_chant_extra_take3.wav",
        1.20, 5.00, fade_in=0.20, fade_out=0.90, stereo=True),
]

# The bed. 32-112 s is the flattest 80 s stretch in the 128 s capture (the
# 22-28 s and 112-115 s spikes are somebody shouting near the mic).
BED: list[Cue] = [
    Cue("crowd_bed_talking", "approved/crowd_bed/crowd_bed_talking.wav",
        32.00, 80.00, fade_in=0.0, fade_out=0.0, stereo=False, loop_xfade=3.0,
        note="seamless loop: tail crossfaded into the 29-32 s pre-roll"),
]

ALL: list[Cue] = SFX + CROWD + BED


# --------------------------------------------------------------------------

def run(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(" ".join(cmd) + "\n" + proc.stderr[-3000:] + "\n")
        raise SystemExit(f"ffmpeg failed for: {cmd[-1]}")


def probe(path: str) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=sample_rate,channels,bits_per_raw_sample",
         "-show_entries", "format=duration,size", "-of", "json", path],
        capture_output=True, text=True).stdout
    data = json.loads(out)
    st = data["stream" + "s"][0]
    fm = data["format"]
    return {
        "sample_rate": int(st["sample_rate"]),
        "channels": int(st["channels"]),
        "duration": float(fm["duration"]),
        "size": int(fm["size"]),
    }


def render(cue: Cue) -> None:
    src = os.path.join(HERE, cue.src)
    if not os.path.exists(src):
        raise SystemExit(f"missing source: {src}")
    dst = os.path.join(DEST, cue.out + ".wav")
    channels = "2" if cue.stereo else "1"

    if cue.loop_xfade > 0:
        # Seamless loop. Input 0 = the body [start, start+dur]; input 1 = the
        # PRE-ROLL [start-x, start]. acrossfade fades 0's tail out under 1's
        # fade-in, so the output's final sample lands on source[start] — which
        # is exactly the output's first sample. Output length = dur.
        pre = cue.start - cue.loop_xfade
        if pre < 0:
            raise SystemExit(f"{cue.out}: needs {cue.loop_xfade}s of pre-roll before {cue.start}s")
        run([
            "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
            "-ss", f"{cue.start}", "-t", f"{cue.dur}", "-i", src,
            "-ss", f"{pre}", "-t", f"{cue.loop_xfade}", "-i", src,
            "-filter_complex",
            # qsin = equal power: uncorrelated crowd noise keeps its level
            # through the blend instead of dipping ~3 dB in the middle.
            f"[0:a][1:a]acrossfade=d={cue.loop_xfade}:c1=qsin:c2=qsin[a]",
            "-map", "[a]", "-ac", channels, "-ar", str(SAMPLE_RATE),
            "-c:a", "pcm_s16le", dst,
        ])
        return

    chain = []
    if cue.fade_in > 0:
        chain.append(f"afade=t=in:st=0:d={cue.fade_in}:curve=exp")
    if cue.fade_out > 0:
        chain.append(f"afade=t=out:st={max(0.0, cue.dur - cue.fade_out):.4f}:d={cue.fade_out}")
    run([
        "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
        "-ss", f"{cue.start}", "-t", f"{cue.dur}", "-i", src,
        *(["-af", ",".join(chain)] if chain else []),
        "-ac", channels, "-ar", str(SAMPLE_RATE), "-c:a", "pcm_s16le", dst,
    ])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true", help="probe only, do not render")
    args = ap.parse_args()

    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg not on PATH")
    os.makedirs(DEST, exist_ok=True)

    if not args.verify:
        for cue in ALL:
            render(cue)
        # Retire the procedural cues the recorded set replaced so they do not
        # sit in the bundle costing space and confusing the licence ledger.
        for name in LEGACY_RETIRED:
            stale = os.path.join(DEST, name)
            if os.path.exists(stale):
                os.remove(stale)

    total = 0
    rows = []
    bad = []
    for cue in ALL:
        path = os.path.join(DEST, cue.out + ".wav")
        if not os.path.exists(path):
            bad.append(f"{cue.out}: NOT RENDERED")
            continue
        info = probe(path)
        total += info["size"]
        rows.append((cue.out, info["duration"], info["channels"],
                     info["sample_rate"], info["size"]))
        if info["duration"] <= 0.05:
            bad.append(f"{cue.out}: duration {info['duration']}s")
        if info["sample_rate"] != SAMPLE_RATE:
            bad.append(f"{cue.out}: sample rate {info['sample_rate']}")
        if abs(info["duration"] - cue.dur) > 0.06:
            bad.append(f"{cue.out}: {info['duration']:.2f}s, expected {cue.dur:.2f}s")

    # Anything else already in the folder counts against the same budget.
    extra = 0
    shipped_names = {c.out for c in ALL}
    for name in sorted(os.listdir(DEST)):
        if not name.endswith(".wav") or name[:-4] in shipped_names:
            continue
        path = os.path.join(DEST, name)
        info = probe(path)
        extra += info["size"]
        rows.append((name[:-4] + "  (legacy)", info["duration"],
                     info["channels"], info["sample_rate"], info["size"]))
        if name not in LEGACY_KEEP:
            bad.append(f"{name}: unexpected leftover in Resources/Audio")

    print(f"{'file':<24} {'dur':>7} {'ch':>3} {'kHz':>5} {'KB':>8}")
    print("-" * 52)
    for name, dur, ch, sr, size in rows:
        print(f"{name:<24} {dur:7.2f} {ch:>3} {sr/1000:5.1f} {size/1024:8.1f}")
    grand = total + extra
    print("-" * 52)
    print(f"{'TOTAL shipped':<24} {'':>7} {'':>3} {'':>5} {grand/1024:8.1f} KB"
          f"   =  {grand/1024/1024:.2f} MB   (budget {BUDGET_MB:.0f} MB)")

    if bad:
        print("\nPROBLEMS:")
        for b in bad:
            print("  " + b)
        return 1
    if grand / 1024 / 1024 > BUDGET_MB:
        print(f"\nOVER BUDGET by {grand/1024/1024 - BUDGET_MB:.2f} MB")
        return 1
    print("\nOK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
