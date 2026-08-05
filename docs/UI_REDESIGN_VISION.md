# UI Redesign Vision — Sunday Night Dynasty

**Status:** direction document. No code changes proposed inline; every verdict names a wave.
**Companion artifact:** `ui_vision_mockups.html` (four screens in the new language, iPad landscape).
**Identity guardrail:** midnight-navy + stadium-gold stays. This is a *grammar* change, not a re-skin.
**Language:** English only, everywhere, including new strings.

**This document is the plan for `TODO.md:15`**, the open item that scopes the work:

> **B · Iso visuaalinen + käytettävyys-UI-aalto ("Tehdään polished!").** Koko sovelluksen visuaalinen
> ja käytettävyysparannus, erityispainona **viikkonäkymän parannus**. Generoituja kuvia (Replicate
> FLUX, sama putki kuin kasvokirjasto) saa käyttää vapaasti: taustakuvitus, stadionit, tunnelmakuvat,
> tyhjien tilojen kuvitus. Tavoite: viimeistelty, julkaisukelpoinen ulkoasu.

Two things follow from that scope and are honoured throughout: the **week view carries particular
weight** (wave 2 is the hub, and it is the largest single rebuild here), and **generated imagery is
in-budget** — backgrounds, stadiums, mood shots and empty-state illustration are allowed art, not
just code. The mockups use flat gradients as placeholders where real art belongs.

---

## 0. Why redesign rather than patch

The app has a good design *palette* and almost no design *grammar*. The color layer landed
everywhere; the structural layers never did.

Task **#70** (`1e91a74 chore(design): DSType size ladder, radius codemod, design-debt lint baseline`)
built the ladders and the instrument to measure them against. It did its job. What it revealed is
that the ladders have almost no consumers — this document is the plan for consuming them.

Measured, not asserted (`tools/lint/design_tokens.py`, baseline `design_tokens_baseline.json`):

| Metric | Off-ladder | Of total | Share |
|---|---:|---:|---:|
| `.system(size:)` font literals | 675 | 1984 | **34 %** |
| `cornerRadius:` literals | 519 | 772 | **67 %** |
| spacing / padding literals | 2681 | 5261 | **51 %** |
| bespoke rating → `Color` functions | 21 | 21 | **100 %** |
| font literals **below the 10 pt legibility floor** | 486 | — | — |

Token adoption by directory (`DSType` / `DSElevation` / `DSSpacing` / `DSCornerRadius` uses):

```
Match       36 / 3 /   0 /  2      ← the broadcast HUD: the one surface built on the tokens
Scouting    45 / 0 /   0 / 21
Roster      33 / 0 /  49 / 57
Staff       31 / 0 /   0 / 19
FreeAgency  27 / 0 /  78 / 53
Career      17 / 0 /  36 /  8
Draft        4 / 0 / 178 / 64
Camp         0 / 0 /  66 / 26
Standings    0 / 0 /   0 /  0      ← zero tokens of any structural kind
Schedule     1 / 0 /   0 /  0
MainMenu     0 / 0 /   0 /  0
```

Globally that is **209 `DSType` uses against 2211 raw `.system(size:` — about 9 % adoption**, and
44 `DSLayout` uses across 150 files. `DSElevation` is a dead token outside the HUD. `DSSpacing` is
dead in eight of fifteen directories.

That is not a lint problem — it is the symptom. Each screen was designed as a standalone artifact, so
the app has:

- **7 progress metaphors** and no shared step component (four `GeometryReader` bars in two different
  accent colors, a capsule, two dot-rails, and a family of bare `"N/M"` counters with ~12 different
  denominators).
- **6 primary-action placements** (pinned bottom bar · last item in a ScrollView · last `List`
  section · inside a header that scrolls away · `.toolbar` · mid-panel in a side rail) — plus two
  screens with no primary action at all.
- **5 flow-termination patterns**, **4 feedback metaphors** (top toast, bottom toast, top overlay
  banner, full-screen overlay), and **5 independent tab-bar implementations**.
- **4 incompatible chip styles** for the same semantic object, and **3 section-header conventions**
  across three sibling detail screens.
- **Row heights spanning 4 pt to a five-line stacked block** for what is conceptually one thing:
  "a person with stats".
- **7 dismissal affordances**: toolbar "Done" · toolbar "Close" · toolbar "Back" (on a modal) ·
  inline full-width gold "Done" · 30 pt circular X · 44 pt circular X · `.cancellationAction` and
  `.confirmationAction` used interchangeably for the same job.
- **3 hand-rolled primary-CTA recipes** at two different corner radii (12 and 10), copied between
  `NewCareerView`, `TradeView` and `ContractNegotiationView`. The one `ButtonStyle` that exists
  (`MenuButtonStyle`) is used in exactly one file.
- **Arbitrary confirmation.** Contract extensions and draft picks confirm before committing; owner
  whims, franchise tags, in-game substitutions and press-conference answers — all irreversible and
  career-affecting — commit on first tap.

### Navigation is modal-stacking, not routing

**85 modal presentations (64 `.sheet` + 21 `.fullScreenCover`) against 5 `.navigationDestination`**,
plus 110 `NavigationStack`, 152 `.toolbar`, 613 `.overlay(` and 125 `@State` is-presented flags.
Two competing navigation models coexist: `CareerShellView`'s single ~40-case `ShellDestination` enum
driving one `.navigationDestination`, and everything else pushing modals onto modals.

Sheet vs cover is chosen ad hoc — peer actions split across both *inside single files*
(`CoachedGameView` presents stats as a sheet and the substitution board as a cover; `MainMenuView`
puts Settings in a sheet and career-open in a cover). That has already cost a correctness hack:

```swift
// MainMenuView.swift:106
showSlotPicker = false
// Defer presentation of the full-screen cover until the sheet
// has dismissed to avoid a presentation conflict.
DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { continueCareer = career }
```

A 350 ms magic delay to sequence a dismiss into a present, in the first screen of the app.

### The same screen, built twice

Four features exist as two independent implementations that share no components and have already
drifted apart:

| Duplicated feature | Files | Lines | Drift already visible |
|---|---|---:|---|
| **Play-calling** | `MatchView` + `PlayCallView` vs `CoachedGameView` | **1458 (dead)** | Modal sheet with drag indicator vs inline switching panel. The sheet version is **unreachable** — referenced only by its own `#Preview`. |
| **Press conference** | `PressConferenceView` / `WeeklyPressConferenceView` | ~2080 | Scrim `.opacity(0.32)` vs `0.25`; 4-stop vs 3-stop gradient; top safe-area scrim present vs absent |
| **Negotiation chat** | `ContractNegotiationView` / `TradeNegotiationView` | ~3490 | Separate bubble, transcript, header and turn logic |
| **Owner meeting** | `News/OwnerMeetingView` vs `IntroSequenceView.OwnerMeetingStep` | — | Two different owner screens |

Any visual fix to these must be made twice, and demonstrably has not been.

### Patching has already been tried, and measured

The `analyze-app` audit (`TODO.md:3897`, 2026-07-31: 13 screens, 4 personas, waves A–E + 2A–2G
shipped through `65ab875`) worked on its own terms. And `TODO.md` still carries **471 open
`Fix:` / `Game:` / `UX:` findings**, of which **244 sit in the single `auto-analyze` per-screen block
at L2560–3600**. They read like symptoms of one disease:

> *"inconsistent label placement across the four stat tiles"* · *"tags only on coordinators,
> inconsistent"* · *"trade arrow icons — sometimes after age, sometimes after OVR, standardize
> column"* · *"chips side-by-side — inconsistent corner radii / heights; normalize"* ·
> *"emoji-style icons feel inconsistent; use a unified badge system"* · *"Numeric values use
> multiple scales without a clear ramp… establish a typography scale and apply consistently"*

And a whole cluster that is precisely P5 and P7, already written down by past reviewers:

> *"full-width gold — but it's the same gold as every other CTA in the app"* · *"button is
> dimmed/disabled but still the same gold — use truly disabled gray"* · *"'View All' gold pill —
> same gold as every other CTA; tone down for nav links"* · *"full-width gold CTA — same gold as
> everything; this should be the primary action"* · *"All section header icons are the same yellow
> tint and same size — they compete for attention instead of guiding it"*

Every one of those is a request for a component that does not exist. Fixing them one at a time is
1:1 work forever; defining the component fixes them in batches and stops new ones appearing.

> **Note on numbering.** The brief for this document referenced "#60–#65, #70". Those live in the
> legacy `docs/TODO.md` (last updated 2026-03-18), are **all closed**, and #65 was never used — that
> file is a finished 2026-03 list, not live debt. The live numbering is the root `TODO.md`/
> `BACKLOG.md` scheme, where **#70** is the token-ladder commit cited above and **#103** is the
> in-flight draft-path overhaul. Live UI debt is `TODO.md:15` (the mandate) plus the 471 open
> findings — not the #60s.

Patching any one screen cannot fix this, because the defect is that no screen agrees with any other
about what a row, a step, a chip, or a commit *is*. The fix is to name those things once.

Two surfaces already got it right and become the references:

- **Big Board** (`UI/Scouting/BigBoardView.swift`) — the list reference. Fixed-width shared column
  constants between header and row, a swappable "lens" of trailing columns, and fixed state-chip
  slots that are *dimmed when empty* so the gaps in the user's work are visible. Its own comment says
  it best: the holes in the board were invisible, "and the holes are the whole question".
- **The broadcast HUD** (`UI/Match/*`, `UI/Theme/DSTokens.swift`) — the token reference. It is the
  only surface where a type ladder, an elevation scale, and semantic color aliases were designed
  together and then actually used.

The redesign generalises those two, and stops inventing.

---

## 1. Core principles

### P1 — Every flow is a visible process
If a screen advances state across more than one step, it mounts the **process bar**: where you are,
how many steps exist, what each one costs, and what a locked step needs before it opens. No flow may
communicate progress with prose, a bare counter, or a title string. The step machines already exist
in the domain layer — `DraftPrepStep` (9), `FreeAgencyStep` (5), `SeasonPhase.groupProgress`,
`DraftDayCoordinator.Mode`, `RosterCutView`'s three cut stages. Today five of them render nothing.

**Consequence:** a stage may never advance invisibly. Two draft-prep stages currently complete
merely by opening a tab; that becomes illegal.

### P2 — One list standard, derived from Big Board
Every list of entities-with-stats — roster, FA market, standings, schedule, league rosters, prospect
pickers, game logs — uses one row component with one anatomy:

```
[rank] [position badge] [portrait] [identity + fixed state-chip slots] [lens columns] [OVR] [trailing] [affordance]
```

Header and row share width constants. The identity block never moves; only the lens columns swap.
Screens choose **columns and lens set**, never row structure, chip shape, or density arithmetic.

**Consequence:** `FreeAgencyView`'s five-line stacked block, `ScheduleView`'s bordered cards, and
`LeagueRostersView`'s self-drawn rows-as-cards all become the same row with different lenses.

### P3 — Three density tiers, chosen explicitly
Density is a named decision on every surface, not an accident of who wrote it:

| Tier | Row height | Info elements | Where |
|---|---|---|---|
| **Glance** | ~32 pt | ≤ 4 | rails, hub cards, mini-standings, "3 numbers and a link" |
| **Scan** | ~44 pt | 8–14 | the default list: roster, board, FA market, standings |
| **Study** | card stacks | unbounded | detail screens, game log, comparison |

The tier is a visible control on list screens, so the user can trade breadth for depth without
leaving. Today the same conceptual density lands anywhere between `padding(.vertical, 4)` and 16.

### P4 — Every card states what it costs and what it unlocks
A card that offers an action must say the price and the outcome in the card, in that order, before
the user commits. "Book 3 interviews · spends 1 of 4 scouting weeks · advances to Pro Days · cannot
be rebooked." This is the **explainer** pattern, and it is how the app teaches its own systems
instead of leaving the player to infer them from drifting numbers.

**Consequence:** hub task rows, flow action bars, and detail-screen actions all carry a cost→unlock
line. Placeholder text is a bug: the camp and preseason hero cards currently ship hardcoded fake
stats ("18 % overloaded", "3 battles, · A+").

### P5 — One primary action, one place, one gold
Gold fill is the primary action and appears **exactly once per screen**. The commit lives in a
**persistent bottom action bar**, right-aligned, in fixed order: `[destructive · rule] [ghost]
[secondary] [PRIMARY →]`. Toolbars stop carrying commits entirely. Nothing important may live in a
header that scrolls away — which is where the entire draft-prep pipeline's advance button lives today.

**Consequence:** the dashboard's five competing action slots collapse to one hero commit plus a task
list whose rows carry their own scoped secondary actions.

Two corollaries, because commit discipline is meaningless without them:

- **One dismissal verb.** A pushed screen goes back; a modal closes with a 44 pt circular X in the
  top-trailing corner. Never "Back" on a modal, never a primary-styled inline "Done" that duplicates
  a toolbar "Close" (`ContractNegotiationView` currently ships both).
- **Irreversibility always confirms.** If an action spends a resource, changes a contract, or cannot
  be undone, it confirms — and the confirmation states the cost. Owner whims, franchise tags,
  substitutions and press answers currently commit on first tap; contract extensions do not. The rule
  decides it, not the author.

### P6 — Navigation is hub-and-process, not a tab forest
A **hub** answers "what is happening and what should I do"; a **process** is entered, completed, and
exited with a result. The persistent bookmark strip is for reference destinations you return to, and
is capped at **seven**. Everything else is reached from the hub, from a task, or from a process step.
Deep links resolve to a real destination or are not offered — today six draft-prep task destinations
collapse to "open the Scouting hub" plus a string hint the hub may silently drop.

**Consequence:** `ShellDestination`'s 36 cases get audited; aliases (`.cap`/`.capOverview`,
`.prospectList`/`.bigBoard`/`.scouting`) merge, unreachable cases (`.hireHC/.hireOC/.hireDC`) are
deleted, and every remaining case is reachable and lands somewhere that makes sense.

### P7 — Color is a ladder, never decoration
One rating ladder, everywhere, for OVR, grades, percentages and bars alike: **90+ elite green ·
80–89 green · 70–79 blue · 60–69 yellow · <60 red** (`Color.forRating(_:scale:)`). The 21 bespoke
rating→Color functions get deleted, not tolerated. Status color means state (`success`/`warning`/
`danger`), accent gold means "primary/current", accent blue means "informational/selected". A screen
never picks a color because it looked nice — `.orange` for a "Hot" flame and raw `.white` on team
chips are the current tell.

**Corollary — legibility floor.** Nothing informational renders below **10 pt**. 486 literals do
today, including a 6–8 pt tail on Big Board's own micro chips. This is the one place the reference
implementation does not get to keep its behaviour.

---

## 2. The component system

Built on the existing tokens (`DSSpacing` 4/8/12/16/24/32, `DSCornerRadius` 4/8/12, `DSLayout`
720/900/1200, `DSType.Size` 10→48, `DSElevation` chip/card/bar). No new primitives; these are the
missing *structural* components that the tokens were always meant to compose into.

### 2.1 `DSProcessBar` — the spine of every flow
Binds to any `(steps, currentIndex, resourceMeter?)`. Renders: an overline title, a `"Step N of M"`
counter that never hides the total, an optional right-aligned **resource meter** (pips + `4 / 8 wks`),
and a node track where each step is `done` (green check) · `current` (gold, haloed, with a sub-caption)
· `future` (neutral) · `locked` (with the unlock condition as its sub-caption, e.g. "after Pro Days").

One component, four scales: season (`SeasonPhase`), draft prep (`DraftPrepStep`, 9), free agency
(`FreeAgencyStep`, 5), draft day (`DraftDayCoordinator.Mode`), roster cuts (3 stages). It replaces
all seven current progress metaphors. Resource meters move *into* the bar rather than scattering
through the body — today draft prep shows its stage count in three places on one screen.

### 2.2 `DSListRow` — the one list standard
Three densities (P3) over one anatomy (P2). Header and row share a `Column` width enum, as Big Board
and `PlayerRowView` already do — that discipline generalises, the rest is replaced.

**Fixed state-chip slots** are the load-bearing idea: a row reserves N slots (roster: `FIT` / `EXT` /
`HLTH`; board: `RPT` / `CMB` / `MEET`), each slot always occupies its position, and an unset slot
renders dashed at ~32 % opacity. The user scans the column of gaps, not the column of achievements.

**Lens tabs** swap only the trailing columns. Roster lenses: Overview · Contract · Physical ·
Development · Scheme. Board lenses: the existing five. One control style, capsule, one selected fill.

Group headers carry a rollup (`QUARTERBACKS · Group grade A− · 3 players · $41.2M cap`) — Big Board's
tier header, generalised.

### 2.3 Stat chip grammar
Exactly three parts, always in this order, everywhere:

```
LABEL      10 pt, 800 weight, tracked, textTertiaryReadable
value      16 pt, 900 weight, tabular numerals, rating-ladder colored
context    10 pt, 700 weight — rank, delta, or denominator
```

Context is colored **only when it is a movement** (`▲ green` / `▼ red`); a static rank stays grey.
This one shape replaces the four incompatible chip styles. The existing scouting chips
(`ProspectMarkChip`, `ProspectValueChip`, `ProductionTierChip`, `ProspectPrepChips`, `UserGradeBadge`)
are re-based onto it and become app-wide instead of Scouting-only.

Alongside it, `DSStatusPill` — the small state marker: colored dot + 10 pt label + hairline border,
in `neutral / ok / warn / bad / info / empty`. Empty is dashed and dimmed (P2's slot rule).

### 2.4 `DSExplainerCard` — cost and unlock
Gold left rule, an uppercase title, and one or two lines of prose with the load-bearing nouns
emphasised. Three placements: in a flow's action bar (what committing does), in a rail (what this
step buys), on a detail card (what the system is doing to this player, and via which coach).

This is the component that carries P4, and it is how the game explains itself.

### 2.5 `DSActionBar` — the commit surface
Persistent, bottom, `backgroundSecondary` over a top hairline with a `DSElevation.bar` lift.
Left: an explainer or the current selection summary. Right: the fixed button order of P5. Destructive
is ghost-red, separated by a vertical rule, and never adjacent to the primary. The bar is the *only*
place a screen commits.

Two screens already do this well (`FAWeeklyView`, `RosterCutView`) and look nothing alike; they
converge here.

### 2.6 `DSResultSheet` — how a process ends
One modal result pattern: outcome headline → what changed (stat chips with deltas) → what it cost →
a single "Continue →". Replaces the five current termination patterns. In-place body swaps are
banned: a user must never have to scroll *up* to discover that the thing they clicked worked, which
is the current Pro Day behaviour.

### 2.7 `DSEmptyState`
`Common/EmptyStateView.swift` already exists and is used by one of the ten list/detail screens.
One variant per density, always: icon → title → what would fill this → the action that fills it.
Big Board's (icon + title + contextual message + two CTAs) is the model.

### 2.8 `DSPrimaryButton` and the presentation rule

**One `ButtonStyle` set** — `.dsPrimary` (gold fill, `DSCornerRadius.inline`), `.dsSecondary`,
`.dsGhost`, `.dsDestructive` — replacing the three hand-copied gold recipes and their two corner
radii. Disabled state is a genuinely disabled grey, never dimmed gold (five separate audit findings
ask for exactly this).

**And a written rule for sheet vs cover vs push**, because ad-hoc choice already cost a 350 ms
sequencing hack:

| Use | When |
|---|---|
| **push** (`.navigationDestination`) | a reference destination the user will navigate back from — every bookmark target, every detail screen |
| **`.sheet`** (with detents) | a short, cancellable side-task that does not own the screen — filters, notes, a single picker |
| **`.fullScreenCover`** | a *process* (P1): it has steps, it owns the screen, and it ends in a result |
| **`.alert` / `.confirmationDialog`** | confirmation only — never as a result presentation |

Peer actions get the same weight. Never two presentation kinds for two equivalent actions in one
screen, which is the current `CoachedGameView` stats-sheet vs board-cover split.

### 2.9 Section headers and surfaces
`SectionHeaderText` wins outright (uppercase, tracked, gold, 11 pt). `Section("String")` and bespoke
`header: { HStack }` are retired. `cardBackground()` becomes the only card surface — it is used by 30
files app-wide but only 2 of the 10 core list/detail screens.

---

## 3. Per-family verdicts

| # | Family | Screens | Verdict | Rationale |
|---|---|---|---|---|
| 1 | **Broadcast HUD / game day** | `CoachedGameView`, `FootballFieldScene` HUD, `CoachesBoardView` | **KEEP the scoreboard — RESTYLE the call sheet — DELETE the twin** | The scoreboard/clock is the token system's origin and stays (continue under `docs/PRESENTATION_POLISH_PLAN.md`). But the call sheet below it is 317 raw `.system(size:)` against 36 `DSType`, and results arrive by five mechanisms on this one screen (toast capsule · ZStack overlay card · confirmationDialog · sheet · cover). `CoachesBoardView` uses zero `DSType`. And the dead twin goes — see family 15. |
| 2 | **Big Board** | `BigBoardView` | **KEEP as the list reference** | Shared column constants, lens tabs, fixed state-chip slots. One correction only: raise its 6–8 pt micro chips to the 10 pt floor (P7 corollary). |
| 3 | **Draft prep flow** | `ScoutingHubView`, `InterviewSelectionView`, `ProDayTourView`, `CombineResultsView`, `MockDraftView`, `ScoutTeamView` | **REBUILD (wave 0, in flight)** | Nine real stages rendered as a scroll-away banner, three skip affordances, two "done" visuals, stage count printed three times, two stages that complete invisibly. It has the best step machine and the worst step UI — the highest-leverage first instance of P1/P5. |
| 4 | **Career dashboard / week hub** | `CareerDashboardView` (5027 ln), `TimelineTasksPanel` | **REBUILD** | Five competing primary-action slots, three "what's next" metaphors, three Advance buttons, dead layout branches, hardcoded placeholder stats, and several quick actions routing to the wrong destination. P5 and P6 have nowhere to land until this is one hub with one commit. |
| 5 | **Free agency flow** | `FinalPushView`, `NewLeagueYearView`, `CapComplianceView`, `FAWeeklyView`, `FACompleteView` | **REBUILD** | A five-step process where nothing tells the user it is one: five progress treatments (three of them "none") and three advance mechanisms. `FAWeeklyView`'s round dots and bottom bar are the salvage — they become instances of `DSProcessBar` + `DSActionBar`. |
| 6 | **List screens** | `RosterView`/`PlayerRowView`, `StandingsView`, `ScheduleView`, `FreeAgencyView`, `LeagueRostersView` | **RESTYLE onto the standard** | The data and sorting logic are fine; the presentation disagrees five ways. Roster is nearly there already. `FreeAgencyView` is the exception that is effectively a rebuild — it has no column grammar, no header row, and no route into `PlayerDetailView` at all. |
| 7 | **Detail screens** | `PlayerDetailView` (3320 ln), `ProspectDetailView`, `CoachDetailView` | **REBUILD** | Three sibling screens, three section-header conventions, and `PlayerDetailView` carries three hand-forked layout branches that each re-order the same sections — so every future change costs 3×. Rebuild as one study-density three-column layout with `DSActionBar`. `CoachDetailView` is stock `LabeledContent` and reads as an un-designed OS form. |
| 8 | **Draft war room** | `DraftDayCoordinator`, `DraftDayView`, `PickSheetView` | **RESTYLE** | Architecturally the best flow in the app — a real `Mode` state machine with a genuine bottom control bar. It needs the process bar on top of its text-only "ROUND 2 — Pick 14/32", and its five simultaneous overlay mechanisms (forced sheet, top banner, bottom toast, full-screen drama overlay, parallel round-recap sheet) reduced to the standard set. |
| 9 | **Camp** | `RosterCutView`, `TrainingPlanView`, `WorkloadDashboard`, `GameWeekPrepPicker`, prompts | **RESTYLE** | Three cut stages exist as title strings with no indicator; three different action placements inside one small directory. Small surface, mechanical fix once the components exist. |
| 10 | **Staff** | `CoachingStaffView` (4194 ln), `HireCoachView`, `CoachDetailView` | **RESTYLE → partial rebuild** | A fourth tab-bar implementation, actions scattered across `@AppStorage`-collapsed sections, a top-toast feedback metaphor unique to this file, and a hire list whose primary action lives only inside a `fullScreenCover`. Hiring is a process and should say so. |
| 11 | **Modals & results** | `GameSummaryView`, `FARoundSummaryView`, `RoundRecapSheet`, `RookieClassRevealView`, `OwnerSeasonReviewSheet`, `HoldoutDialog` | **RESTYLE onto `DSResultSheet`** | Nine modal slots hang off `CareerShellView` alone, each with its own result grammar. The content is good; the container should be one. |
| 12 | **News / inbox** | `NewsView`, `InboxView` | **RESTYLE** | Feed rows become `DSListRow` at glance density; headlines gain the consequence line (P4) so news reads as input to decisions rather than flavour. `NewsView` has no primary action at all — cards only expand in place — and is the one filter strip using blue where the app uses gold. |
| 12b | **Press conference & owner** | `PressConferenceView`, `WeeklyPressConferenceView`, `OwnerMeetingView` + `IntroSequenceView.OwnerMeetingStep` | **MERGE, then restyle** | Two ~1000-line press implementations already drifted (scrim 0.32 vs 0.25, 4- vs 3-stop gradient), and two separate owner screens. Deduplicate into one component each *before* styling anything, or every fix costs 2×. Answers commit on first tap with no undo — P5's confirmation corollary applies. |
| 13 | **Entry & onboarding** | `MainMenuView`, `NewCareerView`, `TeamSelectionView`, `IntroSequenceView` | **RESTYLE** | `MainMenu` uses **zero** structural tokens — the first screen a player sees is the least systematic. `NewCareerView` already has a step indicator; it becomes the first non-flow instance of `DSProcessBar`. |
| 14 | **Contracts & trades** | `ContractNegotiationView`, `TradeNegotiationView`, `TradeView`, `ContractExtensionSheet`, `CapOverviewView` | **MERGE the two chats, then restyle** | Two independent negotiation-chat implementations (~3490 ln) sharing no bubble/transcript/header. The chat-transcript metaphor is the strongest interaction in the app — make it one component. Then: negotiation is a process with rounds and a result, so it mounts the bar and ends in `DSResultSheet`. `CapOverviewView` is the best-behaved file in the group and documents its own token reasoning; `TradeView` hardcodes `720` where `DSLayout.contentMeasure` exists and uses `.large` nav title where its sibling documents why `.inline` is correct for a centred iPad column. |
| 15 | **Dead code** | **`Match/MatchView.swift` (921) + `Match/PlayCallView.swift` (537)**, `CareerDashboardView.timelineStrip` (~100), `.portraitLayout` (~80), `Common/TimelineStripView.swift` (243), `ShellDestination.hireHC/OC/DC`, `Mode.roundTransition` | **DELETE — do this first** | ~1880 lines, zero references outside their own `#Preview`s. `MatchView` is an entire second game screen implementing play-calling as a modal sheet — the opposite of the shipped inline panel — so it is not just dead weight, it is a competing answer to a question wave 3 must settle. Delete before restyling anything in `Match/`. |

---

## 4. Implementation waves

Each wave is independently shippable and ends with the same gate. Nothing in a later wave is a
prerequisite for an earlier one shipping.

**Standard gate for every wave**
1. `python3 tools/lint/design_tokens.py` — no regression, and the wave's own files improve.
2. On-sim walkthrough of every touched screen on the iPad Pro sim (`dynasty-sim-qa`), screenshots
   captured before/after.
3. No new `.system(size:)` below 10 pt; no new bespoke rating→Color function.
4. English-only strings.
5. The user's eye on the screenshots before the wave is called done.

---

### Prelude — delete the dead code *(hours, not days; no gate beyond a clean build)*
Do this before anything else, because it shrinks the surface every later wave has to reason about
and removes a competing answer to a question wave 3 has to settle.

- `Match/MatchView.swift` (921) + `Match/PlayCallView.swift` (537) — the unreachable second game
  screen and its modal play-call sheet.
- `CareerDashboardView.timelineStrip` (~100) and `.portraitLayout` (~80).
- `Common/TimelineStripView.swift` (243).
- `ShellDestination.hireHC/hireOC/hireDC`, `Mode.roundTransition`.

**~1880 lines.** Verify each with a `grep -rn "TypeName(" --include="*.swift"` returning only its own
`#Preview` before deleting.

---

### Wave 0 — `DSProcessBar`, first instance: draft prep *(in flight)*
The draft-path overhaul already underway in `UI/Scouting/*` — task **#103**
(`d1fadd0 feat(scouting): draft-path overhaul — prep wizard, merged board, pro day realism`) — is the
pattern's first real instance. `DraftPrepCard.stageProgressBar` is the prototype. Land it as a
**shared** `DSProcessBar` in `UI/Common/`, not a Scouting-local view, and make draft prep its first
consumer.

> **Coordination note.** `UI/Scouting/*` is under active edit and its files carry "Wave A / Wave B /
> this wave does not own the file" markers. Treat the stage-gate *design* as the agreed direction and
> the *file boundaries* as provisional; extract the shared component when that work settles rather
> than racing it.

- Extract the process bar; bind to `DraftPrepStep` (9 stages, `ScoutingStageGate`).
- Move the advance out of the scrolling header into a `DSActionBar` (P5).
- One skip affordance, not three. One "stage complete" visual, not two.
- Kill the two invisible tab-open completions (P1).
- Stage count rendered **once**.

**Gate additions:** walk all 9 stages on-sim; every stage shows position, cost, and what it unlocks.

---

### Wave 1 — List standard
`DSListRow` (3 densities) + column enum + fixed state-chip slots + lens tabs + stat chip grammar +
`DSStatusPill` + `DSEmptyState` adoption.

- Build against Big Board (which changes least: raise micro chips to the 10 pt floor, otherwise keep).
- Convert **Roster** first — it already mirrors Big Board, so it proves the abstraction cheaply.
- Then Standings, Schedule, League Rosters.
- **FreeAgencyView last** in this wave, since for it this is a rebuild: give it a header row, shared
  widths, and a `NavigationLink` into `PlayerDetailView`.

**Gate additions:** row heights across all six screens fall into exactly three values.

---

### Wave 2 — Hub and shell
The dashboard, the timeline panel, and the navigation spine.

- One hub layout (delete the dead portrait branch and the dead timeline strip).
- One commit: the hero action. Task rows carry scoped secondary actions and a cost→unlock line (P4).
- Replace the three "what's next" metaphors with one.
- Fix the wrong quick-action destinations; delete the hardcoded placeholder stats.
- Audit `ShellDestination`: merge aliases, delete unreachable cases, make the six scouting deep links
  resolve to real destinations rather than a droppable string hint (P6).
- Bookmark strip → seven, with Hub as one of them.

**Gate additions:** every bookmark and every task tap lands on a screen that can service it; no
destination is a dead end.

---

### Wave 3 — Flows on the bar
Every remaining multi-step process mounts `DSProcessBar` + `DSActionBar` + `DSResultSheet`.

- Free agency (5 steps) — salvage `FAWeeklyView`'s dots and bottom bar as the reference instances.
- Roster cuts (3 stages).
- Draft war room — process bar over the existing `Mode` machine; reduce five overlay mechanisms to
  the standard set; retire the parallel `roundTransition`/`pendingRoundRecap` duplication.
- **Merge the two negotiation chats first**, then put the single result on the bar — rounds become
  steps, outcome becomes a result sheet, and the duplicate "Close"/"Done" pair collapses to one.
- Season phases in the shell.
- Apply the §2.8 presentation rule across the app: every process becomes a cover, every side-task a
  sheet, every reference destination a push. Retire the `MainMenuView` 350 ms sequencing hack.

**Gate additions:** no flow terminates by in-place body swap; every flow can be entered, completed,
and exited without the user guessing. Modal-presentation count drops materially from 85, and no two
peer actions in one screen use different presentation weights.

---

### Wave 4 — Detail screens
`PlayerDetailView`, `ProspectDetailView`, `CoachDetailView` as one study-density layout.

- One layout, not three forks. Hero → three columns of grouped cards → `DSActionBar`.
- `SectionHeaderText` only.
- Attribute bars on the shared rating ladder; delete the bespoke rating→Color functions (all 21,
  app-wide, in this wave).
- Development/status cards gain explainers (which coach, which focus, what it is doing).
- `CoachDetailView` stops being a stock form.

**Gate additions:** `ratingfn` count reaches 0 in the lint baseline.

---

### Wave 5 — Long tail
Staff, Camp, news/inbox, press & owner, modals, entry & onboarding, and the game-day call sheet.

- **Merge the two press-conference views and the two owner screens**, then restyle the survivors.
  Press answers gain P5's confirmation corollary.
- `CoachingStaffView`'s tab bar and toast → standard components; hiring becomes a visible process.
- All nine shell modal slots onto `DSResultSheet`.
- Game-day call sheet + `CoachesBoardView` onto `DSType` (the scoreboard already is); reduce the
  screen's five result mechanisms to the standard set.
- `MainMenuView` and `TeamSelectionView` onto tokens — the first screen a player sees should be the
  most systematic, not the least.
- `DSPrimaryButton` adopted app-wide; the three hand-rolled gold recipes deleted.

**Gate additions:** full-career on-sim walkthrough (new career → season → FA → draft prep → draft →
camp) with no screen falling outside the language. Zero duplicate implementations of any one feature.

---

## 5. What "done" looks like

- One row component, three densities, used by every list.
- One process bar, used by every multi-step flow, bound to step machines that already exist.
- One place the primary action lives; one gold fill per screen; one dismissal verb; confirmation
  decided by a rule rather than by whoever wrote the screen.
- One rating ladder; zero bespoke rating→Color functions.
- Nothing informational below 10 pt.
- **Zero features implemented twice** — one play-call UI, one press conference, one negotiation chat,
  one owner screen.
- A written rule for push vs sheet vs cover, and no timing hacks to work around modal conflicts.
- `DSSpacing`, `DSCornerRadius` and `DSElevation` adopted outside the HUD, with the lint baseline
  moving down every wave instead of holding flat.
- A player can name what a chip, a step, and a commit look like — and be right on every screen.
