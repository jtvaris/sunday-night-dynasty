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
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 6)

            // Formation field + position group sidebar
            HStack(alignment: .top, spacing: 6) {
                // Formation field
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let height = layout.fieldHeight

                    ZStack {
                        // Field background with yard lines
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

                // Position group averages sidebar (#103)
                if layout != .specialTeams {
                    positionGroupSidebar
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)
        }
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // MARK: - Field Background (#99 + #102)

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

            // Yard line markings every 10 yards (#102)
            let yardLineCount = 9 // 10, 20, 30, 40, 50, 40, 30, 20, 10
            let yardLabels = ["10", "20", "30", "40", "50", "40", "30", "20", "10"]
            ForEach(0..<yardLineCount, id: \.self) { i in
                let yFraction = CGFloat(i + 1) / CGFloat(yardLineCount + 1)
                let yOffset = (yFraction - 0.5) * height

                // Yard line
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 1)
                    .offset(y: yOffset)

                // Hash marks (small dashes at the sides)
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 6, height: 1)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 6, height: 1)
                }
                .padding(.horizontal, 4)
                .offset(y: yOffset)

                // Yard number labels
                HStack {
                    Text(yardLabels[i])
                        .font(.system(size: 8, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.18))
                        .padding(.leading, 10)
                    Spacer()
                    Text(yardLabels[i])
                        .font(.system(size: 8, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.18))
                        .padding(.trailing, 10)
                }
                .offset(y: yOffset - 7)
            }

            // End zone indicators
            VStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: height / CGFloat(yardLineCount + 1))
                    .overlay(
                        Text("END ZONE")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.12))
                    )
                Spacer()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: height / CGFloat(yardLineCount + 1))
                    .overlay(
                        Text("END ZONE")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.12))
                    )
            }
            .padding(2)

            // Line of scrimmage
            Rectangle()
                .fill(Color.accentGold.opacity(0.4))
                .frame(height: 2)
                .offset(y: (layout.lineOfScrimmageY - 0.5) * height)
        }
    }

    // MARK: - Position Group Sidebar (#103)

    private var positionGroupSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Groups")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.textTertiary)
                .padding(.bottom, 2)

            ForEach(positionGroupAverages, id: \.name) { group in
                HStack(spacing: 4) {
                    Text(group.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 28, alignment: .leading)
                    Text("\(group.average)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.forPlayerCardRating(group.average))
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(width: 80)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundTertiary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.surfaceBorder, lineWidth: 0.5)
        )
    }

    private var positionGroupAverages: [PositionGroupAverage] {
        let groups: [(name: String, positions: [Position])]
        switch layout {
        case .offense:
            groups = [
                ("QB", [.QB]),
                ("RB", [.RB, .FB]),
                ("WR", [.WR]),
                ("TE", [.TE]),
                ("OL", [.LT, .LG, .C, .RG, .RT]),
            ]
        case .defense:
            groups = [
                ("DL", [.DE, .DT]),
                ("LB", [.OLB, .MLB]),
                ("CB", [.CB]),
                ("S", [.FS, .SS]),
            ]
        case .specialTeams:
            groups = [
                ("K", [.K]),
                ("P", [.P]),
            ]
        }

        return groups.compactMap { group in
            let groupPlayers = players.filter { group.positions.contains($0.position) }
            guard !groupPlayers.isEmpty else { return nil }
            let avg = groupPlayers.map(\.overall).reduce(0, +) / groupPlayers.count
            return PositionGroupAverage(name: group.name, average: avg)
        }
    }
}

// MARK: - Position Group Average

private struct PositionGroupAverage {
    let name: String
    let average: Int
}

// MARK: - Formation Player Card (#100 + #101)

struct FormationPlayerCard: View {
    let player: Player
    let isStarter: Bool
    let backupCount: Int

    /// Card border color based on overall rating (#101)
    private var ratingBorderColor: Color {
        Color.forPlayerCardRating(player.overall)
    }

    var body: some View {
        VStack(spacing: 2) {
            // Position label
            Text(player.position.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(ratingBorderColor)

            // Last name (#100 - enlarged)
            Text(player.lastName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            // Overall rating - larger and color-coded (#100 + #101)
            Text("\(player.overall)")
                .font(.system(size: 14, weight: .heavy).monospacedDigit())
                .foregroundStyle(ratingBorderColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minWidth: 64)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.backgroundSecondary.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    ratingBorderColor,
                    lineWidth: isStarter ? 1.5 : 0.75
                )
        )
        .overlay(alignment: .topTrailing) {
            if player.isInjured {
                Image(systemName: "cross.circle.fill")
                    .font(.system(size: 9))
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

// MARK: - Player Card Rating Color (#101)

extension Color {
    /// Color-codes player cards by overall rating tier.
    /// - 90+ Elite: gold
    /// - 80-89 Good: green
    /// - 70-79 Average: cool blue-white
    /// - Below 70: orange-red
    static func forPlayerCardRating(_ value: Int) -> Color {
        switch value {
        case 90...:   return Color.accentGold          // Elite - gold
        case 80..<90: return Color.success             // Good - green
        case 70..<80: return Color.accentBlue          // Average - blue
        default:      return Color(red: 0.9, green: 0.45, blue: 0.2) // Below average - orange
        }
    }
}

// MARK: - Formation Layout

enum FormationLayout: Equatable {
    case offense
    case defense
    case specialTeams

    /// Increased field heights for more screen real estate (#99)
    var fieldHeight: CGFloat {
        switch self {
        case .offense:      return 420
        case .defense:      return 400
        case .specialTeams: return 220
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
