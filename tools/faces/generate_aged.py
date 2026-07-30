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
# with, plus the band tag the variant's bucket carries.
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
AGE_REWRITES = {
    ("player", "male", "20-24"): (
        "in his early twenties",
        "in his mid thirties, gray flecks at the temples, weathered veteran face",
        "34-40"),
    ("player", "male", "25-29"): (
        "in his late twenties",
        "in his mid thirties, gray flecks at the temples, weathered veteran face",
        "34-40"),
    ("player", "male", "30-36"): (
        "in his early thirties",
        "in his late thirties, gray at the temples, weathered veteran face, lined forehead",
        "34-40"),
    ("coach", "male", "38-50"): (
        "in his mid forties",
        "in his early sixties, mostly gray hair, weathered lined face",
        "62-72"),
    ("coach", "male", "50-68"): (
        "in his late fifties, some gray hair",
        "in his late sixties, silver gray hair, weathered face with deep lines",
        "62-75"),
    ("coach", "female", "38-50"): (
        "in her mid forties",
        "in her early sixties, mostly gray hair, weathered lined face",
        "62-72"),
    ("coach", "female", "50-68"): (
        "in her late fifties, some gray hair",
        "in her late sixties, silver gray hair, weathered face with deep lines",
        "62-75"),
}


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
    old, new, band = rule
    prompt = entry.get("prompt", "")
    if old not in prompt:
        return None
    aged_bucket = {**bucket, "gender": bucket.get("gender", "male"), "ageBand": band}
    return aged_id(entry["id"]), aged_bucket, prompt.replace(old, new, 1), entry["seed"]


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
    out_faces = []
    for f in manifest["faces"]:
        if f["id"] in culled:
            continue
        src = os.path.join(ROOT, f["file"])
        dst = os.path.join(OUT, f["id"] + ".heic")
        if not os.path.exists(dst):
            r = subprocess.run(["sips", "-s", "format", "heic", "-s", "formatOptions", "80",
                                "-z", "384", "384", src, "--out", dst], capture_output=True)
            if r.returncode != 0 or not os.path.exists(dst):
                print(f"SKIP {f['id']}: sips failed", file=sys.stderr)
                continue
        out_faces.append({"id": f["id"], "file": f"Faces/{f['id']}.heic",
                          "bucket": f["bucket"], "source": f["source"]})
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
    ap.add_argument("--dry-run", action="store_true", help="print the plan, generate nothing")
    args = ap.parse_args()

    manifest = (json.load(open(MANIFEST)) if os.path.exists(MANIFEST)
                else {"version": 1, "seed": args.seed, "faces": []})

    if args.package:
        package(manifest)
        review_html(manifest)
        return 0

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
            try:
                data = gen(prompt, seed)
            except Exception as exc:                      # noqa: BLE001
                print(f"  FAIL {fid}: {type(exc).__name__} {exc}", file=sys.stderr)
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
                "source": entry["id"]}

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
