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

    /// Latest mock draft projection (generated at midseason, combine, and pre-draft).
    static var currentMockDraft: [ScoutingEngine.MockDraftPick] = []

    /// Historical mock draft snapshots, keyed by phase tag (e.g. "Mid-Season",
    /// "Combine", "Post-FA", "Pre-Draft"). Each value is a copy of
    /// `currentMockDraft` taken right after that phase's mock was generated.
    static var mockDraftHistory: [String: [ScoutingEngine.MockDraftPick]] = [:]

    // MARK: - Draft Class Persistence

    /// Inserts every prospect of the current draft class into the SwiftData
    /// context and persists the change. Safe to call repeatedly — `insert`
    /// is idempotent for managed instances and will register fresh ones so
    /// subsequent `save()` calls flush their property changes too.
    @MainActor
    static func persistDraftClass(_ prospects: [CollegeProspect], to context: ModelContext) {
        for prospect in prospects {
            context.insert(prospect)
        }
        try? context.save()
    }

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
        let previousPhase = career.currentPhase
        career.currentPhase = .regularSeason
        career.currentWeek = 1
        emitGroupTransitionMessageIfNeeded(
            oldPhase: previousPhase,
            newPhase: .regularSeason,
            season: career.currentSeason
        )

        // 5. Reset draft class flag for the new offseason cycle.
        draftClassGenerated = false
        currentDraftClass = []
        currentDraftPicks = []
        currentMockDraft = []
        mockDraftHistory = [:]
    }

    // MARK: - Private: Regular Season

    private static func advanceRegularSeasonWeek(career: Career, modelContext: ModelContext) {
        let week = career.currentWeek
        let season = career.currentSeason

        // Camp Phase 1: apply opponent-prep drift penalty if user has been
        // over-focusing on opponent prep for 3+ consecutive weeks. The
        // gameBoost() side is consumed inside GameSimulator integration -- here
        // we only persist the long-term drift consequence (-1..-3 OVR) so it
        // survives across re-renders.
        if let teamID = career.teamID {
            applyOpponentPrepDrift(teamID: teamID, season: season, week: week, modelContext: modelContext)
        }

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

                // Camp Phase 1: fetch this week's OpponentPrepWeek for the user
                // and convert it into a game-boost via OpponentPrepEngine. The
                // boost is applied to the user's team only — AI-vs-user games
                // still get the full play-by-play simulation but with the user
                // benefiting from their prep choice.
                let userTeamID = career.teamID
                var audibleBoost = 0.0
                var defReadBoost = 0.0
                if let userTeamID = userTeamID,
                   userTeamID == homeTeam.id || userTeamID == awayTeam.id {
                    let prepDescriptor = FetchDescriptor<OpponentPrepWeek>(
                        predicate: #Predicate<OpponentPrepWeek> {
                            $0.seasonYear == season
                                && $0.weekNumber == week
                                && $0.teamID == userTeamID
                        }
                    )
                    if let prep = (try? modelContext.fetch(prepDescriptor))?.first {
                        let boost = OpponentPrepEngine.gameBoost(prep: prep)
                        audibleBoost = boost.audibleBoost
                        defReadBoost = boost.defensiveReadBoost
                    }
                }

                // The user's saved game plan shades only the user's own
                // offense; the AI opponent always simulates with `nil` (today's
                // exact behavior). `savedGamePlan` is nil until the user has
                // touched the Game Plan screen at least once.
                let userPlan = career.savedGamePlan
                let result = GameSimulator.simulate(
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    homeCoaches: homeCoaches,
                    awayCoaches: awayCoaches,
                    audibleBoost: audibleBoost,
                    defReadBoost: defReadBoost,
                    boostedTeamID: userTeamID,
                    homeGamePlan: homeTeam.id == userTeamID ? userPlan : nil,
                    awayGamePlan: awayTeam.id == userTeamID ? userPlan : nil
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

        // Store the latest player game result for UI to access.
        //
        // When the player's game was coached interactively (LiveGameEngine), it
        // was already played BEFORE advanceWeek: it never appears in
        // `unplayedGames`, so `playerGameResult` stays nil here. In that case
        // derive win/loss from the persisted game scores and keep whatever
        // result the live engine stored in `lastPlayerGameResult` (set by
        // `LiveGameEngine.persist`) for the press-conference context.
        var coachedGameWon: Bool?
        if playerGameResult != nil {
            lastPlayerGameResult = playerGameResult
        } else if let playerTeamID = career.teamID,
                  let coachedGame = fetchPlayedPlayerGame(
                      week: week,
                      seasonYear: season,
                      teamID: playerTeamID,
                      modelContext: modelContext
                  ),
                  let home = coachedGame.homeScore,
                  let away = coachedGame.awayScore {
            let isHome = coachedGame.homeTeamID == playerTeamID
            coachedGameWon = isHome ? home > away : away > home
            // lastPlayerGameResult stays as the live engine left it.
        } else {
            // Player genuinely had no played game this week.
            lastPlayerGameResult = nil
        }

        // Coach weekly XP
        if let playerTeamID = career.teamID {
            let teamCoaches = allCoaches.filter { $0.teamID == playerTeamID }
            let hc = teamCoaches.first { $0.role == .headCoach }
            let ahc = teamCoaches.first { $0.role == .assistantHeadCoach }
            let isPlayoff = career.currentPhase == .playoffs
            let playerTeamWon: Bool = {
                if let coachedGameWon { return coachedGameWon }
                guard let result = playerGameResult else { return false }
                if let game = unplayedGames.first(where: {
                    $0.homeTeamID == playerTeamID || $0.awayTeamID == playerTeamID
                }) {
                    let isHome = game.homeTeamID == playerTeamID
                    return isHome ? result.homeScore > result.awayScore : result.awayScore > result.homeScore
                }
                return false
            }()
            for coach in teamCoaches {
                CoachDevelopmentEngine.applyWeeklyXP(
                    coach: coach,
                    didWin: playerTeamWon,
                    isPlayoff: isPlayoff,
                    headCoach: hc,
                    assistantHC: ahc
                )
            }
        }

        // 0. Generate weekly press conference questions
        if let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            let lastGameWon: Bool? = {
                if let coachedGameWon { return coachedGameWon }
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

        // 8c. Generate weekly scout reports for the player's team's scouting staff
        if let playerTeamID = career.teamID, !currentDraftClass.isEmpty {
            let scouts = fetchAllScouts(modelContext: modelContext).filter {
                $0.teamID == playerTeamID
            }
            if !scouts.isEmpty {
                let reports = ScoutingEngine.generateWeeklyReports(
                    scouts: scouts,
                    prospects: currentDraftClass,
                    week: week
                )
                ScoutingEngine.applyWeeklyReports(reports, to: &currentDraftClass)
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

        // 9b. Midseason mock draft at week 9 (generate draft class early for projections)
        if week == 9 {
            if !draftClassGenerated {
                currentDraftClass = ScoutingEngine.generateDraftClass()
                draftClassGenerated = true
                persistDraftClass(currentDraftClass, to: modelContext)
            }
            currentMockDraft = ScoutingEngine.generateMockDraft(
                prospects: currentDraftClass,
                draftPicks: currentDraftPicks,
                teams: teams,
                players: allPlayers
            )
            ScoutingEngine.updateTeamInterest(
                prospects: &currentDraftClass,
                teams: teams,
                players: allPlayers
            )
            ScoutingEngine.applyMockDraftToProspects(
                prospects: &currentDraftClass,
                mockDraft: currentMockDraft
            )
            mockDraftHistory["Mid-Season"] = currentMockDraft
        }

        // 9. At season end (week 18): record season history snapshot per player,
        //    then decrement contract years and expire contracts.
        if week == 18 {
            recordSeasonHistory(
                players: allPlayers,
                season: season,
                modelContext: modelContext
            )

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
            let oldPhase = career.currentPhase
            career.currentPhase = .proBowl
            emitGroupTransitionMessageIfNeeded(
                oldPhase: oldPhase,
                newPhase: .proBowl,
                season: career.currentSeason
            )
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

            // Vaihe 5: Career arc evaluation — refresh trueGrade for every drafted
            // player and surface "Hidden Gem" flashbacks for the user's team.
            // Runs once per offseason at the proBowl → coachingChanges boundary.
            let gemFlashbacks = CareerArcEngine.evaluateAllDraftedPlayers(
                currentSeason: career.currentSeason,
                userTeamID: career.teamID,
                modelContext: modelContext
            )
            for flashback in gemFlashbacks {
                let body = """
                \(flashback.headline)

                Originally selected #\(flashback.draftPickNumber) in the \(flashback.draftYear) draft \
                with a Public Grade of \(flashback.publicGrade.rawValue), \(flashback.playerName) is \
                now grading out as a \(flashback.trueGrade.rawValue) (\(flashback.trueGrade.qualifier)) \
                pick — a true Hidden Gem.
                """
                let gemMessage = InboxMessage(
                    sender: .media(outlet: "NFL Network"),
                    subject: "Hidden Gem: \(flashback.playerName)",
                    body: body,
                    date: "Offseason - Pro Bowl, Season \(career.currentSeason)",
                    category: .scoutingReport
                )
                lastInboxMessages.append(gemMessage)
            }

        case .coachingChanges:
            var newMessages: [InboxMessage] = []

            // Generate draft class early so prospects are visible during offseason
            if !draftClassGenerated {
                currentDraftClass = ScoutingEngine.generateDraftClass()
                draftClassGenerated = true
                // First season: apply pre-scouted data
                let totalWins = teams.reduce(0) { $0 + $1.wins }
                let totalLosses = teams.reduce(0) { $0 + $1.losses }
                if totalWins == 0 && totalLosses == 0 {
                    ScoutingEngine.applyPreScoutedData(prospects: &currentDraftClass)
                }
                persistDraftClass(currentDraftClass, to: modelContext)
            }

            // Check coordinator poaching for all teams (legacy system)
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

            // HC promotion poaching (NFL-realistic coordinator-to-HC pipeline)
            for team in teams {
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                let poached = CoachingEngine.checkHCPromotionPoaching(
                    coaches: teamCoaches,
                    teamWins: team.wins
                )
                for coach in poached {
                    if coach.teamID == career.teamID {
                        let message = InboxMessage(
                            sender: .leagueOffice,
                            subject: "\(coach.fullName) Hired as Head Coach",
                            body: "\(coach.fullName) has accepted a Head Coach position with another team. You will receive a compensatory 3rd round draft pick.",
                            date: "Offseason - Coaching Changes, Season \(career.currentSeason)",
                            category: .staffUpdate
                        )
                        newMessages.append(message)
                    }
                    coach.teamID = nil
                }
            }

            // Develop all coaches based on their team's performance
            for team in teams {
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                let hc = teamCoaches.first { $0.role == .headCoach }
                let ahc = teamCoaches.first { $0.role == .assistantHeadCoach }
                for coach in teamCoaches {
                    CoachingEngine.developCoach(coach, teamWins: team.wins, headCoach: hc, assistantHC: ahc)
                }
            }
            // Develop unattached coaches with neutral win total
            for coach in allCoaches where coach.teamID == nil {
                CoachingEngine.developCoach(coach, teamWins: 8)
            }

            // Coach retirement (65+)
            for coach in allCoaches where coach.age >= 65 {
                if CoachDevelopmentEngine.shouldRetire(coach: coach) {
                    // Generate retirement news if it's the player's team
                    if coach.teamID == career.teamID {
                        let message = InboxMessage(
                            sender: .leagueOffice,
                            subject: "\(coach.fullName) Announces Retirement",
                            body: "\(coach.fullName), your \(coach.role.rawValue), has announced their retirement after \(coach.yearsExperience) seasons in coaching. Their position is now vacant.",
                            date: "Offseason - Coaching Changes, Season \(career.currentSeason)",
                            category: .staffUpdate
                        )
                        newMessages.append(message)
                    }
                    coach.teamID = nil  // Remove from team
                }
            }

            // Increment scout seasonsInRole for familiarity bonus
            let allScouts = fetchAllScouts(modelContext: modelContext)
            for scout in allScouts {
                scout.seasonsInRole += 1
            }

            // Declaration period: underclassmen declare or withdraw from draft
            if !currentDraftClass.isEmpty {
                let declarationNews = ScoutingEngine.generateDeclarations(prospects: &currentDraftClass)
                for item in declarationNews {
                    let sentiment: NewsSentiment = item.isDeclaration ? .neutral : .positive
                    let category: NewsCategory = .draft
                    lastNewsItems.append(NewsItem(
                        headline: item.headline,
                        body: item.isDeclaration
                            ? "\(item.name) has officially declared for the upcoming NFL Draft, forgoing remaining college eligibility."
                            : "\(item.name) has decided to withdraw from the draft and return to college for another season.",
                        category: category,
                        week: 0,
                        season: career.currentSeason,
                        sentiment: sentiment
                    ))
                }
            }

            lastInboxMessages.append(contentsOf: newMessages)

            lastNewsItems.append(contentsOf: NewsGenerator.generateOffseasonNews(
                phase: .coachingChanges,
                career: career,
                teams: teams
            ))

        case .combine:
            // Generate draft class if not yet generated
            if !draftClassGenerated {
                currentDraftClass = ScoutingEngine.generateDraftClass()
                draftClassGenerated = true

                // First season: apply pre-scouted data from previous GM's staff
                let isFirstSeason = career.totalWins == 0 && career.totalLosses == 0
                if isFirstSeason {
                    ScoutingEngine.applyPreScoutedData(prospects: &currentDraftClass)
                }
                persistDraftClass(currentDraftClass, to: modelContext)
            }

            // Combine results are NOT auto-generated here — they should only be
            // generated when the user presses "Send Scouts to Combine" in ScoutingHubView.

            // Post-combine mock draft update
            currentMockDraft = ScoutingEngine.generateMockDraft(
                prospects: currentDraftClass,
                draftPicks: currentDraftPicks,
                teams: teams,
                players: allPlayers
            )
            ScoutingEngine.updateTeamInterest(
                prospects: &currentDraftClass,
                teams: teams,
                players: allPlayers
            )
            ScoutingEngine.applyMockDraftToProspects(
                prospects: &currentDraftClass,
                mockDraft: currentMockDraft
            )
            mockDraftHistory["Combine"] = currentMockDraft

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .combine,
                career: career,
                teams: teams
            )

        case .freeAgency:
            // FA engine logic (contract decrements, AI signings, cap growth)
            // is now handled step-by-step within the FA flow views:
            //   - executeNewLeagueYear (contracts + cap growth)
            //   - FAWeeklyView (player offers + AI round signings)
            //   - simulateRemainingFA (skip button)
            //
            // If the player skipped the entire FA phase without entering it,
            // run the old logic as a fallback.
            if career.freeAgencyStep == FreeAgencyStep.finalPush.rawValue {
                // Player never entered FA — auto-run everything
                let summary = FreeAgencyEngine.executeNewLeagueYear(
                    allPlayers: allPlayers,
                    allTeams: teams,
                    playerTeamID: career.teamID ?? UUID(),
                    modelContext: modelContext
                )
                _ = summary

                FreeAgencyEngine.simulateRemainingFA(
                    allPlayers: allPlayers,
                    allTeams: teams,
                    playerTeamID: career.teamID,
                    modelContext: modelContext
                )
            }

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .freeAgency,
                career: career,
                teams: teams
            )

            // Regenerate mock draft after FA signings change team rosters/needs
            if !currentDraftClass.isEmpty {
                currentMockDraft = ScoutingEngine.generateMockDraft(
                    prospects: currentDraftClass,
                    draftPicks: currentDraftPicks,
                    teams: teams,
                    players: allPlayers
                )
                ScoutingEngine.applyMockDraftToProspects(
                    prospects: &currentDraftClass,
                    mockDraft: currentMockDraft
                )
                mockDraftHistory["Post-FA"] = currentMockDraft
            }

        case .proDays:
            // Pro days phase — engine work happens in scouting UI
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .proDays,
                career: career,
                teams: teams
            )

        case .reviewRoster:
            // Reset roster evaluation flags for the new Review Roster phase
            UserDefaults.standard.set(false, forKey: "rosterEvaluationConfirmed")
            UserDefaults.standard.set(false, forKey: "franchiseTagVisited")

            // Generate owner demands based on weakest position groups (#248)
            if let playerTeamID = career.teamID,
               let playerTeam = teamsByID[playerTeamID],
               let owner = playerTeam.owner {
                let teamPlayers = allPlayers.filter { $0.teamID == playerTeamID }
                career.ownerDemands = generateOwnerDemands(
                    owner: owner,
                    players: teamPlayers
                )
                career.ownerDemandsAddressed = []
            }

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

            // Pre-draft mock draft (final projection with actual draft order)
            currentMockDraft = ScoutingEngine.generateMockDraft(
                prospects: currentDraftClass,
                draftPicks: draftPicks,
                teams: teams,
                players: allPlayers
            )
            ScoutingEngine.updateTeamInterest(
                prospects: &currentDraftClass,
                teams: teams,
                players: allPlayers
            )
            ScoutingEngine.applyMockDraftToProspects(
                prospects: &currentDraftClass,
                mockDraft: currentMockDraft
            )
            mockDraftHistory["Pre-Draft"] = currentMockDraft

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .draft,
                career: career,
                teams: teams
            )

        case .otas:
            // Camp Phase 1 hook-up: apply training plan + workload tick + battles
            // for the user's team during OTAs. AI teams skip the per-player tick
            // to keep WeekAdvancer fast — their development is handled in bulk
            // at the .trainingCamp boundary via PlayerDevelopmentEngine.
            applyCampWeeklyTick(career: career, phase: .otas, modelContext: modelContext, allPlayers: allPlayers)

            // UDFA signing: AI teams auto-sign ~12 UDFAs each, present pool to player
            if !currentDraftClass.isEmpty {
                let udfaPool = ScoutingEngine.getUDFAPool(prospects: currentDraftClass)
                let aiTeams = teams.filter { $0.id != career.teamID }

                // AI teams each sign ~12 UDFAs from the pool
                var signedIDs = Set<UUID>()
                for team in aiTeams {
                    let available = udfaPool.filter { !signedIDs.contains($0.id) }
                    // Pick ~12 UDFAs weighted toward positional need
                    let toSign = Array(available.prefix(max(8, Int.random(in: 10...14))))
                    for prospect in toSign {
                        signedIDs.insert(prospect.id)
                        // Convert prospect to player signed by this AI team
                        let player = Player(
                            firstName: prospect.firstName,
                            lastName: prospect.lastName,
                            position: prospect.position,
                            age: prospect.age,
                            physical: prospect.truePhysical,
                            mental: prospect.trueMental,
                            positionAttributes: prospect.truePositionAttributes,
                            personality: prospect.truePersonality,
                            truePotential: prospect.truePotential,
                            teamID: team.id,
                            contractYearsRemaining: 3,
                            annualSalary: Int.random(in: 600...900)
                        )
                        modelContext.insert(player)
                    }
                }

                // Generate inbox message about UDFA pool for the player's team
                let playerUDFAs = udfaPool.filter { !signedIDs.contains($0.id) }
                if !playerUDFAs.isEmpty, career.teamID != nil {
                    let topNames = playerUDFAs.prefix(5).map {
                        "\($0.fullName) (\($0.position.rawValue))"
                    }.joined(separator: ", ")
                    let message = InboxMessage(
                        sender: .scout(name: "Scouting Department"),
                        subject: "UDFA Prospects Available",
                        body: "There are \(playerUDFAs.count) undrafted free agents available for signing. Top prospects: \(topNames).",
                        date: "Offseason - OTAs, Season \(career.currentSeason)",
                        category: .staffUpdate
                    )
                    lastInboxMessages.append(message)
                }
            }

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .otas,
                career: career,
                teams: teams
            )

        case .trainingCamp:
            // Camp Phase 1 hook-up: per-week training plan + workload + battles
            // for the user's team. Full-pads camp = higher intensity baseline.
            applyCampWeeklyTick(career: career, phase: .trainingCamp, modelContext: modelContext, allPlayers: allPlayers)

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
            // Camp Phase 1 hook-up: lighter intensity; preseason snaps drive perf.
            applyCampWeeklyTick(career: career, phase: .preseason, modelContext: modelContext, allPlayers: allPlayers)

            // Generate preseason news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .preseason,
                career: career,
                teams: teams
            )

        case .rosterCuts:
            // Camp Phase 1 hook-up: compute final camp grade for every player on the
            // user's team before they decide who to cut. AI teams skip the per-player
            // grade since the UI never surfaces them.
            applyCampGrades(career: career, modelContext: modelContext, allPlayers: allPlayers)

            // Resolve any open position battles -- the camp is over.
            let openBattles = fetchOpenPositionBattles(seasonYear: career.currentSeason, modelContext: modelContext)
            if !openBattles.isEmpty {
                PositionBattleTracker.resolveBattles(battles: openBattles, modelContext: modelContext)
            }

            // Player handles manually — just generate phase news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .rosterCuts,
                career: career,
                teams: teams
            )

        default:
            break
        }

        // --- Apply owner demand consequences before season starts (#248) ---
        if nextPhase == .regularSeason {
            if let playerTeamID = career.teamID,
               let playerTeam = teamsByID[playerTeamID],
               let owner = playerTeam.owner {
                let unaddressed = career.ownerDemands.filter {
                    !career.ownerDemandsAddressed.contains($0)
                }
                if !unaddressed.isEmpty {
                    let penaltyPerDemand = owner.patience <= 3 ? 15 : 10
                    let totalPenalty = unaddressed.count * penaltyPerDemand
                    owner.satisfaction = max(0, owner.satisfaction - totalPenalty)

                    let demandList = unaddressed.joined(separator: ", ")
                    let message = InboxMessage(
                        sender: .owner(name: owner.name),
                        subject: "Unaddressed Roster Demands",
                        body: "I'm disappointed you didn't address the following: \(demandList). This is going to affect my confidence in your leadership. (-\(totalPenalty) satisfaction)",
                        date: "Season \(career.currentSeason)",
                        category: .ownerDirective
                    )
                    lastInboxMessages.append(message)
                }
            }
        }

        // --- Camp Phase 1: process waivers when leaving rosterCuts ---
        // Every cut player passes through 24h waivers before the season starts.
        // Worst-record teams get higher priority. Claims stamp the cut row.
        if currentPhase == .rosterCuts && nextPhase == .regularSeason {
            processCampWaivers(career: career, teams: teams, modelContext: modelContext)
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
            emitGroupTransitionMessageIfNeeded(
                oldPhase: currentPhase,
                newPhase: nextPhase,
                season: career.currentSeason
            )
        }

        // Reset FA state when entering the free agency phase
        if nextPhase == .freeAgency {
            career.freeAgencyRound = 0
            career.freeAgencyStep = FreeAgencyStep.finalPush.rawValue
            FASigningTracker.reset()
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

    // MARK: - Private: Phase Group Transition Banner

    /// Emits an inbox message announcing a phase-group boundary crossing
    /// (e.g. Pre-Draft → Pre Season). The message is appended to
    /// `lastInboxMessages` and surfaced to the UI through the same channel
    /// as other phase-transition messages. No-op when the two phases share
    /// the same group.
    private static func emitGroupTransitionMessageIfNeeded(
        oldPhase: SeasonPhase,
        newPhase: SeasonPhase,
        season: Int
    ) {
        guard oldPhase.group != newPhase.group else { return }

        let group = newPhase.group
        let title: String
        let body: String

        switch group {
        case .postseason:
            title = "Postseason Begins"
            body = "Pro Bowl rosters announced. The hardware is being handed out."
        case .offseason:
            title = "Offseason Begins"
            body = "Time to evaluate. Coach contracts come due, the roster gets a fresh look."
        case .preDraft:
            title = "Pre-Draft Phase"
            body = "Scouts at the Combine. The road to draft night begins."
        case .preSeason:
            title = "Pre Season Begins"
            body = "OTAs open the doors. Training camp battles start. 90 \u{2192} 53."
        case .regularSeason:
            title = "Regular Season"
            body = "Lights on. Cuts settled. Time to play football."
        }

        let msg = InboxMessage(
            sender: .leagueOffice,
            subject: title,
            body: body,
            date: "Season \(season) — \(group.displayName)",
            category: .leagueNotice
        )
        lastInboxMessages.append(msg)
    }

    // MARK: - Private: Phase Ordering

    /// Returns the phase that immediately follows `phase` in the annual calendar.
    ///
    /// Full offseason → preseason chain (matches NFL calendar):
    /// playoffs → proBowl → superBowl → coachingChanges → reviewRoster → combine →
    /// freeAgency → draft → otas → trainingCamp → preseason → rosterCuts → regularSeason
    ///
    /// In-season transitions are handled by the regular-season / playoff
    /// logic and are not part of this chain.
    private static func phase(after phase: SeasonPhase) -> SeasonPhase {
        switch phase {
        case .proBowl:          return .superBowl
        case .superBowl:        return .coachingChanges
        case .coachingChanges:  return .reviewRoster
        case .reviewRoster:     return .combine
        case .combine:          return .freeAgency
        case .freeAgency:       return .proDays
        case .proDays:          return .draft
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

    /// Updates `Team.wins`/`losses`/`ties` from a played game's final score.
    /// Internal (not private) because it is shared with `LiveGameEngine.persist`.
    static func updateTeamRecords(game: Game, teamsByID: [UUID: Team]) {
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

    /// Fetches the player team's already-played regular-season game for the
    /// given week, if any. Used to detect games coached interactively via
    /// `LiveGameEngine` (they are played before `advanceWeek` runs).
    private static func fetchPlayedPlayerGame(
        week: Int,
        seasonYear: Int,
        teamID: UUID,
        modelContext: ModelContext
    ) -> Game? {
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate<Game> { game in
                game.week == week &&
                game.seasonYear == seasonYear &&
                game.isPlayoff == false &&
                game.homeScore != nil &&
                (game.homeTeamID == teamID || game.awayTeamID == teamID)
            }
        )
        return (try? modelContext.fetch(descriptor))?.first
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

    private static func fetchAllScouts(modelContext: ModelContext) -> [Scout] {
        let descriptor = FetchDescriptor<Scout>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Private: Season History Recording

    /// Inserts a `PlayerSeasonHistory` snapshot for every player at season's end.
    /// Idempotent per (playerID, season) — re-running on the same season won't
    /// duplicate rows. Captures OVR/age before offseason development changes them.
    ///
    /// NOTE: per-season aggregated stats (`keyStat1/2/3`) are not yet populated
    /// because per-game `PlayerGameStats` aren't persisted league-wide. They
    /// remain 0 until that pipeline lands. The OVR snapshot alone is enough to
    /// drive the Career Trend chart (#36 follow-up).
    private static func recordSeasonHistory(
        players: [Player],
        season: Int,
        modelContext: ModelContext
    ) {
        // Fetch any history rows already written for this season so we don't dupe.
        let existingDescriptor = FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate { $0.season == season }
        )
        let existing = (try? modelContext.fetch(existingDescriptor)) ?? []
        let existingPlayerIDs = Set(existing.map(\.playerID))

        for player in players where !existingPlayerIDs.contains(player.id) {
            let entry = PlayerSeasonHistory(
                playerID: player.id,
                season: season,
                overallAtEndOfSeason: player.overall,
                gamesPlayed: 0,            // TODO: wire when season stats persist
                ageAtEndOfSeason: player.age,
                teamID: player.teamID,
                keyStat1: 0,               // TODO: position-appropriate season totals
                keyStat2: 0,
                keyStat3: 0
            )
            modelContext.insert(entry)
        }
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

    // MARK: - Private: Owner Demand Generation (#248)

    /// Generates owner demands tied to actual roster needs (via `DraftEngine.topTeamNeeds`).
    /// Each demand is a single string that includes the weak area, a timeline, and the
    /// satisfaction consequence so the player knows exactly what's at stake.
    private static func generateOwnerDemands(owner: Owner, players: [Player]) -> [String] {
        guard !players.isEmpty else { return [] }

        // Build position-group OVR map so we can show "current ~64 OVR" context.
        let groupDefs: [(label: String, positions: [Position])] = [
            ("QB",  [.QB]),
            ("RB",  [.RB, .FB]),
            ("WR",  [.WR]),
            ("TE",  [.TE]),
            ("OL",  [.LT, .LG, .C, .RG, .RT]),
            ("DL",  [.DE, .DT]),
            ("LB",  [.OLB, .MLB]),
            ("DB",  [.CB, .FS, .SS]),
        ]
        var groupOVRByPosition: [Position: (label: String, avgOVR: Int)] = [:]
        for group in groupDefs {
            let groupPlayers = players.filter { group.positions.contains($0.position) }
            let avg = groupPlayers.isEmpty ? 0 : groupPlayers.map(\.overall).reduce(0, +) / groupPlayers.count
            for pos in group.positions {
                groupOVRByPosition[pos] = (group.label, avg)
            }
        }

        // Use DraftEngine's roster-need evaluator for priority order (matches scouting/draft logic).
        let needPositions = DraftEngine.topTeamNeeds(roster: players, limit: 5)

        // Determine demand count based on meddling.
        let demandCount: Int
        if owner.meddling >= 70 {
            demandCount = 3
        } else if owner.meddling >= 40 {
            demandCount = 2
        } else {
            demandCount = 1
        }

        // Penalty per ignored demand (mirrors application logic below).
        let penalty = owner.patience <= 3 ? 15 : 10

        var demands: [String] = []
        var seenLabels = Set<String>()

        for pos in needPositions {
            guard demands.count < demandCount else { break }
            guard let group = groupOVRByPosition[pos] else { continue }
            // Avoid duplicate position-group demands (e.g. multiple OL holes).
            guard !seenLabels.contains(group.label) else { continue }
            seenLabels.insert(group.label)

            let action: String
            let timeline: String

            // Low-meddling owners stay vague; mid/high meddling owners get specific.
            if owner.meddling < 30 {
                let side = group.label == "DL" || group.label == "LB" || group.label == "DB" ? "defense" : "offense"
                action = "Improve the \(side) (current \(group.label) avg \(group.avgOVR) OVR)"
                timeline = owner.prefersWinNow ? "before Week 1" : "this offseason"
            } else if owner.prefersWinNow {
                action = "Sign or trade for a starting-caliber \(group.label) (current avg \(group.avgOVR) OVR)"
                timeline = "before the season opener"
            } else {
                action = "Draft or develop a franchise \(group.label) (current avg \(group.avgOVR) OVR)"
                timeline = "by the end of the draft"
            }

            demands.append("\(action) — \(timeline). Ignoring costs -\(penalty) satisfaction.")
        }

        // Fallback: if we got no need positions (empty roster edge case), keep one vague demand.
        if demands.isEmpty {
            let fallback = owner.prefersWinNow ? "Make a splash signing this offseason" : "Build through the draft this offseason"
            demands.append("\(fallback) — by the season opener. Ignoring costs -\(penalty) satisfaction.")
        }

        return demands
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

    // MARK: - Camp Phase 1 Hook-ups
    //
    // The functions below glue pre-built Camp engines into the offseason flow.
    // They run only for the user's team to keep advanceWeek snappy — AI teams
    // continue to use the legacy `PlayerDevelopmentEngine.processOffseason`
    // path. If/when AI camps need the same per-week granularity, expand these
    // helpers to iterate over `teams`.

    /// Applies a single weekly camp tick: training plan deltas + 7 days of
    /// workload + per-active-battle resolutions + a HardKnocks event burst.
    /// Phase intensity:
    ///   .otas         -> 0.45 (no pads)
    ///   .trainingCamp -> 0.85 (full pads)
    ///   .preseason    -> 0.55 (lighter; preseason snaps drive most signal)
    private static func applyCampWeeklyTick(
        career: Career,
        phase: SeasonPhase,
        modelContext: ModelContext,
        allPlayers: [Player]
    ) {
        guard let teamID = career.teamID else { return }
        let roster = allPlayers.filter { $0.teamID == teamID }
        guard !roster.isEmpty else { return }

        // 1. Apply the user's saved training plan for this week. If none exists,
        //    seed a balanced 34/33/33 plan so deltas still tick forward.
        let week = career.currentWeek
        let season = career.currentSeason
        let plan = fetchOrSeedTrainingPlan(
            teamID: teamID,
            season: season,
            week: week,
            phase: phase,
            modelContext: modelContext
        )
        TrainingPlanEngine.applyWeekly(plan: plan, roster: roster, modelContext: modelContext)

        // 2. Tick 7 days of workload per player. Intensity scales with phase.
        //    Recovery rate is derived from the user team's strength coach (or
        //    physio as fallback). A 50-rated coach yields the legacy 0.55
        //    baseline; elite (99) coaches push toward 0.75; weak (1) coaches
        //    drop toward 0.40. See `computeRecoveryRate` for the mapping.
        let intensity: Double
        switch phase {
        case .otas:         intensity = 0.45
        case .trainingCamp: intensity = 0.85
        case .preseason:    intensity = 0.55
        default:            intensity = 0.5
        }
        let teamCoaches = fetchAllCoaches(modelContext: modelContext)
            .filter { $0.teamID == teamID }
        let recoveryRate = computeRecoveryRate(coaches: teamCoaches)
        for player in roster {
            for _ in 0..<7 {
                WorkloadEngine.tickDay(
                    player: player,
                    intensity: intensity,
                    recoveryRate: recoveryRate,
                    modelContext: modelContext
                )
            }
        }

        // 3. Detect/resolve position battles. Detection is idempotent per season
        //    -- we only insert if no open battles exist yet. Daily ticks fire 7x
        //    to mirror the workload week.
        let openBattles = fetchOpenPositionBattles(seasonYear: season, modelContext: modelContext)
            .filter { battle in
                // Only tick battles whose competitors belong to the user's roster.
                let competitorSet = Set(battle.competitorIDs)
                return roster.contains { competitorSet.contains($0.id) }
            }
        let battles: [PositionBattle]
        if openBattles.isEmpty {
            battles = PositionBattleTracker.detectBattles(roster: roster, modelContext: modelContext)
        } else {
            battles = openBattles
        }
        var rng = SystemRandomNumberGenerator()
        for battle in battles {
            for _ in 0..<7 {
                PositionBattleTracker.tickDay(battle: battle, rng: &rng, modelContext: modelContext)
            }
        }

        // 4. Hard Knocks storyline burst -- 1 burst per camp week for the user.
        let recentInjuries = roster.filter { $0.isInjured }
        let recentCutsDescriptor = FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> { $0.teamID == teamID && $0.seasonYear == season }
        )
        let recentCuts = (try? modelContext.fetch(recentCutsDescriptor)) ?? []
        HardKnocksNarrator.generateCampStorylines(
            battles: battles,
            recentInjuries: recentInjuries,
            recentCuts: recentCuts,
            roster: roster,
            modelContext: modelContext
        )
    }

    /// Maps the user team's strength coach (or physio as fallback) onto a
    /// WorkloadEngine recovery rate in 0.40..0.75. The rating used is
    /// `playerDevelopment` because that's the strength coach's primary focus
    /// attribute (`CoachRole.strengthCoach.focusAttributes`).
    /// - A coach rated 50 → 0.575 (close to the legacy 0.55 baseline).
    /// - A coach rated 99 → 0.749 (elite recovery program).
    /// - No qualifying coach → 0.55 (legacy fallback).
    private static func computeRecoveryRate(coaches: [Coach]) -> Double {
        let strength = coaches.first { $0.role == .strengthCoach }
        let physio = coaches.first { $0.role == .physio }
        guard let primary = strength ?? physio else { return 0.55 }
        let rating = max(1, min(99, primary.playerDevelopment))
        // 1..99 → 0.40..0.75 linear.
        return 0.40 + (Double(rating - 1) / 98.0) * 0.35
    }

    /// Fetches a saved TrainingPlan for (team, season, week, phase) or returns
    /// a balanced fallback so the engine always has something to apply.
    private static func fetchOrSeedTrainingPlan(
        teamID: UUID,
        season: Int,
        week: Int,
        phase: SeasonPhase,
        modelContext: ModelContext
    ) -> TrainingPlan {
        let phaseRaw = phase.rawValue
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> {
                $0.teamID == teamID
                    && $0.seasonYear == season
                    && $0.weekNumber == week
                    && $0.phaseRaw == phaseRaw
            }
        )
        if let saved = (try? modelContext.fetch(descriptor))?.first {
            return saved
        }
        // Ephemeral fallback — does not persist so the player's saved plan stays canonical.
        return TrainingPlan(
            seasonYear: season,
            weekNumber: week,
            phaseRaw: phaseRaw,
            tacticalPct: 34,
            physicalPct: 33,
            technicalPct: 33,
            teamID: teamID
        )
    }

    /// Fetches all unresolved position battles for the given season.
    private static func fetchOpenPositionBattles(
        seasonYear: Int,
        modelContext: ModelContext
    ) -> [PositionBattle] {
        let descriptor = FetchDescriptor<PositionBattle>(
            predicate: #Predicate<PositionBattle> {
                $0.seasonYear == seasonYear && $0.winnerID == nil
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// End-of-camp grade computation for the user's roster. Uses an estimate
    /// of training pts (10 pts/week × weeks-in-camp) and preseason snaps from
    /// `PlayerSeasonHistory` if available -- TODO replace with real stat
    /// rollup once preseason GameSimulator persists snap counts.
    private static func applyCampGrades(
        career: Career,
        modelContext: ModelContext,
        allPlayers: [Player]
    ) {
        guard let teamID = career.teamID else { return }
        let roster = allPlayers.filter { $0.teamID == teamID }
        // Approximation: 3 weeks OTAs + 4 weeks camp + 2 weeks preseason = 9 weeks.
        // Scale per-player estimated training pts off cumulativeLoad as a proxy
        // for how engaged each player has been in camp activities.
        for player in roster {
            // Load 0..200 → trainingPts 0..30 (matches CampGradeEvaluator's cap).
            let trainingPts = min(30, max(0, player.cumulativeLoad / 6))
            // Snap volume estimate from yearsPro: vets coast (40 snaps), rooks
            // earn it (70 snaps). Real preseason stats override later.
            let estimatedSnaps = player.yearsPro >= 4 ? 35 : 60
            let perfFactor: Double = {
                // Weighted from current OVR — proxy until real preseason perf lands.
                let ovr = Double(player.overall)
                return min(1.0, max(0.2, ovr / 100.0))
            }()
            let grade = CampGradeEvaluator.computeGrade(
                player: player,
                trainingPts: trainingPts,
                preseasonSnaps: estimatedSnaps,
                preseasonAvgPerf: perfFactor
            )
            player.campGrade = grade
        }
    }

    /// Runs the 24h waiver window for every cut made this season for the user's
    /// team. Worst-record teams get higher claim priority.
    private static func processCampWaivers(
        career: Career,
        teams: [Team],
        modelContext: ModelContext
    ) {
        let season = career.currentSeason
        let cutsDescriptor = FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> {
                $0.seasonYear == season && $0.claimedByTeamID == nil
            }
        )
        let cuts = (try? modelContext.fetch(cutsDescriptor)) ?? []
        guard !cuts.isEmpty else { return }

        let teamRecords = teams.map { (teamID: $0.id, wins: $0.wins, losses: $0.losses) }
        _ = WaiverWireEngine.processWaivers(
            cuts: cuts,
            teamRecords: teamRecords,
            modelContext: modelContext
        )
    }

    /// Applies the long-term attribute drift penalty when the user has prepped
    /// opponent-heavy 3+ consecutive weeks. Penalty is a flat OVR drop applied
    /// to physical.stamina (proxy for unit-wide drift -- TODO: scope to the
    /// affected unit only when scheme-attribution lands).
    private static func applyOpponentPrepDrift(
        teamID: UUID,
        season: Int,
        week: Int,
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<OpponentPrepWeek>(
            predicate: #Predicate<OpponentPrepWeek> {
                $0.teamID == teamID && $0.seasonYear == season
            }
        )
        let prep = (try? modelContext.fetch(descriptor)) ?? []
        let recent = prep.sorted { $0.weekNumber > $1.weekNumber }
        var streak = 0
        for entry in recent where entry.weekNumber < week {
            if entry.opponentPct >= 70 { streak += 1 } else { break }
        }
        let penalty = OpponentPrepEngine.driftPenalty(consecutiveOpponentWeeks: streak)
        guard penalty < 0 else { return }

        // Apply -1..-3 to stamina across the user's roster as a unit-wide proxy.
        let playerDescriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == teamID }
        )
        let roster = (try? modelContext.fetch(playerDescriptor)) ?? []
        for player in roster {
            player.physical.stamina = max(40, player.physical.stamina + penalty)
        }
    }
}
