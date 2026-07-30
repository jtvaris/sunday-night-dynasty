import Foundation
import SwiftData

@Model
final class Game {
    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    #Index<Game>([\.careerID])

    var seasonYear: Int
    var week: Int
    var homeTeamID: UUID
    var awayTeamID: UUID
    var homeScore: Int?
    var awayScore: Int?
    var isPlayoff: Bool

    // MARK: - Computed Properties

    /// True when both scores have been recorded.
    var isPlayed: Bool {
        homeScore != nil && awayScore != nil
    }

    /// The UUID of the winning team, or nil if the game is unplayed or ended in a tie.
    var winnerID: UUID? {
        guard let home = homeScore, let away = awayScore else { return nil }
        if home > away { return homeTeamID }
        if away > home { return awayTeamID }
        return nil
    }

    /// The UUID of the losing team, or nil if the game is unplayed or ended in a tie.
    var loserID: UUID? {
        guard let home = homeScore, let away = awayScore else { return nil }
        if home < away { return homeTeamID }
        if away < home { return awayTeamID }
        return nil
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        seasonYear: Int,
        week: Int,
        homeTeamID: UUID,
        awayTeamID: UUID,
        homeScore: Int? = nil,
        awayScore: Int? = nil,
        isPlayoff: Bool = false
    ) {
        self.id = id
        self.seasonYear = seasonYear
        self.week = week
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
        self.homeScore = homeScore
        self.awayScore = awayScore
        self.isPlayoff = isPlayoff
    }
}
