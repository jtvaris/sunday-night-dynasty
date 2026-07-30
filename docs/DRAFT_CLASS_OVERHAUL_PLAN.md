# Draft Class Overhaul — Analysis & Implementation Plan

Companion data file: `docs/DRAFT_NFL_REFERENCE.md` (all calibration targets trace there).
Scope: draft class **generation**, prospect→player conversion, rookie readiness,
intelligence/learning attribute, college production surfacing. Player development
& training deep-dive is **phase 2** (hooks defined in §9, not implemented now).

---

## 1. Why the current class is unrealistic (verified by Monte Carlo of the shipped code)

Simulating the exact shipped algorithm (300 classes) reproduces the user's report:
QB avg **2.79 R1 grades + 38.1 R2 grades**, best RB median **round 6**, best S
**round 6** (round 5 in "weak" years), WR gets any R1 grade in **1 %** of classes,
CB in **0 %**. Root causes, all in `dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift`
unless noted:

| # | Defect | Code |
|---|---|---|
| A | `trueOverall` has σ≈1.5 (range 60–69 across all 350) because `bellCurveRating` (`:400-407`) halves variance twice, and **position skills are excluded from `trueOverall`** (`CollegeProspect.swift:304-308`). The sort key `trueOverall × positionalDraftValue` (`:145-149`) therefore degenerates into a pure position sort — positional tier gaps (≥2σ) dominate the talent noise. | `:145-149`, `:400-407` |
| B | QB quota is 42/350 = **11.7 %** of the class (`:21-27`) while round 1 is the top 9 % of ranks — QBs monopolize every R1 slot before caps apply. | `:21-27`, `:161` |
| C | The QB first-round cap overflow is dumped wholesale into **round 2**: `projectedRound = 2` (`:211`) → the observed ~20 R2 QBs. All other positions' R1 caps are dead code (never reached). | `:196-215` |
| D | RB (pv 0.65) and FS/SS (pv 0.72) blocks land at rank fraction 0.70–0.85 → base round 6, round 5 in weak years. **No RB or S can ever receive a R1 grade.** NFL reality: the first RB/S has gone by pick ≤47 in every draft 2016–2025. | `:57-74`, `:178-191` |
| E | Grade compression: physicals are retro-fitted to the round (`tieredPhysical`, `:221-224`, `:237-260`) while mental stays ~constant → the entire class spans numeric 61–82 = letters **C…B+**. A-/A/A+ are mathematically unreachable; within-round σ<1 means scout error (±3…±15) dominates → displayed grades are noise. This is the user's "no position skill ever gets an A". | `:221-260`, `CollegeProspect.swift:304-308` |
| F | Tail-trim deletes specialists: `while prospects.count > count { removeLast() }` (`:135-137`) trims the last-generated positions → **28.9 % of classes have zero punters** (P averages 4.2 of 7). | `:135-141` |
| G | Two divergent positional-value tables: `DraftIntel.swift:96-107` vs `ScoutingEngine.swift:57-74` — Steal/Reach indicators disagree with the projections shown on the same screen. | `DraftIntel.swift:93-107` |
| H | Causality is inverted end-to-end: round is decided from placeholder noise + position value, then the body is generated to match the round. Potential (`(41…99 + 41…99)/2`, mean 70, `:289`) is **independent of draft slot** → a R7 pick has the same upside distribution as pick #1, so draft position predicts nothing about careers. | `:221-224`, `:289` |

Supporting facts: rookies enter with `schemeFamiliarity == [:]` (fam 0 → maximum
familiarity penalties for every rookie identically; `DraftEngine.convertToPlayer`
`:171-207` never initializes it — only `LeagueGenerator.swift:148` does). No
intelligence/learning attribute exists anywhere in the domain model. College
production fields exist but are **computed from `truePotential`**
(`CollegeProspect.swift:239-301`) — an information leak (production tier reveals
hidden potential without scouting) — and are shown only in `ProspectDetailView`,
in no list.

## 2. Target model — "talent curve first, positions second, attributes last"

Generation pipeline (new file `Engine/Scouting/DraftClassBuilder.swift`; 
`ScoutingEngine.generateDraftClass` becomes a thin wrapper that calls it, keeping
every existing call site — `WeekAdvancer.swift:1091/:1792/:1984`,
`ScoutingHubView.swift:450`, `DraftDayCoordinator.swift:171`,
`MultiSeasonSmokeTest.swift` — source-compatible):

### Step 1 — class blueprint (positional allocation with guardrails)
1. Draw per-class **positional strength** `s[pos] ~ N(1.0, 0.15)` clamped
   `[0.70, 1.35]` (replaces the discrete strong/weak lists; expose the 2–3
   strongest/weakest as the existing `DraftClassStrength` for UI/news compat).
2. **QB special case** (most volatile position): draw the R1-grade QB count
   directly from the smoothed 10-yr histogram `{1: 8%, 2: 18%, 3: 26%, 4: 22%,
   5: 16%, 6: 10%}`.
3. Allocate **round-band counts per position** = base band shares
   (`DRAFT_NFL_REFERENCE.md` §2–3, encoded in §4 below) × class size × `s[pos]`,
   then **clamp to the observed min/max** (§2 table, R1-range column) and
   renormalize so each band's total matches its pick capacity (R1 band ≈ 26–30
   grades, see §4).
4. **Hard invariants** (assert in debug + harness):
   - best QB/WR/OT/EDGE/CB/DT grade = round 1 (top-40 value) every class;
   - best RB/S/TE/LB/IOL grade ≤ round 2 every class;
   - QB count with grade ≤ R2 never exceeds 8;
   - K ≥ 3 and P ≥ 3 per class, never graded better than round 4 (fixes F);
   - class totals per position within §4 min/max.

### Step 2 — talent backbone
Build the ordered slot list (1…N). True current-ability target for slot r
(class size 350, tune so the **letter thresholds** produce §8 counts):

```
talentTarget(r) = 96.5 − 5.2·ln(r + 1.5) + ε,  ε ~ N(0, 1.2)
```
≈ #1: 91–96 · #10: 83–86 · #28: 78–81 · #100: 72–75 · #224: 66–69 · #350: 60–64.
Apply a small class-quality modifier `q ~ N(0, 0.8)` to the whole curve (some
drafts are simply better). Positions are interleaved through slots (allocation
from step 1 assigns which slots belong to which position — shuffle within bands
so no positional blocks form).

### Step 3 — development archetype & age
Per prospect draw archetype: **Polished** (25 %) / **Balanced** (55 %) /
**Raw** (20 %), position-biased (QB/OL skew polished; WR/DB/EDGE skew raw).
Age 20–23 correlated: raw → 20–21 more likely, polished → 22–23.
Archetype shifts the now-vs-ceiling split (below) and readiness.

### Step 4 — attributes from talent (fixes A, E, H)
- **`trueOverall` must use the Player formula** so drafted players don't morph:
  redefine `CollegeProspect.trueOverall = positionAvg·0.5 + physicalAvg·0.3 + mentalAvg·0.2`
  (same weights as `Player.swift:226-231`).
- Sample **mental profile** from position-specific priors (QB/S/MLB/C higher
  awareness prior), then sample **physical profile** from the per-position
  physical table (§4) scaled toward the talent target, then **solve** the
  required position-skill average: `posAvg = (T − 0.3·physAvg − 0.2·mentalAvg)/0.5`,
  distribute across skills with archetype weights + noise (±8), clamp 25–99,
  rebalance to hit T ± 1.
- **Elite trait rule**: slots 1–12 get 1–3 key skills at 88–97 (A-/A/A+ visible
  grades exist but are scarce); slots 13–40 cap key skills ~84–92; day-2 ~80–88;
  day-3 ~70–84 with a 5 % "freak trait" exception (one 85+ skill on an otherwise
  day-3 profile → sleeper/trait bets).
- Delete `tieredPhysical` (`:237-260`), `bellCurvePhysical` placeholder flow, and
  the post-hoc physical overwrite at `:221-224`.

### Step 5 — potential correlated with slot, overlapping (fixes H)
```
truePotential = clamp(trueOverall + upside, trueOverall, 99)
upside ~ N(µ_band, 5) + archetypeShift (Raw +5, Polished −4) + ageShift (20yo +3, 23yo −2)
µ_band: R1 14 · R2 12 · R3 10 · R4–5 8 · R6–7 7 · UDFA 6   (clamp upside 0…26)
```
→ R1 picks average clearly higher ceilings, but a R7 tail can out-ceiling a R1
floor (steals/busts stay possible). With `developmentCeiling = pot·0.65+35`
(`PlayerDevelopmentEngine.swift:19-21`) this calibrates to §6 of the reference:
share with ceiling ≥ 78 ("starter-capable"): R1 ≈ 90 %, R3 ≈ 55 %, R7 ≈ 25 % —
actual starter rates then land near NFL values because development speed,
coaching and opportunity (phase 2 systems) gate realization.

### Step 6 — intelligence / learning (new attribute)
- **`learning` (0–99)**: how fast the player absorbs playbooks/schemes.
  Generated **correlated with awareness, r ≈ 0.6**:
  `learning = clamp(round(0.6·awareness + 0.4·draw) + archetype/position shift, 25, 99)`
  where `draw` is from the mental prior. This is the user-requested intelligence
  aspect: it correlates with game IQ (awareness) but is not identical to it.
- Storage: `CollegeProspect.trueLearning: Int = 55` and `Player.learning: Int = 55`
  (top-level stored properties, inline defaults, **not** added to any `init`
  signature — set post-construction like `handSize` at `ScoutingEngine.swift:306-308`).
- Wiring now: scheme-learning rate (§5 integration), rookie initial familiarity,
  interview Football IQ = `0.5·awareness + 0.5·learning + noise(quality)`
  (replaces the round-based floor/ceiling at `:1496-1501`), scouted `LRN` grade
  in mental grade grids (`generateMentalGrades` `:709-728` gains the key).
  `awareness` remains the in-sim game-IQ (all 8 PlaySimulator formulas untouched).

### Step 7 — college production (stored, noisy signal — fixes the info leak)
New stored fields on `CollegeProspect` (inline defaults):
`collegeYearsStartedStored: Int = 0`, `collegeCompetitionLevelRaw: String? = nil`
(`P5`/`G5`/`FCS` enum), `collegeProductionScore: Int = 0` (0–99),
`collegeProductionTierStored: String? = nil`, `collegeStatLineStored: String? = nil`.
Generation:
```
yearsStarted = f(age, archetype)             (1–4; polished/older → more)
competitionLevel: 74% P5 / 20% G5 / 6% FCS   (early slots skew P5; FCS early-slot
                                              prospects are rare "small-school riser" stories)
productionScore = clamp(0.55·trueOverall + 0.12·learning + 0.08·yearsStarted·6
                  + compBonus(P5 0 / G5 +3 / FCS +5, easier competition inflates stats)
                  + N(0, 9), 20, 99)
```
Tier from score (Elite ≥ 85 · Above Avg ≥ 74 · Average ≥ 60 · Below Avg < 60);
stat line generated from tier+position+years exactly like the current
`collegeStatLine` math but reading stored values. Existing computed properties
(`CollegeProspect.swift:239-301`) become fallbacks when stored fields are unset
(old in-flight saves). Production is now a **real but imperfect** signal —
workout-warrior (high talent, low production) and production-machine (inverse)
profiles emerge and feed bust/boom narratives.

### Step 8 — NFL readiness (few contribute 100 % on day 1)
`CollegeProspect.nflReadiness: Int = 60` (0–99):
```
readiness = clamp(35 + yearsStarted·9 + (age−20)·4 + learning·0.15
            + polished +8 / raw −8 + positionShift + N(0,6), 25, 95)
positionShift: RB/CB/OT +6 · WR/EDGE/DT/IOL 0 · LB/S/TE −4 · QB/C −8
```
Used in conversion (§3) and rookie familiarity init. UI: show as a scouting
insight line ("Pro-ready" / "Needs seasoning" buckets), no new column needed.

### Step 9 — round projection & scouting (consensus with error)
`projectedRound` = the band from step 1 (slot rank → grade-band mapping), no
more caps/penalty/overflow code (delete `:154-218`, `positionalDraftValue`
`:57-74`, `maxFirstRounders` `:77-83`). Scouting keeps its existing error model
(GradeRange narrowing etc.) — with real variance underneath, scout error now
*refines* instead of *being* the signal. Consolidate the 5 duplicated
`scoutGrade` switches (`:541`, `:788`, `:1777`, `:2483`, `:2647`) into
`LetterGrade.from(numericValue:)`. Replace `DraftIntel.positionalDraftValue`
(`DraftIntel.swift:96-107`) usage: public board rank = order by
`scoutedOverall` + projection (single consensus source, fixes G).

### Step 10 — combine from attributes (per-position realism)
Calibrate to `DRAFT_NFL_REFERENCE.md` §5:
- Extend the per-position mean/σ approach of `fortyTimeFromSpeed` (`:1294-1339`)
  to **all six drills** (bench/vert/broad/cone/shuttle currently use 3 coarse
  groups at `:1158-1240`) with per-position clamps from the reference table.
- Keep attribute correlation (attrBias) but strengthen to r ≈ 0.8; keep the
  10 % warrior / 10 % bad-tester personality modifier; add a **0.5 % freak tail**
  (record-flirting results) for headlines.
- QBs skip bench (already no K/P drills); optional broader skip mechanic only if
  the combine fields are already Optional — do not force a model change for it.
- Position drill grade (`:1083-1149`) stays relative to position group; verify
  the harness target: per position-group per class ≈ 1–3 A/A+ testers, bulk B/C.

## 3. Conversion & rookie integration changes (`DraftEngine.swift`)

1. `convertToPlayer` (`:171-207`): replace pick-number-driven `rookieScaleFactor`
   (`:247-267`) with **readiness-driven** scaling (causality fix — players fall
   in the draft because they're worse, not the reverse):
   ```
   skillFactor    = 0.62 + nflReadiness/99 · 0.28   (≈0.69…0.89)
   physicalFactor = 0.97                            (bodies are NFL-ready)
   mentalFactor   = 0.80 + learning/99 · 0.12
   ```
   floor 35 unchanged. Copy `learning` onto the Player. Expected day-1 OVR ≈
   70–85 % of true ability → nobody contributes at 100 % immediately, and
   pro-ready mid-rounders can out-play raw first-rounders early (real NFL
   pattern).
2. **Initialize rookie scheme familiarity** (fixes the fam-0 bug): after
   conversion, set familiarity for the drafting team's side-matched scheme to
   `10 + readiness·0.20 + learning·0.15` (≈15–45; below the 70 completion pivot
   and mostly below the 55 bust pivot → rookies still err, but differentiated:
   smart+ready rookies ramp from 45, raw ones from 15) plus primary-position
   familiarity 100 (mirror `LeagueGenerator.initializePlayerFamiliarity`
   `:804-836`). Same for UDFAs (`convertUDFAToPlayer` `:219-240`) at −5.
   Weekly growth then uses `learning` (below).
3. `VersatilityDevelopmentEngine.learnScheme` (`:79-111`): replace the
   `awareness/70` term with `learning/65` (learning is now the canonical
   "absorbs the playbook" stat; awareness stays pure game-IQ). Keep coachability
   and coach terms. Balance guard: at learning=55 the multiplier ≈ 0.85 vs the
   old awareness term ≈ 0.9 at awr 63 — net class-average learning speed stays
   within ±10 % of current (harness `familiarity` scenario re-run to confirm no
   drift in the B1/B2 curves' input trajectory).
4. Rookie contracts, AI pick logic, mock draft diversity rules: unchanged (AI
   improves automatically because `truePotential·0.15` and `trueOverall` now
   carry real signal).

## 4. Data tables (implementation constants)

Class position shares (normalize to class size; per-class count clamps in
parens). Game positions mapped from NFL groups (EDGE ≈ DE + pass-rush OLB):

```
QB 5.5% (12–24) · RB 8.7% (22–36) · FB 0.9% (2–5) · WR 14.0% (36–56) · TE 6.0% (14–26)
LT 3.2% · RT 3.2% (OT total 16–30) · LG 2.6% · C 2.6% · RG 2.6% (IOL total 18–30)
DE 7.5% · OLB 5.6% (edge+OLB total 30–48) · DT 7.5% (18–32) · MLB 4.1% (9–20)
CB 13.1% (32–52) · FS 3.6% · SS 3.4% (S total 15–28) · K 0.9% (3–6) · P 0.9% (3–6)
```

R1-grade band shares (of ~28 R1 grades; count clamps): QB special-case
histogram (§2 step 2) · RB 4.5% (0–3) · WR 13% (2–7) · TE 3.5% (0–2) ·
OT 14% (2–7) · IOL 7% (0–4) · DE+OLB 15% (2–7) · DT 9% (1–6) · MLB 2% (0–2) ·
CB 14% (2–7) · FS+SS 4% (0–3) · K/P 0%.

Band structure for 350 with 224 draft picks (7×32): grades R1 ≈ 26–30 ·
R2 ≈ 33 · R3 ≈ 38 · R4 ≈ 43 · R5 ≈ 47 · R6 ≈ 51 · R7 ≈ 55 · UDFA ≈ rest.

Per-position physical priors (mean ± σ; scaled +0.5σ…+1σ for top slots).
**Implementation MUST first read `LeagueGenerator`'s veteran generation and use
one shared table for both** (new `PositionPhysicalProfile` enum) so rookies and
veterans come from the same distributions — if LeagueGenerator is generic today,
migrate it to the shared table in the same commit; existing saves keep their
veterans (drift washes out via roster turnover in ~4–5 seasons):

```
           SPD        ACC        STR        AGI
QB       62±8       68±7       55±8       68±7
RB       82±5       84±5       66±7       82±5
FB       62±6       66±6       76±6       60±6
WR       85±5       86±5       52±7       84±5
TE       70±6       72±6       72±6       66±6
OT       47±6       52±6       84±5       54±6
IOL      45±6       50±6       86±5       52±6
DE/EDGE  73±6       76±6       78±6       72±6
DT       55±7       62±7       87±5       58±7
OLB      76±5       78±5       74±6       74±5
MLB      73±5       75±5       75±6       71±5
CB       86±4       87±4       48±7       85±4
FS/SS    82±5       83±5       58±7       80±5
K/P      50±8       52±8       45±8       55±8
```
Stamina 70±8, durability 72±9 all positions. Combine drill tables: use
`DRAFT_NFL_REFERENCE.md` §5 verbatim (mean/σ/floor/ceiling per position per drill).

Mental priors (mean ± σ): awareness by position (QB/S/MLB/C 62±9, others 56±9),
decisionMaking 56±9, clutch 55±10, workEthic 58±11, coachability 58±10,
leadership 52±11, learning per §2 step 6. Talent scaling: top-40 slots +6 mental
mean (NFL separators are usually mental), UDFA −3.

## 5. Save compatibility & migration

- All new fields: top-level stored properties with inline defaults on the
  `@Model` classes (`Player.learning = 55`, prospect fields §2) — never in
  `init` signatures, enums as `String?` raw + computed accessor. This matches
  the project's established lightweight-migration convention
  (`Player.swift:56-79` pattern). **No changes to the Codable attribute structs**
  (`PlayerAttributes.swift`) — they have no `decodeIfPresent` safety net.
- No new `@Model` types → no schema-list changes needed (`DataContainer.swift:6-36`,
  `MultiSeasonSmokeTest.swift:24-33` both untouched).
- **In-flight save migration**: add `CollegeProspect.generatorVersion: Int = 0`
  (new classes write `2`). In `WeekAdvancer`, when loading/entering a scouting
  phase: if the stored class has `generatorVersion < 2` **and the draft has not
  started** (no picks made this cycle), purge + regenerate the class (and re-run
  combine/pre-scout for the current phase). Scouting progress on the old class
  is lost — acceptable: the old class is the bug. If the draft already happened,
  leave everything alone (players are already in the league). Prospects are
  purged wholesale each season (`WeekAdvancer.swift:3134-3137`) so the migration
  path is short-lived by design.
- `SimPlayer` needs **no** new fields (learning acts through familiarity growth
  and conversion, not per-play).

## 6. UI changes

1. **College production ("PROD") column** in all prospect lists — insertion
   points already mapped (view:line): `ProspectListView` headers `:430-443` +
   `overviewColumns` `:805-824`; compare sheet `:1437-1449`; `BigBoardView`
   `:836-849` + `:1915-1934` + `BigBoardSort` `:2341` + `orderedBoard` `:233-273`;
   `CombineResultsView` `:382-402` + `:431` + `CombineColumn` `:777` + sort
   `:80-118`; `InterviewSelectionView` `:464-482` + `:508`; `WarRoomPanel`
   `:147-186` (micro-label); `LiveBigBoardPanel` `:66-109` (3-char);
   `PickSheetView` `:143` + `:229-248`; `DraftUDFAPanel` `:143-164`;
   `MockDraftView` `:682-701`; `ScoutingHubView.proDayProspectRow` `:1880-1891`.
   Render: 40–44 pt tier chip `ELI/AA/AVG/BA` colored A-scale
   (`PositionGradeCalculator.gradeColorForLetter` colors); tier enum gets a
   localized `displayName` (rawValues are not auto-extracted).
2. **LRN (Learning) grade** added to mental grade surfaces: prospect mental tab
   headers/rows (`ProspectListView` `:464-481`/`:857-883`, `BigBoardView`
   equivalents — widths shrink 32→28 to fit 7 columns), `ProspectDetailView`
   scouting report mental grid, interview report. Roster side:
   `PlayerDetailView` mental sections (`mentalSection` `:1394-1405` +
   `mentalAttributesGrid` `:1775-1787`) gain a Learning row with the standard
   trend component.
3. **Grade legend fix**: `LetterGradeLegend` (`ProspectGradeMenuView.swift:188`)
   and `DraftClassReportView.gradeColor` (`:335`) say B→gold while every list
   renders B→`accentBlue` — align both to `gradeColorForLetter`.
4. Localization: new strings via literal `Text()`/`String(localized:)` per the
   catalog workflow. **English only — the game ships English-only (decided
   2026-07-29); never add `fi` translations.**

## 7. Validation — `draftclass` harness scenario (definition of done)

Extend `tools/balance-harness` (add `ScoutingEngine.swift` + `DraftClassBuilder.swift`
+ a `CollegeProspect` stand-in to the staged sources per the README's stub
pattern; add scenario `draftclass`). Generate **200 classes**, assert:

1. QB R1-grade count ∈ [1,6] in every class; distribution matches the §2
   histogram within ±6 pp; QB grade ≤R2 count ≤ 8.
2. Best-at-position guarantees: QB/WR/OT/EDGE/CB/DT best grade = R1;
   RB/S/TE/LB/IOL best grade ≤ R2; K/P never < R4; K ≥ 3, P ≥ 3.
3. Position class-counts within §4 clamps; R1 band counts within clamps for
   every position; 10-yr means within ±20 % over the 200-class aggregate.
4. Overall-grade spread per class: A-range (A-/A/A+ ≡ 85+) hits 5–14 prospects;
   B-range is the bulk; within-band σ(trueOverall) ≥ 1.5.
5. Elite skills: ≥1 per class per premium position group at 88+; A+ skills ≤3 %
   of all skill grades; day-3 freak-trait rate 3–7 %.
6. `truePotential ≥ trueOverall`; band means monotonically decreasing
   (R1 > R2 > … > UDFA) with distribution overlap (R7 p95 > R1 p05 upside);
   ceiling ≥78 share per band within ±10 pp of §2 step-5 targets.
7. Combine per position: 40-yd mean within ±0.05 s of reference, all drills
   inside clamps, corr(speed, 40 time) ≤ −0.6; 1–3 A/A+ drill grades per
   position group per class.
8. Readiness ∈ [25,95], corr(readiness, yearsStarted) > 0.4, QB mean readiness
   < RB mean readiness.
9. Production: corr(productionScore, trueOverall) ∈ [0.45, 0.75] (real but
   imperfect); all four tiers occur in every class.
10. Re-run harness `familiarity` scenario: B1/B2 curve inputs unchanged (scheme
    learning-rate class average within ±10 % of pre-change).

Also: full app build green (`xcodebuild`/sim), and one in-sim smoke:
`MultiSeasonSmokeTest` 3 seasons — league avg OVR drift stays within the
established |Δ| ≤ 1.5 band (rookie intake quality changed, so verify).

## 8. Explicitly out of scope now (phase 2: development & training deep-dive)

Documented hooks, not implemented in this wave:
- `updatePotentialRealization` (`PlayerDevelopmentEngine.swift:406-436`, dead
  code) — wire into season loop; phase 2 decides morale/schemeFit weights.
- `assessedPotential` writing (`assessPotential` `:538-553`, dead code) — coach's
  potential read UI.
- **Competitiveness / fighter mentality** attribute + adversity-driven
  motivation (bad season → trains harder), mentor/coach interaction — phase 2
  (user's explicit next step). `learning` and archetypes from this wave are its
  inputs.
- Real playing-time share in offseason dev (uses estimate at `:837-848` despite
  tracked `gamesPlayed/StartedThisSeason`).
- `hometownState/City` dead fields; roster-list "Mental" analysis mode; combine
  drill skip mechanic (if fields non-optional); UserDefaults prospect grades
  leaking across careers (`UserProspectGrade.swift:70-71`).

## 9. Implementation order (workflow stages)

1. **Core generator**: `DraftClassBuilder.swift` (+ shared
   `PositionPhysicalProfile`; read & align `LeagueGenerator` first),
   `CollegeProspect` fields, `trueOverall` fix, grade consolidation, K/P fix,
   `DraftIntel` unification, combine calibration. Build green.
2. **Conversion & learning**: `Player.learning`, readiness conversion, rookie
   familiarity init, `learnScheme` learning-term, interview IQ binding. Build green.
3. **UI**: PROD column ×11, LRN surfaces, legend fix, localization (English only). Build green.
4. **Harness + calibration**: `draftclass` scenario, run 200 classes, iterate
   constants until §7 asserts pass; re-run `familiarity`; MultiSeasonSmokeTest 3 seasons.
5. **Verify** (parallel reviews): design-compliance & correctness · save-compat &
   regression · sim-balance & UI. Fix confirmed findings, final build + harness.
