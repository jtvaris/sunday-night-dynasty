import SwiftUI
import SwiftData

struct CareerDashboardView: View {

    @Bindable var career: Career
    @Binding var tasks: [GameTask]
    var onTaskSelected: (TaskDestination) -> Void
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @State private var team: Team?
    @State private var rosterCount: Int = 0
    @State private var coachCount: Int = 0
    @State private var headCoach: Coach?
    @State private var divisionTeams: [Team] = []
    @State private var upcomingGames: [Game] = []
    @State private var lastGame: Game?
    @State private var allTeamsByID: [UUID: Team] = [:]

    /// Game summary sheet after advancing a week.
    @State private var showGameSummary = false
    @State private var lastGameResult: GameSimulator.GameResult?
    @State private var lastHomeTeam: Team?
    @State private var lastAwayTeam: Team?

    // MARK: - Derived

    private var requiredTasks: [GameTask] {
        tasks.filter { $0.isRequired }
    }

    private var optionalTasks: [GameTask] {
        tasks.filter { !$0.isRequired }
    }

    private var incompleteRequiredCount: Int {
        TaskGenerator.incompleteRequiredCount(in: tasks)
    }

    private var canAdvance: Bool {
        TaskGenerator.allRequiredComplete(in: tasks)
    }

    // MARK: - Grid

    private let columns = [
        GridItem(.adaptive(minimum: 300), spacing: 16)
    ]

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {

                    // Row 1 -- Key Info
                    LazyVGrid(columns: columns, spacing: 16) {
                        teamTile
                        seasonTile
                    }

                    // Row 2 -- Action Tiles
                    LazyVGrid(columns: columns, spacing: 16) {
                        rosterTile
                        scheduleTile
                        standingsTile
                        newsTile
                    }

                    // Row 3 -- Management Tiles
                    LazyVGrid(columns: columns, spacing: 16) {
                        staffTile
                        scoutingTile
                        capTile
                        lockerRoomTile
                    }

                    // Row 4 -- Seasonal / Contextual Tiles
                    LazyVGrid(columns: columns, spacing: 16) {
                        if career.currentPhase == .draft || career.currentPhase == .combine {
                            draftTile
                        }
                        if career.currentPhase == .freeAgency {
                            freeAgencyTile
                        }
                        if career.currentPhase == .regularSeason || career.currentPhase == .tradeDeadline {
                            tradeTile
                        }
                    }

                    // Phase Tasks Checklist
                    if !tasks.isEmpty {
                        phaseTasksSection
                    }

                    // Advance Week
                    advanceWeekButton
                        .padding(.top, 8)
                }
                .padding(20)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadAllData() }
        .sheet(isPresented: $showGameSummary) {
            if let result = lastGameResult, let home = lastHomeTeam, let away = lastAwayTeam {
                NavigationStack {
                    GameSummaryView(
                        boxScore: result.boxScore,
                        homeTeam: home,
                        awayTeam: away,
                        playerStats: result.playerStats
                    )
                }
            }
        }
    }

    // MARK: - Phase Tasks Section

    private var phaseTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Gold header
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text("PHASE TASKS \u{2014} \(phaseDisplayName(career.currentPhase))")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if incompleteRequiredCount > 0 {
                    Text("\(incompleteRequiredCount)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.danger))
                }
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // Required tasks first
            if !requiredTasks.isEmpty {
                ForEach(requiredTasks) { task in
                    taskRow(task, isRequired: true)
                }
            }

            // Optional tasks below, dimmer
            if !optionalTasks.isEmpty {
                if !requiredTasks.isEmpty {
                    Divider().overlay(Color.surfaceBorder.opacity(0.3))
                }
                ForEach(optionalTasks) { task in
                    taskRow(task, isRequired: false)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func taskRow(_ task: GameTask, isRequired: Bool) -> some View {
        Button {
            onTaskSelected(task.destination)
        } label: {
            HStack(spacing: 10) {
                // Status indicator
                if task.status == .done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.success)
                } else if isRequired {
                    Circle()
                        .fill(Color.danger)
                        .frame(width: 10, height: 10)
                        .padding(.horizontal, 3)
                } else {
                    Circle()
                        .strokeBorder(Color.textTertiary, lineWidth: 1.5)
                        .frame(width: 10, height: 10)
                        .padding(.horizontal, 3)
                }

                // Label
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        if isRequired && task.status != .done {
                            Text("Required")
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.danger))
                        }
                        Text(task.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(task.status == .done ? Color.textTertiary : Color.textPrimary)
                            .strikethrough(task.status == .done, color: Color.textTertiary)
                    }
                }

                Spacer()

                if task.status != .done {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.vertical, 6)
            .opacity(task.status == .done ? 0.6 : (isRequired ? 1.0 : 0.75))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 1: Team Tile

    private var teamTile: some View {
        NavigationLink {
            OwnerMeetingView(career: career)
        } label: {
            DashboardTile(icon: "shield.fill", title: "Team") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(team?.fullName ?? "No Team")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Record")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text(team?.record ?? "0-0")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Division")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text(divisionRank)
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }
                    }

                    if let owner = team?.owner {
                        ownerSatisfactionBar(owner.satisfaction)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 1: Season Tile

    private var isOffseasonPhase: Bool {
        switch career.currentPhase {
        case .regularSeason, .playoffs, .tradeDeadline:
            return false
        default:
            return true
        }
    }

    private var seasonTile: some View {
        DashboardTile(icon: "clock.fill", title: "Season") {
            VStack(alignment: .leading, spacing: 8) {
                if isOffseasonPhase {
                    // Offseason: show phase name prominently instead of week
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Offseason")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(phaseDisplayName(career.currentPhase))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Color.accentGold)
                        Text("Season \(career.currentSeason)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Week")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text("\(career.currentWeek) of 18")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Phase")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text(phaseDisplayName(career.currentPhase))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentGold)
                        }
                    }
                }

                if let nextGame = upcomingGames.first {
                    Divider().overlay(Color.surfaceBorder)
                    let isHome = nextGame.homeTeamID == career.teamID
                    let opponentID = isHome ? nextGame.awayTeamID : nextGame.homeTeamID
                    let opponentName = allTeamsByID[opponentID]?.fullName ?? "TBD"
                    let prefix = isHome ? "vs" : "@"

                    HStack(spacing: 4) {
                        Text("Next:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                        Text("\(prefix) \(opponentName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    // MARK: - Row 2: Roster Tile

    private var rosterTile: some View {
        NavigationLink {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                Text("Roster - Coming Soon")
                    .font(.title2)
                    .foregroundStyle(Color.textSecondary)
            }
            .navigationTitle("Roster")
            .toolbarColorScheme(.dark, for: .navigationBar)
        } label: {
            DashboardTile(icon: "person.3.fill", title: "Roster", highlighted: currentPhaseHighlightedTiles.contains("Roster")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Players")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(rosterCount)")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }
                    HStack {
                        Text("Cap Space")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(formatCap(team?.availableCap ?? 0))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Color.success)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 2: Schedule Tile

    private var scheduleTile: some View {
        NavigationLink {
            ScheduleView(career: career)
        } label: {
            DashboardTile(icon: "calendar", title: "Schedule", highlighted: currentPhaseHighlightedTiles.contains("Schedule")) {
                VStack(alignment: .leading, spacing: 6) {
                    if let last = lastGame, last.isPlayed {
                        let isHome = last.homeTeamID == career.teamID
                        let myScore = isHome ? (last.homeScore ?? 0) : (last.awayScore ?? 0)
                        let theirScore = isHome ? (last.awayScore ?? 0) : (last.homeScore ?? 0)
                        let won = myScore > theirScore
                        let opponentID = isHome ? last.awayTeamID : last.homeTeamID
                        let oppAbbr = allTeamsByID[opponentID]?.abbreviation ?? "???"

                        HStack {
                            Text(won ? "W" : "L")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(won ? Color.success : Color.danger)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill((won ? Color.success : Color.danger).opacity(0.15))
                                )
                            Text("\(myScore)-\(theirScore)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                            Text("vs \(oppAbbr)")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        Text("No results yet")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }

                    if let next = upcomingGames.first {
                        Divider().overlay(Color.surfaceBorder)
                        let isHome = next.homeTeamID == career.teamID
                        let opponentID = isHome ? next.awayTeamID : next.homeTeamID
                        let oppAbbr = allTeamsByID[opponentID]?.abbreviation ?? "???"
                        HStack(spacing: 4) {
                            Text("Next:")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Text("\(isHome ? "vs" : "@") \(oppAbbr) (Wk \(next.week))")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 2: Standings Tile

    private var standingsTile: some View {
        NavigationLink {
            StandingsView(career: career)
        } label: {
            DashboardTile(icon: "list.number", title: "Standings") {
                VStack(alignment: .leading, spacing: 4) {
                    if divisionTeams.isEmpty {
                        Text("Loading...")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        ForEach(divisionTeams.sorted(by: { $0.wins > $1.wins }), id: \.id) { t in
                            HStack {
                                Text(t.abbreviation)
                                    .font(.caption.weight(t.id == team?.id ? .heavy : .medium))
                                    .foregroundStyle(t.id == team?.id ? Color.accentGold : Color.textSecondary)
                                    .frame(width: 36, alignment: .leading)
                                Spacer()
                                Text(t.record)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(t.id == team?.id ? Color.textPrimary : Color.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 2: News Tile

    private var newsTile: some View {
        NavigationLink {
            NewsView(career: career)
        } label: {
            DashboardTile(icon: "newspaper.fill", title: "News") {
                VStack(alignment: .leading, spacing: 6) {
                    let recentNews = Array(WeekAdvancer.lastNewsItems.prefix(2))
                    if recentNews.isEmpty {
                        Text("No recent headlines")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        ForEach(recentNews) { item in
                            Text(item.headline)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if item.id != recentNews.last?.id {
                                Divider().overlay(Color.surfaceBorder.opacity(0.5))
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 3: Staff Tile

    private var staffTile: some View {
        NavigationLink {
            CoachingStaffView(career: career)
        } label: {
            DashboardTile(icon: "person.2.fill", title: "Staff", highlighted: currentPhaseHighlightedTiles.contains("Staff")) {
                VStack(alignment: .leading, spacing: 6) {
                    if let hc = headCoach {
                        HStack {
                            Text("HC")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.accentGold)
                            Text(hc.fullName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                        }
                        if let scheme = hc.offensiveScheme {
                            Text(scheme.rawValue)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                        HStack {
                            Text("Rating")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text("\(hc.playCalling)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(Color.forRating(hc.playCalling))
                        }
                    } else {
                        Text("No head coach")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 3: Scouting Tile

    private var scoutingTile: some View {
        NavigationLink {
            ScoutingHubView(career: career)
        } label: {
            DashboardTile(icon: "magnifyingglass", title: "Scouting", highlighted: currentPhaseHighlightedTiles.contains("Scouting")) {
                VStack(alignment: .leading, spacing: 6) {
                    let topProspect = WeekAdvancer.currentDraftClass.first
                    if let prospect = topProspect {
                        Text("\(prospect.firstName) \(prospect.lastName)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        HStack {
                            Text(prospect.position.rawValue)
                                .font(.caption)
                                .foregroundStyle(Color.accentGold)
                            Text(prospect.college)
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        Text("No prospects scouted")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Text("\(WeekAdvancer.currentDraftClass.count) prospects")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 3: Cap Tile

    private var capTile: some View {
        NavigationLink {
            CapOverviewView(career: career)
        } label: {
            DashboardTile(icon: "dollarsign.circle.fill", title: "Salary Cap", highlighted: currentPhaseHighlightedTiles.contains("Salary Cap")) {
                VStack(alignment: .leading, spacing: 8) {
                    if let t = team {
                        let usedFraction = t.salaryCap > 0
                            ? Double(t.currentCapUsage) / Double(t.salaryCap)
                            : 0

                        HStack {
                            Text("Used")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(formatCap(t.currentCapUsage))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(usedFraction > 0.9 ? Color.danger : Color.accentGold)
                                    .frame(width: geo.size.width * min(usedFraction, 1.0), height: 8)
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text("Available")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(formatCap(t.availableCap))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(t.availableCap > 0 ? Color.success : Color.danger)
                        }
                    } else {
                        Text("No cap data")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 3: Locker Room Tile

    private var lockerRoomTile: some View {
        NavigationLink {
            LockerRoomView(career: career)
        } label: {
            DashboardTile(icon: "heart.fill", title: "Locker Room") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Chemistry")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("Good")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.success)
                    }

                    // Morale bar placeholder (0.7 = good)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.backgroundTertiary)
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.success)
                                .frame(width: geo.size.width * 0.7, height: 8)
                        }
                    }
                    .frame(height: 8)

                    Text("Morale: 70%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 4: Draft Tile (contextual)

    private var draftTile: some View {
        NavigationLink {
            DraftView(career: career)
        } label: {
            DashboardTile(icon: "list.clipboard.fill", title: "Draft", highlighted: currentPhaseHighlightedTiles.contains("Draft")) {
                VStack(alignment: .leading, spacing: 6) {
                    let picks = WeekAdvancer.currentDraftPicks.filter { $0.currentTeamID == career.teamID }
                    if let firstPick = picks.first {
                        Text("Pick #\(firstPick.pickNumber)")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.accentGold)
                    }
                    if let topProspect = WeekAdvancer.currentDraftClass.first {
                        Text("Top: \(topProspect.firstName) \(topProspect.lastName)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                    Text("\(picks.count) pick(s)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 4: Free Agency Tile (contextual)

    private var freeAgencyTile: some View {
        NavigationLink {
            FreeAgencyView(career: career)
        } label: {
            DashboardTile(icon: "person.badge.plus", title: "Free Agency", highlighted: currentPhaseHighlightedTiles.contains("Free Agency")) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Available Cap")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(formatCap(team?.availableCap ?? 0))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.success)
                    }
                    Text("Browse available free agents")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Row 4: Trade Tile (contextual)

    private var tradeTile: some View {
        NavigationLink {
            TradeView(career: career)
        } label: {
            DashboardTile(icon: "arrow.left.arrow.right", title: "Trade") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Trade window open")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.success)
                    Text("Review potential deals")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Advance Week Button

    /// Returns the label text for the advance button based on the current phase.
    private var advanceButtonLabel: String {
        switch career.currentPhase {
        case .regularSeason:
            return "Advance to Week \(career.currentWeek + 1)"
        case .playoffs:
            switch career.currentWeek {
            case 19: return "Advance to Divisional Round"
            case 20: return "Advance to Conference Championships"
            case 21: return "Advance to Super Bowl"
            default: return "Advance to Next Round"
            }
        case .superBowl:       return "Advance to Pro Bowl"
        case .proBowl:         return "Advance to Coaching Changes"
        case .coachingChanges: return "Advance to NFL Combine"
        case .combine:         return "Advance to Free Agency"
        case .freeAgency:      return "Advance to NFL Draft"
        case .draft:           return "Advance to OTAs"
        case .otas:            return "Advance to Training Camp"
        case .trainingCamp:    return "Advance to Preseason"
        case .preseason:       return "Advance to Roster Cuts"
        case .rosterCuts:      return "Advance to Regular Season"
        case .tradeDeadline:   return "Advance to Week \(career.currentWeek + 1)"
        }
    }

    private var advanceWeekButton: some View {
        VStack(spacing: 8) {
            // Warning text when blocked
            if !canAdvance {
                Label(
                    "Complete \(incompleteRequiredCount) required task\(incompleteRequiredCount == 1 ? "" : "s") to advance",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.danger)
            }

            Button {
                guard canAdvance else { return }
                let teamsByID = fetchTeamsByID()
                WeekAdvancer.advanceWeek(career: career, modelContext: modelContext)
                if let result = WeekAdvancer.lastPlayerGameResult,
                   let home = teamsByID[result.boxScore.home.teamID],
                   let away = teamsByID[result.boxScore.away.teamID] {
                    lastGameResult = result
                    lastHomeTeam = home
                    lastAwayTeam = away
                    showGameSummary = true
                }
                loadAllData()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 16, weight: .bold))
                    Text(advanceButtonLabel)
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(canAdvance ? Color.backgroundPrimary : Color.textTertiary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canAdvance ? Color.accentGold : Color.backgroundTertiary)
                        .shadow(
                            color: canAdvance ? Color.accentGold.opacity(0.4) : Color.clear,
                            radius: 12, x: 0, y: 4
                        )
                )
            }
            .disabled(!canAdvance)
            .animation(.spring(duration: 0.3), value: canAdvance)
            .accessibilityLabel(advanceButtonLabel)
        }
    }

    // MARK: - Owner Satisfaction Bar

    private func ownerSatisfactionBar(_ satisfaction: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "building.2.fill")
                .font(.caption2)
                .foregroundStyle(satisfactionColor(satisfaction))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(satisfactionColor(satisfaction))
                        .frame(width: geo.size.width * (Double(satisfaction) / 100.0), height: 6)
                }
            }
            .frame(height: 6)

            Text("\(satisfaction)%")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(satisfactionColor(satisfaction))
                .frame(width: 32, alignment: .trailing)
        }
    }

    private func satisfactionColor(_ value: Int) -> Color {
        if value > 60  { return Color.success }
        if value >= 35 { return Color.warning }
        return Color.danger
    }

    // MARK: - Division Rank

    private var divisionRank: String {
        guard let myTeam = team else { return "\u{2014}" }
        let sorted = divisionTeams.sorted { $0.wins > $1.wins }
        if let idx = sorted.firstIndex(where: { $0.id == myTeam.id }) {
            let rank = idx + 1
            return "#\(rank)"
        }
        return "\u{2014}"
    }

    // MARK: - Phase Highlight

    /// Which dashboard tile names should be visually emphasized for the current phase.
    private var currentPhaseHighlightedTiles: Set<String> {
        switch career.currentPhase {
        case .coachingChanges:
            return ["Staff"]
        case .combine:
            return ["Scouting", "Draft"]
        case .freeAgency:
            return ["Free Agency", "Salary Cap"]
        case .draft:
            return ["Draft", "Scouting"]
        case .otas, .trainingCamp:
            return ["Roster"]
        case .rosterCuts:
            return ["Roster"]
        case .preseason:
            return ["Schedule", "Roster"]
        default:
            return []
        }
    }

    // MARK: - Helpers

    private func phaseDisplayName(_ phase: SeasonPhase) -> String {
        switch phase {
        case .superBowl:       return "Super Bowl"
        case .proBowl:         return "Pro Bowl"
        case .coachingChanges: return "Coaching"
        case .combine:         return "Combine"
        case .freeAgency:      return "Free Agency"
        case .draft:           return "Draft"
        case .otas:            return "OTAs"
        case .trainingCamp:    return "Camp"
        case .preseason:       return "Preseason"
        case .rosterCuts:      return "Roster Cuts"
        case .regularSeason:   return "Regular Season"
        case .tradeDeadline:   return "Trade Deadline"
        case .playoffs:        return "Playoffs"
        }
    }

    private func formatCap(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if abs(millions) >= 1.0 {
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }

    private func fetchTeamsByID() -> [UUID: Team] {
        let descriptor = FetchDescriptor<Team>()
        let teams = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
    }

    private func loadAllData() {
        guard let teamID = career.teamID else { return }

        // All teams
        let allTeamsDescriptor = FetchDescriptor<Team>()
        let allTeams = (try? modelContext.fetch(allTeamsDescriptor)) ?? []
        allTeamsByID = Dictionary(uniqueKeysWithValues: allTeams.map { ($0.id, $0) })

        // My team
        team = allTeamsByID[teamID]

        // Roster count
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        rosterCount = (try? modelContext.fetchCount(playerDescriptor)) ?? 0

        // Coach count + head coach
        let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
        coachCount = coaches.count
        headCoach = coaches.first(where: { $0.role == .headCoach })

        // Division teams
        if let myTeam = team {
            divisionTeams = allTeams.filter {
                $0.conference == myTeam.conference && $0.division == myTeam.division
            }
        }

        // Games for schedule info
        let seasonYear = career.currentSeason
        let gameDescriptor = FetchDescriptor<Game>(predicate: #Predicate {
            $0.seasonYear == seasonYear
        })
        let allGames = (try? modelContext.fetch(gameDescriptor)) ?? []

        let myGames = allGames.filter {
            $0.homeTeamID == teamID || $0.awayTeamID == teamID
        }

        upcomingGames = myGames
            .filter { !$0.isPlayed && $0.week >= career.currentWeek }
            .sorted { $0.week < $1.week }

        lastGame = myGames
            .filter { $0.isPlayed }
            .sorted { $0.week > $1.week }
            .first
    }
}

// MARK: - Dashboard Tile

/// Reusable tile component for the FM26-inspired grid layout.
private struct DashboardTile<Content: View>: View {

    let icon: String
    let title: String
    var highlighted: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if highlighted {
                    Text("ACTIVE")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentGold))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // Content
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            highlighted ? Color.accentGold.opacity(0.6) : Color.surfaceBorder,
                            lineWidth: highlighted ? 1.5 : 1
                        )
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    @Previewable @State var previewTasks: [GameTask] = TaskGenerator.generateTasks(
        for: .coachingChanges,
        career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
        team: nil,
        hasHeadCoach: false,
        hasOC: false,
        hasDC: true
    )

    NavigationStack {
        CareerDashboardView(
            career: Career(
                playerName: "John Doe",
                role: .gm,
                capMode: .simple
            ),
            tasks: $previewTasks,
            onTaskSelected: { _ in }
        )
    }
    .modelContainer(for: Career.self, inMemory: true)
}
