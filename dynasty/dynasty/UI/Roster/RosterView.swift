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

    @State private var selectedSide: RosterFilter = .all
    @State private var sortOrder: RosterSort = .overall
    @State private var viewMode: RosterViewMode = .list
    @State private var analysisMode: RosterAnalysisMode = .overview

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
        case .all:
            filtered = players
        case .offense:
            filtered = players.filter { $0.position.side == .offense }
        case .defense:
            filtered = players.filter { $0.position.side == .defense }
        case .specialTeams:
            filtered = players.filter { $0.position.side == .specialTeams }
        }

        switch sortOrder {
        case .overall:
            return filtered.sorted { $0.overall > $1.overall }
        case .position:
            return filtered.sorted {
                let sideOrder = positionSideOrder($0.position.side, $1.position.side)
                if sideOrder != 0 { return sideOrder < 0 }
                let posOrder = Position.allCases.firstIndex(of: $0.position)! -
                               Position.allCases.firstIndex(of: $1.position)!
                if posOrder != 0 { return posOrder < 0 }
                return $0.overall > $1.overall
            }
        case .age:
            return filtered.sorted { $0.age < $1.age }
        case .salary:
            return filtered.sorted { $0.annualSalary > $1.annualSalary }
        case .name:
            return filtered.sorted { $0.lastName < $1.lastName }
        }
    }

    private var activeGroups: [PositionGroup] {
        switch selectedSide {
        case .all:
            return Self.offenseGroups + Self.defenseGroups + Self.specialTeamsGroups
        case .offense:
            return Self.offenseGroups
        case .defense:
            return Self.defenseGroups
        case .specialTeams:
            return Self.specialTeamsGroups
        }
    }

    // MARK: - Depth Index Helper

    /// Computes a depth index for a player within their position group,
    /// based on overall rating rank. 0 = starter, 1 = backup, etc.
    private func depthIndex(for player: Player, in groupPlayers: [Player]) -> Int {
        let sorted = groupPlayers
            .filter { $0.position == player.position }
            .sorted { $0.overall > $1.overall }
        return sorted.firstIndex(where: { $0.id == player.id }) ?? sorted.count
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
                            NavigationLink(destination: PlayerDetailView(player: player)) {
                                PlayerRowView(
                                    player: player,
                                    depthIndex: depthIndex(for: player, in: groupPlayers),
                                    analysisMode: analysisMode
                                )
                            }
                            .listRowBackground(Color.backgroundSecondary)
                        }
                    } header: {
                        PositionGroupHeader(
                            group: group,
                            players: groupPlayers
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
        HStack(spacing: 0) {
            sortButton("POS", sort: .position, width: isWideLayout ? 56 : 44)
            sortButton("NAME", sort: .name, width: nil)
            Spacer()
            analysisHeaderColumns
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(Color.textTertiary)
        .padding(.horizontal, 4)
        .listRowBackground(Color.backgroundPrimary)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }

    @ViewBuilder
    private var analysisHeaderColumns: some View {
        switch analysisMode {
        case .overview:
            Group {
                sortButton("AGE", sort: .age, width: 28)
                headerLabel("FRM", width: 16)
                sortButton("OVR", sort: .overall, width: 36)
                headerLabel("DEV", width: 14)
                sortButton("SAL", sort: .salary, width: 48)
                headerLabel("YRS", width: 26)
                headerLabel("MRL", width: 14)
                headerLabel("HP", width: 20)
            }
        case .contracts:
            Group {
                sortButton("SAL", sort: .salary, width: 48)
                headerLabel("CAP", width: 48)
                headerLabel("YRS", width: 30)
                headerLabel("FA", width: 36)
                sortButton("OVR", sort: .overall, width: 28)
            }
        case .development:
            Group {
                sortButton("AGE", sort: .age, width: 28)
                sortButton("OVR", sort: .overall, width: 28)
                headerLabel("POT", width: 36)
                headerLabel("DEV", width: 14)
                headerLabel("PHS", width: 44)
                headerLabel("FRM", width: 16)
                headerLabel("WE", width: 28)
            }
        case .physical:
            Group {
                headerLabel("SPD", width: 30)
                headerLabel("STR", width: 30)
                headerLabel("STA", width: 30)
                headerLabel("DUR", width: 30)
                headerLabel("HP", width: 20)
                sortButton("OVR", sort: .overall, width: 28)
            }
        case .attributes:
            Group {
                headerLabel("SPD", width: 28)
                headerLabel("STR", width: 28)
                headerLabel("AGI", width: 28)
                headerLabel("AWR", width: 28)
                headerLabel("DEC", width: 28)
                sortButton("OVR", sort: .overall, width: 28)
            }
        case .depth:
            Group {
                headerLabel("RNK", width: 24)
                headerLabel("ROLE", width: 48)
                sortButton("OVR", sort: .overall, width: 28)
                sortButton("AGE", sort: .age, width: 24)
                headerLabel("HP", width: 20)
                headerLabel("FRM", width: 16)
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
                sortOrder = sort
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortOrder == sort {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
            }
            .frame(width: width, alignment: .center)
        }
        .foregroundStyle(sortOrder == sort ? Color.accentGold : Color.textTertiary)
    }

    // MARK: - Formation Content

    private var formationContent: some View {
        ScrollView {
            let useColumns = isLandscape && selectedSide == .all
            if useColumns {
                // Side-by-side layout in landscape when showing all
                HStack(alignment: .top, spacing: 12) {
                    VStack {
                        FormationView(
                            title: "Offense",
                            players: players.filter { $0.position.side == .offense },
                            layout: .offense
                        )
                    }
                    .frame(maxWidth: .infinity)

                    VStack {
                        FormationView(
                            title: "Defense",
                            players: players.filter { $0.position.side == .defense },
                            layout: .defense
                        )
                        FormationView(
                            title: "Special Teams",
                            players: players.filter { $0.position.side == .specialTeams },
                            layout: .specialTeams
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
            } else {
                switch selectedSide {
                case .offense, .all:
                    FormationView(
                        title: "Offense",
                        players: players.filter { $0.position.side == .offense },
                        layout: .offense
                    )
                default:
                    EmptyView()
                }

                if selectedSide == .defense || selectedSide == .all {
                    FormationView(
                        title: "Defense",
                        players: players.filter { $0.position.side == .defense },
                        layout: .defense
                    )
                }

                if selectedSide == .specialTeams || selectedSide == .all {
                    FormationView(
                        title: "Special Teams",
                        players: players.filter { $0.position.side == .specialTeams },
                        layout: .specialTeams
                    )
                }
            }
        }
    }

    // MARK: - Toolbar Components

    private var filterPicker: some View {
        Picker("Filter", selection: $selectedSide) {
            ForEach(RosterFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 320, maxWidth: isWideLayout ? 500 : 400)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(RosterSort.allCases) { sort in
                    Label(sort.label, systemImage: sort.icon).tag(sort)
                }
            }
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort roster, currently by \(sortOrder.label)")
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
    case all, offense, defense, specialTeams

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:          return "All"
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
