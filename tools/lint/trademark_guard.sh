#!/usr/bin/env bash
#
# trademark_guard.sh — keep real-league trademarks out of user-facing strings.
#
# The game ships fictional branding: the title game is "the Championship",
# never "the Super Bowl"; the league is "the league" / "the pro game", never
# "the NFL". This guard fails if either trademark reappears in Swift source in
# a way that could reach the screen.
#
# Two forms are deliberately allowed, because neither renders:
#   1. comments (`//`, `///`)
#   2. input matchers — `.contains("… super bowl …")` — which sniff legacy save
#      data and imported league-template text for the old wording.
# The `superBowl` enum case / identifier is likewise ignored: it is an internal
# symbol (`SeasonPhase.superBowl`) whose display strings live elsewhere.
#
# The `NFL` check is narrower than the `Super Bowl` one on purpose: it fires
# only on the mark inside a double-quoted literal, because the token is also a
# legitimate shorthand in comments ("NFL hash marks", "NFL-convention uniform")
# and inside identifiers, neither of which reaches the screen.
#
# Usage:  tools/lint/trademark_guard.sh [root]     (default root: dynasty/)
# Exit:   0 clean, 1 violations found (printed as path:line:text).

set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/../.." && pwd)/dynasty}"

failed=0

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

if [[ $failed -ne 0 ]]; then
  exit 1
fi

echo "trademark_guard: clean (no user-facing 'Super Bowl' or 'NFL')."
exit 0
