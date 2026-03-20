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
        DraftEngine.topTeamNeeds(roster: teamRoster, limit: 5)
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

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if scoutedProspects.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    bigBoardAttributeTabPicker
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
                                            onFlagToggle: { toggleFlag(prospect) },
                                            onWatchlistToggle: { toggleWatchlist(prospectID: prospect.id) },
                                            onGradeTap: { editingAssessmentProspect = prospect }
                                        )
                                    }
                                    .listRowBackground(Color.backgroundSecondary)
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
                                                onFlagToggle: { toggleFlag(prospect) },
                                                onWatchlistToggle: { toggleWatchlist(prospectID: prospect.id) },
                                                onGradeTap: { editingAssessmentProspect = prospect }
                                            )
                                        }
                                        .listRowBackground(Color.backgroundSecondary)
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
                    .environment(\.editMode, .constant(.active))
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
        }
    }

    // MARK: - Attribute Tab Picker

    private var bigBoardAttributeTabPicker: some View {
        Picker("Attributes", selection: $attributeTab) {
            ForEach(ProspectAttributeTab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.backgroundPrimary)
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
        ForEach(1...6, id: \.self) { tier in
            if tier != prospect.scoutedTier {
                Button {
                    moveProspectToTier(prospect, tier: tier)
                } label: {
                    Label("Move to \(Self.tierNames[tier - 1])", systemImage: "arrow.right.circle")
                }
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
            Picker("Position", selection: $positionFilter) {
                ForEach(ProspectPositionFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 380)

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

    /// Move prospect to a different tier by adjusting scoutedOverall to land in the target tier.
    private func moveProspectToTier(_ prospect: CollegeProspect, tier: Int) {
        let targetOverall: Int
        switch tier {
        case 1: targetOverall = 85
        case 2: targetOverall = 75
        case 3: targetOverall = 65
        case 4: targetOverall = 55
        case 5: targetOverall = 45
        default: targetOverall = 40
        }
        prospect.scoutedOverall = targetOverall
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

// MARK: - Big Board Row View

struct BigBoardRowView: View {
    let rank: Int
    let prospect: CollegeProspect
    var ownGrade: String? = nil
    var isWatchlisted: Bool = false
    var schemeFit: String? = nil
    var starterComparison: String? = nil
    var attributeTab: ProspectAttributeTab = .overview
    var scoutsSentToCombine: Bool = false
    var onFlagToggle: (() -> Void)? = nil
    var onWatchlistToggle: (() -> Void)? = nil
    var onGradeTap: (() -> Void)? = nil

    @State private var showMediaPopover = false

    var body: some View {
        HStack(spacing: 14) {
            // Rank number
            Text("\(rank)")
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(rankColor)
                .frame(width: 32, alignment: .trailing)

            // Flag indicator (#215)
            flagIndicator

            // Watchlist bookmark
            Button {
                onWatchlistToggle?()
            } label: {
                Image(systemName: isWatchlisted ? "bookmark.fill" : "bookmark")
                    .font(.caption2)
                    .foregroundStyle(isWatchlisted ? Color.accentGold : Color.textTertiary.opacity(0.4))
            }
            .buttonStyle(.plain)
            .frame(width: 18)

            // Position badge
            Text(prospect.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34, height: 26)
                .background(positionColor, in: RoundedRectangle(cornerRadius: 4))

            // Name and college
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(prospect.fullName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    if prospect.combineMediaMention != nil {
                        Button {
                            showMediaPopover.toggle()
                        } label: {
                            Text("\u{1F4F0}")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showMediaPopover) {
                            if let mention = prospect.combineMediaMention {
                                VStack(alignment: .leading, spacing: 6) {
                                    Label("Combine Media", systemImage: "newspaper.fill")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.accentGold)
                                    Text(mention)
                                        .font(.subheadline)
                                        .foregroundStyle(Color.textPrimary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(12)
                                .frame(maxWidth: 320)
                                .background(Color.backgroundSecondary)
                            }
                        }
                    }
                }
                // Combine stats badges
                if scoutsSentToCombine && prospect.combineInvite {
                    boardCombineStatsBadges
                }

                boardAttributeRow

                HStack(spacing: 6) {
                    if let mockPick = prospect.mockDraftPickNumber,
                       let mockTeam = prospect.mockDraftTeam {
                        Text("Mock: #\(mockPick) \(mockTeam)")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(Color.accentGold)
                    }

                    if prospect.riskLevel != .unknown {
                        HStack(spacing: 2) {
                            Image(systemName: prospect.riskLevel.icon)
                                .font(.system(size: 7))
                            Text(prospect.riskLevel.rawValue)
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(prospect.riskLevel.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(prospect.riskLevel.color.opacity(0.15), in: Capsule())
                    }
                    if let fit = schemeFit {
                        schemeFitBadgeView(fit)
                    }
                    if let comp = starterComparison {
                        Text(comp)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(comp.contains("+") ? Color.success : Color.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background((comp.contains("+") ? Color.success : Color.textSecondary).opacity(0.1), in: Capsule())
                    }
                }
            }

            Spacer()

            // Interest indicator
            if prospect.interestLevel != "Unknown" {
                interestIcon
            }

            // Grade and overall
            VStack(alignment: .trailing, spacing: 3) {
                if let overall = prospect.scoutedOverall {
                    Text("\(overall)")
                        .font(.callout.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(overall))
                }
                HStack(spacing: 6) {
                    if let grade = prospect.scoutGrade {
                        Text("Staff: \(grade)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentGold)
                    }
                    boardGradeChangeIndicator
                    if let userGrade = ownGrade {
                        Text("You: \(userGrade)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentBlue)
                    }
                }
            }
            .onTapGesture {
                onGradeTap?()
            }

            // Drag handle (shown because editMode is active)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(Color.textTertiary)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Attribute Row (Tab-dependent)

    @ViewBuilder
    private var boardAttributeRow: some View {
        switch attributeTab {
        case .overview:
            HStack(spacing: 6) {
                Text(prospect.college)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        case .physical:
            HStack(spacing: 8) {
                if let forty = prospect.fortyTime {
                    ProspectStatPill(label: "40yd", value: String(format: "%.2fs", forty))
                }
                if let bench = prospect.benchPress {
                    ProspectStatPill(label: "Bench", value: "\(bench)")
                }
                if let vert = prospect.verticalJump {
                    ProspectStatPill(label: "Vert", value: String(format: "%.1f\"", vert))
                }
                if let broad = prospect.broadJump {
                    ProspectStatPill(label: "Broad", value: "\(broad)\"")
                }
                if let cone = prospect.coneDrill {
                    ProspectStatPill(label: "3-Cone", value: String(format: "%.2fs", cone))
                }
                if let shuttle = prospect.shuttleTime {
                    ProspectStatPill(label: "Shuttle", value: String(format: "%.2fs", shuttle))
                }
                if prospect.fortyTime == nil && prospect.benchPress == nil {
                    Text("No combine data")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        case .mental:
            HStack(spacing: 8) {
                if prospect.scoutedOverall != nil {
                    ProspectStatPill(label: "AWR", value: "\(prospect.trueMental.awareness)")
                    ProspectStatPill(label: "DEC", value: "\(prospect.trueMental.decisionMaking)")
                    ProspectStatPill(label: "WRK", value: "\(prospect.trueMental.workEthic)")
                    ProspectStatPill(label: "CLT", value: "\(prospect.trueMental.clutch)")
                    ProspectStatPill(label: "COA", value: "\(prospect.trueMental.coachability)")
                    ProspectStatPill(label: "LDR", value: "\(prospect.trueMental.leadership)")
                } else {
                    Text("Scout to reveal")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        case .position:
            if prospect.scoutedOverall != nil {
                HStack(spacing: 8) {
                    switch prospect.truePositionAttributes {
                    case .quarterback(let a):
                        ProspectStatPill(label: "ARM", value: "\(a.armStrength)")
                        ProspectStatPill(label: "SAcc", value: "\(a.accuracyShort)")
                        ProspectStatPill(label: "MAcc", value: "\(a.accuracyMid)")
                        ProspectStatPill(label: "DAcc", value: "\(a.accuracyDeep)")
                        ProspectStatPill(label: "PKT", value: "\(a.pocketPresence)")
                    case .wideReceiver(let a):
                        ProspectStatPill(label: "RTE", value: "\(a.routeRunning)")
                        ProspectStatPill(label: "CTH", value: "\(a.catching)")
                        ProspectStatPill(label: "RLS", value: "\(a.release)")
                        ProspectStatPill(label: "SPC", value: "\(a.spectacularCatch)")
                    case .runningBack(let a):
                        ProspectStatPill(label: "VIS", value: "\(a.vision)")
                        ProspectStatPill(label: "ELU", value: "\(a.elusiveness)")
                        ProspectStatPill(label: "BTK", value: "\(a.breakTackle)")
                        ProspectStatPill(label: "RCV", value: "\(a.receiving)")
                    case .tightEnd(let a):
                        ProspectStatPill(label: "BLK", value: "\(a.blocking)")
                        ProspectStatPill(label: "CTH", value: "\(a.catching)")
                        ProspectStatPill(label: "RTE", value: "\(a.routeRunning)")
                        ProspectStatPill(label: "SPD", value: "\(a.speed)")
                    case .offensiveLine(let a):
                        ProspectStatPill(label: "RBK", value: "\(a.runBlock)")
                        ProspectStatPill(label: "PBK", value: "\(a.passBlock)")
                        ProspectStatPill(label: "PUL", value: "\(a.pull)")
                        ProspectStatPill(label: "ANC", value: "\(a.anchor)")
                    case .defensiveLine(let a):
                        ProspectStatPill(label: "PRU", value: "\(a.passRush)")
                        ProspectStatPill(label: "BSH", value: "\(a.blockShedding)")
                        ProspectStatPill(label: "PWR", value: "\(a.powerMoves)")
                        ProspectStatPill(label: "FIN", value: "\(a.finesseMoves)")
                    case .linebacker(let a):
                        ProspectStatPill(label: "TAK", value: "\(a.tackling)")
                        ProspectStatPill(label: "ZCV", value: "\(a.zoneCoverage)")
                        ProspectStatPill(label: "MCV", value: "\(a.manCoverage)")
                        ProspectStatPill(label: "BLZ", value: "\(a.blitzing)")
                    case .defensiveBack(let a):
                        ProspectStatPill(label: "MCV", value: "\(a.manCoverage)")
                        ProspectStatPill(label: "ZCV", value: "\(a.zoneCoverage)")
                        ProspectStatPill(label: "PRS", value: "\(a.press)")
                        ProspectStatPill(label: "BSK", value: "\(a.ballSkills)")
                    case .kicking(let a):
                        ProspectStatPill(label: "PWR", value: "\(a.kickPower)")
                        ProspectStatPill(label: "ACC", value: "\(a.kickAccuracy)")
                    }
                }
            } else {
                Text("Scout to reveal")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Combine Stats Badges

    @ViewBuilder
    private var boardCombineStatsBadges: some View {
        var parts: [String] = []
        if let forty = prospect.fortyTime {
            let _ = parts.append(String(format: "%.2fs", forty))
        }
        if let bench = prospect.benchPress {
            let _ = parts.append("\(bench) bench")
        }
        if let vert = prospect.verticalJump {
            let _ = parts.append(String(format: "%.0f\" vert", vert))
        }
        if !parts.isEmpty {
            Text(parts.joined(separator: " | "))
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.accentBlue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
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
                .font(.caption.weight(.bold))
                .foregroundStyle(improved ? Color.success : Color.danger)
        }
    }

    // MARK: - Flag Indicator (#215)

    @ViewBuilder
    private var flagIndicator: some View {
        Button {
            onFlagToggle?()
        } label: {
            switch prospect.prospectFlag {
            case .none:
                Image(systemName: "flag")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            case .mustHave:
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentGold)
            case .sleeper:
                Image(systemName: "eye.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentBlue)
            case .avoid:
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.danger)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 20)
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

    private var interestIcon: some View {
        let level = prospect.interestLevel
        let icon: String
        let color: Color
        switch level {
        case "Hot":
            icon = "flame.fill"
            color = .danger
        case "Warm":
            icon = "thermometer.medium"
            color = .warning
        case "Cold":
            icon = "thermometer.snowflake"
            color = .accentBlue
        default:
            icon = "questionmark.circle"
            color = .textTertiary
        }
        return Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func schemeFitBadgeView(_ fit: String) -> some View {
        let isGood = fit == "Good"
        let badgeColor: Color = isGood ? .success : (fit == "Fair" ? .warning : .danger)
        let badgeIcon = isGood ? "checkmark.circle.fill" : (fit == "Fair" ? "minus.circle.fill" : "xmark.circle.fill")
        return HStack(spacing: 2) {
            Image(systemName: badgeIcon)
                .font(.system(size: 7))
            Text(isGood ? "Scheme Fit" : (fit == "Fair" ? "Scheme OK" : "Mismatch"))
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(badgeColor.opacity(0.15), in: Capsule())
    }

    private var accessibilityDescription: String {
        let overall = prospect.scoutedOverall.map { "\($0)" } ?? "ungraded"
        let flag = prospect.prospectFlag == .none ? "" : " \(prospect.prospectFlag.rawValue)"
        return "Rank \(rank), \(prospect.fullName), \(prospect.position.rawValue), \(prospect.college), overall \(overall)\(flag)"
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
