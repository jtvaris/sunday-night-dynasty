import Foundation
import SwiftData

@Model
final class Team {
    var id: UUID
    var name: String
    var city: String
    var abbreviation: String

    var conference: Conference
    var division: Division
    var mediaMarket: MediaMarket

    @Relationship(deleteRule: .nullify) var owner: Owner?

    // NOTE: The players relationship will be added once the Player model is available.
    // @Relationship(deleteRule: .nullify) var players: [Player]
    @Relationship(deleteRule: .nullify) var players: [Player]

    var wins: Int
    var losses: Int
    var ties: Int

    /// Total salary cap in thousands of dollars (default: $255,000,000 → 255_000).
    var salaryCap: Int

    /// Current cap usage in thousands of dollars.
    var currentCapUsage: Int

    // MARK: - Computed Properties

    /// Full franchise name combining city and team name (e.g. "Kansas City Chiefs").
    var fullName: String {
        "\(city) \(name)"
    }

    /// Win-loss record string. Includes ties only when at least one tie has occurred.
    var record: String {
        ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
    }

    /// Remaining cap space in thousands of dollars.
    var availableCap: Int {
        salaryCap - currentCapUsage
    }

    init(
        id: UUID = UUID(),
        name: String,
        city: String,
        abbreviation: String,
        conference: Conference,
        division: Division,
        mediaMarket: MediaMarket,
        owner: Owner? = nil,
        players: [Player] = [],
        wins: Int = 0,
        losses: Int = 0,
        ties: Int = 0,
        salaryCap: Int = 255_000,
        currentCapUsage: Int = 0
    ) {
        self.id = id
        self.name = name
        self.city = city
        self.abbreviation = abbreviation
        self.conference = conference
        self.division = division
        self.mediaMarket = mediaMarket
        self.owner = owner
        self.players = players
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.salaryCap = salaryCap
        self.currentCapUsage = currentCapUsage
    }
}
