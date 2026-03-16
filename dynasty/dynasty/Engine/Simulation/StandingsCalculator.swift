import Foundation

/// Stateless engine that derives standings from a collection of played games.
enum StandingsCalculator {

    // MARK: - Public API

    /// Builds one `StandingsRecord` per team by aggregating all played regular-season games.
    ///
    /// - Parameters:
    ///   - games: Full schedule for the season (played and unplayed, playoff and regular).
    ///   - teams: All teams in the league.
    /// - Returns: An unsorted array containing one record for every team.
    static func calculate(games: [Game], teams: [Team]) -> [StandingsRecord] {
        // Seed a mutable record for every team.
        var records: [UUID: StandingsRecord] = Dictionary(
            uniqueKeysWithValues: teams.map { ($0.id, StandingsRecord(teamID: $0.id)) }
        )

        let playedRegularSeasonGames = games.filter { $0.isPlayed && !$0.isPlayoff }

        for game in playedRegularSeasonGames {
            guard
                let homeScore = game.homeScore,
                let awayScore = game.awayScore,
                records[game.homeTeamID] != nil,
                records[game.awayTeamID] != nil
            else { continue }

            let sameDivision   = areSameDivision(game.homeTeamID,   game.awayTeamID, teams: teams)
            let sameConference = areSameConference(game.homeTeamID, game.awayTeamID, teams: teams)

            let homeWon  = homeScore > awayScore
            let awayWon  = awayScore > homeScore
            let isTie    = homeScore == awayScore

            // --- Home team ---
            records[game.homeTeamID]!.pointsFor     += homeScore
            records[game.homeTeamID]!.pointsAgainst += awayScore

            if homeWon {
                records[game.homeTeamID]!.wins += 1
                if sameDivision   { records[game.homeTeamID]!.divisionWins    += 1 }
                if sameConference { records[game.homeTeamID]!.conferenceWins  += 1 }
            } else if isTie {
                records[game.homeTeamID]!.ties += 1
                if sameDivision   { records[game.homeTeamID]!.divisionTies    += 1 }
                if sameConference { records[game.homeTeamID]!.conferenceTies  += 1 }
            } else {
                records[game.homeTeamID]!.losses += 1
                if sameDivision   { records[game.homeTeamID]!.divisionLosses  += 1 }
                if sameConference { records[game.homeTeamID]!.conferenceLosses += 1 }
            }

            // --- Away team ---
            records[game.awayTeamID]!.pointsFor     += awayScore
            records[game.awayTeamID]!.pointsAgainst += homeScore

            if awayWon {
                records[game.awayTeamID]!.wins += 1
                if sameDivision   { records[game.awayTeamID]!.divisionWins    += 1 }
                if sameConference { records[game.awayTeamID]!.conferenceWins  += 1 }
            } else if isTie {
                records[game.awayTeamID]!.ties += 1
                if sameDivision   { records[game.awayTeamID]!.divisionTies    += 1 }
                if sameConference { records[game.awayTeamID]!.conferenceTies  += 1 }
            } else {
                records[game.awayTeamID]!.losses += 1
                if sameDivision   { records[game.awayTeamID]!.divisionLosses  += 1 }
                if sameConference { records[game.awayTeamID]!.conferenceLosses += 1 }
            }
        }

        return Array(records.values)
    }

    /// Returns the teams in a given division sorted by NFL tiebreaker rules.
    ///
    /// Tiebreaker order (simplified):
    ///   1. Overall win percentage
    ///   2. Division win percentage
    ///   3. Conference win percentage
    ///   4. Point differential
    ///
    /// - Returns: Sorted array; index 0 is the division leader.
    static func divisionStandings(
        records: [StandingsRecord],
        teams: [Team],
        conference: Conference,
        division: Division
    ) -> [StandingsRecord] {
        let divisionTeamIDs = Set(
            teams
                .filter { $0.conference == conference && $0.division == division }
                .map(\.id)
        )

        let filtered = records.filter { divisionTeamIDs.contains($0.teamID) }

        return filtered.sorted { nflTiebreaker($0, $1) }
    }

    /// Returns all teams in a conference sorted for playoff seeding:
    /// the 4 division winners come first (sorted among themselves), followed
    /// by the remaining teams as wild-card contenders (sorted by the same rules).
    ///
    /// - Returns: Full conference standings array.
    static func conferenceStandings(
        records: [StandingsRecord],
        teams: [Team],
        conference: Conference
    ) -> [StandingsRecord] {
        // One winner per division.
        var divisionWinners: [StandingsRecord] = []
        for division in Division.allCases {
            let divStandings = divisionStandings(
                records: records,
                teams: teams,
                conference: conference,
                division: division
            )
            if let leader = divStandings.first {
                divisionWinners.append(leader)
            }
        }

        // Sort division winners among themselves by the same tiebreaker.
        divisionWinners.sort { nflTiebreaker($0, $1) }

        let winnerIDs = Set(divisionWinners.map(\.teamID))

        // All remaining conference teams, sorted as wild-card contenders.
        let conferenceTeamIDs = Set(
            teams.filter { $0.conference == conference }.map(\.id)
        )
        let wildCardContenders = records
            .filter { conferenceTeamIDs.contains($0.teamID) && !winnerIDs.contains($0.teamID) }
            .sorted { nflTiebreaker($0, $1) }

        return divisionWinners + wildCardContenders
    }

    /// Returns the top 7 playoff seeds for the given conference
    /// (4 division winners + 3 wild cards), in seeded order (seed 1 first).
    static func playoffTeams(
        records: [StandingsRecord],
        teams: [Team],
        conference: Conference
    ) -> [StandingsRecord] {
        let standings = conferenceStandings(records: records, teams: teams, conference: conference)
        return Array(standings.prefix(7))
    }

    // MARK: - Private Helpers

    private static func areSameDivision(_ teamA: UUID, _ teamB: UUID, teams: [Team]) -> Bool {
        guard
            let a = teams.first(where: { $0.id == teamA }),
            let b = teams.first(where: { $0.id == teamB })
        else { return false }
        return a.conference == b.conference && a.division == b.division
    }

    private static func areSameConference(_ teamA: UUID, _ teamB: UUID, teams: [Team]) -> Bool {
        guard
            let a = teams.first(where: { $0.id == teamA }),
            let b = teams.first(where: { $0.id == teamB })
        else { return false }
        return a.conference == b.conference
    }

    /// Comparator implementing simplified NFL tiebreaker ordering (higher is better).
    ///   1. Overall win percentage
    ///   2. Division win percentage
    ///   3. Conference win percentage
    ///   4. Point differential
    private static func nflTiebreaker(_ lhs: StandingsRecord, _ rhs: StandingsRecord) -> Bool {
        if lhs.winPercentage != rhs.winPercentage {
            return lhs.winPercentage > rhs.winPercentage
        }
        if lhs.divisionWinPercentage != rhs.divisionWinPercentage {
            return lhs.divisionWinPercentage > rhs.divisionWinPercentage
        }
        if lhs.conferenceWinPercentage != rhs.conferenceWinPercentage {
            return lhs.conferenceWinPercentage > rhs.conferenceWinPercentage
        }
        return lhs.pointDifferential > rhs.pointDifferential
    }
}
