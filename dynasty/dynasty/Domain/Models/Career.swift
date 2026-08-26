import Foundation
import SwiftData

@Model
final class Career {

    var id: UUID
    var playerName: String
    var avatarID: String
    var coachingStyle: CoachingStyle
    var role: CareerRole
    var capMode: CapMode
    var teamID: UUID?
    var leagueID: UUID?
    var reputation: Int
    var totalWins: Int
    var totalLosses: Int
    var playoffAppearances: Int
    var championships: Int
    var yearsFired: Int
    var currentSeason: Int
    var currentWeek: Int
    var currentPhase: SeasonPhase

    // MARK: - Legacy
    /// Tracks press conference promises, achievements, and media reputation.
    var legacy: LegacyTracker

    // MARK: - Coaching Tree
    /// Full history of coaches who have worked under this career.
    /// SwiftData encodes this Codable struct as a composite attribute automatically.
    var coachingTree: CoachingTreeData

    // MARK: - Intro & Goals

    /// Whether the new-career intro sequence has been completed.
    var hasCompletedIntro: Bool

    /// Season goals set by the owner during the intro sequence (or generated later).
    var seasonGoals: SeasonGoals?

    // MARK: - Depth Chart
    /// JSON-encoded `DepthChart` saved whenever the user edits or confirms the
    /// depth chart. `nil` until the user has set a chart at least once — the
    /// "Set depth chart" required task keys off this.
    var depthChartData: Data? = nil

    // MARK: - Game Plan
    /// JSON-encoded `GamePlan` saved whenever the user adjusts the Game Plan
    /// sliders or applies a preset. `nil` until the user has touched the plan
    /// at least once. Optional new attribute → safe lightweight migration.
    var gamePlanData: Data? = nil

    // MARK: - Free Agency State
    /// Current FA round: 0 = pre-FA, 1-6 = rounds (Day 1-3, Week 2-4).
    var freeAgencyRound: Int = 0
    /// Current sub-step within the FA phase (stored as raw value of FreeAgencyStep).
    var freeAgencyStep: String = FreeAgencyStep.finalPush.rawValue

    /// **The season whose league-year rollover has already been executed.**
    ///
    /// `FreeAgencyEngine.executeNewLeagueYear` is destructive and NOT idempotent
    /// — it decrements every contract in the league, grows every club's cap,
    /// expires a whole cohort into free agency and lets the AI re-sign its core.
    /// Its only guard used to be `NewLeagueYearView`'s `@State hasExecuted`,
    /// which dies with the view: backing out of the screen and re-entering it
    /// before pressing Continue ran the entire rollover a second time — a double
    /// decrement (every 1-year deal in the league gone), compounded cap growth, a
    /// second expiry wave and a second `resignAIOwnCore` pass.
    ///
    /// A `@State` flag cannot express "this already happened to the save", so the
    /// save carries it. `0` is "never" — every real season is positive, so a
    /// career created before this field existed runs its next rollover exactly
    /// once and stamps itself from then on.
    ///
    /// The value is `currentSeason` at the moment the rollover ran. That is the
    /// season just COMPLETED: `WeekAdvancer` does not increment the year until
    /// the roster-cuts → regular-season transition, so the identifier is stable
    /// across the whole offseason (`finalPush` → `newLeagueYear` → `capReview` →
    /// `signing` → draft → camp) and cannot collide with the next league year's.
    ///
    /// Inline default → SwiftData lightweight migration; never an init parameter.
    var lastRolloverSeason: Int = 0

    /// League year this save has already run the **bulk free-agent market** for.
    ///
    /// Task #93 F9 gave the bulk market three doors — `FAWeeklyView`'s Skip
    /// button, `WeekAdvancer`'s skipped-FA fallback and its unconditional
    /// mop-up — and the market is not idempotent: a second pass writes a second
    /// wave of contracts against the same calibration, spends cap twice and
    /// double-counts `signingLedger`. The stamp is what keeps the three doors
    /// opening one market.
    ///
    /// It lives HERE and not in a static dictionary because the state it guards
    /// against is persisted: Skip stamps `freeAgencyStep = .complete`, the user
    /// quits, and on relaunch Advance Week reaches the mop-up with an empty
    /// in-memory table and runs the whole market a second time in the same
    /// league year. Exactly the failure ``lastRolloverSeason`` exists for, so it
    /// uses exactly the same shape: `currentSeason` at the moment the market
    /// ran, `0` for "never".
    ///
    /// Inline default → SwiftData lightweight migration; never an init parameter.
    var lastBulkMarketSeason: Int = 0

    // MARK: - FA Visits (R23)
    /// Number of free-agent facility visits hosted this FA phase (max 3).
    /// Reset when the free agency phase begins. Default value → lightweight migration.
    var faVisitsUsed: Int = 0

    // MARK: - Scouting Counters
    /// Number of combine interviews conducted this year (max 60).
    var interviewsUsed: Int = 0
    /// Number of personal workouts conducted this year (max 30).
    var workoutsUsed: Int = 0
    /// Number of pre-draft Top-30 visits used this year (max 30).
    var top30VisitsUsed: Int = 0

    // MARK: - Draft Prep State (#103)

    /// Current stage of the pre-draft pipeline, stored as the raw value of
    /// ``DraftPrepStep``. **Read it through ``prepStep``**, which applies the
    /// cycle stamp and the phase floor; this is the storage, not the API.
    ///
    /// Inline default → SwiftData lightweight migration; never an init parameter.
    var draftPrepStep: String = DraftPrepStep.combineReview.rawValue

    /// Cycle stamp for ``draftPrepStep``.
    ///
    /// A step written in an earlier draft cycle reads as `.combineReview`, so
    /// the pipeline resets with the class **without needing a reset hook in
    /// `WeekAdvancer`** — the same trick `ScoutEvaluationBudget.thisCycle` uses
    /// for the evaluation slots, and the same shape as ``lastRolloverSeason``.
    /// `0` is "never stamped".
    var draftPrepStepSeason: Int = 0

    /// JSON-encoded mock-draft history (`[label: [MockDraftPick]]`).
    ///
    /// `WeekAdvancer.mockDraftHistory` is a process static that is wiped on
    /// relaunch, so the "Mock 1.0 vs Final" comparison the data is shaped for
    /// cannot survive a cold launch. Persisting it here is what makes the two
    /// mock-draft events comparable after the app has been quit.
    /// Optional attribute → safe lightweight migration.
    var mockDraftHistoryData: Data? = nil

    // MARK: - Owner Demands (#248)
    /// Roster demands set by the owner during the review roster phase.
    /// Each string is a demand like "Upgrade QB starter" or "Improve the defense".
    var ownerDemands: [String] = []
    /// Demands that the player has addressed (e.g. signed/drafted at that position).
    var ownerDemandsAddressed: [String] = []

    // MARK: - HC-GM Relationship
    /// Persisted relationship state between the GM and their Head Coach.
    /// Only meaningful when `role == .gm`; ignored for `.gmAndHeadCoach` careers.
    var hcGMRelationship: CoachRelationshipEngine.HCGMRelationship

    // MARK: - Pending Trade Offers (R21)
    /// JSON-encoded `[TradeProposal]` of AI-initiated trade offers awaiting the
    /// user's decision. Populated by WeekAdvancer during the regular season,
    /// consumed by the Trade Center, cleared at the trade deadline and at the
    /// start of every new season. Optional new attribute → lightweight migration.
    var pendingTradeOffersData: Data? = nil

    // MARK: - Trade Negotiation Threads (Wave 3)
    /// JSON-encoded `[TradeNegotiationThread]` — live conversations with AI GMs,
    /// newest first, capped at 12. An offer can sit on a desk for weeks, so the
    /// transcript, the round count and the package on the table all have to
    /// outlive the view (plan §6 Wave 3.2). Same inline-default pattern as
    /// `pendingTradeOffersData` → lightweight migration.
    var tradeThreadsData: Data? = nil

    // MARK: - Inbox (Wave 3)
    /// JSON-encoded `[InboxMessage]`, oldest first, capped at 200.
    ///
    /// The inbox used to be `@State` on `CareerShellView`, which meant every
    /// message died with the view: a draft-day trade notice generated inside the
    /// draft-room modal was gone before the shell ever read it (task #19), and
    /// closing the career threw away the whole mailbox. `WeekAdvancer` still
    /// publishes through `lastInboxMessages`; the shell drains that channel and
    /// writes the result here. Optional new attribute → lightweight migration.
    var inboxData: Data? = nil

    // MARK: - UDFA Market (#204)
    /// JSON-encoded `UDFAMarketState` — the undrafted free-agent market for the
    /// CURRENT season: its round, the standing offers and the signings already
    /// struck. Seeded on the `.draft` exit, settled on the `.otas` exit; a blob
    /// stamped with an older season reads as "no market yet" and is re-seeded.
    /// The market touches this one property and nothing else in the model.
    /// Optional new attribute → lightweight migration.
    var udfaMarketData: Data? = nil

    // MARK: - Camp Roster (#205a)
    /// The season whose camp rosters have already been assembled
    /// (`CampRosterEngine.fillCampRosters`, `OFFSEASON_ROSTER_PLAN.md` §3.3).
    ///
    /// The idempotency stamp for the camp-invite wave, in the same shape as
    /// ``lastRolloverSeason`` and ``lastBulkMarketSeason``: `currentSeason` at
    /// the moment the camps were filled, `0` for "never". It is PERSISTED for
    /// the reason those two are — the `.otas` exit is reachable again after a
    /// quit and relaunch, and a process-global set (the shape the deleted UDFA
    /// bulk block used) does not survive a cold launch, so the fill would run a
    /// second time and put every club at its target again on top of whatever
    /// the user had already cut.
    ///
    /// Inline default → SwiftData lightweight migration; never an init parameter.
    var campFillSeason: Int = 0

    // MARK: - Fan support
    /// The city's read on the front office, 0…100, neutral at 50.
    ///
    /// The home the podium's FANS number never had. `PressEffects.fanExcitement`
    /// was the second-biggest number on the press screen and was written
    /// nowhere at all — a meter the user was asked to play against and that no
    /// state ever held. It moves through
    /// ``PressConferenceEngine/applyRoomEffects(result:career:roster:)`` and is
    /// read by the hub's TEAM card.
    ///
    /// Inline default → SwiftData lightweight migration; never an init parameter.
    /// An old save opens at the neutral 50 rather than at 0, which would read as
    /// a city that had already given up on a coach it has never seen speak.
    var fanSupport: Int = 50

    // MARK: - Development Reports (R26)
    /// JSON-encoded `[DevelopmentReport]` — weekly development digests for
    /// the user's team, newest first, capped at 10.
    /// Optional new attribute → lightweight migration.
    var developmentReportLogData: Data? = nil

    // MARK: - Injury Return Decisions (R28)
    /// JSON-encoded `[ReturnDecision]` — user-team players in their final
    /// rehab week awaiting a "rush back vs. hold out" call. Ignoring an entry
    /// is always safe (normal recovery). Optional attribute → light migration.
    var pendingReturnDecisionsData: Data? = nil

    // MARK: - League Narrative (R29)
    /// JSON-encoded `[NewsItem]` — the persisted news feed, newest first,
    /// capped at 150. Written by WeekAdvancer after every advance so the News
    /// screen survives app restarts. Optional attribute → light migration.
    var newsLogData: Data? = nil

    /// JSON-encoded `[String]` — the career-milestone crossings already
    /// announced THIS season (#154a).
    ///
    /// Milestone stories used to be a single week-18 batch because the only
    /// source of career totals was `PlayerSeasonHistory`, which is written once
    /// a year. They now also fire the week a total is crossed, for the players
    /// whose games actually produce a box score, and this is the ledger that
    /// stops the week-18 pass saying the same thing a second time. Cleared by
    /// `startNewSeason`. Optional attribute → light migration.
    var announcedMilestoneKeysData: Data? = nil
    /// JSON-encoded `LeagueNarrativeState` — power rankings (with last week's
    /// order for movement arrows), MVP race, and anti-repeat story markers.
    /// Optional new attribute → lightweight migration.
    var leagueNarrativeData: Data? = nil

    // MARK: - Coaching Carousel (R30)
    /// JSON-encoded `[CoachCarouselEngine.CarouselMove]` — this offseason's
    /// coaching carousel feed (firings, HC hires, coordinator chain moves),
    /// newest first, capped at 40. Reset each `.coachingChanges` phase.
    /// Optional new attribute → lightweight migration.
    var coachCarouselLogData: Data? = nil
    /// JSON-encoded `CoachCarouselEngine.CoordinatorInterviewRequest` — an AI
    /// team's pending request to interview one of the user's coordinators for
    /// a head-coach vacancy. `nil` when nothing is pending; expires at the
    /// Combine if ignored. Optional new attribute → lightweight migration.
    var pendingInterviewRequestData: Data? = nil

    // MARK: - Owner & Economy 2.0 (R31)
    /// JSON-encoded `[SeasonGoal]` — the owner's tracked goals for the current
    /// season. Generated at every season start (owner kickoff meeting) and
    /// snapshotted with final progress at the end-of-season review.
    /// Optional new attribute → lightweight migration.
    var ownerSeasonGoalsData: Data? = nil
    /// JSON-encoded `[OwnerPersonaEngine.OwnerWhim]` — meddling-owner
    /// "suggestions" issued during the season and the user's responses.
    /// Optional new attribute → lightweight migration.
    var ownerWhimsData: Data? = nil
    /// JSON-encoded `OwnerPersonaEngine.OwnerSeasonReview` — the most recent
    /// end-of-season owner evaluation (verdict + consequences).
    /// Optional new attribute → lightweight migration.
    var ownerSeasonReviewData: Data? = nil
    /// R31: set when the owner fires the coach — the career is over and the
    /// shell shows the final summary screen. Default → lightweight migration.
    var isGameOver: Bool = false

    // MARK: - Press Conference (#161)
    /// JSON-encoded `[ResponseTone.RawValue]` — the coach's recent press-room
    /// tones, NEWEST FIRST, capped at `PressConferenceEngine.toneLedgerDepth`.
    /// Drives the repetition ratchet: a coach who answers everything the same
    /// way watches the payoff decay and eventually earns a "vanilla" label.
    /// Optional new attribute → lightweight migration.
    var pressToneHistoryData: Data? = nil
    /// JSON-encoded `[PressConferenceEngine.PressPromiseRecord]` — measurable
    /// claims made at a podium and their settlement, capped at 40. Settled once
    /// a season in `WeekAdvancer.recordSeasonSummary`.
    /// Optional new attribute → lightweight migration.
    var pressPromiseLedgerData: Data? = nil

    // MARK: - League History & Hall of Fame (R32)
    /// JSON-encoded `[SeasonSummary]` — one entry per completed season,
    /// newest first, capped at 20. Written during the `.superBowl` phase.
    /// Optional new attribute → lightweight migration.
    var leagueHistoryData: Data? = nil
    /// JSON-encoded `[HallOfFameEntry]` — retired legends inducted into the
    /// Hall of Fame, newest induction class first, capped at 80.
    /// Optional new attribute → lightweight migration.
    var hallOfFameData: Data? = nil

    // MARK: - Game Modes & League Settings (R40)
    /// Raw `CareerGameMode` — how this career's league was bootstrapped
    /// (standard rosters or a full fantasy draft). Default → light migration.
    var gameModeRaw: String = CareerGameMode.standard.rawValue
    /// Raw `CareerScenario` when the career was started from a scenario card
    /// (Rebuild / Win Now / Cap Hell). `nil` = plain start.
    /// Optional new attribute → lightweight migration.
    var scenarioRaw: String? = nil
    /// Raw `InjuryFrequency` league setting. Consumed by WeekAdvancer's
    /// weekly injury pass as a multiplier on `MedicalEngine.injuryCheck`.
    /// Default → lightweight migration (normal = today's exact rates).
    var injuryFrequencyRaw: String = InjuryFrequency.normal.rawValue

    // MARK: - League Source (realistic-league phase 3)
    /// Raw `LeagueSource` — which league this career was built from: the random
    /// generator or one of the fixed 2026 templates. Provenance only: the whole
    /// league graph is persisted at career creation, so nothing is ever
    /// re-imported or re-rolled on a later launch.
    /// Default → lightweight migration (existing careers were all generated).
    var leagueSourceRaw: String = LeagueSource.generated.rawValue

    // MARK: - Training-Focus Breakout Cap (R26 jämä)
    /// JSON-encoded `TrainingFocusEngine.SeasonBreakoutCounts` — how many
    /// training-focus breakout events each team has consumed in the CURRENT
    /// season (hard cap 2/team/season). The payload is season-scoped: when
    /// its stored season differs from the season being played, the engine
    /// ignores and overwrites it, so a new season starts from zero without
    /// an explicit `startNewSeason` hook.
    /// Optional new attribute → lightweight migration.
    var breakoutCountsData: Data? = nil

    // MARK: - Weekly Practice Play (R36)
    /// Raw `OffensivePlayCall` the team drills in practice this week. After
    /// enough practice weeks the play installs into the call sheet for the
    /// season. `nil` = nothing queued. Optional attribute → light migration.
    var weeklyPracticePlayRaw: String? = nil
    /// Practice weeks already banked on `weeklyPracticePlayRaw` (an expert OC
    /// installs in 1 week, otherwise 2). Default → lightweight migration.
    var weeklyPracticeWeeksDone: Int = 0
    /// Raw `OffensivePlayCall` values installed through practice — valid for
    /// `bonusInstalledSeason` only. Default → lightweight migration.
    var bonusInstalledPlaysRaw: [String] = []
    /// The season `bonusInstalledPlaysRaw` belongs to; a new season starts
    /// from an empty practiced playbook. Default → lightweight migration.
    var bonusInstalledSeason: Int = 0

    // MARK: - Face Library (phase 4)
    /// JSON-encoded `FaceAssignmentRegistry` — which library face each person
    /// in THIS career wears, plus the retirement cooldown that keeps a freed
    /// face out of circulation for two seasons. Career-scoped on purpose: two
    /// careers may hand the same face to different people.
    /// Optional new attribute → lightweight migration.
    var faceRegistryData: Data? = nil

    // MARK: - Locker Room (R25)
    /// JSON-encoded `[LockerRoomEvent]` — resolved locker-room happenings,
    /// newest first, capped at 12. Optional new attribute → lightweight migration.
    var lockerRoomLogData: Data? = nil
    /// JSON-encoded `LockerRoomEvent` awaiting the coach's response
    /// (intervene / let it play out). `nil` when nothing is pending.
    /// Optional new attribute → lightweight migration.
    var pendingLockerRoomEventData: Data? = nil

    // MARK: - Preseason (#205b)
    /// JSON-encoded `PreseasonState` — the whole three-game exhibition slate in
    /// one blob rather than as `Game` rows (see `PreseasonState`'s header for
    /// why). `nil` outside the phase and before the slate is drawn.
    /// Optional new attribute → lightweight migration.
    var preseasonData: Data? = nil

    // MARK: - Multi-save isolation (careerID wave)
    /// How far this save has been through the `careerID` adoption pass.
    /// `0` = never adopted (a legacy save whose rows still carry
    /// `careerID == nil`); `1` = every row in the store that belongs to this
    /// save has been stamped. Default-value stored property, never in `init`
    /// → safe lightweight migration.
    var schemaBackfillVersion: Int = 0

    var winPercentage: Double {
        let totalGames = totalWins + totalLosses
        guard totalGames > 0 else { return 0.0 }
        return Double(totalWins) / Double(totalGames)
    }

    init(
        playerName: String,
        // The first of the 20 AI headshots (`ExtrasCatalog`). Literal rather
        // than `UserPortrait.fallbackID` to keep the model free of the view
        // layer; every read goes through `UserPortrait.resolve`, which maps any
        // legacy `coach_*` value from an older save onto a photograph too.
        avatarID: String = "avatar_00000",
        coachingStyle: CoachingStyle = .tactician,
        role: CareerRole,
        capMode: CapMode,
        currentSeason: Int = 2026
    ) {
        self.id = UUID()
        self.playerName = playerName
        self.avatarID = avatarID
        self.coachingStyle = coachingStyle
        self.role = role
        self.capMode = capMode
        self.teamID = nil
        self.leagueID = nil
        self.reputation = 50
        self.totalWins = 0
        self.totalLosses = 0
        self.playoffAppearances = 0
        self.championships = 0
        self.yearsFired = 0
        self.currentSeason = currentSeason
        self.currentWeek = 0
        self.currentPhase = .coachingChanges
        self.hasCompletedIntro = false
        self.seasonGoals = nil
        self.legacy = LegacyTracker()
        self.coachingTree = CoachingTreeData()
        self.hcGMRelationship = CoachRelationshipEngine.HCGMRelationship()
    }
}

// MARK: - Draft Prep Stage Bridge (#103)

extension Career {

    /// Where this club is in the pre-draft pipeline.
    ///
    /// **The only supported way to read or write the stage.** Two rules are
    /// baked in here so no call site can forget either of them:
    ///
    /// 1. **Cycle stamp.** Writing stamps `draftPrepStepSeason` with the current
    ///    season, and reading a step stamped in an earlier cycle yields
    ///    `.combineReview`. The pipeline therefore resets with the draft class
    ///    on its own — there is no reset hook anywhere, and there must not be.
    /// 2. **Phase floor.** The stored step is raised to
    ///    ``SeasonPhase/minimumPrepStep``, so a save that predates the field (or
    ///    one that skipped straight through the combine) cannot sit in
    ///    `.proDays` with the pro-day stage locked behind it.
    /// 3. **Evidence floor (#104).** The stored step is also raised to whatever
    ///    the club has demonstrably already DONE — see ``derivedPrepStepFloor``.
    ///    The phase floor alone was too coarse for the save the bug report came
    ///    from: a career created before the stage machine existed carries
    ///    `draftPrepStepSeason == 0`, so every stage it had actually worked read
    ///    as `.combineReview` and the whole pipeline replayed from the top —
    ///    except in `.proDays`, where the phase floor jumped it straight to
    ///    `.proDayFocus` and the two combine stages it skipped were reported as
    ///    "the department has moved on".
    var prepStep: DraftPrepStep {
        get {
            let stored = draftPrepStepSeason == currentSeason
                ? DraftPrepStep(rawValue: draftPrepStep) ?? .combineReview
                : .combineReview
            let phaseFloor = currentPhase.minimumPrepStep
            let evidence = derivedPrepStepFloor
            let floor = phaseFloor.order >= evidence.order ? phaseFloor : evidence
            return stored.order >= floor.order ? stored : floor
        }
        set {
            draftPrepStep = newValue.rawValue
            draftPrepStepSeason = currentSeason
        }
    }

    /// The stage this club's own ledgers prove it has already reached.
    ///
    /// **Self-healing migration.** Nothing about the stored step is trusted: the
    /// per-cycle counters (`interviewsUsed`, `workoutsUsed`, `top30VisitsUsed`,
    /// the evaluation ledger, the two mock stamps) are written by the actions
    /// themselves, so they are the truth about where the club stands whether or
    /// not the stage string ever got written. A save from before #103, a save
    /// whose stamp is a cycle old, and a save whose stage string was written
    /// under the v1 case order all land in the same place: on the last stage
    /// they can prove they worked.
    ///
    /// Three rules keep this honest:
    ///
    /// * **It only ever raises.** It is a floor, never a clamp — a club that
    ///   walked the stages forward without spending anything keeps its place.
    /// * **It never runs ahead of the season** (``SeasonPhase/maximumPrepStep``).
    ///   The counters are zeroed at kickoff, not at each phase, so in February a
    ///   club still carries last spring's workouts; without the ceiling that
    ///   would derive a combine-week club into the pro-day stages.
    /// * **It only reads the OPEN career's scoped defaults.** `CareerScopedDefaults`
    ///   resolves its keys against `WeekAdvancer.activeCareerID`, so for any
    ///   other `Career` row (the save list, a preview) the default-backed
    ///   evidence is another save's and is skipped. The SwiftData counters on
    ///   `self` are always safe and are read either way.
    var derivedPrepStepFloor: DraftPrepStep {
        var floor = DraftPrepStep.combineReview
        func raise(_ step: DraftPrepStep) {
            if step.order > floor.order { floor = step }
        }

        // Counters that live on this row — always this career's.
        if interviewsUsed > 0    { raise(.interviews) }
        if workoutsUsed > 0      { raise(.workouts) }
        if top30VisitsUsed > 0   { raise(.top30Visits) }

        // Ledgers that live in the scoped defaults — only for the open save.
        //
        // **Film reports are deliberately NOT evidence.** They spend
        // `ScoutEvaluationBudget` slots, and that button is not part of the
        // pipeline: `ProspectDetailView` offers it from `.coachingChanges`
        // onward and the plain Big Board routes into the same sheet. One $20K
        // evaluation bought off the reference board in combine week would
        // otherwise derive the club into `.filmStudy` — stepping over
        // `.combineReview` and `.interviews`, both of which then draw as passed
        // while their required tasks are still red in the left bar. The stage's
        // own satisfaction still reads the ledger (`DraftPrepProgress`), so a
        // club that has genuinely filed its reports still finds the stage
        // ticked and its successor open; it just does not get *moved* by a
        // purchase made outside the process.
        if WeekAdvancer.activeCareerID == id {
            let mockOne: Int? = CareerScopedDefaults.value(DraftPrepProgress.Key.mockOneRead)
            if mockOne == currentSeason { raise(.mockOne) }
            let mockTwo: Int? = CareerScopedDefaults.value(DraftPrepProgress.Key.mockTwoRead)
            if mockTwo == currentSeason { raise(.mockTwo) }
        }

        let ceiling = currentPhase.maximumPrepStep
        return floor.order <= ceiling.order ? floor : ceiling
    }

    /// Raises the prep stage to `step` if the club is behind it, and re-stamps
    /// the cycle either way.
    ///
    /// Never lowers the stage: a club that worked its way to the final mock does
    /// not get pulled back to `.proDayFocus` by the phase boundary that carries
    /// the slow ones forward. The unconditional re-stamp is the point of the
    /// "either way" — it persists what the phase floor was already returning, so
    /// an in-flight save stops relying on the floor the first time it crosses a
    /// boundary. (Caller saves the context.)
    func advancePrepStep(to step: DraftPrepStep) {
        prepStep = prepStep.order >= step.order ? prepStep : step
    }
}

// MARK: - Game Modes & League Settings Bridge (R40)

extension Career {

    /// Typed accessor for the career's game mode. Unknown raw values (from
    /// future versions) fall back to `.standard`.
    var gameMode: CareerGameMode {
        get { CareerGameMode(rawValue: gameModeRaw) ?? .standard }
        set { gameModeRaw = newValue.rawValue }
    }

    /// Typed accessor for the scenario this career started from, if any.
    var scenario: CareerScenario? {
        get { scenarioRaw.flatMap { CareerScenario(rawValue: $0) } }
        set { scenarioRaw = newValue?.rawValue }
    }

    /// Typed accessor for the league's injury-frequency setting.
    var injuryFrequency: InjuryFrequency {
        get { InjuryFrequency(rawValue: injuryFrequencyRaw) ?? .normal }
        set { injuryFrequencyRaw = newValue.rawValue }
    }

    /// Typed accessor for the league source this career was built from.
    /// Unknown raw values (a Release build reading a DEBUG save) fall back to
    /// `.generated`; the persisted league itself is unaffected either way.
    var leagueSource: LeagueSource {
        get { LeagueSource(rawValue: leagueSourceRaw) ?? .generated }
        set { leagueSourceRaw = newValue.rawValue }
    }
}

// MARK: - Game Plan Codable Bridge

extension Career {

    /// The user's saved game plan, JSON-decoded from `gamePlanData`.
    /// Reading falls back to `.balanced` when nothing has been saved yet;
    /// writing encodes and stores the new plan (caller saves the context).
    var gamePlan: GamePlan {
        get {
            guard let data = gamePlanData,
                  let plan = try? JSONDecoder().decode(GamePlan.self, from: data) else {
                return .balanced
            }
            return plan
        }
        set {
            gamePlanData = try? JSONEncoder().encode(newValue)
        }
    }

    /// The saved plan, or `nil` when the user has never set one. Simulation
    /// call sites use this so an untouched career keeps today's exact AI
    /// play-calling behavior (`nil` game plan = no bias).
    var savedGamePlan: GamePlan? {
        gamePlanData == nil ? nil : gamePlan
    }
}

// MARK: - Pending Trade Offers Codable Bridge

extension Career {

    /// AI-initiated trade offers awaiting the user's decision, JSON-decoded
    /// from `pendingTradeOffersData`. Writing encodes and stores the new list
    /// (caller saves the context).
    var pendingTradeOffers: [TradeProposal] {
        get {
            guard let data = pendingTradeOffersData,
                  let offers = try? JSONDecoder().decode([TradeProposal].self, from: data) else {
                return []
            }
            return offers
        }
        set {
            pendingTradeOffersData = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - Trade Negotiation Threads Codable Bridge (Wave 3)

extension Career {

    /// Live and recently-closed trade conversations, newest first (max 12).
    /// Writing encodes and stores the trimmed list (caller saves the context).
    var tradeThreads: [TradeNegotiationThread] {
        get {
            guard let data = tradeThreadsData,
                  let threads = try? JSONDecoder().decode([TradeNegotiationThread].self, from: data) else {
                return []
            }
            return threads
        }
        set {
            tradeThreadsData = try? JSONEncoder().encode(Array(newValue.prefix(12)))
        }
    }

    /// Inserts or replaces one thread, keeping the list newest-first.
    /// Caller saves the context.
    func upsertTradeThread(_ thread: TradeNegotiationThread) {
        var threads = tradeThreads.filter { $0.id != thread.id }
        threads.insert(thread, at: 0)
        tradeThreads = threads
    }
}

// MARK: - Inbox Codable Bridge (Wave 3)

extension Career {

    /// The coach's mailbox, OLDEST FIRST (max 200) — the order
    /// `WeekAdvancer.lastInboxMessages` appends in and `InboxView` reverses for
    /// display. Trimming from the front keeps the newest 200 (caller saves the
    /// context).
    var inbox: [InboxMessage] {
        get {
            guard let data = inboxData,
                  let messages = try? JSONDecoder().decode([InboxMessage].self, from: data) else {
                return []
            }
            return messages
        }
        set {
            inboxData = try? JSONEncoder().encode(Array(newValue.suffix(200)))
        }
    }
}

// MARK: - Development Reports Codable Bridge (R26)

extension Career {

    /// Weekly development digests, newest first (max 10). Writing encodes
    /// and stores the trimmed list (caller saves the context).
    var developmentReports: [DevelopmentReport] {
        get {
            guard let data = developmentReportLogData,
                  let reports = try? JSONDecoder().decode([DevelopmentReport].self, from: data) else {
                return []
            }
            return reports
        }
        set {
            developmentReportLogData = try? JSONEncoder().encode(Array(newValue.prefix(10)))
        }
    }
}

// MARK: - Return Decisions Codable Bridge (R28)

extension Career {

    /// Pending "rush back vs. hold out" decisions for user-team players in
    /// their final rehab week. Writing encodes and stores the new list
    /// (caller saves the context).
    var pendingReturnDecisions: [ReturnDecision] {
        get {
            guard let data = pendingReturnDecisionsData,
                  let decisions = try? JSONDecoder().decode([ReturnDecision].self, from: data) else {
                return []
            }
            return decisions
        }
        set {
            pendingReturnDecisionsData = try? JSONEncoder().encode(newValue)
        }
    }
}

// MARK: - League Narrative Codable Bridge (R29)

extension Career {

    /// Persisted news feed, newest first (max 150). Writing encodes and
    /// stores the trimmed list (caller saves the context).
    ///
    /// ## Prefer ``postNews(_:)-(NewsItem)`` over touching this directly
    ///
    /// The setter truncates with `prefix(150)`, and the list is NEWEST-FIRST.
    /// Those two facts together make `newsLog.append(item)` a silent no-op on
    /// any established career: the item is placed at index 150+ and encoded
    /// away in the same statement. That is F-49(1) — the headline announcing
    /// the user's own holding-out star being force-traded was written and
    /// discarded, every time, for as long as the career was old enough to
    /// matter. It fails silently and only on old saves, which is the worst
    /// combination a bug can have.
    var newsLog: [NewsItem] {
        get {
            guard let data = newsLogData,
                  let items = try? JSONDecoder().decode([NewsItem].self, from: data) else {
                return []
            }
            return items
        }
        set {
            newsLogData = try? JSONEncoder().encode(Array(newValue.prefix(150)))
        }
    }

    /// Publishes a headline to the persisted feed, newest first.
    ///
    /// **The only correct way to add to `newsLog`.** Exists so that no caller
    /// has to remember the ordering or the truncation — see the note on
    /// `newsLog` for what forgetting them costs. Caller still saves the context.
    func postNews(_ item: NewsItem) {
        postNews([item])
    }

    /// Publishes several headlines at once, keeping the order they were
    /// produced in, all of them ahead of what the feed already holds.
    func postNews(_ items: [NewsItem]) {
        guard !items.isEmpty else { return }
        newsLog = items + newsLog
    }

    /// Milestone crossings already announced this season (#154a).
    ///
    /// One key per `player | category | rung`, so a crossing announced in week 6
    /// is not repeated by the week-18 sweep. Reset every league year by
    /// `WeekAdvancer.startNewSeason`; capped defensively at 500.
    var announcedMilestoneKeys: Set<String> {
        get {
            guard let data = announcedMilestoneKeysData,
                  let keys = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(keys)
        }
        set {
            announcedMilestoneKeysData = try? JSONEncoder().encode(Array(newValue.prefix(500)))
        }
    }

    /// The coach's recent press-room tones, NEWEST FIRST (#161).
    ///
    /// Career-scoped and deliberately NOT reset at the season rollover — "he
    /// has said the same thing at every podium since he got here" is a fair
    /// thing for a beat writer to notice across a January.
    var pressToneHistory: [ResponseTone] {
        get {
            guard let data = pressToneHistoryData,
                  let raw = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return raw.compactMap(ResponseTone.init(rawValue:))
        }
        set {
            let capped = Array(newValue.prefix(PressConferenceEngine.toneLedgerDepth))
            pressToneHistoryData = try? JSONEncoder().encode(capped.map(\.rawValue))
        }
    }

    /// Measurable promises made at a podium, oldest first (#161).
    var pressPromiseLedger: [PressConferenceEngine.PressPromiseRecord] {
        get {
            guard let data = pressPromiseLedgerData,
                  let records = try? JSONDecoder().decode(
                      [PressConferenceEngine.PressPromiseRecord].self, from: data
                  ) else {
                return []
            }
            return records
        }
        set {
            pressPromiseLedgerData = try? JSONEncoder().encode(Array(newValue.suffix(40)))
        }
    }

    /// League narrative storyline state (power rankings, MVP race, story
    /// markers). `nil` until the first regular-season week has been played.
    var leagueNarrative: LeagueNarrativeState? {
        get {
            guard let data = leagueNarrativeData else { return nil }
            return try? JSONDecoder().decode(LeagueNarrativeState.self, from: data)
        }
        set {
            leagueNarrativeData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }
}

// MARK: - Coaching Carousel Codable Bridge (R30)

extension Career {

    /// This offseason's coaching carousel feed, newest first (max 40).
    /// Writing encodes and stores the trimmed list (caller saves the context).
    var coachCarouselLog: [CoachCarouselEngine.CarouselMove] {
        get {
            guard let data = coachCarouselLogData,
                  let moves = try? JSONDecoder().decode([CoachCarouselEngine.CarouselMove].self, from: data) else {
                return []
            }
            return moves
        }
        set {
            coachCarouselLogData = try? JSONEncoder().encode(Array(newValue.prefix(40)))
        }
    }

    /// The pending interview request for one of the user's coordinators.
    /// Assigning `nil` clears it (caller saves the context).
    var pendingInterviewRequest: CoachCarouselEngine.CoordinatorInterviewRequest? {
        get {
            guard let data = pendingInterviewRequestData else { return nil }
            return try? JSONDecoder().decode(CoachCarouselEngine.CoordinatorInterviewRequest.self, from: data)
        }
        set {
            pendingInterviewRequestData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }
}

// MARK: - Owner & Economy Codable Bridge (R31)

extension Career {

    /// The owner's tracked season goals. Writing encodes and stores the new
    /// list (caller saves the context).
    var ownerSeasonGoals: [SeasonGoal] {
        get {
            guard let data = ownerSeasonGoalsData,
                  let goals = try? JSONDecoder().decode([SeasonGoal].self, from: data) else {
                return []
            }
            return goals
        }
        set {
            ownerSeasonGoalsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Meddling-owner whims issued this season (and recent history).
    /// Writing encodes and stores the trimmed list (caller saves the context).
    var ownerWhims: [OwnerPersonaEngine.OwnerWhim] {
        get {
            guard let data = ownerWhimsData,
                  let whims = try? JSONDecoder().decode([OwnerPersonaEngine.OwnerWhim].self, from: data) else {
                return []
            }
            return whims
        }
        set {
            ownerWhimsData = try? JSONEncoder().encode(Array(newValue.suffix(8)))
        }
    }

    /// The most recent end-of-season owner review. Assigning `nil` clears it
    /// (caller saves the context).
    var ownerSeasonReview: OwnerPersonaEngine.OwnerSeasonReview? {
        get {
            guard let data = ownerSeasonReviewData else { return nil }
            return try? JSONDecoder().decode(OwnerPersonaEngine.OwnerSeasonReview.self, from: data)
        }
        set {
            ownerSeasonReviewData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }
}

// MARK: - League History & Hall of Fame Codable Bridge (R32)

extension Career {

    /// Per-season league history, newest first (max 20 seasons). Writing
    /// encodes and stores the trimmed list (caller saves the context).
    var seasonSummaries: [SeasonSummary] {
        get {
            guard let data = leagueHistoryData,
                  let summaries = try? JSONDecoder().decode([SeasonSummary].self, from: data) else {
                return []
            }
            return summaries
        }
        set {
            leagueHistoryData = try? JSONEncoder().encode(Array(newValue.prefix(20)))
        }
    }

    /// Hall of Fame inductees, newest class first (max 80). Writing encodes
    /// and stores the trimmed list (caller saves the context).
    var hallOfFame: [HallOfFameEntry] {
        get {
            guard let data = hallOfFameData,
                  let entries = try? JSONDecoder().decode([HallOfFameEntry].self, from: data) else {
                return []
            }
            return entries
        }
        set {
            hallOfFameData = try? JSONEncoder().encode(Array(newValue.prefix(80)))
        }
    }
}

// MARK: - Training-Focus Breakout Cap Codable Bridge

extension Career {

    /// Season-scoped per-team breakout usage (max 2/team/season), decoded
    /// from `breakoutCountsData`. Assigning `nil` clears it (caller saves
    /// the context).
    var seasonBreakoutCounts: TrainingFocusEngine.SeasonBreakoutCounts? {
        get {
            guard let data = breakoutCountsData else { return nil }
            return try? JSONDecoder().decode(TrainingFocusEngine.SeasonBreakoutCounts.self, from: data)
        }
        set {
            breakoutCountsData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }
}

// MARK: - Weekly Practice Play Bridge (R36)

extension Career {

    /// The play being drilled in practice this week, or `nil`. Setting a new
    /// play resets the banked weeks (caller saves the context).
    var weeklyPracticePlay: OffensivePlayCall? {
        get { weeklyPracticePlayRaw.flatMap(OffensivePlayCall.init(rawValue:)) }
        set {
            weeklyPracticePlayRaw = newValue?.rawValue
            weeklyPracticeWeeksDone = 0
        }
    }

    /// Plays installed through practice for the CURRENT season. A stale
    /// season's payload reads as empty (the write path resets it).
    var bonusInstalledPlays: [OffensivePlayCall] {
        guard bonusInstalledSeason == currentSeason else { return [] }
        return bonusInstalledPlaysRaw.compactMap(OffensivePlayCall.init(rawValue:))
    }

    /// Installs a practiced play into this season's bonus playbook and clears
    /// the practice slot (caller saves the context).
    func installPracticedPlay(_ play: OffensivePlayCall) {
        if bonusInstalledSeason != currentSeason {
            bonusInstalledPlaysRaw = []
            bonusInstalledSeason = currentSeason
        }
        if !bonusInstalledPlaysRaw.contains(play.rawValue) {
            bonusInstalledPlaysRaw.append(play.rawValue)
        }
        weeklyPracticePlayRaw = nil
        weeklyPracticeWeeksDone = 0
    }
}

// MARK: - Locker Room Codable Bridge (R25)

extension Career {

    /// Rolling log of resolved locker-room events, newest first (max 12).
    /// Writing encodes and stores the new list (caller saves the context).
    var lockerRoomLog: [LockerRoomEvent] {
        get {
            guard let data = lockerRoomLogData,
                  let log = try? JSONDecoder().decode([LockerRoomEvent].self, from: data) else {
                return []
            }
            return log
        }
        set {
            lockerRoomLogData = try? JSONEncoder().encode(Array(newValue.prefix(12)))
        }
    }

    /// The one open locker-room situation waiting for the coach's decision.
    /// Assigning `nil` clears it (caller saves the context).
    var pendingLockerRoomEvent: LockerRoomEvent? {
        get {
            guard let data = pendingLockerRoomEventData else { return nil }
            return try? JSONDecoder().decode(LockerRoomEvent.self, from: data)
        }
        set {
            pendingLockerRoomEventData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// The persisted preseason slate (#205b). Assigning `nil` clears it
    /// (caller saves the context). Career-scoped by construction — it lives on
    /// this row — and `PreseasonState.careerID` is stamped as well.
    var preseasonState: PreseasonState? {
        get {
            guard let data = preseasonData else { return nil }
            return try? JSONDecoder().decode(PreseasonState.self, from: data)
        }
        set {
            preseasonData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    /// The persisted undrafted market (#204), decoded. Assigning `nil` clears it
    /// (caller saves the context). Career-scoped by construction — it lives on
    /// this row.
    ///
    /// **Not the market's read door.** `UDFAMarketEngine.state(career:)` is, and
    /// it additionally checks `UDFAMarketState.season` against
    /// `currentSeason`, so last year's blob reads as "no market yet". This
    /// accessor is the raw codec, mirroring `preseasonState`; anything that
    /// wants to know whether the market is live must ask the engine.
    var udfaMarketState: UDFAMarketState? {
        get {
            guard let data = udfaMarketData else { return nil }
            return try? JSONDecoder().decode(UDFAMarketState.self, from: data)
        }
        set {
            udfaMarketData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }
}
