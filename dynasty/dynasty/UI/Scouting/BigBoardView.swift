import SwiftUI
import SwiftData

struct BigBoardView: View {
    let career: Career
    let prospects: [CollegeProspect]
    let teamRoster: [Player]
    var scoutsSentToCombine: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var positionFilter: ProspectPositionFilter = .all
    @State private var flagFilter: ProspectFlagFilter = .all
    @State private var boardOrder: [UUID] = []
    @State private var attributeTab: ProspectAttributeTab = .overview
    @State private var showWatchlistOnly: Bool = false
    @State private var editingAssessmentProspect: CollegeProspect?
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
    @State private var filterStarredOnly: Bool = false
    @State private var filterMyGradeFirstRound: Bool = false
    @ObservedObject private var userGradeStore = UserProspectGradeStore.shared
    @State private var isLoading: Bool = true
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var cachedTieredBoard: [(tier: Int, prospects: [CollegeProspect])] = []
    @State private var cachedOrderedBoard: [CollegeProspect] = []
    @State private var cachedCustomOrderedBoard: [CollegeProspect] = []
    /// O(1) rank lookup by prospect ID — avoids per-row firstIndex(where:) which would be O(n²) overall.
    @State private var cachedRankMap: [UUID: Int] = [:]
    @State private var cachedCustomRankMap: [UUID: Int] = [:]

    // MARK: - Prospect Notes Storage

    @AppStorage("prospectNotes") private var prospectNotesJSON: String = "{}"

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

    // MARK: - Own Assessments & Watchlist Storage

    @AppStorage("prospectOwnAssessments") private var prospectOwnAssessmentsJSON: String = "{}"
    @AppStorage("prospectWatchlist") private var prospectWatchlistJSON: String = "[]"
    @AppStorage("prospectCustomBoard") private var prospectCustomBoardJSON: String = "[]"
    @AppStorage("rosterPriorities") private var rosterPrioritiesJSON: String = "{}"

    private static let gradeOptions = ["none", "A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D", "F"]

    private var prospectOwnAssessments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(prospectOwnAssessmentsJSON.utf8))) ?? [:]
    }

    private var prospectWatchlist: Set<String> {
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

    private func toggleWatchlist(prospectID: UUID) {
        var list = prospectWatchlist
        let key = prospectID.uuidString
        if list.contains(key) {
            list.remove(key)
        } else {
            list.insert(key)
        }
        if let data = try? JSONEncoder().encode(Array(list)) {
            prospectWatchlistJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    private func isOnWatchlist(_ prospectID: UUID) -> Bool {
        prospectWatchlist.contains(prospectID.uuidString)
    }

    // MARK: - Custom Board Storage

    private var customBoardOrder: [UUID] {
        let strings = (try? JSONDecoder().decode([String].self, from: Data(prospectCustomBoardJSON.utf8))) ?? []
        return strings.compactMap { UUID(uuidString: $0) }
    }

    private func saveCustomBoardOrder(_ ids: [UUID]) {
        let strings = ids.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(strings) {
            prospectCustomBoardJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    // MARK: - User Roster Priorities

    private var rosterPriorities: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rosterPrioritiesJSON.utf8))) ?? [:]
    }

    // MARK: - Tier Constants

    private static let tierNames = ["Blue Chip", "First Rounder", "Day Two (Rd 2-3)", "Day Three (Rd 4-5)", "Late Rounds (Rd 6-7)", "Priority UDFA", "Draftable"]
    private static let tierColors: [Color] = [.accentGold, .success, .accentBlue, .accentBlue.opacity(0.6), .textSecondary, .textTertiary, .textTertiary]
    private static let tierDescriptions = [
        "Elite talent, projected Rd 1 pick",
        "Top tier, solid Rd 1-2 projection",
        "Quality starters, Rd 2-3 range",
        "Developmental starters, Rd 4-5 range",
        "Depth / special teams, Rd 6-7 range",
        "Undrafted free agent priority",
        "Camp bodies / long-shot prospects"
    ]

    // MARK: - Board Prospects

    private var scoutedProspects: [CollegeProspect] {
        prospects.filter { $0.scoutedOverall != nil }
    }

    /// Composite board score: scouted overall weighted by positional draft value.
    /// This ensures QB/DE/LT rank highly while P/K/FB are pushed down.
    /// Reduced positional weight (0.15) so raw talent matters more than position.
    private func boardCompositeScore(for prospect: CollegeProspect) -> Double {
        let ovr = Double(prospect.scoutedOverall ?? prospect.trueOverall)
        let posValue = ScoutingEngine.positionalDraftValue(for: prospect.position)
        return ovr * (0.85 + 0.15 * posValue)
    }

    /// Projected round based on composite board score (considers positional value).
    private func boardProjectedRound(for prospect: CollegeProspect) -> Int {
        let score = boardCompositeScore(for: prospect)
        // Map composite score to round: higher score = lower (better) round
        switch score {
        case 82...:  return 1
        case 76..<82: return 2
        case 70..<76: return 3
        case 64..<70: return 4
        case 58..<64: return 5
        case 52..<58: return 6
        case 46..<52: return 7
        default:       return 8 // UDFA
        }
    }

    /// Board tier based on composite score (considers positional value).
    private func boardTier(for prospect: CollegeProspect) -> Int {
        if let manual = prospect.manualTier { return manual }
        let score = boardCompositeScore(for: prospect)
        switch score {
        case 85...:  return 1  // Blue Chip
        case 78..<85: return 2  // First Rounder
        case 72..<78: return 3  // Day Two (Rd 2-3)
        case 66..<72: return 4  // Day Three (Rd 4-5)
        case 58..<66: return 5  // Late Rounds (Rd 6-7)
        case 50..<58: return 6  // Priority UDFA
        default:       return 7  // Draftable
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
        switch flagFilter {
        case .all:      break
        case .mustHave: result = result.filter { $0.prospectFlag == .mustHave }
        case .sleeper:  result = result.filter { $0.prospectFlag == .sleeper }
        case .avoid:    result = result.filter { $0.prospectFlag == .avoid }
        }
        if showWatchlistOnly {
            result = result.filter { isOnWatchlist($0.id) }
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
        // User grade filters
        if filterStarredOnly {
            result = result.filter { userGradeStore.isStarred($0.id) }
        }
        if filterMyGradeFirstRound {
            result = result.filter { userGradeStore.isFirstRoundPlus($0.id) }
        }
        return result
    }

    private var orderedBoard: [CollegeProspect] {
        let filtered = filteredProspects

        // #9: Apply sort order
        switch boardSortOrder {
        case .boardRank:
            var orderedIDs = boardOrder.filter { id in filtered.contains { $0.id == id } }
            let unordered = filtered.filter { !orderedIDs.contains($0.id) }.map { $0.id }
            orderedIDs.append(contentsOf: unordered)
            return orderedIDs.compactMap { id in filtered.first { $0.id == id } }
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

    /// Custom-ordered board for "My Board" mode.
    private var customOrderedBoard: [CollegeProspect] {
        let filtered = filteredProspects
        let savedOrder = customBoardOrder
        var ordered = savedOrder.compactMap { id in filtered.first { $0.id == id } }
        let remaining = filtered.filter { p in !savedOrder.contains(p.id) }
        ordered.append(contentsOf: remaining)
        return ordered
    }

    /// Maximum number of same-position prospects allowed per tier.
    private static let maxSamePositionPerTier = 4

    /// Prospects grouped by tier, maintaining board order within each tier.
    /// Enforces position diversity: max 4 of same position per tier.
    /// Overflow prospects are pushed to the next tier down.
    private var tieredBoard: [(tier: Int, prospects: [CollegeProspect])] {
        let board = orderedBoard

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
                if count < Self.maxSamePositionPerTier {
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

    /// Grade text for a prospect — prefers grade range, falls back to letter grade from numeric.
    private func bestAvailableGradeText(_ prospect: CollegeProspect) -> String {
        if let gradeRange = prospect.scoutedOverallGrade {
            return gradeRange.displayText
        }
        return LetterGrade.from(numericValue: prospect.scoutedOverall ?? prospect.trueOverall).rawValue
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
        let ordered = orderedBoard
        let custom = customOrderedBoard
        cachedOrderedBoard = ordered
        cachedCustomOrderedBoard = custom
        cachedTieredBoard = tieredBoard
        // Build O(1) rank lookup tables once per refresh.
        var rankMap: [UUID: Int] = [:]
        rankMap.reserveCapacity(ordered.count)
        for (idx, p) in ordered.enumerated() { rankMap[p.id] = idx + 1 }
        cachedRankMap = rankMap

        var customMap: [UUID: Int] = [:]
        customMap.reserveCapacity(custom.count)
        for (idx, p) in custom.enumerated() { customMap[p.id] = idx + 1 }
        cachedCustomRankMap = customMap
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
            } else if scoutedProspects.isEmpty {
                emptyState
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
                            Button(filterStarredOnly ? "Show All (not just starred)" : "Starred Only") {
                                filterStarredOnly.toggle()
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
                                flagFilter = .all
                                showWatchlistOnly = false
                                filterStarredOnly = false
                                filterMyGradeFirstRound = false
                                searchText = ""
                            }
                        } label: {
                            let hasActiveFilter = filterProjectedRoundMin > 1 || filterProjectedRoundMax < 8 || filterRisk != nil || filterStarredOnly || filterMyGradeFirstRound
                            Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                                .font(.body)
                                .foregroundStyle(hasActiveFilter ? Color.accentBlue : Color.textSecondary)
                        }

                        // Auto-rank button (#12)
                        Button {
                            autoRankBoard()
                        } label: {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.body)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .help("Auto-rank board by composite score")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.backgroundPrimary)

                    bigBoardAttributeTabPicker

                    bigBoardColumnHeaders
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                        .background(Color.backgroundPrimary)

                    Divider().overlay(Color.surfaceBorder)

                    List {
                        recommendationsSection
                        depthAnalysisSection
                        if showMyBoard {
                            // Flat custom-ordered list
                            Section {
                                ForEach(cachedCustomOrderedBoard) { prospect in
                                    HStack(spacing: 0) {
                                        ProspectStarButton(prospectID: prospect.id)

                                        NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                            BigBoardRowView(
                                                rank: customRankFor(prospect),
                                                totalCount: cachedCustomOrderedBoard.count,
                                                prospect: prospect,
                                                ownGrade: prospectOwnAssessments[prospect.id.uuidString],
                                                isWatchlisted: isOnWatchlist(prospect.id),
                                                schemeFit: schemeFitLabel(for: prospect),
                                                needLevel: needLevel(for: prospect.position),
                                                starterComparison: starterComparison(for: prospect),
                                                attributeTab: attributeTab,
                                                scoutsSentToCombine: scoutsSentToCombine,
                                                isPositionNeed: teamNeedPositions.contains(prospect.position),
                                                projectedRound: boardProjectedRound(for: prospect),
                                                isValuePick: isValuePick(prospect),
                                                originalPosition: userGradeStore.getOriginalPosition(for: prospect.id),
                                                onFlagToggle: { toggleFlag(prospect) },
                                                onWatchlistToggle: { toggleWatchlist(prospectID: prospect.id) },
                                                onGradeTap: { editingAssessmentProspect = prospect }
                                            )
                                        }
                                    }
                                    .listRowBackground(Color.backgroundSecondary)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
                                    .contextMenu {
                                        tierContextMenu(for: prospect)
                                    }
                                }
                                .onMove { from, to in
                                    moveCustomBoard(from: from, to: to)
                                }
                            } header: {
                                Label("My Board (\(cachedCustomOrderedBoard.count))", systemImage: "person.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.textSecondary)
                                    .textCase(nil)
                            }
                        } else {
                            // Scout tiered board
                            ForEach(cachedTieredBoard, id: \.tier) { tierGroup in
                                Section {
                                    ForEach(tierGroup.prospects) { prospect in
                                        HStack(spacing: 0) {
                                            ProspectStarButton(prospectID: prospect.id)

                                            NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                                BigBoardRowView(
                                                    rank: rankFor(prospect),
                                                    totalCount: cachedOrderedBoard.count,
                                                    prospect: prospect,
                                                    ownGrade: prospectOwnAssessments[prospect.id.uuidString],
                                                    isWatchlisted: isOnWatchlist(prospect.id),
                                                    schemeFit: schemeFitLabel(for: prospect),
                                                    needLevel: needLevel(for: prospect.position),
                                                    starterComparison: starterComparison(for: prospect),
                                                    attributeTab: attributeTab,
                                                    scoutsSentToCombine: scoutsSentToCombine,
                                                    isPositionNeed: teamNeedPositions.contains(prospect.position),
                                                    projectedRound: boardProjectedRound(for: prospect),
                                                    isValuePick: isValuePick(prospect),
                                                    originalPosition: userGradeStore.getOriginalPosition(for: prospect.id),
                                                    onFlagToggle: { toggleFlag(prospect) },
                                                    onWatchlistToggle: { toggleWatchlist(prospectID: prospect.id) },
                                                    onGradeTap: { editingAssessmentProspect = prospect }
                                                )
                                            }
                                        }
                                        .listRowBackground(Color.backgroundSecondary)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
                                        .contextMenu {
                                            tierContextMenu(for: prospect)
                                        }
                                    }
                                    .onMove { from, to in
                                        moveTierProspects(tier: tierGroup.tier, from: from, to: to)
                                    }
                                } header: {
                                    tierHeader(tier: tierGroup.tier, count: tierGroup.prospects.count)
                                }
                            }
                        }
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                positionPicker
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
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMyBoard.toggle()
                } label: {
                    Text(showMyBoard ? "My Board" : "Scout Board")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(showMyBoard ? Color.accentGold : Color.textSecondary)
                }
            }
        }
        .task {
            if boardOrder.isEmpty {
                boardOrder = scoutedProspects
                    .sorted { boardCompositeScore(for: $0) > boardCompositeScore(for: $1) }
                    .map { $0.id }
            }
            // Record original board positions (only sets if not already set)
            for (index, id) in boardOrder.enumerated() {
                userGradeStore.setOriginalPosition(for: id, position: index + 1)
            }
            loadCoaches()
            loadDraftPicks()
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
        .onChange(of: flagFilter) { _, _ in refreshCachedBoard() }
        .onChange(of: boardSortOrder) { _, _ in refreshCachedBoard() }
        .onChange(of: showMyBoard) { _, _ in refreshCachedBoard() }
        .onChange(of: showWatchlistOnly) { _, _ in refreshCachedBoard() }
        .onChange(of: filterProjectedRoundMin) { _, _ in refreshCachedBoard() }
        .onChange(of: filterProjectedRoundMax) { _, _ in refreshCachedBoard() }
        .onChange(of: filterRisk) { _, _ in refreshCachedBoard() }
        .onChange(of: filterStarredOnly) { _, _ in refreshCachedBoard() }
        .onChange(of: filterMyGradeFirstRound) { _, _ in refreshCachedBoard() }
    }

    // MARK: - Attribute Tab Picker (Capsule-style)

    private var bigBoardAttributeTabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ProspectAttributeTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            attributeTab = tab
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10))
                            Text(tab.label)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(attributeTab == tab ? Color.backgroundPrimary : Color.textSecondary)
                        .background(
                            attributeTab == tab ? Color.accentBlue : Color.backgroundTertiary,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    attributeTab == tab ? Color.accentBlue : Color.surfaceBorder,
                                    lineWidth: 1
                                )
                        )
                    }
                    .accessibilityLabel("View mode: \(tab.label)")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .background(Color.backgroundPrimary)
    }

    // MARK: - Column Headers

    @ViewBuilder
    private var bigBoardColumnHeaders: some View {
        HStack(spacing: 0) {
            // Rank
            Text("#")
                .frame(width: 28, alignment: .center)

            // POS
            Text("POS")
                .frame(width: 36, alignment: .center)

            // NAME
            Text("NAME")
                .frame(minWidth: 80, alignment: .leading)
                .padding(.leading, 6)

            Spacer(minLength: 2)

            // Tab-specific headers
            switch attributeTab {
            case .overview:
                bigBoardOverviewHeaders
            case .physical:
                bigBoardPhysicalHeaders
            case .mental:
                bigBoardMentalHeaders
            case .position:
                bigBoardPositionHeaders
            }

            // Always-visible: OVR (with tooltip explaining dual grade format)
            HStack(spacing: 2) {
                Text("OVR")
                InfoTooltipButton(
                    text: "Scout's read on the prospect. When you have logged your own grade you'll see \"Yours / Scout\" — a wider gap means more uncertainty in the scout's evaluation. Letter grades use the standard A-F tiers (see legend).",
                    showLetterGradeKey: true,
                    size: 9
                )
            }
            .frame(width: 50, alignment: .center)

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

    private var bigBoardOverviewHeaders: some View {
        Group {
            Text("AGE")
                .frame(width: 28, alignment: .center)
            Text("FIT")
                .frame(width: 32, alignment: .center)
            Text("NEED")
                .frame(width: 32, alignment: .center)
            Text("RISK")
                .frame(width: 64, alignment: .center)
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
    }

    private var bigBoardPhysicalHeaders: some View {
        Group {
            Text("SPD")
                .frame(width: 32, alignment: .center)
            Text("STR")
                .frame(width: 32, alignment: .center)
            Text("AGI")
                .frame(width: 32, alignment: .center)
            Text("ACC")
                .frame(width: 32, alignment: .center)
            Text("STA")
                .frame(width: 32, alignment: .center)
            Text("DUR")
                .frame(width: 32, alignment: .center)
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
    }

    private var bigBoardMentalHeaders: some View {
        Group {
            Text("AWR")
                .frame(width: 32, alignment: .center)
            Text("DEC")
                .frame(width: 32, alignment: .center)
            Text("WRK")
                .frame(width: 32, alignment: .center)
            Text("CLT")
                .frame(width: 32, alignment: .center)
            Text("COA")
                .frame(width: 32, alignment: .center)
            Text("LDR")
                .frame(width: 32, alignment: .center)
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
    }

    private var bigBoardPositionHeaders: some View {
        Group {
            ForEach(0..<4, id: \.self) { _ in
                Text("--")
                    .frame(width: 32, alignment: .center)
            }
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color.textTertiary)
    }

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
    private var userPriorityPositions: [String] {
        rosterPriorities
            .filter { $0.value != "none" }
            .sorted { priorityRank($0.value) < priorityRank($1.value) }
            .map { $0.key }
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

    // MARK: - Tier Header (#214)

    private func tierHeader(tier: Int, count: Int) -> some View {
        let tierIndex = min(tier - 1, Self.tierNames.count - 1)
        let tierProspects = cachedTieredBoard.first(where: { $0.tier == tier })?.prospects ?? []
        let needCount = tierProspects.filter { teamNeedPositions.contains($0.position) }.count
        let starCount = tierProspects.filter { isOnWatchlist($0.id) }.count
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Self.tierColors[tierIndex])
                    .frame(width: 10, height: 10)

                Text(Self.tierNames[tierIndex])
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Self.tierColors[tierIndex])
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
                if starCount > 0 {
                    HStack(spacing: 1) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 7))
                        Text("\(starCount)")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentGold)
                }
            }
            // Tier description (#8)
            Text(Self.tierDescriptions[tierIndex])
                .font(.system(size: 8))
                .foregroundStyle(Color.textTertiary)
                .textCase(nil)
        }
    }

    // MARK: - Tier Context Menu (#214)

    @ViewBuilder
    private func tierContextMenu(for prospect: CollegeProspect) -> some View {
        // User grade & star
        ProspectGradeContextMenu(prospectID: prospect.id)
        Divider()
        // Tier movement (#17)
        ForEach(1...7, id: \.self) { tier in
            if tier != boardTier(for: prospect) {
                Button {
                    moveProspectToTier(prospect, tier: tier)
                } label: {
                    Label("Move to \(Self.tierNames[tier - 1])", systemImage: "arrow.right.circle")
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
            } label: {
                Label("Reset to Auto Tier", systemImage: "arrow.counterclockwise")
            }
        }
        Divider()
        // Draft round projection
        let roundOptions: [(label: String, projection: Int)] = [
            ("Move to Round 1", 1),
            ("Move to Round 2-3", 2),
            ("Move to Round 4-5", 4),
            ("Move to Round 6-7", 6)
        ]
        ForEach(roundOptions, id: \.projection) { option in
            Button {
                prospect.draftProjection = option.projection
            } label: {
                Label(option.label, systemImage: "number.circle")
            }
        }
        Divider()
        Button {
            toggleFlag(prospect)
        } label: {
            Label(nextFlagLabel(for: prospect), systemImage: nextFlagIcon(for: prospect))
        }
        Divider()
        // #11: Notes
        Button {
            editingNoteProspect = prospect
        } label: {
            Label(
                prospectNotes[prospect.id.uuidString] != nil ? "Edit Note" : "Add Note",
                systemImage: "note.text"
            )
        }
    }

    // MARK: - Toolbar

    private var positionPicker: some View {
        HStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProspectPositionFilter.allCases) { filter in
                        let isSelected = positionFilter == filter
                        Button {
                            positionFilter = filter
                        } label: {
                            Text(filter.label)
                                .font(.caption.weight(isSelected ? .heavy : .medium))
                                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? Color.accentBlue : Color.backgroundTertiary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Picker("Flag", selection: $flagFilter) {
                ForEach(ProspectFlagFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 44)

            Button {
                showWatchlistOnly.toggle()
            } label: {
                Image(systemName: showWatchlistOnly ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(showWatchlistOnly ? Color.accentGold : Color.textSecondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.star")
                .font(.system(size: 52))
                .foregroundStyle(Color.textTertiary)

            Text("Big Board Is Empty")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text("Scout prospects to add them to your draft board.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func moveCustomBoard(from: IndexSet, to: Int) {
        var list = cachedCustomOrderedBoard.map { $0.id }
        list.move(fromOffsets: from, toOffset: to)
        saveCustomBoardOrder(list)
    }

    private func toggleFlag(_ prospect: CollegeProspect) {
        switch prospect.prospectFlag {
        case .none:     prospect.prospectFlag = .mustHave
        case .mustHave: prospect.prospectFlag = .sleeper
        case .sleeper:  prospect.prospectFlag = .avoid
        case .avoid:    prospect.prospectFlag = .none
        }
    }

    private func nextFlagLabel(for prospect: CollegeProspect) -> String {
        switch prospect.prospectFlag {
        case .none:     return "Flag: Must Have"
        case .mustHave: return "Flag: Sleeper"
        case .sleeper:  return "Flag: Avoid"
        case .avoid:    return "Clear Flag"
        }
    }

    private func nextFlagIcon(for prospect: CollegeProspect) -> String {
        switch prospect.prospectFlag {
        case .none:     return "star.fill"
        case .mustHave: return "eye.fill"
        case .sleeper:  return "xmark.octagon.fill"
        case .avoid:    return "flag.slash"
        }
    }

    /// Move prospect to a different tier using manual tier override (preserves scoutedOverall).
    private func moveProspectToTier(_ prospect: CollegeProspect, tier: Int) {
        prospect.manualTier = tier
    }

    private func moveTierProspects(tier: Int, from: IndexSet, to: Int) {
        let tierProspects = cachedTieredBoard.first(where: { $0.tier == tier })?.prospects ?? []
        var tierIDs = tierProspects.map { $0.id }
        tierIDs.move(fromOffsets: from, toOffset: to)

        // Rebuild full board order: replace the tier slice with the reordered IDs.
        var fullOrder = boardOrder
        let oldTierIDs = Set(tierProspects.map { $0.id })
        fullOrder.removeAll { oldTierIDs.contains($0) }

        // Find insertion point: after the last ID from the previous tier.
        let previousTierIDs = cachedTieredBoard
            .filter { $0.tier < tier }
            .flatMap { $0.prospects.map { $0.id } }
        let insertIndex: Int
        if let lastPrev = previousTierIDs.last,
           let idx = fullOrder.firstIndex(of: lastPrev) {
            insertIndex = fullOrder.index(after: idx)
        } else {
            insertIndex = 0
        }
        fullOrder.insert(contentsOf: tierIDs, at: insertIndex)
        boardOrder = fullOrder
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

    /// Auto-rank the board using composite score (#12)
    private func autoRankBoard() {
        boardOrder = scoutedProspects
            .sorted { boardCompositeScore(for: $0) > boardCompositeScore(for: $1) }
            .map { $0.id }
        // Clear and re-record original positions
        userGradeStore.clearOriginalPositions()
        for (index, id) in boardOrder.enumerated() {
            userGradeStore.setOriginalPosition(for: id, position: index + 1)
        }
    }

    /// Move a prospect up or down in the board order (#17)
    private func moveBoardPosition(_ prospect: CollegeProspect, direction: Int) {
        guard let idx = boardOrder.firstIndex(of: prospect.id) else { return }
        let newIdx = idx + direction
        guard newIdx >= 0, newIdx < boardOrder.count else { return }
        boardOrder.swapAt(idx, newIdx)
    }

    /// Probability prospect is available at user's first pick (#18)
    private func availableAtPickProbability(for prospect: CollegeProspect) -> Double? {
        let sortedPicks = teamDraftPicks
            .filter { !$0.isComplete }
            .sorted { $0.pickNumber < $1.pickNumber }
        guard let firstPick = sortedPicks.first else { return nil }
        let projRound = boardProjectedRound(for: prospect)
        let pickRound = max(1, ((firstPick.pickNumber - 1) / 32) + 1)
        if projRound > pickRound + 1 { return 0.95 }
        if projRound > pickRound { return 0.75 }
        if projRound == pickRound { return 0.40 }
        if projRound == pickRound - 1 { return 0.15 }
        return 0.05
    }

    private func loadCoaches() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        coaches = (try? modelContext.fetch(desc)) ?? []
    }

    private func loadDraftPicks() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<DraftPick>(predicate: #Predicate { $0.currentTeamID == teamID })
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

// MARK: - Flag Filter

enum ProspectFlagFilter: String, CaseIterable, Identifiable {
    case all, mustHave, sleeper, avoid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:      return "All"
        case .mustHave: return "Must Have"
        case .sleeper:  return "Sleepers"
        case .avoid:    return "Avoid"
        }
    }
}

// MARK: - Big Board Row View (Compact Table Row)

struct BigBoardRowView: View {
    let rank: Int
    var totalCount: Int = 0
    let prospect: CollegeProspect
    var ownGrade: String? = nil
    var isWatchlisted: Bool = false
    var schemeFit: String? = nil
    var needLevel: String = "Set"
    var starterComparison: String? = nil
    var attributeTab: ProspectAttributeTab = .overview
    var scoutsSentToCombine: Bool = false
    var isPositionNeed: Bool = false
    var projectedRound: Int = 7
    var isValuePick: Bool = false
    var originalPosition: Int? = nil
    var onFlagToggle: (() -> Void)? = nil
    var onWatchlistToggle: (() -> Void)? = nil
    var onGradeTap: (() -> Void)? = nil

    private var isScouted: Bool { prospect.scoutedOverall != nil }

    var body: some View {
        HStack(spacing: 0) {
            // Rank number with counter (#13) and manual move indicator
            VStack(spacing: 0) {
                Text("\(rank)")
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(manualMoveRankColor)
                if let orig = originalPosition, orig != rank {
                    let movedUp = rank < orig
                    Text("\(movedUp ? "\u{2191}" : "\u{2193}") #\(orig)")
                        .font(.system(size: 8, weight: .semibold).monospacedDigit())
                        .foregroundStyle(movedUp ? Color.success : Color.danger)
                } else if totalCount > 0 {
                    Text("/\(totalCount)")
                        .font(.system(size: 6).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(width: 28, alignment: .center)

            // Position badge
            boardPositionBadge

            // Name column (compact)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(prospect.fullName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    // Shortlist star (#11)
                    if isWatchlisted {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.accentGold)
                    }

                    UserGradeBadge(prospectID: prospect.id)

                    // Value pick indicator (#14)
                    if isValuePick {
                        Text("Value")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.success, in: RoundedRectangle(cornerRadius: 2))
                    }
                }

                // Compact sub-info icons
                HStack(spacing: 4) {
                    // Flag indicator (inline)
                    boardFlagIcon

                    // #5: Scouting report count
                    if prospect.scoutReportCount > 0 {
                        Text(prospect.scoutConfidenceDots)
                            .font(.system(size: 7))
                            .foregroundStyle(prospect.scoutReportCount >= 3 ? Color.success : prospect.scoutReportCount >= 2 ? Color.accentBlue : Color.textTertiary)
                    }

                    // CMB badge with color coding (#7)
                    if prospect.combineInvite {
                        Text("CMB")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(combinePerformanceColor, in: RoundedRectangle(cornerRadius: 2))
                    }
                    if prospect.interviewCompleted {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.accentBlue)
                    }
                    if let mention = prospect.combineMediaMention, !mention.isEmpty {
                        Image(systemName: "newspaper.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(boardMediaColor(for: prospect))
                    }

                    // #6: Current starter comparison
                    if let comparison = starterComparison {
                        Text(comparison)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(comparison.hasPrefix("+") ? Color.success : comparison.contains("Depth") ? Color.danger : Color.textTertiary)
                    }
                }
            }
            .frame(minWidth: 80, alignment: .leading)
            .padding(.leading, 6)

            Spacer(minLength: 2)

            // Tab-specific columns
            switch attributeTab {
            case .overview:
                boardOverviewColumns
            case .physical:
                boardPhysicalColumns
            case .mental:
                boardMentalColumns
            case .position:
                boardPositionColumns
            }

            // Always-visible: OVR
            boardOverallBadge

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
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Overview Columns

    private var boardOverviewColumns: some View {
        Group {
            // Age
            Text("\(prospect.age)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 28, alignment: .center)

            // Scheme Fit
            boardSchemeFitIcon
                .frame(width: 32, alignment: .center)

            // Need indicator
            boardNeedIndicator
                .frame(width: 32, alignment: .center)

            // Risk label
            boardCompactRiskBadge
                .frame(width: 64, alignment: .center)
        }
    }

    // MARK: - Physical Columns

    private var boardPhysicalColumns: some View {
        Group {
            if prospect.fortyTime != nil {
                boardColorCodedMiniAttribute(value: prospect.truePhysical.speed, label: "SPD")
                    .frame(width: 32, alignment: .center)
                boardColorCodedMiniAttribute(value: prospect.truePhysical.strength, label: "STR")
                    .frame(width: 32, alignment: .center)
                boardColorCodedMiniAttribute(value: prospect.truePhysical.agility, label: "AGI")
                    .frame(width: 32, alignment: .center)
                boardColorCodedMiniAttribute(value: prospect.truePhysical.acceleration, label: "ACC")
                    .frame(width: 32, alignment: .center)
                boardColorCodedMiniAttribute(value: prospect.truePhysical.stamina, label: "STA")
                    .frame(width: 32, alignment: .center)
                boardColorCodedMiniAttribute(value: prospect.truePhysical.durability, label: "DUR")
                    .frame(width: 32, alignment: .center)
            } else {
                ForEach(0..<6, id: \.self) { _ in
                    Text("?")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 32, alignment: .center)
                }
            }
        }
    }

    // MARK: - Mental Columns

    private var boardMentalColumns: some View {
        Group {
            if isScouted {
                boardGradeRangeMiniAttribute(key: "AWR", label: "AWR", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
                boardGradeRangeMiniAttribute(key: "DEC", label: "DEC", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
                boardGradeRangeMiniAttribute(key: "WRK", label: "WRK", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
                boardGradeRangeMiniAttribute(key: "CLT", label: "CLT", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
                boardGradeRangeMiniAttribute(key: "COA", label: "COA", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
                boardGradeRangeMiniAttribute(key: "LDR", label: "LDR", grades: prospect.scoutedMentalGrades)
                    .frame(width: 32, alignment: .center)
            } else {
                ForEach(0..<6, id: \.self) { _ in
                    Text("--")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 32, alignment: .center)
                }
            }
        }
    }

    // MARK: - Position Columns

    private var boardPositionColumns: some View {
        Group {
            if isScouted {
                let keys = boardPositionSkillKeys
                ForEach(Array(keys.prefix(4).enumerated()), id: \.offset) { _, skill in
                    boardGradeRangeMiniAttribute(key: skill.key, label: skill.label, grades: prospect.scoutedPositionGrades)
                        .frame(width: 32, alignment: .center)
                }
                // Pad to 4 columns if fewer
                if keys.count < 4 {
                    ForEach(0..<(4 - min(keys.count, 4)), id: \.self) { _ in
                        Spacer().frame(width: 32)
                    }
                }
            } else {
                ForEach(0..<4, id: \.self) { _ in
                    Text("--")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 32, alignment: .center)
                }
            }
        }
    }

    /// Returns position-specific attribute keys and labels for grade lookup.
    private var boardPositionSkillKeys: [(key: String, label: String)] {
        switch prospect.truePositionAttributes {
        case .quarterback:
            return [("ARM", "ARM"), ("SAc", "SAc"), ("DAc", "DAc"), ("PKT", "PKT")]
        case .wideReceiver:
            return [("RTE", "RTE"), ("CTH", "CTH"), ("RLS", "RLS"), ("SPC", "SPC")]
        case .runningBack:
            return [("VIS", "VIS"), ("ELU", "ELU"), ("BTK", "BTK"), ("RCV", "RCV")]
        case .tightEnd:
            return [("BLK", "BLK"), ("CTH", "CTH"), ("RTE", "RTE"), ("SPD", "SPD")]
        case .offensiveLine:
            return [("RBK", "RBK"), ("PBK", "PBK"), ("PUL", "PUL"), ("ANC", "ANC")]
        case .defensiveLine:
            return [("PRU", "PRU"), ("BSH", "BSH"), ("PWR", "PWR"), ("FIN", "FIN")]
        case .linebacker:
            return [("TAK", "TAK"), ("ZCV", "ZCV"), ("MCV", "MCV"), ("BLZ", "BLZ")]
        case .defensiveBack:
            return [("MCV", "MCV"), ("ZCV", "ZCV"), ("PRS", "PRS"), ("BSK", "BSK")]
        case .kicking:
            return [("PWR", "PWR"), ("ACC", "ACC")]
        }
    }

    // MARK: - Mini Attribute Helpers

    private func boardColorCodedMiniAttribute(value: Int, label: String) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(boardAttributeColor(for: value))
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func boardAttributeColor(for value: Int) -> Color {
        switch value {
        case 90...:   return .accentGold
        case 80..<90: return .success
        case 70..<80: return .accentBlue
        default:      return .warning
        }
    }

    private func boardGradeRangeMiniAttribute(key: String, label: String, grades: [String: GradeRange]?) -> some View {
        VStack(spacing: 0) {
            if let gradeRange = grades?[key] {
                Text(gradeRange.displayText)
                    .font(.system(size: gradeRange.isSingleGrade ? 10 : 8, weight: .bold))
                    .foregroundStyle(boardGradeColor(gradeRange.midGrade))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("?")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func boardGradeColor(_ grade: LetterGrade) -> Color {
        switch grade {
        case .aPlus, .a, .aMinus: return .accentGold     // A range = elite gold
        case .bPlus:              return .success        // B+ = green
        case .b:                  return .yellow         // B = yellow
        case .bMinus, .cPlus:     return .warning        // B-/C+ = orange
        default:                  return .danger         // C and below = red
        }
    }

    // MARK: - Always-Visible Subviews

    private var boardPositionBadge: some View {
        Text(prospect.position.rawValue)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
            .frame(width: 36, height: 24)
            .background(positionColor, in: RoundedRectangle(cornerRadius: 4))
    }

    private var boardOverallBadge: some View {
        Button {
            onGradeTap?()
        } label: {
            Group {
                if let gradeRange = prospect.effectiveOverallGrade {
                    DualGradeDisplay(
                        prospectID: prospect.id,
                        scoutGradeText: gradeRange.displayText,
                        scoutGradeColor: boardGradeColor(gradeRange.midGrade)
                    )
                } else {
                    Text("?")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(width: 50, alignment: .center)
        }
        .buttonStyle(.plain)
    }

    private var boardProjectedRoundBadge: some View {
        let displayRound = projectedRound <= 7 ? projectedRound : nil
        let text = ProspectRowView.projectedRoundText(for: displayRound)
        let color = boardProjectedRoundColorFromRound
        return VStack(spacing: 0) {
            Text(text)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            boardGradeChangeIndicator
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

    // MARK: - Overview-Specific Column Views

    // MARK: - #1: FIT column - text label with color

    @ViewBuilder
    private var boardSchemeFitIcon: some View {
        if let fit = schemeFit {
            let color: Color = fit == "Good" ? .success : (fit == "Fair" ? .warning : .danger)
            Text(fit)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(color)
        } else if prospect.position.side == .specialTeams {
            Text("N/A")
                .font(.system(size: 8))
                .foregroundStyle(Color.textTertiary)
        } else {
            Text("Fair")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.warning)
        }
    }

    // MARK: - #2: NEED column - clearer labels

    @ViewBuilder
    private var boardNeedIndicator: some View {
        let level = needLevel
        switch level {
        case "High":
            Text("High")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.danger)
        case "Med":
            Text("Med")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.warning)
        default:
            Text("Set")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.success)
        }
    }

    // MARK: - #4: RISK badges - larger with background colors

    @ViewBuilder
    private var boardCompactRiskBadge: some View {
        let risk = prospect.riskLevel
        if risk != .unknown {
            let bgColor: Color = {
                switch risk {
                case .boomOrBust:  return .danger
                case .highCeiling: return .accentBlue
                case .safePick:    return .success
                case .unknown:     return .textTertiary
                }
            }()
            HStack(spacing: 2) {
                Image(systemName: risk.icon)
                    .font(.system(size: 8))
                Text(boardCompactRiskLabel(risk))
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(bgColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
        } else {
            Text("--")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func boardCompactRiskLabel(_ risk: ProspectRiskLevel) -> String {
        switch risk {
        case .safePick:    return "Safe"
        case .highCeiling: return "Ceiling"
        case .boomOrBust:  return "Boom/Bust"
        case .unknown:     return "--"
        }
    }

    // MARK: - Grade Change Indicator

    @ViewBuilder
    private var boardGradeChangeIndicator: some View {
        if let preGrade = prospect.preCombineGrade,
           let currentGrade = prospect.scoutGrade,
           preGrade != currentGrade {
            let improved = ProspectRowView.gradeRank(currentGrade) > ProspectRowView.gradeRank(preGrade)
            Text(improved ? "\u{2191}" : "\u{2193}")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(improved ? Color.success : Color.danger)
        }
    }

    // MARK: - Flag Icon (compact inline)

    @ViewBuilder
    private var boardFlagIcon: some View {
        switch prospect.prospectFlag {
        case .none:
            EmptyView()
        case .mustHave:
            Image(systemName: "star.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.accentGold)
        case .sleeper:
            Image(systemName: "eye.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.accentBlue)
        case .avoid:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(Color.danger)
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
        let flag = prospect.prospectFlag == .none ? "" : " \(prospect.prospectFlag.rawValue)"
        return "Rank \(rank), \(prospect.fullName), \(prospect.position.rawValue), \(prospect.college), overall \(overall)\(flag)"
    }

    /// Combine performance color based on physical attributes and drill results (#7)
    private var combinePerformanceColor: Color {
        // If no combine data (no forty time), gray
        guard prospect.fortyTime != nil else { return Color.textTertiary }
        // Use average of physical stats as a proxy for combine performance
        let avg = prospect.truePhysical.average
        if avg >= 80 { return Color.success }       // Strong combine
        if avg >= 65 { return Color.warning }        // Average combine
        return Color.danger                           // Weak combine
    }

    private func boardMediaColor(for prospect: CollegeProspect) -> Color {
        guard let mention = prospect.combineMediaMention else { return Color.textTertiary }
        if mention.contains("Standout") { return Color.success }
        if mention.contains("Riser") { return Color.accentGold }
        if mention.contains("Faller") { return Color.danger }
        if mention.contains("Surprise") { return Color.accentBlue }
        return Color.textSecondary
    }
}

// MARK: - #9: Big Board Sort Enum

enum BigBoardSort: String, CaseIterable, Identifiable {
    case boardRank, overall, position, tier, schemeFit, risk

    var id: String { rawValue }

    var label: String {
        switch self {
        case .boardRank: return "Board Rank"
        case .overall:   return "Overall"
        case .position:  return "Position"
        case .tier:      return "Tier"
        case .schemeFit: return "Scheme Fit"
        case .risk:      return "Risk Level"
        }
    }

    var icon: String {
        switch self {
        case .boardRank: return "list.number"
        case .overall:   return "star.fill"
        case .position:  return "rectangle.3.group"
        case .tier:      return "chart.bar.fill"
        case .schemeFit: return "checkmark.circle"
        case .risk:      return "bolt.fill"
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
            teamRoster: []
        )
    }
}
