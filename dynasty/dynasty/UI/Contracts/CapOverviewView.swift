import SwiftUI
import SwiftData

struct CapOverviewView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var players: [Player] = []

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if let team {
                        capSummaryCard(team: team)
                        capBarCard(team: team)
                        contractListCard(team: team)
                    } else {
                        ProgressView()
                            .tint(Color.accentGold)
                            .padding(.top, 80)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Salary Cap")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
    }

    // MARK: - Cap Summary Card

    private func capSummaryCard(team: Team) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text("Cap Summary")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                capStatColumn(
                    label: "Total Cap",
                    value: formatMillions(team.salaryCap),
                    color: .accentGold
                )
                capStatColumn(
                    label: "Used Cap",
                    value: formatMillions(team.currentCapUsage),
                    color: capUsageColor(team: team)
                )
                capStatColumn(
                    label: "Available",
                    value: formatMillions(team.availableCap),
                    color: team.availableCap >= 0 ? .success : .danger
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
    }

    private func capStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 28, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: - Cap Bar Card

    private func capBarCard(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Cap Usage")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(String(format: "%.1f%%", usagePercentage(team: team) * 100))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(capUsageColor(team: team))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 14)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(capBarGradient(team: team))
                        .frame(width: geo.size.width * min(usagePercentage(team: team), 1.0), height: 14)
                        .animation(.easeOut(duration: 0.4), value: team.currentCapUsage)
                }
            }
            .frame(height: 14)
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Contract List Card

    private func contractListCard(team: Team) -> some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                    Text("Player Contracts")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Spacer()
                Text("\(players.count) players")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().overlay(Color.surfaceBorder)
                .padding(.horizontal, 20)

            if players.isEmpty {
                Text("No contracts on file")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .padding(24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        contractRow(player: player)

                        if index < players.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 20)
                        }
                    }
                }

                Divider().overlay(Color.surfaceBorder)
                    .padding(.horizontal, 20)

                // Total row
                HStack {
                    Text("Total")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(formatMillions(players.reduce(0) { $0 + $1.annualSalary }))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private func contractRow(player: Player) -> some View {
        HStack(spacing: 12) {
            // Position badge
            Text(player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34)
                .padding(.vertical, 4)
                .background(positionColor(player.position), in: RoundedRectangle(cornerRadius: 4))

            // Name
            Text(player.fullName)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer()

            // Years remaining
            HStack(spacing: 4) {
                Text("\(player.contractYearsRemaining)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(yearsColor(player.contractYearsRemaining))
                Text("yr\(player.contractYearsRemaining == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            // Salary
            Text(formatMillions(player.annualSalary))
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDescriptor).first

        guard let fetchedTeamID = team?.id else { return }
        var playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == fetchedTeamID })
        playerDescriptor.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        players = (try? modelContext.fetch(playerDescriptor)) ?? []
    }

    private func usagePercentage(team: Team) -> Double {
        guard team.salaryCap > 0 else { return 0 }
        return Double(team.currentCapUsage) / Double(team.salaryCap)
    }

    private func capUsageColor(team: Team) -> Color {
        let pct = usagePercentage(team: team)
        if pct > 1.0 { return .danger }
        if pct > 0.9 { return .warning }
        return .textSecondary
    }

    private func capBarGradient(team: Team) -> LinearGradient {
        let pct = usagePercentage(team: team)
        let color: Color = pct > 1.0 ? .danger : (pct > 0.9 ? .warning : .accentGold)
        return LinearGradient(
            colors: [color.opacity(0.7), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func yearsColor(_ years: Int) -> Color {
        switch years {
        case 3...: return .success
        case 2:    return .accentGold
        case 1:    return .warning
        default:   return .danger
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
        CapOverviewView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Team.self, Player.self], inMemory: true)
}
