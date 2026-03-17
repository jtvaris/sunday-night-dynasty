import SwiftUI
import SwiftData

/// Outer container that holds the persistent TopNavigationBar,
/// the main NavigationStack content area, and the CalendarSidebarView.
/// Now integrates with `TaskGenerator` to drive the guided wizard/task system.
struct CareerShellView: View {

    @Bindable var career: Career
    @Environment(\.modelContext) private var modelContext

    @State private var showCalendar = false
    @State private var team: Team?
    @State private var upcomingGames: [Game] = []
    @State private var allTeamsByID: [UUID: Team] = [:]

    /// Navigation path for bookmark quick-nav.
    @State private var navigationPath = NavigationPath()

    /// The current list of tasks for the active phase, persisted across view
    /// updates. Regenerated when the phase changes.
    @State private var currentTasks: [GameTask] = []

    /// Tracks the last phase we generated tasks for, so we can detect phase changes.
    @State private var lastGeneratedPhase: SeasonPhase?

    var body: some View {
        VStack(spacing: 0) {
            // Persistent top navigation bar
            TopNavigationBar(
                teamAbbreviation: team?.abbreviation ?? "???",
                teamName: team?.fullName ?? "No Team",
                pendingTaskCount: pendingTaskCount,
                onCalendarTapped: { showCalendar = true },
                onBookmarkTapped: { destination in
                    handleBookmarkNavigation(destination)
                }
            )

            // Main content area
            NavigationStack(path: $navigationPath) {
                CareerDashboardView(career: career)
                    .navigationDestination(for: ShellDestination.self) { dest in
                        destinationView(for: dest)
                    }
            }
        }
        .background(Color.backgroundPrimary)
        .navigationBarBackButtonHidden(true)
        .task { loadShellData() }
        .onChange(of: career.currentPhase) { _, newPhase in
            regenerateTasks(for: newPhase)
        }
        .sheet(isPresented: $showCalendar) {
            CalendarSidebarView(
                career: career,
                team: team,
                upcomingGames: upcomingGames,
                allTeams: allTeamsByID,
                tasks: $currentTasks,
                onTaskSelected: { destination in
                    handleTaskNavigation(destination)
                },
                onAdvancePhase: {
                    showCalendar = false
                    // The advance logic is handled by WeekAdvancer elsewhere;
                    // this is a placeholder for triggering that flow.
                },
                onDismiss: { showCalendar = false }
            )
            .presentationDetents([.large, .medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Navigation Destinations

    enum ShellDestination: Hashable {
        case roster, schedule, standings, draft, scouting, cap
        case depthChart, gamePlan, coachingStaff, hireCoach
        case prospectList, bigBoard, capOverview, freeAgency
        case contractTimeline, mentoring, trades, news
        case ownerMeeting, lockerRoom
    }

    @ViewBuilder
    private func destinationView(for destination: ShellDestination) -> some View {
        switch destination {
        case .roster:
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                Text("Roster - Coming Soon")
                    .font(.title2)
                    .foregroundStyle(Color.textSecondary)
            }
            .navigationTitle("Roster")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { markTaskVisited(for: .roster) }
        case .schedule:
            ScheduleView(career: career)
                .onAppear { markTaskVisited(for: .schedule) }
        case .standings:
            StandingsView(career: career)
                .onAppear { markTaskVisited(for: .standings) }
        case .draft:
            DraftView(career: career)
                .onAppear { markTaskVisited(for: .draft) }
        case .scouting:
            ScoutingHubView(career: career)
                .onAppear { markTaskVisited(for: .scouting) }
        case .cap, .capOverview:
            CapOverviewView(career: career)
                .onAppear { markTaskVisited(for: .capOverview) }
        case .depthChart:
            DepthChartView(career: career)
                .onAppear { markTaskVisited(for: .depthChart) }
        case .gamePlan:
            GamePlanView(gamePlan: .constant(.balanced))
                .onAppear { markTaskVisited(for: .gamePlan) }
        case .coachingStaff, .hireCoach:
            CoachingStaffView(career: career)
                .onAppear {
                    markTaskVisited(for: .coachingStaff)
                    markTaskVisited(for: .hireCoach)
                }
        case .prospectList:
            ScoutingHubView(career: career)
                .onAppear { markTaskVisited(for: .prospectList) }
        case .bigBoard:
            ScoutingHubView(career: career)
                .onAppear { markTaskVisited(for: .bigBoard) }
        case .freeAgency:
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                Text("Free Agency - Coming Soon")
                    .font(.title2)
                    .foregroundStyle(Color.textSecondary)
            }
            .navigationTitle("Free Agency")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { markTaskVisited(for: .freeAgency) }
        case .contractTimeline:
            ContractTimelineView(career: career)
                .onAppear { markTaskVisited(for: .contractTimeline) }
        case .mentoring:
            MentoringView(career: career)
                .onAppear { markTaskVisited(for: .mentoring) }
        case .trades:
            TradeView(career: career)
                .onAppear { markTaskVisited(for: .trades) }
        case .news:
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                Text("News - Coming Soon")
                    .font(.title2)
                    .foregroundStyle(Color.textSecondary)
            }
            .navigationTitle("News")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { markTaskVisited(for: .news) }
        case .ownerMeeting:
            OwnerMeetingView(career: career)
                .onAppear { markTaskVisited(for: .ownerMeeting) }
        case .lockerRoom:
            LockerRoomView(career: career)
                .onAppear { markTaskVisited(for: .lockerRoom) }
        }
    }

    // MARK: - Task Navigation

    /// Maps a `TaskDestination` to a `ShellDestination` and navigates there.
    private func handleTaskNavigation(_ destination: TaskDestination) {
        let shellDest: ShellDestination
        switch destination {
        case .roster:             shellDest = .roster
        case .depthChart:         shellDest = .depthChart
        case .gamePlan:           shellDest = .gamePlan
        case .schedule:           shellDest = .schedule
        case .standings:          shellDest = .standings
        case .coachingStaff:      shellDest = .coachingStaff
        case .hireCoach:          shellDest = .hireCoach
        case .scouting:           shellDest = .scouting
        case .prospectList:       shellDest = .prospectList
        case .bigBoard:           shellDest = .bigBoard
        case .capOverview:        shellDest = .capOverview
        case .freeAgency:         shellDest = .freeAgency
        case .contractTimeline:   shellDest = .contractTimeline
        case .draft:              shellDest = .draft
        case .mentoring:          shellDest = .mentoring
        case .trades:             shellDest = .trades
        case .news:               shellDest = .news
        case .ownerMeeting:       shellDest = .ownerMeeting
        case .lockerRoom:         shellDest = .lockerRoom
        }

        // Dismiss calendar, then navigate
        showCalendar = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            navigationPath = NavigationPath()
            navigationPath.append(shellDest)
        }
    }

    /// When a destination view appears, mark matching tasks as in-progress
    /// (if todo) so the sidebar reflects that the player has visited the view.
    private func markTaskVisited(for destination: TaskDestination) {
        for index in currentTasks.indices {
            if currentTasks[index].destination == destination && currentTasks[index].status == .todo {
                currentTasks[index].status = .inProgress
            }
        }
    }

    /// Mark a task as completed by its destination. Call this from specific
    /// view actions (e.g., after actually setting the depth chart, signing a
    /// player, completing the draft, etc.).
    func markTaskCompleted(for destination: TaskDestination) {
        for index in currentTasks.indices {
            if currentTasks[index].destination == destination && currentTasks[index].status != .done {
                currentTasks[index].status = .done
            }
        }
    }

    // MARK: - Bookmark Navigation

    private func handleBookmarkNavigation(_ bookmark: TopNavigationBar.BookmarkDestination) {
        let dest: ShellDestination
        switch bookmark {
        case .roster:    dest = .roster
        case .schedule:  dest = .schedule
        case .standings: dest = .standings
        case .draft:     dest = .draft
        case .scouting:  dest = .scouting
        case .cap:       dest = .cap
        }
        // Reset to root then push the destination
        navigationPath = NavigationPath()
        navigationPath.append(dest)
    }

    // MARK: - Pending Task Count

    /// Badge count: number of incomplete required tasks.
    private var pendingTaskCount: Int {
        TaskGenerator.incompleteRequiredCount(in: currentTasks)
    }

    // MARK: - Task Generation

    /// Regenerate the task list for the given phase using current game state.
    private func regenerateTasks(for phase: SeasonPhase) {
        guard phase != lastGeneratedPhase else { return }
        lastGeneratedPhase = phase

        let rosterCount = team?.players.count ?? 53
        let hasPendingTradeOffers = false // TODO: wire up when TradeOffer model exists
        let hasCoachingVacancies = false  // TODO: wire up when coaching vacancy tracking exists
        let hasExpiringContracts = false  // TODO: wire up when contract expiration tracking exists
        let hasScoutsAssigned = false     // TODO: wire up when scout deployment tracking exists
        let hasPendingEvents = !WeekAdvancer.lastEvents.isEmpty
        let ownerSatisfaction = team?.owner?.satisfaction ?? 50

        // Determine opponent name for game-week phases
        var opponentName: String? = nil
        if let nextGame = upcomingGames.first {
            let isHome = nextGame.homeTeamID == career.teamID
            let opponentID = isHome ? nextGame.awayTeamID : nextGame.homeTeamID
            opponentName = allTeamsByID[opponentID]?.fullName
        }

        currentTasks = TaskGenerator.generateTasks(
            for: phase,
            career: career,
            team: team,
            rosterCount: rosterCount,
            hasPendingTradeOffers: hasPendingTradeOffers,
            hasCoachingVacancies: hasCoachingVacancies,
            hasExpiringContracts: hasExpiringContracts,
            opponentName: opponentName,
            playoffRoundName: nil,  // TODO: derive from playoff bracket
            hasScoutsAssigned: hasScoutsAssigned,
            hasPendingEvents: hasPendingEvents,
            ownerSatisfaction: ownerSatisfaction
        )
    }

    // MARK: - Data Loading

    private func loadShellData() {
        guard let teamID = career.teamID else { return }

        let allTeamsDescriptor = FetchDescriptor<Team>()
        let allTeams = (try? modelContext.fetch(allTeamsDescriptor)) ?? []
        allTeamsByID = Dictionary(uniqueKeysWithValues: allTeams.map { ($0.id, $0) })

        team = allTeamsByID[teamID]

        let seasonYear = career.currentSeason
        let gameDescriptor = FetchDescriptor<Game>(predicate: #Predicate {
            $0.seasonYear == seasonYear
        })
        let allGames = (try? modelContext.fetch(gameDescriptor)) ?? []

        upcomingGames = allGames
            .filter { ($0.homeTeamID == teamID || $0.awayTeamID == teamID) && !$0.isPlayed && $0.week >= career.currentWeek }
            .sorted { $0.week < $1.week }

        // Generate tasks on initial load
        regenerateTasks(for: career.currentPhase)
    }
}

#Preview {
    CareerShellView(career: Career(
        playerName: "John Doe",
        role: .gm,
        capMode: .simple
    ))
    .modelContainer(for: Career.self, inMemory: true)
}
