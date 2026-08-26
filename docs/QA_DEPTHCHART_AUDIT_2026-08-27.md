# /analyze-app — Depth Chart, four-lens persona audit (2026-08-27)

Evidence: five screenshots off a **cloned** simulator; Debug build confirmed by `PERF|` console lines.
Functional sweep: three tabs PASS; the per-row chevron turned out to be a REORDER control, not an
expander; Auto-Set rewrote the chart and silently discarded a manual reorder.

**32 findings from 4 persona agents; 6 refuted by an adversarial verifier reading the source; 26 stand.**

| severity | count |
|---|---|
| blocking | 2 |
| high | 9 |
| medium | 13 |
| low | 2 |

## THE TWO BLOCKING FINDINGS ARE ONE DESIGN DECISION, NOT A BUG

Verified independently by the orchestrator against the source:

* `grep` of the whole `Engine/` tree for `depthChartData` / `DepthChart` returns **one hit, and it is a comment**.
* `WeekAdvancer.startingLineupIDs(available:)` fills every slot with `player.overall > choice!.overall` — max-by-overall per position preference. The user's ordering is never read.
* `GameSimulator.rollKickoff` takes no player at all: a flat 2% return-TD chance and a random 20–35 start. KR and PR feed nothing.

The game nevertheless BLOCKS phase advancement on a complete chart (the "Lineup Incomplete" gate),
so the player is held up until he names returners for a system that does not exist.
Wiring the chart into the simulator moves simulated outcomes and needs its own measured pass;
it is recorded here rather than done unilaterally.


## blocking

### The chart the game forces you to fill is never read by the simulator — starters are re-picked by max OVR
- **lens:** Hardcore player (tosipelaaja)
- **evidence:** dc_03 -> dc_04: demoting Wade Braithwaite (93) out of KR STARTER and promoting Kwabena Winchester (75) changes exactly one number on the entire screen — the Returners badge goes 'AVG 93' to 'AVG 84'. 'TEAM 73 ... OFF 74 DEF 72' is pixel-identical in both frames, as are all 4 rows of the Kickers & Punters card. Nothing on any of the five shots reports a consequence of an ordering decision.
- **code:** `dynasty/dynasty/Engine/Simulation/PlaySimulator.swift:2483`
- **fix:** findQB/findRB/findWR (PlaySimulator.swift:2482-2497) resolve the starter as `players.filter { $0.position == .QB }.max(by: { $0.overall < $1.overall })`; the comment at :2480 states the rule outright ('The best player at the position acts as the starter'). A grep for `DepthChart` across Engine/ returns only TaskGenerator/HardKnocksNarrator/InboxEngine — none of them a sim path — and `career.depthChartData` is decoded only in UI (CareerShellView.swift:462/1547, ScheduleView.swift:97, RosterCutView.swift:2476). CareerShellView.swift:461-475 even BLOCKS Advance with 'Lineup incomplete — N starting slot(s) unassigned' until the user fills a chart the engine then discards. Fix: thread the decoded DepthChart into GameSimulator alongside the roster and have the player finders read `chart.starter(for: .QB)` first, falling back to max-by-overall only when the slot resolves to nobody. Until that lands, the reorder chevrons, Auto-Set and every AVG pill are decoration.

### Nothing on this screen reaches any simulation — every engine that fields a lineup picks max-by-overall and never reads the saved chart
- **lens:** Game developer
- **evidence:** The QB card prints "STARTER · Davion Maddocks · QB Age 28 $848K · 73" above "BACKUP · Kaleo Hinsdale · QB Age 26 $894K · 54", and the DT card prints "STARTER Sincere Braithwaite 74 / BACKUP Leander Bolliger 69 / 3RD Wade Tanguay 67". Swapping any of those rows with the chevrons changes nothing that plays: three separate engines each re-derive the lineup from raw overall. The header "TEAM 73 · OFF 74 · DEF 72" is the only number on the whole screen the chart actually moves, and it is a display badge.
- **code:** `dynasty/dynasty/Engine/Simulation/GameSimulator.swift:2090`
- **fix:** GameSimulator.swift:2090-2091 is `players.filter { $0.position == position }.max { $0.overall < $1.overall }`; MatchupResolver.swift:26-88 (`FieldUnit.offense`/`.defense`) and WeekAdvancer.swift:7251-7284 (`startingLineupIDs`, which drives gamesStarted and the development playing-time role) are two more independent copies of the same max-by-overall rule. `career.depthChartData` (written at DepthChartView.swift:288) has zero readers under Engine/ — grep confirms only navigation enums and narrative events. Fix: pass the club's chart into `GameSimulator.simulate` and resolve all three lineup functions through one `Lineup(chart:roster:)` that falls back to max-by-overall only for AI clubs with no chart. Note that docs/AI_FIX_QUEUE.md:807 (F-18) already owns exactly this and is marked **DONE** while only its item (1), MedicalEngine.dressed, shipped — reopen it, or nobody will look at this again.


## high

### Reorder stepper is a ~11×10 pt target and its two buttons sit 9.5 pt apart — a quarter of the 44 pt minimum
- **lens:** Designer
- **evidence:** Measured on dc_01_offense.png (2064×2752 = @2x of 1032×1376 pt). In the RB card the BACKUP row's chevron pair renders as ink spanning device rows 1483–1493 (chevron.up) and 1502–1512 (chevron.down), x 407–425. That is 18×11 device px per glyph = 9×5.5 pt of ink, and the two independent buttons' centres are 19 device px = 9.5 pt apart. The whole two-button stepper occupies 29 device px = 14.5 pt of vertical space. Every one of the 11 player rows visible on dc_01 carries this control.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:708`
- **fix:** Give each Button an explicit `.frame(width: 44, height: 44).contentShape(Rectangle())` and drop the `VStack(spacing: 2)` in favour of a single 44 pt control per direction (or one 44 pt drag handle using `.onMove`, which is what a depth chart actually wants). Widen the gutter from `.frame(width: 20)` to 44 — there are 384 pt of unused row width to pay for it (see the density finding).

### The disabled half of the reorder stepper renders at 1.03:1 contrast, so 10 of 12 offensive rooms show a single lone chevron — the SwiftUI disclosure idiom
- **lens:** Designer
- **evidence:** Measured on dc_01_offense.png: at the RB STARTER row the disabled chevron.up region (x 405–440, y 1388–1404) is bg #1F2632 with the glyph at #1E2839 — contrast 1.03:1. The RB 3RD row's disabled chevron.down measures 1.05:1 against #162135. Result on screen: the RB STARTER row shows only '⌄', the 3RD row shows only '⌃', and only the middle BACKUP row shows a pair. `maxDepth` is 2 for 10 of the 12 offensive slots (WR1/WR2/WR3, TE, FB, LT/LG/C/RG/RT), so in those rooms every single row displays exactly one chevron and the stepper nature is never visible at all.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:718`
- **fix:** `Color.backgroundTertiary` (#1C2940) as a disabled foreground on a #1F2632 surface is invisible, not dimmed. Use `Color.textTertiary.opacity(0.35)` (≈2.5:1 — legibly present, clearly inert) so the up/down pair is always a visible pair, and add a `.imageScale` bump or a hairline capsule behind the pair so it reads as one stepper control rather than two loose glyphs.

### The reorder chevron is drawn as a lone disclosure triangle, so "expand this row" demotes your best player instead
- **lens:** Casual player
- **evidence:** In dc_01 the QB card's STARTER row (Davion Maddocks, 73) carries exactly ONE glyph in the left gutter — a single "⌄" — and the BACKUP row (Kaleo Hinsdale, 54) carries exactly one "⌃". Only the middle row of a 3-deep room shows a stacked pair (RB BACKUP Ezekiel Ferrante 65; DT BACKUP Leander Bolliger 69 in dc_02). Every 2-deep room — WR1, WR2, FB, LE, RE, LOLB, MLB, ROLB, KR, PR — therefore renders one chevron per row, the universal iOS "tap to expand" shape. dc_03 → dc_04 is what that costs: tapping the "⌄" on the KR STARTER row moved Wade Braithwaite (93) to BACKUP and Kwabena Winchester (75) to STARTER, with no dialog, no undo, and no label anywhere saying the control moves people.
- **code:** `DepthChartView.swift:718`
- **fix:** Two changes at DepthChartView.swift:707-740. (1) Stop hiding the disabled arrow: draw both chevrons always, the inactive one at Color.textTertiary.opacity(0.35), so the control reads as a two-way stepper rather than a disclosure triangle — the disabled state is currently Color.backgroundTertiary (#1C2940) on a row filled with the card's #142030, which measures 1.13:1 and is simply not there. (2) Give the pair an affordance a first-timer can name: enclose the 20 pt column in a bordered capsule and set .accessibilityLabel("Move up")/("Move down") on the two buttons (they have none — the row label at DepthChartView.swift:779 describes the player, not the control). Each button is a 10 pt glyph (DSType.Size.micro) in a 20×12 pt box, so this also removes a mis-tap that silently rewrites the lineup.

### Auto-Set overwrites the whole chart with no warning and no undo, then reports discarding the player's own choice in success green
- **lens:** Casual player
- **evidence:** dc_04 → dc_05: the manual KR change (Kwabena Winchester 75 in the STARTER row) is gone and Wade Braithwaite (93) is back on top, with the Returners pill restored from "AVG 84" to "AVG 93". Nothing preceded that: the gold "Auto-Set" pill in the top-right is a bare one-tap button, and the word "Auto-Set" reads to a football fan as "fill in the blanks", not "discard everything I did". No trace of the discarded edit survives anywhere on dc_05.
- **code:** `DepthChartView.swift:391`
- **fix:** The button at DepthChartView.swift:390-404 calls applyAutoSet() straight through, autoGenerate replaces the entire dictionary (DepthChart.swift:387 `storage = newStorage`), and persistDepthChart() writes it at DepthChartView.swift:419 — there is no confirmationDialog, alert or undo anywhere in the file. (a) When the chart is non-empty, gate the button behind a confirmationDialog whose body is the sentence the accessibility hint already contains ("Fills every depth slot with the best available player by overall rating", DepthChartView.swift:403) plus "This replaces your manual changes". (b) Keep the pre-Auto-Set DepthChart in a @State and add an "Undo" button to the toast, which already exists and lives 2.6 s (DepthChartView.swift:470). Also soften the summary: "Re-ordered 1 slot by overall." (DepthChartView.swift:456) renders with Color.success and a green border (DepthChartView.swift:481, 492, 495), telling a casual player their reverted decision was an improvement.

### A player holding three starting jobs is drawn identically to one holding a single job — no marker on the chart, and none in the picker either
- **lens:** Casual player
- **evidence:** Wade Braithwaite (WR, Age 32, $54.0M, OVR 93 — the same three identifiers on every card) appears as STARTER of WR1 in dc_01 and as STARTER of BOTH KR and PR in dc_03. All three rows use the same gold starter plate, the same name/age/salary line and the same green 93 badge. Nothing on any of the three says "also KR", "also PR" or "also WR1". A casual player switching to the Special Teams tab has no way to learn that the man they are looking at is already the offence's WR1 and is now taking every kick and punt back as well.
- **code:** `DepthChartView.swift:815`
- **fix:** The trailing indicator stack at DepthChartView.swift:814-845 renders exactly four things: out-of-position, injury, fatigue, OVR. Add a fifth — an "also KR·PR" capsule — computed from the chart the view already holds (DepthChartSlot.allCases.filter { $0 != slot && depthChart.depthOrder(for: $0).first == player.id }). The existing out-of-position glyph cannot cover this: it is suppressed for returners because slot.acceptsAnyPosition is true for KR/PR (DepthChartView.swift:817), so a WR at KR gets no mark at all. Fix the picker too: the "In Chart" pill at DepthChartView.swift:1249 is scoped by `depthChart.depthOrder(for: slot)` (DepthChartView.swift:1171) — the SAME slot — so opening the PR picker and choosing the man who already starts at WR1 and KR shows no badge either. Widening that check to all slots is one line and puts the warning where the choice is made.

### KR/PR are ranked by speed and agility, and neither number is printed anywhere — the badge shows the OVR the slot ignores
- **lens:** Hardcore player (tosipelaaja)
- **evidence:** The KR card reads 'STARTER Wade Braithwaite / WR Age 32 $54.0M / 93' over 'BACKUP Kwabena Winchester / WR Age 29 $848K / 75', and the group header reads 'AVG 93'. The 93 on the KR row is byte-for-byte the same 93 the WR1 row shows for the same man in dc_01. No speed, agility or any return-specific figure appears on either returner card or in the sub-header ('2 groups - 4 positions - fatigue - lower is better').
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:1027`
- **fix:** The picker's default sort segment is literally labelled 'Overall' (ComparisonSort.overall = "Overall", DepthChartView.swift:991) but for .KR it returns `a.player.physical.speed > b.player.physical.speed` (:1028) and for .PR `physical.agility` (:1031); Auto-Set does the same (DepthChart.swift:359 and :366). So the candidate list arrives sorted by an invisible number while the visible column (OVR, :1259) is out of order — the exact 'hidden roll' that breaks trust. Fix: badge `physical.speed` on KR rows and `physical.agility` on PR rows (DepthChartView.swift:844) with the OVR demoted to the subtitle line, print the same trait in the candidate row, and rename the segment from 'Overall' to 'Best for slot'. Note that `slot.acceptsAnyPosition` (DepthChart.swift:140) also suppresses the out-of-position glyph (:817) and the versatility chip (:1205) for exactly these two slots, so KR/PR are the only slots on the app with no fit signal at all.

### Returners is the highest-rated, greenest card in the app and the engine has no returner — the AVG 93 badge prices a decision the sim cannot read
- **lens:** Hardcore player (tosipelaaja)
- **evidence:** Returners header: green checkmark, '2/2 - 4/4 deep', 'AVG 93' — the highest AVG pill on any of the three tabs (QB 73, Backfield 62, Receivers 79, DL 75, LB 70, Kickers & Punters 65). Four depth rows, two of them badged 93 and 80.
- **code:** `dynasty/dynasty/Engine/Simulation/PlaySimulator.swift:2106`
- **fix:** The punt code comments its own gap: 'the engine has no return man, so the returned yards have to be inside this figure' (PlaySimulator.swift:2106-2107) — the net is centred on the PUNTER's leg only. Kickoffs are a fixed table with no roster argument at all: `rollKickoff` (GameSimulator.swift:1418) draws 2% housed / 55% touchback / else `Int.random(in: 20...35)`. So this is not fixed by wiring the depth chart into the sim (see the blocking finding) — there is no return model to wire it to. Either (a) pass the KR/PR starter into `rollKickoff` and scale `kickoffReturnTouchdownChance` and `kickoffReturnStartRange` by his `physical.speed`, and add a return component to the punt net, or (b) drop KR/PR from `specialTeamsSlots` (DepthChart.swift:154) and stop gating Advance on them. Presenting the club's most decorated room as its most consequential one is worse than presenting no room.

### The Returners group is a decision surface over a system that does not exist — kickoffs are a flat dice roll with no player input at all
- **lens:** Game developer
- **evidence:** "Returners ✓ 2/2 · 4/4 deep · AVG 93" over KR (Wade Braithwaite 93 / Kwabena Winchester 75) and PR (Wade Braithwaite 93 / Kester Vandenberg 80). Demoting the 93 to backup at KR (dc_04) rewrites the group's numbers on screen and rewrites nothing in the game: the sim never asks who is back deep.
- **code:** `dynasty/dynasty/Engine/Simulation/GameSimulator.swift:1418`
- **fix:** `rollKickoff(allowReturnTouchdown:)` at GameSimulator.swift:1418-1438 takes no roster, no player, no rating: a hard 2% housed return (`kickoffReturnTouchdownChance`, :37), a 55% touchback, otherwise `Int.random(in: 20...35)` — identical for all 32 clubs. There is no punt-return model at all. Either give the return a real model (returner speed/agility shifting the start-line distribution and the TD chance) so the two KR/PR slots price a decision, or collapse the Returners group behind a "not yet simulated" note until it does. Same class of problem one card up: PlaySimulator.swift:2156 picks the kicker as `offensePlayers.first(where: { $0.position == .K })` — roster order, not the K slot this screen just let the user set.

### The chart's slot set is not the eleven the engines field: it prints a phantom FB starter and gives no slot for the second DT
- **lens:** Game developer
- **evidence:** Offense sub-header: "4 groups · 12 positions", including an FB card that reads "STARTER · Alaric Bascomb · FB Age 23 $1.2M · 59" in the gold starter plate. Defense sub-header: "3 groups · 10 positions", and the Defensive Line group is LE / DT / RE — one DT card — carrying a green "3/3 · 7/7 deep" all-clear. Twelve offensive slots and ten defensive ones cannot both be an eleven.
- **code:** `dynasty/dynasty/Domain/Models/Team/DepthChart.swift:149`
- **fix:** `defenseSlots` (DepthChart.swift:149-151) is `[.LE, .RE, .DT, .LOLB, .MLB, .ROLB, .CB1, .CB2, .FS, .SS]` — one DT — while MatchupResolver.swift:76-87 seats `deL, dt1, dt2, deR` and WeekAdvancer.swift:7275 fills `.DE, .DT, .DT, .DE`. Consequence on this exact roster: Leander Bolliger (69), printed BACKUP, is a starting DT in every engine that counts starts. The mirror is `offenseSlots` (:144-146): with three RBs on the roster (66/65/64), MatchupResolver.swift:45-46 and WeekAdvancer.swift:7269 both skip the fullback entirely, so the gold STARTER plate on Alaric Bascomb is a label no engine honours. Split DT into DT1/DT2 (dropping DT's compensating `maxDepth: 3` at :129) and either drop FB from the base personnel or mark it as a package slot.


## medium

### One fixed card density serves both tabs: 384 pt of every row is empty and 34% of the iPad's width is gutter, yet Offense still costs ~2 screens of scroll while Special Teams leaves 30% of the screen blank
- **lens:** Designer
- **evidence:** Measured on the 1032 pt-wide iPad screenshots. Horizontal: the slot card is 677.5 pt wide and the depth row's fill is 649.5 pt; 'Brixton Yarborough' ends at x=832 device px (416 pt) and the OVR badge starts at x=1600 (800 pt) — 384 pt (59% of the row) of empty space in between, on every row. Page gutters add (1032−677.5)/2 = 177 pt per side = 354 pt more. Vertical: a 3-row card is 170–183 pt tall and a 2-row card 125–139 pt, so only 5 of the 12 offensive positions (QB, RB, FB, WR1, WR2) fit above the fold on dc_01. On dc_03 the last content pixel is at device row 1927 of 2752 — the bottom 412 pt (30.0%) of the Special Teams tab is empty.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:156`
- **fix:** The scroll is capped at `DSLayout.contentMeasure` (720), which Theme.swift:210 defines as 'the default reading column… a form, a list, a message'. A twelve-position chart is the `wideMeasure`/`gridMeasure` case the same file describes as 'multi-column tables… two-up card rows'. Switch to `DSLayout.wideMeasure` with a 2-column `LazyVGrid` of slot cards on regular width, which halves the offense scroll and fills the Special Teams tab. Then spend the reclaimed in-row space on the data the middle currently wastes (fatigue meter, snap share, OVR delta vs the man below).

### #C9A94E paints 15 elements meaning five different things on one tab, against the file's own rule that gold marks 'real decisions'
- **lens:** Designer
- **evidence:** Sampled from dc_03_specialteams.png, all four identical at #C9A94E: the 'K' slot badge fill, the 'STARTER' label, the group collapse chevron, and the 'Auto-Set' button glyph. Counting the tab: 4 solid gold position badges (K, P, KR, PR) + 4 gold STARTER labels + 4 gold-tinted starter row fills/borders + 2 gold group chevrons + 1 gold Auto-Set = 15 elements in one hex. A fifth yellow, #EAB308 (warning), sits alongside on the '69' and '61' OVR badges and the 'AVG 65' pill — 33 units apart in R, 10 in G. Comparable tabs use blue (#3B82F6, offense) and red (#EF4444, defense) for the badge, so gold is doing unit identity here on top of everything else.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:937`
- **fix:** The comment at DepthChartView.swift:331–336 states the rule — gold is for 'the gold accents that mark real decisions', which is why the tab bar was made blue. Honour it: give special teams its own hue (e.g. `.success`-family teal or purple) in `sideColor`, and change the group collapse chevron at line 589 from `.accentGold` to `.textSecondary` — a disclosure triangle is navigation, not a decision. That leaves gold on exactly two things: the STARTER rank and Auto-Set.

### Every defensive position badge is solid #EF4444 — the app's `danger` token, the same colour as the injury cross and one shade off the sub-60 OVR numeral
- **lens:** Designer
- **evidence:** Sampled from dc_02_defense.png: the 'LE' badge fill and the 'DT' badge fill are both #EF4444 exactly. Six red chips are visible above the fold (LE, DT, RE, LOLB, MLB, ROLB) and the tab holds ten. On dc_01 the poor-tier OVR badge for Kaleo Hinsdale ('54') paints its numeral #F87171 — the neighbouring `dangerText` token — and `Color.danger` is also what the injury cross-circle glyph uses (DepthChartView.swift:828). So on the Defense tab the highest-chroma, first-hit colour on the screen carries no meaning at all, while the two things that genuinely need red are rendered in the same family.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:936`
- **fix:** `sideColor(.defense)` returning `.danger` spends the alarm colour on decoration. Since the badge string is already redundant (see the duplicate-label finding), the cleanest fix is to delete the coloured badge on the slot card entirely and keep the side colour only where a side is genuinely ambiguous. If a defensive tint must stay, use a non-alarm hue (`Color.accentBlue`'s cool counterpart, or `surfaceBorder`-on-`backgroundTertiary` as a neutral chip) and reserve #EF4444/#F87171 for injury and poor ratings.

### The largest numerals on the screen read TEAM 73 / OFF 74 / DEF 72 on the Special Teams tab — three numbers no edit on that tab can ever move
- **lens:** Designer
- **evidence:** The summary bar is pinned above the tab picker on all three tabs and always shows 'TEAM 73 … OFF 74  DEF 72'. On Special Teams none of the three describes anything on screen: the tab holds K, P, KR, PR. Proof it is inert there — the bar region (device rows 415–480) is pixel-identical between dc_04_row_expanded.png and dc_05_autoset.png, while in the same pair the Returners group badge moves 'AVG 84' → 'AVG 93'. There is no ST pill.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:294`
- **fix:** `TeamStrength.lineupSlots` is `offenseSlots + defenseSlots` (ScheduleView.swift:28), so special teams is excluded by construction. Either add a fourth pill computed over `DepthChartSlot.specialTeamsSlots`, or make the bar tab-aware: keep TEAM constant and swap the second pill to the unit in view (OFF on Offense, DEF on Defense, ST on Special Teams). Either way the number beside the tab you are editing should react when you edit it.

### A green check-circle sits 60 px above a visibly empty slot: '✓ 1/1 · 2/3 deep' is rendered identically to '✓ 4/4 · 8/8 deep'
- **lens:** Designer
- **evidence:** On dc_01 the Quarterbacks header pill reads a green (#22C55E) checkmark.circle.fill followed by '1/1 · 2/3 deep'; directly under it the QB card's third row reads '3RD   Tap to assign' with a dashed + affordance. The Receivers header two groups down reads the same green check with '4/4 · 8/8 deep' — a genuinely complete room — in the identical colour, glyph and pill treatment. The indicator has only two states (check/green, exclamation/amber) for three real ones: complete, starters-plus-one-backup-but-not-full, and no-backup.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:600`
- **fix:** Split the glyph from the fraction. Keep the ✓/! circle bound to `isGroupSound` (the injury-risk question) but paint the '2/3 deep' fraction in `Color.textSecondary` rather than inheriting the green — or add a third state: check on 8/8, `circle.righthalf.filled` in `textSecondary` on 2/3, exclamation in warning on a room with no backup. Right now green + ✓ over an empty 'Tap to assign' row reads as 'nothing to do here'.

### 'STARTER' — the one word the screen exists to assign — renders at 8 pt cap height, the same step as '$848K', while the OVR you cannot change here gets 14 pt bold in a coloured box
- **lens:** Designer
- **evidence:** Measured on dc_01_offense.png: the 'STARTER' glyphs on the QB starter row span device rows 935–950 = 16 px = 8.0 pt of cap height. The row uses exactly two type sizes — 14 pt for the name and the OVR badge, 10 pt for everything else — with nothing between. Four of the six strings in every row sit on the 10 pt step: the depth rank, the position, 'Age 28', and '$848K'. Across dc_01's 11 visible player rows that is 44 strings at the ladder's documented legibility floor.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:745`
- **fix:** DSTokens.swift:129 calls `micro` (10) 'the legibility floor… badge and chip captions' and offers `caption` (11) and `footnote` (12) above it. Promote the depth label to `DSType.Size.footnote` with `.weight(.heavy)` and tracking so STARTER/BACKUP/3RD out-rank the contract meta, and leave age/salary at `micro`. That restores a three-step row hierarchy (14 name / 12 rank / 10 meta) without touching row height.

### The green/amber rule on the group pill is never stated and looks self-contradictory: one room is green with a hole, the next is amber with a hole
- **lens:** Casual player
- **evidence:** dc_01: "Quarterbacks — ✓ 1/1 · 2/3 deep" in green, over a card whose 3RD row reads "Tap to assign". Directly below it: "Backfield — (!) 2/2 · 4/5 deep" in amber, over cards whose FB BACKUP row also reads "Tap to assign". Two rooms, one empty slot each, identical-looking empty rows, opposite traffic lights, and no sentence anywhere explaining the difference. The string "X/Y deep" is itself never defined on screen — the one legend line on the page ("4 groups · 12 positions ⚡ fatigue · lower is better") explains the fatigue meter and nothing else.
- **code:** `DepthChartView.swift:562`
- **fix:** The rule is `hasThinRoom` at DepthChartView.swift:562-565 (amber when any slot with maxDepth > 1 has fewer than 2 bodies) and it is already written in plain English — but only for VoiceOver, in the accessibility label at DepthChartView.swift:635 (", a position here has no backup"). Put that clause on the screen: when !isGroupSound, print it beside the pill, or replace the pill text at DepthChartView.swift:602 with "No backup at FB" / "No backup at MLB, ROLB" and demote "4/5 deep" to secondary. While there, extend the legend row at DepthChartView.swift:508 with "deep = slots filled" so the numerator/denominator is readable on first sight.

### The tab bar's warning counts only empty STARTER slots, so an amber room on another tab is invisible until you scroll it
- **lens:** Casual player
- **evidence:** In dc_01 the "Defense" and "Special Teams" tabs are plain text with no glyph and no count. Switch to dc_02 and the Linebackers header is amber: "(!) 3/3 · 4/6 deep", with MLB BACKUP and ROLB BACKUP both reading "Tap to assign". The reverse holds too — the Offense tab carries no mark in dc_02 or dc_03 while dc_01's Backfield room is amber. A casual player who lands on Offense, sees a clean tab strip and leaves has been given no signal that two defensive rooms have nobody behind the starter.
- **code:** `DepthChartView.swift:64`
- **fix:** `unfilledStarters(on:)` at DepthChartView.swift:64-68 tests only `depthOrder(for:).first == nil`, while the group pill one level down also tests `hasThinRoom` (DepthChartView.swift:562). Make the tab badge use the union of the two so the triangle at DepthChartView.swift:345-354 lights for a thin room as well, and distinguish the two states in the badge (red triangle for an empty starter, amber dot for a thin room) so the harder problem still outranks the softer one.

### After a manual change nothing says it saved or what it cost — the only moving number drops 9 points and stays the same green
- **lens:** Casual player
- **evidence:** dc_03 → dc_04 is one tap apart. The entire visible difference on a 2064×2752 screen is two names swapping inside the KR card and the Returners pill going from "AVG 93" to "AVG 84". Both render green (93 is #5BE08A, 84 is #22C55E) with the same ✓ glyph and the same "2/2 · 4/4 deep" text beside them, so a 9-point drop in the room's quality reads as no change at all. The headline bar above stays frozen at "TEAM 73 · OFF 74 · DEF 72" across dc_03, dc_04 and dc_05. No banner, no toast, no "Saved" mark — a first-time player cannot tell whether the tap took effect, let alone whether it was a good idea.
- **code:** `DepthChartView.swift:613`
- **fix:** The headline bar is correctly inert here — TeamStrength.lineupSlots deliberately excludes K/P/KR/PR (ScheduleView.swift:20-29) — so the feedback has to come from the group pill. At DepthChartView.swift:613-621, hold the previous starterAvg in @State and render a delta chip beside it for a few seconds after a change ("AVG 84 ▼9", arrow in Color.danger), the same up/down treatment the picker already uses for ovrDelta at DepthChartView.swift:1223-1231. Cheaper still: reuse the toast machinery (flashAutoSetMessage, DepthChartView.swift:464) from the two reorder buttons at DepthChartView.swift:709-735 so a manual swap says "Kwabena Winchester is now your kick returner" — today the automated action gets a confirmation sentence and the deliberate one gets nothing.

### Every row prints a salary with no term — half a contract on the row that decides who plays
- **lens:** Hardcore player (tosipelaaja)
- **evidence:** 'WR Age 32 $54.0M' on Braithwaite, 'WR Age 29 $4.8M' on Vandenberg, 'RB Age 24 $1.8M' on Harlan Tanguay, and '$848K' repeated on five separate men across Offense and Defense (Maddocks QB, Winchester WR2, Easton Maddocks DE, Sincere Braithwaite DT, Elias Klingman MLB). No years-remaining figure appears on any of the 30-plus rows across the three tabs.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:806`
- **fix:** The row already commits the horizontal space to money (`Text(CommittedCapLedger.money(player.annualSalary))`, :806) and `Player.contractYearsRemaining` exists (Player.swift:137) but is rendered nowhere on this screen — the comparison sheet substitutes 'Age N' + 'Nyr pro' (:1197-1202), which is service time, not term. An annual number without a term cannot be reasoned about: $54.0M expiring and $54.0M with four years to run are opposite decisions about whether the 32-year-old stays the WR1. Append it: '$54.0M - 2yr', and mark the final year ('$54.0M - exp').

### No trajectory on any row, though the app already stores per-player development entries the chart could join to
- **lens:** Hardcore player (tosipelaaja)
- **evidence:** The RB card reads 66 / 65 / 64 — three backs within two points, aged 25 / 25 / 24, at $894K / $852K / $1.8M — with nothing on any row to separate them. Every row across all three tabs is the same static tuple: name, position, age, salary, OVR badge. No arrow, no delta, no prior-season figure appears anywhere on the screen.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:784`
- **fix:** `playerSlotContent` (:784-848) renders exactly position/age/salary plus injury, fatigue and OVR — no progression term. The data already exists and is already persisted: `Career.developmentReports` (Career.swift:683) holds risers / breakouts / stalled as `Entry` values keyed by `playerID` (DevelopmentReport.swift:25-33). Join the latest report in the indicator column at :815 and draw a small up-chevron for a riser, a flat dash for stalled, with the entry's `detail` string ('+1 Route Running') as the accessibility label. That is the difference between guessing at 66/65/64 and knowing which of the three is climbing — the whole reason a franchise player opens this screen twice a season.

### The candidate picker's "In Chart" badge only looks at the slot being edited, so nothing warns you that the man you are about to assign already holds two other slots
- **lens:** Game developer
- **evidence:** Three gold STARTER plates on this roster carry one man: WR1 "Wade Braithwaite · WR Age 32 $54.0M · 93", KR "Wade Braithwaite · 93", PR "Wade Braithwaite · 93". None of the three rows carries any marker that the other two exist — the row's indicator column shows only the out-of-position arrow, the injury cross, the fatigue bolt and the OVR badge.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:1171`
- **fix:** `isInDepthChart` at DepthChartView.swift:1171 is `depthChart.depthOrder(for: slot).contains(player.id)` — scoped to the one slot open in the sheet — so opening PR shows no "In Chart" tag for a man who is already the WR1 and the KR. Widen it to the whole chart and label it with the conflict ("WR1 · KR"), and add the same marker to `playerSlotContent` (:784-848) beside the out-of-position arrow. DepthChart.swift:246-255 deliberately permits a returner slot on top of a position slot, which is right — but a permitted double-booking still has to be visible on the row that made it.

### Fatigue is depth-blind in the weekly advance, so the metric the legend promotes could never be a reason to reorder anything
- **lens:** Game developer
- **evidence:** All three sub-headers read "⚡ fatigue · lower is better" — the screen's own legend row, elevating fatigue to one of the two things it says the chart is about. The only control on a row is the up/down reorder pair. (Not re-filing the already-logged fact that no fatigue value renders — this is why the meter would be inert even when it does.)
- **code:** `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:1904`
- **fix:** WeekAdvancer.swift:1904-1907 adds `Int.random(in: 3...8)` to every non-injured, non-holdout player on every roster with no reference to role — the 3rd-string guard fatigues at the starting QB's rate. That is F-18's unshipped item (3). Scale the weekly add by depth index (starter full, backup ~half, 3rd string minimal) once the chart is readable by the engine; until then the bolt meter on this screen is reporting a quantity the manager has no lever over, and the legend should not present it as a decision input.


## low

### The position is printed six times inside one card, and the badge and the title next to it are literally the same string
- **lens:** Designer
- **evidence:** The RB card on dc_01 renders, in a 183 pt-tall box: an 'RB' badge, the word 'RB' immediately to its right, 'Running Back' right-aligned on the same line, then 'RB' again in each of the three player meta lines ('RB Age 25 $894K', 'RB Age 25 $852K', 'RB Age 24 $1.8M'). Six position labels for one position. The QB card does the same five times. The badge and the adjacent title are not two renderings of two properties — `slot.shortLabel` is defined as `rawValue` (DepthChart.swift:104–106), the identical string the badge draws.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:659`
- **fix:** Delete `Text(slot.shortLabel)` at line 659 and let the coloured badge carry the abbreviation, or delete the badge and keep the text — one of the two, not both. Keep `slot.displayName` on the right as the plain-language gloss. Leave the per-row `player.position.rawValue` (line 795) alone: on KR/PR it is the only thing telling you the returner is a WR, which is the one place it earns its 10 pt.

### Eight different corner radii nest inside one another against a three-step token scale
- **lens:** Designer
- **evidence:** Reading dc_01 top to bottom from the summary bar to a rating badge, every container is a rounded rectangle at a different radius: summary bar 10, tab-bar container 14, selected tab pill 10, group header 10, group status pills Capsule, position card 12, depth row 8, OVR badge 6, position badge 4, fatigue meter 2. `DSCornerRadius` publishes exactly three steps — tight 4, inline 8, card 12 — and Theme.swift:226 states 'Anything else is a deliberate exception — tools/lint/design_tokens.py counts the off-scale literals'. This file contains 13 off-scale radius literals (10 ×7, 14 ×1, 6 ×2, 3 ×1, 2 ×2) plus three hard-coded 12s that should read `DSCornerRadius.card`.
- **code:** `dynasty/dynasty/UI/Roster/DepthChartView.swift:304`
- **fix:** Map them onto the ladder: the summary bar, tab-bar container and group header are containers → `DSCornerRadius.card` (12); the tab pills and OVR badge are chips → `DSCornerRadius.inline` (8); the fatigue meter cap stays `DSCornerRadius.tight` (4). That leaves three radii on the screen instead of eight and removes the file from the lint's off-scale count.
