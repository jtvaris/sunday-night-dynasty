import SwiftUI

/// Visual football formation layout showing players at their approximate field positions.
/// Supports tapping slots to swap/assign players (#43), shows empty placeholders (#42),
/// full 11-player defense (#44), formation name (#46), reserve panel (#81), and depth info (#47).
struct FormationView: View {
    let title: String
    let players: [Player]
    let layout: FormationLayout

    /// Currently selected slot for player swap picker (#43)
    @State private var selectedSlot: FormationSlot?

    var body: some View {
        VStack(spacing: 0) {
            // Section title with formation name (#46)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.textPrimary)
                    Text(layout.formationName)
                        .font(.caption)
                        .foregroundStyle(Color.accentGold)
                }
                Spacer()
                Text("\(starterCount)/\(layout.slots.count) starters")
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

                        // Player cards at positions (or empty placeholders #42)
                        ForEach(layout.slots) { slot in
                            let player = playerForSlot(slot)
                            let x = slot.xPercent * width
                            let y = slot.yPercent * height
                            let backups = backupsForSlot(slot)

                            if let player = player {
                                Button {
                                    selectedSlot = slot
                                } label: {
                                    FormationPlayerCard(
                                        player: player,
                                        label: slot.label,
                                        isStarter: true,
                                        backupCount: backups.count
                                    )
                                }
                                .position(x: x, y: y)
                            } else {
                                // Empty placeholder slot (#42)
                                Button {
                                    selectedSlot = slot
                                } label: {
                                    FormationEmptySlot(label: slot.label)
                                }
                                .position(x: x, y: y)
                            }
                        }
                    }
                    .frame(height: height)
                }
                .frame(height: layout.fieldHeight)

                // Position group sidebar (#47 + #103)
                if layout != .specialTeams {
                    positionGroupSidebar
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            // Reserve/backup players panel (#81)
            if !reservePlayers.isEmpty {
                reservePanel
            }
        }
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .sheet(item: $selectedSlot) { slot in
            PlayerSlotPicker(
                slot: slot,
                players: eligiblePlayers(for: slot),
                currentPlayer: playerForSlot(slot)
            )
        }
    }

    // MARK: - Player Resolution

    /// Number of filled starter slots
    private var starterCount: Int {
        layout.slots.filter { playerForSlot($0) != nil }.count
    }

    /// Finds the player assigned to a specific formation slot using label + positionIndex.
    private func playerForSlot(_ slot: FormationSlot) -> Player? {
        let positionPlayers = players
            .filter { $0.position == slot.position }
            .sorted { $0.overall > $1.overall }
        guard slot.positionIndex < positionPlayers.count else { return nil }
        return positionPlayers[slot.positionIndex]
    }

    /// Returns backup players for a slot (all players at that position after the starter).
    private func backupsForSlot(_ slot: FormationSlot) -> [Player] {
        let positionPlayers = players
            .filter { $0.position == slot.position }
            .sorted { $0.overall > $1.overall }
        // Only show backup count for the first slot of each position
        guard slot.positionIndex == 0 else { return [] }
        let totalSlots = layout.slots.filter { $0.position == slot.position }.count
        return Array(positionPlayers.dropFirst(totalSlots))
    }

    /// Players not assigned to any starter slot — shown in the reserve panel (#81)
    private var reservePlayers: [Player] {
        // Collect all players used in starter slots
        var usedIDs = Set<UUID>()
        for slot in layout.slots {
            if let player = playerForSlot(slot) {
                usedIDs.insert(player.id)
            }
        }
        return players
            .filter { !usedIDs.contains($0.id) }
            .sorted { $0.overall > $1.overall }
    }

    /// Eligible players for a slot's position (#43)
    private func eligiblePlayers(for slot: FormationSlot) -> [Player] {
        players
            .filter { $0.position == slot.position }
            .sorted { $0.overall > $1.overall }
    }

    // MARK: - Field Background (#99 + #102)

    private func fieldBackground(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Dark atmospheric field background
            Image("BgFormationField")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.3))
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

    // MARK: - Position Group Sidebar (#47 + #103)

    private var positionGroupSidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Groups")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textTertiary)
                .padding(.bottom, 2)

            ForEach(positionGroupStats, id: \.name) { group in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(group.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 28, alignment: .leading)
                        Text("\(group.average)")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.forPlayerCardRating(group.average))
                        Spacer()
                    }
                    // Depth info (#47): e.g. "2/2 filled"
                    Text("\(group.filled)/\(group.needed) filled")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(group.filled >= group.needed ? Color.textTertiary : Color.warning)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: 100)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundTertiary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.surfaceBorder, lineWidth: 0.5)
        )
    }

    private var positionGroupStats: [PositionGroupStat] {
        let groups: [(name: String, positions: [Position], neededStarters: Int)]
        switch layout {
        case .offense:
            groups = [
                ("QB", [.QB], 1),
                ("RB", [.RB, .FB], 2),
                ("WR", [.WR], 2),
                ("TE", [.TE], 1),
                ("OL", [.LT, .LG, .C, .RG, .RT], 5),
            ]
        case .defense:
            groups = [
                ("DL", [.DE, .DT], 4),
                ("LB", [.OLB, .MLB], 3),
                ("CB", [.CB], 2),
                ("S", [.FS, .SS], 2),
            ]
        case .specialTeams:
            groups = [
                ("K", [.K], 1),
                ("P", [.P], 1),
            ]
        }

        return groups.compactMap { group in
            let groupPlayers = players.filter { group.positions.contains($0.position) }
            guard !groupPlayers.isEmpty else {
                return PositionGroupStat(
                    name: group.name, average: 0,
                    filled: 0, needed: group.neededStarters
                )
            }
            let avg = groupPlayers.map(\.overall).reduce(0, +) / groupPlayers.count
            return PositionGroupStat(
                name: group.name, average: avg,
                filled: min(groupPlayers.count, group.neededStarters),
                needed: group.neededStarters
            )
        }
    }

    // MARK: - Reserve Panel (#81)

    private var reservePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Text("Reserves & Backups")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(reservePlayers.count) players")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(reservePlayers) { player in
                        NavigationLink(destination: PlayerDetailView(player: player)) {
                            FormationPlayerCard(
                                player: player,
                                label: player.position.rawValue,
                                isStarter: false,
                                backupCount: 0
                            )
                        }
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(Color.backgroundTertiary.opacity(0.3))
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 0.5)
        }
    }
}

// MARK: - Position Group Stat (#47)

private struct PositionGroupStat {
    let name: String
    let average: Int
    let filled: Int
    let needed: Int
}

// MARK: - Empty Slot Placeholder (#42)

struct FormationEmptySlot: View {
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textTertiary)

            Image(systemName: "questionmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.textTertiary.opacity(0.6))

            Text("--")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.textTertiary.opacity(0.5))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minWidth: 64)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.backgroundSecondary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.textTertiary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }
}

// MARK: - Formation Player Card (#100 + #101)

struct FormationPlayerCard: View {
    let player: Player
    let label: String
    let isStarter: Bool
    let backupCount: Int

    /// Card border color based on overall rating (#101)
    private var ratingBorderColor: Color {
        Color.forPlayerCardRating(player.overall)
    }

    var body: some View {
        VStack(spacing: 2) {
            // Slot label (e.g., "LE", "CB1", "WR2")
            Text(label)
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

// MARK: - Player Slot Picker (#43)

/// Sheet presented when tapping a formation slot to swap/assign a different player.
struct PlayerSlotPicker: View {
    let slot: FormationSlot
    let players: [Player]
    let currentPlayer: Player?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if players.isEmpty {
                    Text("No eligible players at \(slot.position.rawValue)")
                        .foregroundStyle(Color.textTertiary)
                        .listRowBackground(Color.backgroundSecondary)
                } else {
                    ForEach(players) { player in
                        Button {
                            // TODO: Wire up actual depth chart swap when DepthChart is observable
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                // Rating badge
                                Text("\(player.overall)")
                                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                                    .foregroundStyle(Color.forPlayerCardRating(player.overall))
                                    .frame(width: 36)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(player.fullName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.textPrimary)
                                    HStack(spacing: 6) {
                                        Text(player.position.rawValue)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(Color.textSecondary)
                                        Text("Age \(player.age)")
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.textTertiary)
                                    }
                                }

                                Spacer()

                                // Current assignment indicator
                                if let current = currentPlayer, current.id == player.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentGold)
                                }

                                if player.isInjured {
                                    Image(systemName: "cross.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.danger)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.backgroundSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
            .navigationTitle("\(slot.label) — Select Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.accentGold)
                }
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

    /// Formation/scheme display name (#46)
    var formationName: String {
        switch self {
        case .offense:      return "11 Personnel"
        case .defense:      return "4-3 Defense"
        case .specialTeams: return "Special Teams"
        }
    }

    /// Increased field heights for more screen real estate (#45 + #99)
    var fieldHeight: CGFloat {
        switch self {
        case .offense:      return 480
        case .defense:      return 480
        case .specialTeams: return 240
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
                FormationSlot(position: .QB, label: "QB", positionIndex: 0, xPercent: 0.50, yPercent: 0.55),
                // RB
                FormationSlot(position: .RB, label: "RB", positionIndex: 0, xPercent: 0.50, yPercent: 0.40),
                // FB
                FormationSlot(position: .FB, label: "FB", positionIndex: 0, xPercent: 0.35, yPercent: 0.48),
                // WR left + right
                FormationSlot(position: .WR, label: "WR1", positionIndex: 0, xPercent: 0.08, yPercent: 0.72),
                FormationSlot(position: .WR, label: "WR2", positionIndex: 1, xPercent: 0.92, yPercent: 0.72),
                // TE
                FormationSlot(position: .TE, label: "TE", positionIndex: 0, xPercent: 0.82, yPercent: 0.72),
                // OL
                FormationSlot(position: .LT, label: "LT", positionIndex: 0, xPercent: 0.28, yPercent: 0.72),
                FormationSlot(position: .LG, label: "LG", positionIndex: 0, xPercent: 0.38, yPercent: 0.72),
                FormationSlot(position: .C,  label: "C",  positionIndex: 0, xPercent: 0.50, yPercent: 0.72),
                FormationSlot(position: .RG, label: "RG", positionIndex: 0, xPercent: 0.62, yPercent: 0.72),
                FormationSlot(position: .RT, label: "RT", positionIndex: 0, xPercent: 0.72, yPercent: 0.72),
            ]
        case .defense:
            // Full 4-3 defense: 11 players (#44)
            return [
                // DL: 2 DE + 2 DT (4-man front)
                FormationSlot(position: .DE, label: "LE",  positionIndex: 0, xPercent: 0.18, yPercent: 0.32),
                FormationSlot(position: .DT, label: "DT1", positionIndex: 0, xPercent: 0.38, yPercent: 0.32),
                FormationSlot(position: .DT, label: "DT2", positionIndex: 1, xPercent: 0.62, yPercent: 0.32),
                FormationSlot(position: .DE, label: "RE",  positionIndex: 1, xPercent: 0.82, yPercent: 0.32),
                // LB: 2 OLB + 1 MLB (3 linebackers)
                FormationSlot(position: .OLB, label: "LOLB", positionIndex: 0, xPercent: 0.20, yPercent: 0.48),
                FormationSlot(position: .MLB, label: "MLB",  positionIndex: 0, xPercent: 0.50, yPercent: 0.48),
                FormationSlot(position: .OLB, label: "ROLB", positionIndex: 1, xPercent: 0.80, yPercent: 0.48),
                // DB: 2 CB + 1 FS + 1 SS (4 defensive backs)
                FormationSlot(position: .CB, label: "CB1", positionIndex: 0, xPercent: 0.08, yPercent: 0.68),
                FormationSlot(position: .CB, label: "CB2", positionIndex: 1, xPercent: 0.92, yPercent: 0.68),
                FormationSlot(position: .FS, label: "FS",  positionIndex: 0, xPercent: 0.38, yPercent: 0.85),
                FormationSlot(position: .SS, label: "SS",  positionIndex: 0, xPercent: 0.62, yPercent: 0.85),
            ]
        case .specialTeams:
            return [
                FormationSlot(position: .K, label: "K", positionIndex: 0, xPercent: 0.35, yPercent: 0.5),
                FormationSlot(position: .P, label: "P", positionIndex: 0, xPercent: 0.65, yPercent: 0.5),
            ]
        }
    }
}

// MARK: - Formation Slot

struct FormationSlot: Identifiable {
    let position: Position
    /// Display label for this slot (e.g. "LE", "CB1", "ROLB")
    let label: String
    /// Index into the sorted-by-overall list for this position (0 = best, 1 = second-best, etc.)
    let positionIndex: Int
    let xPercent: CGFloat
    let yPercent: CGFloat

    var id: String { "\(label)-\(xPercent)-\(yPercent)" }
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
