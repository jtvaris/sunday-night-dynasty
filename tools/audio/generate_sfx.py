#!/usr/bin/env python3
"""Stage-2 Job 2 — generate the bespoke SFX with Stable Audio Open on Replicate.

Usage:
    python3 generate_sfx.py pilot              # small probe batch
    python3 generate_sfx.py run [cat ...]      # full run (optionally subset)
    python3 generate_sfx.py run --tag v2       # extra prompt-iteration wave

Raw model output lands in gen_raw/<category>/<take>.wav; a JSON sidecar per
take records prompt/seed/params/predict_time so any take is reproducible.
Post-processing into gen/ is a separate script (post_sfx.py).
"""

from __future__ import annotations

import concurrent.futures as cf
import json
import os
import random
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RAW = ROOT / "gen_raw"
API = "https://api.replicate.com/v1"

MODEL_OWNER = "stackadoc"
MODEL_NAME = "stable-audio-open-1.0"
# Pinned so every take is reproducible; this is what /v1/models reports as
# latest_version for stackadoc/stable-audio-open-1.0.
MODEL_VERSION = "9aff84a639f96d0f7e6081cdea002d15133d0043727f849c40abdd166b7c75a8"

TOKEN = os.environ.get("REPLICATE_API_TOKEN", "")

# Steer hard away from the model's strong music/FMA bias.
NEG_SFX = "music, melody, song, instrument, rhythm, beat, harmony, singing, reverb tail, room reverb"
NEG_CROWD = "music, melody, song, instrument, beat, singing, announcer, commentary"

ONESHOT_SECS = 3   # generate a little long, trim to the transient in post
CROWD_SECS = 9


def J(*parts: str) -> str:
    return ", ".join(parts)


# category -> list of (take_suffix, prompt, seconds_total, negative_prompt)
def build_jobs() -> dict[str, list[tuple]]:
    jobs: dict[str, list[tuple]] = {}

    jobs["kick_punt"] = [
        (f"take{i+1}", p, ONESHOT_SECS, NEG_SFX) for i, p in enumerate([
            J("punt kick", "foot striking a leather football", "deep low-end thump",
              "burst of air whoosh", "close microphone", "dry foley", "isolated one-shot sound effect"),
            J("hard leather ball kick impact", "thick bassy thud", "fast air swoosh",
              "single hit", "dry studio foley recording", "no music"),
            J("american football punt", "boot striking inflated leather ball",
              "low percussive thump with airy tail", "close mic", "dry", "single sound effect"),
            J("sports ball kick", "deep percussive leather impact", "rush of air",
              "one-shot foley", "dry", "no reverb", "isolated"),
            J("heavy foot to leather thump", "punt", "low frequency impact transient",
              "air rush after contact", "close perspective", "dry sfx"),
            J("leather football punted hard", "muffled deep boom", "wind whoosh",
              "close dry foley", "single isolated hit"),
        ])
    ]

    jobs["kick_place"] = [
        (f"take{i+1}", p, ONESHOT_SECS, NEG_SFX) for i, p in enumerate([
            J("placekick off a tee", "sharp crisp leather ball impact", "bright snappy transient",
              "dry close mic", "isolated one-shot sound effect"),
            J("field goal kick", "hard sharp crack of boot on leather football",
              "tight attack", "short decay", "dry foley one-shot"),
            J("sharp leather ball strike", "crisp snapping impact",
              "bright high transient over a low thump", "dry studio recording", "isolated"),
            J("kicking a football off a tee", "clean percussive leather pop",
              "quick bright crack", "close dry foley", "no music"),
            J("solid boot to ball contact", "sharp leather smack", "punchy transient",
              "tight dry one-shot", "isolated sound effect"),
            J("placekick impact", "crisp hard leather hit", "bright snap with short tail",
              "close microphone foley", "dry"),
        ])
    ]

    jobs["catch"] = [
        (f"take{i+1}", p, ONESHOT_SECS, NEG_SFX) for i, p in enumerate([
            J("football caught in hands", "leather slapping into palms", "grip squeeze",
              "faint fabric rustle", "close dry foley one-shot"),
            J("leather ball smacking into cupped hands", "sharp hand slap",
              "creak of gripping leather", "dry close microphone", "isolated"),
            J("catching a ball against the chest", "muffled leather thud on padding",
              "fabric and pad rustle", "dry foley", "single hit"),
            J("hand slap on leather", "quick grabbing squeeze", "short dry impact",
              "close mic foley", "no music", "isolated one-shot"),
            J("ball into gloves", "leather on leather slap", "tight grip creak",
              "dry studio foley", "single sound effect"),
            J("firm catch", "leather ball smack into hands", "brief clothing rustle",
              "dry close perspective", "isolated one-shot"),
        ])
    ]

    jobs["throw_whoosh"] = [
        (f"take{i+1}", p, 2, NEG_SFX) for i, p in enumerate([
            J("fast air whoosh", "short sharp swish past the microphone", "quick air cut",
              "dry", "isolated", "no music"),
            J("object thrown fast through air", "brief swoosh", "sharp air movement",
              "close dry recording", "single one-shot"),
            J("quick arm swing whoosh", "short airy swish", "fast transient air cut",
              "dry foley", "isolated sound effect"),
            J("sharp whoosh", "compact burst of moving air", "fast attack quick decay",
              "dry close mic", "no music"),
            J("throwing motion air swish", "light fast whoosh", "brief wind cut",
              "dry studio foley", "isolated"),
            J("ball released and cutting through air", "short whoosh", "airy swipe",
              "close dry perspective", "one-shot sfx"),
        ])
    ]

    tackle = [
        J("body impact", "shoulder pads colliding", "heavy dull thud with plastic crunch",
          "fabric rustle", "close dry foley", "one-shot"),
        J("two padded bodies collide", "hard muffled body hit", "pad crunch",
          "cloth scuff", "dry close microphone", "isolated"),
        J("heavy body tackle", "thick low thud", "hard plastic pad clatter",
          "dry foley recording", "single impact"),
        J("football tackle impact", "shoulder pad crunch", "dull heavy body blow",
          "brief fabric scrape", "dry", "isolated one-shot"),
        J("padded collision", "muffled thump", "sharp plastic crack of armour",
          "close dry foley", "no music"),
        J("bodies slamming together", "deep dull impact", "pad and fabric crunch",
          "dry studio foley", "single hit"),
    ]
    tackle_huge = [
        J("massive body collision", "huge heavy impact", "shoulder pad crunch",
          "deep low thump", "powerful bone-jarring hit", "dry cinematic foley one-shot"),
        J("enormous tackle impact", "brutal heavy body slam", "loud pad crunch",
          "thick low-end boom", "punchy dry foley", "isolated big hit"),
    ]
    jobs["tackle_impact"] = ([(f"take{i+1}", p, ONESHOT_SECS, NEG_SFX)
                              for i, p in enumerate(tackle)] +
                             [(f"huge{i+1}", p, ONESHOT_SECS, NEG_SFX)
                              for i, p in enumerate(tackle_huge)])

    whistle = [
        J("referee pea whistle", "single short sharp blast", "shrill piercing tone",
          "rattling pea", "dry close recording", "isolated"),
        J("sports whistle blown once", "loud shrill trill", "sharp piercing blast",
          "dry", "single one-shot", "no music"),
        J("metal pea whistle", "one hard short blast", "high shrill warble",
          "close dry microphone", "isolated sound effect"),
        J("referee whistle blast", "piercing high tone with pea rattle",
          "short and sharp", "dry foley", "single"),
        J("shrill whistle", "one quick loud blow", "bright piercing trill",
          "dry close perspective", "isolated one-shot"),
        J("official's whistle", "single sharp shriek", "rattling pea whistle",
          "dry studio recording", "no music"),
    ]
    whistle_double = [
        J("referee pea whistle", "two short sharp blasts in quick succession",
          "shrill piercing trill", "dry close recording", "isolated"),
        J("sports whistle blown twice", "double short blast", "loud shrill pea whistle",
          "dry", "isolated one-shot", "no music"),
    ]
    jobs["whistle"] = ([(f"take{i+1}", p, 2, NEG_SFX) for i, p in enumerate(whistle)] +
                       [(f"double{i+1}", p, ONESHOT_SECS, NEG_SFX)
                        for i, p in enumerate(whistle_double)])

    cadence = [
        J("male voice shouting short sharp commands outdoors", "loud athletic shout",
          "hut hut", "stadium distance", "open air", "no music"),
        J("man barking a rhythmic snap count", "loud shouted syllables",
          "aggressive male voice", "outdoor stadium perspective", "reverberant distance"),
        J("male athlete shouting cadence", "short repeated loud shouts",
          "commanding voice", "outdoors at a distance", "no music"),
    ]
    grunts = [
        J("male effort grunt", "short forceful exhale", "athletic exertion",
          "close dry recording", "isolated"),
        J("man straining grunt", "deep guttural effort sound", "heavy exhale",
          "dry close microphone", "single one-shot"),
        J("short male exertion grunt", "pushing effort noise", "breathy strain",
          "dry foley", "isolated", "no music"),
    ]
    jobs["shouts"] = ([(f"cadence{i+1}", p, 4, NEG_CROWD) for i, p in enumerate(cadence)] +
                      [(f"grunt{i+1}", p, 2, NEG_SFX) for i, p in enumerate(grunts)])

    jobs["crowd_boo_extra"] = [
        (f"take{i+1}", p, CROWD_SECS, NEG_CROWD) for i, p in enumerate([
            J("large stadium crowd booing", "thousands of people jeering",
              "low rumbling disapproval", "swelling then fading", "outdoor arena ambience"),
            J("huge crowd boos loudly", "mass of angry voices", "deep rumbling jeer",
              "packed outdoor stadium", "wide ambience"),
            J("sports crowd booing in unison", "sustained disapproving roar",
              "thousands of voices", "big open stadium", "no music"),
            J("angry crowd jeering", "rising boo swell from a massive audience",
              "low throaty rumble", "outdoor arena", "distant wide perspective"),
        ])
    ]

    jobs["crowd_gasp_extra"] = [
        (f"take{i+1}", p, 6, NEG_CROWD) for i, p in enumerate([
            J("huge crowd gasping in unison", "sharp collective ohh of surprise",
              "sixty thousand people", "sudden intake then hush", "stadium ambience"),
            J("massive audience reacts with a shocked ooooh", "sharp collective gasp",
              "quick swell then falling away", "packed outdoor stadium"),
            J("stadium crowd sudden gasp", "thousands of voices in a startled ohh",
              "brief loud reaction then quiet murmur", "wide outdoor ambience"),
            J("collective crowd groan of disappointment", "sharp ohhh from a huge audience",
              "sudden reaction swell", "big stadium", "no music"),
        ])
    ]

    jobs["crowd_chant_extra"] = [
        (f"take{i+1}", p, CROWD_SECS, NEG_CROWD) for i, p in enumerate([
            J("large stadium crowd chanting rhythmically", "thousands of voices in unison",
              "repetitive rhythmic shouting", "outdoor arena ambience"),
            J("sports crowd chant", "steady rhythmic mass shouting", "wordless unison voices",
              "packed stadium", "wide reverberant outdoor space"),
            J("football supporters chanting", "pulsing rhythmic crowd voices",
              "call and response shouting", "huge outdoor stadium ambience"),
            J("rhythmic crowd chant with clapping", "thousands chanting together",
              "steady pulse", "big arena", "no music"),
        ])
    ]

    return jobs


def build_jobs_v2() -> dict[str, list[tuple]]:
    """Prompt-iteration wave, aimed at the weaknesses the round-1 analysis
    measured rather than guessed at:

    kick_place  round 1 landed a median spectral centroid of 4.5-6.2 kHz —
                thin and clicky, no ball behind it (one take was effectively
                DC). These prompts lead with the low-end body and name the
                ball as heavy, and the negative prompt pushes back on 'thin'
                and 'click'.
    catch       round 1 came out weak (-28 to -31 LUFS, sparse transients).
                These ask explicitly for a LOUD, hard slap.
    shouts      the grunts sat at ~3.3 kHz centroid, too bright for a big
                lineman; these ask for deep/chesty.
    """
    neg_thin = ("thin, clicky, tapping, ticking, high pitched, tinny, quiet, distant, "
                "music, melody, song, instrument, beat, reverb tail, room reverb")
    neg_weak = ("quiet, distant, thin, faint, rustling, music, melody, song, "
                "instrument, beat, reverb tail, room reverb")
    jobs: dict[str, list[tuple]] = {}

    jobs["kick_place"] = [
        (f"take{i+1}", p, ONESHOT_SECS, neg_thin) for i, p in enumerate([
            J("football placekick", "deep leather thud with a sharp crack on top",
              "low frequency body", "punchy weighty impact", "dry close foley"),
            J("hard kick into a heavy leather ball", "thick low thump with bright leather snap",
              "solid weighty impact", "dry studio recording"),
            J("boot striking a heavy inflated ball", "deep bassy thud and crisp leather crack together",
              "powerful", "dry foley one-shot"),
            J("field goal kick impact", "low end boom with a sharp attack",
              "heavy leather ball", "close dry recording", "isolated"),
            J("kicking a heavy leather ball hard", "deep punchy thump",
              "solid low frequency impact", "short bright transient", "dry"),
            J("solid football kick off a tee", "weighty low thud", "leather impact with body",
              "dry close mic", "isolated one-shot"),
        ])
    ]

    jobs["catch"] = [
        (f"take{i+1}", p, ONESHOT_SECS, neg_weak) for i, p in enumerate([
            J("loud leather ball slapping hard into palms", "sharp hand smack",
              "firm grip squeeze", "dry close foley"),
            J("heavy football smacking into open hands", "strong leather slap",
              "punchy loud impact", "dry studio recording"),
            J("ball hitting hands hard", "sharp loud leather impact like a clap",
              "grip creak", "close dry microphone"),
            J("forceful catch", "leather ball smacking into cupped palms",
              "loud slap transient", "dry foley one-shot"),
            J("leather smacking against skin", "hard hand slap", "quick grip creak",
              "punchy dry close recording"),
            J("football caught firmly against pads", "loud leather slap with a dull thud",
              "short sharp impact", "dry isolated one-shot"),
        ])
    ]

    jobs["shouts"] = [
        (f"grunt{i+1}", p, 2, neg_weak) for i, p in enumerate([
            J("deep male grunt", "low chesty effort exhale", "heavy strain",
              "close dry recording", "isolated"),
            J("low male exertion grunt", "guttural push from the chest", "deep voice",
              "dry close mic", "isolated"),
            J("big man grunting with effort", "deep chest voice", "short forceful exhale",
              "dry foley", "no music"),
        ])
    ]
    return jobs


def post(url: str, payload: dict, headers: dict, timeout: int = 180) -> tuple[int, dict, dict]:
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


def get(url: str, headers: dict, timeout: int = 60) -> dict:
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def generate(cat: str, take: str, prompt: str, secs: int, neg: str,
             seed: int, tag: str) -> dict:
    outdir = RAW / cat
    outdir.mkdir(parents=True, exist_ok=True)
    stem = f"{cat}_{take}" + (f"_{tag}" if tag else "")
    wav = outdir / f"{stem}.wav"
    meta_p = outdir / f"{stem}.json"
    if wav.exists() and meta_p.exists():
        return {"status": "cached", "file": str(wav)}

    headers = {
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
        "Prefer": "wait=60",
    }
    payload = {
        "version": MODEL_VERSION,
        "input": {
            "prompt": prompt,
            "negative_prompt": neg,
            "seconds_start": 0,
            "seconds_total": secs,
            "cfg_scale": 7,
            "steps": 100,
            "seed": seed,
            "sampler_type": "dpmpp-3m-sde",
        },
    }

    pred = None
    for attempt in range(8):
        code, j, hdrs = post(f"{API}/predictions", payload, headers)
        # 202 = accepted but still running when the `Prefer: wait` window
        # expired; the body is a valid prediction, we just have to poll.
        if code in (200, 201, 202):
            pred = j
            break
        if code == 429:
            wait = float(hdrs.get("retry-after") or hdrs.get("Retry-After") or 8)
            time.sleep(wait + random.uniform(0.2, 1.5))
            continue
        if code >= 500:
            time.sleep(4 + attempt * 3)
            continue
        return {"status": "error", "code": code, "detail": j, "take": stem}
    if pred is None:
        return {"status": "error", "detail": "exhausted retries", "take": stem}

    # Prefer: wait usually returns terminal; poll if still running.
    deadline = time.time() + 900
    while pred.get("status") not in ("succeeded", "failed", "canceled"):
        if time.time() > deadline:
            return {"status": "error", "detail": "timeout", "take": stem}
        time.sleep(3)
        try:
            pred = get(pred["urls"]["get"], {"Authorization": f"Bearer {TOKEN}"})
        except Exception:
            time.sleep(4)

    if pred["status"] != "succeeded":
        return {"status": pred["status"], "detail": pred.get("error"), "take": stem}

    url = pred["output"]
    if isinstance(url, list):
        url = url[0]
    for attempt in range(5):
        try:
            with urllib.request.urlopen(url, timeout=180) as r:
                wav.write_bytes(r.read())
            break
        except Exception:
            time.sleep(3 + attempt * 2)
    else:
        return {"status": "error", "detail": "download failed", "take": stem}

    meta = {
        "category": cat, "take": take, "stem": stem, "tag": tag,
        "model": f"{MODEL_OWNER}/{MODEL_NAME}", "version": MODEL_VERSION,
        "prompt": prompt, "negative_prompt": neg,
        "seconds_total": secs, "cfg_scale": 7, "steps": 100, "seed": seed,
        "sampler_type": "dpmpp-3m-sde",
        "prediction_id": pred.get("id"),
        "predict_time": (pred.get("metrics") or {}).get("predict_time"),
        "created_at": pred.get("created_at"),
    }
    meta_p.write_text(json.dumps(meta, indent=2))
    return {"status": "ok", "file": str(wav), "take": stem,
            "predict_time": meta["predict_time"]}


def main() -> None:
    if not TOKEN:
        sys.exit("REPLICATE_API_TOKEN not set")
    mode = sys.argv[1] if len(sys.argv) > 1 else "run"
    args = sys.argv[2:]
    tag = ""
    if "--tag" in args:
        i = args.index("--tag")
        tag = args[i + 1]
        args = args[:i] + args[i + 2:]

    jobs = build_jobs_v2() if mode == "iter" else build_jobs()

    if mode == "pilot":
        work = [
            ("tackle_impact", "pilot_a", jobs["tackle_impact"][0][1], 3, NEG_SFX),
            ("whistle", "pilot_a", jobs["whistle"][0][1], 2, NEG_SFX),
            ("kick_punt", "pilot_a", jobs["kick_punt"][0][1], 3, NEG_SFX),
            ("crowd_boo_extra", "pilot_a", jobs["crowd_boo_extra"][0][1], 9, NEG_CROWD),
        ]
        tag = tag or "pilot"
    else:
        cats = args or list(jobs)
        work = []
        for c in cats:
            for take, prompt, secs, neg in jobs[c]:
                work.append((c, take, prompt, secs, neg))

    print(f"{len(work)} takes -> {RAW}")
    base_seed = 20260803
    results = []
    with cf.ThreadPoolExecutor(max_workers=6) as ex:
        futs = {}
        for n, (c, take, prompt, secs, neg) in enumerate(work):
            seed = base_seed + n * 7919 + (hash(tag) % 1000 if tag else 0)
            futs[ex.submit(generate, c, take, prompt, secs, neg, seed, tag)] = (c, take)
        for f in cf.as_completed(futs):
            c, take = futs[f]
            try:
                r = f.result()
            except Exception as e:
                r = {"status": "error", "detail": repr(e)}
            r.setdefault("category", c)
            results.append(r)
            print(f"  [{r['status']:7s}] {c}/{take}"
                  f"  {r.get('predict_time') or ''}")

    ok = [r for r in results if r["status"] in ("ok", "cached")]
    bad = [r for r in results if r["status"] not in ("ok", "cached")]
    total_pt = sum(r.get("predict_time") or 0 for r in results)
    print(f"\nok={len(ok)} failed={len(bad)} total_predict_time={total_pt:.1f}s")
    for b in bad:
        print("  FAIL", b)


if __name__ == "__main__":
    main()
