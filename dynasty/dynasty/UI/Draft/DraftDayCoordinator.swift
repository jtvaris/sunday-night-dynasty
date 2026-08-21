import Foundation
import SwiftUI
import SwiftData
import Combine

/// Drives the new event-driven Draft Day experience.
///
/// Vaihe 1 surface: AI auto-picks with a clock countdown, user pick interrupts
/// flow, skip-to-my-pick / skip-to-next-event / pause / speed control. Trade
/// offers, reactions, and rich event types arrive in Vaihe 3.
@MainActor
final class DraftDayCoordinator: ObservableObject {

    // MARK: - Mode

    enum Mode: Equatable {
        case loading
        case preDraft
        case playing
        case paused
        case userPick
        case complete
    }

    // MARK: - Published state

    @Published private(set) var mode: Mode = .loading
    @Published private(set) var currentPickIndex: Int = 0
    @Published private(set) var clockSeconds: Int = 120
    @Published private(set) var speed: Double = 1.0
    @Published private(set) var picks: [DraftPick] = []
    @Published private(set) var availableProspects: [CollegeProspect] = []
    @Published private(set) var teamsByID: [UUID: Team] = [:]
    @Published private(set) var rosters: [UUID: [Player]] = [:]
    /// Per-team coordinator schemes (OC offense / DC defense), resolved from the
    /// coaching staff at load. Drives the draft-grade scheme-fit input (#33 OSA B).
    private var schemesByTeam: [UUID: (offense: OffensiveScheme?, defense: DefensiveScheme?)] = [:]
    @Published private(set) var recentEvents: [PlannedDraftEvent] = []
    @Published private(set) var lastPickResult: PickResult?
    @Published private(set) var publicBoardRanks: [UUID: Int] = [:]
    /// The USER's own board — `prospectCustomBoard`, the order the Big Board
    /// persists — as `[ProspectID: 1-based slot]`.
    ///
    /// Computed once, over the whole DECLARED class rather than the live pool,
    /// so "MY #12" means the same thing at pick 1 and at pick 200 and is the
    /// same number the Big Board prints. (Ranking the shrinking pool would have
    /// every row renumber itself after every selection.)
    @Published private(set) var userBoardRanks: [UUID: Int] = [:]
    @Published private(set) var teamNeedScores: [Position: Double] = [:]
    @Published private(set) var reputation: DraftReputation?
    @Published private(set) var pendingReactions: [ReactionsEngine.Reaction] = []
    @Published private(set) var pendingDrama: [DraftDramaEngine.DramaEvent] = []
    @Published private(set) var pendingRoundRecap: RoundRecapData?
    @Published private(set) var allPickResults: [PickResult] = []
    @Published private(set) var lastRoundShown: Int = 0

    /// **Which of the user's cards the CLOCK filed, not the user** (#207).
    ///
    /// The `PickResult` carries the same fact as `isAutoPick`, but the ticker's
    /// history rows are built from `DraftPick` — the persisted row — and a
    /// `DraftPick` has no idea who handed it in. Rather than widen the SwiftData
    /// model for a fact that only lives as long as draft night, the coordinator
    /// keeps the pick numbers here and every surface asks
    /// ``isAutoPick(pickNumber:)``.
    @Published private(set) var autoPickNumbers: Set<Int> = []

    /// Was this slot filed by the expiring clock rather than by the user?
    /// Always `false` for the other 31 clubs — they have no clock to lose.
    func isAutoPick(pickNumber: Int) -> Bool { autoPickNumbers.contains(pickNumber) }

    // MARK: - Trades (R24 pick swaps, rebuilt in Wave 4)

    /// The offer on the table: an AI club buying one of the user's picks, or a
    /// move-up quote the user asked for. Real `DraftPick` rows and real
    /// `Player`s on both sides.
    @Published private(set) var pendingTradeOffer: DraftDayTradeEngine.DraftTradeOffer?
    @Published private(set) var tradeDownMessage: String?

    /// Later-year picks the user and the other 31 clubs own — the bridges that
    /// make the top of the board reachable (plan §6 Wave 1.1 minted them, Wave 4
    /// is the first code that spends them).
    @Published private(set) var futurePicks: [DraftPick] = []

    /// Trades that have happened tonight, newest first. One line per persisted
    /// `DraftEvent` of a trade kind — those rows were write-only before Wave 4
    /// (plan finding S6: "trade events are persisted and never rendered").
    @Published private(set) var tradeTicker: [TradeTickerLine] = []

    /// Queue of league-trade moments big enough to interrupt the broadcast.
    @Published private(set) var pendingTradeBeats: [TradeBeat] = []

    // MARK: - Story feed (Batch 2A)

    /// The night's narrative beats, newest first: runs on a position, slides,
    /// steals, reaches, round breaks.
    ///
    /// The draft has always *computed* these — `bigDrop` and `positionRun` have
    /// been cases in `DraftEventType` since Vaihe 1 and the gem/reach grades
    /// come out of `PickGradeCalculator` on every card — and then thrown them
    /// away: the persisted events were write-only and `recentEvents` was a
    /// published array no view ever read. Meanwhile the ticker column showed
    /// five near-identical "#16 MIA" rows and ~1200 px of nothing. This is the
    /// same data, rendered.
    @Published private(set) var storyFeed: [StoryBeat] = []

    /// One rendered narrative line.
    struct StoryBeat: Identifiable {
        enum Kind {
            case steal
            case reach
            case slide
            case run
            case round
        }
        let id = UUID()
        let kind: Kind
        let pickNumber: Int?
        let headline: String
        let detail: String
    }

    /// Position of the current same-position streak and how long it is. A run
    /// surfaces at three straight and then keeps rewriting its own line, so a
    /// four-deep run is one row that counts up, not four rows.
    private var positionStreak: (position: Position, count: Int)?

    /// The run beat currently on the feed, so a lengthening run rewrites its own
    /// line instead of pushing a new one on top of it.
    private var activeRunBeatID: UUID?

    /// The over-the-cap warning currently on the feed, same rewrite-in-place
    /// contract as `activeRunBeatID` (task #94).
    private var activeCapWarningBeatID: UUID?

    /// Year-one money the USER's own class has cost so far tonight, in
    /// thousands — the sum of the slots charged at his podium turns.
    ///
    /// Kept separately from `team.availableCap` because the two answer different
    /// questions. The room is the club's whole position (it can already have
    /// been in the red before a card was handed in); this is what the CLASS
    /// added. The warning quotes both rather than blaming the class for a hole
    /// free agency dug.
    private var userClassCapCharge = 0

    /// User pick numbers whose "your marked target is still there" beat has
    /// already fired — the watch window spans several picks and the banner is
    /// worth exactly one showing per turn.
    private var announcedTargetPickNumbers: Set<Int> = []

    /// "Call about moving up" sheet state.
    @Published private(set) var isTradeUpBoardOpen = false
    @Published private(set) var tradeUpQuotes: [DraftDayTradeEngine.DraftTradeOffer] = []
    @Published private(set) var tradeUpProspect: CollegeProspect?
    @Published private(set) var tradeUpMessage: String?
    /// Whether the user is willing to put veterans in the package.
    @Published private(set) var tradeUpIncludesVeterans = false

    /// One rendered trade line. `pickNumber` is the slot the deal was about, so
    /// the ticker can sort trades into the pick order they interrupted.
    struct TradeTickerLine: Identifiable {
        let id = UUID()
        let pickNumber: Int?
        let headline: String
        let detail: String
        let involvesUser: Bool
    }

    /// A league trade worth a broadcast beat (round 1-2, or a deal with a
    /// veteran in it). Deliberately a local type rather than a new
    /// `DraftDramaEngine.DramaEvent` case: the drama engine is shared code and
    /// a trade beat needs none of its pick-grade heuristics.
    struct TradeBeat: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let subtitle: String
    }

    // R24 — UDFA stage after the final pick
    @Published private(set) var udfaPool: [CollegeProspect] = []
    @Published private(set) var signedUDFAProspectIDs: [UUID] = []
    @Published private(set) var udfaStageFinished = false
    @Published private(set) var udfaAISummary: String?
    /// How many undrafted men the user may sign on draft night.
    ///
    /// Reads the engine (#199): this used to be a literal `5` against
    /// `UDFAMarketEngine.clubSigningQuota`'s 6, which made the market's own
    /// parity rule — the user's ceiling is the same ceiling every AI club has —
    /// one man short in the user's disfavour. The quota cannot bind this door
    /// itself, because draft-night signings go through
    /// `DraftEngine.convertUDFAToPlayer` and never appear in
    /// `UDFAMarketState.signings`; see ``UDFAMarketEngine/draftNightUserWindow``
    /// for the audit. Deriving the number instead of restating it is what stops
    /// the two drifting apart again.
    var maxUDFASignings: Int { UDFAMarketEngine.draftNightUserWindow }

    /// One trade-down search per pick — prevents re-rolling the dice.
    private var tradeDownSearchedPickNumber: Int?

    // MARK: - Pick-slot claim (task #146)

    /// Slots a card has already been handed in for tonight.
    ///
    /// The write path is idempotent per slot: whoever gets there first owns the
    /// pick and every later writer no-ops. Without it the pick clock and the
    /// user's own confirmation were two writers racing for one `DraftPick` row,
    /// and the loser's selection silently replaced the winner's — the user
    /// confirmed a name, the expiry auto-pick had already filed a different one,
    /// and the board showed the AI's man under the user's team.
    private var claimedPickNumbers: Set<Int> = []

    /// True while a modal the user is answering is on screen — the confirm-pick
    /// alert, or a round recap. The clock does not tick under it.
    ///
    /// This is the other half of the same defect. The confirm alert is raised
    /// from the live big board (#197 — it used to be the retired pick sheet)
    /// and the 120 s clock kept running behind it, so at any
    /// speed above 1× a user reading the card could be overridden mid-decision:
    /// the tap landed on `selectProspect` after the slot had already been filed
    /// by `DraftEngine.aiMakePick`, and `guard isUserOnClock` swallowed it.
    /// A decision the game asked for is not a decision the clock may take back.
    private var isPickConfirmationOpen = false

    /// Nothing may run the pick clock down while the user owes an answer.
    var isClockHeld: Bool { isPickConfirmationOpen || pendingRoundRecap != nil }

    /// `LiveBigBoardPanel` reports its confirm alert opening and closing.
    func setPickConfirmationOpen(_ open: Bool) {
        isPickConfirmationOpen = open
    }

    /// Slot the AI-vs-AI market has already been rolled for.
    private var swapRolledPickNumber: Int?

    /// User picks whose INCOMING (AI-initiated) trade-up offer was declined —
    /// no nagging re-offers on the same pick.
    private var declinedTradeUpPickNumbers: Set<Int> = []

    /// User picks he shopped himself and then walked away from.
    ///
    /// Wave 4 bug fix (plan finding S6): both sets used to be one, and since a
    /// trade-DOWN offer also lists the user's pick under `userGives`, turning
    /// down a price he had asked for permanently blocked rival GMs from calling
    /// about that same pick. Two sets, keyed off who picked up the phone.
    private var declinedTradeDownPickNumbers: Set<Int> = []

    /// Cached GM market views (persona + stance + starter-quality needs), built
    /// on demand and invalidated for the two clubs in any executed trade.
    /// Rebuilding 32 of them per dice roll would cost more than the draft.
    private var marketSeats: [UUID: TradeValueEngine.GMMarketView] = [:]
    private var leagueCoreReference: Double = 80.0
    /// Every pro player in the league at load, for market views and for the
    /// `TradeEngine.executeTrade` lookup. Rookies drafted tonight are added to
    /// `rosters` but not here on purpose: a draft-night need is graded on the
    /// roster a GM walked into the building with.
    private var allLeaguePlayers: [Player] = []

    // MARK: - Reputation snapshot (used to compute round-recap deltas)

    private struct ReputationSnapshot {
        let ownerTrust: Int
        let fanMood: Int
        let lockerRoomMood: Int
        let narrative: MediaNarrative
    }

    private var roundStartReputationSnapshot: ReputationSnapshot?

    // MARK: - Dependencies

    private let career: Career
    private let modelContext: ModelContext
    private let recorder: DraftStoryRecorder
    private var clockTask: Task<Void, Never>?
    private var sequenceCounter: Int = 0

    /// Whose turn was on screen when the user hit Pause (`.playing` or
    /// `.userPick`). Held so `resume` restores the stance it froze rather than
    /// re-opening the slot — see the note on `resume()`.
    private var pausedMode: Mode?

    // MARK: - Lifecycle

    init(career: Career, modelContext: ModelContext) {
        self.career = career
        self.modelContext = modelContext
        self.recorder = DraftStoryRecorder(modelContext: modelContext, careerID: career.id)
    }

    deinit {
        clockTask?.cancel()
    }

    // MARK: - Computed

    var currentPick: DraftPick? {
        guard currentPickIndex < picks.count else { return nil }
        return picks[currentPickIndex]
    }

    var draftYear: Int { career.currentSeason }

    /// The open save. Exposed so the draft room can present the scouting
    /// prospect card (`ProspectDetailView`), which needs it for the phase gates
    /// on its own actions.
    var careerRef: Career { career }

    var userTeamID: UUID? { career.teamID }

    var isUserOnClock: Bool {
        guard let pick = currentPick, let teamID = userTeamID else { return false }
        return pick.currentTeamID == teamID
    }

    var picksUntilUserPick: Int {
        guard let teamID = userTeamID else { return 0 }
        for offset in 0..<(picks.count - currentPickIndex) {
            if picks[currentPickIndex + offset].currentTeamID == teamID {
                return offset
            }
        }
        return -1
    }

    var userPicksRemaining: Int {
        guard let teamID = userTeamID else { return 0 }
        return picks[currentPickIndex...].filter { $0.currentTeamID == teamID }.count
    }

    var currentRound: Int {
        currentPick?.round ?? 1
    }

    // MARK: - Setup

    func loadData() async {
        let season = career.currentSeason
        let cid = career.id
        let teamFetch = FetchDescriptor<Team>(predicate: #Predicate { $0.careerID == cid })
        let playerFetch = FetchDescriptor<Player>(predicate: #Predicate { $0.careerID == cid })
        let pickFetch = FetchDescriptor<DraftPick>(
            predicate: #Predicate { $0.careerID == cid && $0.seasonYear == season },
            sortBy: [SortDescriptor(\.pickNumber)]
        )

        let teams = (try? modelContext.fetch(teamFetch)) ?? []
        let allPlayers = (try? modelContext.fetch(playerFetch)) ?? []
        let persistedPicks = (try? modelContext.fetch(pickFetch)) ?? []

        // Picks: prefer in-memory (current cycle) but fall back to SwiftData
        // if the in-memory list is empty (e.g. fresh launch).
        let inMemoryPicks = WeekAdvancer.currentDraftPicks
            .filter { $0.seasonYear == season }
            .sorted { $0.pickNumber < $1.pickNumber }
        let draftPicks = !inMemoryPicks.isEmpty ? inMemoryPicks : persistedPicks

        // Prospects: SwiftData is the source of truth (preserves Scouting/Big Board
        // edits across app restarts). Fall back to in-memory only if SwiftData is
        // empty, and finally generate a fresh class on demand so the draft is
        // never blocked by missing scouting data.
        // Plan §5: a save that reaches the war room still carrying a pre-overhaul
        // class regenerates it here. No-op once a pick of this cycle is complete —
        // a draft in progress is never rebuilt underneath the user.
        WeekAdvancer.migrateLegacyDraftClassIfNeeded(career: career, modelContext: modelContext)

        let inMemoryClass = WeekAdvancer.currentDraftClass
        let prospectFetch = FetchDescriptor<CollegeProspect>(
            predicate: #Predicate { $0.careerID == cid }
        )
        let persistedClass = (try? modelContext.fetch(prospectFetch)) ?? []
        let draftClass: [CollegeProspect]
        if !persistedClass.isEmpty {
            draftClass = persistedClass
            WeekAdvancer.currentDraftClass = persistedClass
        } else if !inMemoryClass.isEmpty {
            draftClass = inMemoryClass
            // In-memory but never persisted — flush to SwiftData now.
            WeekAdvancer.persistDraftClass(inMemoryClass, to: modelContext)
        } else {
            let generated = ScoutingEngine.generateDraftClass()
            WeekAdvancer.currentDraftClass = generated
            WeekAdvancer.persistDraftClass(generated, to: modelContext)
            draftClass = generated
        }

        let draftedNames: Set<String> = Set(draftPicks.compactMap { $0.playerName })
        // Build the player-facing pool: declared, not already drafted by name
        // (across this and any earlier sessions persisted in SwiftData), and
        // deduplicated by UUID (SwiftData can carry stale dupes from earlier
        // generation cycles).
        var seenIDs = Set<UUID>()
        let availablePool = draftClass
            .filter { $0.isDeclaringForDraft }
            .filter { !draftedNames.contains("\($0.firstName) \($0.lastName)") }
            .filter { seenIDs.insert($0.id).inserted }

        self.teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        self.picks = draftPicks
        self.availableProspects = availablePool
        self.rosters = Dictionary(grouping: allPlayers, by: { $0.teamID ?? UUID() })

        // Wave 4: later-year picks are tradable assets on draft night — they
        // are the only thing that reaches the top of the board (finding S6).
        let futureFetch = FetchDescriptor<DraftPick>(
            predicate: #Predicate { $0.careerID == cid && $0.seasonYear > season },
            sortBy: [SortDescriptor(\.seasonYear), SortDescriptor(\.round)]
        )
        self.futurePicks = ((try? modelContext.fetch(futureFetch)) ?? []).filter { !$0.isComplete }

        self.allLeaguePlayers = allPlayers
        self.leagueCoreReference = TradeValueEngine.leagueCoreReference(allPlayers: allPlayers)
        self.marketSeats = [:]

        // Resolve each team's coordinator schemes once (#33 OSA B) so pick
        // grades can score a prospect against the drafting team's actual
        // offensive/defensive system instead of a flat placeholder.
        let allCoaches = (try? modelContext.fetch(FetchDescriptor<Coach>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        var schemeMap: [UUID: (offense: OffensiveScheme?, defense: DefensiveScheme?)] = [:]
        for coach in allCoaches {
            guard let teamID = coach.teamID else { continue }
            var entry = schemeMap[teamID] ?? (offense: nil, defense: nil)
            if let off = coach.offensiveScheme { entry.offense = off }
            if let def = coach.defensiveScheme { entry.defense = def }
            schemeMap[teamID] = entry
        }
        self.schemesByTeam = schemeMap

        // Compute public board ranks for the visible pool only — guarantees
        // contiguous 1..N rankings even when SwiftData carries leftover
        // already-drafted prospects from previous sessions. Pure: this map is
        // the DRAFT ROOM's, and it shrinks as picks come off the board.
        self.publicBoardRanks = DraftIntel.publicBoardRanks(for: availablePool)

        // The cross-screen board is a different thing and is published
        // separately: it is the whole declared class, so a prospect card opened
        // from the war room prints the same `market ≈ #N` as the scouting hub
        // instead of a rank measured against a pool that is 20 picks shorter.
        DraftIntel.refreshConsensusBoard(for: draftClass)

        // The user's own board, read from the same persisted order the Big
        // Board writes. Built over the declared class (not `availablePool`) so
        // the slot a row prints is stable for the whole night — and identical
        // to the one the scouting screens print.
        self.userBoardRanks = UserDraftBoard.slotMap(among: draftClass)

        // Team needs for the user's roster — refreshes each time the user
        // makes a pick so the picture stays current.
        if let teamID = career.teamID {
            self.teamNeedScores = DraftIntel.teamNeedScores(roster: rosters[teamID] ?? [])
        }

        // Load or create the DraftReputation row for this season.
        let careerID = career.id
        let repFetch = FetchDescriptor<DraftReputation>(
            predicate: #Predicate { $0.seasonYear == season && $0.careerID == careerID }
        )
        if let existing = (try? modelContext.fetch(repFetch))?.first {
            self.reputation = existing
        } else {
            let fresh = DraftReputation(seasonYear: season, careerID: careerID)
            modelContext.insert(fresh)
            try? modelContext.save()
            self.reputation = fresh
        }

        // Skip ahead through picks already completed in a partially-played draft.
        if let firstUnfinished = picks.firstIndex(where: { !$0.isComplete }) {
            currentPickIndex = firstUnfinished
            mode = .preDraft
        } else {
            // No unfinished picks: either no draft data at all, or the draft
            // was already fully played — go straight to the UDFA stage
            // instead of replaying completed picks.
            currentPickIndex = picks.count
            udfaStageFinished = WeekAdvancer.udfaStageCompletedSeasons.contains(season)
            mode = .complete
            prepareUDFAStage()
        }
        clockSeconds = 120
    }

    // MARK: - Control

    func start() {
        guard mode == .preDraft else { return }
        recordEvent(type: .draftStarted)
        if let rep = reputation {
            roundStartReputationSnapshot = ReputationSnapshot(
                ownerTrust: rep.ownerTrust,
                fanMood: rep.fanMood,
                lockerRoomMood: rep.lockerRoomMood,
                narrative: rep.mediaNarrative
            )
        }
        announceCurrentRoundIfNeeded()
        beginCurrentPick()
    }

    /// Freezes the pick clock where it stands.
    ///
    /// Task #195: pausing is a *transport* action and must not touch the pick.
    /// Only `mode` moves; `clockSeconds` is left exactly as it was, and
    /// `pausedMode` remembers whose turn was frozen so `resume` can put it back
    /// without re-deriving it from board state.
    func pause() {
        guard mode == .playing || mode == .userPick else { return }
        clockTask?.cancel()
        pausedMode = mode
        mode = .paused
    }

    /// Un-freezes the clock at the second it stopped on.
    ///
    /// Task #195 BUG: this used to call `beginCurrentPick()`, which is the
    /// *slot-opening* routine — it re-announced `.onTheClock`, re-rolled the
    /// incoming trade-up window, and, the visible symptom, reset `clockSeconds`
    /// to a full 120 / 60. Pausing with eleven seconds left and resuming handed
    /// the user two full minutes back, so Pause was a free timeout and the clock
    /// meant nothing.
    ///
    /// Resuming re-arms the same countdown instead: the slot is already open, so
    /// the only thing that has to restart is the ticking task, and it reads the
    /// `clockSeconds` that pause left behind.
    func resume() {
        guard mode == .paused else { return }
        let fallback: Mode = isUserOnClock ? .userPick : .playing
        let restored: Mode = pausedMode ?? fallback
        pausedMode = nil
        mode = restored
        // The move-up call sheet holds the clock in its own right and restarts it
        // itself on close (`closeTradeUpBoard`). Starting a second loop here would
        // run the pick down underneath an open sheet.
        guard !isTradeUpBoardOpen else { return }
        startClockLoop(forUser: restored == .userPick)
    }

    func setSpeed(_ newSpeed: Double) {
        speed = max(0.25, min(8.0, newSpeed))
    }

    /// The room's one fast-forward (#195): run the AI's night out until the user
    /// is back at the podium, or — when his card count is spent — until the draft
    /// is over.
    ///
    /// `autoAdvanceUntil` stops early on the two things the user has to answer,
    /// a ringing phone and a round recap, so a tap can land short of the target;
    /// that is the point, not a shortfall. Tapping again carries on.
    func skipToMyPick() {
        guard userTeamID != nil else { return }
        // Nothing to fast-forward before the draft is under way or after it has
        // ended — and a board opened outside the draft phase never starts, so
        // without this the button would play the whole thing out in July.
        guard mode == .playing || mode == .paused else { return }
        // `autoAdvanceUntil` finishes by calling `beginCurrentPick()`, which
        // re-opens the slot and puts a FULL clock on it. That is correct when
        // cards were actually turned and wrong when none were, so the two ways
        // the predicate can already be satisfied at the door are refused here
        // rather than costing the user a slot's worth of ticking: he is on the
        // clock, or a rival GM is on the phone and the tape is stopped for him.
        guard !isUserOnClock, pendingTradeOffer == nil else { return }
        clockTask?.cancel()
        autoAdvanceUntil { coordinator in
            coordinator.isUserOnClock || coordinator.mode == .complete
        }
    }

    // #195 removed `skipToNextEvent()` and `skipToNextRound()`. The rail carried
    // three fast-forwards — "My pick", "Next event", "Next round" — and not one
    // of them named where it would stop, so the user learned to tap whichever
    // one moved the board and never found out why it halted. `skipToMyPick` is
    // now the only one, and it needs no round variant: `autoAdvanceUntil`
    // already breaks at a round recap and at a ringing phone, which is every
    // stop the other two could reach that the user would want.
    //
    // The lesson those predicates paid for is worth keeping: their stop
    // conditions were STATE, not edges, so they had to be read against a
    // baseline captured at the tap. `lastPickResult?.isBigDrop` was true on
    // nearly every card before `DraftIntel.isBigSlide` was fixed, and a
    // fast-forward that satisfied its own predicate before turning a single card
    // looked exactly like one that stopped at every event.

    // MARK: - User pick

    /// The user hands in a card.
    ///
    /// `forPickNumber` is the slot the confirmation was raised for. Passing it
    /// makes the confirm belong to a specific turn: a stale tap that somehow
    /// arrives after the board has moved on cannot spend the NEXT pick on a name
    /// chosen for the last one. The claim happens before anything is written —
    /// the clock task is cancelled first, then the slot is taken.
    func selectProspect(_ prospect: CollegeProspect, forPickNumber pickNumber: Int? = nil) {
        guard isUserOnClock, let pick = currentPick else { return }
        if let pickNumber, pick.pickNumber != pickNumber { return }
        clockTask?.cancel()
        guard completePick(pick: pick, prospect: prospect, isUserPick: true) else { return }
        advance()
    }

    // MARK: - Trades (R24 pick swaps, rebuilt in Wave 4)

    /// The board every trade decision is read off. `seat` is a closure so the
    /// engine can price as many clubs as it likes while the cache lives here.
    private var tradeBoard: DraftDayTradeEngine.Board {
        DraftDayTradeEngine.Board(
            picks: picks,
            futurePicks: futurePicks,
            currentPickIndex: currentPickIndex,
            currentSeason: career.currentSeason,
            availableProspects: availableProspects,
            publicBoardRanks: publicBoardRanks,
            seat: { [weak self] teamID in self?.seat(for: teamID) }
        )
    }

    /// One club's GM chair: persona (hidden chart lean), stance and
    /// starter-quality needs. Cached — see `marketSeats`.
    private func seat(for teamID: UUID) -> TradeValueEngine.GMMarketView? {
        if let cached = marketSeats[teamID] { return cached }
        guard let team = teamsByID[teamID] else { return nil }
        let view = TradeValueEngine.marketView(
            team: team,
            allPlayers: allLeaguePlayers,
            season: career.currentSeason,
            week: career.currentWeek,
            coreReference: leagueCoreReference
        )
        marketSeats[teamID] = view
        return view
    }

    // MARK: Accept / decline

    /// The user accepts whatever is on the table.
    ///
    /// Wave 4 routes draft-day deals through `TradeEngine.executeTrade` instead
    /// of flipping `currentTeamID` by hand: the offer can now carry veterans in
    /// either direction, and only the one primitive gets the cap split, the
    /// contract re-point and the ledger row right.
    func acceptTradeOffer() {
        guard let offer = pendingTradeOffer, let teamID = userTeamID else { return }
        guard isOfferStillValid(offer) else {
            pendingTradeOffer = nil
            tradeDownMessage = "That offer is off the table — the assets have moved."
            return
        }
        guard execute(offer: offer, userTeamID: teamID) else {
            // The one primitive refused (unknown team / unbound career). Say so
            // rather than clearing the banner and pretending the deal happened.
            tradeDownMessage = "The deal could not be processed. Nothing changed."
            return
        }
        pendingTradeOffer = nil
        tradeDownMessage = nil

        // If the pick on the clock just changed hands, restart the pick flow so
        // the new owner (either side) goes on the clock immediately.
        if let current = currentPick {
            let ownerChanged = (mode == .userPick && current.currentTeamID != teamID)
                || (mode != .userPick && current.currentTeamID == teamID)
            if ownerChanged { beginCurrentPick() }
        }
    }

    /// The user turns the offer down.
    func declineTradeOffer() {
        guard let offer = pendingTradeOffer else { return }
        let pickNumber = offer.kind == .userMovesDown
            ? offer.userGivesPicks.first?.pickNumber
            : offer.userGetsPicks.first?.pickNumber
        if let pickNumber {
            switch offer.origin {
            case .aiCall:   declinedTradeUpPickNumbers.insert(pickNumber)
            case .userCall: declinedTradeDownPickNumbers.insert(pickNumber)
            }
        }
        recordTradeEvent(
            type: .tradeDeclined,
            teamID: offer.partnerTeamID,
            pickNumber: pickNumber,
            round: nil,
            headline: "\(offer.partnerAbbreviation) hung up",
            detail: "You passed on \(offer.gmName)'s offer\(pickNumber.map { " for #\($0)" } ?? "").",
            involvesUser: true,
            beat: nil
        )
        pendingTradeOffer = nil
    }

    // MARK: Trade DOWN (user shops the pick he is on the clock with)

    /// User taps "Trade Down" while on the clock: search for a willing AI
    /// partner. One search per pick — if the league passes, that's the answer.
    func requestTradeDown() {
        guard isUserOnClock, let pick = currentPick, let teamID = userTeamID else { return }
        guard pendingTradeOffer == nil else { return }
        if declinedTradeDownPickNumbers.contains(pick.pickNumber) {
            tradeDownMessage = "You already turned down the price on #\(pick.pickNumber)."
            return
        }
        if tradeDownSearchedPickNumber == pick.pickNumber {
            if tradeDownMessage == nil {
                tradeDownMessage = "You already shopped this pick — no new callers."
            }
            return
        }
        tradeDownSearchedPickNumber = pick.pickNumber

        if let offer = DraftDayTradeEngine.userTradeDownOffer(
            currentPick: pick,
            board: tradeBoard,
            userTeamID: teamID
        ) {
            pendingTradeOffer = offer
            tradeDownMessage = nil
            recordTradeEvent(
                type: .tradeOffered,
                teamID: offer.partnerTeamID,
                pickNumber: pick.pickNumber,
                round: pick.round,
                headline: "\(offer.partnerAbbreviation) call about #\(pick.pickNumber)",
                detail: offer.motive,
                involvesUser: true,
                beat: nil
            )
        } else {
            tradeDownMessage = "No teams are willing to move up to #\(pick.pickNumber) right now."
        }
    }

    // MARK: Trade UP (the user calls)

    /// Opens the call sheet. Freezes the clock without touching `mode`, so the
    /// room keeps its on-the-clock stance when the user calls from his own turn
    /// (#197: that used to mean "the pick sheet stays up"; the sheet is retired
    /// and the stance now lives on the board and the control bar).
    ///
    /// Cancelling the task is the whole freeze: `clockSeconds` is deliberately
    /// left alone so `closeTradeUpBoard` resumes the same countdown (#195 — the
    /// same remaining-time contract as Pause/Resume; pricing the board is not a
    /// way to buy back two minutes of thinking time).
    func openTradeUpBoard(for prospect: CollegeProspect? = nil) {
        guard userTeamID != nil, mode != .complete, mode != .loading else { return }
        clockTask?.cancel()
        tradeUpProspect = prospect
        isTradeUpBoardOpen = true
        refreshTradeUpQuotes()
    }

    func closeTradeUpBoard() {
        guard isTradeUpBoardOpen else { return }
        isTradeUpBoardOpen = false
        tradeUpQuotes = []
        tradeUpProspect = nil
        tradeUpMessage = nil
        // Picks the countdown back up mid-stride (`startClockLoop` never resets
        // `clockSeconds`). A user who paused before calling stays paused and
        // keeps his Resume button.
        if mode == .playing || mode == .userPick {
            startClockLoop(forUser: mode == .userPick)
        }
    }

    /// Veterans in the package are opt-in: most users are shopping picks, and a
    /// builder that silently offered up a starter would be a nasty surprise.
    func setTradeUpIncludesVeterans(_ enabled: Bool) {
        guard tradeUpIncludesVeterans != enabled else { return }
        tradeUpIncludesVeterans = enabled
        if isTradeUpBoardOpen { refreshTradeUpQuotes() }
    }

    /// Re-prices every callable slot ahead of the user.
    func refreshTradeUpQuotes() {
        guard let teamID = userTeamID else { return }
        let board = tradeBoard
        var targets = DraftDayTradeEngine.tradeUpTargets(board: board, userTeamID: teamID)
        if let prospect = tradeUpProspect, let rank = publicBoardRanks[prospect.id] {
            // Only slots where he is plausibly still there: a few picks either
            // side of his consensus rank. Falling back to the full list keeps
            // the sheet from ever being empty for a prospect the user starred.
            let narrowed = targets.filter { $0.pickNumber >= max(1, rank - 8) }
            if !narrowed.isEmpty { targets = narrowed }
        }
        tradeUpQuotes = targets.compactMap { target in
            DraftDayTradeEngine.userTradeUpQuote(
                targetPick: target,
                board: board,
                userTeamID: teamID,
                allowPlayers: tradeUpIncludesVeterans,
                targetProspect: tradeUpProspect
            )
        }
        tradeUpMessage = tradeUpQuotes.isEmpty
            ? "Nobody ahead of you is picking up the phone."
            : nil
    }

    /// Commits one quote from the call sheet.
    func acceptTradeUpQuote(_ quote: DraftDayTradeEngine.DraftTradeOffer) {
        guard quote.isAffordable, let teamID = userTeamID else { return }
        guard isOfferStillValid(quote) else {
            tradeUpMessage = "That pick is gone — re-price the board."
            refreshTradeUpQuotes()
            return
        }
        guard execute(offer: quote, userTeamID: teamID) else {
            tradeUpMessage = "The deal could not be processed. Nothing changed."
            return
        }
        closeTradeUpBoard()
        if let current = currentPick, current.currentTeamID == teamID, mode != .userPick {
            beginCurrentPick()
        }
    }

    // MARK: Incoming AI calls

    /// Called from the pick flow: when the user is 1-3 picks from the clock, an
    /// AI team may offer to trade up into the user's pick.
    ///
    /// Wave 4 (plan finding S6): this also runs inside `autoAdvanceUntil`, so
    /// the flagship moment finally fires on the skip path — the only way anyone
    /// plays a 224-pick draft. The fast-forward loop stops as soon as an offer
    /// lands, which is what "roll offers before the fast-forward resumes" means
    /// in practice.
    private func considerAITradeUpOffer() {
        guard !isUserOnClock,
              pendingTradeOffer == nil,
              !isTradeUpBoardOpen,
              let teamID = userTeamID else { return }
        let until = picksUntilUserPick
        guard until >= 1, until <= 3 else { return }
        // ~20 % gate per pick inside the window so offers stay meaningful.
        guard Int.random(in: 1...100) <= 20 else { return }
        guard let userPick = picks.dropFirst(currentPickIndex).first(where: { $0.currentTeamID == teamID }),
              !declinedTradeUpPickNumbers.contains(userPick.pickNumber) else { return }

        if let offer = DraftDayTradeEngine.aiTradeUpOffer(
            userPick: userPick,
            board: tradeBoard,
            userTeamID: teamID
        ) {
            pendingTradeOffer = offer
            recordTradeEvent(
                type: .tradeOffered,
                teamID: offer.partnerTeamID,
                pickNumber: userPick.pickNumber,
                round: userPick.round,
                headline: "\(offer.partnerAbbreviation) want #\(userPick.pickNumber)",
                detail: offer.motive,
                involvesUser: true,
                beat: nil
            )
        }
    }

    // MARK: AI vs AI (plan finding S6 — the "31 mannequins")

    /// Rolls one AI-vs-AI move-up into the pick about to be made. Runs on both
    /// the live path and the fast-forward path, so a skipped draft still reads
    /// like a draft.
    private func considerAIvsAISwap() {
        guard let pick = currentPick, !pick.isComplete else { return }
        guard pick.currentTeamID != userTeamID else { return }
        // One roll per slot. `beginCurrentPick` runs again after an accepted
        // offer and after the fast-forward stops, and without this a single
        // pick could be shopped three times at three separate odds.
        guard swapRolledPickNumber != pick.pickNumber else { return }
        swapRolledPickNumber = pick.pickNumber
        guard Double.random(in: 0..<1) < DraftDayTradeEngine.aiSwapChance(round: pick.round) else { return }
        guard let swap = DraftDayTradeEngine.aiVsAiSwap(board: tradeBoard, userTeamID: userTeamID) else { return }
        execute(swap: swap)
    }

    private func execute(swap: DraftDayTradeEngine.AISwap) {
        let proposal = TradeProposal(
            offeringTeamID: swap.buyerTeamID,
            receivingTeamID: swap.sellerTeamID,
            sendingPlayers: swap.buyerGives.compactMap { asset in
                if case .player(let player) = asset { return player.id } else { return nil }
            },
            receivingPlayers: [],
            sendingPicks: swap.buyerGives.compactMap { asset in
                if case .pick(let pick) = asset { return pick.id } else { return nil }
            },
            receivingPicks: swap.sellerGives.map(\.id)
        )
        guard let record = applyTrade(proposal: proposal) else { return }
        settleAfterTrade(
            proposal: proposal,
            record: record,
            teamIDs: [swap.buyerTeamID, swap.sellerTeamID]
        )

        let hasVeteran = swap.buyerGives.contains { if case .player = $0 { return true } else { return false } }
        let notable = (currentPick?.round ?? 9) <= 2 || hasVeteran
        recordTradeEvent(
            type: .tradeAccepted,
            teamID: swap.buyerTeamID,
            pickNumber: swap.targetPickNumber,
            round: currentPick?.round,
            headline: swap.headline,
            detail: swap.motive,
            involvesUser: false,
            beat: notable
                ? TradeBeat(
                    title: "TRADE: \(swap.buyerAbbreviation) MOVE UP",
                    subtitle: "#\(swap.targetPickNumber) from \(swap.sellerAbbreviation) — \(swap.motive)"
                )
                : nil
        )
    }

    // MARK: Execution plumbing

    /// Applies one of the user's draft-night deals and reports it everywhere a
    /// trade has to show up: ledger row, league news, inbox, ticker, event log.
    @discardableResult
    private func execute(offer: DraftDayTradeEngine.DraftTradeOffer, userTeamID teamID: UUID) -> Bool {
        let proposal = TradeProposal(
            offeringTeamID: teamID,
            receivingTeamID: offer.partnerTeamID,
            sendingPlayers: offer.userGivesPlayers.map(\.id),
            receivingPlayers: offer.userGetsPlayers.map(\.id),
            sendingPicks: offer.userGivesPicks.map(\.id),
            receivingPicks: offer.userGetsPicks.map(\.id)
        )
        guard let record = applyTrade(proposal: proposal) else { return false }
        settleAfterTrade(
            proposal: proposal,
            record: record,
            teamIDs: [teamID, offer.partnerTeamID]
        )

        let season = career.currentSeason
        let movedUp = offer.kind == .userMovesUp
        let slot = movedUp
            ? offer.userGetsPicks.first?.pickNumber
            : offer.userGivesPicks.first?.pickNumber
        recordTradeEvent(
            type: .tradeAccepted,
            teamID: offer.partnerTeamID,
            pickNumber: slot,
            round: movedUp ? offer.userGetsPicks.first?.round : offer.userGivesPicks.first?.round,
            headline: movedUp
                ? "TRADE — you move up to #\(slot ?? 0), \(offer.partnerAbbreviation) move down"
                : "TRADE — you send #\(slot ?? 0) to \(offer.partnerAbbreviation)",
            detail: "Out: \(offer.givesLabel(currentSeason: season)) · In: \(offer.getsLabel(currentSeason: season))",
            involvesUser: true,
            beat: TradeBeat(
                title: movedUp ? "YOU'RE ON THE MOVE" : "YOU MOVED DOWN",
                subtitle: movedUp
                    ? "Up to #\(slot ?? 0) — \(offer.getsLabel(currentSeason: season)) in, \(offer.givesLabel(currentSeason: season)) out"
                    : "\(offer.getsLabel(currentSeason: season)) in from \(offer.partnerAbbreviation)"
            )
        )
        return true
    }

    /// The one call that moves assets. Everything else in this file goes
    /// through it so no draft-night deal can skip the cap split or the ledger.
    private func applyTrade(proposal: TradeProposal) -> TradeRecord? {
        let outcome = TradeEngine.executeTrade(
            proposal: proposal,
            allPlayers: allLeaguePlayers,
            allPicks: picks + futurePicks,
            capMode: career.capMode,
            ledger: TradeLedger.Context(
                kind: .draftDay,
                season: career.currentSeason,
                week: career.currentWeek,
                phase: career.currentPhase
            ),
            modelContext: modelContext
        )
        return outcome.record
    }

    /// News + inbox + local caches after a trade has been applied.
    private func settleAfterTrade(
        proposal: TradeProposal,
        record: TradeRecord,
        teamIDs: Set<UUID>
    ) {
        // Wave 2: every executed trade in the league is announced, and a
        // draft-weekend deal is no exception — the war-room ticker is not the
        // news feed, and a deal struck in April should still be readable in
        // July. The headline goes straight into the persisted `newsLog` (there
        // is no week advance in progress to fold it in) while the optional
        // inbox message rides the normal `lastInboxMessages` channel.
        let announcement = TradeNewsFactory.announce(
            record: record,
            teamsByID: teamsByID,
            userTeamID: userTeamID
        )
        career.newsLog = [announcement.news] + career.newsLog
        if let inbox = announcement.inbox {
            WeekAdvancer.lastInboxMessages.append(inbox)
        }

        // `executeTrade` moves ownership but not the denormalised abbreviation
        // the ticker renders, and the local roster map has to follow the
        // players so needs/AI picking stay honest for the rest of the night.
        let movedPickIDs = Set(proposal.sendingPicks + proposal.receivingPicks)
        for pick in (picks + futurePicks) where movedPickIDs.contains(pick.id) {
            pick.teamAbbreviation = teamsByID[pick.currentTeamID]?.abbreviation
        }
        let movedPlayerIDs = Set(proposal.sendingPlayers + proposal.receivingPlayers)
        if !movedPlayerIDs.isEmpty {
            resyncLocalRosters(playerIDs: movedPlayerIDs)
        }
        for teamID in teamIDs { marketSeats[teamID] = nil }
        if let userTeamID {
            teamNeedScores = DraftIntel.teamNeedScores(roster: rosters[userTeamID] ?? [])
        }
        try? modelContext.save()
    }

    /// Re-files traded players in the local roster map (the source the draft
    /// room reads; `Player.teamID` is already correct on the model side).
    private func resyncLocalRosters(playerIDs: Set<UUID>) {
        for teamID in rosters.keys {
            rosters[teamID]?.removeAll { playerIDs.contains($0.id) }
        }
        for player in allLeaguePlayers where playerIDs.contains(player.id) {
            guard let teamID = player.teamID else { continue }
            rosters[teamID, default: []].append(player)
        }
    }

    /// A pending offer survives only while every asset on both sides is still
    /// where the offer says it is.
    private func isOfferStillValid(_ offer: DraftDayTradeEngine.DraftTradeOffer) -> Bool {
        guard let teamID = userTeamID else { return false }
        let currentNumber = currentPick?.pickNumber ?? Int.max
        let season = career.currentSeason

        func pickIsLive(_ pick: DraftPick, ownedBy owner: UUID) -> Bool {
            guard pick.currentTeamID == owner, !pick.isComplete else { return false }
            // A future-year pick has no slot in tonight's order to fall behind.
            guard pick.seasonYear == season else { return true }
            return pick.pickNumber >= currentNumber
        }

        for pick in offer.userGivesPicks where !pickIsLive(pick, ownedBy: teamID) { return false }
        for pick in offer.userGetsPicks where !pickIsLive(pick, ownedBy: offer.partnerTeamID) { return false }
        for player in offer.userGivesPlayers where player.teamID != teamID { return false }
        for player in offer.userGetsPlayers where player.teamID != offer.partnerTeamID { return false }
        return true
    }

    // MARK: Ticker + beats

    /// Records the persisted `DraftEvent` AND the line the ticker renders, in
    /// one call — the two drifted apart before Wave 4 (the events existed, the
    /// ticker never showed them).
    private func recordTradeEvent(
        type: DraftEventType,
        teamID: UUID?,
        pickNumber: Int?,
        round: Int?,
        headline: String,
        detail: String,
        involvesUser: Bool,
        beat: TradeBeat?
    ) {
        recordEvent(type: type, teamID: teamID, pickNumber: pickNumber, round: round)
        tradeTicker.insert(
            TradeTickerLine(
                pickNumber: pickNumber,
                headline: headline,
                detail: detail,
                involvesUser: involvesUser
            ),
            at: 0
        )
        if tradeTicker.count > 30 { tradeTicker.removeLast(tradeTicker.count - 30) }
        if let beat { pendingTradeBeats.append(beat) }
    }

    /// UI calls this once it has shown the next trade beat.
    func consumeOldestTradeBeat() {
        guard !pendingTradeBeats.isEmpty else { return }
        pendingTradeBeats.removeFirst()
    }


    // MARK: - Internal pick flow

    /// Opens a slot: announces it, gives the market its rolls, and puts a FULL
    /// clock on it.
    ///
    /// This is the only place `clockSeconds` is allowed to be reset, which is
    /// what makes "resume where you stopped" (`resume`, `closeTradeUpBoard`)
    /// possible at all — anything that merely re-arms the countdown calls
    /// `startClockLoop` instead.
    private func beginCurrentPick() {
        // A new slot ends any frozen stance the user left behind (skipping
        // forward while paused reaches here).
        pausedMode = nil

        guard let pick = currentPick else {
            completeDraft()
            return
        }

        // Expire stale offers (assets drafted or ownership moved). `.tradeExpired`
        // existed in `DraftEventType` from R24 and had never been written by
        // anything — an offer just silently vanished off the screen.
        if let offer = pendingTradeOffer, !isOfferStillValid(offer) {
            recordTradeEvent(
                type: .tradeExpired,
                teamID: offer.partnerTeamID,
                pickNumber: offer.userGivesPicks.first?.pickNumber,
                round: offer.userGivesPicks.first?.round,
                headline: "\(offer.partnerAbbreviation) pulled their offer",
                detail: "The board moved on before you answered.",
                involvesUser: true,
                beat: nil
            )
            pendingTradeOffer = nil
        }
        tradeDownMessage = nil

        // AI clubs get their move BEFORE the slot is announced — a war room
        // that trades up does it while the previous card is being handed in,
        // not after the wrong team is announced as on the clock.
        considerAIvsAISwap()

        recordEvent(
            type: .onTheClock,
            teamID: pick.currentTeamID,
            pickNumber: pick.pickNumber,
            round: pick.round
        )

        considerAITradeUpOffer()

        if pick.currentTeamID == userTeamID {
            mode = .userPick
            clockSeconds = 120
            startClockLoop(forUser: true)
        } else {
            mode = .playing
            clockSeconds = 60
            startClockLoop(forUser: false)
        }
    }

    /// Re-arms the one-second countdown against whatever `clockSeconds` already
    /// holds. It never sets that value — every caller other than
    /// `beginCurrentPick` (resume, closing the move-up sheet) is resuming a slot
    /// that is already open and must pick the count up mid-stride.
    private func startClockLoop(forUser: Bool) {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                let nanos = UInt64(1_000_000_000.0 / max(0.1, self?.speed ?? 1.0))
                try? await Task.sleep(nanoseconds: nanos)
                guard let self else { return }
                if Task.isCancelled { return }
                self.tickClock(forUser: forUser)
            }
        }
    }

    private func tickClock(forUser: Bool) {
        // A modal the user owes an answer to is open (confirm-pick alert, round
        // recap): the clock waits for him rather than deciding for him (#146).
        guard !isClockHeld else { return }
        clockSeconds = max(0, clockSeconds - 1)
        guard clockSeconds == 0 else { return }
        clockTask?.cancel()
        // The slot may already have been filed by the other writer (the user's
        // confirm). Expiry then has nothing to do — and must NOT advance a
        // second time, which would skip the next club's turn entirely.
        guard let pick = currentPick, !claimedPickNumbers.contains(pick.pickNumber) else { return }
        if forUser {
            // THE CLOCK FILES FROM THE USER'S BOARD, NOT FROM THE LEAGUE AI
            // (#207).
            //
            // This branch used to call `DraftEngine.aiMakePick`, i.e. the same
            // routine the other 31 clubs use — which scores `trueOverall` and
            // `truePotential` through `AIDraftPerception`. Handing the user's
            // own card to it is the room's single worst fog breach: it reaches
            // straight past the board he spent a spring building, files on a
            // rating he is never allowed to see, and leaves him with a rookie
            // and no account of where the name came from.
            //
            // `UserDraftBoard.autoPick` is the same decision taken from HIS
            // chair — marks first (`elite` > `target`), then his persisted
            // board order, then the fogged media consensus for a class he never
            // touched. It cannot read a hidden number, and every name it can
            // return is one he could have pointed at himself.
            //
            // The empty-pool guard stays: the user cannot select from an
            // exhausted board either, so the slot is skipped rather than run
            // into a trap. (`autoPick` returns `nil` there rather than
            // `fatalError`-ing, but the explicit test keeps the intent local.)
            if !availableProspects.isEmpty,
               let chosen = UserDraftBoard.autoPick(
                   among: availableProspects,
                   boardRanks: userBoardRanks
               ) {
                completePick(pick: pick, prospect: chosen, isUserPick: false, ownerOverride: true)
            }
            advance()
        } else {
            aiMakePickForCurrent()
            advance()
        }
    }

    private func aiMakePickForCurrent() {
        guard let pick = currentPick,
              let team = teamsByID[pick.currentTeamID],
              !availableProspects.isEmpty else { return }
        let roster = rosters[pick.currentTeamID] ?? []
        let chosen = DraftEngine.aiMakePick(
            team: team,
            availableProspects: availableProspects,
            teamRoster: roster
        )
        completePick(pick: pick, prospect: chosen, isUserPick: false)
    }

    /// Writes one card. Returns `false` when the slot was already filed, so the
    /// caller knows not to advance the board a second time (task #146).
    @discardableResult
    private func completePick(
        pick: DraftPick,
        prospect: CollegeProspect,
        isUserPick: Bool,
        ownerOverride: Bool = false
    ) -> Bool {
        // One writer per slot, whoever gets here first.
        guard !claimedPickNumbers.contains(pick.pickNumber), !pick.isComplete else { return false }
        claimedPickNumbers.insert(pick.pickNumber)
        // Recorded in the same breath as the claim, so the ticker's history
        // rows — which are built from `DraftPick`, not from `PickResult` — can
        // label the card the clock filed (#207).
        if ownerOverride { autoPickNumbers.insert(pick.pickNumber) }

        // Convert prospect → Player
        let player = DraftEngine.convertToPlayer(
            prospect: prospect,
            teamID: pick.currentTeamID,
            pickNumber: pick.pickNumber,
            draftSeason: pick.seasonYear,
            // Rookie slot money is a share of the cap; the drafting club's own
            // cap is what it is a share OF (task #87 / F5).
            salaryCap: teamsByID[pick.currentTeamID]?.salaryCap
                ?? ContractEngine.openingSalaryCap
        )
        // Seed scheme/position familiarity from the drafting team's coordinators —
        // without this every rookie enters the league at familiarity 0.
        let draftingSchemes = schemesByTeam[pick.currentTeamID]
        DraftEngine.initializeRookieFamiliarity(
            player: player,
            prospect: prospect,
            offensiveScheme: draftingSchemes?.offense,
            defensiveScheme: draftingSchemes?.defense
        )
        // TRACK B — stamp the pre-camp fog band on the user's own picks.
        //
        // The prospect row is about to leave the board (and the class is thrown
        // away at the next cycle), so the ONLY moment his scouted band can be
        // carried onto the player is right here. Stored only when the user's
        // building actually filed on him: everyone else — AI selections,
        // auto-picks on unscouted men — keeps the empty string and reads as the
        // media consensus for his round (`RookieFog.consensusBand`).
        if pick.currentTeamID == userTeamID {
            let read = ProspectFog.read(prospect)
            if case .scouts = read.source, read.band != nil {
                player.preCampScoutBand = read.text
            }
        }
        player.careerID = career.id
        modelContext.insert(player)
        // Task #89: charge the slot to the drafting club NOW. The cap sheet used
        // to stay silent about the entire drafted class from draft night until
        // `FreeAgencyEngine.executeNewLeagueYear`'s true-up rebuilt usage the
        // following March — nine months in which a club's own screen understated
        // its commitments by a whole rookie class, and in which the AI's cap-room
        // tests (trades, camp signings) read a number that was not true.
        teamsByID[pick.currentTeamID]?.currentCapUsage += player.annualSalary
        // Task #94: charging it silently is the other half of the same bug. The
        // draft has no affordability test and should not have one — a drafted
        // man is signed whether the club has room or not — but the user was
        // never told when his own class ate the room. Say it out loud.
        if pick.currentTeamID == userTeamID {
            userClassCapCharge += player.annualSalary
            announceCapRoomIfOver(teamID: pick.currentTeamID, pickNumber: pick.pickNumber)
        }
        // He is in the league now — take him off every future prospect pool.
        // `ScoutingEngine.getUDFAPool` (the OTAs bulk fallback) filters on
        // `isDeclaringForDraft && mockDraftPickNumber == nil`, and the mock is
        // only an annotation: without this a drafted rookie whose mock slot was
        // never stamped (a regenerated class, a cycle whose mock was not
        // refreshed) is signed a SECOND time as a UDFA by an AI team.
        prospect.isDeclaringForDraft = false

        // Update DraftPick
        pick.playerID = player.id
        pick.playerName = "\(prospect.firstName) \(prospect.lastName)"
        pick.playerPosition = prospect.position.rawValue
        pick.playerCollege = prospect.college
        pick.scoutGrade = scoutGradeLabel(for: prospect)
        pick.teamAbbreviation = teamsByID[pick.currentTeamID]?.abbreviation
        pick.isComplete = true

        // Compute and persist Public Pick Grade
        let grade = computePickGrade(pick: pick, prospect: prospect)
        let pickGrade = DraftPickGrade(
            pickID: pick.id,
            draftYear: pick.seasonYear,
            pickNumber: pick.pickNumber,
            teamID: pick.currentTeamID,
            prospectID: prospect.id,
            playerID: player.id,
            publicGrade: grade.grade,
            publicValueDelta: grade.inputs.valueDelta,
            publicNeedScore: grade.inputs.needScore,
            publicSchemeFit: grade.inputs.schemeFit,
            publicOVR: grade.inputs.publicOVR,
            isGem: grade.isGemCandidate
        )
        pickGrade.careerID = career.id
        modelContext.insert(pickGrade)

        // THE DOSSIER, READ BEFORE THE ROSTER MOVES (#203).
        //
        // Every field on `PickResult.Dossier` has to be sampled here, in this
        // order, or it answers a different question than the card asks:
        //
        //   * the prospect leaves `availableProspects` on the next line, so a
        //     view holding only the `PickResult` can never look his age, school,
        //     mark or fogged band up again;
        //   * `fillsPickerNeed` is about the hole the club had **when it walked
        //     to the podium**. Sampled after `rosters[...].append(player)` it is
        //     measured against a roster that already contains the man being
        //     evaluated, which is how a first-round corner stops counting as a
        //     corner need in the same frame he was drafted to fill one.
        let dossier = PickResult.Dossier(
            college: prospect.college,
            age: prospect.age,
            userMark: prospect.userMark,
            userBoardRank: userBoardRanks[prospect.id],
            consensusRank: publicBoardRanks[prospect.id],
            read: ProspectFog.read(prospect),
            fillsPickerNeed: DraftEngine
                .topTeamNeeds(roster: rosters[pick.currentTeamID] ?? [], limit: 3)
                .contains(prospect.position)
        )

        // Update local state
        if let idx = availableProspects.firstIndex(where: { $0.id == prospect.id }) {
            availableProspects.remove(at: idx)
        }
        rosters[pick.currentTeamID, default: []].append(player)

        // Refresh team needs for the user after every pick (their or otherwise)
        // since AI picks may slot into shared positional needs and shift trades.
        if let userTeamID = userTeamID {
            self.teamNeedScores = DraftIntel.teamNeedScores(roster: rosters[userTeamID] ?? [])
        }

        // Record events
        recordEvent(
            type: .pickMade,
            teamID: pick.currentTeamID,
            pickNumber: pick.pickNumber,
            round: pick.round,
            prospectID: prospect.id
        )
        if grade.isGemCandidate {
            recordEvent(
                type: .stealAlert,
                teamID: pick.currentTeamID,
                pickNumber: pick.pickNumber,
                round: pick.round,
                prospectID: prospect.id
            )
        }

        // A slide is measured in PICKS past the slot the media gave him. The
        // old test read `pickNumber > draftProjection + 8`, i.e. a pick number
        // against a ROUND number: a man projected in round 3 "slid" from pick
        // 12 onward, so the beat fired on almost every card and carried no
        // information at all.
        let isBigDrop = DraftIntel.isBigSlide(
            for: prospect,
            pickNumber: pick.pickNumber,
            consensusRank: publicBoardRanks[prospect.id]
        )

        let result = PickResult(
            pickNumber: pick.pickNumber,
            round: pick.round,
            teamAbbrev: pick.teamAbbreviation ?? "—",
            playerName: pick.playerName ?? "—",
            position: prospect.position,
            grade: grade.grade,
            isGem: grade.isGemCandidate,
            isBigDrop: isBigDrop,
            isUserPick: isUserPick,
            isAutoPick: ownerOverride,
            faceID: prospect.faceID,
            dossier: dossier
        )
        lastPickResult = result
        allPickResults.append(result)
        recordStoryBeats(for: result, prospect: prospect, pick: pick)

        // Reactions for the user's own picks (mechanical effects only)
        if isUserPick, let rep = reputation {
            let reactions = ReactionsEngine.reactions(to: result, isUserTeam: true)
            ReactionsEngine.apply(reactions, to: rep)
            ReactionsEngine.updateNarrative(rep, recentPicks: allPickResults.filter { $0.isUserPick })
            pendingReactions.append(contentsOf: reactions)
            for r in reactions {
                let type: DraftEventType = {
                    switch r.actor {
                    case .owner:      return .ownerReaction
                    case .media:      return .mediaReaction
                    case .lockerRoom: return .lockerRoomReaction
                    case .fans:       return .fanReaction
                    }
                }()
                recordEvent(type: type, teamID: pick.currentTeamID, pickNumber: pick.pickNumber, round: pick.round)
            }
        }
        if !isUserPick {
            // AI picks only get a single media reaction when the value delta is dramatic.
            // We never apply these to the user's DraftReputation — they exist purely for
            // UI flavour so the news-ticker stays alive between user picks.
            let aiReactions = ReactionsEngine.reactions(to: result, isUserTeam: false)
            let mediaOnly = aiReactions.filter { $0.actor == .media }
            pendingReactions.append(contentsOf: mediaOnly)
        }

        // Drama events trigger banners / overlays in the UI.
        let drama = DraftDramaEngine.dramaEventsFor(
            result: result,
            currentRound: pick.round,
            previousRound: pick.round,
            picksUntilUserPick: picksUntilUserPick,
            isFinalPick: pick.pickNumber == picks.last?.pickNumber
        )
        pendingDrama.append(contentsOf: drama)

        // The board the user marked up months ago finally pays out tonight.
        //
        // `!ownerOverride` as well as `!isUserPick` (#207): an auto-pick is not
        // a user pick by the flag, but it IS the user's club walking to the
        // podium — firing the sniped sting there told him a rival had taken a
        // man his own war room had just drafted for him.
        if !isUserPick, !ownerOverride,
           let mark = DraftIntel.mark(for: prospect),
           let sting = DraftDramaEngine.targetSnipedBeat(
               playerName: Self.shortName(result.playerName),
               position: prospect.position.rawValue,
               teamAbbrev: result.teamAbbrev,
               isWantedTarget: mark.isBoardPositive
           ) {
            pendingDrama.append(sting)
        }
        announceMarkedTargetIfNeeded()

        try? modelContext.save()
        return true
    }

    /// "Your ELITE-marked target is still on the board, N picks to yours."
    ///
    /// Fires at most once per user turn: the watch window is six picks wide and
    /// the banner would otherwise repeat on every card inside it. Everything
    /// read here is the user's own mark plus the board he can already see —
    /// nothing new is persisted.
    private func announceMarkedTargetIfNeeded() {
        guard userTeamID != nil, let nextPickNumber = nextUserPickNumber else { return }
        guard !announcedTargetPickNumbers.contains(nextPickNumber) else { return }
        let away = picksUntilUserPick
        guard away > 0, away <= DraftDramaEngine.targetWatchDistance else { return }
        guard let target = DraftIntel.markedTargets(in: availableProspects, tier: .elite).first,
              let beat = DraftDramaEngine.targetOnTheBoardBeat(
                  playerName: "\(target.firstName.prefix(1)). \(target.lastName)",
                  position: target.position.rawValue,
                  picksUntilUserPick: away
              ) else { return }
        announcedTargetPickNumbers.insert(nextPickNumber)
        pendingDrama.append(beat)
    }

    /// Pick number of the user's next turn, or nil when he is out of picks.
    private var nextUserPickNumber: Int? {
        guard let teamID = userTeamID else { return nil }
        return picks
            .dropFirst(currentPickIndex)
            .first { $0.currentTeamID == teamID }?
            .pickNumber
    }

    /// Pick number of the turn AFTER the one on the clock — the slot a trade
    /// down is measured against, and the only pick availability means anything
    /// at while the user is picking. `nil` when this is his last.
    var pickNumberAfterCurrent: Int? {
        guard let teamID = userTeamID else { return nil }
        return picks
            .dropFirst(currentPickIndex + 1)
            .first { $0.currentTeamID == teamID }?
            .pickNumber
    }

    private func advance() {
        clockTask?.cancel()
        let previousRound = currentPick?.round ?? 1
        currentPickIndex += 1
        if currentPickIndex >= picks.count {
            completeDraft()
            return
        }
        let nextRound = currentPick?.round ?? 1
        if nextRound != previousRound {
            triggerRoundRecap(forRound: previousRound)
        }
        announceCurrentRoundIfNeeded()
        beginCurrentPick()
    }

    // MARK: - Draft completion + UDFA stage (R24)

    private func completeDraft() {
        clockTask?.cancel()
        pendingTradeOffer = nil
        isTradeUpBoardOpen = false
        tradeUpQuotes = []
        mode = .complete
        recordEvent(type: .draftCompleted)
        prepareUDFAStage()
    }

    /// Builds the undrafted pool from what's actually left on the board,
    /// sorted by the USER'S scouted grade (never the hidden OVR).
    private func prepareUDFAStage() {
        guard udfaPool.isEmpty else { return }
        udfaPool = availableProspects.sorted { a, b in
            let gradeA = a.effectiveOverallGrade?.midGrade.rank ?? 0
            let gradeB = b.effectiveOverallGrade?.midGrade.rank ?? 0
            if gradeA != gradeB { return gradeA > gradeB }
            return (publicBoardRanks[a.id] ?? 999) < (publicBoardRanks[b.id] ?? 999)
        }
    }

    /// Signs one UDFA to the user's team on a three-year minimum-tier deal,
    /// up to ``maxUDFASignings``.
    func signUDFA(_ prospect: CollegeProspect) {
        guard mode == .complete, !udfaStageFinished,
              let teamID = userTeamID,
              signedUDFAProspectIDs.count < maxUDFASignings,
              !signedUDFAProspectIDs.contains(prospect.id),
              udfaPool.contains(where: { $0.id == prospect.id }) else { return }

        let player = DraftEngine.convertUDFAToPlayer(
            prospect: prospect,
            teamID: teamID,
            salaryCap: teamsByID[teamID]?.salaryCap ?? ContractEngine.openingSalaryCap
        )
        let signingSchemes = schemesByTeam[teamID]
        DraftEngine.initializeRookieFamiliarity(
            player: player,
            prospect: prospect,
            offensiveScheme: signingSchemes?.offense,
            defensiveScheme: signingSchemes?.defense,
            isUndrafted: true
        )
        player.careerID = career.id
        modelContext.insert(player)
        rosters[teamID, default: []].append(player)
        signedUDFAProspectIDs.append(prospect.id)
        prospect.isDeclaringForDraft = false   // consumed from future UDFA pools
        if let team = teamsByID[teamID] {
            team.currentCapUsage += player.annualSalary
        }
        teamNeedScores = DraftIntel.teamNeedScores(roster: rosters[teamID] ?? [])
        try? modelContext.save()
    }

    /// Closes the **user's** draft-night window. It signs nobody else and it
    /// consumes nobody else.
    ///
    /// ## #208 G2 — this method was the reason the camp was empty
    ///
    /// It used to be the league's whole undrafted market: 31 AI clubs
    /// round-robined **ten men each** out of the remainder here, on draft night,
    /// and then the last loop cleared `isDeclaringForDraft` on **every**
    /// prospect still standing. Both halves are gone, and the second one is the
    /// load-bearing removal.
    ///
    /// `ScoutingEngine.udfaPoolMembers` — the single pool predicate — is
    /// `isDeclaringForDraft && mockDraftPickNumber == nil`. Clearing the flag on
    /// the whole remainder meant that by the time the advance left `.draft`,
    /// `UDFAMarketEngine.openMarket` found an empty pool and opened the market
    /// in its CLOSED state; `closeMarket` at the `.otas` exit then wrote
    /// `unsignedProspectIDs = []`; and `CampRosterEngine.fillCampRosters` — whose
    /// second source is exactly that survivor list
    /// (`UDFAMarketEngine.campInviteCandidates`) — was left with the free-agent
    /// pool alone. QA measured the consequence precisely: 32 clubs took ~3 men
    /// each out of a ~100-man pool, the user's roster peaked at 61, and the
    /// "Cut to 75" / "Cut to 65" rungs were satisfied on arrival.
    ///
    /// So the calendar now reads the way `OFFSEASON_ROSTER_PLAN.md` §1 states
    /// it: the user may sign up to ``maxUDFASignings`` on draft night, the rest
    /// of the class stays declared, `openMarket` seeds a live market at the
    /// `.draft` exit, the 31 clubs bid against him through `.otas`, and whoever
    /// is still unsigned when `closeMarket` runs becomes camp-invite inventory.
    /// One market, one pool predicate, one signing door.
    func finishUDFASigning() {
        guard mode == .complete, !udfaStageFinished else { return }
        udfaStageFinished = true

        let remaining = udfaPool.filter { !signedUDFAProspectIDs.contains($0.id) }
        WeekAdvancer.udfaStageCompletedSeasons.insert(career.currentSeason)
        udfaAISummary = "\(remaining.count) undrafted players go to the open market. "
            + "The league bids through OTAs."
        try? modelContext.save()
    }

    // MARK: - Reactions / Drama / Recap consumption

    /// UI calls this once it has shown the next pending reaction toast.
    func consumeOldestReaction() {
        guard !pendingReactions.isEmpty else { return }
        pendingReactions.removeFirst()
    }

    /// UI calls this once it has shown the next pending drama overlay.
    func consumeOldestDrama() {
        guard !pendingDrama.isEmpty else { return }
        pendingDrama.removeFirst()
    }

    /// UI calls this once the round recap card has been dismissed.
    func dismissRoundRecap() {
        pendingRoundRecap = nil
    }

    private func triggerRoundRecap(forRound round: Int) {
        guard let teamID = userTeamID, let rep = reputation else { return }
        // Build a synthetic "before" reputation from the snapshot so the
        // recap can compute meaningful round-over-round deltas.
        let beforeRep: DraftReputation? = {
            guard let snap = roundStartReputationSnapshot else { return nil }
            return DraftReputation(
                seasonYear: rep.seasonYear,
                careerID: rep.careerID,
                ownerTrust: snap.ownerTrust,
                fanMood: snap.fanMood,
                lockerRoomMood: snap.lockerRoomMood,
                mediaNarrative: snap.narrative
            )
        }()
        let recap = RoundRecapBuilder.build(
            round: round,
            // The builder's contract: "the caller should filter the global
            // stream by round before passing in". It never did, so "YOUR PICKS
            // THIS ROUND" grew every card the user had taken all night and
            // "Steal Of The Round" ranked the whole draft (task #153b).
            allPickResults: allPickResults.filter { $0.round == round },
            userTeamID: teamID,
            beforeReputation: beforeRep,
            afterReputation: rep
        )
        pendingRoundRecap = recap
        lastRoundShown = round
        // Reset snapshot for next round
        roundStartReputationSnapshot = ReputationSnapshot(
            ownerTrust: rep.ownerTrust,
            fanMood: rep.fanMood,
            lockerRoomMood: rep.lockerRoomMood,
            narrative: rep.mediaNarrative
        )
    }

    private func autoAdvanceUntil(_ predicate: (DraftDayCoordinator) -> Bool) {
        // Process AI picks immediately (no clock). Stop when predicate met or
        // user pick reached.
        var safety = 0
        while !predicate(self) && currentPickIndex < picks.count {
            safety += 1
            if safety > picks.count + 5 { break }
            guard let pick = currentPick else { break }
            if pick.currentTeamID == userTeamID { break }
            // Capture round before pick
            let roundBefore = pick.round
            announceCurrentRoundIfNeeded()

            // Wave 4 (plan finding S6): the trade rolls happen HERE too, before
            // the fast-forward consumes the pick. Skipping to your pick used to
            // bypass both the AI-vs-AI market and the incoming-offer window
            // entirely — i.e. the flagship draft-night moment never fired on the
            // only path anyone actually plays.
            considerAIvsAISwap()
            considerAITradeUpOffer()
            if pendingTradeOffer != nil {
                // A phone is ringing: stop the tape so it can be answered.
                break
            }

            recordEvent(
                type: .onTheClock,
                teamID: pick.currentTeamID,
                pickNumber: pick.pickNumber,
                round: pick.round
            )
            aiMakePickForCurrent()
            currentPickIndex += 1
            // Check round transition AFTER advancing — keeps round-recap firing
            // even when the user skips through AI picks.
            let roundAfter = currentPick?.round ?? roundBefore
            if roundAfter != roundBefore {
                triggerRoundRecap(forRound: roundBefore)
                // The recap is a stop point, exactly like a ringing phone above:
                // the fast-forward must not keep burning cards underneath a
                // modal the user is reading (task #153a).
                break
            }
        }
        if currentPickIndex >= picks.count {
            completeDraft()
            return
        }
        // Resume normal flow at the stop point
        announceCurrentRoundIfNeeded()
        beginCurrentPick()
    }

    private func announceCurrentRoundIfNeeded() {
        guard let pick = currentPick else { return }
        // Check whether the previous completed pick was in a different round.
        let prevRound: Int? = currentPickIndex == 0
            ? nil
            : picks[currentPickIndex - 1].round
        if prevRound != pick.round {
            recordEvent(type: .roundTransition, round: pick.round)
            appendStoryBeat(StoryBeat(
                kind: .round,
                pickNumber: pick.pickNumber,
                headline: "Round \(pick.round) is under way",
                detail: "\(availableProspects.count) names still on the board."
            ))
            // A new round is a new run: three straight receivers in round two
            // is not the same story as one card of it in round one.
            positionStreak = nil
            activeRunBeatID = nil
        }
    }

    // MARK: - Pick Grade

    private struct GradeBundle {
        let grade: PickGrade
        let inputs: PickGradeCalculator.Inputs
        let isGemCandidate: Bool
    }

    private func computePickGrade(pick: DraftPick, prospect: CollegeProspect) -> GradeBundle {
        // Value against the PUBLIC board, at the resolution the public board
        // actually has: a mock slot is graded to the pick, a projected round is
        // graded to the round. Subtracting a board rank from a pick number
        // treated "the media call him a fifth-rounder" as a slot-precise
        // opinion, so day-three cards drew STEAL / REACH chips off ±30 slots of
        // pure ordering noise.
        let valueDelta = DraftIntel.pickValueDelta(
            for: prospect,
            pickNumber: pick.pickNumber,
            consensusRank: publicBoardRanks[prospect.id]
        )

        let roster = rosters[pick.currentTeamID] ?? []
        let teamNeeds = DraftIntel.teamNeedScores(roster: roster)
        let needScore = teamNeeds[prospect.position] ?? 0.2

        // The public-facing OVR reflects the scouted consensus ("public
        // opinion"), never the hidden true overall — for a man nobody in your
        // building has filed on it falls back to the MEDIA band for his
        // projected round, not to `trueOverall`. `applyPreScoutedData` only runs
        // in season 1, so the old fallback fed the hidden rating into the pick
        // grade for most of the board from season 2 onward.
        let publicOVR = DraftIntel.publicOVREstimate(for: prospect)
        // #33 OSA B: score the prospect against the drafting team's coordinator
        // schemes (OC offense / DC defense) instead of a flat 0.6 constant, so
        // pick grades now differentiate by scheme fit. Falls back to a neutral
        // 0.5 when the team's coordinator/scheme is unknown.
        let schemes = schemesByTeam[pick.currentTeamID]
        let schemeFit = ProspectSchemeFitHelper.normalizedFit(
            prospect: prospect,
            offensiveScheme: schemes?.offense,
            defensiveScheme: schemes?.defense
        )

        let inputs = PickGradeCalculator.Inputs(
            valueDelta: valueDelta,
            needScore: needScore,
            publicOVR: publicOVR,
            schemeFit: schemeFit
        )
        let output = PickGradeCalculator.compute(inputs)
        return GradeBundle(
            grade: output.grade,
            inputs: inputs,
            isGemCandidate: output.isGemCandidate
        )
    }

    private func scoutGradeLabel(for prospect: CollegeProspect) -> String {
        // Stamped on completed picks (ticker + DraftPick.scoutGrade). Buckets the
        // PUBLIC number so the fog holds even post-pick — an unscouted steal
        // shouldn't reveal its true tier the moment another club drafts him,
        // which the old `?? trueOverall` fallback did on every unscouted man.
        switch DraftIntel.publicOVREstimate(for: prospect) {
        case 90...:   return "A+"
        case 84..<90: return "A"
        case 78..<84: return "B+"
        case 72..<78: return "B"
        case 66..<72: return "C+"
        case 60..<66: return "C"
        default:      return "D"
        }
    }

    // MARK: - Story feed

    /// Turns one finished card into the narrative beats the ticker renders, and
    /// persists the two `DraftEventType` cases that had never been written by
    /// anything (`bigDrop`, `positionRun`) so the saved story matches what the
    /// user watched. Everything here is read off values the pick already
    /// produced — no second opinion on the board, no new evaluation.
    /// How far off the public board a card has to land before the feed calls it
    /// a steal or a reach. Twelve slots is roughly a third of a round — below
    /// that, two boards ordering the same band differently explains the gap.
    private static let boardBeatSlots = 12

    private func recordStoryBeats(for result: PickResult, prospect: CollegeProspect, pick: DraftPick) {
        let name = Self.shortName(result.playerName)
        let boardRank = publicBoardRanks[prospect.id]
        // Where the PUBLIC CONSENSUS BOARD had him against where he actually
        // went: positive = he lasted past his slot, negative = he came off ahead
        // of it. One measure for both halves of the line (task #153e).
        //
        // The beats used to be gated on the pick GRADE and then print a board
        // rank, which are two different opinions of the same card:
        // `pickValueDelta` grades against the media's WINDOW (a mock slot, or
        // the whole round band the media claimed), the printed number is the
        // board's ordering inside that band. A round-1 card could therefore read
        // "REACH — consensus #163" purely because the AI's board and the media's
        // board sort a round band differently, which is drift, not a story. So
        // the beat now measures what it quotes, and only fires when the gap is
        // wide enough to be a genuine deviation rather than ranking noise.
        let boardDelta = boardRank.map { result.pickNumber - $0 }

        // 1) Value beats — the grade the pick was given, confirmed by the board.
        switch result.grade {
        case .stealAPlus, .hofTrack:
            if let boardRank, let boardDelta, boardDelta >= Self.boardBeatSlots {
                appendStoryBeat(StoryBeat(
                    kind: .steal,
                    pickNumber: result.pickNumber,
                    headline: "\(result.teamAbbrev) steal \(result.position.rawValue) \(name)",
                    detail: "Consensus board had him #\(boardRank); he lasted to #\(result.pickNumber) — \(boardDelta) slots of value."
                ))
            }
        case .reach, .bigReach:
            if let boardRank, let boardDelta, boardDelta <= -Self.boardBeatSlots {
                appendStoryBeat(StoryBeat(
                    kind: .reach,
                    pickNumber: result.pickNumber,
                    headline: "\(result.teamAbbrev) reach for \(result.position.rawValue) \(name)",
                    detail: "Consensus board had him #\(boardRank) — taken \(-boardDelta) slots ahead of it."
                ))
            }
        default:
            if result.isGem {
                appendStoryBeat(StoryBeat(
                    kind: .steal,
                    pickNumber: result.pickNumber,
                    headline: "\(result.teamAbbrev) may have found one in \(name)",
                    detail: "The room likes the value at #\(result.pickNumber)."
                ))
            }
        }

        // 2) The slide — past the slot the media gave him, by a margin.
        if result.isBigDrop {
            recordEvent(
                type: .bigDrop,
                teamID: pick.currentTeamID,
                pickNumber: pick.pickNumber,
                round: pick.round,
                prospectID: prospect.id
            )
            let slide = DraftIntel.slideMagnitude(
                for: prospect,
                pickNumber: result.pickNumber,
                consensusRank: boardRank
            )
            let expectation = prospect.mockDraftPickNumber.map { "The mock had him at #\(String($0))." }
                ?? prospect.draftProjection.map { "Media had him going in Round \($0)." }
                ?? "The room had him well ahead of this."
            appendStoryBeat(StoryBeat(
                kind: .slide,
                pickNumber: result.pickNumber,
                headline: "\(name)'s slide ends at #\(result.pickNumber)",
                detail: "\(expectation) He fell \(slide) picks past it — \(result.teamAbbrev) let him come to them."
            ))
        }

        // 3) The run — three straight cards at the same position. A run that
        //    keeps going updates its own line ("3 straight" → "4 straight")
        //    instead of stacking near-identical rows on top of each other.
        if let streak = positionStreak, streak.position == result.position {
            positionStreak = (result.position, streak.count + 1)
        } else {
            positionStreak = (result.position, 1)
            activeRunBeatID = nil
        }
        if let streak = positionStreak, streak.count >= 3 {
            recordEvent(
                type: .positionRun,
                teamID: pick.currentTeamID,
                pickNumber: pick.pickNumber,
                round: pick.round
            )
            let takers = allPickResults.suffix(streak.count).map(\.teamAbbrev).joined(separator: " · ")
            if let previous = activeRunBeatID {
                storyFeed.removeAll { $0.id == previous }
            }
            let beat = StoryBeat(
                kind: .run,
                pickNumber: result.pickNumber,
                headline: "Run on \(result.position.rawValue)s — \(streak.count) straight",
                detail: "\(takers). The position is drying up."
            )
            activeRunBeatID = beat.id
            appendStoryBeat(beat)
        }
    }

    /// "You are $3.4M over the cap" — the draft room's only money warning.
    ///
    /// Fires on the user's own picks, after the slot has been charged, and only
    /// while the club is actually in the red. Like the position-run beat it
    /// REWRITES its own line rather than stacking a new one per pick, so a class
    /// that keeps digging shows one row counting up instead of five near-copies.
    ///
    /// It reports what the CLASS cost separately from the club's cap position,
    /// because they are different numbers: a club that walked in $5M over and
    /// drafted a $3M class is $8M over, and blaming the class for all of it is
    /// a lie the user cannot check from this screen.
    ///
    /// Sandbox never charges the cap, so it never warns about it.
    ///
    /// The beat is filed under `.reach` on purpose. `StoryBeat.Kind` is a pure
    /// presentation token — its only consumer is `DraftTickerPanel.storyStyle`,
    /// where `.reach` IS the warning style (amber, `exclamationmark.triangle`),
    /// which is exactly the treatment this line wants. A dedicated case would
    /// mean editing that switch, which is outside this task's file set.
    private func announceCapRoomIfOver(teamID: UUID, pickNumber: Int) {
        guard career.capMode != .sandbox, let team = teamsByID[teamID] else { return }

        if let previous = activeCapWarningBeatID {
            storyFeed.removeAll { $0.id == previous }
            activeCapWarningBeatID = nil
        }

        let room = team.availableCap
        guard room < 0 else { return }

        let classShare = userClassCapCharge > 0
            ? " Your class accounts for \(DraftRecapView.formatCap(userClassCapCharge)) of the commitment."
            : ""
        let beat = StoryBeat(
            kind: .reach,
            pickNumber: pickNumber,
            headline: "You are \(DraftRecapView.formatCap(abs(room))) over the cap",
            detail: "Every slot is charged the moment the card goes in.\(classShare) Clear the room with cuts, restructures or a trade before the new league year."
        )
        activeCapWarningBeatID = beat.id
        appendStoryBeat(beat)
    }

    private func appendStoryBeat(_ beat: StoryBeat) {
        storyFeed.insert(beat, at: 0)
        if storyFeed.count > 40 { storyFeed.removeLast(storyFeed.count - 40) }
    }

    /// "Marcus Harlanson" → "M. Harlanson", so a beat headline fits one line.
    private static func shortName(_ fullName: String) -> String {
        let parts = fullName.split(separator: " ")
        guard parts.count >= 2, let initial = parts.first?.first else { return fullName }
        return "\(initial). \(parts.dropFirst().joined(separator: " "))"
    }

    // MARK: - Events

    private func recordEvent(
        type: DraftEventType,
        teamID: UUID? = nil,
        pickNumber: Int? = nil,
        round: Int? = nil,
        prospectID: UUID? = nil
    ) {
        sequenceCounter += 1
        let event = DraftEvent(
            draftYear: career.currentSeason,
            sequence: sequenceCounter,
            type: type,
            teamID: teamID,
            pickNumber: pickNumber,
            round: round,
            prospectID: prospectID
        )
        recorder.record(event)

        let planned = PlannedDraftEvent(
            sequence: sequenceCounter,
            type: type,
            teamID: teamID,
            pickNumber: pickNumber,
            round: round,
            prospectID: prospectID,
            metadata: .none
        )
        recentEvents.append(planned)
        if recentEvents.count > 50 {
            recentEvents.removeFirst(recentEvents.count - 50)
        }
    }
}

// MARK: - Pick Result

struct PickResult: Identifiable {
    let id = UUID()
    let pickNumber: Int
    let round: Int
    let teamAbbrev: String
    let playerName: String
    let position: Position
    let grade: PickGrade
    let isGem: Bool
    let isBigDrop: Bool
    let isUserPick: Bool
    /// **The clock filed this card, not the user** (#207).
    ///
    /// The old name for this flag was `ownerOverride`, which described the
    /// mechanism (the room picking on the owner's behalf) rather than the fact
    /// the user has to be told. It is written by exactly one path — the
    /// `forUser` branch of `tickClock` reaching zero — so `isUserPick` and
    /// `isAutoPick` are never both true, and every "my picks" filter in the
    /// room reads `isUserPick || isAutoPick`.
    let isAutoPick: Bool
    /// Portrait of the drafted prospect, carried so the War Room's "last pick"
    /// line can show a face without re-fetching the (already removed) prospect.
    /// `nil` is normal — it renders the placeholder silhouette.
    var faceID: String? = nil

    /// What the room knows about the *man*, as opposed to the *call* (#203).
    ///
    /// `nil` on any result built before this shipped and on the synthetic
    /// results a preview hands in; every renderer treats a missing dossier as
    /// "print the call and nothing else", never as an empty row.
    var dossier: Dossier? = nil
}

extension PickResult {

    /// The reveal card's payload: the four or five facts a broadcast puts on
    /// screen the second a name is read out, sampled at the podium because the
    /// prospect leaves `availableProspects` in the same breath.
    ///
    /// ## Fog discipline
    ///
    /// Nothing here is a number the user has not earned. `read` is
    /// `ProspectFog.read` — the identical band, with its identical
    /// `Source`, that the big board two columns to the left prints beside the
    /// same man, so the card cannot say more than the board already does.
    /// `userMark` and `userBoardRank` are the user's OWN annotations, which the
    /// fog never covered. `consensusRank`, the college and the age are public.
    /// `trueOverall` does not appear and must not be added.
    struct Dossier {
        let college: String
        let age: Int
        /// The user's own verdict on this man, months ago. The night the board
        /// pays out — or the night somebody else takes the name off it.
        let userMark: ProspectMarkTier
        /// His 1-based slot on the user's own board (`UserDraftBoard`), when the
        /// user ever gave him one.
        let userBoardRank: Int?
        /// His 1-based media-consensus slot.
        let consensusRank: Int?
        /// The fogged grade band — never the true overall.
        let read: ProspectFog.Read
        /// He plays one of the three loudest holes on the DRAFTING club's
        /// roster, measured before he was added to it.
        let fillsPickerNeed: Bool
    }
}
