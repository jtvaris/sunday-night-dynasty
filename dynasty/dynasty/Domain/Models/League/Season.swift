import Foundation
import SwiftData

@Model
final class Season {
    var id: UUID

    /// The calendar year this season represents (e.g. 2025).
    var year: Int

    /// The UUID of the League this season belongs to.
    var leagueID: UUID

    init(
        id: UUID = UUID(),
        year: Int,
        leagueID: UUID
    ) {
        self.id = id
        self.year = year
        self.leagueID = leagueID
    }
}
