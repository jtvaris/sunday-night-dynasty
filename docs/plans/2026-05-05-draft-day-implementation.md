# Draft Day Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the NFL Draft experience as an event-driven, NFL Fantasy Draft-style flow with strategic decision support, two-tier Pick Grades, and a gem story arc that pays off across seasons.

**Architecture:** `DraftDayCoordinator` (state, @MainActor) drives a deterministic `DraftEventEngine` that produces a typed event stream. `DraftIntel` exposes the player-visible knowledge (with confidence-based noise). `DraftStoryRecorder` persists events to SwiftData. UI is a 3-pane iPad layout: Live Big Board / Draft Ticker / War Room.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Swift Testing (new Tests target), iOS 17+, iPad-first.

**Reference design:** `docs/plans/2026-05-05-draft-day-design.md`

**Phasing:** 6 phases (`Vaihe 1`–`Vaihe 6`). This plan details Vaihe 1 (Core mechanics) at task granularity. Phases 2–6 are sketched at the end and detailed in follow-up plan iterations as each phase completes.

---

## Pre-flight: Cleanup and ground rules

- We are doing a **full rebuild** of `dynasty/dynasty/UI/Draft/` and `dynasty/dynasty/Engine/Draft/`. Old files are removed in Vaihe 1 Task 1.
- Existing `MockDraftView.swift` and `DraftOrderView.swift` (under Scouting) are preserved — they are pre-draft scouting tools, not the draft event itself.
- All new domain models added to SwiftData schema in `DataContainer.create()`.
- Existing reference data preserved: `DraftPick`, `Player`, `CollegeProspect`, `Career`, `Team`, `Coach`, `Position`, `Scheme`, `StandingsCalculator`.
- Build via `xcodebuild` for iPad simulator. Run via simulator with `ios-simulator-skill`.
- Visual polish skills (`design`, `ui-ux-pro-max`, `swiftui-pro`) are invoked in Vaihe 4.

---

# VAIHE 1 — Core Mechanics

**Acceptance criterion:** Draft completes end-to-end (224 picks), no crashes, user pick visible and selectable, skip-to-my-pick works, basic ticker rolls.

## Task 1.1 — Remove old Draft files

**Files:**
- Delete: `dynasty/dynasty/UI/Draft/DraftView.swift`
- Delete: `dynasty/dynasty/UI/Draft/DraftPickCard.swift`
- Delete: `dynasty/dynasty/UI/Draft/DraftSelectionSheet.swift`
- Delete: `dynasty/dynasty/UI/Draft/TradeOfferView.swift`
- Delete: `dynasty/dynasty/Engine/Draft/DraftEngine.swift`
- Modify: navigation (ShellDestination `.draft` will fail to compile until Task 1.13 — that's fine, project will be in broken state until UI shell wired)

**Step 1**: `git rm` the five files.
**Step 2**: Add a stub `DraftDayView.swift` with `Text("Draft — under construction")` so navigation compiles.
**Step 3**: Build (`xcodebuild -scheme dynasty -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)' build`); should compile.
**Step 4**: Commit `chore: remove old draft scaffolding ahead of rebuild`.

## Task 1.2 — Create Tests target

**Files:**
- Modify: `dynasty/dynasty.xcodeproj/project.pbxproj` (add Tests target)
- Create: `dynasty/dynastyTests/dynastyTests.swift` (placeholder smoke test)

**Step 1**: Add Tests target via `xcodebuild` or by editing project (use `xed` if needed). Use Swift Testing (`import Testing`, `@Test`).
**Step 2**: Add a `@Test func smoke() { #expect(1 + 1 == 2) }` placeholder.
**Step 3**: Run `xcodebuild test -scheme dynasty -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)'`. Expect: PASS.
**Step 4**: Commit `chore: add Tests target with Swift Testing`.

## Task 1.3 — `DraftEvent` SwiftData model

**Files:**
- Create: `dynasty/dynasty/Domain/Models/Draft/DraftEvent.swift`
- Create: `dynasty/dynasty/Domain/Models/Draft/DraftEventType.swift`
- Modify: `dynasty/dynasty/Data/Persistence/DataContainer.swift` (add to schema)

**Step 1**: Write a test in `dynastyTests/Domain/DraftEventTests.swift`:
```swift
import Testing
import SwiftData
@testable import dynasty

@Test func draftEventStoresPickMadePayload() throws {
  let event = DraftEvent(
    draftYear: 2026,
    sequence: 5,
    type: .pickMade,
    teamID: UUID(),
    pickNumber: 5,
    round: 1,
    prospectID: UUID(),
    timestamp: .now
  )
  #expect(event.type == .pickMade)
  #expect(event.pickNumber == 5)
}
```
**Step 2**: Run test → fails (DraftEvent undefined).
**Step 3**: Implement:
```swift
import SwiftData
import Foundation

@Model
final class DraftEvent {
  var id: UUID
  var draftYear: Int
  var sequence: Int
  var typeRaw: String
  var teamID: UUID?
  var pickNumber: Int?
  var round: Int?
  var prospectID: UUID?
  var payloadJSON: String?     // for non-pick events
  var timestamp: Date

  var type: DraftEventType {
    get { DraftEventType(rawValue: typeRaw) ?? .pickMade }
    set { typeRaw = newValue.rawValue }
  }

  init(draftYear: Int, sequence: Int, type: DraftEventType,
       teamID: UUID? = nil, pickNumber: Int? = nil, round: Int? = nil,
       prospectID: UUID? = nil, payloadJSON: String? = nil,
       timestamp: Date = .now) {
    self.id = UUID()
    self.draftYear = draftYear
    self.sequence = sequence
    self.typeRaw = type.rawValue
    self.teamID = teamID
    self.pickNumber = pickNumber
    self.round = round
    self.prospectID = prospectID
    self.payloadJSON = payloadJSON
    self.timestamp = timestamp
  }
}

enum DraftEventType: String, Codable {
  case pickMade
  case tradeOffered
  case tradeAccepted
  case tradeDeclined
  case bigDrop
  case positionRun
  case stealAlert
  case scoutInterrupt
  case mediaReaction
  case ownerReaction
  case lockerRoomReaction
  case fanReaction
  case roundTransition
  case clockExpired
  case onTheClock
  case draftStarted
  case draftCompleted
}
```
**Step 4**: Add `DraftEvent.self` to `Schema(versionedSchema: ...)` in `DataContainer.swift`.
**Step 5**: Run tests → PASS.
**Step 6**: Commit `feat: add DraftEvent SwiftData model and event types`.

## Task 1.4 — `DraftPickGrade` and `CareerArcState` SwiftData models

**Files:**
- Create: `dynasty/dynasty/Domain/Models/Draft/DraftPickGrade.swift`
- Create: `dynasty/dynasty/Domain/Models/Draft/CareerArcState.swift`
- Modify: `dynasty/dynasty/Data/Persistence/DataContainer.swift`

**Step 1**: Tests asserting both models can be created and stored.
**Step 2**: Implement (both `@Model final class`, with letter-grade enums for Public/True).
**Step 3**: Add to schema.
**Step 4**: Tests pass; commit `feat: add DraftPickGrade and CareerArcState models`.

## Task 1.5 — `PickValueChart` (Jimmy Johnson)

**Files:**
- Create: `dynasty/dynasty/Engine/Draft/PickValueChart.swift`
- Create: `dynasty/dynastyTests/Engine/PickValueChartTests.swift`

**Step 1**: Tests:
```swift
@Test func pickValueChartReturnsCanonicalValues() {
  #expect(PickValueChart.points(forPick: 1) == 3000)
  #expect(PickValueChart.points(forPick: 32) == 590)
  #expect(PickValueChart.points(forPick: 100) == 100)
  #expect(PickValueChart.points(forPick: 224) == 1)
}
```
**Step 2**: Implement as a `enum PickValueChart` with a static lookup table (Jimmy Johnson values for picks 1-224).
**Step 3**: Tests pass; commit `feat: add Jimmy Johnson pick value chart`.

## Task 1.6 — `RookieScalingEngine` (extracted from old DraftEngine)

**Files:**
- Create: `dynasty/dynasty/Engine/Draft/RookieScalingEngine.swift`
- Create: `dynasty/dynastyTests/Engine/RookieScalingEngineTests.swift`

**Step 1**: Tests for scale factor by pick (rd1: 0.85+, late: 0.55+, 5% elite chance).
**Step 2**: Implement `static func scaleFactor(pickNumber:) -> Double` and `static func convertToPlayer(prospect:teamID:pickNumber:salaryCap:) -> Player`.
**Step 3**: Implement `rookieContract(pickNumber:salaryCap:)` (years + dollar amounts based on 2026 rookie wage scale).
**Step 4**: Tests pass; commit `feat: add rookie scaling engine`.

## Task 1.7 — `DraftIntel` layer

**Files:**
- Create: `dynasty/dynasty/Engine/Draft/DraftIntel.swift`
- Create: `dynasty/dynastyTests/Engine/DraftIntelTests.swift`

**Step 1**: Tests:
```swift
@Test func intelNoisesOVRBasedOnConfidence() {
  let prospect = makeProspect(trueOVR: 90, scoutConfidence: 5)
  #expect(DraftIntel.publicOVR(of: prospect) == 90)  // full confidence = no noise
  let lowConf = makeProspect(trueOVR: 90, scoutConfidence: 1)
  let public = DraftIntel.publicOVR(of: lowConf)
  #expect(abs(public - 90) <= 12)  // up to ±12 noise at 1-star
}
```
**Step 2**: Implement:
- `static func publicOVR(of prospect: CollegeProspect) -> Int` — applies seeded noise inversely proportional to scoutConfidence
- `static func customRank(of prospect, in board: BigBoard) -> Int`
- `static func teamNeeds(team: Team, roster: [Player]) -> [Position: Double]` (priority 0..1)
- `static func reachIndicator(prospectBBRank:pickNumber:) -> ReachIndicator` (.steal/.solid/.reach)
**Step 3**: Tests pass; commit `feat: add DraftIntel player-knowledge layer`.

## Task 1.8 — `PickGradeCalculator`

**Files:**
- Create: `dynasty/dynasty/Engine/Draft/PickGradeCalculator.swift`
- Create: `dynasty/dynastyTests/Engine/PickGradeCalculatorTests.swift`

**Step 1**: Tests covering all five grade letters at boundaries (use Design §5 thresholds).
**Step 2**: Implement:
```swift
enum PickGradeCalculator {
  struct Inputs {
    let valueDelta: Int      // BB rank − pick number
    let needScore: Double    // 0..1
    let publicOVR: Int       // 40..99
    let schemeFit: Double    // 0..1
  }
  static func compute(_ inputs: Inputs) -> PickGrade { ... }
}
```
**Step 3**: Tests pass; commit `feat: add public Pick Grade calculator`.

## Task 1.9 — `DraftEventEngine` (deterministic stream)

**Files:**
- Create: `dynasty/dynasty/Engine/Draft/DraftEventEngine.swift`
- Create: `dynasty/dynastyTests/Engine/DraftEventEngineTests.swift`

**Step 1**: Tests:
```swift
@Test func draftEventEngineIsDeterministic() {
  let stream1 = DraftEventEngine.makeStream(seed: 42, ...)
  let stream2 = DraftEventEngine.makeStream(seed: 42, ...)
  #expect(stream1.count == stream2.count)
  #expect(stream1.map(\.type) == stream2.map(\.type))
}

@Test func streamContains224PickEvents() {
  let stream = DraftEventEngine.makeStream(seed: 1, ...)
  let picks = stream.filter { $0.type == .pickMade || $0.type == .onTheClock }
  #expect(picks.filter { $0.type == .pickMade }.count == 224)
}
```
**Step 2**: Implement:
- Generate draft order (port `generateDraftOrder` logic from old DraftEngine, using `StandingsCalculator`)
- For each pick in order: emit `onTheClock` event, then `pickMade` (AI selects via `aiPick(team:available:roster:seed:)`)
- Inject `roundTransition` between rounds
- Emit `bigDrop` when prospect's BB rank > pick number + 8
- Emit `positionRun` when 3 same-position picks in last 5
- Initially: NO trade offers, NO reactions (Vaihe 3)
- Use `SeededGenerator` (linear-congruential) for determinism
**Step 3**: Tests pass; commit `feat: add deterministic DraftEventEngine with pick stream`.

## Task 1.10 — `DraftDayCoordinator` (state + clock)

**Files:**
- Create: `dynasty/dynasty/UI/Draft/DraftDayCoordinator.swift`
- Create: `dynasty/dynastyTests/UI/DraftDayCoordinatorTests.swift`

**Step 1**: Tests:
```swift
@MainActor @Test func coordinatorAdvancesToUserPick() async {
  let coord = DraftDayCoordinator(seed: 1, userTeamID: ...)
  await coord.start()
  await coord.skipToMyPick()
  #expect(coord.mode == .userPick)
  #expect(coord.currentEvent?.teamID == userTeamID)
}
```
**Step 2**: Implement `@MainActor final class DraftDayCoordinator: ObservableObject`:
- `@Published var state: DraftDayState`
- `func start()`, `selectProspect(_:)`, `skipToMyPick()`, `skipToNextEvent()`, `skipToNextRound()`, `pause()`, `resume()`, `setSpeed(_:)`
- Internal Task-based clock loop using `Task.sleep(nanoseconds:)` with speed multiplier
- State machine transitions per Design §3
**Step 3**: Tests pass; commit `feat: add DraftDayCoordinator with state machine and clock`.

## Task 1.11 — `DraftStoryRecorder` (event persistence)

**Files:**
- Create: `dynasty/dynasty/Engine/Draft/DraftStoryRecorder.swift`
- Create: `dynasty/dynastyTests/Engine/DraftStoryRecorderTests.swift`

**Step 1**: Test that calling `record(event:)` persists to ModelContext and can be queried back.
**Step 2**: Implement actor `DraftStoryRecorder` taking a ModelContext, `func record(_ event: DraftEvent)` and `func events(forYear:) -> [DraftEvent]`.
**Step 3**: Tests pass; commit `feat: add DraftStoryRecorder for event persistence`.

## Task 1.12 — Theme tokens for draft

**Files:**
- Modify: `dynasty/dynasty/UI/Common/Theme.swift`

**Step 1**: Add tokens used by draft: `Color.draftClockUrgent`, `Color.draftStealGold`, `Color.draftReachRed`, accent gradients, plus animation durations (`AnimDur.bannerIn = 0.35`, etc.).
**Step 2**: Build; commit `feat: extend theme with draft-specific tokens`.

## Task 1.13 — `DraftDayView` shell + sticky header

**Files:**
- Modify: `dynasty/dynasty/UI/Draft/DraftDayView.swift` (replace stub)
- Create: `dynasty/dynasty/UI/Draft/Components/DraftStickyHeader.swift`

**Step 1**: Implement `DraftDayView` taking a `Career`, instantiating `DraftDayCoordinator`, wiring `.task { coord.start() }`. Layout: VStack with sticky header at top, then 3-pane HStack (placeholders for now).
**Step 2**: Implement `DraftStickyHeader`: round, current pick #, on-the-clock team name, clock countdown, user's-next-pick-distance, picks-remaining count.
**Step 3**: Use `#Preview` with a fixture career for SwiftUI canvas.
**Step 4**: Build, run on simulator, verify header renders. Commit `feat: DraftDayView shell + sticky header`.

## Task 1.14 — `DraftTickerPanel`

**Files:**
- Create: `dynasty/dynasty/UI/Draft/Components/DraftTickerPanel.swift`

**Step 1**: List view binding to `coordinator.state.events`, showing past picks (with team logo / abbrev, prospect name, position, grade chip placeholder), the live "on the clock" row pulsing, and 3 upcoming team rows.
**Step 2**: Animation: new picks slide in from bottom, latest pulses 0.6 s.
**Step 3**: `#Preview` with sample data; build; commit `feat: DraftTickerPanel with live pick feed`.

## Task 1.15 — `LiveBigBoardPanel`

**Files:**
- Create: `dynasty/dynasty/UI/Draft/Components/LiveBigBoardPanel.swift`

**Step 1**: List of available prospects sorted by user's custom rank (fallback BB rank). Per row: rank, name, position, scout-confidence stars, my/BB rank delta, drafted state (greyed if drafted). Sort menu (My Rank / BB Rank / OVR), Position filter.
**Step 2**: Tap row → trigger detail sheet (placeholder for now).
**Step 3**: `#Preview`; build; commit `feat: LiveBigBoardPanel with sorting and filters`.

## Task 1.16 — `WarRoomPanel` (skeleton)

**Files:**
- Create: `dynasty/dynasty/UI/Draft/Components/WarRoomPanel.swift`

**Step 1**: Three sections (Scout Chatter / Trade Radar / Pick Value). Vaihe 1 surfaces only basic Pick Value (current pick value points, user's next pick value, simple compare). Scout Chatter shows a static placeholder. Trade Radar empty in Vaihe 1.
**Step 2**: Build; commit `feat: WarRoomPanel skeleton (pick value live)`.

## Task 1.17 — `PickSheetView`

**Files:**
- Create: `dynasty/dynasty/UI/Draft/Components/PickSheetView.swift`

**Step 1**: Modal sheet over ticker (use `.sheet(presentationDetents: .medium, .large)`). Top 5-10 prospects from intel (sorted by my rank). Per row: name, position, scout-confidence, reach-indicator chip (`STEAL? +4 / SOLID / REACH -3`). Buttons: Draft, Trade Up (disabled in Vaihe 1), Trade Down (disabled), See Full Board.
**Step 2**: On Draft → coordinator.selectProspect(_:) → sheet closes.
**Step 3**: `#Preview` and simulator test.
**Step 4**: Commit `feat: PickSheetView with reach indicator`.

## Task 1.18 — `DraftControlBar` (skip + speed)

**Files:**
- Create: `dynasty/dynasty/UI/Draft/Components/DraftControlBar.swift`

**Step 1**: Bottom-bar HStack with: Skip-to-my-pick, Skip-to-next-event, Pause/Resume toggle, Speed selector (1× / 2× / 4×).
**Step 2**: Wire each button to coordinator method.
**Step 3**: `#Preview`; commit `feat: DraftControlBar with skip and speed`.

## Task 1.19 — Wire 3-pane layout into `DraftDayView`

**Files:**
- Modify: `dynasty/dynasty/UI/Draft/DraftDayView.swift`

**Step 1**: Compose: VStack { sticky header; HStack { LiveBigBoardPanel | DraftTickerPanel | WarRoomPanel } ; DraftControlBar }. Use `horizontalSizeClass == .regular` for iPad. Set `.background` to dimmed `Image("BgDraft")`.
**Step 2**: Add sheet binding for `PickSheetView` when `coordinator.mode == .userPick`.
**Step 3**: Run simulator, verify layout on iPad Pro 12.9".
**Step 4**: Commit `feat: wire 3-pane DraftDayView with pick sheet`.

## Task 1.20 — Coordinator → SwiftData wiring

**Files:**
- Modify: `dynasty/dynasty/UI/Draft/DraftDayCoordinator.swift`
- Modify: `dynasty/dynasty/UI/Draft/DraftDayView.swift`

**Step 1**: Coordinator accepts a `ModelContext` on init. On every event consumption: convert to `DraftEvent` and pass to `DraftStoryRecorder.record`. On user pick: save the resulting `Player` and update `DraftPick.playerID`.
**Step 2**: Manual simulator test: complete a draft (skip-to-my-pick + select), verify drafted players appear on roster afterwards.
**Step 3**: Commit `feat: persist draft events and drafted players`.

## Task 1.21 — Vaihe 1 acceptance run

**Steps:**
1. Build clean: `xcodebuild -scheme dynasty -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch) (6th generation)' build`
2. Launch simulator, navigate to Draft, complete one draft
3. Capture screenshots at: pre-draft, mid-round-1, user-pick-sheet, post-pick, end-of-draft
4. Run `auto-analyze` skill on screenshots
5. Verify acceptance criteria (Design §13 Phase 1)
6. Commit playtest notes to `docs/playtest-notes/2026-05-05-draft-iter-1.md`

If any criterion fails → fix in additional tasks, repeat acceptance run.

---

# VAIHE 2 — Decision Support (high-level)

After Vaihe 1 acceptance:
- Pick Sheet: per-prospect inline grade preview (uses `PickGradeCalculator`)
- Big Board: scout-confidence stars, BB-vs-My-rank delta, custom-rank reorder
- War Room: live scout chatter (static lines tied to events for now), team needs visualization, position depth strips
- Sticky Header: animated countdown to next user pick (3-pick warning pulse)

## VAIHE 3 — Trade Engine + Reactions

- `TradeEvaluator` engine with Jimmy Johnson + need + future-discount
- AI-initiated trade offers in event stream (banner + sheet)
- User-initiated trade builder (modal in War Room)
- 4-actor reaction system with selectivity rules per Design §6
- Owner trust / fan mood / locker room / media narrative state mutations
- Round Recap card with cumulative reactions

## VAIHE 4 — Drama + Visual Polish

- Steal banners (ESPN-style breaking news), round transitions, breaking-news ticker
- Helmi-merkki gold-rim animation
- Invoke `design` skill for Liquid Glass treatment
- Invoke `ui-ux-pro-max` for color/typography refinement
- Invoke `swiftui-pro` for animation review
- Sound stub (optional in Vaihe 4, full audio in Vaihe 6)

## VAIHE 5 — Career Arc + Story

- `CareerArcEngine` running in offseason flow
- True Grade computation per drafted player (rookie season, year 2, year 4 milestones)
- News flashbacks tied to gem triggers
- Player Profile badge (Public + True Grade)
- Draft History view with re-watch (replay events from `DraftEvent` table)
- Decade summary

## VAIHE 6 — Balance + QA

- Auto-analyze runs across 20+ seeds
- Tune weights (helmi probability, trade frequency, reach penalty)
- Bug fixes, edge cases
- 5/5 manual playtests at "felt great"
- Final `gate-check` skill audit

---

## Plan complete

Plan saved to `docs/plans/2026-05-05-draft-day-implementation.md`.

**Execution mode:** Subagent-Driven Development. The orchestrator (this session) dispatches a fresh subagent per task, reviews each task on completion, runs build/tests, captures simulator state via `auto-analyze` at phase boundaries. The orchestrator owns the ReAct loop: at each phase boundary, it captures, analyzes, fixes, and re-runs until acceptance criterion is met.
