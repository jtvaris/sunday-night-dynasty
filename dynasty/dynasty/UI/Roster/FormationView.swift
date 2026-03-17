import SwiftUI

/// Visual football formation layout showing players at their approximate field positions.
struct FormationView: View {
    let title: String
    let players: [Player]
    let layout: FormationLayout

    var body: some View {
        VStack(spacing: 0) {
            // Section title
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(players.count) players")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // Formation field
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = layout.fieldHeight

                ZStack {
                    // Field background
                    fieldBackground(width: width, height: height)

                    // Player cards at positions
                    ForEach(layout.slots) { slot in
                        let positionPlayers = players
                            .filter { $0.position == slot.position }
                            .sorted { $0.overall > $1.overall }

                        if let starter = positionPlayers.first {
                            let x = slot.xPercent * width
                            let y = slot.yPercent * height

                            NavigationLink(destination: PlayerDetailView(player: starter)) {
                                FormationPlayerCard(
                                    player: starter,
                                    isStarter: true,
                                    backupCount: positionPlayers.count - 1
                                )
                            }
                            .position(x: x, y: y)
                        }
                    }
                }
                .frame(height: height)
            }
            .frame(height: layout.fieldHeight)
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func fieldBackground(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.05, green: 0.15, blue: 0.05),
                            Color(red: 0.04, green: 0.12, blue: 0.04),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Yard lines
            ForEach(0..<5, id: \.self) { i in
                let yFraction = CGFloat(i + 1) / 6.0
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .offset(y: (yFraction - 0.5) * height)
            }

            // Line of scrimmage
            Rectangle()
                .fill(Color.accentGold.opacity(0.3))
                .frame(height: 2)
                .offset(y: (layout.lineOfScrimmageY - 0.5) * height)
        }
    }
}

// MARK: - Formation Player Card

struct FormationPlayerCard: View {
    let player: Player
    let isStarter: Bool
    let backupCount: Int

    var body: some View {
        VStack(spacing: 2) {
            // Position label
            Text(player.position.rawValue)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.textTertiary)

            // Name
            Text(player.lastName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            // Overall
            Text("\(player.overall)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(minWidth: 56)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.backgroundSecondary.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isStarter ? Color.accentGold : Color.surfaceBorder,
                    lineWidth: isStarter ? 1.5 : 0.5
                )
        )
        .overlay(alignment: .topTrailing) {
            if player.isInjured {
                Image(systemName: "cross.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.danger)
                    .offset(x: 4, y: -4)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if backupCount > 0 {
                Text("+\(backupCount)")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.backgroundTertiary, in: Capsule())
                    .offset(x: 4, y: 4)
            }
        }
    }
}

// MARK: - Formation Layout

enum FormationLayout {
    case offense
    case defense
    case specialTeams

    var fieldHeight: CGFloat {
        switch self {
        case .offense:      return 340
        case .defense:      return 320
        case .specialTeams: return 180
        }
    }

    var lineOfScrimmageY: CGFloat {
        switch self {
        case .offense:      return 0.72
        case .defense:      return 0.28
        case .specialTeams: return 0.5
        }
    }

    var slots: [FormationSlot] {
        switch self {
        case .offense:
            return [
                // QB
                FormationSlot(position: .QB, xPercent: 0.5, yPercent: 0.55),
                // RB
                FormationSlot(position: .RB, xPercent: 0.5, yPercent: 0.40),
                // FB
                FormationSlot(position: .FB, xPercent: 0.35, yPercent: 0.48),
                // WR left
                FormationSlot(position: .WR, xPercent: 0.08, yPercent: 0.72),
                // TE
                FormationSlot(position: .TE, xPercent: 0.82, yPercent: 0.72),
                // OL
                FormationSlot(position: .LT, xPercent: 0.28, yPercent: 0.72),
                FormationSlot(position: .LG, xPercent: 0.38, yPercent: 0.72),
                FormationSlot(position: .C,  xPercent: 0.50, yPercent: 0.72),
                FormationSlot(position: .RG, xPercent: 0.62, yPercent: 0.72),
                FormationSlot(position: .RT, xPercent: 0.72, yPercent: 0.72),
            ]
        case .defense:
            return [
                // DL
                FormationSlot(position: .DE, xPercent: 0.22, yPercent: 0.35),
                FormationSlot(position: .DT, xPercent: 0.50, yPercent: 0.35),
                // LB
                FormationSlot(position: .OLB, xPercent: 0.15, yPercent: 0.52),
                FormationSlot(position: .MLB, xPercent: 0.50, yPercent: 0.52),
                // DB
                FormationSlot(position: .CB, xPercent: 0.10, yPercent: 0.72),
                FormationSlot(position: .FS, xPercent: 0.40, yPercent: 0.85),
                FormationSlot(position: .SS, xPercent: 0.60, yPercent: 0.85),
            ]
        case .specialTeams:
            return [
                FormationSlot(position: .K, xPercent: 0.35, yPercent: 0.5),
                FormationSlot(position: .P, xPercent: 0.65, yPercent: 0.5),
            ]
        }
    }
}

// MARK: - Formation Slot

struct FormationSlot: Identifiable {
    let position: Position
    let xPercent: CGFloat
    let yPercent: CGFloat

    var id: String { "\(position.rawValue)-\(xPercent)-\(yPercent)" }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScrollView {
            FormationView(
                title: "Offense",
                players: [
                    Player(
                        firstName: "Patrick", lastName: "Mahomes", position: .QB,
                        age: 28, yearsPro: 7,
                        positionAttributes: .quarterback(QBAttributes(
                            armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                            accuracyDeep: 87, pocketPresence: 92, scrambling: 80
                        )),
                        personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning)
                    ),
                    Player(
                        firstName: "Tyreek", lastName: "Hill", position: .WR,
                        age: 29, yearsPro: 8,
                        positionAttributes: .wideReceiver(WRAttributes(
                            routeRunning: 88, catching: 90, release: 92, spectacularCatch: 85
                        )),
                        personality: PlayerPersonality(archetype: .loneWolf, motivation: .stats),
                        isInjured: true
                    ),
                ],
                layout: .offense
            )
        }
        .background(Color.backgroundPrimary)
    }
}
