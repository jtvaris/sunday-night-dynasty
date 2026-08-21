# AI Gameday & Week-to-Week Decision-Making: Implementation Audit and Realism Assessment

**Scope:** read-only analysis of `/Users/jtvaris/workspace/projects/Dynasty`, engine under `dynasty/dynasty/Engine`.
**Date:** 2026-08-21. **Branch:** `feat/skeletal-mocap-players` @ `3423d35`.
**Deliverable:** assessment only. No code changed, nothing committed.
**Measurement rig:** `tools/balance-harness/` (`./run.sh spam stacking` executed read-only for §1.6).

---

## THE ONE-PARAGRAPH VERSION

The AI has a genuinely good adaptive play-calling brain, and it is switched on for **one game per week out of sixteen**. For the other fifteen, `WeekAdvancer.simulateGameScore()` rolls two dice that have never heard of a roster, a coach, a game plan or an injury. Every standing in the league is therefore noise. On top of that, the three "weekly preparation" systems the fiction sells — game plan, opponent prep, fourth-down aggressiveness — are wired so that the user gets them and all 31 rivals are hard-coded to `nil`, and one of them (opponent prep) is a flat **+10 % / −7.5 % multiplier on the final score** worth roughly **+2 wins a season, for free, forever**. On the imperfection question: the entire shipped game contains exactly **one** modelled AI decision error (`DCPersona.misreadChance`), it exists only in coached games, and it is exactly `0.0` for the two most common coordinator personas and for every AI offense in the league.

---

# PART 1 — THE IN-GAME BRAIN

## 1.1 The map: there are three game paths, not two

| # | Path | Entry point | Situational brain | Volume per regular-season week |
|---|---|---|---|---|
| 1 | Coached 3D game | `Engine/Match/LiveGameEngine.swift:1413` (`step`) | Full — plus timeouts, kneel/spike, onside, `PlayMemory`, coordinator personas | 0 or 1 game |
| 2 | Quick sim of the **user's** game | `Engine/Simulation/GameSimulator.swift:100` (`simulate`) → `DriveSimulator.simulateDrive:32` → `PlaySimulator.simulatePlay` | Full play-by-play, shared code with path 1 | 1 game (if not coached) |
| 3 | **The other 15 games** | `Engine/Simulation/WeekAdvancer.swift:1383` → `simulateGameScore()` (`:971`) | **None whatsoever** | **15 games** |

Path 3 is the volume path and it is worth stating precisely, because everything in Parts 2 and 4 depends on it.

```swift
// WeekAdvancer.swift:1382-1386
} else {
    let score = simulateGameScore()
    game.homeScore = score.home
    game.awayScore = score.away
}
```

`simulateGameScore` (`WeekAdvancer.swift:971-990`) calls `randomTeamScore(homeAdvantage:)` (`WeekAdvancer.swift:8186-8214`), whose **entire signature is one `Int`**:

```swift
private static func randomTeamScore(homeAdvantage: Int) -> Int {
    let tdBucket = Int.random(in: 1...10)      // 0 / 1 / 2 / 3 / 4 / 5-6 touchdowns
    let fgBucket = Int.random(in: 1...8)       // 0 / 1 / 2 / 3-4 field goals
    let raw = (touchdowns * 7) + (fieldGoals * 3) + homeAdvantage
    return max(0, raw)
}
```

No team, no roster, no coach, no scheme, no weather, no injuries, no score state. The architecture note is explicit at `SeasonStatSynthesizer.swift:16` — *"AI teams in a live season | 31 of 32 games are score-only (`WeekAdvancer.simulateGameScore`)"* — and the same generator drives the **playoffs** (`WeekAdvancer.swift:7324-7327`), the **Pro Bowl** (`:3065`) and **preseason** (`PreseasonEngine.swift:729`).

### What that costs, arithmetically

Working the two discrete distributions out exactly (derivation in `randomTeamScore`'s own buckets):

```
E[TD] = 0(.10) + 1(.20) + 2(.30) + 3(.20) + 4(.10) + 5.5(.10)      = 2.350
E[FG] = 0(.125) + 1(.375) + 2(.375) + 3.5(.125)                     = 1.5625
E[pts]  away = 2.350×7 + 1.5625×3          = 21.14
E[pts]  home = 21.14 + 3                   = 24.14
sd(pts)      = √(49·2.3275 + 9·0.9961)     = 11.09
margin       = N(3.00, sd 15.69)
```

Convolving the two exact distributions:

| quantity | model | real NFL | source |
|---|---:|---:|---|
| points / team / game | 22.6 | 21.8 (2023) | PFR league totals |
| home win rate, raw | 55.2 % | | |
| home win rate, **after the tie-break rule** at `:984-987` | **58.8 %** | **53.2 %** (2019-2023, 714-625-4) | [PFF](https://www.pff.com/news/nfl-home-field-advantage-pff-data) |
| sd of team season wins (17 g) | **2.06** | ≈ 3.0-3.2 | PFR standings |
| corr(roster quality, wins) | **exactly 0** | strongly positive | — |

Two findings fall straight out:

1. **The tie-break at `WeekAdvancer.swift:984-987` is a bug, not a rounding detail.** Because every score is a sum of 7s and 3s, **4.19 %** of matchups land on an exact tie, and the code hands every one of them to the home side (`return (homeScore + 1, awayScore)`). That single line supplies 4.2 of the 5.6 percentage points by which the model's home advantage exceeds the modern NFL's.
2. **The AI league's standings are pure noise with a mean of 8.5-8.5.** A 13-win AI team appears every season and it means nothing. Nothing an AI front office does — draft, develop, train, gameplan, heal — can move its record by a single game.

## 1.2 The play-selection brain

`PlaySimulator.decidePlayCall` (`Engine/Simulation/PlaySimulator.swift:311-470`) is the whole offensive brain for paths 1 and 2. It returns a bare `PlayType` (`.run` / `.pass` / `.punt` / `.fieldGoal`).

**Inputs it reads (`:311-323`):** `down`, `distance`, `yardLine`, `quarter`, `timeRemaining`, `offensiveScheme`, `gamePlan`, `weather`, `scoreDifferential`.

**Inputs it does NOT read:** personnel (who is on the field, who is hurt, who is fatigued), timeouts remaining, opponent tendencies, the defensive package about to be shown, field-goal range as a function of *its own kicker*, or any win-probability/expected-points model. There is no EV model anywhere in the repo.

### The pass-probability stack (`:353-394`)

```
schemePassBias = schemeOnlyPassBias + planPassBias + weatherPassBias + mgmtPassBias
```

| term | range | line |
|---|---|---|
| scheme | −0.15 (powerRun) … +0.15 (airRaid) | `:354-366` |
| game plan | `(runPassRatio − 0.5) × 1.00` if run-lean, `× 0.60` if pass-lean | `:388-389` |
| weather | −0.08 in snow only | `:393` |
| game management | ∓`min(0.40, 0.030 × (\|margin\| − 6))`, Q3+ only, \|margin\| ≥ 7 | `:308-310, :339-346` |

Base weights (`:450-469`): 1st down 0.50 · 2nd-and-7+ 0.65 · 2nd-and-short 0.50 · 3rd-and-≤3 0.42 · 3rd-and-4-6 0.65 · 3rd-and-7+ 0.80 · 4th-down-go 0.55.

**Because `gamePlan` is `nil` for every AI team (§2.1), the `planPassBias` term is identically 0 for 31 clubs.** Every AI offense in the league runs the same scheme-shaded mix, forever.

### The 4th-down decision (`:397-436`)

Priority order, first match wins:

```swift
402:  if lateGame && scoreDifferential >= 7 { return fieldGoalRange ? .fieldGoal : .punt }
409:  if let plan = gamePlan, plan.fourthDownAggressiveness < 0.35 { ...kick/punt... }
417:  if distance <= 2 && yardsToEndzone <= 5 { return coinFlip(0.5 + bias) ? .pass : .run }
421:  if isTwoMinuteDrill && yardsToEndzone > 45 { return coinFlip(0.7 + bias*0.5) ? .pass : .run }
426:  if let plan = gamePlan, plan.fourthDownAggressiveness > 0.65, distance <= 3, yardLine >= 50 { ...go... }
431:  if fieldGoalRange { return .fieldGoal }
435:  return .punt
```

with `fieldGoalRange = yardsToEndzone <= 45` (`:351`) and `isTwoMinuteDrill = quarter == 4 && timeRemaining <= 120 && scoreDifferential < 7` (`:349-350`).

**Lines 409-415 and 426-429 are unreachable for all 31 AI clubs** (nil plan). The AI's complete 4th-down table is therefore:

| situation | AI decision |
|---|---|
| Q3/Q4, leading by ≥ 7 | FG from the opp. 45 in; punt otherwise. **Never goes for it, not even 4th-and-goal from the 1.** |
| 4th-and-≤2 inside the opponent's 5 | Go (50/50 run/pass) |
| Q4, ≤ 2:00, margin < +7, ball beyond the opp. 45 | Go (70 % pass) |
| Ball at the opponent's 45 or closer | Field goal — **up to a 62-yarder**, regardless of kicker |
| everything else | Punt |

There is no expected-points model, no 4th-and-1-at-midfield rule, no down-by-two-scores aggression outside the last two minutes, and no dependence on the head coach.

## 1.3 The defensive brain

`DriveSimulator.situationalDefensivePackage` (`DriveSimulator.swift:266-298`) is the single shared defensive call sheet — the live engine enters it at `LiveGameEngine.baseDefensivePackage:1837-1846`, so quick sim and coached game cannot drift.

1. `yardsToEndzone <= 10` → man / no blitz / goal-line
2. `quarter >= 4 && timeRemaining <= 240 && 0 < defenseLeadsBy <= 16 && yardsToEndzone > 25` → **prevent** / no blitz / dime
3. `down == 3 && distance >= 7` → cover-4 / no blitz / dime
4. `distance <= 2` → cover-1 / no blitz / bear
5. else → `.standard` (cover 3, no blitz, base front)

Five branches, no personnel input, no tendency input, no coach input. It is a competent skeleton and it is the same skeleton for a 95-grade DC and a 40-grade one.

## 1.4 The adaptive layer — real, well-built, and reachable in one game a week

`Engine/Match/AdaptiveOpponentAI.swift` (821 lines) is the best-engineered part of this audit. It has three layers with sharply different reach:

| Layer | What it is | Reachable from quick sim? | Reachable in AI-vs-AI? |
|---|---|---|---|
| **A — `RunKeyState`** (`:525-576`) | down-bucketed EWMA of the *current offense's* run share; α 0.18, pivot 0.55, full 0.72. Drives a yard bite (`runKeyYardBite(i) = i × 1.1`, `:751`) + stuff bonus (`i × 0.08`, `:753`) and opens the PA counter (`paKeyCompletion(i) = i × 0.035`, `paKeyBigPlay(i) = i × 2.0`, `:758-761`) | **Yes** — `DriveSimulator`/`GameSimulator` own instances | No (path 3 runs no plays) |
| **B — `PlayMemory`** (`:600-736`) | 7 per-concept EWMAs + a 4-wide exact-call ring. Caps: `passTotalMalusCap 0.24`, `runGrandBiteCap 1.80`, `exactPassCap 0.20`, `exactRunYardCap 2.00` (`:794-796`) | **No** — `record(call:down:)` fills solely from the human's explicit calls (`:635`) | No |
| **Tendency tracker + counters** (`:190-412`) | recency-weighted (0.85^age, window 10) read of the player's call families; rolls a scheme-filtered counter package/play | **No** — header at `:35-37`: *"`GameSimulator.simulate` never touches this type"* | No |

`CoordinatorPersona.swift` (DCPersona `:39`, OCPersona `:333`) is wired **only** into `LiveGameEngine` (`:1342-1345`, `:1953-2064`). Its own header states it at `:23`: *"nothing here is reachable from `GameSimulator.simulate`."*

Two structural consequences:

- **The AI never adapts across games or across a season.** `RunKeyState` and `PlayMemory` are documented as *"no `Codable` conformance, never persisted — the state lives for exactly one game and is rebuilt from scratch each time"* (`:523-524`, `:599`). There is no opponent scouting report, no film study, no "they beat us with the same thing in week 4."
- **Personas are constant for the life of a coach.** `stablePersonaPick` (`:31-35`) hashes the coach's UUID. The same DC is Aggressive every week of every season against every opponent.

## 1.5 Coach quality: moves execution, never decisions

`CoachingModifiers` (`Engine/Simulation/CoachingModifiers.swift`) is symmetric and correctly plumbed into both paths 1 and 2. Magnitudes:

| mechanic | slope | cap | line |
|---|---|---|---|
| coordinator grade → completion | 0.0015 / pt off 70 | ±0.045 | `:44-46` |
| coordinator grade → ypc | 0.012 / pt | ±0.35 | `:48-49` |
| game planning → completion / ypc | 0.0006 / 0.006 | ±0.018 / ±0.18 | `:53-56` |
| scheme expertise (positive only) | 0.001 / 0.009 | +0.022 / +0.22 | `:62-65` |
| **net after composition** | | **±0.07 comp, ±0.75 ypc** | `:68-69` |
| discipline → penalty/fumble scale | 0.010 / pt | ×0.72 … ×1.28 | `:74-76` |

That is a real, meaningful spread (7 pp of completion between the best and worst staff). **But not one of these coefficients touches a decision.** An elite head coach and a replacement-level one punt from the same yard line, attempt the same 62-yard field goals, never call a timeout, and never take a knee. Coach quality changes *how well the players execute the same call*, never *which call is made*.

The one exception is the adaptive layer's *timing*: `scaledThreshold(base:coordinatorGrade:)` (`:66-68`) and `counterShare(coordinatorGrade:)` (`:72-74`) let an elite DC key sooner (~30-35 % tendency vs ~50 %) and counter more often (0.60 vs 0.20 share) — coached games only.

## 1.6 Degenerate exploits: the harness says the anti-spam machinery works

The README's "stale shim" incident (`tools/balance-harness/README.md`, *Why this exists*) is the repo's own account of how balance numbers went wrong: hand-copied `AdaptiveOpponentAI` constants drifted from the repo (`paKeyCompletion` `i*0.18` vs the real `i*0.035`; `paKeyBigPlay` `i*8.0` vs `i*2.0`), inflating measured keyed PA-deep to ~40 net YPA against a true ~11. The harness now regenerates the extract mechanically and diffs all 39 constant lines against the repo, failing the build on any difference.

I ran two scenarios read-only at the default N = 40 000. Header confirms the live constants: `paKeyCompletion(1.0)=0.035  paKeyBigPlay(1.0)=2.00  (repo 0.035/2.0)`.

```
===== SCENARIO spam =====
SPAM-COLLAPSE  inside r1=4.11 r4=1.76 (43% of r1)   toss r1=4.07 r4=1.74 (43%)
MIXED-PARITY   memory ON ypc=4.51 passEV=6.42 | OFF ypc=4.50 passEV=6.30
               Δypc=+0.01  ΔpassEV=+0.11  (balanced control, |Δ| ≤ 0.3)  maxAnt=0.50

===== SCENARIO stacking =====
5a WORST-CASE RUN  (spam + fullKey + fam20 bust)  ypc=1.54  stuff=43.7%  neg=26.1%
5b WORST-CASE DEEP (spam bomb + fam20)            comp=14.4%  netYPA=2.59  deepΔ=−0.240 (cap 0.24)
5c WORST-CASE SHORT(spam slant + fam20)           comp=36.3%             shortΔ=−0.240
```

**Reading:** repeating one call collapses it to **43 % of its first-call value** by the fourth repetition, and stacking a scheme bust on top floors an inside run at **1.54 ypc / 43.7 % stuffed**. Meanwhile a *mixed* caller is untouched (Δypc +0.01) — the balanced-control guarantee holds. The `keyed-pa` band (9-12 net YPA @ 70/70, README) and the `stacking` floors are the fairness rails, and they are real.

**The verdict on exploits is therefore split:**

- **Within a coached game, one-play spam is dead.** Verified above.
- **Outside a coached game, the exploit is not a play call at all — it is the two user-only levers in Part 2.** Opponent prep (+4.2 points of margin per game) and the game plan (a 4th-down aggressiveness knob no rival has) are structural, permanent, and cannot be countered by an AI that has neither.
- **The full-game aggregates already run hot from play selection alone.** README §Round-5: at the engine's own calibration point (70 vs 70, attribute-identical to the per-play bands) full games land net YPA **8.4**, pass yds **330**, 3rd-down **50 %**, points **29** — all `[OUT]` high against NFL bands, while plays/comp/sacks are `[OK]`. The README's own diagnosis: *"the gap is pure play-selection."* The situational brain is more efficient than real coaches, in the direction that inflates scoring.

---

# PART 2 — WEEKLY PREPARATION, GAME PLAN, TRAINING

## 2.1 GamePlan — no AI implementation exists

`Domain/Models/Team/GamePlan.swift:5-57`. Five sliders: `offensiveAggression`, `defensiveAggression`, `runPassRatio`, `blitzFrequency`, `fourthDownAggressiveness`.

**Every write site in the repo is a SwiftUI view**: `UI/Career/CareerShellView.swift:2134` (the user's slider) and `UI/Roster/GamePlanView.swift:431, 531` (the user's recommendation builder). Greps for `aiGamePlan|selectGamePlan|chooseGamePlan|autoGamePlan|generateGamePlan` return **zero hits**.

The AI's value is a hard-coded `nil`, in both the regular season and the playoffs:

```swift
// WeekAdvancer.swift:1359-1373  (playoffs: identical ternary at :7288-7297)
// "The user's saved game plan shades only the user's own offense; the AI
//  opponent always simulates with `nil` (today's exact behavior)."
let userPlan = career.savedGamePlan
homeGamePlan: homeTeam.id == userTeamID ? userPlan : nil,
awayGamePlan: awayTeam.id == userTeamID ? userPlan : nil,
```

The coached game does the same for the AI side: `LiveGameEngine.swift:1789` — `gamePlan: playerIsOnOffense ? playerGamePlan : nil`.

**Three of the five sliders are additionally dead or half-dead for everyone:**

| slider | who reads it | where |
|---|---|---|
| `runPassRatio` | user only | `PlaySimulator.swift:388` (sim) + `LiveGameEngine.swift:2219` |
| `fourthDownAggressiveness` | user only | `PlaySimulator.swift:409, 426` |
| `blitzFrequency` | user only, **coached games only** | `LiveGameEngine.swift:1821-1826` — never reaches `GameSimulator` |
| `defensiveAggression` | user only, **coached games only** | `LiveGameEngine.swift:1828-1830` — never reaches `GameSimulator` |
| `offensiveAggression` | **nobody** | zero read sites outside `GamePlan.styleSummary` |

So a user who quick-sims his own game and moves the Defensive Style or Blitz slider changes nothing at all — and `offensiveAggression` changes nothing in any path, for anyone. `UI/Match/GameSummaryView.swift:386` prints `"\(aggressionLabel(r.plan.offensiveAggression)) offense"` in the post-game "planned vs actual" panel: **UI copy describing an engine behaviour that does not exist.**

## 2.2 Opponent prep — the single largest balance leak in the game

`Domain/Models/Camp/OpponentPrepWeek.swift`. The **only** construction site in the repo is `UI/Camp/GameWeekPrepPicker.swift:188-197`, and it hard-codes `teamID: career.teamID`. No AI club has ever had a row.

The user's row is fetched at `WeekAdvancer.swift:1341-1357` behind an explicit identity guard, converted by `OpponentPrepEngine.gameBoost` (`Engine/Camp/OpponentPrepEngine.swift:15-21`) into `(audibleBoost: 0.20×ratio, defReadBoost: 0.15×ratio)`, and then — this is the part that matters — applied **after the game is over, as a multiplier on the final score**:

```swift
// GameSimulator.swift:519-538
if let boostedID = boostedTeamID, (audibleBoost > 0 || defReadBoost > 0) {
    let audibleMult = 1.0 + (max(0.0, min(0.20, audibleBoost)) * 0.5)   // ×1.10 at 100 %
    let defReadMult = 1.0 - (max(0.0, min(0.15, defReadBoost)) * 0.5)   // ×0.925 at 100 %
    ...
    homeScore = Int((Double(homeScore) * audibleMult).rounded())
    awayScore = max(0, Int((Double(awayScore) * defReadMult).rounded()))
}
```

It never touches a play, a call, an audible or a defensive read. It is a scoreboard edit.

**Magnitude.** At an engine-typical 24 points per side:

```
user   24 × 1.100 = 26.4   (+2.4)
rival  24 × 0.925 = 22.2   (−1.8)
margin swing                +4.2 points, every regular-season game
```

Against an NFL-typical margin sd of 13.5, +4.2 points converts a coin flip into **Φ(4.2/13.5) = 62.2 %**. Over a 17-game season that is **8.5 → 10.6 wins: +2.1 wins per year, free, from one slider, that no rival can ever have.**

**And the designed counterweight does not reach the field.** `OpponentPrepEngine.driftPenalty` (`:26-30`) returns −1…−3 after 3+ consecutive opponent-heavy weeks, applied at `WeekAdvancer.swift:8560-8567` to `player.physical.stamina`. Tracing where `stamina` is read:

- `PlaySimulator.swift`, `GameSimulator.swift`, `DriveSimulator.swift`, `LiveGameEngine.swift`, `SimPlayer.swift` — **zero occurrences**.
- `WorkloadEngine.swift:119` — the only engine consumer, feeding `cumulativeLoad`, which per `docs/INJURY_SYSTEM_ANALYSIS.md` §1.2 is a camp-time constant that never moves in-season.
- `Player.overall` (`Player.swift:578-583`) via `physical.average` — a 6-attribute mean at weight 0.30, so **−3 stamina = −0.15 OVR displayed**. Riding the penalty to the stamina floor of 40 across a season costs ≈ **−1.5 displayed OVR** and **exactly zero simulator effect**.

This is the injury-system bug class again, in mirror image: the *benefit* bypasses the simulator to edit the scoreboard directly, and the *cost* lands in a field the simulator never reads.

## 2.3 Training focus — the one system that is genuinely symmetric

Credit where due. `WeekAdvancer.swift:1926-1939` loops all 32 clubs; `TrainingFocusEngine.autoAssignFocus(roster:)` (`:1931`, implementation `TrainingFocusEngine.swift:265-311`) runs for the 31 AI teams every regular-season week, and the `applyWeeklyFocusTick` that converts focus into `+1` attribute bumps runs for **all** 32 (`:1936`). Those bumps land on real `Player` attributes, which `GameSimulator.swift:132` snapshots into `SimPlayer`. The value reaches the simulator.

The AI's version is a real decision — it recycles slots held by post-peak players (`:272-276`), trims overflow by potential (`:281-289`), and fills from young pre-peak candidates. Two caveats, both material for Part 4:

- **It picks the training area blindly.** `defaultArea(for:)` (`TrainingFocusEngine.swift:65-67`) returns `areas(for: position).first` — always the first listed area, never situational.
- **It sorts candidates on `truePotential`** (`:296-300`) — hidden information. See §4.2.

## 2.4 Depth charts, starters, injuries, rest

- **Neither side has a real depth chart in the simulator.** `GameSimulator.startingPlayer(at:in:)` (`:1885-1886`) and `MatchupResolver.swift:26-87` both pick `max by overall`, computed fresh every read. There is no per-team `DepthChart` object; `DepthChart` exists only as `Career.depthChartData` (one blob, one team).
- **The user's saved depth chart never reaches the engine.** `depthChartData` has zero engine read sites — every consumer is a view (`DepthChartView.swift:260`, `CareerShellView.swift:1424, 2779`, `ScheduleView.swift:97`). `CareerShellView.swift:1409-1411` says so: *"the sim fields `WeekAdvancer.startingLineupIDs`, which is derived from the roster and not from the chart."* An hour spent on the depth-chart screen changes nothing.
- **Injured players still take the field.** `GameSimulator.swift:130-131` and `LiveGameEngine.swift:1283-1284` filter on `!$0.isHoldingOut` only. `isInjured` appears nowhere in `PlaySimulator`, `DriveSimulator` or `GameSimulator`. This is the same terminus `docs/INJURY_SYSTEM_ANALYSIS.md` found: injuries do not affect a game result, for anyone.
- **There is no rest, no IR, no inactive list.** `WeekAdvancer.swift:1781-1784` adds `Int.random(in: 3...8)` fatigue to every non-injured player on every roster, unconditionally — a third-string guard fatigues at the QB's rate. `injuredReserve|placeOnIR|isOnIR` returns exactly one hit repo-wide: `Engine/Event/EventTemplates.swift:396`, a narrative **button label** with no mechanical backing.
- **Rush-back is user-only, by design and by comment.** `WeekAdvancer.swift:2033` gates the rehab decision on `player.teamID == career.teamID`; `:2056-2058` states *"AI teams never rush players back."* `MedicalEngine.rushBack(player:)` has no engine caller — its only caller is `UI/Roster/InjuryReportView.swift:303-310`.

## 2.5 Practice squad — symmetric, injury-aware, and it works

`PracticeSquadEngine.runWeeklyPass` (`:876`) is called at `WeekAdvancer.swift:2232` for all 32 teams every regular-season week. `shorthandedPositions(roster:)` (`:1029-1038`) filters `!isInjured` against position-group ideals, so AI clubs genuinely sign bodies where injuries thinned them. `fillSquads` (`:499`) runs league-wide at the cutdown boundary (`WeekAdvancer.swift:4170`). Roster membership reaches the sim via `currentRoster()`.

Two asymmetries, one in each direction: the user's squad is protected by a one-week warning and a `userPoachInterestChance = 0.18` gate (`:184`, `:918-937`) while AI-vs-AI poaches land immediately (**user favour**); and AI clubs never elevate *their own* squad players — `signToActiveRoster`'s only callers are the two poach paths and the user's view (`PracticeSquadView.swift:305`).

## 2.6 THE SYMMETRY TABLE

| System | User path | AI path | AI's actual value | Reaches the simulator? | Verdict |
|---|---|---|---|---|---|
| **Game plan** | `CareerShellView.swift:2134` | **none exists** | hard-coded `nil` (`WeekAdvancer.swift:1372-1373`, `:7296-7297`) | User's: 2 of 5 sliders (`PlaySimulator.swift:388, 409, 426`). AI's: n/a | **User-only** |
| ↳ `offensiveAggression` | slider exists | — | — | **nobody reads it** | **Dead slider** |
| ↳ `blitzFrequency`, `defensiveAggression` | slider exists | — | — | coached games only (`LiveGameEngine.swift:1821-1830`) | **Half-dead** |
| **Opponent prep** | `GameWeekPrepPicker.swift:189` (view) | **none exists** | nothing | User's: post-hoc score multiplier (`GameSimulator.swift:519-538`). | **User-only, +4.2 pts/game** |
| ↳ its drift penalty | `WeekAdvancer.swift:8560` | — | — | **`stamina` — zero sim readers** | **Dead counterweight** |
| **Training focus** | `DevelopmentReportView.swift` | `WeekAdvancer.swift:1931` | **real decision**, all 31 clubs, weekly | yes, via player attributes | **Symmetric ✓** |
| **Depth chart** | `DepthChartView.swift:271` | no object exists | best-by-overall at read time | **neither** — user's chart is UI-only (`GameSimulator.swift:1885`) | **Cosmetic for both** |
| **Injury / rest mgmt** | `InjuryReportView.swift:303` (view) | **none exists** | nothing | injured players play anyway (`GameSimulator.swift:130`) | **Nonexistent** |
| **Practice squad** | `PracticeSquadView.swift:305` | `WeekAdvancer.swift:2232` | **real decision**, injury-aware | yes, via roster membership | **Symmetric ✓** |
| **Timeouts** | `CoachedGameView.swift:4282` | **none** — `LiveGameEngine.swift:175`: *"AI teams never call timeouts"* | 0 of 6 used | coached only; absent from `GameSimulator` entirely | **User-only** |
| **Kneel / spike** | `CoachedGameView.swift:1725, 1734` | **none** — `decidePlayCall` never returns `.kneel`/`.spike` | never | — | **User-only** |
| **Onside kick** | `CoachedGameView.swift:2367` | **none** — `GameSimulator.swift:37`: *"quick sim never onsides"* | never | — | **User-only** |
| **In-game adaptation** | — | `AdaptiveOpponentAI` (good) | real, but coached games only | never in quick sim or AI-vs-AI | **Reaches 1 game/wk** |

## 2.7 Does AI weekly preparation affect results?

**No, and it structurally cannot.** Four of the eight preparation systems have no AI implementation at all. Of the two that do work symmetrically (training focus, practice squad), both feed roster quality — and roster quality is an input to `GameSimulator.simulate`, which an AI team reaches **at most once per season**, in the one week it plays the user. For the other 16 games it is `Int.random(in: 1...10)`.

Stated as a trace, which is what this repo's precedent asks for:

```
AI training focus  →  +1 attribute  →  Player.positionAttributes
                                    →  SimPlayer(from:)  →  GameSimulator
                                    →  ✗ only runs for the user's game
                                    →  the other 16 games: randomTeamScore(homeAdvantage:)
                                                            ↑ takes no player
```

The value terminates in a function that never sees a roster. Fifteen-sixteenths of the league's season is decided before any preparation is read.

---

# PART 3 — REALISM BENCHMARK

Real figures verified against public sources; links at the end of this part.

| # | Situation | Model | Real NFL | Gap |
|---|---|---|---|---|
| 1 | **4th-down go rate** | ≈ 0.15-0.25 per team-game (goal-line 4th-and-≤2 only, plus last-2:00 desperation) | **1.47 attempts / team-game (2023)**; Detroit 41 attempts (2.4/g) | **6-10× too conservative** |
| 2 | **4th-and-1 go rate** | 0 % anywhere between the opponent's 6 and midfield | **48.6 % attempted (2023)**, converted at 71.3 % when tried; models recommend going *anywhere on the field*; 4th-and-1 at midfield = **+3.2 % win probability** | Model is below even the conservative human baseline, let alone EV-optimal |
| 3 | **FG range gate** | fixed `yardsToEndzone ≤ 45` → attempts to **62 yards**, kicker-blind. Kick *power* is never read; only `kickAccuracy` | 50+ yard attempts run **~130-155 per season league-wide** (≈ 0.3/team-game); real range varies 8-12 yards by kicker | **Kicker-blind range is the defect**, not the number |
| 4 | **FG make %** | 0-30: 95 · 31-40: 85 · 41-50: 70 · 51-55: 50 · 56+: 30 (`PlaySimulator.swift:2040-2051`), ×0.975 block | League **84-85 % at all distances since 2015**; 30-49 yd **> 85 %**; 50+ **58-64 %** | Model is **10-20 pp low** at every band ≥ 41 yards |
| 5 | **XP** | `0.90 + (acc−70)/300`, clamp 0.80-0.99 (`:2215`); no block, no weather | ≈ **94 %** since the 2015 33-yard snap | 4 pp low at average |
| 6 | **Two-point decision** | classic chart, `scoreDiffAfterTD ∈ {−16,−13,−11,−8,−5,−2,1,5}`, Q4 or last 2:00 of Q3 (`GameSimulator.swift:1335-1342`) | ≈ 0.22 attempts / team-game, ≈ 50 % converted | **Good.** Base conversion 0.47 at equal talent (`:2257`) is close to real |
| 7 | **Two-minute drill** | Q4 only, ≤ 120 s, margin < +7 (`PlaySimulator.swift:349`) | end-of-half drills are a standard, high-value part of every game | **End of the first half is not modelled at all** |
| 8 | **Two-minute warning** | `GameSimulator.twoMinuteWarning = 120` (`:29`) — **declared, never read anywhere in the repo** | an automatic clock stoppage | **Dead constant** |
| 9 | **Timeouts** | modelled in the coached game only (3/half, `LiveGameEngine.swift:163-190`); **the AI never uses one**; `GameSimulator` has no timeout concept | 3 per half; roughly doubles the snaps a trailing team gets on its last drive | **All 6 go unused in every simulated game** |
| 10 | **Clock management when ahead** | `mgmtPassBias` fires only at Q3+ **and** margin ≥ 7 (`:339-346`) | leading teams bleed clock from the moment they lead late | **A team up 3 with 2:00 left runs an 85 %-pass hurry-up** (`isTwoMinuteDrill` requires only margin < +7) |
| 11 | **Kneel-down** | `.kneel` is resolvable (`PlaySimulator.swift:2090`, 40 s) but **`decidePlayCall` never returns it** (`:450-469`). User has a button (`CoachedGameView.swift:1734`) | victory formation, universally | **The AI cannot end a game it has won.** 3 dropbacks at ~2.3 % INT ≈ 7 % chance of gifting it back |
| 12 | **Onside kick** | 12 % recovery (`GameSimulator.swift:38`), **human-only** (`:37`: *"quick sim never onsides"*) | **8.7 % (2018-2023)**; 4.23 % in 2023, 6.45 % in 2024; 13.5 % pre-2018 | Rate ~2× too generous; **a trailing AI down 5 with 0:40 left always kicks deep** |
| 13 | **Prevent defense** | real and shared (`DriveSimulator.swift:278-283`): Q4, ≤ 4:00, lead 1-16, ball outside the 25. Deep +0.14 / short −0.08 | matches practice | **Good** |
| 14 | **Red zone** | defence changes inside the **10**; pass depth forced short inside the **10**; **play selection has no red-zone branch at all** | red zone starts at the 20 and reshapes both play mix and defence | Threshold and scope both wrong |
| 15 | **Clock model** | flat draws (`DriveSimulator.swift:463-490`): run/completion 25-40 s, incompletion 4-8 s, kneel 40 s, spike 3 s | broadly right in the mean | No out-of-bounds, no 40-s play clock, no first-down stoppage, no hurry-up tempo |
| 16 | **Punting** | punter fetched at `PlaySimulator.swift:1976` **for the description string only**; `Int.random(in: 35...55)` at `:1977` is discarded — field position uses a flat `averagePuntDistance = 40` (`GameSimulator.swift:28, 1429`) | net punt avg ≈ 41.5 yds, with real punter spread | **Punter rating is cosmetic; punt variance is zero** |
| 17 | **Home-field advantage** (AI-vs-AI) | flat +3 pts → **58.8 % home win rate** after the tie-break rule | **53.2 %** (2019-2023); market HFA ~2.5 pts and falling | +5.6 pp, of which +4.2 pp is the `:984-987` tie-break |
| 18 | **League competitive balance** | sd of team wins **2.06**; corr(roster, wins) **= 0** | sd ≈ 3.0-3.2, strongly roster-driven | The standings are a random-number generator |

**Sources:** [TeamRankings 4th-down attempts/game](https://www.teamrankings.com/nfl/stat/fourth-down-conversions-per-game) · [NFL Draft Diamonds on the 2023 4th-and-1 gap (71.3 % converted, 48.6 % attempted)](https://nfldraftdiamonds.com/2025/04/fourth-down/) · [Sharp Football, FG trends by the numbers](https://www.sharpfootballanalysis.com/analysis/field-goal-trends-by-the-numbers/) · [NBC Sports / PFT on the post-2018 onside collapse](https://www.nbcsports.com/nfl/profootballtalk/rumor-mill/news/onside-kick-success-dropped-from-21-percent-to-6-percent-after-new-rule) · [Odds Shark onside-kick rates by season](https://x.com/OddsShark/status/1859048821285585165?lang=en) · [PFF on declining home-field advantage](https://www.pff.com/news/nfl-home-field-advantage-pff-data) · [ESPN NFL game-management cheat sheet](https://www.espn.com/nfl/story/_/id/33059528/nfl-game-management-cheat-sheet-punt-go-kick-field-goal-fourth-downs-plus-2-point-conversion-recommendations)

---

# PART 4 — THE IMPERFECTION MODEL

## 4.1 Inventory: every existing source of AI error or variance

| # | Source | File:line | Magnitude | Reach |
|---|---|---|---|---|
| 1 | **`DCPersona.misreadChance`** — a rolled counter targets the *wrong* tendency | `CoordinatorPersona.swift:88-94`, applied `LiveGameEngine.swift:1978-1983` | aggressive **0.18**, exotic **0.08**, **balanced 0.00, conservative 0.00** | **Coached games only** |
| 2 | Counter-share ceiling — the AI never counters every snap | `AdaptiveOpponentAI.swift:52, 72-74`; `LiveGameEngine.swift:1968-1972` | `min(0.60, max(0.10, (0.20 + 0.40·g) × personaMult))` | Coached only |
| 3 | Tendency threshold by grade — a weak DC keys late or not at all | `AdaptiveOpponentAI.swift:66-68` | grade 0 keys at ~0.50, grade 100 at ~0.30 | Coached only |
| 4 | Persona threshold shade | `CoordinatorPersona.swift:67-74` | −0.06 aggressive … +0.08 conservative | Coached only |
| 5 | Category EWMA α (ramp speed) | `AdaptiveOpponentAI.swift:816-820` | bounded 0.18-0.45 | Coached only |
| 6 | Scheme-pool randomness in counter selection | `AdaptiveOpponentAI.swift:305-325, 364-385` | `randomElement()` over an installed pool, signature entries double-weighted | Coached only |
| 7 | `coinFlip` on every play type | `PlaySimulator.swift:450-469` | the play mix itself | **All paths** |
| 8 | `HeatState` player form | `Engine/Match/HeatState.swift:25-45` | ±1.0 clamped; win/loss step 0.34, turnover 0.55, decay ×0.80/drive | Both engines (symmetric) |
| 9 | PA-bite roll | `PlaySimulator.swift:536-550` | `clamp(0.5 + (70 − boxAwareness)·0.02 + keyIntensity·0.4, 0.05, 0.95)` | Live calls only (nil hint ⇒ never) |
| 10 | Garbage-time edge damp | `PlaySimulator.swift:2922-2926` | scale → floor 0.35 at margin ≥ 21 | All play-by-play paths |
| 11 | AI-vs-AI score RNG | `WeekAdvancer.swift:8186-8214` | sd 11.09 pts/team — **but it is 100 % of the signal, not noise on top of one** | Path 3 |

**The honest summary of that table: the shipped game contains exactly one modelled AI *decision* error — row 1 — and it is zero for most coordinators.**

Working the numbers on row 1. For an aggressive elite DC (grade 100): counter share = `min(0.60, max(0.15, 0.20 + 0.40)) = 0.60`, times `counterShareMultiplier 1.3` = 0.78, clamped by `maxCounterShare` to **0.60**; of those, 18 % misfire → **10.8 % of AI defensive snaps carry a wrong call**. For a balanced grade-70 DC: share `0.20 + 0.40×0.70 = 0.48`, misread 0.0 → **0.0 % of its snaps are ever a mistake**.

And `DCPersona.derive` (`CoordinatorPersona.swift:52-62`) maps `base43 → {balanced, conservative}`, `tampa2 → conservative`, `cover3 → {conservative, balanced}`. **Three of the seven scheme buckets — covering the most common defensive systems — produce a coordinator with a literally zero error rate.**

`OCPersona` (`:333-517`) has **no `misreadChance` at all**. The AI offense never misreads the user's defensive tendency. It either reads correctly or declines to counter.

## 4.2 Where the AI is currently perfect or omniscient

1. **It never mismanages the clock — because it has no clock management to mismanage.** No timeouts (`LiveGameEngine.swift:175`), no kneel, no spike, no hurry-up tempo, no end-of-first-half drill. There is nothing to get wrong, which is a different failure from getting it right.
2. **The two-point chart is unconditionally EV-optimal.** `shouldGoForTwo` (`GameSimulator.swift:1335-1342`) is a lookup table with no coach term, no pressure term and no error rate. A 40-grade head coach in his first game executes the analytics chart perfectly, every time, forever.
3. **It reads `truePotential` — a number the user is explicitly denied.** `TrainingFocusEngine.autoAssignFocus` sorts candidates on `$0.truePotential > $1.truePotential` (`:296-300`). The user's screens show the noisy `assessedPotential` label instead; `UI/Roster/DevelopmentReportView.swift:9` states the rule outright — printing headroom *"hands the manager a number the"* engine deliberately hides. The AI's development desk is omniscient and the user's is not.
4. **`AdaptiveOpponentAI` reads the player's calls perfectly.** `Tracker.recordOffense` (`:199-205`) is fed the literal `OffensivePlayCall` after every snap with no misclassification, no sample noise, and no scouting-quality term. `tendency(of:)` (`:101-133`) is documented as deliberately exhaustive so that rotating same-family plays *cannot* hide a tendency. The only thing coach grade changes is *when* the read arms, never whether it is correct.
5. **The AI's field-goal decision is talent-blind in a way a real staff never is.** `fieldGoalRange = yardsToEndzone <= 45` (`PlaySimulator.swift:351`) with no kicker term, so every club in the league has an identical 62-yard range. Kick *power* is never read anywhere.
6. **`scoreDifferential` is stale, not noisy.** `GameSimulator.swift:249` samples it once per drive. That is an accuracy bug, not an imperfection model — it does not make the AI human, it makes it inconsistent.

**Where the AI is *not* omniscient, and correctly so:** `AIDraftPerception` gives AI front offices a fogged draft board (harness `perception` scenario), and personas are derived from public scheme + a stable id hash rather than from opponent knowledge. Those are the right patterns to extend.

## 4.3 Recommended imperfection model

The design constraint is stated in the brief and it is the correct one: *imperfection must not become a free win for the user.* Three rules make that hold.

- **Rule A — imperfection is structured bias, not symmetric noise.** A conservative coach should punt in one identifiable class of situation, not add Gaussian jitter to every decision. Symmetric noise is EV-neutral in expectation but variance-positive, and the user, who plays 17 games a season against 17 different opponents while each opponent plays him once, harvests variance far more efficiently than they do.
- **Rule B — every new AI error must have a matching user error path or a matching user cost.** If the AI mismanages the clock, the user must be able to as well (he already can — he simply chooses not to). If the AI misreads a tendency, the user's own coordinator recommendation should misread too.
- **Rule C — apply it to *both* sides of the ball and *all* 32 clubs, or it is a subsidy.** This is the failure mode already shipped in §2.1 and §2.2.

### 4.3.1 Head-coach persona — the missing piece (attach: new `HCPersona` in `CoordinatorPersona.swift`)

`Coach` (`Domain/Models/Coach/Coach.swift:24-37`) has `playCalling`, `adaptability`, `gamePlanning`, `discipline`, `motivation`, `moraleInfluence` — and **no risk-tolerance field**. Do not add one. Derive it exactly the way `DCPersona.derive` (`CoordinatorPersona.swift:52-62`) already does, from public signals plus `stablePersonaPick(id:)` (`:31-35`), so there is no schema migration and the persona is stable for the life of the coach:

```
HCPersona ∈ { riverboat, modern, orthodox, punter }
derive: adaptability + playCalling above/below 70, tie-broken by stablePersonaPick(coach.id)
```

Give it three fields, mirroring the existing persona pattern:

| field | riverboat | modern | orthodox | punter |
|---|---:|---:|---:|---:|
| `fourthDownAggressiveness` | 0.85 | 0.60 | 0.40 | 0.15 |
| `twoPointBias` (chart-row shift) | +1 | 0 | 0 | −1 |
| `clockErrorRate` | 0.10 | 0.15 | 0.25 | 0.35 |

**Attachment point:** `PlaySimulator.decidePlayCall:409, 426` already has the two `if let plan` branches. Change nothing about them except the *source* of the value — pass the AI's `HCPersona.fourthDownAggressiveness` in the `gamePlan:` slot instead of `nil` at `WeekAdvancer.swift:1372-1373`, `:7296-7297` and `LiveGameEngine.swift:1789`. **This is a one-line-per-call-site change that simultaneously fixes the §2.1 asymmetry and creates the coach-driven 4th-down spread.** A `punter` HC at 0.15 punts on 4th-and-2 from the opponent's 40; a `riverboat` at 0.85 goes for it on 4th-and-3 past midfield. Both are recognisably real coaches.

### 4.3.2 Clock-management error scaled by coach and pressure (attach: `PlaySimulator.decidePlayCall:338-350`)

Three concrete defects to fix and one error to add:

1. Extend `isTwoMinuteDrill` to `quarter == 2 || quarter == 4` — the end-of-half drill is simply missing.
2. Change the leading-team gate from `scoreDifferential < gameMgmtLeadPts` (7) to a possession-aware test, so a team up 3 with 2:00 left stops calling an 85 %-pass hurry-up.
3. Make `decidePlayCall` able to return `.kneel` when leading and the opponent cannot get the ball back — the resolution already exists at `PlaySimulator.swift:2090`.
4. **Then** gate step 3 on `HCPersona.clockErrorRate` scaled by leverage: `errorChance = clockErrorRate × (1 + leverageIndex)`, using the `leverageIndex` that already exists at `PlaySimulator.swift:3581-3583`. A `punter` HC in a one-score fourth quarter fails to take the knee ~50 % of the time and hands the game back. That is both an error *and* correct football history.

### 4.3.3 A misread channel for the AI offense (attach: `CoordinatorPersona.swift:333`, mirroring `:88-94`)

Add `OCPersona.misreadChance` and apply it at `LiveGameEngine.swift:2018-2025` exactly as the DC's is applied at `:1978-1983` — pick a *wrong* `DefenseTendency` and counter that instead. Suggested: `airRaid 0.15`, `groundAndPound 0.05`, `westCoast 0.08`, `balanced 0.05`. Because the counter acts purely through existing package modifiers (`AdaptiveOpponentAI.swift:281-283`), a wrong counter is automatically a bad-but-legal call, with no new balance surface.

### 4.3.4 Give the "zero-error" personas a floor (attach: `CoordinatorPersona.swift:88-94`)

`conservative` and `balanced` at `misreadChance = 0.0` is the single most anti-realistic constant in the file — it says a Tampa-2 coordinator has never once guessed wrong. Set a floor of ~0.05 for both, and scale the whole thing by coordinator grade so a 40-grade DC misreads more than a 90-grade one:

```
effectiveMisread = basePersonaMisread + max(0, (70 − dcGrade) / 100 × 0.15)
```

At grade 40 that adds +0.045; at grade 90 it adds 0. Coach quality then buys *fewer mistakes*, which is what coach quality actually buys.

### 4.3.5 Timeouts and onside for the AI (attach: `GameSimulator`/`DriveSimulator`, and `LiveGameEngine.swift:179`)

Both are currently structural user-only advantages (§2.6). The minimum honest fix is a rule-based AI user with a persona-scaled error rate:

- **Timeouts:** trailing, ≤ 2:00, opponent has the ball, 3rd/4th down → burn one, with a `clockErrorRate` chance of not doing it. Requires threading a timeout counter through `DriveSimulator`, which today has no concept of one.
- **Onside:** trailing by ≤ 8 with < 2:00 left, or by any margin with < 0:30 → attempt, using the existing `onsideKickRecoveryChance`. **Lower that constant from 0.12 to ~0.08** first — 12 % is roughly double the 2018-2023 reality of 8.7 % and well above 2023's 4.23 %.

### 4.3.6 Guardrails so none of this becomes a free win

1. **Measure the balanced-control invariant first.** The `spam` scenario's mixed-parity line (`Δypc +0.01`, `ΔpassEV +0.11`) is the existing proof that an adaptive change did not tax ordinary play. Every item above needs the same before/after check, plus a `fullgame --home-tier 70 --away-tier 70` run to confirm points/team stay put.
2. **Cap aggregate AI error per game.** Mirror `passTotalMalusCap` / `runGrandBiteCap` (`AdaptiveOpponentAI.swift:794-796`): a per-game budget of at most ~2 decision errors per AI coach, so a bad-luck seed cannot cascade into a 60-point blowout.
3. **Errors must be symmetric across the ledger.** A "mistake" that only ever costs the AI points is a difficulty slider wearing a costume. Roughly half of `clockErrorRate` outcomes should be *over*-aggression (going for it when the chart says kick, burning a timeout early) that occasionally *helps* the AI.
4. **Do not add any of it until §5 items 1-3 are fixed.** Adding realistic coaching error to a league where 15 of 16 games are decided by dice is decorating a room with no floor.

---

# PART 5 — RANKED VERDICT

Ranked by how much each item distorts the game the user is actually playing.

| # | Finding | Target | Type |
|---|---|---|---|
| **1** | **AI-vs-AI games are roster-blind dice.** `randomTeamScore(homeAdvantage:)` takes one `Int` and no team. 15 of 16 games each week, all playoff games the user is not in, the Pro Bowl and preseason. sd of team wins **2.06** vs a real ~3.0, and corr(roster, wins) = **0**. Every AI front-office system in this audit is unfalsifiable because of it. | `WeekAdvancer.swift:8186-8214`, called `:1383`, `:7324`, `:3065`; `PreseasonEngine.swift:729` | **Design change** (a rating-aware Elo/Pythagorean score model would cost microseconds and fix the standings) |
| **2** | **Opponent prep is a user-only +4.2-point-per-game scoreboard edit** — worth ≈ **+2.1 wins/season** — and its designed cost lands in `physical.stamina`, which **no simulator file reads**. | Benefit: `GameSimulator.swift:519-538` ← `OpponentPrepEngine.swift:15-21` ← `WeekAdvancer.swift:1341-1357`. Dead cost: `WeekAdvancer.swift:8560-8567` | **Bug fix** (the dead counterweight) + **design change** (the boost should thread through the sim, and AI clubs should have prep) |
| **3** | **The game plan is hard-coded `nil` for all 31 AI clubs**, in the regular season, the playoffs and coached games. `fourthDownAggressiveness` and `runPassRatio` are structurally user-only levers. | `WeekAdvancer.swift:1372-1373`, `:7296-7297`; `LiveGameEngine.swift:1789` | **Design change** — and §4.3.1 fixes it and the 4th-down realism gap in the same edit |
| **4** | **The AI's 4th-down go rate is 6-10× too conservative** (≈ 0.2 vs **1.47** attempts/team-game) and structurally **zero** between the opponent's 6-yard line and midfield. It also never goes for it while leading by 7+, even on 4th-and-goal from the 1. | `PlaySimulator.swift:397-436` (the `:402` early return; the dead `:409`/`:426` branches) | **Design change** |
| **5** | **The AI cannot kneel, cannot call a timeout, and cannot onside-kick** — the three most basic acts of endgame management, all available to the user via `CoachedGameView`. A leading AI offense runs an **85 %-pass hurry-up** while up 3 with 2:00 left and gifts the game back ~7 % of the time. | `PlaySimulator.swift:349-350, 450-469`; `LiveGameEngine.swift:175`; `GameSimulator.swift:37` | **Bug fix** (the up-3 hurry-up is plainly wrong) + **design change** (the three missing capabilities) |
| **6** | **Exactly one AI decision-error source exists in the shipped game**, it is coached-games-only, and it is `0.0` for `balanced`/`conservative` DCs (≈ 40 % of coordinators) and for **every AI offense in the league**. Coach quality never changes a single situational decision — only execution quality. | `CoordinatorPersona.swift:88-94`; no `misreadChance` on `OCPersona` at `:333` | **Design change** — §4.3.3, §4.3.4 |
| **7** | **The AI reads `truePotential`, which the user is explicitly denied.** The AI development desk picks the three genuinely-highest-ceiling young players every week; the user sees a noisy label. | `TrainingFocusEngine.swift:296-300` vs `UI/Roster/DevelopmentReportView.swift:9` | **Design change** (route the AI through a fogged read, as `AIDraftPerception` already does for the draft) |
| **8** | **The tie-break rule silently manufactures home-field advantage.** 4.19 % of AI-vs-AI games land on an exact tie and `return (homeScore + 1, awayScore)` hands every one to the home side, lifting the home win rate from 55.2 % to **58.8 %** against a real **53.2 %**. | `WeekAdvancer.swift:984-987` | **Bug fix** |
| **9** | **The user's depth chart never reaches the engine**, and injured players dress and play for both sides. Both paths field `max by overall`. | `GameSimulator.swift:130-131, 1885-1886`; `MatchupResolver.swift:26-87`; `Career.depthChartData` has zero engine readers | **Bug fix** (the UI promises a system that does not exist) |
| **10** | **Field-goal range is kicker-blind** — every club attempts 62-yarders — and make rates are **10-20 pp below the modern NFL** at every band ≥ 41 yards. Kick *power* is read nowhere. | `PlaySimulator.swift:351` (gate), `:2040-2051` (table) | **Design change** (gate) + **bug fix** (the table drifted from a modern league) |
| **11** | **`offensiveAggression` is a slider nobody reads**, and `GameSummaryView.swift:386` prints a post-game line describing its effect. `blitzFrequency` / `defensiveAggression` reach only the coached path. | `GamePlan.swift:10`; `UI/Match/GameSummaryView.swift:386`; `LiveGameEngine.swift:1821-1830` | **Bug fix** (UI copy vs engine behaviour) |
| **12** | **Punter rating is cosmetic.** `simulatePunt` fetches the punter for the description string and rolls `35...55` yards which is then discarded — field position uses a flat 40. | `PlaySimulator.swift:1976-1978`; `GameSimulator.swift:28, 1429` | **Bug fix** |
| **13** | **`GameSimulator.twoMinuteWarning = 120` is declared and never read**, anywhere in the repo. The two-minute drill itself never fires at the end of the first half. | `GameSimulator.swift:29`; `PlaySimulator.swift:349` | **Bug fix** |
| **14** | **The AI never adapts across games or seasons.** `PlayMemory`/`RunKeyState` are explicitly never persisted; personas are a UUID hash fixed for a coach's career. There is no film study, no week-over-week scouting. | `AdaptiveOpponentAI.swift:523-524, 599`; `CoordinatorPersona.swift:31-35` | **Design change** |
| **15** | **Full-game play selection runs hot.** At the engine's own 70-vs-70 calibration point the shipped situational AI produces net YPA **8.4**, 3rd-down **50 %** and **29** points/team — all out of band — while plays and completion sit in band. The README's own diagnosis: *"pure play-selection."* | `PlaySimulator.decidePlayCall:450-469`; `tools/balance-harness/README.md` §Round-5 | **Design change** |

**What is genuinely good and should not be touched:** the `AdaptiveOpponentAI` three-layer design and its fairness caps (measured: spam collapses to 43 % of first-call value, mixed callers move ±0.01 ypc); the two-point chart; the prevent-shell rule; `CoachingModifiers`' symmetric, centred coefficients; the practice-squad and training-focus weekly passes; and the balance harness itself, whose anti-drift construction is the reason every number in Part 1 could be trusted.
