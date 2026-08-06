import SwiftUI
import SwiftData

struct CareerDashboardView: View {

    @Bindable var career: Career
    @Binding var tasks: [GameTask]
    @Binding var inboxMessages: [InboxMessage]
    var onTaskSelected: (TaskDestination) -> Void
    var onAdvance: (() -> Void)? = nil
    /// #37: flipped true by the Game Plan screen's "Start Game" button after it
    /// pops back to the dashboard, so the coached game launches from here (the
    /// owner of `coachedSession` / the fullScreenCover). Reset on consumption.
    var launchCoachedGame: Binding<Bool> = .constant(false)
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
    /// Combined overspend across the coaching, medical and scouting pots —
    /// what the `.coachingChanges` advance gate actually blocks on.
    @State private var staffPotOverage: Int = 0
    @State private var expiringContractPlayers: [Player] = []
    @State private var positionGroupGrades: [(group: String, starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int)] = []
    @State private var teamMorale: Int = 70
    /// Team chemistry 0-100 straight from `LockerRoomEngine` — the SAME number
    /// the Locker Room screen shows. The dashboard tile used to label its
    /// chemistry row with `moraleLabel(teamMorale)`, so a 100/100 "Elite" locker
    /// room read as "Good" here.
    @State private var teamChemistry: Int = 50
    @State private var previousSeasonRecord: String?
    @State private var previousSeasonYear: Int?

    // MARK: Sheets

    /// **The one sheet this screen can have open.**
    ///
    /// This view used to carry THREE `.sheet(isPresented:)` modifiers plus a
    /// `.sheet(item:)` on a single modifier chain — game summary, injury
    /// report, position battle, coaching-staff review. SwiftUI honours exactly
    /// one sheet per view: the last modifier on the chain wins, so a button
    /// that flips an earlier flag gets the LAST builder presented, that
    /// builder's `if let` finds nothing, and the user is handed an empty card.
    /// That is bug B1 from `ProDayTourView` verbatim (`ActiveSheet` there is
    /// the same shape, for the same reason). One `.sheet(item:)` over one enum
    /// makes the case unrepresentable.
    private enum ActiveSheet: Identifiable {
        /// Box score after a week advance or a coached game.
        case gameSummary
        /// Medical report — the Injuries quick chip and the Injuries tile.
        case injuryReport
        /// Camp position battle detail.
        case positionBattle(PositionBattle)
        /// Confirmation step before the `.coachingChanges` phase advance.
        case coachingStaffReview

        var id: String {
            switch self {
            case .gameSummary:                return "gameSummary"
            case .injuryReport:               return "injuryReport"
            case let .positionBattle(battle): return "battle:\(battle.id.uuidString)"
            case .coachingStaffReview:        return "coachingStaffReview"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

    /// Game summary payload, resolved before `activeSheet` is set.
    @State private var lastGameResult: GameSimulator.GameResult?
    @State private var lastHomeTeam: Team?

    // MARK: Coached game (live play-calling)

    /// Everything the live match needs, resolved before presentation.
    /// Passed via `fullScreenCover(item:)` so the cover content never sees
    /// stale state from the same transaction that presented it.
    struct CoachedGameSession: Identifiable {
        let id = UUID()
        let game: Game
        let homeTeam: Team
        let awayTeam: Team
        let homeCoaches: [Coach]
        let awayCoaches: [Coach]
        let playerTeamIsHome: Bool
        let audibleBoost: Double
        let defReadBoost: Double
    }

    @State private var coachedSession: CoachedGameSession?
    @State private var lastAwayTeam: Team?
    /// Weather of the player's most recently finished game (quick-simmed or
    /// coached) — shown as a chip in the game summary header.
    @State private var lastGameWeather: GameWeather?

    /// Inbox filter for the messages panel
    @State private var inboxFilter: DashboardInboxFilter = .all

    /// Pulsing animation state for advance button guidance
    @State private var advancePulse = false

    @State private var allCoaches: [Coach] = []
    /// The club's scouting department. Loaded by `refreshStaffTile` (which
    /// already fetches it for the staff budget) and read by the Path to the
    /// Draft hero card, whose `DraftPrepProgress` counts pro-day focus slots
    /// off `scout.proDayColleges` / `scout.maxProDays`.
    @State private var scouts: [Scout] = []

    /// The Path to the Draft card's two inputs, cached per LOAD rather than per
    /// body pass (#fleet review F8).
    ///
    /// Both used to be computed properties, and both walk the whole draft class
    /// — ~350 prospects — on every read: `DraftPrepProgress`'s init counts the
    /// combine, and the scouted share filters on `scoutingReports`, which is a
    /// Codable blob that DECODES on every `get`. SwiftUI re-evaluates a
    /// dashboard body on any state change on the screen, so a card in the
    /// corner was paying two full class walks for a tapped tile.
    ///
    /// `refreshDraftPrepCache()` is the one writer, and it hangs off
    /// `refreshStaffTile()` — which both `loadAllDataBody` and the pop-back
    /// `.onAppear` already call, so the card still re-reads after a trip into
    /// the scouting hub.
    @State private var prepProgress: DraftPrepProgress?
    @State private var draftClassScoutedPercent: Int = 0
    /// The draft-phase hero's live read of the board. Same cache contract as
    /// `prepProgress` above: it walks the class and the pick order, so it is
    /// built by `refreshDraftPrepCache()` rather than on every body pass.
    @State private var draftHero: DraftHeroState?

    /// Tracks which Position-Grades letter is currently showing its explainer popover.
    /// Encoded as "<group>:S" or "<group>:D" (e.g. "QB:S" for QB starter grade).
    @State private var positionGradePopoverID: String?

    /// Guard rail for the "Advance skips the game" trap: raised when the user
    /// taps Advance while their own game for this week is still unplayed.
    @State private var showSkipGameConfirm = false

    /// Unresolved camp position battles involving the user's roster. Real rows
    /// from `PositionBattleTracker` — the tile used to hard-code "0 active".
    @State private var openPositionBattles: [PositionBattle] = []

    /// #106: false until the first appear. `.task` owns the opening load; every
    /// later appear (popping back from staff, cap, scouting…) reloads instead,
    /// so no tile is left showing numbers a pushed screen already changed.
    @State private var hasAppearedOnce: Bool = false

    /// Camp Phase 1 wire-up: latest Hard Knocks event surfaced as a bottom toast.
    @State private var latestHardKnocksEvent: HardKnocksEvent?
    /// Tracks which Hard Knocks event IDs have already been displayed so the
    /// same event isn't re-shown when the dashboard re-appears.
    @State private var shownHardKnocksEventIDs: Set<UUID> = []

    /// R19: What's riding on this week's game ("Win clinches the NFC North"),
    /// computed conservatively from the standings in `loadAllData`. nil when
    /// no claim is provably true — no line beats a wrong line.
    @State private var seasonStakes: SeasonStakes?

    /// A single late-season stakes statement for the hero card.
    struct SeasonStakes {
        let text: String
        /// Urgent stakes (elimination on the line) render in red.
        let urgent: Bool
    }

    /// R37: step index of the one-time dashboard tour overlay (nil = hidden).
    /// Shown on the very first dashboard open; "Got it"/Skip flips the
    /// UserDefaults flag so it never returns (Settings → Reset Tips does).
    @State private var dashboardTourStep: Int? = nil

    /// R37: the four dashboard tour cards — weekly flow, game plan, inbox, tiles.
    private static let dashboardTourSteps: [CoachMarkStep] = [
        CoachMarkStep(
            icon: "checklist",
            title: "Your week lives on the left",
            text: "The tasks panel lists everything this week needs from you. Finish the required tasks, then press Advance Week at the bottom of the panel to move the season forward."
        ),
        CoachMarkStep(
            icon: "list.clipboard.fill",
            title: "Set your game plan",
            text: "During the season, the \u{201C}Set game plan\u{201D} task opens your weekly plan: run/pass lean, tempo, and matchup answers for Sunday. A good plan gives your play-caller better options."
        ),
        CoachMarkStep(
            icon: "envelope.fill",
            title: "Watch your inbox",
            text: "The messages panel collects word from the owner, your staff, and the press. Filters at the top narrow it down — owner mail is worth reading before you advance."
        ),
        CoachMarkStep(
            icon: "square.grid.2x2.fill",
            title: "Tiles are shortcuts",
            text: "The dashboard tiles jump straight to your roster, salary cap, scouting, staff, and more. Standings and the schedule live on the right. That's the tour — good luck, coach."
        )
    ]

    // MARK: - Derived

    /// Staff budget overage in thousands, summed across all three pots
    /// (coaching, medical, scouting) — the same three the staff screen's own
    /// overspend banner checks. Returns 0 when every pot is within budget.
    /// Only relevant during the `.coachingChanges` phase.
    private var coachingOverage: Int {
        guard coachingBudgetTotal > 0 else { return 0 }
        return staffPotOverage
    }

    /// True when the user is in coachingChanges phase and has overspent the
    /// staff budget. Blocks advancement until staff are released or salaries
    /// reduced. (#54)
    private var isBlockedByCoachingBudget: Bool {
        career.currentPhase == .coachingChanges && coachingOverage > 0
    }

    private var canAdvance: Bool {
        guard TaskGenerator.allRequiredComplete(in: tasks) else { return false }
        if isBlockedByCoachingBudget { return false }
        return true
    }

    /// Topmost incomplete required task (mirrors TimelineTasksPanel.nextActionableTask).
    /// Used to surface a Next Action hero banner above the dashboard tiles.
    private var nextActionTask: GameTask? {
        tasks.first { task in
            task.isRequired && task.status != .done && !isHeroTaskLocked(task)
        }
    }

    /// Mirror of TimelineTasksPanel.isTaskLocked for hero-banner gating.
    private func isHeroTaskLocked(_ task: GameTask) -> Bool {
        guard task.status == .todo, task.isRequired else { return false }
        let combineChain = TaskGenerator.combineChain
        if let taskIdx = combineChain.firstIndex(of: task.matchKey), taskIdx > 0 {
            let prereqTitle = combineChain[taskIdx - 1]
            if let prereq = tasks.first(where: { $0.matchKey == prereqTitle }), prereq.status != .done {
                return true
            }
        }
        return false
    }

    /// True while the user's own game for this week is still on the board.
    /// Same fixture the hero card offers to coach (`currentWeekPlayerGame`).
    private var weeklyGameUnplayed: Bool { currentWeekPlayerGame != nil }

    /// Opponent abbreviation of that unplayed game, for confirmation copy.
    private var unplayedGameOpponentAbbr: String? {
        guard let game = currentWeekPlayerGame, let teamID = career.teamID else { return nil }
        let opponentID = game.homeTeamID == teamID ? game.awayTeamID : game.homeTeamID
        return allTeamsByID[opponentID]?.abbreviation
    }

    /// Optional tasks still open this week. The "All tasks complete!" banner
    /// used to claim victory over a list with four unchecked optional rows.
    private var openOptionalTaskCount: Int {
        TimelineTasksPanel.actionableTasks(tasks)
            .filter { !$0.isRequired && $0.status != .done }
            .count
    }

    /// What the pre-advance banner is honestly allowed to say.
    private enum AdvanceReadiness {
        case gameUnplayed
        case optionalOpen(Int)
        case ready
    }

    private var advanceReadiness: AdvanceReadiness {
        if weeklyGameUnplayed { return .gameUnplayed }
        let open = openOptionalTaskCount
        return open > 0 ? .optionalOpen(open) : .ready
    }

    /// Advance owns the screen's single gold CTA only once this week's game is
    /// resolved (coached or simmed).
    private var advanceIsPrimaryCTA: Bool { canAdvance && !weeklyGameUnplayed }

    private var skipGameConfirmTitle: String {
        let opponent = unplayedGameOpponentAbbr.map { " vs \($0)" } ?? ""
        return "Skip your Week \(career.currentWeek) game\(opponent)? It will be simulated."
    }

    /// Use horizontalSizeClass instead of GeometryReader for layout switching.

    // MARK: - Advance Logic

    private func performAdvance() {
        guard canAdvance else { return }

        // The user's own game is still unplayed: never let one tap eat it
        // silently. Confirm, then `runAdvance` sims it as part of the week.
        if weeklyGameUnplayed {
            showSkipGameConfirm = true
            return
        }

        runAdvance()
    }

    /// The actual week advance, past the unplayed-game guard rail.
    private func runAdvance() {
        guard canAdvance else { return }

        // During coaching changes, show the review sheet instead of advancing
        // directly. Guarded: a second tap while the sheet is already up used to
        // present another copy on top of it, and the user then had to dismiss a
        // stack of identical sheets before anything could happen.
        if career.currentPhase == .coachingChanges {
            if case .coachingStaffReview = activeSheet { return }
            loadCoaches()
            activeSheet = .coachingStaffReview
            return
        }

        if let onAdvance {
            onAdvance()
        } else {
            let teamsByID = fetchTeamsByID()
            // Capture the player's game BEFORE the advance plays it, so the
            // summary can show the same deterministic weather the sim used.
            let playedGame = currentWeekPlayerGame
            PerfLog.time("advance_week") {
                WeekAdvancer.advanceWeek(career: career, modelContext: modelContext)
            }
            if let result = WeekAdvancer.lastPlayerGameResult,
               let home = teamsByID[result.boxScore.home.teamID],
               let away = teamsByID[result.boxScore.away.teamID] {
                lastGameResult = result
                lastHomeTeam = home
                lastAwayTeam = away
                lastGameWeather = playedGame.map { GameWeather.forGame(id: $0.id, week: $0.week, homeTeamAbbreviation: teamsByID[$0.homeTeamID]?.abbreviation) }
                activeSheet = .gameSummary
            }
            loadAllData()
        }
    }

    // MARK: - Coached Game Launch / Finish

    /// The player's own game for the current week, if it hasn't been played yet.
    private var currentWeekPlayerGame: Game? {
        upcomingGames.first { $0.week == career.currentWeek && !$0.isPlayed }
    }

    /// Gathers teams, staffs and prep boosts, then presents the live match.
    private func startCoachedGame() {
        PerfLog.mark("coached_scene")   // R39 (c): Coach the Game tap
        guard let teamID = career.teamID,
              let playerTeam = allTeamsByID[teamID],
              let game = currentWeekPlayerGame else { return }

        let opponentID = game.homeTeamID == teamID ? game.awayTeamID : game.homeTeamID
        guard let opponent = allTeamsByID[opponentID] else { return }

        let cid = career.id
        let coachDescriptor = FetchDescriptor<Coach>(
            predicate: #Predicate { $0.careerID == cid }
        )
        let leagueCoaches = (try? modelContext.fetch(coachDescriptor)) ?? []

        // Same opponent-prep boost the quick sim applies (WeekAdvancer parity).
        let season = career.currentSeason
        let week = career.currentWeek
        let prepDescriptor = FetchDescriptor<OpponentPrepWeek>(
            predicate: #Predicate {
                $0.seasonYear == season && $0.weekNumber == week && $0.teamID == teamID
            }
        )
        var audible = 0.0
        var defRead = 0.0
        if let prep = (try? modelContext.fetch(prepDescriptor))?.first {
            let boost = OpponentPrepEngine.gameBoost(prep: prep)
            audible = boost.audibleBoost
            defRead = boost.defensiveReadBoost
        }

        let playerIsHome = game.homeTeamID == teamID

        // Hand the user's saved game plan to the live engine (consumed in
        // LiveGameEngine.init). nil when the user has never set a plan —
        // preserving today's exact AI behavior.
        LiveGameEngine.pendingPlayerGamePlan = career.savedGamePlan

        coachedSession = CoachedGameSession(
            game: game,
            homeTeam: playerIsHome ? playerTeam : opponent,
            awayTeam: playerIsHome ? opponent : playerTeam,
            homeCoaches: leagueCoaches.filter { $0.teamID == game.homeTeamID },
            awayCoaches: leagueCoaches.filter { $0.teamID == game.awayTeamID },
            playerTeamIsHome: playerIsHome,
            audibleBoost: audible,
            defReadBoost: defRead
        )
    }

    /// Persists the coached result and hands off to the standard summary sheet.
    private func finishCoachedGame(engine: LiveGameEngine, game: Game) {
        engine.persist(to: game, context: modelContext, teamsByID: allTeamsByID)

        lastGameResult = WeekAdvancer.lastPlayerGameResult
        lastHomeTeam = allTeamsByID[game.homeTeamID]
        lastAwayTeam = allTeamsByID[game.awayTeamID]
        lastGameWeather = GameWeather.forGame(id: game.id, week: game.week, homeTeamAbbreviation: allTeamsByID[game.homeTeamID]?.abbreviation)

        coachedSession = nil
        loadAllData()

        // Give the cover dismissal a beat before presenting the sheet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            if lastGameResult != nil { activeSheet = .gameSummary }
        }
    }

    /// Confirm and advance out of coaching changes.
    ///
    /// This used to write `career.currentPhase = .reviewRoster` directly, which
    /// looked like an advance and was not one: it skipped
    /// `WeekAdvancer.advanceWeek` entirely, so the whole `.coachingChanges`
    /// engine block never ran for anybody who advanced from the dashboard —
    /// no retirement wave, no coach carousel, no underclassman declarations, no
    /// **Senior Bowl**, no draft-cycle heartbeat — and none of the `.reviewRoster`
    /// entry work either (the `rosterEvaluationConfirmed` / `franchiseTagVisited`
    /// reset and the owner's roster demands). The calendar sidebar's Advance
    /// button, which goes straight to the shell, DID run all of it, so the same
    /// screen had two buttons with two different meanings.
    ///
    /// Now the sheet is purely a confirmation step: it hands the advance back to
    /// the one path every other phase uses.
    private func confirmCoachingAdvance() {
        if let onAdvance {
            onAdvance()
        } else {
            // Standalone/preview use (no shell): still go through the engine.
            WeekAdvancer.advanceWeek(career: career, modelContext: modelContext)
            try? modelContext.save()
            loadAllData()
        }
    }

    private func loadCoaches() {
        guard let teamID = career.teamID else { return }
        // Scoped to the open save as well as the club: `teamID` alone matches
        // every career's copy of that franchise, so a second save's staff
        // could walk into this one's review sheet. Same idiom as
        // `allTeamsDescriptor` in `loadAllDataBody`.
        let cid = career.id
        let descriptor = FetchDescriptor<Coach>(
            predicate: #Predicate { $0.careerID == cid && $0.teamID == teamID }
        )
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
        .task {
            loadAllData()
            // R39 (b): Continue Career tap → dashboard data ready.
            PerfLog.measure("career_open_to_dashboard", sinceMark: "career_open")
            // R39: pre-compile the 3D field's GPU pipelines in the background
            // so the first Coach-the-Game open skips the shader-compile stall.
            FootballFieldScene.warmUp()
            // R37: one-time dashboard tour on the very first open.
            if !FirstRunTip.dashboardTour.isDone && dashboardTourStep == nil {
                withAnimation(.easeInOut(duration: 0.25)) { dashboardTourStep = 0 }
            }
        }
        .onAppear {
            // #106: `.task` only fires on the first open, so hiring staff on a
            // pushed screen and popping back left the tiles on stale budget and
            // slot numbers. The re-appear path refreshes ONLY the staff tile's
            // inputs — the full `loadAllData` refetches every game of two
            // seasons on the main thread mid-pop animation, and its
            // `loadLatestHardKnocksEvent` would clear a toast the user may
            // still be reading. First appear is left to `.task` above.
            if hasAppearedOnce {
                refreshStaffTile()
            } else {
                hasAppearedOnce = true
            }
        }
        // ONE sheet modifier for the whole screen. See ``ActiveSheet`` — four
        // presentations used to hang off this one chain and only the last of
        // them was guaranteed to be the one SwiftUI presented.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .gameSummary:
                if let result = lastGameResult, let home = lastHomeTeam, let away = lastAwayTeam {
                    NavigationStack {
                        GameSummaryView(
                            boxScore: result.boxScore,
                            homeTeam: home,
                            awayTeam: away,
                            playerStats: result.playerStats,
                            weather: lastGameWeather
                        )
                    }
                }

            // Injuries quick chip / Injuries tile → the medical report, not the
            // plain roster Overview. Presented as a sheet so it reads the same
            // here as it does from the Roster screen's medical toolbar button.
            case .injuryReport:
                InjuryReportView(players: players, career: career)

            // Position Battles tile → the real battle, not a dead roster jump.
            case let .positionBattle(battle):
                PositionBattleSheet(
                    battle: battle,
                    competitors: competitors(for: battle)
                )

            case .coachingStaffReview:
                CoachingStaffReviewSheet(
                    career: career,
                    coaches: allCoaches,
                    players: players,
                    onConfirm: {
                        activeSheet = nil
                        confirmCoachingAdvance()
                    },
                    onCancel: {
                        activeSheet = nil
                    }
                )
                .presentationDetents([.large])
            }
        }
        .fullScreenCover(item: $coachedSession) { session in
            CoachedGameView(
                homeTeam: session.homeTeam,
                awayTeam: session.awayTeam,
                homeCoaches: session.homeCoaches,
                awayCoaches: session.awayCoaches,
                playerTeamIsHome: session.playerTeamIsHome,
                audibleBoost: session.audibleBoost,
                defReadBoost: session.defReadBoost,
                // Same deterministic draw the quick sim uses for this game
                // (home venue included so dome teams read indoors/clear).
                weather: GameWeather.forGame(id: session.game.id, week: session.game.week, homeTeamAbbreviation: session.homeTeam.abbreviation),
                // R19: playoff framing (PLAYOFFS badge, win-or-go-home copy).
                isPlayoff: session.game.isPlayoff,
                // R36: plays installed through weekly practice widen the sheet.
                bonusPlays: Set(career.bonusInstalledPlays),
                onPracticeRequest: { play in
                    // "Practice this" from a dimmed call-sheet card: queue the
                    // play as the week's drill (replaces any previous pick).
                    career.weeklyPracticePlay = play
                    try? modelContext.save()
                },
                onFinish: { engine in
                    finishCoachedGame(engine: engine, game: session.game)
                }
            )
        }
        .onChange(of: launchCoachedGame.wrappedValue) { _, shouldLaunch in
            // #37: the Game Plan screen popped back and asked us to launch.
            guard shouldLaunch else { return }
            launchCoachedGame.wrappedValue = false
            startCoachedGame()
        }
        // Advance-with-unplayed-game guard rail.
        .confirmationDialog(
            skipGameConfirmTitle,
            isPresented: $showSkipGameConfirm,
            titleVisibility: .visible
        ) {
            Button("Sim & Advance") { runAdvance() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You haven't coached this game yet. Advancing plays it for you and the result is final.")
        }
        .overlay(alignment: .bottom) {
            if let event = latestHardKnocksEvent,
               !shownHardKnocksEventIDs.contains(event.id) {
                HardKnocksToast(event: event) {
                    shownHardKnocksEventIDs.insert(event.id)
                    latestHardKnocksEvent = nil
                }
                .padding(.bottom, DSSpacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay {
            // R37: first-run dashboard tour — the card floats over the center
            // of the dashboard; everything behind it stays fully interactive.
            if dashboardTourStep != nil {
                CoachMarkOverlay(
                    steps: Self.dashboardTourSteps,
                    step: $dashboardTourStep,
                    onComplete: { FirstRunTip.dashboardTour.markDone() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }

    // MARK: - Landscape Layout (3-column)

    // MARK: - Portrait 2-Column Layout (tasks | content)

    private var portraitTwoColumnLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column -- Tasks (fixed 280pt)
            ScrollView {
                VStack(spacing: 0) {
                    #if DEBUG
                    debugSkipToFABanner
                    #endif
                    if canAdvance {
                        advanceReadinessBanner
                    }
                    coachingBudgetBlockerBanner
                    TimelineTasksPanel(
                        career: career,
                        tasks: $tasks,
                        onTaskSelected: onTaskSelected,
                        onAdvance: { performAdvance() },
                        canAdvance: canAdvance,
                        advanceIsPrimary: !weeklyGameUnplayed
                    )
                }
                .padding(.leading, 8)
            }
            // 300 (matching the landscape rail) rather than 280: at 280 the
            // longest real task titles — "Set game plan for your opponent" —
            // wrapped to a second line, which made the list scan ragged.
            .frame(width: 300)
            // The panel paints its own background only as far as its content
            // reaches; on a short task list that left the bottom of the rail
            // showing the darker page color. Paint the whole column instead.
            .background(Color.backgroundSecondary)

            Divider().overlay(Color.surfaceBorder)

            // Right column -- Tiles + Messages + Division + Schedule
            ScrollView {
                LazyVStack(spacing: 12) {
                    centerTilesGrid
                    // No minHeight: with a single message the 240pt floor left
                    // ~180pt of empty panel under it. The empty state carries
                    // its own height when there is genuinely nothing to show.
                    messagesPanel
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
                #if DEBUG
                debugSkipToFABanner
                #endif
                // Fix #64: Clear guidance when all tasks complete
                if canAdvance {
                    advanceReadinessBanner
                }
                coachingBudgetBlockerBanner
                TimelineTasksPanel(
                    career: career,
                    tasks: $tasks,
                    onTaskSelected: onTaskSelected,
                    onAdvance: { performAdvance() },
                    canAdvance: canAdvance,
                    advanceIsPrimary: !weeklyGameUnplayed
                )
            }
            .frame(width: 300)

            Divider().overlay(Color.surfaceBorder)

            // Center column -- Dashboard tiles + Messages (flexible)
            ScrollView {
                LazyVStack(spacing: 12) {
                    centerTilesGrid
                    messagesPanel
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
            LazyVStack(spacing: 12) {
                // Timeline+Tasks panel (full width, collapsible)
                VStack(spacing: 0) {
                    #if DEBUG
                    debugSkipToFABanner
                    #endif
                    // Fix #64: Clear guidance when all tasks complete
                    if canAdvance {
                        advanceReadinessBanner
                    }
                    coachingBudgetBlockerBanner
                    TimelineTasksPanel(
                        career: career,
                        tasks: $tasks,
                        onTaskSelected: onTaskSelected,
                        onAdvance: { performAdvance() },
                        canAdvance: canAdvance,
                        advanceIsPrimary: !weeklyGameUnplayed
                    )
                }
                .frame(minWidth: 320, minHeight: 280, maxHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                // Gold glow only when Advance is genuinely the next step. With
                // the weekly game unplayed the hero card owns the gold.
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(advanceIsPrimaryCTA ? Color.accentGold : Color.surfaceBorder,
                                      lineWidth: advanceIsPrimaryCTA ? 2 : 1)
                )
                .shadow(color: advanceIsPrimaryCTA ? Color.accentGold.opacity(advancePulse ? 0.4 : 0.1) : .clear,
                        radius: advanceIsPrimaryCTA ? 8 : 0)
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
            (String(localized: "Coaching"), "Feb", .coachingChanges, nil),
            (String(localized: "Review"), "Feb", .reviewRoster, nil),
            (String(localized: "Combine"), "Mar", .combine, nil),
            (String(localized: "Free Agency"), "Mar", .freeAgency, nil),
            (String(localized: "Draft"), "Apr", .draft, nil),
            (String(localized: "OTAs"), "May", .otas, nil),
            (String(localized: "Camp"), "Jun", .trainingCamp, nil),
            (String(localized: "Preseason"), "Aug", .preseason, nil),
            (String(localized: "Cuts"), "Aug", .rosterCuts, nil),
        ]
        // Regular season weeks
        let weekMonths = ["Sep","Sep","Sep","Sep","Oct","Oct","Oct","Oct","Nov","Nov","Nov","Nov","Dec","Dec","Dec","Dec","Jan","Jan"]
        for w in 1...18 {
            let month = w <= weekMonths.count ? weekMonths[w - 1] : "Jan"
            nodes.append((String(localized: "Wk \(w)"), month, .regularSeason, w))
        }
        nodes.append((String(localized: "Playoffs"), "Jan", .playoffs, nil))
        nodes.append((String(localized: "Super Bowl"), "Feb", .superBowl, nil))
        return nodes
    }

    /// Index of the currently active node in the timeline.
    private var currentNodeIndex: Int {
        let phase = career.currentPhase
        let week = career.currentWeek

        // The week nodes are all tagged `.regularSeason`, so the deadline week —
        // a real `.tradeDeadline` phase now — has to match them as one of its own
        // or the strip would highlight node 0 (Pro Bowl) for a week.
        let nodeMatchPhase: SeasonPhase = phase == .tradeDeadline ? .regularSeason : phase
        for (i, node) in timelineNodes.enumerated() {
            if let nodePhase = node.phase {
                if nodePhase == nodeMatchPhase {
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
                        // Shared empty-state component rather than a bare
                        // icon + "No messages", and it now says what will
                        // eventually land here.
                        EmptyStateView(
                            icon: "tray",
                            title: "No messages",
                            message: "Weekly recaps, owner notes and league news arrive here as the season plays out."
                        )
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
        VStack(spacing: 12) {
            // Quick Action Bar — 3 phase-specific shortcuts at the top.
            quickActionBar

            // Phase-aware Hero Card — adapts to current SeasonPhase, sits at top.
            phaseHeroCard

            // Next Action hero banner — promotes the topmost incomplete required task.
            // Sits above all other dashboard content for maximum prominence.
            nextActionHero

            // Satisfaction/Reputation scores row
            satisfactionScoresRow

            // Every tile — core *and* phase-adaptive — flows through one grid.
            // Fixed HStack pairs used to hard-code which two tiles shared a row,
            // so an absent optional tile (no previous season yet) left a dead
            // hole in the right column. In a single grid the next tile closes
            // the gap instead.
            LazyVGrid(columns: tileColumns, spacing: 12) {
                coreTiles
                adaptiveTiles
            }
        }
    }

    /// Tiles shown in every phase, in reading order.
    @ViewBuilder
    private var coreTiles: some View {
        teamTile
        rosterTile
        staffTile
        capTile
        lockerRoomTile
        keyPlayersTile
        positionStrengthsTile
        expiringContractsTile
        ownerExpectationsTile
        if previousSeasonRecord != nil { previousSeasonTile }
    }

    // MARK: - Adaptive Tiles (per Phase Group)

    @ViewBuilder
    private var adaptiveTiles: some View {
        switch career.currentPhase.group {
        case .postseason:
            awardsHubTile
            teamAccoladesTile
            seasonRecapTile

        case .offseason:
            cap3yearForecastTile
            offseasonGoalsTile
            inboxTile

        case .preDraft:
            scoutingTile
            if career.currentPhase == .freeAgency { freeAgencyTile }
            if career.currentPhase == .proDays { proDaysTile }
            if career.currentPhase == .draft { draftTile }
            mockDraftTile
            teamNeedsTile

        case .preSeason:
            trainingPlanTile
            workloadTile
            positionBattlesTile
            campGradesTile
            if career.currentPhase == .rosterCuts { rosterCutsTile }
            if career.currentPhase == .preseason { preseasonGamesTile }

        case .regularSeason:
            gameWeekPrepTile
            depthChartTile
            injuryReportTile
            opponentScoutTile
            if career.currentPhase == .tradeDeadline { tradeDeadlineTile }
            if career.currentPhase == .playoffs { playoffBracketTile }
        }
    }

    // MARK: - Quick Action Bar (per Phase Group)

    private struct QuickAction {
        let icon: String
        let label: String
        let destination: TaskDestination
        /// When true the chip opens the medical/injury report sheet instead of
        /// pushing `destination`. The Injuries chip used to route to `.roster`,
        /// which dumped the user on the plain roster Overview with no hint of
        /// what they were meant to look at.
        var opensInjuryReport: Bool = false
    }

    private func quickActions(for group: SeasonPhaseGroup) -> [QuickAction] {
        switch group {
        case .postseason:
            return [
                QuickAction(icon: "trophy.fill", label: "Awards", destination: .roster),
                QuickAction(icon: "person.fill", label: "Coach Renewals", destination: .coachingStaff),
                QuickAction(icon: "checklist", label: "Draft Grades", destination: .draftReportCard),
                QuickAction(icon: "building.columns.fill", label: "History", destination: .history)
            ]
        case .offseason:
            return [
                QuickAction(icon: "person.fill", label: "Coaching", destination: .coachingStaff),
                QuickAction(icon: "list.dash", label: "Roster Review", destination: .rosterEvaluation),
                QuickAction(icon: "chart.line.uptrend.xyaxis", label: "Cap", destination: .capOverview),
                QuickAction(icon: "building.columns.fill", label: "History", destination: .history)
            ]
        case .preDraft:
            return [
                QuickAction(icon: "magnifyingglass", label: "Scouting", destination: .scouting),
                QuickAction(icon: "list.bullet", label: "Big Board", destination: .bigBoard),
                QuickAction(icon: "list.bullet.rectangle", label: "Mock Draft", destination: .scouting)
            ]
        case .preSeason:
            return [
                QuickAction(icon: "figure.run.circle", label: "Training", destination: .trainingPlan),
                QuickAction(icon: "person.2.fill", label: "Battles", destination: .roster),
                QuickAction(icon: "graduationcap.fill", label: "Camp Grades", destination: .roster)
            ]
        case .regularSeason:
            return [
                QuickAction(icon: "scope", label: "Game Plan", destination: .gamePlan),
                QuickAction(icon: "list.number", label: "Depth Chart", destination: .depthChart),
                QuickAction(icon: "chart.line.uptrend.xyaxis", label: "Development", destination: .developmentReport),
                QuickAction(icon: "cross.case.fill", label: "Injuries", destination: .roster, opensInjuryReport: true)
            ]
        }
    }

    @ViewBuilder
    private var quickActionBar: some View {
        let group = career.currentPhase.group
        HStack(spacing: 8) {
            ForEach(quickActions(for: group), id: \.label) { action in
                quickActionButton(action)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func quickActionButton(_ action: QuickAction) -> some View {
        Button {
            if action.opensInjuryReport {
                activeSheet = .injuryReport
            } else {
                onTaskSelected(action.destination)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: action.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.draftStealGold)
                Text(action.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .strokeBorder(Color.draftStealGold.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Phase-Group Stub Tiles

    private var awardsHubTile: some View {
        Button {
            onTaskSelected(.roster)
        } label: {
            DashboardTile(icon: "trophy.fill", title: "Awards Hub") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pro Bowl & All-Pro")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("0 Pro Bowlers \u{00B7} 0 All-Pro")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var teamAccoladesTile: some View {
        Button {
            onTaskSelected(.roster)
        } label: {
            DashboardTile(icon: "star.fill", title: "Team Accolades") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Legacy: +\(career.legacy.totalPoints)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    Text("Season grade pending")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var seasonRecapTile: some View {
        Button {
            onTaskSelected(.roster)
        } label: {
            DashboardTile(icon: "doc.text.fill", title: "Season Recap") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(seasonRecordSummary)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Final standings & summary")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var seasonRecordSummary: String {
        let wins = team?.wins ?? 0
        let losses = team?.losses ?? 0
        let ties = team?.ties ?? 0
        if ties > 0 {
            return "\(wins)-\(losses)-\(ties) record"
        }
        return "\(wins)-\(losses) record"
    }

    /// "$265M → $321M" — the club's ACTUAL cap rolled forward three league
    /// years at the engine's own growth rate (task #87 / F14, F15).
    private var threeYearCapProjection: String {
        let now = team?.salaryCap ?? ContractEngine.openingSalaryCap
        let then = Double(now) * pow(1.0 + ContractEngine.capGrowthPerSeason, 3)
        return String(format: "$%.0fM \u{2192} $%.0fM", Double(now) / 1_000.0, then / 1_000.0)
    }

    private var cap3yearForecastTile: some View {
        Button {
            onTaskSelected(.capOverview)
        } label: {
            DashboardTile(icon: "chart.line.uptrend.xyaxis", title: "3-Year Cap") {
                VStack(alignment: .leading, spacing: 4) {
                    // Task #87 / F14: this was the string literal `$285M → $310M`
                    // on a live tile — never read `team.salaryCap`, and deceptive
                    // precisely because $285M is close to a number the docs used.
                    Text(threeYearCapProjection)
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    Text("Projection across 3 seasons")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var offseasonGoalsTile: some View {
        Button {
            onTaskSelected(.ownerMeeting)
        } label: {
            DashboardTile(icon: "target", title: "Season Review") {
                VStack(alignment: .leading, spacing: 4) {
                    // R31: real numbers from the last owner review / goal log
                    if let review = career.ownerSeasonReview {
                        Text("\(review.goalsAchieved) of \(max(review.goalsTotal, 1)) met")
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(review.goalsAchieved * 2 >= review.goalsTotal ? Color.success : Color.warning)
                        Text("Owner verdict: \(review.verdict.label)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Text("Owner mandates")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Meet the owner")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var inboxTile: some View {
        Button {
            onTaskSelected(.inbox)
        } label: {
            DashboardTile(icon: "tray.fill", title: "Inbox") {
                VStack(alignment: .leading, spacing: 4) {
                    let unread = inboxMessages.filter { !$0.isRead }.count
                    Text("\(unread) unread")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(unread > 0 ? Color.accentGold : Color.textSecondary)
                    Text("Offseason news")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var mockDraftTile: some View {
        Button {
            onTaskSelected(.scouting)
        } label: {
            DashboardTile(icon: "list.bullet.rectangle.fill", title: "Mock Draft") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest: Pre-Draft")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("Compare to Big Board")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var teamNeedsTile: some View {
        Button {
            onTaskSelected(.roster)
        } label: {
            DashboardTile(icon: "exclamationmark.triangle.fill", title: "Team Needs") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("QB CB LT")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.warning)
                    Text("Top draft priorities")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var proDaysTile: some View {
        Button {
            onTaskSelected(.scouting)
        } label: {
            DashboardTile(icon: "figure.run", title: "Pro Days") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Schedule visits")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("Workouts & interviews")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Position Battles Tile

    /// Unresolved battles whose competitors are on the user's roster. Queried
    /// straight from the `PositionBattle` rows `PositionBattleTracker` writes
    /// during camp — the tile previously printed a hard-coded "0 active".
    ///
    /// Filtered by `seasonYear` again (task #67). The season filter had been
    /// removed as a workaround for `detectBattles` stamping the real-world
    /// calendar year instead of `career.currentSeason`; the tracker writes the
    /// career's season now, so the tile can key on it — and must, or it would
    /// list every unresolved battle the save has ever produced.
    private func loadPositionBattles() {
        let cid = career.id
        let season = career.currentSeason
        let descriptor = FetchDescriptor<PositionBattle>(
            predicate: #Predicate<PositionBattle> {
                $0.careerID == cid && $0.seasonYear == season && $0.winnerID == nil
            }
        )
        let rosterIDs = Set(players.map(\.id))
        openPositionBattles = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { battle in battle.competitorIDs.contains { rosterIDs.contains($0) } }
            .sorted { $0.positionRaw < $1.positionRaw }
    }

    /// Roster players taking part in a battle, in depth-chart order.
    private func competitors(for battle: PositionBattle) -> [Player] {
        let ids = Set(battle.competitorIDs)
        return players.filter { ids.contains($0.id) }
            .sorted { $0.overall > $1.overall }
    }

    private var positionBattlesTile: some View {
        DashboardTile(icon: "person.2.fill", title: "Position Battles") {
            VStack(alignment: .leading, spacing: 4) {
                if openPositionBattles.isEmpty {
                    Text("None active")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                    Text("Camp competitions open in Training Camp")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                } else {
                    Text("\(openPositionBattles.count) active")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    ForEach(openPositionBattles.prefix(3), id: \.id) { battle in
                        Button {
                            activeSheet = .positionBattle(battle)
                        } label: {
                            positionBattleRow(battle)
                        }
                        .buttonStyle(.plain)
                    }
                    if openPositionBattles.count > 3 {
                        Text("+ \(openPositionBattles.count - 3) more")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
    }

    private func positionBattleRow(_ battle: PositionBattle) -> some View {
        let roster = competitors(for: battle)
        let names = roster.prefix(2).map(\.lastName).joined(separator: " vs ")
        let leader = battle.currentLeaderID.flatMap { id in roster.first { $0.id == id } }
        return HStack(spacing: 4) {
            Text(battle.positionRaw)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.accentGold)
                .frame(width: 24, alignment: .leading)
            Text(names.isEmpty ? "Open spot" : names)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let leader {
                Text(leader.lastName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.success)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .contentShape(Rectangle())
    }

    private var campGradesTile: some View {
        Button {
            onTaskSelected(.roster)
        } label: {
            DashboardTile(icon: "graduationcap.fill", title: "Camp Grades") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top: \u{2014}")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("Grades update weekly")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var preseasonGamesTile: some View {
        Button {
            onTaskSelected(.schedule)
        } label: {
            DashboardTile(icon: "sportscourt", title: "Preseason") {
                VStack(alignment: .leading, spacing: 4) {
                    // Preseason is a camp/evaluation phase in this build — no
                    // scored W-L record is tracked, so show the tile's purpose
                    // instead of a fabricated "0-0 record" stat.
                    Text("Evaluate roster")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("3 exhibition games")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var depthChartTile: some View {
        Button {
            onTaskSelected(.depthChart)
        } label: {
            DashboardTile(icon: "list.number", title: "Depth Chart") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("View")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("Starters & backups")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var injuryReportTile: some View {
        Button {
            // Same destination as the Injuries quick chip — the medical report,
            // not the plain roster.
            activeSheet = .injuryReport
        } label: {
            DashboardTile(icon: "cross.case.fill", title: "Injuries") {
                VStack(alignment: .leading, spacing: 4) {
                    let injuredCount = players.filter { $0.injuryWeeksRemaining > 0 }.count
                    Text("\(injuredCount) out")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(injuredCount > 0 ? Color.danger : Color.success)
                    Text("Status updates weekly")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var opponentScoutTile: some View {
        Button {
            onTaskSelected(.gameWeekPrep)
        } label: {
            DashboardTile(icon: "binoculars.fill", title: "Opponent Scout") {
                VStack(alignment: .leading, spacing: 4) {
                    let opponent = upcomingGames.first.flatMap { game in
                        allTeamsByID[game.homeTeamID == team?.id ? game.awayTeamID : game.homeTeamID]
                    }
                    Text(opponent.map { "Vs \($0.abbreviation)" } ?? "Vs \u{2014}")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                    Text("Strengths & weaknesses")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Live for exactly one week now that `.tradeDeadline` is a real persisted
    /// phase (trade plan finding S2). Replaces the old always-dead `tradeTile`,
    /// which claimed "trade window open" from a code path nothing rendered.
    private var tradeDeadlineTile: some View {
        let pendingOffers = career.pendingTradeOffers.count
        return Button {
            onTaskSelected(.trades)
        } label: {
            DashboardTile(icon: "clock.fill", title: "TRADE DEADLINE", highlighted: true) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Passes after Week \(WeekAdvancer.tradeDeadlineWeek)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.danger)
                    Text(pendingOffers > 0
                         ? "\(pendingOffers) offer\(pendingOffers == 1 ? "" : "s") expire\(pendingOffers == 1 ? "s" : "") — answer them"
                         : "Last chance for deals this season")
                        .font(.system(size: 10))
                        .foregroundStyle(pendingOffers > 0 ? Color.accentGold : Color.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var playoffBracketTile: some View {
        Button {
            onTaskSelected(.standings)
        } label: {
            DashboardTile(icon: "rosette", title: "Playoff Bracket") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WC / DIV / CONF / SB")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                    Text("Postseason path")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Camp Tiles

    private var trainingPlanTile: some View {
        NavigationLink(value: CareerShellView.ShellDestination.trainingPlan) {
            DashboardTile(icon: "figure.run.circle.fill", title: "Training Plan") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Set focus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("Tactical / Physical / Technical")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var workloadTile: some View {
        NavigationLink(value: CareerShellView.ShellDestination.workloadDashboard) {
            DashboardTile(icon: "heart.text.square.fill", title: "Workload") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monitor camp load")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("Injury & burnout risk")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rosterCutsTile: some View {
        let rosterCount: Int = {
            guard let teamID = career.teamID else { return 0 }
            let descriptor = FetchDescriptor<Player>(predicate: #Predicate<Player> { $0.teamID == teamID })
            return (try? modelContext.fetchCount(descriptor)) ?? 0
        }()
        let cutsRemaining = max(0, rosterCount - 53)

        return NavigationLink(value: CareerShellView.ShellDestination.rosterCuts) {
            DashboardTile(icon: "scissors", title: "Roster Cuts", highlighted: cutsRemaining > 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cutsRemaining > 0 ? "\(cutsRemaining) cuts remaining" : "Roster set")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(cutsRemaining > 0 ? Color.warning : Color.success)
                    Text("90 → 75 → 65 → 53")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var gameWeekPrepTile: some View {
        NavigationLink(value: CareerShellView.ShellDestination.gameWeekPrep) {
            DashboardTile(icon: "scope", title: "Week Prep") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Week \(career.currentWeek) prep")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("General vs opponent focus")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
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
            } else if isPreSeasonNoGamesPlayed {
                // Empty state — replace 0-0 rows with a "Week 1 in N" countdown.
                preSeasonCountdownRow
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
                                .frame(width: 34, alignment: .leading)

                            // Fills what was ~600pt of empty row between the
                            // abbreviation and the W-L column, and matches the
                            // full Standings screen's team column.
                            Text(t?.fullName ?? "")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(isMyTeam ? Color.textSecondary : Color.textTertiaryReadable)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
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
                        RoundedRectangle(cornerRadius: DSCornerRadius.tight)
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
                        HStack(spacing: 6) {
                            // Same leading-portrait rhythm as the AI head-coach
                            // branch right below — "You" was the one HC on this
                            // tile without a face.
                            UserPortraitView(career: career, size: .small)
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
                    // #106: read the scouting department off the enum — it grew
                    // two extra slots (chief + 5 regional + 2 extra) and the
                    // hardcoded 6 rendered a filled count above the total.
                    // #133: both halves now come from `StaffSlots`, the same seat
                    // list the staff screen counts its vacancies against.
                    let totalSlots = StaffSlots.totalSlots(for: career.role)
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
                                .foregroundStyle(coachingBudgetRemaining > 10_000 ? Color.success : coachingBudgetRemaining > 5_000 ? Color.accentGold : Color.warning)
                            Text("Budget")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                            Text(formatCap(coachingBudgetRemaining))
                                .font(.system(size: 11, weight: .bold).monospacedDigit())
                                .foregroundStyle(coachingBudgetRemaining > 10_000 ? Color.success : coachingBudgetRemaining > 5_000 ? Color.accentGold : Color.warning)
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
                        let isCapTight = usedFraction > 0.85

                        HStack(alignment: .firstTextBaseline) {
                            Text("Used")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            if isCapTight {
                                Text("CAP TIGHT")
                                    .font(.system(size: 8, weight: .black))
                                    .foregroundStyle(.white)
                                    .tracking(0.5)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(usedFraction > 0.95 ? Color.danger : Color.warning))
                            }
                            Spacer()
                            Text(formatCap(t.currentCapUsage))
                                .font(.system(size: 16, weight: .bold).monospacedDigit())
                                .foregroundStyle(isCapTight ? Color.warning : Color.textPrimary)
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
                    // Chemistry tier — same engine label + same 0-100 value the
                    // Locker Room screen prints ("Elite 100/100").
                    HStack {
                        Text("Chemistry")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(LockerRoomEngine.chemistryLabel(teamChemistry)) \(teamChemistry)/100")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(chemistryColor(teamChemistry))
                    }

                    // The bar belongs to the CHEMISTRY row above it — it used to
                    // plot morale under a "Chemistry" label.
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(Color.backgroundTertiary)
                                .frame(height: 12)
                            RoundedRectangle(cornerRadius: 5)
                                .fill(chemistryColor(teamChemistry))
                                .frame(width: geo.size.width * (Double(teamChemistry) / 100.0), height: 12)
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
        // NOTE: Outer NavigationLink intentionally removed — per-grade letters are now
        // tap targets that open an explainer popover. A "View" link is still available
        // in the header.
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
                    // Key first: "S: A / D: B-" was unreadable without it.
                    Text("S = starters \u{00B7} D = depth \u{00B7} tap a grade for details")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                        .padding(.top, 2)
                }
            }
        }
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
            gradeButton(group: item.group, kind: "S", grade: item.starterGrade, ovr: item.starterOVR)
            Text("/")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
            Text("D:")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            gradeButton(group: item.group, kind: "D", grade: item.depthGrade, ovr: item.depthOVR)
            if isWeakest {
                Text("NEED")
                    .font(.system(size: 7, weight: .heavy))
                    // R39 device coverage: on iPad mini the grid column runs
                    // out of width and this badge wrapped into a vertical
                    // letter stack — shrink instead of wrapping.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
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

    /// Tappable grade letter that surfaces an explainer popover.
    /// `kind` is "S" (starter) or "D" (depth) — used to disambiguate the popover binding.
    private func gradeButton(group: String, kind: String, grade: String, ovr: Int) -> some View {
        let id = "\(group):\(kind)"
        return Button {
            positionGradePopoverID = id
        } label: {
            Text(grade)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(grade))
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: Binding(
                get: { positionGradePopoverID == id },
                set: { if !$0 { positionGradePopoverID = nil } }
            ),
            attachmentAnchor: .point(.center),
            arrowEdge: .top
        ) {
            gradeExplainerContent(group: group, kind: kind, grade: grade, ovr: ovr)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// Explainer card content shown inside the position-grade popover.
    private func gradeExplainerContent(group: String, kind: String, grade: String, ovr: Int) -> some View {
        let kindLabel = kind == "S" ? "Starter" : "Depth"
        let (description, percentile) = gradeExplainerCopy(grade)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(group)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentGold.opacity(0.15)))
                Text(kindLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(grade)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(grade))
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(grade): \(description)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(percentile)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                Text("Average OVR: \(ovr)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(12)
        .frame(width: 240)
        .background(Color.backgroundSecondary)
    }

    /// Plain-language copy describing what each letter grade means relative to the league.
    private func gradeExplainerCopy(_ grade: String) -> (description: String, percentile: String) {
        switch grade {
        case "A+":
            return ("elite, top 5% league-wide", "Championship-caliber unit at this position group.")
        case "A":
            return ("excellent, top 10%", "Among the best in the league at this position group.")
        case "A-":
            return ("very strong, top 15%", "Clear strength of the roster.")
        case "B+":
            return ("above league average, top 25%", "Above-average for this position group league-wide.")
        case "B":
            return ("solid starter quality", "Roughly league average — dependable, not a weakness.")
        case "B-":
            return ("average, mid-tier", "Average starter quality, some upside.")
        case "C+":
            return ("below average", "Slightly below the league bar at this position group.")
        case "C":
            return ("weak starter / good depth", "Below average — consider an upgrade.")
        case "C-":
            return ("weakness, bottom 25%", "A position-group hole that opponents will target.")
        case "D+", "D":
            return ("bottom 15% league-wide", "Major roster need — prioritize in FA or the draft.")
        case "F":
            return ("worst in league tier", "Critical hole — fix immediately.")
        default:
            return ("position group grade", "Higher letters indicate stronger units relative to the league.")
        }
    }

    // MARK: - Expiring Contracts Tile (#19)

    /// Phases in which the user can actually do something about an expiring
    /// deal (extend, tag, or let him hit the market). Alarming a Week 1 coach
    /// about 17 contracts he cannot touch for four months is noise.
    private var isContractActionWindow: Bool {
        switch career.currentPhase.group {
        case .postseason, .offseason, .preDraft:
            return true
        case .preSeason, .regularSeason:
            return false
        }
    }

    /// True when expiring contracts warrant a HIGH PRIORITY callout on the Contracts tile.
    /// Triggers when there are 5+ expiring deals or when the average annual salary
    /// of expiring players is high (>= $5M, indicating expensive tag/extension cost)
    /// — and only inside the window where the user can act on them.
    private var contractsHighPriority: Bool {
        let count = expiringContractPlayers.count
        guard count > 0, isContractActionWindow else { return false }
        if count >= 5 { return true }
        let avgSalaryThousands = expiringContractPlayers.reduce(0) { $0 + $1.annualSalary } / count
        return avgSalaryThousands >= 5_000  // $5M average — tag/extension cost will be steep
    }

    private var expiringContractsTile: some View {
        // The whole card used to be one NavigationLink, which made every name
        // on it an unreachable label. Rows are their own links now; the footer
        // link keeps the card-level jump.
        DashboardTile(icon: "clock.badge.exclamationmark", title: "Contracts", highlighted: contractsHighPriority) {
            VStack(alignment: .leading, spacing: 6) {
                if contractsHighPriority {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                        Text("HIGH PRIORITY")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .tracking(0.5)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.danger))
                } else if !expiringContractPlayers.isEmpty {
                    // Outside the window: an amber chip, not a red alarm.
                    Text("\(expiringContractPlayers.count) expiring")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.warning.opacity(0.15)))
                }

                if expiringContractPlayers.isEmpty {
                    Text("No expiring contracts")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                } else {
                    if contractsHighPriority {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(expiringContractPlayers.count)")
                                .font(.system(size: 20, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.danger)
                            Text("expiring contract\(expiringContractPlayers.count == 1 ? "" : "s")")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        Text("Re-sign window opens in the offseason")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(2)
                    }

                    // Show top 3 names sorted by OVR, with star alert (#145).
                    // Each row deep-links into the Cap screen.
                    let topExpiring = Array(expiringContractPlayers.sorted { $0.overall > $1.overall }.prefix(3))
                    ForEach(topExpiring, id: \.id) { player in
                        NavigationLink {
                            CapOverviewView(career: career)
                        } label: {
                            expiringContractRow(player)
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        CapOverviewView(career: career)
                    } label: {
                        HStack(spacing: 3) {
                            Text("View all in Salary Cap")
                                .font(.system(size: 9, weight: .heavy))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(Color.accentGold)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func expiringContractRow(_ player: Player) -> some View {
        let isStar = player.overall >= 80
        return HStack(spacing: 4) {
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
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Owner Expectations Tile (#20, R31: job security + goals)

    private var ownerExpectationsTile: some View {
        NavigationLink {
            OwnerMeetingView(career: career)
        } label: {
            DashboardTile(icon: "building.2.fill", title: "Owner") {
                VStack(alignment: .leading, spacing: 6) {
                    if let owner = team?.owner {
                        let archetype = OwnerPersonaEngine.OwnerArchetype.from(owner)
                        let security = OwnerPersonaEngine.jobSecurity(owner: owner, career: career)

                        HStack(spacing: 6) {
                            // Leading-edge portrait, same rhythm as a coach row.
                            PersonFaceView(owner: owner, size: .small)
                            Text(owner.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if hasPendingOwnerWhim {
                                Image(systemName: "envelope.badge.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.warning)
                            }
                        }

                        HStack(spacing: 4) {
                            Image(systemName: archetype.icon)
                                .font(.system(size: 8))
                            Text(archetype.displayName)
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Color.accentGold)

                        // Job security meter
                        HStack {
                            Text("Job Security")
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(security.level.label)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(jobSecurityColor(security.level))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 5)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(jobSecurityColor(security.level))
                                    .frame(width: geo.size.width * Double(security.score) / 100.0, height: 5)
                            }
                        }
                        .frame(height: 5)

                        // Primary goal progress (goals vs reality)
                        if let primary = evaluatedOwnerGoals.first(where: { $0.priority == .primary }) {
                            HStack(spacing: 4) {
                                Image(systemName: primary.isAchieved ? "star.fill" : "target")
                                    .font(.system(size: 8))
                                    .foregroundStyle(primary.isAchieved ? Color.accentGold : Color.textSecondary)
                                Text(primary.title)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                if let target = primary.target {
                                    Text("\(primary.progress)/\(target)")
                                        .font(.system(size: 9, weight: .bold).monospacedDigit())
                                        .foregroundStyle(primary.isAchieved ? Color.accentGold : Color.textSecondary)
                                } else if primary.isAchieved {
                                    Text("Met")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color.accentGold)
                                }
                            }
                        } else {
                            HStack {
                                Text("Satisfaction")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text("\(owner.satisfaction)%")
                                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                                    .foregroundStyle(satisfactionColor(owner.satisfaction))
                            }
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

    /// R31: whether an owner whim awaits a response in Owner Relations.
    private var hasPendingOwnerWhim: Bool {
        career.ownerWhims.contains {
            $0.seasonYear == career.currentSeason && $0.status == .pending
        }
    }

    /// R31: the persisted season goals, re-evaluated against live team state.
    private var evaluatedOwnerGoals: [SeasonGoal] {
        guard let team else { return [] }
        let stored = career.ownerSeasonGoals
        guard !stored.isEmpty else { return [] }
        return OwnerGoalsEngine.evaluateGoalProgress(goals: stored, team: team, career: career)
    }

    private func jobSecurityColor(_ level: OwnerPersonaEngine.JobSecurityLevel) -> Color {
        switch level {
        case .secure:   return Color.success
        case .stable:   return Color.accentBlue
        case .pressure, .hotSeat: return Color.warning
        case .critical: return Color.danger
        }
    }

    // MARK: - Previous Season Summary Tile (#73)

    private var previousSeasonTile: some View {
        DashboardTile(icon: "clock.arrow.circlepath", title: "Last Season") {
            VStack(alignment: .leading, spacing: 6) {
                if let record = previousSeasonRecord, let year = previousSeasonYear {
                    Text("Season \(String(year))")
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
            // Live war room only during the draft phase — everywhere else this
            // tile opens the read-only recap (see `DraftRecapView`). Resuming
            // the room off stale picks started a 60 s pick clock in-season.
            if career.currentPhase == .draft {
                DraftDayView(career: career)
            } else {
                DraftRecapView(career: career)
            }
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
        let stepLabel: String = {
            switch FreeAgencyStep(rawValue: career.freeAgencyStep) {
            case .finalPush:    return "Final Push \u{2014} Re-sign your players"
            case .newLeagueYear: return "New League Year \u{2014} Contracts advancing"
            case .capReview:    return "Cap Compliance \u{2014} Get under the cap"
            case .signing:      return "Free Agency \u{2014} \(FreeAgencyStep.roundLabel(career.freeAgencyRound)) of 6 rounds"
            case .complete:     return "Free Agency Complete"
            default:            return "Free Agency"
            }
        }()

        return NavigationLink {
            Group {
                switch FreeAgencyStep(rawValue: career.freeAgencyStep) {
                case .finalPush:    FinalPushView(career: career)
                case .newLeagueYear: NewLeagueYearView(career: career)
                case .capReview:    CapComplianceView(career: career)
                case .signing:      FAWeeklyView(career: career)
                case .complete:     FACompleteView(career: career)
                default:            FinalPushView(career: career)
                }
            }
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
                    Text(stepLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentGold)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // NOTE: `tradeTile` deleted (trade plan finding S8) — it had zero call sites
    // and its copy was a lie ("Trade window open" regardless of phase). The
    // deadline week's real entry point is `tradeDeadlineTile`.

    // NOTE: advanceWeekButton and advanceWeekButtonCompact removed --
    // advance UI is now part of TimelineTasksPanel.

    // MARK: - Advance Readiness Banner (Fix #64)

    /// Sits above the tasks panel whenever `canAdvance` is true. It used to
    /// always read "All tasks complete! · Ready to advance" — over a list with
    /// four unchecked optional rows, and over an unplayed Week 1 game. It now
    /// states whichever of those is actually true.
    private var advanceReadinessBanner: some View {
        let state = advanceReadiness
        let icon: String
        let headline: String
        let hint: String
        let tint: Color

        switch state {
        case .gameUnplayed:
            icon = "sportscourt.fill"
            headline = "Week \(career.currentWeek) game not played"
            hint = "Advance will sim it"
            tint = .warning
        case .optionalOpen(let count):
            icon = "circle.dashed"
            headline = "\(count) optional task\(count == 1 ? "" : "s") open"
            hint = "Ready to advance"
            tint = .accentGold
        case .ready:
            icon = "checkmark.seal.fill"
            headline = "All tasks complete!"
            hint = "Ready to advance"
            tint = .success
        }

        return HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
            Text(headline)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 6)
            Text(hint)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentGold)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(0.1))
    }

    // MARK: - Debug Skip-to-FA (DEBUG only)

    #if DEBUG
    /// Tracks whether a skip operation is currently running so the button can show progress.
    @State private var debugSkipRunning: Bool = false

    /// Temporary developer-only banner that exposes a "Skip → FA" button.
    /// Loops `WeekAdvancer.advanceWeek` until the career reaches `.freeAgency`
    /// or a safety cap is hit. Allows fast iteration on FA flow during Loop 2.
    private var debugSkipToFABanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.accentGold)
            Text("DEBUG")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(Color.accentGold)
            Spacer(minLength: 4)
            Button {
                guard !debugSkipRunning else { return }
                Task { await skipToFreeAgency() }
            } label: {
                Label(debugSkipRunning ? "Skipping…" : "Skip → \(debugSkipTargetLabel)",
                      systemImage: debugSkipRunning ? "hourglass" : "forward.end.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentGold.opacity(0.18))
                    .foregroundStyle(Color.accentGold)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            // Disabled in-season (both regular-season phases): from here the skip
            // would grind a whole season of play-by-play on the main actor.
            .disabled(debugSkipRunning
                      || career.currentPhase == .regularSeason
                      || career.currentPhase == .tradeDeadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentGold.opacity(0.06))
    }

    /// The phase the skip will stop at from the current position. FA when it
    /// lies ahead this cycle; otherwise the next regular season. Without the
    /// regular-season stop, skipping from OTAs would grind a full season of
    /// play-by-play sim on the main actor (frozen "Skipping…" UI).
    private var debugSkipTargetLabel: String {
        switch career.currentPhase {
        case .freeAgency, .proDays, .draft, .otas, .trainingCamp, .preseason, .rosterCuts:
            return "Reg. Season"
        default:
            return "FA"
        }
    }

    /// Iterates `WeekAdvancer.advanceWeek` until the career reaches
    /// `.freeAgency` or `.regularSeason` (whichever comes first) or the safety
    /// cap is hit. Persists every step — WeekAdvancer never saves, and the
    /// blocked run loop means autosave cannot flush during the skip.
    @MainActor
    private func skipToFreeAgency() async {
        debugSkipRunning = true
        defer { debugSkipRunning = false }

        // First tap stops at FA (so the FA flow itself stays testable);
        // tapping again from FA onward fast-forwards to the regular season,
        // auto-running the AI draft exactly like the smoke-test harness (R39).
        let faOnwards: [SeasonPhase] = [
            .freeAgency, .proDays, .draft, .otas, .trainingCamp, .preseason, .rosterCuts,
        ]
        let stopAtFA = !faOnwards.contains(career.currentPhase)

        var safety = 0
        while career.currentPhase != .regularSeason
                && !(stopAtFA && career.currentPhase == .freeAgency)
                && safety < 60 {
            // CoachingChanges normally requires a user-confirmed sheet; bypass it
            // for the debug skip by mirroring what the confirm-sheet does.
            if career.currentPhase == .coachingChanges {
                career.currentPhase = .reviewRoster
            } else {
                let phaseBefore = career.currentPhase
                WeekAdvancer.advanceWeek(career: career, modelContext: modelContext)
                if career.currentPhase == .draft && phaseBefore != .draft {
                    MultiSeasonSmokeTest.runAIDraft(career: career, context: modelContext)
                }
            }
            try? modelContext.save()
            safety += 1
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms — let UI breathe
        }
        try? modelContext.save()
        loadAllData()
    }
    #endif

    /// Blocker banner shown when advance is gated by coaching-budget overage. (#54)
    @ViewBuilder
    private var coachingBudgetBlockerBanner: some View {
        if isBlockedByCoachingBudget {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.danger)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resolve coaching budget overage first")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.danger)
                    Text("You are \(formatCap(coachingOverage)) over the staff budget. Release staff or reduce salaries to advance.")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.danger.opacity(0.10))
            .accessibilityElement(children: .combine)
            .accessibilityHint("Resolve coaching budget overage first")
        }
    }

    // MARK: - Next Action Hero Banner

    /// Prominent banner that promotes the topmost incomplete required task.
    /// Shown at the top of the right-column dashboard area as a "hero" call-to-action.
    @ViewBuilder
    private var nextActionHero: some View {
        if let task = nextActionTask {
            Button {
                onTaskSelected(task.destination)
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    // Gold pulse pill
                    ZStack {
                        Circle()
                            .fill(Color.accentGold)
                            .frame(width: 36, height: 36)
                        Image(systemName: task.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("NEXT")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Color.backgroundPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.accentGold))
                            Text(task.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                        }
                        Text("Tap to start \u{2014} \(task.description)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.accentGold.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.accentGold, lineWidth: 1.5)
                        )
                )
                .shadow(color: Color.accentGold.opacity(0.25), radius: 6, x: 0, y: 2)
                .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Satisfaction Scores Row

    private var satisfactionScoresRow: some View {
        let ownerSat = team?.owner?.satisfaction ?? 50
        let legacyPts = career.legacy.totalPoints
        let mediaRep = career.legacy.mediaReputation

        return HStack(spacing: 10) {
            satisfactionCard(
                icon: "building.2.fill",
                label: "Owner",
                value: "\(ownerSat)%",
                color: satisfactionColor(ownerSat)
            )
            satisfactionCard(
                icon: "heart.fill",
                label: "Morale",
                value: "\(teamMorale)%",
                color: moraleColor(teamMorale)
            )
            satisfactionCard(
                icon: "newspaper.fill",
                label: "Media",
                value: career.legacy.reputationLabel,
                color: mediaReputationColor(mediaRep)
            )
            satisfactionCard(
                icon: "trophy.fill",
                label: "Legacy",
                value: "\(legacyPts)",
                color: Color.accentGold
            )
        }
    }

    private func satisfactionCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func mediaReputationColor(_ value: Int) -> Color {
        if value >= 30  { return Color.success }
        if value >= -10 { return Color.textSecondary }
        if value >= -30 { return Color.warning }
        return Color.danger
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

    /// Mirrors `LockerRoomView.chemistryColor` so the dashboard tile and the
    /// Locker Room screen tint the same score identically.
    private func chemistryColor(_ value: Int) -> Color {
        switch value {
        case 90...100: return Color.accentGold
        case 75..<90:  return Color.success
        case 55..<75:  return Color.accentBlue
        case 40..<55:  return Color.warning
        default:       return Color.danger
        }
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

    /// True when no division team has played a regular-season game yet —
    /// i.e. the standings would all read 0-0 and a countdown is more useful.
    private var isPreSeasonNoGamesPlayed: Bool {
        guard isOffseasonPhase else { return false }
        return divisionRecords.allSatisfy { $0.wins == 0 && $0.losses == 0 && $0.ties == 0 }
    }

    /// Approximate "weeks until Week 1" mapped from the current SeasonPhase.
    /// Used by the standings empty state.
    private var weeksUntilWeek1: Int {
        switch career.currentPhase {
        case .coachingChanges: return 28
        case .reviewRoster:    return 26
        case .combine:         return 24
        case .freeAgency:      return 22
        case .proDays:         return 20
        case .draft:           return 18
        case .otas:            return 14
        case .trainingCamp:    return 8
        case .preseason:       return 4
        case .rosterCuts:      return 1
        default:               return 0
        }
    }

    @ViewBuilder
    private var preSeasonCountdownRow: some View {
        let weeks = weeksUntilWeek1
        let phaseLabel: String = {
            switch career.currentPhase {
            case .coachingChanges: return "Coaching Changes"
            case .reviewRoster:    return "Roster Review"
            case .combine:         return "Combine"
            case .freeAgency:      return "Free Agency"
            case .proDays:         return "Pro Days"
            case .draft:           return "Draft"
            case .otas:            return "OTAs"
            case .trainingCamp:    return "Training Camp"
            case .preseason:       return "Preseason"
            case .rosterCuts:      return "Roster Cuts"
            default:               return "Offseason"
            }
        }()

        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentGold)

            VStack(alignment: .leading, spacing: 2) {
                if weeks > 0 {
                    Text("Week 1 in ~\(weeks) week\(weeks == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                } else {
                    Text("Season starts soon")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Text("Currently: \(phaseLabel)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentGold.opacity(0.08))
        )
    }

    /// Streak info derived from recent played games.
    private var currentStreak: (label: String, count: Int, isWin: Bool)? {
        guard let teamID = career.teamID else { return nil }
        let seasonYear = career.currentSeason
        let cid = career.id
        let gameDescriptor = FetchDescriptor<Game>(predicate: #Predicate {
            $0.careerID == cid && $0.seasonYear == seasonYear
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
        // Fallback to simple wins sort when records aren't available yet.
        // #134: the id tiebreaker matters most exactly here — before Week 1 every
        // team has 0 wins, and without it this sort was an unordered shuffle that
        // moved the badge on every render.
        let sorted = divisionTeams.sorted {
            $0.wins != $1.wins ? $0.wins > $1.wins : $0.id.uuidString < $1.id.uuidString
        }
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
        case .proDays:
            return ["Scouting", "Draft"]
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
        let cid = career.id
        let descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.careerID == cid })
        let teams = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
    }

    private func loadAllData() {
        PerfLog.time("dashboard_loadAllData") { loadAllDataBody() }
    }

    /// The staff tile's inputs alone — coaches, scouts and the three budget
    /// pots. This is the slice of `loadAllDataBody` that can go stale while a
    /// pushed screen hires or fires staff, and the ONLY work the `.onAppear`
    /// re-entry path runs: the full load refetches two seasons of games on the
    /// main thread, which is pop-animation jank the tile does not need.
    private func refreshStaffTile() {
        guard let teamID = career.teamID else { return }

        // Both descriptors are scoped to the open save as well as the club.
        // `teamID` alone matches EVERY career's copy of that franchise — a
        // second save's staff would land in this one's headcount, budget and
        // pro-day focus ledger. Same `careerID` clause `allTeamsDescriptor` in
        // `loadAllDataBody` already carries.
        let cid = career.id
        let coachDescriptor = FetchDescriptor<Coach>(
            predicate: #Predicate { $0.careerID == cid && $0.teamID == teamID }
        )
        let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
        allCoaches = coaches
        // #133: SEATS filled, not rows fetched — counted against the same
        // `StaffSlots` list the tile's denominator comes from, so the two can
        // never disagree about what a "staff" is.
        coachCount = StaffSlots.filledCoachSlots(coaches: coaches, careerRole: career.role)
        headCoach = coaches.first(where: { $0.role == .headCoach })

        // Coaching budget (#147) — the coaching pot only, counted exactly the
        // way CoachingStaffView counts it (#106). Medical staff draw from the
        // owner's medical budget and scouts from the scouting budget, so
        // charging either to this pot made the tile read millions lower than
        // the staff screen right after an auto-hire.
        let budgetTotal = team?.owner?.coachingBudget ?? 0
        // R31: medical staff draw from their own pot, not the coaching budget.
        let medicalRoles: Set<CoachRole> = [.teamDoctor, .physio, .headTrainer]
        let coachSalaryUsed = coaches
            .filter { !medicalRoles.contains($0.role) }
            .reduce(0) { $0 + $1.salary }
        let scoutDescriptor = FetchDescriptor<Scout>(
            predicate: #Predicate { $0.careerID == cid && $0.teamID == teamID }
        )
        let fetchedScouts = (try? modelContext.fetch(scoutDescriptor)) ?? []
        scoutCount = StaffSlots.filledScoutSlots(scouts: fetchedScouts)
        // Handed to `DraftPrepProgress` by the Path to the Draft hero card;
        // re-assigned here so popping back from the scouting hub (which runs
        // `refreshStaffTile` via `.onAppear`) re-evaluates the card.
        scouts = fetchedScouts
        coachingBudgetTotal = budgetTotal
        coachingBudgetRemaining = budgetTotal - coachSalaryUsed

        // The advance gate must still catch an overspent medical or scouting
        // pot even though the tile shows the coaching pot alone — narrowing
        // the tile's formula must not silently widen what the week lets pass.
        let medicalUsed = coaches
            .filter { medicalRoles.contains($0.role) }
            .reduce(0) { $0 + $1.salary }
        let scoutUsed = fetchedScouts.reduce(0) { $0 + $1.salary }
        let medicalRemaining = (team?.owner?.medicalBudget ?? 0) - medicalUsed
        let scoutingRemaining = (team?.owner?.scoutingBudget ?? 0) - scoutUsed
        staffPotOverage = max(0, -(budgetTotal - coachSalaryUsed))
            + max(0, -medicalRemaining)
            + max(0, -scoutingRemaining)

        // Last, because it reads the `scouts` this function just wrote. Hung
        // here rather than on `loadAllDataBody` alone so the pop-back path —
        // which is exactly the trip that spends interview slots and reserves
        // pro-day schools — refreshes the card too (#fleet review F8).
        refreshDraftPrepCache()
    }

    private func loadAllDataBody() {
        guard let teamID = career.teamID else { return }

        // All teams
        let cid = career.id
        let allTeamsDescriptor = FetchDescriptor<Team>(
            predicate: #Predicate { $0.careerID == cid }
        )
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

        // Camp position battles (real rows, see `loadPositionBattles`).
        loadPositionBattles()

        // Team morale (#82) — average of all player morale
        if !players.isEmpty {
            teamMorale = players.reduce(0) { $0 + $1.morale } / players.count
            // Chemistry is a separate engine number (leadership vs. toxicity),
            // not a morale average — read it from the same source the Locker
            // Room screen uses so both screens agree on the tier.
            teamChemistry = LockerRoomEngine.calculateChemistry(
                players: players, collectEvents: false
            ).teamChemistry
        }

        // Position group grades (#17)
        positionGroupGrades = calculatePositionGroupGrades(players: players)

        // Coach count + head coach + the staff tile's budget numbers.
        refreshStaffTile()

        // Division teams
        if let myTeam = team {
            divisionTeams = allTeams.filter {
                $0.conference == myTeam.conference && $0.division == myTeam.division
            }
        }

        // Games for schedule info
        let seasonYear = career.currentSeason
        let gameDescriptor = FetchDescriptor<Game>(predicate: #Predicate {
            $0.careerID == cid && $0.seasonYear == seasonYear
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
            // R19: late-season stakes line for the hero card.
            seasonStakes = computeSeasonStakes(
                myTeam: myTeam,
                allTeams: allTeams,
                allRecords: allRecords,
                divisionStandings: divisionRecords,
                allGames: allGames
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
                $0.careerID == cid && $0.seasonYear == prevYear
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

        // Camp Phase 1: surface the most recent Hard Knocks event as a toast.
        loadLatestHardKnocksEvent()
    }

    /// Camp Phase 1 wire-up: fetch the newest Hard Knocks event and present it
    /// as a bottom toast if it is fresh (occurred within the last 30 seconds)
    /// and not yet displayed in this session.
    private func loadLatestHardKnocksEvent() {
        let cid = career.id
        var descriptor = FetchDescriptor<HardKnocksEvent>(
            predicate: #Predicate { $0.careerID == cid },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let events = (try? modelContext.fetch(descriptor)) ?? []
        guard let newest = events.first else {
            latestHardKnocksEvent = nil
            return
        }
        // Only surface fresh events (≤30s old) that haven't been shown yet.
        let isFresh = abs(newest.occurredAt.timeIntervalSinceNow) <= 30
        if isFresh && !shownHardKnocksEventIDs.contains(newest.id) {
            latestHardKnocksEvent = newest
        } else {
            latestHardKnocksEvent = nil
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

    // MARK: - Season Stakes (R19)

    /// Derives a single stakes statement for this week's game — conservatively.
    /// Every branch must be provably true from raw win counts (equal schedule
    /// lengths, no tiebreaker guessing); when ties muddy the math, or the claim
    /// depends on results we can't guarantee, we return nil instead.
    private func computeSeasonStakes(
        myTeam: Team,
        allTeams: [Team],
        allRecords: [StandingsRecord],
        divisionStandings: [StandingsRecord],
        allGames: [Game]
    ) -> SeasonStakes? {
        // Late season only, and only while this week's game is still unplayed.
        guard career.currentPhase == .regularSeason || career.currentPhase == .tradeDeadline,
              career.currentWeek >= 10,
              let nextGame = allGames.first(where: {
                  !$0.isPlayoff && !$0.isPlayed && $0.week == career.currentWeek
                      && ($0.homeTeamID == myTeam.id || $0.awayTeamID == myTeam.id)
              }),
              let myRecord = divisionStandings.first(where: { $0.teamID == myTeam.id })
        else { return nil }

        // Ties break the "more wins = higher percentage" shortcut — bail out.
        guard divisionStandings.allSatisfy({ $0.ties == 0 }) else { return nil }

        /// Unplayed regular-season games left on a team's schedule (this
        /// week's game included).
        func remainingGames(_ teamID: UUID) -> Int {
            allGames.filter {
                !$0.isPlayoff && !$0.isPlayed
                    && ($0.homeTeamID == teamID || $0.awayTeamID == teamID)
            }.count
        }

        let divisionName = "\(myTeam.conference.rawValue) \(myTeam.division.rawValue)"
        let rivals = divisionStandings.filter { $0.teamID != myTeam.id }

        // 1. "Win clinches the NFC North" — I lead the division, no rival can
        //    reach my post-win total even by winning out, and it isn't already
        //    clinched (the win must actually matter).
        if divisionStandings.first?.teamID == myTeam.id {
            let clinchedByWin = rivals.allSatisfy {
                $0.wins + remainingGames($0.teamID) < myRecord.wins + 1
            }
            let alreadyClinched = rivals.allSatisfy {
                $0.wins + remainingGames($0.teamID) < myRecord.wins
            }
            if clinchedByWin && !alreadyClinched {
                return SeasonStakes(text: "Win clinches the \(divisionName)", urgent: false)
            }
        }

        // 2. "Division lead on the line vs CHI" — this week's opponent is a
        //    division rival with my exact record, and we are the division's
        //    top two: the winner holds sole possession of the lead.
        let oppID = nextGame.homeTeamID == myTeam.id ? nextGame.awayTeamID : nextGame.homeTeamID
        if let oppTeam = allTeamsByID[oppID],
           oppTeam.conference == myTeam.conference, oppTeam.division == myTeam.division,
           let oppRecord = divisionStandings.first(where: { $0.teamID == oppID }),
           oppRecord.wins == myRecord.wins, oppRecord.losses == myRecord.losses {
            let topTwo = Set(divisionStandings.prefix(2).map(\.teamID))
            if topTwo.contains(myTeam.id) && topTwo.contains(oppID) {
                return SeasonStakes(
                    text: "Division lead on the line vs \(oppTeam.abbreviation)",
                    urgent: false
                )
            }
        }

        // 3. "Must win to stay in the hunt" — a loss leaves me unable to reach
        //    even the CURRENT win total of the nearest playoff target (division
        //    leader or the 7 seed), while a win keeps that total reachable.
        //    Targets only add wins from here, so the elimination claim is safe.
        guard let leader = divisionStandings.first, leader.teamID != myTeam.id else { return nil }
        let confStandings = StandingsCalculator.conferenceStandings(
            records: allRecords, teams: allTeams, conference: myTeam.conference
        )
        guard let seed7 = confStandings.indices.contains(6) ? confStandings[6] : nil,
              seed7.ties == 0
        else { return nil }
        let target = min(leader.wins, seed7.wins)
        let myCeiling = myRecord.wins + remainingGames(myTeam.id)
        if myCeiling - 1 < target, myCeiling >= target {
            return SeasonStakes(text: "Must win to stay in the hunt", urgent: true)
        }

        return nil
    }

    // MARK: - Career Role Helpers

    private var isGMAndHC: Bool {
        career.role == .gmAndHeadCoach
    }

    // MARK: - Phase-Aware Hero Card

    @ViewBuilder
    private var phaseHeroCard: some View {
        switch career.currentPhase {
        case .otas, .trainingCamp:
            campHeroCard
        case .preseason:
            preseasonHeroCard
        case .rosterCuts:
            rosterCutsHeroCard
        case .regularSeason, .tradeDeadline:
            regularSeasonHeroCard
        case .playoffs:
            playoffsHeroCard
        // #123a: the two phases the draft-prep pipeline actually runs in share
        // ONE card, because the action it offers comes from the prep state
        // machine and not from the phase. (`.freeAgency` keeps its own card —
        // the market has its own step machine and `DraftPrepStep.phase`
        // deliberately excludes it. `.draft` keeps its own — the room is open.)
        case .combine, .proDays:
            pathToDraftHeroCard
        case .freeAgency:
            faHeroCard
        case .draft:
            draftHeroCard
        case .coachingChanges, .reviewRoster:
            offseasonOpenerHeroCard
        case .proBowl, .superBowl:
            seasonClimaxHeroCard
        }
    }

    // Generic shell for all hero cards
    @ViewBuilder
    private func phaseCardBase<Content: View>(
        icon: String,
        accent: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                Spacer()
            }
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                content()
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.lg)
        // A floor, not a fixed height: 220 padded the sparser cards (regular
        // season carries two stat rows, not four) with a visible void under
        // the buttons. 160 keeps a hero presence while letting the card hug.
        .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [accent.opacity(0.18), Color.backgroundSecondary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: DSCornerRadius.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .strokeBorder(accent.opacity(0.45), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func heroHeader(_ text: String) -> some View {
        Text(text)
            .font(.title2.weight(.heavy))
            .foregroundStyle(Color.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }

    @ViewBuilder
    private func heroStatRow(_ label: String, value: String, accent: Color = .accentGold) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(accent)
        }
    }

    @ViewBuilder
    private func heroActionLink(title: String, destination: TaskDestination) -> some View {
        Button {
            onTaskSelected(destination)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(Color.backgroundPrimary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, 8)
            .background(Color.accentGold, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Phase-specific hero cards

    private var campHeroCard: some View {
        let dayNum = max(1, min(21, career.currentWeek == 0 ? 7 : career.currentWeek))
        return phaseCardBase(icon: "figure.strengthtraining.traditional", accent: .accentGold) {
            heroHeader("Training Camp · Day \(dayNum) / 21")
            heroStatRow("Workload heatmap", value: "18% overloaded")
            heroStatRow("Active battles", value: "3")
            heroStatRow("Top camp grade", value: bestPlayer.map { "\($0.lastName) · A+" } ?? "—  · A+")
            heroActionLink(title: "View Training Plan", destination: .roster)
        }
    }

    private var preseasonHeroCard: some View {
        let gameNum = max(1, min(3, career.currentWeek))
        return phaseCardBase(icon: "sportscourt.fill", accent: .accentGold) {
            heroHeader("Preseason · Game \(gameNum) / 3")
            heroStatRow("Snap distribution", value: "60% starters / 40% backups")
            heroStatRow("Surprise breakouts", value: "2")
            heroStatRow("Injury risk", value: "Low")
            heroActionLink(title: "View Snap Counts", destination: .roster)
        }
    }

    private var rosterCutsHeroCard: some View {
        phaseCardBase(icon: "scissors", accent: .draftStealGold) {
            heroHeader("Roster Cuts · 90 → 53")
            heroStatRow("Stage", value: "Cut 1 of 3 (90→75)")
            // Task #87 / F18: "Cap savings projected $4.2M" was a literal. There
            // is no cut plan to project from at this point in the flow, so the
            // row is gone rather than invented — current room is a real number.
            heroStatRow("Cap room", value: formatCap(team?.availableCap ?? 0))
            heroStatRow("Practice squad protected", value: "7")
            heroActionLink(title: "Make Cuts", destination: .roster)
        }
    }

    private var regularSeasonHeroCard: some View {
        // The matchup this card describes: this week's game whether or not
        // it's been played yet; falls back to the next scheduled game
        // (upcomingGames only holds unplayed ones, so it alone would skip
        // ahead to next week's opponent as soon as the game finishes).
        let currentWeekPlayed = lastGame.flatMap { $0.week == career.currentWeek ? $0 : nil }
        let heroGame = currentWeekPlayerGame ?? currentWeekPlayed ?? upcomingGames.first
        let week = heroGame?.week ?? career.currentWeek
        let nextOpponent = heroGame.flatMap { game -> (abbr: String, isHome: Bool)? in
            let isHome = game.homeTeamID == career.teamID
            let oppID = isHome ? game.awayTeamID : game.homeTeamID
            return allTeamsByID[oppID].map { (abbr: $0.abbreviation, isHome: isHome) }
        }
        let oppText: String = {
            if let opp = nextOpponent {
                return opp.isHome ? "vs \(opp.abbr) (Home)" : "@ \(opp.abbr) (Away)"
            }
            return "vs TBD"
        }()
        // No game scheduled this week and none played this week = bye.
        let isByeWeek = currentWeekPlayerGame == nil && currentWeekPlayed == nil
        let playerTeam = career.teamID.flatMap { allTeamsByID[$0] }
        let injuredCount = players.filter(\.isInjured).count
        return phaseCardBase(icon: "calendar.badge.clock", accent: .accentGold) {
            heroHeader(isByeWeek
                       ? "Week \(career.currentWeek) · Bye Week"
                       : "Week \(week) · \(oppText)")
            // R19: late-season stakes — only rendered when provably true.
            if let stakes = seasonStakes {
                HStack(spacing: 6) {
                    Image(systemName: stakes.urgent ? "exclamationmark.triangle.fill" : "flame.fill")
                        .font(.caption.weight(.bold))
                    Text(stakes.text)
                        .font(.footnote.weight(.heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(stakes.urgent ? Color.danger : Color.accentGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    (stakes.urgent ? Color.danger : Color.accentGold).opacity(0.14),
                    in: Capsule()
                )
            }
            heroStatRow("Record", value: playerTeam?.record ?? "—")
            heroStatRow("Injuries", value: injuredCount == 0 ? "Fully healthy" : "\(injuredCount) OUT")
            if currentWeekPlayerGame != nil {
                HStack(spacing: DSSpacing.sm) {
                    Button {
                        startCoachedGame()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "headset")
                                .font(.subheadline.weight(.bold))
                            Text("Coach the Game")
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.vertical, 8)
                        .background(Color.accentGold, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onTaskSelected(.gamePlan)
                    } label: {
                        Text("Game Plan")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, DSSpacing.md)
                            .padding(.vertical, 8)
                            .background(Color.accentGold.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else if isByeWeek {
                heroStatRow("This week",
                            value: "Bye — next up \(oppText) in Week \(week)",
                            accent: .accentGold)
                heroActionLink(title: "Set Game Plan", destination: .gamePlan)
            } else {
                let result: (text: String, won: Bool) = {
                    if let g = currentWeekPlayed,
                       let home = g.homeScore, let away = g.awayScore {
                        let isHome = g.homeTeamID == career.teamID
                        let mine = isHome ? home : away
                        let theirs = isHome ? away : home
                        let tag = mine > theirs ? "W" : (mine < theirs ? "L" : "T")
                        return ("\(tag) \(mine)–\(theirs) — advance when ready", mine >= theirs)
                    }
                    return ("Game played — advance when ready", true)
                }()
                heroStatRow("This week", value: result.text, accent: result.won ? .success : .danger)
                heroActionLink(title: "Set Game Plan", destination: .gamePlan)
            }
        }
    }

    private var playoffsHeroCard: some View {
        phaseCardBase(icon: "trophy.fill", accent: .draftStealGold) {
            heroHeader("Playoffs · Wild Card")
            HStack(spacing: 6) {
                ForEach(["WC", "DIV", "CONF", "SB"], id: \.self) { stage in
                    Text(stage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(stage == "WC" ? Color.backgroundPrimary : Color.textTertiary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(stage == "WC" ? Color.accentGold : Color.backgroundTertiary, in: Capsule())
                }
            }
            heroStatRow("Next opponent", value: "Vs Seed #5 · DOME")
            heroStatRow("Vegas line", value: "-3.5 (Favored)")
            heroActionLink(title: "Game Plan", destination: .gamePlan)
        }
    }

    // MARK: Path to the Draft (#123a)

    /// The pre-draft hero card, for `.combine` and `.proDays`.
    ///
    /// **Named after the journey, not the phase**, because what it offers comes
    /// from the draft-prep state machine (``DraftPrepProgress``) rather than
    /// from `career.currentPhase`. The phase and the class's scouted share drop
    /// to the subtitle.
    ///
    /// What it replaces: `combineHeroCard` titled itself "NFL Combine · 42%
    /// scouted" — a literal — invented a top prospect and a riser count, and
    /// derived its CTA from two `tasks` title lookups. A task is *done* the
    /// moment one interview is conducted and never notices the other 59 slots,
    /// so the card printed "Conduct Interviews →" forever: after the ration was
    /// spent it pointed at a room with nothing left to buy, and it never once
    /// offered the advance that was the club's actual next move.
    /// `proDaysHeroCard` was the same card with four different literals.
    private var pathToDraftHeroCard: some View {
        // The cache, or a one-off build on the single body pass that precedes
        // the first `loadAllData` (#fleet review F8).
        let progress = prepProgress ?? buildPrepProgress()
        let stage = progress[progress.current]
        // Is there still something to DO in this stage? A counted stage is
        // workable until its ration is gone — one interview satisfies the
        // required task, 59 unspent slots is still work. An uncounted stage
        // (a read: the combine review, the two mocks) is finished the moment
        // it is satisfied. A calendar-locked stage is nobody's next move.
        //
        // #fleet review F5: a counted stage needs a ration before `done < total`
        // means anything. A club with no scouts hired has 0 pro-day focus slots,
        // so `.proDayFocus` read 0 < 0 == false — "ration spent" — and the card
        // offered "Advance to NFL Draft" over the one stage whose work the user
        // had not started and could still fix by hiring somebody. With no ration
        // at all the honest question is the uncounted one: has it been satisfied.
        let hasWorkLeft = stage.unlocked
            && ((stage.isCounted && stage.total > 0)
                ? stage.done < stage.total
                : !stage.isSatisfied)

        return phaseCardBase(icon: "flag.checkered", accent: .accentGold) {
            heroHeader("Path to the Draft")
            Text("\(career.currentPhase.displayName) \u{00B7} \(draftClassScoutedPercent)% scouted")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            heroStatRow("Current stage", value: stage.step.displayName)
            heroStatRow("Progress", value: stage.counter)
            heroStatRow("Stages worked",
                        value: "\(progress.satisfiedStageCount) / \(progress.stages.count)")

            if hasWorkLeft, let action = draftPrepStageAction(for: stage.step) {
                // The stage still has room: ONE button, naming the work, deep
                // linked to the hub tab that surface lives on.
                heroPrimaryButton(title: action.title) {
                    openScoutingHub(tab: action.tab)
                }
            } else {
                // Ration spent (or the stage is a read that has been read):
                // the board, and the move the sidebar's Advance would make.
                HStack(spacing: DSSpacing.sm) {
                    heroSecondaryButton(title: "Show Prospects") {
                        openScoutingHub(tab: "board")
                    }
                    if let nextPhase = nextPreDraftPhaseName {
                        heroPrimaryButton(title: "Advance to \(nextPhase)",
                                          enabled: canAdvance) {
                            // The SAME action the sidebar's Advance runs —
                            // guard rails, coaching-budget gate and all. There
                            // is exactly one advance path on this screen.
                            performAdvance()
                        }
                    }
                }
                if !canAdvance {
                    // #fleet review F19e: no coaching-budget branch here. This
                    // card renders for `.combine` and `.proDays` only, and
                    // `isBlockedByCoachingBudget` is `.coachingChanges`-only, so
                    // the other half of that ternary was unreachable — the
                    // remaining required tasks are the only thing that can be
                    // holding an advance on this screen.
                    Text("Finish the required tasks in the left panel to advance.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    /// The draft-prep state machine, built exactly the way `CareerShellView`
    /// builds it for the task list — one authority, one set of counters.
    ///
    /// Costs no fetch of its own: the class is already in memory
    /// (`WeekAdvancer.currentDraftClass`, the same source the Scouting tile
    /// reads) and the department comes off `refreshStaffTile`'s scout fetch.
    private func buildPrepProgress() -> DraftPrepProgress {
        DraftPrepProgress(
            career: career,
            prospects: WeekAdvancer.currentDraftClass,
            scouts: scouts
        )
    }

    /// Share of this cycle's class with a scouting report THIS regime ordered.
    ///
    /// Counted off filed reports rather than `scoutedOverall` so this card and
    /// the scouting hub's own header mean the same thing by "scouted", and
    /// through `ProspectFog.hasOwnReport` so neither of them counts the
    /// inherited "Previous Staff" baseline as work the user did (#124).
    ///
    /// #fleet review F16: over the DECLARING class, which is the hub header's
    /// denominator (`ScoutingHubView.loadData` filters `isDeclaringForDraft`
    /// before it counts). The whole class carries the underclassmen who stayed
    /// in school; counting them dragged this card's percentage below the number
    /// printed at the top of the screen it deep-links into, for the same work.
    private func computeDraftClassScoutedPercent() -> Int {
        let draftClass = WeekAdvancer.currentDraftClass.filter { $0.isDeclaringForDraft }
        guard !draftClass.isEmpty else { return 0 }
        let scouted = draftClass.filter(ProspectFog.hasOwnReport).count
        return Int((Double(scouted) / Double(draftClass.count) * 100).rounded())
    }

    /// Refills the Path to the Draft card's cache. See `prepProgress`.
    private func refreshDraftPrepCache() {
        prepProgress = buildPrepProgress()
        draftClassScoutedPercent = computeDraftClassScoutedPercent()
        // Only while the room is open — outside the draft phase the card is not
        // rendered and the walk would be pure cost.
        draftHero = career.currentPhase == .draft ? buildDraftHeroState() : nil
    }

    /// The stage's work in button voice, plus the scouting-hub tab it lives on.
    ///
    /// `nil` for `.ready`, which is the draft room rather than a stage with
    /// something to buy.
    private func draftPrepStageAction(for step: DraftPrepStep) -> (title: String, tab: String)? {
        switch step {
        case .combineReview: return ("Review Combine Results", "combine")
        case .interviews:    return ("Conduct Interviews", "interviews")
        case .filmStudy:     return ("Order Film Study", "film")
        case .proDayFocus:   return ("Choose Pro-Day Schools", "proDays")
        case .workouts:      return ("Invite Prospects to Work Out", "workouts")
        case .mockOne:       return ("Read Mock 1.0", "mockDraft")
        case .top30Visits:   return ("Host Top-30 Visits", "top30")
        case .mockTwo:       return ("Read the Final Mock", "mockDraft")
        case .ready:         return nil
        }
    }

    /// Opens the scouting hub on a named tab.
    ///
    /// `scoutingPendingTab` is the hint `ScoutingHubView` reads in its `.task`
    /// and clears; set it exactly the way `CareerShellView.handleTaskNavigation`
    /// sets it for the stage task destinations, then push the hub. A hint whose
    /// tab does not exist is ignored by the hub, so this can never dead-end.
    private func openScoutingHub(tab: String) {
        CareerScopedDefaults.set(tab, "scoutingPendingTab")
        onTaskSelected(.scouting)
    }

    /// The phase the sidebar's Advance button would move to.
    ///
    /// Read off `SeasonPhaseGroup.preDraft.subPhases` — the pre-draft calendar,
    /// in order — so this card cannot drift from the real phase order.
    ///
    /// #fleet review F19d: named through `SeasonPhase.displayName`, the same
    /// accessor the card's own subtitle two lines up uses. It used to go through
    /// `TimelineTasksPanel.phaseName`, which calls `.proDays` "Pro Days &
    /// Workouts" — so one card could read "Pro Days · 42% scouted" in its
    /// subtitle and offer "Advance to Pro Days & Workouts" underneath, two names
    /// for the week the user is being moved into.
    private var nextPreDraftPhaseName: String? {
        let window = SeasonPhaseGroup.preDraft.subPhases
        guard let i = window.firstIndex(of: career.currentPhase),
              i + 1 < window.count else { return nil }
        return window[i + 1].displayName
    }

    /// Gold primary capsule — the shape `heroActionLink` draws, over an
    /// arbitrary action rather than a plain push.
    @ViewBuilder
    private func heroPrimaryButton(
        title: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(enabled ? Color.backgroundPrimary : Color.textTertiary)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, 8)
            .background(enabled ? Color.accentGold : Color.backgroundTertiary, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    /// Tinted secondary capsule — same shape the regular-season card's "Game
    /// Plan" button uses.
    @ViewBuilder
    private func heroSecondaryButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentGold)
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, 8)
                .background(Color.accentGold.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var faHeroCard: some View {
        let stepLabel = FreeAgencyStep(rawValue: career.freeAgencyStep)?.rawValue.capitalized ?? "Open"
        return phaseCardBase(icon: "dollarsign.circle.fill", accent: .accentGold) {
            heroHeader("Free Agency · \(stepLabel) · \(formatCap(team?.availableCap ?? 0)) cap")
            heroStatRow("Frenzy", value: "7 hot · 2 outbid alerts")
            heroStatRow("Top targets remaining", value: "5")
            heroStatRow("Pending offers", value: "3")
            heroActionLink(title: "Open Bidding Room", destination: .freeAgency)
        }
    }

    // `proDaysHeroCard` is gone: `.proDays` renders `pathToDraftHeroCard` now.
    // Every row it drew was a literal ("12 / 30 visits used", "8 colleges",
    // "+11%") and its CTA ignored the pro-day rations entirely.

    /// The draft-phase hero.
    ///
    /// Every row on this card was a literal, and the worst of them named three
    /// real NFL quarterbacks (task #147) — through and after a draft sitting at
    /// pick #31 it read "Round 1 · Pick 14 / #14 (3 picks away) / Williams ·
    /// Daniels · Maye". Real players must never ship in generated content.
    ///
    /// It now reads the live board off the same in-memory sources the Draft tile
    /// and the scouting hub use: `WeekAdvancer.currentDraftPicks` for the order
    /// and the user's own board (`UserDraftBoard`) for the targets. Everything
    /// printed is a name, a position and a slot — public information; no grade,
    /// no `trueOverall`. When there is no live board to read (a save that
    /// reaches the phase before the order exists) the card says so instead of
    /// inventing specifics.
    private var draftHeroCard: some View {
        let state = draftHero ?? buildDraftHeroState()
        return phaseCardBase(icon: "pencil.and.list.clipboard", accent: .draftStealGold) {
            heroHeader(state.header)
            heroStatRow("Your next pick", value: state.nextPick)
            if let targets = state.targets {
                heroStatRow(state.targetsLabel, value: targets)
            }
            heroStatRow("Picks left tonight", value: state.picksRemaining)
            heroActionLink(title: "Enter Draft", destination: .draft)
        }
    }

    /// What the draft hero prints, built once per load (see `draftHero`).
    struct DraftHeroState {
        let header: String
        let nextPick: String
        let targetsLabel: String
        let targets: String?
        let picksRemaining: String
    }

    private func buildDraftHeroState() -> DraftHeroState {
        let picks = WeekAdvancer.currentDraftPicks
            .filter { $0.seasonYear == career.currentSeason }
            .sorted { $0.pickNumber < $1.pickNumber }
        let remaining = picks.filter { !$0.isComplete }
        let onClock = remaining.first

        let header: String = {
            guard let onClock else {
                return picks.isEmpty
                    ? "Draft Day"
                    : "Draft complete · \(picks.count) picks in"
            }
            return "Draft · Round \(onClock.round) · Pick \(onClock.pickNumber)"
        }()

        let userNext = remaining.first { $0.currentTeamID == career.teamID }
        let userRemaining = remaining.filter { $0.currentTeamID == career.teamID }.count
        let nextPick: String = {
            guard let userNext else { return "No picks remaining" }
            let away = remaining.filter { $0.pickNumber < userNext.pickNumber }.count
            if away == 0 { return "#\(userNext.pickNumber) — you are on the clock" }
            return "#\(userNext.pickNumber) (\(away == 1 ? "1 pick" : "\(away) picks") away)"
        }()

        // Men still on the board: `completePick` clears `isDeclaringForDraft` as
        // each card goes in, so the declared set IS the live pool.
        let available = WeekAdvancer.currentDraftClass.filter(\.isDeclaringForDraft)
        let marked = DraftIntel.markedTargets(in: available)
        let pool = marked.isEmpty ? UserDraftBoard.sorted(available) : marked
        let targets = pool.prefix(3)
            .map { "\($0.position.rawValue) \($0.lastName)" }
            .joined(separator: " · ")

        return DraftHeroState(
            header: header,
            nextPick: nextPick,
            targetsLabel: marked.isEmpty ? "Top of your board" : "Your marked targets",
            targets: targets.isEmpty ? nil : targets,
            picksRemaining: userRemaining == 1 ? "1 of yours" : "\(userRemaining) of yours"
        )
    }

    /// Next league year's room: the projected cap less what is actually
    /// committed to that year (task #87 / F18 replaced the literal "$58.4M"
    /// here; #127 fixed what it was subtracting).
    ///
    /// It used to subtract `team.currentCapUsage` — THIS year's ledger — from
    /// next year's cap, which is wrong twice over and in opposite directions:
    /// it charged next year for every expiring contract that will be off the
    /// books by then, and, once the tag stopped writing `annualSalary` at apply
    /// time, it missed the franchise tag entirely. The row sat directly under
    /// the offseason hero card's other numbers and disagreed with all of them.
    ///
    /// Now it is the same definition `FranchiseTagView`'s banner uses: contracts
    /// that still run next year, plus tags booked for it, against the projected
    /// cap. One arithmetic, so the dashboard and the tag screen cannot show the
    /// user two different 2027s.
    private var nextYearCapSpace: String {
        guard let team else { return "—" }
        let nextCap = Double(team.salaryCap) * (1.0 + ContractEngine.capGrowthPerSeason)
        let underContract = players
            .filter { $0.contractYearsRemaining > 1 && !$0.isFranchiseTagged }
            .reduce(0) { $0 + $1.annualSalary }
        let tags = CommittedCapLedger.forwardCommitted(
            playerIDs: players.filter(\.isFranchiseTagged).map(\.id),
            careerID: career.id,
            season: career.currentSeason + 1
        )
        // Negative room is a real state (a club can be committed past next
        // year's projected cap), and `formatCap` renders it as "$-8.3M" — a
        // string that reads as a typo rather than as a problem. Named instead.
        let capSpace = Int(nextCap) - underContract - tags
        return capSpace >= 0 ? formatCap(capSpace) : "Over by " + formatCap(-capSpace)
    }

    /// Staff whose deals run out with this league year (#127 — it was the
    /// literal `"2"`).
    ///
    /// `contractYearsRemaining <= 1` is the same test `CoachDetailView` renders
    /// its expiry warning from and the same one the player-side expiring list
    /// uses, so the hero card and the staff screen cannot disagree about who is
    /// about to walk. `allCoaches` is already fetched for the club, scoped to the
    /// open save (`loadCoaches`), so this costs nothing.
    private var expiringCoachCount: Int {
        allCoaches.filter { $0.contractYearsRemaining <= 1 }.count
    }

    /// Roster OVR now, and what it becomes if nobody on an expiring deal is kept
    /// (#127 — it was the literal `"76 → 73 projected"`).
    ///
    /// There is no OVR-projection engine in the game to read, so rather than
    /// invent one this states the only projection the data actually supports and
    /// labels it honestly: the average the club would field if every expiring
    /// contract walked. That is a real number, it is the number this screen's own
    /// "Roster Review" button leads to, and it is the one a GM opening his
    /// offseason wants — the size of the hole.
    ///
    /// The average is the whole-roster one (`Σ overall / count`), which is the
    /// definition `FACompleteView`'s before/after and `NewLeagueYearView`'s
    /// pre-FA snapshot already use; taking a different one here would make the
    /// dashboard disagree with the two screens that report the same move.
    ///
    /// `nil` — and the row is dropped — when the club has no expiring contracts
    /// at all, because "76 → 76" is a row that says nothing.
    private var rosterOVRProjection: String? {
        guard !players.isEmpty else { return nil }
        let current = players.reduce(0) { $0 + $1.overall } / players.count
        // Franchise-tagged men are NOT leaving: the tag is one more year of club
        // control and the rollover keeps them on the roster (#127).
        let retained = players.filter { $0.contractYearsRemaining > 1 || $0.isFranchiseTagged }
        guard retained.count < players.count else { return nil }
        guard !retained.isEmpty else { return "\(current) → — (whole roster expiring)" }
        let projected = retained.reduce(0) { $0 + $1.overall } / retained.count
        return "\(current) → \(projected) if none re-signed"
    }

    private var offseasonOpenerHeroCard: some View {
        phaseCardBase(icon: "arrow.triangle.2.circlepath", accent: .accentGold) {
            heroHeader("Offseason Begins")
            heroStatRow("Coach contracts expiring", value: "\(expiringCoachCount)")
            if let rosterOVRProjection {
                heroStatRow("Roster OVR", value: rosterOVRProjection)
            }
            heroStatRow("Cap space (next yr)", value: nextYearCapSpace)
            HStack(spacing: DSSpacing.sm) {
                heroActionLink(title: "Roster Review", destination: .rosterEvaluation)
                heroActionLink(title: "Salary Cap", destination: .capOverview)
            }
        }
    }

    private var seasonClimaxHeroCard: some View {
        let isProBowl = career.currentPhase == .proBowl
        return phaseCardBase(icon: isProBowl ? "star.fill" : "trophy.circle.fill", accent: .draftStealGold) {
            heroHeader(isProBowl ? "Pro Bowl" : "Super Bowl")
            heroStatRow("Pro Bowlers", value: "4")
            heroStatRow("MVP candidates", value: "1")
            heroStatRow("Awards results", value: "Pending")
            heroActionLink(title: "View Awards", destination: .news)
        }
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
        // maxHeight stretches every tile to its grid row's height, so a short
        // tile (Roster) no longer floats vertically centered beside a tall one
        // (Team) — paired cards share a top edge *and* a bottom edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var allRoles: [CoachRole] { StaffSlots.coachRoles(for: career.role) }

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
                // The inline confirm button lives at the BOTTOM of a scroll that
                // runs staff list → schemes → warnings, so on a short sheet it is
                // below the fold and the only visible action is Cancel — which
                // reads as "this screen cannot advance". The bar copy of it is
                // always on screen.
                ToolbarItem(placement: .confirmationAction) {
                    Button(missingRequiredRoles.isEmpty ? "Advance" : "Advance Anyway") {
                        onConfirm()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(missingRequiredRoles.isEmpty ? Color.accentGold : Color.warning)
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
                // #133: labelled for the population it counts. Bare "STAFF"
                // here read as a contradiction of the dashboard tile's
                // "23 / 23 Staff" — that one includes the scouting department,
                // this list is the coaching seats it enumerates below.
                Text("COACHING STAFF")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)
                Spacer()
                Text("\(StaffSlots.filledCoachSlots(coaches: coaches, careerRole: career.role))/\(allRoles.count) filled")
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
            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
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

            // Team scheme banner
            teamSchemeBanner

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

    // MARK: - Team Scheme Banner

    private var teamSchemeBanner: some View {
        HStack(spacing: 0) {
            // Offensive scheme
            HStack(spacing: 5) {
                Image(systemName: "football.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.accentBlue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OFFENSE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(0.3)
                    Text(oc?.offensiveScheme?.displayName ?? "Not Set")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(oc?.offensiveScheme != nil ? Color.textPrimary : Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.surfaceBorder.opacity(0.5))
                .frame(width: 1, height: 28)

            // Defensive scheme
            HStack(spacing: 5) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.danger)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DEFENSE")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(0.3)
                    Text(dc?.defensiveScheme?.displayName ?? "Not Set")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(dc?.defensiveScheme != nil ? Color.textPrimary : Color.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
        }
        .padding(8)
        .background(Color.backgroundTertiary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.surfaceBorder.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - Scheme Fit Indicator

    /// Returns the coach's expertise level for the team's active scheme on their side.
    private func coachTeamSchemeExpertise(_ coach: Coach) -> Int? {
        let offensiveRoles: [CoachRole] = [.headCoach, .assistantHeadCoach, .offensiveCoordinator, .qbCoach, .rbCoach, .wrCoach, .olCoach]
        let defensiveRoles: [CoachRole] = [.defensiveCoordinator, .dlCoach, .lbCoach, .dbCoach]

        if offensiveRoles.contains(coach.role), let scheme = oc?.offensiveScheme {
            return coach.expertise(for: scheme.rawValue)
        } else if defensiveRoles.contains(coach.role), let scheme = dc?.defensiveScheme {
            return coach.expertise(for: scheme.rawValue)
        }
        return nil
    }

    private func schemeFitColor(_ expertise: Int) -> Color {
        if expertise >= 70 { return .success }
        if expertise >= 40 { return .warning }
        return .danger
    }

    @ViewBuilder
    private func schemeFitIndicator(for coach: Coach) -> some View {
        if let expertise = coachTeamSchemeExpertise(coach) {
            let color = schemeFitColor(expertise)
            HStack(spacing: 3) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text("\(expertise)")
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
            }
        }
    }

    // MARK: - Scheme Mismatch Warnings

    private func schemeMismatchWarning(for coach: Coach) -> String? {
        // Only show warnings for OC and DC
        if coach.role == .offensiveCoordinator,
           let teamScheme = oc?.offensiveScheme,
           let coachScheme = coach.offensiveScheme,
           coachScheme != teamScheme {
            let expertise = coach.expertise(for: teamScheme.rawValue)
            if expertise < 40 {
                return "\(coach.role.abbreviation) specializes in \(coachScheme.displayName) but team runs \(teamScheme.displayName)"
            }
        }
        if coach.role == .defensiveCoordinator,
           let teamScheme = dc?.defensiveScheme,
           let coachScheme = coach.defensiveScheme,
           coachScheme != teamScheme {
            let expertise = coach.expertise(for: teamScheme.rawValue)
            if expertise < 40 {
                return "\(coach.role.abbreviation) specializes in \(coachScheme.displayName) but team runs \(teamScheme.displayName)"
            }
        }
        return nil
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
