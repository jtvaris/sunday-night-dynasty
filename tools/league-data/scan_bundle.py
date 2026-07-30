#!/usr/bin/env python3
"""Anonymization bundle gate — scans a built `.app` for real-identity leaks.

Enforces `docs/ANONYMIZATION_SPEC.md` §6.2 on an actual build product:

  A. No real name from the raw snapshot may appear anywhere in the bundle.
     The blocklist is rebuilt from `tools/league-data/raw/league_raw_2026.json`
     (every 2026 rostered player + every HC/OC/DC) plus `NOTABLE_PAST` — the
     exact same blocklist `make_templates.py` gates the transform with.
  B. `league_2026_dev.json` must not be in the product. The dev profile carries
     sound-alike names and verbatim stat lines and is DEBUG-only; Release
     filters it out via `EXCLUDED_SOURCE_FILE_NAMES`.
  C. No raw-data artifact (the per-team files, the merged snapshot, the QA
     reports) may have been dragged into a target's resources.
  D. Near-miss guard: every identity-bearing string in the shipped publish
     template must stay Levenshtein >= 3 from every blocklisted name, no real
     surname (>= 4 chars) may appear as a token inside one, and no player may
     carry a `notes` payload (ANONYMIZATION_SPEC.md section 3).
  E. Source-level guard on the RUNTIME name generators. Checks A-D see strings;
     they cannot see a name the app assembles at run time out of two separate
     arrays. Every pool pair listed in `SWIFT_NAME_POOLS` is therefore parsed
     out of its Swift source and its whole CROSS PRODUCT is held to the same
     rule as a generated template name.

Exit code 0 = clean, 1 = at least one hit, 2 = could not run.

Usage:  scan_bundle.py <path/to/dynasty.app> [--raw <league_raw_2026.json>]

SCOPE — what a PASS does and does not cover.

Check A matches whole names (full names and initialised "P. Mahomes" forms),
not bare surnames. A bare-surname scan over a 120 MB Mach-O binary is unusable:
"Green", "Jones", "Ward", "Long", "Moore" and dozens more blocklist surnames are
also ordinary English words and Swift symbol fragments, so the rule would fire
hundreds of times on noise and the gate would stop being read. A real surname
sitting in a *generator pool* is therefore invisible to A — which is exactly how
`RandomNameGenerator` shipped pools that cross-produced 68 real 2026 players'
full names under a green gate. Check E closes that specific hole by reading the
pools from source; it is the ONLY thing here that reasons about runtime-composed
names, and it only knows about the pools named in `SWIFT_NAME_POOLS`. A new name
pool elsewhere in the app is out of scope until it is added to that list, and
the verdict says so.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

# The transform tool is the single source of truth for the blocklist and the
# distance function — importing it means the gate can never drift from what the
# generator was actually checked against.
import make_templates as mt  # noqa: E402

# Raw artifacts that must never reach a target's resources (§6.5).
RAW_FILENAMES = {
    "league_raw_2026.json",
    "draft_picks_2026.json",
    "coaching_staffs_2026.json",
    "_build_summary.json",
    "QA_REPORT.md",
    "TRANSFORM_QA.md",
}
RAW_TEAM_FILE = re.compile(r"^[A-Z]{2,3}\.json$")

REPO_ROOT = os.path.dirname(os.path.dirname(HERE))

# Gate E: (source file, given-name array, surname array). Every pool the app
# draws a person's name from at RUN TIME belongs here — the two halves are drawn
# independently, so the reachable name space is the cross product.
SWIFT_NAME_POOLS = [
    ("dynasty/dynasty/Data/Import/RandomNameGenerator.swift",
     "firstNames", "lastNames",
     "players the game invents (draft classes, UDFAs, free agents) in every league source"),
    ("dynasty/dynasty/Data/Import/LeagueGenerator.swift",
     "ownerFirstNames", "ownerLastNames",
     "team owners, including all 32 of a Fixed 2026 template import"),
    ("dynasty/dynasty/Data/Import/LeagueGenerator.swift",
     "coachFirstNames", "coachLastNames",
     "coaches hired at run time in a generated league"),
    ("dynasty/dynasty/Data/Import/LeagueGenerator.swift",
     "coachFemaleFirstNames", "coachLastNames",
     "female coaches hired at run time in a generated league"),
    ("dynasty/dynasty/Data/Import/RandomNameGenerator.swift",
     "femaleFirstNames", "lastNames",
     "female coach candidates in every hiring market"),
]

SWIFT_POOL_DECL = re.compile(
    r"let\s+(?P<name>\w+)\s*:\s*\[String\]\s*=\s*\[(?P<body>[^\]]*)\]", re.S)
SWIFT_STRING = re.compile(r'"([^"\\]*)"')

# Files whose bytes carry no text worth scanning but cost real time. Everything
# else — the Mach-O binary included — is scanned.
SKIP_EXTENSIONS = {
    ".png", ".jpg", ".jpeg", ".heic", ".usdc", ".usdz", ".mp3", ".m4a",
    ".wav", ".caf", ".aiff", ".mov", ".mp4", ".ttf", ".otf", ".car",
}

ASCII_RUN = re.compile(rb"[\x20-\x7e]{3,}")
WORD = re.compile(r"[A-Za-z]+")

# "P. Mahomes" / "C.J. Stroud" — an initialised real name. A full-name scan
# alone misses these (normalising "P. Mahomes" gives "pmahomes", which is not
# "patrickmahomes"), yet initials + a real surname is precisely the recognition
# shortcut `ANONYMIZATION_SPEC.md` §1 forbids. Only fires when the surname is on
# the blocklist, so generated content — whose surnames are blocklist-filtered by
# construction — cannot trip it.
INITIALED_NAME = re.compile(r"\b(?:[A-Z]\.){1,3}\s*([A-Z][a-zA-Z'’-]{2,})\b")


# ---------------------------------------------------------------------------
# Blocklist
# ---------------------------------------------------------------------------


def load_blocklist(raw_path: str) -> dict:
    with open(raw_path, "r", encoding="utf-8") as fh:
        raw = json.load(fh)
    return mt.build_blocklist(raw)


# ---------------------------------------------------------------------------
# A + B + C — walk the product
# ---------------------------------------------------------------------------


def scan_product(app_path: str, blocklist: dict) -> list[str]:
    """Returns a list of violation lines (empty == clean)."""
    violations: list[str] = []

    # Normalized full names, e.g. "Ja'Marr Chase" -> "jamarrchase". A hit is a
    # sequence of adjacent word tokens in a bundle string that concatenates to
    # one of these — which is what a real name looks like however it was
    # spelled, spaced or punctuated.
    full_norm = set(blocklist["fullNorm"])
    block_last = {n.lower() for n in blocklist["last"] if len(n) >= 4}
    max_tokens = 4

    files_scanned = 0
    bytes_scanned = 0

    for root, _dirs, files in os.walk(app_path):
        for name in files:
            path = os.path.join(root, name)
            rel = os.path.relpath(path, os.path.dirname(app_path))

            # --- B: the dev template ------------------------------------
            if name == "league_2026_dev.json":
                violations.append(f"[B] DEV TEMPLATE PRESENT: {rel}")

            # --- C: raw snapshot artifacts -------------------------------
            if name in RAW_FILENAMES or RAW_TEAM_FILE.match(name):
                violations.append(f"[C] RAW DATA ARTIFACT PRESENT: {rel}")

            ext = os.path.splitext(name)[1].lower()
            if ext in SKIP_EXTENSIONS:
                continue
            try:
                with open(path, "rb") as fh:
                    data = fh.read()
            except OSError as exc:
                violations.append(f"[!] unreadable: {rel} ({exc})")
                continue

            files_scanned += 1
            bytes_scanned += len(data)

            # --- A: real names anywhere in the product -------------------
            for run in ASCII_RUN.findall(data):
                text = run.decode("ascii", "ignore")
                tokens = [t.lower() for t in WORD.findall(text)]
                if not tokens:
                    continue
                for i in range(len(tokens)):
                    joined = ""
                    for n in range(max_tokens):
                        if i + n >= len(tokens):
                            break
                        joined += tokens[i + n]
                        if len(joined) > 32:
                            break
                        if joined in full_norm:
                            hit = " ".join(tokens[i:i + n + 1])
                            where = text.lower().find(tokens[i])
                            snippet = (text[max(0, where - 50):where + 90].strip()
                                       if where >= 0 else text.strip()[:120])
                            violations.append(
                                f"[A] REAL NAME IN BUNDLE: {hit!r} in {rel} :: {snippet!r}"
                            )
                            break

                # A2: initialised real name ("P. Mahomes").
                for match in INITIALED_NAME.finditer(text):
                    surname = match.group(1)
                    if surname.lower() not in block_last:
                        continue
                    # A capitalised word immediately before the initial means the
                    # initial is a MIDDLE initial inside a longer proper noun —
                    # "Stephen F. Austin State", a real (and deliberately kept)
                    # university — not somebody's abbreviated name.
                    prefix = text[:match.start()].rstrip()
                    previous = prefix.split()[-1] if prefix.split() else ""
                    if previous[:1].isupper() and previous[1:2].islower():
                        continue
                    around = text[max(0, match.start() - 50):match.end() + 50]
                    violations.append(
                        f"[A] INITIALISED REAL NAME IN BUNDLE: {match.group(0)!r} "
                        f"in {rel} :: {around.strip()!r}"
                    )

    print(f"  scanned {files_scanned} files / {bytes_scanned/1e6:.1f} MB inside {os.path.basename(app_path)}")
    return violations


# ---------------------------------------------------------------------------
# D — near-miss guard on the shipped template
# ---------------------------------------------------------------------------


def identity_strings(template: dict) -> list[tuple[str, str]]:
    """(label, string) for everything in a template that names a PERSON or a
    club nickname — the same surface `make_templates.py` gate 3 scans.

    Cities are deliberately excluded. They are the game's own long-standing
    team branding (`REALISTIC_LEAGUE_PLAN.md`: "team names/cities per game's
    existing setup"), they are not claims about a person, and half of them are
    also common American surnames — "Cleveland", "Dallas", "Houston",
    "Washington", "Green" (Bay) and "Tampa" all appear in the blocklist's
    surname set. Scanning them would report six guaranteed false positives on
    every run, which is how a gate stops being read.
    """
    out: list[tuple[str, str]] = []
    for team in template.get("teams", []):
        ident = team.get("identity", {})
        key = ident.get("key", "?")
        if ident.get("nickname"):
            out.append((f"{key}.nickname", ident["nickname"]))
        staff = team.get("staff", {})
        for slot in ("hc", "oc", "dc"):
            member = staff.get(slot)
            if member and member.get("name"):
                out.append((f"{key}.{slot}", member["name"]))
        for player in team.get("players", []):
            out.append((f"{key}.player", player["name"]))
        for pick in team.get("picks2026", []):
            if pick.get("via"):
                out.append((f"{key}.pick", pick["via"]))
    return out


def scan_publish_template(app_path: str, blocklist: dict) -> list[str]:
    path = os.path.join(app_path, "league_2026_publish.json")
    if not os.path.exists(path):
        return [f"[D] publish template missing from the product: {path}"]

    with open(path, "r", encoding="utf-8") as fh:
        template = json.load(fh)

    violations: list[str] = []
    if template.get("profile") != "publish":
        violations.append(f"[D] bundled template declares profile={template.get('profile')!r}, expected 'publish'")

    # ANONYMIZATION_SPEC.md section 3: `notes` is not part of the publish
    # payload. It used to ship "finished 2025 on injured reserve" for 93 named
    # players — a real medical fact on top of the team + position + depth rank
    # the profile keeps by design.
    noted = sum(1 for t in template.get("teams", [])
                for p in t.get("players", []) if p.get("notes"))
    if noted:
        violations.append(f"[D] {noted} publish players carry a `notes` payload "
                          "(spec section 3 allows none)")

    strings = identity_strings(template)
    block_full = blocklist["fullNorm"]
    by_length: dict[int, list[str]] = {}
    for name in block_full:
        by_length.setdefault(len(name), []).append(name)
    block_last = {n.lower() for n in blocklist["last"] if len(n) >= 4}

    min_distance = 99
    min_pair = ("", "")
    for label, value in strings:
        norm = mt.norm_name(value)
        # Levenshtein >= 3 to every real name.
        for length in range(len(norm) - 2, len(norm) + 3):
            for candidate in by_length.get(length, ()):
                distance = mt.levenshtein_at_most(norm, candidate, 2)
                if distance <= 2:
                    violations.append(
                        f"[D] NEAR-MISS: {label} {value!r} is edit-distance {distance} from a real name"
                    )
                if distance < min_distance:
                    min_distance, min_pair = distance, (value, candidate)
        # No real surname as a token.
        for token in WORD.findall(value):
            if len(token) >= 4 and token.lower() in block_last:
                violations.append(f"[D] REAL SURNAME TOKEN: {label} {value!r} contains {token!r}")

    print(f"  publish template: {len(strings)} identity strings, "
          f"min edit distance to the blocklist = {min_distance if min_distance <= 2 else '>=3'}"
          + (f" ({min_pair[0]!r} vs {min_pair[1]!r})" if min_distance <= 2 else ""))
    return violations


# ---------------------------------------------------------------------------
# E — source-level guard on the runtime name generators
# ---------------------------------------------------------------------------


def _swift_pools(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        source = fh.read()
    return {m.group("name"): SWIFT_STRING.findall(m.group("body"))
            for m in SWIFT_POOL_DECL.finditer(source)}


def scan_name_pools(blocklist: dict) -> list[str]:
    """Every combination a runtime name generator can produce must satisfy the
    same rule a generated template name does (`ANONYMIZATION_SPEC.md` §1)."""
    violations: list[str] = []
    block_last = {n.lower() for n in blocklist["last"] if len(n) >= 4}
    block_last_idx = mt._by_length(blocklist["lastNorm"])
    cache: dict[str, dict] = {}

    for rel, first_key, last_key, purpose in SWIFT_NAME_POOLS:
        path = os.path.join(REPO_ROOT, rel)
        if not os.path.exists(path):
            violations.append(f"[E] name-pool source missing: {rel}")
            continue
        if path not in cache:
            cache[path] = _swift_pools(path)
        pools = cache[path]
        firsts, lasts = pools.get(first_key), pools.get(last_key)
        if not firsts or not lasts:
            # A renamed or deleted pool must FAIL, not silently pass: the gate's
            # whole value is that it still covers the surface it claims to.
            violations.append(
                f"[E] {rel}: pool `{first_key}` / `{last_key}` not found — the "
                "gate can no longer vouch for it")
            continue

        for name in lasts:
            norm = mt.norm_name(name)
            if any(mt.levenshtein_at_most(norm, b, 1) <= 1
                   for b in mt._near(block_last_idx, norm, 1)):
                violations.append(
                    f"[E] {rel}/{last_key}: {name!r} is a real surname or one edit from one")
        for name in firsts:
            if name.lower() in block_last:
                violations.append(
                    f"[E] {rel}/{first_key}: {name!r} is a real NFL surname — it reads "
                    "as a real player's name in a roster list")

        dirty = sorted(mt.recombination_conflicts(firsts, lasts, blocklist["fullNorm"]))
        for first, last in dirty[:20]:
            violations.append(
                f"[E] {rel}: {first!r} + {last!r} composes to within 2 edits of a real "
                f"name — reachable at run time for {purpose}")
        if len(dirty) > 20:
            violations.append(f"[E] {rel}: … and {len(dirty) - 20} more dirty combinations")

        print(f"  {rel}: {first_key} x {last_key} = {len(firsts) * len(lasts)} "
              f"combinations, {len(dirty)} within 2 edits of a real name")
    return violations


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", help="path to the built .app")
    parser.add_argument(
        "--raw",
        default=os.path.join(HERE, "raw", "league_raw_2026.json"),
        help="raw snapshot the blocklist is built from",
    )
    args = parser.parse_args()

    if not os.path.isdir(args.app):
        print(f"scan_bundle: no such app bundle: {args.app}", file=sys.stderr)
        return 2
    if not os.path.exists(args.raw):
        print(f"scan_bundle: no raw snapshot at {args.raw}", file=sys.stderr)
        return 2

    blocklist = load_blocklist(args.raw)
    print(f"  blocklist: {len(blocklist['full'])} real full names, {len(blocklist['last'])} surnames")

    violations = scan_product(args.app, blocklist)
    violations += scan_publish_template(args.app, blocklist)
    violations += scan_name_pools(blocklist)

    if violations:
        print("")
        print(f"BUNDLE GATE FAILED — {len(violations)} violation(s):")
        for line in violations[:50]:
            print(f"  {line}")
        if len(violations) > 50:
            print(f"  … and {len(violations) - 50} more")
        return 1

    print("")
    print("BUNDLE GATE PASSED, within this scope:")
    print("  - no real full name (or initialised form) as a string anywhere in the product;")
    print("  - no dev template, no raw snapshot artifact in the product;")
    print("  - shipped publish template: Levenshtein >= 3, no real surname token, no notes;")
    print(f"  - the {len(SWIFT_NAME_POOLS)} runtime name-pool pairs in SWIFT_NAME_POOLS "
          "cannot compose a real name.")
    print("  NOT covered: bare surnames inside the binary (see the module docstring), and")
    print("  any runtime name source not listed in SWIFT_NAME_POOLS.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
