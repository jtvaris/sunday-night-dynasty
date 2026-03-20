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

    // MARK: - Free Agency State
    /// Current FA round: 0 = pre-FA, 1-6 = rounds (Day 1-3, Week 2-4).
    var freeAgencyRound: Int = 0
    /// Current sub-step within the FA phase (stored as raw value of FreeAgencyStep).
    var freeAgencyStep: String = FreeAgencyStep.finalPush.rawValue

    // MARK: - Scouting Counters
    /// Number of combine interviews conducted this year (max 60).
    var interviewsUsed: Int = 0
    /// Number of personal workouts conducted this year (max 30).
    var workoutsUsed: Int = 0

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
