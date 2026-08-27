# Live backlog — source-verified 2026-08-27

The 181 items that survived triage: checked against the current tree and still true.
Effort is the triage agent's estimate — S is an afternoon at most, L needs its own wave.
Line references point at the original entry in `TODO.md`; everything already done or gone
stale is in `docs/BACKLOG_ARCHIVE_2026-08-27.md`.

| type | count |
|---|---:|
| feature | 82 |
| design | 81 |
| bug | 11 |
| balance | 5 |
| verification | 1 |
| tech-debt | 1 |

## onboarding · 34  (M 6 · S 28)

- [ ] **Last-season record is inline on the team-selection row but the trajectory/situation badge is still detail-only**
  - design · effort S · `TODO.md:2645`
  - dynasty/dynasty/UI/Career/TeamSelectionView.swift:1002-1005 prints preview.lastSeasonRecord beside the team name; CompactTeamRow never renders preview.situation, and the two card layouts that do (MiniTeamCard :1160-1163, TeamGridCard :1217-1226) are dead code — :330 is the only row instantiation in the file.
- [ ] **The Career Role comparison table on New Career step 1 still has no headers over its two checkmark columns.**
  - design · effort S · `TODO.md:2703`
  - dynasty/dynasty/UI/Career/NewCareerView.swift:412-459 renders Picker → six roleComparisonRow calls → blurb with no header row; roleComparisonRow (:867-888) draws two bare 30 pt icon columns.
- [ ] **The Salary Cap Mode comparison table on New Career step 1 has no headers over its three checkmark columns, and the three right-aligned 30 pt columns do not line up with the full-width Simple/Realistic/Sandbox picker above them.**
  - design · effort S · `TODO.md:2704`
  - dynasty/dynasty/UI/Career/NewCareerView.swift:475-514 (Picker then six capFeatureRow calls, no header row); capFeatureRow at :891-915 draws three fixed 30 pt columns.
- [ ] **Neither the Career Role nor the Salary Cap control on New Career step 1 carries a "Recommended" badge, and the cap's "recommended for first-time players" footnote only appears after Simple is already selected — while the default is Realistic.**
  - design · effort S · `TODO.md:2712`
  - dynasty/dynasty/UI/Career/NewCareerView.swift:56-57 (defaults .gmAndHeadCoach / .realistic), :478-482 and :415-418 (bare Text tags in both pickers), :506-511 (footnote gated on capSelection == .simple). Contrast CoachingStyleCard, which does draw a Recommended capsule (:1289-1298).
- [ ] **New Career never warns that the Career Role choice is fixed for the life of the career.**
  - design · effort S · `TODO.md:2714`
  - Career.role is written only in the initialiser (dynasty/dynasty/Domain/Models/Career.swift:401-409); a repo-wide grep for `.role = ` finds only Coach assignments, never a Career. NewCareerView's roleSection (:412-459) carries no permanence note.
- [ ] **The career-intro Team Overview's Average Age still prints a bare "(Avg: 26.0)" that never says it is the league average.**
  - design · effort S · `TODO.md:2955`
  - IntroSequenceView.swift:598 hardcodes Text("(Avg: 26.0)"). The colour-coding half of this item IS done (:599-600 tints warning/success/tertiary against 27.5 and 25.0). The neighbouring Average Overall row was moved to ComparisonStatRow (:582), which spells out "vs league avg"; the age row was left behind.
- [ ] **"Coaching Staff 0 / N filled" on the career-intro Team Overview is still a row inside the roster card, with no dedicated action card or Hire CTA.**
  - design · effort S · `TODO.md:2959`
  - IntroSequenceView.swift:634-655 draws it as the last HStack of the ROSTER card, sharing that card's background. The whole TeamOverviewStep declares no Button or NavigationLink — the only control is the step's Continue bar at :861.
- [ ] **The career-intro Team Overview's cap bar is unlabelled and carries no cap-floor or dead-cap markers, so it is unclear it encodes cap used.**
  - design · effort M · `TODO.md:2960`
  - IntroSequenceView.swift:756-773 draws a bare two-layer RoundedRectangle from usedFraction with no caption, tick marks or legend; "Total Cap" and "Used" sit above as separate StatRows (:753-754) and the green "Available" figure sits below (:775-787).
- [ ] **The "League Avg Cap Space: ~$25.0M" caption on the career-intro Team Overview is still drawn at caption size in the dimmest ink.**
  - design · effort S · `TODO.md:2961`
  - IntroSequenceView.swift:789-791: .font(.caption) with .foregroundStyle(Color.textTertiary).
- [ ] **The stadium silhouette behind the intro roadmap is still a full-bleed background image at 0.1 opacity, sitting under the task card.**
  - design · effort S · `TODO.md:2978`
  - IntroSequenceView.swift:1041-1047 `Image("BgCoachStadium1") … .opacity(0.1)` — unchanged since commit 280defb (2026-03-18), which predates the finding.
- [ ] **Intro roadmap task numbers are 26pt gold circles on all three rows — no diameter bump and no active-task distinction.**
  - design · effort S · `TODO.md:2979`
  - IntroSequenceView.swift:1291-1295 `.frame(width: 26, height: 26).background(Circle().fill(Color.accentGold))`; `git log -S` shows the literal unchanged since the intro sequence first shipped (eaf7754).
- [ ] **Intro roadmap task 3 still bundles two distinct jobs into one row: 'Prepare for the Combine and Free Agency'.**
  - design · effort S · `TODO.md:2985`
  - IntroSequenceView.swift:1028 `TaskRow(number: 3, text: "Prepare for the Combine and Free Agency")`.
- [ ] **The roadmap still ends with 'Regular Season' as one more identical bullet — nothing frames it as the destination the offseason is building toward.**
  - design · effort S · `TODO.md:2989`
  - IntroSequenceView.swift:910 goes through the same row template as the nine offseason phases (:920-1005); the page subtitle at :1067 still says "Here's what lies ahead in your first offseason".
- [ ] **The "Your Journey Begins" screen's stadium backdrop is nearly invisible — the image runs at 30% opacity under a gradient that reaches 85% black.**
  - design · effort S · `TODO.md:2996`
  - IntroSequenceView.swift:1139-1160 — Image("BgStadiumDawn").opacity(0.3) plus a LinearGradient of backgroundPrimary 0.3/0.5/0.85. No field-line layer, no ambient lift.
- [ ] **The final intro screen still stacks two taglines — "Build Your Dynasty." over a motivational line — where one would do.**
  - design · effort S · `TODO.md:2997`
  - IntroSequenceView.swift:1190-1199: Text("Build Your Dynasty.") in accentGold with motivationalLine (:1127-1134) directly under it. Both are gold now, not gold-over-grey, but both are still there.
- [ ] **The football glyph on the final intro screen is 48 pt on an otherwise two-thirds-empty hero page and could carry more weight.**
  - design · effort S · `TODO.md:2998`
  - IntroSequenceView.swift:1177-1180 uses DSType.Size.hero = 48 (DSTokens.swift:147). The pulse half of this item already exists — glowAmount animates 0.3↔0.7 repeatForever (IntroSequenceView.swift:1195, 1230-1237) — so only the size is open.
- [ ] **The final intro screen names the club in plain text but applies none of its colours or mark, even though the app already has both.**
  - design · effort S · `TODO.md:2999`
  - IntroSequenceView.swift:1186-1189 prints "with the \(team.fullName)" in textSecondary; every accent on the screen is Color.accentGold. TeamColors.color(for:) and TeamLogoPlaceholder exist at TeamSelectionView.swift:1248-1266 and are never called here. (Teams are fictional now — "Green Bay Timberjacks", LeagueTeamData.swift:159 — so the original "Packers green/gold" wording is obsolete.)
- [ ] **"Enter the Front Office" is pinned to the bottom bar with the mid-screen left empty — no hype stat fills the gap.**
  - design · effort S · `TODO.md:3000`
  - IntroSequenceView.swift:1207-1230 puts the CTA in a safeAreaInset(edge: .bottom); the body is Spacer/VStack/Spacer (:1163-1204) with only the title block centred. Nothing counts roster size, staff openings or weeks to kickoff.
- [ ] **The gold glow behind the intro football glyph is a 20 pt drop shadow that never reads as a deliberate effect — commit or drop it.**
  - design · effort S · `TODO.md:3001`
  - IntroSequenceView.swift:1180 — .shadow(color: accentGold.opacity(glowAmount), radius: 20, y: 0), glowAmount animating 0.3↔0.7. It is a shadow behind a 48 pt glyph, not a radial burst; unchanged since the original commit eaf7754.
- [ ] **Finishing onboarding produces no celebration — the closing screen only fades its elements in.**
  - design · effort S · `TODO.md:3007`
  - IntroSequenceView.swift:1226-1240 runAnimations(): three easeOut opacity/move transitions plus the glow pulse. No first-run-only moment, no achievement, and nothing distinguishes this from the four Continue screens before it.
- [ ] **The intro's closing CTA gives no hint of the first concrete action waiting on the other side.**
  - design · effort S · `TODO.md:3012`
  - IntroSequenceView.swift:1207-1230 renders the button alone with no caption. The answer is already determined one function away — completeIntro() sets currentPhase = .coachingChanges (:174) and TaskGenerator produces the hire-staff task for that phase.
- [ ] **Team-selection rows show owner patience but still bury market size in the detail sheet, and franchise prestige does not exist at all**
  - feature · effort S · `TODO.md:2644`
  - dynasty/dynasty/UI/Career/TeamSelectionView.swift:1074-1085 puts only the patience glyph + years on the row; marketDescription is detail-only at :1553-1563; Data/Import/LeagueTeamData.swift:14-29 (TeamPreview) has no prestige field to surface.
- [ ] **Team selection surfaces challenge level but has no notion of a player's preferred playstyle to match a club to**
  - feature · effort M · `TODO.md:2650`
  - Challenge is covered (difficulty stars + difficultyLabel + rationale, dynasty/dynasty/UI/Career/TeamSelectionView.swift:1482-1519). Nothing records a playstyle: Data/Import/LeagueTeamData.swift:14-29 has no scheme/identity field, and the career-start flow (startCareer :709) never asks.
- [ ] **Team selection has no "recommended for first-time players" / "recommended for veterans" tag**
  - feature · effort S · `TODO.md:2651`
  - No occurrence of first-time / recommended / beginner anywhere in dynasty/dynasty/UI/Career/TeamSelectionView.swift; the only guidance is the raw difficulty star count on CompactTeamRow (:1041-1052).
- [ ] **The career-intro Team Overview's Key Players list is three untagged, untappable names with no role tag (QB1 / Top Cap / Expiring).**
  - feature · effort M · `TODO.md:2964`
  - IntroSequenceView.swift:379-381 — topPlayers is simply the top 3 by overall. Rendered as plain Text rows at :611-628 (name, position, OVR only); the step contains no Button or NavigationLink, so nothing on it is tappable.
- [ ] **"Expiring Contracts: N players" on the career-intro Team Overview is dead text with no drill-down to who is expiring.**
  - feature · effort S · `TODO.md:2965`
  - IntroSequenceView.swift:604-608 is a plain StatRow; TeamOverviewStep declares no navigation affordances at all.
- [ ] **The career-intro Team Overview never states a meta-strategy verdict (contend / retool / rebuild) for the roster it describes.**
  - feature · effort M · `TODO.md:2967`
  - No stance reference anywhere in IntroSequenceView.swift. TradeValueEngine.TeamStance (Engine/Contract/TradeValueEngine.swift:1244-1260, resolved at :1336-1387) already derives contend/retool/rebuild from record plus core talent and is the obvious source to quote.
- [ ] **The career-intro Team Overview's salary-cap section has no at-a-glance Cap Health verdict (Healthy / Tight / Crisis).**
  - feature · effort S · `TODO.md:2968`
  - IntroSequenceView.swift:748-793 is Total Cap / Used / bar / Available / league-avg caption — all figures, no verdict. Grep for "Cap Health" / "capHealth" across the tree returns nothing.
- [ ] **The career-intro Team Overview has no "First Moves Recommended" panel turning its own data into three concrete next steps.**
  - feature · effort M · `TODO.md:2971`
  - IntroSequenceView.swift:530-870 draws ROSTER, POSITION GROUP STRENGTHS, SALARY CAP and DRAFT PICKS and then the Continue bar (:861); nothing on the step recommends an action. Grep for "First Moves" / "Recommended" across the tree returns nothing for this screen.
- [ ] **No roadmap phase quotes an expected outcome (signings, money committed, picks made) so a new player can tell what 'good' looks like.**
  - feature · effort S · `TODO.md:2987`
  - IntroSequenceView.swift:891-897 — `CalendarEntry` carries only name/description/duration/isMandatory; nothing numeric is stored or rendered (:920-1005).
- [ ] **The roadmap never explains why the phases run in this order — that staff hires shape free-agency targeting and draft scheme fit.**
  - feature · effort S · `TODO.md:2992`
  - IntroSequenceView.swift:1095-1100 — the only explainer reads "Ten phases, February to January. The **required** ones you work through; the **optional** ones you can skip."
- [ ] **The final intro screen never stamps the dynasty's starting point on the timeline.**
  - feature · effort S · `TODO.md:3005`
  - IntroSequenceView.swift:1163-1204 shows only title, team name and taglines. Note the copy has to be the offseason, not "Week 1": completeIntro() sets currentPhase = .coachingChanges and currentWeek = 0 (:172-181).
- [ ] **The last intro screen shows no recap of the choices just made — coach name, owner expectations and roster shape are all left behind on earlier steps.**
  - feature · effort M · `TODO.md:3006`
  - ReadyToBeginStep (IntroSequenceView.swift:1116-1240) receives career, team and teamOverall but renders only the team's full name and a tagline graded off RosterStrength.starterAverage. The owner goals it could quote are already in scope — seasonGoals is loaded at :185-200 and written in completeIntro at :176-178.
- [ ] **No first-run "rookie GM mistake" tip is offered anywhere in the intro sequence.**
  - feature · effort S · `TODO.md:3008`
  - ReadyToBeginStep (IntroSequenceView.swift:1116-1240) has no tip pool and no first-run flag; career.hasCompletedIntro (Career.swift:37) is written at :173 but read by nothing outside MultiSeasonSmokeTest, so there is not even a first-run signal to hang one on.

## roster · 30  (M 5 · S 25)

- [ ] **The red "Biggest Need" chip always fires on the Specialists header, because the Special Teams side has exactly one group to be weakest of.**
  - bug · effort S · `TODO.md:3197`
  - RosterView.swift:310-333 — `weakestGroupName` loops over `activeGroups`, and `activeGroups` for `.specialTeams` is the single-element `Self.specialTeamsGroups`. The header takes `isWeakest: group.name == weakestGroupName` (:702) and draws `stateChip("Biggest Need", tint: .danger)` unconditionally (:1777-1779).
- [ ] **Roster summary-bar labels can shrink below the app's own 10pt legibility floor; the dividers the finding asked for already exist.**
  - design · effort S · `TODO.md:3156`
  - RosterSummaryBar.swift:378-392 — 11pt `DSType.Size.caption` labels with `.minimumScaleFactor(0.65)` (≈7pt against the 10pt `DSType.Size.micro` floor documented at DSTokens.swift:116-129); dividers at :396-400 are already used between all six cells.
- [ ] **In the Roster Overview lens, contract years and health are each drawn twice per row — once in the fixed EXT/HLTH state slots, once again as a trailing column.**
  - design · effort S · `TODO.md:3159`
  - PlayerRowView.swift:190 `DSStateSlotRow(slots: rosterSlots)` renders `extensionSlot` (:260-276) and `healthSlot` (:279-293); `overviewColumns` then draws `contractYearsLabel` (:374) and `healthIndicator` (:382) for the same two facts.
- [ ] **The roster's morale column is still an unlabelled smiley glyph whose column header is that same glyph, so nothing on screen says what it measures.**
  - design · effort S · `TODO.md:3161`
  - PlayerRowView.swift:789-794 `moraleIndicator` draws `face.smiling.fill`/`face.dashed` (:972-979); RosterView.swift:909 heads it with `headerIcon("face.smiling", width: 24)`. Health is already unambiguous (cross/checkmark + weeks, PlayerRowView.swift:796-813) and there is no heart icon anywhere.
- [ ] **The roster's Special Teams side renders one two-man Specialists group and leaves the rest of the screen empty.**
  - design · effort M · `TODO.md:3196`
  - RosterView.swift:249-251 — `specialTeamsGroups` is a single `PositionGroup(name: "Specialists", positions: [.K, .P])`; Position.swift:75-77 puts only K and P on `.specialTeams`, so `filteredPlayers` (:266-269) can never return more than the kicker and punter. `listContent` (:650-714) renders that one section and nothing else.
- [ ] **All seven roster analysis lenses render on the Special Teams side even where they say nothing about a kicker or punter.**
  - design · effort S · `TODO.md:3198`
  - RosterView.swift:600-604 — `analysisLensTabs` passes `RosterAnalysisMode.allCases` with no filter on `selectedSide`; the seven modes are enumerated at PlayerRowView.swift:1075-1083. `installedScheme(for:)` already special-cases specialists to `nil` (RosterView.swift:610-616), so the lens strip is the one place the side is ignored.
- [ ] **The roster list does not adapt when a side holds only two rows — the Special Teams tab leaves most of the screen as empty background.**
  - design · effort S · `TODO.md:3199`
  - RosterView.swift:650-717 `listContent` is one `.insetGrouped` List with fixed `.listSectionSpacing(12)` and `.contentMargins(.top, 0)`; the top-inset fix documented at :718-721 addressed the header gap only. Nothing measures row count or fills the trailing space.
- [ ] **The "Top 5 QB · $39.2M–$48.9M" market comparables strip on the Contract card is still the faintest text on it**
  - design · effort S · `TODO.md:3217`
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:1070-1081 — it moved up out of the card's tail but still renders at DSType.Size.caption in Color.textTertiary with lineLimit(1); nothing about its weight, size or colour was promoted.
- [ ] **The "If X leaves: Y starts at QB — 70 OVR (-14)" replacement preview still formats its OVR delta as plain text, not a red badge**
  - design · effort S · `TODO.md:3221`
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:1828-1846 builds one string with an em-dash and a parenthesised delta; it renders at :1786-1794 in a single Color.textTertiaryReadable line, so the delta gets no tone or badge of its own.
- [ ] **The "Change Position" action is offered unconditionally, even for a player with no viable conversion**
  - design · effort S · `TODO.md:3229`
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:1953 — the ghost slot is a bare .init(title: "Change Position", handler:) that never consults VersatilityEngine.viablePositions; the emptiness is only discovered inside the sheet at :2360-2367 ("No viable alternate positions…").
- [ ] **The per-position versatility explanation ("Athletic QB can line up as WR in trick plays. Max ceiling: 40%") is still inline footnote-size tertiary text.**
  - design · effort S · `TODO.md:3238`
  - PlayerDetailView.swift:2618-2621 renders versatilityExplanation(from:to:rating:) at DSType.Size.footnote in Color.textTertiary; the string itself is built at :3326-3348. The card's DSDetailCard(explainer:) tooltip slot (:2515-2519) carries only the section-level sentence, not these per-row ones.
- [ ] **Schemes at 0% familiarity still occupy a full row each; they sink to the bottom of the list but are never collapsed into a footnote.**
  - design · effort S · `TODO.md:3240`
  - PlayerDetailView.swift:2638-2652 builds allSchemes from every case on the player's side of the ball (comment "#181: Show ALL relevant schemes, not just learned ones"), sorted descending; :2653-2681 renders one full row per scheme regardless of value, greying the label and the percentage when familiarity is 0.
- [ ] **The Personality block on Player Detail is a plain design-system card — no portrait or feature-card treatment**
  - design · effort S · `TODO.md:3258`
  - PlayerDetailView.swift:2480-2511 `personalityCard` — a `DSDetailCard` with an explainer, two `DSDetailRow`/`DSDetailNote` pairs and up to two Labels. `PersonFaceView` is used on this screen only in the hero (:696), so the portrait flair the item asks for has an available component but is not applied here.
- [ ] **Roster Evaluation's position-group table still packs starter and depth grades into one 80pt "Strt / Depth" cell rather than two separately headed columns**
  - design · effort S · `TODO.md:3309`
  - RosterEvaluationView.swift:665 `sortableHeader("Strt / Depth", column: .depth, width: 80)`; the row draws S:/D: + slash inside one 80pt HStack at :737-753. Partly mitigated since the report by the inline "S:"/"D:" prefixes and the legend line at :695, but the column was never split.
- [ ] **Roster Evaluation's nine position-group rows have no alternating row background to scan against**
  - design · effort S · `TODO.md:3312`
  - RosterEvaluationView.swift:835 — the only row background is a red 5% tint on "Starter needed" rows; rows are separated by Dividers only. The combine table did get zebra striping (CombineResultsView.swift:412-416), so the pattern exists in the app.
- [ ] **The Cap $ column on Roster Evaluation is centre-aligned, so $5.9M and $26.6M do not share a decimal column**
  - design · effort S · `TODO.md:3313`
  - RosterEvaluationView.swift:777-780 — `.monospacedDigit()` is already applied (tabular nums done) but the cell is `.frame(width: 72, alignment: .center)`, as is its header at :669. Both this column and the Cap Outlook section use the same `formatMillions` (:2674), so only alignment is at issue.
- [ ] **Staff status pills on Roster Evaluation size to their text, so "Aging — plan ahead" shrinks to ~7pt beside a compact "Solid"**
  - design · effort S · `TODO.md:3314`
  - RosterEvaluationView.swift:899-909 `needBadge` has `.lineLimit(1).minimumScaleFactor(0.7)` but no max width; only the badge GROUP is framed (`minWidth: 60`, :807). Overlap with the "You" column is impossible (they are siblings in an HStack), but the shrink-to-fit makes the longest label illegible.
- [ ] **No roster lens surfaces fatigue or training load, although both are modelled per player.**
  - feature · effort S · `TODO.md:3168`
  - `Player.fatigue` (Player.swift:115) and `Player.workloadStatus` (:503) are rendered only by the separate `WorkloadDashboard` (CareerShellView.swift:2243); the Roster screen's Physical lens shows SPD/STR/STA/DUR/Health only (RosterView.swift:942-950).
- [ ] **The roster summary bar's cap figure is not a control and never says whether dead money is inside it — although it is.**
  - feature · effort S · `TODO.md:3169`
  - RosterSummaryBar.swift:308-346 draws the cap cell as plain text plus a bar with no tap target; the value is `Team.currentCapUsage`, documented at :9-19 as the ledger that "carries dead money"; the breakdown already exists on `CapOverviewView` (deadMoneyCard, CapOverviewView.swift:19-39) with no route from here.
- [ ] **The Roster screen has no generated 'top 3 decisions' panel — the only priorities on it are ones the user types himself.**
  - feature · effort S · `TODO.md:3172`
  - RosterView.swift:96-116 and :204-231 — `rosterOwnAssessments` / `rosterPriorities` are manual per-group notes persisted to JSON; no recommendation source is read anywhere under UI/Roster.
- [ ] **Player detail shows only a league-wide position rank ("Top 11% QB"); it never shows the rank within his own team beside it**
  - feature · effort S · `TODO.md:3225`
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:3208-3224 — leagueRanking sorts allLeaguePlayers at the position and returns one string; nothing filters by teamID to produce a companion team rank.
- [ ] **The trade decision-support loop on player detail shows draft capital and roster impact but never the cap relief a trade would bring**
  - feature · effort S · `TODO.md:3232`
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:1681-1826 — the card carries tradeValuePoints/bucket (draft capital) and replacementPlayerInfo (roster impact) but no money line; CapManagementEngine.tradeCapSplit already exists (Engine/Contract/TradeEngine.swift:362) and is simply never called here.
- [ ] **Position versatility is surfaced on the depth chart but never in the weekly game plan — there is no gadget or decoy usage to wire it to.**
  - feature · effort M · `TODO.md:3245`
  - familiarity(at:) readers are RosterView.swift:1130/1295-1296/1432/1480/1490 and FormationView.swift:321-322/648/847-848/956/998 (out-of-position candidates, familiarity-scaled effective OVR). GamePlanView.swift (1268 lines) contains no reference to familiarity, versatility or trainingPosition, and a repo-wide grep for trickPlay/gadget returns nothing.
- [ ] **No career games-missed figure exists anywhere — the Injury History card shows only per-injury summaries and the durability rating.**
  - feature · effort S · `TODO.md:3247`
  - InjuryRecord carries weeksOut (InjuryRecord.swift:12) and a per-record summary (:20-27), but a repo-wide grep for gamesMissed/weeksMissed returns nothing and nothing aggregates injuryHistory. The no-history branch prints durability alone (PlayerDetailView.swift:2300-2325).
- [ ] **The "Can generate media drama" warning on Player Detail is static text with no way to see which events it feeds**
  - feature · effort S · `TODO.md:3259`
  - PlayerDetailView.swift:2505-2509 — a bare `Label`, no gesture or popover. The triggering events are knowable: `EventEngine.swift:189-203` weights `.socialMediaIncident` (+3 per drama player), `.podcastControversy` (+2 each) and a +2 negative bias off `personality.isDramaticInMedia`.
- [ ] **Player Detail has no synthesised "manager notes" panel tying contract, scheme fit and trade value into one recommendation**
  - feature · effort M · `TODO.md:3269`
  - The page's card list (PlayerDetailView.swift:551-583) ends with versatilityCard; nothing named notes/manager notes exists anywhere in the app (only ScoutingHubView's unrelated `.scoutNotes` tab). The inputs are all on the screen already — `schemeMismatchInfo`, `estimatedMarketValue`, `tradeValueCard`, `comparablesText` — so this is a synthesis card, not new data.
- [ ] **Confirm Evaluation can be committed with zero position-group priorities set, with no block and no warning**
  - feature · effort S · `TODO.md:3318`
  - RosterEvaluationView.swift:222-236 `confirmEvaluationBar` — `isEnabled: !rosterEvaluationConfirmed` only; the explainer text never mentions priorities. `prioritiesSetCount` (:451) is read only by the counter and the auto-set overwrite dialog. Auto-Set Priorities (#108) makes filling them one tap, but nothing requires it.
- [ ] **Position-group rows show Avg OVR / Avg Age / Cap $ with no league-average comparison to say whether a 67 is weak**
  - feature · effort M · `TODO.md:3320`
  - No league-average term anywhere in RosterEvaluationView.swift (no `leagueAvg`/`leagueAverage` symbol); `GroupRowData` (:341-360) carries only own-roster aggregates. The data is already in hand — `allPlayers`/`allTeams` are loaded by `loadData` — so this is computation plus a cell, not new plumbing.
- [ ] **Key Decisions is ordered by tag but offers no filter chips or section headings across its 15 rows**
  - feature · effort S · `TODO.md:3322`
  - RosterEvaluationView.swift:2249-2258 — sorted retirement → expiring → overpaid → underpaid → aging, `prefix(15)`. So the "no sort" half is false and the "similar copy" half is fixed (`expiringRecommendation`, :2270-2300, now has five distinct branches), but there is no filter or group header in `keyDecisionsSection` (:926-965).
- [ ] **Expanded Key Decision rows give financials and FA replacements but no inline Negotiate / Let walk / Tag action**
  - feature · effort M · `TODO.md:3326`
  - RosterEvaluationView.swift:1032-1204 `keyDecisionFinancialDetails` — market value, re-sign/cut/restructure lines, FA previews, and one `NavigationLink` to PlayerDetailView (:1180-1203). Every action is at least two taps away in another screen; the negotiation and franchise-tag flows exist (`ContractNegotiationView`, `ContractEngine.franchiseTagValue`) and would need wiring.

## coaching · 28  (L 1 · M 7 · S 20)

- [ ] **"Projected wins +0.1 / season" on the hire screen comes from an ad-hoc display heuristic that is not derived from the coaching coefficients the sim actually applies.**
  - balance · effort M · `TODO.md:3087`
  - HireCoachView.swift:1720-1732 computes wins = clamp((ovr*0.5 + mot*0.25 + disc*0.25 - 65) * 0.04, -2, 2) — a ±2-win rail invented in the view. What the sim really does lives in CoachingModifiers.swift (coordCompletionSlope, planCompletionSlope, disciplineSlope, moraleBump), and the R40 harness measured it separately (TODO.md:780, 797: grade 88 vs 55 staffs produce a 92% win share, league-average staffs cancel). Missing: derive the label from those coefficients, or from a harness sweep, so the number is traceable.
- [ ] **The "Recommended" coaching-style badge is hardcoded to The Tactician and never adapts to the Career Role chosen one step earlier.**
  - design · effort S · `TODO.md:2733`
  - NewCareerView.swift:670 — isRecommended: style == .tactician. Neither coachingStyleSection (:663-680) nor CoachingStyleCard (:1264-1348) reads selectedRole, and the footnote rationale at :1316-1322 is role-agnostic ("Recommended for first-time players").
- [ ] **The Coordinators and Position Coaches section headers print a bare "0/3" / "0/8" with no label saying it means filled-of-total.**
  - design · effort S · `TODO.md:3041`
  - CoachingStaffView.swift:1990-1993 and 2034-2037 render Text("\(filledCount)/3") and Text("\(filledCount)/8") with colour coding only — no "filled" word, no progress bar, and no accessibility label. Missing: a one-word suffix or a progress bar in those two DisclosureGroup labels.
- [ ] **Position-coach mini-cards float vertically in their grid row because the card never pins its content to the top.**
  - design · effort S · `TODO.md:3042`
  - CoachingStaffView.swift:4633 (compactCoachCard) and 4703 (compactVacantCard) end in .padding(8).background(...) with no .frame(maxHeight: .infinity, alignment: .top), so inside the LazyVGrid at 2003-2010 a short card's text centres against the tallest card in the row. Missing: top alignment on both card bodies.
- [ ] **The staff hire sheet's dismissal is still a small text "Close" button in the top-left rather than an X icon.**
  - design · effort S · `TODO.md:3057`
  - CoachingStaffView.swift:1436-1438 — ToolbarItem(placement: .cancellationAction) { Button("Close") { activeHireSheet = nil } }, tinted accentGold. Missing: an xmark.circle.fill icon button (the pattern the sheet's own inline dismissals already use, e.g. HireCoachView.swift:683).
- [ ] **The hire board's "N candidates" pool size is plain grey caption text tucked at the end of the budget row.**
  - design · effort S · `TODO.md:3063`
  - HireCoachView.swift:664-666 — Text("\(filteredCandidates.count) candidates").font(.caption).foregroundStyle(Color.textSecondary), last child of the budgetHeader HStack after the Affordable toggle. Missing: promoting it to a pill in the sheet header beside the "Hire <role>" title (navigationTitle set at 453).
- [ ] **The coach candidate profile header packs potential, scheme tags, fit and demand badges into one non-wrapping row, so long chips compress and truncate.**
  - design · effort S · `TODO.md:3078`
  - HireCoachView.swift:2054-2110 is a single HStack (OVR box 68 pt, potential chip, up to two schemeTag pills, fit badge, demandBadge, Spacer, salary) with no fixedSize, no wrapping layout and no lineLimit. demandBadge can read "High demand (3 rival teams)" (:2098-2110). schemeTag itself (:2991-3002) has no fixed pill width.
- [ ] **Coach attribute rows still print a tier word and a number side by side instead of a single colour-coded bar.**
  - design · effort S · `TODO.md:3080`
  - HireCoachView.swift:2325-2371 — attributeCell renders name + tier pill ("Elite"/"Great"/"Good"/"Avg"/"Below", attributeTier at :2364-2371) + the numeral in Color.forRating, over a rating-tinted background. The layout moved to two columns with full names (#158, :2303) but the word-plus-number pairing the item objects to is unchanged.
- [ ] **A coach candidate's personality is printed twice on his profile — once in the header identity line and again as the first row of the Coaching Style card.**
  - design · effort S · `TODO.md:3082`
  - HireCoachView.swift:2043-2045 (header, accentBlue) and :2588-2596 (coachingStyleCard) both render candidate.personality.displayName. Only the second is followed by the effect lines, so the header instance is the redundant one.
- [ ] **Coach background blurbs repeat across a candidate board — the opening sentence has only four variants per experience tier.**
  - design · effort S · `TODO.md:3089`
  - CoachingEngine.generateBackground (:1055-1370) builds exactly three sentences (capped at :1368): an experience opener drawn from 4 options within one of 4 tiers (:1060-1128), an attribute line drawn from 3 options for the coach's top attribute (:1144-1260), and a personality line of 2-3 options. Across a 26-candidate board, duplicate openers are guaranteed by pigeonhole. Judging the prose quality itself still needs a human read.
- [ ] **A filled medical staff card shows only the DOC / PHY / TRN chip and the person's name — the role is never spelled out.**
  - design · effort S · `TODO.md:3103`
  - Missing: the full role name on filled cards. dynasty/dynasty/UI/Staff/CoachingStaffView.swift:4633-4640 (`compactCoachCard` prints `role.abbreviation` only) vs 4769-4772, where the vacant card does print `role.displayName` under the same chip
- [ ] **In the staff review only the OC and DC rows carry a scheme chip, and the per-coach scheme-fit indicator that would fill the same slot on every row is dead code.**
  - design · effort S · `TODO.md:3120`
  - CareerDashboardView.swift:5743-5752 computes `schemeName` for `.offensiveCoordinator`/`.defensiveCoordinator` only; `schemeFitIndicator(for:)` (:6442) and `schemeMismatchWarning(for:)` (:6458) — which cover all eleven offensive/defensive roles — have zero call sites.
- [ ] **The staff review's advance wears a padlock and reads 'Lock in Anyway & Advance', but never says hiring stays open in later phases — which it does.**
  - design · effort S · `TODO.md:3128`
  - CareerDashboardView.swift:6789-6810 draws the padlock and the lock-in copy; hiring is not phase-gated — `CoachingStaffView` gates only its two review tasks on `.coachingChanges` (CoachingStaffView.swift:1751) and its own confirm copy already says "You can still hire and replace anybody" (:1727).
- [ ] **Coach Fit and Roster Fit bars in the staff review carry no threshold tick, so a mid-yellow bar gives no sense of where "good" starts.**
  - design · effort S · `TODO.md:3137`
  - CareerDashboardView.swift:6572-6599 — schemeFitBar draws only a track and a fill coloured by fitBarColor (Color.forRating(percent, scale: .percent)); no marker. The same sheet already has the pattern to copy: benchmarkBar (:6048-6070) draws a centre tick at the seat's league average on every staff row, with a legend at :6013-6029.
- [ ] **The staff review's chemistry badge reports a grade and stops — no hint of what hire or change would improve it.**
  - design · effort S · `TODO.md:3140`
  - CareerDashboardView.swift:6682-6703 — staffChemistryRow renders the grade word twice (inline bold and a coloured capsule) and nothing else. The pairing tables that would supply the advice are right below in calculateStaffChemistry (:6706-6734: compatiblePairs / clashingPairs over PersonalityArchetype).
- [ ] **All three coordinator vacancies are stamped "High Priority" from a static role table, so the priority signal carries no information.**
  - feature · effort M · `TODO.md:3045`
  - CoachingStaffView.swift:464-475 — hiringPriority(for:) returns .high for offensiveCoordinator, defensiveCoordinator and specialTeamsCoordinator unconditionally; it reads no roster, scheme or budget state. Missing: a gap-analysis input (installed scheme, weakest unit, roster grades) to rank the three against each other.
- [ ] **Coach hiring impact is still quoted only as an abstract percentage — "Up to +12% offensive efficiency" is never translated into a football outcome.**
  - feature · effort M · `TODO.md:3046`
  - CoachingStaffView.swift:1255-1273 (hiringImpactDescription) is a hardcoded per-role percentage table. The related half of this item did ship — the player-as-HC line now reads "+N Play-Calling rating" (4560-4566) — but nothing converts efficiency into wins. Missing: a wins/points estimate derived from the sim.
- [ ] **The TOP 3 badge on a coaching candidate never says why he is top 3 — the reason is stated once in a collapsible legend, not on the row.**
  - feature · effort S · `TODO.md:3066`
  - HireCoachView.swift:296-305 — cachedTop3IDs is purely the top three by coachOverall; candidateRank (1348-1352) ranks by OVR too. The only explanation is the legend string at 741, "TOP 3 = best OVR on the board". Missing: a per-row reason chip (best scheme fit / best value), both of which the row already computes (schemeFit, valueScore).
- [ ] **The hire board's "Affordable" filter is a hard binary switch against the whole remaining budget, with no max-salary control.**
  - feature · effort S · `TODO.md:3067`
  - HireCoachView.swift:44 (@State showAffordableOnly) and 213-216 — the filter is list.filter { $0.salary <= remainingBudget }; the control at 653-661 is a plain Toggle(.switch). Missing: a max-salary slider, or a default that reserves the seat's share of the pot (the auto-hire plan at CoachingStaffView.swift:711 already computes per-seat allocations).
- [ ] **There is no "best available given my current staff" sort on the coaching hire board — every ranking is raw OVR.**
  - feature · effort M · `TODO.md:3073`
  - HireCoachView.swift:157-167 — SortColumn is name/age/scheme/ovr/play/dev/game/salary/value only; candidateRank (1348-1352) counts men with a higher coachOverall, and the detail sheet's "Best Available" badge (2009) is just rank 1. Missing: a composite that weighs role focus attributes, scheme fit and HC chemistry, all of which are already computed per candidate.
- [ ] **Coach profiles still cannot show real career history — clubs served, win rate and rings — because the sim keeps no per-season coach record.**
  - feature · effort L · `TODO.md:3088`
  - HireCoachView.swift:1595-1665: the card was renamed CAREER HISTORY → EXPERIENCE and now derives 2-3 lines from age, years and role via careerHistoryLines, so the "ONE line" premise is fixed. The rename comment states the remaining condition: "The sim does not persist per-season coach history yet — when it does, this is the card that earns the old name back." Real work is the persistence, not the card.
- [ ] **Lowballing a coach offers no "if he walks, here is who's next" preview to soften the risk.**
  - feature · effort S · `TODO.md:3094`
  - The negotiation card already prints acceptance % (HireCoachView.swift:2687-2698), the coin-flip salary (:2534-2547 / coinFlipSalary at :1531-1537) and an offer assessment (:2705-2720), and rejection is real — onRejected greys the candidate out (#271, :2961-2962). Nothing surfaces the next-ranked candidate at the same seat, though candidateRank / totalCandidates are already in scope (:1450-1451).
- [ ] **There is no aggregate rating for the position-coach group — the only staff roll-up averages every seat including the head coach and coordinators.**
  - feature · effort S · `TODO.md:3106`
  - Missing: the group figure. dynasty/dynasty/UI/Staff/CoachingStaffView.swift:2027-2044 (section header shows only cost range and 8/8) and 2989-2992 (`staffOverall` averages `book.coachRoles`, surfaced as the Review tab's "Staff" chip at 3223-3229)
- [ ] **There is no way to save a staff hiring template and re-apply it in a later career.**
  - feature · effort M · `TODO.md:3110`
  - Missing entirely: no `staffTemplate` / `StaffPreset` / save-staff symbol anywhere under dynasty/dynasty. The nearest existing affordance is one-shot `Auto-Hire Recommended Staff` (UI/Staff/CoachingStaffView.swift:4130-4203)
- [ ] **The staff review has no one-sentence readiness verdict at the top naming the scheme the staff is built for and its weakest seat.**
  - feature · effort S · `TODO.md:3132`
  - CareerDashboardView.swift:5531-5563 — the sheet opens straight into `staffSection`; the nearest things are the league-rank strip (:5980) and the money sentence (:6268), neither of which reads the schemes or names a weak chair.
- [ ] **A weak roster fit for the installed scheme never becomes a draft or free-agency priority — team needs are computed from depth and quality alone.**
  - feature · effort M · `TODO.md:3145`
  - DraftEngine.evaluateTeamNeeds / teamNeedComponents (:1397-1406) scores positions on roster depth and quality; "scheme" appears nowhere in that path. The staff review measures the fit (CareerDashboardView.calculateRosterFit, used at :6485) and then drops it. Prospect-level fit does exist downstream (PickGradeCalculator.swift:46, LiveBigBoardPanel.swift:1284, FAOfferSheet.swift:254) — what is missing is the priority tag flowing from the review into those boards.
- [ ] **"Staff chemistry: Poor" names no culprits, though the score is built pair by pair and the offending pairs are already known.**
  - feature · effort S · `TODO.md:3146`
  - CareerDashboardView.swift:6706-6734 — calculateStaffChemistry walks every coach pair and applies -10 for each clashingPairs hit, then throws the pairs away and returns an Int. staffChemistryRow (:6682-6703) prints only the grade. Surfacing the top one or two clashes is a return-type change, not new analysis.
- [ ] **The staff review offers only a present-tense snapshot — no multi-year projection of how this staff develops.**
  - feature · effort M · `TODO.md:3151`
  - CoachingStaffReviewSheet's sections are staffSection, budgetSection, schemesSection, warningsSection, buttonsSection (CareerDashboardView.swift:5533-5561); the only forward-looking number anywhere is the league rank strip (:5980-6011). The inputs for a projection exist — Coach.potentialLabel(seasonsOnTeam:) (Coach.swift:237-243) and CoachDevelopmentEngine's HC mentoring multiplier (:43-49) — but nothing composes them.

## scouting · 26  (M 8 · S 18)

- [ ] **The Combine tab still offers a live "Send Scouts to the Combine" button with zero scouts hired — it charges the trip and files zero reports, because the CTA gates on budget alone.**
  - bug · effort S · `TODO.md:3382`
  - dynasty/dynasty/UI/Scouting/CombineResultsView.swift:584-623 disables only on !canAffordTrip; ScoutingHubView.swift:500-536 spends combineTripCost (60 + 10n = $60K at n=0) and sets scoutsSentToCombine regardless; ScoutingEngine.swift:3663 `guard !scouts.isEmpty ... else { return 0 }`. The Scout Team tab does hide its own row at 0 scouts (ScoutTeamView.swift:94-134).
- [ ] **The "Update Big Board" task can never reach done — it has no completion criterion anywhere in the app.**
  - bug · effort S · `TODO.md:3384`
  - Engine/Simulation/TaskGenerator.swift:872-879 builds it as a plain GameTask with no `progress:` stage and default completesOnVisit: false, so CareerShellView.markTaskVisited (:2686-2697) can only set .inProgress; there is no `case "Update Big Board"` in the refreshTaskCompletion switch, and the only other mention in the repo is InboxEngine.swift:264.
- [ ] **Nothing prevents a career from advancing through the whole draft-prep pipeline with zero scouts hired — no task, no advance gate.**
  - design · effort M · `TODO.md:3383`
  - TaskGenerator.combineTasks (Engine/Simulation/TaskGenerator.swift:832-918) contains no hire-scouts step; the four advance gates the shell holds are staff seats/budget, depth-chart gaps, roster limit and cap compliance (CareerShellView.swift:221-264, StaffLedger.swift:199-203) — none reads scout headcount. The scouting screens only explain the state (BigBoardView.swift:445, :1001).
- [ ] **The Scout Notes Recommendations block uses four unrelated icon-and-tint pairs where one badge vocabulary would do.**
  - design · effort S · `TODO.md:3396`
  - ScoutNotesView.swift:146-200 — `exclamationmark.triangle.fill`/.warning for the #1 need, `target`/.success for best-at-need, `star.fill`/.accentGold for best available, `list.number`/.accentBlue for picks. No shared badge component; each row hand-rolls its own HStack.
- [ ] **The red Boom/Bust risk pill carries no explanation anywhere it appears, and the sentence that would explain it is dead code.**
  - design · effort S · `TODO.md:3400`
  - ProspectListControls.swift:455-495 — `ProspectRiskBadge` has no `.help`, no `accessibilityHint` and no tap target; `tint(.boomOrBust)` is `.danger`. ProspectDetailView.swift:1081-1092 defines `riskExplanation(_:)` with the exact copy needed and it has zero call sites in the file.
- [ ] **The "Your #1 vs Media #1" callout on Scout Notes is inert text with no way to ask why the two boards disagree.**
  - design · effort M · `TODO.md:3404`
  - ScoutNotesView.swift:317-345 — a `VStack` of `Text` inside a list row, no Button, no NavigationLink, no sheet. The inputs for an explanation exist (`UserDraftBoard.sorted`, `mediaTopProspect` off `draftProjection`, `ProspectFog.valueRead`) and are unused for this.
- [ ] **The "available at Rd N #M: X%" line never says the percentage is the chance he is still on the board when the club picks.**
  - design · effort S · `TODO.md:3405`
  - ScoutNotesView.swift:348-361 prints `Int(prob * 100)` from `reads.availableAtPickProbability(for:)` with no caption, no help and no tap target. The same number appears unlabelled in the board's tier header (BigBoardView.swift:1811-1824).
- [ ] **Scout Notes tells the user to set roster priorities but gives no control to go and do it.**
  - design · effort S · `TODO.md:3410`
  - ScoutNotesView.swift:272-275 — "You: Set your priorities in Roster Evaluation" is a plain `Text` in tertiary grey inside the depth section, with no Button, no `onSwitchTab` call and no route out of the scouting hub. `onSwitchTab` exists on the view (:54) and is used only by the empty state (:381-393).
- [ ] **Combine Report rows show only position, name and headline — no grade and no projected round, so the reader cannot tell whether a name matters at his draft slot.**
  - design · effort S · `TODO.md:3418`
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1852-1870 — mentionRow draws a position chip, prospectName and headline and nothing else, although the sheet already holds the full `prospects` array (:1758).
- [ ] **The Combine Report never states a Stock Faller's actual projection change, even though the combine's own drift pass records a from/to round for every man it moves.**
  - design · effort S · `TODO.md:3424`
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1852-1870 prints only the prose headline (fallerHeadline, ScoutingEngine.swift:3853-3858, says "stock drops" with no number); the real delta lives in ScoutingEngine.ProjectionMove (:4369-4377) produced by WeekAdvancer.swift:3781-3799 and shipped only to the news feed.
- [ ] **The Combine Report has no closing line telling the player that the combine results have already been written into his board.**
  - design · effort S · `TODO.md:3430`
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1793-1850 — the List ends at the last category section, no footer; the reports were in fact filed before the sheet opened (applyCombineScouting at :520-524, sheet raised at :535).
- [ ] **The combine table has no key for its red row markers — red on the Pos chip means defence, and the red capsule beside a name means roster need**
  - design · effort S · `TODO.md:3437`
  - CombineResultsView.swift:1411-1417 `positionColor` paints the Pos chip `.danger` for every defensive prospect; the red capsule at :1007-1015 is the "NEED" chip from `DraftEngine.teamNeedDeficits`. Neither is explained on screen, and the reusable `InfoTooltipButton`/`LetterGradeLegend` pair (ProspectGradeMenuView.swift:426-500) is wired into the Big Board and Mock Draft but not here.
- [ ] **Tapping the combine table's GRD header sorts the table; it never reveals what the A+/A/B+ scale means**
  - design · effort S · `TODO.md:3438`
  - CombineResultsView.swift:727 `sortableHeader("GRD", column: .grade, …)` — the button's only action is `toggleSort`. The grading-scale explainer already exists as `InfoTooltipButton(showLetterGradeKey: true)` + `LetterGradeLegend` (ProspectGradeMenuView.swift:426-500) and is used at BigBoardView.swift:1585/1622/1650 and MockDraftView.swift:673, so this is wiring an existing component.
- [ ] **On interview-report cards only the #1 rank is gold; every other rank is still 14 pt tertiary grey.**
  - design · effort S · `TODO.md:3480`
  - InterviewSelectionView.swift:1984-1986 — Text("#\(rank)") at .system(size: 14, weight: .heavy) with foregroundStyle(isTopPick ? Color.accentGold : Color.textTertiary). The interview score was added underneath (:1987-1989) but the rank's own size and colour for ranks 2+ were not changed.
- [ ] **Interview grades use a 5-band A/B/C/D/F ladder while the rest of the app grades on a 9-band scale with plus/minus.**
  - design · effort S · `TODO.md:3487`
  - InterviewResult.interviewGrade and .footballIQGrade band at 85/75/65/55 into A/B/C/D/F (InterviewSelectionView.swift:1157-1187). PositionGradeCalculator.letterGrade returns A / B+ / B / B- / C+ / C / C- / D / F (UI/Roster/RosterView.swift:1611-1623). Only the colour was unified — both interview helpers now delegate to Color.forGrade (:2398-2404) — the ladders still disagree.
- [ ] **A prospect's personality archetype is printed with no statement of what it actually does for the club.**
  - design · effort S · `TODO.md:3508`
  - `PersonalityArchetype` (Domain/Enums/PersonalityArchetype.swift) exposes only `displayName`, `shortLabel` and `tier` — no effect blurb. ProspectDetailView.swift:1436-1449 and :1817-1846 print the name plus a tier colour and nothing else, while the archetype genuinely drives CoachingEngine.swift:1389-1417 (chemistry pairs), :2095-2098, LockerRoomEngine mentoring (WeekAdvancer.swift:2031) and ContractNegotiationEngine.swift:902. Needs one sentence per archetype, surfaced on the card.
- [ ] **The big board offers no multi-select for marking prospects — every board mark is one row at a time.**
  - feature · effort M · `TODO.md:3406`
  - BigBoardView.swift:904-911 puts a single `ProspectMarkButton` on each row; the only multi-row selection is `compareSelection`, capped at 4 and wired solely to `ProspectCompareSheet` (:1018-1027, :1373-1391). No `EditButton`, `editMode` or selection binding anywhere in the file.
- [ ] **The Combine Report has no inline star or watch action — acting on a name requires pushing into the prospect card.**
  - feature · effort S · `TODO.md:3426`
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1811-1836 — the row is a NavigationLink and nothing else: no swipeActions, no trailing button, no context menu.
- [ ] **The Combine Report never places a riser or faller against the user's Big Board position or the latest mock.**
  - feature · effort M · `TODO.md:3427`
  - dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1793-1870 — the sheet holds only `mentions`, `career` and `prospects` and renders name + headline; mock snapshots exist separately (recordMockDraftSnapshot("Combine"), WeekAdvancer.swift:3818).
- [ ] **There is no composite athleticism score for combine invitees — a manager can rank by one drill at a time only**
  - feature · effort M · `TODO.md:3446`
  - No composite exists anywhere in the app (`athleticismScore` / `athleticScore` / `combineScore` / `RAS` return nothing across dynasty/dynasty). `CombineColumn` (CombineResultsView.swift:1534-1540) has one case per raw drill, and `PercentilePools` ranks each drill independently. Needs a weighting model per position plus a column and a sort case.
- [ ] **The combine table cannot be filtered to risers, fallers or unmoved prospects — only by position**
  - feature · effort S · `TODO.md:3448`
  - CombineResultsView.swift only filters on `positionFilter` (:138, :481) and switches column blocks with `viewMode`. `CombineMovers.improvement` (:1512-1517) already classifies every prospect, but is consumed only by the top-five rails (`combineRisers`/`combineFallers`, :332-343) and the hub's teaser count.
- [ ] **No combine row is highlighted when the week moved the prospect's projected round**
  - feature · effort S · `TODO.md:3451`
  - CombineResultsView.swift:411-416 — the only `listRowBackground` is `index % 2` zebra striping. The GRD cell does carry a rising/falling arrow (`DualGradeDisplay(trajectory:)`, :722-727, drawn at ProspectGradeMenuView.swift:390-397), and `CombineMovers.improvement` measures the grade-ladder move, but nothing keys off a change in `projectionDisplayText`.
- [ ] **The interview card's "Affects scheme learning speed" hint never states the numeric effect football IQ has on install speed.**
  - feature · effort S · `TODO.md:3488`
  - InterviewSelectionView.swift:2062-2064, plus qualitative high/low sentences at :2129-2153 — no number anywhere. The real term is VersatilityDevelopmentEngine.learnScheme's learningRate *= player.learning / 65.0 (Engine/PlayerDevelopment/VersatilityDevelopmentEngine.swift:343). Note the honesty constraint: interview IQ is 0.5·awareness + 0.5·trueLearning plus noise (Engine/Scouting/ScoutingEngine.swift:1529-1532), so only half of the displayed number is the install term.
- [ ] **Up to three scout reports can be filed on one prospect but the card only ever surfaces the latest one — the differing opinions are never shown.**
  - feature · effort M · `TODO.md:3510`
  - ProspectDetailView.swift:1557-1563 `latestOwnFilmReport` takes `.last` only, and the FILM instrument slot (:1512-1521) reopens that single report. The Instruments card (:2830-2843) shows an aggregate "Scouted (N reports)" plus the latest scout's name. `ScoutEvaluationBudget.maxReportsPerProspect` is 3, so two earlier reports exist on the model and have no reader.
- [ ] **The prospect comparison card measures a prospect only against the club's own best man at the position, never against the free agents available at it.**
  - feature · effort M · `TODO.md:3512`
  - ProspectDetailView.swift:1098-1101 — `starterComparisonCard` filters `teamPlayers` (loaded from the club roster at :3062-3068) and takes `.first`. Nothing on the card reads the free-agent pool.
- [ ] **No synthesised recommendation ties a prospect's scouting, interview and combine reads into one two-sentence verdict.**
  - feature · effort M · `TODO.md:3515`
  - No "Director" symbol exists anywhere in the Swift source. `myVerdictCard` (ProspectDetailView.swift:557-612) holds the USER's own free-text note plus a market-vs-my-grade read; nothing generates a recommendation from the three instruments.

## inbox · 10  (L 1 · M 6 · S 3)

- [ ] **Every inbox row prints the same coarse phase label because a message carries a display string, not a timestamp.**
  - design · effort M · `TODO.md:3523`
  - InboxMessage.date is a plain String (InboxMessage.swift:13), stamped once per phase from InboxEngine.dateLabel(week:season:phase:) (InboxEngine.swift:26, 1829-1862 — "Offseason - The Combine, 2026"); InboxView.swift:262-267 renders it verbatim on every row. No field on the model can produce a relative time.
- [ ] **Message bodies render as one raw string, so the "- " lines the generators write stay plain text instead of a bulleted list**
  - design · effort S · `TODO.md:3543`
  - MessageDetailView.swift:46-50 — `Text(message.body).font(.body)`, no parsing. InboxEngine.swift:247-251 writes the bullets as literal `- ` lines ("- Several prospects at positions of need tested exceptionally well"), and the same convention runs through `combineMediaDigestMessage` (:1274-1278) and `seniorBowlDigestMessage` (:1325-1334).
- [ ] **The inbox has no bulk actions — no mark-all-read, no delete, no overflow menu.**
  - feature · effort S · `TODO.md:3526`
  - InboxView.swift:79-87 — the only toolbar item is the read-only "N unread" Text. The `messages` binding is mutated only by markAsRead(messageID:) (:112-117), and the row is a plain Button with no swipe or context actions (:182-215).
- [ ] **Inbox messages carry no game-time — the model has no week/season fields, so two messages from different moments in the same phase are indistinguishable.**
  - feature · effort M · `TODO.md:3530`
  - InboxMessage.swift:8-41 stores only `date: String` alongside subject/body/category; InboxEngine.generatePhaseMessages computes one dateString per phase (InboxEngine.swift:26) and stamps every message in that batch with it (~90 `date: dateString` call sites).
- [ ] **The League Network "Mock Draft: <team> Projected to Select…" message still has no CTA, while the newer personnel-director mock message already links out.**
  - feature · effort S · `TODO.md:3531`
  - InboxEngine.swift:271-285 builds it with no `attachments` and no `actionDestination`; the sibling mockDraftMessage attaches "Open Mock Draft" (.mockDraft) and "Open Big Board" (.bigBoard) at :1593-1596.
- [ ] **Inbox messages cannot be archived or pinned — the model has no such state and the list offers no such gesture.**
  - feature · effort M · `TODO.md:3532`
  - InboxMessage.swift:8-41 — `isRead` is the only mutable field; everything else is `let`. InboxView.swift:182-215 wraps the row in a plain Button with no swipeActions or contextMenu.
- [ ] **There is no reply path for inbox messages — the detail view is read-only plus navigation.**
  - feature · effort L · `TODO.md:3533`
  - MessageDetailView.swift's only controls are Close (:77), the action button (:195-205) and attachment links (:156-190); no compose or response affordance exists, and InboxMessage has no thread/response model.
- [ ] **An "Action Required" message never clears — reading it only marks it read, and nothing ties it to a completion criterion**
  - feature · effort M · `TODO.md:3549`
  - InboxMessage.swift:16 declares `let actionRequired: Bool` (immutable, never written after construction); InboxView.swift:114-118 `markAsRead` only flips `isRead`. The sort at :59-61 leaves a read action-required letter at priority 1 with its red `Color.danger` chip (:274, :301) permanently. No hook connects `actionDestination` to the task system.
- [ ] **The inbox is one-way — no message can be replied to or discussed**
  - feature · effort M · `TODO.md:3551`
  - `grep -n 'reply|Reply'` over InboxView.swift, MessageDetailView.swift and InboxMessage.swift returns nothing. `InboxMessage` (InboxMessage.swift:8-42) has no reply/thread field, and MessageDetailView's only controls are Close, the attachments rows and the `actionButton` deep link.
- [ ] **Scouting messages come from a hardcoded "Director of Scouting" string, never from the club's actually hired Chief Scout**
  - feature · effort M · `TODO.md:3553`
  - `.scout(name: "Director of Scouting")` appears as a literal 13 times in InboxEngine.swift (:239, 421, 449, 641, 979, 1250, 1295, 1337, 1374, 1422, 1476, 1629, 1705) and once in NewsGenerator.swift:946. The hireable staffer exists — `ScoutRole.chiefScout` (ScoutRole.swift:7) on a named `Scout` with `accuracy`/`personalityRead` (Scout.swift:14-27) — but is never consulted, and `Scout` carries no voice or tone trait to match against.

## cap · 8  (M 2 · S 6)

- [ ] **The next-season cap projection row is labelled "~5% increase" but is computed at 6.5%.**
  - bug · effort S · `TODO.md:3341`
  - Missing: the label was never updated with the math. dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:1560 uses `ContractEngine.capGrowthPerSeason`, which is the 0.05…0.08 midpoint = 6.5% (Engine/Contract/ContractEngine.swift:32-38), while line 1593 still prints `"Projected Cap (\(nextSeason), ~5% increase)"`
- [ ] **The Cap Outlook 4-up KPI strip labels are 11pt tertiary-weight text with no icons under large coloured values.**
  - design · effort S · `TODO.md:3331`
  - Missing: bold labels / icons. dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:1706-1719 — `capStatColumn` prints the value at title3 bold and the label at `.caption2` `textSecondary`, no glyph
- [ ] **The league-average cap reference still prints as tiny grey text under the bar instead of a labelled tick on the bar itself.**
  - design · effort S · `TODO.md:3333`
  - Missing: the 78% marker. dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:1676-1680 — `Text("League avg: ~78%")` at `.caption2` / `textTertiary`
- [ ] **Cap scenarios A/B/C all fill the same green below 90% usage, and nothing badges the roomiest one.**
  - design · effort S · `TODO.md:3334`
  - Missing: saturation variation or a "best for cap" badge. dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:2591-2634 — `pctColor` is `.success` for everything under 0.9, and the mini bar uses that single colour
- [ ] **In each cap scenario card the percentage is the headline number while "Available: $X" is caption text on the bottom row.**
  - design · effort S · `TODO.md:3335`
  - Missing: the promotion. dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:2608-2650 — percentage is `.subheadline.bold` top-right, `Available:` is `.caption` bottom-left
- [ ] **"+ Est. Replacement Cost" is printed with no explanation that it is each expiring player's own market value at this cap.**
  - design · effort S · `TODO.md:3342`
  - Missing: the explainer, which the same figure already has on the other cap screen. dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:1618-1622 is a plain `projectedCapRow`; compare UI/Contracts/CapOverviewView.swift:1223 ("Replacement is each expiring player's own market value at this cap — not a veteran minimum.")
- [ ] **There is no "restructure top contracts" cap scenario, although the engine can already price a restructure.**
  - feature · effort M · `TODO.md:3343`
  - Missing: scenario D. dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:2452-2467 builds only release-all / re-sign-top-3 / re-sign-all; `CapManagementEngine.restructureQuote` (Engine/Contract/CapManagementEngine.swift:1237) is the number it would need
- [ ] **No cap scenario is recommended by default — nothing ranks A/B/C or explains why one fits the club.**
  - feature · effort M · `TODO.md:3347`
  - Missing: the recommendation. dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:2477-2500 — `selectedCapScenario` starts empty and the only per-scenario copy is the tradeoff line each card already prints

## dashboard · 8  (M 2 · S 6)

- [ ] **During OTAs the shared camp hero card still prints the header "Training Camp · Install & Evaluation".**
  - bug · effort S · `TODO.md:3614`
  - CareerDashboardView.swift:4320-4321 routes both .otas and .trainingCamp to campHeroCard, whose header is the unconditional literal at :4506. The stale-data half of the complaint is fixed: the "Day N/21" counter was removed with its reasoning (:4487-4493), and overloadedShare (:4474-4480) is the same figure the Workload tile prints (:1982-1990), so hero and heat-map can no longer contradict.
- [ ] **Owner satisfaction moves silently: the engine computes a delta from win %, streak, news sentiment and milestones, then writes the score with no feed or inbox entry naming the cause.**
  - bug · effort M · `TODO.md:3618`
  - OwnerSatisfactionEngine.updateSatisfaction (OwnerSatisfactionEngine.swift:8-110) ends at `owner.satisfaction = min(100, max(0, owner.satisfaction + delta))` and emits nothing; the dashboard reads it through OwnerPersonaEngine.jobSecurity (OwnerPersonaEngine.swift:118-136) at CareerDashboardView.swift:3199. The OVR half is partly served — breakout/late-bloomer development does generate news (WeekAdvancer.swift:8351-8367) and DevelopmentReportView shows deltas — so scope this to the owner rating.
- [ ] **Dashboard tiles still spend a full row on their all-caps title instead of an inline header-with-value layout**
  - design · effort S · `TODO.md:2842`
  - CareerDashboardView.swift:5395-5420 — `DashboardTile` still draws a dedicated header HStack (icon + title + optional ACTIVE pill + chevron) followed by a `Divider()` before `content()`. Nothing merges the title row with the tile's first value. Missing: an inline variant that puts the tile's headline number on the title row.
- [ ] **The dashboard's Position Grades tile still prints every position group's starter/depth letters, duplicating the Roster Evaluation screen, even though a separate Team Needs tile already condenses the three weakest groups.**
  - design · effort S · `TODO.md:3376`
  - dynasty/dynasty/UI/Career/CareerDashboardView.swift:2856-2905 renders all of positionGroupGrades in two columns; the same letters come off PositionGradeCalculator in RosterEvaluationView.swift:717-760. teamNeedsTile at CareerDashboardView.swift:1517-1549 already shows the bottom three.
- [ ] **The dashboard Messages header badge is an unlabelled count of unread mail sitting over a list of the five most recent messages regardless of read state, so the two numbers still disagree with nothing on screen to reconcile them.**
  - design · effort S · `TODO.md:3377`
  - dynasty/dynasty/UI/Career/CareerDashboardView.swift:838-846 (bare Text("\(unread)") in a danger capsule, no label, no accessibilityLabel) vs :911 (Array(filtered.reversed().prefix(5))). Elsewhere the app does label it — :1469-1472 prints "N unread".
- [ ] **The Advance Week button shows no busy state — the week advance runs synchronously on the main actor and the UI simply freezes**
  - design · effort M · `TODO.md:3666`
  - CareerDashboardView.swift:317-341 `runAdvance` calls `WeekAdvancer.advanceWeek` inline inside `PerfLog.time`, as does CareerShellView.swift:1606-1613 `performShellAdvance`; neither sets an in-flight flag. TimelineTasksPanel.swift:841-869 guards the button only on `canAdvance`, which does not change during the advance — there is no spinner, overlay or transient disable. The parent P0 line already records "Still open: run the advance off the main actor with a progress overlay for slower devices."
- [ ] **The Roster tile shows only headcount and cap space — no roster-health or position-holes line**
  - feature · effort S · `TODO.md:2868`
  - CareerDashboardView.swift:2331-2360 — `rosterTile` renders exactly two rows, Players and Cap Space. The needs data exists elsewhere (`teamNeedsTile` at :1532, `positionStrengthsTile`'s NEED badge at :2872-2876) but is not summarised on this tile. Missing: a one-line "Needs: WR, EDGE" derived from `positionGroupGrades` on the Roster tile.
- [ ] **Key Players tags each player's role but still shows only three names**
  - feature · effort S · `TODO.md:2876`
  - CareerDashboardView.swift:2806-2830 — the rows now carry role tags ("QB1", the best defensive player's position, and "TOP" for highest OVR), so the "why are these key" half is answered. But the tile is still exactly three hard-coded rows: `startingQB`, `bestDefensivePlayer`, `bestPlayer`. Missing: extending to 5-7 with further role tags (top cap hit, expiring).

## team selection · 8  (L 1 · M 5 · S 2)

- [ ] **The team detail sheet shows last season's W-L with no playoff result and no multi-season trajectory**
  - feature · effort M · `TODO.md:2663`
  - TeamSelectionView.swift:1466-1468 — `detailHeader` prints only `Text("Last Season: \(preview.lastSeasonRecord)")`. `TeamPreview` (LeagueTeamData.swift:14-31) carries `lastSeasonWins`/`lastSeasonLosses` and nothing else historical — no playoff outcome, no prior years. Missing: new preview fields, authored into the static table and derived for `TeamBrowseCatalog.template`.
- [ ] **The team detail sheet names the starting QB and no other roster fact — no stars, no weakest position**
  - feature · effort M · `TODO.md:2664`
  - TeamSelectionView.swift:1615-1648 — `startingQBCard` is the only player content in the sheet. `TeamPreview` (LeagueTeamData.swift:14-31) has `startingQBName`/`startingQBOverall` and an `estimatedOVR` aggregate; there are no per-position or top-player fields. Missing: 2-3 star players plus a weakest-position line on both catalog paths.
- [ ] **Owner patience names a season count but never says what happens when it runs out**
  - feature · effort S · `TODO.md:2665`
  - TeamSelectionView.swift:1525-1551 — `ownerExpectationsCard` prints the patience tier plus "Gives you N seasons before the pressure mounts". Nothing states the consequence (firing, mandate, trade demand) even though `FiredSummaryView.swift` and `OwnerSatisfactionEngine.swift` are the real mechanics behind it. Missing: one consequence line under the patience row.
- [ ] **Market & Media on the team detail sheet is pure flavour text even though media market drives real numbers**
  - feature · effort S · `TODO.md:2666`
  - TeamSelectionView.swift:1553-1569 — `marketMediaCard` prints `preview.marketDescription` and nothing else. The mechanics exist and are read: `MediaMarket.freeAgentAttraction` 0.8/1.0/1.3 and `mediaPressureMultiplier` 0.7/1.0/1.5 (MediaMarket.swift:8-22), consumed by FreeAgencyEngine.swift:3506/3704/3875, OwnerSatisfactionEngine.swift:79, EventEngine.swift:102 and BudgetEngine.swift:76/118/165. Missing: printing those multipliers beside the copy.
- [ ] **The team detail sheet says nothing about young core, expiring contracts, dead cap or scheme fit**
  - feature · effort L · `TODO.md:2667`
  - TeamSelectionView.swift:1770-1788 / :1792-1814 — the portrait and landscape layouts list every card in the sheet: header, locked banner, difficulty, statsRow, QB, owner, market, coaching budget, division rivals. None of the four is present, and `TeamPreview` (LeagueTeamData.swift:14-31) carries no age, contract or scheme data. The league is not generated until `startCareer` (:709), so the generated-catalog path needs new derivations, not just new display.
- [ ] **The team detail sheet has no "what to expect in Year 1" summary — projected wins, moves needed, pressure timeline**
  - feature · effort M · `TODO.md:2673`
  - TeamSelectionView.swift:1770-1788 — no such card exists in either layout. The closest single element is `ownerExpectationsCard`'s "Gives you N seasons before the pressure mounts" (:1543). Missing: a projected-wins figure (nothing in `TeamPreview` supplies one) and a needs summary.
- [ ] **You cannot preview a team's 53-man roster before committing to it — only the starting QB is shown**
  - feature · effort M · `TODO.md:2674`
  - TeamSelectionView.swift:1770-1788 — no roster route in the sheet. `TeamBrowseCatalog` holds only `TeamPreview` per abbreviation (TeamBrowseCatalog.swift:34, :45-48). The template path does have real players (`starterAverage` walks `LeagueTemplate.TeamTemplate` at :152-157), but the generated path has none until `LeagueGenerator` runs inside `startCareer` — so this is available for template leagues and needs a synthetic preview for generated ones.
- [ ] **Upcoming UFA stars on a prospective team are still not surfaced, though rival division strength now is**
  - feature · effort M · `TODO.md:2675`
  - Half shipped: `divisionRivalsCard` (TeamSelectionView.swift:1656-1706) now prints each rival's record, roster OVR and situation chip on the shared 3-tier ladder, with the comment "makes the card read as 'how tough is my division' instead of filler". The UFA half is absent — `TeamPreview` (LeagueTeamData.swift:14-31) has no contract data at all.

## contracts · 6  (? 2 · M 1 · S 3)

- [ ] **The franchise-tag age warning is a single hard past-peak gate that also never fires on an elite player**
  - balance · effort S · `TODO.md:3362`
  - FranchiseTagView.swift:681-700 — `isPastPeak = player.age > player.position.peakAgeRange.upperBound` is checked only AFTER the `overall >= 85` branch returns. A 30-year-old CB/LB (peak 25...30, Position.swift:115-118) is exactly at the bound and gets no warning, and a 33-year-old 87 OVR WR gets "strongly consider tagging" with no age note at all. No approaching-the-edge band exists.
- [ ] **The Contract card's "Fair Value" verdict never states the band it is testing**
  - design · effort S · `TODO.md:3227`
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:3116-3124 — the thresholds are market/salary > 1.3 → Bargain, > 0.8 → Fair Value, else Overpaid; the Value pill (:1065) and the card explainer (:1003) say none of this.
- [ ] **On the Franchise Tag rows the "Tag Cost" caption still sits below the dollar figure rather than above it**
  - design · effort ? · `TODO.md:3354`
  - FranchiseTagView.swift:525-537 — the `VStack` puts `Text(formatMillions(tagCost))` first and the "Tag Cost" + info-icon row second. The size hierarchy was improved since the review (an 11 pt caption under a 15 pt `textPrimary` figure, with a tappable breakdown), but the requested order flip was never made.
- [ ] **Applying a franchise tag commits on first tap with no confirmation, against the design rule that names franchise tags by example**
  - design · effort ? · `TODO.md:3365`
  - FranchiseTagView.swift:1071-1088 — `applyTag` calls `ContractEngine.applyFranchiseTag` and saves immediately; no `alert`/`confirmationDialog` guards it (the only one on the screen is "Skip Franchise Tag?" at :81). docs/UI_REDESIGN_VISION.md:254-258: "Irreversibility always confirms… Owner whims, franchise tags, substitutions and press answers currently commit on first tap." The row does offer a Remove afterwards (:412-427).
- [ ] **The Contract card prints salary and market value side by side but never states the gap ("underpaid by $5M")**
  - feature · effort S · `TODO.md:3226`
  - dynasty/dynasty/UI/Roster/PlayerDetailView.swift:3116-3124 — marketValueComparison reduces market/salary to a Bargain/Fair/Overpaid enum; the Market and Salary pills at :1062-1064 print two absolute figures and no delta.
- [ ] **There is no transition tag anywhere in the codebase — the franchise tag is the only tag the game models**
  - feature · effort M · `TODO.md:3363`
  - `grep -rn 'transitionTag|Transition Tag' dynasty/dynasty` returns nothing outside build artefacts. `Player.isFranchiseTagged` is the single tag flag (readers across CapOverviewView, ContractTimelineView, FinalPushView, TradeView), and `ContractEngine.applyFranchiseTag` the single application path. A transition tag needs a second cost formula plus a right-of-first-refusal step in free agency.

## press conference · 5  (M 1 · S 4)

- [ ] **The Diplomatic draft answer's media reaction mirrors the question topic instead of the answer**
  - bug · effort S · `TODO.md:2926`
  - PressConferenceEngine.swift:736-739 — tone `.diplomatic` still returns `"\(r.outlet): “\(team.name) putting emphasis on the draft.”"`. Its three siblings in the same question are answer-specific ("BPA philosophy", "wants to see film", "Trade-back strategy" at :700/:713/:726), so this is the one line out of step.
- [ ] **The press conference never reminds the coach of his own archetype before he answers in character.**
  - design · effort S · `TODO.md:2596`
  - PressConferenceView.swift — `career.coachingStyle` has exactly one reader in the file, :2016 `FranchiseIdentityDeclaration.seed(for:)`, in the summary phase. `roomReadCard` (:1004-1043) reads the room, the roster, the building and the owner, and says nothing about the coach.
- [ ] **There is no way to hand a press conference to the media team and take average outcomes — every question must be answered by hand.**
  - feature · effort M · `TODO.md:2597`
  - PressConferenceView.swift has no skip, auto-respond or delegate path: the only exits are `beginQuestioning` (:433) and per-question commits (:2312-2360). The two occurrences of "skip" in the file (:91, :1142) are prose in doc comments. `PressConferenceEngine` exposes no average-outcome entry point.
- [ ] **Answer cards carry no on-character / off-character tag against the coach's own coaching style**
  - feature · effort S · `TODO.md:2620`
  - PressConferenceView.swift:1349-1455 — `responseCard` shows the tone chip, the quote, fogged hints and a headline preview; nothing reads `career.coachingStyle`. The only place it is read on this screen is the post-session summary (`summaryFrontOffice` at :2015-2017, comparing `FranchiseIdentityDeclaration.podiumRead(for: result.dominantTone)` against `seed(for: career.coachingStyle)`), so the consequence is revealed after all four answers. Note `PressConferenceEngine` applies no archetype penalty, so any per-card tag must be framed as the identity read, not a morale cost.
- [ ] **The introductory press conference still asks the same four fixed topics in the same order every career, with no team-state wildcard**
  - feature · effort S · `TODO.md:2924`
  - PressConferenceEngine.swift:293-313 `generateIntroConference` appends vision → cap → fans → draft unconditionally, plus a media-pressure question only in a large market. The weekly presser's ~18 state-seeded generators (division win/loss, narrow loss, sacks allowed, workhorse, power rank, MVP race, streaks, deadline, opener, finale — :834-1841) have no intro equivalent; only the reporter and the effect weights vary.

## sim · 5  (M 2 · S 3)

- [ ] **Field-goal make chance stops decaying past 56 yards, so a 62-yarder is priced identically to a 56-yarder and snow costs only 5 points of it.**
  - balance · effort S · `TODO.md:2098`
  - PlaySimulator.swift:2199-2201 — the `default:` band is a flat `baseMakeChance = 0.42` for every attempt of 56 yards or more, with no further distance term; :2211-2216 applies a flat -0.05 for rain/snow (wind's -0.10 needs `.wind` specifically). With the accuracy modifier at :2204 a strong-legged kicker still converts a 62-yarder in snow at roughly 40%. The shorter bands were retuned against NFL reference in F-41 (:2181-2198); the 56+ band was not.
- [ ] **Nothing bounds or measures per-game scoring in a coached sim-to-final, so a 60-21 blowout has no guard rail.**
  - balance · effort M · `TODO.md:3697`
  - LiveGameEngine.simToEnd (2710-2722) loops step() with only a 500-play safety cap — no score check. The prep boosts are clamped at construction (audibleBoost ≤0.20, defReadBoost ≤0.15, lines 1270-1271) and applied at half strength to per-play momentum (1491-1497), but no test or harness gate measures the resulting coached-game score distribution. Missing: a measured audit plus a drift cap.
- [ ] **The field snap plate and the top HUD chip can briefly show different downs during a play transition**
  - bug · effort S · `TODO.md:1687`
  - dynasty/dynasty/UI/Match/CoachedGameView.swift:3799-3805 captures the plate as a fixed string at the snap and clears it 1.8 s later, while the chip at :813 reads live shown.down, which revealHUD only advances when choreography finishes (:4213-4227) — a play resolving inside 1.8 s leaves the stale plate on screen beside the advanced chip.
- [ ] **About 15% of pass targets are still depth receivers off the 3D field, and the choreographer then silently animates the ball to the design's primary read instead of the man the feed names.**
  - bug · effort S · `TODO.md:3719`
  - PlaySimulator.swift:3336 `primaryTargetShare = 0.85` over `primaryTargets` (:3346-3357) leaves the remaining share to the `depth` pool (:4039-4048); PlayChoreographer.swift:2211-2216 `targetRole` falls back to `c.spec.primaryRole` whenever the sim's target is not one of the on-field eligibles [1,7,8,9,10].
- [ ] **A Stats-motivated player is told he is "unhappy if production drops" but no in-season morale or motivation path reads that motivator**
  - feature · effort M · `TODO.md:3265`
  - `Motivation.stats` is read only by contract/free-agency code (FreeAgencyEngine.swift:3496/3880/3988, SigningInterestEngine.swift:215, ContractNegotiationEngine.swift:915, TamperingRumorEngine.swift:131). `LockerRoomEngine.applyMoraleEffects` branches on the motivator only for `.money` and `.loyalty` (:270-285), and `PlayerDevelopmentEngine.evaluateMotivation`'s demotion trigger (:1072-1078) gates on competitiveness, never on the motivator. The copy at PlayerDetailView.swift:3072 promises a mechanic that does not exist.

## special teams · 3  (L 1 · M 2)

- [ ] **Special teams is modelled as two positions (K and P) — return, coverage and blocking units are not represented on the roster at all.**
  - feature · effort L · `TODO.md:3202`
  - Position.swift:75-77 assigns only `.K` and `.P` to `PositionSide.specialTeams`; RosterView.swift:249-251 groups them as the sole ST group; ScoutBoardReads.swift:44-48 `idealRosterCounts` budgets `.K: 1, .P: 1` and nothing else for the unit. The depth chart carries KR/PR slots drawn from the whole roster (DepthChart.swift:220-223) but the roster screen has no view of them.
- [ ] **Returners are modelled as depth-chart slots but long snapper, holder and gunners still do not exist anywhere.**
  - feature · effort M · `TODO.md:3203`
  - DepthChart.swift:220-223 `specialTeamsSlots` = [.K, .P, .KR, .PR], and KR/PR rank on speed/agility rather than overall (:167-179) — so the returner half of this item shipped. Grepping the whole source for long snapper, holder or gunner returns nothing; there is no slot, position or attribute for any of the three.
- [ ] **No rating exists for the special-teams unit as a whole — only per-man grades for the kicker and punter.**
  - feature · effort M · `TODO.md:3209`
  - Grepping the source for a special-teams unit rating (specialTeamsRating / stRating / coverageUnit / specialTeamsGrade) returns nothing. The Specialists header's letters come from `PositionGradeCalculator.calculatePositionGrades(players:positions:scheme:)` over [.K, .P] only (RosterView.swift:1647-1649).

## balance · 1  (L 1)

- [ ] **The shipped offseason development pass converts potential ~2 OVR/player/season faster than the balance rig, holding the league's 80+ share above band.**
  - balance · effort L · `TODO.md:3881`
  - Still asserted in-tree: MultiSeasonSmokeTest.swift:1393-1413 ("the residual is REALIZATION, not headroom … diag devsource offseasonDevelop = +2.2/player/season here") and LeagueGenerator.swift:864-871 ("That is the task-#51 gap, still open"). DraftClassBuilder.runwayCentre is back at 0.55 (DraftClassBuilder.swift:922) after the 0.40 attempt broke four §6 asserts. Next lever named by both: the WeekAdvancer.processOffseason inputs (opportunity / coaching layers / scheme fit), not a generator constant. Needs its own measured wave against rig AND app smoke.

## depth chart · 1  (M 1)

- [ ] **Out-of-position depth-chart assignments show a fit grade but no cost — and no honest "-X OVR" penalty exists to show, because the sim never docks out-of-position play**
  - feature · effort M · `TODO.md:3628`
  - Engine/PlayerDevelopment/VersatilityDevelopmentEngine.swift:375-386 — positionPerformanceModifier is documented dead: "Nothing calls this, and as the sim stands nothing can", because GameSimulator builds every unit by filtering on player.position. The picker currently offers only candidate.versatility.label and the team-OVR delta from DepthChart.impactOfAssigning (UI/Roster/DepthChartView.swift:1500-1521, :1730-1740), and no learning-curve estimate.

## faces · 1  (S 1)

- [ ] **The coach-portrait picker has no Male/Female filter — all 20 photos of both genders sit in one shuffled grid.**
  - feature · effort S · `TODO.md:2722`
  - UserPortraitPicker (UserPortraitView.swift:244-322) draws a single LazyVGrid over UserPortrait.shuffled(seed:) with only a Shuffle button; no gender state anywhere in NewCareerView.swift. ExtrasCatalog.avatars(gender:) (ExtrasCatalog.swift:162) exists but is used only to build persona labels, and its own doc comment still claims "Male"/"Female" dividers the picker never draws.

## free agency · 1  (L 1)

- [ ] **There is still no user-facing street / post-FA signing screen, so a club that leaves free agency without a kicker cannot acquire one.**
  - feature · effort L · `TODO.md:3606`
  - InSeasonMarketEngine.runWeeklyPass covers only the 31 AI clubs (Engine/Contract/InSeasonMarketEngine.swift:119 filters out career.teamID) and its own comment says the user "has no in-season free-agency screen either … the user's half is a screen and belongs with the rest of D6" (:88-95). FACompleteView does list a K with zero bodies as a "High" remaining need (UI/FreeAgency/FACompleteView.swift:931-942) but never blocks. The progression half is separately de-fanged: the depth-chart task no longer requires unfillable slots (CareerShellView.swift:2979-2985) and the starter-gap gate skips slots no body exists for (:371-377).

## match ui · 1  (S 1)

- [ ] **Matchup callouts are still transient capsules only — they never reach the play feed history.**
  - feature · effort S · `TODO.md:3720`
  - CoachedGameView.swift:4340-4361 `showMatchupCallouts` writes `matchupCallouts` and clears it 3.4s later; `engine.lastMatchups` (LiveGameEngine.swift:131) is never appended to `playLog` (its append sites are :1612, :2681, :3104, :3505-3506, :3660).

## owner · 1  (S 1)

- [ ] **The intro owner meeting still shows two untargeted prose goals while the season is actually scored against a different, targeted goal set.**
  - design · effort S · `TODO.md:2946`
  - Missing: intro reads `SeasonGoals.generate` (Domain/Models/League/SeasonGoals.swift:44-51 — "Win the division" / "Build depth through the draft", no target, no evaluation) via UI/Career/IntroSequenceView.swift:207, while the season uses OwnerGoalsEngine.generateSeasonGoals (Engine/Media/OwnerGoalsEngine.swift:59-180) with real targets (12 wins, 3 rookies at a starts bar) wired at WeekAdvancer.swift:1114

## owner goals · 1  (S 1)

- [ ] **Nobody has measured whether the owner's "Develop 3 Rookies" primary goal is reachable under its current starts-based test.**
  - verification · effort S · `TODO.md:4172`
  - The goal is live at OwnerGoalsEngine.swift:126-135 (target 3, .primary) and is scored at :381-400 against a bar of max(1, teamGames / 3) rookie starts, credited from the lineup WeekAdvancer fields each week. Scope is one club — generateSeasonGoals writes career.ownerSeasonGoals only (:229), so AI clubs have no owner goals at all. What is missing is a season run counting how many rookies clear the bar; nothing in the tree records one.

## tasks · 1  (S 1)

- [ ] **"Update Big Board" has no completion criterion at all, so it sits at "in progress" forever and the user can never see it tick.**
  - bug · effort S · `TODO.md:3562`
  - TaskGenerator.swift:871-879 constructs it with the default completesOnVisit: false and no predicate; CareerShellView's completion switch (~:2900-3010) has no "Update Big Board" case, so markTaskVisited can only raise it to .inProgress (:2688-2695). It is isRequired: false, so it blocks nothing — the defect is purely that it never reaches .done.

## tooling · 1  (S 1)

- [ ] **The anonymization bundle gate still has to be run by hand — no release script or CI step invokes check_bundle.sh**
  - tech-debt · effort S · `TODO.md:363`
  - There is no .github/ directory in the repo, and nothing outside TODO.md/BACKLOG.md references `check_bundle.sh` except the script itself and doc comments in make_templates.py. The script (tools/league-data/check_bundle.sh:24-26) builds Release itself and supports `--no-build`/`--app`. Duplicated by TODO.md:383.

## training · 1  (M 1)

- [ ] **Mentor-mentee pairs assigned on the Mentoring screen are never saved or read — the engine pairs veterans with rookies automatically and ignores the user entirely.**
  - bug · effort M · `TODO.md:3645`
  - MentoringView.swift:28 holds pairs as view-local @State; nothing persists it and no engine reads MentoringPair (it is a struct declared at :5-15 in that same file). PlayerDevelopmentEngine.applyMentoring (:1575-1610) does its own pairing from personality, leadership and position. Meanwhile the screen promises "Active pairs apply +1-3 mental attribute bonuses during offseason development" (:88). The reported ergonomics defect is real too — assignPair clears selectedMentor at :490.

---

## Needs a device or a human eye

22 items no agent can close by reading code.

- [ ] **Eyeball the shipped portraits on an iPad — silhouette vs real face, team ring colours, legibility at small size** — faces · `TODO.md:348`
  - Needs a device and a human eye; nothing in the repo can settle it. The code side is in place (Resources/Faces/ is populated and PersonFaceView is wired across the app), so only the visual pass remains.
- [ ] **Eyeball the development/training overhaul on an iPad — draft class PROD/LRN/CMP columns, Player Detail motivation badge and Coach's Projection, the new development-report reasons, and the scheme-change news item** — development · `TODO.md:392`
  - Needs a device and a human eye; the note also carries a device-handling instruction (delete the app first so the removed fi.lproj does not linger), which nothing in the repo can confirm.
- [ ] **On-device iPad eyeball of the regenerated draft class — Prospects/Big Board/Combine PROD and LRN columns, A grades at the top, RB/S in rounds 1-2, K/P ≥ 3** — draft · `TODO.md:404`
  - Needs an iPad, a live save that predates the migration, and a human eye on the rendered screens; nothing in the repo can settle it.
- [ ] **Whether the QB's trousers still render greyer than his team-mates' white pants needs a rendered frame — and the figure path the observation was made on is now only a fallback.** — match · `TODO.md:1913`
  - dynasty/dynasty/UI/Match/FootballFieldScene.swift:5491-5521 — SkeletalFigure is the primary path when FieldConstants.useSkeletalFigures is true; buildKitFigure/buildProceduralFigure now run only when it is not. PANTS is one shared tint on either path (:5189-5195; SkeletalFigure.swift:414, :465-474).
- [ ] **The referee's touchdown and first-down hand signals are wired but have never been caught in a captured frame.** — match · `TODO.md:1914`
  - dynasty/dynasty/UI/Match/FootballFieldScene.swift:5005 (refereeSignalTouchdown) and :5021 (refereeSignalFirstDown), called from CoachedGameView.swift:4005-4007. Confirming the animation reads on screen needs an eye on a live TD/FD moment.
- [ ] **The match camera's orientation during an away game has never been checked — the QA session only played a home game.** — match · `TODO.md:1915`
  - dynasty/dynasty/UI/Match/FootballFieldScene.swift:1214-1239 and :1331-1335 flip viewFacing/lateralSign, end walls, yaw and the camera rig for either direction; :1331 explicitly notes "viewFacing for away games". Only a played away game proves it renders right.
- [ ] **Clear-weather fog depth has never been eyeballed in an actual clear-weather game.** — sim · `TODO.md:2180`
  - Needs a played clear-weather match to judge: the values are set (dynasty/dynasty/UI/Match/FootballFieldScene.swift:5881 `applyFog(color: clearFogColor, start: 70, end: 210)`, colour at 5904-5906) but nothing in the repo can confirm how they read on screen
- [ ] **A 4th down inside field-goal range still has to be played in the simulator to confirm the FG card selects rather than commits.** — sim · `TODO.md:2253`
  - The path is present and identical to the punt path — CoachedGameView.swift:2272-2280 (`engine.canAttemptFieldGoal` gates the card; the tap only sets `fourthDownChoice`) and :2310 `snap(forcedType: choice)` — but confirming it needs a live run that happens to land on such a down.
- [ ] **Whether an additive rain particle still tints a player pink for a frame needs an eye on a rain game.** — match ui · `TODO.md:2312`
  - Rain is still `system.blendMode = .additive` (FootballFieldScene.swift:6086), but the coach lens now runs alpha 0.11, particleSize 0.06 and stretchFactor 0.022 (:6082-6090) versus the 0.3/0.32/0.06 of the original fix — far fainter, but only a rendered rain game can settle it.
- [ ] **Whether the hire-candidate modal reads as elevated above the dimmed staff screen behind it.** — coaching · `TODO.md:3062`
  - The flow is a system sheet, not an app-drawn overlay: CoachingStaffView.swift:1420 presents it with .sheet(item:) and 1454 sets .presentationSizing(.page), so corner radius, shadow and parent dimming are all UIKit's. Nothing in the repo controls the elevation; judging it needs an eye on a device.
- [ ] **The FA Complete screen's reported infinite layout-loop hang cannot be confirmed or refuted from source — the current view has no loop-capable structure.** — free agency · `TODO.md:3610`
  - UI/FreeAgency/FACompleteView.swift:100-167 is a plain ScrollView + LazyVStack with a pinned DSActionBar; every derived figure loads once in .task into @State (:163-166, loadData at :791) and the file contains no GeometryReader at all. Confirming the hang is gone needs an actual FA phase run on a simulator.
- [ ] **On-device rendering cost of the 22 figures on the 3D field.** — perf · `TODO.md:3702`
  - Needs hardware not in the repo. The premise has also moved: players are now single skinned meshes with a frustum-culling guard on the skinned geometry node (SkeletalFigure.swift:326, 340-360), not 8-primitive assemblies, and flattenedClone appears nowhere in the codebase — it cannot flatten a skinned node anyway.
- [ ] **ScoutNotesView has never been seen rendering on a device and still needs a hands-on look.** — scouting · `TODO.md:3892`
  - Needs a simulator or device run; the screen exists and compiles (UI/Scouting/ScoutNotesView.swift, 436 lines, routed from ScoutingHubView.swift:751 via the `.scoutNotes` War Room tab), but nothing in the repo can prove it has drawn.
- [ ] **The scouting hub's collapsed-by-default Insights block is built but has not been watched behaving in a running app.** — scouting · `TODO.md:3893`
  - The default is in code — ScoutingHubView.swift:788-800 records that #174 deleted the free one-shot expansion, so the block stays shut until the user opens it, keyed per surface by `insightsSurfaceKey` (:803-805). Confirming the runtime behaviour needs a device run.
- [ ] **The portrait-orientation fit of the scouting hub's slat band plus War Room tab row has been reasoned about on paper but never drawn.** — scouting · `TODO.md:3894`
  - The two rows exist and are laid out at ScoutingHubView.swift:932-963 (`DraftPrepProcessBar` over `ScoutingWarRoomTabs`, each with 12 pt horizontal padding); `warRoomTabs` is six entries (:751-752) and `DraftPrepStageCell.bandSteps` supplies the slats. Whether they fit 1032 pt without truncating needs an actual portrait iPad render.
- [ ] **The QA-03/QA-04/QA-05 fixes were built after the last season run, so they have never been exercised in a live save.** — qa · `TODO.md:3896`
  - Stated cause in TODO.md:3896-3897 — the simulator was running an older build. Closing this needs a fresh build plus a full season run; no repo artefact can substitute.
- [ ] **F-74: the user still reads every veteran's true overall while all 32 AI clubs now read them through fog — blocked on deciding whether a fogged rating shows as a range, a letter, or a shifted number** — free agency · `TODO.md:3900`
  - The AI half landed (commit bdc0a99, `AIDraftPerception.veteranSigmaUncapped` at AIDraftPerception.swift:145 and the two F-23 fog sites in FreeAgencyEngine.swift:2678, :3120), so the asymmetry the item names is real and current. The user half cannot start until the display question is answered — docs/AI_FIX_QUEUE.md:2470-2474 records it as the load-bearing decision, and the TODO section is literally "Odottaa käyttäjää". It needs the user's design call, not a code lookup.
- [ ] **The preseason screen has never been audited — it needs a save that is naturally sitting in preseason, and the simulator driver could not get one there.** — preseason · `TODO.md:4212`
  - The single-door observation checks out in code: PreseasonView is pushed only from the "Preseason Slate Unplayed" advance gate, with the comment "there is no other door to it" (CareerShellView.swift:711-713, :2251). Running the audit itself needs the simulator and a preseason-phase save — neither is in the repo, and the recorded attempt stalled three times on navigation.
- [ ] **The scouting hub's 7 process slats plus 6 war-room tabs have never been drawn in portrait — the fit is arithmetic only.** — scouting · `TODO.md:5059`
  - Needs a device or simulator run at 1032 pt portrait; nothing in the repo records the layout being rendered. The 6-tab list it has to fit is ScoutingHubView.swift:753-754 and the slat band is DraftPrepProcessBar.swift.
- [ ] **ScoutNotesView has never been rendered on a device — its empty state, scrolling under the hub chrome and out-of-List block layout are all unchecked.** — scouting · `TODO.md:5060`
  - UI/Scouting/ScoutNotesView.swift exists and compiles (436 lines, struct at :43), but the three open questions are visual and need a simulator run. TODO.md records the same gap a second time at line 3892.
- [ ] **The collapsed-by-default Insights behaviour was built but never observed running.** — scouting · `TODO.md:5061`
  - The code path is present and pure — ScoutingInsightsDefaults.resolvedExpansion reads without writing (DraftPrepProcessBar.swift:545-547) and resolveDefault no longer re-arms on a phase change (:620-624) — but confirming what a user actually sees after a calendar advance across the hub's surfaces needs a device run.
- [ ] **The on-sim trade verifications #38/#46 were never attempted — they need a simulator slot.** — trades · `TODO.md:5062`
  - No later TODO entry records them being run (grep for "on-sim" / "simuslot" across TODO.md returns only this line). The engine work they would verify did land — see the #150/#151 fixes in TradeValueEngine.respond (Engine/Contract/TradeValueEngine.swift:2150-2280).

---

## Recorded decisions found in the queue

20 entries that are choices, not work. They belong with the other
limitation notes rather than in a backlog.

- **The template league's older age pyramid is an accepted, recorded difference from the random league — deliberately not calibrated, and guarded only against drift.** — league data · `TODO.md:360`
  - The entry says so itself ("HYVÄKSYTTY ERO (ei korjata, kirjattu)") and the guard shipped: tools/league-data/make_templates.py:3204 registers gate 18 `age-profile-in-drift-band`, and tools/league-data/out/TRANSFORM_QA.md:35 records it PASSing at mean age 26.7 (band 25.0-28.0) and 5.4% aged 33+ (ceiling 8.0%), with §7 (line 221) stating it fails only on drift.
- **Template rosters ship at 55-57 men and the camp cutdown trims them to 53 before the first season — recorded as expected behaviour, not a bug.** — roster · `TODO.md:384`
  - Self-labelled "Huom (ei bugi)". Still true: dynasty/dynasty/Engine/Camp/RosterCutEvaluator.swift:7-18 documents the 90→75→65→53 cutdown ladder that runs before the first season
- **debugSimulate's ~24-25% completion rate is the harness's own metric level, not the game's — paired-run deltas from it are still valid** — sim · `TODO.md:1575`
  - Recorded under "Havainnot / rajaukset" for the 2026-07-11 verification round, and explicitly cross-referenced to the earlier R36 limitations. It states a known property of the measurement harness; there is no task in it.
- **The play clock was toggled off via UserDefaults during the 2026-07-11 verification and restored to 10s — no state was left changed** — sim · `TODO.md:1577`
  - A session log line under "Havainnot / rajaukset", self-closing by its own text ("pysyvää tilamuutosta ei jäänyt"). Nothing to implement or check.
- **The 2026-07-11 verification advanced a career save from W10 to W12 and committed nothing — the app state lives in the user's save** — sim · `TODO.md:1578`
  - A session log line under "Havainnot / rajaukset" ("EI committoitu mitään, apptila on käyttäjän savessa"). A record of what the verifier touched, not a task.
- **The 10-second decision clock auto-calling a play when the coach does not choose is designed behaviour, and it is configurable** — sim · `TODO.md:1685`
  - dynasty/dynasty/UI/Match/CoachedGameView.swift:405-412 — "the coach gets this long to pick a call before the QB (or the DC) checks into a simple base play and the snap goes off automatically. Never a delay-of-game penalty"; PlayClockSetting offers off / 10 s / 15 s at :3098-3105 and the clock pauses under every overlay at :3109-3113.
- **The 0.1-0.2 s render hold when the result plate appears was measured inside the acceptance threshold and accepted; the separate-layer polish was not taken** — sim · `TODO.md:1686`
  - TODO.md:1602-1603 records criterion (b) as PASS with the longest hold at 0.2 s across all 26 burst windows; the plate is still a plain @State string rendered in the main view tree (dynasty/dynasty/UI/Match/CoachedGameView.swift:3799-3805), i.e. no layer split was made.
- **Recorded test technique: the 10-second play clock plus idb tap latency makes scripted play-calling fragile, and the Coach's Board pause works as a freeze-frame in automated runs.** — tooling · `TODO.md:2100`
  - Explicitly marked "ei tuotekoodia" (not product code) in TODO.md:2100 — a note about how to drive the simulator, not a change to the app. The pause it relies on is verified in the same section's entry (e) at TODO.md:2094.
- **Live player stats update at drive granularity while battle results update per play — a recorded limitation of the live game engine, not a bug.** — sim · `TODO.md:2178`
  - dynasty/dynasty/Engine/Match/LiveGameEngine.swift:399-403 — "Stats accumulate per completed drive; battles update per play", read by `playerGameGrade` and `compactStatLine` (839-851)
- **NFL's two overtime timeouts are deliberately not modelled — OT continues on whatever second-half timeouts remain.** — sim · `TODO.md:2560`
  - LiveGameEngine.swift:3441-3448 restocks `homeTimeouts`/`awayTimeouts` only inside the `quarter == 3` halftime branch; no overtime path touches them.
- **Penalties fire on scrimmage snaps only — punts, field goals and kickoffs are deliberately flag-free.** — sim · `TODO.md:2561`
  - PlaySimulator.swift:135-143 — `if playCall == .pass || playCall == .run, randomChance(scaledPenaltyChance) { return rollPenalty(...) }` is the sole call site of `rollPenalty` (:1985).
- **Half-distance-to-goal is deliberately simplified: a penalty longer than the offense's own field position clamps to the 1-yard line instead of halving.** — sim · `TODO.md:2562`
  - PlaySimulator.swift:2042 `yards = -min(10, yardLine - 1)` (holding) and :2048 `yards = -min(5, yardLine - 1)` (false start).
- **Recorded as skipped in R20: replacing the main-menu hero photo needs a commissioned art asset, not a code change.** — main menu · `TODO.md:2690`
  - The skip note is carried in the item itself ("R20: jätetty väliin — vaatii uuden taideassetin, ei koodikorjaus") and the asset is untouched — MainMenuView.swift:36 still renders Image("HeroImage") full-bleed under a five-stop darkening gradient (:43-53). Nothing in code blocks the swap; it waits on art.
- **Recorded preference: keep the red/green contrast between a strong Coach Fit and a weak Roster Fit in the staff review.** — coaching · `TODO.md:3139`
  - Praise, not a task — and the treatment is intact: both numbers run through fitBarColor → Color.forRating(percent, scale: .percent) (CareerDashboardView.swift:6604-6606), the shared ladder the file adopted so this card and SchemeSelectionView stop describing the same number on different scales.
- **The Injury History card (green check, "No injury history", durability score on the right) was reviewed and approved as-is.** — roster · `TODO.md:3241`
  - Still shipping unchanged at PlayerDetailView.swift:2300-2325 — checkmark.circle.fill in Color.success, "No injury history", "Durability: N" and the right-hand durability readout coloured by colorForAttribute.
- **Cap scenarios A/B/C are deliberately analysis-only — the fake "queued" receipt was removed rather than made real.** — cap · `TODO.md:3340`
  - dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:2477-2483 (#173: the old tap handler stamped a receipt over a `TODO` that mutated nothing and no screen read the selection) and 2517-2521 ("Analysis only — nothing is queued. Make the moves yourself in Roster and Free Agency.")
- **Recorded praise for the interview-report card pattern (grade top-right, IQ chip, character chip, micro-stats) — keep it.** — scouting · `TODO.md:3477`
  - Not a task, a "keep this" note. The pattern still stands in InterviewSelectionView.resultCard (:1966-2160). The one element named in it that is gone is the bust-risk delta line, deliberately replaced — see the item on line 3479.
- **Recorded praise: the prospect card's header pattern (name, position chip, age/height/weight, grade, report count, projected round) is the one to copy.** — scouting · `TODO.md:3498`
  - ProspectDetailView.swift:715 `prospectHero` still carries the pattern; the item states no defect and asks for no change.
- **Recorded praise: the prospect-vs-current-starter comparison card is the pattern worth reusing on other screens.** — scouting · `TODO.md:3502`
  - ProspectDetailView.swift:1097-1177 `starterComparisonCard` still ships, now on one shared `StarterVerdict` ladder (:1186-1216). The item names no defect and no concrete target screen.
- **Recorded praise: the post-game press flow is the pattern to copy for other narrative moments, and it already covers the older tone-tag/running-total requests** — press conference · `TODO.md:3672`
  - Not a task — an observation. It is borne out by the code: PressConferenceView.swift merged both pressers into one component (:1-14), and the stance chip (:1284-1311), per-answer effect previews (:1463-1505) and running impact (:838-905) it credits are all in that file.