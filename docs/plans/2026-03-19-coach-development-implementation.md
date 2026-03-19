# Coach Development System — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace static coach attribute growth with a structured XP/potential system, add coaching hierarchy impact on player development, implement promotion pipeline, and HC-poaching mechanics.

**Architecture:** Extend existing `@Model Coach` with `potential`, `currentXP`, `promotedInSeason`, `mentorCoachID` properties. Create new `CoachDevelopmentEngine` for XP/growth logic. Modify `WeekAdvancer` to call weekly/seasonal development. Update `PlayerDevelopmentEngine` to use 4-layer coaching hierarchy. Update `CoachingEngine.checkCoordinatorPoaching` with HC-promotion mechanics.

**Tech Stack:** Swift, SwiftUI, SwiftData

---

## Impact Analysis

### Files to Modify

| File | Changes | Risk |
|------|---------|------|
| `Coach.swift` | Add 5 new properties | LOW — additive, SwiftData migration |
| `CoachRole.swift` | Add promotion paths, focus attributes | LOW — additive |
| `LeagueGenerator.swift` | Assign potential at generation | LOW — modify `generateCoach()` |
| `CoachingEngine.swift` | Replace `developCoach()`, update poaching, add hierarchy bonus | MEDIUM — core logic replacement |
| `PlayerDevelopmentEngine.swift` | Replace single coach bonus with 4-layer hierarchy | MEDIUM — affects player growth rates |
| `WeekAdvancer.swift` | Add weekly XP call, modify offseason development | MEDIUM — timing-critical |
| `CoachDetailView.swift` | Add development trajectory, promote/demote UI | LOW — UI only |
| `CoachingStaffView.swift` | Add coaching tree badge, adjustment indicator | LOW — UI only |
| `HireCoachView.swift` | Show fuzzy potential label | LOW — UI only |

### New Files to Create

| File | Purpose |
|------|---------|
| `Engine/PlayerDevelopment/CoachDevelopmentEngine.swift` | All XP, growth, potential, retirement logic |

### Files NOT Touched (confirmed safe)

- `PlaySimulator.swift` — coach schemes already passed in, no changes needed
- `DriveSimulator.swift` — same, scheme-based logic unchanged
- `GameSimulator.swift` — same, fetches coaches and passes to drive sim
- `FormationView.swift`, `RosterView.swift`, `PlayerDetailView.swift` — unrelated

---

## Task Breakdown

### Task 1: Extend Coach Model

**Files:**
- Modify: `dynasty/dynasty/Domain/Models/Coach/Coach.swift`

**Step 1: Add new properties to Coach**

```swift
// After existing properties (after moraleInfluence):

// Hidden potential (1-100) — determines attribute ceiling
var potential: Int = 50

// XP accumulator — converted to attribute growth at end of season
var currentXP: Int = 0

// Promotion tracking — season year when promoted; nil = no adjustment period
var promotedInSeason: Int?

// Coaching tree — mentor relationship
var mentorCoachID: UUID?
var mentorshipOrigin: String?  // e.g., "2025 Chicago Bears"
```

**Step 2: Add computed properties**

```swift
/// Attribute ceiling derived from potential
var attributeCeiling: Int {
    Int(Double(potential) * 0.65 + 35)  // potential 90 → 93, potential 50 → 67
}

/// Whether coach is in adjustment period after promotion
var isInAdjustmentPeriod: Bool {
    promotedInSeason != nil
}

/// Fuzzy potential label for UI (±10 noise initially, ±3 after 2+ seasons on team)
func potentialLabel(seasonsOnTeam: Int) -> String {
    let noise = seasonsOnTeam >= 2 ? Int.random(in: -3...3) : Int.random(in: -10...10)
    let displayed = min(99, max(1, potential + noise))
    switch displayed {
    case 85...99: return "Elite Ceiling"
    case 70...84: return "High Ceiling"
    case 55...69: return "Solid Ceiling"
    case 40...54: return "Limited Upside"
    default:      return "Low Ceiling"
    }
}
```

**Step 3: Update init to include potential**

Add `potential: Int = 50` parameter to the existing init.

**Step 4: Commit**

```
feat: add potential, XP, promotion tracking to Coach model
```

---

### Task 2: Add Role Focus Attributes and Promotion Paths to CoachRole

**Files:**
- Modify: `dynasty/dynasty/Domain/Enums/CoachRole.swift`

**Step 1: Add focus attributes per role**

```swift
/// Attributes that grow fastest for this role (weighted 2x in XP distribution)
var focusAttributes: [String] {
    switch self {
    case .headCoach:               return ["motivation", "discipline", "adaptability"]
    case .assistantHeadCoach:      return ["playerDevelopment", "motivation", "gamePlanning"]
    case .offensiveCoordinator:    return ["playCalling", "gamePlanning", "adaptability"]
    case .defensiveCoordinator:    return ["playCalling", "gamePlanning", "adaptability"]
    case .specialTeamsCoordinator: return ["playCalling", "discipline"]
    case .qbCoach:                 return ["playCalling", "playerDevelopment", "gamePlanning"]
    case .rbCoach, .wrCoach:       return ["playerDevelopment", "motivation"]
    case .olCoach, .dlCoach:       return ["playerDevelopment", "discipline"]
    case .lbCoach, .dbCoach:       return ["playerDevelopment", "gamePlanning"]
    case .strengthCoach:           return ["playerDevelopment", "discipline", "motivation"]
    case .teamDoctor, .physio:     return ["playerDevelopment"]
    }
}
```

**Step 2: Add promotion paths**

```swift
/// Roles this coach can be promoted to
var promotionTargets: [CoachRole] {
    switch self {
    case .qbCoach, .rbCoach, .wrCoach, .olCoach:
        return [.offensiveCoordinator]
    case .dlCoach, .lbCoach, .dbCoach:
        return [.defensiveCoordinator]
    case .strengthCoach:
        return [.specialTeamsCoordinator]
    case .offensiveCoordinator, .defensiveCoordinator:
        return [.assistantHeadCoach]
    case .specialTeamsCoordinator:
        return [.assistantHeadCoach]
    case .assistantHeadCoach:
        return [.headCoach]  // Only if player is GM-only mode
    default:
        return []
    }
}

/// Roles this coach can be demoted to
var demotionTargets: [CoachRole] {
    switch self {
    case .offensiveCoordinator:
        return [.qbCoach, .rbCoach, .wrCoach, .olCoach]
    case .defensiveCoordinator:
        return [.dlCoach, .lbCoach, .dbCoach]
    case .assistantHeadCoach:
        return [.offensiveCoordinator, .defensiveCoordinator]
    default:
        return []
    }
}
```

**Step 3: Commit**

```
feat: add focus attributes and promotion/demotion paths to CoachRole
```

---

### Task 3: Create CoachDevelopmentEngine

**Files:**
- Create: `dynasty/dynasty/Engine/PlayerDevelopment/CoachDevelopmentEngine.swift`

**Step 1: Create the engine with all core functions**

```swift
import Foundation

/// Handles coach XP accumulation, attribute growth, aging, retirement, and potential.
enum CoachDevelopmentEngine {

    // MARK: - Potential Generation

    /// Generate potential for a new coach based on age bracket.
    static func generatePotential(forAge age: Int) -> Int {
        switch age {
        case ...30:  return Int.random(in: 40...99)
        case 31...40: return Int.random(in: 45...90)
        case 41...50: return Int.random(in: 50...80)
        case 51...60: return Int.random(in: 40...70)
        default:      return Int.random(in: 30...60)
        }
    }

    // MARK: - Weekly XP

    /// Apply XP from a single game week.
    static func applyWeeklyXP(
        coach: Coach,
        didWin: Bool,
        isPlayoff: Bool,
        headCoach: Coach?,
        assistantHC: Coach?
    ) {
        var xp = 5  // Base weekly XP
        if didWin { xp += 3 }
        else { xp += 1 }
        if isPlayoff { xp += 8 }

        // HC mentoring multiplier (0.6x–1.5x) — PRIMARY LEVER
        let hcMultiplier: Double
        if let hc = headCoach, hc.id != coach.id {
            let leadership = Double(hc.motivation + hc.playerDevelopment) / 2.0
            hcMultiplier = 0.6 + (leadership - 30.0) / 60.0 * 0.9
        } else {
            hcMultiplier = 1.0  // HC doesn't mentor themselves
        }

        // AHC secondary bonus (0–20%)
        var ahcBonus = 0.0
        if let ahc = assistantHC, ahc.id != coach.id {
            ahcBonus = Double(ahc.playerDevelopment - 50) / 50.0 * 0.20
        }

        let totalMultiplier = max(0.3, hcMultiplier + ahcBonus)
        coach.currentXP += Int(Double(xp) * totalMultiplier)
    }

    // MARK: - Seasonal Development

    /// End-of-season: convert XP to attribute growth, apply aging, check retirement.
    static func applySeasonalDevelopment(
        coach: Coach,
        teamWins: Int,
        madePlayoffs: Bool,
        wonSuperBowl: Bool,
        headCoach: Coach?,
        assistantHC: Coach?
    ) {
        // 1. Add seasonal XP bonuses
        var seasonXP = 20  // Base
        if teamWins >= 9 { seasonXP += 15 }
        if madePlayoffs { seasonXP += 20 }
        if teamWins >= 12 { seasonXP += 30 }  // Conference championship caliber
        if wonSuperBowl { seasonXP += 60 }

        // HC multiplier on seasonal XP too
        let hcMult: Double
        if let hc = headCoach, hc.id != coach.id {
            let leadership = Double(hc.motivation + hc.playerDevelopment) / 2.0
            hcMult = 0.6 + (leadership - 30.0) / 60.0 * 0.9
        } else {
            hcMult = 1.0
        }
        coach.currentXP += Int(Double(seasonXP) * hcMult)

        // 2. Convert accumulated XP to attribute growth
        convertXPToGrowth(coach: coach)

        // 3. Age-based decline
        applyAgingDecline(coach: coach)

        // 4. Age the coach
        coach.age += 1
        coach.yearsExperience += 1

        // 5. Reputation based on wins (keep existing logic)
        applyReputationChange(coach: coach, teamWins: teamWins)

        // 6. Clear adjustment period if promoted 1+ seasons ago
        coach.promotedInSeason = nil

        // 7. Reset XP for next season
        coach.currentXP = 0
    }

    // MARK: - XP to Attribute Conversion

    private static func convertXPToGrowth(coach: Coach) {
        let ceiling = coach.attributeCeiling
        var remainingXP = coach.currentXP
        let focusAttrs = coach.role.focusAttributes

        // All 12 attribute names
        let allAttrs = [
            "playCalling", "playerDevelopment", "reputation", "adaptability",
            "gamePlanning", "scoutingAbility", "recruiting", "motivation",
            "discipline", "mediaHandling", "contractNegotiation", "moraleInfluence"
        ]

        // Build weighted pool: focus attributes get 2x weight
        var pool: [String] = []
        for attr in allAttrs {
            pool.append(attr)
            if focusAttrs.contains(attr) {
                pool.append(attr)  // Double weight
            }
        }

        // Attempt to spend XP on random attributes
        var attempts = 0
        while remainingXP > 0 && attempts < 20 {
            attempts += 1
            let attr = pool.randomElement()!
            let currentValue = coach.attributeValue(named: attr)

            guard currentValue < ceiling else { continue }

            let cost = 25 + Int(Double(currentValue) * 0.5)
            guard remainingXP >= cost else { break }

            remainingXP -= cost
            coach.setAttributeValue(named: attr, value: min(ceiling, currentValue + 1))
        }
    }

    // MARK: - Aging Decline

    static func applyAgingDecline(coach: Coach) {
        let age = coach.age
        guard age >= 50 else { return }

        let declineChance: Double
        let maxDecline: Int
        switch age {
        case 50...55: declineChance = 0.10; maxDecline = 1
        case 56...60: declineChance = 0.25; maxDecline = 2
        case 61...65: declineChance = 0.40; maxDecline = 2
        default:      declineChance = 0.60; maxDecline = 3
        }

        if Double.random(in: 0...1) < declineChance {
            let decline = Int.random(in: 1...maxDecline)
            coach.adaptability = max(1, coach.adaptability - decline)
            if age >= 56 {
                coach.playCalling = max(1, coach.playCalling - Int.random(in: 0...1))
            }
            if age >= 61 {
                coach.gamePlanning = max(1, coach.gamePlanning - Int.random(in: 0...1))
            }
        }
    }

    // MARK: - Retirement

    static func shouldRetire(coach: Coach) -> Bool {
        guard coach.age >= 65 else { return false }
        let baseChance = Double(coach.age - 64) * 0.15
        let reputationModifier = coach.reputation >= 80 ? 0.5 : 1.0
        return Double.random(in: 0...1) < (baseChance * reputationModifier)
    }

    // MARK: - Reputation

    private static func applyReputationChange(coach: Coach, teamWins: Int) {
        let change: Int
        switch teamWins {
        case 14...17: change = Int.random(in: 3...6)
        case 11...13: change = Int.random(in: 1...3)
        case 8...10:  change = Int.random(in: -1...1)
        case 5...7:   change = Int.random(in: -3...(-1))
        default:      change = Int.random(in: -6...(-3))
        }
        coach.reputation = min(99, max(1, coach.reputation + change))
    }

    // MARK: - Mentor Assignment

    static func setMentor(coach: Coach, headCoach: Coach?, teamName: String, season: Int) {
        guard let hc = headCoach, hc.id != coach.id else { return }
        if coach.mentorCoachID == nil {
            coach.mentorCoachID = hc.id
            coach.mentorshipOrigin = "\(season) \(teamName)"
        }
    }
}
```

**Step 2: Commit**

```
feat: create CoachDevelopmentEngine with XP, growth, aging, retirement
```

---

### Task 4: Add Helper Methods to Coach for Attribute Access by Name

**Files:**
- Modify: `dynasty/dynasty/Domain/Models/Coach/Coach.swift`

**Step 1: Add attributeValue(named:) and setAttributeValue(named:value:)**

```swift
/// Get attribute value by string name (for XP distribution)
func attributeValue(named name: String) -> Int {
    switch name {
    case "playCalling": return playCalling
    case "playerDevelopment": return playerDevelopment
    case "reputation": return reputation
    case "adaptability": return adaptability
    case "gamePlanning": return gamePlanning
    case "scoutingAbility": return scoutingAbility
    case "recruiting": return recruiting
    case "motivation": return motivation
    case "discipline": return discipline
    case "mediaHandling": return mediaHandling
    case "contractNegotiation": return contractNegotiation
    case "moraleInfluence": return moraleInfluence
    default: return 50
    }
}

/// Set attribute value by string name (for XP distribution)
func setAttributeValue(named name: String, value: Int) {
    switch name {
    case "playCalling": playCalling = value
    case "playerDevelopment": playerDevelopment = value
    case "reputation": reputation = value
    case "adaptability": adaptability = value
    case "gamePlanning": gamePlanning = value
    case "scoutingAbility": scoutingAbility = value
    case "recruiting": recruiting = value
    case "motivation": motivation = value
    case "discipline": discipline = value
    case "mediaHandling": mediaHandling = value
    case "contractNegotiation": contractNegotiation = value
    case "moraleInfluence": moraleInfluence = value
    default: break
    }
}
```

**Step 2: Commit**

```
feat: add Coach attribute access by name for XP distribution
```

---

### Task 5: Wire Potential into Coach Generation

**Files:**
- Modify: `dynasty/dynasty/Data/Import/LeagueGenerator.swift`
- Modify: `dynasty/dynasty/Engine/Simulation/CoachingEngine.swift`

**Step 1: In LeagueGenerator.generateCoach(), assign potential**

After generating age (around line 420), add:
```swift
let potential = CoachDevelopmentEngine.generatePotential(forAge: age)
```

Pass `potential: potential` to Coach init.

**Step 2: In CoachingEngine.generateCoachCandidates(), assign potential**

Same pattern — after generating age, call `CoachDevelopmentEngine.generatePotential(forAge:)`.

**Step 3: Commit**

```
feat: assign potential to coaches during generation
```

---

### Task 6: Replace developCoach() with XP System

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/CoachingEngine.swift`
- Modify: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`

**Step 1: In CoachingEngine, deprecate `developCoach()` or redirect it**

Replace the body of `developCoach(_:teamWins:)` (lines ~271-324) to call `CoachDevelopmentEngine.applySeasonalDevelopment()` instead:

```swift
static func developCoach(_ coach: Coach, teamWins: Int, headCoach: Coach? = nil, assistantHC: Coach? = nil, wonSuperBowl: Bool = false) {
    CoachDevelopmentEngine.applySeasonalDevelopment(
        coach: coach,
        teamWins: teamWins,
        madePlayoffs: teamWins >= 9,
        wonSuperBowl: wonSuperBowl,
        headCoach: headCoach,
        assistantHC: assistantHC
    )
}
```

**Step 2: In WeekAdvancer, add weekly XP after game simulation**

In `advanceRegularSeasonWeek()`, after the game simulation section (around line 250), add:

```swift
// Coach weekly XP accumulation
let playerTeamCoaches = allCoaches.filter { $0.teamID == career.teamID }
let hc = playerTeamCoaches.first { $0.role == .headCoach }
let ahc = playerTeamCoaches.first { $0.role == .assistantHeadCoach }
let playerTeamWon = // derive from game result
for coach in playerTeamCoaches {
    CoachDevelopmentEngine.applyWeeklyXP(
        coach: coach,
        didWin: playerTeamWon,
        isPlayoff: career.currentPhase == .playoffs,
        headCoach: hc,
        assistantHC: ahc
    )
}
```

**Step 3: In WeekAdvancer offseason (.coachingChanges), pass HC/AHC to developCoach**

Update the existing development loop to pass HC and AHC:

```swift
for team in teams {
    let teamCoaches = allCoaches.filter { $0.teamID == team.id }
    let hc = teamCoaches.first { $0.role == .headCoach }
    let ahc = teamCoaches.first { $0.role == .assistantHeadCoach }
    for coach in teamCoaches {
        CoachingEngine.developCoach(
            coach,
            teamWins: team.wins,
            headCoach: hc,
            assistantHC: ahc,
            wonSuperBowl: false  // TODO: track Super Bowl winner
        )
    }
}
```

**Step 4: Commit**

```
feat: replace random coach growth with XP-based development system
```

---

### Task 7: Implement 4-Layer Coaching Hierarchy for Player Development

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/CoachingEngine.swift`
- Modify: `dynasty/dynasty/Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift`

**Step 1: Add hierarchicalDevelopmentBonus() to CoachingEngine**

```swift
/// Calculate layered coaching bonus from HC → AHC → Coordinator → Position Coach
static func hierarchicalDevelopmentBonus(
    headCoach: Coach?,
    assistantHC: Coach?,
    coordinator: Coach?,
    positionCoach: Coach?,
    player: Player
) -> Double {
    var multiplier = 1.0

    // Layer 1: HC team-wide bonus
    if let hc = headCoach {
        let hcBonus = (Double(hc.motivation) - 50.0) / 50.0 * 0.08
        multiplier += hcBonus
        // Adjustment period penalty
        if hc.isInAdjustmentPeriod { multiplier -= 0.05 }
    }

    // Layer 2: AHC secondary bonus
    if let ahc = assistantHC {
        let ahcBonus = (Double(ahc.playerDevelopment) - 50.0) / 50.0 * 0.04
        multiplier += ahcBonus
    }

    // Layer 3: Coordinator unit bonus
    if let coord = coordinator {
        let coordBonus = (Double(coord.playerDevelopment) - 50.0) / 50.0 * 0.10
        multiplier += coordBonus
        if coord.isInAdjustmentPeriod { multiplier -= 0.03 }
    }

    // Layer 4: Position coach direct bonus
    if let pos = positionCoach {
        let posBonus = (Double(pos.playerDevelopment) - 50.0) / 50.0 * 0.15
        multiplier += posBonus
    }

    return max(0.5, min(1.8, multiplier))
}
```

**Step 2: Update PlayerDevelopmentEngine.developPlayer() to use hierarchy**

Replace the single position coach lookup (lines ~36-42) with:

```swift
// Find coaching chain for this player
let hc = coaches.first { $0.role == .headCoach }
let ahc = coaches.first { $0.role == .assistantHeadCoach }
let coordinator = coaches.first { coach in
    (player.position.side == .offense && coach.role == .offensiveCoordinator) ||
    (player.position.side == .defense && coach.role == .defensiveCoordinator) ||
    (player.position.side == .specialTeams && coach.role == .specialTeamsCoordinator)
}
let positionCoach = coaches.first { coach in
    CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: player.position)
}

// Apply hierarchical coaching bonus
let coachBonus = CoachingEngine.hierarchicalDevelopmentBonus(
    headCoach: hc,
    assistantHC: ahc,
    coordinator: coordinator,
    positionCoach: positionCoach,
    player: player
)
```

**Step 3: Commit**

```
feat: implement 4-layer coaching hierarchy for player development
```

---

### Task 8: Upgrade Coordinator Poaching to HC-Promotion System

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/CoachingEngine.swift`
- Modify: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`

**Step 1: Replace/enhance checkCoordinatorPoaching()**

Add HC-interview logic: coordinators with OVR 70+ get HC interview requests from other teams. Player CANNOT block HC interviews. Acceptance based on ambition, offering team prestige, and current team success.

```swift
/// Check if any coordinators receive HC interview requests (NFL-realistic poaching)
static func checkHCPoaching(
    coaches: [Coach],
    teamWins: Int,
    teamName: String
) -> [(coach: Coach, newTeamName: String)] {
    var poached: [(Coach, String)] = []

    let hcCandidates = coaches.filter { coach in
        [.offensiveCoordinator, .defensiveCoordinator, .assistantHeadCoach].contains(coach.role)
        && coach.overallRating >= 70
    }

    for coach in hcCandidates {
        // Base chance: higher OVR = more likely to get interviews
        var interviewChance = Double(coach.overallRating - 60) / 40.0 * 0.30

        // Winning teams' coaches are more attractive
        if teamWins >= 10 { interviewChance += 0.10 }
        if teamWins >= 13 { interviewChance += 0.10 }

        // But winning coaches are slightly less likely to leave
        if teamWins >= 11 { interviewChance -= 0.05 }

        // High motivation/ambition increases leaving chance
        interviewChance += Double(coach.motivation - 50) / 50.0 * 0.10

        if Double.random(in: 0...1) < max(0.0, interviewChance) {
            let fakeTeam = ["Arizona", "Atlanta", "Carolina", "Chicago",
                           "Cincinnati", "Cleveland", "Denver", "Detroit",
                           "Houston", "Jacksonville", "Las Vegas", "Miami",
                           "Minnesota", "New Orleans", "NY Giants", "Tennessee"].randomElement()!
            poached.append((coach, fakeTeam))
        }
    }

    return poached
}
```

**Step 2: Wire into WeekAdvancer offseason**

In the `.coachingChanges` section, call HC poaching and generate news/inbox messages.

**Step 3: Commit**

```
feat: upgrade coordinator poaching to NFL-realistic HC promotion system
```

---

### Task 9: Add Promotion/Demotion UI to CoachDetailView

**Files:**
- Modify: `dynasty/dynasty/UI/Staff/CoachDetailView.swift`

**Step 1: Add Promote button with role picker**

Show "Promote" button when `coach.role.promotionTargets` is non-empty. Opens sheet with role picker → salary negotiation.

**Step 2: Add Demote button with confirmation**

Show "Demote" button when `coach.role.demotionTargets` is non-empty. Confirmation alert warns about morale impact.

**Step 3: Add development trajectory section**

Show fuzzy potential label, "Improving"/"Plateaued"/"Declining" status, and mentorship info.

**Step 4: Commit**

```
feat: add promote/demote buttons and development trajectory to coach detail
```

---

### Task 10: Add Coaching Tree Badge and Adjustment Indicator

**Files:**
- Modify: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift`
- Modify: `dynasty/dynasty/UI/Staff/HireCoachView.swift`

**Step 1: In CoachingStaffView, show adjustment period badge**

For recently promoted coaches, show a small "Adjusting" badge on their card.

**Step 2: In HireCoachView, show fuzzy potential label**

Add a "Potential: High Ceiling" column or badge next to each candidate.

**Step 3: In CoachingStaffView, show coaching tree badge**

For HC, show "Coaching Tree: X coaches" badge if any mentees exist.

**Step 4: Commit**

```
feat: add adjustment badge, potential label, and coaching tree badge to UI
```

---

### Task 11: Coach Retirement System

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`
- Modify: `dynasty/dynasty/Engine/Media/NewsGenerator.swift`

**Step 1: In WeekAdvancer offseason, check retirement**

After seasonal development, iterate coaches 65+ and call `shouldRetire()`. Remove retired coaches and generate news.

**Step 2: Generate retirement inbox message**

If a player's team coach retires, send inbox message: "[Coach Name] announces retirement after [X] seasons."

**Step 3: Commit**

```
feat: implement coach retirement system with news generation
```

---

## Execution Order & Dependencies

```
Task 1 (Coach model) ──┐
Task 2 (CoachRole)   ──┤
Task 4 (Attr helpers) ──┼── Task 3 (Engine) ──┬── Task 5 (Generation)
                        │                     ├── Task 6 (XP system)
                        │                     ├── Task 7 (Hierarchy)
                        │                     ├── Task 8 (Poaching)
                        │                     └── Task 11 (Retirement)
                        │
                        └── Task 9 (Detail UI) ── Task 10 (Staff UI)
```

**Parallel-safe groups:**
- Group A: Tasks 1, 2, 4 (model changes — must be first)
- Group B: Task 3 (engine — depends on Group A)
- Group C: Tasks 5, 6, 7, 8, 11 (can run in parallel after B)
- Group D: Tasks 9, 10 (UI — can run in parallel after A)

---

## Risk Mitigation

| Risk | Mitigation |
|------|-----------|
| SwiftData migration crash from new Coach properties | All new properties have default values — lightweight migration |
| Player growth rates change dramatically | Keep total multiplier range 0.5–1.8 (vs current 0.8–1.5) |
| HC poaching feels unfair | Player gets compensatory draft pick + advance warning |
| XP math produces too-fast/too-slow growth | Tune `cost = 25 + currentValue * 0.5` formula; test with archetype scenarios |
| Adjustment period too punishing | 15% penalty for 1 season — noticeable but not devastating |

---

## Verification Checklist

After all tasks complete:
- [ ] New career: coaches have potential values assigned
- [ ] After 1 season: coach attributes change based on XP (not random)
- [ ] HC with high leadership develops coaches faster
- [ ] Player development affected by 4-layer hierarchy
- [ ] Coordinator with OVR 75+ gets HC interview in offseason
- [ ] Coach detail shows fuzzy potential label
- [ ] Promote button works: role changes, salary negotiates, vacancy created
- [ ] Coach 65+ can retire in offseason
- [ ] Build succeeds, no regressions in game simulation
