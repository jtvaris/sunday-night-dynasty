import Foundation
import SwiftData

@Model
final class Career {

    var id: UUID
    var playerName: String
    var avatarID: String
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

    // MARK: - Coaching Tree
    /// Full history of coaches who have worked under this career.
    /// SwiftData encodes this Codable struct as a composite attribute automatically.
    var coachingTree: CoachingTreeData

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
        role: CareerRole,
        capMode: CapMode,
        currentSeason: Int = 2026
    ) {
        self.id = UUID()
        self.playerName = playerName
        self.avatarID = avatarID
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
        self.currentWeek = 1
        self.currentPhase = .preseason
        self.coachingTree = CoachingTreeData()
        self.hcGMRelationship = CoachRelationshipEngine.HCGMRelationship()
    }
}
