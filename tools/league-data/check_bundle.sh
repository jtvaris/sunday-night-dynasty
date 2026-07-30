#!/usr/bin/env bash
# ============================================================================
# check_bundle.sh — anonymization bundle gate (docs/ANONYMIZATION_SPEC.md §6.2)
# ============================================================================
# Builds the app in the **Release** configuration and scans the resulting `.app`
# for the two things that must never ship:
#
#   (a) any real name from `tools/league-data/raw/league_raw_2026.json`
#       (every 2026 rostered player + every HC/OC/DC + the notable-past list) —
#       the blocklist is rebuilt by importing `make_templates.py`, so the gate
#       and the transform can never disagree about what "real" means;
#   (b) `league_2026_dev.json`, the DEBUG-only sound-alike template.
#
# Two further checks ride along: no raw-snapshot artifact anywhere in the
# product, and a Levenshtein >= 3 / no-real-surname re-check of every identity
# string inside the shipped `league_2026_publish.json`.
#
# Release is the configuration under test on purpose: `EXCLUDED_SOURCE_FILE_NAMES
# = league_2026_dev.json` only applies there, so a DEBUG product legitimately
# contains the dev template and would fail (b) by design.
#
# Usage:
#   ./check_bundle.sh                 # build Release, then scan
#   ./check_bundle.sh --no-build      # scan the last Release product
#   ./check_bundle.sh --app <path>    # scan an existing .app
#
# Exit: 0 clean, 1 violation found, 2 could not run.
# ============================================================================
set -uo pipefail

TOOL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TOOL_DIR/../.." && pwd)"
PROJECT="$REPO_ROOT/dynasty/dynasty.xcodeproj"
SCHEME="dynasty"
CONFIGURATION="Release"
DERIVED="$TOOL_DIR/.bundle-gate-dd"
APP_OVERRIDE=""
DO_BUILD=1

while [ $# -gt 0 ]; do
  case "$1" in
    --no-build) DO_BUILD=0; shift ;;
    --app)      APP_OVERRIDE="${2:-}"; DO_BUILD=0; shift 2 ;;
    -h|--help)  sed -n '2,30p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *)          echo "check_bundle.sh: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

echo "==> bundle gate: $CONFIGURATION build + anonymization scan"

if [ "$DO_BUILD" -eq 1 ]; then
  echo "==> xcodebuild -configuration $CONFIGURATION (derivedData: $DERIVED)"
  BUILD_LOG="$TOOL_DIR/.bundle-gate-build.log"
  if ! xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$DERIVED" \
        -quiet \
        build > "$BUILD_LOG" 2>&1; then
    echo "check_bundle.sh: RELEASE BUILD FAILED — see $BUILD_LOG" >&2
    tail -40 "$BUILD_LOG" >&2
    exit 2
  fi
  echo "==> release build OK"
fi

if [ -n "$APP_OVERRIDE" ]; then
  APP="$APP_OVERRIDE"
else
  APP="$(/usr/bin/find "$DERIVED/Build/Products/$CONFIGURATION-iphonesimulator" \
          -maxdepth 1 -name '*.app' -type d 2>/dev/null | head -1)"
fi

if [ -z "${APP:-}" ] || [ ! -d "$APP" ]; then
  echo "check_bundle.sh: no built .app found (looked in $DERIVED/Build/Products/$CONFIGURATION-iphonesimulator)" >&2
  exit 2
fi

echo "==> scanning $APP"
python3 "$TOOL_DIR/scan_bundle.py" "$APP"
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  echo "==> BUNDLE GATE: PASS"
else
  echo "==> BUNDLE GATE: FAIL (exit $STATUS)"
fi
exit "$STATUS"
