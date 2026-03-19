import Foundation
import SwiftData

/// Stateless engine responsible for advancing game state by one week,
/// simulating games, and managing season/phase transitions.
enum WeekAdvancer {

    /// The result of the last player team game simulation (available after advanceWeek)
    static var lastPlayerGameResult: GameSimulator.GameResult?

    // MARK: - Static Storage for UI Access

    /// News items generated during the most recent advance.
    static var lastNewsItems: [NewsItem] = []

    /// Game events generated during the most recent advance.
    static var lastEvents: [GameEvent] = []

    /// Inbox messages generated during the most recent phase transition.
    static var lastInboxMessages: [InboxMessage] = []

    /// Set to `true` when the owner fires the player after a satisfaction check.
    static var wasFired: Bool = false

    /// Press questions generated after the player's game, pending UI presentation.
    static var pendingPressConference: [PressQuestion]?

    /// Tracks whether a draft class has been generated for the current offseason cycle.
    static var draftClassGenerated: Bool = false

    /// The current draft class of college prospects (persists across offseason phases).
    static var currentDraftClass: [CollegeProspect] = []

    /// Draft picks generated for the current draft.
    static var currentDraftPicks: [DraftPick] = []

    // MARK: - Public API

    /// Advances the career state by exactly one week.
    ///
    /// Behavior depends on the current phase:
    /// - **.regularSeason**: Simulates all unplayed games for the current week,
    ///   updates team records, increments the week counter, and handles the
    ///   trade deadline marker at week 9 and the transition to playoffs after week 18.
    /// - **.playoffs**: Advances through wild card (week 19) → divisional (week 20)
    ///   → conference championship (week 21) → super bowl (week 22), then
    ///   transitions to the `.proBowl` offseason phase.
    /// - **all other offseason phases**: Steps to the next phase in the calendar
    ///   order. When reaching `.regularSeason`, a new season is started via
    ///   `startNewSeason(career:teams:modelContext:)`.
    ///
    /// - Parameters:
    ///   - career: The active `Career` object (mutated in place).
    ///   - modelContext: SwiftData context used to fetch and persist `Game` and `Team` objects.
    static func advanceWeek(career: Career, modelContext: ModelContext) {
        // Reset per-advance state
        lastNewsItems = []
        lastEvents = []
        lastInboxMessages = []
        wasFired = false
        pendingPressConference = nil

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
        // 0. Recalculate coaching budgets based on previous season performance (#80)
        for team in teams {
            if let owner = team.owner {
                let madePlayoffs = team.wins >= 9  // Approximate playoff threshold
                owner.previousCoachingBudget = owner.coachingBudget
                owner.coachingBudget = BudgetEngine.calculateBudget(
                    owner: owner,
                    team: team,
                    previousSeasonWins: team.wins,
                    madePlayoffs: madePlayoffs
                )
            }
        }

        // 0b. Reset franchise tags from previous season
        let allPlayersForReset = fetchAllPlayers(modelContext: modelContext)
        for player in allPlayersForReset where player.isFranchiseTagged {
            player.isFranchiseTagged = false
        }

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

        // 5. Reset draft class flag for the new offseason cycle.
        draftClassGenerated = false
        currentDraftClass = []
        currentDraftPicks = []
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
        let allPlayers = fetchAllPlayers(modelContext: modelContext)
        let allCoaches = fetchAllCoaches(modelContext: modelContext)

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
                let homeCoaches = allCoaches.filter { $0.teamID == homeTeam.id }
                let awayCoaches = allCoaches.filter { $0.teamID == awayTeam.id }
                let result = GameSimulator.simulate(
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    homeCoaches: homeCoaches,
                    awayCoaches: awayCoaches
                )
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

        // 0. Generate weekly press conference questions
        if let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            let lastGameWon: Bool? = {
                guard let result = playerGameResult else { return nil }
                if let game = unplayedGames.first(where: {
                    $0.homeTeamID == playerTeamID || $0.awayTeamID == playerTeamID
                }) {
                    let isHome = game.homeTeamID == playerTeamID
                    return isHome ? result.homeScore > result.awayScore : result.awayScore > result.homeScore
                }
                return nil
            }()

            pendingPressConference = PressConferenceEngine.generateWeeklyPressConference(
                career: career,
                team: playerTeam,
                lastGameResult: lastGameWon,
                week: week
            )
        }

        // --- Engine integrations after game simulation ---

        let teams = Array(teamsByID.values)

        // 1. Generate weekly news
        lastNewsItems = NewsGenerator.generateWeeklyNews(
            teams: teams,
            players: allPlayers,
            career: career,
            week: week,
            season: season
        )

        // 2. Generate weekly events for the player's team
        if let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            lastEvents = EventEngine.generateWeeklyEvents(
                team: playerTeam,
                players: allPlayers,
                coaches: allCoaches,
                career: career
            )

            // 3. Update owner satisfaction
            if let owner = playerTeam.owner {
                OwnerSatisfactionEngine.updateSatisfaction(
                    owner: owner,
                    team: playerTeam,
                    career: career,
                    newsItems: lastNewsItems
                )

                // 4. Check if the owner fires the player
                wasFired = OwnerSatisfactionEngine.checkFiring(owner: owner, career: career)
            }

            // 4b. Generate weekly inbox messages
            let teamCoaches = allCoaches.filter { $0.teamID == playerTeamID }
            lastInboxMessages = InboxEngine.generatePhaseMessages(
                phase: career.currentPhase,
                career: career,
                team: playerTeam,
                coaches: teamCoaches,
                owner: playerTeam.owner
            )
        }

        // 5. Apply fatigue changes for players who played this week
        for player in allPlayers where player.teamID != nil && !player.isInjured {
            let fatigueGain = Int.random(in: 3...8)
            player.fatigue = min(100, player.fatigue + fatigueGain)
        }

        // 5b. Apply fatigue recovery using MedicalEngine (physio improves recovery)
        for player in allPlayers where player.teamID != nil {
            let teamPhysio = allCoaches.first { $0.teamID == player.teamID && $0.role == .physio }
            let recovery = MedicalEngine.weeklyFatigueRecovery(player: player, physio: teamPhysio)
            player.fatigue = max(0, player.fatigue - recovery)
        }

        // 6. Process injuries for players who played (medical staff reduces risk)
        for player in allPlayers where player.teamID != nil && !player.isInjured {
            let teamDoctor = allCoaches.first { $0.teamID == player.teamID && $0.role == .teamDoctor }
            let teamPhysio = allCoaches.first { $0.teamID == player.teamID && $0.role == .physio }

            // Use MedicalEngine for injury check with medical staff awareness
            if let injury = MedicalEngine.injuryCheck(
                player: player,
                playType: .run,  // Approximate — actual play type not tracked at weekly level
                doctor: teamDoctor,
                physio: teamPhysio
            ) {
                MedicalEngine.applyInjury(
                    player: player,
                    injuryType: injury,
                    doctor: teamDoctor,
                    physio: teamPhysio
                )
            }
        }

        // 7. Apply game experience for starters (approximated: high-overall rostered players)
        for player in allPlayers where player.teamID != nil && !player.isInjured {
            // Approximate starters as those with overall >= 65 or on small rosters
            if player.overall >= 65 {
                PlayerDevelopmentEngine.applyGameExperience(player, gamesPlayed: 1, gamesStarted: 1)
            } else {
                PlayerDevelopmentEngine.applyGameExperience(player, gamesPlayed: 1, gamesStarted: 0)
            }
        }

        // 8. Process existing injuries (decrement recovery time via MedicalEngine)
        for player in allPlayers where player.isInjured {
            _ = MedicalEngine.processWeeklyRecovery(player: player)
        }

        // 8b. Weekly scheme learning and position training (during season, reduced intensity)
        for team in teams {
            let teamPlayers = allPlayers.filter { $0.teamID == team.id }
            let teamCoaches = allCoaches.filter { $0.teamID == team.id }
            let oc = teamCoaches.first { $0.role == .offensiveCoordinator }
            let dc = teamCoaches.first { $0.role == .defensiveCoordinator }

            for player in teamPlayers where !player.isInjured {
                // Scheme learning (reduced intensity during season)
                if let offScheme = oc?.offensiveScheme, player.position.side == .offense {
                    let gain = VersatilityDevelopmentEngine.learnScheme(
                        player: player, scheme: offScheme.rawValue,
                        coordinator: oc, practiceIntensity: 0.5
                    )
                    let key = offScheme.rawValue
                    player.schemeFamiliarity[key] = min(100, (player.schemeFamiliarity[key] ?? 0) + gain)
                }
                if let defScheme = dc?.defensiveScheme, player.position.side == .defense {
                    let gain = VersatilityDevelopmentEngine.learnScheme(
                        player: player, scheme: defScheme.rawValue,
                        coordinator: dc, practiceIntensity: 0.5
                    )
                    let key = defScheme.rawValue
                    player.schemeFamiliarity[key] = min(100, (player.schemeFamiliarity[key] ?? 0) + gain)
                }

                // Position training (reduced during season)
                if let trainingPos = player.trainingPosition, trainingPos != player.position {
                    let posCoach = teamCoaches.first { coach in
                        CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: trainingPos)
                    }
                    let gain = VersatilityDevelopmentEngine.trainPosition(
                        player: player, targetPosition: trainingPos,
                        positionCoach: posCoach, practiceIntensity: 0.3
                    )
                    let key = trainingPos.rawValue
                    let ceiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: trainingPos)
                    player.positionFamiliarity[key] = min(ceiling, (player.positionFamiliarity[key] ?? 0) + gain)
                }
            }
        }

        // Advance the week counter.
        career.currentWeek += 1

        // Handle trade deadline at the end of week 8 (before week 9 begins).
        // The phase is momentarily tagged then immediately restored so that
        // any UI or future systems can observe the transition.
        if week == 8 {
            career.currentPhase = .tradeDeadline
            career.currentPhase = .regularSeason
        }

        // 9. At season end (week 18): decrement contract years and expire contracts
        if week == 18 {
            for player in allPlayers where player.contractYearsRemaining > 0 {
                player.contractYearsRemaining -= 1
                if player.contractYearsRemaining == 0 {
                    // Contract expired: player becomes a free agent
                    if let teamID = player.teamID, let team = teamsByID[teamID] {
                        team.currentCapUsage -= player.annualSalary
                    }
                    player.teamID = nil
                    player.annualSalary = 0
                }
            }
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
    /// Week mapping (matches real NFL calendar):
    /// - 19 → Wild Card
    /// - 20 → Divisional Round
    /// - 21 → Conference Championships
    /// - 22 → Pro Bowl week (handled as offseason phase)
    /// - 23 → Super Bowl (handled as offseason phase)
    /// - After Conference Championships → Pro Bowl → Super Bowl → offseason
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

        if week >= 21 {
            // Conference Championships complete → Pro Bowl week next.
            career.currentPhase = .proBowl
        } else {
            career.currentWeek += 1
        }
    }

    // MARK: - Private: Offseason Phase Advancement

    /// Steps the career forward to the next offseason phase in calendar order.
    /// When the cycle reaches `.regularSeason`, a new season is bootstrapped.
    private static func advanceOffseasonPhase(career: Career, modelContext: ModelContext) {
        let currentPhase = career.currentPhase
        let nextPhase = phase(after: currentPhase)

        let teams = fetchAllTeams(modelContext: modelContext)
        let allPlayers = fetchAllPlayers(modelContext: modelContext)
        let allCoaches = fetchAllCoaches(modelContext: modelContext)
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        // --- Run engine logic for the CURRENT phase before transitioning ---
        switch currentPhase {

        case .superBowl:
            // Simulate the Super Bowl game (moved here from playoffs to support Pro Bowl week)
            let sbGames = fetchUnplayedGames(
                week: 22,
                seasonYear: career.currentSeason,
                isPlayoff: true,
                modelContext: modelContext
            )
            for game in sbGames {
                var score = simulateGameScore()
                while score.home == score.away {
                    score = simulateGameScore()
                }
                game.homeScore = score.home
                game.awayScore = score.away
                updateTeamRecords(game: game, teamsByID: teamsByID)
            }

            // Generate championship news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .superBowl,
                career: career,
                teams: teams
            )

        case .proBowl:
            // Simulate Pro Bowl game (AFC vs NFC, simple random result)
            let proBowlScore = simulateGameScore()
            let afcScore = proBowlScore.home
            let nfcScore = proBowlScore.away
            let afcWon = afcScore > nfcScore

            // Generate Pro Bowl selections — top-rated players from each conference
            var proBowlSelections: [String] = []
            if let playerTeamID = career.teamID,
               let playerTeam = teamsByID[playerTeamID] {
                let teamPlayers = allPlayers.filter { $0.teamID == playerTeamID }
                let proBowlers = teamPlayers
                    .sorted { $0.overall > $1.overall }
                    .prefix(3)
                for p in proBowlers {
                    proBowlSelections.append("\(p.firstName) \(p.lastName)")
                }

                // Generate inbox message about Pro Bowl selections
                let selectionsText = proBowlSelections.isEmpty
                    ? "None of your players were selected."
                    : "Pro Bowl selections: \(proBowlSelections.joined(separator: ", "))."
                let resultText = afcWon
                    ? "AFC won \(afcScore)-\(nfcScore)."
                    : "NFC won \(nfcScore)-\(afcScore)."

                let proBowlMessage = InboxMessage(
                    sender: .leagueOffice,
                    subject: "Pro Bowl Results",
                    body: "\(resultText) \(selectionsText)",
                    date: "Offseason - Pro Bowl, Season \(career.currentSeason)",
                    category: .leagueNotice
                )
                lastInboxMessages.append(proBowlMessage)
            }

            // Awards and Pro Bowl news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .proBowl,
                career: career,
                teams: teams
            )

        case .coachingChanges:
            // Check coordinator poaching for all teams
            for team in teams {
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                let poached = CoachingEngine.checkCoordinatorPoaching(
                    coaches: teamCoaches,
                    teamWins: team.wins
                )
                // Poached coaches leave the team
                for coach in poached {
                    coach.teamID = nil
                }
            }

            // Develop all coaches based on their team's performance
            for coach in allCoaches {
                let teamWins: Int
                if let tid = coach.teamID, let team = teamsByID[tid] {
                    teamWins = team.wins
                } else {
                    teamWins = 8 // neutral default for unattached coaches
                }
                CoachingEngine.developCoach(coach, teamWins: teamWins)
            }

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .coachingChanges,
                career: career,
                teams: teams
            )

        case .combine:
            // Generate draft class if not yet generated
            if !draftClassGenerated {
                currentDraftClass = ScoutingEngine.generateDraftClass()
                draftClassGenerated = true
            }

            // Simulate combine for all prospects
            ScoutingEngine.simulateCombine(prospects: &currentDraftClass)

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .combine,
                career: career,
                teams: teams
            )

        case .freeAgency:
            // Decrement contract years and expire contracts for all players
            for player in allPlayers where player.contractYearsRemaining > 0 {
                player.contractYearsRemaining -= 1
                if player.contractYearsRemaining == 0 {
                    // Contract expired: player becomes a free agent
                    if let teamID = player.teamID, let team = teamsByID[teamID] {
                        team.currentCapUsage -= player.annualSalary
                    }
                    player.teamID = nil
                    player.annualSalary = 0
                }
            }

            // Generate free agent market
            let freeAgents = FreeAgencyEngine.generateFreeAgentMarket(allPlayers: allPlayers)

            // Simulate AI free agency (AI teams sign available free agents)
            let aiTeams = teams.filter { $0.id != career.teamID }
            FreeAgencyEngine.simulateAIFreeAgency(
                freeAgents: freeAgents,
                teams: aiTeams,
                modelContext: modelContext
            )

            // Grow salary cap for all teams. Most years 5–8% (NFL average),
            // but ~20% chance of a tough economic year with only 0–2% growth.
            let growthRate: Double = {
                let roll = Double.random(in: 0...1)
                if roll < 0.20 {
                    // Tough economic year — flat or minimal growth
                    return Double.random(in: 0.0...0.02)
                } else {
                    // Normal growth matching NFL trends
                    return Double.random(in: 0.05...0.08)
                }
            }()
            for team in teams {
                CapManagementEngine.applyCapGrowth(team: team, growthRate: growthRate)
            }

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .freeAgency,
                career: career,
                teams: teams
            )

        case .reviewRoster:
            // No engine logic — this phase is for the player to review their roster,
            // apply franchise tags, and evaluate contracts before free agency opens.
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .reviewRoster,
                career: career,
                teams: teams
            )

        case .draft:
            // Generate draft order based on standings
            let allGames = fetchAllGamesForSeason(
                seasonYear: career.currentSeason,
                modelContext: modelContext
            )
            let draftPicks = DraftEngine.generateDraftOrder(
                teams: teams,
                games: allGames,
                seasonYear: career.currentSeason
            )
            currentDraftPicks = draftPicks

            // Persist draft picks
            for pick in draftPicks {
                modelContext.insert(pick)
            }

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .draft,
                career: career,
                teams: teams
            )

        case .otas:
            // Nothing special — just generate phase news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .otas,
                career: career,
                teams: teams
            )

        case .trainingCamp:
            // Process offseason development for all teams
            for team in teams {
                let teamPlayers = allPlayers.filter { $0.teamID == team.id }
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                _ = PlayerDevelopmentEngine.processOffseason(
                    players: teamPlayers,
                    coaches: teamCoaches
                )
            }

            // Note: processOffseason already calls applyAgeRegression which increments
            // player.age and player.yearsPro, so no separate age increment needed.

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .trainingCamp,
                career: career,
                teams: teams
            )

        case .preseason:
            // Generate preseason news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .preseason,
                career: career,
                teams: teams
            )

        case .rosterCuts:
            // Player handles manually — just generate phase news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .rosterCuts,
                career: career,
                teams: teams
            )

        default:
            break
        }

        // --- Transition to the next phase ---
        if nextPhase == .regularSeason {
            // Increment the season year before generating a new schedule.
            career.currentSeason += 1

            startNewSeason(career: career, teams: teams, modelContext: modelContext)

            // Generate schedule news for the new season
            let scheduleNews = NewsGenerator.generateOffseasonNews(
                phase: .regularSeason,
                career: career,
                teams: teams
            )
            lastNewsItems.append(contentsOf: scheduleNews)
        } else {
            career.currentPhase = nextPhase
        }

        // --- Generate inbox messages for the new phase ---
        if let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            let teamCoaches = allCoaches.filter { $0.teamID == playerTeamID }
            lastInboxMessages.append(contentsOf: InboxEngine.generatePhaseMessages(
                phase: career.currentPhase,
                career: career,
                team: playerTeam,
                coaches: teamCoaches,
                owner: playerTeam.owner
            ))
        }
    }

    // MARK: - Private: Phase Ordering

    /// Returns the phase that immediately follows `phase` in the annual calendar.
    ///
    /// Full offseason → preseason chain (matches NFL calendar):
    /// playoffs → proBowl → superBowl → coachingChanges → combine → reviewRoster →
    /// freeAgency → draft → otas → trainingCamp → preseason → rosterCuts → regularSeason
    ///
    /// In-season transitions are handled by the regular-season / playoff
    /// logic and are not part of this chain.
    private static func phase(after phase: SeasonPhase) -> SeasonPhase {
        switch phase {
        case .proBowl:          return .superBowl
        case .superBowl:        return .coachingChanges
        case .coachingChanges:  return .combine
        case .combine:          return .reviewRoster
        case .reviewRoster:     return .freeAgency
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
        case .playoffs:         return .proBowl
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

    private static func fetchAllPlayers(modelContext: ModelContext) -> [Player] {
        let descriptor = FetchDescriptor<Player>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchAllCoaches(modelContext: ModelContext) -> [Coach] {
        let descriptor = FetchDescriptor<Coach>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchAllGamesForSeason(
        seasonYear: Int,
        modelContext: ModelContext
    ) -> [Game] {
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { game in
                game.seasonYear == seasonYear
            }
        )
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
