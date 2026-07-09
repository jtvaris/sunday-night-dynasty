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
