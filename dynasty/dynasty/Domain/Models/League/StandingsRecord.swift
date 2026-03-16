import Foundation

/// A calculated, non-persisted snapshot of a team's standing within a season.
struct StandingsRecord: Identifiable, Codable {
    let teamID: UUID
    var wins: Int
    var losses: Int
    var ties: Int
    var pointsFor: Int
    var pointsAgainst: Int
    var divisionWins: Int
    var divisionLosses: Int
    var divisionTies: Int
    var conferenceWins: Int
    var conferenceLosses: Int
    var conferenceTies: Int

    // MARK: - Identifiable

    var id: UUID { teamID }

    // MARK: - Computed Properties

    /// Overall win percentage (ties count as half a win).
    var winPercentage: Double {
        let games = wins + losses + ties
        guard games > 0 else { return 0.0 }
        return (Double(wins) + Double(ties) * 0.5) / Double(games)
    }

    /// Division win percentage (ties count as half a win).
    var divisionWinPercentage: Double {
        let games = divisionWins + divisionLosses + divisionTies
        guard games > 0 else { return 0.0 }
        return (Double(divisionWins) + Double(divisionTies) * 0.5) / Double(games)
    }

    /// Conference win percentage (ties count as half a win).
    var conferenceWinPercentage: Double {
        let games = conferenceWins + conferenceLosses + conferenceTies
        guard games > 0 else { return 0.0 }
        return (Double(conferenceWins) + Double(conferenceTies) * 0.5) / Double(games)
    }

    /// Points scored minus points allowed.
    var pointDifferential: Int {
        pointsFor - pointsAgainst
    }

    // MARK: - Init

    init(teamID: UUID) {
        self.teamID = teamID
        self.wins = 0
        self.losses = 0
        self.ties = 0
        self.pointsFor = 0
        self.pointsAgainst = 0
        self.divisionWins = 0
        self.divisionLosses = 0
        self.divisionTies = 0
        self.conferenceWins = 0
        self.conferenceLosses = 0
        self.conferenceTies = 0
    }
}
