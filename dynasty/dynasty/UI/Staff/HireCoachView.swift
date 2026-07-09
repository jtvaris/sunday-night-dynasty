import SwiftUI
import SwiftData

struct HireCoachView: View {

    let role: CoachRole
    let teamID: UUID
    let remainingBudget: Int
    /// #267: Team data for candidate quality scaling
    var teamBudget: Int = 25_000
    var teamWins: Int = 8
    var teamReputation: Int = 50
    var onHired: ((String, String) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allCoaches: [Coach]
    @Query private var allCareers: [Career]

    @State private var candidates: [Coach] = []
    @State private var hiredCoachID: UUID?
    @State private var sortColumn: SortColumn = .ovr
    @State private var sortAscending: Bool = false
    @State private var selectedCandidate: Coach?
    @State private var showAffordableOnly: Bool = false
    @State private var schemeFilter: String = "All"
    @State private var showValueLegend: Bool = false
    @State private var showSchemeTip: Bool = false
    /// #17: Toggle for OVR/skill color legend panel.
    @State private var showRatingLegend: Bool = false
    /// #20: Personality archetype filter ("All" or PersonalityArchetype.rawValue).
    @State private var personalityFilter: String = "All"
    /// #271: Track candidates who rejected offers — shown grayed out with "Signed elsewhere"
    @State private var rejectedCandidates: Set<UUID> = []

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

    // MARK: - Sort Column

    enum SortColumn: String, CaseIterable {
        case name    = "Name"
        case age     = "Age"
        case scheme  = "Scheme"
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

    /// Fix #56: Top-3 candidate indices in the current sorted list.
    private var top3IDs: Set<UUID> { cachedTop3IDs }

    /// Available scheme names for the filter dropdown (Fix #58).
    private var availableSchemes: [String] { cachedAvailableSchemes }

    // MARK: - Filtered & Sorted Candidates

    private var filteredCandidates: [Coach] {
        var list = candidates
        if showAffordableOnly {
            list = list.filter { $0.salary <= remainingBudget }
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

    /// Recomputes all derived caches. Called when dependencies change.
    private func refreshCaches() {
        let filtered = filteredCandidates

        let sorted: [Coach]
        switch sortColumn {
        case .name:    sorted = filtered.sorted { $0.lastName < $1.lastName }
        case .age:     sorted = filtered.sorted { $0.age < $1.age }
        case .scheme:  sorted = filtered.sorted { schemeLabel($0) < schemeLabel($1) }
        case .ovr:     sorted = filtered.sorted { coachOverall($0) > coachOverall($1) }
        case .play:    sorted = filtered.sorted { $0.playCalling > $1.playCalling }
        case .dev:     sorted = filtered.sorted { $0.playerDevelopment > $1.playerDevelopment }
        case .game:    sorted = filtered.sorted { $0.gamePlanning > $1.gamePlanning }
        case .salary:  sorted = filtered.sorted { $0.salary < $1.salary }
        case .value:   sorted = filtered.sorted { valueRatio($0) > valueRatio($1) }
        }
        cachedSortedCandidates = sortAscending ? sorted.reversed() : sorted

        // Top-3 by OVR among filtered candidates (regardless of sort column)
        let byOVR = filtered.sorted { coachOverall($0) > coachOverall($1) }
        cachedTop3IDs = Set(byOVR.prefix(3).map { $0.id })

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

                // #149: Horizontally scrollable table for cramped columns
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Sticky column headers
                        tableHeaderRow
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.backgroundTertiary.opacity(0.6))

                        Divider().overlay(Color.surfaceBorder)

                        // Candidate rows
                        ScrollView(.vertical) {
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
                    .frame(minWidth: 780, maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Hire \(role.displayName)")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            if candidates.isEmpty {
                // Yield first so the navigation transition completes before we block on generation.
                // CoachingEngine.generateCoachCandidates is @MainActor (touches SwiftData PersistentModels)
                // so we can't detach — but yielding lets the spinner / nav animation render first.
                await Task.yield()
                let count = Int.random(in: 20...30)
                // #267: Pass team data so candidate quality scales with budget/prestige
                candidates = CoachingEngine.generateCoachCandidates(
                    role: role,
                    count: count,
                    teamBudget: teamBudget,
                    teamWins: teamWins,
                    teamReputation: teamReputation
                )
            }
            refreshCaches()
        }
        .onChange(of: candidates.count) { _, _ in refreshCaches() }
        .onChange(of: sortColumn) { _, _ in refreshCaches() }
        .onChange(of: sortAscending) { _, _ in refreshCaches() }
        .onChange(of: showAffordableOnly) { _, _ in refreshCaches() }
        .onChange(of: schemeFilter) { _, _ in refreshCaches() }
        .onChange(of: personalityFilter) { _, _ in refreshCaches() }
        .onChange(of: allCoaches.count) { _, _ in refreshCaches() }
        // #157: Full screen cover on iPad for max space
        .fullScreenCover(item: $selectedCandidate) { candidate in
            CandidateDetailSheet(
                candidate: candidate,
                remainingBudget: remainingBudget,
                isHired: hiredCoachID == candidate.id,
                headCoach: teamHeadCoach,
                currentCoach: currentCoach,
                candidateRank: candidateRank(for: candidate),
                totalCandidates: filteredCandidates.count,
                schemeFitResult: schemeFit(for: candidate),
                // BUG FIX: When user is GM+HC, no .headCoach Coach record exists.
                // Pass user's coaching style so chemistry can be evaluated against the user.
                userIsHeadCoach: allCareers.first?.role == .gmAndHeadCoach,
                userCoachingStyle: allCareers.first?.coachingStyle,
                marketRivals: CoachCarouselEngine.demand(for: candidate).rivalTeams,
                onHire: { hire(candidate) },
                onRejected: { rejectedCandidates.insert(candidate.id) }
            )
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
                        .foregroundStyle(remainingBudget > 0 ? Color.success : Color.danger)
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
                            .font(.system(size: 12))
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
                            .font(.system(size: 12))
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
                            .font(.system(size: 11))
                        Text("Colors")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(showRatingLegend ? Color.accentGold : Color.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
                }

                Spacer().frame(width: 8)

                // Fix #39: Affordable-only toggle
                Toggle(isOn: $showAffordableOnly) {
                    Text("Affordable")
                        .font(.caption2)
                        .foregroundStyle(Color.textSecondary)
                }
                .toggleStyle(.switch)
                .tint(Color.accentGold)
                .fixedSize()

                Spacer().frame(width: 16)

                Text("\(filteredCandidates.count) candidates")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            // #153: Value column legend
            if showValueLegend {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentGold)
                    Text("Val = skill-to-salary ratio: Great = high skill/low salary, Poor = low skill/high salary")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Button { showValueLegend = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
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
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentBlue)
                        Text("\(label): \(desc)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Button { showSchemeTip = false } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
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
                HStack(spacing: 10) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentGold)
                    legendSwatch(color: .success, label: "≥80 Elite")
                    legendSwatch(color: .accentGold, label: "60–79 Solid")
                    legendSwatch(color: .warning, label: "40–59 OK")
                    legendSwatch(color: .danger, label: "<40 Poor")
                    Spacer()
                    Button { showRatingLegend = false } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .accessibilityLabel("Dismiss color legend")
                }
                .padding(8)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
            }

            // Fix #63: Current coach comparison bar
            if let current = currentCoach {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10))
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
                        .font(.system(size: 7))
                        .foregroundStyle(Color.accentBlue.opacity(0.6))
                }
                .frame(width: 62)
            }
            .foregroundStyle(sortColumn == .scheme ? Color.accentGold : Color.textTertiary)
            .accessibilityLabel("Scheme column")
            .accessibilityHint("Toggle scheme info")
            // Fix #38: Scheme fit column header — only when team has a comparable scheme.
            if hasInferableTeamScheme {
                Text("Fit")
                    .frame(width: 32)
            }
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
                        .font(.system(size: 7))
                        .foregroundStyle(Color.accentGold.opacity(0.6))
                }
                .frame(width: 40)
            }
            .foregroundStyle(sortColumn == .value ? Color.accentGold : Color.textTertiary)
            .accessibilityLabel("Value column")
            .accessibilityHint("Toggle value legend")
            // Status column
            Text("")
                .frame(width: 64)
        }
        .font(.system(size: 10, weight: .semibold))
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
                        .font(.system(size: 7))
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
                .font(.system(size: 10, weight: .medium))
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
        // Fix #63: OVR delta vs current coach (cached current OVR — avoids per-row recompute)
        let ovrDelta: Int? = cachedCurrentCoachOVR.map { ovr - $0 }

        return Button {
            if !isRejected { selectedCandidate = candidate }
        } label: {
            HStack(spacing: 0) {
                // Fix #55: Larger name area with personality + top-3 badge
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(candidate.fullName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isOverBudget ? Color.textTertiary : Color.textPrimary)
                            .lineLimit(1)
                        // Potential label badge
                        let potLabel = candidate.potentialLabel(seasonsOnTeam: 0)
                        Text(potLabel)
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(potentialBadgeColor(potLabel))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(potentialBadgeColor(potLabel).opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                        // Fix #56 + #16: Self-explanatory "TOP 3" badge for top-3 candidates.
                        if isTop3 {
                            Text("TOP 3")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(Color.backgroundPrimary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 3))
                        }
                        // R30 Market 2.0: rival-demand badge — flame + how many
                        // other teams are pursuing this candidate.
                        let demand = CoachCarouselEngine.demand(for: candidate)
                        if demand.rivalTeams > 0 {
                            let demandColor: Color = demand.level == .high ? .danger : .warning
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 7))
                                Text("\(demand.rivalTeams)")
                                    .font(.system(size: 7, weight: .black).monospacedDigit())
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
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.accentBlue)
                                    .lineLimit(1)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 7))
                                    .foregroundStyle(Color.accentBlue.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                        // Fix #63: OVR delta vs current
                        if let delta = ovrDelta {
                            Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundStyle(delta > 0 ? Color.success : delta < 0 ? Color.danger : Color.textTertiary)
                        }
                    }
                }
                .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)

                // Age
                Text("\(candidate.age)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 34)

                // Scheme
                Text(schemeLabel(candidate))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.accentBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 62)

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
                                .font(.system(size: 8))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .frame(width: 32)
                }

                // OVR numeric
                Text("\(ovr)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.forRating(ovr))
                    .frame(width: 36)

                // Key skill numerics
                Text("\(candidate.playCalling)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.forRating(candidate.playCalling))
                    .frame(width: 36)

                Text("\(candidate.playerDevelopment)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.forRating(candidate.playerDevelopment))
                    .frame(width: 36)

                Text("\(candidate.gamePlanning)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.forRating(candidate.gamePlanning))
                    .frame(width: 36)

                // Salary
                Text(salaryFormatted(candidate.salary))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isOverBudget ? Color.danger : Color.textSecondary)
                    .frame(width: 56)

                // Fix #60: Value badge
                Text(val.label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(val.color)
                    .frame(width: 40)

                // Status indicator
                Group {
                    if isHired {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.success)
                    } else if isRejected {
                        // #271: Rejected candidate badge
                        Text("Signed elsewhere")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    } else if isOverBudget {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.danger.opacity(0.5))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .frame(width: 64)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isRejected)
        .opacity(isRejected ? 0.45 : isOverBudget ? 0.6 : 1.0)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.fullName), \(candidate.personality.displayName), age \(candidate.age), overall \(ovr), salary \(candidate.salary) thousand, value \(val.label)")
        .accessibilityHint(isRejected ? "Already rejected" : "Tap to view candidate details")
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
    private func candidateRank(for candidate: Coach) -> Int {
        let byOVR = filteredCandidates.sorted { coachOverall($0) > coachOverall($1) }
        if let idx = byOVR.firstIndex(where: { $0.id == candidate.id }) {
            return idx + 1
        }
        return 0
    }

    // MARK: - Hire Action

    private func hire(_ candidate: Coach) {
        guard candidate.salary <= remainingBudget else { return }

        let descriptor = FetchDescriptor<Coach>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        if let existing = try? modelContext.fetch(descriptor) {
            existing.filter { $0.role == role }.forEach { modelContext.delete($0) }
        }

        candidate.teamID = teamID
        candidate.hireSeasonYear = allCareers.first?.currentSeason ?? 2026
        candidate.contractYearsRemaining = 3
        modelContext.insert(candidate)
        hiredCoachID = candidate.id

        // R30: every hire joins the user's coaching tree.
        if let career = allCareers.first {
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

        // Fix #49: Notify parent about the hire for toast display
        let hiredName = candidate.fullName
        let hiredRole = role.displayName

        // Fix #87: Dismiss sheet first, then pop HireCoachView after sheet animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            selectedCandidate = nil  // Close the sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onHired?(hiredName, hiredRole)
                dismiss()
            }
        }
    }
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
    /// BUG FIX: True when the user's career role is .gmAndHeadCoach (no HC Coach record exists).
    let userIsHeadCoach: Bool
    /// BUG FIX: User's coaching style — used as the HC reference for chemistry when userIsHeadCoach.
    let userCoachingStyle: CoachingStyle?
    /// R30 Market 2.0: how many rival teams are pursuing this candidate.
    /// Competition raises rejection risk unless the user overbids.
    let marketRivals: Int
    let onHire: () -> Void
    /// #271: Callback when candidate rejects offer
    var onRejected: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var proposedSalary: Double
    @State private var proposedYears: Int = 3
    @State private var negotiationResult: NegotiationResult?

    init(candidate: Coach, remainingBudget: Int, isHired: Bool, headCoach: Coach?, currentCoach: Coach?, candidateRank: Int, totalCandidates: Int, schemeFitResult: (color: Color, label: String)?, userIsHeadCoach: Bool = false, userCoachingStyle: CoachingStyle? = nil, marketRivals: Int = 0, onHire: @escaping () -> Void, onRejected: (() -> Void)? = nil) {
        self.candidate = candidate
        self.remainingBudget = remainingBudget
        self.isHired = isHired
        self.headCoach = headCoach
        self.currentCoach = currentCoach
        self.candidateRank = candidateRank
        self.totalCandidates = totalCandidates
        self.schemeFitResult = schemeFitResult
        self.userIsHeadCoach = userIsHeadCoach
        self.userCoachingStyle = userCoachingStyle
        self.marketRivals = marketRivals
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
            Text("CAREER HISTORY")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            ForEach(careerHistoryLines, id: \.self) { line in
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
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
            // Projected wins: blend overall + motivation + discipline.
            let ovr = Double(coachOverall(candidate))
            let mot = Double(candidate.motivation)
            let disc = Double(candidate.discipline)
            let blend = (ovr * 0.5 + mot * 0.25 + disc * 0.25 - leagueAvg)
            let wins = max(-2.0, min(2.0, blend * 0.04))
            items.append((
                label: "Projected wins",
                value: "\(wins >= 0 ? "+" : "")\(String(format: "%.1f", wins)) / season",
                icon: "trophy.fill",
                color: wins >= 0 ? .success : .danger
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
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            ForEach(projectedImpactEstimates, id: \.label) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.color)
                        .frame(width: 18)
                    Text(item.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(item.value)
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(item.color)
                }
            }

            Text("Estimates based on attribute deltas vs. league average.")
                .font(.system(size: 9, weight: .medium))
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
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
        }
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
            if strongFits[style]?.contains(candidate.personality) == true {
                return ("Strong", .success,
                        "\(candidate.personality.displayName) fits well with your \(style.displayName) approach.")
            }
            if weakFits[style]?.contains(candidate.personality) == true {
                return ("Weak", .danger,
                        "\(candidate.personality.displayName) may clash with your \(style.displayName) approach.")
            }
            return ("Average", .textSecondary,
                    "Neutral fit with your \(style.displayName) approach.")
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
                                // #22: Role-aware projected contribution.
                                projectedImpactCard
                                // #90: Position group impact (kept for finer-grained efficiency view).
                                positionGroupImpactCard
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
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentGold)
            Text("Ranked #\(candidateRank) of \(totalCandidates) candidates")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            if candidateRank <= 3 {
                Text("Best Available")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Name + role badge
            HStack(spacing: 10) {
                Text(candidate.role.abbreviation)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(candidate.role.badgeColor, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.fullName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 8) {
                        Text("Age \(candidate.age)")
                        Text("\u{00B7}")
                        Text("\(candidate.yearsExperience) yrs experience")
                        Text("\u{00B7}")
                        Text(candidate.personality.displayName)
                            .foregroundStyle(Color.accentBlue)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Overall rating + scheme + salary summary
            HStack(spacing: 12) {
                // #160: Overall badge with context label
                let ovr = coachOverall(candidate)
                VStack(spacing: 2) {
                    Text("\(ovr)")
                        .font(.system(size: 22, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.forRating(ovr))
                    Text("OVR")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                    Text(ovrContextLabel(ovr))
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Color.forRating(ovr).opacity(0.8))
                }
                .frame(width: 52, height: 58)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))

                // #89: Coach development potential
                VStack(spacing: 2) {
                    Text(candidatePotentialLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(candidatePotentialColor)
                    Text("Potential")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(candidatePotentialColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                if let off = candidate.offensiveScheme {
                    schemeTag(off.displayName, color: .accentBlue)
                }
                if let def = candidate.defensiveScheme {
                    schemeTag(def.displayName, color: .danger)
                }

                // Fix #66: Scheme fit badge in header
                if let fit = schemeFitResult {
                    HStack(spacing: 4) {
                        Circle().fill(fit.color).frame(width: 8, height: 8)
                        Text(fit.label)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(fit.color)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(fit.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                }

                // #91: Other teams' interest badge
                demandBadge

                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Asking Salary")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Text(salaryFormatted(candidate.salary))
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
        .padding(16)
        .cardBackground()
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
                    .font(.system(size: 16, weight: .semibold))
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
                    .font(.system(size: 11, weight: .black))
                    .tracking(1.5)
                    .foregroundStyle(Color.accentGold)
                Spacer()
                // #87: Upgrade summary
                Text("vs \(current.fullName) (\(curOVR) OVR) — \(delta >= 0 ? "+\(delta)" : "\(delta)") \(delta > 0 ? "upgrade" : delta < 0 ? "downgrade" : "even")")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(delta > 0 ? Color.success : delta < 0 ? Color.danger : Color.textTertiary)
            }

            HStack(spacing: 16) {
                // Current
                VStack(spacing: 4) {
                    Text(current.fullName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Text("\(curOVR)")
                        .font(.system(size: 18, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.forRating(curOVR))
                    Text(salaryFormatted(current.salary))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)

                // Arrow with delta
                VStack(spacing: 2) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                    Text(delta >= 0 ? "+\(delta)" : "\(delta)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(delta > 0 ? Color.success : delta < 0 ? Color.danger : Color.textTertiary)
                }

                // New candidate
                VStack(spacing: 4) {
                    Text(candidate.fullName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("\(newOVR)")
                        .font(.system(size: 18, weight: .black).monospacedDigit())
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
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Text(d >= 0 ? "+\(d)" : "\(d)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(d > 0 ? Color.success : d < 0 ? Color.danger : Color.textTertiary)
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
                .font(.system(size: 16, weight: .semibold))
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

    // MARK: - Position Group Impact Card (#90)

    private var positionGroupImpactCard: some View {
        let leagueAvg = 65.0
        let playBoost = (Double(candidate.playCalling) - leagueAvg) * 0.15
        let devBoost = (Double(candidate.playerDevelopment) - leagueAvg) * 0.15
        let avgBoost = (playBoost + devBoost) / 2.0

        let offensiveRoles: [CoachRole] = [.offensiveCoordinator, .qbCoach, .rbCoach, .wrCoach, .olCoach]
        let defensiveRoles: [CoachRole] = [.defensiveCoordinator, .dlCoach, .lbCoach, .dbCoach]
        let sideLabel: String = offensiveRoles.contains(candidate.role) ? "offensive" :
            defensiveRoles.contains(candidate.role) ? "defensive" : "unit"

        return VStack(alignment: .leading, spacing: 8) {
            Text("PROJECTED IMPACT")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            HStack(spacing: 10) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(avgBoost >= 0 ? Color.success : Color.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Expected \(sideLabel) boost: \(avgBoost >= 0 ? "+" : "")\(String(format: "%.1f", avgBoost))% efficiency")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(avgBoost >= 0 ? Color.success : Color.danger)
                    HStack(spacing: 12) {
                        Text("Play Calling: \(playBoost >= 0 ? "+" : "")\(String(format: "%.1f", playBoost))%")
                            .font(.caption)
                            .foregroundStyle(playBoost >= 0 ? Color.success.opacity(0.8) : Color.danger.opacity(0.8))
                        Text("Player Dev: \(devBoost >= 0 ? "+" : "")\(String(format: "%.1f", devBoost))%")
                            .font(.caption)
                            .foregroundStyle(devBoost >= 0 ? Color.success.opacity(0.8) : Color.danger.opacity(0.8))
                    }
                }
            }

            Text("Compared to league average (\(Int(leagueAvg)) rating)")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Attributes Card (Fix #64: color-coded)

    private var attributesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ATTRIBUTES")
                .font(.system(size: 11, weight: .black))
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

    /// Fix #64 + #86: Color-coded attribute cells with tier label.
    private func attributeCell(name: String, value: Int) -> some View {
        let tier = attributeTier(value)
        return HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(tier.label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tier.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tier.color.opacity(tier.isElite ? 0.18 : 0.10))
                )
            Text("\(value)")
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.forRating(value).opacity(0.06))
        )
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
                .font(.system(size: 11, weight: .black))
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

    private var schemeFitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCHEME FIT")
                .font(.system(size: 11, weight: .black))
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
                            Text("Hire a Head Coach first for scheme compatibility rating.")
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

            // #88: Scheme expertise levels
            if !candidate.schemeExpertise.isEmpty {
                Divider().overlay(Color.surfaceBorder)

                Text("SCHEME EXPERTISE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.textTertiary)

                ForEach(candidate.schemeExpertise.sorted(by: { $0.value > $1.value }), id: \.key) { scheme, value in
                    HStack(spacing: 8) {
                        Text(scheme)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 80, alignment: .leading)

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
                            .font(.system(size: 11, weight: .bold))
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
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            // Personality
            HStack(spacing: 8) {
                Image(systemName: "person.fill")
                    .font(.system(size: 14))
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
                        .font(.system(size: 10))
                        .foregroundStyle(isNegative ? Color.danger : Color.success)
                        .frame(width: 16)
                    Text(item.effect)
                        .font(.caption)
                        .foregroundStyle(isNegative ? Color.danger : Color.success)
                }
            }

            Divider().overlay(Color.surfaceBorder)

            // Fix #70: Chemistry prediction with HC
            let chem = chemistryPrediction
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
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
                .font(.system(size: 11, weight: .black))
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
                        .foregroundStyle(isOverBudget ? Color.danger : Color.accentGold)
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
            }

            // Fix #69: Acceptance likelihood
            HStack(spacing: 8) {
                Image(systemName: "gauge.medium")
                    .foregroundStyle(acceptanceLikelihood.color)
                Text("Acceptance: \(acceptanceLikelihood.label)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(acceptanceLikelihood.color)
                Spacer()
                // Fix #65: Budget after hire
                Text("Budget after: $\(formatBudget(budgetAfterHire))M")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(budgetAfterHire >= 0 ? Color.textSecondary : Color.danger)
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
                        .font(.system(size: 12))
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
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(contractLengthEffect)
                        .font(.system(size: 10, weight: .medium))
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
                        .foregroundStyle(rejectionChance > 0.5 ? Color.danger : Color.warning)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((rejectionChance > 0.5 ? Color.danger : Color.warning).opacity(0.1))
                )
            }

            if isOverBudget {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(Color.danger)
                    Text("Over budget")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.danger)
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

                    // #92: Accept counter-offer button
                    if let counter = result.counterOffer, !result.accepted {
                        Button {
                            acceptCounterOffer(amount: counter)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "handshake.fill")
                                    .font(.system(size: 14))
                                Text("Accept Counter: \(salaryFormatted(counter))/yr")
                                    .font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(Color.backgroundPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Int(counter) > remainingBudget ? Color.backgroundTertiary : Color.warning)
                            )
                        }
                        .disabled(Int(counter) > remainingBudget)
                        .buttonStyle(.plain)
                    }
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

            // Make Offer button
            if !isHired && negotiationResult?.accepted != true {
                Button {
                    makeOffer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "handshake.fill")
                            .font(.system(size: 16, weight: .semibold))
                        VStack(spacing: 2) {
                            Text("Offer Contract")
                                .font(.headline.weight(.bold))
                            // Fix #65: Budget impact on offer button
                            Text("Budget after hire: $\(formatBudget(budgetAfterHire))M remaining")
                                .font(.caption2)
                                .opacity(0.8)
                        }
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isOverBudget ? Color.backgroundTertiary : Color.accentGold)
                    )
                }
                .disabled(isOverBudget)
                .buttonStyle(.plain)
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
            .font(.system(size: 11, weight: .medium))
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

// MARK: - Preview

#Preview {
    NavigationStack {
        HireCoachView(role: .offensiveCoordinator, teamID: UUID(), remainingBudget: 15_000)
    }
    .modelContainer(for: Coach.self, inMemory: true)
}
