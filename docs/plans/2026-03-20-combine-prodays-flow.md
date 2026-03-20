# Combine & Pro Days Flow Overhaul

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure the NFL Combine into a multi-step guided experience with required interviews, and add a new Pro Days & Workouts phase between Free Agency and Draft.

**Architecture:** The combine phase keeps its SeasonPhase enum value but gains sub-steps enforced via required tasks with blocking dependencies. A new `proDays` SeasonPhase is inserted between `freeAgency` and `draft`. Task unlocking is dynamic (tasks appear locked until prerequisites complete).

**Tech Stack:** SwiftUI, SwiftData, existing TaskGenerator/WeekAdvancer/ScoutingEngine infrastructure.

---

## ⚠️ PARALLEL EXECUTION — Coordination with Free Agency Plan

This plan runs in parallel with `docs/plans/2026-03-20-free-agency-flow.md`. The plans share these files:

| Shared File | This Plan Uses | FA Plan Uses |
|-------------|---------------|--------------|
| `TaskGenerator.swift` | `combineTasks()`, `proDaysTasks()`, `generateTasks()` switch | `freeAgencyTasks()` |
| `CareerShellView.swift` | Combine + ProDays completion checks, navigation | FA completion checks, FA routing |
| `CareerDashboardView.swift` | ProDays phase display, locked task icon | FA sub-step display |
| `WeekAdvancer.swift` | `phase(after:)` order, `.proDays` case | FA state reset in `.combine` case |
| `NewsGenerator.swift` | Combine + ProDays news | FA media |

### Execution Rules

1. **Tasks 1-3 of THIS plan MUST complete before FA plan Task 8** (both modify TaskGenerator, CareerShellView, CareerDashboardView)
2. **After Task 3 is committed**, create a file `docs/plans/.combine-tasks-1-3-done` as a signal
3. **Tasks 4-8 have NO conflicts** with FA plan — can run freely in parallel
4. **If you encounter merge conflicts**: run `git pull --rebase` to get the other session's changes, then resolve

### How to check if FA plan is ahead of you

```bash
# Check if FA plan has committed changes to shared files
git log --oneline --all -- dynasty/dynasty/Engine/Simulation/TaskGenerator.swift | head -5
```

If you see FA commits on shared files, pull them first before modifying those files.

---

## Current Flow
```
reviewRoster → combine → freeAgency → draft
```

## Target Flow
```
reviewRoster → combine (3 required sub-steps) → freeAgency → proDays → draft
```

### Combine Sub-Steps (within single phase):
1. **Setup & Send** — Set scout focus, send to combine (REQUIRED)
2. **Review Results** — View combine data, media reactions, update board (REQUIRED, unlocks after 1)
3. **Interviews** — Select & conduct interviews, review report (REQUIRED, unlocks after 2)

### Pro Days Phase (new SeasonPhase):
1. **Assign scouts to Pro Days** (REQUIRED)
2. **Review Pro Day results** (REQUIRED)
3. **Conduct personal workouts** (optional)
4. **Final board review** (optional)
→ "Advance to Draft"

---

## Task 1: Add `proDays` SeasonPhase

**Files:**
- Modify: `dynasty/dynasty/Domain/Enums/SeasonPhase.swift`
- Modify: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:1045-1063` (phase order)

**Step 1: Add enum case**

In `SeasonPhase.swift`, add `proDays` between `freeAgency` and `draft`:

```swift
enum SeasonPhase: String, Codable, CaseIterable {
    case proBowl         = "ProBowl"
    case superBowl       = "SuperBowl"
    case coachingChanges = "CoachingChanges"
    case reviewRoster    = "ReviewRoster"
    case combine         = "Combine"
    case freeAgency      = "FreeAgency"
    case proDays         = "ProDays"        // NEW
    case draft           = "Draft"
    case otas            = "OTAs"
    case trainingCamp    = "TrainingCamp"
    case preseason       = "Preseason"
    case rosterCuts      = "RosterCuts"
    case regularSeason   = "RegularSeason"
    case tradeDeadline   = "TradeDeadline"
    case playoffs        = "Playoffs"
}
```

**Step 2: Update phase ordering in WeekAdvancer**

In `WeekAdvancer.swift` `phase(after:)` function (~line 1045):

```swift
case .freeAgency:       return .proDays     // was .draft
case .proDays:          return .draft       // NEW
```

**Step 3: Add proDays case to advanceOffseasonPhase switch**

In `WeekAdvancer.swift` `advanceOffseasonPhase()` (~line 545), add a case for `.proDays`:

```swift
case .proDays:
    // Pro days phase — engine work happens in scouting UI
    lastNewsItems = NewsGenerator.generateOffseasonNews(
        phase: .proDays,
        career: career,
        teams: teams
    )
```

Also update any `switch` on SeasonPhase in:
- `TaskGenerator.swift` — add `case .proDays: return proDay Tasks()`
- `CareerDashboardView.swift` — phase display name/description
- `CareerShellView.swift` — any phase-specific UI gating

**Step 4: Build and verify**

```bash
xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' \
  build 2>&1 | grep "error:" | grep -v "linker\|attach DB"
```
Expected: 0 errors (fix any switch exhaustiveness issues)

**Step 5: Commit**

```bash
git add -A && git commit -m "feat: add proDays SeasonPhase between freeAgency and draft"
```

---

## Task 2: Create Pro Days task list in TaskGenerator

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift`

**Step 1: Add proDaysTasks() function**

After `freeAgencyTasks()`, add:

```swift
private static func proDaysTasks() -> [GameTask] {
    [
        GameTask(
            phase: .proDays,
            title: "Assign scouts to Pro Days",
            description: "Send your scouts to college pro days to evaluate prospects in their home environment.",
            icon: "figure.run",
            destination: .scouting,
            isRequired: true
        ),
        GameTask(
            phase: .proDays,
            title: "Review Pro Day results",
            description: "Check pro day performances and compare to Combine results.",
            icon: "chart.bar.doc.horizontal.fill",
            destination: .scouting,
            isRequired: true
        ),
        GameTask(
            phase: .proDays,
            title: "Conduct personal workouts",
            description: "Invite top prospects for private workouts with your coaching staff.",
            icon: "dumbbell.fill",
            destination: .prospectList,
            isRequired: false
        ),
        GameTask(
            phase: .proDays,
            title: "Finalize Big Board",
            description: "Make your final prospect rankings before the draft.",
            icon: "list.number",
            destination: .bigBoard,
            isRequired: false
        ),
    ]
}
```

**Step 2: Wire into generateTasks()**

Find `generateTasks()` function and add the `.proDays` case to the switch:

```swift
case .proDays:
    return proDaysTasks()
```

**Step 3: Add task completion checks in CareerShellView.refreshTaskCompletionStatus()**

```swift
case "Assign scouts to Pro Days":
    // Done if at least 1 pro day has been attended
    let proDesc = FetchDescriptor<CollegeProspect>(
        predicate: #Predicate { $0.proDayCompleted == true }
    )
    if let count = try? modelContext.count(proDesc), count > 0 {
        currentTasks[index].status = .done
    }

case "Review Pro Day results":
    // Done if visited scouting after pro days attended
    if currentTasks[index].status == .inProgress {
        currentTasks[index].status = .done
    }
```

**Step 4: Build and verify**

**Step 5: Commit**

```bash
git commit -m "feat: add Pro Days tasks to TaskGenerator"
```

---

## Task 3: Make Combine tasks sequential with blocking

**Files:**
- Modify: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:366-404`
- Modify: `dynasty/dynasty/UI/Career/CareerShellView.swift` (refreshTaskCompletionStatus)
- Modify: `dynasty/dynasty/UI/Career/CareerDashboardView.swift` (task display)

**Step 1: Make combine tasks required with blocking order**

Update `combineTasks()`:

```swift
private static func combineTasks() -> [GameTask] {
    [
        // Step 1: REQUIRED — must complete before step 2 unlocks
        GameTask(
            phase: .combine,
            title: "Send scouts to Combine",
            description: "Set scout focus and deploy your scouting staff to evaluate prospects.",
            icon: "binoculars.fill",
            destination: .scouting,
            isRequired: true
        ),
        // Step 2: REQUIRED — unlocks after step 1, blocks step 3
        GameTask(
            phase: .combine,
            title: "Review Combine results",
            description: "Study 40-yard times, bench press, and drill results. Check media reactions.",
            icon: "chart.bar.fill",
            destination: .scouting,
            isRequired: true
        ),
        // Optional: Update board between reviews
        GameTask(
            phase: .combine,
            title: "Update Big Board",
            description: "Rank prospects based on Combine performance and scouting reports.",
            icon: "list.number",
            destination: .bigBoard,
            isRequired: false
        ),
        // Step 3: REQUIRED — unlocks after step 2
        GameTask(
            phase: .combine,
            title: "Conduct prospect interviews",
            description: "Select prospects to interview. Evaluate character, football IQ, and team fit.",
            icon: "bubble.left.and.bubble.right.fill",
            destination: .scouting,
            isRequired: true
        ),
        // Step 4: REQUIRED — unlocks after interviews conducted
        GameTask(
            phase: .combine,
            title: "Review interview report",
            description: "Review coaching staff notes on interviews. Prospect grades updated.",
            icon: "doc.text.magnifyingglass",
            destination: .scouting,
            isRequired: true
        ),
    ]
}
```

**Step 2: Add sequential unlock logic in refreshTaskCompletionStatus()**

In `CareerShellView.swift`, update the combine section:

```swift
// Combine — sequential task unlocking
case "Send scouts to Combine":
    if UserDefaults.standard.bool(forKey: "scoutsSentToCombine") {
        currentTasks[index].status = .done
    }

case "Review Combine results":
    // Locked until scouts sent
    let scoutsSent = UserDefaults.standard.bool(forKey: "scoutsSentToCombine")
    if !scoutsSent {
        currentTasks[index].status = .todo
    } else if currentTasks[index].status == .todo {
        currentTasks[index].status = .inProgress  // Auto-unlock
    }

case "Conduct prospect interviews":
    // Locked until combine results reviewed
    let resultsReviewed = currentTasks.first(where: { $0.title == "Review Combine results" })?.status == .done
    if !resultsReviewed {
        currentTasks[index].status = .todo
    }

case "Review interview report":
    // Locked until interviews conducted
    let interviewsDone = currentTasks.first(where: { $0.title == "Conduct prospect interviews" })?.status == .done
    if !interviewsDone {
        currentTasks[index].status = .todo
    } else if career.interviewsUsed > 0 {
        currentTasks[index].status = .done
    }
```

**Step 3: Add locked task display in CareerDashboardView**

Tasks with `.todo` status where a prerequisite isn't complete should show a lock icon (🔒) and grayed out styling. Find where tasks are rendered in the timeline and add:

```swift
// If task is locked (todo but has unmet prerequisite), show lock
let isLocked = task.status == .todo && isTaskLocked(task)
```

**Step 4: Build and verify**

**Step 5: Commit**

```bash
git commit -m "feat: sequential combine tasks with blocking dependencies"
```

**Step 6: Signal to FA plan that shared files are safe**

```bash
touch docs/plans/.combine-tasks-1-3-done
git add docs/plans/.combine-tasks-1-3-done
git commit -m "signal: combine tasks 1-3 done — FA plan can start Task 8"
```

> **IMPORTANT**: This signal file tells the parallel FA session that TaskGenerator, CareerShellView, and CareerDashboardView now have the combine/proDays infrastructure. The FA session can safely add its cases alongside yours.

---

## Task 4: Create Interview Selection View

**Files:**
- Create: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift`
- Modify: `dynasty/dynasty/UI/Scouting/ScoutingHubView.swift` (add Interviews tab)

**Step 1: Create InterviewSelectionView**

A new view where the player selects which prospects to interview (batch selection), then taps "Conduct Interviews":

```swift
struct InterviewSelectionView: View {
    let career: Career
    @Environment(\.modelContext) private var modelContext

    @State private var selectedProspectIDs: Set<UUID> = []
    @State private var prospects: [CollegeProspect] = []
    @State private var showResults = false
    @State private var interviewResults: [(prospect: CollegeProspect, personality: String, footballIQ: Int, notes: [String])] = []

    private let maxInterviews = 60

    var remainingSlots: Int {
        maxInterviews - career.interviewsUsed
    }

    var body: some View {
        // List of combine-invited prospects with checkboxes
        // "Selected: X / Y remaining" header
        // "Conduct Interviews" button at bottom
        // After conducting → show InterviewReportView
    }
}
```

Key features:
- Show only combine invitees who haven't been interviewed yet
- Multi-select with checkboxes (max = remainingSlots)
- Position filter
- Sort by draft projection
- Show existing scout grade to help player decide
- "Conduct X Interviews" button → runs all interviews → shows report

**Step 2: Create InterviewReportView**

After interviews complete, show a summary with coaching staff comments:

```swift
struct InterviewReportView: View {
    let results: [(prospect: CollegeProspect, personality: String, footballIQ: Int, notes: [String])]

    var body: some View {
        // Each prospect: name, revealed personality, football IQ, character notes
        // Color-coded: green flags, red flags, neutral
        // "Complete Review" button to dismiss
    }
}
```

**Step 3: Add "Interviews" tab to ScoutingHubView**

Add a new case to `ScoutingTab`:
```swift
case interviews = "Interviews"
```

Wire it in `tabContent`:
```swift
case .interviews:
    InterviewSelectionView(career: career)
```

Only show the tab during `.combine` phase.

**Step 4: Build and verify**

**Step 5: Commit**

```bash
git commit -m "feat: interview selection view with batch interviews and report"
```

---

## Task 5: Add media indicators to prospect lists

**Files:**
- Modify: `dynasty/dynasty/UI/Scouting/ProspectListView.swift`
- Modify: `dynasty/dynasty/UI/Scouting/BigBoardView.swift`

**Step 1: Show combine media mentions on prospect rows**

After combine results, prospects with `combineMediaMention` should show a media icon:
- 📰 with colored badge: green (Standout), gold (Stock Riser), red (Stock Faller), blue (Surprise)
- Tooltip/popover on tap showing the media headline

```swift
if let mention = prospect.combineMediaMention, !mention.isEmpty {
    Image(systemName: "newspaper.fill")
        .font(.system(size: 10))
        .foregroundStyle(mediaColor(for: prospect))
}
```

**Step 2: Show interview completion indicator**

After interviews, show a speech bubble icon on interviewed prospects.

**Step 3: Build and verify**

**Step 4: Commit**

```bash
git commit -m "feat: media and interview indicators on prospect rows"
```

---

## Task 6: Wire Pro Days phase into dashboard and scouting

**Files:**
- Modify: `dynasty/dynasty/UI/Career/CareerDashboardView.swift` (phase display)
- Modify: `dynasty/dynasty/UI/Scouting/ScoutingHubView.swift` (pro day tab behavior)
- Modify: `dynasty/dynasty/UI/Career/CareerShellView.swift` (highlight tiles)

**Step 1: Dashboard displays Pro Days phase**

Add pro days phase info to the dashboard:
- Phase name: "PRO DAYS & WORKOUTS"
- Phase month: "Apr"
- Show task list for pro days

**Step 2: Pro Days tab prominent during proDays phase**

In ScoutingHubView, auto-select the "Pro Days" tab when `career.currentPhase == .proDays`.

**Step 3: "START DRAFT" button**

When all required pro day tasks complete, show a prominent "Start Draft" advance button (same pattern as other phase advance buttons).

**Step 4: Build and verify**

**Step 5: Commit**

```bash
git commit -m "feat: wire Pro Days phase into dashboard and scouting UI"
```

---

## Task 7: News/media integration for combine and pro days

**Files:**
- Modify: `dynasty/dynasty/Engine/News/NewsGenerator.swift`
- Modify: `dynasty/dynasty/UI/Career/CareerDashboardView.swift` (inbox)

**Step 1: Generate combine news items**

After combine results, generate inbox messages:
- "Combine Standouts" — top performers list
- "Stock Risers" — players who improved their stock
- "Surprise Performances" — unexpected results

**Step 2: Generate pro day news**

After pro day attendance, generate news about notable performances.

**Step 3: Build and verify**

**Step 4: Commit**

```bash
git commit -m "feat: combine and pro day news/media inbox messages"
```

---

## Task 8: Final verification and polish

**Step 1: Full flow test**

Walk through the entire flow:
1. Enter Combine phase → see "Send scouts" as only available task
2. Set scout focus → Send to combine → task completes
3. "Review Combine results" unlocks → view results, media → complete
4. "Conduct interviews" unlocks → select prospects → conduct → review report
5. "Review interview report" completes → can advance
6. Advance to Free Agency → do FA tasks → advance
7. Enter Pro Days → assign scouts → attend pro days → review results
8. Optional workouts → finalize board
9. "Advance to Draft" → draft begins

**Step 2: Verify phase display names in all relevant views**

Search for hardcoded phase names and ensure proDays has proper display name everywhere.

**Step 3: Build and verify**

**Step 4: Commit**

```bash
git commit -m "polish: combine and pro days flow verification complete"
```

---

## Summary

| Task | Description | Complexity |
|------|-------------|------------|
| 1 | Add `proDays` SeasonPhase | Small |
| 2 | Pro Days task list | Small |
| 3 | Sequential combine tasks with blocking | Medium |
| 4 | Interview Selection + Report views | Large |
| 5 | Media indicators on prospect rows | Small |
| 6 | Wire Pro Days into dashboard/scouting | Medium |
| 7 | News/media for combine + pro days | Medium |
| 8 | Full flow verification | Medium |
