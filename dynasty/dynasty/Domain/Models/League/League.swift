import Foundation
import SwiftData

@Model
final class League {
    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    var name: String

    @Relationship(deleteRule: .cascade) var teams: [Team]

    /// The calendar year of the current season (e.g. 2025).
    var currentSeason: Int

    /// The current week within the season (1-based).
    var currentWeek: Int

    /// The current phase of the season lifecycle.
    var currentPhase: SeasonPhase

    init(
        id: UUID = UUID(),
        name: String = "National Football League",
        teams: [Team] = [],
        currentSeason: Int,
        currentWeek: Int = 1,
        currentPhase: SeasonPhase = .preseason
    ) {
        self.id = id
        self.name = name
        self.teams = teams
        self.currentSeason = currentSeason
        self.currentWeek = currentWeek
        self.currentPhase = currentPhase
    }
}
