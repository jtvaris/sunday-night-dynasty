import Foundation

/// Generates a realistic 18-week, 17-game NFL regular season schedule for 32 teams.
///
/// Follows real NFL scheduling rules:
/// - 6 division games (home-and-away against 3 divisional rivals)
/// - 4 intra-conference games (one full division from the same conference, rotated yearly)
/// - 4 inter-conference games (one full division from the other conference, rotated yearly)
/// - 3 remaining intra-conference games (opponents from the other two divisions)
/// - 1 bye week per team, distributed between weeks 5–14
///
/// Because every team plays 17 games in 18 weeks, each team's schedule is
/// maximally tight: it must play in EVERY week except its single bye. The week
/// assigner therefore runs greedy + repair passes with full-shuffle retries so
/// no game is ever silently dropped (a dropped game shows up in the UI as a
/// team with two or more empty weeks).
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
        let matchups = generateMatchups(
            teams: teams,
            teamsByDivision: teamsByDivision,
            teamsByConference: teamsByConference,
            seasonYear: seasonYear
        )

        // Steps 2 & 3 — byes + week slots, retried together: a specific bye
        // layout can make the maximally tight week assignment unsolvable, so
        // every retry re-rolls the byes as well.
        return assignWeeks(
            matchups: matchups,
            teams: teams,
            teamsByDivision: teamsByDivision,
            seasonYear: seasonYear
        )
    }

    #if DEBUG
    /// Debug integrity check: every team must play exactly 17 games, never
    /// twice in one week, and have exactly ONE empty week (its bye) across the
    /// 18-week season. Returns human-readable violations; empty = sound.
    static func validate(games: [Game], teams: [Team]) -> [String] {
        var issues: [String] = []
        for team in teams {
            let weeks = games
                .filter { $0.homeTeamID == team.id || $0.awayTeamID == team.id }
                .map(\.week)
            if weeks.count != 17 {
                issues.append("\(team.abbreviation): \(weeks.count) games (expected 17)")
            }
            if Set(weeks).count != weeks.count {
                issues.append("\(team.abbreviation): plays twice in the same week")
            }
            let emptyWeeks = (1...18).filter { !weeks.contains($0) }
            if emptyWeeks.count != 1 {
                issues.append("\(team.abbreviation): \(emptyWeeks.count) empty weeks \(emptyWeeks)")
            }
        }
        return issues
    }
    #endif

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
        // Deterministic in-division ordering so home/away splits are stable.
        for key in map.keys {
            map[key]?.sort { $0.id.uuidString < $1.id.uuidString }
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

    // MARK: - Matchup Generation

    /// A lightweight matchup before it gets a week number.
    private struct Matchup {
        let homeID: UUID
        let awayID: UUID
    }

    /// The three possible perfect matchings of four divisions (by index into
    /// `Division.allCases`). Rotated yearly for the intra-conference pairing —
    /// a symmetric matching guarantees every division is paired exactly once.
    private static let divisionMatchings: [[(Int, Int)]] = [
        [(0, 1), (2, 3)],
        [(0, 2), (1, 3)],
        [(0, 3), (1, 2)],
    ]

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

        /// Full 4x4 division-vs-division slate: every team plays all four
        /// opponents, two at home and two away (alternating by index parity).
        func addCrossDivisionSlate(_ groupA: [Team], _ groupB: [Team]) {
            for (i, teamA) in groupA.enumerated() {
                for (j, teamB) in groupB.enumerated() {
                    if (i + j) % 2 == 0 {
                        addMatchup(home: teamA.id, away: teamB.id)
                    } else {
                        addMatchup(home: teamB.id, away: teamA.id)
                    }
                }
            }
        }

        let divisions = Division.allCases
        let intraMatching = divisionMatchings[abs(seasonYear) % divisionMatchings.count]

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

        // ---- 2. Intra-conference games (4 per team) ----
        // A rotating PERFECT MATCHING of the four divisions: each division is
        // paired with exactly one other, so every team gets exactly 4 games.
        // (The old per-division rotation was asymmetric — some divisions ended
        // up paired twice and others not at all, which broke game counts and
        // ultimately produced teams with multiple empty weeks.)
        for conference in Conference.allCases {
            for (i, j) in intraMatching {
                guard let teamsA = teamsByDivision[divisionKey(conference, divisions[i])],
                      let teamsB = teamsByDivision[divisionKey(conference, divisions[j])] else { continue }
                addCrossDivisionSlate(teamsA, teamsB)
            }
        }

        // ---- 3. Inter-conference games (4 per team) ----
        // AFC division i pairs with NFC division (i + year) — a shifted
        // bijection, so every division on both sides is used exactly once.
        // (The old code paired ALL FOUR AFC divisions with the SAME NFC
        // division, giving those four NFC teams ~16 extra games.)
        for (i, afcDiv) in divisions.enumerated() {
            let nfcDiv = divisions[(i + abs(seasonYear)) % divisions.count]
            guard let afcTeams = teamsByDivision[divisionKey(.AFC, afcDiv)],
                  let nfcTeams = teamsByDivision[divisionKey(.NFC, nfcDiv)] else { continue }
            addCrossDivisionSlate(afcTeams, nfcTeams)
        }

        // ---- 4. Remaining intra-conference games (3 per team) ----
        // The intra matching splits each conference into two 8-team halves;
        // every team's two "leftover" divisions are exactly the OTHER half.
        // A circulant 3-regular bipartite graph (team i plays i, i+1, i+2 mod
        // 8 on the other side) gives everyone exactly 3 games — no filler
        // heuristics, no overbooked opponents.
        for conference in Conference.allCases {
            let (pairA, pairB) = (intraMatching[0], intraMatching[1])
            let sideA = (teamsByDivision[divisionKey(conference, divisions[pairA.0])] ?? [])
                + (teamsByDivision[divisionKey(conference, divisions[pairA.1])] ?? [])
            let sideB = (teamsByDivision[divisionKey(conference, divisions[pairB.0])] ?? [])
                + (teamsByDivision[divisionKey(conference, divisions[pairB.1])] ?? [])
            guard !sideB.isEmpty else { continue }
            for (i, team) in sideA.enumerated() {
                for k in 0..<3 {
                    let opponent = sideB[(i + k) % sideB.count]
                    if (i + k) % 2 == 0 {
                        addMatchup(home: team.id, away: opponent.id)
                    } else {
                        addMatchup(home: opponent.id, away: team.id)
                    }
                }
            }
        }

        // Safety net: with the fixed rotations every team lands on exactly 17,
        // so this should never run — kept for malformed league data. Opponents
        // already at 17 are excluded so no team can be pushed past its cap.
        for team in teams {
            while gameCount[team.id, default: 0] < 17 {
                guard let confTeams = teamsByConference[team.conference] else { break }
                let candidates = confTeams.filter { $0.id != team.id }
                    .filter { gameCount[$0.id, default: 0] < 17 }
                    .filter { !existingPairs.contains(pairKey(team.id, $0.id)) }
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

        // Parity repair: a week with an ODD number of teams on bye leaves an
        // odd number of teams needing a game that week — unschedulable in a
        // 17-games/18-weeks season (every non-bye team must play every week).
        // Shift one team between odd-count weeks pairwise until every count is
        // even. (Odd counts always come in pairs because the total, 32, is even;
        // the cap holds because an odd count is at most 5.)
        var oddWeeks = byeRange.filter { (weekCounts[$0] ?? 0) % 2 == 1 }.shuffled()
        while oddWeeks.count >= 2 {
            let source = oddWeeks.removeFirst()
            let destination = oddWeeks.removeFirst()
            if let moved = byeWeeks.first(where: { $0.value == source })?.key {
                byeWeeks[moved] = destination
                weekCounts[source, default: 0] -= 1
                weekCounts[destination, default: 0] += 1
            }
        }

        return byeWeeks
    }

    // MARK: - Week Assignment

    private static let totalWeeks = 18

    /// Distributes matchups across weeks 1–18 while respecting bye weeks.
    /// Each team plays exactly once in every non-bye week.
    ///
    /// The schedule is maximally tight (17 games + 1 bye = 18 weeks), so a
    /// single greedy pass can dead-end — and a specific bye layout can make
    /// the whole instance unsolvable. Every retry therefore re-rolls the byes
    /// AND the matchup order until every matchup is seated.
    private static func assignWeeks(
        matchups: [Matchup],
        teams: [Team],
        teamsByDivision: [String: [Team]],
        seasonYear: Int
    ) -> [Game] {
        var best: [(matchup: Matchup, week: Int)] = []
        for _ in 0..<80 {
            let byeWeeks = assignByeWeeks(teams: teams, teamsByDivision: teamsByDivision)
            let attempt = attemptWeekAssignment(
                matchups: matchups.shuffled(),
                byeWeeks: byeWeeks
            )
            if attempt.count > best.count { best = attempt }
            if best.count == matchups.count { break }
        }

        return best.map { placed in
            Game(
                seasonYear: seasonYear,
                week: placed.week,
                homeTeamID: placed.matchup.homeID,
                awayTeamID: placed.matchup.awayID
            )
        }
    }

    /// One assignment attempt: greedy placement into the emptiest conflict-free
    /// week, then a repair pass that relocates blocking games to seat leftovers.
    /// Returns the placements it managed (callers check the count for success).
    private static func attemptWeekAssignment(
        matchups: [Matchup],
        byeWeeks: [UUID: Int]
    ) -> [(matchup: Matchup, week: Int)] {
        // Weeks each team is unavailable (bye + already-scheduled games).
        var occupied: [UUID: Set<Int>] = [:]
        for (teamID, byeWeek) in byeWeeks { occupied[teamID, default: []].insert(byeWeek) }
        var gamesPerWeek: [Int: Int] = [:]
        var placed: [(matchup: Matchup, week: Int)] = []
        var leftovers: [Matchup] = []

        func isFree(_ team: UUID, in week: Int) -> Bool {
            !(occupied[team]?.contains(week) ?? false)
        }
        func seat(_ matchup: Matchup, in week: Int) {
            placed.append((matchup: matchup, week: week))
            occupied[matchup.homeID, default: []].insert(week)
            occupied[matchup.awayID, default: []].insert(week)
            gamesPerWeek[week, default: 0] += 1
        }

        // --- Greedy pass ---
        for matchup in matchups {
            let candidates = (1...totalWeeks).filter {
                isFree(matchup.homeID, in: $0) && isFree(matchup.awayID, in: $0)
            }
            if let week = candidates.min(by: { (gamesPerWeek[$0] ?? 0) < (gamesPerWeek[$1] ?? 0) }) {
                seat(matchup, in: week)
            } else {
                leftovers.append(matchup)
            }
        }

        // --- Repair pass: Kempe-chain week swaps ---
        // In the tight end-state each team has few (often exactly one) free
        // weeks, so a leftover usually needs a CHAIN of relocations: to seat
        // (u, v) in u's free week A, v's game at A moves to v's free week B,
        // whose displaced opponent's game at B moves back to A, and so on —
        // the classic edge-coloring alternating-chain argument.
        func kempeSeat(_ matchup: Matchup, target: Int, via other: Int, mover: UUID) -> Bool {
            let anchor = mover == matchup.homeID ? matchup.awayID : matchup.homeID
            guard target != other,
                  byeWeeks[mover] != target, byeWeeks[anchor] != target else { return false }

            // Walk the chain of games alternating between `target` and `other`.
            var flips: [(index: Int, toWeek: Int)] = []
            var movedIndexes: Set<Int> = []
            var current = mover
            var from = target
            var to = other
            var steps = 0
            while true {
                steps += 1
                if steps > 64 { return false }
                guard let idx = placed.indices.first(where: { i in
                    !movedIndexes.contains(i) && placed[i].week == from
                        && (placed[i].matchup.homeID == current || placed[i].matchup.awayID == current)
                }) else { break } // current is clear at `from` — chain complete
                let entry = placed[idx].matchup
                let partner = entry.homeID == current ? entry.awayID : entry.homeID
                // A game can never move onto either member's bye.
                if byeWeeks[current] == to || byeWeeks[partner] == to { return false }
                flips.append((index: idx, toWeek: to))
                movedIndexes.insert(idx)
                current = partner
                swap(&from, &to)
            }
            guard !flips.isEmpty else { return false }

            // Verify the swapped board before committing: both weeks must
            // stay conflict-free and the leftover's teams clear at `target`.
            var trial = placed
            for flip in flips { trial[flip.index].week = flip.toWeek }
            for week in [target, other] {
                var seen: Set<UUID> = []
                for entry in trial where entry.week == week {
                    for team in [entry.matchup.homeID, entry.matchup.awayID] {
                        if byeWeeks[team] == week { return false }
                        if !seen.insert(team).inserted { return false }
                    }
                }
                if week == target && (seen.contains(mover) || seen.contains(anchor)) {
                    return false
                }
            }

            // Commit the chain, then seat the leftover.
            var touchedTeams: Set<UUID> = []
            for flip in flips {
                let old = placed[flip.index].week
                let moved = placed[flip.index].matchup
                touchedTeams.insert(moved.homeID)
                touchedTeams.insert(moved.awayID)
                gamesPerWeek[old, default: 0] -= 1
                gamesPerWeek[flip.toWeek, default: 0] += 1
                placed[flip.index].week = flip.toWeek
            }
            // Rebuild occupancy for every team the chain touched: incremental
            // set add/remove can't track two games passing through the same
            // week mid-chain and silently frees weeks that are still taken.
            for team in touchedTeams {
                var weeks: Set<Int> = []
                if let bye = byeWeeks[team] { weeks.insert(bye) }
                for entry in placed
                where entry.matchup.homeID == team || entry.matchup.awayID == team {
                    weeks.insert(entry.week)
                }
                occupied[team] = weeks
            }
            seat(matchup, in: target)
            return true
        }

        // Two passes: a chain committed for one leftover reshuffles the board
        // and can open a spot for a previously stuck one.
        var pending = leftovers
        for _ in 0..<2 where !pending.isEmpty {
            var stillStuck: [Matchup] = []
            for matchup in pending {
                let homeFree = (1...totalWeeks).filter { isFree(matchup.homeID, in: $0) }
                let awayFree = (1...totalWeeks).filter { isFree(matchup.awayID, in: $0) }

                // Direct placement can have opened up via earlier repairs.
                if let direct = homeFree.first(where: { awayFree.contains($0) }) {
                    seat(matchup, in: direct)
                    continue
                }

                var seated = false
                search: for a in homeFree {
                    for b in awayFree {
                        // Free the away side at the home side's free week…
                        if kempeSeat(matchup, target: a, via: b, mover: matchup.awayID) {
                            seated = true
                            break search
                        }
                        // …or the home side at the away side's free week.
                        if kempeSeat(matchup, target: b, via: a, mover: matchup.homeID) {
                            seated = true
                            break search
                        }
                    }
                }
                if !seated { stillStuck.append(matchup) }
            }
            pending = stillStuck
        }

        return placed
    }
}
