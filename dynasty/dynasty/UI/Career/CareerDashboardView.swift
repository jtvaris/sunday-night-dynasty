import SwiftUI
import SwiftData

struct CareerDashboardView: View {

    @Bindable var career: Career
    @Binding var tasks: [GameTask]
    @Binding var inboxMessages: [InboxMessage]
    var onTaskSelected: (TaskDestination) -> Void
    var onAdvance: (() -> Void)? = nil
    /// Fired when a week's result is persisted from THIS screen rather than by
    /// a week advance — i.e. after a coached game.
    ///
    /// The shell owns the season week ladder and rebuilt it only in
    /// `loadShellData`, which a coached game never reaches: the score landed in
    /// the store, this screen's own `loadAllData()` picked it up, and the band
    /// pinned above kept drawing the fixture as unplayed until the next
    /// Advance. Two week-scoped labels disagreeing about one fixture is the
    /// #154 bug class, so the shell gets told instead.
    var onWeekResultRecorded: () -> Void = {}
    /// #37: flipped true by the Game Plan screen's "Start Game" button after it
    /// pops back to the dashboard, so the coached game launches from here (the
    /// owner of `coachedSession` / the fullScreenCover). Reset on consumption.
    var launchCoachedGame: Binding<Bool> = .constant(false)
    /// The gates only the SHELL can see — the roster ceiling, the cap and the
    /// depth-chart holes `performShellAdvance` refuses on. Handed down so the
    /// rail's Advance button can grey itself out and NAME the refusal instead of
    /// rendering solid gold and then throwing a modal after the tap. Nil in
    /// standalone use, where the staff ledger below is the only gate there is.
    var shellAdvanceBlocker: AdvanceBlocker? = nil
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @State private var team: Team?
    @State private var rosterCount: Int = 0
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
    /// #133: the ONE staff reading this screen has — seats, pots and the
    /// advance gate all come off it. It used to be four loose `@State` ints
    /// (`coachCount`, `scoutCount`, `coachingBudgetTotal`,
    /// `coachingBudgetRemaining`, `staffPotOverage`) computed here with a role
    /// filter and a `?? 0` fallback of this screen's own, which is how the tile
    /// and the Staff screen printed different money for the same club.
    /// Rebuilt by `refreshStaffTile`.
    @State private var staffLedger: StaffLedger?
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

    /// True from the tap on Advance until the week has finished advancing.
    ///
    /// Owned here rather than in the rail because this screen owns both advance
    /// paths — its own `WeekAdvancer` call and the shell's, through `onAdvance`
    /// — so one flag covers whichever one is wired. See `runAdvance`.
    @State private var isAdvancing = false

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

    /// The saved camp `TrainingPlan` split and the saved `OpponentPrepWeek`
    /// split for the current key, as plain values.
    ///
    /// Both tiles printed their OPTIONS ("Tactical / Physical / Technical",
    /// "General vs opponent focus") where the decision belongs, so the hub was
    /// the one surface that never reflected the choice the user had just made
    /// on the screen it links to. Loaded beside the battles in
    /// `refreshRosterDerived`, which is also the pop-back path.
    @State private var savedTrainingSplit: (tactical: Int, physical: Int, technical: Int)?
    @State private var savedPrepSplit: (general: Int, opponent: Int)?

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

    /// The non-task reason the advance is refused (#154f, #158).
    ///
    /// Handed to the tasks panel, which is the ONE place it is printed, so the
    /// rail cannot go on printing "Complete 0 required tasks to advance" beside
    /// a banner naming a $49K staff overage. Nil when the required-task list is
    /// the only gate.
    ///
    /// #158: the predicate itself now lives on ``StaffLedger`` — the same value
    /// the Season Guide sheet gates on and the same one
    /// `CareerShellView.performShellAdvance` refuses on. This screen used to own
    /// a private copy that only knew about the budget, so the sidebar (which
    /// knew about neither the budget nor the vacant coordinator seats) offered
    /// an advance this one would have declined.
    ///
    /// #208g: the shell's copy wins when there is one. It is computed from the
    /// same prechecks `performShellAdvance` refuses on and already folds the
    /// staff gate in, so the local ledger below is the standalone fallback and
    /// never a second opinion.
    private var advanceBlocker: AdvanceBlocker? {
        shellAdvanceBlocker ?? staffLedger?.advanceBlocker(phase: career.currentPhase)
    }

    private var canAdvance: Bool {
        guard TaskGenerator.allRequiredComplete(in: tasks) else { return false }
        return advanceBlocker == nil
    }

    // `nextActionTask` / `isHeroTaskLocked` are gone with the Next Action hero
    // banner (#105 wave 2). They were a hand-copy of
    // `TimelineTasksPanel.nextActionableTask` / `isTaskLocked` — a second
    // implementation of "which row is next", kept in sync by hand, feeding a
    // second widget that pointed at a row already visible six inches to its
    // left. The rail marks that row itself now.

    /// True while the user's own game for this week is still on the board.
    /// Same fixture the hero card offers to coach (`currentWeekPlayerGame`).
    private var weeklyGameUnplayed: Bool { currentWeekPlayerGame != nil }

    /// The club has no fixture at all this week: nothing on the board and
    /// nothing played.
    ///
    /// Hoisted out of `regularSeasonHeroCard`, which computed it inline, because
    /// the work band's head asks the same question one card higher up the
    /// column. Two labels about one week deriving "is this a bye" separately is
    /// the #154 shape, and it is cheaper to not have two than to keep them
    /// agreeing.
    private var isByeWeek: Bool {
        currentWeekPlayerGame == nil && currentWeekPlayedGame == nil
    }

    /// The user's game for the current week **once it has been played**.
    private var currentWeekPlayedGame: Game? {
        lastGame.flatMap { $0.week == career.currentWeek ? $0 : nil }
    }

    /// Opponent abbreviation of that unplayed game, for confirmation copy.
    private var unplayedGameOpponentAbbr: String? {
        guard let game = currentWeekPlayerGame, let teamID = career.teamID else { return nil }
        let opponentID = game.homeTeamID == teamID ? game.awayTeamID : game.homeTeamID
        return allTeamsByID[opponentID]?.abbreviation
    }

    private var skipGameConfirmTitle: String {
        let opponent = unplayedGameOpponentAbbr.map { " vs \($0)" } ?? ""
        return "Skip your Week \(career.currentWeek) game\(opponent)? It will be simulated."
    }

    // MARK: - Advance Logic

    private func performAdvance() {
        guard canAdvance, !isAdvancing else { return }

        // The user's own game is still unplayed: never let one tap eat it
        // silently. Confirm, then `runAdvance` sims it as part of the week.
        if weeklyGameUnplayed {
            showSkipGameConfirm = true
            return
        }

        runAdvance()
    }

    /// The actual week advance, past the unplayed-game guard rail.
    ///
    /// The work itself is synchronous and main-actor bound — it sims sixteen
    /// games, moves the market and writes the store — so the screen cannot stay
    /// interactive through it. What it CAN do is say so: the rail's button was
    /// simply frozen mid-tap, indistinguishable from an app that had hung, and
    /// a second tap during the freeze was queued rather than dropped. The flag
    /// below disables the control and swaps its label for a spinner, and the
    /// one-frame hop is what lets SwiftUI paint that state before the main
    /// actor is taken. (Running the advance OFF the main actor is the other
    /// half of the parent item and is not attempted here — `advanceWeek` takes
    /// the SwiftData context.)
    private func runAdvance() {
        guard canAdvance, !isAdvancing else { return }

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

        isAdvancing = true
        Task { await runAdvanceWork() }
    }

    private func runAdvanceWork() async {
        defer { isAdvancing = false }
        // One frame of grace before the main actor is taken. Set-the-flag and
        // do-the-work in the same runloop turn commit as ONE transaction, and
        // the busy state is then never drawn at all.
        try? await Task.sleep(nanoseconds: 32_000_000)
        executeAdvance()
    }

    private func executeAdvance() {
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

    /// **The one fixture every week-scoped label on this screen names** (#154).
    ///
    /// This week's game whether or not it has been played, falling back to the
    /// next one scheduled. `upcomingGames` holds only UNPLAYED games, so reading
    /// `.first` off it directly — which the Opponent Scout tile did — skips to
    /// next week's opponent the instant Sunday's result lands. That is how one
    /// screen came to show hero "Week 16 · @ SF (Away)" over a tile reading
    /// "Vs IND": same week, two different clubs, two different lookups.
    ///
    /// `CareerShellView.currentWeekGame` makes the same pick for the task list,
    /// so the third label agrees as well.
    private var currentWeekFixture: Game? {
        let playedThisWeek = lastGame.flatMap { $0.week == career.currentWeek ? $0 : nil }
        return currentWeekPlayerGame ?? playedThisWeek ?? upcomingGames.first
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

        // The COACHED path's opponent-prep boost, and it is no longer the same
        // thing the quick sim applies — the comment that claimed parity here was
        // true until D1 and is not any more. `WeekAdvancer` now hands
        // `GameSimulator` a signed `prepFocusDelta` that both clubs' staffs
        // contest through `OpponentPrep`; `LiveGameEngine` still consumes the
        // old user-only `gameBoost` pair as a per-play momentum nudge.
        //
        // Flagged as a known remaining asymmetry for a later pass rather than
        // fixed here: it is one game in sixteen, and closing it is engine work.
        // Left in place deliberately so nobody "tidies" it into silence.
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
        // The shell's week ladder reads the same fixtures from its own state,
        // and no advance is going to run to refresh it. Serves the playoff path
        // too — the postseason slat comes off the same dictionary.
        onWeekResultRecorded()

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
    /// **Showcase**, no draft-cycle heartbeat — and none of the `.reviewRoster`
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

    /// Which hiring destination fills a given coaching chair.
    ///
    /// All four of these resolve to `ShellDestination.coachingStaff` today —
    /// `CareerShellView.handleTaskNavigation` maps them onto the same screen,
    /// whose default tab is the Staff tab, i.e. the hiring surface. They are
    /// still named per seat rather than collapsed to `.coachingStaff` because
    /// the destination is the only thing the shell is handed, and the day the
    /// three gate seats get their own pre-filtered market (the `.hireHC` /
    /// `.hireOC` / `.hireDC` cases exist for exactly that) this call site
    /// already asks for it.
    private func hireDestination(for role: CoachRole) -> TaskDestination {
        switch role {
        case .headCoach:            return .hireHC
        case .offensiveCoordinator: return .hireOC
        case .defensiveCoordinator: return .hireDC
        default:                    return .hireCoach
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
                hubLayout
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
            // slot numbers. The re-appear path refreshes the staff tile's
            // inputs and the roster's — the full `loadAllData` refetches every
            // game of two seasons on the main thread mid-pop animation, and its
            // `loadLatestHardKnocksEvent` would clear a toast the user may
            // still be reading. First appear is left to `.task` above.
            if hasAppearedOnce {
                refreshStaffTile()
                refreshRosterDerived()
            } else {
                hasAppearedOnce = true
            }
        }
        // The advance belongs to the shell (`onAdvance`), and when the shell
        // runs it NOTHING on this screen re-fires: `.task` is first-open only
        // and `onAppear` needs a pop back onto the hub. So every tile went on
        // quoting the roster and the schedule fetched before free agency, the
        // draft class and the cutdown — a "Players 56" tile beside a rail asking
        // for 12 more cuts off an 87-man roster, on the same screen. The
        // calendar moving is precisely the moment the whole snapshot is stale,
        // so it gets the full load and not the `onAppear` slice. The phase and
        // the week each move without the other: offseason phases advance on a
        // frozen week counter, and Weeks 1-18 never change phase.
        .onChange(of: career.currentPhase) { _, _ in loadAllData() }
        .onChange(of: career.currentWeek) { _, _ in loadAllData() }
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
                    ledger: staffLedger ?? StaffLedger(
                        careerRole: career.role,
                        coaches: allCoaches,
                        scouts: scouts,
                        owner: team?.owner
                    ),
                    onConfirm: {
                        activeSheet = nil
                        confirmCoachingAdvance()
                    },
                    onCancel: {
                        activeSheet = nil
                    },
                    // A vacant seat is the one line the review cannot fix in
                    // place — hiring lives on the Staff screen. Rather than
                    // print "VACANT" and stop there, the row closes the sheet
                    // and asks the shell for the list that fills that chair.
                    onHireSeat: { role in
                        activeSheet = nil
                        onTaskSelected(hireDestination(for: role))
                    },
                    // The sheet can now push `CoachDetailView`, which fires,
                    // extends, promotes and demotes. #133's rule is that this
                    // screen keeps ONE staff reading: a mutation behind the
                    // modal re-derives the ledger here and hands a fresh one
                    // down, so the review can never argue with the advance gate
                    // it is the front end of.
                    onStaffChanged: { refreshStaffTile() }
                )
                .presentationDetents([.large])
                // On a regular-width iPad a sheet presents as a fixed-size form
                // sheet and detents are ignored, so `.large` never applied: the
                // review came up ~574x654 pt inside a 1032x1376 screen and its
                // bottom edge sliced horizontally through the "SCHEMES &
                // EXPERTISE" heading. `.page` is the sizing that honours the
                // request on iPad.
                .presentationSizing(.page)
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
        //
        // An alert, not a `.confirmationDialog`: on iPad the dialog presents as
        // a popover and iPadOS drops the cancel row from a popover, so a
        // yes/no question about a result the copy calls final shipped with only
        // "yes" on screen and an undiscoverable tap-outside for "no".
        .alert(
            skipGameConfirmTitle,
            isPresented: $showSkipGameConfirm
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Sim & Advance") { runAdvance() }
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

    // MARK: - Hub Layout (tasks rail | work column)

    /// **The one hub layout** (#105 wave 2).
    ///
    /// There used to be two, chosen on `verticalSizeClass == .compact`. On the
    /// device this game is built for that predicate is never true: an iPad in
    /// full screen reports `.regular` vertically in BOTH orientations, so the
    /// "landscape" three-column branch had not rendered on an iPad since it was
    /// written, and every fix since — the merged Division+Upcoming panel
    /// (#143), the column widened to 300 pt, the panel background painted the
    /// full height of the rail — landed only in the branch that does render.
    /// The two had drifted into different screens with one name.
    ///
    /// Deleted the dead branch rather than the live one: the brief named "the
    /// portrait branch" as the corpse, but the grep says otherwise, and the
    /// corpse is whichever one the user has never seen.
    ///
    /// ## The rail is no longer inside a scroll of the hub's own
    ///
    ///
    /// `TimelineTasksPanel` carries its own `ScrollView`, and wrapping it in a
    /// second one nested two vertical scrolls of the same axis: the outer one
    /// proposes an unbounded height, so the inner scroll sized to its content
    /// and never scrolled, the panel's header scrolled away with everything
    /// else, and the panel could not pin anything. The column is given a bounded
    /// height instead, which is what lets the panel keep its header at the top
    /// and its advance button at the bottom with the phase list moving between
    /// them.
    ///
    /// The 8 pt leading inset went with it. The panel declares `minWidth:
    /// railWidth`, so inside a 300 pt column an 8 pt inset did not indent it —
    /// it pushed 8 pt of the panel's right edge under the divider and let the
    /// clip eat it.
    private var hubLayout: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left column -- Tasks rail
            VStack(spacing: 0) {
                #if DEBUG
                debugSkipToFABanner
                #endif
                TimelineTasksPanel(
                    career: career,
                    tasks: $tasks,
                    onTaskSelected: onTaskSelected,
                    onAdvance: { performAdvance() },
                    canAdvance: canAdvance,
                    advanceIsPrimary: !weeklyGameUnplayed,
                    advanceBlocker: advanceBlocker,
                    isAdvancing: isAdvancing
                )
            }
            .frame(width: TimelineTasksPanel.railWidth)
            // The panel paints its own background only as far as its content
            // reaches; on a short task list that left the bottom of the rail
            // showing the darker page color. Paint the whole column instead.
            .background(Color.backgroundSecondary)

            Divider().overlay(Color.surfaceBorder)

            // Right column -- the week, then the club, then the league
            ScrollView {
                LazyVStack(spacing: DSSpacing.sm) {
                    centerTilesGrid
                    // No minHeight: with a single message the 240pt floor left
                    // ~180pt of empty panel under it. The empty state carries
                    // its own height when there is genuinely nothing to show.
                    messagesPanel
                        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.card))
                        .cardBackground()
                    // Division + Upcoming combined to reduce gap (#143)
                    VStack(spacing: 0) {
                        divisionStandingsSection
                            .padding(DSSpacing.sm)
                        Divider().overlay(Color.surfaceBorder.opacity(0.4))
                        scheduleSection
                            .padding(DSSpacing.sm)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.card))
                    .cardBackground()
                    .padding(.bottom, DSSpacing.md)
                }
                .padding(DSSpacing.sm)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bottom Bar (legacy, no longer used in main layout)
    // The TimelineTasksPanel now serves as the combined tasks + advance UI.

    // MARK: - 2. Messages Panel

    private var messagesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                // Grey, like every other panel head on this column and like the
                // season band's above it. A section's NAME is not a decision;
                // the unread badge beside it and the links after it are the two
                // things here that ask for anything.
                Image(systemName: "tray.full.fill")
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("Messages")
                    .font(.system(size: DSType.Size.body, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                // The badge SAYS what it counts.
                //
                // A bare "5" in a red capsule over a list of the five most
                // recent messages — read or not — is two numbers that describe
                // different sets and nothing on screen to tell them apart: a
                // reader with three unread letters and five rows below has no
                // way to know the capsule is not counting the rows. The Inbox
                // tile has always printed "N unread"; so does this now.
                let unread = inboxMessages.filter { !$0.isRead }.count
                if unread > 0 {
                    Text("\(unread) unread")
                        .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.danger))
                        .accessibilityLabel("\(unread) unread message\(unread == 1 ? "" : "s")")
                }

                Spacer()

                // Two nav links, neither of them gold-filled. Gold fill is the
                // primary commit and this screen already has one (P5); the
                // audit's own note — "'View All' gold pill — same gold as
                // every other CTA; tone down for nav links" — is this fix.
                //
                // "News" is here because the League News bookmark came off the
                // strip when it capped at seven: the feed has to keep a route
                // from the hub, and the mail header is where a reader looking
                // for what the league is saying already is.
                sectionNavLink(title: "News", destination: .news)
                sectionNavLink(title: "View All", destination: .inbox)
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
                            .font(.system(size: DSType.Size.caption, weight: inboxFilter == filter ? .bold : .medium))
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

            // Message list.
            //
            // A plain stack, not a `ScrollView` over a `LazyVStack`. The panel
            // has no height of its own and lives inside the work column's
            // scroll, so the inner one was handed an unbounded proposal, sized
            // to its content and never scrolled a pixel — and the list it held
            // is capped at five rows plus a link, which is not a list that needs
            // to scroll. Lazy is the same story: nothing off screen to defer.
            VStack(spacing: 0) {
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
                                .font(.system(size: DSType.Size.caption, weight: .semibold))
                                .foregroundStyle(Color.accentGold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DSSpacing.xs)
                        }
                        .buttonStyle(.plain)
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
            // Outstanding only: a letter the user has dealt with is no longer a
            // task, and the tray it mirrors has already dropped it.
            return inboxMessages.filter { $0.isActionOutstanding }
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
                    .font(.system(size: DSType.Size.body))
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 28, height: 28)
                    .background(Color.backgroundTertiary)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(message.sender.displayName)
                            .font(.system(size: DSType.Size.footnote, weight: message.isRead ? .medium : .bold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(message.date)
                            .font(.system(size: DSType.Size.caption, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Text(message.subject)
                        .font(.system(size: DSType.Size.caption, weight: message.isRead ? .regular : .semibold))
                        .foregroundStyle(message.isRead ? Color.textSecondary : Color.textPrimary)
                        .lineLimit(1)

                    if message.isActionOutstanding {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: DSType.Size.micro))
                                .foregroundStyle(Color.danger)
                            Text("Action Required")
                                .font(.system(size: DSType.Size.caption, weight: .bold))
                                .foregroundStyle(Color.dangerText)
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
        GridItem(.flexible(), spacing: DSSpacing.sm),
        GridItem(.flexible(), spacing: DSSpacing.sm)
    ]

    /// **The week has a shape, and the column is now cut to it.**
    ///
    /// Everything below the hero used to be one flat run: a chip bar, then the
    /// card, then four standing scores, then fourteen tiles in one grid with the
    /// evergreen club tiles FIRST. On a game week that put Team, Roster, Staff,
    /// Cap, Locker Room, Key Players, Position Strengths, Expiring Contracts and
    /// Owner Expectations — none of which change between Tuesday and Sunday —
    /// above Week Prep, Depth Chart, Injuries and Opponent Scout, which are the
    /// four tiles the week is actually made of. The player's one question during
    /// a game week is what to do before Sunday, and the answer was at grid
    /// position eleven of fourteen.
    ///
    /// Two bands instead, each with a head that names it, in the order the week
    /// is lived: **this week's work, then the club that does it.**
    ///
    /// Two grids rather than one is the cost. The single grid existed because
    /// hard-coded `HStack` pairs left a hole when an optional tile was absent,
    /// and each band is still a grid, so that still cannot happen INSIDE a band.
    /// What can happen is a single empty cell at the END of the first band when
    /// it holds an odd count — which is a band ending, not a hole in a run, and
    /// it is what the head above it is there to say.
    private var centerTilesGrid: some View {
        VStack(spacing: DSSpacing.sm) {
            // Phase-aware Hero Card — the screen's ONE commit (P5), and now the
            // first thing in the column. It answers "what happens this week";
            // a row of shortcut chips does not, and used to sit above it.
            phaseHeroCard

            // The phase's shortcuts, under the commit they support.
            quickActionBar

            bandHead(workBandTitle)

            LazyVGrid(columns: tileColumns, spacing: DSSpacing.sm) {
                adaptiveTiles
            }

            bandHead("Your club")

            // The club's standing heads its own band: it is what the tiles under
            // it are about, and it is not something the player does this week.
            satisfactionScoresRow

            LazyVGrid(columns: tileColumns, spacing: DSSpacing.sm) {
                coreTiles
            }
        }
    }

    /// A band head: the label, then a rule to the edge of the column.
    ///
    /// Grey and condensed rather than the app's gold `SectionHeaderText`, and
    /// deliberately the same object as `DSSlatBand`'s head — the season band is
    /// pinned directly above this column, so its "2026 SEASON · WEEK 7 OF 18"
    /// and these two heads are the screen's structural voice and now share one.
    /// Gold on this screen is spent on the hero's commit and the rail's advance.
    ///
    /// The rule is what makes a two-word label fill a 700 pt column instead of
    /// leaving 600 pt of nothing beside it.
    private func bandHead(_ title: String) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text(title.uppercased())
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(0.7)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .fixedSize()

            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)  // ds-lint:allow(spacing) hairline rule, not a gap
        }
        // Two steps of vertical rhythm in the column, not one: `sm` between
        // cards inside a band, `sm + sm` above a head — which is `DSSpacing.lg`,
        // the "between major sections" step, arrived at through the stack's own
        // spacing rather than by declaring a third number.
        .padding(.top, DSSpacing.sm)
        .accessibilityAddTraits(.isHeader)
    }

    /// What the first band is called — **the week's stage, not the phase's
    /// name**, wherever the calendar is on a week.
    ///
    /// Prepare, play, read the result: during the season the head says which of
    /// the three the club is standing in, off the same `weeklyGameUnplayed`
    /// predicate that decides which control wears the gold, so the head and the
    /// hero card cannot describe different Sundays. Outside the season a phase
    /// is not a week and its own name is the honest label.
    private var workBandTitle: String {
        switch career.currentPhase {
        case .regularSeason, .tradeDeadline, .playoffs:
            if isByeWeek { return "Bye week" }
            return weeklyGameUnplayed ? "Before Sunday" : "After the game"
        default:
            return career.currentPhase.displayName
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

    /// **Every chip lands on a screen that can service its own label** (#105
    /// wave 2 gate). Four of them did not:
    ///
    /// * "Awards" → `.roster` — the roster has no awards on it. The season's
    ///   champion, record and MVP are recorded by `LeagueHistoryView`.
    /// * "Mock Draft" → `.scouting` with no tab hint, so it opened whichever
    ///   tab the hub's own rule picked. `.mockDraft` is a real destination and
    ///   carries the hint.
    /// * "Battles" → `.roster`, and camp battles are not on the roster screen
    ///   at all: they live in this dashboard's own Position Battles tile, which
    ///   opens the real `PositionBattleSheet`. A chip cannot open a sheet that
    ///   needs a battle chosen, so the chip is gone and the tile is the route.
    /// * "Camp Grades" → `.roster`, which never renders `Player.campGrade`.
    ///   `WorkloadDashboard`'s per-player detail does, and so does the Camp
    ///   Grades tile itself now.
    private func quickActions(for group: SeasonPhaseGroup) -> [QuickAction] {
        switch group {
        case .postseason:
            return [
                QuickAction(icon: "trophy.fill", label: "Season History", destination: .history),
                QuickAction(icon: "person.fill", label: "Coach Renewals", destination: .coachingStaff),
                QuickAction(icon: "checklist", label: "Draft Grades", destination: .draftReportCard),
                QuickAction(icon: "newspaper.fill", label: "League News", destination: .news)
            ]
        case .offseason:
            return [
                QuickAction(icon: "person.fill", label: "Coaching", destination: .coachingStaff),
                // "Roster Evaluation" is the destination's own title. It used
                // to read "Roster Review", one character away from the phase
                // named "Review Roster" and from the rail's irreversible
                // "Advance to Review Roster" — two controls, one name, two
                // meanings.
                QuickAction(icon: "list.dash", label: "Roster Evaluation", destination: .rosterEvaluation),
                QuickAction(icon: "chart.line.uptrend.xyaxis", label: "Cap", destination: .capOverview),
                QuickAction(icon: "building.columns.fill", label: "History", destination: .history)
            ]
        case .preDraft:
            return [
                QuickAction(icon: "magnifyingglass", label: "Scouting", destination: .scouting),
                QuickAction(icon: "list.bullet", label: "Big Board", destination: .bigBoard),
                QuickAction(icon: "list.bullet.rectangle", label: "Mock Draft", destination: .mockDraft)
            ]
        case .preSeason:
            return [
                QuickAction(icon: "figure.run.circle", label: "Training", destination: .trainingPlan),
                QuickAction(icon: "heart.text.square.fill", label: "Workload", destination: .workloadDashboard),
                QuickAction(icon: "list.number", label: "Depth Chart", destination: .depthChart)
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

    /// The phase's three or four shortcuts, spread across the column.
    ///
    /// They used to sit above the hero card and hug the left edge behind a
    /// `Spacer`, leaving ~330 pt of the measure empty beside them. Sharing the
    /// width evenly spends that, and it puts the strip's right edge on the same
    /// line as the hero card and the tile grid, which is what makes three blocks
    /// of different content read as one column.
    @ViewBuilder
    private var quickActionBar: some View {
        let group = career.currentPhase.group
        HStack(spacing: DSSpacing.xs) {
            ForEach(quickActions(for: group), id: \.label) { action in
                quickActionButton(action)
            }
        }
    }

    /// **Grey, not gold** (P5). Four chips carrying a gold glyph and a gold
    /// border, in a strip that sits directly against a hero card whose one job
    /// is the week's single gold commit: five gold objects for one decision and
    /// four shortcuts. A chip is a door, and the outline is what says so.
    private func quickActionButton(_ action: QuickAction) -> some View {
        Button {
            if action.opensInjuryReport {
                activeSheet = .injuryReport
            } else {
                onTaskSelected(action.destination)
            }
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: action.icon)
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text(action.label)
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            // Padding first, then the flex: the label keeps its inset from the
            // capsule edge, and the frame is what shares the column out. The
            // other order adds 16 pt to every chip's *share* and overflows.
            //
            // §2.12: 44 pt in both axes, measured. At 8 pt of vertical padding
            // around an 11 pt label these chips measured 27.
            .padding(.horizontal, DSSpacing.xs)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Phase-Group Stub Tiles

    /// All-Star and All-Pro honours are announced as inbox mail by
    /// `WeekAdvancer` (the `.proBowl` week's "All-Star selections: …"
    /// message) and nothing persists a per-club count, so the tile stopped
    /// printing `0 All-Stars · 0 All-Pro` — a literal that read as a fact and
    /// was wrong for every club with a All-Star. It says where the honours
    /// actually are and goes there.
    private var awardsHubTile: some View {
        Button {
            onTaskSelected(.inbox)
        } label: {
            DashboardTile(icon: "trophy.fill", title: "Honors") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("All-Star & All-Pro")
                        .font(.system(size: DSType.Size.caption, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("Selections arrive in your inbox")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Legacy points are real (`career.legacy`); "Season grade pending" was
    /// not — it was pending forever, because nothing ever wrote a season grade.
    /// The owner's verdict is the club's actual grade for the year, and it is
    /// persisted on `career.ownerSeasonReview`, so the tile prints that when it
    /// exists and its own record when it does not.
    private var teamAccoladesTile: some View {
        Button {
            onTaskSelected(.history)
        } label: {
            DashboardTile(icon: "star.fill", title: "Team Accolades") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Legacy: \(signedLegacy(career.legacy.totalPoints))")
                        .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    Text(career.ownerSeasonReview.map { "Owner verdict: \($0.verdict.label)" }
                         ?? seasonRecordSummary)
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var seasonRecapTile: some View {
        Button {
            // "Final standings & summary" is the standings screen, not the
            // roster. The roster cannot service the sentence on the tile.
            onTaskSelected(.standings)
        } label: {
            DashboardTile(icon: "doc.text.fill", title: "Season Recap") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(seasonRecordSummary)
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Final standings & summary")
                        .font(.system(size: DSType.Size.footnote))
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

    /// One rung of that projection — the club's cap `yearsAhead` league years out.
    private func projectedCap(yearsAhead: Int) -> String {
        let now = team?.salaryCap ?? ContractEngine.openingSalaryCap
        let then = Double(now) * pow(1.0 + ContractEngine.capGrowthPerSeason, Double(yearsAhead))
        return String(format: "$%.0fM", then / 1_000.0)
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
                        .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    Text("Projection across 3 seasons")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    // The two lines above were stretched to the height of the
                    // six-row Contracts tile beside them, leaving ~180 pt of
                    // empty plate. The ladder the headline compresses into one
                    // arrow is what the free height is for. Labelled in years
                    // rather than league years: the phase this tile renders in
                    // straddles the rollover, and a wrong season number would
                    // be worse than none.
                    ForEach(1...3, id: \.self) { yearsAhead in
                        HStack {
                            Text("+\(yearsAhead) yr")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                            Text(projectedCap(yearsAhead: yearsAhead))
                                .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var offseasonGoalsTile: some View {
        // The card titled itself "Season Review" in a career whose first season
        // has not been played: no goals, no verdict, and a 0-0 record on the
        // same screen. Until a review exists it is the owner's mandates it
        // shows, so that is what it is called.
        let hasReview = career.ownerSeasonReview != nil
        return Button {
            onTaskSelected(.ownerMeeting)
        } label: {
            DashboardTile(icon: "target", title: hasReview ? "Season Review" : "Owner Mandates") {
                VStack(alignment: .leading, spacing: 4) {
                    // R31: real numbers from the last owner review / goal log
                    if let review = career.ownerSeasonReview {
                        Text("\(review.goalsAchieved) of \(max(review.goalsTotal, 1)) met")
                            .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                            .foregroundStyle(review.goalsAchieved * 2 >= review.goalsTotal ? Color.success : Color.warning)
                        Text("Owner verdict: \(review.verdict.label)")
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.textSecondary)
                    } else {
                        Text("No season reviewed yet")
                            .font(.system(size: DSType.Size.footnote, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Meet the owner")
                            .font(.system(size: DSType.Size.footnote))
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
                        .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                        .foregroundStyle(unread > 0 ? Color.accentGold : Color.textSecondary)
                    Text("Offseason news")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// "Latest: Pre-Draft" was a literal that never changed. The two mocks are
    /// real stages of `DraftPrepProgress` (`.mockOne`, `.mockTwo`), so the tile
    /// says which of them has been read, and lands on the hub's Mock Draft tab
    /// instead of wherever the hub happened to open.
    private var mockDraftTile: some View {
        let progress = prepProgress
        let readMocks = [DraftPrepStep.mockOne, .mockTwo]
            .filter { progress?[$0].isSatisfied == true }
            .count
        return Button {
            openScoutingHub(tab: "mockDraft")
        } label: {
            DashboardTile(icon: "list.bullet.rectangle.fill", title: "Mock Draft") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(readMocks) of 2 read")
                        .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    Text("Compare to Big Board")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The three thinnest position groups on the club's own roster.
    ///
    /// "QB CB LT" was a string literal on a live tile — the same defect as the
    /// `$285M → $310M` cap projection (#87/F14), and worse, because three
    /// position codes read as a scouting judgement rather than as decoration.
    /// It is now the bottom three of `positionGroupGrades`, the array the
    /// Position Group Strengths tile on this very screen already computes from
    /// the roster, so the two tiles cannot name different holes.
    private var weakestPositionGroups: [String] {
        positionGroupGrades
            .sorted { $0.starterOVR < $1.starterOVR }
            .prefix(3)
            .map(\.group)
    }

    private var teamNeedsTile: some View {
        let needs = weakestPositionGroups
        return Button {
            // The draft class BY POSITION against the club's own holes — the
            // screen this tile's sentence describes. The roster does not rank
            // the club's needs anywhere.
            onTaskSelected(.classDepth)
        } label: {
            DashboardTile(icon: "exclamationmark.triangle.fill", title: "Team Needs") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(needs.isEmpty ? "Loading\u{2026}" : needs.joined(separator: " "))
                        .font(.system(size: DSType.Size.body, weight: .bold))
                        .foregroundStyle(needs.isEmpty ? Color.textSecondary : Color.warning)
                    // Says what `weakestPositionGroups` actually ranks. It sorts
                    // on `starterOVR` and never reads `depthOVR`, so "thinnest"
                    // named a different column from the one the Position Grades
                    // tile prints beside it — S: B- flagged, D: B- unflagged.
                    Text("Weakest starters on your roster")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var proDaysTile: some View {
        Button {
            openScoutingHub(tab: "proDays")
        } label: {
            DashboardTile(icon: "figure.run", title: "Pro Days") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Schedule visits")
                        .font(.system(size: DSType.Size.caption, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("Workouts & interviews")
                        .font(.system(size: DSType.Size.footnote))
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
        // TWO survivors, not one. The competitor set is frozen at detection, so
        // releasing one of a pair on cut day left a battle with a single man in
        // it — and the row, which joins the survivors with " vs ", printed
        // "CB Broadwater … Broadwater" with the same surname in the matchup
        // column and in the leader chip, still counted in "9 active". A contest
        // with one entrant is over; `PositionBattleTracker` writes the winner at
        // the end of camp.
        let rosterIDs = Set(players.map(\.id))
        openPositionBattles = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { battle in battle.competitorIDs.filter { rosterIDs.contains($0) }.count >= 2 }
            .sorted { $0.positionRaw < $1.positionRaw }
    }

    /// The saved camp training split and week-prep split for the current key.
    ///
    /// Both are keyed exactly the way their editors key them — `TrainingPlan`
    /// on (team, season, week, phase) as `TrainingPlanView.fetchExistingPlan`
    /// does, `OpponentPrepWeek` on (season, week, team) as `WeekAdvancer` does
    /// when it reads the slider — so the hub cannot print a split the engine
    /// will not use. Nil means nothing is saved, and the tiles say so.
    private func loadSavedPlans() {
        guard let teamID = career.teamID else { return }
        let season = career.currentSeason
        let week = career.currentWeek

        let phaseRaw = career.currentPhase.rawValue
        let planDescriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> {
                $0.teamID == teamID
                    && $0.seasonYear == season
                    && $0.weekNumber == week
                    && $0.phaseRaw == phaseRaw
            }
        )
        savedTrainingSplit = (try? modelContext.fetch(planDescriptor))?.first.map {
            (tactical: $0.tacticalPct, physical: $0.physicalPct, technical: $0.technicalPct)
        }

        let prepDescriptor = FetchDescriptor<OpponentPrepWeek>(
            predicate: #Predicate<OpponentPrepWeek> {
                $0.seasonYear == season && $0.weekNumber == week && $0.teamID == teamID
            }
        )
        savedPrepSplit = (try? modelContext.fetch(prepDescriptor))?.first.map {
            (general: $0.generalPct, opponent: $0.opponentPct)
        }
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
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                    // Phase-aware: the old line was unconditional, so standing
                    // in Training Camp — rail reading "TRAINING CAMP · NOW" —
                    // the tile told the player competitions open in Training
                    // Camp. Inside camp the real answer is *when*:
                    // `PositionBattleTracker.detectBattles` only runs on a camp
                    // week advance.
                    Text(career.currentPhase == .trainingCamp || career.currentPhase == .otas
                         ? "Battles open after the first camp week — advance to see them"
                         : "Camp competitions open in Training Camp")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                } else {
                    Text("\(openPositionBattles.count) active")
                        .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
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
                            .font(.system(size: DSType.Size.footnote, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
    }

    /// Surname, or first-initial + surname when the club carries more than one
    /// man by that name.
    ///
    /// Battles are grouped by position, so "DT Bolliger vs Braithwaite" on a
    /// roster whose 93 OVR receiver is also a Braithwaite names two different
    /// men with one word — and the leader chip repeats it. Surname collisions
    /// are normal in a generated league (two Hinsdales on one roster).
    private func battleName(_ player: Player) -> String {
        let shared = players.filter { $0.lastName == player.lastName }.count > 1
        guard shared, let initial = player.firstName.first else { return player.lastName }
        return "\(initial). \(player.lastName)"
    }

    private func positionBattleRow(_ battle: PositionBattle) -> some View {
        let roster = competitors(for: battle)
        let names = roster.prefix(2).map { battleName($0) }.joined(separator: " vs ")
        let leader = battle.currentLeaderID.flatMap { id in roster.first { $0.id == id } }
        return HStack(spacing: 4) {
            Text(battle.positionRaw)
                .font(.system(size: DSType.Size.caption, weight: .bold))
                .foregroundStyle(Color.accentGold)
                .frame(width: 24, alignment: .leading)
            Text(names.isEmpty ? "Open spot" : names)
                .font(.system(size: DSType.Size.micro, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let leader {
                Text(battleName(leader))
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .foregroundStyle(Color.success)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .contentShape(Rectangle())
    }

    /// The club's best camp grades, read off `Player.campGrade` — the value
    /// `WeekAdvancer.applyCampGrades` writes each camp week.
    ///
    /// `"Top: —"` was a permanent em-dash: the tile never read the grade at
    /// all, and it sent the user to the roster screen, which does not render a
    /// camp grade anywhere. Both halves of a dead end in one tile.
    private var topCampGraded: [(name: String, grade: CampGrade)] {
        // Written out longhand: the chained compactMap/filter/sorted over a
        // tuple element blew up the type checker in this file.
        var graded: [(name: String, grade: CampGrade)] = []
        for player in players {
            guard let grade: CampGrade = player.campGrade else { continue }
            guard grade == .aPlus || grade == .a else { continue }
            graded.append((name: player.lastName, grade: grade))
        }
        graded.sort { (lhs: (name: String, grade: CampGrade), rhs: (name: String, grade: CampGrade)) -> Bool in
            if lhs.grade == rhs.grade { return lhs.name < rhs.name }
            return lhs.grade == .aPlus
        }
        return Array(graded.prefix(3))
    }

    /// How many men carry a camp grade at all — the number that separates "camp
    /// has not been graded" from "camp was graded and nobody earned an A".
    ///
    /// `topCampGraded` keeps only A+ and A, so an empty list was being read as
    /// an ungraded camp by three surfaces at once: the hub said "Camp standouts
    /// — None graded yet" while the cut list two taps away printed "Camp D" on
    /// nine of fourteen men.
    private var campGradedCount: Int {
        players.reduce(0) { $0 + ($1.campGrade == nil ? 0 : 1) }
    }

    private var campGradesTile: some View {
        let top = topCampGraded
        let graded = campGradedCount
        return Button {
            // The workload board's per-player detail is the one surface that
            // prints a camp grade outside the cut room.
            onTaskSelected(.workloadDashboard)
        } label: {
            DashboardTile(icon: "graduationcap.fill", title: "Camp Grades") {
                VStack(alignment: .leading, spacing: 4) {
                    if top.isEmpty {
                        // Graded, but nobody reached an A: say so. "Not graded
                        // yet" over a squad the cut room is already showing
                        // "Camp D" for is the tile calling the grades missing
                        // because it only looks at the top two letters.
                        Text(graded == 0 ? "Not graded yet" : "No A grades")
                            .font(.system(size: DSType.Size.caption, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        Text(graded == 0
                             ? "Grades land during Training Camp"
                             : "\(graded) graded — best is a B or lower")
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    } else {
                        ForEach(top, id: \.name) { entry in
                            HStack(spacing: 4) {
                                Text(entry.grade.displayLabel)
                                    .font(.system(size: DSType.Size.micro, weight: .heavy))
                                    .foregroundStyle(Color.accentGold)
                                    .frame(width: 20, alignment: .leading)
                                Text(entry.name)
                                    .font(.system(size: DSType.Size.caption, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var preseasonGamesTile: some View {
        // #205b: the tile advertised "3 exhibition games" and opened the
        // SCHEDULE — a screen no preseason fixture has ever existed on, because
        // the slate is a career blob and not a `Game` row. It points at the
        // slate itself now, and its second line reports the real count off
        // `PreseasonState` instead of promising three games in the abstract.
        let flow = career.preseasonState.flatMap { $0.matches(career: career) ? $0 : nil }
        let played = flow?.results.count ?? 0
        let total = flow?.slate.count ?? PreseasonFlowBand.gameCount
        return Button {
            onTaskSelected(.preseason)
        } label: {
            DashboardTile(icon: "sportscourt", title: "Preseason") {
                VStack(alignment: .leading, spacing: 4) {
                    // Preseason is a camp/evaluation phase in this build — no
                    // scored W-L record is tracked, so show the tile's purpose
                    // instead of a fabricated "0-0 record" stat.
                    Text(flow?.isComplete == true ? "Slate complete" : "Evaluate roster")
                        .font(.system(size: DSType.Size.caption, weight: .medium))
                        .foregroundStyle(Color.accentGold)
                    Text("\(played) of \(total) exhibitions played")
                        .font(.system(size: DSType.Size.footnote))
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
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    // "View" was the first line and it was gold — the tile's
                    // emphasis colour spent on the word every tappable tile
                    // could have printed. What the tile is FOR goes first.
                    Text("Starters & backups")
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Set who takes the snaps")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
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
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    let injuredCount = players.filter { $0.injuryWeeksRemaining > 0 }.count
                    Text(injuredCount == 0 ? "Fully healthy" : "\(injuredCount) out")
                        .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                        .foregroundStyle(injuredCount > 0 ? Color.dangerText : Color.success)
                    Text("Status updates weekly")
                        .font(.system(size: DSType.Size.footnote))
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
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    // #154: `currentWeekFixture`, not `upcomingGames.first` —
                    // the tile used to name next week's opponent the moment this
                    // week's game was played, while the hero card above it still
                    // named this week's.
                    let opponent = currentWeekFixture.flatMap { game in
                        allTeamsByID[game.homeTeamID == team?.id ? game.awayTeamID : game.homeTeamID]
                    }
                    // The opponent's code is a FACT about the week, not a call
                    // the user has to make, so it takes the ink a value takes
                    // and not the screen's emphasis hue.
                    Text(opponent.map { "Vs \($0.abbreviation)" } ?? "Vs \u{2014}")
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Strengths & weaknesses")
                        .font(.system(size: DSType.Size.footnote))
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
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(Color.dangerText)
                    Text(pendingOffers > 0
                         ? "\(pendingOffers) offer\(pendingOffers == 1 ? "" : "s") expire\(pendingOffers == 1 ? "s" : "") — answer them"
                         : "Last chance for deals this season")
                        .font(.system(size: DSType.Size.footnote))
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
                    // The four stage codes were byte-identical in every round —
                    // Wild Card, Divisional and Conference all read the same
                    // tile. `playoffRoundKey` is the same mapping the hero card
                    // highlights its strip with, so the live round is marked
                    // here too instead of being left for the player to work out.
                    let liveKey = playoffRoundKey(forWeek: career.currentWeek)
                    HStack(spacing: 4) {
                        ForEach(["WC", "DIV", "CONF", "SB"], id: \.self) { stage in
                            Text(stage)
                                .font(.system(size: DSType.Size.caption, weight: stage == liveKey ? .heavy : .medium))
                                .foregroundStyle(stage == liveKey ? Color.accentGold : Color.textTertiary)
                        }
                    }
                    Text(playoffRoundName(forWeek: career.currentWeek))
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Camp Tiles

    /// The saved split, or the engine's own default. Camp runs 34/33/33 when
    /// nothing is saved (`TrainingPlanView` seeds its sliders from the same
    /// numbers), so the tile can name what will happen if the user never opens
    /// the screen rather than listing the three options as if they were a value.
    private var trainingPlanTile: some View {
        let split = savedTrainingSplit
        return NavigationLink(value: CareerShellView.ShellDestination.trainingPlan) {
            DashboardTile(icon: "figure.run.circle.fill", title: "Training Plan") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(split.map { "\($0.tactical) / \($0.physical) / \($0.technical)" } ?? "Not set \u{2014} 34 / 33 / 33")
                        .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                        .foregroundStyle(split == nil ? Color.textSecondary : Color.accentGold)
                    Text("Tactical / Physical / Technical")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var workloadTile: some View {
        // `overloadedShare` is the figure the camp hero card three cards above
        // already prints, so the tile that owns the subject no longer sends the
        // player elsewhere to learn its one number.
        let overloaded = overloadedShare
        return NavigationLink(value: CareerShellView.ShellDestination.workloadDashboard) {
            DashboardTile(icon: "heart.text.square.fill", title: "Workload") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(overloaded)% overloaded")
                        .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                        .foregroundStyle(overloaded >= 20 ? Color.warning : Color.textSecondary)
                    Text("Injury & burnout risk")
                        .font(.system(size: DSType.Size.footnote))
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
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(cutsRemaining > 0 ? Color.warning : Color.success)
                    Text("90 → 75 → 65 → 53")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var gameWeekPrepTile: some View {
        // The second line used to be the literal "General vs opponent focus" —
        // the axis, not the value — and it read identically in Week 1 and Week
        // 2 on a decision the task list calls per-opponent. With no saved row
        // `WeekAdvancer` runs a zero delta off `OpponentPrep.neutralFocus`,
        // which is the 50/50 the empty state names.
        let split = savedPrepSplit
        return NavigationLink(value: CareerShellView.ShellDestination.gameWeekPrep) {
            DashboardTile(icon: "scope", title: "Week Prep") {
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    // The SPLIT is the emphasis, not the caption naming the
                    // week: the split is the decision this tile exists for, and
                    // an unset one is the state the week is asking about. The
                    // caption above it used to be the gold line and the split
                    // the grey one, i.e. exactly backwards.
                    Text(split.map { "\($0.general) general / \($0.opponent) opponent" }
                         ?? "Not set \u{2014} 50 / 50")
                        .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                        .foregroundStyle(split == nil ? Color.warning : Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Text("Week \(career.currentWeek) practice focus")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Nav Link

    /// A hub section's "there is a whole screen behind this" affordance.
    ///
    /// Ghost, never gold: gold fill has exactly three jobs and a navigation
    /// link is none of them (P5). Sized to the 44 pt touch target through its
    /// padding plus `contentShape`.
    private func sectionNavLink(title: String, destination: TaskDestination) -> some View {
        Button {
            onTaskSelected(destination)
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .font(.system(size: DSType.Size.caption, weight: .bold))
                Image(systemName: "chevron.right")
                    .font(.system(size: DSType.Size.micro, weight: .bold))
            }
            .foregroundStyle(Color.accentGold)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule().strokeBorder(Color.accentGold.opacity(0.35), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), opens the full screen")
    }

    // MARK: - Schedule Section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "calendar")
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("UPCOMING")
                    .font(.system(size: DSType.Size.footnote, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .tracking(0.5)
                Spacer()
                // The Schedule bookmark came off the seven-slot strip; this is
                // the hub route that paid for it (P6).
                sectionNavLink(title: "Schedule", destination: .schedule)
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
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "list.number")
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Text("DIVISION")
                    .font(.system(size: DSType.Size.footnote, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .tracking(0.5)
                Spacer()
                // The Standings bookmark came off the seven-slot strip; this is
                // the hub route that paid for it (P6).
                sectionNavLink(title: "Standings", destination: .standings)
            }

            if divisionTeams.isEmpty {
                Text("Loading...")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            } else if isPreSeasonNoGamesPlayed {
                // Empty state. The countdown that used to live here said what
                // the Upcoming card directly beneath it already says — the two
                // ran a "no games yet" placeholder each, back to back — while
                // the question this card is asked in the offseason is who has
                // to be beaten and by how much. `Team` carries one year of that
                // (`lastSeasonWins`, sentinel -1 until a season has finished),
                // so the countdown stays for a first career and the table takes
                // every one after it.
                if divisionTeams.contains(where: \.hasLastSeasonRecord) {
                    lastSeasonDivisionTable
                } else {
                    preSeasonCountdownRow
                }
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
                .font(.system(size: DSType.Size.caption, weight: .bold))
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
                                    .font(.system(size: DSType.Size.micro))
                                    .foregroundStyle(Color.accentGold)
                                    .frame(width: 10)
                            } else {
                                Spacer().frame(width: 10)
                            }
                            Text(t?.abbreviation ?? "???")
                                .font(.system(size: DSType.Size.caption, weight: isMyTeam ? .heavy : .medium))
                                .foregroundStyle(isMyTeam ? Color.accentGold : Color.textSecondary)
                                .frame(width: 34, alignment: .leading)

                            // Fills what was ~600pt of empty row between the
                            // abbreviation and the W-L column, and matches the
                            // full Standings screen's team column.
                            Text(t?.fullName ?? "")
                                .font(.system(size: DSType.Size.caption, weight: .regular))
                                .foregroundStyle(isMyTeam ? Color.textSecondary : Color.textTertiaryReadable)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(wl)
                            .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                            .foregroundStyle(isMyTeam ? Color.textPrimary : Color.textSecondary)
                            .frame(width: 48, alignment: .trailing)
                        Text(pctStr)
                            .font(.system(size: DSType.Size.micro, weight: .regular).monospacedDigit())
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
                .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 34, alignment: .leading)

            Text("\(prefix) \(oppAbbr)")
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer()

            if isHome {
                Text("HOME")
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
                    .foregroundStyle(Color.success)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.success.opacity(0.12).cornerRadius(3))
            } else {
                Text("AWAY")
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
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

    /// **The card's promise is the card's destination** (#175).
    ///
    /// This tile used to push `OwnerMeetingView`: the shield icon, the word
    /// "Team", the club's record and its division rank all opened Owner
    /// Relations — which is a *different tile on this same grid*
    /// (`ownerExpectationsTile`, headed "Owner"). Sim-QA tapped three separate
    /// places on the card and landed in the same wrong room every time, which
    /// is what a whole-card `NavigationLink` to the wrong screen looks like
    /// from the outside. A card that prints a record and a division rank has
    /// one honest destination: the standings.
    ///
    /// It is also the hub's only above-the-fold route to Standings. The other
    /// one — the "Standings" pill in the DIVISION section — sits below ten
    /// tiles and the message panel: reachable, but not findable (#175 (2)).
    ///
    /// The owner-satisfaction bar came off the card with the destination. It
    /// was the single element that argued for the Owner room, and the Owner
    /// tile a few rows down carries that relationship in more detail (persona,
    /// job security, pending whim).
    ///
    /// Routed by value rather than by inline view so the push goes through the
    /// shell's `navigationDestination` and ticks the `.standings` task the way
    /// every other route to that screen does.
    private var teamTile: some View {
        NavigationLink(value: CareerShellView.ShellDestination.standings) {
            DashboardTile(icon: "shield.fill", title: "Team") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(team?.fullName ?? "No Team")
                        .font(.system(size: DSType.Size.body, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    // Fix #28: Prominent record display
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(team?.record ?? "0-0")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)

                        // Before Week 1 every club in the division is 0-0-0 and
                        // the sort has nothing to separate them, so the badge
                        // printed whichever slot the id tiebreak fell into —
                        // the same reason the standings panel below shows a
                        // countdown instead of four 0-0 rows. And when the rank
                        // IS earned, name what it ranks: a bare "#4" reads just
                        // as well as a power ranking, a seed or a draft slot.
                        if let rank = divisionRank, !isPreSeasonNoGamesPlayed, let myTeam = team {
                            Text("\(rank) in \(myTeam.conference.rawValue) \(myTeam.division.rawValue)")
                                .font(.system(size: DSType.Size.body, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                    }

                    // Win/loss streak indicator
                    if let streak = currentStreak, streak.count > 1 {
                        Text(streak.label)
                            .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                            .foregroundStyle(streak.isWin ? Color.success : Color.dangerText)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        // Label left to the card's own content (club, record, rank); only the
        // destination needs saying, and saying it is the whole point of #175.
        .accessibilityHint("Opens the league standings")
    }

    // MARK: - Roster Tile

    /// The position groups whose STARTERS are under the league bar, worst
    /// first, at most three.
    ///
    /// Not `weakestPositionGroups`: that one is a plain bottom-three and always
    /// names three groups, which on a stacked roster prints holes that are not
    /// there. 70 is `PositionGradeCalculator`'s own B-/C+ line and the same cut
    /// the Position Grades tile's NEED badge uses, so the two marks on this
    /// screen cannot name different groups.
    private var rosterHoleGroups: [String] {
        positionGroupGrades
            .filter { $0.starterOVR < 70 }
            .sorted { $0.starterOVR < $1.starterOVR }
            .prefix(3)
            .map(\.group)
    }

    private var rosterTile: some View {
        let holes = rosterHoleGroups
        return NavigationLink {
            RosterViewWrapper(career: career)
        } label: {
            // Headcount inline with the caption (see `DashboardTile.headline`):
            // "ROSTER 53" says everything the old "Players / 53" row did, and
            // the row it frees is what the health line below is written in.
            DashboardTile(
                icon: "person.3.fill",
                title: "Roster",
                highlighted: currentPhaseHighlightedTiles.contains("Roster"),
                headline: "\(rosterCount)"
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Cap Space")
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(formatCap(team?.availableCap ?? 0))
                            .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.success)
                    }
                    // Roster HEALTH, which a headcount and a cap figure between
                    // them do not state: 53 men and $12M of room is the same
                    // tile on a club with no weak room and on one starting a
                    // 58-OVR line. The letters themselves stay on the Position
                    // Grades tile — this is the one-line verdict off them.
                    HStack(alignment: .firstTextBaseline) {
                        Text("Needs")
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        if positionGroupGrades.isEmpty {
                            Text("\u{2014}")
                                .font(.system(size: DSType.Size.footnote, weight: .semibold))
                                .foregroundStyle(Color.textTertiary)
                        } else {
                            Text(holes.isEmpty ? "None" : holes.joined(separator: ", "))
                                .font(.system(size: DSType.Size.footnote, weight: .bold))
                                .foregroundStyle(holes.isEmpty ? Color.success : Color.warning)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
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
                                .font(.system(size: DSType.Size.micro, weight: .bold))
                                .foregroundStyle(Color.accentGold)
                            Text("You")
                                .font(.system(size: DSType.Size.footnote, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                        }
                    } else if let hc = headCoach {
                        HStack(spacing: 4) {
                            Text("HC")
                                .font(.system(size: DSType.Size.micro, weight: .bold))
                                .foregroundStyle(Color.accentGold)
                            Text(hc.fullName)
                                .font(.system(size: DSType.Size.footnote, weight: .medium))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                        }
                    } else {
                        Text("No head coach")
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textSecondary)
                    }

                    // The two men the Coaching Changes phase exists to hire.
                    // Hiring a whole staff used to move ONE number on this hub —
                    // the slot counter — and name nobody: the coordinators, and
                    // the schemes they bring, appeared on no tile at all.
                    coordinatorRow(.offensiveCoordinator)
                    coordinatorRow(.defensiveCoordinator)

                    // Fix #61: Prominent filled/total staff display (coaches + scouts)
                    // #106: read the scouting department off the enum — it grew
                    // two extra slots (chief + 5 regional + 2 extra) and the
                    // hardcoded 6 rendered a filled count above the total.
                    // #133: every number on this tile — both halves of the slot
                    // count AND the two money figures below — comes off the one
                    // `StaffLedger` the Staff screen reads. The tile no longer
                    // owns a role filter or a fallback of its own.
                    let ledger = staffLedger
                    let totalSlots = ledger?.totalSlots ?? StaffSlots.totalSlots(for: career.role)
                    let filledSlots = ledger?.filledSlots ?? 0
                    let isFullyStaffed = ledger?.isFullyStaffed ?? false
                    HStack(spacing: 6) {
                        HStack(spacing: 2) {
                            Text("\(filledSlots)")
                                .font(.system(size: DSType.Size.title3, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                            Text("/")
                                .font(.system(size: DSType.Size.body, weight: .medium))
                                .foregroundStyle(Color.textTertiary)
                            Text("\(totalSlots)")
                                .font(.system(size: DSType.Size.title3, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.textSecondary)
                        }
                        Text("Staff")
                            .font(.system(size: DSType.Size.caption, weight: .medium))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        if isFullyStaffed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: DSType.Size.callout))
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

                    // Coaching budget remaining (#147). Hidden — not faked —
                    // until the owner has actually resolved (#133).
                    if let ledger, ledger.isResolved, ledger.coachingBudget > 0 {
                        let remaining = ledger.remainingCoaching
                        // Green means "you can still spend this". Once every
                        // seat is hired it buys nothing — a green figure over a
                        // green tick read the club's biggest unmade upgrade as
                        // an unambiguous win, so a full staff prints its
                        // surplus as unspent money, not as headroom.
                        let budgetColor = isFullyStaffed
                            ? Color.textTertiary
                            : (remaining > 10_000 ? Color.success : remaining > 5_000 ? Color.accentGold : Color.warning)
                        HStack(spacing: 4) {
                            Image(systemName: "dollarsign.square.fill")
                                .font(.system(size: DSType.Size.micro))
                                .foregroundStyle(budgetColor)
                            // "Budget · $26.5M / $47.0M" read as the slot
                            // counter four points above it ("23 / 23 Staff"),
                            // i.e. as money SPENT — it is money LEFT, and the
                            // two fractions filled in opposite directions. Say
                            // which, and drop the slash that mimicked the row
                            // above.
                            Text(isFullyStaffed ? "Budget unspent" : "Budget left")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                            Text(StaffLedger.money(remaining))
                                .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                                .foregroundStyle(budgetColor)
                            Text("of")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textTertiary)
                            Text(StaffLedger.money(ledger.coachingBudget))
                                .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// One coordinator seat on the Staff tile: abbreviation, name, and the
    /// scheme he runs (which is the club's scheme on that side). "VACANT" in
    /// warning amber while the seat is the thing holding the advance shut.
    @ViewBuilder
    private func coordinatorRow(_ role: CoachRole) -> some View {
        let coach = allCoaches.first { $0.role == role }
        let scheme = role == .offensiveCoordinator
            ? coach?.offensiveScheme?.displayName
            : coach?.defensiveScheme?.displayName
        HStack(spacing: 4) {
            Text(role.abbreviation)
                .font(.system(size: DSType.Size.micro, weight: .bold))
                .foregroundStyle(Color.accentGold)
                .frame(width: 22, alignment: .leading)
            Text(coach?.fullName ?? "VACANT")
                .font(.system(size: DSType.Size.caption, weight: coach == nil ? .bold : .medium))
                .foregroundStyle(coach == nil ? Color.warning : Color.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if let scheme {
                Text(scheme)
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
        }
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
                                .font(.system(size: DSType.Size.callout))
                                .foregroundStyle(Color.textTertiary)
                            Text("Hire scouts to begin scouting")
                                .font(.system(size: DSType.Size.caption, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        // Top prospect
                        if let prospect = draftClass.first {
                            HStack(spacing: 4) {
                                Text("#1")
                                    .font(.system(size: DSType.Size.micro, weight: .bold))
                                    .foregroundStyle(Color.accentGold)
                                Text("\(prospect.firstName) \(prospect.lastName)")
                                    .font(.system(size: DSType.Size.footnote, weight: .medium))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                            }
                            Text("\(prospect.position.rawValue) \u{2014} \(prospect.college)")
                                .font(.system(size: DSType.Size.micro))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }

                        // Prospect count by side. The specialists used to fall
                        // out of a row that reads as a partition: "350 total /
                        // OFF 196 / DEF 148" is six kickers and punters short of
                        // adding up, and three numbers where two are meant to
                        // sum to the third is a bug on sight.
                        let offenseCount = draftClass.filter { $0.position.side == .offense }.count
                        let defenseCount = draftClass.filter { $0.position.side == .defense }.count
                        let specialCount = draftClass.filter { $0.position.side == .specialTeams }.count
                        HStack(spacing: 12) {
                            Text("\(draftClass.count) total")
                                .font(.system(size: DSType.Size.micro, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color.textPrimary)
                            Text("OFF \(offenseCount)")
                                .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                            Text("DEF \(defenseCount)")
                                .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                            if specialCount > 0 {
                                Text("ST \(specialCount)")
                                    .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }

                        // How much of the class the department actually has a
                        // report on — the one line on this tile that answers
                        // "is another week here worth buying", and the reason
                        // the card is on screen in the stage it highlights.
                        // `scoutedOverallGrade` is written only by a filed
                        // report, so an unworked class reads 0, not 350.
                        let scoutedCount = draftClass.filter { $0.scoutedOverallGrade != nil }.count
                        HStack {
                            Text("Scouted")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text("\(scoutedCount) of \(draftClass.count)")
                                .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                                .foregroundStyle(scoutedCount > 0 ? Color.accentGold : Color.textTertiary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 5)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.accentGold)
                                    .frame(
                                        width: geo.size.width * Double(scoutedCount) / Double(max(draftClass.count, 1)),
                                        height: 5
                                    )
                            }
                        }
                        .frame(height: 5)
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
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textSecondary)
                            if isCapTight {
                                Text("CAP TIGHT")
                                    .font(.system(size: DSType.Size.micro, weight: .black))
                                    .foregroundStyle(.white)
                                    .tracking(0.5)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(usedFraction > 0.95 ? Color.danger : Color.warning))
                            }
                            Spacer()
                            Text(formatCap(t.currentCapUsage))
                                .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
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
                                // Percentage label inside bar. One decimal, not
                                // `Int(...)`: truncation printed "80%" for the
                                // same 214.6/265 the Cap screen calls "81.0%",
                                // and two screens disagreeing about one division
                                // reads as a bug in the money, not in the format.
                                Text(String(format: "%.1f%%", usedFraction * 100))
                                    .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.leading, 4)
                            }
                        }
                        .frame(height: 12)

                        HStack(alignment: .firstTextBaseline) {
                            Text("Available")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            // Same thresholds as the bar directly above it.
                            // "Available" used to be a binary above/below zero,
                            // so a red 92.0% bar, a CAP TIGHT chip and a green
                            // "$22.7M" described one fact in three colours
                            // inside 60 pt.
                            Text(formatCap(t.availableCap))
                                .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                                .foregroundStyle(availableCapColor(available: t.availableCap, usedFraction: usedFraction))
                        }

                        // Total cap line
                        HStack {
                            Text("Total Cap")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                            Text(formatCap(t.salaryCap))
                                .font(.system(size: DSType.Size.micro, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }
                    } else {
                        Text("No cap data")
                            .font(.system(size: DSType.Size.caption))
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
                    //
                    // No bar under it any more. The bar plotted the stat that
                    // was already maxed while morale — the number the club can
                    // still move — got none, so the card's whole visual weight
                    // sat on the one figure nobody has to act on. The four
                    // readings sit as a matched set instead.
                    HStack {
                        Text("Chemistry")
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(LockerRoomEngine.chemistryLabel(teamChemistry)) \(teamChemistry)/100")
                            .font(.system(size: DSType.Size.footnote, weight: .semibold))
                            .foregroundStyle(chemistryColor(teamChemistry))
                    }

                    // Morale percentage
                    HStack {
                        Text("Team Morale")
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(teamMorale)%")
                            .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                            .foregroundStyle(moraleColor(teamMorale))
                    }

                    // The city's read, beside the room's. `Career.fanSupport`
                    // is where the podium's FANS number lands — it used to be
                    // the second-biggest figure on the press screen and was
                    // written to no state at all, so it had nowhere to be read
                    // back. This is that place.
                    HStack {
                        Text("Fan Support")
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("\(career.fanSupport)%")
                            .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                            .foregroundStyle(moraleColor(career.fanSupport))
                    }

                    // Star players morale indicator. The face alone stood in for
                    // a 0-100 the engine models exactly, on the same card that
                    // prints three other moods as percentages — so it carries
                    // the number too, and the glyph is the quick read.
                    if let qb = startingQB {
                        HStack(spacing: 4) {
                            Text("QB")
                                .font(.system(size: DSType.Size.caption, weight: .bold))
                                .foregroundStyle(Color.accentGold)
                            Text(qb.lastName)
                                .font(.system(size: DSType.Size.micro, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(qb.morale)%")
                                .font(.system(size: DSType.Size.footnote, weight: .semibold).monospacedDigit())
                                .foregroundStyle(moraleColor(qb.morale))
                            Image(systemName: qb.morale >= 70 ? "face.smiling" : (qb.morale >= 40 ? "face.dashed" : "cloud.rain"))
                                .font(.system(size: DSType.Size.micro))
                                .foregroundStyle(moraleColor(qb.morale))
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Key Players Tile (#18)

    /// The men the tile names, each with the reason he is on it.
    ///
    /// Three rows used to be hard-coded — the starting QB, the best defender,
    /// the highest OVR — which is one roster question ("who is good?") asked
    /// three times. The two rows added here are the ones the OVR column cannot
    /// answer and that decide a spring: who the MONEY is on, and who is about
    /// to be out of contract. Deduplicated by id, so a franchise QB who is also
    /// the biggest cap hit takes the first tag that fits him rather than
    /// appearing twice.
    private var keyPlayerRows: [(label: String, player: Player)] {
        var rows: [(label: String, player: Player)] = []
        var seen: Set<UUID> = []

        func add(_ label: String, _ player: Player?) {
            guard let player, !seen.contains(player.id) else { return }
            seen.insert(player.id)
            rows.append((label: label, player: player))
        }

        add("QB1", startingQB)
        // Best defensive player (#144) — tagged with his own position.
        add(bestDefensivePlayer?.position.rawValue ?? "DEF", bestDefensivePlayer)
        // Labelled "TOP", not "MVP": `bestPlayer` is simply the highest OVR on
        // the roster, so the row read as a season award in Week 1 before a snap
        // and never moved by Week 18. The other rows are roster facts; this one
        // is too.
        add("TOP", bestPlayer)
        add("CAP", biggestCapHit)
        add("EXP", topExpiringPlayer)

        return rows
    }

    /// The largest single salary on the books — the row the three OVR rows
    /// could never produce, and the one a cap decision starts from.
    private var biggestCapHit: Player? {
        players.max(by: { $0.annualSalary < $1.annualSalary })
    }

    /// The best man in the last year of his deal. Same `contractYearsRemaining
    /// <= 1` test the Contracts tile counts on, so the two cannot disagree.
    private var topExpiringPlayer: Player? {
        expiringContractPlayers.max(by: { $0.overall < $1.overall })
    }

    private var keyPlayersTile: some View {
        let rows = keyPlayerRows
        return NavigationLink {
            RosterViewWrapper(career: career)
        } label: {
            DashboardTile(icon: "star.fill", title: "Key Players") {
                VStack(alignment: .leading, spacing: 4) {
                    if startingQB == nil {
                        Text("No starting QB")
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textSecondary)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.player.id) { index, row in
                        if index > 0 {
                            Divider().overlay(Color.surfaceBorder.opacity(0.4))
                        }
                        keyPlayerRow(label: row.label, player: row.player)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func keyPlayerRow(label: String, player: Player) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: DSType.Size.caption, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .frame(width: 28, alignment: .leading)
            Text(player.fullName)
                .font(.system(size: DSType.Size.footnote, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(player.overall)")
                .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
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
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textSecondary)
                } else {
                    // The weakest group — flagged only when it is weak in
                    // ABSOLUTE terms (#146). A bare `min` stamps NEED on exactly
                    // one group no matter how strong the roster is, so a club of
                    // straight A's still carried a red flag and the badge said
                    // nothing. 70 is `PositionGradeCalculator`'s own B-/C+ line:
                    // below it the starters really are under the league bar.
                    // "No need on this roster" is a real and useful answer.
                    let weakest = positionGroupGrades.min(by: { $0.starterOVR < $1.starterOVR })
                    let weakestGroup: String? = (weakest?.starterOVR ?? 100) < 70 ? weakest?.group : nil
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
                    // Key first: "S: A / D: B-" was unreadable without it. NEED
                    // is keyed too, and only while one is on screen — it was
                    // the one mark on the tile the legend never defined.
                    Text(weakestGroup == nil
                         ? "S = starters \u{00B7} D = depth \u{00B7} tap a grade for details"
                         : "S = starters \u{00B7} D = depth \u{00B7} NEED = weakest starters \u{00B7} tap a grade")
                        .font(.system(size: DSType.Size.footnote, weight: .medium))
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
                .font(.system(size: DSType.Size.micro, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 22, alignment: .leading)
            Text("S:")
                .font(.system(size: DSType.Size.caption, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            gradeButton(group: item.group, kind: "S", grade: item.starterGrade, ovr: item.starterOVR)
            Text("/")
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiary)
            Text("D:")
                .font(.system(size: DSType.Size.caption, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            gradeButton(group: item.group, kind: "D", grade: item.depthGrade, ovr: item.depthOVR)
            if isWeakest {
                Text("NEED")
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
                    // R39 device coverage: on iPad mini the grid column runs
                    // out of width and this badge wrapped into a vertical
                    // letter stack — shrink instead of wrapping.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Color.dangerText)
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
            // A fixed cell rather than a hugging label, for two reasons. The
            // column: a one-character starter grade used to shove the rest of
            // its row left, so "/ D:" landed ~35 px apart down a tile whose
            // whole job is a side-by-side scan. The target: the caption promises
            // "tap a grade" and the bare glyph was roughly 14x17 pt.
            Text(grade)
                .font(.system(size: DSType.Size.body, weight: .bold))
                .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(grade))
                .padding(.leading, 2)
                .frame(width: 26, height: 32, alignment: .leading)
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
                    .font(.system(size: DSType.Size.caption, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentGold.opacity(0.15)))
                Text(kindLabel)
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(grade)
                    .font(.system(size: DSType.Size.title2, weight: .black))
                    .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(grade))
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            VStack(alignment: .leading, spacing: 4) {
                Text("\(grade): \(description)")
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(percentile)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textSecondary)
                // Nothing averaged is not an average of zero: the ST room's
                // depth grade is `noDepthGrade` precisely because there is no
                // bench behind a kicker and a punter.
                if ovr > 0 {
                    Text("Average OVR: \(ovr)")
                        .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
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
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(.white)
                        Text("HIGH PRIORITY")
                            .font(.system(size: DSType.Size.caption, weight: .black))
                            .foregroundStyle(.white)
                            .tracking(0.5)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.danger))
                } else if !expiringContractPlayers.isEmpty {
                    // Outside the window: an amber chip, not a red alarm. With
                    // the denominator, because "42 expiring" alone is most of a
                    // roster stated as if it were a small number — "42 of 53" is
                    // the planning fact, and it is the same count either way.
                    Text("\(expiringContractPlayers.count) of \(players.count) expiring")
                        .font(.system(size: DSType.Size.caption, weight: .heavy))
                        .foregroundStyle(Color.warning)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.warning.opacity(0.15)))
                }

                if expiringContractPlayers.isEmpty {
                    Text("No expiring contracts")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textSecondary)
                } else {
                    if contractsHighPriority {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(expiringContractPlayers.count)")
                                .font(.system(size: DSType.Size.title2, weight: .bold).monospacedDigit())
                                .foregroundStyle(Color.dangerText)
                            Text("of \(players.count) expiring")
                                .font(.system(size: DSType.Size.caption, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                        }
                    } else {
                        Text("Re-sign window opens in the offseason")
                            .font(.system(size: DSType.Size.footnote))
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
                                .font(.system(size: DSType.Size.footnote, weight: .heavy))
                            Image(systemName: "arrow.right")
                                .font(.system(size: DSType.Size.micro, weight: .bold))
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
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.warning)
            }
            Text(player.position.rawValue)
                .font(.system(size: DSType.Size.caption, weight: .bold))
                .foregroundStyle(isStar ? Color.warning : Color.accentGold)
            Text(player.lastName)
                .font(.system(size: DSType.Size.micro, weight: isStar ? .bold : .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(player.overall)")
                .font(.system(size: DSType.Size.micro, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
            Text(formatCap(player.annualSalary))
                .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
            Image(systemName: "chevron.right")
                .font(.system(size: DSType.Size.micro, weight: .semibold))
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
                                .font(.system(size: DSType.Size.body, weight: .bold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            if hasPendingOwnerWhim {
                                Image(systemName: "envelope.badge.fill")
                                    .font(.system(size: DSType.Size.caption))
                                    .foregroundStyle(Color.warning)
                            }
                        }

                        HStack(spacing: 4) {
                            Image(systemName: archetype.icon)
                                .font(.system(size: DSType.Size.micro))
                            Text(archetype.displayName)
                                .font(.system(size: DSType.Size.caption, weight: .bold))
                        }
                        .foregroundStyle(Color.accentGold)

                        // Job security meter
                        HStack {
                            Text("Job Security")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(security.level.label)
                                .font(.system(size: DSType.Size.micro, weight: .bold))
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

                        // Primary goal progress (goals vs reality). Bound once:
                        // `evaluatedOwnerGoals` re-runs the whole goal
                        // evaluation on every read.
                        let goals = evaluatedOwnerGoals
                        if let primary = goals.first(where: { $0.priority == .primary }) {
                            // The card shows ONE goal; the Season Review tile two
                            // rows down reports "4 of 4 met" off the same set, so
                            // without this caption the owner card reads as the
                            // complete mandate and the two disagree.
                            if goals.count > 1 {
                                Text("Primary goal \u{00B7} \(goals.filter(\.isAchieved).count) of \(goals.count) met")
                                    .font(.system(size: DSType.Size.micro, weight: .medium))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            HStack(spacing: 4) {
                                Image(systemName: primary.isAchieved ? "star.fill" : "target")
                                    .font(.system(size: DSType.Size.micro))
                                    .foregroundStyle(primary.isAchieved ? Color.accentGold : Color.textSecondary)
                                Text(primary.title)
                                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                                Spacer()
                                if let target = primary.target {
                                    Text("\(primary.progress)/\(target)")
                                        .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                                        .foregroundStyle(primary.isAchieved ? Color.accentGold : Color.textSecondary)
                                } else if primary.isAchieved {
                                    Text("Met")
                                        .font(.system(size: DSType.Size.caption, weight: .bold))
                                        .foregroundStyle(Color.accentGold)
                                }
                            }
                        } else {
                            HStack {
                                Text("Satisfaction")
                                    .font(.system(size: DSType.Size.caption))
                                    .foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text("\(owner.satisfaction)%")
                                    .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                                    .foregroundStyle(satisfactionColor(owner.satisfaction))
                            }
                        }
                    } else {
                        Text("No owner data")
                            .font(.system(size: DSType.Size.caption))
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
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(record)
                            .font(.system(size: DSType.Size.title3, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        if career.championships > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "trophy.fill")
                                    .font(.system(size: DSType.Size.footnote))
                                    .foregroundStyle(Color.accentGold)
                                Text("\(career.championships)")
                                    .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Color.accentGold)
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        if career.playoffAppearances > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: DSType.Size.micro))
                                    .foregroundStyle(Color.success)
                                Text("\(career.playoffAppearances) playoff\(career.playoffAppearances == 1 ? "" : "s")")
                                    .font(.system(size: DSType.Size.micro, weight: .medium))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        Text("Career: \(career.totalWins)-\(career.totalLosses)")
                            .font(.system(size: DSType.Size.micro, weight: .medium))
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
                            .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.accentGold)
                    }
                    Text("\(picks.count) pick(s)")
                        .font(.system(size: DSType.Size.micro).monospacedDigit())
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
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text(formatCap(team?.availableCap ?? 0))
                            .font(.system(size: DSType.Size.footnote, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.success)
                    }
                    Text(stepLabel)
                        .font(.system(size: DSType.Size.micro))
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

    // #105 wave 2: `advanceReadinessBanner` (Fix #64) is gone.
    //
    // It was the third of three "what's next" metaphors on one screen, and the
    // only one that said nothing the panel three points below it did not
    // already say: "All tasks complete!" over a gold, enabled Advance button;
    // "N optional tasks open" over a list where those N rows are visible and
    // unchecked; "Week N game not played — advance will sim it" over the
    // panel's own footnote, "Your game is still unplayed — advancing sims it."
    // Deleting it costs no information and returns ~34 pt to the rail.

    // MARK: - Debug Skip-to-FA (DEBUG only)

    #if DEBUG
    /// Tracks whether a skip operation is currently running so the button can show progress.
    @State private var debugSkipRunning: Bool = false

    /// Temporary developer-only banner that exposes a "Skip → FA" button.
    /// Loops `WeekAdvancer.advanceWeek` until the career reaches `.freeAgency`
    /// or a safety cap is hit. Allows fast iteration on FA flow during Loop 2.
    private var debugSkipToFABanner: some View {
        // Shut in-season (both regular-season phases): from here the skip would
        // grind a whole season of play-by-play on the main actor. It used to be
        // shut in full gold — indistinguishable from the live chips under it,
        // so the first thing QA taps in-season is a control that does nothing.
        let blockedInSeason = career.currentPhase == .regularSeason
            || career.currentPhase == .tradeDeadline
        let chipTitle: String
        let chipIcon: String
        if blockedInSeason {
            chipTitle = "Skip unavailable in-season"
            chipIcon = "nosign"
        } else if debugSkipRunning {
            chipTitle = "Skipping…"
            chipIcon = "hourglass"
        } else {
            chipTitle = "Skip → \(debugSkipTargetLabel)"
            chipIcon = "forward.end.fill"
        }
        return HStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: DSType.Size.caption, weight: .bold))
                .foregroundStyle(Color.accentGold)
            Text("DEBUG")
                .font(.system(size: DSType.Size.micro, weight: .black))
                .foregroundStyle(Color.accentGold)
            Spacer(minLength: 4)
            Button {
                guard !debugSkipRunning else { return }
                Task { await skipToFreeAgency() }
            } label: {
                Label(chipTitle, systemImage: chipIcon)
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(blockedInSeason ? Color.backgroundTertiary : Color.accentGold.opacity(0.18))
                    .foregroundStyle(blockedInSeason ? Color.textTertiary : Color.accentGold)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(debugSkipRunning || blockedInSeason)
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

    // The coaching-budget blocker banner (#54) that used to head this rail is
    // gone. It printed `advanceBlocker.title` + `.detail` word for word, and
    // the tasks panel prints the same two sentences again ~700 pt below it —
    // the copy that sits directly above the disabled Advance button it
    // explains. One blocker, one host, and the host is the one beside the
    // control it is about.

    // #105 wave 2: `nextActionHero` is gone.
    //
    // A full-width gold-bordered card whose only job was to name the topmost
    // incomplete required task — the row the rail already draws, already
    // marks, and already makes tappable, a few hundred points to its left. It
    // was also the screen's second gold call to action, competing with the
    // phase hero card's commit for the same eye (P5: one primary action, one
    // place, one gold). Its one piece of real content, `task.description`, now
    // rides on the task row itself as the cost/unlock line (P4).

    // MARK: - Satisfaction Scores Row

    private var satisfactionScoresRow: some View {
        let ownerSat = team?.owner?.satisfaction ?? 50
        let legacyPts = career.legacy.totalPoints
        let mediaRep = career.legacy.mediaReputation

        return HStack(spacing: DSSpacing.xs) {
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
            // Legacy is a SIGNED running total (broken press promises subtract),
            // so it takes the same "+15" the Team Accolades tile prints for the
            // same number, and it is coloured by that sign. It was painted
            // permanent gold at any value: the row's loudest colour, and the
            // screen's emphasis hue, spent on its one tile that made no claim.
            satisfactionCard(
                icon: "trophy.fill",
                label: "Legacy",
                value: signedLegacy(legacyPts),
                color: legacyPts > 0 ? Color.success : (legacyPts < 0 ? Color.dangerText : Color.textSecondary)
            )
        }
    }

    private func satisfactionCard(icon: String, label: String, value: String, color: Color) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: DSType.Size.body, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: DSType.Size.caption, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .tracking(0.3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    /// Media reputation is a SIGNED −100…100 standing, not a rating, so P7
    /// rule 2 applies: status at a stated threshold, never the rating ladder.
    /// The bands are `LegacyTracker.reputationLabel`'s own — the tile must not
    /// read "Scrutinized" in green. The pragma is the sanctioned form for a
    /// signed scale the ladder has no rung for (see
    /// `ProspectDetailView.projectionColor`); the palette is still the shared
    /// one, only the thresholds are local.
    private func mediaReputationColor(_ value: Int) -> Color { // ds-lint:allow(ratingfn)
        if value >= 30  { return .forStatus(.ok) }      // Well-Liked / Darling
        if value >= -10 { return .forStatus(.neutral) } // Respected / Neutral
        if value >= -30 { return .forStatus(.warn) }    // Scrutinized
        return .forStatus(.bad)                         // Controversial / Villain
    }

    // NOTE: `ownerSatisfactionBar` removed with #175. Its one caller was the
    // Team tile, whose owner line came off when the tile stopped opening Owner
    // Relations; the owner's standing with the club is the Owner tile's job and
    // `satisfactionScoresRow`'s, both of which still use `satisfactionColor`.

    private func moraleLabel(_ morale: Int) -> String {
        if morale >= 80 { return "Excellent" }
        if morale >= 60 { return "Good" }
        if morale >= 40 { return "Neutral" }
        if morale >= 20 { return "Poor" }
        return "Toxic"
    }

    /// Unified onto `Color.forRating(scale: .percent)` — the twin in
    /// `LockerRoomView` already was, and a three-band ladder here meant 74
    /// morale read yellow on the dashboard and blue in the Locker Room.
    private func moraleColor(_ morale: Int) -> Color {
        Color.forRating(morale, scale: .percent)
    }

    /// Unified onto `Color.forRating(scale: .percent)` so the dashboard tile and
    /// the Locker Room screen tint the same score identically. They did not: the
    /// bespoke bands here were 90/75/55/40 against the ladder's 90/80/70/60, and
    /// 90+ painted gold — a hue P7 reserves for "primary/current".
    private func chemistryColor(_ value: Int) -> Color {
        Color.forRating(value, scale: .percent)
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

    /// The "Available" figure's colour, on `capBarColor`'s thresholds so the
    /// number and the bar above it cannot disagree. `dangerText` rather than
    /// `danger` because this one is text on the card, not a fill.
    private func availableCapColor(available: Int, usedFraction: Double) -> Color {
        if available <= 0 || usedFraction > 0.9 { return Color.dangerText }
        if usedFraction > 0.8 { return Color.warning }
        return Color.success
    }

    /// Owner satisfaction is printed as a percentage and read alongside morale
    /// and chemistry in the same row of tiles, so it takes the same ladder.
    private func satisfactionColor(_ value: Int) -> Color {
        Color.forRating(value, scale: .percent)
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
        // `SeasonPhase.displayName`, not a fifth private table. This switch was
        // one of five maps for the same enum and the only one that called
        // `.reviewRoster` "Roster Review" — the phase the rail, the guide and
        // the enum itself all call "Review Roster".
        let phaseLabel = career.currentPhase.displayName

        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: DSType.Size.title3, weight: .semibold))
                .foregroundStyle(Color.accentGold)

            VStack(alignment: .leading, spacing: 2) {
                if weeks > 0 {
                    Text("Week 1 in ~\(weeks) week\(weeks == 1 ? "" : "s")")
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                } else {
                    Text("Season starts soon")
                        .font(.system(size: DSType.Size.footnote, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                }
                Text("Currently: \(phaseLabel)")
                    .font(.system(size: DSType.Size.micro, weight: .medium))
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

    /// Last season's final division table — what the DIVISION card shows while
    /// this season's rows would all read 0-0.
    ///
    /// Ordered on wins alone, with the id tiebreaker the rest of this screen
    /// uses for stability (#134), and deliberately uncrowned: the club that
    /// actually won the division was decided by tiebreakers `Team`'s one-year
    /// memory does not carry, and a crown on the wrong badge is worse than no
    /// crown.
    @ViewBuilder
    private var lastSeasonDivisionTable: some View {
        let ranked = divisionTeams
            .filter(\.hasLastSeasonRecord)
            .sorted {
                $0.lastSeasonWins != $1.lastSeasonWins
                    ? $0.lastSeasonWins > $1.lastSeasonWins
                    : $0.id.uuidString < $1.id.uuidString
            }

        Text("Last season \u{00B7} final")
            .font(.system(size: DSType.Size.caption, weight: .bold))
            .foregroundStyle(Color.textTertiary)
            .tracking(0.5)

        ForEach(ranked, id: \.id) { t in
            let isMyTeam = t.id == team?.id
            HStack(spacing: 4) {
                Text(t.abbreviation)
                    .font(.system(size: DSType.Size.caption, weight: isMyTeam ? .heavy : .medium))
                    .foregroundStyle(isMyTeam ? Color.accentGold : Color.textSecondary)
                    .frame(width: 44, alignment: .leading)
                Text(t.fullName)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(isMyTeam ? Color.textSecondary : Color.textTertiaryReadable)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(t.lastSeasonWins)-\(t.lastSeasonLosses)")
                    .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                    .foregroundStyle(isMyTeam ? Color.accentGold : Color.textSecondary)
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.vertical, 2)
        }
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

    /// Nil when the club's slot in the division cannot be read — the tile then
    /// prints the record alone rather than an em dash where a rank belongs.
    private var divisionRank: String? {
        guard let myTeam = team else { return nil }
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
        return nil
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
        headCoach = coaches.first(where: { $0.role == .headCoach })

        let scoutDescriptor = FetchDescriptor<Scout>(
            predicate: #Predicate { $0.careerID == cid && $0.teamID == teamID }
        )
        let fetchedScouts = (try? modelContext.fetch(scoutDescriptor)) ?? []
        // Handed to `DraftPrepProgress` by the Path to the Draft hero card;
        // re-assigned here so popping back from the scouting hub (which runs
        // `refreshStaffTile` via `.onAppear`) re-evaluates the card.
        scouts = fetchedScouts

        // #133: ONE reading — seats, all three pots and the advance gate. The
        // owner is resolved from the store rather than from the `team` @State,
        // which is written by `loadAllDataBody`: reading it here made the tile's
        // money depend on which of the two load paths had run first on a given
        // launch, and that is half of "the budget is different after a
        // relaunch". The other half was the per-surface fallback the ledger now
        // owns.
        let clubOwner = team?.owner ?? {
            let teamDescriptor = FetchDescriptor<Team>(
                predicate: #Predicate<Team> { $0.careerID == cid && $0.id == teamID }
            )
            return (try? modelContext.fetch(teamDescriptor))?.first?.owner
        }()
        staffLedger = StaffLedger(
            careerRole: career.role,
            coaches: coaches,
            scouts: fetchedScouts,
            owner: clubOwner
        )

        // Last, because it reads the `scouts` this function just wrote. Hung
        // here rather than on `loadAllDataBody` alone so the pop-back path —
        // which is exactly the trip that spends interview slots and reserves
        // pro-day schools — refreshes the card too (#fleet review F8).
        refreshDraftPrepCache()
    }

    /// The roster fetch and every tile derived from it.
    ///
    /// Split out of `loadAllDataBody` for the same reason `refreshStaffTile`
    /// was (#106): the pop-back path has to re-read the roster, and the full
    /// load refetches every game of two seasons to do it. The hub's Position
    /// Grades tile and the Roster Evaluation screen run the identical
    /// calculator, so a stale snapshot here does not read as stale — it reads
    /// as the two screens disagreeing about the same room's depth.
    private func refreshRosterDerived() {
        guard let teamID = career.teamID else { return }

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

        // The training / week-prep splits the Camp and Week Prep tiles print.
        // Here rather than in the full load because both are set on a PUSHED
        // screen: the pop-back path is exactly the trip that changes them.
        loadSavedPlans()

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

        // The roster and everything read off it.
        refreshRosterDerived()

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
    ///
    /// **The nine groups are the Roster Evaluation screen's nine**, down to the
    /// labels. This table used to split the secondary into CB and S and leave
    /// the K/P room off the hub entirely, so the two screens graded different
    /// rooms under the same heading — a hub safety grade that no row on the
    /// priorities screen could be reconciled with, and a specialist room the
    /// hub could not flag at all. Change one taxonomy and change the other.
    private func calculatePositionGroupGrades(players: [Player]) -> [(group: String, starterGrade: String, depthGrade: String, starterOVR: Int, depthOVR: Int)] {
        let groups: [(label: String, positions: [Position])] = [
            ("QB", [.QB]),
            ("RB", [.RB, .FB]),
            ("WR", [.WR]),
            ("TE", [.TE]),
            ("OL", [.LT, .LG, .C, .RG, .RT]),
            ("DL", [.DE, .DT]),
            ("LB", [.OLB, .MLB]),
            ("DB", [.CB, .FS, .SS]),
            ("ST", [.K, .P]),
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
        // The two phases used to share one card, and it pointed its gold at
        // Roster Review — step 2 — while the rail beside it said the staff
        // seats hold step 1 shut. A card whose only route is the one the
        // screen refuses is worse than no card.
        case .coachingChanges:
            coachingChangesHeroCard
        case .reviewRoster:
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
                    .font(.system(size: DSType.Size.title1, weight: .semibold))
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

    /// The card's one headline, on the app's own ladder rather than on the
    /// system's `.title2` role — `DSType.Size.title2` is the same 22 pt step,
    /// and it is the step every other section title on the surface is measured
    /// against.
    @ViewBuilder
    private func heroHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: DSType.Size.title2, weight: .heavy))
            .foregroundStyle(Color.textPrimary)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
    }

    /// Legacy points are a signed running total — broken press promises subtract
    /// (championship -15, playoffs -8, overhaul -6), so a hard-coded "+" prefix
    /// can print "+-15". Sign it from the value instead.
    private func signedLegacy(_ points: Int) -> String {
        points > 0 ? "+\(points)" : "\(points)"
    }

    @ViewBuilder
    private func heroStatRow(_ label: String, value: String, accent: Color = .accentGold) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text(label)
                .font(.system(size: DSType.Size.body, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                .foregroundStyle(accent)
                .multilineTextAlignment(.trailing)
        }
    }

    /// **True when the rail's Advance button is the screen's gold** (P5).
    ///
    /// One gold fill per screen, and the two candidates for it are the hero
    /// card's action and the Advance button. The rule that decides between them
    /// is not taste: while the phase still has required work, the work is the
    /// primary move; the moment it does not, leaving the phase is. The one
    /// exception is an unplayed game, where "Coach the Game" outranks a button
    /// that would sim it away — which is the same predicate `advanceIsPrimary`
    /// already passes to the panel, so the two cannot disagree.
    private var advanceOwnsTheGold: Bool { canAdvance && !weeklyGameUnplayed }

    /// The hero card's push CTA.
    ///
    /// Gold-filled while it is the primary move, ghost once Advance has taken
    /// the gold. Before this every hero card fill was unconditional, so on a
    /// finished week the dashboard showed two full-strength gold capsules —
    /// "Set Game Plan" and "Advance to Week N" — and made the user pick.
    @ViewBuilder
    private func heroActionLink(title: String, destination: TaskDestination) -> some View {
        let isPrimary = !advanceOwnsTheGold
        Button {
            onTaskSelected(destination)
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.system(size: DSType.Size.body, weight: .bold))
                Image(systemName: "arrow.right")
                    .font(.system(size: DSType.Size.body, weight: .bold))
            }
            .foregroundStyle(isPrimary ? Color.backgroundPrimary : Color.accentGold)
            .padding(.horizontal, DSSpacing.md)
            // §2.12, measured: at 8 pt of padding around a 15 pt label the
            // week's own call to action was a 33 pt target.
            .frame(minHeight: 44)
            .background(
                isPrimary ? Color.accentGold : Color.accentGold.opacity(0.14),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Phase-specific hero cards

    /// Share of the roster the workload engine currently rates over-loaded or
    /// burned out — the number the Workload heat-map is coloured by.
    private var overloadedShare: Int {
        guard !players.isEmpty else { return 0 }
        let hot = players.filter {
            $0.workloadStatus == .overloaded || $0.workloadStatus == .burnedOut
        }.count
        return Int((Double(hot) / Double(players.count) * 100).rounded())
    }

    /// #105 wave 2, P4: every row here used to be a literal — "18% overloaded"
    /// over a roster the workload engine had never touched, "3" battles beside
    /// a tile that said "None active", and an "A+" glued onto whichever player
    /// happened to have the highest OVR, which is not a camp grade at all. The
    /// card also offered "View Training Plan" and then opened the roster.
    ///
    /// The "Day N / 21" counter is gone for the same reason: it was derived
    /// from `career.currentWeek`, which sits at 19+ for the whole offseason
    /// (only `startNewSeason` resets it), so `min(21, currentWeek)` printed
    /// "Day 21 / 21" on the first visit — and there is no 21-day camp clock in
    /// the model to print honestly instead. Camp is one visit, so the header
    /// names the phase and the rows carry the real numbers.
    private var campHeroCard: some View {
        let topGrade = topCampGraded.first
        // Same A-only reading as the Preseason card's standouts row: with no A
        // in camp there is still a grade on every man, so the only ungraded camp
        // is the one where `campGradedCount` is zero.
        let topGradeValue: String = {
            if let topGrade { return "\(topGrade.name) · \(topGrade.grade.displayLabel)" }
            let graded = campGradedCount
            return graded == 0 ? "Not graded yet" : "No A grades — \(graded) graded"
        }()
        let battles = openPositionBattles.count
        // `phaseHeroCard` routes BOTH `.otas` and `.trainingCamp` here, and the
        // header was the literal "Training Camp · Install & Evaluation" — so the
        // spring's first phase, which the rail, the season band and the phase
        // list all call OTAs, opened under a card announcing a camp that starts
        // weeks later. One card is right (the two phases offer the same work);
        // naming the wrong one is not. The rows below hold for both.
        let isOTAs = career.currentPhase == .otas
        return phaseCardBase(icon: "figure.strengthtraining.traditional", accent: .accentGold) {
            heroHeader(isOTAs
                       ? "OTAs · Install & Conditioning"
                       : "Training Camp · Install & Evaluation")
            // Camp is one visit, and on that visit all three outcome rows are
            // structurally empty — so the roster the player HAS goes first, and
            // gold is kept off the blanks. "Workload heatmap" also named a
            // screen where the label should name the metric beside it.
            heroStatRow("Roster", value: "\(players.count) \(isOTAs ? "under contract" : "in camp")")
            heroStatRow("Squad workload",
                        value: "\(overloadedShare)% overloaded",
                        accent: overloadedShare >= 20 ? .warning : .textSecondary)
            heroStatRow("Active battles",
                        value: "\(battles)",
                        accent: battles == 0 ? .textSecondary : .accentGold)
            heroStatRow("Top camp grade",
                        value: topGradeValue,
                        accent: topGrade == nil ? .textSecondary : .accentGold)
            heroActionLink(title: "Open Training Plan", destination: .trainingPlan)
        }
    }

    /// Snap counts are not tracked for exhibition games in this build, so the
    /// "60% starters / 40% backups" row was describing a number that does not
    /// exist, and "View Snap Counts" opened a roster that has none. What the
    /// preseason actually decides is who dresses and who is healthy enough to.
    ///
    /// The game number is the phase's own business, never the week counter's.
    /// `career.currentWeek` is 19+ from the playoffs onwards and is only reset
    /// in `startNewSeason`, so the old `min(3, career.currentWeek)` printed
    /// "Game 3 / 3" from the first exhibition on. `PreseasonState.step` is the
    /// authority `PreseasonView` itself reads (`currentGame`), so the hub reads
    /// the same value and the two screens cannot disagree. A missing or stale
    /// blob (different career, last year's slate) falls back to Game 1, which
    /// is exactly what a freshly opened preseason is.
    private var preseasonHeroCard: some View {
        let flow = career.preseasonState.flatMap { $0.matches(career: career) ? $0 : nil }
        let slateComplete = flow?.isComplete ?? false
        let gameNum = min(PreseasonFlowBand.gameCount, max(1, flow?.step.gameIndex ?? 1))
        let injuredCount = players.filter(\.isInjured).count
        let standouts = topCampGraded.count
        // "None graded yet" was printed off a count that only ever holds A and
        // A+ men, so a fully graded camp of Cs and Ds read as an ungraded one —
        // while the cut list two taps away was showing the letters.
        let standoutsValue: String = {
            if standouts > 0 { return "\(standouts) at A or better" }
            let graded = campGradedCount
            return graded == 0 ? "Not graded yet" : "No A grades — \(graded) graded"
        }()
        return phaseCardBase(icon: "sportscourt.fill", accent: .accentGold) {
            heroHeader(slateComplete
                       ? "Preseason · Slate complete"
                       : "Preseason · Game \(gameNum) / \(PreseasonFlowBand.gameCount)")
            heroStatRow("Exhibitions played",
                        value: "\(flow?.results.count ?? 0) of \(flow?.slate.count ?? PreseasonFlowBand.gameCount)",
                        accent: slateComplete ? .success : .accentGold)
            heroStatRow("Roster", value: "\(players.count) in camp")
            heroStatRow("Camp standouts", value: standoutsValue)
            heroStatRow("Injuries",
                        value: injuredCount == 0 ? "Fully healthy" : "\(injuredCount) OUT",
                        accent: injuredCount == 0 ? .success : .warning)
            // #205b: the card's one link is the thing the phase is FOR. It used
            // to open the depth chart — a screen with its own task row — while
            // the slate this card is describing had no door anywhere in the app.
            heroActionLink(title: slateComplete ? "Review Preseason" : "Play Preseason Game",
                           destination: .preseason)
        }
    }

    /// The cut ladder, derived rather than asserted. `RosterCutView` keeps its
    /// stage in view-local `@State`, so this card cannot read it — but the
    /// stage is a pure function of the roster count against the same 75/65/53
    /// ceilings that view uses, which is why "Cut 1 of 3 (90→75)" could sit
    /// over a 61-man roster. "Practice squad protected: 7" is gone outright:
    /// the practice-squad flags live in that same view-local state and there is
    /// nothing persisted to count.
    private var rosterCutsHeroCard: some View {
        let count = players.count
        let stage: (index: Int, ceiling: Int) = {
            if count > 75 { return (1, 75) }
            if count > 65 { return (2, 65) }
            return (3, 53)
        }()
        let remaining = max(0, count - stage.ceiling)
        return phaseCardBase(icon: "scissors", accent: .draftStealGold) {
            heroHeader("Roster Cuts · 90 → 53")
            heroStatRow("Stage", value: "Cut \(stage.index) of 3 (\(count)→\(stage.ceiling))")
            heroStatRow("Still to release",
                        value: remaining == 0 ? "None — stage clear" : "\(remaining)",
                        accent: remaining == 0 ? .success : .warning)
            // Task #87 / F18: "Cap savings projected $4.2M" was a literal. There
            // is no cut plan to project from at this point in the flow, so the
            // row is gone rather than invented — current room is a real number.
            heroStatRow("Cap room", value: formatCap(team?.availableCap ?? 0))
            heroActionLink(title: "Make Cuts", destination: .rosterCuts)
        }
    }

    private var regularSeasonHeroCard: some View {
        // The matchup this card describes: this week's game whether or not
        // it's been played yet; falls back to the next scheduled game
        // (upcomingGames only holds unplayed ones, so it alone would skip
        // ahead to next week's opponent as soon as the game finishes).
        let currentWeekPlayed = currentWeekPlayedGame
        let heroGame = currentWeekFixture
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
        let playerTeam = career.teamID.flatMap { allTeamsByID[$0] }
        let injuredCount = players.filter(\.isInjured).count
        return phaseCardBase(icon: "calendar.badge.clock", accent: .accentGold) {
            heroHeader(isByeWeek
                       ? "Week \(career.currentWeek) · Bye Week"
                       : "Week \(week) · \(oppText)")
            // R19: late-season stakes — only rendered when provably true.
            if let stakes = seasonStakes {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: stakes.urgent ? "exclamationmark.triangle.fill" : "flame.fill")
                        .font(.system(size: DSType.Size.caption, weight: .bold))
                    Text(stakes.text)
                        .font(.system(size: DSType.Size.footnote, weight: .heavy))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                // `dangerText`, not `danger`: this badge is words on a card, and
                // DSTokens is explicit that #EF4444 is ~3.4:1 there — keep the
                // fill red for fills and bars.
                .foregroundStyle(stakes.urgent ? Color.dangerText : Color.accentGold)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(
                    (stakes.urgent ? Color.danger : Color.accentGold).opacity(0.14),
                    in: Capsule()
                )
            }
            heroStatRow("Record", value: playerTeam?.record ?? "—")
            heroStatRow("Injuries", value: injuredCount == 0 ? "Fully healthy" : "\(injuredCount) OUT")
            if currentWeekPlayerGame != nil {
                // The week's two moves, and the only pair of buttons on the
                // screen: the gold one plays Sunday, the ghost one prepares for
                // it. Both cleared to the 44 pt floor — they were 33.
                HStack(spacing: DSSpacing.sm) {
                    Button {
                        startCoachedGame()
                    } label: {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "headset")
                                .font(.system(size: DSType.Size.body, weight: .bold))
                            Text("Coach the Game")
                                .font(.system(size: DSType.Size.body, weight: .bold))
                        }
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, DSSpacing.md)
                        .frame(minHeight: 44)
                        .background(Color.accentGold, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onTaskSelected(.gamePlan)
                    } label: {
                        Text("Game Plan")
                            .font(.system(size: DSType.Size.body, weight: .bold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, DSSpacing.md)
                            .frame(minHeight: 44)
                            .background(Color.accentGold.opacity(0.14), in: Capsule())
                            .contentShape(Capsule())
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

    // MARK: Playoffs (#173)

    /// Bracket stage key for a playoff week. The numbering is the one
    /// `WeekAdvancer.ensurePlayoffGames` stages games with: 19 Wild Card,
    /// 20 Divisional, 21 Conference Championship, 22 The Championship.
    private func playoffRoundKey(forWeek week: Int) -> String {
        switch week {
        case 20:            return "DIV"
        case 21:            return "CONF"
        case let w where w >= 22: return "SB"
        default:            return "WC"
        }
    }

    private func playoffRoundName(forWeek week: Int) -> String {
        switch playoffRoundKey(forWeek: week) {
        case "DIV":  return "Divisional Round"
        case "CONF": return "Conference Championship"
        case "SB":   return "The Championship"
        default:     return "Wild Card"
        }
    }

    /// Seed number (1…7) for every postseason team, both conferences, keyed by
    /// team id. Recomputed with the same `StandingsCalculator` call the bracket
    /// itself was staged from, so the number on this card and the pairing in
    /// the bracket can never disagree. Teams that missed the field are absent.
    ///
    /// #173: the card used to print "Vs Seed #5" as a literal, in every round
    /// of every season, for a club that may not even be in the playoffs.
    private func playoffSeedRanks() -> [UUID: Int] {
        guard !allTeamsByID.isEmpty else { return [:] }
        let cid = career.id
        let seasonYear = career.currentSeason
        // Seeding is a regular-season question and `StandingsCalculator`
        // discards bracket rows anyway, so they never cross the fetch boundary
        // on this (per-body) call. `isPlayed` is computed, not stored — it
        // cannot live in a `#Predicate`, and the calculator filters it itself.
        let descriptor = FetchDescriptor<Game>(predicate: #Predicate<Game> {
            $0.careerID == cid && $0.seasonYear == seasonYear && $0.isPlayoff == false
        })
        let games = (try? modelContext.fetch(descriptor)) ?? []
        let teams = Array(allTeamsByID.values)
        let records = StandingsCalculator.calculate(games: games, teams: teams)
        var ranks: [UUID: Int] = [:]
        for conference in Conference.allCases {
            let seeds = StandingsCalculator.playoffTeams(
                records: records, teams: teams, conference: conference
            )
            for (index, record) in seeds.enumerated() {
                ranks[record.teamID] = index + 1
            }
        }
        return ranks
    }

    private var playoffsHeroCard: some View {
        let week = career.currentWeek
        let currentKey = playoffRoundKey(forWeek: week)
        let seedRanks = playoffSeedRanks()
        let myID = career.teamID
        let mySeed = myID.flatMap { seedRanks[$0] }
        let conferenceTag = team.map { " (\($0.conference.rawValue))" } ?? ""

        // This round's game for my club — unplayed (upcomingGames carries
        // playoff rows too) or already on the board this same week.
        let roundGame: Game? = upcomingGames.first(where: { $0.isPlayoff && $0.week == week })
            ?? lastGame.flatMap { $0.isPlayoff && $0.week == week ? $0 : nil }

        // A playoff loss ends the season, so the most recent played game is a
        // sufficient elimination test.
        let eliminationWeek: Int? = {
            guard let myID, let last = lastGame, last.isPlayoff, last.isPlayed,
                  last.loserID == myID else { return nil }
            return last.week
        }()

        let matchup: (label: String, value: String)? = {
            guard let game = roundGame, let myID else { return nil }
            let isHome = game.homeTeamID == myID
            let oppID = isHome ? game.awayTeamID : game.homeTeamID
            let oppAbbr = allTeamsByID[oppID]?.abbreviation ?? "TBD"
            let oppSeed = seedRanks[oppID].map { "#\($0) " } ?? ""
            if game.isPlayed, let home = game.homeScore, let away = game.awayScore {
                let mine = isHome ? home : away
                let theirs = isHome ? away : home
                let tag = mine > theirs ? "W" : (mine < theirs ? "L" : "T")
                return ("Result", "\(tag) \(mine)–\(theirs) vs \(oppSeed)\(oppAbbr)")
            }
            return ("Matchup", isHome
                    ? "vs \(oppSeed)\(oppAbbr) (Home)"
                    : "@ \(oppSeed)\(oppAbbr) (Away)")
        }()

        return phaseCardBase(icon: "trophy.fill", accent: .draftStealGold) {
            heroHeader("Playoffs · \(playoffRoundName(forWeek: week))")
            HStack(spacing: 6) {
                ForEach(["WC", "DIV", "CONF", "SB"], id: \.self) { stage in
                    Text(stage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(stage == currentKey ? Color.backgroundPrimary : Color.textTertiary)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(stage == currentKey ? Color.accentGold : Color.backgroundTertiary, in: Capsule())
                }
            }

            if let mySeed {
                heroStatRow("Your seed", value: "#\(mySeed)\(conferenceTag)")

                if let eliminationWeek {
                    heroStatRow("Season",
                                value: "Eliminated in the \(playoffRoundName(forWeek: eliminationWeek))",
                                accent: .danger)
                    heroActionLink(title: "View Bracket", destination: .standings)
                } else if let matchup {
                    heroStatRow(matchup.label, value: matchup.value)
                    if roundGame?.isPlayed == true {
                        heroActionLink(title: "View Bracket", destination: .standings)
                    } else {
                        heroActionLink(title: "Game Plan", destination: .gamePlan)
                    }
                } else if mySeed == 1, currentKey == "WC" {
                    heroStatRow("Wild Card weekend",
                                value: "First-round bye — you open in the Divisional Round")
                    heroActionLink(title: "View Bracket", destination: .standings)
                } else {
                    heroStatRow("Next game", value: "Bracket pending")
                    heroActionLink(title: "View Bracket", destination: .standings)
                }
            } else if allTeamsByID.isEmpty {
                // #175 (LOW): the pre-load frame. `playoffSeedRanks()` returns
                // an empty map until `loadAllData` has filled `allTeamsByID`
                // (it guards on exactly that), so on the body pass before the
                // first load `mySeed` is nil for EVERY club — including the one
                // that just won the 1-seed. The old else-branch read that as
                // fact and flashed "Missed the playoffs" at a team in the
                // bracket. No seeding is not the same claim as no berth.
                heroStatRow("Your season", value: "Loading seeding…", accent: .textSecondary)
                heroActionLink(title: "View Bracket", destination: .standings)
            } else {
                heroStatRow("Your season",
                            value: "Missed the playoffs",
                            accent: .textSecondary)
                heroActionLink(title: "View Bracket", destination: .standings)
            }
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
    /// What it replaces: `combineHeroCard` titled itself "The Combine · 42%
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
        // offered "Advance to The Draft" over the one stage whose work the user
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
            // Denominator is the BAND's six working stages, not the engine's
            // nine steps — the hub one tap away says "Stage N of 6" (#164), and
            // two totals for one pipeline is the exact defect the band killed.
            heroStatRow("Stages worked",
                        value: "\(DraftPrepStageCell.bandSteps.filter { progress[$0].isSatisfied }.count) / \(DraftPrepStageCell.bandSteps.count)")

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
                        // Same stable handle as the sidebar's control — one
                        // advance path on this screen deserves one name.
                        .accessibilityIdentifier("hero.advance")
                    }
                }
                if !canAdvance {
                    // #fleet review F19e: no coaching-budget branch here. This
                    // card renders for `.combine` and `.proDays` only, and
                    // `advanceBlocker` is `.coachingChanges`-only, so
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
        let scouted = draftClass.filter({ ProspectFog.hasOwnReport($0) }).count
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

    /// #105 wave 2, P4: "7 hot · 2 outbid alerts", "5 top targets remaining"
    /// and "3 pending offers" were all literals. Nothing in the save persists
    /// a hot list, an outbid alert or an open offer — the bidding room builds
    /// those in its own state — so the card was inventing a market and then
    /// sending the user into a room that would disagree with it. It reports
    /// only what the club's own record can answer.
    private var faHeroCard: some View {
        let step = FreeAgencyStep(rawValue: career.freeAgencyStep) ?? .finalPush
        let stepLabel = step.rawValue.replacingOccurrences(
            of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression
        )
        return phaseCardBase(icon: "dollarsign.circle.fill", accent: .accentGold) {
            heroHeader("Free Agency · \(stepLabel)")
            heroStatRow("Cap space", value: formatCap(team?.availableCap ?? 0))
            heroStatRow("Under contract", value: "\(players.count) players")
            if step == .signing, career.freeAgencyRound > 0 {
                heroStatRow("Market", value: FreeAgencyStep.roundLabel(career.freeAgencyRound))
            }
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
    /// that still run next year, plus every forward row booked for it, against
    /// the projected cap. One arithmetic — literally `DealTargetYear.space`, the
    /// function the negotiation gate and `CapOverviewView`'s Y+1 bar read — so
    /// the dashboard and the cap screen cannot show the user two different 2027s.
    ///
    /// **#186 — it counted tags only.** This tile hand-rolled the sum and passed
    /// `forwardCommitted` the tagged men, which was the whole forward table back
    /// when the tag was the only thing that could book a future year. A deferred
    /// extension now parks its charge in the same table while deliberately
    /// leaving `annualSalary` at the old rate until the binding rollover, so an
    /// extended man was counted at his OLD number and his row was missed
    /// entirely: extend a $12.0M player at $45.0M and this card overstated next
    /// year's room by $33.0M while the Cap screen, correctly, showed the club
    /// over. Delegating removes the second copy of the arithmetic rather than
    /// repairing it — the whole roster goes in, and the row supersedes the man's
    /// stale salary for the years it covers.
    private var nextYearCapSpace: String {
        guard let team else { return "—" }
        let space = DealTargetYear.space(
            team: team,
            roster: players,
            currentSeason: career.currentSeason,
            seasonsAhead: 1,
            careerID: career.id,
            excluding: nil
        )
        // Negative room is a real state (a club can be committed past next
        // year's projected cap), and `formatCap` renders it as "$-8.3M" — a
        // string that reads as a typo rather than as a problem. Named instead.
        let capSpace = space.available
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
        // Starter average, not the whole-roster mean (QA 2026-08-21). This card
        // used to print the mean of every man under contract, which on an
        // offseason roster of up to 87 includes forty bodies who will never take
        // a snap — it read 68 on a club the team picker had just called 76, the
        // same label eight points apart on two screens of one save.
        // `RosterStrength` is now the single definition; see its doc comment.
        guard let current = RosterStrength.starterAverage(players) else { return nil }
        // Franchise-tagged men are NOT leaving: the tag is one more year of club
        // control and the rollover keeps them on the roster (#127).
        let retained = players.filter { $0.contractYearsRemaining > 1 || $0.isFranchiseTagged }
        guard retained.count < players.count else { return nil }
        guard let projected = RosterStrength.starterAverage(retained) else {
            return "\(current) → — (whole roster expiring)"
        }
        return "\(current) → \(projected) if none re-signed"
    }

    /// The Coaching Changes card: the seats that gate the phase, the pot they
    /// are hired out of, and one route — the Staff screen.
    ///
    /// The shared "Offseason Begins" card sent its gold at Roster Review, which
    /// is the step AFTER this one and the one `advanceBlocker` refuses while a
    /// coordinator seat is empty, and it offered no route to the screen that
    /// clears the block. It also opened on "Coach contracts expiring 0", which
    /// on a club with no staff at all is not news — it is the absence of a
    /// staff — so that row waits until there is someone to lose.
    private var coachingChangesHeroCard: some View {
        let vacantRequired = staffLedger?.missingRequiredRoles ?? []
        return phaseCardBase(icon: "person.2.fill", accent: .accentGold) {
            heroHeader("Coaching Changes")
            if vacantRequired.isEmpty {
                heroStatRow("Required seats", value: "All filled")
            } else {
                heroStatRow(
                    "Required seats vacant",
                    value: vacantRequired.map(\.abbreviation).joined(separator: ", "),
                    accent: .warning
                )
            }
            if let ledger = staffLedger, ledger.isResolved, ledger.coachingBudget > 0 {
                heroStatRow(
                    "Coaching budget left",
                    value: StaffLedger.money(ledger.remainingCoaching)
                        + " of " + StaffLedger.money(ledger.coachingBudget)
                )
            }
            if !allCoaches.isEmpty {
                heroStatRow("Coach contracts expiring", value: "\(expiringCoachCount)")
            }
            HStack(spacing: DSSpacing.sm) {
                heroActionLink(
                    title: vacantRequired.isEmpty ? "Review Staff" : "Hire Coordinators",
                    destination: .coachingStaff
                )
                heroSecondaryButton(title: "Salary Cap") {
                    onTaskSelected(.capOverview)
                }
            }
        }
    }

    private var offseasonOpenerHeroCard: some View {
        phaseCardBase(icon: "arrow.triangle.2.circlepath", accent: .accentGold) {
            heroHeader("Offseason Begins")
            heroStatRow("Coach contracts expiring", value: "\(expiringCoachCount)")
            if let rosterOVRProjection {
                heroStatRow("Roster OVR", value: rosterOVRProjection)
            }
            heroStatRow("Cap space (next yr)", value: nextYearCapSpace)
            // One gold per card (P5). These were two identical gold capsules
            // side by side, which made the screen ask the user to pick between
            // two primaries; the cap read supports the roster review, so it
            // wears the secondary treatment.
            // Named for the screen it opens, not for the phase. "Roster Review"
            // sat one character from the rail's "Advance to Review Roster" —
            // which commits the phase change and cannot be undone — so two
            // controls on one screen shared a name and meant different things.
            HStack(spacing: DSSpacing.sm) {
                heroActionLink(title: "Open Roster Evaluation", destination: .rosterEvaluation)
                heroSecondaryButton(title: "Salary Cap") {
                    onTaskSelected(.capOverview)
                }
            }
        }
    }

    /// "4 All-Stars · 1 MVP candidate · Awards results Pending" — three
    /// literals, and the first two were counts of things the save does not
    /// record per club. The honest content of this week is the season the club
    /// just played and the ledger it is judged on.
    private var seasonClimaxHeroCard: some View {
        let isProBowl = career.currentPhase == .proBowl
        return phaseCardBase(icon: isProBowl ? "star.fill" : "trophy.circle.fill", accent: .draftStealGold) {
            heroHeader(isProBowl ? "All-Star Game" : "The Championship")
            heroStatRow("Your season", value: seasonRecordSummary)
            heroStatRow("Legacy", value: signedLegacy(career.legacy.totalPoints))
            heroStatRow("Honors", value: "Announced in your inbox")
            heroActionLink(title: "Read the Inbox", destination: .inbox)
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
///
/// **The header is grey; only a highlighted tile's is gold.**
///
/// Every tile's icon and title used to be `accentGold`, which on a game week
/// meant twenty-eight gold objects in the grid alone — under a hero card and
/// beside a rail whose gold is supposed to mean "this is the decision". A tile's
/// name is not a decision; it is a label, and the grid is a wall of them. Gold
/// is left here to `highlighted`, which is the one tile the phase says is live
/// (the trade deadline in its week, the draft in its room), and to whatever
/// VALUE a tile chooses to emphasise inside its own body — a number that changes
/// is worth a colour in a way a fixed caption never is.
private struct DashboardTile<Content: View>: View {

    let icon: String
    let title: String
    var highlighted: Bool = false
    /// The tile's headline figure, drawn ON the title row instead of taking a
    /// row of its own under the divider.
    ///
    /// A tile is roughly 120 pt tall and its caption already eats the first
    /// band of it, so a tile whose first body row was `label + number` spent
    /// two of its three or four rows saying one thing — "ROSTER" over
    /// "Players 53". Where the tile HAS one headline number (a headcount, a
    /// list of holes, an unread count), it belongs beside the name that
    /// already labels it, and the rows under the divider are then free to
    /// carry facts the header cannot.
    ///
    /// Optional on purpose: tiles whose body is a list (Key Players, Position
    /// Grades) have no single headline and keep the plain header.
    var headline: String? = nil
    var headlineTint: Color = .textPrimary
    @ViewBuilder let content: () -> Content

    private var headerInk: Color { highlighted ? .accentGold : .textSecondary }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            // Header
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                    .foregroundStyle(headerInk)
                Text(title)
                    .font(.system(size: DSType.Size.caption, weight: .bold))
                    .foregroundStyle(headerInk)
                    .textCase(.uppercase)
                    .tracking(0.5)
                Spacer(minLength: DSSpacing.xxs)
                if let headline {
                    Text(headline)
                        .font(.system(size: DSType.Size.body, weight: .bold).monospacedDigit())
                        .foregroundStyle(headlineTint)
                        .lineLimit(1)
                        // The header is a fixed-height band shared with the
                        // caption and the chevron: a long headline ("WR, EDGE,
                        // CB") shrinks rather than pushing the chevron off the
                        // tile or wrapping the row.
                        .minimumScaleFactor(0.7)
                }
                if highlighted {
                    Text("ACTIVE")
                        .font(.system(size: DSType.Size.micro, weight: .heavy))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 5)  // ds-lint:allow(spacing) the ACTIVE pill must not grow the tile header
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentGold))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: DSType.Size.micro, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // Content
            content()
        }
        .padding(DSSpacing.sm)
        // maxHeight stretches every tile to its grid row's height, so a short
        // tile (Roster) no longer floats vertically centered beside a tall one
        // (Team) — paired cards share a top edge *and* a bottom edge.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(
                            highlighted ? Color.accentGold.opacity(0.6) : Color.surfaceBorder,
                            lineWidth: highlighted ? 1.5 : 1
                        )
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: DSCornerRadius.card))
    }

}

// MARK: - Coaching Staff Review Sheet

/// A review sheet shown when the user advances from the Coaching Changes phase.
/// Summarizes all hired coaches, vacant positions, schemes, and validation warnings.
private struct CoachingStaffReviewSheet: View {

    let career: Career
    let coaches: [Coach]
    let players: [Player]
    /// #133/#158: the club's one staff reading, handed down. This sheet used to
    /// carry its own `requiredRoles` / `filledRoles` / `vacantRoles` copies —
    /// the fourth set — and they are exactly the seats the advance gate blocks
    /// on, so the two had to be the same list or the sheet would warn about a
    /// hole the gate ignored.
    let ledger: StaffLedger
    let onConfirm: () -> Void
    let onCancel: () -> Void
    /// Leave the review and open the hiring list for a named chair. The sheet
    /// cannot hire — that flow is a modal of its own on the Staff screen, and a
    /// second modal on this presentation is the silent-dismiss bug this file
    /// keeps a one-sheet enum to avoid.
    let onHireSeat: (CoachRole) -> Void
    /// Raised once the pushed coach card has been and gone, because that card
    /// fires, extends, promotes and demotes. Everything on this sheet reads the
    /// ONE `StaffLedger` handed down (#133), so the owner of that reading is
    /// asked to take it again rather than the sheet patching its own copy.
    let onStaffChanged: () -> Void

    @Environment(\.modelContext) private var modelContext

    /// The coach the user tapped, pushed onto this sheet's own stack — the same
    /// `navigationDestination(item:)` idiom `CoachingStaffView` uses for the
    /// identical push, rather than a second sheet over the first.
    @State private var detailCoachID: UUID?

    /// The league read behind every benchmark marker on the list. Nil until the
    /// single fetch in `loadLeagueBenchmark()` lands, and the rows simply omit
    /// their markers while it is — an absent comparison beats a zero one.
    @State private var benchmark: LeagueBenchmark?

    // MARK: - Derived

    private var isGMAndHC: Bool {
        career.role == .gmAndHeadCoach
    }

    private var allRoles: [CoachRole] { ledger.coachRoles }

    private var filledRoles: Set<CoachRole> { ledger.filledCoachRoles }

    private var missingRequiredRoles: [CoachRole] { ledger.missingRequiredRoles }

    private var vacantRoles: [CoachRole] { ledger.vacantCoachRoles }

    /// One occupant per seat, resolved the SAME way ``StaffLedger`` resolves it:
    /// where a save carries duplicate rows for one chair, the dearer man wins.
    ///
    /// `coaches.first(where:)` was good enough while the row printed a rating
    /// and the ledger printed the money separately. It is not good enough now
    /// that the row carries the salary charged to the pot in the card below —
    /// picking a different duplicate here would put two payrolls on one sheet,
    /// which is the #133 defect this whole ledger exists to have ended.
    private var coachBySeat: [CoachRole: Coach] {
        var seated: [CoachRole: Coach] = [:]
        for coach in coaches where ledger.coachRoles.contains(coach.role) {
            if let sitting = seated[coach.role], sitting.salary >= coach.salary { continue }
            seated[coach.role] = coach
        }
        return seated
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
        !missingRequiredRoles.isEmpty || !areSchemesSet || !schemeMismatchWarnings.isEmpty
    }

    /// Every coordinator who specialises in one system while the club installs
    /// another, in the words `schemeMismatchWarning(for:)` already wrote. That
    /// function had no call site, so a coordinator hired for a system nobody
    /// runs was a reading this sheet computed and threw away.
    private var schemeMismatchWarnings: [String] {
        coaches.compactMap { schemeMismatchWarning(for: $0) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // No header block: it printed "COACHING STAFF REVIEW" 90 pt
                    // below the navigation bar that already says exactly that,
                    // with "COACHING STAFF" a third heading under it. The bar
                    // names the sheet; the space goes to the list.
                    //
                    // The verdict, in one sentence, before any of the sixteen
                    // rows are read.
                    readinessVerdict

                    // Staff listing
                    staffSection

                    // What the owner actually gave this club for its staff, and
                    // what is still sitting in the account. The review used to
                    // end the money conversation at a salary-free list: sixteen
                    // ratings and no idea whether the club was skint or sitting
                    // on an unspent coordinator.
                    budgetSection

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
            // One fetch per presentation, never per row — see
            // `loadLeagueBenchmark()`.
            .task { loadLeagueBenchmark() }
            // The coach card, pushed on this sheet's stack. `CoachingStaffView`
            // pushes the identical destination from the identical binding; the
            // review was the only staff surface where a man's name was not a
            // link to him.
            .navigationDestination(item: $detailCoachID) { coachID in
                if let coach = coaches.first(where: { $0.id == coachID }) {
                    CoachDetailView(coach: coach)
                }
            }
            .onChange(of: detailCoachID) { _, pushed in
                // Popped back. That card can fire, extend, promote and demote,
                // so the seat list, the three pots and the advance gate are all
                // re-read from the owner of the reading instead of being
                // trusted from before the push.
                guard pushed == nil else { return }
                onStaffChanged()
                // The club's own mean and its table position both move when a
                // man is fired or promoted, so the league read is dropped and
                // taken again rather than left describing a staff that no
                // longer exists. Only on the way back from a coach card —
                // never on the ordinary appear, where `.task` has it already.
                benchmark = nil
                loadLeagueBenchmark()
            }
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
                    .font(.system(size: DSType.Size.callout, weight: .bold))
                    .foregroundStyle(missingRequiredRoles.isEmpty ? Color.accentGold : Color.warning)
                }
            }
        }
    }

    // MARK: - Readiness Verdict

    /// The whole sheet in one sentence: what this staff is built to run, and
    /// the chair most likely to cost the club.
    ///
    /// The review opened straight into sixteen rows. Everything needed to
    /// answer "is this staff any good, and where is the hole" was on the sheet
    /// — the seats, the two installed systems, the league benchmark — and the
    /// user had to assemble it himself from a scrolling list.
    private var readinessVerdict: some View {
        let unready = !missingRequiredRoles.isEmpty
        let tint: Color = unready ? .warning : .accentGold

        return HStack(alignment: .top, spacing: DSSpacing.xs) {
            Image(systemName: unready ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                .font(.system(size: DSType.Size.footnote, weight: .semibold))
                .foregroundStyle(tint)
            Text(verdictSentence)
                .font(.system(size: DSType.Size.footnote, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.sm)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 10))  // ds-lint:allow(radius) matches its sibling cards
        .overlay(
            RoundedRectangle(cornerRadius: 10)  // ds-lint:allow(radius) matches its sibling cards
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
    }

    /// The systems this staff installs, plus the weakest chair in it.
    private var verdictSentence: String {
        let off = oc?.offensiveScheme?.displayName
        let def = dc?.defensiveScheme?.displayName
        let systems: String
        switch (off, def) {
        case let (o?, d?):
            systems = "This staff is built to run \(o) and \(d)."
        case let (o?, nil):
            systems = "This staff is built to run \(o); nothing is installed on defence yet."
        case let (nil, d?):
            systems = "This staff is built to run \(d); nothing is installed on offence yet."
        default:
            systems = "No system is installed on either side of the ball yet."
        }

        // A chair nobody is sitting in beats any rating for "weakest".
        if let missing = missingRequiredRoles.sorted(by: { $0.sortOrder < $1.sortOrder }).first {
            return systems + " Its weakest link is an empty chair: no \(missing.displayName)."
        }
        guard let weak = weakestSeat else { return systems }
        let name = weak.coach.fullName
        let overall = coachOverall(weak.coach)
        if let delta = weak.delta, delta < 0 {
            return systems + " Weakest chair: \(weak.role.displayName) — \(name), \(overall), "
                + "\(-delta) under what the league gets out of that seat."
        }
        if weak.delta != nil {
            return systems + " No chair is below the league average for its seat; "
                + "the closest is \(weak.role.displayName), \(name) at \(overall)."
        }
        return systems + " Weakest chair: \(weak.role.displayName) — \(name), \(overall)."
    }

    /// The seat this staff is likeliest to lose games in.
    ///
    /// Measured against the seat's OWN league average wherever the benchmark
    /// has landed, never against the raw minimum: `coachOverall` is the mean of
    /// nine attributes and `LeagueGenerator` builds a position coach out of one
    /// to five strong ones, so the lowest number on the sheet is a position
    /// coach every single time — which is a fact about the generator, not a
    /// verdict on this club.
    private var weakestSeat: (role: CoachRole, coach: Coach, delta: Int?)? {
        let seated = coachBySeat
        guard !seated.isEmpty else { return nil }
        if let benchmark {
            let measured = seated.compactMap { entry -> (CoachRole, Coach, Int)? in
                guard let mean = benchmark.meanBySeat[entry.key] else { return nil }
                return (entry.key, entry.value, coachOverall(entry.value) - mean)
            }
            if let worst = measured.min(by: { $0.2 < $1.2 }) {
                return (role: worst.0, coach: worst.1, delta: worst.2)
            }
        }
        guard let worst = seated.min(by: { coachOverall($0.value) < coachOverall($1.value) }) else {
            return nil
        }
        return (role: worst.key, coach: worst.value, delta: nil)
    }

    // MARK: - Staff Section

    private var staffSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                // #133: labelled for the population it counts. Bare "STAFF"
                // here read as a contradiction of the dashboard tile's
                // "23 / 23 Staff" — that one includes the scouting department,
                // this list is the coaching seats it enumerates below.
                Text("COACHING STAFF")
                    .font(.system(size: DSType.Size.caption, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                    .tracking(0.5)
                Spacer()
                // "hired", not "filled": as GM+HC the head-coach chair is yours
                // and `StaffSlots.coachRoles(for:)` leaves it out of the
                // denominator, so "15/15 filled" was printed over sixteen
                // green-ticked rows. The seats you hire are the ones counted.
                Text("\(ledger.filledCoachSlots)/\(ledger.totalCoachSlots) hired")
                    .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.bottom, DSSpacing.xs)

            // Where this staff places in the league, before a single row is
            // read. Sixteen numbers with no denominator was the whole of the
            // complaint: a 58 painted red is only a verdict if you already know
            // what the club across the road pays for the same chair.
            staffQualityStrip

            benchmarkLegend

            // Player as HC (if GM+HC role) — ruled off from the counted seats
            // below it, because it is not one of them.
            if isGMAndHC {
                playerHeadCoachRow
                Divider()
                    .overlay(Color.surfaceBorder.opacity(0.6))
                    .padding(.vertical, 4)
            }

            // All roles in sort order. Resolved once, outside the loop, and
            // resolved the way the LEDGER resolves it — see `coachBySeat`.
            let seated = coachBySeat
            ForEach(allRoles.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.self) { role in
                if let coach = seated[role] {
                    hiredStaffRow(role: role, coach: coach)
                } else {
                    vacantStaffRow(role: role)
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

    /// The shared chrome of a staff line — status glyph, seat code, portrait,
    /// two-line identity block — with the trailing edge left to the caller.
    ///
    /// One shell rather than one row per state, because the three states differ
    /// only in what hangs off the right-hand side and what a tap does. The
    /// 44 pt floor lives here for the same reason: every one of these lines is
    /// now a touch target, and §2.12 has no exceptions for rows.
    private func staffRowShell<Portrait: View, Trailing: View>(
        statusIcon: String,
        statusColor: Color,
        seat: String,
        title: String,
        titleColor: Color,
        subtitle: String,
        highlighted: Bool,
        @ViewBuilder portrait: () -> Portrait,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: statusIcon)
                .font(.system(size: DSType.Size.body))
                .foregroundStyle(statusColor)
                .frame(width: 18)

            Text(seat)
                .font(.system(size: DSType.Size.micro, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .frame(width: 30, alignment: .leading)

            portrait()

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(titleColor)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The flexible column is the one that has to give way, or a long
            // coach name pushes the benchmark marker off the trailing edge.
            .clipped()

            trailing()
        }
        .frame(minHeight: 44)
        .padding(.horizontal, DSSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                .fill(highlighted ? Color.warning.opacity(0.06) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    /// One hired coach. The whole line is the link to his card.
    private func hiredStaffRow(role: CoachRole, coach: Coach) -> some View {
        let overall = coachOverall(coach)
        let seatMean = benchmark?.meanBySeat[role]
        let schemeName: String? = {
            if role == .offensiveCoordinator {
                return coach.offensiveScheme?.displayName
            } else if role == .defensiveCoordinator {
                return coach.defensiveScheme?.displayName
            }
            return nil
        }()

        return Button {
            detailCoachID = coach.id
        } label: {
            staffRowShell(
                statusIcon: "checkmark.circle.fill",
                statusColor: Color.success,
                seat: role.abbreviation,
                title: coach.fullName,
                titleColor: Color.textPrimary,
                subtitle: contractLine(for: coach),
                highlighted: false,
                portrait: { PersonFaceView(coach: coach, size: .small) },
                trailing: {
                    HStack(spacing: DSSpacing.xs) {
                        // The same slot on every row. Only the two coordinators
                        // own a scheme, so on the other fourteen lines the chip
                        // was simply absent — and `schemeFitIndicator`, which
                        // reads a man's expertise in the system his side of the
                        // ball actually runs and covers all eleven offensive
                        // and defensive seats, had no call site at all. The
                        // coordinator's chip names the system; everybody else's
                        // dot says how well he knows the one he has been handed.
                        if let schemeName {
                            schemeChip(schemeName)
                        } else {
                            schemeFitIndicator(for: coach)
                        }
                        if let seatMean {
                            benchmarkBar(overall: overall, seatMean: seatMean)
                            deltaLabel(overall - seatMean)
                        }
                        Text("\(overall)")
                            .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                            .foregroundStyle(coachRatingColor(overall))
                            .frame(width: 28, alignment: .trailing)
                        Image(systemName: "chevron.right")
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    /// An open seat. Tapping it leaves the review and opens the hiring list for
    /// that chair — the review is where the hole is named, so it is the right
    /// place to be handed the shovel.
    private func vacantStaffRow(role: CoachRole) -> some View {
        let isRequired = ledger.requiredCoachRoles.contains(role)
        // The going rate is `CoachRole.salaryRange.avg` — the same engine figure
        // the hiring market prices candidates against. Read, never rewritten:
        // it is what makes "$18.2M unspent" mean something on a line that says
        // the chair is empty.
        let goingRate = role.salaryRange.avg

        return Button {
            onHireSeat(role)
        } label: {
            staffRowShell(
                statusIcon: isRequired ? "exclamationmark.triangle.fill" : "circle",
                statusColor: isRequired ? Color.warning : Color.textTertiary,
                seat: role.abbreviation,
                title: "Vacant — \(role.displayName)",
                titleColor: isRequired ? Color.warning : Color.textSecondary,
                subtitle: "League pays about \(StaffLedger.money(goingRate)) for this chair",
                highlighted: isRequired,
                portrait: {
                    Circle()
                        .strokeBorder(
                            Color.surfaceBorder,
                            style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                        )
                        .frame(width: 30, height: 30)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.system(size: DSType.Size.caption, weight: .bold))
                                .foregroundStyle(isRequired ? Color.warning : Color.textTertiary)
                        )
                },
                trailing: {
                    HStack(spacing: DSSpacing.xs) {
                        Text("HIRE")
                            .font(.system(size: DSType.Size.micro, weight: .heavy))
                            .foregroundStyle(Color.accentGold)
                            .tracking(0.4)
                            .padding(.horizontal, DSSpacing.xs)
                            .padding(.vertical, DSSpacing.xxs)
                            .background(Capsule().fill(Color.accentGold.opacity(0.14)))
                        Image(systemName: "chevron.right")
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    /// The GM+HC's own chair. Not a hire, not a seat in any denominator, and
    /// deliberately not a link — there is no coach row in the store for the man
    /// holding the iPad.
    private var playerHeadCoachRow: some View {
        staffRowShell(
            statusIcon: "checkmark.circle.fill",
            statusColor: Color.success,
            seat: CoachRole.headCoach.abbreviation,
            title: "You (The Tactician)",
            titleColor: Color.textPrimary,
            subtitle: "Your own chair — off the budget and out of the count",
            highlighted: false,
            portrait: { UserPortraitView(career: career, size: .small) },
            trailing: { EmptyView() }
        )
    }

    /// The money line under a hired coach's name — the answer to the question
    /// the rating beside it provokes. It is the same salary `StaffLedger`
    /// charges to the pot in the card below, so the list and the budget cannot
    /// describe two different payrolls.
    private func contractLine(for coach: Coach) -> String {
        let years = coach.contractYearsRemaining
        let term = years <= 0 ? "expiring" : "\(years) yr\(years == 1 ? "" : "s") left"
        return "\(StaffLedger.money(coach.salary)) · \(term) · age \(coach.age)"
    }

    private func schemeChip(_ name: String) -> some View {
        Text(name)
            .font(.system(size: DSType.Size.micro, weight: .semibold))
            .foregroundStyle(Color.accentGold)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentGold.opacity(0.12)))
    }

    // MARK: - League Benchmark

    /// What the rest of the league gets out of the same sixteen chairs.
    ///
    /// Built ONCE per presentation, from one `Coach` fetch. The sheet lists
    /// sixteen seats and "the average OC" is a whole-league question, so a
    /// per-row derivation would be sixteen passes over ~500 rows on a modal
    /// that opens over an already-loading dashboard.
    private struct LeagueBenchmark {
        /// Mean coach overall at each seat, over every employed coach alive in
        /// the league.
        let meanBySeat: [CoachRole: Int]
        /// Mean coach overall across this club's own staff.
        let clubMean: Int
        /// Mean coach overall across every employed coach in the league — the
        /// number `clubMean` is worth reading against.
        let leagueMean: Int
        /// Where `clubMean` places among the league's clubs. 1 is best; 0 means
        /// this club could not be ranked (see the minimum-staff rule below).
        let clubRank: Int
        /// How many clubs were ranked.
        let clubCount: Int
    }

    /// One fetch, one pass, on appear.
    ///
    /// Scoped to the open save by `careerID` alone — deliberately NOT by
    /// `teamID`, because the benchmark wants every club's staff and not just
    /// this one's. Retired men and the out-of-work bench are excluded: an
    /// unemployed 44-year-old is nobody's defensive coordinator, and
    /// `CoachMarketEngine` leaves enough of them on the books to drag every
    /// seat mean down.
    ///
    /// The overall it averages is this sheet's own nine-attribute
    /// `coachOverall`, on both sides of the comparison. `CoachDetailView`
    /// prints a twelve-attribute mean for the same man; that is a different
    /// reading of him and mixing the two would produce a delta that is really
    /// just the two formulas disagreeing.
    private func loadLeagueBenchmark() {
        guard benchmark == nil else { return }

        let cid = career.id
        let descriptor = FetchDescriptor<Coach>(
            predicate: #Predicate<Coach> { $0.careerID == cid }
        )
        let league = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.teamID != nil && !$0.isRetired }
        guard !league.isEmpty else { return }

        var sumBySeat: [CoachRole: Int] = [:]
        var countBySeat: [CoachRole: Int] = [:]
        var sumByClub: [UUID: Int] = [:]
        var countByClub: [UUID: Int] = [:]
        var leagueSum = 0

        for coach in league {
            let overall = coachOverall(coach)
            leagueSum += overall
            sumBySeat[coach.role, default: 0] += overall
            countBySeat[coach.role, default: 0] += 1
            guard let clubID = coach.teamID else { continue }
            sumByClub[clubID, default: 0] += overall
            countByClub[clubID, default: 0] += 1
        }

        var meanBySeat: [CoachRole: Int] = [:]
        for (role, count) in countBySeat where count > 0 {
            meanBySeat[role] = (sumBySeat[role] ?? 0) / count
        }

        // A club is ranked only once it has a staff worth averaging. THIS phase
        // is exactly when that matters: the carousel has just emptied chairs
        // all over the league, and a club with three men on the books would
        // otherwise post the mean of its three best and finish above a fully
        // staffed rival. Half a staff is the floor.
        let minimumStaffToRank = 8
        let clubMeans: [(id: UUID, mean: Int)] = countByClub
            .filter { $0.value >= minimumStaffToRank }
            .map { (id: $0.key, mean: (sumByClub[$0.key] ?? 0) / $0.value) }
            .sorted { $0.mean > $1.mean }

        var clubMean = 0
        var clubRank = 0
        if let clubID = career.teamID {
            let count = countByClub[clubID] ?? 0
            if count > 0 { clubMean = (sumByClub[clubID] ?? 0) / count }
            if let index = clubMeans.firstIndex(where: { $0.id == clubID }) {
                clubRank = index + 1
            }
        }

        benchmark = LeagueBenchmark(
            meanBySeat: meanBySeat,
            clubMean: clubMean,
            leagueMean: leagueSum / league.count,
            clubRank: clubRank,
            clubCount: clubMeans.count
        )
    }

    /// The club's league position for staff quality, in one line above the list.
    @ViewBuilder
    private var staffQualityStrip: some View {
        if let benchmark, benchmark.clubRank > 0, benchmark.clubCount > 1 {
            let tint = rankColor(rank: benchmark.clubRank, of: benchmark.clubCount)
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(tint)
                Text("#\(benchmark.clubRank)")
                    .font(.system(size: DSType.Size.callout, weight: .heavy).monospacedDigit())
                    .foregroundStyle(tint)
                // "staffed clubs", not "clubs": the carousel empties chairs all
                // over the league on the way INTO this phase and the AI refill
                // does not run until the way out, so a plain "of 32" would be a
                // denominator that does not exist yet. The rank is taken over
                // the clubs that currently have a staff worth averaging.
                Text("of \(benchmark.clubCount) staffed clubs for coaching quality")
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("avg \(benchmark.clubMean) · league \(benchmark.leagueMean)")
                    .font(.system(size: DSType.Size.caption).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, DSSpacing.xs)
            .padding(.vertical, DSSpacing.xxs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.backgroundTertiary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
            .padding(.bottom, DSSpacing.xs)
        }
    }

    /// What the tick on every row means, said once instead of sixteen times.
    @ViewBuilder
    private var benchmarkLegend: some View {
        if benchmark != nil {
            HStack(spacing: DSSpacing.xxs) {
                Rectangle()
                    .fill(Color.textSecondary)
                    .frame(width: 1.5, height: 9)
                Text("marks the league average for that seat. Tap a line to open the coach — or the hiring list.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DSSpacing.xxs)
            .padding(.bottom, DSSpacing.xs)
        }
    }

    /// How far from the seat's league average a rating is allowed to read
    /// before the marker pins, and how wide the marker is.
    ///
    /// ±15 rather than a 0–100 rail, and the choice is forced by the data.
    /// `coachOverall` is the mean of nine attributes and `LeagueGenerator`
    /// gives a position coach one to five of them in the 70–85 band with the
    /// rest at 40–60, so virtually every coach in the league lands between 45
    /// and 68. Sixteen full-scale rails would have filled to within a finger's
    /// width of one another and hidden the only question the column is asked:
    /// is this man better or worse than the one the club across the road has in
    /// the same chair.
    private static let benchmarkSpan = 15
    private static let benchmarkWidth: CGFloat = 58

    /// A centre tick at the seat's league average, and a bar off it in the
    /// direction this man differs.
    private func benchmarkBar(overall: Int, seatMean: Int) -> some View {
        let delta = overall - seatMean
        let clamped = max(-Self.benchmarkSpan, min(Self.benchmarkSpan, delta))
        let half = Self.benchmarkWidth / 2
        let length = half * CGFloat(abs(clamped)) / CGFloat(Self.benchmarkSpan)
        // A man exactly on the average gets no bar at all — the tick alone is
        // the honest picture, and a 2 pt stub either side would have read as a
        // direction he does not have.
        let drawn = delta == 0 ? 0 : max(length, 2)

        return ZStack {
            Capsule()
                .fill(Color.surfaceBorder.opacity(0.35))
                .frame(width: Self.benchmarkWidth, height: 4)
            Capsule()
                .fill(delta >= 0 ? Color.success : Color.danger)
                .frame(width: drawn, height: 4)
                .offset(x: delta >= 0 ? drawn / 2 : -drawn / 2)
            Rectangle()
                .fill(Color.textSecondary)
                .frame(width: 1.5, height: 9)
        }
        .frame(width: Self.benchmarkWidth, height: 10)
    }

    private func deltaLabel(_ delta: Int) -> some View {
        Text(delta == 0 ? "±0" : (delta > 0 ? "+\(delta)" : "\(delta)"))
            .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
            .foregroundStyle(delta > 0 ? Color.success : (delta < 0 ? Color.danger : Color.textTertiary))
            .frame(width: 26, alignment: .trailing)
    }

    /// A table position is not a rating, so it deliberately does NOT take
    /// `Color.forRating`: that ladder puts everything under 60 in red, which
    /// would paint a mid-table club — the literal league average — as a
    /// failure. Quarters of the table instead, for the same reason
    /// `coachRatingColor` below reads its bands off the real distribution.
    private func rankColor(rank: Int, of count: Int) -> Color {
        guard count > 0 else { return .textSecondary }
        if rank <= max(1, count / 4) { return .eliteGreen }
        if rank <= count / 2 { return .success }
        if rank <= (count * 3) / 4 { return .accentGold }
        return .warning
    }

    // MARK: - Budget Section

    /// The owner's three envelopes, what is committed against each, and the
    /// sentence that says what the surplus is actually for.
    ///
    /// All THREE pots, even though the list above is coaching seats only,
    /// because this sheet owns the Advance button and
    /// `StaffLedger.advanceBlocker` refuses that advance on the sum of all
    /// three. A review that showed two pots and then declined to advance over
    /// the third would be #158 wearing a new hat.
    ///
    /// Hidden outright — never faked — when no owner has resolved: `StaffLedger`
    /// returns zeros in that state, and a per-screen invented envelope is the
    /// exact defect that type was written to end.
    @ViewBuilder
    private var budgetSection: some View {
        if ledger.isResolved {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                // 6 pt, not `DSSpacing.xxs`, because the two section headers
                // this card sits between are 6 pt: a card head that breathes
                // differently from its neighbours reads as a different KIND of
                // card.
                HStack(spacing: 6) {  // ds-lint:allow(spacing) matches the sheet's other section heads
                    Image(systemName: "dollarsign.square.fill")
                        .font(.system(size: DSType.Size.footnote, weight: .semibold))
                        .foregroundStyle(Color.accentGold)
                    Text("STAFF BUDGET")
                        .font(.system(size: DSType.Size.caption, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                        .tracking(0.5)
                    Spacer()
                    if ledger.isOverspent {
                        Text("\(StaffLedger.money(ledger.overage)) over")
                            .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.danger)
                    } else {
                        Text("\(StaffLedger.money(unspentTotal)) unspent")
                            .font(.system(size: DSType.Size.callout, weight: .bold).monospacedDigit())
                            .foregroundStyle(unspentColor)
                    }
                }

                // Icon and tint per pot are lifted from `OwnerBudgetView`, where
                // the same three envelopes are set. Two screens describing one
                // allocation should not need the labels read to be matched up.
                budgetPotRow(
                    title: "Coaching",
                    icon: "person.3.fill",
                    tint: Color.accentGold,
                    committed: ledger.committedCoaching,
                    envelope: ledger.coachingBudget
                )
                budgetPotRow(
                    title: "Medical",
                    icon: "cross.case.fill",
                    tint: Color.success,
                    committed: ledger.committedMedical,
                    envelope: ledger.medicalBudget
                )
                budgetPotRow(
                    title: "Scouting",
                    icon: "binoculars.fill",
                    tint: Color.accentBlue,
                    committed: ledger.committedScouting,
                    envelope: ledger.scoutingBudget
                )

                if let sentence = budgetSentence {
                    Divider().overlay(Color.surfaceBorder.opacity(0.5))
                    HStack(alignment: .top, spacing: DSSpacing.xxs) {
                        Image(systemName: ledger.isOverspent ? "exclamationmark.octagon.fill" : "lightbulb.fill")
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(ledger.isOverspent ? Color.danger : Color.accentGold)
                        Text(sentence)
                            .font(.system(size: DSType.Size.footnote, weight: .medium))
                            .foregroundStyle(ledger.isOverspent ? Color.dangerText : Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(DSSpacing.sm)
            .background(Color.backgroundSecondary)
            // 10, off the DSCornerRadius ladder, because the staff, schemes and
            // warnings cards stacked with it are all 10 and one card with a
            // 12 pt corner in a column of 10s is a visible defect, not a fix.
            .clipShape(RoundedRectangle(cornerRadius: 10))  // ds-lint:allow(radius) matches its sibling cards
            .overlay(
                RoundedRectangle(cornerRadius: 10)  // ds-lint:allow(radius) matches its sibling cards
                    .strokeBorder(
                        ledger.isOverspent ? Color.danger.opacity(0.4) : Color.surfaceBorder,
                        lineWidth: 1
                    )
            )
        }
    }

    private func budgetPotRow(
        title: String,
        icon: String,
        tint: Color,
        committed: Int,
        envelope: Int
    ) -> some View {
        let remaining = envelope - committed
        let isOver = remaining < 0
        let fraction = envelope > 0 ? min(1.0, Double(committed) / Double(envelope)) : 0

        return VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(tint)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 62, alignment: .leading)
                Text("\(StaffLedger.money(committed)) of \(StaffLedger.money(envelope))")
                    .font(.system(size: DSType.Size.caption).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                Spacer(minLength: 4)
                // "left" / "over", never a bare figure: the tile beside this one
                // shipped "$26.5M / $47.0M" and it read as money SPENT when it
                // was money REMAINING. Say which way the number points.
                Text(isOver
                     ? "\(StaffLedger.money(-remaining)) over"
                     : "\(StaffLedger.money(remaining)) left")
                    .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                    .foregroundStyle(isOver ? Color.danger : tint)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.surfaceBorder.opacity(0.35))
                    Capsule()
                        .fill(isOver ? Color.danger : tint)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 5)
        }
    }

    /// Money still sitting in the three envelopes.
    ///
    /// Negative pots are floored at zero rather than netted off: an overspent
    /// medical pot is not spending power for the coaching one, and subtracting
    /// it would print a comfortable surplus for a club whose advance the gate
    /// is about to refuse.
    private var unspentTotal: Int {
        max(0, ledger.remainingCoaching)
            + max(0, ledger.remainingMedical)
            + max(0, ledger.remainingScouting)
    }

    /// Green means "you can still spend this". The moment every chair is
    /// filled it buys nothing, and a green figure over a fully-hired staff read
    /// the club's biggest unmade upgrade as an unambiguous win — the same
    /// finding the dashboard staff tile records against its own budget line.
    private var unspentColor: Color {
        guard !ledger.vacantCoachRoles.isEmpty else { return .textTertiary }
        if unspentTotal > 10_000 { return .success }
        if unspentTotal > 5_000 { return .accentGold }
        return .warning
    }

    /// The one line that turns a surplus into a decision.
    ///
    /// Ordered by what the Advance button will actually do: an overspend is
    /// what the gate refuses on, so it is said first and nothing else is said
    /// at all. The coaching pot is quoted rather than `unspentTotal` once a
    /// chair is named, because a coaching chair is charged to the coaching pot
    /// (`StaffLedger.medicalRoles` decides which side a title falls on) and
    /// offering the scouting surplus for it would be a lie.
    private var budgetSentence: String? {
        if ledger.isOverspent {
            return "You are \(StaffLedger.money(ledger.overage)) over the staff budget. "
                + "The advance will not run until staff are released or replaced with cheaper men."
        }

        let openCoachingSeats = ledger.vacantCoachRoles
            .filter { !StaffLedger.medicalRoles.contains($0) }

        guard !openCoachingSeats.isEmpty else {
            guard unspentTotal > 0 else { return nil }
            return "\(StaffLedger.money(unspentTotal)) is unspent with every chair filled — "
                + "the only thing left to buy is a better man in one of them."
        }

        let purse = max(0, ledger.remainingCoaching)
        let seatWord = openCoachingSeats.count == 1 ? "chair" : "chairs"
        guard purse > 0 else {
            return "\(openCoachingSeats.count) coaching \(seatWord) open and nothing left in the coaching pot. "
                + "The owner's budget screen is where it gets re-cut."
        }

        // Cheapest first, so "enough for N of them" is the largest honest N.
        var spent = 0
        var covered = 0
        for role in openCoachingSeats.sorted(by: { $0.salaryRange.avg < $1.salaryRange.avg })
        where spent + role.salaryRange.avg <= purse {
            spent += role.salaryRange.avg
            covered += 1
        }

        if covered == 0 {
            return "\(StaffLedger.money(purse)) left in the coaching pot — under the going rate for any of "
                + "the \(openCoachingSeats.count) open \(seatWord)."
        }
        if covered >= openCoachingSeats.count {
            return "\(StaffLedger.money(purse)) left in the coaching pot — enough to fill all "
                + "\(openCoachingSeats.count) open \(seatWord) at the league's going rate."
        }
        return "\(StaffLedger.money(purse)) left in the coaching pot — enough for \(covered) of the "
            + "\(openCoachingSeats.count) open \(seatWord) at the league's going rate."
    }

    // MARK: - Schemes Section

    private var schemesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text("SCHEMES & EXPERTISE")
                    .font(.system(size: DSType.Size.caption, weight: .bold))
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
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.accentBlue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OFFENSE")
                        .font(.system(size: DSType.Size.micro, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(0.3)
                    Text(oc?.offensiveScheme?.displayName ?? "Not Set")
                        .font(.system(size: DSType.Size.caption, weight: .bold))
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
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.danger)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DEFENSE")
                        .font(.system(size: DSType.Size.micro, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(0.3)
                    Text(dc?.defensiveScheme?.displayName ?? "Not Set")
                        .font(.system(size: DSType.Size.caption, weight: .bold))
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

    /// Scheme expertise is 0–100, so it takes the shared ladder — the same one
    /// `fitBarColor` above and `SchemeSelectionView.schemeExpertiseColor` use.
    /// This file was printing the two numbers in the same card on two ladders.
    private func schemeFitColor(_ expertise: Int) -> Color {
        Color.forRating(expertise, scale: .percent)
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
                    .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Knows the installed scheme \(expertise) out of 100")
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
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(isOffensive ? Color.accentBlue : Color.danger)
                Text("\(isOffensive ? "OFFENSIVE" : "DEFENSIVE") SCHEME: \(scheme)")
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
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

            // What the tick on both bars means, said once per side of the ball.
            HStack(spacing: DSSpacing.xxs) {
                Rectangle()
                    .fill(Color.textSecondary)
                    .frame(width: 1.5, height: 8)
                Text("marks \(Self.goodFitMark)% — a fit reads Good from there up.")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.leading, 66)  // ds-lint:allow(spacing) lines up with each bar's own detail line

            // Best Alternative
            if let alt = alternative {
                let currentTotal = coachFit.total + rosterFit.percent
                let altTotal = alt.coachFit + alt.rosterFit
                let significantlyBetter = altTotal - currentTotal > 20 // >10% avg across both

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(significantlyBetter ? Color.warning : Color.textTertiary)
                        Text("Alternative: \(alt.name)")
                            .font(.system(size: DSType.Size.micro, weight: .bold))
                            .foregroundStyle(significantlyBetter ? Color.warning : Color.textSecondary)
                    }

                    HStack(spacing: 12) {
                        HStack(spacing: 3) {
                            Text("Coach:")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textTertiary)
                            Text("\(alt.coachFit)%")
                                .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                                .foregroundStyle(fitBarColor(alt.coachFit))
                        }
                        HStack(spacing: 3) {
                            Text("Roster:")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textTertiary)
                            Text("\(alt.rosterFit)%")
                                .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                                .foregroundStyle(fitBarColor(alt.rosterFit))
                        }
                    }
                    .padding(.leading, 13)

                    if significantlyBetter {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: DSType.Size.footnote))
                            Text("Consider switching -- \(alt.name) may be a better fit")
                                .font(.system(size: DSType.Size.footnote, weight: .medium))
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

    /// Where a fit stops being a worry and starts reading "Good".
    ///
    /// 60 is not a new number: it is the floor of
    /// `CoachingStaffView.schemeFitLabel`'s **Good** band, the vocabulary the
    /// Schemes tab already prints beside the identical percentage. The bar had
    /// a track, a fill and a colour and no mark of any kind, so a mid-yellow
    /// 54 % and a mid-yellow 66 % looked like the same reading.
    private static let goodFitMark = 60

    private func schemeFitBar(label: String, percent: Int, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 60, alignment: .leading)
                Text("\(percent)%")
                    .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                    .foregroundStyle(color)
                // Progress bar, with the Good line marked on the track — the
                // same device `benchmarkBar` uses on every staff row above.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.surfaceBorder.opacity(0.4))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(min(percent, 100)) / 100.0)
                        Rectangle()
                            .fill(Color.textSecondary)
                            .frame(width: 1.5, height: 10)
                            .offset(x: geo.size.width * CGFloat(Self.goodFitMark) / 100.0 - 0.75)
                    }
                }
                .frame(height: 6)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label) \(percent) percent, \(Self.goodFitMark) percent is a good fit")
            Text(detail)
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiary)
                .padding(.leading, 66)
        }
    }

    /// Coach / roster scheme fit is a 0–100 percentage, so it takes the shared
    /// ladder rather than a fourth private one. `CoachingStaffView.schemeFitColor`
    /// and `SchemeSelectionView` describe the same number and now agree with it.
    private func fitBarColor(_ percent: Int) -> Color {
        Color.forRating(percent, scale: .percent)
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
        let chemistry = calculateStaffChemistry()
        let score = chemistry.score
        let grade: String = score >= 75 ? "Great" : (score >= 50 ? "Good" : (score >= 25 ? "Fair" : "Poor"))
        let gradeColor: Color = score >= 75 ? .success : (score >= 50 ? .accentGold : (score >= 25 ? .warning : .danger))

        return VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(gradeColor)
                    .frame(width: 18)
                Text("Staff chemistry: **\(grade)**")
                    .font(.system(size: DSType.Size.caption, weight: .medium))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(grade)
                    .font(.system(size: DSType.Size.micro, weight: .bold))
                    .foregroundStyle(gradeColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(gradeColor.opacity(0.12), in: Capsule())
            }

            // The grade was the whole row: a word, then the same word again in
            // a capsule, over a score built pair by pair from men who are all
            // named on the list above. The pairs that cost the points are the
            // answer to "so what do I do about it", and they were computed and
            // thrown away.
            if let advice = chemistryAdvice(chemistry) {
                Text(advice)
                    .font(.system(size: DSType.Size.micro))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 24)  // hangs under the row's own label: 18 pt glyph + 6 pt gap
            }
        }
    }

    /// A chemistry reading and the pairs that made it.
    private struct StaffChemistryReading {
        let score: Int
        /// Every pair the table charges −10 for, in staff order.
        let clashes: [(Coach, Coach)]
    }

    /// Personality pairs that add to the room. Hoisted off
    /// `calculateStaffChemistry` so the advice line can be scored on the SAME
    /// table the grade is scored on — an advice line derived from a second,
    /// hand-written table is how a screen ends up recommending a hire that
    /// lowers the number it is printed under.
    private static let compatiblePairs: Set<Set<PersonalityArchetype>> = [
        [.teamLeader, .mentor],
        [.teamLeader, .steadyPerformer],
        [.mentor, .quietProfessional],
        [.quietProfessional, .steadyPerformer],
        [.fieryCompetitor, .teamLeader],
    ]

    /// Personality pairs that cost the room points.
    private static let clashingPairs: Set<Set<PersonalityArchetype>> = [
        [.fieryCompetitor, .dramaQueen],
        [.loneWolf, .teamLeader],
        [.dramaQueen, .quietProfessional],
        [.classClown, .fieryCompetitor],
    ]

    /// Simple personality-based chemistry score (0-100), and the clashing pairs
    /// that produced it. The arithmetic is unchanged — only the culprits, which
    /// the loop already knew, now survive the return.
    private func calculateStaffChemistry() -> StaffChemistryReading {
        guard coaches.count >= 2 else { return StaffChemistryReading(score: 50, clashes: []) }

        var score = 50
        var clashes: [(Coach, Coach)] = []
        for i in 0..<coaches.count {
            for j in (i + 1)..<coaches.count {
                let pair: Set<PersonalityArchetype> = [coaches[i].personality, coaches[j].personality]
                if Self.compatiblePairs.contains(pair) { score += 8 }
                if Self.clashingPairs.contains(pair) {
                    score -= 10
                    clashes.append((coaches[i], coaches[j]))
                }
                if coaches[i].personality == coaches[j].personality { score += 3 }
            }
        }
        return StaffChemistryReading(score: min(max(score, 0), 100), clashes: clashes)
    }

    /// What would move the grade, in one line: who is pulling against whom, or
    /// — when nobody is — the personality that would add most in an open chair.
    private func chemistryAdvice(_ chemistry: StaffChemistryReading) -> String? {
        if let clash = chemistry.clashes.first {
            let (first, second) = clash
            let extra = chemistry.clashes.count - 1
            let more = extra > 0 ? " (and \(extra) other pair\(extra == 1 ? "" : "s"))" : ""
            return "\(first.role.abbreviation) \(first.lastName) (\(first.personality.displayName)) and "
                + "\(second.role.abbreviation) \(second.lastName) (\(second.personality.displayName)) "
                + "pull against each other\(more) — replacing either one lifts the room."
        }
        guard let addition = bestAdditionArchetype() else { return nil }
        return "Nobody in the room clashes. A \(addition.displayName) in one of the open chairs "
            + "is what lifts it further."
    }

    /// The personality that would add most to THIS room if the next hire had
    /// it, scored on the same two tables the grade uses. Nil once every chair
    /// is filled — there is nowhere left to put him.
    private func bestAdditionArchetype() -> PersonalityArchetype? {
        guard !coaches.isEmpty, !vacantRoles.isEmpty else { return nil }
        var best: (archetype: PersonalityArchetype, gain: Int)?
        for archetype in PersonalityArchetype.allCases {
            var gain = 0
            for coach in coaches {
                let pair: Set<PersonalityArchetype> = [archetype, coach.personality]
                if Self.compatiblePairs.contains(pair) { gain += 8 }
                if Self.clashingPairs.contains(pair) { gain -= 10 }
                if coach.personality == archetype { gain += 3 }
            }
            if gain > (best?.gain ?? 0) { best = (archetype, gain) }
        }
        return best?.archetype
    }

    // MARK: - Warnings Section

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vacantRoles.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.warning)
                    Text("\(vacantRoles.count) position\(vacantRoles.count == 1 ? "" : "s") still vacant")
                        .font(.system(size: DSType.Size.body, weight: .semibold))
                        .foregroundStyle(Color.warning)
                }
            }

            if !missingRequiredRoles.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.octagon.fill")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.danger)
                    Text("Missing: \(missingRequiredRoles.map { $0.displayName }.joined(separator: ", "))")
                        .font(.system(size: DSType.Size.footnote, weight: .medium))
                        .foregroundStyle(Color.dangerText)
                }

                Text("Without coordinators: -20% offense/defense efficiency, slower player development")
                    .font(.system(size: DSType.Size.footnote, weight: .medium))
                    .foregroundStyle(Color.dangerText)
                    .padding(.leading, 18)
            }

            if !areSchemesSet {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.warning)
                    Text("Schemes not fully configured. Go to Staff > Schemes to set them.")
                        .font(.system(size: DSType.Size.footnote, weight: .medium))
                        .foregroundStyle(Color.warning)
                }
            }

            ForEach(schemeMismatchWarnings, id: \.self) { warning in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.warning)
                    Text(warning)
                        .font(.system(size: DSType.Size.footnote, weight: .medium))
                        .foregroundStyle(Color.warning)
                        .fixedSize(horizontal: false, vertical: true)
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
                        .font(.system(size: DSType.Size.callout, weight: .semibold))
                    Text(missingRequiredRoles.isEmpty && areSchemesSet
                         ? "Confirm & Advance to Review Roster"
                         : "Lock in Anyway & Advance")
                        .font(.system(size: DSType.Size.callout, weight: .bold))
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

            // The padlock and "Lock in" say the market shuts behind you. It
            // does not: hiring is not phase-gated anywhere — `CoachingStaffView`
            // gates only its two review TASKS on `.coachingChanges`, and its own
            // confirm copy already tells the user "You can still hire and
            // replace anybody". This sheet was the one place that implied the
            // opposite, over the button that carries the decision.
            Text("This only advances the phase — you can still hire, replace and re-sign staff afterwards.")
                .font(.system(size: DSType.Size.footnote))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    // MARK: - Coach Overall Helper

    /// A coach number is NOT a player OVR, and it must not be painted on the
    /// player ladder.
    ///
    /// `coachOverall` is the mean of nine attributes, and `LeagueGenerator`
    /// gives a position coach only one to five of them in the 70-85 band and
    /// the rest in 40-60 — so his mean is pinned around 50-58 by construction
    /// and `Color.forRating` (<60 = danger) rendered twelve of fifteen seats,
    /// including coordinators hired seconds earlier, as failing grades. These
    /// bands are the same five colours read against the distribution the game
    /// actually generates: a coordinator lands mid-60s, a strong one high-60s
    /// up, and red is reserved for a man who is genuinely below his peers.
    private func coachRatingColor(_ overall: Int) -> Color {
        switch overall {
        case 78...:   return .eliteGreen
        case 69..<78: return .success
        case 56..<69: return .accentBlue
        case 45..<56: return .warning
        default:      return .danger
        }
    }

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
