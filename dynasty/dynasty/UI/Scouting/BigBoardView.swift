import SwiftUI

struct BigBoardView: View {
    let career: Career
    let prospects: [CollegeProspect]
    let teamRoster: [Player]

    @State private var positionFilter: ProspectPositionFilter = .all
    @State private var flagFilter: ProspectFlagFilter = .all
    @State private var boardOrder: [UUID] = []

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
        return result
    }

    private var orderedBoard: [CollegeProspect] {
        let filtered = filteredProspects
        var orderedIDs = boardOrder.filter { id in filtered.contains { $0.id == id } }
        let unordered = filtered.filter { !orderedIDs.contains($0.id) }.map { $0.id }
        orderedIDs.append(contentsOf: unordered)
        return orderedIDs.compactMap { id in filtered.first { $0.id == id } }
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
                List {
                    recommendationsSection
                    ForEach(tieredBoard, id: \.tier) { tierGroup in
                        Section {
                            ForEach(tierGroup.prospects) { prospect in
                                NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                    BigBoardRowView(
                                        rank: rankFor(prospect),
                                        prospect: prospect,
                                        onFlagToggle: { toggleFlag(prospect) }
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
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .environment(\.editMode, .constant(.active))
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                positionPicker
            }
        }
        .onAppear {
            if boardOrder.isEmpty {
                boardOrder = scoutedProspects
                    .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
                    .map { $0.id }
            }
        }
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

    // MARK: - Helpers

    private func rankFor(_ prospect: CollegeProspect) -> Int {
        if let index = orderedBoard.firstIndex(where: { $0.id == prospect.id }) {
            return index + 1
        }
        return 0
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
    var onFlagToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            // Rank number
            Text("\(rank)")
                .font(.title3.weight(.heavy).monospacedDigit())
                .foregroundStyle(rankColor)
                .frame(width: 32, alignment: .trailing)

            // Flag indicator (#215)
            flagIndicator

            // Position badge
            Text(prospect.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34, height: 26)
                .background(positionColor, in: RoundedRectangle(cornerRadius: 4))

            // Name and college
            VStack(alignment: .leading, spacing: 2) {
                Text(prospect.fullName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 6) {
                    Text(prospect.college)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    if let mockPick = prospect.mockDraftPickNumber,
                       let mockTeam = prospect.mockDraftTeam {
                        Text("Mock: #\(mockPick) \(mockTeam)")
                            .font(.caption2.weight(.medium).monospacedDigit())
                            .foregroundStyle(Color.accentGold)
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
                if let grade = prospect.scoutGrade {
                    Text(grade)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
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
