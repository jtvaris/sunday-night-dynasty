#!/usr/bin/env python3
"""Aged face variants — the library's "same person, ten years later" pass.

The main pool paints every person once, at the age his bucket says. A career
runs 20+ seasons: the 26-year-old whose portrait shipped in the `25-29` band is
34 by season 8 and still wearing a rookie's face, and a head coach hired at 48
is 63 with no gray in him. This pass generates ONE older variant per source id
and the app swaps to it when the person crosses a threshold
(`AgedFaceCatalog.playerAgeThreshold` / `coachAgeThreshold`).

  python3 generate_aged.py --role coach --limit 48        # the pilot
  python3 generate_aged.py --role all                     # the full run
  python3 generate_aged.py --package                      # -> out/AgedFaces/*.heic

Identity strategy (and its known limit). A variant reuses the source's SEED and
its whole prompt except the age clause, which is rewritten by table
(`AGE_REWRITES`). FLUX schnell is text-to-image, not an editing model, so this
buys *bucket* continuity — same tone, build, hair, framing, lighting, wardrobe —
and only partial *identity* continuity. Whether that is close enough is a
judgement call the pilot exists to answer; see docs/FACE_AGE_VARIANTS.md.

Nothing here touches manifest.json, raw/ or the packaged Faces/ — an aged run
is purely additive, and deleting `aged_manifest.json` + `raw_aged/` reverts it.
"""
import argparse
import json
import os
import random
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import generate_faces as gf

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, "raw_aged")
MANIFEST = os.path.join(ROOT, "aged_manifest.json")
SOURCE_MANIFEST = os.path.join(ROOT, "manifest.json")
CULLED = os.path.join(ROOT, "culled_aged.json")
OUT = os.path.join(ROOT, "out", "AgedFaces")

# Id prefix. `aged_face_00007` is the variant of `face_00007` — the source id is
# recoverable by string alone, which is what lets the Swift catalog degrade to
# "no variant" without a manifest lookup.
PREFIX = "aged_"

# The age clause each band was painted with -> the clause its variant is painted
# with, the band tag the variant's bucket carries, and whether the hairstyle
# token should be grayed (see HAIR_AGE).
#
# Keyed by the EXACT fragment `generate_faces.build_spec` composed, so a rewrite
# is a substring replacement with no parsing and no guessing. A source prompt
# that does not contain its band's fragment is skipped and counted, never
# rewritten on a fallback — a wrong age clause would silently paint a stranger.
#
# Targets are absolute, not relative: a player variant is "mid thirties"
# whatever band he came from (34 is the threshold, and nobody in this game plays
# to 45), while a coach's depends on where he started, because a 45-year-old
# coordinator crossing 62 and a 58-year-old head coach crossing 62 are ten years
# apart in the source picture.
#
# PROMPT VERSION 2. v1 put the gray in the AGE clause ("mostly gray hair",
# "silver gray hair"). That clause sits before the hairstyle token
# `build_spec` appended, and in FLUX it beat it: a "buzz cut" source came back
# with a full silver mane, a "bald head" source grew hair, and — because a
# silver mane is a white-coded feature in the model's prior — dark-skinned
# subjects came back several shades lighter. Three failure modes, one cause.
# v2 states no hair volume at all in the age clause and grays the SOURCE's own
# hairstyle token in place instead, so the style survives the decade.
AGE_REWRITES = {
    ("player", "male", "20-24"): (
        "in his early twenties",
        "in his mid thirties, gray flecks at the temples, weathered veteran face",
        "34-40", False),
    ("player", "male", "25-29"): (
        "in his late twenties",
        "in his mid thirties, gray flecks at the temples, weathered veteran face",
        "34-40", False),
    ("player", "male", "30-36"): (
        "in his early thirties",
        "in his late thirties, gray at the temples, weathered veteran face, lined forehead",
        "34-40", False),
    ("coach", "male", "38-50"): (
        "in his mid forties",
        "in his early sixties, weathered lined face",
        "62-72", True),
    ("coach", "male", "50-68"): (
        "in his late fifties, some gray hair",
        "in his late sixties, weathered face with deep lines",
        "62-75", True),
    ("coach", "female", "38-50"): (
        "in her mid forties",
        "in her early sixties, weathered lined face",
        "62-72", True),
    ("coach", "female", "50-68"): (
        "in her late fifties, some gray hair",
        "in her late sixties, weathered face with deep lines",
        "62-75", True),
}

# Hairstyle token -> its grayed form. Keys are verbatim `generate_faces.HAIR` /
# `HAIR_F` entries; the value keeps the CUT and changes only its color (plus the
# one recession cue a sixty-year-old earns), because the cut is the single
# strongest "same man" cue a text-to-image model carries across two renders.
# `bald head` deliberately stays bald.
HAIR_AGE = {
    "short cropped hair": "short cropped gray hair",
    "buzz cut": "gray buzz cut",
    "short dreadlocks": "short gray dreadlocks",
    "medium afro": "medium gray afro",
    "bald head": "bald head, short gray fringe above the ears",
    "short curly hair": "short curly gray hair",
    "short straight hair": "short straight gray hair, thinning",
    "fade haircut": "gray fade haircut",
    "shoulder-length straight hair": "shoulder-length straight gray hair",
    "curly shoulder-length hair": "curly shoulder-length gray hair",
    "long braids": "long gray braids",
    "natural afro": "natural gray afro",
    "hair in a tight bun": "gray hair in a tight bun",
    "short pixie cut": "short gray pixie cut",
    "long straight hair tied back": "long gray hair tied back",
    "medium wavy hair": "medium wavy gray hair",
}
# Longest first: several keys are substrings of nothing here today, but a future
# HAIR entry that overlaps an existing one must not be half-replaced.
HAIR_AGE_ORDER = sorted(HAIR_AGE, key=len, reverse=True)

PROMPT_VERSION = 2


def aged_id(source_id):
    return PREFIX + source_id


def source_id(aged):
    return aged[len(PREFIX):] if aged.startswith(PREFIX) else aged


def rewrite(entry):
    """(aged_id, bucket, prompt, seed) for one source face, or None if its
    prompt does not carry the age clause its bucket claims."""
    bucket = entry["bucket"]
    key = (bucket["role"], bucket.get("gender", "male"), bucket["ageBand"])
    rule = AGE_REWRITES.get(key)
    if rule is None:
        return None
    old, new, band, gray_hair = rule
    prompt = entry.get("prompt", "")
    if old not in prompt:
        return None
    prompt = prompt.replace(old, new, 1)
    if gray_hair:
        # Best-effort: a source whose hairstyle token we do not recognise still
        # ages (the face clause did its work), it just keeps its hair color.
        for token in HAIR_AGE_ORDER:
            if token in prompt:
                prompt = prompt.replace(token, HAIR_AGE[token], 1)
                break
    aged_bucket = {**bucket, "gender": bucket.get("gender", "male"), "ageBand": band}
    return aged_id(entry["id"]), aged_bucket, prompt, entry["seed"]


# ---------------------------------------------------------------------------
# selection
# ---------------------------------------------------------------------------


def select(faces, role, limit, seed):
    """The ids to age, most-used bucket first.

    `--limit` is a PILOT control, so the subset it returns has to look like the
    population rather than like its first N ids: the sample is drawn
    proportionally per (gender, ageBand, tone) bucket and only then truncated.
    Deterministic for a given (role, limit, seed) so a re-run resumes on the
    same set instead of buying a second, different sample.
    """
    pool = [f for f in faces
            if (role == "all" or f["bucket"]["role"] == role)
            and rewrite(f) is not None]
    pool.sort(key=lambda f: f["id"])
    if limit is None or limit >= len(pool):
        return pool

    groups = {}
    for f in pool:
        b = f["bucket"]
        groups.setdefault((b.get("gender", "male"), b["ageBand"], b["tone"]), []).append(f)

    rng = random.Random(f"aged-select:{seed}:{role}:{limit}")
    picked, ordered = [], sorted(groups.items())
    for key, members in ordered:
        share = limit * len(members) / len(pool)
        take = min(len(members), int(share))
        picked += rng.sample(members, take) if take else []
    # Integer truncation leaves a remainder; fill it from the largest buckets so
    # the shortfall lands where the population is densest, not alphabetically.
    if len(picked) < limit:
        chosen = {f["id"] for f in picked}
        rest = [f for _, members in sorted(ordered, key=lambda kv: -len(kv[1]))
                for f in members if f["id"] not in chosen]
        picked += rest[:limit - len(picked)]
    picked.sort(key=lambda f: f["id"])
    return picked[:limit]


# ---------------------------------------------------------------------------
# packaging
# ---------------------------------------------------------------------------


def package(manifest):
    """Same 384² HEIC treatment `package_faces.py` gives the main pool, into its
    own out/ dir and its own manifest so neither can overwrite the other."""
    os.makedirs(OUT, exist_ok=True)
    culled = set(json.load(open(CULLED))) if os.path.exists(CULLED) else set()

    def convert(f):
        if f["id"] in culled:
            return None
        src = os.path.join(ROOT, f["file"])
        dst = os.path.join(OUT, f["id"] + ".heic")
        if not os.path.exists(dst):
            r = subprocess.run(["sips", "-s", "format", "heic", "-s", "formatOptions", "80",
                                "-z", "384", "384", src, "--out", dst], capture_output=True)
            if r.returncode != 0 or not os.path.exists(dst):
                print(f"SKIP {f['id']}: sips failed", file=sys.stderr)
                return None
        return {"id": f["id"], "file": f"Faces/{f['id']}.heic",
                "bucket": f["bucket"], "source": f["source"]}

    # One `sips` process per image, 8 at a time: the full pass is 3 700 spawns and
    # serially that is a coffee break for no reason.
    with ThreadPoolExecutor(max_workers=8) as pool:
        out_faces = [r for r in pool.map(convert, manifest["faces"]) if r]
    path = os.path.join(ROOT, "out", "aged_faces_manifest.json")
    json.dump({"version": 1, "faces": out_faces}, open(path, "w"), indent=1)
    print(f"packaged {len(out_faces)} aged faces -> {OUT}")
    print(f"manifest -> {path}")


def review_html(manifest):
    """Side-by-side contact sheet: source left, variant right. The pilot verdict
    is a LOOK, so the sheet pairs them rather than listing the variants alone."""
    rows = "".join(
        f'<div class="c"><img src="../raw/{f["source"]}.png" loading="lazy">'
        f'<img src="../raw_aged/{f["id"]}.png" loading="lazy"><br>'
        f'<small>{f["source"]} &rarr; {f["bucket"]["ageBand"]} '
        f'({f["bucket"]["role"]}/{f["bucket"]["gender"]}/{f["bucket"]["tone"]})</small>'
        f'<br><label><input type="checkbox" data-id="{f["id"]}">cull</label></div>'
        for f in manifest["faces"])
    html = ("<style>.c{display:inline-block;margin:6px;text-align:center;"
            "font-family:sans-serif}img{width:180px;border-radius:8px;margin:0 2px}</style>"
            f"<h2>Aged variants — {len(manifest['faces'])} pairs (source left, aged right)</h2>"
            + rows +
            '<hr><textarea id="o" rows="4" cols="80"></textarea>'
            '<script>document.addEventListener("change",()=>{o.value=JSON.stringify('
            '[...document.querySelectorAll("input:checked")].map(i=>i.dataset.id))})</script>')
    path = os.path.join(ROOT, "out", "review_aged.html")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(html)
    print(f"review sheet -> {path}")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--role", default="coach", choices=["coach", "player", "all"])
    ap.add_argument("--limit", type=int, default=None, help="pilot size; omit for the whole role")
    ap.add_argument("--backend", default=None)
    ap.add_argument("--seed", type=int, default=20260730)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--package", action="store_true", help="package what already exists and exit")
    ap.add_argument("--reconcile", action="store_true",
                    help="adopt raw_aged/*.png that exist but are not in the manifest, and exit")
    ap.add_argument("--dry-run", action="store_true", help="print the plan, generate nothing")
    args = ap.parse_args()

    manifest = (json.load(open(MANIFEST)) if os.path.exists(MANIFEST)
                else {"version": 1, "seed": args.seed, "faces": []})

    if args.package:
        package(manifest)
        review_html(manifest)
        return 0

    if args.reconcile:
        # The manifest is written once, when a run finishes. A sweep that is
        # killed mid-flight (the harness times long jobs out; the 6/min throttle
        # below $5 of Replicate credit makes a full pass take hours) therefore
        # leaves hundreds of PAID images on disk that no manifest lists — and the
        # next run cannot tell them from ids it never painted, because resume
        # keys on the manifest. Adopting them is pure bookkeeping: the entry is a
        # deterministic function of (source manifest, rewrite table), which is
        # exactly what `work` would have recorded.
        source = json.load(open(SOURCE_MANIFEST))
        have = {f["id"] for f in manifest["faces"]}
        adopted = 0
        for entry in source["faces"]:
            spec = rewrite(entry)
            if spec is None or spec[0] in have:
                continue
            fid, bucket, prompt, seed = spec
            if not os.path.exists(os.path.join(RAW, fid + ".png")):
                continue
            manifest["faces"].append({"id": fid, "file": f"raw_aged/{fid}.png",
                                      "bucket": bucket, "seed": seed,
                                      "backend": "replicate", "prompt": prompt,
                                      "source": entry["id"],
                                      "promptVersion": PROMPT_VERSION})
            adopted += 1
        manifest["faces"].sort(key=lambda f: f["id"])
        json.dump(manifest, open(MANIFEST, "w"), indent=1)
        print(f"reconciled {adopted} on-disk variants; manifest now {len(manifest['faces'])}")
        return 0

    # A manifest carrying images painted by an older prompt table would resume
    # into a MIXED pool — half the coaches aged one way, half another — and
    # nothing downstream could tell them apart. Refuse rather than blend.
    stale = [f for f in manifest["faces"] if f.get("promptVersion", 1) != PROMPT_VERSION]
    if stale:
        sys.exit(f"{MANIFEST} holds {len(stale)} variant(s) from prompt version "
                 f"{stale[0].get('promptVersion', 1)} (current: {PROMPT_VERSION}). "
                 "Archive raw_aged/ + aged_manifest.json and start clean.")

    source = json.load(open(SOURCE_MANIFEST))
    chosen = select(source["faces"], args.role, args.limit, args.seed)
    have = {f["id"] for f in manifest["faces"]}
    todo = [f for f in chosen if aged_id(f["id"]) not in have]

    print(f"aged run: role={args.role} selected={len(chosen)} already={len(chosen)-len(todo)} "
          f"todo={len(todo)}  est. ${len(todo)*0.003:.2f} at FLUX-schnell rates")
    if args.dry_run or not todo:
        for f in todo[:5]:
            spec = rewrite(f)
            print(f"  {spec[0]}: {spec[2][:150]}…")
        return 0

    os.makedirs(RAW, exist_ok=True)
    backend_name, gen = gf.pick_backend(args.backend)
    print(f"backend: {backend_name}")

    lock = __import__("threading").Lock()
    done = [0]

    def work(entry):
        spec = rewrite(entry)
        if spec is None:
            return None
        fid, bucket, prompt, seed = spec
        path = os.path.join(RAW, fid + ".png")
        if not os.path.exists(path):
            # gf.fetch already retries the download; this second ring covers the
            # rarer "prediction returned no output at all" case, which needs a
            # fresh (paid) prediction. Two tries, then leave the id for the next
            # resume rather than hammering a backend that is having a bad minute.
            data = None
            for attempt in range(2):
                try:
                    data = gen(prompt, seed)
                    break
                except Exception as exc:                  # noqa: BLE001
                    print(f"  {'FAIL' if attempt else 'retry'} {fid}: "
                          f"{type(exc).__name__} {exc}", file=sys.stderr)
            if data is None:
                return None
            # Same contract as generate_faces.py: an entry lands in the manifest
            # only after its bytes exist on disk, so a crashed run resumes
            # cleanly instead of claiming faces it never painted.
            open(path, "wb").write(data)
        with lock:
            done[0] += 1
            if done[0] % 10 == 0:
                print(f"  {done[0]}/{len(todo)}")
        return {"id": fid, "file": f"raw_aged/{fid}.png", "bucket": bucket,
                "seed": seed, "backend": backend_name, "prompt": prompt,
                "source": entry["id"], "promptVersion": PROMPT_VERSION}

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = [r for r in pool.map(work, todo) if r]

    manifest["faces"] += results
    manifest["faces"].sort(key=lambda f: f["id"])
    json.dump(manifest, open(MANIFEST, "w"), indent=1)
    print(f"wrote {len(results)} new variants; manifest now {len(manifest['faces'])}")
    review_html(manifest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
