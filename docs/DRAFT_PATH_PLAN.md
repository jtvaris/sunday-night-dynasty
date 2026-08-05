# The Path to the Draft — Investigation Report & Overhaul Plan

*2026-08-05. Recon over the whole pre-draft surface (scouting hub, big board,
prospect list, pro days, interviews, workouts, mock drafts, the fog layer and
the `WeekAdvancer` phase hooks that feed them). Every claim carries a
file:line against the working tree at HEAD. No code has been changed yet —
this document is the decision gate for the overhaul, and it is written against
seven locked user observations (§1).*

---

## 1. The seven locked observations

| # | Observation | Verdict |
|---|---|---|
| 1 | Scouting list pages: only the list scrolls, the header eats the screen (3 rows landscape / 8 portrait). Merge Big Board + Prospects into ONE list surface. | **CONFIRMED** — F1, F2 |
| 2 | Flow order is wrong: workout invites are live at combine time and sit at the bottom of the prospect card. | **CONFIRMED** — F3 |
| 3 | Pro Day tab mixes Top-30 visits and pro days; its buttons do nothing; listing is very slow; results never reach the player. | **CONFIRMED, four separate defects** — F4, F5, F6, F7 |
| 4 | Workouts must be their own tab: Big-Board-style filterable list → tap → invite → results in a modal. | Design (Wave B) |
| 5 | Mock drafts as league events: one after pro days, one right before the draft. | Engine already runs 4 mock moments; **neither is an event the user is told about** — F8 |
| 6 | The whole prep is a staged pipeline with forced transitions; earlier stages stay viewable. | Precedent exists (`FreeAgencyStep`, `combineChain`) and is unused here — F9 |
| 7 | TAPE and MEET are mixed into one column. Film study becomes its own stage funded by the existing evaluation-slot economy (#79). | **CONFIRMED** — F10 |

## 2. What exists today (architecture map)

| Component | Lines | Status |
|---|---|---|
| `ScoutingHubView` (hub + `ProDayListView` + sheets) | 2793 | LIVE — 9 tabs, fixed header, one file holds two screens |
| `BigBoardView` | 3018 | LIVE — the real board: tiers, My Board, compare, filters, `.onMove` |
| `ProspectListView` | 1926 | LIVE — **the same data, a second time**, owns `ProspectAttributeTab` |
| `CombineResultsView` | 1105 | LIVE — third table over the same class |
| `InterviewSelectionView` | 1636 | LIVE — 60 slots on `Career.interviewsUsed` |
| `ProspectDetailView` (+ `ScoutEvaluationBudget`) | 2686 | LIVE — the #79 evaluation economy lives here |
| `MockDraftView` | 1365 | LIVE — reads `WeekAdvancer.currentMockDraft` |
| `DraftPrepCard` (+ `ProspectPrepChips`) | 545 | LIVE — the best piece on the screen |
| `ScoutingEngine` | 4574 | LIVE — combine, pro-day circuit, interviews, Top-30, workouts |
| `ProspectFog` | ~700 | LIVE — the single fog authority |
| `DraftIntel` | — | LIVE — the media-consensus authority |
| `ScoutingPhase` enum | 29 | LIVE — `.collegeSeason … .personalWorkout`, a *confidence* ladder, **not** a UI state machine |

Phase order the prep spans (`WeekAdvancer.swift:4685-4690`):
`combine → freeAgency → proDays → draft`. Three phases, no stage model inside
them.

## 3. What is genuinely good (keep verbatim)

- **`ProspectFog`** — one authority for what the user is allowed to read:
  grade bands, `combineFidelity` full-vs-broadcast (`:139`), the flag-disclosure
  ladder, `footballIQ` (`:301`). Every new column in this plan reads it. It is
  not touched except to *split* one accessor (F10).
- **`ScoutEvaluationBudget`** (`ProspectDetailView.swift:19-89`) — 25 slots a
  cycle, rising cost 20/35/55 K, 3 reports per prospect max, cycle-stamped via
  `thisCycle(_:stampedSeason:currentSeason:)` so it self-resets with the class.
  **This is the currency film study spends. No new currency is introduced.**
- **`DraftIntel.mediaConsensusOrder` / `refreshConsensusBoard`** — public
  information only, pure, session-cached. Stays the consensus authority.
- **The league pro-day circuit** (`ScoutingEngine.runLeagueProDays:3594`) —
  already implements exactly the realism model the user describes: everybody's
  numbers become public at broadcast precision, and `attendProDay:1520` is the
  paid trip that buys the decimals, a filed `.proDay` report and disclosure.
  The model is right; **the UI never says so**.
- **`DraftPrepCard`** — reads stored state, not phase-derived guesses. It
  becomes the wizard's progress header.
- **`FreeAgencyStep`** (`Domain/Enums/FreeAgencyStep.swift` + `Career.swift:58`
  + `CareerShellView.swift:1595-1626`) — the exact persisted-step precedent this
  plan mirrors.
- **`TaskGenerator.combineChain`** (`:1098`) + `GameTask.matchKey` — a working
  sequential-unlock chain with counter-decorated titles already solved.

## 4. Findings (ranked)

### F1 — The hub header is a fixed 40 % of the screen; only the list scrolls.
`ScoutingHubView.body` (`:53-110`) is `VStack(spacing: 0)` of
`overviewMetrics` → `DraftPrepCard` → combine CTA → `tabPicker` →
`positionFilterChips` → `Divider` → `tabContent`. Everything above
`tabContent` is outside the scroll view, permanently. `DraftPrepCard` alone
defaults to expanded (`@AppStorage("draftPrepCardExpanded") = true`,
`DraftPrepCard.swift:98`). Measured effect matches the report: 3 rows in
landscape.

### F2 — Two list surfaces over one dataset, and the mode picker is duplicated.
`ScoutingTab.prospects` → `ProspectListView` and `.bigBoard` → `BigBoardView`
render the same `[CollegeProspect]` with the same `ProspectAttributeTab`
picker — the enum is *declared* in `ProspectListView.swift:6` and re-hosted as
`@State` in both (`BigBoardView.swift:26`, `ProspectListView.swift:40`). The
hub already had to hoist the position filter out of them because three private
copies fought each other (`ScoutingHubView.swift:22-32`). The board is the
richer surface (tiers, My Board, `.onMove`, compare tray, board comparison);
the list is a strictly weaker subset.

### F3 — The evaluation ladder runs backwards.
`ProspectDetailView.isWorkoutWindow` (`:221`) opens private workouts across
`.combine … .draft`, and the button lives at the bottom of the action stack
(`:2122-2146`). So the highest-fidelity, most-rationed instrument in the game
(`ScoutingPhase.personalWorkout.confidenceLevel = 0.9`) is available on the
first day the user sees the class, before a single interview. The intended
ladder is already encoded in `ScoutingPhase.confidenceLevel`
(0.4 → 0.55 → 0.7 → 0.75 → 0.9) and nothing enforces it.

### F4 — The Pro Day tab is two features in one list.
`ProDayListView` (`ScoutingHubView.swift:1003-2273`) renders, in one `List`:
an info banner, a capacity gauge, scout availability cards, **the Top-30 visit
section** (`:1508`), recommended schools, all schools grouped by a fake
calendar week, an "execute" button, a results panel, and **a Personal Workouts
section** (`:1420`). Three distinct economies (`career.top30VisitsUsed`,
`scout.proDaysAttended`, a workout counter) share one scroll.

### F5 — The pro-day buttons genuinely do nothing new.
`sendScoutToProDay` (`:2228`) calls `ScoutingEngine.attendProDay`
**immediately on assignment** — which sets `proDayCompleted = true` for every
prospect at that school. The big gold "Send Scouts to Pro Days" button then
calls `executeProDays` (`:1670`), whose per-college guard is
`needsRun = contains { !$0.proDayCompleted }` — **always false**. It walks the
assignments, runs nothing, and prints a summary of work already done. The user
is not wrong: the button is a no-op with a receipt.

### F6 — The pro-day listing is quadratic-ish over UserDefaults JSON.
`boardOrder` (`:1035`) JSON-decodes the persisted custom board *on every
access*. `boardRank(for:)` (`:1041`) calls it and then does a linear
`firstIndex`. `isTopProspect` (`:1052`) calls `boardRank`. `collegeData`
(`:1062`) is an **uncached computed property** that groups the whole declared
class (~250-330 men) by college and calls `isTopProspect` once per prospect.
`recommendedColleges` (`:1101`) calls `collegeData` again; the body calls
`recommendedColleges` twice (`:1299`, `:1315`) and `collegeData` again for the
week grouping (`:1334`); each school row calls `boardRank` again (`:1886`) and
each expanded row calls it **twice more** (`:2006`) plus once per prospect row
(`:2127`). Order of magnitude: several thousand decode-plus-linear-scan
operations of a ~300-element array **per SwiftUI body evaluation**, and the
body re-evaluates on every `@State` touch. `BigBoardView` already solved this
exact problem with `cachedCustomRankMap` (`:57`) — the pro-day screen never
adopted it.

### F7 — Pro-day and workout results never reach the canonical class.
Two mutation conventions coexist. `scheduleTop30Visit` (`:1615`) and
`focusProspect` (`:1655`) do it right: mutate `WeekAdvancer.currentDraftClass`,
write back, `persistDraftClass`, `save`. `sendScoutToProDay` (`:2228`) mutates
the view's `@Binding var prospects` and calls only `modelContext.save()` —
never `WeekAdvancer.currentDraftClass = …`, never `persistDraftClass`. The
static class is the array every other screen and every engine hook reads
(`WeekAdvancer.swift:56`), and it is re-seeded from SwiftData on process
restart (`:204-237`). Whatever survives is luck of object identity, which is
why "after a pro day runs, results must appear on the player" reads as broken.

Same file, worse: `conductPersonalWorkouts` (`:1726`) implements a *private
workout* by calling `ScoutingEngine.attendProDay` — a whole-school pro day for
the prospect's college — instead of `ScoutingEngine.conductPersonalWorkout`
(`:1686`), and bills it to a `@CareerScopedStorage("personalWorkoutsUsed")`
counter capped at **10**, while `ProspectDetailView.performWorkout` (`:2408`)
bills the same action to `career.workoutsUsed` capped at **30**
(`:201`). **Two workout economies, two caps, two engines, one feature.**

### F8 — Four mock drafts run; zero are events.
`WeekAdvancer` generates and stores four: `"Mid-Season"` (`:2189`),
`"Combine"` (`:3333`), `"Post-FA"` (`:3523`), `"Pre-Draft"` (`:4230`), each
followed by `applyMockDrift(moment: 1…4)` (`:4257`). Only moment 2 (via the
combine hook) and moment 4 emit news; moments 1 and 3 move the board in
silence. `mockDraftHistory` is a **static in-memory dictionary** (`:116`),
wiped on process restart — the "compare the mocks" affordance the data is
shaped for cannot exist. And no mock is generated *after* the pro-day circuit:
moment 3 fires at the end of `.freeAgency`, before the tour.

### F9 — There is no prep state machine, so nothing can be sequenced.
`Career` carries `interviewsUsed`, `workoutsUsed`, `top30VisitsUsed`
(`Career.swift`, "Scouting Counters"), plus five `@CareerScopedStorage` flags
scattered across views (`scoutsSentToCombine`, `combineResultsReviewed`,
`combineTripSpend`, `scoutEvaluations*`, `personalWorkoutsUsed`). No field says
*where in the pre-draft process this club is*. `ScoutingPhase` looks like the
answer and is not: it is a per-report confidence ladder with no persisted
current value and no UI reader. Consequence: the hub shows nine tabs at once
in every phase, the required-task chain only exists for the combine, and
`.proDays` has four unordered tasks (`TaskGenerator.swift:628-684`).

### F10 — TAPE and MEET share one 40-point column.
`ProspectIQCell` (`ProspectFog.swift:578-611`) prints **one** football-IQ read
with a four-character source tag — `"MEET"` when it came from an interview,
`"TAPE"` when it came from the scouts — because `ProspectFog.footballIQ`
(`:301`) is a precedence function: interview number wins, scout letter band is
the fallback. So a board row shows `86 MEET` next to `C-/B+ TAPE` and the user
is asked to compare a number to a letter in the same column. The two are
different instruments answering different questions and belong in two columns.

## 5. The design — one staged pipeline

### 5.1 The stage enum (PINNED)

New file `Domain/Enums/DraftPrepStep.swift`, shaped exactly like
`FreeAgencyStep`:

```swift
enum DraftPrepStep: String, Codable, CaseIterable {
    case combineReview  = "CombineReview"   // combine numbers + prior-season reports
    case filmStudy      = "FilmStudy"       // TAPE  — spends ScoutEvaluationBudget slots
    case interviews     = "Interviews"      // MEET  — spends career.interviewsUsed
    case proDayFocus    = "ProDayFocus"     // pick the schools; broadcast baseline for the rest
    case workouts       = "Workouts"        // private workouts, modal results
    case mockOne        = "MockOne"         // league event: the post-tour mock
    case top30Visits    = "Top30Visits"     // facility visits
    case mockTwo        = "MockTwo"         // league event: the final mock
    case ready          = "Ready"           // draft room unlocked

    var order: Int { DraftPrepStep.allCases.firstIndex(of: self)! }
    var displayName: String { … }
    /// The phase this stage belongs to. `.freeAgency` is deliberately absent:
    /// the market has its own step machine and the prep stage is frozen there.
    var phase: SeasonPhase { … }   // combineReview…interviews → .combine;
                                   // proDayFocus…mockTwo     → .proDays;
                                   // ready                   → .draft
}
```

Persistence on `Career` (inline defaults only — lightweight migration, never
init parameters, exactly like `lastRolloverSeason`/`lastBulkMarketSeason`):

```swift
var draftPrepStep: String = DraftPrepStep.combineReview.rawValue
/// Cycle stamp. A step written in an earlier draft cycle reads as
/// `.combineReview`, so the pipeline resets with the class without needing a
/// hook in WeekAdvancer — same trick as ScoutEvaluationBudget.thisCycle.
var draftPrepStepSeason: Int = 0
```

Read through one accessor so the stamp can never be forgotten:

```swift
extension Career {
    var prepStep: DraftPrepStep {
        get { draftPrepStepSeason == currentSeason
              ? DraftPrepStep(rawValue: draftPrepStep) ?? .combineReview
              : .combineReview }
        set { draftPrepStep = newValue.rawValue; draftPrepStepSeason = currentSeason }
    }
}
```

### 5.2 Forced transitions, read-only history

Each stage owns **one required task** and **one advance button**. The advance
button is disabled until the stage's completion predicate is true; pressing it
writes the next step and, where the stage has a batch action (the pro-day
tour), *runs it*.

| Stage | Required task (`TaskGenerator`) | Completion predicate | Advance also does |
|---|---|---|---|
| combineReview | "Review Combine results" | `combineResultsReviewed` (existing flag) | — |
| filmStudy | "Order film study on your board" | ≥ 8 evaluations spent this cycle **or** user taps "skip — we have enough tape" | — |
| interviews | "Conduct prospect interviews" | `career.interviewsUsed > 0` | — |
| proDayFocus | "Choose pro-day schools" | ≥ 1 focus slot assigned **or** explicit skip | runs the tour ONCE (`executeProDays`) |
| workouts | "Invite prospects to work out" | any workout run **or** skip | — |
| mockOne | "Read the mock" | user opened the mock event | — |
| top30Visits | "Host Top-30 visits" | ≥ 1 visit **or** skip | — |
| mockTwo | "Read the final mock" | opened | — |
| ready | — | — | — |

**Every stage is skippable, none is silently skippable.** A skip is a button
that says what it costs ("you will go into the draft on the media's tape"),
mirroring the combine trip's "or watch it on television" copy
(`ScoutingHubView.swift:255`).

**Earlier stages stay viewable, read-only.** Tab visibility is
`tab.minimumStep.order <= career.prepStep.order`; a tab whose stage has passed
renders with its actions disabled and a "closed" chip. This is `visibleTabs`
(already a hook in `ScoutingHubView`) driven by the step instead of the phase.

### 5.3 Merged Big Board information architecture

`ScoutingTab` after the merge:

```
board (was bigBoard, absorbs prospects) · combine · film · interviews ·
proDays · workouts · mock · draftOrder · scouts · nextYear
```

- `ProspectListView` **is deleted as a view**. Its two enums
  (`ProspectAttributeTab`, `ProspectSort`) move to a new
  `UI/Scouting/ProspectListModels.swift`; nothing else survives. The board
  already hosts the identical picker (`BigBoardView.swift:1142`).
- `ProspectAttributeTab` gains `.workup` (reports · TAPE · MEET · pro day ·
  visit) and keeps `overview / physical / mental / position`.
- **TAPE and MEET become two always-visible columns**, replacing the single
  `ProspectIQCell` in `BigBoardRowView` (`BigBoardView.swift:2427`).

### 5.4 Full-page scroll — the concrete SwiftUI restructure

The naive fix (wrap the hub in a `ScrollView`) is illegal: `BigBoardView`,
`ProDayListView` and `CombineResultsView` each own a `List`, and a `List`
inside a `ScrollView` collapses or grows unbounded. Converting a 3018-line
`List` to `LazyVStack` also destroys `.onMove` (`BigBoardView.swift:970`,
`:997`), which is the board's whole reordering interaction.

**Decision: one scroll owner per surface, and the header moves *into* it.**

1. Extract the hub header into `UI/Scouting/ScoutingHubHeader.swift` —
   a plain `View` taking the metrics strip, the (collapsed-by-default)
   `DraftPrepCard`, and the stage banner.
2. Each list surface takes `@ViewBuilder header: () -> Header` and renders it
   as its **first section**:
   ```swift
   List {
       Section { header() }
           .listRowInsets(EdgeInsets())
           .listRowBackground(Color.clear)
           .listRowSeparator(.hidden)
       …existing sections…
   }
   ```
3. Only the **tab picker + position chips** stay pinned, as a single 36 pt row
   between the navigation bar and the list.

Result: one scroll gesture, the header scrolls away, `.onMove` survives, no
nested scroll views, and no surface rewrite. Header budget: **≤ 96 pt pinned**
(down from ~330 pt), which puts ≥ 10 rows on a landscape iPad.

Condensation, in the same wave: `overviewMetrics` 4 items → one 28 pt strip
with the two that matter (scouted %, phase); `DraftPrepCard` defaults to
collapsed (`@AppStorage("draftPrepCardExpanded")` initial value flips to
`false`) and collapsed state is a one-line progress bar; the combine CTA moves
inside the `combine` tab (it is a stage action, not a hub chrome item).

### 5.5 Pro days — per-school rows and focus slots

**The realism model, stated in the UI:** every club gets a broadcast-level read
from every pro day (`runLeagueProDays` — already true, currently invisible).
Sending scouts/coaches to a *limited* number of schools buys exact decimals, a
filed `.proDay` report and disclosure at those schools (`attendProDay` —
already true, currently mis-wired). The tab's copy says this in one sentence
at the top instead of the current "Reports improve scouting accuracy by
10-15 %" placeholder (`ScoutingHubView.swift:1236`).

- **Grouping source:** `Dictionary(grouping: prospects.filter(\.isDeclaringForDraft)) { $0.college }` —
  unchanged from `:1064`, but computed **once** into cached `@State`, refreshed
  on `.task` and on board-mark change, never in a computed property.
- **Per-school counts from My Board marks:** `elite` = `userMark == .elite`,
  `targeted` = `userMark.isBoardPositive` (elite + target), `need` = position
  ∈ `DraftEngine.topTeamNeeds(roster:limit:5)`. Rendered as a single chip row
  `3 ELITE · 5 TGT · 2 NEED · 14 declared`, sorted by a relevance score that
  is the existing `starred*10 + top*5 + need*3 + count` formula (`:1085`).
- **Focus allocation UX:** `Σ scout.maxProDays` (`Scout.swift:76`) is renamed
  in copy from "assignment capacity" to **focus slots** — the limited resource.
  Assigning a school **reserves** a slot; nothing runs. The stage's advance
  button ("Send the department out") runs the tour once, through
  `executeProDays`, and shows the results panel. This kills F5 by construction:
  there is exactly one execution path and it is the transition.
- **Kill `proDayWeek`** (`:1164`) — a fake calendar week derived from
  `abs(hash(college)) % 5 + 1`. It buys nothing and costs a grouping pass.
- **Top-30 visits move out** to their own stage/tab (§5.2), which is also the
  correct chronology: facility visits are the last instrument before the draft.

### 5.6 Workouts tab

`UI/Scouting/WorkoutsTabView.swift` — a Big-Board-style list (same row
component, same position filter binding, same search/filter/sort menu),
filtered by default to men on the board who have not worked out. Tap a row →
invite → engine runs → **`WorkoutResultSheet`** (a real sheet, not the current
`.alert` at `ScoutingHubView.swift:1671`) showing: grade band before/after,
scheme-fit note, personality read, medical flags, and the slot counter.

**One economy:** `career.workoutsUsed` / 30. The
`@CareerScopedStorage("personalWorkoutsUsed")` 10-cap counter
(`ScoutingHubView.swift:1017`) is deleted. **One engine:**
`ScoutingEngine.conductPersonalWorkout`. The `attendProDay` misuse at `:1733`
is deleted.

### 5.7 The two mock-draft events

**Decision: do not add a fifth engine mock.** The drift budget
(`applyProjectionDrift`, ≤ 1 round, ≤ 8 pairs, zero-sum) is calibrated for
four moments and `draftProjection` anchors AI perception and the rookie bands.
Instead:

1. **Move moment 3 from the end of `.freeAgency` to the `.proDays` hook,
   after the circuit.** The block at `WeekAdvancer.swift:3501-3527`
   (`generateMockDraft` + `updateTeamInterest` + `applyMockDraftToProspects` +
   `mockDraftHistory["Post-FA"]` + `applyMockDrift(moment: 3)`) moves below
   `runLeagueProDays` / `proDayPressure` drift at `:3550`, and the history key
   becomes `"Post-Pro-Day"`. It still runs after free agency has reshaped 32
   rosters, so `updateTeamInterest` is as correct as before — it now also reads
   the pro-day numbers, which is what makes it a *post-tour* mock. The drift
   salt (`mockDrift &+ moment`) is unchanged, so determinism per career is
   preserved; the **values** change, so the smoke re-baselines (§9).
2. **Both moments emit a feed event.** `applyMockDrift` currently emits news
   only from moment 4 (`:4276`). Moments 3 and 4 both emit, via a new
   `NewsGenerator.mockDraftEvent(history:moment:season:)`: one headline
   ("Consensus Mock 1.0 is out"), the top 5 picks, the user's own board's
   biggest disagreement with it, and the two loudest risers/fallers (which
   `projectionDriftNews` already produces).
3. **Persist the history.** `WeekAdvancer.mockDraftHistory` (`:116`) is a
   static wiped on relaunch. Serialise it onto `Career` as a JSON blob
   (`var mockDraftHistoryData: Data? = nil`, inline default) so
   `MockDraftView` can render "Mock 1.0 vs Final" after an app restart. This
   is the only new stored field beyond the two step fields.

### 5.8 AI symmetry

The AI does not run film study, interviews or tours — it does not need to;
`AIDraftPerception` gives each club its own noisy read of the class and is
untouched. Two symmetry rules must nevertheless hold:

- The pro-day **baseline is league-wide** — already true
  (`runLeagueProDays` writes public numbers for the whole DNP cohort).
- **Top-30 visits must not be a user-only mark.** `CollegeProspect.top30VisitedByTeams`
  (`:158`) is written only by `conductTop30Visit`, i.e. only by the user, so
  the "who else is in on him" line on a prospect card is structurally always
  "nobody". Add a deterministic AI pass at the `.proDays` hook: each AI club
  stamps ~30 IDs off its own `AIDraftPerception` board, seeded on
  `cycleSeed(careerID:season:salt:)`. Flavour + a real competition signal;
  **no change to AI draft quality**, and no new engine authority.

### 5.9 What does NOT change

- **Fog authority stays `ProspectFog`.** New TAPE/MEET cells are two reads on
  the same enum, nothing bypasses it, and no screen reads a true attribute.
- **Evaluation economy stays #79's** — 25 slots, 20/35/55 K rising cost, 3
  reports/prospect, `thisCycle` stamping, `isWindowOpen`. Film study is a
  *presentation* of that spend, not a second wallet.
- **Media consensus stays `DraftIntel`** — `mediaConsensusOrder`,
  `refreshConsensusBoard`, `PrepStatus`. No new board ordering.
- **Draft class generation** (`DraftClassBuilder`, `generateDraftClass`) and
  the **draft room** (`DraftDayView`, `DraftDayCoordinator`, war room, trade-up)
  are out of scope.
- **`ScoutingPhase`** keeps its only job: report confidence.

---

## 6. PINNED cross-wave API contracts

Every wave codes against these. They are introduced in Wave 0 and no later wave
may change a signature without amending this section.

```swift
// ── Domain/Enums/DraftPrepStep.swift ─────────────────────────────────────────
enum DraftPrepStep: String, Codable, CaseIterable {
    case combineReview, filmStudy, interviews, proDayFocus,
         workouts, mockOne, top30Visits, mockTwo, ready
    var order: Int { get }
    var displayName: String { get }
    var phase: SeasonPhase { get }
    /// Task title the stage's advance button is gated on. Compared against
    /// `GameTask.matchKey`, never against `title` (counter decoration).
    var requiredTaskKey: String? { get }
}

// ── Domain/Models/Career.swift (inline defaults ONLY) ────────────────────────
var draftPrepStep: String = DraftPrepStep.combineReview.rawValue
var draftPrepStepSeason: Int = 0
var mockDraftHistoryData: Data? = nil
extension Career { var prepStep: DraftPrepStep { get set } }   // cycle-stamped

// ── Engine/Scouting/DraftClassMutator.swift (NEW — the F7 fix) ───────────────
/// The ONE way any screen mutates the draft class. Reads
/// `WeekAdvancer.currentDraftClass`, applies `body`, writes it back, calls
/// `WeekAdvancer.persistDraftClass` and saves. No call site may mutate a local
/// `[CollegeProspect]` and hope.
enum DraftClassMutator {
    @discardableResult
    static func mutate(_ context: ModelContext,
                       _ body: (inout [CollegeProspect]) -> Void) -> Bool
}

// ── Engine/Scouting/ScoutingEngine.swift (signature changes) ─────────────────
struct WorkoutResult {          // NEW — what the modal renders
    let prospectID: UUID
    let gradeBefore: GradeRange?
    let gradeAfter: GradeRange?
    let schemeFitNote: String
    let personalityNote: String?
    let impressions: [String]
}
@discardableResult
static func conductPersonalWorkout(prospect: CollegeProspect,
                                   coaches: [Coach]) -> WorkoutResult   // was Void

struct ProDaySchoolSummary {    // NEW — one row of the school list, precomputed
    let college: String
    let declared: Int
    let eliteCount: Int
    let targetedCount: Int
    let needCount: Int
    let bestProspectID: UUID?
    let relevance: Int
    let isFocused: Bool
    let focusedScoutName: String?
}
/// PURE. Takes a precomputed rank map — never decodes UserDefaults. (F6)
static func proDaySchoolSummaries(prospects: [CollegeProspect],
                                  scouts: [Scout],
                                  teamNeeds: Set<Position>,
                                  boardRanks: [UUID: Int]) -> [ProDaySchoolSummary]

// ── UI/Draft/Components/ProspectFog.swift (the F10 split) ───────────────────
/// Today's `footballIQ` is a precedence function (interview wins, scouts
/// fall back). These two are the SAME data, un-merged. `footballIQ` stays for
/// the draft room's tight rows.
static func tapeRead(_ prospect: CollegeProspect) -> IQRead   // .scouts | .none
static func meetRead(_ prospect: CollegeProspect) -> IQRead   // .interview | .none
struct ProspectTapeCell: View { let prospect: CollegeProspect; var width: CGFloat }
struct ProspectMeetCell: View { let prospect: CollegeProspect; var width: CGFloat }

// ── UI/Scouting/ScoutingHubHeader.swift (NEW) ───────────────────────────────
/// The scroll-away header. Passed BY CLOSURE into each list surface and
/// rendered as that surface's first section. Never wraps a surface.
struct ScoutingHubHeader: View { … }

// ── Every list surface gains this initializer shape ─────────────────────────
init(… , @ViewBuilder header: @escaping () -> some View)

// ── Engine/Media/NewsGenerator.swift ────────────────────────────────────────
static func mockDraftEvent(history: [ScoutingEngine.MockDraftPick],
                           label: String,          // "Mock 1.0" | "Final Mock"
                           userBoardTop: [CollegeProspect],
                           season: Int) -> [NewsItem]
```

---

## 7. Waves

**Sequencing constraint (hard):** Wave 0 touches
`Engine/Simulation/WeekAdvancer.swift`, `Engine/Simulation/TaskGenerator.swift`
and `UI/Career/CareerShellView.swift` — **the same three files the concurrent
cap-compliance wave (task #102) owns**. This overhaul therefore **starts after
#102 has landed and been merged**, and Wave 0 rebases onto it. Waves A/B/C
touch none of those three except through Wave C (see below), which is why C is
scheduled last-in-parallel with an explicit merge order.

### Wave 0 — State machine, contracts, and one pure file move (SEQUENTIAL)

Small, blocking, no behaviour change the user can see except the stage banner.

Files:
- `Domain/Enums/DraftPrepStep.swift` **(new)**
- `Domain/Models/Career.swift` — 3 inline-default fields + `prepStep` accessor
- `Engine/Scouting/DraftClassMutator.swift` **(new)**
- `Engine/Simulation/TaskGenerator.swift` — `draftPrepChain`, stage-keyed
  required tasks for `.combine` and `.proDays`, new `TaskDestination` cases
  (`.filmStudy`, `.proDayTour`, `.workouts`, `.top30Visits`, `.mockDraft`)
- `Engine/Simulation/WeekAdvancer.swift` — stamp `career.prepStep` at the
  `.combine` / `.proDays` / `.draft` boundaries; nothing else
- `UI/Career/CareerShellView.swift` — stage-driven task locking, modelled on
  the `FreeAgencyStep` block at `:1595-1626`
- `UI/Scouting/ProDayListView.swift` **(new — pure move)**: `ProDayListView`,
  `ProDayCollegeInfo`, `ProDayResultSummary`, `FocusProspectSheet`,
  `ProDaySendScoutSheet`, `PersonalWorkoutSheet` cut verbatim out of
  `ScoutingHubView.swift:1003-2686`. **Zero edits during the move** — this
  exists solely so Waves A and B never share a file.
- `dynasty.xcodeproj/project.pbxproj` — the three new files

Acceptance:
- Build clean; a fresh career and an existing save both open the hub.
- `career.prepStep` advances `.combineReview → … → .ready` across one full
  offseason and returns to `.combineReview` on the next cycle **without any
  reset hook** (the stamp does it).
- `ScoutingHubView.swift` shrinks to ≤ 900 lines; `git show --stat` proves the
  move added no diff hunks inside the moved bodies.
- Nothing in the UI is gated yet — every tab still visible. (Gating is Wave A.)

Gate: **build + 4-season smoke unchanged** (this wave must be behaviour-neutral
in the engine).

### Wave A — Hub shell, full-page scroll, merged board, TAPE/MEET (PARALLEL)

Owns: `UI/Scouting/ScoutingHubView.swift`, `UI/Scouting/BigBoardView.swift`,
`UI/Scouting/ProspectListView.swift` (deleted), `UI/Scouting/ProspectListModels.swift`
(new), `UI/Scouting/ScoutingHubHeader.swift` (new),
`UI/Scouting/DraftPrepCard.swift`, `UI/Scouting/CombineResultsView.swift`,
`UI/Draft/Components/ProspectFog.swift`.

1. `ScoutingHubHeader` extraction + `header:` closure threaded into
   `BigBoardView` / `CombineResultsView` (§5.4). Pinned chrome ≤ 96 pt.
2. `DraftPrepCard` collapsed by default; collapsed = one-line stage progress
   ("Stage 4 of 9 — Pro Day focus · 3 of 11 slots used").
3. `ScoutingTab` rewritten: `prospects` deleted, `film` / `workouts` /
   `top30` added, `visibleTabs` driven by `career.prepStep.order`, passed
   stages read-only with a "closed" chip.
4. `ProspectListView.swift` deleted; enums moved to `ProspectListModels.swift`;
   `ProspectAttributeTab` gains `.workup`.
5. `ProspectFog.tapeRead` / `meetRead` + `ProspectTapeCell` / `ProspectMeetCell`;
   `BigBoardRowView` replaces its single `ProspectIQCell` with the two cells
   and widens the column headers accordingly.
6. Film-study stage screen = the board in `.workup` mode with the evaluate
   action promoted into the row (it currently lives two taps deep in
   `ProspectDetailView`). Spends `ScoutEvaluationBudget` **unchanged**.

Acceptance:
- Landscape iPad, `.board` tab: **≥ 10 prospect rows visible**, and scrolling
  down removes the metrics strip and prep card from the screen.
- One list surface for prospects; searching "Prospects" in the tab bar finds
  nothing.
- A prospect with an interview and two reports shows a number under `MEET`
  **and** a letter band under `TAPE`, in two columns, both tinted by
  `ProspectFog` source.
- Drag-to-reorder on the board still works (`.onMove` intact).
- Tabs above the current stage are absent; tabs below it are visible and their
  action buttons are disabled with a reason string.

### Wave B — Pro days, workouts, prospect-card ladder (PARALLEL)

Owns: `UI/Scouting/ProDayListView.swift` → split into
`UI/Scouting/ProDayTourView.swift` + `UI/Scouting/Top30VisitsView.swift` +
`UI/Scouting/WorkoutsTabView.swift` (all new; the moved file is deleted),
`UI/Scouting/ProspectDetailView.swift`, `Engine/Scouting/ScoutingEngine.swift`.

1. **Split the tab** (§5.5): pro-day tour, Top-30 visits and workouts become
   three screens with three stages.
2. **Perf** (F6): `proDaySchoolSummaries` (pure, contract §6) called once into
   `@State`; `boardRanks` built once as `[UUID: Int]` from a single JSON decode
   (copy `BigBoardView.swift:57`'s `cachedCustomRankMap` pattern); `proDayWeek`
   deleted; no computed property may touch `CareerScopedStorage`.
3. **One execution path** (F5): assignment reserves a focus slot and mutates
   nothing; the stage advance runs `executeProDays` once and shows the results
   panel. `sendScoutToProDay`'s eager `attendProDay` call is deleted.
4. **Plumbing** (F7): every mutation in these three screens goes through
   `DraftClassMutator.mutate`. Grep gate: zero remaining
   `ScoutingEngine.` calls in `UI/Scouting/` that take `&prospects` from a view
   binding.
5. **Workouts** (§5.6): `WorkoutsTabView` + `WorkoutResultSheet`;
   `conductPersonalWorkout` returns `WorkoutResult`; the
   `personalWorkoutsUsed`/10 counter and the `attendProDay` misuse are deleted;
   `career.workoutsUsed`/30 is the only economy.
6. **Ladder** (F3): `ProspectDetailView.isWorkoutWindow` becomes
   `career.prepStep.order >= DraftPrepStep.workouts.order`; the "Invite for
   Workout" button moves from the bottom of the action stack to a stage-aware
   row that reads "Available at the workout stage" until then.

Acceptance:
- Pro Day tab opens in **< 300 ms** on a 330-man class (measure with
  `SMOKE`-style `PERF|` line or Instruments Time Profiler; the acceptance
  number is "no frame over 32 ms during first render").
- Assign 3 schools → advance → results panel names those 3 schools, and the
  affected prospects' cards show a filed `.proDay` report, exact decimals, and
  `proDayCompleted` **after an app relaunch**.
- Workout on a prospect at combine time is impossible; at the workout stage it
  opens a sheet and decrements `career.workoutsUsed` exactly once.
- `grep -c personalWorkoutsUsed` → 0.

### Wave C — Mock-draft events, feed, AI symmetry (PARALLEL, merges LAST)

Owns: `Engine/Simulation/WeekAdvancer.swift`, `Engine/Media/NewsGenerator.swift`,
`Engine/Simulation/InboxEngine.swift`, `UI/Scouting/MockDraftView.swift`.

> **Merge order:** C touches `WeekAdvancer.swift`, which Wave 0 also edits.
> C branches from the Wave 0 merge commit and merges after A and B. If #102
> lands late, C rebases again — it is the only wave with that exposure.

1. Move mock moment 3 into the `.proDays` hook after the circuit; rename the
   history key to `"Post-Pro-Day"` (§5.7).
2. `NewsGenerator.mockDraftEvent` for moments 3 and 4 + an inbox letter from
   the personnel director ("here is where the league has our board").
3. Persist `mockDraftHistory` onto `Career.mockDraftHistoryData`;
   `MockDraftView` renders a Mock 1.0 / Final comparison that survives relaunch.
4. AI Top-30 pass (§5.8), deterministic on `cycleSeed`.

Acceptance:
- A 4-season smoke prints exactly **two** mock-draft feed events per offseason,
  in the right order, and the second one is the last board event before the
  draft.
- `mockDraftHistory` keys after one cycle:
  `["Mid-Season", "Combine", "Post-Pro-Day", "Pre-Draft"]`, and the same four
  render in `MockDraftView` after a cold launch.
- `draftProjection` distribution per class is unchanged (drift is zero-sum;
  assert round-1 population identical before/after the moment-3 move).
- A prospect card's "other clubs in on him" line names ≥ 1 AI club for a top-50
  prospect.

---

## 8. Risks

| Risk | Mitigation |
|---|---|
| **SwiftData migration.** Three new `Career` fields. | All inline-defaulted stored properties, never init parameters — the `lastRolloverSeason` precedent (`Career.swift`). No new `@Model` type, no relationship, no rename. Lightweight migration only. |
| **In-flight saves land mid-offseason.** A save sitting in `.proDays` reads `draftPrepStepSeason == 0` → `.combineReview` → the pro-day tab would be locked. | The stamp accessor is *floored by phase*: `max(storedStep, phase.minimumPrepStep)`. A save in `.proDays` reads at least `.proDayFocus`. One line, in the accessor, so no call site can forget it. |
| **Moving mock moment 3 changes smoke numbers.** | Expected and accepted; §9 re-baselines. The invariant that must NOT move is the zero-sum `draftProjection` distribution — asserted in Wave C's acceptance. |
| **Wave A's `header:` closure re-renders the whole list.** | The header is a `Section` of one row; SwiftUI diffs it independently. Guard with the existing `refreshCachedBoard` pattern — the header must not read any uncached computed property (this is F6's lesson applied prophylactically). |
| **File-ownership collision with #102.** | Wave 0 and Wave C are the only waves touching `WeekAdvancer`/`TaskGenerator`/`CareerShellView`; both are explicitly sequenced after #102's merge. A and B are untouched by it. |
| **Deleting `ProspectListView` orphans a task destination.** | `TaskDestination.prospectList` re-points to `.bigBoard`; `scoutingPendingTab == "prospects"` maps to `"board"` in the hub's pending-tab switch (`ScoutingHubView.swift:141-146`). Both are one-line, both in Wave A. |

## 9. Gates battery

Run in order; every gate must be green before the wave is called done.

1. **Build** — `xcodebuild -project dynasty/dynasty.xcodeproj -scheme dynasty
   -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)'` — zero
   warnings introduced. (Never the reserved simulator
   `049C7295-7294-48E8-8B6B-D31CE41E4353`.)
2. **Balance harness — `career`** (`tools/balance-harness/run.sh career`):
   development/retirement bands unchanged. This overhaul must not move a single
   development number; any drift is a bug in the wave, not a re-baseline.
3. **Balance harness — `draftclass`**: class shape, projection distribution,
   consensus error, 80+ population all inside their existing bands. Wave C's
   moment-3 move is the only legitimate source of movement here, and only in
   the *timing* of drift, never in the distribution.
4. **4-season smoke** (`MultiSeasonSmokeTest.run(seasons: 4)`): completes with
   no watchdog trip; `SMOKE: diag draft` lines present for all 4 seasons;
   new assertion `SMOKE: diag prep season=N step=Ready evals=… interviews=…
   proDaySchools=… workouts=… top30=…` proves the pipeline ran headless.
   Re-baseline mock-draft-dependent lines once, in Wave C, and record the diff.
5. **On-sim wizard walkthrough** (the acceptance ritual, driven with
   `dynasty-sim-qa` semantic UI automation): from `.combine` entry to the draft
   room — review combine → order film study → interviews → advance → choose 3
   pro-day schools → advance (tour runs) → workouts + modal → read Mock 1.0 →
   Top-30 visit → read Final Mock → draft room unlocks. Screenshot every stage.
   Explicit checks: **≥ 10 rows landscape**, header scrolls away, TAPE and MEET
   in separate columns, pro-day results visible on a prospect card **after
   force-quit and relaunch**, no tab above the current stage, every passed
   stage still openable and read-only.
6. **Grep gates** (cheap, run in CI-ish fashion):
   `personalWorkoutsUsed` → 0 hits · `ProspectListView` → 0 hits ·
   `proDayWeek` → 0 hits · `&prospects` inside `UI/Scouting/` → 0 hits ·
   `ProspectIQCell` outside the draft room → 0 hits.
