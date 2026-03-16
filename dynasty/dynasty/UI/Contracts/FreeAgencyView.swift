import SwiftUI
import SwiftData

// MARK: - Position Filter

private enum FAPositionFilter: String, CaseIterable {
    case all  = "All"
    case qb   = "QB"
    case skill = "Skill"
    case ol   = "OL"
    case dl   = "DL"
    case lb   = "LB"
    case db   = "DB"
    case st   = "ST"

    func matches(_ position: Position) -> Bool {
        switch self {
        case .all:   return true
        case .qb:    return position == .QB
        case .skill: return [.RB, .FB, .WR, .TE].contains(position)
        case .ol:    return [.LT, .LG, .C, .RG, .RT].contains(position)
        case .dl:    return [.DE, .DT].contains(position)
        case .lb:    return [.OLB, .MLB].contains(position)
        case .db:    return [.CB, .FS, .SS].contains(position)
        case .st:    return [.K, .P].contains(position)
        }
    }
}

// MARK: - Sort Option

private enum FASortOption: String, CaseIterable {
    case overall = "Overall"
    case age     = "Age"
    case salary  = "Salary"
}

// MARK: - FreeAgencyView

struct FreeAgencyView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var allFreeAgents: [Player] = []
    @State private var team: Team?
    @State private var positionFilter: FAPositionFilter = .all
    @State private var sortOption: FASortOption = .overall
    @State private var selectedPlayer: Player?
    @State private var showNegotiationSheet = false

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                capBanner
                filterBar
                sortBar
                playerList
            }
        }
        .navigationTitle("Free Agency")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
        .sheet(isPresented: $showNegotiationSheet) {
            if let player = selectedPlayer, let team {
                NavigationStack {
                    ContractExtensionSheet(
                        player: player,
                        team: team,
                        capMode: career.capMode
                    )
                }
            }
        }
    }

    // MARK: - Cap Banner

    private var capBanner: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Available Cap Space")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text(formatMillions(team?.availableCap ?? 0))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle((team?.availableCap ?? 0) >= 0 ? Color.success : Color.danger)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Free Agents")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text("\(filteredAndSorted.count)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FAPositionFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func filterChip(_ filter: FAPositionFilter) -> some View {
        Button {
            positionFilter = filter
        } label: {
            Text(filter.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundStyle(positionFilter == filter ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(positionFilter == filter ? Color.accentGold : Color.backgroundTertiary)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        HStack(spacing: 0) {
            Text("Sort by:")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 24)

            ForEach(FASortOption.allCases, id: \.self) { option in
                Button {
                    sortOption = option
                } label: {
                    Text(option.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(sortOption == option ? Color.accentGold : Color.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Player List

    private var playerList: some View {
        Group {
            if filteredAndSorted.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.textTertiary)
                    Text("No free agents available")
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)
                    Text("Check back after the season ends or adjust your filter.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredAndSorted) { player in
                        Button {
                            selectedPlayer = player
                            showNegotiationSheet = true
                        } label: {
                            freeAgentRow(player)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.backgroundSecondary)
                        .listRowSeparatorTint(Color.surfaceBorder)
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
        }
    }

    private func freeAgentRow(_ player: Player) -> some View {
        HStack(spacing: 12) {
            // Position badge
            Text(player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34)
                .padding(.vertical, 4)
                .background(positionColor(player.position), in: RoundedRectangle(cornerRadius: 4))

            // Name + details
            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("Age \(player.age)")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text("•")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text(player.position.side.rawValue)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            // OVR
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(player.overall)")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(player.overall))
                Text("OVR")
                    .font(.system(size: 9).weight(.medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(minWidth: 40)

            Divider()
                .frame(height: 32)
                .overlay(Color.surfaceBorder)

            // Estimated salary
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatMillions(estimatedMarketValue(for: player)))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
                Text("Est./yr")
                    .font(.system(size: 9).weight(.medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(minWidth: 60)

            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Filtering & Sorting

    private var filteredAndSorted: [Player] {
        let filtered = allFreeAgents.filter { positionFilter.matches($0.position) }
        switch sortOption {
        case .overall:
            return filtered.sorted { $0.overall > $1.overall }
        case .age:
            return filtered.sorted { $0.age < $1.age }
        case .salary:
            return filtered.sorted { estimatedMarketValue(for: $0) > estimatedMarketValue(for: $1) }
        }
    }

    // MARK: - Market Value

    private func estimatedMarketValue(for player: Player) -> Int {
        let base = Double(player.overall) * Double(player.overall) * positionMultiplier(for: player.position)
        return max(500, Int(base))
    }

    private func positionMultiplier(for position: Position) -> Double {
        switch position {
        case .QB:          return 8.0
        case .LT:          return 4.5
        case .WR, .TE:     return 3.5
        case .RB:          return 2.5
        case .DE, .DT:     return 3.5
        case .CB:          return 3.0
        case .OLB, .MLB:   return 2.8
        case .FS, .SS:     return 2.5
        case .FB, .LG, .C, .RG, .RT: return 2.2
        case .K, .P:       return 0.8
        }
    }

    // MARK: - Helpers

    private func loadData() {
        // Load free agents: contractYearsRemaining == 0 and no team
        var descriptor = FetchDescriptor<Player>(
            predicate: #Predicate { $0.contractYearsRemaining == 0 && $0.teamID == nil }
        )
        descriptor.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        allFreeAgents = (try? modelContext.fetch(descriptor)) ?? []

        // Load player's team for cap info
        guard let teamID = career.teamID else { return }
        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDescriptor).first
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FreeAgencyView(career: Career(
            playerName: "Coach",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Player.self, Team.self], inMemory: true)
}
