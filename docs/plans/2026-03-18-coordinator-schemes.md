# Coordinator Schemes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wire the existing scheme system into game simulation so schemes actually affect play outcomes, and build an interactive Schemes tab where players can view roster-scheme compatibility.

**Architecture:** The scheme system already has enums (8 offensive + 7 defensive), Coach model properties, and a `CoachingEngine.schemeFit()` calculation. What's missing is: (1) scheme influence on `PlaySimulator.decidePlayCall()` and play outcomes, (2) scheme fit bonus/penalty in `GameSimulator`, and (3) interactive UI showing player-scheme compatibility matrix.

**Tech Stack:** Swift, SwiftUI, SwiftData

---

### Task 1: Wire Scheme into PlaySimulator.decidePlayCall()

**Files:**
- Modify: `Dynasty/dynasty/Engine/Simulation/PlaySimulator.swift`

**Step 1: Add scheme parameters to simulatePlay()**

Add `offensiveScheme: OffensiveScheme?` and `defensiveScheme: DefensiveScheme?` parameters to `simulatePlay()` and pass `offensiveScheme` to `decidePlayCall()`.

```swift
static func simulatePlay(
    offensePlayers: [Player],
    defensePlayers: [Player],
    down: Int,
    distance: Int,
    yardLine: Int,
    quarter: Int,
    timeRemaining: Int,
    momentum: Double,
    playNumber: Int,
    offensiveScheme: OffensiveScheme? = nil,
    defensiveScheme: DefensiveScheme? = nil
) -> PlayResult {
```

**Step 2: Make decidePlayCall() scheme-aware**

Add `offensiveScheme: OffensiveScheme? = nil` parameter. Adjust pass/run ratios based on scheme:

```swift
// After existing down/distance logic, apply scheme bias
let schemePassBias: Double = {
    guard let scheme = offensiveScheme else { return 0.0 }
    switch scheme {
    case .airRaid:    return 0.15   // Heavy pass
    case .westCoast:  return 0.08   // Pass-leaning
    case .proPassing: return 0.10   // Pass-leaning
    case .spread:     return 0.05   // Slight pass
    case .powerRun:   return -0.15  // Heavy run
    case .shanahan:   return -0.10  // Run-leaning
    case .option:     return -0.12  // Run-leaning
    case .rpo:        return 0.0    // Balanced
    }
}()
// Apply: base pass chance + schemePassBias
```

**Step 3: Add scheme fit bonus to play outcome calculations**

In `simulatePassPlay()` and `simulateRunPlay()`, add a scheme fit modifier that boosts player effectiveness when scheme fit is high:

```swift
// Calculate average scheme fit for offensive players
let avgSchemeFit = offensePlayers.reduce(0.0) { sum, player in
    sum + CoachingEngine.schemeFit(player: player, offensiveScheme: offensiveScheme, defensiveScheme: nil)
} / max(1.0, Double(offensePlayers.count))

// Scheme fit modifier: -5% to +10% on yards gained
let schemeModifier = (avgSchemeFit - 0.5) * 0.3
```

Apply `schemeModifier` to yard calculations in both pass and run plays.

**Step 4: Same for defensive scheme**

In `simulatePassPlay()` and `simulateRunPlay()`, calculate defensive scheme fit and apply as a penalty to the offense (or bonus to defense):

```swift
let defSchemeFit = defensePlayers.reduce(0.0) { sum, player in
    sum + CoachingEngine.schemeFit(player: player, offensiveScheme: nil, defensiveScheme: defensiveScheme)
} / max(1.0, Double(defensePlayers.count))
let defSchemeModifier = (defSchemeFit - 0.5) * 0.2  // Defense scheme fit reduces offensive yards
```

---

### Task 2: Wire Scheme into GameSimulator

**Files:**
- Modify: `Dynasty/dynasty/Engine/Simulation/GameSimulator.swift`
- Modify: `Dynasty/dynasty/Engine/Simulation/DriveSimulator.swift` (if it calls PlaySimulator)

**Step 1: Extract team schemes from coaches**

In `GameSimulator.simulate()`, extract each team's offensive and defensive schemes from their coaching staff:

```swift
let homeOC = homeTeam.players.isEmpty ? nil : homeTeam.coaches?.first { $0.role == .offensiveCoordinator }
let homeDC = homeTeam.coaches?.first { $0.role == .defensiveCoordinator }
let homeOffScheme = homeOC?.offensiveScheme
let homeDefScheme = homeDC?.defensiveScheme
// Same for away team
```

Note: Check how coaches are accessed from Team model — may need to query via modelContext or pass coaches as parameter.

**Step 2: Pass schemes through to PlaySimulator calls**

Every call to `PlaySimulator.simulatePlay()` must now include the offense's `offensiveScheme` and the defense's `defensiveScheme`:

```swift
PlaySimulator.simulatePlay(
    offensePlayers: offensiveStarters,
    defensePlayers: defensiveStarters,
    // ... existing params ...
    offensiveScheme: isHomePossession ? homeOffScheme : awayOffScheme,
    defensiveScheme: isHomePossession ? awayDefScheme : homeDefScheme
)
```

---

### Task 3: Scheme Selection UI — Enhance Schemes Tab

**Files:**
- Modify: `Dynasty/dynasty/UI/Staff/CoachingStaffView.swift` (Schemes tab section)

**Step 1: Add roster compatibility matrix**

Replace the placeholder Schemes tab with an interactive view showing:

```
┌─────────────────────────────────────┐
│ OFFENSIVE SCHEME: West Coast        │
│ OC: John Smith                      │
│                                     │
│ Player Fit Analysis:                │
│ ✦ P. Mahomes  QB   92% ████████▓░  │
│ ✦ D. Henry    RB   65% ██████░░░░  │
│ ✦ J. Chase    WR   88% ████████░░  │
│ ✦ T. Kelce    TE   78% ███████░░░  │
│ ...                                 │
│                                     │
│ Avg Fit: 78%  [Good]               │
│                                     │
│ ─────────────────────────────────── │
│ DEFENSIVE SCHEME: Cover 3           │
│ DC: Jane Doe                        │
│                                     │
│ Player Fit Analysis:                │
│ ✦ M. Garrett  DE   85% ████████░░  │
│ ...                                 │
└─────────────────────────────────────┘
```

**Step 2: Build SchemeRosterFitView**

Create a reusable view that takes a scheme + players array and shows:
- Each player's name, position, scheme fit % as colored bar
- Average fit for the group
- Color coding: 80%+ green, 60-79% gold, below 60% red

```swift
private func schemeRosterFitSection(
    title: String,
    scheme: String,
    coordinatorName: String?,
    players: [Player],
    offensiveScheme: OffensiveScheme?,
    defensiveScheme: DefensiveScheme?
) -> some View {
    // ... card with player fit bars
}
```

**Step 3: Show scheme impact summary**

At the bottom of the Schemes tab, add a "Scheme Impact" card explaining:
- "Your offensive scheme affects play calling tendencies"
- "Players with high scheme fit perform better in games"
- "Players with high scheme fit develop faster in the offseason"

---

### Task 4: Build Scheme Selection View (TODO #67)

**Files:**
- Create: `Dynasty/dynasty/UI/Staff/SchemeSelectionView.swift`
- Modify: `Dynasty/dynasty/UI/Staff/CoachingStaffView.swift` (link to selection)

**Step 1: Create SchemeSelectionView**

This view allows changing a coordinator's scheme (within reason). Present as a sheet from the Schemes tab:

```swift
struct SchemeSelectionView: View {
    let coordinator: Coach
    let players: [Player]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(OffensiveScheme.allCases, id: \.self) { scheme in
                    SchemeOptionRow(
                        scheme: scheme,
                        isSelected: coordinator.offensiveScheme == scheme,
                        avgFit: averageFit(for: scheme),
                        onSelect: { selectScheme(scheme) }
                    )
                }
            }
            .navigationTitle("Select Scheme")
        }
    }
}
```

Each row shows: scheme name, description, average roster fit %, and visual indicator.

**Step 2: Add "Change Scheme" button to Schemes tab**

In CoachingStaffView's Schemes tab, add a button next to each coordinator's scheme card:

```swift
Button("Change Scheme") {
    showSchemeSelection = true
}
```

Present SchemeSelectionView as a sheet.

**Step 3: Coordinator aptitude affects scheme effectiveness**

When displaying schemes, show how well the coordinator runs each scheme based on their attributes. A coordinator's `playCalling` and `adaptability` determine how effectively they can switch schemes mid-career.

---

### Task 5: Update TODO.md

**Files:**
- Modify: `docs/TODO.md`

Mark #76 and #67 as complete.
