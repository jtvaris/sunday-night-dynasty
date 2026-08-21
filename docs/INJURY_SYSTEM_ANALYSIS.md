# C2 — Injury, Recovery & Durability: Implementation Audit and Realism Assessment

**Scope:** read-only analysis of `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty`, engine under `dynasty/dynasty/Engine`.
**Date:** 2026-08-14. **Branch:** `feat/skeletal-mocap-players` @ `3423d35`.
**Deliverable:** assessment only. No fixes, no code changes proposed as edits.

---

# PART 1 — HOW IT WORKS TODAY

## 1.1 The map: every place an injury can be created

There are exactly **three** live injury-creation paths in the shipped game, plus one that only exists in the balance harness.

| # | Path | File:line | When | Granularity |
|---|------|-----------|------|-------------|
| 1 | Weekly quick-sim roll | `Engine/Simulation/WeekAdvancer.swift:1799-1842` | Once per regular-season week advance | 1 roll per active-roster player per week |
| 2 | Live coached game, per-play | `Engine/Match/LiveGameEngine.swift:3116-3169` (call sites `:3096-3109`) | Every contact play of a coached game | 1 roll per contact involvement (ball carrier + tackler) |
| 3 | Preseason exhibition | `Engine/Simulation/PreseasonEngine.swift:640-711` | Once per preseason game (3 per season) | 1 roll per dressed player, scaled by snap share |
| — | **Harness-only** model | `Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:1658-1728` (`checkForInjury`) | Never in the app — only `tools/balance-harness/driver/CareerScenario.harness.swift:1777` | 1 roll per player per game |

Path 4 (rookie carry-in) is not a roll but a transfer: `Engine/Draft/DraftEngine.swift:409-430` (`carryPreDraftInjury`) converts a scouted pre-draft medical concern into a live injury for a drafted rookie, using `ScoutingEngine.applyPreDraftAttrition` (`Engine/Scouting/ScoutingEngine.swift:4661-4680`, ~2 % of the declared class).

**Paths 1 and 2 are mutually exclusive per team-week.** `LiveGameEngine.persist` registers both clubs in `WeekAdvancer.liveGameInjuryTeamIDs` (`LiveGameEngine.swift:2749`) and the weekly loop skips them (`WeekAdvancer.swift:1801`). This is deliberate anti-double-count parity and it works.

### Places injuries are NOT created (but a reader would expect them to be)

- **Training camp.** `WorkloadEngine.injuryRiskPct` (`Engine/Camp/WorkloadEngine.swift:146-151`) computes a daily camp injury percentage. Its **only caller in the entire codebase is a SwiftUI label** — `UI/Camp/TrainingPlanView.swift:371`. No camp practice ever injures anybody. The camp workload system's only teeth are (a) a multiplier on the *in-season* roll and (b) a halving of camp training gains for `.burnedOut` (`TrainingPlanEngine.swift:47-49`).
- **Hard Knocks "campInjury" story.** `Engine/Camp/HardKnocksNarrator.swift:117-122` prints "*X Injured in Camp — staff are evaluating*". Pure narration; no engine effect.
- **The `freakInjury` random event.** `Engine/Event/EventTemplates.swift:428-448` has two full templates ("freak injury during routine drill", "injures hand in bizarre off-field accident"). `EventEngine.applyEventChoice` (`EventEngine.swift:144-173`) applies **only** morale / owner satisfaction / coach reputation. The player is never injured. Same for `suspension` and `arrest` — no availability effect whatsoever.
- **`injurySetback` / `aheadOfSchedule` events.** Selected only when someone is already rehabbing (`EventEngine.swift:209,216`), and again apply only morale. They do not move `injuryWeeksRemaining`.
- **Playoffs.** `advancePlayoffWeek` (`WeekAdvancer.swift:2726+`) contains no injury roll and no rehab tick. Quick-simmed playoff weeks neither injure nor heal. (Known and logged: `TODO.md:2008`.) A *coached* playoff game still rolls per-play injuries via path 2, so the user's own team is the only club that can be hurt in January, and nobody heals.
- **Offseason.** The only offseason tick is one decrement inside `PlayerDevelopmentEngine.processOffseason` → `processInjury` (`PlayerDevelopmentEngine.swift:1941-1946`, called once per offseason from `WeekAdvancer.swift:3967`). A player who ends the season 10 weeks from clearance enters next Week 1 **9 weeks from clearance**. Nothing anywhere resets `isInjured` at a season boundary (verified across `startNewSeason`, `WeekAdvancer.swift:1036-1110`).

---

## 1.2 The probability model

### The one real formula — `MedicalEngine.injuryCheck`
`Engine/Medical/MedicalEngine.swift:29-86`

```
risk = 0.005                                    // base, "per play" in the doc comment,
                                                // actually per player per WEEK in path 1
     × frequencyMultiplier                      // league setting: off 0.0 / low 0.5 / normal 1.0
     × (1 + max(0, fatigue − 50) / 50)          // fatigue 100 → ×2.0
     × (1 − durability / 200)                   // dur 40 → ×0.80, dur 99 → ×0.505
     × (1 − doctor.playerDevelopment / 330)     // doctor 99 → ×0.70
     × rushBackRiskMultiplier(trainer)          // ×1.5 … ×1.1, only while rushBackWeeksRemaining > 0
     × workloadStatus.injuryMultiplier          // healthy/underloaded 1.0, overloaded 1.6, burnedOut 2.5
     × facilityRiskMultiplier                   // medical wing tier: 1.06 / 1.00 / 0.92
```
Roll: `Double.random(in: 0...1) < risk`.

**Inputs it does NOT contain:** position, age, snap count, play type (the `playType:` parameter is accepted and never read — every caller passes `.run` with a comment saying so: `WeekAdvancer.swift:1812`, `PreseasonEngine.swift:661`), body size, injury history (history affects *type*, not *rate*), or games already played.

### Live per-play twin — `LiveGameEngine.checkInjury`
`LiveGameEngine.swift:3116-3143`. Same shape, base `perPlayInjuryRisk = 0.003` (`:681`), calibrated in the doc comment to match the weekly aggregate (~90 involvements per team per game × 0.003 ≈ 53 × 0.005). It applies fatigue, durability, doctor, workload and facility — but **not** the `frequencyMultiplier` league setting and **not** the rush-back multiplier (it reads `rushBackWeeksRemaining` only for a UI flag at `:523`). It has a safety valve: never bench a side below 12 available (`:3122`).

### Preseason
`PreseasonEngine.rollInjuries` (`:640-711`) calls the exact same `injuryCheck` with
`frequencyMultiplier = career.injuryFrequency.riskMultiplier × preseasonInjuryScale (0.45, :136) × snapShare(player)`, where a starter's share is `0.35` (`:105`). Derivation is documented at `:123-136` and the design target was "worst case +7.5 % season-total injuries".

### Star / user-player special-casing
**None on the rate side.** No branch anywhere treats the user's team, a starter, or a high-OVR player differently in `injuryCheck`. The asymmetries that exist are:
- Star injuries (OVR ≥ 85) generate a `NewsItem` (`WeekAdvancer.swift:1828-1840`).
- Rehab inbox nudges fire only for the user's club and only for OVR ≥ 78 or ≥ 4-week injuries (`WeekAdvancer.swift:2035-2054`).
- The rush-back decision is generated for the user only; "AI teams never rush players back" (`WeekAdvancer.swift:2056-2058`).

### Measured expected rates (analytic, from the shipped constants)

League-average player: durability ≈ 72 (see §1.4), doctor `playerDevelopment` ≈ 60, workload `.healthy`, facility tier 2, fatigue 0 (see the dead-term note below).

```
risk/player/week = 0.005 × 1.00 × 0.64 × 0.818 ≈ 0.00262
per team-week    = 53 × 0.00262             ≈ 0.139 injuries
per team-season  = × 18 weeks               ≈ 2.5 injuries
```
Plus preseason: 3 games × 0.45 × snap share ≈ 0.47 roll-equivalents for a full-tilt starter, ~+0.3–0.7 injuries per team-season at the club level.

**Average absence** (§1.3 below) ≈ 3.0 weeks after staff modifiers ⇒ **≈ 7–9 team-games lost per team per season.**

> **The weekly roll population is the 53-man active roster only.** Practice-squad players carry `teamID == nil` (`PracticeSquadEngine.swift:1051-1053` states this explicitly), so the `player.teamID != nil` guard at `WeekAdvancer.swift:1799` excludes them. Practice-squad players can never be injured.

### Two dead terms in the shipped weekly roll

1. **Fatigue is always exactly 0 at the moment the injury is rolled.** `advanceRegularSeasonWeek` adds `Int.random(in: 3...8)` fatigue at step 5 (`:1781-1784`), then subtracts `MedicalEngine.weeklyFatigueRecovery` — a minimum of 15, typically 20-25 — at step 5b (`:1787-1792`), *then* rolls injuries at step 6 (`:1799`). `max(0, …)` floors it. So `1 + max(0, fatigue − 50)/50` is **always 1.0** in the quick sim. The fatigue→injury link only exists inside a coached game, where `SimPlayer.fatigue` accumulates during the game.
2. **Workload is a camp-time constant.** `cumulativeLoad` is reset at OTAs (`WeekAdvancer.swift:8248-8252`) and ticked only during camp/preseason phases (`applyCampWeeklyTick`, `:8237+`). Whatever status a player carries out of preseason multiplies his injury risk for **all 18 weeks** and never changes. There is no in-season load model. The AI league tick lands rosters in `.healthy` by default, so ×1.0 for essentially everyone except a user who deliberately over-cranks the camp slider.

---

## 1.3 Taxonomy, severity and recovery

### Types — `Domain/Enums/InjuryType.swift`

Ten cases, no sub-types, no grades, no laterality, no body-part hierarchy:

| Case | Display | `baseRecoveryWeeks` | `severity` (1-5) |
|---|---|---|---|
| `.hamstring` | Hamstring | 1…4 | 1 |
| `.ankle` | Ankle Sprain | 1…6 | 2 |
| `.knee` | Knee (MCL/ACL) | 4…16 | 4 |
| `.shoulder` | Shoulder | 2…8 | 3 |
| `.concussion` | Concussion | 1…3 | 1 |
| `.back` | Back | 2…6 | 2 |
| `.foot` | Foot | 2…8 | 2 |
| `.groin` | Groin | 1…4 | 1 |
| `.wrist` | Wrist/Hand | 1…4 | 1 |
| `.ribs` | Ribs | 1…4 | 1 |

**There is no severity roll.** `severity` is a **constant per type** (`InjuryType.swift:31-38`), and it is read in exactly two places: the durability-erosion branch in `applyInjury` (`MedicalEngine.swift:239`) and the pre-draft "pick the worst concern" comparator (`ScoutingEngine.swift:4651-4652`). Severity does not gate anything else — not the recovery draw, not IR, not news, not UI.

The only stochastic severity element is the **uniform draw inside the type's week band**: `Int.random(in: injury.baseRecoveryWeeks)` (`MedicalEngine.swift:149`). A knee is uniform on 4…16 weeks — there is no ACL/MCL distinction, no long tail, no season-ending category, and **no injury can exceed 16 weeks × facility multiplier** (max ≈ 17 weeks at a tier-1 recovery centre with no staff).

### Type selection

- **Weekly + preseason path:** `weightedInjuryType(for:)` (`MedicalEngine.swift:115-130`). With no history, a **uniform random pick among all 10 types**. With history, each prior occurrence of a type adds +60 % weight, capped at 2.5× per type. Total incidence unchanged — the doc comment is explicit that this only redistributes types.
- **Live game path:** `InjuryType.allCases.randomElement()!` (`LiveGameEngine.swift:3145`) — **uniform, ignores history entirely.** The recurrence model does not exist in coached games.
- No positional weighting anywhere. A kicker is as likely to tear a knee as a running back; a lineman is as likely to pull a hamstring as a corner.

### Recovery timeline — `MedicalEngine.recoveryWeeks` (`:143-167`)

```
base     = Int.random(in: type.baseRecoveryWeeks)
modifier = 1.0 − physio.playerDevelopment/400 − doctor.playerDevelopment/660
modifier ×= facilityRecoveryMultiplier      // recovery centre: 1.08 / 1.00 / 0.90
weeks    = max(1, Int(base × modifier))
```
Elite physio (99) + elite doctor (99) + tier-3 recovery centre ⇒ `(1 − 0.2475 − 0.15) × 0.90 = 0.542` — **a 46 % reduction in every absence.** That is a *larger* effect than the entire durability attribute range has on frequency.

### Weekly rehab with variance — `processWeeklyRehab` (`:279-317`)

Called once per injured player per regular-season week (`WeekAdvancer.swift:2031-2033`). Rolls:

- `aheadChance = max(0.02, 0.10 + trainer.playerDevelopment × 0.001 + facilityShift)` → **−2 weeks**
- `setbackChance = max(0.02, 0.10 − trainer.playerDevelopment × 0.0006 − facilityShift)` → **0 weeks progress**, and with 30 % probability **+1 week added back** — but never past `injuryWeeksOriginal` (`:301-304`)
- otherwise on-track → **−1 week**

With no trainer: 10/80/10 ⇒ expected 1.0 weeks/week, i.e. parity with the legacy deterministic path. Elite trainer: ~20 % ahead / ~4 % setback ⇒ expected ≈ 1.16 weeks/week.

`RehabStatus` (`Domain/Models/Player/InjuryRecord.swift:35-55`) is explicitly documented as "purely informational — the weeks counter itself is the source of truth". **A setback can never make an injury longer than its original prognosis.**

### Return-to-play, partial fitness, re-injury

- **No partial fitness on return.** `clearInjury` (`MedicalEngine.swift:330-336`) zeroes everything; the player is instantly at 100 % of his rating. No ramp, no snap limit, no rating haircut. `SimPlayer` (`Engine/Simulation/SimPlayer.swift:43-56`) carries no injury or conditioning field at all.
- **Rush back** (`MedicalEngine.rushBack`, `:322-327`) is the *only* partial-fitness mechanic: clears the injury one week early, sets `rushBackWeeksRemaining = 2`, and adds `+15` fatigue. The fatigue hit evaporates in one week (weekly recovery ≥ 15) and, per the dead-term note above, has no injury consequence in the quick sim anyway. The real cost is the ×1.1–1.5 re-injury multiplier for 2 weeks.
- **Re-injury risk is otherwise flat.** Once cleared normally, a player who has torn a knee three times carries exactly the same weekly hazard as a rookie who has never missed a snap — only the *type* he next suffers is skewed. There is no elevated-risk window after a normal return.
- **Recurrence → permanent durability loss:** `applyInjury` (`:236-242`) — on a repeat of the same type, 25 % chance of −1 durability, and −2 only when `severity ≥ 4` *and* the same roll < 0.06 (≈ 6 % of recurrences). Deliberately tiny.
- A second, **divergent** permanent-damage rule lives in the legacy `PlayerDevelopmentEngine.processInjury` (`:1641-1647`): **15 % chance of −1…−5 durability on healing**. This runs once per offseason for any player still injured at camp, and is the model the balance harness uses every week. It is flagged as unreconciled legacy at `TODO.md:2010`.

### IR / PUP / roster mechanics

**They do not exist.** `RosterStatus` (`Domain/Models/Player/Player.swift:663-678`) is `active | practiceSquad | campBody`, with an explicit doc comment at `:657-662`:

> *"The NFL's injured-reserve / PUP / exempt lists are separate mechanics the game models through `isInjured` + `injuryWeeksRemaining`, so adding them here would give the same state two spellings."*

Consequences:
- An injured player **occupies a 53-man spot for the whole absence**. There is no relief valve, no 4-game minimum, no return designation, no roster exemption.
- There are **no game-day designations** — no Questionable / Doubtful / Out, no practice-participation report (DNP/Limited/Full). `isInjured` is a binary. Grep for `questionable`/`doubtful` across `dynasty/` returns only unrelated scouting-report strings.
- There is **no season-ending flag**. The longest possible absence is ~16-17 weeks, and it simply runs the clock.
- The only roster reactions to injury are: `RosterCutEvaluator` keep-score penalty of −6.0 (`Engine/Camp/RosterCutEvaluator.swift:289`), `WaiverWireEngine` claim-priority bump of +8.0 for shorthanded clubs (`:95`), `PracticeSquadEngine.shorthandedPositions` counting the available roster (`:1029-1039`), and trade-value gating (`TradeValueEngine.swift:2027, 2469, 2521, 2634`).

---

## 1.4 The durability attribute

### Definition and distribution

- Declared: `Domain/Models/Player/PlayerAttributes.swift:11` — `var durability: Int`, one of six `PhysicalAttributes`.
- **League generation:** `PositionPhysicalProfile.swift:60` — `durabilityPrior = Prior(72, 9)`, i.e. **N(72, σ=9), position-independent** (`:58` says so explicitly). Drawn Gaussian with soft ceiling and clamping (`:195-213`). Realistic spread ±2σ ⇒ **≈ 54 … 90**.
- Legacy uniform path: `PlayerAttributes.random()` (`:20`) draws `Int.random(in: 40...99)`. Used by the older/random generator and by harness fixtures.
- Durability is counted in `PhysicalAttributes.average` (`:25`), so it feeds team/positional physical composites even though it is a purely medical trait.

### Every place durability is read

| Site | Effect |
|---|---|
| `MedicalEngine.swift:47` | `risk ×= 1 − dur/200` — **the shipped frequency lever** |
| `LiveGameEngine.swift:3126` | identical term in coached games |
| `PlayerDevelopmentEngine.swift:1666` | `injuryChance += (99−dur)/99 × 0.03` — **harness-only** model |
| `WorkloadEngine.swift:148` | `durabilityFactor = (99−dur)/99 × 0.4 + 1.0` — **UI label only** |
| `MedicalEngine.swift:240` | recurrence erosion, −1 (or −2) |
| `PlayerDevelopmentEngine.swift:1466` | age regression: `−(0…1) − 2 if injured`, once per offseason past peak |
| `PlayerDevelopmentEngine.swift:1645` | legacy heal-damage, −1…−5 at 15 % |
| `TrainingPlanEngine.swift:70-73` | camp physical training can **raise** durability |
| `PlayerRetirementEngine.swift:155` | `dur < 50` → +0.08 retirement chance |
| `PlayerRetirementEngine.swift:649, 662` | injury-toll shock-retirement gate (`dur ≤ 58`) and burden score |
| `ContractEngine.swift:2223-2224` | `p = 0.55 + 0.003 × (dur − 70)` — a contract-related probability |
| `DraftEngine.swift:848` | scaled with the rest of a prospect's attributes |
| `ScoutingEngine.swift:527, 598, 2152, 2176` | scouting strength/weakness blurbs ("Durable, rarely misses time" / "Injury concerns") |
| `CareerScenarioApplier.swift:191` | scenario shift |
| `ProspectDetailView.swift:2564`, `ProspectListControls.swift:632` | fog rules — durability is a *hidden* attribute with no fog-safe source |
| `PlayerDetailView.swift:2247-2256, 2704`, `PlayerRowView.swift:512` | display |

### **Effect size — the headline number**

`risk ×= 1 − durability/200`. Evaluated across the actual generated distribution:

| Durability | Multiplier | vs. league mean (72) |
|---|---|---|
| 54 (−2σ) | 0.730 | **+14 %** more injury-prone |
| 63 (−1σ) | 0.685 | +7 % |
| **72 (mean)** | **0.640** | — |
| 81 (+1σ) | 0.595 | −7 % |
| 90 (+2σ) | 0.550 | **−14 %** less injury-prone |
| 40 (theoretical floor) | 0.800 | +25 % |
| 99 (theoretical cap) | 0.505 | −21 % |

Translated into what a user can observe: at ~2.5 injuries per team-season, a roster of 90-durability iron men suffers **≈ 2.2** injuries/season and a roster of 54-durability crystal **≈ 2.9**. Over a 17-game season that is a difference of roughly **two team-games lost**. For an individual player it is the difference between a 4.2 % and a 5.6 % chance of getting hurt at all in a given season.

**Verdict: durability is, in practice, not a meaningful attribute.** It is:
- weaker than the team doctor (30 % swing),
- far weaker than the physio+facility recovery stack (46 % swing on absence length),
- weaker than the camp workload status (60–150 % swing),
- and it has **zero** influence on severity or on recovery speed.

Note also the sign asymmetry: the mean multiplier is 0.64, which means the durability term is quietly acting as a **flat ×0.64 global rate reducer** more than as a differentiator. Removing durability from the formula entirely and re-basing the constant to `0.0032` would change league-wide behaviour almost imperceptibly.

---

## 1.5 Age, position and career-long wear

### Age
- **The shipped injury model has no age term at all.** A 22-year-old and a 37-year-old at equal durability roll identical dice.
- Age enters only indirectly and slowly, via `applyAgeRegression` (`PlayerDevelopmentEngine.swift:1461-1468`): once per offseason past peak, `durability −= Int.random(in: 0...1) + (isInjured ? 2 : 0)`. Expected ≈ −0.5/yr healthy, −2.5/yr if rehabbing at camp. Four years past peak ⇒ ≈ −2 durability ⇒ ≈ **+1.6 % injury risk**. Invisible.
- The **harness-only** `checkForInjury` *does* have an age term (`+0.005 per year past peak`, `:1674-1677`) — so the balance harness models an age curve the game does not ship.

### Position
- **No positional differentiation anywhere.** Not in rate (no position read in `injuryCheck`), not in type (uniform / history-weighted only), not in recovery, not in the durability prior (explicitly position-independent, `PositionPhysicalProfile.swift:58`).

### Career-long wear — what *does* accumulate
This is the genuinely good part of the system.
- `Player.injuryHistoryData` (`Player.swift:530-562`) persists `[InjuryRecord]` for life — type, weeks out, season, week. Nothing ever clears it (verified in the `startNewSeason` audit, `TODO.md:1825`).
- Recurrence weighting makes a body part become a player's signature problem (`MedicalEngine.swift:115-130`).
- Recurrence erodes durability (`:236-242`), which in turn slightly raises future risk and materially raises retirement probability.
- **Retirement** (`PlayerRetirementEngine.swift:145-156`): `+0.05` per major (≥6 wk) injury capped at 4 (`+0.20` max), `+0.10` if still injured, `+0.08` if `durability < 50`.
- **Shock retirement / "the injury toll"** (`PlayerRetirementEngine.swift:614-663`): a player *inside* his peak window, age 25-32, `yearsPro ≥ 4`, `durability ≤ 58`, with ≥ N major injuries and ≥ 30 career weeks out, and whose motivation is not money/fame, can retire early. This is a genuinely well-designed narrative mechanic. But note: at ~2.5 injuries per team-season, **accumulating 30 career weeks out is extremely rare** — a player would need roughly 10 injuries across a career that only rolls ~0.05 injuries per player-week. The harness's own metric line (`CareerScenario.harness.swift:2618-2619`) reports "injury-toll swaps per league-season", and it is measuring the *hot* harness model, not the shipped one.
- **Development cost:** `healthFactor` (`PlayerDevelopmentEngine.swift:788-793`) — still injured at camp, or a ≥6-week injury last season, ⇒ `×0.4` on that offseason's growth. `majorInjuryWeeks = 6` (`:665`). This is the single strongest long-run consequence of an injury in the game and it is well-sourced (`docs/DEVELOPMENT_NFL_REFERENCE.md:119-123`).
- **No chronic conditions, no degenerative flags, no cumulative "wear" counter** other than durability itself. No career games-missed statistic is tracked (grep: none), which `TODO.md:3247` already notes as a wanted UI element.

---

## 1.6 What the coach actually sees and decides

### Surfaces
| Surface | File | What it shows |
|---|---|---|
| Injury Report sheet | `UI/Roster/InjuryReportView.swift` | Return decisions, current injuries (type, rehab chip, "3 of 7 wks", recurrence ×N badge), Elevated Risk section, Medical Staff footer |
| Player detail medical card | `UI/Roster/PlayerDetailView.swift:2159-2262` | Current injury + circular progress, rush-back warning, last 6 history records with recurrence flags, durability rating when clean |
| Roster summary bar | `UI/Roster/RosterSummaryBar.swift:27, 287-288` | injured count |
| Dashboard tile + chip | `UI/Career/CareerDashboardView.swift:1521-1533, 963, 1052` | "N out", opens the sheet |
| Depth chart | `UI/Roster/DepthChartView.swift:755, 1151` | "Nw" badge |
| League rosters (other clubs) | `UI/Roster/LeagueRostersView.swift:948-960` | `HLTH` state slot with weeks remaining |
| Weekly news | `Engine/Media/NewsGenerator.swift:75-78`; star injuries `WeekAdvancer.swift:1827-1840` | injury report headline; OVR ≥ 85 injuries get their own story |
| Inbox | `WeekAdvancer.swift:2039-2054, 2068-2076` | setback / ahead-of-schedule nudges, return-decision action item |
| Preseason recap | `UI/Camp/PreseasonRecapSheet.swift:519-585` | injury count as the "cost" line of the snap-share policy |
| Live game | `LiveGameEngine.lastPlayInjuries` → red banner + player stays down (`TODO.md:2519-2521`) | in-game injury moment |

### Decisions the coach can make
1. **Rush back vs. hold out** — the one real medical decision (`InjuryReportView.swift:97-152`). Offered only in the final rehab week, only for the user, ignoring it is always the safe default.
2. **Preseason snap policy** — rest starters / starter series / full tilt, trading scheme familiarity against injury exposure (`PreseasonEngine.swift:105, 136`).
3. **Camp intensity** — the training plan slider, which sets a season-long workload multiplier.
4. **Hire / pay for staff** — team doctor (frequency), physio (recovery), head trainer (rehab variance).
5. **Facility investment** — medical wing / recovery centre tiers (`FacilityEngine.swift:178-217`).
6. **League setting at career creation** — injury frequency Off / Low / Normal (`GameModeEnums.swift:71-97`).

### Decisions the coach **cannot** make
- Play him at 80 % / limit his snaps. There is no partial-availability state.
- Designate Questionable / Doubtful / Out; there is no game-day inactive list.
- Place on IR to free a roster spot, or activate from IR.
- Hold a healthy star out of a meaningless Week 18 game (the sim doesn't read availability anyway — see §1.7).
- Choose a treatment (surgery vs rehab), second opinion, or specialist.

---

## 1.7 ⚠️ The finding that dominates everything else: **injuries do not affect game results**

Verified by reading the roster construction of every simulation path:

- **`GameSimulator.simulate`** (`Engine/Simulation/GameSimulator.swift:99-135`): `let homeRoster = (homeRosterOverride ?? homeTeam.currentRoster()).filter { !$0.isHoldingOut }`. **Only holdouts are filtered.** The doc comment at `:93-97` states it outright: *"an injured man genuinely does not dress (the regular-season path leaves that simplification alone rather than changing what a shipped season simulates)"* — the injured-does-not-dress rule is applied **only** to preseason, via `homeRosterOverride` (`PreseasonEngine.swift:332-333, 380-381`).
- **`SimPlayer`** (`Engine/Simulation/SimPlayer.swift:43-56`) carries no injury field, so nothing downstream could filter on it either.
- **`LiveGameEngine.init`** (`:1283-1289`): identical — `filter { !$0.isHoldingOut }` only. A player who tore his knee in Week 3 lines up at left tackle in Week 4 of a coached game. (Players injured *during* the live game are correctly removed via `injuredPlayerIDs` and `rebuildFieldUnits`.)
- **The other 15 games each week** are not simulated from rosters at all: `WeekAdvancer.swift:1383` → `simulateGameScore()` → `randomTeamScore()` (`:8186-8214`), a pure random TD/FG bucket draw with a +3 home bump. No team strength, no roster, no injuries.

**Net effect: an injury in this game costs a team nothing on the scoreboard.** Its entire cost is bookkeeping — a games-played credit withheld (`WeekAdvancer.swift:1419`), a depth-chart role reshuffle for development purposes (`:1883`), a −6 roster-cut keep score, a trade-value gate, a `×0.4` offseason development multiplier, and retirement pressure. The user's *perception* of loss (a red badge, a news story) is real; the mechanical loss is zero.

This is the single biggest realism gap in the system and it is upstream of every tuning question below: **raising injury frequency to NFL levels would not make the game harder, only noisier**, until availability is wired into the sim.

---

## 1.8 Persistence and fog

- **Storage:** `Player.isInjured`, `.injuryWeeksRemaining`, `.injuryType`, `.injuryWeeksOriginal` are first-class SwiftData attributes (`Player.swift:116-119`). History is a JSON blob `injuryHistoryData: Data?` with a `[InjuryRecord]` bridge (`:530-562`); `rehabStatusRaw: String?` (`:536`); `rushBackWeeksRemaining: Int` (`:541`). Pending return decisions live JSON-encoded on `Career` (`Career.pendingReturnDecisions`). All additive/optional — safe lightweight migrations, and `docs/SWIFTDATA_MIGRATION_PLAN.md:245` already flags `injuryHistoryData` as a JSON-blob debt.
- **Fog: there is none for injuries.** Injury state is fully symmetric and fully visible.
  - The user sees every AI club's injuries in `LeagueRostersView` (`:948-960`, `HLTH` slot with exact weeks remaining) and in `TradeView`.
  - The AI reads the user's injuries directly off the model — `TradeValueEngine.swift:1815-1818` (trade valuation), `:2027, 2469, 2521, 2634` (target gating), `HoldoutEngine.swift:66`, `WaiverWireEngine.swift:95`.
  - There is no "reported" vs "true" injury state, no misdirection, no league-wide injury report with practice participation.
- **The one place fog does apply is durability, not injuries**: `truePhysical.durability` is a hidden prospect attribute with *no fog-safe source* (`UI/Scouting/ProspectListControls.swift:632-634` — *"nobody measures a man's durability in front of thirty-two clubs"*), surfaced only through scout-report prose (`ScoutingEngine.swift:527, 598`) and a medical-concern flag at `ProspectDetailView.swift:2555-2566`. That is a good design and it is the model the injury system itself should arguably follow.

---

## 1.9 Balance-harness coverage

**The harness does not measure injury rates, and the model it exercises is not the model the game ships.**

- `tools/balance-harness/sync_sources.sh` compiles `InjuryType.swift`, `InjuryRecord.swift`, `PlayerDevelopmentEngine.swift`, `PlayerRetirementEngine.swift` (README `:95-96, 183-184`). **`MedicalEngine.swift` is not one of the synced sources** — the harness literally cannot call the shipped model, and `PlayerDevelopmentEngine.swift:1679-1686` says so in a comment.
- The `career` scenario rolls `PlayerDevelopmentEngine.checkForInjury(p, playIntensity: started ? 0.7 : 0.45)` once per player per week (`CareerScenario.harness.swift:1777`) and ticks recovery with `processInjury` (`:1403, 1761`).
- **That model is ~8× hotter than the shipped one.** For a league-mean player: `0.02 + 0.0082 (durability) + fatigue + age` ≈ `0.0282`, × `0.85` play-intensity ⇒ ≈ **0.024 per player-game** ⇒ ≈ 0.41 injuries per player-season ⇒ **≈ 21 injuries per 53-man team-season**, against the shipped ≈ 2.5. It also has a severity ladder the game does not have: 45 % minor 1-2 wk / 30 % moderate 3-6 / 18 % major 7-16 / 7 % season-ending **17-52 weeks** (`PlayerDevelopmentEngine.swift:1700-1721`).
- **The only injury-adjacent number the harness prints** is `#84 injury-toll swaps: N over M league-seasons` (`CareerScenario.harness.swift:2618-2619`) — a *retirement* metric. There is no injuries/team/season, no games-lost, no type-mix, no recovery-length, and no durability-correlation output anywhere in the driver (`grep -i injur tools/balance-harness/driver/main.swift` → no hits).
- Consequence: every balance conclusion that depends on availability — playing-time share, `healthFactor`, retirement rates, the shock-retirement gate — was calibrated against a league that loses ~21 men a season, while the shipped league loses ~2.5. The `#97`/`#157` work already established the pattern ("the rig's coach model diverged from the shipped one"); **this is the same class of bug, unfixed, in the medical stack.**

---

# PART 2 — REALISM BENCHMARK (real NFL numbers)

> **Measurement warning that governs every comparison below.** Three incompatible universes are in
> play: (1) **NFL/IQVIA official** — preseason + regular season, practices + games, time-loss,
> EHR-sourced; (2) **peer-reviewed EMR studies** (Mack, Herzog, Lawrence) — often adds postseason;
> (3) **public injury-report scrapes** (Dodson, PFR-derived) — undercounts. **Man-games-lost totals
> differ ~2× purely by definition.** Pick one denominator before calibrating the game against any
> of these.

## 2.1 Frequency

### Missed-game injuries per team-season

| Source | Window | Definition | Per team |
|---|---|---|---|
| Ryan et al., *OJSM* 2023 (PMC10399261) | 2017–22, 1,275 games | musculoskeletal, ≥1 game missed | **~27.4** |
| ProFootballLogic | 2015 | missed-game injuries, non-specialists | **27.6** |
| Wegryn (PFR data) | 2024 | distinct injuries, worst teams | SF 56, CLE 51, HOU 47 |

**Central estimate: 27–30 missed-game injuries per team-season; disaster teams 45–56.**

### Core per-player constants (ProFootballLogic 2015 — the most directly sim-usable dataset)
1,794 players (excl. K/P/LS); **688 (38 %) missed ≥1 game**.
- **Injury rate 4.1 % per player-game**
- **Mean 3.1 games missed per injury**
- **64 % of injuries cost ≤2 games**
- **Average availability 14.2 of 16 games (88.75 %)**
- A distinct histogram spike at exactly **7 games missed** — an artefact of the then-current IR
  designated-to-return rule. **Roster rules visibly shape the duration distribution.**

### Rate per 1,000 athlete-exposures (*OJSM* 2023, 2017–22)
- **19.3 injuries / 1,000 AE** overall
- **Playoff teams 18.4 vs non-playoff 19.9** (p < .05); **IR placements 6.8 vs 8.0 per 1,000 AE**
- 17-game 2021: 18.4/1,000 AE and 984 injuries vs 16-game 2017–20 mean 19.7/1,000 AE and 940 —
  **more injuries, lower rate, n.s. (p = .12)**
- **97.7 % of team-games included ≥1 injury.** Lower-extremity injuries per team-game: 0 in 9.5 %,
  1–3 in 61.9 %, **4+ in 28.6 %**

### Man-games lost
- Wegryn 2024, per team: DET 254, CLE 248, MIA 227, SF 226 … **DEN 95 (fewest)**, WAS 112.
  League total ≈ **5,000–5,300**.
- PFL 2015 cross-check (narrower definition): 882 × 3.1 ≈ **2,700**.
- NFL/IQVIA 2023: **700 fewer games missed than 2022** = "two to three fewer players absent from
  each game".
- **Band: ~85–165 man-games lost per team-season; definition dominates the answer.**

### Adjusted Games Lost (Football Outsiders → FTN)
Built from official weekly injury reports, snap-weighted by expected importance; deep backups
contribute ~nothing. **Out or IR = 1.00 AGL/week; Questionable = 0.27 AGL/week** — calibrated
directly from the finding that **27 % of Questionable starters do not play.**

- **League mean 70.2 AGL per team-season, 2009–2022.** Team 14-year means span 53 → 91+ (SD 9.9).
- **Single-season range ~16 to ~191.** 2021 BAL **191.2** is the all-time record; 2024 BAL **16.3**
  the lowest since 2017. 2022 DEN 148.6; 2023 LAR 26.4; 2024 SF 141.2.
- **⭐ Availability predicts results:** in 2024, **6 of the 8 best-AGL teams made the playoffs and
  none of the 6 worst did**. In 2021, 10 of 14 playoff teams sat in the better half.
- **Injury burden is ~92 % noise.** FO's AGL year-to-year team correlation is **r = 0.29
  (R² ≈ 0.084)**. For contrast, team Snap-Weighted Age is r = 0.59 — **age is ~2× as persistent as
  injury luck.** PFF's WAR-Adjusted Injuries Lost reaches the same conclusion.
  *(⚠ snippet-only — footballoutsiders.com is defunct and archive.org unreachable.)*
- Alternative severity metric, SIS **Total Points Lost** 2024: DET 158 … BAL 33 — a **4.8× spread**;
  2025 thru Wk13 a **6.2× spread**.

### IR placements per team-season
**~12–20 placed, 5–8 activated.** NFLPA 2010: 13 % of all injuries resulted in IR, >350 players
league-wide (~11/team). Modern teams routinely exhaust the 8-designation allotment. Franchise
5-season player-*week* totals 2014–18: SEA 1,268 / NE 1,261 … **ATL 446** — a 2.5× spread.

## 2.2 Type mix

**Lawrence, Hutchison & Comper, *OJSM* 2015 — 4,284 injuries, 1,172 players, 2012–14.** The most
robust ratio in the literature:

| Region | Share |
|---|---|
| **Lower extremity** | **61.9 %** |
| Upper extremity | 18.0 % |
| Head / neck | 10.2 % |
| Axial (spine/trunk) | 7.8 % |

**Lower : upper ≈ 3.4 : 1.** NFL/IQVIA independently states 60 % of injuries are lower-body.

| Type | Share |
|---|---|
| **Knee (all)** | **17.8 %** |
| **Ankle** | **12.4 %** |
| **Hamstring** | **8.7 %** |
| **Shoulder** | **8.4 %** |
| **Head / concussion** | **7.0 %** |
| everything else | 45.7 % |

Top 5 = 54.3 %; knee + ankle alone ≈ 30 %.

**Lower-extremity strain composition** (Herzog, *AJSM* 2023 — 5,780 strains, 2015–19): hamstring
**54.7 %**, adductor/groin 24.1 %, calf 12.6 %, quadriceps 8.3 %. **69 % caused time loss; median
12 days missed. One-year risk of ≥1 LEX strain per player: 26.7 %.**

**Concussions** (NFL/IQVIA, preseason + regular season): 2021 **187** · 2022 **213** · 2023 **219** ·
**2024 182 (record low, −17 % YoY)**. Preseason-only: 2017 91 → 2023 58 → **2024 44 (record low)**.
Mack, *Sports Health* 2021 (all settings, incl. postseason): 2015–19 totals 284/255/302/223/238,
**games 80.3 % · in-season practice 17.0 %**. Rates: **1.70 per 10,000 player-plays**, **69.0 per
1,000 player-games**; **one-season per-player risk 7.4 %**, same-season repeat 6.8 %. Preseason
games are **~14 % more concussive** than regular-season (70.6 vs 61.7 per 100 games). Guardian Caps
cut practice concussions **~50 %** for wearers. Concussions concentrate in the **final third** of
the regular season (p = .03).

**ACL:** NFL official **52 in 2023**; EMR studies **62.8/yr (2015–19)** and 47/season (2012–22);
**in-game only 27–42/yr**. **Use 45–63 league-wide across all settings; ~30 in games.** Per-player
one-season ACL risk **1.9 %**. 2025: −25 %, a seven-season low.
**MCL: 132 (2018) → 109 (2019)** — roughly **2–2.5× ACL frequency**. **PCL ~1/season.**
**Achilles 2023: 23 total** (11 regular-season games + 12 preseason/practice); 17-game-era baseline
**20–23**. Concomitant pathology in NFL ACL tears (191 MRIs): additional ligament injury 71 %
(MCL in 57 %), meniscal tear 70 %, bone bruise 95 %.

**⭐ The conditioning experiment — the single most implementable causal finding in the whole
dataset.** The cancelled 2020 preseason (*Arthroscopy Sports Med Rehab* 2022), rates per 1,000 AE:

| Injury | 2018–19 | 2020–21 | p |
|---|---|---|---|
| **All injuries** | 58.17 | **88.57** (×1.52) | < .001 |
| Hamstring | 5.31 | **9.98** (×1.88) | .043 |
| Groin | 2.46 | **5.56** (×2.26) | .007 |
| Calf | 1.61 | **4.08** (×2.53) | .006 |
| Quadriceps | 0.72 | **2.00** (×2.78) | .030 |
| Thigh | 0.30 | **1.23** (×4.10) | .012 |
| **ACL** | 0.68 | 1.19 | .251 **n.s.** |
| **Achilles** | 0.72 | 0.72 | .214 **n.s.** |
| **Pectoral** | 0.42 | 0.93 | .165 **n.s.** |

**Removing the preseason ramp roughly doubled muscle strains while leaving ligament and tendon
ruptures statistically unchanged.** Injuries per team: 48.8 (2018) → 59.3 (2019) → **77.6 (2020)**.

**Contact vs non-contact: no published overall split exists.** Only the non-contact lower-extremity
subset is reported. **Surface:** non-contact LEX per 100 plays — 2022 synthetic 0.048 vs grass 0.035
(+37 %); **2023 0.043 vs 0.042 (+2.4 %)**; 2025 0.43 vs 0.42. Knee ligament tears by surface
2020–23: grass 0.111 vs turf 0.132 per game, **n.s. (p = .379)**. *Honest read: turf is 0–37 % worse
for non-contact soft tissue depending on year and statistically indistinguishable for ligament
tears.*

## 2.3 Position

**Lawrence 2015 — injuries per 100 team-game-positions:**

| Position | Rate | vs OL |
|---|---|---|
| **Wide receiver** | **30.28** | 2.36× |
| Tight end | 27.44 | 2.14× |
| Defensive back | 23.60 | 1.84× |
| Running back | 21.90 | 1.70× |
| Linebacker | 21.48 | 1.67× |
| Defensive line | 15.88 | 1.24× |
| Offensive line | 12.85 | 1.00× |
| **Quarterback** | **12.09** | **0.94×** |
| **Kicker / punter** | **4.88** | **0.38×** |

**6.2× spread. ⭐ QB is one of the *safest* positions per exposure — below OL.** High-profile QB
injuries create an availability bias the data does not support.

**Per-player cross-check (PFL 2015) — rate/game · mean games missed:** RB 5.2 % · 3.9 | TE 4.9 % ·
2.6 | S 4.7 % · 3.0 | WR 4.5 % · 3.2 | CB 4.4 % · 2.9 | LB 4.3 % · 3.0 | DT 4.3 % · 2.9 |
DE 3.9 % · 3.0 | **OL 3.4 % · 3.3** | **QB 2.5 % · 3.1** | FB 1.5 % · 1.8.
**OL has the lowest non-QB rate but the second-longest duration — low frequency, high severity.**

**Concussion by position — rate and count diverge sharply** (Mack 2021, per 10,000 plays):
TE **2.81** (highest rate) · WR 2.34 · DB 2.15 (**227 = 28.7 % of all concussions, largest count**) ·
RB 1.95 · QB 1.63 · LB 1.41 · OL 1.35 · ST 0.98 · **DL 0.79 (lowest)**. 3.6× spread.
**Severity inverts the rate order** — games missed per concussion: **DL 3.97 (worst)** · LB 3.37 ·
TE 3.36 · RB 2.90 · QB 2.77 · WR 2.46 · OL 2.30 · **DB 2.20 (best)**; overall mean **2.76 games**.

**ACL by position** — % of players at that position tearing an ACL over 2010–13 (Dodson, *OJSM*
2016; league baseline **6.0 %**): FB 10.0 · **G 8.6** · WR 8.0 · TE 7.8 · LB 7.5 · RB 6.3 · C 6.2 ·
DB 5.7 · DT 5.4 · DE 3.5 · **OT 3.0** · **QB 2.5**. Significant: receivers 8.0 % ↑ (p = .004),
backs 7.2 % ↑ (p = .035), perimeter linemen 3.3 % ↓ (p = .009).
**⭐ Guards tear ACLs at nearly 3× the rate of tackles** — interior blocking exposes the knee to
multi-opponent contact mechanisms. Special teams has the highest per-play ACL rate: **7.6 per
10,000 plays**.

**Hamstring clustering:** **DB + WR/TE = 63 %** of hamstring injuries; DB alone accounts for **27 %
of all time-loss LEX strains**. SIRs: LB 2.02, DB 1.62, **OL 0.28, DL 0.29**. DBs were also the
most preseason-sensitive cohort (3.4× increase in 2020).

**Special teams:** ST *specialists* have low concussion rates, but **32.7 % of all RB concussions
and 32.3 % of all LB concussions occur on ST snaps** (~70–82 % of those on kickoffs). LEX strain
rate by play type: **punt 14.9 per 1,000 plays** · kickoff 7.5 · pass 4.3 · run 2.6 — **punts are
the most strain-dangerous play type in football.** The 2024 Dynamic Kickoff cut concussion rate
−43 % and kickoff strains −48 % while raising returns +57 %.

**Stingers invert the concussion order** (per 100,000 plays): RB 18.00 · LB 15.87 · DL 14.78 ·
DB 13.74 · TE 12.50 · OL 8.09 · **WR 3.48 · QB 2.61**. 76.4 % miss no additional time; mean 4.79 days.

## 2.4 Age, career and recurrence

### Age → risk. **⚠ The most important nuance in this whole benchmark.**
**No published NFL study gives injury incidence by age bracket.** The best continuous parameter is
amateur football (*KSSTA* 2023, n = 462, reference < 25): **25–29 rate ratio 2.78; 30–46 3.31;
+6.6 % per year of age (male).** Older age is one of the two strongest hamstring risk factors
(**SMD 1.6**, Green, *BJSM* 2020).

**But the direction reverses for ligaments:**
- **ACL preseason rate is HIGHER for players with ≤3 years experience (9.57 vs 5.12 per 1,000
  player-seasons).**
- **100 % of in-season Achilles tears were non-rookies, but rookies were 29 % of preseason tears**;
  rookie Achilles RTP 42.1 % vs non-rookie 62.2 %.
- A 2024 *OJSM* turf study (718 injuries) found **age, position, weather, week and prior injury
  history did NOT influence odds of season-ending surgery.**
- The 2020 soft-tissue spike showed **no significant age difference**.
- NZ Rugby insurance claims 2005–17: ages 21–30 had a **higher** claim probability (57 %) than
  31–40 (47 %).

**Modelling guidance: age raises muscle/tendon risk and does not raise (may lower) ligament-rupture
risk. Model the two separately.** NFL-native age signals are all threshold-based — quad/patellar
tendon tears and biceps/triceps ruptures both flag **age ≥ 26 + BMI ≥ 31**; rotator-cuff RTP falls
sharply **over 30**.

### **⭐ "Injury-prone" as a general trait has no rigorous statistical support.**
No frailty models or overdispersion analyses exist in the reachable literature; one explicit
functional-testing attempt produced a **non-significant model (p = .822)**. What *is* strongly
supported is **injury-type-specific memory**:

| Prior condition | Effect |
|---|---|
| Any previous hamstring strain | **RR 2.7** (p < .001) |
| **Recent** hamstring strain | **RR 4.8** (p < .001) |
| Previous ACL, same leg → hamstring | RR 1.7 (p = .002) |
| Previous calf strain, same leg | RR 1.5 (p < .001) |
| Injury carried into the season | RR 2.10 |
| **Concussion → lower-extremity injury** | **OR 2.28** single, **2.92** multiple |
| Multiple ankle injuries → concussion | aOR 2.87 |
| Post-ACLR thigh muscle injury (2 yr) | RR 1.6; BPTB-graft quad **RR 3.5** |
| Ankle re-sprain | **26 % with prior history vs 11 % without**; 40 % chronic instability |
| Post-concussion all-cause injury | OR 1.93; **recurrent concussion OR 3.06** |

**Recurrence rates:**
- **Hamstring — NFL:** overall recurrence **38.4 %** (2,075 injuries, 2009–20); same-season
  **11.9 %**; **13.4 % when returning within 2 weeks** — the single greatest modifiable risk factor.
  Second large study: **33 % of players reinjured, 27 % of reinjuries same-season**; mean time on
  the injury report **2.4 ± 2.1 weeks**; **team rates 0.6 % (BAL) to 5.7 % (HOU)**. **23 % of
  in-season recurrences occur in the first week back.**
- **ACL — NFL:** draftees with prior ACLR had **25 % recurrent tears vs 9 % in controls (RR ≈ 2.8)**;
  **ipsilateral graft 12 %, contralateral 14 %**; mean time to reinjury **22.1 ± 16.3 months**.
  NFL athletes are **2.4× more likely to retear** than the general population.
- **Concussion:** **~3× multiplier** (OR 3.06); Guskiewicz: ≥3 prior → **3.0×**; **91.7 % of
  within-season repeats occur within 10 days, 75 % within 7.**
- **Achilles re-rupture is low (~1 %)** after modern repair; the real tail risk is **contralateral**.

### Career length and attrition
**3.3 years (NFLPA, everyone who signs) vs 6.0 years (NFL, rookies who made an opening-day
roster)** — a pure denominator artefact. By draft slot: **R1 9.3 yr · R7 2.1 · UDFA 1.6 · Pro
Bowlers 11.7.** Average retirement age **27.6**. By position: **LS 7.5 · K/P 4.87 · QB 4.44 ·
OL 3.63 · … WR 2.81 · RB 2.57.**
Became a 4+ season full-time starter: **R1 70.6 % · R3 28.8 % · R7 5.9 %.**
**Careers ended by injury: 40.3 %** self-reported *(⚠ snippet-only, JOEM 2016 paywalled)*. Objective
proxy: **34.5 % of players placed on IR with a severe injury never returned within four seasons**,
vs 16.1 % of non-IR injured.
**Protective factor:** multisport background — **IRR 0.80 total injuries, IRR 0.77 major, +0.7
career years** (n = 2,556, drafted 2011–23).

### Chronic / degenerative (former players)
Arthritis or joint replacement **53.4 %** (n = 4,189, mean age 51.8) · TKA 12.3 % · THA 8.1 % ·
lifetime OA 37.6 % · worst-exposed cohort (≥3 concussions + ≥2 LE injuries) **50.6 %** · arthritis
**3.5× the US male rate** under age 60 · career opioid use 52 % (71 % misuse).
**⚠ Playing-through-chronic-conditions prevalence in ACTIVE players is unpublished.**

## 2.5 Recovery timelines

| Injury | Time missed | RTP | Performance after |
|---|---|---|---|
| **ACL reconstruction** | **weighted mean 11.6 months**; RB/WR 13.6 mo | **55.8–73.3 %** (QB 92.9 %, OL ~60 %, WR 60 %) | **power rating −34 %**; fantasy output −33 to −42 %; games 13.7 → 8.7, starts 8.3 → 3.0; **only 28.5 % still in the league at 3 years** |
| **Achilles rupture** | **~9 months** (273–340 days) | **57–81 %** (TE 71 %, WR 38 %) | **−20.7 % beyond aging; only 27.1 % recover pre-injury level; +68 % career-termination hazard; 1.4 fewer seasons over 10 yr** |
| **Patellar / quad tendon** | **96.3 % season-ending**, median 11.3 mo | **56.8 %** | fewer snaps and lower AV into season 2; preseason cases worse |
| **Lisfranc** | **median 11.0 months** | 81.8 % | approximate value 6.0 → 5.0 at 1 yr |
| **Ankle, all** | — | **91 %** | **power rating −22 % Y+1, −27 % Y+2** |
| **High (syndesmotic) ankle** | **imaging drives everything:** other syndesmosis **27 days**; + complete deltoid/diastasis **175 days**; + fracture **250 days**. Only 13 % are isolated. Surgery 71 d vs conservative 39 d | 96–100 % | recurs in-season **20 %** |
| **Low / lateral ankle sprain** | **~15 days**, often next week | — | re-sprain likely, ~2 more weeks |
| **Hamstring** | **Grade I 1.1 games · II 1.7 · III 6.4**; skill players **mean 1.4 games, 33 % miss zero**; report time 2.4 ± 2.1 wk | — | PRP: 1.3 vs 2.9 games (p < .05) |
| **Groin / adductor** | ~3.8 weeks | — | — |
| **Quadriceps** | ~3.4 weeks | — | — |
| **All LEX strains** | **median 12 days** | 69 % time-loss | — |
| **Concussion** | **median 9 days to clear the 5-phase protocol**; **59 % miss ≥1 game**; **mean 2.76 games** | — | — |
| **Stinger** | **76.4 % miss nothing**; mean 4.79 days | — | — |
| **Shoulder subluxation** | **1.6 ± 1.9 wk (median 0.0 — many miss nothing)** | 91 % | playing time matches controls |
| **Shoulder dislocation** | 3.7 ± 5.4 wk (median 3.0); **operative median 39.3 weeks** | 86 % next season | recurrence 58 % surgical vs 9 % non-op |
| **Labral repair** | median 265 days | 86.5 % | defensive players decline persistently |
| **AC joint grade 2 / operative** | 1–4 weeks / **2–12 months (typically 6)** | — | — |
| **Rotator cuff** | **198.4 ± 125.3 days** | — | 2.8 ± 3.4 more years; **over-30 significantly less likely to return** |
| **Clavicle fracture** | **median 3.47 months, 8 games** | — | **no significant performance difference** |
| **Hand / finger** | **mean 1.7 games**; metacarpal K-wire **4.1 weeks to competition, 100 % RTP** | — | — |
| **Wrist** | mean 2.5 games | — | — |
| **Elbow UCL (non-QB)** | **Grade I 1.1 d · II 12.4 d · III 26.3 d** | — | — |
| **Turf toe** | **non-operative 75.8 d; surgical 221.4 d** | 91 % (100 % non-op, 80 % surgical) | **return to prior level: 78 % non-op vs 27 % surgical** |
| **Jones fracture (5th MT)** | 8.7–27 weeks | ~100 % | **⭐ < 10 weeks → −53.2 % performance and 60 % repeat surgery; > 10 weeks → +9.4 % and 14.8 %** |
| **Lumbar disc** | **non-op median 1.8 mo; operative median 7.9 mo** | 74.3 % | PFF grade holds (n.s.) but **contract value −66 %** |
| **Sports hernia** | in-season surgery 58–119 days; 65 % done in the offseason | 94.7 % | −1.2 games/season, **career 3.2 vs 3.8 years** |
| **Pectoralis major** | — | 48.8 % surgical | tears → shorter career than strains |
| **Biceps / triceps rupture** | — | 73.1 % / 70.8 % | **only 52.6 % / 41.2 % regain pre-injury performance** |
| **Ribs** | strain 1–3 wk, fracture 6–8 wk | — | — |

**⭐ Return-to-play and return-to-performance are different events, and the gap is large.**
Catastrophic lower-limb tendon/ligament injuries carry a **permanent 20–35 % output penalty** plus
elevated career-termination hazard. Upper-body and bony injuries mostly heal clean.

## 2.6 IR and roster rules (current through 2025/26)

| Rule | Current value |
|---|---|
| IR roster impact | Off the 53; **salary still counts against the cap** |
| **Minimum absence** | **4 games** (since 2022) |
| **Return designations** | **8 per regular season** (+2 postseason for playoff teams, max 10); unused regular-season designations carry over |
| Per player | May be designated to return **twice** in one season; both count against the 8 |
| Practice window | **21 days** from designation → activate / revert to season-ending / release |
| Earliest activation | **August 31** |
| **Cut-down IR** | Since June 2024, **up to 2 players may go on IR at or before the initial 53-man cutdown *with* a return designation** (counts against the 8) |
| Anyone else IR'd before the roster is set | **Out for the season** |
| Placement limit | **None** |

**Rule history — the returns dial is a design knob, not a constant:** 0 (pre-2012) → 1, 6-week
minimum (2012) → 2, after 8 games (2017) → team-games basis (2018) → **unlimited, 3-game minimum**
(2020–21 COVID) → **8, 4-game minimum, 2 per player** (2022, permanent) → +2 postseason and 2
cut-down designations (2024).

- **PUP** (football injuries only). *Active/PUP* counts vs the 90, may rehab but **cannot practice**;
  **one practice and he can never return to PUP**. *Reserve/PUP* if still unable at cutdown: off the
  53, **must miss the first 4 games**, then a 21-day window. **Full salary paid.**
- **NFI** (non-football injury/illness) — same 4-game structure, but **the player is NOT entitled to
  salary**; the contract keeps running and tolls if he cannot perform by game 6.
- **Practice squad: 16** (17 with an International Pathway player); **up to 6 veterans**;
  **2 elevations per game, max 3 regular-season games per player**; **4 weekly protections**;
  cannot sign with an upcoming opponent within 6 days. Waived/injured players revert to
  Reserve/Injured, typically bought out via injury settlement.
- **Roster: 90 → 53. Gameday actives 47, or 48 with ≥8 offensive linemen** (up from 46/7 pre-2020).
  Gameday ceiling 55 with two standard elevations.
- **Injury report.** Practice participation filed Wed/Thu/Fri: **DNP / Limited (< 100 % of normal
  reps) / Full**. Game status: **Questionable / Doubtful / Out**. **"Probable" was eliminated for
  2016** because ~95 % of Probables played.
  **⭐ Actual play rates: Questionable pre-2016 ~60–65 %; 2016+ ~73 %; Questionable *starters*
  73 % play / 27 % do not** — the exact source of FO's 0.27 AGL weight. Pre-2016 official
  definitions were Probable 75 % / Questionable 50 % / Doubtful 25 %.

## 2.7 Preseason and camp

- **Preseason practices carry 27 % of all annual time-loss LEX strains — the single largest bucket**
  (regular-season games 26 %). **Training-camp practices alone = 19 % of all annual strains.**
- Concussions by setting: games 80.3 % · in-season practice 17.0 %. **Games are roughly an order of
  magnitude more dangerous per exposure than practice.**
- **ACL: preseason games 6.1 vs regular-season 2.7 per 10,000 plays — 2.3×. Preseason-vs-in-season
  IRR 2.68 (p < .00001). August has the highest ACL incidence of any month. 64 % of NFL Achilles
  tears occur in preseason/training camp.**
- **⭐ The acclimation ramp is the best-quantified intervention in the dataset.** Training-camp LEX
  strains **288 (2021) → 215 (2022) → 186 (2023) = −35 %**; the winning protocol is a **gradual
  15-minute daily ramp across the first three practices**. **Regular-season recurrent strains fell
  22/yr → 11/yr and stayed there** — the protective effect persists past camp. NFL/IQVIA:
  hamstring and strain rates are now **half the 2018–2022 level**; ACL −25 % in 2025.
- **⭐ Schedule effects are essentially null and should NOT be modelled:** Thursday Night Football
  n.s. (earlier work found *fewer* injuries); cumulative travel p = .47; **overseas games 19.3 vs
  19.3 per 1,000 AE (p = .96)**; bye-week timing p = .73; the 17th game p = .12; short rest and
  hamstrings p = .959. **The only significant team-level covariate is playoff qualification.**
- **Season-timing curve:** hamstrings peak weeks 5–6 (Weeks 1 and 17 lowest); concussions
  concentrate in the final third; ACL peaks in August; Lisfranc 42.9 % in Q1 of the season.

## 2.8 Quick-reference parameter block

**Per team-season:** 27–30 missed-game injuries · ~20 players missing ≥1 game · 12–20 IR placements ·
**AGL mean 70, range 16–191** · 85–165 man-games lost.
**Per player-game:** 4.1 % injury rate · **mean 3.1 games missed** · **64 % of injuries ≤2 games** ·
availability 88.75 %.
**League-wide per season:** concussions 182–219 · ACL 45–63 · MCL 109–132 · Achilles 20–23 ·
hamstrings ~162 · stingers ~138.
**Type mix:** knee 17.8 · ankle 12.4 · hamstring 8.7 · shoulder 8.4 · concussion 7.0 · other 45.7.
**Region:** lower 61.9 · upper 18.0 · head/neck 10.2 · axial 7.8.
**Position (per 100 team-game-positions, OL = 1.00):** WR 2.36 · TE 2.14 · DB 1.84 · RB 1.70 ·
LB 1.67 · DL 1.24 · OL 1.00 · QB 0.94 · K/P 0.38.
**Conditioning:** no camp ramp → all-injury ×1.52, hamstring ×1.88, groin ×2.26, calf ×2.53,
quad ×2.78; **ACL/Achilles/pectoral unchanged**. Proper ramp → camp strains −35 %, recurrence −50 %.
**Memory:** hamstring same-season 12–27 %, any-season 33–38 %, RR 2.7 (4.8 if recent) · ACL second
event ~25 % career, RR 2.8 · concussion OR 3.06, 75–92 % of repeats within 7–10 days ·
post-concussion LE injury OR 2.28–2.92 · ankle re-sprain 26 % vs 11 %.
**Stability:** team-season burden **r = 0.29 YoY (~92 % noise)**; individual type-specific memory
is strong. **That asymmetry is the empirically correct model.**

### Known gaps and conflicts in the benchmark itself
1. No published NFL incidence-by-age-bracket exists; the amateur-soccer and NZ-rugby proxies
   **disagree in direction for the 30+ band**.
2. No published overall contact/non-contact split.
3. "40.3 % of careers ended by injury" is snippet-only (JOEM 2016 paywalled).
4. AGL r = 0.29 is snippet-only (footballoutsiders.com defunct, archive.org unreachable).
5. MCL counts differ ~20× between official (109–132) and in-game-only studies (3–8). Use official.
6. Man-games-lost totals differ ~2× by definition.
7. Practice-squad injury protection (CBA Art. 33) and exact padded-practice counts could not be
   verified — NFLPA CBA and NFL Operations pages 404'd.
8. The 46 → 47/48 gameday-actives transition year was not re-verified.
9. **"Injury-prone" as a player trait has no rigorous statistical support.**
10. *OJSM* 2023 reports both "4,378 injuries over 5 seasons" and per-season means that do not
    reconcile (940×4 + 984 = 4,744); the abstract figure was treated as primary.

---

# PART 3 — VERDICT

## 3.1 Dimension-by-dimension realism scorecard

| # | Dimension | Grade | Game | NFL |
|---|---|:---:|---|---|
| 1 | **Frequency** | **2/10** | **~2.5–3.2 missed-game injuries/team-season; ~7–9 man-games lost** | **27–30 injuries; 85–165 man-games; AGL mean 70.** ~**10× too few injuries, ~12× too few games lost** |
| 2 | **Type mix** | **3/10** | Uniform 10 % over 10 buckets (weekly path skews by personal history; live path pure uniform) | knee 17.8 / ankle 12.4 / hamstring 8.7 / shoulder 8.4 / concussion 7.0. **The flat table over-produces ribs/wrist ~3× and under-produces knee ~1.8×**. Region ratio lower:upper 3.4:1 is not modelled at all |
| 3 | **Severity distribution** | **2/10** | **No severity roll.** Uniform draw inside a per-type week band; mean ~3.0 wk after staff; **hard ceiling ~16–17 weeks** | **64 % of injuries cost ≤2 games, mean 3.1** — the game's distribution is too flat *and* too long in the middle. **~5–7 % of in-season injuries carry a true 6–12-month duration; the game cannot express one at all** |
| 4 | **Recovery times** | **5/10** | concussion 1–3 wk ✅ · hamstring 1–4 wk ✗ · ankle 1–6 wk ~ · shoulder 2–8 wk ✗ · knee 4–16 wk ✗✗ | concussion median 9 days / 2.76 games — **the game's best-calibrated band**. Hamstring is **~2× too long** (real grade I = 1.1 games, 33 % miss zero) and cannot produce a play-through. Shoulder subluxation median is **0.0 weeks**, the game's floor is 2. **Knee merges a 4-game MCL with a 50-week ACL into one flat 4–16 band** |
| 5 | **Durability effect** | **3/10** | `×(1−dur/200)` = **±14 % at ±2σ**; affects frequency only | **Nuanced verdict.** A weak *global* trait is defensible — **"injury-prone" has no statistical support (one model p = .822)**. But the mechanism that *is* supported — **type-specific memory, RR 2.7 (4.8 if recent)** — the game applies to **type selection only, never to rate.** It has the right data structure (`injuryHistory`, `priorInjuryCount`) wired to the wrong output |
| 6 | **Age effect** | **2/10** | None in the shipped model; ~−0.5 durability/yr past peak ⇒ ~+1.6 % after four years | **+6.6 %/yr for muscle/tendon — but ligament risk skews YOUNGER** (≤3 yr experience have the higher preseason ACL rate) and several NFL papers find age n.s. **The game's omission is less wrong than it looks; the correct model is a split, not a single curve** |
| 7 | **Positional differentiation** | **0/10** | **None.** Same rate, same type mix, same N(72,9) prior for a kicker and a receiver | **6.2× spread (WR 2.36 → K/P 0.38); QB is safer than OL; guards tear ACLs 3× more than tackles; DB+WR/TE = 63 % of hamstrings; DL get the fewest concussions but miss the most time** |
| 8 | **Roster mechanics** | **0/10** | No IR/PUP/NFI, no designations, no inactives. `RosterStatus` omits them by design | 4-game IR minimum, 8 returns (+2 postseason), 2 per player, 21-day windows, 2 cut-down designations, Reserve/PUP, 47/48 actives. **The 2015 data even shows a duration spike at exactly the IR-return threshold — rules visibly shape the injury distribution** |
| 9 | **Coach agency** | **3/10** | One binary rush-back call in the final rehab week; preseason snap policy; camp slider; staff/facility spend | Weekly practice participation, snap counts, Questionable calls, IR timing, load management |
| 10 | **Consequence on results** | **0/10** | **Injured players are never filtered from any regular-season sim roster; 15 of 16 games/week are roster-blind random scores** | **AGL predicts playoffs: 6 of 8 healthiest teams made the 2024 field, 0 of 6 worst did.** Playoff teams 18.4 vs 19.9 injuries/1,000 AE |
| 11 | **Career wear / narrative** | **7/10** | Permanent history, recurrence weighting, durability erosion, retirement pressure, `injuryToll` shock retirement, ×0.4 development health gate | **The evidence strongly endorses this design** — type-specific memory is the supported mechanism, and 34.5 % of severe-IR players never return within 4 seasons. Undermined only by volume: the ≥30-career-weeks-out gate is unreachable at 2.5 injuries/team-season |
| 12 | **Preseason / camp share** | **3/10** | Preseason budgeted at ≤ +8 % of season total and derived honestly (`preseasonInjuryScale = 0.45`); **camp itself injures nobody** | **Camp practices alone = 19 % of all annual strains; preseason practices 27 %; ACL preseason IRR 2.68; 64 % of Achilles tears happen in camp/preseason.** The game's proportion is roughly right but its *biggest single real bucket is empty* |
| 13 | **Schedule effects** | **10/10** | Not modelled at all | **Correct by omission.** Thursday, travel, London, bye placement and the 17th game are all statistically null (p = .96 for London). Do not add them |
| 14 | **Persistence & fog** | **5/10** | Clean migration-safe persistence; **zero fog** — exact weeks visible both directions | Real GMs work from **Questionable (73 % play)**, never an exact week count, and never see another club's medical file |
| 15 | **Harness / telemetry** | **1/10** | Harness exercises a **different, ~8× hotter model**; `MedicalEngine` is not a synced source; the only injury-adjacent output is a *retirement* count | — |

**Weighted: ~2.5/10 as a simulation of NFL availability; ~7/10 as a narrative injury-history
system.** The persistence layer, the recurrence model, the rehab-variance loop and the career-wear
consequences are well built and — importantly — **the recurrence design is the one the literature
actually supports.** What they are attached to (rate, severity, and the link to results) is not.

## 3.2 The five biggest gaps, ranked by gameplay impact

### **GAP 1 — Injuries have no effect on any game result. (critical)**
`GameSimulator.swift:99-100` and `LiveGameEngine.swift:1283-1284` filter only `isHoldingOut`;
`SimPlayer` has no injury field; `MatchupResolver.offense/defense` starts the best-rated man, so
**an injured star plays**. The other 15 games/week never read a roster (`WeekAdvancer.swift:1383` →
`randomTeamScore()`).

Two user-visible contradictions follow: an "OUT — 6 wks" player **accumulates box-score stats**
while `gamesPlayedThisSeason` is withheld (`WeekAdvancer.swift:1419`) — a player can finish with 17
games of rushing yards and 11 games played; and the Injury Report says short-handed while the
scoreboard says otherwise.

**The benchmark quantifies exactly what is missing:** **6 of the 8 healthiest teams by AGL made the
2024 playoffs; none of the 6 worst did**, and playoff teams carry a statistically lower injury rate
(18.4 vs 19.9 per 1,000 AE, p < .05). Availability *is* a competitive variable in the real league.
**This gap is upstream of everything else — raising the rate today would add noise, not difficulty.**

### **GAP 2 — Frequency ~10× low, and the severity tail cannot exist. (critical)**
~2.5 injuries and ~8 man-games lost per team-season vs a real 27–30 and 85–165 (AGL 70). Worse than
the level is the **shape**: the maximum absence is ~16–17 weeks, so **no season-ending injury can
occur**, nothing crosses a season boundary at a realistic length, and the "lost the franchise QB in
Week 4" story is structurally impossible. Simultaneously the *common* case is too long — 64 % of
real injuries cost ≤2 games, while the game's mean is ~3 weeks with a **uniform** shape.
`InjuryType.severity` is a constant that only gates a −1 durability branch.

### **GAP 3 — The recurrence model is wired to the wrong output; durability is decorative. (high)**
The game has exactly the data the literature says matters (`injuryHistory`, `priorInjuryCount`) and
spends it on **type selection instead of rate**. Real hamstring recurrence is **RR 2.7 rising to
4.8 for a recent injury**, and **13.4 % of NFL hamstrings recur when the player returns inside two
weeks** — a *rate* effect the game does not model at all outside the 2-week rush-back window.
Meanwhile the global `durability` term gives ±14 % at ±2σ — a benefit the user cannot perceive
across a season (~2.2 vs ~2.9 injuries per roster). Note the evidence cuts *both* ways here: a
strong global "injury-prone" stat would be **unsupported** by the literature, so the fix is not
"make durability enormous" — it is **move the teeth into type-specific recurrence and make
durability merely perceptible.**

### **GAP 4 — No IR, no designations, no availability decisions. (high)**
No roster relief, so an injured player burns a 53-man spot for the full absence — *harsher* than
the NFL, yet with none of the interesting decisions (stash for 4 games? spend one of 8 returns?).
No Questionable/Doubtful/Out layer, therefore no "play him at 80 %" call. The 2015 duration
histogram's spike at exactly the IR-return threshold is direct evidence that **roster rules shape
the injury distribution**, which the game forgoes entirely. Related defects found:
- **`Injuries: Off` does not work in coached games** — `LiveGameEngine.checkInjury` (`:3124-3142`)
  never reads `career.injuryFrequency`; only `WeekAdvancer` (`:1816`) and `PreseasonEngine`
  (`:654`) do.
- **Playoffs neither injure nor heal** in quick sim (`advancePlayoffWeek` has no injury or rehab
  pass), yet a *coached* playoff game still injures. (`TODO.md:2008`)
- **`freakInjury`, `injurySetback`, `aheadOfSchedule`, `suspension` and `arrest` are pure prose** —
  `EventEngine.applyEventChoice` (`:144-173`) moves only morale/owner/reputation.
- **Camp never injures anyone.** `WorkloadEngine.injuryRiskPct`'s only caller is a SwiftUI label
  (`TrainingPlanView.swift:371`); the Hard Knocks "campInjury" story is narration.

### **GAP 5 — No positional model, the conditioning lever is inverted, and the harness validates the wrong model. (medium-high)**
No positional differentiation despite a **6.2× real spread** — and several of the real effects are
free to implement and highly flavourful (QB safer than OL; guards 3× tackles for ACL; DB+WR/TE =
63 % of hamstrings; DL concussed least but out longest).

**The conditioning model is backwards in a fixable way.** The 2020 natural experiment is
unambiguous: losing the preseason ramp multiplied **strains** by 1.5–2.8× while leaving **ACL,
Achilles and pectoral ruptures statistically unchanged**. The game's camp workload multiplies *all*
injury types uniformly (×1.6 / ×2.5) and — critically — **camp itself, the single largest real
bucket (19 % of all annual strains), produces zero injuries.**

**And the harness measures a different model.** `MedicalEngine.swift` is not in
`sync_sources.sh`, so the `career` scenario rolls `PlayerDevelopmentEngine.checkForInjury` at
**~8× the shipped rate**, with an age term and a 17–52-week season-ending tier the game lacks.
**Every availability-dependent balance conclusion was calibrated against a league losing ~21 men a
season while the shipped league loses ~2.5** — the same class of bug `#97` turned out to be.
Two further divergences: `processInjury`'s 15 %/−1…−5 durability rule contradicts `applyInjury`'s
25 %/−1 rule (`TODO.md:2010`), and there is **no injury-rate metric anywhere in the driver output**.

## 3.3 Concrete tuning recommendations

Ordered by dependency. **R1 gates everything else.**

### **R1 — Wire availability into the simulation.** *(prerequisite)*
- Add `!$0.isInjured` alongside `!$0.isHoldingOut` in `GameSimulator.simulate` (`:99-100`) and
  `LiveGameEngine.init` (`:1283-1284`); add `isInjured` to `SimPlayer`.
- Give `simulateGameScore()` an available-roster strength term so the 15 AI games respond to
  injuries. Suggested: keep the TD/FG bucket draw, shift the bucket index by
  `clamp((availTop24OVR_home − availTop24OVR_away)/3, −2, +2)`.
- **Calibration target from the benchmark:** the healthiest quartile by season-total games lost
  should win ~1.5–2 more games than the most injured quartile, reproducing "6 of 8 best AGL made
  the playoffs, 0 of 6 worst did".
- **Verification gate:** a player must never appear in a box score and on the injury report in the
  same week. Assert it in the harness.

### **R2 — Rebuild the rate model: snap-weighted, position-weighted, memory-weighted.**
**Targets: 27–30 missed-game injuries and ~95–110 man-games lost per team-season; AGL ≈ 70;
~20 of the 53 miss ≥1 game; roster availability ≈ 88–89 %.**

Per-player-per-week base risk (post-modifier, at a league-average player), derived from
27.6 injuries ÷ (53 players × 18 weeks) = **0.029**:

| Playing-time role | Suggested weekly risk |
|---|---|
| starter | **0.048** |
| rotational | 0.030 |
| backup | 0.012 |
| depth | 0.005 |

Roster-weighted this yields ≈ 1.6/team-week ≈ **29 per season**. Reuse the existing
`PlayerDevelopmentEngine.playingTimeRoles` ladder — no new data needed.

**Position multiplier** (normalised so the roster-weighted mean = 1.00; derived from PFL per-player
rates, ordering confirmed by Lawrence):
RB **1.31** · TE 1.23 · S 1.18 · WR 1.13 · CB 1.11 · LB 1.08 · DT 1.08 · DE 0.98 · **OL 0.86** ·
**QB 0.63** · **K/P 0.15**. *(Lawrence's per-position-on-field data implies a wider 6.2× spread; the
PFL-normalised set above is the per-player form the engine actually needs.)*

**Durability** — replace `1 − dur/200` with **`pow(0.6, (durability − 72) / 22)`**: dur 50 → ×1.72,
dur 63 → ×1.24, dur 72 → ×1.00, dur 81 → ×0.81, dur 94 → ×0.58. **~3× across ±2σ instead of 1.3×** —
perceptible without asserting an "injury-prone" trait the literature does not support. Also make
durability shift the **severity tier** by ±1 weight step per ~15 points from 72; a durable man plays
through what a fragile one misses a month with.

**Type-specific recurrence — the highest-evidence change on this list.** Multiply the *rate*, not
just the type draw:
- `× 2.0` if the player has any prior injury of the type being rolled (real RR 2.7 for hamstring)
- `× 3.5` if that prior injury was within the last 8 weeks (real RR 4.8)
- Open a **3-week ×1.5 elevated window after *every* return**, not just after a rush-back — real
  data: **23 % of in-season hamstring recurrences happen in the first week back**, and returning
  inside 2 weeks yields a 13.4 % recurrence rate.
- **Cross-injury contagion** (cheap, high flavour): after a concussion, `× 2.3` on
  lower-extremity types for 12 weeks (real OR 2.28); after 2+ ankle injuries, `× 2.9` on concussion.

**Age — split the curve, do not use one.**
- Muscle/soft-tissue types: `× (1 + 0.066 × max(0, age − 25))` → age 30 ×1.33, age 34 ×1.59.
- Ligament/tendon rupture types: **flat, or slightly *inverted*** (`× (1 + 0.10 × max(0, 24 − age))`
  in the preseason window only), matching the finding that ≤3-years-experience players carry the
  higher preseason ACL rate.

**Fatigue** — either make it real (accumulate in-season snap load) or delete it. As shipped it is
provably always 1.0 in the quick sim (§1.2).

**Durability prior** — widen N(72, 9) → **N(70, 12)** and make it position-dependent, removing the
explicit position-independence at `PositionPhysicalProfile.swift:58`.

### **R3 — Two-stage severity roll with a real tail.**
Roll a **severity tier** first, then a type conditioned on tier and position. Calibrated to the
benchmark's *in-season games missed* distribution (64 % ≤2 games, mean 3.1):

| Tier | Weight | In-season games missed | Cumulative |
|---|---|---|---|
| Day-to-day | **47 %** | 1 | 47 % |
| Minor | **18 %** | 2 | **65 %** ✓ |
| Moderate | **17 %** | 3–5 (mean 4) | 82 % |
| Major | **10 %** | 6–9 (mean 7.5) | 92 % |
| **Season-ending** | **8 %** | 10–17 (mean 13) | 100 % |

Mean ≈ **3.3 games** ✓. Separately, **5–7 % of all injuries must carry a *true* duration of 30–52
weeks** (ACL, Achilles, extensor mechanism, Lisfranc) that **crosses the season boundary** — the
in-season games-missed figure is merely its truncation.

- **Split `.knee` into `.kneeMCL` (median 4 games, tiers 1–4) and `.kneeACL` (36–52 weeks).** Add
  `.achilles`, `.lisfranc`, `.turfToe`, `.calf`, `.quad`, `.patellarTendon`.
- **Re-weight the type draw to the real mix** (knee 17.8 / ankle 12.4 / hamstring 8.7 / shoulder
  8.4 / concussion 7.0) and **apply the same weighting in `LiveGameEngine.checkInjury`**, which
  today uses `allCases.randomElement()` and ignores history entirely.
- **Add a "plays through it" tier-0** (33 % of real hamstrings cost zero games; shoulder
  subluxation's median is 0.0 weeks). This is what the Questionable designation attaches to.
- **Concussion:** shorten to a median of 1 game (real: 9 days to clear, 59 % miss ≥1 game, mean
  2.76) and make it a **week-to-week protocol flag** rather than a fixed countdown.
- **Cross-season healing:** the offseason must tick more than one week. Either run rehab through
  every offseason phase or credit ~20 weeks at the OTAs boundary, so a Week 14 ACL returns around
  Week 6 of the following season instead of freezing.
- **Return at reduced effectiveness:** 2 weeks at 92 %/97 % after any absence ≥ 4 weeks; a
  **permanent −20 to −35 % on the relevant attributes after ACL/Achilles/extensor-mechanism**
  (real: ACL −34 % power rating, Achilles −20.7 %, only 27.1 % recover pre-injury level) plus a
  **+68 % career-termination hazard**. `docs/DEVELOPMENT_NFL_REFERENCE.md:119` already asks for
  "year-of-return performance ~85–90 %" and nothing implements it.

### **R4 — The roster layer: IR, PUP, designations.**
- Extend `RosterStatus` with **`.injuredReserve`** and **`.pup`**. The doc comment at
  `Player.swift:657-662` reasons this away, and that reasoning holds only while there is no
  roster-relief mechanic. Model: **4-game minimum, 8 return designations (+2 postseason), 2 per
  player, 21-day practice window, 2 cut-down designations, Reserve/PUP costing the first 4 games.**
  This turns "my LT is out 6 weeks" into a genuine decision.
- Add **`InjuryDesignation { out, doubtful, questionable, full }`** with a weekly practice-
  participation line (**DNP / Limited / Full**). Calibrate to the real play-through rates:
  **Questionable → plays 73 % of the time, Doubtful ~25 %, Out 0 %.**
- **The "play him at reduced snaps" call** for a Questionable player — rating × 0.90, a snap-share
  cap, and ×1.6 re-injury for that week — is the single highest-value new decision available, and
  it reuses the existing rush-back UI wholesale.

### **R5 — Make camp real and split the conditioning lever.**
The benchmark's clearest causal finding deserves a direct implementation:
- **Camp practices must roll injuries** — target **~19 % of a season's total strains** in camp and
  ~27 % across the whole preseason window. `WorkloadEngine.injuryRiskPct` already computes the
  number; it just needs a caller in `applyCampWeeklyTick`.
- **Split the workload multiplier by injury family.** Overloaded/burned-out should multiply
  **strains by 1.5–2.5×** (matching hamstring ×1.88, groin ×2.26, calf ×2.53, quad ×2.78) and
  **ruptures by ~1.0×** (ACL/Achilles/pectoral were statistically unchanged). Today one flat
  multiplier hits everything.
- **Add an acclimation-ramp choice** to the camp plan: a gradual ramp cuts camp strains ~35 % and
  **halves in-season recurrence** — a persistent, season-long payoff for a camp decision, which is
  exactly the kind of lever the training-plan screen wants.
- **Preseason ACL/Achilles weighting:** ACL preseason IRR is 2.68 and **64 % of Achilles tears
  happen in camp/preseason** — so the rupture types should be *over*-represented in August even
  though the conditioning multiplier does not touch them.

### **R6 — Fix the harness and the known bugs.**
- Add `MedicalEngine.swift` to `sync_sources.sh`; make the `career` scenario roll the **shipped**
  model; retire `PlayerDevelopmentEngine.checkForInjury`.
- Add an **`injuries` metric block** to the driver printing, per league-season: injuries/team,
  man-games lost/team, an **AGL-equivalent** (weighting starters 1.00 and Questionable 0.27),
  severity-tier histogram, type histogram, position histogram, mean/median absence, share of the 53
  missing ≥1 game, and the **durability↔games-missed correlation**. Gate the wave on landing inside
  §2.8's bands.
- Reconcile the two permanent-damage rules (`TODO.md:2010`).
- Pass `career.injuryFrequency.riskMultiplier` into `LiveGameEngine.checkInjury`.
- Run injury + rehab in `advancePlayoffWeek` (`TODO.md:2008`).
- Route `freakInjury` through `MedicalEngine.applyInjury`.
- Add a **career games-missed** counter (`TODO.md:3247`) — the user-facing proof durability matters.
- **Do NOT add** Thursday-game, travel, London, bye-week or 17th-game injury modifiers. All null in
  the data (London p = .96); the game is currently correct by omission.

### **R7 — Fog the injury report.**
Today the AI reads exact `injuryWeeksRemaining` for trade valuation
(`TradeValueEngine.swift:1815-1818, 2027, 2469`) and the user reads every AI club's medical file in
`LeagueRostersView`. Split **true state** from **reported state**: other clubs see body part +
designation only; the user's own **team-doctor rating determines how tight his own prognosis window
is**. This mirrors the fog already applied to prospect durability
(`ProspectListControls.swift:632-634`) and gives the doctor hire a second reason to exist.

## 3.4 Interaction with the planned Life Events system

1. **Build one shared availability model *before* Life Events lands.** Availability today is two
   unrelated booleans plus a counter, and **suspensions already exist as pure narrative with no
   availability effect** (`EventTemplates.swift:107-125`). Suggested:
   ```
   PlayerAvailability { reason: .injury | .suspension | .nonFootballInjury
                              | .personalLeave | .illness | .holdout,
                        weeksRemaining, weeksOriginal, designation, isRosterExempt }
   ```
   `RosterStatus` gains `.injuredReserve`, `.pup`, `.nfi`, `.suspendedList`, `.exemptList`. The
   **~25 call sites** that today ask `!$0.isInjured && !$0.isHoldingOut` — across `WeekAdvancer`,
   `PracticeSquadEngine`, `TrainingFocusEngine`, `VersatilityDevelopmentEngine`, `TradeValueEngine`,
   `HoldoutEngine`, `LeagueNarrativeEngine`, `NewsGenerator` — collapse to one `isAvailable`.
   **Shipping Life Events first means editing all 25 twice.**
2. **Non-football injuries map onto NFI, not IR** — and the NFL's NFI rule carries a real GM
   decision the game does not model: **the player is not entitled to salary**, and the contract
   tolls if he cannot perform by game 6. That is a contract-guarantee lever, not just an
   availability one. The existing `freakInjury` template ("*injures hand in bizarre off-field
   accident*") is the natural first Life Event to make real.
3. **Suspensions share the availability model but not the medical loop.** A suspended player is
   unavailable, accrues no game, does not develop, and generates no rehab roll — and unlike an
   injured player he is **not replaced by any exemption**, which makes a suspension *more* costly
   than an equal-length injury. Good design contrast, and `arrest`/`socialMediaIncident` templates
   already exist inert.
4. **Personal / bereavement / birth leave** is a one-week availability event with a *morale*
   interaction rather than a medical one — forcing a player back costs locker-room standing. It
   reuses `InjuryReportView`'s return-decision UI verbatim.
5. **Declare an exposure budget, as the preseason already does.** `PreseasonEngine.swift:123-136`
   derives `preseasonInjuryScale` from an explicit "+8 % of season total" ceiling. Life Events
   should declare its own ("non-football availability events add ≤ X % to season-total man-games
   lost") and be verified in the R6 metric block.
6. **Life Events is the natural home for the chronic/degenerative arc the injury system lacks.**
   The real numbers are stark — **53.4 % of former players have arthritis or a joint replacement,
   12.3 % a total knee**, 52 % used opioids during their career, and **34.5 % of severe-IR players
   never return within four seasons**. `PlayerRetirementEngine`'s `injuryToll` shock retirement
   (`:614-663`) is already exactly this mechanic and is well written — it simply needs an injury
   system that generates enough career weeks-out for its ≥30-week gate to ever fire.

---

## Appendix — key file references

| Concern | Path |
|---|---|
| Injury taxonomy | `dynasty/dynasty/Domain/Enums/InjuryType.swift` |
| History / rehab / return-decision models | `dynasty/dynasty/Domain/Models/Player/InjuryRecord.swift` |
| Player injury fields | `dynasty/dynasty/Domain/Models/Player/Player.swift:116-119, 528-567, 655-694` |
| **The injury engine** | `dynasty/dynasty/Engine/Medical/MedicalEngine.swift` |
| Weekly roll + rehab tick | `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:1794-1847, 2026-2085` |
| Live per-play roll | `dynasty/dynasty/Engine/Match/LiveGameEngine.swift:673-691, 3080-3170, 2733-2749` |
| Preseason roll | `dynasty/dynasty/Engine/Simulation/PreseasonEngine.swift:123-136, 631-711` |
| **Roster construction (the availability bug)** | `Engine/Simulation/GameSimulator.swift:93-135`; `LiveGameEngine.swift:1283-1289`; `Engine/Match/MatchupResolver.swift:26-80` |
| AI game score (roster-blind) | `Engine/Simulation/WeekAdvancer.swift:971-990, 8186-8214` |
| Durability attribute + prior | `Domain/Models/Player/PlayerAttributes.swift:11,20`; `PositionPhysicalProfile.swift:58-60, 195-213` |
| Harness-only injury model | `Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:1624-1728` |
| Health gate on development | `Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:665, 786-793` |
| Age regression → durability | `Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:1461-1468` |
| Injury-driven retirement | `Engine/PlayerDevelopment/PlayerRetirementEngine.swift:145-156, 614-663` |
| Facility / workload multipliers | `Engine/Camp/FacilityEngine.swift:178-217`; `Engine/Camp/WorkloadEngine.swift:143-151`; `Domain/Enums/CampEnums.swift:21-29` |
| Camp weekly tick (where camp injuries belong) | `Engine/Simulation/WeekAdvancer.swift:8237-8300` |
| League setting | `Domain/Enums/GameModeEnums.swift:71-97`; `Domain/Models/Career.swift:303-306, 549` |
| Inert narrative events | `Engine/Event/EventEngine.swift:144-173, 208-216`; `Engine/Event/EventTemplates.swift:107-125, 381-448` |
| Injury UI | `UI/Roster/InjuryReportView.swift`; `UI/Roster/PlayerDetailView.swift:2159-2262` |
| Balance harness | `tools/balance-harness/driver/CareerScenario.harness.swift:1740-1800, 2618-2619`; `tools/balance-harness/sync_sources.sh` |
| Original design doc | `docs/plans/2026-03-18-medical-staff-and-budget.md` |
| Development reference | `docs/DEVELOPMENT_NFL_REFERENCE.md:97, 114-123` |
