# Skipatut löydökset — medium/low korjausaallot

| syy | kpl |
|---|---|
| peruttu / jo korjattu | 70 |
| toisen tiedostossa | 35 |
| muu | 33 |
| feature-kokoinen | 15 |
| balanssi | 15 |

**Skipattuja yhteensä: 168**


## peruttu / jo korjattu

- **Position filter chips carry no counts, so positional minimums are invisible**
  - The finding's premise is stale — the chips already carry the room's live size (`Text("\(count(in: group))")` in `tabBar`), and the list header already prints the selection's per-room `after → minimum` impacts with violations in `Color.danger`. The remaining half ("QB 2/2" with the floor on the chip) has no cheap data path: `RosterCutEvaluator.positionImpacts` returns minimums keyed by `Position`, while a chip is a `CutPositionGroup` spanning several positions with different floors (OL = LT/LG/C/RG/RT), and with an empty selection it returns nothing at all. Inventing a group→minimum mapping in the view would restate a rule the engine owns.

- **An unexplained "PS" chip in a ~33×19pt touch target, explained only after you commit**
  - Already fixed in the current source. The chip reads "Stash on PS" / "On PS ✓" rather than two unexpanded letters, it only appears on a man who is actually marked for release, it carries `.frame(minHeight: 44)` and `.contentShape(Rectangle())` with a comment explaining why (a miss must not be a release), and the action bar explainer already prints the running "**n** flagged for the practice squad" before commit.

- **Camp grade painted accentGold for every grade, so a D reads as a highlight**
  - Already fixed. `gradeColor(_:)` maps the grade onto the same five-tier rating ladder as the OVR beside it (elite/good/solid/neutral/average/poor); no gold is left in the row.

- **Later offseason phases are faded to 40% opacity — "Regular Season REQUIRED Sep-Jan" is barely legible**
  - Already fixed in the working tree before this wave: the fade is `max(0.7, 1.0 - index * 0.08)` with a comment explaining the 0.7 floor. Nothing left to change.

- **Only the current phase gets a description, so "OTAs", "The Combine" and "UDFAs" appear as bare jargon**
  - Already fixed in the working tree: the `if isCurrent` gate around entry.description is gone and all ten rows render their description. Nothing left to change.

- **Fill the empty end-card with team payload (crest, situation, record, roster OVR, owner)**
  - The half of finding 11 beyond the type scale. ReadyToBeginStep receives only career, team and teamOverall; situation/record would have to come from the static LeagueTeamData table, which carries the same scale-and-staleness problem as the league-average finding above, and choosing what the closing beat shows is a design call, not a defect fix.

- **Widen the per-row mark button's hit area to 44**
  - The finding is wrong about the component: `ProspectMarkButton` (ProspectGradeMenuView.swift:60) already sets `.frame(width: 44, height: 44).contentShape(Rectangle())` on its label. The `.frame(width: 36)` in my file sizes the COLUMN, not the button, and SwiftUI does not clip hit-testing to a frame — so the target is already 44×44, only contested for ~4 pt on each side by the adjacent checkbox. Growing the column to 44 would take 8 pt out of the elastic NAME column and shift the pinned table header for no real gain.

- **Relabel "Complete Review → Return to Interviews" as "Interview 7 More"**
  - `InterviewReportView` takes only `results`; it has no slot count, and the just-ran-a-batch case can legitimately have zero slots left, so the label would read "Interview 0 More". Threading `remainingSlots` through three call sites to buy a copy tweak is more change than the defect is worth — demoting the style already fixes the two-gold-primaries problem.

- **Task descriptions truncate at two lines despite lineLimit(4) (075_hub_draft)**
  - Already fixed, in the working tree, before this wave started — `detailLine`'s Text carries `.lineLimit(4)` with the comment naming exactly this defect. HEAD still has `.lineLimit(2)` at that site, which is what the screenshot was taken against. Left the uncommitted edit intact and did not commit it (instructed not to commit). Measured: the sentence gets ~142 pt beside the fixed-size chip, ~28 characters a line, so the longest string in the batch (101 chars) now fits inside four lines with room to spare — the chip does not need its own row.

- **Playoff task description clipped mid-word: "…for this win-or-go-h…"**
  - Same site, same already-present `.lineLimit(4)`. "Optional · Set your game plan for this win-or-go-home matchup." is 62 characters, which fits in three of the four lines at the width the chip leaves.

- **Rail task descriptions truncate on exactly the clause that tells you how to finish the task (740_season_069)**
  - This finding asks for the uncommitted `.lineLimit(4)` edit to be committed — it is already in the working tree and I am instructed not to commit. Its second half (move the secondary chip to its own line) I did not do: at four lines the sentences now fit beside the chip, and the row comment records the deliberate decision that a 300 pt rail holding seven steps cannot afford a three-deck row.

- **The offseason rail's only button-shaped control is the disabled "Advance to OTAs"**
  - The finding is correct but the fix is a rewrite of the rail's visual grammar — turning the NEXT task row into a gold primary button and demoting or hiding the advance control changes how every phase in the panel reads, and the advance button is the season's documented stable handle (`accessibilityIdentifier("tasks.advance")`) that QA automation drives. Too large and too load-bearing for a small-fix wave. Partially mitigated in passing: the panel header no longer wears gold, so the button has two fewer competitors.

- **MORALE and FANS have no before→after while OWNER and LEGACY do**
  - Already fixed in the working tree: `summaryChanged` now passes "every man +N" for Morale (`rosterMoraleDelta`) and "50% → 61%" for Fans (`fanSupportDelta` against `career.fanSupport`), plus a Media cell. The screenshot predates it.

- **Forecast and outcome are never put side by side (predicted → actual)**
  - Not safe as a small edit: `responseCard` recomputes `preview` from `liveContext`, and by the time the reveal shows, liveContext has already had the committed tone appended — so the chips on screen are no longer the pre-answer forecast. A truthful predicted→actual row needs the preview captured at commit time (new state) before the row can be rebuilt.

- **Team Needs names RB DL TE but four groups show the identical starter grade "S: B−" — the pick is unexplainable from the tile above it**
  - Partly addressed: the caption now says "Weakest starters", and the grade popover already prints the Average OVR the ranking uses. Printing a numeric OVR or a rank on every Position Grades row would need another 2 columns in a tile whose rows already run ~146pt of a ~157pt grid column.

- **POSITION GRADES: the safety row renders "S  S: B / D: B−" — the group label collides with the legend's "S = starters"**
  - Already fixed and the finding is stale. `calculatePositionGroupGrades` now emits QB/RB/WR/TE/OL/DL/LB/DB/ST — the secondary is one "DB" room and there is no "S" or "CB" row to collide with. The screenshots were taken against the pre-#235 taxonomy.

- **Position Battles prints the same surname on both sides of a one-man "battle"**
  - Already fixed in code: `loadPositionBattles` requires at least two competitors still on the roster (`competitorIDs.filter { rosterIDs.contains($0) }.count >= 2`), and the comment above it describes this exact bug. The surname-collision case that remains is the separate finding I did fix.

- **DEPTH CHART tile is a hardcoded label with no state (second half of the PLAYOFF BRACKET finding)**
  - The tile owns no number today. "3 slots below replacement" or "OL depth C" would need a new depth analysis on the hub; the Position Grades tile beside it already carries the depth letters honestly.

- **Split expiring contracts into 0-year and 1-year buckets and re-rank the three shown rows by cap hit**
  - The rows are already OVR-sorted by deliberate choice (#145's star alert reads off it), and splitting `contractYearsRemaining <= 1` into two buckets is a semantics decision about what a 0 means in this model — it needs the contract generator looked at, not a tile edit.

- **"Optional · Important events need your attention before advancing." contradicts itself**
  - Already fixed in the working tree by an earlier wave. TaskGenerator.swift now ships the "Handle pending events" row with description "Off-field stories broke around the club. Nothing here blocks the advance." plus a comment stating that an optional row cannot claim the week is waiting on it. Nothing left to change.

- **Week 1 task rows say "your opponent" while three other elements name JAX**
  - Already fixed. The `opponentName ?? "your opponent"` fallback is gone; the titles now take an optional suffix (" for \(name)" / " vs \(name)") and read as unqualified "Set game plan" / "Tune week prep" while the fixture is unresolved, which is true in that state rather than a pronoun for a club named three inches away.

- **"Check injury report" is generated every week regardless of whether anyone is injured**
  - Already fixed. `injuredCount(on:)` derives the count from the team the way the hub's INJURIES tile does (injuryWeeksRemaining > 0), the row is gated behind `injuredCount > 0`, and the copy now states the number ("2 players are out. Adjust the lineup before kickoff.").

- **Market value is computed for every Key Decision and thrown away**
  - Already fixed in the working tree before I opened the file. keyDecisionRow now computes market for .expiringContract rows and prints "$8.2M now" over "$9.4M market" in the trailing column, and expiringRecommendation reads its marketValue parameter in every branch ("Re-sign at or near his $9.4M market value", "Paying $X against a $Y market value"). Nothing left to change.

- **Roughly half the width of every table row is empty — the Staff/You chips are marooned ~750px right of the last data column**
  - Substantially closed already, by exactly the fix the finding suggested: an "Expiring" column (count of deals up after this season, gold when non-zero) was added to both the header and the row on iPad, plus a legend line under the header. Remaining fixed-column content is ~560pt against a ~950pt card, so a gap survives, but closing it needs the fixed 56/64/80/64/60/72 frames on both the header and the row converted to distributed widths — twelve coordinated frame changes that must stay in lockstep or every column drifts, and that has to hold on iPhone too where three of the six columns disappear. That is a layout restyle, not a surgical fix, so I left it.

- **"Priorities set: 0/9" names a job with nine em-dashes and no visible way to do it**
  - Already fixed in the working tree. The bare Text("—") is now a gold "Set" needBadge, and the card's intro copy reads "Tap any position group to set your own priority — priorities affect draft board rankings and scouting focus".

- **Two adjacent headers are bound to the same sort key, and two sort columns have no header at all**
  - The visible defect is already fixed: "Strt / Depth" is bound to .depth, "Starter" was renamed "Best" and keeps .starter, and .expiring gained a header, so each header now owns one key and only one lights gold. I left the second half alone — SortColumn.avgOVR is genuinely unreachable, but it is @State-only (nothing persists its raw value) and invisible on screen, and deleting the case orphans GroupRowData.avgOvr and its computation, which is a three-site cleanup for zero user-visible gain.

- **"TOP 3" badge splits a tie: two candidates both at OVR 68, only one is badged**
  - Already closed in the working tree before this wave — `refreshCaches` (line 266-274) now badges every candidate level with 3rd place instead of `prefix(3)`, and `candidateRank(for:)` uses standard competition ranking so a tie shares a number. Verified against the code; no further change needed.

- **"Best Available" is a superlative handed to three different candidates**
  - Already closed — line 1761 reads `candidateRank == 1 ? "Best Available" : "Top 3"`, exactly the suggested wording. Verified; no further change needed.

- **SCHEME EXPERTISE prints raw enum values ("ProPassing", "WestCoast", "PressMan")**
  - Already closed — `schemeDisplayName(_:)` (line 2144) maps the raw dictionary key back through OffensiveScheme/DefensiveScheme and the expertise rows print it (label column widened to 92pt with lineLimit(1) so "Pro Passing" fits). Verified both `displayName` extensions exist in CoachingStaffView.swift:4887/4902.

- **SCHEME FIT refuses to answer at the exact moment the player needs it, and the reason is circular**
  - Already closed — `installedSchemeName(for:)` (line 1020) is passed into the detail sheet, so a GM+HC career with a coordinator in post now gets a rated dot and "You run X · Candidate prefers Y"; when genuinely nothing is installed the copy says what the hire does instead of telling him to hire the man he is looking at. The Fit column's `hasInferableTeamScheme` gate is correct as it stands — it hides only when the club has no scheme on either side of the ball.

- **"CAREER HISTORY" is hash-generated flavour text with no record, no teams and no seasons**
  - The presentation half is already closed — the card is titled "EXPERIENCE" (line 1404) so it no longer promises a record it cannot show. The rest of the suggestion (persist per-season OC/DC unit ranks and print three prior seasons) is a save-format and engine-history change well outside a presentation fix, and outside my one owned file.

- **Up to five unexplained badges ride on one candidate row and the only legend button covers colours**
  - Already closed — the toolbar button is now "Legend" (was "Colors") and the panel carries a second line explaining TOP 3, FREE AGENT, the flame count and the Ceiling badges alongside the rating swatches (line 611). Verified; no further change needed.

- **The stage count is printed three times on one screen**
  - Already fixed on this branch before I got here, and I verified it in the current source: `gameCard` has no "GAME n OF 3" eyebrow any more (the opponent is the headline, with a comment citing §2.1), and `reviewHeader`'s eyebrow now prints the policy title in `textSecondary`. The one sub-item still open — the meter reading "0 spent · 3 left" with its unit only in VoiceOver — is built by `PreseasonFlowBand.meter(gamesPlayed:)` in PreseasonFlowBand.swift, which is outside my two files.

- **Gold is doing four jobs on one screen, including the section-header colour P5 bans**
  - Already fixed. The gold card eyebrow is gone entirely and the selected policy row's marker is now a `checkmark.circle.fill` in `textPrimary`, not a gold `DSRowBadge`. Gold is left to the band's current slat and the single commit fill.

- **The install pill is flat blue on all three options while the risk pill ramps**
  - Already fixed. `PreseasonPolicy.familiarityTone` exists (empty → info → ok, climbing as `riskTone` falls) and PreseasonView's policy row passes `tone: policy.familiarityTone`, so both halves of the bet ramp.

- **The selection control is a blank rectangle — unselected rows render an empty chip**
  - Already fixed. `policyRow` renders `Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")`; the `DSRowBadge` whose unselected text was a literal space is gone.

- **"10 still to release before the phase closes." names an obligation with no route to it**
  - Already fixed. The planning stance's `DSActionBar` now carries `secondary: onOpenRosterCuts.map { DSActionBar.Action(title: "Roster cuts", handler: $0) }`, so the route exists during all three planning steps and the primary stays "Play game n".

- **The bubble denominator drops from 54 to 53 between consecutive games**
  - Already fixed by relabel — the Helped chip's context reads "of N who dressed", not "of N on the bubble", with a comment stating that `cutCohort` is built from this game's box score. That is the finding's own second option, and the right one: making the denominator a roster fact would mean building the cohort from the 90 rather than from `result.userLines`.

- **"Who moved" lists six men while the same screen twice says five moved**
  - Already fixed. `PreseasonRecap.starterMoverCount` was added and both printers use it — `reviewSummary` appends "— plus 1 starter who moved" and the sheet's `message` appends ", plus 1 starter who moved", so the arithmetic on screen closes.

- **A red "HURT" pill sits under an "INJURIES 0" chip and means something different**
  - Already fixed. `Verdict.hurt.pillLabel` returns "Slipped", the sheet's chip is labelled "Slipped", and `slateRow` prints a "Slipped" pill. The medical status is left to the `cross.case.fill` glyph.

- **The "On the bubble" tab and the "BUBBLE" standing pill mean two different things**
  - Already fixed. `PreseasonBubbleTable.Cohort.bubble.label` reads "Cut sheet"; "Bubble" survives only as the `Tier` standing value.

- **"2 helped their case, 2 hurt theirs" above a "Who moved" list of five**
  - Same defect and same fix as the six-vs-five finding — `starterMoverCount` is already stated in both the card header and the modal sentence.

- **The word "Preseason" appears twice in 80px (nav title + band headline)**
  - Not a defect on this screen. Every phase screen in the app sets a matching nav title (TrainingPlanView "Training Plan", RosterCutView "Roster Cuts", FAWeeklyView "Free Agency"), so dropping it here would break the navigation idiom and the back-button label rather than fix anything.

- **Step rail sub-caption prints "Frenzy" twice**
  - Already fixed in the working tree before I started. `phaseInfo` now returns descriptions without the word ("top FAs sign fast" / "bidding wars peak") and carries a comment explaining that `isFrenzy` makes `signingSubcaption` prefix it once. No change needed.

- **The news ticker is the hardcoded stub fallback, and it contradicts the board it sits on top of**
  - Already fixed in the working tree. `computeTickerEvents`'s empty-items branch is no longer five fixed sentences — it now reads the board that exists on Day 1: the wire count, the top two `marketInterest` names with position/OVR/ask, the biggest ask, and the club's room versus the league's. The QB-bidding-war line is gone.

- **Both inline controls miss the project's own 44pt rule**
  - Already fixed in the working tree. `visitControl` carries `.frame(minHeight: 44)` with the "button inside a button" rationale, and `positionFilterBar`'s chips carry `.frame(minHeight: 44)` with the measured-rect note. Both sites already read exactly as the finding asked.

- **The irreversible skip confirmation names none of the three resources it forfeits**
  - Already fixed in the working tree. The alert message is `skipConfirmMessage`, which interpolates cap room, remaining facility visits, board size and unplayed market days, and closes with "The AI clubs will sign whoever is left, and this cannot be undone."

- **The tagged player's row is a dead end — no Contact Agent, no contract detail**
  - Already fixed in the working tree before this pass: `taggedPlayerRow` already calls `contactAgentButton(for:)` and already prints his expiring `$X/yr` next to the tag figure. Nothing left to do.

- **The Lineup Incomplete alert names Auto-Set as the fix but does not offer it**
  - Already fixed in the current source. The alert's first button is "Fill & Advance", which calls `fillLineupGapsAndAdvance()` (CareerShellView.swift:1701) — `DepthChart.reconcileSaved` on the fetched roster, save, then `performShellAdvance` off the runloop. The screenshot predates it. Nothing to change.

- **The potential column uses directional arrows for an absolute band**
  - Already fixed in the current source. `shortPotentialLabel` no longer buckets `truePotential` into ★/↑↑/↑/→/↓ — it prints the headroom (`truePotential - overall`) as "+8" or "—", with `shortPotentialColor` banded on the same difference. That is the finding's own preferred fix, already applied.

- **Health is printed twice (HLTH chip and the health column) and the duplicate columns should be dropped**
  - The de-duplication the finding asks for cannot be done from my file alone. `overviewColumns` is right-anchored against `RosterView.sortableHeader`'s labels (Age/Frm/OVR/↗/Salary/Yrs/face/cross), so removing the years or health cell without the matching header edit slides every remaining header label off its own numbers — the exact 42pt drift the file already documents. I fixed the half that is local (one alarm per fact for contract years, above) and left the column set alone. The header change needs whoever owns RosterView.swift.

- **Add a room chip ("$44.2M -> $21.2M") to WHAT CHANGED**
  - Left out deliberately. The grid draws chips in one `Grid` row with `lineLimit(1)` values at title2 size; a fifth chip squeezes the four that carry the deal. The cost line directly under the chips already states the room, and the netting clause I added to `capSentence` is what actually explains the apparent gap the room delta was meant to close.

- **Generated names collide constantly — three consecutive board rows share a first or last name**
  - Already fixed in the working tree. `DraftClassBuilder.buildOrdered` threads a `usedNames: Set<String>` through `makeProspect` and calls `RandomNameGenerator.uniqueName(used:&usedNames)` (DraftClassBuilder.swift:157/169/595), and RandomNameGenerator now rejection-samples with a surname quota and a `givenNameQuota` of 3. Nothing left to change.

- **The legend under the standing strip lists its three items in reverse tile order and names a tile that doesn't exist**
  - Already fixed in the working tree. `standingStrip` labels the third tile OWNER (PressConferenceView.swift:629, with a #117 comment saying exactly why), and the legend below reads "Legacy affects career rating · Media shapes the narrative · Owner affects job security · Morale … · Fans …" — tile order, tile words, plus the two meters the tiles have no room for. The screenshots are from a pre-fix binary.

- **The step header and its meter disagree about whether the current question counts as spent**
  - Already fixed. The band's meter now passes `spent: min(currentQuestionIndex + 1, …)` (PressConferenceView.swift:449) — the same rule as the headline — with a comment stating that `DSResourceMeter` counts the unit in progress as spent so the brightest pip is the live one. Header and meter cannot disagree.

- **"YOUR OFFSEASON 0/2" counts only the current phase's tasks while "Phases complete (7)" sits directly beneath it**
  - Already fixed. The header pill spells its unit — `"\(progress.done)/\(progress.total) \(anyRequired ? "tasks" : "optional")"` (TimelineTasksPanel.swift:155) — with a comment naming this exact misreading ("a bare 4/6 set against the words YOUR OFFSEASON reads as four phases of six"). It reads "0/2 tasks" now, which is the finding's own suggested wording.

- **Future-phase preview rows clip at one line — "Read the Showcase & declaration rep…"**
  - Already fixed. `previewTaskRow` is `.lineLimit(2)` with `.fixedSize(horizontal: false, vertical: true)` (TimelineTasksPanel.swift:921-925) and a comment naming the same truncated string.

- **Four progress counters with four different denominators stacked in one 300 pt rail**
  - Half of it is already fixed — the header pill now says "0/2 tasks", which is what distinguished the two 2s. The other half, dropping "STEP n OF m" from the phase cards, I did not do: `groupCaption` states where a phase sits inside its group ("PRE-DRAFT · STEP 1 OF 4"), which the rail's vertical order does not convey once the list is truncated to three upcoming phases and "+ 9 more phases". That is deleting real information to reduce a count of fractions, not fixing a lie.

- **"YOUR OFFSEASON  0/6" sits directly above "Phases complete (9)"**
  - Same defect and same fix as the 0/2 finding above — the header pill already labels its unit ("0/6 tasks"), so the counter no longer reads as offseason-wide progress. Screenshot predates the fix.

- **Future steps in the hiring rail carry no counts, so the workload total appears only inside the auto-hire button**
  - Already fixed in the current source — the finding describes a stale screenshot. `hiringSlat`'s subcaption now returns "N open" (plus "· plan ~$X M" when the auto-hire plan funds that rung) for EVERY rung with an open seat, not just `.current`, and a comment at that site explains exactly this reasoning. DSSlatBand renders subcaption regardless of slat state. Nothing left to change.

- **Name pool collides: two WR Braithwaites, two Wades and two Zaviers among eight visible players**
  - Same already-fixed cause as above: the 55x55 draw the finding measured no longer exists, and the per-cohort given-name quota (3) is the part that specifically addresses repeated first names in one list. No change left to make inside RandomNameGenerator.swift.

- **3-YEAR CAP card is half empty, skips year 2, and shows no chart despite a line-chart icon**
  - Already fixed in the current source: `cap3yearForecastTile` renders a +1/+2/+3 yr ladder under the headline via `projectedCap(yearsAhead:)`, so year 2 is shown and the empty plate is filled. Only the sparkline-with-committed-money idea is outstanding, and committed money three league years out is not a value this screen holds.

- **"42 expiring" with no denominator and no action available for 18 weeks**
  - The denominator is already there — the chip and the high-priority headline both print "N of \(players.count) expiring". I did not add the "$X coming off the books" line: summing `annualSalary` over expiring players is not the cap relief figure (prorated bonus money can stay on the books), so printing it as relief would be a new presentation lie. That number needs the cap engine's accounting, not a tile-level sum.

- **The step-rail meter reads "1 spent · 5 left" with no noun (062_fa_market.png)**
  - Already fixed in the working tree before I got here. `DSResourceMeter.valueLine` is now `"\(spent) spent · \(left) \(unit) left"` (DSSlatBand.swift:341), so the FA band renders "1 spent · 5 market days left". The noun is on screen; nothing left to change.

- **Flow band contradicts itself: "1 spent · 2 left" while slat 1 is still the current step and shows no result (pre_08_game1.png)**
  - Already fixed in the working tree. `DSSlatButton.secondLine` (DSSlatBand.swift:759) no longer gates the outcome on `.done`: a `.current` slat with a result prints "result · subcaption", result first — exactly what the finding asks for.

- **The same actor is "AI clubs" in the button caption and "AI teams" in the alert it opens**
  - The finding is stale against the source. The skip alert now shows `skipConfirmMessage`, which already ends "The AI clubs will sign whoever is left, and this cannot be undone" — FAWeeklyView.swift contains no "AI teams" copy at all. The only surviving "AI teams will sign remaining free agents based on their needs" string is a leftover entry in dynasty/dynasty/Localizable.xcstrings (never looked up, since Text() is fed a String variable), and that file is outside my four.

- **One calendar block wears three names and two date formats (WeekAdvancer group-transition stamp)**
  - Already fixed in the working tree. At HEAD `emitGroupTransitionMessageIfNeeded` used `date: "Season \(season) — \(group.displayName)"`; the current file (WeekAdvancer.swift:5584) already reads `date: InboxEngine.dateLabel(week: week, season: season, phase: newPhase)`, which is exactly the suggested fix. The remaining half of the finding — reconciling "YOUR OFFSEASON" / "PRE-DRAFT · STEP 1 OF 4" / "STAGE 1 OF 6" onto one word — lives in the rail and hub views, not in WeekAdvancer, and is a cross-file naming change rather than a small correction.

- **"$-20.5M" — currency sigil printed inside the minus sign**
  - Already fixed in the working tree, as the finding itself anticipated. Both private `formatMillions` copies in CapComplianceView.swift (lines 815-822 and 1041-1048) now build `let sign = thousands < 0 ? "-" : ""` and format `"%@$%.1fM"`, so a negative release prints "-$20.5M". The other nine copies the finding lists (RosterEvaluationView, PlayerContractView, ContractTimelineView, CapOverviewView, ContractNegotiationView, ContractExtensionSheet, TradeView, FranchiseTagView) are all in files outside my list, and promoting a shared formatter would touch every one of them.

- **Empty state-slot labels BID/VST render at 4.01:1 contrast**
  - Already fixed in the working tree. DSStatusPill no longer dims the `empty` tone: the body is `.foregroundStyle(tone.tint)` with a comment recording exactly this defect, and `.empty`'s tint is `Color.textTertiary` (#8A96A8) at full opacity, which measures ~6.3:1 on the #0B1222 row background — well clear of AA. The 0.75 alpha that produced the sampled #6A7586 is gone. Switching to `textTertiaryReadable` on top of that would be a change with no defect behind it.

- **Preset chips are ~23pt tall — roughly half the 44pt minimum touch target**
  - Already fixed in the working tree: the chips carry `.frame(minHeight: 44)` and `.contentShape(RoundedRectangle(...))` (TrainingPlanView.swift:186/196), with a comment citing §2.12 and the measured ~24pt. The screenshot predates that change — the chip lockup in it ("Camp Hard", "Recovery Mode", single-line) no longer matches the code either.


## toisen tiedostossa

- **Give the mark button a star/bookmark glyph in the unmarked state instead of a bare circle**
  - `circle.dashed` is set inside `ProspectMarkButton` in ProspectGradeMenuView.swift, which I do not own, and it is shared by the Big Board and the film-study list — changing it there would ripple onto screens no one measured. The alternative (moving the mark into the row's trailing block) restructures the row and the pinned table header. Named the columns in the header instead.

- **The sheet names the problem — "22 jobs still open" — then offers only "Continue →"**
  - DSResultSheet exposes exactly one action (`primary:` on its DSActionBar) and lives in UI/Common, which I do not own. Doing this properly means a secondary action on the shared component plus a StaffOutcome closure, and the continue handler would then have to swap `activeHireSheet` from the result straight into another hire sheet — the precise sequence the comment on `onContinue` documents as the cause of the result-blinks-into-an-empty-sheet flash. Needs its own change with a shared-component owner.

- **HONORS tile is a permanent stub — it says awards "arrive in your inbox" during the All-Star Game itself, next to a rail row saying you already reviewed them**
  - The cause, stated in the tile's own comment, is that nothing persists a per-club All-Star/All-Pro count. Fixing it means writing that record in WeekAdvancer when the proBowl mail is generated — engine files I do not own.

- **No name de-duplication on the 53-man roster — two WRs named Braithwaite (014_tab_Roster)**
  - Closing this properly means threading a league-wide `used` set through LeagueGenerator.swift:656, which builds the whole ~2,880-player league with a bare `randomName()`. That file is not mine. The half that IS reachable from my file already landed: the pools went 55x55 to 195x349, so the cross product is 3,025 -> 68,055 pairs and expected same-surname pairs on a 53-man roster fall from ~25 to ~4.

- **Two adjacent rows both read Callum, initials CA and CB (pre_03)**
  - This finding correctly identifies the fix as 'route the league generator through uniqueName with a league-wide used set' at LeagueGenerator.swift:656 — explicitly a file I do not own. My side of it (the deduplicating API and the widened pools) is in place and ready for that caller.

- **Name collisions make the cut list ambiguous — three Kenjis, duplicated KM initials avatar (camp_10)**
  - Two causes, both outside my file: the roster comes from LeagueGenerator, and the second half of the fix asks to stop deriving the avatar from initials in RosterCutView.swift:684-688. Neither is mine to edit.

- **ST always shows "D: F" / "Depth needed" — a permanent flag telling the player to sign a backup kicker**
  - Already fixed, and the fix lives in a file I do not own. PositionGradeCalculator.calculatePositionGrades (RosterView.swift:1662) now returns noDepthGrade (an em dash) instead of "F" when a group has no backups, so depthBad no longer trips and no "Depth needed" chip is raised for ST. My file's side is done too: both the row badge and the priority scorer treat noDepthGrade as clearing the depth test, so a fully stocked ST room can still be promoted to "Strength".

- **"ACC" is never expanded on the screen that repeats it eight times, and its colour ladder is an OVR ladder in disguise**
  - Both halves land outside my two files. The literal "ACC \(scout.accuracy)" is ProDayTourView.swift:376 and ScoutTeamView.swift:283. The colour comes from `Color.forRating` at those call sites; giving scout accuracy its own tier edges means either editing those call sites (not mine) or adding a `forScoutAccuracy` to Theme.swift with no caller, i.e. dead code. Retuning the shared `RatingTier` edges in Theme.swift instead would repaint all 168 `forRating` call sites in the app to fix eight numbers on one sheet.

- **Roughly 30% of a portrait 13-inch iPad is a dead black gutter, and the page is pinned left**
  - The defect is `.frame(maxWidth: DSLayout.contentMeasure, alignment: .leading)` followed by `.frame(maxWidth: .infinity, alignment: .leading)` in PreseasonView.swift:200-203 — that `alignment: .leading` is what pins the column left while the nav title and the sheet centre. That file is not mine. `contentMeasure = 720` in Theme.swift is not the bug: it is a deliberate reading-column token with a documented rationale, and changing its value would reflow every screen in the app rather than centre one.

- **A Week 16 recap with no playoff picture**
  - Not a small edit and not in my files. `RoundResultsView.Data` has no seeding field and `RoundResultsView.swift` is owned by someone else; the strip also needs a seed/clinch/magic-number computation that does not exist yet (`buildRoundResults` assembles games, power rankings, MVP race and headlines, none of which carry standings). This is a feature, not a presentation fix.

- **Potential is one 5-bucket arrow glyph sitting next to a second, different arrow glyph**
  - Same fix, already in the tree: the potential column is a number now, so it no longer collides with `developmentArrow`'s alphabet, and Bascomb/Nadeau/Osman Tanguay rank against each other. The remaining half of the finding — the missing "Frm"/"↗" headers on screen — is `RosterView.sortableHeader`, which I do not own.

- **Persona header ("Rewards commitment") contradicts the agent's opening line**
  - Both halves of the fix live outside my files: the subtitle string is `Engine/Contract/AgentPersona.swift:100` and the "Wants: …" chip belongs in the negotiation view. The cited line in `AgentDialogueLibrary.swift:322` is not itself wrong — the desire model is a legitimate separate axis — so editing it would not close the contradiction.

- **Franchise tag costs 10 morale and the screen never says so**
  - The morale hit in `ContractEngine.applyFranchiseTag` is correct and documented; the missing copy is in `UI/Contracts/FranchiseTagView.swift:596`, which I do not own. Hoisting the 10 into a named engine constant would be dead code without the view edit.

- **GRD / PROD columns have no on-screen key**
  - `ProductionTierChip.swift` renders a 3-character chip and already carries the VoiceOver label; the legend has to go on the screen that draws the headers (`UI/Scouting/CombineResultsView.swift:722-723`), which I do not own. Adding a legend view to my file would be unreferenced dead code.

- **The required "Set training focus" gate is satisfied by saving the exact split the engine would have used anyway**
  - Both proposed fixes are design-scale and live outside my file set: showing projected per-position-group deltas for four presets is a new panel in TrainingPlanView.swift, and demoting the task to optional is a TaskGenerator change. Nothing in WeekAdvancer.fetchOrSeedTrainingPlan can close the finding on its own — changing the seeded 34/33/33 would just move the default without making the gate a real choice, and it is a development-pass constant besides.

- **Two candidates at the same OVR ... and the comparison sheet drops price entirely (rows/salary half)**
  - The tie-break half is applied. The other two asks — position-relevant attribute columns on the depth-chart row, and carrying salary into ComparisonSheet via CommittedCapLedger.money — are both in dynasty/dynasty/UI/Roster/DepthChartView.swift, which I do not own.

- **Difficulty stars invert the universal ★ = quality convention, with no legend and no label**
  - `difficultyLabel` already exists and is correct in LeagueTeamData.swift (my file); the defect is entirely in what TeamSelectionView.swift renders — it draws the stars and shows the label only in the detail sheet. Every version of the fix (word instead of stars, label beside stars, a "why" line) is an edit to TeamSelectionView.swift, which I do not own and which another agent is currently editing.

- **Cap-compliance letter's date stamp (last remaining non-canonical producer in WeekAdvancer)**
  - `capComplianceInboxMessage` takes season and phase but no week, and its phase can be .regularSeason — routing it through dateLabel with a placeholder week would print "Week 0, Season 2027". Adding a `week:` parameter would change the signature its two callers use, and both (CareerShellView.swift, FAWeeklyView.swift) are outside my file set.

- **PDAY / VISIT / WORK columns render 39 empty circles on a screen where all three stages are locked "After FA"**
  - The gate the finding wants does not exist in my file and cannot be inferred there. ProspectColumns.headers/workupCells only see a ProspectColumnContext; deciding whether the pro day / visits / workouts stages have OPENED needs a new flag on that struct set by each host — FilmStudySelectionView.swift, BigBoardView.swift, InterviewSelectionView.swift and LiveBigBoardPanel's headerContext. Four of those five call sites are outside my file list, and a flag defaulting to "open" that nobody sets changes nothing. Needs the scouting-screen owner.

- **FA market rows are 122pt tall — 2.8x the design system's own "scan" spec**
  - The defect is not in DSListRow. DSListRow.swift:58 is the density doc comment; `scan` already declares minHeight 44 and verticalPadding 2. The 122 pt comes from the FA market screen stacking four full-width lines into the identity slot, and the density control the finding suggests exposing is a host-screen control. Both edits belong to the FA market view, which I do not own.

- **On a win-or-go-home screen the opponent is the smallest text and the cap number is among the largest (740_season_063)**
  - The finding is right about the screen, but the fix it asks for is not in SeasonWeekBand: promoting the playoff matchup to hero scale and demoting the Cap/Staff tiles is a change to the hub's tile grid in CareerDashboardView.swift, which I do not own. The only thing line 194 controls is the tail slat's 11 pt subcaption, and it already prints the opponent — enlarging it there would not put the matchup in the tile grid. Needs an owner of the dashboard.

- **Key quotes are shown without the question that produced them**
  - The engine side named in code_ref is already correct — buildResult populates SelectedResponse.questionSummary and the per-answer resolved effects. The defect is entirely in the renderer, PressConferenceView.swift:1456-1486 (summaryQuotes draws only responseText and mediaReaction), which is not in my file list.

- **On the one screen where the player must draft someone, the only solid-gold button says "Shop this pick"**
  - The diagnosis is right but the fix needs a commit route the bar does not have. `DraftControlBar` cannot reach the highlighted board row or the confirm sheet — that alert is owned by LiveBigBoardPanel's local state (it only reports open/closed via `coordinator.setPickConfirmationOpen`), so a gold "hand in a card" primary means threading a new closure through DraftDayView and LiveBigBoardPanel, both outside my file set. Moving the gold off "Shop this pick" without replacing it would restore the gold-free on-clock stance the file documents as the previous defect.

- **The #1 prospect shows seven blank combine cells with no DNP marker (049_interviews)**
  - The finding is right about the screen but its code_ref is wrong. CombineResultsView ALREADY does exactly what the fix asks: `combineRow` computes `let dash = ScoutingEngine.combineParticipation(for: prospect).isDNP ? "DNP" : "--"` and passes it to every drill cell, and `nameChips` draws the tappable DNP/Partial badge with a reason popover. The screen in the evidence is the Big Board — the "CMB" chip it describes only exists in `dynasty/dynasty/UI/Scouting/BigBoardView.swift:2559`, which is not in my file list. The fix belongs there, in the board's own column code.

- **Every slat in the rail is styled as the app's signature button but nothing in it is tappable**
  - The premise no longer holds. `DSSlatButton.slatBody` (DSSlatBand.swift:578-593) already branches on `action == nil`: a band with no `onSelect` draws plain content with no press style and no `.isButton` trait, and its own comment names this exact defect. Neither `DSSlatBand` call site in PressConferenceView passes `onSelect`, so both presser bands already render as readouts. Nothing to change, and DSSlatBand.swift is not mine to touch anyway.

- **Surname pool is small enough that three of fifteen coaches share a surname with a colleague, and two same-position WRs share one in the decision list**
  - Already fixed, and the fix names these exact collisions. RandomNameGenerator's pools are now 195 male / 40 female given names x 349 surnames (not 55x55), and `uniqueName(female:used:)` enforces surnameQuota = 2 and givenNameQuota = 3 per cohort with a cross-product fallback walk. The file's doc comment cites 'two WRs called Braithwaite in one position group, three Tanguays in an eleven-man draft class, an assistant head coach and a defensive coordinator both called Goddard' as the defects it closed. The remaining callers that draw a bare `randomName()` (LeagueGenerator, CoachingEngine, ScoutingEngine) are outside my file list.

- **Two WRs called Zavier with identical tag costs in a six-row list, and "Wade" recycled from the player signed six minutes earlier**
  - Third report of the same fixed defect. The generator already keeps the per-cohort `used` set the finding asks for, rejecting a repeated full name and capping surnames at 2 and given names at 3 per cohort; the pools were grown at the same time. Recycling a name across two different cohorts (an FA signed earlier vs. this season's tag list) would need a league-lifetime name registry threaded through callers in files I do not own.

- **Duplicate first names in a 14-row window, and an initials avatar that collides with a position code**
  - Split verdict, nothing left for me to do. The name-generator half (suppressing repeated first names within a club) lives in RandomNameGenerator.swift, which I do not own. The half that is mine — surname-only battle rows — is already fixed: `battleName(_:)` prefixes the first initial when the club carries two men of that surname, and both `positionBattleRow` names and the leader chip go through it.

- **Half the WHAT CHANGED grid is empty state given the same weight as the real numbers (DSResultSheet)**
  - Wrong file for the fix. DSResultSheet is a generic component; the four chips ('STILL OPEN 0 / none', 'CLASHES 0 / none') are chosen by the auto-hire sheet's caller, which is not in my file list. The component cannot know that a 0 is empty state rather than a moved number — its own header states the rule ('The caller decides, because only the caller knows whether its number moved'), and collapsing zero chips inside the component would silently change every other result sheet in the app. Sizing zeros differently would also break the single shared baseline that is the whole reason the block is a Grid.

- **FIT column reads 'Good' on 14 of 15 visible rows**
  - Both honest fixes are out of reach here. The FIT cell is rendered by ProspectColumns from a String label, so showing the 0-99 score or swapping the column for projected round means editing ProspectColumns.swift, which I do not own. The alternative — retuning ProspectSchemeFitHelper's 75/55 label bands — is an unmeasured change to a rating-to-label scale shared by the Big Board, the draft-room panel and this list, and the same helper's raw score feeds the draft-grade pipeline; getting the bands right needs the class-wide distribution measured first, i.e. its own wave.

- **The meter says "0 spent · 12 left" and never names what is being spent (camp_10_cut_to_75_b.png)**
  - Same already-fixed `valueLine` as above — the cut band now reads "0 spent · 12 cuts left". The second half of the finding ("spent" is the wrong verb for an uncommitted selection) is not a defect in this file: `spent` is whatever the caller passes, and RosterCutView counts marked-but-uncommitted men into it. Fixing that means changing what the cut screen passes, in a file I do not own.

- **The sheet restates the card behind it almost verbatim — the score appears three times and the mover tally twice**
  - The fix the finding names — dropping the SCORE chip from the result sheet — is in `UI/Camp/PreseasonRecapSheet.swift`, which is not in my file list. Nothing in `PreseasonView.swift` is the right place to close it: the finding itself says the card behind should keep owning the tally, and the card's score headline (line 446) and `reviewSummary` (line 475) are that durable surface. The other in-file repetitions are load-bearing — the band's "W 44–27" slats are the only navigation between games, and `slateCaseTable` exists precisely because earlier slats are not tappable (comment at line 415). Note for whoever owns the sheet: its chip array is documented "Four, and no fifth" and lays out as one Grid row, so removing the score chip leaves three columns and should be checked for width.

- **Inbox badge clamps to "99" with no "+" (4 findings: 740_season_052, pre_07_slate, pre_08_game1, pre_12_game3)**
  - Already fixed in the working tree. TopNavigationBar.swift now reads `Text(unreadInboxCount > 99 ? "99+" : "\(unreadInboxCount)")` with a comment explaining the clamp it replaced. No edit needed — I did not touch the file. (The findings' side note that something is over-filling the inbox is a separate InboxEngine question, not mine.)

- **Two different reach magnitudes for pick #16 sit 300px apart**
  - The reveal card's chip already names its yardstick: `boardChip` renders "MY #63" (or "MEDIA #86") immediately to the left of the "-47 REACH" chip in the same `boardRowChips` HStack, and `boardDelta` is documented as measured against whichever board `boardSlot` quotes. The genuine mismatch is the LIVE FEED copy — "Consensus board had him #86 — taken 70 slots ahead of it" — which is built in DraftDayCoordinator.swift:2030, outside my file list. Adding "vs MY BOARD" into the delta chip would print MY twice in one chip pair and push a `fixedSize` row this file has already had to fight for width.

- **Same countdown printed as "1:46" in the header and "106s left" in the bottom bar**
  - The wrong half is DraftControlBar.swift:377 (`"**\(coordinator.clockSeconds)s** left…"`), which is not in my file list. DraftStickyHeader.swift already prints the mm:ss the finding wants to standardise on (line 1046). Adding a shared formatter here without the call site that needs it would just be dead code.


## muu

- **Every "league average" comparison in the intro is a hard-coded literal, not a computed league value**
  - Cannot be closed surgically. The intro never loads the other 31 teams, so this needs a league-wide fetch (or TeamBrowseCatalog) plumbed through IntroSequenceView.loadData and into two child steps — and first a decision on scale, because the row's own "Average Overall" is the retired whole-roster mean while every league-side OVR figure (LeagueTeamData.estimatedOVR, RosterStrength) is a starter average; comparing them as-is would make every club read below average. Substituting a different literal source would not make the arrow honest. Its own wave.

- **The headline that "ran" is a fixed string and contradicts the media hint on the same card**
  - The fix is content, not presentation: `mediaReaction` is one constant per `PressResponse` in PressConferenceEngine.swift, so closing this means authoring two or three headline variants for every response in the generator and a band selector. That is an engine/content wave, and it is outside the one file I own.

- **561px empty below the last answer while the session's earlier answer is invisible (720_season_007)**
  - Same as above: it asks for a per-question session transcript (outlet + quote + resolved pills) that does not exist yet. `revealedEffects` is single-question state — the view keeps no per-question resolved record — so this needs new state plus a new card.

- **At "TIER 2 OF 5 — COORDINATORS", the entire first screenful is tier-1 work that is already done (scroll half)**
  - The gold-emphasis half was applied. The ScrollViewReader half was not: the staff surface is a multi-section List inside the tab shell, so it needs a reader wrapper, an `.id` per section and a scroll on both appear and slat tap — a behavioural change that has to be watched on the simulator, which this wave cannot do. Demoting the filled Head Coach card to a one-line summary row is likewise a restructure of that Section, not a presentation tweak.

- **Dead space on a portrait iPad: an empty grid cell, a stretched WEEK PREP tile, and 390pt of empty rail**
  - Spanning the last tile across both columns of a `LazyVGrid` and repopulating the rail's bottom is a layout pass over the whole hub, well past a surgical fix. The two sparse tiles it names (Week Prep, Workload) now carry live content, which shortens the empty stretch.

- **LOCKER ROOM prints two morale-family numbers 36 points apart with no explanation and only one bar**
  - The ambiguity of the single bar is fixed (it is now grouped with its Chemistry row). Giving morale its own bar plus a driver line ("−12 from 3 unhappy starters") means importing SquadDynamicsView's insight computation into the tile — a cross-file change, and a second full-width bar changes the card's shape.

- **Duplicate surnames inside one 8-row franchise-tag list (035_franchise_tag)**
  - Same cause and same blocker — these are league players from LeagueGenerator's bare `randomName()`. Not my file. A `randomName(excluding:)` overload in my file would be dead code until that caller changes, so adding one would be inventing work rather than closing the defect.

- **Surname collisions everywhere — two Marsdens and two Wyatts in one 8-row FA buzz list (300_fa_003)**
  - League free agents, built by LeagueGenerator. Not my file. The finding's own arithmetic (~36 men per surname league-wide) is now ~5 per surname on the widened pool, but per-roster uniqueness still needs the caller to hold a `used` set.

- **Surname collisions on the cut sheet — three Tanguays, two Crisantis (pre_10_game2)**
  - Veteran roster from LeagueGenerator, not the draft class, so the quotas in `uniqueName` never see these men. Needs LeagueGenerator to adopt `uniqueName` — out of my ownership.

- **Surnames and first names repeat all over one roster (pre_12_game3)**
  - Same LeagueGenerator path. Not my file.

- **Surname collisions across the roster: three Tanguays, two Frobishers, two Hinsdales (pre_02)**
  - Same LeagueGenerator path. Not my file.

- **Three duplicated surnames inside a single 15-man coaching staff (800_season_end)**
  - Coaching staff comes from CoachingEngine.swift:717/1912/1922 via bare `randomName()`, not my file. The widened surname pool cuts the chance of at least one duplicate pair in a 15-man staff from roughly 85% to roughly 26%, but eliminating it needs CoachingEngine to thread a `used` set.

- **Generated names collide inside an eight-man scouting department: two Farons, two Ezekiels (073_scout_sheet)**
  - This is the purest given-name finding and the generator now supports exactly what it asks for, but the caller is ScoutingEngine.swift:3326 using a bare `randomName()` — not my file — so the new `givenNameQuota` cannot reach it. Verified the capability is there: an 8-man cohort drawn through `uniqueName` comes out with eight distinct first names and eight distinct surnames. Wider pools drop the first-name collision chance for a bare-draw department from ~40% to ~14% in the meantime.

- **Gate F reports three unregistered name pools (observation, not one of my findings)**
  - Pre-existing and outside my ownership, flagged while I was verifying my own file against the anonymization gates: `bigBoardTierNames` in UI/Scouting/BigBoardView.swift and `malePhotoNames`/`femalePhotoNames` in UI/Common/UserPortraitView.swift are unclassified. They are labels ('Blue Chip', 'The Chairman'), not person names, so they want a NON_PERSON_POOLS entry in tools/league-data/scan_bundle.py. Unrelated to my edit — I touched no arrays — but it will fail the bundle gate for whoever owns those files.

- **The seven-item top nav has no current-location indicator**
  - TopNavigationBar has no notion of where the user is — `bookmarkStrip` iterates a static array and the destination state (navigationPath) lives in CareerShellView.swift:533, which another agent owns. Adding an `activeBookmark` parameter with a nil default would compile but nothing would ever pass it, so the strip would render exactly as it does now: dead scaffolding rather than a fix. Needs the one-line call-site change in CareerShellView to be worth doing.

- **Two thirds of a portrait iPad is empty on the scout department and school lists**
  - The fix named — a 2-up LazyVGrid for the department, plus new per-row facts (region covered, error band at current accuracy) and an inline position breakdown on every school row — is a layout rewrite of two List sections plus new data the summary struct does not carry. That is not a small edit, and half-doing it (regridding without the facts) would just make the emptiness wider.

- **Gold is the default colour of the whole hub, so the primary action has nothing to stand out against**
  - Nothing actionable in my files. The forty-odd gold elements named come from `DashboardTile` (private to CareerDashboardView.swift), the task chips, the NOW badge and GradeColors.swift — none of which I own. The only lever in Theme.swift is the tokens themselves: demoting `SectionHeaderText` would repaint 33 headers in files that are NOT the ones in evidence (CareerDashboardView uses none of them), making the app less consistent, and pulling the C-grade tint off `warning` changes the colour of every 60–69 rating at 168 `forRating` sites plus 450 direct `.warning` uses. That is a design-system decision for one deliberate pass, not a surgical fix — and it would collide with the agents editing those screens right now.

- **Gold is doing five different jobs in one column, so it no longer marks the one thing to do**
  - Same as above. The card titles, the panel header and the "9 active" figure are drawn in Camp/Career view files I don't own, and the "STARTER" chip is DepthChartView.swift:678. The only in-file change available is repainting `accentGold` or `warning` app-wide, which is the large, risky edit I was told to skip.

- **Two near-identical golds carry six unrelated meanings on one screen**
  - The same palette change as the two gold findings above: reserving amber for "needs attention" means moving the average rating tier off `warning` in `Color.forRatingTier`, which repaints every 60–69 badge, chip and position grade in the app from one line. The call sites that actually confuse the two (the roster count, the CUTDOWN PENDING alert, the cap figure, the OVR badges) are in Camp/Contracts views I don't own. Needs one deliberate palette pass, not a fix-wave edit.

- **The calendar badge and the rail's own counter disagree about how much offseason work is left**
  - The two numbers are the only part of this in my files; the fix is not. `pendingTaskCount` (required-incomplete) feeds `TopNavigationBar`, which draws it unconditionally in `Color.danger` — and the rail's counter lives in `TimelineTasksPanel`. Neither file is mine. Switching `pendingTaskCount` to total-incomplete on its own would put a red alarm badge on all-optional work: the regular-season list is all-optional by design, so the badge would read a red "6" for seventeen straight weeks. The suggested "badge total-incomplete and colour it red only when required work remains" needs the TopNavigationBar edit to go with it.

- **Negotiation spends morale and loyalty invisibly**
  - The fix is a fact-chip row and a per-round morale delta in the negotiation transcript UI (`ContractNegotiationView` / `NegotiationChat`), neither of which I own. `ContractNegotiationEngine` has no display surface I could add the readout to without the view.

- **Buzz rows not checked against the club's own cap space**
  - Partially addressed — I fixed the empty-suitors half in the engine. The remaining half (grey/annotate each row as affordable / needs a restructure / out of reach against the header's cap figure) is row rendering in `UI/FreeAgency/FinalPushView.swift:347`, which another agent owns.

- **Every list row leaves a 37-58% wide empty gutter between the name and the first number**
  - The only fix inside DSListRow is to stop the identity slot claiming the slack — and the comment on that exact line records why it claims it: with minWidth alone, the first column after identity started at a different x on every row (the board's OVR badge ran from 558 to 685 down one screen). Capping identity or centring the row content re-flows every list in the app — roster, board, FA market, standings, draft — off one shared component, on evidence from three screenshots. That is the large, risky edit this wave is told to skip; it wants its own measured pass with shots of every list.

- **Make the grade chip tappable for the four-input breakdown (second half of the DraftTickerPanel grade finding)**
  - The visible half is fixed (the qualifier now shows at this width). The breakdown half is not a presentation fix: `PickGradeCalculator.Inputs` lives on `GradeBundle` and is never carried into `PickResult`, so it would need new plumbing plus a popover attached to a chip inside an animated reveal card that currently has no tap targets at all. That is bigger and riskier than this wave allows.

- **On the clock, the three recommended names are not tappable**
  - Closing this needs a commit path the panel does not have. `DraftTickerPanel` takes only a `coordinator`; the confirmation the finding names (`askToDraft`) lives in `LiveBigBoardPanel.swift`, and `StageName` carries a UUID and strings, not the `CollegeProspect`. Doing it properly means either a new callback threaded through the panel's call site (DraftRoomView) or a second, duplicate confirmation flow inside the ticker — both outside the owned files, and the duplicate flow would be worse than the read-only list. The scroll-and-highlight alternative needs a shared selection binding across two panels, same problem.

- **"Where your board is" ranks Minnesota above TCU — the deciding top-50 term is never shown**
  - The fix has to be drawn, and the drawing is in dynasty/dynasty/UI/Scouting/ProDayTourView.swift, which is outside my four files. ProDaySchoolSummary has no top50Count field at all (the count lives only inside the local Accumulator and is folded straight into `relevance`), so the only thing I could do in ScoutingEngine.swift is add an unused struct field — the screen would look exactly the same. Removing the top50 term from the sort key instead would delete real information from the ordering, which is worse than the finding it fixes. Needs the engine field and the chip landed together by whoever owns ProDayTourView.

- **Identical headline on all three sessions**
  - The finding itself says do not re-file. Verified present: `mediaOutcomeHeadline(tone:media:)` at PressConferenceView.swift:1878-1888 makes the tone the subject and the media delta the predicate, `summaryChanged` carries a Media cell, and `summaryCostLine` carries `mediaPart`. Needs a rebuild and re-shoot, not an edit.

- **Position Grades prints "S  S: B− / D: B−" — the Safety group code collides with the legend's "S = starters"**
  - The finding is stale against the code: `calculatePositionGroupGrades` has no safety group. The nine labels are QB, RB, WR, TE, OL, DL, LB, DB (CB/FS/SS) and ST (K/P) — no row is labelled "S", so there is nothing to disambiguate.

- **The reaction toast covers the top three rows of the Big Board**
  - Not closable without a structural edit. The placement is deliberate and documented (pinned inside the board column below its measured header, hit-testing off) and both suggested alternatives are large: rendering reactions in the LIVE FEED rail means rewiring the beat pump into another component's file, and shrinking the card to its intrinsic width fights RailCard's frame chain — the card is cardWidth-wide because `.frame(maxWidth:)` precedes `.background()`, and forcing `.fixedSize(horizontal: true)` there would truncate a two-line headline instead of wrapping it. Too risky for a small-fix wave.

- **The season band loses every week number once the postseason starts (740_season_063.png)**
  - Cannot be fixed in my file. SeasonWeekBand.swift:128 forces every regular-season week to `.done` when `inPlayoffs`, and DSSlatBand replaces the numeral with the done glyph — a decision the file documents as measured (a third element in the row costs 16 pt and broke INTERVIEWS across two lines on a nine-stage band), so I will not undo it generically for one consumer. The right fix is one line in SeasonWeekBand.swift: fold the week into the outcome string ("W17 · W 36–31"). That file belongs to another agent.

- **"NEED" carries two meanings on the same row — green pill and column value**
  - Neither end of the fix is in a file I own. The green pill is InterviewSelectionView.swift:705 (its own inline `Text("NEED")` capsule, with a comment explaining why it sits on the name line). The column header is `ProspectColumns.headers` in ProspectListControls.swift:1167, which is mine — but renaming it "URGENCY" needs the column to grow from 32pt to ~46pt (these headers are plain `Text` with a fixed frame and no shrink path; the file's own RISK comment records what an oversized child does to its neighbour), and that width is shared by four surfaces and mirrored in a `blockWidth` constant in LiveBigBoardPanel.swift. Renaming the shared column on Big Board, Live Big Board, Film Study and Interviews to defuse a collision that exists on one of them is wider than the defect.

- **Rival OVR amber sits one hue away from the gold reserved for emphasis**
  - The hue clash is real, but every fix on offer is an app-wide palette change, not a local one. `Color.forRatingTier(.average)` paints every 60–69 rating in the app; `warning` paints every caution state. Repointing either recolours hundreds of screens against a five-tier ladder that Theme.swift:100-106 documents as deliberate (60–69 Average → yellow). Too broad and too risky for a small-fix wave — it wants its own measured colour pass with screenshots.

- **Cap Usage percentage card restates the summary card (fold it into the summary)**
  - The finding's premise is half wrong: `capBarCard` is not a card holding a percentage — it is the usage bar, including the dead-money tail segment and its legend (CapOverviewView.swift:439-486). The percentage in its header labels the bar. Folding the number into the summary card would delete the only chart on the screen. I fixed the zero-value redundancy the same finding names and left the bar alone.


## feature-kokoinen

- **Fill the 772pt row void with a real table — snaps, OVR trend, depth-chart slot, keep-score rank, sticky header**
  - This is the rewrite the brief rules out, not a small fix: a sticky column header, right-aligned column geometry across 87 rows, plus a per-position depth count that would have to be held as state (recomputing it per row is O(n²) on every tap) and would then contradict the selection-adjusted counts the list header already prints. I took the two columns that needed no new state — contract years and dead cap — and left the table redesign for a wave that can own the whole screen.

- **Make the summary pills filters, and add a compact table mode for the 100th visit**
  - Both are new features, not defects: filtering would need selection state, a filtered `rankedResults` and an empty state inside `InterviewReportView`, and a table mode is a second renderer for 53 cards. Well past the size this wave is for.

- **The left rail is empty for the bottom ~55% of a portrait iPad screen (playoffs)**
  - The suggested fill — bracket, seed, opponent record and top-3 ratings, injury list — is a new panel with new engine reads (StandingsCalculator.playoffTeams, playoffSeedRanks), not a presentation fix. It needs its own design and its own wave. The cheaper alternative (pin the advance button to the bottom) would break the panel's single-ScrollView layout, where the button deliberately sits between the current phase and the upcoming ones.

- **Bottom quarter of the summary screen is empty**
  - The suggested fix is new content (a five-meter before→after, a per-question tone/outcome table) or a two-column regular-width grid. Either is a layout redesign of the summary phase, not a surgical edit.

- **"BEFORE THIS SESSION" stays frozen for all five questions**
  - The label is honest as written — it says "before this session". Making it live means merging the standing strip and the running-impact card into one projecting card, which is a redesign of two cards on the screen's most-used phase, not a copy fix.

- **781px of empty navy between the last answer card and the bottom bar (720_season_005)**
  - Closing it means inventing new content for the band — session tone history, the reporter's prior sessions, a media trend. That is a feature, not a defect fix; the empty band is a symptom of the same gap as the summary-dead-space finding.

- **The advance gate shows 16 names and nothing else — every piece of decision content is below the fold, with "SCHEMES & EXPERTISE" clipped in half at the sheet edge**
  - Leading with a verdict block and collapsing the 16-row roster behind a disclosure is a redesign of the sheet, not a small fix. The clipping half of it is closed by the `.presentationSizing(.page)` change, which gives the sheet the height it was already asking for and brings the scheme-fit analysis above the fold.

- **"Coaching Staff Review" is a read-only list — one number per coach, ten of them red, and nothing you can do about any of it**
  - Making each row tappable through to the coach, adding a league-average marker and surfacing the unspent budget is a redesign of the sheet plus navigation out of a modal — too large and too risky for this wave.

- **The list poses a real trade-off and gives no way to hold two candidates side by side**
  - The fix as described is a feature, not a defect repair: multi-select state, a pin store, a hold gesture on the row, and a new side-by-side column view. That is far past a surgical edit on a presentation finding — it needs its own design pass and its own wave.

- **"Will use 6% of cap" is measured against a total cap the screen never shows**
  - Already fixed in the working tree. `capImpactBadge(asking:room:)` now takes the room the `AVAILABLE` strip prints, computes the percentage against it, and says "Will use 28% of your room" / "More than your room" / "No room left". The room is read once per board pass in `freeAgentList` rather than per row.

- **On question 2 the CONFIDENT line dominates FUNNY on every readable axis; the only differentiator is fogged out**
  - Widening `mediaReadable` so a neutral reporter is readable would delete the fog mechanic on most questions in the game — the gate is deliberate and documented, and it changes what every press card shows, which is more than a small honest fix. Guaranteeing that one non-media axis differs in direction is an authoring constraint across the whole question file. The promise-consequence disclosure at pick time is a PressConferenceView addition. What I could do from here I did: the fogged media chip now says "can't read this writer" instead of "? —", so the blank column reads as a state rather than as a rendering fault.

- **"WHAT IT ACTUALLY COST" heads a row that is four-fifths profit**
  - Already fixed. The reveal heading is `hasCost(effects) ? "WHAT IT ACTUALLY COST" : "WHAT IT ACTUALLY MOVED"`, and the commit bar's explainer and the summary action bar switch on the same `hasCost` predicate. The finding's secondary note — that `effectPillRow` hides zero deltas so the pill set changes shape between questions — I left alone: always drawing five pills to make a stable column is an information-design change, not a defect fix, and it would print three unmoved meters on a single-effect answer.

- **"Tag Cost" is a derived number with no way to see what it derives from — and it moved $3.3M between visits with no note**
  - Both halves are more than a small edit, and the premise is partly already met. The derivation IS stated on the same screen — the rules banner three cards up says the tag is "the average of the top 5 salaries at his position" — so what is actually missing is (a) a drill-down listing those five salaries and (b) a since-last-visit delta. (a) needs a new presented view plus an Identifiable wrapper, and a per-row `.popover` bound to one `@State` inside a `ForEach` misbehaves, so it would have to be a body-level sheet — new UI, not a fix. (b) needs the previous visit's tag price persisted per position via CareerScopedDefaults and a rule for when to clear it. Worth its own task; I did not want to half-build it.

- **Roughly the bottom sixth of the rookie reveal is empty ground below the class card**
  - Closing it means inventing new content — a class-shape summary (best/worst vs band, counts above/at/below the report, total rookie cap hit) or a two-column row layout. That is a design feature, not a surgical fix, and both need their own numbers plumbed through `RookieClassReveal.Summary`. The other half of the suggestion — the missing legend — already exists: the class card prints "Gold band = your scouts · grey = the media's guess … last figure is his real OVR." (RookieClassRevealView.swift:585-590).

- **Put the top cap hits with dead-money-if-cut and net savings on the Cap screen**
  - A new section on a screen that does not have one — new rows, new sorting, new per-player math wired in from PlayerRowView's `deadCapIfCut`/`capSavingsIfCut`. That is a feature, well past the size of edit this wave is for.


## balanssi

- **Coaching Changes is a pass-through phase: both tasks Optional, Advance live at 0/2**
  - The only real fix is the one the finding names — a scheme-fit penalty on position grades or a morale hit for a mismatched coordinator. That moves simulated outcomes and needs its own measured wave through the balance harness. The alternative, flipping the two review rows to isRequired: true, is a gating change, not a presentation fix: it would block the offseason advance behind the CoachingStaffView confirm bars, which is exactly the kind of risky behaviour edit this pass is told not to make. No copy change can invent a cost that the engine does not charge.

- **AGGRESSIVE is dominated by CONFIDENT on every audience the preview shows**
  - Both routes out are closed to me. Giving the aggressive line a real upside means editing the tone × situation matrix or the authored intro effects — engine constants that move simulated outcomes, so it needs its own measured wave. Surfacing the hidden counterweight (a magnitude band, or a use-count on the archetype chip) is new chrome in PressConferenceView, which is not my file. Reading the code confirms the finding: at `.introduction`, aggressive buys media +3 against confident's +2 — a 1-point edge that is inside the deadband by construction — and pays morale -3 plus an owner penalty, so it really is dominated.

- **Fall through to the highest-accuracy scout when the specialist's deficit exceeds the +3 specialization bonus**
  - The +3 is a real engine constant, but converting it into an accuracy threshold means picking an exchange rate between accuracy points and error points (the engine's error is `15 × (1 − acc/100)`, so +3 error ≈ 20 accuracy points, and the finding's own 59-vs-79 example lands exactly on the tie). Choosing that cutoff changes which scout the app recommends at most schools and therefore which reads the user buys — needs its own measured wave. The array-order half of the same finding is fixed.

- **Chemistry railed at "Elite 100/100" (unnormalised roster sum)**
  - Not my file — the fix is in `Engine/LockerRoom/LockerRoomEngine.swift`, which I do not own. It is also exactly the kind of change the balance harness gates: normalising leadership/toxicity per-capita moves every club's chemistry and everything downstream of it. Needs its own measured wave.

- **OC profile grades him on seven defensive schemes, twelve F rows**
  - The defect is real but the fix is a display filter in `UI/Staff/HireCoachView.swift:2195`, which another agent owns. The engine side (`initializeSchemeExpertise` seeding every scheme at 15+bonus) cannot be trimmed without changing the shape of `Coach.schemeExpertise`, which scheme-fit reads — that would move simulated outcomes.

- **60 interview slots against a stated norm of 15–20**
  - Half the finding is already fixed: the "League teams typically interview 15-20 prospects" line no longer exists in `InterviewSelectionView` — it was deliberately replaced with "Unused slots expire with this draft class", with a comment explaining that a slot is the only cost and restraint buys nothing. Cutting `interviewSlots` from 60 is a draft-prep economy change against that shipped decision: needs its own measured wave.

- **Chemistry is pegged at "Elite 100/100" — a full bar that cannot move**
  - The only correct fix is to normalise LockerRoomEngine.calculateChemistry's per-player leadership/toxicity sums by roster size — a change to chemistry weights, which the brief names explicitly as off-limits. It moves every save's chemistry number and anything downstream of it. Needs its own measured wave.

- **Team chemistry is pinned at the ceiling — "Elite 100/100" over "Team Morale 64%" in the same card**
  - Same defect and same fix as the finding above (LockerRoomEngine.calculateChemistry normalisation) — needs its own measured wave. The presentation half (labelling what chemistry does that morale does not) is in the Locker Room tile view, which is not in my file set.

- **The largest block on the setup screen is the one choice with zero mechanical effect**
  - Neither option is a small edit. Binding the 20 personas to coaching-style / press-temperament biases is a new engine input (and a balance change). Shrinking the grid to one avatar plus a Change button and spending the space on four editable Quick Start chips is a layout rewrite of NewCareerView.swift — UserPortraitPicker only takes `avatarSize`/`columnCount` from its caller, so nothing in my file can change the screen's proportions.

- **MEDIA -24 is presented as narrative state but nothing in the press conference reads it**
  - Both halves are out of reach. The engine half (weight the reporter draw / shift neutral writers hostile as mediaReputation falls) changes the outlet mix that feeds PressEngine.stance → stanceAdjustment, i.e. it changes press effects — PressEngine's own doc comment warns that adding one outlet to the tough list "would silently double how often evasion gets punished in a crisis presser". That needs its own measured wave. The copy half (relabel "Media shapes the narrative") lives on the career dashboard's standing strip, not in any file I own.

- **The pick grade ignores your own scouting board: the same card reads "A+", "MY #101" and "−50 REACH" with no key**
  - Neither fix is available to me. Feeding `userBoardRanks` into `PickGradeCalculator.Inputs` changes the grade formula, which the balance harness mirrors — needs its own measured wave. The alternative the finding offers (labelling the two frames on the card, "MEDIA A+ · YOUR BOARD −50") is in DraftTickerPanel.swift:2542, which is not in my file set. I left PickGradeCalculator.swift untouched rather than invent a third change.

- **Two of the workload table's three columns carry a single value — STATE is "LIGHT" on all 12 rows and INJ is "4% inj" on 11 of 12**
  - `WorkloadEngine.injuryRiskPct` already returns a Double; the integer rounding that flattens the column happens at its only call site, TrainingPlanView.swift:434, which is not in my file set. The other half of the finding — that `.underloaded` and `.healthy` both multiply by 1.0 — is a balance constant and needs its own measured wave.

- **Regional coverage is modelled but the pro-day circuit neither shows nor uses it**
  - This is a design change to how scouting accuracy is produced — a familiarity bonus at the pro day, a decay on it, and a cap on the chief's reach all move scouted-error and therefore simulated outcomes. Needs its own measured wave through the balance harness, not a presentation pass.

- **WEEK PREP card is ~75% empty**
  - Already fixed: `gameWeekPrepTile` reads `savedPrepSplit` and prints the actual selection ("60 general / 40 opponent", or "Not set — 50 / 50"), not the old "General vs opponent focus" axis label. Showing what the focus is worth this week would mean surfacing a contested `prepFocusDelta` on the hub — an engine-value display that needs its own measured wave.

- **Name pool collides with itself — prospects compared against roster players sharing a name**
  - Two reasons. The fix belongs in the name generator (RandomNameGenerator / DraftClassBuilder), not in BigBoardView, and those files are not mine — tracking issued names per league also changes generated league content, which needs its own measured wave. Separately the evidence is stale: `starterComparison` no longer prints "vs Alaric Kirkbride: +8 OVR"; it prints "Upgrade on Kirkbride" (surname only, no delta), so a shared FIRST name no longer reads as a man compared to himself.

