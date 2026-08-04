#!/usr/bin/env python3
"""NFL-broadcast menu round — 8 heroic anthem candidates for the main menu.

Thin driver on top of generate_music.py: same model (`lucataco/ace-step`,
Apache-2.0 upstream, no revenue cap), same submit/poll/download plumbing
(`generate_music._run`), same `lyrics="[instrumental]"` marker. The only two
differences are the output directory (`gen_nfl_menu/`, so this round does not
mix into the round-1..3 `gen_music_raw/` tree) and the prompt set.

WHY A NEW ROUND. The shipped menu pair is `music_menu_theme_a/b` — round-3
"menu_grand": slow, hymn-like synth-lead anthems. That is one flavour of sports
grandeur. This round goes after the other one: the brass-and-drumline network
broadcast open — fanfare, snare march, timpani, Americana. Style words only;
no existing theme is named, quoted, or reproduced.

BRIEF (all 8): heroic brass fanfare, cinematic orchestra, military snare rolls,
timpani, stadium-sized, prime-time television energy, ~90-120 BPM, 60-120 s,
clean intro because the menu fades the track in under a still screen.

SPREAD (two takes per lane so a lane is never judged on one roll of the dice):
    pure orchestral      classic brass + strings + percussion, no synths
    brass + synth hybrid  same fanfare over a modern synth-bass floor
    slow burn            quiet statement first, fanfare arrives late
    uptempo march        drumline forward, quickest pulse of the set

Duration is also a ship budget: ~20 KB/s at AAC 160 kbps against a 60 MB music
budget, which is why nothing here sits at the 120 s ceiling of the brief.

Usage:
    REPLICATE_API_TOKEN=... python3 generate_nfl_menu.py            # generate
    python3 generate_nfl_menu.py --tsv-only                         # rewrite tsv
"""

from __future__ import annotations

import concurrent.futures as cf
import sys
from pathlib import Path

import generate_music as gm
from generate_music import T

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "gen_nfl_menu"          # gitignored via `gen_nfl_*/`
TSV = ROOT / "selections_nfl_menu.tsv"

# (lane, stem, tags, seed, duration_s)
CANDIDATES: list[tuple] = [
    # --- pure orchestral: no synthesizers anywhere in the tag list ----------
    ("orchestral", "nfl_menu_orch_fanfare", T(
        "epic american football broadcast theme", "heroic trumpet fanfare",
        "full orchestral brass section", "military snare drum march",
        "rolling timpani", "soaring string melody", "cymbal swells",
        "triumphant and majestic", "americana grandeur", "stadium sized",
        "prime time television opening", "clean quiet intro then full orchestra",
        "no synthesizers", "instrumental", "no vocals", "104 BPM", "B flat major"),
     991101, 104),
    ("orchestral", "nfl_menu_orch_noble", T(
        "cinematic orchestral sports anthem", "noble french horn theme",
        "answering trumpet fanfare", "snare drum roll", "timpani heartbeat",
        "warm string ensemble", "grand and dignified", "national broadcast open",
        "wide concert hall reverb", "clean single-note intro",
        "orchestra only", "instrumental", "no vocals", "96 BPM", "E flat major"),
     991102, 112),

    # --- brass + synth hybrid ---------------------------------------------
    ("hybrid", "nfl_menu_hybrid_pulse", T(
        "hybrid orchestral electronic sports theme", "heroic brass fanfare",
        "driving analog synth bass pulse", "military snare march",
        "cinematic percussion", "staccato strings", "timpani hits",
        "modern prime time broadcast package", "confident and powerful",
        "clean intro that builds fast", "instrumental", "no vocals",
        "112 BPM", "D minor"),
     991103, 100),
    ("hybrid", "nfl_menu_hybrid_gleam", T(
        "brass and synthesizer broadcast anthem", "bright trumpet fanfare stabs",
        "wide synth pad bed", "arpeggiated synth under the orchestra",
        "snare drum rudiments", "orchestral horns", "big cymbal crash",
        "sleek and triumphant", "sunday night television energy",
        "clean intro", "instrumental", "no vocals", "118 BPM", "A major"),
     991104, 96),

    # --- slow burn to fanfare ---------------------------------------------
    ("slowburn", "nfl_menu_burn_reveal", T(
        "slow burn cinematic sports anthem", "quiet solo horn statement",
        "distant snare roll growing", "sustained low strings",
        "timpani swell", "brass fanfare arrives late and huge",
        "patient build then triumphant peak", "americana reverence",
        "starts sparse and quiet", "clean intro", "instrumental", "no vocals",
        "92 BPM", "C major"),
     991105, 118),
    ("slowburn", "nfl_menu_burn_legacy", T(
        "majestic orchestral build", "soft string bed opening",
        "muted trumpet motif", "military snare march entering midway",
        "timpani and low brass gathering", "full heroic fanfare finish",
        "dynasty legacy", "cinematic crescendo", "hushed clean opening",
        "instrumental", "no vocals", "88 BPM", "G major"),
     991106, 116),

    # --- uptempo march -----------------------------------------------------
    ("march", "nfl_menu_march_drive", T(
        "uptempo orchestral march", "marching band drumline",
        "tight military snare rudiments", "punchy brass fanfare hits",
        "bass drum on the beat", "energetic string runs", "piccolo trumpet",
        "relentless forward momentum", "game day parade", "stadium sized",
        "clean intro", "instrumental", "no vocals", "124 BPM", "F major"),
     991107, 92),
    ("march", "nfl_menu_march_swagger", T(
        "swaggering brass march", "syncopated trombone and tuba riff",
        "snare drumline groove", "trumpet fanfare answers",
        "orchestral percussion", "hand claps on the backbeat",
        "bold and playful", "prime time sports television",
        "americana big band edge", "clean intro", "instrumental", "no vocals",
        "116 BPM", "C minor"),
     991108, 98),
]


def gen(lane: str, stem: str, tags: str, seed: int, duration: int) -> dict:
    """One ACE-Step take into gen_nfl_menu/<lane>/, sidecar JSON alongside."""
    return gm._run(gm.ACE_VERSION, {
        "tags": tags,
        "lyrics": "[instrumental]",   # load-bearing: empty => pseudo-vocals
        "duration": duration,
        "number_of_steps": gm.ACE_STEPS,
        "seed": seed,
        "scheduler": "euler",
        "guidance_type": "apg",
        "guidance_scale": 15,
        "tag_guidance_scale": 5,
        "lyric_guidance_scale": 0,
    }, stem, OUT / lane,
        {"model": gm.ACE_MODEL, "version": gm.ACE_VERSION, "kind": "menu_theme",
         "style": lane, "seed": seed, "prompt": tags, "round": "nfl_menu",
         "requested_duration": duration})


def write_tsv() -> None:
    """Round sidecar: lane, path, seed, requested seconds, full prompt.

    First two columns keep the selections_*.tsv shape (style, path relative to
    tools/audio) so the existing review/ship tooling can read it; seed and
    prompt are appended so the round replays without the JSON sidecars.
    """
    lines = ["lane\tfile\tseed\trequested_s\tprompt"]
    for lane, stem, tags, seed, dur in CANDIDATES:
        lines.append(f"{lane}\tgen_nfl_menu/{lane}/{stem}.mp3\t{seed}\t{dur}\t{tags}")
    TSV.write_text("\n".join(lines) + "\n")
    print(f"wrote {TSV.relative_to(ROOT)}  ({len(CANDIDATES)} candidates)")


def main() -> None:
    write_tsv()
    if "--tsv-only" in sys.argv:
        return
    if not gm.TOKEN:
        sys.exit("REPLICATE_API_TOKEN not set")
    print(f"nfl_menu: {len(CANDIDATES)} generation(s) -> {OUT.name}/")
    results = []
    with cf.ThreadPoolExecutor(max_workers=4) as ex:   # 4 = gentle on 429s
        futs = [ex.submit(gen, *c) for c in CANDIDATES]
        for f in cf.as_completed(futs):
            r = f.result()
            results.append(r)
            print(f"    ... {r['take']} -> {r['status']}")
    print()
    gm.report(results)


if __name__ == "__main__":
    main()
