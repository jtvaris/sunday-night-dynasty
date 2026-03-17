import SwiftUI
import SwiftData

// MARK: - Main View

struct DepthChartView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Query private var allPlayers: [Player]

    @State private var depthChart = DepthChart()
    @State private var selectedTab: PositionSide = .offense
    @State private var pickerState: PickerState? = nil

    // MARK: - Derived roster

    private var rosterPlayers: [Player] {
        guard let teamID = career.teamID else { return [] }
        return allPlayers.filter { $0.teamID == teamID }
    }

    private func playerLookup() -> [UUID: Player] {
        Dictionary(uniqueKeysWithValues: rosterPlayers.map { ($0.id, $0) })
    }

    // MARK: - Position groups

    private var offensePositions: [Position] {
        [.QB, .RB, .FB, .WR, .TE, .LT, .LG, .C, .RG, .RT]
    }

    private var defensePositions: [Position] {
        [.DE, .DT, .OLB, .MLB, .CB, .FS, .SS]
    }

    private var specialTeamsPositions: [Position] {
        [.K, .P]
    }

    private var activePositions: [Position] {
        switch selectedTab {
        case .offense:      return offensePositions
        case .defense:      return defensePositions
        case .specialTeams: return specialTeamsPositions
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                tabBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(activePositions, id: \.self) { position in
                            positionRow(position: position, lookup: playerLookup())
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Depth Chart")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                autoFillButton
            }
        }
        .sheet(item: $pickerState) { state in
            PlayerPickerSheet(
                position: state.position,
                slotIndex: state.slotIndex,
                players: rosterPlayers.filter { $0.position == state.position },
                currentDepth: depthChart.depthOrder(at: state.position),
                onSelect: { playerID in
                    depthChart.assign(position: state.position, playerID: playerID, at: state.slotIndex)
                    pickerState = nil
                },
                onDismiss: { pickerState = nil }
            )
        }
        .task {
            depthChart.autoGenerate(players: rosterPlayers)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach([PositionSide.offense, .defense, .specialTeams], id: \.self) { side in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = side
                    }
                } label: {
                    Text(side.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedTab == side ? Color.backgroundPrimary : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == side ? Color.accentGold : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Auto-Fill Button

    private var autoFillButton: some View {
        Button {
            withAnimation {
                depthChart.autoGenerate(players: rosterPlayers)
            }
        } label: {
            Label("Auto-Fill", systemImage: "wand.and.stars")
        }
        .foregroundStyle(Color.accentGold)
        .accessibilityLabel("Auto-fill depth chart by overall rating")
    }

    // MARK: - Position Row

    private func positionRow(position: Position, lookup: [UUID: Player]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                positionBadge(position)
                Text(position.rawValue)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(positionFullName(position))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    let depth = depthChart.depthOrder(at: position)
                    let maxSlots = maxSlotsFor(position: position)
                    ForEach(0..<maxSlots, id: \.self) { index in
                        let playerID = index < depth.count ? depth[index] : nil
                        let player = playerID.flatMap { lookup[$0] }
                        depthSlot(
                            index: index,
                            player: player,
                            isStarter: index == 0
                        ) {
                            pickerState = PickerState(position: position, slotIndex: index)
                        }
                    }
                }
            }
        }
        .padding(14)
        .cardBackground()
    }

    // MARK: - Depth Slot

    private func depthSlot(
        index: Int,
        player: Player?,
        isStarter: Bool,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                // Slot label
                Text(slotLabel(index: index))
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isStarter ? Color.accentGold : Color.textTertiary)
                    .textCase(.uppercase)

                if let player {
                    VStack(spacing: 3) {
                        Text(player.lastName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Text("\(player.overall)")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.forRating(player.overall))
                    }
                } else {
                    VStack(spacing: 3) {
                        Text("Empty")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                        Text("—")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .frame(width: 72, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isStarter ? Color.accentGold.opacity(0.08) : Color.backgroundTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                isStarter ? Color.accentGold : Color.surfaceBorder,
                                lineWidth: isStarter ? 1.5 : 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slotAccessibilityLabel(index: index, player: player))
    }

    // MARK: - Position Badge

    private func positionBadge(_ position: Position) -> some View {
        Text(position.rawValue)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color.backgroundPrimary)
            .frame(width: 32, height: 22)
            .background(sideColor(position.side), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Helpers

    private func sideColor(_ side: PositionSide) -> Color {
        switch side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func slotLabel(index: Int) -> String {
        switch index {
        case 0: return "Starter"
        case 1: return "Backup 1"
        case 2: return "Backup 2"
        default: return "Depth \(index + 1)"
        }
    }

    private func slotAccessibilityLabel(index: Int, player: Player?) -> String {
        let slot = slotLabel(index: index)
        if let player {
            return "\(slot): \(player.fullName), overall \(player.overall)"
        }
        return "\(slot): empty, tap to assign"
    }

    private func maxSlotsFor(position: Position) -> Int {
        switch position {
        case .QB:                            return 3
        case .RB, .WR, .CB:                  return 4
        case .DE, .DT, .OLB:                 return 3
        default:                             return 3
        }
    }

    private func positionFullName(_ position: Position) -> String {
        switch position {
        case .QB:  return "Quarterback"
        case .RB:  return "Running Back"
        case .FB:  return "Fullback"
        case .WR:  return "Wide Receiver"
        case .TE:  return "Tight End"
        case .LT:  return "Left Tackle"
        case .LG:  return "Left Guard"
        case .C:   return "Center"
        case .RG:  return "Right Guard"
        case .RT:  return "Right Tackle"
        case .DE:  return "Defensive End"
        case .DT:  return "Defensive Tackle"
        case .OLB: return "Outside Linebacker"
        case .MLB: return "Middle Linebacker"
        case .CB:  return "Cornerback"
        case .FS:  return "Free Safety"
        case .SS:  return "Strong Safety"
        case .K:   return "Kicker"
        case .P:   return "Punter"
        }
    }
}

// MARK: - Picker State

private struct PickerState: Identifiable {
    let id = UUID()
    let position: Position
    let slotIndex: Int
}

// MARK: - Player Picker Sheet

private struct PlayerPickerSheet: View {

    let position: Position
    let slotIndex: Int
    let players: [Player]
    let currentDepth: [UUID]
    let onSelect: (UUID) -> Void
    let onDismiss: () -> Void

    private var slotLabel: String {
        switch slotIndex {
        case 0: return "Starter"
        case 1: return "Backup 1"
        case 2: return "Backup 2"
        default: return "Depth \(slotIndex + 1)"
        }
    }

    private var sortedPlayers: [Player] {
        players.sorted { $0.overall > $1.overall }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                List {
                    // "Clear slot" option
                    Section {
                        Button {
                            onDismiss()
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .foregroundStyle(Color.textTertiary)
                                Text("Leave Empty")
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.backgroundSecondary)

                    Section("Available Players") {
                        if sortedPlayers.isEmpty {
                            Text("No \(position.rawValue) on roster")
                                .foregroundStyle(Color.textTertiary)
                                .font(.subheadline)
                        } else {
                            ForEach(sortedPlayers) { player in
                                Button {
                                    onSelect(player.id)
                                } label: {
                                    pickerRow(player)
                                }
                                .listRowBackground(Color.backgroundSecondary)
                            }
                        }
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Assign \(position.rawValue) — \(slotLabel)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onDismiss)
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
    }

    private func pickerRow(_ player: Player) -> some View {
        let isInDepth = currentDepth.contains(player.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("Age \(player.age)  |  \(player.yearsPro == 0 ? "Rookie" : "\(player.yearsPro)yr pro")")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if isInDepth {
                Text("In Chart")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.accentGold.opacity(0.15))
                    )
            }
            if player.isInjured {
                Image(systemName: "cross.circle.fill")
                    .foregroundStyle(Color.danger)
                    .font(.caption)
            }
            Text("\(player.overall)")
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DepthChartView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Player.self], inMemory: true)
}
