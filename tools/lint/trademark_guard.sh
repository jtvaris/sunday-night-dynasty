#!/usr/bin/env bash
#
# trademark_guard.sh — keep real-league trademarks out of user-facing strings.
#
# The game ships fictional branding: the title game is "the Championship",
# never "the Super Bowl". This guard fails if that phrase (any casing, with or
# without the space) reappears in Swift source in a way that could reach the
# screen.
#
# Two forms are deliberately allowed, because neither renders:
#   1. comments (`//`, `///`)
#   2. input matchers — `.contains("… super bowl …")` — which sniff legacy save
#      data and imported league-template text for the old wording.
# The `superBowl` enum case / identifier is likewise ignored: it is an internal
# symbol (`SeasonPhase.superBowl`) whose display strings live elsewhere.
#
# Usage:  tools/lint/trademark_guard.sh [root]     (default root: dynasty/)
# Exit:   0 clean, 1 violations found (printed as path:line:text).

set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)/dynasty}"

violations="$(
  grep -rniE 'super ?bowl' --include='*.swift' "$ROOT" 2>/dev/null \
    | grep -viE 'superBowl[A-Za-z]*' \
    | grep -viE ':[[:space:]]*///?' \
    | grep -viE '\.contains\("[^"]*super ?bowl[^"]*"\)'
)"

if [[ -n "$violations" ]]; then
  echo "trademark_guard: 'Super Bowl' found in user-facing Swift strings."
  echo "Use the in-game term (\"the Championship\" / \"CHAMPIONS\") instead."
  echo
  echo "$violations"
  exit 1
fi

echo "trademark_guard: clean (no user-facing 'Super Bowl')."
exit 0
