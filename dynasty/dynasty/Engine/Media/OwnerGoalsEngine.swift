import Foundation
import SwiftData

// MARK: - Supporting Types

struct SeasonGoal: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let type: GoalType
    let target: Int?   // e.g., wins target, or nil for boolean goals
    var progress: Int
    var isAchieved: Bool
    let priority: GoalPriority

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        type: GoalType,
        target: Int? = nil,
        progress: Int = 0,
        isAchieved: Bool = false,
        priority: GoalPriority
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.type = type
        self.target = target
        self.progress = progress
        self.isAchieved = isAchieved
        self.priority = priority
    }
}

enum GoalType: String, Codable {
    case wins, playoffs, divisionTitle, conference, superBowl,
         developRookies, reduceCapUsage, improveDraft, winStreak,
         fanSatisfaction, tradeAcquisition
}

enum GoalPriority: String, Codable {
    case primary, secondary, bonus
}

// MARK: - OwnerGoalsEngine

enum OwnerGoalsEngine {

    // MARK: - Goal Generation

    /// Generates 3–4 season goals tailored to the team's strength,
    /// the owner's personality, and the current career context.
    static func generateSeasonGoals(team: Team, owner: Owner, career: Career) -> [SeasonGoal] {
        // S3 (TRADE_OVERHAUL_PLAN §4/§7.5): roster strength off the `teamID`
        // query, one fetch per goal-generation pass (once a season / once per
        // owner screen), never the stale `Team.players` relationship.
        let avgOverall = averageOverall(roster: team.currentRoster())
        var goals: [SeasonGoal] = []

        if avgOverall > 75 {
            // Good team — push for a championship
            goals.append(contenderPrimaryGoal(owner: owner))
            goals.append(
                SeasonGoal(
                    title: "Win 12+ Games",
                    description: "Prove your team belongs among the NFL elite with a dominant regular season.",
                    type: .wins,
                    target: 12,
                    priority: .secondary
                )
            )
            goals.append(
                SeasonGoal(
                    title: "Win the Division",
                    description: "Secure home-field advantage and divisional supremacy.",
                    type: .divisionTitle,
                    priority: .bonus
                )
            )

        } else if avgOverall >= 65 {
            // Middle-of-the-pack — playoffs are the realistic ceiling
            goals.append(
                SeasonGoal(
                    title: "Make the Playoffs",
                    description: "\(owner.name) expects a playoff berth this season. Don't keep the boss waiting.",
                    type: .playoffs,
                    priority: .primary
                )
            )
            goals.append(
                SeasonGoal(
                    title: "Win 9+ Games",
                    description: "A nine-win season demonstrates real progress and silences doubters.",
                    type: .wins,
                    target: 9,
                    priority: .secondary
                )
            )
            goals.append(
                SeasonGoal(
                    title: "Win the Division",
                    description: "Capturing the division title would be a franchise milestone.",
                    type: .divisionTitle,
                    priority: .bonus
                )
            )

        } else {
            // Rebuilding team — focus on development and stability
            if owner.prefersWinNow {
                // Impatient owner still wants a win target
                goals.append(
                    SeasonGoal(
                        title: "Win 6+ Games",
                        description: "\(owner.name) demands progress — at least six wins this season.",
                        type: .wins,
                        target: 6,
                        priority: .primary
                    )
                )
            } else {
                goals.append(
                    SeasonGoal(
                        title: "Develop 3 Rookies",
                        description: "Build the future by getting meaningful snaps for at least three rookies.",
                        type: .developRookies,
                        target: 3,
                        priority: .primary
                    )
                )
            }

            goals.append(
                SeasonGoal(
                    title: "Stay Under the Cap",
                    description: "Maintain financial flexibility heading into future free agency periods.",
                    type: .reduceCapUsage,
                    priority: .secondary
                )
            )

            if !owner.prefersWinNow {
                goals.append(
                    SeasonGoal(
                        title: "Win 6+ Games",
                        description: "Show tangible on-field improvement from last season.",
                        type: .wins,
                        target: 6,
                        priority: .bonus
                    )
                )
            } else {
                goals.append(
                    SeasonGoal(
                        title: "Win 9+ Games",
                        description: "\(owner.name) is not satisfied with a pure rebuild. Push for nine wins.",
                        type: .wins,
                        target: 9,
                        priority: .bonus
                    )
                )
            }
        }

        // Win-now owners always want a stretch win-streak goal appended
        if owner.prefersWinNow && avgOverall >= 65 {
            goals.append(
                SeasonGoal(
                    title: "Win 3 Straight",
                    description: "Demonstrate consistency by putting together a mid-season win streak.",
                    type: .winStreak,
                    target: 3,
                    priority: .bonus
                )
            )
        }

        // R31: the owner's archetype hardens or softens numeric win targets —
        // a Win-Now Tycoon demands an extra win, a Patient Builder accepts one less.
        let adjustment = OwnerPersonaEngine.OwnerArchetype.from(owner).winTargetAdjustment
        if adjustment != 0 {
            goals = goals.map { goal in
                guard goal.type == .wins, let target = goal.target else { return goal }
                let newTarget = min(13, max(5, target + adjustment))
                guard newTarget != target else { return goal }
                return SeasonGoal(
                    id: goal.id,
                    title: "Win \(newTarget)+ Games",
                    description: "\(owner.name) expects at least \(newTarget) wins this season.",
                    type: .wins,
                    target: newTarget,
                    progress: goal.progress,
                    isAchieved: goal.isAchieved,
                    priority: goal.priority
                )
            }
        }

        return Array(goals.prefix(4))
    }

    // MARK: - Progress Evaluation

    /// Re-evaluates each goal's progress against current team state and marks
    /// goals achieved or failed where applicable.
    ///
    /// ## TODO §5.6 — the proxies are gone
    ///
    /// Four of these goals used to be guesses, and two of them were wrong in a
    /// way the player could see:
    ///
    /// - **Playoffs / Conference / Super Bowl** read `career.playoffAppearances`
    ///   and `career.championships`, which are CAREER-LONG counters. One playoff
    ///   berth in season 1 marked the playoff goal achieved in every season
    ///   afterwards, forever, no matter how the team was actually doing. Now
    ///   they read this season's bracket: seeded top 7, won the conference
    ///   title game (week 21), won the Super Bowl (week 22).
    /// - **Division title** was `wins >= 11 && playoffAppearances > 0` — a team
    ///   could win its division at 9-8 and be told it hadn't, or go 11-6 second
    ///   in the division and be told it had. Now it is the division rank from
    ///   `StandingsCalculator`, the same tiebreaker chain the standings screen
    ///   and the playoff bracket use.
    /// - **Win streak** was `wins - losses`, which is not a streak at all: a
    ///   team alternating W/L all year reported a "3-game streak" at 10-7. Now
    ///   it is the longest actual run of consecutive wins in the game log.
    ///
    /// - Parameters:
    ///   - leagueTeams: All teams, when the caller already holds them. `nil`
    ///     fetches them from the team's own context.
    ///   - seasonGames: This season's full schedule, same deal. Callers inside
    ///     a week-advance already have both and should pass them.
    static func evaluateGoalProgress(
        goals: [SeasonGoal],
        team: Team,
        career: Career,
        leagueTeams: [Team]? = nil,
        seasonGames: [Game]? = nil
    ) -> [SeasonGoal] {
        // S3: the roster is resolved by `teamID` ONCE per evaluation pass
        // (once per week advance / owner screen) — never inside the map, so a
        // four-goal slate never fetches four times, and a slate with no
        // roster-shaped goal never fetches at all.
        let roster = goals.contains { $0.type == .developRookies }
            ? team.currentRoster()
            : []

        // Same rule for the standings: derived once, and only when a goal in
        // this slate actually asks a standings question.
        let needsStandings = goals.contains { standingsGoalTypes.contains($0.type) }
        let facts = needsStandings
            ? seasonFacts(team: team, career: career, leagueTeams: leagueTeams, seasonGames: seasonGames)
            : nil

        return goals.map { goal in
            var updated = goal

            switch goal.type {

            case .wins:
                updated.progress = team.wins
                if let target = goal.target {
                    updated.isAchieved = team.wins >= target
                }

            case .playoffs:
                // This season's bracket, not the career's ledger.
                updated.progress = (facts?.madePlayoffs ?? false) ? 1 : 0
                updated.isAchieved = facts?.madePlayoffs ?? false

            case .divisionTitle:
                // Rank among the division, exactly as the standings screen
                // orders it. Progress stays 1/0 like every other boolean goal —
                // the UI's "at risk" test for a target-less goal is
                // `progress == 0`, so "leading the division" is the only value
                // that means anything here.
                let rank = facts?.divisionRank ?? 0
                updated.progress = rank == 1 ? 1 : 0
                // Only final standings can clinch: mid-season the team can lead
                // and still finish second, and a goal that flickers "Achieved"
                // week to week is worse than one that waits.
                updated.isAchieved = rank == 1 && (facts?.regularSeasonComplete ?? false)

            case .conference:
                let won = facts?.wonConference ?? false
                updated.progress = won ? 1 : 0
                updated.isAchieved = won

            case .superBowl:
                let won = facts?.wonSuperBowl ?? false
                updated.progress = won ? 1 : 0
                updated.isAchieved = won

            case .developRookies:
                let rookieCount = roster.filter { $0.yearsPro <= 1 && $0.overall >= 60 }.count
                updated.progress = rookieCount
                if let target = goal.target {
                    updated.isAchieved = rookieCount >= target
                }

            case .reduceCapUsage:
                let usagePct = team.salaryCap > 0
                    ? Double(team.currentCapUsage) / Double(team.salaryCap)
                    : 1.0
                // Goal: stay under 95% of the cap
                updated.progress = Int(usagePct * 100)
                updated.isAchieved = usagePct <= 0.95

            case .winStreak:
                let longest = facts?.longestWinStreak ?? 0
                updated.progress = longest
                if let target = goal.target {
                    updated.isAchieved = longest >= target
                }

            case .improveDraft, .fanSatisfaction, .tradeAcquisition:
                // These goal types rely on external tracking; leave unchanged
                break
            }

            return updated
        }
    }

    // MARK: - Season Facts (TODO §5.6)

    /// Goal types that need real standings or a real schedule to answer.
    private static let standingsGoalTypes: Set<GoalType> = [
        .playoffs, .divisionTitle, .conference, .superBowl, .winStreak,
    ]

    /// Everything the goal slate needs to know about where the team actually
    /// stands this season. Every field is derived from the season's `Game`
    /// rows — nothing here is an estimate.
    struct SeasonFacts: Equatable {
        /// 1-4 within the division (0 = unknown, e.g. no games on the board).
        var divisionRank: Int = 0
        /// 1-7 conference seed; 0 when outside the bracket.
        var conferenceSeed: Int = 0
        /// Seeded into the bracket, or already playing in it.
        var madePlayoffs: Bool = false
        /// Won the conference championship game (playoff week 21).
        var wonConference: Bool = false
        /// Won the Super Bowl (playoff week 22).
        var wonSuperBowl: Bool = false
        /// Longest run of consecutive regular-season wins this season.
        var longestWinStreak: Int = 0
        /// Every regular-season game on the schedule has been played.
        var regularSeasonComplete: Bool = false
    }

    /// Derives this season's facts for one team.
    ///
    /// Memoised per (career, season, week, phase): the League/Dashboard screens
    /// call `evaluateGoalProgress` from a computed property, so without this a
    /// SwiftUI re-render would cost two fetches every time the body ran. The
    /// key covers every clock that can change a standing, and holds only plain
    /// numbers — never a model reference — so a career switch or a rollover
    /// invalidates it on its own.
    static func seasonFacts(
        team: Team,
        career: Career,
        leagueTeams: [Team]? = nil,
        seasonGames: [Game]? = nil
    ) -> SeasonFacts {
        let key = "\(career.id.uuidString)#\(career.currentSeason)#\(career.currentWeek)"
            + "#\(career.currentPhase.rawValue)#\(team.id.uuidString)"
        if factsCacheKey == key, let cached = factsCache { return cached }

        let context = team.modelContext
        let cid = career.id
        let season = career.currentSeason

        let teams: [Team] = leagueTeams ?? {
            guard let context else { return [] }
            let descriptor = FetchDescriptor<Team>(predicate: #Predicate<Team> { $0.careerID == cid })
            return (try? context.fetch(descriptor)) ?? []
        }()
        let games: [Game] = seasonGames ?? {
            guard let context else { return [] }
            let descriptor = FetchDescriptor<Game>(
                predicate: #Predicate<Game> { $0.careerID == cid && $0.seasonYear == season }
            )
            return (try? context.fetch(descriptor)) ?? []
        }()

        var facts = SeasonFacts()
        guard !teams.isEmpty, !games.isEmpty else { return facts }

        let records = StandingsCalculator.calculate(games: games, teams: teams)

        let divisionStandings = StandingsCalculator.divisionStandings(
            records: records, teams: teams,
            conference: team.conference, division: team.division
        )
        if let index = divisionStandings.firstIndex(where: { $0.teamID == team.id }) {
            facts.divisionRank = index + 1
        }

        let seeds = StandingsCalculator.playoffTeams(
            records: records, teams: teams, conference: team.conference
        )
        if let index = seeds.firstIndex(where: { $0.teamID == team.id }) {
            facts.conferenceSeed = index + 1
        }

        let regularSeason = games.filter { !$0.isPlayoff }
        facts.regularSeasonComplete = !regularSeason.isEmpty && regularSeason.allSatisfy(\.isPlayed)
        facts.longestWinStreak = longestWinStreak(
            teamID: team.id,
            games: regularSeason.filter(\.isPlayed).sorted { $0.week < $1.week }
        )

        let playoffGames = games.filter { $0.isPlayoff }
        let inBracket = playoffGames.contains {
            $0.homeTeamID == team.id || $0.awayTeamID == team.id
        }
        // A bracket game is proof. A top-7 seed is proof only once the regular
        // season is over — the seeding is live all year, so a team sitting 6th
        // in Week 5 has not "made the playoffs", it is merely on track.
        facts.madePlayoffs = inBracket || (facts.conferenceSeed > 0 && facts.regularSeasonComplete)
        facts.wonConference = playoffGames.contains {
            $0.week == 21 && $0.isPlayed && $0.winnerID == team.id
        }
        facts.wonSuperBowl = playoffGames.contains {
            $0.week == 22 && $0.isPlayed && $0.winnerID == team.id
        }

        factsCacheKey = key
        factsCache = facts
        return facts
    }

    private static var factsCacheKey: String?
    private static var factsCache: SeasonFacts?

    /// Longest run of consecutive wins inside one team's season. Ties and
    /// losses both break the run — a streak is wins in a row or it is nothing.
    private static func longestWinStreak(teamID: UUID, games: [Game]) -> Int {
        var best = 0, run = 0
        for game in games {
            guard let home = game.homeScore, let away = game.awayScore else { continue }
            let isHome = game.homeTeamID == teamID
            let isAway = game.awayTeamID == teamID
            guard isHome || isAway else { continue }
            let own = isHome ? home : away
            let opponent = isHome ? away : home
            if own > opponent {
                run += 1
                best = max(best, run)
            } else {
                run = 0
            }
        }
        return best
    }

    // MARK: - Private Helpers

    /// Takes the roster (not the team) so the caller resolves it once — see
    /// `Team.currentRoster()`.
    private static func averageOverall(roster: [Player]) -> Double {
        guard !roster.isEmpty else { return 0 }
        let total = roster.reduce(0) { $0 + $1.overall }
        return Double(total) / Double(roster.count)
    }

    private static func contenderPrimaryGoal(owner: Owner) -> SeasonGoal {
        if owner.prefersWinNow {
            return SeasonGoal(
                title: "Win the Super Bowl",
                description: "\(owner.name) has invested in this roster to win a championship. Nothing less will do.",
                type: .superBowl,
                priority: .primary
            )
        } else {
            return SeasonGoal(
                title: "Win the Conference",
                description: "Reach the Super Bowl and prove this team is one of the NFL's elite franchises.",
                type: .conference,
                priority: .primary
            )
        }
    }
}
