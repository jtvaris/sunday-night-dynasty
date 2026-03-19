# Position Versatility & Scheme Learning Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add persistent position versatility (players can learn alternate positions with varying proficiency that develops over time) and scheme learning (players learn schemes gradually, affected by coach expertise and teaching ability), creating deep strategic gameplay where roster decisions have long-term consequences.

**Architecture:** Extend the Player model with `positionFamiliarity` (dict of Position→Int 0-100) and `schemeFamiliarity` (dict of scheme→Int 0-100). Extend Coach with `schemeExpertise` (dict of scheme→Int 0-100). Wire into PlayerDevelopmentEngine for offseason/weekly growth, and into PlaySimulator/CoachingEngine for game-day performance impact. Leverage existing VersatilityEngine ratings as the ceiling for position learning. Connect to existing DepthChartView training UI.

**Tech Stack:** Swift, SwiftUI, SwiftData

---

### Task 1: Add Position Familiarity to Player Model

**Files:**
- Modify: `dynasty/dynasty/Domain/Models/Player/Player.swift`

Add these properties to the Player @Model class:

```swift
/// Position familiarity: how well this player knows each position (0-100).
/// Primary position starts at 100. Alternate positions start based on
/// VersatilityEngine rating and grow through training/playing time.
/// Key: Position.rawValue, Value: 0-100 proficiency
var positionFamiliarity: [String: Int] = [:]

/// Scheme familiarity: how well this player knows each scheme (0-100).
/// Starts based on previous team's scheme. Grows through practice and games.
/// Key: scheme rawValue (e.g., "westCoast"), Value: 0-100
var schemeFamiliarity: [String: Int] = [:]

/// The alternate position currently being trained (if any).
/// Training focuses development points toward this position.
var trainingPosition: Position?
```

Note: Use `[String: Int]` instead of `[Position: Int]` because SwiftData requires Codable-friendly dictionary keys.

Add computed helpers:

```swift
/// Get familiarity for a specific position (defaults to 0, primary is always 100)
func familiarity(at position: Position) -> Int {
    if position == self.position { return 100 }
    return positionFamiliarity[position.rawValue] ?? 0
}

/// Get familiarity for a specific scheme
func schemeFamiliarity(for scheme: String) -> Int {
    return schemeFamiliarity[scheme] ?? 0
}
```

**Initialize primary position on creation:** In LeagueGenerator or wherever players are created, set `positionFamiliarity[player.position.rawValue] = 100`.

Also set initial scheme familiarity based on the team they start on — find the OC/DC and set their scheme familiarity to 60-80 (random, representing "grew up in this system").

---

### Task 2: Add Scheme Expertise to Coach Model

**Files:**
- Modify: `dynasty/dynasty/Domain/Models/Coach/Coach.swift`

Add:

```swift
/// Scheme expertise: how well this coach knows/teaches each scheme (0-100).
/// Primary scheme starts at 80-95. Related schemes start at 40-60.
/// Key: scheme rawValue, Value: 0-100
var schemeExpertise: [String: Int] = [:]
```

Add computed helper:

```swift
/// Get expertise for a specific scheme
func expertise(for scheme: String) -> Int {
    return schemeExpertise[scheme] ?? 20  // Baseline 20 for unknown schemes
}
```

**Initialize on coach generation:** In CoachingEngine.generateCoachCandidates():
- Primary scheme: 75-95 expertise
- Same "family" schemes (e.g., Air Raid & West Coast are both passing): 45-65
- Unrelated schemes: 15-35
- `adaptability` attribute modifies the floor (high adaptability = higher baseline)

Scheme families:
- **Passing family**: westCoast, airRaid, proPassing, spread
- **Run family**: powerRun, shanahan, option, rpo
- **Man defense family**: pressMan, base43
- **Zone defense family**: cover3, tampa2, base34
- **Flex defense family**: multiple, hybrid

---

### Task 3: Create Versatility & Scheme Development Engine

**Files:**
- Create: `dynasty/dynasty/Engine/PlayerDevelopment/VersatilityDevelopmentEngine.swift`

```swift
enum VersatilityDevelopmentEngine {

    // MARK: - Position Training (called weekly during season, daily during OTAs/camp)

    /// Develop a player's alternate position familiarity.
    /// Returns the familiarity points gained this cycle.
    static func trainPosition(
        player: Player,
        targetPosition: Position,
        positionCoach: Coach?,
        practiceIntensity: Double = 1.0  // 0.5 during season, 1.0 during offseason
    ) -> Int {
        // Base learning rate: 1-3 points per cycle
        var learningRate: Double = 2.0

        // Player coachability affects learning speed
        learningRate *= Double(player.mental.coachability) / 70.0

        // Coach teaching ability (playerDevelopment attribute)
        if let coach = positionCoach {
            learningRate *= Double(coach.playerDevelopment) / 60.0
        }

        // VersatilityEngine ceiling: natural=100, accomplished=85, competent=65,
        // unconvincing=40, unqualified=15
        let ceiling = versatilityCeiling(player: player, at: targetPosition)
        let current = player.familiarity(at: targetPosition)

        // Diminishing returns as approaching ceiling
        let headroom = Double(ceiling - current) / Double(ceiling)
        learningRate *= max(0.1, headroom)

        // Practice intensity (season vs offseason)
        learningRate *= practiceIntensity

        // Age penalty (older players learn slower)
        if player.age > 30 { learningRate *= 0.7 }
        else if player.age > 28 { learningRate *= 0.85 }

        return max(0, Int(learningRate.rounded()))
    }

    /// The maximum familiarity a player can reach at a given position,
    /// based on their physical attributes and VersatilityEngine rating.
    static func versatilityCeiling(player: Player, at position: Position) -> Int {
        let rating = VersatilityEngine.rate(player: player, at: position)
        switch rating {
        case .natural:      return 100
        case .accomplished: return 85
        case .competent:    return 65
        case .unconvincing: return 40
        case .unqualified:  return 15
        }
    }

    // MARK: - Scheme Learning (called weekly)

    /// Develop a player's scheme familiarity.
    static func learnScheme(
        player: Player,
        scheme: String,
        coordinator: Coach?,
        practiceIntensity: Double = 1.0
    ) -> Int {
        var learningRate: Double = 1.5

        // Player coachability
        learningRate *= Double(player.mental.coachability) / 70.0

        // Coach's expertise IN THIS SPECIFIC SCHEME drives teaching quality
        if let coord = coordinator {
            let expertise = Double(coord.expertise(for: scheme))
            learningRate *= expertise / 60.0

            // Coach's playerDevelopment = general teaching ability
            learningRate *= Double(coord.playerDevelopment) / 70.0
        }

        // Diminishing returns near 100
        let current = Double(player.schemeFamiliarity(for: scheme))
        let headroom = (100.0 - current) / 100.0
        learningRate *= max(0.1, headroom)

        // Practice intensity
        learningRate *= practiceIntensity

        // Player awareness helps scheme comprehension
        learningRate *= Double(player.mental.awareness) / 70.0

        return max(0, Int(learningRate.rounded()))
    }

    // MARK: - Game Performance Impact

    /// Returns a 0.0-1.0 modifier for how well a player performs at a
    /// non-primary position during a game.
    static func positionPerformanceModifier(player: Player, playingAt position: Position) -> Double {
        let familiarity = Double(player.familiarity(at: position))
        // 100 familiarity = 1.0 (full performance)
        // 50 familiarity = 0.85 (15% penalty)
        // 0 familiarity = 0.65 (35% penalty)
        return 0.65 + (familiarity / 100.0) * 0.35
    }

    /// Returns a 0.0-1.0 modifier for how well a player performs in
    /// a specific scheme during a game.
    static func schemePerformanceModifier(player: Player, scheme: String) -> Double {
        let familiarity = Double(player.schemeFamiliarity(for: scheme))
        // 100 = 1.0, 50 = 0.85, 0 = 0.70
        return 0.70 + (familiarity / 100.0) * 0.30
    }
}
```

Note: Make VersatilityEngine (currently private in PositionVersatilityView.swift) accessible by moving it or making it internal.

---

### Task 4: Make VersatilityEngine Accessible

**Files:**
- Modify: `dynasty/dynasty/UI/Roster/PositionVersatilityView.swift`

Change `private enum VersatilityEngine` to `enum VersatilityEngine` (remove private).

This allows VersatilityDevelopmentEngine and DepthChartView (which already uses it) to access the rating system from outside the file.

Alternatively, extract VersatilityEngine to its own file: `dynasty/dynasty/Engine/PlayerDevelopment/VersatilityEngine.swift`.

---

### Task 5: Wire into PlayerDevelopmentEngine

**Files:**
- Modify: `dynasty/dynasty/Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift`

In `developPlayer()`, after the existing development logic, add:

```swift
// --- Position Training ---
if let trainingPos = player.trainingPosition, trainingPos != player.position {
    let posCoach = coaches.first { coach in
        CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: trainingPos)
    }
    let posGain = VersatilityDevelopmentEngine.trainPosition(
        player: player,
        targetPosition: trainingPos,
        positionCoach: posCoach,
        practiceIntensity: 1.0  // offseason = full intensity
    )
    let key = trainingPos.rawValue
    let current = player.positionFamiliarity[key] ?? 0
    let ceiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: trainingPos)
    player.positionFamiliarity[key] = min(ceiling, current + posGain)
}

// --- Scheme Learning ---
// Find active schemes from coordinators
let oc = coaches.first { $0.role == .offensiveCoordinator }
let dc = coaches.first { $0.role == .defensiveCoordinator }

if let offScheme = oc?.offensiveScheme {
    let gain = VersatilityDevelopmentEngine.learnScheme(
        player: player,
        scheme: offScheme.rawValue,
        coordinator: oc,
        practiceIntensity: 1.0
    )
    let current = player.schemeFamiliarity[offScheme.rawValue] ?? 0
    player.schemeFamiliarity[offScheme.rawValue] = min(100, current + gain)
}

if let defScheme = dc?.defensiveScheme {
    let gain = VersatilityDevelopmentEngine.learnScheme(
        player: player,
        scheme: defScheme.rawValue,
        coordinator: dc,
        practiceIntensity: 1.0
    )
    let current = player.schemeFamiliarity[defScheme.rawValue] ?? 0
    player.schemeFamiliarity[defScheme.rawValue] = min(100, current + gain)
}
```

---

### Task 6: Wire into Game Simulation (PlaySimulator)

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/PlaySimulator.swift`

In `schemeFitModifier()` (or wherever scheme fit is calculated for play outcomes), multiply the existing scheme fit by the player's scheme performance modifier:

```swift
// Existing scheme fit from CoachingEngine
let baseFit = CoachingEngine.schemeFit(player: p, offensiveScheme: offScheme, defensiveScheme: defScheme)

// Modify by scheme familiarity
let schemeName = (p.position.side == .offense) ? offScheme?.rawValue : defScheme?.rawValue
let schemeModifier = schemeName.map {
    VersatilityDevelopmentEngine.schemePerformanceModifier(player: p, scheme: $0)
} ?? 1.0

let effectiveFit = baseFit * schemeModifier
```

Also apply position performance modifier for players playing out of position (check via DepthChart if they're in a slot that doesn't match their primary position).

---

### Task 7: Wire into WeekAdvancer for Weekly Learning

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`

In `advanceRegularSeasonWeek()`, after game simulation, add weekly scheme learning and position training for the player's team:

```swift
// Weekly scheme learning and position training (during season)
if let playerTeamID = career.teamID {
    let teamPlayers = allPlayers.filter { $0.teamID == playerTeamID }
    let teamCoaches = allCoaches.filter { $0.teamID == playerTeamID }
    let oc = teamCoaches.first { $0.role == .offensiveCoordinator }
    let dc = teamCoaches.first { $0.role == .defensiveCoordinator }

    for player in teamPlayers {
        // Scheme learning (reduced intensity during season)
        if let offScheme = oc?.offensiveScheme, player.position.side == .offense {
            let gain = VersatilityDevelopmentEngine.learnScheme(
                player: player, scheme: offScheme.rawValue,
                coordinator: oc, practiceIntensity: 0.5
            )
            let key = offScheme.rawValue
            player.schemeFamiliarity[key] = min(100, (player.schemeFamiliarity[key] ?? 0) + gain)
        }
        if let defScheme = dc?.defensiveScheme, player.position.side == .defense {
            let gain = VersatilityDevelopmentEngine.learnScheme(
                player: player, scheme: defScheme.rawValue,
                coordinator: dc, practiceIntensity: 0.5
            )
            let key = defScheme.rawValue
            player.schemeFamiliarity[key] = min(100, (player.schemeFamiliarity[key] ?? 0) + gain)
        }

        // Position training (reduced during season)
        if let trainingPos = player.trainingPosition {
            let posCoach = teamCoaches.first { coach in
                CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: trainingPos)
            }
            let gain = VersatilityDevelopmentEngine.trainPosition(
                player: player, targetPosition: trainingPos,
                positionCoach: posCoach, practiceIntensity: 0.3
            )
            let key = trainingPos.rawValue
            let ceiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: trainingPos)
            player.positionFamiliarity[key] = min(ceiling, (player.positionFamiliarity[key] ?? 0) + gain)
        }
    }
}
```

---

### Task 8: Connect PositionVersatilityView Training UI

**Files:**
- Modify: `dynasty/dynasty/UI/Roster/PositionVersatilityView.swift`

Connect the existing "Train" buttons (currently unconnected) to set `player.trainingPosition`:

```swift
// In the train alert confirmation action:
player.trainingPosition = trainTargetPosition
try? modelContext.save()
```

Add visual indicators:
- Show current familiarity % next to each alternate position
- Show ceiling (from VersatilityEngine rating) as max bar
- Show "Training..." badge on the currently trained position
- Show scheme familiarity in a separate section

Also add scheme familiarity display to the player detail view:
- Current team's offensive scheme: XX% familiar
- Current team's defensive scheme: XX% familiar

---

### Task 9: Initialize Familiarity for Existing Players

**Files:**
- Modify: `dynasty/dynasty/Data/Import/LeagueGenerator.swift`

When generating players, initialize:

```swift
// Set primary position familiarity to 100
player.positionFamiliarity[player.position.rawValue] = 100

// Set some random secondary position familiarity for veterans
if player.yearsPro >= 3 {
    let viablePositions = VersatilityEngine.viablePositions(for: player)
    for (pos, rating) in viablePositions where rating >= .unconvincing && pos != player.position {
        let maxFam = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: pos)
        let startFam = Int.random(in: 10...min(maxFam, 20 + player.yearsPro * 5))
        player.positionFamiliarity[pos.rawValue] = startFam
    }
}

// Set scheme familiarity from team's current scheme
if let oc = teamCoaches.first(where: { $0.role == .offensiveCoordinator }),
   let scheme = oc.offensiveScheme, player.position.side == .offense {
    player.schemeFamiliarity[scheme.rawValue] = Int.random(in: 55...85)
}
if let dc = teamCoaches.first(where: { $0.role == .defensiveCoordinator }),
   let scheme = dc.defensiveScheme, player.position.side == .defense {
    player.schemeFamiliarity[scheme.rawValue] = Int.random(in: 55...85)
}
```

---

### Task 10: Initialize Scheme Expertise for Coaches

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/CoachingEngine.swift` (in generateCoachCandidates)

When generating coach candidates:

```swift
// Set scheme expertise
var expertise: [String: Int] = [:]

// Primary scheme: high expertise
if let offScheme = coach.offensiveScheme {
    expertise[offScheme.rawValue] = Int.random(in: 75...95)
    // Related schemes in same family
    for related in schemeFamilyMembers(offScheme) where related != offScheme {
        expertise[related.rawValue] = Int.random(in: 40...65)
    }
}
if let defScheme = coach.defensiveScheme {
    expertise[defScheme.rawValue] = Int.random(in: 75...95)
    for related in schemeFamilyMembers(defScheme) where related != defScheme {
        expertise[related.rawValue] = Int.random(in: 40...65)
    }
}

// Adaptability gives higher baseline for unknown schemes
let baselineBonus = Int(Double(coach.adaptability) / 99.0 * 15.0)
for scheme in OffensiveScheme.allCases where expertise[scheme.rawValue] == nil {
    expertise[scheme.rawValue] = 15 + baselineBonus + Int.random(in: 0...10)
}
for scheme in DefensiveScheme.allCases where expertise[scheme.rawValue] == nil {
    expertise[scheme.rawValue] = 15 + baselineBonus + Int.random(in: 0...10)
}

coach.schemeExpertise = expertise
```

Add `schemeFamilyMembers()` helper:
```swift
static func schemeFamilyMembers(_ scheme: OffensiveScheme) -> [OffensiveScheme] {
    switch scheme {
    case .westCoast, .airRaid, .proPassing, .spread: return [.westCoast, .airRaid, .proPassing, .spread]
    case .powerRun, .shanahan, .option, .rpo: return [.powerRun, .shanahan, .option, .rpo]
    }
}

static func schemeFamilyMembers(_ scheme: DefensiveScheme) -> [DefensiveScheme] {
    switch scheme {
    case .pressMan, .base43: return [.pressMan, .base43]
    case .cover3, .tampa2, .base34: return [.cover3, .tampa2, .base34]
    case .multiple, .hybrid: return [.multiple, .hybrid]
    }
}
```

---

### Task 11: Show Scheme Expertise in SchemeSelectionView

**Files:**
- Modify: `dynasty/dynasty/UI/Staff/SchemeSelectionView.swift`

When showing available schemes for a coordinator, display their expertise level:
- Show expertise % next to each scheme option
- Color code: 80%+ gold, 60-79% green, 40-59% blue, below 40% red
- Add warning when selecting a scheme the coach has low expertise in:
  "Coach has only 25% expertise in this scheme — players will learn slower"

---

### Task 12: Show Familiarity in Roster Views

**Files:**
- Modify: `dynasty/dynasty/UI/Roster/PlayerDetailView.swift`

Add a "Versatility & Scheme" section:
- Position familiarity bars for all non-zero positions
- Current training position with progress indicator
- Scheme familiarity bars for team's active schemes
- Ceiling indicator (dotted line) for position training limits

---

### Task 13: Update TODO.md

Add these completed items and remove from TODO if listed.
