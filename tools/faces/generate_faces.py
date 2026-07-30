#!/usr/bin/env python3
"""Dynasty face library generator — backend-pluggable, resume-safe.

Usage:
  python3 generate_faces.py --pilot                 # 24 samples across buckets
  python3 generate_faces.py --count 2048            # full library (resumes)
  python3 generate_faces.py --count 2560            # + the reserve range
  python3 generate_faces.py --count 3584            # + the female-capable range
  python3 generate_faces.py --count 3712            # + the female-ONLY range
  python3 generate_faces.py --backend replicate ... # explicit backend

QA cull loop: tick faces in out/review.html -> paste into culled.json -> re-run
this script. Culled ids are dropped from manifest.json (their PNG is renamed
*.png.culled) so resume regenerates them from the same (seed, id) bucket, and an
id leaves culled.json only once its replacement image lands.

Backends & credentials (first available wins unless --backend given):
  replicate  REPLICATE_API_TOKEN   FLUX schnell  (~$0.003/img, recommended)
  fal        FAL_KEY               FLUX schnell
  gemini     GEMINI_API_KEY        Imagen 3 (AI Studio)
  openai     OPENAI_API_KEY        gpt-image-1
Outputs: raw/<id>.png + manifest.json (id, bucket, prompt, seed, backend).
No fabricated entries: an image lands in the manifest only after it decodes.
"""
import argparse, base64, hashlib, json, os, random, sys, threading, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, "raw")
MANIFEST = os.path.join(ROOT, "manifest.json")
# Ids the human QA sweep rejected (written from package_faces.py's review.html).
# Same path package_faces.py reads — see the cull handling in main().
CULLED = os.path.join(ROOT, "culled.json")

STYLE = ("Professional sports media day headshot portrait photograph, head and "
         "shoulders, facing camera, neutral confident expression, plain dark gray "
         "studio backdrop, soft even studio lighting, photorealistic, 85mm lens, "
         "sharp focus, {clothing}. Single adult person, a generic person who does "
         "not resemble any celebrity or public figure. No text, no logos, no "
         "jersey branding, no hands in frame.")

PLAYER_CLOTHING = "plain dark athletic compression shirt"
COACH_CLOTHING = "plain dark polo shirt"

# (tag, prompt fragment, weight) — editorial approximation of NFL demographics.
# Female lists mirror the male ones with IDENTICAL tags and weights so the
# bucket space (and every wpick draw count) is the same for both genders —
# the app's synthesized catalog replays these draws bit-exactly.
TONES = [
    ("black", "Black American man", 0.55),
    ("white", "white American man", 0.28),
    ("latino", "Latino American man", 0.07),
    ("pacific", "Pacific Islander (Samoan/Tongan) American man", 0.04),
    ("mixed", "mixed-race American man", 0.06),
]
TONES_F = [
    ("black", "Black American woman", 0.55),
    ("white", "white American woman", 0.28),
    ("latino", "Latina American woman", 0.07),
    ("pacific", "Pacific Islander (Samoan/Tongan) American woman", 0.04),
    ("mixed", "mixed-race American woman", 0.06),
]
PLAYER_AGES = [("20-24", "in his early twenties", 0.38),
               ("25-29", "in his late twenties", 0.40),
               ("30-36", "in his early thirties", 0.22)]
COACH_AGES = [("38-50", "in his mid forties", 0.45),
              ("50-68", "in his late fifties, some gray hair", 0.55)]
COACH_AGES_F = [("38-50", "in her mid forties", 0.45),
                ("50-68", "in her late fifties, some gray hair", 0.55)]
BUILDS = [("lean", "lean athletic build, defined jawline", 0.30),
          ("athletic", "muscular athletic build", 0.50),
          ("heavy", "very heavyset powerful build, thick neck, round face", 0.20)]
COACH_BUILDS = [("lean", "average build", 0.4), ("athletic", "sturdy build", 0.35),
                ("heavy", "heavyset build", 0.25)]
HAIR = ["short cropped hair", "buzz cut", "short dreadlocks", "medium afro",
        "bald head", "short curly hair", "short straight hair", "fade haircut"]
HAIR_F = ["shoulder-length straight hair", "curly shoulder-length hair", "long braids",
          "natural afro", "hair in a tight bun", "short pixie cut",
          "long straight hair tied back", "medium wavy hair"]
FACIAL = ["clean shaven", "short beard", "full beard", "goatee", "light stubble", "mustache"]

# Ids at/after this draw a gender for coach faces. Ids below it predate the
# female range and must keep their draw sequence byte-identical (the shipped
# manifest and the app's synthesized catalog both depend on it), so the extra
# rng.random() gender draw is gated on the id, never on the count argument.
FEMALE_RANGE_START = 2560

# Ids at/after this are female coach faces, full stop: role and gender are
# FACTS about the range, not draws. 0.22 of a 0.1875 coach share is one woman
# per ~24 ids — 35 of them across the whole 1 024-id female range, which a
# career exhausts by season 2-3 (measured: freeFemale=0 from 2027, 6-16
# within-gender duplicates by 2028). Buying the next 128 through the same
# lottery would have meant ~3 100 more images, ~2 975 of them men nobody needs.
#
# Forcing the two facts consumes NO rng.random(): a draw whose outcome is
# already decided is not a draw, and spending one anyway would only shift the
# tone/age/build stream of this range for no gain. Same discipline as
# FEMALE_RANGE_START, from the other direction — the gate is on the id, so
# every id below 3584 keeps the exact draw sequence its shipped picture was
# painted from, whatever --count says.
FEMALE_ONLY_RANGE_START = 3584

def wpick(rng, items):
    r, acc = rng.random() * sum(w for _, _, w in items), 0.0
    for tag, frag, w in items:
        acc += w
        if r <= acc: return tag, frag
    return items[-1][0], items[-1][1]

def build_spec(rng, role, gender="male"):
    # Bucket-relevant draws (tone, age, build) come FIRST and are one
    # rng.random() each for both genders; hair/facial draws differ after that,
    # which is fine — nothing downstream replays anything past the build draw.
    female = gender == "female"
    tone_t, tone_f = wpick(rng, TONES_F if female else TONES)
    age_t, age_f = wpick(rng, (COACH_AGES_F if female else COACH_AGES) if role == "coach" else PLAYER_AGES)
    build_t, build_f = wpick(rng, BUILDS if role == "player" else COACH_BUILDS)
    if female:
        subject = f"{tone_f} {age_f}, {build_f}, {rng.choice(HAIR_F)}"
    else:
        subject = f"{tone_f} {age_f}, {build_f}, {rng.choice(HAIR)}, {rng.choice(FACIAL)}"
    clothing = COACH_CLOTHING if role == "coach" else PLAYER_CLOTHING
    prompt = f"{subject}. {STYLE.format(clothing=clothing)}"
    return {"role": role, "gender": gender, "ageBand": age_t, "tone": tone_t, "build": build_t}, prompt

# ---------------- backends ----------------
def http_json(url, payload, headers, timeout=180):
    req = urllib.request.Request(url, json.dumps(payload).encode(), {"Content-Type": "application/json", **headers})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())

def fetch(url, timeout=180):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read()

def gen_replicate(prompt, seed):
    tok = os.environ["REPLICATE_API_TOKEN"]
    out = http_json("https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions",
                    {"input": {"prompt": prompt, "seed": seed, "aspect_ratio": "1:1",
                               "output_format": "png", "disable_safety_checker": False}},
                    {"Authorization": f"Bearer {tok}", "Prefer": "wait"})
    urls = out.get("output") or []
    if not urls: raise RuntimeError(f"replicate empty output: {out.get('error')}")
    return fetch(urls[0] if isinstance(urls, list) else urls)

def gen_fal(prompt, seed):
    key = os.environ["FAL_KEY"]
    out = http_json("https://fal.run/fal-ai/flux/schnell",
                    {"prompt": prompt, "seed": seed, "image_size": "square_hd", "num_images": 1},
                    {"Authorization": f"Key {key}"})
    return fetch(out["images"][0]["url"])

def gen_gemini(prompt, seed):
    key = os.environ["GEMINI_API_KEY"]
    out = http_json(f"https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict?key={key}",
                    {"instances": [{"prompt": prompt}],
                     "parameters": {"sampleCount": 1, "aspectRatio": "1:1", "personGeneration": "allow_adult"}}, {})
    return base64.b64decode(out["predictions"][0]["bytesBase64Encoded"])

def gen_openai(prompt, seed):
    key = os.environ["OPENAI_API_KEY"]
    out = http_json("https://api.openai.com/v1/images/generations",
                    {"model": "gpt-image-1", "prompt": prompt, "size": "1024x1024", "n": 1},
                    {"Authorization": f"Bearer {key}"})
    return base64.b64decode(out["data"][0]["b64_json"])

BACKENDS = [("replicate", "REPLICATE_API_TOKEN", gen_replicate),
            ("fal", "FAL_KEY", gen_fal),
            ("gemini", "GEMINI_API_KEY", gen_gemini),
            ("openai", "OPENAI_API_KEY", gen_openai)]

def pick_backend(name):
    for n, env, fn in BACKENDS:
        if (name and n == name and os.environ.get(env)) or (not name and os.environ.get(env)):
            return n, fn
    sys.exit("No image backend credential found. Set one of: " + ", ".join(e for _, e, _ in BACKENDS))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=2048)
    ap.add_argument("--coach-share", type=float, default=0.1875)  # 384/2048
    ap.add_argument("--female-coach-share", type=float, default=0.22)  # of coach faces at/after FEMALE_RANGE_START
    ap.add_argument("--pilot", action="store_true")
    ap.add_argument("--backend", default=None)
    ap.add_argument("--seed", type=int, default=20260729)
    args = ap.parse_args()
    count = 24 if args.pilot else args.count

    os.makedirs(RAW, exist_ok=True)
    manifest = json.load(open(MANIFEST)) if os.path.exists(MANIFEST) else {"seed": args.seed, "faces": []}

    # The QA cull loop (package_faces.py review.html -> culled.json -> "re-run
    # generate_faces.py to backfill culled ids") only works if the culled ids are
    # actually treated as MISSING. Resume skips everything already in the
    # manifest, and a culled face is still in there, so without this the
    # re-generate step was a silent no-op and the id was simply lost from the
    # shipped library — permanently, since the bucket for an id is a pure
    # function of the seed and cannot be produced by any other id.
    #
    # Dropping the entry here is what makes the id re-enter `todo`; the bucket
    # and prompt are re-derived from (seed, id), so the replacement image is the
    # same KIND of face, which is what the app's synthesized catalog assumes.
    # An id is cleared from culled.json only when its replacement image lands
    # (see `work`), so an interrupted run leaves the id pending and
    # package_faces.py keeps skipping it instead of shipping the artifact.
    culled = set(json.load(open(CULLED))) if os.path.exists(CULLED) else set()
    if culled:
        before = len(manifest["faces"])
        manifest["faces"] = [f for f in manifest["faces"] if f["id"] not in culled]
        dropped = before - len(manifest["faces"])
        for fid in sorted(culled):
            png = os.path.join(RAW, f"{fid}.png")
            if os.path.exists(png):
                os.replace(png, png + ".culled")   # kept for the record, out of the way
        if dropped:
            json.dump(manifest, open(MANIFEST, "w"), indent=1)
        print(f"culled.json: {len(culled)} ids marked, {dropped} manifest entries dropped for regeneration")

    have = {f["id"] for f in manifest["faces"]}
    backend_name, backend = pick_backend(args.backend)
    print(f"backend={backend_name} target={count} existing={len(have)}")

    lock = threading.Lock()
    state = {"failures": 0, "done": len(have)}

    def work(i):
        fid = f"face_{i:05d}"
        rng = random.Random(f"{args.seed}:{fid}")
        if i >= FEMALE_ONLY_RANGE_START:
            role, gender = "coach", "female"   # forced facts, no draws — see the constant
        else:
            role = "coach" if rng.random() < args.coach_share else "player"
            gender = "male"
            if i >= FEMALE_RANGE_START and role == "coach":
                gender = "female" if rng.random() < args.female_coach_share else "male"
        bucket, prompt = build_spec(rng, role, gender)
        seed = rng.randrange(1, 2**31)
        for attempt in range(5):
            try:
                time.sleep(random.uniform(0.5, 2.0))  # smooth burst pressure on the API
                data = backend(prompt, seed)
                if len(data) < 20_000: raise RuntimeError(f"suspiciously small image ({len(data)}B)")
                open(os.path.join(RAW, f"{fid}.png"), "wb").write(data)
                with lock:
                    manifest["faces"].append({"id": fid, "file": f"raw/{fid}.png", "bucket": bucket,
                                              "seed": seed, "backend": backend_name,
                                              "sha256": hashlib.sha256(data).hexdigest()[:16], "prompt": prompt})
                    json.dump(manifest, open(MANIFEST, "w"), indent=1)
                    # A regenerated id is no longer culled — culled.json is the
                    # PENDING list, not a history. Leaving it in would make
                    # package_faces.py (which skips culled ids) drop the fresh
                    # image too, i.e. the exact loss the cull loop is meant to
                    # repair. If the replacement is also bad the next review
                    # sweep simply re-adds it.
                    if fid in culled:
                        culled.discard(fid)
                        json.dump(sorted(culled), open(CULLED, "w"), indent=1)
                    state["done"] += 1
                    if state["done"] % 25 == 0:
                        print(f"progress: {state['done']}/{count}", flush=True)
                return
            except Exception as e:
                print(f"{fid} attempt {attempt+1} FAILED: {e}", file=sys.stderr, flush=True)
                time.sleep(12 * (attempt + 1))  # 429s need real backoff, not seconds
        with lock:
            state["failures"] += 1
            if state["failures"] > max(10, count // 10):
                print("Too many failures — aborting (backend/credit problem?)", file=sys.stderr, flush=True)
                os._exit(2)

    todo = [i for i in range(count) if f"face_{i:05d}" not in have]
    with ThreadPoolExecutor(max_workers=3) as pool:
        list(pool.map(work, todo))
    print(f"done: {len(manifest['faces'])} faces in manifest, {state['failures']} failures")

if __name__ == "__main__":
    main()
