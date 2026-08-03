#!/usr/bin/env python3
"""Design-token debt lint for the Dynasty SwiftUI layer.

Counts the four kinds of design debt the token system exists to retire, and
prints the delta against a committed baseline so a regression is visible in a
diff rather than discovered six months later by an audit.

    font      off-ladder `.system(size:)` literals   (ladder: DSType.Size)
    radius    off-ladder `cornerRadius:` literals    (ladder: DSCornerRadius)
    spacing   off-ladder spacing/padding literals    (ladder: DSSpacing)
    ratingfn  bespoke rating -> Color functions      (should be Color.forRating)

The ladders are **parsed out of the Swift token files**, not hardcoded here, so
adding a step to `DSType.Size` automatically reclassifies every literal that
lands on it. There is exactly one definition of the scale and it is the Swift.

No SwiftLint, no dependencies — stdlib only.

Usage
-----
    python3 tools/lint/design_tokens.py              # report + delta, exit 1 on regression
    python3 tools/lint/design_tokens.py --top 15     # also list worst files per metric
    python3 tools/lint/design_tokens.py --json       # machine-readable
    python3 tools/lint/design_tokens.py --update-baseline

Suppressing a site
------------------
Put a pragma on the line. It is counted as *allowed*, reported separately, and
never affects the totals:

    .font(.system(size: 8, weight: .bold))  // ds-lint:allow(font) field texture

Valid metrics in the pragma: font, radius, spacing, ratingfn, or `all`.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SOURCE_ROOT = REPO / "dynasty" / "dynasty"
BASELINE = Path(__file__).resolve().parent / "design_tokens_baseline.json"

THEME = SOURCE_ROOT / "UI" / "Common" / "Theme.swift"
DSTOKENS = SOURCE_ROOT / "UI" / "Theme" / "DSTokens.swift"

# The files that *define* the tokens are not measured against them.
EXEMPT_FILES = {THEME, DSTOKENS}

METRICS = ("font", "radius", "spacing", "ratingfn")

PRAGMA = re.compile(r"//\s*ds-lint:allow\(([a-z, ]+)\)")


# --------------------------------------------------------------------------
# Ladders, parsed from the Swift token definitions
# --------------------------------------------------------------------------

def _static_lets(text: str, enum_name: str) -> dict[str, float]:
    """Numeric `static let` values inside `enum <enum_name> { ... }`.

    Brace-matched rather than regex-sliced so a nested type (DSType.Size lives
    inside DSType) terminates at the right place.
    """
    m = re.search(r"enum\s+" + re.escape(enum_name) + r"\s*\{", text)
    if not m:
        return {}
    i = m.end() - 1
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                body = text[i + 1 : j]
                break
    else:
        return {}
    out: dict[str, float] = {}
    for name, val in re.findall(
        r"static\s+let\s+(\w+)\s*:\s*CGFloat\s*=\s*(-?[0-9]+(?:\.[0-9]+)?)", body
    ):
        out[name] = float(val)
    return out


def load_ladders() -> dict[str, dict[str, float]]:
    theme = THEME.read_text()
    tokens = DSTOKENS.read_text()
    ladders = {
        "font": _static_lets(tokens, "Size"),
        "radius": _static_lets(theme, "DSCornerRadius"),
        "spacing": _static_lets(theme, "DSSpacing"),
    }
    for metric, values in ladders.items():
        if not values:
            sys.exit(f"design_tokens: could not parse the {metric} ladder — token file moved?")
    return ladders


# --------------------------------------------------------------------------
# Site detection
# --------------------------------------------------------------------------

FONT_RE = re.compile(r"\.system\(\s*size:\s*(-?[0-9]+(?:\.[0-9]+)?)\s*[,)]")
RADIUS_RE = re.compile(r"cornerRadius:\s*(-?[0-9]+(?:\.[0-9]+)?)\s*[,)]")
SPACING_RE = re.compile(
    r"(?:\bspacing:\s*|\.padding\(\s*(?:\.\w+(?:\s*,\s*)?)?)(-?[0-9]+(?:\.[0-9]+)?)\s*[,)]"
)

# A function that maps a number onto a colour ladder by hand. Matched on shape:
# returns Color, takes a numeric parameter, and branches on >= 3 numeric
# thresholds. Delegating one-liners (`Color.forRating(v)`) have none and so are
# correctly *not* counted.
FUNC_RE = re.compile(r"func\s+(\w+)\s*\(([^)]*)\)\s*->\s*Color\b")
NUMERIC_PARAM_RE = re.compile(r":\s*(Int|Double|CGFloat|Float)\b")
THRESHOLD_RE = re.compile(
    r"(?:case\s+-?[0-9]|[><]=?\s*-?[0-9]|\.\.[.<]\s*-?[0-9])"
)


def allowed(line: str, metric: str) -> bool:
    m = PRAGMA.search(line)
    if not m:
        return False
    claimed = {p.strip() for p in m.group(1).split(",")}
    return metric in claimed or "all" in claimed


def swift_files() -> list[Path]:
    return sorted(
        p for p in SOURCE_ROOT.rglob("*.swift") if p not in EXEMPT_FILES
    )


def scan_rating_fns(path: Path, lines: list[str]) -> tuple[int, int, list[str]]:
    """(violations, allowed, detail) for bespoke rating->Color functions."""
    text = "\n".join(lines)
    bad = 0
    ok = 0
    detail = []
    for m in FUNC_RE.finditer(text):
        name, params = m.group(1), m.group(2)
        if not NUMERIC_PARAM_RE.search(params):
            continue
        # Brace-match the body.
        brace = text.find("{", m.end())
        if brace < 0:
            continue
        depth = 0
        end = brace
        for j in range(brace, len(text)):
            if text[j] == "{":
                depth += 1
            elif text[j] == "}":
                depth -= 1
                if depth == 0:
                    end = j
                    break
        body = text[brace : end + 1]
        if len(THRESHOLD_RE.findall(body)) < 3:
            continue
        line_no = text.count("\n", 0, m.start()) + 1
        if allowed(lines[line_no - 1], "ratingfn"):
            ok += 1
            continue
        bad += 1
        detail.append(f"{path.relative_to(REPO)}:{line_no} {name}()")
    return bad, ok, detail


def scan(ladders: dict[str, dict[str, float]]) -> dict:
    on_ladder = {k: set(v.values()) for k, v in ladders.items()}
    # 0 is not a magic number, it is the absence of one: `spacing: 0` says the
    # stack is deliberately flush and `cornerRadius: 0` says square. Counting
    # them as debt would bury the real off-ladder values under ~270 non-issues.
    on_ladder["spacing"].add(0.0)
    on_ladder["radius"].add(0.0)
    counts = {m: 0 for m in METRICS}
    total = {m: 0 for m in METRICS}
    allow = {m: 0 for m in METRICS}
    per_file = {m: Counter() for m in METRICS}
    values = {m: Counter() for m in METRICS}
    below_floor = 0
    floor = min(on_ladder["font"]) if on_ladder["font"] else 0
    rating_detail: list[str] = []

    for path in swift_files():
        try:
            lines = path.read_text().split("\n")
        except UnicodeDecodeError:
            continue
        rel = str(path.relative_to(REPO))

        for regex, metric in ((FONT_RE, "font"), (RADIUS_RE, "radius"), (SPACING_RE, "spacing")):
            for i, line in enumerate(lines):
                for raw in regex.findall(line):
                    val = float(raw)
                    total[metric] += 1
                    if val in on_ladder[metric]:
                        continue
                    if allowed(line, metric):
                        allow[metric] += 1
                        continue
                    counts[metric] += 1
                    per_file[metric][rel] += 1
                    values[metric][raw.rstrip("0").rstrip(".") if "." in raw else raw] += 1
                    if metric == "font" and val < floor:
                        below_floor += 1

        bad, ok, detail = scan_rating_fns(path, lines)
        if bad:
            counts["ratingfn"] += bad
            per_file["ratingfn"][rel] += bad
            rating_detail += detail
        allow["ratingfn"] += ok
        total["ratingfn"] += bad + ok

    return {
        "counts": counts,
        "total": total,
        "allowed": allow,
        "font_below_floor": below_floor,
        "font_floor": floor,
        "ladders": {k: sorted(v) for k, v in on_ladder.items()},
        "per_file": {m: dict(per_file[m].most_common()) for m in METRICS},
        "values": {m: dict(values[m].most_common()) for m in ("font", "radius", "spacing")},
        "rating_detail": sorted(rating_detail),
    }


# --------------------------------------------------------------------------
# Reporting
# --------------------------------------------------------------------------

LABEL = {
    "font": "font sizes off the DSType.Size ladder",
    "radius": "corner radii off the DSCornerRadius ladder",
    "spacing": "spacing/padding off the DSSpacing ladder",
    "ratingfn": "bespoke rating -> Color functions",
}


def fmt_delta(d: int) -> str:
    if d == 0:
        return "     ="
    return f"{d:+6d}"


def report(result: dict, baseline: dict | None, top: int) -> int:
    print("Design-token debt\n" + "=" * 66)
    for metric, values in result["ladders"].items():
        pretty = ", ".join(str(int(v)) if v == int(v) else str(v) for v in values)
        print(f"  {metric:<8} ladder: {pretty}")
    print()

    header = f"  {'metric':<10} {'off-ladder':>10} {'of total':>10} {'delta':>7}  {'allowed':>7}"
    print(header)
    print("  " + "-" * (len(header) - 2))

    regressed = []
    for m in METRICS:
        cur = result["counts"][m]
        tot = result["total"][m]
        base = baseline["counts"][m] if baseline else None
        delta = cur - base if base is not None else 0
        if base is not None and delta > 0:
            regressed.append((m, base, cur))
        # For literals the denominator is "every literal of this kind", which
        # makes the share meaningful. For ratingfn the denominator is only the
        # functions this lint detected at all, so a share would always read
        # 100% and say nothing — leave it blank.
        share = "-" if m == "ratingfn" else (f"{cur}/{tot}" if tot else str(cur))
        print(
            f"  {m:<10} {cur:>10} {share:>10} {fmt_delta(delta) if base is not None else '   n/a':>7}"
            f"  {result['allowed'][m]:>7}"
        )

    floor = result["font_floor"]
    floor_txt = int(floor) if floor == int(floor) else floor
    base_floor = baseline.get("font_below_floor") if baseline else None
    d = f" ({fmt_delta(result['font_below_floor'] - base_floor).strip()})" if base_floor is not None else ""
    print(f"\n  legibility: {result['font_below_floor']} font literals below the {floor_txt}pt floor{d}")

    if top:
        for m in METRICS:
            worst = list(result["per_file"][m].items())[:top]
            if not worst:
                continue
            print(f"\n  worst files - {LABEL[m]}:")
            for rel, n in worst:
                print(f"    {n:>5}  {rel}")
        for m in ("font", "radius", "spacing"):
            vals = list(result["values"][m].items())[:top]
            if vals:
                print(f"\n  off-ladder {m} values: " + ", ".join(f"{v}({n})" for v, n in vals))
        if result["rating_detail"]:
            print(f"\n  bespoke rating -> Color functions ({len(result['rating_detail'])}):")
            for d in result["rating_detail"][:top]:
                print(f"    {d}")
            if len(result["rating_detail"]) > top:
                print(f"    ... and {len(result['rating_detail']) - top} more")

    if baseline is None:
        print("\nNo baseline stored. Run with --update-baseline to record one.")
        return 0

    print()
    if regressed:
        print("REGRESSION - new off-ladder literals since the baseline:")
        for m, base, cur in regressed:
            print(f"  {LABEL[m]}: {base} -> {cur}  (+{cur - base})")
        print("\nUse a token (DSType.Size / DSCornerRadius / DSSpacing), or annotate the")
        print("site with  // ds-lint:allow(<metric>) <why>  if the literal is load-bearing.")
        return 1

    improved = [
        (m, baseline["counts"][m], result["counts"][m])
        for m in METRICS
        if result["counts"][m] < baseline["counts"][m]
    ]
    if improved:
        print("Improved since baseline:")
        for m, base, cur in improved:
            print(f"  {LABEL[m]}: {base} -> {cur}  ({cur - base})")
        print("\nRun --update-baseline to lock the gains in.")
    else:
        print("No regression.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--update-baseline", action="store_true", help="rewrite the stored baseline")
    ap.add_argument("--top", type=int, default=0, help="list the N worst files / values per metric")
    ap.add_argument("--json", action="store_true", help="emit the raw result as JSON")
    args = ap.parse_args()

    result = scan(load_ladders())

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0

    if args.update_baseline:
        payload = {
            "_comment": "Regenerate with: python3 tools/lint/design_tokens.py --update-baseline",
            "counts": result["counts"],
            "total": result["total"],
            "allowed": result["allowed"],
            "font_below_floor": result["font_below_floor"],
            "ladders": result["ladders"],
        }
        BASELINE.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
        print(f"Baseline written: {BASELINE.relative_to(REPO)}")
        for m in METRICS:
            print(f"  {m:<10} {result['counts'][m]:>6} off-ladder of {result['total'][m]}")
        print(f"  font literals below the {result['font_floor']:g}pt floor: {result['font_below_floor']}")
        return 0

    baseline = json.loads(BASELINE.read_text()) if BASELINE.exists() else None
    return report(result, baseline, args.top)


if __name__ == "__main__":
    sys.exit(main())
