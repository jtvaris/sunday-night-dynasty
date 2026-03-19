# Press Conference Situational Questions Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire the existing weekly press conference engine into the game loop so players face situational press conferences after each game during the regular season, with questions that react to team performance.

**Architecture:** `PressConferenceEngine.generateWeeklyPressConference()` is fully coded with post-win, post-loss, playoff push, struggle, and generic questions. What's missing: (1) WeekAdvancer integration to trigger press conferences, (2) a weekly press conference UI modal in the dashboard, (3) applying effects to career state.

**Tech Stack:** Swift, SwiftUI, SwiftData

---

### Task 1: Store Weekly Press Conference in WeekAdvancer

**Files:**
- Modify: `Dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`

**Step 1: Add static storage for pending press conference**

After the existing static vars (around line 29), add:

```swift
/// Press questions generated after the player's game, pending UI presentation.
static var pendingPressConference: [PressQuestion]?
```

**Step 2: Generate press conference after player's game**

In `advanceRegularSeasonWeek()`, after the game simulation loop (after line 190 where `lastPlayerGameResult` is stored), add:

```swift
// 0. Generate weekly press conference questions
if let playerTeamID = career.teamID,
   let playerTeam = teamsByID[playerTeamID] {
    let lastGameWon: Bool? = {
        guard let result = playerGameResult else { return nil }
        // Find the game to determine home/away
        if let game = unplayedGames.first(where: {
            $0.homeTeamID == playerTeamID || $0.awayTeamID == playerTeamID
        }) {
            let isHome = game.homeTeamID == playerTeamID
            return isHome ? result.homeScore > result.awayScore : result.awayScore > result.homeScore
        }
        return nil
    }()

    pendingPressConference = PressConferenceEngine.generateWeeklyPressConference(
        career: career,
        team: playerTeam,
        lastGameResult: lastGameWon,
        week: week
    )
}
```

---

### Task 2: Create WeeklyPressConferenceView

**Files:**
- Create: `Dynasty/dynasty/UI/Career/WeeklyPressConferenceView.swift`

**Step 1: Build the view**

Reuse the same visual pattern as `PressConferenceView` (reporter badge, question card, response options, media reaction) but simplified for 2-3 questions instead of 5.

```swift
struct WeeklyPressConferenceView: View {
    let questions: [PressQuestion]
    let career: Career
    let onComplete: (PressConferenceResult) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var currentQuestionIndex = 0
    @State private var selectedResponses: [Int] = []
    @State private var showReaction = false
    @State private var isComplete = false

    var body: some View {
        // Similar to PressConferenceView but:
        // - No intro phase (jump straight to questions)
        // - Compact summary at end
        // - "Post-Game Press Conference" title
    }
}
```

Key elements:
- Title: "POST-GAME PRESS CONFERENCE — WEEK {N}"
- Reporter badge with name/outlet from PressQuestion
- Question text in quotes
- Response cards with tone badges (reuse exact style from PressConferenceView)
- Media reaction banner after each answer
- Brief summary at end showing effects
- "Return to Dashboard" button calls onComplete with PressConferenceResult

**Step 2: Build the result using PressConferenceEngine.buildResult()**

```swift
private func completeConference() {
    let result = PressConferenceEngine.buildResult(
        questions: questions,
        selectedIndices: selectedResponses,
        season: career.currentSeason
    )
    onComplete(result)
}
```

---

### Task 3: Integrate into CareerDashboardView / CareerShellView

**Files:**
- Modify: `Dynasty/dynasty/UI/Career/CareerShellView.swift`

**Step 1: Add press conference state**

```swift
@State private var pendingPressQuestions: [PressQuestion]?
@State private var showWeeklyPressConference = false
```

**Step 2: Check for pending press conference after advancing week**

In the `performShellAdvance()` method (or wherever advanceWeek is called), after calling `WeekAdvancer.advanceWeek()`:

```swift
// Check for pending press conference
if let questions = WeekAdvancer.pendingPressConference {
    pendingPressQuestions = questions
    showWeeklyPressConference = true
    WeekAdvancer.pendingPressConference = nil
}
```

**Step 3: Present as fullScreenCover**

```swift
.fullScreenCover(isPresented: $showWeeklyPressConference) {
    if let questions = pendingPressQuestions {
        WeeklyPressConferenceView(
            questions: questions,
            career: career,
            onComplete: { result in
                applyPressConferenceEffects(result)
                showWeeklyPressConference = false
            }
        )
    }
}
```

---

### Task 4: Apply Press Conference Effects to Career State

**Files:**
- Modify: `Dynasty/dynasty/UI/Career/CareerShellView.swift`

**Step 1: Create effect application method**

```swift
private func applyPressConferenceEffects(_ result: PressConferenceResult) {
    // Owner satisfaction
    career.ownerSatisfaction = min(100, max(-100,
        career.ownerSatisfaction + result.totalEffects.ownerSatisfaction))

    // Legacy points
    career.legacyTracker.addLegacyPoints(result.totalEffects.legacyPoints)

    // Media reputation
    career.legacyTracker.mediaReputation = min(100, max(-100,
        career.legacyTracker.mediaReputation + result.totalEffects.mediaPerception))

    // Track new promises
    for promise in result.promises {
        career.legacyTracker.promises.append(promise)
    }

    // Save
    try? modelContext.save()
}
```

Check Career model for exact property names — may be `ownerSatisfaction` or similar. Also check if `legacyTracker` is a property on Career.

---

### Task 5: Add TODO #13 dynamic questions

**Files:**
- Modify: `Dynasty/dynasty/Engine/Media/PressConferenceEngine.swift`

Enhance `generateWeeklyPressConference()` with more situational triggers:

```swift
// Winning streak (3+ wins in a row)
if career.currentStreak >= 3 {
    situationalQuestion = generateWinningStreakQuestion(career: career, team: team)
}

// Losing streak (3+ losses)
if career.currentStreak <= -3 {
    situationalQuestion = generateLosingStreakQuestion(career: career, team: team)
}

// Division rivalry game
// Trade deadline approaching (week 8-9)
// First game of season
// Season finale
```

Add new question generators following the exact pattern of existing ones (generatePlayoffPushQuestion etc).

---

### Task 6: Update TODO.md

**Files:**
- Modify: `docs/TODO.md`

Mark #77 and #13 as complete.
