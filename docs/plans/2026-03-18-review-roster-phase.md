# Review Roster Phase Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire the existing RosterEvaluationView into the offseason flow as a new "Review Roster" phase with 4 guided tasks, placed after Free Agency and before the Draft.

**Architecture:** RosterEvaluationView already has 4 complete sections (Position Grades, Key Decisions, Cap Outlook, Strengths/Weaknesses). We need to: (1) add a `.reviewRoster` SeasonPhase case, (2) add TaskDestination + ShellDestination for navigation, (3) generate 4 guided tasks, (4) wire phase transitions in WeekAdvancer.

**Tech Stack:** Swift, SwiftUI, SwiftData

---

### Task 1: Add SeasonPhase case

**Files:**
- Modify: `Dynasty/dynasty/Domain/Enums/SeasonPhase.swift`

Add `.reviewRoster` case. Insert it between `.freeAgency` and `.draft` in the enum. Add display name "Review Roster" and appropriate description.

---

### Task 2: Add navigation destinations

**Files:**
- Modify: `Dynasty/dynasty/UI/Career/CareerShellView.swift`

Step 1: Add `case rosterEvaluation` to `ShellDestination` enum.

Step 2: Add navigation handler in `destinationView(for:)`:
```swift
case .rosterEvaluation:
    RosterEvaluationView(career: career)
        .onAppear {
            markTaskVisited(for: .rosterEvaluation)
            refreshTaskCompletionStatus()
        }
```

Note: Check if RosterEvaluationView takes `career` param or `players` — read the existing view first.

---

### Task 3: Add task generation for Review Roster phase

**Files:**
- Modify: `Dynasty/dynasty/Engine/Simulation/TaskGenerator.swift`

Step 1: Add `case rosterEvaluation` to `TaskDestination` enum.

Step 2: Add `reviewRosterTasks()` function generating 4 tasks:

```swift
static func reviewRosterTasks() -> [GameTask] {
    [
        GameTask(
            title: "Review Position Group Grades",
            description: "Check which position groups need depth and which are strengths",
            destination: .rosterEvaluation,
            isRequired: true
        ),
        GameTask(
            title: "Analyze Contract Situations",
            description: "Review expiring contracts, overpaid and underpaid players",
            destination: .rosterEvaluation,
            isRequired: true
        ),
        GameTask(
            title: "Check Salary Cap Outlook",
            description: "Review cap space projections and budget for upcoming free agency",
            destination: .rosterEvaluation,
            isRequired: false
        ),
        GameTask(
            title: "Set Roster Priorities",
            description: "Identify your biggest needs heading into the draft",
            destination: .rosterEvaluation,
            isRequired: false
        ),
    ]
}
```

Step 3: Add `.reviewRoster` case to the phase→tasks switch that calls `reviewRosterTasks()`.

---

### Task 4: Wire phase transitions in WeekAdvancer

**Files:**
- Modify: `Dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`

Step 1: In `phase(after:)`, insert reviewRoster:
```swift
case .freeAgency:   return .reviewRoster
case .reviewRoster: return .draft
```

Step 2: Add `.reviewRoster` case in `advanceWeek` switch if needed (or let it fall through to generic offseason advance).

Step 3: Generate inbox message when entering review roster phase:
"Time to evaluate your roster before the draft. Review position groups, contracts, and cap situation."

---

### Task 5: Update TODO.md

Mark #78 as complete.
