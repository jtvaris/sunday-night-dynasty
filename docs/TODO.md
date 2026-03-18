# Dynasty - Todo List

Last updated: 2026-03-18

## Bugs (fix first)

- [ ] #63 BUG: Dashboard task list shows hired coordinators as still Required
- [ ] #83 BUG: Team Selection AFC/NFC toggle only responds to text tap (FIXED - committed)
- [ ] #87 BUG: Hire Coach back button navigates to previous position instead of Coaching Staff
- [ ] #88 BUG: Hired coach not showing in Coaching Staff view after hiring
- [ ] #47 BUG: Coach candidate profile attributes disappear on scroll
- [ ] #69 BUG: Roster view shows "Coming Soon" placeholder

## Already Implemented (these tasks were completed but TaskList wasn't updated)

- [x] #3 Main Menu: Make version number more subtle
- [x] #4 New Career: Center content vertically better
- [x] #5 New Career Step 2: Avatar names too small
- [x] #6 New Career Step 2: Soften MALE/FEMALE headers
- [x] #10 Press Conference: Widen question card on iPad
- [x] #11 Press Conference: Enlarge stat change icons
- [x] #12 Press Conference Summary: Widen content for iPad
- [x] #14 Owner Meeting: Center content and show background better
- [x] #17 Team Overview: Add background image and center content
- [x] #22 Roadmap: Add subtle background image
- [x] #24 Ready to Begin: Make this an epic moment
- [x] #25 Ready to Begin: Add team-specific flavor
- [x] #26 Dashboard: Messages panel could show more items
- [x] #28 Dashboard: Add team record prominently
- [x] #29 Dashboard: Salary Cap mini-card needs visual progress bar
- [x] #30 Dashboard: Consider subtle background texture or image
- [x] #31 Dashboard: Move Division standings to center column in portrait
- [x] #32 Coaching Staff: Add hiring priority indicators
- [x] #33 Coaching Staff: Add background image
- [x] #34 Coaching Staff: 2-column layout for iPad portrait
- [x] #35 Coaching Staff: Show budget impact per hire
- [x] #36 Coaching Staff: HC card should show scheme/style info
- [x] #37 Hire Coach: Add column headers/legend
- [x] #39 Hire Coach: Add sorting and filtering
- [x] #40 Hire Coach: Add background image
- [x] #41 Hire Coach: Budget remaining should be sticky/visible
- [x] #42 Hire Coach: Simplify to one star rating + numeric skill values
- [x] #43 Coach Detail: Add "Hire" button directly in profile sheet
- [x] #44 Coach Detail: Open same detail view when tapping row (done via #56)
- [x] #45 Coach Detail: Add scheme fit and HC compatibility
- [x] #46 Coach Detail: Color-code attribute values (done via #51)
- [x] #48 Coaching Staff: Hired coach row should show more info
- [x] #51 Coach Detail: Color-code attributes and add visual bars
- [x] #52 Coach Detail: Add coach avatar and background image
- [x] #54 Coach Detail: 2-column attribute layout for iPad
- [x] #55 Coach Detail: Add context to attribute values
- [x] #56 Hire Coach: Rework row interaction - tap row opens profile, hire from there
- [x] #58 Hire Scout: Add background image
- [x] #59 Hire Scout: Explain what regional scout regions cover
- [x] #60 Hire Scout: Budget remaining should be sticky on scroll
- [x] #61 Dashboard: Staff card should show filled/total more prominently
- [x] #62 Dashboard: Completed tasks should show checkmarks (already in TimelineTasksPanel)
- [x] #64 Dashboard: Clear next action guidance when tasks are done
- [x] #69 BUG: Roster view shows "Coming Soon" placeholder (fixed)
- [x] #63 BUG: Dashboard task list shows hired coordinators as still Required (fixed)
- [x] #71 Roster View: Update PlayerRowView columns to new order
- [x] #72 Roster View: Add NFL-style position group sections
- [x] #73 Roster View: Color-code PlayerDetailView attributes
- [x] #70 Roster View: Connect to navigation (fixed)
- [x] #81 Dashboard: Remove top timeline strip (removed)

## UI Improvements (pending)

### Main Menu
- [ ] #1 Add Settings option
- [ ] #2 Add "Continue Career" button (code exists, shows when career exists)

### Team Selection
- [ ] #7 Add W-L record to team rows
- [ ] #8 Team Detail: Add QB info and division rivals
- [ ] #9 Explain lock icon

### Intro Sequence
- [ ] #15 Owner Meeting: Expand owner info with practical implications
- [ ] #16 Owner Meeting: Warning quote more personal
- [ ] #20 Team Overview: Show roster age and contract situation summary
- [ ] #21 Team Overview: Coaching Staff "0/13 filled" needs emphasis
- [ ] #18 Team Overview: Add position group strengths breakdown
- [ ] #19 Team Overview: Add context to stats (league averages)
- [ ] #23 Roadmap: Highlight current phase in timeline

### Dashboard
- [ ] #27 Division standings need W-L data

### Coaching Staff
- [ ] #49 Show hiring confirmation/celebration
- [ ] #50 Handle insufficient budget and failed hiring scenarios
- [ ] #66 Add "Lock in Staff" / "Confirm Staff" button
- [ ] #107 Add tabs for Staff / Schemes / Review

### Hire Coach
- [ ] #38 Add scheme fit indicator
- [ ] #53 Coach Detail: Add management actions (Fire, Extend, Promote)
- [ ] #86 Candidate profile sheet should be larger on iPad

### Roster
- [ ] #85 Split Receivers and Tight Ends into separate position groups
- [ ] #89 Show starter/backup indicator in player list
- [ ] #91 Position group grade badges need more contrast
- [ ] #92 Cap info in summary bar should show used/total clearly
- [ ] #93 Contract column "1yr" should highlight expiring contracts
- [ ] #94 Add subtle background image
- [ ] #95 Show Cap Hit instead of/alongside Salary
- [ ] #104 Show position group strength and cap allocation in group headers
- [ ] #74 Ensure landscape layouts for all roster views

### Formation
- [ ] #99 Make field fill more of the screen
- [ ] #100 Enlarge player cards and show more data
- [ ] #101 Color-code player cards by rating
- [ ] #102 Add yard lines and field markings
- [ ] #103 Show position group averages alongside field

## Big Features (need planning/new files)

### Game Systems
- [ ] #76 Coordinator Schemes: Implement 5+5 scheme system (designed, see docs/plans)
- [ ] #67 Coordinator Schemes: Build scheme selection view
- [ ] #77 Press Conference: Implement situational question system (designed)
- [ ] #78 Review Roster Phase: Implement 4-task offseason evaluation flow (designed)
- [ ] #79 Medical Staff: Implement Doctor and Physio with fatigue-injury system (designed)
- [ ] #80 Coaching Budget: Dynamic budget system based on market + owner + success (designed)
- [ ] #82 Salary Cap: Dynamic cap that grows each season
- [ ] #84 Season calendar: Add Pro Bowl before Super Bowl
- [ ] #57 Coaching budget and candidate pool should reflect team wealth

### Roster Features
- [ ] #90 Add comprehensive player stats view
- [ ] #96 Add attribute columns view mode for detailed analysis
- [ ] #97 Add player Form column to main table
- [ ] #98 Multiple analysis view modes (Contracts, Development, Physical, Depth, Needs)
- [ ] #105 Depth Chart: Design comprehensive lineup management system
- [ ] #106 Player Faces: Design and implement player avatar/face system

### Press Conference
- [ ] #13 Dynamic questions based on team situation

## Design Documents

- `docs/plans/2026-03-18-roster-view-design.md` — Roster view hybrid design
- `docs/FUTURE_IMPROVEMENTS.md` — Long-term feature ideas (realistic schemes, advanced scouting, etc.)
