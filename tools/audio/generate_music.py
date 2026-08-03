#!/usr/bin/env python3
"""Music experiment — menu themes (ACE-Step) + ambient loops (Stable Audio Open).

Answers one question: do the open, commercially-licensed music models clear the
"SUNDAY NIGHT DYNASTY primetime broadcast" bar, or is a paid service (Suno Pro)
required? Nothing here ships — output stays in tools/audio/ for review.

Two models, both license-gated in LICENSES.md ("Music candidates"):

  lucataco/ace-step            full-song, 60-120 s   Apache-2.0 (upstream
                               ACE-Step/ACE-Step-v1-3.5B) -> no revenue cap
  stackadoc/stable-audio-open  loops, <=47 s         Stability AI Community
                               License -> $1M annual-revenue cap applies

MusicGen and everything else built on `audiocraft` is DISQUALIFIED: its
LICENSE_weights is CC-BY-NC 4.0, which forbids shipping in a paid game.

INSTRUMENTAL ONLY. ACE-Step gets `lyrics="[instrumental]"` (the model's own
instrumental marker) rather than an empty string, because an empty lyrics field
lets it hallucinate mushy syllables over the top.

ROUND 2 (2026-08-03). Round 1 answered the question: yes, the open route
clears the bar. The user approved 6 of the 10 takes by ear — both
orchestral_cinematic, both dark_hybrid, and the downtempo + lofi loops.
Round 2 therefore stops exploring styles and DEEPENS the two approved theme
families, at broadcast length (150-210 s, the model's ceiling is 240) plus two
situational cues, and adds three more loops in the approved ambient lane.

Calibration that matters: the take the user liked most (dark_hybrid_take2) is
the one round 1's structural metrics ranked LAST — flat arc, bright centroid.
So round 2 deliberately does NOT prune candidates by those heuristics. It
generates spread inside each family and lets the ear decide; the metrics are
still measured and shown, but they carry no rank.

Usage:
    python3 generate_music.py pilot          # one theme, validates params
    python3 generate_music.py themes         # the 6 ACE-Step menu themes (r1)
    python3 generate_music.py loops          # the 4 Stable Audio Open loops (r1)
    python3 generate_music.py all            # round 1
    python3 generate_music.py r2-themes      # 10 long themes + 2 cues (r2)
    python3 generate_music.py r2-loops       # 3 ambient loops (r2)
    python3 generate_music.py round2         # both of the above
    python3 generate_music.py r3-menu        # 4 grand synth-lead menu themes
    python3 generate_music.py r3-dashboard   # 5 dark downtempo dashboard beds
    python3 generate_music.py round3         # both of the above
"""

from __future__ import annotations

import concurrent.futures as cf
import json
import os
import random
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "gen_music_raw"
API = "https://api.replicate.com/v1"
TOKEN = os.environ.get("REPLICATE_API_TOKEN", "")

# --- ACE-Step: full-song menu themes -------------------------------------
ACE_MODEL = "lucataco/ace-step"
ACE_VERSION = "280fc4f9ee507577f880a167f639c02622421d8fecf492454320311217b688f1"
ACE_SECS = 90          # inside the 60-120 s brief; same for every take so the
                       # three styles are compared like-for-like
ACE_STEPS = 60         # model default; raising it mostly costs time

# --- Stable Audio Open: ambient loops ------------------------------------
SAO_MODEL = "stackadoc/stable-audio-open-1.0"
SAO_VERSION = "9aff84a639f96d0f7e6081cdea002d15133d0043727f849c40abdd166b7c75a8"
SAO_SECS = 47          # the model's ceiling; we need every second we can get
                       # because ~2 s is spent on the loop crossfade
SAO_NEG = ("vocals, singing, voice, lyrics, choir, speech, announcer, rapping, "
           "harsh, distorted, clipping, sound effect, sudden silence")


def T(*parts: str) -> str:
    return ", ".join(parts)


# style -> [(take, tags, seed)]
# Tag vocabulary is deliberately concrete (instrument + articulation + tempo +
# key). ACE-Step responds to instrument names far better than to adjectives
# alone, and a stated BPM/key keeps the two takes of a style comparable.
# "instrumental, no vocals" is belt-and-braces on top of lyrics="[instrumental]".
THEMES: dict[str, list[tuple]] = {
    # (i) broadcast anthem — heroic brass, drumline, stadium-sized, peaks late
    "broadcast_anthem": [
        ("take1", T(
            "epic sports broadcast theme", "heroic brass fanfare",
            "marching drumline", "snare rolls", "timpani", "orchestral horns",
            "cymbal swells", "stadium anthem", "triumphant", "confident",
            "building to a big finish", "wide stereo", "instrumental",
            "no vocals", "140 BPM", "D minor"), 770101),
        ("take2", T(
            "primetime american football intro theme", "bold brass stabs",
            "military snare drumline", "low brass ostinato", "french horns",
            "orchestral percussion", "powerful", "swaggering", "broadcast package",
            "crescendo to peak", "instrumental", "no vocals", "128 BPM", "E minor"), 770102),
    ],
    # (ii) dark hybrid — synth bass pulse, cinematic percussion, modern primetime
    "dark_hybrid": [
        ("take1", T(
            "dark hybrid cinematic", "pulsing analog synth bass",
            "taiko drums", "cinematic percussion", "tense string ostinato",
            "brass swells", "trailer tension and release", "modern primetime sports",
            "brooding", "night game", "instrumental", "no vocals", "120 BPM", "F minor"), 770201),
        ("take2", T(
            "hybrid orchestral electronic", "driving synth bass pulse",
            "industrial percussion hits", "dark atmospheric pads",
            "staccato strings", "rising tension", "epic drop", "aggressive",
            "sleek and modern", "instrumental", "no vocals", "130 BPM", "A minor"), 770202),
    ],
    # (iii) orchestral cinematic — strings + horns, slow burn, championship weight
    "orchestral_cinematic": [
        ("take1", T(
            "epic orchestral cinematic", "sweeping legato strings",
            "noble french horns", "slow burn build", "timpani",
            "string ensemble", "championship gravitas", "majestic", "emotional",
            "film score", "instrumental", "no vocals", "90 BPM", "C minor"), 770301),
        ("take2", T(
            "cinematic orchestral anthem", "soaring string melody",
            "heroic horn theme", "deep low brass", "orchestral timpani rolls",
            "gradual crescendo to triumphant climax", "legacy and dynasty",
            "grand", "sweeping", "instrumental", "no vocals", "100 BPM", "G minor"), 770302),
    ],
}

# Ambient/dashboard underscore — understated, loopable, sits under UI.
LOOPS: list[tuple] = [
    ("ambient_lofi", "take1", T(
        "lo-fi ambient underscore", "soft warm synth pads", "gentle brushed drums",
        "subtle sub bass", "mellow", "understated", "calm and spacious",
        "steady unchanging loop", "background music", "instrumental"), 880101),
    ("ambient_broadcast", "take1", T(
        "ambient sports broadcast underscore", "muted electric piano",
        "soft pad wash", "light brushed percussion", "distant stadium crowd ambience",
        "relaxed", "professional", "steady loop", "instrumental"), 880201),
    ("ambient_downtempo", "take1", T(
        "downtempo lo-fi beat", "dusty warm keys", "soft kick and rim shot",
        "vinyl texture", "low-key confident", "dark and moody",
        "understated menu music", "steady groove", "instrumental"), 880301),
    ("ambient_cinematic", "take1", T(
        "cinematic ambient bed", "sustained warm string pad", "slow pulse",
        "subtle low percussion", "restrained", "moody", "pre-game calm",
        "evolving texture", "steady loop", "instrumental"), 880401),
]


# =========================================================================
# ROUND 2 — depth inside the two approved families, at broadcast length.
#
# Entries are (style, stem, tags, seed, duration_s). `style` decides the
# output folder and the family label on the review page; `stem` is the file
# name. Durations sit in the 150-210 s brief (ACE-Step's own ceiling is 240)
# except the situational cues, which are 90-120 s by design — a cue that
# outlives the screen it plays on is worse than one that repeats.
#
# Durations are also a SHIP budget, not just an artistic choice: every second
# here costs ~20 KB of app bundle at AAC 160 kbps, and the music budget is
# 60 MB. That is why nothing sits at the 210 s ceiling.
# =========================================================================

R2_THEMES: list[tuple] = [
    # --- orchestral_cinematic family: five different ways to be cinematic ---
    ("orchestral_cinematic", "orchestral_cinematic_r2_percussive", T(
        "epic orchestral cinematic", "driving orchestral percussion", "taiko drums",
        "timpani ostinato", "snare rolls", "staccato low strings",
        "brass punctuation", "relentless forward momentum", "percussion forward mix",
        "championship gravitas", "instrumental", "no vocals", "110 BPM", "C minor"),
     970301, 158),
    ("orchestral_cinematic", "orchestral_cinematic_r2_strings", T(
        "cinematic string orchestra", "no percussion", "sustained legato violins",
        "warm cello counter-melody", "slow burn build", "patient and emotional",
        "film score", "restrained opening then soaring", "dynasty legacy",
        "instrumental", "no vocals", "72 BPM", "D minor"),
     970302, 176),
    ("orchestral_cinematic", "orchestral_cinematic_r2_brass", T(
        "epic orchestral cinematic", "heroic french horn theme",
        "trombone and tuba power chords", "brass fanfare peaks",
        "string bed underneath", "timpani hits", "triumphant summits and quiet valleys",
        "stadium grandeur", "instrumental", "no vocals", "96 BPM", "E flat major"),
     970303, 162),
    ("orchestral_cinematic", "orchestral_cinematic_r2_noble", T(
        "noble restrained orchestral score", "gentle string ensemble",
        "solo french horn melody", "soft woodwinds", "sparse piano",
        "dignified and understated", "quiet confidence", "never bombastic",
        "hall of fame reverence", "instrumental", "no vocals", "80 BPM", "A major"),
     970304, 168),
    ("orchestral_cinematic", "orchestral_cinematic_r2_dark", T(
        "dark orchestral cinematic", "brooding low strings",
        "ominous cellos and double bass", "muted brass", "sparse timpani",
        "minor key tension", "cold and serious", "rivalry week", "foreboding build",
        "instrumental", "no vocals", "88 BPM", "B minor"),
     970305, 152),

    # --- dark_hybrid family: pulse tempo is the main axis of variation ---
    ("dark_hybrid", "dark_hybrid_r2_slow", T(
        "dark hybrid cinematic", "slow pulsing analog synth bass",
        "half-time cinematic drums", "deep sub bass", "sparse metallic percussion",
        "patient tension build", "brooding night game", "wide reverb",
        "instrumental", "no vocals", "92 BPM", "F minor"),
     970401, 166),
    ("dark_hybrid", "dark_hybrid_r2_drive", T(
        "hybrid orchestral electronic", "fast driving synth arpeggio",
        "tight electronic drums", "propulsive sixteenth note bass pulse",
        "staccato string stabs", "urgent momentum", "modern primetime sports",
        "instrumental", "no vocals", "145 BPM", "G minor"),
     970402, 152),
    ("dark_hybrid", "dark_hybrid_r2_atmos", T(
        "dark ambient hybrid score", "evolving synth pads", "distant low drones",
        "sparse sub bass pulse", "occasional cinematic hit", "spacious and atmospheric",
        "slow drifting tension", "minimal percussion", "empty stadium at night",
        "instrumental", "no vocals", "76 BPM", "D minor"),
     970403, 172),
    ("dark_hybrid", "dark_hybrid_r2_aggro", T(
        "aggressive hybrid trailer music", "distorted synth bass",
        "hard hitting industrial percussion", "brass braams", "metallic impacts",
        "gritty and confrontational", "relentless drive", "epic drop",
        "instrumental", "no vocals", "135 BPM", "A minor"),
     970404, 156),
    # the crossover the user asked for: approved family A over approved family B
    ("dark_hybrid", "dark_hybrid_r2_crossover", T(
        "hybrid orchestral electronic crossover",
        "sweeping legato strings over a pulsing analog synth bass",
        "cinematic taiko and timpani", "noble french horns against electronic percussion",
        "epic and modern", "tension and release", "primetime dynasty",
        "instrumental", "no vocals", "118 BPM", "C minor"),
     970405, 160),

    # --- situational cues (90-120 s) ---
    ("cue_draft", "cue_draft_room_take1", T(
        "tense underscore", "ticking clock", "restrained muted percussion",
        "pizzicato strings", "low sustained drone", "sparse piano notes",
        "nervous anticipation", "deadline pressure", "war room",
        "minimal and taut", "no big climax", "instrumental", "no vocals",
        "100 BPM", "A minor"),
     970501, 105),
    ("cue_championship", "cue_championship_take1", T(
        "triumphant orchestral climax", "full brass fanfare", "soaring string melody",
        "timpani rolls and cymbal crashes", "victory celebration",
        "confetti and lifted trophy", "majestic and joyous",
        "peaks early and holds", "instrumental", "no vocals", "104 BPM", "C major"),
     970502, 110),

    # --- situational-map fill: contexts that were still one-deep ---
    ("menu_theme", "menu_theme_r2_take1", T(
        "definitive sports management main menu theme", "warm legato strings",
        "noble horn statement", "soft timpani", "understated drumline",
        "confident but calm", "loops comfortably under a menu", "never fatiguing",
        "broadcast prestige", "instrumental", "no vocals", "86 BPM", "F major"),
     970601, 92),
    ("cue_draft", "cue_draft_room_take2", T(
        "tense minimal underscore", "metronome tick", "muted staccato strings",
        "soft heartbeat kick", "cold synth drone", "rising unease",
        "clock winding down", "restrained", "no melody", "instrumental",
        "no vocals", "92 BPM", "E minor"),
     970503, 100),
    ("cue_draft", "cue_draft_room_take3", T(
        "suspense underscore", "ticking percussion", "col legno strings",
        "low piano ostinato", "sparse marimba", "held breath tension",
        "decision under pressure", "understated and nervous", "instrumental",
        "no vocals", "108 BPM", "C sharp minor"),
     970504, 98),
    ("dark_hybrid", "gameday_build_take1", T(
        "aggressive hybrid pregame build", "pounding synth bass",
        "stadium drumline over electronic drums", "rising brass swell",
        "hard impacts", "adrenaline", "walk out of the tunnel",
        "builds relentlessly to kickoff", "instrumental", "no vocals",
        "128 BPM", "D minor"),
     970701, 150),
    ("orchestral_cinematic", "playoffs_dark_take1", T(
        "dark tense cinematic", "tremolo strings", "low brass swells",
        "sparse war drums", "cold and high stakes", "one game to survive",
        "creeping dread with a defiant peak", "january football",
        "instrumental", "no vocals", "84 BPM", "F sharp minor"),
     970801, 150),
]

# Round-2 loops, all inside the approved downtempo / lo-fi lane. Three feed
# the dashboard rotation, two are held for the offseason context (same lane,
# slightly softer) so the two screens do not share an identical playlist.
R2_LOOPS: list[tuple] = [
    ("ambient_downtempo", "ambient_downtempo_r2_take2", T(
        "downtempo lo-fi beat", "dusty rhodes chords", "soft kick and rim shot",
        "warm tape saturation", "vinyl crackle", "low-key confident",
        "steady unchanging groove", "understated menu music", "instrumental"), 980301),
    ("ambient_downtempo", "ambient_downtempo_r2_take3", T(
        "downtempo instrumental underscore", "muted upright bass", "brushed drums",
        "dark warm keys", "subtle vinyl texture", "moody and patient",
        "constant level", "no build", "background loop", "instrumental"), 980302),
    ("ambient_lofi", "ambient_lofi_r2_take2", T(
        "lo-fi ambient underscore", "soft warm analog pads", "gentle brushed drums",
        "mellow electric piano", "subtle sub bass", "calm and spacious",
        "steady unchanging loop", "no dynamic swells", "background music",
        "instrumental"), 980101),
    ("ambient_lofi", "ambient_lofi_r2_take3", T(
        "soft lo-fi ambient bed", "hazy tape pads", "very light percussion",
        "warm muted guitar", "slow and reflective", "quiet offseason",
        "steady unchanging loop", "background music", "instrumental"), 980102),
    ("ambient_downtempo", "ambient_downtempo_r2_take4", T(
        "slow downtempo underscore", "mellow electric piano", "soft brushed kick",
        "deep warm bass", "vinyl dust", "unhurried and reflective",
        "steady groove", "background loop", "instrumental"), 980303),
]


# =========================================================================
# ROUND 3 (2026-08-03) — the RESTYLE round. Not more depth: a change of
# character in the two contexts the player sits in longest.
#
# MENU. The round-2 menu themes are film-score cinematic — strings and horns
# doing gravitas. The user wants the other kind of sports grandeur: a slow,
# hymn-like SYNTH LEAD carrying a simple singable melody over orchestral
# swells, the sound of a 1981-era inspirational sports film. The style traits
# are described directly (analog synth lead, 72-84 BPM, major key, arpeggiated
# synth bed, slow triumphant build) rather than by naming any song or artist,
# so the prompts describe a genre and not a work.
#
# DASHBOARD. The round-2 dashboard *beds* are the same 150-175 s cinematic
# cues as the menu — too eventful for a screen someone stares at for twenty
# minutes. Round 3 replaces them with dark ambient-leaning downtempo at
# 60-75 BPM: sparse percussion, warm low synths, melancholic-calm, no build.
# The five 40-46 s ambient LOOPS are unaffected and stay in the rotation.
#
# Durations follow the brief (menu 90-110 s, dashboard 150-200 s) and are
# still a bundle budget: ~20 KB/s at AAC 160.
# =========================================================================

R3_MENU: list[tuple] = [
    ("menu_grand", "menu_grand_r3_anthem", T(
        "inspirational sports film main theme", "slow heroic tempo",
        "iconic analog synthesizer lead melody", "simple memorable melody",
        "lush orchestral string swells underneath", "soft timpani heartbeat",
        "nostalgic and triumphant", "slow burn build to a soaring finish",
        "wide reverb", "uplifting", "instrumental", "no vocals",
        "76 BPM", "D major"),
     990101, 96),
    ("menu_grand", "menu_grand_r3_piano", T(
        "grand inspirational anthem", "stately piano ostinato",
        "warm synthesizer lead doubling the melody",
        "swelling string orchestra", "gentle brass pad", "noble and hopeful",
        "patient build then a triumphant peak", "vintage sports film score",
        "instrumental", "no vocals", "80 BPM", "E flat major"),
     990102, 104),
    ("menu_grand", "menu_grand_r3_hymn", T(
        "hymn-like synthesizer anthem", "slow majestic tempo",
        "singing analog synth lead", "sustained orchestral strings",
        "distant french horns", "soft cymbal swells", "reverent and emotional",
        "slow motion victory montage", "nostalgic 1980s film score",
        "instrumental", "no vocals", "72 BPM", "C major"),
     990103, 108),
    ("menu_grand", "menu_grand_r3_soar", T(
        "triumphant synth and orchestra anthem",
        "soaring lead synthesizer melody", "arpeggiated synth bed",
        "orchestral horn swells", "rolling timpani", "rising key change",
        "euphoric and cinematic", "builds steadily to a big major-key finish",
        "instrumental", "no vocals", "84 BPM", "A major"),
     990104, 100),
]

R3_DASHBOARD: list[tuple] = [
    ("dashboard_dark", "dashboard_dark_r3_drift", T(
        "dark ambient downtempo", "warm low analog synth bass",
        "sparse rim clicks", "slow deep sub pulse", "distant pad wash",
        "melancholic and calm", "no build", "constant level",
        "front office at night", "background underscore",
        "instrumental", "no vocals", "62 BPM", "D minor"),
     990201, 176),
    ("dashboard_dark", "dashboard_dark_r3_ember", T(
        "mellow dark downtempo", "muted rhodes electric piano",
        "soft brushed kick", "dark warm synth pads", "tape hiss texture",
        "reflective and unhurried", "steady understated groove",
        "no dynamic swells", "background music",
        "instrumental", "no vocals", "68 BPM", "A minor"),
     990202, 168),
    ("dashboard_dark", "dashboard_dark_r3_late", T(
        "late night downtempo underscore", "deep warm synth bass",
        "sparse closed hi-hat", "distant felt piano notes",
        "smoky and melancholy", "quiet and patient", "steady loop feel",
        "understated menu music", "instrumental", "no vocals",
        "72 BPM", "F minor"),
     990203, 182),
    ("dashboard_dark", "dashboard_dark_r3_hollow", T(
        "dark ambient bed", "sustained low drone", "warm cello-like pad",
        "almost no percussion", "occasional soft sub thud",
        "sombre and spacious", "very slow", "no melody", "no build",
        "empty stadium in the offseason", "instrumental", "no vocals",
        "60 BPM", "C minor"),
     990204, 190),
    ("dashboard_dark", "dashboard_dark_r3_slowpulse", T(
        "slow downtempo with a soft pulse", "muffled kick drum",
        "granular synth pad", "warm low bass", "sparse felt piano",
        "quiet resolve", "mellow and dark", "unchanging intensity",
        "background underscore", "instrumental", "no vocals",
        "75 BPM", "G minor"),
     990205, 158),
]


# -------------------------------------------------------------------------

def post(url: str, payload: dict, headers: dict, timeout: int = 300):
    body = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode()), dict(r.headers)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            j = json.loads(raw)
        except Exception:
            j = {"detail": raw[:400]}
        return e.code, j, dict(e.headers)


def get(url: str, timeout: int = 60) -> dict:
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {TOKEN}", "User-Agent": "curl/8.7.1"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def _run(version: str, inp: dict, stem: str, outdir: Path, meta_extra: dict) -> dict:
    """Submit one prediction, poll to terminal, download the audio + sidecar."""
    outdir.mkdir(parents=True, exist_ok=True)
    meta_p = outdir / f"{stem}.json"
    existing = list(outdir.glob(f"{stem}.*"))
    if meta_p.exists() and any(p.suffix != ".json" for p in existing):
        return {"status": "cached", "take": stem}

    headers = {"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json",
               "User-Agent": "curl/8.7.1", "Prefer": "wait=60"}
    pred = None
    for attempt in range(8):
        code, j, hdrs = post(f"{API}/predictions", {"version": version, "input": inp}, headers)
        if code in (200, 201, 202):
            pred = j
            break
        if code == 429:
            time.sleep(float(hdrs.get("retry-after") or 8) + random.uniform(0.2, 1.5))
            continue
        if code >= 500:
            time.sleep(4 + attempt * 3)
            continue
        return {"status": "error", "code": code, "detail": j, "take": stem}
    if pred is None:
        return {"status": "error", "detail": "exhausted retries", "take": stem}

    deadline = time.time() + 1200
    while pred.get("status") not in ("succeeded", "failed", "canceled"):
        if time.time() > deadline:
            return {"status": "error", "detail": "timeout", "take": stem}
        time.sleep(4)
        try:
            pred = get(pred["urls"]["get"])
        except Exception:
            time.sleep(4)

    if pred["status"] != "succeeded":
        return {"status": pred["status"], "detail": pred.get("error"), "take": stem}

    url = pred["output"]
    if isinstance(url, list):
        url = url[0]
    ext = os.path.splitext(url.split("?")[0])[1] or ".wav"
    audio = outdir / f"{stem}{ext}"
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=300) as r:
                audio.write_bytes(r.read())
            break
        except Exception:
            time.sleep(3 + attempt * 2)
    else:
        return {"status": "error", "detail": "download failed", "take": stem}

    meta = {"stem": stem, "input": inp, "file": audio.name,
            "prediction_id": pred.get("id"),
            "predict_time": (pred.get("metrics") or {}).get("predict_time"),
            "created_at": pred.get("created_at"), **meta_extra}
    meta_p.write_text(json.dumps(meta, indent=2))
    return {"status": "ok", "take": stem, "file": str(audio),
            "predict_time": meta["predict_time"]}


def gen_theme(style: str, take: str, tags: str, seed: int,
              duration: int = ACE_SECS, stem: str | None = None,
              rnd: int = 1) -> dict:
    return _run(ACE_VERSION, {
        "tags": tags,
        # The model's own instrumental marker. An EMPTY lyrics field is what
        # makes ACE-Step invent slurred pseudo-vocals, so this is load-bearing.
        "lyrics": "[instrumental]",
        "duration": duration,
        "number_of_steps": ACE_STEPS,
        "seed": seed,
        "scheduler": "euler",
        "guidance_type": "apg",
        "guidance_scale": 15,
        "tag_guidance_scale": 5,     # >0 so the style tags actually bind
        "lyric_guidance_scale": 0,   # nothing to guide toward — instrumental
    }, stem or f"{style}_{take}", RAW / style,
        {"model": ACE_MODEL, "version": ACE_VERSION, "kind": "menu_theme",
         "style": style, "seed": seed, "prompt": tags, "round": rnd,
         "requested_duration": duration})


def gen_r2_theme(style: str, stem: str, tags: str, seed: int, duration: int) -> dict:
    return gen_theme(style, "", tags, seed, duration=duration, stem=stem, rnd=2)


def gen_r3_theme(style: str, stem: str, tags: str, seed: int, duration: int) -> dict:
    return gen_theme(style, "", tags, seed, duration=duration, stem=stem, rnd=3)


def gen_loop(name: str, take: str, prompt: str, seed: int,
             stem: str | None = None, rnd: int = 1) -> dict:
    return _run(SAO_VERSION, {
        "prompt": prompt,
        "negative_prompt": SAO_NEG,
        "seconds_start": 0,
        "seconds_total": SAO_SECS,
        "cfg_scale": 7,
        "steps": 100,
        "seed": seed,
        "sampler_type": "dpmpp-3m-sde",
    }, stem or f"{name}_{take}", RAW / name,
        {"model": SAO_MODEL, "version": SAO_VERSION, "kind": "ambient_loop",
         "style": name, "seed": seed, "prompt": prompt, "round": rnd,
         "requested_duration": SAO_SECS})


def gen_r2_loop(style: str, stem: str, prompt: str, seed: int) -> dict:
    return gen_loop(style, "", prompt, seed, stem=stem, rnd=2)


def report(results: list[dict]) -> None:
    ok = [r for r in results if r["status"] in ("ok", "cached")]
    gpu = sum(r.get("predict_time") or 0 for r in results)
    for r in results:
        mark = "ok " if r["status"] in ("ok", "cached") else "ERR"
        extra = f"{r.get('predict_time') or 0:6.1f}s" if r.get("predict_time") else "      "
        print(f"  [{mark}] {r['take']:<34} {extra}"
              + ("" if r["status"] in ("ok", "cached") else f"  {str(r.get('detail'))[:160]}"))
    print(f"\n{len(ok)}/{len(results)} ok   GPU {gpu:.1f}s")


def main() -> None:
    if not TOKEN:
        sys.exit("REPLICATE_API_TOKEN not set")
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    jobs = []

    if mode == "pilot":
        s, (tk, tags, seed) = "broadcast_anthem", THEMES["broadcast_anthem"][0]
        jobs = [(gen_theme, (s, tk, tags, seed))]
    if mode in ("themes", "all"):
        jobs += [(gen_theme, (s, tk, tags, seed))
                 for s, takes in THEMES.items() for tk, tags, seed in takes]
    if mode in ("loops", "all"):
        jobs += [(gen_loop, args) for args in LOOPS]
    if mode in ("r2-themes", "round2"):
        jobs += [(gen_r2_theme, args) for args in R2_THEMES]
    if mode in ("r2-loops", "round2"):
        jobs += [(gen_r2_loop, args) for args in R2_LOOPS]
    if mode in ("r3-menu", "round3"):
        jobs += [(gen_r3_theme, args) for args in R3_MENU]
    if mode in ("r3-dashboard", "round3"):
        jobs += [(gen_r3_theme, args) for args in R3_DASHBOARD]

    if not jobs:
        sys.exit(f"unknown mode: {mode}")

    print(f"{mode}: {len(jobs)} generation(s)")
    results = []
    # 4 at a time — enough to keep it quick, gentle enough not to trip 429s.
    with cf.ThreadPoolExecutor(max_workers=4) as ex:
        futs = [ex.submit(fn, *args) for fn, args in jobs]
        for f in cf.as_completed(futs):
            r = f.result()
            results.append(r)
            print(f"    ... {r['take']} -> {r['status']}")
    print()
    report(results)


if __name__ == "__main__":
    main()
