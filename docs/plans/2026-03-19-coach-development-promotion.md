# Coach Development & Promotion System

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform coaches from static attribute holders into dynamic characters that grow, decline, get promoted, and form coaching trees — mirroring the player development system and adding a compelling "develop your staff" strategic layer.

**Architecture:** Coach model already has 12 attributes, age, yearsExperience, role, personality, and schemeExpertise. CoachingEngine already handles end-of-season development (random 1-3 attribute bumps) and coordinator poaching. This plan replaces the simple random growth with a structured XP/potential system, adds a promotion pipeline, and introduces coaching tree tracking.

**Tech Stack:** Swift, SwiftUI, SwiftData

---

## 1. Coach Hidden Potential System

### Design

Every coach receives a hidden `potential` attribute (1-100) at generation time. This value is never shown directly to the player — it can only be inferred through observation over multiple seasons ("this young coach keeps improving" vs "this veteran has plateaued").

**Potential determines:**
- The absolute ceiling for each attribute (similar to player `truePotential`)
- The attribute cap formula: `ceiling = potential * 0.65 + 35` (potential 90 = cap 93, potential 50 = cap 67)
- Growth speed: higher potential coaches gain more XP per event

**Generation rules by age bracket:**
| Age Range | Potential Range | Description |
|-----------|----------------|-------------|
| 25-30 | 40-99 | Wide variance — diamonds in the rough or busts |
| 31-40 | 45-90 | Narrower range, some high-ceiling coaches remain |
| 41-50 | 50-80 | Established coaches, ceiling mostly known |
| 51-60 | 40-70 | Late career, limited upside |
| 61+ | 30-60 | Near retirement, declining ceiling |

**Scouting interaction:** The player cannot see `potential` directly. A future scouting system could reveal a "development outlook" rating (e.g., "High Ceiling", "Limited Upside") based on a fuzzy read of potential, similar to how player potential is scouted.

---

## 2. Coach XP & Attribute Growth

### XP Sources (Weekly / Seasonal)

Replace the current random 1-3 attribute improvement in `CoachingEngine.developCoach()` with a structured XP system.

**Weekly XP (applied in WeekAdvancer during regular season):**
| Source | XP Amount | Notes |
|--------|-----------|-------|
| Game coached (any) | 5 | Base weekly XP for being on staff |
| Win | +3 | Bonus for winning |
| Loss | +1 | Still learn from losses |
| Playoff game | +8 | High-pressure experience |

**Seasonal XP (applied during coachingChanges phase):**
| Source | XP Amount | Notes |
|--------|-----------|-------|
| Season completed | 20 | Base offseason XP |
| Winning season (9+ wins) | +15 | Success breeds growth |
| Playoff appearance | +20 | Postseason experience |
| Conference championship | +30 | Deep run bonus |
| Super Bowl appearance | +40 | Ultimate stage |
| Super Bowl win | +60 | Championship experience |

**Mentoring XP (from HC and AHC):**
| Source | XP Multiplier | Notes |
|--------|--------------|-------|
| HC leadership attribute | 0.8x-1.3x | HC with leadership 80+ = 1.3x multiplier on all coach XP |
| AHC teaching bonus | +0-15% | AHC playerDevelopment attribute adds secondary multiplier |
| Coordinator mentoring | +0-10% | Coordinator playerDevelopment affects position coaches under them |

### XP to Attribute Conversion

```
XP needed per attribute point = 25 + (currentAttributeValue * 0.5)
```

This means:
- Going from 40 → 41 costs 45 XP
- Going from 70 → 71 costs 60 XP
- Going from 90 → 91 costs 70 XP

Growth is progressively harder, rewarding patience with young coaches.

**Attribute selection priority:** XP is not distributed evenly. Each coach has 2-3 "focus attributes" determined by their role:
- QB Coach: playCalling, playerDevelopment, gamePlanning
- OC/DC: playCalling, gamePlanning, adaptability
- HC: all attributes eligible, but motivation and discipline weighted higher
- Position coaches: playerDevelopment weighted highest

The system picks attributes to improve based on role weighting plus randomness, capped by the potential ceiling.

### Age-Based Decline

Replace the current yearsExperience >= 20 decline with an age-based system:

| Age | Effect |
|-----|--------|
| < 50 | No decline |
| 50-55 | 10% chance per season of -1 to adaptability |
| 56-60 | 25% chance of -1 to -2 on adaptability, playCalling |
| 61-65 | 40% chance of -1 to -2 on adaptability, playCalling, gamePlanning |
| 66+ | 60% chance of -1 to -3 on multiple attributes; retirement consideration |

**Retirement:** Coaches 65+ have an increasing chance of retiring each offseason: `retirementChance = (age - 64) * 0.15`. A coach with high reputation (80+) is 50% less likely to retire (they want to keep coaching).

---

## 3. Coaching Impact Hierarchy

### How Coaches Affect Players and Other Coaches

The hierarchy defines which coaches influence which players AND which other coaches:

```
Head Coach (HC)
├── Team-wide: ALL players get HC motivation/discipline bonus
├── Coach development: ALL coaches get HC leadership XP multiplier
│
├── Assistant Head Coach (AHC)
│   ├── Team-wide: ALL players get AHC secondary bonus (weaker than HC)
│   ├── Coach development: ALL coaches get AHC teaching XP bonus
│   │
│   ├── Offensive Coordinator (OC)
│   │   ├── Players: All offensive players (QB, RB, WR, TE, OL)
│   │   ├── Coaches: QB Coach, RB Coach, WR Coach, OL Coach
│   │   ├── Scheme: Offensive scheme teaching to players
│   │   └── Play calling: Affects offensive play outcomes
│   │
│   ├── Defensive Coordinator (DC)
│   │   ├── Players: All defensive players (DL, LB, DB)
│   │   ├── Coaches: DL Coach, LB Coach, DB Coach
│   │   ├── Scheme: Defensive scheme teaching to players
│   │   └── Play calling: Affects defensive play outcomes
│   │
│   └── Special Teams Coordinator (STC)
│       ├── Players: K, P, LS, return specialists
│       └── Play calling: Affects special teams outcomes
│
├── QB Coach → QBs only
├── RB Coach → RBs, FBs only
├── WR Coach → WRs, TEs only
├── OL Coach → LT, LG, C, RG, RT only
├── DL Coach → DEs, DTs only
├── LB Coach → MLBs, OLBs only
├── DB Coach → CBs, FS, SS only
├── Strength Coach → ALL players (physical development)
├── Team Doctor → ALL players (injury prevention)
└── Physio → ALL players (fatigue recovery, rehab)
```

### Player Development Bonus Calculation (Enhanced)

Modify `CoachingEngine.coachDevelopmentBonus()` to layer the hierarchy:

```swift
// Current: only position coach bonus
// New: stack bonuses from HC → Coordinator → Position Coach

var multiplier = 1.0

// Layer 1: HC team-wide bonus
if let hc = headCoach {
    let hcBonus = (Double(hc.motivation) - 50.0) / 50.0 * 0.08
    multiplier += hcBonus
}

// Layer 2: AHC secondary bonus
if let ahc = assistantHC {
    let ahcBonus = (Double(ahc.playerDevelopment) - 50.0) / 50.0 * 0.04
    multiplier += ahcBonus
}

// Layer 3: Coordinator unit bonus (OC for offense, DC for defense)
if let coord = unitCoordinator {
    let coordBonus = (Double(coord.playerDevelopment) - 50.0) / 50.0 * 0.10
    multiplier += coordBonus
}

// Layer 4: Position coach direct bonus (existing logic, slightly reduced)
if let posCoach = positionCoach {
    let posBonus = (Double(posCoach.playerDevelopment) - 50.0) / 50.0 * 0.15
    multiplier += posBonus
}

// Total range: roughly 0.7 to 1.6
```

### Coach Development Speed Bonus

Similarly, the HC and AHC affect how fast OTHER coaches develop:

```swift
// HC leadership multiplier on coach XP
let hcMultiplier = 0.8 + (Double(hc.motivation + hc.playerDevelopment) / 2.0 - 50.0) / 50.0 * 0.5
// Range: 0.8x (bad HC) to 1.3x (elite HC)

// AHC secondary multiplier
let ahcBonus = Double(ahc.playerDevelopment - 50) / 50.0 * 0.15
// Range: -0.15 to +0.15
```

---

## 4. Promotion System

### Promotion Paths

```
Position Coach → Coordinator → Assistant Head Coach → Head Coach*

* HC promotion only available when player is GM-only mode (not GM/HC)
```

**Eligible promotions by current role:**
| Current Role | Can Promote To |
|-------------|---------------|
| QB Coach | OC |
| RB Coach | OC |
| WR Coach | OC |
| OL Coach | OC |
| DL Coach | DC |
| LB Coach | DC |
| DB Coach | DC |
| Strength Coach | STC (lateral) |
| OC | AHC |
| DC | AHC |
| STC | AHC (rare) |
| AHC | HC (GM-only mode) |

**Demotion paths:**
| Current Role | Can Demote To |
|-------------|--------------|
| OC | QB Coach, RB Coach, WR Coach, OL Coach |
| DC | DL Coach, LB Coach, DB Coach |
| AHC | OC, DC |

### Promotion Flow (UI)

1. Player navigates to **Coach Detail View**
2. If coach is eligible for promotion, a **"Promote"** button appears
3. Tapping opens a **Role Picker** showing available promotion targets
4. After selecting a role, a **Salary Negotiation** modal appears:
   - Shows the coach's current salary and the new role's salary range
   - Coach demands a salary based on: new role's average + reputation modifier + OVR modifier
   - Player can accept, counter-offer (limited to 3 rounds), or cancel
5. On acceptance:
   - Coach's role changes
   - Salary updates
   - Previous role becomes vacant (shown in CoachingStaffView)
   - Adjustment period flag set

### Adjustment Period

Promoted coaches have a **1-season adjustment period** where their effectiveness is reduced:

```swift
var adjustmentSeasonPenalty: Double {
    guard isInAdjustmentPeriod else { return 0.0 }
    // First season in new role: -15% to all coaching bonuses
    return -0.15
}
```

The adjustment period is tracked via a new property:
```swift
var promotedInSeason: Int?  // Season year when promoted; nil = no adjustment
```

At the start of each new season, if `promotedInSeason` is more than 1 season ago, clear it.

### Demotion

Demotion works similarly but with morale consequences:
- Demoted coach loses 10-20 reputation
- Demoted coach has reduced moraleInfluence for 1 season
- Chemistry with HC becomes negative (-0.3) for 1 season unless the coach has high adaptability (70+)

---

## 5. Coaching Tree & Reputation

### Data Model

Track mentor-mentee relationships with a new property on Coach:

```swift
/// ID of the head coach this coach developed under (set when first hired onto a team).
var mentorCoachID: UUID?

/// IDs of coaches who developed under this coach when they were HC.
var coachingTreeIDs: [UUID] = []

/// Season and team where this coach was mentored.
var mentorshipOrigin: String?  // e.g., "2025 Chicago Bears"
```

### Coaching Tree Effects

**Reputation bonus from mentor's success:**
- If a coach's mentor (former HC) has reputation 80+, the mentee gets +5 to their own reputation when hired
- If the mentor won a Super Bowl, the mentee gets +10 reputation bonus
- This creates "coaching trees" like the real NFL (Bill Walsh tree, Bill Belichick tree)

**Candidate pool quality:**
- Teams with a highly-reputed HC attract better coaching candidates
- When generating candidates via `CoachingEngine.generateCoachCandidates()`:
  - If the hiring team's HC has reputation 85+: candidate pool quality +10% (higher base attributes)
  - If HC reputation 70+: +5% quality boost
  - If HC reputation < 40: -10% quality (good coaches avoid bad organizations)

### Coaching Tree UI

In **Coach Detail View**, add a "Coaching Tree" section:
- Shows the coach's mentor (if any): "Developed under [Mentor Name], [Team] ([Year])"
- Shows coaches in this coach's tree (if HC): list of former assistants who went on to other roles
- Purely narrative/flavor — no direct gameplay button, just adds depth

---

## 6. Model Changes

### Coach.swift Additions

```swift
// Hidden potential (1-100), determines attribute ceiling
var potential: Int

// XP system
var currentXP: Int = 0

// Promotion tracking
var promotedInSeason: Int?  // nil = not in adjustment period

// Coaching tree
var mentorCoachID: UUID?
var coachingTreeIDs: [UUID] = []
var mentorshipOrigin: String?  // "2025 Chicago Bears"
```

### Coach.swift Init Update

Add `potential` parameter with default:
```swift
potential: Int = 50,
```

---

## 7. Integration Points

### WeekAdvancer Changes

**In `advanceRegularSeasonWeek()` — add after existing engine integrations (after step 8b):**

```swift
// 9. Weekly coach XP accumulation
for team in teams {
    let teamCoaches = allCoaches.filter { $0.teamID == team.id }
    let hc = teamCoaches.first { $0.role == .headCoach }
    let ahc = teamCoaches.first { $0.role == .assistantHeadCoach }

    let didWin: Bool = // determine from this week's game results
    for coach in teamCoaches {
        CoachDevelopmentEngine.applyWeeklyXP(
            coach: coach,
            didWin: didWin,
            isPlayoff: false,
            headCoach: hc,
            assistantHC: ahc
        )
    }
}
```

**In `advanceOffseasonPhase()` — coachingChanges case — replace existing `developCoach` loop:**

```swift
case .coachingChanges:
    // Seasonal coach development (replaces old developCoach)
    for team in teams {
        let teamCoaches = allCoaches.filter { $0.teamID == team.id }
        let hc = teamCoaches.first { $0.role == .headCoach }
        let ahc = teamCoaches.first { $0.role == .assistantHeadCoach }

        for coach in teamCoaches {
            CoachDevelopmentEngine.applySeasonalDevelopment(
                coach: coach,
                teamWins: team.wins,
                madePlayoffs: team.wins >= 9,
                headCoach: hc,
                assistantHC: ahc
            )
        }
    }

    // Check coordinator poaching (existing)
    // Check coach retirement (new)
    // Clear adjustment periods for coaches promoted 1+ seasons ago
```

### PlayerDevelopmentEngine Changes

Modify `developPlayer()` to accept the full coaching staff hierarchy instead of just finding a position coach:

```swift
// Find the coaching chain for this player
let hc = coaches.first { $0.role == .headCoach }
let ahc = coaches.first { $0.role == .assistantHeadCoach }
let coordinator = coaches.first { coach in
    // OC for offensive players, DC for defensive players
    (player.position.side == .offense && coach.role == .offensiveCoordinator) ||
    (player.position.side == .defense && coach.role == .defensiveCoordinator)
}
let positionCoach = coaches.first { coach in
    CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: player.position)
}

// Apply layered coaching bonus
let bonus = CoachingEngine.hierarchicalDevelopmentBonus(
    headCoach: hc,
    assistantHC: ahc,
    coordinator: coordinator,
    positionCoach: positionCoach,
    player: player
)
totalPoints *= bonus
```

### CoachingEngine Changes

Add new method alongside existing `coachDevelopmentBonus()`:

```swift
static func hierarchicalDevelopmentBonus(
    headCoach: Coach?,
    assistantHC: Coach?,
    coordinator: Coach?,
    positionCoach: Coach?,
    player: Player
) -> Double
```

### LeagueGenerator Changes

When generating initial coaches for all 32 teams, assign potential values based on age:

```swift
let potential = CoachDevelopmentEngine.generatePotential(forAge: coach.age)
coach.potential = potential
```

### CoachDetailView Changes

- Add "Development" section showing:
  - Current trajectory: "Improving" / "Plateaued" / "Declining" (based on recent XP gains vs ceiling proximity)
  - Years in current role
  - Coaching tree info
- Add "Promote" button (conditionally shown)
- Add "Demote" button (conditionally shown, with confirmation)

### CoachingStaffView Changes

- Show coaching hierarchy visually (indented or tree-style)
- Highlight vacant positions created by promotions
- Show adjustment period indicator for recently promoted coaches

---

## 8. New Engine File

### CoachDevelopmentEngine.swift

Create: `Dynasty/dynasty/Engine/PlayerDevelopment/CoachDevelopmentEngine.swift`

```swift
enum CoachDevelopmentEngine {

    /// Weekly XP from coaching a game.
    static func applyWeeklyXP(
        coach: Coach,
        didWin: Bool,
        isPlayoff: Bool,
        headCoach: Coach?,
        assistantHC: Coach?
    )

    /// End-of-season development: convert accumulated XP to attribute growth.
    static func applySeasonalDevelopment(
        coach: Coach,
        teamWins: Int,
        madePlayoffs: Bool,
        headCoach: Coach?,
        assistantHC: Coach?
    )

    /// Age-based decline applied at end of season.
    static func applyAgingDecline(coach: Coach)

    /// Check if coach should retire.
    static func shouldRetire(coach: Coach) -> Bool

    /// Generate potential for a coach of the given age.
    static func generatePotential(forAge age: Int) -> Int

    /// Calculate attribute ceiling from potential.
    static func attributeCeiling(potential: Int) -> Int

    /// Set mentor relationship when a coach joins a team.
    static func setMentor(coach: Coach, headCoach: Coach?, team: Team, season: Int)
}
```

---

## 9. Balance Considerations

### Archetype Scenarios

**Young Diamond in the Rough (Age 28, OVR 45, Potential 90):**
- Salary: ~$200K (position coach)
- Season 1: gains 80-120 XP → improves 2-3 attributes by 1-2 points
- Season 3: OVR ~55, starting to show promise
- Season 5: OVR ~68, ready for coordinator promotion
- Season 8: OVR ~78, elite coordinator candidate
- Total investment: low salary for 3-5 years before payoff

**Veteran Plug-and-Play (Age 52, OVR 80, Potential 80):**
- Salary: ~$1.5M (coordinator)
- Already at or near ceiling — minimal growth possible
- Immediately effective, no waiting period
- Will start declining in 5-8 years
- Good for "win now" teams

**Mid-Career Upside (Age 38, OVR 60, Potential 78):**
- Salary: ~$400K (position coach)
- Has room to grow to ~75 OVR over 3-4 seasons
- Balanced risk/reward choice
- Could be promoted to coordinator within 2-3 years

**Budget Strategy:**
- A budget-conscious team can hire 3-4 young high-potential coaches for the price of 1 elite veteran
- Developing coaches mirrors developing players — patience is rewarded
- Losing a coach you developed (to poaching or firing) should feel meaningful narratively

### Narrative Impact of Firing Developed Coaches

When a coach who has been with the player's team for 3+ seasons is fired:
- News article generated: "[Coach] fired after [N] seasons with [Team]"
- If the coach was high-reputation: team morale drops slightly
- If the coach was popular (high moraleInfluence): player satisfaction dips
- Creates meaningful trade-off between loyalty and performance

---

## Implementation Phases

### Phase 1: Core Model & Potential (Priority: HIGH)
1. Add `potential`, `currentXP`, `promotedInSeason`, `mentorCoachID`, `coachingTreeIDs`, `mentorshipOrigin` to Coach model
2. Create `CoachDevelopmentEngine.swift` with XP and potential logic
3. Update `LeagueGenerator` to assign potential values to generated coaches
4. Update `CoachingEngine.generateCoachCandidates()` to assign potential

### Phase 2: XP System & Attribute Growth (Priority: HIGH)
5. Implement weekly XP accumulation in `CoachDevelopmentEngine`
6. Implement seasonal XP-to-attribute conversion with ceiling enforcement
7. Replace `CoachingEngine.developCoach()` random growth with new XP system
8. Wire weekly XP into `WeekAdvancer.advanceRegularSeasonWeek()`
9. Wire seasonal development into `WeekAdvancer.advanceOffseasonPhase()` coachingChanges case

### Phase 3: Coaching Hierarchy Impact (Priority: HIGH)
10. Implement `CoachingEngine.hierarchicalDevelopmentBonus()` method
11. Update `PlayerDevelopmentEngine.developPlayer()` to use layered coaching chain
12. Add HC/AHC multiplier to coach XP accumulation
13. Add coordinator mentoring bonus for position coaches under them

### Phase 4: Promotion & Demotion (Priority: MEDIUM)
14. Add promotion eligibility logic to `CoachDevelopmentEngine`
15. Build salary negotiation logic for promotions
16. Add "Promote" button to `CoachDetailView` with role picker
17. Add "Demote" button with confirmation dialog
18. Implement adjustment period tracking and penalty
19. Handle vacancy creation when a coach is promoted out of their old role

### Phase 5: Coaching Tree (Priority: LOW)
20. Implement mentor assignment when coaches join teams
21. Track coaching tree IDs when mentees leave for other teams
22. Add reputation bonus from mentor's success
23. Add coaching tree section to `CoachDetailView`
24. Modify candidate pool quality based on HC reputation

### Phase 6: Age Decline & Retirement (Priority: MEDIUM)
25. Replace experience-based decline with age-based decline
26. Implement coach retirement system
27. Generate retirement news articles and inbox messages
28. Handle roster impact of unexpected retirements

### Phase 7: UI Polish (Priority: LOW)
29. Add development trajectory indicator to `CoachDetailView` ("Improving" / "Plateaued" / "Declining")
30. Show coaching hierarchy visually in `CoachingStaffView`
31. Show adjustment period badge for recently promoted coaches
32. Add coaching tree visualization
33. Update TODO.md with completed tasks
