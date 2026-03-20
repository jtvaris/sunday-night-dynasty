import SwiftUI

/// Visual football formation layout showing players at their approximate field positions.
/// Supports tapping slots to swap/assign players (#43), shows empty placeholders (#42),
/// full 11-player defense (#44), formation name (#46), reserve panel (#81), depth info (#47),
/// formation picker (#190), player comparison (#192), backup slot selection (#199).
struct FormationView: View {
    let title: String
    let players: [Player]
    @State private var layout: FormationLayout

    /// Callback fired when the user swaps a player into a formation slot.
    /// Parameters: (position, selectedPlayer) — the caller should promote selectedPlayer to starter.
    var onPlayerSwapped: ((Position, Player) -> Void)?

    /// Currently selected slot for player swap picker (#43)
    @State private var selectedSlot: FormationSlot?
    /// Whether we're picking for a backup slot (#199)
    @State private var selectedBackupDepth: Int = 0
    /// Slot for comparison overlay (#192)
    @State private var comparisonSlot: FormationSlot?

    /// Local custom depth ordering built from formation swaps so the formation view
    /// reflects changes immediately (even before the parent updates).
    @State private var localDepthOrder: [Position: [UUID]] = [:]

    init(title: String, players: [Player], layout: FormationLayout, onPlayerSwapped: ((Position, Player) -> Void)? = nil) {
        self.title = title
        self.players = players
        self._layout = State(initialValue: layout)
        self.onPlayerSwapped = onPlayerSwapped
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section title with formation name (#46) + formation picker (#190)
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

                // #188: Highlight unfilled count
                let unfilled = layout.slots.count - starterCount
                HStack(spacing: 4) {
                    Text("\(starterCount)/\(layout.slots.count) starters")
                        .font(.caption)
                        .foregroundStyle(unfilled > 0 ? Color.warning : Color.textSecondary)
                    if unfilled > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.warning)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)

            // Formation picker (#190)
            if layout != .specialTeams {
                formationPicker
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }

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
                                    selectedBackupDepth = 0
                                } label: {
                                    FormationPlayerCard(
                                        player: player,
                                        label: slot.label,
                                        isStarter: true,
                                        backupCount: backups.count
                                    )
                                }
                                .position(x: x, y: y)
                                .contextMenu {
                                    // #192: comparison on long-press context menu
                                    Button {
                                        comparisonSlot = slot
                                    } label: {
                                        Label("Compare Starter vs Backup", systemImage: "arrow.left.arrow.right")
                                    }
                                    // #199: assign backup slots
                                    Button {
                                        selectedSlot = slot
                                        selectedBackupDepth = 1
                                    } label: {
                                        Label("Assign Backup (B2)", systemImage: "person.badge.plus")
                                    }
                                    Button {
                                        selectedSlot = slot
                                        selectedBackupDepth = 2
                                    } label: {
                                        Label("Assign B3", systemImage: "person.badge.plus")
                                    }
                                }
                            } else {
                                // Empty placeholder slot (#42) — shown as "?" card (#188)
                                Button {
                                    selectedSlot = slot
                                    selectedBackupDepth = 0
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

            // Reserve/backup players panel (#81) — #185: enhanced with more info
            reservePanel
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
                allPlayers: players,
                currentPlayer: playerForSlot(slot),
                backupDepth: selectedBackupDepth,
                onPlayerSelected: { player in
                    promotePlayer(player, forSlot: slot)
                }
            )
            .presentationDetents([.medium, .large]) // #193
        }
        .sheet(item: $comparisonSlot) { slot in
            // #192: Comparison overlay
            StarterBackupComparisonSheet(
                slot: slot,
                starter: playerForSlot(slot),
                backups: backupsForSlot(slot)
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Formation Picker (#190)

    @ViewBuilder
    private var formationPicker: some View {
        let formations = layout.availableFormations
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(formations, id: \.formationName) { formation in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            layout = formation
                        }
                    } label: {
                        Text(formation.formationName)
                            .font(.system(size: 11, weight: layout == formation ? .bold : .medium))
                            .foregroundStyle(layout == formation ? Color.backgroundPrimary : Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(layout == formation ? Color.accentGold : Color.backgroundPrimary.opacity(0.5))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(layout == formation ? Color.accentGold : Color.surfaceBorder, lineWidth: 0.5)
                            )
                    }
                    .contentShape(Capsule())
                }
            }
        }
    }

    // MARK: - Player Resolution

    /// Number of filled starter slots
    private var starterCount: Int {
        layout.slots.filter { playerForSlot($0) != nil }.count
    }

    /// Finds the player assigned to a specific formation slot using label + positionIndex.
    /// Respects local depth ordering from formation swaps when available.
    private func playerForSlot(_ slot: FormationSlot) -> Player? {
        let positionPlayers: [Player]
        if let customOrder = localDepthOrder[slot.position] {
            // Sort by custom order, falling back to OVR for players not in the custom list
            let orderLookup = Dictionary(uniqueKeysWithValues: customOrder.enumerated().map { ($1, $0) })
            positionPlayers = players
                .filter { $0.position == slot.position }
                .sorted { a, b in
                    let idxA = orderLookup[a.id] ?? (Int.max - a.overall)
                    let idxB = orderLookup[b.id] ?? (Int.max - b.overall)
                    return idxA < idxB
                }
        } else {
            positionPlayers = players
                .filter { $0.position == slot.position }
                .sorted { $0.overall > $1.overall }
        }
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

    /// Eligible players for a slot's position (#43) + versatile players (#194)
    private func eligiblePlayers(for slot: FormationSlot) -> [Player] {
        players
            .filter { $0.position == slot.position }
            .sorted { $0.overall > $1.overall }
    }

    /// Players from other positions who have familiarity at this slot's position (#194)
    private func versatilePlayers(for slot: FormationSlot) -> [Player] {
        players
            .filter { $0.position != slot.position && $0.familiarity(at: slot.position) > 0 }
            .sorted { $0.familiarity(at: slot.position) > $1.familiarity(at: slot.position) }
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
                    HStack(spacing: 2) {
                        Text(group.name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 22, alignment: .leading)
                        // Starter grade / Depth grade (#235)
                        Text("S:")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Text(group.starterGrade)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(group.starterGrade))
                        Text("/")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.textTertiary)
                        Text("D:")
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Text(group.depthGrade)
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(group.depthGrade))
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
        .frame(width: 110)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundPrimary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.surfaceBorder, lineWidth: 0.5)
        )
    }

    // #186: Fixed OL group — compute average only from starters at those positions
    private var positionGroupStats: [PositionGroupStat] {
        let groups: [(name: String, positions: [Position], neededStarters: Int)]
        switch layout {
        case .offense, .offense11Personnel, .offense12Personnel, .offenseShotgun, .offenseSpread:
            groups = [
                ("QB", [.QB], 1),
                ("RB", [.RB, .FB], 2),
                ("WR", [.WR], 2),
                ("TE", [.TE], 1),
                ("OL", [.LT, .LG, .C, .RG, .RT], 5),
            ]
        case .defense, .defense43, .defense34, .defenseNickel, .defenseDime:
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
            // #186: Include ALL sub-positions for OL group and compute correctly
            let groupPlayers = players.filter { group.positions.contains($0.position) }
            let grades = PositionGradeCalculator.calculatePositionGrades(players: groupPlayers, positions: group.positions)
            guard !groupPlayers.isEmpty else {
                return PositionGroupStat(
                    name: group.name, average: 0,
                    starterGrade: "F", depthGrade: "F",
                    filled: 0, needed: group.neededStarters
                )
            }
            return PositionGroupStat(
                name: group.name, average: grades.starterOVR,
                starterGrade: grades.starterGrade, depthGrade: grades.depthGrade,
                filled: min(groupPlayers.count, group.neededStarters),
                needed: group.neededStarters
            )
        }
    }

    // MARK: - Reserve Panel (#81) — #185: Enhanced with more info

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

            if reservePlayers.isEmpty {
                Text("All players assigned to starter slots")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
            } else {
                // #185: Show reserves grouped by position with more detail
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(reservePlayers) { player in
                            NavigationLink(destination: PlayerDetailView(player: player)) {
                                VStack(spacing: 3) {
                                    // Position badge — #189: larger and clearer
                                    Text(player.position.rawValue)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color.textPrimary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.accentGold.opacity(0.2))
                                        )

                                    // #187: "K. Moore" format
                                    Text(shortName(player))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)

                                    // OVR
                                    Text("\(player.overall)")
                                        .font(.system(size: 13, weight: .heavy).monospacedDigit())
                                        .foregroundStyle(Color.forPlayerCardRating(player.overall))

                                    // #191: age + form dot
                                    HStack(spacing: 3) {
                                        Text("Age \(player.age)")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Color.textTertiary)
                                        formDot(for: player)
                                    }

                                    // #185: salary info
                                    Text(formatSalary(player.annualSalary))
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.textTertiary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(minWidth: 72)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(Color.backgroundSecondary.opacity(0.92))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(Color.surfaceBorder, lineWidth: 0.5)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(Color.backgroundPrimary.opacity(0.3))
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 0.5)
        }
    }

    // MARK: - Helpers

    /// #187: Short name format "K. Moore"
    private func shortName(_ player: Player) -> String {
        let firstInitial = player.firstName.prefix(1)
        return "\(firstInitial). \(player.lastName)"
    }

    /// #191: Form indicator dot based on age vs peak
    private func formDot(for player: Player) -> some View {
        let trend = developmentTrend(for: player)
        return Circle()
            .fill(trend.color)
            .frame(width: 6, height: 6)
    }

    private func developmentTrend(for player: Player) -> DevelopmentTrend {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            return .improving
        } else if peak.contains(player.age) {
            return .stable
        } else {
            return .declining
        }
    }

    private func formatSalary(_ thousands: Int) -> String {
        if thousands >= 1000 {
            let millions = Double(thousands) / 1000.0
            if millions == Double(Int(millions)) {
                return "$\(Int(millions))M"
            }
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }

    /// #197: Effective OVR for out-of-position player
    private func effectiveOVR(player: Player, at position: Position) -> Int {
        let familiarity = player.familiarity(at: position)
        return Int(Double(player.overall) * Double(familiarity) / 100.0)
    }

    /// Promotes a player to the target depth index at the slot's position,
    /// updating both local formation state and notifying the parent via callback.
    private func promotePlayer(_ player: Player, forSlot slot: FormationSlot) {
        let position = slot.position
        let targetIndex = slot.positionIndex

        // Build current ordered list for this position
        let posPlayers = players.filter { $0.position == position }
        var ordered: [UUID]
        if let existing = localDepthOrder[position] {
            let existingSet = Set(existing)
            let newIDs = posPlayers.filter { !existingSet.contains($0.id) }
                .sorted { $0.overall > $1.overall }
                .map { $0.id }
            ordered = existing + newIDs
            let validIDs = Set(posPlayers.map { $0.id })
            ordered = ordered.filter { validIDs.contains($0) }
        } else {
            ordered = posPlayers.sorted { $0.overall > $1.overall }.map { $0.id }
        }

        // Move the selected player to the target depth index
        if let currentIndex = ordered.firstIndex(of: player.id) {
            ordered.remove(at: currentIndex)
        }
        let clampedTarget = max(0, min(targetIndex, ordered.count))
        ordered.insert(player.id, at: clampedTarget)

        localDepthOrder[position] = ordered

        // Notify parent (RosterView) so the list view also updates
        onPlayerSwapped?(position, player)
    }
}

// MARK: - Position Group Stat (#47)

private struct PositionGroupStat {
    let name: String
    let average: Int
    let starterGrade: String
    let depthGrade: String
    let filled: Int
    let needed: Int
}

// MARK: - Empty Slot Placeholder (#42) — #188: "?" card

struct FormationEmptySlot: View {
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.warning)

            Text("?")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.warning.opacity(0.8))

            Text("EMPTY")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.warning.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(minWidth: 72)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.warning.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.warning.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        )
    }
}

// MARK: - Formation Player Card (#100 + #101 + #187 + #191)

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
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ratingBorderColor)

            // #187: "K. Moore" format — first initial + last name
            Text(shortName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            // #191: Age + form dot row
            HStack(spacing: 3) {
                // Overall rating - larger and color-coded (#100 + #101)
                Text("\(player.overall)")
                    .font(.system(size: 15, weight: .heavy).monospacedDigit())
                    .foregroundStyle(ratingBorderColor)

                formDot
            }

            // #191: Age label
            Text("\(player.age)yo")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 10) // #187: increased card size
        .padding(.vertical, 6)
        .frame(minWidth: 72) // #187: larger min width
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
                    .background(Color.backgroundPrimary, in: Capsule())
                    .offset(x: 4, y: 4)
            }
        }
    }

    /// #187: Short name "K. Moore"
    private var shortName: String {
        let firstInitial = player.firstName.prefix(1)
        return "\(firstInitial). \(player.lastName)"
    }

    /// #191: Form indicator dot
    private var formDot: some View {
        let peak = player.position.peakAgeRange
        let color: Color
        if player.age < peak.lowerBound {
            color = .success
        } else if peak.contains(player.age) {
            color = .accentGold
        } else {
            color = .danger
        }
        return Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}

// MARK: - Player Slot Picker (#43 + #193 + #194 + #195 + #196 + #197)

/// Sheet presented when tapping a formation slot to swap/assign a different player.
struct PlayerSlotPicker: View {
    let slot: FormationSlot
    let players: [Player]
    let allPlayers: [Player]
    let currentPlayer: Player?
    let backupDepth: Int // #199: 0 = starter, 1 = B2, 2 = B3
    /// Callback when the user selects a player for this slot.
    var onPlayerSelected: ((Player) -> Void)?

    @Environment(\.dismiss) private var dismiss

    /// Players from other positions with familiarity (#194)
    private var versatilePlayers: [Player] {
        allPlayers
            .filter { $0.position != slot.position && $0.familiarity(at: slot.position) > 0 }
            .sorted { $0.familiarity(at: slot.position) > $1.familiarity(at: slot.position) }
    }

    var body: some View {
        NavigationStack {
            List {
                // #196: Current starter comparison header
                if let current = currentPlayer {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill.checkmark")
                                .foregroundStyle(Color.accentGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current: \(current.fullName)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                HStack(spacing: 8) {
                                    Text("OVR \(current.overall)")
                                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                                        .foregroundStyle(Color.forPlayerCardRating(current.overall))
                                    Text("Age \(current.age)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.textTertiary)
                                    Text(formatSalary(current.annualSalary))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.backgroundSecondary)
                    } header: {
                        Text(backupDepth > 0 ? "Assigning Backup (B\(backupDepth + 1))" : "Current Starter")
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                // Main eligible players section
                Section {
                    if players.isEmpty {
                        Text("No eligible players at \(slot.position.rawValue)")
                            .foregroundStyle(Color.textTertiary)
                            .listRowBackground(Color.backgroundSecondary)
                    } else {
                        ForEach(players) { player in
                            Button {
                                onPlayerSelected?(player)
                                dismiss()
                            } label: {
                                playerPickerRow(player: player, isVersatile: false)
                            }
                            .listRowBackground(Color.backgroundSecondary)
                        }
                    }
                } header: {
                    Text("\(slot.position.rawValue) Players")
                        .foregroundStyle(Color.textTertiary)
                }

                // #194: Other-position players with versatility
                if !versatilePlayers.isEmpty {
                    Section {
                        ForEach(versatilePlayers) { player in
                            Button {
                                onPlayerSelected?(player)
                                dismiss()
                            } label: {
                                playerPickerRow(player: player, isVersatile: true)
                            }
                            .listRowBackground(Color.backgroundSecondary)
                        }
                    } header: {
                        HStack {
                            Text("Other Positions (Versatile)")
                                .foregroundStyle(Color.textTertiary)
                            Image(systemName: "arrow.triangle.swap")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textTertiary)
                        }
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

    // #195 + #196 + #197: Enhanced picker row
    @ViewBuilder
    private func playerPickerRow(player: Player, isVersatile: Bool) -> some View {
        HStack(spacing: 10) {
            // Rating badge
            VStack(spacing: 1) {
                Text("\(player.overall)")
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.forPlayerCardRating(player.overall))

                // #197: Show effective OVR for out-of-position
                if isVersatile {
                    let familiarity = player.familiarity(at: slot.position)
                    let effective = Int(Double(player.overall) * Double(familiarity) / 100.0)
                    Text("~\(effective)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }
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

                    // #195: Salary
                    Text(formatSalary(player.annualSalary))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)

                    // #195: Trend arrow
                    let trend = developmentTrend(for: player)
                    Image(systemName: trend.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(trend.color)

                    // #195: Health icon
                    if player.isInjured {
                        Image(systemName: "cross.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.danger)
                    }
                }

                // #197: Versatility info for out-of-position
                if isVersatile {
                    let familiarity = player.familiarity(at: slot.position)
                    Text("\(player.position.rawValue) at \(slot.position.rawValue): \(player.overall) x \(familiarity)% = ~\(Int(Double(player.overall) * Double(familiarity) / 100.0)) effective")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.warning)
                }

                // #196: Comparison with current starter
                if let current = currentPlayer, current.id != player.id {
                    let diff = player.overall - current.overall
                    let diffStr = diff >= 0 ? "+\(diff)" : "\(diff)"
                    Text("vs \(current.lastName): \(current.overall) -> \(player.overall) (\(diffStr))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(diff >= 0 ? Color.success : Color.danger)
                }
            }

            Spacer()

            // Current assignment indicator
            if let current = currentPlayer, current.id == player.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentGold)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatSalary(_ thousands: Int) -> String {
        if thousands >= 1000 {
            let millions = Double(thousands) / 1000.0
            if millions == Double(Int(millions)) {
                return "$\(Int(millions))M"
            }
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }

    private func developmentTrend(for player: Player) -> DevelopmentTrend {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            return .improving
        } else if peak.contains(player.age) {
            return .stable
        } else {
            return .declining
        }
    }
}

// MARK: - Starter vs Backup Comparison Sheet (#192)

struct StarterBackupComparisonSheet: View {
    let slot: FormationSlot
    let starter: Player?
    let backups: [Player]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let starter = starter {
                    // Starter card
                    comparisonCard(player: starter, role: "Starter", highlight: true)

                    if backups.isEmpty {
                        Text("No backups at this position")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.textTertiary)
                            .padding()
                    } else {
                        Text("vs Backups")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.textTertiary)

                        ForEach(backups.prefix(3)) { backup in
                            let diff = backup.overall - starter.overall
                            comparisonCard(player: backup, role: "Backup (\(diff >= 0 ? "+" : "")\(diff))", highlight: false)
                        }
                    }
                } else {
                    Text("No starter assigned")
                        .foregroundStyle(Color.textTertiary)
                }

                Spacer()
            }
            .padding()
            .background(Color.backgroundPrimary)
            .navigationTitle("\(slot.label) Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
    }

    private func comparisonCard(player: Player, role: String, highlight: Bool) -> some View {
        HStack(spacing: 12) {
            Text("\(player.overall)")
                .font(.system(size: 22, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.forPlayerCardRating(player.overall))
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 8) {
                    Text(role)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(highlight ? Color.accentGold : Color.textSecondary)
                    Text("Age \(player.age)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    if player.isInjured {
                        Image(systemName: "cross.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.danger)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(highlight ? Color.accentGold : Color.surfaceBorder, lineWidth: highlight ? 1.5 : 0.5)
        )
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
        Color.forRating(value)
    }
}

// MARK: - Formation Layout

enum FormationLayout: Equatable {
    case offense
    case offense11Personnel
    case offense12Personnel
    case offenseShotgun
    case offenseSpread
    case defense
    case defense43
    case defense34
    case defenseNickel
    case defenseDime
    case specialTeams

    /// Available formation variants for the picker (#190)
    var availableFormations: [FormationLayout] {
        switch self {
        case .offense, .offense11Personnel, .offense12Personnel, .offenseShotgun, .offenseSpread:
            return [.offense11Personnel, .offense12Personnel, .offenseShotgun, .offenseSpread]
        case .defense, .defense43, .defense34, .defenseNickel, .defenseDime:
            return [.defense43, .defense34, .defenseNickel, .defenseDime]
        case .specialTeams:
            return [.specialTeams]
        }
    }

    /// Formation/scheme display name (#46)
    var formationName: String {
        switch self {
        case .offense, .offense11Personnel: return "11 Personnel"
        case .offense12Personnel:           return "12 Personnel"
        case .offenseShotgun:               return "Shotgun"
        case .offenseSpread:                return "Spread"
        case .defense, .defense43:          return "4-3 Defense"
        case .defense34:                    return "3-4 Defense"
        case .defenseNickel:                return "Nickel"
        case .defenseDime:                  return "Dime"
        case .specialTeams:                 return "Special Teams"
        }
    }

    /// Increased field heights for more screen real estate (#45 + #99 + #185)
    var fieldHeight: CGFloat {
        switch self {
        case .offense, .offense11Personnel, .offense12Personnel, .offenseShotgun, .offenseSpread:
            return 540
        case .defense, .defense43, .defense34, .defenseNickel, .defenseDime:
            return 540
        case .specialTeams:
            return 260
        }
    }

    var lineOfScrimmageY: CGFloat {
        switch self {
        case .offense, .offense11Personnel, .offense12Personnel, .offenseShotgun, .offenseSpread:
            return 0.30
        case .defense, .defense43, .defense34, .defenseNickel, .defenseDime:
            return 0.28
        case .specialTeams:
            return 0.5
        }
    }

    var slots: [FormationSlot] {
        switch self {
        case .offense, .offense11Personnel:
            return [
                // WR left + right (near top, by end zone)
                FormationSlot(position: .WR, label: "WR1", positionIndex: 0, xPercent: 0.08, yPercent: 0.25),
                FormationSlot(position: .WR, label: "WR2", positionIndex: 1, xPercent: 0.92, yPercent: 0.25),
                // OL line (LT on left, RT on right)
                FormationSlot(position: .LT, label: "LT", positionIndex: 0, xPercent: 0.28, yPercent: 0.30),
                FormationSlot(position: .LG, label: "LG", positionIndex: 0, xPercent: 0.38, yPercent: 0.30),
                FormationSlot(position: .C,  label: "C",  positionIndex: 0, xPercent: 0.50, yPercent: 0.30),
                FormationSlot(position: .RG, label: "RG", positionIndex: 0, xPercent: 0.62, yPercent: 0.30),
                FormationSlot(position: .RT, label: "RT", positionIndex: 0, xPercent: 0.72, yPercent: 0.30),
                // TE next to OL on right
                FormationSlot(position: .TE, label: "TE", positionIndex: 0, xPercent: 0.82, yPercent: 0.30),
                // QB behind OL
                FormationSlot(position: .QB, label: "QB", positionIndex: 0, xPercent: 0.50, yPercent: 0.48),
                // FB in front of RB
                FormationSlot(position: .FB, label: "FB", positionIndex: 0, xPercent: 0.35, yPercent: 0.55),
                // RB behind QB
                FormationSlot(position: .RB, label: "RB", positionIndex: 0, xPercent: 0.50, yPercent: 0.62),
            ]
        case .offense12Personnel:
            return [
                // WR (1 wide receiver on left)
                FormationSlot(position: .WR, label: "WR1", positionIndex: 0, xPercent: 0.08, yPercent: 0.25),
                // OL line (LT on left, RT on right)
                FormationSlot(position: .LT, label: "LT", positionIndex: 0, xPercent: 0.28, yPercent: 0.30),
                FormationSlot(position: .LG, label: "LG", positionIndex: 0, xPercent: 0.38, yPercent: 0.30),
                FormationSlot(position: .C,  label: "C",  positionIndex: 0, xPercent: 0.50, yPercent: 0.30),
                FormationSlot(position: .RG, label: "RG", positionIndex: 0, xPercent: 0.62, yPercent: 0.30),
                FormationSlot(position: .RT, label: "RT", positionIndex: 0, xPercent: 0.72, yPercent: 0.30),
                // 2 TE: TE1 right of OL, TE2 left of OL
                FormationSlot(position: .TE, label: "TE1", positionIndex: 0, xPercent: 0.82, yPercent: 0.30),
                FormationSlot(position: .TE, label: "TE2", positionIndex: 1, xPercent: 0.18, yPercent: 0.30),
                // QB behind OL
                FormationSlot(position: .QB, label: "QB", positionIndex: 0, xPercent: 0.50, yPercent: 0.48),
                // FB inline
                FormationSlot(position: .FB, label: "FB", positionIndex: 0, xPercent: 0.35, yPercent: 0.55),
                // RB behind QB
                FormationSlot(position: .RB, label: "RB", positionIndex: 0, xPercent: 0.50, yPercent: 0.62),
            ]
        case .offenseShotgun:
            return [
                // WR wide (near top)
                FormationSlot(position: .WR, label: "WR1", positionIndex: 0, xPercent: 0.05, yPercent: 0.25),
                FormationSlot(position: .WR, label: "WR2", positionIndex: 1, xPercent: 0.95, yPercent: 0.25),
                FormationSlot(position: .WR, label: "WR3", positionIndex: 2, xPercent: 0.18, yPercent: 0.30),
                // OL line (LT on left, RT on right)
                FormationSlot(position: .LT, label: "LT", positionIndex: 0, xPercent: 0.28, yPercent: 0.30),
                FormationSlot(position: .LG, label: "LG", positionIndex: 0, xPercent: 0.38, yPercent: 0.30),
                FormationSlot(position: .C,  label: "C",  positionIndex: 0, xPercent: 0.50, yPercent: 0.30),
                FormationSlot(position: .RG, label: "RG", positionIndex: 0, xPercent: 0.62, yPercent: 0.30),
                FormationSlot(position: .RT, label: "RT", positionIndex: 0, xPercent: 0.72, yPercent: 0.30),
                // TE next to OL on right
                FormationSlot(position: .TE, label: "TE", positionIndex: 0, xPercent: 0.82, yPercent: 0.30),
                // QB further back in shotgun
                FormationSlot(position: .QB, label: "QB", positionIndex: 0, xPercent: 0.50, yPercent: 0.52),
                // RB next to QB in shotgun
                FormationSlot(position: .RB, label: "RB", positionIndex: 0, xPercent: 0.38, yPercent: 0.52),
            ]
        case .offenseSpread:
            return [
                // 4 WR spread: WR1/WR2 wide at top, WR3/WR4 in slot at OL level
                FormationSlot(position: .WR, label: "WR1", positionIndex: 0, xPercent: 0.05, yPercent: 0.25),
                FormationSlot(position: .WR, label: "WR2", positionIndex: 1, xPercent: 0.95, yPercent: 0.25),
                FormationSlot(position: .WR, label: "WR3", positionIndex: 2, xPercent: 0.15, yPercent: 0.30),
                FormationSlot(position: .WR, label: "WR4", positionIndex: 3, xPercent: 0.85, yPercent: 0.30),
                // OL line (LT on left, RT on right)
                FormationSlot(position: .LT, label: "LT", positionIndex: 0, xPercent: 0.28, yPercent: 0.30),
                FormationSlot(position: .LG, label: "LG", positionIndex: 0, xPercent: 0.38, yPercent: 0.30),
                FormationSlot(position: .C,  label: "C",  positionIndex: 0, xPercent: 0.50, yPercent: 0.30),
                FormationSlot(position: .RG, label: "RG", positionIndex: 0, xPercent: 0.62, yPercent: 0.30),
                FormationSlot(position: .RT, label: "RT", positionIndex: 0, xPercent: 0.72, yPercent: 0.30),
                // QB behind OL
                FormationSlot(position: .QB, label: "QB", positionIndex: 0, xPercent: 0.50, yPercent: 0.48),
                // RB behind QB
                FormationSlot(position: .RB, label: "RB", positionIndex: 0, xPercent: 0.50, yPercent: 0.58),
            ]
        case .defense, .defense43:
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
        case .defense34:
            // 3-4 defense: 3 DL + 4 LB + 4 DB
            return [
                FormationSlot(position: .DE, label: "LE",  positionIndex: 0, xPercent: 0.22, yPercent: 0.32),
                FormationSlot(position: .DT, label: "NT",  positionIndex: 0, xPercent: 0.50, yPercent: 0.32),
                FormationSlot(position: .DE, label: "RE",  positionIndex: 1, xPercent: 0.78, yPercent: 0.32),
                // 4 LBs
                FormationSlot(position: .OLB, label: "LOLB", positionIndex: 0, xPercent: 0.12, yPercent: 0.48),
                FormationSlot(position: .MLB, label: "MLB1", positionIndex: 0, xPercent: 0.38, yPercent: 0.48),
                FormationSlot(position: .MLB, label: "MLB2", positionIndex: 1, xPercent: 0.62, yPercent: 0.48),
                FormationSlot(position: .OLB, label: "ROLB", positionIndex: 1, xPercent: 0.88, yPercent: 0.48),
                // DB
                FormationSlot(position: .CB, label: "CB1", positionIndex: 0, xPercent: 0.08, yPercent: 0.68),
                FormationSlot(position: .CB, label: "CB2", positionIndex: 1, xPercent: 0.92, yPercent: 0.68),
                FormationSlot(position: .FS, label: "FS",  positionIndex: 0, xPercent: 0.38, yPercent: 0.85),
                FormationSlot(position: .SS, label: "SS",  positionIndex: 0, xPercent: 0.62, yPercent: 0.85),
            ]
        case .defenseNickel:
            // Nickel: 4 DL + 2 LB + 5 DB (3 CB)
            return [
                FormationSlot(position: .DE, label: "LE",  positionIndex: 0, xPercent: 0.18, yPercent: 0.32),
                FormationSlot(position: .DT, label: "DT1", positionIndex: 0, xPercent: 0.38, yPercent: 0.32),
                FormationSlot(position: .DT, label: "DT2", positionIndex: 1, xPercent: 0.62, yPercent: 0.32),
                FormationSlot(position: .DE, label: "RE",  positionIndex: 1, xPercent: 0.82, yPercent: 0.32),
                // 2 LB
                FormationSlot(position: .MLB, label: "MLB", positionIndex: 0, xPercent: 0.35, yPercent: 0.48),
                FormationSlot(position: .OLB, label: "OLB", positionIndex: 0, xPercent: 0.65, yPercent: 0.48),
                // 5 DB: 3 CB + FS + SS
                FormationSlot(position: .CB, label: "CB1", positionIndex: 0, xPercent: 0.05, yPercent: 0.68),
                FormationSlot(position: .CB, label: "CB2", positionIndex: 1, xPercent: 0.95, yPercent: 0.68),
                FormationSlot(position: .CB, label: "NCB", positionIndex: 2, xPercent: 0.50, yPercent: 0.60),
                FormationSlot(position: .FS, label: "FS",  positionIndex: 0, xPercent: 0.35, yPercent: 0.85),
                FormationSlot(position: .SS, label: "SS",  positionIndex: 0, xPercent: 0.65, yPercent: 0.85),
            ]
        case .defenseDime:
            // Dime: 4 DL + 1 LB + 6 DB (4 CB)
            return [
                FormationSlot(position: .DE, label: "LE",  positionIndex: 0, xPercent: 0.18, yPercent: 0.32),
                FormationSlot(position: .DT, label: "DT1", positionIndex: 0, xPercent: 0.38, yPercent: 0.32),
                FormationSlot(position: .DT, label: "DT2", positionIndex: 1, xPercent: 0.62, yPercent: 0.32),
                FormationSlot(position: .DE, label: "RE",  positionIndex: 1, xPercent: 0.82, yPercent: 0.32),
                // 1 LB
                FormationSlot(position: .MLB, label: "MLB", positionIndex: 0, xPercent: 0.50, yPercent: 0.48),
                // 6 DB: 4 CB + FS + SS
                FormationSlot(position: .CB, label: "CB1", positionIndex: 0, xPercent: 0.05, yPercent: 0.65),
                FormationSlot(position: .CB, label: "CB2", positionIndex: 1, xPercent: 0.95, yPercent: 0.65),
                FormationSlot(position: .CB, label: "NCB", positionIndex: 2, xPercent: 0.35, yPercent: 0.58),
                FormationSlot(position: .CB, label: "DCB", positionIndex: 3, xPercent: 0.65, yPercent: 0.58),
                FormationSlot(position: .FS, label: "FS",  positionIndex: 0, xPercent: 0.35, yPercent: 0.85),
                FormationSlot(position: .SS, label: "SS",  positionIndex: 0, xPercent: 0.65, yPercent: 0.85),
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
