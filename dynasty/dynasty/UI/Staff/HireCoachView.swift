import SwiftUI
import SwiftData

struct HireCoachView: View {

    let role: CoachRole
    let teamID: UUID
    /// The save being played. Threaded in rather than guessed from
    /// `allCareers.first`, which stamped hires with the WRONG save's season
    /// once a second career existed.
    let career: Career
    let remainingBudget: Int
    /// #267: Team data for candidate quality scaling
    var teamBudget: Int = 25_000
    var teamWins: Int = 8
    var teamReputation: Int = 50
    /// `(name, role, salary in thousands)`.
    ///
    /// Wave 5b: the salary joined the callback because the ending is a
    /// `DSResultSheet` now, and §2.6's third beat is "what it cost". The toast
    /// this replaced could not answer it, so the user had to close the sheet and
    /// go and read the budget header himself.
    var onHired: ((String, String, Int) -> Void)?
    /// The hire waiting for the negotiation cover to finish dismissing.
    ///
    /// Replaces a 0.6 s + 0.4 s timer pair. `fullScreenCover(onDismiss:)` fires
    /// when the cover is actually gone, which is the thing the deadlines were
    /// guessing at — and the host can then swap the sheet's content to the
    /// result without racing a dismissal.
    @State private var pendingHire: (name: String, role: String, salary: Int)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allCoachesUnscoped: [Coach]

    // `@Query` cannot take a runtime predicate built from a stored property,
    // so the store-wide result is narrowed to THIS save here.
    private var allCoaches: [Coach] { allCoachesUnscoped.filter { $0.careerID == career.id } }

    @State private var candidates: [Coach] = []
    @State private var hiredCoachID: UUID?
    @State private var sortColumn: SortColumn = .ovr
    @State private var sortAscending: Bool = false
    @State private var selectedCandidate: Coach?
    /// #3067: the salary ceiling the board is filtered against, in thousands.
    ///
    /// Replaces a plain `showAffordableOnly` switch. That switch was binary and
    /// measured against the WHOLE remaining pot, so its only question was "can
    /// this club afford him at all" — and with three coordinator seats sharing
    /// one pot, the question a GM actually has is "what am I willing to spend on
    /// THIS one". Only a ceiling he sets himself can answer that.
    ///
    /// `nil` means "untouched", which reads as the top of the slider's range —
    /// the whole remaining budget, i.e. exactly what the old switch meant when
    /// it was ON. Kept optional rather than seeded in `.task` so the board never
    /// renders a frame filtered against a not-yet-initialised zero.
    @State private var maxSalary: Double?
    @State private var schemeFilter: String = "All"
    @State private var showValueLegend: Bool = false
    @State private var showSchemeTip: Bool = false
    /// #17: Toggle for OVR/skill color legend panel.
    @State private var showRatingLegend: Bool = false
    /// #20: Personality archetype filter ("All" or PersonalityArchetype.rawValue).
    @State private var personalityFilter: String = "All"
    /// #271: Track candidates who rejected offers — shown grayed out with "Signed elsewhere"
    @State private var rejectedCandidates: Set<UUID> = []
    /// Task #96: which rows are real out-of-work coaches rather than invented
    /// candidates. Snapshotted when the list is built — a hire takes the man off
    /// the bench, and the badge must not vanish from the row the user just used.
    @State private var marketCandidateIDs: Set<UUID> = []

    // MARK: - Shortlist (side-by-side compare)
    //
    // The board poses a genuine trade-off — the man with the higher OVR is
    // rarely the man with the better value, the better scheme fit and the
    // shorter queue of rival clubs — and the screen could only ever show ONE
    // candidate at a time: the profile is a full-screen cover, so holding two
    // of them in mind meant closing one, scrolling back to the row, opening the
    // other, and remembering twelve attributes in between.

    /// The pinned candidates, in the order the user picked them.
    ///
    /// An ORDERED array rather than a `Set`: the compare table lays its columns
    /// out in pick order, and a `Set` would let the two men swap sides between
    /// openings for no reason the user can see.
    ///
    /// A pin deliberately survives the filters. Pulling the max-salary ceiling
    /// down after pinning an expensive man is exactly how the trade-off gets
    /// examined, so the pin store is keyed off `candidates`, not off the
    /// filtered list.
    @State private var compareIDs: [UUID] = []
    /// The rows the compare table is showing, frozen when it opened.
    ///
    /// Built at the tap rather than inside the sheet's content closure because
    /// `Coach.potentialLabel(seasonsOnTeam:)` rolls fresh noise on EVERY call —
    /// derived per render, a candidate's ceiling would flicker between "High"
    /// and "Elite" while the user was reading the column.
    @State private var compareEntries: [CoachCompareEntry] = []
    @State private var showCompareSheet: Bool = false
    /// The candidate whose profile the compare table asked for, waiting for the
    /// table to finish dismissing — the same hand-off `pendingHire` uses, for
    /// the same reason: one presentation at a time.
    @State private var pendingProfileID: UUID?

    // MARK: - Performance caches
    // Recomputed via refreshCaches() on dependency changes — avoids per-render O(n log n) sorts in body.
    @State private var cachedSortedCandidates: [Coach] = []
    @State private var cachedTop3IDs: Set<UUID> = []
    @State private var cachedAvailableSchemes: [String] = ["All"]
    @State private var cachedCurrentCoachOVR: Int?

    /// The team's head coach, used to determine current team scheme for fit indicator.
    private var teamHeadCoach: Coach? {
        allCoaches.first { $0.teamID == teamID && $0.role == .headCoach }
    }

    /// The team's offensive coordinator, used as fallback for offensive scheme when HC absent.
    private var teamOffensiveCoordinator: Coach? {
        allCoaches.first { $0.teamID == teamID && $0.role == .offensiveCoordinator }
    }

    /// The team's defensive coordinator, used as fallback for defensive scheme when HC absent.
    private var teamDefensiveCoordinator: Coach? {
        allCoaches.first { $0.teamID == teamID && $0.role == .defensiveCoordinator }
    }

    /// Effective offensive scheme — HC's, falling back to OC's.
    private var teamOffensiveScheme: OffensiveScheme? {
        teamHeadCoach?.offensiveScheme ?? teamOffensiveCoordinator?.offensiveScheme
    }

    /// Effective defensive scheme — HC's, falling back to DC's.
    private var teamDefensiveScheme: DefensiveScheme? {
        teamHeadCoach?.defensiveScheme ?? teamDefensiveCoordinator?.defensiveScheme
    }

    /// Whether any team scheme can be inferred — used to hide the Fit column otherwise.
    private var hasInferableTeamScheme: Bool {
        teamOffensiveScheme != nil || teamDefensiveScheme != nil
    }

    /// The current coach in the role being hired for (Fix #63: comparison).
    private var currentCoach: Coach? {
        allCoaches.first { $0.teamID == teamID && $0.role == role }
    }

    /// Task #96 — REAL out-of-work coaches, listed alongside the invented ones.
    ///
    /// The league runs a coaching market: firings, Black Monday and poaching put
    /// men on an unemployed bench every offseason, all 31 AI clubs hire out of it
    /// (`CoachMarketEngine.hireFromBench`), and a man nobody calls back eventually
    /// leaves the profession. The user could see none of it — this screen was fed
    /// exclusively by `CoachingEngine.generateCoachCandidates`, so the one GM in
    /// the league who could never sign a known coach was the human, and his own
    /// coordinator, whose departure the news announced as "hired away by another
    /// organization", was unreachable forever after.
    ///
    /// Exact-title only, and no mutation before the hire: a listed man's `salary`
    /// is the going rate for THIS seat because it was set for this seat, so the
    /// budget check on the row is honest without re-pricing a coach the user
    /// never signs. Cross-family recycling (a demoted coordinator taking a
    /// position room) stays an AI-side bulk mechanic.
    private var marketCandidates: [Coach] {
        CoachMarketEngine.availableBench(allCoaches).filter { $0.role == role }
    }

    // MARK: - Sort Column

    enum SortColumn: String, CaseIterable {
        case name    = "Name"
        case age     = "Age"
        case scheme  = "Scheme"
        /// "Best available for THIS staff" — see ``teamFitScore(_:)``.
        case teamFit = "For Us"
        case ovr     = "OVR"
        case play    = "Play"
        case dev     = "Dev"
        case game    = "Game"
        case salary  = "Salary"
        case value   = "Value"
    }

    // MARK: - Helpers

    private func coachOverall(_ coach: Coach) -> Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

    /// Fix #60: Value score — OVR-per-million calibrated against the role's avg salary.
    /// Reference ratio = 65 OVR / role.avgSalaryM. A coach matching that ratio is "Fair".
    /// 1.4× reference = "Great", 1.15× = "Good", 0.85× = "Poor".
    private func valueScore(_ coach: Coach) -> (label: String, color: Color) {
        let ratio = valueRatio(coach)
        let reference = roleReferenceRatio
        if ratio >= reference * 1.40 { return ("Great", .success) }
        if ratio >= reference * 1.15 { return ("Good", .accentBlue) }
        if ratio >= reference * 0.85 { return ("Fair", .warning) }
        return ("Poor", .danger)
    }

    private func valueRatio(_ coach: Coach) -> Double {
        let ovr = coachOverall(coach)
        let salaryM = max(Double(coach.salary) / 1000.0, 0.1)
        return Double(ovr) / salaryM
    }

    /// Reference OVR-per-million ratio for the role being hired.
    /// Treats avg-OVR (65) at the role's avg salary as the "Fair" baseline.
    private var roleReferenceRatio: Double {
        let avgSalaryM = max(Double(role.salaryRange.avg) / 1000.0, 0.1)
        return 65.0 / avgSalaryM
    }

    // MARK: - "For Us" composite

    /// Best available **for this staff**, 0-100.
    ///
    /// Every other ranking on this board is an absolute reading of a man: OVR
    /// is the mean of twelve attributes, Val is his price, Fit is one word, and
    /// the TOP 3 badge is OVR again. None of them answers the question a GM
    /// actually has — who is the best man *for this chair, in this system,
    /// under this head coach*. The three terms below are all already computed
    /// per candidate elsewhere on the screen; this composes them.
    ///
    ///   * **focus × 5** — the mean of `CoachRole.focusAttributes`, i.e. what
    ///     this particular chair is bought for (the same set the header row
    ///     already marks with a gold dot). The heaviest term because it is the
    ///     only one about the job itself.
    ///   * **scheme fit × 3** — `schemeFit(for:)`'s Great / OK / Poor against
    ///     the system the club installs. Neutral when the club has installed
    ///     nothing to be rated against, so an unstaffed club is not ranked on a
    ///     comparison that does not exist yet.
    ///   * **chemistry × 2** — `CoachingEngine.coachChemistry` against the head
    ///     coach, the same −1…1 reading the staff screen bands, mapped to
    ///     0…100. Neutral when there is no head coach on the books.
    ///
    /// The weights are the retunable part of this and they are one line each.
    private func teamFitScore(_ coach: Coach) -> Int {
        let focus = role.focusAttributes
        let focusScore = focus.isEmpty
            ? coachOverall(coach)
            : focus.reduce(0) { $0 + coach.attributeValue(named: $1) } / focus.count

        let fitScore: Int = {
            guard let fit = schemeFit(for: coach) else { return 60 }
            switch fit.label {
            case "Great": return 100
            case "OK":    return 60
            default:      return 25
            }
        }()

        let chemistryScore: Int = {
            guard let hc = teamHeadCoach else { return 50 }
            let score = CoachingEngine.coachChemistry(
                coachA: hc.personality,
                coachB: coach.personality
            )
            return Int(((score + 1.0) / 2.0) * 100.0)
        }()

        return (focusScore * 5 + fitScore * 3 + chemistryScore * 2) / 10
    }

    /// Fix #56: Top-3 candidate indices in the current sorted list.
    private var top3IDs: Set<UUID> { cachedTop3IDs }

    /// Available scheme names for the filter dropdown (Fix #58).
    private var availableSchemes: [String] { cachedAvailableSchemes }

    // MARK: - Filtered & Sorted Candidates

    /// The band the max-salary slider runs over: the role's own going-rate floor
    /// (`CoachRole.salaryRange.min`, the band the candidate generator draws
    /// from) up to whatever is left in the pot.
    ///
    /// `nil` when the pot cannot even cover the floor. There is no ceiling left
    /// to choose then, so the control is not offered and the board is not
    /// filtered — every row shows, over budget and greyed, which is the honest
    /// picture of a club that cannot afford this seat.
    private var salarySliderRange: ClosedRange<Double>? {
        let floor = Double(role.salaryRange.min)
        let ceiling = Double(remainingBudget)
        guard ceiling > floor else { return nil }
        return floor...ceiling
    }

    /// The ceiling actually applied to the board, in thousands.
    private var salaryCap: Int? {
        guard let range = salarySliderRange else { return nil }
        let chosen = maxSalary ?? range.upperBound
        return Int(min(range.upperBound, max(range.lowerBound, chosen)))
    }

    /// True only while the slider is excluding somebody — i.e. it has been
    /// pulled below the full remaining budget.
    private var isSalaryCapNarrowed: Bool {
        guard let range = salarySliderRange, let cap = salaryCap else { return false }
        return Double(cap) < range.upperBound
    }

    private var filteredCandidates: [Coach] {
        var list = candidates
        if let cap = salaryCap {
            list = list.filter { $0.salary <= cap }
        }
        // Fix #58: Scheme filter
        if schemeFilter != "All" {
            list = list.filter { schemeLabel($0) == schemeFilter }
        }
        // #20: Personality filter
        if personalityFilter != "All" {
            list = list.filter { $0.personality.rawValue == personalityFilter }
        }
        return list
    }

    private var sortedCandidates: [Coach] { cachedSortedCandidates }

    /// Why the table is empty, in the user's terms.
    ///
    /// Without this the row area simply rendered nothing — the stadium
    /// background showed through a header, a column strip and a void, which
    /// reads as a broken screen rather than as "the filters exclude everyone"
    /// (or, while the pool is still being built, "one moment").
    @ViewBuilder
    private var candidateEmptyState: some View {
        let filtersActive = isSalaryCapNarrowed || schemeFilter != "All" || personalityFilter != "All"
        VStack(spacing: 12) {
            if candidates.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.accentGold)
                Text("Building the candidate pool\u{2026}")
                    .font(.system(size: DSType.Size.callout, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("Your scouts are working the phones for \(role.displayName.lowercased()) candidates.")
                    .font(.system(size: DSType.Size.body))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: DSType.Size.display))
                    .foregroundStyle(Color.textTertiary)
                Text("No candidates match your filters")
                    .font(.system(size: DSType.Size.callout, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text(filtersActive
                     ? "\(candidates.count) \(role.displayName.lowercased()) candidates are available. Clear a filter above to see them."
                     : "Nobody is available for this job right now.")
                    .font(.system(size: DSType.Size.body))
                    .foregroundStyle(Color.textTertiary)
                    .multilineTextAlignment(.center)
                if filtersActive {
                    Button("Clear filters") {
                        maxSalary = salarySliderRange?.upperBound
                        schemeFilter = "All"
                        personalityFilter = "All"
                    }
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 56)
    }

    /// Recomputes all derived caches. Called when dependencies change.
    private func refreshCaches() {
        let filtered = filteredCandidates

        let sorted: [Coach]
        switch sortColumn {
        case .name:    sorted = filtered.sorted { $0.lastName < $1.lastName }
        case .age:     sorted = filtered.sorted { $0.age < $1.age }
        case .scheme:  sorted = filtered.sorted { schemeLabel($0) < schemeLabel($1) }
        case .teamFit: sorted = filtered.sorted { teamFitScore($0) > teamFitScore($1) }
        case .ovr:     sorted = filtered.sorted { coachOverall($0) > coachOverall($1) }
        case .play:    sorted = filtered.sorted { $0.playCalling > $1.playCalling }
        case .dev:     sorted = filtered.sorted { $0.playerDevelopment > $1.playerDevelopment }
        case .game:    sorted = filtered.sorted { $0.gamePlanning > $1.gamePlanning }
        case .salary:  sorted = filtered.sorted { $0.salary < $1.salary }
        case .value:   sorted = filtered.sorted { valueRatio($0) > valueRatio($1) }
        }
        cachedSortedCandidates = sortAscending ? sorted.reversed() : sorted

        // Top-3 by OVR among filtered candidates (regardless of sort column).
        // A bare prefix(3) let sort stability, not merit, break a tie: two men
        // on the same OVR, one badged and one not. Badge everyone level with 3rd.
        let byOVR = filtered.sorted { coachOverall($0) > coachOverall($1) }
        if let thirdOVR = byOVR.prefix(3).last.map({ coachOverall($0) }) {
            cachedTop3IDs = Set(byOVR.filter { coachOverall($0) >= thirdOVR }.map { $0.id })
        } else {
            cachedTop3IDs = []
        }

        // Available scheme names — depends only on candidates list
        var schemes = Set<String>()
        for c in candidates {
            if let o = c.offensiveScheme { schemes.insert(o.displayName) }
            if let d = c.defensiveScheme { schemes.insert(d.displayName) }
        }
        cachedAvailableSchemes = ["All"] + schemes.sorted()

        // Current-coach OVR cache, used by candidateRow to display delta without per-row recompute.
        cachedCurrentCoachOVR = currentCoach.map { coachOverall($0) }
    }

    // MARK: - Shortlist

    /// The pinned candidates, in pick order.
    ///
    /// Resolved against `candidates` (≈20-30 rows) rather than kept as a second
    /// store of `Coach` objects, so a pin can never outlive the pool it came
    /// from — and a man who is no longer on the board simply drops out.
    private var comparePinned: [Coach] {
        compareIDs.compactMap { id in candidates.first { $0.id == id } }
    }

    /// Pins or unpins a candidate. At the cap the OLDEST pin drops out rather
    /// than the tap doing nothing — `BigBoardView`'s prospect tray settled this
    /// question already, and a box that looks live and ignores you is how the
    /// same feature reads as broken.
    private func toggleCompare(_ candidate: Coach) {
        if let index = compareIDs.firstIndex(of: candidate.id) {
            compareIDs.remove(at: index)
        } else {
            if compareIDs.count >= CandidateCompareSheet.maxCandidates {
                compareIDs.removeFirst()
            }
            compareIDs.append(candidate.id)
        }
    }

    /// Freezes the pinned men into table rows, then opens the table.
    private func openCompare() {
        compareEntries = comparePinned.map(makeCompareEntry)
        showCompareSheet = true
    }

    /// One column's worth of derived data, computed once per opening.
    ///
    /// Everything here already exists on this screen — the row prints most of
    /// it — but the row recomputes it per render. The table asks the same
    /// questions of three men at once and would otherwise re-run
    /// `CoachCarouselEngine.demand` on every scroll frame.
    private func makeCompareEntry(_ coach: Coach) -> CoachCompareEntry {
        let ovr = coachOverall(coach)
        let potential = coach.potentialLabel(seasonsOnTeam: 0)
        let value = valueScore(coach)
        let fit = schemeFit(for: coach)
        return CoachCompareEntry(
            id: coach.id,
            coach: coach,
            ovr: ovr,
            ovrDelta: cachedCurrentCoachOVR.map { ovr - $0 },
            valueLabel: value.label,
            valueColor: value.color,
            valueRatio: valueRatio(coach),
            schemeName: schemeLabel(coach),
            fitLabel: fit?.label,
            fitColor: fit?.color,
            potentialLabel: potential,
            potentialColor: potentialBadgeColor(potential),
            rivalTeams: CoachCarouselEngine.demand(for: coach).rivalTeams,
            isMarketCandidate: marketCandidateIDs.contains(coach.id),
            isAffordable: coach.salary <= remainingBudget
        )
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            GeometryReader { geo in
                Image("BgCoachStadium1")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.15)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.backgroundPrimary.opacity(0.85), Color.backgroundPrimary.opacity(0.5), Color.backgroundPrimary.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Sticky budget header + filter
                budgetHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.backgroundSecondary)

                Divider().overlay(Color.surfaceBorder)

                // #149: Horizontally scrollable table for cramped columns.
                // Indicator shown: the row lays out at 864 pt, so in anything
                // narrower Salary and Val are off the right edge and a hidden
                // indicator left the gold role-dot of a clipped header as the
                // only hint that more columns existed. (780 before the compare
                // column joined the row, 820 before "For Us".)
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        // Sticky column headers
                        tableHeaderRow
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.backgroundTertiary.opacity(0.6))

                        Divider().overlay(Color.surfaceBorder)

                        // Candidate rows
                        ScrollView(.vertical) {
                            if sortedCandidates.isEmpty {
                                candidateEmptyState
                            } else {
                                LazyVStack(spacing: 0) {
                                    ForEach(sortedCandidates) { candidate in
                                        candidateRow(candidate)

                                        Divider()
                                            .overlay(Color.surfaceBorder.opacity(0.4))
                                            .padding(.horizontal, 12)
                                    }
                                }
                            }
                        }
                    }
                    .frame(minWidth: 864, maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
            // The shortlist tray (§2.5's commit surface). It exists only while
            // something is pinned, so the board keeps its full height until the
            // user actually asks for a comparison.
            .safeAreaInset(edge: .bottom) { compareTray }
        }
        .navigationTitle("Hire \(role.displayName)")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // How big the market for this seat is, beside the seat's own name.
            // It counts the FILTERED board, so pulling the max-salary slider
            // down is answered in the header rather than by scrolling the list.
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(filteredCandidates.count) candidates")
                    .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentGold.opacity(0.14), in: Capsule())
                    .accessibilityLabel("\(filteredCandidates.count) candidates on the board")
            }
        }
        .task {
            if candidates.isEmpty {
                // Yield first so the navigation transition completes before we block on generation.
                // CoachingEngine.generateCoachCandidates is @MainActor (touches SwiftData PersistentModels)
                // so we can't detach — but yielding lets the spinner / nav animation render first.
                await Task.yield()
                let count = Int.random(in: 20...30)
                // #267: Pass team data so candidate quality scales with budget/prestige
                let invented = CoachingEngine.generateCoachCandidates(
                    role: role,
                    count: count,
                    teamBudget: teamBudget,
                    teamWins: teamWins,
                    teamReputation: teamReputation
                )
                // Task #96: the league's actual unemployed coaches first, then
                // the invented field. Order here is cosmetic — every visible
                // list is re-sorted by `refreshCaches` — but it is the order the
                // empty-state and any future "market" grouping would want.
                let market = marketCandidates
                marketCandidateIDs = Set(market.map(\.id))
                candidates = market + invented
            }
            refreshCaches()
        }
        .onChange(of: candidates.count) { _, _ in refreshCaches() }
        .onChange(of: sortColumn) { _, _ in refreshCaches() }
        .onChange(of: sortAscending) { _, _ in refreshCaches() }
        .onChange(of: maxSalary) { _, _ in refreshCaches() }
        .onChange(of: schemeFilter) { _, _ in refreshCaches() }
        .onChange(of: personalityFilter) { _, _ in refreshCaches() }
        .onChange(of: allCoaches.count) { _, _ in refreshCaches() }
        // #157: Full screen cover on iPad for max space.
        // Wave 5b: the hire is reported from `onDismiss`, so the cover is
        // provably gone before the host swaps this sheet's content to the
        // result — ordered by SwiftUI instead of by a deadline.
        .fullScreenCover(item: $selectedCandidate, onDismiss: {
            if let hire = pendingHire {
                pendingHire = nil
                onHired?(hire.name, hire.role, hire.salary)
            }
        }) { candidate in
            CandidateDetailSheet(
                candidate: candidate,
                remainingBudget: remainingBudget,
                isHired: hiredCoachID == candidate.id,
                headCoach: teamHeadCoach,
                currentCoach: currentCoach,
                candidateRank: candidateRank(for: candidate),
                totalCandidates: filteredCandidates.count,
                schemeFitResult: schemeFit(for: candidate),
                installedSchemeName: installedSchemeName(for: candidate),
                // BUG FIX: When user is GM+HC, no .headCoach Coach record exists.
                // Pass user's coaching style so chemistry can be evaluated against the user.
                userIsHeadCoach: career.role == .gmAndHeadCoach,
                userCoachingStyle: career.coachingStyle,
                marketRivals: CoachCarouselEngine.demand(for: candidate).rivalTeams,
                fallbackCandidate: fallbackCandidate(excluding: candidate),
                onHire: { hire(candidate) },
                onRejected: {
                    rejectedCandidates.insert(candidate.id)
                    // A man who has signed elsewhere is out of the decision, so
                    // he leaves the shortlist too — otherwise the tray keeps
                    // quoting his salary and the table keeps a dead column.
                    compareIDs.removeAll { $0 == candidate.id }
                }
            )
        }
        // The compare table is a `.sheet`, not a second `.fullScreenCover`: two
        // covers on one view fight over the same presentation slot, and the
        // negotiation cover above must win it. `onDismiss` hands the profile
        // request over once the table is genuinely gone — the same ordering
        // `pendingHire` relies on.
        .sheet(isPresented: $showCompareSheet, onDismiss: {
            if let id = pendingProfileID {
                pendingProfileID = nil
                selectedCandidate = candidates.first { $0.id == id }
            }
        }) {
            // Two columns is the floor: a "comparison" of one man is the
            // profile he already has.
            if compareEntries.count >= 2 {
                CandidateCompareSheet(
                    entries: compareEntries,
                    role: role,
                    currentCoachName: currentCoach?.fullName,
                    onOpenProfile: { id in
                        pendingProfileID = id
                        showCompareSheet = false
                    }
                )
            }
        }
    }

    // MARK: - Budget Header

    private var budgetHeader: some View {
        VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Budget Remaining")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text("$\(formatBudget(remainingBudget))M")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(remainingBudget > 0 ? Color.success : Color.dangerText)
                }
                Spacer()

                // Fix #58: Scheme filter dropdown
                Menu {
                    ForEach(availableSchemes, id: \.self) { scheme in
                        Button {
                            schemeFilter = scheme
                        } label: {
                            HStack {
                                Text(scheme)
                                if schemeFilter == scheme {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: DSType.Size.footnote))
                        Text(schemeFilter == "All" ? "Scheme" : schemeFilter)
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(schemeFilter == "All" ? Color.textSecondary : Color.accentGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
                }

                Spacer().frame(width: 8)

                // #20: Personality filter dropdown
                Menu {
                    Button {
                        personalityFilter = "All"
                    } label: {
                        HStack {
                            Text("All")
                            if personalityFilter == "All" {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    ForEach(PersonalityArchetype.allCases, id: \.rawValue) { archetype in
                        Button {
                            personalityFilter = archetype.rawValue
                        } label: {
                            HStack {
                                Text(archetype.displayName)
                                if personalityFilter == archetype.rawValue {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: DSType.Size.footnote))
                        Text(personalityFilter == "All"
                             ? "Personality"
                             : (PersonalityArchetype(rawValue: personalityFilter)?.displayName ?? "Personality"))
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(personalityFilter == "All" ? Color.textSecondary : Color.accentGold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
                }

                Spacer().frame(width: 8)

                // #17: Color legend toggle
                Button {
                    showRatingLegend.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: DSType.Size.caption))
                        Text("Legend")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(showRatingLegend ? Color.accentGold : Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
                }

                // The pool size used to end this row as grey caption text —
                // the last thing after three filter chips and a switch, in the
                // one spot on the screen the eye reaches last. It is the size
                // of the market and it belongs beside the title; it now lives
                // in the navigation bar (see the toolbar on the body).
            }

            // #3067: the max-salary ceiling, replacing Fix #39's binary
            // "Affordable" switch. It gets its own row rather than a fourth
            // seat in the chip strip above, which already carries two menus and
            // a legend button and had no width left for a control that needs a
            // track to drag along.
            if let range = salarySliderRange, let cap = salaryCap {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max salary")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        Spacer()
                        Text("$\(formatBudget(cap))M")
                            .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                            .foregroundStyle(isSalaryCapNarrowed ? Color.accentGold : Color.textSecondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(cap) },
                            set: { maxSalary = $0 }
                        ),
                        in: range,
                        // $50k. Fine enough that a drag moves the one-decimal
                        // figure above smoothly, coarse enough that the head
                        // coach's $3M-$32M band is not 29,000 stops.
                        step: 50
                    )
                    .tint(Color.accentGold)
                    .accessibilityLabel("Maximum salary")
                    .accessibilityValue("$\(formatBudget(cap)) million")
                }
            }

            // #153: Value column legend
            if showValueLegend {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.accentGold)
                    Text("Val = skill-to-salary ratio: Great = high skill/low salary, Poor = low skill/high salary")
                        .font(.system(size: DSType.Size.micro, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button { showValueLegend = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .accessibilityLabel("Dismiss value legend")
                }
                .padding(8)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
            }

            // #151: Scheme info tooltip
            if showSchemeTip, let first = sortedCandidates.first {
                let label = schemeLabel(first)
                let desc = schemeDescription(label)
                if !desc.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.accentBlue)
                        Text("\(label): \(desc)")
                            .font(.system(size: DSType.Size.micro, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Button { showSchemeTip = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: DSType.Size.footnote))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .accessibilityLabel("Dismiss scheme tip")
                    }
                    .padding(8)
                    .background(Color.accentBlue.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            // #17: Rating color legend
            if showRatingLegend {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.accentGold)
                        legendSwatch(color: .success, label: "≥80 Elite")
                        legendSwatch(color: .accentGold, label: "60–79 Solid")
                        legendSwatch(color: .warning, label: "40–59 OK")
                        legendSwatch(color: .danger, label: "<40 Poor")
                        Spacer()
                        Button { showRatingLegend = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: DSType.Size.footnote))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .accessibilityLabel("Dismiss legend")
                    }
                    // A row can carry five badges and none of them was explained
                    // anywhere — the flame's meaning reached VoiceOver and nobody
                    // else. This is the only legend on the screen, so it explains
                    // the badges too, not just the colours.
                    Text("TOP 3 OVR = best OVR on the board \u{00B7} For Us = fit with THIS club: what the seat is bought for, your installed scheme and chemistry with your head coach \u{00B7} FREE AGENT = real out-of-work coach \u{00B7} flame = rival teams bidding \u{00B7} Ceiling badge = potential, Elite down to Low \u{00B7} VS box = pin up to \(CandidateCompareSheet.maxCandidates) and hold them side by side")
                        .font(.system(size: DSType.Size.micro, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(8)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
            }

            // Fix #63: Current coach comparison bar
            if let current = currentCoach {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.accentGold)
                    Text("Replacing:")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                    Text(current.fullName)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("OVR \(coachOverall(current))")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(coachOverall(current)))
                    Text("\u{00B7}")
                        .foregroundStyle(Color.textTertiary)
                    Text(salaryFormatted(current.salary))
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.accentGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Table Header (Fix #42: simplified columns — OVR + numeric skills)

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            headerButton("Name", column: .name, width: nil, alignment: .leading)
            headerButton("Age", column: .age, width: 34)
            // #151: Scheme column with info button
            Button {
                showSchemeTip.toggle()
            } label: {
                HStack(spacing: 2) {
                    Text("Scheme")
                    Image(systemName: "info.circle")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.accentBlue.opacity(0.85))
                }
                .frame(width: 70)
            }
            .foregroundStyle(sortColumn == .scheme ? Color.accentGold : Color.textTertiary)
            .accessibilityLabel("Scheme column")
            .accessibilityHint("Toggle scheme info")
            // Fix #38: Scheme fit column header — only when team has a comparable scheme.
            if hasInferableTeamScheme {
                Text("Fit")
                    .frame(width: 32)
            }
            // The one sortable column that is about THIS club rather than about
            // the man in the abstract. See `teamFitScore`.
            headerButton("For Us", column: .teamFit, width: 44)
            headerButton("OVR", column: .ovr, width: 36)
            // #18: Highlight role-relevant attribute headers with a gold dot.
            headerButton("Play", column: .play, width: 36, keyForRole: roleHighlights("playCalling"))
            headerButton("Dev", column: .dev, width: 36, keyForRole: roleHighlights("playerDevelopment"))
            headerButton("Game", column: .game, width: 36, keyForRole: roleHighlights("gamePlanning"))
            headerButton("Salary", column: .salary, width: 56)
            // Fix #60 + #153: Value column with info legend
            Button {
                showValueLegend.toggle()
            } label: {
                HStack(spacing: 2) {
                    Text("Val")
                    Image(systemName: "info.circle")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.accentGold.opacity(0.85))
                }
                .frame(width: 40)
            }
            .foregroundStyle(sortColumn == .value ? Color.accentGold : Color.textTertiary)
            .accessibilityLabel("Value column")
            .accessibilityHint("Toggle value legend")
            // Status column
            Text("")
                .frame(width: 64)
            // Shortlist column. A word rather than an icon: every other cell in
            // this strip is a word, and "VS" is the question the box answers.
            Text("VS")
                .frame(width: 40)
                .accessibilityLabel("Compare column")
        }
        .font(.system(size: DSType.Size.micro, weight: .semibold))
        .foregroundStyle(Color.textTertiary)
    }

    private func headerButton(_ title: String, column: SortColumn, width: CGFloat?, alignment: Alignment = .center, keyForRole: Bool = false) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = false
            }
        } label: {
            HStack(spacing: 2) {
                // #18: Subtle gold dot when this attribute is a focus for the role being hired.
                if keyForRole {
                    Circle()
                        .fill(Color.accentGold)
                        .frame(width: 4, height: 4)
                }
                Text(title)
                    .fontWeight(keyForRole ? .black : .semibold)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: DSType.Size.micro))
                }
            }
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width)
        }
        .foregroundStyle(sortColumn == column ? Color.accentGold : (keyForRole ? Color.accentGold.opacity(0.85) : Color.textTertiary))
    }

    /// #18: Whether the given Coach attribute key is a focus attribute for the role being hired.
    private func roleHighlights(_ attr: String) -> Bool {
        role.focusAttributes.contains(attr)
    }

    /// #19: Personality effect lines for the row's tappable popover (reuses CandidateDetailSheet's effect set).
    private func personalityEffectsForRow(_ candidate: Coach) -> [String] {
        switch candidate.personality {
        case .teamLeader:        return ["Player morale +5%", "Team chemistry +3%"]
        case .loneWolf:          return ["Individual skill dev +8%", "Team chemistry -3%"]
        case .feelPlayer:        return ["Adaptability +5%", "Consistency -3%"]
        case .steadyPerformer:   return ["Consistency +5%", "Development stability +3%"]
        case .dramaQueen:        return ["Media handling +8%", "Locker room drama risk +5%"]
        case .quietProfessional: return ["Discipline +5%", "Media handling -3%"]
        case .mentor:            return ["Player development +8%", "Young player growth +5%"]
        case .fieryCompetitor:   return ["Motivation +8%", "Discipline risk +3%"]
        case .classClown:        return ["Morale boost +5%", "Discipline -3%"]
        }
    }

    /// #17: Small swatch used inside the rating-color legend.
    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: DSType.Size.micro, weight: .medium))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Candidate Row (Fix #42: one star rating + numeric skill values)

    private func candidateRow(_ candidate: Coach) -> some View {
        let isOverBudget = candidate.salary > remainingBudget
        let isHired = hiredCoachID == candidate.id
        let isRejected = rejectedCandidates.contains(candidate.id)
        let ovr = coachOverall(candidate)
        let isTop3 = top3IDs.contains(candidate.id)
        let val = valueScore(candidate)
        let forUs = teamFitScore(candidate)
        // Fix #63: OVR delta vs current coach (cached current OVR — avoids per-row recompute)
        let ovrDelta: Int? = cachedCurrentCoachOVR.map { ovr - $0 }

        return HStack(spacing: 0) {
            Button {
                if !isRejected { selectedCandidate = candidate }
            } label: {
                HStack(spacing: 0) {
                    // Fix #55: Larger name area with personality + top-3 badge
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(candidate.fullName)
                                .font(.system(size: DSType.Size.body, weight: .bold))
                                .foregroundStyle(isOverBudget ? Color.textTertiary : Color.textPrimary)
                                .lineLimit(1)
                            // Potential label badge
                            let potLabel = candidate.potentialLabel(seasonsOnTeam: 0)
                            Text(potLabel)
                                .font(.system(size: DSType.Size.micro, weight: .bold))
                                .foregroundStyle(potentialBadgeColor(potLabel))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(potentialBadgeColor(potLabel).opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            // Fix #56 + #16: Self-explanatory "TOP 3" badge for top-3 candidates.
                            // The badge now carries its own reason. It is
                            // awarded on OVR and nothing else (`cachedTop3IDs`),
                            // and that fact was written down once, inside a
                            // legend the user has to open — so a gold badge on
                            // a row could as easily have meant best value, best
                            // fit or shortest queue of rivals.
                            if isTop3 {
                                Text("TOP 3 OVR")
                                    .font(.system(size: DSType.Size.micro, weight: .black))
                                    .foregroundStyle(Color.backgroundPrimary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 3))
                                    .accessibilityLabel("Top 3 on this board by overall rating")
                            }
                            // Task #96: a real out-of-work coach from the league's
                            // market — somebody the news has already talked about,
                            // possibly a man this club lost — as opposed to an
                            // invented candidate. Worth calling out: he has a real
                            // record, and every AI club is bidding for him too.
                            if marketCandidateIDs.contains(candidate.id) {
                                Text("FREE AGENT")
                                    .font(.system(size: DSType.Size.micro, weight: .black))
                                    .foregroundStyle(Color.accentBlue)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.accentBlue.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                                    .accessibilityLabel("Free agent coach, currently out of work")
                            }
                            // R30 Market 2.0: rival-demand badge — flame + how many
                            // other teams are pursuing this candidate.
                            let demand = CoachCarouselEngine.demand(for: candidate)
                            if demand.rivalTeams > 0 {
                                let demandColor: Color = demand.level == .high ? .danger : .warning
                                HStack(spacing: 2) {
                                    Image(systemName: "flame.fill")
                                        .font(.system(size: DSType.Size.micro))
                                    Text("\(demand.rivalTeams)")
                                        .font(.system(size: DSType.Size.micro, weight: .black).monospacedDigit())
                                }
                                .foregroundStyle(demandColor)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(demandColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                                .accessibilityLabel("\(demand.rivalTeams) rival teams pursuing")
                            }
                        }
                        HStack(spacing: 4) {
                            // Fix #59 + #148: Coaching personality — shorter labels to avoid truncation.
                            // #19: Tappable personality reveals an effects menu.
                            Menu {
                                Text(candidate.personality.displayName)
                                ForEach(personalityEffectsForRow(candidate), id: \.self) { line in
                                    Text(line)
                                }
                            } label: {
                                HStack(spacing: 2) {
                                    Text(candidate.personality.shortLabel)
                                        .font(.system(size: DSType.Size.caption, weight: .medium))
                                        .foregroundStyle(Color.accentBlue)
                                        .lineLimit(1)
                                    Image(systemName: "info.circle")
                                        .font(.system(size: DSType.Size.micro))
                                        .foregroundStyle(Color.accentBlue.opacity(0.85))
                                }
                            }
                            .buttonStyle(.plain)
                            // Fix #63: OVR delta vs current
                            if let delta = ovrDelta {
                                Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                                    .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                                    .foregroundStyle(delta > 0 ? Color.success : delta < 0 ? Color.dangerText : Color.textTertiary)
                            }
                        }
                    }
                    .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)

                    // Age
                    Text("\(candidate.age)")
                        .font(.system(size: DSType.Size.caption).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 34)

                    // Scheme
                    Text(schemeLabel(candidate))
                        .font(.system(size: DSType.Size.caption, weight: .medium))
                        .foregroundStyle(Color.accentBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.91)  // floor the shrink at 10pt (11 * 0.91)
                        .frame(width: 70)

                    // Fix #38: Scheme/roster fit indicator — only when team has comparable scheme.
                    if hasInferableTeamScheme {
                        Group {
                            if let fit = schemeFit(for: candidate) {
                                Circle()
                                    .fill(fit.color)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(fit.color.opacity(0.5), lineWidth: 1)
                                    )
                                    .accessibilityLabel("Scheme fit: \(fit.label)")
                            } else {
                                Text("--")
                                    .font(.system(size: DSType.Size.micro))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .frame(width: 32)
                    }

                    // "For Us" composite
                    Text("\(forUs)")
                        .font(.system(size: DSType.Size.caption, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.forRating(forUs))
                        .frame(width: 44)
                        .accessibilityLabel("Fit with this staff \(forUs) of 100")

                    // OVR numeric
                    Text("\(ovr)")
                        .font(.system(size: DSType.Size.caption, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.forRating(ovr))
                        .frame(width: 36)

                    // Key skill numerics
                    Text("\(candidate.playCalling)")
                        .font(.system(size: DSType.Size.caption, design: .monospaced))
                        .foregroundStyle(Color.forRating(candidate.playCalling))
                        .frame(width: 36)

                    Text("\(candidate.playerDevelopment)")
                        .font(.system(size: DSType.Size.caption, design: .monospaced))
                        .foregroundStyle(Color.forRating(candidate.playerDevelopment))
                        .frame(width: 36)

                    Text("\(candidate.gamePlanning)")
                        .font(.system(size: DSType.Size.caption, design: .monospaced))
                        .foregroundStyle(Color.forRating(candidate.gamePlanning))
                        .frame(width: 36)

                    // Salary
                    Text(salaryFormatted(candidate.salary))
                        .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                        .foregroundStyle(isOverBudget ? Color.dangerText : Color.textSecondary)
                        .frame(width: 56)

                    // Fix #60: Value badge
                    Text(val.label)
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                        .foregroundStyle(val.color)
                        .frame(width: 40)

                    // Status indicator
                    Group {
                        if isHired {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: DSType.Size.body))
                                .foregroundStyle(Color.success)
                        } else if isRejected {
                            // #271: Rejected candidate badge
                            Text("Signed elsewhere")
                                .font(.system(size: DSType.Size.micro, weight: .bold))
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                        } else if isOverBudget {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: DSType.Size.body))
                                .foregroundStyle(Color.dangerText.opacity(0.85))
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: DSType.Size.caption, weight: .semibold))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .frame(width: 64)
                }
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRejected)
            .opacity(isRejected ? 0.45 : isOverBudget ? 0.6 : 1.0)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(candidate.fullName), \(candidate.personality.displayName), age \(candidate.age), overall \(ovr), salary \(candidate.salary) thousand, value \(val.label)")
            .accessibilityHint(isRejected ? "Already rejected" : "Tap to view candidate details")

            // The pin sits OUTSIDE the row button rather than inside its
            // label: a control nested in a Button's label does not reliably
            // get the tap, and the row's tap is the way into the negotiation
            // — the one thing on this board that must never misfire.
            compareToggle(for: candidate, isRejected: isRejected)
        }
        .padding(.horizontal, 12)
        .background(
            Group {
                if isHired {
                    Color.success.opacity(0.06)
                } else if isRejected {
                    Color.backgroundTertiary.opacity(0.3)
                } else if isTop3 {
                    // Fix #56: Subtle gold highlight for top 3
                    Color.accentGold.opacity(0.04)
                } else {
                    Color.clear
                }
            }
        )
        // Fix #56: Gold left border for top 3
        .overlay(alignment: .leading) {
            if isTop3 {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentGold)
                    .frame(width: 3)
            }
        }
    }

    // MARK: - Shortlist Controls

    /// The per-row pin. The same checkbox vocabulary team selection's compare
    /// mode uses, so "empty square = not picked, blue tick = picked" means one
    /// thing across the app.
    ///
    /// Always on the row rather than behind a compare MODE: this board's tap is
    /// the way into the negotiation, and a mode that repurposes it would put a
    /// second meaning on the most important gesture on the screen.
    private func compareToggle(for candidate: Coach, isRejected: Bool) -> some View {
        let isPinned = compareIDs.contains(candidate.id)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                toggleCompare(candidate)
            }
        } label: {
            Image(systemName: isPinned ? "checkmark.square.fill" : "square")
                .font(.system(size: DSType.Size.callout, weight: .semibold))
                .foregroundStyle(isPinned ? Color.accentBlue : Color.textTertiary)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRejected)
        .accessibilityLabel(isPinned
                            ? "Remove \(candidate.fullName) from the comparison"
                            : "Add \(candidate.fullName) to the comparison")
        .accessibilityHint(!isPinned && compareIDs.count >= CandidateCompareSheet.maxCandidates
                           ? "Replaces the first pinned candidate"
                           : "")
    }

    /// The tray that appears with the first pin.
    @ViewBuilder
    private var compareTray: some View {
        if !compareIDs.isEmpty {
            DSActionBar(
                explainer: .init(
                    title: "Shortlist",
                    message: compareTrayMessage
                ),
                ghost: .init(
                    title: "Clear",
                    caption: "unpins all",
                    handler: {
                        withAnimation(.easeInOut(duration: 0.18)) { compareIDs.removeAll() }
                    }
                ),
                primary: .init(
                    title: "Compare (\(compareIDs.count))",
                    caption: compareIDs.count < 2 ? "pin one more" : "side by side",
                    isEnabled: compareIDs.count >= 2,
                    accessibilityLabel: "Compare \(compareIDs.count) pinned candidates",
                    handler: { openCompare() }
                )
            )
            .transition(.move(edge: .bottom))
        }
    }

    /// States the trade-off in the bar itself.
    ///
    /// With exactly two men pinned the interesting fact is not that they are
    /// pinned — it is which of them is better and what the better one costs
    /// extra, which is the whole question the table then answers in detail. The
    /// third case (better AND cheaper) is worth its own sentence: that is not a
    /// trade-off at all, and the user should be told so rather than left to
    /// discover it in a table.
    private var compareTrayMessage: String {
        let pinned = comparePinned
        guard let first = pinned.first else { return "" }
        if pinned.count == 1 {
            return "**\(first.fullName)** pinned \u{2014} pin one more to hold them side by side."
        }
        guard pinned.count == 2 else {
            return pinned.map(\.lastName).joined(separator: " \u{00B7} ") + " \u{2014} three men, one table."
        }
        let second = pinned[1]
        let gap = coachOverall(first) - coachOverall(second)
        if gap == 0 {
            return "**\(first.lastName)** and **\(second.lastName)** rate level at **\(coachOverall(first)) OVR** \u{2014} money and fit decide it."
        }
        let better = gap > 0 ? first : second
        let other = gap > 0 ? second : first
        let payGap = better.salary - other.salary
        if payGap > 0 {
            return "**\(better.lastName)** is **+\(abs(gap)) OVR** on \(other.lastName), at **\(salaryFormatted(payGap))/yr** more."
        }
        if payGap == 0 {
            return "**\(better.lastName)** is **+\(abs(gap)) OVR** on \(other.lastName) for the same money."
        }
        return "**\(better.lastName)** is **+\(abs(gap)) OVR** on \(other.lastName) and **\(salaryFormatted(-payGap))/yr** cheaper \u{2014} no trade-off here."
    }

    // MARK: - Helpers

    /// Color for potential label badge text.
    private func potentialBadgeColor(_ label: String) -> Color {
        switch label {
        case "Elite Ceiling":   return Color.accentGold
        case "High Ceiling":    return .success
        case "Solid Ceiling":   return Color.accentBlue
        case "Limited Upside":  return .orange
        case "Low Ceiling":     return .red
        default:                return Color.textSecondary
        }
    }

    private func schemeLabel(_ coach: Coach) -> String {
        if let o = coach.offensiveScheme { return o.displayName }
        if let d = coach.defensiveScheme { return d.displayName }
        return "--"
    }

    // MARK: - Scheme Fit (Fix #38)

    /// Determines how well a candidate's scheme fits the team's current scheme.
    /// Falls back from HC → OC/DC when no HC scheme set. Returns nil when no
    /// comparable scheme is available on the team or candidate.
    /// The club's installed scheme on the side of the ball this candidate coaches —
    /// the same value `schemeFit(for:)` rates against, so the detail card can name it.
    private func installedSchemeName(for candidate: Coach) -> String? {
        if candidate.offensiveScheme != nil { return teamOffensiveScheme?.displayName }
        if candidate.defensiveScheme != nil { return teamDefensiveScheme?.displayName }
        return nil
    }

    private func schemeFit(for candidate: Coach) -> (color: Color, label: String)? {
        // Compare offensive schemes against effective team offensive scheme.
        if let candidateOff = candidate.offensiveScheme {
            if let teamOff = teamOffensiveScheme {
                if candidateOff == teamOff {
                    return (.success, "Great")
                }
                // Similar scheme families
                let passingSchemes: Set<OffensiveScheme> = [.westCoast, .airRaid, .proPassing, .spread]
                let runSchemes: Set<OffensiveScheme> = [.powerRun, .shanahan, .option, .rpo]
                if (passingSchemes.contains(candidateOff) && passingSchemes.contains(teamOff))
                    || (runSchemes.contains(candidateOff) && runSchemes.contains(teamOff)) {
                    return (.warning, "OK")
                }
                return (.danger, "Poor")
            }
        }

        // Compare defensive schemes against effective team defensive scheme.
        if let candidateDef = candidate.defensiveScheme {
            if let teamDef = teamDefensiveScheme {
                if candidateDef == teamDef {
                    return (.success, "Great")
                }
                let frontSchemes: Set<DefensiveScheme> = [.base34, .base43]
                let coverageSchemes: Set<DefensiveScheme> = [.cover3, .tampa2, .pressMan]
                let flexSchemes: Set<DefensiveScheme> = [.multiple, .hybrid]
                if (frontSchemes.contains(candidateDef) && frontSchemes.contains(teamDef))
                    || (coverageSchemes.contains(candidateDef) && coverageSchemes.contains(teamDef))
                    || (flexSchemes.contains(candidateDef) && flexSchemes.contains(teamDef)) {
                    return (.warning, "OK")
                }
                return (.danger, "Poor")
            }
        }

        return nil
    }

    private func salaryFormatted(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "$%.1fM", millions)
    }

    private func formatBudget(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "%.1f", millions)
    }

    /// #151: Scheme tooltip descriptions.
    private func schemeDescription(_ label: String) -> String {
        switch label {
        case "West Coast":  return "Short-to-intermediate passing, high-percentage throws"
        case "Air Raid":    return "Four/five-wide sets, vertical passing emphasis"
        case "Spread":      return "Space the field with spread formations"
        case "Power Run":   return "Downhill running with pulling guards"
        case "Shanahan":    return "Outside zone running, play-action boots"
        case "Pro Passing": return "Pro-style balanced attack, under-center play-action"
        case "RPO":         return "Run-pass options, QB reads defense post-snap"
        case "Option":      return "Triple/read-option, requires athletic QB"
        case "3-4 Base":    return "Versatile OLBs who rush and drop into coverage"
        case "4-3 Base":    return "Four down linemen generating pass rush"
        case "Cover 3":     return "Three deep defenders, four underneath zones"
        case "Press Man":   return "Aggressive press coverage at the line"
        case "Tampa 2":     return "Zone coverage, requires fast MLB for deep middle"
        case "Multiple":    return "Disguised fronts and coverages pre-snap"
        case "Hybrid":      return "Blends 3-4/4-3 with positionless players"
        default:            return ""
        }
    }

    /// #160: OVR context label — league average comparison.
    private func ovrContextLabel(_ ovr: Int) -> String {
        if ovr >= 80 { return "Elite" }
        if ovr >= 70 { return "Above Avg" }
        if ovr >= 60 { return "Average" }
        if ovr >= 50 { return "Below Avg" }
        return "Poor"
    }

    /// Fix #67: Candidate ranking by OVR among filtered list.
    /// Called once when the detail sheet opens — no longer per-row.
    ///
    /// Standard competition ranking: two men on the same OVR share a number,
    /// rather than the sort deciding which of them gets called "#1".
    private func candidateRank(for candidate: Coach) -> Int {
        guard filteredCandidates.contains(where: { $0.id == candidate.id }) else { return 0 }
        let ovr = coachOverall(candidate)
        return filteredCandidates.filter { coachOverall($0) > ovr }.count + 1
    }

    // MARK: - Hire Action

    private func hire(_ candidate: Coach) {
        guard candidate.salary <= remainingBudget else { return }

        // Task #96: the incumbent is RELEASED, not deleted. A `Coach` row is
        // permanent in this game — `LeagueEvent.coachID` is a live fetch by id
        // whose reader reads `coach.faceID` off the row, so
        // deleting the row blanks the subject of every archived news item about
        // him and orphans his face reservation until the next `FaceLibrary`
        // backfill. It also threw away the man himself: replaced coaches now join
        // the unemployed bench, where `CoachMarketEngine` can place them on
        // another staff or, in time, retire them out of the profession — the same
        // door every AI-fired coach goes through.
        let descriptor = FetchDescriptor<Coach>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        if let existing = try? modelContext.fetch(descriptor) {
            for outgoing in existing where outgoing.role == role && outgoing.id != candidate.id {
                outgoing.teamID = nil
                outgoing.contractYearsRemaining = 0
                outgoing.unemployedSeasons = 0
            }
        }

        candidate.teamID = teamID
        candidate.careerID = career.id
        candidate.hireSeasonYear = career.currentSeason
        candidate.contractYearsRemaining = 3
        // Task #133: he keeps the job through the advance out of this phase.
        // Rival clubs poach on that advance, and a man signed an hour ago has
        // not yet coached anything to be poached out of.
        candidate.signedThisOffseason = true
        // Task #96: back in work, so his time on the bench stops counting toward
        // `CoachMarketEngine.settleUnemployment`'s attrition roll. No-op for an
        // invented candidate, which has never been out of work.
        candidate.unemployedSeasons = 0
        // Phase 4 faces: a candidate list carries a NON-reserving preview
        // portrait (`CoachingEngine.generateCoachCandidates`), so every hire has
        // to claim it here. Without the claim the registry never learns the
        // face is taken and the next person drawn from the same free list — the
        // very next hire in this same wizard — can be handed the same portrait.
        // A market coach already holds his reservation, and `claimFace` returns
        // it unchanged when the registry names him as the holder.
        candidate.faceID = FaceLibrary.shared.claimFace(
            candidate.faceID, personID: candidate.id,
            role: .coach, age: candidate.age, position: nil,
            gender: FacePersonGender(tag: candidate.gender)
        )
        // Only an invented candidate needs inserting; a market coach is already
        // a row in this store and re-inserting is at best a no-op.
        if candidate.modelContext == nil {
            modelContext.insert(candidate)
        }
        hiredCoachID = candidate.id

        // R30: every hire joins the user's coaching tree.
        do {
            var tree = career.coachingTree
            CoachRelationshipEngine.updateCoachingTree(
                tree: &tree.entries,
                coach: candidate,
                event: "hired",
                season: career.currentSeason
            )
            career.coachingTree = tree
        }

        // Fix #88: Save context before dismissing so CoachingStaffView's @Query refreshes
        try? modelContext.save()

        // Fix #49 / wave 5b: hand the hire up so the host can end the process in
        // a `DSResultSheet`. Parked rather than fired: the negotiation cover is
        // still up, and reporting from underneath it is what the old 0.6 s + 0.4 s
        // deadline pair was working around. `onDismiss` fires when the cover is
        // genuinely gone. No `dismiss()` either — the result sheet owns the
        // ending now, and closing this view would have pulled the surface out
        // from under it (P5's one-dismissal corollary).
        // The seat is filled, so the shortlist weighing candidates for it has
        // nothing left to weigh — and the tray must not still be offering a
        // comparison over the result sheet.
        compareIDs.removeAll()

        pendingHire = (name: candidate.fullName, role: role.displayName, salary: candidate.salary)
        selectedCandidate = nil
    }

    // MARK: - Fallback candidate

    /// The best man left on the board for this seat if the one being negotiated
    /// with walks away.
    ///
    /// Read off `candidates` rather than `filteredCandidates`: the question is
    /// who else could take the job, and a Scheme filter or a salary ceiling set
    /// two minutes ago is not an answer to it. Men who have already signed
    /// elsewhere are out — `onRejected` retires them from the board for good.
    private func fallbackCandidate(excluding candidate: Coach) -> FallbackCandidate? {
        let field = candidates.filter {
            $0.id != candidate.id
                && $0.id != hiredCoachID
                && !rejectedCandidates.contains($0.id)
        }
        guard let next = field.max(by: { coachOverall($0) < coachOverall($1) }) else { return nil }
        return FallbackCandidate(
            name: next.fullName,
            ovr: coachOverall(next),
            salary: next.salary,
            isAffordable: next.salary <= remainingBudget
        )
    }
}

// MARK: - Fallback Candidate

/// The next man at this seat, for the negotiation card's "if he walks" line.
private struct FallbackCandidate {
    let name: String
    let ovr: Int
    /// Asking salary, in thousands.
    let salary: Int
    let isAffordable: Bool
}

// MARK: - Candidate Detail / Negotiation Sheet

private struct CandidateDetailSheet: View {
    let candidate: Coach
    let remainingBudget: Int
    let isHired: Bool
    let headCoach: Coach?
    let currentCoach: Coach?
    let candidateRank: Int
    let totalCandidates: Int
    let schemeFitResult: (color: Color, label: String)?
    /// The scheme the club actually runs on this candidate's side of the ball.
    /// `schemeFitResult` is computed from it, but the card could only name a
    /// head coach — so a GM+HC career saw the rating suppressed even when a
    /// coordinator had a scheme installed.
    let installedSchemeName: String?
    /// BUG FIX: True when the user's career role is .gmAndHeadCoach (no HC Coach record exists).
    let userIsHeadCoach: Bool
    /// BUG FIX: User's coaching style — used as the HC reference for chemistry when userIsHeadCoach.
    let userCoachingStyle: CoachingStyle?
    /// R30 Market 2.0: how many rival teams are pursuing this candidate.
    /// Competition raises rejection risk unless the user overbids.
    let marketRivals: Int
    /// The next man on the board if this one says no. `nil` when he is the only
    /// candidate left for the seat.
    let fallbackCandidate: FallbackCandidate?
    let onHire: () -> Void
    /// #271: Callback when candidate rejects offer
    var onRejected: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var proposedSalary: Double
    @State private var proposedYears: Int = 3
    @State private var negotiationResult: NegotiationResult?

    init(candidate: Coach, remainingBudget: Int, isHired: Bool, headCoach: Coach?, currentCoach: Coach?, candidateRank: Int, totalCandidates: Int, schemeFitResult: (color: Color, label: String)?, installedSchemeName: String? = nil, userIsHeadCoach: Bool = false, userCoachingStyle: CoachingStyle? = nil, marketRivals: Int = 0, fallbackCandidate: FallbackCandidate? = nil, onHire: @escaping () -> Void, onRejected: (() -> Void)? = nil) {
        self.candidate = candidate
        self.remainingBudget = remainingBudget
        self.isHired = isHired
        self.headCoach = headCoach
        self.currentCoach = currentCoach
        self.candidateRank = candidateRank
        self.totalCandidates = totalCandidates
        self.schemeFitResult = schemeFitResult
        self.installedSchemeName = installedSchemeName
        self.userIsHeadCoach = userIsHeadCoach
        self.userCoachingStyle = userCoachingStyle
        self.marketRivals = marketRivals
        self.fallbackCandidate = fallbackCandidate
        self.onHire = onHire
        self.onRejected = onRejected
        self._proposedSalary = State(initialValue: Double(candidate.salary))
    }

    private var askingSalary: Double { Double(candidate.salary) }

    /// R30 Market 2.0: extra rejection risk from rival teams pursuing the same
    /// candidate. Each rival adds 6%; overbidding melts it away — +10% over
    /// asking locks rivals out entirely.
    private var competitionRisk: Double {
        guard marketRivals > 0 else { return 0.0 }
        let overbid = max(0.0, proposedSalary / askingSalary - 1.0)
        let mitigation = max(0.0, 1.0 - overbid * 10.0)
        return Double(marketRivals) * 0.06 * mitigation
    }

    /// Chance the candidate rejects the offer (0.0 - 1.0): below-asking
    /// discount risk plus rival-market competition (R30).
    private var rejectionChance: Double {
        let discountRisk: Double
        if proposedSalary < askingSalary {
            let discount = (askingSalary - proposedSalary) / askingSalary
            // Up to 90% rejection at 50%+ discount
            discountRisk = min(0.9, discount * 1.8)
        } else {
            discountRisk = 0.0
        }
        return min(0.95, discountRisk + competitionRisk)
    }

    /// The salary where acceptance crosses 50% — below it the roll in
    /// `makeOffer` is likelier to fail than not.
    ///
    /// Inverts `rejectionChance`: under asking, the rival term is constant and
    /// the discount term is linear at 1.8x, so the crossing has a closed form
    /// and the player can be told where it is instead of hunting for it by
    /// dragging. nil when the rivals alone already make the hire a coin flip.
    private var coinFlipSalary: Double? {
        let headroom = 0.5 - Double(marketRivals) * 0.06
        guard headroom > 0 else { return nil }
        return askingSalary * (1.0 - headroom / 1.8)
    }

    /// Fix #69: Acceptance likelihood label that updates with salary slider.
    private var acceptanceLikelihood: (label: String, color: Color) {
        let chance = 1.0 - rejectionChance
        if chance >= 0.95 { return ("Very High", .success) }
        if chance >= 0.75 { return ("High", .success) }
        if chance >= 0.50 { return ("Medium", .warning) }
        if chance >= 0.25 { return ("Low", .danger) }
        return ("Very Low", .danger)
    }

    private var isOverBudget: Bool {
        Int(proposedSalary) > remainingBudget
    }

    /// #162: Contract length effect description.
    private var contractLengthEffect: String {
        switch proposedYears {
        case 1:  return "Short deal: higher acceptance, but coach may leave soon"
        case 2:  return "Standard short: balanced flexibility and commitment"
        case 3:  return "Standard deal: good balance of cost and stability"
        case 4:  return "Long deal: coach expects slight discount, higher commitment"
        case 5:  return "Max deal: coach expects best terms, locked in long-term"
        default: return ""
        }
    }

    /// Fix #65: Budget remaining after this hire.
    private var budgetAfterHire: Int {
        remainingBudget - Int(proposedSalary)
    }

    /// #160: OVR context label.
    private func ovrContextLabel(_ ovr: Int) -> String {
        if ovr >= 80 { return "Elite" }
        if ovr >= 70 { return "Above Avg" }
        if ovr >= 60 { return "Average" }
        if ovr >= 50 { return "Below Avg" }
        return "Poor"
    }

    private func coachOverall(_ coach: Coach) -> Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

    // MARK: - #89: Coach Development Potential

    private var candidatePotentialLabel: String {
        candidate.potentialLabel(seasonsOnTeam: 0)
    }

    private var candidatePotentialColor: Color {
        let p = candidate.potential
        if p >= 85 { return .accentGold }
        if p >= 70 { return .success }
        if p >= 55 { return .accentBlue }
        if p >= 40 { return .warning }
        return .danger
    }

    // MARK: - #21: Career History

    /// Generates plausible career history lines from age, experience, and role.
    /// Uses simple deterministic rules so results are stable per candidate.
    private var careerHistoryLines: [String] {
        var lines: [String] = []
        let exp = max(candidate.yearsExperience, 0)
        if exp > 0 {
            lines.append("\(exp) year\(exp == 1 ? "" : "s") of coaching experience")
        } else {
            lines.append("First-time \(candidate.role.displayName.lowercased()) candidate")
        }

        // Hash the candidate ID to derive a stable count without storing extra state.
        let stableHash = abs(candidate.id.hashValue)

        if candidate.role == .headCoach {
            if candidate.age > 50 && exp > 12 {
                let stints = 1 + (stableHash % 2) // 1 or 2 prior HC stints
                lines.append("\(stints) previous head coach stint\(stints == 1 ? "" : "s")")
            } else if exp >= 8 {
                lines.append("Coordinator at \(2 + stableHash % 2) different teams")
            }
        } else if candidate.role == .offensiveCoordinator || candidate.role == .defensiveCoordinator {
            if exp >= 10 {
                lines.append("Coordinator at \(1 + stableHash % 3) prior team\(stableHash % 3 == 0 ? "" : "s")")
            } else if exp >= 4 {
                lines.append("Promoted from position coach")
            }
        } else if candidate.role == .assistantHeadCoach {
            if exp >= 8 {
                lines.append("Former coordinator with playoff experience")
            }
        } else {
            // Position coach
            if exp >= 6 {
                lines.append("Position coach at \(1 + stableHash % 3) prior team\(stableHash % 3 == 0 ? "" : "s")")
            } else if exp == 0 {
                lines.append("Recently moved from playing or college ranks")
            }
        }
        return Array(lines.prefix(3))
    }

    private var careerHistoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // "CAREER HISTORY" promised clubs, seasons and a won-lost record;
            // `careerHistoryLines` derives two summary lines from age and years
            // in the game. Title the card what it actually holds. (The sim does
            // not persist per-season coach history yet — when it does, this is
            // the card that earns the old name back.)
            Text("EXPERIENCE")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            ForEach(careerHistoryLines, id: \.self) { line in
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - #22: Projected Impact estimates

    /// Role-aware contribution estimates derived from the coach's attributes.
    /// Numbers are intentionally conservative.
    private var projectedImpactEstimates: [(label: String, value: String, icon: String, color: Color)] {
        let leagueAvg = 65.0
        var items: [(label: String, value: String, icon: String, color: Color)] = []

        let positionCoaches: Set<CoachRole> = [.qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach]
        let coordinators: Set<CoachRole> = [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator]
        let topRoles: Set<CoachRole> = [.headCoach, .assistantHeadCoach]

        if positionCoaches.contains(candidate.role) {
            // +X% position development (conservative 0.5–3% range).
            let dev = Double(candidate.playerDevelopment)
            let pct = max(-3.0, min(3.0, (dev - leagueAvg) * 0.05))
            let group = candidate.role.displayName.replacingOccurrences(of: "Coach", with: "").trimmingCharacters(in: .whitespaces)
            items.append((
                label: "\(group) development",
                value: "\(pct >= 0 ? "+" : "")\(String(format: "%.1f", pct))% / season",
                icon: "chart.line.uptrend.xyaxis",
                color: pct >= 0 ? .success : .danger
            ))

            let mot = Double(candidate.motivation)
            let moralePct = max(-2.0, min(2.0, (mot - leagueAvg) * 0.03))
            items.append((
                label: "Player morale",
                value: "\(moralePct >= 0 ? "+" : "")\(String(format: "%.1f", moralePct))%",
                icon: "heart.fill",
                color: moralePct >= 0 ? .success : .danger
            ))
        } else if coordinators.contains(candidate.role) {
            let play = Double(candidate.playCalling)
            let plan = Double(candidate.gamePlanning)
            let efficiency = max(-3.0, min(3.0, ((play + plan) / 2.0 - leagueAvg) * 0.05))
            let side = candidate.role == .offensiveCoordinator ? "offensive"
                : candidate.role == .defensiveCoordinator ? "defensive" : "special teams"
            items.append((
                label: "\(side.capitalized) efficiency",
                value: "\(efficiency >= 0 ? "+" : "")\(String(format: "%.1f", efficiency))%",
                icon: "bolt.horizontal.fill",
                color: efficiency >= 0 ? .success : .danger
            ))

            let dev = Double(candidate.playerDevelopment)
            let devPct = max(-2.0, min(2.0, (dev - leagueAvg) * 0.03))
            items.append((
                label: "Unit development",
                value: "\(devPct >= 0 ? "+" : "")\(String(format: "%.1f", devPct))% / season",
                icon: "chart.line.uptrend.xyaxis",
                color: devPct >= 0 ? .success : .danger
            ))
        } else if topRoles.contains(candidate.role) {
            // #3087: what the sim ACTUALLY applies for this seat, read straight
            // off `CoachingModifiers`, in place of the "Projected wins" figure
            // that used to sit here.
            //
            // That figure was `clamp((ovr·0.5 + mot·0.25 + disc·0.25 - 65) ·
            // 0.04, -2, 2)` — a display heuristic with no path into the engine.
            // The engine's coaching terms are all PER-PLAY (completion
            // probability, yards per carry, penalty frequency, pre-game morale),
            // and turning any of them into wins needs a plays-per-season and a
            // points-to-wins conversion this game does not have. Rather than
            // invent one, the card quotes the levers themselves.
            if candidate.role == .headCoach {
                // Mech 4 — the head coach sets the discipline that scales this
                // club's own penalty AND fumble frequencies. Mirrors
                // `CoachingModifiers.disciplineScale`, which is private.
                let scale = min(CoachingModifiers.disciplineScaleMax,
                                max(CoachingModifiers.disciplineScaleMin,
                                    1.0 - (Double(candidate.discipline) - CoachingModifiers.disciplineCenter)
                                        * CoachingModifiers.disciplineSlope))
                let penaltyPct = (scale - 1.0) * 100.0
                items.append((
                    label: "Penalties & fumbles",
                    value: "\(penaltyPct >= 0 ? "+" : "")\(String(format: "%.0f", penaltyPct))%",
                    icon: "flag.fill",
                    color: penaltyPct <= 0 ? .success : .danger
                ))
            } else {
                // Mech 2 — the assistant's game planning is a completion edge,
                // but only while he is the sharpest planner on the staff:
                // `CoachingModifiers.ratings` takes the max over HC/AHC/OC/DC.
                let edge = min(CoachingModifiers.planCompletionCap,
                               max(-CoachingModifiers.planCompletionCap,
                                   (Double(candidate.gamePlanning) - CoachingModifiers.planCenter)
                                       * CoachingModifiers.planCompletionSlope))
                let pts = edge * 100.0
                items.append((
                    label: "Game-plan edge",
                    value: "\(pts >= 0 ? "+" : "")\(String(format: "%.1f", pts)) pts completion",
                    icon: "doc.text.fill",
                    color: pts >= 0 ? .success : .danger
                ))
            }

            // Mech 3/5 — the pre-game morale bump, in points of morale.
            // Morale influence is taken from the best man on the staff and
            // motivation is the head coach's lever alone, so this is what the
            // candidate contributes when he is that man.
            var bump = (Double(candidate.moraleInfluence) - CoachingModifiers.moraleCenter)
                * CoachingModifiers.moraleInfluenceSlope
            if candidate.role == .headCoach {
                bump += (Double(candidate.motivation) - CoachingModifiers.moraleCenter)
                    * CoachingModifiers.motivationSlope
            }
            let morale = Int(min(CoachingModifiers.moraleBumpCap,
                                 max(-CoachingModifiers.moraleBumpCap, bump)).rounded())
            items.append((
                label: "Pre-game morale",
                value: "\(morale >= 0 ? "+" : "")\(morale) pts",
                icon: "heart.fill",
                color: morale >= 0 ? .success : .danger
            ))

            let dev = Double(candidate.playerDevelopment)
            let devPct = max(-2.0, min(2.0, (dev - leagueAvg) * 0.03))
            items.append((
                label: "Roster-wide dev",
                value: "\(devPct >= 0 ? "+" : "")\(String(format: "%.1f", devPct))% / season",
                icon: "chart.line.uptrend.xyaxis",
                color: devPct >= 0 ? .success : .danger
            ))

            let media = Double(candidate.mediaHandling)
            let repPct = max(-2.0, min(2.0, (media - leagueAvg) * 0.03))
            items.append((
                label: "Team reputation",
                value: "\(repPct >= 0 ? "+" : "")\(String(format: "%.1f", repPct))%",
                icon: "star.fill",
                color: repPct >= 0 ? .success : .danger
            ))
        } else {
            // Strength / medical / etc.
            let dev = Double(candidate.playerDevelopment)
            let pct = max(-2.0, min(2.0, (dev - leagueAvg) * 0.04))
            items.append((
                label: "Roster development",
                value: "\(pct >= 0 ? "+" : "")\(String(format: "%.1f", pct))% / season",
                icon: "chart.line.uptrend.xyaxis",
                color: pct >= 0 ? .success : .danger
            ))
        }

        return Array(items.prefix(3))
    }

    private var projectedImpactCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PROJECTED CONTRIBUTION")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            ForEach(projectedImpactEstimates, id: \.label) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.system(size: DSType.Size.footnote, weight: .semibold))
                        .foregroundStyle(item.color)
                        .frame(width: 18)
                    Text(item.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(item.value)
                        .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                        .foregroundStyle(item.color)
                }
            }

            Text("Estimates based on attribute deltas vs. league average.")
                .font(.system(size: DSType.Size.caption, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - #91: Other Teams' Interest

    private var demandBadge: some View {
        // R30 Market 2.0: badge reflects the actual rival count used in
        // negotiation math (was a rough OVR estimate before).
        let (label, icon): (String, String) = {
            if marketRivals >= 2 { return ("High demand (\(marketRivals) rival teams)", "flame.fill") }
            if marketRivals == 1 { return ("Moderate (1 rival team)", "person.2.fill") }
            return ("Limited interest", "person.fill")
        }()
        let color: Color = marketRivals >= 2 ? .danger : marketRivals == 1 ? .warning : .textTertiary
        return HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        // The longest chip in the header row, and the one that used to be
        // squeezed into "High dem…" by the pills beside it. It states its full
        // width and lets the row's `ViewThatFits` choose the arrangement.
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - #92: Negotiation Offer Assessment

    private var offerAssessment: (label: String, color: Color) {
        let ratio = proposedSalary / askingSalary
        if ratio >= 0.95 { return ("Likely to accept", .success) }
        if ratio >= 0.80 { return ("May counter-offer", .warning) }
        return ("High risk of rejection", .danger)
    }

    private var counterOfferMinimum: Double {
        askingSalary * 0.85
    }

    /// Fix #68: Personality effect descriptions.
    private var personalityEffects: [(effect: String, icon: String)] {
        switch candidate.personality {
        case .teamLeader:        return [("Player morale +5%", "arrow.up"), ("Team chemistry +3%", "person.2")]
        case .loneWolf:          return [("Individual skill dev +8%", "figure.walk"), ("Team chemistry -3%", "person.2.slash")]
        case .feelPlayer:        return [("Adaptability +5%", "arrow.triangle.2.circlepath"), ("Consistency -3%", "waveform.path")]
        case .steadyPerformer:   return [("Consistency +5%", "equal.circle"), ("Development stability +3%", "chart.line.flattrend.xyaxis")]
        case .dramaQueen:        return [("Media handling +8%", "mic.fill"), ("Locker room drama risk +5%", "exclamationmark.bubble")]
        case .quietProfessional: return [("Discipline +5%", "checkmark.shield"), ("Media handling -3%", "mic.slash")]
        case .mentor:            return [("Player development +8%", "graduationcap"), ("Young player growth +5%", "figure.and.child.holdinghands")]
        case .fieryCompetitor:   return [("Motivation +8%", "flame"), ("Discipline risk +3%", "exclamationmark.triangle")]
        case .classClown:        return [("Morale boost +5%", "face.smiling"), ("Discipline -3%", "exclamationmark.triangle")]
        }
    }

    /// Fix #70: Pre-hire chemistry prediction with HC.
    private var chemistryPrediction: (label: String, color: Color, description: String) {
        // BUG FIX: When the user IS the head coach (career.role == .gmAndHeadCoach),
        // no Coach record exists for the HC, so `headCoach` is nil. Evaluate chemistry
        // against the user's coaching style instead of showing "No HC hired".
        if headCoach == nil, userIsHeadCoach, let style = userCoachingStyle {
            // Coaching-style ↔ candidate-personality compatibility heuristic.
            let strongFits: [CoachingStyle: Set<PersonalityArchetype>] = [
                .tactician:      [.quietProfessional, .steadyPerformer],
                .playersCoach:   [.teamLeader, .mentor, .feelPlayer],
                .disciplinarian: [.quietProfessional, .steadyPerformer],
                .innovator:      [.feelPlayer, .mentor],
                .motivator:      [.fieryCompetitor, .teamLeader]
            ]
            let weakFits: [CoachingStyle: Set<PersonalityArchetype>] = [
                .tactician:      [.classClown, .dramaQueen],
                .playersCoach:   [.loneWolf],
                .disciplinarian: [.classClown, .dramaQueen, .loneWolf],
                .innovator:      [.steadyPerformer],
                .motivator:      [.quietProfessional]
            ]
            // `displayName` carries its own article ("The Tactician"), which
            // read as "your The Tactician approach" once it was dropped into
            // the sentence. The bare noun is what belongs after "your".
            let styleNoun = style.displayName.hasPrefix("The ")
                ? String(style.displayName.dropFirst(4))
                : style.displayName
            if strongFits[style]?.contains(candidate.personality) == true {
                return ("Strong", .success,
                        "\(candidate.personality.displayName) fits well with your \(styleNoun) approach.")
            }
            if weakFits[style]?.contains(candidate.personality) == true {
                return ("Weak", .danger,
                        "\(candidate.personality.displayName) may clash with your \(styleNoun) approach.")
            }
            return ("Average", .textSecondary,
                    "Neutral fit with your \(styleNoun) approach.")
        }

        guard let hc = headCoach else {
            return ("Unknown", .textTertiary, "No Head Coach on staff to evaluate chemistry.")
        }

        // Simple personality compatibility matrix
        let compatiblePairs: Set<Set<String>> = [
            ["TeamLeader", "QuietProfessional"],
            ["Mentor", "SteadyPerformer"],
            ["FieryCompetitor", "TeamLeader"],
            ["Mentor", "TeamLeader"],
            ["QuietProfessional", "SteadyPerformer"],
        ]
        let clashingPairs: Set<Set<String>> = [
            ["DramaQueen", "QuietProfessional"],
            ["FieryCompetitor", "DramaQueen"],
            ["LoneWolf", "TeamLeader"],
            ["ClassClown", "FieryCompetitor"],
        ]

        let pair: Set<String> = [candidate.personality.rawValue, hc.personality.rawValue]

        if candidate.personality == hc.personality {
            return ("Neutral", .warning, "Same personality type (\(hc.personality.displayName)) — may overlap rather than complement.")
        }
        if compatiblePairs.contains(pair) {
            return ("Strong", .success, "\(candidate.personality.displayName) and \(hc.personality.displayName) complement each other well.")
        }
        if clashingPairs.contains(pair) {
            return ("Weak", .danger, "\(candidate.personality.displayName) may clash with HC's \(hc.personality.displayName) style.")
        }
        return ("Average", .textSecondary, "No strong synergy or conflict expected with \(hc.personality.displayName) HC.")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        // Fix #67: Candidate ranking badge
                        rankingBadge

                        // Profile header
                        profileHeader

                        if isHired || negotiationResult?.accepted == true {
                            hiredBanner
                        }

                        // Fix #63 + #87: Comparison to current coach
                        if let current = currentCoach {
                            comparisonCard(current: current)
                        } else {
                            noCurrentCoachCard
                        }

                        // Two-column layout for cards
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 12) {
                                // All attributes
                                attributesCard
                                // #22: Role-aware projected contribution. The
                                // only efficiency projection on the profile —
                                // #90's second card stacked another one right
                                // under it off a cruder formula, and the two
                                // printed opposite signs for the same hire.
                                projectedImpactCard
                                // #21: Career history
                                careerHistoryCard
                                // Background story
                                if !candidate.background.isEmpty {
                                    backgroundCard
                                }
                            }
                            .frame(maxWidth: .infinity)
                            VStack(spacing: 12) {
                                // Fix #66: Scheme fit analysis
                                schemeFitCard
                                // Fix #68 + #70: Coaching style & chemistry
                                coachingStyleCard
                                // Negotiation section
                                negotiationCard
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom) { offerActionBar }
            }
            .navigationTitle("Candidate Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Ranking Badge (Fix #67)

    private var rankingBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(Color.accentGold)
            Text("Ranked #\(candidateRank) of \(totalCandidates) candidates")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            // The superlative belongs to #1 only — handing it to three men told a
            // player opening three profiles the same thing three times. Ranks 2-3
            // get the list's own wording instead.
            if candidateRank >= 1 && candidateRank <= 3 {
                Text(candidateRank == 1 ? "Best Available" : "Top 3")
                    .font(.system(size: DSType.Size.micro, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Name + role badge
            HStack(spacing: 10) {
                // A candidate already carries a preview portrait
                // (`CoachingEngine.generateCoachCandidates` → `previewFace`), and
                // `CoachDetailView` shows one for a hired coach — this header was
                // the only coach detail screen still opening on a name alone.
                PersonFaceView(coach: candidate, size: .large, ringColor: .accentGold)

                Text(candidate.role.abbreviation)
                    .font(.system(size: DSType.Size.body, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(candidate.role.badgeColor, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.fullName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    // Age and experience only. The personality used to end this
                    // line too, and the Coaching Style card below prints the
                    // same words as its first row — with the effect lines that
                    // make them mean something. One statement of a man's
                    // temperament per profile, and it is the one that explains
                    // itself.
                    HStack(spacing: 8) {
                        Text("Age \(candidate.age)")
                        Text("\u{00B7}")
                        Text("\(candidate.yearsExperience) yrs experience")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Overall rating + scheme + salary summary.
            //
            // A `ViewThatFits` over a one-line and a two-line arrangement, with
            // every chip in it `fixedSize`. This row carries an OVR box, a
            // ceiling chip, up to two scheme pills, a fit badge and a demand
            // badge that can read "High demand (3 rival teams)" — in a single
            // HStack they compressed each other into ellipses instead of
            // wrapping, so the busiest candidates lost exactly the words that
            // make the badges worth printing. The rule for a row of fixed-size
            // chips (see `DraftTickerPanel.callLine`) is that it must carry a
            // smaller variant.
            ViewThatFits(in: .horizontal) {
                headerSummary(stacked: false)
                headerSummary(stacked: true)
            }
        }
        .padding(16)
        .cardBackground()
    }

    /// One arrangement of the header's rating / chips / salary line.
    /// `stacked` moves the chips onto a second line under the OVR box.
    @ViewBuilder
    private func headerSummary(stacked: Bool) -> some View {
        HStack(alignment: stacked ? .top : .center, spacing: 12) {
            headerOverallBox

            if stacked {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        headerPotentialChip
                        headerSchemeTags
                    }
                    HStack(spacing: 8) {
                        headerFitBadge
                        demandBadge
                    }
                }
            } else {
                headerPotentialChip
                headerSchemeTags
                headerFitBadge
                demandBadge
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Asking Salary")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                Text(salaryFormatted(candidate.salary))
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// #160: Overall badge with context label.
    private var headerOverallBox: some View {
        let ovr = coachOverall(candidate)
        return VStack(spacing: 2) {
            Text("\(ovr)")
                .font(.system(size: DSType.Size.title2, weight: .black).monospacedDigit())
                .foregroundStyle(Color.forRating(ovr))
            Text("OVR")
                .font(.system(size: DSType.Size.caption, weight: .bold))
                .foregroundStyle(Color.textTertiary)
            Text(ovrContextLabel(ovr))
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(Color.forRating(ovr).opacity(0.8))
        }
        // 52 pt clipped the context label to "Above A…" / "Below A…",
        // i.e. every candidate rated 50–79 lost the word that gives the
        // number its meaning.
        .frame(width: 68, height: 58)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))
    }

    /// #89: Coach development potential.
    private var headerPotentialChip: some View {
        VStack(spacing: 2) {
            Text(candidatePotentialLabel)
                .font(.system(size: DSType.Size.caption, weight: .bold))
                .foregroundStyle(candidatePotentialColor)
            Text("Potential")
                .font(.system(size: DSType.Size.micro, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(candidatePotentialColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var headerSchemeTags: some View {
        if let off = candidate.offensiveScheme {
            schemeTag(off.displayName, color: .accentBlue)
                .fixedSize(horizontal: true, vertical: false)
        }
        if let def = candidate.defensiveScheme {
            schemeTag(def.displayName, color: .danger)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// Fix #66: Scheme fit badge in header.
    @ViewBuilder
    private var headerFitBadge: some View {
        if let fit = schemeFitResult {
            HStack(spacing: 4) {
                Circle().fill(fit.color).frame(width: 8, height: 8)
                Text(fit.label)
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(fit.color)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fit.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
        }
    }

    // MARK: - Quick Hire Button (Fix #43 + #65: budget impact)

    private var quickHireButton: some View {
        Button {
            proposedSalary = askingSalary
            proposedYears = 3
            makeOffer()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "handshake.fill")
                    .font(.system(size: DSType.Size.callout, weight: .semibold))
                VStack(spacing: 2) {
                    Text("Offer Contract")
                        .font(.headline.weight(.bold))
                    // Fix #65: Budget impact
                    Text("at \(salaryFormatted(candidate.salary))/yr \u{00B7} Budget after: $\(formatBudget(remainingBudget - candidate.salary))M")
                        .font(.caption2)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(candidate.salary > remainingBudget ? Color.backgroundTertiary : Color.accentGold)
            )
        }
        .disabled(candidate.salary > remainingBudget)
        .buttonStyle(.plain)
    }

    // MARK: - Hired Banner

    private var hiredBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.success)
            Text("Hired!")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.success)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.success.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.success.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Comparison Card (Fix #63 + #87)

    private func comparisonCard(current: Coach) -> some View {
        let curOVR = coachOverall(current)
        let newOVR = coachOverall(candidate)
        let delta = newOVR - curOVR

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("VS CURRENT \(candidate.role.abbreviation)")
                    .font(.system(size: DSType.Size.caption, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.accentGold)
                Spacer()
                // #87: Upgrade summary
                Text("vs \(current.fullName) (\(curOVR) OVR) — \(delta >= 0 ? "+\(delta)" : "\(delta)") \(delta > 0 ? "upgrade" : delta < 0 ? "downgrade" : "even")")
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(delta > 0 ? Color.success : delta < 0 ? Color.dangerText : Color.textTertiary)
            }

            HStack(spacing: 16) {
                // Current
                VStack(spacing: 4) {
                    Text(current.fullName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Text("\(curOVR)")
                        .font(.system(size: DSType.Size.title3, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.forRating(curOVR))
                    Text(salaryFormatted(current.salary))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)

                // Arrow with delta
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: DSType.Size.body, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                    Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                        .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                        .foregroundStyle(delta > 0 ? Color.success : delta < 0 ? Color.dangerText : Color.textTertiary)
                }

                // New candidate
                VStack(spacing: 4) {
                    Text(candidate.fullName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(newOVR)")
                        .font(.system(size: DSType.Size.title3, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.forRating(newOVR))
                    Text(salaryFormatted(candidate.salary))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }

            // #87: Key attribute side-by-side comparison
            let comparisons: [(String, Int, Int)] = [
                ("Play Calling", current.playCalling, candidate.playCalling),
                ("Player Dev", current.playerDevelopment, candidate.playerDevelopment),
                ("Reputation", current.reputation, candidate.reputation),
                ("Game Plan", current.gamePlanning, candidate.gamePlanning),
                ("Motivation", current.motivation, candidate.motivation),
            ]
            HStack(spacing: 6) {
                ForEach(comparisons, id: \.0) { name, curVal, newVal in
                    let d = newVal - curVal
                    VStack(spacing: 2) {
                        Text(name)
                            .font(.system(size: DSType.Size.micro, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Text(d >= 0 ? "+\(d)" : "\(d)")
                            .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
                            .foregroundStyle(d > 0 ? Color.success : d < 0 ? Color.dangerText : Color.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - No Current Coach Card (#87)

    private var noCurrentCoachCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: DSType.Size.callout, weight: .semibold))
                .foregroundStyle(Color.accentBlue)
            VStack(alignment: .leading, spacing: 2) {
                Text("New hire — no current \(candidate.role.abbreviation)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("This is a new addition to the coaching staff.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Attributes Card (Fix #64: color-coded)

    private var attributesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ATTRIBUTES")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            // #158: Full attribute names (no truncation in 2-column layout)
            let attrs: [(String, Int)] = [
                ("Play Calling", candidate.playCalling),
                ("Player Development", candidate.playerDevelopment),
                ("Game Planning", candidate.gamePlanning),
                ("Scouting Ability", candidate.scoutingAbility),
                ("Recruiting", candidate.recruiting),
                ("Motivation", candidate.motivation),
                ("Discipline", candidate.discipline),
                ("Adaptability", candidate.adaptability),
                ("Media Handling", candidate.mediaHandling),
                ("Contract Negotiation", candidate.contractNegotiation),
                ("Morale Influence", candidate.moraleInfluence),
                ("Reputation", candidate.reputation),
            ]

            VStack(spacing: 8) {
                ForEach(0..<(attrs.count / 2), id: \.self) { rowIndex in
                    let left = attrs[rowIndex * 2]
                    let right = attrs[rowIndex * 2 + 1]
                    HStack(spacing: 8) {
                        attributeCell(name: left.0, value: left.1)
                        attributeCell(name: right.0, value: right.1)
                    }
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    /// Fix #64 + #86: Colour-coded attribute cells.
    ///
    /// A bar, not a tier word beside a numeral. The pair said one thing twice
    /// ("Great" and 78 are the same statement on the same ladder) and neither
    /// half showed what twelve attributes in a column are actually read for —
    /// how they stand against each other. The tier word is not lost: it is
    /// spoken, in the cell's accessibility label, where it still adds something.
    private func attributeCell(name: String, value: Int) -> some View {
        let tier = attributeTier(value)
        let color = Color.forRating(value)
        return HStack(spacing: 8) {
            Text(name)
                .font(.system(size: DSType.Size.micro, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.surfaceBorder.opacity(0.35))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 99)) / 99.0)
                }
            }
            .frame(width: 56, height: 6)
            Text("\(value)")
                .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(0.06))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(value), \(tier.label)")
    }

    /// #86: Attribute tier with color coding.
    private func attributeTier(_ value: Int) -> (label: String, color: Color, isElite: Bool) {
        if value >= 85 { return ("Elite", .accentGold, true) }
        if value >= 75 { return ("Great", .success, false) }
        if value >= 65 { return ("Good", .accentBlue, false) }
        if value >= 55 { return ("Avg", .textSecondary, false) }
        return ("Below", .warning, false)
    }

    // MARK: - Background Card

    private var backgroundCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BACKGROUND")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            Text(candidate.background)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Scheme Fit Card (Fix #66)

    /// `Coach.schemeExpertise` is keyed by raw enum value ("ProPassing"); every
    /// other line on this card prints the display name ("Pro Passing").
    private func schemeDisplayName(_ rawValue: String) -> String {
        if let off = OffensiveScheme(rawValue: rawValue) { return off.displayName }
        if let def = DefensiveScheme(rawValue: rawValue) { return def.displayName }
        return rawValue
    }

    /// The schemes this candidate's job actually installs — the only ones worth
    /// grading him on.
    ///
    /// Both seeding paths (`CoachingEngine.initializeSchemeExpertise` and the
    /// byte-identical one in `LeagueGenerator`) write EVERY scheme in the game
    /// onto EVERY coach: the primary at 75–95, its family at 40–65, and all the
    /// rest at `15 + adaptability/99*15 + 0...10`, which can never exceed 40.
    /// So the raw map graded an offensive coordinator on seven defensive
    /// systems and filled his card with a dozen F rows for work nobody will
    /// ever ask him to do. The map itself is deliberately left whole underneath
    /// — scheme fit reads it in full through `Coach.expertise(for:)`, and
    /// trimming it would move simulated outcomes. This is a display filter and
    /// nothing else.
    ///
    /// The side comes from the ROLE, using the same split every other
    /// scheme-fit surface in the app already uses
    /// (`CoachRole.installsOffence` / `.installsDefence`, which
    /// `CoachingEngine`'s own file-private pair mirrors, as do
    /// `SchemeSelectionView.staffCoachFit` and
    /// `CareerDashboardView.calculateCoachFit`), UNION any side on which the
    /// man holds an actual named scheme. That union is load-bearing, not
    /// decoration: `role` is rewritten on promotion and by the AI staff refill
    /// (`CoachCarouselEngine`, `WeekAdvancer`) while `offensiveScheme` /
    /// `defensiveScheme` are never rewritten after construction — so an
    /// ex-head-coach working as a DC really does carry a 75–95 offensive
    /// scheme that his role alone would hide. It is also how a head coach —
    /// whose role sits on neither side, and who is generated with one side or
    /// both — gets exactly the sides he has.
    ///
    /// That cross-side case is why there is no separate "off-side expertise"
    /// line: the genuine article is already in this list at its real number,
    /// and a dedicated line for everyone else could only ever print an F,
    /// because no writer in the codebase ever lifts an off-side value above
    /// the 40 baseline ceiling.
    ///
    /// Roles that install neither side and carry no scheme (special teams,
    /// strength, medical) yield an empty list, and the block hides.
    private var relevantSchemeExpertise: [(key: String, value: Int)] {
        var keys: Set<String> = []
        if candidate.role.installsOffence || candidate.offensiveScheme != nil {
            keys.formUnion(OffensiveScheme.allCases.map(\.rawValue))
        }
        if candidate.role.installsDefence || candidate.defensiveScheme != nil {
            keys.formUnion(DefensiveScheme.allCases.map(\.rawValue))
        }
        // Name breaks value ties: `sorted` is not stable and these rows are
        // `ForEach` identities, so equal expertise used to be free to re-order
        // itself between redraws.
        return candidate.schemeExpertise
            .filter { keys.contains($0.key) }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    }

    private var schemeFitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCHEME FIT")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            if let fit = schemeFitResult, let hc = headCoach {
                HStack(spacing: 10) {
                    Circle()
                        .fill(fit.color)
                        .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scheme Compatibility: \(fit.label)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(fit.color)
                        let hcScheme = hc.offensiveScheme?.displayName ?? hc.defensiveScheme?.displayName ?? "Unknown"
                        let candScheme = candidate.offensiveScheme?.displayName ?? candidate.defensiveScheme?.displayName ?? "Unknown"
                        Text("HC runs \(hcScheme) \u{00B7} Candidate prefers \(candScheme)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else if let fit = schemeFitResult, let installed = installedSchemeName {
                // A GM+HC career has no `.headCoach` row, but the club still runs
                // a scheme — the coordinator in post installed it. Rate against
                // that rather than refusing to answer on the screen whose whole
                // job is picking the next coordinator.
                HStack(spacing: 10) {
                    Circle()
                        .fill(fit.color)
                        .frame(width: 14, height: 14)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scheme Compatibility: \(fit.label)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(fit.color)
                        let candScheme = candidate.offensiveScheme?.displayName ?? candidate.defensiveScheme?.displayName ?? "Unknown"
                        Text("You run \(installed) \u{00B7} Candidate prefers \(candScheme)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else if headCoach == nil {
                // #159: Show candidate's scheme even without HC
                let candScheme = candidate.offensiveScheme?.displayName ?? candidate.defensiveScheme?.displayName ?? nil
                if let scheme = candScheme {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color.textTertiary)
                            .frame(width: 14, height: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Candidate prefers: \(scheme)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            // A GM+HC career has no `.headCoach` Coach row — the
                            // user IS the head coach — so telling him to "hire a
                            // head coach first" was advice he could not take. And
                            // with nothing installed there is genuinely nothing to
                            // rate against (`SchemeSelectionView` stores the scheme
                            // on the coordinator), so say what the hire DOES rather
                            // than ask him to hire the man he is looking at.
                            let installsScheme = candidate.role == .offensiveCoordinator || candidate.role == .defensiveCoordinator
                            Text(userIsHeadCoach
                                 ? (installsScheme
                                    ? "Nothing is installed yet — hiring him puts \(scheme) in, and you can change it later in Schemes."
                                    : "Nothing is installed yet. Whichever coordinator you hire first sets the scheme this man would be rated against.")
                                 : "Hire a Head Coach first for a scheme compatibility rating.")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                } else {
                    Text("No scheme data available for comparison.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            } else {
                Text("No scheme data available for comparison.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            // #88: Scheme expertise levels — narrowed to the schemes this
            // candidate's role installs; see `relevantSchemeExpertise`.
            let schemeRows = relevantSchemeExpertise
            if !schemeRows.isEmpty {
                Divider().overlay(Color.surfaceBorder)

                Text("SCHEME EXPERTISE")
                    .font(.system(size: DSType.Size.caption, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.textTertiary)

                ForEach(schemeRows, id: \.key) { scheme, value in
                    HStack(spacing: 8) {
                        Text(schemeDisplayName(scheme))
                            .font(.system(size: DSType.Size.caption, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .frame(width: 92, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.forRating(value))
                                    .frame(width: geo.size.width * CGFloat(value) / 100.0, height: 6)
                            }
                        }
                        .frame(height: 6)

                        Text(LetterGrade.from(numericValue: value).rawValue)
                            .font(.system(size: DSType.Size.caption, weight: .bold))
                            .foregroundStyle(Color.forRating(value))
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Coaching Style & Chemistry Card (Fix #68 + #70)

    private var coachingStyleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("COACHING STYLE")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            // Personality
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: DSType.Size.body))
                    .foregroundStyle(Color.accentBlue)
                Text(candidate.personality.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }

            // Fix #68 + #161: Style effects — green for positive, red for negative
            ForEach(personalityEffects, id: \.effect) { item in
                let isNegative = item.effect.contains("-") || item.effect.lowercased().contains("risk")
                HStack(spacing: 6) {
                    Image(systemName: item.icon)
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(isNegative ? Color.danger : Color.success)
                        .frame(width: 16)
                    Text(item.effect)
                        .font(.caption)
                        .foregroundStyle(isNegative ? Color.dangerText : Color.success)
                }
            }

            Divider().overlay(Color.surfaceBorder)

            // Fix #70: Chemistry prediction with HC
            let chem = chemistryPrediction
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: DSType.Size.body))
                    .foregroundStyle(chem.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text("HC Chemistry: \(chem.label)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(chem.color)
                    Text(chem.description)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Negotiation Card

    private var negotiationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NEGOTIATE")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            // Proposed salary slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Proposed Salary")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(salaryFormatted(Int(proposedSalary)))
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(isOverBudget ? Color.dangerText : Color.accentGold)
                }

                let minSalary = max(100, Double(candidate.salary) * 0.5)
                let maxSalary = Double(candidate.salary) * 1.3
                Slider(value: $proposedSalary, in: minSalary...maxSalary, step: 50)
                    .tint(Color.accentGold)

                HStack {
                    Text(salaryFormatted(Int(minSalary)))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text("Asking: \(salaryFormatted(candidate.salary))")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text(salaryFormatted(Int(maxSalary)))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }

                if let coinFlip = coinFlipSalary, coinFlip > minSalary {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.left.circle")
                            .font(.system(size: DSType.Size.micro))
                        Text("Under \(salaryFormatted(Int(coinFlip))) he is likelier to walk than sign")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(proposedSalary < coinFlip ? Color.warning : Color.textSecondary)
                }
            }

            // Fix #69: Acceptance likelihood
            HStack(spacing: 8) {
                Image(systemName: "gauge.medium")
                    .foregroundStyle(acceptanceLikelihood.color)
                // The bucketed word alone flattened a live probability into a
                // 20-point band — "High" spans 75-95%. `makeOffer` rolls against
                // exactly this number, so print it.
                Text("Acceptance: \(Int((1.0 - rejectionChance) * 100))% \u{00B7} \(acceptanceLikelihood.label)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(acceptanceLikelihood.color)
                Spacer()
                // Fix #65: Budget after hire
                Text("Budget after: $\(formatBudget(budgetAfterHire))M")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(budgetAfterHire >= 0 ? Color.textSecondary : Color.dangerText)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.backgroundTertiary.opacity(0.5))
            )

            // #92: Detailed offer assessment
            if proposedSalary < askingSalary {
                let assessment = offerAssessment
                HStack(spacing: 6) {
                    Image(systemName: assessment.color == .danger ? "xmark.circle.fill" :
                            assessment.color == .warning ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(assessment.color)
                    Text(assessment.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(assessment.color)
                    Text("— Below asking, may reject or counter-offer")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Contract years + #162: Show contract length effect
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Contract Length")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(proposedYears) year\(proposedYears == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                }
                Stepper("Years", value: $proposedYears, in: 1...5)
                    .labelsHidden()

                // #162: Contract length effect on salary/acceptance
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                    Text(contractLengthEffect)
                        .font(.system(size: DSType.Size.micro, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }
            }

            // R30 Market 2.0: rival-competition note — overbidding locks rivals out.
            if marketRivals > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(competitionRisk > 0 ? Color.danger : Color.success)
                    Text(competitionRisk > 0
                         ? "\(marketRivals) rival team\(marketRivals == 1 ? "" : "s") pursuing — you could lose this candidate. Overbid (+10%) to lock rivals out."
                         : "\(marketRivals) rival team\(marketRivals == 1 ? "" : "s") pursuing — your overbid locks them out.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((competitionRisk > 0 ? Color.danger : Color.success).opacity(0.08))
                )
            }

            // Rejection warning
            if rejectionChance > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(rejectionChance > 0.5 ? Color.danger : Color.warning)
                    Text("Rejection risk: \(Int(rejectionChance * 100))%")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(rejectionChance > 0.5 ? Color.dangerText : Color.warning)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((rejectionChance > 0.5 ? Color.danger : Color.warning).opacity(0.1))
                )
            }

            // What a rejection actually costs, in the one place the risk is
            // being taken. A refusal is permanent — `onRejected` greys the man
            // out and takes him off the shortlist — so the screen was asking
            // for a lowball with no picture of the downside at all.
            if rejectionChance > 0, let fallback = fallbackCandidate {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.uturn.forward.circle")
                        .foregroundStyle(Color.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("If he walks: \(fallback.name) is next on the board")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text("OVR \(fallback.ovr) \u{00B7} asking \(salaryFormatted(fallback.salary))"
                             + (fallback.isAffordable ? "" : " \u{00B7} over budget"))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(fallback.isAffordable ? Color.textTertiary : Color.dangerText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundTertiary.opacity(0.5))
                )
            }

            if isOverBudget {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(Color.danger)
                    Text("Over budget")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.dangerText)
                }
            }

            // Negotiation result
            if let result = negotiationResult {
                let resultColor: Color = result.accepted ? .success : (result.counterOffer != nil ? .warning : .danger)
                let resultIcon = result.accepted ? "checkmark.circle.fill" : (result.counterOffer != nil ? "arrow.triangle.2.circlepath.circle.fill" : "xmark.circle.fill")
                let resultTitle = result.accepted ? "Offer Accepted!" : (result.counterOffer != nil ? "Counter-Offer" : "Offer Rejected")

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: resultIcon)
                            .font(.title2)
                            .foregroundStyle(resultColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(resultTitle)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(resultColor)
                            Text(result.message)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // #92's accept-counter button moved to `offerActionBar`:
                    // this card is the last one in the right column, so every
                    // commit it carried opened below the fold.
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(resultColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(resultColor.opacity(0.3), lineWidth: 1)
                        )
                )
            }

            if isHired || negotiationResult?.accepted == true {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.success)
                    Text("Hired!")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.success)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - The Commit (P5)

    /// The profile's one commit, pinned.
    ///
    /// The negotiation card is the last card in the right column, so on a
    /// portrait iPad the gold "Offer Contract" button opened below the fold:
    /// the screen asked for a decision and showed no way to make one. The bar
    /// carries the negotiation's ANSWER as well as the terms, because the card
    /// that prints the result is the same one that was off-screen — without it,
    /// pressing the pinned button would change nothing the user can see.
    private var offerActionBar: some View {
        let signed = isHired || negotiationResult?.accepted == true
        var secondary: DSActionBar.Action?
        var primary: DSActionBar.Action?
        if !signed {
            if let counter = negotiationResult?.counterOffer {
                // Kept alongside the primary rather than replacing it: the user
                // may still want to re-offer his own number after a counter.
                secondary = DSActionBar.Action(
                    title: "Accept Counter",
                    caption: "\(salaryFormatted(counter))/yr",
                    isEnabled: counter <= remainingBudget,
                    handler: { acceptCounterOffer(amount: counter) }
                )
            }
            primary = DSActionBar.Action(
                title: "Offer Contract",
                caption: "budget after: $\(formatBudget(budgetAfterHire))M",
                isEnabled: !isOverBudget,
                handler: { makeOffer() }
            )
        }
        return DSActionBar(
            explainer: .init(
                title: offerBarTitle,
                message: offerBarMessage,
                isWarning: !signed && (isOverBudget || negotiationResult != nil)
            ),
            secondary: secondary,
            primary: primary
        )
    }

    private var offerBarTitle: String {
        if isHired || negotiationResult?.accepted == true { return "Signed" }
        guard let result = negotiationResult else { return "Your offer" }
        return result.counterOffer != nil ? "Countered" : "Turned down"
    }

    /// Quotes the same salary and the same budget-after the negotiation card
    /// prints, so the pinned bar and the card cannot disagree.
    private var offerBarMessage: String {
        if isHired || negotiationResult?.accepted == true {
            return "**\(candidate.fullName)** signed at **\(salaryFormatted(candidate.salary))/yr** \u{00B7} **$\(formatBudget(remainingBudget - candidate.salary))M** left."
        }
        if let counter = negotiationResult?.counterOffer {
            return "\(candidate.firstName) wants **\(salaryFormatted(counter))/yr** \u{00B7} **$\(formatBudget(remainingBudget - counter))M** left after."
        }
        if negotiationResult != nil {
            return "\(candidate.firstName) rejected the offer \u{2014} see the negotiation card for what he said."
        }
        if isOverBudget {
            return "**\(salaryFormatted(Int(proposedSalary)))/yr** for **\(proposedYears) years** \u{2014} over the **$\(formatBudget(remainingBudget))M** you have left."
        }
        return "**\(salaryFormatted(Int(proposedSalary)))/yr** for **\(proposedYears) years** \u{00B7} budget after: **$\(formatBudget(budgetAfterHire))M**."
    }

    // MARK: - Offer Logic

    private func makeOffer() {
        let roll = Double.random(in: 0...1)
        let accepted = roll >= rejectionChance

        if accepted {
            negotiationResult = NegotiationResult(
                accepted: true,
                counterOffer: nil,
                message: proposedSalary < askingSalary
                    ? "\(candidate.firstName) accepted your below-market offer of \(salaryFormatted(Int(proposedSalary)))/yr for \(proposedYears) years."
                    : "\(candidate.firstName) is pleased with the offer of \(salaryFormatted(Int(proposedSalary)))/yr for \(proposedYears) years."
            )
            candidate.salary = Int(proposedSalary)
            onHire()
        } else {
            // #92: Counter-offer instead of instant rejection
            let minAcceptable = Int(counterOfferMinimum)
            let ratio = proposedSalary / askingSalary
            // R30 Market 2.0: with multiple rivals in pursuit, a rejection
            // often means the candidate takes a competing offer instead of
            // giving you a second chance.
            let lostToRival = marketRivals >= 2
                && competitionRisk > 0
                && Double.random(in: 0...1) < 0.5
            if ratio >= 0.65 && !lostToRival {
                // Coach counters instead of walking away
                negotiationResult = NegotiationResult(
                    accepted: false,
                    counterOffer: minAcceptable,
                    message: "\(candidate.firstName) rejected your offer but is willing to negotiate. Coach wants at least \(salaryFormatted(minAcceptable))."
                )
            } else {
                // Offer too low or a rival club swooped in — walks away
                negotiationResult = NegotiationResult(
                    accepted: false,
                    counterOffer: nil,
                    message: lostToRival
                        ? "\(candidate.firstName) has accepted an offer from a rival organization. They are no longer available."
                        : "\(candidate.firstName) has signed elsewhere. They are no longer available."
                )
                // #271: Notify parent to gray out this candidate
                onRejected?()
            }
        }
    }

    // MARK: - #92: Accept Counter-Offer

    private func acceptCounterOffer(amount: Int) {
        negotiationResult = NegotiationResult(
            accepted: true,
            counterOffer: nil,
            message: "\(candidate.firstName) accepted the counter-offer of \(salaryFormatted(amount))/yr for \(proposedYears) years."
        )
        candidate.salary = amount
        onHire()
    }

    // MARK: - Helpers

    private func salaryFormatted(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "$%.1fM", millions)
    }

    private func formatBudget(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "%.1f", millions)
    }

    private func schemeTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: DSType.Size.caption, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Negotiation Result

private struct NegotiationResult {
    let accepted: Bool
    /// #92: Counter-offer amount (in thousands) if the coach didn't walk away.
    let counterOffer: Int?
    let message: String
}

// MARK: - Candidate Compare Table

/// One pinned candidate, frozen at the moment the table opened.
///
/// A snapshot rather than a live read of the `Coach`: the ceiling label rolls
/// fresh noise on every call and the rival count runs a hash per lookup, and a
/// comparison whose numbers move while you read it is worse than none.
private struct CoachCompareEntry: Identifiable {
    let id: UUID
    let coach: Coach
    let ovr: Int
    /// Against the incumbent in this role; nil when the seat is empty.
    let ovrDelta: Int?
    let valueLabel: String
    let valueColor: Color
    /// The raw OVR-per-million behind `valueLabel` — the label buckets four
    /// ways, so two men can both read "Good" and still not be equal.
    let valueRatio: Double
    let schemeName: String
    let fitLabel: String?
    let fitColor: Color?
    let potentialLabel: String
    let potentialColor: Color
    let rivalTeams: Int
    let isMarketCandidate: Bool
    let isAffordable: Bool
}

/// Two or three candidates held side by side: one measure per row, the leader
/// on each row marked in gold.
///
/// The board can rank by any single column, which is precisely what it cannot
/// answer — the man with the best OVR is rarely the man with the best value,
/// the better scheme fit and the shorter queue of rival clubs, and the profile
/// is a full-screen cover, so weighing two of them meant closing one and
/// remembering twelve attributes.
private struct CandidateCompareSheet: View {
    let entries: [CoachCompareEntry]
    let role: CoachRole
    /// The incumbent's name, so the overall row can say what the delta is
    /// measured against instead of printing a bare signed number.
    let currentCoachName: String?
    let onOpenProfile: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Three is the cap. A fourth column does not fit a 1032 pt portrait iPad
    /// once the faces and the "Open profile" buttons are in, and a four-way
    /// coaching decision is not one anybody makes. (`BigBoardView` caps its
    /// prospect tray the same way, at four narrower columns.)
    static let maxCandidates = 3

    /// The measure column. Sized for "Contract Negotiation" at the caption step.
    private let labelWidth: CGFloat = 150

    // MARK: Attribute rows

    private struct AttributeRow: Identifiable {
        /// The `Coach` property name — the same key `CoachRole.focusAttributes`
        /// is written in, which is what makes the gold focus dot free.
        let id: String
        let label: String
        let path: KeyPath<Coach, Int>
    }

    private var attributeRows: [AttributeRow] {
        let all: [AttributeRow] = [
            .init(id: "playCalling",        label: "Play Calling",        path: \.playCalling),
            .init(id: "playerDevelopment",  label: "Player Development",  path: \.playerDevelopment),
            .init(id: "gamePlanning",       label: "Game Planning",       path: \.gamePlanning),
            .init(id: "scoutingAbility",    label: "Scouting Ability",    path: \.scoutingAbility),
            .init(id: "recruiting",         label: "Recruiting",          path: \.recruiting),
            .init(id: "motivation",         label: "Motivation",          path: \.motivation),
            .init(id: "discipline",         label: "Discipline",          path: \.discipline),
            .init(id: "adaptability",       label: "Adaptability",        path: \.adaptability),
            .init(id: "mediaHandling",      label: "Media Handling",      path: \.mediaHandling),
            .init(id: "contractNegotiation", label: "Contract Negotiation", path: \.contractNegotiation),
            .init(id: "moraleInfluence",    label: "Morale Influence",    path: \.moraleInfluence),
            .init(id: "reputation",         label: "Reputation",          path: \.reputation)
        ]
        // The attributes this job leans on come first — the same set the board's
        // header marks with a gold dot. A stable partition, so the rest keep the
        // order the profile lists them in.
        let focus = role.focusAttributes
        return all.filter { focus.contains($0.id) } + all.filter { !focus.contains($0.id) }
    }

    // MARK: Leaders

    /// The single leader on a measure, or nil when two men tie on it.
    ///
    /// A tie is left unmarked rather than broken by array order: the whole point
    /// of the table is that it does not invent a winner the numbers do not name.
    private func leaderID(by score: (CoachCompareEntry) -> Double) -> UUID? {
        guard let best = entries.map(score).max() else { return nil }
        let winners = entries.filter { score($0) == best }
        return winners.count == 1 ? winners.first?.id : nil
    }

    private func fitRank(_ entry: CoachCompareEntry) -> Double {
        switch entry.fitLabel {
        case "Great": return 3
        case "OK":    return 2
        case "Poor":  return 1
        default:      return 0
        }
    }

    private var anyFitRated: Bool { entries.contains { $0.fitLabel != nil } }

    /// The leader's surname for the summary band, or "Level" for a tie.
    private func leaderName(by score: (CoachCompareEntry) -> Double) -> String {
        guard let id = leaderID(by: score),
              let entry = entries.first(where: { $0.id == id }) else { return "Level" }
        return entry.coach.lastName
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Identity is pinned above the scroll: the one thing a
                    // comparison table can never afford is a column of numbers
                    // whose owner has scrolled off the top.
                    columnHeader

                    Divider().overlay(Color.surfaceBorder)

                    ScrollView {
                        VStack(spacing: 0) {
                            leaderBand
                            measureSection
                            attributeSection
                            footnote
                        }
                        .frame(maxWidth: DSLayout.wideMeasure)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, DSSpacing.lg)
                    }
                }
            }
            .navigationTitle("Compare Candidates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
        }
    }

    // MARK: Column header

    private var columnHeader: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("HEAD TO HEAD")
                    .font(.system(size: DSType.Size.caption, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.accentGold)
                Text("for the \(role.displayName) job")
                    .font(.system(size: DSType.Size.micro, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: labelWidth, alignment: .leading)
            .padding(.top, 8)

            ForEach(entries) { entry in
                VStack(spacing: 6) {
                    PersonFaceView(coach: entry.coach, size: .medium, ringColor: .accentGold)

                    Text(entry.coach.fullName)
                        .font(.system(size: DSType.Size.body, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 4) {
                        Text(entry.coach.personality.shortLabel)
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(Color.accentBlue)
                        if entry.isMarketCandidate {
                            Text("FREE AGENT")
                                .font(.system(size: DSType.Size.micro, weight: .black))
                                .foregroundStyle(Color.accentBlue)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentBlue.opacity(0.15), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                        }
                    }
                    .lineLimit(1)

                    // The way out of the table and into the negotiation. It sits
                    // in the header, not at the foot of the columns, because the
                    // twelve attribute rows below it would put a footer button
                    // under a scroll on a portrait iPad.
                    Button("Open profile") { onOpenProfile(entry.id) }
                        .buttonStyle(.dsSecondary)
                        .accessibilityLabel("Open \(entry.coach.fullName)'s profile")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: DSLayout.wideMeasure)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary)
    }

    // MARK: Who wins what

    /// The verdict, before the detail. Four chips is the whole trade-off: the
    /// best coach, the best price, the best return on the money, and the best
    /// fit — and it is the rare candidate who takes all four.
    private var leaderBand: some View {
        var chips: [(label: String, winner: String)] = [
            ("Best overall", leaderName { Double($0.ovr) }),
            ("Best value", leaderName { $0.valueRatio }),
            ("Cheapest", leaderName { -Double($0.coach.salary) })
        ]
        if anyFitRated {
            chips.append(("Best scheme fit", leaderName(by: fitRank)))
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text("WHO WINS WHAT")
                .font(.system(size: DSType.Size.caption, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            HStack(spacing: 8) {
                ForEach(chips, id: \.label) { chip in
                    VStack(spacing: 2) {
                        Text(chip.label.uppercased())
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                        Text(chip.winner)
                            .font(.system(size: DSType.Size.callout, weight: .black))
                            .foregroundStyle(chip.winner == "Level" ? Color.textSecondary : Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(chip.label): \(chip.winner)")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Measures

    private var measureSection: some View {
        VStack(spacing: 0) {
            compareRow(
                "Overall",
                leaderID: leaderID { Double($0.ovr) },
                spoken: { entry in
                    guard let delta = entry.ovrDelta else { return "\(entry.ovr)" }
                    return "\(entry.ovr), \(delta >= 0 ? "plus" : "minus") \(abs(delta)) on the incumbent"
                }
            ) { entry in
                VStack(spacing: 2) {
                    Text("\(entry.ovr)")
                        .font(.system(size: DSType.Size.title3, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.forRating(entry.ovr))
                    if let delta = entry.ovrDelta, let incumbent = currentCoachName {
                        Text("\(delta >= 0 ? "+" : "")\(delta) vs \(incumbent)")
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(delta > 0 ? Color.success : delta < 0 ? Color.dangerText : Color.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }

            compareRow(
                "Asking salary",
                leaderID: leaderID { -Double($0.coach.salary) },
                spoken: { entry in salaryFormatted(entry.coach.salary) + (entry.isAffordable ? "" : ", over budget") }
            ) { entry in
                VStack(spacing: 2) {
                    Text(salaryFormatted(entry.coach.salary))
                        .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                        .foregroundStyle(entry.isAffordable ? Color.textPrimary : Color.dangerText)
                    if !entry.isAffordable {
                        Text("over budget")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(Color.dangerText)
                    }
                }
            }

            compareRow(
                "Value",
                leaderID: leaderID { $0.valueRatio },
                spoken: { $0.valueLabel }
            ) { entry in
                Text(entry.valueLabel)
                    .font(.system(size: DSType.Size.callout, weight: .bold))
                    .foregroundStyle(entry.valueColor)
            }

            compareRow(
                "Scheme",
                leaderID: anyFitRated ? leaderID(by: fitRank) : nil,
                spoken: { entry in "\(entry.schemeName), fit \(entry.fitLabel ?? "not rated")" }
            ) { entry in
                VStack(spacing: 2) {
                    Text(entry.schemeName)
                        .font(.system(size: DSType.Size.footnote, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let fitLabel = entry.fitLabel, let fitColor = entry.fitColor {
                        HStack(spacing: 4) {
                            Circle().fill(fitColor).frame(width: 6, height: 6)
                            Text(fitLabel)
                                .font(.system(size: DSType.Size.micro, weight: .bold))
                                .foregroundStyle(fitColor)
                        }
                    }
                }
            }

            // No leader on the ceiling: `potentialLabel` is a scouting estimate
            // carrying deliberate noise, so a gold cell here would be marking a
            // dice roll as a fact.
            compareRow("Ceiling", spoken: { $0.potentialLabel }) { entry in
                Text(entry.potentialLabel)
                    .font(.system(size: DSType.Size.footnote, weight: .bold))
                    .foregroundStyle(entry.potentialColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // Nor on age: young is upside on a coach and old is a proven record,
            // and the sim does not rate one above the other.
            compareRow(
                "Age \u{00B7} experience",
                spoken: { entry in "age \(entry.coach.age), \(entry.coach.yearsExperience) years" }
            ) { entry in
                Text("\(entry.coach.age) \u{00B7} \(entry.coach.yearsExperience) yrs")
                    .font(.system(size: DSType.Size.footnote, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }

            // Fewer rivals is easier to sign, not a better coach — coloured for
            // risk, deliberately not crowned.
            compareRow(
                "Rival interest",
                spoken: { entry in entry.rivalTeams == 0 ? "no rivals" : "\(entry.rivalTeams) rival teams" }
            ) { entry in
                HStack(spacing: 4) {
                    if entry.rivalTeams > 0 {
                        Image(systemName: "flame.fill")
                            .font(.system(size: DSType.Size.micro))
                    }
                    Text(entry.rivalTeams == 0 ? "Clear run" : "\(entry.rivalTeams) team\(entry.rivalTeams == 1 ? "" : "s")")
                        .font(.system(size: DSType.Size.footnote, weight: .semibold))
                }
                .foregroundStyle(entry.rivalTeams >= 2 ? Color.dangerText : entry.rivalTeams == 1 ? Color.warning : Color.success)
            }

            compareRow("Personality", spoken: { $0.coach.personality.displayName }) { entry in
                Text(entry.coach.personality.displayName)
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                    .foregroundStyle(Color.accentBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: Attributes

    private var attributeSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("ATTRIBUTES")
                    .font(.system(size: DSType.Size.caption, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.accentGold)
                Spacer()
                Circle()
                    .fill(Color.accentGold)
                    .frame(width: 4, height: 4)
                Text("what this job leans on")
                    .font(.system(size: DSType.Size.micro, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)

            ForEach(attributeRows) { row in
                compareRow(
                    row.label,
                    focus: role.focusAttributes.contains(row.id),
                    leaderID: leaderID { Double($0.coach[keyPath: row.path]) },
                    spoken: { entry in "\(entry.coach[keyPath: row.path])" }
                ) { entry in
                    Text("\(entry.coach[keyPath: row.path])")
                        .font(.system(size: DSType.Size.callout, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.forRating(entry.coach[keyPath: row.path]))
                }
            }
        }
    }

    private var footnote: some View {
        Text("A gold cell leads that line. Ceiling, age and rival interest are not crowned \u{2014} the first is an estimate and the other two are trade-offs, not scores.")
            .font(.system(size: DSType.Size.micro, weight: .medium))
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Row builder

    private func compareRow<Cell: View>(
        _ label: String,
        focus: Bool = false,
        leaderID: UUID? = nil,
        spoken: @escaping (CoachCompareEntry) -> String,
        @ViewBuilder cell: @escaping (CoachCompareEntry) -> Cell
    ) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                HStack(spacing: 4) {
                    // #18's gold dot, reused: the same mark means the same thing
                    // on the board's header and in this table.
                    if focus {
                        Circle()
                            .fill(Color.accentGold)
                            .frame(width: 4, height: 4)
                    }
                    Text(label)
                        .font(.system(size: DSType.Size.caption, weight: focus ? .black : .semibold))
                        .foregroundStyle(focus ? Color.accentGold : Color.textTertiary)
                    Spacer(minLength: 0)
                }
                .frame(width: labelWidth, alignment: .leading)

                ForEach(entries) { entry in
                    cell(entry)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                .fill(entry.id == leaderID ? Color.accentGold.opacity(0.12) : Color.clear)
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(entry.coach.lastName), \(label): \(spoken(entry))\(entry.id == leaderID ? ", leads this line" : "")")
                }
            }
            .padding(.horizontal, 16)

            Divider().overlay(Color.surfaceBorder.opacity(0.4))
        }
    }

    private func salaryFormatted(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "$%.1fM", millions)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HireCoachView(
            role: .offensiveCoordinator,
            teamID: UUID(),
            career: Career(playerName: "Preview", role: .gm, capMode: .simple),
            remainingBudget: 15_000
        )
    }
    .modelContainer(for: Coach.self, inMemory: true)
}
