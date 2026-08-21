# Living a Season as an AI Club: Implementation Audit and Realism Assessment

**Scope:** read-only analysis of `/Users/jtvaris/workspace/projects/Dynasty`, engine under `dynasty/dynasty/Engine`.
**Date:** 2026-08-21. **Branch:** `feat/skeletal-mocap-players` @ `36b9a2e`.
**Deliverable:** assessment only. No code changed, nothing committed.
**Question:** walk the calendar as one of the 31 AI clubs. Does anything happen to it, and does it respond?

**Prior art this report does not repeat:** `AI_GAMEDAY_DECISIONS_ANALYSIS.md` (play-calling, game plan, prep),
`AI_ROSTER_DECISIONS_ANALYSIS.md` (draft board, FA bidding, cap), `AI_TRADE_ANALYSIS.md` (trade volume and value),
`REBUILD_VIABILITY_ANALYSIS.md` (levers, parity, counter-forces), `INJURY_SYSTEM_ANALYSIS.md` (injury rates and taxonomy).
Where a finding here overlaps one of theirs it is marked and credited rather than re-derived.

---

## THE ONE-PARAGRAPH VERSION

An AI club in this league is **alive in March and dead from September to February**. Its offseason is a real
organism: it retires players, fires coaches, hires off a bench, signs free agents, drafts on a fogged board,
bids for undrafted men, fills a camp to 87, cuts to 53, and stocks a 16-man practice squad. Its regular season
is **0.81 practice-squad poaches and ~0.6 trades**, total — that is the entire in-season transaction budget of a
football club, against a real NFL wire that runs to dozens of moves a year per team. It cannot sign a street
free agent in any week of any season (no code path exists), it cannot elevate a man off **its own** practice
squad (the board is built with `excluding: suitor.id`), it has no injured reserve (the concept does not exist
in the schema), and its waiver claims move nobody. Its four playoff weeks are a calendar with nothing in it.
And the one mechanism that would make an injury *matter* — a different man taking the snap — does not exist for
any club in the game, user included: `GameSimulator` and `LiveGameEngine` filter holdouts out of the dressed
roster and **let injured players play**, while a second, injury-aware ledger 400 lines away credits the backup
with the start he never took.

---

# PART 1 — THE PHASE-BY-PHASE WALK

A full league year is **33 advances**: 18 regular-season weeks, 3 playoff weeks
(`WeekAdvancer.swift:2726` → weeks 19/20/21), and 12 offseason phases
(`phase(after:)`, `WeekAdvancer.swift:5345-5359`). What follows is each one from the AI club's chair.

---

## 1.1 Regular season, weeks 1–18 — `advanceRegularSeasonWeek` (`WeekAdvancer.swift:1265-2497`)

### What happens to the club

| # | Event | Producer | Reaches AI clubs? |
|---|---|---|---|
| 1 | **The game itself** | `simulateGameScore()` `:1383` → `:971` → `randomTeamScore` `:8186` | Yes, but **roster-blind dice**. 15 of 16 games a week. *(Gameday audit #1)* |
| 2 | **Injuries** | `MedicalEngine.injuryCheck` at `:1799-1842` | **Yes, league-wide.** Loop is `for player in allPlayers where player.teamID != nil`. |
| 3 | **Rehab tick** | `MedicalEngine.processWeeklyRehab` `:2035` | **Yes, league-wide** (`for player in allPlayers where player.isInjured`). |
| 4 | **Rush-back decision** | `:2056-2078` | **No** — `guard player.teamID == career.teamID` at `:2038`. Self-documented: *"AI teams never rush players back."* |
| 5 | **Morale** | `LockerRoomEngine.weeklyMoraleUpdate` `:1770` | **Yes, league-wide** — every club that played is ticked (`:1765-1769`). A genuine fix, correctly scoped. |
| 6 | **Game XP / playing-time roles** | `:1885-1893`, `PlayerDevelopmentEngine.playingTimeRoles` | **Yes, league-wide**, and it is *injury-aware*: `available` excludes the injured, so a backup really does take the starter's development share. |
| 7 | **Weekly training focus + breakouts** | `TrainingFocusEngine` `:1928-1962` | **Yes, league-wide.** `autoAssignFocus` runs for every club that is not the user's (`:1934`). |
| 8 | **Scheme learning** | `:2094-2148` | **Yes, league-wide.** |
| 9 | **Trades** | `runLeagueMarketWindow` `:2291`, `:2314` | **Yes, league-wide.** ~17–21 in-season deals *(Trade audit §1.2)*. |
| 10 | **Practice-squad churn** | `PracticeSquadEngine.runWeeklyPass` `:2232` | **Yes** — and it is the *only* injury-driven AI roster response in the game. See §1.1.2. |
| 11 | **Milestone news** | `announceWeeklyMilestones` `:1583` | **Yes, league-wide** (`allPlayers`, no team filter, `:7186`). |
| 12 | **League narrative / power rankings / MVP race / hot seat** | `LeagueNarrativeEngine.updateWeekly` `:1508` | **Yes, league-wide.** Presentation only. |
| 13 | **Locker-room events** | `processLockerRoomWeek` `:1737` | **NO — user only.** `if let playerTeamID = career.teamID` at `:1735`. 25 %/week (`LockerRoomEngine.swift:571`) ⇒ ~4–5 events/season, all of them the user's. |
| 14 | **Holdouts** | `processHoldoutWeek` `:1721`; start at `CareerShellView.swift:1311` | **NO — user only.** `guard let teamID = career.teamID` (`CareerShellView.swift:1278`). `HoldoutEngine.detectHoldoutCandidates` (`:35`) has **zero callers**. |
| 15 | **Random life events** (freak injury, arrest, suspension, contract gripe) | `EventEngine.generateWeeklyEvents` `:1598` | **NO — user only** (`:1596`), **and inert for him too** — see §1.1.3. |
| 16 | **Owner satisfaction / firing / whims** | `OwnerSatisfactionEngine` `:1607`,`:1618`; `OwnerPersonaEngine.rollWhim` `:1643` | **NO — user only.** No AI owner's satisfaction is ever written anywhere in the codebase. |
| 17 | **Press conference** | `PressConferenceEngine` `:1538` | **NO — user only** (by design; it is his mailbox). |
| 18 | **Scouting reports on the draft class** | `ScoutingEngine.generateWeeklyReports` `:2204` | **NO — user only.** AI clubs read a deterministic `AIDraftPerception` lens instead, which is a defensible substitute *(Roster audit §1.3)*. |
| 19 | **Opponent prep** | `OpponentPrepEngine` `:1341-1357` | **NO — user only.** Worth ≈ +2.1 wins/season *(Gameday audit #2)*. |

**Score: 11 of 19 weekly producers reach an AI club, and 8 do not.** Everything that is a *story* — drama,
ownership, contract friction, the press — is hard-gated on `career.teamID`. Everything that is *bookkeeping* —
injuries, morale, XP, trades — is league-wide.

### 1.1.1 Quantified: what an AI club's season contains

Derived from the shipped constants (arithmetic shown):

```
Injuries      risk/player/week = 0.005 × 1.00 (freq)
                               × (1 − 72/200)  (league-mean durability 72)
                               × (1 − 60/330)  (league-mean doctor 60)
                               = 0.00262
              per team-week    = × 53 active   = 0.139
              per team-season   = × 18 weeks    = 2.50 injuries
```
Fatigue and workload are dead terms in the quick sim, so the AI club's number is exactly the league mean
(`INJURY_SYSTEM_ANALYSIS.md` §1.2, re-derived and confirmed).

```
PS poaches    weeklyPoachTarget()  = 0·0.20 + 1·0.35 + 2·0.30 + 3·0.15 = 1.40 / week league-wide
                                     (PracticeSquadEngine.swift:171-179)
              per season league-wide = × 18 = 25.2
              per AI club            = ÷ 31 = 0.81
Trades        ~17-21 in-season league-wide (Trade audit §1.2) ÷ 31 ≈ 0.6 per AI club
Street FA     0.00  — no code path (§1.1.2)
Own-squad
  elevations  0.00  — structurally impossible (§1.1.2)
IR moves      0.00  — mechanic does not exist (§1.1.2)
Waiver claims 0.00 transactions (§1.14)
─────────────────────────────────────────────────────
TOTAL in-season roster moves per AI club per season ≈ 1.4
```

Locker-room events per AI club per season: **0**. Holdouts: **0**. Owner interventions: **0**.
Suspensions, arrests, freak injuries: **0** (and 0 for the user too — §1.1.3).

### 1.1.2 The one thing an AI club *does* do about an injury — and its three holes

`PracticeSquadEngine.runWeeklyPass` (`:876-957`) is the single injury-driven AI roster routine in the game,
and it is well built. Each week it draws a poach budget, picks AI clubs at random, and asks
`shorthandedPositions(roster:)` (`:1029-1037`) which position rooms are below the ideal count **on the
available roster** — `roster.filter { !$0.isInjured && !$0.isHoldingOut && !$0.isRetired }` at `:1030`. That is
a real injury read, priced against the same `FreeAgencyEngine.positionGroupInfo` table the free-agent market
uses. It then signs a man to the 53, releases the lowest `keepScore` body to make room, and charges the cap
(`signToActiveRoster`, `:748-829`).

Three holes:

1. **The club cannot sign its own man.** The board is
   `leagueSquad(excluding: suitor.id, in: allPlayers)` (`:911`). A club whose starting corner is out
   for six weeks, with a perfectly good corner on **its own** 16-man squad, will sign somebody else's
   instead — or, if nobody else has one, nobody at all. Own-squad elevations per AI club per season: **0**.
   In the real NFL the standard gameday elevation is the *default* answer to an injury.
2. **The volume is a tenth of what it should be.** 0.81 signings per club per season.
3. **The street is closed.** There is no in-season `FreeAgencyEngine` call anywhere in
   `advanceRegularSeasonWeek` (`:1265-2497`) — verified by reading the whole function. Every AI signing
   entry point (`simulateAIFreeAgency:2334`, `simulateRemainingFA:823`, `simulateRemainingFAOnce:863`,
   `resignAIOwnCore:1526`, `signFreeAgentAI:909`) is reachable only from the `.freeAgency` phase or the
   user's FA screens.

**Injured reserve does not exist.** `RosterStatus` (`Player.swift:663`) has exactly three cases —
`.active`, `.practiceSquad`, `.campBody`. The only occurrence of the letters "IR" in a roster sense is
`EventTemplates.swift:396`, an `EventOption(label: "Place on IR")` whose entire payload is
`moraleEffect: -8, lockerRoomEffect: -3, ownerEffect: -2, mediaEffect: -1` — and whose applier has zero
callers (§1.1.3). Every club in the league, user and AI, carries its injured men on the 53 for the whole
absence.

### 1.1.3 The random-event system is inert for everybody

`EventEngine.generateWeeklyEvents` (`EventEngine.swift:87`) fires at 40 % + 16 % per week
(`:105`) ⇒ ~9–10 events a season, for the user's club only (`WeekAdvancer.swift:1596-1598`). It writes to
`WeekAdvancer.lastEvents` (`:41`). **The only consumer in the entire codebase** is
`CareerShellView.swift:3008` — `let hasPendingEvents = !WeekAdvancer.lastEvents.isEmpty`, a boolean.
No view renders a `GameEvent`, and `EventEngine.applyEventChoice` (`EventEngine.swift:144`) has **zero
callers**, so none of its morale / owner-satisfaction / reputation effects ever land.

Consequence: the two `freakInjury` templates, the `suspension` template and the `arrest` template
(`EventTemplates.swift:428-448` and neighbours) are unreachable prose. `INJURY_SYSTEM_ANALYSIS.md:30`
records that these "apply only morale / owner satisfaction / coach reputation" — the true state is one step
worse: they apply nothing, to anybody.

**`docs/LIFE_EVENTS_PLAN.md` describes a 347-event catalogue with an explicit `scope: player|team|league`
field and a league-wide budget of ~360 items a season (~11 per club).** `grep -rl "LifeEvent\|lifeEvent"`
over `dynasty/dynasty/**` returns **nothing**. It is the only designed system in the repo that would give the
31 AI clubs a drama layer, and it is unimplemented.

---

## 1.2 Trade deadline, week 9 (`WeekAdvancer.swift:2298-2337`)

**What happens:** the phase opens at `:2251`, closes at `:2299`, and `runLeagueMarketWindow(window: .deadline)`
fires 5–9 AI-vs-AI deals plus the season's under-delivery.

**What the AI does about it — and this is a genuine strength.** `TradeValueEngine.stance(for:roster:)`
(`:628-676`) is real situational reasoning: record signal ×3.0, core-24 talent against a league reference,
core age multiplied *by the sign of the record* (`:661` — "old + winning = go for it, old + losing = tear it
down"), and cap room. It produces `.contend` / `.retool` / `.rebuild`, which then move pick prices
(`:544-560`), future-pick leans, and who is on the block. A 2-10 club really does sell and a contender
really does buy.

**Two things undercut it:**

1. **The stance is keyed to a signal that carries no information.** `recordSignal` reads `team.wins`, and
   for 31 clubs `team.wins` is the output of `randomTeamScore` (`:8186`), which takes one `Int` and no team.
   Roster quality and record are uncorrelated *(Gameday audit #1: corr = 0)*. So "the 2-10 club sells" is
   really "the club the dice put at 2-10 sells", and the man it sells is chosen off a roster the dice never
   looked at. The whole situational-response layer is unfalsifiable for the same reason every other AI
   front-office system is.
2. **The need model at the deadline is injury-blind.** `TradeValueEngine.needProfile(roster:)` (`:746-780`)
   opens with `for player in roster where !player.isRetired` (`:748`) — no `isInjured` filter — and then fills
   each position's starter slots from `ranked.prefix(slots)` (`:761`). **An injured starter still occupies his
   starter slot at his full OVR.** A club that loses its 88-OVR quarterback in week 6 reads QB severity ≈ 0 at
   the deadline and will not trade for one.

That is a two-constants-drifted-apart bug in its purest form: `PracticeSquadEngine.shorthandedPositions`
(`:1030`) filters `isInjured` and `TradeValueEngine.needProfile` (`:748`) does not, and both are documented as
answering "what does this club need".

---

## 1.3 Playoffs, weeks 19–21 — `advancePlayoffWeek` (`WeekAdvancer.swift:2726-2807`)

**What happens to an AI club: nothing.** Read the whole function. It stages the bracket, plays the games
(score-only for anyone but the user), records postseason stat lines, and mails the user his elimination note.

There is **no injury roll, no rehab tick, no fatigue pass, no morale pass, no development pass, no training
focus, no trade window, no practice-squad pass**. Every one of the eleven league-wide weekly producers in
§1.1 is absent. Four calendar weeks in which the league is frozen.

The rehab omission is known and logged (`TODO.md:2008`, cited by `INJURY_SYSTEM_ANALYSIS.md:32`); the other
ten are not. Practical consequence for an AI club: a man hurt in week 17 stands still through January.

---

## 1.4 All-Star week — `case .proBowl` (`WeekAdvancer.swift:3063-3133`)

**What happens:** a random score (`simulateGameScore()`, `:3065`).

**Awards.** All-Star "selections" are the user's own top-3 by OVR (`:3072-3080`) — there is no league
selection, no All-Pro team, no OPOY/DPOY/ROY/Coach of the Year anywhere in the repo. The single league award
is MVP, taken from `career.leagueNarrative?.mvpRace.first` at `recordSeasonSummary:6144`. For AI-club players
it necessarily falls back to `ratingStarPower` (`LeagueNarrativeEngine.swift:745`, `(overall − 80) × 0.35`)
because `productionStarPower` requires `gamesPlayedThisSeason > 0` **and** a non-empty stat line, and only the
user's opponents ever produce a box score. This is honest and documented (`:698-700`), but it means the MVP
of this league is "the highest-rated quarterback", every year, forever.

**What the AI club does about any of it: nothing.** No award affects morale, contract demands, market price,
retirement or owner mood for anyone.

---

## 1.5 Championship — `case .superBowl` (`WeekAdvancer.swift:2968-3061`)

League-wide and correct: `finalizePostseasonHistory` models playoff lines for the 13 clubs the sim never box-scored
(`:2999`), and `TeamSeasonArchiveBuilder.record` freezes all 32 clubs' season rows while the staff that coached
them is still in place (`:3057`, with a good comment explaining why it must precede the carousel).

Owner review, goals and the firing verdict (`:3011-3038`) are **user-only**. No AI owner ever evaluates a season.

---

## 1.6 Coaching changes — `case .coachingChanges` (`WeekAdvancer.swift:3134-3450`)

**This is the AI club's one genuinely alive day of the year, and it is well built.**

| Event | Line | Scope | Volume |
|---|---|---|---|
| Retirement wave | `:3140` → `processPlayerRetirements:6242` → `PlayerRetirementEngine.evaluateRetirements:918` | **League-wide** (`for player in allPlayers where !player.isRetired`, `:968`) | whole league, one pass |
| Un-retirement / comeback | `:3153` → `processComeback:6488` | **League-wide, AI-only destination** (`$0.id != career.teamID`, `:6503`) | 45 % gate/offseason, max 1 |
| Coordinator poaching | `:3187-3243` | **League-wide** (`for team in teams`), user's coordinators exempted at `:3197` | per-seat roll on all 32 staffs |
| HC-promotion poaching | `:3245-3257` | **AI-only** (`where team.id != career.teamID`) | — |
| Coach development | `:3259-3277` | **League-wide** | all coaches |
| Coach retirement (65+) | `:3279-3313` | **League-wide** | — |
| **Black Monday carousel** | `:3328` → `CoachCarouselEngine.runBlackMonday:121` | **AI-only** (`aiTeams = teams.filter { $0.id != userTeamID }`, `:131`) | `min(Int.random(in: 3...6), …)` at `:164` |
| AI staff refill | `:3362` → `refillAIStaffVacancies:6871` | **AI-only** | ~10 seats/advance, bench-first |
| Unemployment settlement | `:3379` → `CoachMarketEngine.settleUnemployment:191` | **League-wide** | all coaches |
| Declarations + Senior Bowl | `:3392-3440` | League event | — |

Firings: **3–6 per season over 31 AI clubs = 0.10–0.19 per club**, mean 0.145 ⇒ a mean AI head-coach tenure
of **~6.9 seasons**. The real NFL has run 5–8 head-coach changes a year in recent seasons (~0.20/club,
mean tenure ~5). The game is somewhat sticky but in the right order of magnitude — the closest thing in this
audit to a correctly-calibrated league-wide system.

**The one asymmetry:** `CoachRelationshipEngine`'s entire staff-harmony model is dead. `calculateHarmony`
(`:44`), `hcDisagreesWithDecision` (`:100`), `applyDisagreement` (`:138`), `applySharedSuccess` (`:157`),
`personalityHarmonyBonus` (`:334`), `schemeMismatchPenalty` (`:357`), `hcMeddlingFactor` (`:371`),
`hcVolatilityPenalty` (`:387`) — **eight functions, zero callers between them**. Staff friction never fires
for anyone. Only `recordDeparture` / `markCoachingTreeSuccess` are live, and they write
`career.coachingTree`, a user-career blob.

---

## 1.7 Review Roster — `case .reviewRoster` (`WeekAdvancer.swift:3739-3760`)

Two `CareerScopedDefaults` flags and `generateOwnerDemands` for the user's owner. **Nothing happens to an AI
club in this phase at all.** One of twelve offseason advances is, for 31 clubs, a no-op.

---

## 1.8 Combine — `case .combine` (`WeekAdvancer.swift:3452-3603`)

League scouting event. AI clubs consume it through `AIDraftPerception`'s deterministic lens rather than
through scout reports — a defensible design, measured in `AI_ROSTER_DECISIONS_ANALYSIS.md` §1.3.

---

## 1.9 Free agency — `case .freeAgency` (`WeekAdvancer.swift:3605-3719`)

**The AI club's biggest day.** `executeNewLeagueYear` (`:3637`) ticks every contract, expires the zeroes,
grows the cap, and runs `resignAIOwnCore`; `simulateRemainingFAOnce` (`:3668`) closes the bulk market for
every club; `processWashouts` (`:3691`) retires the unsigned; `settleCompensatoryPicks` (`:3701`) awards
round 3–7 picks off a **league-wide** departure ledger (`CompensatoryPickEngine.recordDeparture` is called for
every expiring contract in the league at `FreeAgencyEngine.swift:620`).

Genuinely symmetric and genuinely active. Its defects — omniscient veteran evaluation, a 15 % hard reserve at
every door, no dead money, no salary floor, no franchise tags — are `AI_ROSTER_DECISIONS_ANALYSIS.md` §1–§4
and are not re-litigated here. One thing that audit did not say and this one must: **the AI club's ability
to respond to a hole is concentrated entirely in this single phase.** Whatever it does not fix in March, it
carries for twelve months.

---

## 1.10 Pro days — `case .proDays` (`WeekAdvancer.swift:3722-3737`)

`break`. Deliberately empty; the work lives in the phase-**entry** hook (`:4239-4462`), which is correct and
well-explained. In that hook, `runAITop30Visits` (`:4885-4947`) stamps ~30 prospect IDs per AI club off its
own perception board. Its own doc comment (`:4880-4882`) is honest: *"no interview is run, no report is filed,
no attribute is touched, and `DraftEngine` never reads the field."* It is a competition signal on the user's
prospect card and nothing else — a decision that terminates in a field the simulator never reads, declared as
such, which is the right way to ship one.

---

## 1.11 Draft — `case .draft` (`WeekAdvancer.swift:3762-3792`)

Draft order at phase entry (`prepareDraftOrder:4543`), AI picks through `DraftEngine.aiMakePick` behind
`AIDraftPerception`, then `UDFAMarketEngine.openMarket` (`:3784`).

**Continuity check — does a hole created in November reach the April board?** Partially.
`DraftEngine.topTeamNeeds(roster:)` reads the **live** roster, so a departure is a need. But it counts bodies,
not availability: it has **no `isInjured` read anywhere in `DraftEngine.swift`**, and `Engine/Contract/
FreeAgencyEngine.swift` has none either. A club that lost its franchise left tackle for the season in week 4
does not draft or sign like a club that needs a left tackle — it drafts like a club that has one.

---

## 1.12 OTAs — `case .otas` (`WeekAdvancer.swift:3794-3893`)

**League-wide, and both halves work.** `UDFAMarketEngine.closeMarket` (`:3805`) settles a real bidding market
across all 32 clubs (`aiTeams` at `UDFAMarketEngine.swift:1050`); `CampRosterEngine.fillCampRosters` (`:3868`)
fills every club to `campRosterTarget` 87. One asymmetry worth naming: **Phase A of the camp fill serves the
user's club first** out of a shared inventory (`CampRosterEngine.swift:452-470`), with an explicit comment that
QA measured league-wide inventory at ~100 men so a fair round-robin gave each club three. The user gets first
call on the camp-invite pool.

---

## 1.13 Training camp — `case .trainingCamp` (`WeekAdvancer.swift:3895-4038`)

**The AI club's only development pass of the year.** `applySchemeChanges` (`:3906`) and
`PlayerDevelopmentEngine.processOffseason` (`:3971`) run for all 32 clubs, against real
`buildOffseasonInputs` situational data (last season's record, participation, career trend, scheme fit,
health flags). This is the pass the balance harness's `career` scenario is calibrated against, and it is the
most symmetric system in the game.

**Everything else about camp is user-only**, and the section note says so
(`WeekAdvancer.swift:8216-8229`):

| Camp system | Definition | Scope |
|---|---|---|
| Training plan (`TrainingPlanEngine.applyWeekly`) | `:8281` | **User only** — `guard let teamID = career.teamID` at `:8260` |
| Per-day workload rows (`WorkloadEngine.tickDay`) | `:8290` | **User only** |
| Cheap workload state (`WorkloadEngine.tickWeek`) | `applyAICampWorkload:8388` | **League-wide** — the one deliberate carve-out |
| Position battles | `PositionBattleTracker.detectBattles:8322` | **User only** (re-filtered at `:8337-8338`) |
| Hard Knocks storylines | `HardKnocksNarrator:8358` | **User only** |
| Camp grades | `applyCampGrades:8475` | **User only** — comment at `:4052`: *"AI teams skip the per-player grade since the UI never surfaces them"* |

An AI club has no camp battle, no camp grade, no camp storyline and no training plan. Its August development
is one function call.

---

## 1.14 Preseason — `case .preseason` (`WeekAdvancer.swift:4040-4049`) — **31 clubs have no August**

This is the cleanest user-only system in the audit.

- `PreseasonEngine.drawSlate` (`:174-181`) opens `guard let userTeamID = career.teamID`. **A slate exists
  only for the user's club.**
- `PreseasonEngine.simulateGame` (`:313-453`) is guarded the same way at `:321-323`.
- The AI opponent dresses (`opponentDressed = opponentAvailable`, `:352`) but its **fatigue and morale are
  snapshotted before the game and restored after** (`:353-360`, `:385-393`), with the comment
  *"Its rows are restored afterwards, so this costs the league nothing."*
- `rollInjuries` (`:640-711`) is called at `:402-408` with `dressed:` — the **user's** dressed roster only.
  The AI opponent takes zero injury rolls.
- `applySchemeSnaps` (`:396`) is *"(user's club only)"* by its own comment at `:395`.
- The other 30 clubs get `leagueScoreboard` (`:722-742`): pairs shuffled, `WeekAdvancer.simulateGameScore()`
  per pair, with the header comment *"never touches a record, a stat line or a `Game` row — these numbers
  exist so the recap's league scoreboard is not blank."*

**Correction to a prior audit.** `INJURY_SYSTEM_ANALYSIS.md:19` lists the preseason exhibition as injury path
3, *"once per preseason game (3 per season), 1 roll per dressed player"*, and §1.2 derives a league-wide
`+0.3–0.7 injuries per team-season` from it. That figure applies to **exactly one club**. Preseason injuries
per AI club per season are **0**. The asymmetry runs *against* the user — he takes ~2.5 + 0.5 injuries a
season while every AI club takes 2.5 — but the more important point is that 31 clubs simply do not have a
preseason.

## 1.15 Roster cuts — `case .rosterCuts` (`WeekAdvancer.swift:4051-4078`)

`trimAIRosters` (`:4067` → `:6805-6864`) cuts every AI club from ~87 to 53 **in one pass**, worst-first by
`RosterValue.keepScore`, honouring `CapManagementEngine.releaseBlockReason` positional floors and routing
through the same `applyRelease` door the user uses (a good fix, documented at `:6812-6835`). Roughly **34 cuts
per AI club, all on the same afternoon.** The user walks a three-rung `CutDay` ladder (90→75→65→53); the AI
has no intermediate rungs.

`RosterCutEvaluator.recommendCuts` (`RosterCutEvaluator.swift:21-66`) — the purpose-built cut evaluator with
camp grade, age, contract and a position-depth guard — has **zero callers**. So do
`RosterCutEvaluator.integrityViolations`-adjacent `isPracticeSquadEligible` (`:86`, `yearsPro <= 2`), which is
a **second, incompatible definition** of practice-squad eligibility next to the live
`PracticeSquadEngine.isSquadEligible` (`:323`, `yearsPro <= 3` OR accrued-seasons rule OR one of six veteran
slots, gated on `startingCalibreOverall`).

## 1.16 The rosterCuts → regularSeason boundary (`WeekAdvancer.swift:4124-4197`)

Four things fire, and one of them is a receipt for a transaction that never happens.

1. **Waivers** — `processCampWaivers` (`:4128` → `:8508-8534`) → `WaiverWireEngine.processWaivers`
   (`WaiverWireEngine.swift:24-88`). On a claim it writes `cut.claimedByTeamID`, `player.cutByTeamID`,
   `player.cutAt` and `break`s (`:69-79`). **It never writes `player.teamID`.** The claimed player stays a
   free agent. The only readers of `claimedByTeamID` are `CareerShellView.swift:1644/1665` (a banner) and
   `CapOverviewView.swift:1487` (a filter). *(`REBUILD_VIABILITY_ANALYSIS.md` §2.9 / rec #13 found this; it is
   still true.)*
   Worse, **AI cuts never reach the wire at all**: `trimAIRosters` calls `applyRelease` without a
   `ModelContext`, so `CapManagementEngine.recordReleaseReceipt` (`:772`) files no `RosterCut` row, and the
   `.isCampCutdown` filter at `WeekAdvancer.swift:8525` would drop it anyway. The waiver wire processes the
   user's camp cuts, and produces no transaction from them.
2. **Camp-body settlement** — `CampRosterEngine.settleCampBodies` (`:4142`), league-wide, correct.
3. **`startNewSeason`** (`:4158` → `:1004-1226`): budgets, facility investment (`FacilityEngine.
   processOffseasonInvestment:1042`, league-wide, user excluded from upgrades by design), schedule, counters,
   and `refillAIRosters` (`:1219` → `:6710-6781`) — a floor pass that tops every AI club back to 53 from a
   `keepScore`-sorted free-agent pool, generating a street free agent from nothing only when the pool is dry.
4. **`PracticeSquadEngine.fillSquads`** (`:4170`) — all 32 clubs stock 16 seats. Up to **512 signings
   league-wide in one advance**, which is by an order of magnitude the largest transaction event in the game.

---

# PART 2 — USER vs AI SYMMETRY TABLE

| System | User path | AI path | Verdict |
|---|---|---|---|
| Weekly game result | `GameSimulator.simulate` full play-by-play, or `LiveGameEngine` | `simulateGameScore()` `WeekAdvancer.swift:971`/`:8186` — pure `Int.random`, no roster input | **Asymmetric — fatal.** *(Gameday #1)* |
| Weekly injury roll | `MedicalEngine.injuryCheck` `:1799` | same loop, same constants | **Symmetric** ✅ |
| Weekly rehab tick | `processWeeklyRehab` `:2035` | same | **Symmetric** ✅ |
| Rush-back decision | `ReturnDecision` + inbox `:2056` | none — *"AI teams never rush players back"* | Asymmetric, deliberate, harmless |
| Morale (weekly + season-end) | `:1770`, `:2411` | same loops, all 32 clubs | **Symmetric** ✅ |
| Game XP / playing-time roles | `:1885` | same, injury-aware | **Symmetric** ✅ |
| Weekly training focus | user picks; `applyWeeklyFocusTick` | `autoAssignFocus` `:1934` then same tick | **Symmetric** ✅ (but AI reads `truePotential`, Gameday #7) |
| Breakouts | `rollBreakout` `:1957` | same | **Symmetric** ✅ |
| Offseason development | `processOffseason` `:3971` | same call, same inputs | **Symmetric** ✅ |
| Trades | Trade Center, unlimited | `runLeagueMarketWindow`, 1–2/window | **Symmetric in kind**, capped for AI only *(Trade D2)* |
| Trade need model | — | `needProfile:746` — **injury-blind** | **Bug** |
| Free agency (March) | six interactive rounds + Final Push | `simulateAIFreeAgency` / `resignAIOwnCore` | **Symmetric in kind** *(Roster audit)* |
| Free agency (in-season) | *also none* | **none — no code path** | **Symmetric, and both are wrong** |
| Practice squad — fill | `fillSquads` (user included) `:4170` | same | **Symmetric** ✅ |
| Practice squad — own elevation | `PracticeSquadView.swift:305` → `signToActiveRoster` | **impossible** — `leagueSquad(excluding: suitor.id)` `:911` | **Asymmetric — user-only capability** |
| Practice squad — poach a rival | not offered to the user | `runWeeklyPass` `:876`, 0.81/club/season | Asymmetric the other way |
| Injured reserve | none | none | Symmetric; mechanic absent |
| Waiver claims | camp cuts enter the wire | AI cuts never file a `RosterCut` row | **Asymmetric, and cosmetic for both** |
| Depth chart | `DepthChartView.swift:271` writes `Career.depthChartData` | **no per-`Team` depth chart exists in the schema** | **Asymmetric — and irrelevant: zero engine readers** |
| Starting lineup used by the sim | `MatchupResolver.offense/defense` + `GameSimulator.startingPlayer:1885` — best OVR, injured included | identical | Symmetric and wrong |
| Cutdown | 3-rung `CutDay` ladder, `RosterCutView` | `trimAIRosters` one 87→53 pass `:6805` | Asymmetric, acceptable |
| Cap compliance | weekly gate + compliance workspace | `sweepAICapCompliance:861` — **restructure only, never cuts**, every advance | Asymmetric; deliberate *(Roster #1)* |
| Camp: training plan / battles / grades / storylines | all four | **none** | **Asymmetric — user-only** |
| Camp: workload status | per-day rows | `tickWeek` state only `:8388` | Symmetric in effect ✅ |
| Preseason exhibitions | 3 real games, real injuries, real snaps | **none** — a random scoreboard line | **Asymmetric — user-only** |
| Locker-room events | `processLockerRoomWeek:2509`, ~4–5/season | **none** | **Asymmetric — user-only** |
| Holdouts | `HoldoutEngine`, `CareerShellView:1311` | **none** | **Asymmetric — user-only** |
| Owner satisfaction / goals / firing / whims | four systems | **none; no AI owner satisfaction is ever written** | **Asymmetric — user-only** |
| Press conferences | `PressConferenceEngine:275` | none (correct — it is his mailbox) | Fine |
| FA storyline events (reunion/mentor/community/revenge/milestone/loyalty) | `FreeAgencyEngine:318-370` on user signings | **none** | **Asymmetric — and write-only: no view fetches `FAStorylineEvent`** |
| Random life events (freak injury, arrest, suspension) | `EventEngine:87`, ~9–10/season | **none** | **Asymmetric — and inert: `applyEventChoice` has zero callers** |
| Retirements / comebacks / washouts | league-wide | league-wide | **Symmetric** ✅ |
| Coaching carousel / staff market | user hires; coordinators protected by interview flow | `runBlackMonday`, `refillAIStaffVacancies`, `settleUnemployment` | **Symmetric in kind** ✅ |
| Compensatory picks | league-wide ledger | same | **Symmetric** ✅ |
| UDFA market | interactive board | `aiTeams` bid on the same board | **Symmetric** ✅ |
| Camp-invite pool | **served first** (`CampRosterEngine:452-470`) | served from the remainder | Minor user edge |
| Opponent prep | +4.2 pts/game | none | **Asymmetric** *(Gameday #2)* |
| Game plan | `savedGamePlan` | hard-coded `nil` | **Asymmetric** *(Gameday #3)* |
| Awards | All-Star list = his top 3 by OVR | MVP by rating proxy | Thin for everyone |
| Playoff weeks | coachable game | random score, nothing else | **Both dead except the game** |

**Count: 15 symmetric, 6 acceptably asymmetric, 13 user-only systems with no AI counterpart.**

---

# PART 3 — THE INJURY-TO-LINEUP CHAIN, TRACED END TO END

This is the sharpest single test of whether an AI club is alive: a starter goes down — does a different man
take the snap?

### Link 1 — the injury is created ✅
`WeekAdvancer.swift:1799-1842`. League-wide, 0.139 per club-week. The flag lands:
`player.isInjured = true`, `injuryWeeksRemaining`, `injuryType`, an `InjuryRecord`
(`MedicalEngine.applyInjury:198-250`). **This link works.**

### Link 2 — the club notices ⚠️ partial
Three consumers read the flag on the AI club's behalf:
- `WeekAdvancer.swift:1420-1428` — the attendance/starts tally builds `available` (injured excluded) and calls
  `startingLineupIDs`. ✅
- `WeekAdvancer.swift:1883-1893` — the development pass does the same and hands the starter's XP share to the
  backup. ✅ *(This is real "next man up" — in the development ledger only.)*
- `PracticeSquadEngine.shorthandedPositions:1030` — the poach board. ✅

Two that should and do not:
- `TradeValueEngine.needProfile:748` — no `isInjured` filter (§1.2).
- `DraftEngine` / `FreeAgencyEngine` — **zero `isInjured` reads in either file.**

### Link 3 — a depth chart is updated ❌ there is no depth chart
`Career.depthChartData` (`Career.swift:46`) is a single `Data?` blob on the *career*. There is no per-`Team`
depth-chart field anywhere in the schema, so **structurally no AI club can have one.** The user's is written
by exactly one site (`DepthChartView.swift:271`) and read by four, all UI:
`DepthChartView.swift:260`, `CareerShellView.swift:1424` and `:2779`, `ScheduleView.swift:97`.
**Zero engine readers.** *(Gameday audit #9 found this; it is still true.)*

### Link 4 — a replacement is signed or promoted ⚠️ one narrow path
- Own practice squad → **impossible** (`PracticeSquadEngine.swift:911`).
- Rival practice squad → **0.81 per club per season** (§1.1.2). This is the only working link.
- Street free agent → **no code path in-season.**
- Trade for one → the need model says he isn't needed (§1.2).
- IR to open a spot → **mechanic does not exist.**
- Waiver claim → **moves nobody** (§1.16).

### Link 5 — the replacement takes the snap ❌ **THE CHAIN BREAKS HERE, FOR EVERY CLUB**

```
GameSimulator.swift:130   let homeRoster = (homeRosterOverride ?? homeTeam.currentRoster()).filter { !$0.isHoldingOut }
GameSimulator.swift:131   let awayRoster = (awayRosterOverride ?? awayTeam.currentRoster()).filter { !$0.isHoldingOut }
```
`Team.currentRoster()` (`Team.swift:147-154`) is a raw `teamID` fetch. **`isInjured` is not filtered.**
`SimPlayer` (`SimPlayer.swift:14-56`) has no injury field at all — the concept does not survive the snapshot.
The play simulator then picks by raw overall:
```
GameSimulator.swift:1885  players.filter { $0.position == position }.max { $0.overall < $1.overall }
PlaySimulator.swift:2328  players.filter { $0.position == .QB }.max(by: { $0.overall < $1.overall })
MatchupResolver.swift:26  best-available-by-overall, with an "any warm body" back-fill at :32-37
```
**An 88-OVR quarterback with a torn knee and 11 weeks remaining starts, takes every snap and throws for 300 yards.**

The coached path is identical. `LiveGameEngine.swift:1283-1284` filters `isHoldingOut` and not `isInjured`;
`sidelinedIDs` (`:696-700`) is `injuredPlayerIDs ∪ manuallyBenchedIDs ∪ restingRB`, and `injuredPlayerIDs`
starts empty and only ever accumulates **injuries suffered during this game** (`:688`). A man who was hurt
last Sunday is on the field this Sunday. The comment at `:1451-1453` — *"Injured … players are off the board:
the sim picks its QB/RB/targets from the remaining roster, so the replacement genuinely plays"* — is true only
of injuries the current game produced.

The one path that gets it right is the preseason: `PreseasonEngine.swift:332-333` filters
`!$0.isInjured && !$0.isHoldingOut` on both sides, with a comment that names the regular-season path as the
known simplification. That comment has been correct for at least two audit cycles.

### Link 6 — the ledgers disagree ❌ a receipt for something that never happened

Because link 2 works and link 5 does not, the same week produces two contradictory records:

| Ledger | Source | Says |
|---|---|---|
| `gamesStartedThisSeason` | `WeekAdvancer.swift:1420-1428`, `available` excludes injured | **the backup started** |
| `gamesPlayedThisSeason` | same | **the injured starter did not play** |
| `Player.seasonStatLine` | `accumulateSeasonStats:7109` — no injury guard | **the injured starter threw for 312 yards** |
| the scoreboard | `GameSimulator` | **the injured starter's ratings decided the game** |

`PlayerSeasonHistory` snapshots the first two at week 18 (`recordSeasonHistory:7040`); the third is the
box score. So a player can end a season with 0 games played and 3,000 passing yards, and his backup can end it
with starts he never took. `LeagueNarrativeEngine.productionStarPower:711` guards on
`gamesPlayedThisSeason > 0`, so the injured leader silently drops out of the MVP race he statistically leads.

### Link 7 — for 15 of 16 games it could not have mattered anyway
`WeekAdvancer.swift:1383` → `simulateGameScore()` → `randomTeamScore(homeAdvantage:)` (`:8186`), which takes
one `Int`. No AI-vs-AI result has ever been a function of who was healthy. *(Gameday #1.)*

### Link 8 — the injury outlives the season ❌
Playoffs tick nothing (§1.3). The **entire** offseason contains exactly one decrement:
`PlayerDevelopmentEngine.processOffseason` → `processInjury` (`:1941-1946`), and only for rostered,
non-holdout, non-camp-body players. Nothing in `startNewSeason` (`:1004-1226`) resets `isInjured` — verified
line by line.

Derived, using the shipped bands (`InjuryType.swift:20-30`) and a league-average staff modifier
`1 − 60/400 − 60/660 = 0.759`, injury week uniform on 1…18 and effective weeks `max(1, ⌊base × 0.759⌋)`:

```
mean effective absence            2.73 weeks
P(an injury survives the offseason)  9.60 %
carried injuries per club per season 0.240
expected residual weeks per club     0.64
league-wide: 32 × 0.240 ≈ 7.7 players open a season already hurt
```

An AI club that cannot sign anybody in-season also cannot sign anybody about it in February, because the free
agency phase's need model does not read the flag either.

**Verdict: the chain has eight links and works at three of them.** Link 5 is where it breaks for every club in
the league; links 3, 4 and 8 are where it breaks specifically for the AI.

---

# PART 4 — REALISM BENCHMARK

## 4.1 Transaction volume

| Quantity | This game, per AI club per season | Real NFL, per club per season |
|---|---|---|
| In-season roster transactions (all kinds) | **≈ 1.4** | Well over 100 once practice-squad signings, releases and elevations are counted; the league's transaction wire runs to thousands of entries a year |
| Practice-squad **gameday elevations** | **0** (structurally impossible) | The standard elevation was introduced in 2020: up to 2 PS players per game, each a maximum of 3 times a season. A club using it at a typical rate makes ~20–35 elevations a year, and it is the *first* answer to an injury |
| Practice-squad signings/releases | 16 in one August pass, 0.81 in-season | Continuous; a 16-man squad (2022 CBA — the game's own `squadSize = 16`, `PracticeSquadEngine.swift:56`) turns over many times |
| Street free agents signed in-season | **0** | Every club signs veterans off the street during the year, most weeks |
| Injured-reserve placements | **0** — mechanic absent | Roughly 12–20 per club; since 2023 a club may return up to 8 players from IR (minimum 4 games missed) |
| Waiver claims that move a player | **0** | Dozens league-wide every cutdown weekend and throughout the season |
| Trades | ≈ 0.6 in-season, ≈ 1.0 offseason | ≈ 1.5 per club per league year *(Trade audit §2.1)* |
| Head-coach changes | 0.145 (3–6 across 31 clubs) | ~0.20 (5–8 across 32) — **the one well-calibrated number in this table** |

The cleanest single statistic: in a recent NFL season roughly **1,900 different players appear in at least one
regular-season game**, against **32 × 53 = 1,696** active-roster spots. That surplus of ~200 men is what
in-season churn *is*. In this game the surplus is 25 practice-squad poaches, and every one of them is a lateral
move between existing rosters — the league's player population is fixed from the day camp breaks.

## 4.2 Injury response

Real NFL clubs lose starters constantly and are built around replacing them. In recent seasons **60–68
different quarterbacks have started a game** — about two per club — and the entire "next man up" apparatus
(elevation, IR, street signing, deadline rental) exists to serve exactly that. In this game:

- a hurt starter **keeps starting** (Part 3, link 5);
- if he did not, the man behind him would be chosen by raw overall with no depth chart (link 3);
- the club would not sign a replacement (link 4);
- and the result would be a random number regardless (link 7).

The game's own weekly injury rate — **2.5 per club per season** — is itself far below a real NFL club's
double-digit count of players missing at least one game, which the prior injury audit already establishes.
This report adds that it does not matter what the rate is while link 5 is broken.

## 4.3 August

Every NFL club plays three preseason games with real injury exposure and a real roster decision at the end of
them. In this game, **one club** does. The other 31 read a shuffled random scoreboard
(`PreseasonEngine.swift:722-742`) and take zero injury rolls.

## 4.4 Where the game is genuinely at NFL scale

Retirement and un-retirement, the coaching carousel and staff market, compensatory picks, the UDFA market,
the March free-agent market, the trade market's *stance* model, and the offseason development pass are all
league-wide, all active, and several are well-calibrated. The AI club is not a stub — it is a fully modelled
front office that is only allowed to work five months a year.

---

# PART 5 — RANKED VERDICT

Ranked by how much each distorts the league the user is actually playing in.
**[BUG]** = the code does not do what its own comments or obvious intent say. **[DESIGN]** = it works as
written and the design is wrong or missing.

| # | Finding | Target | Class |
|---|---|---|---|
| **1** | **An AI club makes ≈1.4 roster moves a season and cannot promote its own practice-squad player.** The only injury-driven AI routine in the game builds its board with `leagueSquad(excluding: suitor.id)`, so a club with the right man on its own 16-man squad signs somebody else's or nobody. Own-squad elevations per AI club per season: **0**, against a real NFL mechanic (2 per game, 3 per player per season) that is the default response to an injury. Volume is 1.40/week league-wide ⇒ 0.81 per club per season. | `PracticeSquadEngine.swift:911` (the exclusion), `:171-179` (the volume), `signToActiveRoster:748` (the door that already works) | **BUG** (the exclusion) + **DESIGN** (the volume) |
| **2** | **The injury-to-lineup chain is severed at the roster filter, for every club in the league.** Both simulators filter `isHoldingOut` and not `isInjured`; `SimPlayer` has no injury field; the play simulator picks `max by overall`. An injured starter plays every snap. The preseason path does it correctly two files away. | `GameSimulator.swift:130-131`; `LiveGameEngine.swift:1283-1284` + `sidelinedIDs:696-700`; `PlaySimulator.swift:2328`; `MatchupResolver.swift:26,60`; correct version at `PreseasonEngine.swift:332-333` | **BUG** — *(extends Gameday #9 with the coached path and the ledger split)* |
| **3** | **Two ledgers disagree about who started.** `startingLineupIDs` credits the backup with a start and denies the injured man a game played (`:1420-1428`), while `accumulateSeasonStats` (`:7109`) books the injured man's box score with no guard. A season can end with 0 games played and 3,000 passing yards, and `PlayerSeasonHistory` snapshots both. | `WeekAdvancer.swift:1420-1428` vs `:7109-7117`; snapshot at `recordSeasonHistory:7040` | **BUG** |
| **4** | **The AI's deadline need model is injury-blind, so a club with a hurt QB never goes to get one.** `needProfile` fills starter slots from `ranked.prefix(slots)` with no `isInjured` filter, while `PracticeSquadEngine.shorthandedPositions` — answering the same question — does filter. Two need models, one blind. | `TradeValueEngine.swift:746-780` (esp. `:748`, `:761`) vs `PracticeSquadEngine.swift:1029-1037` | **BUG** |
| **5** | **31 clubs have no August.** The preseason slate, its injuries, its scheme snaps and its camp verdicts are all `career.teamID`-gated; the AI opponent's fatigue and morale are explicitly restored so the game "costs the league nothing"; the other 30 clubs get a shuffled random scoreboard. `INJURY_SYSTEM_ANALYSIS.md:19` describes this as a league-wide injury path — it is not. | `PreseasonEngine.swift:174-181` (`drawSlate` guard), `:321-323`, `:352-360`, `:385-393`, `:402-408`, `:722-742` | **DESIGN** (+ **BUG** in the prior doc's derivation) |
| **6** | **The playoffs are three dead calendar weeks.** No injury roll, no rehab tick, no fatigue, no morale, no development, no training focus, no trade window, no practice-squad pass — all eleven league-wide weekly producers are absent. Only the missing rehab tick was previously logged. | `WeekAdvancer.swift:2726-2807` (whole function) | **BUG** |
| **7** | **AI clubs have no drama layer at all, and the user's is inert.** 13 user-only systems with no AI counterpart (locker room, holdouts, owner satisfaction/goals/whims/firing, camp battles, camp grades, Hard Knocks, FA storylines, life events, opponent prep, game plan, preseason). `EventEngine.applyEventChoice` has **zero callers**, so the ~9–10 events a season the user "gets" apply nothing; `lastEvents`' only consumer is a Bool at `CareerShellView.swift:3008`; no view fetches `FAStorylineEvent`; `docs/LIFE_EVENTS_PLAN.md`'s 347-event catalogue has **zero Swift symbols**. | `EventEngine.swift:144` (dead); `WeekAdvancer.swift:1596-1598`, `:1721`, `:1737`, `:1607`, `:1643`, `:8260`, `:8480`; `FreeAgencyEngine.swift:318-370` | **BUG** (the dead applier) + **DESIGN** (the AI counterpart) |
| **8** | **A late-season injury follows a club into next September on one decrement.** Playoffs tick nothing; the whole 12-phase offseason contains exactly one `processInjury` call, for rostered non-camp-body players only; nothing resets `isInjured` at the season boundary. Derived: **9.6 % of injuries carry over, 0.24 per club, ~7.7 players league-wide open a season hurt** — and the AI cannot sign a replacement for any of them. | `PlayerDevelopmentEngine.swift:1941-1946` ← `WeekAdvancer.swift:3971`; `startNewSeason:1004-1226` (no reset) | **BUG** |
| **9** | **Injured reserve does not exist.** `RosterStatus` has three cases and none is IR. The only "Place on IR" in the repo is an `EventOption` whose payload is four morale integers and whose applier is dead. Every club carries its injured men on the 53 for the full absence, against a real rule that returns roster spots and a real usage of 12–20 placements a club a year. | `Player.swift:663-680`; `EventTemplates.swift:396` | **DESIGN** |
| **10** | **No depth chart reaches any engine, and no AI club can have one.** `Career.depthChartData` is a single blob on the *career* — there is no per-`Team` field in the schema. Four readers, all UI, zero engine. `startingLineupIDs` (the injury-aware one) is consulted by the development and attendance passes and by nothing that decides a game. | `Career.swift:46`; `DepthChartView.swift:260,271`; `CareerShellView.swift:1424,2779`; `ScheduleView.swift:97`; `WeekAdvancer.swift:6976` | **BUG** *(re-states Gameday #9; the schema half is new)* |
| **11** | **No AI in-season free agency, in any week of any season.** Verified by reading `advanceRegularSeasonWeek` end to end: not one `FreeAgencyEngine` call. Every AI signing entry point is reachable only from `.freeAgency` or a user screen. A club that loses three corners in week 5 signs nobody. | `WeekAdvancer.swift:1265-2497` (absence); `FreeAgencyEngine.swift:823, :863, :909, :1526, :2334` (all callers) | **DESIGN** |
| **12** | **Waivers produce no transaction, and AI cuts never reach the wire.** `processWaivers` writes `claimedByTeamID` and never `player.teamID`; `trimAIRosters` files no `RosterCut` row (no `ModelContext`), and the `.isCampCutdown` filter would drop it anyway. The wire runs once a year over one club's cuts. | `WaiverWireEngine.swift:69-79`; `WeekAdvancer.swift:8525`, `:6851-6859`; `CapManagementEngine.swift:733-737` | **BUG** *(confirms `REBUILD_VIABILITY_ANALYSIS.md` rec #13)* |
| **13** | **The AI's situational-response machinery is real but keyed to a signal with no information.** `TeamStance` (record ×3.0, core talent, core age × sign of record, cap room) is the best situational model in the codebase — and `team.wins` for 31 clubs is `Int.random`. Every buyer/seller decision in the league is made about a season that never happened on a roster nobody looked at. | `TradeValueEngine.swift:628-676` reading `WeekAdvancer.swift:8186` | **DESIGN** — blocked on Gameday #1 |
| **14** | **Zero-caller census (this audit's new entries).** `RosterCutEvaluator.recommendCuts` (the purpose-built cut evaluator with the depth guard — `trimAIRosters` uses `keepScore` instead); `RosterCutEvaluator.isPracticeSquadEligible` (`yearsPro <= 2`, a **second, incompatible** definition next to the live `PracticeSquadEngine.isSquadEligible`); `RosterCutEvaluator.integrityViolations`; `EventEngine.applyEventChoice`; `HoldoutEngine.detectHoldoutCandidates`; `RevengeTourEngine.markCut`/`hasActiveGrudge`/`performanceModifier` (grudges never affect a snap); `LoyaltyEngine.loyaltyDiscount`; `CommunityImpactEngine.civicTierBonus`; `MentorPairEngine.protegéDiscount`; `CoachReunionMatcher.reunionDiscount`/`reunionLoyaltyBonus`; `OwnerSatisfactionEngine.generateJobOffers`; `OwnerGoalsEngine.seasonFacts`; `CoachMarketEngine.attritionChance`/`hiringScore`; `CampGradeEvaluator.scoreFor`; `HardKnocksNarrator.storyTemplate`; **all eight `CoachRelationshipEngine` harmony/friction functions** (`:44, :100, :138, :157, :334, :357, :371, :387`) — staff friction fires for nobody. | as listed | **BUG** |
| **15** | **`.reviewRoster` is a no-op for 31 clubs**, and `.proBowl` nearly so. One of twelve offseason advances does nothing for anyone but the user; awards are one rating-proxy MVP with no All-Pro, ROY, OPOY/DPOY or Coach of the Year, and no award affects morale, price, retirement or mood for any player. | `WeekAdvancer.swift:3739-3760`; `:3063-3133`; `recordSeasonSummary:6144` | **DESIGN** |

## What is genuinely good and should be protected

The March-to-August organism. `processPlayerRetirements` / `processComeback` / `processWashouts` are
league-wide and well-shaped. `CoachCarouselEngine.runBlackMonday` plus `refillAIStaffVacancies` plus
`CoachMarketEngine.settleUnemployment` is a closed, bounded, correctly-sized coaching economy — 0.145 firings
per club per season against a real ~0.20 — and its bench-first hiring fixed an unbounded-population bug the
right way. `UDFAMarketEngine` and `CompensatoryPickEngine` are properly league-wide. `TeamStance` is the best
piece of situational reasoning in the repo. `PracticeSquadEngine.runWeeklyPass` is the correct *shape* for an
in-season response system — it reads availability, prices need against the same table the FA market uses,
opens a roster spot, and charges the cap. Everything item #1 asks for is a small edit to a board that already
exists.

## If only one thing is fixed

**`PracticeSquadEngine.swift:911`.** Include the suitor's own squad in the board and let a club elevate its own
man. It is one clause, it turns the game's only injury-aware roster routine into an actual next-man-up
mechanic, and it is the single cheapest step from "31 disconnected offseason routines" toward "31 clubs
that respond to what happens to them." Then #2 — filter `isInjured` at `GameSimulator.swift:130-131` and
`LiveGameEngine.swift:1283-1284` — so that the man who was promoted has a reason to exist.

---

## APPENDIX — arithmetic and measurement notes

All rates in this report are derived analytically from the shipped constants; the derivations are shown inline
in §1.1.1 and Part 3 link 8. The reproduction script for the carry-over figures:

```python
bands = {'hamstring':(1,4),'ankle':(1,6),'knee':(4,16),'shoulder':(2,8),'concussion':(1,3),
         'back':(2,6),'foot':(2,8),'groin':(1,4),'wrist':(1,4),'ribs':(1,4)}   # InjuryType.swift:20-30
mod = 1 - 60/400 - 60/660        # MedicalEngine.recoveryWeeks:151-165, league-average physio+doctor
# effective weeks = max(1, int(base*mod)); injury week uniform 1..18;
# ticks available = (18-w) regular-season + 1 offseason (PlayerDevelopmentEngine:1941)
# → P(carry) = 0.0960, residual = 0.256 wk/injury, × 2.50 injuries/club = 0.24 carried, 0.64 wk
```

**Harness note.** `tools/balance-harness` was not usable for this audit: `./run.sh career` fails at compile,
with `CareerScenario.swift` referencing `CoachingEngine.schemeFitFamiliarityPivot`,
`schemeFitTraitGain`, `schemeFitFamiliarityGain`, `VersatilityDevelopmentEngine.earlyCareerLearnMultiplier`
and `ContractEngine` symbols the staged slice does not carry, plus
`input file 'PracticeSquadExtract.swift' was modified during the build`. Engine sources were being edited
concurrently, so this was not investigated further. Per the harness README the `career` scenario's practice-
squad block is in any case a **shadow** — *"no player is mutated"* — so the shipped practice-squad path,
which is the subject of finding #1, has never had rig exposure. Nothing in this report depends on a harness
run; every number is derivable from the constants cited.
