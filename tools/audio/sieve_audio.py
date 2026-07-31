#!/usr/bin/env python3
"""
Stage 1 of the Sunday Night Dynasty game-audio pipeline.

Walks the extracted Sonniss GameAudioGDC bundle, sieves every audio file into
the sound categories the game needs (by filename + path keywords), stages the
best candidates per category, renders small AAC previews, and writes a
self-contained review page the user can listen through.

Usage:
    python3 sieve_audio.py --extract-root <dir> [--stage] [--html]
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor

AUDIO_EXTS = {".wav", ".flac", ".ogg", ".aiff", ".aif"}

# Each rule is (category, label, predicate-spec).
# "all" groups mean every term must be present; plain strings are single terms.
# Terms are matched with word boundaries against a normalised path string.
CATEGORIES = {
    "crowd_cheer": [
        "cheer", "cheering", "applause", "ovation",
        ("crowd", "roar"), ("crowd", "applause"), ("crowd", "stadium"),
        ("stadium", "roar"),
    ],
    "crowd_boo": ["boo", "boos", "booing", "jeer", "jeering", "heckle"],
    "crowd_gasp": [
        "gasp", "ooh", "aah", "shock", "reaction", "murmur", "groan",
        ("crowd", "disappointed"),
    ],
    "crowd_bed": [
        ("ambience", "stadium"), ("ambience", "arena"), ("ambience", "crowd"),
        ("ambient", "stadium"), ("ambient", "arena"), ("ambient", "crowd"),
        ("loop", "stadium"), ("loop", "arena"), ("loop", "crowd"),
        # "walla" is the industry term for background crowd murmur; several
        # libraries name the files opaquely (NIG015.wav) and only the folder
        # says "Nigerian Walla", so match it as a standalone term.
        "walla",
    ],
    "chant": ["chant", "chants", "chanting"],
    "impact_tackle": [
        "impact", "thud", "slam", "wallop",
        ("body", "fall"), ("body", "hit"), ("body", "impact"), ("body", "drop"),
        ("punch", "hit"), ("punch", "impact"), ("punch", "body"),
        "football", ("pad", "hit"), ("shoulder", "pad"),
        ("hit", "flesh"), ("tackle",),
    ],
    "kick": ["kick", "punt", ("boot", "ball")],
    "throw_whoosh": ["whoosh", "swish", "swoosh", "throw", "throwing"],
    "catch": [
        "catch", "glove", "leather",
        ("ball", "hand"), ("ball", "catch"),
    ],
    "whistle": ["whistle", "whistling", "referee"],
    "shouts": [
        "shout", "shouting", "yell", "yelling", "grunt", "effort",
        ("male", "voice"), ("male", "vocal"), ("man", "vocal"),
        "cadence", "hut", "holler",
    ],
}

# The keyword sieve above is deliberately broad (it has to be: many libraries
# put the only meaningful words in the folder name). These lists re-rank the
# shortlist toward football-usable audio and push the obvious false positives
# down — musical "impacts", animal "groans", Aztec death whistles, motorcycle
# "kick" starts, leather-jacket "catch" foley.
# Format: category -> (boost terms, penalty terms)
RELEVANCE = {
    "crowd_cheer": (
        ["crowd", "stadium", "arena", "audience", "applause", "sport", "game", "fans", "score"],
        ["cartoon", "synth", "designed", "riser", "magic"]),
    "crowd_boo": (
        ["crowd", "audience", "stadium", "people", "fans", "game"], []),
    "crowd_gasp": (
        ["crowd", "audience", "people", "human", "vocal", "reaction", "applause"],
        ["animal", "camel", "pig", "cow", "horse", "dog", "metal", "ice", "door",
         "wood", "zombie", "creature", "monster", "sheet", "hinge", "engine"]),
    "crowd_bed": (
        ["crowd", "stadium", "arena", "walla", "game", "sport", "audience", "people"],
        ["designed", "synth", "magic"]),
    "chant": (["crowd", "people", "stadium", "protest", "fans", "game"], []),
    "impact_tackle": (
        ["body", "flesh", "punch", "football", "pad", "tackle", "fall", "bone",
         "human", "gravel", "dirt", "grass", "thud", "wrestling"],
        ["drum", "cartoon", "chord", "musical", "synth", "riser", "cinematic",
         "designed", "transition", "glitch", "laser", "magic", "explosion",
         "rock", "metal", "sweep", "vibrato", "reverb", "door", "slime",
         "gore", "boom", "distorted", "rusty", "resonant", "borax", "ui"]),
    "kick": (
        ["ball", "football", "soccer", "punt", "foot", "grass", "leather"],
        ["motorcycle", "motorbike", "engine", "bike", "moped", "scooter",
         "start", "rev", "exhaust", "drum", "door", "idle"]),
    "throw_whoosh": (
        ["throw", "swing", "arm", "air", "fast", "spin"],
        ["magic", "designed", "sci", "laser", "spell"]),
    "catch": (
        ["ball", "football", "glove", "hand", "grab", "mitt"],
        ["bracelet", "jacket", "apparel", "clasp", "shoe", "boot", "wallet",
         "purse", "belt", "squeak", "creak", "door", "fish", "sofa", "chair"]),
    "whistle": (
        ["referee", "ref", "sport", "game", "coach", "pea", "crowd"],
        ["death", "aztec", "firecracker", "train", "kettle", "bird", "wind",
         "bomb", "bullet", "tea", "steam", "designed"]),
    "shouts": (
        ["shout", "yell", "grunt", "effort", "cheer", "crowd", "team",
         "battle", "attack", "exertion", "strain"],
        ["laugh", "cough", "cry", "breathing", "idle", "sneeze", "snore",
         "ghost", "creature", "zombie", "monster", "whisper",
         # "grunt" pulls in a lot of livestock/wildlife foley
         "animal", "anml", "dog", "pig", "camel", "cow", "horse", "cat",
         "bird", "monkey", "bear", "wild", "farm", "dying", "pain"]),
}

# Categories whose ideal asset is a long loop rather than a short stinger.
BED_CATEGORIES = {"crowd_bed"}


def relevance_score(cat, norm_path):
    """+ for football-relevant context words, - for known false-positive context."""
    boost, penalty = RELEVANCE.get(cat, ([], []))
    b = sum(1 for t in boost if has_term(norm_path, t))
    p = sum(1 for t in penalty if has_term(norm_path, t))
    return min(b, 3) * 6.0 - min(p, 3) * 9.0

MAX_PER_CATEGORY = 25
MAX_PER_LIBRARY_PER_CATEGORY = 6
PREVIEW_MAX_SECONDS = 45
PROBE_POOL = 60  # how many ranked candidates to ffprobe per category

_camel = re.compile(r"(?<=[a-z0-9])(?=[A-Z])")
_nonword = re.compile(r"[^a-z0-9]+")


def normalise(text):
    """Lowercase + split camelCase + collapse separators, so word boundaries work."""
    text = _camel.sub(" ", text)
    text = text.lower()
    text = _nonword.sub(" ", text)
    return " " + " ".join(text.split()) + " "


def has_term(norm, term):
    if term == "ooh":
        return re.search(r"\bo{2,}h\b", norm) is not None
    if term == "aah":
        return re.search(r"\ba{2,}h\b", norm) is not None
    return re.search(r"\b" + re.escape(term) + r"\b", norm) is not None


def match_categories(rel_path, filename):
    """Return {category: matched-keyword} for every category this file matches."""
    norm_all = normalise(rel_path)
    norm_name = normalise(filename)
    hits = {}
    for cat, rules in CATEGORIES.items():
        for rule in rules:
            terms = (rule,) if isinstance(rule, str) else rule
            if all(has_term(norm_all, t) for t in terms):
                label = "+".join(terms)
                in_name = all(has_term(norm_name, t) for t in terms)
                # Prefer a filename-level hit if we find one later in the rule list.
                if cat not in hits or (in_name and not hits[cat][1]):
                    hits[cat] = (label, in_name)
    return {c: v for c, v in hits.items()}


def scan(extract_root):
    files = []
    for dirpath, dirnames, filenames in os.walk(extract_root):
        dirnames[:] = [d for d in dirnames if not d.startswith("__MACOSX")]
        for fn in filenames:
            if fn.startswith("._"):
                continue
            if os.path.splitext(fn)[1].lower() not in AUDIO_EXTS:
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, extract_root)
            files.append((full, rel, fn))
    return files


def library_of(rel):
    parts = rel.split(os.sep)
    # Sonniss layout: <Bundle part>/<Publisher>/... — use the publisher when present.
    for p in parts[:-1]:
        if p and not re.match(r"^Sonniss", p, re.I):
            return p
    return parts[0] if parts else "unknown"


def ffprobe_duration(path):
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nw=1:nk=1", path],
            capture_output=True, text=True, timeout=30,
        )
        return float(out.stdout.strip())
    except Exception:
        return None


def name_quality(fn):
    """Cheap pre-ffprobe ranking: short, clean, descriptive names score higher."""
    base = os.path.splitext(fn)[0]
    score = 0.0
    if len(base) <= 40:
        score += 3
    if len(base) <= 25:
        score += 2
    # Penalise long serial-number style names.
    digits = sum(c.isdigit() for c in base)
    score -= digits * 0.15
    return score


def dedupe_key(fn):
    base = os.path.splitext(fn)[0].lower()
    base = re.sub(r"[\s_\-.]*\d+\s*$", "", base)       # trailing take numbers
    base = re.sub(r"[\s_\-.]*(take|var|v)\s*\d*$", "", base)
    return _nonword.sub(" ", base).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--extract-root", required=True)
    ap.add_argument("--out-root", default=os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--stage", action="store_true")
    ap.add_argument("--html", action="store_true")
    args = ap.parse_args()

    extract_root = os.path.abspath(args.extract_root)
    out_root = os.path.abspath(args.out_root)
    staging_root = os.path.join(out_root, "staging")
    os.makedirs(out_root, exist_ok=True)

    print(f"scanning {extract_root} ...", flush=True)
    files = scan(extract_root)
    print(f"  {len(files)} audio files found", flush=True)

    # ---- sieve -----------------------------------------------------------
    buckets = defaultdict(list)
    for full, rel, fn in files:
        for cat, (kw, in_name) in match_categories(rel, fn).items():
            buckets[cat].append({
                "path": full, "rel": rel, "file": fn,
                "keyword": kw, "in_name": in_name,
                "library": library_of(rel),
                "size": os.path.getsize(full),
            })

    print("\n=== sieve counts ===")
    for cat in CATEGORIES:
        print(f"  {cat:16s} {len(buckets.get(cat, [])):6d}")

    sieve_summary = {c: len(buckets.get(c, [])) for c in CATEGORIES}
    with open(os.path.join(out_root, "sieve_report.json"), "w") as fh:
        json.dump({
            "extract_root": extract_root,
            "total_audio_files": len(files),
            "counts": sieve_summary,
        }, fh, indent=2)

    if not args.stage:
        return

    # ---- rank, probe, select --------------------------------------------
    selected = {}
    for cat in CATEGORIES:
        cands = buckets.get(cat, [])
        if not cands:
            selected[cat] = []
            continue

        # Pre-rank cheaply so we only ffprobe a shortlist.
        for c in cands:
            c["relevance"] = relevance_score(cat, normalise(c["rel"]))
            c["prescore"] = ((10 if c["in_name"] else 0)
                             + name_quality(c["file"]) + c["relevance"])
        cands.sort(key=lambda c: -c["prescore"])

        # Spread across libraries + drop near-identical names before probing.
        seen_keys, per_lib, shortlist = set(), defaultdict(int), []
        for c in cands:
            k = (c["library"], dedupe_key(c["file"]))
            if k in seen_keys:
                continue
            if per_lib[c["library"]] >= MAX_PER_LIBRARY_PER_CATEGORY:
                continue
            seen_keys.add(k)
            per_lib[c["library"]] += 1
            shortlist.append(c)
            if len(shortlist) >= PROBE_POOL:
                break

        print(f"probing {len(shortlist)} candidates for {cat} ...", flush=True)
        with ThreadPoolExecutor(max_workers=8) as ex:
            durs = list(ex.map(lambda c: ffprobe_duration(c["path"]), shortlist))
        for c, d in zip(shortlist, durs):
            c["duration"] = d

        is_bed = cat in BED_CATEGORIES
        scored = []
        for c in shortlist:
            d = c["duration"]
            if d is None or d <= 0:
                continue
            s = c["prescore"]
            if is_bed:
                s += 8 if d >= 20 else (3 if d >= 10 else -4)
            else:
                if 0.2 <= d <= 15:
                    s += 8
                elif d <= 30:
                    s += 2
                else:
                    s -= 6
            scored.append((s, c))
        scored.sort(key=lambda t: -t[0])
        selected[cat] = [c for _, c in scored[:MAX_PER_CATEGORY]]

    # ---- stage + previews ------------------------------------------------
    jobs = []
    for cat, items in selected.items():
        cdir = os.path.join(staging_root, cat)
        os.makedirs(cdir, exist_ok=True)
        for i, c in enumerate(items):
            stem = re.sub(r"[^A-Za-z0-9._-]+", "_", os.path.splitext(c["file"])[0])[:60]
            stem = f"{i:02d}_{stem}"
            dst = os.path.join(cdir, stem + os.path.splitext(c["file"])[1].lower())
            prev = os.path.join(cdir, stem + ".m4a")
            c["staged"] = dst
            c["preview"] = prev
            jobs.append((c, dst, prev))

    def do_job(job):
        c, dst, prev = job
        if not os.path.exists(dst):
            shutil.copy2(c["path"], dst)
        if not os.path.exists(prev):
            cmd = ["ffmpeg", "-nostdin", "-v", "error", "-y", "-i", c["path"]]
            if c["duration"] and c["duration"] > PREVIEW_MAX_SECONDS:
                cmd += ["-t", str(PREVIEW_MAX_SECONDS)]
                c["preview_truncated"] = True
            # Several libraries embed cover art as a video stream inside the
            # .wav; muxing that into an .m4a fails and leaves a 0-byte file.
            # -vn + explicit audio map keeps only the first audio stream.
            cmd += ["-vn", "-map", "0:a:0",
                    "-c:a", "aac", "-b:a", "96k", "-ac", "2", prev]
            r = subprocess.run(cmd, capture_output=True, timeout=300)
            if r.returncode != 0 or not os.path.getsize(prev):
                print(f"  preview FAILED: {os.path.basename(prev)} "
                      f"{r.stderr.decode('utf-8','ignore').strip().splitlines()[-1:]}")
        return c

    print(f"\nstaging + encoding {len(jobs)} previews ...", flush=True)
    with ThreadPoolExecutor(max_workers=6) as ex:
        list(ex.map(do_job, jobs))

    manifest = {
        cat: [{
            "file": c["file"], "rel": c["rel"], "library": c["library"],
            "keyword": c["keyword"], "duration": c.get("duration"),
            "size": c["size"], "relevance": c.get("relevance", 0),
            "staged": os.path.relpath(c["staged"], out_root),
            "preview": os.path.relpath(c["preview"], out_root),
            "preview_truncated": c.get("preview_truncated", False),
            "source_path": c["path"],
        } for c in items]
        for cat, items in selected.items()
    }
    with open(os.path.join(out_root, "staging_manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=2)

    print("\n=== staged counts ===")
    for cat in CATEGORIES:
        print(f"  {cat:16s} {len(manifest.get(cat, [])):4d}")

    if args.html:
        write_html(manifest, sieve_summary, out_root)


def write_html(manifest, sieve_summary, out_root):
    esc = lambda s: (str(s).replace("&", "&amp;").replace("<", "&lt;")
                     .replace(">", "&gt;").replace('"', "&quot;"))
    total = sum(len(v) for v in manifest.values())
    empty = [c for c in CATEGORIES if not manifest.get(c)]
    # "Weak" = matched on a keyword, but nothing in the shortlist actually looks
    # like football audio (e.g. kick -> motorcycle kick-start). Treat these the
    # same as empty when building the bespoke list.
    weak = [c for c in CATEGORIES
            if manifest.get(c) and max(i.get("relevance", 0) for i in manifest[c]) <= 0]

    parts = ["""<meta charset="utf-8"><title>Dynasty — game audio candidates</title>
<style>
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;margin:0;background:#12151a;color:#e8ecf1}
header{position:sticky;top:0;background:#0d1014;border-bottom:1px solid #2a3140;padding:14px 20px;z-index:10}
h1{margin:0 0 4px;font-size:19px}
.sub{color:#8b97a8;font-size:12px}
button{background:#2d6cdf;color:#fff;border:0;border-radius:6px;padding:8px 14px;font-size:13px;cursor:pointer;margin-right:8px}
button:hover{background:#3d7cef}
h2{margin:26px 20px 8px;font-size:15px;color:#7fd4a0;border-bottom:1px solid #2a3140;padding-bottom:6px}
table{width:calc(100% - 40px);margin:0 20px;border-collapse:collapse;font-size:12px}
td{padding:5px 8px;border-bottom:1px solid #1e242e;vertical-align:middle}
tr:hover{background:#181d25}
.fn{font-family:ui-monospace,Menlo,monospace;color:#dfe6ee;max-width:330px;overflow-wrap:anywhere}
.lib{color:#8b97a8;max-width:190px;overflow-wrap:anywhere}
.kw{color:#e0b050;font-family:ui-monospace,Menlo,monospace;font-size:11px}
.dur{color:#8b97a8;text-align:right;white-space:nowrap}
.trunc{color:#c98}
audio{height:30px;vertical-align:middle}
.empty{margin:6px 20px;color:#e0806a;font-size:12px}
#out{width:calc(100% - 40px);margin:10px 20px;height:130px;background:#0b0e12;color:#9fe8b8;
border:1px solid #2a3140;border-radius:6px;font-family:ui-monospace,Menlo,monospace;font-size:11px;display:none;padding:8px}
</style>
<header>
<h1>Dynasty — game audio candidates</h1>
<div class="sub">Sonniss GameAudioGDC &mdash; full 2026 bundle + 8 archive-year parts (28.8 GB) &middot; """
+ f"{total} staged clips across {len(CATEGORIES)} categories" + """ &middot;
tick what you want to keep, then copy the list (category + source path per line)</div>
<div style="margin-top:10px">
<button onclick="copySel()">Copy selected list</button>
<button onclick="document.querySelectorAll('input[type=checkbox]').forEach(c=>c.checked=false);count()">Clear all</button>
<span id="n" class="sub"></span>
</div>
</header>
<textarea id="out" readonly></textarea>
"""]

    if empty:
        parts.append('<div class="empty"><b>Zero candidates</b> (bespoke / ElevenLabs list): '
                     + esc(", ".join(empty)) + "</div>")
    if weak:
        parts.append('<div class="empty"><b>Keyword hits only, nothing football-usable</b> '
                     '&mdash; treat as bespoke too: ' + esc(", ".join(weak)) + "</div>")

    for cat in CATEGORIES:
        items = manifest.get(cat, [])
        parts.append(f'<h2>{esc(cat)} &mdash; {len(items)} staged '
                     f'<span class="sub">({sieve_summary.get(cat,0)} matched in bundle)</span></h2>')
        if not items:
            parts.append('<div class="empty">no candidates found &mdash; needs bespoke audio</div>')
            continue
        if cat in weak:
            parts.append('<div class="empty">heads-up: these matched the keyword but none look '
                         'like real football audio &mdash; likely all false positives</div>')
        parts.append("<table>")
        for it in items:
            d = it.get("duration")
            dur = f"{d:.2f}s" if d else "?"
            tr = ' <span class="trunc">(preview 45s)</span>' if it.get("preview_truncated") else ""
            parts.append(
                "<tr>"
                f'<td><input type="checkbox" value="{esc(it["source_path"])}"></td>'
                f'<td class="fn">{esc(it["file"])}</td>'
                f'<td class="dur">{dur}{tr}</td>'
                f'<td class="lib">{esc(it["library"])}</td>'
                f'<td class="kw">{esc(it["keyword"])}</td>'
                f'<td><audio controls preload="none" src="{esc(it["preview"])}"></audio></td>'
                "</tr>")
        parts.append("</table>")

    parts.append("""
<script>
function count(){document.getElementById('n').textContent=
 document.querySelectorAll('input[type=checkbox]:checked').length+' selected';}
document.addEventListener('change',count);
function copySel(){
 const rows=[...document.querySelectorAll('input[type=checkbox]:checked')].map(c=>{
   const cat=c.closest('table').previousElementSibling.textContent.split('\\u2014')[0].trim();
   return cat+'\\t'+c.value;});
 const t=rows.join('\\n');
 const o=document.getElementById('out');o.style.display='block';o.value=t;
 navigator.clipboard.writeText(t).then(()=>{},()=>{o.select();});
 count();
}
count();
</script>""")

    path = os.path.join(out_root, "review_audio.html")
    with open(path, "w") as fh:
        fh.write("\n".join(parts))
    print(f"\nreview page -> {path}")


if __name__ == "__main__":
    main()
