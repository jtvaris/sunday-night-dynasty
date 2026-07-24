#!/usr/bin/env bash
# ============================================================================
# sync_sources.sh — stage the balance harness's engine sources from the repo
# ============================================================================
# Populates build/src/ with the CANONICAL engine sources needed to compile the
# balance harness against the SHIPPED simulation math:
#
#   • 10 files copied VERBATIM from the repo (byte-identical; sha-verified).
#   • AdaptiveOpponentAIExtract.swift REGENERATED mechanically from the shipped
#     Engine/Match/AdaptiveOpponentAI.swift by awk-stripping only the 4
#     persona-hint functions (which need DCPersona/OCPersona and carry ZERO
#     balance constants). Every tuning literal — paKeyCompletion 0.035,
#     paKeyBigPlay 2.0, runGrandBiteCap 1.80, … — flows through untouched from
#     the repo bytes. It is NEVER hand-copied, so it cannot drift.
#   • SimPlayer.swift ASSEMBLED from driver/SimPlayer.harness.swift, with the
#     storage decls and the computed-property block spliced VERBATIM from the
#     repo SimPlayer.swift.
#
# WHY THIS EXISTS (the stale-default incident): earlier /tmp rebuilds of this
# harness hand-copied the AdaptiveOpponentAI constants behind a "// VERBATIM"
# comment. In balance rounds 2 AND 3 those copies had drifted — the paKey levers
# were left at stale defaults (0.18 / 8.0 instead of the shipped 0.035 / 2.0),
# inflating keyed PA-deep ~4-5x and silently invalidating the measurements. This
# script makes that class of bug impossible: constants are sliced from the repo
# file every build and a post-slice check fails the build if a single tuning
# line differs from the repo. See README.md.
#
# Refuses to proceed if any repo source is missing, if a verbatim copy's sha
# ever diverges from the repo, or if the extract still references DCPersona /
# OCPersona or a tuning constant drifted.
# ============================================================================
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"
ENGINE="$REPO_ROOT/dynasty/dynasty"
SRC_OUT="$HARNESS_DIR/build/src"
MANIFEST="$SRC_OUT/MANIFEST.txt"

sha() { shasum -a 256 "$1" | awk '{print $1}'; }
die() { echo "sync_sources.sh: FATAL: $*" >&2; exit 1; }

# Temp scratch files, cleaned up on any exit.
SLICE=""; STORAGE=""; COMPUTED=""
cleanup() { rm -f "$SLICE" "$STORAGE" "$COMPUTED"; }
trap cleanup EXIT

# --- Canonical repo sources (relative to $ENGINE) --------------------------
# 10 files copied verbatim.
VERBATIM_SOURCES=(
  "Domain/Enums/PlayCall.swift"
  "Domain/Enums/PlayType.swift"
  "Domain/Enums/Position.swift"
  "Domain/Enums/Scheme.swift"
  "Domain/Enums/GameWeather.swift"
  "Domain/Enums/PersonalityArchetype.swift"
  "Domain/Models/League/PlayResult.swift"
  "Domain/Models/Player/PlayerAttributes.swift"
  "Domain/Models/Team/GamePlan.swift"
  "Engine/Simulation/PlaySimulator.swift"
)
AI_SOURCE="$ENGINE/Engine/Match/AdaptiveOpponentAI.swift"
SIM_SOURCE="$ENGINE/Engine/Simulation/SimPlayer.swift"
SIM_TEMPLATE="$HARNESS_DIR/driver/SimPlayer.harness.swift"

# --- Preflight: refuse to build if any source is missing -------------------
missing=0
for rel in "${VERBATIM_SOURCES[@]}"; do
  [ -f "$ENGINE/$rel" ] || { echo "  MISSING: $ENGINE/$rel" >&2; missing=1; }
done
[ -f "$AI_SOURCE" ]     || { echo "  MISSING: $AI_SOURCE" >&2; missing=1; }
[ -f "$SIM_SOURCE" ]    || { echo "  MISSING: $SIM_SOURCE" >&2; missing=1; }
[ -f "$SIM_TEMPLATE" ]  || { echo "  MISSING: $SIM_TEMPLATE" >&2; missing=1; }
[ "$missing" -eq 0 ] || die "one or more canonical sources are missing — refusing to build."

rm -rf "$SRC_OUT"
mkdir -p "$SRC_OUT"

GITREV="$(cd "$REPO_ROOT" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
{
  echo "# Balance Harness source MANIFEST"
  echo "# generated $(date '+%Y-%m-%d %H:%M:%S') by sync_sources.sh"
  echo "# repo HEAD: $GITREV"
  echo "#"
  echo "# ROLE       SHA256(dest)                                                      DEST  <=  SHA256(repo-source)  SOURCE"
} > "$MANIFEST"

# --- 1) Verbatim copies (sha must equal the repo file's sha) ---------------
echo "==> verbatim engine sources"
for rel in "${VERBATIM_SOURCES[@]}"; do
  base="$(basename "$rel")"
  cp "$ENGINE/$rel" "$SRC_OUT/$base"
  src_sha="$(sha "$ENGINE/$rel")"
  dst_sha="$(sha "$SRC_OUT/$base")"
  [ "$src_sha" = "$dst_sha" ] || die "verbatim copy $base sha mismatch (copy corrupted)."
  printf 'VERBATIM   %s  build/src/%s  <=  %s  dynasty/dynasty/%s\n' "$dst_sha" "$base" "$src_sha" "$rel" >> "$MANIFEST"
  echo "    $base"
done

# --- 2) AdaptiveOpponentAIExtract.swift (mechanical slice) ------------------
echo "==> regenerating AdaptiveOpponentAIExtract.swift from repo (awk strip of persona-hint fns)"
EXTRACT="$SRC_OUT/AdaptiveOpponentAIExtract.swift"
SLICE="$(mktemp)"
awk '
  BEGIN { skip = 0 }
  skip == 0 && /^[[:space:]]*static func (defenseKeyHint|exactCallHint|categoryKeyHint|offenseAdjustHint)\(/ {
    skip = 1; depth = 0; seen = 0
  }
  skip == 1 {
    l1 = $0; o = gsub(/[{]/, "X", l1)
    l2 = $0; c = gsub(/[}]/, "X", l2)
    depth += o - c
    if (o > 0) seen = 1
    if (seen == 1 && depth <= 0) skip = 0
    next
  }
  { print }
' "$AI_SOURCE" > "$SLICE"

# 2a) The SLICED CODE must no longer reference the persona types (guard runs on
#     the pure slice — the harness-authored header below intentionally names them).
if grep -qE 'DCPersona|OCPersona' "$SLICE"; then
  grep -nE 'DCPersona|OCPersona' "$SLICE" >&2
  die "extract still references DCPersona/OCPersona — the awk strip failed."
fi

# 2b) ANTI-DRIFT GUARD: every balance-constant line in the repo file must appear
#     byte-identical in the slice. The persona funcs hold no such lines, so a
#     mismatch means the slice mangled a constant — refuse.
CONST_RE='^[[:space:]]*static (let [A-Za-z].*=|func (paKeyCompletion|paKeyBigPlay|runKeyYardBite|runKeyStuffBonus|catPivot|catAlpha)\()'
if ! diff <(grep -E "$CONST_RE" "$AI_SOURCE") <(grep -E "$CONST_RE" "$SLICE") > /dev/null; then
  echo "  --- constant drift (repo <, slice >) ---" >&2
  diff <(grep -E "$CONST_RE" "$AI_SOURCE") <(grep -E "$CONST_RE" "$SLICE") >&2 || true
  die "a balance constant differs between the repo file and the extract."
fi
CONST_COUNT="$(grep -cE "$CONST_RE" "$SLICE")"

# 2c) Assemble: harness header (documents the transform) + verified slice.
{
  echo "// GENERATED by sync_sources.sh — DO NOT EDIT."
  echo "// Source: dynasty/dynasty/Engine/Match/AdaptiveOpponentAI.swift (sha $(sha "$AI_SOURCE"))"
  echo "// Transform: awk-strip of the 4 persona-hint funcs (defenseKeyHint / exactCallHint /"
  echo "//            categoryKeyHint / offenseAdjustHint) — they hold NO balance constants;"
  echo "//            every tuning literal below is the repo byte ($CONST_COUNT lines verified)."
  echo ""
  cat "$SLICE"
} > "$EXTRACT"
rm -f "$SLICE"; SLICE=""
echo "    AdaptiveOpponentAIExtract.swift  ($CONST_COUNT tuning lines verified byte-identical to repo)"
printf 'EXTRACT    %s  build/src/AdaptiveOpponentAIExtract.swift  <=  %s  dynasty/dynasty/Engine/Match/AdaptiveOpponentAI.swift  (persona-hint fns stripped; %s consts verified)\n' \
  "$(sha "$EXTRACT")" "$(sha "$AI_SOURCE")" "$CONST_COUNT" >> "$MANIFEST"

# --- 3) SimPlayer.swift (template + repo splices) ---------------------------
echo "==> assembling SimPlayer.swift (template + verbatim repo splices)"
STORAGE="$(mktemp)"; COMPUTED="$(mktemp)"
# storage decls: `let id: UUID` .. `var fatigue: Int` (verbatim, incl. doc comments)
sed -n '/^    let id: UUID$/,/^    var fatigue: Int$/p' "$SIM_SOURCE" > "$STORAGE"
# computed block: `func schemeFam(...)` .. EOF (schemeFam + Mental Game props +
# struct-close `}` + `enum MentalTemperament`), verbatim.
sed -n '/^    func schemeFam(for scheme: String) -> Int {$/,$p' "$SIM_SOURCE" > "$COMPUTED"
[ -s "$STORAGE" ]  || die "SimPlayer storage splice is empty — repo anchors changed."
[ -s "$COMPUTED" ] || die "SimPlayer computed-block splice is empty — repo anchors changed."
grep -q 'composureRating' "$COMPUTED" || die "SimPlayer computed splice missing composureRating — repo layout changed."
grep -q 'enum MentalTemperament' "$COMPUTED" || die "SimPlayer computed splice missing MentalTemperament — repo layout changed."

SIM_OUT="$SRC_OUT/SimPlayer.swift"
# Match only the STANDALONE marker lines (`    // @@SPLICE:STORAGE@@`), never the
# header prose that names the markers with surrounding text.
awk -v storage="$STORAGE" -v computed="$COMPUTED" '
  /^[[:space:]]*\/\/ @@SPLICE:STORAGE@@[[:space:]]*$/  { while ((getline line < storage)  > 0) print line; close(storage);  next }
  /^[[:space:]]*\/\/ @@SPLICE:COMPUTED@@[[:space:]]*$/ { while ((getline line < computed) > 0) print line; close(computed); next }
  { print }
' "$SIM_TEMPLATE" > "$SIM_OUT"

grep -q 'struct SimPlayer' "$SIM_OUT"      || die "assembled SimPlayer.swift lost its struct."
grep -q 'enum CoachingEngine' "$SIM_OUT"   || die "assembled SimPlayer.swift lost the harness stubs."
# The template's marker lines must have been consumed, not left in the output.
if grep -q '@@SPLICE:' "$SIM_OUT"; then die "a SimPlayer splice marker was left unresolved."; fi
echo "    SimPlayer.swift  (storage + computed-prop block spliced from repo)"
printf 'ASSEMBLED  %s  build/src/SimPlayer.swift  <=  %s  dynasty/dynasty/Engine/Simulation/SimPlayer.swift  (storage+computed spliced into driver/SimPlayer.harness.swift)\n' \
  "$(sha "$SIM_OUT")" "$(sha "$SIM_SOURCE")" >> "$MANIFEST"

echo "==> MANIFEST written to build/src/MANIFEST.txt"
echo "==> sync complete: $(ls "$SRC_OUT"/*.swift | wc -l | tr -d ' ') engine sources staged."
