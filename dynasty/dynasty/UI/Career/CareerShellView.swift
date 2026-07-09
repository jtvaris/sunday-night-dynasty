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

    /// Camp Phase 1 wire-up: surface the VoluntaryWorkoutPrompt sheet when the
    /// player advances into an OTAs / Training Camp week.
    @State private var pendingVoluntaryWorkout: Bool = false

    // FA Drama Phase 5 — Holdout dialog state.
    @State private var pendingHoldout: Holdout?
    @State private var pendingHoldoutPlayer: Player?
    @State private var pendingHoldoutMarketValue: Int = 0

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
        .sheet(isPresented: $pendingVoluntaryWorkout) {
            VoluntaryWorkoutPrompt(career: career)
        }
        .sheet(item: $pendingHoldout) { holdout in
            if let player = pendingHoldoutPlayer {
                HoldoutDialog(
                    holdout: holdout,
                    playerName: player.fullName,
                    position: player.position.rawValue,
                    currentSalary: player.annualSalary,
                    marketValue: pendingHoldoutMarketValue,
                    onResolve: { resolution in
                        HoldoutEngine.resolveHoldout(
                            holdout: holdout,
                            resolution: resolution,
                            modelContext: modelContext
                        )
                        // After resolution, persist a storyline event for the inbox.
                        if let teamID = career.teamID {
                            let evt = FAStorylineEvent(
                                seasonYear: career.currentSeason,
                                type: .holdout,
                                playerID: player.id,
                                teamID: teamID,
                                headline: "\(player.fullName) holdout resolved",
                                body: "Front office took the \(resolutionLabel(resolution)) path."
                            )
                            modelContext.insert(evt)
                            try? modelContext.save()
                        }
                    }
                )
            }
        }
    }

    // MARK: - Holdout Helpers

    private func resolutionLabel(_ resolution: HoldoutEngine.Resolution) -> String {
        switch resolution {
        case .extend:        return "extension"
        case .signingBonus:  return "signing-bonus"
        case .forceTrade:    return "trade"
        case .mediation:     return "mediation"
        }
    }

    /// FA Drama Phase 5: scan the user's roster at training-camp entry for any
    /// sub-market players and pop the HoldoutDialog for the first candidate.
    /// Only triggers once per training-camp transition.
    @MainActor
    private func detectAndShowHoldout() {
        guard let teamID = career.teamID else { return }
        let roster = teamRoster
        guard !roster.isEmpty else { return }

        // Build per-player market value map.
        var marketValues: [UUID: Int] = [:]
        for p in roster {
            marketValues[p.id] = ContractEngine.estimateMarketValue(player: p)
        }
        let candidates = HoldoutEngine.detectHoldoutCandidates(roster: roster, marketValues: marketValues)
        guard let first = candidates.first else { return }
        let market = marketValues[first.id] ?? first.annualSalary
        let delta = max(0, market - first.annualSalary)
        if let holdout = HoldoutEngine.startHoldout(
            player: first,
            teamID: teamID,
            subMarketDelta: delta,
            modelContext: modelContext
        ) {
            pendingHoldoutPlayer = first
            pendingHoldoutMarketValue = market
            pendingHoldout = holdout
        }
    }

    // MARK: - Advance Week

    /// Performs the week/phase advance from the TimelineTasksPanel.
    private func performShellAdvance() {
        WeekAdvancer.advanceWeek(career: career, modelContext: modelContext)
        // WeekAdvancer never saves (caller's responsibility) — persist the
        // phase/week change immediately so a force-quit can't lose it.
        try? modelContext.save()
        // Reload data so the dashboard picks up the new state
        loadShellData()

        // Check for pending press conference
        if let questions = WeekAdvancer.pendingPressConference {
            pendingPressQuestions = questions
            showWeeklyPressConference = true
            WeekAdvancer.pendingPressConference = nil
        }

        // Camp Phase 1 wire-up: surface the per-week voluntary workout prompt
        // whenever the player has just stepped into an OTAs or Training Camp
        // week. The prompt itself persists the chosen workout flavor; engine
        // application is handled by VoluntaryWorkoutEngine on next tick.
        if career.currentPhase == .otas || career.currentPhase == .trainingCamp {
            pendingVoluntaryWorkout = true
        }

        // FA Drama Phase 5: at training-camp entry, scan for holdout candidates
        // (players signed sub-market) and surface a HoldoutDialog if any are
        // found. Limited to one candidate per camp opening to avoid stacking.
        if career.currentPhase == .trainingCamp && pendingHoldout == nil {
            detectAndShowHoldout()
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
        // Camp destinations
        case trainingPlan, workloadDashboard, rosterCuts, gameWeekPrep
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
            DraftDayView(career: career)
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
                .onDisappear {
                    refreshTaskCompletionStatus()
                }
        case .gamePlan:
            GamePlanView(gamePlan: gamePlanBinding, context: gamePlanContext)
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
            Group {
                switch FreeAgencyStep(rawValue: career.freeAgencyStep) {
                case .finalPush:
                    FinalPushView(career: career)
                case .newLeagueYear:
                    NewLeagueYearView(career: career)
                case .capReview:
                    CapComplianceView(career: career)
                case .signing:
                    FAWeeklyView(career: career)
                case .complete:
                    FACompleteView(career: career)
                default:
                    FinalPushView(career: career)
                }
            }
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
        case .trainingPlan:
            TrainingPlanView(career: career, roster: teamRoster)
                .onAppear {
                    markTaskVisited(for: .trainingPlan)
                    refreshTaskCompletionStatus()
                }
                .onDisappear {
                    refreshTaskCompletionStatus()
                }
        case .workloadDashboard:
            WorkloadDashboard(roster: teamRoster)
        case .rosterCuts:
            RosterCutView(career: career, roster: teamRoster)
        case .gameWeekPrep:
            GameWeekPrepPicker(
                career: career,
                consecutiveOpponentWeeks: consecutiveOpponentPrepWeeks
            )
        }
    }

    // MARK: - Game Plan Helpers

    /// Live binding between the Game Plan screen and the persisted career.
    /// Every slider drag / preset tap encodes to `career.gamePlanData`, saves
    /// the model context, and completes any "Set game plan…" task.
    private var gamePlanBinding: Binding<GamePlan> {
        Binding(
            get: { career.gamePlan },
            set: { newValue in
                career.gamePlan = newValue
                try? modelContext.save()
                markTaskCompleted(for: .gamePlan)
            }
        )
    }

    /// Situational context (week, opponent, OC scheme) for the Game Plan header
    /// and scouting panel. All fields degrade gracefully to nil.
    private var gamePlanContext: GamePlanView.Context {
        var ctx = GamePlanView.Context()

        // Week / playoff-round label — only meaningful in-season. Uses the
        // NEXT unplayed game's week so the label matches the opponent shown
        // (after this week's game is played, the plan targets next week).
        switch career.currentPhase {
        case .regularSeason:
            let week = upcomingGames.first?.week ?? career.currentWeek
            ctx.weekLabel = "Week \(week)"
        case .playoffs:
            ctx.weekLabel = playoffRoundName
        default:
            ctx.weekLabel = nil
        }

        // OC's offensive scheme badge.
        if let teamID = career.teamID {
            let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
            let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
            ctx.schemeName = coaches
                .first { $0.role == .offensiveCoordinator }?
                .offensiveScheme?.displayName
        }

        // Opponent panel — next unplayed game for the user's team.
        if let teamID = career.teamID, let nextGame = upcomingGames.first {
            let opponentID = nextGame.homeTeamID == teamID ? nextGame.awayTeamID : nextGame.homeTeamID
            if let opponent = allTeamsByID[opponentID] {
                ctx.opponentName = opponent.fullName
                ctx.opponentRecord = opponent.record
                ctx.passDefense = Self.defenseStrength(of: opponent, positions: [.CB, .FS, .SS])
                ctx.runDefense = Self.defenseStrength(of: opponent, positions: [.DE, .DT, .MLB, .OLB])
            }
        }

        return ctx
    }

    /// Buckets a defensive unit's average overall into weak / average / strong.
    private static func defenseStrength(
        of team: Team,
        positions: Set<Position>
    ) -> GamePlanView.DefenseStrength? {
        let unit = team.players.filter { positions.contains($0.position) }
        guard !unit.isEmpty else { return nil }
        let average = unit.reduce(0) { $0 + $1.overall } / unit.count
        switch average {
        case 78...:   return .strong
        case 70..<78: return .average
        default:      return .weak
        }
    }

    // MARK: - Camp Helpers

    /// Fetches the user's current roster (used by Camp views as a parameter).
    /// Returns an empty array when no team is assigned.
    private var teamRoster: [Player] {
        guard let teamID = career.teamID else { return [] }
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate<Player> { $0.teamID == teamID })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Counts how many consecutive prior weeks the user spent at >=70%
    /// opponent-specific prep — drives the GameWeekPrepPicker drift warning.
    private var consecutiveOpponentPrepWeeks: Int {
        guard let teamID = career.teamID else { return 0 }
        let season = career.currentSeason
        let descriptor = FetchDescriptor<OpponentPrepWeek>(
            predicate: #Predicate<OpponentPrepWeek> {
                $0.teamID == teamID && $0.seasonYear == season
            }
        )
        let prep = (try? modelContext.fetch(descriptor)) ?? []
        let sorted = prep.sorted { $0.weekNumber > $1.weekNumber }
        var streak = 0
        for week in sorted {
            if week.opponentPct >= 70 { streak += 1 } else { break }
        }
        return streak
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
                    remainingBudget: budget - usedBudget,
                    teamBudget: budget,
                    teamWins: team?.wins ?? 8,
                    teamReputation: career.reputation
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
        case .hireCoach:          shellDest = .coachingStaff
        case .hireHC:             shellDest = .coachingStaff
        case .hireOC:             shellDest = .coachingStaff
        case .hireDC:             shellDest = .coachingStaff
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
        case .interviewReport:
            // Hint to ScoutingHubView to auto-select the Interviews tab so the
            // saved interview report is visible immediately.
            UserDefaults.standard.set("interviews", forKey: "scoutingPendingTab")
            shellDest = .scouting
        case .personalWorkouts:   shellDest = .scouting
        case .trainingPlan:        shellDest = .trainingPlan
        case .workloadDashboard:   shellDest = .workloadDashboard
        case .rosterCuts:          shellDest = .rosterCuts
        case .gameWeekPrep:        shellDest = .gameWeekPrep
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

            // Combine — sequential task unlocking
            case "Send scouts to Combine":
                if UserDefaults.standard.bool(forKey: "scoutsSentToCombine") {
                    currentTasks[index].status = .done
                }

            case "Review Combine results":
                // Locked until scouts sent
                let scoutsSent = UserDefaults.standard.bool(forKey: "scoutsSentToCombine")
                if !scoutsSent {
                    currentTasks[index].status = .todo
                } else if UserDefaults.standard.bool(forKey: "combineResultsReviewed") {
                    // User visited the Combine tab after scouts were sent
                    currentTasks[index].status = .done
                }

            case "Conduct prospect interviews":
                // Locked until combine results reviewed
                let resultsReviewed = currentTasks.first(where: { $0.title == "Review Combine results" })?.status == .done
                if !resultsReviewed {
                    currentTasks[index].status = .todo
                } else if career.interviewsUsed > 0 {
                    // Player has conducted at least one interview
                    currentTasks[index].status = .done
                }

            case "Review interview report":
                // Locked until interviews conducted
                let interviewsDone = currentTasks.first(where: { $0.title == "Conduct prospect interviews" })?.status == .done
                if !interviewsDone {
                    currentTasks[index].status = .todo
                } else if UserDefaults.standard.bool(forKey: "interviewReportReviewed") {
                    // User opened/closed the InterviewReportView → report reviewed
                    currentTasks[index].status = .done
                } else if career.interviewsUsed >= 60 {
                    // Backstop for stuck saves: all 60 interviews used means the
                    // post-interview report was shown automatically; treat as reviewed.
                    UserDefaults.standard.set(true, forKey: "interviewReportReviewed")
                    currentTasks[index].status = .done
                }

            // OTAs — verified by actual persisted game state
            case "Set depth chart":
                // Done once the user has saved a chart (edit or Auto-Set).
                // Deliberately does NOT require every slot filled — a roster
                // hole (e.g. no kicker) must never make the task impossible.
                if career.depthChartData != nil {
                    currentTasks[index].status = .done
                }

            // Game plan — done once the user has saved a plan at least once
            // (sliders or preset). Weekly "Set game plan for <opponent>" tasks
            // are completed in-session via markTaskCompleted(.gamePlan).
            case "Set game plan":
                if career.gamePlanData != nil {
                    currentTasks[index].status = .done
                }

            case "Set training focus":
                // Done once a TrainingPlan row exists for the current
                // (team, season, week, phase) key — i.e. the user hit Save.
                let season = career.currentSeason
                let week = career.currentWeek
                let phaseRaw = career.currentPhase.rawValue
                let planDescriptor = FetchDescriptor<TrainingPlan>(
                    predicate: #Predicate {
                        $0.teamID == teamID
                            && $0.seasonYear == season
                            && $0.weekNumber == week
                            && $0.phaseRaw == phaseRaw
                    }
                )
                if let count = try? modelContext.fetchCount(planDescriptor), count > 0 {
                    currentTasks[index].status = .done
                }

            // Draft — done when this season's draftees are on the roster
            case "Enter the Draft":
                if players.contains(where: { $0.draftPickNumber != nil && $0.yearsPro == 0 }) {
                    currentTasks[index].status = .done
                }

            // Pro Days — completion checks
            case "Assign scouts to Pro Days":
                // Done if at least 1 pro day has been attended
                let proDesc = FetchDescriptor<CollegeProspect>(
                    predicate: #Predicate { $0.proDayCompleted == true }
                )
                if let count = try? modelContext.fetch(proDesc).count, count > 0 {
                    currentTasks[index].status = .done
                }

            case "Review Pro Day results":
                // Done if visited scouting after pro days attended
                if currentTasks[index].status == .inProgress {
                    currentTasks[index].status = .done
                }

            // Free Agency — sequential task unlocking based on career.freeAgencyStep
            case "Final Push \u{2014} Re-sign or let walk":
                let step = FreeAgencyStep(rawValue: career.freeAgencyStep)
                if step != .finalPush {
                    currentTasks[index].status = .done
                }

            case "Start New League Year":
                let step = FreeAgencyStep(rawValue: career.freeAgencyStep)
                if step == .finalPush {
                    // Locked — Final Push not done yet
                    currentTasks[index].status = .todo
                } else if step != .newLeagueYear {
                    currentTasks[index].status = .done
                }

            case "Roster & Cap compliance":
                let step = FreeAgencyStep(rawValue: career.freeAgencyStep)
                if step == .finalPush || step == .newLeagueYear {
                    // Locked — previous steps not done
                    currentTasks[index].status = .todo
                } else if step != .capReview {
                    currentTasks[index].status = .done
                }

            case "Free agency signings":
                let step = FreeAgencyStep(rawValue: career.freeAgencyStep)
                if step == .finalPush || step == .newLeagueYear || step == .capReview {
                    // Locked — must complete cap review first
                    currentTasks[index].status = .todo
                } else if step == .complete {
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

    /// Derive the current playoff round name from the career week.
    /// Week mapping: 19 = Wild Card, 20 = Divisional, 21 = Conference Championships.
    private var playoffRoundName: String? {
        guard career.currentPhase == .playoffs else { return nil }
        switch career.currentWeek {
        case 19: return "Wild Card"
        case 20: return "Divisional Round"
        case 21: return "Conference Championships"
        default: return nil
        }
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

        // TODO: Wire up when TradeOffer state is persisted on Career or Team.
        // TradeEngine.generateAITradeOffers() creates offers but they aren't stored
        // in a persistent collection yet. When added, check for offers where
        // receivingTeamID == career.teamID && isAccepted == nil.
        let hasPendingTradeOffers = false

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

        // Check roster for players with 1 year or less remaining on contract
        let hasExpiringContracts: Bool = {
            guard let teamID = career.teamID else { return false }
            let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
            let players = (try? modelContext.fetch(playerDescriptor)) ?? []
            return players.contains { $0.contractYearsRemaining <= 1 }
        }()

        // Check if any scouts are assigned to the team
        let hasScoutsAssigned: Bool = {
            guard let teamID = career.teamID else { return false }
            let scoutDescriptor = FetchDescriptor<Scout>(predicate: #Predicate { $0.teamID == teamID })
            let count = (try? modelContext.fetchCount(scoutDescriptor)) ?? 0
            return count > 0
        }()
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
            playoffRoundName: playoffRoundName,
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

        // One-time data integrity pass: bring legacy `scoutGrade` and the new
        // `scoutedOverallGrade` into agreement on existing saves so every list
        // shows the same letter for the same prospect.
        syncProspectGrades()

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

        // Generate tasks on initial load, then re-derive completion from
        // persisted game state so a relaunch doesn't reset finished tasks.
        regenerateTasks(for: career.currentPhase)
        refreshTaskCompletionStatus()

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

    /// Reconciles the legacy `scoutGrade` letter with the modern `scoutedOverallGrade`
    /// range, and back-fills `scoutedOverallGrade` from `scoutedOverall` when missing.
    /// Idempotent — safe to call on every load.
    private func syncProspectGrades() {
        let prospects = (try? modelContext.fetch(FetchDescriptor<CollegeProspect>())) ?? []
        var changed = 0

        for prospect in prospects {
            // 1. If the modern range is missing but a numeric/legacy grade exists,
            //    seed it so all readers converge on the same letter.
            if prospect.scoutedOverallGrade == nil {
                if let ovr = prospect.scoutedOverall {
                    let lg = LetterGrade.from(numericValue: ovr)
                    prospect.scoutedOverallGrade = GradeRange(grade: lg)
                    changed += 1
                } else if let raw = prospect.scoutGrade, let lg = LetterGrade(rawValue: raw) {
                    prospect.scoutedOverallGrade = GradeRange(grade: lg)
                    changed += 1
                }
            }

            // 2. Pin the legacy `scoutGrade` to the range's mid-grade so any
            //    older code path that still reads `scoutGrade` agrees with the UI.
            if let range = prospect.scoutedOverallGrade {
                let canonical = range.midGrade.rawValue
                if prospect.scoutGrade != canonical {
                    prospect.scoutGrade = canonical
                    changed += 1
                }
            }
        }

        if changed > 0 {
            try? modelContext.save()
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
