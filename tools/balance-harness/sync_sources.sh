#!/usr/bin/env bash
# ============================================================================
# sync_sources.sh — stage the balance harness's engine sources from the repo
# ============================================================================
# Populates build/src/ with the CANONICAL engine sources needed to compile the
# balance harness against the SHIPPED simulation math:
#
#   • 30 files copied VERBATIM from the repo (byte-identical; sha-verified).
#     11 play-by-play sources + 6 full-game sources (GameSimulator / DriveSimulator /
#     CoachingModifiers / BoxScore / PlayerGameStats / DriveResult) for the round-5
#     full-game campaign, 7 draft-class generator sources for `draftclass`, and 6
#     development sources (PlayerDevelopmentEngine / PlayerRetirementEngine /
#     MotivationState / InjuryRecord / InjuryType / CampEnums) for `career` — all
#     pure engine, no hand-typed constants.
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
SLICE=""; STORAGE=""; COMPUTED=""; SCOUTSLICE=""; ANCHORS=""; PRODUCTION=""
cleanup() { rm -f "$SLICE" "$STORAGE" "$COMPUTED" "$SCOUTSLICE" "$ANCHORS" "$PRODUCTION"; }
trap cleanup EXIT

# --- Canonical repo sources (relative to $ENGINE) --------------------------
# 31 files copied verbatim: 12 play-by-play + 6 full-game + 7 draft-class +
# 6 development.
VERBATIM_SOURCES=(
  "Domain/Enums/PlayCall.swift"
  # Playbook catalog: the per-scheme install / signature / call-order tables the
  # AdaptiveOpponentAI extract reads (Playbook.isSignature, Playbook.passOrder).
  "Domain/Models/Playbook.swift"
  "Domain/Enums/PlayType.swift"
  "Domain/Enums/Position.swift"
  "Domain/Enums/Scheme.swift"
  "Domain/Enums/GameWeather.swift"
  "Domain/Enums/PersonalityArchetype.swift"
  "Domain/Models/League/PlayResult.swift"
  "Domain/Models/Player/PlayerAttributes.swift"
  "Domain/Models/Team/GamePlan.swift"
  "Engine/Simulation/PlaySimulator.swift"
  "Engine/Match/HeatState.swift"
  # --- round-5 full-game pipeline (sha-verified verbatim; zero hand-typed math) ---
  "Domain/Models/League/DriveResult.swift"
  "Domain/Models/League/BoxScore.swift"
  "Domain/Models/League/PlayerGameStats.swift"
  "Engine/Simulation/CoachingModifiers.swift"
  "Engine/Simulation/DriveSimulator.swift"
  "Engine/Simulation/GameSimulator.swift"
  # --- draft-class generator (stage 4; zero hand-typed generator constants) ------
  "Domain/Enums/Motivation.swift"
  "Domain/Models/Player/PlayerPersonality.swift"
  "Domain/Models/Scouting/LetterGrade.swift"
  "Domain/Models/Player/PositionPhysicalProfile.swift"
  "Domain/Models/Player/MentalAttributeModel.swift"
  "Data/Import/RandomNameGenerator.swift"
  "Engine/Scouting/DraftClassBuilder.swift"
  # --- development stack (stage 5; scenario `career`) ----------------------------
  # The whole realization model is copied byte-for-byte: motivation state machine,
  # R factor, catch-up table, position-shaped regression, potential drift,
  # retirement probability. NOTHING in the career scenario re-implements any of it.
  "Domain/Enums/InjuryType.swift"
  "Domain/Enums/CampEnums.swift"
  "Domain/Enums/MotivationState.swift"
  "Domain/Models/Player/InjuryRecord.swift"
  "Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift"
  "Engine/PlayerDevelopment/PlayerRetirementEngine.swift"
  # --- AI draft fog (Track C; scenario `perception`) -----------------------------
  # Pure Foundation: UUID -> deterministic per-(team, prospect) perceived
  # overall/potential. Copied VERBATIM so the diagnostic measures the shipped
  # sigma/fat-tail model, never a re-typed one.
  "Engine/Draft/AIDraftPerception.swift"
)
AI_SOURCE="$ENGINE/Engine/Match/AdaptiveOpponentAI.swift"
SIM_SOURCE="$ENGINE/Engine/Simulation/SimPlayer.swift"
SIM_TEMPLATE="$HARNESS_DIR/driver/SimPlayer.harness.swift"
# Harness-owned SwiftData-model stubs (Player/Team/Coach/CoachRole + SimPlayer.init(from:))
# copied verbatim so the synced full-game pipeline compiles standalone.
GAMEMODELS_TEMPLATE="$HARNESS_DIR/driver/GameModels.harness.swift"
# --- draft-class staging (scenario `draftclass`) ------------------------------
SCOUT_SOURCE="$ENGINE/Engine/Scouting/ScoutingEngine.swift"
PROSPECT_SOURCE="$ENGINE/Domain/Models/Scouting/CollegeProspect.swift"
PROSPECT_TEMPLATE="$HARNESS_DIR/driver/CollegeProspect.harness.swift"
DRAFTSCENARIO_TEMPLATE="$HARNESS_DIR/driver/DraftClassScenario.harness.swift"
# --- development staging (scenario `career`, plan §6) -------------------------
PLAYER_SOURCE="$ENGINE/Domain/Models/Player/Player.swift"
COACHING_SOURCE="$ENGINE/Engine/Simulation/CoachingEngine.swift"
VERSATILITY_SOURCE="$ENGINE/Engine/PlayerDevelopment/VersatilityDevelopmentEngine.swift"
CONTRACT_SOURCE="$ENGINE/Engine/Contract/ContractEngine.swift"
FOCUS_SOURCE="$ENGINE/Engine/PlayerDevelopment/TrainingFocusEngine.swift"
DRAFTENGINE_SOURCE="$ENGINE/Engine/Draft/DraftEngine.swift"
CAREERSCENARIO_TEMPLATE="$HARNESS_DIR/driver/CareerScenario.harness.swift"
LEAGUEGEN_SOURCE="$ENGINE/Data/Import/LeagueGenerator.swift"
LEAGUEGENSCENARIO_TEMPLATE="$HARNESS_DIR/driver/LeagueGenScenario.harness.swift"
# --- AI draft fog staging (scenario `perception`, Track C) ---------------------
# AIDraftPerception needs exactly two things from the rest of the app: the repo
# RNG (`SeededLeagueRandom`) and the GM archetype draw (`TradeValueEngine`).
# Both are sliced rather than stubbed — a hand-typed sigma table or a re-typed
# archetype threshold is precisely the drift this script exists to prevent.
SEEDRNG_SOURCE="$ENGINE/Domain/Models/Player/TemplateAttributeSolver.swift"
TRADEVALUE_SOURCE="$ENGINE/Engine/Contract/TradeValueEngine.swift"
PERCEPTIONSCENARIO_TEMPLATE="$HARNESS_DIR/driver/PerceptionScenario.harness.swift"

# --- Preflight: refuse to build if any source is missing -------------------
missing=0
for rel in "${VERBATIM_SOURCES[@]}"; do
  [ -f "$ENGINE/$rel" ] || { echo "  MISSING: $ENGINE/$rel" >&2; missing=1; }
done
[ -f "$AI_SOURCE" ]     || { echo "  MISSING: $AI_SOURCE" >&2; missing=1; }
[ -f "$SIM_SOURCE" ]    || { echo "  MISSING: $SIM_SOURCE" >&2; missing=1; }
[ -f "$SIM_TEMPLATE" ]  || { echo "  MISSING: $SIM_TEMPLATE" >&2; missing=1; }
[ -f "$GAMEMODELS_TEMPLATE" ] || { echo "  MISSING: $GAMEMODELS_TEMPLATE" >&2; missing=1; }
[ -f "$SCOUT_SOURCE" ]    || { echo "  MISSING: $SCOUT_SOURCE" >&2; missing=1; }
[ -f "$PROSPECT_SOURCE" ] || { echo "  MISSING: $PROSPECT_SOURCE" >&2; missing=1; }
[ -f "$PROSPECT_TEMPLATE" ]     || { echo "  MISSING: $PROSPECT_TEMPLATE" >&2; missing=1; }
[ -f "$DRAFTSCENARIO_TEMPLATE" ] || { echo "  MISSING: $DRAFTSCENARIO_TEMPLATE" >&2; missing=1; }
for f in "$PLAYER_SOURCE" "$COACHING_SOURCE" "$VERSATILITY_SOURCE" "$CONTRACT_SOURCE" \
         "$FOCUS_SOURCE" "$DRAFTENGINE_SOURCE" "$CAREERSCENARIO_TEMPLATE" \
         "$SEEDRNG_SOURCE" "$TRADEVALUE_SOURCE" "$PERCEPTIONSCENARIO_TEMPLATE"; do
  [ -f "$f" ] || { echo "  MISSING: $f" >&2; missing=1; }
done
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

# --- 4) GameModels.swift (harness-owned SwiftData-model stubs, verbatim copy) -
# No repo splice: these are harness scaffolding (Player/Team/Coach/CoachRole +
# SimPlayer.init(from:)) carrying ZERO balance math, so they are copied straight
# from the driver/ template. They exist only to let the sha-verified full-game
# engine sources above compile & run standalone.
#
# ONE exception (stage 5): the stub `Player` needs the SHIPPED `Player.overall`
# blend, because the `career` scenario develops attributes and must read the same
# rating the app would. Rather than retype the 0.5/0.3/0.2 weights, the repo's own
# computed property is spliced VERBATIM into a `ShippedOverall` carrier.
echo "==> assembling harness model stubs (GameModels.swift + Player.overall splice)"
GAMEMODELS_OUT="$SRC_OUT/GameModels.swift"
OVERALL="$(mktemp)"
sed -n '/^    var overall: Int {$/,/^    }$/p' "$PLAYER_SOURCE" > "$OVERALL"
[ -s "$OVERALL" ] || die "Player.overall splice is empty — repo anchors changed."
grep -q 'positionAttributes.overall' "$OVERALL" || die "Player.overall splice lost the position term — repo layout changed."
grep -q 'mental.average' "$OVERALL"             || die "Player.overall splice lost the mental term — repo layout changed."
awk -v overall="$OVERALL" '
  /^[[:space:]]*\/\/ @@SPLICE:PLAYEROVERALL@@[[:space:]]*$/ { while ((getline line < overall) > 0) print line; close(overall); next }
  { print }
' "$GAMEMODELS_TEMPLATE" > "$GAMEMODELS_OUT"
rm -f "$OVERALL"
if grep -q '@@SPLICE:' "$GAMEMODELS_OUT"; then die "the GameModels PLAYEROVERALL splice marker was left unresolved."; fi
grep -q 'final class Player' "$GAMEMODELS_OUT"   || die "GameModels.swift lost the Player stub."
grep -q 'struct ShippedOverall' "$GAMEMODELS_OUT" || die "GameModels.swift lost the ShippedOverall carrier."
grep -q 'init(from p: Player)' "$GAMEMODELS_OUT" || die "GameModels.swift lost SimPlayer.init(from:)."
# Guard: the stubs must stay math-free. If a repo constant ever needs to live here
# it belongs in a verbatim engine source instead — fail loudly rather than let a
# hand-typed number sneak into the harness (the stale-default incident lesson).
if grep -qE '^[[:space:]]*static let [A-Za-z].*=[[:space:]]*[0-9]' "$GAMEMODELS_OUT"; then
  die "GameModels.swift contains a static-let numeric constant — stubs must carry no balance math."
fi
printf 'ASSEMBLED  %s  build/src/GameModels.swift  <=  %s  dynasty/dynasty/Domain/Models/Player/Player.swift  (overall spliced into driver/GameModels.harness.swift %s)\n' \
  "$(sha "$GAMEMODELS_OUT")" "$(sha "$PLAYER_SOURCE")" "$(sha "$GAMEMODELS_TEMPLATE")" >> "$MANIFEST"
echo "    GameModels.swift  (Player/Team/Coach/CoachRole stubs + SimPlayer.init(from:) + Player.overall splice)"

# --- 5) ScoutingEngineExtract.swift (mechanical KEEP-LIST slice) --------------
# The shipped ScoutingEngine is 3 000 lines wired to Scout / ScoutingReport /
# Coach / Player / GradeRange — none of which the harness compiles. The
# `draftclass` scenario needs exactly four things out of it: the college list,
# the anthropometrics table, the COMBINE math (per-position drill table +
# drillResult + the personality modifier + the relative drill grading) and the
# risk-profile roll. Those members reference nothing outside the verbatim
# sources, so they are sliced out MECHANICALLY (brace/bracket-balanced from each
# named declaration) and re-wrapped in `enum ScoutingEngine { … }`.
#
# ANTI-DRIFT: every non-blank line of the slice must appear VERBATIM in the repo
# file (checked below), and the per-position drill constants must diff clean —
# so no combine mean/σ can ever be hand-typed here.
echo "==> regenerating ScoutingEngineExtract.swift from repo (awk keep-list slice)"
SCOUT_OUT="$SRC_OUT/ScoutingEngineExtract.swift"
SCOUTSLICE="$(mktemp)"; ANCHORS="$(mktemp)"
cat > "$ANCHORS" <<'EOF'
static let colleges = \[
static func generateAnthropometrics\(
static func generateDeclarations\(
static func generateCombineResults\(
private static func applyPositionDrillGrades\(
private static func drillGradeLetter\(
private static func noisyPositionDrillScore\(
enum CombinePositionGroup: Hashable \{
private static func positionGroup\(
struct CombineDrill \{
private enum DrillAttribute \{
enum CombineDrillTable \{
private static func drillResult\(
private static func combinePersonalityModifier\(
static func generateRiskProfile\(
EOF
awk -v anchorfile="$ANCHORS" '
  BEGIN {
    n = 0
    while ((getline line < anchorfile) > 0) { if (line != "") anchors[++n] = "^[[:space:]]*" line }
    close(anchorfile)
    cap = 0
  }
  cap == 0 {
    for (i = 1; i <= n; i++) if ($0 ~ anchors[i]) { cap = 1; depth = 0; seen = 0; break }
  }
  cap == 1 {
    l = $0; o  = gsub(/[{]/, "X", l)
    l = $0; c  = gsub(/[}]/, "X", l)
    l = $0; ob = gsub(/\[/, "X", l)
    l = $0; cb = gsub(/\]/, "X", l)
    depth += (o + ob) - (c + cb)
    # `seen` only flips once the block is actually OPEN — a multi-line signature
    # whose parameter list carries a balanced `[CollegeProspect]` must not be
    # mistaken for the end of the member.
    if (depth > 0) seen = 1
    print
    if (seen == 1 && depth <= 0) { cap = 0; print "" }
  }
' "$SCOUT_SOURCE" > "$SCOUTSLICE"

[ -s "$SCOUTSLICE" ] || die "ScoutingEngine slice is empty — repo anchors changed."
# 5a) Every member the harness names must actually be in the slice.
for want in 'static let colleges' 'generateAnthropometrics' 'generateDeclarations' 'generateCombineResults' \
            'applyPositionDrillGrades' 'drillGradeLetter' 'noisyPositionDrillScore' \
            'enum CombinePositionGroup' 'func positionGroup' 'struct CombineDrill' \
            'enum DrillAttribute' 'enum CombineDrillTable' 'func drillResult' \
            'combinePersonalityModifier' 'generateRiskProfile'; do
  grep -q "$want" "$SCOUTSLICE" || die "ScoutingEngine slice lost '$want' — the awk keep-list failed."
done
# 5b) ANTI-DRIFT GUARD 1: no line may exist in the slice that is not byte-identical
#     to a line of the repo file (i.e. nothing was retyped or mangled).
if grep -vxF -f "$SCOUT_SOURCE" "$SCOUTSLICE" | grep -q '[^[:space:]]'; then
  grep -vxF -f "$SCOUT_SOURCE" "$SCOUTSLICE" | grep '[^[:space:]]' >&2
  die "ScoutingEngine slice contains lines absent from the repo file."
fi
# 5c) ANTI-DRIFT GUARD 2: the per-position combine drill constants must diff clean.
DRILL_RE='^[[:space:]]*(forty|bench|vertical|broad|cone|shuttle): (timed|drill)\('
if ! diff <(grep -E "$DRILL_RE" "$SCOUT_SOURCE") <(grep -E "$DRILL_RE" "$SCOUTSLICE") > /dev/null; then
  diff <(grep -E "$DRILL_RE" "$SCOUT_SOURCE") <(grep -E "$DRILL_RE" "$SCOUTSLICE") >&2 || true
  die "a combine drill constant differs between the repo file and the extract."
fi
DRILL_COUNT="$(grep -cE "$DRILL_RE" "$SCOUTSLICE")"
[ "$DRILL_COUNT" -ge 60 ] || die "only $DRILL_COUNT combine drill lines sliced — expected the full per-position table."
{
  echo "// GENERATED by sync_sources.sh — DO NOT EDIT."
  echo "// Source: dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift (sha $(sha "$SCOUT_SOURCE"))"
  echo "// Transform: awk KEEP-LIST slice of the members the draftclass scenario needs"
  echo "//            (colleges, anthropometrics, the whole combine path, risk profile),"
  echo "//            re-wrapped in the enum. Every line is a repo byte —"
  echo "//            $DRILL_COUNT per-position drill constants verified identical."
  echo ""
  echo "import Foundation"
  echo ""
  echo "enum ScoutingEngine {"
  cat "$SCOUTSLICE"
  echo "}"
} > "$SCOUT_OUT"
rm -f "$SCOUTSLICE" "$ANCHORS"; SCOUTSLICE=""; ANCHORS=""
echo "    ScoutingEngineExtract.swift  ($DRILL_COUNT drill constants verified byte-identical to repo)"
printf 'EXTRACT    %s  build/src/ScoutingEngineExtract.swift  <=  %s  dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift  (keep-list slice; %s drill consts verified)\n' \
  "$(sha "$SCOUT_OUT")" "$(sha "$SCOUT_SOURCE")" "$DRILL_COUNT" >> "$MANIFEST"

# --- 6) CollegeProspect.swift (template + repo math splice) -------------------
echo "==> assembling CollegeProspect.swift (storage stub + verbatim repo math splice)"
PRODUCTION="$(mktemp)"
# Math block: `enum CollegeProductionTier` .. just before the Boom/Bust MARK —
# the tier/competition/archetype enums, collegeYearsStarted, productionTier(forScore:),
# statLine(...) and trueOverall / overallValue (the formula under test).
sed -n '/^    enum CollegeProductionTier: String {$/,/^    \/\/ MARK: - Boom\/Bust Risk Indicator$/p' \
  "$PROSPECT_SOURCE" | sed '$d' > "$PRODUCTION"
[ -s "$PRODUCTION" ] || die "CollegeProspect math splice is empty — repo anchors changed."
grep -q 'static func overallValue' "$PRODUCTION" || die "CollegeProspect splice missing overallValue — repo layout changed."
grep -q 'var trueOverall: Int' "$PRODUCTION"     || die "CollegeProspect splice missing trueOverall — repo layout changed."
grep -q 'static func productionTier' "$PRODUCTION" || die "CollegeProspect splice missing productionTier — repo layout changed."
# Task #181: the usage-suppression math (limited-sample status, the deterministic
# stat-line jitter and the best-season stat line itself) has to come through the
# same splice, or the `draftclass` gate would measure a harness-local stat line.
grep -q 'enum CollegeSampleStatus' "$PRODUCTION"     || die "CollegeProspect splice missing CollegeSampleStatus (#181) — repo layout changed."
grep -q 'var hasLimitedCollegeSample' "$PRODUCTION"  || die "CollegeProspect splice missing hasLimitedCollegeSample (#181) — repo layout changed."
grep -q 'static func productionJitter' "$PRODUCTION" || die "CollegeProspect splice missing productionJitter (#181) — repo layout changed."
grep -q 'static func statLine' "$PRODUCTION"         || die "CollegeProspect splice missing statLine (#181) — repo layout changed."
PROSPECT_OUT="$SRC_OUT/CollegeProspect.swift"
awk -v production="$PRODUCTION" '
  /^[[:space:]]*\/\/ @@SPLICE:PRODUCTION@@[[:space:]]*$/ { while ((getline line < production) > 0) print line; close(production); next }
  { print }
' "$PROSPECT_TEMPLATE" > "$PROSPECT_OUT"
grep -q 'final class CollegeProspect' "$PROSPECT_OUT" || die "assembled CollegeProspect.swift lost its class."
if grep -q '@@SPLICE:' "$PROSPECT_OUT"; then die "the CollegeProspect splice marker was left unresolved."; fi
echo "    CollegeProspect.swift  (production + overall math spliced from repo)"
printf 'ASSEMBLED  %s  build/src/CollegeProspect.swift  <=  %s  dynasty/dynasty/Domain/Models/Scouting/CollegeProspect.swift  (math spliced into driver/CollegeProspect.harness.swift)\n' \
  "$(sha "$PROSPECT_OUT")" "$(sha "$PROSPECT_SOURCE")" >> "$MANIFEST"
rm -f "$PRODUCTION"; PRODUCTION=""

# --- 7) DraftClassScenario.swift (harness-owned scenario, verbatim copy) ------
# Measurement + assertions only: it reads the generator, it never re-implements
# it. Same math-free guard as GameModels.swift.
echo "==> copying draftclass scenario (DraftClassScenario.swift)"
DRAFTSCENARIO_OUT="$SRC_OUT/DraftClassScenario.swift"
cp "$DRAFTSCENARIO_TEMPLATE" "$DRAFTSCENARIO_OUT"
grep -q 'func scenarioDraftClass' "$DRAFTSCENARIO_OUT" || die "DraftClassScenario.swift lost its entry point."
printf 'HARNESS    %s  build/src/DraftClassScenario.swift  <=  (harness-owned scenario) driver/DraftClassScenario.harness.swift  %s\n' \
  "$(sha "$DRAFTSCENARIO_OUT")" "$(sha "$DRAFTSCENARIO_TEMPLATE")" >> "$MANIFEST"
echo "    DraftClassScenario.swift  (200-class distribution report + plan §7 asserts)"

# =============================================================================
# 8) Development-stack extracts (stage 5, scenario `career`)
# =============================================================================
# The realization model itself (PlayerDevelopmentEngine / PlayerRetirementEngine /
# MotivationState) is copied VERBATIM above. What is left are five files that the
# engine reaches into but which cannot compile standalone (SwiftData, SwiftUI, the
# Scout/Career graph). Each is reduced by the SAME mechanical KEEP-LIST slice the
# ScoutingEngine extract uses, then guarded two ways:
#
#   • every non-blank line of the slice must appear byte-identically in the repo
#     file (nothing was retyped or mangled), and
#   • the named single-line tuning constants are grepped straight out of the repo
#     (never transcribed).
#
# So no development constant — the ±15 % position-coach layer, the 0.05 continuity
# bonus, the 1.5 base scheme-learning rate, the 0.49 + readiness·0.28 rookie skill
# factor, the 0.32/0.18/0.06 weekly focus bands — can drift into this harness.

# keeplist_slice <source> <anchors-file> <dest>
#   Copies each named declaration brace/bracket-balanced from its header line to
#   its closing brace. Block members only; single-line `static let`s are pulled by
#   const_lines below (a one-line member has no block for the balancer to close).
keeplist_slice() {
  awk -v anchorfile="$2" '
    BEGIN {
      n = 0
      while ((getline line < anchorfile) > 0) { if (line != "") anchors[++n] = "^[[:space:]]*" line }
      close(anchorfile)
      cap = 0
    }
    cap == 0 {
      for (i = 1; i <= n; i++) if ($0 ~ anchors[i]) { cap = 1; depth = 0; seen = 0; break }
    }
    cap == 1 {
      l = $0; o  = gsub(/[{]/, "X", l)
      l = $0; c  = gsub(/[}]/, "X", l)
      l = $0; ob = gsub(/\[/, "X", l)
      l = $0; cb = gsub(/\]/, "X", l)
      depth += (o + ob) - (c + cb)
      if (depth > 0) seen = 1
      print
      if (seen == 1 && depth <= 0) { cap = 0; print "" }
    }
  ' "$1" > "$3"
  [ -s "$3" ] || die "keep-list slice of $(basename "$1") is empty — repo anchors changed."
}

# verbatim_guard <source> <slice>  — every non-blank slice line must be a repo byte.
verbatim_guard() {
  if grep -vxF -f "$1" "$2" | grep -q '[^[:space:]]'; then
    grep -vxF -f "$1" "$2" | grep '[^[:space:]]' >&2
    die "slice of $(basename "$1") contains lines absent from the repo file."
  fi
}

DEVSLICE=""; DEVANCHORS=""
cleanup_dev() { rm -f "$DEVSLICE" "$DEVANCHORS"; }
trap 'cleanup; cleanup_dev' EXIT

# --- 8a) CoachingEngineExtract.swift -----------------------------------------
echo "==> regenerating CoachingEngineExtract.swift from repo (awk keep-list slice)"
COACHING_OUT="$SRC_OUT/CoachingEngineExtract.swift"
DEVANCHORS="$(mktemp)"; DEVSLICE="$(mktemp)"
# The scheme-fit block (task #54) is sliced too: `rosterSchemeFit` is the ONE
# definition of a rostered player's scheme fit, and the `career` scenario now
# calls it instead of drawing a frozen N(0.55, 0.18). Slicing rather than
# re-typing is the whole point — the shipped distribution and the harness's are
# the same function or the calibration is being validated against a fiction.
cat > "$DEVANCHORS" <<'EOF'
static func hierarchicalDevelopmentBonus\(
static func positionRoleMatch\(
static func rosterSchemeFit\(
private static func schemeTraitEdge\(
private static func activeSchemeFamiliarity\(
private static func schemeFit\(
static func normalize\(
EOF
keeplist_slice "$COACHING_SOURCE" "$DEVANCHORS" "$DEVSLICE"
verbatim_guard "$COACHING_SOURCE" "$DEVSLICE"
COACHING_CONSTS="$(grep -E '^[[:space:]]*static let (coordinatorContinuitySeasons|coordinatorContinuityBonus|developmentBonusPivot|schemeFitNeutral|schemeFitTraitGain|schemeFitFamiliarityGain|schemeFitFamiliarityPivot|schemeFitFloor|schemeFitCeiling) =' "$COACHING_SOURCE")"
[ -n "$COACHING_CONSTS" ] || die "CoachingEngine continuity constants not found in the repo file."
grep -q 'hierarchicalDevelopmentBonus' "$DEVSLICE" || die "CoachingEngine slice lost hierarchicalDevelopmentBonus."
grep -q 'positionRoleMatch' "$DEVSLICE"            || die "CoachingEngine slice lost positionRoleMatch."
grep -q 'rosterSchemeFit' "$DEVSLICE"              || die "CoachingEngine slice lost rosterSchemeFit."
grep -q 'schemeTraitEdge' "$DEVSLICE"              || die "CoachingEngine slice lost schemeTraitEdge."
grep -q 'activeSchemeFamiliarity' "$DEVSLICE"      || die "CoachingEngine slice lost activeSchemeFamiliarity."
grep -q 'rawScore + adaptabilityBonus' "$DEVSLICE" || die "CoachingEngine slice lost the trait scheme-fit core."
for k in schemeFitNeutral schemeFitTraitGain schemeFitFamiliarityGain schemeFitFamiliarityPivot developmentBonusPivot; do
  printf '%s\n' "$COACHING_CONSTS" | grep -q "$k" || die "CoachingEngine slice lost $k."
done
{
  echo "// GENERATED by sync_sources.sh — DO NOT EDIT."
  echo "// Source: dynasty/dynasty/Engine/Simulation/CoachingEngine.swift (sha $(sha "$COACHING_SOURCE"))"
  echo "// Transform: awk KEEP-LIST slice of the 4-layer development multiplier and the"
  echo "//            position-role matcher, re-wrapped as an extension of the harness"
  echo "//            CoachingEngine stub. Every line is a repo byte."
  echo ""
  echo "import Foundation"
  echo ""
  echo "extension CoachingEngine {"
  echo "$COACHING_CONSTS"
  echo ""
  cat "$DEVSLICE"
  echo "}"
} > "$COACHING_OUT"
printf 'EXTRACT    %s  build/src/CoachingEngineExtract.swift  <=  %s  dynasty/dynasty/Engine/Simulation/CoachingEngine.swift  (keep-list slice)\n' \
  "$(sha "$COACHING_OUT")" "$(sha "$COACHING_SOURCE")" >> "$MANIFEST"
echo "    CoachingEngineExtract.swift"

# --- 8b) VersatilityExtract.swift --------------------------------------------
echo "==> regenerating VersatilityExtract.swift from repo (awk keep-list slice)"
VERS_OUT="$SRC_OUT/VersatilityExtract.swift"
cat > "$DEVANCHORS" <<'EOF'
static func learnScheme\(
static func decayUnusedSchemes\(
static func installBaseline\(
static func seedActiveSchemes\(
static func earlyCareerLearnMultiplier\(
EOF
keeplist_slice "$VERSATILITY_SOURCE" "$DEVANCHORS" "$DEVSLICE"
verbatim_guard "$VERSATILITY_SOURCE" "$DEVSLICE"
VERS_CONSTS="$(grep -E '^[[:space:]]*static let (schemeInstallIntensityBonus|unusedSchemeDecayPerOffseason|unusedSchemeFloor|installBaselineFloor|installBaselineLearningWeight|installBaselineCoachabilityWeight|installBaselineCarryOver|installBaselineCap|earlyCareerLearnBonus|earlyCareerLearnWindow) =' "$VERSATILITY_SOURCE")"
[ -n "$VERS_CONSTS" ] || die "VersatilityDevelopmentEngine scheme constants not found in the repo file."
grep -q 'learningRate \*= Double(player.learning)' "$DEVSLICE" || die "Versatility slice lost the learning term."
grep -q 'seedActiveSchemes' "$DEVSLICE" || die "Versatility slice lost seedActiveSchemes (task #54)."
grep -q 'installBaselineCarryOver' "$DEVSLICE" || die "Versatility slice lost the install-baseline carry-over."
{
  echo "// GENERATED by sync_sources.sh — DO NOT EDIT."
  echo "// Source: dynasty/dynasty/Engine/PlayerDevelopment/VersatilityDevelopmentEngine.swift (sha $(sha "$VERSATILITY_SOURCE"))"
  echo "// Transform: awk KEEP-LIST slice of the scheme-learning path, re-wrapped as an"
  echo "//            extension of the harness VersatilityDevelopmentEngine stub."
  echo ""
  echo "import Foundation"
  echo ""
  echo "extension VersatilityDevelopmentEngine {"
  echo "$VERS_CONSTS"
  echo ""
  cat "$DEVSLICE"
  echo "}"
} > "$VERS_OUT"
printf 'EXTRACT    %s  build/src/VersatilityExtract.swift  <=  %s  dynasty/dynasty/Engine/PlayerDevelopment/VersatilityDevelopmentEngine.swift  (keep-list slice)\n' \
  "$(sha "$VERS_OUT")" "$(sha "$VERSATILITY_SOURCE")" >> "$MANIFEST"
echo "    VersatilityExtract.swift"

# --- 8c) ContractEngineExtract.swift -----------------------------------------
echo "==> regenerating ContractEngineExtract.swift from repo (awk keep-list slice)"
CONTRACT_OUT="$SRC_OUT/ContractEngineExtract.swift"
cat > "$DEVANCHORS" <<'EOF'
static let leagueAffordabilityScale
static func veteranMinimum\(
static func estimateMarketValue\(
static func marketBasePercent\(
private static func quarterbackScarcityFloor\(
static func naturalPositionForAttributes\(
static func attributeGroupPremium\(
static func physicalFitZ\(
static func bestPayingPosition\(
EOF
keeplist_slice "$CONTRACT_SOURCE" "$DEVANCHORS" "$DEVSLICE"
verbatim_guard "$CONTRACT_SOURCE" "$DEVSLICE"
grep -q 'basePercent \* positionMultiplier(position)' "$DEVSLICE" || die "ContractEngine slice lost the market-value formula."
# The league minimum is a DEFINITION the sliced formula calls, not a constant the
# grep block below can reach (it is a func, so `CONTRACT_CONSTS` cannot see it).
# `estimateMarketValue` ends `max(Int(value), veteranMinimum(cap: salaryCap))`,
# so a slice without the definition compiles to "cannot find 'veteranMinimum' in
# scope" — the same class of break as task #52.
grep -q 'static func veteranMinimum(cap: Int) -> Int' "$DEVSLICE" \
  || die "ContractEngine slice lost veteranMinimum — estimateMarketValue's floor calls it."
grep -q 'veteranMinimum(cap: salaryCap)' "$DEVSLICE" \
  || die "ContractEngine slice lost estimateMarketValue's veteran-minimum floor."
# Task #87: the cap itself, the league-year growth roll and the position-switch
# fit floor are the file's four bare constants. They cannot be reached by a
# keep-list anchor (a `static let` line has no braces, so the slicer would run on
# into whatever follows it), so they come across by grep like every other
# constant block in this script.
CONTRACT_CONSTS="$(grep -E '^[[:space:]]*static let (openingSalaryCap|capGrowthRange|capGrowthPerSeason|positionSwitchFitFloor)(: [A-Za-z<>]+)? =' "$CONTRACT_SOURCE")"
for k in openingSalaryCap capGrowthRange capGrowthPerSeason positionSwitchFitFloor; do
  printf '%s\n' "$CONTRACT_CONSTS" | grep -qE "static let $k(:| =)" || die "ContractEngine constant $k not found in the repo file."
done
# Task #87 / F2: the upgrade gate. Without these three the six formerly-dead
# position multipliers go dead again and the harness would measure the OLD
# effective table while the app measured the new one — the exact split-brain the
# wave exists to close.
grep -q 'static func attributeGroupPremium' "$DEVSLICE" || die "ContractEngine slice lost attributeGroupPremium (F2 gate)."
grep -q 'static func physicalFitZ' "$DEVSLICE" || die "ContractEngine slice lost physicalFitZ (F2 gate)."
grep -q 'guard attributeGroupPremium(for: current) != natural' "$DEVSLICE" \
  || die "ContractEngine slice lost the real-position-change gate (F2)."
# F20: one multiplier table, used by both the valuation and the ranking.
grep -q 'static func positionMultiplier' "$DEVSLICE" \
  || die "ContractEngine slice lost the single positionMultiplier table (F20)."
# Task #27 put the league's price LEVEL in its own constant; the formula above
# multiplies by it, so a slice without it compiles against a missing symbol.
grep -q 'leagueAffordabilityScale = ' "$DEVSLICE" \
  || die "ContractEngine slice lost leagueAffordabilityScale."
# The P1 pyramid wave moved the OVR→money ladder into its own function, so the
# slice has to carry it too or the harness compiles against a missing symbol.
grep -q 'anchors: \[(ovr: Double, pct: Double)\]' "$DEVSLICE" \
  || die "ContractEngine slice lost marketBasePercent's anchor ladder."
# Task #163: the quarterback scarcity shoulder is a SECOND price curve on the
# same path — `estimateMarketValue` floors a QB's base percent with it over
# OVR 85-92. Both halves have to cross or the harness measures a market the app
# does not have: without the definition the slice will not compile, and without
# the call site it would compile and silently price every 85-91 quarterback ~20 %
# under the shipped game.
grep -q 'private static func quarterbackScarcityFloor(overall: Int) -> Double' "$DEVSLICE" \
  || die "ContractEngine slice lost quarterbackScarcityFloor (task #163)."
grep -q 'quarterbackScarcityFloor(overall: overall)' "$DEVSLICE" \
  || die "ContractEngine slice lost estimateMarketValue's QB scarcity floor (task #163)."
{
  echo "// GENERATED by sync_sources.sh — DO NOT EDIT."
  echo "// Source: dynasty/dynasty/Engine/Contract/ContractEngine.swift (sha $(sha "$CONTRACT_SOURCE"))"
  echo "// Transform: awk KEEP-LIST slice of the market-value path — the ONLY thing the"
  echo "//            motivation state machine's post-payday trigger reads."
  echo ""
  echo "import Foundation"
  echo ""
  echo "enum ContractEngine {"
  echo "$CONTRACT_CONSTS"
  echo ""
  cat "$DEVSLICE"
  echo "}"
} > "$CONTRACT_OUT"
printf 'EXTRACT    %s  build/src/ContractEngineExtract.swift  <=  %s  dynasty/dynasty/Engine/Contract/ContractEngine.swift  (keep-list slice)\n' \
  "$(sha "$CONTRACT_OUT")" "$(sha "$CONTRACT_SOURCE")" >> "$MANIFEST"
echo "    ContractEngineExtract.swift"

# --- 8d) TrainingFocusExtract.swift ------------------------------------------
# Two slices from one file: the TrainingFocusArea enum stays top-level, the engine
# members are re-wrapped. Everything the Career/SwiftData-bound report builder and
# the breakout-cap persistence need is left behind.
echo "==> regenerating TrainingFocusExtract.swift from repo (awk keep-list slice x2)"
FOCUS_OUT="$SRC_OUT/TrainingFocusExtract.swift"
FOCUS_AREA="$(mktemp)"
cat > "$DEVANCHORS" <<'EOF'
enum TrainingFocusArea: String, Codable, CaseIterable, Identifiable \{
EOF
keeplist_slice "$FOCUS_SOURCE" "$DEVANCHORS" "$FOCUS_AREA"
verbatim_guard "$FOCUS_SOURCE" "$FOCUS_AREA"
cat > "$DEVANCHORS" <<'EOF'
struct FocusGain \{
static func applyWeeklyFocusTick\(
static func weeklyGainChance\(
static func autoAssignFocus\(
static func potentialCeiling\(
static func applyFocusPoint\(
private static func bump<T>\(
EOF
keeplist_slice "$FOCUS_SOURCE" "$DEVANCHORS" "$DEVSLICE"
verbatim_guard "$FOCUS_SOURCE" "$DEVSLICE"
FOCUS_CONSTS="$(grep -E '^[[:space:]]*static let maxFocusPlayersPerTeam =' "$FOCUS_SOURCE")"
[ -n "$FOCUS_CONSTS" ] || die "TrainingFocusEngine slot cap constant not found in the repo file."
grep -q 'base = 0.32' "$DEVSLICE" || die "TrainingFocus slice lost the pre-peak weekly gain band."
grep -q 'focusGainMultiplier' "$DEVSLICE" || die "TrainingFocus slice lost the motivation multiplier."
{
  echo "// GENERATED by sync_sources.sh — DO NOT EDIT."
  echo "// Source: dynasty/dynasty/Engine/PlayerDevelopment/TrainingFocusEngine.swift (sha $(sha "$FOCUS_SOURCE"))"
  echo "// Transform: awk KEEP-LIST slices — the TrainingFocusArea enum verbatim at top"
  echo "//            level, plus the weekly-tick members re-wrapped in the enum. The"
  echo "//            Career-persisted breakout cap and the SwiftData report builder are"
  echo "//            deliberately left behind (the harness has no store)."
  echo ""
  echo "import Foundation"
  echo ""
  cat "$FOCUS_AREA"
  echo "enum TrainingFocusEngine {"
  echo "$FOCUS_CONSTS"
  echo ""
  cat "$DEVSLICE"
  echo "}"
} > "$FOCUS_OUT"
rm -f "$FOCUS_AREA"
printf 'EXTRACT    %s  build/src/TrainingFocusExtract.swift  <=  %s  dynasty/dynasty/Engine/PlayerDevelopment/TrainingFocusEngine.swift  (keep-list slice)\n' \
  "$(sha "$FOCUS_OUT")" "$(sha "$FOCUS_SOURCE")" >> "$MANIFEST"
echo "    TrainingFocusExtract.swift"

# --- 8e) DraftEngineExtract.swift --------------------------------------------
# Draft-day INTAKE: the readiness/learning rookie scaling and the familiarity seed.
# The career scenario converts prospects through these exact functions, so the
# rookie level it measures is the one the app ships.
echo "==> regenerating DraftEngineExtract.swift from repo (awk keep-list slice)"
DRAFTENGINE_OUT="$SRC_OUT/DraftEngineExtract.swift"
cat > "$DEVANCHORS" <<'EOF'
struct RookieScaleFactors \{
static func rookieScaleFactors\(
private static func scaleAttribute\(
static func scalePhysical\(
static func scaleMental\(
static func scalePositionAttributes\(
static func roundForPick\(
private static let rookieSlotAnchors
static func rookieSlotCapPercent\(
static func rookieContract\(
static func udfaContract\(
static func initializeRookieFamiliarity\(
static func aiMakePick\(
private static func evaluateTeamNeeds\(
private static func teamNeedComponents\(
EOF
keeplist_slice "$DRAFTENGINE_SOURCE" "$DEVANCHORS" "$DEVSLICE"
verbatim_guard "$DRAFTENGINE_SOURCE" "$DEVSLICE"
# Track C: the AI scorer itself comes across so the `perception` diagnostic
# measures the SHIPPED board, need model and top-4 weighted-random pick.
grep -q 'AIDraftPerception.read(' "$DEVSLICE" || die "DraftEngine slice lost the AI perceived-value read (Track C)."
grep -q 'let weights: \[Double\] = \[0.65, 0.20, 0.10, 0.05\]' "$DEVSLICE" || die "DraftEngine slice lost the R24 top-4 pick weights."
DRAFTENGINE_CONSTS="$(grep -E '^[[:space:]]*(private )?static let (attributeFloor|rawnessPivot|veteranMinimumCapPercent|rookieFamiliarity[A-Za-z]*) =' "$DRAFTENGINE_SOURCE")"
echo "$DRAFTENGINE_CONSTS" | grep -q attributeFloor || die "DraftEngine attributeFloor constant not found in the repo file."
echo "$DRAFTENGINE_CONSTS" | grep -q rawnessPivot  || die "DraftEngine rawnessPivot constant not found in the repo file."
# Task #89 follow-up: the rookie slot curve now extrapolates past the last
# anchor and floors at the veteran minimum, so the slice needs that constant or
# `rookieSlotCapPercent` does not compile in the harness.
echo "$DRAFTENGINE_CONSTS" | grep -q veteranMinimumCapPercent \
  || die "DraftEngine veteranMinimumCapPercent constant not found in the repo file."
grep -q 'max(veteranMinimumCapPercent, extrapolated)' "$DEVSLICE" \
  || die "DraftEngine slice lost the post-224 rookie slot extrapolation."
for k in rookieFamiliarityFloor rookieFamiliarityReadinessWeight rookieFamiliarityLearningWeight rookieFamiliarityUDFAPenalty; do
  echo "$DRAFTENGINE_CONSTS" | grep -q "$k" || die "DraftEngine constant $k not found in the repo file."
done
grep -q 'skill: .*readinessShare \*' "$DEVSLICE" || die "DraftEngine slice lost the rookie skill-scaling term."
# Task #89 / F2: the harness used to ship its OWN five-branch rookie wage scale
# in CareerScenario.harness.swift, so the money a drafted rookie cost in the
# harness and the money he cost in the app were two unrelated tables. The slot
# curve now comes across verbatim and `crRookieSalary` calls it.
grep -q 'static func rookieContract(pickNumber' "$DEVSLICE" \
  || die "DraftEngine slice lost the rookie wage scale (task #89 / F2)."
grep -q 'rookieSlotAnchors' "$DEVSLICE" \
  || die "DraftEngine slice lost the rookie slot anchors (task #89 / F2)."
grep -q 'mental: .*learningShare \*' "$DEVSLICE"  || die "DraftEngine slice lost the rookie mental-scaling term."
{
  echo "// GENERATED by sync_sources.sh — DO NOT EDIT."
  echo "// Source: dynasty/dynasty/Engine/Draft/DraftEngine.swift (sha $(sha "$DRAFTENGINE_SOURCE"))"
  echo "// Transform: awk KEEP-LIST slice of the prospect→Player conversion math"
  echo "//            (readiness-driven scaling + rookie familiarity seed)."
  echo ""
  echo "import Foundation"
  echo ""
  echo "enum DraftEngine {"
  echo "$DRAFTENGINE_CONSTS"
  echo ""
  cat "$DEVSLICE"
  echo "}"
} > "$DRAFTENGINE_OUT"
printf 'EXTRACT    %s  build/src/DraftEngineExtract.swift  <=  %s  dynasty/dynasty/Engine/Draft/DraftEngine.swift  (keep-list slice)\n' \
  "$(sha "$DRAFTENGINE_OUT")" "$(sha "$DRAFTENGINE_SOURCE")" >> "$MANIFEST"
echo "    DraftEngineExtract.swift"

# --- 8f) LeagueGeneratorExtract.swift ----------------------------------------
# The RANDOM league's rating math — the intake level and shape that the P1
# quality-pyramid wave calibrated. Only the pure level/range functions come
# across; everything around them in LeagueGenerator (SwiftData, NFLTeamData,
# owners, coaches, salaries, draft picks) is left behind. The `leaguegen`
# scenario assembles a 53-man roster out of these and reads `Player.overall`, so
# the pyramid it reports is the SHIPPED generator's, not a re-implementation.
#
# This exists because every distribution number in
# `LeagueGenerator.targetQualityPyramid` was fitted on the Python mirror in
# tools/league-data/make_templates.py. A mirror that silently drifts from the
# Swift is the one failure mode that would invalidate the whole calibration
# (and the template league with it), so the two are now measured against the
# same bands from opposite sides.
echo "==> regenerating LeagueGeneratorExtract.swift from repo (awk keep-list slice)"
LEAGUEGEN_OUT="$SRC_OUT/LeagueGeneratorExtract.swift"
cat > "$DEVANCHORS" <<'EOF'
private static let rosterBlueprint
static func ageLevelShift\(
static func veteranLevelShift\(
static func talentLevelShift<G: RandomNumberGenerator>\(
static func positionAttributeRange\(
private static func rndAttr\(
private static func randomPositionAttributes\(
private static func randomAge\(
private static func careerAgeSpan\(
static func veteranPotential\(
static func tierEarnedUpside\(
static func activeSchemeSeed<G: RandomNumberGenerator>\(
static func realisticSalary<G: RandomNumberGenerator>\(
static func overallDrift\(
EOF
keeplist_slice "$LEAGUEGEN_SOURCE" "$DEVANCHORS" "$DEVSLICE"
verbatim_guard "$LEAGUEGEN_SOURCE" "$DEVSLICE"
LEAGUEGEN_CONSTS="$(grep -E '^[[:space:]]*static let ((rookieAgeLevel|primeAgeLevel|pastPeakAgeDecay|talentSpreadLimit): Double|rosterCapTargetBand: ClosedRange<Int>|rookieDealYears|preePeakOverallGain|postPeakOverallLoss|earlyExtensionOverall) =' "$LEAGUEGEN_SOURCE")"
for k in rookieAgeLevel primeAgeLevel pastPeakAgeDecay talentSpreadLimit \
         rosterCapTargetBand rookieDealYears preePeakOverallGain postPeakOverallLoss earlyExtensionOverall; do
  echo "$LEAGUEGEN_CONSTS" | grep -q "$k" || die "LeagueGenerator constant $k not found in the repo file."
done
# Task #87 / F1: the roster seeder. `leaguegen` prices a generated league off it
# and gates the result, so a seeder that stopped reading `overall` — the defect
# the wave fixed — would fail the harness instead of shipping silently.
grep -q 'let marketThen = ContractEngine.estimateMarketValue(' "$DEVSLICE" \
  || die "LeagueGenerator slice lost the rating-aware salary seed (F1)."
grep -q 'let extendedEarly = overall >= earlyExtensionOverall' "$DEVSLICE" \
  || die "LeagueGenerator slice lost the early-extension rule (F1)."
grep -q 'let capThen = max(' "$DEVSLICE" \
  || die "LeagueGenerator slice lost the deal-age back-dating (F1)." 
grep -q 'z \* (z >= 0 ? up : down)' "$DEVSLICE" || die "LeagueGenerator slice lost the split-normal talent draw."
grep -q 'case 0:  return 66...88' "$DEVSLICE" || die "LeagueGenerator slice lost the depth-tier rating ranges."
grep -q 'rosterBlueprint' "$DEVSLICE" || die "LeagueGenerator slice lost the 53-man rosterBlueprint."
# Task #66's day-one familiarity curve. It decides what EVERY new save's league
# knows about its own playbook on the morning of season 1, and until #85 nothing
# in the repo measured it — `career` gates the DEVELOPMENT equilibrium the curve
# was fitted to, not the curve. `leaguegen` gates the curve.
grep -q '78.0 - 34.0 \* pow(0.78' "$DEVSLICE" || die "LeagueGenerator slice lost the activeSchemeSeed tenure curve."
# Sole mechanical transform, applied AFTER verbatim_guard has proved every line is
# a repo byte: drop `private` so the scenario in the neighbouring file can call
# these. `private` in Swift is declaration-scoped, and the extract lands in its own
# file, so the slice would otherwise compile but be unreachable. No other token is
# touched — the rating math is repo bytes.
sed -i '' 's/^\([[:space:]]*\)private static /\1static /' "$DEVSLICE"
grep -q 'private static' "$DEVSLICE" && die "LeagueGenerator slice still carries a private member."
# The blueprint sums to 53 with WR/DE/CB split across a base entry and an
# "extra depth" entry; the scenario walks it in order, exactly as generateRoster
# does, so that split matters and is asserted here rather than assumed.
BP_TOTAL="$(awk '/static let rosterBlueprint/,/^[[:space:]]*\][[:space:]]*$/' "$DEVSLICE" \
  | grep -o '\.[A-Za-z]*, [0-9]*' | awk -F', ' '{s+=$2} END {print s}')"
[ "$BP_TOTAL" = "53" ] || die "LeagueGenerator rosterBlueprint no longer sums to 53 (got $BP_TOTAL)."
{
  echo "// GENERATED by sync_sources.sh — DO NOT EDIT."
  echo "// Source: dynasty/dynasty/Data/Import/LeagueGenerator.swift (sha $(sha "$LEAGUEGEN_SOURCE"))"
  echo "// Transform: awk KEEP-LIST slice of the RATING path only (age level curve,"
  echo "//            talent spread, depth ranges, position-attribute draw, age draw,"
  echo "//            veteran potential) plus the rosterBlueprint and the four level"
  echo "//            constants, all verbatim repo bytes."
  echo ""
  echo "import Foundation"
  echo ""
  echo "enum LeagueGenerator {"
  echo "$LEAGUEGEN_CONSTS"
  echo ""
  cat "$DEVSLICE"
  echo "}"
} > "$LEAGUEGEN_OUT"
printf 'EXTRACT    %s  build/src/LeagueGeneratorExtract.swift  <=  %s  dynasty/dynasty/Data/Import/LeagueGenerator.swift  (keep-list slice)\n' \
  "$(sha "$LEAGUEGEN_OUT")" "$(sha "$LEAGUEGEN_SOURCE")" >> "$MANIFEST"
echo "    LeagueGeneratorExtract.swift"

# --- 8g) SeededRandomExtract.swift -------------------------------------------
# The repo's SplitMix64 (`SeededLeagueRandom`), which `AIDraftPerception` seeds
# from the (team, prospect) pair. Sliced, not re-typed: the harness must draw
# the SAME error for the same pair the app draws, or the fog it measures is a
# different fog.
echo "==> regenerating SeededRandomExtract.swift from repo (awk keep-list slice)"
SEEDRNG_OUT="$SRC_OUT/SeededRandomExtract.swift"
cat > "$DEVANCHORS" <<'EOF'
struct SeededLeagueRandom: RandomNumberGenerator \{
EOF
keeplist_slice "$SEEDRNG_SOURCE" "$DEVANCHORS" "$DEVSLICE"
verbatim_guard "$SEEDRNG_SOURCE" "$DEVSLICE"
grep -q '0x9E37_79B9_7F4A_7C15' "$DEVSLICE" || die "SeededLeagueRandom slice lost the SplitMix64 gamma."
{
  echo "// GENERATED by sync_sources.sh — DO NOT EDIT."
  echo "// Source: dynasty/dynasty/Domain/Models/Player/TemplateAttributeSolver.swift (sha $(sha "$SEEDRNG_SOURCE"))"
  echo "// Transform: awk KEEP-LIST slice of the file-scope SplitMix64 generator."
  echo ""
  echo "import Foundation"
  echo ""
  cat "$DEVSLICE"
} > "$SEEDRNG_OUT"
printf 'EXTRACT    %s  build/src/SeededRandomExtract.swift  <=  %s  dynasty/dynasty/Domain/Models/Player/TemplateAttributeSolver.swift  (keep-list slice)\n' \
  "$(sha "$SEEDRNG_OUT")" "$(sha "$SEEDRNG_SOURCE")" >> "$MANIFEST"
echo "    SeededRandomExtract.swift"

# --- 8h) GMPersonaExtract.swift ----------------------------------------------
# The GM archetype draw the draft fog keys its sigma off. Only the persona block
# comes across (archetype table + `GMPersona.forTeam` + the UUID byte helper);
# the 3 000 lines of pricing, stances and negotiation around it stay behind —
# they need DraftPick / Player / SwiftData, none of which the harness compiles.
echo "==> regenerating GMPersonaExtract.swift from repo (awk keep-list slice)"
GMPERSONA_OUT="$SRC_OUT/GMPersonaExtract.swift"
cat > "$DEVANCHORS" <<'EOF'
enum GMArchetype: String, CaseIterable \{
struct GMPersona \{
private static let gmNamePool: \[String\] = \[
private static func uuidDice\(
EOF
keeplist_slice "$TRADEVALUE_SOURCE" "$DEVANCHORS" "$DEVSLICE"
verbatim_guard "$TRADEVALUE_SOURCE" "$DEVSLICE"
grep -q 'case ..<26:  archetype = .oldSchool' "$DEVSLICE" || die "GMPersona slice lost the archetype thresholds."
grep -q 'static func forTeam(id: UUID) -> GMPersona' "$DEVSLICE" || die "GMPersona slice lost forTeam."
{
  echo "// GENERATED by sync_sources.sh — DO NOT EDIT."
  echo "// Source: dynasty/dynasty/Engine/Contract/TradeValueEngine.swift (sha $(sha "$TRADEVALUE_SOURCE"))"
  echo "// Transform: awk KEEP-LIST slice of the GM-persona block only, re-wrapped in"
  echo "//            enum TradeValueEngine. Every line is a repo byte."
  echo ""
  echo "import Foundation"
  echo ""
  echo "enum TradeValueEngine {"
  cat "$DEVSLICE"
  echo "}"
} > "$GMPERSONA_OUT"
printf 'EXTRACT    %s  build/src/GMPersonaExtract.swift  <=  %s  dynasty/dynasty/Engine/Contract/TradeValueEngine.swift  (keep-list slice)\n' \
  "$(sha "$GMPERSONA_OUT")" "$(sha "$TRADEVALUE_SOURCE")" >> "$MANIFEST"
echo "    GMPersonaExtract.swift"

# --- 9) CareerScenario.swift (harness-owned scenario, verbatim copy) ----------
# League scaffolding + measurement + assertions only: it drives the staged engine,
# it never re-implements it. Same math-free guard as GameModels.swift.
echo "==> copying career scenario (CareerScenario.swift)"
CAREERSCENARIO_OUT="$SRC_OUT/CareerScenario.swift"
cp "$CAREERSCENARIO_TEMPLATE" "$CAREERSCENARIO_OUT"
grep -q 'func scenarioCareer' "$CAREERSCENARIO_OUT" || die "CareerScenario.swift lost its entry point."
printf 'HARNESS    %s  build/src/CareerScenario.swift  <=  (harness-owned scenario) driver/CareerScenario.harness.swift  %s\n' \
  "$(sha "$CAREERSCENARIO_OUT")" "$(sha "$CAREERSCENARIO_TEMPLATE")" >> "$MANIFEST"
echo "    CareerScenario.swift  (32-team synthetic league + plan §6 asserts)"

# --- 9b) LeagueGenScenario.swift (harness-owned scenario, verbatim copy) ------
echo "==> copying league-generator scenario (LeagueGenScenario.swift)"
LEAGUEGENSCENARIO_OUT="$SRC_OUT/LeagueGenScenario.swift"
cp "$LEAGUEGENSCENARIO_TEMPLATE" "$LEAGUEGENSCENARIO_OUT"
grep -q 'func scenarioLeagueGen' "$LEAGUEGENSCENARIO_OUT" || die "LeagueGenScenario.swift lost its entry point."
printf 'HARNESS    %s  build/src/LeagueGenScenario.swift  <=  (harness-owned scenario) driver/LeagueGenScenario.harness.swift  %s\n' \
  "$(sha "$LEAGUEGENSCENARIO_OUT")" "$(sha "$LEAGUEGENSCENARIO_TEMPLATE")" >> "$MANIFEST"
echo "    LeagueGenScenario.swift  (t=0 intake pyramid vs DEVELOPMENT_NFL_REFERENCE §8)"

# --- 9c) PerceptionScenario.swift (harness-owned scenario, verbatim copy) -----
echo "==> copying draft-fog scenario (PerceptionScenario.swift)"
PERCEPTIONSCENARIO_OUT="$SRC_OUT/PerceptionScenario.swift"
cp "$PERCEPTIONSCENARIO_TEMPLATE" "$PERCEPTIONSCENARIO_OUT"
grep -q 'func scenarioPerception' "$PERCEPTIONSCENARIO_OUT" || die "PerceptionScenario.swift lost its entry point."
if grep -qE '^[[:space:]]*(private )?(static )?let (sigma|fatTail)[A-Za-z]* *=' "$PERCEPTIONSCENARIO_OUT"; then
  die "PerceptionScenario.swift re-types a perception constant — it must read them off AIDraftPerception."
fi
printf 'HARNESS    %s  build/src/PerceptionScenario.swift  <=  (harness-owned scenario) driver/PerceptionScenario.harness.swift  %s\n' \
  "$(sha "$PERCEPTIONSCENARIO_OUT")" "$(sha "$PERCEPTIONSCENARIO_TEMPLATE")" >> "$MANIFEST"
echo "    PerceptionScenario.swift  (AI draft fog diagnostic — reaches/steals/|err| by persona)"

echo "==> MANIFEST written to build/src/MANIFEST.txt"
echo "==> sync complete: $(ls "$SRC_OUT"/*.swift | wc -l | tr -d ' ') engine sources staged."
