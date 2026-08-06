import SwiftUI
import SwiftData

// MARK: - Board constants
//
// File scope rather than static members: `BigBoardView` is generic over its
// header view, and a generic type cannot hold static stored properties.

/// The user's own draft-grade options in the assessment sheet.
private let bigBoardGradeOptions = ["none", "A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D", "F"]

private let bigBoardTierNames = ["Blue Chip", "First Rounder", "Day Two (Rd 2-3)", "Day Three (Rd 4-5)", "Late Rounds (Rd 6-7)", "Priority UDFA", "Draftable"]
private let bigBoardTierColors: [Color] = [.accentGold, .success, .accentBlue, .accentBlue.opacity(0.6), .textSecondary, .textTertiary, .textTertiary]
private let bigBoardTierDescriptions = [
    "Elite talent, projected Rd 1 pick",
    "Top tier, solid Rd 1-2 projection",
    "Quality starters, Rd 2-3 range",
    "Developmental starters, Rd 4-5 range",
    "Depth / special teams, Rd 6-7 range",
    "Undrafted free agent priority",
    "Camp bodies / long-shot prospects"
]

/// Cap on how many men of one position a single scout tier may hold.
private let bigBoardMaxSamePositionPerTier = 4

// The Physical block's six drill columns and their width moved to
// `ProspectListControls.swift` as `prospectMeasurableLabels` /
// `prospectMeasurableWidth`, with the whole column vocabulary
// (`ProspectColumns`) the batch-selection lists now render too. One definition
// of "what the combine card says at this fidelity", not three.

/// The one prospect list surface.
///
/// It used to be two: a "Prospects" tab and this one, over the same array, with
/// the same attribute-mode picker declared once and re-hosted as `@State` in
/// both. The board is the richer of the two — tiers, My Board, the compare
/// tray, `.onMove` reordering, board-vs-media comparison — so the list is gone
/// and its one unique idea, the work-up column block, is a mode here.
///
/// The hub's header is passed in by closure and rendered as this list's FIRST
/// SECTION, which is what makes the whole page scroll with one gesture without
/// nesting a `List` inside a `ScrollView` (illegal) or flattening the list into
/// a `LazyVStack` (which would take `.onMove` with it).
struct BigBoardView<Header: View>: View {
    let career: Career
    let prospects: [CollegeProspect]
    let teamRoster: [Player]
    var scoutsSentToCombine: Bool = false
    /// Lets the empty state hand the user back to another Scouting tab
    /// ("Hire Scouts" → Scout Team, "Browse Prospects" → Prospects). Optional so
    /// standalone call sites and previews can omit it.
    var onSwitchTab: ((ScoutingTab) -> Void)?
    /// Number of scouts currently on staff — drives the empty state's copy
    /// (0 scouts is a different problem from 8 scouts and an unscouted class).
    var scoutCount: Int = 0
    /// Owned by `ScoutingHubView` so one tap on the hub's position chips filters
    /// the Big Board, the Prospects list and the Combine table together, and
    /// switching tabs keeps the filter. The board used to carry its own copy in
    /// a `.principal` toolbar item, which the hub's large navigation title hid —
    /// so the chips the user could see (the Prospects tab's) drove a different
    /// piece of state than the board he was looking at.
    @Binding var positionFilter: ProspectPositionFilter

    /// The column block the board opens on, when the HOST has an opinion.
    ///
    /// The film-study stage opens it on `.workup`, which is the block that
    /// answers "what work is missing". `nil` — the default, and what the plain
    /// Board tab passes — lets the board read the calendar instead: see
    /// ``defaultAttributeTab``.
    ///
    /// Optional rather than defaulted-to-`.overview` because those are two
    /// different statements and the board has to tell them apart. With a plain
    /// default there is no way to distinguish "the host wants Overview" from
    /// "the host did not say", so a calendar-aware default would silently
    /// override a host that had deliberately asked for Overview.
    var initialAttributeTab: ProspectAttributeTab? = nil

    /// Film-study stage: the board IS the stage screen, and the paid evaluate
    /// action is promoted out of the prospect card (two taps deep) into the row.
    var isFilmStudy: Bool = false

    /// The club has moved past this stage. The board stays open and read-only —
    /// marks, notes and ordering are free and local, the priced action is not.
    var isStageClosed: Bool = false

    /// The hub's scroll-away header. Rendered as the first `Section` of the
    /// list, never as a wrapper around it.
    let header: () -> Header

    @Environment(\.modelContext) private var modelContext
    @State private var markFilter: ProspectMarkFilter = .all
    @State private var attributeTab: ProspectAttributeTab = .overview
    /// See ``rebuildPercentilePools()``. Empty until the board's `.task` runs,
    /// which is exactly right — an empty pool prints no percentile claim.
    @State private var percentilePools = PercentilePools()
    /// Loaded for the film-study row action; empty everywhere else.
    @State private var scouts: [Scout] = []
    @State private var scoutingBudget: Int = 4_000
    @State private var showMarkedOnly: Bool = false
    @State private var editingAssessmentProspect: CollegeProspect?
    @State private var editingMarkNoteProspect: CollegeProspect?
    /// Compare tray — up to four men, reachable straight off a board row.
    @State private var compareSelection: [CollegeProspect] = []
    @State private var showCompareSheet: Bool = false
    @State private var coaches: [Coach] = []
    @State private var showMyBoard: Bool = false
    @State private var teamDraftPicks: [DraftPick] = []
    @State private var boardSortOrder: BigBoardSort = .boardRank
    @State private var editingNoteProspect: CollegeProspect?
    @State private var searchText: String = ""
    @State private var filterProjectedRoundMin: Int = 1
    @State private var filterProjectedRoundMax: Int = 8
    @State private var filterRisk: ProspectRiskLevel? = nil
    @State private var showFilterMenu: Bool = false
    @State private var filterMyGradeFirstRound: Bool = false
    @State private var showBoardComparison: Bool = false
    @ObservedObject private var userGradeStore = UserProspectGradeStore.shared
    @State private var isLoading: Bool = true
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var cachedTieredBoard: [(tier: Int, prospects: [CollegeProspect])] = []
    @State private var cachedOrderedBoard: [CollegeProspect] = []
    @State private var cachedCustomOrderedBoard: [CollegeProspect] = []
    /// My Board, split into mark-tier sections. The tier is the tier-break
    /// primitive: a verdict written on the prospect card becomes structure here.
    @State private var cachedMarkGroups: [(tier: ProspectMarkTier, prospects: [CollegeProspect])] = []
    /// O(1) rank lookup by prospect ID — avoids per-row firstIndex(where:) which would be O(n²) overall.
    @State private var cachedRankMap: [UUID: Int] = [:]
    @State private var cachedCustomRankMap: [UUID: Int] = [:]
    /// Value-vs-my-grade read per prospect, computed once per refresh so a row
    /// never re-derives it and the sort has one source.
    @State private var cachedValueReads: [UUID: ProspectFog.ValueRead] = [:]

    // MARK: - Prospect Notes Storage

    @CareerScopedStorage("prospectNotes") private var prospectNotesJSON: String = "{}"

    private var prospectNotes: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(prospectNotesJSON.utf8))) ?? [:]
    }

    private func saveProspectNote(prospectID: UUID, note: String) {
        var notes = prospectNotes
        let key = prospectID.uuidString
        if note.isEmpty {
            notes.removeValue(forKey: key)
        } else {
            notes[key] = note
        }
        if let data = try? JSONEncoder().encode(notes) {
            prospectNotesJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    // MARK: - Own Assessments Storage

    @CareerScopedStorage("prospectOwnAssessments") private var prospectOwnAssessmentsJSON: String = "{}"
    /// Read only to MIGRATE the legacy bookmark set onto the unified mark. The
    /// board's own bookmark filter is gone — it was a third opinion of the same
    /// prospect that only this screen could see.
    @CareerScopedStorage("prospectWatchlist") private var prospectWatchlistJSON: String = "[]"
    @CareerScopedStorage("prospectCustomBoard") private var prospectCustomBoardJSON: String = "[]"
    @CareerScopedStorage("rosterPriorities") private var rosterPrioritiesJSON: String = "{}"


    private var prospectOwnAssessments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(prospectOwnAssessmentsJSON.utf8))) ?? [:]
    }

    private var legacyWatchlistIDs: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(prospectWatchlistJSON.utf8))) ?? [])
    }

    private func saveOwnAssessment(prospectID: UUID, grade: String) {
        var assessments = prospectOwnAssessments
        let key = prospectID.uuidString
        if grade == "none" {
            assessments.removeValue(forKey: key)
        } else {
            assessments[key] = grade
        }
        if let data = try? JSONEncoder().encode(assessments) {
            prospectOwnAssessmentsJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
    }

    // MARK: - Board Order Storage
    //
    // ONE persisted order for the whole screen.
    //
    // There used to be two, and neither worked. `boardOrder` was `@State`,
    // re-seeded from the composite score on every appearance and never written
    // anywhere, so the tier movers and the Move Up / Move Down actions were
    // discarded the moment the view went away. `prospectCustomBoard` WAS
    // persisted, but nothing ever seeded it: "My Board" appended every prospect
    // the filter returned in raw fetch order, i.e. `DraftClassBuilder`'s
    // generation shuffle, and `moveCustomBoard` wrote the reordered list to
    // defaults without refreshing the cached array the list actually renders —
    // so a drag snapped straight back.
    //
    // Both are now the same list: `prospectCustomBoard`, seeded from the media
    // consensus on first open, appended to as new men are scouted, and written
    // (plus re-cached) by every mover.

    private var boardOrder: [UUID] {
        let strings = (try? JSONDecoder().decode([String].self, from: Data(prospectCustomBoardJSON.utf8))) ?? []
        return strings.compactMap { UUID(uuidString: $0) }
    }

    private func saveBoardOrder(_ ids: [UUID]) {
        let strings = ids.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(strings) {
            prospectCustomBoardJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    /// Media-only ordering used to seed the board and to place anything the
    /// stored order has not seen yet: the consensus rank by contract (mock pick,
    /// then projected round), falling back to the scouts' own read.
    private func consensusOrdered(_ list: [CollegeProspect]) -> [CollegeProspect] {
        list.sorted { lhs, rhs in
            let l = marketRank(for: lhs) ?? Int.max
            let r = marketRank(for: rhs) ?? Int.max
            if l != r { return l < r }
            return boardCompositeScore(for: lhs) > boardCompositeScore(for: rhs)
        }
    }

    /// Seeds the order on first open, drops last year's class, and appends newly
    /// scouted men to the end of the stored list (in consensus order) so nothing
    /// is left un-ranked. Writes only when something actually changed.
    ///
    /// The prune is what makes the stored order usable past season 1.
    /// `prospectCustomBoard` is career-scoped but NOT season-scoped and nothing
    /// resets it at the rollover, so without it season 2's men were appended
    /// behind ~285 retired IDs: `recordOriginalPositions` then stamped "original
    /// slot 286…570" on prospects whose row prints rank 1…285, and every single
    /// row rendered a green "↑ #412" movement badge.
    private func syncBoardOrder() {
        let board = scoutedProspects
        guard !board.isEmpty else { return }
        let live = Set(prospects.map(\.id))
        let stored = boardOrder
        let pruned = stored.filter { live.contains($0) }
        let known = Set(pruned)
        let missing = consensusOrdered(board.filter { !known.contains($0.id) }).map(\.id)
        let didPrune = pruned.count != stored.count
        guard didPrune || !missing.isEmpty else { return }
        // A class rollover invalidates every stored "original slot" too — they
        // were indices into a list that no longer exists.
        if didPrune { userGradeStore.clearOriginalPositions() }
        saveBoardOrder(pruned + missing)
    }

    /// Throws the stored order away and rebuilds it from the media consensus.
    private func resetBoardToConsensus() {
        saveBoardOrder(consensusOrdered(scoutedProspects).map(\.id))
        userGradeStore.clearOriginalPositions()
        recordOriginalPositions()
        refreshCachedBoard()
    }

    /// Ranks the board by what the USER has said: mark tier first, then his own
    /// draft grade, then the consensus as the tie-break. The point of the action
    /// is that a board full of marks and grades can be turned into an order in
    /// one tap instead of a hundred drags.
    private func autoRankFromMyGrades() {
        let ranked = scoutedProspects.sorted { lhs, rhs in
            let lm = lhs.userMark.sortRank
            let rm = rhs.userMark.sortRank
            if lm != rm { return lm < rm }
            let lg = impliedBoardSlot(forGradeOf: lhs) ?? Int.max
            let rg = impliedBoardSlot(forGradeOf: rhs) ?? Int.max
            if lg != rg { return lg < rg }
            let lc = marketRank(for: lhs) ?? Int.max
            let rc = marketRank(for: rhs) ?? Int.max
            if lc != rc { return lc < rc }
            return boardCompositeScore(for: lhs) > boardCompositeScore(for: rhs)
        }
        saveBoardOrder(ranked.map(\.id))
        userGradeStore.clearOriginalPositions()
        recordOriginalPositions()
        refreshCachedBoard()
    }

    /// The board slot the user's own draft grade implies, via `DraftIntel`'s
    /// table — the same one the value delta is measured against, so a board
    /// auto-ranked from the grades reads "IN LINE" all the way down.
    private func impliedBoardSlot(forGradeOf prospect: CollegeProspect) -> Int? {
        guard let grade = userGradeStore.grade(for: prospect.id),
              let ordinal = ProspectFog.gradeOrdinal(for: grade) else { return nil }
        return DraftIntel.impliedBoardSlot(userGradeOrdinal: ordinal)
    }

    private func recordOriginalPositions() {
        for (index, id) in boardOrder.enumerated() {
            userGradeStore.setOriginalPosition(for: id, position: index + 1)
        }
    }

    /// Whether the movement badge (`↑ #34`) means anything on the current view.
    ///
    /// It compares the row's printed `rank` against the slot the board was
    /// seeded at, so it is only readable when `rank` IS the board slot: the
    /// board-rank sort, with nothing filtered out. Under any other sort, or with
    /// a filter narrowing the list, `rank` is 1..N over a different population
    /// while `originalPosition` is still an index into the full stored order, so
    /// every row would claim a move it never made.
    private var showsBoardMovement: Bool {
        boardSortOrder == .boardRank
            && debouncedSearchText.isEmpty
            && positionFilter == .all
            && markFilter == .all
            && !showMarkedOnly
            && filterProjectedRoundMin <= 1
            && filterProjectedRoundMax >= 8
            && filterRisk == nil
            && !filterMyGradeFirstRound
    }

    /// Applies a reorder made inside one visible section (a scout tier, or a
    /// mark group on My Board) to the single stored order.
    ///
    /// The section keeps the slots it already occupies in the full list and
    /// only the occupants are rewritten, so dragging inside "Blue Chip" can
    /// never scatter a man into round five.
    private func reorderSection(ids sectionIDs: [UUID], from: IndexSet, to: Int) {
        guard !sectionIDs.isEmpty else { return }
        var section = sectionIDs
        section.move(fromOffsets: from, toOffset: to)

        var full = boardOrder
        let member = Set(sectionIDs)
        var slots: [Int] = []
        for (index, id) in full.enumerated() where member.contains(id) { slots.append(index) }
        guard slots.count == section.count else { return }
        for (offset, slot) in slots.enumerated() { full[slot] = section[offset] }
        saveBoardOrder(full)
        refreshCachedBoard()
    }

    // MARK: - Market rank (pinned contract: media-only)

    /// The media's consensus board slot for one prospect.
    ///
    /// `DraftIntel` owns it, and by contract it is built from public
    /// information ONLY — the latest mock's pick number, then the projected
    /// round — never `scoutedOverall`. Routed through one call site so the
    /// board, the value chip and the seed all read the same number.
    private func marketRank(for prospect: CollegeProspect) -> Int? {
        DraftIntel.consensusRank(for: prospect.id)
    }

    /// The value read for a row, or `nil` when there is nothing honest to show.
    private func valueRead(for prospect: CollegeProspect) -> ProspectFog.ValueRead? {
        cachedValueReads[prospect.id]
    }

    // MARK: - User Roster Priorities

    private var rosterPriorities: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rosterPrioritiesJSON.utf8))) ?? [:]
    }

    // MARK: - Film study (the evaluate action, promoted into the row)
    //
    // #79's evaluation economy, unchanged: 25 slots a cycle, 20/35/55 K rising
    // cost, three reports a man, cycle-stamped so it resets with the class.
    // Film study is a PRESENTATION of that spend, not a second wallet — the
    // counters below are the same three career-scoped keys the prospect card
    // writes, read through the same `ScoutEvaluationBudget.thisCycle` stamp.
    //
    // What changes is where the button is. It lived at the bottom of a prospect
    // card's action stack, so ordering tape on twenty men was sixty taps and
    // four screens; the stage that is *about* ordering tape needs it on the row.

    @CareerScopedStorage("scoutEvaluationsUsed") private var evaluationsUsedStored: Int = 0
    @CareerScopedStorage("scoutEvaluationSpend") private var evaluationSpendStored: Int = 0
    @CareerScopedStorage("scoutEvaluationCycle") private var evaluationCycleStored: Int = 0
    @CareerScopedStorage("combineTripSpend") private var combineTripSpend: Int = 0

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

    private var remainingScoutingBudget: Int {
        scoutingBudget
            - scouts.reduce(0) { $0 + $1.salary }
            - combineTripSpend
            - evaluationSpend
    }

    /// Same ladder as the prospect card's, so a row and a card never disagree
    /// about whether a man can be worked.
    private func filmAvailability(for prospect: CollegeProspect) -> ScoutEvaluationAvailability {
        guard !isStageClosed else {
            return .windowShut(hint: "Film study closed when the department moved on.")
        }
        guard ScoutEvaluationBudget.isWindowOpen(career.currentPhase) else {
            return .windowShut(hint: ScoutEvaluationBudget.windowHint(for: career.currentPhase))
        }
        guard !scouts.isEmpty else { return .noScouts }
        guard ScoutEvaluationBudget.chargeableReports(prospect) < ScoutEvaluationBudget.maxReportsPerProspect else {
            return .reportsMaxed
        }
        guard evaluationSlotsLeft > 0 else { return .slotsSpent }
        let cost = ScoutEvaluationBudget.cost(existingReports: ScoutEvaluationBudget.chargeableReports(prospect))
        guard remainingScoutingBudget >= cost else {
            return .cannotAfford(cost: cost, remaining: remainingScoutingBudget)
        }
        return .available(cost: cost, slotsLeft: evaluationSlotsLeft)
    }

    /// The scout the department would put on this man: his position specialist
    /// first, then the most accurate eye on staff. The prospect card still lets
    /// the user pick by hand; a board row is a bulk instrument and picking a
    /// scout twenty times is not a decision, it is a chore.
    private func assignedScout(for prospect: CollegeProspect) -> Scout? {
        scouts
            .max { lhs, rhs in
                let l = (lhs.positionSpecialization == prospect.position ? 100 : 0) + lhs.accuracy
                let r = (rhs.positionSpecialization == prospect.position ? 100 : 0) + rhs.accuracy
                return l < r
            }
    }

    /// `ProspectDetailView.currentScoutingPhase`, copied so the report a row
    /// files carries the same confidence as one filed from the card.
    private var currentScoutingPhase: ScoutingPhase {
        switch career.currentPhase {
        case .combine:                                  return .combine
        case .freeAgency, .proDays, .draft:             return .proDay
        case .otas, .trainingCamp, .preseason, .rosterCuts: return .personalWorkout
        default:                                        return .collegeSeason
        }
    }

    /// Files one report and books it against the cycle's slots and the pot.
    ///
    /// Every write goes through `DraftClassMutator` — the canonical class, the
    /// SwiftData flush and the save in one call — so a report ordered from a row
    /// survives a relaunch exactly like one ordered from the card.
    private func orderFilmStudy(on prospect: CollegeProspect) {
        guard case let .available(cost, _) = filmAvailability(for: prospect),
              let scout = assignedScout(for: prospect) else { return }

        let phase = currentScoutingPhase
        let applied = DraftClassMutator.mutate(modelContext) { klass in
            guard let index = klass.firstIndex(where: { $0.id == prospect.id }) else { return }
            let report = ScoutingEngine.generateScoutReport(
                scout: scout,
                prospect: klass[index],
                phase: phase
            )
            ScoutingEngine.applyReport(report: report, to: klass[index])
        }
        guard applied else { return }

        // ORDER IS LOAD-BEARING, exactly as in `ProspectDetailView.recordEvaluation`.
        // `evaluationsUsed` / `evaluationSpend` read through
        // `ScoutEvaluationBudget.thisCycle`, which returns 0 while the stored
        // stamp belongs to an earlier cycle. Stamping FIRST makes both of them
        // start returning LAST cycle's totals, so the first film-study order of
        // a new cycle resurrected the previous spring's spend: slots jumped
        // 0 → 26/25, every later evaluation reported `.slotsSpent`, and the
        // scouting pot (which also gates the combine trip) lost a full cycle.
        // Snapshot first, stamp last.
        let usedBefore = evaluationsUsed
        let spendBefore = evaluationSpend
        evaluationCycleStored = career.currentSeason
        evaluationsUsedStored = usedBefore + 1
        evaluationSpendStored = spendBefore + cost
        refreshCachedBoard()
    }

    private func loadScoutingDepartment() {
        guard let teamID = career.teamID else { return }
        let scoutDesc = FetchDescriptor<Scout>(predicate: #Predicate { $0.teamID == teamID })
        scouts = (try? modelContext.fetch(scoutDesc)) ?? []
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        scoutingBudget = (try? modelContext.fetch(teamDesc))?.first?.owner?.scoutingBudget ?? 4_000
    }

    // MARK: - Tier Constants


    // MARK: - Board Prospects

    private var scoutedProspects: [CollegeProspect] {
        prospects.filter { $0.scoutedOverall != nil }
    }

    /// Composite board score = the scouted overall, full stop.
    /// Positional value is baked into the class blueprint (a position's talent
    /// is decided by which board slots it is allocated), so re-applying a
    /// positional multiplier here would double-count it.
    ///
    /// An unscouted man scores 0 and sinks, rather than falling back to
    /// `trueOverall`. Every caller filters on `scoutedOverall != nil` today, so
    /// the old `?? prospect.trueOverall` was unreachable — but it sat one filter
    /// change away from leaking the generator's own number through the SORT,
    /// which is the quietest disclosure channel there is: nothing prints, the
    /// unscouted stud just happens to land at the top of the board.
    private func boardCompositeScore(for prospect: CollegeProspect) -> Double {
        Double(prospect.scoutedOverall ?? 0)
    }

    /// Projected round from the board score. Thresholds are `DraftClassBuilder`'s
    /// own `talentTarget` evaluated at the cumulative band boundaries, **including
    /// the post-#224 taper** the bare `96.5 − 5.2·ln(r + 1.5)` curve omits:
    /// #28 78.9 · #61 75.0 · #99 72.5 · #142 70.7 · #189 69.2 ·
    /// #240 67.5 (68.0 − 0.48 taper) · #295 64.8 (66.9 − 2.13 taper).
    /// Reading the R6/R7/UDFA cuts off the untapered curve put them a full band
    /// too high, so ~58 % of round-7 grades rendered "UDFA" here while every
    /// other screen showed the prospect's own `draftProjection` of "Rd 7".
    private func boardProjectedRound(for prospect: CollegeProspect) -> Int {
        let score = boardCompositeScore(for: prospect)
        switch score {
        case 78.9...:     return 1
        case 75..<78.9:   return 2
        case 72.5..<75:   return 3
        case 70.7..<72.5: return 4
        case 69.2..<70.7: return 5
        case 67.5..<69.2: return 6
        case 64.8..<67.5: return 7
        default:          return 8 // UDFA
        }
    }

    /// Board tier from the board score, on the same tapered curve as the round
    /// bands (tier 5 "Late Rounds (Rd 6-7)" therefore spans the R6 *and* R7
    /// bands, and tier 6/7 split the UDFA band at its midpoint #322 ≈ 63.5).
    private func boardTier(for prospect: CollegeProspect) -> Int {
        if let manual = prospect.manualTier { return manual }
        let score = boardCompositeScore(for: prospect)
        switch score {
        case 83.8...:     return 1  // Blue Chip      (top ~10 slots)
        case 78.9..<83.8: return 2  // First Rounder
        case 72.5..<78.9: return 3  // Day Two (Rd 2-3)
        case 69.2..<72.5: return 4  // Day Three (Rd 4-5)
        case 64.8..<69.2: return 5  // Late Rounds (Rd 6-7)
        case 63.5..<64.8: return 6  // Priority UDFA
        default:          return 7  // Draftable
        }
    }

    private var filteredProspects: [CollegeProspect] {
        var result = scoutedProspects
        // Search filter (#9) - uses debounced text for performance
        if !debouncedSearchText.isEmpty {
            let query = debouncedSearchText.lowercased()
            result = result.filter {
                $0.fullName.lowercased().contains(query) ||
                $0.position.rawValue.lowercased().contains(query) ||
                $0.college.lowercased().contains(query)
            }
        }
        if positionFilter != .all {
            result = result.filter { positionFilter.matches($0.position) }
        }
        // ONE mark system drives the filter: the tier the user set, nothing else.
        if let tier = markFilter.tier {
            result = result.filter { $0.userMark == tier }
        }
        if showMarkedOnly {
            result = result.filter(\.isMarked)
        }
        // Projected round range filter (#10)
        if filterProjectedRoundMin > 1 || filterProjectedRoundMax < 8 {
            result = result.filter {
                let rd = boardProjectedRound(for: $0)
                return rd >= filterProjectedRoundMin && rd <= filterProjectedRoundMax
            }
        }
        // Risk filter (#10)
        if let riskFilter = filterRisk {
            result = result.filter { $0.riskLevel == riskFilter }
        }
        // User grade filters. There is no second "marked only" test here: the
        // menu item used to drive its own `filterStarredOnly` flag against the
        // LEGACY star store while calling itself "Marked Only", so after
        // `migrateLegacyMarks` folded the stars into `userMarkTier` the two
        // controls with the same name disagreed — the toolbar bookmark filtered
        // on the mark the user can actually see and set, the menu item on a set
        // nothing writes any more. Both now drive `showMarkedOnly` above.
        if filterMyGradeFirstRound {
            result = result.filter { userGradeStore.isFirstRoundPlus($0.id) }
        }
        return result
    }

    /// Applies the ONE persisted board order to a filtered slice. Anything the
    /// stored order has not seen yet (a man scouted since the last sync) falls
    /// in behind it, in consensus order rather than fetch order.
    private func applyBoardOrder(_ filtered: [CollegeProspect]) -> [CollegeProspect] {
        var index: [UUID: Int] = [:]
        for (position, id) in boardOrder.enumerated() { index[id] = position }
        return filtered.sorted { lhs, rhs in
            let l = index[lhs.id] ?? Int.max
            let r = index[rhs.id] ?? Int.max
            if l != r { return l < r }
            let lc = marketRank(for: lhs) ?? Int.max
            let rc = marketRank(for: rhs) ?? Int.max
            if lc != rc { return lc < rc }
            return boardCompositeScore(for: lhs) > boardCompositeScore(for: rhs)
        }
    }

    /// The board's sort applied to the current filter.
    ///
    /// `valueReads` is passed in rather than read off `cachedValueReads`
    /// because `refreshCachedBoard` computes both in one pass — reading a
    /// `@State` it has just written in the same function is exactly the kind of
    /// ordering assumption that made the old movers no-ops.
    private func orderedBoard(valueReads: [UUID: ProspectFog.ValueRead]) -> [CollegeProspect] {
        let filtered = filteredProspects

        // #9: Apply sort order
        switch boardSortOrder {
        case .boardRank:
            return applyBoardOrder(filtered)
        case .valueDelta:
            // Fog-safe: an ungraded or fully fogged prospect has no read at all
            // and sinks to the bottom rather than sorting as "zero value".
            return filtered.sorted { lhs, rhs in
                let l = valueReads[lhs.id]?.delta ?? Int.min
                let r = valueReads[rhs.id]?.delta ?? Int.min
                if l != r { return l > r }
                return boardCompositeScore(for: lhs) > boardCompositeScore(for: rhs)
            }
        case .overall:
            return filtered.sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
        case .position:
            return filtered.sorted {
                let ai = Position.allCases.firstIndex(of: $0.position) ?? 0
                let bi = Position.allCases.firstIndex(of: $1.position) ?? 0
                if ai != bi { return ai < bi }
                return ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0)
            }
        case .tier:
            return filtered.sorted {
                let t0 = boardTier(for: $0)
                let t1 = boardTier(for: $1)
                if t0 != t1 { return t0 < t1 }
                return boardCompositeScore(for: $0) > boardCompositeScore(for: $1)
            }
        case .schemeFit:
            return filtered.sorted {
                let fitA = schemeFitLabel(for: $0)
                let fitB = schemeFitLabel(for: $1)
                return schemeFitRank(fitA) < schemeFitRank(fitB)
            }
        case .risk:
            return filtered.sorted {
                let riskRankA = riskSortRank($0.riskLevel)
                let riskRankB = riskSortRank($1.riskLevel)
                if riskRankA != riskRankB { return riskRankA < riskRankB }
                return ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0)
            }
        case .production:
            return filtered.sorted {
                let prodA = $0.collegeProductionTier.sortRank
                let prodB = $1.collegeProductionTier.sortRank
                if prodA != prodB { return prodA < prodB }
                return ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0)
            }
        case .footballIQ:
            // Fog-safe: `IQRead.rank` puts the interview's number and the
            // scouts' tape band on one scale and floors "no intel" at zero, so
            // the sort cannot leak a mind the user has not read.
            return filtered.sorted {
                let iqA = ProspectFog.iqRank($0)
                let iqB = ProspectFog.iqRank($1)
                if iqA != iqB { return iqA > iqB }
                return ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0)
            }
        }
    }

    private func schemeFitRank(_ fit: String?) -> Int {
        switch fit {
        case "Good": return 0
        case "Fair": return 1
        case "Poor": return 2
        default:     return 3
        }
    }

    private func riskSortRank(_ risk: ProspectRiskLevel) -> Int {
        switch risk {
        case .boomOrBust:  return 0
        case .highCeiling: return 1
        case .safePick:    return 2
        case .unknown:     return 3
        }
    }

    /// "My Board" — the persisted user order, grouped by mark tier.
    private var customOrderedBoard: [CollegeProspect] {
        applyBoardOrder(filteredProspects).sorted {
            $0.userMark.sortRank < $1.userMark.sortRank
        }
    }

    /// My Board split into its mark-tier sections, each preserving the stored
    /// order inside itself. Empty tiers are dropped.
    private var markGroupedBoard: [(tier: ProspectMarkTier, prospects: [CollegeProspect])] {
        let ordered = applyBoardOrder(filteredProspects)
        var grouped: [ProspectMarkTier: [CollegeProspect]] = [:]
        for prospect in ordered { grouped[prospect.userMark, default: []].append(prospect) }
        return ProspectMarkTier.allCases
            .sorted { $0.sortRank < $1.sortRank }
            .compactMap { tier in
                guard let group = grouped[tier], !group.isEmpty else { return nil }
                return (tier: tier, prospects: group)
            }
    }

    /// Maximum number of same-position prospects allowed per tier.

    /// Prospects grouped by tier, maintaining board order within each tier.
    /// Enforces position diversity: max 4 of same position per tier.
    /// Overflow prospects are pushed to the next tier down.
    private func tieredBoard(from board: [CollegeProspect]) -> [(tier: Int, prospects: [CollegeProspect])] {
        // First pass: assign tiers based on composite score
        var tierAssignments: [(prospect: CollegeProspect, tier: Int)] = board.map { ($0, boardTier(for: $0)) }

        // Sort by tier then composite score descending within tier
        tierAssignments.sort {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            return boardCompositeScore(for: $0.prospect) > boardCompositeScore(for: $1.prospect)
        }

        // Second pass: enforce position diversity (max 4 per position per tier)
        var positionCountPerTier: [Int: [Position: Int]] = [:]
        var finalAssignments: [(prospect: CollegeProspect, tier: Int)] = []

        for entry in tierAssignments {
            var assignedTier = entry.tier
            let pos = entry.prospect.position

            // Check if this position already has max count in the assigned tier
            while assignedTier <= 7 {
                let count = positionCountPerTier[assignedTier, default: [:]][pos, default: 0]
                if count < bigBoardMaxSamePositionPerTier {
                    break
                }
                assignedTier += 1
            }
            // Clamp to tier 7 max
            assignedTier = min(assignedTier, 7)

            positionCountPerTier[assignedTier, default: [:]][pos, default: 0] += 1
            finalAssignments.append((entry.prospect, assignedTier))
        }

        // Group by final tier
        var grouped: [Int: [CollegeProspect]] = [:]
        for entry in finalAssignments {
            grouped[entry.tier, default: []].append(entry.prospect)
        }

        return (1...7).compactMap { tier in
            guard let group = grouped[tier], !group.isEmpty else { return nil }
            return (tier: tier, prospects: group)
        }
    }

    // MARK: - Need-Based Recommendations

    private var teamNeeds: [Position] {
        DraftEngine.topTeamNeeds(roster: teamRoster, limit: 3)
    }

    private var topNeedPosition: Position? {
        teamNeeds.first
    }

    private var bestAtNeed: CollegeProspect? {
        guard let need = topNeedPosition else { return nil }
        return scoutedProspects
            .filter { $0.position == need }
            .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
            .first
    }

    private var bestPlayerAvailable: CollegeProspect? {
        scoutedProspects
            .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
            .first
    }

    private var teamNeedPositions: Set<Position> {
        guard !teamRoster.isEmpty else { return [] }
        return Set(teamNeeds)
    }

    /// Best available prospect on the board for a given position.
    private func bestAvailableForPosition(_ pos: Position) -> CollegeProspect? {
        scoutedProspects
            .filter { $0.position == pos }
            .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
            .first
    }

    /// Grade text for a prospect — the stored band, else the letter its scouted
    /// overall implies, else nothing at all.
    ///
    /// The old last resort was `LetterGrade.from(numericValue: … ?? trueOverall)`,
    /// which would have printed the generator's grade for a man nobody had filed
    /// on. Unreachable behind the `scoutedProspects` filter, and removed for the
    /// same reason `boardCompositeScore`'s twin was: fail soft, never fall back
    /// to the truth.
    private func bestAvailableGradeText(_ prospect: CollegeProspect) -> String {
        if let gradeRange = prospect.scoutedOverallGrade {
            return gradeRange.displayText
        }
        guard let scouted = prospect.scoutedOverall else { return "\u{2014}" }
        return LetterGrade.from(numericValue: scouted).rawValue
    }

    /// Format the team's draft picks for display.
    private var draftPicksSummary: String {
        let sorted = teamDraftPicks
            .filter { !$0.isComplete }
            .sorted { $0.pickNumber < $1.pickNumber }
        if sorted.isEmpty { return "No picks" }
        return sorted.map { "Rd \($0.round) #\($0.pickNumber)" }.joined(separator: ", ")
    }

    // MARK: - Body

    private func refreshCachedBoard() {
        // Value reads first: the `.valueDelta` sort reads them, so they have to
        // exist before `orderedBoard` runs.
        var reads: [UUID: ProspectFog.ValueRead] = [:]
        for prospect in scoutedProspects {
            if let read = ProspectFog.valueRead(
                for: prospect,
                marketRank: marketRank(for: prospect),
                myGrade: userGradeStore.grade(for: prospect.id)
            ) {
                reads[prospect.id] = read
            }
        }
        cachedValueReads = reads

        let ordered = orderedBoard(valueReads: reads)
        let custom = customOrderedBoard
        cachedOrderedBoard = ordered
        cachedCustomOrderedBoard = custom
        cachedMarkGroups = markGroupedBoard
        cachedTieredBoard = tieredBoard(from: ordered)
        // Build O(1) rank lookup tables once per refresh.
        var rankMap: [UUID: Int] = [:]
        rankMap.reserveCapacity(ordered.count)
        for (idx, p) in ordered.enumerated() { rankMap[p.id] = idx + 1 }
        cachedRankMap = rankMap

        // My Board prints the BOARD SLOT, not a position inside the section it
        // happens to be rendered in. The war room and the pick sheet both say
        // "MY #N is the slot the Big Board prints" — and it was not: this map
        // used to be an index into `cachedCustomOrderedBoard`, i.e. the current
        // FILTER re-sorted by mark tier, so marking three men `elite` printed
        // them #1/#2/#3 here while the draft room printed #4/#19/#41. One
        // reader now, shared with `DraftDayCoordinator` and `MockDraftView`.
        cachedCustomRankMap = UserDraftBoard.slotMap(among: prospects)
    }

    // MARK: - Board Row

    /// One row, shared by the scout board and My Board — they differ only in
    /// which rank they print, and having two copies is how the mark button and
    /// the value chip ended up on one of them and not the other.
    @ViewBuilder
    private func boardRow(
        prospect: CollegeProspect,
        rank: Int,
        totalCount: Int,
        showsMovement: Bool
    ) -> some View {
        HStack(spacing: 0) {
            ProspectMarkButton(
                prospect: prospect,
                onChange: {
                    try? modelContext.save()
                    refreshCachedBoard()
                },
                onEditNote: { editingMarkNoteProspect = prospect }
            )

            NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                BigBoardRowView(
                    rank: rank,
                    totalCount: totalCount,
                    prospect: prospect,
                    ownGrade: prospectOwnAssessments[prospect.id.uuidString],
                    schemeFit: schemeFitLabel(for: prospect),
                    needLevel: needLevel(for: prospect.position),
                    starterComparison: starterComparison(for: prospect),
                    attributeTab: attributeTab,
                    scoutsSentToCombine: scoutsSentToCombine,
                    percentilePools: percentilePools,
                    isPositionNeed: teamNeedPositions.contains(prospect.position),
                    projectedRound: boardProjectedRound(for: prospect),
                    isValuePick: isValuePick(prospect),
                    valueRead: valueRead(for: prospect),
                    originalPosition: showsMovement
                        ? userGradeStore.getOriginalPosition(for: prospect.id)
                        : nil,
                    isSelectedForCompare: isSelectedForCompare(prospect),
                    userTeamID: career.teamID,
                    hidesPositionBadge: positionFilter != .all,
                    onGradeTap: { editingAssessmentProspect = prospect }
                )
            }

            if isFilmStudy {
                filmStudyButton(for: prospect)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
        .contextMenu {
            tierContextMenu(for: prospect)
        }
    }

    /// The film-study stage's row action: one tap orders tape on this man.
    ///
    /// Priced and rationed exactly as the prospect card's button is — the price
    /// is on the button, and a blocked button says why rather than going
    /// quietly grey.
    @ViewBuilder
    private func filmStudyButton(for prospect: CollegeProspect) -> some View {
        let availability = filmAvailability(for: prospect)
        let filed = prospect.scoutingReports.count
        Button {
            orderFilmStudy(on: prospect)
        } label: {
            VStack(spacing: 1) {
                Image(systemName: filed >= ScoutEvaluationBudget.maxReportsPerProspect
                      ? "checkmark.seal.fill"
                      : "doc.text.magnifyingglass")
                    .font(.system(size: 13))
                Text(filmButtonCaption(availability, filed: filed))
                    .font(.system(size: 7, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(availability.isAvailable ? Color.accentGold : Color.textTertiary)
            .frame(width: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!availability.isAvailable)
        .accessibilityLabel("Order film study on \(prospect.fullName)")
        .accessibilityHint(filmAccessibilityHint(availability, filed: filed))
    }

    private func filmButtonCaption(_ availability: ScoutEvaluationAvailability, filed: Int) -> String {
        switch availability {
        case let .available(cost, _): return "$\(cost)K"
        case .reportsMaxed:           return "DONE"
        default:                      return "\(filed)/\(ScoutEvaluationBudget.maxReportsPerProspect)"
        }
    }

    private func filmAccessibilityHint(_ availability: ScoutEvaluationAvailability, filed: Int) -> String {
        switch availability {
        case let .available(cost, slotsLeft):
            return "$\(cost)K, \(slotsLeft) of \(ScoutEvaluationBudget.slotsPerCycle) evaluations left this cycle"
        case let .windowShut(hint):
            return hint
        case .noScouts:
            return "No scouts on staff \u{2014} hire one from the Scout Team tab."
        case .slotsSpent:
            return "All \(ScoutEvaluationBudget.slotsPerCycle) evaluations are spent this cycle."
        case .reportsMaxed:
            return "Three reports filed \u{2014} your department has seen everything it is going to see."
        case let .cannotAfford(cost, remaining):
            return "Needs $\(cost)K \u{2014} only $\(remaining)K left in the scouting budget."
        }
    }

    // MARK: - Compare tray

    private func isSelectedForCompare(_ prospect: CollegeProspect) -> Bool {
        compareSelection.contains { $0.id == prospect.id }
    }

    /// Adds or removes a man from the compare tray. Four is the cap: a fifth
    /// column does not fit a portrait iPad, and a five-way compare is not a
    /// decision anybody makes.
    private func toggleCompareSelection(_ prospect: CollegeProspect) {
        if let idx = compareSelection.firstIndex(where: { $0.id == prospect.id }) {
            compareSelection.remove(at: idx)
        } else {
            if compareSelection.count >= ProspectCompareSheet.maxProspects {
                compareSelection.removeFirst()
            }
            compareSelection.append(prospect)
        }
    }

    @ViewBuilder
    private var compareTrayBar: some View {
        if !compareSelection.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.caption)
                    .foregroundStyle(Color.accentBlue)
                Text(compareSelection.map(\.lastName).joined(separator: " \u{00B7} "))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Button("Clear") { compareSelection.removeAll() }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Button {
                    showCompareSheet = true
                } label: {
                    Text("Compare \(compareSelection.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(
                            compareSelection.count >= 2 ? Color.backgroundPrimary : Color.textTertiary
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            compareSelection.count >= 2 ? Color.accentBlue : Color.backgroundTertiary,
                            in: Capsule()
                        )
                }
                .disabled(compareSelection.count < 2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.backgroundTertiary)
        }
    }

    // MARK: - Mark group header (My Board)

    private func markGroupHeader(tier: ProspectMarkTier, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: tier.icon)
                .font(.caption)
                .foregroundStyle(tier.color)
            Text(tier == .none ? "Unmarked" : tier.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(tier.color)
                .textCase(nil)
            Text("\(count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.backgroundSecondary, in: Capsule())
            Text(tier.blurb)
                .font(.system(size: 8))
                .foregroundStyle(Color.textTertiary)
                .textCase(nil)
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentBlue)
                    Text("Loading Big Board...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 0) {
                    // Search bar (#9)
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                            TextField("Search prospects...", text: $searchText)
                                .font(.subheadline)
                                .foregroundStyle(Color.textPrimary)
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.textTertiary)
                                }
                                .accessibilityLabel("Clear search")
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))

                        // Filter button (#10)
                        Menu {
                            // Round range
                            Menu("Projected Round") {
                                ForEach(1...8, id: \.self) { rd in
                                    let label = rd <= 7 ? "Rd \(rd)+" : "UDFA+"
                                    Button(label) { filterProjectedRoundMin = rd }
                                }
                                Divider()
                                Button("Reset Round Filter") {
                                    filterProjectedRoundMin = 1
                                    filterProjectedRoundMax = 8
                                }
                            }
                            // Risk
                            Menu("Risk Level") {
                                Button("All Risks") { filterRisk = nil }
                                Button("Boom/Bust") { filterRisk = .boomOrBust }
                                Button("High Ceiling") { filterRisk = .highCeiling }
                                Button("Safe Pick") { filterRisk = .safePick }
                            }
                            Divider()
                            // My Grade filters
                            Button(showMarkedOnly ? "Show All (not just marked)" : "Marked Only") {
                                showMarkedOnly.toggle()
                            }
                            Button(filterMyGradeFirstRound ? "Show All Grades" : "My Grade: 1st Round+") {
                                filterMyGradeFirstRound.toggle()
                            }
                            Divider()
                            Button("Clear All Filters") {
                                filterProjectedRoundMin = 1
                                filterProjectedRoundMax = 8
                                filterRisk = nil
                                positionFilter = .all
                                markFilter = .all
                                showMarkedOnly = false
                                filterMyGradeFirstRound = false
                                searchText = ""
                            }
                        } label: {
                            let hasActiveFilter = filterProjectedRoundMin > 1 || filterProjectedRoundMax < 8 || filterRisk != nil || showMarkedOnly || filterMyGradeFirstRound
                            Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.body)
                                .foregroundStyle(hasActiveFilter ? Color.accentBlue : Color.textSecondary)
                        }
                        .accessibilityLabel("Filter prospects")

                        // Board-order actions. The old single "auto-rank by
                        // composite score" button wrote to a `@State` array
                        // nothing persisted, so the board it produced lived
                        // exactly as long as the screen did.
                        Menu {
                            Button {
                                autoRankFromMyGrades()
                            } label: {
                                Label("Auto-rank From My Grades", systemImage: "person.crop.circle.badge.checkmark")
                            }
                            Button {
                                autoRankBoard()
                            } label: {
                                Label("Auto-rank By Scout Score", systemImage: "arrow.up.arrow.down")
                            }
                            Divider()
                            Button(role: .destructive) {
                                resetBoardToConsensus()
                            } label: {
                                Label("Reset to Consensus", systemImage: "arrow.counterclockwise")
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.body)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .accessibilityLabel("Board order actions")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .background(Color.backgroundPrimary)

                    bigBoardAttributeTabPicker

                    compareTrayBar

                    if !scoutedProspects.isEmpty {
                        // Insets MIRROR the rows' `listRowInsets` (leading 8 /
                        // trailing 16) so each label sits over its own column.
                        bigBoardColumnHeaders
                            .padding(.leading, 8)
                            .padding(.trailing, 16)
                            .padding(.vertical, 3)
                            .background(Color.backgroundPrimary)

                        Divider().overlay(Color.surfaceBorder)
                    }

                    List {
                        // The hub header, as this list's FIRST SECTION. One
                        // scroll owner, one gesture: scrolling the board scrolls
                        // the metrics strip and the prep card off the screen
                        // instead of leaving them parked over it.
                        Section {
                            header()
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                        if scoutedProspects.isEmpty {
                            Section {
                                emptyState
                                    .frame(minHeight: 260)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else {
                        recommendationsSection
                        depthAnalysisSection
                        if showBoardComparison {
                            boardComparisonSection
                        }
                        if showMyBoard {
                            // My Board: the persisted order, broken on the mark
                            // tier. A verdict written on a prospect card is
                            // structure here two taps later.
                            ForEach(cachedMarkGroups, id: \.tier) { group in
                                Section {
                                    ForEach(group.prospects) { prospect in
                                        boardRow(
                                            prospect: prospect,
                                            rank: customRankFor(prospect),
                                            // The whole board, not this section:
                                            // the rank printed is now the board
                                            // SLOT, so "#41 of 12" would be the
                                            // old, section-relative reading.
                                            totalCount: cachedCustomRankMap.count,
                                            // The movement badge measures the
                                            // scout board's tier order, which is
                                            // not what these sections show.
                                            showsMovement: false
                                        )
                                    }
                                    .onMove { from, to in
                                        reorderSection(
                                            ids: group.prospects.map(\.id),
                                            from: from,
                                            to: to
                                        )
                                    }
                                } header: {
                                    markGroupHeader(tier: group.tier, count: group.prospects.count)
                                }
                            }
                        } else {
                            // Scout tiered board
                            ForEach(cachedTieredBoard, id: \.tier) { tierGroup in
                                Section {
                                    ForEach(tierGroup.prospects) { prospect in
                                        boardRow(
                                            prospect: prospect,
                                            rank: rankFor(prospect),
                                            totalCount: cachedOrderedBoard.count,
                                            showsMovement: showsBoardMovement
                                        )
                                    }
                                    .onMove { from, to in
                                        reorderSection(
                                            ids: tierGroup.prospects.map(\.id),
                                            from: from,
                                            to: to
                                        )
                                    }
                                } header: {
                                    tierHeader(tier: tierGroup.tier, count: tierGroup.prospects.count)
                                }
                            }
                        }
                        } // end else (board has men on it)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
        }
        .sheet(item: $editingAssessmentProspect) { prospect in
            prospectAssessmentSheet(prospect: prospect)
        }
        .sheet(item: $editingNoteProspect) { prospect in
            prospectNoteSheet(prospect: prospect)
        }
        .sheet(item: $editingMarkNoteProspect) { prospect in
            ProspectMarkNoteSheet(
                prospectName: prospect.fullName,
                initialNote: prospect.userMarkNote,
                onSave: { note in
                    // A note is a verdict too: writing one on an unmarked man
                    // puts him on the board as a target rather than leaving the
                    // text stranded on a prospect nothing tracks.
                    prospect.setUserMark(prospect.isMarked ? prospect.userMark : .target, note: note)
                    try? modelContext.save()
                    editingMarkNoteProspect = nil
                    refreshCachedBoard()
                },
                onCancel: { editingMarkNoteProspect = nil }
            )
        }
        .sheet(isPresented: $showCompareSheet) {
            if compareSelection.count >= 2 {
                ProspectCompareSheet(
                    career: career,
                    prospects: compareSelection,
                    schemeFits: Dictionary(
                        uniqueKeysWithValues: compareSelection.compactMap { prospect in
                            schemeFitLabel(for: prospect).map { (prospect.id, $0) }
                        }
                    ),
                    starterComparisons: Dictionary(
                        uniqueKeysWithValues: compareSelection.compactMap { prospect in
                            starterComparison(for: prospect).map { (prospect.id, $0) }
                        }
                    ),
                    onDismiss: { showCompareSheet = false }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                boardFilterControls
            }
            // #9: Sort menu
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Sort by", selection: $boardSortOrder) {
                        ForEach(BigBoardSort.allCases) { sort in
                            Label(sort.label, systemImage: sort.icon).tag(sort)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundStyle(boardSortOrder == .boardRank ? Color.textSecondary : Color.accentBlue)
                }
                .accessibilityLabel("Sort by, currently \(boardSortOrder.label)")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMyBoard.toggle()
                } label: {
                    Text(showMyBoard ? "My Board" : "Scout Board")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(showMyBoard ? Color.accentGold : Color.textSecondary)
                }
                .accessibilityHint("Switch between your custom-ranked board and the scouts' board")
            }
            // #2: MyBoard vs Media Board comparison toggle
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showBoardComparison.toggle()
                    }
                } label: {
                    Image(systemName: showBoardComparison ? "arrow.left.arrow.right.circle.fill" : "arrow.left.arrow.right.circle")
                        .foregroundStyle(showBoardComparison ? Color.accentBlue : Color.textSecondary)
                }
                .accessibilityLabel(showBoardComparison ? "Hide media comparison" : "Show media comparison")
            }
        }
        .task {
            // One mark system: fold the legacy star / flag / bookmark opinions
            // into `userMarkTier` before anything reads it.
            let migrated = CollegeProspect.migrateLegacyMarks(
                in: prospects,
                watchlistIDs: legacyWatchlistIDs
            )
            if migrated > 0 { try? modelContext.save() }

            // Publish the media consensus board so `DraftIntel.consensusRank`
            // answers for this class — the seed order and every value chip on
            // this screen read it, and it is a per-session cache, not a save.
            DraftIntel.refreshConsensusBoard(for: prospects)

            // Seed the persisted board from the media consensus on first open,
            // and take in anyone scouted since the last visit.
            syncBoardOrder()
            recordOriginalPositions()
            loadCoaches()
            loadDraftPicks()
            loadScoutingDepartment()
            attributeTab = initialAttributeTab ?? defaultAttributeTab
            rebuildPercentilePools()
            refreshCachedBoard()
            isLoading = false
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                debouncedSearchText = newValue
                refreshCachedBoard()
            }
        }
        .onChange(of: positionFilter) { _, _ in refreshCachedBoard() }
        .onChange(of: markFilter) { _, _ in refreshCachedBoard() }
        .onChange(of: boardSortOrder) { _, _ in refreshCachedBoard() }
        .onChange(of: showMyBoard) { _, _ in refreshCachedBoard() }
        .onChange(of: showMarkedOnly) { _, _ in refreshCachedBoard() }
        .onChange(of: filterProjectedRoundMin) { _, _ in refreshCachedBoard() }
        .onChange(of: filterProjectedRoundMax) { _, _ in refreshCachedBoard() }
        .onChange(of: filterRisk) { _, _ in refreshCachedBoard() }
        .onChange(of: filterMyGradeFirstRound) { _, _ in refreshCachedBoard() }
    }

    // MARK: - Attribute Tab Picker (Capsule-style)
    //
    // The control itself moved to `ProspectListControls.swift` so the combine
    // table wears the same one. The position chips stay switched OFF here: the
    // hub draws them above the whole tab strip already, and `positionFilter` is
    // passed through only so the board and the shared control agree on which
    // binding the chips would write if a future host turned them on.

    /// Which block the board opens on when the host has no opinion.
    ///
    /// Combine week, the question the user came to this screen with is "what did
    /// he run" — the numbers land that week and they are the only new
    /// information on the board — so the board opens on the drills instead of
    /// making him find the mode chip first. Every other phase opens on Overview,
    /// which is the block that answers "who is he".
    ///
    /// Two signals, because the phase and the prep stage do not move together: a
    /// save can sit in `DraftPrepStep.combineReview` — the stage whose whole job
    /// is reading the numbers — after `SeasonPhase.combine` has rolled over.
    ///
    /// The host can still override: `initialAttributeTab` wins whenever it is
    /// non-`nil`, which is how the film-study stage keeps its `.workup`.
    private var defaultAttributeTab: ProspectAttributeTab {
        if career.currentPhase == .combine { return .physical }
        if career.prepStep == .combineReview { return .physical }
        return .overview
    }

    /// The position-relative pool the Physical block ranks drill results
    /// against, built ONCE per open rather than per row: it is a full sort of
    /// every measurement in the class, and this list is 350 rows deep.
    ///
    /// Built from the whole class rather than from the combine invitee list the
    /// combine table uses. The two produce the same numbers in practice —
    /// `PercentilePools` only collects non-`nil` measurements, and a man with a
    /// 40 time on file is in both populations — while this one also ranks a
    /// pro-day riser the combine table's invitee filter drops.
    private func rebuildPercentilePools() {
        percentilePools = PercentilePools(prospects: prospects)
    }

    private var bigBoardAttributeTabPicker: some View {
        ProspectListControls(
            positionFilter: $positionFilter,
            mode: $attributeTab,
            modes: ProspectAttributeTab.allCases,
            showsPositionChips: false
        )
    }

    // MARK: - Column Headers

    @ViewBuilder
    private var bigBoardColumnHeaders: some View {
        HStack(spacing: 0) {
            // Leading star-button column (44 pt): unlabelled, but in every row.
            Spacer().frame(width: 44)

            // Rank. The "/350" denominator that used to print under every one
            // of these numbers is gone — same value on every row, at 6 pt.
            Text("#")
                .frame(width: 24, alignment: .center)

            // POS — drawn only when the rows draw it, i.e. when the hub's
            // position chips are NOT already scoping the board to one group.
            if positionFilter == .all {
                Text("POS")
                    .frame(width: 36, alignment: .center)
            }

            // Portrait column — unlabelled, but reserved so the header keeps
            // matching the row (30 pt `PersonFaceView` + 6 pt leading padding).
            Spacer().frame(width: 36)

            // NAME
            Text("NAME")
                .frame(minWidth: 80, alignment: .leading)
                .padding(.leading, 6)

            // OVR — leading, beside the name, in every mode. Mirrors the row's
            // `boardOverallBadge`, same 50 pt.
            HStack(spacing: 2) {
                Text("OVR")
                InfoTooltipButton(
                    text: "Scout's read on the prospect. When you have logged your own grade you'll see \"Yours / Scout\" \u{2014} a wider gap means more uncertainty in the scout's evaluation. Letter grades use the standard A-F tiers (see legend).",
                    showLetterGradeKey: true,
                    size: 9
                )
            }
            .frame(width: 50, alignment: .center)

            Spacer(minLength: 2)

            // Tab-specific headers — the shared vocabulary, so the board, the
            // combine table and the two selection lists label the same columns
            // with the same words at the same widths.
            ProspectColumns.headers(mode: attributeTab)

            // Always-visible: TAPE and MEET, in two columns.
            //
            // They shared one 40-point column until this pass, because
            // `ProspectFog.footballIQ` is a precedence function — the interview
            // number wins and the scouts' band is the fallback — so a board row
            // printed `86 MEET` next to `C-/B+ TAPE` and asked the user to
            // compare a number with a letter in the same strip. Two instruments,
            // two questions, two columns.
            HStack(spacing: 2) {
                Text("TAPE")
                InfoTooltipButton(
                    text: "What your scouting department has on his head off tape \u{2014} a band off awareness and learning, and only as tight as the reports you have paid for. A dash means nobody in your building has filed on him.",
                    size: 9
                )
            }
            .frame(width: 42, alignment: .center)

            HStack(spacing: 2) {
                Text("MEET")
                InfoTooltipButton(
                    text: "What your own people got out of him in a room. An exact football-IQ number, because that is what a meeting produces. A dash means you have not spent an interview slot on him.",
                    size: 9
                )
            }
            .frame(width: 38, alignment: .center)

            // Always-visible: value vs the user's own grade. Blank for anyone
            // he has not graded — the column is a read on HIS opinion, and
            // there is no honest number to print without one.
            HStack(spacing: 2) {
                Text("VAL")
                InfoTooltipButton(
                    text: "Value versus your own grade. The market number is media consensus \u{2014} the latest mock's pick and the projected round, never your scouts' read. A green +18 means the board will let him fall eighteen picks past where you have him; an amber \u{2212}12 means taking him where you rate him is a reach. Blank until you grade him.",
                    size: 9
                )
            }
            .frame(width: 34, alignment: .center)

            // OVR moved LEADING, beside NAME — see the block above.

            // Always-visible: Proj Rd (overview) or Grade (others)
            if attributeTab == .overview {
                Text("PROJ")
                    .frame(width: 52, alignment: .center)
            } else {
                HStack(spacing: 2) {
                    Text("GRD")
                    InfoTooltipButton(
                        text: "Letter grade summarizes the scout's overall evaluation. A = elite / first-round talent, B = quality starter, C = average, D = back-end roster, F = undraftable.",
                        showLetterGradeKey: true,
                        size: 9
                    )
                }
                .frame(width: 30, alignment: .center)
            }

            // Drag handle spacer
            Text("")
                .frame(width: 22)
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
        .textCase(.uppercase)
    }

    // The five per-mode header blocks moved to `ProspectColumns.headers` in
    // `ProspectListControls.swift`, beside the cells they label.

    // MARK: - Recommendations Section (#216)

    private var recommendationsSection: some View {
        Section {
            if let need = topNeedPosition {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.warning)
                        .font(.caption)
                    Text("Your #1 need: **\(need.rawValue)** (weakest group)")
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
                .listRowBackground(Color.backgroundSecondary)
            }

            if let prospect = bestAtNeed, let need = topNeedPosition {
                HStack(spacing: 10) {
                    Image(systemName: "target")
                        .foregroundStyle(Color.success)
                        .font(.caption)
                    Text("Best available at \(need.rawValue): **\(prospect.fullName)** (Tier \(prospect.scoutedTier))")
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
                .listRowBackground(Color.backgroundSecondary)
            }

            if let prospect = bestPlayerAvailable {
                HStack(spacing: 10) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color.accentGold)
                        .font(.caption)
                    Text("Best player available: **\(prospect.fullName)** (Tier \(prospect.scoutedTier))")
                        .font(.subheadline)
                        .foregroundStyle(Color.textPrimary)
                }
                .listRowBackground(Color.backgroundSecondary)
            }

            // #71: Show team's draft picks
            HStack(spacing: 10) {
                Image(systemName: "list.number")
                    .foregroundStyle(Color.accentBlue)
                    .font(.caption)
                Text("Your picks: \(draftPicksSummary)")
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
            }
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            Label("Recommendations", systemImage: "lightbulb.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .textCase(nil)
        }
    }

    // MARK: - Depth Analysis (#227)

    /// Position needs mapped to how many are on the board vs how many are needed.
    private var positionDepthItems: [(position: Position, onBoard: Int, needed: Int)] {
        teamNeeds.map { pos in
            let onBoard = scoutedProspects.filter { $0.position == pos }.count
            // Estimate need count from roster deficit (1-3 range).
            let rosterCount = teamRoster.filter { $0.position == pos }.count
            let idealCounts: [Position: Int] = [
                .QB: 2, .RB: 3, .FB: 1, .WR: 5, .TE: 3,
                .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 2,
                .DE: 4, .DT: 3, .OLB: 4, .MLB: 2,
                .CB: 5, .FS: 2, .SS: 2, .K: 1, .P: 1
            ]
            let ideal = idealCounts[pos] ?? 2
            let needed = max(1, ideal - rosterCount)
            return (position: pos, onBoard: onBoard, needed: needed)
        }
    }

    private var mediaTopProspect: CollegeProspect? {
        // Media board = sorted by draftProjection (lowest = best).
        prospects
            .filter { $0.draftProjection != nil }
            .sorted { ($0.draftProjection ?? Int.max) < ($1.draftProjection ?? Int.max) }
            .first
    }

    /// Map a Position to its EvalPositionGroup id for roster priority lookup.
    private func positionGroupID(for position: Position) -> String {
        switch position {
        case .QB: return "QB"
        case .RB, .FB: return "RB"
        case .WR: return "WR"
        case .TE: return "TE"
        case .LT, .LG, .C, .RG, .RT: return "OL"
        case .DE, .DT: return "DL"
        case .OLB, .MLB: return "LB"
        case .CB, .FS, .SS: return "DB"
        case .K, .P: return "ST"
        }
    }

    /// User's priority positions from Roster Evaluation, formatted for display.
    ///
    /// HIGH only, top-3: Auto-Set Priorities stamps every group with SOME
    /// priority, so listing everything non-"none" would read "Priority QB,
    /// RB, WR, TE, OL, DL, LB, DB, ST" — a signal with no information in it.
    /// This line is the counterpoint to the scouts' top-3 need call above it.
    private var userPriorityPositions: [String] {
        Array(
            rosterPriorities
                .filter { $0.value == "high" }
                .map { $0.key }
                .sorted()   // dictionary order is unstable frame to frame
                .prefix(3)
        )
    }

    private func priorityRank(_ priority: String) -> Int {
        switch priority {
        case "high": return 0
        case "medium": return 1
        case "low": return 2
        default: return 3
        }
    }

    private var depthAnalysisSection: some View {
        Section {
            // Staff vs User needs comparison
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scout: Need \(teamNeeds.prefix(3).map { $0.rawValue }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                    if userPriorityPositions.isEmpty {
                        Text("You: Set your priorities in Roster Evaluation")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Text("You: Priority \(userPriorityPositions.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Color.accentBlue)
                    }
                }
            }
            .listRowBackground(Color.backgroundSecondary)

            // Position depth summary
            ForEach(positionDepthItems, id: \.position) { item in
                HStack(spacing: 8) {
                    Text(item.position.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 32)

                    let sufficient = item.onBoard >= item.needed
                    Text("\(item.onBoard) on board (need \(item.needed))")
                        .font(.caption)
                        .foregroundStyle(sufficient ? Color.success : Color.warning)

                    Text(sufficient ? "\u{2713}" : "\u{26A0}\u{FE0F}")
                        .font(.caption)

                    // #72: Best available prospect for this position need
                    if let best = bestAvailableForPosition(item.position) {
                        Text("Best: \(best.lastName) (\(bestAvailableGradeText(best)))")
                            .font(.caption2)
                            .foregroundStyle(Color.textSecondary)
                    }

                    let groupID = positionGroupID(for: item.position)
                    if let userPriority = rosterPriorities[groupID], userPriority != "none" {
                        Text("You: \(userPriority)")
                            .font(.caption2)
                            .foregroundStyle(userPriority == "high" ? Color.danger : userPriority == "medium" ? Color.warning : Color.accentBlue)
                            .padding(.horizontal, 4)
                            .background(Color.backgroundTertiary, in: Capsule())
                    }
                }
                .listRowBackground(Color.backgroundSecondary)
            }

            // Your #1 vs Media #1 comparison (#15)
            if let myTop = cachedOrderedBoard.first, let mediaTop = mediaTopProspect {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption)
                            .foregroundStyle(Color.accentBlue)

                        if myTop.id == mediaTop.id {
                            Text("Your #1 matches media consensus: **\(myTop.fullName)**")
                                .font(.caption)
                                .foregroundStyle(Color.textPrimary)
                        } else {
                            Text("Your #1: **\(myTop.fullName)** vs Media #1: **\(mediaTop.fullName)**")
                                .font(.caption)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                    // Media projection for #1 (#15)
                    if let proj = mediaTop.draftProjection {
                        Text("Media projects \(mediaTop.lastName) at Pick #\(proj <= 3 ? proj : proj * 5)")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                            .padding(.leading, 26)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)
            }

            // Available at your pick probability (#18)
            if let myTop = cachedOrderedBoard.first,
               let prob = availableAtPickProbability(for: myTop),
               let firstPick = teamDraftPicks.filter({ !$0.isComplete }).sorted(by: { $0.pickNumber < $1.pickNumber }).first {
                HStack(spacing: 8) {
                    Image(systemName: "percent")
                        .font(.caption)
                        .foregroundStyle(Color.accentBlue)
                    Text("**\(myTop.lastName)** available at Rd \(firstPick.round) #\(firstPick.pickNumber): \(Int(prob * 100))%")
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                }
                .listRowBackground(Color.backgroundSecondary)
            }
        } header: {
            Label("Position Depth Analysis", systemImage: "chart.bar.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentBlue)
                .textCase(nil)
        }
    }

    // MARK: - #2: Board Comparison Section (MyBoard vs Media Board)

    /// Disagreements between user's board rank and media's draft projection.
    /// Returns prospects where the rank gap suggests a meaningful disagreement.
    private struct BoardComparisonEntry: Identifiable {
        let id: UUID
        let prospect: CollegeProspect
        let myRank: Int
        let mediaPick: Int
        let gap: Int           // myRank - mediaPick (negative = user has higher than media)
        let direction: Direction

        enum Direction {
            case userHigher    // user ranks them better than media
            case mediaHigher   // media ranks them better than user
        }
    }

    private var boardComparisonEntries: [BoardComparisonEntry] {
        let board = showMyBoard ? cachedCustomOrderedBoard : cachedOrderedBoard
        var entries: [BoardComparisonEntry] = []
        for (index, prospect) in board.enumerated() {
            // On My Board the row's own number is the board SLOT, so the diff
            // has to compare the same number the row prints — an enumeration
            // index would make "You: #3 Media: ~#48" out of a man the row
            // itself labels #41.
            let myRank = showMyBoard ? (customRankFor(prospect) == 0 ? index + 1 : customRankFor(prospect)) : index + 1
            // Use round-based projection scaled to a pick number (heuristic).
            guard let projRound = prospect.draftProjection else { continue }
            // Estimate media pick number from round: round 1 = 1-32, round 2 = 33-64, etc.
            // Use mid-round position as a proxy.
            let mediaPick = (projRound - 1) * 32 + 16
            let gap = myRank - mediaPick
            // Only show meaningful disagreements (>= 12 picks apart).
            guard abs(gap) >= 12 else { continue }
            let direction: BoardComparisonEntry.Direction = gap < 0 ? .userHigher : .mediaHigher
            entries.append(BoardComparisonEntry(
                id: prospect.id,
                prospect: prospect,
                myRank: myRank,
                mediaPick: mediaPick,
                gap: gap,
                direction: direction
            ))
        }
        // Sort by absolute gap descending, take top 8.
        return entries
            .sorted { abs($0.gap) > abs($1.gap) }
            .prefix(8)
            .map { $0 }
    }

    @ViewBuilder
    private var boardComparisonSection: some View {
        let entries = boardComparisonEntries
        Section {
            if entries.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                        .font(.caption)
                    Text("Your board aligns with the media consensus.")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .listRowBackground(Color.backgroundSecondary)
            } else {
                // Summary header
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.accentBlue)
                        .font(.caption)
                    Text("\(entries.count) prospect\(entries.count == 1 ? "" : "s") rated very differently from media")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                }
                .listRowBackground(Color.backgroundSecondary)

                ForEach(entries) { entry in
                    boardComparisonRow(entry: entry)
                        .listRowBackground(Color.backgroundSecondary)
                }
            }
        } header: {
            Label("Board Diff: \(showMyBoard ? "My" : "Scout") vs Media", systemImage: "arrow.left.arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentBlue)
                .textCase(nil)
        }
    }

    private func boardComparisonRow(entry: BoardComparisonEntry) -> some View {
        let isUserHigher = entry.direction == .userHigher
        let icon = isUserHigher ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"
        let color: Color = isUserHigher ? Color.success : Color.warning
        let label = isUserHigher ? "You're high" : "Media's high"
        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)

            Text(entry.prospect.position.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(positionColorForProspect(entry.prospect), in: RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.prospect.fullName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("You: #\(entry.myRank)  Media: ~#\(entry.mediaPick)  (\(label) by \(abs(entry.gap)))")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()
        }
    }

    private func positionColorForProspect(_ prospect: CollegeProspect) -> Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue.opacity(0.3)
        case .defense:      return .danger.opacity(0.3)
        case .specialTeams: return .accentGold.opacity(0.3)
        }
    }

    // MARK: - Tier Header (#214)

    private func tierHeader(tier: Int, count: Int) -> some View {
        let tierIndex = min(tier - 1, bigBoardTierNames.count - 1)
        let tierProspects = cachedTieredBoard.first(where: { $0.tier == tier })?.prospects ?? []
        let needCount = tierProspects.filter { teamNeedPositions.contains($0.position) }.count
        let markedCount = tierProspects.filter(\.isMarked).count
        // Availability summary: prospects in this tier likely available at user's first pick (#1)
        let firstPick = teamDraftPicks
            .filter { !$0.isComplete }
            .sorted { $0.pickNumber < $1.pickNumber }
            .first
        let availableAtPickCount: Int? = firstPick.map { _ in
            tierProspects.filter { p in
                guard let prob = availableAtPickProbability(for: p) else { return false }
                return prob >= 0.5
            }.count
        }
        // Tier-level "available" probability rollup: average prob across tier prospects
        let tierAvailabilityProb: Double? = {
            guard firstPick != nil, !tierProspects.isEmpty else { return nil }
            let probs = tierProspects.compactMap { availableAtPickProbability(for: $0) }
            guard !probs.isEmpty else { return nil }
            return probs.reduce(0, +) / Double(probs.count)
        }()
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Circle()
                    .fill(bigBoardTierColors[tierIndex])
                    .frame(width: 10, height: 10)

                Text(bigBoardTierNames[tierIndex])
                    .font(.caption.weight(.bold))
                    .foregroundStyle(bigBoardTierColors[tierIndex])
                    .textCase(nil)

                Text("\(count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.backgroundSecondary, in: Capsule())

                // Tier summary (#16)
                if needCount > 0 {
                    Text("\(needCount) need")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.warning)
                }
                if markedCount > 0 {
                    HStack(spacing: 1) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 7))
                        Text("\(markedCount)")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentGold)
                    .accessibilityLabel("\(markedCount) marked")
                }
                // #1: Available at user's pick (probability rollup for tier)
                if let pick = firstPick,
                   let availCount = availableAtPickCount,
                   let avgProb = tierAvailabilityProb {
                    HStack(spacing: 2) {
                        Image(systemName: "percent")
                            .font(.system(size: 7))
                        Text("\(availCount)/\(count) avail @#\(pick.pickNumber) (\(Int(avgProb * 100))%)")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(avgProb >= 0.6 ? Color.success : (avgProb >= 0.3 ? Color.accentBlue : Color.warning))
                }
            }
            // Tier description (#8)
            Text(bigBoardTierDescriptions[tierIndex])
                .font(.system(size: 8))
                .foregroundStyle(Color.textTertiary)
                .textCase(nil)
        }
    }

    // MARK: - Tier Context Menu (#214)

    @ViewBuilder
    private func tierContextMenu(for prospect: CollegeProspect) -> some View {
        // The ONE mark, then the user's own draft grade.
        ProspectGradeContextMenu(
            prospect: prospect,
            onChange: {
                try? modelContext.save()
                refreshCachedBoard()
            },
            onEditNote: { editingMarkNoteProspect = prospect }
        )
        Divider()
        Button {
            toggleCompareSelection(prospect)
        } label: {
            Label(
                isSelectedForCompare(prospect) ? "Remove From Compare" : "Add to Compare",
                systemImage: "rectangle.on.rectangle.angled"
            )
        }
        Divider()
        // Tier movement (#17)
        ForEach(1...7, id: \.self) { tier in
            if tier != boardTier(for: prospect) {
                Button {
                    moveProspectToTier(prospect, tier: tier)
                } label: {
                    Label("Move to \(bigBoardTierNames[tier - 1])", systemImage: "arrow.right.circle")
                }
            }
        }
        Divider()
        // Move up / down in board (#17)
        Button {
            moveBoardPosition(prospect, direction: -1)
        } label: {
            Label("Move Up", systemImage: "arrow.up")
        }
        Button {
            moveBoardPosition(prospect, direction: 1)
        } label: {
            Label("Move Down", systemImage: "arrow.down")
        }
        // Reset to auto tier (only show if manually overridden)
        if prospect.manualTier != nil {
            Button {
                prospect.manualTier = nil
                try? modelContext.save()
                refreshCachedBoard()
            } label: {
                Label("Reset to Auto Tier", systemImage: "arrow.counterclockwise")
            }
        }
        Divider()
        // NO "move to round N" here any more (task #78).
        //
        // Those four buttons wrote `draftProjection`, which is the MEDIA's
        // projected round — not the user's board. Three things broke because of
        // it, and the market model this wave adds makes all three worse:
        //
        //  * `applyProjectionDrift` guarantees the class-wide multiset of
        //    projections is exactly preserved (every rise is paid for by a
        //    fall). A manual write is unpaired, so a user could mint round-1
        //    grades and quietly re-tune the whole draft;
        //  * `ProspectFog.consensusBand` and `DraftIntel.publicOVREstimate` /
        //    `consensusWindow` read it as "what the room thinks", so overwriting
        //    it made the STEAL / REACH / value chips compare the user's opinion
        //    against itself; and
        //  * `projectionAtGeneration` now anchors the market arrow, which would
        //    read as a media move that never happened.
        //
        // Everything the buttons were actually for is already above and below
        // this line: the seven tier moves (`manualTier`), Move Up / Move Down,
        // and the mark + user grade at the top of the menu — all of which are
        // the user's own board and are stored as such.
        Divider()
        // #11: Scouting scratch note (separate from the board note the mark
        // carries — this one is the long-form pad).
        Button {
            editingNoteProspect = prospect
        } label: {
            Label(
                prospectNotes[prospect.id.uuidString] != nil ? "Edit Scouting Note" : "Add Scouting Note",
                systemImage: "square.and.pencil"
            )
        }
    }

    // MARK: - Toolbar

    /// Board-only filters. The position chips used to live here too, in a
    /// `.principal` toolbar item that the hub's large title suppressed — they
    /// now sit in the hub's own bar, shared with the other tabs.
    private var boardFilterControls: some View {
        HStack(spacing: 12) {
            // Mark filter — the ONE mark system. This used to be a flag filter
            // over `prospectFlag`, one of four parallel opinions of the same
            // prospect; the other three were unreachable from here.
            Menu {
                Picker("Mark", selection: $markFilter) {
                    ForEach(ProspectMarkFilter.allCases) { filter in
                        Label(filter.label, systemImage: filter.icon).tag(filter)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: markFilter.icon)
                        .font(.caption)
                    Text(markFilter == .all ? "All Marks" : markFilter.label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(markFilter == .all ? Color.textSecondary : Color.accentGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Color.backgroundTertiary)
                )
                .fixedSize()
            }
            .accessibilityLabel("Filter by mark, \(markFilter.label)")

            Button {
                showMarkedOnly.toggle()
            } label: {
                Image(systemName: showMarkedOnly ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(showMarkedOnly ? Color.accentGold : Color.textSecondary)
            }
            .accessibilityLabel(showMarkedOnly ? "Show all prospects" : "Show marked prospects only")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        // The board can only fill up via scouting, so a bare "it's empty"
        // message left the user staring at a full-screen void with nothing to
        // press. Both routes out of the dead end are offered here.
        VStack(spacing: 16) {
            Image(systemName: "list.star")
                .font(.system(size: 52))
                .foregroundStyle(Color.textTertiary)

            Text("Big Board Is Empty")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text(emptyStateMessage)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 12) {
                emptyStateButton(
                    title: "Hire Scouts",
                    systemImage: "person.badge.plus",
                    isPrimary: scoutCount == 0
                ) { onSwitchTab?(.scouts) }

                emptyStateButton(
                    title: "Combine Numbers",
                    systemImage: "figure.run",
                    isPrimary: scoutCount > 0
                ) { onSwitchTab?(.combine) }
            }
            .padding(.top, 4)
            .opacity(onSwitchTab == nil ? 0 : 1)
            .disabled(onSwitchTab == nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMessage: String {
        if scoutCount == 0 {
            return "You have no scouts on staff, so nobody is filing reports. Hire a scout, then order film study to build your board."
        }
        return "Nobody in your building has filed on this class yet. Order film study at the film-study stage \u{2014} every report you pay for puts a man on this board."
    }

    private func emptyStateButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPrimary ? Color.backgroundPrimary : Color.textPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .fill(isPrimary ? Color.accentGold : Color.backgroundTertiary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(isPrimary ? Color.clear : Color.surfaceBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Assessment Sheet

    private func prospectAssessmentSheet(prospect: CollegeProspect) -> some View {
        let currentUserGrade = userGradeStore.grade(for: prospect.id)
        return NavigationStack {
            VStack(spacing: 20) {
                Text(prospect.fullName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                if let staffGrade = prospect.scoutGrade {
                    Text("Scout Grade: \(staffGrade)")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }

                Text("Your Assessment")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    // "None" button
                    Button {
                        userGradeStore.setGrade(nil, for: prospect.id)
                        editingAssessmentProspect = nil
                    } label: {
                        Text("None")
                            .font(.callout.weight(currentUserGrade == nil ? .bold : .regular))
                            .foregroundStyle(currentUserGrade == nil ? Color.backgroundPrimary : Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(currentUserGrade == nil ? Color.accentGold : Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.textTertiary.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    ForEach(UserGrade.allCases) { grade in
                        let isSelected = currentUserGrade == grade
                        Button {
                            userGradeStore.setGrade(grade, for: prospect.id)
                            editingAssessmentProspect = nil
                        } label: {
                            VStack(spacing: 1) {
                                Text(grade.letterGrade)
                                    .font(.callout.weight(isSelected ? .bold : .regular))
                                Text(grade.shortLabel)
                                    .font(.system(size: 7))
                                    .foregroundStyle(isSelected ? Color.backgroundPrimary.opacity(0.7) : Color.textTertiary)
                            }
                            .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSelected ? grade.color : Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.textTertiary.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 24)
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Grade Prospect")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingAssessmentProspect = nil }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - #11: Note Sheet

    private func prospectNoteSheet(prospect: CollegeProspect) -> some View {
        ProspectNoteSheetView(
            prospectName: prospect.fullName,
            initialNote: prospectNotes[prospect.id.uuidString] ?? "",
            onSave: { note in
                saveProspectNote(prospectID: prospect.id, note: note)
                editingNoteProspect = nil
            },
            onCancel: { editingNoteProspect = nil }
        )
    }

    // MARK: - Helpers

    private func rankFor(_ prospect: CollegeProspect) -> Int {
        cachedRankMap[prospect.id] ?? 0
    }

    private func customRankFor(_ prospect: CollegeProspect) -> Int {
        cachedCustomRankMap[prospect.id] ?? 0
    }

    /// Move prospect to a different tier using manual tier override (preserves scoutedOverall).
    private func moveProspectToTier(_ prospect: CollegeProspect, tier: Int) {
        prospect.manualTier = tier
        try? modelContext.save()
        refreshCachedBoard()
    }

    /// Need level: High / Med / Set based on roster depth (#4)
    private func needLevel(for position: Position) -> String {
        guard !teamRoster.isEmpty else { return "Set" }
        let idealCounts: [Position: Int] = [
            .QB: 2, .RB: 3, .FB: 1, .WR: 5, .TE: 3,
            .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 2,
            .DE: 4, .DT: 3, .OLB: 4, .MLB: 2,
            .CB: 5, .FS: 2, .SS: 2, .K: 1, .P: 1
        ]
        let rosterCount = teamRoster.filter { $0.position == position }.count
        let ideal = idealCounts[position] ?? 2
        let deficit = ideal - rosterCount
        if deficit >= 2 { return "High" }
        if deficit >= 1 { return "Med" }
        return "Set"
    }

    /// Whether a prospect is a value pick: board rank significantly better than projected round (#14)
    private func isValuePick(_ prospect: CollegeProspect) -> Bool {
        let rank = rankFor(prospect)
        guard rank > 0 else { return false }
        let projRound = boardProjectedRound(for: prospect)
        // If ranked in top 32 but projected Rd 3+, or top 64 but projected Rd 4+, etc.
        let boardRound = max(1, ((rank - 1) / 32) + 1)
        return projRound - boardRound >= 2
    }

    /// Auto-rank the board using the scouts' composite score (#12).
    private func autoRankBoard() {
        let ranked = scoutedProspects
            .sorted { boardCompositeScore(for: $0) > boardCompositeScore(for: $1) }
            .map(\.id)
        saveBoardOrder(ranked)
        userGradeStore.clearOriginalPositions()
        recordOriginalPositions()
        refreshCachedBoard()
    }

    /// Move a prospect up or down in the board order (#17).
    private func moveBoardPosition(_ prospect: CollegeProspect, direction: Int) {
        var order = boardOrder
        guard let idx = order.firstIndex(of: prospect.id) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0, newIdx < order.count else { return }
        order.swapAt(idx, newIdx)
        saveBoardOrder(order)
        refreshCachedBoard()
    }

    /// Probability prospect is available at user's first pick (#18).
    ///
    /// ONE availability model, shared with the Mock Draft and the war room's
    /// pick sheet (`DraftAvailability`). This used to bucket off the ROUND —
    /// `boardProjectedRound` vs the pick's round → 0.95/0.75/0.40/0.15/0.05 —
    /// so a man the media mocked at #18 read 40 % here and 76 % on the Mock
    /// Draft, and the two screens contradicted each other about the same
    /// player on the same day. The curve now reads the media's published
    /// window and is as flat as that window is wide.
    private func availableAtPickProbability(for prospect: CollegeProspect) -> Double? {
        let sortedPicks = teamDraftPicks
            .filter { !$0.isComplete }
            .sorted { $0.pickNumber < $1.pickNumber }
        guard let firstPick = sortedPicks.first else { return nil }
        return DraftAvailability.probability(
            for: prospect,
            atPick: firstPick.pickNumber,
            consensusRank: marketRank(for: prospect)
        )
    }

    private func loadCoaches() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        coaches = (try? modelContext.fetch(desc)) ?? []
    }

    /// The club's picks in the draft this cycle is building toward — and ONLY
    /// those.
    ///
    /// This used to fetch every `DraftPick` the team owned, in any year. The
    /// pick pool always holds three future drafts as well (`futureDraftPicks`,
    /// the tradable horizon), and each of those rows carries a *provisional*
    /// slot: the midpoint of its round, `round * 32 - 16`. So the Draft Prep
    /// card listed "Rd 1 #16, Rd 1 #16, Rd 1 #16, Rd 2 #48, Rd 2 #48…" — 28
    /// picks in triplicate — and "available at your first pick" was computed
    /// against a fabricated #16 belonging to a draft three years out, on a team
    /// that in this year's draft was picking fourth.
    private func loadDraftPicks() {
        guard let teamID = career.teamID else { return }
        let season = career.currentSeason
        let desc = FetchDescriptor<DraftPick>(
            predicate: #Predicate<DraftPick> {
                $0.currentTeamID == teamID && $0.seasonYear == season
            }
        )
        teamDraftPicks = (try? modelContext.fetch(desc)) ?? []
    }

    /// Compute scheme fit label for a prospect based on team's coordinators.
    private func schemeFitLabel(for prospect: CollegeProspect) -> String? {
        guard prospect.scoutedOverall != nil else { return nil }
        let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
        let dc = coaches.first(where: { $0.role == .defensiveCoordinator })

        if prospect.position.side == .offense, let scheme = oc?.offensiveScheme {
            return ProspectSchemeFitHelper.offensiveFit(prospect: prospect, scheme: scheme)
        } else if prospect.position.side == .defense, let scheme = dc?.defensiveScheme {
            return ProspectSchemeFitHelper.defensiveFit(prospect: prospect, scheme: scheme)
        }
        return nil
    }

    /// Compute starter comparison text for a prospect.
    private func starterComparison(for prospect: CollegeProspect) -> String? {
        guard let prospectOVR = prospect.scoutedOverall else { return nil }
        let starters = teamRoster
            .filter { $0.position == prospect.position }
            .sorted { $0.overall > $1.overall }
        guard let starter = starters.first else {
            return "No \(prospect.position.rawValue) on roster"
        }
        let diff = prospectOVR - starter.overall
        if diff > 0 {
            return "vs \(starter.fullName): +\(diff) OVR"
        } else if diff == 0 {
            return "vs \(starter.fullName): lateral"
        } else {
            return "Depth add (\(diff) OVR)"
        }
    }
}

// MARK: - Mark Filter

/// Board filter over the ONE mark system. Replaces `ProspectFlagFilter`, which
/// filtered `prospectFlag` — one of the four parallel opinions the unified
/// mark collapsed.
enum ProspectMarkFilter: String, CaseIterable, Identifiable {
    case all, elite, target, depth, avoid, unmarked

    var id: String { rawValue }

    /// The tier this filter keeps, or `nil` for "everything".
    var tier: ProspectMarkTier? {
        switch self {
        case .all:      return nil
        case .elite:    return .elite
        case .target:   return .target
        case .depth:    return .depth
        case .avoid:    return .avoid
        case .unmarked: return ProspectMarkTier.none
        }
    }

    var label: String {
        switch self {
        case .all:      return "All"
        case .unmarked: return "Unmarked"
        default:        return tier?.label ?? "All"
        }
    }

    var icon: String {
        switch self {
        case .all:      return "line.3.horizontal.decrease.circle"
        case .unmarked: return "circle.dashed"
        default:        return tier?.icon ?? "circle"
        }
    }
}

// MARK: - Big Board Row View (Compact Table Row)

struct BigBoardRowView: View {
    let rank: Int
    var totalCount: Int = 0
    let prospect: CollegeProspect
    var ownGrade: String? = nil
    var schemeFit: String? = nil
    var needLevel: String = "Set"
    var starterComparison: String? = nil
    var attributeTab: ProspectAttributeTab = .overview
    var scoutsSentToCombine: Bool = false
    /// The class-wide, position-keyed drill pool the Physical block ranks this
    /// man's numbers against. Built once by the host — see
    /// `BigBoardView.rebuildPercentilePools()`.
    var percentilePools: PercentilePools = PercentilePools()
    var isPositionNeed: Bool = false
    var projectedRound: Int = 7
    var isValuePick: Bool = false
    /// Market-vs-my-grade read; `nil` when the user has not graded him or the
    /// media has no slot for him.
    var valueRead: ProspectFog.ValueRead? = nil
    var originalPosition: Int? = nil
    var isSelectedForCompare: Bool = false
    /// The user's own club — the only team whose Top-30 visit tells him
    /// anything. `nil` outside a career (previews).
    var userTeamID: UUID? = nil
    /// Drops the per-row position badge while the hub's position chips are
    /// scoping the board to one group.
    var hidesPositionBadge: Bool = false
    var onGradeTap: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            // Rank, and the movement badge when the user has hand-moved him.
            //
            // The "/350" denominator under every rank is gone: it was the same
            // number on all 350 rows, printed at 6 pt — below the legibility
            // floor — and it forced this column into a two-line stack that set
            // the row's height. The board size belongs in the header, not on
            // every row of it.
            VStack(spacing: 0) {
                Text("\(rank)")
                    .font(.system(size: DSType.Size.caption, weight: .heavy).monospacedDigit())
                    .foregroundStyle(manualMoveRankColor)
                if let orig = originalPosition, orig != rank {
                    let movedUp = rank < orig
                    Text("\(movedUp ? "\u{2191}" : "\u{2193}")\(orig)")
                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                        .foregroundStyle(movedUp ? Color.success : Color.dangerText)
                }
            }
            .frame(width: 24, alignment: .center)

            // Position badge — dropped while a position filter is on. The chips
            // above the list already say "QB", and repeating it on every row of
            // a QB-only board is 36 pt of column spent on a constant.
            if !hidesPositionBadge {
                boardPositionBadge
            }

            // Portrait (30 pt — same height as the row's two text lines, so
            // board rows keep their current density).
            PersonFaceView(prospect: prospect, size: .small)
                .padding(.leading, 6)

            // Name column (compact)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(prospect.fullName)
                        .font(.system(size: DSType.Size.body, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    // The ONE mark, with a dog-ear when a board note exists.
                    ProspectMarkChip(
                        mark: prospect.userMark,
                        showsNote: !prospect.userMarkNote.isEmpty
                    )

                    if isSelectedForCompare {
                        Image(systemName: "checkmark.rectangle.stack.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.accentBlue)
                            .accessibilityLabel("In compare tray")
                    }

                    UserGradeBadge(prospectID: prospect.id)
                }

                // Compact sub-info icons.
                //
                // Two chips left this line. The green "Value" badge duplicated
                // the VAL column two inches to the right — same fact, two
                // encodings, one of them a word — and the newspaper glyph said
                // only "a combine mention exists", which the CMB badge's own
                // performance tint already carries.
                HStack(spacing: 4) {
                    // Prep state: reports filed / room taken / numbers measured.
                    // Three fixed slots, dimmed when empty — the icons used to
                    // appear only when the work HAD been done, which made the
                    // holes in the board invisible, and the holes are the whole
                    // question the user is scanning for.
                    ProspectPrepChips(prospect: prospect)

                    // CMB badge with color coding (#7)
                    if prospect.combineInvite {
                        Text("CMB")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(combinePerformanceColor, in: RoundedRectangle(cornerRadius: 2))
                    }
                    // Is he even in this draft? (S11)
                    ProspectDeclarationChip(prospect: prospect)

                    // #6: Current starter comparison
                    if let comparison = starterComparison {
                        Text(comparison)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(comparison.hasPrefix("+") ? Color.success : comparison.contains("Depth") ? Color.dangerText : Color.textTertiaryReadable)
                    }
                }
            }
            .frame(minWidth: 80, alignment: .leading)
            .padding(.leading, 6)

            // OVR — the FIRST column after the name, in every mode.
            //
            // It used to sit at the trailing edge, eleven columns to the right,
            // which meant the Physical block read as six raw stopwatch numbers
            // with your department's actual verdict on the man parked past them.
            // The grade is what orders this board and it is what the user scans
            // for; it belongs beside the name it belongs to.
            boardOverallBadge

            Spacer(minLength: 2)

            // Tab-specific columns, from the shared vocabulary. Nothing here is
            // board-only any more: the film-study and interview batch lists
            // render the same five blocks from the same fogged accessors.
            ProspectColumns.cells(for: prospect, mode: attributeTab, context: columnContext)

            // Always-visible, and now TWO columns rather than one: the tape read
            // (a gold band from your scouts) and the meeting read (an exact blue
            // number from your interview). `ProspectIQCell` merged them behind a
            // precedence rule and printed whichever won, which is right for the
            // draft room's tight rows and wrong for a board the user is scanning
            // to find the work he has not done.
            //
            // 42 / 38 rather than 40 / 34: the pinned header has always reserved
            // 42 and 38 for these labels (the tooltip button needs it), so the
            // cells were running 2 and 4 points narrow and walking every column
            // to their right off its label.
            ProspectTapeCell(prospect: prospect, width: 42)
            ProspectMeetCell(prospect: prospect, width: 38)

            // Always-visible: value vs the user's own grade.
            ProspectValueChip(read: valueRead)
                .frame(width: 34, alignment: .center)

            // Always-visible: Proj Rd or Grade
            if attributeTab == .overview {
                boardProjectedRoundBadge
            } else {
                boardGradeColumn
            }

            // Drag handle
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Color.textTertiary)
                .font(.system(size: 10))
                .frame(width: 22)
        }
        // 4 → 2. With the rank column back to one line, the 30 pt portrait is
        // the row's height floor, so this is 4 pt off every row of a 350-row
        // list — roughly one extra prospect per screen on its own.
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Column context
    //
    // The five per-mode column blocks moved to `ProspectColumns` in
    // `ProspectListControls.swift`, because the film-study and interview batch
    // lists render exactly the same blocks and three copies of "what the
    // combine card says at this fidelity" is three copies that drift. What is
    // left here is the part that is genuinely the BOARD's: the facts a column
    // needs that live on this screen rather than on the prospect.

    private var columnContext: ProspectColumnContext {
        ProspectColumnContext(
            schemeFit: schemeFit,
            needLevel: needLevel,
            userTeamID: userTeamID,
            scoutsSentToCombine: scoutsSentToCombine,
            // Chargeable, like the board's own evaluate gate and both other
            // list surfaces — without this the board read 1/3 on a man whose
            // only paper was the inherited baseline, then happily sold him a
            // "fourth" report (#122 review F4).
            reportCount: ScoutEvaluationBudget.chargeableReports(prospect),
            percentilePools: percentilePools
            // `leadsWithScoutBand` stays OFF: the board pins its OWN band beside
            // the name, because tapping it opens the assessment sheet and a
            // shared cell cannot carry the board's `onGradeTap`. Turning both on
            // would print the same band twice on one row.
        )
    }

    // MARK: - Always-Visible Subviews

    private var boardPositionBadge: some View {
        Text(prospect.position.rawValue)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
            .frame(width: 36, height: 24)
            .background(positionColor, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
    }

    /// The OVR cell — the band the user's own scouts are entitled to, widened by
    /// how confident they are (`ProspectFog.read`, which folds in
    /// `DraftIntel.scoutConfidence`).
    ///
    /// Reading `prospect.effectiveOverallGrade` straight printed the raw stored
    /// range, which is narrower than the department's actual certainty — the
    /// same drift `ProspectDetailView` fixed on the prospect card. Still `nil`
    /// exactly when `effectiveOverallGrade` was (a scouted grade is the only
    /// thing that makes the read `.scouts`), so the "?" branch is unchanged.
    ///
    /// The cell itself is `ProspectScoutBandCell` in `ProspectListControls.swift`
    /// now — the interview list prints the same band and was reading
    /// `overallGradeDisplay`, i.e. the un-widened stored range. What is left
    /// here is the board's own affordance: tapping the grade opens the
    /// assessment sheet.
    private var boardOverallBadge: some View {
        Button {
            onGradeTap?()
        } label: {
            ProspectScoutBandCell(prospect: prospect, width: 50)
        }
        .buttonStyle(.plain)
    }

    private var boardProjectedRoundBadge: some View {
        let displayRound = projectedRound <= 7 ? projectedRound : nil
        let text = ProspectRoundFormat.projectedRoundText(for: displayRound)
        let color = boardProjectedRoundColorFromRound
        return VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // Two arrows, two sources: the MEDIA's move on the projected round
            // (blue/amber) beside your own scouts' grade change (green/red).
            HStack(spacing: 3) {
                ProspectMarketArrow(prospect: prospect)
                boardGradeChangeIndicator
            }
        }
        .frame(width: 52, alignment: .center)
    }

    private var boardProjectedRoundColorFromRound: Color {
        switch projectedRound {
        case 1:    return .accentGold
        case 2:    return .accentGold.opacity(0.8)
        case 3:    return .accentBlue
        case 4:    return .accentBlue.opacity(0.7)
        case 5...6: return .textSecondary
        default:    return .textTertiary
        }
    }

    private var boardGradeColumn: some View {
        VStack(spacing: 0) {
            if let grade = prospect.scoutGrade {
                Text(grade)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            } else {
                Text("--")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            boardGradeChangeIndicator
        }
        .frame(width: 30, alignment: .center)
    }

    // The FIT / NEED / RISK cells moved to `ProspectColumns` with the rest of
    // the Overview block. The risk badge is `ProspectRiskBadge` there, because
    // the interview list pins risk in its own trailing column and was drawing a
    // second, differently-worded copy of it.

    // MARK: - Grade Change Indicator

    @ViewBuilder
    private var boardGradeChangeIndicator: some View {
        if let preGrade = prospect.preCombineGrade,
           let currentGrade = prospect.scoutGrade,
           preGrade != currentGrade {
            let improved = ProspectRoundFormat.gradeRank(currentGrade) > ProspectRoundFormat.gradeRank(preGrade)
            Text(improved ? "\u{2191}" : "\u{2193}")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(improved ? Color.success : Color.danger)
        }
    }

    // MARK: - Helpers

    private var rankColor: Color {
        switch rank {
        case 1:    return .accentGold
        case 2...5: return .textPrimary
        default:   return .textSecondary
        }
    }

    /// Rank color that reflects manual movement: green if moved up, red if moved down, default otherwise.
    private var manualMoveRankColor: Color {
        guard let orig = originalPosition, orig != rank else { return rankColor }
        return rank < orig ? .success : .danger
    }

    private var positionColor: Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    // boardProjectedRoundColor replaced by boardProjectedRoundColorFromRound

    private var accessibilityDescription: String {
        let overall = prospect.overallGradeDisplay
        let mark = prospect.isMarked ? ", marked \(prospect.userMark.label)" : ""
        let value = valueRead.flatMap { $0.isMeaningful ? ", \($0.label)" : nil } ?? ""
        // `totalCount` is spoken here rather than printed on the row: VoiceOver
        // has no column headers to fall back on, so "rank 12 of 350" is the one
        // place the denominator still earns its keep.
        let of = totalCount > 0 ? " of \(totalCount)" : ""
        return "Rank \(rank)\(of), \(prospect.fullName), \(prospect.position.rawValue), \(prospect.college), overall \(overall)\(mark)\(value)"
    }

    /// How the CMB badge is tinted — how the man TESTED, as far as this club is
    /// entitled to read it (#7).
    ///
    /// It used to average `truePhysical`, which is the generator's own attribute
    /// block: low bandwidth, but a leak all the same, because a club that never
    /// went to Indianapolis still got a green badge off a 91 speed nobody had
    /// ever shown it. The signal is the position-drill grade at
    /// `ProspectFog.combineFidelity` now — the same letter the combine table
    /// prints in its Pos Drill cell, coarsened to its tier for a club that only
    /// watched the broadcast — so the tint says exactly what the card says and
    /// nothing more. Grey when the drill session produced nothing you can read:
    /// a specialist, or a man who did not work out.
    private var combinePerformanceColor: Color {
        let fidelity = ProspectFog.combineFidelity(
            for: prospect,
            scoutsAttended: scoutsSentToCombine
        )
        guard let text = ProspectFog.drillGradeText(prospect.positionDrillGrade, fidelity: fidelity)
        else { return Color.textTertiary }
        // THE grade colour, not a fourth ladder. This used to be a bespoke
        // three-band switch on `ProspectRoundFormat.gradeRank` — B+ and up
        // green, C through B yellow, C- and down red — so the same letter that
        // printed blue in the Pos Drill cell painted the badge yellow two
        // inches away. The central function already handles "D-", which is the
        // string the engine writes and which `LetterGrade` has no case for.
        return PositionGradeCalculator.gradeColorForLetter(text)
    }

    // `boardMediaColor` deleted with the newspaper glyph it tinted. The glyph
    // said "a combine mention exists" and nothing else; the mention's direction
    // is already on the row twice — as the CMB badge's performance tint and as
    // the stock-trajectory arrow inside the OVR cell.
}

// MARK: - #9: Big Board Sort Enum

enum BigBoardSort: String, CaseIterable, Identifiable {
    case boardRank, valueDelta, overall, position, tier, schemeFit, risk, production, footballIQ

    var id: String { rawValue }

    var label: String {
        switch self {
        case .boardRank:  return String(localized: "Board Rank")
        case .valueDelta: return String(localized: "Value vs My Grade")
        case .overall:    return String(localized: "Overall")
        case .position:   return String(localized: "Position")
        case .tier:       return String(localized: "Tier")
        case .schemeFit:  return String(localized: "Scheme Fit")
        case .risk:       return String(localized: "Risk Level")
        case .production: return String(localized: "College Production")
        case .footballIQ: return String(localized: "Football IQ")
        }
    }

    var icon: String {
        switch self {
        case .boardRank:  return "list.number"
        case .valueDelta: return "arrow.up.arrow.down.square"
        case .overall:    return "star.fill"
        case .position:   return "rectangle.3.group"
        case .tier:       return "chart.bar.fill"
        case .schemeFit:  return "checkmark.circle"
        case .risk:       return "bolt.fill"
        case .production: return "chart.bar.xaxis"
        case .footballIQ: return "brain.head.profile"
        }
    }
}

// MARK: - #11: Prospect Note Sheet

struct ProspectNoteSheetView: View {
    let prospectName: String
    @State var noteText: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    init(prospectName: String, initialNote: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.prospectName = prospectName
        self._noteText = State(initialValue: initialNote)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(prospectName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                TextEditor(text: $noteText)
                    .scrollContentBackground(.hidden)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                    .padding(8)
                    .frame(minHeight: 120)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.backgroundSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                            )
                    )

                Text("\(noteText.count)/200")
                    .font(.caption)
                    .foregroundStyle(noteText.count > 200 ? Color.danger : Color.textTertiary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 24)
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Prospect Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(String(noteText.prefix(200)))
                    }
                    .foregroundStyle(Color.accentGold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Draft Round Helper

enum DraftRoundHelper {
    /// Convert a projected overall pick number to a round (1-7), 32 picks per round.
    static func roundForPick(_ pick: Int) -> Int {
        return min(7, max(1, ((pick - 1) / 32) + 1))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BigBoardView(
            career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
            prospects: [
                CollegeProspect(
                    firstName: "Caleb", lastName: "Williams",
                    college: "USC", position: .QB,
                    age: 21, height: 74, weight: 214,
                    truePositionAttributes: .quarterback(QBAttributes(
                        armStrength: 92, accuracyShort: 88, accuracyMid: 90,
                        accuracyDeep: 85, pocketPresence: 87, scrambling: 78
                    )),
                    truePersonality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                    scoutedOverall: 89, scoutGrade: "A", draftProjection: 1
                ),
                CollegeProspect(
                    firstName: "Marvin", lastName: "Harrison Jr.",
                    college: "Ohio State", position: .WR,
                    age: 21, height: 75, weight: 209,
                    truePositionAttributes: .wideReceiver(WRAttributes(
                        routeRunning: 91, catching: 93, release: 90, spectacularCatch: 88
                    )),
                    truePersonality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning),
                    scoutedOverall: 91, scoutGrade: "A+", draftProjection: 2
                ),
            ],
            teamRoster: [],
            positionFilter: .constant(.all),
            header: { EmptyView() }
        )
    }
}
