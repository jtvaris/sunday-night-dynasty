#!/usr/bin/env python3
"""Package generated faces for the app bundle.

- center-crop + resize to 384x384 HEIC via macOS `sips` (no extra deps)
- exact-duplicate detection (sha256 of raw bytes)
- emits out/Faces/<id>.heic + out/faces_manifest.json (id, tags, file)
- emits review.html contact sheet for the human QA sweep (cull -> culled.json,
  then re-run generate_faces.py to backfill culled ids)
"""
import json, os, subprocess, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW_MANIFEST = os.path.join(ROOT, "manifest.json")
OUT = os.path.join(ROOT, "out")
FACES = os.path.join(OUT, "Faces")
CULLED = os.path.join(ROOT, "culled.json")
SIZE = "384"

def main():
    m = json.load(open(RAW_MANIFEST))
    culled = set(json.load(open(CULLED))) if os.path.exists(CULLED) else set()
    os.makedirs(FACES, exist_ok=True)
    seen_hash, out_faces, dupes = {}, [], []
    for f in m["faces"]:
        if f["id"] in culled: continue
        h = f.get("sha256")
        if h in seen_hash:
            dupes.append((f["id"], seen_hash[h])); continue
        seen_hash[h] = f["id"]
        src = os.path.join(ROOT, f["file"])
        dst = os.path.join(FACES, f["id"] + ".heic")
        if not os.path.exists(dst):
            r = subprocess.run(["sips", "-s", "format", "heic", "-s", "formatOptions", "80",
                                "-z", SIZE, SIZE, src, "--out", dst], capture_output=True)
            if r.returncode != 0 or not os.path.exists(dst):
                print(f"SKIP {f['id']}: sips failed: {r.stderr.decode()[:120]}", file=sys.stderr); continue
        out_faces.append({"id": f["id"], "file": f"Faces/{f['id']}.heic", "bucket": f["bucket"]})
    json.dump({"version": 1, "seed": m.get("seed"), "faces": out_faces},
              open(os.path.join(OUT, "faces_manifest.json"), "w"), indent=1)

    # gender is in the caption because the one defect the sweep exists to catch
    # on the extended range (ids 2560+) is "the prompt said woman, the model
    # rendered a man" — invisible without it. by_id keeps the row build linear:
    # the two `next(...)` scans it replaces were ~13M comparisons at 3584 faces.
    by_id = {x["id"]: x for x in m["faces"]}
    rows = "".join(
        f'<div class="c"><img src="../{raw["file"]}" loading="lazy"><br>'
        f'<small>{o["id"]}<br>{b["role"]}/{b.get("gender", "male")}/'
        f'{b["ageBand"]}/{b["tone"]}/{b["build"]}</small>'
        f'<br><label><input type="checkbox" data-id="{o["id"]}">cull</label></div>'
        for o in out_faces
        for raw in [by_id[o["id"]]]
        for b in [raw["bucket"]])
    html = ("<style>.c{display:inline-block;width:200px;margin:4px;text-align:center;font-family:sans-serif}"
            "img{width:192px;border-radius:8px}</style>"
            f"<h2>Face review — {len(out_faces)} faces (dupes removed: {len(dupes)})</h2>"
            "<p>Tick faces to cull, then copy the JSON from the box below into culled.json and re-run both scripts.</p>"
            + rows +
            '<hr><textarea id="o" rows="4" cols="80"></textarea>'
            '<script>document.addEventListener("change",()=>{o.value=JSON.stringify('
            '[...document.querySelectorAll("input:checked")].map(c=>c.dataset.id))});</script>')
    open(os.path.join(OUT, "review.html"), "w").write(html)
    print(f"packaged {len(out_faces)} faces -> {FACES}; dupes {len(dupes)}; review: out/review.html")

if __name__ == "__main__":
    main()
