import SwiftUI

struct RosterView: View {
    let players: [Player]

    // MARK: - State

    @State private var selectedSide: RosterFilter = .all
    @State private var sortOrder: RosterSort = .overall
    @State private var viewMode: RosterViewMode = .list

    // MARK: - Position Groups (NFL-style names)

    private static let offenseGroups: [PositionGroup] = [
        PositionGroup(name: "QB Room", positions: [.QB]),
        PositionGroup(name: "Backfield", positions: [.RB, .FB]),
        PositionGroup(name: "Receivers", positions: [.WR, .TE]),
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

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                RosterSummaryBar(players: players)

                viewModePicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                if viewMode == .list {
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
                                PlayerRowView(player: player)
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
            sortButton("POS", sort: .position, width: 44)
            sortButton("NAME", sort: .name, width: nil)
            Spacer()
            sortButton("AGE", sort: .age, width: 36)
            sortButton("OVR", sort: .overall, width: 40)
            sortButton("SAL", sort: .salary, width: 52)
        }
        .font(.caption2)
        .fontWeight(.semibold)
        .foregroundStyle(Color.textTertiary)
        .padding(.horizontal, 4)
        .listRowBackground(Color.backgroundPrimary)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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

    // MARK: - Toolbar Components

    private var filterPicker: some View {
        Picker("Filter", selection: $selectedSide) {
            ForEach(RosterFilter.allCases) { filter in
                Text(filter.label).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .frame(minWidth: 320, maxWidth: 400)
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
        case 85...:   return ("A", .success)
        case 75..<85: return ("B", .accentGold)
        case 65..<75: return ("C", .warning)
        case 55..<65: return ("D", .danger)
        default:      return ("F", .danger)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Group name
            Text(group.name)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            // Letter grade badge
            Text(letterGrade.letter)
                .font(.caption)
                .fontWeight(.heavy)
                .foregroundStyle(letterGrade.color)
                .frame(width: 20, height: 20)
                .background(letterGrade.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

            // Average OVR
            HStack(spacing: 3) {
                Text("AVG")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                Text("\(averageOVR)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundStyle(Color.forRating(averageOVR))
            }

            // Depth indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(depthStatus.color)
                    .frame(width: 8, height: 8)
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
