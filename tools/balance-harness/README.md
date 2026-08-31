# Balance Measurement Harness

A standalone Monte-Carlo measurement rig for the Dynasty play-by-play engine. It
compiles the **shipped** simulation math (`PlaySimulator` + the adaptive-AI
Layer-A/B model) outside the iOS app and runs large-sample scenarios to check
that the balance bands still hold after an engine change.

This is **repo tooling** — it does not build the iOS app and it never touches
`dynasty/dynasty/**`. It reads those sources, copies/slices what it needs into a
throwaway `build/` tree, and compiles that with `swiftc -O`.

---

## Why this exists — the stale-default incident

Earlier iterations of this harness lived in `/tmp` and **hand-copied** the
`AdaptiveOpponentAI` tuning constants into a shim file behind a `// VERBATIM`
comment. In balance **rounds 2 and 3**, those copies had silently **drifted**
from the repo literals: the play-action key levers were left at stale defaults

| lever | stale shim | shipped repo |
|-------|-----------:|-------------:|
| `paKeyCompletion(_ i)` | `i * 0.18` | `i * 0.035` |
| `paKeyBigPlay(_ i)`    | `i * 8.0`  | `i * 2.0`   |

The stale values applied a ~5x completion boost and ~4x air-yards on keyed
play-action, inflating measured keyed PA-deep to ~40+ net YPA vs the real ~11 —
and every "verified" number built on that shim was wrong. The `// VERBATIM`
comment made it *look* trustworthy.

**This harness makes that class of bug impossible by construction.** No engine
constant is ever hand-typed here. On every build, `sync_sources.sh`:

- copies the engine sources **verbatim** from the repo — `AdaptiveOpponentAI.swift`
  among them, since the `coachedgame` wave removed the last reason to slice it —
  and asserts each copy's SHA-256 equals the repo file's, and
- **regenerates** every remaining extract by mechanically slicing it out of the
  real file, then **fails the build** if a single tuning line differs from the
  repo, or if the repo has stopped defining a lever the rig reports on.

If a repo constant changes, the harness picks it up on the next `./run.sh`. If
the slice ever mangled a constant, the build refuses to proceed.

---

## Layout

```
tools/balance-harness/
  README.md              this file
  sync_sources.sh        stage engine sources into build/src (verbatim + slice)
  run.sh                 sync + swiftc -O + run selected scenario(s)
  driver/
    main.swift           the scenario library + CLI dispatcher (harness-owned)
    SimPlayer.harness.swift
                         SimPlayer scaffolding (memberwise init + stubs) with two
                         splice markers filled from the repo on each sync
    GameModels.harness.swift
                         SwiftData-model stubs (Player/Team/Coach/CoachRole +
                         SimPlayer.init(from:)) so the shipped full-game pipeline
                         (GameSimulator/DriveSimulator) compiles standalone
    *Scenario.harness.swift
                         one file per parameterized scenario — DraftClass,
                         Career, LeagueGen, Perception, CoachedGame. Measurement
                         and assertions only; each is copied verbatim into
                         build/src and guarded math-free by sync_sources.sh
  build/                 GENERATED, git-ignored — reproduced by sync_sources.sh
    src/                 staged engine sources + MANIFEST.txt
    harness              compiled binary
```

`build/` is `.gitignore`d — nothing generated is committed. Only the authored
files (`sync_sources.sh`, `run.sh`, `driver/main.swift`, the two `.harness.swift`
scaffolding templates and the per-scenario `*Scenario.harness.swift` files) plus
this README live in git.

---

## How the source staging works

`sync_sources.sh` produces `build/src/` in three ways:

### 1. Verbatim copies (36 files, SHA-verified)

**Play-by-play (11):** `PlayCall.swift`, `PlayType.swift`, `Position.swift`,
`Scheme.swift`, `GameWeather.swift`, `PersonalityArchetype.swift`,
`PlayResult.swift`, `PlayerAttributes.swift`, `GamePlan.swift`,
`PlaySimulator.swift`, `HeatState.swift`.

**Full-game pipeline (6, round 5):** `DriveResult.swift`, `BoxScore.swift`,
`PlayerGameStats.swift`, `CoachingModifiers.swift`, `DriveSimulator.swift`,
`GameSimulator.swift` — the SHIPPED complete-game engine, so the `fullgame` /
`positionsweep` scenarios run the exact box-score pipeline the app ships (no
reimplemented game loop, momentum, clock, heat feed, or box score).

**Draft-class generator (7, stage 4):** `Motivation.swift`,
`PlayerPersonality.swift`, `LetterGrade.swift`, `PositionPhysicalProfile.swift`,
`MentalAttributeModel.swift`, `RandomNameGenerator.swift`,
`DraftClassBuilder.swift`.

**Development stack (7, stage 5):** `InjuryType.swift`, `CampEnums.swift`,
`MotivationState.swift`, `InjuryRecord.swift`, `PlayerDevelopmentEngine.swift`,
`PlayerRetirementEngine.swift`, `SeasonPhase.swift` — the last one is the camp
calendar the `lockerroom` scenario drives the shipped camp scheduler with
(`WeekAdvancer.campIntensity(for:)` takes a `SeasonPhase` and nothing else).

Plus `Playbook.swift`, `HCPersona.swift`, `RosterValue.swift`,
`AIDraftPerception.swift` and `GMTaste.swift` alongside their own scenarios.

All 36 are copied byte-for-byte. The script asserts `sha(copy) == sha(repo)` for
each and records both in `MANIFEST.txt`; a mismatch aborts the build.

### 2. `AdaptiveOpponentAI.swift` — verbatim (it used to be a slice)

This file used to be staged as `AdaptiveOpponentAIExtract.swift`: an `awk` pass
that copied the repo file line-for-line and **skipped only** its four
**persona-hint** functions (`defenseKeyHint`, `exactCallHint`,
`categoryKeyHint`, `offenseAdjustHint`), because they reference `DCPersona` /
`OCPersona` from `CoordinatorPersona.swift` — a file the harness did not
compile.

The `coachedgame` scenario compiles it. `LiveGameEngine` holds one persona of
each kind and calls all four hint functions, so `CoordinatorPersona.swift` is
now a verbatim source (§1) and the strip has nothing left to justify it. The
whole file arrives as repo bytes, sha-verified like every other verbatim copy.
**One less transform is one less thing that can mangle a constant.**

Two guards survive the change, aimed at the failure mode a sha check cannot
catch — the repo *renaming* a lever the rig reports on:

- the tuning-line count (`static let …`, plus the `paKeyCompletion` /
  `paKeyBigPlay` / `runKeyYardBite` / `runKeyStuffBonus` / `catPivot` /
  `catAlpha` signatures) must stay at or above 20; and
- each of the four `paKey*`/`runKey*` levers the harness header prints, and each
  of the four persona-hint functions `LiveGameEngine` calls, must still be
  declared. Either one going missing aborts the sync.

### 3. `SimPlayer.swift` — template + verbatim repo splices

The shipped `SimPlayer` builds from a SwiftData `@Model Player` via
`init(from:)`, which the harness cannot compile. `driver/SimPlayer.harness.swift`
supplies the harness-owned pieces (a plain **memberwise init** replacing
`init(from:)`, plus stubs for `CoachingEngine` / `VersatilityDevelopmentEngine`
/ the display helpers that the all-70 no-scheme roster never actually calls).
Its two splice markers are filled on each sync with regions sliced **verbatim**
from the repo `SimPlayer.swift`:

- the **storage decls** (`let id: UUID` … `var fatigue: Int`), and
- the **computed-property block** (`schemeFam` + `composureRating` /
  `isFormSensitive` / `isEgoProne` / `mentalTemperament` + `enum
  MentalTemperament`).

So the sim-read fields and the mental-game computeds are drift-proof too. If the
repo adds a stored property, the splice re-emits it and the memberwise init
fails to compile until updated — a loud, fail-closed signal, never silent drift.

### 4. `GameModels.swift` — harness-owned SwiftData-model stubs

The shipped `GameSimulator` is written against three SwiftData `@Model` types —
`Player`, `Team`, `Coach` — that cannot compile outside the iOS app. **None of
the three carries any balance math**; they are pure data holders. So
`driver/GameModels.harness.swift` supplies plain shells (a reference-type
`Player` — required because `finalizeGameResult` writes fatigue back through a
`let` dictionary — plus `Team`, `Coach`, a minimal `CoachRole`, and a
`SimPlayer.init(from: Player)` overload). It is copied verbatim into
`build/src/GameModels.swift`; the sync asserts the `Player` stub and
`init(from:)` survive, and **fails the build if the stub ever contains a
`static let` numeric constant** — no engine number may live in the scaffolding.
Every tuning literal still flows from the sha-verified verbatim sources above.

### 5. `ScoutingEngineExtract.swift` — mechanical KEEP-LIST slice

The shipped `ScoutingEngine` is 3 000 lines wired to `Scout` / `ScoutingReport` /
`Coach` / `Player` / `GradeRange`. The `draftclass` scenario needs four things
out of it: the college list, the anthropometrics table, the **whole combine
path** (per-position drill table + `drillResult` + the personality modifier +
the relative drill grading) and the risk-profile roll — none of which reference
anything outside the verbatim sources. So an `awk` **keep-list** pass copies
exactly those members (brace/bracket-balanced from each named declaration) and
re-wraps them in `enum ScoutingEngine { … }`.

Two guards make it drift-proof: **every non-blank line of the slice must appear
byte-identically in the repo file** (so nothing can be retyped or mangled), and
the 78 per-position drill constants (`forty: timed(4.83, 0.12, …)` …) must
`diff` clean against the repo. A mismatch aborts the build.

### 6. Development-stack extracts (stage 5 — the `career` scenario)

The realization model itself is copied **verbatim**: `PlayerDevelopmentEngine`,
`PlayerRetirementEngine`, `MotivationState`, `InjuryRecord`, `CampEnums`,
`InjuryType`, `RosterValue`. The motivation state machine, the R factor, the
catch-up table, the position-shaped regression, potential drift, the retirement
curve and the cutdown-day sort key are therefore the shipped bytes, sha-verified
like everything else above.

Seven more files are reached into by that stack but cannot compile standalone, so
each is reduced by the same mechanical **KEEP-LIST slice** the `ScoutingEngine`
extract uses, then guarded twice — every non-blank line of the slice must appear
byte-identically in the repo file, and the named single-line tuning constants are
grepped straight out of the repo rather than transcribed:

| extract | what is sliced | wrapped as |
|---|---|---|
| `CoachingEngineExtract.swift` | `hierarchicalDevelopmentBonus` (the 4-layer ±8/±4/±10/±15 % stack), `positionRoleMatch`, the continuity constants | `extension CoachingEngine` |
| `VersatilityExtract.swift` | `learnScheme`, `decayUnusedSchemes`, the install/decay constants | `extension VersatilityDevelopmentEngine` |
| `ContractEngineExtract.swift` | `estimateMarketValue` + its two position helpers — the only thing the post-payday complacency trigger reads | `enum ContractEngine` |
| `TrainingFocusExtract.swift` | `TrainingFocusArea` (top level, verbatim) + `applyWeeklyFocusTick` / `weeklyGainChance` / `autoAssignFocus` / `potentialCeiling` / `applyFocusPoint` / `bump` | `enum TrainingFocusEngine` |
| `DraftEngineExtract.swift` | `rookieScaleFactors` + `scaleAttribute`/`scalePhysical`/`scaleMental`/`scalePositionAttributes` + `initializeRookieFamiliarity` + `roundForPick` + `topTeamNeeds` | `enum DraftEngine` |
| `PracticeSquadExtract.swift` | `isSquadEligible` + `needsVeteranSlot` + `squadSigningScore` + `FillSummary` (the engine's own diagnostic line), plus the ten squad constants by grep | `enum PracticeSquadEngine` |
| `CampRosterConstantsExtract.swift` | `campRosterTarget` / `campContractYears` by grep, plus `TradeValueEngine.offseasonRosterCeiling` — the ladder the camp diagnostic measures against | `enum CampRosterEngine` + `extension TradeValueEngine` |
| `LockerRoomExtract.swift` | `LockerRoomState` + `calculateChemistry` / `chemistryScore` / `chemistryRating` / `chemistryLabel` + `weeklyMoraleUpdate` + the four morale-damping constants by grep | `struct` at file scope + `enum LockerRoomEngine` |
| `WorkloadEngineExtract.swift` | the band table (`underloadedMax` / `healthyMax` / `overloadedMax` / `burnoutFloor` / `absoluteCap`) by grep + `applyDailyLoad` / `classify` / `tickWeek` / `resetCampLoad` / `injuryRiskPct` | `enum WorkloadEngine` |
| `CampScheduleExtract.swift` | `campIntensity(for:)` + `computeRecoveryRate(coaches:)` — the camp scheduler's two inputs, out of the 8 900-line `WeekAdvancer` | `enum WeekAdvancer` |

The last three rows belong to the `lockerroom` scenario rather than to `career`;
they are listed here because they are staged by the same keep-list machinery.
See "Locker room + camp workload" below for why those two engines had to stop
being measured by a hand-written mirror.

`GameModels.swift` also gains one repo splice: the stub `Player` needs the
SHIPPED `Player.overall` blend, because the career scenario develops attributes
and must read the rating the app would. Rather than retype the 0.5/0.3/0.2
weights, the repo's own computed property is spliced verbatim into a
`ShippedOverall` carrier and `Player.overall` falls through to it whenever the
round-5 tier generator has not pinned an explicit grade.

### 7. `CollegeProspect.swift` — template + repo math splice

The shipped `CollegeProspect` is a SwiftData `@Model` pulling in SwiftUI and the
whole scouting graph. `driver/CollegeProspect.harness.swift` supplies the storage
(plain `var`s with the same names and init labels) and splices the **math block**
verbatim from the repo: the production/competition/archetype enums,
`collegeYearsStarted`, `productionTier(forScore:)`, `statLine(…)`, the task-#181
usage-suppression math (`CollegeSampleStatus`, `hasLimitedCollegeSample`,
`productionSeed` / `productionJitter` / `productionSpread`) and — the one the
scenario actually measures — `trueOverall` / `overallValue(…)`. Same
fail-closed contract as `SimPlayer.swift`: if the repo anchors move, the sync
dies instead of measuring a stale formula.

`draftclass` §7.9 band history: `corr(production, trueOverall)` was
`[0.45, 0.75]` while production had one cause, and moved to `[0.30, 0.65]` in
task #181 when ~4.5 % of every class gained a second one (usage suppression).
The old band survives unchanged as **7.9g**, measured over the played-a-season
cohort, so the widened whole-class band cannot hide a regression in the ordinary
production model. Derivation is printed in the scenario's DEVIATION NOTES.

`MANIFEST.txt` records the role (`VERBATIM` / `EXTRACT` / `ASSEMBLED` /
`HARNESS`), the staged file's SHA, and the repo source SHA for every file.

---

## Running

```bash
./run.sh <scenario> [scenario ...]     # sync + build + run
./run.sh all                           # every per-play scenario
./run.sh --no-sync depth               # reuse build/src, skip re-sync
BH_N=60000 ./run.sh regression         # override per-cell sample size

# Round-5 parameterized scenarios (flag args passed straight through):
./run.sh fullgame --home-tier elite --away-tier weak --n 200 --seedable
./run.sh positionsweep --group CB --n 100

# Locker room + camp workload (defaults shown):
./run.sh lockerroom --clubs 400 --travel-clubs 40

# COACHED sim-to-final scoring (defaults shown; ~18 s at n=200):
./run.sh coachedgame --n 200
```

`run.sh` re-syncs (unless `--no-sync`), rebuilds only when a source is newer
than the binary, and passes the scenario list to the harness. Sample sizes are
`BH_N` (default 40000, per cell) and `BH_GN` (default 24000, per grid cell) —
the defaults reproduce the round-3 verifier numbers.

The engine uses Swift's global RNG (unseeded), so numbers carry Monte-Carlo
noise of ±~0.1 ypc / ±~0.5 pt comp% at the default sample sizes; bands are set
with margin for that.

### Scenarios

| scenario | what it measures | key band(s) |
|----------|------------------|-------------|
| `percall` | per-call neutral run ypc vs the play-mix **and** vs a nil package (quick-sim parity) | inside blend **4.0–4.6** ypc, stuff **16–19 %** |
| `depth` | short/mid/deep completion curve + per-depth sack/INT/net, weighted 45/40/15 | short comp **60–66**, monotone; sack **≤ 8.7 %**, INT **2.0–2.6 %**, net-YPA **6.0–7.5** |
| `keyed-pa` | keyed play-action-deep net YPA @70/70, 95/95, 55/55 vs neutral | keyed PA-deep @70 **9–12** (repo paKey 0.035/2.0) |
| `regression` | CATEGORY 1 — the full band guard (1a run, 1b depth, 1c sack, 1d INT, 1e net-YPA, 1f spam-collapse, 1g deep tier matrix, 1h keyed PA) | all of the above |
| `pass-talent` | CATEGORY 2 — QB×WR completion grids (short/mid), covering-CB axis, TE/RB target paths | grids monotone both axes; CB scrub>shutdown; TE/RB Δcomp > 0 |
| `run-talent` | CATEGORY 3 — RB×OL four cells + OL/front axes | ordering **eliteRB+badOL < badRB+eliteOL < elite+elite**; OL↑ / front↓ monotone |
| `familiarity` | CATEGORY 4 — offense/defense scheme-familiarity sweeps + drive TD% | comp/ypc rise with off-fam; def busts fall with def-fam; TD% gap 100-vs-33 |
| `stacking` | CATEGORY 5 — worst-case grand-cap floors (run/deep/short) | adaptive-only (neutral fam) run floor **≥ ~1.8** (`runGrandBiteCap` 1.80); with a **fam20 scheme bust** stacked on top 5a lands ~1.4 (intended worst-of-worst); deep/short stay functional (~8 % / ~27 % comp) |
| `spam` | degenerate spam-collapse + mixed-parity (memory ON vs OFF) | repeated call decays to ~45 % of r1; varied script `|Δ| ≤ 0.3` (balanced-control) |
| `fullgame` | **round 5** — complete games via the shipped GameSimulator/DriveSimulator; per-game box + N-game aggregates + win split | per-team-per-game NFL bands (see below) + equal-tier ~50/50, elite-vs-weak decisive-not-deterministic |
| `positionsweep` | **round 5** — one position group swept {55,70,85,95} on an avg roster vs an avg opponent | monotone win% + headline stat vs the swept group |
| `draftclass` | **draft-class overhaul** — N classes through the shipped `DraftClassBuilder` + combine; full distribution report + the 31 plan-§7 invariants as hard asserts | every §7.1–§7.10 invariant; **exits 1** on any violation |
| `career` | **development overhaul** — 20 independent 32-team leagues run end-to-end through the shipped development stack; hit rates by round, elite shares, trajectory mix, aging curves, R and motivation distributions, career lengths, **and the §8 league quality pyramid** | every `PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §6 item + `DEVELOPMENT_NFL_REFERENCE.md` §8 (6.9a-g); **exits 1** on any violation |
| `leaguegen` | **P1 quality-pyramid wave** — the RANDOM league's t=0 intake: 400 × 53-man rosters straight out of `LeagueGenerator`'s rating path, reported as the §8 quality pyramid, plus a **pin against the Python mirror** in `tools/league-data/make_templates.py` | §8 bands on the intake distribution, depth-tier ordering, the rating floor, `veteranPotential` headroom ≤ 4, and Swift-vs-mirror agreement; **exits 1** on any violation |
| `lockerroom` | **the two engines this harness did not cover** — locker-room chemistry across generated clubs (mean/sd, clamp shares, travel by archetype mix) and the shipped 21-day camp cycle's workload band split at preseason exit, with the strength-coach axis | chemistry mean **52–64**, sd **1.5–6.0**, pinned-at-100 **0–2 %**, travel **≥ 35**; camp `.overloaded`+`.burnedOut` **2–40 %**, mean injury multiplier **1.02–1.35**; 5 hard gates, **exits 1** on any violation |
| `perception` | **AI draft fog (Track C)** — 32 personas draft N boards twice off the same rosters, once through `AIDraftPerception` and once on the true board (`--perceptionEnabled false`), through the shipped `DraftEngine.aiMakePick` | DIAGNOSTIC ONLY, always exits 0: R1 reaches / steals / true-BPA slide and mean \|perceived − true\| by GM persona |
| `coachedgame` | **the path the user actually plays** — `LiveGameEngine.simToEnd()` over 4 matchups × 4 prep-boost steps, against `GameSimulator.simulate` on identical roster specs; per-team scoring distribution with the tail (p90/p99/max), headline-scoreline shares, a possession-vs-conversion attribution of the coached/quick delta, and the `simToEnd` safety-cap headroom | 7 hard gates, **exits 1** on any violation — see "Coached sim-to-final" below |

The last eight are **parameterized** — they take `--flag value` args instead of a
scenario-name list (see "Round-5 full-game campaign" and "Draft-class validation"
below), so they are invoked on their own, not via `all`.

---

## Engine bands that must hold (as of e1b0845)

- inside run blend **4.0–4.6** ypc, stuff **16–19 %**
- depth curve monotone, short comp **60–66**
- sack **≤ 8.7 %** weighted (45/40/15)
- INT **2.0–2.6 %**
- net YPA **6.0–7.5**
- keyed PA-deep **9–12** net YPA @70/70
- run talent ordering: `eliteRB+badOL < badRB+eliteOL < elite+elite` on inside runs
- adaptive-only worst-case keyed+spam run floor `≥ ~1.8` ypc (the `runGrandBiteCap`;
  a fam-bust may stack further on top)

---

## Proof run (default N=40000, GN=24000, HEAD e1b0845)

Reproduces the round-3 independent verifier's headline numbers:

```
./run.sh percall depth keyed-pa

DEPTH CURVE comp%  short=62.8  mid=56.4  deep=38.6  monotone=YES     (verifier 62.0/55.7/38.8)
KEYED PA-DEEP @70 netYPA=11.13 (neutral 8.58, +2.55)                 (verifier 11.05–11.19)
percall insideRun vs-mix ypc=4.16  quick-sim(nil) ypc=4.02          (verifier probe 4.11/4.04)
        NFL-blend (inside-heavy)  vs-mix=4.09                        (band 4.0–4.6)
```

> Note: the round-3 `probe_results.txt` snapshot shows *outside* runs at
> ~2.8–3.0 ypc; the harness now measures ~4.0. That is not a harness fault — the
> engine's edge-run resolution was rebalanced (an "A2-run-edge" fix that restores
> the RB-speed contribution to perimeter runs) **after** that snapshot was
> captured. Recompiling the original round-3 `probe.swift` against the current
> `PlaySimulator.swift` yields the same ~4.0. The harness always measures whatever
> is in the working tree at sync time — that is the point: it never carries a
> stale copy of the engine.

---

## Round-5 full-game campaign (`fullgame` / `positionsweep`)

Round 5 runs **complete games** through the shipped
`GameSimulator → DriveSimulator → PlaySimulator` pipeline (all sha-verified
verbatim) against generated tier rosters, and reads the engine's **own**
`BoxScore` — so every points / pass-yds / rush-yds / sacks / 3rd-down number is
what the app itself would report, not a harness re-derivation.

### Tier roster generator

Full two-way 25-man squads (QB, 2 RB, 3 WR, TE, 5 OL, 4 DL, 3 LB, 2 CB, 2 S, K, P).
Each player's attributes are drawn uniformly within the tier band and pinned
across his cluster:

| tier | band |
|------|------|
| `elite` | 88–95 |
| `good`  | 80–87 |
| `avg`   | 70–79 |
| `weak`  | 55–69 |

A tier grade means "that grade **for his position**". Skills and speed carry the
grade literally; **acceleration and strength** are placed at the position's
`PositionPhysicalProfile` prior offset by `grade − 70` (`phys(_:_:str:acc:agi:)`
in `driver/main.swift`). That is required, not cosmetic: PlaySimulator's R39
attribute-gap terms read those two through `relativeAcceleration` /
`relativeStrength`, which measure a player against his own position prior — a
flat `acceleration = grade` on both sides of the line would read as an 18-point
OL advantage and drag the sack rate ~2 pp off. With the offset, `relativeX`
returns exactly the grade, so every band below is measured on the same footing
as the shipped, position-shaped rosters.

A bare number (`--home-tier 70`) means that exact grade. **Unit-level overrides**
put a different tier on one position group: `--home-override QB=elite,OL=weak,CB=95x2`
(comma-separated, no spaces; `xN` limits it to the first N of the group).
**Asym presets** expand to overrides: `--home-asym elite-O/weak-D` sets the
offense units (QB/RB/WR/TE/OL) elite and the defense units (DL/LB/CB/S) weak.
**Archetype mixes** `--archetypes sensitive|immune|mixed` set every skill player's
form personality. **Familiarity** `--fam 33|66|100` attaches neutral (grade-70,
zero-edge) scheme-carrying coaches and sets every player's scheme learning, so
the directFamiliarity / scheme-fit terms fire in full games. **Offense style**
`--offense-style run-heavy|balanced|pass-heavy` threads a `GamePlan.runPassRatio`
(0.25 / 0.5 / 0.75) into the drive, exercising the Layer-A run-key / PlayMemory
read across a whole game. Every knob has a per-side form (`--home-*` / `--away-*`)
and a both-sides default.

### CLI reference

```
harness fullgame  --home-tier <tier> --away-tier <tier> --n <games>
                  [--home-override U=tier[,U=tier...]] [--away-override ...]
                  [--home-asym elite-O/weak-D]         [--away-asym ...]
                  [--archetypes sensitive|immune|mixed] [--home-archetypes ...]
                  [--fam 33|66|100]                     [--home-fam ...]
                  [--offense-style run-heavy|balanced|pass-heavy] [--home-offense-style ...]
                  [--seedable] [--seed N] [--detail]

harness positionsweep --group QB|RB|WR|TE|OL|DL|LB|CB|S --n <games> [--seedable]

harness career    [--teams 32] [--burnin 8] [--classes 10] [--window 12]
                  [--leagues 20] [--size 420] [--fog 11.5] [--fog-slope 0]
                  [--board 0.30] [--verbose]

harness leaguegen [--leagues 400]

harness perception [--drafts 12] [--size 350] [--seed N]
```

**`leaguegen` exists to keep two independent implementations of one calibration
honest.** The random `LeagueGenerator` and the fixed-2026 template league must sit
at the same level and shape (`LeagueGenerator.targetQualityPyramid`), and the
template achieves that by being rank-mapped onto a **Python mirror** of the Swift
rating math (`make_templates.py`'s `reference_overall`). A mirror that drifts from
the Swift therefore breaks BOTH league sources at once, and nothing else in the
repo can see it. This scenario measures the Swift side — the rating path is
awk-sliced verbatim into `LeagueGeneratorExtract.swift`, and `Player.overall` comes
from the repo splice — and fails if the two disagree by more than Monte-Carlo
slack. It earned its keep on its first run by catching a depth-chart bug worth
+0.79 OVR of league mean.

`fullgame` prints a per-game box line when `--n ≤ 8` (or with `--detail`), then a
pooled per-team-per-game aggregate with an `[OK]/[OUT]` marker against each NFL
band, the home/away/tie win split + margin, and the games/sec. `positionsweep`
runs N games per `{55,70,85,95}` point and prints win% + home/away points + the
swept group's headline stat.

**`--seedable`** seeds a SplitMix64 used for **roster** draws only, so the rosters
are reproducible run-to-run. The engine's play-by-play uses Swift's global
(unseedable) RNG, so games still carry Monte-Carlo noise — which is exactly why
campaigns run N games and report bands. `--seed N` picks the roster seed.

### Throughput

~**600 games/sec** on an M-series laptop (`swiftc -O`, rosters rebuilt per game,
no per-play allocation in the driver). A **200-game campaign finishes in ~0.3 s**;
even a 4-point positionsweep at N=200 (800 games) is ~1.3 s.

### NFL reference bands (per team per game) and what round 5 found

Bands: points **17–27** · total yds **300–400** · pass yds **200–250** · rush yds
**100–130** · plays **58–68** · sacks-taken **2–3** · INT thrown **0.7–1.3** ·
completion **60–67 %** · ypc **3.9–4.6** · net YPA **5.9–7.5** · 3rd-down **35–45 %**.

Smoke campaigns surfaced two headline results (the harness is faithful — these
are engine properties, reported, **not** fixed here; fixes are out of this
tool's file scope):

1. **Full-game passing/scoring runs hot.** At the engine's own calibration point
   (`--home-tier 70 --away-tier 70`, attribute-identical to the all-70 rosters the
   per-play bands are calibrated on), full games land **plays 66.9 [OK]**,
   **completion 66 % [OK]**, **sacks 2.5 [OK]** — but **net YPA 8.4**, **pass yds
   330**, **3rd-down 50 %**, **points 29** all **[OUT]** high. Since the players
   are identical to the calibrated per-play rosters, the gap is **pure
   play-selection**: the situational full-game AI produces higher passing
   efficiency than the flat 45/40/15 per-play blend, compounding into ~29 pts/team.
2. **The talent curve is too steep at the extremes.** Uniform-tier
   `elite (88–95)` vs `weak (55–69)` is **deterministic** — home **100 %**, mean
   score **~103–4** — well past the "biggest NFL favorites ~85–90 %, never
   deterministic" guardrail. (Caveat: uniform tiers are an extreme construction;
   a realistic star/role-player mix via `--home-override` narrows it. `weak`-vs-
   `weak` lands **26.5 pts [OK]**, `avg`-vs-`avg` 31, `elite`-vs-`elite` 39 — the
   response is monotone but scales faster than NFL.)

## Development validation (`career`)

```bash
./run.sh career                                   # the calibrated default
./run.sh career --leagues 4 --classes 4 --verbose # quick iteration
./run.sh career --fog 8                           # sweep the scouting-error knob
```

### What it runs

A synthetic league, exactly as `PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §6 specifies:
**depth-chart rank by OVR inside the position cohort → playing-time share, no
game sim.** Per season, per club: retirement roll → contract tick → draft off a
scouted board → cut to the 53-man template → coordinator churn → training camp
(`processOffseason`) → 17 weeks of availability, game experience, injuries and
weekly training-focus ticks → standings from starter strength.

Intake is the shipped generator (`DraftClassBuilder` + the combine and
declaration passes) converted through the shipped `DraftEngine` rookie scaling.
Development, regression, motivation, plateau/late-bloomer, potential drift and
retirement are the shipped engines. The scenario itself contains **no
development constant** — it drives the engine and measures it.

Defaults: 20 independent leagues × (8 burn-in + 10 measured classes + 12-season
career window) = 30 seasons each, 7 680 drafted careers per round bucket plus
~47 000 undrafted camp bodies. ~12 s.

### The asserts (plan §6)

`6.1` hit rate by round within ±8 pp of `DRAFT_NFL_REFERENCE.md` §6 ·
`6.2` elite (peak OVR ≥ 90) shares R1 20-30 % / R2 8-15 % / R3-7 ≤ 4 % ·
`6.3` plateau 30-50 %, late bloomer 5-12 %, R5-7 washout ≥ 45 % ·
`6.4` modal peak age inside every position's `peakAgeRange` and the decline
ordering RB/CB < standard < QB/OL · `6.5` R mean 0.45-0.55, p10 ≤ 0.30,
p90 ≥ 0.85 and the four-state motivation mix · `6.6` career length ·
`6.7` growth shape · `6.8` split-half stability.

### The offseason development ledger (task #97 / F-71, diagnostic — no gate)

Printed as `OFFSEASON DEVELOPMENT LEDGER`, one row per season, in the exact
units `DevelopmentSourceDiag.report` prints on the shipped smoke's
`SMOKE: diag devsource … offseasonDevelop=` term: the sum of every man's
UNROUNDED `Player.overall` after `PlayerDevelopmentEngine.processOffseason`
minus before, over the men the pass was handed. `crExactOverall` is
`Player.overall` without its final `.rounded()`, kept byte-identical to the
shipped diag so both sides are read off one ruler.

**Read it at a matched `leaguePot`, never on the raw rate.** The pass converts
headroom, so its rate is a function of the ceiling left in the population; the
row therefore carries `meanOVR`, `leaguePot` and `headroom` for the pre-camp
population alongside the gain. This rig's equilibrium sits near 12.7 points of
headroom, while a freshly generated app league opens at ~2 and takes several
seasons to climb — comparing those two rates without the headroom column
compares different questions.

Why it exists: two in-tree notes (TODO `#97`, `docs/AI_FIX_QUEUE.md` F-71) read
the smoke's `offseasonDevelop` figure as evidence that the shipped pipeline
over-develops relative to this rig, and there was no rig-side number to check
that against. There is now.

### The practice-squad / camp block (task #157, diagnostic — no gate)

Printed after `SALARY BY POSITION`. At every measured cutdown the scenario
assembles the practice squad the **shipped rules** would build out of the men it
is about to write off — `PracticeSquadEngine.isSquadEligible`,
`needsVeteranSlot`, `squadSigningScore`, `RosterValue.keepScore` and
`DraftEngine.topTeamNeeds`, all sliced by `sync_sources.sh`; only the
round-robin loop is scaffolding, because `fillSquads` is wired to `Career` /
`ModelContext` / `InboxEngine`.

It is a **shadow**: no player is mutated, so all 36 asserts read exactly the
league they read before the block existed. That is deliberate — a real squad
path would keep men in the league who currently wash out, which moves career
length, the age pyramid and the §8 shares, i.e. it is a balance change and needs
these numbers *first*.

What it answers: how deep squads run and **why** they stop (pool exhausted vs
calibre gate vs veteran slots vs position caps), the OVR/keepScore distribution
of who gets signed against `startingCalibreOverall`, who ages out of the
`accruedSeasonsLimit` window and at what `yearsPro`, a sweep of both gates
(calibre 70/72/75, accrued limit 2/3/4) so a lever can be argued from a number,
and where the rig's camp roster sits on the shipped ladder
(`CampRosterEngine.campRosterTarget`, `TradeValueEngine.offseasonRosterCeiling`,
rungs 75/65/53) — the camp path had **zero** rig exposure before this block.

The last line is a mirror check: the rig assembles its ranking from
`keepScore` + the two shipped bonus constants for speed, then compares it with
`PracticeSquadEngine.squadSigningScore` on every man it signs and prints the
largest disagreement. It is 0.000000 or the slice has drifted.

### The one fitted parameter

`crScoutErrorRange` (`--fog`) is the width of the draft-day evaluation error.
How wrong front offices are about a prospect's eventual level is not directly
observable; the observable is the outcome it produces, which is exactly
`DRAFT_NFL_REFERENCE.md` §6. The harness cannot stage the app's whole evaluation
apparatus (scouts, multiple reports, interviews, `DraftIntel`, the AI need
model), so that width is calibrated here — which makes assert 6.1 a check that
the DEVELOPMENT system can reproduce the reference curve at all, not an
independent test of the draft. Asserts 6.2-6.8 and the league quality pyramid
printed at the end are independent of it.


---

## Locker room + camp workload (`lockerroom`)

### Why this scenario exists

Two engines that **move simulated outcomes** were changed by a balance wave and
neither was covered here. Both were verified only against a hand-written Python
mirror of the engine — which is precisely the failure mode described at the top
of this file, one step removed: not a stale constant this time, but a stale
*model* of the engine that looks authoritative and can silently drift from it.

| engine | what changed | what it moves |
|---|---|---|
| `LockerRoomEngine.calculateChemistry` | summed leadership/toxicity across the roster (a value that scaled with HEADCOUNT), now normalised **per capita** via `chemistryRating(net:headcount:)` | `applyMoraleEffects` and `weeklyMoraleUpdate` both branch on the number; morale feeds the motivation state machine, holdouts and the whole development loop |
| `WorkloadEngine`'s band table | `.overloaded` 80 → **56**, `.burnedOut` 130 → **63** | `WorkloadStatus.injuryMultiplier` (×1.6 / ×2.5), `TrainingPlanEngine.burnedOutGainFactor`, and two camp UI warnings |

`sync_sources.sh` now stages both files the way it stages everything else — awk
keep-list slice, `verbatim_guard` (every non-blank line must be a repo byte), and
named grep guards on the lines that carry the fix. It also stages
`WeekAdvancer.campIntensity(for:)` and `computeRecoveryRate(coaches:)`, because a
workload band table can only be judged against the loads the **camp scheduler**
can actually emit — re-typing 0.45 / 0.85 / 0.55 into the scenario would have
measured a camp the app does not run.

Rosters come out of `LeagueGeneratorExtract`: bodies, ages, salaries, contract
runway, and (new in this wave's staging) `initialMorale` and
`realisticContractYears`. `calculateChemistry` reads morale at six thresholds
(75 / 70 / 60 / 50 / 45 / 40), so a hand-drawn morale would have made the whole
chemistry number a fiction.

### What it runs

- **A.** `--clubs` (default 400) × 53-man rosters built by the shipped generator
  with the shipped uniform archetype draw → `LockerRoomEngine.chemistryScore`.
  Reports mean, sd, the percentile spread, the share pinned at each clamp, and
  the mix over the engine's own `chemistryLabel` ladder.
- **A2.** the same roster build with all 53 men forced to ONE archetype, nine
  rows — the widest a GM could build in each direction. Plus the analytic clamp
  points, computed by `chemistryRating` itself.
- **B.** the shipped 21-day camp cycle (`resetCampLoad` at OTAs, then one
  `tickWeek` per phase at `campIntensity(for:)`) over the same rosters at the
  league-default recovery rate, reported as the band split at preseason exit
  plus the mean injury multiplier.
- **B2.** the same camp swept across the user club's strength coach through
  `computeRecoveryRate`.

The AI-club recovery rate is read as `computeRecoveryRate(coaches: [])` rather
than typed: `applyAICampWorkload` hard-codes the same number the no-coach
fallback returns, and `sync_sources.sh` fails the build if that stops being
true.

### Published bands

Chemistry, 400 clubs:

| quantity | band | measured | PRE-CHANGE |
|---|---|---|---|
| league mean chemistry | **52–64** | 57.6 | **98.0** |
| sd across clubs | **1.5–6.0** | 2.7 | ~0 (the meter could not move) |
| share pinned at 100 | **0–2 %** | 0.0 % | **83 %** |
| share pinned at 0 | **0–2 %** | 0.0 % | 0 % |
| travel, best archetype mix − worst | **≥ 35** | 62.8 | 0 (every mix read 100) |

Camp workload at preseason exit, league-default recovery (0.550 — 31 of 32
clubs):

| quantity | band | measured | PRE-CHANGE |
|---|---|---|---|
| `.overloaded` + `.burnedOut` share | **2–40 %** | 14.5 % | **0.005 %** (see below) |
| `.burnedOut` share | **0–15 %** | 1.6 % | **0.000 %** |
| mean injury multiplier | **1.02–1.35** | 1.101 | **1.000, for every player in the league** |
| p90 exit load | inside `[underloadedMax, overloadedMax]` | 56 | — |
| max exit load | `< absoluteCap` | 84 | — |

Five **hard gates** (the scenario exits 1): chemistry pinned-at-100 < 50 %,
league mean chemistry < 90, travel ≥ 20, `.overloaded`+`.burnedOut` > 0, mean
injury multiplier > 1.000. They are deliberately looser than the bands above —
they are regression guards on two defects that were *measured*, not a
restatement of the distribution. The bands carry the tight expectation and do
not gate, because this scenario's job is to report what the engine does, not to
hold it still.

### What the measurement says about the change

**Chemistry.** The per-capita rating puts an ordinary club at **57.6**, inside
the engine's own "Average" 50..<65 label band, with 98 % of clubs reading
*Average* and 2 % *Strong*. Every consumer branch is now reachable in both
directions and none of them is free: the `>= 65` arm needs a genuinely
leader-heavy room and the `< 50` arm a genuinely toxic one. The travel table
shows where those rooms come from — a 53-man room of Team Leaders reads 87.5
(*Elite*), of Mentors 87.3, of Drama Queens 24.6 (*Toxic*), of Fiery Competitors
38.8 (*Shaky*) — and it shows the clamps are **not** reachable by archetype
alone: `chemistryRating` rails at ±8.0 net per head, which is a roster of
*entirely happy* Team Leaders or *entirely unhappy* Drama Queens, and generated
morale never delivers all 53. That is the correct shape for a 0-100 dial: the
ends exist, and they cost something.

**Workload.** The re-anchored table lands the league at
11.6 / 73.9 / 13.1 / 1.6 % across `.underloaded` / `.healthy` / `.overloaded` /
`.burnedOut`. The engine's own justification for `healthyMax = 56` — "the
measured p90 of a default-intensity club's end-of-cycle load" — **reproduces
exactly**: measured p90 is 56, run after run. The median man finishes at 42 and
reads `.healthy`, which is what `MedicalEngine.workloadRiskMultiplier`'s comment
says the league-wide tick has to leave a default-intensity roster in.

### Deviation notes — three places the engine's own comments are optimistic

Recorded, not fixed. A harness measures the engine; it does not edit it.

1. **`WorkloadEngine`'s comment says the 21-day cycle "tops out at 70".** It does
   not. Measured over 42 400 players, **0.77 %** finish above 70 and the maximum
   observed exit load is **84**. The lattice in that comment assumes the OTAs
   week contributes nothing, which holds for the median body but not for a
   low-stamina one: `round(0.45 · 18 · staminaFactor)` reaches 7 against a
   recovery of 6 once `staminaFactor ≥ 0.803`, i.e. stamina ≤ 48.
2. **The conclusion the re-anchoring rests on survives anyway, with a thinner
   margin than claimed.** The pre-change `.overloaded` edge of 80 was reachable
   by **~0.005 %** of the league (measured 0.000 %–0.009 % over three 42 400-player
   runs — of order one player per league per several seasons), not the flat
   zero the comment asserts; the pre-change `.burnedOut` edge of 130 was reachable
   by **exactly 0 %**. So both upper bands were dead in practice and the ×1.6 /
   ×2.5 rungs really were unreachable — but the true ceiling is 84, not 70, and
   the old 80 sat 4 points *below* it rather than 10 above.
3. **`.burnedOut` is ~4× more common than the comment estimates.** The engine
   comment puts a 63-load camp at "~0.4 % of a roster, roughly one player every
   other club per camp". Measured at the league-default recovery it is **1.6 %**
   — about **0.8 players per club per camp**, i.e. roughly one man per club, not
   one per two clubs. Still rare enough that the ×2.5 rung is an event rather
   than a tax.

### The strength coach is a 5-rung step, not a curve

`computeRecoveryRate` maps a coach's `playerDevelopment` 1..99 onto 0.40..0.75
linearly — but `applyDailyLoad` consumes it as `Int((rate · 10).rounded())`, so
the whole 1-99 axis collapses to **five** distinct camps. Measured band split at
preseason exit:

| coach rating | recovery | daily recovery | under | healthy | over | burnt | mean load |
|---|---|---|---|---|---|---|---|
| 1 | 0.400 | 4 | 0.0 % | 0.0 % | 2.6 % | **97.4 %** | 81.5 |
| 25 | 0.486 | 5 | 0.0 % | 24.8 % | 6.7 % | 68.5 % | 60.5 |
| 50 / 60 / 70 | 0.575–0.646 | 6 | 10.8 % | 74.5 % | 13.1 % | 1.6 % | 41.2 |
| 80 / 88 | 0.682–0.711 | 7 | 83.3 % | 16.7 % | 0.0 % | 0.0 % | 27.1 |
| 99 | 0.750 | 8 | 99.2 % | 0.8 % | 0.0 % | 0.0 % | 13.3 |

Diagnostic, deliberately ungated. It is reported because it is the kind of thing
a hand mirror of the engine would never have surfaced: hiring a strength coach
is worth nothing at all across three of the four rating bands the game can hand
you (a 50 and a 70 run an identical camp), and everything at the two boundaries.
Whether that is a defect is a design question, not a harness one.

### Known gap

`CareerScenario.harness.swift` still substitutes a hand-rolled morale drift with
**no chemistry term at all** (`driver/CareerScenario.harness.swift`, the
"Locker-room mood" block). With `LockerRoomExtract` staged, replacing it is now a
call-site change only — `LockerRoomEngine.chemistryScore(players:)` once per club
per season, then `weeklyMoraleUpdate(players:wonLastGame:chemistry:)` in place of
the hand-rolled win/role/reversion arithmetic. It was not done in this wave
because that file was owned by another agent at the time; it must be done with
the `career` bands re-read afterwards, and if they shift, the shift is the
result — the engine does not move to keep them.

---

`positionsweep` confirms the **discrimination is clean and monotone** even where
aggregates run hot — e.g. sweeping `CB` drives opponent completion **74.8 → 59.5 %**
and home win% **33 → 80 %**; sweeping `QB` drives net YPA **6.5 → 10.1** and
completion **52 → 76 %**. Equal-tier matchups sit near 50/50 with a modest
engine home-field tilt (~56–62 % home over small N).

---

## Coached sim-to-final (`coachedgame`)

Every scoring number this rig had ever taken came out of `GameSimulator.simulate`
— the **quick sim**. The game the user actually plays runs `LiveGameEngine`, and
its "sim to final" button is `simToEnd()`: a loop over `step()` behind a 500-play
safety cap with **no score check at all**. So a 60-21 coached blowout had nothing
to be compared against — not a distribution, not a ceiling, not even the quick
sim. This scenario is that comparison.

### What it stages

`LiveGameEngineExtract.swift` is the shipped 3 700-line engine minus exactly one
function: `persist(to:context:teamsByID:)`, the post-whistle SwiftData write-back
(final score onto the `Game` row, team records, season/postseason stats, injury
persistence). It is the file's **only** reference to `Game` / `ModelContext` /
`WeekAdvancer` / `MedicalEngine.applyInjury`, it runs strictly after the last
snap, and it holds no balance math. Its doc-comment block goes with it, so the
strip leaves no orphan comment behind.

Getting there pulled in four more staged sources:

- `CoordinatorPersona.swift` — verbatim (and it is what let §2 stop slicing
  `AdaptiveOpponentAI.swift`);
- `MatchupResolverExtract.swift` — verbatim minus its trailing
  `extension SimPlayer`, whose `displayNumber` / `shortName` helpers
  `SimPlayer.harness.swift` has carried as a **hand-copy** since before this file
  was staged. Redeclaring them would be ambiguous, so they are stripped — and
  the hand-copy they shadow is now diffed against the repo on every sync (the
  jersey-range table line-for-line, the `shortName` body line-for-line);
- `MedicalEngineExtract.swift` — widened from `dressed()` alone to also carry
  `workloadRiskMultiplier` and `facilityRiskMultiplier`, the two terms
  `LiveGameEngine` folds into its per-play injury roll;
- `FacilityEngineExtract.swift` — the tier ladder and the medical-wing injury
  multiplier, verbatim. Its club lookup (`levels(forPlayer:)`) fetches through a
  `ModelContext` and cannot come across; the harness shim returns `.standard`,
  which is **exactly** what the shipped function returns for a player with no
  `teamID`. Both halves of that claim are guarded: the repo's short-circuit line
  must still be there, and the stub `Player` must still declare an always-nil
  `teamID`.

### Die-watches

Every constant the scenario's numbers depend on aborts the sync if the repo stops
defining it: both prep clamps (`min(0.20, audibleBoost)` / `min(0.15,
defReadBoost)`), both half-strength momentum folds (`audibleBoost * 0.5` /
`defReadBoost * 0.5`), the `playCount < 500` cap in `simToEnd`,
`perPlayInjuryRisk` and its two multipliers, and a whole-file `diff` of every
`static let <name> = <number>` across the strip. The scenario file itself is
grepped for re-typed prep-boost literals — it must read the ceiling off the
engine's behaviour, never name it.

### How the prep ceiling is measured, not typed

The sweep asks `LiveGameEngine` for four boost pairs, the last of which is
**double the shipped clamp** (`0.40 / 0.300`). A binding clamp shows up from
outside as `max` and `over` measuring the same game. They agree to **0.12 of a
point**, and the boosts turn out to be nearly inert on scoring at all: the
ceiling buys the player **−0.06 points per game**. Whatever makes a coached game
high-scoring, it is not opponent prep.

### What it found

At `--n 400` (6 400 coached games vs 1 600 quick-sim reference games):

| | coached (no prep) | quick sim | delta |
|---|---|---|---|
| points / team-game | 27.30 | 20.46 | **+6.85** |
| drives / game | 20.75 | 23.31 | −2.56 |
| scrimmage plays / game | 139.90 | 144.86 | −4.96 |
| points / drive | 2.63 | 1.76 | **+0.88** |

`LiveGameEngine`'s own header promises that a nil-argument live game is
"statistically identical to `GameSimulator.simulate`", and `simToEnd()` is
precisely such a game. It is not identical: it scores a third more, and the
attribution is unambiguous — the coached path takes **fewer** possessions and
converts each one **50 % better**. The tail follows: the winning team's p99 is
**60** coached against **51** quick, a team reaches 50+ in **7.80 %** of coached
games against **1.50 %** quick, and 60+ in **1.03 %** against **0.06 %**.

That divergence is a defect, and sizing it is a different job from fixing it —
which is why `CG-1` gates it at 9.0 rather than at parity. A rail set at parity
would fail on every run and guard nothing; set at 9.0 it stops the gap growing
while the product call on it is outstanding.

### The gates

All seven are set **from** the first full run, and deliberately loosely — the
printed tables carry the tighter expectations, because this scenario's job is to
report what the coached engine does, not to hold it still.

| id | rail | measured |
|----|------|----------|
| CG-1 | coached-vs-quick per-team points gap ≤ **9.0** | 6.85 |
| CG-2 | prep saturates: max-request vs double-the-clamp ≤ **1.5** | 0.12 |
| CG-3 | max prep lift on the player's own scoring ≤ **3.0** | −0.06 |
| CG-4 | p99 of the winning team's score ≤ **66** | 60 |
| CG-5 | share of games with a 60-point team ≤ **2.50 %** | 1.03 % |
| CG-6 | p99 margin of victory ≤ **62** | 53 |
| CG-7 | longest play log **< 500** (the `simToEnd` cap never truncated) | 195 |
