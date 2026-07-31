#!/usr/bin/env bash
# ============================================================================
# run.sh — sync engine sources, build the harness, run selected scenario(s)
# ============================================================================
# Usage:
#   ./run.sh <scenario> [scenario ...]      # e.g. ./run.sh percall keyed-pa
#   ./run.sh all                            # every per-play scenario
#   BH_N=60000 ./run.sh regression          # override per-cell sample size
#   ./run.sh --no-sync depth                # skip re-sync (reuse build/src)
#   ./run.sh fullgame --home-tier elite --away-tier weak --n 200   # round-5 full games
#   ./run.sh positionsweep --group CB --n 100                      # round-5 sweep
#   ./run.sh draftclass --classes 200          # draft-class generator validation
#   ./run.sh career                            # player-development validation
#   ./run.sh leaguegen [--leagues 400]         # RANDOM-league t=0 quality pyramid
#   ./run.sh perception [--drafts 12]          # AI draft-fog diagnostic (no gate)
#
# Per-play scenarios: percall depth keyed-pa regression pass-talent run-talent
#            familiarity stacking spam heat-* composure-lev mental-regression macro.
# Parameterized scenarios (flag args, run on their own — not via `all`):
#            fullgame, positionsweep, draftclass, career, leaguegen, perception.
#            (see README.md for the full CLI + band targets.)
#
# This is REPO TOOLING — it does NOT build the iOS app. It compiles only the
# synced simulation sources + the driver with swiftc -O.
# ============================================================================
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_OUT="$HARNESS_DIR/build/src"
DRIVER="$HARNESS_DIR/driver/main.swift"
BIN="$HARNESS_DIR/build/harness"

DO_SYNC=1
ARGS=()
for a in "$@"; do
  if [ "$a" = "--no-sync" ]; then DO_SYNC=0; else ARGS+=("$a"); fi
done
[ "${#ARGS[@]}" -gt 0 ] || { echo "usage: ./run.sh <scenario> [scenario ...] | all   (see README.md)" >&2; exit 2; }

if [ "$DO_SYNC" -eq 1 ]; then
  "$HARNESS_DIR/sync_sources.sh"
fi
[ -d "$SRC_OUT" ] || { echo "run.sh: no build/src — run without --no-sync first." >&2; exit 1; }

# Rebuild if the binary is missing or any source is newer than it.
needs_build=0
if [ ! -x "$BIN" ]; then
  needs_build=1
else
  while IFS= read -r f; do [ "$f" -nt "$BIN" ] && { needs_build=1; break; }; done \
    < <(printf '%s\n' "$SRC_OUT"/*.swift "$DRIVER")
fi

if [ "$needs_build" -eq 1 ]; then
  echo "==> swiftc -O (this compiles PlaySimulator.swift — expect ~30-60s)"
  # shellcheck disable=SC2046
  swiftc -O -o "$BIN" $(printf '%s ' "$SRC_OUT"/*.swift) "$DRIVER"
  echo "==> built $BIN"
else
  echo "==> up to date, reusing $BIN"
fi

echo "==> running: ${ARGS[*]}"
echo ""
exec "$BIN" "${ARGS[@]}"
