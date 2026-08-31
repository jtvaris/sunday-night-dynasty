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
    /// #187 — the column sort, as one value on the shared standard
    /// (`DSSortState`, `DSListRow.swift`). It was two loose properties, and the
    /// pair had to be kept in step by hand at every call site that set either.
    /// Default unchanged: OVR, descending.
    @State private var sort = DSSortState<RosterSort>(key: .overall)
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

        // Warn, not gold. P5 gives gold exactly three jobs — the primary
        // commit, the current step on a band, the live/now marker — and a
        // roster group's verdict is none of them. The roster has no commit at
        // all, so the correct amount of gold on this screen is zero; before
        // this pass a bad roster could print it in four places at once.
        if depthBad { return ("Depth thin", .warning) }

        let n = PositionGradeCalculator.starterCount(for: group.positions)
        let sorted = players.sorted { $0.overall > $1.overall }
        let starters = Array(sorted.prefix(n))
        if !starters.isEmpty {
            let avgAge = starters.map(\.age).reduce(0, +) / starters.count
            let peakUpper = group.positions.map { $0.peakAgeRange.upperBound }.reduce(0, +) / max(group.positions.count, 1)
            if avgAge > peakUpper { return ("Aging", .accentBlue) }
        }

        let hasExpiring = players.contains { $0.contractYearsRemaining <= 1 && $0.overall >= grades.starterOVR - 5 }
        // Informational, and it sits beside "Aging" on the same ladder: neither
        // is a fault, both are things to note about a group that is otherwise
        // fine.
        if hasExpiring { return ("Key FA pending", .accentBlue) }

        if starterGood && depthGood { return ("Strong", .success) }
        if starterGood { return ("Solid starters", .success) }
        return ("Adequate", .textSecondary)
    }

    /// Starters sit on the **raised** surface, backups on the base card
    /// surface. Two tokens, one step apart, saying the thing the roster is
    /// grouped to say.
    ///
    /// It was a raw `Color(red: 0.10, green: 0.14, blue: 0.22)` — a hand-mixed
    /// navy roughly between `backgroundSecondary` and `backgroundTertiary` that
    /// belonged to no scale, so the one visual distinction the depth chart
    /// makes was the only paint on the screen that could not be adjusted with
    /// the theme.
    private func starterRowBackground(player: Player, groupPlayers: [Player], starterCount: Int) -> Color {
        let idx = depthIndex(for: player, in: groupPlayers)
        return idx < starterCount ? Color.backgroundTertiary : Color.backgroundSecondary
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

    /// Your own verdict on a group, on the same five-step ladder the staff
    /// read uses: danger (broken) / warning (caution) / accentBlue (noted) /
    /// success (good) / textTertiary (unset). "Upgrade needed" was gold, which
    /// is the screen's commit paint on a screen that never commits (P5); it is
    /// a caution, and it now says so in the same colour "Depth needed" does.
    private func assessmentColor(_ assessment: String) -> Color {
        switch assessment {
        case "Solid":           return .success
        case "Starter needed":  return .danger
        case "Depth needed":    return .warning
        case "Upgrade needed":  return .warning
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

        // #187 / #134a: every branch below ends in an id tiebreak, because a
        // comparator that calls two equal-OVR players "not less than each other"
        // is not an ordering and `sorted(by:)` may hand back either arrangement.
        // Over a `@Query` result, whose own fetch order is unspecified, that is
        // rows swapping places on an unrelated redraw.
        //
        // A second thing changed with the standard: the direction is now the
        // SAME for every column. `age` and `name` used to be wired backwards —
        // "descending" gave you the youngest player and the A's — so the chevron
        // the header draws would have pointed the wrong way on two of five
        // columns. Descending is now "most of this first" everywhere.
        let asc = sort.ascending
        switch sort.key {
        case .overall:
            return filtered.dsSorted(asc, by: \.overall, id: \.id)
        case .position:
            return filtered.dsSorted(asc, id: \.id) { lhs, rhs in
                let side = positionSideOrder(lhs.position.side, rhs.position.side)
                if side != 0 { return side < 0 ? .orderedAscending : .orderedDescending }
                let order = dsCompare(
                    Position.allCases.firstIndex(of: lhs.position) ?? 0,
                    Position.allCases.firstIndex(of: rhs.position) ?? 0
                )
                if order != .orderedSame { return order }
                // Inside one position the better player leads in both
                // directions — reversing the position order should not also
                // turn every group upside down.
                return dsCompare(rhs.overall, lhs.overall)
            }
        case .age:
            return filtered.dsSorted(asc, by: \.age, id: \.id)
        case .salary:
            return filtered.dsSorted(asc, by: \.annualSalary, id: \.id)
        case .name:
            return filtered.dsSorted(asc, by: \.lastName, id: \.id)
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
    ///
    /// "Biggest Need" is a RANKING, so it needs a field to rank. The Special
    /// Teams side holds exactly one group (`specialTeamsGroups` is
    /// single-element, because only K and P are on `.specialTeams`), so the
    /// chip fired on Specialists in every save, in every season, whatever the
    /// kicker's rating — a red alarm that carried no information because
    /// nothing could ever have out-ranked it. With fewer than two groups to
    /// compare there is no weakest one, and the header draws no chip.
    private var weakestGroupName: String? {
        var stocked: [(name: String, avg: Double)] = []
        for group in activeGroups {
            let groupPlayers = filteredPlayers.filter { group.positions.contains($0.position) }
            guard !groupPlayers.isEmpty else { continue }
            let avg = Double(groupPlayers.reduce(0) { $0 + $1.overall }) / Double(groupPlayers.count)
            stocked.append((group.name, avg))
        }
        guard stocked.count > 1 else { return nil }
        return stocked.min { $0.avg < $1.avg }?.name
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
                    phase: career?.currentPhase,
                    // …and the save itself, so the cap cell can push the
                    // breakdown that attributes its dead money.
                    career: career
                )

                controlStrip

                if viewMode == .list {
                    topDecisionsCard
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
    ///
    /// A club glyph rather than the three-person one: this sits directly beside
    /// the practice-squad button in the toolbar, and the two shipped pixel
    /// identical. What distinguishes this one is that it browses *teams*.
    @ViewBuilder
    private var leagueRostersButton: some View {
        if let career {
            NavigationLink {
                LeagueRostersView(career: career)
            } label: {
                Label("League Rosters", systemImage: "building.2")
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
                        .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
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

    // MARK: - Control strip

    /// The roster's one band of chrome: **what shape you are looking at**, and
    /// **which columns are on**.
    ///
    /// It was two stacked bands, and between them they spent something like
    /// 110 pt above the first player on a screen whose entire job is the
    /// players. The first was a two-option segmented control handed the full
    /// 1000 pt width of a portrait iPad — a binary switch drawn as a header
    /// band. The second was a hand-rolled capsule strip under an
    /// `ANALYSIS · OVERVIEW` ident that restated, in tracked caps, the one
    /// capsule already filled blue four points beneath it.
    ///
    /// One line now. The shape switch takes the width a two-option control
    /// actually needs and the lens strip takes the rest, which is also why the
    /// strip passes no `title:` — `DSLensTabs` will happily draw the same
    /// redundant ident, and the selected capsule *is* the title.
    private var controlStrip: some View {
        HStack(spacing: DSSpacing.md) {
            viewModePicker
                .frame(width: 280)

            if viewMode == .list {
                analysisLensTabs
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
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

    // MARK: - Analysis Lens (#96, #98)

    /// The lens strip, on the shared control (`DSLensTabs`, `DSListRow.swift`).
    ///
    /// `DSLensTabs`' own documentation names this exact strip as one of the
    /// three styles it exists to collapse — "the roster's analysis pills (with
    /// a blue glow the board's do not have)" — and the glow was the tell: it
    /// was the only capsule in the app carrying a coloured shadow, so the
    /// roster's selected lens looked like a different kind of object from the
    /// board's. The hand-rolled version also measured ~30 pt tall against
    /// §2.12's 44 pt floor, which is the one number a lens strip cannot get
    /// wrong: it is the control the user hits most often on this screen.
    ///
    /// Nothing about *what* the lenses do changes — same seven modes, same
    /// `analysisMode` binding, same `analysisHeaderColumns` reading it.
    private var analysisLensTabs: some View {
        DSLensTabs(
            selection: $analysisMode,
            lenses: lenses(for: selectedSide),
            label: { $0.label },
            icon: { $0.icon }
        )
    }

    /// The lenses offered on one side of the ball.
    ///
    /// #3198 — **Depth is dropped on Special Teams, and only there.** It is the
    /// one lens that is provably degenerate at two players: `specialTeamsGroups`
    /// is a single group holding one K and one P, so every man is first at his
    /// own position and the column can print nothing but "Starter", in every
    /// save, in every season. That is not a thin reading, it is a column with
    /// one possible value.
    ///
    /// The other six stay. Read against a kicker they all resolve to something
    /// real — Overview, Contracts, Development and Mental print his actual
    /// numbers, and Position Skills lands on the kicking pair — and Physical in
    /// particular was NOT cut: SPD and STR are noise on a kicker, but DUR and
    /// fatigue are not, and hiding the row to be rid of two cells loses the two
    /// that matter.
    private func lenses(for side: RosterFilter) -> [RosterAnalysisMode] {
        side == .specialTeams
            ? RosterAnalysisMode.allCases.filter { $0 != .depth }
            : RosterAnalysisMode.allCases
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

    // MARK: - Top Decisions (#3172)

    /// The three most pressing decisions on the roster.
    ///
    /// Not a second opinion: this is literally Roster Evaluation's own ranked
    /// "Key Decisions" list — the same `KeyDecisionBuilder`, whose order already
    /// puts a man weighing retirement ahead of an expiring deal ahead of a
    /// contract out of step with the market — cut to its top three. A generator
    /// of its own here would have disagreed with that screen the first week
    /// either set of rules was edited.
    ///
    /// The franchise-tag quote is left out on purpose: pricing a tag needs the
    /// LEAGUE's top-5 salaries at the position, which this screen does not fetch
    /// and has no other reason to, so an elite expiring player reads the generic
    /// "prioritize extension" line here and the tag number one tap away, on the
    /// screen that already holds the league.
    ///
    /// Sharing the generator was only half of "the same three". `build` ranks by
    /// decision KIND and nothing else, so inside a kind the order is whatever
    /// order it was handed the roster in — and Roster Evaluation hands it a
    /// salary-descending fetch (`loadData`) while this screen's fetch
    /// (`RosterViewWrapper`) asks for no order at all. With no retirement
    /// candidates and a dozen expiring deals, the common case, that screen
    /// listed the three highest-paid expiring men and this card listed three
    /// arbitrary ones — the exact drift a shared builder was supposed to end.
    /// So the roster is put in the same order here before it goes in.
    private var topDecisions: [KeyDecision] {
        Array(
            KeyDecisionBuilder.build(
                players: players.sorted { $0.annualSalary > $1.annualSalary },
                salaryCap: teamSalaryCap,
                availableCap: teamCapUsed.map { teamSalaryCap - $0 }
            ).prefix(3)
        )
    }

    /// Read-only, above the list, and it commits nothing.
    ///
    /// The priorities the user types into a group header are his own and stay
    /// his own (#283) — this sits beside them rather than over them, and its one
    /// affordance is the way through to the screen that owns these decisions in
    /// full, with the money, the FA replacements and the negotiation.
    ///
    /// Above the list rather than inside it, and only in list mode. Inside it,
    /// `List` hangs its own disclosure chevron on any `NavigationLink` row — the
    /// same one the player rows carry and `sortableHeader` reserves a gutter for
    /// — so a card with its own "Roster Evaluation ›" affordance would have
    /// shipped with two arrows pointing the same way. It is kept to three tight
    /// lines for the same reason the control strip was collapsed to one band:
    /// the screen's job is the players underneath it.
    @ViewBuilder
    private var topDecisionsCard: some View {
        if let career {
            let decisions = topDecisions
            if !decisions.isEmpty {
                NavigationLink {
                    RosterEvaluationView(career: career)
                } label: {
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        HStack(spacing: DSSpacing.xxs) {
                            SectionHeaderText(title: "Top Decisions")
                            Spacer(minLength: DSSpacing.xxs)
                            Text("Roster Evaluation")
                                .font(DSType.text(11, .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: DSType.Size.micro, weight: .bold))
                        }
                        .foregroundStyle(Color.accentGold)

                        ForEach(decisions) { decision in
                            topDecisionRow(decision)
                        }
                    }
                    .padding(DSSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .fill(Color.backgroundSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DSSpacing.md)
                .padding(.bottom, DSSpacing.xxs)
            }
        }
    }

    /// One line: who, what kind of decision, and how good he is. The verb is the
    /// badge — the reasoning and the money live on the screen this links to, and
    /// repeating a two-line recommendation three times would cost more height
    /// than the whole card is worth.
    private func topDecisionRow(_ decision: KeyDecision) -> some View {
        let badge = decision.type.badge
        return HStack(spacing: DSSpacing.xs) {
            Text(decision.player.position.rawValue)
                .font(DSType.display(11, .heavy))
                .foregroundStyle(Color.textTertiary)
                .frame(width: DSListColumn.position, alignment: .leading)

            Text(decision.player.fullName)
                .font(DSType.text(12, .semibold, prose: true))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(badge.label)
                .font(DSType.display(11, .heavy))
                .foregroundStyle(badge.color)
                .padding(.horizontal, DSSpacing.xxs)
                .background(badge.color.opacity(0.15), in: Capsule())

            Spacer(minLength: DSSpacing.xxs)

            Text("\(decision.player.overall)")
                .font(DSType.display(12, .heavy))
                .foregroundStyle(Color.forRating(decision.player.overall))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(decision.player.fullName), \(decision.player.position.rawValue), \(badge.label), \(decision.player.overall) overall")
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

            // #3196 / #3202 / #3199 / #3209 — what the Special Teams side holds
            // BELOW the two men the domain actually seats. Offense and Defense
            // are untouched: they have eight stocked groups between them and
            // none of this reading to do.
            if selectedSide == .specialTeams {
                // Decoded and reconciled ONCE for the whole block — the units
                // and the rating both want the chart, and it is real work.
                let chart = savedDepthChart
                ForEach(SpecialTeamsUnitBuilder.units(roster: players, chart: chart)) { unit in
                    specialTeamsUnitSection(unit)
                }
                kickingGameSection
                unitRatingSection(chart: chart)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        // insetGrouped's stock top inset and section gaps left a wide band of
        // empty navy between the control strip and the first position group —
        // roughly a third of a screen before any player was visible.
        .listSectionSpacing(12)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // MARK: - Special Teams: Derived Units (#3196, #3202)

    /// The saved depth chart, reconciled against today's roster — or `nil` when
    /// this save has never set one (and for every preview / lightweight call
    /// site, which carry no `Career`).
    ///
    /// Read ONLY on the Special Teams side, because decoding and reconciling a
    /// chart is real work and the other two sides ask nothing of it.
    private var savedDepthChart: DepthChart? {
        guard selectedSide == .specialTeams, let career else { return nil }
        return DepthChart.saved(career: career, roster: players)
    }

    /// One derived unit as a section: its men, then the line saying where they
    /// came from and what the simulator does with them.
    ///
    /// The rows are `NavigationLink`s to the player card and nothing else. That
    /// is the whole of "read-only": you can look the man up, you cannot give
    /// him the job, because there is no job in the save to give.
    @ViewBuilder
    private func specialTeamsUnitSection(_ unit: SpecialTeamsUnit) -> some View {
        Section {
            if unit.members.isEmpty {
                Text("Nobody on the roster fits this job.")
                    .font(DSType.text(DSType.Size.footnote, .medium, prose: true))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .listRowBackground(Color.backgroundSecondary)
            } else {
                ForEach(unit.members) { member in
                    NavigationLink(destination: PlayerDetailView(player: member.player)) {
                        specialTeamsMemberRow(member)
                    }
                    .listRowBackground(member.isListed ? Color.backgroundTertiary : Color.backgroundSecondary)
                }
            }
            DSDetailNote(text: unit.note)
                .listRowBackground(Color.backgroundSecondary)
        } header: {
            DSGroupRollup(title: unit.title, facts: unit.facts, tint: .textPrimary)
                .textCase(nil)
        }
    }

    /// Job, position, name, and the measured traits he was picked on.
    ///
    /// Deliberately NOT `PlayerRowView`: that row's anatomy is a depth chip, a
    /// tappable position badge and a starter badge — three affordances that
    /// change the man's job — and a unit nothing can be assigned to must not
    /// offer them.
    private func specialTeamsMemberRow(_ member: SpecialTeamsUnit.Member) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text(member.role)
                .font(DSType.display(11, .heavy))
                .foregroundStyle(member.isListed ? Color.accentBlue : Color.textTertiary)
                .frame(width: DSListColumn.position, alignment: .leading)

            Text(member.player.position.rawValue)
                .font(DSType.display(11, .heavy))
                .foregroundStyle(Color.textTertiary)
                .frame(width: DSListColumn.position, alignment: .leading)

            Text(member.player.fullName)
                .font(DSType.text(12, .semibold, prose: true))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer(minLength: DSSpacing.xxs)

            traitCell(member.traitLabel, member.traitValue)
            if let label = member.secondLabel, let value = member.secondValue {
                traitCell(label, value)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(member.player.fullName), \(member.player.position.rawValue), \(member.role)"
            + (member.isListed ? ", listed on the depth chart" : "")
            + ", \(member.traitLabel) \(member.traitValue)"
        )
    }

    /// A measured trait over its own three-letter caption — the same number
    /// over caption the analysis lenses draw in the rows above.
    private func traitCell(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 0) {
            Text("\(value)")
                .font(DSType.display(12, .heavy))
                .foregroundStyle(Color.forRating(value))
            Text(label)
                .font(DSType.display(DSType.Size.micro, .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: DSListColumn.attribute)
    }

    // MARK: - Special Teams: The Kicking Game (#3199)

    /// What fills the space under a two-row list: the kicking game, in the two
    /// numbers the engine actually uses and the production it actually recorded.
    ///
    /// Every figure here is quoted, not modelled:
    ///
    ///   * **Longest attempt** is `PlaySimulator.fieldGoalRangeYards` — the
    ///     club's real 4th-down cutoff, which reads `kickPower` and nothing
    ///     else — plus the 17 yards of snap and hold its own documentation
    ///     names. It is the one place a kicker's leg is visible as the yard
    ///     line it changes rather than as a 0-99 attribute.
    ///   * **Field goals** come off `Player.seasonStatLine`, which is what the
    ///     simulator recorded — `SeasonStatLine.add` folds `fieldGoalsMade` and
    ///     `fieldGoalsAttempted` out of every box score. Nothing is projected: a
    ///     club that has not kicked yet is told it has not kicked yet.
    ///   * **Punting production is not shown at all**, because no function
    ///     produces it in season. `PlayerGameStats` has no punting column, so
    ///     `SeasonStatLine.add` leaves `punts` and `puntAverage` untouched
    ///     forever; `WeekAdvancer.recordSeasonHistory` tops both up from
    ///     `SeasonStatSynthesizer` — a table keyed on OVERALL — into the season
    ///     history row only. `line.punts` on a live punter is therefore always
    ///     0. What the punter DOES change is the punt itself: the net draw at
    ///     `PlaySimulator.simulatePunt` is centred on `kickPower` and reads
    ///     nothing else, so that attribute is what this card prints.
    @ViewBuilder
    private var kickingGameSection: some View {
        let kicker = SpecialTeamsUnitBuilder.best(.K, in: players)
        let punter = SpecialTeamsUnitBuilder.best(.P, in: players)
        Section {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                if let kicker {
                    let line = kicker.seasonStatLine
                    let attempt = PlaySimulator.fieldGoalRangeYards(for: SimPlayer(from: kicker)) + 17
                    DSDetailRow("Kicker", kicker.fullName)
                    DSDetailRow("Longest attempt", "\(attempt) yd", tint: .accentGold)
                    DSDetailRow(
                        "Field goals",
                        line.fieldGoalsAttempted > 0
                            ? "\(line.fieldGoalsMade) of \(line.fieldGoalsAttempted)"
                            : "none attempted yet",
                        tint: line.fieldGoalsAttempted > 0 ? .textPrimary : .textTertiary
                    )
                } else {
                    DSDetailRow("Kicker", "nobody on the roster", tint: .danger)
                }

                if let punter {
                    DSDetailRow("Punter", punter.fullName)
                    if case .kicking(let attrs) = punter.positionAttributes {
                        DSDetailRow("Punting leg", "PWR \(attrs.kickPower)", tint: .accentGold)
                    }
                } else {
                    DSDetailRow("Punter", "nobody on the roster", tint: .danger)
                }

                DSDetailNote(
                    text: "Longest attempt is the engine's own cutoff — it reads the kicker's leg and "
                        + "nothing else, and the staff punts rather than try past it. Field goals are "
                        + "the count the box score kept. Punting production is not shown because the "
                        + "game does not record it: a box score has no punting column, so a punter's "
                        + "punts and average are modelled from his overall only when the season is "
                        + "filed. The leg above is the attribute every punt in the sim is centred on."
                )
            }
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            DSGroupRollup(title: "Kicking Game", facts: ["what the sim reads"], tint: .textPrimary)
                .textCase(nil)
        }
    }

    // MARK: - Special Teams: Unit Rating (#3209)

    /// The unit as one number, with every term it was cut from printed beneath
    /// it — because two of those terms are stand-ins and a bare 74 could not
    /// say so.
    @ViewBuilder
    private func unitRatingSection(chart: DepthChart?) -> some View {
        let unit = SpecialTeamsUnitBuilder.rating(roster: players, chart: chart)
        Section {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                    Text(unit.rating.map { "\($0)" } ?? "\u{2014}")
                        .font(DSType.display(DSType.Size.title1, .black))
                        .foregroundStyle(unit.rating.map { Color.forRating($0) } ?? Color.textTertiary)
                    Text("of 100")
                        .font(DSType.display(DSType.Size.caption, .semibold))
                        .foregroundStyle(Color.textTertiary)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    unit.rating.map { "Special teams unit rating \($0) of 100" }
                        ?? "Special teams unit rating unavailable"
                )

                ForEach(unit.terms) { term in
                    DSDetailRow(label: term.label) {
                        HStack(spacing: DSSpacing.xs) {
                            Text(term.detail)
                                .font(DSType.display(DSType.Size.caption, .semibold))
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(term.value.map { "\($0)" } ?? "\u{2014}")
                                .font(DSType.display(DSType.Size.callout, .heavy))
                                .foregroundStyle(term.value.map { Color.forRating($0) } ?? Color.textTertiary)
                                .frame(width: DSListColumn.tight, alignment: .trailing)
                        }
                    }
                }

                DSDetailNote(
                    text: "An even average of the five jobs, each read on the trait that job is picked "
                        + "on. The kicker and the punter are the halves the simulator uses today — the "
                        + "kicker on leg and accuracy, the punter on his leg alone, which is all a punt "
                        + "reads. The return and coverage terms are a stand-in, because kickoff returns "
                        + "are rolled without reading a player and no coverage unit exists to field; "
                        + "coverage is speed, plus tackling only for the linebackers, since no other "
                        + "room carries a tackling rating. The returner terms follow the depth chart "
                        + "across the whole roster, so either can name a man the Return Men list above "
                        + "did not scout."
                )
            }
            .listRowBackground(Color.backgroundSecondary)
        } header: {
            DSGroupRollup(
                title: "Unit Rating",
                facts: ["\(unit.terms.compactMap(\.value).count) of \(unit.terms.count) jobs filled"],
                tint: .textPrimary
            )
            .textCase(nil)
        }
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
                        .font(.system(size: DSType.Size.caption))
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
                headerLabel("Pot", width: 20)
                sortButton("Salary", sort: .salary, width: 52)
                // The `Yrs` and health columns left this lens with the cells
                // they headed — the EXT and HLTH slots beside the name already
                // carry both facts, and drawing them twice per row is the
                // "one encoding per quantity" rule this row documents twice.
                headerLabel("Mor", width: 24)
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
                // `Player.fatigue` and `Player.workloadStatus` are both live
                // all season — the sim charges a rating penalty above 70 and
                // an injury multiplier above 50 — and no roster lens drew
                // either. The Physical lens is where the body is read.
                headerLabel("Ftg", width: DSListColumn.attribute)
                headerLabel("Health", width: 28)
                sortButton("OVR", sort: .overall, width: PlayerRowView.Column.ovr)
            }
        case .attributes:
            Group {
                // ONE label over the whole block, because the columns under it
                // are not the same four attributes on every row: a QB's are ACC
                // / ARM / AWR, a corner's are MAN / ZON / PRS, and each cell
                // already prints its own ident under the number
                // (`PlayerRowView.colorCodedMiniAttribute`). Four per-column
                // headers cannot be right for more than one position at a time,
                // which is why they shipped as "Skill 1"…"Skill 4" — a
                // placeholder header is worse than none.
                //
                // The width is the four 32 pt cells plus the three gaps between
                // them, so the OVR label after it still lands on OVR.
                headerLabel("Position skills", width: 32 * 4 + PlayerRowView.Column.gap * 3)
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

    /// #187 — the static half of the header, on the same component as the
    /// sortable half. Both are now `DSListRow`'s: a header row where the
    /// tappable labels are uppercase tracked display and the untappable ones are
    /// mixed-case body text reads as two headers stacked, which is exactly what
    /// adopting the standard on only the sort columns would have produced.
    /// `DSColumnHeader` also brings the shrink-then-clip rule, so "Health" in a
    /// 28 pt column shrinks instead of wrapping.
    private func headerLabel(_ title: String, width: CGFloat) -> some View {
        DSColumnHeader(title, width: width)
    }

    // The icon column header is gone with its last caller. It headed the
    // morale and health columns with the same glyph the cell under it drew, so
    // the header said nothing the row did not already say — and on the morale
    // column, where the glyph is a face, nothing on the screen named the
    // quantity at all. Both columns now carry a word.

    /// Width the `NavigationLink` disclosure chevron occupies on every player
    /// row. The header row has no chevron, so without reserving the same gutter
    /// its columns sit ~21pt right of the values they label.
    private static let disclosureGutter: CGFloat = 21

    /// #187 — the roster's hand-rolled sort header, now the shared one
    /// (`DSSortableColumnHeader`). The tap rule, the chevron, the active tint and
    /// the shrink-before-clip behaviour all live in `DSListRow.swift`; this is
    /// the call site's binding and nothing else.
    private func sortButton(_ title: String, sort key: RosterSort, width: CGFloat?) -> some View {
        DSSortableColumnHeader(title, key: key, sort: $sort, width: width)
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
                        // #3198: a side that does not offer the current lens
                        // would otherwise land on a strip with no capsule lit
                        // while the rows below still drew the hidden column.
                        if !lenses(for: filter).contains(analysisMode) {
                            analysisMode = .overview
                        }
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
            ForEach(RosterSort.allCases) { option in
                Button {
                    // Same tap rule as the column headers — one implementation
                    // (#187), so the menu and the header can never disagree
                    // about what a second tap does.
                    withAnimation(.easeInOut(duration: 0.2)) { sort.tap(option) }
                } label: {
                    HStack {
                        Label(option.label, systemImage: option.icon)
                        if sort.isActive(option) {
                            Image(systemName: sort.directionSymbol)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: sort.ascending ? "arrow.up" : "arrow.down")
                Text(sort.key.label)
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
        .accessibilityLabel("Sort roster, currently by \(sort.key.label) \(sort.spokenDirection)")
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
                            .font(.system(size: DSType.Size.caption, weight: .heavy))
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
                                        .font(.system(size: DSType.Size.caption, weight: .heavy))
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
                                                .font(.system(size: DSType.Size.footnote, weight: .medium))
                                                .foregroundStyle(Color.warning)
                                        }
                                    }

                                    Spacer()

                                    // Familiarity % for out-of-position
                                    if !entry.isNatural {
                                        Text("\(entry.familiarity)%")
                                            .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
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
                                    .font(.system(size: DSType.Size.body, weight: .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                HStack(spacing: 8) {
                                    Text("OVR \(current.overall)")
                                        .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                                        .foregroundStyle(Color.forPlayerCardRating(current.overall))
                                    Text("Age \(current.age)")
                                        .font(.system(size: DSType.Size.caption))
                                        .foregroundStyle(Color.textTertiary)
                                    Text(starterPickerFormatSalary(current.annualSalary))
                                        .font(.system(size: DSType.Size.caption))
                                        .foregroundStyle(Color.textTertiary)
                                    if current.isInjured {
                                        HStack(spacing: 2) {
                                            Image(systemName: "cross.circle.fill")
                                                .font(.system(size: DSType.Size.micro))
                                            Text("\(current.injuryWeeksRemaining)w")
                                                .font(.system(size: DSType.Size.micro))
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
                                .font(.system(size: DSType.Size.micro))
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
                    .font(.system(size: DSType.Size.callout, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.forPlayerCardRating(player.overall))

                // Effective OVR for out-of-position
                if isVersatile {
                    let familiarity = player.familiarity(at: position)
                    let effective = Int(Double(player.overall) * Double(familiarity) / 100.0)
                    Text("~\(effective)")
                        .font(.system(size: DSType.Size.micro, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                // Name, position, age
                Text(player.fullName)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 6) {
                    Text(player.position.rawValue)
                        .font(.system(size: DSType.Size.caption, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Text("Age \(player.age)")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textTertiary)

                    // Salary
                    Text(starterPickerFormatSalary(player.annualSalary))
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textTertiary)

                    // Form trend arrow
                    let trend = starterPickerTrend(for: player)
                    Image(systemName: trend.icon)
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(trend.color)

                    // Health/injury status
                    if player.isInjured {
                        HStack(spacing: 2) {
                            Image(systemName: "cross.circle.fill")
                                .font(.system(size: DSType.Size.micro))
                            Text("\(player.injuryWeeksRemaining)w")
                                .font(.system(size: DSType.Size.micro))
                        }
                        .foregroundStyle(Color.danger)
                    }
                }

                // Versatility info for out-of-position players
                if isVersatile {
                    let familiarity = player.familiarity(at: position)
                    let effective = Int(Double(player.overall) * Double(familiarity) / 100.0)
                    Text("\(player.position.rawValue) at \(position.rawValue): \(player.overall) \u{00d7} \(familiarity)% = ~\(effective) effective")
                        .font(.system(size: DSType.Size.footnote))
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
                        .font(.system(size: DSType.Size.footnote, weight: .medium))
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

    /// Printed where a depth grade would go when a group carries no backups at
    /// all. Not a letter, deliberately — there is nobody behind the starters to
    /// grade, and the em dash keeps it out of `Color.forGrade`'s red.
    static let noDepthGrade = "\u{2014}"

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
        // `noDepthGrade` is the one string here that is not a grade, so it does
        // not get a grade's colour — `Color.forGrade` would drop it into the
        // same red as an F, which is the verdict it exists to avoid.
        grade == noDepthGrade ? .textTertiary : Color.forGrade(grade)
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
        // No backups is nothing to grade, not a failing grade. Special teams
        // wants exactly one kicker and one punter, so every club in the league
        // carried a permanent red "D: F" on a room that was fully stocked.
        let dGrade = backups.isEmpty ? noDepthGrade : letterGrade(for: depthAvg)

        return (sGrade, dGrade, starterAvg, depthAvg)
    }
}

// MARK: - Special Teams Derived Units (#3196, #3202)

/// One special-teams job the roster can be **read** for and not assigned to.
///
/// `Position.side` puts exactly two men on `.specialTeams` — the kicker and the
/// punter — so the return, coverage and blocking units below are DERIVED from
/// players who already hold another job. Nothing here writes: no slot, no depth
/// order, no `Player` field. It is a reading of the roster the club already has,
/// which is why every row carries the measured trait it was picked on rather
/// than a rank.
///
/// **Written so the two real positions can land without a rewrite.** When the
/// long snapper and the holder become `Position` cases with their own ideal
/// roster counts and generation (their own gated wave), they join
/// ``RosterView/specialTeamsGroups``' `positions` array and list themselves
/// beside the kicker like any other stocked room. Nothing in this file moves:
/// these units are keyed on traits and roster membership, never on the
/// `.specialTeams` side, so two more real specialists change only the group
/// above them.
struct SpecialTeamsUnit: Identifiable {
    /// "Return Men", "Coverage Unit", "Blocking Wall".
    let title: String
    /// Short facts for the header rollup — already formatted.
    let facts: [String]
    /// Where the men came from, and what the simulator does with them. Every
    /// unit here says the second part, because for two of the three the honest
    /// answer today is "nothing".
    let note: String
    let members: [Member]

    var id: String { title }

    struct Member: Identifiable {
        let player: Player
        /// The job, as the depth chart spells it where the chart has one: KR,
        /// PR, GUN, WALL.
        let role: String
        /// The trait he was picked on, named and measured.
        let traitLabel: String
        let traitValue: Int
        /// A second measured trait, present ONLY where the domain models it for
        /// this man — a running back has elusiveness and a corner does not, and
        /// the row prints nothing rather than a substitute.
        let secondLabel: String?
        let secondValue: Int?
        /// True when the saved depth chart already lists him in this job. The
        /// only real state any of these rows can report.
        let isListed: Bool

        /// Role FIRST, then the man — because one man holds two jobs in the
        /// same list more often than not. The Return Men unit is KR (ranked on
        /// speed) concatenated with PR (ranked on agility) over the SAME WR /
        /// RB / CB pool, and the two traits correlate, so the club's best
        /// athlete is routinely both. Keyed on `player.id` alone, `ForEach`
        /// saw one UUID twice and SwiftUI's diff is undefined there.
        var id: String { "\(role)-\(player.id.uuidString)" }
    }
}

/// Derives the special-teams units, and the unit rating, from a roster.
///
/// Kept out of the view for the same reason `PositionGradeCalculator` is: the
/// arithmetic is the part worth reading, and it must be quotable from one place
/// when the long snapper and the holder arrive.
enum SpecialTeamsUnitBuilder {

    // MARK: Populations

    /// Where the return game is scouted from (#3196).
    static let returnPool: [Position] = [.WR, .RB, .CB]

    /// Where the punt / field-goal wall is scouted from — the rooms whose
    /// attributes actually model blocking. A running back blocks in real
    /// football and `RBAttributes` has no field for it, so the fullback and the
    /// backs are deliberately absent rather than ranked on a stand-in.
    static let blockingPool: [Position] = [.LT, .LG, .C, .RG, .RT, .TE]

    /// Ten men cover a kick; the kicker is the eleventh.
    static let coverageSize = 10

    /// Five hold the interior wall in front of the snap.
    static let blockingSize = 5

    // MARK: Traits

    /// Deterministic ranking: the trait, then overall, then the id — because a
    /// comparator that calls two equal-speed men "not less than each other" is
    /// not an ordering, and this list is rebuilt on every redraw.
    static func ranked(_ players: [Player], by trait: (Player) -> Int) -> [Player] {
        players.sorted { lhs, rhs in
            let a = trait(lhs), b = trait(rhs)
            if a != b { return a > b }
            if lhs.overall != rhs.overall { return lhs.overall > rhs.overall }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// The best man at a position by overall, or `nil` if the club has none.
    static func best(_ position: Position, in roster: [Player]) -> Player? {
        ranked(roster.filter { $0.position == position && !$0.isRetired }, by: { $0.overall }).first
    }

    /// Elusiveness, where the domain models it. Only `RBAttributes` carries the
    /// field, so this is `nil` for the receivers and corners in the same list.
    static func elusiveness(of player: Player) -> Int? {
        if case .runningBack(let a) = player.positionAttributes { return a.elusiveness }
        return nil
    }

    /// Tackling, where the domain models it. Only `LBAttributes` carries the
    /// field — the defensive backs and receivers who make up most of a real
    /// coverage unit have no tackling rating at all — so the row prints it for
    /// the linebackers and prints nothing for everyone else.
    static func tackling(of player: Player) -> Int? {
        if case .linebacker(let a) = player.positionAttributes { return a.tackling }
        return nil
    }

    /// The blocking read for the wall, on each room's own attributes: pass
    /// protection and anchor averaged for a lineman, the tight end's blocking
    /// grade.
    ///
    /// The lineman's caption is PRO and deliberately NOT "PBK". PBK means
    /// exactly `passBlock` everywhere else in the app — `PlayerRowView`'s
    /// attribute triple, `ScoutingEngine`, `ProspectFog` — and the same man
    /// printing two different numbers under one three-letter caption is the
    /// caption lying, not the arithmetic. This is a different quantity, so it
    /// gets a different name and the unit's note says what it is made of.
    static func blocking(of player: Player) -> (label: String, value: Int)? {
        switch player.positionAttributes {
        case .offensiveLine(let a): return ("PRO", (a.passBlock + a.anchor) / 2)
        case .tightEnd(let a):      return ("BLK", a.blocking)
        default:                    return nil
        }
    }

    /// How a coverage man is ranked: speed, plus tackling **where it exists**.
    ///
    /// #3209 asked for "speed + tackling". `tackling` is a field on
    /// `LBAttributes` and on nothing else, so for the corners, receivers and
    /// backs who make up most of a gunner unit there is no second half to add —
    /// and inventing one (borrowing man coverage, scaling strength) would be
    /// exactly the coefficient this screen refuses to print. Where the man has
    /// a tackling rating the term is the mean of the two; where he does not it
    /// is his speed, and the row shows which by printing a TAK cell or not.
    static func coverageScore(_ player: Player) -> Int {
        guard let tackle = tackling(of: player) else { return player.physical.speed }
        return (player.physical.speed + tackle) / 2
    }

    /// The men who are not first choice in their own room, kicker and punter
    /// excluded — a club fields one of each and neither covers a kick.
    ///
    /// Uses the same `idealStarterCounts` the roster's own group grades use, so
    /// "non-starter" means here what it means three rows up the screen.
    static func nonStarters(in roster: [Player]) -> [Player] {
        var byPosition: [Position: [Player]] = [:]
        for player in roster where !player.isRetired && player.position.side != .specialTeams {
            byPosition[player.position, default: []].append(player)
        }
        var reserves: [Player] = []
        for (position, room) in byPosition {
            let starters = PositionGradeCalculator.idealStarterCounts[position] ?? 1
            reserves.append(contentsOf: ranked(room, by: { $0.overall }).dropFirst(starters))
        }
        return reserves
    }

    // MARK: Units

    /// The listed man for a returner slot, plus the men the roster would put
    /// there — the chart's own holder first, so a coach who has set the slot
    /// always sees his choice even when a faster body has since arrived.
    private static func returners(
        pool: [Player],
        roster: [Player],
        trait: DepthChartSlot.RankingTrait,
        depth: Int,
        listed: UUID?
    ) -> [Player] {
        var picked = Array(ranked(pool, by: { trait.value(of: $0) }).prefix(depth))
        if let listed,
           !picked.contains(where: { $0.id == listed }),
           let holder = roster.first(where: { $0.id == listed }) {
            picked.insert(holder, at: 0)
        }
        return picked
    }

    static func units(roster: [Player], chart: DepthChart?) -> [SpecialTeamsUnit] {
        let active = roster.filter { !$0.isRetired }
        let returnCandidates = active.filter { returnPool.contains($0.position) }
        // `chart?.starter(for:)` is doubly optional — no chart, or a chart with
        // an empty slot — and the two mean the same thing here, so they are
        // flattened once rather than unwrapped twice at every use.
        let krListed: UUID? = chart?.starter(for: .KR) ?? nil
        let prListed: UUID? = chart?.starter(for: .PR) ?? nil

        // Return men — ranked on the trait the depth chart's own slot ranks on
        // (`DepthChartSlot.rankingTrait`: KR speed, PR agility), and as deep as
        // that slot goes.
        //
        // The POOL is narrower than the chart's, and deliberately: KR and PR are
        // `acceptsAnyPosition`, so `DepthChart.reconcile` ranks the whole roster
        // and the picker offers every player, while this list scouts `returnPool`
        // (WR / RB / CB) only. A fast safety is a legitimate chart candidate and
        // will not appear here unless the chart already lists him — which is why
        // the listed man is always spliced in above, and why the header says
        // where this list looked. Same reason the Unit Rating's returner term can
        // name a man who is not in this section: its fallback follows `reconcile`
        // across the whole roster, not this pool.
        let kickReturners = returners(
            pool: returnCandidates, roster: active, trait: .speed,
            depth: DepthChartSlot.KR.maxDepth, listed: krListed
        )
        let puntReturners = returners(
            pool: returnCandidates, roster: active, trait: .agility,
            depth: DepthChartSlot.PR.maxDepth, listed: prListed
        )
        let returnUnit = SpecialTeamsUnit(
            title: "Return Men",
            facts: ["from WR / RB / CB", "\(returnCandidates.count) candidates"],
            note: "Derived from the roster — nothing here is assignable. KR is ranked on speed and PR "
                + "on agility, the traits the depth chart's own slots rank on; elusiveness is a "
                + "running back's attribute only, so it is shown where the domain has it and ranks "
                + "nobody. Scouted from the receivers, backs and corners — the chart's KR and PR "
                + "slots will take any position, so a fast safety belongs there and appears here "
                + "only once he is listed. A kickoff is still rolled without reading a returner, so "
                + "these men change no result yet.",
            members: kickReturners.map { player in
                SpecialTeamsUnit.Member(
                    player: player,
                    role: DepthChartSlot.KR.rawValue,
                    traitLabel: DepthChartSlot.RankingTrait.speed.shortLabel,
                    traitValue: player.physical.speed,
                    secondLabel: elusiveness(of: player) == nil ? nil : "ELU",
                    secondValue: elusiveness(of: player),
                    isListed: player.id == krListed
                )
            } + puntReturners.map { player in
                SpecialTeamsUnit.Member(
                    player: player,
                    role: DepthChartSlot.PR.rawValue,
                    traitLabel: DepthChartSlot.RankingTrait.agility.shortLabel,
                    traitValue: player.physical.agility,
                    secondLabel: elusiveness(of: player) == nil ? nil : "ELU",
                    secondValue: elusiveness(of: player),
                    isListed: player.id == prListed
                )
            }
        )

        // Coverage — the gunners, i.e. the fastest men who are not first choice
        // anywhere else, which is how a real coverage unit is staffed.
        let reserves = nonStarters(in: active)
        let coverage = Array(ranked(reserves, by: coverageScore).prefix(coverageSize))
        let coverageUnit = SpecialTeamsUnit(
            title: "Coverage Unit",
            facts: ["fastest reserves", "\(reserves.count) available"],
            note: "The fastest men not first choice in their own room. Speed is measured for all of "
                + "them; tackling only where the domain models it, so a TKL cell appears on the "
                + "linebackers and nowhere else. No coverage unit is fielded by the simulator.",
            members: coverage.map { player in
                SpecialTeamsUnit.Member(
                    player: player,
                    role: "GUN",
                    traitLabel: DepthChartSlot.RankingTrait.speed.shortLabel,
                    traitValue: player.physical.speed,
                    // TKL, not TAK. This is `LBAttributes.tackling`, and PlayerRowView,
                    // ScoutingEngine and ProspectFog all caption that exact attribute TKL —
                    // the same linebacker must not read TAK here and TKL on his player card.
                    // ProspectDetailView already carries a comment about this exact three
                    // letters never matching what the engine writes.
                    secondLabel: tackling(of: player) == nil ? nil : "TKL",
                    secondValue: tackling(of: player),
                    isListed: false
                )
            }
        )

        // The wall in front of the snap.
        let blockers = active.filter { blockingPool.contains($0.position) }
        let wall = Array(
            ranked(blockers, by: { blocking(of: $0)?.value ?? 0 }).prefix(blockingSize)
        )
        let blockingUnit = SpecialTeamsUnit(
            title: "Blocking Wall",
            facts: ["from the line and the tight ends", "\(blockers.count) candidates"],
            note: "Punt and field-goal protection, ranked on the blocking attributes each room "
                + "already stores. PRO is a lineman's pass block and anchor averaged — not the PBK "
                + "on his player card, which is pass block alone; a tight end shows his own BLK. "
                + "The simulator prices a punt as a net draw centred on the punter's leg and a "
                + "field goal as a flat block chance, so this wall is a reading of the roster and "
                + "not an input.",
            members: wall.compactMap { player in
                guard let read = blocking(of: player) else { return nil }
                return SpecialTeamsUnit.Member(
                    player: player,
                    role: "WALL",
                    traitLabel: read.label,
                    traitValue: read.value,
                    secondLabel: "STR",
                    secondValue: player.physical.strength,
                    isListed: false
                )
            }
        )

        return [returnUnit, coverageUnit, blockingUnit]
    }

    // MARK: Unit Rating (#3209)

    /// The special-teams unit as one 0-100 number, and the terms it is cut from.
    struct Rating {
        struct Term: Identifiable {
            let label: String
            /// Who, in one line — the term is only as trustworthy as the man.
            let detail: String
            /// `nil` when the club has nobody for the job. A hole is not a zero:
            /// averaging a 0 would price an empty slot as the worst player alive
            /// rather than as absent, so a missing term leaves the average.
            let value: Int?

            var id: String { label }
        }

        let terms: [Term]

        /// An EVEN average of the terms that have a man. There is no weighting
        /// because there is nothing to weight it with — the simulator prices a
        /// kick and a punt and prices no return or coverage snap at all, so any
        /// ratio between the five would be a number this screen invented.
        var rating: Int? {
            let values = terms.compactMap(\.value)
            guard !values.isEmpty else { return nil }
            return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        }
    }

    /// K + P + the chart's KR and PR, each on the trait its own job is picked
    /// on, plus a coverage term over the fastest reserves (#3209).
    ///
    /// The kicker and the punter are read on their kicking attributes rather
    /// than on overall, because overall folds in the physical and mental blocks
    /// that no kicking play consults. The two are NOT read the same way: the
    /// kicker's leg sets `PlaySimulator.fieldGoalRangeYards` and his accuracy
    /// sets the field-goal and extra-point make chance, so his term is the mean
    /// of both; the punt draw reads `kickPower` and nothing else, so the
    /// punter's term is his leg alone and the row says so.
    ///
    /// The returner terms prefer the chart's own holder and fall back to the man
    /// `DepthChart.reconcile` would install if the slot were left empty (the
    /// roster leader on that trait), so the number does not change the moment a
    /// coach opens the depth chart and saves it unchanged.
    static func rating(roster: [Player], chart: DepthChart?) -> Rating {
        let active = roster.filter { !$0.isRetired }

        func specialist(_ position: Position, label: String) -> Rating.Term {
            guard let man = best(position, in: active),
                  case .kicking(let attrs) = man.positionAttributes else {
                return Rating.Term(label: label, detail: "nobody on the roster", value: nil)
            }
            // The punter is priced on his leg alone: `kickAccuracy` is read at
            // PlaySimulator's field goal and extra point and nowhere else, so
            // averaging it into a punter would be half a number the simulator
            // never asks him for.
            if position == .P {
                return Rating.Term(
                    label: label,
                    detail: "\(man.fullName) \u{00B7} PWR \(attrs.kickPower), leg only",
                    value: attrs.kickPower
                )
            }
            return Rating.Term(
                label: label,
                detail: "\(man.fullName) \u{00B7} PWR \(attrs.kickPower) / ACC \(attrs.kickAccuracy)",
                value: Int(attrs.overall.rounded())
            )
        }

        func returner(_ slot: DepthChartSlot, label: String) -> Rating.Term {
            guard let trait = slot.rankingTrait else {
                return Rating.Term(label: label, detail: "no ranking trait", value: nil)
            }
            let listedID: UUID? = chart?.starter(for: slot) ?? nil
            let listedMan = listedID.flatMap { id in active.first { $0.id == id } }
            let man = listedMan ?? ranked(active, by: { trait.value(of: $0) }).first
            guard let man else {
                return Rating.Term(label: label, detail: "nobody on the roster", value: nil)
            }
            let source = listedMan == nil ? "unlisted" : "listed"
            return Rating.Term(
                label: label,
                detail: "\(man.fullName) \u{00B7} \(source)",
                value: trait.value(of: man)
            )
        }

        let reserves = ranked(nonStarters(in: active), by: coverageScore).prefix(coverageSize)
        let coverage: Rating.Term
        if reserves.isEmpty {
            coverage = Rating.Term(label: "Coverage", detail: "no reserves", value: nil)
        } else {
            let mean = reserves.map(coverageScore).reduce(0, +) / reserves.count
            coverage = Rating.Term(
                label: "Coverage",
                detail: "fastest \(reserves.count) reserves",
                value: mean
            )
        }

        return Rating(terms: [
            specialist(.K, label: "Kicker"),
            specialist(.P, label: "Punter"),
            returner(.KR, label: "Kick return"),
            returner(.PR, label: "Punt return"),
            coverage,
        ])
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
    /// which is not yet plumbed into this row. Until that data exists the row
    /// draws no chip at all — neither a number invented from a hash nor the
    /// neutral dash it used to print, which sat in a tinted capsule between the
    /// live cap and expiring chips and so read as a measured "flat" verdict.
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

    /// **Title, facts, verdict** — in that order, at three different weights.
    ///
    /// The header used to be one `HStack` of ten children at one weight: the
    /// group name, a "Biggest Need" capsule, the two graded readouts, two grey
    /// rounded boxes (cap, starter ratio), a warn capsule (expiring), a bare
    /// glyph-plus-number with no container at all (injuries), the staff verdict
    /// and the review control. Six of those ten were *facts* dressed as chips,
    /// which is why nothing on the line read as more important than anything
    /// else — a chip is a container, and putting every fact in one says every
    /// fact is a state.
    ///
    /// Three tiers now:
    ///
    ///   * **Title + facts** — `DSGroupRollup`, the shared group-header
    ///     grammar (§2.2: "a position group on the roster and a tier on the
    ///     board read as the same object at the same weight"). The cap and the
    ///     starter ratio are prose in that line, because that is what they are.
    ///   * **The verdict** — the starter and depth grades, still the largest
    ///     type on the row. On a roster you return to a hundred times, the
    ///     letter is the thing you scan for.
    ///   * **The states** — capsules, one shape, only for things that are
    ///     actually a state: biggest need, expiring, injured, the staff read,
    ///     your own read.
    var body: some View {
        let g = grades
        HStack(spacing: DSSpacing.xs) {
            // Title + the neutral facts. `DSGroupRollup` ends in its own
            // `Spacer`, so everything after it is pushed to the trailing edge —
            // which is the split this header wanted all along: who and what,
            // left; how good and what is wrong, right.
            DSGroupRollup(
                title: group.name,
                facts: rollupFacts,
                tint: .textPrimary
            )

            gradeReadout(g)

            // Development trend — drawn only once there is a real delta to
            // draw. Styled as a state capsule like its neighbours, the
            // placeholder dash read as a measured "flat" verdict on every group
            // in every season (see `developmentTrend`).
            let trend = developmentTrend
            if trend.delta != 0 {
                stateChip(trend.label, tint: trend.color)
                    .accessibilityLabel("Development trend \(trend.label)")
            }

            if isWeakest {
                stateChip("Biggest Need", tint: .danger)
            }

            if expiringCount > 0 {
                stateChip("\(expiringCount) expiring", tint: .warning)
            }

            if injuredCount > 0 {
                stateChip("\(injuredCount) injured", glyph: "cross.circle.fill", tint: .danger)
            }

            stateChip(staffLabel, tint: staffColor)

            // Review control — shows your own assessment, or invites one.
            if let own = ownAssessment, own != "none" {
                stateChip(own, tint: Self.ownAssessmentColor(own))
            } else {
                stateChip("Review", glyph: "square.and.pencil", tint: .accentBlue)
            }
        }
        .textCase(nil)
    }

    /// The neutral facts, already formatted — `DSGroupRollup` does no
    /// arithmetic. The starter ratio names both of its numbers because a bare
    /// "3 / 7" was the one reading on this header that named neither.
    private var rollupFacts: [String] {
        [
            "\(starterCount) of \(players.count) starting",
            "\(formattedCap) cap"
        ]
    }

    /// The group's two grades, spelled out and with the average each was cut
    /// from beside it: `S:` and `D:` were the largest type on the row and the
    /// two labels on the screen that nothing expanded, and the letter alone
    /// could not be reconciled with the OVRs printed in the rows below it.
    private func gradeReadout(
        _ g: (starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int)
    ) -> some View {
        HStack(spacing: 3) {  // ds-lint:allow(spacing) label-to-value gaps inside one readout
            Text("Starters")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textTertiary)
            Text(g.starterGrade)
                .font(DSType.display(DSType.Size.title3, .black))
                .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(g.starterGrade))
            Text("\(g.starterOVR) avg")
                .font(DSType.display(DSType.Size.caption, .semibold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
            Text("\u{00B7}")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textTertiary)
            Text("Depth")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textTertiary)
            Text(g.depthGrade)
                .font(DSType.display(DSType.Size.title3, .black))
                .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(g.depthGrade))
            if g.depthGrade != PositionGradeCalculator.noDepthGrade {
                Text("\(g.depthOVR) avg")
                    .font(DSType.display(DSType.Size.caption, .semibold).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Starters grade \(g.starterGrade), \(g.starterOVR) average. "
            + "Depth grade \(g.depthGrade)."
        )
    }

    /// One state, one shape.
    ///
    /// Every tinted thing on this header goes through here, so "expiring",
    /// "injured", the staff read and your own read cannot end up as four
    /// different objects again. 11 pt display rather than the 10 pt text the
    /// chips shipped at: 11 is the condensed voice's floor (P7's legibility
    /// corollary) and these are the words that carry the row's verdict.
    private func stateChip(_ text: String, glyph: String? = nil, tint: Color) -> some View {
        HStack(spacing: 3) {  // ds-lint:allow(spacing) glyph-to-text gap inside one chip
            if let glyph {
                Image(systemName: glyph)
                    .font(DSType.text(DSType.Size.caption, .semibold))
            }
            Text(text)
                .font(DSType.display(DSType.Size.caption, .heavy))
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, DSSpacing.xxs + 2)
        .padding(.vertical, 2)
        .background(tint.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
    }

    /// Mirrors `RosterView.assessmentColor` — same words, same ladder. Gold is
    /// off this screen entirely (P5): the roster has no commit to spend it on.
    static func ownAssessmentColor(_ assessment: String) -> Color {
        switch assessment {
        case "Solid":           return .success
        case "Starter needed":  return .danger
        case "Depth needed":    return .warning
        case "Upgrade needed":  return .warning
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
