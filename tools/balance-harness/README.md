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
  build/                 GENERATED, git-ignored — reproduced by sync_sources.sh
    src/                 staged engine sources + MANIFEST.txt
    harness              compiled binary
```

`build/` is `.gitignore`d — nothing generated is committed. Only the four
authored files (`sync_sources.sh`, `run.sh`, `driver/main.swift`,
`driver/SimPlayer.harness.swift`) plus this README live in git.

---

## How the source staging works

`sync_sources.sh` produces `build/src/` in three ways:

### 1. Verbatim copies (10 files, SHA-verified)

`PlayCall.swift`, `PlayType.swift`, `Position.swift`, `Scheme.swift`,
`GameWeather.swift`, `PersonalityArchetype.swift`, `PlayResult.swift`,
`PlayerAttributes.swift`, `GamePlan.swift`, `PlaySimulator.swift` are copied
byte-for-byte. The script asserts `sha(copy) == sha(repo)` for each and records
both in `MANIFEST.txt`; a mismatch aborts the build.

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

`MANIFEST.txt` records the role (`VERBATIM` / `EXTRACT` / `ASSEMBLED`), the
staged file's SHA, and the repo source SHA for every file.

---

## Running

```bash
./run.sh <scenario> [scenario ...]     # sync + build + run
./run.sh all                           # every scenario
./run.sh --no-sync depth               # reuse build/src, skip re-sync
BH_N=60000 ./run.sh regression         # override per-cell sample size
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
