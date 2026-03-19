import Foundation
import SwiftData

@Model
final class DraftPick {
    var id: UUID
    var seasonYear: Int
    var round: Int
    var pickNumber: Int
    var originalTeamID: UUID
    var currentTeamID: UUID
    var playerID: UUID?
    var playerName: String?
    /// Position abbreviation of the drafted player (e.g. "QB"), stored for quick display.
    var playerPosition: String?
    /// College of the drafted player, stored for quick display.
    var playerCollege: String?
    /// Scout grade of the drafted player (e.g. "A+"), stored for quick display.
    var scoutGrade: String?
    /// Abbreviation of the team that made the pick, stored for quick display.
    var teamAbbreviation: String?
    var isComplete: Bool

    /// Media draft grade for this pick (e.g. "A+", "B-", "D").
    var mediaGrade: String?
    /// Media headline for this pick (e.g. "Lions steal Smith in Round 2!").
    var mediaHeadline: String?
    /// Media commentary sentence for this pick.
    var mediaComment: String?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        seasonYear: Int,
        round: Int,
        pickNumber: Int,
        originalTeamID: UUID,
        currentTeamID: UUID,
        playerID: UUID? = nil,
        playerName: String? = nil,
        playerPosition: String? = nil,
        playerCollege: String? = nil,
        scoutGrade: String? = nil,
        teamAbbreviation: String? = nil,
        isComplete: Bool = false,
        mediaGrade: String? = nil,
        mediaHeadline: String? = nil,
        mediaComment: String? = nil
    ) {
        self.id = id
        self.seasonYear = seasonYear
        self.round = round
        self.pickNumber = pickNumber
        self.originalTeamID = originalTeamID
        self.currentTeamID = currentTeamID
        self.playerID = playerID
        self.playerName = playerName
        self.playerPosition = playerPosition
        self.playerCollege = playerCollege
        self.scoutGrade = scoutGrade
        self.teamAbbreviation = teamAbbreviation
        self.isComplete = isComplete
        self.mediaGrade = mediaGrade
        self.mediaHeadline = mediaHeadline
        self.mediaComment = mediaComment
    }
}
