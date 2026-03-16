import SwiftUI

struct PlayerRowView: View {
    let player: Player

    var body: some View {
        HStack(spacing: 12) {
            positionBadge

            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)

                Text(experienceLabel)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            if player.isInjured {
                Image(systemName: "cross.circle.fill")
                    .foregroundStyle(Color.danger)
                    .font(.caption)
                    .accessibilityLabel("Injured")
            }

            overallBadge
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(player.fullName), \(player.position.rawValue), overall \(player.overall)\(player.isInjured ? ", injured" : "")")
    }

    // MARK: - Subviews

    private var positionBadge: some View {
        Text(player.position.rawValue)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(Color.textPrimary)
            .frame(width: 36, height: 28)
            .background(positionColor, in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("\(player.position.rawValue), \(player.position.side.rawValue)")
    }

    private var overallBadge: some View {
        Text("\(player.overall)")
            .font(.callout.monospacedDigit())
            .fontWeight(.bold)
            .foregroundStyle(Color.forRating(player.overall))
            .frame(width: 36, alignment: .trailing)
            .accessibilityLabel("Overall rating \(player.overall)")
    }

    // MARK: - Helpers

    private var positionColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var experienceLabel: String {
        let expText = player.yearsPro == 0 ? "Rookie" : "\(player.yearsPro)yr pro"
        return "Age \(player.age)  |  \(expText)"
    }
}

// MARK: - Overall Color Helper (package-level for reuse)

func overallColor(for value: Int) -> Color {
    Color.forRating(value)
}

// MARK: - Preview

#Preview {
    List {
        PlayerRowView(player: Player(
            firstName: "Patrick",
            lastName: "Mahomes",
            position: .QB,
            age: 28,
            yearsPro: 7,
            positionAttributes: .quarterback(QBAttributes(
                armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                accuracyDeep: 87, pocketPresence: 92, scrambling: 80
            )),
            personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
            morale: 85
        ))
        PlayerRowView(player: Player(
            firstName: "Tyreek",
            lastName: "Hill",
            position: .WR,
            age: 29,
            yearsPro: 8,
            positionAttributes: .wideReceiver(WRAttributes(
                routeRunning: 88, catching: 90, release: 92, spectacularCatch: 85
            )),
            personality: PlayerPersonality(archetype: .loneWolf, motivation: .stats),
            isInjured: true
        ))
        PlayerRowView(player: Player(
            firstName: "Myles",
            lastName: "Garrett",
            position: .DE,
            age: 28,
            yearsPro: 7,
            positionAttributes: .defensiveLine(DLAttributes(
                passRush: 96, blockShedding: 90, powerMoves: 88, finesseMoves: 91
            )),
            personality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning)
        ))
        PlayerRowView(player: Player(
            firstName: "Justin",
            lastName: "Tucker",
            position: .K,
            age: 34,
            yearsPro: 12,
            positionAttributes: .kicking(KickingAttributes(kickPower: 95, kickAccuracy: 98)),
            personality: PlayerPersonality(archetype: .steadyPerformer, motivation: .loyalty)
        ))
    }
}
