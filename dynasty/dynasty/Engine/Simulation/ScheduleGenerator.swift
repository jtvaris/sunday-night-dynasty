import Foundation

/// Generates a realistic 18-week, 17-game NFL regular season schedule for 32 teams.
///
/// Follows real NFL scheduling rules:
/// - 6 division games (home-and-away against 3 divisional rivals)
/// - 4 intra-conference games (one full division from the same conference, rotated yearly)
/// - 4 inter-conference games (one full division from the other conference, rotated yearly)
/// - 3 remaining intra-conference games (opponents from the other two divisions, randomized)
/// - 1 bye week per team, distributed between weeks 5–14
enum ScheduleGenerator {

    // MARK: - Public API

    /// Generate a full 18-week regular season schedule.
    /// - Parameters:
    ///   - teams: All 32 NFL teams. Behavior is undefined for counts other than 32.
    ///   - seasonYear: The season year used on every `Game` object.
    /// - Returns: An array of `Game` objects representing every regular season matchup.
    static func generateSeason(teams: [Team], seasonYear: Int) -> [Game] {
        guard teams.count == 32 else { return [] }

        // Build lookup structures
        let teamsByDivision = buildDivisionMap(teams)
        let teamsByConference = buildConferenceMap(teams)

        // Step 1 — generate all matchups (unscheduled, no week yet)
        var matchups = generateMatchups(
            teams: teams,
            teamsByDivision: teamsByDivision,
            teamsByConference: teamsByConference,
            seasonYear: seasonYear
        )

        // Step 2 — assign bye weeks
        let byeWeeks = assignByeWeeks(teams: teams, teamsByDivision: teamsByDivision)

        // Step 3 — slot matchups into weeks 1–18
        let games = assignWeeks(matchups: &matchups, byeWeeks: byeWeeks, seasonYear: seasonYear)

        return games
    }

    // MARK: - Division / Conference Helpers

    private static func divisionKey(_ conference: Conference, _ division: Division) -> String {
        "\(conference.rawValue)-\(division.rawValue)"
    }

    private static func buildDivisionMap(_ teams: [Team]) -> [String: [Team]] {
        var map: [String: [Team]] = [:]
        for team in teams {
            let key = divisionKey(team.conference, team.division)
            map[key, default: []].append(team)
        }
        return map
    }

    private static func buildConferenceMap(_ teams: [Team]) -> [Conference: [Team]] {
        var map: [Conference: [Team]] = [:]
        for team in teams {
            map[team.conference, default: []].append(team)
        }
        return map
    }

    private static func divisionsInConference(_ conference: Conference, excluding: Division) -> [Division] {
        Division.allCases.filter { $0 != excluding }
    }

    // MARK: - Matchup Generation

    /// A lightweight matchup before it gets a week number.
    private struct Matchup {
        let homeID: UUID
        let awayID: UUID
    }

    private static func generateMatchups(
        teams: [Team],
        teamsByDivision: [String: [Team]],
        teamsByConference: [Conference: [Team]],
        seasonYear: Int
    ) -> [Matchup] {
        var matchups: [Matchup] = []
        // Track how many games each team has been assigned
        var gameCount: [UUID: Int] = [:]
        for team in teams { gameCount[team.id] = 0 }

        // Track all matchup pairs to avoid duplicates (unordered pair)
        var existingPairs: Set<String> = []

        func pairKey(_ a: UUID, _ b: UUID) -> String {
            let sorted = [a.uuidString, b.uuidString].sorted()
            return "\(sorted[0])|\(sorted[1])"
        }

        func addMatchup(home: UUID, away: UUID) {
            let key = pairKey(home, away)
            guard !existingPairs.contains(key) else { return }
            existingPairs.insert(key)
            matchups.append(Matchup(homeID: home, awayID: away))
            gameCount[home, default: 0] += 1
            gameCount[away, default: 0] += 1
        }

        // ---- 1. Division games: 6 per team (home-and-away vs 3 rivals) ----
        for (_, divTeams) in teamsByDivision {
            for i in 0..<divTeams.count {
                for j in (i + 1)..<divTeams.count {
                    let a = divTeams[i]
                    let b = divTeams[j]
                    // Each pair plays twice — once at each venue
                    matchups.append(Matchup(homeID: a.id, awayID: b.id))
                    matchups.append(Matchup(homeID: b.id, awayID: a.id))
                    gameCount[a.id, default: 0] += 2
                    gameCount[b.id, default: 0] += 2
                    // Division games are always home-and-away pairs, so we don't
                    // add them to existingPairs (they intentionally repeat).
                }
            }
        }

        // ---- 2. Intra-conference games (4 per team): full division rotation ----
        let divisions = Division.allCases
        for conference in Conference.allCases {
            for divIndex in 0..<divisions.count {
                let div = divisions[divIndex]
                // Rotate: each division plays one other division fully, based on seasonYear
                let otherDivs = divisions.filter { $0 != div }
                let rotationIndex = seasonYear % otherDivs.count
                let pairedDiv = otherDivs[rotationIndex]

                let key1 = divisionKey(conference, div)
                let key2 = divisionKey(conference, pairedDiv)

                guard let divTeams = teamsByDivision[key1],
                      let pairedTeams = teamsByDivision[key2] else { continue }

                // To avoid double-booking (div A pairs with B, AND B pairs with A),
                // only generate when div < pairedDiv in raw value order.
                guard div.rawValue < pairedDiv.rawValue else { continue }

                // Each team in div plays all 4 teams in pairedDiv (2 home, 2 away).
                for team in divTeams {
                    let shuffled = pairedTeams.shuffled()
                    for (i, opponent) in shuffled.enumerated() {
                        if i < 2 {
                            addMatchup(home: team.id, away: opponent.id)
                        } else {
                            addMatchup(home: opponent.id, away: team.id)
                        }
                    }
                }
            }
        }

        // ---- 3. Inter-conference games (4 per team): full division from opposite conference ----
        for div in divisions {
            // AFC div plays against NFC div based on rotation
            let otherDivs = divisions
            let rotationIndex = seasonYear % otherDivs.count
            let pairedDiv = otherDivs[rotationIndex]

            let afcKey = divisionKey(.AFC, div)
            let nfcKey = divisionKey(.NFC, pairedDiv)

            guard let afcTeams = teamsByDivision[afcKey],
                  let nfcTeams = teamsByDivision[nfcKey] else { continue }

            // Each AFC team plays all 4 NFC teams (2 home, 2 away).
            for afcTeam in afcTeams {
                let shuffled = nfcTeams.shuffled()
                for (i, nfcTeam) in shuffled.enumerated() {
                    if i < 2 {
                        addMatchup(home: afcTeam.id, away: nfcTeam.id)
                    } else {
                        addMatchup(home: nfcTeam.id, away: afcTeam.id)
                    }
                }
            }
        }

        // ---- 4. Remaining intra-conference games (need 17 total per team) ----
        // Each team needs 3 more games from the remaining 2 divisions in their conference.
        let teamByID: [UUID: Team] = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        for conference in Conference.allCases {
            for div in divisions {
                let key = divisionKey(conference, div)
                guard let divTeams = teamsByDivision[key] else { continue }

                // Find the two divisions that are NOT the paired intra-conference division
                let otherDivs = divisions.filter { $0 != div }
                let intraRotation = seasonYear % otherDivs.count
                let pairedIntraDiv = otherDivs[intraRotation]
                let remainingDivs = otherDivs.filter { $0 != pairedIntraDiv }

                for team in divTeams {
                    let needed = 17 - gameCount[team.id, default: 0]
                    guard needed > 0 else { continue }

                    // Collect candidate opponents from the remaining divisions
                    var candidates: [Team] = []
                    for rd in remainingDivs {
                        let rdKey = divisionKey(conference, rd)
                        if let rdTeams = teamsByDivision[rdKey] {
                            candidates.append(contentsOf: rdTeams)
                        }
                    }

                    // Filter out anyone we already play
                    candidates = candidates.filter { candidate in
                        let key1 = pairKey(team.id, candidate.id)
                        return !existingPairs.contains(key1)
                    }

                    // Also prefer opponents who still need games
                    candidates.sort { (gameCount[$0.id, default: 0]) < (gameCount[$1.id, default: 0]) }

                    let toSchedule = min(needed, candidates.count)
                    for i in 0..<toSchedule {
                        let opponent = candidates[i]
                        // Alternate home/away
                        if i % 2 == 0 {
                            addMatchup(home: team.id, away: opponent.id)
                        } else {
                            addMatchup(home: opponent.id, away: team.id)
                        }
                    }
                }
            }
        }

        // Safety: if any team still doesn't have 17, fill with random intra-conference opponents
        for team in teams {
            while gameCount[team.id, default: 0] < 17 {
                guard let confTeams = teamsByConference[team.conference] else { break }
                let candidates = confTeams.filter { $0.id != team.id }
                    .filter { candidate in
                        let key = pairKey(team.id, candidate.id)
                        return !existingPairs.contains(key)
                    }
                    .sorted { gameCount[$0.id, default: 0] < gameCount[$1.id, default: 0] }

                guard let opponent = candidates.first else { break }
                if gameCount[team.id, default: 0] % 2 == 0 {
                    addMatchup(home: team.id, away: opponent.id)
                } else {
                    addMatchup(home: opponent.id, away: team.id)
                }
            }
        }

        return matchups
    }

    // MARK: - Bye Week Assignment

    /// Assigns bye weeks between weeks 5–14, ensuring:
    /// - At most 6 teams on bye per week (fits 32 teams across 10 weeks: need at least ~4 per week)
    /// - Divisional rivals avoid sharing the same bye week when possible.
    private static func assignByeWeeks(
        teams: [Team],
        teamsByDivision: [String: [Team]]
    ) -> [UUID: Int] {
        let byeRange = 5...14  // 10 available bye weeks
        let maxPerWeek = 6
        var weekCounts: [Int: Int] = [:]  // week -> number of teams on bye
        for w in byeRange { weekCounts[w] = 0 }

        var byeWeeks: [UUID: Int] = [:]

        // Assign division by division, spreading each division across different weeks
        for (_, divTeams) in teamsByDivision {
            let shuffled = divTeams.shuffled()
            // Track which weeks this division has already used
            var usedWeeks: Set<Int> = []

            for team in shuffled {
                // Prefer weeks not used by this division yet AND under the cap
                let preferred = byeRange.filter { w in
                    !usedWeeks.contains(w) && (weekCounts[w] ?? 0) < maxPerWeek
                }
                let fallback = byeRange.filter { w in
                    (weekCounts[w] ?? 0) < maxPerWeek
                }

                let pool = preferred.isEmpty ? fallback : preferred
                guard let chosen = pool.randomElement() else { continue }

                byeWeeks[team.id] = chosen
                weekCounts[chosen, default: 0] += 1
                usedWeeks.insert(chosen)
            }
        }

        return byeWeeks
    }

    // MARK: - Week Assignment

    /// Distributes matchups across weeks 1–18 while respecting bye weeks.
    /// Each team plays at most once per week and has exactly one bye week.
    private static func assignWeeks(
        matchups: inout [Matchup],
        byeWeeks: [UUID: Int],
        seasonYear: Int
    ) -> [Game] {
        var games: [Game] = []

        // Shuffle matchups for variety
        matchups.shuffle()

        // Track which weeks each team is already playing in
        var teamWeeks: [UUID: Set<Int>] = [:]

        // Add bye weeks to the team's "occupied" weeks so no game lands there
        for (teamID, byeWeek) in byeWeeks {
            teamWeeks[teamID, default: []].insert(byeWeek)
        }

        // Assign each matchup to a week
        for matchup in matchups {
            let homeOccupied = teamWeeks[matchup.homeID, default: []]
            let awayOccupied = teamWeeks[matchup.awayID, default: []]

            // Find a week where neither team is busy
            var bestWeek: Int?
            var bestCount = Int.max  // prefer weeks with fewer games for balance

            for week in 1...18 {
                guard !homeOccupied.contains(week),
                      !awayOccupied.contains(week) else { continue }

                // Count how many games are already in this week
                let currentCount = games.filter { $0.week == week }.count
                if currentCount < bestCount {
                    bestCount = currentCount
                    bestWeek = week
                }
            }

            guard let week = bestWeek else {
                // Fallback: find any available week (shouldn't happen with valid inputs)
                let available = (1...18).first { w in
                    !homeOccupied.contains(w) && !awayOccupied.contains(w)
                }
                guard let fallbackWeek = available else { continue }
                let game = Game(
                    seasonYear: seasonYear,
                    week: fallbackWeek,
                    homeTeamID: matchup.homeID,
                    awayTeamID: matchup.awayID
                )
                games.append(game)
                teamWeeks[matchup.homeID, default: []].insert(fallbackWeek)
                teamWeeks[matchup.awayID, default: []].insert(fallbackWeek)
                continue
            }

            let game = Game(
                seasonYear: seasonYear,
                week: week,
                homeTeamID: matchup.homeID,
                awayTeamID: matchup.awayID
            )
            games.append(game)
            teamWeeks[matchup.homeID, default: []].insert(week)
            teamWeeks[matchup.awayID, default: []].insert(week)
        }

        return games
    }
}
