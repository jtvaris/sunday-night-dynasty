import Foundation

struct TeamBoxScore: Codable {
    var teamID: UUID
    var score: Int
    /// Scores per quarter: indices 0–3 are Q1–Q4; index 4 is overtime if played
    var quarterScores: [Int]
    var totalYards: Int
    var passingYards: Int
    var rushingYards: Int
    var firstDowns: Int
    var thirdDownConversions: Int
    var thirdDownAttempts: Int
    var turnovers: Int
    var sacks: Int
    var penalties: Int
    var penaltyYards: Int
    /// Total time of possession in seconds
    var timeOfPossession: Int
    var drives: Int
}

struct BoxScore: Codable {
    var home: TeamBoxScore
    var away: TeamBoxScore
    /// Ordered sequence of all drives in the game
    var drives: [DriveResult]
    /// Notable plays: touchdowns, turnovers, and big gains
    var highlights: [PlayResult]
}
