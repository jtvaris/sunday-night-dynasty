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

    private static let tierNames = ["Blue Chip", "First Rounder", "Day Two", "Day Three", "Priority FA", "Draftable"]
    private static let tierColors: [Color] = [.accentGold, .success, .accentBlue, .textSecondary, .textTertiary, .textTertiary]

    // MARK: - Board Prospects

    private var scoutedProspects: [CollegeProspect] {
        prospects.filter { $0.scoutedOverall != nil }
    }

    private var filteredProspects: [CollegeProspect] {
        var result = scoutedProspects
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
        return result
    }

    private var orderedBoard: [CollegeProspect] {
        let filtered = filteredProspects
        var orderedIDs = boardOrder.filter { id in filtered.contains { $0.id == id } }
        let unordered = filtered.filter { !orderedIDs.contains($0.id) }.map { $0.id }
        orderedIDs.append(contentsOf: unordered)
        return orderedIDs.compactMap { id in filtered.first { $0.id == id } }
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

    /// Prospects grouped by tier, maintaining board order within each tier.
    private var tieredBoard: [(tier: Int, prospects: [CollegeProspect])] {
        let board = orderedBoard
        var grouped: [Int: [CollegeProspect]] = [:]
        for prospect in board {
            grouped[prospect.scoutedTier, default: []].append(prospect)
        }
        return (1...6).compactMap { tier in
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

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if scoutedProspects.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
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
                                ForEach(customOrderedBoard) { prospect in
                                    NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                        BigBoardRowView(
                                            rank: customRankFor(prospect),
                                            prospect: prospect,
                                            ownGrade: prospectOwnAssessments[prospect.id.uuidString],
                                            isWatchlisted: isOnWatchlist(prospect.id),
                                            schemeFit: schemeFitLabel(for: prospect),
                                            starterComparison: starterComparison(for: prospect),
                                            attributeTab: attributeTab,
                                            scoutsSentToCombine: scoutsSentToCombine,
                                            isPositionNeed: teamNeedPositions.contains(prospect.position),
                                            onFlagToggle: { toggleFlag(prospect) },
                                            onWatchlistToggle: { toggleWatchlist(prospectID: prospect.id) },
                                            onGradeTap: { editingAssessmentProspect = prospect }
                                        )
                                    }
                                    .listRowBackground(Color.backgroundSecondary)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                                    .contextMenu {
                                        tierContextMenu(for: prospect)
                                    }
                                }
                                .onMove { from, to in
                                    moveCustomBoard(from: from, to: to)
                                }
                            } header: {
                                Label("My Board (\(customOrderedBoard.count))", systemImage: "person.fill")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.accentGold)
                                    .textCase(nil)
                            }
                        } else {
                            // Staff tiered board
                            ForEach(tieredBoard, id: \.tier) { tierGroup in
                                Section {
                                    ForEach(tierGroup.prospects) { prospect in
                                        NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                            BigBoardRowView(
                                                rank: rankFor(prospect),
                                                prospect: prospect,
                                                ownGrade: prospectOwnAssessments[prospect.id.uuidString],
                                                isWatchlisted: isOnWatchlist(prospect.id),
                                                schemeFit: schemeFitLabel(for: prospect),
                                                starterComparison: starterComparison(for: prospect),
                                                attributeTab: attributeTab,
                                                scoutsSentToCombine: scoutsSentToCombine,
                                                isPositionNeed: teamNeedPositions.contains(prospect.position),
                                                onFlagToggle: { toggleFlag(prospect) },
                                                onWatchlistToggle: { toggleWatchlist(prospectID: prospect.id) },
                                                onGradeTap: { editingAssessmentProspect = prospect }
                                            )
                                        }
                                        .listRowBackground(Color.backgroundSecondary)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
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
        .toolbar {
            ToolbarItem(placement: .principal) {
                positionPicker
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showMyBoard.toggle()
                } label: {
                    Text(showMyBoard ? "My Board" : "Staff Board")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(showMyBoard ? Color.accentGold : Color.textSecondary)
                }
            }
        }
        .onAppear {
            if boardOrder.isEmpty {
                boardOrder = scoutedProspects
                    .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
                    .map { $0.id }
            }
            loadCoaches()
            loadDraftPicks()
        }
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
                            attributeTab == tab ? Color.accentGold : Color.backgroundTertiary,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    attributeTab == tab ? Color.accentGold : Color.surfaceBorder,
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

            // Always-visible: OVR
            Text("OVR")
                .frame(width: 34, alignment: .center)

            // Always-visible: Proj Rd (overview) or Grade (others)
            if attributeTab == .overview {
                Text("PROJ")
                    .frame(width: 52, alignment: .center)
            } else {
                Text("GRD")
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
                .frame(width: 28, alignment: .center)
            Text("NEED")
                .frame(width: 28, alignment: .center)
            Text("RISK")
                .frame(width: 52, alignment: .center)
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
                .foregroundStyle(Color.accentGold)
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
                    Text("Staff: Need \(teamNeeds.prefix(3).map { $0.rawValue }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                    if userPriorityPositions.isEmpty {
                        Text("You: Set your priorities in Roster Evaluation")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Text("You: Priority \(userPriorityPositions.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Color.accentGold)
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
                            .foregroundStyle(Color.accentGold)
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

            // Your #1 vs Media #1 comparison
            if let myTop = orderedBoard.first, let mediaTop = mediaTopProspect {
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
        HStack(spacing: 8) {
            Circle()
                .fill(Self.tierColors[tier - 1])
                .frame(width: 10, height: 10)

            Text(Self.tierNames[tier - 1])
                .font(.caption.weight(.bold))
                .foregroundStyle(Self.tierColors[tier - 1])
                .textCase(nil)

            Text("\(count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.backgroundSecondary, in: Capsule())
        }
    }

    // MARK: - Tier Context Menu (#214)

    @ViewBuilder
    private func tierContextMenu(for prospect: CollegeProspect) -> some View {
        // Tier movement
        ForEach(1...6, id: \.self) { tier in
            if tier != prospect.scoutedTier {
                Button {
                    moveProspectToTier(prospect, tier: tier)
                } label: {
                    Label("Move to \(Self.tierNames[tier - 1])", systemImage: "arrow.right.circle")
                }
            }
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
                                        .fill(isSelected ? Color.accentGold : Color.backgroundTertiary)
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
        let currentGrade = prospectOwnAssessments[prospect.id.uuidString] ?? "none"
        return NavigationStack {
            VStack(spacing: 20) {
                Text(prospect.fullName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                if let staffGrade = prospect.scoutGrade {
                    Text("Staff Grade: \(staffGrade)")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }

                Text("Your Assessment")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 10) {
                    ForEach(Self.gradeOptions, id: \.self) { grade in
                        let isSelected = currentGrade == grade
                        let displayLabel = grade == "none" ? "None" : grade
                        Button {
                            saveOwnAssessment(prospectID: prospect.id, grade: grade)
                            editingAssessmentProspect = nil
                        } label: {
                            Text(displayLabel)
                                .font(.callout.weight(isSelected ? .bold : .regular))
                                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(isSelected ? Color.accentGold : Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 8))
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

    // MARK: - Helpers

    private func rankFor(_ prospect: CollegeProspect) -> Int {
        if let index = orderedBoard.firstIndex(where: { $0.id == prospect.id }) {
            return index + 1
        }
        return 0
    }

    private func customRankFor(_ prospect: CollegeProspect) -> Int {
        if let index = customOrderedBoard.firstIndex(where: { $0.id == prospect.id }) {
            return index + 1
        }
        return 0
    }

    private func moveCustomBoard(from: IndexSet, to: Int) {
        var list = customOrderedBoard.map { $0.id }
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
        let tierProspects = tieredBoard.first(where: { $0.tier == tier })?.prospects ?? []
        var tierIDs = tierProspects.map { $0.id }
        tierIDs.move(fromOffsets: from, toOffset: to)

        // Rebuild full board order: replace the tier slice with the reordered IDs.
        var fullOrder = boardOrder
        let oldTierIDs = Set(tierProspects.map { $0.id })
        fullOrder.removeAll { oldTierIDs.contains($0) }

        // Find insertion point: after the last ID from the previous tier.
        let previousTierIDs = tieredBoard
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
    let prospect: CollegeProspect
    var ownGrade: String? = nil
    var isWatchlisted: Bool = false
    var schemeFit: String? = nil
    var starterComparison: String? = nil
    var attributeTab: ProspectAttributeTab = .overview
    var scoutsSentToCombine: Bool = false
    var isPositionNeed: Bool = false
    var onFlagToggle: (() -> Void)? = nil
    var onWatchlistToggle: (() -> Void)? = nil
    var onGradeTap: (() -> Void)? = nil

    private var isScouted: Bool { prospect.scoutedOverall != nil }

    var body: some View {
        HStack(spacing: 0) {
            // Rank number
            Text("\(rank)")
                .font(.caption.weight(.heavy).monospacedDigit())
                .foregroundStyle(rankColor)
                .frame(width: 28, alignment: .center)

            // Position badge
            boardPositionBadge

            // Name column (compact)
            VStack(alignment: .leading, spacing: 1) {
                Text(prospect.fullName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                // Compact sub-info icons
                HStack(spacing: 4) {
                    // Flag indicator (inline)
                    boardFlagIcon

                    // Watchlist indicator
                    if isWatchlisted {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(Color.accentGold)
                    }

                    if prospect.combineInvite {
                        Text("CMB")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 2))
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
                .frame(width: 28, alignment: .center)

            // Need indicator
            boardNeedIndicator
                .frame(width: 28, alignment: .center)

            // Risk label
            boardCompactRiskBadge
                .frame(width: 52, alignment: .center)
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
        switch grade.rank {
        case 10...12: return .success      // A range
        case 7...9:   return .accentGold   // B range
        case 4...6:   return .warning      // C range
        case 2...3:   return .danger       // D range
        default:      return .danger       // F
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
                    Text(gradeRange.displayText)
                        .font(.system(size: gradeRange.isSingleGrade ? 14 : 11, weight: .bold))
                        .foregroundStyle(boardGradeColor(gradeRange.midGrade))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("?")
                        .font(.callout.weight(.bold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(width: 34, alignment: .center)
        }
        .buttonStyle(.plain)
    }

    private var boardProjectedRoundBadge: some View {
        let text = ProspectRowView.projectedRoundText(for: prospect.draftProjection)
        let color = boardProjectedRoundColor
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

    private var boardGradeColumn: some View {
        VStack(spacing: 0) {
            if let grade = prospect.scoutGrade {
                Text(grade)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.accentGold)
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

    @ViewBuilder
    private var boardSchemeFitIcon: some View {
        if let fit = schemeFit {
            let isGood = fit == "Good"
            let color: Color = isGood ? .success : (fit == "Fair" ? .warning : .danger)
            let icon = isGood ? "checkmark.circle.fill" : (fit == "Fair" ? "minus.circle.fill" : "xmark.circle.fill")
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
        } else {
            Text("--")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
    }

    @ViewBuilder
    private var boardNeedIndicator: some View {
        if isPositionNeed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentGold)
        } else {
            Text("")
                .font(.system(size: 9))
        }
    }

    @ViewBuilder
    private var boardCompactRiskBadge: some View {
        let risk = prospect.riskLevel
        if risk != .unknown {
            HStack(spacing: 2) {
                Image(systemName: risk.icon)
                    .font(.system(size: 7))
                Text(boardCompactRiskLabel(risk))
                    .font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(risk.color)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(risk.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
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

    private var positionColor: Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var boardProjectedRoundColor: Color {
        switch prospect.draftProjection {
        case .some(1):    return .accentGold
        case .some(2):    return .accentGold.opacity(0.8)
        case .some(3):    return .accentBlue
        case .some(4):    return .accentBlue.opacity(0.7)
        case .some(5...6): return .textSecondary
        default:           return .textTertiary
        }
    }

    private var accessibilityDescription: String {
        let overall = prospect.overallGradeDisplay
        let flag = prospect.prospectFlag == .none ? "" : " \(prospect.prospectFlag.rawValue)"
        return "Rank \(rank), \(prospect.fullName), \(prospect.position.rawValue), \(prospect.college), overall \(overall)\(flag)"
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
