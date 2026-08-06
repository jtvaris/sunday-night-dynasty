import SwiftUI
import SwiftData

// MARK: - Film Study, as a batch instrument (#119)
//
// The film-study stage shipped as the Big Board in work-up mode with a $20K
// button welded onto every row. That is a correct *economy* and the wrong
// *shape*: ordering tape on the fifteen men at the top of a board meant fifteen
// separate taps on fifteen separate rows of a 350-row table, each one silently
// spending a slot and a fee, with no running total, no way to see what the
// order would cost before committing it, and no report at the end — the band
// just quietly narrowed somewhere behind the user.
//
// The interview room already solved exactly this problem: pick the men, read
// what the order costs, run it once, read the report. This screen is that same
// surface over the evaluation ledger, and it is deliberately built from the same
// parts as `InterviewSelectionView` so the two stages feel like one process.
//
// ## What is reused, exactly
//
// Nothing about the economy is new. Every number below comes from
// `ScoutEvaluationBudget` — 25 slots a cycle, $15/25/40K rising per CHARGEABLE
// report (the inherited "Previous Staff" baseline neither prices nor caps,
// #122), three own reports a man, cycle-stamped so it resets with the class —
// and the three
// career-scoped keys this view writes are the same three the prospect card
// (`ProspectDetailView.recordEvaluation`) and the board row
// (`BigBoardView.orderFilmStudy`) write:
//
//   * `scoutEvaluationsUsed`  — slots spent this cycle
//   * `scoutEvaluationSpend`  — thousands of the scouting pot committed
//   * `scoutEvaluationCycle`  — the season those two belong to
//
// A fourth key is read-only here: `combineTripSpend`, because the trip and the
// evaluations draw on the same pot and the budget quoted on this screen has to
// be the number the hub's budget tile shows.
//
// `DraftPrepProgress.filmReportsFiled` reads the first and third of those keys
// to decide whether the stage is *worked*, so getting a key wrong here would not
// merely mis-price an order — it would silently spend the owner's money forever
// and leave the stage's required task red. The strings are copied verbatim
// rather than derived.
//
// ## What this screen deliberately does NOT do
//
// It does not pick a scout per prospect. The card keeps its picker — one man,
// one considered choice — but a batch of twenty is not twenty decisions, it is
// one, so the department puts its best eye on the whole order and the report
// says whose eye it was. That is the same call `BigBoardView.assignedScout`
// makes for its row button, and the same shape as "Interviews run by OC X".

/// Orders film study on a batch of prospects, then shows what the batch bought.
///
/// - Parameters (via the memberwise init):
///   - `career`: the open save — supplies the phase, the season stamp and the
///     club whose scouts and pot are spent.
///   - `positionFilter`: the hub's ONE position filter. This screen must not
///     grow chips of its own: `ScoutingHubView.positionFilterAppliesToCurrentTab`
///     already draws them above the film tab, and a second set over the same
///     list is the exact bug that pass deleted.
///   - `canAct`: `DraftPrepProgress.canAct(.filmStudy)`. The one gate every
///     stage screen asks, of the same struct, so a process-bar cell that invites
///     a tap can never land on a screen whose buttons are dead.
///   - `board`: the work-up board this tab used to be, kept one tap away.
///     `DraftPrepStep.filmStudy.actionLabel` is literally "Order film study on
///     your board", and the board's columns are the ones that answer *which*
///     men still need work — so the route is preserved as a secondary surface
///     rather than deleted.
struct FilmStudySelectionView<Board: View>: View {

    let career: Career
    @Binding var positionFilter: ProspectPositionFilter
    /// Whether the club may spend an evaluation slot right now. Defaults to
    /// `true` so a preview or a future non-hub entry point is not silently dead.
    var canAct: Bool = true
    /// The Big Board in work-up mode, rendered when the user asks for it.
    let board: () -> Board

    @Environment(\.modelContext) private var modelContext

    // MARK: - Loaded state

    @State private var prospects: [CollegeProspect] = []
    @State private var scouts: [Scout] = []
    @State private var scoutingBudget: Int = 4_000
    @State private var isLoading: Bool = true

    // MARK: - Derived caches
    //
    // Everything below is a pure function of `prospects` + `positionFilter`, and
    // every one of them is O(n) or worse over a ~350-man class. They are cached
    // rather than computed because this screen re-evaluates its body on every
    // checkbox tap: a `selectedSpend` that re-sorted the class, called once per
    // visible row from `canAdd`, is an O(n² log n) scroll. `refreshList()` is
    // the ONE writer — call it whenever the class or the filter moves.

    /// The filtered class in consensus board order.
    @State private var orderedCache: [CollegeProspect] = []
    /// `computeRecommended(from:)`, cached.
    @State private var recommendedCache: [CollegeProspect] = []
    /// Everyone not in `recommendedCache`, cached.
    @State private var otherCache: [CollegeProspect] = []
    /// Next-report price per prospect. Keyed by ID so the selection footer costs
    /// O(selected) — at most 25 — instead of O(class).
    @State private var costByID: [UUID: Int] = [:]
    /// Chargeable reports per prospect, from the same one walk that prices them.
    ///
    /// `scoutingReports` is a DECODED stored property: every `chargeableReports`
    /// call pays for a JSON decode. The row asked for it three times over
    /// (`reportsOnFile`, `hasRoom`, `nextReportCost` inside `canAdd`) and the
    /// work-up column block asks again, so the count is cached beside the price
    /// and every reader goes through ``reportsOnFile``.
    @State private var reportsByID: [UUID: Int] = [:]
    /// The cycle's filed reports, rebuilt from what is stamped on the prospects.
    @State private var filedCache: [FilmStudyReportEntry] = []
    /// The lowest next-report price anywhere in the class that still has room.
    /// `nil` when every man is at three reports. Drives ``cycleIsSpent``.
    @State private var cheapestWorkableCost: Int?

    // MARK: - Screen state

    @State private var selectedIDs: Set<UUID> = []
    /// Which block of columns the list renders, driven by the shared mode chips.
    ///
    /// Opens on `.workup` because that is the block this stage is about — who
    /// have I not put tape on — and it is the same block the tab's Board surface
    /// opens on (`initialAttributeTab: .workup`), so switching surfaces does not
    /// switch the question.
    @State private var mode: ProspectAttributeTab = .workup
    /// The one sheet this screen can have open. See ``FilmStudySheet``.
    @State private var activeSheet: FilmStudySheet?
    /// Which of the tab's two surfaces is showing. The order screen is primary;
    /// the board is the secondary read the stage copy points at.
    @State private var surface: Surface = .order
    /// Set when the user explicitly opens the saved report while slots remain.
    @State private var viewingFiledReport: Bool = false

    @ObservedObject private var userGradeStore = UserProspectGradeStore.shared

    /// The tab's two surfaces.
    private enum Surface {
        /// The batch order screen — this tab's primary content.
        case order
        /// The work-up board, kept because the stage's own action label promises
        /// it and because its columns say what work is still missing.
        case board
    }

    /// The screen's single sheet slot.
    ///
    /// An enum rather than a boolean even though there is one case today: the
    /// hub, the prospect card and the pro-day tour each shipped with two stacked
    /// `.sheet(isPresented:)` on one node, SwiftUI honoured only the last, and
    /// three separate buttons opened the wrong sheet or nothing at all. One
    /// `item:` slot makes "two sheets at once" unrepresentable.
    enum FilmStudySheet: Identifiable {
        /// What a just-run batch filed.
        case batchReport(FilmStudyBatch)

        var id: String {
            switch self {
            case .batchReport: return "batchReport"
            }
        }
    }

    // MARK: - Evaluation ledger (career-scoped, cycle-stamped)
    //
    // Copied key-for-key from `ProspectDetailView`. `DraftPrepProgress.Key` owns
    // two of the three names; the spend key has no constant there, so it is
    // spelled the same way the other three screens spell it.

    @CareerScopedStorage(DraftPrepProgress.Key.evaluationsUsed)
    private var evaluationsUsedStored: Int = 0
    @CareerScopedStorage("scoutEvaluationSpend")
    private var evaluationSpendStored: Int = 0
    @CareerScopedStorage(DraftPrepProgress.Key.evaluationCycle)
    private var evaluationCycleStored: Int = 0
    /// Read only — the combine trip and the evaluations share one pot.
    @CareerScopedStorage("combineTripSpend")
    private var combineTripSpend: Int = 0

    private var evaluationsUsed: Int {
        ScoutEvaluationBudget.thisCycle(
            evaluationsUsedStored,
            stampedSeason: evaluationCycleStored,
            currentSeason: career.currentSeason
        )
    }

    private var evaluationSpend: Int {
        ScoutEvaluationBudget.thisCycle(
            evaluationSpendStored,
            stampedSeason: evaluationCycleStored,
            currentSeason: career.currentSeason
        )
    }

    private var evaluationSlotsLeft: Int {
        max(0, ScoutEvaluationBudget.slotsPerCycle - evaluationsUsed)
    }

    /// What is left of the owner's scouting pot, by the same arithmetic
    /// `ScoutingHubView.remainingScoutingBudget` does — so the number in this
    /// footer and the number on the hub's budget tile are the same money.
    private var remainingScoutingBudget: Int {
        scoutingBudget
            - scouts.reduce(0) { $0 + $1.salary }
            - combineTripSpend
            - evaluationSpend
    }

    // MARK: - The department

    /// The eye the department puts on the whole order.
    ///
    /// Best raw accuracy on staff, full stop. The board row's `assignedScout`
    /// weights a position specialist ahead of him, which is right for ONE man;
    /// a batch spans every position group, so a per-prospect specialist race
    /// would name a different scout on every card of one report.
    private var leadScout: Scout? {
        scouts.max { $0.accuracy < $1.accuracy }
    }

    /// "Scout Dan Reeves" — the man the report is filed by. `nil` until the
    /// department has loaded, so the header does not flash a placeholder.
    private var leadScoutName: String? {
        leadScout.map { "Scout \($0.fullName)" }
    }

    /// `ProspectDetailView.currentScoutingPhase`, copied so a report ordered in
    /// a batch carries the same confidence as one ordered from a card.
    private var currentScoutingPhase: ScoutingPhase {
        switch career.currentPhase {
        case .combine:                                      return .combine
        case .freeAgency, .proDays, .draft:                 return .proDay
        case .otas, .trainingCamp, .preseason, .rosterCuts: return .personalWorkout
        default:                                            return .collegeSeason
        }
    }

    /// "Combine · 2027" — phase plus season, so a report read back in April
    /// still says when the tape was ground.
    private var occasionLabel: String {
        "\(currentScoutingPhase.displayName) \u{00B7} " + String(career.currentSeason)
    }

    // MARK: - The list

    /// Everyone the filter shows, in consensus board order.
    ///
    /// Ordered by `draftProjection` — public, media information — and never by
    /// anything derived from `trueOverall`. Sorting a list by the generator's own
    /// number is the quietest disclosure channel there is: nothing prints, the
    /// unscouted stud just happens to be at the top.
    private func computeOrderedProspects() -> [CollegeProspect] {
        prospects
            .filter { positionFilter.matches($0.position) }
            .sorted {
                let a = $0.draftProjection ?? 99
                let b = $1.draftProjection ?? 99
                if a != b { return a < b }
                return $0.lastName < $1.lastName
            }
    }

    /// Reports already on a man, counted the way the price ladder counts them.
    ///
    /// This is `scoutingReports.count` — the inherited "Previous Staff" freebie
    /// INCLUDED — because that is the count `ScoutEvaluationBudget.cost` and
    /// `maxReportsPerProspect` read. Showing a different denominator here than
    /// the one the money uses would mean a row reading "0/3" over a $35K price.
    /// Whether THIS regime has ordered tape on him is a different question, and
    /// it is answered by ``hasOwnFilmReport`` in the filed-report list.
    /// Reads the cache `refreshList` builds, and falls back to the live decode
    /// for a man the cache has not seen (a prospect outside the filtered class).
    private func reportsOnFile(_ prospect: CollegeProspect) -> Int {
        reportsByID[prospect.id] ?? ScoutEvaluationBudget.chargeableReports(prospect)
    }

    private func hasRoom(_ prospect: CollegeProspect) -> Bool {
        reportsOnFile(prospect) < ScoutEvaluationBudget.maxReportsPerProspect
    }

    /// Thousands the NEXT report on this man costs. Rising: the first look is a
    /// cheap tape grade, the third is a cross-check trip.
    private func nextReportCost(_ prospect: CollegeProspect) -> Int {
        ScoutEvaluationBudget.cost(existingReports: reportsOnFile(prospect))
    }

    /// A tape report THIS regime ordered — the same predicate the prospect
    /// card's Film Study pill uses. The pre-scout "Previous Staff" rows are
    /// inherited intel and the workout files its own `.personalWorkout` report,
    /// so neither may claim work this staff paid for.
    private func hasOwnFilmReport(_ prospect: CollegeProspect) -> Bool {
        prospect.scoutingReports.contains {
            $0.scoutName != "Previous Staff" && $0.phase != .personalWorkout
        }
    }

    /// A man this club's board actually tracks — marked, or given a user grade.
    private func isOnUserBoard(_ prospect: CollegeProspect) -> Bool {
        prospect.isMarked || userGradeStore.grade(for: prospect.id) != nil
    }

    /// The men "Select All Recommended" fills from, in the list's own ranking.
    ///
    /// The user's board first, because film study is the instrument you point at
    /// men you are already interested in. A brand-new board tracks nobody and
    /// "the button did nothing" is the worse failure, so an empty board falls
    /// back to the top of the consensus order — the same fallback the hub's
    /// combine trip makes for the same reason.
    private func computeRecommended(from ordered: [CollegeProspect]) -> [CollegeProspect] {
        let withRoom = ordered.filter(hasRoom)
        let onBoard = withRoom.filter(isOnUserBoard)
        if !onBoard.isEmpty { return onBoard }
        return Array(withRoom.prefix(DraftPrepProgress.filmStudyThreshold * 2))
    }

    // MARK: - Selection maths
    //
    // The cap is TWO limits at once, and both of them move as the selection
    // changes: the cycle's remaining slots, and what the pot can afford given
    // that every pick carries its OWN escalating price. Deselecting frees both.

    /// The men in the order, in consensus board order.
    ///
    /// Read off the WHOLE class rather than the filtered list: a selection made
    /// under the QB chip is still an order after the user tabs to the corners,
    /// and filing only what the current filter happens to show would charge for
    /// men it never scouted.
    private var selectedProspects: [CollegeProspect] {
        prospects
            .filter { selectedIDs.contains($0.id) }
            .sorted {
                let a = $0.draftProjection ?? 99
                let b = $1.draftProjection ?? 99
                if a != b { return a < b }
                return $0.lastName < $1.lastName
            }
    }

    /// Thousands this order would cost, priced per man at his own next-report
    /// tier. Reads the cached price map, so the footer and every row's
    /// affordability test cost O(selected) rather than O(class).
    private var selectedSpend: Int {
        selectedIDs.reduce(0) { $0 + (costByID[$1] ?? 0) }
    }

    private var slotsLeftAfterOrder: Int {
        max(0, evaluationSlotsLeft - selectedIDs.count)
    }

    private var budgetLeftAfterOrder: Int {
        remainingScoutingBudget - selectedSpend
    }

    /// Whether one more man fits inside both limits.
    ///
    /// `canAct` is part of the answer (#119 review F6): without it the shut
    /// stage handed out a fully live order surface — 25 ticks, a $700K footer
    /// — and only the run bar at the bottom admitted nothing could be bought.
    private func canAdd(_ prospect: CollegeProspect) -> Bool {
        guard canAct else { return false }
        guard hasRoom(prospect) else { return false }
        guard selectedIDs.count < evaluationSlotsLeft else { return false }
        return selectedSpend + nextReportCost(prospect) <= remainingScoutingBudget
    }

    private func toggle(_ prospect: CollegeProspect) {
        if selectedIDs.contains(prospect.id) {
            selectedIDs.remove(prospect.id)
        } else if canAdd(prospect) {
            selectedIDs.insert(prospect.id)
        }
    }

    /// Fills the selection from `recommendedProspects`, in order, stopping at
    /// whichever limit binds first.
    ///
    /// Walked one man at a time rather than `prefix(slotsLeft)` because the
    /// prices are not uniform: three men at $55K cost more than three at $20K,
    /// so the budget can bind before the slots do — and a man the pot cannot
    /// afford must not block a cheaper one behind him.
    private func selectAllRecommended() {
        for prospect in recommendedCache where !selectedIDs.contains(prospect.id) {
            guard selectedIDs.count < evaluationSlotsLeft else { break }
            guard canAdd(prospect) else { continue }
            selectedIDs.insert(prospect.id)
        }
    }

    // MARK: - Gate
    //
    // Every blocked case carries the sentence the run bar prints. A dead control
    // that does not say why is the bug this whole wave exists to stop repeating.

    /// Why the order cannot be placed, or `nil` when it can.
    private var blockedReason: String? {
        if !canAct {
            return "Film study opens at that stage"
        }
        if !ScoutEvaluationBudget.isWindowOpen(career.currentPhase) {
            return ScoutEvaluationBudget.windowHint(for: career.currentPhase)
        }
        if scouts.isEmpty {
            return "Hire a scout before you order tape"
        }
        if evaluationSlotsLeft == 0 {
            return "All \(ScoutEvaluationBudget.slotsPerCycle) evaluations are spent this cycle"
        }
        if selectedIDs.isEmpty {
            return "Select Prospects to Put on Tape"
        }
        // The ledger can move UNDER a standing selection — the combine trip
        // and the card's own order both spend this pot — so the bar must
        // re-answer against live money, not against what was true at tick
        // time. Without these the bar promised 12 reports, filed 7, and said
        // nothing about the other five (#119 review F4).
        if selectedIDs.count > evaluationSlotsLeft {
            return "\(selectedIDs.count) selected — only \(evaluationSlotsLeft) evaluation\(evaluationSlotsLeft == 1 ? "" : "s") left"
        }
        if selectedSpend > remainingScoutingBudget {
            return "Order costs $\(selectedSpend)K — only $\(remainingScoutingBudget)K left"
        }
        return nil
    }

    /// Whether the cycle has nothing left to buy: no slots, or nothing the pot
    /// can afford that is not already at three reports.
    ///
    /// Answered from `cheapestWorkableCost` rather than by walking the class,
    /// because this is read on every body pass and `scoutingReports` is a decoded
    /// stored property — 350 decodes per checkbox tap is a stutter nobody can
    /// explain later. The cached figure only moves when the class does, and the
    /// budget it is compared against only moves when a batch is filed, which
    /// rebuilds the cache.
    private var cycleIsSpent: Bool {
        if evaluationSlotsLeft == 0 { return true }
        guard let cheapest = cheapestWorkableCost else { return true }
        return cheapest > remainingScoutingBudget
    }

    // MARK: - Filed reports (the steady state)

    /// Every man this regime has tape on, as report entries.
    ///
    /// Rebuilt from what is STAMPED ON THE PROSPECTS rather than remembered
    /// across a batch, so the summary survives a tab switch and a relaunch
    /// exactly like the interview tab's saved report does. Cached only because
    /// the walk is O(class); `refreshList()` rebuilds it.
    private func computeFiledEntries() -> [FilmStudyReportEntry] {
        prospects
            .filter(hasOwnFilmReport)
            .compactMap { prospect -> FilmStudyReportEntry? in
                guard let report = prospect.scoutingReports.last(where: {
                    $0.scoutName != "Previous Staff" && $0.phase != .personalWorkout
                }) else { return nil }
                return FilmStudyReportEntry(
                    prospectName: prospect.fullName,
                    position: prospect.position,
                    college: prospect.college,
                    scoutName: report.scoutName,
                    // No "before" for a saved report: the band it replaced is not
                    // stored anywhere, and inventing one would be a fabrication
                    // dressed as intel.
                    bandBefore: nil,
                    bandAfter: Self.scoutBand(prospect),
                    strengths: Self.nonEmpty(report.strengthNotes),
                    weaknesses: Self.nonEmpty(report.weaknessNotes),
                    personality: Self.nonEmpty(report.personalityNotes)
                )
            }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else {
                VStack(spacing: 0) {
                    header
                    Divider().overlay(Color.surfaceBorder.opacity(0.6))

                    switch surface {
                    case .board:
                        board()
                    case .order:
                        orderSurface
                    }
                }
            }
        }
        // ONE sheet modifier, over an `item:` slot.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case let .batchReport(batch):
                NavigationStack {
                    ZStack {
                        Color.backgroundPrimary.ignoresSafeArea()
                        FilmStudyBatchReportView(batch: batch)
                    }
                    .navigationTitle("Film Study Report")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { activeSheet = nil }
                        }
                    }
                }
            }
        }
        .task {
            loadDepartment()
            refreshList()
            isLoading = false
        }
        // The hub owns the position chips, so the filter moves from OUTSIDE this
        // view and the cached lists have to follow it.
        .onChange(of: positionFilter) { _, _ in refreshList() }
        // The Board surface files reports of its own (`BigBoardView
        // .orderFilmStudy` writes the same ledger), so coming back to the
        // order surface on stale caches mis-priced every row the board had
        // already bought (#119 review F1).
        .onChange(of: surface) { _, newSurface in
            if newSurface == .order { refreshList() }
        }
    }

    private var loadingView: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.5)
                    .tint(Color.accentGold)
                Text("Loading Film Study...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// The order screen, plus the two states it collapses into.
    @ViewBuilder
    private var orderSurface: some View {
        if viewingFiledReport && !filedCache.isEmpty {
            // Explicitly requested while slots remain.
            savedReport(dismissTitle: "Back to Ordering") {
                viewingFiledReport = false
                refreshList()
            }
        } else if cycleIsSpent && !filedCache.isEmpty {
            // STEADY STATE. The cycle is bought out and the report IS this tab,
            // so there is no run bar and no "complete" CTA: dismissing would
            // re-render this same screen, and a gold call-to-action weeks after
            // the stage closed reads as a required action the user is failing
            // (#118, the same defect the interview tab just had removed).
            savedReport(dismissTitle: nil, onDismiss: nil)
        } else {
            selectionList
        }
    }

    private func savedReport(dismissTitle: String?, onDismiss: (() -> Void)?) -> some View {
        VStack(spacing: 0) {
            FilmStudyBatchReportView(
                batch: FilmStudyBatch(
                    entries: filedCache,
                    scoutName: leadScoutName ?? "your department",
                    occasion: occasionLabel,
                    totalSpend: evaluationSpend,
                    slotsLeft: evaluationSlotsLeft
                ),
                isSavedReport: true
            )

            if let dismissTitle, let onDismiss {
                Button(action: onDismiss) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text(dismissTitle)
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentGold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // The way OUT of a bought-out cycle. Without it the steady state is
            // a dead end: the report is the tab, the run bar is gone, and the
            // only forward control is a bar the hub pins on a DIFFERENT tab.
            advanceStageButton
        }
    }

    // MARK: - Stage advance
    //
    // The stage transition ONLY — never the phase advance, which belongs to the
    // calendar and to `ScoutingHubView`.
    //
    // Shaped exactly like `WorkoutsTabView.advanceStage`: gated on the same
    // `canAct` the whole screen is, writes `Career.advancePrepStep(to:)` with
    // the successor `DraftPrepStep.next` names, saves, and refreshes.

    /// Whether the hub is already pinning `DraftPrepAdvanceBar` under this tab.
    ///
    /// `ScoutingHubView.showsAdvanceBar` draws it whenever the selected tab IS
    /// the current stage's tab, and film study is an `.advance` stage — so a
    /// club standing in `.filmStudy` already has that control a few points below
    /// this one. Two gold bars over one transition is #118 wearing a different
    /// label, so this one stands down when the hub's is up.
    private var hubPinsAdvanceBar: Bool { career.prepStep == .filmStudy }

    /// The stage this button writes, or `nil` when there is nothing to write.
    ///
    /// Two clamps, and both of them are the pipeline's own rules rather than
    /// this screen's:
    ///
    /// * **The season is a ceiling.** `SeasonPhase.maximumPrepStep` is the
    ///   furthest stage a club standing in this phase may hold, and in combine
    ///   week that is `.filmStudy` itself — the pro-day circuit is not on the
    ///   calendar yet, which is exactly why `ScoutingStageGate` blocks the hub's
    ///   own bar there. So in the combine the advance lands ON film study (the
    ///   club is now standing in the stage it has been working, and the hub
    ///   takes the transition from here); in the pro-day window it lands on
    ///   `.filmStudy.next`.
    /// * **It has to move something.** `Career.advancePrepStep` never lowers, so
    ///   a target at or behind the club's stage is a dead control — and a dead
    ///   control that does not say why is the bug this whole wave is about.
    ///   `nil` hides the button instead of greying it.
    private var advanceTarget: DraftPrepStep? {
        guard let next = DraftPrepStep.filmStudy.next else { return nil }
        let ceiling = career.currentPhase.maximumPrepStep
        let target = next.order <= ceiling.order ? next : ceiling
        return target.order > career.prepStep.order ? target : nil
    }

    /// Shown only when the club may act in this stage (the same
    /// `DraftPrepProgress.canAct(.filmStudy)` every control on this screen is
    /// gated on), the cycle has nothing left to buy, the hub is not already
    /// drawing the transition, and the write would actually move the pipeline.
    ///
    /// `cycleIsSpent` is what makes this an *ending* rather than a shortcut: it
    /// is true in both of the tab's dead ends — the bought-out steady state, and
    /// the list whose run bar can only say "nothing you can still afford". While
    /// slots and money remain there is work to do here and the run bar is the
    /// thing to look at.
    ///
    /// #fleet review F6: **and the club has to have reached this stage.** The
    /// calendar clamp in `advanceTarget` lands on `.filmStudy` itself in combine
    /// week, so a club still standing in `.interviews` cleared `target.order >
    /// prepStep.order` and was offered "Complete Film Study — Advance" — a
    /// button that moves him INTO the stage while claiming he has finished it,
    /// with 50-odd interview slots still unspent behind him.
    private var showsAdvanceStage: Bool {
        canAct
            && career.prepStep.order >= DraftPrepStep.filmStudy.order
            && cycleIsSpent && !hubPinsAdvanceBar && advanceTarget != nil
    }

    @ViewBuilder
    private var advanceStageButton: some View {
        if showsAdvanceStage, let target = advanceTarget {
            VStack(alignment: .leading, spacing: 4) {
                // When the calendar clamped the target, say so: the user is
                // being moved onto film study rather than past it, and the
                // reason is the season, not anything he failed to do.
                //
                // #fleet review F18: the sentence comes from
                // `DraftPrepProgress.opensSentence` now. The local copy said
                // "the pro-day circuit opens with the pro-day window", which
                // tells a club standing in combine week nothing it did not
                // already know — free agency runs between the two, and naming it
                // is the whole point of that table.
                if target == .filmStudy {
                    Text("\(DraftPrepProgress.opensSentence(for: .proDayFocus)) This closes the combine block.")
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button { advanceStage() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Complete Film Study \u{2014} Advance")
                                .font(.subheadline.weight(.bold))
                            Text(filedCache.isEmpty
                                 ? "No tape ordered this cycle \u{2014} \(target.displayName) next"
                                 : (filedCache.count == 1
                                    ? "1 report filed \u{2014} \(target.displayName) next"
                                    : "\(filedCache.count) reports filed \u{2014} \(target.displayName) next"))
                                .font(.caption)
                                .opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(12)
                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Moves the club on to \(target.displayName)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    /// The STAGE transition, and only that — the phase advance belongs to the
    /// calendar and to the hub.
    ///
    /// Every guard the button applied is re-applied here, exactly as
    /// `WorkoutsTabView.advanceStage` re-applies its own: `prepStep` is a floor
    /// the whole pre-draft UI reads, and writing a pro-day stage in combine week
    /// would open five tabs the season has not reached.
    private func advanceStage() {
        guard canAct, let target = advanceTarget else { return }
        career.advancePrepStep(to: target)
        try? modelContext.save()
        refreshList()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("FILM STUDY")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)

                Spacer()

                Text("\(evaluationsUsed)/\(ScoutEvaluationBudget.slotsPerCycle) used")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(evaluationSlotsLeft == 0 ? Color.danger : Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.backgroundTertiary))

                surfacePicker
            }

            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.accentGold)
                Text("Reveals: overall band \u{00B7} all eight mental grades \u{00B7} every position skill \u{00B7} strengths, weaknesses and a personality read")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let leadScoutName {
                Text("Sessions run by \(leadScoutName) \u{00B7} \(occasionLabel)")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }

            if surface == .order { selectionProgress }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// The secondary route to the board.
    ///
    /// Not a link away to another tab: the stage's own action label is "Order
    /// film study on your board", and the work-up columns are the read that says
    /// which men still need tape. It is the SECOND surface of this tab, and the
    /// order screen is the first thing the user lands on.
    private var surfacePicker: some View {
        HStack(spacing: 2) {
            surfaceChip(.order, label: "Order", icon: "checklist")
            surfaceChip(.board, label: "Board", icon: "list.number")
        }
        .padding(2)
        .background(Capsule().fill(Color.backgroundTertiary))
    }

    private func surfaceChip(_ target: Surface, label: String, icon: String) -> some View {
        let isSelected = surface == target
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { surface = target }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9))
                Text(label).font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(isSelected ? Color.accentGold : Color.clear))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(target == .order ? "Order tape on prospects" : "Open the work-up board")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The running footer: what is selected, what it costs, and what is left of
    /// both limits AFTER the order. Deselecting a man gives the numbers back.
    private var selectionProgress: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(selectedIDs.count) selected \u{00B7} $\(selectedSpend)K total")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(selectedIDs.isEmpty ? Color.textSecondary : Color.textPrimary)

                Spacer()

                Text("\(slotsLeftAfterOrder) slots left \u{00B7} $\(budgetLeftAfterOrder)K budget left")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(budgetLeftAfterOrder < 0 ? Color.danger : Color.textTertiary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(selectedIDs.isEmpty ? Color.textTertiary : Color.accentGold)
                        .frame(
                            width: evaluationSlotsLeft > 0
                                ? geo.size.width * CGFloat(selectedIDs.count) / CGFloat(evaluationSlotsLeft)
                                : 0,
                            height: 6
                        )
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Selection list

    private var selectionList: some View {
        VStack(spacing: 0) {
            listActionBar

            // The board's view modes, on the order screen. This list used to be
            // one frozen five-column set — POS / NAME / TAPE / RPTS / NEXT —
            // while the board one tap away could be asked five different
            // questions about the same men, which made the batch surface the
            // information-poor way to do the same job.
            //
            // The hub owns the position chips (`showsPositionChips: false`), so
            // the binding here is inert: passing a live one would be a second
            // position filter over a list the hub already scopes.
            ProspectListControls(
                positionFilter: .constant(.all),
                mode: $mode,
                modes: ProspectAttributeTab.allCases,
                showsPositionChips: false,
                background: Color.backgroundTertiary.opacity(0.4)
            )

            ScrollView {
                LazyVStack(spacing: 0) {
                    tableHeader

                    if !recommendedCache.isEmpty {
                        sectionHeader(
                            "RECOMMENDED",
                            subtitle: recommendedCache.contains(where: isOnUserBoard)
                                ? "The men on your board who still have room for a report"
                                : "Top of the consensus board \u{2014} mark men to make this your own"
                        )
                        ForEach(recommendedCache) { prospect in
                            prospectRow(prospect)
                            Divider().overlay(Color.surfaceBorder.opacity(0.3))
                        }
                    }

                    sectionHeader("ALL PROSPECTS", subtitle: nil)
                    ForEach(otherCache) { prospect in
                        prospectRow(prospect)
                        Divider().overlay(Color.surfaceBorder.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16)
            }

            runBar

            // "Nothing more affordable": the slots or the pot are gone but no
            // report has been filed this cycle, so the steady-state report is
            // not what renders — the list is, with a run bar that can only say
            // no. That is the other dead end this stage had, and it gets the
            // same way out. (`showsAdvanceStage` carries the `cycleIsSpent`
            // test, so this draws nothing while there is still tape to buy.)
            advanceStageButton
        }
    }

    /// The mass-selection row, in the same place and the same style as the
    /// interview tab's. Ordering tape on fifteen men one checkbox at a time is
    /// the chore this whole screen exists to delete; leaving the *selection*
    /// as fifteen taps would have moved the chore rather than removed it.
    private var listActionBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "film")
                .font(.system(size: 11))
                .foregroundStyle(Color.accentGold)
            Text("\(evaluationSlotsLeft)/\(ScoutEvaluationBudget.slotsPerCycle) evaluations remaining")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(evaluationSlotsLeft < 5 ? Color.danger : Color.textPrimary)

            Spacer()

            // Surfaces the reports already filed so the "Order film study"
            // dashboard task can be reviewed mid-cycle, before the slots run out.
            if !filedCache.isEmpty {
                Button {
                    viewingFiledReport = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 9))
                        Text("View Report (\(filedCache.count))")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentGold.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            if !recommendedCache.isEmpty {
                Button {
                    selectAllRecommended()
                } label: {
                    Text("Select All Recommended")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentGold.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Fills the order from the recommended list until the slots or the budget run out")
            }

            if !selectedIDs.isEmpty {
                Button {
                    selectedIDs.removeAll()
                } label: {
                    Text("Clear Selection")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.backgroundTertiary))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(Color.backgroundTertiary.opacity(0.4))
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .tracking(0.5)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.top, 4)
    }

    /// Column labels. The leading four and the trailing block are PINNED — the
    /// checkbox, the man, and what a report on him costs are the same question
    /// in every mode — and the block between them follows the mode chips. RPTS
    /// is the one exception: the Work-up block prints that count itself, so the
    /// pinned copy stands down there (#fleet review F19a).
    private var tableHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 22)
            Text("POS").frame(width: 36, alignment: .center)
            // Portrait column: unlabelled, but reserved so the header keeps
            // matching the row (30 pt `PersonFaceView` + 6 pt leading padding).
            Color.clear.frame(width: 36)
            Text("NAME")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 6)

            // `leadsWithScoutBand` must match the row's context exactly or the
            // labels slide one column out of line — see `columnContext`.
            ProspectColumns.headers(mode: mode, context: ProspectColumnContext(leadsWithScoutBand: true))

            Text("TAPE").frame(width: 46, alignment: .center)
            // #fleet review F19a: the Work-up block opens with the same n/3, so
            // in that mode the pinned column would print the count twice on
            // every row. The block owns it there; this column covers the others.
            if mode != .workup {
                Text("RPTS").frame(width: 38, alignment: .center)
            }
            Text("NEXT").frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .heavy))
        .foregroundStyle(Color.textTertiary)
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Row

    /// What a column block needs that lives on this SCREEN rather than on the
    /// prospect.
    ///
    /// `knowsSchemeFit` / `knowsNeeds` are both false: the order screen loads
    /// scouts and a budget, not coordinators and a roster, and a FIT cell that
    /// defaulted to "Fair" here would be a fabricated verdict rather than a
    /// missing one. `reportCount` is the cached chargeable count so the work-up
    /// block's RPT cell and this row's own RPTS column cannot print two
    /// different numbers for the same man.
    ///
    /// `leadsWithScoutBand` is on: this screen asks the user to spend money on a
    /// man, and what his own department already has him at is the first thing he
    /// needs to read. The list draws no OVR column of its own, so the shared one
    /// cannot duplicate anything — the case `BigBoardView.columnContext` stays
    /// off for.
    private func columnContext(filed: Int) -> ProspectColumnContext {
        ProspectColumnContext(
            knowsSchemeFit: false,
            knowsNeeds: false,
            userTeamID: career.teamID,
            reportCount: filed,
            leadsWithScoutBand: true
        )
    }

    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        let isSelected = selectedIDs.contains(prospect.id)
        let filed = reportsOnFile(prospect)
        let maxed = filed >= ScoutEvaluationBudget.maxReportsPerProspect
        let selectable = isSelected || canAdd(prospect)
        let cost = nextReportCost(prospect)
        // Everything printed here is fogged: the tape band comes from
        // `ProspectFog.tapeRead`, the mode block from `ProspectColumns` (fogged
        // measurables, scouted grade bands, work the club has actually done),
        // the projection is the media's round, and there is no raw attribute
        // anywhere on the row.

        return Button {
            toggle(prospect)
        } label: {
            HStack(spacing: 0) {
                Image(systemName: isSelected ? "checkmark.circle.fill"
                                 : (maxed ? "checkmark.seal.fill" : "circle"))
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentGold
                                     : (maxed ? Color.success : Color.textTertiary))
                    .frame(width: 22)

                ProspectSelectionPositionBadge(position: prospect.position)

                // Portrait + name + mark + my grade over college · projected
                // round — the board row's identity block, shared.
                ProspectRowIdentity(prospect: prospect) {
                    // A blocked row must say WHY on the row, not go quietly grey.
                    if maxed {
                        Text("3 reports filed \u{2014} nothing left to see")
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(Color.success)
                    } else if !selectable {
                        // Most-binding reason first: a shut stage blocks
                        // every row, so blaming the budget for it sent the
                        // user chasing money he did not need to find.
                        Text(!canAct
                             ? "Stage is not open yet"
                             : (selectedIDs.count >= evaluationSlotsLeft
                                ? "No slots left in this order"
                                : "Over budget at $\(cost)K"))
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(Color.warning)
                    }
                }

                ProspectColumns.cells(
                    for: prospect,
                    mode: mode,
                    context: columnContext(filed: filed)
                )

                // PINNED regardless of mode: the tape read the money buys, and
                // what the next report on him costs.
                ProspectTapeCell(prospect: prospect, width: 46)

                // Dropped in Work-up mode — the block's own RPT cell already
                // prints this exact fraction (#fleet review F19a). See
                // `tableHeader`, which drops the label in lockstep.
                if mode != .workup {
                    Text("\(filed)/\(ScoutEvaluationBudget.maxReportsPerProspect)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(maxed ? Color.success : Color.textSecondary)
                        .frame(width: 38, alignment: .center)
                }

                Text(maxed ? "\u{2014}" : "$\(cost)K")
                    .font(.system(size: 12, weight: .heavy).monospacedDigit())
                    .foregroundStyle(maxed ? Color.textTertiary
                                     : (selectable ? Color.accentGold : Color.textTertiary))
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(maxed || !selectable)
        .opacity(maxed ? 0.5 : (selectable ? 1.0 : 0.55))
        .accessibilityLabel("\(prospect.fullName), \(prospect.position.rawValue), \(prospect.college)")
        .accessibilityValue(rowAccessibilityValue(prospect, filed: filed, maxed: maxed,
                                                  selectable: selectable, cost: cost))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func rowAccessibilityValue(
        _ prospect: CollegeProspect,
        filed: Int,
        maxed: Bool,
        selectable: Bool,
        cost: Int
    ) -> String {
        if maxed {
            return "Three reports filed \u{2014} your department has seen everything it is going to see."
        }
        if !selectable {
            return selectedIDs.count >= evaluationSlotsLeft
                ? "No evaluation slots left in this order."
                : "Needs $\(cost)K \u{2014} only $\(budgetLeftAfterOrder)K left after the men already selected."
        }
        return "\(filed) of \(ScoutEvaluationBudget.maxReportsPerProspect) reports on file. Next report $\(cost)K."
    }

    // `positionColor` moved to `ProspectSelectionPositionBadge` in
    // `ProspectListControls.swift` — the interview list carried a byte-identical
    // copy of the same three cases.

    // MARK: - Run bar

    private var runBar: some View {
        let reason = blockedReason
        let blocked = reason != nil
        return Button {
            runBatch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: canAct ? "film.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(reason ?? "Order Film Study (\(selectedIDs.count)) \u{2014} $\(selectedSpend)K")
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(blocked ? Color.textTertiary : Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(blocked ? Color.backgroundTertiary.opacity(0.5) : Color.accentGold)
            )
        }
        .disabled(blocked)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Running the batch

    /// Files one report per selected man, charges the ledger once, and presents
    /// what the order bought.
    ///
    /// Every guard the button already applied is re-applied here. The button is
    /// the UI; this is the money, and spending an evaluation slot writes state
    /// the stage machine reads (`DraftPrepProgress.filmReportsFiled` raises
    /// `Career.derivedPrepStepFloor`), so one order placed out of turn would
    /// step the whole pipeline over the film-study stage.
    private func runBatch() {
        guard canAct,
              blockedReason == nil,
              let scout = leadScout else { return }

        let phase = currentScoutingPhase
        let targets = selectedProspects
        var entries: [FilmStudyReportEntry] = []
        var spent = 0
        // Local copies of both limits so the loop re-checks them per man, in the
        // same escalating-price arithmetic the selection used. A class that moved
        // under the selection (it cannot today, but the guard costs nothing)
        // simply buys fewer reports rather than overdrawing the pot.
        var slotsLeft = evaluationSlotsLeft
        var budgetLeft = remainingScoutingBudget

        // The ONE way any screen mutates the draft class: it writes the canonical
        // static, calls `WeekAdvancer.persistDraftClass` and saves the context —
        // the same flush `ProspectDetailView.recordEvaluation` does by hand.
        // Without it the money is spent and the intel is forgotten on relaunch.
        let applied = DraftClassMutator.mutate(modelContext) { klass in
            for target in targets {
                guard slotsLeft > 0 else { break }
                guard let index = klass.firstIndex(where: { $0.id == target.id }) else { continue }
                let existing = ScoutEvaluationBudget.chargeableReports(klass[index])
                guard existing < ScoutEvaluationBudget.maxReportsPerProspect else { continue }
                let cost = ScoutEvaluationBudget.cost(existingReports: existing)
                guard budgetLeft >= cost else { continue }

                // Band before/after around the apply, so the report can show the
                // move the money paid for — the same shape as the single-prospect
                // film-study result sheet (#117) and the workout result.
                let before = Self.scoutBand(klass[index])
                let report = ScoutingEngine.generateScoutReport(
                    scout: scout,
                    prospect: klass[index],
                    phase: phase
                )
                ScoutingEngine.applyReport(report: report, to: klass[index])

                entries.append(FilmStudyReportEntry(
                    prospectName: klass[index].fullName,
                    position: klass[index].position,
                    college: klass[index].college,
                    scoutName: report.scoutName,
                    bandBefore: before,
                    bandAfter: Self.scoutBand(klass[index]),
                    strengths: Self.nonEmpty(report.strengthNotes),
                    weaknesses: Self.nonEmpty(report.weaknessNotes),
                    personality: Self.nonEmpty(report.personalityNotes)
                ))

                slotsLeft -= 1
                budgetLeft -= cost
                spent += cost
            }
        }

        // `mutate` returns false when there is no class in memory. Nothing
        // happened, so nothing is charged and nothing is claimed.
        guard applied, !entries.isEmpty else { return }

        // ORDER IS LOAD-BEARING, exactly as in `ProspectDetailView
        // .recordEvaluation` and `BigBoardView.orderFilmStudy`. `evaluationsUsed`
        // and `evaluationSpend` read through `ScoutEvaluationBudget.thisCycle`,
        // which returns 0 while the stored stamp belongs to an earlier cycle.
        // Stamping FIRST makes both start returning LAST cycle's totals, and the
        // first order of a new spring would resurrect the previous spring's
        // spend. Snapshot first, stamp last.
        let usedBefore = evaluationsUsed
        let spendBefore = evaluationSpend
        evaluationCycleStored = career.currentSeason
        evaluationsUsedStored = usedBefore + entries.count
        evaluationSpendStored = spendBefore + spent

        selectedIDs.removeAll()
        refreshList()

        activeSheet = .batchReport(FilmStudyBatch(
            entries: entries,
            scoutName: "Scout \(scout.fullName)",
            occasion: occasionLabel,
            totalSpend: spent,
            slotsLeft: max(0, ScoutEvaluationBudget.slotsPerCycle - (usedBefore + entries.count))
        ))
    }

    // MARK: - Data

    /// Reloads the class and rebuilds every derived cache.
    ///
    /// The ONE writer of `orderedCache` / `recommendedCache` / `otherCache` /
    /// `costByID` / `filedCache`. Called on appearance, when the hub's position
    /// filter moves, and after a batch — the three moments any of those inputs
    /// can change. Everything it computes is O(class); nothing that renders a
    /// row is.
    private func refreshList() {
        prospects = WeekAdvancer.currentDraftClass.filter(\.isDeclaringForDraft)

        let ordered = computeOrderedProspects()
        let recommended = computeRecommended(from: ordered)
        let recommendedIDs = Set(recommended.map(\.id))

        orderedCache = ordered
        recommendedCache = recommended
        otherCache = ordered.filter { !recommendedIDs.contains($0.id) }
        // One walk of the class prices everybody and finds the cheapest man
        // still worth ordering on — the two facts every row and the steady-state
        // test need, computed once instead of per render.
        var costs: [UUID: Int] = [:]
        var filed: [UUID: Int] = [:]
        var cheapest: Int?
        for prospect in prospects {
            // The ONE decode per man per refresh. Everything downstream —
            // the price, the RPTS column, the work-up block's RPT cell, the
            // affordability test — reads these two maps.
            let existing = ScoutEvaluationBudget.chargeableReports(prospect)
            let cost = ScoutEvaluationBudget.cost(existingReports: existing)
            filed[prospect.id] = existing
            costs[prospect.id] = cost
            if existing < ScoutEvaluationBudget.maxReportsPerProspect,
               cheapest == nil || cost < cheapest! {
                cheapest = cost
            }
        }
        reportsByID = filed
        costByID = costs
        cheapestWorkableCost = cheapest
        filedCache = computeFiledEntries()

        // A man the batch just took to three reports must not keep charging the
        // footer for an order he can no longer be in. Tested against the WHOLE
        // class, never against the filtered list: switching the hub's position
        // chip is a change of view, not a change of order, and silently
        // discarding the eight linemen a user picked before he tabbed to the
        // corners would be the worst kind of quiet.
        let stillWorkable = Set(prospects.filter(hasRoom).map(\.id))
        selectedIDs.formIntersection(stillWorkable)
    }

    private func loadDepartment() {
        guard let teamID = career.teamID else { return }
        let scoutDesc = FetchDescriptor<Scout>(predicate: #Predicate { $0.teamID == teamID })
        scouts = (try? modelContext.fetch(scoutDesc)) ?? []
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        scoutingBudget = (try? modelContext.fetch(teamDesc))?.first?.owner?.scoutingBudget ?? 4_000
    }

    // MARK: - Fog-safe reads

    /// The overall band this screen may print for a man.
    ///
    /// `ProspectDetailView.effectiveOverallGrade` verbatim: the fogged read,
    /// accepted only when it came from THIS building's scouts. Reading
    /// `CollegeProspect.effectiveOverallGrade` straight would print a band
    /// tighter than the department's actual confidence, and falling through to
    /// the media's projected-round band would label the league's guess as work
    /// the user just paid for. `trueOverall` is never touched.
    private static func scoutBand(_ prospect: CollegeProspect) -> GradeRange? {
        let read = ProspectFog.read(prospect)
        return read.source == .scouts ? read.band : nil
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

// MARK: - Report model
//
// Value types, deliberately. The sheet outlives the mutation that produced it,
// and holding `@Model` references across that boundary is how a result screen
// ends up re-reading a prospect that has moved on. Everything the report prints
// is snapshotted at file time.

/// One prospect's line in a film-study report.
struct FilmStudyReportEntry: Identifiable {
    let id = UUID()
    let prospectName: String
    let position: Position
    let college: String
    /// The scout whose name is on the report.
    let scoutName: String
    /// The band before the report was applied. `nil` for a saved report — the
    /// previous band is not stored, and inventing one would be a fabrication.
    let bandBefore: GradeRange?
    let bandAfter: GradeRange?
    let strengths: String?
    let weaknesses: String?
    /// Present only when the report actually carried a personality read — the
    /// scout's `personalityRead` roll can come back with nothing.
    let personality: String?

    /// Ranking key: the post-report band. Fog-safe by construction — it is a
    /// letter band, never a stored attribute.
    var rank: Int { bandAfter?.midGrade.rank ?? 0 }

    /// Whether the money visibly moved the band.
    var bandMoved: Bool {
        guard let before = bandBefore, let after = bandAfter else { return bandAfter != nil }
        return before != after
    }
}

/// Everything one film-study order (or one cycle of them) bought.
struct FilmStudyBatch: Identifiable {
    let id = UUID()
    let entries: [FilmStudyReportEntry]
    /// Who ran the sessions.
    let scoutName: String
    /// "Combine · 2027".
    let occasion: String
    /// Thousands spent.
    let totalSpend: Int
    /// Evaluation slots left in the cycle after the order.
    let slotsLeft: Int
}

// MARK: - Report view

/// What the order filed, ranked by the band it bought.
///
/// Modelled on `InterviewReportView`'s result cards — compact card, tier-coloured
/// grade at the trailing edge — so the two stages report in the same voice.
/// Rendered inside a sheet after a batch, and inline as the tab's steady state
/// once the cycle is bought out.
struct FilmStudyBatchReportView: View {
    let batch: FilmStudyBatch
    /// `true` when this is the cycle's saved summary rather than a just-run
    /// batch. Suppresses the before→after arrow (there is no stored "before")
    /// and re-words the header.
    var isSavedReport: Bool = false

    private var rankedEntries: [FilmStudyReportEntry] {
        batch.entries.sorted { $0.rank > $1.rank }
    }

    var body: some View {
        VStack(spacing: 0) {
            reportHeader
            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            ScrollView {
                LazyVStack(spacing: 12) {
                    summarySection
                    ForEach(Array(rankedEntries.enumerated()), id: \.element.id) { index, entry in
                        entryCard(entry, rank: index + 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Header

    private var reportHeader: some View {
        HStack {
            Text(isSavedReport ? "FILM STUDY \u{2014} THIS CYCLE" : "FILM STUDY REPORT")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .tracking(0.5)

            Spacer()

            Text("\(batch.entries.count) report\(batch.entries.count == 1 ? "" : "s") filed")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .tracking(0.5)

            HStack(spacing: 12) {
                summaryPill(
                    icon: "doc.text.magnifyingglass",
                    text: "\(batch.entries.count) filed by \(batch.scoutName)",
                    color: .accentGold
                )
                summaryPill(icon: "calendar", text: batch.occasion, color: .textSecondary)
            }

            HStack(spacing: 12) {
                summaryPill(
                    icon: "dollarsign.circle",
                    text: isSavedReport
                        ? "$\(batch.totalSpend)K spent this cycle"
                        : "$\(batch.totalSpend)K spent",
                    color: .textSecondary
                )
                summaryPill(
                    icon: "gauge.with.dots.needle.33percent",
                    text: "\(batch.slotsLeft) of \(ScoutEvaluationBudget.slotsPerCycle) evaluations left",
                    color: batch.slotsLeft == 0 ? .danger : .textSecondary
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentGold.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentGold.opacity(0.2))
                )
        )
    }

    private func summaryPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Card

    private func entryCard(_ entry: FilmStudyReportEntry, rank: Int) -> some View {
        let isTop = rank == 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("#\(rank)")
                    .font(.system(size: 14, weight: .heavy).monospacedDigit())
                    .foregroundStyle(isTop ? Color.accentGold : Color.textTertiary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.prospectName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text(entry.position.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentGold.opacity(0.15)))
                    }
                    Text(entry.college)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                // Tier-coloured grade at the trailing edge, exactly where the
                // interview report puts its letter.
                VStack(spacing: 1) {
                    Text(entry.bandAfter?.displayText ?? "\u{2014}")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(gradeColor(entry.bandAfter))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Band")
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(width: 58)
            }

            // Before → after. Suppressed on a saved report and on a first
            // report (there was no band to move), so the row only appears when
            // it has something true to say.
            if !isSavedReport, let after = entry.bandAfter {
                HStack(spacing: 6) {
                    Image(systemName: entry.bandBefore == nil
                          ? "eye.fill"
                          : (entry.bandMoved ? "arrow.triangle.branch" : "equal.circle"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(entry.bandBefore?.displayText ?? "No read")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                    Text(after.displayText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(gradeColor(after))
                }
            }

            if let strengths = entry.strengths {
                noteRow(icon: "checkmark.circle.fill", tint: .success,
                        title: "What the tape showed", body: strengths)
            }
            if let weaknesses = entry.weaknesses {
                noteRow(icon: "exclamationmark.triangle.fill", tint: .warning,
                        title: "Where he gets beaten", body: weaknesses)
            }
            if let personality = entry.personality {
                noteRow(icon: "person.fill", tint: .accentBlue,
                        title: "The person", body: personality)
            }

            Text("Filed by \(entry.scoutName)")
                .font(.system(size: DSType.Size.micro, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isTop ? Color.accentGold : Color.surfaceBorder.opacity(0.3),
                            lineWidth: isTop ? 1.5 : 0.5
                        )
                )
        )
    }

    private func noteRow(icon: String, tint: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(tint)
                    .tracking(0.3)
            }
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The band's tier colour. Keyed off the MIDPOINT grade rather than the
    /// display string, so "B-/A-" is coloured by where the department actually
    /// has him and not by whichever letter happens to be printed first.
    private func gradeColor(_ band: GradeRange?) -> Color {
        guard let band else { return Color.textTertiary }
        return PositionGradeCalculator.gradeColorForLetter(band.midGrade.rawValue)
    }
}
