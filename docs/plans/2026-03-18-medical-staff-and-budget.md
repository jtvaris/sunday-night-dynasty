# Medical Staff & Dynamic Coaching Budget Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** (1) Add Doctor and Physio roles with a fatigue-injury system that makes medical staff meaningful for player health. (2) Make coaching budget dynamic, adjusting each offseason based on market size, owner satisfaction, and team success.

**Architecture:** Player already has `fatigue`, `isInjured`, `injuryWeeksRemaining` properties. CoachRole enum needs Doctor/Physio cases. Owner already has `coachingBudget` and `spendingWillingness`. Budget recalculation runs at season start in WeekAdvancer.

**Tech Stack:** Swift, SwiftUI, SwiftData

---

## Part A: Medical Staff (#79)

### Task 1: Add Doctor and Physio to CoachRole

**Files:**
- Modify: `Dynasty/dynasty/Domain/Enums/CoachRole.swift`

Add two new cases:
```swift
case teamDoctor
case physio
```

Add to `displayName`:
- `.teamDoctor` → "Team Doctor"
- `.physio` → "Physiotherapist"

Add to `sortOrder` (after strengthCoach).

Add to `abbreviation` and `badgeColor` following existing patterns.

---

### Task 2: Add Injury Types and Severity

**Files:**
- Create: `Dynasty/dynasty/Domain/Enums/InjuryType.swift`

```swift
enum InjuryType: String, Codable, CaseIterable {
    case hamstring = "Hamstring"
    case ankle = "Ankle Sprain"
    case knee = "Knee (MCL/ACL)"
    case shoulder = "Shoulder"
    case concussion = "Concussion"
    case back = "Back"
    case foot = "Foot"
    case groin = "Groin"
    case wrist = "Wrist/Hand"
    case ribs = "Ribs"

    var baseRecoveryWeeks: ClosedRange<Int> {
        switch self {
        case .hamstring:   return 1...4
        case .ankle:       return 1...6
        case .knee:        return 4...16
        case .shoulder:    return 2...8
        case .concussion:  return 1...3
        case .back:        return 2...6
        case .foot:        return 2...8
        case .groin:       return 1...4
        case .wrist:       return 1...4
        case .ribs:        return 1...4
        }
    }

    var severity: Int {  // 1-5 scale
        switch self {
        case .concussion, .hamstring, .groin, .wrist: return 1
        case .ankle, .back, .foot, .ribs:             return 2
        case .shoulder:                                return 3
        case .knee:                                    return 4
        }
    }
}
```

---

### Task 3: Add Injury Properties to Player

**Files:**
- Modify: `Dynasty/dynasty/Domain/Models/Player/Player.swift`

Add/update:
```swift
var injuryType: InjuryType?      // nil = healthy
var injuryWeeksOriginal: Int     // Total expected weeks out (for progress display)
```

Keep existing `isInjured`, `injuryWeeksRemaining`, `fatigue`.

---

### Task 4: Build Medical Staff Engine

**Files:**
- Create: `Dynasty/dynasty/Engine/Medical/MedicalEngine.swift`

```swift
enum MedicalEngine {

    /// Calculate injury risk for a play. Returns injury if one occurs, nil otherwise.
    static func injuryCheck(
        player: Player,
        playType: PlayType,
        doctor: Coach?,
        physio: Coach?
    ) -> InjuryType? {
        // Base risk: 0.5% per play
        var risk = 0.005

        // Fatigue increases risk (fatigue 80+ = 2x risk)
        risk *= 1.0 + Double(max(0, player.fatigue - 50)) / 50.0

        // Player durability reduces risk
        risk *= 1.0 - Double(player.physical.durability) / 200.0

        // Doctor prevention bonus (0-30% reduction)
        if let doc = doctor {
            risk *= 1.0 - Double(doc.playerDevelopment) / 330.0
        }

        // Roll
        guard Double.random(in: 0...1) < risk else { return nil }

        // Random injury type
        return InjuryType.allCases.randomElement()!
    }

    /// Calculate recovery weeks, modified by medical staff quality.
    static func recoveryWeeks(
        injury: InjuryType,
        physio: Coach?,
        doctor: Coach?
    ) -> Int {
        let base = Int.random(in: injury.baseRecoveryWeeks)

        var modifier = 1.0

        // Physio reduces recovery by up to 25%
        if let physio = physio {
            modifier -= Double(physio.playerDevelopment) / 400.0
        }

        // Doctor reduces by up to 15%
        if let doc = doctor {
            modifier -= Double(doc.playerDevelopment) / 660.0
        }

        return max(1, Int(Double(base) * modifier))
    }

    /// Weekly fatigue recovery, improved by physio.
    static func weeklyFatigueRecovery(player: Player, physio: Coach?) -> Int {
        var recovery = 15  // Base: recover 15 fatigue per week

        if let physio = physio {
            recovery += Int(Double(physio.playerDevelopment) / 10.0)  // Up to +10 extra
        }

        return recovery
    }
}
```

---

### Task 5: Wire Injury System into Game Simulation

**Files:**
- Modify: `Dynasty/dynasty/Engine/Simulation/PlaySimulator.swift`

Add optional doctor/physio params to simulatePlay(). After each play result, roll for injury on involved players. If injury occurs, set it on the PlayResult (may need to extend PlayResult with an optional injury field).

- Modify: `Dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`

In advanceRegularSeasonWeek(), after game simulation:
- Process injuries from game results
- Apply weekly fatigue recovery to all players
- Decrement injuryWeeksRemaining for injured players

---

### Task 6: Add Medical Staff to CoachingStaffView

**Files:**
- Modify: `Dynasty/dynasty/UI/Staff/CoachingStaffView.swift`

Add "Medical Staff" section showing Doctor and Physio roles (vacant or filled) following the same pattern as position coaches. Show their impact: "Reduces injury risk by X%" and "Speeds recovery by X%".

---

## Part B: Dynamic Coaching Budget (#80)

### Task 7: Create Budget Calculator

**Files:**
- Create: `Dynasty/dynasty/Engine/Budget/BudgetEngine.swift`

```swift
enum BudgetEngine {

    /// Recalculate coaching budget for a new season.
    static func calculateBudget(
        owner: Owner,
        team: Team,
        previousSeasonWins: Int,
        madePlayoffs: Bool
    ) -> Int {
        // Base from spending willingness: $12M-$35M
        let baseBudget = 12_000 + Int(Double(owner.spendingWillingness) / 99.0 * 23_000.0)

        // Market size modifier: +10% large, 0% medium, -10% small
        let marketModifier: Double = {
            switch team.mediaMarket {
            case .large:  return 1.10
            case .medium: return 1.0
            case .small:  return 0.90
            }
        }()

        // Success modifier: winning → owner spends more
        let successModifier: Double = {
            if madePlayoffs { return 1.15 }
            if previousSeasonWins >= 10 { return 1.08 }
            if previousSeasonWins >= 7 { return 1.0 }
            if previousSeasonWins >= 4 { return 0.95 }
            return 0.90  // Bad season = budget cut
        }()

        // Owner satisfaction modifier (from Career)
        // High satisfaction → willing to invest more
        let satisfactionModifier = 1.0  // Can be wired later from career.ownerSatisfaction

        let total = Double(baseBudget) * marketModifier * successModifier * satisfactionModifier
        return max(10_000, Int(total))  // Floor of $10M
    }
}
```

---

### Task 8: Wire Budget Recalculation into Season Start

**Files:**
- Modify: `Dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`

In `startNewSeason()` or the equivalent offseason transition, recalculate each team's coaching budget:

```swift
// Recalculate coaching budgets for new season
for team in teams {
    if let owner = team.owner {
        owner.coachingBudget = BudgetEngine.calculateBudget(
            owner: owner,
            team: team,
            previousSeasonWins: team.wins,
            madePlayoffs: team.madePlayoffs  // Check if this property exists
        )
    }
}
```

---

### Task 9: Show Budget Changes in UI

**Files:**
- Modify: `Dynasty/dynasty/UI/Staff/CoachingStaffView.swift`

In the budget header section, add context showing how budget changed:
- "Budget: $28.5M (+$2.5M from last season)"
- Color code: green for increase, red for decrease
- Tooltip: "Strong season performance increased owner's investment"

---

### Task 10: Update TODO.md

Mark #79, #80, and #57 as complete.
