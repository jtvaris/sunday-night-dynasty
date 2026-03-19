---
name: auto-analyze
description: Automated full-game playthrough analysis using Maestro to navigate the iOS simulator, play through the game (create career, hire staff, review roster, scout, draft), take screenshots at every step, and run analyze-app process (visual + game design + decision support) on each screen. Creates todos for all findings.
---

# Auto-Analyze — Automated Game Playthrough & Analysis

## Overview

Uses **Maestro mobile testing CLI** to automatically play through the Dynasty game from start to finish, taking screenshots at every screen and running the full `/analyze-app` analysis process (visual design + game design + decision support). Catches bugs, UI issues, and missing game mechanics automatically.

## Prerequisites

- Maestro CLI: `~/.maestro/bin/maestro` (v2.3.0+)
- iPad simulator booted
- App built and installed
- Export PATH: `export PATH="$PATH:$HOME/.maestro/bin"`

## CRITICAL: Analysis Rules

Every screenshot MUST be analyzed using the `/analyze-app` skill's rules:
1. **Visual Design Analysis** (7 checks)
2. **Game Design Analysis** (5 checks) — EQUALLY IMPORTANT
3. **Decision Support Analysis** — the MOST important check
4. **EVERY finding = a TaskCreate todo** — zero tolerance for missing todos
5. **Completeness verification** after each screen
6. **Bug detection** — if Maestro flow fails or UI behaves unexpectedly, create Bug todo

## Phase 1: Build & Install

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build 2>&1 | tail -3

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl boot 'iPad Pro 13-inch (M5)' 2>/dev/null
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl terminate 'iPad Pro 13-inch (M5)' com.brewcrow.dynasty 2>/dev/null
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install 'iPad Pro 13-inch (M5)' ~/Library/Developer/Xcode/DerivedData/dynasty-arklysztnruxtvfbogjmrinmtdqt/Build/Products/Debug-iphonesimulator/dynasty.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch 'iPad Pro 13-inch (M5)' com.brewcrow.dynasty
```

## Phase 2: Gameplay Flows

Each flow is a YAML file that plays through a section of the game. Write all flows to `/tmp/maestro-flows/`, run each one, take screenshots, and analyze.

### Maestro Command Reference
```yaml
- launchApp                          # Launch/relaunch app
- tapOn: "Button Text"               # Tap visible text
- tapOn:
    id: "accessibilityIdentifier"    # Tap by accessibility ID
- tapOn:
    point: "50%,50%"                 # Tap by coordinates
- inputText: "Hello"                 # Type text
- scroll                             # Scroll down
- scrollUntilVisible:
    element: "Target Text"           # Scroll until element visible
- back                               # Navigate back
- swipeLeft / swipeRight / swipeUp / swipeDown
- waitForAnimationToEnd
- assertVisible: "Expected Text"     # Assert element exists
- assertNotVisible: "Error"          # Assert no errors
- takeScreenshot: /path/to/file      # Capture screenshot
- repeat:
    times: 3
    commands:
      - scroll
```

### Flow A: Fresh Game — New Career Setup

```yaml
# A1: Main Menu
- launchApp → screenshot

# A2: New Career Step 1
- tapOn: "New Career"
- inputText: "Test GM"
- screenshot

# A3: New Career Step 2
- tapOn: "Next"
- tapOn: "The Tactician"  # Select coaching style
- screenshot

# A4: Team Selection
- tapOn: "Choose Your Team"
- screenshot

# A5: Team Detail
- tapOn first team row
- screenshot

# A6: Select team → Intro begins
- tapOn: "SELECT THIS TEAM"
- wait for loading

# A7-A11: Intro Sequence (5 steps)
- screenshot each step
- tapOn: "Continue" between steps
- Press Conference: tap answer options
- Owner Meeting: screenshot
- Team Overview: screenshot + scroll down for draft picks
- Roadmap: screenshot
- Ready to Begin: screenshot
```

### Flow B: Dashboard & Navigation

```yaml
# B1: Dashboard (arrives after intro)
- screenshot

# B2: Dashboard scroll down
- scroll
- screenshot

# B3: Each nav item
- tapOn: "Roster" → screenshot → back
- tapOn: "Staff" → screenshot → back
- tapOn: "Schedule" → screenshot → back
- tapOn: "Standings" → screenshot → back
- tapOn: "Draft" → screenshot → back
- tapOn: "Scouting" → screenshot → back
- tapOn: "Cap" → screenshot → back
```

### Flow C: Coaching Staff — Hire All Coaches

```yaml
# C1: Navigate to Coaching Staff
- tapOn: "Staff" (from dashboard nav)
- screenshot

# C2: Hire Assistant Head Coach
- tapOn: "Assistant Head Coach" vacant row
- screenshot (hire list)
- tapOn first candidate
- screenshot (candidate profile)
- tapOn: "Offer Contract"
- screenshot (confirm hired)
- back to coaching staff

# C3: Hire Offensive Coordinator
- tapOn: "Offensive Coordinator" vacant
- tapOn first candidate → hire
- back

# C4: Hire Defensive Coordinator
- same pattern

# C5: Hire Position Coaches (iterate through all)
- for each vacant position coach: tap → hire first → back

# C6: Hire Medical Staff
- same pattern

# C7: Hire Scouts
- same pattern

# C8: Final Coaching Staff screenshot
- screenshot (all positions filled)

# C9: Lock in Staff
- tapOn: "Lock in Staff & Advance"
- screenshot (confirmation)
- tapOn: "Confirm"
```

### Flow D: Review Roster Phase

```yaml
# D1: Roster Overview (Offense)
- tapOn: "Roster"
- screenshot

# D2: Roster Defense
- tapOn: "Defense"
- screenshot

# D3: Player Detail (tap best player)
- tapOn first player row
- screenshot
- scroll → screenshot (attributes section)
- back

# D4: Formation View
- tapOn: "Formation"
- screenshot
- tapOn: "Defense" filter → screenshot
- back to List View

# D5: Depth Chart
- navigate to Depth Chart
- screenshot

# D6: Different analysis modes
- tapOn: "Contracts" → screenshot
- tapOn: "Development" → screenshot
- tapOn: "Physical" → screenshot
- tapOn: "Attributes" → screenshot
```

### Flow E: Scouting & Draft Prep

```yaml
# E1: Scouting Hub
- tapOn: "Scouting"
- screenshot (Scout Team tab)

# E2: Prospects tab
- tapOn: "Prospects"
- screenshot

# E3: Prospect Detail
- tapOn first prospect
- screenshot
- tapOn: "Send Scout" → select scout → screenshot
- back

# E4: Big Board
- tapOn: "Big Board"
- screenshot

# E5: Combine Results
- tapOn: "Combine"
- screenshot

# E6: Mock Draft
- tapOn: "Mock Draft"
- screenshot

# E7: Pro Days
- tapOn: "Pro Days"
- screenshot
```

### Flow F: Advance Through Phases

```yaml
# F1: Advance to NFL Combine
- from dashboard: tapOn "Advance to NFL Combine"
- screenshot

# F2: Review Combine Results
- tapOn: "Scouting" → "Combine" tab
- screenshot

# F3: Conduct Interviews
- tapOn: "Prospects" → tapOn prospect → "Conduct Interview"
- screenshot

# F4: Advance to Free Agency
- advance phase
- screenshot

# F5: Advance to Draft
- advance phase
- screenshot (Draft view with war room)
```

### Flow G: Draft Night

```yaml
# G1: Draft starts
- screenshot (war room)

# G2: First pick (AI)
- wait for AI pick
- screenshot (media grade)

# G3: Your pick arrives
- screenshot (on the clock + staff recommendations)

# G4: Make selection
- tapOn: "Make Pick"
- screenshot (selection sheet)
- tapOn first prospect → "Draft"
- screenshot (pick announced + media grade)

# G5: Continue through picks
- let AI picks advance
- screenshot periodically

# G6: Draft summary
- screenshot (end of draft summary sheet)
```

## Phase 3: Run & Analyze Loop

For EACH flow step:

1. **Write the Maestro YAML** to `/tmp/maestro-flows/`
2. **Run it:**
   ```bash
   export PATH="$PATH:$HOME/.maestro/bin"
   maestro test /tmp/maestro-flows/flow_name.yaml --no-ansi 2>&1
   ```
3. **Check for failures** — if Maestro reports FAILED:
   - Create Bug todo with the failure details
   - Try alternative navigation (coordinates, accessibility IDs)
   - Skip if unresolvable and note it
4. **Read the screenshot:**
   ```
   Read /tmp/snd-screenshots/screenshot_name.png
   ```
5. **Run /analyze-app analysis** on the screenshot:
   - Visual Design (7 checks)
   - Game Design (5 checks)
   - Decision Support (most important)
6. **Create TaskCreate for EVERY finding** — no exceptions
7. **Move to next step**

## Phase 4: Error Detection

During each flow, watch for:
- **Crash indicators:** Maestro flow fails with "App not running"
- **Navigation bugs:** Back button goes to wrong screen
- **Missing content:** "No data" or empty views where data should exist
- **Layout bugs:** Overlapping text, truncated content
- **Phase bugs:** Advancing phase skips required tasks

For each error: create a Bug todo with reproduction steps.

## Phase 5: Completeness Audit

After ALL flows complete:

1. **Count total screenshots taken**
2. **Count total findings across all screens**
3. **Count total todos created**
4. **Verify:** findings count == todos count
5. **List any screens that couldn't be reached** (and why)
6. **Summary report:** screens analyzed, bugs found, improvements identified

## Flow Execution Tips

- **If "Continue Career" exists:** Use it instead of creating new career
- **If a tap fails:** Try `scrollUntilVisible` first, then coordinates
- **Between flows:** Re-launch app to ensure clean state
- **For long flows:** Break into smaller YAML files
- **Screenshot naming:** Use `auto_FLOW_STEP` pattern (e.g., `auto_C2_hire_ahc`)
- **Maestro timeout:** Default 30s per command. Add `- extendedWaitUntil` for slow operations

## Screen Inventory Checklist

Track which screens have been analyzed:

- [ ] Main Menu
- [ ] New Career Step 1
- [ ] New Career Step 2
- [ ] Team Selection
- [ ] Team Detail Sheet
- [ ] Intro: Press Conference (4 questions + summary)
- [ ] Intro: Owner Meeting
- [ ] Intro: Team Overview (top + bottom)
- [ ] Intro: Roadmap
- [ ] Intro: Ready to Begin
- [ ] Dashboard (top + bottom)
- [ ] Roster (Offense)
- [ ] Roster (Defense)
- [ ] Roster (Spec Teams)
- [ ] Player Detail (top + bottom)
- [ ] Formation (Offense)
- [ ] Formation (Defense)
- [ ] Depth Chart
- [ ] Coaching Staff (top + bottom)
- [ ] Hire Coach (list + candidate profile)
- [ ] Hire Scout
- [ ] Scouting Hub (Scout Team)
- [ ] Scouting Hub (Prospects)
- [ ] Scouting Hub (Big Board)
- [ ] Scouting Hub (Combine Results)
- [ ] Scouting Hub (Mock Draft)
- [ ] Scouting Hub (Pro Days)
- [ ] Scouting Hub (Next Year)
- [ ] Prospect Detail
- [ ] Schedule
- [ ] Standings
- [ ] Cap Overview
- [ ] Draft (pre-start)
- [ ] Draft (during — war room)
- [ ] Draft (your pick — selection sheet)
- [ ] Draft (post-pick — media grade)
- [ ] Draft Summary
- [ ] Free Agency
- [ ] Trade Center
- [ ] Locker Room
- [ ] News / Inbox
- [ ] Settings
