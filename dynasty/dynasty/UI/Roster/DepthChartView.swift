import SwiftUI
import SwiftData

// MARK: - Main View

struct DepthChartView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Query private var allPlayers: [Player]

    @State private var depthChart = DepthChart()
    @State private var selectedTab: PositionSide = .offense
    @State private var comparisonState: ComparisonState? = nil
    /// Tracks which slots are collapsed. By default all are expanded.
    @State private var collapsedSlots: Set<String> = []
    /// Tracks which position groups are collapsed (e.g. "DL", "LB").
    @State private var collapsedGroups: Set<String> = []

    // MARK: - Derived roster

    private var rosterPlayers: [Player] {
        guard let teamID = career.teamID else { return [] }
        return allPlayers.filter { $0.teamID == teamID }
    }

    private var playerLookup: [UUID: Player] {
        Dictionary(uniqueKeysWithValues: rosterPlayers.map { ($0.id, $0) })
    }

    // MARK: - Slot groups

    private var activeSlots: [DepthChartSlot] {
        switch selectedTab {
        case .offense:      return DepthChartSlot.offenseSlots
        case .defense:      return DepthChartSlot.defenseSlots
        case .specialTeams: return DepthChartSlot.specialTeamsSlots
        }
    }

    // MARK: - Grouped Slots

    /// A position group containing related depth chart slots, used for collapse/expand.
    private struct SlotGroup: Identifiable {
        let id: String
        let name: String
        let icon: String
        let slots: [DepthChartSlot]
    }

    /// Returns slots grouped by position family for the active tab.
    private var activeSlotGroups: [SlotGroup] {
        switch selectedTab {
        case .offense:
            return [
                SlotGroup(id: "QB", name: "Quarterbacks", icon: "figure.american.football", slots: [.QB]),
                SlotGroup(id: "Backfield", name: "Backfield", icon: "figure.run", slots: [.RB, .FB]),
                SlotGroup(id: "Receivers", name: "Receivers", icon: "hand.wave", slots: [.WR1, .WR2, .WR3, .TE]),
                SlotGroup(id: "OL", name: "Offensive Line", icon: "shield.lefthalf.filled", slots: [.LT, .LG, .C, .RG, .RT]),
            ]
        case .defense:
            return [
                SlotGroup(id: "DL", name: "Defensive Line", icon: "bolt.shield", slots: [.LE, .DT, .RE]),
                SlotGroup(id: "LB", name: "Linebackers", icon: "shield", slots: [.LOLB, .MLB, .ROLB]),
                SlotGroup(id: "DB", name: "Secondary", icon: "eye", slots: [.CB1, .CB2, .FS, .SS]),
            ]
        case .specialTeams:
            return [
                SlotGroup(id: "Kickers", name: "Kickers & Punters", icon: "sportscourt", slots: [.K, .P]),
                SlotGroup(id: "Returners", name: "Returners", icon: "arrow.uturn.backward", slots: [.KR, .PR]),
            ]
        }
    }

    // MARK: - Team OVR

    private var teamOVR: Int {
        depthChart.teamOverall(lookup: playerLookup)
    }

    private var offenseOVR: Int {
        depthChart.offenseOverall(lookup: playerLookup)
    }

    private var defenseOVR: Int {
        depthChart.defenseOverall(lookup: playerLookup)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                teamOverallBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                tabBar
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ScrollView {
                    LazyVStack(spacing: 14) {
                        // Collapse-all / expand-all controls
                        groupCollapseControls
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        ForEach(activeSlotGroups) { group in
                            groupSection(group)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 16)
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
        .sheet(item: $comparisonState) { state in
            ComparisonSheet(
                slot: state.slot,
                slotIndex: state.slotIndex,
                rosterPlayers: rosterPlayers,
                depthChart: depthChart,
                playerLookup: playerLookup,
                onSelect: { playerID in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        depthChart.assign(slot: state.slot, playerID: playerID, at: state.slotIndex)
                    }
                    persistDepthChart()
                    comparisonState = nil
                },
                onClear: {
                    if let currentDepth = depthChart.depthOrder(for: state.slot)[safe: state.slotIndex] {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            depthChart.remove(slot: state.slot, playerID: currentDepth)
                        }
                        persistDepthChart()
                    }
                    comparisonState = nil
                },
                onDismiss: { comparisonState = nil }
            )
        }
        .task {
            loadOrSeedDepthChart()
        }
    }

    // MARK: - Persistence

    /// Loads the saved chart from the career, seeding a fresh auto-generated
    /// chart (without persisting it) when none has been saved yet. The chart
    /// is only persisted on explicit user action so the "Set depth chart"
    /// task completes from a real decision, not a screen visit.
    private func loadOrSeedDepthChart() {
        if let data = career.depthChartData,
           let saved = try? JSONDecoder().decode(DepthChart.self, from: data) {
            depthChart = saved
        } else {
            depthChart.autoGenerate(players: rosterPlayers)
        }
    }

    /// Writes the current chart back to the career and saves the context.
    /// Called after every user mutation (assign / clear / reorder / auto-set).
    private func persistDepthChart() {
        career.depthChartData = try? JSONEncoder().encode(depthChart)
        try? modelContext.save()
    }

    // MARK: - Team Overall Bar

    private var teamOverallBar: some View {
        HStack(spacing: 16) {
            ovrPill(label: "TEAM", value: teamOVR)
            Spacer()
            ovrPill(label: "OFF", value: offenseOVR)
            ovrPill(label: "DEF", value: defenseOVR)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func ovrPill(label: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textTertiary)
            Text("\(value)")
                .font(.system(size: 16, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
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
            persistDepthChart()
        } label: {
            Label("Auto-Set", systemImage: "wand.and.stars")
        }
        .foregroundStyle(Color.accentGold)
        .accessibilityLabel("Auto-fill depth chart by overall rating")
    }

    // MARK: - Group Collapse Controls

    private var groupCollapseControls: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet.indent")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
            Text("\(activeSlotGroups.count) groups · \(activeSlots.count) positions")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if collapsedGroups.intersection(activeSlotGroups.map(\.id)).count == activeSlotGroups.count {
                        // All collapsed → expand all
                        for g in activeSlotGroups { collapsedGroups.remove(g.id) }
                    } else {
                        // Collapse all
                        for g in activeSlotGroups { collapsedGroups.insert(g.id) }
                    }
                }
            } label: {
                let allCollapsed = collapsedGroups.intersection(activeSlotGroups.map(\.id)).count == activeSlotGroups.count
                HStack(spacing: 3) {
                    Image(systemName: allCollapsed ? "chevron.down.square" : "chevron.up.square")
                        .font(.system(size: 11, weight: .semibold))
                    Text(allCollapsed ? "Expand all" : "Collapse all")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.accentBlue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(collapsedGroups.intersection(activeSlotGroups.map(\.id)).count == activeSlotGroups.count ? "Expand all groups" : "Collapse all groups")
        }
    }

    // MARK: - Group Section

    private func groupSection(_ group: SlotGroup) -> some View {
        let isCollapsed = collapsedGroups.contains(group.id)
        let groupSlots = group.slots
        let filledStarters = groupSlots.filter { depthChart.depthOrder(for: $0).first.flatMap { playerLookup[$0] } != nil }.count
        let starterAvg: Int = {
            let starters = groupSlots.compactMap { slot -> Int? in
                guard let pid = depthChart.depthOrder(for: slot).first, let p = playerLookup[pid] else { return nil }
                return p.overall
            }
            return starters.isEmpty ? 0 : starters.reduce(0, +) / starters.count
        }()

        return VStack(spacing: 10) {
            // Group header (tappable to collapse/expand)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedGroups.remove(group.id)
                    } else {
                        collapsedGroups.insert(group.id)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.accentGold)
                        .frame(width: 14)
                    Image(systemName: group.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(group.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    // Filled count
                    HStack(spacing: 3) {
                        Image(systemName: filledStarters == groupSlots.count ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 10))
                        Text("\(filledStarters)/\(groupSlots.count)")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(filledStarters == groupSlots.count ? Color.success : Color.warning)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (filledStarters == groupSlots.count ? Color.success : Color.warning).opacity(0.12),
                        in: Capsule()
                    )
                    // Average starter OVR
                    if starterAvg > 0 {
                        Text("AVG \(starterAvg)")
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.forRating(starterAvg))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.forRating(starterAvg).opacity(0.12), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.forRating(starterAvg).opacity(0.3), lineWidth: 0.5))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.name), \(filledStarters) of \(groupSlots.count) starters filled, \(isCollapsed ? "collapsed, tap to expand" : "expanded, tap to collapse")")

            // Slots — only render when expanded
            if !isCollapsed {
                VStack(spacing: 10) {
                    ForEach(groupSlots) { slot in
                        slotCard(slot: slot)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
    }

    // MARK: - Slot Card

    private func slotCard(slot: DepthChartSlot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                slotBadge(slot)
                Text(slot.shortLabel)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(slot.displayName)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            // Depth slots in a vertical list (drag-to-reorder)
            let depth = depthChart.depthOrder(for: slot)
            let maxSlots = slot.maxDepth

            VStack(spacing: 6) {
                ForEach(0..<maxSlots, id: \.self) { index in
                    let playerID = depth[safe: index]
                    let player = playerID.flatMap { playerLookup[$0] }
                    depthSlotRow(
                        slot: slot,
                        index: index,
                        player: player,
                        totalInSlot: depth.count
                    )
                }
            }
        }
        .padding(14)
        .cardBackground()
    }

    // MARK: - Depth Slot Row

    private func depthSlotRow(
        slot: DepthChartSlot,
        index: Int,
        player: Player?,
        totalInSlot: Int
    ) -> some View {
        let isStarter = index == 0

        return HStack(spacing: 10) {
            // Reorder buttons
            if let _ = player, totalInSlot > 1 {
                VStack(spacing: 2) {
                    Button {
                        guard index > 0 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            depthChart.swap(slot: slot, indexA: index, indexB: index - 1)
                        }
                        persistDepthChart()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(index > 0 ? Color.textSecondary : Color.backgroundTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == 0)

                    Button {
                        guard index < totalInSlot - 1 else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            depthChart.swap(slot: slot, indexA: index, indexB: index + 1)
                        }
                        persistDepthChart()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(index < totalInSlot - 1 ? Color.textSecondary : Color.backgroundTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(index >= totalInSlot - 1)
                }
                .frame(width: 20)
            } else {
                Color.clear.frame(width: 20, height: 1)
            }

            // Slot label
            Text(depthLabel(index: index))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isStarter ? Color.accentGold : Color.textTertiary)
                .textCase(.uppercase)
                .frame(width: 48, alignment: .leading)

            // Player info or empty
            Button {
                comparisonState = ComparisonState(slot: slot, slotIndex: index)
            } label: {
                if let player {
                    playerSlotContent(player: player, slot: slot, isStarter: isStarter)
                } else {
                    emptySlotContent()
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isStarter ? Color.accentGold.opacity(0.06) : Color.backgroundTertiary.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isStarter ? Color.accentGold.opacity(0.3) : Color.surfaceBorder.opacity(0.5),
                            lineWidth: isStarter ? 1 : 0.5
                        )
                )
        )
        .accessibilityLabel(slotAccessibilityLabel(index: index, player: player))
    }

    // MARK: - Player Slot Content

    private func playerSlotContent(player: Player, slot: DepthChartSlot, isStarter: Bool) -> some View {
        HStack(spacing: 8) {
            // Player name
            VStack(alignment: .leading, spacing: 1) {
                Text(player.fullName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                HStack(spacing: 6) {
                    Text(player.position.rawValue)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)

                    Text("Age \(player.age)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)

                    Text("$\(player.annualSalary / 1000)M")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            // Indicators
            HStack(spacing: 6) {
                // Wrong position indicator
                if !slot.acceptsAnyPosition && player.position != slot.basePosition {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.warning)
                        .help("Playing out of natural position")
                }

                // Injury icon
                if player.isInjured {
                    HStack(spacing: 2) {
                        Image(systemName: "cross.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.danger)
                        if player.injuryWeeksRemaining > 0 {
                            Text("\(player.injuryWeeksRemaining)w")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.danger)
                        }
                    }
                }

                // Fatigue bar
                if player.fatigue > 0 {
                    fatigueMeter(value: player.fatigue)
                }

                // OVR rating badge
                ratingBadge(value: player.overall)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Empty Slot Content

    private func emptySlotContent() -> some View {
        HStack {
            Image(systemName: "plus.circle.dashed")
                .font(.system(size: 14))
                .foregroundStyle(Color.textTertiary)
            Text("Tap to assign")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .contentShape(Rectangle())
    }

    // MARK: - Rating Badge

    private func ratingBadge(value: Int) -> some View {
        Text("\(value)")
            .font(.system(size: 13, weight: .bold).monospacedDigit())
            .foregroundStyle(Color.forRating(value))
            .frame(width: 34, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.forRating(value).opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.forRating(value).opacity(0.3), lineWidth: 1)
                    )
            )
    }

    // MARK: - Fatigue Meter

    private func fatigueMeter(value: Int) -> some View {
        VStack(spacing: 1) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 7))
                .foregroundStyle(fatigueColor(value))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.backgroundTertiary)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(fatigueColor(value))
                        .frame(width: geo.size.width * CGFloat(value) / 100.0)
                }
            }
            .frame(width: 20, height: 3)
        }
    }

    private func fatigueColor(_ value: Int) -> Color {
        switch value {
        case 70...:  return .danger
        case 40..<70: return .warning
        default:     return .success
        }
    }

    // MARK: - Slot Badge

    private func slotBadge(_ slot: DepthChartSlot) -> some View {
        Text(slot.shortLabel)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Color.backgroundPrimary)
            .frame(minWidth: 28, minHeight: 20)
            .padding(.horizontal, 4)
            .background(sideColor(slot.side), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Helpers

    private func sideColor(_ side: PositionSide) -> Color {
        switch side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func depthLabel(index: Int) -> String {
        switch index {
        case 0: return "Starter"
        case 1: return "Backup"
        case 2: return "3rd String"
        default: return "Depth \(index + 1)"
        }
    }

    private func slotAccessibilityLabel(index: Int, player: Player?) -> String {
        let slot = depthLabel(index: index)
        if let player {
            return "\(slot): \(player.fullName), overall \(player.overall)"
        }
        return "\(slot): empty, tap to assign"
    }
}

// MARK: - Comparison State

private struct ComparisonState: Identifiable {
    let id = UUID()
    let slot: DepthChartSlot
    let slotIndex: Int
}

// MARK: - Comparison Sheet

private struct ComparisonSheet: View {

    let slot: DepthChartSlot
    let slotIndex: Int
    let rosterPlayers: [Player]
    let depthChart: DepthChart
    let playerLookup: [UUID: Player]
    let onSelect: (UUID) -> Void
    let onClear: () -> Void
    let onDismiss: () -> Void

    @State private var sortMode: ComparisonSort = .overall

    private enum ComparisonSort: String, CaseIterable {
        case overall = "Overall"
        case fit = "Position Fit"
        case age = "Age"
    }

    // MARK: - Candidate Players

    /// Returns all players who could fill this slot, including out-of-position candidates.
    private var candidates: [CandidatePlayer] {
        rosterPlayers.map { player in
            let isNatural = player.position == slot.basePosition
            let versatility = VersatilityEngine.rate(player: player, at: slot.basePosition)
            let isViable = isNatural || versatility.rawValue >= VersatilityRating.unconvincing.rawValue
            let ovrDelta = depthChart.impactOfAssigning(
                playerID: player.id,
                toSlot: slot,
                at: slotIndex,
                lookup: playerLookup
            )
            return CandidatePlayer(
                player: player,
                isNatural: isNatural,
                versatility: versatility,
                isViable: isViable,
                ovrDelta: ovrDelta
            )
        }
        .filter { $0.isViable || slot.acceptsAnyPosition }
        .sorted { sortCandidate($0, $1) }
    }

    private func sortCandidate(_ a: CandidatePlayer, _ b: CandidatePlayer) -> Bool {
        switch sortMode {
        case .overall:
            // Returner slots rank by the trait that actually matters back deep
            // (speed for KR, agility for PR) — raw overall would put QBs on top.
            if slot == .KR {
                return a.player.physical.speed > b.player.physical.speed
            }
            if slot == .PR {
                return a.player.physical.agility > b.player.physical.agility
            }
            return a.player.overall > b.player.overall
        case .fit:
            if a.versatility != b.versatility {
                return a.versatility > b.versatility
            }
            return a.player.overall > b.player.overall
        case .age:
            return a.player.age < b.player.age
        }
    }

    private var currentPlayerID: UUID? {
        depthChart.depthOrder(for: slot)[safe: slotIndex]
    }

    private var slotLabel: String {
        switch slotIndex {
        case 0: return "Starter"
        case 1: return "Backup"
        case 2: return "3rd String"
        default: return "Depth \(slotIndex + 1)"
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Impact header
                    if let currentID = currentPlayerID, let current = playerLookup[currentID] {
                        currentPlayerHeader(current)
                    }

                    // Sort picker
                    sortPicker

                    // Candidate list
                    List {
                        Section {
                            Button(action: onClear) {
                                HStack {
                                    Image(systemName: "xmark.circle")
                                        .foregroundStyle(Color.textTertiary)
                                    Text("Clear Slot")
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                        .listRowBackground(Color.backgroundSecondary)

                        Section("Candidates (\(candidates.count))") {
                            if candidates.isEmpty {
                                Text("No viable players for \(slot.shortLabel)")
                                    .foregroundStyle(Color.textTertiary)
                                    .font(.subheadline)
                            } else {
                                ForEach(candidates, id: \.player.id) { candidate in
                                    Button {
                                        onSelect(candidate.player.id)
                                    } label: {
                                        candidateRow(candidate)
                                    }
                                    .listRowBackground(
                                        candidate.player.id == currentPlayerID
                                            ? Color.accentGold.opacity(0.08)
                                            : Color.backgroundSecondary
                                    )
                                }
                            }
                        }
                        .listRowBackground(Color.backgroundSecondary)
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("\(slot.shortLabel) — \(slotLabel)")
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

    // MARK: - Current Player Header

    private func currentPlayerHeader(_ player: Player) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Current: \(player.fullName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 8) {
                    Text("\(player.position.rawValue) · \(player.overall) OVR")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    if player.isInjured {
                        Label("Injured", systemImage: "cross.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.danger)
                    }
                }
            }
            Spacer()
            Text("\(player.overall)")
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
        }
        .padding(16)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Sort Picker

    private var sortPicker: some View {
        Picker("Sort", selection: $sortMode) {
            ForEach(ComparisonSort.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Candidate Row

    private func candidateRow(_ candidate: CandidatePlayer) -> some View {
        let player = candidate.player
        let isCurrent = player.id == currentPlayerID
        let isInDepthChart = depthChart.depthOrder(for: slot).contains(player.id)

        return HStack(spacing: 10) {
            // Position badge
            Text(player.position.rawValue)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.backgroundPrimary)
                .frame(width: 28, height: 18)
                .background(positionColor(player.position.side), in: RoundedRectangle(cornerRadius: 3))

            // Player info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    if isCurrent {
                        Text("Current")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentGold.opacity(0.15)))
                    }
                }
                HStack(spacing: 6) {
                    Text("Age \(player.age)")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(player.yearsPro == 0 ? "Rookie" : "\(player.yearsPro)yr pro")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)

                    // Versatility rating
                    if !candidate.isNatural && !slot.acceptsAnyPosition {
                        Text(candidate.versatility.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(candidate.versatility.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(candidate.versatility.color.opacity(0.12))
                            )
                    }
                }
            }

            Spacer()

            // Indicators column
            VStack(alignment: .trailing, spacing: 2) {
                // OVR impact delta
                if candidate.ovrDelta != 0 && !isCurrent {
                    HStack(spacing: 2) {
                        Image(systemName: candidate.ovrDelta > 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(abs(candidate.ovrDelta))")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                    }
                    .foregroundStyle(candidate.ovrDelta > 0 ? Color.success : Color.danger)
                }

                // Injury status
                if player.isInjured {
                    HStack(spacing: 2) {
                        Image(systemName: "cross.circle.fill")
                            .foregroundStyle(Color.danger)
                            .font(.system(size: 10))
                        if player.injuryWeeksRemaining > 0 {
                            Text("\(player.injuryWeeksRemaining)w")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.danger)
                        }
                    }
                }
            }

            // Depth chart status
            if isInDepthChart && !isCurrent {
                Text("In Chart")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentGold.opacity(0.15)))
            }

            // OVR badge
            Text("\(player.overall)")
                .font(.callout.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func positionColor(_ side: PositionSide) -> Color {
        switch side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }
}

// MARK: - Candidate Player

private struct CandidatePlayer {
    let player: Player
    let isNatural: Bool
    let versatility: VersatilityRating
    let isViable: Bool
    let ovrDelta: Int
}

// MARK: - Safe Collection Index

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
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
