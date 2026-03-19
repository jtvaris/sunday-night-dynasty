import SwiftUI

struct RosterView: View {
    let players: [Player]
    /// The team's current salary cap in thousands. Falls back to 255_000 if not provided.
    var teamSalaryCap: Int = 255_000

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    /// True when in landscape on iPad (regular width, compact height) or wide layout.
    private var isLandscape: Bool {
        verticalSizeClass == .compact || (horizontalSizeClass == .regular && verticalSizeClass == .compact)
    }

    /// True when on iPad with regular width (both orientations).
    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    // MARK: - State

    @State private var selectedSide: RosterFilter = .offense
    @State private var sortOrder: RosterSort = .overall
    @State private var sortAscending: Bool = false
    @State private var viewMode: RosterViewMode = .list
    @State private var analysisMode: RosterAnalysisMode = .overview
    /// Custom depth ordering per position. When a user promotes/demotes a player,
    /// their manual ordering is stored here and takes priority over OVR-based sorting.
    @State private var customDepthOrder: [Position: [UUID]] = [:]
    @State private var positionPickerPlayer: Player? = nil
    @State private var starterPickerPosition: Position? = nil

    /// Track whether the user has seen the sort hint.
    @AppStorage("rosterSortHintSeen") private var sortHintSeen: Bool = false

    // MARK: - Position Groups (NFL-style names)

    private static let offenseGroups: [PositionGroup] = [
        PositionGroup(name: "QB Room", positions: [.QB]),
        PositionGroup(name: "Backfield", positions: [.RB, .FB]),
        PositionGroup(name: "Wide Receivers", positions: [.WR]),
        PositionGroup(name: "Tight Ends", positions: [.TE]),
        PositionGroup(name: "Offensive Line", positions: [.LT, .LG, .C, .RG, .RT]),
    ]

    private static let defenseGroups: [PositionGroup] = [
        PositionGroup(name: "Defensive Line", positions: [.DE, .DT]),
        PositionGroup(name: "Linebackers", positions: [.OLB, .MLB]),
        PositionGroup(name: "Secondary", positions: [.CB, .FS, .SS]),
    ]

    private static let specialTeamsGroups: [PositionGroup] = [
        PositionGroup(name: "Specialists", positions: [.K, .P]),
    ]

    // MARK: - Computed

    private var filteredPlayers: [Player] {
        let filtered: [Player]
        switch selectedSide {
        case .offense:
            filtered = players.filter { $0.position.side == .offense }
        case .defense:
            filtered = players.filter { $0.position.side == .defense }
        case .specialTeams:
            filtered = players.filter { $0.position.side == .specialTeams }
        }

        let asc = sortAscending
        switch sortOrder {
        case .overall:
            return filtered.sorted { asc ? $0.overall < $1.overall : $0.overall > $1.overall }
        case .position:
            return filtered.sorted {
                let sideOrder = positionSideOrder($0.position.side, $1.position.side)
                if sideOrder != 0 { return asc ? sideOrder > 0 : sideOrder < 0 }
                let posOrder = Position.allCases.firstIndex(of: $0.position)! -
                               Position.allCases.firstIndex(of: $1.position)!
                if posOrder != 0 { return asc ? posOrder > 0 : posOrder < 0 }
                return $0.overall > $1.overall
            }
        case .age:
            return filtered.sorted { asc ? $0.age > $1.age : $0.age < $1.age }
        case .salary:
            return filtered.sorted { asc ? $0.annualSalary < $1.annualSalary : $0.annualSalary > $1.annualSalary }
        case .name:
            return filtered.sorted { asc ? $0.lastName > $1.lastName : $0.lastName < $1.lastName }
        }
    }

    private var activeGroups: [PositionGroup] {
        switch selectedSide {
        case .offense:
            return Self.offenseGroups
        case .defense:
            return Self.defenseGroups
        case .specialTeams:
            return Self.specialTeamsGroups
        }
    }

    /// Name of the weakest position group on the current side (lowest average OVR).
    private var weakestGroupName: String? {
        var worst: (name: String, avg: Double)? = nil
        for group in activeGroups {
            let groupPlayers = filteredPlayers.filter { group.positions.contains($0.position) }
            guard !groupPlayers.isEmpty else { continue }
            let avg = Double(groupPlayers.reduce(0) { $0 + $1.overall }) / Double(groupPlayers.count)
            if worst == nil || avg < worst!.avg {
                worst = (group.name, avg)
            }
        }
        return worst?.name
    }

    // MARK: - Depth Index Helper

    /// Computes a depth index for a player within their position group.
    /// Uses custom ordering if available, otherwise falls back to OVR-based ranking.
    private func depthIndex(for player: Player, in groupPlayers: [Player]) -> Int {
        let posPlayers = groupPlayers.filter { $0.position == player.position }
        if let customOrder = customDepthOrder[player.position] {
            if let idx = customOrder.firstIndex(of: player.id) {
                return idx
            }
        }
        let sorted = posPlayers.sorted { $0.overall > $1.overall }
        return sorted.firstIndex(where: { $0.id == player.id }) ?? sorted.count
    }

    /// Returns all players at a given position sorted by custom depth or OVR.
    private func depthSortedPlayers(at position: Position, from groupPlayers: [Player]) -> [Player] {
        let posPlayers = groupPlayers.filter { $0.position == position }
        if let customOrder = customDepthOrder[position] {
            return posPlayers.sorted { a, b in
                let idxA = customOrder.firstIndex(of: a.id) ?? Int.max
                let idxB = customOrder.firstIndex(of: b.id) ?? Int.max
                return idxA < idxB
            }
        }
        return posPlayers.sorted { $0.overall > $1.overall }
    }

    /// Handles a depth change request: moves a player to a new depth index at their position.
    private func handleDepthChange(player: Player, newIndex: Int, groupPlayers: [Player]) {
        let position = player.position
        let posPlayers = groupPlayers.filter { $0.position == position }

        // Build current ordered list (custom or OVR-based)
        var ordered: [UUID]
        if let existing = customDepthOrder[position] {
            // Start from existing custom order, adding any missing players
            let existingSet = Set(existing)
            let newIDs = posPlayers.filter { !existingSet.contains($0.id) }
                .sorted { $0.overall > $1.overall }
                .map { $0.id }
            ordered = existing + newIDs
            // Remove players no longer in the group
            let validIDs = Set(posPlayers.map { $0.id })
            ordered = ordered.filter { validIDs.contains($0) }
        } else {
            ordered = posPlayers.sorted { $0.overall > $1.overall }.map { $0.id }
        }

        guard let currentIndex = ordered.firstIndex(of: player.id) else { return }
        let clampedNew = max(0, min(newIndex, ordered.count - 1))
        guard clampedNew != currentIndex else { return }

        ordered.remove(at: currentIndex)
        ordered.insert(player.id, at: clampedNew)
        customDepthOrder[position] = ordered
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            // Subtle locker room background image (#94)
            GeometryReader { geo in
                Image("BgLockerRoom2")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.12)
            }
            .ignoresSafeArea()
            .overlay(
                LinearGradient(
                    colors: [Color.backgroundPrimary.opacity(0.6), Color.clear, Color.backgroundPrimary.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            VStack(spacing: 0) {
                RosterSummaryBar(players: players, teamSalaryCap: teamSalaryCap)

                viewModePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                if viewMode == .list {
                    analysisModePicker
                        .padding(.horizontal)
                        .padding(.bottom, 6)

                    listContent
                } else {
                    formationContent
                }
            }
        }
        .navigationTitle("Roster (\(players.count))")
        .sheet(item: $positionPickerPlayer) { player in
            positionPickerSheet(for: player)
        }
        .sheet(item: $starterPickerPosition) { position in
            starterPickerSheet(for: position)
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                filterPicker
            }
            ToolbarItem(placement: .primaryAction) {
                sortMenu
            }
        }
    }

    // MARK: - View Mode Picker

    private var viewModePicker: some View {
        Picker("View Mode", selection: $viewMode) {
            ForEach(RosterViewMode.allCases) { mode in
                Label(mode.label, systemImage: mode.icon).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Analysis Mode Picker (#96, #98)

    private var analysisModePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(RosterAnalysisMode.allCases) { mode in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            analysisMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 10))
                            Text(mode.label)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(analysisMode == mode ? Color.backgroundPrimary : Color.textSecondary)
                        .background(
                            analysisMode == mode ? Color.accentGold : Color.backgroundTertiary,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    analysisMode == mode ? Color.accentGold : Color.surfaceBorder,
                                    lineWidth: 1
                                )
                        )
                    }
                    .accessibilityLabel("Analysis mode: \(mode.label)")
                }
            }
        }
    }

    // MARK: - List Content

    private var listContent: some View {
        List {
            sortableHeader

            ForEach(activeGroups) { group in
                let groupPlayers = filteredPlayers.filter { group.positions.contains($0.position) }
                if !groupPlayers.isEmpty {
                    Section {
                        ForEach(groupPlayers) { player in
                            let posPlayers = groupPlayers.filter { $0.position == player.position }
                            NavigationLink(destination: PlayerDetailView(player: player)) {
                                PlayerRowView(
                                    player: player,
                                    depthIndex: depthIndex(for: player, in: groupPlayers),
                                    analysisMode: analysisMode,
                                    positionGroupCount: posPlayers.count,
                                    onDepthChange: { newIndex in
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            handleDepthChange(player: player, newIndex: newIndex, groupPlayers: groupPlayers)
                                        }
                                    },
                                    onPositionBadgeTap: {
                                        positionPickerPlayer = player
                                    },
                                    onStarterBadgeTap: {
                                        starterPickerPosition = player.position
                                    }
                                )
                            }
                            .listRowBackground(Color.backgroundSecondary)
                        }
                    } header: {
                        PositionGroupHeader(
                            group: group,
                            players: groupPlayers,
                            isWeakest: group.name == weakestGroupName
                        )
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    // MARK: - Sortable Header

    private var sortableHeader: some View {
        VStack(spacing: 4) {
            if !sortHintSeen {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 9))
                    Text("Tap column headers to sort")
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundStyle(Color.accentGold)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation { sortHintSeen = true }
                    }
                }
            }
            HStack(spacing: 0) {
                sortButton("POS", sort: .position, width: isWideLayout ? 56 : 44)
                sortButton("NAME", sort: .name, width: nil)
                Spacer()
                analysisHeaderColumns
            }
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 4)
        .listRowBackground(Color.backgroundPrimary)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    @ViewBuilder
    private var analysisHeaderColumns: some View {
        switch analysisMode {
        case .overview:
            Group {
                sortButton("Age", sort: .age, width: 32)
                headerLabel("Form", width: 24)
                sortButton("OVR", sort: .overall, width: 40)
                headerLabel("Dev", width: 20)
                sortButton("Salary", sort: .salary, width: 52)
                headerLabel("Yrs", width: 30)
                headerLabel("Morale", width: 24)
                headerLabel("Health", width: 28)
            }
        case .contracts:
            Group {
                sortButton("Salary", sort: .salary, width: 52)
                headerLabel("Cap", width: 52)
                headerLabel("Yrs", width: 34)
                headerLabel("FA", width: 40)
                sortButton("OVR", sort: .overall, width: 32)
            }
        case .development:
            Group {
                sortButton("Age", sort: .age, width: 32)
                sortButton("OVR", sort: .overall, width: 32)
                headerLabel("Pot", width: 40)
                headerLabel("Dev", width: 20)
                headerLabel("Phase", width: 48)
                headerLabel("Form", width: 24)
                headerLabel("WE", width: 32)
            }
        case .physical:
            Group {
                headerLabel("SPD", width: 34)
                headerLabel("STR", width: 34)
                headerLabel("STA", width: 34)
                headerLabel("DUR", width: 34)
                headerLabel("Health", width: 28)
                sortButton("OVR", sort: .overall, width: 32)
            }
        case .attributes:
            Group {
                headerLabel("SPD", width: 32)
                headerLabel("STR", width: 32)
                headerLabel("AGI", width: 32)
                headerLabel("AWR", width: 32)
                headerLabel("DEC", width: 32)
                sortButton("OVR", sort: .overall, width: 32)
            }
        case .depth:
            Group {
                headerLabel("Rank", width: 28)
                headerLabel("Role", width: 52)
                sortButton("OVR", sort: .overall, width: 32)
                sortButton("Age", sort: .age, width: 28)
                headerLabel("Health", width: 28)
                headerLabel("Form", width: 24)
            }
        }
    }

    private func headerLabel(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .frame(width: width, alignment: .center)
            .foregroundStyle(Color.textTertiary)
    }

    private func sortButton(_ title: String, sort: RosterSort, width: CGFloat?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if sortOrder == sort {
                    sortAscending.toggle()
                } else {
                    sortOrder = sort
                    sortAscending = false
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortOrder == sort {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .frame(width: width, alignment: .center)
        }
        .foregroundStyle(sortOrder == sort ? Color.accentGold : Color.textTertiary)
    }

    // MARK: - Formation Content

    private var formationContent: some View {
        ScrollView {
            switch selectedSide {
            case .offense:
                FormationView(
                    title: "Offense",
                    players: players.filter { $0.position.side == .offense },
                    layout: .offense
                )
            case .defense:
                FormationView(
                    title: "Defense",
                    players: players.filter { $0.position.side == .defense },
                    layout: .defense
                )
            case .specialTeams:
                FormationView(
                    title: "Special Teams",
                    players: players.filter { $0.position.side == .specialTeams },
                    layout: .specialTeams
                )
            }
        }
    }

    // MARK: - Toolbar Components

    private var filterPicker: some View {
        HStack(spacing: 4) {
            ForEach(RosterFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedSide = filter
                    }
                } label: {
                    Text(filter.label)
                        .font(.subheadline)
                        .fontWeight(selectedSide == filter ? .heavy : .medium)
                        .foregroundStyle(selectedSide == filter ? Color.backgroundPrimary : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(
                            selectedSide == filter ? Color.accentGold : Color.clear,
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .overlay(
                            selectedSide == filter
                                ? nil
                                : RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(3)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
        .frame(minWidth: 280, maxWidth: isWideLayout ? 420 : 360)
    }

    private var sortMenu: some View {
        Menu {
            ForEach(RosterSort.allCases) { sort in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if sortOrder == sort {
                            sortAscending.toggle()
                        } else {
                            sortOrder = sort
                            sortAscending = false
                        }
                    }
                } label: {
                    HStack {
                        Label(sort.label, systemImage: sort.icon)
                        if sortOrder == sort {
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                Text(sortOrder.label)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .accessibilityLabel("Sort roster, currently by \(sortOrder.label) \(sortAscending ? "ascending" : "descending")")
    }

    // MARK: - Position Picker Sheet (#175)

    private func positionPickerSheet(for player: Player) -> some View {
        NavigationStack {
            List {
                let eligible = Position.allCases.filter { pos in
                    pos == player.position || player.familiarity(at: pos) > 0
                }
                ForEach(eligible) { pos in
                    Button {
                        // In a real implementation this would update the player's position
                        positionPickerPlayer = nil
                    } label: {
                        HStack {
                            Text(pos.rawValue)
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            if pos == player.position {
                                Text("Current")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentGold)
                            } else {
                                Text("\(player.familiarity(at: pos))%")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Color.forRating(player.familiarity(at: pos)))
                            }
                        }
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
            .navigationTitle("Change Position — \(player.fullName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { positionPickerPlayer = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Starter Picker Sheet (#198)

    private func starterPickerSheet(for position: Position) -> some View {
        let candidates = players
            .filter { $0.position == position }
            .sorted { $0.overall > $1.overall }

        return NavigationStack {
            List {
                ForEach(candidates) { player in
                    Button {
                        // Promote the tapped player to starter
                        let groupPlayers = players.filter { $0.position.side == position.side }
                        handleDepthChange(player: player, newIndex: 0, groupPlayers: groupPlayers)
                        starterPickerPosition = nil
                    } label: {
                        HStack(spacing: 8) {
                            PlayerAvatarView(player: player, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.fullName)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.textPrimary)
                                Text(depthRoleLabel(for: depthIndex(for: player, in: candidates)))
                                    .font(.caption)
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Spacer()
                            Text("\(player.overall)")
                                .font(.title3.monospacedDigit())
                                .fontWeight(.bold)
                                .foregroundStyle(Color.forRating(player.overall))
                        }
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
            .navigationTitle("Set Starter — \(position.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { starterPickerPosition = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func depthRoleLabel(for index: Int) -> String {
        switch index {
        case 0:  return "Starter"
        case 1:  return "Backup"
        case 2:  return "3rd String"
        default: return "#\(index + 1)"
        }
    }

    // MARK: - Helpers

    private func positionSideOrder(_ a: PositionSide, _ b: PositionSide) -> Int {
        let order: [PositionSide: Int] = [.offense: 0, .defense: 1, .specialTeams: 2]
        return (order[a] ?? 0) - (order[b] ?? 0)
    }
}

// MARK: - Position Group Model

struct PositionGroup: Identifiable {
    let name: String
    let positions: [Position]
    var id: String { name }
}

// MARK: - Position Group Header

struct PositionGroupHeader: View {
    let group: PositionGroup
    let players: [Player]
    var isWeakest: Bool = false

    private var averageOVR: Int {
        guard !players.isEmpty else { return 0 }
        return players.reduce(0) { $0 + $1.overall } / players.count
    }

    private var averageOVRDecimal: Double {
        guard !players.isEmpty else { return 0 }
        return Double(players.reduce(0) { $0 + $1.overall }) / Double(players.count)
    }

    private var injuredCount: Int {
        players.filter { $0.isInjured }.count
    }

    private var depthStatus: DepthStatus {
        let healthy = players.filter { !$0.isInjured }.count
        if healthy <= 1 { return .critical }
        if healthy <= 2 { return .thin }
        return .deep
    }

    private var letterGrade: (letter: String, color: Color) {
        switch averageOVR {
        case 90...:   return ("A+", .success)
        case 85..<90: return ("A", .success)
        case 80..<85: return ("A-", .success)
        case 77..<80: return ("B+", .accentGold)
        case 75..<77: return ("B", .accentGold)
        case 72..<75: return ("B-", .accentGold)
        case 69..<72: return ("C+", .warning)
        case 65..<69: return ("C", .warning)
        case 60..<65: return ("C-", .warning)
        case 55..<60: return ("D", .danger)
        default:      return ("F", .danger)
        }
    }

    /// Total cap allocation for this position group in thousands.
    private var totalCapAllocation: Int {
        players.reduce(0) { $0 + $1.annualSalary }
    }

    private var formattedCap: String {
        let millions = Double(totalCapAllocation) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(totalCapAllocation)K"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            // Group name
            Text(group.name)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)

            if isWeakest {
                Text("Biggest Need")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.danger.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.danger.opacity(0.4), lineWidth: 1))
            }

            Spacer()

            // Letter grade badge with average (e.g. "A- (82.3)")
            HStack(spacing: 4) {
                Text(letterGrade.letter)
                    .font(.caption)
                    .fontWeight(.heavy)
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(minWidth: 22, maxWidth: 28, minHeight: 22, maxHeight: 22)
                    .background(letterGrade.color, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .strokeBorder(letterGrade.color.opacity(0.6), lineWidth: 1)
                    )

                Text(String(format: "%.1f", averageOVRDecimal))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.forRating(averageOVR))
            }

            // Cap allocation
            Text(formattedCap)
                .font(.caption2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 4))

            // Depth indicator
            HStack(spacing: 3) {
                Circle()
                    .fill(depthStatus.color)
                    .frame(width: 7, height: 7)
                Text(depthStatus.label)
                    .font(.caption2)
                    .foregroundStyle(depthStatus.color)
            }

            // Injured count
            if injuredCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "cross.circle.fill")
                        .font(.caption2)
                    Text("\(injuredCount)")
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(Color.danger)
            }

            // Player count
            Text("\(players.count)")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.backgroundTertiary, in: Capsule())
        }
        .textCase(nil)
    }
}

// MARK: - Depth Status

enum DepthStatus {
    case deep, thin, critical

    var label: String {
        switch self {
        case .deep: return "Deep"
        case .thin: return "Thin"
        case .critical: return "Critical"
        }
    }

    var color: Color {
        switch self {
        case .deep: return .success
        case .thin: return .warning
        case .critical: return .danger
        }
    }
}

// MARK: - Supporting Enums

enum RosterFilter: String, CaseIterable, Identifiable {
    case offense, defense, specialTeams

    var id: String { rawValue }

    var label: String {
        switch self {
        case .offense:      return "Offense"
        case .defense:      return "Defense"
        case .specialTeams: return "Spec. Teams"
        }
    }
}

enum RosterSort: String, CaseIterable, Identifiable {
    case overall, position, age, salary, name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overall:  return "Overall"
        case .position: return "Position"
        case .age:      return "Age"
        case .salary:   return "Salary"
        case .name:     return "Name"
        }
    }

    var icon: String {
        switch self {
        case .overall:  return "star.fill"
        case .position: return "rectangle.3.group"
        case .age:      return "calendar"
        case .salary:   return "dollarsign.circle"
        case .name:     return "textformat.abc"
        }
    }
}

enum RosterViewMode: String, CaseIterable, Identifiable {
    case list, formation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .list:      return "List View"
        case .formation: return "Formation"
        }
    }

    var icon: String {
        switch self {
        case .list:      return "list.bullet"
        case .formation: return "sportscourt"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RosterView(players: [
            Player(
                firstName: "Patrick", lastName: "Mahomes", position: .QB,
                age: 28, yearsPro: 7,
                positionAttributes: .quarterback(QBAttributes(
                    armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                    accuracyDeep: 87, pocketPresence: 92, scrambling: 80
                )),
                personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                morale: 90, contractYearsRemaining: 3, annualSalary: 45000
            ),
            Player(
                firstName: "Tyreek", lastName: "Hill", position: .WR,
                age: 29, yearsPro: 8,
                positionAttributes: .wideReceiver(WRAttributes(
                    routeRunning: 88, catching: 90, release: 92, spectacularCatch: 85
                )),
                personality: PlayerPersonality(archetype: .loneWolf, motivation: .stats),
                isInjured: true, injuryWeeksRemaining: 3, contractYearsRemaining: 2, annualSalary: 30000
            ),
            Player(
                firstName: "Myles", lastName: "Garrett", position: .DE,
                age: 28, yearsPro: 7,
                positionAttributes: .defensiveLine(DLAttributes(
                    passRush: 96, blockShedding: 90, powerMoves: 88, finesseMoves: 91
                )),
                personality: PlayerPersonality(archetype: .quietProfessional, motivation: .winning),
                contractYearsRemaining: 4, annualSalary: 25000
            ),
            Player(
                firstName: "Justin", lastName: "Tucker", position: .K,
                age: 34, yearsPro: 12,
                positionAttributes: .kicking(KickingAttributes(kickPower: 95, kickAccuracy: 98)),
                personality: PlayerPersonality(archetype: .steadyPerformer, motivation: .loyalty),
                contractYearsRemaining: 1, annualSalary: 6000
            ),
        ])
    }
}
