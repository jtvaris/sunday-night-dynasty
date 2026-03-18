# Roster View Design

## Overview

Hybrid roster view combining compact table rows with rich detail profiles. Three view modes (List, Formation, Depth Chart) with offense/defense/special teams tabs and NFL-style position group sections.

## Navigation

Roster is accessed from the top nav bar in CareerShellView. Currently shows a placeholder — needs to be connected to the existing RosterView.swift and related views.

## View Modes

### 1. List View (Default)

**Summary Bar** (always visible at top):
- Player count, healthy/injured, average OVR, cap usage %, roster strength stars

**Tabs**: Offense | Defense | Special Teams

**Sort**: OVR, Position, Age, Salary, Name, Cap Hit

**Position Groups per tab**:

- **Offense**: QB Room (QB) → Backfield (RB, FB) → Receivers (WR, TE) → Offensive Line (LT, LG, C, RG, RT)
- **Defense**: Defensive Line (DE, DT) → Linebackers (OLB, MLB) → Secondary (CB, FS, SS)
- **Special Teams**: Specialists (K, P)

**Group Header** per position group:
```
── QB ROOM ──── Avg: 75  Depth: Deep  Grade: B ──
```
Shows: group name, average OVR, depth status (Deep/Thin/Critical), letter grade.

**Compact Player Row** columns (left to right):
1. Position badge (color by side)
2. Depth indicator: starter/backup/3rd string
3. Player name
4. Age
5. Cap Hit
6. Contract years remaining (final year highlighted yellow)
7. OVR (large, color-coded)
8. Development arrow (Rising/Prime/Declining)
9. Salary
10. Morale icon
11. Health status

**Tap row** → opens full PlayerDetailView.

### 2. Formation View

Existing FormationView.swift — visual football field with player cards at positions. Already built.

### 3. Depth Chart View

Existing DepthChartView.swift — interactive per-position depth management with drag/drop. Already built.

## Player Detail View

Existing PlayerDetailView.swift with enhancements:
- Position-specific attributes prominently displayed (arm strength, route running etc.)
- Color-coded attribute values: green (80+), yellow (60-79), red (<60)
- League average comparison for each attribute
- 2-column layout on iPad for attributes

## Roster Evaluation

Existing RosterEvaluationView.swift — connects to "Review Roster" offseason phase:
- Position group grades
- Expiring contracts
- Overpaid/underpaid players
- Aging veterans
- Cap outlook

## Implementation Notes

Most views already exist in code:
- RosterView.swift — main view with List/Formation/Depth Chart modes
- PlayerRowView.swift — compact row
- PlayerDetailView.swift — full profile
- DepthChartView.swift — depth chart management
- FormationView.swift — field visualization
- RosterSummaryBar.swift — summary bar
- RosterEvaluationView.swift — analysis dashboard

**Primary work needed:**
1. Connect RosterView to CareerShellView navigation (fix placeholder)
2. Update PlayerRowView columns to new order: Pos, Depth, Name, Age, Cap Hit, Contract, OVR, Dev, Salary, Morale, Health
3. Add position group sections (QB Room, Backfield, Receivers, O-Line, D-Line, LBs, Secondary, Specialists)
4. Add group headers with avg OVR, depth status, letter grade
5. Color-code attribute values in PlayerDetailView
6. Add league average comparison to PlayerDetailView
7. Add position-specific attributes display to PlayerDetailView
8. Ensure landscape layout works for all roster views
