# QA — ONE DRIVEN SEASON, 2026-08-24

Source: a live playthrough on the iPad Pro 13-inch sim (`049C7295…4353`), fresh Debug build
`24.8. 14:17`, new career **Houston Astronauts**, Generated league, Quick Start. The whole
offseason was driven for real — staff hiring, roster evaluation, franchise tag, contract
negotiation, the combine, interviews, film study, free agency's final push, cap compliance,
the FA market, pro days and a seven-round draft — and every screen was screenshotted.
A second run drove the 2028 offseason on the FIXED build all the way through OTAs,
training camp, the three-game preseason slate and the 75/65/53 cut ladder.

Each distinct screen went through the `analyze-app` four-lens audit (designer / casual player /
hardcore player / game developer) in parallel agents, and every **blocking**/**high** claim was
then handed to a separate adversarial verifier whose job was to REFUTE it against the Swift
source. What is below survived that pass; each entry names the file the verifier read.

**606 findings**: 10 blocking, 143 high, 342 medium, 111 low.


---

## BLOCKING (10)


### Intro — session result

- [ ] **Q-B01 · Outcome headline is derived from tone, not from the media number — it says "steady, professional operator" while media reputation just fell to -21 ("Scrutinized")**
  - evidence: 012 headline: "The media sees a steady, professional operator", directly under the gold "PRESS CONFERENCE" seal, with the subtitle "That is how the room writes you up. It shapes free-agent interest, fan engagement and the tone of your coverage." On the previous screen (011) the RUNNING IMPACT chip reads "MEDIA -21" in red. In code the headline is `Text(mediaPerceptionLabel(for: result.dominantTone))` (PressConferenceView.swift:1215) and `mediaPerceptionLabel` is a pure switch on tone (:1683-1691) — `.diplomatic` always returns "The media sees a steady, professional operator", whatever the arithmetic. Meanwhile `LegacyTracker.applyPressConferenceResult` books `mediaReputation = clamp(0 + (-21))` (LegacyTracker.swift:73), and `reputationLabel` maps -21 into the `-30 ..< -10` band = "Scrutinized" (LegacyTracker.swift:100). The player is told the room likes him on the exact screen where the engine records that it does not.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1215`
  - fix: Derive the headline from `result.totalEffects.mediaPerception` (or from the resulting `mediaReputation` band label) and use `dominantTone` only for flavour: e.g. "Five straight non-answers — the room files you as evasive (Media -21, now Scrutinized)". At minimum, never print a positive media verdict when the media delta is negative.


### Roster evaluation

- [ ] **Q-B02 · "Starter" column prints the group's BEST player while the "S:" grade beside it is the starting-unit AVERAGE — 7 of 9 rows contradict the app's own grade table**
  - evidence: On both 030 and 032 the table reads: WR "94" next to "S: B+"; LB "91" / "S: B+"; DB "89" / "S: B"; OL "86" / "S: B+"; DL "81" / "S: B"; RB "79" / "S: B-"; ST "77" / "S: B-". The app's own ladder (PositionGradeCalculator.letterGrade, RosterView.swift:1605) is 85+=A, 80-84=B+, 75-79=B, 70-74=B-. So 94 must be A, 89 must be A, 81 must be B+, 79 must be B, 77 must be B. The only two rows where number and letter agree are QB "86 / A" and TE "73 / B-" — and those are exactly the only two single-starter groups (EvalPositionGroup QB=[.QB], TE=[.TE], line 12 and 15). Cause: `starterOVR: topOVR` where `topOVR = groupPlayers.map(\.overall).max()` (line 377), rendered under the header "Starter", while `starterGrade` comes from the average of the top-n starters. Both are labelled "Starter"/"S:" on the same row with no legend. The card above states "Setting priorities affects draft board rankings and scouting focus", so a player reading WR as elite off the 94 (when the starting trio grades B+) mis-sets a priority that propagates straight into the draft board.
  - code: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:377`
  - fix: Rename the column to "Best" (or show the starting-unit average there instead) and add a one-line legend under the table: "Best = top player in the group · S: = average of the projected starters · D: = average of everyone behind them". Cheapest correct fix: print both, e.g. "94 best / 82 avg".


### Contract negotiation

- [ ] **Q-B03 · The signed deal's headline terms are not the terms written: sheet says "$108.0M total / $54.0M/yr", the contract booked is $117.0M with a $60.5M year-one cap hit**
  - evidence: 038 shows, in four places, the same flat numbers: sheet "YEARS 2 · CAP HIT $54.0M/yr · TOTAL $108.0M · GUARANTEED 69%", receipt "Wade Braithwaite — 2 years, $108.0M total, 69% guaranteed", and the transcript card "2 Years / $43.0M Salary / $22.1M Bonus / Total: $108.0M / Cap Hit: $54.0M/yr". Those come from NegotiationOffer.totalValue (annualSalary*years + bonus) and .annualCapHit (salary + bonus/years). What is persisted is frontLoadedBaseSalaries: [$43.0M x 1.15 = $49.4M, x0.92 = $45.5M] = $94.9M base + $22.1M bonus = $117.0M, with year one charging $49.4M + $11.05M = $60.5M. The screen's own cost line proves it: "Charges $23.0M of your $44.2M in room" is exactly $60.5M less the $37.4M he was already carrying — the books used $60.5M while the headline said $54.0M/yr. Same on 037: "Cap Hit: $46.0M/yr" vs "Charges $14.2M" ($37.5M x1.15 + $8.5M = $51.6M, minus $37.4M = $14.2M). ContractEngine's own doc says it: "the schedule does NOT sum to annualSalary x years... a 2-year veteran deal pays 10.4% over the negotiated total... a flat 'salary + bonus / years' quoted as the cap hit is a different number from the one that gets booked." The negotiation UI is that forbidden caller. The 69% guarantee is also computed off $108.1M, so the written deal is 63.8% guaranteed, not 69%.
  - code: `dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:2699 (chips) and :2622 (receipt); dynasty/dynasty/Engine/Contract/ContractEngine.swift:1508-1540 (booking) and :640-650 (frontLoadedBaseSalaries); dynasty/dynasty/Engine/Contract/DealTargetYear.swift:302-323 (firstYearCapHit)`
  - fix: Price every receipt off the schedule the deal will be written with, not the flat average: quote plan.firstYearCapHit as "Year 1 cap hit", sum(baseSalaries)+bonus as Total, and show the AAV as a secondary line if it is kept at all. Alternatively renormalise frontLoadedBaseSalaries/escalatingBaseSalaries so the schedule sums to annualSalary x years — then the flat number becomes true and every existing surface is fixed at once.


### Film study

- [ ] **Q-B04 · Film Study says both "0/25 reports" and "View Report (46)" on the same screen — 46 reports the player never ordered already set every price**
  - evidence: Header pill: "FILM STUDY / 0/25 reports · 16% scouted · The Combine". Stage chip: "3 FILM STUDY / 0/25 reports · spends 1 scouting week". Order header: "0/25 used". Action bar: "25/25 evaluations remaining" — and immediately to its right "View Report (46)". Every one of the 13 visible RECOMMENDED rows already carries an RPT value of "1/3" or "2/3" and a gold TAPE band (Ackerly "A-/A+", Broadwater "C/A-", Brockway "C+/B+", Crisanti "B-/A+"), and not one row is priced at the $15K first-look tier — every NEXT cell reads "$25K" or "$40K".
  - code: `dynasty/dynasty/UI/Scouting/FilmStudySelectionView.swift:750, :937, :295, :453, :1503; dynasty/dynasty/UI/Scouting/ProspectDetailView.swift:78, :92; dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:2319; dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift:2617`
  - fix: `filedCache` counts `hasOwnFilmReport` (any report whose scoutName != "Previous Staff"), which picks up the reports `ScoutingEngine.applyWeeklyReports` stamps automatically during the college season; `evaluationsUsedStored` never sees them. Either exclude auto-generated `.collegeSeason` reports from `chargeableReports`/`hasOwnFilmReport` so the ladder starts at $15K and "View Report" only counts ordered tape, or count them against the 25-slot ledger so "0/25" stops lying. Do not ship two counters both labelled "reports" that read 0 and 46 eight points apart.


### Press reaction

- [ ] **Q-B05 · MORALE and FANS are the two biggest numbers on the press screen and neither is ever written to the game**
  - evidence: 060 RUNNING IMPACT reads "OWNER +6 · MORALE +28 · FANS +8 · MEDIA 0" — MORALE +28 is the largest number on the screen — and the ledger under it reads "WHAT IT ACTUALLY COST · OWNER -2 · MORALE +5 · FANS -4 · MEDIA -11". Same on 048 ("MORALE +15 · FANS -9", ledger "MORALE +8 · FANS -5") and 007 ("MORALE +19 · FANS +5"). Every response card sells them as a decision axis: "Locker room ↑ will back you", "Fans ↓ will groan". In code the only consumers of PressEffects.playerMorale / .fanExcitement are this view and sessionFeedback: applyPressConferenceEffects (CareerShellView.swift:1832-1846) applies only owner satisfaction plus legacy/media; IntroSequenceView.applyPressConferenceResult:106-133 the same; LegacyTracker.applyPressConferenceResult:72-86 touches only totalPoints, mediaReputation and promises. A grep for totalEffects across dynasty/dynasty returns owner, legacy and media only — no roster morale, no fan/attendance model.
  - code: `dynasty/dynasty/UI/Career/CareerShellView.swift:1832-1847; dynasty/dynasty/Engine/Media/PressEngine.swift:962-976; dynasty/dynasty/UI/Career/PressConferenceView.swift:1361-1372`
  - fix: Either apply them (spread playerMorale across the roster the way the holdout resolution does at CareerShellView.swift:1267, and route fanExcitement into whatever fan/market state exists) or delete both axes from the hint row, the running strip and the ledger. Shipping four meters where two are inert makes the whole fogged-hint system untrustworthy the first time a player checks the locker room after a presser.


### Press session summary

- [ ] **Q-B06 · MORALE and FANS are phantom stats — the two biggest numbers on the card are never written to any game state**
  - evidence: 740_season_061 shows "MORALE +28" and "FANS +8"; 740_season_050 shows "MORALE +15" and "FANS -9" (the only red number on that screen); 720_season_011 shows "MORALE +23" and "FANS +2". In code, PressEffects.playerMorale / .fanExcitement (PressConferenceEngine.swift:54) are read ONLY by display code in PressConferenceView (lines 656-657 running strip, 1085-1089 per-answer pill, 1366-1367 this card). Both apply sites write everything else and neither touches them: CareerShellView.applyPressConferenceEffects (1832-1846) writes owner satisfaction + legacy; IntroSequenceView.applyPressConferenceResult (106-129) writes owner satisfaction, legacy and franchise identity; PressEngine.commit (962-977) writes pressToneHistory + pressPromiseLedger; LegacyTracker.applyPressConferenceResult (72-74) writes totalPoints and mediaReputation. A real Player.morale exists (Player.swift:114) and LockerRoomEngine moves team morale (LockerRoomEngine.swift:598), but no press-conference path ever reaches either, and fanExcitement has no model in the app at all outside PressEffects.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1366`
  - fix: Pick one and do it in this build: (a) wire it — route totalEffects.playerMorale into the roster morale the sim already reads, and give fanExcitement a real home (fan support / attendance / owner pressure input); or (b) delete the two columns from WHAT CHANGED, from the running strip (656-657) and from the per-answer pills (1085-1089). Shipping a green +28 that moves nothing turns the whole podium into a fake trade-off — the player optimises answers for locker-room morale and buys literally nothing.


### Playoff hub

- [ ] **Q-B07 · OPPONENT SCOUT names the wrong club ("Vs JAX") in all three playoff rounds**
  - evidence: 063: the band's live chip reads "WILD CARD  NOW / vs DEN" and the rail task reads "Prepare for Wild Card vs Denver Summit", but the OPPONENT SCOUT tile reads "Vs JAX / Strengths & weaknesses". 064: band "DIVISIONAL NOW / vs NE", task "Prepare for Divisional Round vs New England Colonials" — tile still "Vs JAX". 065: band "CONFERENCE NOW / @ KC", task "…vs Kansas Cit…" — tile still "Vs JAX". Three rounds, three opponents, one frozen tile. Proof it is staleness and not a different lookup: the WEEK PREP tile next to it does move ("Week 19 prep" → "Week 20 prep" → "Week 21 prep") because it reads career.currentWeek live, while the scout tile reads the @State array.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1551-1573 (tile) → :336 (currentWeekFixture) → :3549 (upcomingGames written only in loadAllDataBody) → :484 (.task) / :496 (.onAppear refreshes staff+roster only) / :296 (runAdvance delegates to onAdvance and skips loadAllData)`
  - fix: CareerDashboardView owns its own copies of upcomingGames/lastGame (loaded at :3549) but only refetches them in `.task` (first mount) and in its own local advance branch. Since CareerShellView passes `onAdvance: { performShellAdvance() }` (CareerShellView.swift:517), `runAdvance` takes the `if let onAdvance { onAdvance() }` branch at :294 and never calls loadAllData(), so every fetched value on the hub is frozen from the last mount. Either add `.onChange(of: career.currentWeek) { loadAllData() }` to the dashboard, or have the shell call back into the dashboard's reload after performShellAdvance (onWeekResultRecorded already proves the callback channel exists). Same root cause as the missing skip-game confirmation below.

- [ ] **Q-B08 · Advancing sims your unplayed playoff game with no confirmation and no warning**
  - evidence: On all three screens the club's playoff game is unplayed — the band tail prints the opponent tag ("vs DEN" / "vs NE" / "@ KC") and not a result line, which is exactly what SeasonWeekBand.postseasonSlat does when `resultLine` is nil. Yet the rail's "Advance to Divisional Round" is drawn as the FILLED gold primary and the honest footnote "Your game is still unplayed — advancing sims it." is absent beneath it. Per TimelineTasksPanel:708-721 that footnote and the ghost fill are drawn whenever `advanceIsPrimary == false`, so the app believes there is no game on the board.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:250 (weeklyGameUnplayed), :266-277 (performAdvance), :663 (advanceIsPrimary), :598-607 (the only confirm dialog); UI/Common/TimelineTasksPanel.swift:708-721`
  - fix: `advanceIsPrimary: !weeklyGameUnplayed` (CareerDashboardView.swift:663) and `weeklyGameUnplayed` (:250) both read `currentWeekPlayerGame`, which filters the stale `upcomingGames` array — the week-19/20/21 playoff Game rows are created by WeekAdvancer.ensurePlayoffGames after that array was last fetched, so it is always nil in the postseason. Consequence: performAdvance() (:271) skips `showSkipGameConfirm = true` entirely and one tap on gold sims the Wild Card game away with no dialog. Fixing the reload (finding above) restores the guard rail; also worth asserting in a test that the postseason has the confirmation, since it is the one week where losing the coached game ends the season. Note the same stale array makes startCoachedGame() `guard let game = currentWeekPlayerGame else { return }` fall through silently, so Game Plan → Start Game is a dead button in the playoffs too.


### Training camp — practice picker

- [ ] **Q-B09 · The whole Workout Request choice is inert — VoluntaryWorkoutEngine is never called from anywhere**
  - evidence: The modal states "Choose how the team will train this week. Each option has different scheme, locker-room, and injury implications." and prints exact deltas per card ("Scheme +3 / LR +2 / Inj +0%", "Scheme +5 / LR −5 / Inj +2%", "Scheme +1 / LR +0 / Inj +0%"). In code, submit() only inserts a VoluntaryWorkout row (VoluntaryWorkoutPrompt.swift:182-199). Grepping the whole tree for `VoluntaryWorkoutEngine.` returns exactly one hit outside the engine's own file, and it is a doc comment. `apply(workout:roster:modelContext:)` — the function that would grant the scheme bump, the morale delta and the cumulativeLoad/injury risk — has zero call sites. CareerShellView.swift:1583 asserts "engine application is handled by VoluntaryWorkoutEngine on next tick"; no tick ever calls it. Nothing else reads the VoluntaryWorkout model either: the only other references are DynastySchema registration and CareerScope adopt/wipe/audit bookkeeping.
  - code: `dynasty/dynasty/UI/Camp/VoluntaryWorkoutPrompt.swift:182`
  - fix: Call VoluntaryWorkoutEngine.apply from the camp-week advance in WeekAdvancer (fetch unapplied VoluntaryWorkout rows for career+season+week), and stamp an `appliedAt` on the model so it cannot double-apply. Until it is wired, do not present the prompt — an inert modal that quotes numbers is worse than no modal. Add a test asserting a submitted OTA week raises at least one player's schemeFamiliarity.


### Training camp — training plan

- [ ] **Q-B10 · Hub tiles render a stale roster snapshot: "Players 56" sits beside "Cut to 75 (87 currently)" on the same screen**
  - evidence: Left rail: "Cut to 75 (87 currently) · Required" / "Required to advance · Release 12 more players to reach the 75-man limit" (87−75=12, internally consistent). Right-hand ROSTER tile on the same screen: "Players 56". A roster of 56 cannot owe 12 cuts to reach 75. Second, independent proof one minute later: the Hub's KEY PLAYERS says "QB1 Kaleo Hinsdale 53" and POSITION GRADES says "QB S: D / D: — NEED", while camp_09_training_focus_b.png (7.50, no action between) lists "QB Kenji Hopewell OVR 75" on the same roster. `startingQB` is `players.filter { $0.position == .QB }.max(by: overall)`, so a 75 OVR QB on the roster makes "QB1 … 53" impossible from a fresh fetch.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3462-3467 (fetch/rosterCount/startingQB); refresh only at :484-507; advance bypass at :293-296 + CareerShellView.swift:517, 3314-3315`
  - fix: `rosterCount`, `startingQB`, `bestPlayer`, `expiringContractPlayers`, `teamMorale`, `overloadedShare` and `openPositionBattles` are all @State written only by `refreshRosterDerived()`, which runs on `.task` (first open) and on `onAppear` when `hasAppearedOnce` (CareerDashboardView.swift:496-507) — a phase advance that adds a draft class in place, or a full-screen cover dismissing back onto the hub, never re-fires either. Re-derive these from a @Query / observed fetch, or call `refreshRosterDerived()` on `career.currentPhase` and `career.currentWeek` change. Until then the Roster tile is quoting a pre-free-agency roster.


---

## HIGH (143)


### Team picker

- [ ] **Q-H01 · OWNER column ('5yr', '2yr') and CAP column are static ad copy the Generated league never reproduces**
  - evidence: Rows advertise owner tolerance as an icon + years: Jacksonville Tidewater '5yr' (green clock), Baltimore Harbormen '3yr' (blue gauge), Cleveland Forgemen and Las Vegas Highrollers '2yr' (amber warning triangle). Those come from the hardcoded table — LeagueTeamData.swift:83 is literally `"BAL": TeamPreview(difficulty: 3, ..., ownerPatience: "Moderate", patienceSeasons: 3, ..., estimatedCapSpace: 15, ...)`. `patienceSeasons` is read ONLY by this view (TeamSelectionView.swift:1021, 1469, 1824); no engine code consumes it. The owner the career actually gets is built with `patience: Int.random(in: 2...9, using: &rng)` and `prefersWinNow: Bool.random(using: &rng)` (LeagueGenerator.swift:588, 591), and the in-career Owner Briefing then reports "Results within \(owner.patience) season(s)" (OwnerBriefing.swift:562) — a number with no relation to the '5yr' that sold the job. The generator's ONLY reads of the preview table are lastSeasonWins (lines 403-406, draft order), spendingWillingness (578), coachingBudget (582) and startingQBName/Overall (620-621); `estimatedCapSpace` and `ownerPatience` are never read, and there is no per-team payroll target in generateRoster. DIFFICULTY stars are baselined on the same unused ownerPatience string (TeamBrowseCatalog.swift:212-235), so every pressure signal on this screen is decorative.
  - code: `dynasty/dynasty/Data/Import/LeagueGenerator.swift:638`
  - fix: At career creation, write the picker's numbers into the world: set `owner.patience` from `preview.patienceSeasons` (and `prefersWinNow` from the ownerPatience string) instead of `Int.random(in: 2...9)`, and give generateRoster a per-team payroll target derived from `estimatedCapSpace`. If that wiring is out of scope, delete the OWNER and CAP columns rather than shipping numbers the engine contradicts on day one.

- [ ] **Q-H02 · Portrait iPad takes the landscape two-column branch — 43.8% of the screen is empty background**
  - evidence: Screenshot is 2064x2752 portrait = 1032pt wide. `private var isLandscape: Bool { viewWidth > 900 }` (TeamSelectionView.swift:85), so a 13" iPad in PORTRAIT satisfies it and the view takes the `if isLandscape` two-column LazyVGrid branch (line 169) instead of the single-column VStack written for portrait (line 187). Result: all 16 AFC teams fit in the top 56% — measured, the last row of non-background pixels is y=1547 of 2752, leaving 1205px (43.8%) of flat #0B1222 below the 'Highrollers / Currents' row, with no content, no summary, no CTA.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:85`
  - fix: Stop inferring orientation from a width threshold — use the real interface orientation or a size class, or raise the breakpoint above 1032pt. Then spend the reclaimed 1205px: a single-column list with roster OVR, cap, staff and owner on one line, or keep two columns and fill the tail with a league-average strip and a persistent 'Take this job' summary for the highlighted team.


### Team detail

- [ ] **Q-H03 · Team detail renders its LANDSCAPE two-column layout on a portrait iPad — bottom 40% of the screen is empty**
  - evidence: The cards are laid out two-up ("OWNER EXPECTATIONS" beside "MARKET & MEDIA", "COACHING BUDGET" beside "DIVISION RIVALS"), the content column measures ~850pt wide (wideMeasure 900 − 48pt padding; the portrait branch caps at 600), the logo is ~56pt and "Houston Astronauts" is set at title2/22 (the portrait branch specifies 72pt and title1/28). Everything ends at the rivals row "TEN Tennessee Cumberlands 3-14 / 69 OVR / REBUILDING", leaving ~560pt of bare background between it and the "STARTING THIS CAREER … SELECT THIS TEAM" bar.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:1276 (isLandscape = viewWidth > 900), :1693 landscapeDetailContent, :1671 portraitDetailContent`
  - fix: `isLandscape` is `viewWidth > 900`; an iPad Pro 13" in PORTRAIT is 1032pt wide, so a full-screen cover always takes the landscape branch. Gate the two-column grid on the aspect ratio (or on `verticalSizeClass == .compact`), not on width alone — or keep the grid but let it fill: give `landscapeDetailContent` a `frame(minHeight:)` from the container and distribute the slack, so a portrait iPad does not pay 40% of its screen for nothing. Note the same `viewWidth > 900` line exists at TeamSelectionView.swift:85 for the list screen.


### Intro — session result

- [ ] **Q-H04 · WHAT CHANGED silently drops MEDIA (-21) and adds LEGACY, which the session strip never tracked — the two ledgers do not agree**
  - evidence: 010 and 011 track four meters in RUNNING IMPACT: "OWNER +4 / MORALE +4 / FANS -2 / MEDIA -7" then "OWNER +18 / MORALE +15 / FANS -11 / MEDIA -21". 012's WHAT CHANGED card shows a different four: "OWNER +18, MORALE +15, FANS -11, LEGACY +15". MEDIA — the largest single delta of the session and the meter named in the headline right above — is not on the card, and LEGACY +15 appears for the first time with no running counterpart. The action-bar cost line repeats the omission: "5 answers · moved the owner +18 · +15 legacy · no promises on the ledger." Code: `summaryChanged`'s `cells` array is literally `[Owner, Morale, Fans, Legacy]` with no media entry (PressConferenceView.swift:1317-1325), and `summaryCostLine` builds only owner/legacy/promise parts (:1493-1507), while `buildResult` sums the same `resolvedEffects` as `runningTotals`, so `result.totalEffects.mediaPerception` is exactly the -21 that was on screen a moment ago.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1317`
  - fix: Make WHAT CHANGED a five-cell grid (Owner, Morale, Fans, Media, Legacy) so it is a superset of RUNNING IMPACT, give Media the `0 → -21` baseline line and its band name ("Scrutinized"), and add the media term to `summaryCostLine`.


### Intro — owner briefing

- [ ] **Q-H05 · Owner badge says "PATIENT BUILDER" directly above "Philosophy: Win Now" and "Patience 4/10"**
  - evidence: Header chip: "PATIENT BUILDER". First priority row: "Philosophy — Win Now" with "Prioritizes free agency spending and expects playoff contention. Veterans are favored over draft-and-develop." Patience card: "4/10 PATIENCE" and "The owner wants results sooner rather than later. Missing the playoffs repeatedly will cost you." The one-glance identity label contradicts every number under it.
  - code: `dynasty/dynasty/Engine/Media/OwnerPersonaEngine.swift:29`
  - fix: OwnerArchetype.from() only returns .winNowTycoon when prefersWinNow && spendingWillingness >= 55, so any win-now owner at 36–54 spending falls through to the .patientBuilder default. Either add an explicit win-now branch that ignores the wallet (prefersWinNow && patience <= 5 → .winNowTycoon) or rename the fallback to something that does not assert patience (e.g. "Steady Hand"), and add a test asserting archetype never contradicts prefersWinNow.

- [ ] **Q-H06 · The same patience value 4 is called "About average… steady progress" and "wants results sooner rather than later" on one screen**
  - evidence: Priorities row: "League avg: 5 seasons — About average patience. Steady progress expected each year." Owner Patience card, ~450px below on the same screen: "The owner wants results sooner rather than later. Missing the playoffs repeatedly will cost you." Both are rendered from owner.patience == 4.
  - code: `dynasty/dynasty/UI/News/OwnerBriefing.swift:128 vs :215`
  - fix: patienceImplication() bands on `< leagueAvg - 1` (so 4 is "about average") and case 4...6 ("steady progress"), while patienceDescription() bands on `>= 4` ("results sooner rather than later"). Both live in OwnerBriefingCopy — collapse them onto one band table (lines 128–142 and 215–220) so a given patience integer produces one verdict.

- [ ] **Q-H07 · Spending row headline "Willing to Spend" contradicts its own explainer "Modest spending — be strategic with signings"**
  - evidence: One row, two halves: value "Willing to Spend" (blue) and directly beneath it "↳ Budget: $47.0M (league avg: $38.0M). Modest spending — be strategic with signings." A $47.0M budget is also 24% ABOVE the $38.0M league average it is compared to, while being called modest.
  - code: `dynasty/dynasty/UI/News/OwnerBriefing.swift:106 vs :147`
  - fix: spendingLabel() breaks at 25/50/75 and budgetImplication() breaks at 30/60, so every owner with spendingWillingness 50–60 gets "Willing to Spend" + "Modest spending". Use one shared band boundary set for the label and the tail.

- [ ] **Q-H08 · "SEASONS BEFORE REVIEW" is computed from a firing counter, so it can never count down**
  - evidence: The Owner Patience card shows three columns: "4/10 PATIENCE", "4 SEASONS BEFORE REVIEW", "2026 CURRENT SEASON" — and the priorities row says "Results within 4 seasons". The same 4 is printed three times in three different units, and the middle one is labelled as a countdown.
  - code: `dynasty/dynasty/UI/News/OwnerBriefing.swift:615`
  - fix: seasonsBeforeReview = max(0, owner.patience - career.yearsFired); career.yearsFired is incremented only when the coach is actually fired (CareerShellView.swift:1529, which also sets career.isGameOver = true). It therefore stays at the owner's patience value for the entire tenure. Base the countdown on seasons elapsed since hire (career.currentSeason - hire season) instead.

- [ ] **Q-H09 · The primary goal shown as "Win the Championship" is graded by the engine as a conference-final (11-win) expectation**
  - evidence: Season Goals card: "Win the Championship — PRIMARY"; the action bar underneath states "This is the bar you are measured against. It does not change because you disagree with it." With this roster (average overall 70, owner prefersWinNow) the stored goal is SeasonGoals(primaryGoal: "Win the Championship", ownerExpectation: .conference), and .conference is evaluated as 11 expected wins.
  - code: `dynasty/dynasty/Domain/Models/League/SeasonGoals.swift:41 + LeagueNarrativeEngine.swift:906`
  - fix: SeasonGoals.generate() pairs the championship string with .conference for the 70..<80 win-now branch, and LeagueNarrativeEngine.swift:903-911 grades against ownerExpectation, not against the string. Either show the expectation the engine actually uses ("Reach the Conference Championship — 11 wins expected") or set ownerExpectation to .superBowl for that branch. Displaying the win target next to the goal would make the bar checkable.


### Intro — team overview

- [ ] **Q-H10 · Special teams shows a red "D: F" depth grade on a fully-stocked unit that the same card marks green "2/2 players"**
  - evidence: The ST card reads "S: B- / D: F", "ST", "73 OVR", "2/2 players" — the player count is green (meets ideal) and the depth grade is a red F on the same card. No other card has an F.
  - code: `dynasty/dynasty/UI/Roster/RosterView.swift:1647`
  - fix: calculatePositionGrades() does `let dGrade = backups.isEmpty ? "F" : letterGrade(for: depthAvg)`, and ST's starter count is K:1 + P:1 = 2 (RosterView.swift:1554-1560). Any team carrying exactly one kicker and one punter — i.e. every team — gets a permanent red F. Render "—" (or hide the depth grade) when there are no backups instead of grading an empty set as failing.

- [ ] **Q-H11 · "Average Overall 70" is lower than every one of the nine position groups, and nothing on screen says the group numbers are starters-only**
  - evidence: Roster card: "Average Overall 70 (Avg: 72)" with a red down arrow. The nine group cards below read 86, 72, 81, 73, 80, 75, 81, 78, 73 OVR — all ≥ 72, and their player counts (3+4+7+3+9+8+7+10+2) sum to exactly the 53 on the roster. As drawn, the numbers are arithmetically impossible. The QB card is the sharpest case: "86 OVR" sits directly above "3/3 players", but 86 is one quarterback's rating, not the average of three.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:656 vs :331`
  - fix: Group OVR is grades.starterOVR — the top-N-by-overall average (RosterView.swift:1639-1643) — while Average Overall is the whole 53-man mean. Label the group figure "STARTERS 86" (and show the depth average next to the D grade), or add a one-line legend to the card head. A hardcore player cannot use these grades until they know what N is per group.


### Intro — roadmap

- [ ] **Q-H12 · Roadmap screen leaves the bottom ~40% of a portrait iPad empty**
  - evidence: The "YOUR FIRST TASKS" card ends at roughly 55% of the screen height; below it there is nothing but the darkened background photo until the "Continue" pill at the very bottom — about 1,090 px of 2,752 with no content, on the screen that is supposed to sell the shape of the whole offseason.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:970-1027 (tasksCard :959)`
  - fix: The step is two cards plus a fixed 80pt spacer in a ScrollView with no minHeight. Fill the space with what the player is about to need: the phase descriptions that are currently hidden for the 9 non-current entries, a "what you can and cannot undo" note, or the roster/cap headline from the previous step so the roadmap is anchored to this team.


### Career hub

- [ ] **Q-H13 · The staff blocker is printed twice, word for word, in the same left rail**
  - evidence: The rail shows "Fill your required staff first / Offensive Coordinator, Defensive Coordinator are still vacant. Hire from the Staff screen to advance." at the top (under the DEBUG bar), and then the identical two sentences again below the task list, between "1 more required task after it." and the "Advance to Review Roster" button. Same octagon icon, same red title, same detail sentence, ~700px apart in one scroll.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3036 + :652-665; dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:636-645`
  - fix: Pick one host. `coachingBudgetBlockerBanner` (CareerDashboardView.swift:3035, mounted at :656) and `TimelineTasksPanel.advanceSection` (:637-644) both render `advanceBlocker.title` + `.detail`. The panel's copy sits directly above the disabled button it explains, so delete the top banner and stop passing `advanceBlocker` twice — or keep the top banner and drop the panel block.

- [ ] **Q-H14 · TEAM card prints "#4" as a division rank when every team in the division is 0-0 — the number is a tiebreak artifact**
  - evidence: TEAM tile: "Houston Astronauts / 0-0   #4". No games have been played (record 0-0, no Previous Season tile rendered), so all four AFC South teams are 0-0-0 and `nflTiebreaker` has nothing to separate them; the rank falls out of array order. Identical "0-0  #4" on 025. The rank also carries no label — nothing on the card says "#4" means division position rather than power ranking, seed, or draft slot.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3324-3341 + :1931 (vs :3214-3218); dynasty/dynasty/Engine/Simulation/StandingsCalculator.swift:193-215`
  - fix: `teamTile` (:1931) reads `divisionRank` (:3324) unconditionally, but this same view already has `isPreSeasonNoGamesPlayed` (:3215) and uses it to suppress the all-0-0 standings panel. Gate the rank badge on the same predicate, and in its place show the club's last-season result — `LeagueTeamData` already carries `lastSeasonWins: 10, lastSeasonLosses: 7` for HOU.


### Cap tab

- [ ] **Q-H15 · Year 2027 renders as "2 027" — the section header runs the year through the locale number formatter**
  - evidence: The section label reads "CARRIED INTO 2 027" (a grouping space between the 2 and the 027), while every other year on the same screen is correct: "THIS YEAR (2026)", "NEXT YEAR (2027)", and the Cap Outlook rows "2026 / 2027 / 2028".
  - code: `dynasty/dynasty/UI/Contracts/CapOverviewView.swift:726`
  - fix: `Text("CARRIED INTO \(nextSeason)")` uses SwiftUI's LocalizedStringKey interpolation, which formats an Int with the device locale's grouping separator (this sim is on a fi/EU locale — see "14.26", "Mon 24. Aug", "100 %"). The file already solves this everywhere else: `seasonLabel(yearOffset:)` returns `"\(openYear + yearOffset)"` as a String, and the two correct headers build the year into a String literal first. Change line 726 to `Text("CARRIED INTO " + seasonLabel(yearOffset: 1))` (or `String(nextSeason)`). Worth a grep for any other `Text("…\(someYearInt)")` in the app — the bug only shows on 4-digit numbers, so it hides in testing.


### Draft tab

- [ ] **Q-H16 · 55% of a portrait iPad is empty — the Draft tab ends at "2030 / 7 picks" and shows nothing below**
  - evidence: Last painted content is the 2030 capital card ("2030 · R1 R2 R3 R4 R5 R6 R7 · 7 picks") ending at roughly 46% of the 2064×2752 screen. Everything from there to the bottom bezel is flat `backgroundPrimary`. The four capital cards are also mutually identical — same seven chips, same "7 picks" — so the screen spends its top half restating one fact ("you own all your own picks") and its bottom half saying nothing.
  - code: `dynasty/dynasty/UI/Draft/DraftRecapView.swift:273`
  - fix: Collapse the four identical years into one "You hold all 28 of your own picks, 2027–2030" summary line with per-year rows only where capital differs from baseline, then fill the reclaimed half with what a player standing here actually needs: class-strength read, top-5 of your own board, position needs vs class depth, and last year's draft results.


### Scouting / big board

- [ ] **Q-H17 · OVR values sit under no column — the header label and every row's badge land at a different x**
  - evidence: The header "OVR ⓘ" prints immediately right of "NAME" at roughly x=352 (of 1500). The grade badges print far right of it and never twice in the same place: "B+/A+" (Jamari Crisanti) ≈ x=558, "B/A+" (Wilkes Kirkbride) ≈ x=568, "B/A+" (Jamari Goddard) ≈ x=625, "A-/A+" (Kenji Shelburne) ≈ x=670, "B/A+" (Xander Hubbell) ≈ x=685. The badge x tracks the length of the sub-line, so a long comparison ("vs Barrett Brockway: +18 O…", itself truncated) pushes the grade right and a short one ("Depth add (-4 OVR)") pulls it left. The one number the board is sorted on cannot be scanned down a column.
  - code: `dynasty/dynasty/UI/Common/DSListRow.swift:620`
  - fix: The header and the row both use `.frame(minWidth: DSListColumn.identityMin)` on an intrinsically-sized identity block, so the two never agree. Give the identity slot a resolved width (`.frame(maxWidth: .infinity)` in both header and row, or a fixed identity column) so the OVR badge starts at a constant offset, and truncate the comparison line inside it.

- [ ] **Q-H18 · Big Board auto-opens the Physical lens before any combine has been held — 7 columns × 350 rows of "—"**
  - evidence: All 16 visible rows print the identical empty combine strip: "— 40YD  — BENCH  — VERT  — BROAD  — 3CONE  — SHUT  — DRILL". That block is ~45% of every row's width and carries zero information. The screen's own subtitle contradicts the lens choice: "BIG BOARD / 0 of 350 filed on · 0% scouted · Coaching Changes" — the phase is Coaching Changes, the combine has not been simulated, so no prospect has a 40 time. The "Physical" chip is nonetheless the selected (blue) lens.
  - code: `dynasty/dynasty/UI/Scouting/BigBoardView.swift:1511`
  - fix: Gate `defaultAttributeTab` on data existence, not only on the prep pointer: return `.physical` only when at least one prospect has a non-nil measurement (e.g. `prospects.contains { $0.fortyTime != nil }`), otherwise fall through to `.overview`. Optionally dim the Physical chip and label it "Physical — after the combine" until measurements land.

- [ ] **Q-H19 · Fog leak: an exact "+18 OVR" delta prints six pixels from the fogged "A-/A+" band for the same man**
  - evidence: Kenji Shelburne's OVR cell shows the uncertainty band "A-/A+" while the line under his name reads "vs Barrett Brockway: +18 O…". Same pattern on every row: Boone Engelhardt "B/A+" / "vs Roman Frobisher: +17 OVR"; Jamari Goddard "B/A+" / "vs Rafferty Larrabee: +2 OVR"; Xander Hubbell "B/A+" / "vs Barrett Brockway: +8 OVR". The header says "0 of 350 filed on · 0% scouted", so nothing has been paid for — yet the exact integer overall is recoverable by adding the delta to the starter's OVR, which the Roster screen prints in the clear. The band is decoration.
  - code: `dynasty/dynasty/UI/Scouting/BigBoardView.swift:2258`
  - fix: `starterComparison` must read the same fogged value the badge does (`ProspectFog` band midpoint / band-vs-starter verdict), not raw `scoutedOverall`. Print a qualitative read — "Upgrade on Brockway" / "Depth" / "Lateral" — and only reveal the signed integer once the club has filed enough reports to collapse the band.

- [ ] **Q-H20 · Tier header's "(76%)" is not the percentage of the "11/17" it is glued to**
  - evidence: The Blue Chip header reads "% 11/17 avail @#19 (76%)". 11/17 is 64.7%, not 76%. The two numbers are different statistics rendered as if one explained the other: the count is prospects whose individual availability probability is ≥ 0.5, the percentage is the arithmetic mean probability across all 17.
  - code: `dynasty/dynasty/UI/Scouting/BigBoardView.swift:1853`
  - fix: Split them or label them. Either print "11 of 17 likely available at #19" and move the mean into the tooltip, or render "avg 76% available at #19 · 11 of 17 better than a coin flip". Never put a fraction and an unrelated percentage inside one parenthetical.


### Staff tab

- [ ] **Q-H21 · Auto-Hire promises "the best affordable candidate" but hard-caps every offer at the average asking price — it plans to leave $33.8M of $47.0M unspent, and unspent budget is destroyed at the season roll**
  - evidence: The primary CTA reads "Auto-Hire Recommended Staff / Fills all 23 vacant roles with the best affordable candidate who fits your staff. / Spends ~$13.2M of $47.0M coaching · ~$1.7M of $2.8M medical · ~$4.1M of $4.1M scouting". The same card sits under "Coaching Budget / Used $0.0M of $47.0M / $47.0M remaining / Above league avg (~$35M)". So the screen's one headline advantage — an above-average coaching pot — is 72% unused by the recommended path.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:617-650, :715-717, :3456`
  - fix: In `autoHireAllocations` the comfortable branch is `if totalAvg <= available { result[job.id] = band.avg }`, and each hire is then capped at `min(wallet, allocation)`. With a fat pot the pass never offers above the going rate, so "best affordable" is really "best at or under the average asking price". Nothing recovers the surplus either: `WeekAdvancer.swift:1064-65` overwrites `owner.coachingBudget` from `BudgetEngine.calculateBudget` each season, so the leftover simply vanishes. Either (a) spread the surplus upward — scale allocations toward `band.max` when `available > totalAvg`, which turns a rich owner into a real advantage and makes the budget a live trade-off; or (b) keep the conservative plan but tell the truth in the subtitle ("best candidate at the going rate — leaves $33.8M unspent, which does not carry over"). Reference: FM's staff-hiring screen shows wage budget remaining and lets you break the recommendation deliberately; Madden's staff points are all-or-nothing precisely so none are wasted.


### Trades tab

- [ ] **Q-H22 · Pick Trade Simulator lists your picks in a scrambled year order (2029, 2030, 2028, 2027, 2030, 2028, 2029, 2027)**
  - evidence: The "Your Pick" row reads left to right: "2029 1st 360 pts | 2030 1st 216 pts | 2028 1st 600 pts | 2027 1st (#19) 875 pts | 2030 2nd 91 pts | 2028 2nd 252 pts | 2029 2nd 151 pts | 2027 2nd 390 p[ts]". Neither the years nor the values are monotonic. Cause: `myPicks` sorts on `pickNumber` alone, and every future pick is minted at the round midpoint `round × 32 − 16` (so all three future 1sts share pickNumber 16 and tie-break arbitrarily, landing before the real 2027 #19).
  - code: `dynasty/dynasty/UI/Contracts/TradeView.swift:2258`
  - fix: Sort `myPicks` by `(seasonYear, round, pickNumber)`. The same array feeds the Propose Trade asset list at TradeView.swift:372, so one fix corrects both.


### Coaching staff

- [ ] **Q-H23 · Staff screen promises "+12% offensive efficiency" for the OC seat; the best candidate's own profile projects -0.1%**
  - evidence: 015: "Offensive Coordinator [High Priority] / Vacant — Tap to hire / ~$0.8-9.5M/yr / 📈 +12% offensive efficiency". 017, for the #1 / "Best Available" candidate for that exact seat: "Expected offensive boost: -0.1% efficiency" and "Offensive efficiency +0.5%". Three numbers for one purchase spanning -0.1% to +12%.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:1189; caps at CoachingModifiers.swift:43-46; clamp at HireCoachView.swift:1413`
  - fix: `hiringImpactDescription` returns a hardcoded candidate-independent constant per role. Either label it as the ceiling ("up to +12% with an elite OC") or compute it from the pool actually on offer, so the promise on the vacancy row and the projection on the profile can never differ by 12 points.


### Hire list

- [ ] **Q-H24 · Hire list opens as a default iPad form sheet using ~26% of a 13-inch portrait screen, truncating its own filter chip**
  - evidence: The "Hire Offensive Coordinator" panel spans roughly x330–1172, y540–1470 of a 1500x2000 frame (~580x640pt of a 1032x1376pt screen). The personality filter renders as "Perso…", 8 of 30 candidates fit before the panel clips a 9th row mid-name, and the entire Coaching Staff screen behind it is dimmed and unusable. The detail sheet one tap deeper (017) is full-screen, so the same flow uses two different presentation sizes.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:1343 vs dynasty/dynasty/UI/Staff/HireCoachView.swift:384; chip label at :482-485`
  - fix: Present the hire list with .presentationSizing(.page) or a fullScreenCover, matching the detail sheet the code already comments as "#157: Full screen cover on iPad for max space". That alone fixes the clipped columns and the "Perso…" chip.

- [ ] **Q-H25 · Salary, Game and Val columns sit off the right edge of the hire sheet with scroll indicators disabled**
  - evidence: The header reads "Budget Remaining $47.0M" and offers an "Affordable" toggle, yet the rightmost visible column is "Dev" — no salary is shown for any of the 30 candidates. The only hint that more columns exist is a stray gold dot at the sheet's right edge (x≈1165), which is the role-highlight dot belonging to the clipped "Game" header.
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:313, :337, :630-679`
  - fix: Row is Name(min 160)+Age 34+Scheme 70+OVR 36+Play 36+Dev 36+Game 36+Salary 56+Val 40+Status 64 ≈ 780pt inside a ~580pt form sheet. Widen the sheet (see the sizing finding), or drop Game/Val from the list and pin Salary next to OVR — a hire list gated on a budget must never scroll salary out of view. At minimum set showsIndicators: true.


### Candidate profile

- [ ] **Q-H26 · Two cards on the same profile give opposite-signed offensive-efficiency projections for the same hire**
  - evidence: Left column, stacked one above the other: "PROJECTED CONTRIBUTION — Offensive efficiency +0.5%" (green, upward icon) and directly beneath it "PROJECTED IMPACT — Expected offensive boost: -0.1% efficiency" (red). The same pair disagrees on development too: "Unit development +0.2% / season" vs "Player Dev: +1.1%". Both cards claim to be measured against league average ("Estimates based on attribute deltas vs. league average." / "Compared to league average (65 rating)").
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:1408-1418 vs :1987-2022; both mounted at :1651/:1653`
  - fix: Delete one card. `projectedImpactCard` computes efficiency as ((playCalling+gamePlanning)/2 - 65) * 0.05 = +0.45; `positionGroupImpactCard` computes ((playCalling-65)*0.15 + (playerDevelopment-65)*0.15)/2 = -0.15. Keep a single formula, derive it from the attributes the sim actually reads (playCalling, adaptability, gamePlanning, scheme expertise), and show one number with a breakdown row.

- [ ] **Q-H27 · The screen's only primary action, "Offer Contract", is below the fold on a 13-inch iPad in portrait**
  - evidence: The visible page ends at "Contract Length 3 years / − + / Standard deal: good balance of cost and stability" at the very bottom edge. Nothing on screen says "hire" — the gold 56pt "Offer Contract" button is the last element of the third card in the right column, inside the page's ScrollView, with no pinned action bar.
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:2489-2513, mounted via negotiationCard at :1666; no safeAreaInset in file`
  - fix: Pin the Offer Contract button in a .safeAreaInset(edge: .bottom) bar carrying salary, years and "Budget after: $40.4M", so the commit action is on screen from the moment the profile opens.

- [ ] **Q-H28 · "Ranked #1 / Best Available" is an unweighted 12-attribute mean; the sim grades an OC on playCalling+adaptability, both of which are red here**
  - evidence: Finnian Balfour is "Ranked #1 of 30 candidates" with the gold "Best Available" badge and OVR 71 — while his ATTRIBUTES card shows "Play Calling Avg 56" and "Adaptability Below 54". The 71 is carried by Game Planning 92, Reputation 88, Morale Influence 83, Discipline 83, Motivation 81. The screen even flags the mismatch itself ("Play Calling: -1.3%") and the list highlights "•Play" with a gold role dot. Adaptability is not a column in the list at all.
  - code: `dynasty/dynasty/Engine/Simulation/CoachingModifiers.swift:120 vs dynasty/dynasty/UI/Staff/HireCoachView.swift:1286, :1080, :1701`
  - fix: Rank coordinators by the number the sim uses. Either replace OVR in the hire list with a role-weighted grade, or keep OVR and add an "OC Grade" column sorted by (playCalling+adaptability)/2 plus own-scheme expertise. Add Adaptability as a list column for coordinator hires since it is half the engine's input.


### Hire result sheet

- [ ] **Q-H29 · Result sheet is ~46% of the screen tall with a ~350pt empty band between the chips and the cost bar**
  - evidence: On 019/020 the modal card runs from y≈535 to y≈1465 of 2000, but its content stops at the WHAT CHANGED grid (bottom edge y≈858) and nothing else appears until the "WHAT IT COST" bar starts at y≈1368 — ~510 display px (~350pt) of pure void inside the card. 022 is identical: content ends after "HIRED 22 / SPENT $19.5M / STILL OPEN 0 / CLASHES 0" and the next pixel of content is "Leaves $26.5M coaching…" 500px lower.
  - code: `dynasty/dynasty/UI/Common/DSResultSheet.swift:103 (ScrollView fills); dynasty/dynasty/UI/Staff/CoachingStaffView.swift:1343 (.sheet with no detents/presentationSizing)`
  - fix: The sheet is a bare `.sheet` (CoachingStaffView.swift:1343) with no `.presentationDetents` / `.presentationSizing(.fitted)`, so the iPad form sheet takes its fixed size from the largest face (the hire list) and DSResultSheet's `ScrollView` stretches to fill it. Either add `.presentationSizing(.fitted)` on the result face, or earn the space: put the hired man's card (rating, fit badge, contract years) or the next open job in it.


### Staff after auto-hire

- [ ] **Q-H30 · Auto-Hire promised "~$10.8M of $47.0M" coaching and spent $13.9M — 29% over its own estimate**
  - evidence: 019 shows the Auto-Hire card reading "Fills all 22 vacant roles w… / Spends ~$10.8M of $47.0M" with "Coaching Budget Used $6.6M of $47.0M". 022, after the same 22 hires ("HIRED 22 of 22 jobs"), shows "Coaching Budget Used $20.5M of $47.0M" — $13.9M of coaching spend against a ~$10.8M projection, and a $19.5M headline total.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:757 (second-pass cap ignores the projection); projection at CoachingStaffView.swift:653-670; CoachRole.swift:108 salary bands; StaffLedger.swift:118`
  - fix: The subtitle sums `autoHireAllocations` (CoachingStaffView.swift:654-669), and the first pass is capped by that allocation so it can never exceed it. The second pass at line 757 caps on `min(walletLeft, max(band.avg, fairShare))` — the whole remaining pot, not the plan — so it is structurally free to blow past the number the button advertised. Either cap the retry at the projection, or make the subtitle a range/upper bound ("up to $X") derived from the same wallet logic the retry uses.


### Career hub (offseason)

- [ ] **Q-H31 · STAFF card uses "N / M" for two opposite meanings four points apart — Budget is money LEFT, not money spent**
  - evidence: The card reads "23 / 23 Staff" (filled of total) and immediately under it "Budget  $26.5M / $47.0M". The second pair is remaining/total: actual spend is $20.5M. On 013 the same row reads "$47.0M / $47.0M" with 0 of 23 staff hired — i.e. nothing spent, rendered as a maxed-out-looking fraction. The label is the bare word "Budget" with no "left"/"remaining".
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2073-2091 (vs :2032-2040)`
  - fix: `staffTile` prints `StaffLedger.money(remaining)` then `/` then `coachingBudget`. Label it "Budget left" and/or invert to spent-of-total so both fractions in the card fill in the same direction. At minimum change the separator so it does not mimic the slot counter above it (e.g. "$26.5M left of $47.0M").


### Coaching staff review sheet

- [ ] **Q-H32 · The rail's task instructions are clipped at exactly the actionable half — "…then confirm the review on..." loses the tab name**
  - evidence: Left rail, under "Review coaching staff": "Optional · Evaluate your coordinators and position coaches, then confirm the review on..." — the string in TaskGenerator.swift:770 ends "…confirm the review on the Review tab." Under "Review coordinator scheme[s]": "Optional · Check offensive and defensive scheme fit with yo…" — the full string (TaskGenerator.swift:779) ends "…then confirm the review on the Schemes tab." Both descriptions exist solely to name which tab closes the task, and both lose exactly that clause. Cause: `detailLine(...)` is rendered at `.font(.system(size: 10))` with `.lineLimit(2)` inside a rail hard-framed at `.frame(width: 300)` (CareerDashboardView.swift:669), sharing that line with a secondary-action chip via `Spacer(minLength: 2)`.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:446`
  - fix: Raise to `.lineLimit(3)` for the two rows that carry a destination instruction, or shorten the generated strings to lead with the tab ("Confirm on the Review tab · evaluate coordinators and position coaches") so the clipped half is the expendable half.


### Career hub (review roster)

- [ ] **Q-H33 · Hub "Position Grades" tile and Roster Evaluation disagree on RB depth: D: C vs D: F, 60 seconds apart**
  - evidence: 029 (14.34) POSITION GRADES tile: "RB  S: B- / D: C  [NEED]". 031 (14.35) Roster Evaluation table: "RB  79  S: B- / D: F". Every other shared group matches exactly (QB C, WR C+, TE C+, OL C, DL C-, LB C+), so it is not a rounding difference. Both screens call the identical PositionGradeCalculator on the identical group [.RB, .FB] with scheme nil, so with the same roster the letters cannot differ — the hub's copy is a stale snapshot: loadAllData() (which fills `players` and `positionGroupGrades`) runs only in `.task`, and the re-appear path deliberately runs `refreshStaffTile()` only ("the ONLY work the .onAppear re-entry path runs").
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:496 (onAppear → refreshStaffTile only); 3444-3486 (loadAllDataBody writes players/rosterCount/positionGroupGrades); 3612 vs dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:363 (identical calculator call); dynasty/dynasty/UI/Career/CareerShellView.swift:1375,1522 (shell advance never reloads the dashboard)`
  - fix: Extract a cheap `refreshRosterDerived()` (players fetch + positionGroupGrades + expiring + morale) and call it from `.onAppear` alongside `refreshStaffTile()`, or invalidate the snapshot on `career.currentPhase` / roster-version change. The full two-season game refetch can stay behind `.task`.


### Roster evaluation

- [ ] **Q-H34 · "Declining output relative to cost" is emitted without ever looking at cost — $950K and $5.3M get the identical line**
  - evidence: On 030/032: "Kenji Cunliffe Age 28 EXPIRING — Declining output relative to cost. Consider letting him walk." at 60 OVR / $950K, and "Zavier Braithwaite Age 32 EXPIRING — Declining output relative to cost. Consider letting him walk." at 72 OVR / $5.3M. A $950K deal is roughly league minimum and cannot be a cost problem. In code, `expiringRecommendation(player:marketValue:)` takes `marketValue` as a parameter and its body never references it, nor `player.annualSalary` — every branch keys off `player.overall` and `isPastPeak` only. Eight rows on this screen carry cost-flavoured copy ("relative to cost", "at or slightly above market") that no cost input produced.
  - code: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:2201`
  - fix: Either use the `marketValue` already computed at line 2129 in the branch conditions (compare salary to marketValue before saying "relative to cost"), or drop the cost clause and say what is actually modelled: "Past peak at 32 — production is falling." A $950K player past peak should read "Cheap depth — re-sign at the minimum", not "let him walk".

- [ ] **Q-H35 · Franchise-tag advice fires only for 65-69 OVR players and never for the star — it is recommended for a 67 OVR WR whose current deal is below the tag floor**
  - evidence: On 030/032: "Zavier Hambleton WR Age 29 EXPIRING — Franchise tag is an option to buy time before committing long-term." at 67 OVR / $4.0M. The 94 OVR WR on the same list (Wade Braithwaite, $37.4M) gets no tag mention at all. In code the tag line is the final `else` of `expiringRecommendation`, reachable only when overall is 65..<70 and the player is not past peak — structurally it can never fire for an elite player. Meanwhile ContractEngine.franchiseTagValue is "the average of the top 5 salaries for that position group" with a floor of `franchiseTagFloorShare` = 5,000/265,000 of the cap; screen 027 shows the cap as $265.0M, so the WR tag costs at least $5.0M and realistically an average that includes the $37.4M row on this very screen. The app is recommending a raise on a 67 OVR backup.
  - code: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:2211`
  - fix: Invert the condition: offer the tag to high-OVR expiring players the club cannot afford to extend this year (overall >= 80 and cap space < projected extension), and show the computed tag number inline ("Tag: $31.2M") so the trade-off is visible. Never surface it for a player whose current salary is below the tag floor.


### Tasks panel

- [ ] **Q-H36 · Two different position-group taxonomies: hub grades CB and S, Roster Evaluation grades DB and ST**
  - evidence: 029 POSITION GRADES lists QB RB WR TE OL DL LB **CB** (S: B+ / D: C+) **S** (S: B- / D: B-) — no special teams row at all. 031 Roster Evaluation lists QB RB WR TE OL DL LB **DB** (S: B / D: C) **ST** (77, S: B-, "Depth needed") and says "Priorities set: 0/9 position groups". The K/P room flagged "Depth needed" on the priorities screen is invisible on the hub, and the hub's safety grade (B-) cannot be reconciled with the eval screen's merged DB grade (B).
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3596-3604 (hub 9 groups: CB, S, no K/P), 1282-1287 (Team Needs reads the same array); dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:11-21 (DB, ST); dynasty/dynasty/UI/Career/IntroSequenceView.swift:335-337; dynasty/dynasty/UI/Roster/RosterView.swift:228-232`
  - fix: Delete the private group table in CareerDashboardView.calculatePositionGroupGrades and read EvalPositionGroup.allGroups (the list the priorities counter, draft board and scouting focus already use). One taxonomy, nine groups, everywhere.


### Franchise tag

- [ ] **Q-H37 · Franchise tag has no 120%-of-prior-salary floor, so tagging the best player on the list is a pay cut he silently accepts**
  - evidence: Row 1: "Wade Braithwaite / WR / Age 30  94 OVR  $37.4M/yr" with "$26.0M / Tag Cost" and the advice "Elite player — strongly consider tagging." The tag prices a 94 OVR receiver $11.4M BELOW what he is already earning. franchiseTagValue is the bare mean of the top five positional salaries with only a 1.9%-of-cap floor — no max(top-5 avg, 120% of prior salary), no consecutive-tag escalator. The only cost applyFranchiseTag charges is `player.morale -= 10`, fully refunded by removeFranchiseTag. Meanwhile the alternative the same row offers, Contact Agent, opens at $46.0M–$56.0M/yr (036).
  - code: `dynasty/dynasty/Engine/Contract/ContractEngine.swift:2035`
  - fix: Floor the tag at max(top-5 positional average, 1.2 × current annualSalary) as the real rule does, and escalate a second/third tag (120%/144%). Without it the tag strictly dominates re-signing for every well-paid star and the screen's central choice is fake.

- [ ] **Q-H38 · The two options on each row are quoted in different league years, so tag-vs-re-sign cannot be compared**
  - evidence: The row prices the tag in 2027: "$26.0M Tag Cost" and "2027 space after tag: $116.2M", under a banner whose whole headline is "Projected 2027 Cap $282.2M / Committed to 2027 $140.1M / Projected Space $142.2M — 2026 cap space $44.2M — unchanged by tagging". Tapping "Contact Agent" on that same row opens a screen that prices the re-sign in 2026: "Charges $14.2M of your $44.2M in room." Its Yearly Breakdown labels rows "Yr 1 / Yr 2", never 2027. Nowhere does the app say what re-signing Braithwaite does to the $142.2M of 2027 space the tag decision is being made against.
  - code: `dynasty/dynasty/UI/Contracts/FranchiseTagView.swift:452`
  - fix: Print the re-signed deal's charge in the same year the tag row quotes ("2027 space after signing: $X") in the negotiation's cap preview, and add a "tag $26.0M vs re-sign ~$XX.XM" comparison line to the expiring row so the screen's own question can be answered without leaving it.


### Contract negotiation

- [ ] **Q-H39 · Composer's "Total: $92.0M / Cap Hit: $46.0M/yr" is not the deal the engine writes — the base schedule doesn't preserve the negotiated total**
  - evidence: Footer reads "Cap Hit: $46.0M/yr" and "Total: $92.0M" for Years 2 / Salary $37.5M / Bonus $17.0M. The bar below reads "Charges $14.2M of your $44.2M in room." Those cannot both be right: the man's row is "$37.4M/yr", so a $46.0M year-one hit would charge $8.6M net, not $14.2M. $14.2M is what the engine actually books: age 30 → frontLoadedBaseSalaries(37_500, 2) = [$43.1M, $39.7M], year one = $43.1M + $8.5M prorated = $51.6M, less the $37.4M replaced = $14.2M. The schedule sums to $82.8M of base, not the $75.0M the offer contains (1.15 + 1.15×0.92 = 2.208× the average, never renormalised), so the Yearly Breakdown disclosure on this same panel totals $99.8M of cap hit against the footer's "Total: $92.0M". Direction and size depend on age and term: a 2-yr veteran deal overpays 10.4%, a 1-yr overpays 15%, a 6-yr veteran deal underpays 5.7%, a 2-yr deal for an under-28 (escalatingBaseSalaries) underpays 12%.
  - code: `dynasty/dynasty/Engine/Contract/ContractEngine.swift:642`
  - fix: Normalise both schedules so they sum to annualSalary × years (divide each year by the shape's mean multiplier), or stop advertising a flat "Cap Hit: $X/yr" and "Total" and print the real schedule's year-one hit and true total in the always-visible footer. Either way the footer, the Yearly Breakdown total and the action-bar charge must be three views of one number.

- [ ] **Q-H40 · "Accept Theirs" commits $112.0M with no cost line — the one explainer next to it describes the other button**
  - evidence: The bar reads "SEND THIS OFFER / Charges $14.2M of your $44.2M in room." and then three buttons: "Walk Away", "Accept Theirs", "Send Offer". Accepting theirs signs the $56.0M/yr, $112.0M package quoted in the bubble above — roughly four times the charge the sentence next to the button states. acceptAction is built with a title and an accessibilityLabel and no explainer at all; DSActionBar shows one explainer, the primary's.
  - code: `dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:821`
  - fix: Swap the explainer to the agent's plan whenever "Accept Theirs" is focused, or print a second short cost line on the secondary button ("Charges $X of your $44.2M"), computed from capGate(for: thread.pendingAgentOffer).

- [ ] **Q-H41 · Roughly 40% of the portrait page is empty background between the one agent message and the offer dials**
  - evidence: The agent's card ends just under "Total: $112.0M  Cap Hit: $56.0M/yr" at about a third of the way down the page; the next pixel of content is the "Years / 2 yrs" row about three-quarters of the way down. The entire middle band of a 13-inch portrait iPad is empty. The body is a fixed VStack — header, round band, NegotiationTranscript, composer, commit bar — so the transcript ScrollView absorbs all slack, and a round-one thread has exactly one bubble in it.
  - code: `dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:208`
  - fix: Fill the band with the decision material this screen is missing anyway: market value, the top-5 positional salaries the ask is priced off, his last three seasons, cap-space-after-signing across the deal's years. Failing that, bottom-anchor the transcript so the single bubble sits against the composer instead of leaving a hole.

- [ ] **Q-H42 · No market value anywhere in the offer composer, though the same file prints one for a pay cut**
  - evidence: The only price anchors on screen are the agent's ask ("2 Years / $44.3M Salary / $23.3M Bonus / 69% Gtd / Total: $112.0M / Cap Hit: $56.0M/yr") and the app's own pre-seeded counter ($37.5M / $17.0M / 59%). Nothing says what a 94 OVR WR is worth. The pay-cut branch of this very view builds the sentence "Market for a 94 OVR WR is $X/yr" from liveDemand.marketValue; the extension composer never reads that property. There is also no snap count, production, injury history or contract history, and the header is not tappable to a player card.
  - code: `dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:929`
  - fix: Show `liveDemand.marketValue` under the Salary dial as a market anchor with a your-offer-vs-market delta, and make the player header open the player card. Reuse payCutMarketNote's wording so both branches say it identically.

- [ ] **Q-H43 · $500K steppers mean 14 taps to reach the agent's asking salary, on 28pt buttons, with no slider or text entry**
  - evidence: Salary shows "$37.5M" and the ask in the bubble is "$44.3M Salary" — at salaryStep = 500 (thousand) that is 14 taps of the "+" to match, plus 13 more for Bonus ($17.0M → $23.3M) and 2 for Guaranteed (59% → 69%). stepperButton is .frame(width: 28, height: 28). The pay-cut composer in the same file gets a Slider under its stepper row; the offer composer gets steppers only.
  - code: `dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:2717`
  - fix: Give the offer builder the same Slider the pay-cut composer has, plus tap-and-hold acceleration and a "Match his ask" shortcut, and raise the stepper hit area to 44pt.

- [ ] **Q-H44 · Same screen says the deal is 2 years and that he has 3 years left**
  - evidence: The sheet headline reads "Wade Braithwaite signs for 2 years", the chip row "YEARS 2", and the receipt "Wade Braithwaite — 2 years, $108.0M total". The header chips directly above read "WR · Age 30 · $54.0M/yr · 3yr left" (they read "$37.4M/yr · 1yr left" on 037). The +1 is deliberate — FranchiseTagView compensates for executeNewLeagueYear's decrement while the rollover is still pending — but nothing on screen says so, and the Contract row itself is written with totalYears = 2, so Player.contractYearsRemaining (3) and Contract.totalYears (2) disagree for the rest of the offseason. A GM reads it as a 3-year, $54.0M/yr commitment ($162M) instead of the $108.0M he just agreed to.
  - code: `dynasty/dynasty/UI/Contracts/FranchiseTagView.swift:112; dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:540-541; dynasty/dynasty/Engine/Contract/ContractEngine.swift:1476 (contractYearsRemaining = plan.contractYears)`
  - fix: Derive the header's term chip from the Contract row (or from plan.contractYears) rather than the compensated counter, or label it by year rather than count ("through 2028"). Long-term, hold the pre-rollover compensation somewhere other than the field the UI reads.


### Combine board

- [ ] **Q-H45 · Red NEED chips on the combine board name OLB/DE/QB while the Hub's Team Needs tile says RB TE S**
  - evidence: On 046 the NEED chip is on Easton Hinsdale (OLB), Brixton Ackerly (DE), Bram Lovegrove (QB), Tobias Lovegrove (OLB), and on 047 Zachariah Jaramillo (OLB). One minute earlier the Hub (200) TEAM NEEDS tile reads "RB TE S — Thinnest groups on your roster". The two sets are disjoint. The board's chips come from `DraftEngine.topTeamNeeds`, which that engine's own documentation calls "a positional-value table wearing a need model's clothes… wrong for anything that means 'this club has a hole': see `teamNeedDeficits`" (DraftEngine.swift:1408-1414). `teamNeedDeficits` exists at DraftEngine.swift:1637 and gates on `components.multiplier > 1.0`.
  - code: `dynasty/dynasty/UI/Scouting/CombineResultsView.swift:292`
  - fix: Point CombineResultsView.teamNeeds at `DraftEngine.teamNeedDeficits(roster:limit:)` — the function written for exactly this question — so the NEED chip on a draft board and the Team Needs tile on the hub cannot name different holes.

- [ ] **Q-H46 · "Rank" column header wraps to "Ra"/"nk" and collides with the sort caret and the Name header**
  - evidence: The first sortable header renders as gold "Ra" on one line and "nk" on the next, with the ascending chevron floating between the two halves and touching the "Name" label to its right (verified on a 4x crop of both 046 and 047). Cause: `CombineW.rank = 32` is a fixed frame, and `sortLabel` appends a chevron inside that 32 pt when the column is the active sort, with no `lineLimit` or `minimumScaleFactor` on the Text. Every other header on the row (Pos 40, GRD 56, PROD 46) has room.
  - code: `dynasty/dynasty/UI/Scouting/CombineResultsView.swift:678`
  - fix: Widen `CombineW.rank` to ~44 (chevron + "Rank"), or label the column "#" and put "Rank" only in the accessibility label. Add `.lineLimit(1)` to `sortLabel`'s Text so no header can ever wrap.


### Combine interviews

- [ ] **Q-H47 · RISK chips clipped to "Ce…" and "Bo…" — the interview list pins RISK at 48pt where the shared board uses 80pt**
  - evidence: In the RECOMMENDED table the RISK column reads "Ce…" (Judah Smallwood, Seneca Truesdale, Boone Lovegrove, Faron Nadeau, Zachariah Jaramillo) and "Bo…" (Bram Vanterpool, Tobias Lovegrove, Jeremiah Colgrove, Wilkes Pankhurst); only the green "Safe" chips (Easton Hinsdale, Kenji Shelburne, Brixton Ackerly, Jonas Brockway, Nehemiah Abernathy) render whole. The real labels are "Ceiling" and "Boom/Bust" (ProspectListControls.swift:481-482).
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:713`
  - fix: Widen this view's own RISK header (line 582) and cell (line 713) from 48 to the 80pt the shared Overview block already uses — ProspectListControls.swift:824-829 documents that 76pt truncates to "Boom/Bus…" and that 80 is the measured minimum. Buy the 32pt back from the elastic NAME column, exactly as that comment says the board did.

- [ ] **Q-H48 · "League teams typically interview 15–20 prospects" advises the player into a strictly worse choice than the screen's own default of 53**
  - evidence: The header prints "53/60 selected" on the left and "League teams typically interview 15–20 prospects" on the right of the same line. The app's own one-tap "Select All Recommended" button produced those 53, and the primary reads "Conduct 53 Interviews". Slots are the only cost — `conductInterviews` does `career.interviewsUsed += ids.count`, no money and no per-interview time — the stage costs one week flat whether you run 1 or 60 ("spends 1 scouting week" on the stage slat), and `WeekAdvancer` resets `career.interviewsUsed = 0` each cycle, so unspent slots are simply destroyed. A player who follows the hint leaves 40 free information slots on the table every spring.
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:294,412,909; Engine/Simulation/WeekAdvancer.swift:1245`
  - fix: Either drop the sentence, or make it true by giving restraint a cost/benefit the engine models (interviewer fatigue lowering read quality past N, or slots that trade against film-study reports). Until then replace it with the fact that matters: "Unused slots expire at the end of the spring."

- [ ] **Q-H49 · "Skip Interviews" and "Advance — Film Study" run the identical handler, and the skip caption is false after 53 interviews**
  - evidence: Bottom bar shows a ghost control titled "Skip Interviews" captioned "Nobody in the building has met this class — the MEET column stays empty." sitting beside the gold primary "Advance — Film Study". The same screen's header reads "53 interviews completed" and "53/60 used", and the explainer to the left already reads "Closes Interviews and opens Film Study. Spends 1 of the 4 scouting weeks left in the spring." In code both controls call the same closure: ghost handler `{ if let next = gate.next { advance(to: next) } }` and primary handler `{ if let next = gate.next { advance(to: next) } }`. `offersHeaderSkip` returns `!isPhaseBlocked` for any `.advance` action and never consults `isComplete`, so the skip ghost is still drawn after the stage is satisfied. The caption string is unconditional for `.interviews`.
  - code: `dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1369, ScoutingHubHeader.swift:60,135`
  - fix: Gate `offersHeaderSkip` on `!isComplete` so the ghost disappears once the stage is satisfied — when both buttons do the same thing, only one should be on screen. While it is shown, derive the caption from state: with `career.interviewsUsed > 0` it must read what is actually forfeited (e.g. "\(60 - used) interview slots go unspent — they do not carry into next spring"), never "Nobody in the building has met this class".

- [ ] **Q-H50 · "Bust risk: 35% → 15%" is a view-local constant, and it contradicts the "Safe" chip the same player wore one screen earlier**
  - evidence: #1 Kenji Shelburne reads "Bust risk: 35% → 15% after interview". #2 Declan Colgrove reads the identical "Bust risk: 35% → 15% after interview". The pre-interview figure comes from `estimateBustRisk` inside the view: `var risk = 35` plus +10 for QB, +5 for WR/CB, +5 for age ≤ 20 — so every non-QB/WR/CB prospect aged 21+ in a 53-man batch prints exactly 35%. That is a third, weaker risk model in the same feature: `CollegeProspect.riskLevel` (age, position, report variance, potential gap, personality) produced the green "Safe" chip on Kenji's row on 051_interviews_selected, and `InterviewResult.riskLabel` (personality tier + off-field + IQ) produced the SUMMARY line "18 low, 19 med, 16 high risk" on this very screen. Kenji is simultaneously "Safe", "low", and "35% bust". Nothing in the engine consumes the 35% — the only prospect-facing bust concepts are post-hoc (`DraftGradeEngine.isBust`, `CareerArcEngine`).
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:1514,1122; Domain/Models/Scouting/CollegeProspect.swift:938`
  - fix: Delete `estimateBustRisk` and derive the delta from the same model the RISK chip uses, so "Safe" and the percentage are one claim. If a percentage is wanted, it has to move into the engine and actually drive rookie development, otherwise print the band change ("Boom/Bust → Safe") which the player can reconcile with the board.


### Film study

- [ ] **Q-H51 · Stage advertises 25 evaluations against $19K when the cheapest visible report is $25K — every recommended row is dead and "Select All Recommended" silently no-ops**
  - evidence: Footer: "0 selected · $0K total" … "25 slots left · $19K budget left". All 13 RECOMMENDED rows are greyed with the sub-line "Over budget at $25K" (or "$40K" for Broadwater, Crisanti, Engelhardt). The cheapest NEXT price anywhere on screen is $25K. The pill "Select All Recommended" is still rendered live in gold, and "25/25 evaluations remaining" is drawn in white (not the danger tint).
  - code: `dynasty/dynasty/UI/Scouting/FilmStudySelectionView.swift:385-391, :949-956, :363-368, :438, :559, :927, :1096`
  - fix: `selectAllRecommended()` walks the list with `guard canAdd(prospect) else { continue }`, so with $19K it inserts nothing and gives no feedback — tapping the screen's one mass-action button does literally nothing. Disable the pill (or caption it "nothing affordable") when no recommended man passes `canAdd`, and make the slot counter honest: show "25 slots · $19K buys 0 of these" rather than a green 25/25. `cycleIsSpent` only fires when the *whole class* is unaffordable, so it never catches the common case where the ranked entry list is unaffordable but a $15K unknown 300 rows down is not.

- [ ] **Q-H52 · "Top of the consensus board" is sorted A→Z by surname, not by board rank**
  - evidence: RECOMMENDED / "Top of the consensus board — mark men to make this your own", then: Ackerly, Broadwater, Brockway, Cartwright, Colgrove, Colgrove, Crisanti, Engelhardt, Goddard, Hinsdale, Hinsdale, Hopewell, Jaramillo — strict alphabetical order by last name. Every row's projection cell reads "Rd1", so the round tie-break never breaks and the whole visible list is an alphabet. The class's own #1 man per the hub ("#1 Kenji Hopewell / QB — Oklahoma") does not appear, even though the list runs Hinsdale → Hopewell → Jaramillo, exactly where he would sort.
  - code: `dynasty/dynasty/UI/Scouting/FilmStudySelectionView.swift:256-265, :313-318, :884; dynasty/dynasty/Engine/Draft/DraftIntel.swift:29-70; dynasty/dynasty/Domain/Models/Scouting/CollegeProspect.swift:117`
  - fix: `computeOrderedProspects()` sorts on `draftProjection ?? 99` then `lastName`. Round is a 7-value key across 350 men, so it is not an ordering. Sort on the consensus board rank (or `scoutedOverall` band midpoint) and show the rank number in the row, so the user ordering $25K of tape can see who is actually worth it. Right now the section header promises a ranking the list does not contain.


### Cap compliance

- [ ] **Q-H53 · The newest, largest contract on the books is the only row that costs $0 to release — a free-lunch cut ranked #2 in the levers list**
  - evidence: Row 2: "MLB Callum Abernathy 91 Age 30 — $25.3M/yr, 4 yrs left → Release +$25.3M / $0K dead". Releasing him returns 100% of his salary at zero cost. Every other visible row prices dead money at ≈10.7%/yr of salary: Wimberly $31.0M/1yr → $3.3M dead; Goddard $12.8M/1yr → $1.4M; Brockway $5.1M/1yr → $548K; Kirkbride $4.9M/2yr → $1.1M; Frobisher $6.1M/3yr → $2.0M; Hedgepeth $3.9M/3yr → $1.3M. At that rate Abernathy should read ≈$10.9M dead; his own signing card on 066 claims $55.6M guaranteed. Sandbox mode is ruled out (every other row books dead money) and `CampRosterEngine.isCampBody` is ruled out (it zeroes `salaryRelieved` too, which would render "+$0K", not "+$25.3M").
  - code: `dynasty/dynasty/UI/FreeAgency/FinalPushView.swift:1413-1414 (NOT CapManagementEngine.swift:295)`
  - fix: Trace the FA signing door: `FreeAgencyEngine.signFreeAgent` mints a Contract only in `.realistic`, while `ContractEngine.signPlayer` mints none in either simple or realistic (ContractEngine.swift:139-142). A just-signed player must land in one of the two priced paths — either a Contract with real signingBonus/guaranteedMoney, or `ContractEngine.impliedDeadCap`. Add a regression test asserting a player signed this league year cannot be released for a net gain equal to his full salary.


### Free agency — market

- [ ] **Q-H54 · Every row shows "HEAT COOL" next to "10 teams interested — bidding war" — two market-temperature readings that contradict each other**
  - evidence: Row 1 (Kason Marsden, SS, 90): the third state slot reads "HEAT COOL", and the line directly under it reads "🔥 10 teams interested — bidding war". Same on all 7 visible rows: Hopewell "HEAT COOL" + "7 teams interested — bidding war"; Bolliger "HEAT COOL" + "7 teams interested — bidding war"; Winchester "HEAT COOL" + "8 teams interested — bidding war". Not one row on the board reads anything but COOL. Same on 064_fa_offer_sheet.png and 065_fa_skipped.png.
  - code: `dynasty/dynasty/Engine/FreeAgency/BiddingHeatEngine.swift:27 (consumer: dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:1518-1571; missing producer: no FABid is ever inserted anywhere in the app)`
  - fix: The two readings come from different models: HEAT is `BiddingHeatEngine.computeHeat(playerID:currentDay:bids:visits:)`, which counts persisted `FABid` rows (`uniqueBidderCount ... case ...2: tier = .cool`, BiddingHeatEngine.swift:45-47), and on Day 1 no bids exist yet because `generateAIOffers` only runs inside `processRound()`. The interest line comes from the static `fa.marketInterest`. So HEAT is guaranteed COOL for all 126 free agents on the single most important market day. Either seed heat from `marketInterest` on round 1, or suppress the HEAT slot until bids exist (draw it as an unset dashed slot like BID/VST) rather than printing a false "COOL" verdict that invites the player to lowball a man 10 clubs are chasing. Slot is built at FAWeeklyView.swift:1565.

- [ ] **Q-H55 · The gold primary button reads "Submit offers → Day 2" while the warning beside it reads "NO OFFERS ON THE TABLE"**
  - evidence: Bottom bar, left: "NO OFFERS ON THE TABLE / Advancing lets the league sign unopposed for a day you cannot get back." Bottom bar, right, the screen's only gold element: "Submit offers → Day 2". The ledger above agrees there is nothing to submit: "PENDING —" and "AVAILABLE $64.8M" equal to "CAP ROOM $64.8M". Same on 064 and 065.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:1784 vs 1795-1802`
  - fix: `submitExplainer` already branches on `offerCount > 0` (FAWeeklyView.swift:1797) and correctly says "No offers on the table", but the primary title is unconditional: `title: currentRound < 6 ? "Submit offers → \(nextLabel)" : "Close the market"`. Give the button the same branch — "Advance → Day 2" (or "Sit out Day 1 → Day 2") when `myOffers.isEmpty`, and "Submit 3 offers → Day 2" when it is not, so the commit label names what it actually does and the count is legible before the tap.

- [ ] **Q-H56 · The interest count is printed twice on every row — "6 teams interested   6 teams interested"**
  - evidence: Row 3 (Leander Marchetti, FS, 88): "👥 6 teams interested  🔥 6 teams interested" — the identical five words, back to back, same amber colour, two different icons. Row 1: "🔥 10 teams interested — bidding war  🔥 10 teams interested". Every one of the 7 visible rows repeats its own count: Hopewell 7/7, Bolliger 7/7, Waterhouse 5/5, Balfour 6/6, Winchester 8/8. Same on 064 and 065.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:1694-1712 (HEAD had the duplicate; working tree line 1712 is the fix)`
  - fix: At HEAD, `rumorText` returns `"\(fa.marketInterest) teams interested — bidding war"` (>=7) or `"\(fa.marketInterest) teams interested"` (>=4), and `aiInterestLabel` in the same HStack independently prints `"\(interest) teams interested"`. NOTE: the working tree already carries an uncommitted fix (rumour reduced to the bare "Bidding war" flavour, count left to `aiInterestLabel`, now at FAWeeklyView.swift:1712) — verify it is committed and rebuilt rather than filing this twice.


### Free agency — complete

- [ ] **Q-H57 · "$55.6M gtd" on the FA signing card is a hardcoded 55% of total value, not the contract's guaranteed money**
  - evidence: 066 signing card: "MLB Callum Abernathy … 4yr · $101.0M total · $55.6M gtd". $101.0M × 0.55 = $55.55M — exactly the displayed figure. FACompleteView.swift:750-751 builds the row as `totalValue: player.annualSalary * player.contractYearsRemaining, guaranteedMoney: Int(Double(player.annualSalary * player.contractYearsRemaining) * 0.55)`. Nothing reads `Contract.guaranteedMoney`. Every FA signing on this screen will always read exactly 55% guaranteed regardless of the deal. The engine disagrees about the same contract one step earlier: 060 prices Abernathy's release at "$0K dead".
  - code: `dynasty/dynasty/UI/FreeAgency/FACompleteView.swift:751 (render at :442)`
  - fix: Read the real term: fetch the player's `Contract` and show `contract.guaranteedMoney` (and `contract.signingBonus`), or omit the gtd chip when no Contract row exists rather than inventing one. `Contract.deadCap` already treats guarantees as the mechanism that produces dead money (Contract.swift:125, F-61) — the summary screen must quote the same number or the player plans against a fiction.

- [ ] **Q-H58 · Before/After "Cap Used" is hardcoded as an improvement — spending cap is painted the same green as saving it**
  - evidence: On screen: "Cap Used  $255.5M → $219.3M" with $219.3M in green (success), on a page headlined "DISAPPOINTING FA — Critical needs went unaddressed". FACompleteView.swift:331-335 passes `improved: true` unconditionally for that row, and `comparisonRow` renders `.foregroundStyle(improved ? Color.success : Color.warning)` (line 363). The two rows either side are computed honestly (`ba.rosterOVRAfter >= ba.rosterOVRBefore` → 80→79 in amber; `ba.starterGapsAfter <= ba.starterGapsBefore` → 0→1 in amber). So a GM who correctly invested $40M in free agency sees his rising cap number in the same green as one who signed nobody.
  - code: `dynasty/dynasty/UI/FreeAgency/FACompleteView.swift:334 (color at :363)`
  - fix: Cap Used has no universally good direction on this screen — either drop the colour (render it in textPrimary and let the delta speak) or tie it to whether the spend bought anything, e.g. green only when cap rose AND starter gaps fell.


### Pro days — reserve sheet

- [ ] **Q-H59 · The reserve sheet takes the default iPad form-sheet size: it bisects a scout row and hides the school's prospect list entirely**
  - evidence: The sheet is ~564x636pt on a 1032x1376pt screen. The 5th option renders as "Ezekiel Waterhouse | DT Specialist | Recommended" with its stat line "Accuracy 76  0/3 slots" sliced horizontally by the pinned "Select a scout" bar; 3 of 8 scouts are below the fold. Below them sits a whole "Michigan State prospects" section (code line 1221) that is invisible — so while choosing who reads this school, you cannot see who is at it.
  - code: `dynasty/dynasty/UI/Scouting/ProDayTourView.swift:215,1197-1224,1230-1245`
  - fix: ProDayTourView is the only sheet host in the app with no sizing modifier (21 other call sites use presentationDetents/presentationSizing). Add `.presentationSizing(.page)` or an explicit large detent, and move the prospect section above the scout list — you pick the reader after you know the reading.

- [ ] **Q-H60 · The scout choice is never priced: "Accuracy 79" vs "Accuracy 59" is ±3 vs ±6 OVR on 11 men, and the green "Recommended" chip is worth only −3**
  - evidence: The sheet offers "Faron Maddocks | Chief Scout | Recommended | Accuracy 79", "Sincere Hubbell | FS Specialist | Accuracy 59" (red), "Ezekiel Waterhouse | DT Specialist | Recommended | Accuracy 76" and never states what the number buys. In the engine errorRange = max(2, 15*(1−acc/100)): 79 → ±3, 59 → ±6, applied to every declared man at the school (11 at Michigan State). The "Recommended" chip is granted to ANY scout whose specialization matches ANY prospect present and is worth accuracyBonus += 3 on that one position — so a red "Accuracy 59" row can wear the same green chip as the department's best scout.
  - code: `dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift:210-225,1538-1584; ProDayTourView.swift:1187-1191,1291`
  - fix: Print the consequence, not the input: "reads 11 men to ±3 OVR" vs "±6". Restrict "Recommended" to bestMatch only, or label the weak case honestly ("DT specialist — 2 DTs here, ±3 better on those two"). Sort the list by resulting error band.


### Pro days

- [ ] **Q-H61 · The screen's one commit — "Send the department out" — is not on screen, and the sheet tells you to press it**
  - evidence: On 073 and 074 the full 2064x2752 screen contains no primary button: the only actions visible are three 12pt gold "Reserve" labels. The commit is the last section of a List that holds 8 scout rows + 5 recommended rows + 25 school rows. Meanwhile the sheet on 067 says "Reserving a slot books this school for the circuit. Nothing runs until you send the department out." — naming a control the player cannot see from anywhere on this screen.
  - code: `dynasty/dynasty/UI/Scouting/ProDayTourView.swift:236-248,724,1199; ScoutingHubView.swift:1314-1323; ScoutingHubHeader.swift:113`
  - fix: Pin the CTA: move "Send the department out" into a bottom safe-area bar (`.safeAreaInset(edge: .bottom)`) so it is on screen from arrival, disabled with "Reserve at least one school first" — the copy already written for the zero-slot state. A one-shot, cycle-losing action must not live 30 rows below the fold.

- [ ] **Q-H62 · The stage-unlock captions — the only sentence telling you why a stage is shut — are truncated on the band**
  - evidence: Slat 5 reads "Finish Pro Day Foc…" (the string is "Finish Pro Day Focus") and slat 6 reads "Opens after Mock…" (the string is "Opens after Mock 1.0 is filed"). The truncation eats the payload: which mock, and what act. Both appear identically on 067.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:713-718,729-740; DraftPrepProcessBar.swift:117-135`
  - fix: `secondLine` is `.lineLimit(1)` in an ~82pt box while the TITLE was deliberately given two lines for exactly this reason (see the `titleLines` doc comment two lines below). Give the sub-caption `lineLimit(2)` on locked slats, or shorten the caption vocabulary to fit 12 condensed characters ("After Mock 1.0", "After Pro Days").

- [ ] **Q-H63 · "Reserve" — the screen's per-row action — is a ~13pt-tall tap target, well under the 44pt minimum**
  - evidence: The "Reserve" labels beside Michigan State, USC and Minnesota are caption-size text with a scope glyph and no padding; measured on the 2064px shot the hit box is ~25px ≈ 12pt tall. The row behind it is itself a Button (the expand chevron), so a near-miss expands the school instead of doing nothing. Same on 067 and 074.
  - code: `dynasty/dynasty/UI/Scouting/ProDayTourView.swift:573-580,457-487`
  - fix: Give the button `.padding(.vertical, 12).padding(.horizontal, 10).contentShape(Rectangle())` or `.frame(minHeight: 44)`. The release "x" on a RESERVED row (same file, caption-size icon) needs the same treatment.


### Draft war room

- [ ] **Q-H64 · Two different prospects share the full name "Nehemiah Abernathy" on the same visible board**
  - evidence: 076: row "#1  RT  Nehemiah Abernathy  22  ELI  Set  Safe  B–/A" and row "#23  OLB  Nehemiah Abernathy  20  ELI  Med  Ceiling  B–/A" — same first+last name, different position, different age. On 077/078 the #1 row is struck through and stamped "ARI #13" while the #23 row is still live, so they are provably two men. The class is 350 prospects (DraftClassBuilder.swift:69 `count: Int = 350`) drawn from a 55×55 = 3,025-name cross product (RandomNameGenerator firstNames/lastNames) with no uniqueness pass — expected collisions ≈ C(350,2)/3025 ≈ 20 duplicate full names per class.
  - code: `dynasty/dynasty/Engine/Scouting/DraftClassBuilder.swift:586`
  - fix: Give DraftClassBuilder a used-name set and redraw (or append a suffix / widen the pools) until the full name is unique within the class. 3,025 combinations cannot cover 350 draws; either the pools grow or the draw must be rejection-sampled.

- [ ] **Q-H65 · Big Board prints a "FIT" header over a column no row fills, and the whole header block is 32pt off its data**
  - evidence: Header reads "#  POS  NAME  AGE  PROD ⓘ  FIT  NEED  RISK  OVR". Every one of the 25 visible rows prints exactly five values — e.g. #1: "22 | ELI | Set | ✓Safe | B–/A" — nothing ever appears under FIT. Cause: rows pass `includesSchemeFit: false` with an explicit comment ("NO FIT COLUMN IN THE ROOM… A column that is structurally empty is not information", LiveBigBoardPanel.swift:1216) but the header uses `ProspectColumnContext(includesRisk: true)` where `includesSchemeFit` defaults to `true` (ProspectListControls.swift:681), so `Text("FIT").frame(width: 32)` still renders (ProspectListControls.swift:1163). The extra 32pt is absorbed by the elastic NAME column, so measured on the shot the ages sit ~32pt right of "AGE" (nearer "PROD"), the ELI/AA chips sit ~32pt right of "PROD" (nearer "FIT"), and "Set/Med/High" sits under "FIT" rather than "NEED". Same on 077 and 078.
  - code: `dynasty/dynasty/UI/Draft/Components/LiveBigBoardPanel.swift:621`
  - fix: Change `headerContext` to `ProspectColumnContext(includesSchemeFit: false, includesRisk: true)` so the header block matches the cell block exactly. Better: derive the header context from the same function that builds the row context so they cannot diverge again.

- [ ] **Q-H66 · The available-prospect pool is rebuilt by full-name string, so a duplicate name erases the innocent twin on reload**
  - evidence: `DraftDayCoordinator` builds the board at load with `let draftedNames: Set<String> = Set(draftPicks.compactMap { $0.playerName })` then `.filter { !draftedNames.contains("\($0.firstName) \($0.lastName)") }`. On 077 ARI has drafted RT Nehemiah Abernathy at #13 (row #1 struck, stamped "ARI #13"). OLB Nehemiah Abernathy is still live at row #23. Resume this draft and the name filter drops BOTH — the undrafted OLB silently disappears from the class and can never be picked. The live path is correct (`availableProspects.firstIndex(where: { $0.id == prospect.id })`, line 1406) and `LiveBigBoardPanel.recentlyTaken()` was already hardened against exactly this hazard ("an unguarded index could hand the struck-through row to the wrong man"); only the coordinator's load-time rebuild is still name-keyed.
  - code: `dynasty/dynasty/UI/Draft/DraftDayCoordinator.swift:385`
  - fix: Persist the prospect UUID on DraftPick and filter the pool by id, not by `playerName`. Until then, at minimum apply the same still-available tie-break `recentlyTaken()` uses so only one of a duplicate pair can be removed per pick.

- [ ] **Q-H67 · The MEDIA toast prints a red "-3" / green "+2" penalty chip on picks that change nothing**
  - evidence: 077 shows "MEDIA — Eyebrows raised across the war room — Kenji Shelburne?" with a red "-3" chip; 078 shows "MEDIA — NE gets a high-floor OLB in Jonas Brockway." with a green "+2". Both are AI picks (Shelburne → CLE #2, Brockway → NE #7 per the board's right column), and the coordinator states AI deltas are thrown away: "We never apply these to the user's DraftReputation — they exist purely for UI flavour" (DraftDayCoordinator.swift:1485-1489). Even for a USER pick the media delta is a no-op: `ReactionsEngine.apply` has `case .media: // Media has no numeric stat ... continue` (ReactionsEngine.swift:118-122). The rail renders this dead number in the identical red/green chip it uses for owner, locker-room and fan deltas, which DO move real stats (DraftBroadcastRail.swift:617-620).
  - code: `dynasty/dynasty/UI/Draft/Components/DraftBroadcastRail.swift:617`
  - fix: Suppress the delta chip when `actor == .media`, or when the reaction belongs to an AI pick. A signed red number next to a critical headline reads as "this just cost you 3"; it costs nothing and it isn't even your pick.


### Draft — on the clock

- [ ] **Q-H68 · Two different prospects in the same draft class are both named "Nehemiah Abernathy", and both are on screen at once**
  - evidence: 080 big board: "#1 RT Nehemiah Abernathy" (struck through, ARI #13) and, twenty-two rows below it, "#23 OLB Nehemiah Abernathy" (live, PICK chip). Both are visible in the same scroll position. The feed then abbreviates one of them ambiguously: "ARI steal RT N. Abernathy #13". 084 shows the same pair ("#23 OLB Nehemiah Abernathy", struck, BUF #24) plus a third Abernathy in the card's TE list ("48 B. Abernathy"). The same class also carries three Colgroves (Jeremiah TE, Hayden RG, O. Colgrove TE), three Lovegroves (Boone DT, Tobias OLB, B. Lovegrove QB), three Pankhursts, three Smallwoods and three Vanterpools.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:31-77, 85-89; DraftClassBuilder.swift:586`
  - fix: `RandomNameGenerator.randomName()` draws first and last independently from two 55-item arrays with no used-name set — 3,025 possible full names against a ~285-man declared class, so ~13 exact collisions per class is the expected value, before counting the ~1,700 veterans. Thread a `used: inout Set<String>` through `DraftClassBuilder` (and the league builder) and redraw on collision, or grow the pools by an order of magnitude. Exact duplicates inside one class are the one case that must be impossible — the feed's `shortName` ("N. Abernathy") cannot disambiguate them.

- [ ] **Q-H69 · The TRADE WIRE says SF burned two future 1sts to jump the line for a RT — and the same screen shows SF took a guard and the RT still on the board**
  - evidence: TRADE WIRE, highlighted row: "TRADE — SF move up to #18, sending #43 (R2) + 2029 R1 + 2030 R1 to DEN" / "Otis Landry jumped the line for a RT: Nadeau was BB #11 and is still on the board." But on the SAME screen: the pick strip reads "SF · LG GODDARD"; the right rail reads "LAST OFF THE BOARD  SF  LG Jamari Goddard"; the feed reads "SF reach for LG J. Goddard — Consensus board had him #55 — taken 37 slots ahead of it. #18"; RECENT reads "#18 SF Jamari Goddard LG". And row "#11 RT Faron Nadeau" is still live with a PICK chip. SF moved up for a RT and did not take the RT.
  - code: `dynasty/dynasty/Engine/Draft/DraftDayTradeEngine.swift:634-704 (motive at :699), :196; DraftDayCoordinator.swift:875-913`
  - fix: `DraftDayTradeEngine` builds `motive` from `slider.prospect` — the falling man whose position clears the buyer's need threshold — at the moment the swap is priced, and nothing binds the buyer's subsequent `aiMakePick` to that target. Either (a) pin the target: have the buyer take `slider.prospect` on the acquired slot unless he is gone, which is what a real trade-up means, or (b) stop naming a player and write the motive off the position only ("San Francisco moved up for tackle help"). As shipped this is the one line on the screen that tells the user whether to panic and move up, and it is wrong one pick later.

- [ ] **Q-H70 · The big board header has a phantom "FIT" column: no row renders a FIT cell, and AGE/PROD values sit 32pt right of their own headers**
  - evidence: Header on all three shots reads "# POS NAME AGE PROD ⓘ FIT NEED RISK OVR". In row #1 on 080 the values are "22 | ELI | Set | ✓Safe | B−/A | ARI #13" — five cells under six labels. Zoomed, the age value "22" is centred under the word PROD, the ELI production chip is centred under the word FIT, and nothing at all sits under FIT's own 32pt slot in any of the ~80 rows across the three screenshots. NEED, RISK and OVR realign only because the missing column is absorbed further right.
  - code: `dynasty/dynasty/UI/Draft/Components/LiveBigBoardPanel.swift:621 vs :1228 and :296-299; ProspectListControls.swift:681, :810, :1163`
  - fix: `columnContext(for:)` passes `includesSchemeFit: false` (deliberately — see its comment "NO FIT COLUMN IN THE ROOM"), but `headerContext` is `ProspectColumnContext(includesRisk: true)` and `includesSchemeFit` defaults to `true`, so `ProspectColumns.headers` still emits `Text("FIT").frame(width: 32)`. Both the header and the rows have an elastic NAME column of the same total width, so the header's NAME comes out 32pt narrower and every header label left of NEED drifts off its data. One-line fix: `private static let headerContext = ProspectColumnContext(includesSchemeFit: false, includesRisk: true)`.


### Combine hub

- [ ] **Q-H71 · Chemistry is pinned at 100/100 "Elite" — the score is an unnormalised per-player sum that clamps for every roster in the league**
  - evidence: LOCKER ROOM reads "Chemistry  Elite 100/100" with a completely full green bar, directly above "Team Morale 65%" — two numbers in one card giving opposite readings of the same room, in week 1 of a career. Chemistry is computed as `50 + leadershipScore - toxicityScore` with no normalisation by roster size (LockerRoomEngine.swift:112), and archetypes are drawn uniformly from 9 cases (LeagueGenerator.swift:694). On a 53-man roster that is ~5.9 of each archetype: leadership ≈ 5.9×(8 teamLeader + 6 mentor + 1 steady + 1 quiet + 2 clown) + ~10 motivation-bonding ≈ 116, toxicity ≈ 5.9×(4 dramaQueen + 2 fiery) ≈ 36, raw ≈ 130 → clamped to 100. The stat has no dynamic range, so the card can never react to a signing, a cut, or a bad season.
  - code: `dynasty/dynasty/Engine/Simulation/LockerRoomEngine.swift:112`
  - fix: Divide leadership and toxicity by roster size (or express them per-man) before the 50 baseline so a typical roster lands near 50-60 and an actual leadership core is what pushes toward 100. Then the tier labels (Elite/…) and the bar become readable, and the card starts paying off locker-room decisions instead of always showing the ceiling.

- [ ] **Q-H72 · SCOUTING tile arithmetic does not add up: 350 total vs OFF 196 + DEF 148 = 344**
  - evidence: The SCOUTING card reads "#1 Kenji Hopewell / QB — Oklahoma / 350 total   OFF 196   DEF 148". 196 + 148 = 344, six short of 350. In code the three numbers are `draftClass.count`, `filter { $0.position.side == .offense }.count` and `filter { $0.position.side == .defense }.count` — but `PositionSide` has a third case, `.specialTeams` (Position.swift:3-7), so the K/P/LS prospects are silently dropped from the breakdown with no third figure to catch them.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2151`
  - fix: Either add the missing bucket ("ST 6") or make the two shown figures explicitly partial ("196 OFF · 148 DEF of 350" reads no better — prefer showing all three). A tile whose sub-counts must sum to its total should assert that in a test.

- [ ] **Q-H73 · Hub's gold "#1" prospect (Kenji Hopewell) is not the #1 on the Scouting board (Easton Hinsdale)**
  - evidence: At 14.43 the Hub SCOUTING card shows "#1 Kenji Hopewell / QB — Oklahoma" with the "#1" in accent gold. At 14.44 the Scouting board (046) shows "Rank 1  Easton Hinsdale  OLB  Rd 1  UCLA" and Kenji Hopewell appears nowhere in the visible top 15. The tile takes `draftClass.first` — and `currentDraftClass` is restored from `modelContext.fetch(FetchDescriptor<CollegeProspect>(...))` with **no sortBy** (WeekAdvancer.swift:308-313), so after any restore ".first" is an undefined row; on a freshly generated class it is slot 1, i.e. the class's hidden ground-truth best player, handed to a club that has scouted 9% of the class.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2136`
  - fix: Drive the tile from the same ordering the Big Board uses (the club's own scouted board), or drop the "#1" badge and label the row for what it is. Add `sortBy:` to the restore FetchDescriptor so the in-memory class order is deterministic across launches.

- [ ] **Q-H74 · Offseason rail truncates the required task's own title and cuts every cost clause off the descriptions**
  - evidence: The one required task renders as "Review" / "Combine res…" — its own name is unreadable — while the locked row two lines below spells it out in full: 'Locked · finish "Review Combine results" first'. Three descriptions are cut mid-word at two lines despite `.lineLimit(4)`: "…Check media r…" (source string ends "Check media reactions."), "…Skip it and you read the same n…" (source ends "…the same numbers off the broadcast, rounded."), "…for the men at the top…" (source continues "…of your board. 8 reports is a worked stage; each one costs an evaluation slot."). The clause naming the *price* is the half that gets cut every time — which is verbatim the failure the code comment at :442-449 says was fixed by raising the limit to four.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:386`
  - fix: The title is squeezed because NEXT + Required chips share its first line via `HStack(alignment: .firstTextBaseline)` — move the chips to their own row under the title, or give the title `.layoutPriority(1)`. Then find why `.lineLimit(4)` renders as two: the rail is `.frame(width: 300)` around a panel with `.frame(minWidth: 300)` plus 8 pt leading padding, i.e. the panel is already 8 pt over budget.


### Week hub (regular season)

- [ ] **Q-H75 · Week 1 task list says "your opponent" while the same screen names JAX twice**
  - evidence: On 700_season_001 the week band reads "1 @ JAX  NOW" and the Opponent Scout tile reads "Vs JAX", but the YOUR SEASON list under REGULAR SEASON reads "Set game plan for your opponent" and "Tune week prep vs your opponent". One week later (720_season_003) the identical rows read "Set game plan for Green Bay Timberjacks" / "Tune week prep vs Green Bay Timberjacks" — so the generic string is Week 1 only.
  - code: `dynasty/dynasty/UI/Career/CareerShellView.swift:711 vs 720; guard at 2997-3001; opponent read at 3084-3089; TaskGenerator.swift:1374`
  - fix: In CareerShellView's `.onChange(of: career.currentPhase)` (line 710) call `reloadSeasonFixtures()` BEFORE `regenerateTasks(for: newPhase)`. On the offseason→regularSeason flip the fixtures for the new season do not exist yet, so `currentWeekGame` is nil when the task list is built, `TaskGenerator.regularSeasonTasks` falls to `opponentName ?? "your opponent"`, and `regenerateTasks`'s `week != lastGeneratedWeek` guard stops it ever being rebuilt for Week 1. Alternatively have `reloadSeasonFixtures` re-run `regenerateTasks` whenever it changes `currentWeekGame`.

- [ ] **Q-H76 · The one "Action Required" message drops off the hub after a single week — the preview sorts by recency only**
  - evidence: On 700_season_001 the MESSAGES list ends with "Yosef Estabrook · Season 2027: My Expectations · ⚠ Action Required" as the 5th and last visible row, above "77 more messages". On 720_season_003 that row is gone — the five rows are Player Development, Nina Kowalski, Local Media, Demetri Goddard, Finnian Balfour, all routine, and "82 more messages". Nothing else on the hub indicates an action is outstanding; the "Tasks" filter tab carries no count.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:802, 767, 833 vs dynasty/dynasty/UI/News/InboxView.swift:43-61; OwnerPersonaEngine.swift:504-506`
  - fix: The full Inbox already gets this right — `InboxView.filteredMessages` sorts "1) Action Required (unread first), 2) Unread, 3) Read" (InboxView.swift:45). Apply the same `sortRank` to the dashboard's `displayMessages` instead of `Array(filtered.reversed().prefix(5))`, and put an unread count on the "Tasks" filter tab.

- [ ] **Q-H77 · Chemistry is welded at "Elite 100/100" — the meter is the clamp, not a measurement**
  - evidence: LOCKER ROOM reads "Chemistry  Elite 100/100" with a 100%-full green bar on 700_season_001 (Week 1) and the identical "Elite 100/100" on 720_season_003 after a 28-18 win. Chemistry is `max(0, min(100, 50 + leadershipScore - toxicityScore))` where the scores are SUMS over the whole 53+ man roster: teamLeader +8, mentor +6, classClown +2, steady/quiet +1 each, +2 per motivation group of 3+, against dramaQueen 4-8 and fieryCompetitor 2-5. Archetypes are assigned uniformly (`PersonalityArchetype.allCases.randomElement()!`), so a 53-man roster at the 70 morale baseline scores roughly +115 leadership vs ~36 toxicity = 129 raw against 50 points of headroom. The stat is pinned at the ceiling for essentially every roster.
  - code: `dynasty/dynasty/Engine/Simulation/LockerRoomEngine.swift:112-113 (clamp), 36-98 (table), 341-348 (Elite >= 80); CareerDashboardView.swift:3483`
  - fix: Normalise instead of clamping: divide the net score by roster size (a per-player average) or map raw score through a curve onto 0-100 so a good room lands ~75 and there is headroom above and below. Until then the whole locker-room system (chemistry-affecting events, leadership signings) is invisible to the player because the number cannot move.


### Advance confirm sheet

- [ ] **Q-H78 · The "Sim & Advance" confirmation lands on the top navigation bar, not on the button that raised it**
  - evidence: On 700_season_002 and 740_season_044 the popover covers the middle of the top nav: only "Hub" and "Trades" labels remain readable — Roster, Staff, Cap, Scouting and Draft are hidden behind it (all seven are visible on 740_season_052, where no popover is up). It also covers the Staff tile: "23/23" is clipped at the top and the budget row reads "Budge" with the rest under the card. Its arrow points down into the Locker Room tile. The button that triggered it — "Advance to Week 2" — is ~700 pt away in the bottom-left rail.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:598-607, :266-273`
  - fix: `.confirmationDialog` is attached to the dashboard's root view, so iPadOS anchors the popover to the root's centre. Attach it to the Advance button inside `TimelineTasksPanel` (or drive it with a `.popover(item:attachmentAnchor:arrowEdge:)` anchored to `tasks.advance`) so it points at the control it is confirming and never covers the nav bar.


### Weekly press conference

- [ ] **Q-H79 · "Preview headline" tap target is 22pt tall — exactly half the 44pt HIG minimum, on all 12 option cards in the batch**
  - evidence: The "Preview headline ⌄" capsule on the CONFIDENT card measures 44 device px tall (rows 1078–1121 of the 2064x2752 image) = 22.0pt at @2x. Code confirms the size: 11pt caption text (DSType.Size.caption) with .padding(.vertical, DSSpacing.xxs) = 4pt top and bottom, and .contentShape(Capsule()) clips the hit area to exactly that capsule. It appears three times per screen on 720_season_005.png, 740_season_054.png and 740_season_058.png — 12 instances in this batch — and it is the only route to what the code calls "the strongest read available before answering".
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:986-1005`
  - fix: Give the button .frame(minHeight: 44) (or .contentShape(Rectangle()) over a 44pt-tall row) without growing the visible capsule. There is 28% of the screen sitting empty below these cards, so there is no layout pressure justifying a 22pt control.


### Press reaction

- [ ] **Q-H80 · Owner satisfaction is already 100% but the screen keeps paying and displaying owner gains the clamp throws away**
  - evidence: 048 BEFORE THIS SESSION shows "100% SATISFACTION" while RUNNING IMPACT shows "OWNER +3" and the ledger shows "OWNER +1". 060 shows "100% SATISFACTION" with "OWNER +6". Both apply sites clamp: CareerShellView.swift:1838 `ownerObj.satisfaction = min(100, max(0, ownerObj.satisfaction + result.totalEffects.ownerSatisfaction))`. At 100 every positive owner delta is discarded and only negatives (060's "OWNER -2") register — yet the hint chips still advertise "Owner ↑ likely approves" as an upside worth choosing over "Media ↑ good copy".
  - code: `dynasty/dynasty/UI/Career/CareerShellView.swift:1838; dynasty/dynasty/UI/Career/PressConferenceView.swift:1362-1364,1543-1550`
  - fix: When owner satisfaction is at the cap, make the owner hint headroom-aware ("Owner ↑ already maxed", greyed) and print the ledger pill as "OWNER +1 (0 banked)", the way the summary already prints 92% → 95%. Same treatment at 0. Better still, give the owner axis somewhere to go above 100 (job-security buffer) so a maxed owner is not a dead axis for the rest of the season.


### Press session summary

- [ ] **Q-H81 · OWNER "+3" is printed above "100% → 100%" — the delta is clamped away and the cost line still claims it**
  - evidence: 740_season_050: the OWNER cell reads "+3" in green with "100% → 100%" underneath, and the action bar says "2 answers · moved the owner +3 · +4 legacy · no promises on the ledger." 740_season_061 is the same defect one presser later: "+6" over "100% → 100%", cost line "3 answers · moved the owner +6 · +4 legacy". The baseline string is built with a clamp — PressConferenceView.swift:1364: "\(base.satisfaction)% → \(min(100, max(0, base.satisfaction + effects.ownerSatisfaction)))%" — and the write clamps identically (CareerShellView.swift:1839, IntroSequenceView.swift:116), so at 100% satisfaction +3 and +6 are worth exactly zero. The screen advertises a payoff it did not deliver, and summaryCostLine (PressConferenceView.swift:1548-1550) only branches on owner == 0, so it never notices.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1364`
  - fix: Show the realised delta, not the authored one: compute realised = clamped(after) - before and drive both the big number and the cost line off it. When realised == 0 but authored > 0, say so — "+3 (owner already maxed)" in tertiary, and "the owner was already all the way there" in the cost line. Same treatment at the 0% floor.

- [ ] **Q-H82 · Roughly half the portrait iPad is empty background between the last card and the action bar**
  - evidence: On 740_season_050 the YOUR KEY QUOTES card ends at about y=750 of the 2000px view and the "WHAT IT COST" bar starts at about y=1868 — ~1120px, 56% of the screen, is empty. 720_season_011 and 740_season_061 carry one more quote each and are still ~51% empty below y=858. Horizontally the same: the content column is capped at DSLayout.wideMeasure = 900pt (Theme.swift:206) on a 1032pt-wide canvas and left-aligned, so a ~130pt gutter runs down the right edge of every card. summaryContent (PressConferenceView.swift:1194-1210) is a top-aligned VStack in a ScrollView with only `Spacer(minLength: DSSpacing.sm)` at the end, so nothing ever fills the page.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1194`
  - fix: The empty half is exactly where the missing content belongs — put the season-to-date tone ledger, the promise ledger (currently hidden entirely when empty), and the question that produced each quote into it. Failing that, the summary is short enough to be a DSResultSheet rather than a full-screen phase, or centre the stack vertically and let the type scale up.


### Advance confirm sheet

- [ ] **Q-H83 · At Week 18 of 18 the primary button says "Advance to Week 19" — a week the same screen says does not exist**
  - evidence: Header: "2027 SEASON · WEEK 18 OF 18". Week band tail: "POSTSEASON / Opens after Week…". Band current slat: "18 VS PIT NOW". The only gold action in the rail reads "» Advance to Week 19". Three elements on one screen; two say the season ends at 18, the button invents a 19th regular-season week. The engine actually flips to the playoffs here.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:737; WeekAdvancer.swift:2617-2620; SeasonWeekBand.swift:52,185,244`
  - fix: In `advanceButtonLabel`, guard the `.regularSeason` case: when `career.currentWeek >= SeasonWeekBand.regularSeasonWeeks` return "Advance to the Wild Card Round" (or "Enter the Playoffs"), matching `WeekAdvancer`'s `currentWeek > 18 → phase = .playoffs, currentWeek = 19`. Week 19 is an internal index, not a label to print.

- [ ] **Q-H84 · The PLAYOFFS phase block is captioned "WEEKLY DURING REGULAR SEASON"**
  - evidence: All three screens. The rail's third block reads "PLAYOFFS · Jan" and directly beneath it "WEEKLY DURING REGULAR SEASON", followed by "Prepare for this round vs your opponent / Review matchups / Check injury report". The caption contradicts both the header above it and the tasks below it ("this round" is a bracket, not a week).
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:932-940, :831-838; dynasty/dynasty/Domain/Enums/SeasonPhase.swift:88-94`
  - fix: `groupCaption(for:)` keys off `phase.group`, and `SeasonPhase.group` files `.playoffs` under `.regularSeason`. Special-case `.playoffs` (and `.tradeDeadline`) in `groupCaption` — e.g. "Each playoff round" — or split the group enum so the postseason carries its own cadence string.

- [ ] **Q-H85 · "TRADE DEADLINE · Oct" is still advertised as the next upcoming phase in Week 18**
  - evidence: 740_season_052 header: "2027 SEASON · WEEK 18 OF 18"; the band shows five played weeks and "18 VS PIT NOW". Directly under the current REGULAR SEASON block the rail lists "TRADE DEADLINE — Oct" as the next phase, with PLAYOFFS after it. Same on 740_season_044 (Week 17). The deadline is week 9 of 18 and is months gone; advancing from Week 18 goes straight to the playoffs.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:46-62, :157-163, :764-793; WeekAdvancer.swift:2409-2410, :2447-2448, :5564; TradeValueEngine.swift:54`
  - fix: `upcomingPhaseTasks` walks a static `orderedPhases` array in which `.tradeDeadline` always follows `.regularSeason`. Filter phases already behind the calendar: skip `.tradeDeadline` when `career.currentWeek > TradeValueEngine.deadlineWeek`, so the rail's next-phase preview matches `WeekAdvancer.nextPhase` (`.regularSeason → .playoffs`).


### Weekly press conference

- [ ] **Q-H86 · The two answers you didn't pick render at 1.34:1 contrast — the road-not-taken is unreadable at the exact moment it teaches**
  - evidence: After committing, the DIPLOMATIC line "We ride the hot hand. Ramiro Maddocks earned every one of those yards, but it stays a committee." and the FUNNY line "I might hand it to him 40 times next week. Somebody should probably warn his agent." are near-invisible. Pixel-sampled from the shot: brightest text pixel on the DIPLOMATIC quote is rgb(43,55,75) against card background rgb(22,33,53) = 1.34:1 contrast; the FUNNY quote measures 1.35:1. The chosen CONFIDENT quote on the same screen measures 4.54:1. WCAG AA needs 4.5:1 for body text and 3:1 even for large text. Their hint chips ("Locker room ↑ will back you", "Fans — muted") are equally faded.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:846,884,887`
  - fix: The dim is applied twice: line 846 sets foregroundStyle to Color.textTertiaryReadable (#7C8BA1) for isDisabled, and then line 884 multiplies the whole card by .opacity(0.4). Pick one. Keep the text at the readable token and signal "not chosen" with the container instead — drop the card fill/stroke, not the type. Post-commit is the one moment the player can compare what he said against what he passed on, so the alternatives need to stay legible.


### Press reaction

- [ ] **Q-H87 · The committed answer is framed in its tone colour, so the session's worst answer gets the app's positive green**
  - evidence: On 060 the answered DIPLOMATIC card carries a 2pt border sampled at RGB(28,140,77) — the same success green as the "↑ will back you" chip inside it — while that card's own chips read "Fans ↓ will groan" and "Media ↓ they'll pounce", and the ledger directly below reads "OWNER -2 · MORALE +5 · FANS -4 · MEDIA -11". On 048 the identical state (committed answer) is blue, because that tone is HUMBLE. So "this is the line you said" has no stable colour, and on 060 it borrows the exact hue the screen uses for good news.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:813,862-870,947-952,1727-1735`
  - fix: Give committed/picked a dedicated treatment that is not a semantic colour: keep the tone hue on the 4pt left rail only (PressConferenceView.swift:872-878) and use a neutral 2pt ring plus an explicit "SAID · ON THE RECORD" badge. Note the gold "Picked" label at line 845 also disappears at the moment the answer becomes permanent (isPending goes false), which is backwards.


### Press session summary

- [ ] **Q-H88 · dominantTone on a tied session is decided by Swift Dictionary iteration order — nondeterministic across launches**
  - evidence: 740_season_061's YOUR APPROACH reads "1 DIPLOMATIC · 1 HUMBLE · 1 CONFIDENT" — a perfect three-way tie. 740_season_050 reads "1 DIPLOMATIC · 1 HUMBLE" — a two-way tie. buildResult picks the winner with `toneCounts.max(by: { $0.value < $1.value })?.key ?? .diplomatic` (PressConferenceEngine.swift:434) over a [ResponseTone: Int] dictionary, whose iteration order is seeded per process, so `max` returns an arbitrary one of the tied tones and the same saved session can resolve differently on a relaunch. Two consumers depend on it: FranchiseIdentityDeclaration.amend at the intro presser — the identity all 31 other front offices price the player against (IntroSequenceView.swift:127) — and the summary headline (PressConferenceView.swift:1253), which the in-flight working-tree edit has just made derive from it.
  - code: `dynasty/dynasty/Engine/Media/PressConferenceEngine.swift:434`
  - fix: Give the tie a stated rule instead of a hash seed: iterate ResponseTone.allCases in a fixed order and take max by (count, priority), or break ties on the tone that moved media the most this session. Then say it on screen — with a 1-1-1 split the summary should read "no dominant tone" rather than silently crowning one, and FranchiseIdentityDeclaration should leave the seed alone on a tie the same way it already leaves it alone for .confident/.funny.


### Playoff hub

- [ ] **Q-H89 · Nothing on the screen offers to PLAY the playoff game — the only button names the next round**
  - evidence: On the Wild Card screen the three rail steps are "Prepare for Wild Card vs Denver Summit — Optional", "Review matchups — Optional", "Check injury report — Optional", and the single gold button reads "Advance to Divisional Round". Same shape on 064 ("Advance to Conference Championships") and 065 ("Advance to the Championship"). A reader with no manual sees three optional chores and one button that names a round they have not earned yet; the ten-second read is "the game plays itself, press gold to skip ahead".
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3755 (phaseHeroCard → playoffsHeroCard), :4152-4245 (playoffsHeroCard has no coach branch), :4041-4056 ("Coach the Game" exists only in regularSeasonHeroCard), :1035 (playoff quick chips), :591-596 + :340 (startCoachedGame guards on the stale currentWeekPlayerGame)`
  - fix: In the playoffs the primary control should name the game, not the destination — "Play the Wild Card vs DEN" (or a two-button row: "Coach the Game" gold / "Sim it" ghost, the same pairing the regular-season hero card uses at CareerDashboardView.swift:4050). The destination-name label is honest only after the game is played.

- [ ] **Q-H90 · The Conference round opponent is truncated to "Kansas Cit…" in the rail's only opponent label**
  - evidence: 065 rail: "Prepare for Conference Championships vs Kansas Cit…" — the club name is cut mid-word at the 2-line limit. On this screen that is the only full-name mention of the opponent: the OPPONENT SCOUT tile is wrong ("Vs JAX") and the band gives only the abbreviation "@ KC". 063 ("vs Denver Summit") and 064 ("vs New England Colonials") fit; the longest round name plus the longest club name is what overflows.
  - code: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:1561 (title: "Prepare for \(round) vs \(opponent)"); UI/Common/TimelineTasksPanel.swift:386-391 (.lineLimit(2), no minimumScaleFactor); UI/Career/CareerShellView.swift:2982 (round = "Conference Championships"), :3088 (opponent = full club name)`
  - fix: Task title is `.lineLimit(2)` at TimelineTasksPanel.swift:390 in a 300pt rail. Either shorten the generated title (TaskGenerator.swift:1559 builds "Prepare for \(round) vs \(opponent)" — use the round's short name "Conference Championship" and/or the club nickname), allow 3 lines for the playoff phase, or drop the round from the title since the phase header two rows above already says PLAYOFFS and the band says CONFERENCE.


### Season end

- [ ] **Q-H91 · Rail header calls the postseason "YOUR OFFSEASON", then "YOUR SEASON" one phase later — the caption under it says POSTSEASON both times**
  - evidence: 066: header reads "YOUR OFFSEASON  1/1" while the phase block directly beneath reads "ALL-STAR GAME · NOW · Feb / POSTSEASON · STEP 1 OF 2". 067 (next phase, same group): header reads "YOUR SEASON  2/2" over "THE CHAMPIONSHIP · NOW / POSTSEASON · STEP 2 OF 2". 069 flips back to "YOUR OFFSEASON  0/2". So the sequence a player walks is OFFSEASON → SEASON → OFFSEASON, and on 066/067 the header contradicts the caption 20pt below it.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:169-176 (seasonLabel) vs :933-941 (groupCaption); dynasty/dynasty/Domain/Enums/SeasonPhase.swift:96`
  - fix: `seasonLabel` lists `.superBowl` under "SEASON" but leaves `.proBowl` to the `default:` "OFFSEASON" branch, while `SeasonPhase.group` (Domain/Enums/SeasonPhase.swift:88) puts both in `.postseason`. Drive the header off `career.currentPhase.group.displayName` — the same source the caption already uses — so the two lines cannot disagree and "POSTSEASON" gets its own header instead of borrowing one of the other two.

- [ ] **Q-H92 · DIVISION card says "Season starts soon / Currently: Offseason" during the postseason — Week 1 is ~30 weeks away**
  - evidence: 066 and 067 are in POSTSEASON (rail: "POSTSEASON · STEP 1 OF 2", "POSTSEASON · STEP 2 OF 2", dated Feb), yet the DIVISION card reads "Season starts soon" / "Currently: Offseason". Two screens later, on 069, the same card in the LATER phase (Coaching Changes, also Feb) reads "Week 1 in ~28 weeks" — so the earlier screen claims imminence and the later one, correctly, claims 28 weeks. "Currently: Offseason" also contradicts the rail caption "POSTSEASON" on the same screen.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3204-3253 (isOffseasonPhase, weeksUntilWeek1, preSeasonCountdownRow)`
  - fix: `weeksUntilWeek1` has no case for `.proBowl` / `.superBowl`, so both fall to `default: return 0`, and `phaseLabel` in `preSeasonCountdownRow` (:3241) falls to `default: "Offseason"`. Add postseason cases (~30 weeks) and label them "All-Star Game" / "The Championship"; the "Season starts soon" copy should only fire at rosterCuts→Week 1.

- [ ] **Q-H93 · KEY PLAYERS labels the roster's highest-rated player "MVP" — he did not win MVP, he is just the top overall**
  - evidence: All three screens: "QB1  M. Wimberly  86 / MLB  Callum Abernathy  90 / MVP  Wade Braithwaite  93". "MVP" is a league award; here it is applied to whoever has the highest overall. The three row labels are also three different taxonomies rendered in identical gold — a depth slot (QB1), a position (MLB), and an award (MVP).
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2344-2352, :3468`
  - fix: The row is fed by `bestPlayer = players.max(by: { $0.overall < $1.overall })` (:3468) and hard-labelled `"MVP"`. Label it "TOP" or use the player's actual position like the row above it, and reserve "MVP" for a player who actually holds the award. Make all three labels one taxonomy (position) with the role as a suffix if needed.

- [ ] **Q-H94 · First-day onboarding mail is re-sent every offseason — "Welcome to the Houston Astronauts" arrives after a 14-3 season with the same club**
  - evidence: 069 inbox, all dated "Offseason - Coaching Changes, 2027": "League Office — Welcome to the Houston Astronauts" and "Yosef Estabrook — Welcome -- Roster Assessment Needed" flagged "⚠ Action Required". The same hub shows "SEASON RECAP 14-3 record", "Legacy: +85" and "Owner verdict: Outstanding" for the season this coach just finished with this club. The owner body reads "This is your franchise now. I trust your judgment... before the offseason really gets going" — first-day copy. The subject also uses a literal double hyphen ("Welcome -- Roster Assessment") rather than an em dash.
  - code: `dynasty/dynasty/Engine/Media/InboxEngine.swift:34-38, :110-138, :203-227; dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:4713-4723`
  - fix: `coachingChangesMessages` is unconditional — it does not even take `career`, so it cannot know this is year N. Gate the two welcome messages on first season with the club (career.seasonsWithTeam == 0) and write a returning-coach variant for every later year ("Year two plan", referencing last season's record). Fix the `--` to an em dash while in there.


### Training camp — training focus

- [ ] **Q-H95 · Every pick past #224 is an automatic A+ STEAL — the consensus window caps a round at 32 picks while comp picks renumber the draft to ~256**
  - evidence: Row: "R7 · #252  K  Roman Nadeau  C−/B ↘ 53" carries the chip "Press A+ · STEAL" — a kicker whose staff evaluation came in BELOW the band he was shown, graded the best possible pick in the draft. `PickGradeCalculator.letterGrade` returns `.stealAPlus` whenever `valueDelta >= 12`. `DraftIntel.consensusWindow` builds that delta against `let late = round * picksPerRound` with `picksPerRound = 32`, so a round-7-projected prospect's window ends at #224. `CompensatoryPickEngine.applyAwards` splices comp picks in and "renumbers the whole thing 1…N" (DraftEngine.swift:1700-1704 says a normal year runs ~230-256) — hence a real R7 pick numbered #252. Every pick from #237 onward therefore scores valueDelta ≥ 12 regardless of the player.
  - code: `dynasty/dynasty/Engine/Draft/DraftIntel.swift:218, 236-238; PickGradeCalculator.swift:110-112; Engine/Contract/CompensatoryPickEngine.swift:213-223; Engine/Scouting/DraftClassBuilder.swift:402, 639`
  - fix: `consensusWindow` must derive a round's late bound from the actual pick pool (the real last pick number of that round after `applyAwards`), not from the fixed 32×round arithmetic. Symptom on screen: all 11 rows carry the identical "Press A+ · STEAL" chip, which averages to "CLASS GRADE A+" and the press line "No selection was graded a reach" — the grade carries zero information.

- [ ] **Q-H96 · Two different Houston players are both named Kaleo Hinsdale — rookie names are only de-duplicated inside their own draft class**
  - evidence: This screen: "R2 · #62  LG  Kaleo Hinsdale  C+/B ↘ 59" (Houston's 2028 class). camp_08_training_plan.png, same team, six minutes later: "KEY PLAYERS · QB1 Kaleo Hinsdale 53" and LOCKER ROOM "QB Hinsdale". Different position, different OVR — two distinct rows sharing a full name on one roster. Same pool exhaustion is visible elsewhere: three Tanguays in an 11-man class (Osman RT, Harlan RB, Wade DT), and camp_09 shows Kenji Marchetti, Kenji Vandenberg and Kenji Hopewell plus Orrin Hopewell in 13 visible rows.
  - code: `dynasty/dynasty/Engine/Scouting/DraftClassBuilder.swift:157, 595; Data/Import/LeagueGenerator.swift:656; Data/Import/RandomNameGenerator.swift:31/65 (55 × 55 pool), 102-124`
  - fix: `var usedNames: Set<String> = []` is seeded empty and holds only this class's 350 draws, so a rookie can collide exactly with a man already in the league; `LeagueGenerator` (Data/Import/LeagueGenerator.swift:656) uses plain `randomName()` with no uniqueness at all against ~1,700 players and a 55×55 = 3,025 pair space. Seed `usedNames` from every existing Player and Coach full name before building a class, and route league generation through `uniqueName(used:)` too. Every roster, depth-chart, trade and transaction screen identifies players by full name.


### Training camp — position battles

- [ ] **Q-H97 · All 11 rookies carry the identical "Press A+ · STEAL" chip while 8 of 11 came in BELOW their own pre-camp band**
  - evidence: Every row on both shots ends in the same green chip: "Press A+ · STEAL" — 11 of 11, from R1 · #30 down to R7 · #252. The same rows show the ↘ arrow (RookieFog.Verdict.below, "Below the report") on 8 of them, and OVRs of 58, 59, 61, 59, 61, 58, 59, 58, 59, 57, 53 — nine printed in danger red. The header then averages those chips into "A+ / CLASS GRADE" and the press verdict claims "No selection was graded a reach." Root cause: PickGradeCalculator.letterGrade returns .stealAPlus on `valueDelta >= 12` with no other condition, and DraftIntel.consensusWindow turns a media "round N" projection into a band whose late edge is `round * 32` — so any prospect taken one round past his projection clears +12 automatically. RookieClassReveal.points scores every stealAPlus at 4.3 and letterForAverage returns "A+" at 4.15+, so an all-STEAL class is A+ by construction. A chip that fires on 11 of 11 picks carries no information, and it directly contradicts the only real data on the same screen.
  - code: `dynasty/dynasty/Engine/Draft/PickGradeCalculator.swift:112`
  - fix: Gate the unconditional steal on player quality as well as board slide (e.g. also require publicOVR at or above the round's band centre), and widen the round-band tolerance so a one-round slide is SOLID rather than a STEAL. Independently, add a test asserting a realistic 11-pick class does not return the same PickGrade for every pick.


### Training camp — practice picker

- [ ] **Q-H98 · Off-Day Practice card advertises Scheme +4 / LR −2 / Inj +4% while the engine config for the same option is +2 / −3 / +3%**
  - evidence: Three of the four cards on screen quote numbers that match VoluntaryWorkoutEngine.config exactly — Voluntary OTAs "Scheme +3 · LR +2 · Inj +0%", Mandatory Minicamp "Scheme +5 · LR −5 · Inj +2%", Saturday Film "Scheme +1 · LR +0 · Inj +0%" — so the player has every reason to trust the fourth. It is the one that diverges: VoluntaryWorkoutPrompt.swift:144 returns Config(schemeBonus: 4, lrDelta: -2, injuryRiskBoost: 4, participationPct: 80) for .offDayPractice, while VoluntaryWorkoutEngine.swift:96 returns (schemeBonus: 2, lrDelta: -3, injuryRiskBoost: 3) and VoluntaryWorkoutEngine.swift:28 uses baseAttendance 0.55 against the UI's 80. VoluntaryWorkoutEngine.apply then overwrites the stored row with its own config (`workout.schemeBonus = cfg.schemeBonus`), so the card promises double the scheme gain and understates the morale hit. The UI's own comment admits the duplication: "Local config — mirrors the canonical VoluntaryWorkoutEngine.config(for:) values".
  - code: `dynasty/dynasty/UI/Camp/VoluntaryWorkoutPrompt.swift:144`
  - fix: Delete VoluntaryWorkoutPrompt.Config and read VoluntaryWorkoutEngine.config(for:) / the engine's baseAttendance table directly, so the card cannot drift from the effect again. Add a test that asserts the numbers rendered on each card equal the engine's config for that type.

- [ ] **Q-H99 · "Saturday Film" is strictly dominated by "Voluntary OTAs" on every axis the card shows**
  - evidence: Voluntary OTAs: "Scheme +3 · LR +2 · Inj +0%". Saturday Film: "Scheme +1 · LR +0 · Inj +0%". Less scheme, less locker room, identical injury cost — there is no axis on which Film wins, and nothing on the card compensates. The only differentiator the engine models is participationPct (70 vs 40, VoluntaryWorkoutPrompt.swift:138-143), which is never displayed and also favours OTAs. A 100th-visit player picks OTAs or Minicamp forever and Film is dead UI. Madden's OTA intensity slider and OOTP's spring-training settings both make the cheap option cheap in a currency the expensive one spends (fatigue, snap counts); here nothing is spent.
  - code: `dynasty/dynasty/UI/Camp/VoluntaryWorkoutPrompt.swift:138`
  - fix: Give Film a real edge in a currency OTAs lack — e.g. mental/awareness gain instead of scheme, or a fatigue/cumulativeLoad *reduction* (a recovery week) — or cut the option to three. Surface participationPct on the card so "only 40% show" is a visible cost of the cheap option.


### Training camp — training focus

- [ ] **Q-H100 · The focus split never reaches the workload engine — "Camp Hard" and "Recovery Mode" cannot change a single number in the table under them**
  - evidence: The screen stacks "Physical 33% — S&C + conditioning → stamina, durability" directly above a "PER-PLAYER WORKLOAD" table with LOAD / STATE / INJ columns, and offers presets literally named "Camp Hard" (20/50/30) and "Recovery Mode" (40/15/45). The camp sim computes load as `let intensity = campIntensity(for: phase)` — a function of the phase alone (`.trainingCamp: return 0.85`). The saved `TrainingPlan` is passed only to `TrainingPlanEngine.applyWeekly` (attribute deltas); `plan.physicalPct` is never passed to `WorkloadEngine.tickDay`. So no slider position and no preset can move `cumulativeLoad`, `workloadStatus`, the LOAD bars, the STATE pills, the INJ column, or the Hub's "0% overloaded".
  - code: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:8546, 8552-8561, 8634-8641; Engine/Camp/WorkloadEngine.swift:108-135`
  - fix: Feed the plan into intensity, e.g. `campIntensity(for: phase) * loadFactor(plan.physicalPct)`, so Recovery Mode actually recovers and Camp Hard actually costs something. Until it does, either drop the two intensity-flavoured preset names (they promise a dimension the model has none of) or stop rendering the workload table on this screen — right now the layout asserts a causal link the engine does not implement. Reference: FM's training-intensity matrix and Madden's rep-count slider both bind the same control to both development AND fatigue; here only development is bound.

- [ ] **Q-H101 · "PER-PLAYER WORKLOAD" silently shows an arbitrary 30 of ~87 players, unsorted**
  - evidence: The section header reads "PER-PLAYER WORKLOAD" with no count and no "see all". The view renders `Array(roster.prefix(30))` — comment: "Limit roster preview to first 30 to keep ScrollView responsive on iPad." The left rail on camp_08 puts the roster at 87. The 13 visible rows are in no order at all (C, CB, CB, DE, WR, LT, DT, RT, OLB, DT, QB, MLB) — not by position, OVR, load or risk — so the 30 that survive the prefix are an arbitrary slice, and the burnout risk this screen exists to surface may live entirely in the 57 that are cut off.
  - code: `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:352-355 (prefix), 237-268 (header/ForEach); CareerShellView.swift:2099, 2325-2329 (unsorted roster passed in)`
  - fix: Sort by risk descending (workloadStatus, then cumulativeLoad, then durability) before any truncation, label the header "30 of 87 — highest load first", and add sort/filter controls plus a "show all" so a 100th-visit GM can jump to his fragile starters. A LazyVStack removes the performance justification for the prefix entirely.


### Roster cuts — cut to 75

- [ ] **Q-H102 · Markdown **bold** emphasis in the action-bar explainer renders completely flat — the design system's documented emphasis mechanism is dead**
  - evidence: camp_10 bottom bar reads "You are 12 over the 75-man limit. Tap a player to mark him for release." The source is "You are **\(remaining) over** the \(stage.target)-man limit…", so "12 over" should be bold and "75-man" should not. Measured on the pixels: the 'e' inside the bold span (in "over", x 234-247) has 131 ink pixels / brightness sum 26844; the 'e' outside any span (in "the", x 296-309) has 130 px / 26792 — a 0.8% difference, both 14 px wide. Stem widths are identical too: the '1' of the bold "12" is 3 px (x 169-171), the 'l' of the unbolded "limit" is 3 px (x 433-435). Same on camp_11: "Frees $7.6M and leaves $1.9M of dead money." is uniform weight although both money figures are wrapped in **. The asterisks ARE consumed (none appear on screen), so LocalizedStringKey parses the markdown and the font then discards the strong-emphasis trait.
  - code: `dynasty/dynasty/UI/Common/DSActionBar.swift:113`
  - fix: DSActionBar.swift:113 renders Text(LocalizedStringKey(message)) under .font(DSType.text(DSType.Size.body, .medium)), which is Font.system(size:weight:).monospacedDigit() — the .monospacedDigit() modifier drops the inline .stronglyEmphasized trait. Build the line as AttributedString(markdown:) and set the bold run's font explicitly, or drop .monospacedDigit() on prose explainers (DSType.text(..., prose: true) already does). The contract is documented at DSActionBar.swift:31-32 ("Markdown is honoured, so a call site emphasises the load-bearing nouns with **…**") and RosterCutView alone has six call sites relying on it — add a snapshot test that asserts the bold run actually resolves.

- [ ] **Q-H103 · The PS button is a 27.5 × 18.5 pt tap target nested inside a 58 pt row whose own tap gesture is the destructive one**
  - evidence: Measured on camp_10: the PS chip fill (#1C2940, backgroundTertiary) spans x 1952-2006 and y 819-855 = 55 × 37 px at 2x = 27.5 × 18.5 pt. The row card it sits in is 116 px = 58 pt tall and its whole area is a .contentShape(Rectangle()) + .onTapGesture that marks the player for RELEASE. A finger that misses an 18.5 pt-tall chip by a few points commits the irreversible action instead of the reversible one.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:330`
  - fix: The Button at RosterCutView.swift:317-338 uses .buttonStyle(.plain) with only .padding(.horizontal, 8)/.padding(.vertical, 3) and no minimum frame. Give it .frame(minWidth: 44, minHeight: 44) with the visible chip centred inside, or move the practice-squad flag out of the row entirely (a swipe action, or a second column in the marked-players review) so a small control never shares a hit area with a destructive one.

- [ ] **Q-H104 · Camp grade is painted one flat gold for every grade — a "Camp C" and a "Camp D" are pixel-identical — while the OVR beside it IS colour-coded, in a second, different gold**
  - evidence: Sampled from camp_10: Orrin Hopewell's "Camp D" = RGB(201,169,78) #C9A94E; Isaias Laurelwood's "Camp C" = RGB(201,169,78) — byte-identical. On Harlan Shelburne's single 11 pt metadata line, "OVR 65" = RGB(234,179,8) #EAB308 and "Camp D" = #C9A94E, 160 px apart — two different golds on one line. OVR is tiered (OVR 54/58 red, OVR 61/64/65 #EAB308, OVR 71-79 blue, OVR 84 green #22C55E) but camp grade is not tiered at all. The same #C9A94E is the screen's primary CTA fill ("Release 12 players", sampled RGB(163,139,66)) and the step-1 underline. Distribution is also flat: 8 of the 9 visible grades are "Camp D", one is "Camp C".
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:293`
  - fix: RosterCutView.swift:291-293 sets .foregroundStyle(Color.accentGold) unconditionally. Route the grade through the existing five-tier ladder (Color.forRatingTier) so A+/A read green, B/C read blue/neutral and D/F read danger — camp grade is the one piece of information this phase actually generated and it is the screen's decision input. Then stop using accentGold for a per-row value at all: on this screen gold is the CTA and the current-step underline, and a row-level D badge in the CTA colour is the colour-discipline break. Separately, check the grade curve — 8 D's in 9 graded rows means the grade carries almost no signal.

- [ ] **Q-H105 · The "PS" chip is a live toggle on all 87 rows that does nothing unless the man is also marked for release, and it silently discards its own state**
  - evidence: Every row in camp_10/11/12 carries a "PS" chip. It is a real Button (togglePracticeSquad) that fills accentBlue and re-labels to "PS ✓" on tap — but practiceSquadIDs is independent of selectedIDs, only practiceSquadIDs.intersection(selectedIDs) is ever counted into the explainer or the result sheet, and performCuts ends with practiceSquadIDs.removeAll(). So flagging a man you keep gives persistent visual confirmation for a no-op that is then wiped. There is also no eligibility rule: the chip is offered identically on the 32-year-old OVR 75 DT Kenji Vandenberg, the OVR 84 age 23 Isaias Laurelwood, and a 22-year-old camp body. And "PS" is never expanded anywhere on the screen.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:317`
  - fix: Either gate the chip on selection (show it only on marked rows, where it means something) or make the flag persist and mean something for kept players too. Add a real eligibility predicate — the engine already tracks yearsPro and rosterStatus — and grey/omit the chip for ineligible men with the same in-row reason treatment releaseBlockReason already uses. Expand the jargon: label it "Stash on PS" or add a one-line legend under the filter chips.

- [ ] **Q-H106 · Half the marked men price at "+$0.0M" and carry no camp grade, with nothing on screen explaining either — the engine's camp-body status is modelled but never surfaced**
  - evidence: In camp_10/11, six of the twelve marked rows read "+$0.0M": Tobias Crisanti (CB, OVR 73, Age 29), Jaden Ogletree (CB, 58, 24), Alaric Colgrove (DE, 71, 27), Callum Lovegrove (DT, OVR 79, Age 29), Kenji Vandenberg (DT, 75, 32) and Kenji Hopewell (QB, 75, 28). Those are exactly the six rows that also show no "Camp X" chip — every row with a non-zero figure (Orrin Hopewell +$0.7M, Isaias Laurelwood +$4.9M, Wade Hedgepeth +$3.1M, Kason Maddocks +$1.3M, Harlan Shelburne +$1.1M, Seneca Crisanti +$0.8M) has one. Cutting an OVR 79 DT frees $0.0M and cutting an OVR 58 CB frees $0.0M — the money column is dead information for exactly the population the cut ladder exists to trim, and "+$0.0M" is visually indistinguishable from a fully guaranteed veteran deal that genuinely frees nothing.
  - code: `dynasty/dynasty/Engine/Contract/CapManagementEngine.swift:464`
  - fix: CapManagementEngine.releaseCapSplit returns an all-zero split when CampRosterEngine.isCampBody(player) (CapManagementEngine.swift:464-468) — correct, and deliberately so, but the row never says it. Add a "CAMP" badge to camp-body rows (Player.rosterStatus is already loaded) and replace "+$0.0M" with "Cap-free" or "—" for them, so a real $0 relief on a guaranteed vet deal stays distinguishable. And decide whether camp bodies should be graded at all: applyCampGrades (WeekAdvancer.swift:8739) grades the whole roster but only runs on entry to .rosterCuts, so at the cut-to-75 rung the men brought in FOR camp show neither a price nor an evaluation.

- [ ] **Q-H107 · The engine scores every man for cut priority for the AI, and never offers that to the player**
  - evidence: RosterCutEvaluator.recommendCuts scores the whole roster on a keep axis and applies a depth filter, and the AI's cutdown consumes it. RosterCutView mentions it only inside a comment ("the AI's trim reads the same table through recommendCuts", line 613) and never calls it. On screen there is no "auto-fill recommended cuts" button, no "suggested cut" badge on any row, and no keep-score column — camp_10's bar just says "Tap a player to mark him for release" over 87 unranked rows, and the player repeats that 12 times, then 10, then 12 across three visits.
  - code: `dynasty/dynasty/Engine/Camp/RosterCutEvaluator.swift:21`
  - fix: Add a secondary bar action "Suggest 12" that seeds selectedIDs from RosterCutEvaluator.recommendCuts(roster:targetCount:modelContext:) so the player edits a plan instead of building one, and show the keep-score rank as a per-row chip so a hardcore player can see WHY a man is bottom-12. Madden's cut-day "recommended cuts" and OOTP's auto-roster are the references; the whole trade-off (my judgement vs the staff's) only exists once the staff's answer is on screen.

- [ ] **Q-H108 · 87 rows in arbitrary database order — no sort, no search, and the nine position filter chips carry no counts**
  - evidence: Down the visible list the OVR runs 64, 73, 58, 71, 54, 61, 79, 84, 78, 75, 75, 73, 65, 61 — not sorted by rating. Surnames run Hopewell, Crisanti, Ogletree, Colgrove, Marchetti, Shelburne, Lovegrove, Laurelwood, Hedgepeth, Vandenberg, Hopewell, Maddocks, Shelburne, Crisanti — not alphabetical. Positions run C, CB, CB, DE, WR, LT, DT, RT, OLB, DT, QB, MLB, OLB, CB — not grouped. The filter row reads "All | QB | RB / FB | WR / TE | OL | DL | LB | DB | ST" with no count on any chip, so nothing tells you a room's size before you tap into it. On a 100th visit this is 87 rows scanned by eye, three times per cutdown.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:606`
  - fix: filteredRoster (RosterCutView.swift:605-607) applies only .filter with no .sorted, and liveRoster comes from an unsorted FetchDescriptor (loadLedger, ~line 750). Sort by cut priority (RosterCutEvaluator.keepScore) by default, and add a sort control for OVR / age / cap saving / camp grade. Put a live count on each CutPositionGroup chip ("DL 14") — CutPositionGroup.label at RosterCutView.swift:1073-1085 is a bare string today. FM's squad screen is the reference: sortable columns plus a persistent depth readout.

- [ ] **Q-H109 · The ladder band mixes committed and pending state — "87 on the roster · 0 more to release" and "12 spent" while nothing has been committed**
  - evidence: camp_11 and camp_12 show, in one viewport: slat subcaption "87 on the roster · 0 more to release" (87 is the live uncommitted roster; 0 is the selection-adjusted remainder), meter "12 spent · 0 left" (nothing has been spent — no release is booked until the alert is confirmed), and the action bar "RELEASE 12 — 75 LEFT ON THE ROSTER". Read literally the subcaption says the club has 87 men, a 75-man target, and owes nothing. camp_10 shows the same widgets in the consistent pre-selection state ("87 on the roster · 12 more to release", "0 spent · 12 left").
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:186`
  - fix: currentSubcaption (RosterCutView.swift:185-188) concatenates activeRoster.count — a committed fact — with `remaining` = max(0, activeRoster.count - selectedIDs.count - stage.target), a projected one. Put both halves on the same basis: "87 on the roster · 12 marked · 75 after" while a selection is live, or project the count too ("75 after these cuts · 0 more to release"). Same for the meter: DSResourceMeter's "spent" wording (DSSlatBand.swift:326) is wrong for an uncommitted selection — say "12 marked · 0 left".


### Roster cuts — release result

- [ ] **Q-H110 · Position depth — the actual decision variable — is only revealed inside the final confirm alert, after all twelve men are already picked**
  - evidence: The camp_12 alert reads "Position groups after this: C 3 → 2 · CB 10 → 8 · DE 8 → 7 · DT 6 → 4 · LT 3 → 2 · MLB 4 → 3 · OLB 6 → 4 · QB 3 → 2 · WR 10 → 9." Nine before/after room counts, all derivable from data the screen has held since it loaded (RosterCutEvaluator.positionImpacts), shown for the first time after the player has hand-picked twelve men. Nothing on camp_10 or camp_11 shows a room's size: the filter chips are bare labels and the rows carry only OVR / Age / Camp grade.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:648`
  - fix: Move the depth table out of confirmMessage (RosterCutView.swift:648-665) and onto the list screen: a persistent strip above the rows showing each room's current count and its live count after the marks, turning red as a room approaches RosterCutEvaluator.minimumCount. The confirm alert should then only have to repeat the rooms that changed. Also note the floors are 1 per position and 2 at QB (RosterCutEvaluator.swift:136-139), so "C 3 → 2" and "QB 3 → 2" raise no warning at all — a cut to 53 with one centre is legal by this rule.


### Lineup Incomplete dialog

- [ ] **Q-H111 · The gold "Advance" CTA renders as ready with every visible requirement ticked, then refuses after the tap**
  - evidence: camp_13 sidebar: both non-optional rows are struck through with green checks ("Set training focus", "Cut to 75"), the four remaining rows are all prefixed "Optional ·", and "Advance to Preseason" is a full-width solid-gold enabled button. Tapping it produces the "Lineup Incomplete" modal. Training Camp has no depth-chart task at all — `trainingCampTasks` is focus / camp grades / battles / workload / storylines — so nothing on the screen hinted the chart was the gate. cuts_01 is the same shape with "Advance to Roster Cuts". The panel already has the mechanism to prevent this: `advanceBlocker` draws a named blocker banner over a disabled button, but it is fed only by `staffLedger.advanceBlocker(phase:)` — the lineup, roster-limit, cap and preseason-slate gates never populate it.
  - code: `dynasty/dynasty/UI/Career/CareerShellView.swift:1454-1466,2594; dynasty/dynasty/UI/Common/CalendarSidebarView.swift:55`
  - fix: Compute the lineup gap in the same pass that computes `staffAdvanceBlocker` and pass it as an `AdvanceBlocker(title: "Lineup incomplete", detail: "3 starting slots unassigned — Wide Receiver 3, Left OLB, Right OLB")`. The button then greys out and names its own blocker before the tap, which is exactly the behaviour #154f/#193 wrote that type for. Do the same for the roster-limit and cap gates so all four refusals are pre-tap.

- [ ] **Q-H112 · "Review camp grades" is a Training Camp task for data that does not exist until Roster Cuts, and it opens a screen that never renders it**
  - evidence: camp_13 sidebar: "Review camp grades ›  Optional · See which players are earning roster spots based on camp performance." The hero card on the SAME screen says "Top camp grade — Not graded yet". cuts_01 repeats it a phase later: "Camp standouts — None graded yet". `applyCampGrades` has exactly one call site — `case .rosterCuts` — so no `Player.campGrade` exists during Training Camp or Preseason at all. The task's destination is `.roster`, and `Player.campGrade` is read in only three views (campGradesTile, WorkloadDashboard, RosterCutView) — never RosterView. The codebase already deleted the identical quick-action chip for this reason: "'Camp Grades' → `.roster`, which never renders `Player.campGrade`."
  - code: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:1221-1229; dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:4256-4258`
  - fix: Two fixes, both needed. (1) Point the task at `.workloadDashboard`, the one screen that renders a camp grade before the cut room. (2) Grade continuously — call `applyCampGrades` on every camp week tick, not only at `.rosterCuts`, so "Top camp grade" and "Camp standouts" carry a name from week 1 and the camp actually pays off before the decision it is supposed to inform. If grading mid-camp is not wanted, drop the task and the two hero rows entirely rather than shipping three permanent "not graded yet" strings.

- [ ] **Q-H113 · "Resolve position battles" opens the Depth Chart, which contains no position-battle UI anywhere**
  - evidence: camp_13 sidebar: "Resolve position battles ›  Optional · Track daily winners in position competitions and lock in starters." Its destination is `.depthChart`. camp_14 is that screen: Quarterbacks / Backfield / Receivers slot cards, a TEAM 78 bar and three tabs — no battle, no daily winner, no "lock in starters" control. `grep 'attle' DepthChartView.swift` returns zero matches. The real route is the dashboard's own Position Battles tile → `PositionBattleSheet`, and the codebase already removed the parallel chip with that reasoning: "'Battles' → `.roster`, and camp battles are not on the roster screen at all: they live in this dashboard's own Position Battles tile."
  - code: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:1230-1237; dynasty/dynasty/UI/Career/CareerDashboardView.swift:1000-1002`
  - fix: There is no `TaskDestination` that reaches a battle without one being chosen, which is why the chip was deleted. Either add a `.positionBattles` destination that lands on a list of the open battles (the tile currently caps at 3 rows plus "+ 6 more", so a full list is needed regardless), or remove the task and let the tile be the only route — but do not leave a chevron row promising a screen that cannot service its own label.


### Depth chart after Auto-Set

- [ ] **Q-H114 · The blocking dialog names "Auto-Set" but the Depth Chart's Auto-Set button ships as a bare, unlabelled white wand glyph**
  - evidence: camp_13 / cuts_01 dialog body: "Open the depth chart and assign them — Auto-Set fills every empty slot in one tap." Tapping "Go to Depth Chart" lands on camp_14, where the only toolbar control is a circular button in the top-right containing a wand-and-stars glyph, rendered white, with no text. The words "Auto-Set" appear nowhere on the destination screen. The source says the opposite is required: "`.labelStyle(.titleAndIcon)` is load-bearing: a toolbar `Label` collapses to icon-only by default, and a bare wand glyph in the corner is not a discoverable action for a first-time manager staring at eleven empty slots." Both the title AND the `.foregroundStyle(Color.accentGold)` are lost at runtime.
  - code: `dynasty/dynasty/UI/Roster/DepthChartView.swift:159-160,356-366`
  - fix: A toolbar Label collapses to icon-only under the iOS 26 toolbar regardless of labelStyle. Stop relying on Label collapsing behaviour: render `Button { applyAutoSet() } label: { HStack { Image(systemName: "wand.and.stars"); Text("Auto-Set") } }` with an explicit `.tint(Color.accentGold)`, or move it out of the toolbar into a gold pill on the team-overall bar next to "TEAM 78". Verify with a screenshot, not with the code — this is the second time the label has been lost.

- [ ] **Q-H115 · Depth chart prints "$0M" for every player under $1M — 8 of the 12 visible rows, including the starting QB**
  - evidence: "Davion Maddocks / QB Age 27 $0M" (STARTER, 73 OVR), "Kaleo Hinsdale / QB Age 25 $0M", "Brixton Yarborough / RB Age 24 $0M", "Ezekiel Ferrante / RB Age 24 $0M", "Nehemiah Lockridge / FB Age 23 $0M", "Alonso Hinsdale / WR Age 29 $0M", "Odalric Crisanti / WR Age 29 $0M". Cause is integer truncation: `Text("$\(player.annualSalary / 1000)M")` where `annualSalary` is documented as "Annual salary in thousands (e.g., 15000 = $15M)" and the Player default is 750. 750/1000 = 0. The same magnitude renders correctly elsewhere in the build: cuts_01's CONTRACTS card shows "RG Ogletree 81 $848K". Non-zero values are floor-truncated too, so "$2M" could be anything from $2.0M to $2.9M.
  - code: `dynasty/dynasty/UI/Roster/DepthChartView.swift:731`
  - fix: Replace with the formatter the app already owns: `Text(CommittedCapLedger.money(player.annualSalary))` (Engine/Contract/CommittedCapLedger.swift:663), which yields "$750K" / "$12.5M". Grep for the same `/ 1000)M` pattern — it also appears in CareerShellView.swift:1362, HoldoutDialog.swift:23 and FAWeeklyView.swift:2398.


### Career hub (roster cuts)

- [ ] **Q-H116 · "Finalize depth chart" is labelled Optional but hard-blocks the Advance button**
  - evidence: The rail row reads "Finalize depth chart / Optional · Lock in starters and backups before final roster cuts begin." with a hollow (not-required) bullet. Tapping the screen's one primary button, "Advance to Roster Cuts", raises a blocking alert: "Lineup Incomplete / Offense: Left Guard unassigned / Offense: Right Tackle unassigned / Defense: Free Safety unassigned". The task the gate refuses on is the one the rail calls optional.
  - code: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:1304 + dynasty/dynasty/UI/Career/CareerShellView.swift:1454`
  - fix: Either make the row required (isRequired: true) so the red bullet warns before the tap, or downgrade the gate to a warning that offers "Advance anyway". Right now TaskGenerator.swift:1304 ships isRequired:false while CareerShellView.swift:1454-1466 does `pendingDepthChartGap = ...; return` — a hard refusal. One of the two has to move.

- [ ] **Q-H117 · "Camp standouts: None graded yet" is false — camp IS graded, there are just no A grades**
  - evidence: The Preseason hero card reads "Camp standouts — None graded yet". Two screens later the cut list shows "Camp D" on 9 of the 14 visible players (Tanguay, Abernathy, Lockridge, Colgrove, Hopewell, Vestergaard, Goddard, Hinsdale, Bonaventure-row group). Grades exist; the hub says they don't.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3954`
  - fix: `standouts` is `topCampGraded.count`, and topCampGraded (line 1436) filters to `.aPlus || .a` only. So zero standouts renders as "None graded yet". Change the empty copy to "No A grades — N graded" and only say "not graded yet" when every campGrade is nil. The campGradesTile repeats the same lie with "Not graded yet / Grades land during Training Camp".


### Roster cuts — cut to 53

- [ ] **Q-H118 · The PS toggle is a ~34x19pt target embedded in a whole-row tap that marks a man for release**
  - evidence: Every row carries a small "PS" chip at the far right under the cap figure, while the action bar reads "NOBODY SELECTED / You are 12 over the 53-man limit. Tap a player to mark him for release." A miss on the PS chip lands on the row and selects the player for an irreversible release. Same on cuts_02.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:316`
  - fix: The PS Button is 11pt text with `.padding(.horizontal, DSSpacing.xs)` (8) and `.padding(.vertical, 3)` — roughly 34x19pt, well under the 44pt minimum — and the row wraps it in `.contentShape(Rectangle()).onTapGesture { toggleSelection(player) }` (lines 356-359). Give the chip `.frame(minWidth: 44, minHeight: 44)` with the visual pill inset, or move PS flagging into the confirm sheet where release is already the committed intent.

- [ ] **Q-H119 · The cut list is unsorted and the engine's cut recommendation is dead code**
  - evidence: With "12 more to release" from 65, the All list runs OVR 72, 72, 90, 69, 79, 78, 66, 81, 57, 78, 79, 66, 65, 54 — no order at all. Row 3 is "MLB Callum Abernathy OVR 90 Age 32", the same man the hub's KEY PLAYERS tile lists at 90. There is no sort control, no "suggested cuts", no bubble ranking — only nine position filter chips.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:605 + dynasty/dynasty/Engine/Camp/RosterCutEvaluator.swift:21`
  - fix: `filteredRoster` is `activeRoster.filter { positionGroup.includes($0.position) }` with no `.sorted`. Meanwhile RosterCutEvaluator.recommendCuts (RosterCutEvaluator.swift:21) and its keepScore — OVR, camp grade, age, salary, dead cap, injury, dramaQueen archetype — are referenced nowhere in the app except a comment at RosterCutView.swift:613. Sort ascending by keepScore by default and show the score (or a Keep/Bubble/Cut band) per row; that is the whole decision the engine already models.


### Lineup Incomplete dialog

- [ ] **Q-H120 · Position Battles counts and renders one-man battles after the cutdown — the same surname printed twice on one row**
  - evidence: cuts_01 POSITION BATTLES: "9 active", then "CB  Broadwater                Broadwater ›" and "DE  Frobisher                 Frobisher ›" — one name in the matchup column, the same name again in the green leader chip, no "vs". camp_13 (before the cut to 65) shows the healthy shape of the same row: "CB  Broadwater vs Klingman     Klingman ›". The tile keeps any battle where ANY ONE competitor is still on the roster, the competitor set is frozen at detection ("The incumbent row keeps the competitor set it was opened with"), and the row joins `roster.prefix(2)` with " vs " — so releasing one of two contenders leaves a solo "battle" that still counts toward "9 active".
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1352,1398-1399`
  - fix: In `loadPositionBattles`, require at least two surviving competitors: `.filter { battle in battle.competitorIDs.filter(rosterIDs.contains).count >= 2 }`. A battle that drops to one man has been decided by the cut — resolve it (set `winnerID` to the survivor) rather than hiding it, so the player gets the payoff of "Broadwater won the job" instead of the row silently vanishing.


### Roster cuts — practice squad

- [ ] **Q-H121 · "Flag practice-squad keepers" opens the identical cut screen and never counts flags against the 16/6/3 caps the engine enforces**
  - evidence: cuts_02 is the same screen as cuts_01 pixel for pixel — same "CUT DAY 3 OF 3", same "3 CUT TO 53 / 65 on the roster · 12 more to release", same list, same "0 spent · 12 left". Nothing on it mentions the practice squad except an unlabelled "PS" chip repeated on all 14 rows: no "0 / 16", no veteran-slot counter, no note that a flag only takes effect on a man you release.
  - code: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:1353 + dynasty/dynasty/UI/Camp/RosterCutView.swift:677`
  - fix: The task ships `destination: .rosterCuts`, identical to "Cut to 53". Downstream, PracticeSquadEngine enforces squadSize 16, veteranSlots 6, maxPerPosition 3, maxQuarterbacks 2, and userFlaggedKeepers does `Set(cuts.prefix(squadSize)...)` — flags past 16 are silently dropped. RosterCutView has no reference to any of those numbers. Put a live "PS 4/16 · vet 1/6" readout in the band and disable the chip when a cap is hit.


### Draft — pick result

- [ ] **Q-H122 · Every slide fires TWO near-identical feed rows — the "slide ends" beat and the "steal" beat quote the same three numbers**
  - evidence: draft_01 LIVE FEED, rows 1 and 2: "J. Winchester's slide ends at #51 — The mock had him at #19. He fell 32 picks past it — HOU let him come to them. #51" immediately followed by "HOU steal K J. Winchester — Consensus board had him #19; he lasted to #51 — 32 slots of value. #51". Same #19, same #51, same 32. Rows 4 and 5 repeat it exactly: "B. Vanterpool's slide ends at #49 — The mock had him at #29. He fell 20 picks past it — ATL let him come to them." then "ATL steal OLB B. Vanterpool — Consensus board had him #29; he lasted to #49 — 20 slots of value." Four of the nine visible feed rows are two events told twice.
  - code: `dynasty/dynasty/UI/Draft/DraftDayCoordinator.swift:1913-1921 and :1943-1966; DraftIntel.swift:288-297; PickGradeCalculator.swift letterGrade`
  - fix: `recordStoryBeats` runs the value block (step 1, `.stealAPlus`/`.hofTrack` → steal beat) and the slide block (step 2, `result.isBigDrop` → slide beat) independently; both trigger on the same card because a big drop and a steal grade are the same fact. Merge them: when both fire, emit one beat ("HOU steal K J. Winchester — the mock had him at #19; he lasted to #51") and drop the other, the same way the position-run beat already rewrites its own row instead of stacking.

- [ ] **Q-H123 · Kickers sit at consensus #19 and #27 and a punter at #49 — the media board has no positional discount, so a round-2 kicker grades A+ as a "32 slots of value" steal**
  - evidence: 080 big board: "#19 K Jace Winchester ... B−/A" and "#27 K Elias Derringer ... C−/B"; draft_01 adds "#49 P Wilkes Marsden". On draft_01 the user's own card reads "#51 HOU YOURS  A+ | Jace Winchester | K | Age 23 · Duke" and the feed reads "HOU steal K J. Winchester — Consensus board had him #19; he lasted to #51 — 32 slots of value." A kicker inside the consensus top 20, and an A+ for spending the 51st pick on him.
  - code: `dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift:2332-2385; DraftIntel.swift:29-33; DraftClassBuilder.swift:1374-1380, :376-396; PickGradeCalculator.swift letterGrade; DraftEngine.swift:303`
  - fix: The engine already knows better in two places and the media board ignores both: `DraftClassBuilder.SlotGroup.earliestBand` returns 4 for `.kicker`/`.punter` ("no amount of consensus error puts a punter in round 1") and `DraftEngine` applies `specialistDiscount = 8.0`. But `ScoutingEngine.generateMockDraft` sorts purely on `consensusOverall` with no specialist carve-out and no `earliestBand` respect, and `DraftIntel.mediaConsensusOrder`'s FIRST key is `mockDraftPickNumber` — so the mock overrides the round-4 floor and sets the consensus rank the whole draft room quotes. Apply the same floor in the mock (exclude K/P from rounds 1–3, or discount their mock score), and the guaranteed slide-then-"steal" for every specialist disappears with it.


### Preseason — training focus

- [ ] **Q-H124 · None of the four preset chips ever shows a selected state — the split is exactly "Balanced" and "Balanced" is not highlighted**
  - evidence: Sliders read Tactical 34% / Physical 33% / Technical 33%, which is verbatim `Preset.balanced.allocation = (34, 33, 33)`, yet "Balanced", "Scheme Heavy", "Camp Hard" and "Recovery Mode" all render with the same `Color.backgroundTertiary` fill and the same `Color.surfaceBorder` stroke. The button label has no `isSelected` branch at all (TrainingPlanView.swift:141-155), so tapping "Camp Hard" moves the sliders and leaves the chip row visually unchanged — no confirmation that the tap registered.
  - code: `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:133-158, :47-63`
  - fix: Compute `current == preset.allocation` and give the matching chip the filled/selected treatment the roster's own filter picker already uses (accentBlue fill, backgroundPrimary label). Clear the selection the moment a slider is dragged off a preset value.

- [ ] **Q-H125 · "Camp Hard" and "Recovery Mode" promise a workload trade-off the engine cannot model — the plan carries no intensity, so nothing in the LOAD/STATE/INJ table can ever move**
  - evidence: The screen pairs a preset row containing "Camp Hard" and "Recovery Mode" with a "PER-PLAYER WORKLOAD" table whose columns are LOAD, STATE and INJ. But `TrainingPlan` stores only `tacticalPct`/`physicalPct`/`technicalPct` (TrainingPlan.swift:21-23) — there is no intensity or volume field — and `TrainingPlanEngine.applyWeekly` spends those three numbers exclusively on attribute deltas (awareness, decisionMaking, stamina, durability, position skill, scheme familiarity). Nothing in the plan path writes `cumulativeLoad` or `workloadStatus`; those come from `WorkloadEngine.tickDay(intensity:)`, which this screen never calls. So "Recovery Mode" (40/15/45) recovers nobody — it is a technical-heavy split wearing a rest label — and "Camp Hard" (20/50/30) costs nothing. The only real decision on the screen is which attributes grow, and the table under it is decoration.
  - code: `dynasty/dynasty/Domain/Models/Camp/TrainingPlan.swift:20-25; dynasty/dynasty/Engine/Camp/TrainingPlanEngine.swift:20-89; dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:8635-8642`
  - fix: Either add an intensity/volume dimension to `TrainingPlan` that feeds `WorkloadEngine` (so Camp Hard actually raises load and injury risk and Recovery Mode lowers it — the Madden/FM camp-intensity trade-off), or rename the presets to what they truly are ("Film Room", "Conditioning", "Fundamentals") and replace the workload table with a projected-attribute-gain preview that does respond to the sliders.

- [ ] **Q-H126 · "PER-PLAYER WORKLOAD" silently shows an arbitrary, unsorted 30 of the team's 75 players**
  - evidence: `private var displayRoster: [Player] { Array(roster.prefix(30)) }` (TrainingPlanView.swift:351-354), fed by `CareerShellView.teamRoster`, which is an unsorted `FetchDescriptor<Player>` with no `sortBy` (CareerShellView.swift:2325-2329). The roster is 75 men — pre_04's summary bar reads "75 / 90  Players · offseason" — so 45 players' burnout state is unreachable from this screen, and the header says only "PER-PLAYER WORKLOAD" with no "30 of 75". The 30 shown are in no order: the OVR column runs 89, 63, 79, 87, 68, 78, 65, 62, 76, 77, 72, 72.
  - code: `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:352-354, :238-269; dynasty/dynasty/UI/Career/CareerShellView.swift:2099, :2325-2329`
  - fix: Sort by cumulativeLoad descending (the men at risk are the reason the table exists), show the full roster in a lazy list, and if a cap must stay, say "Top 30 by load · 75 on roster" with a "Show all" row.


### Roster cuts — cut to 65

- [ ] **Q-H127 · Camp grade is degenerate — 15 of the 17 graded rows in this batch read "Camp D", across OVR 54 to OVR 90**
  - evidence: pre_17: every graded row is "Camp D" — Callum Abernathy OVR 90, Waylon Hopewell OVR 81, Norbert Vestergaard OVR 78, Nehemiah Lockridge OVR 77, Hayden Tanguay OVR 72, Jarreth Colgrove OVR 65, Osric Goddard OVR 65, Kaleo Hinsdale OVR 54. pre_03/pre_15 add Camp C once (Isaias Laurelwood OVR 89) and Camp F once (Odalric Smallwood OVR 62); the other seven graded rows are all Camp D. Note the inversion on pre_03: Isaias Laurelwood OVR 89 Age 24 = Camp C, Callum Abernathy OVR 90 Age 32 = Camp D — the better player graded worse.
  - code: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:8749-8760 (estimatedSnaps/perfFactor/trainingPts proxies), Engine/Camp/CampGradeEvaluator.swift:37-73, Engine/Camp/WorkloadEngine.swift:15-19 (load 200 cap, healthy<80)`
  - fix: applyCampGrades feeds CampGradeEvaluator three placeholders: trainingPts = cumulativeLoad/6 (comment claims a 0..200 load range, but WorkloadEngine.classify calls >130 burned-out and >80 unhealthy, so a well-managed roster earns ~0-17 of the 40 training points and only a burned-out one earns 40), estimatedSnaps = a flat 35 if yearsPro >= 4 else 60, and perfFactor = ovr/100. gradeFor needs 50 for a C, so the whole roster lands in the 35..<50 D band, and the age-gated snap constant alone is the 8-point swing that made the OVR 89 a C and the OVR 90 a D. Persist real preseason snaps/performance (the file's own TODO), and rescale gradeFor against the distribution the proxies actually produce so a camp grade discriminates.

- [ ] **Q-H128 · Camp C, Camp D and Camp F all render in the same gold — the grade is unreadable at a glance and gold is spent on the most common chip**
  - evidence: On pre_03 "Camp C" (Isaias Laurelwood), "Camp D" (Seneca Crisanti, Rafferty Larrabee, Brixton Tanguay, Jace Klingman, Roman Frobisher, Hayden Tanguay, Callum Abernathy) and "Camp F" (Odalric Smallwood) are drawn in one identical gold at one identical weight. An F is indistinguishable from a C without reading the letter, and gold — the app's emphasis colour, also used for the active slat "2 CUT TO 65" and the primary button — is on almost every row.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:290-294; UI/Common/Theme.swift:25; DSActionBar.swift:235; DSSlatBand.swift:709,810`
  - fix: Color the camp chip by grade off the same five-tier ladder the OVR number already uses (Color.forRatingTier): A/A+ green, B blue, C neutral, D warning, F danger. Line 293 hardcodes Color.accentGold for every grade; WorkloadDashboard.swift:156 does the same, so fix both from one helper.

- [ ] **Q-H129 · The cut list is in arbitrary order with no sort control, and the engine's worst-first cut recommender is dead code**
  - evidence: OVR top-to-bottom on pre_03 and pre_15: 89, 63, 79, 87, 68, 78, 65, 62, 76, 77, 72, 72, 90, 69. On pre_17 after ten cuts: 72, 72, 90, 69, 79, 77, 65, 81, 57, 78, 79, 66, 65, 54. Not sorted by OVR, age, cap, position or name — and there is no sort or "suggest cuts" control anywhere on the screen. To find the ten worst of 75 you must scroll the whole roster and hold it in your head.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:605-607, :755-759; Engine/Camp/RosterCutEvaluator.swift:21 (no callers); WeekAdvancer.swift:7040 (AI uses RosterValue.keepScore instead)`
  - fix: filteredRoster only filters — `activeRoster.filter { positionGroup.includes($0.position) }` — and the fetch behind it is a FetchDescriptor<Player> with no sortBy, so the order is whatever SwiftData hands back and can change between launches. Default the list to RosterCutEvaluator.recommendCuts order (worst-first, already weighs camp grade, OVR, age, contract and depth) and add a sort segment (Cut priority / OVR / Cap saved / Age). recommendCuts currently has zero callers in the app or tests — only a doc-comment mention in this very view.

- [ ] **Q-H130 · No way to inspect a player before releasing him — the row tap IS the release selection, and the row carries only four facts**
  - evidence: Every row shows exactly OVR, Age, an optional Camp letter and one cap figure (e.g. "MLB Callum Abernathy / OVR 90 Age 32 Camp D / +$25.3M"). The action bar instructs "Tap a player to mark him for release." There is no chevron, no info affordance, no long-press hint. Releasing an OVR 90 MLB with a $25.3M cap swing is irreversible and is decided on four numbers.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:356-365 (tap = selection); :252-336 (row content); UI/Roster/PlayerDetailView.swift exists and is used by RosterView/TradeView/ContractNegotiationView but never here`
  - fix: The row's only gesture is `.onTapGesture { toggleSelection(player) }`; there is no NavigationLink and the view's single sheet slot holds the result. Add a secondary route to the player card — a chevron/info button on the row, or long-press — so contract years, dead money, depth-chart rank, injury and preseason snaps are one tap away without leaving the cut flow.


### Preseason — depth chart

- [ ] **Q-H131 · Two toolbar buttons use the identical person.3.sequence.fill glyph and sit side by side — Practice Squad and League Rosters are indistinguishable**
  - evidence: Top-right toolbar renders, left to right: "↓ Overall", a red medical case with badge "1", then TWO pixel-identical three-person icons. Code: `Label("Practice Squad", systemImage: "person.3.sequence.fill")` (RosterView.swift:473) and `Label("League Rosters", systemImage: "person.3.sequence.fill")` (RosterView.swift:489). One opens a sheet, the other pushes a navigation destination. Same on pre_05_Evaluate_young_players_b.png.
  - code: `dynasty/dynasty/UI/Roster/RosterView.swift:473, :489`
  - fix: Give League Rosters a distinct symbol (`list.bullet.rectangle` or `building.2`) and Practice Squad `person.badge.clock` / `person.3.fill`. On a 13" portrait iPad there is room to show `.labelStyle(.titleAndIcon)` for both.


### Preseason — slate

- [ ] **Q-H132 · "WHAT THIS COSTS" is truncated mid-sentence — the half that states the trade-off is cut off**
  - evidence: The action bar reads: "A third of the ones open. They rotate across the slate, so every starter gets one exhibition and the other two thirds of…" — clipped with an ellipsis on all three shots. The missing half is "…of the first-team spots belong to the bubble. Part install, part risk, and most of the tape." (PreseasonView.swift:661-666), i.e. exactly the sentence that explains the bet. Cause: DSActionBar.swift:116 `.lineLimit(2)` plus DSActionBar.swift:120 `.frame(maxWidth: 420, alignment: .leading)` — a 420pt text column on a 1032pt screen. The bar between the truncated text (ends x≈632) and the "Play game 1" button (starts x≈1310) is empty, and there is ~550pt of empty page directly above it.
  - code: `dynasty/dynasty/UI/Common/DSActionBar.swift:116`
  - fix: Raise the explainer's `maxWidth` (the bar has 600+ pt of unused width to its right) or raise `lineLimit` to 3 — the file's own comment says "the bar has no fixed height". Better: shorten `planExplainer` to a two-line sentence that survives the cap, since the cap exists for a reason and silently eating the second half of a cost statement is worse than a shorter statement.

- [ ] **Q-H133 · Roughly half the portrait page is empty — content stops at 52% height and the right 32% is an unused gutter**
  - evidence: Identical on all three shots (pre_01_Play_the_preseason_slate_(0_3_played)__N_b.png, pre_07_slate.png, pre_07_slate_b.png). The last card ("On the roster 75 / Season opens at 65") ends at y≈1070 of the 2000px render; the action bar starts at y≈1868 — ~798px (~550pt) of black nothing between them. Horizontally every card's right edge is x≈1021 of 1500, leaving a ~479px (~330pt) empty column running the full page height. Code: PreseasonView.swift:202-203 caps the column at `DSLayout.contentMeasure` (Theme.swift:203 = 720pt) and then pins it with `.frame(maxWidth: .infinity, alignment: .leading)` on a 1032pt-wide screen — most sibling screens (ScheduleView:223, DepthChartView:139, CapOverviewView:122) use the same cap WITHOUT `alignment: .leading`, i.e. centred, so this screen's asymmetric gutter is also a deviation. `planningContent` (PreseasonView.swift:210-213) is only three cards: gameCard + policyPicker + rosterStanding.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:202`
  - fix: This screen already owns the component that fills the hole: `PreseasonBubbleTable` is built in the same file but only mounted in the `.reviewing` stance. Show the bubble cohort (and current injuries) BELOW the policy picker while planning — it is literally the roster the decision is about, and it is the evidence for the 10 cuts the screen is nagging about. At minimum drop `alignment: .leading` on the outer frame so the 720pt column centres.


### Preseason — game 1

- [ ] **Q-H134 · Two identical gold "Plan game 2" buttons on screen at once — the one in the sheet only closes the sheet**
  - evidence: pre_08/pre_09: the recap sheet's primary reads "Plan game 2 →" and the bottom action bar reads "Plan game 2" — same words, same gold pill, both visible simultaneously. pre_10: "Plan game 3 →" in the sheet and "Plan game 3" in the bar. In code the two do different things: the sheet's handler is `onContinue: { activeSheet = nil }` (dismiss only), the bar's is `handler: { advance(from: currentGame) }` which calls `PreseasonEngine.acknowledgeRecap`, resets the policy and saves the step. So the button labelled "Plan game 2" does not plan game 2.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:135, :636-640, :691-693`
  - fix: Give the two buttons different jobs and different words. The sheet's primary is a dismissal, so label it "Read the tape" (or wire it to `advance(from:)` and drop the duplicate from the bar). Never render the same `continueTitle(after:)` string on two live controls at the same time.

- [ ] **Q-H135 · No preseason snap rotation — one man takes 100% of a position's work for four quarters, so the bubble behind him has no tape to be cut from**
  - evidence: pre_08: "Brixton Yarborough — 2.7 a carry on 46 carries". 46 carries exceeds the NFL single-game record (45, and that was an overtime game) — in an exhibition. Same screen: "Davion Maddocks (QB, camp) — 28/38, 369 yds, 4 td, 1 int", i.e. one camp-body QB threw every pass. pre_10: "Kaleo Hinsdale — 3 interceptions on 47 throws", and five consecutive tape rows read "No stat line", including "RB Kenji Hambleton / No stat line / 62 / +1 / BUBBLE / QUIET". Code confirms this is by construction: `snapShare` returns `1.0` for everybody — "there is no half-present player in this simulator" — and `GameSimulator` "fields the best available man at each position for four quarters". So the screen's own promise ("This is the sheet the cut to 65 gets written from") is unwriteable for the second back, the third receiver and the backup QB, who are marked QUIET for a snap allocation they had no say in.
  - code: `dynasty/dynasty/Engine/Simulation/PlaySimulator.swift:2482-2516; dynasty/dynasty/Engine/Simulation/GameSimulator.swift:1932`
  - fix: Split each exhibition into quarters or drives and rotate the depth chart down (Madden's preseason and OOTP's spring-training playing-time model both do this). Even a crude "first team through Q1, twos through Q3, threes in Q4" would cap a back at ~15 carries and give every bubble body a real line. Until then the QUIET verdict should read "Did not play" rather than a judgement.


### Preseason — game 2

- [ ] **Q-H136 · The cut to 65 is decided over three games but no screen ever shows a man's three games together**
  - evidence: Odalric Goddard reads "5/7 rec, 65 yds, 2 TD … 78 … CAMP … HELPED" on pre_08 and "6/7 rec, 65 yds … 78 … CAMP … HELD" on pre_10, and there is no control on pre_10 to see game 1's row — the tape is rebuilt per game and the flow band's game-1 slat is a disabled button ("Not navigable", `onSelect` is nil). The `.complete` step does not aggregate either: it renders `moversCard(built)` and `PreseasonBubbleTable(recap: built, …)` for `playedIndices.last` only, so after the slate closes the cut list is still one exhibition's box score.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:580-583, :587-612; dynasty/dynasty/UI/Camp/PreseasonFlowBand.swift:24-26, :166-172`
  - fix: Add a cumulative cohort table: slate totals per man plus a 3-cell G1/G2/G3 verdict strip (this is exactly FM's squad-screen 'last 5' column). It is the only view the cut decision actually needs, and it is currently the one view the phase never renders.


### Preseason — game 3

- [ ] **Q-H137 · 32% of the portrait iPad's width is flat background down the right edge, while the band above and the bar below are full-bleed**
  - evidence: Sampling pre_12_game3.png at y=640, 900, 1600, 2100 and 2500, the scrolling content spans x 32→1407 at every height — identical stop. The flow band at y=340/420 spans x 32→2031 and the action bar at y=2640 spans x 0→2063. So 657 px of the 2064 px width (32%, ~328 pt) is uniform background: sampling the block x 1450–2050 / y 520–2580 returns 99.2% a single colour, (11,18,34). Same on all three screens. Cause: `.frame(maxWidth: DSLayout.contentMeasure, alignment: .leading)` then `.frame(maxWidth: .infinity, alignment: .leading)` (PreseasonView.swift:202-203). `contentMeasure` is 720 and its own doc comment says it is "the default reading column: one stack of cards, a form, a list" — but this screen's body is a 6-column table (POS / PLAYER·OUTING / OVR / FAM / STANDING / CASE) with 12+ rows. The token for that is in the same enum: `wideMeasure = 900`, documented as "dense content that needs the room: multi-column tables, standings" (Theme.swift:200-207).
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:202`
  - fix: Switch this screen to `DSLayout.wideMeasure` and centre it (`alignment: .center` on the outer frame) so the column's right edge lines up with the band and bar instead of dumping all the slack on one side. The reclaimed 180 pt is enough to put AGE and CONTRACT in the tape table — the two numbers a cut decision needs and the screen currently lacks.

- [ ] **Q-H138 · The cut sheet can never produce evidence for an offensive lineman — LT Wade Vandenberg is "QUIET / No stat line" in every game by construction**
  - evidence: pre_12_game3.png row: "LT · Wade Vandenberg · No stat line · 61 · – · BUBBLE · QUIET". pre_12_game3_result.png, one game later: "LT · Wade Vandenberg · No stat line · 61 · +1 · BUBBLE · QUIET" again. Both screens' recap cards say verbatim "This is the sheet the cut to 65 gets written from." `PreseasonEngine.CampCase.read()` scores only passing, rushing, receiving, defensive events and field goals; `opportunities` is incremented from attempts/carries/targets/tackles/sacks/FGAs only, and the first branch of the verdict is `if opportunities == 0 { verdict = .quiet }` (PreseasonEngine.swift:1046-1048). No blocking, pressure-allowed or snap-grade term exists. So LT/LG/C/RG/RT — five of the eleven offensive starters — are structurally pinned at QUIET for all three exhibitions, and the screen still asks the player to release 10 men off this sheet.
  - code: `dynasty/dynasty/Engine/Simulation/PreseasonEngine.swift:1046`
  - fix: Give the linemen a denominator. Either credit them from what the sim already produces (team sacks allowed / rushing yards on their side while dressed) or, at minimum, replace the QUIET pill for a no-box-score position with an explicit "NO TAPE" chip and a row sentence like "Nothing the box score can show — judge him on OVR and camp." Grading a tackle "QUIET" against a cut when the engine cannot ever say otherwise is worse than saying nothing.


### Preseason — game result

- [ ] **Q-H139 · Two identical gold "Close the slate" buttons on screen at once — the one in the modal does not close the slate, it only dismisses the sheet**
  - evidence: pre_12_game3_result.png and pre_13_slate_done.png both show a gold "Close the slate →" button inside the recap modal AND a gold "Close the slate" button in the bottom action bar, simultaneously, with the identical label. The two screenshots (taken 8.04 and 8.05) are pixel-identical apart from the status-bar clock — ImageChops diff bbox is (93, 21, 298, 48), i.e. only the "8.04"→"8.05" glyphs. A whole QA step produced zero state change: modal still up, band still "3 GAME 3", bar still "Close the slate". In code the modal's button runs `onContinue: { activeSheet = nil }` (PreseasonView.swift:135) while the real commit `advance(from: currentGame)` lives only on the action bar (PreseasonView.swift:640-646), which is behind the sheet's scrim. Both labels come from the same `continueTitle` (PreseasonView.swift:692). The sheet is `.interactiveDismissDisabled(true)`, so that mislabeled button is the ONLY way out of it.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:135`
  - fix: Give the sheet's button the commit: pass `onContinue: { activeSheet = nil; advance(from: recap.gameIndex) }`. If the sheet must stay a pure read, relabel its button "Back to the tape" (or a plain Done) so only one control on the screen claims to close the slate.

- [ ] **Q-H140 · After the final game the band still says "Read the tape before the next one" while its own meter says "0 left"**
  - evidence: On pre_12_game3_result.png and pre_13_slate_done.png the third slat reads "3 GAME 3 / Read the tape before the next one", and 1400 px to its right on the same rule the meter reads "3 spent · 0 left", with the action bar underneath headed "AFTER THIS — The slate closes with 75 on the roster". There is no next one. Code: `PreseasonView.stance` maps `flow.step.kind == .recap` to `.reviewing` for every game including game 3 (PreseasonView.swift:159-165), and `.reviewing` returns "Read the tape before the next one" (PreseasonFlowBand.swift:57). The correct copy already exists — `.complete` returns "The slate is done" (PreseasonFlowBand.swift:58) — but only fires after the slate has already been closed.
  - code: `dynasty/dynasty/UI/Camp/PreseasonFlowBand.swift:57`
  - fix: Add a terminal review case: when `currentGame == PreseasonFlowBand.gameCount` and stance is `.reviewing`, print "Last look before the cut to 65" (or reuse "The slate is done") instead of the pre-next-game caption. The action bar already switches its explainer title on the same condition (`currentGame < gameCount ? "Next" : "After this"`, PreseasonView.swift:634) — the band should use the same test.


### Preseason — slate complete

- [ ] **Q-H141 · The cut sheet only ever shows one game's tape — there is no cumulative view across the three exhibitions**
  - evidence: All three screens print "This is the sheet the cut to 65 gets written from" and the action bar on pre_12_game3_result.png says "The slate closes with 75 on the roster — 10 over the 65 the phase exits at." But the tape is per-game and it contradicts itself between games: Odalric Crisanti is HURT in game 2 ("0 yards on 6 targets", pre_12_game3.png) and HELD in game 3 ("5/8 rec, 54 yds, 1 TD", pre_12_game3_result.png), with nothing anywhere adding the two together. Elias Klingman shows "5 tkl" then "4 tkl" as two unrelated snapshots. Even the post-slate `.complete` screen does not aggregate — `slateContent` mounts `moversCard(built)` and `PreseasonBubbleTable(recap: built)` for `recapsByGame[playedIndices.last]` only, i.e. the last game (PreseasonView.swift:580-583). The three-game totals the cut is supposedly written from exist nowhere in the UI.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:580`
  - fix: Add a "Slate" lens beside "On the bubble" / "Whole roster" that sums all played games per player: total touches, total case delta, and a 3-cell W/L/W verdict strip (G1 QUIET, G2 HURT, G3 HELD). FM's squad screen and OOTP's spring-training report both make the cumulative column the default; a per-game snapshot is a box score, not a cut sheet.


### Roster cuts — cut to 65

- [ ] **Q-H142 · Result sheet warns about waiver claims on "a flagged man" while its own chip reads "PRACTICE SQUAD 0 flagged"**
  - evidence: In the CUTDOWN · CUT TO 65 sheet the fourth chip reads "PRACTICE SQUAD / 0 / flagged", and the WHAT IT COST rule directly beneath it reads "$3.5M of dead cap stays on this year's books, and a flagged man can still be claimed off waivers before you sign him." Nobody was flagged, so the sentence describes a risk the player did not take.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:510-512 (cost ternary keys on deadMoney only) vs :500-506 (ps chip reads practiceSquadFlagged)`
  - fix: Make the waiver clause conditional on result.practiceSquadFlagged > 0, not on deadMoney > 0. Both branches of the `cost:` ternary currently append a flagged-man clause unconditionally. When 0 are flagged the cost line should stop at the dead money; when >0, name the count ("3 flagged men can still be claimed…").


### Team picker (after the fix)

- [ ] **Q-H143 · Every column header on the team picker floats over the wrong column; "OWNER" labels empty margin outside the row card**
  - evidence: "DIFFICULTY" sits directly above "CAP $15M / STF $46M", not above the stars (which are ~78 pt to its left). "CAP / STAFF" sits above the owner gauge icon and "3yr". "OWNER" sits entirely past the right edge of the BAL row card, over blank background — the card's rounded corner and the NORTH divider both stop well to its left. Cause: the team rows are wrapped in `.frame(maxWidth: DSLayout.wideMeasure)` (900 pt) and centred, while `columnHeaderRow` gets only `.padding(.horizontal, 16)` and spans the full 1032 pt width — so the header is 100 pt wider and every fixed column (60/64/42 pt) lands ~50 pt right of the column it names.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:167`
  - fix: Apply the same `.frame(maxWidth: DSLayout.wideMeasure).frame(maxWidth: .infinity)` to columnHeaderRow that the list VStack gets, and add the row card's own `.padding(.horizontal, 10)` so the header's trailing inset matches the row content's. The whole point of the #117 header row was to label otherwise-mystery numeric columns; as shipped it mislabels all three.


---

## MEDIUM (342)


### New career

- [ ] **Q-M01 · The largest block on the setup screen is the one choice with zero mechanical effect; the choice that IS wired to the engine is three grey words**
  - evidence: Twenty portraits with loaded archetype names — 'The Enforcer', 'The Bulldog', 'The Diplomat', 'The Negotiator', 'The Firebrand', 'The Statesman' — occupy roughly the bottom 40% of the screen. The screen's own copy admits they do nothing: 'The portrait is yours alone — your coaching style and your press answers are what the league reads.' The code confirms the names are not authored per face: 'Persona label lists, applied in id order within each gender' (UserPortraitView.swift:33-43), so 'The Enforcer' is simply the 5th female photo in the manifest. Meanwhile the setting the engine actually consumes appears once, as grey body text with no control: 'Jump straight in with sensible defaults: GM & Head Coach, Realistic cap, standard mode, Tactician style.'
  - code: `dynasty/dynasty/UI/Common/UserPortraitView.swift:33`
  - fix: Either give the personas real weight (bind each to a coaching-style/press-temperament bias so 'The Enforcer' plays differently from 'The Diplomat' — the archetype names are already doing the promising) or shrink the grid to a single avatar with a 'Change' button and spend the reclaimed space showing the four Quick Start defaults as four editable chips. Reference: FM's manager-creation screen puts the mechanical attributes above the fold and the face in a thumbnail.


### Team picker

- [ ] **Q-M02 · 'J. Falkenrath 94' is an unlabelled name and number — nothing on screen says it is the quarterback**
  - evidence: Every row reads e.g. 'Harbormen 12-5 / Baltimore · J. Falkenrath 94', 'Stockyards 15-2 / Kansas City · S. Osgood 97'. The four column headers are TEAM, DIFFICULTY, CAP / STAFF, OWNER — none of them covers this cell, so a fan reading no manual cannot tell whether 94 is the head coach's rating, the team's rating, or a jersey number. The app already knows the answer and says it to VoiceOver only: `.accessibilityLabel("... QB \(preview.startingQBName) \(preview.startingQBOverall) OVR ...")` (TeamSelectionView.swift:1047).
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:1047`
  - fix: Prefix the cell with the same two letters VoiceOver gets — 'QB J. Falkenrath 94' — or add 'QB' to the column header row. Two glyphs remove the whole ambiguity.

- [ ] **Q-M03 · Difficulty stars invert the universal ★ = quality convention, with no legend and no label**
  - evidence: Jacksonville Tidewater — 4-13 record, weakest job on the board by every other number, '$50M' cap, '5yr' owner — shows ONE green star. Kansas City Stockyards — 15-2, QB 97 — shows FOUR gold stars. Under a header reading 'DIFFICULTY' more stars means harder (difficultyColor: 1-2 → success, 3 → accentBlue, 4 → warning, 5 → danger; TeamSelectionView.swift:910-917), but a 1-star row reads as 'worst option' to anyone who has ever seen a star rating. The plain-language label exists — `difficultyLabel` returns 'Very Easy'…'Very Hard' (LeagueTeamData.swift:36-44) — but is rendered only in the detail sheet (line 1428), and nothing states what drives the rating (owner patience baseline, +1 elite roster, +1 for 12+ wins — TeamBrowseCatalog.swift:212-235).
  - code: `dynasty/dynasty/Data/Import/LeagueTeamData.swift:36`
  - fix: Replace the stars with the word — 'VERY EASY' … 'VERY HARD' — or keep stars and print difficultyLabel beside them, plus a one-line 'why' on tap ('Demanding owner · 2 seasons · elite roster expected'). A rating a hardcore player cannot decompose is a rating he will not trust.

- [ ] **Q-M04 · Column header row labels only the right-hand column of the two-up grid**
  - evidence: 'DIFFICULTY', 'CAP / STAFF' and 'OWNER' sit at x≈1610-1935px, directly over Cincinnati Riverkings' and Pittsburgh Steelworks' cells. Baltimore Harbormen's identical stars / 'CAP $15M STF $46M' / owner cells sit at x≈600-905px, under no header at all. The cause: `columnHeaderRow` is one HStack with fixed widths (60 / 64 / 42) and `.padding(.leading, 56)` sized for a single full-width CompactTeamRow (TeamSelectionView.swift:401-426); it is emitted once above a grid that renders two rows per line.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:401`
  - fix: Emit the header once per grid column (an HStack of two columnHeaderRows matching the LazyVGrid's GridItems), or drop the shared header and put micro-labels inside each cell the way 'CAP'/'STF' already do.

- [ ] **Q-M05 · Filter / Division / Compare chips are 26.5pt tall — well under the 44pt minimum**
  - evidence: Measured the chip fill directly: the 'Filter' capsule spans y=445-497px on a 2x screen = 53px = 26.5pt. Code confirms there is no expanded hit area — all three chips are `.padding(.horizontal, 10).padding(.vertical, 6)` around a footnote-sized label, with `.buttonStyle(.plain)` and no `frame(minHeight:)` or `contentShape` (TeamSelectionView.swift:459-466, 494-501, 519-526). By contrast the AFC/NFC picker beside them does use `.padding(.vertical, 10)` + `.contentShape(Rectangle())` and clears the bar.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:459`
  - fix: Raise the vertical padding to 12 or add `.frame(minHeight: 44)` + `.contentShape(Capsule())` on all three chips. The visual capsule can stay small if the hit target grows.

- [ ] **Q-M06 · Team roster overall is never shown on a row, yet the sort menu offers 'Overall'**
  - evidence: The only rating on any row is the quarterback's — 'S. Osgood 97', 'L. Medlock 65', 'J. Falkenrath 94'. The team's own strength exists (`estimatedOVR`: BAL 83, KC 87, CLE 68 — LeagueTeamData.swift:83, 96, 85) but is rendered only inside the per-team detail sheet (TeamSelectionView.swift:1498), one tap and one dismiss per team. Meanwhile `TeamSortMode.overall` is exposed with the label 'Overall' (line 1727) and sorts by `estimatedOVR` (line 110) — choosing it silently reorders the list by a number that appears nowhere on it.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:110`
  - fix: Put `estimatedOVR` on the row as its own column (it is the single most decision-relevant number on a team-choice screen, and there are 1205 empty px to hold it). At minimum, never offer a sort key whose value is invisible in the sorted list.

- [ ] **Q-M07 · Sorting never leaves the division, so no league-wide ranking is possible**
  - evidence: `divisionsForConference` filters to `divTeams` per `Division.allCases` and sorts inside that four-team bucket (TeamSelectionView.swift:99-115). Picking 'Cap Space' reorders the 4 NORTH teams, then the 4 SOUTH teams, then EAST, then WEST — Jacksonville's '$50M' and Tennessee's '$42M' (both SOUTH) never come to the top of the AFC, and the on-screen NORTH/SOUTH/EAST/WEST rules stay in place regardless of sort mode. The question 'who has the most cap room in this conference' cannot be answered by any control on the screen.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:99`
  - fix: When sortMode != .division, drop the division grouping and render one flat ranked list for the conference (keeping the division as a small chip on each row). Also rename the chip — it currently reads 'Division' with a sort glyph, which a first-time player reads as a division filter, not a sort order.


### Team detail

- [ ] **Q-M08 · "Moderate" appears twice in the same blue for two unrelated scales**
  - evidence: "CAREER DIFFICULTY ★★★☆☆ Moderate" sits 250pt above "OWNER EXPECTATIONS ⌾ Moderate  3 seasons tolerance", both rendered in the same accent blue. A reader skimming the screen sees the same word in the same colour twice and has no cue that one is a 1–5 difficulty rating and the other is an owner-patience tier.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:1428`
  - fix: `difficultyColor` returns `.accentBlue` for difficulty 3 and `ownerPatienceColor` returns `.accentBlue` for patience "Moderate" — same token, same word, different ladders. Rename the patience tier to something in the owner's voice ("Patient enough", "Gives you three years") or fold it into the tolerance phrase ("Owner gives you 3 seasons"), and let only one of the two scales own accent blue on this screen.

- [ ] **Q-M09 · The three headline numbers have no league anchor and no way to compare a second team**
  - evidence: "Roster OVR 81 · Cap Space $20M · Draft Picks 7" are printed bare, while the far less decision-critical Coaching Budget is the only figure that gets a comparison ("$47M … League average: $42M"). The three values also use three different colour languages — 81 green, $20M blue, 7 plain white — so the row reads as if the app has an opinion on two of them and none on the third.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:1493`
  - fix: `statsRow` prints `preview.estimatedOVR/estimatedCapSpace/estimatedDraftPicks` with no baseline; the catalog already computes `averageCoachingBudget`, so the same league averages (and a rank, "7th of 32 in cap room") are one property away. This is also the screen where the player commits a decade of play and it has no comparison affordance at all — `CompareTeamsSheet` is reachable only from the list behind it. FM's squad screen and OOTP's team page both anchor every headline figure to a league rank; put "vs league" under each of the three, and a "Compare with…" entry beside SELECT THIS TEAM.


### Intro — press conference

- [ ] **Q-M10 · Meter says "0 spent · 5 left" while the header says "QUESTION 1 OF 5" and slat 1 is badged NOW**
  - evidence: Band head reads "QUESTION 1 OF 5" on the left and "0 spent · 5 left" on the right, with all five pips drawn as empty outlines — no pip marks the question the player is currently on. The same string "0 spent · 5 left" also appears unchanged on 005_intro_01.png, before anything has started.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:438`
  - fix: DSResourceMeter documents its own contract as "Units already committed, **including the one in progress** — the brightest pip is spent, not pending, which is what makes spent + left == total" (DSSlatBand.swift:317-322), and FAWeeklyView.swift:588 follows it with `spent: min(currentRound, 6)`. The presser passes `selectedIndices.count`, which excludes the live question, so the meter permanently trails the headline by one and the "current" pip never lights. Pass `min(currentQuestionIndex + 1, questions.count)`.

- [ ] **Q-M11 · The stat strip calls it "SATISFACTION", the legend under it calls it "Owner", and the two lists are in opposite order**
  - evidence: Tiles read "★ 0 LEGACY · 📰 0 MEDIA · 🏢 70% SATISFACTION"; the line directly beneath reads "Owner affects job security · Media shapes the narrative · Legacy affects career rating". Nothing on screen states that the 70% tile is the owner, and every response chip below uses the word "Owner", never "Satisfaction". LEGACY 0 and MEDIA 0 carry no unit or range — a first-time player cannot tell whether 0 is the floor, the midpoint, or bad.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:589`
  - fix: Label the tile "OWNER" (or "OWNER SATISFACTION") to match the chips and the legend, and print the legend clauses in tile order. Give the two raw counters a scale — "MEDIA 0 (−50…+50)" or a signed "±0" — so the number reads as a position on a scale rather than as an empty field. Two of the three figures are 0 on the introductory presser, so as it stands the panel that opens the scroll, above the question, says almost nothing.

- [ ] **Q-M12 · "Preview headline" disclosure chips are ~21pt tall — half the 44pt minimum, four of them stacked**
  - evidence: Each of the four answer cards carries a "Preview headline ⌄" pill roughly 19pt tall as rendered. It is the only per-option control on the screen and it sits directly under a row of same-height non-interactive chips ("Owner ↑ likely approves"), so the one tappable pill is indistinguishable in size and weight from the four decorative ones beside it.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:955`
  - fix: The button is `display(11)` text with `.padding(.vertical, DSSpacing.xxs)` (4pt) and `.contentShape(Capsule())`, which caps the hit area at about 21pt. Add `.frame(minHeight: 44)` (padding the capsule, or an invisible expanded content shape), and give it a treatment that separates a control from a readout — a filled surface or a chevron-leading affordance the flat hint chips do not have.

- [ ] **Q-M13 · AGGRESSIVE is dominated by CONFIDENT on every audience the preview shows**
  - evidence: CONFIDENT: "Owner ↑ likely approves · Locker room — shrugs · Fans ↑ will eat it up · Media ↑ good copy". AGGRESSIVE: "Owner ↓ won't like it · Locker room ↓ risky · Fans ↑ will eat it up · Media ↑ good copy". Same on two audiences, strictly worse on the other two — under the information on screen there is no reason ever to pick AGGRESSIVE.
  - code: `dynasty/dynasty/Engine/Media/PressEngine.swift:727`
  - fix: `preview(for:)` derives the hints from the same `resolvedEffects` the commit runs and coarsens them to direction with a ±3 dead band, so the arrows are truthful — the hidden upside (a bigger fan/media magnitude, or the `isVanilla` penalty for repeating a tone) is invisible at the moment of choice. Either surface the counterweight the engine actually models (a magnitude band "small/large", or a "you have used this tone N times" mark on the archetype chip), or have the intro question's aggressive line buy something the safe line cannot — otherwise the four cards are one real choice and three decoys.


### Intro — press reaction

- [ ] **Q-M14 · The headline that "ran" is a fixed string on the response and flatly contradicts the media hint on the same card**
  - evidence: On 010 the chosen DIPLOMATIC card's own hint row reads "Media ↓ they'll pounce", and 400px below it the reveal card prints what actually ran: "Continental Sports: \"Steady hand takes the reins in Houston.\"" — a compliment. Same contradiction on 011: the card is badged "SAYS NOTHING, BEAUTIFULLY" with "Media ↓ they'll pounce", and the headline is "Continental Sports: \"Refreshing transparency from the new regime.\""; 012 reprints all five under YOUR KEY QUOTES, every one of them favourable, for a session that cost -21 media. Cause: `mediaReaction` is a constant on `PressResponse` (e.g. PressConferenceEngine.swift:743) and is rendered verbatim (`Text(reactionText)`, PressConferenceView.swift:1024; `Text(response.mediaReaction)`, :1421); nothing in `resolvedEffects` — not the hostile-reporter stance, not the repetition ratchet, not `vanillaMediaCost = -4` — ever changes the words.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1024`
  - fix: Give each response two or three headline variants keyed to the resolved media band (favourable / flat / hostile) and pick by `resolvedEffects.mediaPerception`, so a fifth identical non-answer in front of a TOUGH writer prints a sceptical headline rather than "Refreshing transparency".

- [ ] **Q-M15 · Answered-away options drop to ~1.78:1 contrast — a 40% opacity card multiplied on top of the already-tertiary text colour**
  - evidence: On 010 the three unpicked answers ("We're going to bring a championship to Houston. That's the only goal.", "First, I need to understand what we have. Then we build, brick by brick.", "This roster needs a complete overhaul...") and all of their hint chips are barely legible; same on 011. The card applies both `.foregroundStyle(isDisabled ? Color.textTertiaryReadable : …)` (PressConferenceView.swift:832) and `.opacity(isDisabled ? 0.4 : 1.0)` on the whole card (:870). `textTertiaryReadable #7C8BA1` on `backgroundSecondary #141E30` measures 4.82:1; composited at 40% over `backgroundPrimary #0B1222` it falls to 1.78:1 — far under the AA floor the palette explicitly commits to ("Its label is `textTertiaryReadable #7C8BA1`, which clears AA on it — a disabled label is still information", Theme.swift:69).
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:870`
  - fix: Pick one dimming mechanism, not two. Drop the card `.opacity` to ~0.75 and let the tertiary text colour carry the de-emphasis, so the record of what you did not say stays readable at 4.5:1.

- [ ] **Q-M16 · "BEFORE THIS SESSION" stays frozen at the session-start snapshot for all five questions — the projection the summary eventually prints is arithmetic the player has to do himself**
  - evidence: On 010 (after one answer) and 011 (after five) the top card reads identically: "LEGACY 0 · MEDIA 0 · SATISFACTION 70%". Directly beneath it on 011 sits "OWNER +18", and one screen later 012 prints "70% → 88%". The two cards are never combined: `standingStrip` reads `career.legacy.*` and `owner.satisfaction` raw (PressConferenceView.swift:576-597) while `runningImpactStrip` renders `runningTotals` (:645-648), and nothing on the questioning screen shows the landing spot. A player deciding question 5 has to add +18 to 70% in his head, and has no way at all to see that media has left the "Neutral" band (0) for "Scrutinized" (-21).
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:576`
  - fix: Relabel to "WHERE YOU STAND" and print `70% → 88%` / `0 → -21 (Scrutinized)` live in the same card, using the `reputationLabel` band that already exists (LegacyTracker.swift:96-106). That also removes the redundant second card.


### Intro — press conference

- [ ] **Q-M17 · "Preview headline" on the answer you committed looks live but is inert — the parent Button's disabled state propagates into it**
  - evidence: On 011 the selected green DIPLOMATIC card renders at full brightness with a bordered "Preview headline ⌄" pill (same on 010's selected card). The pill's own modifier is `.disabled(isDisabled)` where `isDisabled = selectedResponseIndex != nil && !isSaid` — false for the selected card (PressConferenceView.swift:791, :976) — but the whole card is wrapped in `Button { … }.disabled(selectedResponseIndex != nil)` (:871), and SwiftUI's disabled state propagates to every descendant and cannot be re-enabled by a child. The card is also not dimmed (`opacity(isDisabled ? 0.4 : 1.0)`, :870), and the pill's foreground is `textTertiaryReadable` in both states, so nothing signals it is dead. The one headline preview a player would actually want after answering — the one for the line he just said, to compare against what ran — is the one that no longer responds.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:871`
  - fix: Move `.disabled` off the outer Button onto its action (`Button { guard selectedResponseIndex == nil else { return }; pickResponse(...) }`), or hoist the headline-preview control out of the card Button, so the committed card's preview stays tappable. If it is meant to be dead, style it as disabled.

- [ ] **Q-M18 · Green "Front office and locker room aligned" verdict fires on a session that is net +1, with FANS -11 and MEDIA -21 sitting red beside it**
  - evidence: 011's RUNNING IMPACT reads "OWNER +18 | MORALE +15 | FANS -11 | MEDIA -21" and the verdict strip below it is a green check: "Front office and locker room aligned". `sessionFeedback` computes `net = owner + morale + fans + media` = +18+15-11-21 = +1, but the `owner >= 10 && morale >= 5` branch is evaluated before any net test (PressEngine.swift:837-841) and returns `severity: .good`, which the view paints with `Color.success` (PressConferenceView.swift:1665). The one running verdict the player has says the session is going well while half the board is being burned; the earlier `net >= 10` / `net <= -10` branches that would have said otherwise are unreachable once owner and morale are up.
  - code: `dynasty/dynasty/Engine/Media/PressEngine.swift:837`
  - fix: Either test `net` before the audience-pair branches, or keep the "aligned" text but downgrade its severity when another audience is ≤ -10 and name the cost: "Front office and locker room aligned — but the fans and the press are not (-11 / -21)".

- [ ] **Q-M19 · On the information shown, FUNNY weakly dominates the DIPLOMATIC answer — the ±3 hint deadband erases the differences exactly when the ratchet has made them matter**
  - evidence: 011's two live options read: DIPLOMATIC "Owner — no strong read | Locker room — shrugs | Fans — muted | Media ↓ they'll pounce" versus FUNNY "Owner — no strong read | Locker room ↑ will back you | Fans ↑ will eat it up | Media ↓ they'll pounce". Identical on owner and media, strictly better on two axes — there is no visible reason to ever take the one the player took. It is an artefact of the fog, not of the data: Q5 diplomatic's base effects are owner +6 / morale +3 / media +6 / fans +3 (PressConferenceEngine.swift:748-755, commented "best Owner trust + best Media, balanced positives, no negatives"), decayed to ~+2/+1/+2 by the fifth repeat, which lands inside `hintDeadBand = 3` (PressEngine.swift:723) and collapses three of four hints to "no strong read / shrugs / muted". The only axis on which diplomatic still beats funny — legacy 3 vs 2 — is never displayed at all.
  - code: `dynasty/dynasty/Engine/Media/PressEngine.swift:723`
  - fix: Make the deadband relative rather than absolute (a ±3 band is meaningless once the ratchet has scaled everything to ±2), or surface the ratchet on the card ("upside at 40%") so a flattened hint row reads as "this answer has stopped working" rather than as "this answer is neutral".

- [ ] **Q-M20 · The repetition ratchet is a hidden 35% tax before it is a visible label — the "vanilla" chip only appears on the fifth repeat, the decay starts on the fourth**
  - evidence: 011's slat strip shows Diplomatic on all five questions and only Q5's card carries the "SAYS NOTHING, BEAUTIFULLY" chip; Q1's card on 010 carries none. `repetitionScale` already returns 0.65 at three prior repeats and 0.40 at four (PressEngine.swift:637-645), but `isVanilla` — the sole trigger for the chip — is `repetitionCount >= 4` (:649). So on question 4 the answer's entire upside was quietly worth 65% with no marker on screen, and the extra `vanillaMediaCost = -4` (:629) that pushes the running total to -21 is never itemised anywhere the player can see. Nothing on 010/011 ever states how many times a tone has been used.
  - code: `dynasty/dynasty/Engine/Media/PressEngine.swift:637`
  - fix: Show the ratchet as soon as it bites: a "3rd time · 65% impact" marker on the card at count 3, and a tone-usage tally ("Diplomatic ×4") in the RUNNING IMPACT strip so the player can see the tax accruing rather than only being named once it has been paid.


### Intro — session result

- [ ] **Q-M21 · "That is the answer that did it" points at one answer, but the league read is computed from the dominant tone across all five — and no answer is identified**
  - evidence: 012's league-read card ends with "That is the answer that did it. It is not what your staff file said when you were hired." The identity above it comes from `FranchiseIdentityDeclaration.podiumRead(for: result.dominantTone)` (PressConferenceView.swift:1250) and `podiumRead` is a switch on tone only — `.diplomatic → .balanced` (FranchiseIdentityDeclaration.swift:107-115); `amend(tone:teamID:)` likewise takes `result.dominantTone` (IntroSequenceView.swift:126-128). There is no single answer, and the five quotes listed below carry no marker showing which one the copy means. YOUR APPROACH on the same screen even shows "5 DIPLOMATIC", i.e. all of them.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1284`
  - fix: Reword to the mechanism — "Five diplomatic answers is what did it; the room heard one note and priced you on it" — and, if a single line really is meant to be the trigger, badge that quote in YOUR KEY QUOTES.

- [ ] **Q-M22 · Summary column is pinned to the left edge — 155pt of empty right gutter against a 25pt left margin, while the questioning screens centre the identical 900pt measure**
  - evidence: On 012 every card (WHAT CHANGED, HOW THE LEAGUE WILL DEAL WITH YOU, YOUR KEY QUOTES) starts at x≈37/1500 and stops at x≈1275/1500 — a right gutter roughly six times the left margin. On 010 and 011 the cards run x≈120→1380, evenly inset. Code: the summary uses `.frame(maxWidth: DSLayout.wideMeasure, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)` (PressConferenceView.swift:1184-1185), whereas the questioning phase uses `.frame(maxWidth: DSLayout.wideMeasure).frame(maxWidth: .infinity)` with no alignment, i.e. centred (:442-443, :484-485). `wideMeasure` is 900pt on a 1032pt portrait canvas (Theme.swift:206). Two consecutive screens of the same flow use different page alignment.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1185`
  - fix: Drop `alignment: .leading` from the outer `.frame(maxWidth: .infinity, …)` on line 1185 so the measure centres like every other phase; keep `.leading` only on the inner content frame.

- [ ] **Q-M23 · Bottom quarter of the summary screen is empty — content ends at 68% of the page height with nothing beneath it**
  - evidence: On 012 the last quote card ("I respect the media. You have a job to do, and so do I. Let's work together." / Continental Sports: "Refreshing transparency from the new regime.") ends at y≈1372/2000; the WHAT IT COST action bar starts at y≈1868/2000. That is ~340pt of dead navy — roughly 25% of the 1376pt portrait canvas — on the screen that is supposed to be the payoff for five decisions. Structurally it is a ScrollView whose content does not fill the viewport (PressConferenceView.swift:1169-1187); PROMISES TRACKED is conditional and did not render here (`if !result.promises.isEmpty`, :1178).
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1169`
  - fix: Spend the band on what is missing rather than padding: the Media row this screen drops, a small before→after for all five meters, and the per-question tone/outcome table (which answer moved which meter). Failing that, use a two-column grid on regular width so WHAT CHANGED + league read sit beside YOUR KEY QUOTES.

- [ ] **Q-M24 · MORALE and FANS have no before→after and no absolute scale anywhere, while OWNER and LEGACY in the same row do**
  - evidence: 012's WHAT CHANGED row: "OWNER +18 / 70% → 88%", "MORALE +15" (blank line beneath), "FANS -11" (blank line beneath), "LEGACY +15 / 0 → 15". Two of four cells carry context and two do not — the code passes `nil` for Morale and Fans (`("Morale", effects.playerMorale, nil), ("Fans", effects.fanExcitement, nil)`, PressConferenceView.swift:1321-1322) while reserving the row height for a context line that never arrives (:1352-1359). Nothing on 010, 011 or 012 ever states a morale or fan-excitement baseline, so -11 fans is unscorable: 11 out of what?
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1321`
  - fix: Feed the team's current morale and fan-excitement values into those two cells so all four read `base → final`, the way OWNER and LEGACY already do.


### Intro — owner briefing

- [ ] **Q-M25 · The commit control changes shape and position between consecutive intro steps**
  - evidence: 012_intro_03 commits with a full-width bar: gold rule, "OWNER MEETING / This is the bar you are measured against…" on the left and a gold rounded rectangle labelled "Continue" (no chevron) at the far right. 012_intro_04 and 012_intro_05 commit with a centred gold capsule reading "Continue ›". The button the player just tapped moves from bottom-right to bottom-centre and changes shape and label.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:293`
  - fix: OwnerMeetingStep uses DSActionBar while TeamOverviewStep and YourRoadmapStep use IntroContinueButton. Pick one for the whole intro; DSActionBar is the stronger choice because it can carry the one-line explainer each of the other two steps currently lacks.

- [ ] **Q-M26 · Every "league average" comparison in the intro is a hard-coded literal, not a computed league value**
  - evidence: Screen 03: "League avg: 5 seasons" and "league avg: $38.0M". Screen 04: "Average Overall 70 (Avg: 72)" with a red arrow, "Average Age 25.4 (Avg: 26.0)", "League Avg Cap Space: ~$25.0M" plus a green up-arrow driven by `availableCap > 25_000`. All five are constants in the view layer, so the arrows are asserting a comparison against numbers the simulated league is never consulted about.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:547`
  - fix: Compute these from the loaded league (mean team overall, mean roster age, mean available cap, mean coaching budget) once at intro load and pass them in. As it stands, any balance change to roster generation or the cap silently turns the up/down arrows into decoration.

- [ ] **Q-M27 · The budget the owner quotes for "signings" is the coaching-salary pot, and the next screen shows a different, similar number for actual signings**
  - evidence: Screen 03: "Spending … ↳ Budget: $47.0M (league avg: $38.0M). Modest spending — be strategic with signings." The Staff Budget Envelope directly below shows the same $47.0M under "COACHING". Screen 04 then shows "Available $43.3M" of cap space — the money that actually buys signings. Two pots, two similar figures, one of them attached to the wrong advice.
  - code: `dynasty/dynasty/UI/News/OwnerBriefing.swift:147`
  - fix: budgetImplication() formats owner.coachingBudget but its tail talks about free agency ("be strategic with signings", "free agency will be tight"). Either quote the cap room in that sentence or retitle the row "Staff Spending" and move the free-agency guidance to the cap card.

- [ ] **Q-M28 · The facilities line inside the Staff Budget Envelope tells the player the system is a no-op, and its $7.8M is not part of the $53.8M above it**
  - evidence: Card head: "STAFF BUDGET ENVELOPE  $53.8M" over columns "$47.0M COACHING / $4.1M SCOUTING / $2.8M MEDICAL". The quote beneath: "The buildings are league standard across the board — $7.8M a year. That's what everybody else has, so it buys us nothing and costs us nothing." A fourth pot appears inside a card whose total excludes it, and the copy states outright that there is no trade-off here.
  - code: `dynasty/dynasty/Engine/Camp/FacilityEngine.swift:449`
  - fix: FacilityEngine already models three upgrade tracks with real effects; at .standard the only line it can say is the null one. Either give the card the affordance ("Training Complex — Standard · upgrade available", the FacilityEngine tier data is right there) or move the facilities sentence out of the staff-salary card and into its own row, so a $7.8M figure never sits under a $53.8M total that does not include it.


### Intro — team overview

- [ ] **Q-M29 · "S:" and "D:" head nine grade cards with no legend, and "7/6 players" reads as a fraction**
  - evidence: Every card leads with e.g. "S: B+ / D: C+" in the largest type on the card. Nothing on the screen expands S or D. The count line under WR reads "7/6 players" and under DB "10/8 players" — numerators larger than denominators, which reads as a broken fraction rather than "7 rostered against an ideal of 6".
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:660`
  - fix: Spell the two grades out in the card head ("STARTERS / DEPTH") or add a small key under the section label, and change the count line to "7 (need 6)" so the comparison direction is unambiguous.

- [ ] **Q-M30 · The Continue button sits on top of an unread DRAFT PICKS section with scroll indicators hidden**
  - evidence: The Salary Cap card is cut off by the bottom bar after "League Avg Cap Space: ~$25.0M", and a dimmed "DRAFT PICKS" section head is visible behind the Continue bar at the very bottom edge. There is no scrollbar and no more-content cue, so the obvious read is "you have seen the team, tap Continue" — and the player never sees the draft capital they own.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:801`
  - fix: The ScrollView sets .scrollIndicators(.hidden) and the Continue lives in a safeAreaInset with a 0.95-opacity background. Either show scroll indicators on this step, add a fade/chevron affordance, or move the draft-pick chips up beside the cap card so the whole briefing fits one screen.

- [ ] **Q-M31 · Gold section heads on the Team Overview / Roadmap steps break the rule the Owner Meeting step follows**
  - evidence: Screen 04 puts gold on "TEAM OVERVIEW", "ROSTER", "POSITION GROUP STRENGTHS", "SALARY CAP", the building glyph, the cap progress bar and the "Continue" pill — seven gold elements. The immediately preceding screen (012_intro_03) renders its card heads "OWNER PRIORITIES", "OWNER PATIENCE", "STAFF BUDGET ENVELOPE", "SEASON GOALS" in neutral grey and reserves gold for the Continue fill alone. Screen 05 follows screen 04.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:1187`
  - fix: SectionLabel hard-codes Color.accentGold; OwnerCard uses Color.textSecondary with an in-code comment stating "gold has three jobs and 'every heading on the screen' is not one of them". Point SectionLabel at textSecondary so all three intro steps obey the same rule and gold marks only the commit.

- [ ] **Q-M32 · "Average Overall 70" is painted blue by the rating ladder and flagged red by the league comparison in the same row**
  - evidence: The row reads: "Average Overall   70  (Avg: 72)  [red down-arrow]" — the 70 is blue, the arrow beside it is danger red. Two colour verdicts on one number, and a 2-point shortfall gets the same saturated red a 20-point shortfall would.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:1243`
  - fix: ComparisonStatRow colours the value with Color.forRating(value) and the arrow with success/danger on `value >= leagueAvg`. Pick one carrier of the verdict — most likely the delta — and render it as a signed number ("-2 vs league") so magnitude is visible; leave the value itself neutral.


### Intro — roadmap

- [ ] **Q-M33 · Only the current phase gets a description, so "OTAs", "The Combine" and "UDFAs" appear as bare jargon**
  - evidence: "Coaching Changes CURRENT Feb" carries "Hire and fire coaches, set coordinator schemes, build your staff". The other nine rows are name + REQUIRED/OPTIONAL + month only: "OTAs OPTIONAL May-Jun", "The Draft & UDFAs REQUIRED Late Apr", "The Combine OPTIONAL Late Feb". A football fan who has never played a manager game cannot tell what an OTA or a UDFA is, and the screen is titled "Here's what lies ahead".
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:926`
  - fix: The description strings already exist for all ten entries (offseasonCalendarEntries) and are gated by `if isCurrent`. Show them for every row — there is a screen-height of empty space directly below to absorb it — or at minimum for the OPTIONAL ones, which are the phases a new player will otherwise skip without knowing what they skipped.

- [ ] **Q-M34 · "YOUR FIRST TASKS" card is centred at content width while the calendar card above it is full width**
  - evidence: The "OFFSEASON CALENDAR" card spans nearly the full content column; the "YOUR FIRST TASKS" card directly beneath starts about 360 px further right and ends about 360 px further left, so neither its left nor its right edge lines up with the card above.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:959`
  - fix: tasksCard is a VStack(alignment: .leading) with .padding(20).cardBackground() and no width constraint, so it hugs its longest row ("Prepare for the Combine and Free Agency"); calendarCard is stretched by the Spacer() inside its rows. Add .frame(maxWidth: .infinity, alignment: .leading) to tasksCard.

- [ ] **Q-M35 · Later offseason phases are faded to 40% opacity — "Regular Season REQUIRED Sep-Jan" is barely legible**
  - evidence: Reading down the timeline the rows get progressively dimmer: "Coaching Changes" is gold and crisp, "Roster Cuts REQUIRED Late Aug" and "Regular Season REQUIRED Sep-Jan" are grey-on-near-black at the fade floor. The two phases the whole season builds toward are the hardest text on the screen to read.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:868`
  - fix: distanceFade = max(0.4, 1.0 - index * 0.08) drops the last four rows to 0.4 opacity on textPrimary/textSecondary, which fails body-text contrast. Raise the floor to ~0.7 and carry the emphasis with the gold CURRENT pill and background instead of by dimming everything else.


### Intro — ready to begin

- [ ] **Q-M36 · The intro's closing line is picked from a deprecated whole-roster OVR, so it mis-brands an 80-OVR contender as a rebuild**
  - evidence: The intro ends with "Build Your Dynasty. / Write your legacy." One minute later (14.25 → 14.26) the hub hero reads "Roster OVR   80 → 77 if none re-signed". `motivationalLine` maps 65...74 to "Write your legacy." and 75...84 to "Finish what they started." — the correct line for an 80. HOU's own brief in LeagueTeamData is `situation: "Contender", estimatedOVR: 81`.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:77`
  - fix: IntroSequenceView.swift:77 computes `teamOverall` as `players.map(\.overall).reduce(0,+) / players.count` — the whole-roster mean the codebase explicitly retired (see the doc comment on `rosterOVRProjection`, CareerDashboardView.swift:~4616: "it read 68 on a club the team picker had just called 76"). Switch line 77 to `RosterStrength.starterAverage(players)`, the single sanctioned definition.

- [ ] **Q-M37 · Roughly three quarters of the portrait page is empty — all content sits in a 330px band in the middle**
  - evidence: On the 1500x2000 render: content runs from the football glyph at y≈790 to "Write your legacy." at y≈1110. Above it, y=45→790 is empty stadium gradient (~37% of the page); below it, y=1110→1855 is empty before the "Enter the Front Office" capsule (~37%). The headline "Your Journey Begins" uses the 36pt `display` size, not the 48pt `hero` size the token scale reserves for full-bleed moments.
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:1094`
  - fix: The body is `VStack { Spacer(); content; Spacer() }` with no iPad sizing. On a 13" portrait iPad, promote the title to `DSType.Size.hero`, and fill the reclaimed space with the payload the player actually just chose — team crest, the club's situation line ("Contender"), record last season, roster OVR, owner name — instead of two Spacers.


### Career hub

- [ ] **Q-M38 · The starting QB is the only player in the league stored with an initial for a first name — "M. Wimberly"**
  - evidence: KEY PLAYERS lists "QB1  M. Wimberly  86", "MLB  Callum Abernathy  91", "MVP  Wade Braithwaite  94". All three rows call `player.fullName`, so the QB's stored firstName is literally "M.". The same player is rendered a third way one card to the left — LOCKER ROOM shows "QB Wimberly" (lastName only). Same on 025.
  - code: `dynasty/dynasty/Data/Import/LeagueGenerator.swift:1155`
  - fix: `LeagueGenerator.generateNamedQB` (:1149-1161) parses the preview string `startingQBName: "M. Wimberly"` (LeagueTeamData.swift:89) and persists "M." as firstName forever. Either store full first names in the 32 `startingQBName` entries, or have `generateNamedQB` draw a real first name from `RandomNameGenerator.firstNames` and keep only the surname from the preview.

- [ ] **Q-M39 · Task subtitles truncate mid-word and cut exactly the clause that names where to go**
  - evidence: Rail: "Optional · Evaluate your coordinators and position coaches, then confirm the review on…" (full string ends "…on the Review tab.") and "Optional · Check offensive and defensive scheme fit with yo…" (ends "…then confirm the review on the Schemes tab."). The second is squeezed further by the gold "Roster" chip sharing its line. In the collapsed REVIEW ROSTER list, "Read the Showcase & declaration rep…" clips four characters off a title. Same on 025.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:446`
  - fix: TimelineTasksPanel.swift:446 caps the detail at `.lineLimit(2)` at 10pt in a 300pt rail. Either allow 3 lines for rows carrying a "confirm on X" instruction, or move the destination out of the sentence into the existing secondary chip (which already has room and is already the tap target).

- [ ] **Q-M40 · The seven-item top nav has no current-location indicator — "Hub" looks identical to the six screens you are not on**
  - evidence: "Hub  Roster  Staff  Cap  Scouting  Draft  Trades" all render in the same grey icon+label treatment while the Hub is the screen being displayed. Identical on 025. Nothing in the strip, and nothing else on the page, states where you are.
  - code: `dynasty/dynasty/UI/Common/TopNavigationBar.swift:171`
  - fix: `bookmarkStrip` applies `.foregroundStyle(Color.textSecondary)` to every entry with no selection parameter. Pass the active destination into `TopNavigationBar` and tint the matching bookmark `Color.accentGold` with a 2pt underline or filled pill.

- [ ] **Q-M41 · Position-grade letters are ~14pt tap targets and the only route to the explainer the card advertises**
  - evidence: POSITION GRADES prints twenty grade letters ("QB S: A / D: C", "DL S: B / D: C-", …) and the legend promises "S = starters · D = depth · tap a grade for details". Each letter is the only tap target — the outer NavigationLink was deliberately removed. Same grid on 025.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2443`
  - fix: `gradeButton` sets a 14pt bold single character with `.padding(.horizontal, 2)` and `.contentShape(Rectangle())` — roughly 14×17pt against the 44pt HIG minimum. Add `.frame(minWidth: 44, minHeight: 44)` to the button (keeping the visual glyph small via an overlay), or make the whole "QB S: A / D: C" row the target and disambiguate S vs D inside the popover.

- [ ] **Q-M42 · Chemistry is railed at "Elite 100/100" because it is an unnormalised sum over the roster, clamped at 100**
  - evidence: LOCKER ROOM shows "Chemistry  Elite 100/100" with a fully filled green bar, on a club with "Team Morale 65%", zero coaches hired, and a QB whose own mood glyph is the neutral `face.dashed`. The value is byte-identical on 025 after 23 coaching hires. A stat pinned at its ceiling with a full bar is a dead readout — it can only ever move down, and nothing on the hub explains what it is or how to change it.
  - code: `dynasty/dynasty/Engine/LockerRoom/LockerRoomEngine.swift:110`
  - fix: `LockerRoomEngine.calculateChemistry` computes `50 + leadershipScore - toxicityScore` clamped to 0...100, where leadership accrues +1…+8 per player across a 53-man (offseason: up to 87-man) roster plus +2 per motivation cluster. The sum scales with roster size, so it saturates. Normalise by roster size (mean contribution) or express leadership/toxicity as per-capita rates before the 50-point offset, and surface the two component scores on the tile so a 100 is explainable.

- [ ] **Q-M43 · The four headline tiles mix three incompatible scales and one jargon word, none of them explained**
  - evidence: The row reads "88% OWNER", "65% MORALE", "Scrutinized MEDIA", "15 LEGACY". Two are 0–100 percentages, one is a word from a hidden seven-band ladder on a −100…100 axis, and one is an unbounded point total with no max, no tier and no trend. "15 LEGACY" is painted permanent gold regardless of value, so the screen's emphasis colour is spent on the one number that carries no judgement. "Scrutinized" (orange/warn) also sits unexplained beside "Job Security: Secure" and "Satisfaction 88%" in the OWNER card below. Identical row on 025.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3090`
  - fix: `satisfactionScoresRow` hardcodes `color: Color.accentGold` for Legacy — colour it by tier like the others, and print the underlying number for Media ("Scrutinized · −18") the way `PressConferenceView` already does. Add the scale to each tile's caption or make the row tappable to an explainer; a GM cannot act on "15" or "Scrutinized" without knowing the range.


### Cap tab

- [ ] **Q-M44 · Cap Outlook footnote is incoherent English — "The middle bar is that section drawn instead of stated"**
  - evidence: Directly under the three outlook bars: "Committed vs projected cap, on the same rules as the Next Year section above. The middle bar is that section drawn instead of stated."
  - code: `dynasty/dynasty/UI/Contracts/CapOverviewView.swift:918`
  - fix: Shipped copy, not a truncation. The intent is presumably "the 2027 bar is the Next Year section above, shown as a bar". Rewrite as one plain sentence: "Committed money against the projected ceiling. The 2027 bar is the Next Year section above, drawn." This card is otherwise the best-explained block on the screen (the "Active + dead money = used cap" and "Ceiling grows +6.5%/yr" notes are excellent) — this one line breaks the voice.


### Draft tab

- [ ] **Q-M45 · The Draft tab's only action leads to a guaranteed-empty screen, and there is no route to the thing you should actually do**
  - evidence: The screen says "No draft on the books yet" and "The war room opens during the Draft phase. Until then this screen tracks the picks you hold." The one tappable affordance is "Draft Report Card" — a hindsight review of past classes, which on a first career (no player has ever been drafted) can only render its empty state. Meanwhile the Scouting tab is sitting at "0 of 350 filed on · 0% scouted", which is the actual pending work, and this screen does not link to it.
  - code: `dynasty/dynasty/UI/Draft/DraftRecapView.swift:121`
  - fix: Make the primary action on a pre-draft Draft screen "Open the Big Board — 0 of 350 scouted", and hide or disable "Draft Report Card" when `seasons.isEmpty` (the data for that check is already loaded in DraftClassReportView.loadIfNeeded).

- [ ] **Q-M46 · Green success seal over the empty state "No draft on the books yet"**
  - evidence: A filled green checkmark-seal glyph sits immediately left of the headline "No draft on the books yet". Green + checkmark is the app's success semantic; here it decorates the absence of any draft. The icon and tint are rendered unconditionally, so the same mark serves "2027 Draft complete" and "nothing has happened".
  - code: `dynasty/dynasty/UI/Draft/DraftRecapView.swift:106`
  - fix: Branch the glyph with the headline: `checkmark.seal.fill` / `Color.success` when `recapSeason != nil`, and a neutral `calendar` or `clock` in `Color.textTertiary` when it is nil.

- [ ] **Q-M47 · Draft capital shows bare R1–R7 chips while the Trades screen prices the identical picks 875/600/360/216**
  - evidence: The Draft screen prints "2027 · R1 R2 R3 R4 R5 R6 R7 · 7 picks", four times, with no slot and no value. The Trades screen, one tab away, prices the same assets: "2027 1st (#19) 875 pts", "2028 1st 600 pts", "2029 1st 360 pts", "2030 1st 216 pts". The draft-capital screen is the one place a manager evaluates capital, and it is the only one of the two that hides both the pick number and the value.
  - code: `dynasty/dynasty/UI/Draft/DraftRecapView.swift:284`
  - fix: Print the slot on the chip when it is known ("R1 #19") and the projection marker when it is not ("R1 ~#16", from `DraftPick.isProvisionalOrder`), plus the per-year point total from `TradeValueEngine.pickTradeValue` so the four years are actually comparable. A "Trade these picks" link into the Trade Center closes the loop.


### Roster tab

- [ ] **Q-M48 · No name de-duplication: two WRs named Braithwaite sit in the same position group, and duplicate first/last names recur across screens**
  - evidence: Roster, Wide Receivers group: "Wade Braithwaite · 30 · 94" and two rows below "Zavier Braithwaite · 32 · 72". Roster Backfield has "Brixton Yarborough" while the Cap screen's Expiring Contracts lists "Norbert Yarborough (SS)". The Cap list also carries "Zavier Braithwaite" and "Zavier Hambleton".
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:30-101 (randomName has no uniqueness check)`
  - fix: `RandomNameGenerator.randomName()` draws first and last independently from a 55×55 pool with no uniqueness pass. For one 53-man roster against 55 surnames the expected number of shared-surname pairs is C(53,2)/55 ≈ 25; league-wide (~1,700 players over 3,025 combinations) the expected number of identical FULL names is ~470. Two same-surname WRs in one group is the visible tip; identical full names in a trade or FA list is the real hazard. Add a per-league used-name set (retry on collision, or fall back to a middle initial), or widen the pools — the anonymization gate in the file header constrains the cross product, not its size.

- [ ] **Q-M49 · The franchise QB is the only player on the roster displayed with an initial instead of a first name**
  - evidence: QB Room, top row: "M. Wimberly". Every other player on the screen has a full given name — "Hayden Bolliger", "Kaleo Hinsdale", "Waylon Hopewell", "Nehemiah Lockridge", "Brixton Yarborough", "Seneca Ogletree", "Wade Braithwaite", "Kester Vandenberg", "Jamari Nadeau". "M. Wimberly" is short enough that this is not truncation.
  - code: `dynasty/dynasty/Data/Import/LeagueGenerator.swift:1148-1160 (generateNamedQB); data at dynasty/dynasty/Data/Import/LeagueTeamData.swift:89`
  - fix: `generateNamedQB` parses `TeamPreview.startingQBName` ("M. Wimberly" at LeagueTeamData.swift:89) into firstName "M." / lastName "Wimberly", so the initial becomes the player's permanent identity everywhere — roster, player detail, press conferences, trade blocks. The preview string is a scouting-blurb format, not a name. Either author full first names in `TeamPreview` and abbreviate at the Team Selection call sites (which already do `shortName($0)` for generated leagues, TeamBrowseCatalog.swift:203), or expand the initial to a full name from `RandomNameGenerator.firstNames` starting with that letter.

- [ ] **Q-M50 · Group-header chips are unlabeled, and "exp" means two different things in two tabs of the same app**
  - evidence: "QB Room  S: A / D: C  —  $34.2M  1/3  Solid starters"; "Backfield … 3/4  1 exp  Solid starters"; "Wide Receivers … 3/7  3 exp  Key FA pending". Nothing on screen defines "S:", "D:", "1/3", or "1 exp". On the Staff screen the same token appears as years of service ("yrs exp" in the coach rows).
  - code: `dynasty/dynasty/UI/Roster/RosterView.swift:1766-1782; Staff usage at CoachingStaffView.swift:4352`
  - fix: "S:"/"D:" are starter and depth grade, "1/3" is `starterCount/players.count` (RosterView.swift:1767), "1 exp" is `expiringCount` — expiring contracts. Spell the two ambiguous ones out ("1 starter of 3", "1 expiring") or add a one-line legend under the ANALYSIS strip. A hardcore player also needs the grades to be explainable: an "A" starter grade sitting next to an 86 OVR QB should say what produced it on tap.

- [ ] **Q-M51 · Two adjacent columns use the same ↑/→/↓ alphabet for two unrelated facts, and one of them is headed with a bare "↗"**
  - evidence: Column headers read "AGE  FRM  OVR  ↗  SALARY  YRS  [smiley]  [medical case]". On M. Wimberly's row the FRM cell is a yellow "→" and three columns later the "↗" cell is a blue "↑↑". On Seneca Ogletree the FRM cell is a red "↓" and the "↗" cell is a grey "→". The identical glyph "↑" means "in form" in one column and "70–79 potential" in the other, ~90px apart on the same row.
  - code: `dynasty/dynasty/UI/Roster/RosterView.swift:899-907 (analysisHeaderColumns .overview); PlayerRowView.swift formColumn / shortPotentialLabel`
  - fix: `formColumn` maps form to ↑/→/↓ and `shortPotentialLabel` maps potential to ★/↑↑/↑/→/↓. Give them distinct visual languages — form as a small sparkline or a filled/hollow dot, potential as a number or a capped bar — and replace the "↗" header with a real word ("POT"). Four of the eight Overview headers are currently unreadable without a manual: "FRM", "↗", a smiley glyph and a medical-case glyph.

- [ ] **Q-M52 · Every row prints contract years twice and health twice, while the third chip (FIT) carries no value on any of the 53 players**
  - evidence: M. Wimberly's row: chips "FIT | EXT 2y | HLTH" on the left, and columns "… 2yr … [green check]" on the right. Contract years = EXT 2y and 2yr; health = HLTH and the green check. Every visible row repeats the pair (EXT 4y/4yr, EXT 3y/3yr, EXT 1y/1yr). Meanwhile the FIT chip is a bare label with no number on all 53 rows — and the header confirms why there is nothing to show: "53 Healthy · 0 Injured", and the Staff screen shows "Schemes" locked.
  - code: `dynasty/dynasty/UI/Roster/PlayerRowView.swift:224-285 (rosterSlots/fitSlot/extensionSlot/healthSlot) and :328-372 (overviewColumns contractYearsLabel + healthIndicator)`
  - fix: Confirmed intentional in `rosterSlots` ("Each is always drawn … What the user scans for is the gap") — but with 0 injuries and no scheme installed, two of the three fixed chips are informationless on the entire roster, and the row then re-prints both facts as columns. Drop the duplicate columns (or the chips), and give the empty FIT state its reason inline ("FIT —" → "no scheme"), which also gives the offseason player a reason to go hire a coordinator.

- [ ] **Q-M53 · The potential column uses directional arrows for an absolute band, so a 22-year-old with 8 points of headroom and a 31-year-old with 3 get the identical "↑↑"**
  - evidence: Same screen, same column (header "↗"): "Waylon Hopewell · 22 · 79 · ↑↑" and "M. Wimberly · 31 · 86 · ↑↑". Also "Wade Braithwaite · 30 · 94 · ★" — a star implying upside on a 30-year-old already at 94.
  - code: `dynasty/dynasty/UI/Roster/PlayerRowView.swift (shortPotentialLabel), header at RosterView.swift:904`
  - fix: `shortPotentialLabel` buckets `player.truePotential` into ★ / ↑↑ / ↑ / → / ↓ at 90/80/70/60 — it encodes the absolute ceiling but draws it with growth glyphs. The decision this column serves is "how much is left in him", which is potential MINUS current OVR, weighted by age. Print the headroom ("+8", "+3", "0") or the ceiling itself ("POT 89") next to OVR; arrows are the wrong alphabet for a level. At minimum, cap the glyph at → once `truePotential - overall <= 2`.


### Scouting / big board

- [ ] **Q-M54 · "0 spent · 6 left" names no unit, over six stages that are all locked and carry no lock glyph**
  - evidence: The Draft Prep band head reads "DRAFT PREP · 6 STAGES" with pips and "0 spent · 6 left" — no noun anywhere on screen saying what is spent (it is scouting weeks; the word exists only in the VoiceOver string). Below it all six slats are dimmed with captions that only the locked branch produces: "1 COMBINE REVIEW / Combine week", "2 INTERVIEWS / Combine week", "3 FILM STUDY / Combine week", "4 PRO DAY FOCUS / After FA", "5 PRIVATE WORKOUTS / After FA", "6 TOP-30 VISITS / After FA". There is no padlock, so "6 left" reads as an invitation to spend six things right now, when the answer is zero.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:399`
  - fix: Render the meter's `unit` alongside `valueLine` ("0 of 6 scouting weeks spent"), and put a `lock.fill` glyph on locked slats so the dim treatment is not the only signal. Consider a band-head line that names the gate — "Prep opens in Combine week" — since every stage is shut.

- [ ] **Q-M55 · Toolbar "Scout Board" reads as a title, not a control, and labels the state instead of the destination**
  - evidence: Between the sort arrows and the compare icon the toolbar prints "Scout Board" as plain grey text with no capsule, border or chevron — in a header that already carries the screen title "Scouting", a "BIG BOARD" tab, a "SCOUT NOTES" tab and a "SCOUT TEAM" tab. It is actually a toggle: it shows "Scout Board" while you are on the scouts' board and "My Board" while you are on yours, so the word on the button is where you are, not where tapping takes you.
  - code: `dynasty/dynasty/UI/Scouting/BigBoardView.swift:1415`
  - fix: Make it a two-segment control ("Scout Board | My Board") with the active segment filled, so the state and the destination are both visible. That also stops it from reading as a fifth heading in a header already carrying four scout-prefixed labels.

- [ ] **Q-M56 · "Blue Chip — Elite talent, projected Rd 1 pick" contains prospects the same row ranks #170, #177, #181, #203 and #224**
  - evidence: The tier header reads "Blue Chip 17 … Elite talent, projected Rd 1 pick" and the # column down that tier runs 1, 5, 11, 2, 23, 61, 64, 112, 7, 34, 170, 177, 181, 203, 224, 60 — non-monotonic, and five of the sixteen visible men rank outside the top 150 of 350. Nothing on screen says the # is a different opinion from the tier: the column is headed with a bare "#" and the only tooltip on the strip is on OVR.
  - code: `dynasty/dynasty/UI/Scouting/BigBoardView.swift:767`
  - fix: Two orderings are in play — `#` comes from the saved board order falling back to media consensus, the tier from `scoutedOverall` — and the screen presents them as one list. Either label the column ("MEDIA #") and add a one-line legend under the tier description, or surface the disagreement as the feature it is: a "+205 vs media" chip on Callum Henshaw is a reason to click, an unexplained 224 in an elite tier reads as a bug.


### Staff tab

- [ ] **Q-M57 · "Above league avg (~$35M)" cites a hardcoded constant; the league it describes actually averages $42.2M**
  - evidence: The budget card reads "Coaching Budget / Used $0.0M of $47.0M / Above league avg (~$35M)". Summing `coachingBudget` across the 32 authored teams in LeagueTeamData gives 1349, i.e. a real mean of $42.2M — the stated figure is $7.2M (17%) low.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:3580-3596; data at dynasty/dynasty/Data/Import/LeagueTeamData.swift:77-108`
  - fix: `leagueAverageCoachingBudget = 35_000` with the comment "Hardcoded to $35M for now". The band is avg×0.9…avg×1.1 = $31.5M–$38.5M, so every team from $38.6M up is badged "Above league avg" — that mislabels PIT ($39M), CLE ($40M), DEN/SEA ($41M) and ATL ($42M), all of which are at or below the true mean. HOU's verdict happens to survive, but the number printed to the player is wrong. Compute the mean from the live `Owner.coachingBudget` values (or at minimum from `LeagueTeamData.previews`) instead of a literal.

- [ ] **Q-M58 · Vacancy rows leave ~70% of a portrait-iPad row empty at the exact moment the player has to choose a coach**
  - evidence: "Assistant Head Coach / Vacant — Tap to hire / ~$1.3-7.0M/yr / +5% staff chemistry bonus" occupies roughly the left third of the row; the remaining ~1,000px holds nothing but a small "+" glyph at the far right edge. Same shape for "Offensive Coordinator [High Priority] / Vacant — Tap to hire / ~$0.8-9.5M/yr / +12% offensive efficiency" and "Defensive Coordinator [High Priority]". The Assistant Head Coach block also has no card background at all, unlike the Head Coach card directly above it.
  - fix: The dead middle is where the decision lives. Put the top 1–2 available candidates inline — name, best attribute, asking price, fit vs. the HC's "Tactician" style — so the player can compare without entering a sheet (FM's staff screen and OOTP's coach hiring both do this). It also gives the "+12% offensive efficiency" claim something concrete to attach to. And give the AHC block the same `cardBackground()` as the HC card so the two read as the same class of object.


### Trades tab

- [ ] **Q-M59 · Two independent team pickers on one screen, labelled "Trade Partner" and "Partner Team"**
  - evidence: The Propose Trade card asks for a "Trade Partner" (ARI ATL BAL BUF CAR CHI CIN CLE DAL DEN DET…) and 300px below the Pick Trade Simulator asks for a "Partner Team" (ARI ATL BAL BUF CAR CHI CIN CLE DAL DEN DET GB IND…). The two names are near-synonyms, the chip rails look identical, and the selections are backed by separate state (`selectedPartner` vs `wizardPartnerID`) — so choosing DAL up top leaves the simulator below still saying "Pick a draft pick and a partner team."
  - code: `dynasty/dynasty/UI/Contracts/TradeView.swift:1338`
  - fix: One partner selection for the screen. Hoist it into the Trade Center header ("Trading with: [DAL ▾]") and have both the proposal builder and the pick simulator read it; if the simulator genuinely needs a second club, say so explicitly ("Compare against a different club").

- [ ] **Q-M60 · Both chip rails clip mid-glyph at the right edge with no scroll affordance**
  - evidence: The "Trade Partner" rail ends "… DAL DEN DET" followed by a sliced partial glyph at the card's right edge. The "Your Pick" rail's last chip reads "2027 2nd / 390 p" — the "ts" of "pts" is cut off. "Partner Team" ends flush at "IND" with 18 more clubs off-screen. All three are `ScrollView(.horizontal, showsIndicators: false)` with no fade, no chevron and no edge gradient, so a first-time player has no cue that 31 teams exist.
  - code: `dynasty/dynasty/UI/Contracts/TradeView.swift:327`
  - fix: Add a trailing fade mask (or a `.contentMargins`-style peek) so the cut chip is obviously a cut chip, and make the rails scroll-snap. Better still for a 31-item set: replace the rail with a searchable team grid or a Menu, since horizontally scrubbing to find "WAS" is 20 swipes.

- [ ] **Q-M61 · Team and pick chips measure ~22pt tall, half the 44pt touch floor**
  - evidence: The "ARI"/"ATL"/"BAL" chips render about 44 device px tall on a 2064×2752 (2× ) display — roughly 22pt. Source is `.font(.caption)` with `.padding(.vertical, 6)` and no minimum height, against a codebase whose own DSListRow header states "§2.12 has no exceptions: every button, link, capsule, segment, stepper AND ROW is ≥ 44 pt in both axes". Same for the wizard's pick chips and the Draft screen's R1–R7 capsules.
  - code: `dynasty/dynasty/UI/Contracts/TradeView.swift:347`
  - fix: Add `.frame(minHeight: 44)` (or `.contentShape(Rectangle()).frame(minHeight: 44)` to keep the visual capsule small while the hit rect clears the floor) to `wizardPickChip`, the Trade Partner chip and the Partner Team chip.


### Coaching staff

- [ ] **Q-M62 · Staff screen advises "creative coordinators"; the hire screen rates the least creative archetype as a Strong fit**
  - evidence: 015, under the Head Coach card: "💡 Pair with creative coordinators who can execute complex schemes". 017, for the top candidate: "HC Chemistry: Strong — Steady Performer fits well with your The Tactician approach." whose listed effects are "Consistency +5%" and "Development stability +3%".
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:1212 vs dynasty/dynasty/UI/Staff/HireCoachView.swift:1563 (.tactician strongFits = [.quietProfessional, .steadyPerformer]); the same table marks .steadyPerformer as a weak fit for .innovator`
  - fix: One table should drive both strings. Either change the Tactician's advice line to describe the archetypes `strongFits` actually rewards (steady, quiet-professional), or move .steadyPerformer out of the Tactician's strong list. As it stands the two screens send the player in opposite directions.

- [ ] **Q-M63 · Three unlabelled money figures for the same purchase, and the step rail's estimate is smaller than one candidate's asking price**
  - evidence: Step rail: "2 COORDINATORS / 3 open · ~$6.1M". Section header: "Coordinators   $2.2M–$20.0M   0/3". Row: "Offensive Coordinator … ~$0.8-9.5M/yr". The very first OC the game then offers (017) asks $6.6M — more than the rail's estimate for all three coordinator seats.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:3341 (planned = sum of CoachRole.salaryRange.avg) with ranges at dynasty/dynasty/Domain/Enums/CoachRole.swift:112-114 (2400+2400+1300 = 6100)`
  - fix: The ~$6.1M is an auto-hire allocation built from league-average salaries, not a market quote. Label it ("auto-hire plan ~$6.1M") or compute it from the generated candidate pool, so the rail's number and the first asking price the player sees cannot disagree by more than the whole tier.

- [ ] **Q-M64 · At "TIER 2 OF 5 — COORDINATORS", the entire first screenful is tier-1 work that is already done**
  - evidence: Below the highlighted "2 COORDINATORS" slat the eye hits, in order: Staff Budget, the Auto-Hire card, then the gold-ringed "1 Head Coach — You (Test GM)" card (the largest, brightest object on the page, marked ✓ done in the rail), then Assistant Head Coach. "2 Coordinators" and the Offensive Coordinator row only appear at the very bottom edge, y≈1765 of 2000.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:3378-3395 (hiringBand onSelect opens a sheet but the page never scrolls)`
  - fix: Scroll the page to the current tier's section on appear and on slat tap (ScrollViewReader + .id per section), and demote the completed Head Coach card to a one-line summary row once the seat is filled. Gold, the emphasis colour, is currently spent on the one thing the player cannot act on.

- [ ] **Q-M65 · Vacancy rows leave roughly 70% of a portrait-iPad width empty between the text block and a plus glyph on the far edge**
  - evidence: "Assistant Head Coach / Vacant — Tap to hire / ~$1.3-7.0M/yr / 📈 +5% staff chemistry bonus" occupies x59–280 of a card that runs to x1443, with a lone ⊕ at x1427. The Offensive Coordinator row repeats the shape. With 23 vacancies to fill, this is the dominant layout of the screen.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:4098-4155 (HStack { VStack(leading) … Spacer(); Image("plus.circle") })`
  - fix: Use the empty right half for the decision: candidate count, best available OVR and his asking price, so the player can triage 23 seats without opening 23 sheets. Failing that, cap the row width or move to a 2-up grid in portrait.


### Hire list

- [ ] **Q-M66 · "TOP 3" badge splits a tie: two candidates both at OVR 68, only one is badged**
  - evidence: Row 3: "Cedric Wimberly [Solid Ceiling] [TOP 3] [FREE AGENT] 🔥1 … 68". Row 4: "Easton Waterhouse [High Ceiling] 🔥1 … 68" — identical OVR, no TOP 3 badge.
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:268`
  - fix: `cachedTop3IDs = Set(byOVR.prefix(3))` cuts the list at exactly 3 regardless of ties, so the badge depends on sort stability, not on merit. Include every candidate whose OVR ties the 3rd-place value, or badge by a threshold instead of a prefix. The same prefix logic drives `candidateRank`, so the tie also decides who is called "#1".

- [ ] **Q-M67 · Up to five unexplained badges ride on one candidate row and the only legend button covers colours**
  - evidence: "Cedric Wimberly [Solid Ceiling] [TOP 3] [FREE AGENT] 🔥1" and "Finnian Balfour [Limited Upside] [TOP 3] 🔥2", plus "High Ceiling" on row 4. The toolbar offers "Scheme ⓘ", "Perso…", "Colors" and an "Affordable" switch — "Colors" explains rating colours, nothing explains Limited Upside vs Solid Ceiling vs High Ceiling, or what the flame count means.
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:766-815`
  - fix: The flame already has an accessibility label ("2 rival teams pursuing") that never reaches a sighted player — surface it as a tappable tip like the Val/Scheme ⓘ, and fold the three ceiling labels into one legend row. A football fan should not need three taps to learn that 🔥2 means two clubs are bidding.

- [ ] **Q-M68 · The list poses a real trade-off and gives no way to hold two candidates side by side**
  - evidence: "Finnian Balfour … 48 Pro Passing 71 56 72" vs "Harlan Bourgeois [Limited Upside] … 35 Pro Passing 66 85 62" — 5 OVR against 29 points of play-calling and 13 years of age. There is no multi-select, no compare, no pin; opening either profile is a full-screen cover that replaces the list entirely.
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:2634-area (.fullScreenCover(item: $selectedCandidate))`
  - fix: Add a two-slot compare tray (FM's shortlist comparison): tap-and-hold to pin up to 3, then a side-by-side column view of the attributes the OC grade actually uses. On the 100th hire this is the only screen a returning player needs.


### Candidate profile

- [ ] **Q-M69 · "Best Available" is a superlative handed to three different candidates**
  - evidence: Header row: "# Ranked #1 of 30 candidates" with a gold "Best Available" chip at the right. The chip is not exclusive to #1.
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:1701 (if candidateRank <= 3)`
  - fix: Show "Best Available" only for rank 1; for ranks 2-3 show "Top 3" to match the list badge wording, so a player opening three profiles isn't told three times that he's looking at the best man on the board.

- [ ] **Q-M70 · SCHEME EXPERTISE prints raw enum values ("ProPassing", "WestCoast", "PressMan") on a card whose own first line says "Pro Passing"**
  - evidence: The card reads "Candidate prefers: Pro Passing" and then lists "ProPassing A-", "AirRaid C", "WestCoast D", "PowerRun F", "PressMan F", "Base34 F", "Base43 F", "Tampa2 F", "Cover3 F". The candidate list on 016 shows the same schemes as "Pro Passing", "West Coast", "Air Raid".
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:2197 (Text(scheme) on the raw [String: Int] key) — raw values defined in dynasty/dynasty/Domain/Enums/Scheme.swift:4-20`
  - fix: Map the dictionary key back through OffensiveScheme/DefensiveScheme and print .displayName, as `schemeFitCard` already does four lines above.

- [ ] **Q-M71 · SCHEME FIT refuses to answer at the exact moment the player needs it, and the reason is circular**
  - evidence: "SCHEME FIT — Candidate prefers: Pro Passing. You set the scheme as head coach. Compatibility is rated once your coordinators are in place." — shown with a grey (no-rating) dot on the screen whose entire job is deciding which coordinator to put in place. The candidate list on 016 has no "Fit" column either.
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:2169 and :651 (Fit column gated on hasInferableTeamScheme)`
  - fix: When the user is the head coach, compare the candidate's preferred scheme against the user's own selected scheme and rate it now — the data is already on the card (ProPassing A-). Failing that, say what the player must do ("Pick your offensive scheme in Schemes to see fit") rather than telling him to hire the coordinator first.

- [ ] **Q-M72 · An offensive coordinator's profile spends half a card grading him on seven defensive schemes, twelve rows of which are F by construction**
  - evidence: SCHEME EXPERTISE lists 15 rows for an OC hire: ProPassing A-, AirRaid C, WestCoast D, Spread D, then Shanahan/Multiple/PowerRun/Cover3/Base34/RPO/Hybrid/PressMan/Option/Tampa2/Base43 all F, with visually identical bar lengths. Cover3, Base34, Base43, PressMan, Tampa2, Multiple and Hybrid are defensive schemes an OC will never call.
  - code: `dynasty/dynasty/Engine/Simulation/CoachingEngine.swift:989-995 (unknown schemes roll 15 + adaptability bonus + 0...10, i.e. always F) and dynasty/dynasty/UI/Staff/HireCoachView.swift:2195`
  - fix: Filter the list to the side of the ball the role coaches, and collapse anything below D behind a "9 more, all F" disclosure. Twelve identical F rows are ~500px of a portrait screen carrying zero decision information.

- [ ] **Q-M73 · "CAREER HISTORY" is hash-generated flavour text with no record, no teams and no seasons**
  - evidence: The whole card is two lines: "22 years of coaching experience" and "Coordinator at 1 prior team". No club names, no years, no unit ranks, no won-lost — nothing a manager could use to tell a 22-year journeyman from a rising name.
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:1309-1345 ("Coordinator at \(1 + abs(candidate.id.hashValue) % 3) prior team")`
  - fix: This is the OOTP/FM gap that matters most on a coach profile: three prior seasons with team, role, and the unit's rank. If the sim doesn't persist coach history yet, rename the card "BACKGROUND" so it stops promising a record it cannot show, and start recording OC/DC unit ranks per season.

- [ ] **Q-M74 · Negotiation shows "Acceptance: High" — a computed probability flattened into a 20-point word**
  - evidence: "ⓘ Acceptance: High   Budget after: $40.4M" at the asking price of $6.6M, against a header badge reading "🔥 High demand (2 rival teams)" and a slider spanning $3.3M–$8.6M. The player cannot tell whether he is at 76% or 94%, or how far down the slider he can go before it breaks.
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:1243-1250 (chance = 1.0 - rejectionChance, then bucketed into 5 labels; "High" spans 0.75-0.95)`
  - fix: Print the number — "Acceptance 87%" — and mark the slider with the point where it drops below 50%, so lowballing becomes a readable risk instead of a guess.


### Hire result sheet

- [ ] **Q-M75 · Result copy uses internal dev vocabulary: "the pass", "down the ladder", "across three pots"**
  - evidence: 022 reads "The pass worked down the ladder, most decisive job first." and the SPENT chip's context line is "across three pots". 019's rail header reads "HIRING — TIER 2 OF 5". A football fan reading no manual does not know what "the pass", "the ladder", "a tier" or "three pots" are.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:792`
  - fix: Say it in football: "Filled the most important jobs first — head coach, then coordinators." and "coaching + medical + scouting budgets". "Tier 2 of 5" → "Step 2 of 5: Coordinators".

- [ ] **Q-M76 · The sheet names the problem — "22 jobs still open" — then offers only "Continue →"**
  - evidence: 019's modal reads "22 jobs still open on the staff." and its single button is "Continue →". Filling those 22 jobs requires dismissing the sheet, finding the Auto-Hire card (currently half-covered by the sheet: "Auto-Hire Recomm…"), and tapping again.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:1471`
  - fix: Make the one commit do the obvious next thing when jobs remain: "Hire the next one →" (opens the next vacancy in `orderedVacancies`) or "Fill the rest →" (runs auto-hire), with Continue as the plain dismissal. The sheet already knows `stillOpen`.

- [ ] **Q-M77 · Coach row prints "★★★★☆ Game Planning" next to a red "56 Play Calling" — two quality signals, opposite directions, neither explained**
  - evidence: Finnian Balfour's row on 019 reads "★★★★☆ Game Planning" on the left and a red "56 / Play Calling" on the right, with a green "✓ Good fit" underneath. On 022 the same pattern repeats: Zavier Goddard "★★★★☆ Adapta… / 62" in amber, Demetri Goddard "★★★☆☆ Player Dev / 58" in red. Nothing on the row says the stars and the number measure different things.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:4513`
  - fix: The stars are `starString(averageAttribute)` — the 12-attribute mean — rendered immediately adjacent to `primaryStrength`, so "★★★★☆ Game Planning" reads as a rating OF game planning; the big number is `playCalling` coloured by `RatingTier`. The two ladders also disagree (starRating calls 41–60 three stars, RatingTier calls anything under 60 poor/red), so a 4-star coach can show red. Caption the stars ("★★★★☆ overall") and put the strength on its own line, or colour the stars on the same RatingTier ladder the number uses.

- [ ] **Q-M78 · Coordinators header shows an uncaptioned "$8.0M–$17.1M" that includes the coordinator already signed, while the rail prices the same tier at "~$3.7M"**
  - evidence: 019 shows "2 Coordinators … $8.0M–$17.1M  1/3" in the section header, and the hiring rail one screen-third above says "2 COORDINATORS / 2 open · ~$3.7M". On 022 the header becomes "$9.6M  3/3" (6.6 + 2.0 + 1.0). So the header is the group total including the $6.6M already committed, but nothing labels it — beside "1/3" it reads as the cost of what is left.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:1096`
  - fix: `sectionSalaryRange` sums hired actual salaries with vacant role bands. Caption it ("group total $8.0M–$17.1M") or split it into "$6.6M committed · $1.4M–$10.5M to fill" so it reconciles with the rail's ~$3.7M plan for the same two chairs.

- [ ] **Q-M79 · Single-hire result reports Role / Salary / Budget-left but not one number about how good the man is**
  - evidence: 019's WHAT CHANGED grid is "ROLE Offensive Coordinator · SALARY $6.6M/yr · COACHING LEFT $40.4M". The screen behind immediately renders the same man as a red "56 / Play Calling". The sheet confirming a $6.6M/yr coordinator never shows his defining attribute, his fit with the HC, or his contract length.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:3537`
  - fix: Add a fourth chip — play-calling (coloured on the RatingTier ladder) plus the ✓/⚠/✗ fit band — so the celebration and the roster row agree. That is also content for the ~350pt of dead space in the same sheet.

- [ ] **Q-M80 · Hiring rail hides jobs-and-cost for every rung except the current one**
  - evidence: On 019 the rail reads "1 HEAD COACH / You", "2 COORDINATORS / 2 open · ~$3.7M", then "3 POSITION", "4 MEDICAL", "5 SCOUTING" with no sub-line at all. A player deciding how much of $40.4M to spend on coordinators cannot see that 8 position coaches, 3 medical and 5 scouting jobs are still to be funded without tapping each rung.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:3339`
  - fix: `subcaption` is gated on `guard state == .current else { return nil }`. Show "N open · ~$X" on future rungs too (dimmed) — the allocations are already computed once per render and handed to every slat.

- [ ] **Q-M81 · "Above league avg (~$35M)" is a hardcoded constant, not the league's actual mean, and sits under a spend line**
  - evidence: Green chip "Above league avg (~$35M)" is printed directly beneath "Used $6.6M of $47.0M", so it reads as a verdict on the $6.6M spend rather than on the $47.0M envelope. The comparison itself is not measured: `private static let leagueAverageCoachingBudget: Int = 35_000` with the comment "Hardcoded to $35M for now", while the 32 authored budgets in LeagueTeamData range from $24M (JAX) to $48M (NYJ) and BudgetEngine recomputes them every season.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:3610`
  - fix: Average the other 31 owners' `coachingBudget` rows at load and show the live figure plus a rank ("$47.0M · 4th of 32, league avg $38.1M"), and attach the chip to the "$47.0M" total rather than to the "Used" line.

- [ ] **Q-M82 · Two different prices for the same three coordinator seats: "~$3.7M" on the ladder vs "$8.0M–$17.1M" on the section header**
  - evidence: Tier slat: "2 COORDINATORS / 2 open · ~$3.7M". Section header 1,300 px below: "② Coordinators … $8.0M–$17.1M  1/3". Neither says what it covers: the slat is the auto-hire plan for the two OPEN seats only, while the header adds Balfour's already-signed $6.6M to the authored min/max of the two vacancies. A player comparing the two reads a 2-4x cost swing on the same decision.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:1110`
  - fix: Label the header "Committed $6.6M · 2 open $1.4M–$10.5M" (split the signed money from the estimate) so it decomposes into the ladder's "~$3.7M" plan instead of contradicting it.


### Staff after auto-hire

- [ ] **Q-M83 · "CLASHES 0 · none" sits directly above a coordinator row badged "⚠ Tension"**
  - evidence: The result sheet's fourth chip reads "CLASHES / 0 / none", and 380px below it on the same screenshot the DC row reads "Demetri Goddard · Age 49 · 13 yrs exp · Cover 3 · $2.0M/yr" with "⚠ Tension" underneath. A player reading "clashes: none" and then seeing a warning triangle on the man auto-hire just signed has been told two different things about the same hire.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:829`
  - fix: The chip counts `conflictHires` only — the ✗ Conflict band — while the row badge has three states (✓ / ⚠ Tension / ✗ Conflict, see the comment at CoachingStaffView.swift:893). The code is self-consistent but the word "Clashes" is not. Rename the chip "Conflicts" and add the tension count ("1 tension"), or report both bands: the ranking already penalises tension by −4, so the batch knows it happened.


### Career hub (offseason)

- [ ] **Q-M84 · The calendar badge and the rail's own counter disagree about how much offseason work is left**
  - evidence: On 025 the calendar icon in the top bar carries no badge (0 pending) while the rail header directly below reads "YOUR OFFSEASON  2/4" with two open rows, "Review coaching staff" and "Review coordinator schemes". On 013 the badge reads "2" while the rail reads "0/4" — four open rows. The badge has never matched the counter it sits above.
  - code: `dynasty/dynasty/UI/Career/CareerShellView.swift:2971`
  - fix: `pendingTaskCount` (CareerShellView.swift:2971) is `TaskGenerator.incompleteRequiredCount`; the rail's "n/4" counts all tasks including optional ones. Make both count the same set, or badge the calendar with total-incomplete and colour it red only when required work remains.

- [ ] **Q-M85 · Two near-identically named controls on one screen do different things: "Advance to Review Roster" vs "Roster Review →"**
  - evidence: The rail's gold button reads "Advance to Review Roster" (commits the phase change, irreversible). The hero card's button reads "Roster Review →" (just opens a screen). On this screenshot the hero button has also demoted to a dim olive capsule that is visually indistinguishable from the "Salary Cap" secondary beside it — only the arrow glyph separates them — so the card no longer has an internal primary either.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3836`
  - fix: The demotion is deliberate (`advanceOwnsTheGold`, :3827) but the labels collide. Rename the hero link to "Open Roster Evaluation" or "Inspect Roster", and keep "Advance to …" exclusively for the phase-committing control. When the hero link demotes, drop the arrow or restyle it as a plain text link so it stops competing with the secondary next to it.

- [ ] **Q-M86 · Hiring an entire coaching staff changes one counter on the hub and names not one coach you hired**
  - evidence: Comparing 013 (0 staff) with 025 (23 staff, $20.5M committed): every tile is identical except the STAFF card. Position Grades are unchanged ("QB S: A / D: C", RB still flagged NEED), Locker Room still "Elite 100/100" and "65%", Owner still 88%, Media still "Scrutinized", Messages still 2, and the hero still reads "Offseason Begins / Coach contracts expiring 0". The STAFF card itself lists only "HC You", "23 / 23 Staff" and the budget — the Offensive and Defensive Coordinators the phase exists to hire are named nowhere on the hub, and neither is their scheme.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1985`
  - fix: `staffTile` renders HC + slot count + budget only. Add OC/DC name + scheme rows (the phase's own optional task is "Review coordinator schemes", so the model has them), and let the Position Grades tile show a scheme-fit delta so the hire visibly moves a number. Reference: FM's staff panel names every coordinator with their attribute stars on the club overview; Madden's franchise hub shows the coordinator's scheme and its fit against the roster.


### Coaching staff review sheet

- [ ] **Q-M87 · "15/15 filled" sits above 16 green-ticked rows**
  - evidence: The COACHING STAFF card header reads "15/15 filled" while the list below it shows sixteen rows, each with a green checkmark: HC (You (The Tactician)), AHC, OC, DC, STC, QB, RB, WR, OL, DL, LB, DB, S&C, DOC, PHY, TRN. Cause: the counter is `ledger.filledCoachSlots/ledger.totalCoachSlots` (line 4871) and `StaffSlots.coachRoles(for: .gmAndHeadCoach)` deliberately excludes `.headCoach` (CoachRole.swift:205-210), but the sheet renders the "You" row separately, outside the `allRoles` loop, when `isGMAndHC` (line 4880-4889). The denominator is right; the visual count next to it is not.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:4871`
  - fix: Visually separate the "You" row from the counted seats — put it above the card with its own rule, or label the counter "15/15 staff hired · you hold the HC chair" — so the row that is not in the denominator does not look like it should be.

- [ ] **Q-M88 · Three different denominators on one rail — "YOUR OFFSEASON 2/4" over "STEP 1 OF 2", "STEP 2 OF 2" and "+ 9 more phases"**
  - evidence: The rail header reads "YOUR OFFSEASON" with "2/4" at the right. Directly beneath, "COACHING CHANGES · NOW · Feb" is subtitled "OFFSEASON · STEP 1 OF 2", "REVIEW ROSTER" is "OFFSEASON · STEP 2 OF 2", "THE COMBINE" is "PRE-DRAFT · STEP 1 OF 4", and the rail ends with "+ 9 more phases". Nothing labels what 4 counts. In code it is `Self.taskProgress(tasks)` — tasks in the current phase only (TimelineTasksPanel.swift:137-139), i.e. 2 of the 4 Coaching Changes tasks are done — but it is rendered on a header scoped to the whole offseason, which the same rail says is 2 phases and 15+ steps.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:139`
  - fix: Move the counter onto the current phase row it actually measures ("COACHING CHANGES · 2/4"), or label it in place: "THIS STEP 2/4".

- [ ] **Q-M89 · The advance gate shows 16 names and nothing else — every piece of decision content is below the fold, with "SCHEMES & EXPERTISE" clipped in half at the sheet edge**
  - evidence: The Coaching Staff Review sheet occupies roughly the middle 46% of the screen height on a 13" portrait iPad, and its entire visible area is the 16-row staff list. The next section header, "SCHEMES & EXPERTISE", is cut off mid-glyph at the sheet's bottom boundary and is the only clue anything follows. In code the sheet's VStack runs header → staffSection → schemesSection → warningsSection → buttonsSection (line 4792-4805), so the scheme-fit analysis, the team scheme banner, the staff-chemistry row, every validation warning and the real primary button ("Confirm & Advance to Review Roster", line 5474) are all below the fold. The gate exists to answer "is this staff ready" and shows no aggregate answer — no staff grade, no comparison to last year's staff or to the league.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:4792`
  - fix: Lead the sheet with a verdict block (overall staff grade, scheme fit for offense and defense, warnings count) and collapse the 16-row roster behind a disclosure. On a 13" iPad the sheet should also take the full height rather than leaving a lit hub visible on all four sides.


### Career hub (review roster)

- [ ] **Q-M90 · The franchise QB is named with an initial — "M. Wimberly" — while every other player has a full first name**
  - evidence: KEY PLAYERS tile: "QB1 M. Wimberly 86" beside "MLB Callum Abernathy 91" and "MVP Wade Braithwaite 94"; LOCKER ROOM tile: "QB Wimberly". The tile prints `player.fullName` (= "firstName lastName"), so the stored first name is literally "M." — `generateNamedQB` parses the team-select preview string "M. Wimberly" (LeagueTeamData.swift:89) into firstName "M." / lastName "Wimberly" and keeps it forever.
  - code: `dynasty/dynasty/Data/Import/LeagueGenerator.swift:1149`
  - fix: Give each preview QB a real first name in LeagueTeamData (add `startingQBFirstName`, or store "Marcus Wimberly" and let the preview card call `shortName()`); when parsing, expand a bare initial from the first-name pool rather than persisting "M.".

- [ ] **Q-M91 · "YOUR OFFSEASON 0/6" counts one phase's tasks while the same panel lists 11 more phases**
  - evidence: Panel header: "YOUR OFFSEASON  0/6". Directly below it the panel lists REVIEW ROSTER (6 tasks), THE COMBINE, FREE AGENCY, PRO DAYS & WORKOUTS and "+ 8 more phases" — so the offseason is 15 phases, not 6 items. The Season Guide (031) labels the same six rows correctly: "Review Roster … 2/6 tasks done". The header uses `taskProgress(tasks)`, which is the CURRENT phase's list, under a season-scope title.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:127`
  - fix: Title the counter with the phase it counts — "REVIEW ROSTER 0/6" under a "YOUR OFFSEASON" section label, or keep the title and show "Phase 4 of 15 · 0/6 tasks".

- [ ] **Q-M92 · One phase, four names: "Roster Review", "REVIEW ROSTER", "Review Roster", "Roster Evaluation"**
  - evidence: 029 quick-action chip: "Roster Review"; 029 hero button: "Roster Review →"; 029 sidebar phase: "REVIEW ROSTER"; 031 screen title: "Roster Evaluation"; 031 Season Guide: "Review Roster". Five separate maps for SeasonPhase.reviewRoster exist: SeasonPhase.swift:72 and TimelineTasksPanel.swift:951 say "Review Roster", CareerDashboardView.swift:3239 and CalendarSidebarView.swift:450 say "Roster Review", MainMenuView.swift:1007 says "Review", and the destination view is titled "Roster Evaluation".
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3239`
  - fix: Make `SeasonPhase.displayName` the single source ("Review Roster") and delete the four local switches; rename the destination's navigationTitle to match the button that opens it.

- [ ] **Q-M93 · The one required next task's title is truncated in the rail — "Review Position Grou…" — while the banner below spells it in full**
  - evidence: Sidebar row: "Review" / "Position Grou…" with the NEXT and Required chips on the first line; 400 px below, the red banner reads "Required: Review Position Group Grades". Same screen, same task, one name cut mid-word. Cause: the title is `.lineLimit(2)` sharing an HStack with the "NEXT" and "Required" capsules in a 300 pt rail.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:390`
  - fix: Move the NEXT/Required chips to their own line under the title (or drop NEXT when Required is present — they are redundant on the same row) and give the title `.lineLimit(3)`. The one row the player must act on is the one that must never truncate.

- [ ] **Q-M94 · "3-YEAR CAP" tile is ~55% empty: two lines of content in a card stretched to its neighbour's height**
  - evidence: The tile contains only "$265M → $320M" and "Projection across 3 seasons" in the top ~110 px of a ~245 px card; the lower half is blank. Its own icon is a trend chart, and the numbers that would fill it are already on the same screen ("Cap space (next yr) $142.2M", "Used $220.8M", "9 expiring contracts").
  - fix: Put the three per-season rows in it (2026 $265M / committed $220.8M, 2027 $283M / $141M, 2028 $320M / …) or a three-point sparkline of committed-vs-cap; failing that, let the card size to its content instead of matching the CONTRACTS tile.


### Roster evaluation

- [ ] **Q-M95 · Two adjacent headers are bound to the same sort key, and two sort columns have no header at all**
  - evidence: On 030/032 the header row is "Group | Starter | Strt / Depth | Avg Age | Cap $". In code, `sortableHeader("Starter", column: .starter, width: 64)` and `sortableHeader("Strt / Depth", column: .starter, width: 80)` sit on consecutive lines (643, 644) bound to the same `.starter` column, which sorts on `starterOVR` (line 397) — so tapping "Strt / Depth" does not sort by grade, and because `sortableHeader` lights gold and draws its caret on `sortColumn == column` (line 418-422), tapping either header lights BOTH headers gold with a caret simultaneously. The `SortColumn` cases `.avgOVR` and `.depth` have no header bound to them and are unreachable from the UI.
  - code: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:644`
  - fix: Bind "Strt / Depth" to `.depth` (or split it into two headers) so each header owns one key, and either wire up `.avgOVR` to a header or delete the case.

- [ ] **Q-M96 · "Priorities set: 0/9" names a job with nine em-dashes and no visible way to do it**
  - evidence: On 030/032 the card says "Setting priorities affects draft board rankings and scouting focus" and "Priorities set: 0/9 position groups", and the "You" column shows "—" on all nine rows. Nothing indicates the rows are tappable: no chevron, no disclosure indicator, no "tap a row to set" hint. The only visible affordance is the "Auto-Set Priorities" button, which makes the manual path look like it does not exist. In code each row IS a `Button` opening the note/priority sheet (line 685-693), and the dash is a plain `Text("—")` at micro size in textTertiary (line 775).
  - code: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:775`
  - fix: Replace the bare dash with a tappable "Set" pill (44pt tall) in the accent colour, or add a trailing chevron to each row, plus one line of helper text: "Tap any group to set your own priority."

- [ ] **Q-M97 · Roughly half the width of every table row is empty — the Staff/You chips are marooned ~750px right of the last data column**
  - evidence: On 030/032, in every one of the nine rows the last data value ends at the "Cap $" column (e.g. "$34.2M" ending around x=550 of 1500) and the next mark on the row is the "Solid" chip starting around x=1298. That is ~750px, half the row width, of empty space repeated nine times, on a portrait iPad. Cause: the columns are fixed-width (44 + 64 + 80 + 60 + 72 = 320pt of content) with a bare `Spacer()` between them and a right-aligned chip pair (RosterEvaluationView.swift:743, and the same `Spacer()` in the header at 649).
  - code: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:743`
  - fix: Spend the gap on the numbers a priority decision actually needs — starters count, expiring count in the group, snap-weighted age, last season's grade for trend — or distribute the columns across the full width instead of packing them left and pushing the badges right.

- [ ] **Q-M98 · The first column header wraps mid-word: "Grou" on one line, "p" on the next**
  - evidence: On 030/032 the leftmost header of the Position Group Grades table renders as "Grou" above "p", with the gold sort caret to the right — visibly taller than the rest of the header row and misaligned with the QB/RB/WR labels beneath it. Cause: `sortableHeader("Group", column: .group, width: 44, alignment: .leading)` hard-frames the label at 44pt, and because `.group` is the default sort the HStack also has to fit an 8pt chevron plus 2pt spacing inside that 44pt.
  - code: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:642`
  - fix: Widen to 60pt (the row's own group label at line 700 is already framed at 44 and only ever holds 2-3 characters, so widening the header alone is safe), or add `.fixedSize()` / `.lineLimit(1)` so the header never wraps.

- [ ] **Q-M99 · ST always shows "D: F" / "Depth needed" — a permanent flag telling the player to sign a backup kicker**
  - evidence: On 030/032 the ST row reads "77 · S: B- / D: F · 27 · $3.3M" with a gold "Depth needed" chip. ST is `[.K, .P]` (line 20) with ideal starter counts K:1 + P:1 = 2, so a roster carrying exactly one kicker and one punter — i.e. every well-built roster — produces `backups.isEmpty`, which forces `dGrade = "F"` (RosterView.swift:1648), which trips `depthBad` → "Depth needed" (RosterEvaluationView.swift:825). The flag can never be cleared and should never be acted on, and it is one of only two "Depth needed" chips on the screen, so it dilutes the one that is real (RB).
  - code: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:825`
  - fix: Suppress the depth grade and the depth flag for groups where the ideal depth count is zero — show "D: n/a" for ST — or grade specialist depth against the practice squad rather than an absent backup.

- [ ] **Q-M100 · Market value is computed for every Key Decision and thrown away — the screen says "at or slightly above market" without ever showing market**
  - evidence: On 030/032 four rows read "Solid contributor with value. Re-sign at or slightly above market." (Demetri Larrabee $8.2M, Norbert Yarborough $5.1M, Wade Hopewell $2.4M) with no market figure anywhere on the row — only OVR and current salary. The same list proves the number exists and can be printed: "Roman Brockway Age 26 UNDERPAID — Worth $3.9M more than current deal." `buildKeyDecisions` computes `let marketValue = ContractEngine.estimateMarketValue(player:salaryCap:)` for every player at line 2129 and uses it in the overpaid and underpaid branches, then passes it to `expiringRecommendation` which ignores it. Eight expiring rows ask for a re-sign decision without the one number the decision needs.
  - code: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:2129`
  - fix: Print market alongside salary on every expiring row — "$8.2M now · $9.4M market" — so the recommendation is auditable. On the 100th visit that turns the list from prose into a sortable delta column.


### Tasks panel

- [ ] **Q-M101 · Season Guide opens at the medium detent: the only required task is sliced in half at the sheet's bottom edge**
  - evidence: The sheet shows "Review Roster / Season 2026 · Week 0 / Phase 4 of 15 / 2/6 tasks done", then "⚠ Required (1)", then a row cut horizontally through the text "Review Position Group Grades" at the card's rounded bottom edge, where it bleeds over the underlying screen's text ("…ue. Re-sign at or slightly above market."). The task list, the Optional section, the schedule and the Advance button are all below the fold on a 13-inch iPad in portrait. `.presentationDetents([.large, .medium])` leaves SwiftUI to open at the smallest detent.
  - code: `dynasty/dynasty/UI/Career/CareerShellView.swift:777`
  - fix: Open at `.large` — `.presentationDetents([.large, .medium], selection: $guideDetent)` with the state defaulting to `.large` — so the required task and the Advance button are visible on open; keep `.medium` as a drag-down option.

- [ ] **Q-M102 · Table header wraps mid-word: the first column reads "Grou" / "p"**
  - evidence: The sortable header row renders "Grou" on line 1 and "p" on line 2 next to the sort chevron, above the QB/RB/WR column. The header is built with a fixed 44 pt frame: `sortableHeader("Group", column: .group, width: 44, alignment: .leading)`, and the caption-weight text plus the chevron do not fit. The neighbouring header is also abbreviated to "Strt / Depth".
  - code: `dynasty/dynasty/UI/Roster/RosterEvaluationView.swift:643`
  - fix: Widen the Group column to ~64 pt (or `.lineLimit(1).fixedSize()` on the header label) and spell "Start / Depth"; the row content is only 2-3 characters wide, so the width is free.


### Franchise tag

- [ ] **Q-M103 · Duplicate surnames and first names inside one 8-row list — two Braithwaites at the same position and price**
  - evidence: The expiring list shows "Wade Braithwaite / WR / $26.0M Tag Cost" at row 1 and "Zavier Braithwaite / WR / $26.0M Tag Cost" at row 5, plus "Wade Hopewell" at row 3. On 041_tag_task.png the pair "Zavier Braithwaite" and "Zavier Hambleton" sits three rows apart. RandomNameGenerator draws first and last independently from a 55-name and a 55-surname pool with no used-name check, so a 53-man roster collides by the birthday paradox with near certainty.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:88`
  - fix: Track issued (first, last) pairs and surnames per league and redraw on collision, or at minimum forbid a repeated surname inside one team. Two same-position players with the same surname and the same tag price three rows apart is a mis-tap waiting to happen.

- [ ] **Q-M104 · Eight identical gold "Apply Tag" buttons for a resource you have exactly one of, with no counter**
  - evidence: Every one of the eight expiring rows carries the same gold "Apply Tag" pill at equal weight. The one-per-season limit appears only inside the grey rules paragraph — "You can apply up to 1 franchise tag per season" — and the banner's status line spends its right edge on "8 expiring" rather than on tags remaining. Nothing on the row says applying one disables the other seven (they become "Tag Used").
  - code: `dynasty/dynasty/UI/Contracts/FranchiseTagView.swift:190`
  - fix: Add "1 tag available" to the banner beside "8 expiring" and demote seven of the eight pills — gold only on the recommended row, outline elsewhere — so a one-shot resource does not read as eight equal primary actions.

- [ ] **Q-M105 · Every interactive control on these screens is well under the 44pt minimum**
  - evidence: "Apply Tag", "Contact Agent" and (in the tagged section) "Remove" are all .font(.caption) with .padding(.vertical, 6) — about 26pt tall; on the 2064×2752 capture each pill measures roughly 44px against a 1366pt page height. On 036_negotiation.png the eight stepper buttons are .frame(width: 28, height: 28). Same defect on 041_tag_task.png, which shows seven more of each pill.
  - code: `dynasty/dynasty/UI/Contracts/FranchiseTagView.swift:419`
  - fix: Give every pill and stepper .frame(minHeight: 44) (or .contentShape with a 44pt hit area) — the visual size can stay if the touch region grows.

- [ ] **Q-M106 · Tagging costs 10 morale and the screen never mentions it, while advising the tag with no downside**
  - evidence: Row advice reads "Elite player — strongly consider tagging." and the only other line is "2027 space after tag: $116.2M". applyFranchiseTag does `player.morale = max(0, player.morale - 10)` and the engine's own comment says "R22: no player wants the tag — it costs 10 morale." The words morale and Morale do not occur anywhere in FranchiseTagView.swift.
  - code: `dynasty/dynasty/Engine/Contract/ContractEngine.swift:2130`
  - fix: Name the cost on the row ("−10 morale") and, since removeFranchiseTag refunds it exactly, say that too — a reversible action the player is afraid of is as bad as an irreversible one he isn't.


### Contract negotiation

- [ ] **Q-M107 · The composer opens pre-loaded with a lowball and never says so — the obvious single gold action tables it**
  - evidence: Agent asks "2 / $44.3M / $23.3M / 69%". The composer opens at "2 yrs / $37.5M / $17.0M / 59%" — exactly ask × 0.85 salary, ask × 0.75 bonus, ask − 10 guarantee (44.3 × 0.85 = 37.7 → $37.5M at the 500 step; 23.3 × 0.75 = 17.5 → $17.0M; 69 − 10 = 59). Nothing on screen labels the gap, and per this view's own code a tabled offer moves morale by −4 and, at a refusing camp, hardens the ask and costs pester morale.
  - code: `dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:1883`
  - fix: Print the delta against the ask beside each dial ("−$6.8M vs ask") and label the seed for what it is ("opening counter, 85% of his ask"), so the default gold button is a choice rather than an accident.

- [ ] **Q-M108 · Header says "Loyalty-Driven … Rewards commitment" while the agent's first line says the client "plays for the paycheck"**
  - evidence: Identity block: "Nina Kowalski | Loyalty-Driven | Old School" over "Rewards commitment. Discounts for teams that show respect." First bubble: "He plays for the paycheck. That's not a flaw, it's honest…". These are three independent models rendered as one block — AgentPersona.loyalist (bargaining style), AgentVoice.oldSchool (register) and AgentDesire.money (what the client wants) — but only the persona gets a label and a description, so the prose reads as a flat contradiction of the chips above it.
  - code: `dynasty/dynasty/Engine/Contract/AgentDialogueLibrary.swift:322`
  - fix: Give the client's desire its own labelled chip ("Wants: Money" / "Wants: To Win" / "Wants: The Ball") next to the agent's style chip, and reword the persona subtitle so it clearly describes the AGENT ("His agent rewards commitment…") rather than the player.

- [ ] **Q-M109 · The promised "discount for respect" runs on two hidden numbers, and the screen spends one of them invisibly**
  - evidence: "Rewards commitment. Discounts for teams that show respect." is the only guidance the screen gives on how to get a better price, but the inputs are player.loyaltyYears (openingTone: loyalist → .eager at ≥3 years) and player.morale (0.12 persona give plus a −0.06…+0.06 morale give in the pay-cut floor). Neither appears anywhere in the header, which shows only "WR  Age 30  $37.4M/yr  1yr left" and "94 OVR". The same screen then mutates morale on every round (+5 / +2 / −4, and −pesterMoraleCost per tabled offer at a refusing camp) with no readout.
  - code: `dynasty/dynasty/Engine/Contract/ContractNegotiationEngine.swift:1286`
  - fix: Put morale and years-with-club in the fact-chip row and show the morale delta each round in the transcript, so the resource the screen spends and the mechanic it advertises are both visible.

- [ ] **Q-M110 · ~255 pt of empty transcript between the agent's live counter and the controls you must answer it with**
  - evidence: The last message — Nina Kowalski's "$108.0M across 2 years" counter — ends at y≈1125 of the 2000px render; the composer panel starts at y≈1497. That is ~370 render px (~255 pt) of empty plate on a portrait iPad, because the transcript is top-aligned in its ScrollView with only three messages in it. The gold "Total: $92.0M" of your own standing offer sits a further 700 px above the dials that produced it, so comparing his $108.0M to your $92.0M means looking at opposite ends of the screen.
  - code: `dynasty/dynasty/UI/Contracts/NegotiationChat.swift:344-365`
  - fix: Bottom-anchor the transcript (defaultScrollAnchor(.bottom)) so the newest bubble sits against the composer, and consider pinning a one-line gap strip above the dials ("His ask $108.0M · yours $92.0M · gap $16.0M") in the space that frees up.

- [ ] **Q-M111 · The round band's per-round outcomes are computed, passed, and can never render — the band costs ~90 pt to repeat its own headline**
  - evidence: The ribbon shows three near-identical parallelograms reading "✓ ROUND 1", "2 ROUND 2", "3 ROUND 3" and nothing else, while the headline already says "ROUND 2 OF 3". The screen builds `roundOutcomes` — documented as "the money the club tabled in [each round], read straight off the transcript so the band cannot quote a number the conversation does not contain" — so ROUND 1 should carry "$37.5M", and the current slat should carry its subcaption "One of 3 the table will hear". Neither can appear: NegotiationRoundBand hardcodes isCompact: true, and DSSlatBand renders the second line only `if !isCompact`.
  - code: `dynasty/dynasty/UI/Contracts/NegotiationChat.swift:325; dynasty/dynasty/UI/Common/DSSlatBand.swift:713-726; dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:608-616`
  - fix: Either drop isCompact for this band (a negotiation IS the process the screen is about, which is the band's own criterion for full height) or render the outcome string in compact mode. As drawn, the band is 90 pt of chrome carrying zero information the one-line headline lacks.

- [ ] **Q-M112 · The cap sentence never says it is netting his existing $37.4M, so "$46.0M/yr" and "Charges $14.2M" look like a contradiction**
  - evidence: The composer footer shows "Cap Hit: $46.0M/yr" in gold and "Total: $92.0M" on the right, and the commit bar immediately under it says "Charges $14.2M of your $44.2M in room." Nothing on screen bridges the $31.8M gap — it is his current $37.4M coming off the books plus the front-loaded year-one hit. The code proves the omission is local to this shape: the tag-replacement branch of capSentence says "...net of the $X tag it retires" and the freeing branch says "...it comes in under the $X already on his row", but the plain re-sign branch returns the bare "Charges $14.2M of your $44.2M in room."
  - code: `dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:1277-1306`
  - fix: Give the .currentYear branch the same netting clause the other two have: "Charges $14.2M of your $44.2M in room — $51.6M in year one, net of the $37.4M he already carries." That single sentence also removes the apparent contradiction with the gold cap-hit figure above it.

- [ ] **Q-M113 · The round tracker goes backwards after signing: "ROUND 2 OF 3" becomes "1 ROUND SPOKEN" with round 2 hatched as never-used, and a closed talk still advertises "2 left"**
  - evidence: 037's band reads "ROUND 2 OF 3" with ROUND 1 ticked, ROUND 2 the live gold step, and the meter "1 spent · 2 left". After accepting, 038's band reads "1 ROUND SPOKEN", ROUND 2 and ROUND 3 are drawn as locked hatching ("never used — talks are over") even though the transcript now holds a second YOU bubble and the closing exchange, and the sheet says "Nina Kowalski closed it after 1 round." The meter is unchanged at "1 spent · 2 left" — patience left on a deal that is done. Cause: acceptAgentOffer() closes the thread without advancing live.round (submitCounterOffer and submitPayCut both do), so the ribbon retracts the step the player was standing in.
  - code: `dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:2417-2436; dynasty/dynasty/UI/Contracts/NegotiationChat.swift:316-325`
  - fix: Count the accept as a spoken round (or keep the ribbon's high-water mark when isClosed) so the band never shows fewer rounds than the transcript contains; and on a closed thread replace the patience meter with the outcome rather than leaving "2 left" on screen.

- [ ] **Q-M114 · "WHAT CHANGED" shows four absolute values and not one delta**
  - evidence: The section head reads "WHAT CHANGED" and under it sits "YEARS 2 · CAP HIT $54.0M/yr · TOTAL $108.0M · GUARANTEED 69%" — none of which is a change. What actually changed is invisible: his pay went $37.4M/yr -> $54.0M/yr, his term 1yr -> 3yr, and room $44.2M -> $21.2M (the 2026 figure confirmed on 045). DSResultSheet supports exactly this: each chip has an optional `context` line and the grid reserves a third row for it (rendering " " when empty, which is why the card has a blank band). The pay-cut branch of the same function uses it properly ("Was / Now / Freed"); the signing branch passes no context on any chip.
  - code: `dynasty/dynasty/UI/Contracts/ContractNegotiationView.swift:2693-2705; dynasty/dynasty/UI/Common/DSResultSheet.swift:195-205`
  - fix: Pass context deltas on the signing chips the way the pay-cut branch does: Cap hit "was $37.4M/yr", Years "was 1 left", and a room chip "$44.2M -> $21.2M". The data is already on the screen's state (salaryBeforeClose, teamCapSpace, capChargeAtClose).


### Franchise tag (applied)

- [ ] **Q-M115 · Every expiring row still coaches you to tag a player and projects the cap after tagging him, on a screen that says you have no tag left**
  - evidence: The rules card states "You can apply up to 1 franchise tag per season", Callum Abernathy already holds it, and every row's button is the disabled pill "Tag Used". Yet each row still prints tag advice and a tag projection: Wade Hopewell — "Solid contributor — tag if you can't afford to lose him" / "2027 space after tag: $65.8M"; Zavier Braithwaite — "Aging veteran at 32 — tag cost may not be worth it" / "2027 space after tag: $41.5M"; three more the same. Worse, those projections are computed as projectedNextYearSpace − tagCost against a $70.8M that already contains Abernathy's $17.3M tag, i.e. they price a second tag that the rules forbid. Meanwhile the gold — the app's emphasis colour — sits on the dead "Tag Cost" figures, and the one live control per row ("Contact Agent") is a low-contrast blue outline.
  - code: `dynasty/dynasty/UI/Contracts/FranchiseTagView.swift:382-470`
  - fix: When hasUsedTag, swap the row's guidance to the decision that is actually available (re-sign or let walk) and drop the "space after tag" line, or grey it with "tag unavailable — 1 per season". Move the gold to the live Contact Agent action.

- [ ] **Q-M116 · The tagged player's row is a dead end — no Contact Agent, no contract detail, so the tag-and-extend the engine models is not reachable from the screen that applies tags**
  - evidence: Callum Abernathy's row shows only "MLB · Callum Abernathy · Age 30 · 91 OVR", "$17.3M / 2027 Tag" and a red "Remove". Every expiring row below it gets a "Contact Agent" button; the tagged man does not, and his row does not show his current salary or years the way the expiring rows do ("$2.4M/yr", "$8.2M/yr"). The engine has a whole shape for the follow-up move — DealTargetYear.Shape.tagReplacement, with a tag-and-extend ceiling so "year one lands under the tag it retires" and a dedicated sentence "Frees $X in 2026 — year one lands under the $Y tag it retires" — and none of it is offered here. Madden's tag screen and OOTP's arbitration screen both put "tag now, negotiate long-term before the deadline" on the same row; here the tag reads as a terminal state.
  - code: `dynasty/dynasty/UI/Contracts/FranchiseTagView.swift:308-357; dynasty/dynasty/Engine/Contract/DealTargetYear.swift:283-300`
  - fix: Add the same contactAgentButton to taggedPlayerRow (the negotiation already plans .tagReplacement correctly) and show his expiring terms next to the tag figure, so the row states the real trade-off: play out the $17.3M tag, or convert it into a long deal that lands under it.


### Combine board

- [ ] **Q-M117 · GRD "B-/A" and PROD "AA"/"ELI" are unexplained on screen, though VoiceOver is told what they mean**
  - evidence: The table's third and fourth columns read "B-/A", "C+/A-", "B/A+" under "GRD" and green "AA" / "ELI" chips under "PROD", with no key anywhere on the screen; the Insights disclosure is collapsed and carries no legend when opened. `ProductionTierChip` supplies `accessibilityLabel("College production: \(tier.displayName)")` — so a VoiceOver user is told "College production: Elite" while a sighted user gets "ELI". The GRD pair is a scout *band* (`scoutBand(for:)?.displayText`), not current/ceiling, which nothing on screen says either. Same on 047.
  - code: `dynasty/dynasty/UI/Common/ProductionTierChip.swift:179`
  - fix: Tap-a-header popover, or a one-line key under the view-mode chips: "GRD = scouting range (low/high) · PROD = college production tier". The strings already exist as `tier.displayName`.

- [ ] **Q-M118 · Two gold fills compete on one screen, against this codebase's own one-gold rule**
  - evidence: A full-width gold banner "Send Scouts to the Combine — $140K from the scouting budget" sits mid-screen while the pinned action bar carries the gold primary "Advance — Interviews"; the gold "ADVANCE — INTERVIEWS" explainer rule and the gold active-sort header add two more gold marks. DSActionBar.swift:284 documents `dsPrimary` as "The one gold fill on a screen" and ScoutingHubView.swift:1330-1332 calls two gold primaries on one screen "the exact thing P5 forbids". The banner also hardcodes `cornerRadius: 10`, which is not a `DSCornerRadius` token (tight 4 / inline 8 / card 12).
  - code: `dynasty/dynasty/UI/Scouting/CombineResultsView.swift:572`
  - fix: Demote the banner to the secondary/outline treatment (it is an optional purchase, the advance is the stage's commit), or move the purchase into the action bar as the secondary and leave the table clean. Swap the 10 pt radius for `DSCornerRadius.card`.

- [ ] **Q-M119 · The "Skip Combine Review" caption measures 4.32:1 contrast — below AA — right beside a 15.8:1 explainer**
  - evidence: Sampled from the PNG: the caption "You go into the spring on the broadcast's rounded times." peaks at rgb(116,129,149) on rgb(19,29,47) = 4.32:1 at 11 pt (AA needs 4.5:1 for normal text). The explainer 300 px to its left, "Closes Combine Review and opens Interviews…", measures 15.82:1. Cause: the ghost caption is `DSType.display(11, .semibold)` at `.opacity(0.75)` over the ghost's `textSecondary` ink. The same bar's explainer carries a code comment saying it was raised out of exactly this state ("the user's own example of 'small dim text I can't read'") — the ghost caption was not raised with it. Same defect on 047.
  - code: `dynasty/dynasty/UI/Common/DSActionBar.swift:174`
  - fix: Drop the `.opacity(0.75)` on `DSActionLabel`'s caption and take it to 12 pt, or give it `textTertiaryReadable` — this line states what an irreversible skip forfeits, so it is read, not glanced at.

- [ ] **Q-M120 · Generated names collide constantly — three consecutive board rows share a first or last name**
  - evidence: Board rows 8, 9, 10 read "Bram Lovegrove", "Bram Vanterpool", "Tobias Lovegrove". The Combine Report on 047 lists "Jamari Goddard" and "Jamari Crisanti" in the same four-row Standout block. "Jace Hopewell" is prospect #12, "Kenji Hopewell" is the Hub's #1 prospect, and "K Hopewell" is an expiring contract on the user's own roster (screen 200) — three Hopewells across two screens. Cause: `RandomNameGenerator.randomName()` draws independently from a 55-name first pool and a 55-name surname pool with no uniqueness check, and `DraftClassBuilder` calls it once per prospect for a 350-man class (≈6 repeats per surname by expectation).
  - code: `dynasty/dynasty/Engine/Scouting/DraftClassBuilder.swift:586`
  - fix: Thread a used-names `Set<String>` through the class build and redraw on collision (and prefer at most one or two of each surname per class). The pools are already gate-checked as fictional, so growing them is cheap and would also cut first-name repeats.

- [ ] **Q-M121 · The Rank column is not a talent order — all 15 visible rows are "Rd 1" and the grades run non-monotonic**
  - evidence: Every visible Proj cell reads "Rd 1" (ranks 1-15 on both 046 and 047), while GRD down the same rows runs B-/A, B-/A, B-/A, C+/A-, B/A+, B/A+, C+/A-, C+/A-, B-/A, C+/A-, B-/A, B/A+, C/B+ — rank 4 (C+/A-) sits above ranks 5 and 6 (both B/A+). `sortColumn == .rank` sorts on `a.draftProjection ?? 999` with no tiebreak, so inside the ~32-man first round the numbering carries no information, and the base array it sorts comes from an unsorted SwiftData fetch.
  - code: `dynasty/dynasty/UI/Scouting/CombineResultsView.swift:239`
  - fix: Break the projection tie on the club's own board value (scout band mid-grade, then talent), so the Rank column is a ranking. A 350-row table whose first column is decorative costs the hardcore player their only ordering.


### Combine board (scouts on site)

- [ ] **Q-M122 · Combine Report prints every player's name twice, and 3 of 4 standouts share one identical fallback sentence**
  - evidence: Each row shows the name as its title and then repeats it inside the headline: "Jamari Goddard / Jamari Goddard posts elite combine numbers across the board", "Jace Hopewell / Jace Hopewell posts elite combine numbers across the board", "Jamari Crisanti / Jamari Crisanti posts elite combine numbers across the board". Only Davion Tanguay gets a specific line. The sheet draws `Text(mention.prospectName)` above `Text(mention.headline)`, and `standoutHeadline` builds the headline as "\(p.fullName) posts elite…" — the last-resort branch after three drill-specific ones.
  - code: `dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift:3675`
  - fix: Strip the name from the generated headline (the row already renders it) and widen the specific branches — a Top-10% bench, broad jump or 3-cone should each produce a sentence, so the generic fallback is rare rather than the default.

- [ ] **Q-M123 · Combine Report is a dead-end modal: 10 names, no numbers, no way to open any of them**
  - evidence: The sheet names Jamari Goddard, Davion Tanguay, Jace Hopewell, Jamari Crisanti and (clipped) Hayden Derringer with prose only — no 40 time except in Tanguay's line, no grade, no round. The rows are plain `HStack`s inside a `List` with no Button or NavigationLink, so none of the ten men can be opened from here; the only control is "Done". The sheet also spends ~230 pt on a hero "COMBINE REPORT / 10 notable performances" directly under a nav bar that already says "Combine Report", which is why only 4 of the 10 mentions fit before the fold.
  - code: `dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1773`
  - fix: Make each row a NavigationLink into ProspectDetailView and put the number that earned the mention on the row (40 time, bench, grade delta). Delete the duplicate hero header — the nav title covers it — and the count can move into the header as a subtitle.


### Combine interviews

- [ ] **Q-M124 · Band head says "STAGE 1 OF 6" while stage 1 says "Done" and the player is already working in stage 2**
  - evidence: On 049 the head reads "STAGE 1 OF 6", the slat under it reads "1 COMBINE REVIEW / Done · spends 1 scouting week" and carries the gold current rule, and slat 3 reads "3 FILM STUDY / Finish Interviews". On 051_interviews_selected the head still reads "STAGE 1 OF 6" while the "2 INTERVIEWS" slat is the selected one and the live "Conduct 53 Interviews" button is spending stage-2 slots. Only after the batch runs does 053_interviews_done read "STAGE 2 OF 6". Compounding it, the Interviews slat is the one slat with no sub-caption at all on 049 and 051 (`subcaption` is nil for a non-current stage by spec) — so the room you are standing and working in is the only room the band tells you nothing about, while a finished room advertises "spends 1 scouting week".
  - code: `dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1030`
  - fix: `bandHeadline` counts the `.current` cell; a stage whose own slat prints "Done" should not be `.current`. Either advance the pointer when `isSatisfied` becomes true, or count the head off the selected/reachable stage. And give the `.open` stage the player is actively working in its counter sub-caption ("0/60 interviews") rather than blank.

- [ ] **Q-M125 · The #1 prospect shows seven blank combine cells with no DNP marker, although the engine models DNP deliberately**
  - evidence: Row 1, "Kenji Shelburne" DT, blue-chip, grade A-/A+, prints "—" under all seven of 40YD, BENCH, VERT, BROAD, 3CONE, SHUT, DRILL, and his CMB chip is an empty dashed outline while every other row shows "CMB A+", "CMB A-", "CMB B" etc. The stage slat above reads "1 COMBINE REVIEW / Done". The engine treats this as a designed event — CombineResultsView's own comment reads "An invitee who did not work out has NO measurements at all (`ScoutingEngine.applyCombineDNP`) … a first-round talent with an empty card is a scouting decision, not a missing row" — but no DNP label exists anywhere in the board's column code, so on the Big Board a deliberate DNP is indistinguishable from missing data or a broken save.
  - code: `dynasty/dynasty/UI/Scouting/CombineResultsView.swift:169`
  - fix: Print "DNP" in the combine block (or a single "DNP — did not work out at the combine" chip on the name line) whenever `combineInvite && fortyTime == nil`, matching the treatment the Combine tab already gives it. It is a scouting signal the player should be able to act on, not a wall of dashes.

- [ ] **Q-M126 · Stale stage counter: header says "STAGE 1 OF 6" while the selected slat and the whole surface below it are "2 INTERVIEWS"**
  - evidence: The band head reads "STAGE 1 OF 6" at top-left; slat 1 is "1 COMBINE REVIEW / Done · spends 1 scouting week" and slat 2 "2 INTERVIEWS" carries the blue selection outline. Everything underneath is the interviews surface ("INTERVIEWS · 0/60 interviews", "PROSPECT INTERVIEWS", "Select Prospects to Interview"). bandHeadline indexes the cell whose state == .current, never the selected one, so the one place the process is allowed to print its count names a different room than the one on screen.
  - code: `dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1034`
  - fix: Either headline the SELECTED slat ("Stage 2 of 6") since the whole screen below is that stage, or keep the current-stage count but qualify it ("Stage 1 of 6 · viewing 2 Interviews"). As-is the number and the selection state contradict each other on every stage the user browses ahead.

- [ ] **Q-M127 · The same 0-of-60 quantity is printed four times in the top 250px, in three different formats**
  - evidence: Top to bottom: "INTERVIEWS · 0/60 interviews · 16% scouted · The Combine", the pill "0/60 used", "0/60 selected" over an empty progress bar, and "60/60 interviews remaining". Worse, the two denominators are different quantities: "selected" is `selectedProspectIDs.count / remainingSlots` (line 288) while the pill is `interviewsUsed / maxInterviews` (line 248), so after the first batch of 20 the screen would read "0/40 selected" beside "20/60 used".
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:288`
  - fix: Keep one counter — "N of 60 interviews used" — beside the action bar, and make the selection bar read "3 selected · 57 left" against the same 60. Two counters with silently different denominators on one screen is the drift this project's own DSResourceMeter doc ("the pips and the words can never disagree") was written to stop.

- [ ] **Q-M128 · "Select All Recommended" — the screen's one efficiency shortcut — is a ~17pt-tall tap target**
  - evidence: The gold capsule at the right of the "60/60 interviews remaining" row is `.font(.system(size: 10, weight: .bold))` with `.padding(.vertical, 4)` and `.buttonStyle(.plain)`, no minimum frame — roughly 17-18pt tall against the 44pt HIG minimum. It measures ~24px in a 1500px-wide render of a 2064px screen. The neighbouring "0/60 used" pill, the "Filter" pill and the row's "Deselect All" share the same 4pt vertical padding.
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:418`
  - fix: Give the capsule row `.frame(minHeight: 44)` with `.contentShape(Rectangle())` (keeping the visual pill small if the density is wanted). This is the control a hardcore player taps on the 100th visit to skip 15 individual selections — it should be the easiest thing on the screen to hit.

- [ ] **Q-M129 · 60 interview slots against a stated norm of 15-20 — the ration is not a constraint, so the stage has no trade-off**
  - evidence: The screen offers "60/60 interviews remaining" and "0/60 used" while telling the user in the same block that "League teams typically interview 15–20 prospects". DraftPrepProgress.interviewSlots = 60. Only 15 prospects are surfaced under RECOMMENDED, so "Select All Recommended" spends a quarter of the budget and no scarcity is ever felt; nothing on the screen says what an interview costs (the stage explainer says "No money").
  - code: `dynasty/dynasty/Engine/Scouting/DraftPrepProgress.swift:46`
  - fix: Cut the ration toward the 15-20 the copy itself quotes, or attach a real cost (scouting weeks, staff fatigue, a competing stage's budget) so choosing WHO to interview is the decision. As it stands the correct play on every playthrough is "select all recommended and move on", which is a dominant strategy, not a choice.

- [ ] **Q-M130 · Two circular controls per row — an empty dashed circle outside the card and a gold tick inside it — with nothing saying which one is the interview selection**
  - evidence: Every visible row renders an unfilled dashed circle in the left gutter, outside the row's card border, then a gold ✓ inside the card: "○  ✓ OLB Easton Hinsdale", "○  ✓ TE Judah Smallwood", "○  ✓ RT Seneca Truesdale". The outer one is `ProspectMarkButton` (unmarked state), the inner is the interview checkbox. Both are ~20 pt circles about 50 px apart, both unlabelled, and they are in opposite states on all 15 rows — the reading "the circle is off, so this row is not selected" is available to any first-time player.
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:636`
  - fix: Give the mark button its filled/outline star or bookmark glyph in the unmarked state instead of a bare circle, so the two controls are not both circles; or move the mark into the row's trailing block and leave only the checkbox in the leading gutter.

- [ ] **Q-M131 · The interview ration is printed five different ways in one 350 px header, and "X/Y selected" silently changes its denominator between screens**
  - evidence: Within the header block: "INTERVIEWS / 0/60 interviews · 16% scouted", the pill "0/60 used", the progress line "53/60 selected", the row "60/60 interviews remaining", and the button "Conduct 53 Interviews". Four of those five are the same fact. Worse, `Text("\(selectedProspectIDs.count)/\(remainingSlots) selected")` uses REMAINING as the denominator while the pill next to it uses the TOTAL: on 051 both happen to be 60 so "53/60 selected" reads as capacity, but on 053_interviews_done the same line reads "0/7 selected" directly beneath "53/60 used" — the same label, two different scales, one screen apart.
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:288`
  - fix: Print the ration once, in one scale. Keep "53 selected · 7 of 60 slots left" as a single line and delete the pill and the remaining-row. Fix the denominator to `maxInterviews` so the progress bar never rebases mid-cycle.

- [ ] **Q-M132 · Batch controls are ~21 pt tall — under half the 44 pt minimum**
  - evidence: "Select All Recommended" and "Deselect All" measure ~42 px tall on the 2064 px capture, i.e. ~21 pt. In code both are 10–11 pt text with `.padding(.horizontal, 8).padding(.vertical, 4)` and no minimum frame. The info banner's dismiss control is a bare `Image(systemName: "xmark")` at `.font(.system(size: 10))` with no frame at all. The per-row mark button sits at `.frame(width: 36)`. "Select All Recommended" is the single highest-leverage control on the screen — it commits 53 of 60 slots' worth of selection in one tap.
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:416`
  - fix: Give every capsule `.frame(minHeight: 44)` (keep the visual pill smaller via `contentShape(Capsule())` if the 21 pt look is wanted), frame the banner ✕ at 44×44, and widen the mark button's hit area to 44.

- [ ] **Q-M133 · Selection chrome persists over the report: "0/7 selected", an empty progress bar and a live "Filter" pill above a screen with nothing to select or filter**
  - evidence: The report state shows "PROSPECT INTERVIEWS", "Reveals: Football IQ (exact) · …", "Interviews run by OC Finnian Balfour", "0/7 selected" with an empty bar, "League teams typically interview 15–20 prospects" and a gold "Filter" pill — all sitting above "INTERVIEW REPORT / 53 interviews completed". The body below is 53 read-only result cards. In code `header` is rendered unconditionally in the VStack before the branch that swaps `selectionList` for `InterviewReportView`, so every control in it survives into a state where it controls nothing.
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:174`
  - fix: Move the selection-progress block and the Filter menu inside the `selectionList` branch, or swap the header for a report header (batch date, interviewer, slots left) when `showResults || viewingPastReport || remainingSlots == 0`.

- [ ] **Q-M134 · SUMMARY card is centred at ~40% width with ~600 px of dead space each side, while every result card below is full-bleed**
  - evidence: The SUMMARY card ("53 interviewed", "18 low, 19 med, 16 high risk", "9 off-field concerns", "Best: Kenji Shelburne — Grade A") spans roughly x=680…1390 of the 2064 px portrait width; the Kenji Shelburne card directly beneath spans x=30…2035. The single most decision-dense block on the screen is the narrowest thing on it, and the two blocks share no left edge. `summarySection`'s VStack has no `frame(maxWidth:)` and sits in a centre-aligned LazyVStack, so it hugs its text.
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:1236`
  - fix: Add `.frame(maxWidth: .infinity, alignment: .leading)` to the summary VStack so it aligns with the cards, and use the recovered width for a fourth and fifth pill (position breakdown, average football IQ) instead of empty ground.

- [ ] **Q-M135 · Two gold-filled primaries stacked at the bottom, and the full-width one is the lesser action**
  - evidence: "Complete Review → Return to Interviews" renders full-width in `Color.accentGold`, and directly under it the action bar's "Advance — Film Study" renders in `Color.accentGold` too. The eye hits the full-width one first, but it returns you to a selection list with 7 slots left; the smaller one is the actual forward move the explainer describes ("Closes Interviews and opens Film Study"). The hub's own code comment for this bar states the rule being broken: "and ONE gold primary".
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:1185`
  - fix: Demote "Complete Review → Return to Interviews" to a bordered/ghost style (it is a dismiss, not a commit), leaving the stage advance as the only gold on the screen. Better still, since 7 slots remain, label it "Interview 7 More" so it says what it buys.

- [ ] **Q-M136 · "16% scouted" is unchanged by spending 53 of 60 interview slots — the stage's payoff is invisible in the chrome that frames it**
  - evidence: The card header reads "INTERVIEWS / 53/60 interviews · 16% scouted · The Combine". On 049_interviews before any interview it read "46 of 288 filed on · 16% scouted" and on 051_interviews_selected "0/60 interviews · 16% scouted". The one progress percentage the hub prints is `scoutedCount / prospects.count` where `scoutedCount = prospects.filter { ProspectFog.hasOwnReport($0) }`, so interviews — which write exact Football IQ plus revealed AWR/LRN/CMP/LDR/WRK bands onto 53 men (18% of the class) — cannot move it. The player's biggest single action of the week reports zero progress.
  - code: `dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:544`
  - fix: Either add a second coverage clause the stage does move ("53 met"), or widen the coverage metric to count any first-party intel (report, interview, workout, visit) so the number the hub repeats on every screen actually responds to the work.

- [ ] **Q-M137 · 53 result cards ranked "#1…#53" with no stated ranking basis, no sort, no filter, and the summary's "9 off-field concerns" is not reachable**
  - evidence: Header reads "INTERVIEW REPORT / 53 interviews completed"; cards are "#1 Kenji Shelburne DT Washington Rd 1" then "#2 Declan Colgrove DT Ohio State Rd 7". Nothing on screen says the ordinal is `interviewScore` — a projected 7th-rounder ranking above 51 men reads as a bug until you know that. Both cards show "A Grade", so the summary's "Best: Kenji Shelburne — Grade A" superlative is undecidable from what is displayed. The summary's "9 off-field concerns" and "16 high risk" are static text: reaching those 9 men means scrolling 53 cards of ~250 pt each.
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:1146`
  - fix: Caption the report "Ranked by interview score (IQ + character + leadership)" and print the score on each card so ties are readable. Make the summary pills filters — tapping "9 off-field concerns" should reduce the list to those 9 — and add a compact table mode for the 100th visit.


### Film study

- [ ] **Q-M138 · Name generator produces guaranteed surname collisions — two Colgroves and two Hinsdales inside 13 rows, three Hopewells and three Goddards across screens**
  - evidence: On 054: "Hayden Colgrove · RG · Texas A&M" and "Jeremiah Colgrove · TE · Minnesota"; "Easton Hinsdale · OLB · UCLA" and "Ezekiel Hinsdale · CB · TCU"; also two Zachariahs (Broadwater, Jaramillo) and two Jamaris (Crisanti, Goddard) in the same 13 rows. Cross-screen: "Jace Hopewell · LT · Utah" (054) vs "#1 Kenji Hopewell / QB — Oklahoma" (075/500) vs "DEN land RT Kason Hopewell (88 OVR) from CLE" (075/500 trade wire); "Jamari Goddard · LG · Clemson" (054) vs roster "CB Goddard 89 $12.8M" and staff "Demetri Goddard" (075/500).
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:66-77, :86-91`
  - fix: `RandomNameGenerator.randomName()` draws `firstNames.randomElement()` × `lastNames.randomElement()` from 55×55 with no uniqueness pass. A 350-man draft class from 55 surnames averages 6.4 men per surname — collisions are structural, not unlucky. Draw without replacement per class (and per league) with a fallback, or widen the surname pool; in a game where the board is scanned by surname, two Colgroves in one screenful is a real identification cost.

- [ ] **Q-M139 · Neither of the two stacked bottom bars is tappable, and the top one's label is an instruction, not an action**
  - evidence: Bottom bar 1 (full width, dark): "▤ Select Prospects to Put on Tape". Bottom bar 2: orange rule + "ADVANCE — PRO DAY FOCUS / The pro-day circuit opens after free agency." with a grey "Advance — Pro Day Focus" button at the right. Both are disabled. A player who reads no manual has no enabled control anywhere below the table and no sentence telling him where to go instead.
  - code: `dynasty/dynasty/UI/Scouting/FilmStudySelectionView.swift:412-413; dynasty/dynasty/Engine/Scouting/DraftPrepProgress.swift:344 vs :363; dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1377`
  - fix: The run-bar label is `blockedReason`, which returns the sentence "Select Prospects to Put on Tape" when the selection is empty — a button whose text tells you to do something else. Keep the verb on the button ("Put 0 on Tape", disabled) and move the instruction to a caption. For the advance bar, `DraftPrepProgress` has a longer variant that ends "— advance the calendar to get there"; the short one shown here (:363) drops the only actionable clause. Ship the actionable one, and give the bar a live route (e.g. "Go to Free Agency").

- [ ] **Q-M140 · PDAY / VISIT / WORK columns render 39 empty circles on a screen where all three of those stages are locked "After FA"**
  - evidence: Table header: "POS  NAME … OVR  RPT ⓘ  PDAY  VISIT  WORK  FILE  TAPE  NEXT". Every one of the 13 rows shows an identical empty ○ under PDAY, VISIT and WORK. The stage strip above the table shows those exact stages hatched out: "4 PRO DAY FOCUS / After FA", "5 PRIVATE WORKOUTS / After FA", "6 TOP-30 VISITS / After FA". Meanwhile there is a ~550px horizontal void between the NAME block and the OVR column — roughly 37% of the table width carrying nothing on every row.
  - code: `dynasty/dynasty/UI/Scouting/ProspectListControls.swift:1173-1189`
  - fix: The `.workup` header block emits PDAY/VISIT/WORK unconditionally. Gate them on whether that stage has opened, and spend the reclaimed width on the NAME/college/projection block (which currently truncates college + round into a 280px stub) or on a rank column. Three columns of guaranteed-empty circles is not an information display.

- [ ] **Q-M141 · FILE column uses a five-symbol vocabulary with no legend — "CLEAN", "—", "1?" and "1" all appear on one screen**
  - evidence: FILE column values down the visible rows: "CLEAN" (Ackerly, Broadwater, Brockway, J. Colgrove, Crisanti, Hinsdale, Jaramillo), "—" (Cartwright, Goddard, Hopewell), "1?" (H. Colgrove), "1" (Engelhardt), "—" (E. Hinsdale). Nothing on the screen defines them. The only column with an explainer is RPT, which carries an ⓘ tooltip button; FILE, TAPE, PDAY, VISIT and WORK carry none.
  - code: `dynasty/dynasty/UI/Scouting/ProspectListControls.swift:940-961; tooltip precedent at :1174-1180`
  - fix: In code "—" means *count-level disclosure, zero flags* and "CLEAN" means *full disclosure, zero flags* — two glyphs for the same fact, differing only in how much the club has earned. "1?" vs "1" is the same split with one flag. Give FILE the same ⓘ tooltip RPT has, spelling out all five states, or collapse the disclosure distinction into a single tint on one glyph.


### Cap compliance

- [ ] **Q-M142 · Restructure says "Not available" with no reason, though the engine already wrote the reason and the Release lever beside it shows one**
  - evidence: On 060 three rows read "Restructure — / Not available": M. Wimberly (1 yr left), Callum Goddard (1 yr left), Roman Brockway (1 yr left); on 061 Wilkes Vestergaard (1 yr left) does the same. One row away, a blocked Release lever DOES explain itself: Isaias Laurelwood shows "Release — / Last RT on the roster — sign or trade for another first". The engine models the reason: `ContractEngine.RestructureVerdict` is documented "Why a restructure is not on the table, phrased for the user" and carries `.unavailable(String)` (ContractEngine.swift:1653-1656). CapComplianceView.swift:571 discards it via `restructureVerdict(for:).quote`, and line 423 substitutes the generic `?? "Not available"`.
  - code: `dynasty/dynasty/UI/FreeAgency/CapComplianceView.swift:571`
  - fix: Render the verdict's own sentence in the footnote, exactly as the Release lever does with `releaseBlockReason`: keep the `RestructureVerdict` and fall back to its associated string instead of a literal. The leverButton footnote is already `lineLimit(2)` for precisely this case (line 465).

- [ ] **Q-M143 · A compliant team is shown a 46-row "how to cut your players" workspace as the entire screen body**
  - evidence: The status card reads "✓ Cap Compliant · Cap Usage 77.2% · $284.1M Salary Cap · $219.3M Used · $64.8M Available" and the step subtitle reads "Under the cap — the market will take your offers". Everything below that on 060, and all of 061, is "Levers — Ranked by Cap Freed · 46 players" — release/restructure/renegotiate tiles for men the club has no reason to touch. The action this screen actually wants ("Enter free agency →") is a chip in the bottom-right corner. The band and the list are stacked unconditionally in the body (CapComplianceView.swift:96-104); `isOverCap` changes only the subcaption and whether the primary button is enabled.
  - code: `dynasty/dynasty/UI/FreeAgency/CapComplianceView.swift:96`
  - fix: When `isOverCap == false`, collapse the levers card behind a disclosure ("46 ways to free more room") and give the freed space to what a compliant GM needs next — room by position, top remaining needs, what $64.8M buys. Keep the full workspace expanded only when the club is over.

- [ ] **Q-M144 · "Ranked by Cap Freed" but the ranking number is not a column, so the order reads as random**
  - evidence: Header: "Levers — Ranked by Cap Freed · 46 players". Row 3 is Wade Braithwaite whose Release reads "$-20.5M" — a negative — sitting ABOVE Callum Goddard's "+$11.4M" release. On 061 Wilkes Vestergaard ($3.8M/yr) sits above Wade Hedgepeth ($3.9M/yr) and Isaias Laurelwood ($5.5M/yr). The sort is actually correct — `bestSaving` returns `max(release, restructure)` (CapComplianceView.swift:512-518), so Braithwaite ranks on his Restructure "+$24.3M" — but that max is never displayed, so the user must mentally take the larger of two tiles on every row to see why the list is in this order.
  - code: `dynasty/dynasty/UI/FreeAgency/CapComplianceView.swift:330`
  - fix: Show the ranking number: a right-aligned "Best: +$24.3M (restructure)" on the identity line, or give the winning tile a highlighted border. Alternatively rename the header to what it actually ranks — "Ranked by best available relief".

- [ ] **Q-M145 · The Renegotiate lever is byte-identical on all 46 rows — "Ask / His call" carries zero per-player information**
  - evidence: All 14 visible rows on 060 and all 9 on 061 show the same three lines: "Renegotiate / Ask / His call" — Wimberly, Abernathy, Braithwaite, Goddard, Larrabee, Brockway, Frobisher, Kirkbride, Vandenberg, Auchter, Ottinger, Vestergaard, Hedgepeth, Laurelwood. The header says "46 players". CapComplianceView.swift:430-436 hardcodes `headline: "Ask", footnote: "His call", enabled: true` for every player. A third of every row's width on a 46-row list tells the user nothing about which man would actually take a cut — and the engine knows, since the view already handles a "He wants his release" refusal (lines 167-174).
  - code: `dynasty/dynasty/UI/FreeAgency/CapComplianceView.swift:430`
  - fix: Put a cheap per-player signal in the footnote — the engine's read on willingness (contract year, age, market value vs salary), e.g. "Likely" / "Long shot" / "Wants out" — or collapse the column to a single icon and give the width back to the two levers that carry real numbers.


### Free agency — market

- [ ] **Q-M146 · Step rail sub-caption prints "Frenzy" twice: "Day 1 · Frenzy · Frenzy: top FAs sign fast"**
  - evidence: Under the gold "4 SIGNING" slat: "Day 1 · Frenzy · Frenzy: top FAs sign fast". Present identically on 064 and 065.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:582`
  - fix: `signingSubcaption` prepends "Frenzy · " when `phase.isFrenzy`, and the round-1 and round-2 descriptions already begin with the word: `PhaseInfo(label: "Day 1", description: "Frenzy: top FAs sign fast", isFrenzy: true)` (FAWeeklyView.swift:560). Drop the prefix, or strip the word from the two frenzy descriptions ("top FAs sign fast" / "bidding wars peak") so the prefix carries it once.

- [ ] **Q-M147 · Rows are 122pt tall — 2.8x the design system's own "scan" spec — so 7 of "126 on the board" are visible while 60% of each row is empty**
  - evidence: Measured row dividers at y = 1114, 1358, 1602, 1846, 2090, 2334 — a pitch of 244px = 122pt on a 2x display. Header says "126 on the board"; 7 fit on a 13-inch portrait screen, so the board takes ~18 screens to scroll. Row 1's content ends at x=812 of 2064 ("10 teams interested"), and the Host Visit line ends at x=361 — the right 60-82% of three of the row's four lines is empty, while the OVR/AGE/ASKS/YRS columns sit alone on the top line.
  - code: `dynasty/dynasty/UI/Common/DSListRow.swift:58`
  - fix: `DSListDensity.scan` is documented as "~44 pt, 8-14 info elements — the default list: roster, board, FA market" and this screen names itself an example of it, but the FA row stacks four full-width lines. Move the cap-impact badge, the interest reading and the Host Visit control into the dead right half beside the number columns to get the row toward two lines, or expose the `glance`/`scan`/`study` density control (`DSListDensity` is already `CaseIterable` with `label`s) so a hardcore player can see 20 names at once on the 100th visit.

- [ ] **Q-M148 · Both inline controls miss the project's own 44pt rule: Host Visit is 32pt tall, the position filter chips 31pt**
  - evidence: Measured the "Host Visit" capsule fill (17,31,59) from y=1034 to y=1098 → 64px = 32pt tall. Measured the selected "All" chip's blue border at y=680 and y=740 → 62px = 31pt tall; the QB/Skill/OL/DL/LB/DB chips match. Same on 064 and 065.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:1611`
  - fix: The design system quotes the rule against itself at DSListRow.swift:76-78 — "every button, link, capsule, segment, stepper AND ROW is >= 44 pt in both axes — measured rects, not declared styles". `visitControl` declares `.frame(minHeight: 32)` (line 1611) and `positionFilterBar` relies on `.padding(.vertical, DSSpacing.xs)` with no minimum (line 1179). Set `minHeight: 44` on both. Host Visit is the more urgent: it is a 32pt target sitting inside a row that is itself a button to the offer sheet, so a near-miss silently opens the wrong surface.

- [ ] **Q-M149 · The news ticker is the hardcoded stub fallback, and it contradicts the board it sits on top of**
  - evidence: All four visible chips are verbatim placeholder strings: "FA market opens — top FAs hitting the wire", "Bidding wars expected on premier QBs", "Visit schedules being arranged league-wide", "Cap-rich teams r…". Meanwhile the board's top 7 by OVR contains zero QBs — SS, RT, FS, SS, DT, RG, DT — so the ticker promises a QB bidding war that this market does not have. Same on 064 and 065.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:2334`
  - fix: The comment names it: "Stub fallback so the UI is visible during early FA when no bid data exists". Items 1-3 of `computeTickerEvents` all require `FABid` rows, which do not exist until `processRound()` runs — so the stub is what every player sees on Day 1, the first and most consequential market day, every season. Seed the ticker from data that does exist at that moment: the highest-`marketInterest` names on the board, the club's cap room versus the league's, the top asks by position. "Kason Marsden (SS, 90) draws 10 clubs — $18.1M ask" is a real headline available before a single bid is cast.

- [ ] **Q-M150 · The board carries no roster-need or depth reading, so the highest-OVR name is always the apparent right answer**
  - evidence: The top two rows are both strong safeties — "Kason Marsden SS 90 · 30 · $18.1M · 3" and "Nehemiah Bolliger SS 86 · 30 · $12.3M · 2" — and nothing on the screen says whether Houston already starts an 88 at SS. The columns are POS / FREE AGENT / OVR / AGE / ASKS / YRS; the only positional tool is the All/QB/Skill/OL/DL/LB/DB filter, which filters but does not rank by need.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:1393`
  - fix: Grepping FAWeeklyView for needScore/positionNeed/depthAt/teamNeed returns nothing — the screen surfaces none of the roster model the engine already has. FM's squad screen and Madden's FA board both show "your current starter at this spot" inline; OOTP shows depth-chart delta. Add an upgrade-over-incumbent column ("+4 over Hollis, 88") or a need tint on the POS badge, so signing a 90 SS behind an 88 SS reads as the luxury it is instead of the obvious top-of-board pick. Right now the trade-off is fake: sort by OVR, buy the top name you can afford.

- [ ] **Q-M151 · "Will use 6% of cap" is measured against a total cap the screen never shows, while the ledger two lines above shows a different denominator**
  - evidence: The ledger reads "CAP ROOM $64.8M  PENDING —  AVAILABLE $64.8M". Row 1 reads "$18.1M" and "Will use 6% of cap". $18.1M is 28% of the $64.8M the screen actually says you have; the 6% is against a ~$264M total cap that appears nowhere on this screen (back-solved from the seven visible pairs: 18.1→6%, 17.2→6%, 14.2→5%, 12.3→4%, 18.4→6%, 9.9→3%, 15.9→6%).
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:1671`
  - fix: `capImpactBadge` computes `Double(asking) / Double(cap)` against `team?.salaryCap`. The decision this screen exists to support is "can I afford him from what is left", so the honest reading is the share of AVAILABLE room — or print both, e.g. "$18.1M · 28% of your room". At minimum name the denominator so two percentages on one screen do not silently mean two different things.

- [ ] **Q-M152 · Returning from a player's sheet leaves no trace on the board — the market is pixel-identical to before the tap**
  - evidence: 064_fa_offer_sheet.png differs from 062_fa_market.png only inside the bounding box (107,21)-(123,43), i.e. one status-bar clock digit; every pixel of the app is unchanged. After opening 063_fa_player_sheet.png and coming back, Kason Marsden's row still shows a dashed empty "BID" slot, the ledger still shows "PENDING —", and the bar still shows "NO OFFERS ON THE TABLE". Nothing marks the row as seen, considered or dismissed.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:1526`
  - fix: The row reserves three state slots (BID / VST / HEAT) and the design system's own note says "what the user is scanning for is the gap" — but there is no slot for "I already looked at this man and passed". With 126 names, 7 rows to a screen and 6 market days, the player has no way to resume a pass over the board. Add a fourth reserved slot or a subdued row treatment for opened-and-declined, plus a shortlist/star the offer sheet can set on dismiss.


### Free agency — skip dialog

- [ ] **Q-M153 · The irreversible skip confirmation names none of the three resources it forfeits, all of which are visible behind it**
  - evidence: The alert reads "Skip Remaining Free Agency? / AI teams will sign remaining free agents based on their needs. You won't be able to make any more signings." Behind it the screen shows "Visits left 3/3", "126 on the board", "AVAILABLE $64.8M", and "FREE AGENCY · STEP 4 OF 5 … 1 spent · 5 left". The alert quantifies nothing.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:315`
  - fix: The alert message is a static string. Interpolate the stakes the screen already computes: "You are leaving $64.8M in cap room, 3 facility visits and 126 free agents to the rest of the league, with 5 market days unplayed. This cannot be undone." The action bar's own explainer already found the right voice for this ("a day you cannot get back") — the confirm step is where it matters most.


### Free agency — complete

- [ ] **Q-M154 · Three contradictory verdicts on the same signing inside one card — a fan cannot tell whether this was good**
  - evidence: On one screen Callum Abernathy is simultaneously: "Headline signing: Callum Abernathy (MLB, 91 OVR)" in a green capsule with a green up-arrow (FACompleteView.swift:243-255); "Replaces Brixton Tanguay (+14 OVR)" in green (lines 450-452); and "Big Overpay" in a red chip (line 46, `.bigOverpay` → Color.danger). The page header above all three reads "DISAPPOINTING FA — Critical needs went unaddressed. The pressure is on the GM." and the grade below reads "D". The green capsule is unconditional — `recentSignings.first` is celebrated no matter how bad the deal was.
  - code: `dynasty/dynasty/UI/FreeAgency/FACompleteView.swift:243`
  - fix: Let the value tag drive the capsule: a Big Overpay headline signing should render in warning colour with a down-arrow, e.g. "Biggest commitment: Callum Abernathy — $101.0M for a 91 MLB, above market". One player should carry one verdict on one screen.

- [ ] **Q-M155 · The same MLB position badge is red on Cap Review and blue on FA Complete**
  - evidence: 060 renders Callum Abernathy's "MLB" badge on RED, alongside QB/WR/LG/LT/C/RT on blue and CB/DE/OLB on red — side-of-ball colouring via `positionSideColor(player.position)` (CapComplianceView.swift:376). 066 renders the identical "MLB" badge for the identical player on BLUE, because signings hardcode `.background(Color.accentBlue, …)` (FACompleteView.swift:415) and losses hardcode `.background(Color.danger.opacity(0.6), …)` (line 485) — which is why "K", "DE", "SS" and "WR" in Players Lost are all red regardless of side of ball. The badge means offense/defense on one screen and signed/lost on the next.
  - code: `dynasty/dynasty/UI/FreeAgency/FACompleteView.swift:415`
  - fix: Pick one meaning for the position chip across the app (side of ball, which the cap and roster screens already use) and express signed/lost with a leading glyph or row tint instead of repainting the position badge.

- [ ] **Q-M156 · The "D" is unexplained — the grade's components are computed and then thrown away for a canned sentence**
  - evidence: The Free Agency Grade card contains exactly two elements: a large orange "D" and "Disappointing FA. Several needs unaddressed and some questionable spending." — a fixed string from the 45..<55 tier (FACompleteView.swift:940-955); the right half of the card is empty. Underneath, `calculateFAGrade` computed the score from four separable terms — needs addressed (+8/+4 per signing), value (`.bigOverpay` = −6, which this signing triggered), roster OVR delta ×3 (screen shows 80 → 79, i.e. −3), starter gaps ×4 (0 → 1, i.e. −4) — and discards every one of them.
  - code: `dynasty/dynasty/UI/FreeAgency/FACompleteView.swift:891`
  - fix: Put the arithmetic in the empty half of the card: labelled rows with signed contributions (Needs +8, Value −6, Roster OVR −3, Starter gaps −4, Unspent cap −n) summing to the score. It costs no new modelling — the terms already exist as locals at lines 891-932.


### Pro days — reserve sheet

- [ ] **Q-M157 · The "best match" tip picks the FIRST specialist in array order, not the best one — with two FS Specialists (59 and 61) it will name the worse**
  - evidence: The sheet's tip reads "Faron Maddocks (highest accuracy: 79)", which is the fallback branch. The specialist branch above it runs `scoutsWithSlots.first(where: { $0.positionSpecialization == position })`. The department on 073 holds two FS Specialists — "Sincere Hubbell ACC 59" and "Callum Derringer ACC 61" — listed in that order, so at any school whose most common declared position is FS the app recommends the 59, its worst scout, over the 61.
  - code: `dynasty/dynasty/UI/Scouting/ProDayTourView.swift:1064`
  - fix: `scoutsWithSlots.filter { $0.positionSpecialization == position }.max(by: { $0.accuracy < $1.accuracy })`, and fall through to the highest-accuracy scout when the specialist's accuracy deficit exceeds the +3 specialization bonus.

- [ ] **Q-M158 · Scouts are ordered by nothing the decision uses — role order in the picker, insertion order in the department list**
  - evidence: Picker on 067, top to bottom: Accuracy 79, 59, 74, 61, 76 — the two "Recommended" rows are 1st and 5th with three non-recommended rows between them, and the 5th is the one clipped by the button bar. Department list on 073/074: ACC 74, 71, 75, 75, 79, 76, 59, 61. Finding who still has a free slot on the 100th visit means reading all eight "n/3 slots" values.
  - code: `dynasty/dynasty/UI/Scouting/ProDayTourView.swift:1182`
  - fix: Picker: sort recommended first, then by accuracy descending, and push full scouts to the bottom (the isFull styling already exists). Department list: sort by slots remaining, then accuracy, so the top of the list is always who you can still spend.


### Pro days

- [ ] **Q-M159 · Generated names collide inside an eight-man department: two Farons, two Ezekiels, two Sinceres**
  - evidence: 073 department list: "Faron Laurelwood", "Ezekiel Broadwater", "Sincere Hedgepeth", "Jarreth Colgrove", "Faron Maddocks", "Ezekiel Waterhouse", "Sincere Hubbell", "Callum Derringer" — 6 of 8 share a first name with a colleague. On 067 the pick-one list shows "Faron Maddocks" and "Faron Laurelwood" two rows apart. The surname pool leaks across entity types too: scout "Jarreth Colgrove" vs Minnesota prospect "Jeremiah Colgrove" on 074.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:88`
  - fix: RandomNameGenerator draws `randomElement()` from 55x55 independently with no uniqueness check. Add a `randomName(excluding:)` that rejects a first name already used inside the same group (department, coaching staff, one team's roster); 55 given names against an 8-man draw collides ~40% of the time by birthday.

- [ ] **Q-M160 · "ACC" is never expanded on the screen that repeats it eight times, and its colour ladder is an OVR ladder in disguise**
  - evidence: 073 prints "ACC 74", "ACC 71", "ACC 75", "ACC 75", "ACC 79", "ACC 76", "ACC 59" (red), "ACC 61" (gold) with no legend; the sheet on 067 spells the same stat "Accuracy 79". The colours come from the 0-99 player-OVR tiers (<60 poor/red, 60-70 average/gold, 70-80 solid/blue), so the department's best scout (79) paints the same blue as its 71, nothing in an 8-man staff can ever reach green, and a 2-point gap (59 vs 61) flips red to gold.
  - code: `dynasty/dynasty/UI/Common/Theme.swift:152`
  - fix: Spell it "Accuracy" in both places (space is not the constraint — the row ends at the left third), and give scout accuracy its own tier edges calibrated to the hiring pool rather than reusing the player OVR ladder; or drop the colour and print the derived error band, which is what the number means.

- [ ] **Q-M161 · The same 0/25 is printed four times in the top third of the screen**
  - evidence: 073, top to bottom in ~700px: slat 4 "0/25 focus slots · spends 1 scouting week"; band "PRO DAYS / 0/25 focus slots · 16% scouted · Pro Days & Workouts"; gauge "Focus slots / 0/25 reserved · 8 scouts"; section header "25 slots left". (074: 1/25, 1/25, 1/25 reserved, 24 slots left.) The band line also prints "Pro Days" twice — as its own title and as the phase label.
  - code: `dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1091`
  - fix: Keep the counter on the slat (it is the band's job and it is visible from every stage) and let the gauge say the thing nothing else says: capacity shape — "25 slots across 8 scouts · chief carries 4". Drop "N slots left" from the section header or drop the gauge.

- [ ] **Q-M162 · Two thirds of a portrait iPad is empty: every row in the department and board lists ends at the left third**
  - evidence: On 073 the longest content in the 8 scout rows is "Ezekiel Waterhouse | DT Specialist" ending at x≈450 of a 1500px-wide render; the rows run to x≈1440. The gauge card carries a 60x6pt meter at the far right and ~1100px of nothing between it and the label. The school rows are the same: "Michigan State / 8 NEED 11 declared / Your best read here: Osman Vandenberg" occupies the left 400px, with only a 12pt "Reserve" at the right edge.
  - code: `dynasty/dynasty/UI/Scouting/ProDayTourView.swift:325`
  - fix: Portrait iPad wants columns: put the department in a 2-up LazyVGrid, and give each scout row the facts the choice needs in the empty space — region covered, schools already booked, error band at current accuracy. The school rows can carry their position breakdown ("3 EDGE · 2 CB · 1 QB") inline instead of hiding it behind an expand.

- [ ] **Q-M163 · Stage 3 FILM STUDY is still workable with unspent slots and is the only slat drawing no information at all**
  - evidence: On all three screens slat 3 reads "3 FILM STUDY" — no tick (so its report threshold was never met), no counter, no caption — sitting between "✓ COMBINE REVIEW", "✓ INTERVIEWS / 53/60 interviews" and "4 PRO DAY FOCUS / 0/25 focus slots". It is unlocked and still actionable (canAct = unlocked, and its order is below reach), so the one stage with capacity the player can still spend is the one telling him nothing.
  - code: `dynasty/dynasty/UI/Scouting/DraftPrepProcessBar.swift:186`
  - fix: DraftPrepStageCell sets `subcaption = nil` for both .done and .open. Give .open the stage counter ("0/25 reports · still open") so a walked-past-but-workable stage advertises what is left in it; that is the only state where the number changes a decision.

- [ ] **Q-M164 · Regional coverage is modelled and drives in-season reports, but the pro-day circuit — a literal travel decision — neither shows nor uses it, leaving accuracy strictly dominant**
  - evidence: The department is 8 scouts, each with a unique role including five regionals, yet every chip on 067/073/074 is a position label ("Chief Scout", "FS Specialist", "DT Specialist", "LG Specialist", "K Specialist", "RT Specialist"). ScoutingEngine.colleges(forRegion:) maps Michigan State and Minnesota to regionalScout4 (North), USC to regionalScout2 (West), TCU to regionalScout5 (Central), and generateWeeklyReports uses it all season — attendProDay/generateScoutReport do not. With specialization worth −3 error and the department's accuracy spread running 59→79 (±6→±3 on every man), "send the highest ACC scout with a free slot" is dominant and the picker is ceremony.
  - code: `dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift:2589`
  - fix: Give the region a payoff at the pro day (a familiarity bonus for the scout whose region owns the school, decayed if he has not worked it), show it in the picker ("Regional (North) — covered Michigan State all season"), and cap the chief's reach so the optimal circuit is a routing problem rather than a sort. Reference: FM's scout-region assignment screen, where knowledge is territorial and visible.

- [ ] **Q-M165 · "Where your board is" ranks Minnesota above TCU although every number printed on the two rows says the opposite**
  - evidence: 074 lists, in order: "USC — 4 NEED, 11 declared", "Minnesota — 2 NEED, 11 declared", "TCU — 4 NEED, 9 declared". The sort key is relevance = targeted*10 + top50*5 + need*3 + declared → Minnesota 17, TCU 21 on the visible terms alone. Only the top50 term (board men ranked ≤50, worth 5 each) can produce this order, and no chip on any row prints it — the row shows ELITE / TGT / NEED / declared and nothing else.
  - code: `dynasty/dynasty/Engine/Scouting/ScoutingEngine.swift:1686`
  - fix: Add the missing chip ("3 TOP-50") so the ordering is legible, or print the relevance score itself. A gold section titled "Where your board is" whose deciding term is the only board term not shown is the one place this cannot be left implicit.

- [ ] **Q-M166 · The school you just reserved disappears from the list you reserved it from, and another school silently slides into its place**
  - evidence: 073 "Where your board is": Michigan State, USC, Minnesota. 074, after reserving Michigan State: USC, Minnesota, TCU — the list is the same length, so nothing signals that a row left rather than the list re-sorting. The only confirmation on screen is an 11pt grey "Michigan State" under "Faron Maddocks · ACC 79 · 1/4 slots". The row that actually wears the gold "RESERVED" chip and the release control lives in the Schools section, ~25 rows below the fold.
  - code: `dynasty/dynasty/UI/Scouting/ProDayTourView.swift:178`
  - fix: The recommended filter is `!$0.isFocused`. Keep a reserved school in place with its RESERVED chip and the release X instead of dropping it, or add a "Booked (1)" summary strip directly under the gauge listing school → scout, which is also where the plan should be reviewable before the one-shot send.


### Career hub (draft)

- [ ] **Q-M167 · Scouting tile's three numbers don't add up: "350 total  OFF 196  DEF 148" leaves 6 players in no bucket**
  - evidence: SCOUTING card: "#1 Kenji Hopewell / QB — Oklahoma / 350 total   OFF 196   DEF 148". 196 + 148 = 344, not 350. Identical on 500_draft_002.png (same screen, 15.03 vs 15.04).
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2152-2163`
  - fix: `offenseCount`/`defenseCount` filter on `position.side == .offense` / `.defense`; specialists (K/P/LS) belong to neither, so they vanish from a row that reads as a partition. Either add "ST 6" as a third chip or label the two as a subset ("of which OFF 196 / DEF 148"). Three numbers side by side where two are meant to sum to the third and don't is the kind of thing a reviewer screenshots.

- [ ] **Q-M168 · Task descriptions truncate at two lines despite lineLimit(4), losing the end of both sentences in a rail with ~500px of empty space below**
  - evidence: THE DRAFT rows: "Required to advance · It's time to select the future of…" and "Optional · Check your depth chart for positions that need…". Full strings in TaskGenerator are "It's time to select the future of your franchise." and "Check your depth chart for positions that need reinforcements." Both are cut mid-clause with an ellipsis while the rail below "+ 4 more phases" is empty from roughly y=1470 to y=2000. Same on 500_draft_002.png.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:441-455, :491-504; dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:1145, :1154`
  - fix: `detailLine` is drawn with `.lineLimit(4)` and `.fixedSize(horizontal: false, vertical: true)`, and the code comment at that site documents exactly this defect as already fixed ("at two lines a 300 pt rail cut exactly that half off") — it has regressed. The trailing `Spacer(minLength: 2)` + secondary chip ("Big Board" / "Roster") in the same HStack is squeezing the text's proposed width; give the text its own row above the chip, or drop the chip to a second line.

- [ ] **Q-M169 · The offseason rail's only button-shaped control is the disabled "Advance to OTAs"; the actual required action is styled as a plain list row**
  - evidence: Rail order top to bottom: "⚑ Enter the Draft  [NEXT] [Required] ›" (plain text row with a chevron), "○ Review team needs ›", then in red "⚠ Required: Enter the Draft", then a full-width rounded button "» Advance to OTAs" in grey-on-dark. The eye lands on the button, which is dead (`.disabled(!canAdvance)`), and the live action is the smallest-weight element on the panel.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:693 (.disabled), :723-731 (advanceFill/Foreground), :377-400 (task row styling)`
  - fix: Give the required next step the gold primary treatment ("Enter the Draft →") and demote the blocked advance to a caption line, or hide it until it unblocks. The current arrangement teaches the player to reach for the one thing that cannot be tapped. (The gating itself is correct — advance is properly disabled — this is purely hierarchy.)

- [ ] **Q-M170 · Large dead regions on a portrait iPad: bottom quarter of the left rail and the right column beside TEAM NEEDS**
  - evidence: Left rail: content ends at "+ 4 more phases" (~y1470 of 2000) and the remaining ~26% of the rail is empty background. Right column: after the MOCK DRAFT card ends (~y1130) the column is empty down to the MESSAGES card (~y1300) while the left column runs DRAFT and TEAM NEEDS through that band — a ~500×170px hole. Same on 500_draft_002.png.
  - fix: The rail already truncates two task sentences (see the lineLimit finding) while holding a quarter-page of nothing; expand "+ 4 more phases" inline or let task detail lines breathe. For the tile grid, let the two columns flow independently (masonry) rather than row-locking, so TEAM NEEDS/DRAFT don't leave a notch.

- [ ] **Q-M171 · Team Needs names RB DL TE but four groups show the identical starter grade "S: B−" — the pick is unexplainable from the tile above it**
  - evidence: TEAM NEEDS: "RB DL TE / Thinnest groups on your roster". POSITION GRADES, immediately above: "RB S: B− / D: F [NEED]", "TE S: B− / D: C+", "DL S: B− / D: D", "S S: B− / D: B−". Four groups read S: B−; three are named as needs and Safety is not, with nothing on screen to separate them. TE's depth grade (C+) is also better than QB's, WR's and OL's (all D: C), none of which are listed.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1281-1287 (weakestPositionGroups), :2378-2412 (positionStrengthsTile)`
  - fix: `weakestPositionGroups` takes the bottom three by numeric `starterOVR`, but the tile that is supposed to corroborate it only prints a letter band, so the ranking is invisible and looks arbitrary. Either show the numeric starter OVR (or a rank) on the Position Grades rows, or have Team Needs state its own reason per group ("RB — starters 74, depth 61"). Also note needs ignore depth entirely, which is why RB's D: F and DL's D: D read as coincidence rather than cause.


### Draft war room

- [ ] **Q-M172 · The per-row "call about moving up" button is a 30×26pt target, repeated on all 25 rows**
  - evidence: Every board row ends in a gold phone glyph (the legend promises "the phone calls about moving up"). In code it is `Image(systemName: "phone.arrow.up.right.fill").font(.system(size: 11, weight: .bold)).frame(width: 30, height: 26)` — 30×26pt, well under the 44pt HIG minimum, and the row pitch itself measures ~30pt on the shot (rows at 43.5px spacing in a 1500px-wide render of a 2064px 2x image). Twenty-five of them stacked, under a running clock, opening a trade sheet on a mis-tap.
  - code: `dynasty/dynasty/UI/Draft/Components/LiveBigBoardPanel.swift:1051`
  - fix: Give the button a 44×44pt `contentShape` (the visual glyph can stay 30×26) or move the call verb into the prospect card the row already opens on tap.

- [ ] **Q-M173 · 332×222pt of empty panel in the right rail on the draft's opening screen**
  - evidence: On 076 the right rail ends at "#6  LV  IN 5  Rd 1" and the panel below it is blank down to its foot. Measured on the source PNG: from y≈2110 to y≈2555 across x 1345-2010 the region has a per-20px-band standard deviation of 0.6-1.0 (flat fill) — 445×665 source px = 222×332pt of nothing, roughly a fifth of the portrait screen, while the left board is dense with 25 rows. It only fills once the LIVE FEED accumulates cards (077/078).
  - fix: Seed the pre-first-pick state with something the player needs: the full UPCOMING order to your #19, your 7 owned slots, or the war-room targets list. A first impression of the draft room should not be half-empty.

- [ ] **Q-M174 · LIVE FEED shows the identical "Round 1 is under way" beat twice**
  - evidence: 077 and 078 both show two consecutive feed cards reading "Round 1 is under way / 288 names still on the board." each stamped "#1". 076 (before the user hit Skip to my pick) shows only one. `announceCurrentRoundIfNeeded()` fires the beat whenever `prevRound != pick.round`, and at `currentPickIndex == 0` `prevRound` is `nil`, so the condition is true on every call — it is called from `start()` (line 496) and again at the top of the skip loop (line 1745) before the first card is burned. `appendStoryBeat` does no de-duplication (line 2041-2044).
  - code: `dynasty/dynasty/UI/Draft/DraftDayCoordinator.swift:1787`
  - fix: Track the last announced round in a stored property and guard on it, instead of deriving from `picks[currentPickIndex - 1]` where index 0 has no predecessor. Or de-dupe in `appendStoryBeat` on (kind, pickNumber).

- [ ] **Q-M175 · Media reaction toasts run 10-15 picks behind the board and never say which pick they are about**
  - evidence: 077 (clock 0:47, header "On the clock: Miami Reefsharks · ROUND 1 · PICK 17 OF 32") shows "MEDIA — Eyebrows raised across the war room — Kenji Shelburne?" — Shelburne went to CLE at #2 (row #5 stamped "CLE #2"). 078, 13 seconds later and still on pick #17, shows "NE gets a high-floor OLB in Jonas Brockway" — Brockway went at #7 (row #2 stamped "NE #7"). Neither toast carries a pick number. `pendingReactions` is an unbounded FIFO appended once per AI pick (DraftDayCoordinator.swift:1486-1489) and drained one beat at a time (`consumeOldestReaction`, line 1682); Skip-to-my-pick burns 16 cards faster than the dwell can drain them. `reactedToPick()` deliberately returns nil for AI picks, so the subject line is dropped (DraftBroadcastRail.swift:~425).
  - code: `dynasty/dynasty/UI/Draft/DraftDayCoordinator.swift:1486`
  - fix: Cap/flush `pendingReactions` when the fast-forward runs (keep only the last 1-2), and stamp every reaction beat with its pick number and team the way the LIVE FEED cards already are ("#16", "#13"). A reaction to pick #2 arriving at pick #17 reads as a bug even when it is a queue.

- [ ] **Q-M176 · Pick #19 carries two different point values on the same screen with nothing to distinguish them**
  - evidence: Bottom-left chip reads "WAR ROOM / R1 · #19 · 3620 pts". The trade bar 900px to its right reads "Decline / Keep #19 (R1) · 875 pts" against "Accept trade / Get 2028 R1 + 2028 R2 + 2029 R3 · 921 pts". Both strings name pick #19 and both end in "pts". They are different quantities: `WarRoomPanel.chipText` prints `totalPoints` — this year's remaining slots PLUS future picks — while the trade caption prints `offer.userGivesValue`, the chart value of #19 alone (875 is the correct chart number for pick 19). Nothing on screen says so, so the trade reads as giving away 3620 for 921.
  - code: `dynasty/dynasty/UI/Draft/Components/WarRoomPanel.swift:68`
  - fix: Label the war-room chip's number ("3620 pts of capital" / "7 cards · 3620 pts") or drop the pick number from it, so the only "#19 · N pts" on screen is the one the trade is actually about.

- [ ] **Q-M177 · Header says "DT 0", the panel beside it says "DT LEFT 24" — same position, same screen, neither names its denominator**
  - evidence: Header strip: "NEEDS · MY TOP 20   DE 0  QB 1  WR 0  OLB 0  DT 0". The reveal card 700px right: "DT LEFT 24 | BOARD 272 | YOU'RE UP 2", and the board itself still lists undrafted "#13 DT Boone Lovegrove" and "#21 OLB Tobias Lovegrove". Both numbers are correct by design — the pill counts men inside the user's own top 20 (`boardPressure`, DraftStickyHeader.swift:838), "DT LEFT" counts the whole class (DraftTickerPanel.swift:2794) — but the pill prints a bare "0" and the only explanation lives in the VoiceOver string ("none left in your top 20", spokenPill).
  - code: `dynasty/dynasty/UI/Draft/Components/DraftStickyHeader.swift:788`
  - fix: Print the pill as "DT 0/20" or add the same ⓘ tooltip PROD already has. A grid of zeroes next to "24 LEFT" trains the reader to distrust both numbers.

- [ ] **Q-M178 · The pick grade shows as a bare orange "D" — no qualifier, no inputs — while VoiceOver gets more than the screen does**
  - evidence: The reveal card header reads "PICK #16  LAR  SELECTS" with an orange "D" chip at the trailing edge and nothing else. `gradeChip(showsQualifier:)` drops `result.grade.qualifier` on narrow rows, but its accessibility label is unconditional: `"Grade \(result.grade.rawValue), \(result.grade.qualifier)"` — so a screen-reader user hears the gloss a sighted user cannot see, on a 13-inch iPad that has 332×222pt of unused rail on the same screen. The four inputs the grade is actually made of (valueDelta, needScore, publicOVR, schemeFit — DraftDayCoordinator.swift:1851) are never surfaced anywhere.
  - code: `dynasty/dynasty/UI/Draft/Components/DraftTickerPanel.swift:2954`
  - fix: Show the qualifier at this width, and make the chip tappable for the four-input breakdown. "Why is this a D" is the single question a hardcore player asks of a letter grade.


### Draft — trade offer

- [ ] **Q-M179 · The trade offer shows no deadline of its own; the only visible clock belongs to Miami**
  - evidence: The bottom bar carries "TRADE OFFER — BUD FERRARO · EVEN KEEL" with Decline / Accept trade and no timer. The only countdown on screen is the header's "⏱ 0:47" (077) / "⏱ 0:34" (078) sitting directly under "On the clock: Miami Reefsharks · YOUR PICK IN 2" — i.e. Miami's pick clock. A player reading the offer will assume 34 seconds is the answer window for the trade.
  - fix: Give the offer its own countdown or an explicit "expires when you're on the clock" line in the trade bar; the header clock is unambiguously another team's.

- [ ] **Q-M180 · The engine models "will he still be there at #19" and the draft room never shows it — including on the trade-down decision**
  - evidence: 078 asks the flagship decision: "TRADE OFFER — BUD FERRARO · EVEN KEEL / NYG want to jump to #19 — Bud Ferraro is targeting a RT before the board turns" with Decline (875 pts) vs Accept (921 pts). The only inputs offered are two point totals. `DraftAvailability.probability(for:atPick:)` — "Probability the prospect is still on the board at pickNumber", a full logistic read over the consensus window — exists and is used ONLY in Scouting (ScoutBoardReads.swift:173, MockDraftView.swift:857/1149/1245). Grepping `DraftAvailability.` across dynasty/UI/Draft returns nothing. So the number that actually decides sit-vs-move is computed by the game and withheld on the night it matters.
  - code: `dynasty/dynasty/UI/Draft/Components/DraftBoardIntel.swift:262`
  - fix: Put the survival read on the trade bar and on the board row: "RT Faron Nadeau — 38% to reach #19". Madden's trade block and OOTP's draft screen both lead with availability, not chart points; without it the choice is 875 vs 921 and the answer is always "take the bigger number".


### Draft — on the clock

- [ ] **Q-M181 · "Round 1 is under way" is posted to the live feed twice, as two adjacent identical rows**
  - evidence: 080 LIVE FEED, the two bottom rows: "🏳 Round 1 is under way   #1" followed immediately by "🏳 Round 1 is under way   #1". Identical headline, identical pick number, no distinguishing detail on either.
  - code: `dynasty/dynasty/UI/Draft/DraftDayCoordinator.swift:1745, :1783, :1787`
  - fix: `announceCurrentRoundIfNeeded()` decides whether to post purely from `picks[i-1].round != picks[i].round` — a pure function of `currentPickIndex` with no record that it already announced — and `autoAdvanceUntil` calls it at the top of every loop iteration (:1745) AND once more after the loop exits (:1783). Start the draft (announce at index 0) then tap "Skip to my pick" and the first loop iteration announces index 0 again. Guard it with a `lastAnnouncedRound` (or a `Set<Int>` of announced rounds) rather than re-deriving from the array.

- [ ] **Q-M182 · On the one screen where the player must draft someone, the only solid-gold button says "Shop this pick"**
  - evidence: 080 bottom bar: a filled gold "Shop this pick / Take calls from behind you" on the right, a dark ghost "Call about moving up / Price the slots ahead of you" beside it, and the instruction "YOU ARE ON THE CLOCK — #19 / 106s left. Hand in a card from the board, or shop the slot to a club behind you." There is no bar-level control for the action the sentence names first; handing in a card is a 44×26pt tinted chip 900pt up the screen, or a tap on a name. A football fan reading nothing else takes the gold button and trades the pick away.
  - code: `dynasty/dynasty/UI/Draft/Components/DraftControlBar.swift:300, :341, :361`
  - fix: `onClockBar` deliberately puts the gold on `requestTradeDown()` (documented at DraftControlBar.swift:300 as the fix for a round-1 shot where both actions were muted navy). The diagnosis was right, the cure overshot: the answer to "the screen got quieter at the loudest moment" is to make DRAFTING loud, not trading. Give the bar a gold primary that commits the currently highlighted board row (or opens the confirm sheet for the top recommendation), and demote "Shop this pick" to the ghost slot alongside "Call about moving up" — both are the same kind of verb.

- [ ] **Q-M183 · The commit control on the clock is a 44×26pt chip; off the clock the trade-up button is 30×26pt — both well under the 44pt minimum**
  - evidence: On 080 the ~14 gold "PICK" chips down the right of the board measure ~44×26pt (26pt tall = 19pt at the rendered scale in the shot). On 084 and draft_01 the same column is a phone glyph in a 30×26pt box. These are the two verbs the board exists for, and on 080 one of them has to be hit accurately while a 1:46 countdown runs.
  - code: `dynasty/dynasty/UI/Draft/Components/LiveBigBoardPanel.swift:1030, :1051`
  - fix: `actionBox` sets `.frame(width: 44, height: 26)` on the PICK label and `.frame(width: 30, height: 26)` on the phone. `Col.action` is already 76pt wide, so the hit area can be grown to 76×44 with `.contentShape(Rectangle())` without moving a single pixel of the visible chip — the row is 30pt tall, so pair it with a row-height bump or let the chip's tappable rect overhang. The context menu ("Draft him — Pick #19") and the full card are the current fallbacks, but neither is discoverable from the row.

- [ ] **Q-M184 · On the clock, all three recommended names are below the visible board and none of them is tappable**
  - evidence: With 1:46 on the clock, the right rail says "Take a name off the board, or move the slot." and lists "BEST AVAILABLE · ON YOUR NEEDS: 28 DE W. Pankhurst C+/B · 30 WR O. Balfour C/B+ · 46 QB R. Maddocks B−/A". The big board beside it is scrolled to #1–#27 — every one of the three recommendations is below the fold, and the rows in the rail are static text with no PICK chip and no tap target. To act on the room's own advice the user must scroll a 300-row table while the clock runs.
  - code: `dynasty/dynasty/UI/Draft/Components/DraftTickerPanel.swift:3192 (ForEach → StageNameRow), :1124 (StageNameRow has no gesture)`
  - fix: `StageNameRow` is a plain `VStack` with only `.accessibilityElement(children: .combine)` — no Button, no `onTapGesture`. Make each of the three rows commit the pick directly (same `askToDraft` confirmation the board's PICK chip uses), or at minimum scroll-and-highlight the matching board row. This is the panel that exists to answer "what do I do in the next 106 seconds" and it currently answers in read-only.

- [ ] **Q-M185 · Trade wire rows truncate exactly the part that matters — the price**
  - evidence: 080 TRADE WIRE: the top row is expanded and readable, but the rows under it are one-line and cut mid-asset: "TRADE — LAR move up to #16, sending #20 (R1) + 2…" and "TRADE — CHI move up to #6, sending #8 (R1) + #40…". The club and the destination slot survive; what was paid — the only number that tells a GM what the market costs tonight — is the half that gets an ellipsis.
  - code: `dynasty/dynasty/UI/Draft/Components/DraftTickerPanel.swift:845`
  - fix: `tradeRow` applies `.lineLimit(isMuted ? 1 : nil)` to `line.headline`, and the headline is built as "TRADE — {buyer} move up to #{n}, sending {assets} to {seller}" with the assets at the end. Either give muted rows `lineLimit(2)`, or restructure the headline so the price leads ("LAR → #16 for #20 (R1) + 2029 R2"), or make the row expand on tap. A trade wire whose deals are all "+ 2…" is a list of rumours.


### Combine hub

- [ ] **Q-M186 · Hub's red NEED badge is an unconditional argmin and disagrees with the scouting screen's need model**
  - evidence: POSITION GRADES stamps a red "NEED" on "RB  S: B- / D: F" — but the badge is `positionGroupGrades.min(by: { $0.starterOVR < $1.starterOVR })`, with no threshold, so exactly one group is always flagged no matter how strong the roster is, and it is chosen on STARTER ovr while the eye reads it as a verdict on the "F" depth grade beside it. It also contradicts the other need model: on 050_interviews_stage.png every one of the 15 rows under "RECOMMENDED — Matches team needs with top-half talent" is OLB/TE/RT/DT/DE and not one is an RB. That list uses DraftEngine.teamNeedDeficits, which InterviewSelectionView.swift:65-73 documents was adopted precisely so "the two tabs stop contradicting each other".
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2377`
  - fix: Feed the hub tile the same DraftEngine.teamNeedDeficits the scouting surfaces use, and show no badge when nothing clears the bar — a well-built roster with no NEED is a real and useful answer. If the badge is meant to mean "weakest group", label it that and stop colouring it danger-red.

- [ ] **Q-M187 · Four unlabelled progress counters in one rail, two of which appear to contradict each other**
  - evidence: The offseason rail shows "YOUR OFFSEASON  4/6" in its header, "Phases complete (3)" one row below, "REVIEW ROSTER … OFFSEASON · STEP 2 OF 2" three rows below that, and "+ 8 more phases" at the bottom. The 4/6 is task progress inside Review Roster (TimelineTasksPanel.swift:135-141 → taskProgress), but sitting flush against the words "YOUR OFFSEASON" it reads as offseason phases — and "OFFSEASON · STEP 2 OF 2" says the offseason has two steps, not six.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:127`
  - fix: Label the header pill for what it counts ("4/6 tasks") or move it onto the REVIEW ROSTER row it describes, and leave the phase-level counting to the "step 2 of 2" caption. A bare X/Y next to a phase-group name will always be read as phases.

- [ ] **Q-M188 · 3-YEAR CAP tile is ~60% empty — two lines of text stretched to the height of the 6-row CONTRACTS tile beside it**
  - evidence: The tile holds exactly "$265M → $320M" and "Projection across 3 seasons" but is stretched by the grid row to match CONTRACTS ("HIGH PRIORITY / 7 expiring contracts / MLB Abernathy 91 $17.4M / K Hopewell 77 $2.4M / DE Larrabee 74 $8.2M / View all in Salary Cap →"), leaving roughly 180px of empty plate on a portrait iPad. The tile body is a 2-item VStack (CareerDashboardView.swift:1184-1198).
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1183`
  - fix: Spend the free height on what the tile is claiming to project — a three-bar sparkline of 2026/2027/2028 cap vs committed money, or the per-year committed total — so it answers "can I afford Abernathy in year 3" instead of restating one growth-rate multiplication.

- [ ] **Q-M189 · "YOUR OFFSEASON 0/6" sits directly above "Phases complete (4)" — two unlabelled counters in different units**
  - evidence: The rail header reads "YOUR OFFSEASON" with "0/6" flush right; the very next row reads "Phases complete (4)". Read together they say the offseason is 0/6 done and 4 phases are complete. In code the 6 is `taskProgress(tasks)` — tasks inside the *current* phase (the six Combine rows below it) — and the 4 is `pastPhases.count`. Neither number carries its unit, and the rail's own list ends with "+ 7 more phases", so 6 matches no phase count on screen either.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:127`
  - fix: Give the header counter its unit — "0/6 tasks" — or move it down onto the THE COMBINE row it actually describes, where "PRE-DRAFT · STEP 1 OF 4" already lives.

- [ ] **Q-M190 · Team Needs says "Thinnest groups on your roster" but ranks by starter quality, contradicting the depth column beside it**
  - evidence: TEAM NEEDS shows "RB TE S / Thinnest groups on your roster". The POSITION GRADES tile on the same screen splits S (starters) from D (depth) and shows RB S: B- / D: F [NEED], DL S: B / D: C-, OL S: B+ / D: C, S S: B- / D: B-. By depth — what "thinnest" means — the three worst are RB (F), DL (C-) and OL (C); the tile instead names S, whose depth B- is among the best on the card. The code sorts `positionGroupGrades` by `starterOVR` and ignores the `depthOVR` field it already computes.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1284`
  - fix: Either change the sentence to "Weakest starters on your roster", or rank by `depthOVR` so the words and the numbers agree. Best: show both, since the draft answers one and free agency the other.


### Free agency — final push

- [ ] **Q-M191 · Surname collisions everywhere — 55 last names are shared by the whole league, drawn with no uniqueness check**
  - evidence: The 8-row buzz list contains "SS Kason Marsden 90 OVR" and "LG Wyatt Marsden 88 OVR", plus "LG Wyatt Balfour 90 OVR" (a second Wyatt, at the same position), and the alternatives list adds "Jace Balfour (BUF)". On 050_interviews_stage.png "DT Boone Lovegrove" and "OLB Tobias Lovegrove" sit in adjacent rows and "RT Nehemiah Abernathy" duplicates the club's own MLB "Callum Abernathy" from the hub; the interviewer is "OC Finnian Balfour". RandomNameGenerator holds 55 first names and 55 surnames drawn with `randomElement()` for ~1,700 players plus a 288-man draft class plus coaches — about 36 men per surname league-wide.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:65`
  - fix: Expand the surname pool by an order of magnitude and/or track used (first, last) pairs per league generation, rejecting a draw that duplicates a surname already on the same roster or in the same draft class. Two Marsdens in an 8-row list is the kind of detail that reads as placeholder data.

- [ ] **Q-M192 · Gold hierarchy inverted: eight rival free agents' salaries are the brightest numbers, the user's own market value is dim blue**
  - evidence: The buzz rows print "~$32.8M/yr", "~$5.5M/yr", "~$15.6M/yr", "~$16.9M/yr", "~$11.7M/yr", "~$15.8M/yr", "~$13.3M/yr", "~$13.3M/yr" in Color.warning gold (FinalPushView.swift:338-340) — the highest-contrast text on the page — while the number the screen actually asks you to act on, Callum Abernathy's "~$16.3M MKT", is Color.accentBlue (line 657-662). Gold also carries the two card titles, the "Money" chip, the Quick Offer tint and the footer CTA, so it marks six different things on one screen.
  - code: `dynasty/dynasty/UI/FreeAgency/FinalPushView.swift:338`
  - fix: Demote the buzz salaries to a secondary/tertiary text colour (they are reference, not action) and promote the per-player MKT figure and its delta against the current $17.4M/yr. Keep gold for the one commit action, as the DSSlatBand notes elsewhere in this codebase already require.

- [ ] **Q-M193 · "Top FA alternatives" hides the age the engine already computed — on a screen whose whole question is a 30-year-old**
  - evidence: Callum Abernathy's header shows "91 OVR  Age 30  $17.4M/yr", and the alternatives beneath show only "Wilkes Latimer (CIN) 80 OVR ~$7.6M", "Elias Goddard (CLE) 77 OVR ~$5.7M", "Jace Balfour (BUF) 74 OVR ~$4.6M". ContractEngine.FAPreviewPlayer already carries `age` (ContractEngine.swift:2188) and the row never prints it, so the user cannot tell a 24-year-old 77 from a 33-year-old 77 without leaving the screen.
  - code: `dynasty/dynasty/UI/FreeAgency/FinalPushView.swift:681`
  - fix: Add age (and ideally the OVR delta vs the man being decided) to each alternatives row — the data is already in the struct. "77 OVR · 25 · ~$5.7M" against "91 OVR · 30 · ~$16.3M" is the whole trade-off in one line, which is what OOTP's comparison rows do.

- [ ] **Q-M194 · Buzz prices are never checked against the cap space quoted two cards above**
  - evidence: The header card states "Cap Space $21.2M". The buzz list then quotes "~$32.8M/yr" for Tobias Quarterman (92 OVR) — more than the club's entire space — plus $16.9M, $15.8M, $15.6M and $13.3M×2, so no two of the eight can be signed together. Nothing on any row is greyed, marked, or annotated, and the rows carry no suitor abbreviations either: all eight read the identical "Market still forming", an 8-row column with zero information (TamperingRumorEngine.swift:126-129 only prints that string when suitorAbbrs is empty).
  - code: `dynasty/dynasty/Engine/FreeAgency/TamperingRumorEngine.swift:126`
  - fix: Mark each row against available cap (affordable / needs a restructure / out of reach) and show the suitors the engine already computes — the rows currently all fall into the empty-suitors branch, which suggests the `availableCap >= projected` + High/Critical-need filter is too strict at this point in the calendar. Either loosen it or say "no clubs with room at this price" rather than the same four words eight times.


### Week hub (regular season)

- [ ] **Q-M195 · PLAYOFFS phase is captioned "WEEKLY DURING REGULAR SEASON"**
  - evidence: On both 700_season_001 and 720_season_003 the rail reads "PLAYOFFS  Jan" and directly under it "WEEKLY DURING REGULAR SEASON", followed by "Prepare for this round vs your opponent / Review matchups / Check injury report". The playoffs are neither weekly nor during the regular season.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:931-940, Domain/Enums/SeasonPhase.swift:88-94`
  - fix: `groupCaption` switches on `phase.group`, and SeasonPhase maps `.regularSeason, .tradeDeadline, .playoffs` all to group `.regularSeason`, so the playoffs inherit the weekly caption. Switch on the PHASE, not the group: "Weekly during regular season" for `.regularSeason`/`.tradeDeadline`, "Each playoff round" (or "Single elimination · Jan") for `.playoffs`.

- [ ] **Q-M196 · Every step in the weekly checklist is stamped "Optional" and the 0/4 counter never has to move**
  - evidence: YOUR SEASON reads "0/4" and all four rows begin with "Optional ·": "Optional · Choose your offensive and defensive s…", "Optional · Balance general training vs opponent-speci…", "Optional · Make sure your best players are starting and back…", "Optional · Review player injuries and adjust your lineup if needed." The gold primary button below reads "Advance to Week 2" with "Your game is still unplayed — advancing sims it." — so the fastest path through a week is to touch nothing. Same on 720_season_003 ("0/4", "Advance to Week 3").
  - code: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:1370-1408`
  - fix: The tasks description itself says week prep "drives audible / read bonuses", so the engine does model the payoff — surface it. Replace the word "Optional" with the stake ("+3 audible reads if set", "Unset — no opponent prep this week"), and show last week's actual outcome of the choice on the hub after the sim so the decision visibly pays off. Also cut the two truncated descriptions ("opponent-speci…", "and back…") — they lose exactly the words that would explain the value.

- [ ] **Q-M197 · The current-week slat prints the opponent twice — "1 @ JAX" over "@ JAX"**
  - evidence: 700_season_001: the expanded, widest slat in the week band reads "1  @ JAX  NOW" on the title line and "@ JAX" again on the line below. 720_season_003: "2  VS GB  NOW" over "vs GB". The expanded slat is ~430 of the band's 1500 px and spends it repeating three characters, while the played slat beside it uses its second line for real information ("@ JAX" / "W 28-18").
  - code: `dynasty/dynasty/UI/Career/SeasonWeekBand.swift:141-147`
  - fix: `SeasonWeekBand.slats` sets `title = tag` and then `subcaption = result ?? tag` for the `.current` state, so an unplayed current week duplicates itself. The file's own spec quote asks for "the current week expanded in place with opponent, window and stakes" — put the stakes on line 2 instead: opponent record + rank, home/away, or "Sunday 1:00 · JAX 0-0".

- [ ] **Q-M198 · A 100%-full bar sits directly above "Team Morale 64%" and belongs to neither row unambiguously**
  - evidence: The LOCKER ROOM tile stacks "Chemistry  Elite 100/100", then a full-width green bar, then "Team Morale  64%" — with equal 6pt gaps above and below the bar, and 64% rendered in gold while the bar is solid green. Morale has no bar of its own; chemistry has no number attached to its bar.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2266-2303`
  - fix: The code comment already records that this bar "belongs to the CHEMISTRY row above it — it used to plot morale under a 'Chemistry' label". Either move the bar tight under the Chemistry row (2pt gap, 12pt gap below) or, better, give each row its own inline mini-bar so the 100 and the 64 each show their own fill.

- [ ] **Q-M199 · Dead space on a portrait iPad: an empty grid cell, a stretched WEEK PREP tile, and 390pt of empty rail**
  - evidence: On 700_season_001 and 720_season_003: (a) the cell to the right of the OPPONENT SCOUT tile is completely empty — roughly 500x120 px of bare background at x 978-1482, y 1228-1348; (b) the WEEK PREP tile's content ends at "General vs opponent focus" (y≈935) but the card runs to y≈1063, ~78pt of empty card, because the LazyVGrid row is height-matched to the taller OWNER tile beside it; (c) the left rail's content ends at "Check injury report" (y≈1436) and the column is empty to y=2000 — about 390pt of dead column.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:894-919, 969-976`
  - fix: The 13-tile 2-column `LazyVGrid` (tileColumns, CareerDashboardView.swift:894) always leaves a hole on an odd count — let the last tile span both columns, or give the sparse tiles (Week Prep, Injuries, Depth Chart) real content so rows balance. For the rail, either let the phase list stretch (more upcoming phases) or move the standings/next-opponent snapshot into the empty bottom, which is also the easiest thumb reach in portrait.

- [ ] **Q-M200 · The red "NEED" chip is relative-only: it flags S (B / B-) while RB and OL (B+ / C) go unflagged**
  - evidence: POSITION GRADES on 700_season_001 and 720_season_003 shows "S  S: B / D: B-" with a red NEED chip, while "RB S: B+ / D: C", "OL S: B+ / D: C" and "QB S: A / D: C+" — all with WORSE depth grades — carry no chip. The legend under the grid explains only "S = starters · D = depth · tap a grade for details"; NEED is never defined.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2393, 2437-2452`
  - fix: `weakestGroup` is `positionGroupGrades.min(by: starterOVR)`, so exactly one group is always stamped NEED regardless of absolute quality — a roster of straight A's would still show it. Gate the chip on an absolute threshold (starter OVR below a positional par, or depth grade C or worse), add NEED to the legend, and make the chip's popover say why ("lowest starter OVR on the roster: 74 vs league median 79").

- [ ] **Q-M201 · WEEK PREP tile shows no state at all — two static strings where the prep split should be**
  - evidence: The tile reads "WEEK PREP" / "Week 1 prep" / "General vs opponent focus" on 700_season_001 and "Week 2 prep" / "General vs opponent focus" on 720_season_003 — the second line is a literal label, not a value, and it is identical in both weeks despite the task list claiming prep is a per-opponent decision.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1680-1693`
  - fix: The tile body is two hardcoded `Text`s. Print the live split and its state — "60 general / 40 vs GB · set" or "Not set — defaults to 50/50" — plus the resulting bonus, so the 100th visit needs no tap. Same treatment for the DEPTH CHART tile ("View / Starters & backups") which is likewise stateless.


### Advance confirm sheet

- [ ] **Q-M202 · Week 1 task rows say "your opponent" while three other elements on the same screen name JAX**
  - evidence: 700_season_002: the band reads "1 @ JAX NOW", the Opponent Scout tile reads "Vs JAX / Strengths & weaknesses", and the popover reads "Skip your Week 1 game vs JAX?" — yet the two top task rows read "Set game plan for your opponent" and "Tune week prep vs your opponent". On 740_season_044 and 740_season_052 the same rows correctly read "Set game plan for Cincinnati Riverkings" and "Set game plan for Pittsburgh Steelworks", so this is a Week-1 fallback, not the intended copy.
  - code: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:1374-1377 (`opponentName ?? "your opponent"`); dynasty/dynasty/UI/Career/CareerShellView.swift:3084-3089`
  - fix: `opponentName` is `nil` when the Week 1 list is generated because `currentWeekGame` has not been resolved yet, and the list is only rebuilt on a phase/week change. Regenerate the tasks when `currentWeekGame` first becomes non-nil (add it to the regeneration key alongside `lastGeneratedWeek`), or resolve the fixture before the first `generateTasks` call.

- [ ] **Q-M203 · "MVP" in Key Players is not an MVP — it is just the highest OVR on the roster**
  - evidence: 700_season_002 is Week 1, before a single snap of 2027 has been played, and Key Players already reads "MVP  Wade Braithwaite  93". The same row is unchanged on 740_season_044 (Week 17) and 740_season_052 (Week 18) after a full season of results. The other two rows in the tile are positions ("QB1", "MLB"), so the column mixes a depth-chart slot with what reads as a season award.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2349-2355`
  - fix: The row is `keyPlayerRow(label: "MVP", player: bestPlayer)` where `bestPlayer` is simply the top overall. Relabel it "TOP" or "BEST" (or the man's actual position), and reserve "MVP" for a real award computed from season production — which is also the number a hardcore player expects to see move between Week 1 and Week 18.


### Week hub (regular season)

- [ ] **Q-M204 · The rail prints the same four task titles twice, with two different opponents, and "Check injury report" three times**
  - evidence: On 720_season_003 the rail shows under REGULAR SEASON: "Set game plan for Green Bay Timberjacks", "Tune week prep vs Green Bay Timberjacks", "Review depth chart", "Check injury report"; then under TRADE DEADLINE (Oct): "Set game plan for your opponent", "Tune week prep vs your opponent", "Review depth chart", "Check injury report", "Evaluate trade targets", "Review roster and needs"; then under PLAYOFFS (Jan): "Prepare for this round vs your opponent", "Review matchups", "Check injury report". Same duplication on 700_season_001.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:762-790, Engine/Simulation/TaskGenerator.swift:476-489`
  - fix: `TaskGenerator` deliberately makes the deadline week "an OVERLAY on the weekly list" (TaskGenerator.swift:476-489), which is right for the live phase but wrong for a preview. In `TimelineTasksPanel.upcomingPhaseTasks` filter the preview down to the tasks the phase ADDS (here: Evaluate trade targets / Review roster and needs) and drop rows whose titles already appear in the current phase's list.


### Weekly press conference

- [ ] **Q-M205 · 781px of empty navy — 28.4% of the portrait screen — between the last answer card and the bottom bar**
  - evidence: Measured on the shot: a contiguous band of undifferentiated background from y=1830 to y=2611 of 2752 (28.4% of screen height), spanning the full width between the AGGRESSIVE card's bottom edge and the "YOUR ANSWER / Pick a line. Nothing is said until you say it." bar. Identical 781px band at the same coordinates on 740_season_054.png. On 740_season_058.png the same band is only 268px because the reveal panel fills it — proving the layout has nothing to put there before an answer is given.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:456-492`
  - fix: This is where the hardcore lens is starving. Fill it before the commit with the things currently unavailable: the tone history for this session (which archetypes are already spent, since repetitionScale/isVanilla silently decays repeats), the reporter's prior sessions, and a media-reputation trend rather than the single snapshot "-14". Right now the empty region reads as a screen that has finished loading and has nothing more to say.

- [ ] **Q-M206 · "Media ? —" on 12 of 12 option rows in this batch — a whole column of the decision matrix is permanently blank and never explained**
  - evidence: Every answer card on all three screens shows "Media ? —" while the other three chips carry real reads ("Owner ↑ likely approves", "Locker room ↓ risky", "Fans — muted"). Meanwhile the same screen prints MEDIA -14 (005) / -24 (054, 058) in the standing strip and the legend says "Media shapes the narrative", and the reveal on 058 books MEDIA +9. The cause is in code: mediaReadable = stance != .neutral || situation.demandsAStance, and all three reporters carry the NEUTRAL pill — but nothing on screen connects the grey "NEUTRAL" chip on the reporter row to the question marks 200px below.
  - code: `dynasty/dynasty/Engine/Media/PressEngine.swift:744-746`
  - fix: The fog is a good mechanic that currently reads as a rendering fault, partly because it double-encodes as a "?" glyph AND an em-dash. Render it as a single explicit state ("Media · can't read him") and hang the reason off the reporter's NEUTRAL pill ("A neutral writer gives nothing away — you won't see how the media takes this until you say it"). Tapping the pill should say which outlets are friendly/hostile.


### Press reaction

- [ ] **Q-M207 · A progress slat's second line means two different things: the reporter's stance, or the tone you answered in**
  - evidence: On 007 slat 2 (live) reads "PRESSBOX DAILY / Nora Whitlock · neutral" — reporter and stance — while slat 1 (done) reads "NATIONAL SPORTS NETWORK / Humble" — the tone the coach used. Same slot, same type, no label. On 060 slat 3 reads "LOCAL NEWS 9 / Diplomatic" while the reporter card for that exact outlet shows the stance pill "FRIENDLY", so the two vocabularies (Friendly/Neutral/Tough vs Confident/Humble/Aggressive/Diplomatic/Funny) collide in the same position on the same screen.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:544`
  - fix: Prefix the done slat's outcome — "Answered: Humble" — or move the tone into a small tone-coloured pill on the slat and keep the plain subcaption reserved for reporter · stance. The code already distinguishes them (subcaption at PressConferenceView.swift:544 vs outcome at line 548); only the rendering is ambiguous.

- [ ] **Q-M208 · 561px (20.4% of the portrait screen) is empty below the last answer, while the session's earlier answer is invisible**
  - evidence: On 007 the last response card ends at y=2024 and the action bar starts at y≈2585 of a 2752px screen — 561px, 20.4% of the display, containing nothing. Meanwhile the only trace of question 1 is the slat "✓ NATIONAL SPORTS NETWORK / Humble"; the line the coach actually said and what it cost are gone, and RUNNING IMPACT gives only the aggregate "OWNER +1 · MORALE +19 · FANS +5 · MEDIA +7".
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:455`
  - fix: Put the session transcript in that space: one collapsed row per answered question — outlet, the quote, and its resolved pills — under the running-impact card. The data is already in selectedIndices and resolvedEffects, it fills the dead 20%, and it is what a repeat player wants on the 100th presser: what have I already said in this room today.

- [ ] **Q-M209 · "Preview headline" is a 21.5pt tap target, less than half the 44pt minimum**
  - evidence: Measured on 007 card 1: the capsule's top border is at y=1311 and its bottom at y=1354 — 43 device px = 21.5pt at @2x. It is built from 11pt text with .padding(.vertical, DSSpacing.xxs) = 4pt top and bottom (PressConferenceView.swift:996) and .contentShape(Capsule()) at line 999 clips the hit area to exactly that capsule. It is the only per-option disclosure control on the screen.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:996`
  - fix: Add .frame(minHeight: 44) to the capsule, or put .contentShape(Rectangle()) over a 44pt-tall container, the way DSButtonChrome already does at DSActionBar.swift:207. Every other control on this screen is a full-width card, so this one chip is the sole HIG violation and it is the one a curious player reaches for most.

- [ ] **Q-M210 · On question 2 the CONFIDENT line dominates FUNNY on every readable axis; the only differentiator is fogged out**
  - evidence: 007 CONFIDENT: "Owner ↑ likely approves · Locker room ↑ will back you · Fans ↑ will eat it up · Media ? —". FUNNY: "Owner — no strong read · Locker room ↑ will back you · Fans ↑ will eat it up · Media ? —". Identical except the Owner chip, so CONFIDENT weakly dominates. The third option (DIPLOMATIC) shows only "no strong read / shrugs / muted / ?" plus the orange "SAYS NOTHING, BEAUTIFULLY" chip. Media is unreadable on all three because Pressbox Daily maps to .neutral (PressEngine.swift:114-121) and mediaReadable = stance != .neutral || situation.demandsAStance (PressEngine.swift:747) is therefore false — the one axis that could create a trade-off is hidden on every card, leaving a question with no visible cost to the best answer.
  - code: `dynasty/dynasty/Engine/Media/PressEngine.swift:747`
  - fix: When mediaReadable is false for every option on a question the question has no visible trade-off at all: either widen the readability gate (a beat writer's likely angle is something a head coach can read) or guarantee at least one non-media axis differs in direction across the response set. Also surface the promise consequence at pick time — promiseKind() (PressEngine.swift:939) turns a confident line into a season-long liability worth up to -15 legacy / -10 media / -8 owner and nothing on the card says so.


### Press session summary

- [ ] **Q-M211 · YOUR APPROACH counts only this session, while the engine penalises a tone repeated across sessions**
  - evidence: 720_season_011 shows "2 DIPLOMATIC · 1 HUMBLE"; 740_season_050 "1 DIPLOMATIC · 1 HUMBLE"; 740_season_061 "1 DIPLOMATIC · 1 HUMBLE · 1 CONFIDENT" — three pressers where diplomatic is the only tone present every time, and no screen says so. The engine keeps a career-scoped ledger for exactly this (PressEngine.commit writes career.pressToneHistory, PressEngine.swift:963-965) and punishes it: isVanilla fires at `repetitionCount(tone:recentTones:) >= 4` (PressEngine.swift:648-649) and hangs a label on the coach — for diplomatic, "Says nothing, beautifully" (line 658). The summary is where a player would learn how close he is to that, and summaryApproach (PressConferenceView.swift:1423-1430) counts only `result.selectedResponses`.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1423`
  - fix: Render each chip against the running ledger, not the session: "DIPLOMATIC 3 of your last 4 answers" with the 4-in-a-row threshold marked, so the player can see the vanilla penalty coming instead of only meeting it. There is half a screen of empty space directly below to put it in.

- [ ] **Q-M212 · Key quotes are shown without the question that produced them, though the result already carries it**
  - evidence: 720_season_011's second quote reads "We ride the hot hand. Ramiro Maddocks earned every one of those yards, but it stays a committee." with nothing saying what was asked; 740_season_050's "That's on all of us — scheme, calls, execution. We'll get it fixed in the protection meetings this week." is only decodable from the outlet line's "after 5-sack afternoon". PressConferenceResult.SelectedResponse stores `questionSummary` and buildResult populates it (PressConferenceEngine.swift:123 and 413), but summaryQuotes (PressConferenceView.swift:1456-1486) renders only responseText and mediaReaction — the field is written and read nowhere.
  - code: `dynasty/dynasty/Engine/Media/PressConferenceEngine.swift:413`
  - fix: Add the question above each quote as a tertiary caption (it is already in the model — one Text). Add each answer's own effect pills too: the third quote on 011 and 061, "I'll keep that between us and the locker room.", is authored at mediaPerception -5 (PressEngine.swift:1454-1462) and the player never sees which of his three answers cost him that.


### Week hub (week 18)

- [ ] **Q-M213 · Two power-ranking blurbs one row apart use the identical sentence — a deterministic template collision**
  - evidence: Rank 1: "KC Kansas City Stockyards 14-1 — The 14-game heater shows no sign of cooling off." Rank 4: "DEN Denver Summit 10-5 — The 5-game heater shows no sign of cooling off." Verbatim the same sentence, three rows apart, on the same card.
  - code: `dynasty/dynasty/Engine/Media/LeagueNarrativeEngine.swift:277-354`
  - fix: The variant index is `pool[(week + rank) % pool.count]` with 3-line pools, so any two teams in the same streak bucket whose ranks differ by a multiple of 3 ALWAYS print the same line, every week. Mix the team id into the index (`(week + rank + teamHash) % count`), or de-duplicate at assembly time by tracking sentences already used for this week's board.

- [ ] **Q-M214 · A Week 16 recap with no playoff picture — the one thing that matters at Week 16**
  - evidence: "Week 16 Recap · Around the league · Season 2027" shows results, then Power Rankings ("HOU Houston Astronauts 13-2"), and the footer offers only "Continue", "Full Standings", "League News". Nothing states HOU's seed, whether the division is clinched, or who they can still catch — with 2-3 games left that is the only decision-relevant fact on the screen.
  - code: `dynasty/dynasty/UI/Career/CareerShellView.swift:1747-1826`
  - fix: `RoundResultsView.Data` is assembled from state that already includes standings; add a seeding/clinch strip above Power Rankings from week ~12 on ("AFC 2 seed · clinched playoff berth · 1 game behind KC for the bye"), the way Madden's weekly wrap and OOTP's magic-number line do. Power rankings are flavour; seeding is the decision.

- [ ] **Q-M215 · 16 score rows with no records or context, and a ~530px empty gutter in every one**
  - evidence: Rows read "IND 9 @ HOU 30 [BLOWOUT]", "BUF 52 @ NYJ 27 [BLOWOUT]", "LAC 26 @ BAL 13 [UPSET]", "NO 20 @ DET 9", … 16 of them. Nothing states either team's record, so "DEN 23 @ TEN 20" is unreadable as a good or bad result — you have to reach the Power Rankings card below to learn DEN is 10-5. Content stops at x≈570 in a card 990px wide; the badge column sits at x≈1100-1210, leaving ~530px of empty row × 16 rows.
  - code: `dynasty/dynasty/UI/News/RoundResultsView.swift:147-196`
  - fix: `scoreRow` already receives `awayName`/`homeName` and the recap already holds `narrative.rankings` — put each team's record (and a rank chip for top-10 clubs) in the gutter, and mark division/conference rivals. That is the OOTP/FM standard for a league-wide results sheet.


### Advance confirm sheet

- [ ] **Q-M216 · Task titles wrap to two lines on every real club name — the exact failure the 300 pt rail was widened to prevent**
  - evidence: 740_season_044: "Set game plan for / Cincinnati Riverkings" and "Tune week prep vs / Cincinnati Riverkings" both wrap. 740_season_052: "Set game plan for / Pittsburgh Steelworks", "Tune week prep vs / Pittsburgh Steelworks". The rail's width comment says 300 pt was chosen over 280 because "the longest real task titles — 'Set game plan for your opponent' — wrapped to a second line, which made the list scan ragged" — but the generic placeholder is the only title that fits; every actual opponent name wraps.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:668-672 (`.frame(width: 300)` and its comment); titles from TaskGenerator.swift:1377, :1386`
  - fix: Size the rail against real data, not the placeholder. Either use the club's short name/abbreviation in the title ("Set game plan vs CIN") and keep the full name in the detail line, or widen the rail / reduce the title size so "Set game plan for Jacksonville Tidewater" fits on one line.


### Press reaction

- [ ] **Q-M217 · "Preview headline" stops working on every card the moment you commit, including the answer you said**
  - evidence: On 048 and 060 all three "Preview headline ⌄" capsules render greyed out — on the dimmed unpicked cards AND on the highlighted card that was actually said. The code intends the said card to stay interactive: isDisabled = selectedResponseIndex != nil && !isSaid is false for the committed card, and headlinePreviewSection only applies .disabled(isDisabled) (PressConferenceView.swift:1002). But the outer card Button carries .disabled(selectedResponseIndex != nil) at line 885, and SwiftUI propagates isEnabled down the whole subtree, so the nested toggle is disabled too.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:885`
  - fix: Replace the outer .disabled(...) with .allowsHitTesting(selectedResponseIndex == nil) on the card's tap surface, or move the headline-preview button out of the card Button's subtree — so the reveal-phase player can still open the headline on the line he said, and ideally on the lines he did not, since comparing the headline that ran against the one that would have run is the learning loop this screen is built around.


### Press session summary

- [ ] **Q-M218 · The bar titled "What it cost" omits the only cost on the screen — FANS -9**
  - evidence: 740_season_050's WHAT CHANGED card shows "FANS -9" in red — the single negative number anywhere on the screen — and "MORALE +15". The action bar directly below reads "2 answers · moved the owner +3 · +4 legacy · no promises on the ledger." A player who reads only the summary line believes the presser was pure upside. summaryCostLine (PressConferenceView.swift:1543-1560) builds only ownerPart, legacyPart and promisePart (the in-flight edit adds mediaPart); playerMorale and fanExcitement are never considered.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1543`
  - fix: Either name every axis the card above shows — "2 answers · owner unchanged (already 100%) · fans -9 · +4 legacy · no promises" — or, if fans/morale are being cut per the phantom-stat finding, cut them from the card too so the two summaries on one screen cannot disagree.


### Advance confirm sheet

- [ ] **Q-M219 · The current-week slat prints the opponent twice, in two different casings**
  - evidence: 740_season_052: the live tile reads "18  VS PIT  [NOW]" with "vs PIT" on the line directly beneath it. 700_season_002: "1  @ JAX  [NOW]" with "@ JAX" beneath. The subcaption slot, which on a played week carries the score ("W 36–13", "L 32–38"), degrades to a duplicate of the title while the game is unplayed.
  - code: `dynasty/dynasty/UI/Career/SeasonWeekBand.swift:143-145`
  - fix: In `SeasonWeekBand.slats`, the `.current` case is `subcaption = result ?? (isBye ? "No game this week" : tag)` — `tag` is already the title. Replace the unplayed fallback with something the title does not say: kickoff day/time, the opponent's record, or "Not played yet".

- [ ] **Q-M220 · "Optional · Important events need your attention before advancing." — the row contradicts itself in one sentence**
  - evidence: 740_season_044 and 740_season_052, last row of the REGULAR SEASON block: title "Handle pending events", detail "Optional · Important events need your attention before advancing." The prefix says skip it; the sentence says you cannot advance without it. A player reading in ten seconds cannot tell which is true.
  - code: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:1437-1445 with TimelineTasksPanel.swift:502-503`
  - fix: The task is created with `isRequired: false` and the panel prepends "Optional". Either make it required (and let Advance block on it), or reword the description to drop the false urgency — e.g. "Events are waiting in the inbox. Advancing resolves them with the default outcome."

- [ ] **Q-M221 · "YOUR SEASON 0/6" is a progress counter that can never need finishing — every row under it is labelled "Optional"**
  - evidence: 740_season_052 (Week 18 of 18, the last week of a season the club has played out) still reads "YOUR SEASON  0/6", and all six rows beneath it are prefixed "Optional ·". 740_season_044 reads "0/6" too; 700_season_002 reads "0/4". The player has advanced seventeen weeks with the counter pinned at zero and nothing has gone wrong, so the pill's only message is a standing, meaningless zero.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:121-142 (`taskProgress`); TaskGenerator.swift:1371 ("no required tasks")`
  - fix: `regularSeasonTasks` opens with "Regular season: no required tasks — advance always allowed", so the denominator is all-optional by design. Either drop the X/Y pill for phases with no required steps (show the count as "6 things you can do"), or split it into "0/0 required · 6 optional" so the zero is not read as being behind.

- [ ] **Q-M222 · A defeat is stamped with a red checkmark, and completed weeks lose their week number**
  - evidence: 740_season_052 week band: "✔ VS CIN / L 32–38" — the same checkmark glyph used on the four wins beside it ("✔ VS NYJ / W 36–13"), recoloured red. A tick means "done well"; tinting it red does not undo that. The glyph also replaces the week index, so the five finished tiles carry no week number at all — only the live tile shows "18".
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:683-686; tint from SeasonWeekBand.swift:91-96`
  - fix: `DSSlatBand` hard-codes `Image(systemName: "checkmark")` for every `.done` slat. Let the slat supply its own done-glyph (checkmark for a win, `xmark` for a loss, `minus` for a tie), and keep the week numeral on done slats — the band is a schedule, not a task list, so position is load-bearing.

- [ ] **Q-M223 · "tap a grade for details" promises 18 tap targets that are about 20 pt tall**
  - evidence: The Position Grades tile ends with "S = starters · D = depth · tap a grade for details". The tappable items are the bare letters — "A", "B+", "C", "B-" — laid out in two columns of rows spaced ~41 device px (≈20 pt) apart, with 2 pt of horizontal padding each. Eighteen targets, all well under the 44×44 pt HIG minimum, sitting 2 pt from the untappable "/" and "D:" labels.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2459-2470 (label) and :2411 (the caption that promises it)`
  - fix: `gradeButton`'s label is a `Text` with `.padding(.horizontal, 2)` and `.contentShape(Rectangle())` — no minimum size. Add `.frame(minWidth: 44, minHeight: 44)` on the content shape (visual size can stay small), or make the whole position row one tap target that opens an explainer for that group.

- [ ] **Q-M224 · Gold is the default colour of the whole hub, so the primary action has nothing to stand out against**
  - evidence: On 740_season_052 gold/amber carries: the HOU chip, "YOUR SEASON", "REGULAR SEASON" + the NOW badge, the three task chips (Depth Chart / Game Plan / Roster), the Advance button, the band's "18" + NOW badge, "$14.7M", ten card headers (LOCKER ROOM, POSITION GRADES, OWNER, DEPTH CHART, OPPONENT SCOUT, KEY PLAYERS, CONTRACTS, WEEK PREP, INJURIES, MESSAGES, DIVISION), "Team Morale 64%", "QB1/MLB/MVP", "42 expiring", "View all in Salary Cap →", "Vs PIT", the News/View All/Standings pills, the "All" tab and the division crown — plus all eight C/C+ grades, because `Color.warning` (#EAB308) is a near-neighbour of `accentGold` (#C9A94E) at 11–15 pt on navy. Forty-odd gold elements, and the one that should own the eye — "Advance to Week 19" — is a 10%-opacity outline among them.
  - code: `dynasty/dynasty/UI/Common/Theme.swift:25 (accentGold) and :49 (warning); grade mapping GradeColors.swift:43`
  - fix: Reserve `accentGold` for the single primary action and the NOW marker. Move card headers to `textSecondary` with the existing icon carrying the accent, and pull the C-grade tint away from gold (an orange or a desaturated amber) so "gold" never means "mediocre" on the same screen where it means "do this next".

- [ ] **Q-M225 · Large dead regions on a portrait iPad: an empty rail foot, an empty grid cell, and a half-empty Week Prep card**
  - evidence: 740_season_052: the left rail's content ends at "Check injury report" under PLAYOFFS and the panel background runs empty for roughly the bottom fifth of the column (on 700_season_002 it is closer to a quarter — the rail ends at y≈1445 of 2000). In the tile grid, OPPONENT SCOUT occupies only the left half of its row: the cell to its right (roughly 700×185 device px, beside "Vs PIT / Strengths & weaknesses") is bare background on all three screens. WEEK PREP is a full-height card holding two short lines — "Week 18 prep" and "General vs opponent focus" — with the lower half empty.
  - fix: Let the tile grid reflow so OPPONENT SCOUT spans the row when it is the last card, or promote the opponent's record/injuries into the empty cell. Fill the rail foot with something the player wants at the bottom of a week (last week's result, next week's fixture) or let the Advance button dock there. Week Prep should carry the actual slider split and the audible/read bonus it drives rather than one generic phrase.

- [ ] **Q-M226 · "Check injury report" is generated every week regardless of whether anyone is injured — the same screen says "0 out"**
  - evidence: All three screens carry the row "Check injury report / Optional · Review player injuries and adjust your lineup if needed." while the INJURIES card on the same screen reads "0 out / Status updates weekly" and is green. The neighbouring "Scout college prospects" row IS guarded (`hasScoutsAssigned && week >= 9`) with a comment saying an unguarded version "sent the user to it every week from opening day with a promise … that could not possibly exist yet" — the injury row has exactly that shape and no guard.
  - code: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:1402-1409 (unguarded) vs :1415-1424 (guarded neighbour)`
  - fix: Pass the injured count into `regularSeasonTasks` and append the row only when it is > 0 ("Check injury report — 2 out"), the way the scouting row is gated. It would also drop the rail from 6 rows to 5 on a healthy week, which is honest progress rather than permanent 0/6.

- [ ] **Q-M227 · Position Grades' depth column is ragged — the numbers meant for side-by-side comparison do not line up**
  - evidence: In the left column, "QB S: A / D: C+" and "WR S: A / D: C+" put "/ D:" ~35 device px left of "RB S: B+ / D: C", "TE S: B+ / D: C+" and "OL S: B+ / D: C", because a one-character starter grade shifts the whole rest of the row. Right column, same: "S  S: B / D: B-" sits left of "DL/LB/CB  S: B+ / D: …". Nine units you are supposed to scan for the weak spot, and the depth grades are not in a column.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2421-2440`
  - fix: `positionGradeRow` is an `HStack(spacing: 2)` with no fixed widths. Give each grade a `.frame(width: 26, alignment: .leading)` (or use a `Grid`/`LazyVGrid` with fixed columns) so S and D each occupy a true column; the "NEED" chip then also lands in a consistent place.


### Weekly press conference

- [ ] **Q-M228 · The post-win opener is one hardcoded triple: Week 2 and Week 18 produce byte-identical questions and answers**
  - evidence: 720_season_005.png (Week 2, Legacy 19, Media -14) and 740_season_054.png (Week 18, Legacy 81, Media -24) show the same question except the number — "Great win in Week 2. What worked out there?" vs "Great win in Week 18. What worked out there?" — and all three answers word for word: "The guys executed the game plan perfectly. That's what happens when you prepare." / "Credit goes to the players and coaches. They put in the work all week." / "We won but we left a lot on the table. We need to be better." generatePostWinQuestion has exactly one authored set with no pool. Question 2 on 740_season_058.png proves the system can do better: "Ramiro Maddocks ran for 126 yards — is he your workhorse now?" is built from real sim output.
  - code: `dynasty/dynasty/Engine/Media/PressConferenceEngine.swift:770-816`
  - fix: The opener is the slot the player sees every single week, so it is the worst one to hardcode. Feed it what 058's question already uses — margin, opponent, the standout stat line, the streak — and give it 4-6 variants per situation. Reference: OOTP's presser generator keys every question off a concrete box-score fact; Madden's franchise pressers are the failure case this currently matches. Note the engine already penalises repeating a TONE (repetitionScale / the "vanilla" label) while the literal words repeat verbatim for 18 weeks — the fiction and the mechanic are punishing different things.

- [ ] **Q-M229 · MEDIA -24 is presented as narrative state but nothing in the press conference reads it — the reporter and his stance are drawn at random from a name list**
  - evidence: The standing strip shows "-24 MEDIA" under a red newspaper icon with the legend "Media shapes the narrative". In the engine, the reporter comes from reporters.randomElement() and stance(forOutlet:) is a pure string match on the outlet name ("local press"/"city tribune"/"local news 9" → friendly, "continental sports" → hostile, everything else → neutral). Neither reads career.legacy.mediaReputation. A coach at -24 draws the same writers, the same stances and the same questions as one at +40; mediaReputation's only downstream consumer is the contract-negotiation discount at ContractNegotiationEngine.swift:847.
  - code: `dynasty/dynasty/Engine/Media/PressConferenceEngine.swift:236-238`
  - fix: Either make the stat pay off here — weight the reporter draw and shift a neutral writer toward hostile as mediaReputation falls, which also makes the fogged Media chip readable when you have burned the press — or stop claiming "Media shapes the narrative" on this screen and label what it actually does ("Media affects what free agents and agents will sign for"). Right now the most prominently negative number on the screen has no visible consequence on the screen that produced it.

- [ ] **Q-M230 · "WHAT IT ACTUALLY COST" heads a row of five green gains, and the footer calls the same all-upside result something that "cannot be taken back"**
  - evidence: The reveal panel reads "WHAT IT ACTUALLY COST" over: OWNER +10, MORALE +13, FANS +17, MEDIA +9, LEGACY +2 — every value positive and green, nothing negative anywhere. Below it the bar says "ON THE RECORD / That is what ran, and what it cost. It cannot be taken back." A reader taking "cost" literally will read five gains as five losses, or conclude the labels are broken.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1060`
  - fix: The heading is fixed text at PressConferenceView.swift:1060 while effectPillRow paints signs from the data. Make the heading match the data: "WHAT IT MOVED" always, or branch to "WHAT IT COST" only when any effect is negative. Same for the explainer copy — "That is what ran, and what it moved. It cannot be taken back."

- [ ] **Q-M231 · Only the current reporter's name and stance are shown; the two upcoming slats hide the one fact that determines whether the Media forecast works**
  - evidence: On 740_season_058.png the rail shows "✓ THE GRIDIRON WEEKLY / Humble", "✓ NATIONAL SPORTS NETWORK / Confident", "3 LOCAL NEWS 9" — the third slat carries no reporter and no stance. Same on 720_season_005.png: slat 1 reads "1 NATIONAL SPORTS NETWORK / Marcus Deane · neutral" while "2 PRESSBOX DAILY" and "3 LOCAL PRESS" are bare. This is load-bearing, not cosmetic: stance(forOutlet:) maps "local news 9" and "local press" to .friendly, which is exactly what would unlock the "Media ? —" chip on the next question — so the player is denied the information needed to plan which tone to spend where. The code's own comment says "On the podium every slat carries its reporter and stance", but the condition is previewOnly || state == .current.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:544-546`
  - fix: Drop the state gate so future slats also show "name · stance", which is what the comment at PressConferenceView.swift:541-543 already promises. A three-question session is a small budget of tones; seeing that a hostile writer is waiting at question 3 is the entire reason to hold something back at question 1.

- [ ] **Q-M232 · Forecast and outcome are never put side by side — the "Media ?" that resolved to +9 sits 700px from its own answer**
  - evidence: On the committed CONFIDENT card the pre-answer chips still read "Owner ↑ likely approves · Locker room ↑ will back you · Fans ↑ will eat it up · Media ? —". The actual result — "OWNER +10, MORALE +13, FANS +17, MEDIA +9, LEGACY +2" — is in a separate panel roughly 700px further down, past two dimmed cards. Nothing marks the top chips as predictions, and the single most instructive pairing in the whole design ("Media was unreadable; it turned out +9") is left for the player to scroll between and hold in his head.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1042-1075`
  - fix: After the commit, collapse the chosen card's hint row into a predicted→actual row on the same line: "Owner: likely approves → +10 · Fans: will eat it up → +17 · Media: couldn't read → +9". That is the learning loop the file header describes ("the player finds out what … actually costs by paying it once") and it costs no new state — both values are already computed from the same resolvedEffects call.


### Press reaction

- [ ] **Q-M233 · The legend explains three meters; the screen moves four, and two of them have no baseline anywhere**
  - evidence: 060's standing card explains exactly three things — "Owner affects job security · Media shapes the narrative · Legacy affects career rating" — and shows baselines for exactly three — "81 LEGACY · -24 MEDIA · 100% SATISFACTION". The row below reports four meters, "OWNER +6 · MORALE +28 · FANS +8 · MEDIA 0", and the ledger reports "MORALE +5 · FANS -4". Nothing says what Morale or Fans do, and neither has a base number, so "MORALE +28" is +28 of an unknown out of an unknown. Legacy is named in the legend but has no chip in the running strip at all.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:611`
  - fix: One list, four or five entries: add "Morale is your locker room" and "Fans drive the gate" to the line at PressConferenceView.swift:611, and give Morale and Fans a before-value in the standing strip so the deltas have a denominator the way Satisfaction already reads "100%". If Morale and Fans genuinely do nothing (see the blocking finding), delete them from all three places instead.


### Playoff hub

- [ ] **Q-M234 · Caption under the PLAYOFFS header reads "WEEKLY DURING REGULAR SEASON"**
  - evidence: All three screens: the rail shows "PLAYOFFS  NOW  Jan" and directly beneath it, in the caption slot, "WEEKLY DURING REGULAR SEASON". The band above says "2027 SEASON · POSTSEASON".
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:936`
  - fix: groupCaption (TimelineTasksPanel.swift:930-939) switches on `phase.group`, and SeasonPhase.swift:95 puts `.playoffs` in the `.regularSeason` group alongside `.regularSeason` and `.tradeDeadline`. Special-case `.playoffs` in groupCaption — "One game a week — lose and the season is over" says something true and useful in the same slot.

- [ ] **Q-M235 · Same unread count printed twice with different values: envelope badge "99" vs "MESSAGES 192"**
  - evidence: Top bar envelope carries a red badge reading "99"; the MESSAGES panel header on the same screen carries a red badge reading "192", and the list footer reads "187 more messages" (192 − 5). Both badges are the unread count. Identical on 063, 064, 065.
  - code: `dynasty/dynasty/UI/Common/TopNavigationBar.swift:200`
  - fix: TopNavigationBar.swift:200 renders `Text("\(min(unreadInboxCount, 99))")` with no overflow marker, so a clamped 192 reads as an exact 99. Print "99+" past the cap (and consider capping the panel badge the same way so the two agree at a glance).

- [ ] **Q-M236 · Playoff task description clipped mid-word: "…for this win-or-go-h…" on all three rounds**
  - evidence: Identical on 063, 064 and 065: the first step's detail line reads "Optional · Set your game plan for this win-or-go-h…" over two lines, next to the "Depth Chart" chip. The real string is "Set your game plan for this win-or-go-home matchup." — the one phrase that tells the player the season ends here is the phrase that gets cut.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:453`
  - fix: The detail Text is `.lineLimit(4)` (TimelineTasksPanel.swift:453) but shares its HStack with the secondary chip, so it is width-starved and truncates at two. Give the chip its own line under the sentence when the sentence needs more than two lines, or `Spacer(minLength:)` a real minimum width to the text and let it use its four lines.

- [ ] **Q-M237 · POSITION GRADES: the safety row renders "S  S: B / D: B−" — the group label collides with the legend's "S = starters"**
  - evidence: Right column of the tile, last row: "S   S: B / D: B−  NEED", under a legend that says "S = starters · D = depth · tap a grade for details". So on that one row "S" means safeties and "S:" means starters, one character apart. Same on all three screens.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2421`
  - fix: positionGradeRow (CareerDashboardView.swift:2421) prints the raw group string in a 22pt column then a literal "S:". Use "SAF" for the position group (the tile already uses DL/LB/CB/OL, so a 3-letter convention is consistent) or drop the per-row "S:"/"D:" prefixes and put STARTERS / DEPTH as column headers once at the top of the tile.

- [ ] **Q-M238 · The left rail is empty for the bottom ~55% of a portrait iPad screen**
  - evidence: On all three screens the rail's content ends at the "Advance to …" button (~y=870 of 2000 displayed, i.e. ~1200 of 2752 px); everything below it to the bottom of the screen is flat backgroundSecondary — roughly 1130 × 300 px of nothing, next to a right column that is scrolling. The postseason has no upcoming phases to draw (orderedPhases ends at .playoffs, so upcomingPhaseTasks breaks immediately), which is exactly why the rail empties out here and not in the regular season.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:762`
  - fix: The playoffs are the one phase where the rail has room and the player has questions. Fill it with what the round actually needs: the bracket (who you play, who the winner meets), your seed, the opponent's record and top-3 ratings, and the injury list — all data the engine already has (StandingsCalculator.playoffTeams, playoffSeedRanks). Failing that, pin the Advance button to the bottom and let the phase list breathe.

- [ ] **Q-M239 · On a win-or-go-home screen the opponent is the smallest text and the cap number is among the largest**
  - evidence: "vs DEN" is set in the band's 11pt slat subcaption at the very top edge; the largest figures on the same screen are "$22.7M" (Available cap) and "23/23" (staff slots), both several times its size, and neither is a Wild Card decision. The hero card that would carry the matchup is scrolled off the top — what is actually on screen is a cap bar, a staff count and a locker-room meter.
  - code: `dynasty/dynasty/UI/Career/SeasonWeekBand.swift:194`
  - fix: For .playoffs, promote the matchup into the tile grid at hero scale (opponent, seed, record, home/away, "lose and the season ends") rather than leaving it to an 11pt band subcaption; demote Cap/Staff, which are not actionable until the offseason (the CONTRACTS tile already says so: "Re-sign window opens in the offseason").

- [ ] **Q-M240 · PLAYOFF BRACKET and DEPTH CHART tiles are hardcoded labels with no state**
  - evidence: PLAYOFF BRACKET shows "WC / DIV / CONF / SB" and "Postseason path" — byte-identical on 063 (Wild Card), 064 (Divisional) and 065 (Conference); it never marks which round you are in or who is left. DEPTH CHART shows "View" and "Starters & backups" — no starter, no gap, no state at all.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1608`
  - fix: Both strings are literals (CareerDashboardView.swift:1608 and :1521). The bracket tile should at minimum bold the live round and name the opponent and the winner's next foe (playoffSeedRanks + upcomingGames already supply it — the hero card does exactly this); the depth chart tile should surface the one number it owns, e.g. "3 slots below replacement" or "OL depth C".

- [ ] **Q-M241 · The "NEED" flag lands on a group that reads better than two unflagged ones**
  - evidence: "S  S: B / D: B−  NEED" is flagged, while "RB S: B+ / D: C" and "OL S: B+ / D: C" are not — the flagged group has a better depth letter than both. Nothing on the tile explains the ranking; the letters shown cannot produce it.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2393`
  - fix: weakestGroup is `positionGroupGrades.min(by: { $0.starterOVR < $1.starterOVR })` (CareerDashboardView.swift:2393) — it ranks on a starter OVR the tile never prints, and it ignores depth entirely. Either print the OVR the ranking uses ("S 74 OVR — lowest starter group") in the NEED chip's tooltip/popover, or rank on the same letters the player is looking at.

- [ ] **Q-M242 · Chemistry is pegged at "Elite 100/100" — a full bar that cannot move**
  - evidence: LOCKER ROOM prints "Chemistry  Elite 100/100" with a completely full green bar, directly above "Team Morale 64%". Same value on all three screens. Two locker-room numbers side by side, one saturated and one mid-range, with nothing saying how they differ.
  - code: `dynasty/dynasty/Engine/Simulation/LockerRoomEngine.swift:110`
  - fix: LockerRoomEngine.calculateChemistry sums unnormalised per-player contributions (+8/+6/+3/+2/+1 for leaders, mentors, feel players, clowns, steady pros) against smaller toxicity penalties, then clamps: `max(0, min(100, 50 + leadership - toxicity))`. On a 53-man roster the positive sum routinely exceeds +50, so the meter parks at 100 and stops carrying information. Normalise by roster size (or use a per-player average), and label what chemistry does that morale does not.

- [ ] **Q-M243 · "42 expiring" is stated without a denominator, a cost, or anything to do about it**
  - evidence: CONTRACTS reads "42 expiring", then "Re-sign window opens in the offseason", then three names (CB Goddard 88 $12.8M, QB Wimberly 86 $31.0M, DT Pankhurst 83 $795K) and "View all in Salary Cap →". 42 is most of a 53-man roster and the card gives no share, no next-year cap consequence, and explicitly no action.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3472`
  - fix: expiringContractPlayers is `players.filter { $0.contractYearsRemaining <= 1 }` (CareerDashboardView.swift:3472). Print it as "42 of 53" plus the money coming off the books and the cap room it creates next year — that turns a scary number into the planning fact it actually is. If 42/53 is not intended, the contract-length generator is the place to look.

- [ ] **Q-M244 · Rail claims "Phases complete (14)" while its own button says "Advance to the Championship"**
  - evidence: 065 shows, 380px apart in the same column: "✓ Phases complete (14)" and the gold button "Advance to the Championship". TimelineTasksPanel.orderedPhases has 15 entries with `.playoffs` last, and pastPhases is everything before the current index — so the 14 counted as complete include `.superBowl` ("The Championship") and `.proBowl` ("All-Star Game"), the two the club is still trying to reach. Expanding the disclosure lists them by name.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:46`
  - fix: orderedPhases (TimelineTasksPanel.swift:46) starts the cycle at proBowl/superBowl, but the engine's chain is playoffs → proBowl → superBowl (WeekAdvancer.swift:5566), so during the playoffs the two postseason phases are ahead, not behind. Rotate the rail's cycle to match the engine, or exclude the postseason group from pastPhases while `currentPhase == .playoffs`.

- [ ] **Q-M245 · Two playoff wins generate zero mail — the newest of 192 messages is still "Week 18, Season 2027"**
  - evidence: On 065 (Conference Championship week, so the Wild Card and Divisional games have both been won) the five newest messages are "League Office — Playoff Berth Clinched", "Director of Scouting — Scouting: 28 new reports…", "Player Development — Development Report — Week 18", "Local Media — Weekly Press Conference Reminder", "Demetri Goddard — Game Plan Ready (Defense)", every one stamped "Week 18, Season 2027". Identical list on 063 and 064.
  - code: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:2940`
  - fix: WeekAdvancer.advancePlayoffWeek appends an inbox letter only for the user's ELIMINATION (WeekAdvancer.swift:2940); a win goes to career.postNews (News screen) and never to the inbox, and the weekly cadence senders (Player Development, Local Media, Director of Scouting) stop at week 18. The postseason is the emotional peak of the year and the mailbox goes silent — add round-win letters, an owner note, and a media reaction; InboxEngine.dateLabel already knows how to stamp them ("Wild Card, Season 2027").


### Season end

- [ ] **Q-M246 · Two unlabelled "X/Y" counters sit 40px apart in the rail and mean different things**
  - evidence: 066: header pill "1/1" (tasks done this phase) with caption "POSTSEASON · STEP 1 OF 2" (phase position in its group) immediately below. 067: "2/2" over "STEP 2 OF 2" — identical numbers by coincidence, which teaches the wrong reading. 069: "0/2" over "STEP 1 OF 2" — the two now disagree, and nothing on screen says why.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:139`
  - fix: Label the header pill — "1/1 tasks" — or move it onto the phase row it actually describes. The `taskProgress` helper is already the single source for this number; only the presentation is ambiguous.

- [ ] **Q-M247 · Roughly half the portrait rail is empty below the phase list on every screen**
  - evidence: 066: rail content ends at "+ 11 more phases" about 52% down a 2000px-tall render; everything below is bare background to the bottom of the screen. 067 ends at "+ 10 more phases" at ~62%. 069 ends at "+ 9 more phases" at ~70%. On the right, the same emptiness appears inside grid cells: HONORS on 066/067 holds two short lines in a cell ~3x taller than its content, and on 069 both "3-YEAR CAP" ($284M → $343M / Projection across 3 seasons) and "INBOX" (203 unread / Offseason news) do the same.
  - fix: The rail's dead half is the natural home for the thing the hub currently has no room for: expand "+ N more phases" into the remaining timeline by default, or park the current phase's key numbers (cap space, expiring count, owner goal) there. For the half-empty tiles, let the grid size rows to content instead of matching the tallest sibling, or give the stub tiles real content (see the HONORS finding).

- [ ] **Q-M248 · Salary Cap tile signals danger and success about the same fact: a red 92.0% bar sits directly above a green "$22.7M"**
  - evidence: All three screens: a full-width RED bar labelled "92.0%", then "Available  $22.7M" in success green, then "Total Cap  $284.1M". The clipped row above it carries a "CAP TIGHT" warning chip. The player is told, in three colours within 60px, that the cap is critical, tight, and healthy.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2237`
  - fix: `Available` uses `t.availableCap > 0 ? Color.success : Color.dangerText` — a binary above/below zero — while the bar uses `capBarColor(usedFraction)`, a graded scale. Drive both from the same `usedFraction` thresholds so "available" turns amber the moment the bar does.

- [ ] **Q-M249 · HONORS tile is a permanent stub — it says awards "arrive in your inbox" during the All-Star Game itself, next to a rail row saying you already reviewed them**
  - evidence: 066 and 067: the HONORS tile shows only "All-Star & All-Pro" / "Selections arrive in your inbox" with a chevron, and no club-specific number at all. On 066 the rail row beside it reads "✓ Review All-Star selections" (struck through, done) and on 067 "✓ Review league awards" (done). The tile is at its most prominent in the one phase whose entire subject is awards, and has nothing to say.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1088`
  - fix: The code comment above `awardsHubTile` states the cause: "nothing persists a per-club count". Persist the All-Star / All-Pro selections per club per season when `WeekAdvancer` generates the proBowl mail, then print "3 All-Stars · 1 All-Pro" with the names. Reference: Madden's franchise hub lists the club's Pro Bowlers by name on the postseason screen; OOTP shows the award winners inline with a link to the ballot.

- [ ] **Q-M250 · LOCKER ROOM prints two morale-family numbers 36 points apart with no explanation and only one bar**
  - evidence: All three screens: "Chemistry  Elite 100/100" with a full green bar, then "Team Morale  64%" in amber with no bar, then "QB Wimberly 🙂" — a face icon with no legend. A perfect 100 and a mediocre 64 on the same card, after a 14-3 season, with nothing saying what separates chemistry from morale or what moves either.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2296`
  - fix: The bar deliberately belongs to chemistry (comment at :2280), which leaves morale as a bare number. Give morale its own bar on the same scale, and add a one-line driver under it ("−12 from 3 unhappy starters on expiring deals") — SquadDynamicsView already computes exactly that insight (SquadDynamicsView.swift:678). Then a tap should open the breakdown, since neither number is currently explainable from this screen.

- [ ] **Q-M251 · "Postseason complete (1)" is printed directly above "THE CHAMPIONSHIP — NOW — POSTSEASON · STEP 2 OF 2"**
  - evidence: 067 rail, top to bottom: "✓ Postseason complete (1)" then "THE CHAMPIONSHIP · NOW · Feb / POSTSEASON · STEP 2 OF 2". The postseason is not complete — the player is inside step 2 of 2 of it, and the primary button below reads "Advance to Coaching Changes".
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:204`
  - fix: `completedPhasesLabel` names the group of the finished phases without checking whether the CURRENT phase belongs to that same group. When `career.currentPhase.group` is in the completed set, fall back to "Phases complete" (or "1 phase complete") instead of "<Group> complete".

- [ ] **Q-M252 · Four different date formats in one five-row message list, including two dash styles**
  - evidence: 067 message list, top to bottom: "Offseason - The Championship, 2027" · "Offseason - The Championship, 2027" · "Offseason - All-Star Game, Season 2027" · "Season 2027 — Postseason" · "Week 21, Season 2027". Same field, four shapes: phase-first vs season-first, "2027" vs "Season 2027", ASCII hyphen vs em dash. 066 and 069 show the same mix ("Season 2027 — Postseason" beside "Week 18, Season 2027" beside "Offseason - Coaching Changes, 2027").
  - code: `dynasty/dynasty/Engine/Media/InboxEngine.swift:1861`
  - fix: `InboxMessage.date` is a free-form String written at ~20 call sites. InboxEngine:1861 emits "Offseason - <phase>, <season>", WeekAdvancer.swift:3259 emits "Offseason - All-Star Game, Season <season>", WeekAdvancer.swift:5532 emits "Season <season> — <group>", InboxEngine:1832 emits "Week <n>, Season <season>". Make every producer call `InboxEngine.dateLabel(week:season:phase:)` and delete the hand-rolled literals — the function already exists and is public.

- [ ] **Q-M253 · Mail badge shows "99" while the same viewport says "203 unread" — the cap has no "+"**
  - evidence: 069: the top-nav envelope badge reads "99"; the INBOX tile on the same screen reads "203 unread"; the MESSAGES header reads "203" and the footer "198 more messages". On 066 the badge is "99" against "MESSAGES 194", on 067 "99" against "197". The badge reads as an exact count, so three screens show a number that is flatly wrong.
  - code: `dynasty/dynasty/UI/Common/TopNavigationBar.swift:201`
  - fix: `Text("\(min(unreadInboxCount, 99))")` truncates without marking it. Emit `unreadInboxCount > 99 ? "99+" : "\(unreadInboxCount)"`. (The accessibility label at :211 already says the true count, so VoiceOver and the visual badge currently disagree too.)

- [ ] **Q-M254 · Rail task descriptions truncate on exactly the clause that tells you how to finish the task**
  - evidence: 069, current phase COACHING CHANGES: row 1 reads "Optional · Evaluate your coordinators and position coaches, then confirm the review on…" — cut before naming the tab. Row 2 reads "Optional · Check offensive and defensive scheme fit with yo…" — cut mid-word, with a gold "Roster" chip occupying the right of that line. Both full strings end "...then confirm the review on the Review tab. / ...on the Schemes tab.", i.e. the actionable half is the half removed.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:453`
  - fix: At HEAD this Text carries `.lineLimit(2)` on a 300 pt rail. An uncommitted working-tree edit already raises it to 4 with a comment naming this exact failure — commit it. Also move the secondary chip ("Roster") to its own line below the sentence rather than sharing line 2, since `.fixedSize()` on the chip steals the width the sentence needs.

- [ ] **Q-M255 · Coaching Changes is a pass-through phase: both tasks are marked Optional and the Advance button is live at 0/2**
  - evidence: 069: header "YOUR OFFSEASON 0/2"; both rows are prefixed "Optional ·" ("Review coaching staff", "Review coordinator schemes"); neither carries the red "Required" pill the panel uses elsewhere; and the gold "Advance to Review Roster" button is already enabled above them. Nothing on the screen states a cost for skipping, so pressing Advance strictly dominates.
  - code: `dynasty/dynasty/Engine/Simulation/TaskGenerator.swift:767`
  - fix: Both tasks ship `isRequired: false`. Give the phase a real trade-off the hub can show: a coordinator whose scheme fit is wrong should carry a visible penalty (scheme-fit delta on the position grades, or a morale hit), and the rail row should state it — "Skip: DC scheme stays Cover-3 vs a roster graded B- at S". Reference: FM's staff screen prices every unfilled role against the squad it coaches; here the phase currently costs nothing either way.

- [ ] **Q-M256 · OWNER tile shows one goal with no subset marker while SEASON REVIEW on the same screen says "4 of 4 met"**
  - evidence: 069: OWNER card lists exactly one goal — "★ Make the Playoffs … Met" — under "Job Security: Secure". Two cards below, SEASON REVIEW reads "4 of 4 met / Owner verdict: Outstanding". A reader takes the owner card as the complete goal set and the review card as a different, larger one.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2752`
  - fix: The tile renders `evaluatedOwnerGoals.first(where: { $0.priority == .primary })` and nothing else. Add a count caption on the same row — "Primary goal · 1 of 4" — or a compact 4-dot progress strip so the card reads as a summary of a set rather than the whole set.

- [ ] **Q-M257 · CONTRACTS shouts HIGH PRIORITY over "42 expiring contracts" but exposes three names and no way to triage the rest here**
  - evidence: All three screens show the identical, unchanged tile: red "HIGH PRIORITY" pill, "42" in large red, "expiring contracts", then exactly three rows — "CB Goddard 88 $12.8M", "QB Wimberly 86 $31.0M", "DT Pankhurst 83 $795K" — and "View all in Salary Cap →". No years-remaining, no cap hit if they walk, no sort. On 069 the rail shows the phase that can actually act on them ("Franchise Tag Decisions", "Analyze Contract Situations") is two phases away under REVIEW ROSTER.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2589`
  - fix: `expiringContractPlayers` is `players.filter { $0.contractYearsRemaining <= 1 }` (:3472) — one bucket lumping deals with 0 and 1 year left. Split them ("9 expiring now · 33 in final year"), rank the three shown rows by cap hit rather than fetch order, and add the one number that makes this a decision: total cap coming off the books. Reference: OOTP's contract page leads with expiring-payroll totals; Madden's re-sign screen sorts by cap hit with a tag/extension cost per player.

- [ ] **Q-M258 · Three different date grammars in the inbox feed, two of them on adjacent rows**
  - evidence: Adjacent rows in the dashboard inbox card: "Yosef Estabrook / Welcome -- Roster Assessment Needed" stamped "Offseason - Coaching Changes, 2027" (ASCII hyphen, phase first, bare year), and directly below it "League Office / Offseason Begins" stamped "Season 2027 — Offseason" (em dash, season first, reversed order). A third form exists in the same feed's producers: `"Offseason - Coaching Changes, Season \(career.currentSeason)"` (WeekAdvancer.swift:3405, 3470, 3496, 3555 and eleven more sites) inserts the word "Season" that InboxEngine's own formatter omits.
  - code: `dynasty/dynasty/Engine/Media/InboxEngine.swift:1861`
  - fix: Route every InboxMessage date through `InboxEngine.dateLabel(week:season:phase:)` and delete the hand-written interpolations in WeekAdvancer, NewsGenerator and TamperingRumorEngine. Right now a player scanning 203 messages cannot sort or scan by date because the stamps do not share a grammar, and the strings are free text so nothing can sort them chronologically.

- [ ] **Q-M259 · Three duplicated surnames inside a single 15-man coaching staff**
  - evidence: In one list: "AHC Zavier Goddard 74" and "DC Demetri Goddard 50"; "RB Ramiro Kirkbride 47" and "DL Alicia Kirkbride 58"; "DOC Tobias Derringer 59" and "PHY Jeremiah Derringer 57". The surname pool is 55 entries drawn with a bare `randomElement()` and no dedup, shared by coaches, players and scouts. At 14 draws the birthday-collision probability is roughly 80%, so at least one duplicate pair per staff is the expected outcome, not bad luck. The same pool feeds ~1,700 league players, so every surname is carried by ~31 men. The team has already hit this elsewhere — DraftTickerPanel.swift:309 documents "`R. Goddard` printed twice, one line under the other".
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:65`
  - fix: Either expand the surname list by an order of magnitude, or pass a used-name set through generation and reroll on collision within a club (and within a draft class). A staff where the assistant head coach and the defensive coordinator are both "Goddard" is an immersion break, and it makes abbreviated forms ("D. Goddard") ambiguous in every list that uses them.

- [ ] **Q-M260 · Inbox badge clamps to a bare "99" with no overflow marker, on a screen that says there are 203 messages**
  - evidence: The top-bar envelope badge reads "99". The inbox card on the same screen ends with "198 more messages" under five listed rows — 203 messages in the same `filteredInboxMessages` collection the badge counts from. The badge is `Text("\(min(unreadInboxCount, 99))")`, so any unread count of 99 or more renders as an exact "99" with nothing to indicate it is a cap.
  - code: `dynasty/dynasty/UI/Common/TopNavigationBar.swift:201`
  - fix: Render "99+" above the cap (`unreadInboxCount > 99 ? "99+" : "\(unreadInboxCount)"`). Also worth asking why 203 messages have accumulated by the 2027 offseason with none aged out — the badge is only the symptom; an inbox nobody can drain is why the number reached the clamp.

- [ ] **Q-M261 · The review sheet's bottom edge slices horizontally through the "SCHEMES & EXPERTISE" header**
  - evidence: The sheet ends mid-glyph on its next section: the letters of "SCHEMES & EXPERTISE" are cut across their x-height, with the book icon beside them half gone, and no scroll indicator or fade to say more content exists. The sheet asks for `.presentationDetents([.large])`, but on a regular-width iPad a sheet presents as a fixed-size form sheet and detents are ignored, so the requested height never applies — the measured sheet is ~574 × 654 pt inside a 1032 × 1376 pt screen.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:560`
  - fix: Either give the sheet an explicit `.presentationSizing(.page)` / fullScreenCover on iPad so the requested height is honoured, or add bottom padding and a scroll-edge fade so the cut lands in whitespace rather than through a heading. A sliced header reads as a rendering fault, and it hides the fact that the scheme-fit analysis — the only part of this sheet that carries a judgement rather than a list — exists at all.

- [ ] **Q-M262 · Team chemistry is pinned at the ceiling — "Elite 100/100" over "Team Morale 64%" in the same card**
  - evidence: The Locker Room tile reads "Chemistry  Elite 100/100" with a completely full green bar, directly above "Team Morale  64%" and a frowning QB face for "QB Wimberly". Chemistry is `50 + leadershipScore - toxicityScore`, clamped `max(0, min(100, ...))`, where leadershipScore accumulates per player across a 53-man roster (teamLeader +8, mentor +6, feelPlayer +3, classClown +2, steady/quiet +1 each, plus +2 per motivation group of three or more). The sum is unbounded against a ceiling of 100, so any roster that is not overtly toxic saturates and the meter can never move.
  - code: `dynasty/dynasty/Engine/Simulation/LockerRoomEngine.swift:103`
  - fix: Normalise before clamping — divide the net score by roster size, or express it as a delta from a 50 baseline scaled by squad count — so the bar has headroom in both directions. As shipped, the headline number on the Locker Room tile is a constant, which also means the player's locker-room decisions have no visible payoff here. A tile that always says 100/100 next to a morale number that says 64% reads as a bug even when it isn't.

- [ ] **Q-M263 · "Coaching Staff Review" is a read-only list — one number per coach, ten of them red, and nothing you can do about any of it**
  - evidence: Fifteen rows, each carrying only a green check, a role code, a name and one OVR: 74, 68, 50, 48, 64, 47, 59, 64, 58, 53, 54, 63, 59, 57, 58. Ten of the fifteen paint danger red. No age, no contract years, no last-season trend, no league average, no salary — nothing that says whether 58 for a linebackers coach is bad or normal. The rows are not buttons and have no chevron, so a red 47 at RB coach cannot be opened or replaced from here. The sheet's only two controls are "Cancel" and "Advance", and with "15/15 filled" the warnings section is empty, so the gate cannot be failed — it is one extra tap between the rail's Advance button and the phase change.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:5004`
  - fix: This is the last screen before the phase closes, so it should be the screen that makes the case for acting. Reference: FM's staff screen puts each coach's star rating against the division average and lets you click through to the man; OOTP's coaching page shows the contract alongside the rating. Minimum: make each row tappable to the coach's page, add a league-average marker to the OVR column, and surface the unspent staff budget (the hub tile behind this sheet reads "Budget $14.7M / $35.2M") so the player can see there is money to fix the ten red rows.


### Training camp — training focus

- [ ] **Q-M264 · Drafted rookies lose their college — 0 of 11 rows show a school although the row template has a slot for one**
  - evidence: Every row's second line reads only "$4.7M · 4 yrs", "$2.4M · 4 yrs", "$1.8M · 4 yrs" etc. The row renders `if let college = row.college, !college.isEmpty { Text(college) }` from `player.college`, which is never populated: `DraftEngine.convertToPlayer` does not set it and `copyProspectMetadata` copies `hometownState` and `hometownCity` but not `college`, so `Player.college` stays at its `nil` default. The school does survive onto `DraftPick.playerCollege` and `PickResult.Dossier.college`, just not onto the player himself.
  - code: `dynasty/dynasty/Engine/Draft/DraftEngine.swift:618`
  - fix: Add `player.college = prospect.college` to `copyProspectMetadata`. This is a one-line loss that empties the school field on every screen that reads `Player.college` for the whole career of every drafted player, not just this reveal.

- [ ] **Q-M265 · Each rookie row carries two contradictory verdicts — a red down-arrow and a green STEAL chip — with nothing saying they are different graders**
  - evidence: "R1 · #30 RT Osman Tanguay  B−/A ↘ 58" with "Press A+ · STEAL" in green; "R7 · #252 K Roman Nadeau  C−/B ↘ 53" with "Press A+ · STEAL". Eight of the eleven rows show the red ↘ (staff evaluation landed below the pre-camp band) next to a green best-possible press chip. The only explanation on screen is the caption "Pre-camp band vs. the evaluation your staff filed this morning", which describes the band/arrow/OVR group and never mentions that the chip is last April's draft-night verdict rather than today's.
  - code: `dynasty/dynasty/UI/Draft/RookieClassRevealView.swift:642`
  - fix: Split the row into two labelled halves — "DRAFT NIGHT: Press A+ · STEAL" and "TODAY: B−/A → 58 ↘" — or drop the press chip from the row and keep it in the verdict card only. A football fan reading no manual sees green STEAL beside a red down-arrow and cannot tell which one is the news.


### Training camp — position battles

- [ ] **Q-M266 · Every rookie's college is missing — Player.college is never written anywhere in the app**
  - evidence: The second line of each row shows only the deal ("$4.7M · 4 yrs", "$1.1M · 4 yrs") on all 11 rows. The row is designed to lead with the school: RookieClassRevealView.swift:620 renders `if let college = row.college, !college.isEmpty` before the deal text, fed by `college: player.college` (line 335). DraftEngine.convertToPlayer builds the Player without a college argument, and copyProspectMetadata (DraftEngine.swift:608-630) carries learning, competitiveness, draftTruePotential, hometownState, hometownCity, faceID and the pre-draft injury — but not college. Grepping the tree for writes to `Player.college` returns none; the prospect's school (set at DraftClassBuilder.swift:603 from ScoutingEngine.colleges) is discarded at the podium, so every drafted player in the save is school-less for life.
  - code: `dynasty/dynasty/Engine/Draft/DraftEngine.swift:608`
  - fix: Add `player.college = prospect.college` to DraftEngine.copyProspectMetadata alongside the hometown pair. One line, and it lights up an already-written render path here and anywhere else Player.college is read.

- [ ] **Q-M267 · "The room's favourite pick" is a tie-break, not a judgement — it is always your earliest pick when the grades tie**
  - evidence: The press verdict names "The room's favourite pick: R1 · #30 RT Osman Tanguay" while every one of the 11 rows carries the same "Press A+ · STEAL" chip. All 11 therefore score the identical 4.3 points (RookieClassReveal.points), and bestLine is `gradedRows.max(by: { $0.points < $1.points })` (line 359), which under a total tie returns the first element — the earliest pick. The paragraph presents an arbitrary tie-break as the war room having an opinion, and the screen offers nothing that distinguishes Tanguay from the ten men below him.
  - code: `dynasty/dynasty/UI/Draft/RookieClassRevealView.swift:359`
  - fix: Break the tie on something meaningful — largest positive valueDelta, then highest actual overall — and suppress the sentence entirely when every graded pick shares a grade (which is itself the more honest headline given the STEAL calibration).

- [ ] **Q-M268 · Three of eleven rookies share the surname Tanguay**
  - evidence: "R1 · #30  RT  Osman Tanguay", "R3 · #94  RB  Harlan Tanguay", "R4 · #104  DT  Wade Tanguay" — three Tanguays in an 11-man draft class, with no relation modelled and nothing on screen acknowledging it. RandomNameGenerator holds 55 first names × 55 surnames (3,025 unique pairs) for a 32-club league of ~1,700 players plus a fresh ~350-prospect class every spring. uniqueName (RandomNameGenerator.swift:102) rejects only duplicate FULL names; surname frequency inside a cohort is never checked, so roughly six men share each surname in every draft class.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:102`
  - fix: Grow the surname pool (a few hundred entries costs nothing) and cap surname repeats per generated cohort inside uniqueName — reject a surname already used N times in `used` before falling back to the cross-product walk.


### Training camp — workload

- [ ] **Q-M269 · The "staff's first read on his ceiling" projection can never render on this screen — the field is written after the reveal**
  - evidence: No row shows the binoculars projection chip the layout provides for; all 11 second lines are just the deal ("$1.6M · 4 yrs"). Row.projection is documented as "The staff's first read on his ceiling (noise-2 by design)" and reads `player.assessedPotential` (RookieClassRevealView.swift:342), rendered as a gold Label at line 630. assessedPotential is written in exactly one place — PlayerDevelopmentEngine.swift:1958, inside the yearly camp development pass, explicitly "Written AFTER development … re-written every camp". A rookie drafted this spring has never been through that pass when RookieClassReveal.build runs at the camp boundary, so the field is nil for the entire class, every season.
  - code: `dynasty/dynasty/UI/Draft/RookieClassRevealView.swift:342`
  - fix: Stamp an initial assessedPotential at the draft boundary (from the scout's band plus the same noise the label uses) so the reveal has a ceiling to print, or drop the projection from the row and stop reserving layout for it.

- [ ] **Q-M270 · The grade column is unlabelled and three separate colours carry meaning with no legend anywhere on screen**
  - evidence: The right-hand cluster reads "B−/A ↘ 58", "C+/B ↘ 59", "C/B+ = 61" with no column header — nothing says the number is OVR, or that the letters are the pre-camp band. Three encodings are silently load-bearing: the band's tint (RookieFog.Source — gold = your scouts filed on him, grey = media consensus for his round), the arrow (↘ below / = matched / ↗ above the band), and the OVR's red-vs-gold (Color.forRating, flipping at 60 — hence 59 red and 61 gold, a two-point gap producing a colour change). The only explanation offered is the caption "Pre-camp band vs. the evaluation your staff filed this morning." A hardcore player cannot tell why one man's band is gold and another's grey, which is precisely the payoff for a spring of scouting spend.
  - code: `dynasty/dynasty/UI/Draft/RookieClassRevealView.swift:601`
  - fix: Add a one-line legend under the caption — "gold band = your scouts · grey = media · ↘ under the report" — and header the numeric column "OVR". A tap on any band chip could reveal how many scout reports produced it (GradeRange already carries reportCount).


### Training camp — practice picker

- [ ] **Q-M271 · Position Battles empty state tells you to go to the phase you are already in**
  - evidence: The tile reads "POSITION BATTLES / None active / Camp competitions open in Training Camp" while the sidebar reads "TRAINING CAMP  NOW  Jul–Aug" and the hero card reads "Active battles  0". The copy is unconditional — CareerDashboardView.swift:1371 prints it whenever openPositionBattles.isEmpty, with no phase check. The real reason the list is empty is that PositionBattleTracker.detectBattles only runs on a camp-week advance (WeekAdvancer.swift:8586) and the player has just entered camp, which the copy never says. The sidebar meanwhile offers the task "Resolve position battles — Optional · Track daily winners in position competitions and lock in starters", promising an affordance with zero content behind it (and its destination is .depthChart, TaskGenerator.swift:1235, not a battles screen).
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1371`
  - fix: Make the empty state phase-aware: inside Training Camp say "Battles open after the first camp week — advance to see them"; outside camp keep the current line. Gate or grey the "Resolve position battles" task while openPositionBattles is empty, or point it at the camp screen rather than the depth chart.

- [ ] **Q-M272 · "WEEK 21" in a July training camp — the raw offseason counter is printed in the same "Week N" vocabulary the regular season uses**
  - evidence: The modal header reads "WEEK 21 — PICK ONE" while the sidebar behind it reads "TRAINING CAMP  NOW  Jul–Aug" and "PRE SEASON · STEP 2 OF 4". A football fan reads "Week 21" as week 21 of a 17-game season, which does not exist. The string is `"Week \(career.currentWeek) — Pick One"` and currentWeek is the unreset offseason counter — the codebase already knows this: CareerDashboardView.swift:3906-3911 removed a "Day N / 21" readout for exactly this reason, noting currentWeek "sits at 19+ for the whole offseason (only startNewSeason resets it)". GameWeekPrepPicker.swift:75 uses the identical "Week \(career.currentWeek)" phrasing for real regular-season weeks, so one label means two different things.
  - code: `dynasty/dynasty/UI/Camp/VoluntaryWorkoutPrompt.swift:53`
  - fix: Label the header by phase, not by the raw counter — "Training Camp · Week 2 — Pick One" (or "OTAs · Week 1"), derived from the phase's own step, the same way PreseasonState.step is used for the preseason card.

- [ ] **Q-M273 · The only live control on the modal is the escape hatch: Submit is disabled with no default selected, Skip this week is fully enabled**
  - evidence: "Submit" in the top-right renders greyed against the enabled white "Skip this week" in the top-left; no card shows the gold selected border/checkmark, so nothing is chosen. Code confirms `.disabled(selected == nil)` (VoluntaryWorkoutPrompt.swift:43) with `@State private var selected: VoluntaryWorkoutType?` starting nil. A player following the 10-second rule sees one tappable button — the one that opts out of the decision — and there is no safe default. Nothing on screen says a choice is required to enable Submit beyond the small caps "WEEK 21 — PICK ONE".
  - code: `dynasty/dynasty/UI/Camp/VoluntaryWorkoutPrompt.swift:43`
  - fix: Pre-select the safe default (Voluntary OTAs, the no-injury option) so Submit is live on arrival and the modal has an obvious primary action; keep Skip as a plain text link, not a filled toolbar button competing with it. Alternatively keep Submit disabled but label it "Pick an option" so the disabled state explains itself.

- [ ] **Q-M274 · The sheet is short enough to slice the 4th option in half — Off-Day Practice's Scheme/LR/Inj chips are below the cut with no scroll affordance**
  - evidence: The modal's bottom edge falls through the fourth card: "Off-Day Practice" and its blurb "Intensive — adds fatigue and injury risk for a sharper edge." are the last visible content, and the chip row that every other card has ("Scheme +3 / LR +2 / Inj +0%" etc.) is cut off entirely. The option carrying the highest injury cost is the one whose numbers cannot be read. The three cards above it are fully visible, so nothing signals that content continues; there is no scroll indicator or peeking partial row to imply it.
  - code: `dynasty/dynasty/UI/Camp/VoluntaryWorkoutPrompt.swift:22`
  - fix: Give the sheet a taller detent (or .presentationDetents([.large]) on iPad) so all four cards fit, or reflow the four options into a 2×2 grid — they are short cards on a 13-inch portrait canvas. At minimum, cut the sheet between cards rather than through one.

- [ ] **Q-M275 · The Training Camp hero card is three empty values on the one visit the player makes to it — two of them in gold**
  - evidence: "Training Camp · Install & Evaluation" carries exactly three stat rows and all three are null on arrival: "Workload heatmap — 0% overloaded", "Active battles — 0", "Top camp grade — Not graded yet". The card's own doc comment (CareerDashboardView.swift:3903) says camp "is one visit", so this is the state the player sees. "0" and "Not graded yet" are rendered in the gold accent that the design otherwise reserves for emphasis, spending the loudest colour on the emptiest numbers. The largest, boldest thing on the screen is a headline over three blanks, with the only CTA — "Open Training Plan →" — sending the player somewhere else to find content.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3913`
  - fix: On first camp entry, replace the null rows with what the player can act on now: roster count vs the 75 limit (the sidebar already computes "Cut to 75 (87 currently)"), rookies reporting, and days to the first preseason game. Restrict gold to values that are actually notable — render "0" and "Not graded yet" in textTertiary.


### Training camp — training plan

- [ ] **Q-M276 · POSITION BATTLES tells the player battles "open in Training Camp" while he is in Training Camp**
  - evidence: The tile reads "None active / Camp competitions open in Training Camp" at the same moment the left rail shows "TRAINING CAMP · NOW · Jul–Aug" and the hero reads "Training Camp · Install & Evaluation". The rail simultaneously offers a tappable row "Resolve position battles — Optional · Track daily winners in position competitions and lock in starters" pointing at content that does not exist, and the hero reads "Active battles 0". The empty-state string is unconditional — no phase check.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1371`
  - fix: Branch the empty state on `career.currentPhase`. Inside camp it should say when battles appear (they are created by `PositionBattleTracker.tickDay` during the first camp week sim) — e.g. "Battles open after the first camp week — advance to see them." Outside camp the current copy is correct.

- [ ] **Q-M277 · The camp hero card — the largest, gold-bordered element on the page — prints three null values**
  - evidence: "Training Camp · Install & Evaluation" then "Workload heatmap — 0% overloaded", "Active battles — 0", "Top camp grade — Not graded yet". On day one of camp all three are structurally empty, and "Not graded yet" is repeated verbatim in the CAMP GRADES tile at the bottom of the same page. The first thing the eye hits therefore tells the player nothing, while the one thing he actually has to do ("Required: Set training focus") is a small red line in the left rail.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3916`
  - fix: On entry to camp the hero should carry the decision, not the outcome: roster 87/75 with cuts owed, the focus split that will be applied if he does nothing, days until the first cutdown. Swap in the outcome rows ("0% overloaded", grades, battles) only once a camp week has been simmed. Also drop the "Workload heatmap" label — it names a screen, not the metric "0% overloaded" beside it.

- [ ] **Q-M278 · TRAINING PLAN and WORKLOAD tiles are static captions with no state, stretched into visible dead space**
  - evidence: The TRAINING PLAN tile shows "Set focus" / "Tactical / Physical / Technical" and nothing else, occupying roughly 240 px of height with content only in its top ~90 px because it is stretched to match the CONTRACTS tile beside it. WORKLOAD shows "Monitor camp load" / "Injury & burnout risk". Both are hard-coded literals — `trainingPlanTile` and `workloadTile` contain no bindings — in a grid where every neighbouring tile carries live numbers ("Players 56", "$194.8M", "17 expiring", "Elite 100/100").
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1623`
  - fix: Show the saved split ("34 / 33 / 33 · saved for camp week 1" or "Not set — engine will run 34/33/33") on TRAINING PLAN, and the two worst-loaded players plus the overloaded count on WORKLOAD. Both numbers already exist in state; the tiles are the player's only at-a-glance record of the decision he just made and currently reflect none of it.

- [ ] **Q-M279 · The required "Set training focus" gate is satisfied by saving the exact split the engine would have used anyway**
  - evidence: The rail marks "Set training focus" as "Required to advance" and "Advance to Preseason" is held behind it. camp_09 opens on Tactical 34% / Physical 33% / Technical 33% and the commit bar reads "Banks 34/33/33 tactical, physical and technical for this week's development pass." `WeekAdvancer.fetchOrSeedTrainingPlan` falls back to `tacticalPct: 34, physicalPct: 33, technicalPct: 33` when no plan is saved — byte-identical. Tapping "Save plan" without touching a slider produces exactly the outcome of never opening the screen.
  - code: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:8702`
  - fix: A required step should force a real choice. Either make the screen show what each split buys (projected attribute deltas per position group for the four presets, side by side) so 34/33/33 is a considered decision rather than an accepted default, or demote the task to optional and let the seeded plan run. As written it is a click-through.


### Training camp — training focus

- [ ] **Q-M280 · The current split IS the Balanced preset, but no preset chip shows a selected state**
  - evidence: Sliders read Tactical 34% / Physical 33% / Technical 33%, which is exactly `Preset.balanced = (34, 33, 33)`. All four chips — "Balanced", "Scheme Heavy", "Camp Hard", "Recovery Mode" — render identically: same `Color.backgroundTertiary` fill, same `Color.surfaceBorder` stroke, same `Color.textPrimary` label. `presetRow` has no selection concept and `applyPreset` records nothing, so on a 100th visit the player cannot tell at a glance whether he is on a preset or a hand-tuned split.
  - code: `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:134`
  - fix: Derive selection from the live values (`Preset.allCases.first { $0.allocation == (tacticalPct, physicalPct, technicalPct) }`) and give the match a gold fill/border; show "Custom" when nothing matches. Also put each preset's split in the chip subtitle ("Camp Hard · 20/50/30") so the four options can be compared without tapping each one and losing the current split.

- [ ] **Q-M281 · Roughly 60% of every workload row is blank — the table wastes the whole middle of a portrait iPad**
  - evidence: In each of the 13 rows the identity block ends at the player name / "OVR 64" (about x=250 of 1500) and nothing is drawn again until the LOAD bar at x=1165 (`DSColumnHeader("LOAD", width: 96)`). That is ~915 px of blank row, ~60% of the width, repeated 13 times down the screen, while the numbers a GM needs for this decision — durability, stamina, age, snaps, injury history, whether the man is in a position battle — appear nowhere on the screen or one tap away.
  - code: `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:290`
  - fix: Fill the gutter with the decision inputs: DUR, STA, AGE, and last-season games missed as narrow numeric columns between PLAYER and LOAD. On a 1024pt-wide portrait canvas there is room for four more columns before anything crowds.

- [ ] **Q-M282 · The INJ column's entire dynamic range is 4%–6%, so it cannot separate a fragile player from a durable one**
  - evidence: 11 of the 13 visible rows read exactly "4% inj" and 2 read "5% inj" — across players from OVR 54 to OVR 84. `injuryRiskPct` = `baseRisk(0.04) × status.injuryMultiplier × durabilityFactor`, and `.underloaded`/`.healthy` both have `injuryMultiplier = 1.0` while `durabilityFactor` spans only 1.0…1.4. With the whole roster underloaded the column can only ever print 4, 5 or 6, and rounding to an integer throws away most of the durability signal. The code comment claims the formula exists "otherwise every player reads an identical 4% inj" — on screen it very nearly still does.
  - code: `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:368`
  - fix: Print one decimal (4.2% / 5.6%), or replace the percentage with the input the player can act on — durability and stamina ratings, plus games missed last season. A number that is the same for 85% of the roster is a column of noise occupying a fixed 44pt of every row.


### Roster cuts — cut to 75

- [ ] **Q-M283 · All three ladder slats are drawn as the screen's most interactive-looking element and none of them is tappable**
  - evidence: camp_10/11/12 draw "1 CUT TO 75", "2 CUT TO 65" and "3 CUT TO 53" as slanted tabs with index badges, dividers and a gold selected-underline — the visual language of a segmented control. All three are inert. RosterCutView passes only slats/headline/meter to DSSlatBand with no selectedID and no onSelect, so DSSlatButton receives action == nil and is .disabled(true), yet still declares .isButton to VoiceOver.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:538`
  - fix: Either make the future rungs previewable (tap step 2 to see what a 65-man roster would look like — the ladder is the screen's whole framing device) or drop the button chrome when onSelect is nil: no press style, no index badge highlight, and remove the .isButton trait at DSSlatBand.swift:570 so VoiceOver stops announcing three buttons that do nothing. DSSlatButton's own doc comment (DSSlatBand.swift:545-550) says the slat "must be the most obviously interactive thing on the screen" — on this screen that promise is inverted.

- [ ] **Q-M284 · Every player row wastes 772 pt of its width — a 1545 px void between the metadata and the cap figure, on all 87 rows**
  - evidence: Measured on camp_10's Orrin Hopewell row (y 650-725): ink ends at x=386 (the end of "Camp D") and the next ink is "+$0.7M" starting at x=1931 — a continuous 1545 px gap = 772.5 pt, about 75% of the 1032 pt row width, repeated on all 87 rows. The two lower ladder slats are similarly empty: "2 CUT TO 65" and "3 CUT TO 53" each occupy ~22% of the band width carrying nine and nine characters respectively.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:309`
  - fix: The row is HStack[avatar][name+meta][Spacer][value+PS] (RosterCutView.swift:308-315). On portrait iPad that Spacer is the screen's largest single design failure. Fill it with columns the decision needs and the engine already models: contract years remaining, snaps, injury flag, OVR trend since camp opened, depth-chart slot, and the keep-score rank. Right-align them as real columns with a sticky header so the list reads as a table rather than a phone list stretched to 1032 pt.

- [ ] **Q-M285 · Inverted hierarchy — the biggest text on screen is the static label "Roster Cuts"; the number that defines the task is 11 pt in a dim tertiary colour**
  - evidence: Measured cap heights on camp_10: "Roster Cuts" = 24 px (the largest text on the screen, centred, white, and it tells the player nothing they did not already know). "87 on the roster · 12 more to release" = 16 px in RGB(124,139,161) #7C8BA1 — the same optical size as its own slat title "CUT TO 75" (16 px) and as the band headline "CUT DAY 1 OF 3" (16 px). The eye hits a static noun first, the nine filter chips second, and the count that is the whole job third.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:373`
  - fix: Give the current slat a real internal hierarchy: promote the owed count to a display-voice figure ("12 TO RELEASE", title2/title1 step) above the roster context in caption, rather than running both at 11 pt in the same weight and colour. The DSSlat subcaption treatment (DSSlatBand.swift:726-727) is right for a five-stage scouting band and wrong for the one number a cut screen exists to communicate.

- [ ] **Q-M286 · Unfilled meter pips sit at 1.35:1 contrast — in the state the screen opens in, the entire meter reads as blank**
  - evidence: camp_10 opens with "0 spent · 12 left" and all twelve pips unfilled. The unfilled pip is a 1 pt stroke of Color.surfaceBorder #1E293B on Color.backgroundPlate #060B16 — a contrast ratio of 1.35:1, against a 3:1 minimum for non-text UI. The only element in that cluster that is actually visible is the half-way tick, sampled at RGB(138,150,168). camp_11's filled state (RGB(148,163,184) pips, "12 spent · 0 left") is legible, so the meter is readable only once the job is already done.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:418`
  - fix: pip(index:meter:) at DSSlatBand.swift:408-421 strokes empty pips in surfaceBorder. Raise the empty-pip stroke to at least textTertiary-on-plate (or fill them at ~15% textSecondary) so the unspent budget is visible at 3:1. This is a shared component — every band that opens with 0 spent has the same blank meter.

- [ ] **Q-M287 · Name-generator collisions make the list ambiguous to scan — three duplicated surnames, three Kenjis, and a duplicated initials avatar, all within fifteen visible rows**
  - evidence: camp_10's fifteen visible rows contain Hopewell ×2 (Orrin, C / Kenji, QB), Crisanti ×2 (Tobias, CB / Seneca, CB), Shelburne ×2 (Demetri, LT / Harlan, OLB) and Kenji ×3 (Marchetti WR, Vandenberg DT, Hopewell QB). The initials avatar — the only other per-row identifier — collides too: "KM" is drawn on both Kenji Marchetti (row 5) and Kason Maddocks (row 12). Two of the collision pairs are in the same position group (Crisanti/Crisanti both CB).
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:67`
  - fix: The pools are 55 first names × 55 surnames (RandomNameGenerator.swift:31-44 and 67-78) and uniqueName only guarantees unique FULL names, so an 87-man roster collides on surname by construction (the file's own doc comment already flags the abbreviation hazard: "the draft feed abbreviates to 'N. Abernathy', which names them both"). Either widen the surname pool substantially or add a per-team draw constraint that rejects a surname already on the same roster. Separately, stop deriving the avatar from initials alone (initials(for:) at RosterCutView.swift:684-688) — use jersey number or a position-tinted avatar so two men never share the same badge on one screen.


### Roster cuts — release result

- [ ] **Q-M288 · The confirm alert buries "Releases cannot be undone" at the end of a seven-line run-on paragraph and never names the twelve men**
  - evidence: camp_12's alert body is one block: "This frees $7.6M and leaves $1.9M of dead money on this year's books. Position groups after this: C 3 → 2 · CB 10 → 8 · DE 8 → 7 · DT 6 → 4 · LT 3 → 2 · MLB 4 → 3 · OLB 6 → 4 · QB 3 → 2 · WR 10 → 9. Releases cannot be undone." The only irreversibility warning is the final clause of the seventh wrapped line, inside a system alert roughly 460 px (230 pt) wide on a 1032 pt-wide iPad. The twelve names are never listed — the player has to trust that the twelve red outlines behind the dimmed alert are the right twelve, and eight of them are scrolled or covered.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:664`
  - fix: Replace the system .alert (RosterCutView.swift:117-124) with a confirmation sheet wide enough for the content: the twelve names as a scannable list, the money on its own line, the position table as a real table, and the irreversibility as a distinct warning row above the destructive button — not as prose clause #3. The destructive button label already carries the count; the warning should carry the weight.


### Lineup Incomplete dialog

- [ ] **Q-M289 · "Left OLB" and "Right OLB" are the only two abbreviations in a dialog that spells everything else out**
  - evidence: The blocking dialog reads: "Offense: Wide Receiver 3 unassigned / Defense: Left OLB unassigned / Defense: Right OLB unassigned". `DepthChartSlot.displayName` spells out all 27 slots — including "Middle Linebacker", "Strong Safety", "Kick Returner" — and `.LOLB` / `.ROLB` are the only two left as acronyms. cuts_01's dialog, which happens to draw three spelled-out slots ("Left Guard", "Right Tackle", "Free Safety"), reads cleanly by comparison.
  - code: `dynasty/dynasty/Domain/Models/Team/DepthChart.swift:89,91`
  - fix: `case .LOLB: return "Left Outside Linebacker"` and `case .ROLB: return "Right Outside Linebacker"`. The dialog is the one place in the app that gets read by someone who does not yet know the chart, and the two-line message has room.

- [ ] **Q-M290 · TRAINING PLAN and WORKLOAD hub tiles are hardcoded captions with no data, leaving the lower half of both cards empty**
  - evidence: camp_13: TRAINING PLAN reads "Set focus" / "Tactical / Physical / Technical" — a list of the options, not the focus that was chosen, while the sidebar on the same screen shows "✓ Set training focus" struck through as complete. WORKLOAD reads "Monitor camp load" / "Injury & burnout risk" while the hero card three cards above already prints the real figure: "Workload heatmap — 0% overloaded". Measured on the 2064×2752 original, the TRAINING PLAN card is 320 px tall with content stopping at 168 px, and WORKLOAD is 280 px tall with content stopping at 147 px — the lower ~50% of both is empty, and they sit in the bottom row of the grid where a portrait iPad has the most room. Both tiles are literal `Text` with no state read; every other tile on the screen (ROSTER, SALARY CAP, KEY PLAYERS, CONTRACTS, POSITION GRADES, POSITION BATTLES, OWNER) reads real data. Identical on cuts_01.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1623-1652`
  - fix: TRAINING PLAN should print the saved focus and its cost, e.g. "Physical · Week 3 of 4" over "Load 0% overloaded" — the player's last decision reflected back at him. WORKLOAD should print the two numbers the WorkloadDashboard already computes (players in the red band, highest cumulative load). If neither can be sourced, drop both to half-height nav rows rather than reserving a full grid cell for a caption.

- [ ] **Q-M291 · Gold is doing five different jobs in one column, so it no longer marks the one thing to do**
  - evidence: camp_13's left rail alone spends `accentGold` on the panel header "YOUR OFFSEASON", the phase title "TRAINING CAMP", the "NOW" pill, the "Roster" reference chip beside "Resolve position battles", and the "Advance to Preseason" CTA. Across the divider it is also every card title ("TEAM", "ROSTER", "SALARY CAP", "KEY PLAYERS", "CONTRACTS", "POSITION GRADES", "OWNER", "TRAINING PLAN", "WORKLOAD", "POSITION BATTLES"), the "9 active"/"4 active" figure, and the hero CTA "Open Training Plan →". On camp_14 gold takes a further job: the "STARTER" role label (accentGold #C9A94E) sits inches from the 60-69 OVR badges "65" and "62" (warning #EAB308) on the same RB card, two near-identical yellows meaning "this is the first-teamer" and "this player is mediocre".
  - code: `dynasty/dynasty/UI/Common/Theme.swift:25,49; dynasty/dynasty/UI/Roster/DepthChartView.swift:678`
  - fix: Demote card titles and the panel header to `textSecondary` and keep gold for exactly two roles: the live phase marker (NOW pill + phase title) and the single primary CTA. On the depth chart, render "STARTER" as an outlined white/secondary chip so the only yellow in a row is the rating band.

- [ ] **Q-M292 · "YOUR OFFSEASON 2/6" and "PRE SEASON · STEP 2 OF 4" sit 90 px apart and count entirely different things**
  - evidence: camp_13's rail header reads "YOUR OFFSEASON            2/6", directly above "Phases complete (9)", and three lines below sits "PRE SEASON · STEP 2 OF 4". The 2/6 is the CURRENT PHASE's task tally (Set training focus ✓, Review camp grades, Resolve position battles, Monitor workload, Check preseason storylines, Cut to 75 ✓ = 6 rows, 2 done) via `Self.taskProgress(tasks)`; the "2 OF 4" is Training Camp's index inside the PRE SEASON group. cuts_01 reads "3/6" and "STEP 3 OF 4" — the numerators match again, which makes the pair look like one counter with a typo in the denominator. Neither number is labelled, and "6" also happens to be the number of phase rows visible in the rail (TRAINING CAMP, PRESEASON, ROSTER CUTS, REGULAR SEASON, + 2 more phases), giving a third plausible reading.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:120-142`
  - fix: Label the header fraction with what it counts — "2/6 steps" — or move it onto the phase card next to "TRAINING CAMP" where its scope is unambiguous, and leave the panel header to the phase-level count that its wording promises.

- [ ] **Q-M293 · The three gap names live only inside the dismissed dialog; the Depth Chart opens on Offense with no marker on the tab that holds the holes**
  - evidence: camp_13 dialog names "Defense: Left OLB unassigned" and "Defense: Right OLB unassigned" (2 of 3 gaps are on Defense). camp_14 is the screen it navigates to: the Offense tab is selected and filled blue, and "Defense" and "Special Teams" carry no badge, count or warning glyph. `selectedTab` is hardcoded `= .offense` and `ShellDestination.depthChart` carries no target slot or side. The per-group "✓ 1/1" / "✓ 4/4" pills only appear one level deeper, inside the tab you are already on. cuts_01 has the same split ("Offense: Left Guard", "Offense: Right Tackle", "Defense: Free Safety").
  - code: `dynasty/dynasty/UI/Roster/DepthChartView.swift:19,316-345; dynasty/dynasty/UI/Career/CareerShellView.swift:615-617`
  - fix: Give `ShellDestination.depthChart` an optional target side and open on the tab holding the first gap. Add an amber count badge to each tab ("Defense ⚠2") derived from the same `depthChartGaps` the gate uses, and give the empty slot rows an amber border so they are findable by eye on a 12-position scroll.


### Depth chart after Auto-Set

- [ ] **Q-M294 · Two candidates at the same OVR give the depth chart nothing to break the tie, and the comparison sheet drops price entirely**
  - evidence: WR2 card: "STARTER Odalric Crisanti / WR Age 29 $0M — 79" over "BACKUP Kester Vandenberg / WR Age 28 $4M — 79". Identical rating, and Auto-Set's only sort key is `$0.overall > $1.overall`, so the order between them is arbitrary roster order. The row offers OVR, age and a (broken) salary and nothing else — no catch, speed, route or durability — and tapping into `ComparisonSheet` shows "Age / Nyr pro / versatility" but no salary at all, so the one screen where you might price a start decision has the number and the one where you compare two men does not.
  - code: `dynasty/dynasty/Domain/Models/Team/DepthChart.swift:321-380; dynasty/dynasty/UI/Roster/DepthChartView.swift:1095-1125`
  - fix: Add the two attributes that decide the slot to each row (a WR row should carry speed and catching; an OL row strength and awareness) — FM's squad screen and OOTP both key the list on position-relevant columns, not one aggregate. Carry salary into `ComparisonSheet` using `CommittedCapLedger.money`. Break Auto-Set ties on a deterministic secondary key (fewer years pro, then lower cap hit) so the same roster produces the same chart twice.


### Career hub (roster cuts)

- [ ] **Q-M295 · Position Battles prints the same surname on both sides of a one-man "battle"**
  - evidence: The tile reads "9 active" then "CB  Broadwater ......... Broadwater" and "DE  Frobisher ......... Frobisher" — competitor and leader are the same name. Only the third row, "DT  Bolliger vs Braithwaite ... Bolliger", is an actual matchup.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1352`
  - fix: loadPositionBattles keeps a battle when ANY competitor is still on the roster (`.filter { battle.competitorIDs.contains { rosterIDs.contains($0) } }`), then positionBattleRow builds `names` from `roster.prefix(2).map(\.lastName).joined(separator: " vs ")`. Once a competitor is cut or traded the battle collapses to one man and the row echoes him twice. Require at least two roster competitors, or resolve the battle in favour of the survivor when the field drops to one.

- [ ] **Q-M296 · The Lineup Incomplete alert names Auto-Set as the fix but does not offer it**
  - evidence: The alert body ends "Open the depth chart and assign them — Auto-Set fills every empty slot in one tap." The two buttons underneath are "Go to Depth Chart" and "Cancel". The one-tap fix the copy advertises costs a navigation plus a hunt for a button on the next screen.
  - code: `dynasty/dynasty/UI/Career/CareerShellView.swift:611`
  - fix: The message is built at CareerShellView.swift:344 and the alert at 611-621 offers only navigate/cancel. Add an "Auto-Set & Advance" destructive-free primary that calls the same DepthChart auto-fill the depth chart screen calls, then re-runs the advance — three unassigned slots on a 65-man roster is not a decision worth a screen change.

- [ ] **Q-M297 · Gold is doing eight jobs in the left rail, so the one gold thing that matters loses its voice**
  - evidence: In a single 300pt column, accentGold marks: the "DEBUG" label and its "Skip → Reg. Season" chip, the clipboard icon, "YOUR OFFSEASON", "PRESEASON" and its icon, the "NOW" pill, the month labels "Aug" / "Sep–Jan" / "Oct", the "Roster" chip on the Finalize depth chart row, the dotted in-progress bullet on "Evaluate young players", and the "Advance to Roster Cuts" button fill. The button — the only thing the player must press — is the tenth gold object down the column.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:596`
  - fix: Demote phase headers, month labels and the in-progress bullet to textSecondary/accentBlue and keep accentGold for the current phase marker and the Advance button only. The dotted gold in-progress bullet (taskStatusIcon, line 595-598) is also a third, unlegended state next to a red required dot and a hollow optional ring.

- [ ] **Q-M298 · Dead space: the task rail ends a quarter of the way up the screen and the Training Plan card is mostly empty**
  - evidence: The rail's last content is "+ 1 more phase" at roughly y=1515 of 2000; the remaining ~485px of the 300pt column is empty. In the right grid, the TRAINING PLAN card holds two lines — "Set focus" and "Tactical / Physical / Technical" — inside a card stretched to match the fully-packed OWNER card beside it, leaving ~140px of empty card below the text.
  - fix: Pin the phase list to the top and let the Advance button dock at the bottom of the rail rather than floating mid-column; and give the Training Plan card the content its own screen has (current focus weightings, weeks remaining, the intensity setting) instead of stretching two lines to fill a grid cell.


### Roster cuts — cut to 53

- [ ] **Q-M299 · Camp grade is painted accentGold for every grade, so a D reads as a highlight**
  - evidence: Nine rows carry "Camp D" in the same gold as the active ladder segment "3 CUT TO 53". An A+ would render in exactly the same gold at the same weight. On the screen whose whole job is separating keepers from cuts, the one evaluation the engine produced carries no visual signal. Same on cuts_02.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:291`
  - fix: `Text("Camp \(grade.displayLabel)").font(DSType.display(11, .heavy)).foregroundStyle(Color.accentGold)` is unconditional. Colour it the way OVR is coloured (Color.forRating is already in the row two lines above): green for A/A+, neutral for B/C, danger for D/F — and reserve gold for the ladder.

- [ ] **Q-M300 · Roughly 70% of every cut row is empty on a portrait iPad**
  - evidence: In each of the 14 rows the name lockup ends at about x=320 of 1500 and nothing appears again until the "+$1.0M / PS" stack at about x=1390. The ~1070px band between them is blank in every row, while the decision the screen exists for needs contract years, dead money, snaps and remaining depth at the position — none of which appear anywhere on the screen. Same on cuts_02.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:253`
  - fix: The row is HStack(name lockup) → Spacer() → VStack(money, PS). Fill the gap with the columns the engine already has: contract years remaining, dead cap on release, camp grade trend, and "N left at POS" from RosterCutEvaluator.positionImpacts — which is currently computed only for the confirm dialog.

- [ ] **Q-M301 · The row's only money figure is unlabelled, reads "+$0.0M" on half the list, and is always painted success green**
  - evidence: Seven of the 14 visible rows show "+$0.0M" (Littlefield, Bonaventure, Crisanti, Lovegrove, Vestergaard, Bolliger, Bascomb) in the same green as Abernathy's "+$25.3M". There is no column header, no legend and no dead-money figure anywhere in the list, so the reader cannot tell whether "+$0.0M" means "free to cut" or "saves nothing". Same on cuts_02.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:314`
  - fix: `.foregroundStyle(Color.success)` is unconditional while capSavings is explicitly signed — CapManagementEngine.swift:436 defines it as `salaryRelieved + proratedPerYear - deadCap` and line 707 comments "capSavings is signed: a negative value…". A release that costs cap space would render "−$2.0M" in success green. Colour by sign, label the column "CAP SAVED", and print the dead-money half beside it — the confirm dialog and the result sheet both already carry it, only the row where the decision is made does not.


### Lineup Incomplete dialog

- [ ] **Q-M302 · Position battle rows print surnames only, and the same screen proves surnames collide in this league**
  - evidence: cuts_01 POSITION BATTLES row: "DT  Bolliger vs Braithwaite     Bolliger ›". Two cards away on the same screen: "MVP  Wade Braithwaite  93", and the CONTRACTS card lists him as "WR Braithwaite 93 $54.0M". Battles are grouped strictly by `$0.position`, so the DT competitor is provably a different man — but the tile renders `\.lastName` in both the matchup string and the leader chip and has no way to say so. camp_14 confirms surname collisions are normal here: "Kaleo Hinsdale / QB Age 25" and "Alonso Hinsdale / WR Age 29" on the same roster.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1399,1412; dynasty/dynasty/Engine/Camp/PositionBattleTracker.swift:54`
  - fix: Use first-initial + surname ("T. Braithwaite") whenever more than one roster player shares a surname — the check is a one-line `players.filter { $0.lastName == p.lastName }.count > 1`. The row already has horizontal room: "Bolliger vs Braithwaite" does not truncate.


### Draft — pick result

- [ ] **Q-M303 · The header's "NEEDS · MY TOP 20" strip reads all zeros by round 2 and never says what the number counts**
  - evidence: 080 (pick #19, the user's FIRST card): "NEEDS · MY TOP 20  DE 0  QB 1  WR 0  OLB 0  DT 0" — four of five positions already zero. 084 (pick #35): identical. draft_01 (pick #52): "DE 0  QB 0  WR 0  OLB 0  DT 0" — five zeros, and it will stay five zeros for the remaining five rounds. Nothing on any of the three screens explains what the digit beside "DE" is; it could equally read as a need score, a count drafted, or players left at the position.
  - code: `dynasty/dynasty/UI/Draft/Components/DraftStickyHeader.swift:788, :818, :840`
  - fix: `boardPressure` counts available prospects whose `userBoardRanks[id] <= pressureDepth`, with `pressureDepth` hard-coded to 20. The doc says the number decides "trade up or sit", but a fixed top-20 is exhausted before the user's second card, so the strip stops answering anything after round 1. Scale the depth with the current pick (e.g. `max(20, currentPickNumber + 20)`), or switch to "men left at this position inside your board" — and put the unit in the label ("LEFT IN MY TOP 20") so the bare digit is readable without the manual.

- [ ] **Q-M304 · The pick grade ignores your own scouting board: the same card reads "A+", "MY #101" and "−50 REACH" with no key**
  - evidence: draft_01's pick card: green "A+" chip top-right, "#51 HOU YOURS", "Jace Winchester K Age 23 · Duke", "SCOUTS B−/A", then "MY #101" beside an amber "−50 REACH". Directly below, the feed calls the same pick "HOU steal K J. Winchester — 32 slots of value". Three verdicts on one pick — A+, steal, and a 50-slot reach — with nothing on the card saying which board each is measured against. Compare 084, where the identical layout reads "MY #32 · ON SLOT" and is coherent.
  - code: `dynasty/dynasty/Engine/Draft/PickGradeCalculator.swift:8; dynasty/dynasty/UI/Draft/Components/DraftTickerPanel.swift:2542`
  - fix: `PickGradeCalculator.Inputs` takes `valueDelta` (media window), `needScore`, `publicOVR` and `schemeFit` — the user's own board rank never enters it, so the grade can hand out an A+ on a man the club's own scouts rank 82 slots lower. Either feed `userBoardRanks` into the grade for the user's own picks, or label the two frames explicitly on the card ("MEDIA A+ · YOUR BOARD −50"). As it stands the grade rewards the user for ignoring the scouting department he spent the whole spring paying for.


### Preseason — training focus

- [ ] **Q-M305 · Surname collisions across the roster: three Tanguays, two Frobishers, two Hinsdales — with two of each pair on adjacent rows**
  - evidence: pre_02 lists "Roman Frobisher (FS)" and "Zavier Frobisher (DE)" as consecutive rows, plus "Brixton Tanguay (MLB)" and "Hayden Tanguay (FS)" seven rows apart. pre_04/pre_05 add "Osman Tanguay (RT)" and "Kaleo Hinsdale (LG)" against pre_02's "Alonso Hinsdale (WR)"; "Callum Derringer (TE)" and "Callum Ackerly (LG)" repeat the given name. `RandomNameGenerator.uniqueName` only guarantees the FULL name is unused (`used.insert("\(first) \(last)")`, RandomNameGenerator.swift:104-107) against a 55 × 55 pool, and the seeded league JSON draws from the same 55 surnames, so surnames repeat freely on one 75-man roster. Any abbreviated reference ("Tanguay makes the tackle") is ambiguous three ways.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:100-118`
  - fix: Track surnames per team as well as full names — reject a surname already on the roster unless the pool is exhausted — and grow `lastNames` well past 55 so a 32-team, 2,700-player league is not drawing from a 3,025-pair space.

- [ ] **Q-M306 · The four preset chips are ~24pt tall — well under the 44pt touch minimum, and half the height of the app's own filter chips**
  - evidence: "Balanced", "Scheme Heavy", "Camp Hard", "Recovery Mode" are built as `.font(.caption.weight(.semibold))` + `.padding(.vertical, 6)` inside `.buttonStyle(.plain)` with no `contentShape` or minimum frame (TrainingPlanView.swift:141-156) — roughly 11pt of text plus 12pt of padding. Measured on the screenshot the chips span ~35 display px of 2000 ≈ 24pt. The roster's own `filterPicker` chips on pre_04 use `.padding(.vertical, 12)` and land near 44pt, so the two chip styles disagree inside one app.
  - code: `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:136-156`
  - fix: Raise vertical padding to 12 and add `.contentShape(RoundedRectangle(...))` with `.frame(minHeight: 44)`, matching `filterPicker`. While there, give each preset a one-line gloss ("Camp Hard — pads on, stamina and durability") so the names are not opaque on first contact.

- [ ] **Q-M307 · Two of the workload table's three columns carry a single value — STATE is "LIGHT" on all 12 rows and INJ is "4% inj" on 11 of 12**
  - evidence: Every visible row reads the same "LIGHT" pill; the INJ column reads "4% inj" for Laurelwood, Hinsdale, Larrabee, Hubbell, B. Tanguay, Klingman, Smallwood, R. Frobisher, Z. Frobisher, H. Tanguay and Littlefield, and "5% inj" only for Seneca Crisanti. The arithmetic makes that inevitable: `injuryRiskPct` = 0.04 × `status.injuryMultiplier` × durabilityFactor, `.underloaded` and `.healthy` both multiply by 1.0 (CampEnums.swift:24-25), and durabilityFactor spans just 1.0→1.4, so with nobody overloaded the column can only ever print 4%, 5% or 6%. The comment at TrainingPlanView.swift:369 claims the engine formula was adopted "otherwise every player reads an identical 4% inj" — on screen it still does.
  - code: `dynasty/dynasty/Engine/Camp/WorkloadEngine.swift:146-151; dynasty/dynasty/Domain/Enums/CampEnums.swift:22-29`
  - fix: Print one decimal (4.2% / 5.6%) so durability differences are legible, or replace the percentage with the delta the decision actually turns on — projected risk under the plan you are about to save versus the current plan.


### Roster cuts — cut to 65

- [ ] **Q-M308 · Name generator collides constantly on a roster you must identify men by name — two adjacent rows both read "Callum" with initials "CA" and "CB"**
  - evidence: pre_03 rows 13-14 are "CA · MLB Callum Abernathy" immediately above "CB · DE Callum Bonaventure". Across the three screens, ~24 distinct men produce eight shared-name pairs: Roman/Zavier Frobisher, Brixton/Hayden Tanguay, Alonso/Kaleo Hinsdale, Seneca/Odalric Crisanti, Odalric Smallwood/Odalric Crisanti, Norbert Vestergaard/Norbert Bascomb, Zavier Frobisher/Zavier Lovegrove, Callum Abernathy/Callum Bonaventure.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:31-80 and :91-123; dynasty/dynasty/Data/Import/LeagueGenerator.swift:656`
  - fix: LeagueGenerator.swift:656 builds the whole ~2880-player league with the plain colliding RandomNameGenerator.randomName(); only DraftClassBuilder uses the deduplicating uniqueName(used:). With 55 first × 55 last names, a single 75-man roster expects ~50 surname collisions. Route the league generator through uniqueName with a league-wide `used` set, and widen both pools.

- [ ] **Q-M309 · Position filter chips carry no counts, so the positional minimums the engine enforces are invisible until a row is locked**
  - evidence: The filter row reads "All | QB | RB / FB | WR / TE | OL | DL | LB | DB | ST" with no number on any chip. The floors are real and enforced — pre_17's Kaleo Hinsdale row is dimmed with "You must carry 2 QBs — sign or trade for another first" — but you only discover a floor by hitting it 60 rows into the list.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:204-236; RosterCutEvaluator.swift:143-172`
  - fix: Put "count / minimum" on each chip ("QB 2/2", "OL 11/5") and tint a group at its floor. The data already exists: RosterCutEvaluator.positionImpacts returns after/minimum per room and the view already calls it for the confirm dialog.

- [ ] **Q-M310 · An unexplained "PS" chip sits on all 75 rows in a ~33×19pt touch target, and what it means is only explained after you commit**
  - evidence: Every row on all three screens carries a small grey "PS" chip under the cap figure. Nothing on the screen expands the abbreviation. The only explanation appears in the post-commit sheet — "PRACTICE SQUAD / flagged" and "a flagged man can still be claimed off waivers before you sign him" — after the decision is irreversible.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:317-338`
  - fix: The chip is a real toggle (togglePracticeSquad) whose flag is genuinely consumed by PracticeSquadEngine.userFlaggedKeepers, so it is not a fake affordance — but it is 11pt text with 3pt vertical and 8pt horizontal padding, roughly 33×19pt, well under the 44pt minimum, and stacked 2pt under the cap number. Grow the hit area to 44pt (contentShape/frame without growing the visual chip), label it with a legend above the list, and show a running "n flagged" count in the action bar so the flag has feedback before commit.

- [ ] **Q-M311 · Roughly 60% of every row is empty on a portrait iPad while the numbers the cut decision needs are missing**
  - evidence: On all three screens the name/meta block ends around "Camp D" and the next ink is the cap figure hard against the right edge — e.g. the Brixton Tanguay row runs "MLB Brixton Tanguay / OVR 78 Age 27 Camp D" then ~600pt of nothing then "+$1.5M / PS". Fifteen rows repeat the same void. Meanwhile dead money, contract years remaining, depth-chart rank at his position, and injury status appear nowhere on the screen.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:311-339`
  - fix: A single Spacer separates the two columns. Fill the gap with the columns a cut is actually made on — dead money left behind (the engine already computes it per player via releaseCapSplit), years left, and depth rank at position — as right-aligned mini-columns so the whole list is scannable down each axis, FM-squad-screen style.

- [ ] **Q-M312 · Type scale is inverted for the screen's job — the name you already know is the largest text, the numbers you decide on are all 11pt**
  - evidence: "Isaias Laurelwood" is set at body semibold while "OVR 89", "Age 24" and "Camp C" are all 11pt, and "Age 24" is additionally tertiary grey. The eye hits the name first, the OVR second only because it is coloured, and Age/Camp last — the reverse of the order a cut decision needs.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:278-294`
  - fix: Rows 278-294 use DSType.Size.body semibold for fullName and a flat DSType.display(11) for OVR, Age and Camp. Raise OVR to at least footnote weight-heavy, keep Camp at the same step as OVR since it is a peer signal, and drop the name half a step. Keep the position badge as-is.

- [ ] **Q-M313 · Camp grade is simply absent on a third of the rows with no placeholder, so "no grade" is indistinguishable from missing data**
  - evidence: On pre_03, Alonso Hinsdale, Barrett Hubbell, Zavier Frobisher, Wade Littlefield and Callum Bonaventure show "OVR nn  Age nn" and then nothing, while the rows around them show "Camp D". Same on pre_17 for Wade Littlefield, Callum Bonaventure, Odalric Crisanti, Zavier Lovegrove, Jamari Bolliger and Norbert Bascomb. Every one of those rows also happens to read "+$0.0M", which makes the blank read as a data hole rather than a fact.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:290-294`
  - fix: Line 290 is `if let grade` with no else branch. Render an explicit muted "Camp —" (accessibility label "no camp grade") so the absence is a stated fact. Worth also confirming which acquisition paths leave campGrade nil — WeekAdvancer.swift:8766 is the only site that ever writes it and nothing ever clears it, so a player acquired after camp shows blank while a returning player would show last season's letter.

- [ ] **Q-M314 · The one number on the right reads "+$0.0M" in success green on a third to half the list, and never shows the dead money**
  - evidence: pre_03 shows "+$0.0M" in green for Alonso Hinsdale, Barrett Hubbell, Zavier Frobisher, Wade Littlefield and Callum Bonaventure — 5 of the 14 full rows. pre_17 shows it for 7 of 15 (Wade Littlefield, Callum Bonaventure, Odalric Crisanti, Zavier Lovegrove, Norbert Vestergaard, Jamari Bolliger, Norbert Bascomb). Yet the same commit reports "DEAD MONEY $3.5M stays on the books" — money no row ever showed.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:313-316 and :733-740`
  - fix: money() formats %.1fM so every sub-$50K saving collapses to "+$0.0M", and capSavingsLabel always prefixes "+" while line 316 always paints Color.success — even though ReleaseCapSplit.capSavings is explicitly documented as able to go negative. Format small values as "<$0.1M" or the exact thousands, drop the "+" and the green when the value is zero, paint negatives in danger, and add the per-player dead-cap figure beside it.


### Preseason — depth chart

- [ ] **Q-M315 · "CUTDOWN PENDING +22 — 22 players over the 53-man active roster" is the most urgent thing on the screen and cannot be tapped**
  - evidence: The banner is a bare `HStack` inside `RosterSummaryBar` — no `Button`, no `NavigationLink`, no `onTapGesture` (RosterSummaryBar.swift:233-266). It names a mandatory action and offers no route to it; the cut tool (`RosterCutView`) lives elsewhere. Directly below it the summary bar reads "75 / 90  Players · offseason", so a reader who does not know the rules sees "75 of 90, room to spare" one line under "22 over the limit". Same on pre_05.
  - code: `dynasty/dynasty/UI/Roster/RosterSummaryBar.swift:233-266`
  - fix: Make the banner the primary action — a tappable row with a trailing chevron and the words "Cut to 53" that pushes RosterCutView — and gloss the two ceilings on the same line ("90 allowed now · 53 by cutdown day").

- [ ] **Q-M316 · Contract years are printed twice on every row, in two different colour languages**
  - evidence: Each row carries an "EXT Ny" chip beside the name and an "Nyr" badge in the right-hand columns, always the same number: Laurelwood "EXT 1y"/"1yr", Larrabee "EXT 2y"/"2yr", Nadeau "EXT 3y"/"3yr", Osman Tanguay "EXT 4y"/"4yr" — 12 of 12 visible rows. Both read `player.contractYearsRemaining` (`extensionSlot`, PlayerRowView.swift:256; `contractYearsLabel`, PlayerRowView.swift:768) and both colour-code it independently (orange `.warn` chip vs. filled gold badge), so an expiring deal raises two different alarms for one fact. The file's own comment eight lines above `contractYearsLabel` cites "§2.2's 'one encoding per quantity, never both'" as the reason another badge was removed. Same on pre_05.
  - code: `dynasty/dynasty/UI/Roster/PlayerRowView.swift:256 and :768`
  - fix: Drop the EXT slot from the Overview lens (keep it in Contracts, where it is the subject) or drop the "Nyr" column, and free the space for the potential number the ↗ glyph is currently compressing.

- [ ] **Q-M317 · Every list row leaves a 37-58% wide empty gutter between the name and the first number**
  - evidence: On pre_04 the identity block ends at "Instinct" around x≈440 of 1500 and the first value ("24") starts at x≈1005 — ~550px, 37% of the screen width, empty on all 12 rows, while eight columns are crushed into the right third. On pre_02 it is worse: "Isaias Laurelwood / OVR 89" ends around x≈290 and the LOAD meter starts at x≈1165, ~58% of the width dead. Root cause: `DSListRow` gives the identity block `.frame(minWidth: identityMin, maxWidth: .infinity, alignment: .leading)`, so it absorbs all slack and left-aligns inside it — fine on iPhone, a canyon on a 13" portrait iPad. Same on pre_05.
  - code: `dynasty/dynasty/UI/Common/DSListRow.swift:636`
  - fix: On the wide layout, spend the slack: widen the numeric columns and add the two facts the Overview lens keeps one tap away (numeric potential, cap % trend), or cap the identity block and centre the row content so the gutter is split rather than pooled in one place.

- [ ] **Q-M318 · Two near-identical golds carry six unrelated meanings on one screen**
  - evidence: Pixel-sampled from the screenshot: `warning` (234,179,8) paints the roster count "75 / 90", the "CUTDOWN PENDING" alert, and average-tier ratings "OVR 68" / "OVR 63"; `accentGold` (201,169,78) paints the cap figure "$187.1M" and the "Key FA pending" chip. The two hues are 33 RGB points apart and read as one colour at 11pt on the dark ground, so "you are 22 men over the limit", "this guy is mediocre" and "this is the money number" all shout in the same voice. pre_02 spends the same gold a fourth and fifth way — the "PRESEASON FOCUS" ident and the Technical slider tint — next to gold OVR values (63, 68, 65, 62).
  - code: `dynasty/dynasty/UI/Common/Theme.swift:25 and :49; :123-131`
  - fix: Reserve amber strictly for "needs your attention" (cutdown, expiring, over-limit) and move the average-rating tier to a neutral grey-blue; keep `accentGold` for emphasis/identity only, or merge the two tokens so the app has one gold with one job.


### Preseason — young players

- [ ] **Q-M319 · Potential — the number this screen's task turns on — is one 5-bucket arrow glyph sitting next to a second, different arrow glyph**
  - evidence: Rows read "24 ↑ 89 ★", "31 → 81 ↑↑", "28 ↑ 79 ↑↑", "25 ↑ 78 ↑↑", "25 ↑ 68 ↑↑", "24 → 65 ↑↑". The glyph before OVR is `developmentArrow` (form, header "Frm") and the glyph after is `shortPotentialLabel` (true potential, header "↗") — two adjacent 20-24pt columns drawing from overlapping arrow vocabularies, with neither header on screen. Potential is bucketed into ★/↑↑/↑/→/↓ (PlayerRowView.swift:826-836), so Bascomb (78 OVR, age 25), Nadeau (68, 25) and Osman Tanguay (65, 24) all read "↑↑" and cannot be ranked — on a screen whose job is "evaluate young players".
  - code: `dynasty/dynasty/UI/Roster/PlayerRowView.swift:815-836`
  - fix: Use non-colliding marks (a filled ceiling bar or the numeric potential band "82-88" for potential; a small delta chip "+2" for form), and surface the numeric potential in the Overview lens rather than only under the Development chip.

- [ ] **Q-M320 · "S: B+ / D: C" is the biggest type in the group header and nothing on screen says what it is or how it was derived — and the tap it invites opens something else**
  - evidence: The Offensive Line header prints "S: B+ / D: C" at title3-black weight beside "$45.8M", "5/15", "6 exp", "Key FA pending" and "Review". Nowhere is S/D expanded, the inputs are not shown, and the whole header is a `Button` that opens the group-assessment sheet (RosterView.swift:686-696) — i.e. it asks for YOUR opinion rather than explaining the engine's. The grade comes from `PositionGradeCalculator.calculatePositionGrades` over the scheme's starter count, but the reader is given no starter average, no depth average and no scheme context to reconcile with the visible OVRs (89/87/87/81/79 starters, 78/68/65/63/63/62/62 behind them). Same on pre_04.
  - code: `dynasty/dynasty/UI/Roster/RosterView.swift:686-696, :1738-1755`
  - fix: Expand the labels ("Starters B+ · Depth C") and put the arithmetic one tap away — a popover naming the starter OVR average, the depth average, the scheme's required starter count and which man is dragging the grade down. Keep the assessment editor on a separate explicit control.


### Preseason — slate

- [ ] **Q-M321 · The selection control is a blank rectangle — unselected rows render an empty chip, not a radio button**
  - evidence: The left column of the picker shows two dark empty rounded rectangles ("Rest the starters", "Full tilt") and one gold rectangle containing a ~4px dot ("A series for the ones"). No radio ring, no checkmark, no border. Code: PreseasonView.swift:277-281 — `DSRowBadge(text: isSelected ? "\u{2022}" : " ", tint: isSelected ? .accentGold : .backgroundTertiary)` with `affordance: .none` — the unselected badge is literally a space character on a dark chip. A first-time player scanning the screen has one colour cue and no shape cue for what is currently chosen, and the empty chips read as disabled buttons.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:277`
  - fix: Use a real radio glyph pair (`circle` / `largecircle.fill.circle`) or `checkmark.circle.fill` vs an outlined circle, so selection is legible in shape as well as colour. VoiceOver is already correct ("Selected"/"Not selected") — only the visual is missing.

- [ ] **Q-M322 · "10 still to release before the phase closes." names an obligation with no route to it on this screen**
  - evidence: The card states, in alert orange, "10 still to release before the phase closes." beside "On the roster 75 / Season opens at 65". The card is a plain `HStack` in `cardBackground()` (PreseasonView.swift:340-372) — not a Button, no chevron, no tap target. The push to roster cuts exists and is non-nil throughout (CareerShellView.swift:2119 supplies `onOpenRosterCuts`), but PreseasonView only wires it into the `.complete` stance action bar (PreseasonView.swift:645-653). So during all three planning steps the player is told what he must do and given only "Play game 1" to do.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:363`
  - fix: Make the roster-standing card tappable to `onOpenRosterCuts` (it is already passed in), or add a secondary "Roster cuts" button to the planning action bar — DSActionBar's fixed order already has a secondary slot, and the primary commit stays "Play game n".

- [ ] **Q-M323 · Gold is doing four jobs on one screen, including the one P5 explicitly bans (section-header colour)**
  - evidence: Gold appears as: (1) the band's current-slat top rule, (2) the "GAME 1 OF 3" card eyebrow, (3) the selected policy row's chip, (4) the action bar's rule + "WHAT THIS COSTS" title + the "Play game 1" fill. UI_REDESIGN_VISION.md:236-240: "Gold has exactly three jobs and no others: (1) the primary commit fill, (2) the current-step marker on a band, (3) the live/now indicator... It is *not* the section-header colour — iteration 1 made it one and immediately had seven golds on a screen... Section heads are textSecondary, tracked, 11 pt." The card eyebrow is `DSType.display(11, .heavy).tracking(0.7)` in `Color.accentGold` (PreseasonView.swift:220-223) — the exact section-head shape, in the banned colour — while "Who dresses" 60px below is the identical 11pt tracked head correctly in `textSecondary` (PreseasonView.swift:253-256). Two identical section heads, two different colours, on one screen.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:222`
  - fix: Recolour the card eyebrow to `textSecondary` (or delete it per the previous finding) and give the selected-row marker a non-gold treatment (a filled checkmark in `textPrimary`, or the row's own selected surface tint), leaving gold to the band's current slat and the single commit.

- [ ] **Q-M324 · The install pill is flat blue on all three options while the risk pill ramps green/orange/red — the colour scan says only risk varies**
  - evidence: Right-hand column: "NO STARTER RISK" (green) → "PART STARTER RISK" (orange) → "FULL STARTER RISK" (red). Left-hand column: "NO FIRST-TEAM INSTALL", "PART INSTALL", "FULL INSTALL" — all three in the same blue. So the benefit axis reads as constant and only the cost axis as varying, which biases the eye straight to "Rest the starters" (the only green thing on the screen). Code: PreseasonView.swift:322 hardcodes `tone: .info` for `familiarityNote`, while :323 uses `policy.riskTone`, which ramps `.ok/.warn/.bad` (PreseasonRecapSheet.swift:429-435).
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:322`
  - fix: Give `familiarityNote` its own tone ramp mirroring `riskTone` in the opposite direction (no install = bad/neutral, full install = ok), so the two pills read as the two sides of one bet. Keeping both axes flat-neutral would also be defensible; what is not defensible is colour-ramping one and not the other.

- [ ] **Q-M325 · The stage count is printed three times on one screen, against the flow band's own documented rule**
  - evidence: Within 170px vertically: the band head prints "PRESEASON · GAME 1 OF 3", the meter beside it prints "0 spent · 3 left", and the card below prints "GAME 1 OF 3" again — in gold, i.e. at HIGHER emphasis than the authority. PreseasonFlowBand.swift:12-15 states the rule being broken verbatim: "UI_REDESIGN_VISION §2.1's rule that a process prints its stage count exactly once is why the head owns 'GAME 2 OF 3' and no screen underneath repeats it. The band is the only component allowed to say where in the slate the club stands." The repeat is PreseasonView.swift:219. UI_REDESIGN_VISION.md:339 calls out the same defect elsewhere ("today draft prep prints its stage count three times on one screen"). Separately the word "Preseason" appears twice in 80px (nav title + band headline), and the meter's unit ("preseason games") only reaches VoiceOver — on screen "0 spent · 3 left" says spent-what.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:219`
  - fix: Delete the "GAME n OF 3" eyebrow from `gameCard` and let the opponent be the card's headline (the band already carries position). Same repeat exists at PreseasonView.swift:400 in `reviewHeader`. Append the unit to the meter's value line so it reads "0 of 3 games played".

- [ ] **Q-M326 · The commit has no busy state and no failure state — the "Playing…" label is unreachable dead code**
  - evidence: The primary button reads "Play game 1" on all three shots. Its busy variant can never render: `playGame` (PreseasonView.swift:705-733) is a synchronous main-actor function that does `isSimulating = true` then `defer { isSimulating = false }`, so SwiftUI never draws a frame in between — `title: isSimulating ? "Playing\u{2026}" : "Play game \(currentGame)"` (:626) and `isEnabled: !isSimulating` (:627) are both unreachable, while a full `GameSimulator.simulate` run blocks the main thread. Worse, three guards abandon the tap silently: `guard !isSimulating, let current = flow else { return }`, `guard let matchup = ... else { return }`, `guard let result = PreseasonEngine.simulateGame(...) else { return }` — if the sim returns nil the button is pressed and absolutely nothing happens, no sheet, no message, no state change.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:705`
  - fix: Make `playGame` async (or hop through `Task { @MainActor in }` after setting the flag) so the disabled "Playing…" state actually paints, and replace the bare `else { return }` on the simulate call with a visible failure — an inline error in the action bar's explainer (`isWarning: true`) saying the exhibition could not be played.


### Preseason — game 1

- [ ] **Q-M327 · "Who moved" lists six men while the same screen twice says five moved**
  - evidence: pre_08's "Who moved" card lists 6 rows — Davion Maddocks (QB), Brixton Yarborough (RB), Wade Braithwaite (WR), Odalric Goddard (TE), Wade Tanguay (DT), Kwabena Winchester (WR) — while the card above says "4 helped their case, 1 hurt his." and the sheet says "4 of the men fighting for a spot helped their case and 1 hurt his." The tape confirms only 4 HELPED chips (Maddocks, Goddard, Tanguay, Winchester) plus Yarborough HURT. The sixth, Braithwaite, is a projected starter: `movers` filters all `lines`, but `helpedCount`/`hurtCount` filter `cutCohort`, which excludes starters. The tier pill that would explain it ("Starter") is the one thing on his row hidden behind the sheet.
  - code: `dynasty/dynasty/UI/Camp/PreseasonRecapSheet.swift:276-279 (movers, all lines) vs :266-267 (counts, cut cohort only)`
  - fix: Say the split in the card header — "4 helped their case, 1 hurt his, and 1 starter moved" — or group the movers card into "Fighting for a spot" and "The ones" so the arithmetic is visibly two lists, not one broken one.

- [ ] **Q-M328 · A red "HURT" pill sits directly under an "INJURIES 0 — none among the ones" chip and means something completely different**
  - evidence: pre_08: the sheet's chip row reads "INJURIES / 0 / none among the ones", and the "Who moved" row immediately below shows "RB Brixton Yarborough — 2.7 a carry on 46 carries" tagged with a red "HURT" pill. pre_10 has the same collision: "HURT 2 / played themselves down" as a chip, and red "HURT" pills on Kaleo Hinsdale and Odalric Crisanti, neither of whom is injured. In code `Verdict.hurt.pillLabel == "Hurt"` with `.bad` tone, while an actual injury is a separate 10 pt `cross.case.fill` glyph next to the name.
  - code: `dynasty/dynasty/UI/Camp/PreseasonRecapSheet.swift:57-58, :68, :87 (Hurt verdict pill) vs :557-566 (Injuries chip)`
  - fix: Rename the verdict pill so it cannot be read as a medical status — "Slipped", "Down", or "Case ↓". The verdict column already has the word "CASE" as its header; use that vocabulary in the pill.

- [ ] **Q-M329 · The "On the bubble" tab and the "BUBBLE" standing pill on its own rows mean two different things**
  - evidence: pre_08 with "On the bubble" selected, the STANDING column reads CAMP for Maddocks, Goddard, Winchester, Klingman and Vestergaard, and BUBBLE for only Tanguay and Derringer. pre_10, same tab: CAMP for Alonso Hinsdale, Elias Klingman and Odalric Goddard, BUBBLE for the rest. The tab is `recap.cutCohort` = everyone whose `Tier.isCutCohort` is true (`self != .starter`, so camp bodies and rookies included), while `Tier.bubble.pillLabel` is the literal string "Bubble". A reader is told these seven men are "on the bubble" and then told five of them are not.
  - code: `dynasty/dynasty/UI/Camp/PreseasonRecapSheet.swift:205 (isCutCohort), :610 (tab label), :182 (Bubble pill label)`
  - fix: Rename the tab to what it filters — "Fighting for a spot" or "Cut sheet" — and keep "Bubble" as the standing value only. The two-tab lens is otherwise the right control.

- [ ] **Q-M330 · The screen's core vocabulary — "the ones", "on the bubble", "camp", "FAM" — is never defined anywhere on it**
  - evidence: pre_08 uses "the ones" three times without ever saying it means the first team: eyebrow "GAME 1 · A SERIES FOR THE ONES", chip context "none among the ones", cost line "The ones who opened banked +2 scheme familiarity". The tape header column reads "FAM" — the phrase "scheme familiarity" appears only inside the sheet, which the player has to dismiss to reach the column. Standing values "CAMP" and "BUBBLE" and case values "HELD" and "QUIET" are all unexplained four-letter chips, and "the cut to 65" appears with no indication of where the roster stands today.
  - fix: Spell it out once per screen: "the ones (your projected starters)" on first use, "FAM · scheme familiarity gained" as the column header or a tappable legend, and put the live roster count next to "the cut to 65" so the target has a distance.

- [ ] **Q-M331 · Roughly 30% of a portrait 13-inch iPad is a dead black gutter, and the page is pinned left while the title and sheet are centred**
  - evidence: On all three screens every card stops at the same vertical edge (~x=1024 of the 1500 px render) and nothing is drawn to the right of it for the full ~1800 px height of the scroll. The "Preseason" nav title is centred at x=750 and the recap sheet is centred at x=750, so the header, the modal and the body disagree about where the page's axis is. Cause is `.frame(maxWidth: DSLayout.contentMeasure, alignment: .leading)` with `contentMeasure = 720` inside a 1032 pt window, then `.frame(maxWidth: .infinity, alignment: .leading)`.
  - code: `dynasty/dynasty/UI/Common/Theme.swift:203 (contentMeasure = 720); dynasty/dynasty/UI/Camp/PreseasonView.swift:200-203`
  - fix: On a regular-width portrait iPad, either centre the 720 pt measure so the gutter is symmetric, or put the gutter to work: a fixed right rail carrying the cut ladder (90 → 65) and a live position-count tally is the number the whole phase is driving toward and it is currently on no screen at all.


### Preseason — game 2

- [ ] **Q-M332 · The bubble denominator drops from 54 to 53 between consecutive games with 0 injuries and no cuts**
  - evidence: pre_08 sheet: "HELPED 4 / of 54 on the bubble" and "INJURIES 0 / none among the ones". pre_10 sheet, the very next game: "HELPED 1 / of 53 on the bubble", again "INJURIES 0 / none among the ones", while the bottom bar states "Nothing here is locked until the slate is done" — i.e. no roster move happened. The chip's context is `"of \(recap.cutCohort.count) on the bubble"`, and `cutCohort` is `lines.filter { $0.tier.isCutCohort }` where `lines` is built from `result.userLines` — non-starters who appeared in THIS game's box score, not a roster count. So the denominator drifts game to game for reasons the screen never states, and it also includes ~40 men shown as "No stat line" who could not have helped.
  - code: `dynasty/dynasty/UI/Camp/PreseasonRecapSheet.swift:547 (chip context) and :264 (cutCohort), :258 (lines built from userLines)`
  - fix: Make the denominator the roster fact it claims to be — the actual count of non-starters on the 90 — and hold it fixed across the slate, or relabel it "of 54 who got a snap".

- [ ] **Q-M333 · Surname collisions all over the cut sheet — three Tanguays, two Crisantis, two Hinsdales, two Braithwaites**
  - evidence: pre_10 alone: "MLB Brixton Tanguay" and "FS Hayden Tanguay" in the same 12 visible rows, plus "DT Wade Tanguay" on pre_08 — three Tanguays on one roster. Also "WR Odalric Crisanti" (Who moved) and "CB Seneca Crisanti" (tape); "QB Kaleo Hinsdale" and "WR Alonso Hinsdale"; "DT Sincere Braithwaite" here and "WR Wade Braithwaite" on pre_08. First names repeat as hard: Wade ×3 (Braithwaite, Tanguay, Vandenberg), Elias ×2 (Klingman, Derringer), Brixton ×2 (Yarborough, Tanguay), Odalric ×2 (Goddard, Crisanti). The pool is 55 surnames and `uniqueName` dedupes only the concatenated full name (`used.insert("\(name.first) \(name.last)")`), so a 90-man roster drawn from 55 surnames collides constantly.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:66-77 (55 surnames) and :102-119 (uniqueness on full name only)`
  - fix: Add a per-club surname budget to the generator (at most one, or one plus a deliberate rare pair) and a per-club given-name cap. This screen's entire job is a list of names the player must tell apart before cutting them.


### Preseason — game 3

- [ ] **Q-M334 · The band never shows the score of the game you are currently reading — GAME 2 has no "L 14–40" on the very screen printing 14–40**
  - evidence: pre_12_game3.png: the band reads "✓ GAME 1 / W 44–27" then "2 GAME 2 / Read the tape before the next one" — no result — while the card 300 px below reads "14–40 at Detroit (L)". pre_12_game3_result.png: "✓ GAME 1 / W 44–27", "✓ GAME 2 / L 14–40", "3 GAME 3 / Read the tape before the next one" — again no score, while the card below reads "22–9 vs Pittsburgh (W)" and the meter says "3 spent · 0 left". Cause: `secondLine` returns the outcome only when the slat is `.done`; a `.current` slat always falls through to the subcaption (DSSlatBand.swift:726). `PreseasonFlowBand.slats` does pass `outcome: outcomes[game]` for the current game, so the data is there and is being discarded. The band is the screen's result ledger and it is permanently one game stale.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:726`
  - fix: In `secondLine`, prefer the outcome whenever one exists regardless of state, or let `DSSlat` carry both and render "L 14–40 · read the tape" on a current slat that has a result. A played-but-current step is a real state and the band should not pretend the game has no score.

- [ ] **Q-M335 · Surnames and first names repeat all over one roster — three surname pairs and two first-name pairs visible in a single viewport**
  - evidence: pre_12_game3.png alone: Kaleo Hinsdale (QB) in "Who moved" and Alonso Hinsdale (WR) in the table; Odalric Crisanti (WR) in "Who moved" and Seneca Crisanti (CB) in the table; Brixton Tanguay (MLB) and Hayden Tanguay (FS) four rows apart; plus repeated first names Odalric Crisanti / Odalric Goddard and Elias Klingman / Elias Derringer. pre_12_game3_result.png adds Roman Frobisher (FS) in "Who moved" against Zachariah Frobisher (CB) in the table, and Brixton Yarborough against Brixton Tanguay. `RandomNameGenerator` holds 55 first names and 55 last names (verified by parsing the arrays), and `uniqueName` dedupes only the concatenated full string (RandomNameGenerator.swift:102-124) — nothing constrains surname reuse within a club. At ~2400 league players against 55 surnames, every surname recurs ~44 times league-wide and ~1.4 times per 75-man roster by pigeonhole. On a screen where the player is releasing 10 men, "Frobisher" naming two different defensive backs is a live confusion risk.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:102`
  - fix: Grow the pools (300+ surnames is the usual floor for a sports sim) and add a per-team constraint to `uniqueName`: reject a surname already on the drafting club unless the pool is exhausted. Cheap, and it is the difference between a league that reads as real and one that reads as generated.

- [ ] **Q-M336 · The QUIET chip measures 3.69:1 — below the AA floor the theme file commits to — because a real verdict is drawn in the "empty slot" style**
  - evidence: Sampled the QUIET pill on the Wade Vandenberg row (orig px 1320-1390 × 2130-2158): ink is (108,120,138) on card fill (20,30,48) = 3.69:1, under the 4.5:1 WCAG AA floor for 11 pt text. The HELD pill two rows up measures 5.00:1 ((148,163,184) on (40,51,70)), so the failure is specific. Cause: `DSStatusPill` paints `.empty` as `Color.textTertiary.opacity(0.75)` (DSStatusPill.swift:93) — the 0.75 is what drops the token below its own documented rating; Theme.swift:36-43 explicitly states textTertiary was lightened so it clears AA "on every surface the app actually paints it on: primary 6.24 : 1". And `.quiet` should not be `.empty` at all: `.empty` is documented as "The slot exists and nothing has filled it" (DSStatusPill.swift:44) while `.quiet` is a stated verdict, "Dressed, barely featured" (PreseasonRecapSheet.swift:59), mapped at PreseasonRecapSheet.swift:88. It is on 8 of the 11 bubble rows on pre_12_game3.png.
  - code: `dynasty/dynasty/UI/Common/DSStatusPill.swift:93`
  - fix: Map `.quiet` to `.neutral` (solid chip, textSecondary, 5.0:1) so a stated verdict is drawn as a fact rather than as an unfilled slot, and reserve the dashed `.empty` style for genuinely absent data. Separately, drop the `.opacity(0.75)` on `.empty` — it undoes the AA lightening the token was retuned for.

- [ ] **Q-M337 · No way to open a player from the cut sheet — no age, contract or dev trait anywhere, and the rows are not tappable**
  - evidence: The tape table gives exactly six fields per man: POS, PLAYER · OUTING, OVR, FAM, STANDING, CASE — e.g. "CB · Zachariah Frobisher · No stat line · 67 · – · CAMP · QUIET". The screen asks the player to write a cut from 75 to 65 ("The slate closes with 75 on the roster — 10 over the 65 the phase exits at") with no age, no contract, no cap number, no dev trait and no scheme fit on screen or one tap away. The rows are inert: `DSListRow` is constructed with no tap handler and defaults to `affordance: .none` (DSListRow.swift:601), and the row builder at PreseasonRecapSheet.swift:674-728 attaches no gesture — which matches the screenshots, where no row shows a chevron. Deciding between "CB Zachariah Frobisher 67" and "CB Seneca Crisanti 63" is impossible from this screen: the 63 could be a 22-year-old on a rookie deal and the 67 a 31-year-old on the last year of a veteran contract.
  - code: `dynasty/dynasty/UI/Camp/PreseasonRecapSheet.swift:674`
  - fix: Make the row open the player card (chevron + tap), and use the width freed by widening the column to add AGE and CONTRACT-YEARS as two tight columns. Madden's cut-day screen and OOTP's spring-training report both put age and salary on the row itself, because those two numbers decide more cuts than the exhibition tape does.


### Preseason — game result

- [ ] **Q-M338 · "2 helped their case, 2 hurt theirs" sits directly above a "Who moved" list of five named men**
  - evidence: pre_12_game3_result.png / pre_13_slate_done.png: the recap card says "2 helped their case, 2 hurt theirs." and the modal repeats "2 of the men fighting for a spot helped their case and 2 hurt theirs." The "Who moved" card immediately below names five: Brixton Yarborough (RB, "3.2 a carry on 33 carries"), Easton Maddocks (DE, "2 sacks"), Norbert Vestergaard (SS, "1 interception"), Roman Frobisher (FS, "1 interception"), Jeremiah Marchetti (TE, "7 of 14 caught"). 2+2=4, list=5. In code `movers` filters `lines` on `verdict.moved` with starters included (PreseasonRecapSheet.swift:276-279) while `helpedCount`/`hurtCount` filter `cutCohort`, which excludes `.starter` (PreseasonRecapSheet.swift:264-267). So exactly one named mover is counted nowhere, and nothing on screen says why — the tier pill that would explain it (STARTER) is the only clue and it is covered by the modal in this exact state.
  - code: `dynasty/dynasty/UI/Camp/PreseasonRecapSheet.swift:276`
  - fix: Make the sentence own its scope: "2 of the 52 on the bubble helped their case, 2 hurt theirs — plus 1 starter who moved." Or split the Who-moved card into two labelled groups ("On the bubble" / "Among the ones") so the arithmetic on screen closes.


### Roster cuts — cut to 65

- [ ] **Q-M339 · Two gold "Done" buttons in the same frame meaning two different things**
  - evidence: The result sheet's gold button reads "Done →" (dismisses the sheet) while the action bar visible below it reads "Done — back to Preseason" (leaves the screen entirely). Same word, same gold, one frame, two destinations.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:408-415 and :513`
  - fix: The sheet's continueTitle is "Done" whenever stillOwed == 0 (line 513) and doneAction is titled "Done — back to \(phase)" (lines 408-415). Retitle the sheet's control to what it does — "Back to the list" / "Keep cutting" — and reserve "Done" for the bar action that actually exits.


### Team picker (after the fix)

- [ ] **Q-M340 · The OWNER column is four undocumented icons and a year count with no legend anywhere on the screen**
  - evidence: Under the header "OWNER" each row shows a bare glyph plus a duration: a blue circular gauge with "3yr" (BAL, HOU, BUF, MIA, DEN, KC, LAC), a hollow clock with "4yr" (CIN, PIT, IND, TEN, NE), a filled green clock with "5yr" (JAX), an amber warning triangle with "2yr" (CLE, NYJ, LV). Nothing on the screen says a gauge means "Moderate" and a triangle means "Demanding", or what the years count down to. The underlying strings — "Very Patient", "Patient", "Moderate", "Demanding", "Win Now" — exist on TeamPreview and are simply not rendered in the row.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:1023`
  - fix: Show the word, not just the glyph — "Demanding · 2yr" fits in the 42 pt column at micro size with the icon dropped, or widen the column using the dead space below the list. At minimum add one legend line under the filter bar: "Owner = patience · years before the seat gets hot." This is the second-most decision-relevant column on the screen and currently only a returning player can read it.

- [ ] **Q-M341 · 198 pt of dead space below the last team row on the most important screen in the game**
  - evidence: The last row ("LAC Currents 11-6 · Los Angeles · P. Jimison 87") ends at native y=2355 of a 2752-px canvas — 397 px, or 198 pt at 2x, of empty full-width background beneath it. That is 14.4% of a portrait iPad screen doing nothing on the screen where the player commits to a franchise for the next twenty seasons. The list is also capped at `DSLayout.wideMeasure` (900 pt) inside a 1032 pt screen, so there is a further 50 pt of unused margin down each side.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:196`
  - fix: Spend it. The obvious candidates are the missing OVR column, a difficulty/owner legend, and taller rows (currently `.padding(.vertical, 6)`) so the CAP/STF stack is not two 10-11 pt lines jammed together. Alternatively pin a persistent "Compare" tray or a one-line "what the columns mean" strip to the bottom of the safe area.

- [ ] **Q-M342 · Roster overall is missing from the picker row — the QB rating stands in for it and points the wrong way**
  - evidence: Each row carries record, one QB name+OVR, cap space, staff budget, owner patience, difficulty. It never shows team overall. TeamPreview computes and stores `estimatedOVR`, and the picker never reads it. On this screen that actively misleads: "Tidewater 4-13 · B. Vandenberg 78 · ★" has the best QB of the four low-difficulty clubs, but JAX's estimatedOVR is 66 — the worst in the AFC (LeagueTeamData.swift:91). "Colonials 4-13 · H. Grimsley 68" looks worse and is a 70. A player choosing on "easiest star rating with a usable QB" walks into the weakest roster in the conference and cannot see it without opening every team detail sheet one at a time.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:960`
  - fix: Add an OVR column to CompactTeamRow (the 198 pt of dead space below the last row leaves room to widen rows, or shorten the CAP/STAFF stack). `preview.estimatedOVR` is already in hand; render it with Color.forRating so it shares the app-wide ladder. Optionally show it as "OVR 66 · QB 78" so the gap between the two is the story.


---

## LOW (111)


### Main menu

- [ ] **Q-L01 · Resume line mixes two separators with inverted hierarchy and leads with an unexplained phase name**
  - evidence: The line reads 'CONTINUE: LAS VEGAS HIGHROLLERS  -  COACHING CHANGES — 2027 SEASON'. The top-level break (team → progress) is a thin hyphen while the sub-break (phase → season) is a full em-dash, so the weaker mark does the stronger job: `String(localized: "CONTINUE: \(teamName)  -  \(progressFragment)")` with `progressFragment = "\(phaseLabel(...)) — \(...season)"` (MainMenuView.swift:255, 258). 'COACHING CHANGES' is also the only anchor a returning player gets — unlike the regular-season branch, which produces the far clearer 'Week 9, 2027 season' (line 251).
  - code: `dynasty/dynasty/UI/MainMenu/MainMenuView.swift:258`
  - fix: Use one separator level: em-dash between team and progress, a middot inside the progress fragment. And anchor the offseason phases the way the regular season is anchored — 'Offseason · Coaching Changes, 2027' tells a fan the season is over; 'COACHING CHANGES' alone does not.


### New career

- [ ] **Q-L02 · The screen's only forward action is disabled on arrival, and no default name is offered**
  - evidence: 'Choose Your Team' renders greyed out with the standing hint 'Enter your name above to choose a team.' beneath it, while the Player Name field shows only the placeholder 'Enter your name'. `.disabled(!isNameValid)` on the NavigationLink (NewCareerView.swift:779). The 'Shuffle' control on this screen only rerolls the portrait — there is no equivalent for the name, so the first thing a new player meets is a dead button.
  - code: `dynasty/dynasty/UI/Career/NewCareerView.swift:779`
  - fix: Pre-fill a random coach name (the league already ships name pools — LeagueGenerator.swift:68/126) so the button is live on arrival and the field becomes an edit, not a gate. Focus the field on appear as a fallback.

- [ ] **Q-L03 · 'Step 1 of 1' with a 100%-full progress bar while a mandatory team-selection step still follows; 'Your Career' printed twice**
  - evidence: The indicator row reads 'Step 1 of 1' on the left and 'Your Career' on the right, above a blue bar filled edge to edge — `if totalSteps == 1 { return 1.0 }` (NewCareerView.swift:152). The flow is not finished: the button at the bottom is 'Choose Your Team', which pushes a whole further screen (quickStartChooseTeamButton → TeamSelectionView, line 764). Separately, 'Your Career' appears as the large nav title at y≈160 and again ~70pt below it as the step row's right-hand label `Text(stepTitle(currentStep))` (line 140).
  - code: `dynasty/dynasty/UI/Career/NewCareerView.swift:152`
  - fix: In Quick Start, hide the step row entirely (a one-step flow has no progress to report) — or count the team pick, making it 'Step 1 of 2' with the bar at 50%. Drop the duplicated right-hand title either way.


### Team picker

- [ ] **Q-L04 · 'Generated League' is painted in the screen's interactive blue but is not tappable**
  - evidence: The header subtitle reads 'Generated League  Freshly rolled rosters' with a dice glyph, tinted `.foregroundStyle(leagueSource.isTemplate ? Color.accentGold : Color.accentBlue)` (TeamSelectionView.swift:385) inside a plain HStack with no Button and no navigation. That same accentBlue is the selected AFC tab fill and the active-filter chip colour on this very screen, so the one blue thing that looks like a control is the one thing that is not.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:385`
  - fix: Use a neutral secondary-text colour for the banner, or make it real: tapping it returns to the league-source step, which is the action its colour is promising.

- [ ] **Q-L05 · One amber carries four different meanings inside a 90pt strip, with no key**
  - evidence: On Cleveland Forgemen's row alone, amber marks the four DIFFICULTY stars, 'CAP $12M', and the QB rating '65'. On Jacksonville Tidewater's row, green marks the single DIFFICULTY star AND 'CAP $50M', while amber marks 'STF $24M'. Same token (`Color.warning`, Theme.swift:49) for 'hard job', 'no cap room', 'small staff budget' and 'weak quarterback'; same green (`Color.success`) for 'easy job' and 'lots of cap room'. The same amber family is the app's positive/primary fill on the launch screen ('Continue Career', sampled RGB 187,157,73 ≈ Color.accentGold). No legend appears anywhere on the screen.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:1003`
  - fix: Pick one axis for hue. Keep green/amber for 'good/bad for you' on the money columns, and give difficulty a neutral, monochrome ramp (filled vs unfilled) so the stars stop competing with the money colours — or add a two-line key under the filter bar.

- [ ] **Q-L06 · AFC/NFC picker is a 368pt centred island floating above a 1000pt edge-to-edge table**
  - evidence: Measured: the picker spans x=664-1399px = 367.5pt, horizontally centred; the team rows below span x=32-2031px = 999.5pt. `.frame(maxWidth: 400)` at TeamSelectionView.swift:578. Nothing else on the screen is centred — 'Choose Your Team', the 'Generated League' banner, the Filter chip, the 'TEAM' header and every row are all flush to the same left/right margins, so the one centred element breaks the only alignment rule the screen has.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:578`
  - fix: Either let the picker span the same measure as the table, or left-align it to the 16pt margin so its leading edge lines up with 'TEAM'.


### Team detail

- [ ] **Q-L07 · Division rivals drop the situation colour code the same screen uses two cards above**
  - evidence: Houston's own status chip "CONTENDER" is gold on a gold-tinted capsule, but in DIVISION RIVALS the identical vocabulary — "RISING", "REBUILDING", "REBUILDING" — is rendered grey-on-grey for all three, so the one ascending rival is indistinguishable at a glance from the two rebuilding ones.
  - code: `dynasty/dynasty/UI/Career/TeamSelectionView.swift:1593`
  - fix: The rival chip hardcodes `Color.surfaceBorder` fill and `textSecondary` ink, ignoring the `situationColor` ladder declared at TeamSelectionView.swift:1287 ("blue = building, green = ascending, gold = competing"). Reuse `situationColor(for:)` for the rival chips — the card exists to answer "how tough is my division", and colour is the fastest way it can.

- [ ] **Q-L08 · Rival OVR amber sits one hue away from the gold reserved for emphasis**
  - evidence: "66 OVR" and "69 OVR" in the rivals list are `warning` yellow (#EAB308) and sit ~250pt from the `accentGold` (#C9A94E) "CONTENDER" badge and the gold "SELECT THIS TEAM" button — two near-identical yellows in one view, one meaning "mediocre roster" and the other meaning "premium status / commit here".
  - code: `dynasty/dynasty/UI/Common/Theme.swift:49`
  - fix: `Color.forRatingTier` maps `.average` to `.warning`, whose hue is within ~15° of `accentGold`; the codebase's own rule (TeamSelectionView.swift:1287) is "Amber/red stay reserved for warnings and dangers" while gold means competing. Either push `.warning` further orange, or use `textSecondary` for average ratings so amber only ever means "a problem".


### Intro — podium

- [ ] **Q-L09 · Every slat in the rail is styled as the app's signature button but nothing in it is tappable**
  - evidence: The five index-numbered parallelogram slats carry the same pressed/lift treatment as the interactive bands elsewhere in the app, and on 006_presser_q1.png slat 1 is raised and badged "NOW" — a player who wants to look ahead at question 3, or back at a question he has answered, will tap them and get nothing.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:414`
  - fix: Neither DSSlatBand call site in PressConferenceView passes `onSelect`, so `DSSlatButton` is constructed with `action == nil` and `.disabled(true)` while keeping the button chrome and the `.isButton` accessibility trait. Either wire read-only selection (tapping a `.done` slat shows the answer already given) or render the presser's band with a non-button treatment so it reads as a progress rail.

- [ ] **Q-L10 · The empty resource meter reads as missing-glyph tofu next to "0 spent · 5 left"**
  - evidence: To the left of "0 spent · 5 left" (on both 005_intro_01.png and 006_presser_q1.png) sit five 5×11pt hairline outlines with a 1pt vertical tick in the middle, which at this size render as "▯▯|▯▯▯" — indistinguishable from a font falling back to replacement boxes with a stray pipe character.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:408`
  - fix: Confirmed in code as DSResourceMeter pips, not missing glyphs — but at `spent == 0` every pip fill is `.clear` with a `surfaceBorder` stroke, so the meter's entire visible state is five empty boxes plus a half-way tick that reads as punctuation. Give unfilled pips a faint filled track instead of an outline, and drop the half-way tick when nothing is spent.

- [ ] **Q-L11 · The session preview rail shows three labels for five questions — slats 1/5 and 2/4 are exact duplicates**
  - evidence: The rail reads "1 CONTINENTAL SPORTS · 2 THE GRIDIRON WEEKLY · 3 LOCAL PRESS · 4 THE GRIDIRON WEEKLY · 5 CONTINENTAL SPORTS". Four of the five slats are one of two identical strings, and none of them names a topic, so the band that exists to show "the shape of the session … before it starts" tells the player nothing he can act on.
  - code: `dynasty/dynasty/Engine/Media/PressConferenceEngine.swift:236`
  - fix: `randomReporter()` is `reporters.randomElement()` called independently per question with no de-duplication across the session, so an outlet — and the same named reporter — can be drawn twice. Draw the session's reporters without replacement, and put the question's subject on the slat (`title: question.topic`, outlet as subcaption) so the rail is a table of contents rather than a list of the same masthead.


### Intro — press reaction

- [ ] **Q-L12 · Two of the five progress slats carry the same outlet name, so the strip cannot be used to tell questions apart**
  - evidence: 010's slat strip reads "✓ CONTINENTAL SPORTS / Diplomatic | 2 THE GRIDIRON WEEKLY | 3 LOCAL PRESS | 4 THE GRIDIRON WEEKLY | 5 CONTINENTAL SPORTS" — slats 2 and 4 are indistinguishable, as are 1 and 5 (011 confirms all five checked with the same labels). Each question draws its reporter independently with replacement: `reporters.randomElement()` per generator, with no exclusion list (PressConferenceEngine.swift:236-238, called from :651, :711, etc.), so the same outlet — and, from the same line, the same reporter name — can be drawn twice in a five-question conference.
  - code: `dynasty/dynasty/Engine/Media/PressConferenceEngine.swift:236`
  - fix: Deal reporters without replacement for one conference (shuffle the pool once in `generateIntroConference` and pop), or label the slats by topic ("VISION", "THE CAP", "THE FANS", "THE DRAFT", "THE PRESS") which is what the player is actually navigating by.


### Intro — owner briefing

- [ ] **Q-L13 · Staff Budget Envelope columns sum to $53.9M but the card header says $53.8M**
  - evidence: Header: "$53.8M". Columns: "$47.0M COACHING", "$4.1M SCOUTING", "$2.8M MEDICAL" — 47.0 + 4.1 + 2.8 = 53.9.
  - code: `dynasty/dynasty/UI/News/OwnerBriefing.swift:677`
  - fix: The total is summed in thousands and then rounded once, while each column is rounded independently, so the displayed parts need not add to the displayed whole. Round the three columns first and display their sum, or show the total to the same precision the parts imply.

- [ ] **Q-L14 · The first owner meeting of the career is headed "0/2 met"**
  - evidence: Season Goals card head: "SEASON GOALS   0/2 met", with both goals showing empty circles: "Win the Championship — PRIMARY", "Upgrade key roster positions — SECONDARY". The season has not started; the first thing the owner screen reports is a zero score.
  - code: `dynasty/dynasty/UI/News/OwnerBriefing.swift:745`
  - fix: The intro always builds both goals with isAchieved: false, so this counter can only ever read 0/2 here. Suppress the counter when nothing has been played (show "2 goals" or the deadline instead) and keep "n/2 met" for the in-season hub.


### Intro — team overview

- [ ] **Q-L15 · A five-screen forced intro gives no sense of how many Continues remain**
  - evidence: Screens 03, 04 and 05 each end in a "Continue" with no step counter, dots or progress rail anywhere on the screen; the intro is five steps (press conference, owner meeting, team overview, roadmap, ready to begin).
  - code: `dynasty/dynasty/UI/Career/IntroSequenceView.swift:82`
  - fix: The TabView sets .tabViewStyle(.page(indexDisplayMode: .never)). Either re-enable the page dots or put a small "2 of 5" beside the Continue, so the player knows the briefing is finite before they start skimming.

- [ ] **Q-L16 · Two of the three key players share the first name Callum**
  - evidence: Key Players list: "Wade Braithwaite WR — 94 OVR", "Callum Abernathy MLB — 91 OVR", "Callum Goddard CB — 89 OVR". Two of the only three names on the franchise's marquee list are Callums.
  - fix: Add a same-first-name check when generating a team's roster (or at least when picking the three names surfaced on this card) so the first impression of the franchise's stars does not read as a generator artefact.


### Career hub

- [ ] **Q-L17 · A card titled "SEASON REVIEW" shows generic placeholder copy because there is no season to review yet**
  - evidence: Bottom-left card: "SEASON REVIEW" with body "Owner mandates / Meet the owner". No goals met, no verdict, no numbers — and the club's record on this same screen is 0-0. Identical on 025.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1205`
  - fix: `offseasonGoalsTile` titles the card "Season Review" unconditionally and falls back to the "Owner mandates"/"Meet the owner" literals when `career.ownerSeasonReview == nil`. Retitle the empty state to "Owner Mandates" (which is what it actually shows), or hide the tile until a review exists.

- [ ] **Q-L18 · 3-YEAR CAP card is half empty, skips year 2, and shows no chart despite a line-chart icon**
  - evidence: The card holds a line-chart glyph, the title "3-YEAR CAP", then two lines: "$265M → $320M" and "Projection across 3 seasons". Year 2 is never shown. The card is stretched to match the OWNER card beside it, leaving roughly the bottom 55% of its area blank. Identical on 025.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1179`
  - fix: `cap3yearForecastTile` renders only `threeYearCapProjection` plus a static caption. Draw the three years as a three-bar sparkline with committed money stacked against each year's cap — the data is already there, and the icon promises it.

- [ ] **Q-L19 · The QB's morale is reduced to an unlabelled 10pt glyph on the same card that prints team morale as a percentage**
  - evidence: LOCKER ROOM shows "Team Morale  65%" and directly beneath it "QB  Wimberly" ending in a small gold dashed-face icon with no number and no legend. The glyph is one of three buckets (smiling / dashed / rain) standing in for a 0–100 value the engine models exactly. Same on 025.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2301`
  - fix: Print the number beside the glyph ("QB Wimberly  54%") the way the line above does, and add the same treatment for the top defender so the card supports a comparison rather than a single mood emoji.


### Cap tab

- [ ] **Q-L20 · Two full-width cards and ~450px of vertical space are spent restating zeroes and a number already shown above**
  - evidence: "Cap Usage 83.7%" is its own card, but the card directly above already prints "$265.0M Total Cap / $221.7M Used Cap / $43.3M Available" — the percentage is those two numbers. Below it, a second full card holds "Dead money  $0K / No dead money on the books — every dollar of cap charge belongs to a player on the roster." A third zero — "No restructured bonus carrying forward  $0K" — gets its own row in the Next Year card. Zero is also formatted as "$0K" rather than "$0".
  - code: `dynasty/dynasty/UI/Contracts/CapOverviewView.swift:~660-780 (cap usage + dead money cards); dynasty/dynasty/UI/Roster/PlayerRowView.swift:388-405`
  - fix: Fold the usage percentage into the summary card (next to "Used Cap") and collapse zero-valued blocks to a single quiet line, freeing the space for what a cap screen is actually for: the top cap hits with dead-money-if-cut and net-savings per player. Those numbers already exist — `deadCapIfCut` and `capSavingsIfCut` are computed for the Roster's Contracts tab (PlayerRowView.swift:388-405) — but the Cap screen shows only the expiring roll call. Reference: OOTP's payroll page and Madden's Restructure/Release flow both put the cut/restructure math on the cap screen itself.


### Roster tab

- [ ] **Q-L21 · The "Position Skills" tab ships placeholder column headers — "Skill 1" through "Skill 4"**
  - evidence: The ANALYSIS strip on screen offers "Overview · Contracts · Development · Physical · Position Skills · Mental · Depth". The Position Skills lens (one tap away) heads its four data columns with the literals "Skill 1", "Skill 2", "Skill 3", "Skill 4" — while every other lens on the same strip uses real names ("Dead / Save / Salary / Cap / Yrs / FA", "SPD / STR / STA / DUR", "LRN / CMP / WE / Motiv").
  - code: `dynasty/dynasty/UI/Roster/RosterView.swift:946-953; cells at PlayerRowView.swift:555-572`
  - fix: `analysisHeaderColumns` case `.attributes` hardcodes the four labels, even though the cells below already carry per-position names via `positionSkillAttributes` (`colorCodedMiniAttribute(value:label:)`). Since the skills differ by position, either drive the header from the selected position filter, or drop the four header labels entirely and let the cell captions speak — a placeholder header is worse than none.


### Scouting / big board

- [ ] **Q-L22 · Name pool collides with itself — prospects compared against roster players who share their first or last name**
  - evidence: Row 8: "Alaric Yarborough … vs Alaric Kirkbride: +8 OVR". Row 13: "Wade Hambleton … vs Wade Hedgepeth: +8 OVR". Both read as a man being compared to himself. Within the 16 visible prospects: "Kenji Shelburne" (#1) and "Hayden Shelburne" (#34); "Jamari Crisanti" (#5) and "Jamari Goddard" (#2); "Callum Lockridge" (#203) and "Callum Henshaw" (#224); "Jace Hopewell" (#23) plus a roster comp "Waylon Hopewell" plus a prospect "Waylon Karrington"; "Wilkes Kirkbride" (#61) alongside the comp "Alaric Kirkbride". Eight collisions in sixteen rows.
  - code: `dynasty/dynasty/UI/Scouting/BigBoardView.swift:2249`
  - fix: The comparison line pulls `starter.fullName` from the same generated pool as the class. Track issued first names and surnames per league and reject a draw that collides with an active player at the same position, or at minimum re-roll when the generated prospect shares a first or last name with the starter he will be compared against.

- [ ] **Q-L23 · Two different "no data" glyphs in the same row: em dash in the combine cells, double hyphen in GRD**
  - evidence: Ezekiel Ferrante, Waylon Karrington, Wade Hambleton and Callum Lockridge show "--" (two hyphens) in the trailing GRD column while the seven combine cells on the very same rows show "—" (em dash). Confirmed in source: the grade column hardcodes `Text("--")` while the shared prospect cells use `Text("\u{2014}")`.
  - code: `dynasty/dynasty/UI/Scouting/BigBoardView.swift:2645`
  - fix: Use `\u{2014}` in `boardGradeColumn`, or better, route every empty cell through one `DSEmptyCell` so the placeholder cannot fork again.


### Staff tab

- [ ] **Q-L24 · Gold is doing seven different jobs on one screen, so it no longer signals emphasis**
  - evidence: Staff screen gold: the "HOU" team chip, the "HC" role badge, the head-coach portrait ring, the ① and ② section badges, the "Vacant — Tap to hire" text (×2 visible), the two "+" add buttons, and the auto-hire spend line "Spends ~$13.2M of $47.0M coaching · ~$1.7M of $2.8M medical · ~$4.1M of $4.1M scouting". The Roster screen spends it on a further set: "$221.7M" and its cap bar, the 3-star team rating, the "1yr" contract badges, the "1 exp / 3 exp" chips, the "Key FA pending" chip and the "★" potential glyph.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:1526-1530 (states the rule)`
  - fix: The codebase already states the rule — CoachingStaffView.swift:1528 says "gold has exactly three jobs". Pick the three (identity, money-at-risk, and the single primary action would be a defensible set) and demote the rest: section badges and portrait rings to `textSecondary`, "Vacant — Tap to hire" to the standard action blue used by "Change portrait" on the same screen.

- [ ] **Q-L25 · Three incompatible bonus grammars on one screen, none tied to a visible baseline**
  - evidence: Head Coach card: "+10 Play-Calling". Assistant Head Coach: "+5% staff chemistry bonus". Offensive Coordinator: "+12% offensive efficiency". An absolute unitless delta, a percentage of an unnamed stat, and a percentage of an unnamed team metric — with no way to tell whether +10 Play-Calling is worth more or less than +12% offensive efficiency.
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:1195-1205`
  - fix: The role-benefit strings are authored literals (CoachingStaffView.swift:1195-1205). Normalize to one currency the player can compare — either express everything as a percentage of a named, visible number, or add a common "impact" score per role. Ideally each line should point at where the effect will show up ("+12% offensive efficiency → shows on the Hub as OFF rating"), so the hire visibly pays off later.


### Coaching staff

- [ ] **Q-L26 · "Assistant Head Coach" is printed twice in the same card group, and the section breaks the numbered ladder**
  - evidence: Section header "👥 Assistant Head Coach" sits directly above a card whose first line is also "Assistant Head Coach". It is also the only section with no step number, so the page reads "1 Head Coach → (unnumbered) → 2 Coordinators".
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:4103 (Text(role.displayName) inside a section already titled with the same string); the missing number is deliberate — tier(for:) returns nil for .assistantHeadCoach at :3270`
  - fix: Drop the role name from the row inside a single-role section and let the row lead with "Vacant — Tap to hire ~$1.3-7.0M/yr". Mark the section "Optional" so the absent step number reads as intent rather than as a missing rung.

- [ ] **Q-L27 · Future steps in the hiring rail carry no counts, so the workload total appears only inside the auto-hire button**
  - evidence: The rail shows "✓ HEAD COACH / You" and "2 COORDINATORS / 3 open · ~$6.1M", but "3 POSITION", "4 MEDICAL" and "5 SCOUTING" are bare labels. The only place the player learns how much work is left is the auto-hire subtitle: "Fills all 23 vacant roles…".
  - code: `dynasty/dynasty/UI/Staff/CoachingStaffView.swift:3337-3341 (subcaption returns nil unless state == .current)`
  - fix: Give future slats a muted "8 open" / "3 open" / "5 open" caption. A manager planning a $47.0M budget needs to see that the eight position coaches are still ahead of him before he spends $6.6M on one coordinator.


### Candidate profile

- [ ] **Q-L28 · Double article in the chemistry line: "with your The Tactician approach"**
  - evidence: COACHING STYLE card: "HC Chemistry: Strong — Steady Performer fits well with your The Tactician approach."
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:1578 (also :1581 and :1584 for the Weak and Average variants)`
  - fix: CoachingStyle.displayName carries the article ("The Tactician", "The Players' Coach"). Either strip it for interpolation or reword to "fits well with your \(style.displayName) approach" → "fits well with \(style.displayName)". All five styles and all three chemistry verdicts are affected.

- [ ] **Q-L29 · OVR context label clipped to "Above A…" in a fixed 52pt badge**
  - evidence: The overall badge reads "71 / OVR / Above A…" — the qualifier that gives the 71 its meaning is the part that gets cut.
  - code: `dynasty/dynasty/UI/Staff/HireCoachView.swift:1765 (.frame(width: 52, height: 58)) with labels from :1274 ("Above Avg", "Below Avg")`
  - fix: Widen the badge to ~68pt or shorten the labels to "Above"/"Below"/"Elite"/"Average"/"Poor". "Below Avg" clips identically, so every candidate rated 50-79 loses the word.


### Hire result sheet

- [ ] **Q-L30 · 020_autohire is a byte-identical duplicate of 019 — it carries no new evidence**
  - evidence: md5 of 019_hire_oc_result.png and 020_autohire.png are both f54b646da5f5db22de963a65ff302d6f. 020 still shows the single-hire modal "Finnian Balfour is your Offensive Coordinator" with the Auto-Hire card behind the scrim, so the step captured the pre-tap state (the tap was correctly blocked by the modal).
  - fix: Capture harness issue, not an app defect: the auto-hire step should dismiss the result sheet ("Continue →") and wait for the sheet to leave before screenshotting. Treat 020 as a duplicate of 019 when tallying.


### Staff after auto-hire

- [ ] **Q-L31 · Half the WHAT CHANGED grid is empty state given the same weight as the real numbers**
  - evidence: The grid reads "HIRED 22 / of 22 jobs · SPENT $19.5M / across three pots · STILL OPEN 0 / none · CLASHES 0 / none". Two of four chips are zeros whose context line is the word "none", rendered at the same title2-heavy size as $19.5M.
  - code: `dynasty/dynasty/UI/Common/DSResultSheet.swift:171`
  - fix: On a clean batch, collapse the two zero chips into one reassurance line ("No jobs left open, no clashes with your head coach") and give the freed columns to something with content — e.g. the two most important men signed.


### Coaching staff review sheet

- [ ] **Q-L32 · Surname pool is small enough that three of fifteen coaches share a surname with a colleague, and two same-position WRs share one in the decision list**
  - evidence: 027's fifteen-coach list contains Zavier Goddard (AHC) with Demetri Goddard (DC), Ramiro Kirkbride (RB) with Alicia Kirkbride (DL), and Tobias Derringer (DOC) with Jeremiah Derringer (PHY) — three collisions in one screen. On 030/032 the Key Decisions list puts Wade Braithwaite (WR, 94 OVR, $37.4M, EXPIRING) three rows above Zavier Braithwaite (WR, 72 OVR, $5.3M, EXPIRING): same surname, same position, same status, same list, opposite recommendations ("Prioritize extension" vs "Consider letting him walk"). Across the two screens the given name Zavier appears three times and Demetri, Callum and Wade twice each. Cause: `RandomNameGenerator.lastNames` holds 55 surnames, drawn independently for every player, coach and scout in the league. The small pool is deliberate (the file header documents a Levenshtein-3 anonymization gate against real NFL names), so this is a constraint to design around, not a coding error.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:66`
  - fix: Keep the pool but de-duplicate at assignment: reject a surname already held by another member of the same coaching staff or the same position group on the same roster. Where a collision survives, disambiguate in list UI the way the draft ticker already does (DraftTickerPanel.swift:309-355 solved exactly this for "R. Goddard").

- [ ] **Q-L33 · The sheet title is repeated verbatim as a section header 90px below itself**
  - evidence: The navigation bar reads "Coaching Staff Review" and immediately beneath it, in gold small-caps, the first content element reads "COACHING STAFF REVIEW" — the same three words twice in the top eighth of the sheet, followed by a gold rule. In code these are `.navigationTitle("Coaching Staff Review")` at line 4814 and `Text("COACHING STAFF REVIEW")` in `headerSection` at line 4842.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:4842`
  - fix: Delete `headerSection` and let the nav title carry the name, or replace the duplicated line with the verdict the gate is actually asking for ("15 seats filled · 2 schemes set · ready to advance").


### Career hub (review roster)

- [ ] **Q-L34 · KPI strip gives two of four numbers no scale: "Scrutinized MEDIA" and "15 LEGACY"**
  - evidence: The four tiles read "88% OWNER", "65% MORALE", "Scrutinized MEDIA", "15 LEGACY". The two percentages carry an implicit 0-100; "Scrutinized" is an unexplained tier with no ladder shown, and "15" has no denominator, direction or trend — a first-time player cannot tell whether 15 Legacy is good or whether Scrutinized is worse than the alternative.
  - fix: Show each as value-in-context: "MEDIA Scrutinized (3 of 5)" and "LEGACY 15 · +2 this season", and make the tiles tappable to the ladder that defines the tiers.


### Tasks panel

- [ ] **Q-L35 · Name pool collides: two WR Braithwaites, two Wades and two Zaviers among eight visible players**
  - evidence: Key Decisions list shows "WR Wade Braithwaite" (94 OVR, $37.4M) and "WR Zavier Braithwaite" (Age 32, 72 OVR, $5.3M) — same position, same surname — plus "Zavier Hambleton" (WR) and "Wade Hopewell" (K). The generator draws from 55 first names × 55 last names (3,025 combinations) for a whole league of ~1,700 players, so repeats are guaranteed.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:31`
  - fix: Reject a draw whose (firstName,lastName) or lastName already exists on the same club, and grow the pools; two same-position players sharing a surname on one roster reads as a duplicated row.

- [ ] **Q-L36 · Roster Evaluation table has a ~700 px empty band in every row between "Cap $" and the Staff/You chips**
  - evidence: Row content ends at "$34.2M" (x≈550 of 1500) and the next element is the "Solid" chip at x≈1290, with "—" under "You" at the far right; the same dead band repeats down all nine rows (QB…ST). The screen's job is comparing rooms, yet starter count, injuries, expiring bodies and last season's group OVR — all of which the engine holds — have nowhere to go.
  - fix: Fill the band with the two columns this decision needs — bodies at the position ("3 / 4 ideal") and expiring count — or left-align the Staff/You columns against the cap column and narrow the card.


### Franchise tag

- [ ] **Q-L37 · Gold is the default colour on this screen, so it emphasises nothing — and the actual advice is the dimmest text**
  - evidence: Gold appears on "$282.2M", the section header "Expiring Contracts (8 players)", all eight tag costs ("$26.0M", "$17.3M", "$5.0M", "$25.1M", "$26.0M", "$15.6M", …) and all eight "Apply Tag" pills — roughly twenty gold elements. The screen's actual recommendation, "Elite player — strongly consider tagging.", is textSecondary caption, and the consequence line "2027 space after tag: $116.2M" is textTertiary caption — the two things a GM decides on are the two faintest strings in the row.
  - code: `dynasty/dynasty/UI/Contracts/FranchiseTagView.swift:403`
  - fix: Reserve gold for the recommended action and the single headline number; render tag costs in textPrimary monospaced, and promote the recommendation and post-tag space to subheadline weight so the eye lands on the decision, not on eight prices of equal loudness.


### Contract negotiation

- [ ] **Q-L38 · The round chrome states the same quantity four times while the page below it is empty**
  - evidence: One band carries: the eyebrow "ROUND 1 OF 3", three slats reading "1 ROUND 1 / 2 ROUND 2 / 3 ROUND 3", a three-pip meter, and the value line "0 spent · 3 left" — four encodings of "you are in round 1 of 3", with the word ROUND printed four times, above a page that is 40% blank.
  - code: `dynasty/dynasty/UI/Contracts/NegotiationChat.swift:260`
  - fix: Keep the slat ribbon (it carries outcomes per round) and drop either the eyebrow or the pip meter + value line; the ribbon already shows spent, current and remaining by state.


### Franchise tag

- [ ] **Q-L39 · "Tag Cost" is a derived number with no way to see what it derives from — and it moved $3.3M between visits with no note**
  - evidence: The rules banner says the tag is "the average of the top 5 salaries at his position", but no row lets you see those five salaries. Between 035 and 041 the WR tag went from "$26.0M" (Zavier Braithwaite, Zavier Hambleton) to "$29.3M" for the same two men, because re-signing Wade Braithwaite raised the league's top-5 WR average — tagValue reads every player in the league at that position. The screen shows no history and no cause; "Committed to 2027" also jumped $140.1M → $194.1M with no ledger of what changed it.
  - code: `dynasty/dynasty/UI/Contracts/FranchiseTagView.swift:655`
  - fix: Make the tag cost tappable to a popover listing the five salaries it averages, and stamp a delta on the row when the price has moved since the last visit ("+$3.3M — your own re-signing raised the WR market").


### Franchise tag (applied)

- [ ] **Q-L40 · Norbert Yarborough's row: $70.8M − $15.6M is shown as $55.3M**
  - evidence: The banner reads "Projected Space $70.8M" and his row reads "$15.6M Tag Cost" with "2027 space after tag: $55.3M". 70.8 − 15.6 = 55.2. Every other row reconciles exactly (Hopewell 70.8−5.0=65.8; Larrabee 70.8−25.1=45.7; both WRs 70.8−29.3=41.5), so this one row visibly fails the subtraction a reader can do in their head. It is a rounding artefact — the underlying thousands round up while the displayed millions round down — but it is on screen.
  - code: `dynasty/dynasty/UI/Contracts/FranchiseTagView.swift:389 and :465`
  - fix: Round once: compute the displayed "space after tag" from the already-rounded display values, or format all three from the same rounding pass so rows can always be checked against the banner.

- [ ] **Q-L41 · Two WRs called Zavier with identical tag costs in a six-row list, and "Wade" recycled from the player signed six minutes earlier**
  - evidence: The expiring list holds "Zavier Braithwaite — WR, Age 32, 72 OVR, $5.3M/yr, $29.3M Tag Cost" and "Zavier Hambleton — WR, Age 29, 67 OVR, $4.0M/yr, $29.3M Tag Cost" — same position, same first name, same tag price, three rows apart. "Wade Hopewell" heads the same list while 037/038 just re-signed "Wade Braithwaite", so both halves of that name are re-used on adjacent screens. RandomNameGenerator draws first and last independently from 55 x 55 pools with no uniqueness check, for a league of well over a thousand players, so first-name collisions inside a single six-row list are routine.
  - code: `dynasty/dynasty/Data/Import/RandomNameGenerator.swift:85-89`
  - fix: Keep a per-league used-name set in the generator (retry on a full-name collision, and prefer a fresh first name when a club already rosters that first name at the same position). The pools are already gate-checked for realism; only the draw needs the memory.


### Combine interviews

- [ ] **Q-L42 · The same explanation of what an interview reveals is printed twice, 240px apart**
  - evidence: Under the PROSPECT INTERVIEWS title: "Reveals: Football IQ (exact) · Awareness, Learning, Compete, Leadership, Work Ethic grades · personality & character" (line 264). Then a dismissible info banner below the mode chips: "Interviews reveal personality, football IQ, and character — reducing bust risk." (line 505). The Insights strip above both already says "INTERVIEWS · 0/60 interviews · 16% scouted · The Combine".
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:505`
  - fix: Delete the banner — the precise line above it strictly dominates it (it names the exact attributes) — and fold "reduces bust risk" into that line, or move both behind the INSIGHTS chevron that already exists for exactly this content.

- [ ] **Q-L43 · The gold info banner repeats, less precisely, the line printed three rows above it**
  - evidence: Header line: "Reveals: Football IQ (exact) · Awareness, Learning, Compete, Leadership, Work Ethic grades · personality & character". Banner ~120 px below: "Interviews reveal personality, football IQ, and character — reducing bust risk." The banner is strictly less informative than the line it repeats, and it is the only gold-tinted card in the upper half of the screen, so it takes emphasis that should belong to "53/60 selected".
  - code: `dynasty/dynasty/UI/Scouting/InterviewSelectionView.swift:505`
  - fix: Delete the banner. If the "reduces bust risk" claim is worth keeping, append it to the existing Reveals line as a clause rather than as a second card with its own dismiss control.

- [ ] **Q-L44 · "NEED" carries two different meanings on the same row — a green pill and a column value**
  - evidence: Every row in the RECOMMENDED section shows a green "NEED" pill next to the school ("UCLA Rd1 ●○○ NEED") and, in the trailing block, a column headed "NEED" whose value reads "Med" or "High". The pill is the boolean `teamNeedPositions.contains(position)`; the column is the urgency (`needCell` renders High / Med / Set). Because the section only lists need positions, the column can never read "Set" here, which makes the pill 100% redundant with "the column is not Set" while claiming to be a different fact.
  - code: `dynasty/dynasty/UI/Scouting/ProspectListControls.swift:866`
  - fix: Drop the green pill inside the RECOMMENDED section (the section title already says these match team needs) and keep the graded column, or rename the column "URGENCY" so the two words stop competing.

- [ ] **Q-L45 · FIT column reads "Good" on 14 of 15 visible rows — a column with no discriminating power in the default view**
  - evidence: The FIT column reads Good, Good, Good, Good, Good, Good, Good, Good, Good, Good, Good, Good, Good, Fair, Good top to bottom. `schemeFitLabel` can return Good / Fair / Poor, so the axis exists — but as displayed it costs a column and separates nothing, on a screen whose whole job is picking 60 names out of 288.
  - code: `dynasty/dynasty/Domain/Models/Scouting/ProspectSchemeFitHelper.swift:7`
  - fix: Either show the underlying fit score (0–99 from `ProspectSchemeFitHelper`) so rows can be ranked against each other, or replace the column with something that varies — projected round, or the position's depth-chart hole — and keep the coarse label on the prospect card.

- [ ] **Q-L46 · Projected round is typeset two ways one screen apart — "Rd1" in the list, "Rd 1" in the report**
  - evidence: 051_interviews_selected rows read "UCLA Rd1", "Ohio State Rd1", "Clemson Rd1", "Minnesota Rd2". The report cards on 053 read "Washington  Rd 1" and "Ohio State  Rd 7". Same fact, same feature, two typographies.
  - fix: Pick one form and route both call sites through a single `projectedRoundText(for:)` helper so the list and the report cannot drift again.


### Cap compliance

- [ ] **Q-L47 · "$-20.5M" — the currency sigil is printed inside the minus sign on a negative release**
  - evidence: Wade Braithwaite's Release tile reads "Release / $-20.5M / $74.5M dead" (confirmed at 3× crop). At HEAD the formatter is `String(format: "$%.1fM", millions)` with a negative `millions` (CapComplianceView.swift:686), which produces exactly that. NOTE: the working tree already carries an uncommitted fix — `let sign = thousands < 0 ? "-" : ""` … `String(format: "%@$%.1fM", sign, millions)` — in both CapComplianceView and RestructureQuoteSheet, so this may already be handled by another pass in this session.
  - code: `dynasty/dynasty/UI/FreeAgency/CapComplianceView.swift:686`
  - fix: Ship the working-tree fix (sign outside the sigil → "-$20.5M"), then audit the other nine private copies of `formatMillions` (RosterEvaluationView:2626, PlayerContractView:462, ContractTimelineView:414, CapOverviewView:1555, ContractNegotiationView:2825, ContractExtensionSheet:565, TradeView:2432, FranchiseTagView:739) — they carry the same body and any that can be handed a negative will print the same thing. Better: promote one shared formatter.


### Free agency — market

- [ ] **Q-L48 · Markdown emphasis in the action-bar explainer does not render — "**unopposed**" prints unbolded**
  - evidence: The bar reads "Advancing lets the league sign unopposed for a day you cannot get back." At 6x zoom, "unopposed" is stroke-for-stroke the same weight as "sign" and "for a day you" around it. The source string is "Advancing lets the league sign **unopposed** for a day you cannot get back."
  - code: `dynasty/dynasty/UI/Common/DSActionBar.swift:113`
  - fix: `Explainer.message` is documented at DSActionBar.swift:31-32 as "Markdown is honoured, so a call site emphasises the load-bearing nouns with `**…**`", and it renders through `Text(LocalizedStringKey(explainer.message))` — a LocalizedStringKey built from a runtime String, which is not reliably markdown-parsed. Build an `AttributedString(markdown:)` instead. This affects every DSActionBar in the app, including call sites like "Closes **Film Study** and spends **1 of 6** scouting weeks left in the spring" (DSActionBar.swift:308) where the emphasis is carrying the number.

- [ ] **Q-L49 · The top two names on the board share a first name — Kason Marsden and Kason Hopewell**
  - evidence: Row 1: "Kason Marsden  Money  SS 90". Row 2: "Kason Hopewell  Stats  RT 88". The two highest-rated free agents in the league, adjacent, both named Kason.
  - fix: Not a rendering fault — a name-generator collision that lands in the two most-looked-at rows in free agency. Add a same-first-name suppression window when generating a cohort (reject a first name already used within the last N draws, or weight by frequency), so the board does not read as procedurally generated at the exact moment the player is memorising names.

- [ ] **Q-L50 · Five separate jargon systems on one screen with no legend: BID/VST/HEAT, Money/Stats/Fame/Winning, ASKS, Skill**
  - evidence: Row 1 alone carries: a dashed "BID" chip, a dashed "VST" chip, a "HEAT COOL" chip, the word "Money" in grey beside the player's name, the column header "ASKS", and a filter chip labelled "Skill". None is expanded anywhere on the screen, and the header row explains only POS / FREE AGENT / OVR / AGE / ASKS / YRS.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:1539`
  - fix: The three-letter idents are a good scanning system once learned, but there is no first-run path to learning them. Add an info affordance in the list header that expands a one-line legend (BID = your offer, VST = facility visit hosted, HEAT = how many clubs have actually bid), and spell the motivation label as a phrase on first encounter ("Chasing money") — `motivationLabel` returns bare nouns at FAWeeklyView.swift:2117.

- [ ] **Q-L51 · The step-rail meter reads "1 spent · 5 left" with no noun, on a screen that also says "Visits left 3/3"**
  - evidence: Top right of the band: six pips (one filled) and the text "1 spent · 5 left". Twenty pixels below it: "Visits left 3/3" and "126 on the board". Nothing on screen says the 6 are market days.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:326`
  - fix: `DSResourceMeter` carries `unit` ("market days", set correctly at FAWeeklyView.swift:588) but `valueLine` is `"\(spent) spent · \(left) left"` — the noun only ever reaches VoiceOver via `accessibilityText`. Render it: "1 of 6 market days spent". Every screen mounting a `DSSlatBand` meter has the same hole.

- [ ] **Q-L52 · Empty state-slot labels BID and VST render at 4.01:1 contrast — below WCAG AA for an 11pt label**
  - evidence: Sampled the dominant non-background colour across the BID/VST chips at (185-300, 940-970): #6A7586 (384 px) on the #0B1222 row background = 4.01:1. Their dashed borders sample #444D5E = ~2.3:1. The set "HEAT COOL" slot beside them measures 7.29:1.
  - code: `dynasty/dynasty/UI/Common/DSStatusPill.swift:92`
  - fix: `.foregroundStyle(tone.isEmpty ? Color.textTertiary.opacity(0.75) : tone.tint)` — `textTertiary` is #8A96A8 and the 0.75 alpha drops it to #6A7586. The codebase already added `textTertiaryReadable` (#7C8BA1) and `dangerText` for exactly this class of miss; use `textTertiaryReadable` at full opacity and let the dashed border alone carry the "unset" reading. Applies app-wide — roster FIT/EXT/HLTH and board RPT/CMB/MEET use the same component.

- [ ] **Q-L53 · Ticker overflow is invisible: the 4th chip is cut mid-word at the screen edge and a 5th item can never be discovered**
  - evidence: The fourth ticker chip reads "$ Cap-rich teams r" — sliced at x=2064 with no padding, no fade and no scroll indicator. The source list holds five items; "Early movers shape the market" is entirely off-screen.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:2239`
  - fix: `ScrollView(.horizontal, showsIndicators: false)` with a hard clip. Add a trailing gradient mask or trailing inset so the cut reads as "more this way" rather than as a rendering fault, and let the last chip clip at a chip boundary rather than mid-word.


### Free agency — skip dialog

- [ ] **Q-L54 · The same actor is "AI clubs" in the button caption and "AI teams" in the alert it opens**
  - evidence: Bottom bar, destructive button: "Skip the rest / AI clubs sign everyone left." The alert it raises: "AI teams will sign remaining free agents based on their needs." Two nouns for one actor, one tap apart.
  - code: `dynasty/dynasty/UI/FreeAgency/FAWeeklyView.swift:319`
  - fix: Pick one. The action bar (FAWeeklyView.swift:1779) and the rest of the FA copy say "clubs"; the alert message (line 319) says "teams". Change the alert to "AI clubs".


### Pro days

- [ ] **Q-L55 · The largest type on the screen says "Scouting", which the nav bar already says, and the screen's actual subject is fifth in the hierarchy**
  - evidence: Top nav prints "Scouting" as one of seven items; ~150px below, a back chevron and an ~44pt H1 print "Scouting" again. The subject — "PRO DAYS" — appears at ~20pt, 250px further down, after the stage band. That is ~330px (17% of screen height) of chrome before anything specific to this screen, and the eye's first hit is a word that carries no information.
  - code: `dynasty/dynasty/UI/Scouting/ScoutingHubView.swift:1851`
  - fix: Make the H1 the stage ("Pro Day Focus") with "Scouting" as a breadcrumb/back affordance, or drop the H1 entirely — the band's gold slat 4 already states where you are. The same stage is also called two names 60px apart: the band title "PRO DAYS" (tab name) vs the slat "PRO DAY FOCUS" (DraftPrepStep.displayName), with "Pro Days & Workouts" (the phase) on the same line.

- [ ] **Q-L56 · The focus-slot meter is 60x6pt, so the first reservation renders as a ~2pt sliver**
  - evidence: 074: "Focus slots / 1/25 reserved · 8 scouts" with a meter at the far right whose gold fill is 1/25 of 60pt = 2.4pt — a single visible tick. On 073 (0/25) the bar is empty and indistinguishable from a disabled control.
  - code: `dynasty/dynasty/UI/Scouting/ProDayTourView.swift:315`
  - fix: The row has ~1100px of unused width; give the meter 200-300pt, or replace it with 25 pips (8 grouped by scout) so a slot is a countable object. Note also `progress > 0.8 ? .danger : .accentGold` paints a nearly fully-committed department red — spending your scouts' attention is the goal here, not a hazard.


### Career hub (draft)

- [ ] **Q-L57 · Position Grades prints "S  S: B− / D: B−" — the Safety group code collides with the legend's "S = starters"**
  - evidence: Right column of the tile: "S   S: B− / D: B−", directly above the key "S = starters · D = depth · tap a grade for details". Two different meanings of "S" in the same 40px row.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2410`
  - fix: Label the group "SAF" (or "S/FS") in this tile, or change the legend keys to "ST:" / "DP:". Every other row reads cleanly ("QB S: A / D: C"); only the safety row asks the reader to parse the same letter twice.

- [ ] **Q-L58 · "YOUR OFFSEASON 0/2" counts only the current phase's tasks while "Phases complete (7)" sits directly beneath it**
  - evidence: Rail header: "▤ YOUR OFFSEASON        0/2". Next row: "✓ Phases complete (7)". Then "THE DRAFT [NOW] Apr / PRE-DRAFT · STEP 4 OF 4" with two tasks. The 0/2 is this phase's task pair, but the label it sits on says "offseason", which reads as 0% offseason progress with 7 phases already done.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:121-142 (panelHeader + taskProgress), :185 (completedPhasesDisclosure)`
  - fix: Scope the counter to what it counts — put it on THE DRAFT row ("0/2") rather than the panel header, or relabel the header count as "this step 0/2".

- [ ] **Q-L59 · Locker Room draws a progress bar for the maxed stat and none for the one that needs attention**
  - evidence: LOCKER ROOM card: "Chemistry — Elite 100/100" with a full-width green bar underneath; "Team Morale — 66%" (gold) with no bar at all, then "QB Wimberly" with a neutral-face glyph. The 100/100 value gets the visual weight; the 66% that is actually movable gets none.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2279-2301`
  - fix: Either give morale its own bar (the code comment notes the bar was reassigned to chemistry after it was found plotting morale under a Chemistry label — the fix removed morale's bar rather than adding a second) or drop both bars and let the two numbers sit as a matched pair.


### Draft war room

- [ ] **Q-L60 · The reaction toast covers the top three rows of the Big Board**
  - evidence: On 077 the MEDIA card sits directly on the table: row "#1 RT Nehemiah Abernathy 22 ELI Set Safe B–/A" is half visible behind its top hairline, and rows #2 and #3 are hidden entirely except their trailing club stamps "NE #7" and "TEN #4", which peek out to the right of the card. Same placement on 078. This is deliberate — the rail is pinned "inside the LEFT column and below that column's header" (DraftBroadcastRail.swift:154-171) and it is `.allowsHitTesting(false)` so taps still reach the rows — but the cost is the three highest-ranked names disappearing for the toast's dwell, repeatedly, on the surface the eye is scanning.
  - code: `dynasty/dynasty/UI/Draft/Components/DraftBroadcastRail.swift:154`
  - fix: Either shrink the card to the width it needs (the text ends at ~60% of the card) and float it right of the NAME column, or render reactions inline in the LIVE FEED rail that already has 222pt of empty space beneath it.

- [ ] **Q-L61 · Completed cells in the pick strip drop their pick number while upcoming cells keep theirs**
  - evidence: The strip on 077/078 reads "✓ ATL / RT TRUESDALE", "✓ IND / OLB JARAMILLO", "✓ LAR / DT HUBBELL", then "#17 MIA NOW", "#18 DEN", "#19 HOU", "#20 CIN". The three completed cells carry no slot number, so the reader has to cross-reference the board's right-hand column ("ATL #14", "IND #15") to learn which picks those were — on the one strip whose whole job is where the draft is.
  - fix: Prefix completed cells with their pick number the same way upcoming ones are: "#14 ATL ✓ / RT TRUESDALE".

- [ ] **Q-L62 · Two different reach magnitudes for pick #16 sit 300px apart with no reconciliation**
  - evidence: The reveal card reads "MY #63   -47 REACH" for Xander Hubbell. The LIVE FEED card immediately below reads "LAR reach for DT X. Hubbell / Consensus board had him #86 — taken 70 slots ahead of it." Both are correct (16−63 = −47 against the user's board; 86−16 = 70 against the media board, per `boardDelta` at DraftTickerPanel.swift:2539) but the chip's "-47 REACH" never names the board it is measured against, so the two numbers read as a contradiction.
  - code: `dynasty/dynasty/UI/Draft/Components/DraftTickerPanel.swift:2539`
  - fix: Print the yardstick inside the delta chip — "-47 vs MY BOARD" — or make the feed card quote the same board the reveal card quotes.


### Draft — on the clock

- [ ] **Q-L63 · The same countdown is printed two ways on one screen: "1:46" in the header and "106s left" in the bottom bar**
  - evidence: 080 header band, right edge: "⏱ 1:46" over a gold progress bar. 080 bottom bar, ~1500pt below it: "YOU ARE ON THE CLOCK — #19 / 106s left. Hand in a card from the board, or shop the slot to a club behind you." Same value, mm:ss in one place and raw seconds in the other, so the two never visibly agree.
  - code: `dynasty/dynasty/UI/Draft/Components/DraftStickyHeader.swift:1021; dynasty/dynasty/UI/Draft/Components/DraftControlBar.swift:341`
  - fix: `DraftStickyHeader` formats `"\(clamped / 60):\(String(format: "%02d", clamped % 60))"`; `DraftControlBar` interpolates `"**\(coordinator.clockSeconds)s** left"`. Share one formatter. mm:ss is the broadcast convention and is what the header already shows, so the bar should read "1:46 left".

- [ ] **Q-L64 · The pick-inventory pips are effectively invisible against the header plate**
  - evidence: 080 header band, right of the pick strip: seven hollow rectangles rendered as dark slate outlines on a near-black plate, followed by legible white text "0 spent · 7 left". draft_01 shows the same strip with two filled and five hollow beside "2 spent · 5 left". At the rendered size the unspent pips are barely distinguishable from the background, and the sentence next to them already states the count exactly.
  - fix: Either raise the unspent pip to a readable stroke (textTertiary at full opacity rather than a low-alpha outline) so the glanceable channel actually works, or drop the pips and keep the text — right now the graphic costs width and contributes nothing the adjacent label does not already say.


### Combine hub

- [ ] **Q-L65 · Two adjacent hub cards both render a "no games yet" placeholder**
  - evidence: DIVISION shows "Week 1 in ~26 weeks / Currently: Roster Review" and directly beneath it UPCOMING shows "Season starts after Roster Cuts" — roughly 250px of the hub's lower half saying the same thing twice, with a "Standings >" and a "Schedule >" link that are the only live content in either card.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1745`
  - fix: In the offseason, collapse the two into one card, and fill the DIVISION empty state with LAST season's final division table instead of a countdown — during roster building, "who I have to beat and by how much" is the decision-relevant fact, and the standings data already exists.

- [ ] **Q-L66 · One calendar block wears three names and two date formats on a single screen**
  - evidence: The rail header says "YOUR OFFSEASON", the phase block under it says "PRE-DRAFT · STEP 1 OF 4", and in MESSAGES the same moment is stamped two different ways in adjacent rows: "Offseason - The Combine, 2026" (hyphen, phase first, year last — `InboxEngine.dateLabel`) and "Season 2026 — Pre-Draft" (em dash, season first — `WeekAdvancer.emitGroupTransitionMessageIfNeeded`).
  - code: `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:5531`
  - fix: Route the group-transition message through `InboxEngine.dateLabel(week:season:phase:)` so there is one stamp format, and pick one word for the block — the rail, the stamps and the Scouting hub's "STAGE 1 OF 6" should not need reconciling.

- [ ] **Q-L67 · The ACTIVE Scouting tile is ~40% empty on the phase it is active for**
  - evidence: The SCOUTING card is 324 px tall in the crop; its content ("#1 Kenji Hopewell", "QB — Oklahoma", "350 total OFF 196 DEF 148") stops at 190 px, leaving ~130 px of blank card under a gold ACTIVE chip. The card is stretched to match the OWNER card beside it, which fills its height. This is the phase the player is standing in ("THE COMBINE — NOW") and the tile shows four facts, none of them a decision.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2117`
  - fix: Fill it with what the stage actually costs and gives: scouting weeks left ("1 spent · 5 left"), scouting budget remaining, and the stage counter — all values the Scouting hub already computes and the player currently has to tap through to read.

- [ ] **Q-L68 · The DIVISION card contains no division data and restates the rail**
  - evidence: A full-width card headed "DIVISION" with a "Standings >" button contains exactly one row: "Week 1 in ~24 weeks / Currently: Combine". No team, record or standing appears. "Currently: Combine" repeats the rail's "THE COMBINE — NOW — Feb–Mar" 1,500 px to its left, and the ~24 is a hardcoded per-phase constant, not a computed date.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:3259`
  - fix: In the offseason, either collapse the card to its "Standings" link, or show last season's final division table — which is the thing a manager actually wants during the Combine — instead of a countdown the rail already gives.


### Week hub (regular season)

- [ ] **Q-L69 · Phase rows run backwards in time: "Sep–Jan", then "Oct", then "Jan"**
  - evidence: The rail lists REGULAR SEASON "Sep–Jan" (NOW), then below it TRADE DEADLINE "Oct", then PLAYOFFS "Jan". Read top to bottom as a timeline, the second entry starts a month after the first began and inside its range, and the third duplicates the first's end month.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:963-980`
  - fix: `phaseDate` returns "Sep–Jan" for `.regularSeason` while its two sub-phases return points inside that span. End the regular season at "Sep–Dec" and label the playoffs "Jan–Feb", or drop the date on any phase that is contained by the one above it.

- [ ] **Q-L70 · "42 expiring" with no denominator and no action available for 18 weeks**
  - evidence: CONTRACTS shows an amber "42 expiring" chip, then "Re-sign window opens in the offseason", then three names (CB Goddard 88 $12.8M, QB Wimberly 86 $31.0M, DT Pankhurst 83 $795K) and "View all in Salary Cap →". 42 out of what is never stated, and the tile's own copy says you cannot act on it yet.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2604-2612, 3472`
  - fix: The count is `players.filter { $0.contractYearsRemaining <= 1 }.count` over every Player row stamped with the team id (active roster + practice squad), so print the denominator — "42 of 69 expiring" — and the cap consequence ("$118M coming off the books"), which is the number that actually informs in-season trade and extension thinking. Without a denominator the chip reads as an alarm the player cannot size.


### Advance confirm sheet

- [ ] **Q-L71 · The "Skip your Week 1 game?" popover offers exactly one answer and no visible way out**
  - evidence: 700_season_002 and 740_season_044: the sheet asks "Skip your Week 1 game vs JAX? It will be simulated." / "You haven't coached this game yet. Advancing plays it for you and the result is final." and offers a single button, "Sim & Advance". The source declares `Button("Cancel", role: .cancel)`, but iPadOS suppresses the cancel row in popover-style confirmation dialogs, so a question framed as yes/no ships with only "yes" on screen and an invisible tap-outside dismiss.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:598-608`
  - fix: Do not rely on `.confirmationDialog`'s cancel on iPad. Present a small custom popover/alert with two explicit buttons — "Coach it" (the decision the copy is warning you about) and "Sim & Advance" — or use `.alert`, which keeps the cancel button on iPad.


### Weekly press conference

- [ ] **Q-L72 · The legend under the standing strip lists its three items in reverse tile order and names a tile that doesn't exist**
  - evidence: The tiles read, left to right: "19 LEGACY", "-14 MEDIA", "91% SATISFACTION". The legend directly beneath reads "Owner affects job security · Media shapes the narrative · Legacy affects career rating" — reverse order, and its first term "Owner" never appears as a tile label (the tile says SATISFACTION). Only the middle item lines up with the thing above it. Same mismatch on 740_season_054.png and 740_season_058.png.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:585-611`
  - fix: Order the legend Legacy · Media · Owner to match the tiles and rename the term to the tile's own word ("Satisfaction affects job security"), or better, put each explainer under its own tile so the mapping is positional and needs no reading order at all.


### Press reaction

- [ ] **Q-L73 · Markdown emphasis in the action-bar explainer is parsed away and renders no bold**
  - evidence: 007's explainer reads "Pick a line. Nothing is said until you say it." — no asterisks (so the markdown was parsed) but "say it" is the same weight as the rest. Measured per-word ink density across the line: "Pick" 7.94 ink/px, "said" 8.21, "until" 7.59, "you" 7.62, "say" 7.61, "it." 6.95 — "say" is neither heavier nor wider than surrounding body text. The call site is message: "Pick a line. Nothing is said until you **say it**." (PressConferenceView.swift:1171) and DSActionBar.swift:31-32 documents "Markdown is honoured, so a call site emphasises the load-bearing nouns with **…**". The copy exists to point at the button literally named "Say it", and the pointer is invisible.
  - code: `dynasty/dynasty/UI/Common/DSActionBar.swift:113`
  - fix: The explainer label is Text(LocalizedStringKey(message)).font(DSType.text(DSType.Size.body, .medium)) at DSActionBar.swift:113, and DSType.text applies .monospacedDigit() when prose is false (DSTokens.swift:175-178). Try DSType.text(..., prose: true) first; if the emphasis still drops, build an AttributedString and set an explicit bold font on the strong run. This affects every action bar in the app, not just the presser.

- [ ] **Q-L74 · CONFIDENT and FUNNY get near-identical yellow rails, defeating the stated purpose of the tone tint**
  - evidence: On 007 the CONFIDENT card's 4pt left rail samples RGB(174,148,74) and its chip text (201,169,78); the FUNNY card's rail samples (202,157,14) and its chip text (234,179,8). Two of the three options are the same yellow. The code's own comment says the tinted stroke exists "so the cards can be pre-scanned by personality" (PressConferenceView.swift:866-867), and toneColor maps .confident to accentGold and .funny to warning (lines 1727-1735) — the same gold that is also the primary CTA, the "Picked" tick, the prompt-card border, the outlet name and the explainer rule on this screen.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1727`
  - fix: Move .funny off the amber warning token to a distinct hue (violet or teal), and stop spending accentGold on a tone — reserve gold for the commit affordance and the prompt, which is what the screen's own hierarchy rules say it is for. Five tones need five separable hues or the rail is decoration.


### Week hub (week 18)

- [ ] **Q-L75 · Recap footer links are blue in an otherwise gold-accented app**
  - evidence: The footer shows a gold "Continue" button above two blue-tinted links, "Full Standings" and "League News"; the section icons on the same screen are blue too, while every accent on the hub screens (700/720) — YOUR SEASON, Advance button, tile titles, "View all in Salary Cap →" — is gold.
  - code: `dynasty/dynasty/UI/News/RoundResultsView.swift:44 and UI/Career/CareerDashboardView.swift:746-757`
  - fix: Keep gold as the single primary (Continue) and render the two secondary links in `textSecondary` with a gold chevron, matching the hub's "News" / "View All" nav-link treatment, which the dashboard code explicitly chose so gold stays the one commit.


### Press reaction

- [ ] **Q-L76 · "WHAT IT ACTUALLY COST" heads a row that is four-fifths profit**
  - evidence: 048's reveal reads "WHAT IT ACTUALLY COST" over "OWNER +1 · MORALE +8 · FANS -5 · MEDIA +7 · LEGACY +2" — four of the five pills are gains, in green. The bar underneath repeats the framing: "ON THE RECORD — That is what ran, and what it cost."
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1060`
  - fix: "WHAT IT MOVED" or "WHAT IT DID" — neutral, and true in both directions; keep "cost" for the summary's net verdict line. Also note the pill set changes shape between questions (060 drops LEGACY entirely because `if effects.legacyPoints != 0` at PressConferenceView.swift:1091 hides it), so the ledger is not a stable set of columns to scan across a session.


### Press session summary

- [ ] **Q-L77 · Identical headline on all three sessions — already fixed in the uncommitted working tree, do not re-file**
  - evidence: All three screens open with the same headline, "The media sees a steady, professional operator", across three different sessions (2D+1H, 1D+1H, 1D+1H+1C) and three different ledgers — including 740_season_050 where FANS reads -9. The build under test also has no MEDIA column in WHAT CHANGED and no media clause in the cost line, so the media delta the headline claims to report is invisible. All three are already repaired by an uncommitted edit in the working tree: mediaOutcomeHeadline(tone:media:) replaces mediaPerceptionLabel(for:) at PressConferenceView.swift:1253/1737-1766, a ("Media", effects.mediaPerception, "rep → rep") cell is added at 1371, a "Media reputation X → Y · label" line at 1263, and mediaPart at 1551. The screenshots are from a pre-fix binary.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:1253`
  - fix: Nothing to do beyond rebuilding and re-shooting these three screens to confirm — but note the fix inherits the dominantTone tie-break defect filed above, so with 740_season_061's 1-1-1 split the new headline will pick its tone at random.


### Advance confirm sheet

- [ ] **Q-L78 · Inbox badge is clamped to "99" with no "+", contradicting the message count on the same screen**
  - evidence: 740_season_052: the toolbar envelope badge reads "99" while the MESSAGES card two-thirds down the same screen reads "186" (and "181 more messages" under five rows). 740_season_044: badge "99" vs MESSAGES "181". Only 700_season_002, where the real count is 82, agrees with itself (badge 82, card 82).
  - code: `dynasty/dynasty/UI/Common/TopNavigationBar.swift:200-212`
  - fix: `Text("\(min(unreadInboxCount, 99))")` clamps without a suffix. Render "99+" past the cap (the accessibility label already says the true number), or widen the badge and print the real value.

- [ ] **Q-L79 · DEBUG "Skip → FA" chip renders at full brightness while it is disabled for the whole regular season**
  - evidence: All three screens show the top-of-rail strip "🔧 DEBUG   ▶| Skip → FA" with the chip in full gold on a gold-tinted capsule — identical styling to the live "Depth Chart" / "Game Plan" chips below it. The code disables it whenever `currentPhase == .regularSeason || .tradeDeadline`, which is exactly the phase all three screens are in, so it is an enabled-looking control that does nothing on tap.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:2966-3000 (`.disabled(...)` with no styling branch)`
  - fix: Give the disabled state a visual: dim to `textTertiary` on `backgroundTertiary` and change the label to "Skip unavailable in-season". (DEBUG-gated, so player-facing impact is nil — but it is the affordance that QA taps first.)


### Weekly press conference

- [ ] **Q-L80 · The step header and its meter disagree about whether the current question counts as spent**
  - evidence: On 740_season_058.png the band reads "QUESTION 2 OF 3" on the left and "2 spent · 1 left" on the right — while question 2 is the one on screen and its answer has just been revealed. On 720_season_005.png the same band reads "QUESTION 1 OF 3" with "0 spent · 3 left", so on the first screen 3 remain while you are already standing on one of them. The headline counts the current question as in-progress (currentQuestionIndex + 1); the meter counts it as spent only after commit (selectedIndices.count), so the pair is briefly self-contradictory on every question.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:441-449`
  - fix: Pick one counting rule for the band. Simplest is to make the headline follow the commit state too — "QUESTION 2 OF 3 · ANSWERED" once selectedResponseIndex is set, which also removes the oddity of a header that still says you are ON a question whose primary button reads "Next question".

- [ ] **Q-L81 · After committing, the chosen card still offers "Preview headline" for a headline that has already run and is printed below it**
  - evidence: The committed CONFIDENT card keeps its "Preview headline ⌄" button while the reveal panel below already prints "National Sports Network: \"Astronauts commit to the ground game behind Ramiro Maddocks.\"" Both draw the same string — headlinePreviewSection renders response.mediaReaction, and commitPendingResponse sets reactionText = response.mediaReaction. The word "Preview" is also false at that point: the headline is past tense. The same button on the two un-chosen cards is .disabled(isDisabled) yet still drawn with a full capsule border, so it reads as tappable and does nothing.
  - code: `dynasty/dynasty/UI/Career/PressConferenceView.swift:851-856,1005`
  - fix: Hide headlinePreviewSection entirely once selectedResponseIndex != nil — the chosen card's copy is duplicated by the reveal, and the un-chosen cards' buttons are inert. If the un-chosen previews are worth keeping as a what-if, keep them enabled and relabel them ("See the headline you avoided") rather than leaving a live-looking control that is switched off.


### Press reaction

- [ ] **Q-L82 · Straight quotes in the reveal headline, curly quotes everywhere else on the same screen**
  - evidence: 060's reveal renders Local News 9: "Tight-lipped approach from Astronauts front office." with straight double quotes, while the prompt above renders “How's the mood in the locker room?” and the response renders “I'll keep that between us and the locker room.” with curly quotes. Same on 048: "Astronauts promise answers up front after 5-sack afternoon." The view wraps quotes with \u{201C}/\u{201D} (PressConferenceView.swift:764, 851) but the authored mediaReaction strings embed literal \" (e.g. PressConferenceEngine.swift:459).
  - code: `dynasty/dynasty/Engine/Media/PressConferenceEngine.swift:459`
  - fix: Replace the literal \" in the mediaReaction content table with \u{201C}/\u{201D}, or strip and re-wrap in the view. It is the one place on the screen where the typography breaks, and it lands on the line the whole reveal is built around.


### Playoff hub

- [ ] **Q-L83 · WEEK PREP card is ~75% empty**
  - evidence: "Week 19 prep" + "General vs opponent focus" occupy the top ~45px of a card roughly 235px tall (its height is matched to the OWNER card beside it, which carries a portrait, an archetype chip, a job-security meter and a goal row). Same void on 064 ("Week 20 prep") and 065 ("Week 21 prep").
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1680`
  - fix: gameWeekPrepTile (CareerDashboardView.swift:1680) prints two static-ish lines. It should say which focus is currently set and what it is worth this week — the engine models it (OpponentPrepWeek, prepFocusDelta contested by both staffs), so the card can show the actual selection and its edge instead of the generic "General vs opponent focus".

- [ ] **Q-L84 · Staff card shows a green "complete" tick over 58% of the budget unspent**
  - evidence: "HC You · 23/23 Staff ✓" with a full green bar, and beneath it "Budget $14.7M / $35.2M". The only verdict on the card is the tick on headcount; $20.5M of unspent staff money gets no comment at all.
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1995`
  - fix: Full slots is not the same as a good staff. Grade the money too — "23/23 filled · $20.5M unspent — league average $28M" — or state what happens to the surplus (rolls over? lost at the league year?), because right now the underspend reads as an unambiguous win when it may be the club's biggest missed upgrade.

- [ ] **Q-L85 · The season band loses every week number once the postseason starts**
  - evidence: The six visible slats read "✓ VS NYJ / W 36–13", "✓ @ NE / W 34–12", "✓ VS CLE / W 31–20", "✓ VS IND / W 30–9", "✓ VS CIN / L 32–38", "✓ VS PIT / W 36–31" — no week numbers on any of them, and the head reads "2027 SEASON · POSTSEASON" rather than a week. Since the band is horizontally scrolled and cropped, there is no anchor to count from: you cannot tell whether the CIN loss was Week 13 or Week 17.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:683`
  - fix: SeasonWeekBand.slats forces every regular-season slat to `.done` when inPlayoffs, and DSSlatBand replaces the index numeral with a checkmark on a done slat (DSSlatBand.swift:683). For the postseason band, keep the numeral and use the result tint for the W/L signal, or put the week into the result line ("W18 · W 36–31").


### Season end

- [ ] **Q-L86 · Future-phase preview rows clip at one line — "Read the Showcase & declaration rep…"**
  - evidence: "Read the Showcase & declaration rep…" is clipped identically on 066, 067 and 069 under REVIEW ROSTER. Every other row in that block fits, so one row alone loses its last word ("reports").
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:865`
  - fix: `previewTaskRow` sets `.lineLimit(1)` with no `.minimumScaleFactor`. Add `.minimumScaleFactor(0.9)` or allow two lines — the rail has vertical room to spare (see the dead-space finding) and the string misses by roughly one word.

- [ ] **Q-L87 · The sheet states its own title twice, 90 pt apart**
  - evidence: The navigation bar reads "Coaching Staff Review" (inline, centred, between Cancel and Advance). Directly beneath it the first content block reads "COACHING STAFF REVIEW" in gold, black weight, with a gold rule under it. Two identical titles occupy the top ~110 pt of a 654 pt sheet, and the section immediately below adds a third heading, "COACHING STAFF".
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:4912`
  - fix: Drop `headerSection` — the navigation title already names the sheet, and the gold rule can move up to sit under the toolbar. That reclaims roughly 40 pt, which is most of what it would take to stop the sheet slicing through "SCHEMES & EXPERTISE" at the bottom.

- [ ] **Q-L88 · Four progress counters with four different denominators stacked in one 300 pt rail**
  - evidence: Reading top to bottom in the left rail: "YOUR OFFSEASON  0/2", then "COACHING CHANGES … OFFSEASON · STEP 1 OF 2", then "REVIEW ROSTER … OFFSEASON · STEP 2 OF 2", then "THE COMBINE … PRE-DRAFT · STEP 1 OF 4", "FREE AGENCY … PRE-DRAFT · STEP 2 OF 4", and finally "+ 9 more phases". The two 2s at the top mean different things — the header's is tasks completed in the current phase, the card's is phases within the offseason group — and they sit 110 pt apart with no label distinguishing them.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:126`
  - fix: Label the header count for what it counts ("0/2 tasks") and drop "STEP n OF m" from the phase cards, since the rail's vertical order already conveys sequence and the group name already conveys the grouping. A player glancing at this rail should be able to answer "how much is left" in one read; right now there are three candidate answers on screen.

- [ ] **Q-L89 · Owner's opening message uses a programmer's double hyphen in the subject line**
  - evidence: The inbox row reads "Yosef Estabrook / Welcome -- Roster Assessment Needed" with two ASCII hyphens where an em dash belongs. The string is hardcoded identically in three files: InboxEngine.swift:119 (the live one), plus InboxView.swift:360 and MessageDetailView.swift:267 as preview fixtures. Elsewhere in the same feed the app uses a proper em dash ("Season 2027 — Offseason"), so this is inconsistent within one list.
  - code: `dynasty/dynasty/Engine/Media/InboxEngine.swift:119`
  - fix: Replace with \u{2014}: "Welcome — Roster Assessment Needed". While in there, collapse the three copies to one constant — a subject line duplicated across an engine and two preview fixtures will drift.


### Training camp — position battles

- [ ] **Q-L90 · Roughly the bottom sixth of a 13-inch portrait canvas is empty ground below the class card**
  - evidence: The class card closes just under the last row ("R7 · #252  K  Roman Nadeau  C−/B ↘ 53") and everything from there down to the "Open Camp" footer bar is flat empty background — no content, no summary, no legend. Identical on camp_03 and camp_06. Meanwhile the 11 rows above are packed at 8pt vertical padding with two designed sub-fields (college, projection) rendering as nothing, so the screen is simultaneously cramped and empty.
  - code: `dynasty/dynasty/UI/Draft/RookieClassRevealView.swift:463`
  - fix: Spend the space on what the screen is for: a class-shape summary (best/worst vs band, count above/at/below the report, total rookie cap hit — the salary is already on every row), or the missing legend. On a canvas this tall the reveal could also run two columns of rows rather than one narrow measure.

- [ ] **Q-L91 · The close X is a ~28pt hit target, under the 44pt minimum**
  - evidence: The header's only secondary control is the xmark.circle.fill at top-right, rendered at `.font(.system(size: 28))` inside a `.buttonStyle(.plain)` Button with no frame or contentShape (RookieClassRevealView.swift:490-497), so the tappable area is the ~28pt glyph itself. The primary "Open Camp" below is a correct 50pt-tall bar, which makes the inconsistency plain on the same screen.
  - code: `dynasty/dynasty/UI/Draft/RookieClassRevealView.swift:490`
  - fix: Wrap the icon in `.frame(width: 44, height: 44).contentShape(Rectangle())`. The same pattern is worth auditing across other modal headers using this icon.


### Training camp — practice picker

- [ ] **Q-L92 · "YOUR OFFSEASON  0/6" sits directly above "Phases complete (9)" — the counter is the current phase's, not the offseason's**
  - evidence: The rail header reads "YOUR OFFSEASON" with "0/6" on the same line, and the very next row reads "Phases complete (9)". Read top-down that is "you have done 0 of 6 offseason things" immediately contradicted by "9 phases are complete". The 0/6 is TimelineTasksPanel.taskProgress for the CURRENT phase only — Training Camp lists exactly six tasks (Set training focus, Cut to 75, Review camp grades, Resolve position battles, Monitor workload, Check preseason storylines), which is where the 6 comes from.
  - code: `dynasty/dynasty/UI/Common/TimelineTasksPanel.swift:923`
  - fix: Move the pill onto the TRAINING CAMP header row where its denominator lives, or label it "This phase 0/6". The section header should carry a phase-agnostic word or the offseason-wide total.

- [ ] **Q-L93 · Chip labels are unexpanded and unitless — "LR", "Scheme +3", "Inj +0%" with no scale**
  - evidence: Every card's decision basis is three chips: "Scheme", "LR", "Inj". "LR" is never expanded on the chip; the reader has to infer it from the body copy "locker-room implications". "Scheme +3" gives no denominator (it is +3 on a 0–100 schemeFamiliarity, applied to the attendee's single best scheme only — VoluntaryWorkoutEngine.swift:66-72). "Inj +0%" is a risk boost, not an absolute risk, so "+0%" reads as "zero injury risk" rather than "no change". Three of the four options show "Inj +0%", which makes the injury axis look like a non-factor.
  - code: `dynasty/dynasty/UI/Camp/VoluntaryWorkoutPrompt.swift:89`
  - fix: Expand the chip to "Locker Room", suffix scheme with its scale ("Scheme +3 fam"), and phrase injury as a delta ("Injury risk ±0" / "+2%"). Add the modelled-but-hidden participation number as a fourth chip — it is the one figure that distinguishes the options.


### Training camp — training plan

- [ ] **Q-L94 · The rail reads "PRESEASON — PRE SEASON · STEP 3 OF 4": the group and one of its members share a name**
  - evidence: The left rail lists "TRAINING CAMP … PRE SEASON · STEP 2 OF 4", then "PRESEASON … PRE SEASON · STEP 3 OF 4", then "ROSTER CUTS … PRE SEASON · STEP 4 OF 4". `SeasonPhaseGroup.preSeason` contains `.otas, .trainingCamp, .preseason, .rosterCuts`, so the phase called "Preseason" is step 3 of a group also called "Pre Season", printed by `"\(phase.group.displayName) · step \(current) of \(total)"`. Two spellings of one word, nested, meaning different things.
  - code: `dynasty/dynasty/Domain/Enums/SeasonPhase.swift:93`
  - fix: Rename the group to "Summer" or "Camp to Kickoff" (or the phase to "Exhibition Games") so the step counter never repeats the phase name directly beneath it.

- [ ] **Q-L95 · Gold is spent on a dozen elements, so the one real primary action does not win**
  - evidence: Gold appears on: the HOU badge, "YOUR OFFSEASON", "TRAINING CAMP", the NOW pill, the "Open Training Plan" button, the ROSTER tile's "ACTIVE" pill and gold border, the "17 expiring" pill, the "85 LEGACY" tile, "Set focus", "Monitor camp load", the verdict card border, and most tile icons. The genuinely actionable gold ("Open Training Plan") is visually indistinguishable from two static captions and a decorative status pill.
  - fix: Reserve the solid gold fill for the single primary action on the screen and for the one required task in the rail; move status pills ("ACTIVE", "17 expiring") and tile captions to a neutral or semantic colour. The reference here is FM's squad screen, where exactly one control per screen carries the accent.


### Training camp — training focus

- [ ] **Q-L96 · Preset chips are ~23pt tall — roughly half the 44pt minimum touch target**
  - evidence: The "Balanced / Scheme Heavy / Camp Hard / Recovery Mode" chips measure ~33 px of the 2000 px-tall render, i.e. ~23pt on a 1024×1366pt canvas. In code they are `.font(.caption.weight(.semibold))` with only `.padding(.vertical, 6)` — about 12pt of text plus 12pt of padding. They are the fastest path through this screen and the hardest thing on it to hit.
  - code: `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:140`
  - fix: Raise vertical padding to 12–14pt, or add `.contentShape(Rectangle()).frame(minHeight: 44)` on the button so the tap area meets HIG without changing the visual chip size.


### Roster cuts — cut to 75

- [ ] **Q-L97 · The meter says "0 spent · 12 left" and never names what is being spent**
  - evidence: camp_10's band meter reads "0 spent · 12 left", camp_11's reads "12 spent · 0 left". Neither states the unit. The component is given one — DSResourceMeter(spent:total:unit: "cuts") — but unit is only used in accessibilityText and never rendered visually. "Spent" is also the wrong verb for a selection that has not been committed (see the state-mixing finding on camp_11).
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:326`
  - fix: DSResourceMeter.valueLine (DSSlatBand.swift:326) is "\(spent) spent · \(left) left". Render the unit: "12 cuts left" or "0 of 12 cuts made". It is a shared component, so the same nounless line appears on the scouting band and every other DSSlatBand surface.


### Depth chart after Auto-Set

- [ ] **Q-L98 · An unexplained bolt-and-bar indicator appears on 9 of 12 rows with no legend anywhere on screen**
  - evidence: A small bolt glyph over a ~20×3 pt bar sits left of the OVR badge on Kaleo Hinsdale, Waylon Hopewell, Brixton Yarborough, Ezekiel Ferrante, Nehemiah Lockridge, Wade Braithwaite, Odalric Crisanti, Kester Vandenberg and Alonso Hinsdale, and is absent on Davion Maddocks and Alaric Bascomb. Nothing on the screen says what it is or which direction is good. It is fatigue on an inverted colour ladder (`Color.forRating(100 - value)`), and the explanation exists only as a VoiceOver string: "Fatigue \(value) percent, lower is better". At 3 pt the fill level is not readable at all — only the glyph tint carries information.
  - code: `dynasty/dynasty/UI/Roster/DepthChartView.swift:809-834`
  - fix: Put a one-line key next to the existing "4 groups · 12 positions" row — "⚡ fatigue · lower is better" — and grow the bar to at least 28×5 pt, or replace it with the number ("⚡24") which is legible at this density and comparable between two rows at a glance.

- [ ] **Q-L99 · Group header shows a green "✓ 1/1" directly above an empty slot row**
  - evidence: "Quarterbacks  ✓ 1/1  AVG 73" in green, and in the card immediately below: "STARTER Davion Maddocks 73", "BACKUP Kaleo Hinsdale 53", "3RD STRING  ⊕ Tap to assign". `filledStarters` counts only index 0 of each slot, so the only completeness signal on the header is blind to depth — which is the number the cut decision actually needs, since a 1-deep room is the room a September injury ends.
  - code: `dynasty/dynasty/UI/Roster/DepthChartView.swift:505,536-550`
  - fix: Keep the starter check but add depth beside it — "✓ 1/1 · 2 deep" — or amber the pill when any room in the group has no backup. On camp_14 that would flag Quarterbacks (2 QBs for 3 slots) as the genuine risk it is.

- [ ] **Q-L100 · "3RD STRING" wraps to two lines, knocking its reorder chevron and the empty row's content out of alignment**
  - evidence: On the QB and RB cards "STARTER" and "BACKUP" render on one line while "3RD / STRING" stacks over two. On the RB card the 3rd-string up-chevron sits above the label's vertical centre, whereas the BACKUP row's up/down pair is centred. On the QB card the empty row's text "Tap to assign" starts ~44 px right of where the player names "Davion Maddocks" and "Kaleo Hinsdale" start, because the ⊕ glyph is inserted into the name column instead of the label column.
  - code: `dynasty/dynasty/UI/Roster/DepthChartView.swift:640-660,775-787`
  - fix: Use "3RD" (matching the "STARTER"/"BACKUP" single-line rhythm) or widen the label column to fit "3RD STRING" on one line. Move the ⊕ into the reorder-chevron column so "Tap to assign" left-aligns with the player names above it.


### Roster cuts — cut to 53

- [ ] **Q-L101 · Duplicate first names in a 14-row window, and an initials avatar that collides with a position code**
  - evidence: "MLB Callum Abernathy" and "DE Callum Bonaventure" sit two rows apart; "SS Norbert Vestergaard" and "WR Norbert Bascomb" three rows apart. Callum Bonaventure's avatar reads "CB" — the same two letters as the CB position badge on Wade Littlefield's row directly above him. Same on cuts_02. On the hub the surname-only battle row "DT Bolliger vs Braithwaite" reads as the WR the same screen lists as "WR Braithwaite 93 $54.0M" and "MVP Wade Braithwaite 93".
  - code: `dynasty/dynasty/UI/Career/CareerDashboardView.swift:1399`
  - fix: Suppress repeats of a first name within a club in the name generator, and disambiguate surname-only displays (positionBattleRow uses `map(\.lastName)`) with the first initial when the club carries two of that surname.

- [ ] **Q-L102 · "12 more to release" is stated three times in three different phrasings in one viewport**
  - evidence: Band meter: "0 spent · 12 left". Active slat: "65 on the roster · 12 more to release". Action bar: "You are 12 over the 53-man limit. Tap a player to mark him for release." Plus "CUT DAY 3 OF 3" and the slat "3 CUT TO 53" both stating the stage. Same on cuts_02.
  - code: `dynasty/dynasty/UI/Camp/RosterCutView.swift:190`
  - fix: Keep the instruction in the action bar (it is the one that says what to do) and let the band carry the stage plus the pips only. `meter` and `currentSubcaption` are both derived from `requiredCuts`/`remaining` — one of them can go.

- [ ] **Q-L103 · The 12 unspent meter pips render as an indistinct dark smear next to "0 spent · 12 left"**
  - evidence: Top right of the band, between the ladder and the words "0 spent · 12 left", is a run of barely-visible dark rectangles split by a faint tick. At "0 spent" every pip is empty, so the meter conveys nothing that the words beside it do not. Same on cuts_02.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:408`
  - fix: An unspent pip is `fill: .clear` with a 1pt Color.surfaceBorder stroke on a 5x11pt slat shape — near-invisible on backgroundPlate. Fill unspent pips with a low-opacity textTertiary instead of relying on a hairline stroke, or drop the pip rail below ~8 total and keep only the value line.


### Preseason — training focus

- [ ] **Q-L104 · The commit bar says "this week's development pass" in a phase whose header deliberately refuses to call itself a week**
  - evidence: The action bar reads "SAVE — PRESEASON FOCUS / Banks 34/33/33 tactical, physical and technical for this week's development pass." The title is "PRESEASON FOCUS" precisely because `headerTitle` avoids weeks outside the regular season — its comment says "'Week 0' reads like a bug during the offseason" (TrainingPlanView.swift:106-117) — but the explainer two lines below still anchors the commit to "this week", and the plan is keyed on `career.currentWeek`, which is the very value the header would not print.
  - code: `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:88-117`
  - fix: Make the explainer read the same phase-aware string: "…for the preseason development pass" outside the regular season, "…for Week N" inside it.


### Roster cuts — cut to 65

- [ ] **Q-L105 · The number 10 is restated four times in the chrome while the pip rail renders as ten empty hairline outlines**
  - evidence: On pre_03/pre_15 the same fact appears as "75 on the roster · 10 more to release" (slat 2), a rail of ten faint outlined pips, "0 spent · 10 left" (meter text), and "You are 10 over the 65-man limit. Tap a player to mark him for release." (action bar). Four statements of how many, zero indication of which. On pre_17 the meter is gone entirely and the band head is "CUT DAY 2 OF 3 · BANKED" with the whole right two-thirds of the bar empty.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:408-421; RosterCutView.swift:185-200`
  - fix: An unspent pip is drawn with `.clear` fill and a 1pt surfaceBorder stroke at 5×11pt, so at spent=0 the rail carries no readable signal at all. Either drop the meter on this screen (the slat subcaption and the action bar already say it twice) or give unspent pips a visible fill, and use the freed band-head width for something the screen does not otherwise show — cap space after the plan, or the position rooms at their floor.


### Preseason — slate

- [ ] **Q-L106 · Inbox badge caps at "99" with no "+", so the number shown can be false**
  - evidence: The top bar shows a red badge reading "99" on all three shots. TopNavigationBar.swift:201 is `Text("\(min(unreadInboxCount, 99))")` — the count is clamped with no overflow marker, so 250 unread and exactly 99 unread render identically. The accessibility label (:212) correctly speaks the true count, so VoiceOver and the visual disagree.
  - code: `dynasty/dynasty/UI/Common/TopNavigationBar.swift:201`
  - fix: Render `unreadInboxCount > 99 ? "99+" : "\(unreadInboxCount)"`. Separately, 99 unread messages sitting on the bar through the whole preseason suggests the inbox is generating more than a player will ever read — worth a look at what is filling it.

- [ ] **Q-L107 · Band slats print their number twice: "1 GAME 1", "2 GAME 2", "3 GAME 3"**
  - evidence: Each slat shows an index chip and a title that repeat the same digit — on screen: "1 GAME 1", "2 GAME 2", "3 GAME 3". `PreseasonFlowBand.slats` passes `index: "\(game)"` (PreseasonFlowBand.swift:106) alongside `title: title(game: game)` where `title(game:)` returns "Game \(game)" (:52). The sibling band this file says it was "modelled on line for line" does not have the problem, because its titles are words: FAFlowBand.swift:89 pairs `index: "\(i + 1)"` with "Final Push", "New League Year", "Cap Review" (FAFlowBand.swift:37-45).
  - code: `dynasty/dynasty/UI/Camp/PreseasonFlowBand.swift:52`
  - fix: Title the slats by what each exhibition IS rather than by its number — the opponent is already persisted on `PreseasonMatchup.opponentAbbreviation`, so "1 vs LV", "2 at DAL", "3 vs KC" costs nothing, removes the duplication, and turns three identical slats into a readable slate.


### Preseason — game 1

- [ ] **Q-L108 · Flow band contradicts itself: "1 spent · 2 left" while slat 1 is still the current step and shows no result**
  - evidence: pre_08 header reads "PRESEASON · GAME 1 OF 3" with the meter "1 spent · 2 left", yet slat 1 renders as the current step — "1  GAME 1 / Read the tape before the next one" — with no check and no score, even though 44–27 is printed three times below it on the same screen. pre_10 shows the same slat correctly as "✓ GAME 1 / W 44–27". The outcome is passed to the slat on both screens but `DSSlatBand` only prints it when `slat.state == .done`.
  - code: `dynasty/dynasty/UI/Common/DSSlatBand.swift:726 (outcome only rendered for .done); dynasty/dynasty/UI/Camp/PreseasonView.swift:151-166 (reviewing keeps the slat .current)`
  - fix: Let a `.current` slat in the `.reviewing` stance print its outcome alongside the subcaption ("W 44–27 · read the tape"), so the meter's "1 spent" and the slat agree.

- [ ] **Q-L109 · Inbox badge clamps to "99" with no overflow indicator**
  - evidence: All three screens show a red "99" on the envelope in the top nav. The badge is `Text("\(min(unreadInboxCount, 99))")`, so it reads as an exact 99 whether there are 99 unread or 900 — while the accessibility label reports the true count ("Inbox, N unread"), meaning the visual and spoken values disagree above 99.
  - code: `dynasty/dynasty/UI/Common/TopNavigationBar.swift:200-212`
  - fix: Render "99+" when the count exceeds 99, matching the accessibility label.

- [ ] **Q-L110 · The sheet restates the card behind it almost verbatim — the score appears three times and the mover tally twice**
  - evidence: On pre_08 "44–27" appears as the card headline, as the sheet headline "Won 44–27 vs Las Vegas", and as the sheet's SCORE chip — three times within 800 px. The mover tally is stated twice in different words: card "4 helped their case, 1 hurt his." and sheet "4 of the men fighting for a spot helped their case and 1 hurt his." pre_10 repeats the pattern: "14–40" in the card, in "Lost 14–40 at Detroit", and in the SCORE chip, with "W 44–27" in the band above making four scores on one screen.
  - code: `dynasty/dynasty/UI/Camp/PreseasonView.swift:400-447 (score card + reviewSummary); dynasty/dynasty/UI/Camp/PreseasonRecapSheet.swift:483-486, :536-543`
  - fix: Drop the SCORE chip from the sheet — the headline already carries the score and the W/L — and let the card behind own the tally so the sheet's message can spend its two sentences on the thing the card cannot say.


### Preseason — game 3

- [ ] **Q-L111 · Inbox badge silently clamps at "99" with no overflow marker, contradicting its own VoiceOver label**
  - evidence: All three screens show a red "99" badge on the envelope in the top bar. The code renders `Text("\(min(unreadInboxCount, 99))")` (TopNavigationBar.swift:201) — no "+" and no other overflow treatment — while the accessibility label three lines down reads `"Inbox, \(unreadInboxCount) unread"` with the true, unclamped count. So a sighted player is told there are exactly 99 unread items and a VoiceOver user is told there are, say, 340. A badge that reads as an exact figure but is a ceiling is a number that lies.
  - code: `dynasty/dynasty/UI/Common/TopNavigationBar.swift:201`
  - fix: Render "99+" when `unreadInboxCount > 99` (and mirror it in the accessibility label, or keep the true count there deliberately and say so). One-line change at TopNavigationBar.swift:201.
