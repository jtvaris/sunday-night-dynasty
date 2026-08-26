# /analyze-app — Training Camp & Roster Cuts, four-lens persona audit (2026-08-26)

Evidence: five screenshots off a **cloned** simulator (the user's save was never touched),
Debug build confirmed live by `PERF|launch_to_menu` in the console.
Functional sweep run before the personas: preset chips PASS, heat-map cell tap PASS.

**68 findings from 8 persona agents; 6 refuted by an adversarial verifier reading the source; 62 stand.**

| severity | count |
|---|---|
| blocking | 5 |
| high | 10 |
| medium | 36 |
| low | 11 |


## blocking

### The plan you save in the Roster Cuts phase is never applied, and the action bar promises it will be
- **lens:** Casual player · **screen:** Training Camp — Training Plan
- **evidence:** The screen's own header reads "ROSTER CUTS FOCUS" and the gold action bar reads "SAVE — ROSTER CUTS FOCUS" / "Banks 40/15/45 tactical, physical and technical for the Roster Cuts development pass." with an enabled "Save plan" button. There is no Roster Cuts development pass. `TrainingPlanEngine.applyWeekly` has exactly one call site (WeekAdvancer.swift:8591) inside `applyCampWeeklyTick`, and that function is called from exactly three places — WeekAdvancer.swift:4038 `.otas`, :4137 `.trainingCamp`, :4281 `.preseason`. The row is keyed on `phaseRaw` (TrainingPlanView.swift:632-652, fetch at :605-620), so a row stamped "RosterCuts" is never fetched by anything. A casual player reaches this screen the way the app offers it: during rosterCuts the dashboard's phase quick-actions still include `QuickAction(icon: "figure.run.circle", label: "Training", destination: .trainingPlan)` (CareerDashboardView.swift:1115), because `SeasonPhase.rosterCuts` maps to the `.preSeason` group (SeasonPhase.swift:96). He picks a preset, presses Save plan, is told "Plan saved", and the hub tile then prints "40 / 15 / 45" in gold — under a doc comment that claims "the hub cannot print a split the engine will not use" (CareerDashboardView.swift:1487).
- **code:** `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:119`
- **fix:** Two cheap halves. (1) Gate the entry points: drop `.trainingPlan` from the `.preSeason` quick-action list and hide `trainingPlanTile` when `career.currentPhase == .rosterCuts`. (2) Make the editor honest if it is still reachable: in `commitBar` (TrainingPlanView.swift:111-128), when `career.currentPhase` is not one of `.otas / .trainingCamp / .preseason`, replace the "Banks …" message with "Camp training is over — this split will not run until next season's OTAs", set `isWarning: true`, and disable Save. Do not leave a Save button that writes a row nothing reads.

### The plan banked in Roster Cuts is written to a key nothing ever reads — the action bar promises a pass that does not exist
- **lens:** Hardcore player (tosipelaaja) · **screen:** Training Camp — Training Plan
- **evidence:** Header reads "ROSTER CUTS FOCUS". The pinned bar reads "SAVE — ROSTER CUTS FOCUS / Banks 40/15/45 tactical, physical and technical for the Roster Cuts development pass" beside a live gold "Save plan" button. Both strings come from currentPhase == .rosterCuts, and there is no Roster Cuts development pass.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/TrainingPlanView.swift:642`
- **fix:** Save writes phaseRaw = career.currentPhase.rawValue ("RosterCuts"), line 642. The only reader is WeekAdvancer.fetchOrSeedTrainingPlan (WeekAdvancer.swift:8736), called solely from applyCampWeeklyTick (8583), which fires only for .otas / .trainingCamp / .preseason (4038 / 4137 / 4281) — and rosterCuts is the phase AFTER preseason (SeasonPhase.swift:62), so every camp tick has already run. The same dead-write happens for .regularSeason (headerTitle line 137 prints "Week N Focus"). Fix: make the entry point honest — when currentPhase has no pass, either route the plan forward (persist to the next phase that ticks) or open the screen read-only with the bar saying "camp is spent; this split applies from next OTAs". Do not leave an enabled Save that banks nothing.

### "Save plan" during Roster Cuts banks a plan no engine path ever reads
- **lens:** Game developer · **screen:** Training Camp — Training Plan
- **evidence:** Section header reads "ROSTER CUTS FOCUS"; the pinned action bar reads "SAVE — ROSTER CUTS FOCUS" / "Banks 34/33/33 tactical, physical and technical for the Roster Cuts development pass." (and "Banks 40/15/45 …" after the Fundamentals chip), with an active gold "Save plan" button.
- **code:** `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:119`
- **fix:** There is no Roster Cuts development pass. save() stamps phaseRaw = career.currentPhase (TrainingPlanView.swift:642), i.e. "RosterCuts". TrainingPlanEngine.applyWeekly has exactly one call site — WeekAdvancer.swift:8591 inside applyCampWeeklyTick — invoked only at WeekAdvancer.swift:4038 (.otas), :4137 (.trainingCamp), :4281 (.preseason). The .rosterCuts exit (WeekAdvancer.swift:4290-4319) resolves position battles, trims AI rosters and generates news; no development pass. fetchOrSeedTrainingPlan (:8736) queries by phaseRaw, so the saved "RosterCuts" row is never matched. Worse, CareerShellView.swift:2977-2992 marks the shell task "Set training focus" DONE off that same dead key, so the game confirms the plan is set. The screen is reachable here because the Training quick action is offered for the whole .preSeason group (CareerDashboardView.swift:1115) and SeasonPhase.swift:62 puts .rosterCuts in it. Fix: either run a development pass with the saved plan on the .rosterCuts → .regularSeason advance, or drop .rosterCuts from the Training quick action and render the screen read-only there ("camp is over — this is the split that ran").

### The Technical lane can SUBTRACT position skill — it clamps the attribute down to the development ceiling
- **lens:** Game developer · **screen:** Training Camp — Training Plan
- **evidence:** Technical slider reads "Drills + fundamentals → position skill" at 45%, and the selected gold chip reads "Fundamentals 40/15/45" — the largest of the three shares. The roster below carries five specialists (K Winchester, K Derringer, K Nadeau, P Marsden, P Bourgeois on the heat-map).
- **code:** `dynasty/dynasty/Engine/Camp/TrainingPlanEngine.swift:124`
- **fix:** applyTechnicalDelta passes `current: 0` into rollPoints, so the `guard current < ceiling` gate at TrainingPlanEngine.swift:114 never fires — unlike the Tactical and Physical lanes (:56, :66), which pass the real value. It then writes `min(cap, attr + bump)` with `cap = min(99, ceiling)` (:126, :130-155), so any player whose bumped attribute already sits above developmentCeiling is SET DOWN to the ceiling. developmentCeiling is truePotential for pot ≤ 84 (PlayerDevelopmentEngine.swift:67-71), and veteranPotential returns overall + 0…2 at or past peak (LeagueGenerator.swift:927-935). Since overall = 0.5·positionAvg + 0.3·physicalAvg + 0.2·mentalAvg (Player.swift:578-582), any position attribute above the player's OVR is exposed; for kickers and punters, whose physical/mental averages drag OVR far below positionAvg = (kickPower + kickAccuracy)/2 (PlayerAttributes.swift:147-153), the hit is near-certain and double-digit. It fires on the seeded 34/33/33 plan too — three camp ticks at ~20% per player per week. Fix: pass the real current value per position into rollPoints, and write `max(current, min(cap, current + bump))` so training can never reduce an attribute.

### FREES/DEAD are priced off a contract length the game never advances — the row contradicts its own YRS column
- **lens:** Hardcore player (tosipelaaja) · **screen:** Roster Cuts
- **evidence:** Row 5, Wade Braithwaite: YRS reads 1, FREES reads "−$20.5M" (red) and DEAD reads "$74.5M". Those three cannot all be true. The engine's own identity is capSavings = salaryRelieved + proratedPerYear − deadCap, and with one year left proratedPerYear = deadCap/1 = deadCap, so capSavings collapses to salaryRelieved, which is never negative. A negative FREES therefore proves the split was priced over 2+ remaining years while the YRS cell beside it prints 1. Sanity check on the same screen: every row whose YRS is small shows a small dead figure (row 11 Bodie Balfour, YRS 2, +$2.8M / $0.8M) — Braithwaite is the one row with a real Contract record and he is the one row that is impossible.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/Engine/Contract/CapManagementEngine.swift:316`
- **fix:** CapManagementEngine.tradeCapSplit:316 uses `years = max(1, contract.totalYears - contract.currentYear)` whenever a Contract row exists. `Contract.currentYear` is only ever WRITTEN as 0 (ContractEngine.swift:618, :1147, :1522, :1533) and is never incremented — Player.swift:168 states this outright: "`Contract.currentYear` is never advanced anywhere in the game — `Player.contractYearsRemaining` is the authority on years left". So every player with a Contract row is released as if his entire original deal were still ahead of him, and the bonus for years he has already played accelerates onto the cap. Fix: make :316 read `years = max(1, player.contractYearsRemaining)` (same source the YRS cell at RosterCutView.swift:830 uses) — or advance `Contract.currentYear` at the league-year rollover — so the row's YRS and its money come from one clock. This is also the upstream cause of Braithwaite's $54M implied cap hit that skews keepScore, so it is worth fixing before the already-filed cut-order item.


## high

### The heat-map has no heat: the healthy and under-loaded fills measure 1.04:1 against each other
- **lens:** Designer · **screen:** Training Camp — Workload heat-map
- **evidence:** camp_03: the 8 "healthy" cells fill #0F322D, the 45 "under-loaded" cells fill #222A3A. Computed contrast between those two fills = 1.04:1 (each against the #0B1222 page: 1.35:1 and 1.30:1). The entire colour signal of the map therefore lives in a 1 px stroke (#1C994F on green cells vs #6B7687 on grey ones) and a 20 pt glyph. At arm's length the grid reads as 53 identical dark rectangles.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:97`
- **fix:** Line 97 is `.fill(tint.opacity(0.18))` for all four states. Give the states different weights, not the same one: drop under-loaded to a flat `Color.backgroundSecondary` + `surfaceBorder` stroke so "nothing to see here" recedes, and raise healthy/over-loaded/burned-out to ~0.35–0.45 opacity so a flagged man is legible without reading his glyph. The stroke at line 101 should then only fire for the flagged states.

### The grid is unsorted, so the most-loaded player on the roster is cell 51 of 53
- **lens:** Designer · **screen:** Training Camp — Workload heat-map
- **evidence:** camp_01 labels its table "TOP 30 OF 53 BY LOAD" and puts RB Kenji Hambleton in row 1 with the fullest LOAD bar. On camp_03 that same Hambleton is the bottom-left cell — row 11 of 11, 51st of 53 — while the top-left cell is DE Goddard, who reads "–" (under-loaded). The 8 green cells land at grid positions 2, 13, 32, 39, 41, 44, 50, 51: no reading order at all.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:71`
- **fix:** `ForEach(roster, id: \.id)` iterates the fetch order. Sort it the way the sibling screen already does — TrainingPlanView.swift:453-460 sorts `cumulativeLoad` descending, with a comment stating exactly this rule ("the men this table exists to warn about have to be the men it shows"). Sort worst-state-first so the top-left corner is always the man to look at.

### A heat-map that encodes no magnitude — 53 cells, zero numbers
- **lens:** Designer · **screen:** Training Camp — Workload heat-map
- **evidence:** Every cell on camp_03 prints exactly three things: position, one glyph, surname ("DE / – / Goddard"). The load value appears only in camp_04's sheet, one player per tap ("Cumulative load  42 / 100"). Comparing two players' load costs two sheet open/dismiss cycles and a memorised number; ranking the 45 grey cells against each other is impossible from the grid.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:80`
- **fix:** Put `player.cumulativeLoad` in the cell as its numeric hero (monospaced digits, `DSType.display`), and drive the fill from the continuous value rather than only the 4-way bucket, so the map has a gradient rather than four flat steps. The width for it already exists — see the 73–79% empty cell width finding.

### Four presets, zero yield information — and the one preset that behaves differently is invisible
- **lens:** Hardcore player (tosipelaaja) · **screen:** Training Camp — Training Plan
- **evidence:** The chips read "Balanced 34/33/33", "Scheme Heavy 60/20/20", "Conditioning 20/50/30", "Fundamentals 40/15/45". Tapping Fundamentals changes the bar only to "Banks 40/15/45 tactical, physical and technical for the Roster Cuts development pass". No projected effect, no units, no per-week ceiling is stated anywhere on the screen.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/Engine/Camp/TrainingPlanEngine.swift:92`
- **fix:** tacticalDelta / physicalDelta / technicalDelta (lines 92, 98, 104) are the identical function pct/100 × 0.6, and the per-attribute weights are awareness ×1.0 + decisionMaking ×0.7, stamina ×1.0 + durability ×0.8, one position attribute ×1.0. Expected attribute points per player per week: Balanced 0.90, Scheme Heavy 0.95, Conditioning 0.92, Fundamentals 0.84 — a 12% spread across the whole chip row. The one real discontinuity is line 82, bump = Int((tDelta × 1.5).rounded()): scheme familiarity moves only at tactical ≥ 56%, so Scheme Heavy (60) is the sole preset that touches it and Balanced (34) never does. Print the projected weekly effect under each slider ("+0.36 awareness, +0.25 decision-making per week") and put the scheme bump on the Scheme Heavy chip; a min-maxer currently cannot tell the choice is near-inert or where its only cliff sits.

### The INJ column prints a percentage the simulation never rolls, with no time unit
- **lens:** Hardcore player (tosipelaaja) · **screen:** Training Camp — Training Plan
- **evidence:** Eleven visible INJ cells read 4.6, 4.4, 4.3, 4.6, 4.6, 4.6, 4.4, 4.3, 4.6, 4.6, 4.6 % — a 0.3-point spread across a DUR spread of 60 to 81. The header is the bare word "INJ"; nothing on screen says per play, per day, per week or per camp.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/TrainingPlanView.swift:490`
- **fix:** Line 490 calls WorkloadEngine.injuryRiskPct(player:baseRisk: 0.04) — a literal chosen in the view, and the function's only call site in the app. Its durability term (WorkloadEngine.swift:239) is (99−dur)/99×0.4+1.0, range 1.00–1.24. The engine that actually injures players uses base 0.005 per play and durability as 1 − dur/200, range 0.505–0.80 (MedicalEngine.swift:90 and :96) plus fatigue, doctor, facility and rush-back terms. So the column understates durability's leverage by roughly half (1.24× vs 1.96×) and its absolute value corresponds to no roll the game makes; camp weeks roll no injury at all (applyCampWeeklyTick never calls injuryCheck). Derive the column from MedicalEngine's own terms, express it over a stated period ("per preseason game", "over camp"), and label the header with that period.

### 53 cells in database order — the states the map exists to surface are not ranked or grouped
- **lens:** Hardcore player (tosipelaaja) · **screen:** Training Camp — Workload heat-map
- **evidence:** The grid is 53 cells: 8 green with "✓", 45 grey with "–", zero yellow and zero red although the legend advertises "Over-loaded" and "Burned out" and the blurb says "Yellow / red flags signal injury risk". The green cells sit at grid positions 2, 13, 32, 39, 41, 44, 50 and 51 — scattered. Positions are not grouped either: the two QBs are cells 2 and 30, the three Ks are cells 34, 36 and 53.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:71`
- **fix:** Line 71 is ForEach(roster) with no sort, and the roster handed in is an unsorted FetchDescriptor (CareerShellView.swift:2462). The sibling table already does this right and says why — TrainingPlanView.swift:453 ranks heaviest-load-first with a comment that the burnout "could sit entirely inside the rows that never rendered". Sort the grid by cumulativeLoad descending (or bucket by status with headers), and add a one-line tally above it ("0 burnt · 0 over-loaded · 8 healthy · 45 under-loaded") so a 20-season player reads the club's state without counting 53 tiles.

### The user's roster is ticked with the per-day rounding the engine documents as defective; the bands were calibrated on the netted path only AI clubs use
- **lens:** Game developer · **screen:** Training Camp — Workload heat-map
- **evidence:** Workload Detail reads "Cumulative load 42" for a Healthy player; the map is 45 "–" to 8 "✓" with nothing above Healthy — while the band note calls 37 the tenth percentile and says "the median man stays .healthy".
- **code:** `dynasty/dynasty/Engine/Simulation/WeekAdvancer.swift:8603`
- **fix:** WeekAdvancer.swift:8603-8615 ticks the user's 53 men through WorkloadEngine.tickDay seven times per phase; :8714 ticks all 31 other clubs through tickWeek. tickDay rounds load and recovery to integers separately every day (WorkloadEngine.swift:211, :214) — exactly the defect WorkloadEngine.swift:35-41 documents ("rounding recovery UP (0.55 → 6) and therefore under-reporting load") and that the fix removed from tickWeek only (:180-182). The 37/64/73 thresholds (:62-64) are explicitly anchored to the tickWeek distribution (mean 50, sd 9.8, p10 37, p90 64, :44-45). Consequence: each phase adds exactly 7 × an integer to a user player, so the map has no reachable value between 35 and 42 — one rounding step decides "–" vs "✓" — and the user's roster sits systematically below the p10 line the bands call "under-worked", which is why 45 of 53 cells are gray. The strength coach's 1-99 rating also re-collapses into five reachable values on this path, undoing the resolution :156-166 was written to restore. Fix: net the user's week with tickWeek too and derive the seven WorkloadEvent rows by splitting the netted total rather than re-deriving them per day.

### Every number on the screen is cap money and the screen never says what the cap is
- **lens:** Hardcore player (tosipelaaja) · **screen:** Roster Cuts
- **evidence:** Fourteen columns, two of them money ("FREES", "DEAD"), values from "+$0.7M" to "−$20.5M" and "$74.5M", and the footer reads "CUTDOWN COMPLETE — Your roster is at 53. Nothing more is owed here." Nowhere on the screen — not the band, not the chips, not the header strip, not the action bar — is there a salary-cap total, a cap-space figure, a payroll total, or the player's own cap hit. The one summary the screen prints is a headcount.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:1077`
- **fix:** The data is already loaded: `loadedTeam` is fetched at RosterCutView.swift:1529 and `Team` carries `salaryCap` and `currentCapUsage` (Team.swift:106/109). Put "Cap $X used of $Y · $Z space" in the band alongside the roster count, and extend the action-bar explainer (RosterCutView.swift:1062-1112) so a live selection reads "…frees $A, leaves $B dead → $C of space after". Also add a HIT column: the cap hit is currently only obtainable by adding FREES + DEAD in your head on 53 rows, and it is the denominator for every judgement on this screen.

### "Cutdown complete" is a headcount only — the finished 53 is never checked for shape
- **lens:** Hardcore player (tosipelaaja) · **screen:** Roster Cuts
- **evidence:** The filter chips read "All 53 · QB 2 · RB/FB 5 · WR/TE 10 · OL 12 · DL 8 · LB 4 · DB 7 · ST 5" (they sum to exactly 53, so every player falls in exactly one chip and the ST chip covers only K and P). That is a 53-man roster carrying five kickers and punters, twelve offensive linemen and four linebackers — and the screen stamps "CUTDOWN COMPLETE", three green ticks, and "Nothing more is owed here." over it. The header strip reads only "WORST FIRST · YOUR STAFF'S CUT ORDER" with no room line beside it.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:1259`
- **fix:** `isDueStageComplete` is `activeRoster.count <= stage.target` — a pure count — and the only room-by-room readout, `selectionImpacts`, dies the moment nothing is ticked (`guard !releasing.isEmpty else { return [] }`, RosterCutEvaluator.swift:173). So the roster's shape is checked only against per-position FLOORS (minimumCount: 1, QB 2, RosterCutEvaluator.swift:136) and only while a selection is live; there are no ceilings and no check at all on the finished 53. Keep the impacts strip alive with the CURRENT rooms against a target band (min/typical/max per group), tint rooms outside it, and make the completion copy carry it: "53 — LB 4 (thin), K/P 5 (heavy)". A min-maxer will take the warning; the tick as it stands is the screen certifying a roster it never inspected.

### YRS and the money columns on the same row are priced on two different contract terms
- **lens:** Game developer · **screen:** Roster Cuts
- **evidence:** Row 5 reads: Wade Braithwaite · OVR 93 · AGE 32 · YRS 1 · FREES −$20.5M · DEAD $74.5M. Those three numbers cannot all be true. capSavings = salaryRelieved + proratedPerYear − deadCap, and at leagueYearRemaining 1.0 salaryRelieved = salary − proratedPerYear, so salary = deadCap + capSavings = $54.0M. Put years = 1 through the same math: proratedPerYear = $74.5M, base clamps to 0, and capSavings comes out exactly $0.0M — not −$20.5M. The row is only self-consistent at years = 2 (prorated $37.25M, base $16.75M, savings −$20.5M). The '1' in YRS is provably not the term this money was priced on.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:829`
- **fix:** contractYearsCell prints player.contractYearsRemaining, while the split takes its acceleration term from `contract.totalYears - contract.currentYear` whenever a Contract row exists (CapManagementEngine.swift:315-322). Price the YRS cell off the same source the money uses — contractsByPlayer[player.id] first, contractYearsRemaining as fallback — so the term and the dead money on one row can never disagree. Separately, player.restructureDeadMoney is added OUTSIDE the `min(rawDead, salary × years)` clamp (CapManagementEngine.swift:343), which is the one legitimate way DEAD can exceed the deal; when it is non-zero, mark the row (a 'restructured' marker on DEAD, or the subline) so a dead figure larger than the contract can explain itself. This is the number that ranks the club's MVP fifth in the cut order, so it is the last one on the screen that should be unexplainable.


## medium

### Camp grade is painted in the primary-action gold whatever the letter, so a D reads as a commendation
- **lens:** Designer · **screen:** Training Camp — Workload heat-map
- **evidence:** camp_04: "Camp grade    D" renders at #C9A94E — the identical token as the "Save plan" button fill and the "ROSTER CUTS FOCUS" section header on camp_01. The screen's call-to-action colour and its worst-but-one grade are the same pixels.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:157`
- **fix:** `tint: Color.accentGold` is unconditional. The app already owns the ladder — `Color.forGrade` (GradeColors.swift:39) and RosterCutView.swift:967 `gradeColor(_:)`, whose comment at line 960 documents this exact fix on the other camp screen: "Every grade used to be one flat `accentGold`... Gold is also the screen's primary button." Reuse it. And because the curve is currently degenerate (known), print the letter's meaning beside it (percentile, or "C = squad median") so a row that never varies stops looking like a verdict.

### The status glyph is emoji (🔥 / 💀) on the one screen the design standard exempted by accident
- **lens:** Designer · **screen:** Training Camp — Workload heat-map
- **evidence:** camp_03 renders "–" and "✓" as the cell's largest element; camp_04's sheet renders "Status   ✓ Healthy". Those glyphs come from `WorkloadStatus.emoji`, whose other two cases are "🔥" and "💀" — so an over-loaded roster shows a grid of fire emoji and VoiceOver reads a cell as "fire".
- **code:** `dynasty/dynasty/Domain/Enums/CampEnums.swift:12`
- **fix:** TrainingPlanView.swift:19-22 and :406-408 record the standard and the exception that was left open: "a status told in EMOJI — 🔥 and 💀 — which §2.12 rules out by name... The model still exposes an `emoji` for the heat-map dashboards." Close it: swap WorkloadDashboard.swift:84 and :140 for SF Symbols on the status tint (`minus` / `checkmark` / `flame.fill` / `exclamationmark.triangle.fill`) plus an `accessibilityLabel` carrying the word, and delete `WorkloadStatus.emoji`.

### Three vocabularies for one four-state enum, on two screens one tap apart
- **lens:** Designer · **screen:** Training Camp — Training Plan + Workload heat-map
- **evidence:** camp_01's pills read `HEALTHY` and `LIGHT`. camp_03's legend, reachable in one tap, reads "Under-loaded · Healthy · Over-loaded · Burned out". camp_04's sheet reads "Healthy" from `rawValue.capitalized` — which for the `.burnedOut` case emits "Burnedout". So the same player state is called LIGHT here, Under-loaded there, and the fourth state has three spellings: BURNT, Burned out, Burnedout.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:140`
- **fix:** Three call sites invent their own strings: TrainingPlanView.swift:409-416 (`Light/Healthy/Heavy/Burnt`), WorkloadDashboard.swift:51-54 (legend literals), WorkloadDashboard.swift:140 (`rawValue.capitalized`). Add one `displayLabel` to `WorkloadStatus` in CampEnums.swift and have all three read it.

### The column rhythm breaks at LOAD: 7 pt between AGE and LOAD, 93.5 pt between LOAD and STATE
- **lens:** Designer · **screen:** Training Camp — Training Plan
- **evidence:** Measured header label gaps on camp_01: DUR→STA 15.5 pt, STA→AGE 14.0 pt, AGE→LOAD **7.0 pt**, LOAD→STATE **93.5 pt**, STATE→INJ 33.0 pt. In the data row the age "24" sits 10.0 pt from the start of the load bar where DUR→STA is 24.5 pt, and a 57.0 pt void opens between the bar's end and the HEALTHY pill. The age number reads as a label on the load meter.
- **code:** `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:325`
- **fix:** `DSColumnHeader("LOAD", width: 96, alignment: .leading)` (line 325) and `.dsColumn(96, alignment: .leading)` (line 384) are the only `.leading` entries in an otherwise all-`.center` column set, and DSListRow lays columns out in `HStack(spacing: 0)` (DSListRow.swift:617) — so a leading-aligned column abuts its neighbour with zero gutter and dumps 100% of its slack on the right. Drop `alignment: .leading` from both so the meter centres in its slot, or shrink the column to the meter's real width.

### Cell hierarchy is inverted: the 20 pt hero glyph is a hyphen in 45 of 53 cells, the identifying name is smallest and dimmest
- **lens:** Designer · **screen:** Training Camp — Workload heat-map
- **evidence:** camp_03 cell anatomy, measured: `DE` at 11 pt bold #F1F5F9 (13.1:1), then the status glyph at 20 pt #FFFFFF, then `Goddard` at 10 pt #94A3B8 (5.6:1). The eye lands on a hyphen, then on a position abbreviation that repeats across the grid (TE appears 4×, DE 5×, CB 4×), and only last on the surname that says who this is.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:81`
- **fix:** Invert the stack in `cell(for:)`: surname first at 12–13 pt semibold in `textPrimary`, load number as the numeric hero, position demoted to a `textSecondary` caption. The status should be carried by the cell fill (see the 1.04:1 finding), not by a character.

### Two yellows one degree of hue apart mean two different things on the same scroll, and accentGold carries five jobs
- **lens:** Designer · **screen:** Training Camp — Training Plan
- **evidence:** Measured on camp_01: #C9A94E (hue 44.4°) paints the "ROSTER CUTS FOCUS" and "PER-PLAYER WORKLOAD" headers, the selected "Balanced" chip fill, the Technical slider track and its "33%", the "Show all 53" button and the "Save plan" button. #EAB308 (hue 45.4°) simultaneously paints "OVR 62", "OVR 66", "DUR 63" — the 60–69 rating band. One degree of hue separates "this is the commit button" from "this player is mediocre". Green does the same double duty: #22C55E is both the Physical focus slider and the HEALTHY pill and the INJ figure.
- **code:** `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:225`
- **fix:** The three focus sliders borrow the semantic palette (accentBlue :211, success :219, accentGold :225) which the rows 500 px below use for rating tiers and health. Give the three focus areas their own non-semantic triad (or distinguish them by label + fill pattern rather than by the status hues), and keep `accentGold` (Theme.swift:25) for commit + selected-state only, so the one gold thing on screen is the thing to press.

### The INJ column spends a slot and a colour to repeat what the STATE pill just said
- **lens:** Designer · **screen:** Training Camp — Training Plan
- **evidence:** camp_01, the 12 visible rows read 4.6 / 4.4 / 4.3 / 4.6 / 4.6 / 4.6 / 4.4 / 4.3 / 4.6 / 4.6 / 4.6 — a 0.3-point spread — and every one of them is drawn in the same #22C55E as the HEALTHY or LIGHT pill immediately to its left. The channel that draws the eye (colour) is constant across the whole column, so the column reads as noise.
- **code:** `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:392`
- **fix:** The value comes from `WorkloadEngine.injuryRiskPct` but line 394 tints it with `loadTint(for: player.workloadStatus)` — the pill's colour, not the risk's. The code's own comment (lines 483-491) puts the healthy-load range at 4.0–5.6. Either tint INJ on its own thresholds over that range so the 4.3s and 4.6s separate, or fold it into the pill's tooltip and give the 34 pt slot to a figure that varies (this week's load delta).

### Surname renders at 10 pt fixed — under the design system's own documented 11 pt floor, and it does not scale
- **lens:** Designer · **screen:** Training Camp — Workload heat-map
- **evidence:** Measured ink height of "Goddard" on camp_03 = 7.5 pt cap height, i.e. a 10 pt face. It is the smallest type anywhere on either screen (the legend and POS labels measure 11 pt, the subtitle 13 pt) and it is the string that identifies the player.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:87`
- **fix:** `.font(.system(size: 10))` is a raw point size that bypasses `DSType` and ignores Dynamic Type. DSListRow.swift:199-202 states the rule: "One label over one column, in the display voice at the 11 pt floor. Big Board's header shipped at 8 pt bold, which is three steps under the floor." Use `DSType.display(12, .semibold)` — and per the hierarchy finding this text should be the cell's primary line anyway.

### 45 of 53 cells are a bare ASCII hyphen, and the legend maps colours to words but never the glyph to anything
- **lens:** Casual player · **screen:** Training Camp — Workload heat-map
- **evidence:** Counting the grid: 53 cells, 45 of them render "–" over a dark-grey card, 8 render "✓" over a green card, zero render anything else. The legend directly above reads "● Under-loaded  ● Healthy  ● Over-loaded  ● Burned out" — four coloured dots and four words, none of which appear in a cell. The glyph comes from `WorkloadStatus.emoji`, where `.underloaded` returns the string "-" while its three siblings return "✓", "🔥" and "💀" (CampEnums.swift:12-19) — one state opted out of the glyph system entirely. A casual player looking at 45 dashes cannot decode them: dark grey on a dark background is not a legible colour cue, and nothing on the screen connects a hyphen to the phrase "Under-loaded".
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:84`
- **fix:** Print the state as a word in the cell — `TrainingPlanView.workloadLabel` (TrainingPlanView.swift:409-416) already produces "Light / Healthy / Heavy / Burnt" and is the vocabulary the sibling screen uses. If the cell must stay glyph-only, give `.underloaded` a real mark ("○") and change `legendChip` to draw the same glyph it is labelling instead of a coloured dot.

### The screen never states the one number the player opened it for; the tile that links here does
- **lens:** Casual player · **screen:** Training Camp — Workload heat-map
- **evidence:** The header says "Per-player camp load. Tap a cell for detail. Yellow / red flags signal injury risk." There are zero yellow cells and zero red cells on the screen — the player is told to look for flags that do not exist, and is never told that means "all clear" rather than "not computed yet". Meanwhile the dashboard tile that navigates here prints "\(overloaded)% overloaded" over "Injury & burnout risk" (CareerDashboardView.swift:1862-1866, computed at :4332-4338), and the camp hero card prints "Squad workload — X% overloaded" (:4370). So the summary exists two screens up and is dropped on arrival: `WorkloadDashboard.header` is a title and one instruction sentence, with no counts (WorkloadDashboard.swift:39-47).
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:39`
- **fix:** Add one summary line between `header` and `legend`, computed from the same roster the grid already has: "45 under-loaded · 8 healthy · 0 over-loaded · 0 burnt out" — and when over-loaded + burnt out is zero, say so in words ("nobody is at risk this week"). The destination screen has to state the number that made the player tap the tile.

### Camp grade is painted gold whatever the letter — the sheet highlights a D as if it were an achievement
- **lens:** Casual player · **screen:** Training Camp — Workload heat-map (Workload Detail sheet)
- **evidence:** The sheet reads "Camp grade    D" with the D in the app's accent gold — the same hue the selected preset chip, the Save plan button and "Top camp grade" use for emphasis. The tint is unconditional: `statusRow(label: "Camp grade", value: grade.displayLabel, tint: Color.accentGold)`. An A+ and an F get the identical treatment. Every other value in the same sheet is tinted by meaning — Status is tinted by `tint(for:)`, Injury multiplier by whether it exceeds 1.0 — so the one row a casual reads as a verdict is the one row whose colour carries no information, and it miscues in the wrong direction: gold reads as good, the letter says D.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:157`
- **fix:** Tint the grade by the grade: map `CampGrade` onto the existing status palette (`Color.forStatus` / `Color.forRating`) so A+/A are green, B neutral, C/D/F warn-to-bad, and reserve `accentGold` for the emphasis it means elsewhere. One switch on `CampGrade`, next to `displayLabel` in CampEnums.swift:41-49.

### The same four states have two vocabularies one tap apart, and the sheet has a third
- **lens:** Casual player · **screen:** Training Camp — Training Plan + Workload heat-map
- **evidence:** On Training Plan the STATE column prints "HEALTHY" (8 rows) and "LIGHT" (3 rows visible), and the caption above it says "A player who reads Burnt takes only half of the week's gains." One tap away the Workload legend reads "Under-loaded / Healthy / Over-loaded / Burned out". Same enum, different words: `TrainingPlanView.workloadLabel` returns Light/Healthy/Heavy/Burnt (TrainingPlanView.swift:409-416) while `WorkloadDashboard.legend` hardcodes its own four strings (WorkloadDashboard.swift:51-54). The detail sheet invents a third form — `player.workloadStatus.rawValue.capitalized`, which prints the on-screen "Healthy" today but yields "Underloaded", "Overloaded" and "Burnedout" for the other three cases. A casual who learns to watch for "Burnt" will not find it on the heat-map, and will not recognise "Burnedout" as the same thing.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:140`
- **fix:** Put one `displayLabel` on `WorkloadStatus` in CampEnums.swift next to `emoji` — Light / Healthy / Heavy / Burnt, the pair the pill already uses — and read it from all three sites: the pill, `legendChip`, and the sheet's Status row (delete the `rawValue.capitalized`, which can only ever produce mangled text).

### The INJ column has no unit and a 0.3-point spread, so it costs 30 rows and decides nothing
- **lens:** Casual player · **screen:** Training Camp — Training Plan
- **evidence:** The INJ column reads, top to bottom on the 11 visible rows: 4.6% 4.4% 4.3% 4.6% 4.6% 4.6% 4.4% 4.3% 4.6% 4.6% 4.6% — three distinct values, total spread 0.3 percentage points, over a table headed "TOP 30 OF 53 BY LOAD". That is by construction: the label is `WorkloadEngine.injuryRiskPct(player:baseRisk: 0.04)`, and the method's own comment states "at a healthy load the formula's whole range is 4.0–5.6". Nothing on screen says what the percentage is per — the visible header is the three letters "INJ"; only the invisible accessibility string says "Daily injury risk" (TrainingPlanView.swift:393). A casual cannot tell whether 4.6% is a per-day, per-week or whole-camp number, and cannot use it to prefer any player over any other.
- **code:** `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:482`
- **fix:** Put the unit where the eye is: change the visible header to "INJ/DAY" (DSColumnHeader at :327) so the column says what the accessibility label already knows. And while a healthy camp can only emit 4.0–5.6, the column is dead weight on this screen — consider showing it only for rows whose status is Heavy or Burnt (where the 1.6× / 2.5× multiplier actually separates players) and leaving the rest blank.

### The detail sheet has no visible way out and no action in it
- **lens:** Casual player · **screen:** Training Camp — Workload heat-map (Workload Detail sheet)
- **evidence:** The "Workload Detail" card shows a title, a player line, four read-only rows (Status / Cumulative load / Injury multiplier / Camp grade) and empty space — no Done button, no Close, no grab handle at the top of the card. The sheet is `.sheet` + `.presentationDetents([.medium])` inside a `NavigationStack` whose toolbar is empty, with no `.presentationDragIndicator(.visible)` (WorkloadDashboard.swift:32-34, :164-167). Dismissal only works if the player guesses to tap the dimmed area or swipe the card down. It is also a dead end for the casual: he tapped a cell after being told "Yellow / red flags signal injury risk", and the sheet gives him four numbers and nothing to press.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:167`
- **fix:** Add `.presentationDragIndicator(.visible)` and a `.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selectedPlayer = nil } } }` on the NavigationStack. If a next step exists for this player (open his roster card, rest him from the next voluntary workout), put it in the sheet's empty lower half; otherwise say in one line what the player should do with the reading.

### The load scalar the whole feature turns on is printed nowhere except one modal
- **lens:** Hardcore player (tosipelaaja) · **screen:** Training Camp — Training Plan + Workload heat-map
- **evidence:** On Training Plan the LOAD column is a bare capsule with no number, no axis and no tick; the STATE pill flips from HEALTHY (Kaleo Hinsdale LG, bar roughly 60% full) to LIGHT (Brixton Yarborough RB, bar roughly 20%) with nothing on the row saying where the boundary lies. On the heat-map each cell carries only three lines — "QB", "✓", "Hinsdale" — no load, no OVR. The number exists only inside the tapped Workload Detail sheet.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/TrainingPlanView.swift:432`
- **fix:** workloadMeter (line 432) divides by WorkloadEngine.burnoutFloor = 73, and the band edges 37 / 64 / 73 are private constants (WorkloadEngine.swift:62-64). Print the integer load beside the bar and draw the three band edges as tick marks, so "how close is this man to Heavy" is answerable without tapping; put the same integer in the heat-map cell in place of the glyph (WorkloadDashboard.swift:84), which already carries the colour.

### No trajectory anywhere, though the engine writes a per-day load trail for exactly this roster
- **lens:** Hardcore player (tosipelaaja) · **screen:** Training Camp — Workload heat-map
- **evidence:** The Workload Detail sheet's four rows — "Status ✓ Healthy", "Cumulative load", "Injury multiplier x1.0", "Camp grade D" — are all snapshots. Neither screen shows a direction: whether this man is climbing toward Heavy or recovering out of it.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/Engine/Camp/WorkloadEngine.swift:113`
- **fix:** tickDay inserts a WorkloadEvent per player per camp day carrying loadDelta and recoveryDelta, stamped with season / week / dayOfWeek (lines 113-124) — 371 rows per camp week for the user's club, and the engine's own comment at line 138 states "no screen reads them… zero fetch sites", which a grep confirms (only DynastySchema, CareerScope and the wipe path touch the type). Fetch the last 7 (or the camp's 21) rows for the tapped player and draw them as a sparkline in the detail sheet — the data is already paid for and stored.

### One set of four states, three different vocabularies across two screens of the same feature
- **lens:** Hardcore player (tosipelaaja) · **screen:** Training Camp — Training Plan + Workload heat-map
- **evidence:** The Training Plan STATE column reads "HEALTHY" and "LIGHT". The heat-map legend for the same four states reads "Under-loaded · Healthy · Over-loaded · Burned out". The detail sheet reads "Healthy". Nothing tells the player that LIGHT and Under-loaded are the same state.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:140`
- **fix:** Three independent spellings exist: TrainingPlanView.workloadLabel (line 411) yields Light / Healthy / Heavy / Burnt; WorkloadDashboard's legend strings (lines 51-54) yield Under-loaded / Healthy / Over-loaded / Burned out; and line 140 prints workloadStatus.rawValue.capitalized, which renders ".underloaded" as "Underloaded" and ".burnedOut" as "Burnedout" — a fourth spelling the screenshot does not happen to expose because this save has no over-worked player. Put one displayLabel on WorkloadStatus (CampEnums.swift:5) and have all three sites read it.

### Camp grade is a bare letter in a sheet that prints its own dominant input two rows above it
- **lens:** Hardcore player (tosipelaaja) · **screen:** Training Camp — Workload heat-map
- **evidence:** The Workload Detail sheet gives one of its four rows to "Camp grade D" — a letter with no score, no components and no comparison. Nothing on the sheet says what produced it, and nothing distinguishes a 35-point D from a 49-point D.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:153`
- **fix:** CampGradeEvaluator.scoreFor (CampGradeEvaluator.swift:32) already returns the 0-100 score and its doc comment says it is "Exposed so the UI can sort players within the same letter grade" — no UI calls it. Its four terms are training 0-40, preseason snaps 0-25, preseason performance 0-25, OVR floor 0-10, and the training term is fed by cumulativeLoad / 6 (WeekAdvancer.swift:8804) — i.e. the grade is largely a restatement of the Cumulative load row printed two lines above it, which the sheet presents as an unrelated fact. Either show the four components (or the score) so the letter is checkable, or drop the row from this sheet until the curve moves; a column that reads D for nearly every man is costing a quarter of a four-row sheet.

### Four-state legend, two reachable states — and the two that occur are mechanically identical
- **lens:** Game developer · **screen:** Training Camp — Workload heat-map
- **evidence:** Legend: "Under-loaded · Healthy · Over-loaded · Burned out". Caption: "Per-player camp load. Tap a cell for detail. Yellow / red flags signal injury risk." All 53 cells are gray "–" (45) or green "✓" (8) — zero yellow, zero red. Every opened Workload Detail reads "Injury multiplier x1.0".
- **code:** `dynasty/dynasty/Domain/Enums/CampEnums.swift:24`
- **fix:** CampEnums.swift:23-28 gives .underloaded and .healthy the same injuryMultiplier of 1.0, and .underloaded is branched on nowhere else in the engine — the only other consumer, TrainingPlanEngine.swift:47, tests `== .burnedOut`. MedicalEngine.swift:118 says so in its own comment. So the single distinction this 53-cell map ever draws carries zero mechanical consequence, and the two bands that do carry consequence never appear: a full page delivering one bit that means nothing. Fix, UI side first: lead with the number the player came for — "0 of 53 at risk" in the header — and collapse Under-loaded and Healthy into one "No added risk" swatch until they differ. Engine side, if the design wants four states: give .underloaded the mirror of the burnout tax (reduced training gain) so the gray tiles are a cost the player can act on.

### The INJ column restates the DUR column three places to its left and spans 0.3 points across the roster
- **lens:** Game developer · **screen:** Training Camp — Training Plan
- **evidence:** INJ over the 11 visible rows: 4.6, 4.4, 4.3, 4.6, 4.6, 4.6, 4.4, 4.3, 4.6, 4.6, 4.6. DUR on the same rows: 63, 77, 79, 61, 61, 62, 72, 81, 60, 60, 62.
- **code:** `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:490`
- **fix:** injuryRiskLabel calls WorkloadEngine.injuryRiskPct(baseRisk: 0.04) = baseRisk × status.injuryMultiplier × ((99 − DUR)/99 × 0.4 + 1) (WorkloadEngine.swift:237-242). With the multiplier pinned at 1.0 for every player who can appear on this screen, INJ is a strictly decreasing function of DUR alone — the row prints the same fact twice and the second copy is compressed into 0.3 of a point. The comment at :486-489 claims a 4.0-5.6 range at a healthy load; durability floors at 40 (PlayerAttributes.swift:12-21), so the real range is 4.0-5.0 and on this roster 4.3-4.6. Fix: split the two terms so the column earns its width — print "4.3% ×1.0" (durability risk × workload multiplier), which also makes the 1.6 and 2.5 rungs legible the moment they become reachable; or drop INJ and keep DUR until the multiplier can vary.

### 53 tiles in raw fetch order — the flagged men are scattered and there is no count, sort or filter
- **lens:** Game developer · **screen:** Training Camp — Workload heat-map
- **evidence:** 53 cells; row 1 runs DE Goddard, QB Hinsdale, TE Marchetti, CB Pankhurst, DE Brockway — not position-grouped. The 8 "✓" cells sit at grid slots 2, 13, 32, 39, 41, 44, 50, 51 — not load-ordered either. The header offers no at-risk count.
- **code:** `dynasty/dynasty/UI/Career/CareerShellView.swift:2462`
- **fix:** teamRoster is a FetchDescriptor with no sortBy, and WorkloadDashboard.swift:71 renders it in that order. Its own sibling learned this lesson: the Training Plan list sorts heaviest-first and says so in the header ("TOP 30 OF 53 BY LOAD" — TrainingPlanView.swift:449-461, :488). Against the reference bar (an FM squad screen, the OOTP fatigue view), the two gaps that matter are ordering by exposure and stating the at-risk count up front; nobody scans 53 unordered tiles looking for a red one. Fix: sort by cumulativeLoad descending using displayRoster's comparator, and put "N at risk" in the header beside the legend.

### One preset chip is strictly dominated by another, and only one chip clears the hidden scheme-familiarity cliff
- **lens:** Game developer · **screen:** Training Camp — Training Plan
- **evidence:** Four chips read "Balanced 34/33/33", "Scheme Heavy 60/20/20", "Conditioning 20/50/30", "Fundamentals 40/15/45". Slider captions: "Scheme + film → awareness, decision-making" (two attributes), "S&C + conditioning → stamina, durability" (two), "Drills + fundamentals → position skill" (one).
- **code:** `dynasty/dynasty/Engine/Camp/TrainingPlanEngine.swift:82`
- **fix:** Per 100 points allocated the three lanes buy different amounts: Tactical 0.6 + 0.42 = 1.02 expected attribute points (TrainingPlanEngine.swift:56-63), Physical 0.6 + 0.48 = 1.08 (:66-73), Technical 0.6 on a single attribute (:76). Summed over the chips: Scheme Heavy 0.95/week, Conditioning 0.92, Balanced 0.90, Fundamentals 0.84. On top of that the scheme-familiarity bump at :82 is `Int((tDelta · 1.5).rounded())`, which is 0 below tacticalPct 56 and 1 above it — so Scheme Heavy is the only chip that buys any scheme knowledge, and it does so by clearing a cliff nothing on screen shows. Scheme Heavy therefore dominates Fundamentals on both axes, while Fundamentals is the chip the UI dresses in gold. Fix: either give the Technical lane a second position-appropriate attribute so the three lanes are priced alike, or state the exchange rate on the chip ("Fundamentals — one position skill, no scheme work") and replace the cliff with a proportional scheme bump so 40% tactical is worth 40% of what 60% buys.

### The one instruction on the screen is the dimmest text on it — row 1's lock line measures 4.02:1, under AA
- **lens:** Designer · **screen:** Roster Cuts
- **evidence:** Row 1 is Kaleo Hinsdale, ranked #1, gold-outlined, carrying the only imperative sentence anywhere in the list: "You must carry 2 QBs — sign or trade for another first". Sampled from the PNG, that line renders at RGB(147,117,22) on a row fill of RGB(16,25,42) = 4.02:1, below the 4.5:1 AA floor. Its OVR "54" measures RGB(150,51,58) on the same fill = 2.37:1. The identical name style on row 2 (Harlan Brockway) measures 15.24:1 and its OVR "56" measures 4.44:1 — so the blocked row is running at roughly 40% less ink than every row around it, including on the sentence that tells the player what to do.
- **code:** `dynasty/dynasty/UI/Camp/RosterCutView.swift:559`
- **fix:** Drop the blanket `.opacity(0.6)` on the blocked row. Dim only the columns that are no longer actionable (or nothing at all) and let the existing warning-tinted border at line 553 carry "closed" on its own — the lock glyph plus the orange stroke already say it twice. If a dim is wanted, apply it to the row background rather than to the row's content so the lock sentence and the OVR keep their measured contrast.

### A 256–278 pt void sits between the player name and the first number on every row
- **lens:** Designer · **screen:** Roster Cuts
- **evidence:** Measured ink gaps across three rows at 1032 pt viewport width: row 2 (Harlan Brockway) is blank from x=244 pt to x=500 pt (256 pt); row 6 (Jaden Latimer, "No stat line") from 226 to 499 pt (273 pt); row 11 (Bodie Balfour) from 220 to 499 pt (278 pt). That is 25–27% of the full row width, empty, repeated down all 53 rows, while the tape/money columns to its right are packed at 26–30 pt each. The header row inherits the same hole — "PLAYER · PRESEASON TAPE" ends at 244 pt and "OVR" does not start until 496 pt.
- **code:** `dynasty/dynasty/UI/Common/DSListRow.swift:636`
- **fix:** The identity slot is `maxWidth: .infinity`, so it swallows 100% of the slack on an iPad-width row (the same at DSListRow.swift:728 for the header). RosterCutView uses no `DSLayout` measure at all, unlike 70 other call sites in UI/. Cap the band/header/list stack at `DSLayout.wideMeasure` (900 — its doc names "multi-column tables") and give the identity slot a `maxWidth` around 220 so the remaining slack is distributed as inter-group gutters instead of one dead column.

### REPS column: one header word over two unlike numbers, neither of them labelled
- **lens:** Designer · **screen:** Roster Cuts
- **evidence:** Under the single header "REPS", every cell stacks two figures with no caption between them: "95 / 3/3" (Kaleo Hinsdale), "3 / 3/3" (Harlan Brockway), "7 / 1/3" (Wade Braithwaite), "0 / 3/3" (Wade Vandenberg), "87 / 3/3" (Brixton Yarborough). Nothing on the screen says the top figure is chances the box score saw and the bottom is exhibitions dressed. The column is 34 pt wide — the DS's `attribute` step, whose own definition is "a number over a 3-letter caption: LRN / SPD / a skill" — so the component is being used for value-over-value where it was specified for value-over-caption.
- **code:** `dynasty/dynasty/UI/Camp/RosterCutView.swift:756`
- **fix:** Either give the second line a caption the way `attribute` intends ("95" over "GM 3/3"), or split into two labelled columns (REPS | GM). The screen already has 256+ pt of unused row width to spend on the extra column — see the identity-slot finding.

### The dashed "unfilled slot" pill is the majority style in the CASE column, where it means a real verdict
- **lens:** Designer · **screen:** Roster Cuts
- **evidence:** 12 of the 16 visible CASE cells read QUIET in the dashed, unfilled pill style (rows 2,3,4,6,7,9,10,11,12,13,14,16); only 4 are solid (SLIPPED ×2, HELPED, HELD). The DEPTH column immediately to its right uses the identical dashed style for OFF on 4 rows — where it genuinely means "not on the depth chart". So one visual treatment carries two different meanings in adjacent columns, and the treatment the design system reserves for a hole is the commonest thing in the table.
- **code:** `dynasty/dynasty/UI/Camp/PreseasonRecapSheet.swift:94`
- **fix:** `Verdict.quiet` returns `DSStatusPill.Tone.empty`, whose contract is "the slot exists and nothing has filled it. Dashed, dimmed, no dot" and whose default spoken form is "…not done". QUIET is a stated verdict about a man who dressed and did not factor — map it to `.neutral` (solid, textSecondary) and leave `.empty` to the DEPTH column's OFF, where the file header at RosterCutView.swift:801-804 deliberately uses it for a real absence.

### The nine filter chips measure 30.5 pt tall against the app's own stated 44 pt floor
- **lens:** Designer · **screen:** Roster Cuts
- **evidence:** Scanning the "All 53" chip's blue selected border in the PNG: top edge at y = 262.0 pt, bottom edge at y = 292.5 pt — 30.5 pt of hit rect. The row of nine chips (All 53, QB 2, RB/FB 5, WR/TE 10, OL 12, DL 8, LB 4, DB 7, ST 5) is the primary navigation control on the screen. Every other control on the same screen honours the floor: the info button is framed at 44 (RosterCutView.swift:941), and the Stash toggle explicitly wraps a 19 pt pill in 44 pt of finger (RosterCutView.swift:899-902).
- **code:** `dynasty/dynasty/UI/Camp/RosterCutView.swift:358`
- **fix:** The chip label is `.padding(.vertical, DSSpacing.xs)` (8) around a 12 pt footnote and nothing claims a larger rect. Add `.frame(minHeight: 44).contentShape(Rectangle())` inside the Button label — the same pattern the Stash button on this file already uses — so the target grows without the chip's visual box changing.

### Thirteen column labels, eleven of them abbreviations, and no way to find out what any of them mean — while the plain-English sentence for each already exists as VoiceOver-only text
- **lens:** Casual player · **screen:** Roster Cuts
- **evidence:** The frozen header reads "CUT POS PLAYER · PRESEASON TAPE OVR OVR± CAMP REPS CASE DEPTH AGE YRS FREES DEAD PS". Across the 16 visible rows the badge vocabulary is eleven more words with no gloss: SLIPPED, QUIET, HELPED, HELD (CASE); BACKUP, OFF, WR1, LG, RB, LOLB (DEPTH); ELIGIBLE (PS, on 7 of 16 rows). The single largest number on the screen is Wade Braithwaite's "$74.5M" under a column headed "DEAD" — no unit, no currency context, no definition — sitting beside "−$20.5M" under "FREES". The REPS cell stacks a bare "95" over "3/3" for Kaleo Hinsdale and "7" over "1/3" for Braithwaite; nothing says 95 is chances and 3/3 is exhibitions dressed. There is no ?, no legend strip, no long-press hint anywhere on the screen.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:868`
- **fix:** The English is already written and only VoiceOver hears it: RosterCutView.swift:868 builds "Leaves $74.5M of dead money", :851-856 builds "Releasing him costs $20.5M of cap space", :772-774 builds "95 chances across 1 of 3 exhibitions", :789 builds "The tape says he …". DSColumnHeader (/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Common/DSListRow.swift:203) takes only a title and has no help hook. Add an optional `help:` string to DSColumnHeader, make the header label tappable to a small popover, and seed it with those same sentences for DEAD, FREES, CASE, REPS and PS. No layout change, no new copy to write.

### "YOUR STAFF'S CUT ORDER" ranks #1 a man the game refuses to let you cut
- **lens:** Casual player · **screen:** Roster Cuts
- **evidence:** The list header reads "WORST FIRST · YOUR STAFF'S CUT ORDER". Row 1 is CUT 1, QB Kaleo Hinsdale, dimmed, with a padlock and the gold subline "You must carry 2 QBs — sign or trade for another first". The first instruction a casual reading the staff's plan top-down receives is one the screen then blocks.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:1521`
- **fix:** cutOrder at :1521 ranks the whole fetched roster by keepScore ascending with no filter — yet suggestCuts at :1398-1406 already skips any player whose releaseBlockReason is non-nil, so the machine's plan is correct and only the visible ranking is wrong. Apply the same guard to the display order: partition blocked players to the tail of the sort (or rank them but draw an em dash in the CUT slot instead of a number), so position 1 is always a man the player can actually act on.

### "OFF" in the DEPTH column means "not on the depth chart" but reads as "offense" on a football screen
- **lens:** Casual player · **screen:** Roster Cuts
- **evidence:** Four of the 16 visible rows carry a dashed pill reading OFF in the DEPTH column — row 2 Harlan Brockway (POS badge DE, red/defense), row 3 Callum Derringer (TE), row 9 Wilkes Marsden (P), row 14 Hayden Truesdale (RT). Every other value in that same column is a real football abbreviation: BACKUP, WR1, LG, RB, LOLB. So the casual has been trained by the column itself to read three-letter caps as football shorthand, and OFF is the one that isn't — and it lands on a defensive end, where "offense" is flatly false.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:812`
- **fix:** Change the pill label at :812 from "Off" to "Not listed" (the label column is DSListColumn.label, wide enough for BACKUP already) or to an em dash. The spokenLabel one line down at :815 is already correct — "Not on the depth chart" — so only the visible string needs to catch up to it.

### In the CUTDOWN COMPLETE state nothing says what a row tap does, but tapping a player's name arms an irreversible release
- **lens:** Casual player · **screen:** Roster Cuts
- **evidence:** The bottom bar reads "CUTDOWN COMPLETE / Your roster is at 53. Nothing more is owed here." with a gold "Done — roster is set". No text anywhere on the screen mentions tapping a row. Yet every one of the 53 rows is a full-width tap target; tapping Wade Braithwaite's name turns his row red and swaps that gold button to "Release 1 player". The only labelled per-row control is the ⓘ at x≈1965 of a 2064 px screen — the extreme right edge, past fourteen columns.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:561`
- **fix:** The explainer at :1074-1078 deliberately drops the "Tap a player to mark him for release" sentence once the roster is legal (the branch at :1083 still carries it while a rung is owed), so at 53 the screen's most consequential gesture is the only unlabelled one — the code itself calls it "an irreversible release" at :931. Either add one quiet non-soliciting line to the complete-state message ("Tap a player to release him — nothing is owed.") or move the arming gesture off the name: let a tap on the name/portrait open the player card the ⓘ currently owns, and confine arming to a dedicated select column.

### A 14-column table that cannot be sorted or searched
- **lens:** Hardcore player (tosipelaaja) · **screen:** Roster Cuts
- **evidence:** The table header reads "CUT | POS | PLAYER · PRESEASON TAPE | OVR | OVR± | CAMP | REPS | CASE | DEPTH | AGE | YRS | FREES | DEAD | PS" and the strip above it declares the one order that exists: "WORST FIRST · YOUR STAFF'S CUT ORDER". The only other control is the position chip row. There is no sort control, no ascending/descending arrow on any header, and no search field.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:1282`
- **fix:** `filteredRoster` is hardwired to `cutOrder`, and `DSColumnHeader` (DSListRow.swift:203-221) is a bare `Text` with no gesture, so twelve comparable columns are laid out as a table and behave as a fixed list. "Who are my biggest cap savings", "who is 30+", "who lost OVR since December" all require scanning by eye — 87 rows at the first rung. Add a `@State sortKey` defaulting to the staff order, make the numeric headers tappable (OVR, OVR±, AGE, YRS, FREES, DEAD) with a caret on the active one, and put a name-search field beside the chip row. The CUT rank column already survives filtering, so it keeps the staff's answer visible under any sort.

### The PS column offers a stash with no ceiling, no count and no per-position cap
- **lens:** Hardcore player (tosipelaaja) · **screen:** Roster Cuts
- **evidence:** A column headed "PS" with grey "ELIGIBLE" pills on seven of the sixteen visible rows (Derringer, Vandenberg, Latimer, Ackerly, Marsden, Ferrante, Truesdale). Nowhere on the screen is a practice-squad size, a spots-used count, or a per-position limit.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:1411`
- **fix:** `togglePracticeSquad` inserts into an unbounded `practiceSquadIDs` set, and the flags are written onto RosterCut rows that accumulate across all three rungs. The pass that honours them takes at most `squadSize` = 16, `maxPerPosition` = 3 (`maxQuarterbacks` = 2) and `veteranSlots` = 6, then silently skips the rest (PracticeSquadEngine.swift:56, :159, :162, :634-643). Flag a 17th man, or a 4th receiver, and nothing on this screen ever tells you he was dropped. Show "PS 4/16" in the header strip (counting RosterCut.practiceSquadEligible rows already banked at earlier rungs), disable the Stash button when the squad or the position cap is spent, and say which limit stopped it.

### The finished ladder throws away the only numbers the cutdown was about
- **lens:** Game developer · **screen:** Roster Cuts
- **evidence:** The three completed slats read 'CUT TO 75 / 12 released', 'CUT TO 65 / 10 released', 'CUT TO 53 / 12 released' — and nothing else. Thirty-four men left this roster across three phases and the screen cannot say what that freed or what dead money it left on the books.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:1546`
- **fix:** loadLedger fetches the RosterCut rows and reduces them to `byStage[day, default: 0] += 1`. Those same rows already carry capSavings and deadCap per release (RosterCut.swift:31-33) — the data is in hand and discarded. Sum both in the same loop and feed them into the slat's outcome string at RosterCutView.swift:288: '12 released · +$14.2M · $3.1M dead'. The result sheet already prints exactly these as chips for a single commit, so the ladder would simply be saying at the end what each rung said at the time. This is also the only place on the screen the club's cap position is ever implied; OOTP's transaction ledger is the reference bar.

### The practice-squad flag is write-only, uncounted, and silently capped at 16
- **lens:** Game developer · **screen:** Roster Cuts
- **evidence:** In the CUTDOWN COMPLETE state the PS column shows 'ELIGIBLE' on eight of the sixteen visible rows — Derringer, Vandenberg, Latimer, Ackerly, Marsden, Ferrante, Truesdale and one more — every one of them a man who is STAYING on the 53. Nothing on the screen refers to the 34 men who left, and there is no count anywhere of how many were flagged for the squad.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:885`
- **fix:** practiceSquadCell renders the Stash button only `if isSelected`, and practiceSquadIDs is wiped after every commit (RosterCutView.swift:1881), so the flag exists only inside one uncommitted selection. It is read months later by PracticeSquadEngine.userFlaggedKeepers, which sorts the flagged cuts newest-first and takes prefix(squadSize) with squadSize = 16 (PracticeSquadEngine.swift:766 and :56). The user works this ladder across three separate phases with no running tally, so flagging 20 men across the three rungs silently discards the four he flagged FIRST — the camp-cut rung — and he finds out only when the squad fills at the regular-season boundary. Read RosterCut.practiceSquadEligible back in loadLedger, print 'N of 16 flagged for the practice squad' beside the slats, and refuse the 17th tick with the same in-row lock line the position floors already use.

### The preseason tape column cannot see a third of the roster and prints a verdict anyway
- **lens:** Game developer · **screen:** Roster Cuts
- **evidence:** Rows 4, 6, 7 and 14 (LT Vandenberg, LG Latimer, LG Ackerly, RT Truesdale) and row 9 (P Marsden) all read REPS '0' over '3/3' with CASE 'QUIET' — in uniform for every exhibition, zero chances, verdict rendered. That is five of the sixteen visible rows; with the chips reading OL 12 and ST 5 it is 17 of the 53. The identity column is headed 'PLAYER · PRESEASON TAPE'.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/Domain/Models/League/PlayerGameStats.swift:9`
- **fix:** PlayerGameStats has no snap, block, pressure or punt column, so PreseasonEngine.CampCase.read counts opportunities only from attempts, carries, targets, defensive events and FG attempts and returns .quiet whenever the total is zero (PreseasonEngine.swift:1069). Every offensive lineman and every punter therefore returns QUIET by construction, and VoiceOver speaks it as 'The tape says he did not factor' (PreseasonRecapSheet.swift:82) — a false sentence about a left tackle who played three games. Give caseCell (RosterCutView.swift:781) a third state: a man who dressed at a position with no box-score footprint reads 'Not measured', not 'Quiet' — the same distinction repsCell already draws between '0 of 3' and '—'. The durable fix is one measurable event per blind position (pressures allowed for OL, punts and gross average for P), which is what would make the tape usable on the twelve-man OL room this club just chose to keep.


## low

### Two different whites two pixels apart inside the same cell
- **lens:** Designer · **screen:** Training Camp — Workload heat-map
- **evidence:** camp_03: the "–" / "✓" glyph samples at #FFFFFF while the position label directly above it samples at #F1F5F9 (`Color.textPrimary`). Two whites stacked with 2 pt between them.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:84`
- **fix:** `Text(player.workloadStatus.emoji).font(.title3)` carries no `foregroundStyle`, so it falls through to SwiftUI's default `.primary` instead of the token. Add `.foregroundStyle(tint)` — the glyph should be carrying the status colour anyway.

### Five hard-coded columns leave 73–79% of every cell empty and 288 pt of dead canvas below the grid
- **lens:** Designer · **screen:** Training Camp — Workload heat-map
- **evidence:** camp_03: cells measure 192.5 × 68 pt. The widest ink inside any of them is 51.5 pt ("Vestergaard"); the narrowest is 39.5 pt ("Goddard") — 73–79% of each cell's width is background. The 11-row grid ends 288 pt above the bottom of the page, 21% of the page height left empty.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:15`
- **fix:** `Array(repeating: GridItem(.flexible(), spacing: DSSpacing.xs), count: 5)` fixes 5 columns regardless of size class. `GridItem(.adaptive(minimum: 116))` gives 8 columns on the 1032 pt iPad — all 53 men in 7 rows, no scroll, and each cell still comfortably wider than its content. The reclaimed density is what makes the whole roster comparable at a glance, which is the point of a heat-map.

### "DUR" and "STA" are never expanded anywhere on the screen
- **lens:** Casual player · **screen:** Training Camp — Training Plan
- **evidence:** The table header row reads "POS  PLAYER  DUR  STA  AGE  LOAD  STATE  INJ", with DUR values 63/77/79/61/61/62/72/81 and STA values 56/58/53/62/65/61/67/65. Nothing on the screen says what DUR or STA stand for; the nearest text, the Physical slider blurb "S&C + conditioning → stamina, durability", sits in a different card 500 px above and never ties itself to the abbreviations. The code comment at TrainingPlanView.swift:371 states the columns exist because "the row asked the GM to trust a risk he had no way to check" — which only works if the reader can decode the headers.
- **code:** `dynasty/dynasty/UI/Camp/TrainingPlanView.swift:322`
- **fix:** Extend the existing caption at :306 by one clause — "DUR is durability and STA stamina; the two ratings the INJ figure is built from" — rather than widening the headers. One sentence, no layout change.

### "Injury multiplier x1.0" is an engine internal shown to the player, in green
- **lens:** Casual player · **screen:** Training Camp — Workload heat-map (Workload Detail sheet)
- **evidence:** The sheet's third row reads "Injury multiplier    x1.0", rendered in the success green. A multiplier of what, against what baseline, is stated nowhere; the value is `String(format: "x%.1f", player.workloadStatus.injuryMultiplier)` and the green comes from `injuryMultiplier > 1.0 ? Color.warning : Color.success`. A first-session player has no way to know that 1.0 is the neutral value and that the reachable alternatives are 1.6 and 2.5 (CampEnums.swift:22-28). Two of the sheet's four rows are now raw engine terms.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:150`
- **fix:** Say it in the player's language, switched off the status: "Injury risk — normal" for 1.0, "+60% while he is Heavy" for 1.6, "+150% while he is Burnt" for 2.5. Same row, same tint rule, no new data.

### The workload table cannot be re-sorted, though the app already ships tap-to-sort headers
- **lens:** Hardcore player (tosipelaaja) · **screen:** Training Camp — Training Plan
- **evidence:** The section label reads "TOP 30 OF 53 BY LOAD" and the header row DUR / STA / AGE / LOAD / STATE / INJ is inert — there is no caret, no sort affordance, and load-descending is the only available order.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/TrainingPlanView.swift:453`
- **fix:** displayRoster (line 453) hard-codes cumulativeLoad descending, tie-broken by durability ascending. RosterEvaluationView.sortableHeader (RosterEvaluationView.swift:416) is the existing pattern — a Button header that toggles sortColumn / sortAscending and draws a chevron. Reuse it for DUR, STA, AGE and INJ so the 100th visit can answer "oldest men with the worst durability" without reading 53 rows; keep load-descending as the default.

### Camp grade is the only row in the detail sheet with no conditional tint — an F and an A+ both print in accent gold
- **lens:** Game developer · **screen:** Training Camp — Workload heat-map
- **evidence:** In Workload Detail: "Status ✓ Healthy" is green, "Cumulative load 42" is green, "Injury multiplier x1.0" is green — and "Camp grade D" is gold, the screen's emphasis colour.
- **code:** `dynasty/dynasty/UI/Camp/WorkloadDashboard.swift:157`
- **fix:** statusRow is called with `tint: Color.accentGold` unconditionally for the grade, while the three rows above it all branch on value (:141, :146, :151). Given that this column is currently degenerate, gold is the loudest treatment on the sheet applied to the least informative row. Fix: tint the grade off its own value the way the other rows do (Color.forRating, or the A/B/C/D/F palette the roster screens already use), so the sheet reads correctly once the curve is fixed and so a D stops borrowing the colour reserved for emphasis.

### accentBlue carries four unrelated meanings in a single viewport
- **lens:** Designer · **screen:** Roster Cuts
- **evidence:** In the one screenshot, the same blue reads as: (1) the selected filter — the 2 pt border on "All 53"; (2) offense — the QB/TE/LT/WR/LG/RB/RT position badges on 9 of 16 rows; (3) the 70–79 OVR band — "74" on Bodie Balfour and "71" on Bodie Auchter; and (4) practice-squad flagged, the fill the On-PS toggle takes once a row is marked. Four semantics, one hue, no separation of tint or shape.
- **code:** `dynasty/dynasty/UI/Camp/RosterCutView.swift:366`
- **fix:** The filter chip is the cheapest one to move: it already changes its fill from `backgroundSecondary` to `backgroundTertiary` when selected, so the 2 pt `accentBlue` stroke is redundant as a selection cue. Drop the blue and let the fill plus a `textPrimary` label carry selection, leaving blue to mean offense and the 70s band.

### "CUTDOWN COMPLETE" is printed twice in one viewport, 800 pt apart
- **lens:** Designer · **screen:** Roster Cuts
- **evidence:** The words appear at the top of the ladder card (grey, RGB(148,163,184), 7.67:1) and again at the bottom of the action bar in gold (RGB(199,167,78), 7.28:1) above "Your roster is at 53. Nothing more is owed here." The three ladder slats already show ✓ CUT TO 75 / ✓ CUT TO 65 / ✓ CUT TO 53, so the completed state is asserted four ways without either headline adding a fact the other lacks.
- **code:** `dynasty/dynasty/UI/Camp/RosterCutView.swift:304`
- **fix:** The file already applies this rule to the in-progress state (see the `currentSubcaption` note at lines 313-318: the remainder is said in exactly two places and no more). Extend it to the complete state: let the bar keep "Cutdown complete" (it owns what to DO) and have the band `headline` at line 304 return the fact the bar cannot carry — e.g. "34 released · 53 on the roster".

### OVR uses the fill-only red as text (4.44:1) while the money column beside it uses the text red (6.03:1)
- **lens:** Designer · **screen:** Roster Cuts
- **evidence:** Row 2's OVR "56" samples as RGB(239,68,68) = #EF4444 on the row fill = 4.44:1, marginally under the 4.5:1 AA floor. On the same row, DEAD "$0.1M" samples as RGB(248,113,113) = #F87171 = 6.03:1. Two red text roles on one line, measurably 36% apart in contrast.
- **code:** `dynasty/dynasty/UI/Common/Theme.swift:129`
- **fix:** `forRatingTier(.poor)` returns `.danger`. DSTokens.swift:42-46 states the rule explicitly — "#EF4444 (~3.4:1) is too dim to read as words on the dark surfaces… Use [#F87171] for red text only; keep danger #EF4444 for fills, bars, and icon glyphs". Return `.dangerText` from the `.poor` tier (app-wide, one line) so every red numeral matches the red the money columns already use.

### OVR± prints a delta with no baseline in pixels
- **lens:** Hardcore player (tosipelaaja) · **screen:** Roster Cuts
- **evidence:** The column header reads "OVR±" and the cells read "+1", "+3", "0", "−1", "+2" with no statement anywhere of what the comparison is against. Wade Braithwaite reads "0" and Wade Vandenberg reads "+3" — over what window is not on the screen.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:726`
- **fix:** `OVRTrend` already carries `sinceSeason`, and `trendSpoken` says it out loud ("Up 3 since the end of 2025") — but only to VoiceOver. Every sighted reader gets an unanchored number. Put the season in the header: "OVR± vs '25". One string, and the column stops being a number you have to trust blind.

### The locked row names a remedy the screen has no route to
- **lens:** Game developer · **screen:** Roster Cuts
- **evidence:** Row 1's subline reads '🔒 You must carry 2 QBs — sign or trade for another first', and the QB chip reads 'QB 2'. The club is finishing the cutdown exactly at the QB floor, with a 54-OVR backup who is the staff's own number-one cut candidate and whose CASE pill reads SLIPPED — and the only thing the screen offers is a lock glyph.
- **code:** `/Users/jtvaris/workspace/projects/Dynasty/dynasty/dynasty/UI/Camp/RosterCutView.swift:645`
- **fix:** The blocked subline is plain Text inside an HStack. Make it the tap target it is already asking to be: the row already carries a NavigationLink in playerCardCell (RosterCutView.swift:934), so the same pattern pushes the free-agency or trade screen from the lock line. Alternatively state the standing risk once in the band rather than per row — 'QB room at the 2-man floor' — so a cutdown that ends one injury from having no quarterback is not something the user has to infer from a chip.
