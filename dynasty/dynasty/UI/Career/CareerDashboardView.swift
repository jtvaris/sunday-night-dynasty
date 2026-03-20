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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // MARK: - State

    @State private var team: Team?
    @State private var rosterCount: Int = 0
    @State private var coachCount: Int = 0
    @State private var scoutCount: Int = 0
    @State private var headCoach: Coach?
    @State private var divisionTeams: [Team] = []
    @State private var divisionRecords: [StandingsRecord] = []
    @State private var upcomingGames: [Game] = []
    @State private var lastGame: Game?
    @State private var allTeamsByID: [UUID: Team] = [:]
    @State private var players: [Player] = []
    @State private var startingQB: Player?
    @State private var bestPlayer: Player?
    @State private var bestDefensivePlayer: Player?
    @State private var coachingBudgetRemaining: Int = 0
    @State private var coachingBudgetTotal: Int = 0
    @State private var expiringContractPlayers: [Player] = []
    @State private var positionGroupGrades: [(group: String, starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int)] = []
    @State private var teamMorale: Int = 70
    @State private var previousSeasonRecord: String?
    @State private var previousSeasonYear: Int?

    /// Game summary sheet after advancing a week.
    @State private var showGameSummary = false
    @State private var lastGameResult: GameSimulator.GameResult?
    @State private var lastHomeTeam: Team?
    @State private var lastAwayTeam: Team?

    /// Inbox filter for the messages panel
    @State private var inboxFilter: DashboardInboxFilter = .all

    /// Pulsing animation state for advance button guidance
    @State private var advancePulse = false

    /// Coaching staff review sheet (shown during coachingChanges phase advance)
    @State private var showCoachingStaffReview = false
    @State private var allCoaches: [Coach] = []

    // MARK: - Derived

    private var canAdvance: Bool {
        TaskGenerator.allRequiredComplete(in: tasks)
    }

    /// Use horizontalSizeClass instead of GeometryReader for layout switching.

    // MARK: - Advance Logic

    private func performAdvance() {
        guard canAdvance else { return }

        // During coaching changes, show the review sheet instead of advancing directly
        if career.currentPhase == .coachingChanges {
            loadCoaches()
            showCoachingStaffReview = true
            return
        }

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

    /// Confirm and advance from coaching changes to review roster.
    private func confirmCoachingAdvance() {
        career.currentPhase = .reviewRoster
        try? modelContext.save()
        loadAllData()
    }

    private func loadCoaches() {
        guard let teamID = career.teamID else { return }
        let descriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        allCoaches = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            // Fix #30: Subtle stadium background texture
            GeometryReader { geo in
                Image("BgStadiumNight")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.06)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                if verticalSizeClass == .compact {
                    // Landscape: 3-column (tasks | tiles+messages | schedule+standings)
                    landscapeLayout
                } else {
                    // Portrait: 2-column (tasks | tiles+messages+standings)
                    portraitTwoColumnLayout
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
        .sheet(isPresented: $showCoachingStaffReview) {
            CoachingStaffReviewSheet(
                career: career,
                coaches: allCoaches,
                players: players,
                onConfirm: {
                    showCoachingStaffReview = false
                    confirmCoachingAdvance()
                },
                onCancel: {
                    showCoachingStaffReview = false
                }
            )
            .presentationDetents([.large])
        }
    }

    // MARK: - Landscape Layout (3-column)

    // MARK: - Portrait 2-Column Layout (tasks | content)

    private var portraitTwoColumnLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column -- Tasks (fixed 280pt)
            ScrollView {
                VStack(spacing: 0) {
                    if canAdvance {
                        allTasksCompleteBanner
                    }
                    TimelineTasksPanel(
                        career: career,
                        tasks: $tasks,
                        onTaskSelected: onTaskSelected,
                        onAdvance: { performAdvance() },
                        canAdvance: canAdvance
                    )
                }
                .padding(.leading, 8)
            }
            .frame(width: 280)

            Divider().overlay(Color.surfaceBorder)

            // Right column -- Tiles + Messages + Division + Schedule
            ScrollView {
                VStack(spacing: 12) {
                    centerTilesGrid
                    messagesPanel
                        .frame(minHeight: 240)
                        .background(Color.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                        )
                    // Division + Upcoming combined to reduce gap (#143)
                    VStack(spacing: 0) {
                        divisionStandingsSection
                            .padding(12)
                        Divider().overlay(Color.surfaceBorder.opacity(0.4))
                        scheduleSection
                            .padding(12)
                    }
                    .background(Color.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
                    .padding(.bottom, 16)
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Landscape 3-Column Layout

    private var landscapeLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column -- Timeline+Tasks Panel (fixed 300pt)
            VStack(spacing: 0) {
                // Fix #64: Clear guidance when all tasks complete
                if canAdvance {
                    allTasksCompleteBanner
                }
                TimelineTasksPanel(
                    career: career,
                    tasks: $tasks,
                    onTaskSelected: onTaskSelected,
                    onAdvance: { performAdvance() },
                    canAdvance: canAdvance
                )
            }
            .frame(width: 300)

            Divider().overlay(Color.surfaceBorder)

            // Center column -- Dashboard tiles + Messages (flexible)
            ScrollView {
                VStack(spacing: 12) {
                    centerTilesGrid
                    messagesPanel
                        .frame(minHeight: 280)
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

            Divider().overlay(Color.surfaceBorder)

            // Right column -- Division standings only (fixed 200pt)
            ScrollView {
                divisionStandingsSection
                    .padding(12)
            }
            .frame(width: 200)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Portrait Layout (stacked)

    private var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Timeline+Tasks panel (full width, collapsible)
                VStack(spacing: 0) {
                    // Fix #64: Clear guidance when all tasks complete
                    if canAdvance {
                        allTasksCompleteBanner
                    }
                    TimelineTasksPanel(
                        career: career,
                        tasks: $tasks,
                        onTaskSelected: onTaskSelected,
                        onAdvance: { performAdvance() },
                        canAdvance: canAdvance
                    )
                }
                .frame(minWidth: 320, minHeight: 280, maxHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(canAdvance ? Color.accentGold : Color.surfaceBorder, lineWidth: canAdvance ? 2 : 1)
                )
                .shadow(color: canAdvance ? Color.accentGold.opacity(advancePulse ? 0.4 : 0.1) : .clear, radius: canAdvance ? 8 : 0)
                .padding(.horizontal, 16)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                        advancePulse = true
                    }
                }

                // 2-column tile grid
                centerTilesGrid
                    .padding(.horizontal, 16)

                // Messages section (full width)
                messagesPanel
                    .frame(minHeight: 280)
                    .background(Color.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)

                // Division Standings (moved to center column in portrait)
                divisionStandingsSection
                    .padding(12)
                    .background(Color.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 16)

                // Schedule only (standings already shown above)
                rightPanelScheduleOnly
                    .padding(12)
                    .background(Color.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
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
            ("Review", "Feb", .reviewRoster, nil),
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
                    HStack(spacing: 4) {
                        Text("View All")
                            .font(.system(size: 12, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.accentGold))
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
                        let displayMessages = Array(filtered.reversed().prefix(5))
                        ForEach(displayMessages) { message in
                            messageRow(message)
                            Divider().overlay(Color.surfaceBorder.opacity(0.3))
                        }

                        if filtered.count > 5 {
                            Button {
                                onTaskSelected(.inbox)
                            } label: {
                                Text("\(filtered.count - 5) more message\(filtered.count - 5 == 1 ? "" : "s")")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.accentGold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
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
            // Row 1: Team + Roster (equalized height)
            teamTile.frame(minHeight: 160)
            rosterTile.frame(minHeight: 160)

            // Row 2: Staff + Scouting (equalized height)
            staffTile.frame(minHeight: 150)
            scoutingTile.frame(minHeight: 150)

            // Row 3: Salary Cap + Locker Room (equalized height)
            capTile.frame(minHeight: 160)
            lockerRoomTile.frame(minHeight: 160)

            // Row 4: Key Players + Position Strengths
            keyPlayersTile
            positionStrengthsTile

            // Row 5: Expiring Contracts + Owner Expectations
            expiringContractsTile
            ownerExpectationsTile

            // Previous season summary (season 2+)
            if previousSeasonRecord != nil {
                previousSeasonTile
            }

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

    /// Full right panel with both schedule and standings (used in landscape right sidebar)
    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            scheduleSection
            Divider().overlay(Color.surfaceBorder.opacity(0.6))
            divisionStandingsSection
        }
    }

    /// Schedule-only right panel (used in portrait where standings move to center)
    private var rightPanelScheduleOnly: some View {
        VStack(alignment: .leading, spacing: 16) {
            scheduleSection
        }
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
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
    }

    // MARK: - Division Standings Section

    private var divisionStandingsSection: some View {
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
                    Text("W-L")
                        .frame(width: 48, alignment: .trailing)
                    Text("PCT")
                        .frame(width: 40, alignment: .trailing)
                }
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.textTertiary)
                .textCase(.uppercase)

                ForEach(Array(divisionRecords.enumerated()), id: \.element.id) { index, record in
                    let t = allTeamsByID[record.teamID]
                    let isMyTeam = record.teamID == team?.id
                    let isLeader = index == 0
                    let wl = record.ties > 0
                        ? "\(record.wins)-\(record.losses)-\(record.ties)"
                        : "\(record.wins)-\(record.losses)"
                    let pct = record.winPercentage
                    let pctStr = pct == 1.0 ? "1.000" : String(format: ".%03d", Int((pct * 1000).rounded()))

                    HStack {
                        HStack(spacing: 4) {
                            if isLeader {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color.accentGold)
                                    .frame(width: 10)
                            } else {
                                Spacer().frame(width: 10)
                            }
                            Text(t?.abbreviation ?? "???")
                                .font(.system(size: 11, weight: isMyTeam ? .heavy : .medium))
                                .foregroundStyle(isMyTeam ? Color.accentGold : Color.textSecondary)
                        }
                        .frame(width: 54, alignment: .leading)
                        Spacer()
                        Text(wl)
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isMyTeam ? Color.textPrimary : Color.textSecondary)
                            .frame(width: 48, alignment: .trailing)
                        Text(pctStr)
                            .font(.system(size: 10, weight: .regular).monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 40, alignment: .trailing)
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

                    // Fix #28: Prominent record display
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(team?.record ?? "0-0")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)

                        Text(divisionRank)
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }

                    // Win/loss streak indicator
                    if let streak = currentStreak, streak.count > 1 {
                        Text(streak.label)
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(streak.isWin ? Color.success : Color.danger)
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
            RosterViewWrapper(career: career)
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
                    if isGMAndHC {
                        HStack(spacing: 4) {
                            Text("HC")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.accentGold)
                            Text("You")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                        }
                    } else if let hc = headCoach {
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

                    // Fix #61: Prominent filled/total staff display (coaches + scouts)
                    let totalCoachSlots = allRoles.count
                    let totalScoutSlots = 6  // Chief + 5 regional
                    let totalSlots = totalCoachSlots + totalScoutSlots
                    let filledSlots = coachCount + scoutCount
                    let isFullyStaffed = filledSlots >= totalSlots
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            Text("\(filledSlots)")
                                .font(.system(size: 18, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                            Text("/")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.textTertiary)
                            Text("\(totalSlots)")
                                .font(.system(size: 18, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.textSecondary)
                        }
                        Text("Staff")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        if isFullyStaffed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.success)
                        }
                    }

                    // Mini progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.backgroundTertiary)
                                .frame(height: 5)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(isFullyStaffed ? Color.success : Color.accentGold)
                                .frame(
                                    width: geo.size.width * min(1.0, Double(filledSlots) / Double(totalSlots)),
                                    height: 5
                                )
                        }
                    }
                    .frame(height: 5)

                    // Coaching budget remaining (#147)
                    if coachingBudgetTotal > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.square.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(coachingBudgetRemaining > 5000 ? Color.success : coachingBudgetRemaining > 2000 ? Color.accentGold : Color.warning)
                            Text("Budget")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                            Text(formatCap(coachingBudgetRemaining))
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(coachingBudgetRemaining > 5000 ? Color.success : coachingBudgetRemaining > 2000 ? Color.accentGold : Color.warning)
                            Text("/")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                            Text(formatCap(coachingBudgetTotal))
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }
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
                VStack(alignment: .leading, spacing: 6) {
                    let draftClass = WeekAdvancer.currentDraftClass
                    if draftClass.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.magnifyingglass")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.textTertiary)
                            Text("Hire scouts to begin scouting")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        // Top prospect
                        if let prospect = draftClass.first {
                            HStack(spacing: 4) {
                                Text("#1")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.accentGold)
                                Text("\(prospect.firstName) \(prospect.lastName)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                            }
                            Text("\(prospect.position.rawValue) \u{2014} \(prospect.college)")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }

                        // Prospect count by side
                        let offenseCount = draftClass.filter { $0.position.side == .offense }.count
                        let defenseCount = draftClass.filter { $0.position.side == .defense }.count
                        HStack(spacing: 12) {
                            Text("\(draftClass.count) total")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                            Text("OFF \(offenseCount)")
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                            Text("DEF \(defenseCount)")
                                .font(.system(size: 9, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
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
                VStack(alignment: .leading, spacing: 6) {
                    if let t = team {
                        let usedFraction = t.salaryCap > 0
                            ? Double(t.currentCapUsage) / Double(t.salaryCap)
                            : 0

                        HStack(alignment: .firstTextBaseline) {
                            Text("Used")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(formatCap(t.currentCapUsage))
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                        }

                        // Larger progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 12)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(capBarColor(usedFraction))
                                    .frame(width: geo.size.width * min(usedFraction, 1.0), height: 12)
                                // Percentage label inside bar
                                Text("\(Int(usedFraction * 100))%")
                                    .font(.system(size: 8, weight: .bold).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.leading, 4)
                            }
                        }
                        .frame(height: 12)

                        HStack(alignment: .firstTextBaseline) {
                            Text("Available")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(formatCap(t.availableCap))
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundStyle(t.availableCap > 0 ? Color.success : Color.danger)
                        }

                        // Total cap line
                        HStack {
                            Text("Total Cap")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                            Text(formatCap(t.salaryCap))
                                .font(.system(size: 10, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
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
                VStack(alignment: .leading, spacing: 6) {
                    // Chemistry label with dynamic text
                    HStack {
                        Text("Chemistry")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(moraleLabel(teamMorale))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(moraleColor(teamMorale))
                    }

                    // Visual morale bar (larger)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.backgroundTertiary)
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(moraleColor(teamMorale))
                                .frame(width: geo.size.width * (Double(teamMorale) / 100.0), height: 12)
                        }
                    }
                    .frame(height: 12)

                    // Morale percentage
                    HStack {
                        Text("Team Morale")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(teamMorale)%")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(moraleColor(teamMorale))
                    }

                    // Star players morale indicator
                    if let qb = startingQB {
                        HStack(spacing: 4) {
                            Text("QB")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.accentGold)
                            Text(qb.lastName)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: qb.morale >= 70 ? "face.smiling" : (qb.morale >= 40 ? "face.dashed" : "cloud.rain"))
                                .font(.system(size: 10))
                                .foregroundStyle(moraleColor(qb.morale))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Key Players Tile (#18)

    private var keyPlayersTile: some View {
        NavigationLink {
            RosterViewWrapper(career: career)
        } label: {
            DashboardTile(icon: "star.fill", title: "Key Players") {
                VStack(alignment: .leading, spacing: 4) {
                    if let qb = startingQB {
                        keyPlayerRow(label: "QB1", player: qb)
                    } else {
                        Text("No starting QB")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                    }

                    // Best defensive player (#144)
                    if let defPlayer = bestDefensivePlayer, defPlayer.id != startingQB?.id {
                        Divider().overlay(Color.surfaceBorder.opacity(0.4))
                        keyPlayerRow(label: defPlayer.position.rawValue, player: defPlayer)
                    }

                    // Best overall if different from QB and defensive star (#144)
                    if let best = bestPlayer,
                       best.id != startingQB?.id,
                       best.id != bestDefensivePlayer?.id {
                        Divider().overlay(Color.surfaceBorder.opacity(0.4))
                        keyPlayerRow(label: "MVP", player: best)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func keyPlayerRow(label: String, player: Player) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .frame(width: 28, alignment: .leading)
            Text(player.fullName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(player.overall)")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
        }
    }

    // MARK: - Position Group Strengths Tile (#17)

    private var positionStrengthsTile: some View {
        NavigationLink {
            RosterViewWrapper(career: career)
        } label: {
            DashboardTile(icon: "chart.bar.fill", title: "Position Grades") {
                VStack(alignment: .leading, spacing: 4) {
                    if positionGroupGrades.isEmpty {
                        Text("No roster data")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        // Find weakest group (#146)
                        let weakestGroup = positionGroupGrades.min(by: { $0.starterOVR < $1.starterOVR })?.group
                        // Show in two columns
                        let halfCount = (positionGroupGrades.count + 1) / 2
                        let leftCol = Array(positionGroupGrades.prefix(halfCount))
                        let rightCol = Array(positionGroupGrades.dropFirst(halfCount))
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(leftCol, id: \.group) { item in
                                    positionGradeRow(item, isWeakest: item.group == weakestGroup)
                                }
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(rightCol, id: \.group) { item in
                                    positionGradeRow(item, isWeakest: item.group == weakestGroup)
                                }
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func positionGradeRow(_ item: (group: String, starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int), isWeakest: Bool = false) -> some View {
        HStack(spacing: 2) {
            Text(item.group)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 22, alignment: .leading)
            Text("S:")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            Text(item.starterGrade)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(item.starterGrade))
            Text("/")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
            Text("D:")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            Text(item.depthGrade)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(item.depthGrade))
            if isWeakest {
                Text("NEED")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.danger.opacity(0.15))
                    )
            }
        }
    }

    // MARK: - Expiring Contracts Tile (#19)

    private var expiringContractsTile: some View {
        NavigationLink {
            CapOverviewView(career: career)
        } label: {
            DashboardTile(icon: "clock.badge.exclamationmark", title: "Contracts") {
                VStack(alignment: .leading, spacing: 6) {
                    if expiringContractPlayers.isEmpty {
                        Text("No expiring contracts")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(expiringContractPlayers.count)")
                                .font(.system(size: 20, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.warning)
                            Text("expiring contract\(expiringContractPlayers.count == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }

                        // Show top 3 names sorted by OVR, with star alert (#145)
                        let topExpiring = Array(expiringContractPlayers.sorted { $0.overall > $1.overall }.prefix(3))
                        ForEach(topExpiring, id: \.id) { player in
                            let isStar = player.overall >= 80
                            HStack(spacing: 4) {
                                if isStar {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color.warning)
                                }
                                Text(player.position.rawValue)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(isStar ? Color.warning : Color.accentGold)
                                Text(player.lastName)
                                    .font(.system(size: 10, weight: isStar ? .bold : .medium))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(player.overall)")
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Color.forRating(player.overall))
                                Text(formatCap(player.annualSalary))
                                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Owner Expectations Tile (#20)

    private var ownerExpectationsTile: some View {
        NavigationLink {
            OwnerMeetingView(career: career)
        } label: {
            DashboardTile(icon: "building.2.fill", title: "Owner") {
                VStack(alignment: .leading, spacing: 6) {
                    if let owner = team?.owner {
                        Text(owner.name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        HStack {
                            Text("Patience")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            // Patience shown as visual pips (1-10)
                            HStack(spacing: 2) {
                                ForEach(0..<10, id: \.self) { i in
                                    Circle()
                                        .fill(i < owner.patience ? Color.accentGold : Color.backgroundTertiary)
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }

                        HStack {
                            Text("Satisfaction")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text("\(owner.satisfaction)%")
                                .font(.system(size: 12, weight: .bold).monospacedDigit())
                                .foregroundStyle(satisfactionColor(owner.satisfaction))
                        }

                        HStack {
                            Text("Style")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(owner.prefersWinNow ? "Win Now" : "Rebuild OK")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(owner.prefersWinNow ? Color.warning : Color.success)
                        }
                    } else {
                        Text("No owner data")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Previous Season Summary Tile (#73)

    private var previousSeasonTile: some View {
        DashboardTile(icon: "clock.arrow.circlepath", title: "Last Season") {
            VStack(alignment: .leading, spacing: 6) {
                if let record = previousSeasonRecord, let year = previousSeasonYear {
                    Text("Season \(year)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(record)
                            .font(.system(size: 18, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if career.championships > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.accentGold)
                                Text("\(career.championships)")
                                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Color.accentGold)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        if career.playoffAppearances > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.success)
                                Text("\(career.playoffAppearances) playoff\(career.playoffAppearances == 1 ? "" : "s")")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        Text("Career: \(career.totalWins)-\(career.totalLosses)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
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

    // MARK: - All Tasks Complete Banner (Fix #64)

    private var allTasksCompleteBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.success)
            Text("All tasks complete!")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.success)
            Spacer()
            Text("Ready to advance")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentGold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.success.opacity(0.1))
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

    private func moraleLabel(_ morale: Int) -> String {
        if morale >= 80 { return "Excellent" }
        if morale >= 60 { return "Good" }
        if morale >= 40 { return "Neutral" }
        if morale >= 20 { return "Poor" }
        return "Toxic"
    }

    private func moraleColor(_ morale: Int) -> Color {
        if morale >= 70 { return Color.success }
        if morale >= 40 { return Color.warning }
        return Color.danger
    }

    private func gradeForOVR(_ ovr: Int) -> String {
        if ovr >= 90 { return "A+" }
        if ovr >= 85 { return "A" }
        if ovr >= 80 { return "A-" }
        if ovr >= 77 { return "B+" }
        if ovr >= 73 { return "B" }
        if ovr >= 70 { return "B-" }
        if ovr >= 67 { return "C+" }
        if ovr >= 63 { return "C" }
        if ovr >= 60 { return "C-" }
        if ovr >= 55 { return "D+" }
        if ovr >= 50 { return "D" }
        return "F"
    }

    private func capBarColor(_ fraction: Double) -> Color {
        if fraction > 0.9 { return Color.danger }
        if fraction > 0.8 { return Color.warning }
        return Color.success
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

    /// Streak info derived from recent played games.
    private var currentStreak: (label: String, count: Int, isWin: Bool)? {
        guard let teamID = career.teamID else { return nil }
        let seasonYear = career.currentSeason
        let gameDescriptor = FetchDescriptor<Game>(predicate: #Predicate {
            $0.seasonYear == seasonYear
        })
        let allGames = (try? modelContext.fetch(gameDescriptor)) ?? []
        let playedGames = allGames
            .filter { ($0.homeTeamID == teamID || $0.awayTeamID == teamID) && $0.isPlayed }
            .sorted { $0.week > $1.week }

        guard let latest = playedGames.first,
              let latestHS = latest.homeScore,
              let latestAS = latest.awayScore else { return nil }

        let latestIsWin: Bool = {
            let isHome = latest.homeTeamID == teamID
            return isHome ? latestHS > latestAS : latestAS > latestHS
        }()

        var streakCount = 0
        for game in playedGames {
            guard let hs = game.homeScore, let aws = game.awayScore else { break }
            let isHome = game.homeTeamID == teamID
            let won = isHome ? hs > aws : aws > hs
            if won == latestIsWin {
                streakCount += 1
            } else {
                break
            }
        }

        let label = latestIsWin ? "W\(streakCount)" : "L\(streakCount)"
        return (label, streakCount, latestIsWin)
    }

    private var divisionRank: String {
        guard let myTeam = team else { return "\u{2014}" }
        if !divisionRecords.isEmpty {
            if let idx = divisionRecords.firstIndex(where: { $0.teamID == myTeam.id }) {
                return "#\(idx + 1)"
            }
        }
        // Fallback to simple wins sort when records aren't available yet
        let sorted = divisionTeams.sorted { $0.wins > $1.wins }
        if let idx = sorted.firstIndex(where: { $0.id == myTeam.id }) {
            return "#\(idx + 1)"
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
        case .reviewRoster:
            return ["Roster", "Salary Cap"]
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

        // Roster count and players
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        players = (try? modelContext.fetch(playerDescriptor)) ?? []
        rosterCount = players.count

        // Key players (#18, #144)
        startingQB = players.filter { $0.position == .QB }.max(by: { $0.overall < $1.overall })
        bestPlayer = players.max(by: { $0.overall < $1.overall })
        bestDefensivePlayer = players.filter { $0.position.side == .defense }.max(by: { $0.overall < $1.overall })

        // Expiring contracts (#19)
        expiringContractPlayers = players.filter { $0.contractYearsRemaining <= 1 }

        // Team morale (#82) — average of all player morale
        if !players.isEmpty {
            teamMorale = players.reduce(0) { $0 + $1.morale } / players.count
        }

        // Position group grades (#17)
        positionGroupGrades = calculatePositionGroupGrades(players: players)

        // Coach count + head coach
        let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
        allCoaches = coaches
        coachCount = coaches.count
        headCoach = coaches.first(where: { $0.role == .headCoach })

        // Coaching budget (#147) — includes both coach and scout salaries
        let budgetTotal = team?.owner?.coachingBudget ?? 0
        let coachSalaryUsed = coaches.reduce(0) { $0 + $1.salary }
        let scoutDescriptor = FetchDescriptor<Scout>(predicate: #Predicate { $0.teamID == teamID })
        let fetchedScouts = (try? modelContext.fetch(scoutDescriptor)) ?? []
        scoutCount = fetchedScouts.count
        let scoutSalaryUsed = fetchedScouts.reduce(0) { $0 + $1.salary }
        coachingBudgetTotal = budgetTotal
        coachingBudgetRemaining = budgetTotal - coachSalaryUsed - scoutSalaryUsed

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

        // Division standings from calculated records (proper NFL tiebreakers)
        if let myTeam = team {
            let allRecords = StandingsCalculator.calculate(games: allGames, teams: allTeams)
            divisionRecords = StandingsCalculator.divisionStandings(
                records: allRecords,
                teams: allTeams,
                conference: myTeam.conference,
                division: myTeam.division
            )
        }

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

        // Previous season summary (#73)
        let prevYear = career.currentSeason - 1
        if prevYear >= 1 {
            let prevGameDescriptor = FetchDescriptor<Game>(predicate: #Predicate {
                $0.seasonYear == prevYear
            })
            let prevGames = (try? modelContext.fetch(prevGameDescriptor)) ?? []
            let prevMyGames = prevGames.filter {
                ($0.homeTeamID == teamID || $0.awayTeamID == teamID) && $0.isPlayed
            }
            if !prevMyGames.isEmpty {
                var w = 0, l = 0
                for game in prevMyGames {
                    guard let hs = game.homeScore, let aws = game.awayScore else { continue }
                    let isHome = game.homeTeamID == teamID
                    let won = isHome ? hs > aws : aws > hs
                    if won { w += 1 } else { l += 1 }
                }
                previousSeasonRecord = "\(w)-\(l)"
                previousSeasonYear = prevYear
            } else {
                previousSeasonRecord = nil
                previousSeasonYear = nil
            }
        } else {
            previousSeasonRecord = nil
            previousSeasonYear = nil
        }
    }

    /// Calculate starter + depth grades by position group (#235).
    private func calculatePositionGroupGrades(players: [Player]) -> [(group: String, starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int)] {
        let groups: [(label: String, positions: [Position])] = [
            ("QB", [.QB]),
            ("RB", [.RB, .FB]),
            ("WR", [.WR]),
            ("TE", [.TE]),
            ("OL", [.LT, .LG, .C, .RG, .RT]),
            ("DL", [.DE, .DT]),
            ("LB", [.OLB, .MLB]),
            ("CB", [.CB]),
            ("S", [.FS, .SS]),
        ]

        var results: [(group: String, starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int)] = []
        for group in groups {
            let groupPlayers = players.filter { group.positions.contains($0.position) }
            guard !groupPlayers.isEmpty else { continue }
            let grades = PositionGradeCalculator.calculatePositionGrades(players: groupPlayers, positions: group.positions)
            results.append((group: group.label, starterGrade: grades.starterGrade, depthGrade: grades.depthGrade, starterOVR: grades.starterOVR, depthOVR: grades.depthOVR))
        }
        return results
    }

    // MARK: - Career Role Helpers

    private var isGMAndHC: Bool {
        career.role == .gmAndHeadCoach
    }

    private var allRoles: [CoachRole] {
        if isGMAndHC {
            return CoachRole.allCases.filter { $0 != .headCoach }
        }
        return CoachRole.allCases
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

// MARK: - Coaching Staff Review Sheet

/// A review sheet shown when the user advances from the Coaching Changes phase.
/// Summarizes all hired coaches, vacant positions, schemes, and validation warnings.
private struct CoachingStaffReviewSheet: View {

    let career: Career
    let coaches: [Coach]
    let players: [Player]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    // MARK: - Derived

    private var isGMAndHC: Bool {
        career.role == .gmAndHeadCoach
    }

    private var allRoles: [CoachRole] {
        if isGMAndHC {
            return CoachRole.allCases.filter { $0 != .headCoach }
        }
        return CoachRole.allCases
    }

    private var filledRoles: Set<CoachRole> {
        Set(coaches.map { $0.role })
    }

    private var requiredRoles: [CoachRole] {
        if isGMAndHC {
            return [.offensiveCoordinator, .defensiveCoordinator]
        }
        return [.headCoach, .offensiveCoordinator, .defensiveCoordinator]
    }

    private var missingRequiredRoles: [CoachRole] {
        requiredRoles.filter { !filledRoles.contains($0) }
    }

    private var vacantRoles: [CoachRole] {
        allRoles.filter { !filledRoles.contains($0) }
    }

    private var oc: Coach? {
        coaches.first { $0.role == .offensiveCoordinator }
    }

    private var dc: Coach? {
        coaches.first { $0.role == .defensiveCoordinator }
    }

    private var areSchemesSet: Bool {
        oc?.offensiveScheme != nil && dc?.defensiveScheme != nil
    }

    private var hasValidationWarnings: Bool {
        !missingRequiredRoles.isEmpty || !areSchemesSet
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    headerSection

                    // Staff listing
                    staffSection

                    // Schemes
                    schemesSection

                    // Warnings
                    if hasValidationWarnings {
                        warningsSection
                    }

                    // Buttons
                    buttonsSection
                }
                .padding(20)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Coaching Staff Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("COACHING STAFF REVIEW")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color.accentGold)
                .tracking(1.0)

            Rectangle()
                .fill(Color.accentGold.opacity(0.3))
                .frame(height: 1)
        }
    }

    // MARK: - Staff Section

    private var staffSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text("STAFF")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)
                Spacer()
                Text("\(coaches.count)/\(allRoles.count) filled")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.bottom, 8)

            // Player as HC (if GM+HC role)
            if isGMAndHC {
                staffRow(
                    role: .headCoach,
                    name: "You (The Tactician)",
                    overall: nil,
                    schemeName: nil,
                    isFilled: true,
                    isRequired: true
                )
            }

            // All roles in sort order
            ForEach(allRoles.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { role in
                if let coach = coaches.first(where: { $0.role == role }) {
                    let schemeName: String? = {
                        if role == .offensiveCoordinator {
                            return coach.offensiveScheme?.displayName
                        } else if role == .defensiveCoordinator {
                            return coach.defensiveScheme?.displayName
                        }
                        return nil
                    }()
                    staffRow(
                        role: role,
                        name: coach.fullName,
                        overall: coachOverall(coach),
                        schemeName: schemeName,
                        isFilled: true,
                        isRequired: requiredRoles.contains(role)
                    )
                } else {
                    staffRow(
                        role: role,
                        name: "VACANT",
                        overall: nil,
                        schemeName: nil,
                        isFilled: false,
                        isRequired: requiredRoles.contains(role)
                    )
                }
            }
        }
        .padding(12)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
    }

    private func staffRow(
        role: CoachRole,
        name: String,
        overall: Int?,
        schemeName: String?,
        isFilled: Bool,
        isRequired: Bool
    ) -> some View {
        HStack(spacing: 8) {
            // Status icon
            Image(systemName: isFilled ? "checkmark.circle.fill" : (isRequired ? "exclamationmark.triangle.fill" : "circle"))
                .font(.system(size: 14))
                .foregroundStyle(isFilled ? Color.success : (isRequired ? Color.warning : Color.textTertiary))
                .frame(width: 18)

            // Role abbreviation
            Text(role.abbreviation)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .frame(width: 30, alignment: .leading)

            // Name
            Text(name)
                .font(.system(size: 13, weight: isFilled ? .medium : .bold))
                .foregroundStyle(isFilled ? Color.textPrimary : Color.warning)
                .lineLimit(1)

            Spacer()

            // Scheme badge (for coordinators)
            if let scheme = schemeName {
                Text(scheme)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.accentGold.opacity(0.12))
                    )
            }

            // OVR
            if let ovr = overall {
                Text("\(ovr)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(ovr))
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(!isFilled && isRequired ? Color.warning.opacity(0.06) : Color.clear)
        )
    }

    // MARK: - Schemes Section

    private var schemesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text("SCHEMES & EXPERTISE")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)
            }

            // Each coach's scheme expertise
            ForEach(coaches.sorted(by: { $0.role.sortOrder < $1.role.sortOrder }), id: \.id) { coach in
                let expertisePairs = coach.schemeExpertise
                    .sorted { $0.value > $1.value }
                    .prefix(3)

                if !expertisePairs.isEmpty || coach.offensiveScheme != nil || coach.defensiveScheme != nil {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(coach.role.abbreviation)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Color.accentGold)
                                .frame(width: 26)
                                .padding(.vertical, 2)
                                .background(Color.accentGold.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                            Text(coach.fullName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if let scheme = coach.offensiveScheme {
                                Text(scheme.displayName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.accentBlue)
                            } else if let scheme = coach.defensiveScheme {
                                Text(scheme.displayName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.accentBlue)
                            }
                        }

                        // Expertise bars
                        if !expertisePairs.isEmpty {
                            HStack(spacing: 8) {
                                ForEach(Array(expertisePairs), id: \.key) { schemeName, level in
                                    let label = schemeDisplayLabel(schemeName)
                                    HStack(spacing: 4) {
                                        Text(label)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(Color.textTertiary)
                                            .lineLimit(1)
                                        Text("\(level)")
                                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                                            .foregroundStyle(Color.forRating(level))
                                    }
                                }
                            }
                            .padding(.leading, 34)
                        }
                    }

                    if coach.id != coaches.sorted(by: { $0.role.sortOrder < $1.role.sortOrder }).last?.id {
                        Divider().overlay(Color.surfaceBorder.opacity(0.4))
                    }
                }
            }

            // Scheme Fit Analysis
            if let offScheme = oc?.offensiveScheme {
                Divider().overlay(Color.surfaceBorder.opacity(0.5))
                schemeFitAnalysis(
                    scheme: offScheme.displayName,
                    schemeKey: offScheme.rawValue,
                    side: .offense,
                    isOffensive: true
                )
            }
            if let defScheme = dc?.defensiveScheme {
                Divider().overlay(Color.surfaceBorder.opacity(0.5))
                schemeFitAnalysis(
                    scheme: defScheme.displayName,
                    schemeKey: defScheme.rawValue,
                    side: .defense,
                    isOffensive: false
                )
            }

            // Staff Chemistry
            Divider().overlay(Color.surfaceBorder.opacity(0.5))
            staffChemistryRow
        }
        .padding(12)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
    }

    private func schemeDisplayLabel(_ rawValue: String) -> String {
        if let off = OffensiveScheme(rawValue: rawValue) { return off.displayName }
        if let def = DefensiveScheme(rawValue: rawValue) { return def.displayName }
        return rawValue
    }

    // MARK: - Scheme Fit Analysis

    private func schemeFitAnalysis(scheme: String, schemeKey: String, side: PositionSide, isOffensive: Bool) -> some View {
        let coachFit = calculateCoachFit(schemeKey: schemeKey, isOffensive: isOffensive)
        let rosterFit = calculateRosterFit(schemeKey: schemeKey, side: side)
        let alternative = bestAlternativeScheme(currentKey: schemeKey, side: side, isOffensive: isOffensive)

        return VStack(alignment: .leading, spacing: 8) {
            // Current scheme header
            HStack(spacing: 6) {
                Image(systemName: isOffensive ? "football.fill" : "shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isOffensive ? Color.accentBlue : Color.danger)
                Text("\(isOffensive ? "OFFENSIVE" : "DEFENSIVE") SCHEME: \(scheme)")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.textPrimary)
                    .tracking(0.3)
            }

            // Coach Fit
            schemeFitBar(
                label: "Coach Fit",
                percent: coachFit.total,
                detail: coachFit.detail,
                color: fitBarColor(coachFit.total)
            )

            // Roster Fit
            schemeFitBar(
                label: "Roster Fit",
                percent: rosterFit.percent,
                detail: "\(rosterFit.familiarCount)/\(rosterFit.starterCount) starters familiar",
                color: fitBarColor(rosterFit.percent)
            )

            // Best Alternative
            if let alt = alternative {
                let currentTotal = coachFit.total + rosterFit.percent
                let altTotal = alt.coachFit + alt.rosterFit
                let significantlyBetter = altTotal - currentTotal > 20 // >10% avg across both

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 9))
                            .foregroundStyle(significantlyBetter ? Color.warning : Color.textTertiary)
                        Text("Alternative: \(alt.name)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(significantlyBetter ? Color.warning : Color.textSecondary)
                    }

                    HStack(spacing: 12) {
                        HStack(spacing: 3) {
                            Text("Coach:")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                            Text("\(alt.coachFit)%")
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundStyle(fitBarColor(alt.coachFit))
                        }
                        HStack(spacing: 3) {
                            Text("Roster:")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                            Text("\(alt.rosterFit)%")
                                .font(.system(size: 9, weight: .bold).monospacedDigit())
                                .foregroundStyle(fitBarColor(alt.rosterFit))
                        }
                    }
                    .padding(.leading, 13)

                    if significantlyBetter {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 9))
                            Text("Consider switching -- \(alt.name) may be a better fit")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(Color.warning)
                        .padding(.leading, 13)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(significantlyBetter ? Color.warning.opacity(0.06) : Color.backgroundPrimary.opacity(0.5))
                )
            }
        }
    }

    private func schemeFitBar(label: String, percent: Int, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 60, alignment: .leading)
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.surfaceBorder.opacity(0.4))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(min(percent, 100)) / 100.0)
                    }
                }
                .frame(height: 6)
            }
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 66)
        }
    }

    private func fitBarColor(_ percent: Int) -> Color {
        if percent >= 75 { return .success }
        if percent >= 50 { return .accentGold }
        if percent >= 25 { return .warning }
        return .danger
    }

    // MARK: - Fit Calculation Helpers

    private struct CoachFitResult {
        let total: Int
        let detail: String
    }

    private struct RosterFitResult {
        let percent: Int
        let familiarCount: Int
        let starterCount: Int
    }

    private struct AlternativeScheme {
        let name: String
        let coachFit: Int
        let rosterFit: Int
    }

    private func calculateCoachFit(schemeKey: String, isOffensive: Bool) -> CoachFitResult {
        // Relevant coaches: coordinator + position coaches on that side
        let relevantRoles: [CoachRole] = isOffensive
            ? [.offensiveCoordinator, .qbCoach, .rbCoach, .wrCoach, .olCoach]
            : [.defensiveCoordinator, .dlCoach, .lbCoach, .dbCoach]

        let relevantCoaches = coaches.filter { relevantRoles.contains($0.role) }
        guard !relevantCoaches.isEmpty else { return CoachFitResult(total: 0, detail: "No coaches") }

        let expertiseValues = relevantCoaches.map { ($0.role.abbreviation, $0.expertise(for: schemeKey)) }
        let avg = expertiseValues.reduce(0) { $0 + $1.1 } / expertiseValues.count

        let detailParts = expertiseValues.prefix(3).map { "\($0.0): \($0.1)" }
        let detail = detailParts.joined(separator: ", ")

        return CoachFitResult(total: avg, detail: detail)
    }

    private func calculateRosterFit(schemeKey: String, side: PositionSide) -> RosterFitResult {
        let sidePlayers = players.filter { $0.position.side == side }
        let starters = Array(sidePlayers.sorted { $0.overall > $1.overall }.prefix(11))
        let familiarCount = starters.filter { $0.schemeFam(for: schemeKey) >= 50 }.count
        let pct = starters.isEmpty ? 0 : Int(Double(familiarCount) / Double(starters.count) * 100)
        return RosterFitResult(percent: pct, familiarCount: familiarCount, starterCount: starters.count)
    }

    private func bestAlternativeScheme(currentKey: String, side: PositionSide, isOffensive: Bool) -> AlternativeScheme? {
        struct SchemeScore: Comparable {
            let name: String
            let key: String
            let coachFit: Int
            let rosterFit: Int
            var total: Int { coachFit + rosterFit }
            static func < (lhs: SchemeScore, rhs: SchemeScore) -> Bool { lhs.total < rhs.total }
        }

        var scores: [SchemeScore] = []
        if isOffensive {
            for scheme in OffensiveScheme.allCases where scheme.rawValue != currentKey {
                let cf = calculateCoachFit(schemeKey: scheme.rawValue, isOffensive: true).total
                let rf = calculateRosterFit(schemeKey: scheme.rawValue, side: side).percent
                scores.append(SchemeScore(name: scheme.displayName, key: scheme.rawValue, coachFit: cf, rosterFit: rf))
            }
        } else {
            for scheme in DefensiveScheme.allCases where scheme.rawValue != currentKey {
                let cf = calculateCoachFit(schemeKey: scheme.rawValue, isOffensive: false).total
                let rf = calculateRosterFit(schemeKey: scheme.rawValue, side: side).percent
                scores.append(SchemeScore(name: scheme.displayName, key: scheme.rawValue, coachFit: cf, rosterFit: rf))
            }
        }

        guard let best = scores.max() else { return nil }
        return AlternativeScheme(name: best.name, coachFit: best.coachFit, rosterFit: best.rosterFit)
    }

    private var staffChemistryRow: some View {
        let score = calculateStaffChemistry()
        let grade: String = score >= 75 ? "Great" : (score >= 50 ? "Good" : (score >= 25 ? "Fair" : "Poor"))
        let gradeColor: Color = score >= 75 ? .success : (score >= 50 ? .accentGold : (score >= 25 ? .warning : .danger))

        return HStack(spacing: 6) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 10))
                .foregroundStyle(gradeColor)
                .frame(width: 18)
            Text("Staff chemistry: **\(grade)**")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(grade)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(gradeColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(gradeColor.opacity(0.12), in: Capsule())
        }
    }

    /// Simple personality-based chemistry score (0-100).
    private func calculateStaffChemistry() -> Int {
        guard coaches.count >= 2 else { return 50 }

        // Compatible personality pairs get bonus, clashing pairs get penalty
        let compatiblePairs: Set<Set<PersonalityArchetype>> = [
            [.teamLeader, .mentor],
            [.teamLeader, .steadyPerformer],
            [.mentor, .quietProfessional],
            [.quietProfessional, .steadyPerformer],
            [.fieryCompetitor, .teamLeader],
        ]
        let clashingPairs: Set<Set<PersonalityArchetype>> = [
            [.fieryCompetitor, .dramaQueen],
            [.loneWolf, .teamLeader],
            [.dramaQueen, .quietProfessional],
            [.classClown, .fieryCompetitor],
        ]

        var score = 50
        for i in 0..<coaches.count {
            for j in (i + 1)..<coaches.count {
                let pair: Set<PersonalityArchetype> = [coaches[i].personality, coaches[j].personality]
                if compatiblePairs.contains(pair) { score += 8 }
                if clashingPairs.contains(pair) { score -= 10 }
                if coaches[i].personality == coaches[j].personality { score += 3 }
            }
        }
        return min(max(score, 0), 100)
    }

    // MARK: - Warnings Section

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vacantRoles.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.warning)
                    Text("\(vacantRoles.count) position\(vacantRoles.count == 1 ? "" : "s") still vacant")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.warning)
                }
            }

            if !missingRequiredRoles.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.danger)
                    Text("Missing: \(missingRequiredRoles.map { $0.displayName }.joined(separator: ", "))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.danger)
                }

                Text("Without coordinators: -20% offense/defense efficiency, slower player development")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.danger.opacity(0.8))
                    .padding(.leading, 18)
            }

            if !areSchemesSet {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.warning)
                    Text("Schemes not fully configured. Go to Staff > Schemes to set them.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.warning)
                }
            }
        }
        .padding(12)
        .background(Color.warning.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.warning.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Buttons Section

    private var buttonsSection: some View {
        VStack(spacing: 10) {
            Button {
                onConfirm()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text(missingRequiredRoles.isEmpty && areSchemesSet
                         ? "Confirm & Advance to Review Roster"
                         : "Lock in Anyway & Advance")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Color.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(missingRequiredRoles.isEmpty && areSchemesSet
                              ? Color.accentGold
                              : Color.warning)
                )
            }
            .buttonStyle(.plain)

            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: - Coach Overall Helper

    private func coachOverall(_ coach: Coach) -> Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
        return sum / 9
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
