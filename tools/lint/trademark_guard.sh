#!/usr/bin/env bash
#
# trademark_guard.sh — keep real-league trademarks out of what ships.
#
# The game ships fictional branding: the title game is "the Championship",
# never "the Super Bowl"; the league is "the league" / "the pro game", never
# "the NFL"; the shrine is "the Hall", never Canton. This guard fails if any of
# those marks reappears anywhere it could reach a player — Swift strings, the
# bundled league templates, or a bundled resource FILENAME (a name inside the
# `.app` is as visible to a string scan of the product as any on-screen label).
#
# Five checks:
#   1. "Super Bowl" in Swift source          (whole tree)
#   2. "NFL" in a Swift string literal       (whole tree)
#   3. `nfl*` in a bundled resource filename (dynasty/dynasty/Resources)
#   4. "Super Bowl" / "NFL" in the league templates — both the generator output
#      (tools/league-data/out) and the bundled copies (Resources). The `raw/`
#      snapshot is deliberately NOT scanned: it is the real-world input to the
#      anonymizing transform and never ships (check_bundle.sh gate C proves the
#      product carries no raw artifact).
#   5. "Canton" in a UI Swift string literal (dynasty/dynasty/UI)
#
# Two forms are deliberately allowed in checks 1/2/5, because neither renders:
#   a. comments (`//`, `///`)
#   b. input matchers — `.contains("… super bowl …")` — which sniff legacy save
#      data and imported league-template text for the old wording.
# The `superBowl` enum case / identifier is likewise ignored: it is an internal
# symbol (`SeasonPhase.superBowl`) whose display strings live elsewhere.
#
# The `NFL` check is narrower than the `Super Bowl` one on purpose: it fires
# only on the mark inside a double-quoted literal, because the token is also a
# legitimate shorthand in comments ("NFL hash marks", "NFL-convention uniform")
# and inside identifiers, neither of which reaches the screen.
#
# Check 5 is scoped to the UI tree, not the whole app: the Engine still carries
# one user-facing "Canton" news headline (NewsGenerator's Hall-of-Fame-watch
# lane) that is owned by another task. Widen the scope to "$ROOT" the moment
# that string is rewritten.
#
# Usage:  tools/lint/trademark_guard.sh [root]     (default root: dynasty/)
#         Checks 3-4 always run against the repo's fixed paths; a custom root
#         only redirects the Swift scans.
# Exit:   0 clean, 1 violations found (printed as path:line:text).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ROOT="${1:-$REPO_ROOT/dynasty}"
RESOURCES="$REPO_ROOT/dynasty/dynasty/Resources"
UI_ROOT="$ROOT/dynasty/UI"
LEAGUE_OUT="$REPO_ROOT/tools/league-data/out"

failed=0

# ---- 1. "Super Bowl" in Swift source ---------------------------------------
bowl_violations="$(
  grep -rniE 'super ?bowl' --include='*.swift' "$ROOT" 2>/dev/null \
    | grep -viE 'superBowl[A-Za-z]*' \
    | grep -viE ':[[:space:]]*///?' \
    | grep -viE '\.contains\("[^"]*super ?bowl[^"]*"\)'
)"

if [[ -n "$bowl_violations" ]]; then
  echo "trademark_guard: 'Super Bowl' found in user-facing Swift strings."
  echo "Use the in-game term (\"the Championship\" / \"CHAMPIONS\") instead."
  echo
  echo "$bowl_violations"
  echo
  failed=1
fi

# ---- 2. "NFL" in a Swift string literal ------------------------------------
nfl_violations="$(
  grep -rnE '"[^"]*\bNFL\b[^"]*"' --include='*.swift' "$ROOT" 2>/dev/null \
    | grep -vE ':[[:space:]]*///?' \
    | grep -vE '\.contains\("[^"]*NFL[^"]*"\)'
)"

if [[ -n "$nfl_violations" ]]; then
  echo "trademark_guard: 'NFL' found in a user-facing Swift string literal."
  echo "Use the in-game term (\"the league\" / \"the pro game\") instead."
  echo
  echo "$nfl_violations"
  echo
  failed=1
fi

# ---- 3. bundled resource FILENAMES -----------------------------------------
# The six broadcast-round music cues shipped as `nfl_menu_*` / `nfl_dash_*`
# until #167; the generator round that produced them keeps those working names
# under tools/audio (never bundled), the shipped copies must not.
if [[ -d "$RESOURCES" ]]; then
  name_violations="$(find "$RESOURCES" -iname '*nfl*' 2>/dev/null | sort)"
  if [[ -n "$name_violations" ]]; then
    echo "trademark_guard: bundled resource filename contains 'nfl'."
    echo "Rename the file (a name inside the .app is a shipped string)."
    echo
    echo "$name_violations"
    echo
    failed=1
  fi
fi

# ---- 4. league templates (generator output + bundled copies) ---------------
# The templates are single-line minified JSON, so matches are printed as a
# windowed excerpt rather than the whole 1.5 MB line.
for template in \
  "$LEAGUE_OUT/league_2026_publish.json" \
  "$LEAGUE_OUT/league_2026_dev.json" \
  "$RESOURCES/league_2026_publish.json" \
  "$RESOURCES/league_2026_dev.json"
do
  [[ -f "$template" ]] || continue
  template_hits="$(
    grep -oiE '.{0,50}(super ?bowl|\bNFL\b).{0,50}' "$template" 2>/dev/null
  )"
  if [[ -n "$template_hits" ]]; then
    echo "trademark_guard: '$(basename "$template")' carries a real-league mark."
    echo "Fix make_templates.py (TITLE_GAME_RESULTS) and regenerate, then copy"
    echo "tools/league-data/out/ over dynasty/dynasty/Resources/."
    echo
    echo "$template_hits"
    echo
    failed=1
  fi
done

# ---- 5. "Canton" in a UI Swift string literal ------------------------------
if [[ -d "$UI_ROOT" ]]; then
  canton_violations="$(
    grep -rniE '"[^"]*\bcanton\b[^"]*"' --include='*.swift' "$UI_ROOT" 2>/dev/null \
      | grep -viE ':[[:space:]]*///?' \
      | grep -viE '\.contains\("[^"]*canton[^"]*"\)'
  )"
  if [[ -n "$canton_violations" ]]; then
    echo "trademark_guard: 'Canton' found in a user-facing UI string literal."
    echo "The game's shrine is \"the Hall\" — it has no real city."
    echo
    echo "$canton_violations"
    echo
    failed=1
  fi
fi

if [[ $failed -ne 0 ]]; then
  exit 1
fi

# Say what was actually checked. "no 'NFL' in Swift" was not true and could not
# be: check 2 is deliberately scoped to STRING LITERALS, because "NFL hash
# marks" in a comment is legitimate shorthand (see the header). A clean line
# that overstates its own coverage is how a guard stops being trusted.
echo "trademark_guard: clean (no 'Super Bowl' anywhere in Swift, no 'NFL' in a"
echo "Swift STRING LITERAL — comments are allowed shorthand — no 'nfl*' bundled"
echo "filename, no mark in either league template, no 'Canton' in UI)."
exit 0
