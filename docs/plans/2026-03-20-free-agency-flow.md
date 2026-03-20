# Free Agency Flow Overhaul

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform Free Agency into a day-by-day experience with pre-market re-signing, league year transition, cap compliance, competitive bidding against AI teams, and media summaries per round.

**Architecture:** The `freeAgency` SeasonPhase becomes a multi-step flow with internal state tracking via `freeAgencyRound` (0-6) on Career model. The first 3 rounds are "days" (Day 1-3, intense), then 3 "weeks" (Week 2-4, cooling off). Player can skip remaining rounds — AI auto-fills rosters. Flow: Final Push → New League Year → Cap Compliance → FA Day 1-3 + Week 2-4 → Advance to Pro Days.

**Tech Stack:** SwiftUI, SwiftData, existing FreeAgencyEngine/ContractEngine/TaskGenerator.

---

## ⚠️ PARALLEL EXECUTION — Coordination with Combine & Pro Days Plan

This plan runs in parallel with `docs/plans/2026-03-20-combine-prodays-flow.md`. The plans share files.

### Safe to Start Immediately (no conflicts)

**Tasks 1-2** of this plan are safe to start right away:
- Task 1 modifies `RosterEvaluationView.swift` + `ContractEngine.swift` (not shared)
- Task 2 modifies `Career.swift` + creates `FreeAgencyStep.swift` (not shared)

### Tasks 3-7 are safe (new files only)

These tasks create NEW files in `UI/FreeAgency/` and modify `FreeAgencyEngine.swift` — none of which are touched by the Combine plan.

### ⛔ Task 8 MUST WAIT for Combine Plan Tasks 1-3

Task 8 modifies shared files: `TaskGenerator.swift`, `CareerShellView.swift`, `CareerDashboardView.swift`.

**Before starting Task 8**, verify the Combine plan's Tasks 1-3 are committed:

```bash
# Check for the signal file
ls docs/plans/.combine-tasks-1-3-done 2>/dev/null && echo "SAFE TO PROCEED" || echo "WAIT — Combine Tasks 1-3 not done yet"

# Alternative: check git log for combine commits
git log --oneline -10 | grep -i "combine\|proDays\|sequential"
```

**If the signal file doesn't exist**, work on Tasks 3-7 first (FA views and engine — all independent files). Then check again before Task 8.

**When starting Task 8**: run `git pull --rebase` or check `git log` to ensure you have the Combine plan's changes to shared files, then add your FA cases alongside the existing combine/proDays cases.

### Tasks 9-10 are safe after Task 8

Once Task 8 is committed, Tasks 9-10 have no conflicts.

### Shared Files Reference

| Shared File | Combine Plan Modifies | This Plan Modifies |
|-------------|----------------------|-------------------|
| `TaskGenerator.swift` | `combineTasks()`, `proDaysTasks()`, switch | `freeAgencyTasks()` only |
| `CareerShellView.swift` | Combine+ProDays checks, proDays nav | FA checks, FA step routing |
| `CareerDashboardView.swift` | ProDays phase, locked task icon | FA sub-step display |
| `WeekAdvancer.swift` | `phase(after:)`, `.proDays` case | FA state reset |
| `NewsGenerator.swift` | Combine+ProDays news funcs | FA media funcs |

---

## Design Decisions (confirmed by user)

| Decision | Choice |
|----------|--------|
| FA rounds | Day 1, Day 2, Day 3, Week 2, Week 3, Week 4 (6 rounds) |
| Skip option | Player can end FA early → AI completes all remaining signings |
| AI visibility | Progressive: Day 1 = "5 teams interested", Day 3 = hints ("contender"), Week 3-4 = team names |
| Rejection reason | Always shown: "Chose KC for championship contention" |
| Cap mode | Same flow for Simple and Realistic, simpler numbers in Simple |
| New file location | `dynasty/dynasty/UI/FreeAgency/` |
| Franchise tag | Stays in Review Roster phase (not moved) |
| Incentives | Not now — future enhancement |

---

## Complete Target Flow

```
┌─────────────────────────────────────────────────────────┐
│ REVIEW ROSTER (existing phase — enhancement)            │
│                                                         │
│ Show: your expiring players + potential FA replacements  │
│ from other teams. Help player decide: re-sign or wait?  │
│ Franchise tag decisions happen here (existing)          │
└──────────────────────┬──────────────────────────────────┘
                       ▼
┌─────────────────────────────────────────────────────────┐
│ FREE AGENCY PHASE                                       │
│                                                         │
│ Step 1: FINAL PUSH (required)                           │
│   - Show own expiring players side-by-side with         │
│     top FA options at same position from other teams    │
│   - Last chance to re-sign before market opens          │
│   - Player accepts/rejects/counters offer               │
│   - Reason always shown if rejected                     │
│   - Button: "START NEW LEAGUE YEAR"                     │
│                                                         │
│ Step 2: NEW LEAGUE YEAR TRANSITION (automatic)          │
│   - All contracts: yearsRemaining -= 1                  │
│   - Expired contracts (0) → free agents                 │
│   - Next year's salaries kick in                        │
│   - Cap recalculated                                    │
│   - Summary sheet shown                                 │
│                                                         │
│ Step 3: ROSTER & CAP REVIEW (required)                  │
│   - Show updated cap with new-year salaries             │
│   - If OVER cap: MUST cut/restructure to get under      │
│   - Both Simple and Realistic must be under cap         │
│   - Button: "Enter Free Agency" (only if under cap)     │
│                                                         │
│ Step 4: FREE AGENCY ROUNDS (Day 1-3, Week 2-4)         │
│                                                         │
│   ROUND START: Summary of previous round results        │
│   - Accepted offers (yours + AI signings)               │
│   - Rejected offers with REASONS always shown           │
│   - Media headlines                                     │
│   - Market update (X players remaining)                 │
│                                                         │
│   DURING ROUND: Browse & make offers                    │
│   - Position group strengths visible                    │
│   - Team needs highlighted                              │
│   - Scheme fit per player                               │
│   - AI interest: Day 1 = count only,                    │
│     Day 3 = hints, Week 3-4 = team names               │
│   - Player motivation visible                           │
│   - Make / modify / withdraw offers                     │
│   - See own pending offers                              │
│                                                         │
│   ROUND END: Two options                                │
│   a) "Submit offers → Day 2" (continue)                 │
│   b) "Skip remaining FA" (AI auto-completes)            │
│      → AI signs remaining FAs to fill rosters           │
│      → FA list shows final state                        │
│                                                         │
│   MARKET DYNAMICS:                                      │
│   - Day 1: Top 10-15 players sign. Bidding wars.        │
│   - Day 2: More starters sign. Still competitive.       │
│   - Day 3: Mid-tier market. Reasonable deals.           │
│   - Week 2: Market slows. Better value available.       │
│   - Week 3: Bargain bin opens. Depth signings.          │
│   - Week 4: Scraps. Minimum deals. Camp bodies.         │
│                                                         │
│ Step 5: ADVANCE                                         │
│   - Button: "Advance to Pro Days & Workouts"            │
└─────────────────────────────────────────────────────────┘
```

---

## Task 1: Enhance Review Roster with FA Preview

**Files:**
- Modify: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift`
- Modify: `dynasty/dynasty/Engine/Contract/ContractEngine.swift`

**Goal:** During Review Roster, for each position group with expiring contracts, show potential FA replacements from other teams so the player can decide: re-sign now, franchise tag, or wait for market?

**Step 1: Add FA preview helper in ContractEngine**

```swift
struct FAPreviewPlayer {
    let playerID: UUID
    let name: String
    let position: Position
    let overall: Int
    let age: Int
    let estimatedSalary: Int  // thousands
    let currentTeamAbbr: String
}

static func previewFreeAgents(
    allPlayers: [Player],
    allTeams: [Team],
    playerTeamID: UUID,
    position: Position,
    limit: Int = 5
) -> [FAPreviewPlayer] {
    allPlayers
        .filter { $0.teamID != playerTeamID
              && $0.contractYearsRemaining <= 1
              && $0.position == position }
        .sorted { $0.overallRating > $1.overallRating }
        .prefix(limit)
        .map { player in
            let teamAbbr = allTeams.first { $0.id == player.teamID }?.abbreviation ?? "FA"
            return FAPreviewPlayer(
                playerID: player.id,
                name: player.fullName,
                position: player.position,
                overall: player.overallRating,
                age: player.age,
                estimatedSalary: estimateMarketValue(overall: player.overallRating, position: player.position, age: player.age),
                currentTeamAbbr: teamAbbr
            )
        }
}
```

**Step 2: Add FA preview section in RosterEvaluationView**

For each position group with expiring players, add collapsible section:

```
📋 Defensive Line — 1 expiring contract
   Your player: Marquise Coleman (DT, 80 OVR, $2.3M)

   🔍 Potential FA replacements:
   🟢 Marcus Williams (DT, 85 OVR, ~$8M) — BAL
   🔵 James Foster (DE, 78 OVR, ~$4M) — NYJ
   ⚪ Kevin Brown (DT, 72 OVR, ~$2M) — CAR

   💡 Williams would be a significant upgrade (+5 OVR)
```

**Step 3: Build and verify**

```bash
xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  build 2>&1 | grep "error:" | grep -v "linker\|attach DB"
```

**Step 4: Commit**

```bash
git commit -m "feat: FA preview in roster evaluation — compare expiring vs market"
```

---

## Task 2: Add FA state tracking to Career model

**Files:**
- Modify: `dynasty/dynasty/Domain/Models/Career.swift`
- Create: `dynasty/dynasty/Domain/Enums/FreeAgencyStep.swift`

**Step 1: Add FA state to Career**

```swift
// In Career.swift, add properties:
var freeAgencyRound: Int = 0              // 0 = pre-FA, 1-6 = rounds
var freeAgencyStep: String = "finalPush"  // tracks current sub-step
```

**Step 2: Create FreeAgencyStep enum**

```swift
// dynasty/dynasty/Domain/Enums/FreeAgencyStep.swift
import Foundation

enum FreeAgencyStep: String, Codable {
    case finalPush     = "FinalPush"      // Re-sign own players
    case newLeagueYear = "NewLeagueYear"  // Transition (automatic)
    case capReview     = "CapReview"       // Must get under cap
    case signing       = "Signing"         // FA rounds 1-6
    case complete      = "Complete"        // Done, can advance

    /// Human-readable round label
    static func roundLabel(_ round: Int) -> String {
        switch round {
        case 1: return "Day 1"
        case 2: return "Day 2"
        case 3: return "Day 3"
        case 4: return "Week 2"
        case 5: return "Week 3"
        case 6: return "Week 4"
        default: return "Complete"
        }
    }

    /// How aggressive AI teams are in this round (1.0 = very, 0.3 = passive)
    static func aiAggression(_ round: Int) -> Double {
        switch round {
        case 1: return 1.0    // Day 1: bidding wars
        case 2: return 0.85   // Day 2: still hot
        case 3: return 0.7    // Day 3: calming down
        case 4: return 0.5    // Week 2: measured
        case 5: return 0.35   // Week 3: bargain hunting
        case 6: return 0.2    // Week 4: scraps
        default: return 0.1
        }
    }

    /// How much AI team info is revealed
    static func aiVisibility(_ round: Int) -> AIVisibilityLevel {
        switch round {
        case 1, 2: return .countOnly       // "5 teams interested"
        case 3:    return .hints           // "A contender is interested"
        case 4:    return .partialNames    // "KC and 2 others"
        case 5, 6: return .fullNames      // "KC, SF, DAL interested"
        default:   return .countOnly
        }
    }
}

enum AIVisibilityLevel {
    case countOnly
    case hints
    case partialNames
    case fullNames
}
```

**Step 3: Build and verify**

**Step 4: Commit**

```bash
git commit -m "feat: FA state tracking — FreeAgencyStep enum + Career model"
```

---

## Task 3: Create FinalPushView

**Files:**
- Create: `dynasty/dynasty/UI/FreeAgency/FinalPushView.swift`

**Goal:** Show own expiring players vs top FA alternatives. Last chance to re-sign. Each player: offer/let walk/counter. Then "START NEW LEAGUE YEAR".

**Key UI:**
```
┌─ YOUR EXPIRING PLAYERS ─────────────────────────────────┐
│                                                          │
│ ┌─ DT Marquise Coleman ─────┬─ TOP FA ALTERNATIVES ────┐│
│ │ 80 OVR · Age 32 · $2.3M  │ Marcus Williams (BAL)     ││
│ │ 2 Pro Bowls               │ DT · 85 OVR · Age 27     ││
│ │ Motivation: 💰 Money      │ Est. ~$8M/yr              ││
│ │                           │                           ││
│ │ [Re-Sign $3M/2yr]        │ James Foster (NYJ)        ││
│ │ [Let Walk]               │ DE · 78 OVR · Age 29     ││
│ │                           │ Est. ~$4M/yr              ││
│ └───────────────────────────┴───────────────────────────┘│
│                                                          │
│ Coleman's response: "Wants $4M/yr — counter?"            │
│ [Accept Counter] [Revise Offer] [Let Walk]               │
│                                                          │
│ ══════════════════════════════════════════════════════════│
│                                                          │
│              [ START NEW LEAGUE YEAR ]                   │
│     All remaining undecided players will hit market      │
└──────────────────────────────────────────────────────────┘
```

**Re-sign evaluation logic:**

```swift
static func evaluateReSignOffer(
    player: Player,
    offeredSalary: Int,
    offeredYears: Int,
    marketValue: Int,
    teamWins: Int,
    teamReputation: Int
) -> ReSignResponse {
    let ratio = Double(offeredSalary) / Double(marketValue)

    // Own team loyalty bonus: +10-15% acceptance
    let loyaltyBonus = 0.12

    // Motivation modifiers
    let motivationMod: Double = {
        switch player.personalityArchetype {
        case .loyalVeteran:   return 0.15  // big discount for staying
        case .moneyMotivated: return -0.05 // needs market value
        case .ringChaser:     return teamWins >= 10 ? 0.10 : -0.05
        default:              return 0.05
        }
    }()

    let threshold = 0.80 - loyaltyBonus - motivationMod

    if ratio >= threshold {
        return .accepted
    } else if ratio >= threshold - 0.15 {
        let counterSalary = Int(Double(marketValue) * (threshold + 0.05))
        return .countered(salary: counterSalary, years: offeredYears, reason: "Wants more money")
    } else {
        return .rejected(reason: rejectReason(player: player, offeredSalary: offeredSalary, marketValue: marketValue))
    }
}
```

Rejection reasons always shown:
- "Wants to test the free agent market"
- "Feels undervalued — asking price is $X"
- "Looking for a championship contender"
- "Wants a bigger role elsewhere"

**Step: Build, verify, commit**

```bash
git commit -m "feat: FinalPushView — re-sign or let walk with FA alternatives"
```

---

## Task 4: New League Year transition

**Files:**
- Modify: `dynasty/dynasty/Engine/Contract/FreeAgencyEngine.swift`

**Step 1: Create transition function**

```swift
struct LeagueYearSummary {
    let newFreeAgents: [(name: String, position: String, overall: Int, formerTeam: String)]
    let playerTeamCapBefore: Int
    let playerTeamCapAfter: Int
    let capFreed: Int
    let notableFreeAgents: [(name: String, position: String, overall: Int)]  // top 10
}

static func executeNewLeagueYear(
    allPlayers: [Player],
    allTeams: [Team],
    playerTeamID: UUID,
    modelContext: ModelContext
) -> LeagueYearSummary {
    // 1. Decrement all contracts
    // 2. Players at 0 years → become free agents (teamID = nil)
    // 3. Recalculate team caps
    // 4. Apply cap growth (~5-8%)
    // 5. Return summary for display
}
```

**Step 2: Show transition summary sheet**

After button press, show animated summary:
- "42 players hit free agency"
- "Your cap: $182M → $198M (freed $16M from expirations)"
- "Notable new free agents: QB Marcus Williams (85), DE..."
- [Continue to Cap Review]

**Step: Build, verify, commit**

```bash
git commit -m "feat: new league year transition — contracts advance, FAs generated"
```

---

## Task 5: CapComplianceView

**Files:**
- Create: `dynasty/dynasty/UI/FreeAgency/CapComplianceView.swift`

**Goal:** If team is over cap with new-year salaries, player MUST cut/restructure to get under. Both Simple and Realistic modes.

**Key features:**
- Red/green cap indicator
- Player list sorted by salary
- "Cut" button per player (shows dead cap in Realistic mode)
- "Restructure" button (converts salary to bonus, spreads cap — Realistic only)
- "Enter Free Agency" disabled until under cap

**Step: Build, verify, commit**

```bash
git commit -m "feat: cap compliance — must get under cap before FA signing"
```

---

## Task 6: FAWeeklyView — core signing loop

**Files:**
- Create: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift`
- Create: `dynasty/dynasty/UI/FreeAgency/FAOfferSheet.swift`
- Create: `dynasty/dynasty/UI/FreeAgency/FARoundSummaryView.swift`

**This is the largest task.** The core free agency experience.

**FAWeeklyView structure:**

```swift
struct FAWeeklyView: View {
    let career: Career
    @Environment(\.modelContext) private var modelContext

    @State private var freeAgents: [FreeAgent] = []
    @State private var myOffers: [UUID: ContractOffer] = [:]
    @State private var roundResults: RoundResults?
    @State private var showRoundSummary = false

    var currentRound: Int { career.freeAgencyRound }
    var roundLabel: String { FreeAgencyStep.roundLabel(currentRound) }

    var body: some View {
        VStack(spacing: 0) {
            // Header: "FREE AGENCY — Day 2" with round indicator dots
            roundHeader

            // Pending offers bar
            if !myOffers.isEmpty { pendingOffersBar }

            // Position needs banner (from roster evaluation)
            positionNeedsBanner

            // Free agent list (tiered, filtered, with competition info)
            freeAgentList

            // Bottom bar with two buttons
            HStack {
                Button("Skip Remaining FA") { skipRemainingFA() }
                    .buttonStyle(.bordered)
                Button("Submit Offers → \(FreeAgencyStep.roundLabel(currentRound + 1))") {
                    processRound()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}
```

**Free agent row shows (progressive AI visibility):**
```
Round 1-2: "🔥 5 teams interested"
Round 3:   "🔥 A championship contender and 3 others interested"
Round 4:   "🔥 KC and 2 others interested"
Round 5-6: "🔥 KC, SF, DAL interested"
```

**"Skip Remaining FA" logic:**
```swift
func skipRemainingFA() {
    // AI signs all remaining FAs based on team needs
    FreeAgencyEngine.simulateRemainingFA(
        freeAgents: freeAgents,
        allTeams: teams,
        playerTeamID: career.teamID
    )
    career.freeAgencyStep = FreeAgencyStep.complete.rawValue
    // Show final summary
}
```

**Step: Build, verify, commit**

```bash
git commit -m "feat: FAWeeklyView — day-by-day signing with offers and AI competition"
```

---

## Task 7: AI bidding engine + player decisions

**Files:**
- Modify: `dynasty/dynasty/Engine/Contract/FreeAgencyEngine.swift`

**AI offer generation per round:**

```swift
static func generateAIOffers(
    freeAgents: [FreeAgent],
    round: Int,
    allTeams: [Team],
    playerTeamID: UUID?
) -> [UUID: [(teamID: UUID, teamAbbr: String, salary: Int, years: Int)]] {
    let aggression = FreeAgencyStep.aiAggression(round)

    // Round 1: AI targets 85+ OVR players aggressively
    //   3-5 teams bid at 90-110% asking
    // Round 3: AI targets 75-84 OVR
    //   2-3 teams bid at 85-100% asking
    // Round 6: AI targets <70 OVR
    //   1 team bids at 60-80% asking

    // AI team selection based on:
    //   - Team has need at position (starter OVR < FA OVR)
    //   - Team has cap space
    //   - Team aggression = wins × budget willingness
}
```

**Player decision with ALWAYS-visible reasons:**

```swift
struct PlayerDecision {
    let accepted: Bool
    let chosenTeamID: UUID?
    let chosenTeamName: String?
    let reason: String          // ALWAYS populated
    let salary: Int?
    let years: Int?
}

// Reasons based on motivation:
// Money:   "Chose [Team] — offered $2M more per year"
// Winning: "Chose [Team] for championship contention"
// Fame:    "Chose [Team] for the big market spotlight"
// Loyalty: "Chose [Team] to return to familiar surroundings"
// Stats:   "Chose [Team] for a larger role and more playing time"
// Stayed:  "Excited to stay and build something special here"
```

**Step: Build, verify, commit**

```bash
git commit -m "feat: AI bidding with progressive visibility + player decision reasons"
```

---

## Task 8: Wire FA flow into navigation + tasks

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift`
- Modify: `dynasty/dynasty/UI/Career/CareerShellView.swift`
- Modify: `dynasty/dynasty/UI/Career/CareerDashboardView.swift`

**Step 1: Update FA tasks**

```swift
private static func freeAgencyTasks(hasExpiringContracts: Bool) -> [GameTask] {
    [
        GameTask(
            phase: .freeAgency,
            title: "Final Push — Re-sign or let walk",
            description: "Make final offers to your expiring players before the market opens.",
            icon: "arrow.triangle.2.circlepath",
            destination: .freeAgency,
            isRequired: true
        ),
        GameTask(
            phase: .freeAgency,
            title: "Start New League Year",
            description: "Advance contracts and open the free agent market.",
            icon: "calendar.badge.clock",
            destination: .freeAgency,
            isRequired: true
        ),
        GameTask(
            phase: .freeAgency,
            title: "Roster & Cap compliance",
            description: "Ensure your team is under the salary cap.",
            icon: "dollarsign.circle.fill",
            destination: .capOverview,
            isRequired: true
        ),
        GameTask(
            phase: .freeAgency,
            title: "Free agency signings",
            description: "Browse the market and sign free agents over 6 rounds.",
            icon: "person.badge.plus",
            destination: .freeAgency,
            isRequired: true
        ),
    ]
}
```

**Step 2: Route FA destination based on current step**

```swift
case .freeAgency:
    Group {
        switch FreeAgencyStep(rawValue: career.freeAgencyStep) {
        case .finalPush:    FinalPushView(career: career)
        case .capReview:    CapComplianceView(career: career)
        case .signing:      FAWeeklyView(career: career)
        case .complete:     FACompleteView(career: career)  // summary + advance
        default:            FinalPushView(career: career)
        }
    }
    .onAppear { markTaskVisited(for: .freeAgency); refreshTaskCompletionStatus() }
```

**Step 3: Sequential task unlocking**

Tasks unlock based on `career.freeAgencyStep`:
- Final Push: always available
- Start League Year: available after finalPush complete
- Cap compliance: available after newLeagueYear
- FA signings: available after capReview (under cap)

**Step 4: Dashboard phase display**

Show current FA sub-step in timeline:
- "Final Push — Re-sign your players"
- "New League Year — Contracts advancing"
- "Cap Compliance — $4.2M over cap"
- "Free Agency — Day 2 of 6 rounds"

**Step: Build, verify, commit**

```bash
git commit -m "feat: wire FA flow into navigation, tasks, and dashboard"
```

---

## Task 9: Round summaries + media

**Files:**
- Create: `dynasty/dynasty/UI/FreeAgency/FARoundSummaryView.swift`
- Modify: `dynasty/dynasty/Engine/Contract/FreeAgencyEngine.swift`

**Round summary shown at start of each new round:**

```
╔══════════════════════════════════════════════╗
║            DAY 1 RESULTS                     ║
╠══════════════════════════════════════════════╣
║                                              ║
║ ✅ YOUR SIGNINGS                             ║
║   WR James Davis — $8M/yr · 3 years         ║
║                                              ║
║ ❌ YOUR REJECTIONS                           ║
║   QB Marcus Williams → signed by KC          ║
║   "Chose Kansas City for championship        ║
║    contention" ($20M/yr · 4 years)           ║
║                                              ║
║ 📰 HEADLINES                                 ║
║   "Chiefs land Williams in $80M blockbuster" ║
║   "Raiders quietly add Davis for depth"      ║
║   "Surprise: Jets lose out on top CB target" ║
║                                              ║
║ 📊 MARKET UPDATE                             ║
║   8 players signed · 34 still available      ║
║   Your cap remaining: $24.1M                 ║
║                                              ║
║              [Continue to Day 2]             ║
╚══════════════════════════════════════════════╝
```

**Step: Build, verify, commit**

```bash
git commit -m "feat: FA round summaries with signings, rejections, and media"
```

---

## Task 10: State reset + full flow verification

**Files:**
- Modify: `dynasty/dynasty/UI/Career/TeamSelectionView.swift`
- Modify: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift`

**Step 1: Reset FA state**

In `startCareer()`:
```swift
// Career model defaults handle freeAgencyRound = 0, freeAgencyStep = "finalPush"
```

In `WeekAdvancer`, when entering FA phase:
```swift
case .combine:
    // ... existing combine logic ...
    // When advancing TO freeAgency:
    career.freeAgencyRound = 0
    career.freeAgencyStep = FreeAgencyStep.finalPush.rawValue
```

**Step 2: Full flow walkthrough**

1. Review Roster → see FA preview for positions with expiring contracts ✓
2. Advance to FA → Final Push → own expiring players vs alternatives ✓
3. Re-sign/let walk decisions → "START NEW LEAGUE YEAR" ✓
4. Contracts advance, FAs generated → summary shown ✓
5. Cap compliance → cut/restructure if over → "Enter Free Agency" ✓
6. Day 1 → browse market, make offers → "Submit → Day 2" ✓
7. Day 2 → summary of Day 1 results, AI signings shown ✓
8. Day 3 → AI hints appear ("A contender interested") ✓
9. Week 2-4 → team names progressively revealed ✓
10. OR "Skip Remaining" at any point → AI completes ✓
11. FA Complete → "Advance to Pro Days & Workouts" ✓

**Step 3: Verify edge cases**
- No expiring contracts → skip Final Push (auto-complete)
- Over cap → must resolve before FA
- All targets signed by AI → appropriate rejection messages
- Skip after Day 1 → AI fills remaining
- Simple mode → same flow, no guaranteed/bonus fields

**Step: Build, verify, commit**

```bash
git commit -m "polish: FA flow complete — state reset and full verification"
```

---

## Summary

| Task | Description | Complexity | New Files |
|------|-------------|------------|-----------|
| 1 | FA preview in roster evaluation | Medium | — |
| 2 | Career FA state + FreeAgencyStep enum | Small | FreeAgencyStep.swift |
| 3 | FinalPushView (re-sign or let walk) | Large | FinalPushView.swift |
| 4 | New League Year transition | Medium | — |
| 5 | CapComplianceView | Medium | CapComplianceView.swift |
| 6 | FAWeeklyView (core loop) | **Very Large** | FAWeeklyView.swift, FAOfferSheet.swift |
| 7 | AI bidding + player decisions | Large | — |
| 8 | Wire into navigation + tasks | Medium | — |
| 9 | Round summaries + media | Medium | FARoundSummaryView.swift |
| 10 | State reset + verification | Small | — |

## Dependency Order

```
Task 2 (model) → Task 3 (FinalPush) → Task 4 (LeagueYear) → Task 5 (Cap)
  → Task 6 (Weekly) + Task 7 (AI) → Task 8 (wire) → Task 9 (media) → Task 10 (verify)
Task 1 (roster preview) is independent
```

## New Files Created

```
dynasty/dynasty/Domain/Enums/FreeAgencyStep.swift
dynasty/dynasty/UI/FreeAgency/FinalPushView.swift
dynasty/dynasty/UI/FreeAgency/CapComplianceView.swift
dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift
dynasty/dynasty/UI/FreeAgency/FAOfferSheet.swift
dynasty/dynasty/UI/FreeAgency/FARoundSummaryView.swift
```
