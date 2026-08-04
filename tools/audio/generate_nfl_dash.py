#!/usr/bin/env python3
"""NFL-broadcast round — DASHBOARD underscore candidates (ACE-Step).

Sister round to `generate_music.py`'s r3-dashboard, with a different brief.
r3 answered "what does a calm front-office bed sound like" with lo-fi/downtempo
(rhodes, tape hiss, brushed kicks). This round asks a narrower question: can the
*broadcast* palette — brass, strings, timpani, military snare — be dialled down
far enough to work as an underscore, so the dashboard shares DNA with the menu
theme instead of sounding like a different game?

The constraint that defines the round: it must sit BEHIND reading and decisions.
Every prompt therefore carries explicit anti-arc language ("no build", "constant
intensity", "never demands attention") on top of the instrument list, because
ACE-Step's default reading of "brass fanfare" is a trailer climax, and a
trailer climax under a roster screen is unusable no matter how good it sounds.

STYLE WORDS ONLY. The tags describe a genre — heroic brass, snare march rolls,
Americana grandeur, prime-time sports television — and never name a real theme,
show, network, composer or melody.

Four lanes x two takes, so each idea gets a second roll of the dice:

  lowbrass    trombone/tuba ostinato, the "war room at night" core
  strings     string ostinato + soft pulse, motion without event
  ambient     ambient-orchestral hybrid, texture over rhythm
  fanfare     a muted fanfare MOTIF (fragment, not statement) over a bed

Durations 96-148 s (brief: 90-150). Duration is also a ship budget: ~20 KB/s at
AAC 160 kbps against a 60 MB music budget.

Output: gen_nfl_dash/<stem>.mp3 + <stem>.json sidecar (gitignored via
`gen_nfl_*/`). Mastering + metrics are `post_nfl_dash.py`.

Usage:
    python3 generate_nfl_dash.py            # all 8
    python3 generate_nfl_dash.py lowbrass   # one lane
"""

from __future__ import annotations

import concurrent.futures as cf
import sys
from pathlib import Path

import generate_music as gm
from generate_music import T

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "gen_nfl_dash"

ROUND = "nfl_dash_r1"

# (lane, stem, tags, seed, duration_s)
CANDIDATES: list[tuple] = [
    # --- lane 1: low-brass ostinato ---------------------------------------
    ("lowbrass", "nfl_dash_lowbrass_a", T(
        "dark cinematic sports underscore", "muted low brass ostinato",
        "trombones and tuba repeating a short figure", "sustained cello bed",
        "soft timpani heartbeat", "distant military snare roll very quiet",
        "restrained and serious", "constant intensity", "no build",
        "no climax", "background music under a screen", "war room at night",
        "wide but dark mix", "instrumental", "no vocals", "84 BPM", "D minor"),
     994101, 132),
    ("lowbrass", "nfl_dash_lowbrass_b", T(
        "understated broadcast underscore", "low brass pedal tone",
        "french horns held soft and far back", "double bass ostinato",
        "sparse snare march accents", "occasional soft timpani",
        "sombre and patient", "unchanging level", "never demands attention",
        "no fanfare", "americana gravitas held in reserve",
        "instrumental", "no vocals", "76 BPM", "F minor"),
     994102, 118),

    # --- lane 2: strings + pulse ------------------------------------------
    ("strings", "nfl_dash_strings_a", T(
        "cinematic string underscore", "quiet staccato string ostinato",
        "soft synth pulse underneath", "warm low strings",
        "very sparse snare tap", "muted brass pad in the distance",
        "forward motion without drama", "steady and hypnotic", "no swells",
        "no build", "thoughtful", "prime time sports television bed",
        "instrumental", "no vocals", "92 BPM", "A minor"),
     994103, 126),
    ("strings", "nfl_dash_strings_b", T(
        "dark orchestral pulse underscore", "tremolo violins held low",
        "pizzicato bass pulse", "cello counter-line", "muffled timpani pulse",
        "brushed military snare, barely audible", "cold and analytical",
        "constant dynamics", "no crescendo", "night broadcast",
        "background underscore", "instrumental", "no vocals",
        "88 BPM", "C minor"),
     994104, 144),

    # --- lane 3: ambient-orchestral hybrid --------------------------------
    ("ambient", "nfl_dash_ambient_a", T(
        "ambient orchestral hybrid bed", "sustained brass drone",
        "granular string texture", "deep sub pulse", "soft warm synth pad",
        "almost no percussion", "one distant timpani every few bars",
        "spacious and sombre", "very slow", "no melody", "no build",
        "empty stadium at night", "instrumental", "no vocals",
        "62 BPM", "G minor"),
     994105, 148),
    ("ambient", "nfl_dash_ambient_b", T(
        "cinematic ambient underscore", "orchestral strings blurred into pad",
        "low horn swell rising and falling gently", "faint snare rustle",
        "warm analog bass drone", "reverb heavy", "reflective and dark",
        "unchanging intensity", "no dynamic peaks", "hangs in the background",
        "americana melancholy", "instrumental", "no vocals",
        "70 BPM", "E minor"),
     994106, 136),

    # --- lane 4: muted-fanfare motif --------------------------------------
    ("fanfare", "nfl_dash_fanfare_a", T(
        "muted broadcast fanfare motif over a quiet bed",
        "short three note horn figure played softly",
        "the motif answered by low strings", "military snare rolls kept low",
        "timpani under the surface", "heroic material played restrained",
        "dignified", "no big statement", "no climax", "constant level",
        "sports television underscore", "instrumental", "no vocals",
        "90 BPM", "B flat minor"),
     994107, 122),
    ("fanfare", "nfl_dash_fanfare_b", T(
        "restrained brass motif underscore", "cup muted trumpets",
        "short repeating brass phrase, quiet and far back",
        "string bed underneath", "snare march roll at low volume",
        "soft cymbal wash", "americana grandeur held back",
        "steady, never rising", "no peak", "thoughtful background music",
        "instrumental", "no vocals", "96 BPM", "D minor"),
     994108, 96),
]


def gen(lane: str, stem: str, tags: str, seed: int, duration: int) -> dict:
    return gm._run(gm.ACE_VERSION, {
        "tags": tags,
        "lyrics": "[instrumental]",       # load-bearing: "" -> pseudo-vocals
        "duration": duration,
        "number_of_steps": gm.ACE_STEPS,
        "seed": seed,
        "scheduler": "euler",
        "guidance_type": "apg",
        "guidance_scale": 15,
        "tag_guidance_scale": 5,
        "lyric_guidance_scale": 0,
    }, stem, OUT, {
        "model": gm.ACE_MODEL, "version": gm.ACE_VERSION,
        "kind": "dashboard_underscore", "style": "nfl_dash", "lane": lane,
        "seed": seed, "prompt": tags, "round": ROUND,
        "requested_duration": duration,
    })


def main() -> None:
    if not gm.TOKEN:
        sys.exit("REPLICATE_API_TOKEN not set")
    lanes = set(sys.argv[1:])
    jobs = [c for c in CANDIDATES if not lanes or c[0] in lanes]
    if not jobs:
        sys.exit(f"no candidates in lane(s) {sorted(lanes)}")

    print(f"{ROUND}: {len(jobs)} generation(s) -> {OUT.relative_to(ROOT.parent.parent)}")
    results = []
    with cf.ThreadPoolExecutor(max_workers=4) as ex:
        futs = [ex.submit(gen, *c) for c in jobs]
        for f in cf.as_completed(futs):
            r = f.result()
            results.append(r)
            print(f"    ... {r['take']} -> {r['status']}")
    print()
    gm.report(results)


if __name__ == "__main__":
    main()
