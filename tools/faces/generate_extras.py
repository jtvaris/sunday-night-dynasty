#!/usr/bin/env python3
"""User-avatar + owner portrait generator — the face library's small siblings.

Two id spaces of their own (`avatar_NNNNN`, `owner_NNNNN`), a separate
manifest (extras_manifest.json) and raw dir (raw_extras/). Deliberately NOT
part of manifest.json / the face_* pool: gate 19 in make_templates.py
cross-checks that manifest against its bucket transcription, and these ranges
never need the app's synthesized-catalog fallback — they ship manifest-only,
so no bit-exact RNG port is required on the Swift side.

  python3 generate_extras.py             # generate 20 avatars + 96 owners
  python3 generate_extras.py --package   # -> out/ExtraFaces/*.heic + manifest

Avatars: 10 male + 10 female coach-style headshots for the career wizard
(replaces/augments the illustrated coach_m*/coach_f* picks). Gender is fixed
by index (first 10 male), not drawn — the picker wants a balanced grid.
Owners: 96 executive portraits (suit, older, ~15 % female) so a career's 32
owners stay unique with headroom to spare.
"""
import argparse, hashlib, json, os, random, subprocess, sys, time
from concurrent.futures import ThreadPoolExecutor

import generate_faces as gf

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, "raw_extras")
MANIFEST = os.path.join(ROOT, "extras_manifest.json")
OUT = os.path.join(ROOT, "out", "ExtraFaces")

AVATAR_COUNT = 20          # 10 male + 10 female, gender by index
OWNER_COUNT = 96
OWNER_FEMALE_SHARE = 0.15  # NFL has a handful of female principal owners

OWNER_CLOTHING = "dark tailored business suit with a white dress shirt"
OWNER_AGES = [("45-60", "in his mid fifties", 0.40),
              ("60-78", "in his late sixties, gray hair", 0.60)]
OWNER_AGES_F = [("45-60", "in her mid fifties", 0.40),
                ("60-78", "in her late sixties, gray hair", 0.60)]
# Editorial approximation of NFL principal-owner demographics — deliberately
# different weights from the player/coach TONES.
OWNER_TONES = [("white", "white American man", 0.72),
               ("black", "Black American man", 0.12),
               ("latino", "Latino American man", 0.06),
               ("pacific", "Pacific Islander American man", 0.02),
               ("mixed", "mixed-race American man", 0.08)]
OWNER_TONES_F = [("white", "white American woman", 0.72),
                 ("black", "Black American woman", 0.12),
                 ("latino", "Latina American woman", 0.06),
                 ("pacific", "Pacific Islander American woman", 0.02),
                 ("mixed", "mixed-race American woman", 0.08)]
OWNER_BUILDS = [("lean", "trim build", 0.45), ("athletic", "sturdy build", 0.30),
                ("heavy", "heavyset build", 0.25)]


def avatar_spec(i):
    fid = f"avatar_{i:05d}"
    rng = random.Random(f"{gf.FEMALE_RANGE_START}:{gf.STYLE[:8]}:{fid}")  # stable, own stream
    gender = "male" if i < AVATAR_COUNT // 2 else "female"
    bucket, prompt = gf.build_spec(rng, "coach", gender)
    bucket = {**bucket, "role": "avatar"}
    return fid, bucket, prompt, rng.randrange(1, 2**31)


def owner_spec(i):
    fid = f"owner_{i:05d}"
    rng = random.Random(f"owner:{20260729}:{fid}")
    female = rng.random() < OWNER_FEMALE_SHARE
    tone_t, tone_f = gf.wpick(rng, OWNER_TONES_F if female else OWNER_TONES)
    age_t, age_f = gf.wpick(rng, OWNER_AGES_F if female else OWNER_AGES)
    build_t, build_f = gf.wpick(rng, OWNER_BUILDS)
    if female:
        subject = f"{tone_f} {age_f}, {build_f}, {rng.choice(gf.HAIR_F)}"
    else:
        subject = f"{tone_f} {age_f}, {build_f}, {rng.choice(gf.HAIR)}, {rng.choice(gf.FACIAL)}"
    prompt = f"{subject}. {gf.STYLE.format(clothing=OWNER_CLOTHING)}"
    bucket = {"role": "owner", "gender": "female" if female else "male",
              "ageBand": age_t, "tone": tone_t, "build": build_t}
    return fid, bucket, prompt, rng.randrange(1, 2**31)


def specs():
    return [avatar_spec(i) for i in range(AVATAR_COUNT)] + \
           [owner_spec(i) for i in range(OWNER_COUNT)]


def generate(backend_name, backend):
    os.makedirs(RAW, exist_ok=True)
    manifest = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {"version": 1, "faces": []}
    have = {f["id"] for f in manifest["faces"]}
    todo = [s for s in specs() if s[0] not in have]
    print(f"backend={backend_name} extras target={AVATAR_COUNT + OWNER_COUNT} existing={len(have)} todo={len(todo)}")
    import threading
    lock = threading.Lock()
    failures = [0]

    def work(spec):
        fid, bucket, prompt, seed = spec
        for attempt in range(5):
            try:
                time.sleep(random.uniform(0.5, 2.0))
                data = backend(prompt, seed)
                if len(data) < 20_000: raise RuntimeError(f"suspiciously small image ({len(data)}B)")
                open(os.path.join(RAW, f"{fid}.png"), "wb").write(data)
                with lock:
                    manifest["faces"].append({"id": fid, "file": f"raw_extras/{fid}.png",
                                              "bucket": bucket, "seed": seed, "backend": backend_name,
                                              "sha256": hashlib.sha256(data).hexdigest()[:16],
                                              "prompt": prompt})
                    json.dump(manifest, open(MANIFEST, "w"), indent=1)
                return
            except Exception as e:
                print(f"{fid} attempt {attempt+1} FAILED: {e}", file=sys.stderr, flush=True)
                time.sleep(12 * (attempt + 1))
        with lock:
            failures[0] += 1
            if failures[0] > 12:
                print("Too many failures — aborting", file=sys.stderr); os._exit(2)

    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(work, todo))
    print(f"done: {len(manifest['faces'])} extras in manifest, {failures[0]} failures")


def package():
    m = json.load(open(MANIFEST))
    os.makedirs(OUT, exist_ok=True)
    out_faces = []
    for f in m["faces"]:
        src = os.path.join(ROOT, f["file"])
        dst = os.path.join(OUT, f"{f['id']}.heic")
        if not os.path.exists(dst):
            subprocess.run(["sips", "-s", "format", "heic", "-s", "formatOptions", "80",
                            "-Z", "384", src, "--out", dst],
                           check=True, capture_output=True)
        out_faces.append({"id": f["id"], "file": f"ExtraFaces/{f['id']}.heic", "bucket": f["bucket"]})
    json.dump({"version": 1, "faces": out_faces},
              open(os.path.join(ROOT, "out", "extra_faces_manifest.json"), "w"), indent=1)
    print(f"packaged {len(out_faces)} extras -> {OUT}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--package", action="store_true")
    ap.add_argument("--backend", default=None)
    args = ap.parse_args()
    if args.package:
        package()
        return
    name, fn = gf.pick_backend(args.backend)
    generate(name, fn)


if __name__ == "__main__":
    main()
