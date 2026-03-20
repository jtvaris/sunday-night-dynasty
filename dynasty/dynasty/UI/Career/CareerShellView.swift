import SwiftUI
import SwiftData

/// Outer container that holds the persistent TopNavigationBar,
/// the main NavigationStack content area, and the CalendarSidebarView.
/// Now integrates with `TaskGenerator` to drive the guided wizard/task system.
struct CareerShellView: View {

    @Bindable var career: Career
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showCalendar = false
    @State private var showQuitConfirmation = false
    @State private var team: Team?
    @State private var upcomingGames: [Game] = []
    @State private var allTeamsByID: [UUID: Team] = [:]

    /// Navigation path for bookmark quick-nav.
    @State private var navigationPath = NavigationPath()

    /// The current list of tasks for the active phase, persisted across view
    /// updates. Regenerated when the phase changes.
    @State var currentTasks: [GameTask] = []

    /// Tracks the last phase we generated tasks for, so we can detect phase changes.
    @State private var lastGeneratedPhase: SeasonPhase?

    /// Accumulated inbox messages across all phase transitions.
    @State var inboxMessages: [InboxMessage] = []

    /// Pending weekly press conference questions (shown after advancing a regular-season week).
    @State private var pendingPressQuestions: [PressQuestion]?
    @State private var showWeeklyPressConference = false

    var body: some View {
        VStack(spacing: 0) {
            // Persistent top navigation bar
            TopNavigationBar(
                teamAbbreviation: team?.abbreviation ?? "???",
                teamName: team?.fullName ?? "No Team",
                pendingTaskCount: pendingTaskCount,
                onCalendarTapped: { showCalendar = true },
                onQuitTapped: { showQuitConfirmation = true },
                onBookmarkTapped: { destination in
                    handleBookmarkNavigation(destination)
                }
            )

            // Main content area (timeline is inside CareerDashboardView)
            NavigationStack(path: $navigationPath) {
                CareerDashboardView(
                    career: career,
                    tasks: $currentTasks,
                    inboxMessages: $inboxMessages,
                    onTaskSelected: { destination in
                        handleTaskNavigation(destination)
                    },
                    onAdvance: {
                        performShellAdvance()
                    }
                )
                    .onAppear {
                        // Refresh task completion when returning to the dashboard
                        // (e.g., after hiring coaches, signing players, etc.)
                        refreshTaskCompletionStatus()
                    }
                    .navigationDestination(for: ShellDestination.self) { dest in
                        destinationView(for: dest)
                    }
            }
        }
        .background(Color.backgroundPrimary)
        .navigationBarBackButtonHidden(true)
        .alert("Quit to Main Menu?", isPresented: $showQuitConfirmation) {
            Button("Quit", role: .destructive) {
                // Pop to root by dismissing
                if let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows.first {
                    window.rootViewController = UIHostingController(rootView:
                        ContentView()
                            .modelContainer(DataContainer.create())
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress is saved automatically.")
        }
        .task { loadShellData() }
        .onChange(of: navigationPath) { _, _ in
            refreshTaskCompletionStatus()
        }
        .onChange(of: career.currentPhase) { _, newPhase in
            regenerateTasks(for: newPhase)
            collectInboxMessages()
        }
        .onChange(of: career.currentWeek) { _, _ in
            collectInboxMessages()
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
                    performShellAdvance()
                },
                onDismiss: { showCalendar = false }
            )
            .presentationDetents([.large, .medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showWeeklyPressConference) {
            if let questions = pendingPressQuestions {
                WeeklyPressConferenceView(
                    questions: questions,
                    career: career,
                    onComplete: { result in
                        applyPressConferenceEffects(result)
                        showWeeklyPressConference = false
                    }
                )
            }
        }
    }

    // MARK: - Advance Week

    /// Performs the week/phase advance from the TimelineTasksPanel.
    private func performShellAdvance() {
        WeekAdvancer.advanceWeek(career: career, modelContext: modelContext)
        // Reload data so the dashboard picks up the new state
        loadShellData()

        // Check for pending press conference
        if let questions = WeekAdvancer.pendingPressConference {
            pendingPressQuestions = questions
            showWeeklyPressConference = true
            WeekAdvancer.pendingPressConference = nil
        }
    }

    // MARK: - Press Conference Effects

    /// Apply the effects from a weekly press conference result to career state.
    private func applyPressConferenceEffects(_ result: PressConferenceResult) {
        // Owner satisfaction (clamped 0-100, stored on Owner)
        if let ownerObj = team?.owner {
            ownerObj.satisfaction = min(100, max(0,
                ownerObj.satisfaction + result.totalEffects.ownerSatisfaction))
        }

        // Legacy points and media reputation (via LegacyTracker helper)
        career.legacy.applyPressConferenceResult(result, season: career.currentSeason)

        // Save changes
        try? modelContext.save()
    }

    // MARK: - Navigation Destinations

    enum ShellDestination: Hashable {
        case roster, schedule, standings, draft, scouting, cap
        case depthChart, gamePlan, coachingStaff, hireCoach
        case hireHC, hireOC, hireDC
        case prospectList, bigBoard, capOverview, freeAgency
        case contractTimeline, mentoring, trades, news
        case ownerMeeting, lockerRoom, inbox, rosterEvaluation
        case franchiseTag
    }

    @ViewBuilder
    private func destinationView(for destination: ShellDestination) -> some View {
        switch destination {
        case .roster:
            RosterViewWrapper(career: career)
                .onAppear {
                    markTaskVisited(for: .roster)
                    refreshTaskCompletionStatus()
                }
        case .schedule:
            ScheduleView(career: career)
                .onAppear {
                    markTaskVisited(for: .schedule)
                    refreshTaskCompletionStatus()
                }
        case .standings:
            StandingsView(career: career)
                .onAppear {
                    markTaskVisited(for: .standings)
                    refreshTaskCompletionStatus()
                }
        case .draft:
            DraftView(career: career)
                .onAppear {
                    markTaskVisited(for: .draft)
                    refreshTaskCompletionStatus()
                }
                .onDisappear {
                    refreshTaskCompletionStatus()
                }
        case .scouting:
            ScoutingHubView(career: career)
            .onAppear {
                markTaskVisited(for: .scouting)
                refreshTaskCompletionStatus()
            }
        case .cap, .capOverview:
            CapOverviewView(career: career)
                .onAppear {
                    markTaskVisited(for: .capOverview)
                    refreshTaskCompletionStatus()
                }
        case .depthChart:
            DepthChartView(career: career)
                .onAppear {
                    markTaskVisited(for: .depthChart)
                    refreshTaskCompletionStatus()
                }
        case .gamePlan:
            GamePlanView(gamePlan: .constant(.balanced))
                .onAppear {
                    markTaskVisited(for: .gamePlan)
                    refreshTaskCompletionStatus()
                }
        case .coachingStaff, .hireCoach:
            CoachingStaffView(career: career)
            .onAppear {
                markTaskVisited(for: .coachingStaff)
                markTaskVisited(for: .hireCoach)
                refreshTaskCompletionStatus()
            }
            .onDisappear {
                refreshTaskCompletionStatus()
            }
        case .hireHC:
            hireCoachDestination(role: .headCoach, taskDestination: .hireHC)
        case .hireOC:
            hireCoachDestination(role: .offensiveCoordinator, taskDestination: .hireOC)
        case .hireDC:
            hireCoachDestination(role: .defensiveCoordinator, taskDestination: .hireDC)
        case .prospectList:
            ScoutingHubView(career: career)
            .onAppear {
                markTaskVisited(for: .prospectList)
                refreshTaskCompletionStatus()
            }
        case .bigBoard:
            ScoutingHubView(career: career)
            .onAppear {
                markTaskVisited(for: .bigBoard)
                refreshTaskCompletionStatus()
            }
        case .freeAgency:
            FreeAgencyView(career: career)
                .onAppear {
                    markTaskVisited(for: .freeAgency)
                    refreshTaskCompletionStatus()
                }
        case .contractTimeline:
            ContractTimelineView(career: career)
                .onAppear {
                    markTaskVisited(for: .contractTimeline)
                    refreshTaskCompletionStatus()
                }
        case .mentoring:
            MentoringView(career: career)
                .onAppear {
                    markTaskVisited(for: .mentoring)
                    refreshTaskCompletionStatus()
                }
        case .trades:
            TradeView(career: career)
                .onAppear {
                    markTaskVisited(for: .trades)
                    refreshTaskCompletionStatus()
                }
        case .news:
            NewsView(career: career)
                .onAppear {
                    markTaskVisited(for: .news)
                    refreshTaskCompletionStatus()
                }
        case .ownerMeeting:
            OwnerMeetingView(career: career)
                .onAppear {
                    markTaskVisited(for: .ownerMeeting)
                    refreshTaskCompletionStatus()
                }
        case .lockerRoom:
            LockerRoomView(career: career)
                .onAppear {
                    markTaskVisited(for: .lockerRoom)
                    refreshTaskCompletionStatus()
                }
        case .inbox:
            InboxView(
                career: career,
                messages: $inboxMessages,
                onNavigate: { destination in
                    handleTaskNavigation(destination)
                }
            )
        case .rosterEvaluation:
            RosterEvaluationView(career: career)
                .onAppear {
                    markTaskVisited(for: .rosterEvaluation)
                    refreshTaskCompletionStatus()
                }
        case .franchiseTag:
            FranchiseTagView(career: career)
                .onAppear {
                    markTaskVisited(for: .franchiseTag)
                    refreshTaskCompletionStatus()
                }
        }
    }

    // MARK: - Hire Coach Destination Helper

    /// Creates a HireCoachView destination for a specific coaching role.
    @ViewBuilder
    private func hireCoachDestination(role: CoachRole, taskDestination: TaskDestination) -> some View {
        Group {
            if let teamID = career.teamID {
                let budget = team?.owner?.coachingBudget ?? 0
                let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
                let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
                let usedBudget = coaches.reduce(0) { $0 + $1.salary }
                HireCoachView(
                    role: role,
                    teamID: teamID,
                    remainingBudget: budget - usedBudget
                )
            } else {
                Text("No team selected")
            }
        }
        .onAppear {
            markTaskVisited(for: taskDestination)
            refreshTaskCompletionStatus()
        }
        .onDisappear {
            refreshTaskCompletionStatus()
        }
    }

    // MARK: - Task Navigation

    /// Maps a `TaskDestination` to a `ShellDestination` and navigates there.
    func handleTaskNavigation(_ destination: TaskDestination) {
        let shellDest: ShellDestination
        switch destination {
        case .roster:             shellDest = .roster
        case .depthChart:         shellDest = .depthChart
        case .gamePlan:           shellDest = .gamePlan
        case .schedule:           shellDest = .schedule
        case .standings:          shellDest = .standings
        case .coachingStaff:      shellDest = .coachingStaff
        case .hireCoach:          shellDest = .hireCoach
        case .hireHC:             shellDest = .hireHC
        case .hireOC:             shellDest = .hireOC
        case .hireDC:             shellDest = .hireDC
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
        case .inbox:              shellDest = .inbox
        case .rosterEvaluation:   shellDest = .rosterEvaluation
        case .franchiseTag:       shellDest = .franchiseTag
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

    // MARK: - Task Completion Refresh

    /// Checks actual game state against tasks and marks them done when the
    /// underlying condition is satisfied (e.g., coach hired, roster trimmed).
    ///
    /// IMPORTANT: Tasks should only auto-complete when a verifiable game-state
    /// condition is met (e.g., a coach was actually hired, the roster count
    /// dropped to 53). Merely visiting a screen should NOT auto-complete tasks.
    /// Phase transitions happen ONLY when the user taps the explicit "Advance"
    /// button, so we must not inflate task completion status here.
    func refreshTaskCompletionStatus() {
        guard let teamID = career.teamID else { return }

        // Ensure any pending inserts/updates are committed before querying
        try? modelContext.save()

        // Fetch current coaches
        let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
        let hasHC = coaches.contains { $0.role == .headCoach }
        let hasOC = coaches.contains { $0.role == .offensiveCoordinator }
        let hasDC = coaches.contains { $0.role == .defensiveCoordinator }

        // Fetch current roster
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        let players = (try? modelContext.fetch(playerDescriptor)) ?? []
        let rosterCount = players.count

        for index in currentTasks.indices {
            guard currentTasks[index].status != .done else { continue }
            let task = currentTasks[index]

            switch task.title {
            // Coaching Changes — verified by actual game state (coach exists)
            case "Hire Head Coach":
                if hasHC { currentTasks[index].status = .done }
            case "Hire Offensive Coordinator":
                if hasOC { currentTasks[index].status = .done }
            case "Hire Defensive Coordinator":
                if hasDC { currentTasks[index].status = .done }

            // Roster Cuts — verified by actual game state (roster count)
            case _ where task.title.contains("Finalize 53-man roster"):
                if rosterCount <= 53 { currentTasks[index].status = .done }

            // Review Roster tasks — check actual game state / user confirmations
            case "Review Position Group Grades":
                if UserDefaults.standard.bool(forKey: "rosterEvaluationConfirmed") {
                    currentTasks[index].status = .done
                }
            case "Analyze Contract Situations":
                if UserDefaults.standard.bool(forKey: "rosterEvaluationConfirmed") {
                    currentTasks[index].status = .done
                }
            case "Franchise Tag Decisions":
                // Complete if a franchise tag was applied OR the user confirmed evaluation
                let hasFranchiseTag = players.contains { $0.isFranchiseTagged }
                if hasFranchiseTag || UserDefaults.standard.bool(forKey: "franchiseTagVisited") {
                    currentTasks[index].status = .done
                }
            case "Check Salary Cap Outlook":
                // Auto-complete once visited — viewing cap data is the action
                if currentTasks[index].status == .inProgress {
                    currentTasks[index].status = .done
                }
            case "Set Roster Priorities":
                if let data = UserDefaults.standard.string(forKey: "rosterPriorities"),
                   !data.isEmpty, data != "{}" {
                    currentTasks[index].status = .done
                }

            // All other tasks: do NOT auto-complete based on visit status.
            // The user must explicitly tap "Advance" to progress the phase.
            // Visiting a screen only marks the task as .inProgress (via
            // markTaskVisited), which gives visual feedback without
            // triggering phase advancement.
            default:
                break
            }
        }
    }

    // MARK: - Bookmark Navigation

    private func handleBookmarkNavigation(_ bookmark: TopNavigationBar.BookmarkDestination) {
        let dest: ShellDestination
        switch bookmark {
        case .roster:        dest = .roster
        case .schedule:      dest = .schedule
        case .standings:     dest = .standings
        case .draft:         dest = .draft
        case .scouting:      dest = .scouting
        case .cap:           dest = .cap
        case .coachingStaff: dest = .coachingStaff
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

        let rosterCount: Int
        if let teamID = career.teamID {
            let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
            rosterCount = (try? modelContext.fetchCount(playerDescriptor)) ?? 53
        } else {
            rosterCount = 53
        }

        let hasPendingTradeOffers = false // TODO: wire up when TradeOffer model exists

        // Detect coaching vacancies
        var hasHC = true
        var hasOC = true
        var hasDC = true
        if let teamID = career.teamID {
            let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
            let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
            hasHC = coaches.contains { $0.role == .headCoach }
            hasOC = coaches.contains { $0.role == .offensiveCoordinator }
            hasDC = coaches.contains { $0.role == .defensiveCoordinator }
        }

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
            hasHeadCoach: hasHC,
            hasOC: hasOC,
            hasDC: hasDC,
            hasExpiringContracts: hasExpiringContracts,
            opponentName: opponentName,
            playoffRoundName: nil,  // TODO: derive from playoff bracket
            hasScoutsAssigned: hasScoutsAssigned,
            hasPendingEvents: hasPendingEvents,
            ownerSatisfaction: ownerSatisfaction
        )
    }

    // MARK: - Inbox Collection

    /// Appends any newly generated inbox messages from WeekAdvancer to the
    /// accumulated inbox. Called after each phase/week transition.
    func collectInboxMessages() {
        let newMessages = WeekAdvancer.lastInboxMessages
        guard !newMessages.isEmpty else { return }
        inboxMessages.append(contentsOf: newMessages)
        // Clear so we don't double-add on next read
        WeekAdvancer.lastInboxMessages = []
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

        // Generate initial inbox messages if empty (first time entering dashboard)
        if inboxMessages.isEmpty, let playerTeam = team {
            let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
            let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
            let messages = InboxEngine.generatePhaseMessages(
                phase: career.currentPhase,
                career: career,
                team: playerTeam,
                coaches: coaches,
                owner: playerTeam.owner
            )
            inboxMessages = messages
        }
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
