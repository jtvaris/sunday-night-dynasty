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

Usage:
    python3 generate_music.py pilot          # one theme, validates params
    python3 generate_music.py themes         # the 6 ACE-Step menu themes
    python3 generate_music.py loops          # the 4 Stable Audio Open loops
    python3 generate_music.py all
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


def gen_theme(style: str, take: str, tags: str, seed: int) -> dict:
    return _run(ACE_VERSION, {
        "tags": tags,
        # The model's own instrumental marker. An EMPTY lyrics field is what
        # makes ACE-Step invent slurred pseudo-vocals, so this is load-bearing.
        "lyrics": "[instrumental]",
        "duration": ACE_SECS,
        "number_of_steps": ACE_STEPS,
        "seed": seed,
        "scheduler": "euler",
        "guidance_type": "apg",
        "guidance_scale": 15,
        "tag_guidance_scale": 5,     # >0 so the style tags actually bind
        "lyric_guidance_scale": 0,   # nothing to guide toward — instrumental
    }, f"{style}_{take}", RAW / style,
        {"model": ACE_MODEL, "version": ACE_VERSION, "kind": "menu_theme",
         "style": style, "seed": seed, "prompt": tags})


def gen_loop(name: str, take: str, prompt: str, seed: int) -> dict:
    return _run(SAO_VERSION, {
        "prompt": prompt,
        "negative_prompt": SAO_NEG,
        "seconds_start": 0,
        "seconds_total": SAO_SECS,
        "cfg_scale": 7,
        "steps": 100,
        "seed": seed,
        "sampler_type": "dpmpp-3m-sde",
    }, f"{name}_{take}", RAW / name,
        {"model": SAO_MODEL, "version": SAO_VERSION, "kind": "ambient_loop",
         "style": name, "seed": seed, "prompt": prompt})


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
