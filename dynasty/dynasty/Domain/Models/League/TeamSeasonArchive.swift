import Foundation
import SwiftData

// MARK: - Playoff Result

/// How far a team got in January. Ordered from "stayed home" to "won it all"
/// so a comparison is a legitimate ranking of two seasons.
enum PlayoffResult: String, Codable, CaseIterable, Comparable {
    case missed
    case wildCard
    case divisional
    case conference
    case runnerUp
    case champion

    /// Sort weight; also the "how good was this season" ladder.
    var rank: Int {
        switch self {
        case .missed:     return 0
        case .wildCard:   return 1
        case .divisional: return 2
        case .conference: return 3
        case .runnerUp:   return 4
        case .champion:   return 5
        }
    }

    var label: String {
        switch self {
        case .missed:     return "Missed Playoffs"
        case .wildCard:   return "Lost Wild Card"
        case .divisional: return "Lost Divisional"
        case .conference: return "Lost Conf. Title"
        case .runnerUp:   return "Lost Super Bowl"
        case .champion:   return "SUPER BOWL CHAMPS"
        }
    }

    /// Short form for a dense archive row.
    var shortLabel: String {
        switch self {
        case .missed:     return "—"
        case .wildCard:   return "WC"
        case .divisional: return "DIV"
        case .conference: return "CONF"
        case .runnerUp:   return "SB L"
        case .champion:   return "CHAMPS"
        }
    }

    var madePlayoffs: Bool { self != .missed }

    static func < (lhs: PlayoffResult, rhs: PlayoffResult) -> Bool { lhs.rank < rhs.rank }
}

// MARK: - Team Season Archive (TODO §5.2)

/// One completed season for ONE franchise — record, finish, roster strength and
/// the staff that ran it.
///
/// Before this existed, the only per-team memory in the game was
/// `Team.lastSeasonWins`: a single integer, one year deep, for the user's club
/// and the other 31 alike. That is enough to ask "did they collapse last year?"
/// and nothing else — no trend, no dynasty, no coach's track record, no
/// "fourth straight losing season in Cleveland". `Career.seasonSummaries`
/// (`SeasonSummary`) is the league-level book: champion, the USER's record, the
/// MVP. This is the franchise-level book, thirty-two rows a season.
///
/// ## Everything here is derived, nothing is opinion
///
/// The record, the seeding, the division rank and the playoff finish all come
/// out of the season's `Game` rows through `StandingsCalculator` — the same
/// tiebreakers the standings screen and the playoff bracket use, so an archive
/// row can never disagree with the bracket that produced it. Roster strength
/// comes from that season's `PlayerSeasonHistory` snapshots (the ratings as
/// they were, not as they are now), and the staff names are snapshotted as
/// text because a coach who was fired three seasons ago must still be the coach
/// this row remembers.
///
/// ## Identity is snapshotted on purpose
///
/// `teamAbbr` / `teamName` are stored rather than joined: the archive has to
/// render after a relocation or rename, and after the `Team` row itself is
/// gone. Same reasoning as `HallOfFameEntry`.
@Model
final class TeamSeasonArchive {

    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    #Index<TeamSeasonArchive>([\.careerID])

    /// The franchise this season belongs to.
    var teamID: UUID

    /// Calendar season year (e.g. 2026).
    var season: Int

    // MARK: - Identity snapshot

    var teamAbbr: String
    /// City + nickname as it read that season.
    var teamName: String
    var conferenceRaw: String
    var divisionRaw: String

    // MARK: - Record

    var wins: Int
    var losses: Int
    var ties: Int
    var pointsFor: Int
    var pointsAgainst: Int

    /// 1-4 within the team's own division (`StandingsCalculator` tiebreakers).
    var divisionRank: Int

    /// 1-7 conference playoff seed; `0` when the team missed the bracket.
    var conferenceSeed: Int

    /// Raw `PlayoffResult`.
    var playoffResultRaw: String

    // MARK: - Roster

    /// Average end-of-season overall across the players who finished the season
    /// on this roster — the ratings AS THEY WERE, from `PlayerSeasonHistory`.
    var avgOverall: Double

    /// How many players that average is over (0 when the season predates the
    /// history rows, in which case `avgOverall` is 0 and the UI omits it).
    var rosterCount: Int

    // MARK: - Staff

    var headCoachName: String
    var offensiveCoordinatorName: String
    var defensiveCoordinatorName: String

    // MARK: - Flags & colour

    /// True when this was the user's own franchise that season.
    var isUserTeam: Bool

    /// Short, factual sentences about the season — the longest streak, the
    /// biggest win, a division title. Derived from the game log, never invented.
    var notableEvents: [String] = []

    // MARK: - Computed

    var playoffResult: PlayoffResult {
        PlayoffResult(rawValue: playoffResultRaw) ?? .missed
    }

    var recordText: String {
        ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
    }

    var pointDifferential: Int { pointsFor - pointsAgainst }

    /// Ties count as half a win, same as `StandingsRecord`.
    var winPercentage: Double {
        let games = wins + losses + ties
        guard games > 0 else { return 0 }
        return (Double(wins) + Double(ties) * 0.5) / Double(games)
    }

    var wonDivision: Bool { divisionRank == 1 }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        teamID: UUID,
        season: Int,
        teamAbbr: String,
        teamName: String,
        conferenceRaw: String,
        divisionRaw: String,
        wins: Int,
        losses: Int,
        ties: Int,
        pointsFor: Int,
        pointsAgainst: Int,
        divisionRank: Int,
        conferenceSeed: Int,
        playoffResult: PlayoffResult,
        avgOverall: Double,
        rosterCount: Int,
        headCoachName: String,
        offensiveCoordinatorName: String,
        defensiveCoordinatorName: String,
        isUserTeam: Bool,
        notableEvents: [String]
    ) {
        self.id = id
        self.teamID = teamID
        self.season = season
        self.teamAbbr = teamAbbr
        self.teamName = teamName
        self.conferenceRaw = conferenceRaw
        self.divisionRaw = divisionRaw
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.pointsFor = pointsFor
        self.pointsAgainst = pointsAgainst
        self.divisionRank = divisionRank
        self.conferenceSeed = conferenceSeed
        self.playoffResultRaw = playoffResult.rawValue
        self.avgOverall = avgOverall
        self.rosterCount = rosterCount
        self.headCoachName = headCoachName
        self.offensiveCoordinatorName = offensiveCoordinatorName
        self.defensiveCoordinatorName = defensiveCoordinatorName
        self.isUserTeam = isUserTeam
        self.notableEvents = notableEvents
    }
}

// MARK: - Team Season Archive Builder

/// Derives `TeamSeasonArchive` rows from a finished season, and persists them
/// idempotently.
///
/// ## Where this is called from
///
/// The archive belongs at the season rollover, next to `recordSeasonSummary`
/// in `WeekAdvancer`'s `.superBowl` phase — that is the moment every input is
/// simultaneously true (the regular-season records are intact, the bracket has
/// been played out, and the staff has not yet been through the carousel).
/// ``record(career:teams:modelContext:)`` is that entry point and is safe to
/// call there directly.
///
/// Until it is wired there, ``backfill(career:modelContext:)`` keeps the
/// feature honest on its own: it harvests every season still on the books that
/// has a complete game log and no archive rows yet, and the League History
/// screen calls it when it opens. Both paths run through the same derivation,
/// both are idempotent per (career, team, season), so wiring the rollover later
/// changes nothing except WHEN the row appears.
///
/// ## Why the record is re-derived instead of read off `Team`
///
/// `Team.wins` is live and gets zeroed by `startNewSeason`, so it is only the
/// truth inside the `.superBowl` window. The game log is the truth forever.
/// Deriving from games makes the rollover path and the catch-up path produce
/// byte-identical rows, which is what makes them interchangeable.
enum TeamSeasonArchiveBuilder {

    /// Seasons a catch-up pass will look back over. The store only keeps the
    /// current and previous season's games (`purgeStaleSeasonData`), so this is
    /// generous rather than load-bearing.
    private static let backfillLookback = 3

    // MARK: - Pure derivation

    /// Builds one archive row per team from a completed season's game log.
    /// PURE: touches no context, inserts nothing, reads nothing global.
    ///
    /// - Parameters:
    ///   - season: The season year being archived.
    ///   - teams: All teams in the league.
    ///   - games: Every `Game` of that season (regular + playoff, played or not).
    ///   - coaches: The staff as it stood when the season ended.
    ///   - history: That season's `PlayerSeasonHistory` rows, for roster strength.
    ///     Pass an empty array when they do not exist; `avgOverall` reads 0 and
    ///     the UI omits it rather than inventing a rating.
    ///   - userTeamID: The user's franchise, for the `isUserTeam` flag.
    /// - Returns: 32 unattached rows (the caller inserts and stamps them), or
    ///   an empty array when the season is not actually finished.
    static func build(
        season: Int,
        teams: [Team],
        games: [Game],
        coaches: [Coach],
        history: [PlayerSeasonHistory],
        userTeamID: UUID?
    ) -> [TeamSeasonArchive] {
        guard !teams.isEmpty else { return [] }

        let regularSeason = games.filter { !$0.isPlayoff }
        let playedRegular = regularSeason.filter(\.isPlayed)
        // A season nobody finished is not an archive — half a year of results
        // would read as a franchise-record collapse forever.
        guard !playedRegular.isEmpty, playedRegular.count >= regularSeason.count else { return [] }

        let records = StandingsCalculator.calculate(games: games, teams: teams)
        let recordByTeam = Dictionary(records.map { ($0.teamID, $0) }, uniquingKeysWith: { a, _ in a })

        // Division rank + conference seed, both straight off the shared
        // tiebreaker so the archive and the bracket can never disagree.
        var divisionRank: [UUID: Int] = [:]
        var conferenceSeed: [UUID: Int] = [:]
        for conference in Conference.allCases {
            for division in Division.allCases {
                let standing = StandingsCalculator.divisionStandings(
                    records: records, teams: teams, conference: conference, division: division
                )
                for (index, row) in standing.enumerated() { divisionRank[row.teamID] = index + 1 }
            }
            let seeds = StandingsCalculator.playoffTeams(
                records: records, teams: teams, conference: conference
            )
            for (index, row) in seeds.enumerated() { conferenceSeed[row.teamID] = index + 1 }
        }

        let playoffResults = playoffFinishes(games: games)
        let strength = rosterStrength(history: history)
        let staff = staffNames(coaches: coaches)
        let leagueDifferentials = records.map { ($0.teamID, $0.pointDifferential) }
        let bestDifferential = leagueDifferentials.max { $0.1 < $1.1 }?.1 ?? 0
        let worstDifferential = leagueDifferentials.min { $0.1 < $1.1 }?.1 ?? 0

        return teams.map { team in
            let record = recordByTeam[team.id] ?? StandingsRecord(teamID: team.id)
            let finish = playoffResults[team.id] ?? .missed
            let rank = divisionRank[team.id] ?? 4
            let seed = conferenceSeed[team.id] ?? 0
            let people = staff[team.id] ?? StaffNames()

            return TeamSeasonArchive(
                teamID: team.id,
                season: season,
                teamAbbr: team.abbreviation,
                teamName: team.fullName,
                conferenceRaw: team.conference.rawValue,
                divisionRaw: team.division.rawValue,
                wins: record.wins,
                losses: record.losses,
                ties: record.ties,
                pointsFor: record.pointsFor,
                pointsAgainst: record.pointsAgainst,
                divisionRank: rank,
                conferenceSeed: seed,
                playoffResult: finish,
                avgOverall: strength[team.id]?.average ?? 0,
                rosterCount: strength[team.id]?.count ?? 0,
                headCoachName: people.headCoach,
                offensiveCoordinatorName: people.offensiveCoordinator,
                defensiveCoordinatorName: people.defensiveCoordinator,
                isUserTeam: team.id == userTeamID,
                notableEvents: notableEvents(
                    team: team,
                    record: record,
                    divisionRank: rank,
                    finish: finish,
                    playedRegular: playedRegular,
                    bestDifferential: bestDifferential,
                    worstDifferential: worstDifferential
                )
            )
        }
    }

    // MARK: - Persistence

    /// Archives `season` (defaults to the career's current one) exactly once.
    /// Idempotent per (career, team, season): a second call is a fetch and a
    /// return.
    ///
    /// Intended rollover call site — `WeekAdvancer`, `.superBowl` phase,
    /// immediately after `recordSeasonSummary`:
    /// ```
    /// TeamSeasonArchiveBuilder.record(career: career, teams: teams, modelContext: modelContext)
    /// ```
    ///
    /// - Returns: How many rows were written (0 when already archived, or when
    ///   the season's game log is incomplete).
    @discardableResult
    static func record(
        career: Career,
        teams: [Team],
        modelContext: ModelContext,
        season: Int? = nil
    ) -> Int {
        let year = season ?? career.currentSeason
        let cid = career.id
        guard !isArchived(careerID: cid, season: year, modelContext: modelContext) else { return 0 }

        let games = fetchGames(careerID: cid, season: year, modelContext: modelContext)
        let coaches = fetch(Coach.self, careerID: cid, modelContext: modelContext)
        let history = fetchHistory(careerID: cid, season: year, modelContext: modelContext)

        let rows = build(
            season: year,
            teams: teams,
            games: games,
            coaches: coaches,
            history: history,
            userTeamID: career.teamID
        )
        guard !rows.isEmpty else { return 0 }

        for row in rows {
            CareerScope.stamp(row, careerID: cid)
            modelContext.insert(row)
        }
        return rows.count
    }

    /// Catch-up pass: archives every finished season still on the books that
    /// has no archive rows yet. Cheap and idempotent — one count query per
    /// candidate season, and nothing at all once the archive is current.
    ///
    /// This exists so the franchise history is real in a save whose rollover
    /// predates the archive (and while the rollover call site is still a
    /// handoff). It can only reach as far back as the game log does.
    ///
    /// ## One thing it cannot reconstruct
    ///
    /// Records, finishes and roster ratings are all recovered exactly — they
    /// live in `Game` rows and `PlayerSeasonHistory` snapshots. The STAFF does
    /// not: coaches carry only their current job, so a catch-up pass run after
    /// the coaching carousel credits last season to whoever holds the seat now.
    /// Calling ``record(career:teams:modelContext:season:)`` at the rollover,
    /// before the carousel, is what makes the staff line exact — the one thing
    /// that is actually lost by leaving the archive to the catch-up path.
    @discardableResult
    static func backfill(career: Career, modelContext: ModelContext) -> Int {
        let cid = career.id
        // The season in progress has no finished game log; start one back.
        let newest = career.currentSeason - 1
        guard newest >= 1 else { return 0 }

        var teams: [Team]?
        var written = 0
        for year in stride(from: newest, through: max(1, newest - backfillLookback + 1), by: -1) {
            guard !isArchived(careerID: cid, season: year, modelContext: modelContext) else { continue }
            // Resolve the roster of teams once, and only if there is work.
            let resolved: [Team]
            if let teams { resolved = teams } else {
                let fetched = fetch(Team.self, careerID: cid, modelContext: modelContext)
                teams = fetched
                resolved = fetched
            }
            written += record(career: career, teams: resolved, modelContext: modelContext, season: year)
        }
        return written
    }

    // MARK: - Reads

    /// Archives for one franchise, newest season first.
    static func archives(
        careerID: UUID,
        teamID: UUID,
        modelContext: ModelContext
    ) -> [TeamSeasonArchive] {
        var descriptor = FetchDescriptor<TeamSeasonArchive>(
            predicate: #Predicate<TeamSeasonArchive> {
                $0.careerID == careerID && $0.teamID == teamID
            },
            sortBy: [SortDescriptor(\.season, order: .reverse)]
        )
        descriptor.fetchLimit = 40
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Every archived row for a save, newest season first. Used by the
    /// narrative engine, which needs the whole league to spot a dynasty.
    static func allArchives(careerID: UUID, modelContext: ModelContext) -> [TeamSeasonArchive] {
        let descriptor = FetchDescriptor<TeamSeasonArchive>(
            predicate: #Predicate<TeamSeasonArchive> { $0.careerID == careerID },
            sortBy: [SortDescriptor(\.season, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Private: derivation helpers

    /// How far each team got, read off the bracket's own game rows.
    /// Week 19 = wild card, 20 = divisional, 21 = conference title, 22 = Super
    /// Bowl (`WeekAdvancer.ensurePlayoffGames`).
    private static func playoffFinishes(games: [Game]) -> [UUID: PlayoffResult] {
        var finishes: [UUID: PlayoffResult] = [:]

        /// A team's finish is the deepest round it appeared in, so a later
        /// round overwrites an earlier one and the ladder only moves up.
        /// Game order is irrelevant because the move is monotonic.
        func promote(_ teamID: UUID, to result: PlayoffResult) {
            if let existing = finishes[teamID], existing >= result { return }
            finishes[teamID] = result
        }

        for game in games where game.isPlayoff && game.isPlayed {
            let reached: PlayoffResult
            switch game.week {
            case 19: reached = .wildCard
            case 20: reached = .divisional
            case 21: reached = .conference
            case 22: reached = .runnerUp
            default: continue
            }
            promote(game.homeTeamID, to: reached)
            promote(game.awayTeamID, to: reached)
            if game.week == 22, let winner = game.winnerID {
                promote(winner, to: .champion)
            }
        }
        return finishes
    }

    private struct RosterStrength {
        var total: Int = 0
        var count: Int = 0
        var average: Double { count > 0 ? Double(total) / Double(count) : 0 }
    }

    /// End-of-season average overall per team, from that season's snapshots.
    private static func rosterStrength(history: [PlayerSeasonHistory]) -> [UUID: RosterStrength] {
        var byTeam: [UUID: RosterStrength] = [:]
        for row in history {
            guard let teamID = row.teamID else { continue }
            byTeam[teamID, default: RosterStrength()].total += row.overallAtEndOfSeason
            byTeam[teamID, default: RosterStrength()].count += 1
        }
        return byTeam
    }

    private struct StaffNames {
        var headCoach: String = "—"
        var offensiveCoordinator: String = "—"
        var defensiveCoordinator: String = "—"
    }

    private static func staffNames(coaches: [Coach]) -> [UUID: StaffNames] {
        var byTeam: [UUID: StaffNames] = [:]
        for coach in coaches {
            guard let teamID = coach.teamID else { continue }
            var entry = byTeam[teamID] ?? StaffNames()
            switch coach.role {
            case .headCoach:              entry.headCoach = coach.fullName
            case .offensiveCoordinator:   entry.offensiveCoordinator = coach.fullName
            case .defensiveCoordinator:   entry.defensiveCoordinator = coach.fullName
            default:                      continue
            }
            byTeam[teamID] = entry
        }
        return byTeam
    }

    /// Two or three short, factual lines about the season. Everything here is
    /// counted off the game log — no adjectives that the record does not earn.
    private static func notableEvents(
        team: Team,
        record: StandingsRecord,
        divisionRank: Int,
        finish: PlayoffResult,
        playedRegular: [Game],
        bestDifferential: Int,
        worstDifferential: Int
    ) -> [String] {
        var events: [String] = []

        if finish == .champion {
            events.append("Won the Super Bowl.")
        } else if finish == .runnerUp {
            events.append("Reached the Super Bowl and lost.")
        } else if divisionRank == 1 {
            events.append("Won the \(team.conference.rawValue) \(team.division.rawValue).")
        }

        let teamGames = playedRegular
            .filter { $0.homeTeamID == team.id || $0.awayTeamID == team.id }
            .sorted { $0.week < $1.week }
        let (bestWin, worstSkid) = longestRuns(teamID: team.id, games: teamGames)
        if bestWin >= 5 {
            events.append("Won \(bestWin) straight at one point.")
        } else if worstSkid >= 5 {
            events.append("Lost \(worstSkid) in a row.")
        }

        if record.pointDifferential == bestDifferential, bestDifferential > 0 {
            events.append("Best point differential in the league (+\(bestDifferential)).")
        } else if record.pointDifferential == worstDifferential, worstDifferential < 0 {
            events.append("Worst point differential in the league (\(worstDifferential)).")
        }

        return Array(events.prefix(3))
    }

    /// Longest winning and losing runs inside one team's season.
    private static func longestRuns(teamID: UUID, games: [Game]) -> (wins: Int, losses: Int) {
        var bestWin = 0, bestLoss = 0, runWin = 0, runLoss = 0
        for game in games {
            guard let home = game.homeScore, let away = game.awayScore else { continue }
            let isHome = game.homeTeamID == teamID
            let own = isHome ? home : away
            let opponent = isHome ? away : home
            if own > opponent {
                runWin += 1; runLoss = 0
            } else if own < opponent {
                runLoss += 1; runWin = 0
            } else {
                runWin = 0; runLoss = 0
            }
            bestWin = max(bestWin, runWin)
            bestLoss = max(bestLoss, runLoss)
        }
        return (bestWin, bestLoss)
    }

    // MARK: - Private: fetches

    private static func isArchived(careerID: UUID, season: Int, modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TeamSeasonArchive>(
            predicate: #Predicate<TeamSeasonArchive> {
                $0.careerID == careerID && $0.season == season
            }
        )
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private static func fetchGames(careerID: UUID, season: Int, modelContext: ModelContext) -> [Game] {
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate<Game> {
                $0.careerID == careerID && $0.seasonYear == season
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchHistory(
        careerID: UUID,
        season: Int,
        modelContext: ModelContext
    ) -> [PlayerSeasonHistory] {
        let descriptor = FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate<PlayerSeasonHistory> {
                $0.careerID == careerID && $0.season == season
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetch<T: PersistentModel & CareerScoped>(
        _ type: T.Type,
        careerID: UUID,
        modelContext: ModelContext
    ) -> [T] {
        // The predicate is written per concrete type on purpose — a generic one
        // over `CareerScoped` compiles and then fails at runtime (see the note
        // on `CareerScope.cascadeDelete`).
        let all = (try? modelContext.fetch(FetchDescriptor<T>())) ?? []
        return all.filter { $0.careerID == careerID }
    }
}
