import Foundation
import SwiftData

@Model
final class Schedule {
    var id: UUID
    var seasonYear: Int
    var leagueID: UUID

    // MARK: - Init

    init(
        id: UUID = UUID(),
        seasonYear: Int,
        leagueID: UUID
    ) {
        self.id = id
        self.seasonYear = seasonYear
        self.leagueID = leagueID
    }
}
