import Foundation
import SwiftData

/// Stateless engine responsible for advancing game state by one week,
/// simulating games, and managing season/phase transitions.
enum WeekAdvancer {

    /// The result of the last player team game simulation (available after advanceWeek)
    static var lastPlayerGameResult: GameSimulator.GameResult?

    // MARK: - Public API

    /// Advances the career state by exactly one week.
    ///
    /// Behavior depends on the current phase:
    /// - **.regularSeason**: Simulates all unplayed games for the current week,
    ///   updates team records, increments the week counter, and handles the
    ///   trade deadline marker at week 9 and the transition to playoffs after week 18.
    /// - **.playoffs**: Advances through wild card (week 19) → divisional (week 20)
    ///   → conference championship (week 21) → super bowl (week 22), then
    ///   transitions to the `.superBowl` offseason phase.
    /// - **all other offseason phases**: Steps to the next phase in the calendar
    ///   order. When reaching `.regularSeason`, a new season is started via
    ///   `startNewSeason(career:teams:modelContext:)`.
    ///
    /// - Parameters:
    ///   - career: The active `Career` object (mutated in place).
    ///   - modelContext: SwiftData context used to fetch and persist `Game` and `Team` objects.
    static func advanceWeek(career: Career, modelContext: ModelContext) {
        switch career.currentPhase {

        case .regularSeason:
            advanceRegularSeasonWeek(career: career, modelContext: modelContext)

        case .playoffs:
            advancePlayoffWeek(career: career, modelContext: modelContext)

        default:
            advanceOffseasonPhase(career: career, modelContext: modelContext)
        }
    }

    // MARK: - Score Simulation

    /// Generates a pair of realistic NFL final scores.
    ///
    /// Model:
    /// - Each side rolls a base number of touchdowns (0–5) and field goals (0–4).
    /// - TD = 7 points, FG = 3 points (simplified; no extra-point failures).
    /// - Home team receives a flat +3 point advantage on average.
    /// - Approximately 1 % of games end in a tie by forcing overtime parity.
    ///
    /// - Returns: A tuple `(home: Int, away: Int)` with each score ≥ 0.
    static func simulateGameScore() -> (home: Int, away: Int) {
        // ~1 % tie chance — resolve before computing independent scores.
        let tieRoll = Int.random(in: 1...100)
        if tieRoll == 1 {
            // Tied game: both teams land the same realistic score.
            let tiedScore = randomTeamScore(homeAdvantage: 0)
            return (tiedScore, tiedScore)
        }

        let homeScore = randomTeamScore(homeAdvantage: 3)
        let awayScore = randomTeamScore(homeAdvantage: 0)

        // Ensure no accidental tie outside the 1 % path.
        if homeScore == awayScore {
            // Break tie by giving home team one extra point (safety).
            return (homeScore + 1, awayScore)
        }

        return (homeScore, awayScore)
    }

    // MARK: - New Season Bootstrap

    /// Resets every team's record, generates a fresh schedule, and sets the
    /// career state to Week 1 of the regular season.
    ///
    /// All generated `Game` objects are inserted into `modelContext`. It is the
    /// caller's responsibility to save the context afterward.
    ///
    /// - Parameters:
    ///   - career: The active `Career` object (mutated in place).
    ///   - teams:  All 32 teams in the league.
    ///   - modelContext: SwiftData context used to insert the new games.
    static func startNewSeason(career: Career, teams: [Team], modelContext: ModelContext) {
        // 1. Reset every team's win/loss/tie record.
        for team in teams {
            team.wins = 0
            team.losses = 0
            team.ties = 0
        }

        // 2. Generate a brand-new schedule for the upcoming season year.
        let newGames = ScheduleGenerator.generateSeason(
            teams: teams,
            seasonYear: career.currentSeason
        )

        // 3. Persist every game into the SwiftData store.
        for game in newGames {
            modelContext.insert(game)
        }

        // 4. Update career state.
        career.currentPhase = .regularSeason
        career.currentWeek = 1
    }

    // MARK: - Private: Regular Season

    private static func advanceRegularSeasonWeek(career: Career, modelContext: ModelContext) {
        let week = career.currentWeek
        let season = career.currentSeason

        // Fetch all unplayed regular-season games for this week.
        let unplayedGames = fetchUnplayedGames(
            week: week,
            seasonYear: season,
            isPlayoff: false,
            modelContext: modelContext
        )

        // Build a team lookup so we can update records efficiently.
        let teamsByID = fetchTeamsByID(modelContext: modelContext)

        // Simulate every unplayed game.
        // Player's team game uses full play-by-play simulation;
        // all other games use the fast random score generator.
        var playerGameResult: GameSimulator.GameResult?

        for game in unplayedGames {
            let isPlayerGame = (game.homeTeamID == career.teamID || game.awayTeamID == career.teamID)

            if isPlayerGame,
               let homeTeam = teamsByID[game.homeTeamID],
               let awayTeam = teamsByID[game.awayTeamID] {
                // Full play-by-play simulation for the player's game
                let result = GameSimulator.simulate(homeTeam: homeTeam, awayTeam: awayTeam)
                game.homeScore = result.homeScore
                game.awayScore = result.awayScore
                playerGameResult = result
            } else {
                let score = simulateGameScore()
                game.homeScore = score.home
                game.awayScore = score.away
            }

            updateTeamRecords(game: game, teamsByID: teamsByID)
        }

        // Store the latest player game result for UI to access
        lastPlayerGameResult = playerGameResult

        // Advance the week counter.
        career.currentWeek += 1

        // Handle trade deadline at the end of week 8 (before week 9 begins).
        // The phase is momentarily tagged then immediately restored so that
        // any UI or future systems can observe the transition.
        if week == 8 {
            career.currentPhase = .tradeDeadline
            career.currentPhase = .regularSeason
        }

        // Transition to playoffs once all 18 regular season weeks are done.
        if career.currentWeek > 18 {
            career.currentPhase = .playoffs
            career.currentWeek = 19   // Playoff week numbering starts at 19.
        }
    }

    // MARK: - Private: Playoffs

    /// Advances one playoff round.
    ///
    /// Week mapping:
    /// - 19 → Wild Card
    /// - 20 → Divisional Round
    /// - 21 → Conference Championships
    /// - 22 → Super Bowl
    /// - After 22 → transition to `.superBowl` offseason phase.
    private static func advancePlayoffWeek(career: Career, modelContext: ModelContext) {
        let week = career.currentWeek

        // Simulate any unplayed playoff games for this week.
        let unplayedGames = fetchUnplayedGames(
            week: week,
            seasonYear: career.currentSeason,
            isPlayoff: true,
            modelContext: modelContext
        )

        let teamsByID = fetchTeamsByID(modelContext: modelContext)

        for game in unplayedGames {
            var score = simulateGameScore()

            // Playoff games cannot end in a tie — keep re-rolling until scores differ.
            while score.home == score.away {
                score = simulateGameScore()
            }

            game.homeScore = score.home
            game.awayScore = score.away

            updateTeamRecords(game: game, teamsByID: teamsByID)
        }

        if week >= 22 {
            // Super Bowl complete → begin offseason.
            career.currentPhase = .superBowl
            // currentWeek is left at 22; it will be reset when the new season starts.
        } else {
            career.currentWeek += 1
        }
    }

    // MARK: - Private: Offseason Phase Advancement

    /// Steps the career forward to the next offseason phase in calendar order.
    /// When the cycle reaches `.regularSeason`, a new season is bootstrapped.
    private static func advanceOffseasonPhase(career: Career, modelContext: ModelContext) {
        let nextPhase = phase(after: career.currentPhase)

        if nextPhase == .regularSeason {
            // Increment the season year before generating a new schedule.
            career.currentSeason += 1

            let teams = fetchAllTeams(modelContext: modelContext)
            startNewSeason(career: career, teams: teams, modelContext: modelContext)
        } else {
            career.currentPhase = nextPhase
        }
    }

    // MARK: - Private: Phase Ordering

    /// Returns the phase that immediately follows `phase` in the annual calendar.
    ///
    /// Full offseason → preseason chain:
    /// superBowl → proBowl → coachingChanges → combine → freeAgency →
    /// draft → otas → trainingCamp → preseason → rosterCuts → regularSeason
    ///
    /// In-season transitions are handled by the regular-season / playoff
    /// logic and are not part of this chain.
    private static func phase(after phase: SeasonPhase) -> SeasonPhase {
        switch phase {
        case .superBowl:        return .proBowl
        case .proBowl:          return .coachingChanges
        case .coachingChanges:  return .combine
        case .combine:          return .freeAgency
        case .freeAgency:       return .draft
        case .draft:            return .otas
        case .otas:             return .trainingCamp
        case .trainingCamp:     return .preseason
        case .preseason:        return .rosterCuts
        case .rosterCuts:       return .regularSeason
        // These cases should be handled by their dedicated advance functions,
        // but return a sensible fallback to avoid unhandled switches.
        case .regularSeason:    return .playoffs
        case .tradeDeadline:    return .regularSeason
        case .playoffs:         return .superBowl
        }
    }

    // MARK: - Private: Team Record Updates

    private static func updateTeamRecords(game: Game, teamsByID: [UUID: Team]) {
        guard let homeScore = game.homeScore,
              let awayScore = game.awayScore else { return }

        let homeTeam = teamsByID[game.homeTeamID]
        let awayTeam = teamsByID[game.awayTeamID]

        if homeScore > awayScore {
            homeTeam?.wins   += 1
            awayTeam?.losses += 1
        } else if awayScore > homeScore {
            awayTeam?.wins   += 1
            homeTeam?.losses += 1
        } else {
            homeTeam?.ties += 1
            awayTeam?.ties += 1
        }
    }

    // MARK: - Private: SwiftData Helpers

    private static func fetchUnplayedGames(
        week: Int,
        seasonYear: Int,
        isPlayoff: Bool,
        modelContext: ModelContext
    ) -> [Game] {
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { game in
                game.week == week &&
                game.seasonYear == seasonYear &&
                game.isPlayoff == isPlayoff &&
                game.homeScore == nil
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchTeamsByID(modelContext: ModelContext) -> [UUID: Team] {
        let descriptor = FetchDescriptor<Team>()
        let teams = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
    }

    private static func fetchAllTeams(modelContext: ModelContext) -> [Team] {
        let descriptor = FetchDescriptor<Team>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Private: Score Generation Helpers

    /// Generates a single realistic team score.
    ///
    /// - Parameter homeAdvantage: Flat bonus added to the raw score (pass 0 for away teams).
    /// - Returns: A non-negative integer score.
    private static func randomTeamScore(homeAdvantage: Int) -> Int {
        // Touchdowns: weighted toward 2–4 TDs per game.
        // Distribution: 0 TD (rare), 1–2 (below average), 2–4 (typical), 5+ (blowout)
        let tdBucket = Int.random(in: 1...10)
        let touchdowns: Int
        switch tdBucket {
        case 1:        touchdowns = 0           // shutout / very low scoring
        case 2...3:    touchdowns = 1
        case 4...6:    touchdowns = 2
        case 7...8:    touchdowns = 3
        case 9:        touchdowns = 4
        case 10:       touchdowns = Int.random(in: 5...6)   // blowout
        default:       touchdowns = 2
        }

        // Field goals: 0–4, weighted toward 1–2.
        let fgBucket = Int.random(in: 1...8)
        let fieldGoals: Int
        switch fgBucket {
        case 1:        fieldGoals = 0
        case 2...4:    fieldGoals = 1
        case 5...7:    fieldGoals = 2
        case 8:        fieldGoals = Int.random(in: 3...4)
        default:       fieldGoals = 1
        }

        let raw = (touchdowns * 7) + (fieldGoals * 3) + homeAdvantage
        return max(0, raw)
    }
}
