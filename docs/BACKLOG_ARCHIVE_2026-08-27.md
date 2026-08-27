# Backlog archive — what the TODO already carried as finished

Generated 2026-08-27 from a source-verified triage of every open `- [ ]` in `TODO.md`.
Twelve agents checked 596 items against the current tree; each verdict below names the
file, symbol or call path that proves it. Nothing here is a judgement call about
priority — only about whether the item was still true.

| verdict | count | share |
|---|---:|---:|
| Already implemented | 269 | 45 % |
| Stale — premise no longer true | 104 | 17 % |
| Genuinely open | 181 | 30 % |
| Needs a device or a human | 22 | 4 % |
| A recorded decision, not a task | 20 | 3 % |

**62 % of the open backlog was not open.**

The cause is structural rather than careless: the file uses one notation — `- [ ]` —
for work, for limitations, and for decisions. A line reading *"reason texts are English
only (intentional)"* is a decision, and it is indistinguishable from unfinished work.
Five months of that and the queue and the history become the same document.

---

## Already implemented

269 items. Each carries the evidence the triage agent read.

### dashboard · 38

- **The dashboard's 'Game Plan' quick chip opens GamePlanView, not the Week Prep screen.**
  - `TODO.md:2578` · bug
  - CareerDashboardView.swift:1224 `QuickAction(icon: "scope", label: "Game Plan", destination: .gamePlan)`; CareerShellView.swift:2107-2114 routes `.gamePlan` to `GamePlanView` (`.gameWeekPrep` is a separate case at :2266).
- **Career Dashboard needs a dominant hero tile so the eye has an entry point instead of a uniform card grid**
  - `TODO.md:2840` · design
  - CareerDashboardView.swift:1029 — `centerTilesGrid` now opens with `phaseHeroCard` (phase-switched, CareerDashboardView.swift:4317-4351), drawn by `phaseCardBase` as a full-width, minHeight 160pt accent-gradient card with a 22pt heavy headline (:4353-4390). Secondary tiles are demoted under two `bandHead` rules — the week's work band then "Your club" (:1039, :1044).
- **Dashboard tile header icons should be neutral, with accent colour reserved for the 1-2 tiles that need attention**
  - `TODO.md:2841` · design
  - CareerDashboardView.swift:5390 — `DashboardTile.headerInk` is `Color.textSecondary` unless `highlighted`; the doc comment above it (:5373-5382) records the fix ("twenty-eight gold objects in the grid alone"). `currentPhaseHighlightedTiles` (:3915-3938) returns only the 1-2 tiles the current phase makes live.
- **The Owner/Morale/Media/Legacy status strip should not be the brightest cluster on the dashboard**
  - `TODO.md:2845` · design
  - CareerDashboardView.swift:1044-1046 — `satisfactionScoresRow` now sits below the hero card, the quick-action bar and the whole work band, under the "Your club" band head. `satisfactionCard` (:3630-3655) renders at `DSType.Size.body` value / `.caption` label in a plain `backgroundSecondary` capsule — no longer the largest cluster, and no longer top-right.
- **The left task rail rendered low-contrast grey on dark grey, hiding the most decision-relevant element**
  - `TODO.md:2846` · design
  - TimelineTasksPanel.swift:539-541 — an actionable task title is `Color.textPrimary` at `DSType.Size.body`; `textTertiary` is used only for done/locked rows. The NEXT chip is gold-filled (:546-552), the Required chip danger-filled (:568-576), and every row carries a `textTertiaryReadable` cost→unlock sentence (:613-617).
- **The Team tile's unlabelled green progress bar read as "85% of season done" on an 0-0 team**
  - `TODO.md:2847` · bug
  - That bar was `ownerSatisfactionBar`, and it was deleted with #175 — CareerDashboardView.swift:3675-3678 ("`ownerSatisfactionBar` removed with #175. Its one caller was the Team tile") and the tile's own note at :2278-2282. `teamTile` (:2287-2320) now prints club, record, and a division rank that is suppressed entirely while `isPreSeasonNoGamesPlayed`.
- **Position Grades letter chips were too small for the +/- modifiers to read at iPad distance**
  - `TODO.md:2850` · design
  - CareerDashboardView.swift:2942-2958 — `gradeButton` renders the letter at `DSType.Size.body` bold inside a fixed 26x32 cell (its comment records the old "roughly 14x17 pt" glyph), and the grid is split into two columns via `leftCol`/`rightCol` (:2878-2890) with an S/D legend under it (:2894-2900).
- **An incomplete coaching staff should be obvious at a glance from the Staff tile, not a single easy-to-miss pill**
  - `TODO.md:2851` · design
  - CareerDashboardView.swift:3917 — `currentPhaseHighlightedTiles` returns `["Staff"]` in `.coachingChanges`, which makes `DashboardTile` stroke the whole card in 1.5pt accentGold plus an ACTIVE pill (:5430-5437). `coordinatorRow` prints VACANT in `Color.warning` bold (:2514-2517), and `coachingChangesHeroCard` heads the column with "Required seats vacant: OC, DC" in warning amber. The "RETIRED" pill the item describes no longer appears anywhere in the file.
- **Dashboard columns looked unintentionally asymmetric — pick a 50/50 grid or an explicit hero+rail split**
  - `TODO.md:2855` · design
  - Both. CareerDashboardView.swift:1002-1005 — `tileColumns` is two equal `GridItem(.flexible())` entries, so every tile grid is 50/50. The page-level split is now explicit: `hubLayout` (:766-800) is a fixed `TimelineTasksPanel.railWidth` = 300pt rail (TimelineTasksPanel.swift:57) plus a `maxWidth: .infinity` work column, divided by a `Divider()`.
- **Key Players rows clipped names into the OVR badge with no column alignment**
  - `TODO.md:2856` · design
  - CareerDashboardView.swift:2836-2852 — `keyPlayerRow` is a fixed 28pt tag column, then the name at `lineLimit(1)` (truncates with an ellipsis rather than colliding), then `Spacer()`, then the OVR. The Spacer pins every OVR to the same trailing edge, so the badges align as a column.
- **The Salary Cap progress bar was amber at healthy cap levels — it needs a green/amber/red ramp**
  - `TODO.md:2857` · design
  - CareerDashboardView.swift:3716-3720 — `capBarColor` is `success` at or below 80% used, `warning` above 80%, `danger` above 90%. `availableCapColor` (:3725-3729) uses the same thresholds so the figure and the bar cannot disagree, and a CAP TIGHT chip appears above 85% (:2640-2653).
- **Numeric values across the dashboard need one typography scale rather than ad-hoc sizes**
  - `TODO.md:2860` · design
  - DSTokens.swift:125-148 — `DSType.Size` is a documented 11-rung ladder (micro 10 / caption 11 / footnote 12 / body 14 / callout 16 / title3 18 / title2 22 / title1 28 / display 36 / hero 48) with a per-rung usage note. Every dashboard tile now reads off it, and departures need an explicit `// ds-lint:allow(font)` pragma (e.g. MainMenuView.swift:195).
- **Label placement was inconsistent across the four status tiles — some above the number, some below**
  - `TODO.md:2861` · design
  - CareerDashboardView.swift:3630-3645 — all four tiles are built by one `satisfactionCard`, a single VStack in fixed order: icon, value, label. Owner, Morale, Media and Legacy cannot differ.
- **Some dashboard cards had no icon and others used generic ones that did not say what the card was**
  - `TODO.md:2864` · design
  - CareerDashboardView.swift:5384 — `DashboardTile.icon` is a non-optional `String`, so no tile can render iconless. Each declares a distinct, apt symbol: shield=Team (:2288), person.3=Roster (:2337), person.2=Staff (:2369), magnifyingglass=Scouting (:2535), dollarsign.circle=Cap (:2633), heart=Locker Room (:2724), chart.bar=Grades (:2860), clock.badge.exclamationmark=Contracts (:3081), building.2=Owner (:3195), tray.full=Messages (:826).
- **The Scouting tile showed one line of prompt text with no counts, preview or way in**
  - `TODO.md:2867` · feature
  - CareerDashboardView.swift:2529-2620 — the tile is a `NavigationLink` to `ScoutingHubView` (the CTA) and its body now prints the #1 prospect with position and college, the class split ("N total / OFF / DEF / ST"), and "Scouted N of M" over a gold progress bar keyed on `scoutedOverallGrade`. The bare prompt survives only in the genuinely empty branch, before a draft class exists.
- **The Messages panel had a fixed tall height that left dead space under a short inbox**
  - `TODO.md:2869` · design
  - CareerDashboardView.swift:803-805 — the 240pt `minHeight` floor was removed ("with a single message the 240pt floor left ~180pt of empty panel under it"). The empty branch is now a shared `EmptyStateView` that carries its own height and says what will arrive (:903-909); a populated panel caps at 5 rows plus a "N more messages" link (:912-927).
- **The Division standings preview showed four meaningless 0-0 rows before Week 1**
  - `TODO.md:2870` · design
  - CareerDashboardView.swift:2138-2152 — when `isPreSeasonNoGamesPlayed` the section renders `lastSeasonDivisionTable` (if any club has a finished season) or `preSeasonCountdownRow`, never the 0-0 table. The `scheduleSection` merged directly beneath it (:797-803) carries the upcoming fixture.
- **The task rail never said which task unlocks the next phase or what that next phase is**
  - `TODO.md:2874` · feature
  - TimelineTasksPanel.swift:922-940 — `advanceButtonLabel` names the milestone directly ("Advance to Combine"). When the advance is blocked, `advanceSection` (:809-820) prints "Required: <task title>" plus "N more required tasks after it", and every row's `detailLine` (:669-681) opens "Required to advance · …" or, for a locked row, "Locked · finish "<prereq>" first".
- **The coaching-changes phase read as a flat checklist with no sense of what each hire is worth**
  - `TODO.md:2875` · feature
  - `coachingChangesHeroCard` (CareerDashboardView.swift, in `phaseHeroCard`) heads the column with vacant required seats, coaching budget left, and expiring coach contracts. `coordinatorRow` (:2502-2528) prints the scheme each coordinator brings. The Review Schemes task opens `schemeFitAnalysis` (:6483-6570), which shows Coach Fit %, Roster Fit % ("N/M starters familiar") and a scored best-alternative scheme — the "+X% playbook fit" the item asked for.
- **The Contracts tile listed expiring names with no timing, no priority order and no way through**
  - `TODO.md:2877` · feature
  - CareerDashboardView.swift:3077-3160 — timing: `isContractActionWindow` (:3055-3063) plus the copy "Re-sign window opens in the offseason". Priority: a `contractsHighPriority` HIGH PRIORITY badge (:3084-3096), a "N of M expiring" denominator, rows sorted by OVR, and a warning triangle on any player at OVR 80+ (:3163-3168). CTA: each row deep-links to the cap screen and a "View all in Salary Cap" link closes the tile (:3143-3156).
- **Position Grades was purely descriptive with no alert on weak groups and nothing to tap**
  - `TODO.md:2878` · feature
  - CareerDashboardView.swift:2872-2876 — the weakest group is flagged NEED, but only in absolute terms (starter OVR under 70), so a strong roster carries no false alarm. Every grade letter is a `gradeButton` (:2942-2958) opening a popover with league-percentile copy — "bottom 15% league-wide / Major roster need — prioritize in FA or the draft" (:3000-3040). Not implemented, and not needed for the item's ask: jumping from the tap into that position group on the roster.
- **The dashboard's top card is a phase-aware hero with a primary button naming the single next action; a generic "Next Action" card was built and then deliberately removed as a duplicate of the rail's NEXT chip.**
  - `TODO.md:2882` · feature
  - dynasty/dynasty/UI/Career/CareerDashboardView.swift:1028-1033 (phaseHeroCard first in the column), :4910-4915 (heroPrimaryButton titled from the live stage), and the removal record at :3581-3589; the rail's single NEXT marker is TimelineTasksPanel.swift:545-552.
- **The dashboard states the in-game phase and week on screen — a gold live-phase row with a NOW pill and month range in the rail, plus a week ladder during the season.**
  - `TODO.md:2883` · design
  - dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:402-419 (phase title, NOW pill, phaseDate), :491-497 ("Week N" in-season), :1543-1548 ("Feb–Mar" etc.); CareerShellView.swift:513-586 mounts SeasonWeekBandView at the hub.
- **The dashboard carries a phase-aware Quick Actions chip row of three to four shortcuts directly under the hero card.**
  - `TODO.md:2884` · feature
  - dynasty/dynasty/UI/Career/CareerDashboardView.swift:1036 (quickActionBar in the column), :1240-1247 (spread across the width), :1189-1230 (per-phase-group chip sets: Scouting/Big Board/Mock Draft in preDraft, Game Plan/Depth Chart/Development/Injuries in season, etc.).
- **The Owner tile shows the owner archetype, a job-security meter, a pending-demand badge and the primary owner goal with progress, and opens the Owner Meeting.**
  - `TODO.md:2886` · design
  - dynasty/dynasty/UI/Career/CareerDashboardView.swift:3191-3275 — PersonFaceView + archetype, OwnerPersonaEngine.jobSecurity bar, hasPendingOwnerWhim envelope badge, "Primary goal · N of M met" with target progress, pushing OwnerMeetingView.
- **The dashboard Team tile names what its rank ranks and suppresses it entirely before Week 1.**
  - `TODO.md:2891` · bug
  - CareerDashboardView.swift:2308-2316 prints "#N in <conference> <division>" and only when !isPreSeasonNoGamesPlayed. The comment at :2301-2307 records both halves: the pre-Week-1 0-0 tie shuffle and "when the rank IS earned, name what it ranks: a bare '#4' reads just as well as a power ranking, a seed or a draft slot."
- **The offseason rail's Advance button is gold when primary and a neutral disabled fill when gated — never red.**
  - `TODO.md:2892` · design
  - TimelineTasksPanel.swift:912-923 — advanceFill returns Color.controlDisabled when !canAdvance and accentGold (or 10% gold when the weekly game outranks it) otherwise; advanceForeground follows the same three states.
- **Required and optional tasks in the dashboard rail are differentiated three ways: a red "Required" capsule, a filled-vs-hollow status dot, and a "Required to advance ·" vs "Optional ·" sentence prefix.**
  - `TODO.md:3373` · design
  - dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:561-577 (danger capsule), :760-785 (filled danger disc vs hollow tertiary ring), :669-678 (detailLine prefix). "Send scouts to Combine" is also isRequired: false now — TaskGenerator.swift:838-860.
- **The rail's advance-blocked message is a heavy dangerText label with a warning triangle that names the blocking task, not grey body text.**
  - `TODO.md:3374` · design
  - dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:806-819 — Label("Required: \(blocking.title)", systemImage: "exclamationmark.triangle.fill") in Color.dangerText, .heavy, plus an "N more required tasks after it" line. Placement beside the Advance button rather than above the list is a recorded choice (CareerDashboardView.swift:3574-3579).
- **The blocked Advance button paints a genuinely disabled grey and the banner directly above it names the gate.**
  - `TODO.md:3375` · design
  - dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:906-920 (advanceFill returns Color.controlDisabled, advanceForeground Color.textTertiary when !canAdvance, with the token choice explained) and :806-830 (blocking task + AdvanceBlocker title/detail).
- **The Messages section's "View All" is an outlined gold-text capsule, not a gold-filled pill.**
  - `TODO.md:3379` · design
  - dynasty/dynasty/UI/Career/CareerDashboardView.swift:2063-2083 (sectionNavLink: gold text on a Capsule().strokeBorder at 35% gold); the comment at :850-853 quotes this audit note verbatim and calls the change "this fix".
- **Every phase draws its own hero card at the top of the dashboard's centre column with a primary button naming the next action.**
  - `TODO.md:3389` · feature
  - dynasty/dynasty/UI/Career/CareerDashboardView.swift:1028-1033 (phaseHeroCard is the first item in centerTilesGrid), :4315-4352 (a card per SeasonPhase), :4910-4915 (heroPrimaryButton titled from the live stage action).
- **A gated Advance button names its blocker in a persistent banner directly above it.**
  - `TODO.md:3608` · bug
  - TimelineTasksPanel.swift:788-841 — when !canAdvance it draws "Required: <task title>", "<N> more required tasks after it", and the AdvanceBlocker's title plus detail. The same banner is on the Season Guide sheet (CalendarSidebarView.swift:469-491). The tap itself is still inert (.disabled at :869), but the explanation is on screen for the whole blocked phase rather than fired as a toast.
- **The regular-season hero's injuries, streak and opponent lines are all derived and agree with the tiles beside them.**
  - `TODO.md:3615` · bug
  - Hero injuries = players.filter(\.isInjured).count (CareerDashboardView.swift:4621/4648) beside the tile's injuryWeeksRemaining > 0 (:1861); currentStreak needs played games and the badge is gated on count > 1 (:3856-3890, :2316-2320), so an 0-0 record cannot print "W3"; hero and Opponent Scout both read currentWeekFixture (:4607 and :1883, per the #154 note), so "vs TBD" and "Vs —" can only appear together when no fixture exists.
- **Division rank is deterministic — the wins sort carries a UUID tiebreaker so a 0-0 division cannot reshuffle between renders.**
  - `TODO.md:3616` · bug
  - CareerDashboardView.swift:3895-3912, whose #134 comment names this exact symptom ("before Week 1 every team has 0 wins, and without it this sort was an unordered shuffle that moved the badge on every render") and sorts by `$0.wins > $1.wins` then `$0.id.uuidString < $1.id.uuidString`. The same fix is applied to comparablePlayers at PlayerDetailView.swift:3438-3452.
- **Every dashboard quick chip lands on a screen that services its own label; the Battles and Camp Grades chips were removed in favour of their tiles.**
  - `TODO.md:3617` · bug
  - CareerDashboardView.swift:1173-1188 is the gate comment naming Battles ("the chip is gone and the tile is the route") and Camp Grades; the chip lists at :1189-1228 now point Training at .trainingPlan, Mock Draft at .mockDraft and Awards at .history.
- **The advance button is a pinned footer deck below a divider, so it cannot collide with the phase rail — and the deadline row no longer reads "Oct".**
  - `TODO.md:3619` · bug
  - TimelineTasksPanel.swift:134-199 — a VStack of header, Divider, ScrollView, Divider, then advanceSection with its own Color.backgroundPrimary background; no ZStack or overlay is involved. The trade-deadline rail label is now "Wk \(TradeValueEngine.deadlineWeek)" (:1566), changed with a comment about the rows overlapping as a calendar.
- **The dashboard hero and the Opponent Scout tile resolve this week's opponent from one shared fixture lookup**
  - `TODO.md:3667` · bug
  - CareerDashboardView.swift:363-377 — `currentWeekFixture` is "**The one fixture every week-scoped label on this screen names** (#154)", `currentWeekPlayerGame ?? playedThisWeek ?? upcomingGames.first`. The hero reads it at :4607 and the Opponent Scout tile at :1880-1890 ("#154: `currentWeekFixture`, not `upcomingGames.first`"); "vs TBD"/"Vs —" survive only as unresolvable fallbacks.

### coaching · 36

- **The "Recommended" badge sits on the coaching-style title row beside the style name, not next to the effect line.**
  - `TODO.md:2724` · design
  - NewCareerView.swift:1286-1301 — HStack { Text(style.displayName); if isRecommended { Text("Recommended") } }, with the effect text rendered on the following line at :1302-1306.
- **Coaching Style offers exactly five options, all rendered in a non-scrolling stack — the "if only 5, fine" branch is the true one.**
  - `TODO.md:2725` · verification
  - CoachingStyle.swift:4-8 declares five cases; coachingStyleSection (NewCareerView.swift:663-680) ForEach's CoachingStyle.allCases into a plain VStack with no ScrollView.
- **Coaching styles state a concrete gameplay effect instead of an unanchored "+10 <attribute>" badge.**
  - `TODO.md:2726` · design
  - coachingStyleEffect(_:) at NewCareerView.swift:1243-1262 ("+10% play-call accuracy in close-game situations", "-10% penalties and fumbles drawn each game", …), whose doc comment says it "Replaces the previous vague '+10 <Attribute>' badge". Each card additionally prints FranchiseIdentityDeclaration.frontOfficeLine (:1307-1314).
- **Coaching style carries a real trade-off: it seeds a franchise market identity whose asking premium and contact appetite are anti-correlated by construction.**
  - `TODO.md:2732` · balance
  - FranchiseIdentityDeclaration.swift:44-63 — the four-identity table (analytics 1.20/0.88 … aggressive 1.08/1.15) under the heading "No identity may be strictly best"; seed(for:) at :88-96, declared into TradeValueEngine.FranchiseIdentityRegistry at :118-124, and surfaced per card at NewCareerView.swift:1307-1314.
- **The "Recommended" coaching-style badge carries its rationale as a footnote under the card.**
  - `TODO.md:2734` · design
  - NewCareerView.swift:1316-1322 — "Recommended for first-time players: easier learning curve.", commented as preventing the badge from feeling arbitrary.
- **Coach salaries use a power curve that discounts low-OVR candidates harder, widening the visible spread between the cheapest and the best.**
  - `TODO.md:2745` · balance
  - dynasty/dynasty/Data/Import/LeagueGenerator.swift:1632-1644 — `pow(ovrFraction, 1.6)`, commented "lower-OVR coaches get a steeper discount so the visible salary spread widens. OVR ~70 maps to ~50% of spread (vs ~67% linear)"
- **The hire-coach board's name column is flexible rather than fixed-width, and the labels that shared the row were shortened.**
  - `TODO.md:2746` · bug
  - dynasty/dynasty/UI/Staff/HireCoachView.swift:1000 (`.frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)`), 917 ("Fix #55: Larger name area") and 972 ("Fix #59 + #148: shorter labels to avoid truncation")
- **The hire-coach board has the badge legend, a personality filter, role-aware impact estimates and an experience card; only per-season coach W-L history stays deferred.**
  - `TODO.md:2747` · feature
  - dynasty/dynasty/UI/Staff/HireCoachView.swift:741 (legend: TOP 3 / FREE AGENT / flame / Ceiling / VS), 52-53 + 598-629 (#20 personality filter), 1668-1740 (#22 role-aware projected impact, incl. "Projected wins +X/season" for HC/AHC), 1639-1650 (#21 card renamed EXPERIENCE with the note that the sim does not persist per-season coach history yet)
- **The coaching budget line says "Used $0.0M of $27.0M" instead of the contradictory "$0.0M / $27.0M used".**
  - `TODO.md:3037` · design
  - CoachingStaffView.swift:4373 — Text("Used $\(formatBudget(totalCoachSalaryUsed))M of $\(formatBudget(coachingBudget))M"); the scouting and medical lines at 4432 and 4461 use the same phrasing.
- **The staff screen's 1/2/3 section step badges are legible — dark digits on a filled light disc, not dim outlined circles.**
  - `TODO.md:3038` · design
  - CoachingStaffView.swift:388-395 (staffTierBadge): Color.backgroundPrimary text on a Circle().fill(Color.textSecondary), 18pt, weight .black. The comment at 371-378 records that colouring them by tier was deliberately rejected (gold already has three jobs on this screen).
- **Vacant staff seats are tappable across the whole row, with a gold "Tap to hire" label and a ⊕ affordance.**
  - `TODO.md:3040` · design
  - CoachingStaffView.swift:4858-4924 — vacantRow wraps the entire HStack in a Button with .contentShape(Rectangle()), prints "Vacant — Tap to hire" in Color.accentGold and a plus.circle at the trailing edge; compactVacantCard (4699-4742) adds a dashed gold border. Only the press-state highlight is absent (.buttonStyle(.plain)).
- **The "You (name)" head-coach card only appears for a GM+HC career, so a GM-only save never sees itself listed as the tactician.**
  - `TODO.md:3047` · design
  - CoachingStaffView.swift:1911-1921 gates playerAsHeadCoachRow behind career.role == .gmAndHeadCoach and falls through to the hired-HC card or headCoachVacantRow otherwise; CareerRole.swift:3-6 has the separate .gm case. The card itself labels the role "GM & Head Coach" (4544).
- **The staff screen shows hiring order as an explicit stepper — "Hiring — step N of 5" over five numbered rungs.**
  - `TODO.md:3048` · feature
  - CoachingStaffView.swift:3940-3960 (StaffTier), 4002-4012 (currentTier / hiringHeadline) and 4084-4107 (hiringBand, a DSSlatBand whose rungs carry done/current/future state and open the next vacancy on tap). The vacant HC row also carries a "HIRE FIRST" capsule (4830-4844).
- **The hire flow previews what a signing leaves in the budget before you commit.**
  - `TODO.md:3049` · feature
  - HireCoachView.swift:2144 — the Offer Contract button prints "at $X/yr · Budget after: $Y M"; the negotiation panel repeats it at 2698-2701 (budgetAfterHire, computed at 1560), and the offer-assessment copy at 2905-2914 quotes what is left after the deal.
- **The staff screen marks which vacancy to fill next rather than showing 23 equal chairs.**
  - `TODO.md:3052` · feature
  - CoachingStaffView.swift:4002-4004 — currentTier is the first rung with a hole; hiringSlat (4017-4072) gives it DSSlat.State.current while later rungs are .future, and hiringBand's onSelect (4098-4103) opens the first job in orderedVacancies for that rung.
- **The hire-list filter row's ambiguous "Colors" toggle is now a labelled "Legend" button with a question-mark icon.**
  - `TODO.md:3059` · design
  - HireCoachView.swift:636-651 — Button toggling showRatingLegend, labelled "Legend" with Image(systemName: "questionmark.circle"); it opens the rating-colour + badge legend at 718-746.
- **The hire table's column headers are spelled out and sortable — the ambiguous "Sav" and "Pers" abbreviations are gone.**
  - `TODO.md:3060` · design
  - HireCoachView.swift:780-833 (tableHeaderRow): Name / Age / Scheme / Fit / OVR / Play / Dev / Game / Salary / Val / VS, each a sort button with a direction chevron and gold active state (headerButton, 836-856); Scheme and Val carry info buttons that open explanatory legends.
- **Every numeric column on the hire board is coloured by one rating scale, with a legend that names the bands.**
  - `TODO.md:3061` · design
  - HireCoachView.swift:1042-1063 — OVR, Play, Dev and Game all go through Color.forRating (Theme.swift:117); salary is textSecondary or dangerText on over-budget, Val uses valueScore's own tone. The legend at 718-733 prints ≥80 Elite / 60-79 Solid / 40-59 OK / <40 Poor.
- **Coaching candidates can be pinned and compared side by side from the hire list.**
  - `TODO.md:3068` · feature
  - HireCoachView.swift:76-90 (compareIDs / compareEntries), compareToggle draws a per-row checkbox at 1145-1166, compareTray is the commit bar at 1170-1193 with a live trade-off sentence (1204-1229), and the table itself is CandidateCompareSheet, presented at 536-547.
- **A candidate's personality archetype explains its effects from the list row, without opening the profile.**
  - `TODO.md:3069` · feature
  - HireCoachView.swift:973-991 — the personality chip is a Menu whose content is the archetype name plus the effect lines from personalityEffectsForRow (872-886), e.g. "Player development +8%" for .mentor; the chip carries an info.circle to advertise it.
- **Selecting a coaching candidate shows the budget delta the hire would cause.**
  - `TODO.md:3070` · feature
  - Tapping a row opens CandidateDetailSheet (HireCoachView.swift:498-517), whose offer button prints "Budget after: $X M" (2144) and whose negotiation panel prints the same off budgetAfterHire (1560, 2698-2701). The shortlist tray also quotes the salary gap between two pinned men (1218-1228).
- **The candidate profile's rank badge no longer duplicates the list's wording — "Best Available" is reserved for #1 and ranks 2-3 echo the list's "Top 3".**
  - `TODO.md:3079` · design
  - HireCoachView.swift:2001-2013, with the reasoning recorded inline: "The superlative belongs to #1 only — handing it to three men told a player opening three profiles the same thing three times." The badge now sits beside "Ranked #N of M candidates" (:2000-2007), information the list row (:931-933) does not carry.
- **Scheme Expertise rows can no longer overlap: the name and letter-grade columns are fixed width and the bar takes whatever is left.**
  - `TODO.md:3081` · bug
  - HireCoachView.swift:2547-2564 — name .frame(width: 92), a GeometryReader bar as the only flexible element, grade .frame(width: 24, alignment: .trailing), HStack spacing 8. Overlap is structurally impossible. The list is also narrowed to the schemes the candidate's role installs (relevantSchemeExpertise, :2437-2452).
- **Chemistry on the coach profile no longer reads "Unknown" in a GM+Head Coach career — it is evaluated against the user's own coaching style.**
  - `TODO.md:3083` · bug
  - HireCoachView.swift:1851-1887 — chemistryPrediction takes a userIsHeadCoach / userCoachingStyle branch before the headCoach == nil guard, with strong/weak fit tables per CoachingStyle and copy like "fits well with your Tactician approach". Wired at the call site: :511-512 pass career.role == .gmAndHeadCoach and career.coachingStyle.
- **Verified: the coach profile has a distinct, labelled Scheme Fit block separate from the Scheme Expertise bars.**
  - `TODO.md:3090` · verification
  - HireCoachView.swift:2455-2570 — a card headed "SCHEME FIT" printing "Scheme Compatibility: <label>" with a colour dot and the HC-runs-X / candidate-prefers-Y line, including a GM+HC branch that rates against the installed scheme (:2477-2492) and a no-HC branch (:2496-2529). The "SCHEME EXPERTISE" bars are a divided sub-section beneath it (:2534-2564).
- **Negative projected-contribution figures on the coach profile are flagged: the sign, icon and value all render in danger red.**
  - `TODO.md:3091` · design
  - HireCoachView.swift:1735-1741 — color: devPct >= 0 ? .success : .danger, applied to both the icon and the value in projectedImpactCard (:1774-1786), with the basis stated at :1789 ("Estimates based on attribute deltas vs. league average."). The calc is correct by construction: a below-average developer drags roster development. The contradictory second projection card that printed opposite signs was removed (comment at :1950-1953).
- **The staff row's star rating is captioned "overall · best: X" so it cannot be misread as a rating of the trailing single-attribute number.**
  - `TODO.md:3100` · design
  - dynasty/dynasty/UI/Staff/CoachingStaffView.swift:5279-5299 — the caption exists precisely because the stars (12-attribute mean) and the trailing number (one attribute) use different ladders. No "Good Fit" chip is rendered on any staff row (it survives only in CoachDetailView:999 and HireCoachView's scheme-fit column)
- **The special-teams coordinator's salary band now sits above every position coach band, so the inverted pricing curve is gone.**
  - `TODO.md:3107` · verification
  - dynasty/dynasty/Domain/Enums/CoachRole.swift:143-151 — STC $650K-$3.5M (avg $1.3M) vs position coaches $250-400K min and $1.1-2.0M max. A $200K STC is no longer producible: `LeagueGenerator.salaryForCoach` clamps to `range.min` (Data/Import/LeagueGenerator.swift:1643)
- **Total staff spend against budget is shown as "Used $X M of $Y M" plus a remaining figure and a bar for each pot.**
  - `TODO.md:3113` · design
  - dynasty/dynasty/UI/Staff/CoachingStaffView.swift:4365-4407 (`budgetHeaderView`: used-of-total, remaining, progress bar, plus separate scouting and medical lines) mounted at 1843, and repeated as the Review tab's Budget Summary with a bold Remaining row at 3459-3530
- **The staff review lost its duplicate in-body header — the nav bar names the sheet and the list header is labelled for the population it counts.**
  - `TODO.md:3119` · design
  - CareerDashboardView.swift:5537-5542 ("No header block: it printed 'COACHING STAFF REVIEW' 90 pt below the navigation bar that already says exactly that"); the section label is now "COACHING STAFF" at :5630 with its own rationale, and the count sits beside it at :5640.
- **The staff review's SCHEMES & EXPERTISE heading is no longer sliced off — the sheet sizes to .page on iPad.**
  - `TODO.md:3121` · bug
  - CareerDashboardView.swift:646-653 `.presentationSizing(.page)` with a comment naming the exact defect ("its bottom edge sliced horizontally through the 'SCHEMES & EXPERTISE' heading"); the confirm action is also mirrored into the always-visible toolbar at :5601-5610.
- **The staff review names every empty seat, prices it, offers to fill it, and labels the advance 'Advance Anyway' when required roles are missing.**
  - `TODO.md:3125` · feature
  - CareerDashboardView.swift:6738-6784 `warningsSection` lists missing roles plus the −20% efficiency consequence; `vacantStaffRow` (:5790-5834) is a Button into the hiring list quoting the going rate; the toolbar button reads "Advance Anyway" in warning colour at :5607.
- **The staff review opens with the club's league rank for coaching quality plus club and league means, and each seat gets a league-average benchmark bar.**
  - `TODO.md:3126` · feature
  - CareerDashboardView.swift:5980-6035 `staffQualityStrip` prints "#N of X staffed clubs for coaching quality · avg NN · league NN", fed by `loadLeagueBenchmark()` (:5916-5978); per-seat `benchmarkBar` at :6048-6082.
- **The alternative-scheme recommendation in the staff review is visually promoted when it is materially better.**
  - `TODO.md:3138` · design
  - CareerDashboardView.swift:6517-6567 — an arrow.triangle.swap glyph, warning-coloured heading, a warning-tinted background fill, and a lightbulb "Consider switching — X may be a better fit" line, all gated on significantlyBetter (altTotal - currentTotal > 20).
- **Changing a scheme now states its price before commit, in the units the simulator reads.**
  - `TODO.md:3144` · design
  - F-65: SchemeInstallForecast.swift:101-108 costHeadline ("Scheme fit 61% → 48%, a 13-point drop your starters carry into every snap of next season"), plus curveLine, abandonedLine and installYearLine (:111-135), all computed from CoachingEngine.rosterSchemeFit and VersatilityDevelopmentEngine rather than restated. Shown in the commit bar at SchemeSelectionView.swift:124-138 with a "Keep current" ghost. Residual: the review sheet's own "Consider switching" hint (CareerDashboardView.swift:6552-6561) does not repeat the cost.
- **Changing a scheme is priced before the user commits, using the engine's own arithmetic rather than a re-derived formula.**
  - `TODO.md:3250` · feature
  - SchemeInstallForecast (SchemeInstallForecast.swift:1-80, task F-65) measures fit now vs after by calling CoachingEngine.rosterSchemeFit twice per starter and recovers the learn rate by sampling VersatilityDevelopmentEngine.learnScheme; SchemeSelectionView.swift:502/516 prices the candidate and :557 renders installForecastPanel.

### roster · 31

- **Per-season career stats are persisted and rendered as a "Career Stats by Season" table on the player page.**
  - `TODO.md:2743` · feature
  - dynasty/dynasty/Domain/Models/Player/PlayerSeasonHistory.swift:32-140 (the model the item asked for, incl. a separate postseason line) and UI/Roster/PlayerDetailView.swift:1604-1655 (`careerTableRows` via `CareerTableBuilder`, shared with PlayerStatsView's By Season tab)
- **Season-over-season OVR history exists and the player page shows both the per-season OVR column and a rising / prime / declining arrow.**
  - `TODO.md:2744` · feature
  - dynasty/dynasty/Domain/Models/Player/PlayerSeasonHistory.swift:48-50 (`overallAtEndOfSeason`); UI/Roster/PlayerDetailView.swift:1620-1626 ("the single OVR column carries the trend the old bar chart used to duplicate") and 736-743 / 3352-3361 (trend arrow — note it is derived from `developmentPhase`, i.e. age vs peak, not from the history rows)
- **The roster's analysis lenses are filled, bordered, 44pt capsules — an unselected lens no longer reads as disabled.**
  - `TODO.md:3157` · design
  - RosterView.swift:598-605 now mounts the shared `DSLensTabs`; DSListRow.swift:875-882 — unselected = `textSecondary` on `backgroundTertiary` with a `surfaceBorder` stroke, selected = filled `accentBlue`, both at `minHeight: 44`.
- **The roster's form arrow is a fixed column between Age and OVR — it no longer floats to either side of them.**
  - `TODO.md:3160` · design
  - PlayerRowView.swift:337-350 orders age → `formColumn` → `ovrCell`, each pinned by `dsColumn`; `formColumn` at :640-656 uses `DSListColumn.glyph`, and RosterView.swift:906-908 heads the same three slots in that order.
- **The roster's 'Tap column headers to sort' hint is grey, sits on the header it explains, auto-clears after 5s and is remembered per career.**
  - `TODO.md:3162` · design
  - RosterView.swift:842-856 (`Color.textTertiary`, 5-second dismiss) backed by `@CareerScopedStorage("rosterSortHintSeen")` at :93; the accentGold → textTertiary change landed in a202269, the same batch that recorded the finding.
- **Position-group grades now print the average each letter was cut from, so the letter can be reconciled with the OVRs in the rows below.**
  - `TODO.md:3165` · design
  - RosterView.swift:1815-1845 `gradeReadout` renders "Starters B+ 74 avg · Depth C+ 61 avg", with the comment naming the unreconcilable bare letter as the defect it fixes.
- **A position group's two letter grades are labelled and each carries the average it was cut from.**
  - `TODO.md:3178` · design
  - RosterView.swift:1817-1846 (gradeReadout) prints "Starters B 79 avg · Depth C+ 68 avg" with the words spelled out; calculatePositionGrades (1648-1673) splits the group at the scheme-aware starter count, so the first grade is the starters and the second the men behind them.
- **The position-group header spells out "1 expiring" instead of the cryptic "1 exp" tag.**
  - `TODO.md:3179` · design
  - RosterView.swift:1781-1783 — stateChip("\(expiringCount) expiring", tint: .warning), where expiringCount counts contractYearsRemaining <= 1 (1695-1697).
- **The position-group header's starter ratio names both of its numbers — "1 of 7 starting".**
  - `TODO.md:3180` · design
  - RosterView.swift:1803-1810 (rollupFacts) returns ["\(starterCount) of \(players.count) starting", "\(formattedCap) cap"], with the comment at 1800-1802 recording that a bare "3 / 7" was the one reading on the header that named neither number.
- **Defensive groups separate starters from depth using 3-4 vs 4-3 counts — starters sort to the top on a lighter row background.**
  - `TODO.md:3184` · feature
  - RosterView.swift:1577-1592 (starterCounts(for: scheme) — 1 DT in a 3-4, 2 in a 4-3), 621-648 (starterSortedPlayers puts scheme-aware starters first), 174-178 (starterRowBackground tints starter rows backgroundTertiary). Note the header's own "N of M starting" fact still calls the non-scheme starterCount (1691-1693) while the grade beside it is scheme-aware — a small inconsistency worth its own item.
- **A young high-ceiling player is flagged specifically on the roster row, not lumped in with everyone else.**
  - `TODO.md:3186` · feature
  - PlayerRowView.swift:826-848 — the overview lens prints the headroom left in him as "+N" (truePotential − overall), gold at 10+, green at 6-9, blue at 3-5; the development lens adds the phase word "Rising" (1003-1011). The comment at 828-836 records that this replaced the old ★/↑↑ bucket precisely because it could not rank two developing players.
- **Every roster row carries a colour-coded scheme column for the system that unit actually installs.**
  - `TODO.md:3187` · feature
  - RosterView.swift:608-619 (installedScheme picks the offensive or defensive install per side) feeds PlayerRowView.swift:228-262, whose FIT slot reads Player.schemeFamiliarity for that scheme and tones it ok/neutral/warn at 80/60. The doc comment there records the deliberate choice to report playbook familiarity rather than the full CoachingEngine.rosterSchemeFit blend.
- **The roster shows which players do not know the installed scheme — the FIT slot turns warn below 60.**
  - `TODO.md:3188` · feature
  - PlayerRowView.swift:250-262 — familiarity <60 sets DSStatusPill.Tone.warn, 60-79 neutral, 80+ ok, and a man with no reps in the scheme prints an em dash with the spoken label "he has not taken a rep in this scheme" (229-240).
- **Cut cost is on the roster list itself — the contracts lens leads with DEAD and SAVE columns.**
  - `TODO.md:3191` · feature
  - PlayerRowView.swift:389-415 — capColumn(value: deadCapIfCut, caption: "dead") and capColumn(value: capSavingsIfCut, caption: "save") open the contracts lens, each with a spoken label ("Dead cap if cut" / "Cap saved by cutting") at 455-470.
- **A kicker's row breaks his overall into kick power and kick accuracy, and the sim derives field-goal range from the power rating.**
  - `TODO.md:3204` · feature
  - PlayerRowView.swift:562 — the Position Skills lens returns `[(a.kickPower, "PWR"), (a.kickAccuracy, "ACC")]` for a kicker; PlaySimulator.swift:2689-2692 `fieldGoalRangeYards(for:)` maps power to a 40-50 yard range, consumed by DriveSimulator.swift:147 and LiveGameEngine.swift:1827.
- **Every roster position-group header, Specialists included, prints the group's total cap allocation.**
  - `TODO.md:3206` · design
  - RosterView.swift:1804-1810 — `rollupFacts` returns ["N of M starting", "$X.XM cap"], fed to `DSGroupRollup` at :1760-1764; `totalCapAllocation` sums `annualSalary` at :1703-1706 and `formattedCap` renders it at :1720-1726.
- **Promote the small "Rising" career-trend pill on the player detail header**
  - `TODO.md:3214` · design
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:735-743 — the trend is now a coloured arrow badge overlaid on the 76pt OVR ring (with an accessibility label), and it repeats as the Development card's phase heading at :1335-1341; the small chip at :2950-2961 is now the third copy, not the only one.
- **Stop rendering every key number on the player detail Overview/Contract cards in the same gold**
  - `TODO.md:3216` · design
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:1058-1065 — Salary is now .textSecondary, Years .textPrimary (warning only in the final year), Cap % banded .textSecondary/.warning/.danger at :1254-1259, and OVR/Morale run Color.forRating; gold survives only as the Fair-Value verdict.
- **Render the player detail development trajectory copy ("Entering prime in ~2 years") in a neutral colour, not gold**
  - `TODO.md:3218` · design
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:1376-1378 — Text(trajectoryDescription).foregroundStyle(Color.textTertiaryReadable).
- **Say why the player's season stats are empty rather than printing a bare "No stats recorded this season"**
  - `TODO.md:3219` · design
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:1575-1584 — seasonEmptyNote returns "Season hasn't kicked off yet" at week 0, "Retired — see the career table below", or "No games played this season"; the card title also carries the season year (:1491).
- **Label what the Trade Value card's Overall/Age/Contract ticks actually mean**
  - `TODO.md:3220` · design
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:1701-1737 — the three unlabelled ⊕ marks are now signed factor rows ("Base (OVR) 84 OVR — 118 pts", "Position QB ×1.30 (+30 %)", …) rendered by tradeValueFactorRow at :1885-1908 with up/flat/down tone icons.
- **A Scheme Mismatch card names the player's best scheme against the head coach's installed scheme and states what it costs him.**
  - `TODO.md:3246` · design
  - PlayerDetailView.swift:3390-3431 — schemeMismatchInfo compares bestSchemeFit against the HC's scheme for the player's side and fires only when team familiarity < 50; the card (rendered at :555) reads "<Player> knows X. Coach Y runs Z." plus "He installs the club's system from scratch, which costs him snaps and costs the coordinator a package."
- **Player attribute values are colour-coded on a five-tier ladder, so an 83 and a 77 no longer print the same green**
  - `TODO.md:3255` · design
  - PlayerDetailView.swift:296-298 `colorForAttribute` → `Color.forRating`; the ladder is Theme.swift:132-140 with bands at 90/80/70/60 (RatingTier, :158-169): 83 → success green, 77 → accentBlue, 65 → warning. Introduced by dd27c1f (2026-05-07, "unified 5-tier OVR color scale"), after this note was filed.
- **Player Detail leads with a Scheme Mismatch card naming the player's system, the coach's system, and the two ways out**
  - `TODO.md:3263` · feature
  - PlayerDetailView.swift:3413-3432 `schemeMismatchCard` (section header: "MARK: - Scheme Mismatch CTA"), rendered first in the lead column at :555. `schemeMismatchInfo` (:3391-3408) fires only when the best-fit scheme differs from the HC's scheme for the player's side AND team familiarity is under 50; the note reads "A trade or a scheme change are the two ways out." It is a callout, not a pair of buttons.
- **The "Group" column header on Roster Evaluation no longer wraps to "Grou" / "p"**
  - `TODO.md:3310` · design
  - RosterEvaluationView.swift:660-663 — width raised from 44 to 56 with a comment naming exactly this wrap ("'Group' plus its sort chevron does not fit in 44"); `sortLabel` adds `.lineLimit(1).minimumScaleFactor(0.8)` at :427-434.
- **The "You" column on Roster Evaluation shows a gold "Set" affordance instead of an em-dash when the user has graded nothing**
  - `TODO.md:3311` · design
  - RosterEvaluationView.swift:812-818 — `needBadge(label: "Set", color: .accentGold)` with the comment "A grey dash … reads as 'nothing here' rather than 'tap me'". The Staff column is always populated (Strength/Solid/needs, :795-806).
- **The Roster Evaluation priorities banner is already split into an explainer line and a separate progress counter**
  - `TODO.md:3315` · design
  - RosterEvaluationView.swift:618-624 — two Text views in a VStack: "Tap any position group to set your own priority — priorities affect draft board rankings and scouting focus" and "Priorities set: N/9 position groups", the latter monospaced and colour-coded to completion.
- **Tapping a position-group row on Roster Evaluation opens that group's full roster with starters flagged**
  - `TODO.md:3319` · feature
  - RosterEvaluationView.swift:786-800 the row is a Button opening `rosterNoteSheet`, which renders `evalGroupPlayerList` (:1921-1962): every player in the group sorted by OVR with an "S" starter badge (starterCount from `PositionGradeCalculator`), plus age, contract years/EXP, trend, OVR, morale and salary.
- **The "Biggest Need" callout has a divider above it and lives inside the roster-snapshot card, separate from the Cap Outlook section.**
  - `TODO.md:3337` · design
  - dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:1463 (`Divider().overlay(Color.surfaceBorder)`), 1465-1483 (tinted callout with its own bordered background), 1540-1543 (Cap Outlook is its own `sectionCard`)
- **The cut list headed "worst first" is a football judgement again — the money term is clamped so a salary can no longer outrank twenty points of overall.**
  - `TODO.md:4227` · bug
  - RosterCutEvaluator.swift:341-368 records the exact symptom ("how the club's 93 OVR MVP came to sit fifth on a list headed 'worst first'") and fixes it two ways: moneyScore is clamped to ±moneyCeiling = 4.0 (:296, :368) against an ovrScore of 0.55/point, and the weight inside the clamp is Owner.capReliefLean (0.25…1.75) so who cares about the cap is a fiction choice rather than a constant. Ordering call site: RosterCutView.swift:2370.
- **Non-total comparators in PlayerDetailView's league ranking and comparables got id tiebreaks, and the duplicated task counter collapsed to one.**
  - `TODO.md:5055` · bug
  - PlayerDetailView.swift:3211-3215 (leagueRanking) and :3448-3452 (comparablePlayers) both end in $0.id.uuidString < $1.id.uuidString. TimelineTasksPanel.taskProgress (UI/Common/TimelineTasksPanel.swift:1497) is now the single counter, read by CalendarSidebarView.swift:72. The refusal to delete LegacyTracker.pressPromises / PressPromise.isDelivered also stands — both are still present as stored Codable fields (Domain/Models/League/LegacyTracker.swift:6, :30).

### scouting · 29

- **Scout vacancies are differentiated: only the Chief Scout gets the red High Priority capsule, the five regionals get a quieter amber "Recommended".**
  - `TODO.md:3102` · design
  - dynasty/dynasty/UI/Staff/CoachingStaffView.swift:1240-1246 (`scoutHiringPriority`: `.chiefScout → .high`, everything else `.recommended`) and 4999-5015 (red capsule vs plain amber text)
- **The combine-trip CTA is no longer a green banner — it renders gold when live, dead grey with a warning-coloured reason when blocked, and is absent entirely with no scouts on staff.**
  - `TODO.md:3394` · design
  - ScoutTeamView.swift:222-264 — `blockedReason` drives `live`; blocked draws `lock.fill` on `backgroundTertiary` with the caption in `Color.warning`, and `.disabled(!live)`. Green now appears only on the completed state (:196-212). With zero scouts the tab renders `emptyState` instead of the row (ScoutTeamView.swift:90-92).
- **Board tier breaks render as a full pinned section header carrying the tier name, count, need and marked tallies and an availability rollup.**
  - `TODO.md:3399` · design
  - BigBoardView.swift:1805-1875 `tierHeader`, attached as the `header:` of each tier `Section` at :1340-1342 inside an `.insetGrouped` List (headers pin by default). The dot at :1827-1829 is now one element of a two-line bar, not the whole divider.
- **The scouting hub's "#1 need" and Roster Evaluation's "Biggest Need" are computed from the same DraftEngine need scoring.**
  - `TODO.md:3403` · bug
  - RosterEvaluationView.swift:2145-2152 documents and uses `DraftEngine.topTeamNeeds(roster:limit:1)`; ScoutBoardReads.swift:270-278 `computeTeamNeeds` uses `DraftEngine.teamNeedDeficits` with `topTeamNeeds` as fallback — both rank on `teamNeedComponents`' `multiplier × weight` (DraftEngine.swift:1366-1370, :1642-1654). ScoutBoardReads is the single value both the board's NEED chip and Scout Notes' "#1 need" line render from (ScoutBoardReads.swift:16-22).
- **The scouted-coverage percentage sits beside the rationed instruments that raise it, each greyed with its own "window shut" reason.**
  - `TODO.md:3407` · design
  - DraftPrepCard.swift:443-485 `coverageRow` prints "% Top N scouted" next to Evaluations used/slotsPerCycle, Interviews used (labelled "(window shut)" outside its phase), Combine on-site/TV and pro-day slot counts; :264-277 lists the specific unscouted top-32 men as tappable attention items, gated on `progress.canAct(.filmStudy)`.
- **The Combine Report's inner hero card is gone; the count is now a plain caption on a clear row under the nav title.**
  - `TODO.md:3416` · design
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1798-1809 — Text("\(mentions.count) notable performances") in .caption on .listRowBackground(Color.clear), with the comment at :1799-1803 describing the removed 40 pt "COMBINE REPORT" hero.
- **Combine Report categories are colour-coded per section — gold Standout, green Stock Riser, red Stock Faller, blue Surprise — with directional up/down icons.**
  - `TODO.md:3417` · design
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1773-1791 (categoryIcon / categoryColor) applied to the section header Label at :1828-1834.
- **Each Combine Report row opens the prospect's detail card when the class still holds that man.**
  - `TODO.md:3423` · feature
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1820-1826 — NavigationLink(destination: ProspectDetailView(career:prospect:)) around mentionRow, with a non-linked fallback row for a stale mention; the rationale at :1754-1756 quotes the original complaint.
- **The Combine Report lists every mention the combine generated — roughly a dozen across four categories — under an honest "<n> notable performances" count.**
  - `TODO.md:3425` · design
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1805 and :1811-1836 (all four categories rendered, none truncated); counts at ScoutingEngine.swift:3524, 3548, 3565, 3584.
- **The combine table's column headers stay pinned over their columns while the table scrolls**
  - `TODO.md:3435` · design
  - CombineResultsView.swift:430-466 — the rows sit in a `Section` whose `header:` holds `ProspectListControls` plus `columnHeaders`, and the outer view is `.listStyle(.plain)` (:469), which pins section headers. The comment at :436-441 names this as the fix for the old nested-scroll layout.
- **Combine drill percentiles render as a colour-coded tier phrase, green at the top of the pool, not as grey micro-text**
  - `TODO.md:3436` · design
  - CombineResultsView.swift:1232-1252 `drillCell` prints `ProspectMeasurableTier.label(for: pct).text` in `tier.color`; the ladder (ProspectListControls.swift:255-263) is Top 10% → eliteGreen, Top 25% → success, Above Avg → accentBlue, Below Avg → warning, Bottom 25% → danger. It is coloured text rather than a capsule, but the signal the item asked for is there.
- **Prospect filter chips now use a filled blue pill with inverted heavy text for the active state, not gold**
  - `TODO.md:3440` · design
  - ProspectListControls.swift:40-61 — selected chips fill `Color.accentBlue` with `backgroundPrimary` text at `.heavy`, unselected sit on `backgroundTertiary` with a `surfaceBorder` stroke, and selection carries `.isSelected` for VoiceOver. The mode chips match (:107-125).
- **Combine drill numbers use tabular figures inside equal fixed-width cells, so 4.85 and 4.45 line up**
  - `TODO.md:3441` · design
  - CombineResultsView.swift:1232-1252 `drillCell` — `.font(.caption.monospacedDigit())` in a `.frame(width:)` shared by the cell and its pinned header (widths in `CombineW`, :43-49). Cells are centred rather than trailing-aligned, but with tabular digits and equal digit counts per drill the columns align exactly.
- **Every combine drill column sorts on a header tap, with an ascending/descending chevron**
  - `TODO.md:3444` · feature
  - CombineResultsView.swift:752-760 `physicalHeaders` — 40yd, Bench, Vert, Broad, 3-Cone, Shuttle and Pos Drill are all `sortableHeader`; `toggleSort` (:832-839) flips direction on re-tap and `sortLabel` (:840-855) draws the chevron. Switching away from the Physical block resets a drill sort (:485-497).
- **The interview-report summary is no longer one packed strip — it is a labelled card with a scrollable pill row and the best-man line on its own row.**
  - `TODO.md:3478` · design
  - InterviewSelectionView.swift:1580-1647 — SUMMARY header plus "Showing N of M", then a horizontal ScrollView of six facet pills, then the "Best: …" line. The comment at :1602-1605 records why the pills scroll rather than wrap to rows (the report also renders in split view).
- **Interview-report per-card actions are the four-tier prospect mark, with Avoid drawn in red instead of the old same-coloured Star / Red Flag pair.**
  - `TODO.md:3482` · design
  - InterviewSelectionView.swift:2284-2318 iterates ProspectMarkTier.choices and tints each pill by tier.color; ProspectMarkTier.color maps .avoid to .danger, .elite to gold, .target to green, .depth to blue (Domain/Models/Scouting/CollegeProspect.swift:1307-1315). The comment at :2286-2289 records that the old star and red-flag wrote conflicting halves of one field.
- **The "Review interview report" dashboard task completes when the report is opened or its Complete Review button is tapped.**
  - `TODO.md:3486` · bug
  - InterviewSelectionView.swift:1508 (the CTA) and :1538 (.onAppear) both set CareerScopedDefaults "interviewReportReviewed"; CareerShellView.swift:2963-2976 marks the task .done off that flag, with a 60-interviews-used backstop for stuck saves.
- **The interview report's off-field-concerns count is a filter chip that scopes the list to exactly those men.**
  - `TODO.md:3489` · feature
  - InterviewReportFacet.concerns (InterviewSelectionView.swift:1231, predicate at :1288) is drawn as a tappable 44 pt pill by facetPill (:1656-1700) and scopes visibleRows (:1420-1428). A facet nobody matches is dimmed and refuses the tap (:1658-1660).
- **The interview report has a table mode with sortable SCORE, IQ and RISK columns plus six scoping facets.**
  - `TODO.md:3490` · feature
  - InterviewReportSort with DSSortableColumnHeader (InterviewSelectionView.swift:1348-1352, 1816-1820), applied with id tiebreaks in visibleRows (:1430-1435). GRD is deliberately unsortable — the comment at :1345-1348 records it as "the SCORE column under a second name". POS remains a badge column rather than a sort key.
- **The interview report carries a scout's recommendation naming the top three targets by interview grade.**
  - `TODO.md:3493` · feature
  - recommendationSection (InterviewSelectionView.swift:2325-2364) draws "SCOUT'S RECOMMENDATION" over topTargets (:1458-1460). It sits at the foot rather than the head deliberately — the comment at :1489-1492 records it as the batch's conclusion, drawn only when nothing is filtered.
- **The prospect card's Quick Assessment chips are tinted per concept instead of all wearing the same gold border.**
  - `TODO.md:3499` · design
  - ProspectDetailView.swift:956-970 — each `assessmentBadge` takes its own tint: `risk.color`, `schemeFitColor(fit)` (Fair = .warning, :2480-2486), `athleticProfileColor` (:1071-1079), `trajectory.color`.
- **The prospect card's action bar carries no green button — instruments run on the shared gold-primary / neutral-secondary / ghost ladder.**
  - `TODO.md:3501` · design
  - ProspectDetailView.swift:2923-2940 `springActionBar` puts Workout on `ghost`, Interview on `secondary`, film study on `primary`; DSActionBar.swift:275 (gold gradient primary), :291 (backgroundTertiary secondary), :303 (clear ghost) — no success/green anywhere.
- **Combine percentiles render as a tinted, filled chip rather than tiny grey trailing text.**
  - `TODO.md:3503` · design
  - ProspectDetailView.swift:3212-3218 — `CombineMeasurableRow` draws the "Nth %ile for POS" text in `percentileColor(pct)` on a `percentileColor(pct).opacity(0.15)` rounded background.
- **Putting a prospect on the board is now four full-width 44 pt tier buttons in the hero, not a small star-plus-text link.**
  - `TODO.md:3504` · design
  - ProspectDetailView.swift:833-878 `heroMarkLane` / `markLaneButton` — one button per `ProspectMarkTier`, `frame(height: 44)`, live tier washed in its own colour. The doc comment at :826-832 records the deliberate choice NOT to make it a gold primary (gold is reserved for the bar's one commit).
- **A below-average combine percentile is tinted warning/danger by the shared rating ladder instead of reading neutral.**
  - `TODO.md:3505` · design
  - ProspectDetailView.swift:3252-3256 — `percentileColor(_:)` returns `Color.forRating(pct, scale: .percent)`, so a 28th percentile lands in the low band; the chip background at :3216 uses the same colour.
- **The prospect card renders a per-position skill grid (a QB gets ARM/SAC/MAC/DAC/PKT/SCR) alongside the eight mental keys.**
  - `TODO.md:3509` · feature
  - ProspectDetailView.swift:1628-1658 `positionGradesGrid` draws every key from `ProspectFog.positionSkillKeys(for:)`; ProspectFog.swift:671 returns ["ARM","SAC","MAC","DAC","PKT","SCR"] for a quarterback. Unbought keys render as dark cells (:1702-1723) rather than being hidden.
- **The prospect card prints the estimated rookie deal for the projected round and the pick-value read at the club's actual slot.**
  - `TODO.md:3511` · feature
  - ProspectDetailView.swift:2594 `DSDetailRow("Est. Rookie Deal", rookieContractEstimate(round: proj))`, computed at :3009-3018 off `DraftEngine.rookieContractBand(round:salaryCap:)` against the club's live cap; `onTheClockValueRow` (:2626-2641) prints "At Your Pick #N — Value/Reach vs the board" from `DraftIntel.pickValueDelta`.
- **Scouting-hub Insights blocks default to collapsed with per-surface memory, and the war room carries a Scout Notes tab.**
  - `TODO.md:5052` · feature
  - ScoutingInsightsDefaults.resolvedExpansion is a pure read defaulting to false (UI/Scouting/DraftPrepProcessBar.swift:545-547) and resolveDefault no longer writes or watches a phase token (:620-624). insightsSurfaceKey is "<career-uuid>-<tab>" (UI/Scouting/ScoutingHubView.swift:801-803). warRoomTabs is the 6-tab list [board, classDepth, scoutNotes, draftOrder, mockDraft, scouts] (:753-754); ScoutingTab.scoutNotes at :1895.
- **Big Board's recommendations and depth-analysis blocks were extracted into ScoutNotesView, both reading one shared ScoutBoardReads walk.**
  - `TODO.md:5053` · tech-debt
  - UI/Scouting/ScoutBoardReads.swift is 401 lines (struct at :36); UI/Scouting/ScoutNotesView.swift is 436 lines with recommendationsSection at :144 and depthAnalysisSection at :262. BigBoardView.swift (now 2916 lines) contains zero references to either symbol.

### onboarding · 26

- **Add a sort menu to team selection so clubs can be ranked by difficulty, cap and record**
  - `TODO.md:2641` · feature
  - dynasty/dynasty/UI/Career/TeamSelectionView.swift:1818-1830 — TeamSortMode {division, capSpace, difficulty, overall, wins}, driven by the sort menu at :508-543; rebuild stage is covered by the situation filter at :471-506. Draft-pick count is the one axis with no sort.
- **Give the team-selection list a clear visual division header**
  - `TODO.md:2642` · design
  - dynasty/dynasty/UI/Career/TeamSelectionView.swift:635-653 — divisionHeader draws a tracked uppercase label between two rules, emitted per group by divisionsForConference (:98).
- **Surface an explicit career-difficulty signal on team selection instead of leaving it inferred from a tier word**
  - `TODO.md:2643` · design
  - dynasty/dynasty/UI/Career/TeamSelectionView.swift:1041-1052 — 1-5 difficulty stars on every row under a "DIFFICULTY" column header (:414); the detail sheet spells out preview.difficultyLabel ("Very Easy"…"Very Hard", Data/Import/LeagueTeamData.swift:36-45) at :1498 plus the rationale "Difficulty weighs roster talent, cap room, and draft capital" at :1514-1518.
- **Add a compare mode to team selection so two or three finalists can be evaluated side by side**
  - `TODO.md:2648` · feature
  - dynasty/dynasty/UI/Career/TeamSelectionView.swift:546-573 (compare toggle), :397-405 (toggleCompare), :1834+ (CompareTeamsSheet, a column-per-team stat table); rows grow a checkbox and a selected tint at :974-981.
- **Put cap space, draft picks and roster strength on one comparable colour scale across teams**
  - `TODO.md:2649` · design
  - dynasty/dynasty/UI/Career/TeamSelectionView.swift:1581-1608 — all three now band success/accentBlue/warning and each carries a "League N" anchor; on the row the difficulty stars were deliberately de-coloured to stop a second meaning landing on the CAP/STF amber (:1041-1048) and a column-header key was added (:408-437).
- **The New Career step-1 background is a stadium photo at 20% opacity under a three-stop dark scrim, not a noisy player silhouette.**
  - `TODO.md:2701` · design
  - dynasty/dynasty/UI/Career/NewCareerView.swift:101-116 — Image("BgCoachStadium2") at .opacity(0.2), then a LinearGradient of backgroundPrimary 0.85/0.5/0.85 over it; the asset is Assets.xcassets/BgCoachStadium2.imageset, a coach/stadium plate.
- **The New Career segmented controls paint the unselected half as light textSecondary on backgroundSecondary with a blue (not gold) selected segment, so the inactive half no longer reads as a dead button.**
  - `TODO.md:2702` · design
  - dynasty/dynasty/UI/Common/Theme.swift:282-294 (DSAppearance.apply sets selectedSegmentTintColor = accentBlue, normal title = textSecondary on backgroundSecondary), called at DynastyApp.swift:15; NewCareerView.swift:144-146 notes the palette is applied app-wide.
- **The New Career forward commit is disabled until the player name has at least two non-space characters, on both the Custom League and Quick Start paths.**
  - `TODO.md:2706` · bug
  - dynasty/dynasty/UI/Career/NewCareerView.swift:77-79 (isNameValid), :955 (.disabled(!isNameValid) on Next), :998 (same on Choose Your Team) plus the standing nameGateHint at :1012-1022 and inline errors at :358-367.
- **The New Career step indicator is a single "Step N of M" line over the progress bar; the step title moved to the large navigation title.**
  - `TODO.md:2707` · design
  - dynasty/dynasty/UI/Career/NewCareerView.swift:151-180 with the comment at :153-154 ("The step's own title used to sit at the trailing end of this row"), and .navigationTitle(stepTitle(currentStep)) at :141.
- **The Career Role card prints a one-line blurb explaining the GM vs GM+HC responsibility split under the comparison table.**
  - `TODO.md:2710` · design
  - dynasty/dynasty/UI/Career/NewCareerView.swift:455 renders Text(roleBlurb); roleBlurb at :465-472 returns "Focus on roster building and let your head coach handle game day." / "Total control over every decision, from the roster to the play sheet."
- **Simple cap mode has its own concrete blurb plus a six-row feature checklist showing exactly which cap mechanics it omits.**
  - `TODO.md:2711` · design
  - dynasty/dynasty/UI/Career/NewCareerView.swift:487-499 (Simple gets only "Annual salary cap"; bonuses, dead cap, restructures, tags and rollover are all minus-circles) and capBlurb at :519-521.
- **Cap mode has a third Sandbox option, wired end-to-end through the contract, cap and free-agency engines.**
  - `TODO.md:2713` · feature
  - dynasty/dynasty/UI/Career/NewCareerView.swift:16-28 and :481 (picker segment); Domain/Enums/CapMode.swift:10; short-circuits at Engine/Contract/CapManagementEngine.swift:310, :1107, :1313 and CommittedCapLedger.swift:268-333.
- **Verified: the New Career forward button cannot be pressed on an empty or one-character name.**
  - `TODO.md:2717` · bug
  - dynasty/dynasty/UI/Career/NewCareerView.swift:77-79 isNameValid requires >= 2 trimmed characters; :942 guards the Next action, :955 and :998 disable both commits, and :1012-1022 shows a standing hint on the NavigationLink path.
- **The career-wizard progress bar counts the team-pick screen, so "Choose Your Team" no longer lands past the last step.**
  - `TODO.md:2727` · design
  - NewCareerView.swift:82-87 — totalSteps is 2 for Quick Start and 4 for Custom League, with the comment stating both counts include the mandatory team pick that follows.
- **The career-intro Team Overview's "Average Overall" states its league comparison explicitly instead of an ambiguous "(avg: 71)".**
  - `TODO.md:2954` · design
  - IntroSequenceView.swift:582-587 uses ComparisonStatRow(leagueAvg: 72), which renders "+N vs league avg 72" or "level with league avg 72" (ComparisonStatRow.deltaText, IntroSequenceView.swift:1319-1322).
- **Team Overview position-group cards label the two grades S (starters) / D (depth) and carry an explanatory caption.**
  - `TODO.md:2956` · design
  - IntroSequenceView.swift:671 draws the caption "S is the starters, D the depth behind them. Each group's OVR is its starters' average…"; the S:/D: prefixes are rendered at :679-698.
- **A fully-stocked special-teams room no longer shows an alarming "F" depth grade on a green-bordered card.**
  - `TODO.md:2957` · bug
  - PositionGradeCalculator.noDepthGrade is an em dash (UI/Roster/RosterView.swift:1608), returned whenever a group has no backups (:1669-1670) and drawn in textTertiary rather than red (gradeColorForLetter, :1635-1639). The source comment names this exact case: "Special teams wants exactly one kicker and one punter, so every club in the league carried a permanent red 'D: F' on a room that was fully stocked."
- **The Team Overview "Weakest Group" line and the position-group cards compute from the same starter average, so WR cannot read two OVRs on one screen.**
  - `TODO.md:2958` · bug
  - IntroSequenceView.swift:386-395 — weakestPositionGroup calls PositionGradeCalculator.calculatePositionGrades over the same Self.groupPositions the cards use at :472-489. The doc comment at :383-385 states it "stays consistent with the Position Group Strengths card (both rely on the top-N starter average)".
- **Position-group cards on the Team Overview state roster count against an ideal and surface the positional need.**
  - `TODO.md:2966` · design
  - IntroSequenceView.swift:714 prints "<count> (need <ideal>)" — the comment at :710-713 records why it is not "7/6 players". The need chip ("Need starter" / "Need depth" / "Need upgrade") comes from Self.needLabel at :448-458 and is drawn at :716-726.
- **The WR OVR conflict between the Team Overview's position-group card and its Weakest Group line is reconciled — both read the same starter average.**
  - `TODO.md:2972` · bug
  - IntroSequenceView.swift:386-395 routes weakestPositionGroup through PositionGradeCalculator.calculatePositionGrades, the same call the cards make at :472-489. Duplicate of the item on line 2958.
- **Locked future phases on the intro roadmap are legible — the fade floor was raised from 0.4 to 0.7 and every row keeps its month label.**
  - `TODO.md:2976` · design
  - dynasty/dynasty/UI/Career/IntroSequenceView.swift:929 `let distanceFade: Double = isCurrent ? 1.0 : max(0.7, 1.0 - Double(index) * 0.08)` with the comment naming the raised floor; applied at :1002; month label rendered at :982.
- **Every one of the roadmap's ten offseason phases now carries its own one-line description.**
  - `TODO.md:2980` · design
  - IntroSequenceView.swift:900-911 — all ten `CalendarEntry` rows have a `description`; rendered unconditionally at :986-994 under the comment "Nine of the ten descriptions used to be withheld" (landed in ed4e9a1).
- **The roadmap's 'OFFSEASON CALENDAR' section label is grey, not a second stack of yellow micro-caps under the gold page heading.**
  - `TODO.md:2982` · design
  - IntroSequenceView.swift:1256-1265 `SectionLabel` paints `Color.textSecondary` at footnote size; the only gold heading is "YOUR ROADMAP" at :1062-1066.
- **Every future offseason phase on the roadmap previews the decision it asks for (e.g. Roster Cuts: 'Cut to 53-man roster — tough decisions on borderline players').**
  - `TODO.md:2986` · design
  - IntroSequenceView.swift:900-911 descriptions, Roster Cuts at :909; rendered on every row at :986-994.
- **Confirmed: dashboard task rows deep-link, and 'Hire Head Coach' routes to the coaching staff screen.**
  - `TODO.md:2988` · verification
  - TaskGenerator.swift:717-726 emits the task with `destination: .hireHC`; TimelineTasksPanel.swift:525-527 wraps the row in a Button calling `onTaskSelected(task.destination)`; CareerShellView.swift:2560 maps `.hireHC` → `.coachingStaff`.
- **Verified: entering the front office is one-way — the intro sequence cannot be re-entered from a saved career.**
  - `TODO.md:3009` · verification
  - IntroSequenceView is presented from exactly one place, TeamSelectionView.swift:298 (navigationDestination on a freshly created career). Continuing a save goes straight to CareerShellView (MainMenuView.swift:145, :1063). completeIntro() (IntroSequenceView.swift:172-181) saves and presents CareerShellView as a fullScreenCover, and the intro sets navigationBarBackButtonHidden(true) at :111. Loose end worth a line: career.hasCompletedIntro is written but never read as a gate.

### press conference · 18

- **The press-conference podium states the question count before the player takes the microphone.**
  - `TODO.md:2593` · design
  - PressConferenceView.swift:432-437 — the action-bar explainer reads "**N questions.** Everything you say is on the record."; :500-508 draws a `DSSlatBand` headlined "N questions" with a `DSResourceMeter(spent: 0, total: questions.count, unit: "questions")`.
- **The podium names what each of the five meters answers for before the first question is asked.**
  - `TODO.md:2594` · design
  - PressConferenceView.swift:735-739 — the `roomLedgerCard` legend reads "Owner affects job security · Morale is the locker room's read · Fans are the city's · Media shapes the narrative · Legacy affects career rating", and the comment at :733-736 records that it stays on both card states. The card is drawn on the podium at :489.
- **The podium carries a four-line pre-conference brief: the room's situation, where the roster stands, the mood in the building and the owner's stance.**
  - `TODO.md:2595` · design
  - PressConferenceView.swift:1004-1043 `roomReadCard`, drawn on `podiumPlate` at :494. Rows come from `PressContext` — `situationRead` (:1098-1112), `standingRead` (:1116-1125), `lockerRoomRead` (:1127-1136), and `ownerPersonaLabel`/`ownerRead` (:1138-1160), which print the owner's win-now stance and patience out of 10.
- **The podium shows the Owner / Morale / Fans / Media / Legacy baselines before the session opens.**
  - `TODO.md:2600` · design
  - PressConferenceView.swift:713-745 `roomLedgerCard` renders `baselineTiles` (:754-800) while `selectedIndices` is empty, headed "BEFORE THIS SESSION": owner satisfaction %, locker-room band, fan support %, media reputation with its label, and legacy points. Drawn on `podiumPlate` at :489.
- **Every scheduled question's outlet, reporter and stance is listed on the podium before the session starts.**
  - `TODO.md:2601` · design
  - PressConferenceView.swift:644-660 — with `previewOnly: true` each slat's title is `question.outlet` and its subcaption is "reporterName · stance", from `PressConferenceEngine.stance(for:)`. The comment at :636-643 records this as deliberate: "a hostile writer waiting at question 3 is the whole reason to hold a tone back at question 1." The band is drawn at :500-508.
- **Press conference answers fired on first tap with no confirm step, so a mis-tap was irreversible**
  - `TODO.md:2618` · design
  - PressConferenceView.swift:1851-1861 — `commitBar` is the two-step: tapping a card sets `pendingResponseIndex` (reversible, gold "Picked" tick at :1387-1391) and the DSActionBar primary reads "Say it", firing `commitPendingResponse` (:2320). `commitExplainer` states the finality in words before and after: "Nothing is said until you **say it**" and then "It cannot be taken back" (:1871-1888). Undoing an already-said answer stays impossible by design.
- **The press conference gave no read on locker-room or owner state before you answered**
  - `TODO.md:2619` · feature
  - PressConferenceView.swift:752-796 — `baselineTiles` prints all five meters (Owner %, locker-room band, Fans %, Media reputation + label, Legacy) before a word is said, colour-graded by `Color.forRating`. `roomReadCard` (:1004-1042) adds one row per engine axis with a plain-language read: "The building" (locker-room band) and "The owner" (win-now stance plus patience N/10, :1137-1139).
- **The reporter card carried no tone tag, so the same answer landed unpredictably**
  - `TODO.md:2625` · feature
  - PressConferenceView.swift:1274-1310 — the reporter identity strip resolves `PressConferenceEngine.stance(for: question)` into a coloured pill beside the outlet, and the doc above it notes the pill is an engine input (`stanceAdjustment`), not decoration. The stance also rides the slat band's subcaption for both answered and upcoming questions (:634-653).
- **There was no preview of the media headline each answer would produce**
  - `TODO.md:2626` · feature
  - PressConferenceView.swift:1542-1598 — `headlinePreviewSection` puts a "Preview headline" disclosure capsule on every unanswered response card, expanding to show that response's `mediaReaction` verbatim in a quote block. It is drawn only while `selectedResponseIndex == nil` (:1407-1415), because after the commit the reveal prints the same string.
- **There was no running session total, so you could not course-correct across the later questions**
  - `TODO.md:2627` · feature
  - PressConferenceView.swift:307-320 — `runningTotals` folds every committed answer in the context it was asked in, mirroring `buildResult`. `roomLedgerCard` flips to "WHERE YOU STAND NOW" from the first committed answer (:713-742) and renders `meterLedgerGrid(cells: meterCells(for: totals))` — five running deltas each with its landing value — over `sessionVerdict`, the engine's running verdict (:956-985).
- **Unselected press-conference answer cards are legible — they sit on an opaque panel, and the dim is contrast-measured**
  - `TODO.md:2914` · design
  - PressConferenceView.swift:1418-1445 — cards fill `Color.backgroundSecondary` (opaque), and the disabled dim is 0.8 with a comment recording the measurement: "Measured at 0.8 with textSecondary: 4.6 : 1, clear of the AA floor". The dark photo the text washed out against was deleted in #167 (:359-362).
- **Press-conference standing meters carry units and before→after context instead of bare numbers**
  - `TODO.md:2915` · design
  - PressConferenceView.swift:752-798 `baselineTiles` prints "70%", the media reputation with its `reputationLabel` caption, and Legacy points; from the first committed answer :838-905 `meterCells`/`meterLedgerGrid` prints a signed delta per audience over a context line (`"\(base.satisfaction)% → …%"`, `"every man +N"`).
- **The press-conference meter legend is at the 12 pt display floor, in textSecondary, and cannot truncate**
  - `TODO.md:2916` · design
  - PressConferenceView.swift:735-740 — `DSType.text(DSType.Size.footnote…)` where `footnote = 12` (DSTokens.swift:133), `Color.textSecondary` (7.3:1 per the recorded contrast audit), `.multilineTextAlignment(.center)` + `.fixedSize(horizontal: false, vertical: true)`.
- **Every press-conference answer card carries a visible border, tinted by its archetype**
  - `TODO.md:2918` · design
  - PressConferenceView.swift:1420-1439 — `strokeBorder(isHighlighted ? tint.opacity(0.75) : tint.opacity(0.28), lineWidth: isHighlighted ? 2 : 1)`, plus a 4 pt leading tone bar on every card: "The default stroke is tinted by the archetype so the cards can be pre-scanned by personality."
- **The press media-reaction block is identified by a gold newspaper glyph, and its pre-commit form is labelled "Preview headline"**
  - `TODO.md:2919` · design
  - PressConferenceView.swift:1613-1619 — `resultReveal` opens `Image(systemName: "newspaper.fill").foregroundStyle(Color.accentGold)` beside the reaction text; before committing, the same string sits behind an explicit "Preview headline" control with a `newspaper` icon (:1546-1560).
- **Committing a press answer animates in a reveal card of signed per-audience deltas, and flips the standing card to a delta+projection grid**
  - `TODO.md:2923` · design
  - PressConferenceView.swift:2334-2349 `commitPendingResponse` inserts `showReaction` under `.easeOut(duration: 0.4).delay(0.25)`; the inserted `resultReveal` carries `effectPillRow` (:1662-1682), and `roomLedgerCard` (:713-742) switches from `baselineTiles` to `meterLedgerGrid` with "72% → 76%" context.
- **The 70% satisfaction meter is labelled OWNER and the legend under it says what each of the five meters does**
  - `TODO.md:2927` · design
  - PressConferenceView.swift:765-773 — the tile is `label: "Owner", value: "\(owner.satisfaction)%"` with a comment recording the #117 rename; :735 keeps the legend "Owner affects job security · Morale is the locker room's read · Fans are the city's · Media shapes the narrative · Legacy affects career rating" on BOTH card states by #119.
- **Answer cards show per-audience direction hints before you commit, so options can be compared without revealing the arithmetic**
  - `TODO.md:2930` · design
  - PressConferenceView.swift:1463-1505 `hintRow`/`hintLine` renders an audience chip with a direction glyph and phrase on every card pre-commit (nothing blurred), :1540-1595 adds a "Preview headline" expander per option, and `roomReadCard` (:990-1010) names the context those hints resolve against.

### draft · 17

- **All four draft-class loose ends closed: hometown fields written, a Mental roster mode added, combine DNP shipped, and prospect grades scoped per career**
  - `TODO.md:403` · tech-debt
  - hometown is written at Data/Import/LeagueGenerator.swift:745-746, Engine/Draft/DraftEngine.swift:617-618, Engine/Scouting/DraftClassBuilder.swift:626 and read by Engine/FreeAgency/HometownDetector.swift:53; RosterAnalysisMode.mental exists at UI/Roster/PlayerRowView.swift:1081 with LRN/CMP/WE columns at :298-320; DNP is real (Engine/Scouting/ScoutingEngine.swift:788-791, UI/Scouting/CombineResultsView.swift:875-878); UserProspectGradeStore now resolves career-suffixed UserDefaults keys per access (Domain/Models/Scouting/UserProspectGrade.swift:66-95).
- **Merge the interviews tab's two parallel slot meters into one progress line**
  - `TODO.md:3456` · design
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:290-306 — selectionProgress prints one line, "N selected · M of 60 left", over one bar; the duplicate header pill was removed (:257-261, "three counters for one fact, two of them on different denominators").
- **Collapse the interviews tab's fixed five-chip trailing column set**
  - `TODO.md:3457` · design
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:567-609 — only RISK and OVR are pinned trailing; the middle block follows the shared mode chips (ProspectListControls at :494-500) and NEED moved onto the name line at :702-711.
- **Give the interviews tab's row checkboxes a filled selected state and say which of the two circles spends a slot**
  - `TODO.md:3459` · design
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:669-672 — Image(systemName: isSelected ? "checkmark.circle.fill" : "circle") tinted gold when ticked; the header names the gutter "MARK" vs a checkmark glyph at :575-579.
- **Resolve the gold-on-gold collision between the RECOMMENDED section header and the prospect row chips**
  - `TODO.md:3460` · design
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:704-710 — the NEED chip is Color.success; ProspectRiskBadge tints danger/accentBlue/success (UI/Scouting/ProspectListControls.swift:487-494); gold is now reserved for the section headers, the ration bar and the ticked checkbox.
- **Make the interviews tab show what happens when all 60 slots are taken**
  - `TODO.md:3461` · design
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:648 (canSelect gate) and :760 (.opacity(canSelect || isSelected ? 1.0 : 0.4)) dim and no-op unselectable rows; at zero remaining the list is replaced by the saved report or allInterviewsUsedView (:202-217).
- **Give the interviews tab's disabled bottom CTA a real disabled treatment instead of the enabled gold**
  - `TODO.md:3462` · design
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:806-818 — blocked paints Color.backgroundTertiary.opacity(0.5) with Color.textTertiary text, carries .disabled(blocked), and swaps the copy for the reason when the stage is locked.
- **Separate formal combine interviews from informal team facility visits**
  - `TODO.md:3466` · feature
  - dynasty/dynasty/Engine/Scouting/DraftPrepProgress.swift:79-84 — three distinct rations (interviewSlots 60, workoutSlots 30, top30Slots 30); the facility visit is its own stage and screen, UI/Scouting/Top30VisitsView.swift:1-40 ("facility visits are the LAST instrument before the draft").
- **Add filters to the interviews tab so 60 slots do not have to be spent by scrolling**
  - `TODO.md:3468` · feature
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:348-390 — a menu with Position, Projected Round, Team Needs Only, Shortlisted Only, Starred Only, "My Grade: 1st Round+" and Deselect All, all applied in selectableProspects at :90-108.
- **State the rule behind the interviews tab's RECOMMENDED section instead of leaving it an unexplained heuristic**
  - `TODO.md:3469` · design
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:522 prints the subtitle "Matches team needs with top-half talent", and recommendedProspects at :111-120 is exactly that predicate (teamNeedPositions ∩ ovr ≥ median).
- **Re-entering the war room after the draft opens the UDFA panel instead of a frozen "Pick 0/32 · -1 picks away" board.**
  - `TODO.md:3611` · bug
  - DraftDayCoordinator.swift:478-490 — with no unfinished picks it sets currentPickIndex = picks.count, mode = .complete and calls prepareUDFAStage(); DraftDayView.swift:105-107 renders DraftUDFAPanel for .complete rather than the pick board. The negative and zero counts are handled explicitly in DraftControlBar.skipTarget (:499-509: away < 0 → endOfDraft, away == 0 → "You are on the clock", .complete → "The draft is over").
- **The Big Board no longer degenerates into a single-position list — the class generator was rewritten and tiers cap same-position stacking.**
  - `TODO.md:3631` · bug
  - DraftClassBuilder.swift:3-23 records the rewrite: the old generator derived a round from trueOverall × positionalDraftValue "which degenerated into a pure position sort (every QB ahead of every RB)"; talent now leads and positions follow. BigBoardView.swift:25 and 780-800 additionally cap each tier at bigBoardMaxSamePositionPerTier = 4 and push the overflow down.
- **Draft-night fast-forward really runs the AI's picks, and the broadcast speed control is wired to the clock.**
  - `TODO.md:3633` · bug
  - DraftDayCoordinator.swift:600-618 (skipToMyPick) drives autoAdvanceUntil (1800-1856), which loops AI picks until the user is on the clock, the draft ends, a trade offer arrives or a round turns. setSpeed (589-591) feeds startClockLoop's tick interval at 1244; the 0.5×/1×/2×/4× menu calls it from DraftControlBar.swift:670-702. The three competing fast-forwards were collapsed to one (comment at 622-637).
- **The round recap fires on the round it recaps and shows only that round's picks.**
  - `TODO.md:3634` · bug
  - DraftDayCoordinator.swift:1778-1786 — RoundRecapBuilder.build is passed allPickResults.filter { $0.round == round }, with the comment recording that the caller never filtered before, so "YOUR PICKS THIS ROUND" grew all night and "Steal Of The Round" ranked the whole draft (task #153b). It is triggered from the round transition detected after advancing (1836-1846) and deduped via lastRoundShown.
- **The two grades on a draft pick card now name whose opinion each is, and broadcast beats leave the screen in seconds.**
  - `TODO.md:3636` · bug
  - PickGradeCalculator.swift:34-37 — "The two numbers on that card are two frames, not one broken one"; the ticker's chip prints "MEDIA A+ STEAL" while boardRow prints "MY #101 · -50 REACH". DraftBroadcastRail.swift serialises beats on their own dwell (202-231), with per-beat dwells of 1.6-2.6 s and a hard min(4.2, …) cap at 1100; trimFastForwardReactions (1866-1872) collapses the backlog a skip creates.
- **Draft year headings print as "2026", not "2 026" — every one goes through String(Int) rather than a localized number.**
  - `TODO.md:3637` · bug
  - DraftDayView.swift:73 navigationTitle("The Draft \(String(DraftYearLabel.classYear(duringSeason:)))"); the same String(...) wrapping at DraftClassReportView.swift:106, DraftRecapView.swift:114/321/369, DraftUDFAPanel.swift:45 and RookieClassRevealView.swift:657.
- **The dashboard draft card reads the same live pick data as the war room, and the Finnish "Vaihe 3" string is gone from the UI.**
  - `TODO.md:3638` · bug
  - CareerDashboardView.swift:5141-5182 (buildDraftHeroState) derives the header round/pick, your next pick number and picks-away, and the top three targets from WeekAdvancer.currentDraftPicks / currentDraftClass, DraftIntel.markedTargets and UserDraftBoard; the tile at 3387-3395 prints "Pick #N" off the same filter. "Vaihe" now survives only in source comments (e.g. DraftDayCoordinator.swift:8-10), and the trade engine it promised exists (DraftDayTradeEngine, pendingTradeOffer, TradeUpBoardSheet).

### inbox · 10

- **The dashboard message badge counts unread only, and the inbox filter tabs carry per-tab unread counts.**
  - `TODO.md:2893` · bug
  - CareerDashboardView.swift:838-845 badges inboxMessages.filter { !$0.isRead }.count, and the Inbox tile spells it out as "N unread" (:1469-1472). InboxView.filterLabel appends each filter's own unread count to its lens label (UI/News/InboxView.swift:126-129), used by the DSLensTabs strip at :131-143.
- **Unread inbox messages are marked by a blue dot and a bold subject, not only by the toolbar's unread pill.**
  - `TODO.md:3521` · design
  - InboxView.swift:219-231 draws an 8 pt accentBlue dot in a reserved slot on every row; :248-251 renders the subject with DSType.text(..., message.isRead ? .regular : .bold).
- **Action Required inbox rows are promoted with a red tint, a heavier red border, an "Action" pill and top sort placement.**
  - `TODO.md:3522` · design
  - InboxView.swift:299-311 (rowFill Color.danger.opacity(0.12), rowBorderColor Color.danger.opacity(0.7), border 1.5 pt at :204-208), the DSStatusPill at :270-278, and sortRank at :58-63 putting action-required rows first.
- **Inbox sender glyphs are 18 pt inside a 36 pt tinted disc, with a distinct colour per sender role.**
  - `TODO.md:3524` · design
  - InboxView.swift:225-231 (18 pt symbol, 36x36 frame, Circle background at 0.15 opacity) and iconColor(for:) at :336-347, which gives each of the eight MessageSender cases its own colour.
- **Action Required inbox messages open a real flow — the detail view renders the destination button and attachment links, and the shell navigates on dismiss.**
  - `TODO.md:3529` · design
  - MessageDetailView.swift:63-67 and actionButton(destination:emphasized:) at :195-205, plus attachmentsSection at :144-190; InboxView.swift:88-108 parks the destination and replays it from .sheet(onDismiss:). All six `actionRequired: true` messages in InboxEngine.swift also supply an actionDestination.
- **The message-detail Close control is a standard gold toolbar button, not a purple pill**
  - `TODO.md:3541` · design
  - MessageDetailView.swift:74-80 — `ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() }.foregroundStyle(Color.accentGold) }`. The purple in this file is now only `senderColor`/`categoryColor` for media messages (:232, :250).
- **The category and Action Required chips on a message share one capsule shape, padding and type step**
  - `TODO.md:3542` · design
  - MessageDetailView.swift:110-140 — both `categoryBadge` and `actionRequiredBadge` use `.caption2`, `.padding(.horizontal, 8).padding(.vertical, 3)` and `Capsule()`; only the fill colour differs.
- **Inbox messages sign off with the sender, and the body cannot be truncated in the detail view**
  - `TODO.md:3544` · design
  - InboxEngine.swift:255 ends the combine letter "Scouting Department"; the owner check-in ends with `\(ownerName)` (:298) and the media piece with "League Network Draft Coverage" (:283). MessageDetailView.swift:46-50 renders the body with `.fixedSize(horizontal: false, vertical: true)` inside a `ScrollView`.
- **The Director of Scouting now mails a combine digest naming real prospects off the actual combine sheet**
  - `TODO.md:3550` · feature
  - InboxEngine.swift:1263-1305 `combineMediaDigestMessage` builds "Stock up: / Came out of nowhere: / Stock down: / Athletic standouts:" blocks of `"- \(position) \(prospectName)"` from `ScoutingEngine.CombineMediaMention`, subject "Combine board movement: N up, M down". Delivered at WeekAdvancer.swift:3760-3770 off `ScoutingEngine.combineMediaDigest(prospects: currentDraftClass)`.
- **Messages end with a list of deep-linked next actions rather than closing on prose**
  - `TODO.md:3556` · design
  - MessageDetailView.swift:145-190 renders an ATTACHMENTS section of tappable navigation rows at the bottom of the body, followed by the `actionButton` CTA (:62-66). The combine letter's rows are "View Scouting Hub" and "Update Big Board" (InboxEngine.swift:262-265) — two of the three actions the review asked for.

### owner · 9

- **Owner portraits and names are gender-matched — a female owner draws a female first-name pool and a female-only portrait.**
  - `TODO.md:2934` · bug
  - dynasty/dynasty/Domain/Models/Team/Owner.swift:88-107 (`gender` + gender-strict `faceID`/`avatarID` contract); dynasty/dynasty/Data/Import/LeagueGenerator.swift:545-575 (`isFemale` selects `ownerFemaleFirstNames` and `ExtrasCatalog.ownerFaceID(for:gender:)`)
- **The OWNER MEETING eyebrow is heavy display type at 4pt tracking in textSecondary, not thin yellow.**
  - `TODO.md:2935` · design
  - dynasty/dynasty/UI/News/OwnerBriefing.swift:478-486 — `DSType.display(footnote, .black)`, `.tracking(4)`, `Color.textSecondary` (§2.9: section heads are not gold)
- **Owner trait rows carry their verdict in the value colour (green / blue / amber / red); the leading glyph is a neutral bullet, not four identical gold icons.**
  - `TODO.md:2936` · design
  - dynasty/dynasty/UI/News/OwnerBriefing.swift:106-118 (`spendingLabel`/`meddlingLabel` colour bands), 409-434 ("bullet, not a highlight" — glyph is `textTertiaryReadable`), 616-628
- **Restrictive owner traits (tight wallet, Highly Controlling) render in the danger hue and permissive ones in green.**
  - `TODO.md:2937` · design
  - dynasty/dynasty/UI/News/OwnerBriefing.swift:106-118 — spending <25 → `dangerText`, meddling ≥75 → `dangerText`, meddling <25 → `success`
- **The owner's consequences line ("Failure may result in budget cuts, forced trades, or termination.") wraps in full instead of truncating.**
  - `TODO.md:2938` · bug
  - dynasty/dynasty/UI/News/OwnerBriefing.swift:873-882 — full string with `.fixedSize(horizontal: false, vertical: true)` and no lineLimit
- **Each owner trait row has 8pt between the fact and its explainer, with 12pt plus a divider between traits.**
  - `TODO.md:2939` · design
  - dynasty/dynasty/UI/News/OwnerBriefing.swift:624-633 (`VStack(spacing: DSSpacing.xs)` around fact + implication, `DSSpacing.sm` + Divider between priorities); dynasty/dynasty/UI/Common/Theme.swift:186-192 (xs = 8, sm = 12)
- **Owner meddling drives real mid-season events: Meddler-archetype owners fire 1-2 whims a season into the inbox and the answer moves satisfaction.**
  - `TODO.md:2943` · verification
  - dynasty/dynasty/Engine/Media/OwnerPersonaEngine.swift:198-236 (`rollWhim` gates on `.meddler`, weeks 2-13; `respond` moves `owner.satisfaction` ±3-5) and Engine/Simulation/WeekAdvancer.swift:1798-1804 (rolled each week, mailed to the inbox)
- **Owner identity and traits are procedurally generated per club — nothing about the owner is hardcoded to a team.**
  - `TODO.md:2947` · verification
  - dynasty/dynasty/Data/Import/LeagueGenerator.swift:524-598 — name from random first/last pools, patience `2...9`, meddling `5...80`, `prefersWinNow` a coin flip, spending from the team preview ±5; the fixed-2026 template only pins gender (`genderOverride`) so the seeded stream stays stable
- **Every owner trait carries a "what this means for you" explainer line under it on both the intro and hub owner screens.**
  - `TODO.md:2950` · design
  - dynasty/dynasty/UI/News/OwnerBriefing.swift:122-196 (vision / patience / budget / meddling implications, each naming the practical consequence) rendered by `OwnerImplicationRow` at 436-455 and 616-635; this was the #15 merge that gave the hub screen the explainers it never had

### contracts · 7

- **Only the endorsed franchise-tag row gets a filled gold pill; the rest are outlined**
  - `TODO.md:3353` · design
  - FranchiseTagView.swift:556-576 — "One tag, eight rows: a filled gold pill on every one of them reads as eight primary actions for a resource the club has exactly one of. Only the favourite is filled" — `isFavourite ? Color.accentGold : Color.accentGold.opacity(0.10)`, driven by `tagFavourite` (:719-731).
- **Franchise-tag recommendations are colour-coded by tier through a per-tier icon and colour**
  - `TODO.md:3355` · design
  - FranchiseTagView.swift:681-717 — `Recommendation` carries `icon`/`color` per tier: elite `star.fill`/accentGold, past-peak `exclamationmark.triangle.fill`/warning, role player `arrow.right.circle.fill`/textTertiary, solid `checkmark.circle.fill`/success. Rendered at :584-592; the sentence itself is deliberately `textPrimary` ("this is the only line in the row that tells the GM what to do, and it was the faintest string on it").
- **The Franchise Tag banner's projected space is the live running total, and the per-row "space after tag" disappears once the tag is spent**
  - `TODO.md:3356` · bug
  - FranchiseTagView.swift:279-289 — `committedNextYear` folds applied tags into the banner's `projectedNextYearSpace`; :596-612 suppresses the row line once `hasUsedTag`, because "once it is spent this line was projecting the room left after a SECOND tag — a number the rules three cards up forbid." With one tag per season the per-row figure is no longer misleading.
- **Spending the franchise tag disables every remaining Apply Tag button and the banner counts the resource**
  - `TODO.md:3357` · design
  - FranchiseTagView.swift:547-554 — `hasUsedTag` swaps each pill for a disabled "Tag Used" chip; :227-236 adds "1 tag available" / "0 tags left" beside the expiring count, with the comment "The tag is a one-shot, and the only place that said so was a sentence buried in the grey rules paragraph."
- **The gold star on a franchise-tag row is the 85+ elite tier's glyph, applied to every such row with its meaning stated beside it**
  - `TODO.md:3358` · design
  - FranchiseTagView.swift:685-692 — the `overall >= 85` branch returns `icon: "star.fill", color: .accentGold` with the text "Elite player — strongly consider tagging." Every 85+ row gets it; the four tiers each have their own glyph (:681-717).
- **Tapping a franchise-tag cost opens a per-position breakdown naming the five salaries it averages**
  - `TODO.md:3361` · feature
  - FranchiseTagView.swift:511-547 — the Tag Cost figure is a button opening `tagBreakdownRequest`, with hint "Shows the five salaries the \(position) tag averages"; `TagBreakdownSheet` (:1276-1315) titles itself "\(quote.position.rawValue) Tag Cost" and lists the five men and their clubs.
- **The Franchise Tag screen endorses exactly one man for the one tag, with a stated reason on his row**
  - `TODO.md:3368` · design
  - FranchiseTagView.swift:719-731 — `tagFavourite` picks the best row whose recommendation `endorsesTag` AND whose tag the projected cap can absorb ("the screen has no business urging a tag it would then have to call unaffordable two lines further down"); that row alone gets the filled gold pill, and every row carries its recommendation sentence (:584-592).

### development · 4

- **The quality-pyramid calibration wave shipped — intake level, ceiling slope, veteran potential and the level-bound thresholds were all retuned together**
  - `TODO.md:390` · balance
  - LeagueGenerator.swift:974 `rookieAgeLevel = -8.0` and :976 `primeAgeLevel = 6.0`, both tagged "P1 pyramid calibration (2026-07-30)", plus the new `talentLevelShift` (:1062) and `tierEarnedUpside` (:955). Recorded as done at TODO.md:19 with its own section at TODO.md:219-235 (gates: leaguegen 10/10, draftclass 32/32, career 26/26, check_bundle exit 0).
- **Phase 2 of the development/training overhaul — competitiveness, real playing-time share, and the dead potential-realisation code — shipped**
  - `TODO.md:398` · feature
  - competitiveness is a real attribute (Data/Import/LeagueGenerator.swift:736,777-781; shown as CMP in UI/Roster/PlayerRowView.swift:316); updatePotentialRealization is called at Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:2024 and assessPotential at :1880 — neither is dead; :78-83 documents that playing-time share is now realPlayingTimeShare off gamesStarted/gamesPlayed, "not an OVR-based estimate".
- **The league-potential ratchet (intake potential dragging leaguePot up ~+0.9/season) is dead**
  - `TODO.md:399` · balance
  - Data/Import/LeagueGenerator.swift:1023-1026 — the generator's mean is now set to "where the DEVELOPMENT stack's own 30-season equilibrium lands (career harness: 71.4)", and :800-813 records the P1 fix that made veteran upside earned rather than granted; TODO.md:385 measures leaguePot plateauing at +0.14.
- **The quality-pyramid miss against DEVELOPMENT_NFL_REFERENCE §8 was closed by the calibration wave, on both of the two causes the measurement named**
  - `TODO.md:400` · balance
  - Cause (b) is gone: developmentCeiling is identity below an 84 blue-chip pivot, not 0.60·pot+39 (Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:64-71). Cause (a) is gone: LeagueGenerator.targetQualityPyramid now lands 90+ 1.80 % / 80+ 17.10 % / 75+ 35.06 % / sub-65 23.43 % / mean 71.00 against §8's 1-2 / 12-16 / 30-40 / ~25 (Data/Import/LeagueGenerator.swift:987-1034). Note TODO.md:387, which forward-references this line as still open, is stale for the same reason.

### faces · 4

- **The generated portraits and their manifest are bundled in the app's Resources**
  - `TODO.md:346` · feature
  - dynasty/dynasty/Resources/Faces/ holds 7 540 .heic portraits plus faces_manifest.json (keys: version, seed, faces), committed in ba8453b ("3 584-portrait face library") and extended by c8a11f4 ("163 female coach faces").
- **PersonFaceView is wired into every surface the face wave listed — player detail, roster rows, prospects, draft panels, coach views, news and Hall of Fame**
  - `TODO.md:347` · feature
  - PlayerDetailView.swift:696 (hero, `.large` with team ring), PlayerRowView.swift, BigBoardView.swift + ProspectDetailView.swift + ProspectListControls.swift, WarRoomPanel/DraftTickerPanel/TradeUpBoardSheet, CoachDetailView/CoachingStaffView/HireCoachView, NewsView.swift:531, LeagueHistoryView.swift:386 (HOF entries).
- **The selected coach portrait gets a 3 pt gold ring and a 1.1x scale, not just gold name text.**
  - `TODO.md:2721` · design
  - UserPortraitView.swift:302-309 — Circle().strokeBorder(isSelected ? Color.accentGold : .clear, lineWidth: 3) plus .scaleEffect(isSelected ? 1.1 : 1.0).
- **Every coach-portrait slot holds real content: 20 photos in the extras manifest, each with a persona label drawn from a per-gender list.**
  - `TODO.md:2738` · verification
  - dynasty/dynasty/Resources/Faces/extra_faces_manifest.json contains 20 distinct avatar_000NN ids; ExtrasCatalog.avatars (ExtrasCatalog.swift:144-150) is "The 20 user-avatar portraits"; labels are built per gender at UserPortraitView.swift:45-60 and wrap rather than run out; an absent manifest renders "Portraits are unavailable in this build." (UserPortraitView.swift:258-264) instead of blank discs.

### main menu · 4

- **The main menu gave no "last played" hint, so returning players had to tap through to find where they were**
  - `TODO.md:2693` · feature
  - MainMenuView.swift:214-243 — `continueHintBlock` prints `continueHintText(for:)` above the button stack, formatted "CONTINUE: Green Bay Timberjacks — Week 6, 2026 season" (:269), resolving the team name from the teams query and choosing between a week anchor and a phase-group anchor (:251-265). With more than one save it becomes "N ACTIVE DYNASTIES" instead (:216-223).
- **There was no save-slot picker, so multi-career players could not see their active dynasties**
  - `TODO.md:2694` · feature
  - MainMenuView.swift:792 — `SaveSlotPickerSheet` lists every career from a `@Query` sorted by season. It is reached from a "Continue / Load" primary shown whenever `careers.count > 1` (:296-306), presented through the screen's single `.sheet(item:)` point (:136-144), with the chosen career opened in `onDismiss` via `openPendingCareer` (:150-161). The count is also printed on the menu itself (:217).
- **First-time players got no preview of what the game offers before starting a career**
  - `TODO.md:2695` · feature
  - MainMenuView.swift:337-343 — a "How to Play" button opens `TutorialSheet` (:452-537), which pages through `TutorialPage.all` (:551-718): ten pages covering the weekly career flow, scouting, free agency, the draft, coaching, development and the offseason loop. Settings can re-trigger it via the `pendingTutorialReplay` flag (:110-114). Not implemented, and not required by the item: auto-showing it on first launch.
- **League and difficulty presets were buried in Settings instead of being offered at career start**
  - `TODO.md:2696` · feature
  - NewCareerView.swift:182-193 — step 1 opens with an explicit segmented "Quick Start" vs "Custom League" toggle (`FlowMode`, :6-7), and Quick Start collapses the wizard from four steps to two (:86). `quickStartSettings` (:528-560) surfaces the four settings the sim actually reads as live controls on that first screen, pre-filled, with the note that Custom League adds the side-by-side comparisons.

### tasks · 4

- **"Review interview report" completes on three independent hooks plus a stuck-save backstop, so it can no longer block the advance indefinitely.**
  - `TODO.md:3560` · bug
  - CareerScopedDefaults "interviewReportReviewed" is set by InterviewReportView's .onAppear (InterviewSelectionView.swift:1535-1539, commented as guaranteeing completion even if the user navigates away), by the Complete Review CTA (:1507-1509) and by the steady-state dismiss (:206-211). CareerShellView.swift:2962-2975 reads it and adds an `interviewsUsed >= 60` backstop; :2583-2586 now hints the Interviews tab on the .interviewReport deep link.
- **"Send scouts to Combine" completes off the persisted scoutsSentToCombine flag, and is optional now, so it can never show a stuck REQUIRED chip.**
  - `TODO.md:3561` · verification
  - ScoutingHubView.sendScoutsToCombine sets the @CareerScopedStorage flag at :533; CareerShellView.swift:2952-2955 marks the task done from it; TaskGenerator.swift:855-860 declares it isRequired: false and the #104 note at :1699-1706 removes it from combineChain so it gates nothing; WeekAdvancer.swift:417 clears it per draft cycle.
- **The required-task counter is a live derivation over the task array, and the blocker banner now names the row instead of printing only a number.**
  - `TODO.md:3563` · verification
  - TaskGenerator.incompleteRequiredCount(in:) is `tasks.filter { $0.isRequired && $0.status != .done }.count` (TaskGenerator.swift:1661-1663), so it cannot drift. TimelineTasksPanel.swift:788-816 prints "Required: <title>" plus "N more required tasks after it", and per the #154f note at :788-796 suppresses the sentence entirely when something other than the task list is holding the advance.
- **Sidebar tasks now rebuild on a week change as well as a phase change, so regular-season tasks no longer persist across weeks**
  - `TODO.md:3669` · bug
  - CareerShellView.swift:3156-3161 — `guard phase != lastGeneratedPhase || week != lastGeneratedWeek else { return }`, with the doc comment: "Rebuilt on a phase change **or a week change**: several titles name the week's opponent, and in the regular season the phase does not move for eighteen of them (#154)."

### camp · 3

- **The voluntary workout prompt names the phase outside the regular season instead of printing a bogus week number**
  - `TODO.md:3668` · bug
  - VoluntaryWorkoutPrompt.swift:59-70 — `headerTitle` returns "Week N — Pick One" only for `.regularSeason`/`.tradeDeadline`/`.playoffs` and `"\(career.currentPhase.displayName) — Pick One"` otherwise, with the fix documented: "a July training camp prompt headed 'Week 21' claims a week of a seventeen-game season that does not exist."
- **The strength coach is no longer a placebo — a camp week is netted once in Double, restoring the resolution his 1-99 rating was meant to buy.**
  - `TODO.md:4122` · balance
  - WorkloadEngine.tickWeek (:207-220) computes weekLoad and weekRecovery as Doubles and rounds the net once, replacing seven per-day double-roundings; the doc comment at :187-205 cites the same lockerroom B2 measurement this item raised. The band anchors it invalidated were re-measured off the new curve: underloadedMax/healthyMax/overloadedMax are now 37/64/73 (:59-64), replacing 30/56/63, derived as p10/p90/p99 of the measured distribution.
- **The camp letter grade is no longer decided by overall — its training term was re-anchored on the load the camp scheduler can actually emit.**
  - `TODO.md:4219` · balance
  - WeekAdvancer.swift:8910-8913 now computes trainingPts as cumulativeLoad * 30 / WorkloadEngine.burnoutFloor, replacing the /6 that assumed a ~180 load; the reasoning and the re-modelled distribution (A 1.4%, B 33.4%, C 57.5%, D 7.7%, from 0% A / 0% B / 66% D) are recorded at :8895-8909 and in commit ec81e5a. Two residuals the commit states rather than hides: the grade still correlates 0.60 with OVR, and the training-focus split still never reaches the workload tick — intensity at :8692 is campIntensity(for: phase), not per-player.

### depth chart · 3

- **Mark depth-chart candidates who already hold a slot at another position, so picking them cannot silently strip it**
  - `TODO.md:3626` · design
  - dynasty/dynasty/UI/Roster/DepthChartView.swift:1679-1683 computes heldElsewhere = depthChart.slots(holding:excluding:) — every slot, not just this one — and :1761-1770 renders it as a warning-tinted "In LOLB·MLB" capsule with the full list spoken by VoiceOver.
- **Unify the depth-chart group completion badge so starters and backups are counted in one visible signal**
  - `TODO.md:3627` · design
  - dynasty/dynasty/UI/Roster/DepthChartView.swift:851-863 computes filledStarters, filledDepth and totalDepth; :900-909 renders "2/2 · 5/6 deep" with a three-state glyph (exposed/partial/complete) and :922-927 adds the roomWarning line ("No backup at MLB").
- **The decision was taken and shipped: the depth chart now fields the team, falling back to highest-overall only where a slot names nobody usable.**
  - `TODO.md:4200` · design
  - WeekAdvancer.startingLineupIDs(available:chart:) (:7309-7362) walks the user's own order per slot and only then runs the old max-by-overall search; nil for all 31 AI clubs is byte-for-byte the pre-chart path (:7302-7308). The same chart drives the game's depth ranks (GameSimulator.swift:156-162), so the starter and his stat line agree. Wired at WeekAdvancer.swift:1374-1379 via DepthChart.saved(career:roster:). Residual, and explicitly documented: KR/PR are still gated by "Lineup Incomplete" while rollKickoff reads no player at all (GameSimulator.swift:1472-1480).

### sim · 3

- **A defender's empty live stat line reads "No stats yet"; only skill players get "No touches yet".**
  - `TODO.md:2177` · design
  - dynasty/dynasty/UI/Match/CoachesBoardView.swift:504-510 — `emptyStatLineText` branches on `selectedPlayer.position.side == .defense`
- **Distant snowflakes no longer read as a starfield against the dark sky.**
  - `TODO.md:2179` · design
  - dynasty/dynasty/UI/Match/FootballFieldScene.swift:5893-5900 (snow fog lifted to sky-glow grey "so distant flakes melt into the haze instead of reading as a starfield"), 5908-5929 (sky background tinted to the fog colour because SceneKit fog does not touch particles), 5970-5978 (emitter slab kept low so far flakes stay below the field edge)
- **Playoff games run the full GameSimulator and the player's saved game plan shades his own side.**
  - `TODO.md:2577` · bug
  - WeekAdvancer.swift:7655-7679 inside `playPlayoffGames` — `GameSimulator.simulate(… homeGamePlan: homeTeam.id == userTeamID ? plan : nil, awayGamePlan: …)`; `simulateGameScore()` survives only as the fallback for games whose teams the career scope cannot resolve (:7733, documented at :7608-7610).

### staff · 3

- **The dashboard Staff tile's seat count and its money both come from one StaffLedger, so an empty staff cannot show a spent budget.**
  - `TODO.md:2890` · bug
  - CareerDashboardView.swift:2411-2492 reads totalSlots / filledSlots / remainingCoaching off staffLedger with no local role filter or fallback. StaffLedger sums one row per seat (Domain/Staff/StaffLedger.swift:99-120) and hides money entirely when no owner has resolved (:77-78). The figure is explicitly labelled "Budget left" / "Budget unspent" rather than spent (:2480).
- **The QA follow-ups tracked out of the cap-year wave (staff counters, rank flicker, auto-hire conflict fits, dead ledger members) all landed**
  - `TODO.md:4480` · verification
  - TODO.md:3858 records the shipping commits, both of which exist: 91f62a5 "feat(ui+fixes): Scout Notes tab, insights closed by default, the small pile" (#133/#135/#158) and 8ba35f1 "fix(staff+dashboard): one staff-slot truth, offseason poach grace, stable ranks" (#134). Root causes and the #131 sweep (7 dead members, −37 lines) are written up at TODO.md:5054-5055, including the one deliberate carve-out: `LegacyTracker.pressPromises` is kept because it is a stored `Codable` field on `Career.legacy` (LegacyTracker.swift:6, 19, 81) and removing it is a save-format change deferred to #171.
- **One StaffLedger answers seats, salaries and the advance gate for staff, fixing the per-row salary sum, the invented budgets and the Season Guide's ungated advance.**
  - `TODO.md:5054` · bug
  - Domain/Staff/StaffLedger.swift (231 lines) resolves one occupant per seat before summing salaries (:99-120) and refuses to invent an envelope when no owner has resolved (isResolved, :77-78). CareerShellView.swift:2741-2761 computes it once and feeds advanceGateBlocker; CareerDashboardView.swift:243-256 and CalendarSidebarView.swift:14-24 + :54-55 both consume the same value. The entry's own caveat still stands: the relaunch symptom was never reproduced on device.

### team selection · 3

- **Cap space, roster OVR and draft picks were sized smallest despite being the core decision data**
  - `TODO.md:2671` · design
  - TeamSelectionView.swift:1581-1611 — `statsRow` is one card carrying all three through a single `detailStat` recipe (icon + caption label + `title2` black value + anchor line, :1432-1451). It is promoted directly under the difficulty row in both layouts, with the comment "Franchise vitals promoted directly under the header" (:1774, :1801). Coaching budget remains its own card below (:1716).
- **Team detail numbers had no league-average anchor, so "Cap $25M" said nothing about rank**
  - `TODO.md:2672` · feature
  - TeamSelectionView.swift:1571-1579 — `leagueAverages` computes the mean OVR, cap space and draft picks across the browsed catalog, and each `detailStat` prints it as its anchor line: "League 78", "League $24M", "League 7" (:1583-1610). The coaching budget card carries the same treatment via `leagueAvgCoachingBudget` (:1712, :1729).
- **The Coaching Budget figure carried an unexplained warning icon with no way to tell if the number was low**
  - `TODO.md:2676` · bug
  - TeamSelectionView.swift:1716-1740 — `coachingBudgetCard` uses `dollarsign.square.fill`, not a warning glyph, tinted on a three-band ladder (success at 40M+, accentBlue at 30M+, warning below), and prints "League average: $NNM" from `leagueAvgCoachingBudget` (:1712, computed by `TeamBrowseCatalog.averageCoachingBudget` at TeamBrowseCatalog.swift:59-63). The colour is now a stated comparison, not an unexplained alarm.

### trades · 3

- **CareerShellView computes hasPendingTradeOffers from the career's live pending offers and feeds it to the task generator.**
  - `TODO.md:2742` · feature
  - dynasty/dynasty/UI/Career/CareerShellView.swift:3172 (`let hasPendingTradeOffers = !career.pendingTradeOffers.isEmpty`) and 3255 (passed into `TaskGenerator`, declared at Engine/Simulation/TaskGenerator.swift:411)
- **AI trade concessions are capped per GM archetype instead of walking back 100% of the premium by round 10.**
  - `TODO.md:5056` · balance
  - GMArchetype.concessionCap returns 0.35 / 0.55 / 0.40 / 0.65 (Engine/Contract/TradeValueEngine.swift:361-368), lifted only by deadlinePressure(week:) (:2495) and needPressure (:2504) inside concessionCeiling (:2464-2470). counterLead's balanced line is now "hold where they are — this is their number" (:2729).
- **An AI-initiated trade comeback in deadline week now prices its urgency from the current calendar week, not the week the thread opened.**
  - `TODO.md:5063` · bug
  - WeekAdvancer.swift:6294-6308 passes pressureWeek: week explicitly, with a comment naming exactly this defect ("a comeback in deadline week priced from a week-3 opening would never feel the clock"). TradeValueEngine.respond takes pressureWeek: Int? defaulting to the pricing week (:2161, :2269) and concessionCeiling reads it (:2464-2468).

### training · 3

- **Per-player individual training focus exists — attribute-target areas per man, a hard three-slot team budget, and a weekly roll that pays out visible gains.**
  - `TODO.md:3643` · feature
  - R26 TrainingFocusEngine.swift:9-70 defines 17 TrainingFocusArea cases with per-position lists; maxFocusPlayersPerTeam = 3 is the shared budget (:125), enforced in applyWeeklyFocusTick (:209-211) and autoAssignFocus (:358-368). Assignment UI is DevelopmentReportView.swift:640-665 and :1168-1172; the weekly roll runs from WeekAdvancer and reports FocusGain rows.
- **A Development Report lands in the inbox after every training week and again after camp, naming who gained what.**
  - `TODO.md:3644` · feature
  - WeekAdvancer.swift:2165-2184 builds the weekly edition (focus gains, mentor pairs, breakouts, stalled players) and appends DevelopmentReportBuilder.inboxMessage; WeekAdvancer.swift:4278-4298 files the camp edition built by buildCampReport (TrainingFocusEngine.swift:838-900: late bloomers, driven, complacent, plateaued, install-year laggards). Both are kept on career.developmentReports and rendered by DevelopmentReportView.
- **Coach quality visibly moves training output: the focus picker prints a per-week gain chance that the position coach's development rating shifts.**
  - `TODO.md:3646` · design
  - TrainingFocusEngine.weeklyGainChance (:244-270) folds in a coachFactor of 1.0 ± 0.3·(coachDev-50)/99 from the matching position coach (coordinator fallback). DevelopmentReportView surfaces it as "%/wk" per candidate (:195-216, :252, :1115), ranks candidates by expected gain, and explains it at :1073. Residual: the coach's share is not itemised out of the blended number.

### cap · 2

- **The Cap Usage bar and its percentage are threshold-coloured (<80 green, 80-90 amber, 90-95 orange, >95 red) with a tap popover explaining the bands.**
  - `TODO.md:3332` · design
  - dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:2344-2351 (`capThresholdColor`), 2360-2363 (`capBarGradientThreshold`), 1655-1674 (bar + popover), 2383-2410 (band legend)
- **The roster evaluation quotes the franchise-tag cost for an elite expiring player the club has no room to extend.**
  - `TODO.md:3344` · feature
  - dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:2274-2287 ("The tag holds him a year at $X" when `team.availableCap < marketValue`) and 2305-2313 (`ContractEngine.franchiseTagValue`, the same number the tag screen charges). No navigation link to the tag flow, but the preview and its price are on the screen

### match · 2

- **Coach-camera snow no longer spawns lens-filling blobs: coach shots run 0.09 flakes at 0.45 alpha in a slab pushed 12 units downfield of the low lens.**
  - `TODO.md:1911` · bug
  - dynasty/dynasty/UI/Match/FootballFieldScene.swift:6106-6124 (snowSystem(coach:) halves particleSize 0.15→0.09 and alpha 0.62→0.45, shrinks the emitter box), :5987-5994 (weatherSlabZOffset), :5971-5981; the comment at :6102-6105 names the old "head-sized white balls" symptom.
- **Billboard jersey numbers drop to 0.2 opacity in the coach camera and sit clear above the helmet, killing the ghost-number read.**
  - `TODO.md:1912` · design
  - dynasty/dynasty/UI/Match/FootballFieldScene.swift:468-480 (billboardNumberOpacity = 0.2 for coach vs 0.6 broadcast, applied on every style switch) and :5570-5578 (node raised to y 1.52, with the low-angle phantom-number rationale).

### tooling · 2

- **The anonymization bundle gate is hard gate #1 on the pre-ship release checklist.**
  - `TODO.md:383` · tech-debt
  - docs/RELEASE_CHECKLIST.md:1-14 — "1. **Anonymization bundle gate** — `tools/league-data/check_bundle.sh` … Must exit 0", with a re-run instruction if templates change. (No CI workflow exists in this repo; the checklist is the resting place the item itself proposed.)
- **Diagnostic clip renders are bright — the harness defaults to Workbench STUDIO lighting with a high-contrast figure material**
  - `TODO.md:4320` · tech-debt
  - tools/asset-pipeline/render_verify.py:121-141 `setup_render` defaults to `BLENDER_WORKBENCH` (:77, :92) with `display.shading.light = "STUDIO"`, `color_type = "MATERIAL"`, shadows and cavity on; the EEVEE path gets a 3.2-energy sun. :156-170 `paint()` — "Green turf plane at the measured foot plane + bright figure material" (0.86, 0.47, 0.13). The TODO's own next section records the bright 14-frame filmstrips shipping for all 22 clips.

### balance · 1

- **The potential-realisation over-delivery behind #97 was fixed, measured alone and last, exactly as the queue entry demanded.**
  - `TODO.md:4182` · balance
  - Commit 834ade0: 6.9b (80+ share) 19.17% FAIL → 17.64% PASS with §6.2a/§6.2b/§6.9a unmoved. Both causes are in the tree — updatePotentialRealization's scheme-fit rungs now read the edge against CoachingEngine.schemeFitNeutral = 0.594 (PlayerDevelopmentEngine.swift:1650-1672, CoachingEngine.swift:345), and primeWindowDamper is applied to developPlayer's in-peak channel (PlayerDevelopmentEngine.swift:268, :708). Residual recorded in the commit, not lost: 6.9g (33+ share) is 4.05% against a 4.0% ceiling, and the lever that clears it was built, measured and reverted because it trades one red for another.

### coached game · 1

- **The play-call category tab snaps to the AI suggestion's category on every new snap.**
  - `TODO.md:3699` · design
  - CoachedGameView.swift:3575-3590 (proceed) sets selectedCall = rec.call and selectedCategory = rec.call.category when the user's offense lines up; the coordinator bubble's re-select does the same (1596-1600), as do the fourth-down and conversion paths (2030, 2497). Only a deliberate tab tap (1835) moves it elsewhere, which is correct.

### match ui · 1

- **The result/injury/milestone toast now floats above whatever height the bottom panel has, instead of a fixed 352pt offset.**
  - `TODO.md:2311` · bug
  - CoachedGameView.swift:2832-2836 — "Rendered as a bottom overlay on the field section … so the stack floats just above the bottom panel whatever height the panel happens to have"; attached at :1116 `.overlay(alignment: .bottom) { bannerOverlay }` with `.padding(.bottom, 54)` at :2893 and `.allowsHitTesting(false)` at :2898.

### navigation · 1

- **Schedule and Standings came off the top navigation strip entirely and are reached from the hub's UPCOMING and DIVISION headers instead.**
  - `TODO.md:3386` · design
  - dynasty/dynasty/UI/Common/TopNavigationBar.swift:46-72 — defaultBookmarks is Hub / Roster / Staff / Cap / Scouting / Draft / Trades, and :58-60 records that Schedule, Standings and News were removed once the hub carried routes to them.

### schedule · 1

- **The double-bye schedule bug is fixed — bye assignment retries with parity repair and a DEBUG validator asserts exactly one bye per team.**
  - `TODO.md:3718` · bug
  - ScheduleGenerator.swift:56-75 `validate` flags any team without exactly 17 games and exactly one empty week across 18; `assignByeWeeks` plus odd-week parity repair at :259-314, re-rolled on every retry (:324-345).

---

## Stale

104 items whose premise no longer holds, or which a later change superseded.

### roster · 19

- **The roster position-group header was rebuilt around one chip shape and deliberately spells its grades out rather than dropping the labels.**
  - `TODO.md:3158` · design
  - RosterView.swift:1753-1797 (`DSGroupRollup` at :1759 + `gradeReadout` + a single `stateChip` shape for every state); the rationale at :1815-1821 records the choice to expand "S:"/"D:" into "Starters B+ 74 avg · Depth C+ 61 avg".
- **'Project Need' no longer exists as a group label — the staff read now names its own cause (Starter needed / Depth thin / Key FA pending / Aging …).**
  - `TODO.md:3166` · design
  - No "Project Need" string exists in any Swift source; RosterView.swift:119-165 `staffAssessment` returns the ten labels actually drawn, each derived from the starter/depth grades printed beside it.
- **There is no 'Trade Watch' tag on roster players anywhere in the app.**
  - `TODO.md:3167` · design
  - grep for "Trade Watch" across all Swift sources returns nothing; the roster row's only state markers are the FIT/EXT/HLTH slots plus Tag/Out pills (PlayerRowView.swift:190-200).
- **A cross-reference to the Offense tab's row-density notes, carrying no finding of its own — and the roster row has since been rebuilt on the shared list grammar.**
  - `TODO.md:3177` · note
  - PlayerRowView.swift lays every cell out through .dsColumn(DSListColumn.…) and the three fixed state slots FIT/EXT/HLTH (214-226, 337-385); the offence and defence tabs render the identical component from RosterView.swift:664-684, so there is no defence-specific chrome left to triage here.
- **Red down-arrows no longer cover the default roster list — the overview lens replaced the trend arrow with a numeric headroom column.**
  - `TODO.md:3181` · design
  - RosterView.swift:48 defaults analysisMode to .overview, whose columns (PlayerRowView.swift:337-385) end in shortPotentialLabel "+N" (826-848) with no arrow. developmentArrow (816-824) is now drawn only by developmentColumns (473-511), the Development lens, where a direction is the column's whole point.
- **The "Trade Watch" chip this asked to price no longer exists anywhere on the roster.**
  - `TODO.md:3185` · design
  - No "Trade Watch"/tradeWatch string survives in the codebase; the roster row's chips are the depth chip and the FIT/EXT/HLTH slots (PlayerRowView.swift:214-300). Trade value now lives in PlayerDetailView.swift:1671-1740 as a card with "~N pts" and a base/age/contract factor breakdown.
- **The "Trade Watch" badge no longer exists in the app, so there is no generator behaviour left to audit.**
  - `TODO.md:3205` · bug
  - The string appears only in TODO.md and docs/TRADE_OVERHAUL_PLAN.md:146 (which lists "'Trade Watch' badges link nowhere" as symptom S8); it exists in no Swift file, and `git log -S "Trade Watch" -- dynasty` returns nothing. The surviving trade-flagging concept is the user-driven `TradeBlockStore` (Domain/Models/Trade/TradeBlockStore.swift:48).
- **The player detail hero's dense four-figure strip (morale / health / salary / contract) was deliberately cut to a single health pill**
  - `TODO.md:3215` · note
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:805-814 — "Health is the ONLY figure left in the hero strip"; the other four were removed because they were restated in the Overview and Contract cards in a different encoding.
- **The player detail five-button action grid was replaced by DSActionBar, and the extension button's money teaser was deliberately deleted**
  - `TODO.md:3222` · note
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:1948-1956 (destructive/ghost/secondary/primary slots) and :2107-2117 — the "~$38.4M/yr · 3yr" caption was removed on purpose (#127) so the agent's ask is discovered in the negotiation, not printed on the door.
- **The "Set as Starter" button on player detail no longer exists, so there is no starter/bench toggle state to verify**
  - `TODO.md:3228` · note
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:1941-1944 — "**'Set as Starter' is gone**, because its closure was literally `{}`… The depth chart is where a starter is set."
- **Position-versatility bars are painted from the shared five-tier rating ladder, replacing the two bespoke low-contrast ladders the note describes.**
  - `TODO.md:3237` · design
  - PlayerDetailView.swift:2685-2691 — versatilityBarColor is Color.forRating, with a comment recording that the two ladders it replaced "disagreed with Color.forRating and with each other". Theme.swift:132-139 maps the tiers onto eliteGreen/success/accentBlue/warning/dangerText; the bar sits on a backgroundTertiary track with a ceiling marker (PlayerDetailView.swift:2596-2617).
- **Scheme Familiarity no longer colours bars by scheme identity — both bar length and colour now derive from the same value.**
  - `TODO.md:3239` · design
  - PlayerDetailView.swift:2693-2695 — schemeFamColor is Color.forRating; it feeds the bar fill (:2661-2664) and the percentage text (:2670-2673). The comment at :2685-2688 records that the previous bespoke ladders were removed for exactly this reason.
- **Physical attributes are not "all green": the shared ladder puts 80-89 on green and 70-79 on blue, so Speed 82 and Acceleration 78 land in different bands.**
  - `TODO.md:3242` · design
  - colorForAttribute is Color.forRating (PlayerDetailView.swift:296-298), used for both the numeral and the leading bar in attributeGrid (:2862-2884). RatingTier bands are 90+/80..<90/70..<80/60..<70/else at Theme.swift:160-168, mapping to eliteGreen/success/accentBlue/warning/dangerText.
- **The second number beside a QB skill was the position's league average, not a scout rating, and it now prints as a signed delta**
  - `TODO.md:3256` · design
  - PlayerDetailView.swift:2793-2803 feeds `qbLeagueAverages` into `attributeGridWithAvg`, which at :2904-2910 draws `leagueDeltaText` ("+8" / "-4" / "±0") colour-coded by `leagueDeltaColor`, with the VoiceOver label "… versus the league average for this position, 79". The code comment names the bare "(68)" parenthetical as the thing it replaced (#182). No scouting-accuracy mechanic was ever behind it.
- **An attribute equal to its position's league average now reads "±0", which is information rather than a redundant repeat**
  - `TODO.md:3257` · design
  - PlayerDetailView.swift:2918-2932 — `leagueDeltaText` returns "±0" on equality and `leagueDeltaColor` paints it neutral `textTertiaryReadable` inside the ±5 noise band. The "89 (89)" form the item describes no longer exists; suppressing the equal case would delete the comparison, not a duplicate.
- **The Scheme Fit card was rebuilt as a design-system card with one explainer line and four label/value rows**
  - `TODO.md:3260` · design
  - PlayerDetailView.swift:2699-2742 — `DSDetailCard("Scheme Fit", explainer: "Which system he already knows, and the two profile averages a coordinator reads before he installs anything.")` over Best Scheme / Position Group / Physical Profile / Mental Profile rows. There is no loose prose left to tighten.
- **"Football IQ Genius" is a descriptive band on the mental-attribute average, not an archetype with its own gameplay effect**
  - `TODO.md:3264` · note
  - PlayerDetailView.swift:3179-3187 `mentalProfileLabel` maps mental average 85+ to that phrase, shown with the raw average beside it at :2730-2741; the attributes it summarises are itemised in the Mental Attributes card (:2771-2785). Real archetypes already carry effect copy — `archetypeEffectDescription` (:3051-3064) rendered as a `DSDetailNote` under the Archetype row.
- **A fully stocked K/P room can no longer show a red "Depth needed" badge beside a strong special-teams grade**
  - `TODO.md:3321` · bug
  - RosterView.swift:1668-1670 — `calculatePositionGrades` returns `noDepthGrade` (an em dash, :1608) instead of "F" when there are no backups, with a comment naming special teams as the case; `assessNeeds` only raises "Depth needed" on a D/F depth grade (RosterEvaluationView.swift:876-878). The contradiction the item describes is designed out, not annotated.
- **System-recommended position priorities shipped as one-tap Auto-Set Priorities rather than as a "Recommended priorities (3)" card**
  - `TODO.md:3325` · feature
  - RosterEvaluationView.swift:463-486 (`autoSetPrioritiesButton`) and :502-528 (`applyAutoPriorities`) — scores every group from starter/depth grade, `DraftEngine.teamNeedDeficits` rank, expiring starters and starter age (heuristic table documented at :530-560), then reports "N high · N medium · N low". Same decision support, different affordance.

### scouting · 15

- **Regional scouts are not redundant hires — each of the five covers a distinct college region, so there are no diminishing returns to communicate.**
  - `TODO.md:3108` · balance
  - dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift:2656-2695 (`colleges(forRegion:)` maps each role to its own conferences; East / West / South / North / Central) and 2777-2780 (weekly reports draw only from that scout's region); the row already names the beat via `ScoutRole.displayName` = "Regional Scout (East)". The generic "+5% regional prospect coverage" copy at CoachingStaffView.swift:1231-1237 is the only vague part
- **There is no cap on parallel scout effectiveness to reinforce — regional beats do not overlap, and the Chief Scout / regional badge split already differentiates the seats.**
  - `TODO.md:3109` · design
  - dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift:2656-2711 (non-overlapping region map; the chief has no region) and UI/Staff/CoachingStaffView.swift:1240-1246 (priority split already shipped)
- **The flat seven-tab scouting bar is gone; the hub is a six-slat stage band with the reference screens grouped behind a War Room slat.**
  - `TODO.md:3395` · design
  - ScoutingHubView.swift:751-752 `warRoomTabs` = [.board, .classDepth, .scoutNotes, .draftOrder, .mockDraft, .scouts]; :932-963 draws `DraftPrepProcessBar` (six stage slats) and shows `ScoutingWarRoomTabs` only while `isWarRoomSelected` (:783). The grouping the item asked for is exactly what replaced it.
- **Position Depth Analysis and the board's risk pills no longer share a screen, so the green-on-green collision described is gone.**
  - `TODO.md:3397` · design
  - BigBoardView.swift:1268-1278 records the #105 split: "Recommendations" and "Position Depth Analysis" moved off the board's List onto `ScoutNotesView` (ScoutNotesView.swift:260-364). The `Safe`/`Boom-Bust` pills stay on board rows via `ProspectRiskBadge` (ProspectListControls.swift:828), a different surface.
- **The big-board row's ad-hoc trailing chip stack was replaced by a frozen DSListRow column grammar with a five-mode lens selector.**
  - `TODO.md:3398` · design
  - BigBoardView.swift:2404-2463 — the row is a `DSListRow` with a documented, frozen column order and the mode-specific block supplied by `ProspectColumns.cells(for:mode:)` (ProspectListControls.swift:774-793). Overview keeps age/production/fit/need/risk (:796-832); Work-up, Physical, Mental and Position each swap that block, which is the density answer that landed instead of a per-chip tap.
- **The Combine Report sheet dismisses with a standard nav-bar Done in .confirmationAction — the small pill this described no longer exists.**
  - `TODO.md:3415` · design
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1841-1848 — NavigationStack with .navigationTitle("Combine Report"), .navigationBarTitleDisplayMode(.inline) and ToolbarItem(placement: .confirmationAction) { Button("Done") }.
- **The Combine Report is a plain SwiftUI .sheet(item:), so its backdrop dimming is system-owned and not tunable from the app.**
  - `TODO.md:3419` · design
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:403-408 — .sheet(item: $activeHubSheet) with no presentationBackground, presentationDetents or custom overlay anywhere in the file.
- **The Combine Report is no longer four names — the generator produces roughly a dozen mentions across four categories — and it presents as a standard system sheet.**
  - `TODO.md:3420` · design
  - Engine/Scouting/ScoutingEngine.swift:3524 (4-7 standouts), :3548-3549 (3-5 risers), :3565-3566 (2-3 fallers), :3584 (2-3 surprises); ScoutingHubView.swift:403-408 presents it via .sheet(item:) with no detents.
- **The combine table's unlabelled leading column is the app's single shared prospect mark control, not a duplicate of the Big Board star**
  - `TODO.md:3439` · design
  - CombineResultsView.swift:717-719 is a blank header over `ProspectMarkButton` (:887-891), described in the code as "The ONE mark, same control as the board and the prospect list"; the control itself (ProspectGradeMenuView.swift:60-81) draws `circle.dashed` when unmarked and carries its own VoiceOver label. The "remove if redundant" premise is refuted by design.
- **The combine results table is a single lazy List with one scroll owner, so no pagination or scroll indicator is needed**
  - `TODO.md:3445` · design
  - CombineResultsView.swift:369-470 — rows are one `Section` inside a `List`, the hub header is the list's first section, and the doc comment at :74-84 records that the old layout (a horizontal table nested inside a vertical scroll) was the reported problem. The count line at :541-546 still prints "N of M prospects invited".
- **The red markers near a combine row's position label mean defence (side colour) and roster need — the same question line 3437 already tracks**
  - `TODO.md:3447` · design
  - Duplicate of TODO.md:3437. Answered in code: CombineResultsView.swift:1411-1417 `positionColor` returns `.danger` for `.defense`, and :1007-1015 draws the red "NEED" capsule. Neither is a "needs attention" flag; the remaining work (a legend) is carried by line 3437.
- **The interview report's "Bust risk 50% → 40%" arrow line was removed, not restyled — it now shows the board's own risk badge.**
  - `TODO.md:3479` · design
  - bustRiskRow (InterviewSelectionView.swift:2189-2204) prints "BOARD RISK" plus ProspectRiskBadge(prospect.riskLevel) plus "updated with this meeting". The doc comment at :2171-2188 records the old percentage as a third, bogus risk model whose before-figure was a flat 35 for nearly every prospect and which no engine ever read.
- **Interview-report card borders now encode off-field concerns / exemplary character / top pick, so the border channel is no longer free for a grade tint.**
  - `TODO.md:3481` · design
  - InterviewSelectionView.swift:1968-1976 — borderColor is danger for off-field concerns, success for exemplary character, accentGold for the top pick, else surfaceBorder. Grade already carries its own colour on the card's letter (:2025-2027) and in the table's GRD column (:1880-1882), both via Color.forGrade. Tinting the border by grade would now collide with a stronger signal.
- **The interview report's "Complete Review" bar was deliberately demoted to a bordered dismiss rather than promoted to the primary CTA.**
  - `TODO.md:3483` · design
  - InterviewSelectionView.swift:1502-1527 — gold text on a 0.5-opacity gold stroke, with the comment at :1517-1522: "Bordered, not filled. This bar is a dismiss … and it was drawing a full-width gold primary directly above the hub's stage advance, which is the actual forward move and the one gold the action bar's own rule allows." The bar is also hidden entirely when dismissing goes nowhere (showsCompleteCTA, :1370).
- **The prospect card no longer prints a second "Scout Grade" beside the Overall band, so there is nothing left to disambiguate.**
  - `TODO.md:3500` · design
  - ProspectDetailView.swift:1425-1428 — the legacy Scout Grade row was deliberately deleted ("`syncProspectGrades` pins it to the band's midpoint… one exact answer the range exists to withhold"). Only Overall Grade / Potential / Personality remain.

### coaching · 14

- **Coaching styles are not filtered by Career Role, and that is no longer a defect: every style seeds a trade-market identity a GM-only career uses constantly.**
  - `TODO.md:2737` · bug
  - FranchiseIdentityDeclaration.declare(style:teamID:) writes TradeValueEngine.FranchiseIdentityRegistry (FranchiseIdentityDeclaration.swift:118-124), called from TeamSelectionView.swift:936. Separately worth knowing: CoachingStyle.bonusAttribute/bonusValue (CoachingStyle.swift:45-55) is read only by CoachingStaffView.swift:4567 — the "+10" itself is display-only for every role.
- **The Coaching Staff tab strip's unreadable inactive tabs — the whole yellow-underline bar was replaced by the shared capsule lens control.**
  - `TODO.md:3036` · design
  - CoachingStaffView.swift:1648-1668 renders DSLensTabs; DSListRow.swift:856-884 draws unselected capsules as Color.textSecondary (#94A3B8) on backgroundTertiary with a surfaceBorder stroke and the selected one as a filled accentBlue capsule — no underline and no dim-grey-on-dark text remain.
- **The head-coach card no longer has a gold chip beside a gold circle — the avatar is a real photograph and the HC chip is a rounded rect.**
  - `TODO.md:3039` · design
  - CoachingStaffView.swift:4495-4501 draws the "HC" chip as a RoundedRectangle(cornerRadius: 6); 4512-4521 draws the face via UserPortraitView, which is PersonFaceView with a photo and a thin ring (UserPortraitView.swift:139-167). Two different shapes, only one of which is a disc.
- **Candidate-row badges can no longer push the row to wrap — the hire board became a fixed-width horizontally scrolling table.**
  - `TODO.md:3058` · design
  - HireCoachView.swift:416-445 puts the whole table in a ScrollView(.horizontal) with .frame(minWidth: 820); the name cell is minWidth 160 with .lineLimit(1) (1000-1003), and every badge (TOP 3, potential, FREE AGENT, demand flame) shares one micro/bold style at 4×1 padding, radius 3 (920-970).
- **The salary control on the coach negotiation card is a stock SwiftUI Slider with the system's circular thumb, not a custom thin bar.**
  - `TODO.md:3084` · design
  - HireCoachView.swift:2659 — Slider(value: $proposedSalary, in: minSalary...maxSalary, step: 50).tint(Color.accentGold). No custom thumb view exists anywhere in the file; the gold seen in the screenshot is the tinted track. "Use a larger circular handle" would mean replacing a stock control with a hand-built one.
- **The post-hire green toast is gone — a hire now ends in a result sheet showing role, salary, pot remaining and the new man's key grade.**
  - `TODO.md:3099` · design
  - dynasty/dynasty/UI/Staff/CoachingStaffView.swift:4206-4285 — #49 wave 5b: "The old toast said `<name> hired as <role>!` and faded after three seconds"; the 0.6/0.4/0.8s timers were deleted with it
- **Position coaches render as a 2-column grid of compact cards where the key-attribute number sits on the badge row and is rating-coloured, not a large yellow number floating beside the name.**
  - `TODO.md:3101` · design
  - dynasty/dynasty/UI/Staff/CoachingStaffView.swift:2006-2025 (#50 `LazyVGrid` of `compactCoachCard`) and 4633-4648 (row 1 = role badge + `Color.forRating` value; row 2 = name)
- **The Coaching Staff Review is a system sheet with an opaque body — there is no app-controlled backdrop opacity left to raise.**
  - `TODO.md:3118` · design
  - CareerDashboardView.swift:583 presents it through `.sheet(item: $activeSheet)`; the sheet body paints `Color.backgroundPrimary` (:5565) and now sizes to `.page` on iPad (:646-653), so far less of the dashboard shows behind it than when the finding was written.
- **The 'ALL TASKS COMPLETED — READY TO ADVANCE' ribbon the modal covered was deleted; the tasks panel is now the single advance surface.**
  - `TODO.md:3122` · design
  - CareerDashboardView.swift:3455-3461 — "#105 wave 2: `advanceReadinessBanner` (Fix #64) is gone", removed because it repeated the panel's own "All tasks complete!" state three points below it.
- **Offense and defense schemes are independent in the model — the review now scores each side's coach fit and roster fit separately and recommends a better scheme.**
  - `TODO.md:3127` · design
  - CareerDashboardView.swift:6483-6565 `schemeFitAnalysis` (Coach Fit / Roster Fit bars, `bestAlternativeScheme`, and a "Consider switching" prompt); `calculateCoachFit` (:6627) and `calculateRosterFit` (:6645) split strictly by `PositionSide` with no cross-side compatibility term anywhere.
- **Advancing out of Coaching Changes costs no coach availability — the entire coach market runs once, on entry to the phase.**
  - `TODO.md:3129` · verification
  - WeekAdvancer.swift:3605-3661 — Black Monday (`CoachCarouselEngine.runBlackMonday`), `refillAIStaffVacancies` and `CoachMarketEngine.settleUnemployment` all fire inside the `case .coachingChanges` hook; nothing coach-market-related re-runs on the advance into `.reviewRoster`.
- **The staff review's confirm button is never actually disabled, so it needs no disabled-grey state — the padlock is a "lock in the staff" metaphor, and the incomplete case is already differentiated.**
  - `TODO.md:3141` · design
  - CareerDashboardView.swift:6789-6812 — one Button that always calls onConfirm(), with copy "Confirm & Advance to Review Roster" on accentGold when complete and "Lock in Anyway & Advance" on Color.warning when not. The toolbar copy behaves the same way ("Advance" / "Advance Anyway", :6605-6611). Worth noting the residual: a lock.fill on an always-enabled button still reads as disabled.
- **A poor scheme fit at the staff review is not a trap — the scheme can be changed on the spot and the advance is never blocked on it.**
  - `TODO.md:3147` · design
  - SchemeSelectionView is reachable from the Coaching Staff screen whenever a coordinator is in post (CoachingStaffView.swift:1534-1550) and prices the change before commit (SchemeSelectionView.swift:124-138). The review sheet points there itself ("Go to Staff > Schemes to set them", CareerDashboardView.swift:6772) and its confirm button reads "Lock in Anyway & Advance" rather than refusing (:6789-6812).
- **Scheme is not implicitly locked to the head coach — it is installed on the coordinator and can be swapped at any time.**
  - `TODO.md:3148` · design
  - SchemeSelectionView takes a coordinator, not the HC (CoachingStaffView.swift:1534-1550), and the staff review reads oc?.offensiveScheme / dc?.defensiveScheme (CareerDashboardView.swift:5516-5522) as the club's installed pair. The GM+HC branch in HireCoachView says so in copy: "Nothing is installed yet — hiring him puts \(scheme) in, and you can change it later in Schemes" (:2517-2520).

### inbox · 6

- **The per-sender inbox filter chips are gone; the three remaining lenses and the unread pill are counted from one predicate and cannot disagree.**
  - `TODO.md:3520` · bug
  - InboxFilter now has only .all/.actionRequired/.unread (InboxMessage.swift:145-149). filterLabel counts `!isRead && filter.matches` (InboxView.swift:126-129) and the toolbar pill counts `!isRead` (InboxView.swift:65-67), so the "All" lens and the pill are the same number by construction.
- **The inbox's two-tier tab-plus-pill strip is gone; a single lens row now carries a solid blue selected fill and a bold label.**
  - `TODO.md:3525` · design
  - InboxView.swift:130-143 is one DSLensTabs; DSListRow.swift:857-885 paints the selected capsule with a solid Color.accentBlue fill, bold text, a 1.5 pt border and a 44 pt minimum height, with a "FILTER · <selection>" ident above it (:826-843).
- **A sticky "N action required" bar is unnecessary: action-required messages sort to the top of the tray and have their own lens with a live count.**
  - `TODO.md:3536` · design
  - InboxView.swift:58-63 gives action-required messages sortRank 0 (unread) and 1 (read), ahead of everything else; :130-143 exposes the .actionRequired lens with its unread count folded into the label (:126-129).
- **Message detail has always had CTA buttons — the reviewer's screenshot was cut off before them**
  - `TODO.md:3545` · design
  - MessageDetailView.swift:62-66 renders `actionButton(destination:)` ("Open Scouting", gold when Action Required) and :145-190 renders the attachments as tappable navigation rows. Both shipped in 405902e (2026-03-17), long before this review; the combine letter carries "View Scouting Hub" and "Update Big Board" (InboxEngine.swift:262-265). The neighbouring TODO line records the screenshot cutting off mid-body.
- **The message sheet paints an opaque background, so no inbox row can read through it**
  - `TODO.md:3546` · design
  - MessageDetailView.swift:18-19 — the view roots on `ZStack { Color.backgroundPrimary.ignoresSafeArea() … }`, presented from a plain `.sheet(item: $selectedMessage)` (InboxView.swift:93-112). Nothing behind the sheet content is visible; what remains above the card is the system's own sheet inset, which is not an app-controlled scrim.
- **The combine letter's deep links already exist — "View Scouting Hub" and "Update Big Board" ship as attachment rows**
  - `TODO.md:3552` · feature
  - InboxEngine.swift:262-265 attaches `MessageAttachment(title: "View Scouting Hub", destination: .scouting)` and `(title: "Update Big Board", destination: .bigBoard)`; MessageDetailView.swift:154-190 renders each as a button that dismisses and calls `onNavigate?(attachment.destination)`. Present since 405902e (2026-03-17).

### draft · 5

- **"Select All Recommended" was moved out of the header beside the filter chip into the block that owns the interview ration, not into a sticky bottom bar**
  - `TODO.md:3458` · design
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:417-465 — the pill now sits under selectionProgress ("the ration and the controls that spend it, in one block"); the header keeps only the filter menu (:257-267) and the bottom bar is reserved for the Conduct commit (:806-818).
- **The "NFL teams typically interview 15–20 prospects" banner that contradicted the 60-slot ration was deliberately deleted**
  - `TODO.md:3465` · design
  - dynasty/dynasty/Engine/Scouting/DraftPrepProgress.swift:45-79 records why 60 stays (60 of ~330 combine invitees, the hardest cap in the pre-draft process, matching workoutSlots/top30Slots at the same scale); InterviewSelectionView.swift:313-320 now reads "Unused slots expire with this draft class" instead.
- **The interviews tab already names the bust-risk mechanism in its header; the per-row "hover" reinforcement it asked for is not a touch interaction**
  - `TODO.md:3467` · design
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:270-278 — the Reveals line ends "…which is what reduces bust risk", and the redundant gold banner was deleted (:504-509); every row still pins a ProspectRiskBadge (:731-733).
- **A capped "smart pick 15" auto-select was rejected; "Select All Recommended" is the shipped default and a cap would be strictly worse**
  - `TODO.md:3472` · design
  - dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:449-465 fills recommendedProspects up to the remaining slots in one tap; DraftPrepProgress.swift:60-78 records that a slot is the only cost and WeekAdvancer.startNewSeason zeroes interviewsUsed, so restraint "buys nothing and destroys forty reads".
- **A prospect's college grade and his rookie OVR are two calibrated quantities by design, not one rating pipeline running twice.**
  - `TODO.md:3635` · balance
  - DraftEngine.rookieScaleFactors (864-880) applies skill/physical/mental multipliers so "a rookie enters at roughly 70-75% of his eventual level"; the doc table at 899-906 gives measured entry OVRs of ~57-59 across all seven rounds against much higher college potentials, tied to DEVELOPMENT_NFL_REFERENCE.md §2. udfaEntryOverall (766-777) is documented as reproducing the converted player's overall exactly. What is left is disclosure on the draft board, not a duplicate pipeline.

### onboarding · 5

- **The Player Name helper line was deliberately enlarged for contrast in a later pass, and the input above it is already .title3 inside a bordered field, so it is plainly primary.**
  - `TODO.md:2705` · design
  - dynasty/dynasty/UI/Career/NewCareerView.swift:369-372 carries the comment "#99: larger explanation text with better contrast" over Text(...).font(.subheadline); the TextField at :343-347 is .font(.title3) on a filled, stroked background.
- **"Your Identity" still holds both coaching style and portrait, but the two concerns are now explicitly separated and the style genuinely IS the franchise identity.**
  - `TODO.md:2728` · design
  - FranchiseIdentityDeclaration.swift:20-33 rules that the coaching style is the identity declaration and the portrait is deliberately not a channel; NewCareerView.swift:717-720 prints that separation to the user on the same card.
- **The roadmap's phase date labels no longer conflict with anything — 'Coaching Changes' reads 'Feb', and the 'Thu 30. Apr' in the screenshot was the iPad's own status-bar clock, not game state.**
  - `TODO.md:2977` · design
  - IntroSequenceView.swift:901 `CalendarEntry(name: "Coaching Changes", …, duration: "Feb")`; no "Apr — May" string exists anywhere; the action-bar explainer at :1097-1099 states "Ten phases, February to January."
- **Each roadmap phase already names its calendar window (Feb … Sep-Jan), and a per-phase week count is not a real quantity — the week counter is frozen through the offseason.**
  - `TODO.md:2981` · design
  - IntroSequenceView.swift:896 `let duration: String`, values at :901-910, rendered at :982; CareerDashboardView.swift:578-580 records that "offseason phases advance on a frozen week counter".
- **The intro's closing screen already signals completion through the step counter, so a separate "onboarding complete" chip is redundant.**
  - `TODO.md:3002` · design
  - IntroSequenceView.swift:96-105 overlays "STEP \(currentStep + 1) OF \(totalSteps)" on every step after the press conference; totalSteps = 5 (:26) and ReadyToBeginStep is .tag(4), so this screen reads "STEP 5 OF 5". That counter was added after the audit.

### press conference · 5

- **Add a tier or percentage label to the answer cards' raw delta badges so +12 has a scale**
  - `TODO.md:2623` · design
  - The numeric pre-answer badges no longer exist. #161's fog rule replaced them with `hintRow(preview)` — directional markers only, "never numbers" (PressConferenceView.swift:1456-1463, and the header contract at :21-23). Post-commit the scale question is answered by `meterCells` (:858-910), which prints each delta beside where the meter it feeds actually lands ("72% → 76%", "every man +3").
- **Pulse the badge of the currently weakest metric across all four answer cards**
  - `TODO.md:2624` · design
  - The badges the fix targets were removed with #161's fog rule (PressConferenceView.swift:1456-1463), and pre-answer per-audience arithmetic is now deliberately forbidden. The underlying need is served instead: `baselineTiles` colour-grades all five meters before the first answer (:752-796) and `sessionFeedback` names the audience being lost by name — "Owner growing impatient", "Locker room is restless", "…but not the fans (-14)" (PressEngine.swift:1044-1090), rendered by `sessionVerdict` (:956-985).
- **The press-room reporter photograph no longer exists, so there is no busy image under the answer cards to scrim**
  - `TODO.md:2917` · design
  - PressConferenceView.swift:359-390 — "Token-only backdrop (#167). The press-room photograph carried a shield-form crest on the backdrop wall, so the asset is deleted." The backdrop is now a four-stop token gradient plus a radial podium key light and a top safe-area scrim.
- **The gold page ident the outlet badge competed with is gone from the question screen — it survives only on the podium plate**
  - `TODO.md:2920` · design
  - PressConferenceView.swift:514-535 — the questioning phase's pinned chrome is a `DSSlatBand` with a plain-text headline ("Question 3 of 4"); the gold `session.ident` at tracking 8 (:464-467) now renders only in `podiumPlate`, a separate phase.
- **Archetype spam is now taxed by a repetition ratchet rather than hidden by showing 3 of 4 answers**
  - `TODO.md:2925` · design
  - PressConferenceView.swift:1160-1237 — `toneLedgerStrip` ("WHAT THEY HAVE HEARD FROM YOU") counts each tone over the engine's own window and marks a taxed one in `alertOrange`; `PressConferenceEngine.repetitionScale` discounts the payoff, and `preview.isVanilla`/`vanillaChip` (:1523-1538) penalises the safe note. All four tones stay on the card by design.

### localization · 4

- **The ~900 remaining untranslated UI strings no longer exist as work — Finnish was removed and the game ships English-only**
  - `TODO.md:1512` · tech-debt
  - Commit ae2b995 (2026-07-30) "chore(l10n): drop Finnish localization — English only": "every 'fi' translation stripped (319 locale entries, 0 left)… The game ships in English from here on." Verified now: Localizable.xcstrings holds 2514 keys with `en` as the only language present, and project.pbxproj:91-94 has `knownRegions = (en, Base)`.
- **The English-only carve-out for procedural commentary is moot — the whole app is English-only**
  - `TODO.md:1513` · decision
  - Commit ae2b995 (2026-07-30) removed Finnish entirely; Localizable.xcstrings now carries zero `fi` localizations across 2514 keys and project.pbxproj:91-94 lists `knownRegions = (en, Base)`. There is no second locale for the LiveGameEngine feed, news generators or task titles to be excluded from.
- **The tutorial pages' English-only limitation is moot — Finnish was dropped before any model-type change was needed**
  - `TODO.md:1514` · decision
  - Commit ae2b995 (2026-07-30) stripped all Finnish. `TutorialPage` still declares `let title: String` / `subtitle` / `body` (MainMenuView.swift:541-549), which is now simply correct rather than a limitation, since there is no target locale.
- **The pending Finnish coach-HUD screenshot verification can never run — the Finnish build was removed**
  - `TODO.md:1515` · verification
  - Commit ae2b995 (2026-07-30) "chore(l10n): drop Finnish localization — English only", gated on `grep '"fi"' Localizable.xcstrings -> 0 hits`. Confirmed: 2514 keys, `en` only; project.pbxproj:91-94 `knownRegions = (en, Base)`. There is no fi build to screenshot.

### sim · 4

- **Instant-replay offers are no longer rare — any touchdown, any turnover, and any 20+ yard rush or completion arms the banner**
  - `TODO.md:1576` · note
  - CoachedGameView.swift:4413-4418 — `chunkFromScrimmage = play.yardsGained >= 20 && (play.outcome == .rush || play.outcome == .completion)`, and the offer arms on `pointsScored >= 6 || play.isTurnover || chunkFromScrimmage`. The chunk-gain rule supersedes the "extend to 15+ yd third-down conversions" idea; the ~1-per-50-plays observation predates it.
- **The wet-ball theory for that interception cluster is disproven — weather never enters the interception roll, and the INT weights have since been re-pivoted twice.**
  - `TODO.md:2254` · balance
  - PlaySimulator.swift:3288-3321 `interceptionChance` takes no `weather` parameter at all; its inputs were re-centred by B6 (dbMod pivot 50→70) and P0-2 (`edgeScale` compression). Weather touches completion (:1077-1079) and fumbles (:1817) only.
- **blitzFrequency stays a coached-game dial by design — the quick sim's per-snap defensive parity rule was kept and the limitation is now printed on the slider itself.**
  - `TODO.md:2579` · design
  - LiveGameEngine.swift:1864-1873 remains the only reader; GamePlanView.swift:1137-1145 `coachedOnlyReach` — "Applies to games you coach. A quick-simmed game does not read this dial." — records F-69 closing this the other way.
- **Fiery Competitor + Stats + "can generate media drama" is two traits shown three ways, and no engine applies both as penalties**
  - `TODO.md:3266` · verification
  - `isDramaticInMedia` is derived, not stored: PlayerPersonality.swift:7-9 returns `archetype == .dramaQueen || archetype == .fieryCompetitor`. Its only engine reader is EventEngine.swift:189-203 (event-pool weighting). `LockerRoomEngine.applyMoraleEffects`'s archetype switch (:287-309) has no `.fieryCompetitor` case — it falls to `default: break` — and the motivator term (:270-285) is a disjoint addend. No double application.

### backlog · 3

- **A wave-closing follow-up index pointing at queue items #112, #115 and #116; the two that can be checked in source have shipped.**
  - `TODO.md:4451` · note
  - #112: CareerDashboardView.swift:66-88 is now one .sheet(item:) over an ActiveSheet enum, with the three-.sheet(isPresented:) defect described in the doc comment. #115: ProspectDetailView.swift:1563-1567 — "A private workout files a .personalWorkout report rather than setting a flag of its own (see #115)".
- **A wave-closing follow-up index pointing at queue items #97 and #124-#127 plus review findings F14/F15; the isScouted cleanup it names has shipped.**
  - `TODO.md:4468` · note
  - #124: ProspectDetailView.swift:267 — isScouted is now derived as ProspectFog.read(prospect).source == .scouts, replacing the unsafe scoutedOverall != nil gate described at :2153; the same derivation is used at ClassDepthView.swift:802-810.
- **A backlog queue pointer (#152/#154/#155/#156/#137-#145) whose entire contents were closed by later commits recorded further down the same file.**
  - `TODO.md:4502` · note
  - TODO.md:4509-4513 records #137/#139/#142/#145 (3f07f63), #140/#141/#143/#152/#154/#156 (08df531), #138 + the rest of #154 (36b3c43), #155 + part of #97 (ce5ad57) and #144 (b48372d); TODO.md:3859 repeats the same closures. The #155 fix is visible in code: DraftEngine.swift:144-151 heads a block "The consensus anchor was inert (task #155)", and consensusSlot now resolves at pick granularity (:391-410, applied at :508).

### dashboard · 3

- **Promote the blocked-advance warning to a full-width amber banner above the tile grid**
  - `TODO.md:2852` · design
  - Superseded by #105 wave 2's one-what's-next-marker rule (TimelineTasksPanel.swift:504-511: the dashboard "used to carry three of them" and they were collapsed onto the rail), which forbids a second banner over the grid. The warning itself was promoted instead: `advanceSection` (:809-820) now prints `Label("Required: <task title>")` at footnote/heavy in `dangerText` with a triangle glyph plus "N more required tasks after it", pinned directly above a visibly disabled advance button.
- **The dashboard's owner/morale strip is now four non-interactive stat cards (Owner, Morale, Media, Legacy) with no progress bars and no selected/unselected state.**
  - `TODO.md:3378` · design
  - dynasty/dynasty/UI/Career/CareerDashboardView.swift:3593-3657 (satisfactionScoresRow → satisfactionCard: icon, value, label only) and the removal note at :3673-3676 ("ownerSatisfactionBar removed with #175").
- **A day-based combine countdown has nothing to count: the sim carries only season, week and phase, and the offseason advances only when the user presses Advance.**
  - `TODO.md:3385` · design
  - Domain/Models/Career.swift:21-23 (currentSeason / currentWeek / currentPhase, no day field). The rail already prints the phase's in-game month range (TimelineTasksPanel.swift:416, :1543-1548) and a task fraction (:241-245); a "14 days" figure would be a literal with no model behind it.

### faces · 3

- **Coach-portrait grid label truncation: the eight archetype names it cites no longer exist, and labels now auto-shrink instead of truncating.**
  - `TODO.md:2720` · design
  - UserPortraitView.swift:34-43 — the persona lists are 10 male + 10 female photo names ("The Chairman", "The Executive"…); none of "The Strategist / Old Soul / Motivator / Innovator / Professor / Trailblazer / Tactician / Commander" survive. Cell label at UserPortraitView.swift:311-315 is .lineLimit(1).minimumScaleFactor(0.7).
- **The "Cosmetic only — does not affect gameplay" portrait disclaimer was deliberately deleted as misleading, not resized.**
  - `TODO.md:2723` · design
  - NewCareerView.swift:709-722 replaces it with "The portrait is yours alone — your coaching style and your press answers are what the league reads", with a comment explaining the old claim was false (coaching style carries a real modifier; the press conference shapes free-agent interest). The replacement still renders at .caption/.textTertiary.
- **The portrait archetype names no longer contradict a "cosmetic only" claim — the claim was removed rather than the names.**
  - `TODO.md:2731` · design
  - NewCareerView.swift:709-722 (the disclaimer rewrite, with its reasoning) and FranchiseIdentityDeclaration.swift:29-33, which calls that sentence "a promise this file keeps rather than a disclaimer it contradicts".

### owner · 3

- **The owner meeting is now one uniform card stack, so the season-goals card is no longer an orphan between the trait list and the quote.**
  - `TODO.md:2940` · design
  - Wave 5a rebuilt both owner screens on the shared `OwnerCard` chrome — dynasty/dynasty/UI/News/OwnerBriefing.swift:311-372; the stacks are composed at UI/News/OwnerMeetingView.swift:70-110 and UI/Career/IntroSequenceView.swift:288-316
- **The owner's money row is labelled "Spending" and states outright that the coaching pot is separate from the cap; no owner-approval ceiling on player contracts exists to surface.**
  - `TODO.md:2944` · design
  - dynasty/dynasty/UI/News/OwnerBriefing.swift:167-186 — the "Free Agency Budget" mislabel was the bug and is fixed ("Coaching staff budget: $X (league avg …), separate from the cap"). `spendingWillingness` readers are only budget pots, facilities and archetype (BudgetEngine.swift:72-189, FacilityEngine.swift:255); no veto/approval gate exists in ContractEngine or the FA path
- **Owner patience is a severity dial, not a countdown — the dashboard Owner tile surfaces job security and goal progress instead of a Year X / N chip.**
  - `TODO.md:2945` · design
  - dynasty/dynasty/UI/News/OwnerBriefing.swift:660-680 — the countdown column was deliberately removed because `patience - yearsFired` could never move; dynasty/dynasty/UI/Career/CareerDashboardView.swift:3223-3300 (job-security meter, level label, primary goal + "X of Y met")

### balance · 2

- **#97: offseasonDevelop over-delivers ~+2.2 OVR per player per season, putting the app's 80+ share above the rig's at the same league pot**
  - `TODO.md:4489` · balance
  - The work is genuinely still open — MultiSeasonSmokeTest.swift:1395-1414 still prints the ANOMALY line with this exact diagnosis and names the next lever (`WeekAdvancer.processOffseason` inputs), and LeagueGenScenario.harness.swift:542 still records +2.0…+2.9. But this 2026-08-06 entry has been superseded: it is now tracked as F-71/#97 at TODO.md:3882 under "Ainoa aidosti auki jäävä työ", which carries the same diagnosis plus the current sequencing plan (own wave, measured against both rig and smoke, not on top of F-23). Close this copy in favour of that one.
- **The 2026-08-07 "still open" roll-up (#97 remainder, #157, #158, #105, user #5/#74) has been overtaken by later waves.**
  - `TODO.md:4513` · note
  - TODO.md:4526 and :4573 record #157 CLOSED on 2026-08-14 by measurement (upsidePremium proven exhausted as a lever, 0.45→0.30 breaks 6.1a); :4517 strikes #97 as done in Megarun 2. #158 is in code: StaffLedger.advanceBlocker is handed to the Season Guide sheet (CalendarSidebarView.swift:14-24, canAdvance at :54-55) and to the dashboard (CareerDashboardView.swift:254-256). Only the user-owned items survive (#105 direction call, #5 iPad review, #74 music), and they are tracked elsewhere.

### cap · 2

- **The $265M salary cap is one deliberate league constant, not a projected cap plus carryover — there is no carryover to break out.**
  - `TODO.md:2889` · design
  - ContractEngine.openingSalaryCap = 265_000 (Engine/Contract/ContractEngine.swift:24), documented as the single definition after task #87 found four competing caps shipping at once. Team.availableCap = salaryCap - currentCapUsage (Domain/Models/Team/Team.swift:154), so Used + Available equals the total exactly — the math is not off. Grep for carryover/rollover/capCarry across the tree returns nothing, and the league is fictional after #167, so real-NFL cap parity is not a target.
- **The roster-evaluation commit is a pinned action bar with an explainer, not a full-width gold button competing with the cap warnings in the scroll.**
  - `TODO.md:3336` · design
  - dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:212-236 (`confirmEvaluationBar` in a `safeAreaInset`, moved out of the scroll stack) and UI/Common/DSActionBar.swift:3-22 (§2.5/P5 — gold is reserved for the one commit surface, nav links are blue)

### contracts · 2

- **The Franchise Tag KPI strip the icon request was written against was replaced by a three-column next-league-year projection banner**
  - `TODO.md:3352` · design
  - FranchiseTagView.swift:179-240 — `capBanner` now prints Projected 2027 Cap / Committed to 2027 / Projected Space, over a small line reading "2026 cap space … — unchanged by tagging · N expiring · 1 tag available". "Available Cap Space / Expiring Contracts 10" no longer exists (#127).
- **Tag-and-trade cannot be a follow-up CTA — a franchise-tagged player is explicitly barred from every trade package**
  - `TODO.md:3364` · feature
  - TradeView.swift:480-490 `untradeableReason` and TradeNegotiationView.swift:466-471 both print "Franchise-tagged — can't be traded.", and their comments name the authority: "#141b: `TradeValueEngine.validationErrors` refuses a tagged man on either side of any package." Adding tag-and-trade means reversing that shipped rule, not adding a button.

### development · 2

- **The halved catch-up fractions' transient drag on existing saves has expired, and the potential-gated alternative it proposed is what shipped**
  - `TODO.md:401` · balance
  - Engine/PlayerDevelopment/PlayerDevelopmentEngine.swift:249-268 — the catch-up channel is now merit-gated on realizationFactor × primeWindowDamper under a deepInPrime condition, i.e. gated on realised potential rather than a flat fraction; the note's own "~4 offseasons" horizon is long past (dated 2026-07-28).
- **The claim that every drafted player's ceiling is ≥78 by construction is no longer true — the talent curve's tail was steepened**
  - `TODO.md:402` · balance
  - Engine/Scouting/DraftClassBuilder.swift:822-833 (bandProjection's hump) with the shipped band-mean-potential table at :888-893: R1 90.5 · R7 69.2 · UDFA 65.7, down from 95.2 / 74.0 / 70.4, and the upside draw is "centred at 0.55·runway … clipped at 0, so a real share of the board comes out with no headroom at all" (:866-870). The third option it listed — lowering the developmentCeiling slope — also shipped (PlayerDevelopmentEngine.swift:64-71).

### accessibility · 1

- **The accessibility-coverage snapshot naming only the coach HUD, Board and three menus is badly out of date**
  - `TODO.md:1516` · note
  - 95 of 165 files under dynasty/dynasty/UI now contain an explicit `accessibilityLabel`, including screens the note lists as relying on default semantics: FranchiseTagView.swift:544/610/634, PressConferenceView.swift:1335/1454/1509, MessageDetailView/InboxView.swift:291-292, TimelineTasksPanel.swift:880 (`accessibilityIdentifier("tasks.advance")`).

### calendar · 1

- **The offseason task list is not out of phase with the calendar — the "Thu 30. Apr" on screen was the device clock, not an in-game date.**
  - `TODO.md:2894` · bug
  - In game the roadmap dates Coaching Changes and Roster Evaluation to Feb, the Combine to Late Feb and Free Agency to Mar (IntroSequenceView.swift:900-903). SeasonPhaseGroup.subPhases orders phases chronologically — coachingChanges, reviewRoster, then combine, freeAgency, proDays, draft (Domain/Enums/SeasonPhase.swift:56-65) — and TaskGenerator.generateTasks is keyed on the phase, never on a month.

### coach mode · 1

- **The defensive call sheet is no longer ten cards in one grid — it is category-tabbed with rows sized to the panel.**
  - `TODO.md:3738` · design
  - DefensiveCall grew past 30 calls split across Coverage / Pressure / Man / Packages (Domain/Enums/PlayCall.swift:983-1023). CoachedGameView.defensePanel renders only the active category's calls behind a tab strip (:2575-2606), and CallCard.diagramHeight derives row height from the space actually available (:1481-1491). Pressure alone now holds 13 calls, so a fixed two-row constraint no longer describes the problem.

### coached game · 1

- **Skip Drive no longer shares screen space with the offensive category tabs — it sits in the defense panel's header row.**
  - `TODO.md:3698` · design
  - CoachedGameView.swift:2521-2545 puts the Skip Drive capsule at the trailing edge of the defense panel's title row (with .disabled(isAnimating)), the same band the offense panel fills with its coverage-read capsule (1560-1582). The offensive category tab row is three blocks lower, after the header, the OC bubble and the tendency strip (1608-1615).

### navigation · 1

- **Schedule and Standings are no longer on the top strip, and the Team tile now declares and honours its real destination (the league standings).**
  - `TODO.md:2885` · design
  - dynasty/dynasty/UI/Common/TopNavigationBar.swift:46-72 (seven bookmarks: Hub/Roster/Staff/Cap/Scouting/Draft/Trades; Schedule, Standings and News removed once the hub carried their routes); CareerDashboardView.swift:2286-2328 (teamTile is a NavigationLink to .standings with accessibilityHint "Opens the league standings").

### team selection · 1

- **Add a compare or shortlist affordance beside the team detail sheet's SELECT THIS TEAM button**
  - `TODO.md:2668` · feature
  - Superseded by the #117 compare mode on the list one level up: `compareModeOn` toggle in `filterSortBar` (TeamSelectionView.swift:549-575), up to four teams via `toggleCompare` (:397-404), and `CompareTeamsSheet` (:1834-1988). The detail sheet's `DSActionBar` (:1408-1414) still carries only the primary CTA, so the residual is a duplicate entry point, not a missing capability.

### tooling · 1

- **An unlisted runtime name pool is no longer invisible to the bundle gate — check F fails the build on any unclassified name-pool-shaped array**
  - `TODO.md:364` · verification
  - scan_bundle.py:27-31 documents check F as a coverage guard on E, implemented at :509-570 `scan_pool_coverage`: it walks the Swift sources via `_pool_candidates` and emits "[F] UNREGISTERED NAME POOL" unless the array is in SWIFT_NAME_POOLS, NON_PERSON_POOLS or PERSON_NAME_LITERALS, then holds literal pools to Levenshtein ≥3. The PASS verdict (:638-645) was updated to claim the wider coverage.
