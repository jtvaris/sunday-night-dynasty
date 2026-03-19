# Scouting & Draft System — Design Document

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a full-season scouting pipeline from college football kickoff through draft night, delivering the "discover → evaluate → decide" emotional arc that makes NFL GM simulation compelling.

**Core Fantasy:** You're in the war room on draft night. The board is falling your way. You know something the other teams don't — because your scouts found a diamond in the rough months ago. Your preparation pays off.

**Tech Stack:** Swift, SwiftUI, SwiftData

---

## Design Decisions (from brainstorming 2026-03-19)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| **Core emotion** | Full arc: Discovery → Information gathering → Risk/reward at draft | Each phase feeds into the next |
| **Depth** | Strategic with Madden 2.0 touches | Priorities + key decisions manual; details auto |
| **Draft classes visible** | 2 (current + next year preview) | Enables "tank for future" strategy |
| **Draft experience** | Full elämys (pick-by-pick, trades, media, war room) | The payoff moment for months of scouting |
| **Info reveal** | Layered + scout accuracy | Phases reveal data layers; scout skill = reliability |
| **Competition visibility** | Mock drafts + team interest | Adds strategic depth |
| **Big Board** | Auto-rank with tiers + manual overrides | Strategic, not tedious |
| **Prospect count** | ~350 draftable (NFL-realistic) | From ~3000 eligible, ~330 combine invites, ~260 drafted |

---

## 1. Annual Scouting Timeline

```
NFL Season Start (Sep)
│
├── College Season Begins (Late Aug)
│   ├── Weeks 1-4: Early reports trickle in
│   ├── Weeks 5-8: Production data builds
│   ├── Weeks 9-12: Midseason evaluations
│   └── Weeks 13-17: Late season + conference championships
│
├── NFL Regular Season ends (Week 18)
│
├── College Bowls + Playoffs (Dec-Jan)
│   └── Prospect declarations begin
│
├── Senior Bowl / All-Star Games (Late Jan)
│   └── Reveals: interview data, practice film, 1-on-1s
│
├── Offseason begins — Coaching Changes phase
│
├── Review Roster phase
│   └── Player evaluates roster needs → informs scouting priorities
│
├── NFL Combine (Late Feb - Early Mar)
│   └── Reveals: physical measurements, drill times, medical, interviews
│
├── Pro Days (March)
│   └── Reveals: supplementary physical data, non-Combine prospects
│
├── Personal Workouts & Visits (March-April)
│   └── Reveals: scheme fit, personality deep dive, final evaluations
│
├── NFL Draft (Late April) — THE EVENT
│   ├── Round 1: Thursday evening
│   ├── Rounds 2-3: Friday
│   └── Rounds 4-7: Saturday
│
└── UDFA Signing (Post-draft)
    └── Sign ~12 undrafted prospects
```

---

## 2. Prospect Generation

### 2.1 College Prospect Pool

Each season, generate **~3,000 draft-eligible prospects** across all positions:

| Position | Eligible | Typical Drafted | Notes |
|----------|----------|----------------|-------|
| QB | ~200 | 8-12 | Only 4-6 in Rd 1-2 |
| RB | ~250 | 12-16 | Declining value |
| WR | ~350 | 25-30 | Highest demand |
| TE | ~150 | 10-14 | |
| OT | ~200 | 18-24 | Premium |
| OG | ~200 | 14-18 | |
| C | ~100 | 6-10 | |
| DE/EDGE | ~300 | 22-28 | Always in demand |
| DT | ~200 | 16-20 | |
| LB | ~300 | 18-22 | ILB + OLB |
| CB | ~350 | 28-32 | Most drafted position |
| FS | ~150 | 8-10 | |
| SS | ~150 | 8-10 | |
| K | ~50 | 1-3 | |
| P | ~50 | 1-3 | |

### 2.2 Prospect Model (CollegeProspect)

```swift
@Model final class CollegeProspect {
    var id: UUID
    var firstName: String
    var lastName: String
    var position: Position
    var college: String           // "Alabama", "Ohio State" etc
    var conference: String        // "SEC", "Big Ten" etc
    var classYear: ProspectClass  // .freshman, .sophomore, .junior, .senior
    var age: Int                  // 20-24
    var draftYear: Int            // The year they're eligible

    // TRUE attributes (hidden from player initially)
    var trueOverall: Int          // 40-99
    var truePotential: Int        // 40-99
    var trueSpeed: Int
    var trueStrength: Int
    var trueAgility: Int
    // ... all physical + mental attributes

    // Scouted/revealed attributes (what player can see)
    var scoutedOverall: Int?      // nil = not scouted yet
    var scoutedGrade: ScoutGrade? // .elite, .firstRound, .dayTwo, .dayThree, .priority, .draftable, .undrafted
    var scoutedAttributes: [String: ScoutedValue]  // attribute name → ScoutedValue

    // College production stats
    var collegeStats: CollegeStats  // games, touchdowns, yards, etc

    // Combine data (revealed at combine)
    var combineFortyYard: Double?
    var combineBenchPress: Int?
    var combineVerticalJump: Double?
    var combineBroadJump: Double?
    var combineThreeCone: Double?
    var combineShuttle: Double?
    var combineHeight: Double?    // inches
    var combineWeight: Int?       // lbs
    var combineArmLength: Double?
    var combineHandSize: Double?

    // Interview/personality data (revealed in interviews)
    var personality: PersonalityArchetype?
    var motivation: String?
    var footballIQ: Int?          // revealed in interviews
    var characterConcerns: [String]  // "Off-field issues", "Work ethic questions"

    // Draft status
    var declaredForDraft: Bool = false
    var projectedRound: Int?      // 1-7, media mock draft projection
    var teamInterest: [UUID]      // team IDs showing interest
    var combineInvite: Bool = false

    // Scouting progress
    var scoutingLevel: ScoutingLevel = .unknown  // .unknown, .basic, .intermediate, .advanced, .elite
    var scoutReports: [ScoutReport]  // individual reports from scouts
}
```

### 2.3 ScoutedValue (Fuzzy Information)

```swift
struct ScoutedValue: Codable {
    let estimatedValue: Int     // Scout's estimate (may be wrong)
    let confidence: Double      // 0.0-1.0, how reliable the estimate is
    let source: ScoutingSource  // .collegeTape, .combine, .proDay, .interview, .workout
}
```

Scout accuracy formula:
```
estimatedValue = trueValue + noise
noise = Int.random(in: -errorRange...errorRange)
errorRange = max(2, Int(15.0 * (1.0 - scoutAccuracy/100.0)))
```

Elite scout (accuracy 95): ±2 error
Average scout (accuracy 60): ±9 error
Poor scout (accuracy 30): ±15 error

---

## 3. Scouting Phases & Information Reveal

### Phase 1: College Season (Sep-Dec) — "Film Study"

**What scouts do:** Watch college games, evaluate game tape
**What is revealed:**
- College production stats (yards, TDs, completion %)
- General scouting grade (fuzzy: "1st round talent" to "Priority free agent")
- 2-3 strength/weakness notes ("Elite arm talent", "Struggles against press coverage")
- Injury history from college

**Player actions:**
- Assign scouts to regions/conferences (each scout covers ~300 prospects)
- Set scouting priorities (focus positions, focus conferences)
- Review weekly scout reports as they come in

**Auto-updates:** Each week during the NFL regular season, 1-3 new reports arrive per scout.

### Phase 2: Declaration Period (Jan) — "Who's Coming Out?"

**Event:** Underclassmen decide whether to declare for the draft
- ~70 underclassmen declare (some surprises, some expected)
- News articles for top declarations ("Generational QB prospect declares!")
- Some prospects withdraw and return to college (news: "Top WR returns for senior year")
- This year's draft class is finalized

**Player action:** Review declarations, adjust Big Board

### Phase 3: Senior Bowl / All-Star Games (Late Jan) — "Up Close"

**What scouts do:** Attend practices, watch 1-on-1 drills
**What is revealed:**
- Practice performance grades (effort, coachability)
- Position-specific skills (route running, pass blocking technique)
- Preliminary personality/character read
- How they respond to NFL-level coaching

**Player actions:** Send scouts to Senior Bowl (costs scouting budget)

### Phase 4: NFL Combine (Late Feb - Early Mar) — "The Tests"

**What is revealed (for ~330 invited prospects):**
- ALL physical measurements: height, weight, arm length, hand size
- Combine drill results: 40-yard dash, bench press, vertical jump, broad jump, 3-cone, shuttle
- Medical examination results (injury flags)
- Wonderlic/cognitive test score (partial reveal of football IQ)

**Player actions:**
- Schedule interviews (limited to ~60 per combine, 15 minutes each)
- Each interview reveals: personality, motivation, football IQ, character concerns
- Interview effectiveness depends on coaching staff quality

### Phase 5: Pro Days (March) — "The Deep Cuts"

**What is revealed (for ALL prospects, including non-Combine):**
- Physical data for non-Combine prospects (hand-timed, less accurate)
- Updated drill numbers for Combine prospects who want to improve
- Position-specific workout results

**Player actions:**
- Send scouts to specific Pro Days (each scout can attend ~5)
- Discover late-round gems at smaller schools

### Phase 6: Personal Workouts & Visits (March-April) — "The Final Piece"

**What is revealed:**
- Scheme fit evaluation (how prospect fits YOUR team's schemes)
- Deep personality dive (locker room fit)
- Medical deep dive for flagged prospects
- Highest confidence scouting grade

**Player actions:**
- Invite prospects for personal workouts (limited to ~30)
- Each workout gives highest-accuracy evaluation
- Coaches provide input on scheme fit

### Phase 7: Draft Week — "War Room"

**Pre-draft:**
- Final Big Board lock-in
- Mock draft updates (media predictions shift)
- Trade offers start arriving
- Coaching staff recommendations

---

## 4. Big Board System

### 4.1 Tier-Based Auto-Ranking

Prospects are auto-sorted into tiers based on scouted grades:

| Tier | Name | Description | Typical Count |
|------|------|-------------|---------------|
| 1 | Blue Chip | Franchise-changing talent | 5-10 |
| 2 | First Rounder | Day 1 starter | 15-25 |
| 3 | Day Two | Solid starter potential | 30-50 |
| 4 | Day Three | Rotational/developmental | 60-100 |
| 5 | Priority FA | Likely undrafted, worth signing | 80-120 |
| 6 | Draftable | Might get a late-round flier | 50-80 |

### 4.2 Player Overrides

Within each tier:
- Auto-sorted by scouted overall + position value
- Player can drag-and-drop to reorder within tier
- Player can move prospects between tiers (override scout grade)
- Player can flag prospects: "Must Have", "Avoid", "Sleeper"
- Position-specific sub-boards: "Top QBs", "Top Edge Rushers" etc

### 4.3 Need-Based Recommendations

System highlights:
- "Your #1 need: CB (weakest position group)"
- "Best available at need: Prospect X (Tier 2, CB)"
- "Best player available: Prospect Y (Tier 1, EDGE)"
- Coaching staff input: "OC recommends Prospect Z for scheme fit"

---

## 5. Draft Night Experience

### 5.1 War Room View

```
┌──────────────────────────────────────────────────┐
│  NFL DRAFT — ROUND 1                    Pick 12  │
│  ═══════════════════════════════════════════════  │
│                                                   │
│  ┌─────────────┐  ┌──────────────────────────┐   │
│  │  YOUR BIG   │  │  DRAFT BOARD             │   │
│  │  BOARD      │  │                          │   │
│  │             │  │  #1 KC — [Player] EDGE   │   │
│  │  1. ████    │  │  #2 CHI — [Player] QB    │   │
│  │  2. ████    │  │  #3 NE — [Player] OT     │   │
│  │  3. ████    │  │  ...                      │   │
│  │  4. ████    │  │  #11 NYG — ON THE CLOCK  │   │
│  │  5. ████    │  │  #12 YOU — NEXT          │   │
│  │             │  │                          │   │
│  └─────────────┘  └──────────────────────────┘   │
│                                                   │
│  ┌─────────────────────────────────────────────┐ │
│  │  📞 TRADE OFFERS          💬 WAR ROOM CHAT  │ │
│  │  PHI offers #22 + #54     OC: "Take the QB" │ │
│  │  for your #12             DC: "EDGE rusher!" │ │
│  │  [Accept] [Counter] [X]   Scout: "Sleeper!"  │ │
│  └─────────────────────────────────────────────┘ │
│                                                   │
│  ┌─ YOUR PICK ──────────────────────────────────┐│
│  │  [Select Player]  [Trade Down]  [Trade Up]   ││
│  └──────────────────────────────────────────────┘│
└──────────────────────────────────────────────────┘
```

### 5.2 Pick-by-Pick Flow

For each pick in the draft:

1. **Announcement:** "[Team] is on the clock" + timer (simulated)
2. **AI Decision:** Other teams select based on their needs + BPA
3. **Your Big Board updates:** Crossed-off players, "still available" highlights
4. **Trade offers appear:** Phone rings with offers from other teams
5. **Staff commentary:** OC/DC/scouts comment on available players
6. **Your pick arrives:**
   - Big moment — spotlight on your selection
   - Player card reveals with highlight reel description
   - Media grade: "A — Best player available!" or "D — Massive reach"
   - War room celebration or concern animation

### 5.3 Trade System During Draft

Players can:
- **Trade up:** Offer future picks + current picks to move up
- **Trade down:** Accept offers from teams below to accumulate picks
- **Trade future picks:** Next year's picks as currency (2 draft classes visible)
- **Counter-offer:** Negotiate trade terms

Trade value chart (simplified):
- Pick #1 = ~3000 points
- Pick #32 = ~600 points
- Pick #64 = ~300 points
- Pick #100 = ~150 points
- Pick #200 = ~20 points

### 5.4 Media & Narrative

After each of your picks:
- **Instant grade:** A+ to F (from "experts")
- **Media headline:** "Lions steal Prospect X in the 3rd round!"
- **Fan reaction:** Social media style comments
- **After draft:** Full draft grade card with analysis

---

## 6. First Season Special Case

When the player starts a new career:
- College season has already happened (offseason start)
- Prospects are pre-scouted to a "basic" level (as if scouts watched games)
- Combine data is available for top ~330 prospects
- The player starts at the Pro Day / personal workout phase
- Big Board has auto-generated rankings based on "inherited" scout reports
- This simulates a new GM inheriting the previous staff's work

---

## 7. Mock Drafts & Competition

### 7.1 Media Mock Drafts

- Published at 3 points: midseason, post-combine, pre-draft
- Each mock assigns projected rounds to top ~100 prospects
- Mocks are imperfect (±5-10 picks typical variance)
- Creates drama: "Mock has YOUR top target going #3 overall — too high for you"

### 7.2 Team Interest Indicators

- Other teams' interest shown as heat level: Cold / Warm / Hot
- Based on team needs + prospect fit
- Not always accurate (teams bluff)
- Creates urgency: "5 teams show HOT interest in your target CB"

---

## 8. Scout Staff Integration

### Current Scout Roles (already in game)

| Role | Function in Scouting |
|------|---------------------|
| Chief Scout | +10% accuracy to all evaluations, oversees process |
| Regional Scout (East) | Covers ACC, Big East, AAC schools |
| Regional Scout (West) | Covers Pac-12, Mountain West, Big West |
| Regional Scout (South) | Covers SEC, Sun Belt, C-USA |
| Regional Scout (North) | Covers Big Ten, MAC, Missouri Valley |
| Regional Scout (Central) | Covers Big 12, AAC, independents |

### Scouting Budget & Assignments

Each scout can:
- Evaluate ~300 prospects per season (college game attendance)
- Attend 1 All-Star game (Senior Bowl, Shrine Bowl)
- Attend ~5 Pro Days
- Conduct ~20 personal workouts
- The more focused a scout is (fewer schools), the deeper the evaluation

### Scout Accuracy Impact

```
Base accuracy = scout.accuracy attribute (1-99)
Chief Scout bonus = +10 to all scouts on team
Focus bonus = +5 if scout specializes in that position
Familiarity bonus = +5 if scout has scouted this conference before (2nd year+)
Final evaluation accuracy = min(99, base + bonuses)
```

---

## 9. Data Model Summary

### New Models

| Model | Purpose |
|-------|---------|
| CollegeProspect | Draft-eligible player with hidden + revealed attributes |
| ScoutReport | Individual scout's evaluation of a prospect |
| BigBoardEntry | Player's ranking/tier/flags for a prospect |
| DraftResult | Record of who picked whom and at what pick |
| MockDraft | Media's predicted draft order |

### Modified Models

| Model | Changes |
|-------|---------|
| Scout | Add `assignedConferences`, `focusPositions`, `evaluationsThisSeason` |
| Career | Add `bigBoard: [BigBoardEntry]`, `draftHistory: [DraftResult]` |
| DraftPick | Already exists — add link to CollegeProspect |

---

## 10. UI Screens

| Screen | Purpose | Priority |
|--------|---------|----------|
| **ScoutingHubView** | Main scouting dashboard — assignments, reports, progress | HIGH |
| **ProspectListView** | Browsable/filterable list of all prospects | HIGH |
| **ProspectDetailView** | Individual prospect deep-dive (revealed info only) | HIGH |
| **BigBoardView** | Tier-based rankings with drag-and-drop | HIGH |
| **CombineResultsView** | Combine drill results table | MEDIUM |
| **DraftView** | War room experience — pick-by-pick | CRITICAL |
| **DraftResultsView** | Post-draft summary and grades | MEDIUM |
| **ScoutReportView** | Individual scout report detail | LOW |
| **MockDraftView** | Media mock draft display | LOW |

---

## 11. Implementation Phases

### Phase 1: Prospect Generation (HIGH)
1. Create CollegeProspect model
2. Create ProspectGenerator that creates ~350 draftable prospects per year
3. Generate college stats, true attributes, personalities
4. Wire into LeagueGenerator for initial season

### Phase 2: Scouting Pipeline (HIGH)
5. Create ScoutReport model
6. Implement weekly scout report generation during regular season
7. Create scouting assignment UI (regions, positions)
8. Implement information reveal by phase (college → combine → pro day → workout)
9. Scout accuracy affects revealed data quality

### Phase 3: Big Board (HIGH)
10. Create BigBoardEntry model
11. Implement auto-ranking by scouted grade + position value
12. Build tier-based UI with manual overrides
13. Position-specific sub-boards
14. Need-based recommendations

### Phase 4: Draft Night (CRITICAL)
15. Build war room UI
16. Implement pick-by-pick flow with AI team decisions
17. Trade offer system during draft
18. Media commentary and grades
19. UDFA signing post-draft

### Phase 5: Mock Drafts & Competition (MEDIUM)
20. Generate mock drafts at 3 points in season
21. Team interest tracking
22. Pre-draft trade market

### Phase 6: Integration (HIGH)
23. Wire drafted players into team rosters
24. Connect scouting phases to season calendar
25. First-season special case (pre-scouted prospects)
26. Next-year prospect class preview (2 classes visible)

---

## 12. Balance Considerations

### Scout Staffing vs Quality

| Staff Level | Coverage | Accuracy | Cost |
|-------------|----------|----------|------|
| 6 scouts (full) | ~1800/3000 prospects | High | ~$800K total |
| 3 scouts (budget) | ~900/3000 prospects | Medium | ~$350K total |
| 1 scout (minimal) | ~300/3000 prospects | Low | ~$100K |

Trade-off: More scouts = better information = better draft picks. But scouts cost money from coaching budget.

### Draft Value vs Risk

- Top-rated prospects (Tier 1-2): High floor, high ceiling, everyone wants them
- Mid-rated (Tier 3-4): Moderate risk, where value is found
- Late-rated (Tier 5-6): High bust rate but occasional stars
- A good scouting department finds Tier 3-4 players who are actually Tier 1-2 talent

### First Season Balance

New GM starts with basic scouting (as if previous staff did the work). This means:
- Top ~50 prospects have decent evaluations
- Next ~100 have basic grades
- Remaining ~200 are poorly scouted
- The player's first draft is "inherited" — less control, more uncertainty
- Motivation to invest in scouting staff for Year 2
