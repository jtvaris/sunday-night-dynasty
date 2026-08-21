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

- copies 10 engine sources **verbatim** from the repo and asserts each copy's
  SHA-256 equals the repo file's, and
- **regenerates** the adaptive-AI code by mechanically slicing it out of the
  real `AdaptiveOpponentAI.swift`, then **fails the build** if a single tuning
  line differs from the repo.

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
  build/                 GENERATED, git-ignored — reproduced by sync_sources.sh
    src/                 staged engine sources + MANIFEST.txt
    harness              compiled binary
```

`build/` is `.gitignore`d — nothing generated is committed. Only the five
authored files (`sync_sources.sh`, `run.sh`, `driver/main.swift`,
`driver/SimPlayer.harness.swift`, `driver/GameModels.harness.swift`) plus this
README live in git.

---

## How the source staging works

`sync_sources.sh` produces `build/src/` in three ways:

### 1. Verbatim copies (30 files, SHA-verified)

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

**Development stack (6, stage 5):** `InjuryType.swift`, `CampEnums.swift`,
`MotivationState.swift`, `InjuryRecord.swift`, `PlayerDevelopmentEngine.swift`,
`PlayerRetirementEngine.swift`.

All 30 are copied byte-for-byte. The script asserts `sha(copy) == sha(repo)` for
each and records both in `MANIFEST.txt`; a mismatch aborts the build.

### 2. `AdaptiveOpponentAIExtract.swift` — mechanically sliced from the repo

The shipped `Engine/Match/AdaptiveOpponentAI.swift` does not compile standalone:
its four **persona-hint** functions (`defenseKeyHint`, `exactCallHint`,
`categoryKeyHint`, `offenseAdjustHint`) reference `DCPersona` / `OCPersona`,
which live in `CoordinatorPersona.swift` and are pure UI-broadcast text — no
balance math. Everything else (the `OffenseTendency` enum, `RunKeyState`,
`PlayMemory`, `counterConcepts`, the `paKey*`/`runKey*` levers, and **all** the
`static let` tuning constants + `catPivot`/`catAlpha`) resolves against the
verbatim sources above.

So the extract is produced by an `awk` pass that copies the repo file
line-for-line and **skips only those four functions** (brace-balanced deletion
from each `static func …Hint(` declaration to its closing brace). Because those
functions contain zero balance constants, every tuning literal flows through
untouched, straight from the repo bytes. The script then enforces two guards
before accepting the slice:

- **no persona leak** — `grep` for `DCPersona`/`OCPersona` in the sliced code
  must find nothing (proves the right functions were removed); and
- **constant-drift guard** — it `diff`s every balance-constant line
  (`static let …`, and the `paKeyCompletion` / `paKeyBigPlay` /
  `runKeyYardBite` / `runKeyStuffBonus` / `catPivot` / `catAlpha` signatures)
  between the repo file and the slice. They must be **byte-identical** (39 lines
  as of e1b0845); any difference aborts the build.

This is the anti-drift core: the constants are never retyped, and the build
proves it every time.

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
| `perception` | **AI draft fog (Track C)** — 32 personas draft N boards twice off the same rosters, once through `AIDraftPerception` and once on the true board (`--perceptionEnabled false`), through the shipped `DraftEngine.aiMakePick` | DIAGNOSTIC ONLY, always exits 0: R1 reaches / steals / true-BPA slide and mean \|perceived − true\| by GM persona |

The last six are **parameterized** — they take `--flag value` args instead of a
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

`positionsweep` confirms the **discrimination is clean and monotone** even where
aggregates run hot — e.g. sweeping `CB` drives opponent completion **74.8 → 59.5 %**
and home win% **33 → 80 %**; sweeping `QB` drives net YPA **6.5 → 10.1** and
completion **52 → 76 %**. Equal-tier matchups sit near 50/50 with a modest
engine home-field tilt (~56–62 % home over small N).
