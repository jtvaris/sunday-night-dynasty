# Franchise Tag & Player Evaluation Phase Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a dedicated Franchise Tag view where users can tag expiring-contract players before free agency, and enhance the Review Roster phase with evaluation-focused tasks including franchise tag decisions.

**Architecture:** Contract model already has `franchiseTagged: Bool` and ContractEngine has `franchiseTagValue()`. Need: (1) FranchiseTagView — dedicated listing of expiring players with tag/untag actions, budget warnings, and cap impact preview, (2) enhance ReviewRoster tasks to include franchise tag task, (3) wire franchise tag into free agency (tagged players don't become free agents).

**Tech Stack:** Swift, SwiftUI, SwiftData

---

### Task 1: Create FranchiseTagView

**Files:**
- Create: `dynasty/dynasty/UI/Contracts/FranchiseTagView.swift`

A dedicated view showing all players with expiring contracts (contractYearsRemaining <= 1) with the ability to apply franchise tags.

**Layout:**
```
┌─────────────────────────────────────────┐
│ FRANCHISE TAG DECISIONS                  │
│ Cap Space: $45.2M available             │
│ ─────────────────────────────────────── │
│                                         │
│ ⚠️ You can apply up to 1 franchise tag  │
│    and 1 transition tag per season.     │
│                                         │
│ EXPIRING CONTRACTS (12 players)         │
│                                         │
│ ★ J. Chase  WR  92 OVR  $18.5M/yr     │
│   Tag Cost: $22.1M │ [Apply Tag]       │
│   "Elite player — strongly consider"    │
│                                         │
│ ★ D. Henry  RB  84 OVR  $12.0M/yr     │
│   Tag Cost: $14.8M │ [Apply Tag]       │
│   "Aging veteran — tag cost may not     │
│    be worth it at 30 years old"         │
│                                         │
│ ... more players ...                    │
│                                         │
│ ─────────────────────────────────────── │
│ TAGGED PLAYERS                          │
│ ★ [tagged player] — [Remove Tag]       │
│                                         │
│ Cap Impact: +$22.1M if tag applied      │
│ Remaining Cap: $23.1M                   │
└─────────────────────────────────────────┘
```

**Key features:**
- List all players where `contractYearsRemaining <= 1` for player's team
- Show each player: name, position, age, OVR, current salary, tag cost
- Tag cost from `ContractEngine.franchiseTagValue()` — needs top 5 salaries at that position league-wide
- Smart recommendation per player: "Elite — strongly consider", "Aging — may not be worth it", "Role player — better to let walk"
- Cap impact preview: show remaining cap if tag applied
- Warning if tag would put team over cap
- NFL rules: max 1 franchise tag + 1 transition tag per team per season
- Tagged section at bottom showing currently tagged players with remove option

**Data flow:**
```swift
struct FranchiseTagView: View {
    let career: Career
    @Environment(\.modelContext) private var modelContext
    @Query private var allPlayers: [Player]
    @Query private var allContracts: [Contract]

    private var expiringPlayers: [Player] {
        allPlayers.filter { $0.teamID == career.teamID && $0.contractYearsRemaining <= 1 }
            .sorted { $0.overall > $1.overall }
    }
}
```

---

### Task 2: Implement Tag/Untag Logic

**Files:**
- Modify: `dynasty/dynasty/Engine/Contract/ContractEngine.swift`

Add:
```swift
/// Apply franchise tag to a player. Creates a 1-year contract at the tag value.
static func applyFranchiseTag(
    player: Player,
    position: Position,
    allPlayers: [Player],
    modelContext: ModelContext
) {
    // Calculate tag value (avg of top 5 salaries at position)
    let positionPlayers = allPlayers.filter { $0.position == position }
    let topSalaries = positionPlayers.map { $0.annualSalary }.sorted(by: >).prefix(5)
    let tagValue = topSalaries.isEmpty ? 15_000 : Array(topSalaries).reduce(0, +) / topSalaries.count

    // Set player contract to 1-year tag value
    player.contractYearsRemaining = 1
    player.annualSalary = tagValue
    player.isFranchiseTagged = true  // Need to add this property
}

/// Remove franchise tag from a player.
static func removeFranchiseTag(player: Player) {
    player.isFranchiseTagged = false
    player.contractYearsRemaining = 0  // Back to expiring
}
```

---

### Task 3: Add isFranchiseTagged to Player Model

**Files:**
- Modify: `dynasty/dynasty/Domain/Models/Player/Player.swift`

Add:
```swift
var isFranchiseTagged: Bool = false
```

This is simpler than using the Contract model's `franchiseTagged` since not all players use realistic contracts.

---

### Task 4: Wire Franchise Tag into Free Agency

**Files:**
- Modify: `dynasty/dynasty/Engine/Contract/FreeAgencyEngine.swift`

In the free agent market generation, exclude franchise-tagged players:
```swift
// Existing filter: contractYearsRemaining == 0
// Add: && !player.isFranchiseTagged
let freeAgents = players.filter { $0.contractYearsRemaining == 0 && !$0.isFranchiseTagged }
```

---

### Task 5: Add Navigation & Task Destination

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift`
- Modify: `dynasty/dynasty/UI/Career/CareerShellView.swift`

Add `case franchiseTag` to TaskDestination enum.
Add `case franchiseTag` to ShellDestination enum.
Add navigation handler routing to FranchiseTagView.

---

### Task 6: Enhance Review Roster Tasks

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift`

Update `reviewRosterTasks()` to include franchise tag task:

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
            title: "Franchise Tag Decisions",
            description: "Apply franchise tag to keep key players from hitting free agency",
            destination: .franchiseTag,
            isRequired: true
        ),
        GameTask(
            title: "Check Salary Cap Outlook",
            description: "Review cap space projections and budget for upcoming free agency",
            destination: .capOverview,
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

---

### Task 7: Place Phase Correctly — Before Free Agency

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`

Current order: `coachingChanges → combine → freeAgency → reviewRoster → draft`

The franchise tag window should be BEFORE free agency (that's how NFL works). The reviewRoster phase is already after freeAgency, but franchise tags need to happen before. Two options:
- Move reviewRoster before freeAgency
- Or keep reviewRoster where it is and make franchise tag available during it

**Best approach:** Move reviewRoster to BEFORE freeAgency:
```
coachingChanges → combine → reviewRoster → freeAgency → draft
```

This matches the NFL calendar: evaluate roster → tag players → free agency opens → draft.

Update `phase(after:)`:
```swift
case .combine:       return .reviewRoster
case .reviewRoster:  return .freeAgency
case .freeAgency:    return .draft
```

---

### Task 8: Reset Franchise Tags at Season End

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`

In `startNewSeason()`, reset all franchise tags:
```swift
// Reset franchise tags from previous season
for player in allPlayers where player.isFranchiseTagged {
    player.isFranchiseTagged = false
}
```
