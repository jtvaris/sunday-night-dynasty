import SwiftUI
import SwiftData

struct CareerDashboardView: View {

    @Bindable var career: Career
    @Binding var tasks: [GameTask]
    @Binding var inboxMessages: [InboxMessage]
    var onTaskSelected: (TaskDestination) -> Void
    var onAdvance: (() -> Void)? = nil
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

    /// Inbox filter for the messages panel
    @State private var inboxFilter: DashboardInboxFilter = .all

    // MARK: - Derived

    private var canAdvance: Bool {
        TaskGenerator.allRequiredComplete(in: tasks)
    }

    private var isLandscape: Bool {
        horizontalSizeClass == .regular
    }

    // MARK: - Advance Logic

    private func performAdvance() {
        guard canAdvance else { return }
        if let onAdvance {
            onAdvance()
        } else {
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
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Timeline strip -- always at top
                timelineStrip
                    .padding(.top, 4)

                if isLandscape {
                    landscapeLayout
                } else {
                    portraitLayout
                }
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

    // MARK: - Landscape Layout (3-column + bottom messages)

    private var landscapeLayout: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                // Left column -- Timeline+Tasks Panel (30%)
                TimelineTasksPanel(
                    career: career,
                    tasks: $tasks,
                    onTaskSelected: onTaskSelected,
                    onAdvance: { performAdvance() },
                    canAdvance: canAdvance
                )
                .frame(maxWidth: .infinity)
                .layoutPriority(0.3)

                Divider().overlay(Color.surfaceBorder)

                // Center column -- Dashboard tiles + Messages (40%)
                ScrollView {
                    VStack(spacing: 12) {
                        centerTilesGrid
                        messagesPanel
                            .frame(height: 280)
                            .background(Color.backgroundSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                            )
                    }
                    .padding(12)
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(0.4)

                Divider().overlay(Color.surfaceBorder)

                // Right column -- Schedule + Standings (30%)
                ScrollView {
                    rightPanel
                        .padding(12)
                }
                .frame(maxWidth: .infinity)
                .layoutPriority(0.3)
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Portrait Layout (stacked)

    private var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Timeline+Tasks panel (replaces old phaseTasksSection + advance button)
                TimelineTasksPanel(
                    career: career,
                    tasks: $tasks,
                    onTaskSelected: onTaskSelected,
                    onAdvance: { performAdvance() },
                    canAdvance: canAdvance
                )
                .frame(minHeight: 300, maxHeight: 500)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
                .padding(.horizontal, 16)

                // Messages + Schedule side by side
                HStack(alignment: .top, spacing: 0) {
                    messagesPanel
                        .frame(maxWidth: .infinity)

                    Divider().overlay(Color.surfaceBorder)

                    ScrollView {
                        VStack(spacing: 12) {
                            // Schedule + Standings in portrait
                            rightPanel
                        }
                        .padding(12)
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 320)
                .background(Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
                .padding(.horizontal, 16)

                // Tiles grid
                centerTilesGrid
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Bottom Bar (legacy, no longer used in main layout)
    // The TimelineTasksPanel now serves as the combined tasks + advance UI.

    // MARK: - 1. Horizontal Timeline Strip

    private var timelineNodes: [(label: String, month: String, phase: SeasonPhase?, weekNum: Int?)] {
        var nodes: [(String, String, SeasonPhase?, Int?)] = [
            ("Coaching", "Feb", .coachingChanges, nil),
            ("Combine", "Mar", .combine, nil),
            ("Free Agency", "Mar", .freeAgency, nil),
            ("Draft", "Apr", .draft, nil),
            ("OTAs", "May", .otas, nil),
            ("Camp", "Jun", .trainingCamp, nil),
            ("Preseason", "Aug", .preseason, nil),
            ("Cuts", "Aug", .rosterCuts, nil),
        ]
        // Regular season weeks
        let weekMonths = ["Sep","Sep","Sep","Sep","Oct","Oct","Oct","Oct","Nov","Nov","Nov","Nov","Dec","Dec","Dec","Dec","Jan","Jan"]
        for w in 1...18 {
            let month = w <= weekMonths.count ? weekMonths[w - 1] : "Jan"
            nodes.append(("Wk \(w)", month, .regularSeason, w))
        }
        nodes.append(("Playoffs", "Jan", .playoffs, nil))
        nodes.append(("Super Bowl", "Feb", .superBowl, nil))
        return nodes
    }

    /// Index of the currently active node in the timeline.
    private var currentNodeIndex: Int {
        let phase = career.currentPhase
        let week = career.currentWeek

        for (i, node) in timelineNodes.enumerated() {
            if let nodePhase = node.phase {
                if nodePhase == phase {
                    if phase == .regularSeason || phase == .tradeDeadline {
                        if let wk = node.weekNum, wk == week {
                            return i
                        }
                    } else {
                        return i
                    }
                }
            }
        }
        return 0
    }

    private var timelineStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(timelineNodes.enumerated()), id: \.offset) { index, node in
                        let isCurrent = index == currentNodeIndex
                        let isPast = index < currentNodeIndex
                        let isFuture = index > currentNodeIndex

                        VStack(spacing: 2) {
                            // Node indicator
                            ZStack {
                                if isCurrent {
                                    Circle()
                                        .fill(Color.accentGold)
                                        .frame(width: 22, height: 22)
                                    Text("NOW")
                                        .font(.system(size: 6, weight: .black))
                                        .foregroundStyle(Color.backgroundPrimary)
                                } else if isPast {
                                    Circle()
                                        .fill(Color.backgroundTertiary)
                                        .frame(width: 16, height: 16)
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Color.textTertiary)
                                } else {
                                    Circle()
                                        .strokeBorder(Color.surfaceBorder, lineWidth: 1.5)
                                        .frame(width: 16, height: 16)
                                }
                            }
                            .frame(height: 24)

                            Text(node.label)
                                .font(.system(size: 9, weight: isCurrent ? .heavy : .medium))
                                .foregroundStyle(isCurrent ? Color.accentGold : (isPast ? Color.textTertiary : Color.textSecondary))
                                .lineLimit(1)

                            Text(node.month)
                                .font(.system(size: 8, weight: .regular))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(width: 52)
                        .opacity(isFuture ? 0.6 : 1.0)
                        .id(index)

                        // Connecting line
                        if index < timelineNodes.count - 1 {
                            Rectangle()
                                .fill(isPast ? Color.textTertiary.opacity(0.4) : Color.surfaceBorder)
                                .frame(width: 12, height: 2)
                                .offset(y: -12)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            .frame(height: 60)
            .background(Color.backgroundSecondary)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(currentNodeIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - 2. Messages Panel

    private var messagesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text("Messages")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                    .textCase(.uppercase)
                    .tracking(0.5)

                let unread = inboxMessages.filter { !$0.isRead }.count
                if unread > 0 {
                    Text("\(unread)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.danger))
                }

                Spacer()

                Button {
                    onTaskSelected(.inbox)
                } label: {
                    Text("View All")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentBlue)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Filter tabs
            HStack(spacing: 0) {
                ForEach(DashboardInboxFilter.allCases, id: \.self) { filter in
                    Button {
                        inboxFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 11, weight: inboxFilter == filter ? .bold : .medium))
                            .foregroundStyle(inboxFilter == filter ? Color.accentGold : Color.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                inboxFilter == filter
                                    ? Color.accentGold.opacity(0.12)
                                    : Color.clear
                            )
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // Message list
            ScrollView {
                LazyVStack(spacing: 0) {
                    let filtered = filteredInboxMessages
                    if filtered.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "tray")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.textTertiary)
                            Text("No messages")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                    } else {
                        ForEach(filtered.reversed()) { message in
                            messageRow(message)
                            Divider().overlay(Color.surfaceBorder.opacity(0.3))
                        }
                    }
                }
            }
        }
    }

    private var filteredInboxMessages: [InboxMessage] {
        switch inboxFilter {
        case .all:
            return inboxMessages
        case .new:
            return inboxMessages.filter { !$0.isRead }
        case .tasks:
            return inboxMessages.filter { $0.actionRequired }
        }
    }

    private func messageRow(_ message: InboxMessage) -> some View {
        Button {
            onTaskSelected(.inbox)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                // Unread dot
                Circle()
                    .fill(message.isRead ? Color.clear : Color.accentGold)
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)

                // Sender avatar
                Image(systemName: message.sender.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 28, height: 28)
                    .background(Color.backgroundTertiary)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(message.sender.displayName)
                            .font(.system(size: 12, weight: message.isRead ? .medium : .bold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(message.date)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Text(message.subject)
                        .font(.system(size: 11, weight: message.isRead ? .regular : .semibold))
                        .foregroundStyle(message.isRead ? Color.textSecondary : Color.textPrimary)
                        .lineLimit(1)

                    if message.actionRequired {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.danger)
                            Text("Action Required")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.danger)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. Center Tiles Grid

    private let tileColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var centerTilesGrid: some View {
        LazyVGrid(columns: tileColumns, spacing: 12) {
            teamTile
            rosterTile
            staffTile
            scoutingTile
            capTile
            lockerRoomTile

            // Contextual tiles
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
    }

    // MARK: - 4. Right Panel (Schedule + Standings)

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Upcoming fixtures
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                    Text("UPCOMING")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                        .tracking(0.5)
                }

                if upcomingGames.isEmpty {
                    Text(isOffseasonPhase ? "Season starts after Roster Cuts" : "No upcoming games")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(Array(upcomingGames.prefix(5)), id: \.id) { game in
                        fixtureRow(game)
                    }
                }
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // Division standings mini-table
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "list.number")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                    Text("DIVISION")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                        .tracking(0.5)
                }

                if divisionTeams.isEmpty {
                    Text("Loading...")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                } else {
                    // Header row
                    HStack {
                        Text("Team")
                            .frame(width: 40, alignment: .leading)
                        Spacer()
                        Text("W")
                            .frame(width: 24)
                        Text("L")
                            .frame(width: 24)
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                    .textCase(.uppercase)

                    ForEach(divisionTeams.sorted(by: { $0.wins > $1.wins }), id: \.id) { t in
                        let isMyTeam = t.id == team?.id
                        HStack {
                            Text(t.abbreviation)
                                .font(.system(size: 11, weight: isMyTeam ? .heavy : .medium))
                                .foregroundStyle(isMyTeam ? Color.accentGold : Color.textSecondary)
                                .frame(width: 40, alignment: .leading)
                            Spacer()
                            Text("\(t.wins)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(isMyTeam ? Color.textPrimary : Color.textSecondary)
                                .frame(width: 24)
                            Text("\(t.losses)")
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(isMyTeam ? Color.textPrimary : Color.textSecondary)
                                .frame(width: 24)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.accentGold.opacity(isMyTeam ? 0.08 : 0))
                        )
                    }
                }
            }
        }
    }

    private func fixtureRow(_ game: Game) -> some View {
        let isHome = game.homeTeamID == career.teamID
        let opponentID = isHome ? game.awayTeamID : game.homeTeamID
        let oppAbbr = allTeamsByID[opponentID]?.abbreviation ?? "???"
        let prefix = isHome ? "vs" : "@"

        return HStack(spacing: 8) {
            Text("Wk \(game.week)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 34, alignment: .leading)

            Text("\(prefix) \(oppAbbr)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer()

            if isHome {
                Text("HOME")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.success)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.success.opacity(0.12).cornerRadius(3))
            } else {
                Text("AWAY")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.backgroundTertiary.cornerRadius(3))
            }
        }
        .padding(.vertical, 4)
    }

    // NOTE: phaseTasksSection, taskRow, taskChip removed -- replaced by TimelineTasksPanel.

    // MARK: - Team Tile

    private var teamTile: some View {
        NavigationLink {
            OwnerMeetingView(career: career)
        } label: {
            DashboardTile(icon: "shield.fill", title: "Team") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(team?.fullName ?? "No Team")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Record")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            Text(team?.record ?? "0-0")
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Division")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            Text(divisionRank)
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
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

    // MARK: - Roster Tile

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
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Players")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(rosterCount)")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }
                    HStack {
                        Text("Cap Space")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(formatCap(team?.availableCap ?? 0))
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.success)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Staff Tile

    private var staffTile: some View {
        NavigationLink {
            CoachingStaffView(career: career)
        } label: {
            DashboardTile(icon: "person.2.fill", title: "Staff", highlighted: currentPhaseHighlightedTiles.contains("Staff")) {
                VStack(alignment: .leading, spacing: 4) {
                    if let hc = headCoach {
                        HStack(spacing: 4) {
                            Text("HC")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.accentGold)
                            Text(hc.fullName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("No head coach")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                    }
                    HStack {
                        Text("Staff")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(coachCount) filled")
                            .font(.system(size: 11, weight: .medium).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scouting Tile

    private var scoutingTile: some View {
        NavigationLink {
            ScoutingHubView(career: career)
        } label: {
            DashboardTile(icon: "magnifyingglass", title: "Scouting", highlighted: currentPhaseHighlightedTiles.contains("Scouting")) {
                VStack(alignment: .leading, spacing: 4) {
                    let topProspect = WeekAdvancer.currentDraftClass.first
                    if let prospect = topProspect {
                        Text("\(prospect.firstName) \(prospect.lastName)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text("\(prospect.position.rawValue) \u{2014} \(prospect.college)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("No prospects scouted")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                    }
                    Text("\(WeekAdvancer.currentDraftClass.count) prospects")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cap Tile

    private var capTile: some View {
        NavigationLink {
            CapOverviewView(career: career)
        } label: {
            DashboardTile(icon: "dollarsign.circle.fill", title: "Salary Cap", highlighted: currentPhaseHighlightedTiles.contains("Salary Cap")) {
                VStack(alignment: .leading, spacing: 4) {
                    if let t = team {
                        let usedFraction = t.salaryCap > 0
                            ? Double(t.currentCapUsage) / Double(t.salaryCap)
                            : 0

                        HStack {
                            Text("Used")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(formatCap(t.currentCapUsage))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(usedFraction > 0.9 ? Color.danger : Color.accentGold)
                                    .frame(width: geo.size.width * min(usedFraction, 1.0), height: 6)
                            }
                        }
                        .frame(height: 6)

                        HStack {
                            Text("Available")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(formatCap(t.availableCap))
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(t.availableCap > 0 ? Color.success : Color.danger)
                        }
                    } else {
                        Text("No cap data")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Locker Room Tile

    private var lockerRoomTile: some View {
        NavigationLink {
            LockerRoomView(career: career)
        } label: {
            DashboardTile(icon: "heart.fill", title: "Locker Room") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Chemistry")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("Good")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.success)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.backgroundTertiary)
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.success)
                                .frame(width: geo.size.width * 0.7, height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("Morale: 70%")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Contextual Tiles

    private var draftTile: some View {
        NavigationLink {
            DraftView(career: career)
        } label: {
            DashboardTile(icon: "list.clipboard.fill", title: "Draft", highlighted: currentPhaseHighlightedTiles.contains("Draft")) {
                VStack(alignment: .leading, spacing: 4) {
                    let picks = WeekAdvancer.currentDraftPicks.filter { $0.currentTeamID == career.teamID }
                    if let firstPick = picks.first {
                        Text("Pick #\(firstPick.pickNumber)")
                            .font(.system(size: 16, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.accentGold)
                    }
                    Text("\(picks.count) pick(s)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var freeAgencyTile: some View {
        NavigationLink {
            FreeAgencyView(career: career)
        } label: {
            DashboardTile(icon: "person.badge.plus", title: "Free Agency", highlighted: currentPhaseHighlightedTiles.contains("Free Agency")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Available Cap")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(formatCap(team?.availableCap ?? 0))
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.success)
                    }
                    Text("Browse free agents")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var tradeTile: some View {
        NavigationLink {
            TradeView(career: career)
        } label: {
            DashboardTile(icon: "arrow.left.arrow.right", title: "Trade") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Trade window open")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.success)
                    Text("Review potential deals")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // NOTE: advanceWeekButton and advanceWeekButtonCompact removed --
    // advance UI is now part of TimelineTasksPanel.

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

    // MARK: - Computed Properties

    private var isOffseasonPhase: Bool {
        switch career.currentPhase {
        case .regularSeason, .playoffs, .tradeDeadline:
            return false
        default:
            return true
        }
    }

    private var divisionRank: String {
        guard let myTeam = team else { return "\u{2014}" }
        let sorted = divisionTeams.sorted { $0.wins > $1.wins }
        if let idx = sorted.firstIndex(where: { $0.id == myTeam.id }) {
            let rank = idx + 1
            return "#\(rank)"
        }
        return "\u{2014}"
    }

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

// MARK: - Dashboard Inbox Filter

private enum DashboardInboxFilter: String, CaseIterable {
    case all = "All"
    case new = "New"
    case tasks = "Tasks"
}

// MARK: - Dashboard Tile

/// Reusable tile component for the FM26-inspired grid layout.
private struct DashboardTile<Content: View>: View {

    let icon: String
    let title: String
    var highlighted: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer()
                if highlighted {
                    Text("ACTIVE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentGold))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // Content
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            highlighted ? Color.accentGold.opacity(0.6) : Color.surfaceBorder,
                            lineWidth: highlighted ? 1.5 : 1
                        )
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
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
    @Previewable @State var previewInbox: [InboxMessage] = []

    NavigationStack {
        CareerDashboardView(
            career: Career(
                playerName: "John Doe",
                role: .gm,
                capMode: .simple
            ),
            tasks: $previewTasks,
            inboxMessages: $previewInbox,
            onTaskSelected: { _ in }
        )
    }
    .modelContainer(for: Career.self, inMemory: true)
}
