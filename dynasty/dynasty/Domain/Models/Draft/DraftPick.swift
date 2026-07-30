import Foundation
import SwiftData

@Model
final class DraftPick {
    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    #Index<DraftPick>([\.careerID])

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

    /// `true` while `pickNumber` is only a PLACEHOLDER slot.
    ///
    /// Future-year picks (seasons N+1…N+3) exist from league creation so they can
    /// be traded, but their real slot depends on standings nobody has played yet.
    /// Those rows are minted at the midpoint of their round (`round × 32 − 16`) —
    /// "a 2029 second" is one commodity, not 32 differently-priced ones — and this
    /// flag marks them as projections. `WeekAdvancer.prepareDraftOrder` adopts the
    /// rows of the year that just became current: it renumbers them from the final
    /// standings (keeping `currentTeamID`, so traded ownership and the "via ABC"
    /// badge survive) and clears the flag. Rows whose order is real from birth —
    /// the template's 2026 board, `DraftEngine.generateDraftOrder`, compensatory
    /// awards — are created with `false` and are never renumbered.
    ///
    /// Inline default = lightweight SwiftData migration: every pick row an
    /// existing save already holds reads back as a real, non-provisional order.
    var isProvisionalOrder: Bool = false

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
        isProvisionalOrder: Bool = false,
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
        self.isProvisionalOrder = isProvisionalOrder
        self.mediaGrade = mediaGrade
        self.mediaHeadline = mediaHeadline
        self.mediaComment = mediaComment
    }
}
