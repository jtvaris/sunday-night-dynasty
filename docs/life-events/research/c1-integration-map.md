# Life Events — Integration Map

Research pass, read-only. All paths relative to `/Users/jtvaris/workspace/jtvaris/IOS/Dynasty`.
Engine = `dynasty/dynasty/Engine`, UI = `dynasty/dynasty/UI`, Domain = `dynasty/dynasty/Domain`.

---

## 0 · Executive summary (read this first)

**Persistence: NO schema change needed. `V2` is avoidable.** Every recent feature state
(`UDFAMarketState`, `PreseasonState`, `LeagueNarrativeState`, `LockerRoomEvent`, `NewsItem`,
`GamePlan`, …) is a plain `Codable` struct JSON-encoded into a `Data? = nil` attribute on the
**`Career` `@Model`**, with a typed computed-property bridge beside it. That pattern is documented
as *free* in `docs/SWIFTDATA_MIGRATION_PLAN.md` §4.1. A `LifeEventsState` blob follows it exactly.
See §8.

**Determinism: the sim is NOT globally seeded.** 428 unseeded `.random(in:)` / `randomElement()`
call sites in `Engine/` vs 69 `using: &generator` sites. Determinism is *opt-in per feature*, via
SplitMix64 streams seeded from `(careerID, season[, salt])`. Life Events should adopt the seeded
dialect (it is the house convention for anything a user can re-observe). See §10.1.

**Best structural precedent to copy wholesale: the Locker Room system** —
`Career.lockerRoomLogData` (capped array blob) + `Career.pendingLockerRoomEventData` (single
pending item awaiting a coach decision), generated inside `WeekAdvancer` (`:2522-2578`), surfaced in
`LockerRoomView`. Life Events is the same shape one level up.

**Availability: suspension does not exist, and injury does NOT gate the regular-season sim.**
`SimPlayer` has no `isInjured` field, so availability cannot cross into the simulator at all. The
only filter on either simulator is `filter { !$0.isHoldingOut }` at **`GameSimulator.swift:130-131`**
and **`LiveGameEngine.swift:1283-1284`**. Those two lines are the whole surface a suspension has to
touch. See §5.4/§5.5 — including why you must *not* add `!$0.isInjured` in the same change.

**Contract willingness has exactly one honest seam:** `situationBreakdown` →
the components array at `ContractNegotiationEngine.swift:974-983` (`Source` enum `:489-506`). Adding
one case + one `.init(source:value:)` wires a willingness modifier end to end. See §6.2.

**Existing hooks already in the tree that Life Events plugs into with zero new vocabulary:**
- **`EventEngine`'s `enum EventType` (`Engine/Event/EventEngine.swift:70-77`) already contains
  `arrest`, `suspension`, `socialMediaIncident`, `contractDispute`, `tradeRequest`, …** — 18 cases,
  with a 4-meter `EventOption` (`:42-68`) and a written template library. **The whole system is
  dead** (zero renderers, `applyEventChoice` has zero callers). Life Events should *absorb* it, not
  sit beside it. See §2.3.
- `NewsCategory.offFieldIncident` — already a case (`Engine/Media/NewsGenerator.swift:42`), and
  `NewsView.swift:110` already lenses on it.
- `MessageCategory.playerIssue` / `.leagueNotice` + `MessageSender.leagueOffice` — a suspension
  notice needs no new inbox vocabulary (§3.1).
- `MotivationState` is a `String`-raw enum on an **optional** column — **adding a `.distracted` case
  is free** and flows into development, focus and the contract ask with no other wiring (§6.5).
- `CollegeProspect.redFlags: [String]?` — off-field/character flags with a probability model
  (`Engine/Scouting/ScoutingEngine.swift:3709-3748`: 80% clean / 14% medical / 4% red / 2% both).
  **Dies at the draft** (see §1.5) — a real gap.
- `docs/FUTURE_IMPROVEMENTS.md:79` "Off-field issues affecting availability" is already a
  parked design line under "Player Personalities — Deep System".

---

## 1 · Personality & Mental

### 1.1 `PlayerPersonality` — the whole type

`Domain/Models/Player/PlayerPersonality.swift:3-22`. **Two fields only.**

```swift
nonisolated struct PlayerPersonality: Codable, Equatable {
    var archetype: PersonalityArchetype   // :4
    var motivation: Motivation            // :5
}
```

Convenience predicates on it (`:7-21`): `isDramaticInMedia` (dramaQueen ‖ fieryCompetitor),
`isMentor` (mentor ‖ teamLeader), `isMoodDependent` (feelPlayer ‖ dramaQueen),
`isConsistent` (steadyPerformer ‖ quietProfessional). These four are ready-made conditioning
predicates for event probability.

Stored on `Player.personality` (`Domain/Models/Player/Player.swift:26`) as a **Codable composite
attribute** — i.e. FROZEN per migration-plan §4.2 (changing its shape needs a stage). Also on
`CollegeProspect.truePersonality` (`Domain/Models/Scouting/CollegeProspect.swift:30`).

### 1.2 `PersonalityArchetype` — `Domain/Enums/PersonalityArchetype.swift`

`String`-raw enum, 9 cases, persisted rawValues (`:3-12`) — **frozen names**:

| case | rawValue | tier (`:44-53`) |
|---|---|---|
| `teamLeader` | `"TeamLeader"` | positive |
| `loneWolf` | `"LoneWolf"` | neutral |
| `feelPlayer` | `"FeelPlayer"` | neutral |
| `steadyPerformer` | `"SteadyPerformer"` | positive |
| `dramaQueen` | `"DramaQueen"` | risky |
| `quietProfessional` | `"QuietProfessional"` | positive |
| `mentor` | `"Mentor"` | positive |
| `fieryCompetitor` | `"FieryCompetitor"` | risky |
| `classClown` | `"ClassClown"` | neutral |

Behavior hooks already defined on the enum (`:64-88`) — **use these, don't invent parallel ones**:
- `isFormSensitive` (`:68`) — fieryCompetitor, feelPlayer, dramaQueen, classClown
- `isFormImmune` (`:76`) — steadyPerformer, quietProfessional
- `isEgoArchetype` (`:82`) — fieryCompetitor, dramaQueen, loneWolf ("me-first temperaments")
- `interviewScoreContribution` (`:56`) — +10 / 0 / −10 by tier
- `displayName` (`:14`), `shortLabel` (`:29`)

`PersonalityTier` enum at `:90` (`positive, neutral, risky`) — **not** persisted, no rawValue.

### 1.3 How personality is generated — uniform 1/9 everywhere

All three cohorts draw **uniformly across all 9 archetypes and all motivations**:

- `Data/Import/LeagueGenerator.swift:693-696` — `PersonalityArchetype.allCases.randomElement()!`,
  `Motivation.allCases.randomElement()!` (unseeded).
- `Engine/Scouting/DraftClassBuilder.swift:555` (`let personalityArchetype = PersonalityArchetype.allCases.randomElement()!`)
  and `:587-590` (motivation uniform). Drawn *before* the mental-software ratings because
  `competitiveness` reads the archetype.
- `Data/Import/LeagueTemplateImporter.swift:277-280` — same, but through `SeededLeagueRandom`
  (`seed &+ traitSeedOffset`), so the fixed 2026 league reproduces byte-identically.

**Design consequence for Life Events:** each archetype is ~11% of the league, and the `.risky`
tier (dramaQueen + fieryCompetitor) is ~22%. Conditioning an arrest-class event on
`tier == .risky` alone would fire against a fifth of the league — base rates must be small and
multiplied by mental attributes, not by archetype alone.

### 1.4 `PersonalitySource` (the "#185 recent wave" — scouting provenance, NOT life events)

`Domain/Models/Scouting/CollegeProspect.swift:1160-1186`. `String`-raw enum:
`leagueConsensus`(strength 0), `report`(1), `workout`(2), `interview`(3), plus
`attributionLabel`. Stored on the prospect as `scoutedPersonalitySourceRaw: String? = nil`
(`:51`) with a typed bridge at `:58-61`. Written *only* by
`ScoutingEngine.recordPersonalityRead(...)` (`Engine/Scouting/ScoutingEngine.swift:181-198`),
which **refuses a weaker instrument** (`if source.strength < current.strength { return }`, `:193`).

This is about *what the scout knows*, not about the player's life. It is the right precedent for
"how much of a life event does the coach get to see", if fog is wanted on rumors.

### 1.5 Ego / character / reputation concepts across the tree

- **Player-level "character":** `isEgoArchetype` (above) is the only ego concept on a Player.
- **`CollegeProspect.redFlags: [String]?`** (`CollegeProspect.swift:191`, doc `:189-191`)
  — free-text off-field/character flags. Sister field `medicalConcerns: [String]?` (`:187`).
  Generated by `ScoutingEngine.generateRiskProfile(for:)`
  (`Engine/Scouting/ScoutingEngine.swift:3709-3748`) with an explicit distribution:
  **80% clean / 14% one medical / 4% one red flag / 2% both** (unseeded `Int.random(in: 1...100)`).
  Red-flag pool (`:3720-3728`): "Off-field arrest", "Failed drug test", "Practice habits
  questioned", "Locker-room concerns", "Missed team meetings", "Coach clashed with player",
  "Social media incident" — i.e. **the Life Events taxonomy already exists as strings.**
  - ⚠️ **GAP:** `Player` has **no** `redFlags` field. `DraftEngine` carries
    `personality: prospect.truePersonality` across (`Engine/Draft/DraftEngine.swift:349`, `:488`)
    but drops `redFlags` / `medicalConcerns`. Character history dies at the draft. Carrying it
    forward is an additive optional on `Player` → free per §4.1.
- **Reputation is coach/GM-level, not player-level:**
  - `Career.reputation: Int` (`Domain/Models/Career.swift:15`, seeded 50 at `:398`).
  - `DraftReputation` `@Model` (`Domain/Models/Draft/DraftReputation.swift:12-40`) — per
    career-season: `ownerTrust` (0..100, def 70), `fanMood` (0..100, def 60),
    `lockerRoomMood` (0..100, def 65), `mediaNarrativeRaw`. This is the **"WHAT CHANGED" chip
    source** — see §4. Note it carries a **non-optional** `careerID: UUID` and is deliberately
    excluded from `CareerScoped` (`Data/Persistence/CareerScope.swift:49-52`).

### 1.6 `MentalAttributes` — `Domain/Models/Player/PlayerAttributes.swift:31-53`

```swift
nonisolated struct MentalAttributes: Codable, Equatable {
    var awareness: Int        // :32
    var decisionMaking: Int   // :33
    var clutch: Int           // :34
    var workEthic: Int        // :35
    var coachability: Int     // :36
    var leadership: Int       // :37
    static func random() -> MentalAttributes   // :39 — uniform 40...99 each
    var average: Double                        // :50
}
```

**Frozen shape** — it is a Codable composite attribute on `Player.mental`
(`Player.swift:23`), migration-plan §4.2/§4.3. Do not add fields.

There is **no `composure` and no `discipline`** field. The nearest analogues:
- discipline-ish → `workEthic`, `coachability`
- composure-ish → `clutch` (in-sim nerve stat), plus `Engine/Match/HeatState.swift` (in-game
  mental state, not persisted per-player)

### 1.7 The two mental ratings that live *outside* `MentalAttributes`

Both are plain `Int` columns on `Player` with inline defaults (the free pattern):

- **`Player.learning: Int = 55`** (`Player.swift:44`) — playbook absorption, r≈0.6 with awareness.
- **`Player.competitiveness: Int = 55`** (`Player.swift:74`) — "fighter mentality": *"how a player
  answers adversity — a collapsed season, a demotion, a down year — and how immune he is to
  post-payday complacency"* (`:63-72`). **This is the single best-fitting existing attribute for
  Life-Event resilience/response.** Explicitly NOT read by `PlaySimulator`.
- Generation for both lives in `Domain/Models/Player/MentalAttributeModel.swift`:
  `learning(awareness:level:shift:seed:using:)` (`:72`, `:85`),
  `competitiveness(archetype:workEthic:clutch:seed:bounds:)` (`:115`). The `seed:` parameter is a
  **UUID byte** producing a deterministic draw (`:70-72`) — the exact dialect a Life Events roll
  should copy.
- Sentinel convention (`:24-45`): `55` = "never written"; `storedLearning` /
  `storedCompetitiveness` nudge a genuine 55 to 56 so backfills stay idempotent.

- **`Player.motivationStateRaw: String? = nil`** (`Player.swift:94`) with typed bridge
  `motivationState` (`:98-101`), defaulting `.focused`. Recomputed **once per offseason at
  `.trainingCamp`**. `Domain/Enums/MotivationState.swift`. → the natural place for a
  "distracted / motivated / wants out" modifier to land (see §6).
- **`Player.draftTruePotential: Int = 0`** (`Player.swift:112`) — anchor for the ±8 lifetime
  potential-drift cap.

### 1.8 Where personality already drives behavior (files consuming `.archetype`)

`Engine/Camp/RosterCutEvaluator.swift`, `Engine/Camp/VoluntaryWorkoutEngine.swift`,
`Engine/Contract/ContractNegotiationEngine.swift`, `Engine/Match/LiveGameEngine.swift`,
`Engine/Media/OwnerPersonaEngine.swift`, `Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift`,
`Engine/Scouting/ScoutingEngine.swift`, `Engine/Simulation/LockerRoomEngine.swift`,
`Engine/Simulation/SimPlayer.swift`, `Engine/Simulation/WeekAdvancer.swift`.
Also `Engine/Simulation/CoachingEngine.swift:2011` takes `playerPersonality:` directly.

---

## 2 · Existing event machinery

### 2.1 `LockerRoomEvent` — **THE precedent to copy**

`Domain/Models/League/LockerRoomEvent.swift`. **NOT a `@Model`** — `nonisolated struct
LockerRoomEvent: Codable, Identifiable` (`:9`). No SwiftData row, no `careerID` field; career
scoping is free because the blob lives *on* the `Career` row.

Fields (`:24-39`): `id: UUID`, `season: Int`, `week: Int`, `kind: Kind`, `title: String`,
`detail: String`, `playerIDs: [UUID]`, `playerNames: [String]`,
`var options: [LockerRoomEventOption]`, `var resolutionSummary: String?`.
Computed `var requiresResponse: Bool { resolutionSummary == nil && !options.isEmpty }` (`:42`).

`Kind` (`:11-22`), 5 cases: `.outburst`, `.playersOnlyMeeting`, `.mentorMoment`, `.starTension`,
`.moodLift`. Choice events = outburst + starTension; the other three are informational and
auto-apply.

`LockerRoomEventOption` (`:74-100`): `id`, `label`, `detail`, `targetMoraleDelta: Int`,
`teamMoraleDelta: Int`, `outcomeSummary: String`. Deltas deliberately within ±5.
**Convention: the LAST option is the passive one**, auto-applied if ignored for a week (`:33-36`).

Persistence — `Career.lockerRoomLogData` (`Career.swift:349`, `[LockerRoomEvent]` cap 12) and
`Career.pendingLockerRoomEventData` (`:355`, single pending). Bridges at `:962` / `:977`.

### 2.2 `LockerRoomEngine` — `Engine/Simulation/LockerRoomEngine.swift` (756 lines, static enum)

**Chemistry** (`:29-127`) — `calculateChemistry(players:collectEvents:) -> LockerRoomState`.
`LockerRoomState` (`:5-14`) is **never persisted** — recomputed on demand.
`rawChemistry = 50 + leadershipScore − toxicityScore`, clamped 0...100 (`:112`).
Per-archetype contributions (`:37-98`): teamLeader +8/+4, mentor +6/+3, dramaQueen −8/−4,
fieryCompetitor −5/−2, feelPlayer +3/−3, steady/quietPro +1, classClown +2/−2, loneWolf 0.
Motivation clustering: 3+ sharing a `Motivation` → +2 each (`:102-109`).
Labels (`:341`): 80+ Elite / 65 Strong / 50 Average / 35 Shaky / else Toxic.
`moraleTier` (`:352`): ≥75 high, 45..<75 medium, else low.

**Morale damping constants (`:129-148`) — Life Events must respect these:**
`moraleBaseline = 70` (`:132`), **`weeklyMoraleSwingCap = 3` (`:138`)**,
**`seasonMoraleSwingCap = 8` (`:141`)**, `reversionStep` pulls ±1 toward baseline.

- `applyMoraleEffects(...)` (`:169`) — once per season at week 18; archetype multipliers
  (feelPlayer ×1.5, dramaQueen ×1.4 on negatives, steady/quiet ×0.6, loneWolf ×0.7); clamp ±8,
  then `player.morale` clamped 1...100 (`:252`).
- `weeklyMoraleUpdate(...)` (`:270`) — ±3 base on W/L, ±1 chemistry, archetype variance, motivation
  modifiers, clamp ±3, plus reversion (`:330-334`).

**Position-room layer (R25)** (`:369-545`): `positionRooms` table of 5 (`:417-423`);
`activeMentorships` (`:428` — Mentor/TeamLeader, `yearsPro >= 4`, `leadership >= 65`, not holding
out, paired with greenest ≤2-yr same-position player); `activeConflicts` (`:475` — two hotheads in
a room with one at morale <65, or two ≥82 OVR at the same position within 2 points);
`positionGroupChemistry` (`:513`).

**Event generation** (`:562-722`) — `rollWeeklyEvent(players:wonLastGame:teamWins:teamLosses:week:season:)`:
- **Gate: `guard Int.random(in: 1...100) <= 25` (`:571`)** — flat 25%/week, before candidates.
  ⚠️ **Unseeded.** A Life Events roll should use the seeded dialect (§10.1).
- Weighted candidate pool `[(weight: Int, build: () -> LockerRoomEvent)]` (`:574`) with
  **preconditions baked into each builder** so impossible events contribute nothing:
  outburst `4 + (losing ? 2 : 0)` (`:577`), playersOnlyMeeting 3 (`:615`), mentorMoment 2 (`:634`),
  starTension `2 + (losing ? 1 : 0)` (`:649`), moodLift 1 (`:679`).
- Weighted pick by running subtraction (`:696-706`).
- `applyEventEffects(...)` (`:726`), `resolve(event:option:players:)` (`:741` — returns a copy with
  `resolutionSummary` set; **caller persists**).

**When it runs** — `WeekAdvancer.swift:1737` → `processLockerRoomWeek` (impl `:2509-2571`), which is
the complete loop worth copying verbatim:
1. auto-resolve a stale pending event with its **last** option (`:2522-2531`)
2. **never stack two open events**: `guard career.pendingLockerRoomEvent == nil else { return }` (`:2534`)
3. roll (`:2537`)
4. emit `InboxMessage` with `category: .playerIssue`, `actionRequired: event.requiresResponse`,
   `actionDestination: .lockerRoom` (`:2565-2570`); sender OC → DC → `.media(outlet: "Team Insider")` (`:2554-2558`)
5. `appendLockerRoomLog` (`:2574`)
UI resolution at `UI/Roster/LockerRoomView.swift:305-316`.

### 2.3 `EventEngine` / `EventTemplates` — **functionally DEAD, and it is a Life Events first draft**

`Engine/Event/EventEngine.swift` (289 lines) + `EventTemplates.swift` (534 lines).

- `struct GameEvent: Identifiable, Codable` (`:5-40`) — `id, type: EventType, headline, description,
  playerID?, coachID?, teamID, options: [EventOption], week, season`. **Not a `@Model`, not in
  `DynastySchema`, never encoded to `Career`** → vanishes on relaunch.
- **`struct EventOption` (`:42-68`) carries a four-meter effect vector**: `moraleEffect`,
  `lockerRoomEffect`, `ownerEffect`, `mediaEffect` — **the richest effect grammar in the codebase**
  and exactly what Life Events needs. `LockerRoomEvent` only moves player morale.
- **`enum EventType` (`:70-77`) — 18 cases, and it is already the Life Events taxonomy:**
  `holdout`, **`suspension`**, **`arrest`**, **`socialMediaIncident`**, `retirementSpeculation`,
  `podcastControversy`, `manOfTheYear`, `voluntaryWorkouts`, `rookieImpresses`, `coachConflict`,
  `coordinatorInterview`, `veteranReturn`, `injurySetback`, `aheadOfSchedule`, `freakInjury`,
  `contractDispute`, `tradeRequest`, `teamChemistry`.
- Probability model (`:104-136`):
  `eventChance = 0.40 * team.mediaMarket.mediaPressureMultiplier * (isLosing ? 1.3 : 1.0)`;
  second roll at `eventChance * 0.4`; dedupe by type; cap 2/week.
- Weighted pool `rollEvent` (`:177-288`) scales weights off roster facts:
  `underpaidPlayers.count * 3` (holdout), `dramaPlayers.count * 3` (socialMedia),
  `unhappyPlayers.count * 2` (tradeRequest), `negativeBias = (isLosing ? 2 : 0) + (dramaPlayers.isEmpty ? 0 : 2)`.
  Zero-weight entries filtered.
- `EventTemplates.buildEvent` (`:18-46`) — random template per type + `{playerName}` /
  `{teamName}` / `{coachName}` substitution (`:50-64`), 2-4 authored options each with signed
  4-meter deltas.
- `applyEventChoice` (`:144-173`) mutates `player.morale` (0-100), `owner.satisfaction` (0-100),
  `coach.reputation` (1-99). Note `:156-161`: `lockerRoomEffect` is a **stub** that re-adds
  `effect/2` to the same player's morale.

**Dead-code verdict.** Only caller: `WeekAdvancer.swift:1598` → `WeekAdvancer.lastEvents` (`:41`).
Only consumer: `CareerShellView.swift:3008` — `let hasPendingEvents = !WeekAdvancer.lastEvents.isEmpty`,
**a bool only**. **`applyEventChoice` has zero callers.** No view ever renders a `GameEvent`.

> **Strong recommendation:** Life Events should *absorb* `EventEngine`/`EventTemplates` rather than
> live beside it. Its `EventType` taxonomy, its 4-meter `EventOption`, its roster-fact-weighted
> pool and its `{placeholder}` template library are the design already written down; what it lacks
> is persistence, a UI, and a wired `applyEventChoice`. Shipping a second parallel system while
> this one sits half-built is how the `FAStorylineEvent` orphan (§2.5) happened.

### 2.4 `LeagueNarrativeEngine` / `LeagueNarrativeState`

`Engine/Media/LeagueNarrativeEngine.swift` (1262 lines).
`nonisolated struct LeagueNarrativeState: Codable` (`:11-54`): `season`, `week`,
`rankings: [PowerRankingEntry]`, `mvpPoints: [UUID: Double]`, `mvpRace: [MVPCandidate]`,
`reportedStreaks: [UUID: Int]`, `hotSeatReported: Set<UUID>`, `arcCheckpointsDone: Set<Int>`,
`divisionRacesReported: Set<String>`, `franchiseArcsReported: Set<String>?`.

**Two patterns to steal:**
1. **Anti-repeat ledgers** — every story type keeps an "already told" marker set so the news cycle
   cannot loop. A Life Events state needs the same (per-player cooldowns, per-kind season caps).
2. **The header comment at `:32-40`** spells out why late-added fields must be **`Optional` and
   last**: synthesized `Codable` throws on a missing key and would nuke the whole blob. This is the
   §8 rule stated at the point of use — **read it before designing `LifeEventsState`.**

Persisted at `Career.leagueNarrativeData` (`Career.swift:236`), bridge `:777`.
Trigger `WeekAdvancer.swift:1508` → `updateWeekly(...)`, returns `WeeklyUpdate { state, news }`,
`maxWeeklyItems = 6` (`:101`). Story priority order at `:151-207`. Surfaced in
`UI/News/NewsView.swift:193`, `:615`, `RoundResultsView.swift`, `LeagueHistoryView.swift:269`.

### 2.5 Every other storyline system, and which are traps

| System | Emits | Persisted | Surfaced | Live? |
|---|---|---|---|---|
| `DraftDramaEngine` `Engine/Draft/DraftDramaEngine.swift:15` | `DramaEvent` (`:17-34`), 7 cases | **nothing** (in-memory) | `DraftDayCoordinator.swift:52` → `DraftBroadcastRail.swift:948` | live, draft-night only |
| `DraftEventEngine` `Engine/Draft/DraftEventEngine.swift:37` | `PlannedDraftEvent` (`:5-22`) | would map to `@Model DraftEvent` | — | **DEAD — "⚠️ NOT WIRED" at `:29-36`**, zero callers |
| `DraftEvent` `Domain/Models/Draft/DraftEvent.swift:8` | `@Model`, `careerID: UUID? = nil` (`:15`), `payloadJSON: String?` | SwiftData | `DraftDayCoordinator.recordStoryBeats` | live |
| `HardKnocksNarrator` `Engine/Camp/HardKnocksNarrator.swift:10` | 5-10 `HardKnocksEvent`/camp | `@Model HardKnocksEvent` (`Domain/Models/Camp/HardKnocksEvent.swift:7`, `careerID` `:14`) | `WeekAdvancer.swift:8358` writes; `CareerDashboardView.swift:3567` → `HardKnocksToast` | live |
| `FAStorylineEvent` `Domain/Models/FreeAgency/FAStorylineEvent.swift:9` | 8 types (`:4`) | `@Model`, `CareerScoped` | **8 producers, ZERO readers** — the reader views exist only as stale artifacts under `dynasty/build/` | ⚠️ **write-only orphan** |
| `TamperingRumorEngine` `Engine/FreeAgency/TamperingRumorEngine.swift:12` | `TamperingRumor` (`:17-29`) | no | `WeekAdvancer.swift:4448-4457` → inbox + news; `FinalPushView.swift:1625` | live |
| `RevengeTourEngine` `Engine/FreeAgency/RevengeTourEngine.swift:14` | flags not events: `Player.cutByTeamID` + `cutAt`; `grudgeWindowSeasons = 2` (`:17`), `grudgePerformanceBoost = 0.05` (`:20`) | fields on `Player` | — | half-wired (`markCut` bypassed by `CapManagementEngine.swift:693`, `WaiverWireEngine.swift:78`) |
| `MilestoneTracker` `Engine/FreeAgency/MilestoneTracker.swift` | `FAMilestone` (`:20-26`) + `CareerCrossing` | `Player.milestoneRaw`; dedupe via `Career.announcedMilestoneKeysData` | `FAWeeklyView.swift:338`, `MilestoneSigningSheet`, `NewsGenerator.swift:1277-1404` | live |
| `CareerArcEngine` `Engine/Draft/CareerArcEngine.swift:16` | `GemFlashback`; updates `CareerArcState` | `@Model CareerArcState` (`:11`), `milestoneFlagsRaw: Int` bitmask | `WeekAdvancer.swift:3110` | live |
| `OwnerPersonaEngine` whims `Engine/Media/OwnerPersonaEngine.swift:137` | `OwnerWhim` — `status(.pending/.complied/.defied)`, 5 templates (`:165-187`) | JSON `Career.swift:259` | `WeekAdvancer.swift:1644`; `OwnerMeetingView.swift:143-231`; `CareerDashboardView.swift:2765` badge | live |

> **Avoid the `FAStorylineEvent` trap: wire the surface before the generator.** Eight engines write
> rows nobody ever reads. A Life Events wave must ship generator + inbox + pop-up + a log view in
> the same commit.

---

## 3 · News & popup surfacing

### 3.1 `InboxMessage` — the coach's mailbox

`Domain/Models/League/InboxMessage.swift`. **A `struct`, not a `@Model`** — `Identifiable, Codable`
(`:8`), persisted as JSON on `Career`.

Fields (`:9-19`): `let id: UUID`, `let sender: MessageSender`, `let subject: String`,
`let body: String`, `let date: String` (human-readable, e.g. `"Week 1, Season 2026"`),
`let category: MessageCategory`, `let actionRequired: Bool`,
`let actionDestination: TaskDestination?`, **`var isRead: Bool`** (the only `var`),
`let attachments: [MessageAttachment]`. Memberwise init with defaults at `:21-43`.

- `enum MessageSender: Codable, Equatable` (`:48-98`) — `.owner(name:)`, `.offensiveCoordinator(name:)`,
  `.defensiveCoordinator(name:)`, `.scout(name:)`, `.media(outlet:)`, `.leagueOffice`,
  `.playerAgent(name:)`, `.developmentStaff`; each has `displayName`, `icon`, `roleLabel`.
  → **`.leagueOffice` is the natural sender for a suspension notice.**
- `enum MessageCategory: String, Codable, CaseIterable` (`:102-130`) — `rosterAnalysis, staffUpdate,
  scoutingReport, tradeOffer, contractRequest, mediaRequest, ownerDirective, leagueNotice,
  playerIssue, gamePrep, draftPrep`. → **`.playerIssue` (used by locker room) and `.leagueNotice`
  (suspensions) cover Life Events with no new cases.**
- `MessageAttachment` (`:135-149`), `InboxFilter` (`:153-177` — `.all/.actionRequired/.unread`),
  `TaskDestination.inboxDisplayName` (`:181-233`).

**Persistence:** `Career.inboxData: Data? = nil` (`Career.swift:181`); bridge `Career.swift:642-660`
— **oldest first, capped at 200** (`Array(newValue.suffix(200))`).

**Lifecycle:**
1. produced → appended to `WeekAdvancer.lastInboxMessages` (`WeekAdvancer.swift:44`), cleared at
   `:184` / `:912`. ~60 append sites in `WeekAdvancer`, plus `DraftDayCoordinator.swift:987`,
   `TradeView.swift:1665`, `ProDayTourView.swift:993`, `FAWeeklyView.swift:972`.
2. drained → `CareerShellView.collectInboxMessages()` (`CareerShellView.swift:3136-3143`) — **the
   only consumer**; called from `.onChange(of: navigationPath)` (`:708`), `currentPhase` (`:712`),
   `currentWeek` (`:721`), and pre-advance (`:1482`).
3. hydrated → `CareerShellView.swift:3270-3286`.
4. persisted → `persistInbox()` (`:3123-3126`) and the write-through `inboxBinding` (`:3110-3119`).
5. marked read → `InboxView.markAsRead(messageID:)` (`UI/News/InboxView.swift:114-119`).

### 3.2 `InboxEngine` — how to inject a message

`Engine/Media/InboxEngine.swift` (1868 lines, static enum).
Bulk generator: `generatePhaseMessages(phase:career:team:coaches:owner:) -> [InboxMessage]` (`:19`),
switching (`:33-104`) into ~15 per-phase private generators.
~19 single-message factories at `:1001-1825` (trade wire, poach warnings, scouting digests,
`characterFindingsMessage` `:1603`, retirement/comeback `:1720-1785`).

**There is NO `InboxEngine.send(...)`.** The canonical injection is to construct the struct and push
it on the channel — copy this:

```swift
WeekAdvancer.lastInboxMessages.append(InboxMessage(
    sender: .leagueOffice,
    subject: "...",
    body: "...",
    date: InboxEngine.dateLabel(week: career.currentWeek,      // :1825 — the public helper
                               season: career.currentSeason,
                               phase: career.currentPhase),
    category: .leagueNotice,
    actionRequired: true,
    actionDestination: .lockerRoom
))
```
Reference sites: `WeekAdvancer.swift:2046`, `:2562`, `:5256`.
**Dedupe convention: callers dedupe by `subject`** — `CareerShellView.swift:1371`,
`FAWeeklyView.swift:970`, `ProDayTourView.swift:991`.

### 3.3 `NewsItem` / `NewsGenerator`

`Engine/Media/NewsGenerator.swift:5-47` — `NewsItem` (`id, headline, body, category, week, season,
relatedTeamID?, relatedPlayerID?, sentiment`), `NewsCategory` (`:39-43`, **includes
`offFieldIncident`**), `NewsSentiment` (`:45`).
Generators: `generateWeeklyNews(...)` (`:57`), `generateOffseasonNews(...)` (`:125`),
`characterFindingNews` (`:572`), `rookieClassGraded` (`:865`), `rookieClassInboxMessage` (`:887`),
`TradeNewsFactory` (`:949`), `MilestoneNewsFactory` (`:1251`), `RetirementCaseNewsFactory` (`:1595`).

Staged on `WeekAdvancer.lastNewsItems` (`:38`), persisted at `WeekAdvancer.swift:955-957`
(`career.newsLog = lastNewsItems + career.newsLog`), stored `Career.newsLogData` (`:224`), bridge
`:709-720` — **newest first, capped at 150**. Read at `UI/News/NewsView.swift:442`.

### 3.4 The screens

| File | Role |
|---|---|
| `UI/News/InboxView.swift:31` | **PRIMARY personal feed.** `InboxView(career:messages:onNavigate:)`. `DSLensTabs` over `InboxFilter` (`:131-156`), `DSListRow` rows (`:182`), `DSEmptyState` (`:318`), reverses for display (`:46`), 4-bucket sort rank (`:58-63`). |
| `UI/News/MessageDetailView.swift:7` | Detail; attachments `:54-57`; CTA for `actionDestination` `:63-65`. |
| `UI/News/NewsView.swift:64` | **League-wide "newspaper".** `NewsFilter` (`:6-46`), `DateBucket` (`:50`). `NewsView.swift:110` already filters `.offFieldIncident` into a lens. |
| `UI/News/OwnerBriefing.swift` | **Not a feed** — a card vocabulary (`OwnerBriefingHeader`, `OwnerPatienceCard`, `OwnerSatisfactionCard`, `OwnerWarningCard`, …) composed by `OwnerMeetingView.swift:74-95` and `IntroSequenceView.swift:240`. |

**Routing:** `TaskDestination` (`Engine/Simulation/TaskGenerator.swift:186`) has `.inbox` and
`.news`. Shell route enum `CareerShellView.ShellDestination` (`:1836-1856`);
`handleTaskNavigation(_:)` (`:2341`) maps `.news → .news` (`:2380`), `.inbox → .inbox` (`:2383`);
views mounted in `destinationView(for:)` (`:1859`) — `NewsView` `:2005-2010`, `InboxView` `:2023-2029`.
Entry points: top-bar envelope + unread badge (`CareerShellView.swift:471-476`,
`TopNavigationBar.swift:194-212`); dashboard Messages panel (`CareerDashboardView.swift:712-813`).

### 3.5 Press conference + the promise ledger

`Engine/Media/PressConferenceEngine.swift`: `PressQuestion` (`:5`), `PressResponse` (`:27`),
**`PressEffects { ownerSatisfaction, playerMorale, mediaPerception, legacyPoints, fanExcitement }`**
(`:49`, with `static func +` at `:71`), `ResponseTone` (`:82`), `PressConferenceResult` (`:113`),
**`GameFacts` (`:161`)** — *the sole world-event injection surface for question selection*.
Entry points: `generateIntroConference` (`:247`), **`generateWeeklyPressConference(career:team:
lastGameResult:week:facts:)` (`:275`)**, `buildResult` (`:394`).

`Engine/Media/PressEngine.swift`: **tone matrix as an ASCII table in the header at `:24-53`**,
implemented as `situationAdjustment` (`:431`), `standingAdjustment` (`:502`),
`personaAdjustment` (`:539`), `stanceAdjustment` (`:572`), `lockerRoomAdjustment` (`:602`),
composed by `resolvedEffects(for:question:context:)` (`:370`).
`PressContext` (`:200`), builders `introContext` (`:267`) / `weeklyContext` (`:287`),
`situation(team:week:facts:)` (`:311`), `PressSituation` (`:132`), `ReporterStance` (`:83`),
`LockerRoomBand` (`:172`). Repetition ratchet `:632-653`. Fogged preview `ReactionHint` (`:667`),
`ReactionPreview` (`:712`), `preview(...)` (`:726`).

**Promise ledger** (`PressEngine.swift:862-1079`): `PressPromiseRecord` (`:867`) with
`Kind { championship, playoffs, overhaul }` (`:871`), `isPending` (`:923`);
`promiseKind(for:)` (`:928` — only `.confident`/`.aggressive`, keyword match);
`commit(result:to career:)` (`:951`); `PromiseSettlement` (`:973`);
`settlePromises(...)` (`:991`); `payoff(for:met:)` (`:1064`).
Settled once, in `WeekAdvancer.recordSeasonSummary` at `.superBowl`.
A broken promise emits **both** a `NewsItem` (`:1030`) **and** an `InboxMessage` from
`.media(outlet: "The Gridiron Weekly")`, subject `"About that quote"` (`:1046-1055`) — a good
template for a Life Event's engine→inbox emission.

**Can a life event feed a press question?** Not today — no hook. Two clean insertions:
(a) add fields to `GameFacts` (`:161`) + a branch in `generateWeeklyPressConference` (precedent:
the R18 fact block at `:879`, R19 rivalry `:1033`, R29 narrative `:1133`); or
(b) add a case to `PressEngine.PressSituation` (`:132`) plus a column in `situationAdjustment` (`:431`).
Question *text* is hard-authored per generator; nothing reads an external event store.
Views: `WeeklyPressConferenceView.swift:21` is an 8-line adapter onto
`PressConferenceView.swift:89`. Trigger `WeekAdvancer.swift:1538` → parked on
`pendingPressConference`/`pendingPressContext` → consumed `CareerShellView.swift:1528-1535`
(`shellCover = .press`) → rendered `:829-845`.

### 3.6 THE POPUP PATTERN — `DSResultSheet` + the single enum-sheet point

**`UI/Common/DSResultSheet.swift:28`** — memberwise init only:

```swift
DSResultSheet(
    tone: DSResultSheet.Tone = .neutral,   // :86  .good/.neutral/.bad (enum :32)
    eyebrow: String,                       // :88  screen ident, uppercased
    headline: String,                      // :90  the outcome in one line
    message: String? = nil,                // :92  1-2 sentences, Markdown emphasis honoured
    chips: [DSResultSheet.Chip] = [],      // :94  "what changed"
    cost: String? = nil,                   // :97  becomes the DSActionBar explainer
    continueTitle: String = "Continue",    // :98
    onContinue: () -> Void                 // :99  the ONLY commit on the surface
)

DSResultSheet.Chip(id:label:value:context:valueColor:contextColor:)   // :59-84
```
Fixed layout: headline block (`:126`) → "WHAT CHANGED" 3-band `Grid` (`:160`) → `DSActionBar` with
the cost explainer + a **single** primary `"<continueTitle> →"` (`:116-119`).
**The sheet has no dismissal of its own** — unskippability is the caller's job via
`.interactiveDismissDisabled(true)`. This is where the one-gold-fill rule is satisfied for free.

**The single enum-sheet convention** — documented at `CareerShellView.swift:11-33`: one sheet slot
and one cover slot, both `item`-driven, because sibling presentation modifiers silently lose races.

| element | file:line |
|---|---|
| sheet enum | **`CareerShellView.swift:36`** — `private enum ShellSheet: String, Identifiable { case calendar, voluntaryWorkout, ownerReview, holdout, result, settings }`, `id` `:48` |
| cover enum | **`CareerShellView.swift:53`** — `private enum ShellCover: String, Identifiable { case press, roundResults, rookieReveal, fired }` |
| state | `:63 shellSheet`, `:64 shellCover`, `:68 lastShellSheet`, `:69 lastShellCover` |
| `.sheet(item:)` | **`CareerShellView.swift:732`** |
| `.fullScreenCover(item:)` | **`CareerShellView.swift:735`** |
| sheet switch | `:741 shellSheetContent(_:)` — `.calendar :745`, `.voluntaryWorkout :768`, `.ownerReview :771`, `.holdout :787`, **`.result :801`**, `.settings :817` |
| cover switch | `:825 shellCoverContent(_:)` — `.press :829`, `.roundResults :846`, `.rookieReveal :866`, `.fired :880` |
| dismiss handlers | `:900 handleSheetDismiss()` (exhaustive, `:907-940`), `:957 handleCoverDismiss()` (`:962-976`) |
| result payload | `:84 pendingResult: ShellResult?`, `:87 struct ShellResult { tone, eyebrow, headline, message, chips, cost }` |

**Recipe to register a Life Event pop-up:**
1. add a case to `ShellSheet` (`:36`) — e.g. `case lifeEvent`
2. add a `@State` payload property (the enum is a **tag, not a box** — stated at `:31-33`)
3. add the branch in `shellSheetContent` (`:741`)
4. **add the case in `handleSheetDismiss` (`:900`)** — the switch is exhaustive *on purpose* so a
   new slot cannot silently skip cleanup (`:812-816`)
5. present with `shellSheet = .lifeEvent`, **never a new `.sheet` modifier**

**For the terminal "here's what happened" beat, use the existing `.result` slot:** set
`pendingResult = ShellResult(...)` then `shellSheet = .result`. Live example — holdout resolution
at `CareerShellView.swift:1147-1157`, handed off in `handleSheetDismiss` at `:932`
(`if pendingResult != nil { shellSheet = .result }`).

`CareerDashboardView` has its own parallel slot: `ActiveSheet` (`:73`, hand-written `id` `:83-90`),
`activeSheet` (`:93`), `.sheet(item:)` at **`:504`** with the switch at `:505-552`; cover
`:554 .fullScreenCover(item: $coachedSession)`. Rationale comment at `:64-72` (four sibling
`.sheet`s used to hang off one chain; only the last presented).

### 3.7 Non-modal toast / banner

- **`UI/Camp/HardKnocksToast.swift:9`** — `HardKnocksToast(event:onDismiss:)`, bottom-edge slide+fade,
  4 s dwell (`:16`), tap expands a full-story `.sheet` (`:29`). Mounted
  `CareerDashboardView.swift:598-607` as `.overlay(alignment: .bottom)`, gated on
  `latestHardKnocksEvent` (`:171`) + a shown-set `shownHardKnocksEventIDs` (`:174`); loader
  `loadLatestHardKnocksEvent()` `:3567-3585`.
- **`UI/Camp/WaiverClaimsBanner.swift:9`** — `WaiverClaimsBanner(claims:onDismiss:)`, `Claim` at
  `:12`, top-edge, ~8 s dwell, shows first 4 + "…and N more", manual X (`:33-41`). Mounted
  `CareerShellView.swift:540-548` as `.overlay(alignment: .top)` on the `NavigationStack`
  (so it sits below the persistent top bar), `.zIndex(1)`; state `pendingWaiverClaims` (`:424`),
  filled by `collectWaiverClaims()` (`:1638-1670`).

**Convention:** toasts/banners are `.overlay(alignment:)` + a `@State` optional payload + a
shown-ID set for idempotence + a self-cancelling `Task` dwell. They are **NOT** registered in the
sheet enums — those slots are for modals only. → **Small life events = toast; big ones = the
`ShellSheet` modal.**

---

## 4 · Morale / chemistry meters

### 4.1 The "WHAT CHANGED" chips — where they actually live

Not in `DraftRecapView`. They render in
**`UI/Draft/Components/RoundRecapSheet.swift`**: `changedBlock` (`:171`, a 3-band `Grid`),
`var chips: [DSResultSheet.Chip]` (`:218`) → `"Cards in"`, then
`deltaChip(id:"owner", label:"Owner", delta: recap.ownerTrustDelta)` (`:228`),
`"fans"` → `fanMoodDelta` (`:229`), `"locker"` → `lockerRoomDelta` (`:230`).
Narrative line sums all three at `:164`. Deltas computed in
`Engine/Draft/RoundRecapData.swift:76-89` as `after.X − before.X`.

**Backing store: `DraftReputation`** (`Domain/Models/Draft/DraftReputation.swift:12`) — a `@Model`
**per career-season** (`seasonYear` + non-optional `careerID`):
`ownerTrust: Int` 0..100 def 70 (`:17`), `fanMood: Int` 0..100 def 60 (`:18`),
`lockerRoomMood: Int` 0..100 def 65 (`:19`), `mediaNarrativeRaw: String` (`:20`).
**Granularity: career-season level — neither team-level nor player-level.**
Mutated **only** by `Engine/Draft/ReactionsEngine.swift:113 apply(_:to:)` (clamped 0...100) from the
grade matrix at `:70-100`. **`media` is a no-op in `apply` (`:118-122`)** — it has no numeric stat.
Read outside the draft at `ContractNegotiationView.swift:1687` and `FinalPushView.swift:1618`
(ownerTrust is one of five GM-factor inputs; `ContractNegotiationEngine.swift:142` documents 70
as neutral).

### 4.2 Player-level and team-level

**`Player.morale: Int`** — `Domain/Models/Player/Player.swift:114`. **The only player morale meter.**
Range 1...100 in practice (every engine clamps `max(1, min(100, …))`); `EventEngine.swift:153`
clamps 0...100 — a minor inconsistency to normalise if Life Events absorbs that file.
`Player.loyaltyYears: Int = 0` (`:430`) is a counter, not a meter. **No `happiness`, no per-player
`chemistry`, no per-player `satisfaction`.**

**`Team`** — `Domain/Models/Team/Team.swift`: **no `chemistry`, no `morale`, no `culture`, no fan
field.** Chemistry is *always* derived on demand from the roster; `LockerRoomState` is never
persisted. The one relevant team property is `team.mediaMarket.mediaPressureMultiplier`, which
amplifies event probability and negative owner deltas — **the natural market-size lever for how
loudly a life event lands.**

### 4.3 Owner meter

`Domain/Models/Team/Owner.swift` (`@Model`, `careerID: UUID? = nil` `:11`):
**`var satisfaction: Int`** — 0–100, default 70. Companions: `patience` 1–10,
`spendingWillingness` 1–99, `meddling` 1–99, `prefersWinNow: Bool`; budgets; facility levels
(default 2 = neutral).

Mutation sites for `satisfaction`:
- `Engine/Media/OwnerSatisfactionEngine.swift:107` — `min(100, max(0, satisfaction + delta))`,
  weekly from `WeekAdvancer.swift:1604`. Delta built `:16-105`: win% (win-now +5/+2/−6/−3; patient
  +4/+1/−4/−2), loss margin (≥5 → −4, ≥3 → −2), patience multiplier on negatives (1-3 → ×1.5,
  7-10 → ×0.6), `OwnerArchetype.negativeSwingMultiplier`, media pressure on negatives,
  `meddling > 60` → −1, **±1 per negative/positive news item**, +10 playoff, +25 championship.
  → **the "±1 per news item" term means a Life Event that emits a negative `NewsItem` already
  moves the owner meter for free. Watch for double-counting if the event also applies its own
  `ownerEffect`.**
- `Engine/Media/OwnerPersonaEngine.swift:222`/`:225` — whim comply `+3` / defy `−5` (patience ≤3) or `−4`.
- `Engine/Event/EventEngine.swift:165` — `applyEventChoice`, **dead (no callers)**.
- `CareerShellView.swift:1807`, `IntroSequenceView.swift:116` — press `totalEffects.ownerSatisfaction`.
Firing gate: `OwnerSatisfactionEngine.checkFiring` (`:114-140`) —
`criticalThreshold = max(10, 20 − patience)`, `dangerThreshold = max(20, 35 − patience)`.
`OwnerArchetype.from(owner)` (`OwnerPersonaEngine.swift:25-30`) is a pure derivation.

### 4.4 Fan sentiment — **there is no persistent team-level fan meter**

Three disconnected things carry "fan":
1. `DraftReputation.fanMood` 0..100 def 60 — draft-season scoped, `ReactionsEngine` only.
2. **`Career.reputation: Int`** (`Career.swift:15`, seeded 50 at `:398`) — the closest durable
   standing meter. Mutated `WeekAdvancer.swift:5603`, `OwnerPersonaEngine.swift:318` (whim-defiance,
   cap +4), `CoachingStaffView.swift:3020`, `FinalPushView.swift:1537`
   (`career.reputation + penalty.fanMood / 2` — the only place `fanMood` leaks into a durable value).
3. Fan deltas returned as tuples that are usually **discarded**:
   `LoyaltyEngine.letWalkPenalty` (`Engine/FreeAgency/LoyaltyEngine.swift:35-42`) →
   `(ownerTrust: -10, fanMood: -15)` for 6+ yr vets, `(-5, -10)` for 4+;
   `CommunityImpactEngine.civicTierBonus` (`:15-24`) → `(fanMood:, ticketSales:)`.

**If Life Events needs a fan meter, one does not exist — you would be creating it.**
`Career.reputation` is the only durable candidate. Scope this explicitly before design.

### 4.5 The meter surfaces

- `UI/Roster/LockerRoomView.swift` — `loadData()` (`:1022-1032`) recomputes
  `calculateChemistry` (`:1026`) + `positionGroupChemistry` (`:1029`) from `Player.morale` +
  personality **on every appearance**; reads `career.lockerRoomLog` (`:1032`) and
  `career.pendingLockerRoomEvent` (`:1030`). Displays `chemistryCard` (`:402`),
  `moraleDistributionCard` (`:537`), per-group avg morale (`:82-89`), top issues (`:95-148`),
  `pendingEventCard` (`:221`) with `moraleDeltaPill` showing each option's `targetMoraleDelta`
  ("Them") and `teamMoraleDelta` ("Team") (`:254-255`). Resolution at `:305`.
  → **This is the ready-made host screen for a Life Events log + pending-decision card.**
- `UI/Roster/SquadDynamicsView.swift` — pure analytics, same single `calculateChemistry` call
  (`:1118-1122`); no event log, no pending event.
- **`UI/Career/CareerDashboardView.swift:3063 satisfactionScoresRow`** — the four top-level meters a
  Life Event would most plausibly move: **Owner** = `team?.owner?.satisfaction ?? 50`,
  **Morale** = `teamMorale` (`@State` `:51`, computed `:3470` as the plain roster mean of
  `player.morale`), **Media** = `career.legacy.mediaReputation`
  (`Domain/Models/League/LegacyTracker.swift:10`, range **−100...100**, clamped `:74`),
  **Legacy** = `career.legacy.totalPoints`.

---

## 5 · AVAILABILITY — and the biggest surprise in this map

### 5.1 The injury model

`Domain/Models/Player/InjuryRecord.swift` (69 lines, **all plain structs/enums, no `@Model`**):
- `struct InjuryRecord: Codable, Identifiable, Equatable` (`:7-28`) — `id: UUID = UUID()` (`:9`),
  `injuryTypeRaw: String` (`:11`), `weeksOut: Int` (`:13`), `season: Int = 0` (`:15`),
  `week: Int = 0` (`:17`); computed `injuryType: InjuryType?` (`:19`), `summary: String` (`:22`).
- `enum RehabStatus: String, Codable, CaseIterable` (`:36-56`) — **persisted rawValues are
  PascalCase and differ from the case names**: `.aheadOfSchedule = "AheadOfSchedule"` (`:37`),
  `.onTrack = "OnTrack"` (`:38`), `.setback = "Setback"` (`:39`).
- `struct ReturnDecision` (`:63-69`) — stored JSON on `Career.pendingReturnDecisions`.
- Load-bearing doc at `:33-35`: *"Purely informational — the weeks counter itself is the source of
  truth for availability."*

`Domain/Enums/InjuryType.swift` (39 lines) — `enum InjuryType: String, Codable, CaseIterable`,
10 cases whose **rawValues are display strings** (persisted in both `InjuryRecord.injuryTypeRaw`
and `Player.injuryType`): `hamstring="Hamstring"` (`:4`), `ankle="Ankle Sprain"` (`:5`),
`knee="Knee (MCL/ACL)"` (`:6`), `shoulder="Shoulder"` (`:7`), `concussion="Concussion"` (`:8`),
`back="Back"` (`:9`), `foot="Foot"` (`:10`), `groin="Groin"` (`:11`), `wrist="Wrist/Hand"` (`:12`),
`ribs="Ribs"` (`:13`). `baseRecoveryWeeks` (`:16-29`, knee 4...16 max, concussion 1...3);
`severity: Int` 1-5 (`:32-38`, only 1-4 used).

**Weeks-out modelling: a single `Int` countdown. No dated return, no IR list.**

### 5.2 `Player` availability fields

Core quartet (**in `init`, so no stored-property defaults**) — `Player.swift`:
`isInjured: Bool` (`:116`, init default `false` `:612`), `injuryWeeksRemaining: Int` (`:117`, `:613`),
`injuryType: InjuryType?` (`:118`, `:614`), `injuryWeeksOriginal: Int` (`:119`, `:615`).

Medical 2.0 (R28), default-value properties not in `init`: `injuryHistoryData: Data? = nil` (`:532`),
`rehabStatusRaw: String? = nil` (`:536`), `rushBackWeeksRemaining: Int = 0` (`:541`),
accessors `rehabStatus` (`:544-547`), `injuryHistory` (`:551-562`),
`priorInjuryCount(of:)` (`:565-567`).

Other flags: `isHoldingOut: Bool = false` (`:235`), `isRetired: Bool = false` (`:241`),
`rosterStatusRaw: String = RosterStatus.active.rawValue` (`:263`),
`practiceSquadTeamID: UUID? = nil` (`:269`), `rosterStatus` (`:272-275`),
`isOnPracticeSquad` (`:280-282`), `employerTeamID` (`:287-289`),
`teamID: UUID? = nil` (`:135` — **the de-facto "can he dress" flag**, ~240 call sites, see `:250-255`),
`isFranchiseTagged` (`:210`). Counters: `gamesPlayedThisSeason: Int = 0` (`:439`),
`gamesStartedThisSeason: Int = 0` (`:452`).

**There is NO `gamesMissed`, NO IR flag, NO `isActive`/`isInactive`, NO gameday-inactive concept.**
`RosterStatus` (`:655-696`) has exactly three cases — `active` / `practiceSquad` / `campBody`
(rawValues are the **implicit lowercase case names**, `:663-678`) — and its doc at `:659-662` states
the design decision outright:

> *"The NFL's injured-reserve / PUP / exempt lists are separate mechanics the game models through
> `isInjured` + `injuryWeeksRemaining`, so adding them here would give the same state two spellings."*

### 5.3 `MedicalEngine` — `Engine/Medical/MedicalEngine.swift` (337 lines, static enum)

`injuryCheck(player:playType:doctor:physio:trainer:frequencyMultiplier:) -> InjuryType?` (`:29-36`)
— base 0.5%/play (`:41`), fatigue (`:44`), durability (`:47`), doctor (`:51`), rush-back window
(`:56-58`), camp workload (`:72`), facility (`:78`). Multipliers `:91-110`, weighted type `:115-130`
(recurrence +60%/prior, capped 2.5×), `recoveryWeeks(...)` `:143-148`,
`weeklyFatigueRecovery(...)` `:179-191`.

- **`applyInjury(player:injuryType:doctor:physio:season:week:)` (`:199-206`) — THE one creation
  point.** Sets `isInjured = true`, `injuryType`, `injuryWeeksRemaining`, `injuryWeeksOriginal`,
  `rehabStatus = .onTrack`, `rushBackWeeksRemaining = 0` (`:215-221`); appends `InjuryRecord`
  (`:224-231`); erodes durability on recurrence (`:236-242`).
- `processWeeklyRehab(player:trainer:) -> RehabResult` (`:279-317`) — 10/80/10 ahead(−2)/on-track(−1)/
  setback(0 or +1). Legacy deterministic path `processWeeklyRecovery` (`:249-260`).
- `rushBack(player:)` (`:322-327`) — clears injury, `rushBackWeeksRemaining = 2`, `fatigue += 15`.
- **`clearInjury(player:)` (`:330-336`) — THE one heal point.**

**IR designations: none.** `MedicalEngine` never touches `rosterStatus`. The string "IR" appears in
the whole codebase only as flavour text on a dead event option
(`Engine/Event/EventTemplates.swift:396`, `EventOption(label: "Place on IR", …)` — morale deltas only).

### 5.4 ⚠️ HOW THE SIM CONSUMES AVAILABILITY — **injury does NOT gate the regular-season sim**

**There is exactly ONE choke point per simulator, and it filters holdouts only.**

- Quick sim — `Engine/Simulation/GameSimulator.swift:130-131`:
  ```swift
  let homeRoster = (homeRosterOverride ?? homeTeam.currentRoster()).filter { !$0.isHoldingOut }
  let awayRoster = (awayRosterOverride ?? awayTeam.currentRoster()).filter { !$0.isHoldingOut }
  ```
- Coached/live — `Engine/Match/LiveGameEngine.swift:1281-1289`: the same
  `filter { !$0.isHoldingOut }` on both squads. `LiveGameEngine.injuredPlayerIDs` (`:689`) is seeded
  **empty** and only ever gains IDs from in-game rolls (`:3146`), never from `player.isInjured`.
- `Team.currentRoster()` (`Domain/Models/Team/Team.swift:147-154`) is an unfiltered
  `#Predicate<Player> { $0.teamID == ownID }` — no health/status filter.

**Why the exclusion is total:** `SimPlayer` (`Engine/Simulation/SimPlayer.swift:13-56`) **has no
`isInjured` field** — `init(from player:)` reads 12 properties, none injury-related. Availability
information physically cannot cross into the sim. `MatchupResolver.offense(from:)` / `.defense(from:)`
(`Engine/Match/MatchupResolver.swift:26`, `:60`) pick best-available purely by `overall`; zero
occurrences of `injur` in `MatchupResolver.swift`, `PlaySimulator.swift`, `DriveSimulator.swift`.
`DepthChart` has zero `isInjured` occurrences and **is not consulted by either simulator anyway**.

This is **deliberate and documented** — `GameSimulator.swift:90-98`:
> *"…and where an injured man genuinely does not dress (**the regular-season path leaves that
> simplification alone rather than changing what a shipped season simulates**). The holdout filter
> below still applies on top of an override…"*

The **only** path that excludes an injured player is preseason —
`Engine/Simulation/PreseasonEngine.swift:332-333`:
```swift
let userAvailable = userRoster.filter { !$0.isInjured && !$0.isHoldingOut }
```
fed via `homeRosterOverride`/`awayRosterOverride` at `:374-381`.

The canonical predicate `!isInjured && !isHoldingOut && !isRetired` is duplicated ~8× but is used
**only for bookkeeping, never for who plays**: `WeekAdvancer.swift:1419` (attendance credit) →
`startingLineupIDs(available:)` (`:6976-7009`, a best-at-position filler never handed to the sim),
`:1883`, `:1896`, `:2111`, `:7378`; `PracticeSquadEngine.swift:1030`;
`TrainingFocusEngine.swift:175/296/332/667`; `VersatilityDevelopmentEngine.swift:538/801`.
Rehab tick at `WeekAdvancer.swift:2031`; rush-back decrement at `:1845`.

> **→ The two lines a suspension must change are `GameSimulator.swift:130-131` and
> `LiveGameEngine.swift:1283-1284`.** Both already have the `filter { !$0.isHoldingOut }` seam;
> adding `&& !$0.isSuspended` there covers both engines and satisfies the #208 lesson
> ("the guard belongs in the engine, not the view"). **Do NOT add `!$0.isInjured` there in the same
> change** — that is a behaviour change to shipped seasons that `GameSimulator.swift:94-96`
> deliberately avoided, and it would silently move every balance number.

### 5.5 SUSPENSION — **it does not exist as game state**

Case-insensitive sweep of `dynasty/` for `suspend|suspension|banned|ineligible|deactivat`:
no `isSuspended`, no `suspensionWeeks`, no `SuspensionType`, no roster-status case. Complete
inventory of real hits:

| file:line | what |
|---|---|
| `Engine/Event/EventEngine.swift:71` | `case holdout, suspension, arrest, …` in `enum EventType: String` — rawValue `"suspension"` |
| `Engine/Event/EventEngine.swift:201` | `pool.append((.suspension, 1 + negativeBias))` |
| `Engine/Event/EventEngine.swift:257-258` | `case .suspension, .arrest: return players.randomElement()` |
| `Engine/Event/EventTemplates.swift:105-127` | two news templates — *"{playerName} suspended for violating league policy"*, *"…facing league suspension for substance abuse"*. Options carry ONLY the 4 morale-family deltas |
| `Engine/Event/EventTemplates.swift:138` | `EventOption(label: "Suspend indefinitely", …)` under `.arrest` — morale deltas only |
| `Engine/Event/EventEngine.swift:144-153` | `applyEventChoice` — the only thing a choice does is move `player.morale` + team meters. **It never touches `isInjured`, `teamID`, or `rosterStatus`** |
| `Engine/Scouting/ScoutingEngine.swift:4107` | `"Suspended for the bowl game, never explained why"` — a prospect red-flag string |

**A suspension feature is greenfield: no persisted field, no enum case, no sim hook.** The minimal
free implementation (§8 rules): `Player.suspensionWeeksRemaining: Int = 0` + optional
`suspensionReasonRaw: String? = nil` as inline-default stored properties (free), decremented in the
same weekly block that ticks rehab (`WeekAdvancer.swift:2026-2033`), and gated at the two sim seams
above. Display piggybacks on `UI/Roster/InjuryReportView.swift` (`injuredPlayers` `:22-25`,
`rushBackPlayers` `:27-29`, injury row `:190-238`) — a third section costs nothing.

---

## 6 · Contract willingness

### 6.1 Holdout / hold-in

`Domain/Models/FreeAgency/Holdout.swift` (71 lines): `enum HoldoutResolution: String` (`:4-8`) —
`extended, bonusGiven, traded, unresolved`, plus `playerCaved` (`:7`), implicit rawValues.
`@Model final class Holdout` (`:10-70`) — `careerID: UUID? = nil` (`:18`), `playerID` (`:20`),
`teamID` (`:21`), `startedAt` (`:22`), `resolvedAt: Date?` (`:23`), `resolutionRaw: String?` (`:24`),
`subMarketDelta: Int` (`:25`, thousands), `weeksActive: Int = 0` (`:30`), `seasonYear: Int = 0` (`:44`).
**Only two states in practice** — unresolved (`resolvedAt == nil`) and resolved. No graduated
hold-in / partial-participation state.

`Engine/FreeAgency/HoldoutEngine.swift` (292 lines, `@MainActor enum`):
`subMarketThreshold = 0.85` (`:18`), `mediationSuccessRate = 0.75` (`:21`),
`enum Resolution { extend, signingBonus, forceTrade, mediation }` (`:24-29`),
`detectHoldoutCandidates(roster:marketValues:)` (`:35-46`),
**`detectStarHoldoutCandidates(roster:marketValues:)` (`:57-84`)** — the live trigger; gate at `:66`
(`!isFranchiseTagged, !isHoldingOut, !isInjured`), star = `overall >= 85 || top-3 by overall` (`:69`),
fires on `contractYearsRemaining == 1` OR (`yearsPro >= 3` && underpaid);
`startHoldout(...)` (`:93-116`, sets `isHoldingOut = true` `:107`);
`resolveHoldout(...)` (`:129-173`, `.mediation` = 75% coin flip `:159`);
`forceTrade(...)` (`:204-291`, real trade via `TradeValueEngine.buildForcedTradePackage` +
`TradeEngine.executeTrade`).

⚠️ **Inputs are contract math ONLY.** `detectStarHoldoutCandidates` reads `overall`,
`contractYearsRemaining`, `annualSalary`, `yearsPro`, `isFranchiseTagged`, `isInjured` — **no
`personality`, no `archetype`, no `motivation`, no `morale`, no `motivationState`.** This is the
most obvious personality-driven hook in the whole map, and a "wants out" life event fits it exactly.

Weekly tick — `WeekAdvancer.swift:2594-2680 processHoldoutWeek(...)`: auto-settle at
`annualSalary >= market * 0.95` or `contractYearsRemaining >= 2` → `.extended` (`:2622-2624`);
`weeksActive += 1`, teammates −1 morale, holdout −2 (`:2644-2650`);
**`:2653` `let caves = holdout.weeksActive >= 4 || (holdout.weeksActive == 3 && Bool.random())`
→ `.playerCaved`, morale −10 (`:2656`) — a pure coin flip, no personality input.**

`isHoldingOut == true` excludes from: the sim (`GameSimulator.swift:130-131`,
`LiveGameEngine.swift:1283-1284`), attendance (`WeekAdvancer.swift:1419`), development
(`TrainingFocusEngine.swift:175/296/332/649/667`, `VersatilityDevelopmentEngine.swift:538/801`),
trade targeting (`TradeValueEngine.swift:2469/2521/2634`), locker-room roles
(`LockerRoomEngine.swift:432/437/582`), narrative (`LeagueNarrativeEngine.swift:654`);
and adds **+0.05 leverage** to the ask (`ContractNegotiationEngine.swift:942`).
Cleared by `CapManagementEngine.swift:673`, `PracticeSquadEngine.swift:724`,
`CampRosterEngine.swift:596`, `PlayerRetirementEngine.swift:880/1035`.

UI — `UI/FreeAgency/HoldoutDialog.swift:5`, `onResolve: (HoldoutEngine.Resolution) -> Void` (`:11`).
⚠️ **Known duplication bug at `:138`:** `let didResolve = selectedResolution == .mediation ?
Bool.random() : true` — the dialog rolls its **own** mediation coin for display, independent of the
engine's roll in `resolveHoldout`. Driver: `CareerShellView.swift:789` (present), `:1025-1038`
(resolve), `:1232-1262` (`applyHoldoutResolutionEffects`), `:1294-1311` (detect+start),
`:1565` (one holdout max).

### 6.2 ★ THE willingness seam — `situationBreakdown`

`Engine/Contract/ContractNegotiationEngine.swift` (2393 lines). The pipeline is
`demand(...) -> ContractDemand` then `respond(...) -> AgentResponse`.

Accept/reject entry: **`respond(gmOffer:player:demand:previousAgentOffer:roundNumber:recordToLedger:)
-> AgentResponse` (`:1344-1351`)**. Acceptance is `outcome == .dealReached(gmOffer)`, produced only
in the `.eager` branch (`:1441-1446`). The verdict itself is a **pure function on a ratio** —
`ContractDemand.tone(forPerYear:currentAskPerYear:)` at **`:444-452`**:
```swift
guard !isRefusing else { return .refusing }
let floor = max(1, Int(Double(ask) * floorFraction))
if offered >= Int(Double(ask) * acceptRatio) { return .eager }        // acceptRatio 0.97  :548
if offered >= floor                          { return .professional }
if offered >= Int(Double(floor) * insultRatio) { return .hardline }   // insultRatio 0.75  :552
return .insulted
```
(`insultRatchet = 1.06` `:560`.) `offered` is pre-adjusted at `:1418-1437` (incentive credit ×1.35
for prove-it, short-deal credit, guarantee drag ×0.96 when the gap > 15pts).
**Crucially, `:1332-1341` documents that morale/loyalty/persona are NOT re-applied at grading time:**
*"They live in `ContractDemand` now, once."*

Entry: `demand(player:negotiationType:salaryCap:situation:standing:insultCount:) -> ContractDemand`
(`:632-639`) — `market = ContractEngine.estimateMarketValue` (`:641`) × `breakdown.multiplier`
(`:652`) × deterministic `theatre = 1.04 + 0.08 * unitDraw(player.id, salt: 0x51)` (`:651`), banded
to `0.75…1.60 × market` (`:665`), ratcheted by insults (`:670`), floored at `veteranMinimum` (`:671`).

**★ THE PLUG-IN POINT ★** —
`private static func situationBreakdown(player:persona:negotiationType:situation:gm:)
-> ContractDemand.SituationBreakdown` at **`ContractNegotiationEngine.swift:858-864`**.
It returns `.init(source:value:)` components (`:974-983`) where each `value` is a **signed
multiplicative fraction (positive = costs more / less willing)**, combined as `∏(1 + value)` and
clamped to `SituationBreakdown.bounds = 0.72 ... 1.50` (`:517-530`). The eight current components
*are* the willingness ledger:

| `Source` (enum `:489-506`) | line | value |
|---|---|---|
| `.agentPersona` | `:869` | `persona.demandFactor − 1.0` |
| `.archetype` | `:875-888` | dramaQueen +0.08, loneWolf +0.05, fieryCompetitor +0.03, classClown +0.01, feelPlayer 0, steadyPerformer −0.02, quietProfessional −0.03, mentor −0.05, teamLeader −0.06; negatives ×0.4 when not own club |
| `.motivation` | `:893-901` | money +0.12, fame +0.08, stats +0.03, winning −0.12/−0.06, loyalty −0.10/−0.03 |
| `.morale` | `:905-913` | <40 +0.08 … ≥85 −0.05 |
| `.motivationState` | `:918-925` | driven −0.02, focused 0, complacent +0.03, discouraged +0.06 |
| `.leverage` | `:928-947` | age vs `position.peakAgeRange`, cameOffCareerYear +0.06, isFranchiseTagged +0.08, **isHoldingOut +0.05 (`:942`)**, provedTheBet +0.10 |
| `.teamSituation` | `:951-971` | losing +0.05 / contender −0.03; legacy-veteran ∓0.10/+0.04 |
| `.frontOffice` | `:982` | `gm.total` from `gmAdjustment(_:)` (`:826`) |

> **To add a "distracted / motivated / wants out" life-event modifier: add a case to
> `ContractDemand.SituationBreakdown.Source` (`:489-506`) and one `.init(source:value:)` to the array
> at `:974-983`. That is the entire wiring** — every UI surface that itemises the ask picks it up for
> free via `SituationBreakdown.value(_:)` (`:523`). ⚠️ `Source` is inside a persisted `Codable`
> (`ContractDemand`) only if that demand is stored — verify before adding a case; if it never hits a
> blob it is free either way (§8.1 rule 4 covers `String`-raw enums regardless).

Two secondary seams:
- **`floorFraction(player:persona:situation:) -> Double` (`:993-1011`)** — base by persona
  (0.86/0.78/0.82) ± age/overall/career-year, clamped `0.72…0.95`. A lower floor = accepts a lower
  offer **without changing the headline ask** — the right lever for "he just wants it done".
- **`refusalVerdict(player:situation:gm:) -> AgentRefusalReason?` (`:1038-1042`)** — the hard door.
  Precedence: `ringChaserVerdict` (`:1043`) → `AgentRefusalReason.evaluate(...)` (`:1047-1058`) →
  mercenary/losing-culture door gated on `motivation == .money || archetype == .loneWolf`,
  `morale < 65`, `weeksPlayed >= 6`, `teamWinPercentage < 0.35`, threshold
  `0.08 + max(0, gm.total)` (`:1062-1077`). Applied only for `negotiationType.isOwnClub` (`:679-681`).
  `ringChaserVerdict(player:situation:)` (`:1110-1127`) gates on `overall >= 88`, `age >= 26`,
  **`competitiveness >= 80`**, `motivation == .winning || archetype == .fieryCompetitor`,
  `morale < 75`, `isGoingNowhere`, then `unitDraw(id, salt: 0xD5) < 0.5`.
  → **A "wants out after the incident" life event belongs here**, as a new
  `AgentRefusalReason` case.

Chat shell: `evaluateCounterOffer(...) -> ChatVerdict` (`:1802-1812`, struct `:1775-1793`) — a thin
wrapper over `demand` + `respond`. Also `closeTone(...)` (`:729-747`), `payCutVerdict(...)` (`:1611`),
`maxContractYears(forAge:)` (`:1296`), `generateOpeningDemand(...)` (`:1276`).

### 6.3 `DealTargetYear` — the contract-year authority

`Engine/Contract/DealTargetYear.swift` (621 lines, static-only). Purpose (doc `:5-60`): answer
*"which league year does this contract actually charge, and can the club carry it in that year"* —
fixing #186, where the cap gate measured a 2027 deal against 2026's balance. **One `Plan` feeds both
the GATE (`verdict`) and the BOOKING (`ContractEngine.applyNegotiatedDeal`) so they cannot drift.**

`enum Shape { tagReplacement, deferredExtension, currentYear }` (`:66-73`);
`struct Plan` (`:81-160`) — `startSeason` (`:88`), `seasonsAhead` (`:91`), `contractYears` (`:96`),
`lastSeason` (`:109`), `netChargeInStartYear = firstYearCapHit − replacedCharge` (`:149`),
`booksForward` (`:156`); `openSeason(currentSeason:hasRolledOver:)` (`:182`);
**`plan(player:offer:application:capMode:currentSeason:hasRolledOver:careerID:existingContract:) -> Plan`
(`:203-212`)**; `struct Space` (`:360-370`); `space(...)` (`:385`, `:452`);
`enum Verdict` (`:509-538`); `verdict(plan:space:capMode:)` (`:553`, overload `:578`);
`yearSpan(_:)` (`:616`).

**Tag-and-extend (`.tagReplacement`):** a *pending* tag still owns a
`CommittedCapLedger.forwardCommitment(playerID:careerID:kind: .franchiseTag)` row (`:217-224`) and is
deliberately **not** `.tagReplacement`. A *settled* tag is detected off `player.franchiseTagSeason`,
**not** `isFranchiseTagged`, because `FreeAgencyEngine.settleFranchiseTags` clears the flag in the
same pass (`:226-245`). **Term does not stack** (`:263-268`). Relief (`:276-282`).
The ceiling at `:284+` (`cappedFirstYear`) structures year one at or below the tag it replaces:
*"A club retires a $41.9M tag in order to get UNDER it."*

**→ Life Events must not write contract fields directly.** Any event that changes money must route
through `DealTargetYear.plan` + `verdict`, or it will desynchronise the gate from the booking.

### 6.4 Interest / preference scoring — three parallel motivation switches

- **`Engine/FreeAgency/SigningInterestEngine.swift`** — the real one.
  **`interest(candidate:askingPrice:offer:team:allPlayers:schemeFit:hostedVisit:) -> Breakdown`
  (`:151-159`)**; player-typed wrapper at `:109-118`.
  Terms: money `clamp01((offer.salary/askingPrice − 0.6) / 0.6)` (`:161-167`, `0.45` with no offer),
  teamSuccess = last season's win% (`:171-172`), role via `roleScore(...)` (`:214-230`, 1.0/0.7/0.4/0.15),
  schemeFit `?? 0.5`, `visitBonus = 0.12` flat (`:192`), clamped (`:193`).
  **`Motivation` is the ONLY personality input, and it sets the weights** (`:178-185`):

  | motivation | money | success | role | scheme |
  |---|---|---|---|---|
  | `.money` | 0.60 | 0.10 | 0.15 | 0.15 |
  | `.winning` | 0.35 | 0.35 | 0.15 | 0.15 |
  | `.stats` | 0.35 | 0.10 | 0.35 | 0.20 |
  | `.loyalty` | 0.45 | 0.15 | 0.20 | 0.20 |
  | `.fame` | 0.50 | 0.20 | 0.15 | 0.15 |

  `struct Candidate` (`:77-100`) carries only `id, position, overall, motivation` — **`archetype`,
  `morale` and `motivationState` are NOT inputs.** A willingness term goes either into `Candidate`
  + the weight switch (`:178-185`), or as a multiplier on `total` beside `visitBonus` (`:192-193`).
- **`FreeAgencyEngine.resolvePlayerDecision(...)` (`:3228-3237`)** — the AI free agent's actual
  choice. Inner `scoreBid(_:)` (`:3332-3406`) is a **second, independent motivation switch**
  (`:3335-3363`: money ×1.3, winning ×(1+winPct×0.15) and ×1.15 for user, stats ×1.05,
  loyalty ×1.25/×0.85, fame ×`mediaMarket.freeAgentAttraction`), plus incumbent ×1.1 (`:3366-3368`),
  hosted visit ×1.15 (`:3372-3374`), role weight 0.30/0.12 (`:3378-3387`), youth×length (`:3390-3392`),
  `legacyVeteranPreference` (`:3403`, impl `:3447-3457`). Highest score wins (`:3409`).
  **Motivation only — no archetype/morale/motivationState.**
- `Engine/FreeAgency/LoyaltyEngine.swift` (68 lines): `loyaltyThresholdYears = 4` (`:15`),
  `legendThresholdYears = 6` (`:18`), `loyaltyDiscount(player:currentTeamID:)` (`:25-31`, 0.85/0.90/1.0),
  `letWalkPenalty(player:)` (`:35-43`), `generateLetWalkEvent(player:)` (`:47-67`).
  **No personality input at all**, and ⚠️ **`loyaltyDiscount` has no caller outside its own file** —
  `BiddingRoomEngine.swift:77-78` computes its own parallel `1.0 − loyalty * 0.15`.
- `Engine/FreeAgency/PlayerPreferenceEngine.swift` (230 lines) — **mostly vestigial.**
  `generatePreferences(playerID:position:)` (`:10-36`) uses a deterministic FNV-seeded xorshift64*
  `SeededRNG` (`:215-229`); `baseWeight(for:position:)` (`:119-133`) **returns 1.0 for every case**
  (the position bias is a stub). **`teamFitScore(...)` (`:40-63`) has zero call sites.**
  Only `generatePreferences` (from `FAWeeklyView.swift:527`) and `offerRanking(...)` (`:67-99`,
  70% money / 30% fit `:91`, called from `UDFAMarketEngine.swift:521`) are live.

> ⚠️ **Three separate motivation switches** (`SigningInterestEngine:178-185`,
> `FreeAgencyEngine:3335-3363`, `ContractNegotiationEngine:893-901`) would each need touching for a
> consistent willingness change. `situationBreakdown` is the only *honest* single seam.

### 6.5 `Motivation` and `MotivationState` — persisted rawValues

`Domain/Enums/Motivation.swift` (9 lines, the whole file) — `enum Motivation: String, Codable,
CaseIterable`, **rawValues are capitalized display strings**:
`money = "Money"` (`:4`), `winning = "Winning"` (`:5`), `stats = "Stats"` (`:6`),
`loyalty = "Loyalty"` (`:7`), `fame = "Fame"` (`:8`). Stored inside `PlayerPersonality.motivation`
(`PlayerPersonality.swift:5`) — i.e. inside a **frozen Codable composite** on `Player.personality`.
Consumed in 18 files.

`Domain/Enums/MotivationState.swift` (179 lines) — `enum MotivationState: String, Codable,
CaseIterable, Identifiable` (`:19`). **rawValues are the implicit lowercase case names.**

| line | case | `developmentMultiplier` (`:74`) | `moraleDelta` (`:84`) | `focusGainMultiplier` (`:95`) |
|---|---|---|---|---|
| `:21` | `.driven` | 1.30 | +3 | 1.20 |
| `:23` | `.focused` | 1.00 | 0 | 1.00 |
| `:25` | `.complacent` | 0.75 | −1 | 0.85 |
| `:27` | `.discouraged` | 0.60 | −3 | 0.70 |

`static let default = .focused` (`:34`); `displayName` (`:38`), `icon` (`:48`), `summary` (`:58`);
`from(score:paydayPenalty:otherPenalty:)` (`:121-126` — `≥2 driven`, `≥−1 focused`, payday-dominant
→ `.complacent`, else `.discouraged`); `incentiveChaseScore(for:)` (`:154-159`, gated on
`competitiveness >= PlayerDevelopmentEngine.contractYearGate || motivation == .money`);
`incentiveChaseNote(for:)` (`:168-178`).
Storage `Player.motivationStateRaw: String? = nil` (`:96`), accessor `:99-101`.
**Recomputed once per offseason at `.trainingCamp`** (`WeekAdvancer.swift:4035 motivationCampNews`).
Written by `PlayerDevelopmentEngine.swift:880` and `ContractNegotiationView.swift:2467-2468`
(sets `.driven`).

> **This is the cleanest home for a life-event performance/attitude modifier.** `MotivationState` is
> a `String`-raw enum on an **optional** column — **adding a case is FREE** (§8.1 rule 4). A
> `.distracted` case (developmentMultiplier ~0.70, moraleDelta −2, focusGain ~0.80) would flow into
> development, focus, and the contract ask (`situationBreakdown` `.motivationState` `:918-925`)
> with **no other wiring**. Caveat: it is recomputed wholesale each `.trainingCamp`, so an in-season
> life event must either write it and accept the annual reset, or carry its own duration counter.

---

## 7 · Calendar & tick

### 7.1 `SeasonPhase` — FROZEN persisted rawValues

`Domain/Enums/SeasonPhase.swift`, `enum SeasonPhase: String, Codable, CaseIterable` (`:3`).
**`allCases` order IS the calendar order** — `overallOrdinal` (`:99`) and
`CalendarSidebarView.phaseStatus` (`:432`) both derive done/upcoming from `allCases.firstIndex`.
Per migration-plan §4.3 these rawValues may **never** be renamed or deleted.

| # | case | rawValue | line |
|---|---|---|---|
| 0 | `.proBowl` | `"ProBowl"` | `:4` |
| 1 | `.superBowl` | `"SuperBowl"` | `:5` |
| 2 | `.coachingChanges` | `"CoachingChanges"` | `:6` |
| 3 | `.reviewRoster` | `"ReviewRoster"` | `:7` |
| 4 | `.combine` | `"Combine"` | `:8` |
| 5 | `.freeAgency` | `"FreeAgency"` | `:9` |
| 6 | `.proDays` | `"ProDays"` | `:10` |
| 7 | `.draft` | `"Draft"` | `:11` |
| 8 | `.otas` | `"OTAs"` | `:12` |
| 9 | `.trainingCamp` | `"TrainingCamp"` | `:13` |
| 10 | `.preseason` | `"Preseason"` | `:14` |
| 11 | `.rosterCuts` | `"RosterCuts"` | `:15` |
| 12 | `.regularSeason` | `"RegularSeason"` | `:16` |
| 13 | `.tradeDeadline` | `"TradeDeadline"` | `:17` |
| 14 | `.playoffs` | `"Playoffs"` | `:18` |

⚠️ **Ordering trap:** `allCases` puts `.playoffs` (14) *after* `.regularSeason`, but the runtime
chain is `playoffs → proBowl` (wrap-around). **`phase(after:)` is the real authority, not `allCases`.**

Also: `SeasonPhaseGroup` (`:25`, 5 groups, `displayName` `:32`, `icon` `:43`, `subPhases` `:54`);
`displayName` (`:67` — note `.proBowl` → "All-Star Game", `.superBowl` → "The Championship" — the
trademark-safe register); `group` (`:88`); `overallOrdinal` (`:99`); `groupProgress` (`:105`).
**There is no `isOffseason`.** The offseason test is the `default:` arm of the dispatch switch
(`WeekAdvancer.swift:929`), i.e. "anything not `.regularSeason`/`.tradeDeadline`/`.playoffs`".
Life Events should define its own explicit phase→lane table rather than relying on that default.

### 7.2 `WeekAdvancer` — the tick

`Engine/Simulation/WeekAdvancer.swift` (8569 lines, `enum WeekAdvancer` `:6` — stateless, all static).

```
:897   static func advanceWeek(career:modelContext:)                        // THE TICK
:1265  private static func advanceRegularSeasonWeek(career:modelContext:)   // in-season week
:2726  private static func advancePlayoffWeek(career:modelContext:)
:2944  private static func advanceOffseasonPhase(career:modelContext:)      // phase step
:1004  static func startNewSeason(career:teams:modelContext:)
:5345  private static func phase(after phase: SeasonPhase) -> SeasonPhase
:164   static func bind(to career: Career)
:178   static func resetProcessStateForCareerSwitch()
```

**`advanceWeek` (`:897-958`)** — the dispatcher:
```swift
bind(to: career)                                                    // :899
restoreDraftClassIfNeeded(...)                                      // :907
lastNewsItems = []; lastEvents = []; lastInboxMessages = []         // :910-915
wasFired = false; pendingPressConference = nil; pendingPressContext = nil
switch career.currentPhase {                                        // :917
case .regularSeason, .tradeDeadline: advanceRegularSeasonWeek(...)  // :919-922
case .playoffs:                      advancePlayoffWeek(...)        // :924-927
default:                             advanceOffseasonPhase(...)     // :929-932
}
liveGameInjuryTeamIDs = []                                          // :937
sweepAICapCompliance(career:modelContext:)                          // :950
if !lastNewsItems.isEmpty { career.newsLog = lastNewsItems + career.newsLog }  // :955-957
```
→ **`:917` (pre-dispatch) or `:934-950` (post-phase, pre-cap-sweep) is the single best hook for a
top-level Life Events scheduler that must run in BOTH in-season and offseason lanes.**

`phase(after:)` (`:5345-5364`): `proBowl → superBowl → coachingChanges → reviewRoster → combine →
freeAgency → proDays → draft → otas → trainingCamp → preseason → rosterCuts → regularSeason`;
fallbacks `regularSeason → playoffs`, `tradeDeadline → regularSeason`, `playoffs → proBowl`.

### 7.3 **The contract clock rule — `executeNewLeagueYear` is NOT in `WeekAdvancer`**

`Engine/Contract/FreeAgencyEngine.swift:415`:
```swift
static func executeNewLeagueYear(allPlayers:allTeams:playerTeamID:modelContext:career:) -> LeagueYearSummary
```
- Idempotency: `career.lastRolloverSeason >= career.currentSeason` → early return (`:425`);
  the stamp is written at `:439` **before** any mutation.
- **Exactly two call sites:** UI happy path `UI/FreeAgency/NewLeagueYearView.swift:230`, and
  calendar fallback `WeekAdvancer.swift:3636` (inside `case .freeAgency:`, gated on
  `rolloverPending = career.lastRolloverSeason < career.currentSeason` `:3634` and a `beforeRollover`
  step check `:3635`).
- **Read `WeekAdvancer.swift:2419-2448` before touching contract ticking:** it documents that the
  week-18 block *used* to decrement contracts too, causing a **double-tick**. That block is now dead
  comment; the rollover is the only tick. **A Life Event must never decrement a contract year.**

### 7.4 Per-week engine call order — `advanceRegularSeasonWeek` (`:1265-2496`)

| line | call |
|---|---|
| `:1276` | `applyOpponentPrepDrift` |
| `:1279` | fetches (`PerfLog` lap `"fetch"` `:1301`) |
| `:1307-1311` | `backfillLegacyLearning` / `Competitiveness` / `Faces`, `migrateLegacyDraftClassIfNeeded`, `ensureFuturePickHorizon` |
| `:1324` | game-sim loop — `GameSimulator.simulate` / `simulateGameScore()`, `updateTeamRecords` (`"games"` `:1391`) |
| `:1397` | `accumulateSeasonStats` |
| `:1409` | games-played / games-started attendance (`"attendance"` `:1424`) |
| `:1493` | `CoachDevelopmentEngine.applyWeeklyXP` |
| `:1508` | `LeagueNarrativeEngine.updateWeekly` (`"narrative"` `:1519`) |
| `:1538` | `PressConferenceEngine.generateWeeklyPressConference` (+ `.weeklyContext` `:1551`) |
| **`:1565`** | **`NewsGenerator.generateWeeklyNews` → `lastNewsItems`** |
| `:1577` | `+= narrativeUpdate.news` |
| `:1586` | `announceWeeklyMilestones` |
| `:1598` | `EventEngine.generateWeeklyEvents` → `lastEvents` *(the dead system, §2.3)* |
| `:1607` | `OwnerSatisfactionEngine.updateSatisfaction` |
| `:1618` | `OwnerSatisfactionEngine.checkFiring` → `wasFired` |
| `:1632` | `InboxEngine.generatePhaseMessages` → `lastInboxMessages` |
| `:1643` | `OwnerPersonaEngine.rollWhim` |
| `:1662-1698` | trade hazard / AI offer / inbox (`"news_events_inbox"` `:1716`) |
| **`:1721`** | **`processHoldoutWeek(...)`** (impl `:2594`) |
| **`:1737`** | **`processLockerRoomWeek(...)`** (impl `:2509`) (`"holdout_lockerroom"` `:1748`) |
| **`:1770`** | **`LockerRoomEngine.weeklyMoraleUpdate`** — league-wide (`"morale"` `:1777`) |
| `:1779` | fatigue — `MedicalEngine.weeklyFatigueRecovery` `:1790` |
| `:1794` | **new injuries** — `MedicalEngine.injuryCheck` `:1810`, `.applyInjury` `:1818` |
| `:1849` | XP — `playingTimeRoles` `:1886`, `applyGameExperience` `:1907` (`"fatigue_injury_xp"` `:1918`) |
| `:1920` | `TrainingFocusEngine` focus/breakout (`"training_focus"` `:2024`) |
| **`:2026`** | **injury HEALING — `MedicalEngine.processWeeklyRehab`** `:2033` (`"rehab"` `:2086`) |
| `:2088` | `VersatilityDevelopmentEngine` scheme learning (`"scheme_learning"` `:2180`) |
| `:2185` | scouting, weeks 10-18 (`"scouting"` `:2217`) |
| `:2232` | `PracticeSquadEngine.runWeeklyPass` (`"practice_squad"` `:2255`) |
| **`:2258`** | **`career.currentWeek += 1`** ← the counter bump |
| `:2271`/`:2307` | trade-deadline phase flips + `runLeagueMarketWindow` |
| `:2345-2373` | week-9 draft-class / mock-draft hooks |
| `:2376` | week 18 — `recordSeasonHistory` `:2379`, `announceCareerMilestones` `:2390`, `LockerRoomEngine.applyMoraleEffects` `:2411` |
| **`:2452`** | `currentWeek > 18` → `.playoffs`, `currentWeek = 19` (`"transitions"` `:2494`) |

**In-season Life Events insertion point:** immediately after `processLockerRoomWeek` (`:1737`) and
before `weeklyMoraleUpdate` (`:1770`) — so an event's morale delta is damped by the same
weekly cap and reversion the locker room obeys. Alternatively `:2255` (after all engines, before the
week counter bumps). Availability-affecting events (suspensions) must land **before** the game-sim
loop at `:1324` if they are to take effect the same week — otherwise they apply from next week.

`advancePlayoffWeek` (`:2726`): `ensurePlayoffGames` `:2731` → `playPlayoffGames` →
`recordPostseasonWeek` `:2757` → conference-final `ensurePlayoffGames(forWeek: 22)` `:2789`,
`currentPhase = .proBowl` `:2793`; else `currentWeek += 1` `:2800`.

### 7.5 Offseason arc — `advanceOffseasonPhase` (`:2944`)

Preamble `:2948-2963` (fetches, legacy backfills, `ensureFuturePickHorizon`), then
`switch currentPhase {` at **`:2966`**:

| case | line | notable |
|---|---|---|
| `.superBowl` | `:2968` | championship sim, `finalizePostseasonHistory`, `OwnerGoalsEngine.evaluateGoalProgress`, `OwnerPersonaEngine.evaluateSeason`, `recordSeasonSummary` `:3046` (**promise settlement**) |
| `.proBowl` | `:3063` | |
| `.coachingChanges` | `:3134` | Black Monday carousel `:3323`, `evaluateCoachingTreeAlumni` |
| `.combine` | `:3452` | |
| `.freeAgency` | `:3605` | **`FreeAgencyEngine.executeNewLeagueYear` fallback `:3636`** |
| `.proDays` | `:3722` | |
| `.reviewRoster` | `:3739` | |
| `.draft` | `:3762` | **`UDFAMarketEngine.openMarket(...)` `:3784`** |
| `.otas` | `:3794` | `applyCampWeeklyTick(phase: .otas)` `:3799`; **`UDFAMarketEngine.closeMarket(...)` `:3820`**; **`CampRosterEngine.fillCampRosters(...)` `:3868`** (to 80) |
| `.trainingCamp` | `:3895` | `applyCampWeeklyTick` `:3898`; `applySchemeChanges`; `motivationCampNews` `:4035` (**`MotivationState` recomputed here**) |
| `.preseason` | `:4040` | `applyCampWeeklyTick` `:4042` |
| `.rosterCuts` | `:4051` | `applyCampGrades` `:4055`, `PositionBattleTracker.resolveBattles` `:4060`, `trimAIRosters` `:4068` |
| `default` | `:4076` | `break` |

Post-switch, in order: `:4086` offseason trade market; `:4098` owner-demand penalties when
`nextPhase == .regularSeason`; **`:4126`** `.rosterCuts → .regularSeason` → `processCampWaivers` `:4127`
→ `CampRosterEngine.settleCampBodies` `:4143`; **`:4157`** transition — if
`nextPhase == .regularSeason` then `career.currentSeason += 1` `:4159`, `startNewSeason(...)` `:4161`,
`PracticeSquadEngine.fillSquads` `:4173`; else `career.currentPhase = nextPhase` `:4192` +
`emitGroupTransitionMessageIfNeeded` `:4193` (impl `:5296`); `:4200+` draft-prep stage machine.

**Offseason Life Events insertion point:** right after the `switch` closes and before the trade
market at `:4086` — one call, every offseason phase, with the phase in hand for lane selection.
The heaviest natural lanes are `.otas` → `.trainingCamp` (the long quiet stretch) and
`.freeAgency` (contract-willingness consequences land where they can be acted on).

### 7.6 The offseason sub-arcs (#204 / #205)

**Preseason (#205b)** — `Domain/Models/Camp/PreseasonState.swift`:
`PreseasonPolicy` (`:40`, rawValues `"StartersRest"`/`"StarterSeries"`/`"FullTilt"`,
`dressesStarters` `:72`); `PreseasonStep.Kind` (`:90` — `plan` `:92` / `recap` `:94` /
`complete` `:96`); `PreseasonMatchup`, `PreseasonInjury`, `PreseasonFamiliarityGain`,
`PreseasonScoreLine`, `PreseasonResult`; **`struct PreseasonState` (`:305`)** — `careerID` `:308`,
`season` `:311`, `step` `:312`, `slate` `:313`, `results` `:314`; `matches(career:)` `:334`,
`isComplete` `:338`, `pendingMatchup` `:341`, `pendingRecap` `:347`.
Persisted `Career.preseasonState` (`:990`) over `Career.preseasonData`.
Engine `Engine/Simulation/PreseasonEngine.swift`: `openPreseasonIfNeeded` `:149`,
`recordResult` `:207`, `acknowledgeRecap` `:220`, `canLeavePreseason` `:241` (**`nil ⇒ true` — must
seed first**), `gamesRemaining` `:247`, `unplayedSlateInboxMessage` `:256`, `simulateGame` `:278`/`:313`,
`dressedRoster` `:455`, `CampCase` `:787`.
⚠️ **The step machine is UI-driven, not `WeekAdvancer`-driven** — `PreseasonView.swift:713`
(`simulateGame`), `:724` (`recordResult`). The calendar's only involvement is the **exit gate** in
`CareerShellView.performShellAdvance` `:1451-1466` (seeds via `ensuredPreseasonState()` `:2301`,
then refuses on `!canLeavePreseason(slate)` `:1453`).

**UDFA market (#204)** — `Engine/FreeAgency/UDFAMarketEngine.swift`. Season-stamped idempotency.
`state(career:)` `:372`, `isOpen` `:380`, `board(...)` `:395`, `campInviteCandidates` `:437`,
`openMarket(...)` `:570` (← `WeekAdvancer:3784`), `submitUserOffer` `:604`, `runAIRound` `:667`
(UI-driven), `closeMarket(...)` `:713` (← `WeekAdvancer:3820`), `clearingPrice` `:1113`.

**Cutdown stages** — `Domain/Enums/CampEnums.swift:56` `enum CutDay: String, Codable, CaseIterable`:
`cut90To75`, `cut75To65`, `cut65To53`. Extension in `UI/Camp/RosterCutView.swift:969`:
`target` `:971` (75/65/53), `stage(forRosterCount:)` `:993`,
**`duePhase` `:1018` → `.trainingCamp` / `.preseason` / `.rosterCuts`**,
**`rung(dueIn:)` `:1031`** (read by `TaskGenerator.rosterLadderTask`, `WeekAdvancer`'s exit ceiling
gate, and `RosterCutView.dueStage` `:572`). Roster-limit refusal wired at
`CareerShellView.swift:1362-1365`.

**Waivers** — `Engine/Camp/WaiverWireEngine.swift`: `WaiverClaim` `:14`,
`processWaivers(cuts:teamRecords:modelContext:)` `:24`. Single hook:
`WeekAdvancer.processCampWaivers` `:8508` → `:8531`, invoked once at the
`.rosterCuts → .regularSeason` transition (`:4127`), filtered to `\.isCampCutdown` (`:8526`).

**Camp weekly tick** — `WeekAdvancer.applyCampWeeklyTick(career:phase:modelContext:allPlayers:)`
`:8237`, called from `.otas` `:3799`, `.trainingCamp` `:3898`, `.preseason` `:4042`.
`campIntensity(for:)` `:8371` — `.otas` 0.45 / `.trainingCamp` 0.85 / `.preseason` 0.55.

### 7.7 UI trigger and `Career` calendar fields

**The single tick trigger:** `UI/Career/CareerShellView.swift:1344 performShellAdvance()`.
Gates in order (all early-`return`): staff blocker (~`:1350`), depth-chart gaps (`:1425-1436`),
preseason slate (`:1451-1466`), roster limit (`:1365`), cap compliance (`:1385`). Then:
`collectInboxMessages()` `:1481` → **`PerfLog.time("advance_week") { WeekAdvancer.advanceWeek(...) }`
`:1484-1486`** → `try? modelContext.save()` `:1489` (**`WeekAdvancer` never saves**) →
`loadShellData()` `:1491` → `wasFired` check `:1495` → drains press `:1529-1534`.
Callers: dashboard `onAdvance` (`CareerShellView.swift:517-519` → `CareerDashboardView.swift:652`),
deferred-from-calendar (`:911-914` in `handleSheetDismiss`, staged at `:758-760`),
left-rail `TimelineTasksPanel.swift:657-659`.
`CalendarSidebarView` — `onAdvancePhase: () -> Void` (`:26`), `canAdvance` (`:54`),
`advanceButton` (`:467-519`, `.disabled(!canAdvance)` `:516`), mounted `CareerShellView.swift:746-765`.
`SeasonWeekBand` is **display only** (`onSelect` nil, all slats disabled `:40-45`).

**`Career` calendar fields** — `Domain/Models/Career.swift`:
**`:21 currentSeason: Int`**, **`:22 currentWeek: Int`**, **`:23 currentPhase: SeasonPhase`**;
`:19 yearsFired`. Init defaults (`:388`): `currentSeason = 2026` `:404`, **`currentWeek = 0` `:405`**,
**`currentPhase = .coachingChanges` `:406`** — a new career starts in the offseason at week 0.
Week/phase writes happen in exactly seven places: `WeekAdvancer:2258`, `:2272`/`:2307`,
`:2453-2454`, `:2793`/`:2800`, `:4159`, `:4192`, and `startNewSeason:1140-1141`.

**Season-stamped idempotency fields — the pattern any Life Events scheduler must copy:**
`lastRolloverSeason` (~`:58`), `lastBulkMarketSeason` (~`:99`), `udfaMarketData` (`:190`),
`campFillSeason` (`:205`), `draftPrepStepSeason` (`:443`/`:453`), `bonusInstalledSeason` (`:937`/`:944`).

---

## 8 · PERSISTENCE — the critical answer

### 8.1 The policy, verbatim from the source of truth

`Data/Persistence/DynastySchema.swift:1-19` (the header) and
`docs/SWIFTDATA_MIGRATION_PLAN.md` §4.1-§4.3.

**FREE — no stage, no V2** (`SWIFTDATA_MIGRATION_PLAN.md` §4.1):
1. **Add a stored property to any `@Model`**, with an inline default or `Optional`,
   **never in `init`**. ("198 existing properties prove it works.")
2. **Add a new `@Model` type.** (Register it in the newest `VersionedSchema.models`.)
3. Add/remove an `#Index`.
4. **Add a case to any enum whose persisted form is a raw `String`.**
5. Change anything computed — computed properties, typed bridges over `…Raw` columns, all engine
   logic, all UI.

**NEEDS A STAGE** (§4.2):
- **Any change to an existing `Data?` blob's Codable type** unless the new field is `Optional` or
  defaulted in a custom `init(from:)`. Adding a *non-optional* field **silently empties the entire
  blob** for every existing save. The doc names the affected types explicitly, including
  `InboxMessage`, `NewsItem`, `LeagueNarrativeState`, **`LockerRoomEvent`**, `GamePlan`,
  `InjuryRecord`.
- Any rename/type change of a stored property; any change to a Codable **composite** attribute
  (`Player.physical`, `.mental`, `.positionAttributes`, **`.personality`**; `Career.legacy`, …).

**FORBIDDEN on a live beta store** (§4.3):
- Renaming/deleting a raw value of any persisted enum — *"applies with special force to
  `Position` and `SeasonPhase`"*.
- Bare property rename in any `@Model` (there is no `@Attribute(originalName:)` anywhere).
- Editing `DynastySchemaV1` after it shipped.
- Shipping a schema change and the V1 baseline in the same build.

`DynastySchemaV1` (`DynastySchema.swift:36-79`) lists the 29 models; `DynastyMigrationPlan`
(`:100-109`) currently has `schemas = [V1]`, `stages = []`.

### 8.2 The pattern the recent features actually use — JSON blob on `Career`

**Not** an external file, **not** a new `@Model`. It is:

> a `Data? = nil` stored property on the **`Career` `@Model`** + a typed computed-property
> bridge that `JSONEncoder`/`JSONDecoder`s a `Codable` struct, with `try?` on the decode so a
> corrupt/older blob degrades to `nil`/`[]` instead of failing the row.

**26 existing blob columns on `Career`** (`Domain/Models/Career.swift`):

| line | column | payload |
|---|---|---|
| `:46` | `depthChartData` | `DepthChart` |
| `:52` | `gamePlanData` | `GamePlan` |
| `:143` | `mockDraftHistoryData` | `[MockDraftPick]` |
| `:162` | `pendingTradeOffersData` | `[TradeProposal]` |
| `:170` | `tradeThreadsData` | `[TradeNegotiationThread]` |
| `:181` | `inboxData` | `[InboxMessage]`, cap 200 |
| `:190` | `udfaMarketData` | `UDFAMarketState` (#204) |
| `:212` | `developmentReportLogData` | `[DevelopmentReport]`, cap 10 |
| `:218` | `pendingReturnDecisionsData` | `[ReturnDecision]` |
| `:224` | `newsLogData` | `[NewsItem]`, cap 150 |
| `:235` | `announcedMilestoneKeysData` | `[String]` |
| `:239` | `leagueNarrativeData` | `LeagueNarrativeState` |
| `:246` | `coachCarouselLogData` | `[CarouselMove]`, cap 40 |
| `:251` | `pendingInterviewRequestData` | `CoordinatorInterviewRequest?` |
| `:258` | `ownerSeasonGoalsData` | `[SeasonGoal]` |
| `:262` | `ownerWhimsData` | `[OwnerWhim]` |
| `:266` | `ownerSeasonReviewData` | `OwnerSeasonReview` |
| `:277` | `pressToneHistoryData` | tone ledger |
| `:282` | `pressPromiseLedgerData` | `[PressPromiseRecord]`, cap 40 |
| `:288` | `leagueHistoryData` | league history |
| `:292` | `hallOfFameData` | `[HallOfFameEntry]` |
| `:323` | `breakoutCountsData` | `SeasonBreakoutCounts` |
| `:346` | `faceRegistryData` | `FaceAssignmentRegistry` |
| `:351` | **`lockerRoomLogData`** | `[LockerRoomEvent]`, cap 12 |
| `:355` | **`pendingLockerRoomEventData`** | `LockerRoomEvent?` |
| `:362` | `preseasonData` | `PreseasonState` (#205b) |

Plus non-blob idempotency stamps in the same dialect, e.g. `campFillSeason: Int = 0` (`:205`),
`schemaBackfillVersion: Int = 0` (`:373`).

**The canonical accessor pair** (copy this verbatim) — `Career.swift:962-985`:

```swift
// list, capped on write
var lockerRoomLog: [LockerRoomEvent] {
    get {
        guard let data = lockerRoomLogData,
              let log = try? JSONDecoder().decode([LockerRoomEvent].self, from: data) else {
            return []
        }
        return log
    }
    set { lockerRoomLogData = try? JSONEncoder().encode(Array(newValue.prefix(12))) }
}

// single pending item
var pendingLockerRoomEvent: LockerRoomEvent? {
    get {
        guard let data = pendingLockerRoomEventData else { return nil }
        return try? JSONDecoder().decode(LockerRoomEvent.self, from: data)
    }
    set { pendingLockerRoomEventData = newValue.flatMap { try? JSONEncoder().encode($0) } }
}
```

And the season-stamped variant with an engine-owned read door — `Career.swift:1009-1017`
(`udfaMarketState`), whose doc explicitly says *"Not the market's read door.
`UDFAMarketEngine.state(career:)` is, and it additionally checks `UDFAMarketState.season` against
`currentSeason`, so last year's blob reads as 'no market yet'."*

### 8.3 Precise recommendation for `LifeEventsState`

**A `LifeEventsState` payload can be added with NO schema change.** Recipe:

1. In `Domain/Models/Career.swift`, add **three** `Data? = nil` stored properties with inline
   defaults, never in `init` (§4.1 rule 1):
   - `lifeEventsStateData: Data? = nil` — the whole `LifeEventsState` (cooldowns, per-player
     event history keys, season stamp, active suspensions/effects).
   - `lifeEventLogData: Data? = nil` — `[LifeEvent]`, capped (12-40, mirroring lockerRoom/carousel).
   - `pendingLifeEventData: Data? = nil` — the one big event awaiting a coach pop-up.
2. Add the typed bridges in the same file, copying `lockerRoomLog` / `pendingLockerRoomEvent`
   byte for byte, with `try?` on both decodes.
3. Give `LifeEventsState` a `season: Int` stamp and route reads through
   `LifeEventsEngine.state(career:)`, which compares against `career.currentSeason` — the
   `UDFAMarketEngine.state(career:)` pattern. This makes the blob self-invalidating and removes
   any need for a migration when the shape changes across seasons.
4. Make **every** field of `LifeEvent` / `LifeEventsState` either non-optional-with-a-default in a
   hand-written `init(from decoder:)`, or `Optional`. This is the §4.2 rule: it is what lets you
   *keep adding fields later* without a stage. **Do this from day one** — retrofitting a custom
   `init(from:)` after the blob ships is exactly the trap the doc warns about.
5. New enums (`LifeEventKind`, `LifeEventSeverity`, …) are `String`-raw + a `…Raw: String` column
   if ever stored directly on a `@Model` — §4.5 standing recommendation:
   *"New persisted enum-typed properties use the `…Raw: String` + typed-bridge dialect."*
   Inside a JSON blob a plain `String`-raw enum is fine.

**When V2 WOULD become unavoidable** (avoid all three):
- Adding a field to `PlayerPersonality`, `MentalAttributes`, or any other Codable **composite**
  attribute on `Player` (§4.2). → Instead add a *separate* top-level column on `Player`, e.g.
  `lifeEventFlagsData: Data? = nil` or `suspensionWeeksRemaining: Int = 0`.
- Adding a **non-optional** field to an existing shipped blob type (`LockerRoomEvent`, `NewsItem`,
  `InboxMessage`) — that silently empties every existing save's blob.
- Renaming/removing a `SeasonPhase` or `Position` rawValue.

**Alternative that is also free but heavier:** a `LifeEvent` `@Model` type (§4.1 rule 2). Rejected
for three reasons: (a) it must be added to `DynastySchemaV1.models` — but V1 is **frozen**, so a
new model needs `DynastySchemaV2` to be created just to hold the list, which the "free" rule
assumes exists ("add it to the NEWEST schema version's `models` list", `DynastySchema.swift:48-49`);
(b) it would need `CareerScoped` conformance + entries in `CareerScope.cascadeDelete` and both
DEBUG audits; (c) `MultiSeasonSmokeTest.swift:35-44` keeps a **hand-synced duplicate** of the model
list that would silently drift (the schema file flags this at `:43-45`). The blob route touches
none of that.

---

## 9 · Fog & invariants a Life Events implementation must respect

### 9.1 `careerID` stamping

`Data/Persistence/CareerScope.swift`. Every population `@Model` conforms to `CareerScoped`
(`:12-14`, `var careerID: UUID? { get set }`) and is listed in the 27 conformance lines
(`:16-42`). `nil` = legacy row, adopted once by `adoptLegacyRowsIfNeeded(context:)` (`:90`).
`CareerScope.stamp(_:careerID:)` (`:67`) and the array overload (`:72`) must be called **at every
insert site**. `WeekAdvancer.activeCareerID` (`:160`, set in `bind` at `:165-167`, cleared `:179`)
is the ambient handle every engine reads (`CareerArcEngine.swift:58`, `TradeEngine.swift:122`, …).
`Career.schemaBackfillVersion` (`Career.swift:373`) gates the one-shot adoption.
**Implication:** if Life Events stays as blobs on `Career`, it is career-scoped *by construction*
— the blob lives on the career row. No stamping needed. But any *side effect* that inserts a row
(e.g. an `InboxMessage` is a struct so it's fine; a `Game`/`Player` mutation is not an insert) must
respect existing stamps. UserDefaults-backed state must go through `CareerScopedDefaults`
(`CareerScope.swift:550+` key list; `Data/Persistence/CareerScopedStorage.swift:130-151`) — never
bare `@AppStorage`, which binds its key before the career is known
(`CareerScopedStorage.swift:9-22` explains the bug this caused).

### 9.2 Fog discipline

The rule is absolute on the draft/scouting surfaces: **`trueOverall` / `truePotential` /
`truePhysical` / `trueMental` never reach a view.** Enforced by
`UI/Draft/Components/ProspectFog.swift` (header `:7-24`: *"`trueOverall` never reaches a view
again. The AI keeps drafting on the true numbers"*), and restated at
`UI/Draft/DraftDayCoordinator.swift:2078`, `UI/Scouting/ScoutBoardReads.swift:30`,
`UI/Scouting/ClassDepthView.swift:35`, `UI/Scouting/Top30VisitsView.swift:842`,
`UI/Draft/Components/LiveBigBoardPanel.swift:69`, `:859` (sorting on the true value leaks the board
even when the number is hidden). The AI is allowed to read truth; the **UI and any sort key** are
not. `PersonalitySource` (§1.4) is the provenance mechanism for a partial reveal.
**Implication:** a Life Event about a *prospect* must not leak his hidden grades; a rumor should be
a fogged/graded read (`PersonalitySource`-style strength ordering) rather than a fact, and the
event's own severity must not be inferable from a sort order. For rostered players there is no
overall-fog (the user sees his own roster), but a *rumor* stage before a *confirmed* stage is the
idiomatic fog here.

### 9.3 English-only

`sourceLanguage: "en"` in `dynasty/dynasty/Localizable.xcstrings:2`; `knownRegions = (en, Base)` in
`dynasty/dynasty.xcodeproj/project.pbxproj:91-94`. Per the user's standing instruction, **no `fi`
localization for new strings**. All Life Event headlines/bodies are English literals.
Additionally `tools/lint/trademark_guard.sh` **fails the build** on: `"Super Bowl"` in Swift source,
`"NFL"` inside a Swift string literal, `nfl*` in a bundled resource filename, either mark in the
league templates, and `"Canton"` in a **UI** Swift string literal. Life-Event copy ("suspended by
the league", "the Championship") must be written in the fictional register from the first draft —
never "NFL suspended", never "banned by the NFL".

### 9.4 DSType tokens & the one-gold-fill rule

`UI/Theme/DSTokens.swift` is the semantic layer over `UI/Common/Theme.swift`.
- Type ladder `DSType.Size` (`:125-147`): micro 10, caption 11, footnote 12, body 14, callout 16,
  title3 18, title2 22, title1 28, display 36, hero 48. Named roles at `:181-195`.
  A **legibility floor** landed in `50b5ff4` — no sub-10pt; `tools/lint/design_tokens.py` counts
  off-ladder `.system(size:)`, `cornerRadius:`, spacing literals and bespoke rating→Color functions
  against `tools/lint/design_tokens_baseline.json` and **exits 1 on regression**. Suppress with
  `// ds-lint:allow(font) reason`.
- Semantic colors: `chipKey` = `accentGold` (`:65`), `chipInfo` = `accentBlue` (`:67`),
  `ctaPrimary` = `accentGold` (`:70`). Text: `Color.dangerText` `#F87171` (`:46`) for red **text**
  (`danger #EF4444` is for fills/bars/glyphs only); `Color.textTertiaryReadable` `#7C8BA1` (`:40`)
  only where an opacity modifier is being removed — never as a swap for plain `textTertiary`.
- **One gold fill per screen** — `docs/UI_REDESIGN_VISION.md:236-241`, `:453`, `:775`:
  *"Gold fill is the primary action and appears exactly once per screen."* Enforced by convention
  and by explicit cross-file coordination in the draft room
  (`UI/Draft/Components/DraftStickyHeader.swift:48-69`, `DraftControlBar.swift:59`, `:537`,
  `WarRoomPanel.swift:662`, `LiveBigBoardPanel.swift:1018`).
  **Implication:** a Life Event pop-up gets **one** gold CTA (the commit: "Suspend him internally" /
  "Stand by him"), and every other option is `.dsSecondary`. If the pop-up appears over a screen
  that already has a gold fill, the sheet owns it and the underlying screen must not compete —
  which is automatic for a modal sheet.

---

## 10 · Risks

### 10.1 Sim determinism / seeded RNG — **RISK 1**

**The engine is overwhelmingly unseeded.** Measured across `dynasty/dynasty/Engine`:
- **428** `.random(in:)` / `randomElement()` call sites with **no** `using:` generator
  (Scouting 123, Simulation 102, PlayerDevelopment 59, Contract 57, Match 30, Media 24, Event 14,
  Draft 12, Medical 7, Camp 4, FreeAgency 1).
- **69** sites passing `using: &generator`.

So there is **no global seed and no replay determinism**. Determinism is adopted *per feature*
where a value must be stable across recomputation or relaunch. Three seeded dialects exist:

1. **SplitMix64 + `(careerID, season[, salt])` seed** — the house standard.
   - `Engine/Scouting/ScoutingEngine.swift:4858-4877` (`ScoutingCycleRandom`), seeded by
     `ScoutingEngine.cycleSeed(careerID:season:salt:)`. Its doc is the rule:
     *"never from `hashValue` (whose seed changes every launch, which would make 'deterministic per
     career-season' true only until the next relaunch)."* **Copy this warning.**
   - `Engine/PlayerDevelopment/PlayerRetirementEngine.swift:682-694` —
     `specialCaseSeed(careerID:season:)` = FNV-1a over the UUID bytes XOR
     `season &* 0x9E3779B97F4A7C15`, plus `mix(_:)` finalizer and a `playerSalt(_ id: UUID)`
     (`:702+`) *"so a given man's gate answers the same way for a given season no matter what order
     the league is iterated in"* — **exactly the property a per-player Life-Event roll needs.**
   - `Domain/Models/Player/TemplateAttributeSolver.swift:5-9`, `LeagueTemplateImporter.swift:669`.
   - `MentalAttributeModel.learning/competitiveness(..., seed: Int?)` — a UUID byte, deterministic.
2. **Knuth LCG** — `Engine/Draft/DraftEventEngine.swift:223-229` (`SeededGenerator`).
3. **`ScoutPoolGenerator`** SplitMix64 — `Engine/Simulation/CoachingEngine.swift:1964-1972`.

**Recommendation:** Life Events must use dialect 1 —
`lifeEventSeed(careerID:season:week:) ⊕ playerSalt(player.id)`. Reasons: (a) the roll is
re-derivable, so a re-entered offseason phase can't re-roll a different arrest; (b) it is
iteration-order-independent, which matters because `WeekAdvancer` iterates leagues in fetch order;
(c) it survives cold launch, which a process-global `Set` does not — a lesson already paid for
(`Career.swift:196-204` on `campFillSeason`: *"a process-global set … does not survive a cold
launch, so the fill would run a second time"*).

### 10.2 Save compatibility — **RISK 2**

Two distinct failure modes, both silent:
- **Blob-emptying.** Adding a non-optional field to `LockerRoomEvent`, `NewsItem`, or
  `InboxMessage` to carry life-event data empties the *whole* array for every existing save
  (`SWIFTDATA_MIGRATION_PLAN.md` §4.2). The `try? JSONDecoder().decode(...)` in every accessor
  turns a decode failure into `[]` with **no error surfaced anywhere**. Mitigation: new fields must
  be `Optional`, or ship a new blob column instead of extending an old one.
- **Forward-incompat on downgrade.** `NewsItem.category` is a `String`-raw `NewsCategory`
  (`NewsGenerator.swift:39-43`) with **no** custom `init(from:)` and no unknown-case fallback. A
  new category rawValue written by a newer build makes an older build's *entire* `newsLog` decode
  fail → empty feed. `offFieldIncident` **already exists** (`:42`), so Life Events should reuse it
  rather than adding cases. If new cases are unavoidable, add a custom
  `init(from:)` with an `unknown` fallback in the same release.

### 10.3 Balance-harness breakage — **RISK 3**

`tools/balance-harness/sync_sources.sh` copies **33 engine sources verbatim** into a throwaway
`build/src` and **sha-verifies each copy against the repo**, then compiles them standalone with
`swiftc -O`. Files in that list that Life Events would plausibly touch:

`Domain/Enums/PersonalityArchetype.swift`, `Domain/Models/Player/PlayerPersonality.swift`,
`Domain/Models/Player/PlayerAttributes.swift`, `Domain/Enums/Motivation.swift`,
`Domain/Enums/MotivationState.swift`, `Domain/Models/Player/MentalAttributeModel.swift`,
`Domain/Models/Player/InjuryRecord.swift`, `Domain/Enums/InjuryType.swift`,
`Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift`,
`Engine/PlayerDevelopment/PlayerRetirementEngine.swift`, `Engine/Simulation/GameSimulator.swift`,
`Engine/Scouting/DraftClassBuilder.swift`.

**Any new symbol introduced into one of these files** (e.g. a `LifeEventsEngine.modifier(for:)`
call inside `PlayerDevelopmentEngine`, or a new case referencing a new type on
`PersonalityArchetype`) **breaks the harness build** — the harness has no `Career`, no SwiftData,
and no Life Events source. The `career` / `draftclass` / `leaguegen` scenarios are release gates
(`tools/balance-harness/run.sh:12-20`). Mitigations, in order of preference: (a) keep all Life
Events logic in *new* files not on the sync list and call **into** them from `WeekAdvancer` only
(`WeekAdvancer.swift` is **not** synced); (b) if a synced file must change, add the new source to
`VERBATIM_SOURCES` in `sync_sources.sh` and make it SwiftData-free; (c) worst case, stub it in
`driver/GameModels.harness.swift`.
Also note `CollegeProspect.swift:53-57` documents that the computed-property block is spliced
verbatim into the harness and *"must stay free of types the harness does not compile"* — the same
constraint applies to any block Life Events adds there.

### 10.4 The `MultiSeasonSmokeTest` duplicate model list — **RISK 4**

`Engine/Simulation/MultiSeasonSmokeTest.swift:34-44` hand-syncs a copy of the 29-model schema list
for its in-memory container. `DynastySchema.swift:43-45` flags this explicitly:
*"still keeps a hand-synced duplicate of this list … pointing it here is a one-line follow-up."*
If Life Events ever adds a `@Model` (it should not — §8.3), **both** lists must change or the smoke
test silently runs against a different schema. Choosing the blob route sidesteps this entirely.

### 10.5 Double-fire / idempotency across phase re-entry — **RISK 5**

Offseason phases are **re-enterable** after a quit and relaunch, and the codebase has already been
burned by this twice:
- `Career.swift:196-204` (`campFillSeason`) — a process-global set did not survive a cold launch
  and every club got re-filled on top of the user's cuts.
- `WeekAdvancer.swift:76`, `:3777` — UDFA idempotency rests on `UDFAMarketState.season`, *"a
  PERSISTED stamp"*.
- `WeekAdvancer.swift:2534` — `guard career.pendingLockerRoomEvent == nil else { return }` is the
  locker-room single-flight guard.

**A Life Events scheduler must carry a persisted `(season, phase, week)` stamp inside
`LifeEventsState`**, not a `static var` on the engine, and must guard on a pending event the way
locker room does. A duplicated arrest that suspends a starter twice is an unrecoverable save bug.

### 10.6 Availability regression — the balance trap

The suspension gate itself is cheap (two lines, §5.4). The trap is scope creep next to it.

`GameSimulator.swift:130-131` and `LiveGameEngine.swift:1283-1284` currently filter **holdouts
only**. It is very tempting, while adding `&& !$0.isSuspended`, to "fix" the missing injury filter
at the same time. **Do not.** `GameSimulator.swift:90-98` documents that leaving injured players in
the regular-season sim is a deliberate shipped simplification, and the balance bands
(`docs/BALANCE_REPORT_2026-07.md`, the `fullgame` / `career` harness scenarios) were all measured
with it in place. Adding the injury filter would silently move every scoring, YPA and development
number, and the harness would not attribute the shift to Life Events.

Two further consequences to design around:
- **Timing.** The sim runs at `WeekAdvancer.swift:1324`, near the top of the weekly block. A
  suspension applied by a Life Events pass placed after `processLockerRoomWeek` (`:1737`) takes
  effect **next** week, not this one. If same-week effect is wanted, the scheduler must run before
  `:1324` — which also means before the news/inbox block, so the notification ordering has to be
  handled deliberately.
- **`SimPlayer` cannot carry the state.** Any availability concept must filter the `[Player]` array
  *before* `SimPlayer.init(from:)`. There is no way to make the sim itself aware of it, and the
  #208 lesson applies with full force: the guard belongs in the engine, not the view. `RosterCutView`,
  `DepthChartView` and `InjuryReportView` all read `Player` directly, so a UI-only suspension would
  be bypassed by every other path.

### 10.7 Meter double-counting

`OwnerSatisfactionEngine.updateSatisfaction` already applies **±1 per negative/positive `NewsItem`**
(`Engine/Media/OwnerSatisfactionEngine.swift:16-105`, called `WeekAdvancer.swift:1604`). A Life Event
that both emits a negative `NewsItem` *and* applies its own `ownerEffect` moves the owner meter
twice. Same shape on morale: `LockerRoomEngine.weeklyMoraleUpdate` (`:270`) already caps the weekly
swing at ±3 (`weeklyMoraleSwingCap` `:138`) and reverts ±1 toward `moraleBaseline = 70` (`:132`) —
a Life Event morale delta applied *after* `:1770` escapes that cap entirely. Apply Life Event morale
deltas **before** `weeklyMoraleUpdate` so they are damped by the same governor, or explicitly
document why they are exempt.

Also note there is **no persistent team-level fan meter** (§4.4). If Life Events wants one, it is
new scope — `Career.reputation` is the only durable candidate, and `DraftReputation.fanMood` is
draft-season-scoped and mutated by exactly one engine.

