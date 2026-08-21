# AI Roster Decisions — Draft & Free Agency Brain: Implementation Audit and Imperfection Design

**Scope:** read-only analysis of `/Users/jtvaris/workspace/projects/Dynasty`. Engine under `dynasty/dynasty/Engine`, war room under `dynasty/dynasty/UI/Draft`, market under `dynasty/dynasty/UI/FreeAgency`.
**Date:** 2026-08-21. **Branch:** `feat/skeletal-mocap-players` @ `3423d35`.
**Deliverable:** assessment + a recommended imperfection model. No code changed.
**Measurement:** `tools/balance-harness` `perception` scenario, run read-only at `--drafts 12` (12 drafts × 224 picks, class 350, 32 clubs). Repo smoke figures quoted from `TODO.md:140-180`.

---

# PART 1 — THE DRAFT BRAIN

## 1.1 The map: every path an AI pick can be made

| # | Path | File:line | Live? |
|---|------|-----------|-------|
| 1 | War room, AI on the clock | `UI/Draft/DraftDayCoordinator.swift:1214-1226` (`aiMakePickForCurrent`) → `Engine/Draft/DraftEngine.swift:161` | **Yes** — every AI pick the user watches |
| 2 | War room, AI clock expiry | `DraftDayCoordinator.swift:1209` | **Yes** |
| 3 | Debug/smoke fast-forward | `Engine/Simulation/MultiSeasonSmokeTest.swift:486`, entered from `UI/Career/CareerDashboardView.swift:3012` | DEBUG only |
| 4 | Pre-built event stream | `Engine/Draft/DraftEventEngine.swift:129` | **Dead.** The file's own header (`:29-36`) says "⚠️ NOT WIRED". 229 lines, zero callers |
| — | Balance harness control arm | `tools/balance-harness/driver/PerceptionScenario.harness.swift:179` | measurement only |

The user's *own* expired clock does **not** run `aiMakePick` — it runs `UserDraftBoard.autoPick` off his persisted board (`DraftDayCoordinator.swift:1182-1209`). That is correct and deliberate (#207): the clock must not file a card off a number the user cannot see.

There is exactly **one** AI pick function. `FantasyDraftEngine.aiPickIndex` (`Engine/Draft/FantasyDraftEngine.swift:9,115`) is a separate scorer for the fantasy-draft league-creation mode and is explicitly "modeled on" `aiMakePick` rather than sharing it — a second brain that can drift.

### Dead code found in the draft path

| Symbol | File:line | Lines | Callers |
|---|---|---|---|
| `DraftEventEngine.makeStream` (whole file) | `Engine/Draft/DraftEventEngine.swift` | 229 | 0 (self-documented) |
| `DraftEngine.generateStaffRecommendations` | `Engine/Draft/DraftEngine.swift:1114-1213` | 100 | **0** |
| `DraftEngine.generateFanReaction` | `Engine/Draft/DraftEngine.swift:1233-1301` | 69 | **0** |
| `DraftEngine.gradeForPositionGroup` | `Engine/Draft/DraftEngine.swift:1305-1314` | 10 | only the two dead functions above |

`generateStaffRecommendations` matters beyond its line count: its "Chief Scout's sleeper pick" sorts the board by **`prospect.truePotential`** (`DraftEngine.swift:1195`) and hands the user the name. If it were ever wired, the user's own staff would be pointing at hidden truth — a fog breach in the user's favour, sitting armed in the codebase.

## 1.2 The scoring function, term by term, in OVR points

`DraftEngine.aiMakePick` (`:161-300`) is an **additive** score, deliberately (the `:120-141` note documents the multiplicative predecessor and the 93 %-premium-position round 1 it produced). Constants at `:199-207`:

| Term | Formula | File:line | Realised range |
|---|---|---|---|
| Talent | `perceivedOverall + 0.15 × perceivedPotential` | `:257` | ≈ 70 … 99 (span **≈ 29**) |
| Roster deficit | `5.0 × max(0, multiplier − 1)` | `:261` | 0 … **+5.25** (CB, empty room); typical **0 or +0.75** |
| Positional value | `(weight − 0.8) × 8.0` | `:267` | **−1.6 … +1.6** |
| Specialist discount | `−8.0` when `weight ≤ 0.35` | `:268` | 0 or −8.0 (K/P only, so K/P sit at −12.0) |
| QB premium | `+2.0` when QB deficit multiplier > 1.2 | `:275-277` | 0 or +2.0 |
| Public consensus anchor | `12.0 × exp(−consensusSlot / 64)` | `:283` | **0.17 … 11.81** |

Then a top-4 weighted-random draw, `[0.65, 0.20, 0.10, 0.05]` (`:292-299`).

### What the arithmetic actually says

**The AI is a consensus follower with a fogged talent read, not a need drafter.**

- The consensus anchor is the largest non-talent term by a factor of ~2. A prospect the media mocks at #1 gets **+11.81**; one projected in round 3 (band centre slot 80) gets **+3.44**; a round-7 man gets **+0.46**. That 11.4-point spread dwarfs everything else.
- The whole positional-value opinion is **±1.6 points, 5.5 % of the talent span**. A quarterback is worth 3.2 points more to an AI club than a running back of identical grade — about two thirds of one letter grade.
- Need is near-inert on a normal board. `teamNeedComponents` (`:1364-1425`) uses ideal counts summing to **48** against rosters that leave free agency at **46** (`FreeAgencyEngine.faRosterCeiling`, `:1124`), so most positions carry a deficit of 0 and contribute exactly 0.
- **The quality half of the need model is a rounding error.** `multiplier += 0.2` when a position group averages under 60 OVR and `+= 0.1` under 70 (`:1401-1403`) — worth **+1.0 and +0.5 board points** after `deficitPoints`. A club whose entire cornerback room grades 55 values that hole *less* than a club that is two bodies short at fullback (2 × 0.15 × 5.0 = +1.5). That is backwards and it is a bug, not a taste.

### Sensitivity: how much does one point of read error move a pick?

d/ds of the consensus term at slot 16 (the round-1 band centre) is `−12/64 · e^(−0.25) = −0.146` points per slot. So **1 OVR point of misread ≈ 6.8 slots of consensus-equivalent board movement in round 1**. At the balanced archetype's σ = 4.5 that is ±31 slots — which is why the measured mean `|pick − publicRank|` in round 1 is 26.0 (§1.5).

## 1.3 The information question — SETTLED, and the docs have not caught up

**The AI does not draft off true ratings.** `AIDraftPerception` (`Engine/Draft/AIDraftPerception.swift`) is real, wired, and measured.

Every AI board read goes through `AIDraftPerception.read` (`DraftEngine.swift:236-244`, lens hoisted at `:178`). The model:

- **Gaussian error by GM archetype** (`AIDraftPerception.swift:60-67`): σ = 3.0 analytics / 4.5 balanced / 5.0 aggressive / **6.0 old-school**, +1.0 on the ceiling read (`:72`).
- **Fat tail**: 7 % of `(team, prospect)` pairs get an extra ±8-14 OVR in the same direction on both numbers (`:76-80`, applied `:163-170`).
- **Deterministic per pair**, seeded off a SplitMix64/xxHash fold of the two UUIDs, explicitly *not* `hashValue` (`:184-196`). The same front office misjudges the same man the same way at pick 3 and pick 190, across relaunches.
- Correlated ceiling read at ρ = 0.5 (`:84`).

**Measured** (`perception`, 12 drafts, n = 110 208 pair reads):

```
oldSchool   mean |perceived − true|  5.25 OVR   (≥8 off on 21.6 % of prospects)
balanced                             4.08       (≥8 off on 12.0 %)
analytics                            3.01       (≥8 off on  6.5 %)
aggressive                           4.46       (≥8 off on 15.2 %)
LEAGUE                               3.96       fat tail fired on 6.99 % (target 7 %)
determinism: repeat read identical = true
```

**The public board is also wrong.** `DraftClassBuilder.consensusError` (`Engine/Scouting/DraftClassBuilder.swift:251-279`) applies σ = 5.0 plus the same 7 % / ±8-14 fat tail to `draftProjection`, per `(careerID, prospectID)`. So the anchor the AI leans on is itself noisy, and identically noisy for all 32 clubs — correct, because a consensus is public.

**The user's information, for comparison.** `ScoutingEngine.generateScoutReport` (`Engine/Scouting/ScoutingEngine.swift:204-227`) gives `scoutedOverall = trueOverall + U(−e, +e)` where `e = max(2, 15·(1 − accuracy/100)) − bonuses`, bonuses being +3 position specialisation and +15 focus position (`:214-220`). A 70-accuracy scout: e = 4 → mean |error| **2.0**. With a focus position: e = 1 → mean |error| **0.67**. A 50-accuracy scout: e = 7 → mean |error| 3.5. Display is then quantised to a `GradeRange` — `LetterGrade` bands are 5 OVR wide (`Domain/Models/Scouting/LetterGrade.swift:41-56`), one report opens a ±2-grade band (`ProspectFog.swift:228-230`), three reports narrow to a single grade.

**Verdict on the information question:** the user is **not** structurally disadvantaged. On a man he has actually scouted his read is *sharper* than any AI club's (mean |err| 0.67-3.5 vs the league's 3.96), and coarsened only by 5-point letter banding. The asymmetry is **coverage, not accuracy**: he gets 25 paid evaluations per cycle (`ScoutEvaluationBudget.slotsPerCycle`, `UI/Scouting/ProspectDetailView.swift:26`) against a 350-man class, plus the combine trip, the pro-day tour and the inherited top-250 baseline. That is the right shape — a real GM has a sharper opinion on the 25 men he worked out and the same public board as everyone else on the rest.

**But the code says otherwise in two places, and both are load-bearing documentation:**

- `UI/Draft/Components/ProspectFog.swift:24-26`: *"`trueOverall` never reaches a view again. **The AI keeps drafting on the true values internally** (`DraftEngine.aiMakePick`, `DraftDayCoordinator`'s pick grades) — this is a user-information change, not a nerf to pick quality."* This is **false** as of the current tree and is the single most misleading comment in the draft path. A reader auditing fairness would conclude the opposite of the truth.
- `Engine/Draft/DraftEngine.swift:1195` — the dead sleeper-pick sorter reads `truePotential` (§1.1).

**One real fog breach survives in a live path**: `DraftEngine.draftGrade` boosts the published pick grade by a full letter when `prospect.trueOverall >= 80` (`DraftEngine.swift:1026`). The grade the user is shown for his own pick is partly computed from a number he is never allowed to see.

## 1.4 Positional value vs the real market

The game holds **two** positional-value tables and they disagree.

| Position | Draft board `positionalWeight` (`DraftEngine.swift:1413-1420`) | Money `positionMultiplier` (`ContractEngine.swift:453-524`) | Money as ratio to QB |
|---|---:|---:|---:|
| QB | 1.0 | 2.20 | 1.00 |
| WR | 1.0 | 1.30 | 0.59 |
| DE (edge) | 1.0 | 1.25 | 0.57 |
| CB | 1.0 | 0.95 | 0.43 |
| LT | 1.0 | 1.05 | 0.48 |
| DT | 0.8 | 1.00 | 0.45 |
| OLB | 0.8 | 1.00 | 0.45 |
| MLB | 0.8 | 0.80 | 0.36 |
| FS/SS | 0.8 | 0.75 | 0.34 |
| TE | 0.8 | 0.70 | 0.32 |
| **RT** | **0.6** | **0.85** | 0.39 |
| LG/C/RG | 0.6 | 0.65 | 0.30 |
| RB | 0.6 | 0.60 | 0.27 |
| **FB** | **0.6** | **0.25** | 0.11 |
| K/P | 0.3 | 0.25 | 0.11 |

Three problems:

1. **The draft table is far too flat.** Real 2025 top-of-market APY: QB **$60.0M** (Dak Prescott), EDGE **$50.0M** (Will Anderson Jr., 3 yr/$150M), WR **$40.25M** (Ja'Marr Chase), CB **$30.1M** (Sauce Gardner), RB **$20.6M** (Saquon Barkley) — a QB:RB ratio of **2.9 : 1**, and the game's own money table agrees at **3.67 : 1**. The draft board prices that same gap at **1.0 : 0.6**, delivered as a **3.2-point** tilt on a 29-point talent scale. In OVR-point currency the game says a franchise quarterback is worth about **two thirds of a letter grade** more than a running back.
2. **Two rungs are inverted against the game's own money.** RT is paid 0.85 (above MLB 0.80, S 0.75, TE 0.70) but drafted at 0.6 — below all three. FB is paid 0.25 (bottom tier, same as a kicker) but drafted at 0.6 — the same as a right tackle. These are the classic "two constants that were supposed to be equal and drifted" pair: `FreeAgencyEngine.holePriority` (`:1083-1091`) is a *third* copy of the same 1.0/0.8/0.6/0.3 tiering, and its doc explicitly says it "mirrors `DraftEngine.teamNeedComponents`" — so the drift is now replicated into free agency.
3. **The specialist discount does the heavy lifting instead.** `−8.0` on top of `−4.0` (`:268`) is 5× the entire QB-vs-RB spread. The one positional statement the AI makes emphatically is "do not draft a kicker".

## 1.5 Does the AI reach, panic, over-draft, or fall for a workout warrior? — measured

From the `perception` scenario (12 drafts × 224 picks; "reach" = a round-1 pick ≥ 8 slots below the man's slot on the **true** board; "steal" = any pick ≥ 20 slots above it):

```
              R1 reaches    steals      true-BPA slid past pick 5   R1 mean |rank−pick|
fog OFF       8.33/draft    38.42       8 % of drafts               7.88
fog ON       13.25/draft    65.92       25 % of drafts             16.78

vs THE PUBLIC BOARD                mean |pick − publicRank|   R1     R2     R3    p90
fog OFF                                      34.9            19.2   35.6   49.9   85
fog ON                                       43.4            26.0   47.8   56.3  116
  taken >20 slots AHEAD of the media on 40 % of R1-3 picks (n = 1152)
```

- **Reaches: 13.25 of 32 round-1 picks — 41 % of the first round is a ≥8-slot reach off the true board.** With the fog switched off that is still 8.33 (26 %), so roughly **⅔ of reaching comes from the fog** and ⅓ from the need/consensus/positional terms plus the top-4 draw.
- **Steals: 65.92 per draft = 29.4 % of all 224 picks** are ≥20 true-board slots of value. Fog nearly doubles this over the control arm (38.42).
- **The true best player available slides past pick 5 in 25 % of drafts.** That is the top-10 bust generator working.
- **Panic is not modelled.** Nothing in `aiMakePick` reads how many picks have gone at a position, how long the club has been on the clock, or what the club just lost in free agency. There is no run-chasing, no "the third quarterback just went so we take ours now". `DraftEventEngine` detects position runs (`:170-180`) and is dead code.
- **Over-drafting a stocked position is possible but unmotivated.** Because the score is additive, a club with no deficit contributes 0 from need and simply takes the best perceived man — so it *can* take a fifth receiver, but only if he really is the top of its board. There is no house preference, no scheme fit, no "we always take the big corner".
- **Workout warriors: not modelled on the AI side at all.** `aiMakePick` never reads a combine number, a 40 time, height/weight, or `nflReadiness`. The only route by which testing numbers reach an AI board is indirectly, through the media consensus — `ScoutingEngine.applyProjectionDrift` moves `draftProjection` after the combine (`WeekAdvancer.swift:3504, 4280, 4677, 5072`), and the AI's consensus term chases it. That is a genuine mechanism but it is second-hand and it applies identically to all 32 clubs. **No individual AI club has a trait bias.**

### The AI's round 1 by position vs the real first round

```
fog ON, R1:   CB 20 %   WR 13 %   DE 11 %   QB 9 %   DT 8 %   OLB 8 %   (rest 31 %)
```

CB 20 % is **6.4 corners per first round**. QB 9 % is **2.9 quarterbacks** — against a real 15-year average of **about three per first round**, but with none of the real variance (1 in 2022, 2 in 2025, a record-tying 6 in 2024). The game's QB count is right on average and far too stable, because nothing in the model produces a quarterback run.

---

# PART 2 — THE FREE-AGENCY BRAIN

## 2.1 The map: two markets, one league

| Path | File:line | When | Who runs it |
|---|---|---|---|
| **Interactive rounds 1-6** | `FreeAgencyEngine.generateAIOffers` (`:2758`) → `processBiddingWars` (`:3034`) → `resolvePlayerDecision` (`:3228`), driven by `UI/FreeAgency/FAWeeklyView.swift:1808-1994` | the six FA days the user plays | 31 AI clubs bid; the user is a 32nd bidder |
| **Bulk market** | `FreeAgencyEngine.simulateAIFreeAgency` (`:2334`) via `simulateRemainingFAOnce` (`:863`) | the skip button (`FAWeeklyView.swift:2076`) and `WeekAdvancer.swift:3668` mop-up | AI vs AI only |
| **Own-core retention** | `resignAIOwnCore` (`:1526`) inside `executeNewLeagueYear` (`:566`) | rollover, before expiry | 31 AI clubs, 3 + 2 slots each |
| **Fifth-year options** | `settleFifthYearOptions` (`:2188`) | rollover | AI included |
| **Franchise tag** | `ContractEngine.applyFranchiseTag` | — | **user only** (`UI/Contracts/FranchiseTagView.swift:673`, `UI/FreeAgency/FinalPushView.swift:1342`) |
| **UDFA market** | `UDFAMarketEngine.postAIOffers` (`:1050-1110`) | draft exit → OTAs | 31 AI clubs; the user's board is **NOT WIRED** (`:190-197`) |
| **In-season refill** | `WeekAdvancer.refillAIRosters` | weekly | veteran-minimum churn |

Two markets means two pricing paths, and they are not the same:

- Bulk: `settlement = floor + (ask − floor) · U^(1/lean)` (`:2601-2602`). **The AI can never exceed the agent's opening ask.**
- Interactive: `rawOffer = ask × needFactor × U(0.85·agg, 1.05·agg + 0.05)` (`:2953-2956`). **The AI can exceed the ask, by up to 2.36×.**

The same club, in the same league year, is a different negotiator depending on whether the user pressed "skip".

## 2.2 Who bids, on whom, how much

**Ordering** (`:2347`): `marketAppeal` — `overall − min(14, 3.2·(age−25)) + 0.45·(potential − overall)` if `yearsPro ≤ 4` (`:1238-1249`). Derivation is documented at `:1145-1216` and is one of the better-argued constants in the repo.

**Eligibility** (`:2513-2527`): `availableCap − 0.15·cap − holeReserve ≥ askingPrice`, plus `rosterSize < 46`.

**Shortlist**: clubs with any need at the position, ranked; if nobody has a need, the whole league is the fallback (`:2544-2556`). Winner is a roulette-wheel draw (`:2570-2596`) weighted by:

| Factor | Range | File:line |
|---|---|---|
| Coach development appeal | ~1.0 | `:2573` |
| `needWeight` | **0.25 … 3.0** | `:1282-1289` |
| `topNeedBonus` | ×1.5 | `:1306` |
| Stance lean (contender vs rebuilder) | ×[0.769, 1.30], effectively only 0.72→0.769 bites | `:1331-1335` |

**Money in the interactive path** (`:2937-2971`):
- `needMultiplier`: critical **1.3-1.5**, high 1.1-1.3, moderate 0.95-1.1, none 0 (`:2735-2742`)
- × 1.10 if a top-5 deficit position, × stance lean (≤1.30)
- × `U(0.85·agg, 1.05·agg+0.05)`, `aiAggression` = 1.0 / 0.85 / 0.7 / 0.5 / 0.35 / 0.2 by round (`Domain/Enums/FreeAgencyStep.swift:24-33`)
- clamped to **30 % of spendable room** (`:2966`)

Round-1 expectation for a critical, top-5 need: `1.4 × 1.10 × 0.975 = 1.50 × ask`. Worst case `1.5 × 1.10 × 1.30 × 1.10 = 2.36 × ask`. **The AI *does* overpay in the first 48 hours** — this is the one place the model already does something a real GM does.

## 2.3 Cap discipline — the AI is structurally incapable of cap trouble

This is the largest realism gap in the FA brain, and it is over-determined by four independent mechanisms:

1. **Hard 15 % reserve on every signing door.** `capReservePercent = 0.15` (`:1143`). Enforced at bid time (`:2906`), at bulk eligibility (`:2520`) *and* at the signing door (`signFreeAgentAI`, `:919`). An AI club cannot end free agency below 15 % room. Ever.
2. **Dead money is wiped annually.** The league-year true-up rebuilds `currentCapUsage` from the sum of rostered `annualSalary` (`:713-720`). Every cut, every trade, every accelerated proration ages off in one league year. The doc at `:691-711` says so explicitly and calls it a placeholder "until a per-year dead-cap ledger exists".
3. **Cap growth is unconditional.** `Double.random(in: 0.05...0.08)` applied to all 32 clubs every rollover (`:686-689`).
4. **There is no salary floor.** `CapManagementEngine.isAboveSalaryFloor` and `.amountBelowFloor` implement the NFL's 89 % rule (`Engine/Contract/CapManagementEngine.swift:857-889`) and have **zero callers anywhere in the repo**. Nothing forces a club to spend.

**Measured consequence** (`TODO.md:149, 172`, 4-season smoke, two runs):

```
capRoom  34.4 → 40.3 → 32.9 → 25.3 %   (32/32 under the cap every season)
capRoom  30.3 → 39.2 → 32.3 → 23.1 %   (31/32 in 2028, worst club −0.2 %)
payroll  70.9 → 64.5 → 72.2 → 79.8 % of cap
```

The league carries a mean of **23-25 % of the cap unused** and spends **64.5-79.8 %** of it. The real NFL's CBA requires **89 % cash spend** over each four-year period; the 2025 cap was **$279.2M** and all 32 clubs had to be compliant by 4 p.m. on 12 March 2025 — several (New Orleans most notoriously) entered March tens of millions in the red and had to restructure and cut their way out. In this game **that has never happened and cannot happen**.

The one AI cap lever that *is* wired is restructure-only self-healing (`CapManagementEngine.selfHealCapCompliance:1222`, called from `FreeAgencyEngine.swift:750` and `WeekAdvancer.swift:884`), and its own header (`:1214-1218`) says it "buys legality, never spending power" — it stops at `availableCap == 0`, still far under the 15 % reserve.

### More dead code in the cap path

Every one of these has **zero callers** outside its own file:

| Symbol | File:line |
|---|---|
| `CapManagementEngine.calculateCapRollover` (both overloads) | `:19, :29` |
| `CapManagementEngine.processCompensatoryPicks` | `:49` (the live one is `CompensatoryPickEngine.applyAwards`) |
| `CapManagementEngine.calculateDeadCap` (both overloads) | `:106, :112` |
| `CapManagementEngine.applyCapGrowth` | `:806` (growth is hand-inlined at `FreeAgencyEngine.swift:686-689`) |
| `CapManagementEngine.projectedCapSpace` (both) | `:824, :830` |
| `CapManagementEngine.isAboveSalaryFloor` (both) | `:857, :864` |
| `CapManagementEngine.amountBelowFloor` (both) | `:875, :882` |
| `CapManagementEngine.canSelfHeal` | `:1123` |

That is ~120 lines of cap machinery, including the entire salary-floor model and the only dead-money calculator, sitting unreferenced.

## 2.4 Bidding wars: a mechanic that almost never fires, and a receipt for a price nobody paid

`processBiddingWars` (`:3034-3096`) requires `bids.count >= 4` (`:3043`). But bids are capped at `maxBidders = max(1, Int(aggression × qualityFactor × 6))` where `qualityFactor = (overall − 60)/40` (`:2982-2983`). Solving `aggression × (ovr−60)/40 × 6 ≥ 4`:

| Round | `aiAggression` | Minimum OVR for a bidding war |
|---:|---:|---:|
| 1 | 1.00 | **87** |
| 2 | 0.85 | **92** |
| 3 | 0.70 | **99** |
| 4 | 0.50 | 113 — **impossible** |
| 5 | 0.35 | 151 — impossible |
| 6 | 0.20 | 193 — impossible |

**Bidding wars are structurally impossible in rounds 4-6, and in round 3 require a 99-OVR free agent.** Against a league where the 90+ band is 1.7-3.1 % (`TODO.md:143`) and `resignAIOwnCore`'s star door keeps 80+-appeal men off the market (`ownCoreStarAppeal = 80.0`, `:1426`), the mechanic fires on a handful of players a decade.

Worse, when it does fire it produces a **false receipt**:

- The escalation affordability test is `team.availableCap >= escalatedPrice` (`:3057`) — **the 15 % reserve is not subtracted**, unlike every other cap test in the file. This is the one place a bid can be priced above the reserve.
- The signing door then refuses exactly that bid: `signFreeAgentAI` gates on `availableCap − reserve >= salary` (`:919`). `FAWeeklyView.swift:1895-1912` documents this race and handles it by leaving the man on the market.
- But `BiddingWarInfo.escalatedPrice` has already been written and is printed to the user verbatim: **`UI/FreeAgency/FARoundSummaryView.swift:127` — "Price escalated to ~$XM/yr"** — for a deal that may not have been struck, at a price nobody may have paid. `generateHeadlines` (`:3471-3484`) prints `bidderCount` from *before* the drop-outs.

## 2.5 Own core, tags, and the veteran door

`resignAIOwnCore` (`:1526-1719`) is the strongest piece of the FA brain. Two budgets per club:

- **Core**: 3 slots, `marketAppeal ≥ 72` (`:1415, :1421`), needs-gated unless `appeal ≥ 80` (`:1426`), priced at `0.95 × ask` (`:1431`) through the same `ContractNegotiationEngine.demand(.extend)` the user faces, with `demand.isRefusing` honoured (`:1670`).
- **Veteran door**: 2 slots, age ≥ 31 and raw OVR ≥ 76 and no successor within 4 OVR (`:1476-1508`).

Measured: **70 retentions per league year = 2.3 per club against a ceiling of 3** (`TODO.md:172`) at mean OVR 83.7, age 26.2. Saturated, as designed.

**No AI club ever franchise-tags anybody.** `ContractEngine.applyFranchiseTag` is reachable only from `FranchiseTagView` and `FinalPushView`. `settleFranchiseTags` (`:1924`) settles them league-wide, but only the user's ever exist. In the real NFL, 8-15 tags are applied league-wide every March.

## 2.6 Contract values vs the game's own engine and the real market

`ContractEngine.estimateMarketValue` (`:568-618`) is well-calibrated and its derivation is documented at `:380-452`: `basePercent(overall) × positionMultiplier × 0.75 (leagueAffordabilityScale) × cap`, with a QB-only scarcity floor over OVR 85-92 (`:576-579`). The header's own ratio audit — QB 1.00, WR 0.59 (real ~0.58), EDGE 0.57 (~0.67), OT 0.48 (~0.47), CB 0.43 (~0.50), IDL 0.45, RB 0.27 (~0.30) — is honest and holds up against the 2025 top-of-market numbers in §1.4, with EDGE the one visible under-price (0.57 modelled vs 0.83 realised in 2025 after the Will Anderson deal).

Two structural gaps against the real market shape:

- **Guaranteed money does not move.** `Contract.guaranteedMoney` exists and `escalatingBaseSalaries` / `frontLoadedBaseSalaries` (`:625-643`) shape a schedule, but no AI decision anywhere reads or trades on guarantees. In the real second-contract market guarantee structure is often the whole negotiation.
- **Term is a club veto, not a lever.** `contractYearsCeiling(age:)` (`:1382`) caps years; `agreedYears = min(desiredYears, ceiling)` (`:2606-2609`). The AI never buys a year to save APY, and never offers a shorter prove-it deal to lower risk.

---

# PART 3 — REALISM BENCHMARK

| Dimension | This game (measured) | Real NFL (cited) | Verdict |
|---|---|---|---|
| Round-1 QBs | 9 % ≈ 2.9/round, very low variance | ~3/round over 15 years; **1** in 2022, **2** in 2025, **6** in 2024 (record-tying) | mean right, **variance far too low** |
| Round-1 CBs | 20 % ≈ 6.4/round | ~4/round; 5 in 2021 was notable | **over-drafted** |
| QB : RB positional value, in money | 3.67 : 1 (`positionMultiplier` 2.2 : 0.6) | $60.0M : $20.6M = **2.9 : 1** | good |
| QB : RB positional value, on the draft board | 1.0 : 0.6 → a **3.2-point** OVR tilt | QBs go #1 overall in most drafts; RBs have not gone top-10 in consecutive drafts since 2016-17 | **far too flat** |
| Kicker in round 1 | −12.0 points ⇒ effectively never | no kicker in round 1 since 2000 | correct |
| League mean unused cap room | **23-25 %** | in-season league mean runs low single digits; 2025 cap $279.2M | **wildly high** |
| League payroll as % of cap | **64.5-79.8 %** | CBA floor **89 % cash** per 4-year period | **below the legal floor** |
| Clubs over the cap in March | **0-1 of 32, worst −0.2 %** | routine; NO entered 2025 tens of millions over | **absent** |
| Franchise tags per year | **0 by AI clubs** | 8-15 league-wide | **absent** |
| Top-of-market APY by position | QB 1.00 / WR 0.59 / EDGE 0.57 / CB 0.43 / RB 0.27 | QB $60.0M / EDGE $50.0M (0.83) / WR $40.25M (0.67) / CB $30.1M (0.50) / RB $20.6M (0.34) | **EDGE and CB under-priced** |
| Round-1 "reaches" (≥8 true-board slots) | 41 % | no direct analogue; ~⅓ of round 1 lands well off consensus | plausible |
| Mean pick vs public board, R1 | 26.0 slots | media consensus is typically within ~10-15 slots in round 1 | **too noisy** |
| 33+ share of rosters | 3.2 → **0.8 %** (`TODO.md:146`) | ~7-8 % of active rosters are 31+ | **too young** |

---

# PART 4 — THE IMPERFECTION MODEL

## 4.1 Inventory: every existing source of AI error, with its measured magnitude

| # | Source | File:line | Magnitude | Verdict |
|---|---|---|---|---|
| 1 | Draft perception fog (Gaussian by archetype) | `AIDraftPerception.swift:60-67` | σ 3.0-6.0 OVR; league mean \|err\| **3.96** | **Real and working.** The best imperfection asset in the codebase |
| 2 | Draft fog fat tail | `AIDraftPerception.swift:76-80, 163-170` | 7 % of pairs, ±8-14 OVR; fires at **6.99 %** | **Real.** Doubles steals (38→66/draft) and quadruples top-5 BPA slides (8→25 %) |
| 3 | Public consensus error | `DraftClassBuilder.swift:228-279` | σ 5.0 + same fat tail | **Real** |
| 4 | Top-4 weighted-random pick | `DraftEngine.swift:292-299` | 35 % off-argmax | **Cosmetic.** With ~350 prospects the top 4 sit within ~1-2 points; this moves a pick by a few true-board slots. It is noise, not a decision |
| 5 | GM settlement lean in FA | `FreeAgencyEngine.swift:1359-1366` | E[settlement] moves 0.444 … 0.556 of the `[floor, ask]` band — a **1.25× spread** | **Marginal.** The band itself is ±15 %, so the whole persona effect is ~±2 % of salary |
| 6 | Stance lean (contender/rebuilder) | `FreeAgencyEngine.swift:1331-1335` | clamp `[0.769, 1.30]`; the doc at `:1310-1320` admits the real span is 0.72-1.10, so **exactly one branch bites** (0.72→0.769) and the upper bound is unreachable | **Near-dead.** Self-documented as "a RAIL, not a working knob" |
| 7 | Need multiplier randomness | `FreeAgencyEngine.swift:2735-2742` | ±0.1 to ±0.2 on the need factor | Real but small |
| 8 | Round aggression band | `FreeAgencyEngine.swift:2953` | `U(0.85, 1.10)` in round 1 | Real |
| 9 | Bidding-war escalation | `FreeAgencyEngine.swift:3048` | ×1.05-1.15 | **Effectively dead** — fires only on 87+/92+/99+ OVR free agents (§2.4) |
| 10 | UDFA board noise | `UDFAMarketEngine.swift:283-287, 1071` | uniform integer ±6 (σ = 3.74) | Real — but a **second, incompatible fog model**: uniform not Gaussian, no fat tail, no GM archetype, different seed function (`:1153-1166` FNV vs `AIDraftPerception.pairSeed`) |
| 11 | Draft-day trade persona | `DraftDayTradeEngine.swift:249-262, 310-315` | seller ask premium, buyer ceiling `[0.90, 1.45]`, per-club `askNoise` | **Real and good.** The analytics GM lands under 1.0 and never trades up |
| 12 | Draft-day trade frequency | `DraftDayTradeEngine.swift:712-718` | 0.15 / 0.10 / 0.06 per pick | Real; calibrated to 12-35 swaps |
| 13 | Scout report noise (user side) | `ScoutingEngine.swift:224-235` | uniform ±1 … ±7 | Real, user-facing |

**Summary:** the draft has a genuine, measured, persona-shaped imperfection model. **Free agency has essentially none.** Items 5, 6 and 9 are the only FA-side error sources and all three are either sub-2 % or structurally dead.

## 4.2 Where the AI is currently PERFECT and should not be

| # | Perfection | File:line | Why it matters |
|---|---|---|---|
| **P1** | **AI clubs read every veteran's TRUE `overall` and TRUE `truePotential`.** `marketAppeal` (`:1238-1249`), `RosterNeedIndex` (`:952-1030`), `resignAIOwnCore` (`:1666-1700`) all read the model directly | `FreeAgencyEngine.swift` throughout | There is no `AIDraftPerception` equivalent for free agency. A club never signs a bust, never lets a good player walk because it misjudged him, never overpays for a name. Every one of the 31 rooms values every one of ~500 free agents identically and correctly |
| **P2** | **AI clubs cannot get into cap trouble.** 15 % hard reserve + annual dead-money wipe + unconditional cap growth + no salary floor | `:1143, :713-720, :686-689`; `CapManagementEngine.swift:857-889` (dead) | Removes the single biggest source of real-league churn. 23-25 % mean room, 32/32 compliant |
| **P3** | **No AI club has a house preference.** No scheme fit, no size/athleticism bias, no college bias, no "we always take the corner" | `DraftEngine.aiMakePick:186-289` | All 32 boards differ only by a symmetric Gaussian. Nobody is *systematically* wrong about anything, which is exactly what a real GM is |
| **P4** | **No AI club panics.** No position-run chasing, no clock pressure, no reaction to what it just lost in free agency | `aiMakePick` has no run/clock/history input | The most legible GM error in the sport is missing |
| **P5** | **The AI never bids above the agent's ask in the bulk market.** `settlement = floor + (ask−floor)·U^(1/lean)` | `:2601-2602` | Half the league's contracts cannot be overpays, by construction |
| **P6** | **The AI never franchise-tags, never restructures for room to spend, never eats dead money to cut a bad deal** | tags user-only; `selfHealCapCompliance` restructure-only by design (`CapManagementEngine.swift:1206-1212`) | The whole toolkit of a real front office in trouble is absent because trouble is absent |
| **P7** | **The AI's contract term is never a negotiating lever** | `:2606-2609` | No prove-it deals, no back-loaded gambles, no void years |

## 4.3 Recommended imperfection model

**Design rule.** Error must be *structured and repeatable per club*, not uniform degradation. The measure of success is that the user can learn "Denver always overpays for size" and exploit it — and that the exploit costs him something elsewhere. `AIDraftPerception` already proves the pattern works and is measurable; the recommendations below extend that pattern rather than inventing a second one.

### R1 — Give free agency a fog. (`VeteranPerception`, mirroring `AIDraftPerception`)

**What:** a per-`(team, player, season)` deterministic read on a free agent's `overall` and remaining ceiling.

**Where it attaches:** `FreeAgencyEngine.marketAppeal(_:)` (`:1238`) takes a `teamID`; `RosterNeedIndex.need/bestOverall` (`:989, :977`) take a lens; `resignAIOwnCore`'s appeal test (`:1690`) uses the club's own read.

**Distribution:** Gaussian, σ **2.0-3.5** by GM archetype (analytics 2.0 / balanced 2.5 / aggressive 3.0 / old-school 3.5) — roughly **half** the draft σ, because a veteran has NFL tape and a college prospect does not. Fat tail 4 % at ±6-10 (down from the draft's 7 % / ±8-14).

**Why it is not a gift to the user:** the user's own view of a free agent is exact today. Fogging only the AI *is* a gift. The correct pairing is to add a small user-side veteran fog too — a ±1-2 band on free agents from outside the user's own division, narrowing with a scouting spend — so both sides are pricing an estimate. If that is too large a UI change, cap the AI σ at 2.0 and let the asymmetry stay small.

**Season-anchored, not pair-anchored:** unlike the draft, re-roll the read each league year. A club that was wrong about a man in 2028 should be able to be right about him in 2030.

### R2 — Give AI clubs *house preferences*: a persistent per-club bias vector

**What:** each club carries a small, permanent, deterministic tilt on the draft and FA boards. This is the single highest-value addition, because it turns symmetric noise into a *readable* opponent.

**Where:** a new `GMTaste` alongside `TradeValueEngine.GMPersona.forTeam(id:)`, consumed as an extra additive term in `aiMakePick` (a new line after `DraftEngine.swift:277`) and as a multiplier in `simulateAIFreeAgency`'s `weightedPick` (`:2570`).

**Shape (each club draws 2 of these, deterministically from its UUID):**

| Taste | Board effect | Real-world referent |
|---|---|---|
| Traits over tape | `+0.4 × (physicalScore − 70)` in OVR points | falling in love with a 4.3 forty |
| Scheme fit | `+2.5` when the prospect's projected scheme matches the club's OC/DC | every real front office |
| Position bias | `+3.0` on one randomly-assigned position group, `−1.5` on another | "we're a running-back team" |
| Small-school aversion | `−2.0` on FCS/non-power prospects | genuine and well documented |
| Character hawk | `−4.0` per disclosed red flag; the opposite archetype ignores them entirely | the boom-or-bust GM |
| Age hawk / age blind | `marketAgeDiscountPerYear` ×1.4 or ×0.6 for this club only | the rebuilder vs the win-now buyer |

Magnitude matters: **2-4 OVR points is one letter grade and 15-27 slots of round-1 consensus movement** (§1.2 sensitivity). That is enough to be noticed and not enough to break the board.

### R3 — Round-1 need drafting, and only round 1

Real GMs draft for need in round 1 far more than the value curve justifies, and much less on day three. Attach to `DraftEngine.aiMakePick:261`:

```
deficitPoints = 5.0 × roundScale(pickNumber)      // 2.0 in R1, 1.0 in R2-3, 0.6 after
```
and **fix the inverted quality term** (`:1401-1403`): a group averaging under 60 should be worth *more* than being one body short, not less. Recommend `multiplier += 0.45` (under 60) / `+= 0.25` (under 70), which prices a replacement-level room at +2.25 board points instead of +1.0.

### R4 — Position runs and clock panic

`aiMakePick` needs two new inputs it does not currently receive: `recentPositions` (the last ~6 picks) and `pickNumber`. Then:

```
if recentPositions.suffix(6).count(of: prospect.position) >= 2 { score += 1.5 }   // the run tax
```
The plumbing is already built and dead: `DraftEventEngine.swift:170-180` detects three-in-a-row runs, and `DraftDayCoordinator` holds the pick history. This is the cheapest realistic panic model available.

For quarterbacks specifically, a run mechanic is what produces the missing variance in §3 (2.9 QBs/round with near-zero spread against a real range of 1-6): if a club with a QB deficit sees two go in the last five picks, `quarterbackPremium` should jump from 2.0 to ~6.0. That single rule reproduces the real distribution's fat right tail.

### R5 — Let AI clubs go broke

This is the biggest realism win available and it is four changes, all in one file:

1. **Persist dead money across league years.** Replace the annual wipe at `FreeAgencyEngine.swift:713-720` with the per-year ledger its own comment asks for. `CapManagementEngine.calculateDeadCap` (`:106`) already exists and is dead code — wire it.
2. **Make the reserve a *taste*, not a rail.** `capReservePercent = 0.15` (`:1143`) becomes per-club: 0.18 for the analytics GM, **0.06** for the aggressive one. The aggressive club then genuinely runs out of money in November, which is when `WeekAdvancer.refillAIRosters` has to sign minimum bodies.
3. **Enforce the salary floor.** Wire `CapManagementEngine.isAboveSalaryFloor` (`:857`) into the FA mop-up: a club under 89 % must spend in the mop-up wave (`:2650-2653`) whether or not it has a need. This alone lifts league payroll from 64-80 % into the legal band and thickens the veteran market.
4. **Give AI clubs the release lever.** `selfHealCapCompliance` (`CapManagementEngine.swift:1222`) is restructure-only, for the stated and correct reason that cuts move task #53's calibrated churn. With (1) in place, a *bounded* cap-casualty pass — at most 1 per club per year, only on a man whose dead-money charge is less than his cap hit — is the missing half. It is also the mechanism that produces good players on the market in March, which is what §3's "veteran market is unrealistically thin" is about.

### R6 — Overpay in the first 48 hours, then get cold

The interactive path already does this (§2.2) and the bulk path does not. Make `simulateAIFreeAgency`'s settlement able to exceed the ask for the top of the market: replace `:2601-2602` with a ceiling that decays over the wave, e.g. the first 15 % of `sortedAgents` settle at `floor + (ask−floor)·U^(1/lean) × U(1.0, 1.25)`. This is the single most-cited GM error in the sport and the bulk market is currently immune to it.

### R7 — Fix the bidding-war gate

`maxBidders` (`:2983`) should not be the same quantity that gates a bidding war. Decouple: keep the bid cap, but trigger `processBiddingWars` on `bids.count >= 3` *or* on the top two offers being within 10 %. And subtract the reserve at `:3057` so the escalated price is one the signing door will actually honour — otherwise `FARoundSummaryView.swift:127` keeps printing a price nobody paid.

### R8 — Unify the three positional-value tables

`DraftEngine.teamNeedComponents:1413-1420`, `FreeAgencyEngine.holePriority:1083-1091` and `ContractEngine.positionMultiplier:453-524` are three copies of one idea with two live inversions (RT, FB). Derive the first two from the third — e.g. `weight = clamp(positionMultiplier / 1.25, 0.3, 1.6)` — and widen `positionalValuePoints` from 8.0 to ~14 so that the QB-vs-RB tilt becomes ~+6 board points rather than +3.2.

### R9 — Merge the two fogs

`UDFAMarketEngine.boardNoise` (`:1153-1166`) is a uniform ±6 with its own FNV hash. It should be `AIDraftPerception.read` on the same lens the club drafted with two days earlier. One scouting department, one error model.

---

# PART 5 — RANKED VERDICT

Ranked by how much the finding distorts the simulation. **[BUG]** = the code does not do what it says or what it obviously intends. **[DESIGN]** = the code works as written and the design is wrong or missing.

| # | Finding | Target | Class |
|---|---|---|---|
| **1** | **No AI club can ever be in cap trouble.** 15 % hard reserve at every door + dead money wiped every league year + unconditional 5-8 % cap growth + an unenforced salary floor. Measured: **23-25 % mean unused room, 32/32 clubs compliant every season, payroll 64.5-79.8 % of cap** against a CBA floor of 89 % | `FreeAgencyEngine.swift:1143, :713-720, :686-689, :919, :2520, :2906` | **DESIGN** |
| **2** | **Free agency has no perception model at all.** Every AI club reads every veteran's true `overall` and true `truePotential`. `AIDraftPerception` has no FA sibling | `FreeAgencyEngine.swift:1238-1249, :952-1030, :1666-1700` | **DESIGN** |
| **3** | **No AI club has a house preference.** 32 boards differ only by a zero-mean symmetric Gaussian. Nobody is systematically wrong about anything — no trait bias, no scheme fit, no position bias, no small-school aversion | `DraftEngine.swift:186-289` | **DESIGN** |
| **4** | **The salary floor is implemented and never called.** `isAboveSalaryFloor` / `amountBelowFloor` model the real 89 % rule and have zero callers. So do `calculateDeadCap`, `calculateCapRollover`, `applyCapGrowth`, `projectedCapSpace`, `processCompensatoryPicks`, `canSelfHeal` — ~120 lines | `CapManagementEngine.swift:19, :29, :49, :106, :112, :806, :824, :830, :857, :864, :875, :882, :1123` | **BUG** |
| **5** | **Bidding wars are arithmetically impossible in rounds 4-6** and need a **99-OVR** free agent in round 3, because `maxBidders = Int(aggression × (ovr−60)/40 × 6)` must reach 4 | `FreeAgencyEngine.swift:2982-2983` vs `:3043` | **BUG** |
| **6** | **A receipt for a price nobody paid.** Bidding-war escalation tests `availableCap` without the 15 % reserve, then the signing door refuses on `availableCap − reserve`. The escalated price is printed to the user regardless | `FreeAgencyEngine.swift:3057` vs `:919`; printed at `UI/FreeAgency/FARoundSummaryView.swift:127` | **BUG** |
| **7** | **The fairness comment is inverted.** `ProspectFog` states "the AI keeps drafting on the true values internally". It has not since `AIDraftPerception` landed. Any future audit of fairness starts from a false premise | `UI/Draft/Components/ProspectFog.swift:24-26` | **BUG** |
| **8** | **Three positional-value tables, two live inversions.** RT is paid above MLB/S/TE and drafted below all three; FB is paid at kicker rate and drafted at right-tackle rate | `DraftEngine.swift:1413-1420` vs `ContractEngine.swift:453-524` vs `FreeAgencyEngine.swift:1083-1091` | **BUG** |
| **9** | **The quality half of the need model is inverted in magnitude.** A position group averaging under 60 OVR is worth **+1.0** board point; being two bodies short at any position is worth **+1.5** | `DraftEngine.swift:1395-1407` × `:261` | **BUG** |
| **10** | **Positional value on the draft board is 5.5 % of the talent scale.** QB over RB = **3.2 OVR points**, against the game's own money table at 3.67 : 1 and a real 2025 market at 2.9 : 1 ($60.0M vs $20.6M) | `DraftEngine.swift:202, :267` | **DESIGN** |
| **11** | **The AI never panics and never chases a run.** No pick history, no clock, no reaction to the board. Consequence: 2.9 QBs per first round with almost no variance, against a real 1-to-6 range | `DraftEngine.swift:161` (missing inputs) | **DESIGN** |
| **12** | **No AI club ever franchise-tags.** `applyFranchiseTag` is reachable only from two user views; the real league applies 8-15 tags a March | `UI/Contracts/FranchiseTagView.swift:673`, `UI/FreeAgency/FinalPushView.swift:1342` | **DESIGN** |
| **13** | **Two incompatible scouting fogs, two days apart.** Draft: Gaussian σ 3-6 by archetype + 7 % fat tail, seeded by `AIDraftPerception.pairSeed`. UDFA: uniform ±6, no archetype, own FNV hash | `UDFAMarketEngine.swift:283-287, :1153-1166` vs `AIDraftPerception.swift:60-80, :184-196` | **BUG** |
| **14** | **The bulk FA market cannot overpay.** `settlement = floor + (ask − floor)·U^(1/lean)` is bounded above by the agent's opening ask, while the interactive path reaches 2.36× ask. Same club, two negotiators | `FreeAgencyEngine.swift:2601-2602` vs `:2953-2956` | **DESIGN** |
| **15** | **The stance lean is a rail, not a knob** — self-documented: of the `[0.769, 1.30]` clamp only one branch (0.72→0.769) ever bites and the upper bound is unreachable | `FreeAgencyEngine.swift:1310-1335` | **BUG** |
| **16** | **A live fog breach in the pick grade.** The grade shown for the user's own pick is boosted a full letter on `prospect.trueOverall >= 80` | `DraftEngine.swift:1026` | **BUG** |
| **17** | **~400 lines of dead draft code**, one piece of which (`generateStaffRecommendations`' sleeper sort on `truePotential`) is an armed fog breach | `DraftEngine.swift:1114-1213, :1233-1314`; `DraftEventEngine.swift` (whole file, 229 lines) | **BUG** |
| **18** | **The top-4 weighted-random draw is cosmetic.** 35 % off-argmax over a 350-man board whose top 4 sit within ~1-2 points is noise, not a decision. The real reaching comes from the fog: 13.25 R1 reaches with fog vs 8.33 without | `DraftEngine.swift:292-299` | **DESIGN** |
| **19** | **Guaranteed money and contract term are never AI levers.** No prove-it deals, no back-loading, no guarantee negotiation | `FreeAgencyEngine.swift:2606-2609`; `ContractEngine.swift:625-643` | **DESIGN** |
| **20** | **Round-1 board noise runs hot.** Mean `\|pick − publicRank\|` of **26.0** slots in round 1, with 40 % of R1-3 picks taken >20 slots ahead of the media. Real consensus is tighter than that in round 1 | `AIDraftPerception.swift:60-67` (σ) × `DraftEngine.swift:283` (anchor decay) | **DESIGN** |

## The one-line summary

**The draft brain is in good shape and the free-agency brain is not.** The draft has a measured, persona-shaped, deterministic fog that produces busts and steals at credible rates; free agency has 31 omniscient, permanently solvent front offices that read true ratings, cannot overpay in half the market, cannot go broke, cannot tag, and cannot cut. Fixing #1 and #2 — persistent dead money plus a veteran perception model — would do more for league realism than every other item on this list combined.
