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

    // MARK: - Locker Room (R25)
    /// JSON-encoded `[LockerRoomEvent]` — resolved locker-room happenings,
    /// newest first, capped at 12. Optional new attribute → lightweight migration.
    var lockerRoomLogData: Data? = nil
    /// JSON-encoded `LockerRoomEvent` awaiting the coach's response
    /// (intervene / let it play out). `nil` when nothing is pending.
    /// Optional new attribute → lightweight migration.
    var pendingLockerRoomEventData: Data? = nil

    var winPercentage: Double {
        let totalGames = totalWins + totalLosses
        guard totalGames > 0 else { return 0.0 }
        return Double(totalWins) / Double(totalGames)
    }

    init(
        playerName: String,
        avatarID: String = "coach_m1",
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
}
