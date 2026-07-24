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

### 1. Verbatim copies (17 files, SHA-verified)

**Play-by-play (11):** `PlayCall.swift`, `PlayType.swift`, `Position.swift`,
`Scheme.swift`, `GameWeather.swift`, `PersonalityArchetype.swift`,
`PlayResult.swift`, `PlayerAttributes.swift`, `GamePlan.swift`,
`PlaySimulator.swift`, `HeatState.swift`.

**Full-game pipeline (6, round 5):** `DriveResult.swift`, `BoxScore.swift`,
`PlayerGameStats.swift`, `CoachingModifiers.swift`, `DriveSimulator.swift`,
`GameSimulator.swift` — the SHIPPED complete-game engine, so the `fullgame` /
`positionsweep` scenarios run the exact box-score pipeline the app ships (no
reimplemented game loop, momentum, clock, heat feed, or box score).

All 17 are copied byte-for-byte. The script asserts `sha(copy) == sha(repo)` for
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

The last two are **parameterized** — they take `--flag value` args instead of a
scenario-name list (see "Round-5 full-game campaign" below), so they are invoked
on their own, not via `all`.

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
```

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

`positionsweep` confirms the **discrimination is clean and monotone** even where
aggregates run hot — e.g. sweeping `CB` drives opponent completion **74.8 → 59.5 %**
and home win% **33 → 80 %**; sweeping `QB` drives net YPA **6.5 → 10.1** and
completion **52 → 76 %**. Equal-tier matchups sit near 50/50 with a modest
engine home-field tilt (~56–62 % home over small N).
