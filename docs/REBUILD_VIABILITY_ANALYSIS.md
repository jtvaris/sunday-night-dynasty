# Rebuild Viability: Can a Bad Team Become a Great Team in Four Seasons?

**Scope:** read-only analysis of `/Users/jtvaris/workspace/projects/Dynasty`.
**Date:** 2026-08-21. **Branch:** `feat/skeletal-mocap-players` @ `3423d35`.
**Method:** source reading with `file.swift:line` citations, plus ~110 000 games run through the
shipped `GameSimulator → DriveSimulator → PlaySimulator` pipeline via `tools/balance-harness`
(`fullgame`, `leaguegen`), plus direct measurement of `Resources/league_2026_publish.json`.
**Deliverable:** assessment only. No source file under `dynasty/dynasty/**` was modified.

---

## THE ANSWER, IN FOUR LINES

1. **Yes, easily — and far too fast.** The worst team in the shipped league can reach the
   *win-maximising* roster in **one to three offseasons**, and reaches .500 in **season one**,
   because free agency is uncontested at the top of the market and the salary cap does not bind.
2. **The "great team" endpoint is actively punished by the match engine.** Win probability
   against the league **peaks at a starter average of ~83 and then falls**. A 90-overall roster
   wins *fewer* games (11.3-5.7) than an 83-overall roster (14.0-3.0). The cause is
   `PlaySimulator.edgeCompressionScale` (`PlaySimulator.swift:2769-2785`), which deletes 91.5 %
   of the talent signal once the on-field talent gap exceeds 9 points.
3. **The counter-forces are individually real and collectively toothless.** Aging bites,
   retirement bites, the AI front office is genuinely competent — but dead money expires every
   March, there is no spending floor, no cap rollover, no parity mechanism, and the fairness
   band that governs trades is never applied to a user-proposed trade.
4. **One elite quarterback is worth more than ten points of team overall.** A 99-OVR QB on an
   otherwise-78 roster wins 79.7 % of home games; a *uniformly* 88-overall roster wins 66.4 %.
   That is accidentally realistic and is the single best thing about the current curve.

---

# PART 0 — THE ENDPOINTS, DERIVED FROM THE GAME'S OWN DATA

## 0.1 What the game calls a "team rating"

There is **no team-strength model anywhere in the engine.** No prestige, no tier, no power
rating that feeds the sim. Every "team overall" in the game is an unweighted arithmetic mean of
individual `Player.overall`:

| Function | Pool | Cite |
|---|---|---|
| `DepthChart.teamOverall(lookup:)` | first man in every depth-chart slot (~24-26) | `Domain/Models/Team/DepthChart.swift:376-381`, pool at `:189-191` |
| `RosterSummaryBar.averageOVR` | whole 53-man roster | `UI/Roster/RosterSummaryBar.swift:29-32` |
| `OwnerGoalsEngine.averageOverall` | whole roster (drives the owner's demands) | `Engine/Media/OwnerGoalsEngine.swift:464-468` |
| `TeamBrowseCatalog.starterAverage` | template `role == "starter"` (24-26) | `Data/Import/TeamBrowseCatalog.swift:152-157` |

`Player.overall = 0.5·positionAvg + 0.3·physicalAvg + 0.2·mentalAvg`
(`Domain/Models/Player/Player.swift:578-583`), and every one of those three blocks is itself a
flat mean — a QB's arm strength and his scrambling weigh identically
(`Domain/Models/Player/PlayerAttributes.swift:65-67`).

`GameSimulator` **never reads a team rating.** Its only `.overall` accesses are per-player
starter lookups (`Engine/Simulation/GameSimulator.swift:1886`, `:1894`); results emerge from the
22 starters' individual attributes through `PlaySimulator`. Team overall is therefore a *proxy*
for strength, not the input to wins — a distinction that turns out to matter enormously (§1.7).

## 0.2 The actual distribution — measured, not assumed

**Random league (`LeagueGenerator.generate`, `Data/Import/LeagueGenerator.swift:147`).** There is
no per-team strength input at all. `generateRoster` reads the team preview only for the starting
QB's name and rating (`:618-623`); all 52 other players go through
`generatePlayer(position:teamID:depthIndex:)` (`:655`), whose only behavioural inputs are
`position` and `depthIndex`. The advertised `estimatedOVR` on the team-select screen
(`Data/Import/LeagueTeamData.swift:20`, spread 64-87) correlates with the roster it actually
builds at **r ≈ 0.14**. Measured over 400 generated leagues: 53-man team mean **71.0 ± 0.96**,
best-minus-worst **3.94**; 19-starter mean **77.2 ± 1.69**, best-minus-worst **7.03**. In other
words the random league's entire quality spread is sampling noise.

**Fixed 2026 template (`Resources/league_2026_publish.json`).** Here team strength is engineered:
`tools/league-data/make_templates.py:1509-1567` solves a per-team offset by fixed point against
`strength = 0.65·z(win% + playoff bonus) + 0.35·z(top-26 quality)`, with
`TEAM_SPREAD_TARGET = 5.0` (`make_templates.py:94`). Measured directly on the shipped file
(1 807 players, `ratingTarget`, which `TemplateAttributeSolver.tune` guarantees equals
`Player.overall`, `Domain/Models/Player/TemplateAttributeSolver.swift:192-195`):

```
player mean 71.01  sd 8.95  min 45  max 96
90+ 2.16 %   80+ 17.21 %   75+ 34.75 %   sub-65 23.52 %
53-man team mean:      68.40 (NYJ) … 73.30 (SEA)   sd 1.34   spread 4.90
24-starter team mean:  75.71 (NYJ) … 82.25 (CHI)   sd 1.64   spread 6.54
corr(team mean, 2025 wins) = 0.945
```

**So the game's own definition of the endpoints is:**

| | Bad | Median | Great |
|---|---|---|---|
| starter average OVR | **74.9** (NYJ) | 78.2 | **81.5** (CHI) |
| whole-roster average | 68.4 | 71.3 | 73.3 |
| authored 2025 record | 3-14 | 8-9 | 11-14 wins |
| 85+ players on roster | 2 | 4 | 9 |
| 2026 draft picks | 10 | 8 | 7 |
| starting cap space | uniform $13.3M-$53.0M, **drawn independently of roster quality** (`LeagueGenerator.swift:1625`, `Data/Import/LeagueTemplateImporter.swift:443-458`) |

**The whole best-to-worst gap is 6.5 points of starter overall.** Hold that number; §1.7 shows
what the match engine does with it.

## 0.3 Three UI ladders read a scale the league does not occupy

- `RosterSummaryBar.rosterStrength` (`:172-190`) labels 80+ "Elite", 75-79 "Strong", 70-74
  "Average". It reads the *whole-roster* mean (68-73), so **all 32 teams render "Average" or
  "Below Avg"** and the Elite/Strong/Weak labels are unreachable. The ladder was written against
  the pre-P1 generator (league mean 76.5, `LeagueGenerator.swift:993`) and was not moved when the
  mean was recalibrated to 71.00 (`LeagueGenerator.swift:1027-1034`).
- `IntroSequenceView` ladder (`UI/Career/IntroSequenceView.swift:1048-1055`) — same problem.
- **`OwnerGoalsEngine.generateSeasonGoals` (`:55-145`) is the important one.** Its branches are
  `avgOverall > 75` → championship, `>= 65` → playoffs, `< 65` → "Develop 3 Rookies". Whole-roster
  averages in the shipped league run 68.4-73.3, so **every team including the 3-14 club lands in
  the middle branch and is told "Make the Playoffs / Win 9+ Games."** The rebuild grace-period
  branch and the contender branch are both unreachable in a normal save. The user starting a
  rebuild is judged against a playoff bar from day one.

---

# PART 1 — THE LEVERS, AND WHAT EACH IS WORTH PER SEASON

Conversion constant used throughout: `teamOverall` is the mean of ~26 starters
(`DepthChart.swift:376-381`, slots at `:144-156`), so **one starter improved by +26 OVR = +1.0
team overall.**

## 1.1 Free agency and the cap — the dominant lever, by an order of magnitude

**The cap is $265M** (`Engine/Contract/ContractEngine.swift:24`) and grows 5-8 % a year, one draw
applied to all 32 clubs (`:32`, applied `Engine/Contract/FreeAgencyEngine.swift:685-689`).

**Room a bad team can clear in one offseason.** Generated payroll is 80-95 % of cap
(`LeagueGenerator.swift:1625`). Veterans past six years pro are written on 1-2 year deals
(`LeagueGenerator.swift:1834-1836`), so ~35 % of salary expires annually. The March true-up
rebuilds `currentCapUsage` from scratch off rostered salaries
(`FreeAgencyEngine.swift:711-720`):

```
payroll at 95 %                       $251.75M
expiries (~35 % salary-weighted)      −$88.11M
new cap (×1.065)                      $282.23M
──────────────────────────────────────────────
room before any decision               $118.6M      = 42 % of cap
+ ~5 realistic veteran cuts             +$40.8M
+ ~3 restructures                       +$40.1M
──────────────────────────────────────────────
one-offseason total                    ~$199.5M     = 71 % of cap
```

Cut cost is `deadCap = 0.15 × annualSalary × yearsRemaining`
(`Engine/Camp/RosterCutEvaluator.swift:76-83`), so an offseason cut recovers
`S × (1 − 0.15N)` — 85 % on a one-year deal, 55 % on three. Restructures always succeed (consent
is never rolled, `ContractEngine.swift:1465-1469`) and free `(S − 750K) × (1 − 1/N)` — **75 % of a
four-year salary**.

**Price of talent** (`ContractEngine.estimateMarketValue`, `:545-600`; anchors `:268-276`;
`leagueAffordabilityScale = 0.75` at `:409`; position multipliers `:453-537`), at $265M, in-peak
age:

| OVR | avg position | WR | EDGE | CB | interior OL | QB |
|---|---|---|---|---|---|---|
| 68 | $4.5M | $4.9M | $4.7M | $3.5M | $2.4M | $8.2M |
| 75 | $8.5M | $8.9M | $8.6M | $6.5M | $4.5M | $15.1M |
| **85** | **$12.6M** | $17.1M | $16.4M | $12.5M | $8.5M | $28.9M |
| 92 | — | $28.3M | $27.2M | $20.7M | $14.1M | $47.9M |

**Cost per +1.0 team overall:** interior OL 68→78 = **$7.9M**; CB 68→78 = $11.6M;
WR 75→85 = $21.2M; WR 80→88 = $27.9M. Improvement gets ~3.5× more expensive at the top of the
curve — that part is correct.

**And the AI barely bids against you where it matters.** `generateAIOffers`
(`FreeAgencyEngine.swift:2758-2995`) gates round-1 entry on `marketAppeal >= 85` (`:2885-2888`,
`:2770-2779`). But `resignAIOwnCore` ranks each club's expiring men by the same `marketAppeal`
descending and auto-retains anyone clearing `ownCoreStarAppeal = 80` (`:1426`, `:1674-1686`).
**Any free agent good enough to draw a round-1 AI bid necessarily cleared the auto-keep
threshold, so he reaches the market only if his own club had already spent all three of its
`ownCoreRetentionsPerClub` slots on men ranked above him (`:1415`, `:1675`) or could not afford
him.** Given the league carries ~100 players at 85+ across 32 clubs, and appeal docks 3.2 per year
past age 25 (`:1238-1248`), a fourth appeal-85 expiring player on one roster is rare — **round 1
of free agency is, in practice, an uncontested board.** The players who *do* leak through in
volume are the ones the appeal formula
(`appeal = OVR − min(14, 3.2·max(0, age−25))`, `:1238-1248`) pushes below 72 — an 85-overall
30-year-old scores 71.0 and hits the board every single year. He draws his first AI bid in
**round 4**, at `targetMinOVR = 70`.

**On top of that the player's own decision function favours the user.** `scoreBid`
(`FreeAgencyEngine.swift:3332-3406`) multiplies the user's offer by ×1.10 flat (`:3366-3368`),
×1.15 for a hosted visit (`:3372-3374`), ×1.25 if the player is loyalty-motivated (`:3353-3355`) —
while the *entire* losing-team penalty is the winning-motivated record term
`×(1 + winPct × 0.15)`, a 12.4 % spread between 0-17 and 17-0 (`:3340-3345`). Net:

| player motivation | what the user must bid to win |
|---|---|
| money, no visit | 90.9 % of the top AI offer |
| money, with visit | **79.4 %** |
| loyalty, with visit | **61.8 %** |

And there is **no "won't sign with a loser" gate at all** in free agency:
`ContractNegotiationEngine.demand` computes `refusalVerdict` (including `.losingCulture`) only
when `negotiationType.isOwnClub` (`:679-681`), and the FA path calls it with `.freeAgent`
(`FreeAgencyEngine.swift:142-148`). `.losingCulture`
(`Domain/Models/Contract/NegotiationThread.swift:214-218`) gates extensions of your own players
only.

> **Yield, free agency: +3 to +4 starter-average points in offseason 1 for a team at 74.9,
> at optimal play; +1.0 to +1.5 at average play.** (The larger $118.6M → +8 to +12 figure holds
> only for a team whose starters average 68; NYJ's starters already average 74.9, so most of the
> board is a downgrade and the buyable delta is smaller.) Repeatable at roughly half strength in
> each subsequent offseason as the cap grows and contracts expire.

**Structural free money on the table, all verified dead code:** `calculateCapRollover`
(`Engine/Contract/CapManagementEngine.swift:19-26`) has zero call sites — yet
`UI/Career/NewCareerView.swift:468-469` advertises "Cap rollover" with a checkmark.
`isAboveSalaryFloor` / `amountBelowFloor` (`CapManagementEngine.swift:857-879`) also have zero
call sites: **there is no spending floor; a team may run at $0 payroll.** June 1 designations
(`ContractEngine.swift:1669-1687`) are implemented and never called.

## 1.2 Trades — an unbounded value pump if the user wants one

Value is `32.0 × pow(1.128, overall − 60) × positionMult × ageMult × contractMult`
(`Engine/Contract/TradeValueEngine.swift:81-88`). Picks are the literal Jimmy Johnson chart
(`Engine/Draft/PickValueChart.swift:22-58`); future picks discount 20 %/yr (`:169-174`).

A 30-year-old 85-OVR DE fetches **650 points ≈ pick #28** — a late first.

**The fairness band never fires on a user proposal.** `dealIsCoherent` — the 0.82-1.45
chart-neutral check — is called from exactly three places, all AI *offer builders*
(`TradeValueEngine.swift:2337`, `:2416`, `:3671`). `respond` (`:1186-1302`) never calls it. A
user-proposed trade is judged solely against one GM's leaned, need-inflated ratio, with no
reference to the public chart the user is looking at. Consequences:

- **Persona/stance pick arbitrage.** An old-school contender prices a future pick at
  `0.87 × 0.94 × 0.88 = 0.720`; an analytics rebuilder at `1.14 × 1.08 × 1.15 = 1.416`
  (`:236-243`, `:543-561`) — a **1.97× spread on an identical asset**, and only the user can stand
  on both sides of it.
- **Round-tripping a veteran.** Buy a 30-yo 85 DE from a rebuilding analytics club at ~414 points
  (outgoing ×0.82, `:586-599`); sell to a needy old-school contender for ~945 (incoming ×1.10 plus
  need premium, his picks priced at 0.818). **+531 points per flip ≈ a mid-first, with 31
  counterparties.**
- `partnerVerdict` (`:1086-1124`) is a free, unlimited binary search on the acceptance bar; only
  offers below `insultCutoff` earn a strike (`:1257-1282`).
- **No per-season cap on user trades.** `WeekAdvancer.swift:131-132` caps AI-vs-AI only.

> **Yield, trades: 0 at average play (most users won't find this). +2 to +4 starter-average
> points per season for a user who exploits it, essentially without limit.**

## 1.3 The draft — a 3-to-5-year lever, not an annual one

**Class shape.** 350 prospects (`Engine/Scouting/DraftClassBuilder.swift:69`), talent target
`96.5 − 5.2·ln(slot + 1.5)` (`:448-455`) → the 1.01 board man is `trueOverall` **91.7 ± 1.1** with
potential 97-99. Measured over 200 classes (`./run.sh draftclass`):

| band | true OVR | potential |
|---|---|---|
| R1 | 83.0 | 90.5 |
| R2 | 76.7 | 86.9 |
| R3 | 73.7 | 84.6 |
| R7 | 66.1 | 69.3 |

**But rookie scaling flattens all of it.** `DraftEngine.rookieScaleFactors` (`:617-631`) applies
`skill = 0.05 + readiness/99·0.14 − rawness·0.34`, which is **negative for any prospect with
potential ≥ 92**. Measured entry OVR (`./run.sh career`, 20 leagues × 30 seasons):

| | R1 | R2 | R3 | R4 | R5 | R6 | R7 | UDFA |
|---|---|---|---|---|---|---|---|---|
| entry OVR | **57.4** | 58.1 | 58.6 | 58.7 | 58.7 | 58.6 | 58.5 | 57.4 |
| dev ceiling | 90 | 85 | 81 | 77 | 74 | 72 | 71 | 71 |

This is deliberate and documented (`DraftEngine.swift:592-606`). The consequence is exact: **in a
league whose starters average 74.9, every rookie in every round is a downgrade on the incumbent
starter in year 1. The draft's year-1 contribution to team overall is zero or negative.**

**Measured hit rates** (`career` harness, hit = OVR ≥ 73 by year 4):

| rnd | hit % | washout % | career peak OVR | yr-4 median peak |
|---|---|---|---|---|
| R1 | **75.0** | 6.4 | 81.4 | 76 |
| R2 | 48.6 | 16.6 | 76.2 | 72 |
| R3 | 29.5 | 30.5 | 72.8 | 70 |
| R5 | 14.4 | 55.0 | 69.9 | — |
| R7 | 4.8 | 68.8 | 67.3 | 66 |

**Against a 74.9-overall starter set, only the R1 pick's year-4 median (76) beats the man he
replaces.** A whole seven-pick class is worth roughly **+1.1 OVR spread over 26 slots = +0.04 team
overall at the four-year mark** on a team that is already at 74.9. Its real function is
*replacing decay*, not adding strength. On the 68-overall roster the draft agent modelled, the same
class is worth +0.58 — the lever's value is entirely a function of how low the incumbent bar is.

**The chart is mispriced against the game's own outcome curve.** Expected starters per 1000
chart points: #1 = 0.25, #33 = 0.84, #65 = 1.11, #129 = 3.43. Trading down is +EV in
starter-count terms by an order of magnitude, and `DraftDayTradeEngine` gates every trade-down
offer shown to the user at chart ratio **∈ [0.98, 1.45]** (`:404-407`, `:472-475`) — the user
literally cannot get less than parity to move down.

**The user's scouting edge is decisive.** `ScoutingEngine.evaluateProspect` (`:204-235`) gives a
focus-position scout `adjustedError = max(1, errorRange − 15)`, i.e. **±1 OVR**. The average AI
club reads a prospect at mean |error| 3.96 with a 7 % ±8-14 fat tail
(`Engine/Draft/AIDraftPerception.swift:54-71`), and `aiMakePick` then deliberately misses its own
top-scored man 35 % of the time (weighted-random over the top 4 at `[0.65, 0.20, 0.10, 0.05]`,
`DraftEngine.swift:288-300`). Measured (`./run.sh perception`): the average AI first-round pick is
the **27.8th-best player on the true board** of a 32-pick round, vs 20.0 with fog off.

> **Yield, draft: +0.0 in season 1. +0.3 to +0.6 team overall per season from season 3 onward at
> optimal play (top picks, focus-scouted, started immediately); ~+0.2 at average play.**

## 1.4 Player development — powerful, but not on the roster you inherit

The whole game is one phase: `.trainingCamp` → `PlayerDevelopmentEngine.processOffseason`
(`:1842`), driven from `WeekAdvancer.swift:3958-3978` for **all 32 clubs**.

Growth is dominated by the catch-up channel (`:412-447`, `:2068-2151`):
```
f = catchUpFraction(yearsPro) · R · clamp(coachBonus, 0.80, 1.20) · damper
ΔOVR ≈ 0.8 · f · (ceiling − OVR)
catchUpFraction:  yp0/1 0.70 · yp2 0.50 · yp3 0.35 · yp4 0.245 · else 0.19
ceiling = potential ≤84 ? potential : round(84 + (potential−84)·0.72)   (:64-71)
```

For a 23-year-old 72/88 starter: **+4.2 OVR under elite coaching, +3.8 average, +3.5 with no
coaches at all, +1.4 if benched.** Growth is near-deterministic given the inputs — the spread you
see across a league comes from `R` (work ethic, motivation, snaps, health), not from a die
(`:653-656`).

**Lever ranking, by measured swing on that player:**

| lever | range | ΔOVR |
|---|---|---|
| playing time (`opportunity = 0.20 + 0.80·share`, `:848`) | ×0.32-1.00 | +1.4 → +3.8 |
| age / yearsPro | ×0.19-0.70 | +2.1 → +7.6 |
| ceiling headroom | linear | pot 75 → +1.0; pot 99 → +5.7 |
| motivation state (`MotivationState.swift:74-81`) | ×0.60-1.30 | +2.4 → +5.0 |
| health (`:789-793`) | ×0.40-1.00 | +1.6 → +3.8 |
| **coaching stack** (clamped 0.80-1.20 at `:432`) | ±10 % | **+3.1 → +4.2** |
| facilities (`FacilityEngine.swift:162-176`) | ×0.92-1.08 | +3.6 → +4.2 |

**And here is the structural problem for season 1.** The `leaguegen` harness reports the shipped
generator's mean potential headroom over current OVR as **2.05** (`./run.sh leaguegen`, assert
`8.hea`), against the draft pipeline's equilibrium of **12.02** — a gap the harness itself flags as
a known open task. Measured directly on the shipped template: mean headroom **1.6**, and the
bottom-six teams (1.68) have *no more* upside than the top six (1.63); their mean age (26.8) is
*higher* (top six 26.65).

> **There is nothing on a bad team's inherited roster to develop.** At headroom 1.6 the catch-up
> channel yields ~+0.4 OVR/player/year for the under-peak half, against −1.0 to −1.5/yr for the
> 1-3-past-peak cohort and −3 to −4/yr for the 4+ cohort (`:1424-1457`).
> **Yield, development of the inherited roster: +0.1 team overall/season. Net of decline: −0.5 to
> −1.0.** Development only becomes a real lever from season 2-3, once drafted intake (headroom 12)
> displaces the template intake (headroom 1.6).

**In-season development is ≤ 10 % of the offseason.** `TrainingFocusEngine.applyWeeklyFocusTick`
covers at most 3 players/team (`:91`) at ~+0.5 OVR/season; `applyGameExperience` is ~+0.06 OVR for
a rookie starter (`PlayerDevelopmentEngine.swift:1273-1344`).

**The AI develops as well as you do.** `autoAssignFocus` runs for every non-user club
(`WeekAdvancer.swift:1930-1932`) and reads `truePotential` **directly, with no fog**
(`TrainingFocusEngine.swift:293-308`) — better than a user reading through `HeadroomFog`
(`UI/Roster/DevelopmentReportView.swift:19-30`). AI clubs auto-upgrade facilities
(`FacilityEngine.swift:379-393`) and hire coaches best-first (`CoachCarouselEngine.swift:209`,
`:378`). The only genuine user-only development channel is the camp training plan
(`WeekAdvancer.swift:8260`), worth **~+0.09 OVR per player per offseason** — about 2 % of a camp.

## 1.5 Coaching and staff — big on the field, small on the roster

`hierarchicalDevelopmentBonus` (`Engine/Simulation/CoachingEngine.swift:1811-1853`), pivot 60
(`:1803`), clamp 0.5-1.8 (`:1852`):

| layer | attribute | slope | at 90 | at 40 |
|---|---|---|---|---|
| HC | motivation | ×0.08 | +4.8 % | −3.2 % |
| AHC | playerDevelopment | ×0.04 | +2.4 % | −1.6 % |
| coordinator | playerDevelopment | ×0.10 | +6.0 % | −4.0 % |
| **position coach** | playerDevelopment | **×0.15** | **+9.0 %** | −6.0 % |
| coordinator continuity ≥3 yr | — | flat | +5.0 % | — |

But the catch-up channel clamps this to **0.80-1.20** (`PlayerDevelopmentEngine.swift:432`), so an
elite staff computing 1.339 is capped at 1.20. **Coaching is a ±10 % development lever, worth
~0.8 OVR of terminal value over an eight-year career arc, not the ±37 % the formula suggests.**

On the field it is much larger. `CoachingModifiers` (`Engine/Simulation/CoachingModifiers.swift`)
is wired identically into quick sim (`GameSimulator.swift:154-164`) and the live game
(`LiveGameEngine.swift:1294-1299`), net-clamped at **±0.07 completion and ±0.75 run yards**
(`:215-216`) ≈ **±3.4 points/game per team**. The repo's own R40 measurement
(`TODO.md:780`): turning coaching from OFF to ON with a grade-88 staff against a grade-55 staff
moved home win share **53 % → 92 %** and margin **+4.2 → +22.0**.

**A bad team can buy a near-elite staff on day one.** `BudgetEngine.annualBudget`
(`Engine/Budget/BudgetEngine.swift:15-48`) is
`(15_000 + spendingWillingness/99 · 40_000) × market × success × archetype`, floor $12M. The
success multiplier spans only 0.90 (bad) to 1.15 (playoffs) — a 28 % swing. Sum of role *maxima*
excluding the head-coach seat (which a GM+HC career never fills, `Domain/Enums/CoachRole.swift:205-209`)
is **$37.3M** against a ~$35M average pot. Eight elite position coaches — the heaviest development
weight in the game — cost **~$8.8M total**. The only real gate on a losing club is a 40 % decline
chance on premium candidates when `reputation < 40 && wins < 5`
(`CoachingEngine.swift:669-705`), plus a 10-15 % salary premium; and **firing a coach is free**
(`UI/Staff/CoachDetailView.swift:1011-1014`) because `Coach.contractYearsRemaining` is never
decremented anywhere in the engine.

> **Yield, coaching: ~+0.1 team overall/season via development, but +2 to +3 points of scoring
> margin per game immediately — worth roughly +1.5 to +2.5 wins in season 1 alone, for money that
> does not touch the salary cap.** This is the single most underpriced lever in the game.

## 1.6 Scheme fit — real, but ~30 % of its designed size, and it punishes change

`rosterSchemeFit = 0.594 + 1.77·traitEdge + 0.25·(familiarity − 60)/100`
(`CoachingEngine.swift:487-509`) feeds `updatePotentialRealization`
(`PlayerDevelopmentEngine.swift:1556-1576`): fit ≥ 0.8 → +1..2 potential/yr, < 0.2 → −2..−1,
lifetime drift capped ±8 (`:1622`).

On the field, familiarity enters `PlaySimulator` through four channels
(`famCurve` `:4042-4046`; blown-assignment `:4063-4078`; direct yardage `:3952-3965`;
`schemePerformanceModifier` `VersatilityDevelopmentEngine.swift:357-367`), designed to be worth
**~+3.5 points/game at fam 100 vs 33**. The measured in-repo figure is +2.7 points
(`TODO.md:786`), because `offensePlayers`/`defensePlayers` handed to `simulatePlay` are the
**entire 53-man roster**, not the 11 on the field (`GameSimulator.swift:230-231` →
`DriveSimulator.swift:115-117`), and off-side players return `schemeFam = 0`
(`Player.swift:592-594`), averaging ~27 hard zeros into every squad reading. A league-average
defense reads ~29.7 and fires the coverage-bust branch on ~3.3 % of pass plays, contradicting the
engine's own comment that "a neutral squad never busts" (`PlaySimulator.swift:4022-4023`).

Switching schemes costs ~1 season in the blown-assignment regime: the new scheme seeds at
`installBaseline ≤ 50` (`VersatilityDevelopmentEngine.swift:229-237`), below the
`famBustPivot` of 55, and takes ~1.6 seasons to reach the scheme-fit pivot and **~3.7 seasons** to
reach the completion pivot at 70. Switching in the UI is free and instant with no cost preview
(`UI/Staff/SchemeSelectionView.swift:399-409`).

> **Yield, scheme: −2 to −3 points/game for one season after a change, +2 to +3 once installed
> (3-4 seasons). A rebuild that changes coordinator and scheme in year 1 pays a real,
> correctly-shaped tax.** This is one of the few counter-forces that works as designed.

## 1.7 The conversion that decides everything: roster quality → wins

Measured with the shipped `GameSimulator → DriveSimulator → PlaySimulator` pipeline through
`tools/balance-harness/run.sh fullgame`, uniform-tier rosters, n = 2 000-3 000 games per cell.
Home and away sweeps were averaged to remove the engine's ~+3 pp home tilt.

**Neutral-field win probability vs team-overall gap:**

| gap | 0 | +1 | +2 | +3 | +4 | **+5** | +6 | +8 | **+10** | +13 | +16 | +23 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| win % | 50.0 | 60.0 | 71.0 | 79.6 | 86.4 | **87.8** | 84.9 | 69.1 | **63.9** | 68.0 | 74.6 | 84.0 |

**The curve is not monotone.** It peaks at a +5 gap and falls to a trough at +10. Reproduced at a
second baseline (home swept against a fixed 78 opponent, n = 3 000/cell): 79 → 63.4 %, 81 → 82.1 %,
**83 → 88.0 %**, 84 → 86.6 %, 86 → 70.2 %, **88 → 67.4 %**, 90 → 70.3 %, 95 → 82.2 %.

### The mechanism, exactly

`PlaySimulator.edgeCompressionScale` (`Engine/Simulation/PlaySimulator.swift:2769-2785`):

```swift
private static let teamEdgeFull  = 3.5     // |gap| at/below which scale = 1.0
private static let teamEdgeCrush = 9.0     // |gap| at/above which scale = floor
private static let teamEdgeFloor = 0.085   // residual edge on a full-team mismatch

let a = abs(mean(offense.overall) − mean(defense.overall))
if a <= 3.5 { return 1.0 }
if a >= 9.0 { return 0.085 }
let t = (a − 3.5) / 5.5
return 1.0 − 0.915 * (t*t*(3 − 2*t))       // smoothstep
```

This multiplies **every** 0-centred talent channel — sack, completion, matchup, deep, INT, drops,
contested, run block, carrier, stuff, breakaway, fumble (call sites `:509-510`, `:573`, `:713`,
`:796`, `:843-844`, `:1082`, `:1233`, `:1263`, `:1390-1391`, `:1466`, `:1525`, `:1588`, `:1644`,
`:1689`). Beyond a 9-point gap, **91.5 % of the roster-quality advantage is deleted.**

Effective on-field edge = `gap × scale(gap)`:

| gap | 3.5 | 4 | **4.9** | 6 | 7 | 8 | 9 | 10 | 20 | 30 | **49** |
|---|---|---|---|---|---|---|---|---|---|---|---|
| scale | 1.000 | 0.979 | 0.855 | 0.605 | 0.360 | 0.165 | 0.085 | 0.085 | 0.085 | 0.085 | 0.085 |
| **effective edge** | 3.50 | 3.91 | **4.18** | 3.63 | 2.52 | 1.32 | 0.77 | 0.85 | 1.70 | 2.55 | **4.17** |

> **The effective talent edge this engine will express peaks at a 4.9-point gap and does not
> return to that level until a gap of 49 — a number no roster in this game can reach.**
> +5 points of team overall is the maximum on-field advantage that exists.

A second, smaller mechanism compounds it: `underdogReliefCompletion`
(`PlaySimulator.swift:2896-2910`) hands the weaker offense up to **+4.5 pp of completion**, on a
trapezoid that ramps in from a 4-point gap, plateaus at 11-13, and fades out by 19
(`underdogGapMin/Peak/Plateau/Zero` at `:2883-2894`). So exactly in the band where compression is
crushing the favourite, the underdog is being handed free completions.

Both were introduced deliberately — the block comments at `:2742-2768` and `:2871-2882` explain
they exist to stop uniform elite-vs-weak matchups going 100 % deterministic (a real problem: the
harness README documents `elite` vs `weak` landing at 100 % / ~103-4 points). **The cure is
correct in intent and wrong in shape:** it is a hard non-monotonicity applied to the exact region
a successful rebuild has to travel through.

### What that does to a season

Applying the measured neutral curve to the 32 actual starter averages in
`league_2026_publish.json`, round-robin, 17 games:

```
league starter mean 78.21, sd 1.63

CHI 81.54 → 13.4 W        (authored record 11-6)
SEA 81.33 → 13.2 W        (14-3)
NE  80.08 → 11.6 W        (14-3)
...
ARI 76.00 →  4.9 W        (3-14)
NYJ 74.92 →  3.6 W        (3-14)

simulated win sd 2.59
```

The static league reproduces a plausible NFL win spread. Now the same model, asking what a *user*
gets for each additional point of starter overall:

| starter OVR | win % | record |
|---|---|---|
| 74.9 (worst in league) | 20.3 | 3.5-13.5 |
| 77.0 | 38.2 | 6.5-10.5 |
| 78.2 (league mean) | 48.0 | 8.2-8.8 |
| 80.0 | 66.9 | 11.4-5.6 |
| 81.5 (best in league) | 74.5 | 12.7-4.3 |
| **83.0** | **82.3** | **14.0-3.0** ← maximum |
| 84.0 | 81.3 | 13.8-3.2 |
| 86.0 | 74.0 | 12.6-4.4 |
| **88.0** | 67.0 | **11.4-5.6** |
| 90.0 | 66.4 | 11.3-5.7 |
| 92.0 | 69.7 | 11.8-5.2 |

> **A 90-overall roster wins the same number of games as an 80-overall roster.** The reward curve
> for a rebuild rises steeply to 83 and then falls off a cliff. Everything a user does after
> reaching ~83 starter overall makes his team worse on the field.

### The corollary: concentrate talent, do not spread it

Because the compression keys on the *team mean* of the eleven on the field, a roster with a few
superstars stays in the uncompressed zone while a uniformly-strong roster gets crushed.
Measured, home vs a fixed 78 opponent, n = 2 500:

| roster | team OVR delta | home win % |
|---|---|---|
| uniform 83 | +5.0 | 88.3 % |
| **uniform 88** | **+10.0** | **66.4 %** |
| 78 base + 9 elite starters (QB/2 WR/2 OL/2 DL/2 CB at 99) | +7.6 | 80.2 % |
| **78 base + one 99-OVR QB** | **+0.84** | **79.2 %** |

QB sweep on an otherwise-78 roster (home, n = 2 500): QB 60 → 25.1 %, 70 → 40.0 %, 78 → 55.0 %,
86 → 65.4 %, 90 → 71.8 %, 99 → 79.7 %.

> **Upgrading one QB from 78 to 90 (+0.46 team overall) buys +16.8 pp of win probability ≈ +2.9
> wins. Upgrading the whole roster by the same +0.46 buys +0.6 wins.** The QB slot carries roughly
> **six times** the win-leverage per point of team overall of the average slot — and, unlike broad
> improvement, it never triggers compression.

## 1.8 Lever ledger — starter-average points per season

| lever | optimal play | average play | cite |
|---|---|---|---|
| **Free agency** | **+3.0 to +4.0** (yr 1), +1.5-2.0 after | +1.0 to +1.5 | §1.1 |
| **Trades** | +2.0 to +4.0 | 0.0 | §1.2 |
| **Coaching / staff** | +0.1 OVR, **+1.5 to +2.5 wins** | +0.3 wins | §1.5 |
| **Draft** | 0.0 (yr 1-2), +0.3 to +0.6 (yr 3+) | +0.2 | §1.3 |
| **Development, inherited roster** | +0.1 | +0.1 | §1.4 |
| **Development, drafted intake** | +0.5 to +1.0 (yr 3+) | +0.3 | §1.4 |
| **Aging + retirement drag** | **−0.7 to −1.0** | −0.7 to −1.0 | §2.3 |
| **Scheme change tax** | −0.0 (don't change) to −2.5 pts/game for 1 yr | — | §1.6 |
| **NET** | **+4.5 to +7.5 in yr 1; +3.0 to +5.0/yr after** | **+1.0 to +1.5/yr** | |

---

# PART 2 — THE COUNTER-FORCES, AND WHICH OF THEM ACTUALLY FIRE

## 2.1 The AI front office is genuinely competent — this is a strength

Every one of the 31 AI clubs runs a real offseason (`WeekAdvancer.swift:5347-5358`): franchise
tags (`FreeAgencyEngine.swift:1924`), fifth-year options (`:2188`), core re-signings (`:1526`),
free agency (`:2334`), cuts to 53 on `RosterValue.keepScore` (`WeekAdvancer.swift:6805`), refill
to 53 (`:6710`), a fogged competent draft (`DraftEngine.swift:161`), UDFAs (`:3786`), camp fill to
80 (`:3876`), coach firings and hires (`CoachCarouselEngine.swift:121`), facility investment
(`WeekAdvancer.swift:1044`), and 15-40 offseason + 8-25 in-season trades (`:5719-5726`). AI clubs
also self-heal cap compliance by restructure (`CapManagementEngine.swift:1222`). This is a better
AI GM than most commercial products ship.

**FIRES.** A user who does nothing will lose ground.

## 2.2 There is no parity mechanism of any kind

A search for `parity|rubberBand|regressToMean|meanReversion|competitiveBalance` across all Swift
returns only sim-engine *byte-parity* comments (`PlaySimulator.swift:337`,
`AdaptiveOpponentAI.swift:35`). Nothing detects that the user is running away and nothing
responds. The only correctives are structural and NFL-realistic: reverse-order draft
(`DraftEngine.draftSlotOrder:50-104`), worst-record-first waivers
(`WaiverWireEngine.swift:33-38`), need-and-cap-ranked free agency
(`FreeAgencyEngine.swift:2511-2551`), compensatory picks (`WeekAdvancer.swift:5193`) — **all of
which benefit the user while he is bad and stop helping the moment he is good.**

The one genuine equaliser is `edgeCompressionScale` (§1.7) — but it is a *match-level* rubber band
that punishes the roster you built rather than a *league-level* one that helps your rivals build.

**DOES NOT FIRE at the league level.**

## 2.3 Aging, decline and retirement — real, symmetric, and the only honest drag

`applyAgeRegression` (`PlayerDevelopmentEngine.swift:1382-1469`), league-wide at
`WeekAdvancer.swift:3987-3998`:

| years past peak | chance | physical attrs | magnitude | position skills | mental |
|---|---|---|---|---|---|
| < 0 | — | — | — | — | none (`:1390-1393`) |
| 0 | 10 % | 1-2 | −1 | 0-1 | — |
| 1-3 | 40 % | 2-4 | −1..−3 | 1-3 | — |
| 4+ | **80 %** | 3-6 | **−2..−5** | 2-4 | 1-2 at −1..−2 |

≈ **−1.0 to −1.5 OVR/yr** at 1-3 past peak, **−3 to −4/yr** at 4+. `declineProfile` adds +15 pp /
+1 magnitude for RB and CB, −10 pp / −1 for QB, OL, K, P (`Domain/Enums/Position.swift:23-38`).

`PlayerRetirementEngine.retirementProbability` (`:110-213`): `0.04 + yearsPastPeak · 0.19`, plus an
age wall of **+0.18 at 33, +0.25 at 35, +0.30 at 37**, forced at 41. In practice 18 %/yr at 33,
43 % at 35, 73 % at 37.

**FIRES, hard.** A team that does nothing loses ~0.7-1.0 starter-average points per season.
**But it is perfectly symmetric across all 32 clubs, so it creates churn, not competitive
pressure.** And note the model's blind spot: `overall` contributes at most +0.20 to the hazard and
only below 60 (`:141-144`), so **a 34-year-old 90-OVR quarterback retires at exactly the same rate
as a 34-year-old 55-OVR one**. Contract status and snap counts are absent entirely.

## 2.4 Cap consequences — structurally impossible past one league year

`executeNewLeagueYear` rebuilds `currentCapUsage` from scratch each March
(`FreeAgencyEngine.swift:711-720`), and the file's own comment is explicit
(`:691-710`): *"dead cap thus bites for the league year it was incurred and then expires."*
Combined with 5-8 % compounding cap growth, **a catastrophic cap sheet self-clears in one
offseason.** The `.capHell` career scenario (`Domain/Enums/GameModeEnums.swift:33`) is a
one-season starting condition, not a persistent state. There is no spending floor (§1.1).

**DOES NOT FIRE.** A bad contract costs one year and evaporates.

## 2.5 Owner patience — a real risk in seasons 2-3, unreachable after one good year

Two firing paths, both live (`career.isGameOver = true`,
`UI/Career/CareerShellView.swift:1495-1502`): weekly `OwnerSatisfactionEngine.checkFiring`
(`:117-142`, called `WeekAdvancer.swift:1618`) and the season review
`OwnerPersonaEngine.evaluateSeason` (`:294-360`, called `WeekAdvancer.swift:3028-3040`).

Thresholds with the default `patience = 5` (`Domain/Models/Team/Owner.swift:116`):
`critical = max(10, 20 − patience) = 15`, `danger = max(20, 35 − patience) = 30`. Satisfaction
starts at 70 and moves weekly: a patient owner takes −4 at win% < 0.30, −2 at < 0.45, −4 more on a
5-game losing streak, all multiplied by 0.6× at patience 7-10
(`OwnerSatisfactionEngine.swift:9-108`).

- **Season 1 is fully immune** (`totalWins + totalLosses > 18` gate at `:117-142` and
  `isFirstCompletedSeason` at `OwnerPersonaEngine.swift:294-360`).
- A 3-14 season 2 lands satisfaction around 19-25 → the danger branch fires at ~35-45 %, capped
  at 50 %.
- **One playoff berth (+10/week) or one championship (+25/week, tested as
  `career.championships > 0`, i.e. permanent) pins satisfaction at 100 forever** (`:99-105`).

And the bar itself is a playoff berth for everyone (§0.3), because the `< 65` rebuild-goal branch
is unreachable in the shipped league.

**FIRES WEAKLY.** It is a genuine coin-flip risk if the user tanks for two full seasons — but the
optimal path (§3) is at .500 in season 1, so it never engages.

## 2.6 Star discontent — a user-only tax, record-blind, self-resolving

`HoldoutEngine.detectStarHoldoutCandidates` (`:57-84`) triggers on *contract* state only — expiring,
or `salary < 0.85 × market` with `yearsPro >= 3`. **There is no wins term, no morale term, no
losing-culture term anywhere in the file.** It is called only for the user's roster
(`CareerShellView.swift:1277-1338`), so **no AI team ever has a holdout**, and it resolves within
four weeks (50 % cave at week 3, guaranteed at week 4, `WeekAdvancer.swift:2654`).

Morale is heavily damped: ±3/week cap plus one point of reversion to a 70 baseline
(`LockerRoomEngine.swift:138`, `:270-336`) — the file states a 4-13 team bleeds ~−10 over a whole
season.

**DOES NOT FIRE.** A star on a 2-15 team applies exactly the same pressure as the same star on a
15-2 team, and the only way he leaves is if the user ships him.

## 2.7 Draft busts — real, and *milder* than the real NFL

Three mechanisms: a round-independent **5 % breakout / 5 % struggle** rookie roll
(`PlayerDevelopmentEngine.swift:252-285`); the realization factor `R` (mean 0.513, p10 0.214,
p90 0.942, `:824-851`); and draft-day fog (`AIDraftPerception.swift`). Measured R1 washout is
**6.4 %** and R1 hit rate **75.0 %** — the `career` harness explicitly acknowledges this runs hot
against its own NFL reference of 55-65 % hit and 20-25 % washout, and widens the gate rather than
fixing it (`tools/balance-harness/driver/CareerScenario.harness.swift:113-131`).

**FIRES WEAKLY.** First-rounders in this build are materially safer than in real football.

> ### Defect found: the rookie boom/bust roll is unreachable
> `processOffseason` calls `applyAgeRegression` (which bumps `yearsPro`) at
> `PlayerDevelopmentEngine.swift:1908` **before** `developPlayer` at `:1918`. `developPlayer`
> gates its boom/bust branch on `player.yearsPro == 0` (`:257`). A drafted rookie therefore
> always arrives with `yearsPro == 1`. **The 5 % ×3.0 breakout and the 5 % zero-development,
> −2-all-mentals struggle never fire in the shipped game.**

## 2.8 The five structural asymmetries in the user's favour

Each is a *rule* difference, not an AI-competence difference:

| # | asymmetry | cite |
|---|---|---|
| 1 | AI clubs may re-sign at most **3 core + 2 veteran** expiring players per year; the user may re-sign all of them | `FreeAgencyEngine.swift:1415`, `:1476`; `UI/FreeAgency/FinalPushView.swift:150-155` |
| 2 | AI clubs hold back **15 % of cap** they may never spend; the user has no reserve | `FreeAgencyEngine.swift:1143`, enforced `:2517`, `:919-921` |
| 3 | AI clubs stop signing free agents at a **46-man** roster | `FreeAgencyEngine.swift:1124`, applied `:2521` |
| 4 | AI coordinators are poached silently; the user's cannot be taken without consent, and he gets a comp 3rd for allowing an interview | `WeekAdvancer.swift:3178-3181`, `:3243-3248`, `:3357` |
| 5 | The `dealIsCoherent` fairness band never runs on a user-proposed trade | `TradeValueEngine.swift:2729`, called only at `:2337`, `:2416`, `:3671` |

Asymmetry 1 is the load-bearing one: **every March, 31 clubs are forced to release roughly 80 % of
their quality expiring players into a market where the user is the most attractive bidder
(§1.1), has no cap reserve, and faces no round-1 competition.**

## 2.9 Waivers are a notification, not a mechanic

`WaiverWireEngine.processWaivers` (`:24-42`) computes priority worst-record-first and interest per
club, then writes only `cut.claimedByTeamID`, `player.cutByTeamID`, `player.cutAt` (`:70-79`) —
**never `teamID`, never a contract, never a cap charge.** The only consumer is a UI banner
(`CareerShellView.swift:1638-1673`), it runs on user camp cuts only
(`WeekAdvancer.swift:8517-8529`), and there is no user-facing claim path at all.

## 2.10 Counter-force scorecard

| counter-force | exists | fires | bites a skilled user |
|---|---|---|---|
| AI runs a real front office | ✅ | ✅ | partially |
| Veteran decline | ✅ | ✅ | yes, symmetric |
| Retirement wall | ✅ | ✅ | yes, symmetric |
| Scheme-install tax | ✅ | ✅ | yes (1 season) |
| Match-engine talent compression | ✅ | ✅ | **yes — too much (§1.7)** |
| Owner firing | ✅ | seasons 2-3 only | no, if you win in yr 1 |
| Draft busts | ✅ | weakly | R1 washout 6.4 % vs NFL 20-25 % |
| Dead money / cap hell | ✅ | one league year | **no** |
| Salary floor | ❌ dead code | ❌ | no |
| Cap rollover | ❌ dead code (but advertised) | ❌ | no |
| Star trade demands driven by losing | ❌ | ❌ | no |
| League parity / rubber band | ❌ | ❌ | no |
| Waiver claims | ❌ non-functional | ❌ | no |
| Difficulty scaling | ❌ (`difficulty` is UI-only, `TeamBrowseCatalog.swift:212-218`) | ❌ | no |
| Trade fairness band on user offers | ❌ | ❌ | no |

---

# PART 3 — THE MODEL: SEASONS TO CONTENTION

## 3.1 Assumptions, stated

1. Start: worst team in the shipped 2026 template — NYJ, **74.92 starter average**, 68.40
   whole-roster, 3-14, 10 draft picks, cap space drawn uniformly on $13.3M-$53.0M.
2. League is static in *level*: the `career` harness measures league mean OVR drift at
   **+0.018/season** (`CareerScenario.harness.swift:2745` gate is ≤ |0.40|). Rivals churn but do
   not collectively improve. Modelled as a constant 78.21 ± 1.63 opposition.
3. Win conversion is the measured neutral-field curve of §1.7, applied round-robin over the 31
   actual opponents, 17 games.
4. "Contention" = 11+ wins (a playoff team). "Great" = the win-maximising roster, starter
   average **83**.
5. Optimal play = exploits the round-1 free-agency vacuum, buys a near-elite non-HC staff in year
   1, focus-scouts, starts its rookies, and does *not* trade-fleece (I model the fleece separately
   because it is a bug, not a design).
6. Average play = signs 2-3 free agents, drafts by board rank, keeps the inherited staff, rotates
   rookies rather than starting them.

## 3.2 Optimal play

| offseason | FA | trades | draft | dev | decline | Δ | starter avg | record |
|---|---|---|---|---|---|---|---|---|
| entering yr 1 | — | — | — | — | — | — | **74.92** | 3-14 |
| yr 1 | +3.5 | 0 | +0.0 | +0.1 | −0.8 | **+2.8** | **77.7** | **7-10**, ~.410 |
| yr 2 | +2.0 | 0 | +0.2 | +0.4 | −0.8 | +1.8 | **79.5** | **10-7** |
| yr 3 | +1.8 | 0 | +0.5 | +0.8 | −0.8 | +2.3 | **81.8** | **13-4** |
| yr 4 | +1.5 | 0 | +0.6 | +0.9 | −0.9 | +2.1 | **83.9** | **13.8-3.2** |

Add the coaching lever, which does not appear in team overall at all: an elite non-HC staff bought
for ~$30M of a non-cap budget is worth up to **+3.4 points/game** (`CoachingModifiers.swift:215-216`)
≈ **+1.5 to +2.5 wins** from **season one**. So the realistic optimal line is:

> **Season 1: 8-9 or 9-8. Season 2: 11-12 wins, playoffs. Season 3: 13-14 wins, the win-maximum.
> Season 4: the roster keeps improving and the team starts winning *fewer* games.**

If the user also works the trade exploit (§1.2, +2 to +4/season), season 1 lands at ~80 starter
average and **11-6**, and the win-maximum is reached in **season 2**.

## 3.3 Average play

| offseason | Δ | starter avg | record |
|---|---|---|---|
| entering yr 1 | — | 74.92 | 3-14 |
| yr 1 | +1.2 | 76.1 | 5-12 |
| yr 2 | +1.3 | 77.4 | 7-10 |
| yr 3 | +1.4 | 78.8 | 9-8 |
| yr 4 | +1.4 | 80.2 | **11-6, playoffs** |

**Average play reaches contention in season 4** and would reach the win-maximum around season 6.
That is a good curve. The problem is not the average path — it is that the gap between average and
optimal is **three full seasons and six wins**, and the optimal path is not skilful, it is a single
exploitable market rule.

## 3.4 Doing nothing

Development of the inherited roster (+0.1) minus aging (−0.8) plus auto-draft (+0.2) plus AI-style
refill ≈ **−0.4 to −0.5/season**. NYJ auto-piloted lands near 73 starter average and 2-15 by season
4. **The game is not trivially automatic — the null strategy loses.** The failure mode is the
opposite: any *deliberate* strategy produces outsized gains, because the market is uncontested.

## 3.5 The endpoint the model cannot reach

There is no path to a roster the game would call "Elite". The `RosterSummaryBar` ladder needs
whole-roster 80+ (§0.3); the shipped league's best is 73.3 and the pyramid gate holds 90+ players
at 1-2 % of the league (`LeagueGenerator.swift:1027-1034`). And the match engine stops rewarding
improvement at starter 83 (§1.7). **The "great team" the fantasy promises is simultaneously
unrepresentable in the UI and counterproductive on the field.**


---

# PART 4 — REALISM BENCHMARK AGAINST THE ACTUAL NFL

## 4.1 The league is roughly twice as sticky as the real one

Monte Carlo, 4 000 seasons, using the 32 shipped template teams' starter averages, the measured
win curve of §1.7, binomial 17-game noise, real conference/division structure, and 7 playoff
spots per conference:

| metric | Sunday Night Dynasty | real NFL | source |
|---|---|---|---|
| **year-to-year win correlation** | **0.63** | **0.32** (r² ≈ 0.10) | Chase Stuart, *Football Perspective*, "Projecting Team Wins Using DVOA," 2014 (1989-2012) |
| SD of team wins | 3.24 | **3.10** (win% SD .194, 16 games, 2000-09) | Brian Burke, *Advanced NFL Stats*, 2010 |
| luck share of record variance | 36.6 % | **42 %** | Burke, 2010 |
| corr(record, true strength) | 0.80 | **0.75** | Burke, 2010 |
| **new playoff teams / season** | **4.2** | **5.85** avg since 1990; ~7 per season since the 2020 expansion to 14 | Nate Davis, *USA Today* 2024, via theScore |
| **worst-to-first / season** | **0.28** | **1.29** (31 teams in 24 seasons since 2002 realignment) | John Breech, CBS Sports, 2026 |
| last-place team → playoffs | 0.74 of 8 | 3 of 8 in 2025 (Bears, 49ers, Patriots); ~1.3 of 8 typical | Bleacher Report, 2026 (2025 datapoint verified; multi-decade rate is **not** published — treat the NFL cell as an estimate) |
| home win % at talent parity | 52.6-54.2 % | **.532** (714-625-4, 2020-24) | Bradley Locker, PFF, 2025 |

**The win *spread* is well calibrated; the *mixing* is not.** The engine reproduces the NFL's
standard deviation of wins, its luck share, and its modern home-field advantage almost exactly.
What it does not reproduce is churn: the real NFL regresses a team's wins **two-thirds of the way
back to 8.0 every offseason** (`Year N+1 = 5.343 + 0.332 × Year N`, Stuart 2014). This game
regresses roughly one-third.

Sensitivity: to reproduce the NFL's 0.32, the 31 AI clubs' starter averages would need to move
with a standard deviation of about **±2.7 OVR per season**. They currently move by well under
±0.5 — the `career` harness gates league-mean drift at ≤ |0.40| per season
(`CareerScenario.harness.swift:2745`), and re-running the Monte Carlo with ±0.5 OVR of AI drift
moves the correlation only from 0.635 to 0.623. **The AI churns players; it does not churn team
strength.**

## 4.2 The talent→result curve versus real point spreads

| | game | real NFL |
|---|---|---|
| biggest realistic favourite | ~85 % (best vs worst in the shipped league, a 6.5-point roster gap) | **92.3 %** — 14+ point favourites are 155-13 SU since 2005-06 (BetMGM, 2025); 13+ point favourites 49-7 (87.5 %) since 2017 (CBS) |
| largest margin the engine will express | **+13.9 points** (at a 5-point roster gap) | typical season maximum spread **14-20**; all-time record **−28** (Broncos-Jaguars, 2013 Wk 6; ESPN 2013) |
| is the favourite monotone in quality? | **no** — margin falls from +13.9 at gap +5 to +5.0 at gap +10 | **yes**, trivially |

The *magnitude* is roughly right. The *shape* is not. There is no point in the real NFL at which
adding talent makes a team a smaller favourite; there is a five-point-wide window in this engine
where it does (§1.7). Note also that the largest realistic favourite the engine can produce
(~85 %) is *lower* than the real NFL's biggest favourites (92 %) — the anti-determinism cure
over-corrected past the thing it was correcting for.

## 4.3 Rebuild timelines — the game's optimum is inside the real range; its *distribution* is not

Verified records (Wikipedia franchise season lists, cross-checked):

| franchise | trough | next | what changed | swing |
|---|---|---|---|---|
| **Colts** | 2011 **2-14** | 2012 **11-5**, playoffs | Andrew Luck 1.01 + new HC/GM (Manning had missed all of 2011) | **+9 in one year** |
| **Chiefs** | 2012 **2-14** | 2013 **11-5**, playoffs | Andy Reid hired, Alex Smith traded in | **+9 in one year** |
| **Rams** | 2016 **4-12** | 2017 **11-5**, div title | Sean McVay hired — **same QB**, Goff year 2 | **+7 in one year** |
| **Jaguars** | 2021 **3-14** | 2022 **9-8**, div title + playoff win | Doug Pederson hired — **same QB**, Lawrence year 2 | **+6 in one year** |
| **Bengals** | 2019 2-14, 2020 **4-11-1** | 2021 **10-7**, **Super Bowl LVI** | Burrow healthy (1.01 in 2020), Chase 1.05 | **+6 in one year**, 2 years from 2-14 |
| **Lions** | 2021 **3-13-1** | 2022 9-8 → 2023 **12-5** → 2024 **15-2** | Campbell/Holmes hired 2021, Goff | **+3/yr for three years** |
| **49ers** | 2016 **2-14** | 2017 6-10 → 2018 4-12 → 2019 **13-3, SB LIV** | Shanahan/Lynch 2017, Garoppolo trade, Bosa 2.01 | **3 years**, then back to 6-10 in 2020 |
| **Browns** | 2017 **0-16** | 2018 7-8-1 → 2019 6-10 → 2020 **11-5** | Mayfield 1.01, **three head coaches** | **4 years**, then 8-9 in 2021 |
| **Cowboys** | 2011-13 **8-8, 8-8, 8-8** | 2014 **12-4** | three first-round OL, no QB or coach change | **+4**, then **4-12** when Romo broke his collarbone |

**Two findings fall out of this table.**

**(a) The game's optimal-play speed is not unrealistic.** §3.2 has a 3-14 team at 8-9 in season 1
and the playoffs in season 2. Four of the nine real cases above did better than that in a single
offseason. A one-year worst-to-contender turnaround is a genuine NFL phenomenon, not a design bug.

**(b) The mechanism and the frequency are both wrong.** In the real league those jumps are driven
by a **new starting quarterback or a new head coach** (7 of the 9 cases; the ninth, Dallas 2014,
collapsed to 4-12 the moment its quarterback got hurt), and they are **rare** — 1.29 worst-to-first
teams per year out of 8 last-place clubs, i.e. **~16 %**. In this game the same jump is available
to **every** user, **every** year, through a mechanism that has nothing to do with the quarterback
or the coach: an unopposed shopping trip in free-agency round 1 (§1.1) and a trade market with no
fairness check on user offers (§1.2).

> **The right correction is not to slow the ceiling down. It is to make the ceiling contingent —
> on landing a quarterback, on hiring the right coach, on the draft breaking your way — and to
> make the median outcome much slower than the ceiling.** Right now the ceiling *is* the median
> for anyone who reads the market.

## 4.4 Quarterback leverage — accidentally excellent, and worth protecting

PFF WAR (Eager & Chahrouri, MIT Sloan; 25 500+ player-seasons, 2006-2018), mean seasonal WAR by
position for players above the 60th percentile in snaps:

| QB | WR | CB | S | TE | LB | RB | G/C | T | DI | ED |
|---|---|---|---|---|---|---|---|---|---|---|
| **1.63** | 0.28 | 0.23 | 0.23 | 0.18 | 0.11 | 0.10 | 0.10 | 0.09 | 0.06 | 0.06 |

The starting QB is worth **5.8× the next most valuable position** and 16-27× a lineman. Against an
8-win average team and a 3-win replacement team, an elite-versus-replacement QB swing is worth
**2-3 wins**.

Measured in this engine (§1.7, n = 2 500/cell): upgrading the QB on an otherwise-78 roster from 78
to 90 is worth **+2.9 wins**; from 70 to 99, **+6.4 wins**. The 78→90 figure lands squarely on the
PFF estimate. And the per-point-of-team-overall leverage ratio — QB slot ≈ **6×** the average slot
— is the right order of magnitude against PFF's 5.8×.

**This is the single best-calibrated relationship in the game, and it exists partly by accident**:
a one-man upgrade barely moves the team mean, so it never triggers `edgeCompressionScale`. Any fix
to recommendation 1 must preserve it — that is exactly what `teamEdgeFull = 3.5`'s
"single-unit safe zone" comment (`PlaySimulator.swift:2755-2765`) is protecting, and it is right
to protect it.

## 4.5 Draft realism

| | game (measured, `./run.sh career`) | real NFL | source |
|---|---|---|---|
| R1 "hit" rate | **75.0 %** | 26.0-52.4 % reach a Pro Bowl by pick range (1-10: 52.4 %, 11-20: 36.3 %, 21-32: 26.0 %); **49-73 % become full-time starters** by position | RotoWire (800 R1 picks, 2000-2024); PFF, Timo Riske, 2025 |
| R1 washout / bust | **6.4 %** | picks 1-5 bust rate **17 %**; picks 22 and 26 **57 %**; pick 32 **50 %** | RotoWire, 2026 |
| rookie #1 pick's year-1 level | 57.4 OVR in a 71.0-mean league — **well below average** | rookie QBs average PFF ~65 and **negative EPA/play** vs a typical QB's +0.04; only 3 of 24 #1-overall QBs since 1967 won Rookie of the Year | Kevin Cole, *Unexpected Points*, 2026; CBS |
| when a top pick becomes good | measured growth yp0→1 **+4.77**, yp1→2 +3.53, yp2→3 +2.32, yp3→4 +1.53, yp4→5 +0.82 | "clear and steep increase from **Years 2-4**, then levels off" | Judah Fortgang, PFF, 2023 |

**The rookie-entry curve is the best-calibrated part of the draft** — a top-5 pick who is below
average as a rookie and peaks around year 4 is exactly right, and it is a braver design choice
than most GM sims make. **The risk profile is not.** A 6.4 % R1 washout against a real 17 % (top
five) to 50-57 % (late first) means the draft in this game is a much safer store of value than in
football, which is a direct contributor to §3's fast climb. The `career` harness knows: it
explicitly widens its own R1 gate to [58, 78] % rather than fixing the number
(`tools/balance-harness/driver/CareerScenario.harness.swift:113-131`).

## 4.6 Realism scorecard

| relationship | verdict |
|---|---|
| SD of team wins | ✅ 3.24 vs 3.10 |
| luck share of record | ✅ 36.6 % vs 42 % |
| home-field advantage | ✅ 53 % vs .532 |
| QB positional leverage | ✅ ~6× vs PFF's 5.8× |
| rookie-year level and growth shape | ✅ below average, peaks yr 4 |
| magnitude of the biggest favourite | ⚠️ 85 % vs 92 % — slightly *too* competitive at the extreme |
| **year-to-year win correlation** | ❌ **0.63 vs 0.32** |
| **worst-to-first frequency** | ❌ **0.28/yr vs 1.29/yr** |
| **playoff-field turnover** | ❌ 4.2/yr vs 5.85 (7 in the 14-team era) |
| **monotonicity of quality → results** | ❌ **non-monotone above a 5-point gap; no real-world analogue** |
| **first-round bust risk** | ❌ 6.4 % washout vs 17-57 % |

---

# PART 5 — VERDICT AND RANKED RECOMMENDATIONS

## 5.1 Verdict

**On the question as asked: a user can take the worst team in the league and reach the
win-maximising roster in two to three seasons, and .500 in season one. That is too fast, and the
reason it is fast is not that the levers are generous — it is that two market rules leave the
premium end of free agency and the entire trade market uncontested.**

Three separate things are wrong, and they are wrong in different directions:

**(a) The fantasy's destination does not exist.** The match engine stops rewarding roster quality
at a starter average of ~83 and then *punishes* it: 90-overall wins 11.3-5.7 where 83-overall wins
14.0-3.0 (§1.7). The UI cannot render a great team either — all 32 teams read "Average" or
"Below Avg" on the roster ladder, and the owner tells every club including the 3-14 one to make
the playoffs (§0.3). A player who successfully executes a four-year rebuild is told he built an
average roster and then watches it win fewer games than it did in year three. **This is the most
serious finding in this report.**

**(b) The journey is too short and too cheap.** Free agency round 1 is a board with no other
bidders (§1.1); the user's offers carry a ×1.10-1.45 structural multiplier against a maximum
12.4 % losing-team penalty; the salary cap does not bind because dead money expires every March
and there is neither a rollover nor a floor; and a user-proposed trade is the only transaction in
the game that is never checked against the public value chart.

**(c) The parts that *are* right are genuinely right, and should be protected.** The AI front
office is competent and active. The aging and retirement model is well-shaped and symmetric. The
scheme-install tax is a correctly-sized, correctly-timed cost of change. The draft is a
three-to-five-year lever with a flat rookie-entry curve — an unusual and defensible design that
makes tanking-for-one-pick unattractive. And the QB leverage (§1.7) is an accident of the
compression that happens to reproduce the single most important fact about real NFL rebuilds.

**Does it feel earned?** For an average player, yes — the average-play line (§3.3) reaches the
playoffs in season 4, which is a good curve. For a player who reads the market, no: one offseason
of unopposed shopping is worth three seasons of everything else combined. The skill the game
currently rewards is noticing that nobody is bidding against you.

## 5.2 Ranked recommendations

Each is marked **BUG** (the code does not do what its own comments/design say) or **DESIGN** (it
does what it says and the design is wrong for this fantasy).

---

### 1. Make the roster-quality → win-probability curve monotone — **BUG**
`Engine/Simulation/PlaySimulator.swift:2769-2785` (`edgeCompressionScale`)

`teamEdgeFloor = 0.085` applied as a *multiplier on the raw gap* makes the effective on-field edge
`gap × scale(gap)` peak at **gap 4.9** and not recover until **gap 49**. Measured consequence: win
probability 87.8 % at +5, 63.9 % at +10 (§1.7). The intent — stop uniform elite-vs-weak going
deterministic — is right; the shape is wrong.

Replace the multiplier with a **monotone saturating map on the effective edge**, e.g.
`effEdge = teamEdgeFull + (gap − teamEdgeFull) · k` with `k ≈ 0.10-0.15`, or a tanh knee. That
preserves the flat-1.0 single-unit zone below 3.5, preserves the anti-determinism at large gaps,
and removes the reversal.

**Acceptance test (already exists, no new scenario needed):**
`./run.sh fullgame --home-tier X --away-tier 78 --n 3000` for X ∈ {78…95} must be monotone
non-decreasing in home win %, and must top out below ~92 % rather than reaching 100 %.

---

### 2. Give the random league actual bad and good teams — **BUG**
`Data/Import/LeagueGenerator.swift:606-651` (`generateRoster`), `:655` (`generatePlayer`)

`generatePlayer`'s only behavioural inputs are `position` and `depthIndex`. `TeamPreview.estimatedOVR`
(`Data/Import/LeagueTeamData.swift:20`) and the "Dynasty"/"Rebuilding" `situation` labels shown on
the team-select screen (`UI/Career/TeamSelectionView.swift:110`, `:1477-1478`) never reach the
generator: measured `corr(advertised estimatedOVR, actual roster mean) = 0.14`. KC ("Dynasty",
advertised 87) averages 71.4; CAR ("Rebuilding", advertised 64) averages 70.7.

**In a random league, the premise of this entire report is unavailable — there is no bad team to
take over.** Thread a per-team level shift through `generatePlayer` (the template path already
solves exactly this at `tools/league-data/make_templates.py:1509-1567`, target spread 5.0), so the
random league lands on the same 4-5 point roster-mean spread the template achieves.

---

### 3. Put bidders on the board in free-agency rounds 1-3 — **DESIGN**
`Engine/Contract/FreeAgencyEngine.swift:2770-2779` (round gate) × `:1415`, `:1421`, `:1426`
(retention gates)

The round-1 AI entry bar (`marketAppeal >= 85`) sits *above* the auto-retain bar
(`ownCoreStarAppeal = 80`), so nearly every player who would draw a round-1 bid was kept by his own
club. Two cheap options, either or both:

- Lower `targetMinOVR` for round 1 from 85 to ~78, so the leaked 30-year-old 85s (appeal 71.0) and
  the 78-82 tier draw AI competition in the rounds the user actually shops.
- Make `ownCoreRetentionsPerClub` (3) scale with roster quality — a contender keeps 5-6, a
  rebuilder keeps 1-2. Today it is a flat talent tax on good AI teams and the main reason quality
  flows to whoever bids (§2.8, asymmetry 1).

---

### 4. Run the trade fairness band on user proposals — **BUG**
`Engine/Contract/TradeValueEngine.swift:2729` (`dealIsCoherent`), call sites `:2337`, `:2416`,
`:3671`; missing from `respond` (`:1186-1302`)

The 0.82-1.45 chart-neutral coherence check governs every AI-built offer and no user-built one.
Combined with the 1.97× persona/stance spread on an identical future pick (`:236-243`, `:543-561`),
this is an unbounded value pump: buy a 30-year-old 85 from a rebuilding analytics club at ~414
chart points, sell him to a needy old-school contender for ~945, repeat across 31 counterparties.
Add the same guard inside `respond`, using the public chart the user is shown.

---

### 5. Stop the underdog relief firing inside the compression floor — **BUG**
`Engine/Simulation/PlaySimulator.swift:2883-2894` (constants), `:2896-2910` (function)

`underdogReliefCompletion` ramps in at a 4-point gap and hits its **+4.5 pp** plateau at gaps
11-13 — precisely the band where `edgeCompressionScale` has already fallen to its 0.085 floor. The
favourite is being crushed and the underdog subsidised at the same time, which is the second half
of the reversal in §1.7. Either narrow the trapezoid to [4, 8] (where compression has not yet
bitten), or scale the relief by `edgeCompressionScale` so the two cannot stack.

---

### 6. Balance the free-agent decision function — **DESIGN**
`Engine/Contract/FreeAgencyEngine.swift:3340-3374` (`scoreBid`)

The user's club gets ×1.10 flat (`:3366-3368`), ×1.15 for a hosted visit (`:3372-3374`) and ×1.25
for loyalty-motivated players (`:3353-3355`). The entire penalty for being a bad team is the
winning-motivated record term, a 12.4 % spread between 0-17 and 17-0 (`:3340-3345`). Net: a 2-15
user outbids a 14-3 AI at **79 cents on the dollar**.

The `.loyalty` branch is also mis-implemented against its own comment ("prefers current team"):
`bid.isPlayer` is set only for the human's offer (`:3273-3282`), so a loyalty-motivated free agent
gives the *human* +25 % and every other club −15 %, regardless of where he has played. Fix the
loyalty branch to key on `bid.teamID == player.teamID`, and either give AI clubs a matching "their
team" bonus or gate the flat ×1.10 on team success.

---

### 7. Decide whether the cap is supposed to bind — **DESIGN**
`Engine/Contract/FreeAgencyEngine.swift:691-720` (annual true-up),
`Engine/Contract/CapManagementEngine.swift:19-26` (`calculateCapRollover`, zero call sites),
`:857-885` (salary floor, zero call sites), `UI/Career/NewCareerView.swift:468-469`

Dead money is erased every March by design and documented as such. Combined with 5-8 % compounding
growth, no rollover and no floor, **there is no lasting cost to any roster decision.** At minimum,
remove the "Cap rollover" checkmark from the mode picker, which currently advertises a function
with no call sites. Better: keep proration on the books for its real term so a bad contract is a
two-to-four-season problem — that is the single strongest available brake on §3.2.

---

### 8. Give the season-1 roster something to develop — **DESIGN**
`Data/Import/LeagueGenerator.swift:914-960` (`veteranPotential`),
`Data/Import/LeagueTemplateImporter.swift:352`, `tools/league-data/make_templates.py`

Measured mean potential headroom over current OVR is **2.05** for the generator (`./run.sh
leaguegen`, assert `8.hea`, which the harness itself annotates as a KNOWN GAP against the draft
pipeline's equilibrium of **12.02**) and **1.6** on the shipped template. The bottom-six teams
carry *no more* upside than the top six (1.68 vs 1.63) and are *older* (26.8 vs 26.65).

**In seasons 1-2 the development engine — the most interesting system in the game — has nothing to
act on.** Raise the headroom for under-25 players at intake so the roster the user inherits
contains the players the rebuild is supposed to be about.

---

### 9. Rebase the UI ladders and the owner's goals onto the starter average — **BUG**
`UI/Roster/RosterSummaryBar.swift:172-190`, `UI/Career/IntroSequenceView.swift:1048-1055`,
`Engine/Media/OwnerGoalsEngine.swift:63`, `:83`, `:110`, pool at `:464-468`

All three read the whole-roster mean (real range 68.4-73.3) against thresholds written for the
pre-P1 generator (league mean 76.5, `LeagueGenerator.swift:993`). Consequences: "Elite"/"Strong"/
"Weak" are unreachable labels; and **every club in the league, including the 3-14 one, is given
"Make the Playoffs / Win 9+ Games" as the owner's primary demand** while the `< 65` rebuild-goal
branch and the `> 75` championship branch are both dead. Switch the pool to
`DepthChart.teamOverall` (range 74.9-81.5) and move the thresholds to ~76 / ~79.5.

---

### 10. Pass the on-field unit to the familiarity terms — **BUG**
`Engine/Simulation/GameSimulator.swift:230-231` → `Engine/Simulation/DriveSimulator.swift:115-117`;
consumed at `PlaySimulator.swift:4063-4078`

`offensePlayers` / `defensePlayers` are the whole 53-man roster, and off-side players return
`schemeFam = 0` (`Domain/Models/Player/Player.swift:592-594`), so ~27 hard zeros are averaged into
every squad reading. A league-average defense reads ~29.7 against a `famBustPivot` of 55
(`PlaySimulator.swift:4027`) and fires the blown-coverage branch on **~3.3 % of pass plays**,
directly contradicting the engine's own contract that "a neutral squad never busts"
(`:4022-4023`). Realized scheme effect is ~69 % of its designed size.

---

### 11. Make the rookie boom/bust roll reachable — **BUG**
`Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:1908` (`applyAgeRegression`) vs `:1918`
(`developPlayer`) vs `:257` (`yearsPro == 0` gate)

Aging runs first and bumps `yearsPro` to 1, so the 5 % ×3.0 breakout and the 5 % zero-development
struggle branch **never fire in the shipped game**. Capture `yearsPro` before `applyAgeRegression`
and pass it into `developPlayer`. This is also one of the few available sources of draft variance
(§2.7: R1 washout is 6.4 % against the harness's own NFL reference of 20-25 %).

---

### 12. Let quality and contract status matter to retirement — **DESIGN**
`Engine/PlayerDevelopment/PlayerRetirementEngine.swift:137-144`, `:196-208`

The `overall` term contributes at most +0.20 and only below 60, so a 34-year-old 90-OVR QB retires
at exactly the same 18 % as a 34-year-old 55-OVR one; and the OVR / injury / durability terms all
sit *inside* `if yearsPastPeak >= 0`, so an in-window player is immune to them. Add a quality
discount above ~80 and a bump for the unsigned.

---

### 13. Make waiver claims move players — **BUG**
`Engine/Camp/WaiverWireEngine.swift:70-79`; only consumer `UI/Career/CareerShellView.swift:1638-1673`

`processWaivers` computes worst-record-first priority and per-club interest correctly, then writes
only `cut.claimedByTeamID` / `player.cutByTeamID` / `player.cutAt` — never `teamID`, never a
contract, never a cap charge. It runs on user camp cuts only (`WeekAdvancer.swift:8517-8529`) and
there is no user-facing claim path. The one structural mechanism that hands talent to bad teams is
a notification.

---

### 14. Instrument competitive dispersion — **TOOLING**
`Engine/Simulation/MultiSeasonSmokeTest.swift:159`, `:251`, `:306`, `:855-933`

The smoke test tracks league average OVR, retirements, draftee counts, HC changes, cap bands, churn
funnels and age pyramids. **Nothing anywhere in the repo tracks whether the standings stay
competitive.** Add: standard deviation of team wins, year-to-year win correlation, repeat-champion
rate, and the share of last-place teams that reach the playoffs the next season. Every constant in
recommendations 1-6 is currently un-gated — a change to any of them is invisible to CI.

---

## 5.3 What to fix first, if only one thing

**Recommendation 1.** Everything else in this report is a balance argument. That one is a broken
function: the game's central promise is that a better roster wins more games, and above a
five-point talent gap it does not.

---

# APPENDIX — REPRODUCING THE MEASUREMENTS

All harness runs are read-only against `dynasty/dynasty/**` (`tools/balance-harness/README.md`
describes the SHA-verified source staging). From `tools/balance-harness/`:

```bash
# t=0 quality pyramid, headroom, day-one salary/market, Python-mirror pin  (§0.2, §1.4)
./run.sh leaguegen --leagues 200

# the win-probability-vs-talent-gap curve  (§1.7) — sweep both sides and average
for h in 71 72 73 74 75 76 77 78 79 80 82 85 90 95; do
  ./run.sh --no-sync fullgame --home-tier $h --away-tier 72 --n 3000 | grep "WIN SPLIT"; done
for a in 71 72 73 74 75 76 77 78 80 82; do
  ./run.sh --no-sync fullgame --home-tier 72 --away-tier $a --n 3000 | grep "WIN SPLIT"; done

# same curve at a realistic league level (confirms it is gap-driven, not level-driven)  (§1.7)
for h in 74 76 78 79 80 81 82 83 84 86 88 90 92 95; do
  ./run.sh --no-sync fullgame --home-tier $h --away-tier 78 --n 3000 | grep "WIN SPLIT"; done

# concentration vs breadth, and the QB lever  (§1.7)
./run.sh --no-sync fullgame --home-tier 83 --away-tier 78 --n 2500
./run.sh --no-sync fullgame --home-tier 88 --away-tier 78 --n 2500
./run.sh --no-sync fullgame --home-tier 78 --home-override QB=99 --away-tier 78 --n 2500
for q in 60 65 70 75 78 82 86 90 95 99; do
  ./run.sh --no-sync fullgame --home-tier 78 --home-override QB=$q --away-tier 78 --n 2500 \
    | grep "WIN SPLIT"; done

# draft outcomes, development, career lengths, §8 pyramid  (§1.3, §1.4, §2.7)
./run.sh career
./run.sh draftclass --classes 200
./run.sh perception --drafts 12
```

The per-team template numbers (§0.2, §3, §4.1) come from reading
`dynasty/dynasty/Resources/league_2026_publish.json` directly — `ratingTarget` per player, pooled
by `roleHint == "starter"`. `TemplateAttributeSolver.tune`
(`Domain/Models/Player/TemplateAttributeSolver.swift:192-195`) guarantees
`Player.overall == ratingTarget` on import, so no re-derivation is needed.

The season and league-churn models (§3, §4.1) apply the measured neutral-field win curve to those
32 starter averages: round-robin over the 31 opponents × 17 games for expected wins, and a
4 000-season Monte Carlo with binomial 17-game noise and the real conference/division structure
(4 division winners + 3 wild cards per conference) for churn. **Nothing in the repo currently
measures any of this** — see recommendation 14.

## Caveats on the measurements

1. **Uniform-tier rosters are an extreme construction.** The harness's `fullgame` tier rosters put
   every player at the same grade. Because `edgeCompressionScale` keys on the *team mean* of the
   on-field unit, a realistic star/role-player mix with the same mean produces the same
   compression — which §1.7's concentration test confirms — but the absolute per-game aggregates
   (points, net YPA) run hot against NFL bands at every tier, a known engine property documented
   in `tools/balance-harness/README.md`.
2. **The win curve was measured with no coaching staff and no scheme familiarity attached**
   (`--fam` unset), so `CoachingModifiers` and the familiarity channels contribute zero. Both
   would widen the spread further, not narrow it.
3. **The `career` harness has no game simulator** — its standings come from starter-strength
   z-scores — so its hit rates and pyramid are development measurements, not competitive ones.
4. **`crScoutErrorRange` (`--fog 11.5`) is a fitted parameter** and sets the *level* of the
   round-by-round hit rate. The elite shares, trajectory mix, aging curves and the §8 pyramid are
   independent of it.
