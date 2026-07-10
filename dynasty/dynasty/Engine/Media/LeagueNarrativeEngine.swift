import Foundation

// MARK: - League Narrative State (R29)

/// Persisted, presentation-only storyline state for the league narrative
/// systems: weekly power rankings (with week-over-week movement), the MVP
/// race, and "already reported" markers that keep the news cycle from
/// repeating the same story week after week.
/// JSON-encoded onto the career (`Career.leagueNarrativeData`).
struct LeagueNarrativeState: Codable {
    var season: Int
    /// The regular-season week these rankings were computed after.
    var week: Int
    /// Full 32-team power ranking, rank 1 first.
    var rankings: [PowerRankingEntry]
    /// Accumulated MVP-race score per player (top candidates only).
    var mvpPoints: [UUID: Double]
    /// Top-3 MVP candidates, best first (snapshot for UI + presser).
    var mvpRace: [MVPCandidate]
    /// Signed streak length last reported per team (+N win / -N loss streak).
    /// A streak only makes headlines again once it has grown further.
    var reportedStreaks: [UUID: Int]
    /// Teams whose hot-seat story already ran this season.
    var hotSeatReported: Set<UUID>
    /// Season-arc checkpoint weeks already covered for the user's team.
    var arcCheckpointsDone: Set<Int>
    /// Division-race pairs (sorted team-id strings joined) already framed as
    /// a rivalry this season — each pairing gets one big rivalry story.
    var divisionRacesReported: Set<String>

    init(season: Int) {
        self.season = season
        self.week = 0
        self.rankings = []
        self.mvpPoints = [:]
        self.mvpRace = []
        self.reportedStreaks = [:]
        self.hotSeatReported = []
        self.arcCheckpointsDone = []
        self.divisionRacesReported = []
    }
}

/// One row of the weekly power rankings. Team display fields are snapshotted
/// at generation time so the UI card can render without model fetches.
struct PowerRankingEntry: Codable, Identifiable {
    var id: UUID { teamID }
    let teamID: UUID
    let rank: Int
    /// Last week's rank; nil in the first ranked week of the season.
    let previousRank: Int?
    let teamAbbr: String
    let teamName: String
    let record: String
    /// One-sentence, template-based blurb tied to the team's week.
    let blurb: String

    /// Positive = climbed, negative = fell, 0 = held (or first week).
    var movement: Int { previousRank.map { $0 - rank } ?? 0 }
}

/// One MVP-race candidate (snapshot for UI + presser).
struct MVPCandidate: Codable, Identifiable {
    var id: UUID { playerID }
    let playerID: UUID
    let playerName: String
    let teamID: UUID?
    let teamAbbr: String
    let positionRaw: String
    /// Accumulated race score (higher = stronger case).
    let points: Double
}

// MARK: - League Narrative Engine (R29)

/// Stateless generator for the weekly league narrative: storyline news
/// (streaks, upsets, hot seats, division races, the user team's season arc),
/// the MVP race, and the full power rankings. Presentation only — nothing
/// here touches simulation results or distributions.
enum LeagueNarrativeEngine {

    struct WeeklyUpdate {
        let state: LeagueNarrativeState
        let news: [NewsItem]
    }

    /// Maximum narrative headlines added per week (the base weekly news from
    /// `NewsGenerator` is produced separately).
    private static let maxWeeklyItems = 6

    // MARK: - Weekly Update

    /// Runs after this week's games have been simulated and team records
    /// updated. `games` is the full season schedule (played + unplayed).
    static func updateWeekly(
        previousState: LeagueNarrativeState?,
        teams: [Team],
        players: [Player],
        coaches: [Coach] = [],
        games: [Game],
        career: Career,
        week: Int,
        season: Int
    ) -> WeeklyUpdate {
        var state: LeagueNarrativeState = {
            if let prev = previousState, prev.season == season { return prev }
            return LeagueNarrativeState(season: season)
        }()

        let playedGames = games.filter { $0.isPlayed && !$0.isPlayoff }
        let streaks = currentStreaks(teams: teams, playedGames: playedGames)
        let form = recentForm(teams: teams, playedGames: playedGames)

        // 1. Power rankings (always computed — feeds the UI card + movement).
        let previousRanks: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: state.rankings.map { ($0.teamID, $0.rank) }
        )
        let rankings = computeRankings(
            teams: teams,
            previousRanks: previousRanks,
            streaks: streaks,
            form: form,
            week: week
        )

        // 2. MVP race accumulation.
        let mvpUpdate = accumulateMVPRace(
            state: state,
            teams: teams,
            players: players,
            weekGames: playedGames.filter { $0.week == week }
        )
        state.mvpPoints = mvpUpdate.points
        state.mvpRace = mvpUpdate.race

        // 3. Assemble this week's storyline headlines (priority order, cap 6).
        var news: [NewsItem] = []

        news.append(powerRankingsNews(
            rankings: rankings, career: career, week: week, season: season
        ))

        if let upset = upsetNews(
            teams: teams, playedGames: playedGames,
            previousRanks: previousRanks, week: week, season: season
        ) {
            news.append(upset)
        }

        news.append(contentsOf: streakNews(
            teams: teams, streaks: streaks, state: &state, week: week, season: season
        ))

        // R33: coordinator-persona flavor — an exotic DC stifling an offense.
        if let personaItem = exoticDefenseNews(
            teams: teams, coaches: coaches, playedGames: playedGames,
            week: week, season: season
        ) {
            news.append(personaItem)
        }

        if week >= 6, week % 3 == 0, !state.mvpRace.isEmpty {
            news.append(mvpRaceNews(race: state.mvpRace, week: week, season: season))
        }

        if week >= 12, let raceItem = divisionRaceNews(
            teams: teams, state: &state, week: week, season: season
        ) {
            news.append(raceItem)
        }

        if let arc = seasonArcNews(
            teams: teams, career: career, state: &state, week: week, season: season
        ) {
            news.append(arc)
        }

        if week >= 6, let hotSeat = hotSeatNews(
            teams: teams, career: career, state: &state, week: week, season: season
        ) {
            news.append(hotSeat)
        }

        // 4. Persist the fresh rankings + streak markers.
        state.week = week
        state.rankings = rankings
        pruneStreakMarkers(state: &state, streaks: streaks)

        return WeeklyUpdate(state: state, news: Array(news.prefix(maxWeeklyItems)))
    }

    // MARK: - Power Rankings

    /// Ranking score: record is the backbone, scoring margin separates equal
    /// records, and the last three weeks add a form kicker so hot/cold teams
    /// move even before their record catches up.
    private static func computeRankings(
        teams: [Team],
        previousRanks: [UUID: Int],
        streaks: [UUID: Int],
        form: [UUID: Int],
        week: Int
    ) -> [PowerRankingEntry] {
        struct Scored {
            let team: Team
            let score: Double
        }

        let scored = teams.map { team -> Scored in
            let games = team.wins + team.losses + team.ties
            let winPct = games > 0
                ? (Double(team.wins) + 0.5 * Double(team.ties)) / Double(games)
                : 0.5
            // Point differential per game isn't tracked on Team; the form
            // component (last-3 result trend) carries the recency signal and
            // signed streaks act as the margin proxy.
            let formScore = Double(form[team.id] ?? 0)          // -3...3
            let streakScore = Double(streaks[team.id] ?? 0)     // signed
            let score = winPct * 100.0
                + formScore * 4.0
                + streakScore.clampedNarrative(to: -5...5) * 1.5
            return Scored(team: team, score: score)
        }

        let sorted = scored.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            // Stable tie-break so equal teams don't shuffle randomly week to week.
            return $0.team.abbreviation < $1.team.abbreviation
        }

        return sorted.enumerated().map { index, entry in
            let rank = index + 1
            let previous = previousRanks[entry.team.id]
            return PowerRankingEntry(
                teamID: entry.team.id,
                rank: rank,
                previousRank: previous,
                teamAbbr: entry.team.abbreviation,
                teamName: entry.team.fullName,
                record: entry.team.record,
                blurb: rankingBlurb(
                    team: entry.team,
                    rank: rank,
                    movement: previous.map { $0 - rank } ?? 0,
                    streak: streaks[entry.team.id] ?? 0,
                    week: week
                )
            )
        }
    }

    /// Template-pool blurbs — variant rotates with the week so the same team
    /// in the same situation still reads differently next week.
    private static func rankingBlurb(
        team: Team,
        rank: Int,
        movement: Int,
        streak: Int,
        week: Int
    ) -> String {
        let pool: [String]
        if streak >= 4 {
            pool = [
                "Riding a \(streak)-game winning streak and playing like it.",
                "Winners of \(streak) straight — the league is on notice.",
                "The \(streak)-game heater shows no sign of cooling off.",
            ]
        } else if streak >= 3 {
            pool = [
                "Three in a row has this locker room believing.",
                "Quietly stacking wins — three straight and counting.",
                "A three-game run has changed the mood in \(team.city).",
            ]
        } else if streak <= -4 {
            pool = [
                "Losers of \(-streak) straight — the season is slipping away.",
                "A \(-streak)-game skid has \(team.city) asking hard questions.",
                "No answers yet during this \(-streak)-game slide.",
            ]
        } else if streak <= -3 {
            pool = [
                "Three straight losses and the pressure is building.",
                "A three-game skid puts every job under the microscope.",
                "Searching for a spark after three losses in a row.",
            ]
        } else if movement >= 3 {
            pool = [
                "The week's biggest riser, up \(movement) spots.",
                "Climbing fast — up \(movement) places in this week's board.",
                "Momentum is real: a \(movement)-spot jump.",
            ]
        } else if movement <= -3 {
            pool = [
                "Falling \(-movement) spots after a rough week.",
                "The week's steepest drop — down \(-movement) places.",
                "A stumble costs them \(-movement) spots.",
            ]
        } else if rank == 1 {
            pool = [
                "The team to beat until someone proves otherwise.",
                "Holding the top spot with room to spare.",
                "Still the standard the rest of the league chases.",
            ]
        } else if rank <= 5 {
            pool = [
                "Legitimate contenders by any measure.",
                "Built for January — the résumé keeps growing.",
                "Firmly in the championship conversation.",
            ]
        } else if rank <= 12 {
            pool = [
                "In the playoff mix with work left to do.",
                "Good enough to beat anyone, streaky enough to worry.",
                "The middle of the pack starts here.",
            ]
        } else if rank <= 24 {
            pool = [
                "Searching for consistency week to week.",
                "Flashes of promise, too many empty afternoons.",
                "Every win feels like a step; every loss, a reset.",
            ]
        } else {
            pool = [
                "Eyes already drifting toward April's draft board.",
                "A long season — the rebuild continues.",
                "Playing for pride and next year's core.",
            ]
        }
        return pool[(week + rank) % pool.count]
    }

    private static func powerRankingsNews(
        rankings: [PowerRankingEntry],
        career: Career,
        week: Int,
        season: Int
    ) -> NewsItem {
        let top = rankings.prefix(3)
        let leader = top.first
        let riser = rankings.max { $0.movement < $1.movement }

        var body = "This week's top three: "
            + top.map { "\($0.rank). \($0.teamName) (\($0.record))" }.joined(separator: ", ")
            + "."
        if let riser, riser.movement >= 3 {
            body += " Biggest riser: \(riser.teamName), up \(riser.movement) spots."
        }
        if let userEntry = rankings.first(where: { $0.teamID == career.teamID }) {
            body += " Your squad checks in at No. \(userEntry.rank)."
        }

        let headlinePool = [
            "Week \(week) Power Rankings: \(leader?.teamName ?? "TBD") on top",
            "Power Rankings, Week \(week): \(leader?.teamName ?? "TBD") set the pace",
            "Week \(week) board: \(leader?.teamName ?? "TBD") hold off the field",
        ]

        return NewsItem(
            headline: headlinePool[week % headlinePool.count],
            body: body,
            category: .teamRanking,
            week: week,
            season: season,
            relatedTeamID: leader?.teamID,
            sentiment: .neutral
        )
    }

    // MARK: - Streaks

    /// Signed current streak per team (+N straight wins / -N straight losses),
    /// derived from played regular-season games. Ties break streaks.
    static func currentStreaks(teams: [Team], playedGames: [Game]) -> [UUID: Int] {
        var streaks: [UUID: Int] = [:]
        for team in teams {
            let teamGames = playedGames
                .filter { $0.homeTeamID == team.id || $0.awayTeamID == team.id }
                .sorted { $0.week > $1.week }
            guard let latest = teamGames.first else { continue }
            guard let latestWon = didWin(team: team.id, game: latest) else { continue }

            var count = 0
            for game in teamGames {
                guard let won = didWin(team: team.id, game: game), won == latestWon else { break }
                count += 1
            }
            streaks[team.id] = latestWon ? count : -count
        }
        return streaks
    }

    /// Wins minus losses over each team's last three played games (-3...3).
    private static func recentForm(teams: [Team], playedGames: [Game]) -> [UUID: Int] {
        var form: [UUID: Int] = [:]
        for team in teams {
            let recent = playedGames
                .filter { $0.homeTeamID == team.id || $0.awayTeamID == team.id }
                .sorted { $0.week > $1.week }
                .prefix(3)
            var score = 0
            for game in recent {
                guard let won = didWin(team: team.id, game: game) else { continue }
                score += won ? 1 : -1
            }
            form[team.id] = score
        }
        return form
    }

    /// True/false for a decided game, nil for a tie or if the team didn't play.
    private static func didWin(team: UUID, game: Game) -> Bool? {
        guard let home = game.homeScore, let away = game.awayScore, home != away else { return nil }
        if game.homeTeamID == team { return home > away }
        if game.awayTeamID == team { return away > home }
        return nil
    }

    /// Streak headlines: only when a streak reaches 3+ and only when it has
    /// grown past what was already reported (no identical story two weeks
    /// running). Max two win-streak stories and one skid story per week.
    private static func streakNews(
        teams: [Team],
        streaks: [UUID: Int],
        state: inout LeagueNarrativeState,
        week: Int,
        season: Int
    ) -> [NewsItem] {
        var items: [NewsItem] = []

        let hotTeams = teams
            .filter { (streaks[$0.id] ?? 0) >= 3 && (streaks[$0.id] ?? 0) > (state.reportedStreaks[$0.id] ?? 0) }
            .sorted { (streaks[$0.id] ?? 0) > (streaks[$1.id] ?? 0) }
        for team in hotTeams.prefix(2) {
            let streak = streaks[team.id] ?? 0
            let headlines = [
                "\(team.fullName) make it \(streak) straight",
                "Streaking: \(team.fullName) win their \(ordinal(streak)) in a row",
                "\(team.name) stay red-hot with \(ordinal(streak)) consecutive win",
            ]
            let bodies = [
                "The \(team.fullName) (\(team.record)) extended their winning streak to \(streak) games this week. Around the league, opponents are starting to circle this matchup on the schedule.",
                "Another week, another win for the \(team.fullName). At \(streak) straight, the conversation in \(team.city) has shifted from playoffs to how far this run can go.",
                "Make it \(streak) in a row for the \(team.fullName). The locker room is buzzing, and the front office looks smarter every Sunday.",
            ]
            let idx = (week + streak) % headlines.count
            items.append(NewsItem(
                headline: headlines[idx],
                body: bodies[idx],
                category: .gameResult,
                week: week,
                season: season,
                relatedTeamID: team.id,
                sentiment: .positive
            ))
            state.reportedStreaks[team.id] = streak
        }

        let coldTeams = teams
            .filter { (streaks[$0.id] ?? 0) <= -3 && (streaks[$0.id] ?? 0) < (state.reportedStreaks[$0.id] ?? 0) }
            .sorted { (streaks[$0.id] ?? 0) < (streaks[$1.id] ?? 0) }
        if let team = coldTeams.first {
            let skid = -(streaks[team.id] ?? 0)
            let headlines = [
                "\(team.fullName) drop their \(ordinal(skid)) straight",
                "Freefall in \(team.city): \(skid) losses in a row",
                "\(team.name) can't stop the slide at \(team.record)",
            ]
            let bodies = [
                "The losses keep piling up for the \(team.fullName), now losers of \(skid) straight at \(team.record). Fans are restless and the locker room is searching for answers.",
                "It went from a rough patch to a full skid: \(skid) consecutive defeats for the \(team.fullName). Something has to change, and everyone in the building knows it.",
                "Another Sunday, another loss for the \(team.fullName). The \(skid)-game slide has turned the season's storyline from contention to survival.",
            ]
            let idx = (week + skid) % headlines.count
            items.append(NewsItem(
                headline: headlines[idx],
                body: bodies[idx],
                category: .gameResult,
                week: week,
                season: season,
                relatedTeamID: team.id,
                sentiment: .negative
            ))
            state.reportedStreaks[team.id] = -skid
        }

        return items
    }

    /// Drops markers for teams whose reported streak has been broken so the
    /// next run starts a fresh story.
    private static func pruneStreakMarkers(
        state: inout LeagueNarrativeState,
        streaks: [UUID: Int]
    ) {
        for (teamID, reported) in state.reportedStreaks {
            let current = streaks[teamID] ?? 0
            // Streak direction flipped or fizzled below the 3-game bar.
            if reported > 0 && current < 3 { state.reportedStreaks[teamID] = nil }
            if reported < 0 && current > -3 { state.reportedStreaks[teamID] = nil }
        }
    }

    // MARK: - Upsets

    /// A clear upset: a team ranked 20+ spots or 10+ spots below a previous
    /// top-10 side beats it by a touchdown or more.
    private static func upsetNews(
        teams: [Team],
        playedGames: [Game],
        previousRanks: [UUID: Int],
        week: Int,
        season: Int
    ) -> NewsItem? {
        guard !previousRanks.isEmpty else { return nil }
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        let weekGames = playedGames.filter { $0.week == week }
        var best: (winner: Team, loser: Team, margin: Int, gap: Int)?

        for game in weekGames {
            guard let winnerID = game.winnerID, let loserID = game.loserID,
                  let winner = teamsByID[winnerID], let loser = teamsByID[loserID],
                  let winnerRank = previousRanks[winnerID],
                  let loserRank = previousRanks[loserID],
                  let home = game.homeScore, let away = game.awayScore
            else { continue }

            let margin = abs(home - away)
            let gap = winnerRank - loserRank  // positive = worse team won
            guard loserRank <= 10, gap >= 10, margin >= 7 else { continue }

            if best == nil || gap > best!.gap {
                best = (winner, loser, margin, gap)
            }
        }

        guard let upset = best else { return nil }
        let headlines = [
            "Stunner: \(upset.winner.fullName) take down \(upset.loser.fullName)",
            "Upset of the week: \(upset.winner.name) shock \(upset.loser.fullName)",
            "\(upset.loser.fullName) humbled by \(upset.winner.fullName)",
        ]
        let idx = (week + upset.gap) % headlines.count
        return NewsItem(
            headline: headlines[idx],
            body: "Nobody saw this coming: the \(upset.winner.fullName) (\(upset.winner.record)) didn't just beat one of the league's best — they won by \(upset.margin). The \(upset.loser.fullName) leave with more questions than answers.",
            category: .gameResult,
            week: week,
            season: season,
            relatedTeamID: upset.winner.id,
            sentiment: .positive
        )
    }

    // MARK: - Coordinator Personas (R33)

    /// One persona-flavored defensive headline per week at most: a winner
    /// whose DC calls an EXOTIC game (see ``DCPersona/derive(for:)``) held
    /// the loser to 13 points or fewer. Picks the most smothered loser when
    /// several games qualify. Purely presentational — reads results only.
    private static func exoticDefenseNews(
        teams: [Team],
        coaches: [Coach],
        playedGames: [Game],
        week: Int,
        season: Int
    ) -> NewsItem? {
        guard !coaches.isEmpty else { return nil }
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        var best: (winner: Team, loser: Team, loserScore: Int)?
        for game in playedGames where game.week == week {
            guard let winnerID = game.winnerID, let loserID = game.loserID,
                  let winner = teamsByID[winnerID], let loser = teamsByID[loserID],
                  let home = game.homeScore, let away = game.awayScore
            else { continue }
            let loserScore = min(home, away)
            guard loserScore <= 13 else { continue }
            guard let dc = coaches.first(where: {
                $0.teamID == winnerID && $0.role == .defensiveCoordinator
            }), DCPersona.derive(for: dc) == .exotic else { continue }

            if best == nil || loserScore < best!.loserScore {
                best = (winner, loser, loserScore)
            }
        }

        guard let pick = best else { return nil }
        return NewsItem(
            headline: "Exotic defense confuses \(pick.loser.name)",
            body: "The \(pick.winner.fullName)' shape-shifting pressure packages held the \(pick.loser.fullName) to \(pick.loserScore) points. Bear fronts, mugged-up A-gaps, coverage rotating late — \(pick.loser.city) never got a clean look at any of it.",
            category: .gameResult,
            week: week,
            season: season,
            relatedTeamID: pick.winner.id,
            sentiment: .positive
        )
    }

    // MARK: - MVP Race

    /// Weekly accumulation of a heuristic MVP-race score. League-wide season
    /// stat lines aren't persisted, so the race blends team success, player
    /// quality, and positional MVP-voting bias, with light weekly variance so
    /// the order can shift without teleporting.
    private static func accumulateMVPRace(
        state: LeagueNarrativeState,
        teams: [Team],
        players: [Player],
        weekGames: [Game]
    ) -> (points: [UUID: Double], race: [MVPCandidate]) {
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        let winnersThisWeek = Set(weekGames.compactMap(\.winnerID))

        // Candidate pool: healthy stars on rosters.
        let candidates = players.filter {
            $0.teamID != nil && $0.overall >= 82 && !$0.isInjured && !$0.isHoldingOut
        }

        var points = state.mvpPoints
        for player in candidates {
            guard let teamID = player.teamID, let team = teamsByID[teamID] else { continue }
            let games = team.wins + team.losses + team.ties
            let winPct = games > 0 ? Double(team.wins) / Double(games) : 0.5

            var weekly = 0.0
            weekly += winPct * 3.0                                    // voters love winners
            weekly += Double(player.overall - 80) * 0.35              // star power
            weekly += mvpPositionWeight(player.position)              // QB-heavy award
            weekly += winnersThisWeek.contains(teamID) ? 1.2 : 0.0    // won this week
            weekly += Double.random(in: 0...1.2)                      // weekly narrative swing
            points[player.id, default: 0] += weekly
        }

        // Keep the table small: only the 12 strongest cases persist.
        let kept = points.sorted { $0.value > $1.value }.prefix(12)
        points = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })

        let playersByID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        let race: [MVPCandidate] = kept.prefix(3).compactMap { entry in
            guard let player = playersByID[entry.key] else { return nil }
            let abbr = player.teamID.flatMap { teamsByID[$0]?.abbreviation } ?? "FA"
            return MVPCandidate(
                playerID: player.id,
                playerName: player.fullName,
                teamID: player.teamID,
                teamAbbr: abbr,
                positionRaw: player.position.rawValue,
                points: entry.value
            )
        }

        return (points, race)
    }

    /// MVP voting is QB-dominated; skill positions trail, defenders rarely win.
    private static func mvpPositionWeight(_ position: Position) -> Double {
        switch position {
        case .QB:       return 3.0
        case .RB:       return 1.8
        case .WR:       return 1.4
        case .TE:       return 1.0
        case .DE, .OLB: return 0.9
        default:        return 0.6
        }
    }

    private static func mvpRaceNews(
        race: [MVPCandidate],
        week: Int,
        season: Int
    ) -> NewsItem {
        let leader = race[0]
        let headlines = [
            "MVP watch: \(leader.playerName) leads the field",
            "MVP race check-in: \(leader.playerName) out front",
            "The MVP conversation runs through \(leader.teamAbbr)",
        ]
        let names = race.enumerated()
            .map { "\($0.offset + 1). \($0.element.playerName) (\($0.element.positionRaw), \($0.element.teamAbbr))" }
            .joined(separator: ", ")
        return NewsItem(
            headline: headlines[week % headlines.count],
            body: "With the season heating up, the award chatter has a clear shape: \(names). Voters reward winning — every result from here shifts the math.",
            category: .award,
            week: week,
            season: season,
            relatedTeamID: leader.teamID,
            relatedPlayerID: leader.playerID,
            sentiment: .neutral
        )
    }

    // MARK: - Division Races

    /// Late-season rivalry framing: two teams neck-and-neck atop a division.
    /// Each pairing gets one big story per season.
    private static func divisionRaceNews(
        teams: [Team],
        state: inout LeagueNarrativeState,
        week: Int,
        season: Int
    ) -> NewsItem? {
        var candidates: [(a: Team, b: Team)] = []

        for conference in Conference.allCases {
            for division in Division.allCases {
                let divTeams = teams
                    .filter { $0.conference == conference && $0.division == division }
                    .sorted { winPct($0) > winPct($1) }
                guard divTeams.count >= 2 else { continue }
                let first = divTeams[0], second = divTeams[1]
                guard winPct(first) >= 0.55, abs(first.wins - second.wins) <= 1 else { continue }

                let key = [first.id.uuidString, second.id.uuidString].sorted().joined(separator: "|")
                guard !state.divisionRacesReported.contains(key) else { continue }
                candidates.append((first, second))
            }
        }

        guard !candidates.isEmpty else { return nil }
        let pick = candidates[week % candidates.count]
        let key = [pick.a.id.uuidString, pick.b.id.uuidString].sorted().joined(separator: "|")
        state.divisionRacesReported.insert(key)

        let divisionLabel = "\(pick.a.conference.rawValue) \(pick.a.division.rawValue)"
        let headlines = [
            "\(divisionLabel) race goes down to the wire",
            "Two-horse race: \(pick.a.name) and \(pick.b.name) trade blows",
            "The \(divisionLabel) will be settled in the trenches",
        ]
        return NewsItem(
            headline: headlines[week % headlines.count],
            body: "The \(pick.a.fullName) (\(pick.a.record)) and the \(pick.b.fullName) (\(pick.b.record)) are separated by a hair atop the \(divisionLabel). With the schedule tightening, every snap between now and January carries division-title weight.",
            category: .teamRanking,
            week: week,
            season: season,
            relatedTeamID: pick.a.id,
            sentiment: .neutral
        )
    }

    private static func winPct(_ team: Team) -> Double {
        let games = team.wins + team.losses + team.ties
        guard games > 0 else { return 0.0 }
        return (Double(team.wins) + 0.5 * Double(team.ties)) / Double(games)
    }

    // MARK: - Season Arc (User Team)

    /// Expectations-vs-reality checkpoints for the user's team at weeks 6, 12
    /// and 16, using the owner's stated season goals as the yardstick.
    private static func seasonArcNews(
        teams: [Team],
        career: Career,
        state: inout LeagueNarrativeState,
        week: Int,
        season: Int
    ) -> NewsItem? {
        let checkpoints: Set<Int> = [6, 12, 16]
        guard checkpoints.contains(week), !state.arcCheckpointsDone.contains(week),
              let teamID = career.teamID,
              let team = teams.first(where: { $0.id == teamID }),
              let goals = career.seasonGoals
        else { return nil }

        state.arcCheckpointsDone.insert(week)

        let played = team.wins + team.losses + team.ties
        guard played > 0 else { return nil }
        let projectedWins = Double(team.wins) * 18.0 / Double(played)
        let expectedWins: Double = {
            switch goals.ownerExpectation {
            case .superBowl:     return 12
            case .conference:    return 11
            case .playoff:       return 10
            case .winningRecord: return 9.5
            case .development:   return 7
            case .rebuild:       return 5
            }
        }()

        let delta = projectedWins - expectedWins
        if delta >= 2 {
            let headlines = [
                "\(team.fullName) running ahead of schedule",
                "Expectations rising in \(team.city)",
                "\(team.name) outperforming the preseason script",
            ]
            return NewsItem(
                headline: headlines[week % headlines.count],
                body: "At \(team.record), the \(team.fullName) are tracking well ahead of the front office's stated goal (\"\(goals.primaryGoal)\"). Ownership is thrilled — and quietly recalibrating what success looks like this year.",
                category: .teamRanking,
                week: week,
                season: season,
                relatedTeamID: team.id,
                sentiment: .positive
            )
        } else if delta <= -2 {
            let headlines = [
                "Reality check: \(team.fullName) off the pace",
                "\(team.city) grows impatient with the \(team.name)",
                "\(team.fullName) chasing their own expectations",
            ]
            return NewsItem(
                headline: headlines[week % headlines.count],
                body: "The goal in \(team.city) was clear — \"\(goals.primaryGoal)\" — but at \(team.record) the math is getting uncomfortable. The coming weeks will decide whether this season is a slow start or a broken promise.",
                category: .teamRanking,
                week: week,
                season: season,
                relatedTeamID: team.id,
                sentiment: .negative
            )
        } else if week == 12 {
            // Mid-season on-track note (only once, at the natural midpoint).
            return NewsItem(
                headline: "\(team.fullName) tracking with expectations",
                body: "At \(team.record), the \(team.fullName) are roughly where the front office said they'd be (\"\(goals.primaryGoal)\"). No fireworks, no crisis — just a season unfolding on script.",
                category: .teamRanking,
                week: week,
                season: season,
                relatedTeamID: team.id,
                sentiment: .neutral
            )
        }
        return nil
    }

    // MARK: - Hot Seat

    /// One coach hot-seat story per struggling AI team per season, once the
    /// record makes the narrative credible (4+ games under .500 from week 6).
    private static func hotSeatNews(
        teams: [Team],
        career: Career,
        state: inout LeagueNarrativeState,
        week: Int,
        season: Int
    ) -> NewsItem? {
        let strugglers = teams
            .filter {
                $0.id != career.teamID
                    && $0.losses - $0.wins >= 4
                    && !state.hotSeatReported.contains($0.id)
            }
            .sorted { ($0.losses - $0.wins) > ($1.losses - $1.wins) }

        guard let team = strugglers.first else { return nil }
        state.hotSeatReported.insert(team.id)

        let headlines = [
            "Hot seat watch: patience wearing thin in \(team.city)",
            "\(team.fullName) coaching staff under scrutiny",
            "Sources: \(team.city) ownership 'evaluating everything'",
        ]
        return NewsItem(
            headline: headlines[week % headlines.count],
            body: "At \(team.record), the \(team.fullName) have fallen far short of what ownership expected when the season kicked off. League sources say the front office has started sketching contingency plans for the offseason — and the staff knows it.",
            category: .coachingChange,
            week: week,
            season: season,
            relatedTeamID: team.id,
            sentiment: .negative
        )
    }

    // MARK: - Helpers

    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }
}

// MARK: - Private Numeric Helper

private extension Double {
    /// Local clamp (namespaced to avoid colliding with other extensions).
    func clampedNarrative(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
