import Foundation
import SwiftData

/// Tracked competition between 2-3 players for a starting / depth-chart spot.
/// `dailyResults` stores a JSON-encoded array of (day, leaderID) tuples that
/// `PositionBattleTracker` updates each camp day.
@Model
final class PositionBattle {
    var id: UUID
    var seasonYear: Int
    /// Raw value of `Position` enum.
    var positionRaw: String
    var competitorIDs: [UUID]
    var currentLeaderID: UUID?
    var winnerID: UUID?
    /// JSON: `[{"day": 0, "leaderID": "<uuid>"}, …]`. nil until first daily result is recorded.
    var dailyResults: String?
    var resolvedAt: Date?

    init(
        id: UUID = UUID(),
        seasonYear: Int,
        positionRaw: String,
        competitorIDs: [UUID],
        currentLeaderID: UUID? = nil,
        winnerID: UUID? = nil,
        dailyResults: String? = nil,
        resolvedAt: Date? = nil
    ) {
        self.id = id
        self.seasonYear = seasonYear
        self.positionRaw = positionRaw
        self.competitorIDs = competitorIDs
        self.currentLeaderID = currentLeaderID
        self.winnerID = winnerID
        self.dailyResults = dailyResults
        self.resolvedAt = resolvedAt
    }
}
