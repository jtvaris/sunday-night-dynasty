---
name: auto-analyze
description: Automated screen-by-screen app analysis using Maestro to navigate the iOS simulator, take screenshots, and run the analyze-app process on every screen without manual user navigation. Build → Navigate → Screenshot → Analyze → Create todos → Next screen.
---

# Auto-Analyze — Automated Screen Analysis

## Overview

Uses **Maestro mobile testing CLI** to automatically navigate through every screen in the Dynasty app, take screenshots, and run visual + game design analysis on each one. No manual user navigation needed.

## Prerequisites

- Maestro CLI installed: `~/.maestro/bin/maestro`
- iPad simulator booted with app installed
- App built and ready

## Process

### Phase 1: Build & Install

```bash
# Build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)' build 2>&1 | tail -3

# Boot + Install + Launch
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl boot 'iPad Pro 13-inch (M5)' 2>/dev/null
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install 'iPad Pro 13-inch (M5)' ~/Library/Developer/Xcode/DerivedData/dynasty-arklysztnruxtvfbogjmrinmtdqt/Build/Products/Debug-iphonesimulator/dynasty.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch 'iPad Pro 13-inch (M5)' com.brewcrow.dynasty
```

### Phase 2: Create Maestro Flows

Create YAML flow files in `/tmp/maestro-flows/` for each screen navigation path.

**Important Maestro commands:**
```yaml
# Tap on text
- tapOn: "New Career"

# Tap on accessibility label
- tapOn:
    id: "accessibilityIdentifier"

# Enter text
- inputText: "John Doe"

# Scroll down
- scroll

# Wait for element
- assertVisible: "Choose Your Team"

# Take screenshot
- takeScreenshot: /tmp/snd-screenshots/screen_name

# Go back
- back

# Swipe
- swipeLeft
- swipeRight
- swipeUp
- swipeDown

# Wait
- waitForAnimationToEnd
```

### Phase 3: Navigation Flows

Define flows for each screen path. Run each flow, take screenshot, then analyze.

**Flow 1: Main Menu**
```yaml
appId: com.brewcrow.dynasty
---
- launchApp
- waitForAnimationToEnd
- takeScreenshot: /tmp/snd-screenshots/auto_mainmenu
```

**Flow 2: New Career Step 1**
```yaml
appId: com.brewcrow.dynasty
---
- launchApp
- tapOn: "New Career"
- waitForAnimationToEnd
- takeScreenshot: /tmp/snd-screenshots/auto_newcareer_step1
```

**Flow 3: New Career Step 2**
```yaml
appId: com.brewcrow.dynasty
---
- launchApp
- tapOn: "New Career"
- inputText: "Test GM"
- tapOn: "Next"
- waitForAnimationToEnd
- takeScreenshot: /tmp/snd-screenshots/auto_newcareer_step2
```

**Flow 4: Team Selection**
```yaml
appId: com.brewcrow.dynasty
---
- launchApp
- tapOn: "New Career"
- inputText: "Test GM"
- tapOn: "Next"
- tapOn: "Choose Your Team"
- waitForAnimationToEnd
- takeScreenshot: /tmp/snd-screenshots/auto_teamselection
```

Continue creating flows for each screen...

### Phase 4: Run Flows & Analyze

For each flow:

1. **Run Maestro flow:**
```bash
export PATH="$PATH:$HOME/.maestro/bin"
maestro test /tmp/maestro-flows/flow_name.yaml
```

2. **Read screenshot:**
```
Read /tmp/snd-screenshots/auto_screenname.png
```

3. **Run analyze-app analysis** (visual + game design + decision support)

4. **Create todos for ALL findings**

5. **Move to next flow**

### Phase 5: Existing Career Screens

For screens that require an existing career (Dashboard, Roster, etc.):

1. Start a new career via Maestro (select team, go through intro)
2. OR use "Continue Career" if a saved career exists
3. Navigate to each screen from the dashboard

**Dashboard flow:**
```yaml
appId: com.brewcrow.dynasty
---
- launchApp
- tapOn: "Continue Career"
- waitForAnimationToEnd
- takeScreenshot: /tmp/snd-screenshots/auto_dashboard
```

**Roster flow:**
```yaml
appId: com.brewcrow.dynasty
---
- launchApp
- tapOn: "Continue Career"
- tapOn: "Roster"
- waitForAnimationToEnd
- takeScreenshot: /tmp/snd-screenshots/auto_roster
```

### Running the Full Suite

```bash
export PATH="$PATH:$HOME/.maestro/bin"
mkdir -p /tmp/snd-screenshots /tmp/maestro-flows

# Write all flow files
# Run each flow and capture screenshots
for flow in /tmp/maestro-flows/*.yaml; do
    maestro test "$flow" --no-ansi 2>&1 | tail -3
done
```

Then read each screenshot and run analysis.

## Rules

- All analyze-app rules apply (mandatory todos, completeness verification)
- Take both portrait AND landscape screenshots where relevant
- If Maestro can't find an element, try accessibility identifiers or coordinates
- If a flow fails, skip to next and note the failure
- After all screens analyzed, do the completeness audit
