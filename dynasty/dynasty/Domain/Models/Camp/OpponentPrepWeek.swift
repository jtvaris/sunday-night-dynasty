import Foundation
import SwiftData

/// Per-game-week balance between general (attribute development) and
/// opponent-specific preparation. The two pcts must sum to 100.
@Model
final class OpponentPrepWeek {
    var id: UUID
    var seasonYear: Int
    var weekNumber: Int
    /// 0–100. Drives long-term attribute drift.
    var generalPct: Int
    /// 0–100. Drives short-term audible/read bonuses for the upcoming game.
    var opponentPct: Int
    var teamID: UUID

    init(
        id: UUID = UUID(),
        seasonYear: Int,
        weekNumber: Int,
        generalPct: Int,
        opponentPct: Int,
        teamID: UUID
    ) {
        self.id = id
        self.seasonYear = seasonYear
        self.weekNumber = weekNumber
        self.generalPct = generalPct
        self.opponentPct = opponentPct
        self.teamID = teamID
    }
}
