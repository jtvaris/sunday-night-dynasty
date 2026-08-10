import SwiftUI
import SwiftData

struct RosterView: View {
    let players: [Player]
    /// The team's current salary cap in thousands. Falls back to the league's
    /// opening cap (`ContractEngine.openingSalaryCap`) if not provided.
    var teamSalaryCap: Int = ContractEngine.openingSalaryCap
    /// `Team.currentCapUsage` in thousands — the same ledger the Cap screen and
    /// the dashboard quote. `nil` only for previews and lightweight call sites,
    /// where the summary bar falls back to summing the roster's salaries.
    var teamCapUsed: Int? = nil
    /// The defensive coordinator's scheme, used to determine correct DL starter counts.
    var defensiveScheme: DefensiveScheme = .base43
    /// The offensive coordinator's scheme. Only the `FIT` slot reads it; `nil`
    /// (previews, lightweight call sites) leaves the slot honestly empty on
    /// offensive rows rather than inventing a number.
    var offensiveScheme: OffensiveScheme? = nil
    /// R28: career context for the Injury Report (pending return decisions).
    /// Optional so lightweight call sites and previews keep working.
    var career: Career? = nil

    // MARK: - Environment

    @Environment(\.modelContext) private var modelContext
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
    /// **The one modal slot on this screen** (§2.8 + the house rule).
    ///
    /// This view carried FIVE presentation modifiers on a single node — two
    /// `.sheet(item:)` and three `.sheet(isPresented:)` — which is the defect
    /// this codebase has now found five separate times: SwiftUI honours one
    /// `.sheet` per view, so the position picker, the starter picker and the
    /// group-assessment editor were all competing for a slot the injury report
    /// and the practice squad had already claimed. Whichever lost opened blank
    /// or dismissed the moment it appeared.
    ///
    /// All five stay **sheets** rather than covers or pushes, and that is the
    /// §2.8 reading, not an accident of what was here: every one of them is a
    /// short, cancellable side-task off the roster — a picker, an editor, a
    /// report you glance at — and none of them is a process that owns the
    /// screen. Peer side-tasks get the same presentation weight.
    private enum RosterSheet: Identifiable {
        /// Change a player's listed position.
        case positionPicker(Player)
        /// Pick the starters for one position.
        case starterPicker(Position)
        /// The group's own assessment / priority / note editor (#283).
        case groupAssessment
        /// R28: Injury Report.
        case injuryReport
        /// §5.1: practice squad + league poach board.
        case practiceSquad

        var id: String {
            switch self {
            case .positionPicker(let player): return "position-\(player.id)"
            case .starterPicker(let position): return "starter-\(position.rawValue)"
            case .groupAssessment:            return "assessment"
            case .injuryReport:               return "injury"
            case .practiceSquad:              return "practiceSquad"
            }
        }
    }

    @State private var activeSheet: RosterSheet? = nil

    /// Track whether the user has seen the sort hint.
    @CareerScopedStorage("rosterSortHintSeen") private var sortHintSeen: Bool = false

    // MARK: - Group Assessment (#283)
    @CareerScopedStorage("rosterOwnAssessments") private var rosterOwnAssessmentsJSON: String = "{}"
    @CareerScopedStorage("rosterNotes") private var rosterNotesJSON: String = "{}"
    @CareerScopedStorage("rosterPriorities") private var rosterPrioritiesJSON: String = "{}"
    @State private var assessmentGroup: String? = nil
    @State private var editingAssessment: String = "none"
    @State private var editingPriority: String = "none"
    @State private var editingNote: String = ""

    private var rosterOwnAssessments: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rosterOwnAssessmentsJSON.utf8))) ?? [:]
    }
    private var rosterNotes: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rosterNotesJSON.utf8))) ?? [:]
    }
    private var rosterPriorities: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(rosterPrioritiesJSON.utf8))) ?? [:]
    }

    private static let assessmentOptions = [
        "none", "Solid", "Starter needed", "Depth needed", "Upgrade needed", "Aging", "Priority"
    ]

    /// Computes the staff assessment label and color for a position group.
    private func staffAssessment(group: PositionGroup, players: [Player]) -> (label: String, color: Color) {
        let scheme: DefensiveScheme? = group.positions.first?.side == .defense ? defensiveScheme : nil
        let grades = PositionGradeCalculator.calculatePositionGrades(players: players, positions: group.positions, scheme: scheme)

        let starterBad = ["D", "F"].contains(grades.starterGrade)
        let depthBad = ["D", "F"].contains(grades.depthGrade)
        let starterWeak = ["C-", "D", "F"].contains(grades.starterGrade)
        let starterGood = grades.starterGrade.hasPrefix("A") || grades.starterGrade.hasPrefix("B")
        let depthGood = grades.depthGrade.hasPrefix("A") || grades.depthGrade.hasPrefix("B")

        if starterBad { return ("Starter needed", .danger) }
        if depthBad && starterWeak { return ("Needs work", .danger) }

        if starterWeak {
            let hasExpiring = players.contains { $0.contractYearsRemaining <= 1 }
            if hasExpiring { return ("Upgrade + expiring", .warning) }
            return ("Below average", .warning)
        }

        if depthBad { return ("Depth thin", .accentGold) }

        let n = PositionGradeCalculator.starterCount(for: group.positions)
        let sorted = players.sorted { $0.overall > $1.overall }
        let starters = Array(sorted.prefix(n))
        if !starters.isEmpty {
            let avgAge = starters.map(\.age).reduce(0, +) / starters.count
            let peakUpper = group.positions.map { $0.peakAgeRange.upperBound }.reduce(0, +) / max(group.positions.count, 1)
            if avgAge > peakUpper { return ("Aging", .accentBlue) }
        }

        let hasExpiring = players.contains { $0.contractYearsRemaining <= 1 && $0.overall >= grades.starterOVR - 5 }
        if hasExpiring { return ("Key FA pending", .accentGold) }

        if starterGood && depthGood { return ("Strong", .success) }
        if starterGood { return ("Solid starters", .success) }
        return ("Adequate", .textSecondary)
    }

    /// Returns a slightly brighter background for starters to visually distinguish them.
    private func starterRowBackground(player: Player, groupPlayers: [Player], starterCount: Int) -> Color {
        let idx = depthIndex(for: player, in: groupPlayers)
        if idx < starterCount {
            return Color(red: 0.10, green: 0.14, blue: 0.22) // blue tint distinguishing starters from backups
        }
        return Color.backgroundSecondary
    }

    /// Maps assessment group IDs to the EvalPositionGroup-style IDs used by RosterEvaluationView.
    private func evalGroupID(for group: PositionGroup) -> String {
        switch group.name {
        case "QB Room":        return "QB"
        case "Backfield":      return "RB"
        case "Wide Receivers": return "WR"
        case "Tight Ends":     return "TE"
        case "Offensive Line": return "OL"
        case "Defensive Line": return "DL"
        case "Linebackers":    return "LB"
        case "Secondary":      return "DB"
        case "Specialists":    return "ST"
        default:               return group.name
        }
    }

    private func saveGroupAssessment(groupID: String, assessment: String, priority: String, note: String) {
        var assessments = rosterOwnAssessments
        var priorities = rosterPriorities
        var notes = rosterNotes
        if assessment == "none" { assessments.removeValue(forKey: groupID) } else { assessments[groupID] = assessment }
        if priority == "none" { priorities.removeValue(forKey: groupID) } else { priorities[groupID] = priority }
        if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { notes.removeValue(forKey: groupID) } else { notes[groupID] = note }
        if let data = try? JSONEncoder().encode(assessments) { rosterOwnAssessmentsJSON = String(data: data, encoding: .utf8) ?? "{}" }
        if let data = try? JSONEncoder().encode(priorities) { rosterPrioritiesJSON = String(data: data, encoding: .utf8) ?? "{}" }
        if let data = try? JSONEncoder().encode(notes) { rosterNotesJSON = String(data: data, encoding: .utf8) ?? "{}" }
    }

    private func assessmentColor(_ assessment: String) -> Color {
        switch assessment {
        case "Solid":           return .success
        case "Starter needed":  return .danger
        case "Depth needed":    return .warning
        case "Upgrade needed":  return .accentGold
        case "Aging":           return .accentBlue
        case "Priority":        return .danger
        default:                return .textTertiary
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority {
        case "high":   return .danger
        case "medium": return .warning
        case "low":    return .accentBlue
        default:       return .clear
        }
    }

    // MARK: - Position Groups (NFL-style names)

    static let offenseGroups: [PositionGroup] = [
        PositionGroup(name: "QB Room", positions: [.QB]),
        PositionGroup(name: "Backfield", positions: [.RB, .FB]),
        PositionGroup(name: "Wide Receivers", positions: [.WR]),
        PositionGroup(name: "Tight Ends", positions: [.TE]),
        PositionGroup(name: "Offensive Line", positions: [.LT, .LG, .C, .RG, .RT]),
    ]

    static let defenseGroups: [PositionGroup] = [
        PositionGroup(name: "Defensive Line", positions: [.DE, .DT]),
        PositionGroup(name: "Linebackers", positions: [.OLB, .MLB]),
        PositionGroup(name: "Secondary", positions: [.CB, .FS, .SS]),
    ]

    static let specialTeamsGroups: [PositionGroup] = [
        PositionGroup(name: "Specialists", positions: [.K, .P]),
    ]

    /// Offense → defense → specialists, in one list. Shared (rather than
    /// re-declared) so another team's roster in `LeagueTeamRosterView` groups
    /// exactly the way the user's own roster does.
    static let allPositionGroups: [PositionGroup] =
        offenseGroups + defenseGroups + specialTeamsGroups

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
                RosterSummaryBar(
                    players: players,
                    teamSalaryCap: teamSalaryCap,
                    capUsed: teamCapUsed,
                    // The roster ceiling is phase-dependent (90 in the offseason,
                    // 53 once the season starts), so the bar needs the calendar
                    // to label the count honestly.
                    phase: career?.currentPhase
                )

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
        // The one modal slot — see `RosterSheet`.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .positionPicker(let player):
                positionPickerSheet(for: player)
            case .starterPicker(let position):
                starterPickerSheet(for: position)
            case .groupAssessment:
                groupAssessmentSheet
            case .injuryReport:
                InjuryReportView(players: players, career: career)
            case .practiceSquad:
                if let career {
                    PracticeSquadView(career: career)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                filterPicker
            }
            ToolbarItem(placement: .primaryAction) {
                sortMenu
            }
            ToolbarItem(placement: .primaryAction) {
                injuryReportButton
            }
            ToolbarItem(placement: .primaryAction) {
                practiceSquadButton
            }
            ToolbarItem(placement: .primaryAction) {
                leagueRostersButton
            }
        }
    }

    // MARK: - Practice Squad Button (§5.1)

    /// Entry point into the squad screen. The 16 men below the 53 are a roster
    /// surface, not a camp one — they develop all season, they can be promoted
    /// on any given week, and any rival can sign them away — so they hang off
    /// the roster screen rather than off the cutdown flow that created them.
    @ViewBuilder
    private var practiceSquadButton: some View {
        if career != nil {
            Button {
                activeSheet = .practiceSquad
            } label: {
                Label("Practice Squad", systemImage: "person.3.sequence.fill")
            }
        }
    }

    // MARK: - League Rosters Button

    /// Entry point into the 32-roster browser (plan finding S8: the other 31
    /// teams had no surface at all). Needs the career for the "your team" mark
    /// and the trade route, so lightweight call sites/previews simply omit it.
    @ViewBuilder
    private var leagueRostersButton: some View {
        if let career {
            NavigationLink {
                LeagueRostersView(career: career)
            } label: {
                Label("League Rosters", systemImage: "person.3.sequence.fill")
            }
        }
    }

    // MARK: - Injury Report Button (R28)

    /// Count feeding the toolbar badge: current injuries + pending decisions.
    private var injuryReportBadgeCount: Int {
        let injured = players.filter { $0.isInjured }.count
        let decisions = career?.pendingReturnDecisions.count ?? 0
        return injured + decisions
    }

    private var injuryReportButton: some View {
        Button {
            activeSheet = .injuryReport
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "cross.case.fill")
                    .foregroundStyle(injuryReportBadgeCount > 0 ? Color.danger : Color.textSecondary)
                if injuryReportBadgeCount > 0 {
                    Text("\(injuryReportBadgeCount)")
                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.danger, in: Capsule())
                        .offset(x: 8, y: -6)
                }
            }
        }
        .accessibilityLabel("Injury report, \(injuryReportBadgeCount) item\(injuryReportBadgeCount == 1 ? "" : "s")")
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                Text("ANALYSIS")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)
                Text("·")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
                Text(analysisMode.label.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.accentBlue)
                    .tracking(0.5)
                Spacer()
            }
            .padding(.horizontal, 4)

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
                                    .font(.system(size: 11, weight: analysisMode == mode ? .bold : .regular))
                                Text(mode.label)
                                    .font(.caption)
                                    .fontWeight(analysisMode == mode ? .bold : .medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundStyle(analysisMode == mode ? Color.backgroundPrimary : Color.textSecondary)
                            .background(
                                analysisMode == mode ? Color.accentBlue : Color.backgroundTertiary,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(
                                        analysisMode == mode ? Color.accentBlue : Color.surfaceBorder,
                                        lineWidth: analysisMode == mode ? 1.5 : 1
                                    )
                            )
                            .shadow(
                                color: analysisMode == mode ? Color.accentBlue.opacity(0.3) : .clear,
                                radius: analysisMode == mode ? 4 : 0,
                                y: analysisMode == mode ? 1 : 0
                            )
                        }
                        .accessibilityLabel("Analysis mode: \(mode.label)\(analysisMode == mode ? ", selected" : "")")
                        .accessibilityAddTraits(analysisMode == mode ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 1)
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - List Content

    /// The scheme this man's unit runs, keyed the way
    /// `Player.schemeFamiliarity` stores it — the `FIT` slot's only input.
    /// Special-teams players belong to neither install, so their slot stays
    /// empty rather than borrowing the defense's.
    private func installedScheme(for player: Player) -> String? {
        switch player.position.side {
        case .offense:      return offensiveScheme?.rawValue
        case .defense:      return defensiveScheme.rawValue
        case .specialTeams: return nil
        }
    }

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
                            let posStarterCount = group.positions.first?.side == .defense
                                ? schemeStarterCount(for: player.position)
                                : (PositionGradeCalculator.idealStarterCounts[player.position] ?? 1)
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
                                        activeSheet = .positionPicker(player)
                                    },
                                    onStarterBadgeTap: {
                                        activeSheet = .starterPicker(player.position)
                                    },
                                    starterCountForPosition: posStarterCount,
                                    teamSalaryCap: teamSalaryCap,
                                    installedScheme: installedScheme(for: player)
                                )
                            }
                            .listRowBackground(starterRowBackground(player: player, groupPlayers: groupPlayers, starterCount: posStarterCount))
                        }
                    } header: {
                        let gid = evalGroupID(for: group)
                        let staffInfo = staffAssessment(group: group, players: groupPlayers)
                        Button {
                            let gid = evalGroupID(for: group)
                            editingAssessment = rosterOwnAssessments[gid] ?? "none"
                            editingPriority = rosterPriorities[gid] ?? "none"
                            editingNote = rosterNotes[gid] ?? ""
                            assessmentGroup = gid
                            activeSheet = .groupAssessment
                        } label: {
                            PositionGroupHeader(
                                group: group,
                                players: groupPlayers,
                                isWeakest: group.name == weakestGroupName,
                                defensiveScheme: group.positions.first?.side == .defense ? defensiveScheme : nil,
                                staffLabel: staffInfo.label,
                                staffColor: staffInfo.color,
                                ownAssessment: rosterOwnAssessments[gid]
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        // insetGrouped's stock top inset and section gaps left a wide band of
        // empty navy between the analysis pills and the first position group —
        // roughly a third of a screen before any player was visible.
        .listSectionSpacing(12)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // MARK: - Group Assessment Sheet (#283)

    private var groupAssessmentSheet: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Your Assessment picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Your Assessment")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)

                            LazyVGrid(columns: [
                                GridItem(.flexible()),
                                GridItem(.flexible()),
                                GridItem(.flexible())
                            ], spacing: 8) {
                                ForEach(Self.assessmentOptions, id: \.self) { option in
                                    let isSelected = editingAssessment == option
                                    let displayLabel = option == "none" ? "None" : option
                                    let badgeColor = option == "none" ? Color.textTertiary : assessmentColor(option)

                                    Button {
                                        editingAssessment = option
                                    } label: {
                                        Text(displayLabel)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(isSelected ? Color.backgroundPrimary : badgeColor)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(
                                                isSelected ? badgeColor : badgeColor.opacity(0.1),
                                                in: RoundedRectangle(cornerRadius: 8)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .strokeBorder(badgeColor.opacity(isSelected ? 1 : 0.4), lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Priority picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Priority")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            Picker("Priority", selection: $editingPriority) {
                                Text("None").tag("none")
                                Text("Low").tag("low")
                                Text("Medium").tag("medium")
                                Text("High").tag("high")
                            }
                            .pickerStyle(.segmented)
                        }

                        // Notes field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notes")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            TextEditor(text: $editingNote)
                                .scrollContentBackground(.hidden)
                                .font(.body)
                                .foregroundStyle(Color.textPrimary)
                                .frame(minHeight: 120)
                                .padding(10)
                                .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    Group {
                                        if editingNote.isEmpty {
                                            Text("Add your evaluation notes...")
                                                .font(.body)
                                                .foregroundStyle(Color.textTertiary)
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 18)
                                                .allowsHitTesting(false)
                                        }
                                    },
                                    alignment: .topLeading
                                )
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("\(assessmentGroup ?? "") Evaluation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                        .foregroundStyle(Color.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let gid = assessmentGroup {
                            saveGroupAssessment(groupID: gid, assessment: editingAssessment, priority: editingPriority, note: editingNote)
                        }
                        activeSheet = nil
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentGold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sortable Header

    private var sortableHeader: some View {
        VStack(spacing: 4) {
            if !sortHintSeen {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 11))
                    Text("Tap column headers to sort")
                        .font(DSType.text(11, .medium, prose: true))
                }
                .foregroundStyle(Color.textTertiary)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation { sortHintSeen = true }
                    }
                }
            }
            // Wave 1: the header is built from the SAME slots as the row it
            // labels (`UI_REDESIGN_VISION` §2.2), because a header whose
            // gutters are missing puts every label one column left of the
            // numbers it describes — which is exactly what this one did.
            //
            // `POS` claimed 44 or 56 while the row's badge is 36, and nothing
            // at all was reserved for the depth chip and the face, so the whole
            // leading block was ~62pt out. The trailing block happened to line
            // up only because both sides were right-anchored and both used a
            // 6pt gap; that gap is now `PlayerRowView.Column.gap`, read from
            // one place, and the leading gutters are the row's own constants.
            HStack(spacing: 0) {
                sortButton("POS", sort: .position, width: DSListColumn.position)

                // The depth chip and the portrait: reserved, not labelled.
                Color.clear
                    .frame(width: PlayerRowView.Column.portraitSlot, height: 1)

                sortButton("NAME", sort: .name, width: nil)
                    .frame(minWidth: DSListColumn.identityMin, alignment: .leading)
                    .padding(.leading, DSListColumn.identityGap)

                Spacer(minLength: 2)

                HStack(spacing: PlayerRowView.Column.gap) {
                    analysisHeaderColumns
                    // Matches the disclosure chevron on the player rows below.
                    Color.clear.frame(width: Self.disclosureGutter, height: 1)
                }
            }
            // 11pt display, tracked — the same voice and the same floor the
            // cells below now use. `.caption2` was 11pt already, but in the
            // text voice, so the header's digits and the row's did not share a
            // width class.
            .font(DSType.display(11, .heavy))
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
                sortButton("Age", sort: .age, width: PlayerRowView.Column.age)
                headerLabel("Frm", width: 24)
                sortButton("OVR", sort: .overall, width: PlayerRowView.Column.ovr)
                headerLabel("↗", width: 20)
                sortButton("Salary", sort: .salary, width: 52)
                headerLabel("Yrs", width: 30)
                headerIcon("face.smiling", width: 24)
                headerIcon("cross.case.fill", width: 28)
            }
        case .contracts:
            Group {
                headerLabel("Dead", width: PlayerRowView.Column.deadCap)
                headerLabel("Save", width: PlayerRowView.Column.capSavings)
                sortButton("Salary", sort: .salary, width: 52)
                headerLabel("Cap", width: 52)
                headerLabel("Yrs", width: 34)
                headerLabel("FA", width: 40)
                sortButton("OVR", sort: .overall, width: PlayerRowView.Column.ovr)
            }
        case .development:
            Group {
                sortButton("Age", sort: .age, width: PlayerRowView.Column.age)
                sortButton("OVR", sort: .overall, width: PlayerRowView.Column.ovr)
                headerLabel("Pot", width: 40)
                headerLabel("Dev", width: 20)
                headerLabel("Phase", width: 48)
                headerLabel("Form", width: 24)
                headerLabel("WE", width: 32)
            }
        case .mental:
            Group {
                sortButton("Age", sort: .age, width: PlayerRowView.Column.age)
                sortButton("OVR", sort: .overall, width: PlayerRowView.Column.ovr)
                headerLabel("LRN", width: 34)
                headerLabel("CMP", width: 34)
                headerLabel("WE", width: 34)
                headerLabel("Motiv", width: PlayerRowView.Column.motivation)
            }
        case .physical:
            Group {
                headerLabel("SPD", width: 34)
                headerLabel("STR", width: 34)
                headerLabel("STA", width: 34)
                headerLabel("DUR", width: 34)
                headerLabel("Health", width: 28)
                sortButton("OVR", sort: .overall, width: PlayerRowView.Column.ovr)
            }
        case .attributes:
            Group {
                headerLabel("Skill 1", width: 32)
                headerLabel("Skill 2", width: 32)
                headerLabel("Skill 3", width: 32)
                headerLabel("Skill 4", width: 32)
                sortButton("OVR", sort: .overall, width: PlayerRowView.Column.ovr)
            }
        case .depth:
            Group {
                headerLabel("Rank", width: 28)
                headerLabel("Role", width: 52)
                sortButton("OVR", sort: .overall, width: PlayerRowView.Column.ovr)
                sortButton("Age", sort: .age, width: PlayerRowView.Column.age)
                headerLabel("Health", width: 28)
                headerLabel("Form", width: 24)
            }
        }
    }

    private func headerLabel(_ title: String, width: CGFloat) -> some View {
        Text(title)
            // Same reason as `sortButton`: a fixed-width box wraps a label it
            // cannot fit ("Health" in 28pt, "Skill 1" in 32) rather than
            // shrinking it, which breaks the header's baseline.
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width, alignment: .center)
            .foregroundStyle(Color.textTertiary)
    }

    /// Icon column header — for columns whose cells are SF Symbols rather than
    /// text (morale, health). Emoji were used here, which rendered in full
    /// colour at a different optical weight than every neighbouring header.
    private func headerIcon(_ systemName: String, width: CGFloat) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 11, weight: .semibold))
            .frame(width: width, alignment: .center)
            .foregroundStyle(Color.textTertiary)
    }

    /// Width the `NavigationLink` disclosure chevron occupies on every player
    /// row. The header row has no chevron, so without reserving the same gutter
    /// its columns sit ~21pt right of the values they label.
    private static let disclosureGutter: CGFloat = 21

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
                    // A header in a fixed-width box wraps mid-word when the
                    // chevron appears next to it — "OVR" became "OV / R" the
                    // moment the column was sorted. The widths above are sized
                    // for label + chevron; this makes wrapping impossible even
                    // at larger dynamic type.
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if sortOrder == sort {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
            }
            .frame(width: width, alignment: .center)
            // Make the full frame tappable, not just the text glyph itself.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(sortOrder == sort ? Color.accentBlue : Color.textTertiary)
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
        HStack(spacing: 8) {
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
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                        .background(
                            selectedSide == filter ? Color.accentBlue : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                        .overlay(
                            selectedSide == filter
                                ? nil
                                : RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                        )
                }
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(5)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .frame(minWidth: 320, maxWidth: isWideLayout ? 480 : 400)
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

    /// Finds the position group containing a given position.
    private func positionGroup(for position: Position) -> PositionGroup? {
        let allGroups = Self.offenseGroups + Self.defenseGroups + Self.specialTeamsGroups
        return allGroups.first { $0.positions.contains(position) }
    }

    /// All players in the same position group as the given player, excluding the player itself.
    private func swapCandidates(for player: Player) -> [(player: Player, effectiveOVR: Int, familiarity: Int, isNatural: Bool)] {
        guard let group = positionGroup(for: player.position) else { return [] }
        let groupPlayers = players.filter { group.positions.contains($0.position) && $0.id != player.id }

        return groupPlayers.map { candidate in
            // What OVR would this candidate have at the selected player's position?
            let fam = candidate.familiarity(at: player.position)
            let effectiveOVR = candidate.position == player.position
                ? candidate.overall
                : Int(Double(candidate.overall) * Double(fam) / 100.0)
            let isNatural = candidate.position == player.position
            return (player: candidate, effectiveOVR: effectiveOVR, familiarity: fam, isNatural: isNatural)
        }
        .sorted { $0.effectiveOVR > $1.effectiveOVR }
    }

    private func positionPickerSheet(for player: Player) -> some View {
        let candidates = swapCandidates(for: player)
        let playerDepth = depthIndex(for: player, in: players.filter { $0.position == player.position })
        let isStarter = playerDepth < (PositionGradeCalculator.idealStarterCounts[player.position] ?? 1)

        return NavigationStack {
            List {
                // Current player info
                Section {
                    HStack(spacing: 12) {
                        Text(player.position.rawValue)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Self.positionSideColor(player.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.fullName)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.textPrimary)
                            Text(isStarter ? "Starter" : "Backup")
                                .font(.caption)
                                .foregroundStyle(isStarter ? Color.success : Color.textTertiary)
                        }
                        Spacer()
                        Text("\(player.overall)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.forRating(player.overall))
                    }
                    .listRowBackground(Color.backgroundSecondary)
                } header: {
                    Text("Swap from")
                }

                // Swap candidates
                Section {
                    if candidates.isEmpty {
                        Text("No other players in this position group")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                            .listRowBackground(Color.backgroundSecondary)
                    } else {
                        ForEach(candidates, id: \.player.id) { entry in
                            Button {
                                performSwap(player: player, with: entry.player)
                                activeSheet = nil
                            } label: {
                                HStack(spacing: 12) {
                                    // Position badge
                                    Text(entry.player.position.rawValue)
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundStyle(Color.backgroundPrimary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Self.positionSideColor(entry.player.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

                                    // Name
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.player.fullName)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(Color.textPrimary)
                                        if !entry.isNatural {
                                            Text("\(entry.player.position.rawValue) → \(player.position.rawValue)")
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundStyle(Color.warning)
                                        }
                                    }

                                    Spacer()

                                    // Familiarity % for out-of-position
                                    if !entry.isNatural {
                                        Text("\(entry.familiarity)%")
                                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                                            .foregroundStyle(Color.forRating(entry.familiarity))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.forRating(entry.familiarity).opacity(0.12), in: Capsule())
                                    }

                                    // Effective OVR at the target position
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text("\(entry.effectiveOVR)")
                                            .font(.headline.weight(.bold).monospacedDigit())
                                            .foregroundStyle(Color.forRating(entry.effectiveOVR))
                                        if !entry.isNatural {
                                            Text("eff. OVR")
                                                .font(.system(size: DSType.Size.micro))
                                                .foregroundStyle(Color.textTertiary)
                                        }
                                    }
                                    .frame(width: 50, alignment: .trailing)
                                }
                            }
                            .listRowBackground(Color.backgroundSecondary)
                        }
                    }
                } header: {
                    Text("Swap with")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
            .navigationTitle("Swap — \(player.fullName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { activeSheet = nil }
                }
            }
        }
        .presentationDetents([.large])
    }

    static func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    /// Swaps two players' depth chart positions by exchanging their depth order indices.
    private func performSwap(player: Player, with other: Player) {
        // If same position, swap depth order
        if player.position == other.position {
            let posPlayers = players.filter { $0.position == player.position }
            var ordered = customDepthOrder[player.position] ?? posPlayers.sorted { $0.overall > $1.overall }.map(\.id)

            if let idxA = ordered.firstIndex(of: player.id), let idxB = ordered.firstIndex(of: other.id) {
                ordered.swapAt(idxA, idxB)
                customDepthOrder[player.position] = ordered
            }
        } else {
            // Cross-position swap: exchange positions
            let posA = player.position
            let posB = other.position
            player.position = posB
            other.position = posA
            try? modelContext.save()
        }
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
                                .foregroundStyle(Color.success)
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
                                activeSheet = nil
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
                                activeSheet = nil
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
                    Button("Cancel") { activeSheet = nil }
                        .foregroundStyle(Color.textSecondary)
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
                    .foregroundStyle(Color.success)
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

    /// Color for an OVR value using the unified 5-tier rating palette.
    /// 90+ eliteGreen, 80-89 green, 70-79 blue, 60-69 yellow, <60 red.
    static func gradeColor(for avgOVR: Int) -> Color {
        Color.forRating(avgOVR)
    }

    /// THE grade colour, now owned by ``Color/forGrade(_:)-(String)`` in
    /// `UI/Common/GradeColors.swift` so a screen that tints a letter does not
    /// have to reach into the roster's grade calculator to do it. Kept as the
    /// name ~25 call sites already spell.
    static func gradeColorForLetter(_ grade: String) -> Color {
        Color.forGrade(grade)
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
    var staffLabel: String = "Solid"
    var staffColor: Color = .success
    var ownAssessment: String? = nil

    private var grades: (starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int) {
        PositionGradeCalculator.calculatePositionGrades(players: players, positions: group.positions, scheme: defensiveScheme)
    }

    private var starterCount: Int {
        group.positions.reduce(0) { $0 + PositionGradeCalculator.starterCount(for: [$1]) }
    }

    private var expiringCount: Int {
        players.filter { $0.contractYearsRemaining <= 1 }.count
    }

    private var injuredCount: Int {
        players.filter { $0.isInjured }.count
    }

    /// Total cap allocation for this position group in thousands.
    private var totalCapAllocation: Int {
        players.reduce(0) { $0 + $1.annualSalary }
    }

    /// Development trend for the position group. A real season-over-season
    /// delta requires stored group OVR history (aggregated from
    /// `PlayerSeasonHistory.overallAtEndOfSeason` across the group's starters),
    /// which is not yet plumbed into this row. Until that data exists we show a
    /// neutral placeholder rather than inventing a number from a hash — a fake
    /// "-4" that reflects nothing breaks player trust.
    /// TODO(TODO.md): wire to actual season-over-season group OVR delta.
    private var developmentTrend: (icon: String, color: Color, label: String, delta: Int) {
        ("minus", .textTertiary, "—", 0)
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
                    .font(.system(size: DSType.Size.micro, weight: .bold))
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.danger.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.danger.opacity(0.4), lineWidth: 1))
            }

            Spacer()

            // Starter grade / Depth grade — prominent sizing
            HStack(spacing: 3) {
                Text("S:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                Text(g.starterGrade)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(g.starterGrade))
                Text("/")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.textTertiary)
                Text("D:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                Text(g.depthGrade)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(g.depthGrade))
            }

            // Development trend — neutral placeholder until real
            // season-over-season group history is available (see developmentTrend).
            let trend = developmentTrend
            Text(trend.label)
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundStyle(trend.color)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(trend.color.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(trend.color.opacity(0.3), lineWidth: 0.5))
                .accessibilityLabel("Development trend not yet available")

            // Cap allocation
            Text(formattedCap)
                .font(.caption2)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

            // Starter / total count
            Text("\(starterCount)/\(players.count)")
                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

            // Expiring contracts
            if expiringCount > 0 {
                Text("\(expiringCount) exp")
                    .font(.system(size: DSType.Size.micro, weight: .bold))
                    .foregroundStyle(Color.warning)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.warning.opacity(0.15), in: Capsule())
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

            // Staff assessment badge
            Text(staffLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(staffColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(staffColor.opacity(0.15), in: Capsule())
                .overlay(Capsule().strokeBorder(staffColor.opacity(0.4), lineWidth: 1))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Review button — shows own assessment or prompts review
            if let own = ownAssessment, own != "none" {
                Text(own)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Self.ownAssessmentColor(own))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Self.ownAssessmentColor(own).opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(Self.ownAssessmentColor(own).opacity(0.4), lineWidth: 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 9))
                    Text("Review")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(Color.accentBlue)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.accentBlue.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.accentBlue.opacity(0.3), lineWidth: 1))
            }
        }
        .textCase(nil)
    }

    static func ownAssessmentColor(_ assessment: String) -> Color {
        switch assessment {
        case "Solid":           return .success
        case "Starter needed":  return .danger
        case "Depth needed":    return .warning
        case "Upgrade needed":  return .accentGold
        case "Aging":           return .accentBlue
        case "Priority":        return .danger
        default:                return .textTertiary
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
