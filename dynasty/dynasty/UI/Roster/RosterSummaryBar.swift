import SwiftUI

/// Always-visible summary bar at the top of the Roster view showing key team stats.
struct RosterSummaryBar: View {
    let players: [Player]
    /// The team's current salary cap in thousands. Falls back to 255_000 if not provided.
    var teamSalaryCap: Int = 255_000

    private var totalCount: Int { players.count }
    private var healthyCount: Int { players.filter { !$0.isInjured }.count }
    private var injuredCount: Int { players.filter { $0.isInjured }.count }

    private var averageOVR: Int {
        guard !players.isEmpty else { return 0 }
        return players.reduce(0) { $0 + $1.overall } / players.count
    }

    private var totalCapUsed: Int {
        players.reduce(0) { $0 + $1.annualSalary }
    }

    /// Salary cap ceiling in thousands (e.g., 255000 = $255M).
    private var salaryCap: Int { teamSalaryCap }

    private var formattedCapUsed: String {
        let millions = Double(totalCapUsed) / 1000.0
        return String(format: "$%.0fM", millions)
    }

    private var formattedCapTotal: String {
        let millions = Double(salaryCap) / 1000.0
        return String(format: "$%.0fM", millions)
    }

    private var capUsageRatio: Double {
        guard salaryCap > 0 else { return 0 }
        return min(Double(totalCapUsed) / Double(salaryCap), 1.0)
    }

    private var capColor: Color {
        switch capUsageRatio {
        case 0.9...:  return .danger
        case 0.75..<0.9: return .warning
        default:      return .accentGold
        }
    }

    private var rosterStrength: Int {
        switch averageOVR {
        case 80...: return 5
        case 75..<80: return 4
        case 70..<75: return 3
        case 65..<70: return 2
        default: return 1
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            summaryItem(
                label: "Players",
                value: "\(totalCount)",
                color: .textPrimary
            )

            divider

            summaryItem(
                label: "Healthy",
                value: "\(healthyCount)",
                color: .success
            )

            divider

            summaryItem(
                label: "Injured",
                value: "\(injuredCount)",
                color: injuredCount > 0 ? .danger : .textSecondary
            )

            divider

            summaryItem(
                label: "Avg OVR",
                value: "\(averageOVR)",
                color: Color.forRating(averageOVR)
            )

            divider

            // Salary cap with progress bar
            VStack(spacing: 3) {
                HStack(spacing: 0) {
                    Text(formattedCapUsed)
                        .font(.caption)
                        .fontWeight(.bold)
                        .monospacedDigit()
                        .foregroundStyle(capColor)
                    Text(" / ")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Text(formattedCapTotal)
                        .font(.caption)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(Color.textSecondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.backgroundTertiary)
                            .frame(height: 4)
                        Capsule()
                            .fill(capColor)
                            .frame(width: geo.size.width * capUsageRatio, height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 8)

                Text("Salary Cap")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity)

            divider

            // Roster Strength stars
            VStack(spacing: 2) {
                HStack(spacing: 1) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: index < rosterStrength ? "star.fill" : "star")
                            .font(.system(size: 8))
                            .foregroundStyle(index < rosterStrength ? Color.accentGold : Color.textTertiary)
                    }
                }
                Text("Strength")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.surfaceBorder),
            alignment: .bottom
        )
    }

    private func summaryItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.surfaceBorder)
            .frame(width: 1, height: 28)
    }
}

#Preview {
    VStack {
        RosterSummaryBar(players: [
            Player(
                firstName: "Patrick", lastName: "Mahomes", position: .QB,
                age: 28, yearsPro: 7,
                positionAttributes: .quarterback(QBAttributes(
                    armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                    accuracyDeep: 87, pocketPresence: 92, scrambling: 80
                )),
                personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                contractYearsRemaining: 3, annualSalary: 45000
            ),
            Player(
                firstName: "Tyreek", lastName: "Hill", position: .WR,
                age: 29, yearsPro: 8,
                positionAttributes: .wideReceiver(WRAttributes(
                    routeRunning: 88, catching: 90, release: 92, spectacularCatch: 85
                )),
                personality: PlayerPersonality(archetype: .loneWolf, motivation: .stats),
                isInjured: true, injuryWeeksRemaining: 3
            ),
        ])
        Spacer()
    }
    .background(Color.backgroundPrimary)
}
