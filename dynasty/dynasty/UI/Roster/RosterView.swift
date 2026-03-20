import SwiftUI

struct RosterView: View {
    let players: [Player]
    /// The team's current salary cap in thousands. Falls back to 255_000 if not provided.
    var teamSalaryCap: Int = 255_000
    /// The defensive coordinator's scheme, used to determine correct DL starter counts.
    var defensiveScheme: DefensiveScheme = .base43

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

    /// Returns scheme-aware starter count for a position.
    private func schemeStarterCount(for position: Position) -> Int {
        let counts = PositionGradeCalculator.starterCounts(for: defensiveScheme)
        return counts[position] ?? 1
    }

    /// Sorts group players: starters first (by OVR desc), then backups (by OVR desc).
    /// Uses scheme-aware starter counts for defensive positions.
    private func starterSortedPlayers(in group: PositionGroup, from groupPlayers: [Player]) -> [Player] {
        // Group by position, determine starters per position
        var starters: [Player] = []
        var backups: [Player] = []

        for position in group.positions {
            let posPlayers = depthSortedPlayers(at: position, from: groupPlayers)
            let starterCount = group.positions.first?.side == .defense
                ? schemeStarterCount(for: position)
                : (PositionGradeCalculator.idealStarterCounts[position] ?? 1)
            starters.append(contentsOf: posPlayers.prefix(starterCount))
            backups.append(contentsOf: posPlayers.dropFirst(starterCount))
        }

        // Sort starters by OVR desc, backups by OVR desc
        starters.sort { $0.overall > $1.overall }
        backups.sort { $0.overall > $1.overall }

        return starters + backups
    }

    private var listContent: some View {
        List {
            sortableHeader

            ForEach(activeGroups) { group in
                let groupPlayers = filteredPlayers.filter { group.positions.contains($0.position) }
                if !groupPlayers.isEmpty {
                    let sortedGroupPlayers = starterSortedPlayers(in: group, from: groupPlayers)
                    Section {
                        ForEach(sortedGroupPlayers) { player in
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
                            isWeakest: group.name == weakestGroupName,
                            defensiveScheme: group.positions.first?.side == .defense ? defensiveScheme : nil
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
                headerLabel("Skill 1", width: 32)
                headerLabel("Skill 2", width: 32)
                headerLabel("Skill 3", width: 32)
                headerLabel("Skill 4", width: 32)
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
                    layout: .offense,
                    onPlayerSwapped: { position, player in
                        let groupPlayers = players.filter { $0.position.side == .offense }
                        handleDepthChange(player: player, newIndex: 0, groupPlayers: groupPlayers)
                    }
                )
            case .defense:
                FormationView(
                    title: "Defense",
                    players: players.filter { $0.position.side == .defense },
                    layout: .defense,
                    onPlayerSwapped: { position, player in
                        let groupPlayers = players.filter { $0.position.side == .defense }
                        handleDepthChange(player: player, newIndex: 0, groupPlayers: groupPlayers)
                    }
                )
            case .specialTeams:
                FormationView(
                    title: "Special Teams",
                    players: players.filter { $0.position.side == .specialTeams },
                    layout: .specialTeams,
                    onPlayerSwapped: { position, player in
                        let groupPlayers = players.filter { $0.position.side == .specialTeams }
                        handleDepthChange(player: player, newIndex: 0, groupPlayers: groupPlayers)
                    }
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

    // MARK: - Starter Picker Sheet (#198) — Rich version matching PlayerSlotPicker

    private func starterPickerSheet(for position: Position) -> some View {
        let candidates = players
            .filter { $0.position == position }
            .sorted { $0.overall > $1.overall }

        let currentStarter = candidates.first

        // Versatile players from other positions with familiarity at this position
        let versatile = players
            .filter { $0.position != position && $0.familiarity(at: position) > 0 }
            .sorted { $0.familiarity(at: position) > $1.familiarity(at: position) }

        return NavigationStack {
            List {
                // Current starter header
                if let current = currentStarter {
                    Section {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill.checkmark")
                                .foregroundStyle(Color.accentGold)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current: \(current.fullName)  \(current.position.rawValue)  OVR \(current.overall)")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                HStack(spacing: 8) {
                                    Text("OVR \(current.overall)")
                                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                                        .foregroundStyle(Color.forPlayerCardRating(current.overall))
                                    Text("Age \(current.age)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.textTertiary)
                                    Text(starterPickerFormatSalary(current.annualSalary))
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.textTertiary)
                                    if current.isInjured {
                                        HStack(spacing: 2) {
                                            Image(systemName: "cross.circle.fill")
                                                .font(.system(size: 10))
                                            Text("\(current.injuryWeeksRemaining)w")
                                                .font(.system(size: 10))
                                        }
                                        .foregroundStyle(Color.danger)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.backgroundSecondary)
                    } header: {
                        Text("Current Starter at \(position.rawValue)")
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                // Same-position candidates
                Section {
                    if candidates.isEmpty {
                        Text("No eligible players at \(position.rawValue)")
                            .foregroundStyle(Color.textTertiary)
                            .listRowBackground(Color.backgroundSecondary)
                    } else {
                        ForEach(candidates) { player in
                            Button {
                                let groupPlayers = players.filter { $0.position.side == position.side }
                                handleDepthChange(player: player, newIndex: 0, groupPlayers: groupPlayers)
                                starterPickerPosition = nil
                            } label: {
                                starterPickerRow(
                                    player: player,
                                    position: position,
                                    currentStarter: currentStarter,
                                    isVersatile: false
                                )
                            }
                            .listRowBackground(Color.backgroundSecondary)
                        }
                    }
                } header: {
                    Text("\(position.rawValue) Players")
                        .foregroundStyle(Color.textTertiary)
                }

                // Versatile players from other positions
                if !versatile.isEmpty {
                    Section {
                        ForEach(versatile) { player in
                            Button {
                                // For versatile players, promote to starter depth
                                let groupPlayers = players.filter { $0.position.side == position.side }
                                handleDepthChange(player: player, newIndex: 0, groupPlayers: groupPlayers)
                                starterPickerPosition = nil
                            } label: {
                                starterPickerRow(
                                    player: player,
                                    position: position,
                                    currentStarter: currentStarter,
                                    isVersatile: true
                                )
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
            .navigationTitle("Set Starter — \(position.rawValue)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { starterPickerPosition = nil }
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Starter Picker Row

    @ViewBuilder
    private func starterPickerRow(
        player: Player,
        position: Position,
        currentStarter: Player?,
        isVersatile: Bool
    ) -> some View {
        HStack(spacing: 10) {
            // OVR badge (large, color-coded)
            VStack(spacing: 1) {
                Text("\(player.overall)")
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.forPlayerCardRating(player.overall))

                // Effective OVR for out-of-position
                if isVersatile {
                    let familiarity = player.familiarity(at: position)
                    let effective = Int(Double(player.overall) * Double(familiarity) / 100.0)
                    Text("~\(effective)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                // Name, position, age
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

                    // Salary
                    Text(starterPickerFormatSalary(player.annualSalary))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)

                    // Form trend arrow
                    let trend = starterPickerTrend(for: player)
                    Image(systemName: trend.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(trend.color)

                    // Health/injury status
                    if player.isInjured {
                        HStack(spacing: 2) {
                            Image(systemName: "cross.circle.fill")
                                .font(.system(size: 10))
                            Text("\(player.injuryWeeksRemaining)w")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Color.danger)
                    }
                }

                // Versatility info for out-of-position players
                if isVersatile {
                    let familiarity = player.familiarity(at: position)
                    let effective = Int(Double(player.overall) * Double(familiarity) / 100.0)
                    Text("\(player.position.rawValue) at \(position.rawValue): \(player.overall) \u{00d7} \(familiarity)% = ~\(effective) effective")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.warning)
                }

                // Comparison vs current starter
                if let current = currentStarter, current.id != player.id {
                    let playerOVR = isVersatile
                        ? Int(Double(player.overall) * Double(player.familiarity(at: position)) / 100.0)
                        : player.overall
                    let diff = playerOVR - current.overall
                    let diffStr = diff >= 0 ? "+\(diff)" : "\(diff)"
                    Text("vs \(current.lastName): \(current.overall) \u{2192} \(playerOVR) (\(diffStr))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(diff >= 0 ? Color.success : Color.danger)
                }
            }

            Spacer()

            // Current starter checkmark
            if let current = currentStarter, current.id == player.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentGold)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Starter Picker Helpers

    private func starterPickerFormatSalary(_ thousands: Int) -> String {
        if thousands >= 1000 {
            let millions = Double(thousands) / 1000.0
            if millions == Double(Int(millions)) {
                return "$\(Int(millions))M"
            }
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }

    private func starterPickerTrend(for player: Player) -> DevelopmentTrend {
        let peak = player.position.peakAgeRange
        if player.age < peak.lowerBound {
            return .improving
        } else if peak.contains(player.age) {
            return .stable
        } else {
            return .declining
        }
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

// MARK: - Position Grade Calculator (#235)

/// Shared helper for computing starter grade + depth grade for a position group.
enum PositionGradeCalculator {

    /// Ideal starter counts per individual position (default: 4-3 defense).
    static let idealStarterCounts: [Position: Int] = [
        .QB: 1, .RB: 2, .FB: 1, .WR: 3, .TE: 1,
        .LT: 1, .LG: 1, .C: 1, .RG: 1, .RT: 1,
        .DE: 2, .DT: 2, .OLB: 2, .MLB: 1,
        .CB: 2, .FS: 1, .SS: 1,
        .K: 1, .P: 1,
    ]

    /// Scheme-aware starter counts for defensive positions.
    /// - 4-3/Cover3/PressMan/Tampa2: 2 DE + 2 DT, 2 OLB + 1 MLB
    /// - 3-4/Multiple/Hybrid: 2 DE + 1 DT(NT), 2 OLB + 2 MLB
    static func starterCounts(for scheme: DefensiveScheme) -> [Position: Int] {
        var counts = idealStarterCounts
        switch scheme {
        case .base34, .multiple, .hybrid:
            counts[.DT] = 1   // 3-4: one NT
            counts[.DE] = 2
            counts[.OLB] = 2
            counts[.MLB] = 2  // 3-4 uses 2 ILBs
        case .base43, .cover3, .pressMan, .tampa2:
            counts[.DT] = 2   // 4-3: two DTs
            counts[.DE] = 2
            counts[.OLB] = 2
            counts[.MLB] = 1
        }
        return counts
    }

    /// Returns the total ideal starter count for a set of positions.
    static func starterCount(for positions: [Position]) -> Int {
        positions.reduce(0) { $0 + (idealStarterCounts[$1] ?? 1) }
    }

    /// Returns the total ideal starter count for a set of positions using scheme-aware counts.
    static func starterCount(for positions: [Position], scheme: DefensiveScheme) -> Int {
        let counts = starterCounts(for: scheme)
        return positions.reduce(0) { $0 + (counts[$1] ?? 1) }
    }

    /// Converts an average OVR to a letter grade using the #235 thresholds.
    static func letterGrade(for avgOVR: Int) -> String {
        switch avgOVR {
        case 85...:   return "A"
        case 80..<85: return "B+"
        case 75..<80: return "B"
        case 70..<75: return "B-"
        case 65..<70: return "C+"
        case 60..<65: return "C"
        case 55..<60: return "C-"
        case 50..<55: return "D"
        default:      return "F"
        }
    }

    /// Color for a letter grade.
    static func gradeColor(for avgOVR: Int) -> Color {
        switch avgOVR {
        case 80...:   return .success
        case 70..<80: return .accentBlue
        case 60..<70: return .accentGold
        case 50..<60: return .warning
        default:      return .danger
        }
    }

    /// Color for a letter grade string (A=green, B=blue, C=gold, D=orange, F=red).
    static func gradeColorForLetter(_ grade: String) -> Color {
        if grade.hasPrefix("A") { return .success }
        if grade.hasPrefix("B") { return .accentBlue }
        if grade.hasPrefix("C") { return .accentGold }
        if grade.hasPrefix("D") { return .warning }
        return .danger
    }

    /// Calculate starter grade + depth grade for a group of positions.
    /// - Parameters:
    ///   - players: All players in the position group (e.g. all OL players).
    ///   - positions: The positions in this group (e.g. [.LT, .LG, .C, .RG, .RT]).
    ///   - scheme: Optional defensive scheme for scheme-aware starter counts.
    /// - Returns: Tuple with starter grade letter, depth grade letter, starter avg OVR, depth avg OVR.
    static func calculatePositionGrades(
        players: [Player],
        positions: [Position],
        scheme: DefensiveScheme? = nil
    ) -> (starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int) {
        let n: Int
        if let scheme {
            n = starterCount(for: positions, scheme: scheme)
        } else {
            n = starterCount(for: positions)
        }
        let sorted = players.sorted { $0.overall > $1.overall }
        let starters = Array(sorted.prefix(n))
        let backups = Array(sorted.dropFirst(n))

        let starterAvg = starters.isEmpty ? 0 : starters.map(\.overall).reduce(0, +) / starters.count
        let depthAvg = backups.isEmpty ? 0 : backups.map(\.overall).reduce(0, +) / backups.count

        let sGrade = starters.isEmpty ? "F" : letterGrade(for: starterAvg)
        let dGrade = backups.isEmpty ? "F" : letterGrade(for: depthAvg)

        return (sGrade, dGrade, starterAvg, depthAvg)
    }
}

// MARK: - Position Group Header

struct PositionGroupHeader: View {
    let group: PositionGroup
    let players: [Player]
    var isWeakest: Bool = false
    var defensiveScheme: DefensiveScheme? = nil

    private var grades: (starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int) {
        PositionGradeCalculator.calculatePositionGrades(players: players, positions: group.positions, scheme: defensiveScheme)
    }

    private var injuredCount: Int {
        players.filter { $0.isInjured }.count
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
        let g = grades
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

            // Starter grade / Depth grade (#235)
            HStack(spacing: 2) {
                Text("S:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Text(g.starterGrade)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(g.starterGrade))
                Text("/")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                Text("D:")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Text(g.depthGrade)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(g.depthGrade))
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
