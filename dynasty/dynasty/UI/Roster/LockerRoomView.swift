import SwiftUI
import SwiftData

struct LockerRoomView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @State private var players: [Player] = []
    @State private var lockerRoomState: LockerRoomState?

    // MARK: - Computed

    private var chemistry: Int {
        lockerRoomState?.teamChemistry ?? 50
    }

    private var leaders: [Player] {
        players
            .filter {
                $0.personality.archetype == .teamLeader ||
                $0.personality.archetype == .mentor ||
                ($0.personality.archetype == .feelPlayer && $0.morale >= 75)
            }
            .sorted { $0.morale > $1.morale }
            .prefix(5)
            .map { $0 }
    }

    private var risks: [Player] {
        players
            .filter {
                ($0.personality.archetype == .dramaQueen ||
                 $0.personality.archetype == .fieryCompetitor) && $0.morale < 50
                || ($0.personality.archetype == .feelPlayer && $0.morale < 45)
            }
            .sorted { $0.morale < $1.morale }
            .prefix(5)
            .map { $0 }
    }

    private var highMorale: Int  { players.filter { LockerRoomEngine.moraleTier($0.morale) == .high }.count }
    private var medMorale: Int   { players.filter { LockerRoomEngine.moraleTier($0.morale) == .medium }.count }
    private var lowMorale: Int   { players.filter { LockerRoomEngine.moraleTier($0.morale) == .low }.count }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    chemistryCard
                    moraleDistributionCard
                    leadersCard
                    risksCard
                    eventsCard
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Locker Room")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
    }

    // MARK: - Chemistry Card

    private var chemistryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "heart.fill")
                    .foregroundStyle(chemistryColor(chemistry))
                Text("Team Chemistry")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(LockerRoomEngine.chemistryLabel(chemistry))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(chemistryColor(chemistry))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 16)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(chemistryColor(chemistry))
                        .frame(width: geo.size.width * CGFloat(chemistry) / 100.0, height: 16)
                        .animation(.easeInOut(duration: 0.5), value: chemistry)
                }
            }
            .frame(height: 16)

            HStack {
                Text("0")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text("\(chemistry) / 100")
                    .font(.caption.weight(.medium).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("100")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }

            if let state = lockerRoomState {
                Divider().overlay(Color.surfaceBorder)

                HStack(spacing: 0) {
                    chemStatColumn(
                        label: "Leadership",
                        value: "+\(state.leadershipScore)",
                        color: Color.success
                    )
                    chemStatColumn(
                        label: "Toxicity",
                        value: "-\(state.toxicityScore)",
                        color: Color.danger
                    )
                    chemStatColumn(
                        label: "Net",
                        value: "\(state.leadershipScore - state.toxicityScore > 0 ? "+" : "")\(state.leadershipScore - state.toxicityScore)",
                        color: state.leadershipScore >= state.toxicityScore ? Color.success : Color.danger
                    )
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func chemStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Morale Distribution Card

    private var moraleDistributionCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Morale Distribution")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(players.count) players")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                moraleColumn(
                    label: "High",
                    count: highMorale,
                    total: max(players.count, 1),
                    color: Color.success,
                    icon: "arrow.up.circle.fill"
                )
                moraleColumn(
                    label: "Medium",
                    count: medMorale,
                    total: max(players.count, 1),
                    color: Color.warning,
                    icon: "minus.circle.fill"
                )
                moraleColumn(
                    label: "Low",
                    count: lowMorale,
                    total: max(players.count, 1),
                    color: Color.danger,
                    icon: "arrow.down.circle.fill"
                )
            }

            // Stacked bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    let total = max(players.count, 1)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.success)
                        .frame(width: geo.size.width * CGFloat(highMorale) / CGFloat(total))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.warning)
                        .frame(width: geo.size.width * CGFloat(medMorale) / CGFloat(total))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.danger)
                        .frame(width: geo.size.width * CGFloat(lowMorale) / CGFloat(total))
                }
                .frame(height: 10)
            }
            .frame(height: 10)
        }
        .padding(20)
        .cardBackground()
    }

    private func moraleColumn(label: String, count: Int, total: Int, color: Color, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text("\(count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
            Text("\(total > 0 ? Int(Double(count) / Double(total) * 100) : 0)%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Leaders Card

    private var leadersCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Chemistry Leaders")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            if leaders.isEmpty {
                Text("No standout chemistry leaders right now.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(leaders) { player in
                    playerChemistryRow(player: player, isPositive: true)
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Risks Card

    private var risksCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.danger)
                Text("Chemistry Risks")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            if risks.isEmpty {
                Text("No active chemistry risks detected.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(risks) { player in
                    playerChemistryRow(player: player, isPositive: false)
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func playerChemistryRow(player: Player, isPositive: Bool) -> some View {
        HStack(spacing: 12) {
            // Morale indicator dot
            Circle()
                .fill(moraleColor(player.morale))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 6) {
                    Text(player.position.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.accentGold)
                    Text("·")
                        .foregroundStyle(Color.textTertiary)
                    Text(player.personality.archetype.displayName)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Morale \(player.morale)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(moraleColor(player.morale))
                Text(player.personality.motivation.rawValue)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Events Log Card

    private var eventsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "text.bubble.fill")
                    .foregroundStyle(Color.accentBlue)
                Text("Recent Events")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }

            Divider().overlay(Color.surfaceBorder)

            let events = lockerRoomState?.recentEvents ?? []
            if events.isEmpty {
                Text("Nothing notable happening in the locker room.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
            } else {
                ForEach(events.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.accentBlue.opacity(0.6))
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(events[index])
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if index < events.count - 1 {
                        Divider().overlay(Color.surfaceBorder.opacity(0.5))
                    }
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Helpers

    private func chemistryColor(_ value: Int) -> Color {
        switch value {
        case 75...100: return Color.success
        case 55..<75:  return Color.accentGold
        case 40..<55:  return Color.warning
        default:       return Color.danger
        }
    }

    private func moraleColor(_ value: Int) -> Color {
        switch value {
        case 75...100: return Color.success
        case 45..<75:  return Color.warning
        default:       return Color.danger
        }
    }

    private func loadData() {
        guard let teamID = career.teamID else { return }
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        players = (try? modelContext.fetch(descriptor)) ?? []
        lockerRoomState = LockerRoomEngine.calculateChemistry(players: players)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LockerRoomView(career: Career(
            playerName: "Coach Smith",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Player.self], inMemory: true)
}
