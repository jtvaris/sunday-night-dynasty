import Foundation
import SwiftData

/// Stateless engine responsible for advancing game state by one week,
/// simulating games, and managing season/phase transitions.
enum WeekAdvancer {

    /// The result of the last player team game simulation (available after advanceWeek)
    static var lastPlayerGameResult: GameSimulator.GameResult?

    /// Teams whose weekly injury roll is skipped on the next advance because
    /// their game was played live: `LiveGameEngine` already rolled per-play
    /// injury dice for both sides at the same aggregate probability, so
    /// rolling again here would double the live coach's injury rate.
    /// Set by `LiveGameEngine.persist`, cleared at the end of `advanceWeek`.
    static var liveGameInjuryTeamIDs: Set<UUID> = []

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

    /// R24: seasons whose UDFA signing was already handled interactively at
    /// the end of Draft Day — the OTAs bulk-signing fallback must skip these.
    static var udfaStageCompletedSeasons: Set<Int> = []

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

        // The live-game injury exemption never outlives the advance it was
        // registered for (consumed by the regular-season injury pass above).
        liveGameInjuryTeamIDs = []

        // R29: persist this advance's headlines (newest first) so the News
        // screen has real content that survives app restarts. `lastNewsItems`
        // stays available for same-advance consumers (owner satisfaction).
        if !lastNewsItems.isEmpty {
            career.newsLog = lastNewsItems + career.newsLog
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
                // R27: recalculate the dedicated scouting department budget too
                owner.previousScoutingBudget = owner.scoutingBudget
                owner.scoutingBudget = BudgetEngine.calculateScoutingBudget(
                    owner: owner,
                    team: team,
                    previousSeasonWins: team.wins,
                    madePlayoffs: madePlayoffs
                )
                // R31: recalculate the dedicated medical department budget too
                owner.previousMedicalBudget = owner.medicalBudget
                owner.medicalBudget = BudgetEngine.calculateMedicalBudget(
                    owner: owner,
                    team: team,
                    previousSeasonWins: team.wins,
                    madePlayoffs: madePlayoffs
                )
            }
        }

        // 0a. R31: season-opening owner meeting for the user's team —
        // apply last review's bonus to the fresh envelope, generate this
        // season's tracked goals, and deliver the expectations message.
        if let userTeam = teams.first(where: { $0.id == career.teamID }),
           let owner = userTeam.owner {
            if let review = career.ownerSeasonReview,
               review.budgetBonusPct > 0,
               review.seasonYear == career.currentSeason - 1 {
                let bonus = 1.0 + review.budgetBonusPct
                owner.coachingBudget = Int(Double(owner.coachingBudget) * bonus)
                owner.scoutingBudget = Int(Double(owner.scoutingBudget) * bonus)
                owner.medicalBudget = Int(Double(owner.medicalBudget) * bonus)
            }

            let goals = OwnerGoalsEngine.generateSeasonGoals(
                team: userTeam,
                owner: owner,
                career: career
            )
            career.ownerSeasonGoals = goals
            // Whims from finished seasons are history now.
            career.ownerWhims = career.ownerWhims.filter { $0.seasonYear >= career.currentSeason }

            lastInboxMessages.append(OwnerPersonaEngine.seasonKickoffMessage(
                owner: owner,
                career: career,
                goals: goals
            ))
        }

        // 0b. Reset franchise tags from previous season
        let allPlayersForReset = fetchAllPlayers(modelContext: modelContext)
        for player in allPlayersForReset where player.isFranchiseTagged {
            player.isFranchiseTagged = false
        }

        // 0c. R22: a new season reopens every negotiation an insulted agent
        // froze last offseason.
        NegotiationLockRegistry.reset()

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

        // 6. R21: stale trade offers never survive into a new season.
        career.pendingTradeOffers = []

        // 6b. R28: return decisions are week-scoped calls — never carry them
        // into a new season (offseason rehab resolves the injuries anyway).
        career.pendingReturnDecisions = []

        // 6c. R32: scouting counters are per-draft-cycle allowances — they
        // were never reset before, so the user permanently ran out of
        // interviews/workouts/visits after season one.
        career.interviewsUsed = 0
        career.workoutsUsed = 0
        career.top30VisitsUsed = 0

        // 6c-2. R32: scouts' pro-day trip counters are per-cycle too (same
        // leak — `canAttendProDay` went permanently false after season one).
        for scout in fetchAllScouts(modelContext: modelContext) {
            scout.proDaysAttended = 0
            scout.proDayColleges = []
        }

        // 6d. R32: last season's owner demands were settled (the penalty was
        // applied at the rosterCuts → regularSeason boundary) — clear them so
        // stale demands don't linger in the UI. Fresh ones arrive at the next
        // reviewRoster phase.
        career.ownerDemands = []
        career.ownerDemandsAddressed = []

        // 7. R32: database hygiene — drop the concluded draft's prospect rows
        // (~350/season; the restart-restore path reads ALL persisted
        // prospects, so stale rows would pollute next season's board) and
        // games older than the season that just ended.
        purgeStaleSeasonData(career: career, modelContext: modelContext)

        // 8. R32: AI roster floor — teams that shrank below playable size
        // (retirements + expiries) re-sign veteran-minimum free agents by
        // need, or street free agents when the pool is dry.
        refillAIRosters(career: career, teams: teams, modelContext: modelContext)
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
                    awayGamePlan: awayTeam.id == userTeamID ? userPlan : nil,
                    // Deterministic per-game weather — the live coached game
                    // derives the identical value from the same game id/week.
                    weather: GameWeather.forGame(id: game.id, week: game.week)
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

        // R25: win/loss of the user's game this week — shared by the press
        // conference context and the locker-room pulse below.
        let userWonLastGame: Bool? = {
            if let coachedGameWon { return coachedGameWon }
            guard let result = playerGameResult, let playerTeamID = career.teamID else { return nil }
            if let game = unplayedGames.first(where: {
                $0.homeTeamID == playerTeamID || $0.awayTeamID == playerTeamID
            }) {
                let isHome = game.homeTeamID == playerTeamID
                return isHome ? result.homeScore > result.awayScore : result.awayScore > result.homeScore
            }
            return nil
        }()

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

        // 0a. R29: league narrative — power rankings, MVP race, storyline
        // headlines (streaks, upsets, hot seats, division races, season arc).
        // Runs before the presser so this week's fresh ranking can be quoted.
        // Presentation only: reads results, never touches them.
        let seasonGames = fetchAllGamesForSeason(seasonYear: season, modelContext: modelContext)
        let narrativeUpdate = LeagueNarrativeEngine.updateWeekly(
            previousState: career.leagueNarrative,
            teams: Array(teamsByID.values),
            players: allPlayers,
            coaches: allCoaches,
            games: seasonGames,
            career: career,
            week: week,
            season: season
        )
        career.leagueNarrative = narrativeUpdate.state

        // 0. Generate weekly press conference questions
        if let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            let lastGameWon = userWonLastGame

            // Distill concrete facts from the played game (quick-simmed or
            // live-coached — both leave their result in lastPlayerGameResult)
            // so the presser can reference what actually happened.
            let gameFacts = pressGameFacts(
                lastGameWon: lastGameWon,
                result: lastPlayerGameResult,
                playerTeamID: playerTeamID,
                allPlayers: allPlayers,
                teamsByID: teamsByID,
                narrative: narrativeUpdate.state
            )

            pendingPressConference = PressConferenceEngine.generateWeeklyPressConference(
                career: career,
                team: playerTeam,
                lastGameResult: lastGameWon,
                week: week,
                facts: gameFacts
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

        // 1b. R29: storyline headlines from the narrative engine (power
        // rankings, streaks, upsets, MVP race, division races, hot seats).
        lastNewsItems.append(contentsOf: narrativeUpdate.news)

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

                // 4. Check if the owner fires the player.
                // R31: the shell now consumes this flag (career-over screen).
                // Grace period — no mid-season firing during the first season.
                if career.totalWins + career.totalLosses > 18 {
                    wasFired = OwnerSatisfactionEngine.checkFiring(owner: owner, career: career)
                }
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

            // 4b-2. R31: Meddler owners fire off 1-2 "suggestions" a season.
            // The whim lands in the inbox; the user responds in Owner Relations.
            if let owner = playerTeam.owner,
               let whim = OwnerPersonaEngine.rollWhim(owner: owner, career: career, week: week) {
                career.ownerWhims = career.ownerWhims + [whim]
                lastInboxMessages.append(
                    OwnerPersonaEngine.whimInboxMessage(whim: whim, ownerName: owner.name)
                )
            }

            // 4c. R21: AI-initiated trade offer (~15 % chance per week until
            // the Week 8 deadline). Contenders buy, rebuilders sell — the
            // offer is persisted on the career and lands as an inbox message.
            if week <= TradeValueEngine.deadlineWeek, Int.random(in: 1...100) <= 15 {
                let activePicks = fetchActiveDraftPicks(modelContext: modelContext)
                if let offer = TradeValueEngine.generateWeeklyAIOffer(
                    userTeam: playerTeam,
                    allTeams: Array(teamsByID.values),
                    allPlayers: allPlayers,
                    allPicks: activePicks,
                    capMode: career.capMode,
                    currentSeason: season
                ) {
                    var pending = career.pendingTradeOffers
                    // Never stack duplicate offers from the same team.
                    pending.removeAll { $0.offeringTeamID == offer.proposal.offeringTeamID }
                    pending.append(offer.proposal)
                    career.pendingTradeOffers = Array(pending.suffix(5))
                    lastInboxMessages.append(
                        TradeValueEngine.offerInboxMessage(offer: offer, week: week, season: season)
                    )
                }
            }
        }

        // 4d. R22: active holdout drama for the user's team — weekly morale
        // drain, agent escalation, and the player caving around week 3-4.
        if let playerTeamID = career.teamID {
            processHoldoutWeek(
                teamID: playerTeamID,
                allPlayers: allPlayers,
                week: week,
                season: season,
                modelContext: modelContext
            )
        }

        // 4e. R25: locker room pulse — auto-resolve stale pending drama, then
        // roll a new personality-driven event (~25 % of weeks) for the user's
        // team. Choice events wait on the career; info events apply instantly.
        if let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            processLockerRoomWeek(
                career: career,
                team: playerTeam,
                allPlayers: allPlayers,
                allCoaches: allCoaches,
                wonLastGame: userWonLastGame,
                week: week,
                season: season
            )
        }

        // 5. Apply fatigue changes for players who played this week
        // (R22: holdout players are away from the facility — no game fatigue).
        for player in allPlayers where player.teamID != nil && !player.isInjured && !player.isHoldingOut {
            let fatigueGain = Int.random(in: 3...8)
            player.fatigue = min(100, player.fatigue + fatigueGain)
        }

        // 5b. Apply fatigue recovery using MedicalEngine (physio improves recovery)
        for player in allPlayers where player.teamID != nil {
            let teamPhysio = allCoaches.first { $0.teamID == player.teamID && $0.role == .physio }
            let recovery = MedicalEngine.weeklyFatigueRecovery(player: player, physio: teamPhysio)
            player.fatigue = max(0, player.fatigue - recovery)
        }

        // 6. Process injuries for players who played (medical staff reduces risk).
        //    Teams that played their game LIVE this week are exempt: the live
        //    engine already rolled per-play injury dice at the same aggregate
        //    rate (see LiveGameEngine.rollInjuries) — rolling here too would
        //    double the live coach's injury exposure.
        for player in allPlayers where player.teamID != nil && !player.isInjured && !player.isHoldingOut {
            if let teamID = player.teamID, liveGameInjuryTeamIDs.contains(teamID) { continue }
            let teamDoctor = allCoaches.first { $0.teamID == player.teamID && $0.role == .teamDoctor }
            let teamPhysio = allCoaches.first { $0.teamID == player.teamID && $0.role == .physio }
            let teamTrainer = allCoaches.first { $0.teamID == player.teamID && $0.role == .headTrainer }

            // Use MedicalEngine for injury check with medical staff awareness.
            // R40: the career's injury-frequency league setting scales (or
            // disables) the weekly roll; .normal = 1.0 = today's exact rates.
            if let injury = MedicalEngine.injuryCheck(
                player: player,
                playType: .run,  // Approximate — actual play type not tracked at weekly level
                doctor: teamDoctor,
                physio: teamPhysio,
                trainer: teamTrainer,
                frequencyMultiplier: career.injuryFrequency.riskMultiplier
            ) {
                MedicalEngine.applyInjury(
                    player: player,
                    injuryType: injury,
                    doctor: teamDoctor,
                    physio: teamPhysio,
                    season: season,
                    week: week
                )

                // R28: league star injuries make headlines.
                if player.overall >= 85, let teamID = player.teamID,
                   let team = teamsByID[teamID] {
                    lastNewsItems.append(NewsItem(
                        headline: "\(team.abbreviation) star \(player.fullName) suffers \(injury.rawValue.lowercased()) injury",
                        body: "\(team.fullName) \(player.position.rawValue) \(player.fullName) left this week's action with a \(injury.rawValue.lowercased()) injury and is expected to miss around \(player.injuryWeeksOriginal) week\(player.injuryWeeksOriginal == 1 ? "" : "s"). The medical staff has started his rehab program.",
                        category: .injury,
                        week: week,
                        season: season,
                        relatedTeamID: teamID,
                        relatedPlayerID: player.id,
                        sentiment: .negative
                    ))
                }
            }
        }

        // R28: tick down post-rush-back exposure windows (healthy players only).
        for player in allPlayers where player.rushBackWeeksRemaining > 0 && !player.isInjured {
            player.rushBackWeeksRemaining -= 1
        }

        // 7. Apply game experience for starters (approximated: high-overall rostered players)
        // (R22: holdout players don't play, so they earn no experience.)
        // R25: a young player with an active mentor in his position room
        // develops slightly faster (+10 % XP, league-wide and symmetric).
        let mentoredIDs = LockerRoomEngine.mentoredProtegeIDs(allPlayers: allPlayers)
        for player in allPlayers where player.teamID != nil && !player.isInjured && !player.isHoldingOut {
            let mentorBoost = mentoredIDs.contains(player.id) ? 1.1 : 1.0
            // Approximate starters as those with overall >= 65 or on small rosters
            if player.overall >= 65 {
                PlayerDevelopmentEngine.applyGameExperience(
                    player, gamesPlayed: 1, gamesStarted: 1, experienceBoost: mentorBoost
                )
            } else {
                PlayerDevelopmentEngine.applyGameExperience(
                    player, gamesPlayed: 1, gamesStarted: 0, experienceBoost: mentorBoost
                )
            }
        }

        // 7b. R26: weekly training-focus micro-development. Every team runs
        // the same tick; AI teams auto-focus their best young players so the
        // user gains no free edge. Gains are +1 attribute bumps capped by the
        // same potential ceiling the offseason development engine uses.
        var userFocusGains: [TrainingFocusEngine.FocusGain] = []
        var userBreakout: (player: Player, pointsGained: Int)?
        for team in teams {
            let roster = allPlayers.filter { $0.teamID == team.id }
            guard !roster.isEmpty else { continue }

            if team.id != career.teamID {
                TrainingFocusEngine.autoAssignFocus(roster: roster)
            }
            let teamCoaches = allCoaches.filter { $0.teamID == team.id }
            let gains = TrainingFocusEngine.applyWeeklyFocusTick(roster: roster, coaches: teamCoaches)

            // Rare breakout leap for a high-potential youngster (max 2/season/team).
            let breakout = TrainingFocusEngine.rollBreakout(roster: roster, season: season, teamID: team.id)
            if let breakout {
                lastNewsItems.append(NewsItem(
                    headline: "Breakout: \(breakout.player.fullName) has arrived",
                    body: "\(team.fullName) \(breakout.player.position.rawValue) \(breakout.player.fullName) has taken a massive leap in practice — coaches say the game has finally slowed down for the \(max(1, breakout.player.yearsPro))-year pro.",
                    category: .playerPerformance,
                    week: week,
                    season: season,
                    relatedTeamID: team.id,
                    relatedPlayerID: breakout.player.id,
                    sentiment: .positive
                ))
            }

            if team.id == career.teamID {
                userFocusGains = gains
                userBreakout = breakout
            }
        }

        // 7c. R26: assemble the weekly Development Report for the user's team
        // (focus gains, R25 mentor pairs, breakouts, stalled players) and
        // drop a digest in the inbox. The report screen keeps the last 10.
        if let playerTeamID = career.teamID {
            let userRoster = allPlayers.filter { $0.teamID == playerTeamID }
            let report = DevelopmentReportBuilder.buildWeeklyReport(
                roster: userRoster,
                focusGains: userFocusGains,
                breakout: userBreakout,
                week: week,
                season: season
            )
            if !report.isEmpty {
                career.developmentReports = [report] + career.developmentReports
                let focusedCount = userRoster.filter { $0.trainingFocusArea != nil }.count
                lastInboxMessages.append(
                    DevelopmentReportBuilder.inboxMessage(report: report, focusedCount: focusedCount)
                )
            }
        }

        // 8. Process existing injuries — R28 rehab with variance: the weekly
        // roll can land ahead of schedule, on track, or on a setback. Head
        // trainer skill shifts the odds (no trainer = neutral averages, so
        // quick-sim time-missed parity holds).
        var pendingDecisions = career.pendingReturnDecisions
        for player in allPlayers where player.isInjured {
            let teamTrainer = allCoaches.first { $0.teamID == player.teamID && $0.role == .headTrainer }
            let result = MedicalEngine.processWeeklyRehab(player: player, trainer: teamTrainer)

            guard player.teamID == career.teamID else { continue }

            // Inbox nudge on notable rehab swings for key players.
            let isNotable = player.overall >= 78 || player.injuryWeeksOriginal >= 4
            if !result.recovered, result.status != .onTrack, isNotable {
                let subject = result.status == .aheadOfSchedule
                    ? "\(player.lastName) ahead of schedule"
                    : "Setback in \(player.lastName)'s rehab"
                let body = result.status == .aheadOfSchedule
                    ? "\(player.fullName)'s \(player.injuryType?.rawValue.lowercased() ?? "injury") rehab is progressing faster than expected — the training staff now projects him back in \(player.injuryWeeksRemaining) week\(player.injuryWeeksRemaining == 1 ? "" : "s")."
                    : "\(player.fullName) had a setback in his \(player.injuryType?.rawValue.lowercased() ?? "injury") rehab this week. Current projection: \(player.injuryWeeksRemaining) week\(player.injuryWeeksRemaining == 1 ? "" : "s") until return."
                lastInboxMessages.append(InboxMessage(
                    sender: .developmentStaff,
                    subject: subject,
                    body: body,
                    date: "Week \(week), Season \(season)",
                    category: .playerIssue,
                    actionDestination: .roster
                ))
            }

            // R28: entering the final rehab week → offer the rush-back call.
            // Ignoring it is always safe (normal recovery next week). AI teams
            // never rush players back.
            if !result.recovered, player.injuryWeeksRemaining == 1,
               !pendingDecisions.contains(where: { $0.playerID == player.id }) {
                pendingDecisions.append(ReturnDecision(
                    playerID: player.id,
                    playerName: player.fullName,
                    injuryTypeRaw: player.injuryType?.rawValue ?? "Injury",
                    season: season,
                    week: week
                ))
                lastInboxMessages.append(InboxMessage(
                    sender: .developmentStaff,
                    subject: "\(player.lastName) nearly ready — return decision",
                    body: "\(player.fullName) (\(player.injuryType?.rawValue ?? "injury")) is one week from full clearance. He could be rushed back for this week's game, but the medical staff warns of elevated re-injury risk and a short conditioning dip. Holding him out one more week is the safe call.\n\nDecide in the Roster screen's Injury Report — if you do nothing, he completes rehab normally.",
                    date: "Week \(week), Season \(season)",
                    category: .playerIssue,
                    actionRequired: true,
                    actionDestination: .roster
                ))
            }
        }
        // Drop stale decisions (player recovered, was rushed back, or left the team).
        pendingDecisions.removeAll { decision in
            guard let player = allPlayers.first(where: { $0.id == decision.playerID }) else { return true }
            return !player.isInjured || player.teamID != career.teamID
        }
        career.pendingReturnDecisions = pendingDecisions

        // 8b. Weekly scheme learning and position training (during season, reduced intensity)
        for team in teams {
            let teamPlayers = allPlayers.filter { $0.teamID == team.id }
            let teamCoaches = allCoaches.filter { $0.teamID == team.id }
            let oc = teamCoaches.first { $0.role == .offensiveCoordinator }
            let dc = teamCoaches.first { $0.role == .defensiveCoordinator }

            for player in teamPlayers where !player.isInjured && !player.isHoldingOut {
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

        // 8b2. R36: the week's practice play. Each week of reps banks one
        // practice week; the play installs into the season's call sheet after
        // 2 weeks — 1 when the OC is a true expert in his scheme (75+).
        if let practicePlay = career.weeklyPracticePlay, let teamID = career.teamID {
            let oc = allCoaches.first {
                $0.teamID == teamID && $0.role == .offensiveCoordinator
            }
            let expertise = oc?.offensiveScheme.map { oc?.expertise(for: $0.rawValue) ?? 20 } ?? 20
            let weeksRequired = expertise >= 75 ? 1 : 2
            career.weeklyPracticeWeeksDone += 1
            if career.weeklyPracticeWeeksDone >= weeksRequired {
                career.installPracticedPlay(practicePlay)
                lastInboxMessages.append(InboxMessage(
                    sender: .developmentStaff,
                    subject: "\(practicePlay.rawValue) is installed",
                    body: "The offense has \(practicePlay.rawValue) down cold after \(weeksRequired) week\(weeksRequired == 1 ? "" : "s") of practice reps\(weeksRequired == 1 ? " — your coordinator taught it in record time" : ""). It's on the call sheet for the rest of the season.",
                    date: "Week \(week), Season \(season)",
                    category: .gamePrep
                ))
            } else {
                lastInboxMessages.append(InboxMessage(
                    sender: .developmentStaff,
                    subject: "Practice report: \(practicePlay.rawValue)",
                    body: "The unit ran \(practicePlay.rawValue) all week. One more week of reps and it's installed.",
                    date: "Week \(week), Season \(season)",
                    category: .gamePrep
                ))
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

            // R21: Deadline drama — 2-4 AI-vs-AI trades (contenders buy
            // veterans from rebuilders for picks, value-curve validated).
            // Players and picks really change teams.
            let activePicks = fetchActiveDraftPicks(modelContext: modelContext)
            let deadlineTrades = TradeValueEngine.executeDeadlineTrades(
                userTeamID: career.teamID,
                teams: Array(teamsByID.values),
                allPlayers: allPlayers,
                allPicks: activePicks,
                capMode: career.capMode,
                currentSeason: season,
                modelContext: modelContext
            )
            for trade in deadlineTrades {
                lastNewsItems.append(
                    TradeValueEngine.newsItem(for: trade, week: week, season: season)
                )
            }
            if !deadlineTrades.isEmpty {
                lastInboxMessages.append(
                    TradeValueEngine.deadlineRoundupMessage(
                        trades: deadlineTrades, week: week, season: season
                    )
                )
            }

            // Any offers the user sat on expire at the deadline.
            career.pendingTradeOffers = []
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
                    // R23: log the departure for the compensatory-pick formula
                    // (only contract expiries count — cuts never register here).
                    if let formerTeamID = player.teamID {
                        CompensatoryPickEngine.recordDeparture(
                            playerID: player.id,
                            formerTeamID: formerTeamID
                        )
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

            // R32: stage the real wild-card bracket (playoff games used to be
            // phantom weeks with no Game rows — now the champion, the draft
            // order, and career history all read actual results).
            ensurePlayoffGames(forWeek: 19, career: career, modelContext: modelContext)

            // Tell the user where their season stands.
            if let userTeamID = career.teamID {
                let allSeasonGames = fetchAllGamesForSeason(seasonYear: season, modelContext: modelContext)
                let records = StandingsCalculator.calculate(
                    games: allSeasonGames,
                    teams: Array(teamsByID.values)
                )
                var userSeed: Int?
                for conference in Conference.allCases {
                    let seeds = StandingsCalculator.playoffTeams(
                        records: records,
                        teams: Array(teamsByID.values),
                        conference: conference
                    )
                    if let index = seeds.firstIndex(where: { $0.teamID == userTeamID }) {
                        userSeed = index + 1
                    }
                }
                if let seed = userSeed {
                    let byeText = seed == 1
                        ? "As the #1 seed you have a first-round bye — your run starts in the Divisional Round."
                        : "You enter the Wild Card round as the #\(seed) seed."
                    lastInboxMessages.append(InboxMessage(
                        sender: .leagueOffice,
                        subject: "Playoff Berth Clinched",
                        body: "Congratulations — your team is in the postseason. \(byeText)",
                        date: "Week 18, Season \(season)",
                        category: .leagueNotice
                    ))
                }
            }
        }
    }

    // MARK: - Private: Locker Room Pulse (R25)

    /// Weekly locker-room tick for the user's team.
    ///
    /// Explainable rules:
    /// - A pending choice event ignored for a full week resolves itself with
    ///   the passive option — not reacting IS a decision the room notices.
    /// - Only one open situation at a time; ~25 % of weeks roll a new event
    ///   from personalities, morale, and the latest result.
    /// - Every event lands in the inbox; choice events flag "action required"
    ///   and deep-link to the Locker Room screen.
    private static func processLockerRoomWeek(
        career: Career,
        team: Team,
        allPlayers: [Player],
        allCoaches: [Coach],
        wonLastGame: Bool?,
        week: Int,
        season: Int
    ) {
        let teamPlayers = allPlayers.filter { $0.teamID == team.id }
        guard !teamPlayers.isEmpty else { return }

        // 1. Stale pending event → passive option auto-applies.
        if let pending = career.pendingLockerRoomEvent,
           pending.season != season || pending.week < week {
            if let passive = pending.options.last {
                let resolved = LockerRoomEngine.resolve(
                    event: pending, option: passive, players: teamPlayers
                )
                appendLockerRoomLog(resolved, career: career)
            }
            career.pendingLockerRoomEvent = nil
        }

        // 2. Never stack two open situations.
        guard career.pendingLockerRoomEvent == nil else { return }

        // 3. Roll a new event (~25 % chance, inside the engine).
        guard let event = LockerRoomEngine.rollWeeklyEvent(
            players: teamPlayers,
            wonLastGame: wonLastGame,
            teamWins: team.wins,
            teamLosses: team.losses,
            week: week,
            season: season
        ) else { return }

        if event.requiresResponse {
            career.pendingLockerRoomEvent = event
        } else {
            appendLockerRoomLog(event, career: career)
        }

        // 4. Surface it in the inbox.
        let oc = allCoaches.first { $0.teamID == team.id && $0.role == .offensiveCoordinator }
        let dc = allCoaches.first { $0.teamID == team.id && $0.role == .defensiveCoordinator }
        let sender: MessageSender =
            oc.map { .offensiveCoordinator(name: $0.fullName) }
            ?? dc.map { .defensiveCoordinator(name: $0.fullName) }
            ?? .media(outlet: "Team Insider")
        let bodySuffix: String = event.requiresResponse
            ? "\n\nThe room is waiting to see how you handle this. Head to the Locker Room to respond."
            : (event.resolutionSummary.map { "\n\n\($0)" } ?? "")
        lastInboxMessages.append(InboxMessage(
            sender: sender,
            subject: event.title,
            body: event.detail + bodySuffix,
            date: "Week \(week), Season \(season)",
            category: .playerIssue,
            actionRequired: event.requiresResponse,
            actionDestination: .lockerRoom
        ))
    }

    /// Prepends a resolved event to the career's locker-room log (cap 12).
    static func appendLockerRoomLog(_ event: LockerRoomEvent, career: Career) {
        var log = career.lockerRoomLog
        log.removeAll { $0.id == event.id }
        log.insert(event, at: 0)
        career.lockerRoomLog = Array(log.prefix(12))
    }

    // MARK: - Private: Holdout Drama (R22)

    /// Weekly tick for any active (unresolved) holdout on the user's team.
    ///
    /// Explainable rules:
    /// - The holdout drags the locker room down: every teammate loses 1
    ///   morale per week, the holdout himself 2.
    /// - `weeksActive` counts regular-season weeks only. At week 3 there is
    ///   a 50% chance the player caves; by week 4 he always reports back
    ///   without a new deal (morale -10).
    /// - If the front office already fixed the money (salary at/above ~95%
    ///   of market, or 2+ contract years now remaining after an extension),
    ///   the holdout auto-resolves as a settlement.
    private static func processHoldoutWeek(
        teamID: UUID,
        allPlayers: [Player],
        week: Int,
        season: Int,
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<Holdout>(
            predicate: #Predicate<Holdout> { $0.teamID == teamID && $0.resolvedAt == nil }
        )
        let activeHoldouts = (try? modelContext.fetch(descriptor)) ?? []
        guard !activeHoldouts.isEmpty else { return }

        let teamPlayers = allPlayers.filter { $0.teamID == teamID }

        for holdout in activeHoldouts {
            guard let player = teamPlayers.first(where: { $0.id == holdout.playerID }) else {
                // Player was traded or cut — the standoff is moot.
                holdout.resolvedAt = Date()
                holdout.resolution = .traded
                continue
            }

            // Keep the flag and the record in sync.
            if !player.isHoldingOut { player.isHoldingOut = true }

            // Settlement check: the front office already fixed the money.
            let market = ContractEngine.estimateMarketValue(player: player)
            let paidFairly = market > 0 && Double(player.annualSalary) >= Double(market) * 0.95
            if paidFairly || player.contractYearsRemaining >= 2 {
                player.isHoldingOut = false
                holdout.resolvedAt = Date()
                holdout.resolution = .extended
                lastInboxMessages.append(
                    holdoutSettledMessage(player: player, caved: false, week: week, season: season)
                )
                lastNewsItems.append(NewsItem(
                    headline: "\(player.fullName) holdout ends with new deal",
                    body: "\(player.fullName) is back in the building after the front office reworked his contract. Teammates welcomed the star back at practice.",
                    category: .contract,
                    week: week,
                    season: season,
                    relatedTeamID: teamID,
                    relatedPlayerID: player.id,
                    sentiment: .positive
                ))
                continue
            }

            holdout.weeksActive += 1

            // Locker-room distraction: teammates -1 morale, the holdout -2.
            for teammate in teamPlayers where teammate.id != player.id {
                teammate.morale = max(0, teammate.morale - 1)
            }
            player.morale = max(0, player.morale - 2)

            // Cave check: 50% at week 3, guaranteed at week 4.
            let caves = holdout.weeksActive >= 4 || (holdout.weeksActive == 3 && Bool.random())
            if caves {
                player.isHoldingOut = false
                player.morale = max(0, player.morale - 10)
                holdout.resolvedAt = Date()
                holdout.resolution = .playerCaved
                lastInboxMessages.append(
                    holdoutSettledMessage(player: player, caved: true, week: week, season: season)
                )
                lastNewsItems.append(NewsItem(
                    headline: "\(player.fullName) ends holdout without new deal",
                    body: "After \(holdout.weeksActive) weeks away, \(player.fullName) reported back without the contract he wanted. Sources say the star is deeply unhappy with how the standoff played out.",
                    category: .contract,
                    week: week,
                    season: season,
                    relatedTeamID: teamID,
                    relatedPlayerID: player.id,
                    sentiment: .negative
                ))
            } else {
                // Ongoing drama: the agent turns up the heat via the inbox.
                let agentName = AgentPersona.agentName(for: player.id)
                let demand = ContractEngine.estimateMarketValue(player: player)
                lastInboxMessages.append(InboxMessage(
                    sender: .playerAgent(name: agentName),
                    subject: "\(player.fullName) holdout — week \(holdout.weeksActive)",
                    body: "My client remains away from the team. He is worth $\(demand / 1000)M a year and the locker room knows it. Pay him what he has earned, or this drags on. The longer you wait, the worse it gets for everyone.",
                    date: "Week \(week), Season \(season)",
                    category: .contractRequest,
                    actionRequired: true,
                    actionDestination: .roster
                ))
            }
        }
    }

    /// Inbox message for a holdout that just ended (settlement or cave-in).
    private static func holdoutSettledMessage(
        player: Player,
        caved: Bool,
        week: Int,
        season: Int
    ) -> InboxMessage {
        let agentName = AgentPersona.agentName(for: player.id)
        if caved {
            return InboxMessage(
                sender: .playerAgent(name: agentName),
                subject: "\(player.fullName) reports back",
                body: "My client is ending his holdout and reporting to the team — not because this was resolved, but because he refuses to let his teammates down. Make no mistake: he has not forgotten how this was handled.",
                date: "Week \(week), Season \(season)",
                category: .playerIssue
            )
        }
        return InboxMessage(
            sender: .playerAgent(name: agentName),
            subject: "\(player.fullName) holdout resolved",
            body: "On behalf of my client: thank you for getting this done. \(player.firstName) is back in the building, fully committed, and ready to earn every dollar of the new deal.",
            date: "Week \(week), Season \(season)",
            category: .contractRequest
        )
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

        // R32: self-heal — make sure this round's bracket exists (covers
        // saves that entered the playoffs before real bracket games landed).
        ensurePlayoffGames(forWeek: week, career: career, modelContext: modelContext)

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

            // Note: no record update — playoff games don't touch W/L/T (R32).
        }

        // R32: user's playoff exit is worth a note (win news comes via the
        // round staging below and the Super Bowl phase).
        if let userTeamID = career.teamID,
           let userGame = unplayedGames.first(where: {
               $0.homeTeamID == userTeamID || $0.awayTeamID == userTeamID
           }),
           let loser = userGame.loserID, loser == userTeamID,
           let winnerID = userGame.winnerID,
           let opponent = teamsByID[winnerID] {
            let roundName = week == 19 ? "Wild Card round" : (week == 20 ? "Divisional Round" : "Conference Championship")
            lastInboxMessages.append(InboxMessage(
                sender: .leagueOffice,
                subject: "Season Over: Eliminated in the \(roundName)",
                body: "The \(opponent.fullName) ended your playoff run \(max(userGame.homeScore ?? 0, userGame.awayScore ?? 0))-\(min(userGame.homeScore ?? 0, userGame.awayScore ?? 0)). Time to regroup — the offseason starts soon.",
                date: "Week \(week), Season \(career.currentSeason)",
                category: .leagueNotice
            ))
        }

        if week >= 21 {
            // R32: conference title games are decided — stage the Super Bowl
            // game so the `.superBowl` phase simulates a real matchup.
            ensurePlayoffGames(forWeek: 22, career: career, modelContext: modelContext)

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

            // R32: stage the next round from this round's winners so the
            // dashboard can show (and the user can coach) the upcoming game.
            ensurePlayoffGames(forWeek: career.currentWeek, career: career, modelContext: modelContext)
        }
    }

    // MARK: - Private: Playoff Bracket (R32)

    /// Creates the playoff games for one round when they don't exist yet.
    /// Idempotent per (season, week). Seeding uses the same
    /// `StandingsCalculator` rules as the standings screen:
    /// - Week 19 (Wild Card): per conference 2v7, 3v6, 4v5 — seed 1 has a bye.
    /// - Week 20 (Divisional): seed 1 + wild-card winners; best surviving
    ///   seed hosts the worst.
    /// - Week 21 (Conference Championship): divisional winners, better seed hosts.
    /// - Week 22 (Super Bowl): the two conference champions; the better
    ///   regular-season record is the designated "home" side (neutral site).
    ///
    /// If a previous round is missing (legacy saves mid-playoffs), the round
    /// falls back to the top seeds so the bracket always completes.
    private static func ensurePlayoffGames(
        forWeek week: Int,
        career: Career,
        modelContext: ModelContext
    ) {
        guard (19...22).contains(week) else { return }
        let season = career.currentSeason

        let existingDescriptor = FetchDescriptor<Game>(
            predicate: #Predicate<Game> {
                $0.seasonYear == season && $0.week == week && $0.isPlayoff == true
            }
        )
        let existing = (try? modelContext.fetch(existingDescriptor)) ?? []
        guard existing.isEmpty else { return }

        let teams = fetchAllTeams(modelContext: modelContext)
        let seasonGames = fetchAllGamesForSeason(seasonYear: season, modelContext: modelContext)
        let records = StandingsCalculator.calculate(games: seasonGames, teams: teams)
        let playoffGames = seasonGames.filter { $0.isPlayoff }

        var newGames: [Game] = []
        // Conference champion (winner of week 21) per conference, for the SB.
        var conferenceChampions: [UUID] = []

        for conference in Conference.allCases {
            let seeds = StandingsCalculator.playoffTeams(
                records: records,
                teams: teams,
                conference: conference
            )
            guard seeds.count >= 7 else { continue }
            let seedRank: [UUID: Int] = Dictionary(
                uniqueKeysWithValues: seeds.enumerated().map { ($0.element.teamID, $0.offset) }
            )
            let conferenceTeamIDs = Set(seeds.map(\.teamID))

            /// Winners of the given playoff week belonging to this conference.
            func roundWinners(week: Int) -> [UUID] {
                playoffGames
                    .filter { $0.week == week && conferenceTeamIDs.contains($0.homeTeamID) }
                    .compactMap(\.winnerID)
            }
            /// Sorts surviving teams best seed first.
            func bySeed(_ ids: [UUID]) -> [UUID] {
                ids.sorted { (seedRank[$0] ?? 8) < (seedRank[$1] ?? 8) }
            }

            switch week {
            case 19:
                // 2v7, 3v6, 4v5 (0-based seed indices).
                for (home, away) in [(1, 6), (2, 5), (3, 4)] {
                    newGames.append(Game(
                        seasonYear: season, week: 19,
                        homeTeamID: seeds[home].teamID,
                        awayTeamID: seeds[away].teamID,
                        isPlayoff: true
                    ))
                }

            case 20:
                let wildCardWinners = roundWinners(week: 19)
                let alive: [UUID] = wildCardWinners.count == 3
                    ? bySeed([seeds[0].teamID] + wildCardWinners)
                    : seeds.prefix(4).map(\.teamID)   // legacy-save fallback
                guard alive.count >= 4 else { continue }
                newGames.append(Game(
                    seasonYear: season, week: 20,
                    homeTeamID: alive[0], awayTeamID: alive[3], isPlayoff: true
                ))
                newGames.append(Game(
                    seasonYear: season, week: 20,
                    homeTeamID: alive[1], awayTeamID: alive[2], isPlayoff: true
                ))

            case 21:
                let divisionalWinners = roundWinners(week: 20)
                let alive: [UUID] = divisionalWinners.count == 2
                    ? bySeed(divisionalWinners)
                    : seeds.prefix(2).map(\.teamID)   // legacy-save fallback
                guard alive.count >= 2 else { continue }
                newGames.append(Game(
                    seasonYear: season, week: 21,
                    homeTeamID: alive[0], awayTeamID: alive[1], isPlayoff: true
                ))

            case 22:
                let titleGameWinners = roundWinners(week: 21)
                if let champion = titleGameWinners.first {
                    conferenceChampions.append(champion)
                } else if let topSeed = seeds.first {
                    conferenceChampions.append(topSeed.teamID)   // fallback
                }

            default:
                break
            }
        }

        // Super Bowl: cross-conference — better regular-season record "hosts".
        if week == 22, conferenceChampions.count == 2 {
            let recordByID = Dictionary(uniqueKeysWithValues: records.map { ($0.teamID, $0) })
            let sorted = conferenceChampions.sorted {
                (recordByID[$0]?.winPercentage ?? 0) > (recordByID[$1]?.winPercentage ?? 0)
            }
            newGames.append(Game(
                seasonYear: season, week: 22,
                homeTeamID: sorted[0], awayTeamID: sorted[1], isPlayoff: true
            ))
        }

        for game in newGames {
            modelContext.insert(game)
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

            // R31: end-of-season owner review — goals vs results, verdict,
            // and consequences (bonus budget next season / warning / firing).
            // Runs here while the final records are still intact.
            if let playerTeamID = career.teamID,
               let playerTeam = teamsByID[playerTeamID],
               let owner = playerTeam.owner {
                // Old saves may predate persisted goals — fall back to the
                // same deterministic generation the Goals screen shows.
                let baseGoals = career.ownerSeasonGoals.isEmpty
                    ? OwnerGoalsEngine.generateSeasonGoals(team: playerTeam, owner: owner, career: career)
                    : career.ownerSeasonGoals
                let evaluated = OwnerGoalsEngine.evaluateGoalProgress(
                    goals: baseGoals,
                    team: playerTeam,
                    career: career
                )
                career.ownerSeasonGoals = evaluated

                let review = OwnerPersonaEngine.evaluateSeason(
                    owner: owner,
                    team: playerTeam,
                    career: career,
                    goals: evaluated
                )
                career.ownerSeasonReview = review
                lastInboxMessages.append(
                    OwnerPersonaEngine.reviewInboxMessage(review: review, ownerName: owner.name)
                )
                if review.verdict == .fired {
                    wasFired = true
                }
            }

            // R32: close the book on the season — champion, user record, and
            // MVP into career history; increment the career counters
            // (totalWins/playoffAppearances/championships) that the dashboard
            // and fired-summary screens read but nothing ever wrote before.
            recordSeasonSummary(
                career: career,
                teams: teams,
                teamsByID: teamsByID,
                modelContext: modelContext
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

            // R32: the annual retirement wave — the offseason's first move,
            // before free agency, so departures actually leave the league
            // (rostered players, holdouts, AND unsigned free agents).
            // Star ceremonies, user-team farewells, and the Hall of Fame
            // induction class all come out of this pass.
            processPlayerRetirements(
                career: career,
                teamsByID: teamsByID,
                allPlayers: allPlayers,
                modelContext: modelContext
            )

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

            // R30: Evaluate coaching-tree alumni against last season's results.
            // Alumni whose new teams won big flip to "successful" — the tree
            // grows the user's reputation (small legacy bonus, capped at +2).
            evaluateCoachingTreeAlumni(
                career: career,
                teams: teams,
                allCoaches: allCoaches
            )

            // R30: fresh offseason, fresh carousel feed.
            career.coachCarouselLog = []

            // Check coordinator poaching for all teams (legacy system)
            let coordinatorRoles: Set<CoachRole> = [
                .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator
            ]
            for team in teams {
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                var poached = CoachingEngine.checkCoordinatorPoaching(
                    coaches: teamCoaches,
                    teamWins: team.wins
                )
                // R30: the user's coordinators only leave with the user's
                // consent (interview-request flow) — position coaches can
                // still be hired away silently.
                if team.id == career.teamID {
                    poached.removeAll { coordinatorRoles.contains($0.role) }
                }
                // Poached coaches leave the team
                for coach in poached {
                    if team.id == career.teamID {
                        var tree = career.coachingTree
                        CoachRelationshipEngine.recordDeparture(
                            tree: &tree.entries,
                            coach: coach,
                            event: "departed_other",
                            season: career.currentSeason,
                            destination: "Hired away by another organization"
                        )
                        career.coachingTree = tree
                    }
                    coach.teamID = nil
                }
            }

            // HC promotion poaching (NFL-realistic coordinator-to-HC pipeline).
            // R30: AI teams only — the user's coordinators go through the
            // interview-request flow instead of vanishing overnight.
            for team in teams where team.id != career.teamID {
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                let poached = CoachingEngine.checkHCPromotionPoaching(
                    coaches: teamCoaches,
                    teamWins: team.wins
                )
                for coach in poached {
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

                        // R30: retirements close out the coaching-tree entry.
                        var tree = career.coachingTree
                        CoachRelationshipEngine.recordDeparture(
                            tree: &tree.entries,
                            coach: coach,
                            event: "retired",
                            season: career.currentSeason
                        )
                        career.coachingTree = tree
                    }
                    coach.teamID = nil  // Remove from team
                }
            }

            // MARK: R30 — Black Monday: the league-wide coaching carousel.
            // Struggling AI teams fire their HCs (record + R29 hot-seat data),
            // vacancies fill from rising coordinators and recycled HCs, and
            // the coordinator seats those promotions empty fill in a chain.
            let userTeamWins = teams.first { $0.id == career.teamID }?.wins ?? 0
            let carousel = CoachCarouselEngine.runBlackMonday(
                teams: teams,
                allCoaches: allCoaches,
                userTeamID: career.teamID,
                userTeamWins: userTeamWins,
                hotSeatTeamIDs: career.leagueNarrative?.hotSeatReported ?? [],
                season: career.currentSeason
            )
            for coach in carousel.newCoaches {
                modelContext.insert(coach)
            }
            lastNewsItems.append(contentsOf: carousel.news)
            career.coachCarouselLog = Array(carousel.moves.reversed()) + career.coachCarouselLog

            // R30: an AI team wants to interview one of the user's
            // coordinators for its HC vacancy — the user decides in the
            // Staff view (allow / block). Expires at the Combine if ignored.
            if let request = carousel.interviewRequest {
                career.pendingInterviewRequest = request
                newMessages.append(InboxMessage(
                    sender: .leagueOffice,
                    subject: "Interview Request: \(request.coachName)",
                    body: "The \(request.requestingTeamName) have requested permission to interview your \(request.coachRole.displayName.lowercased()) \(request.coachName) for their head coach vacancy. Your team's success has made your staff hot names around the league.\n\nGo to your Coaching Staff screen to allow or block the interview. If you allow it and \(request.coachName) is hired, they join your coaching tree — and you will receive a compensatory 3rd round draft pick.",
                    date: "Offseason - Coaching Changes, Season \(career.currentSeason)",
                    category: .staffUpdate,
                    actionRequired: true,
                    actionDestination: .coachingStaff
                ))
            }

            // R32: after the carousel has settled, AI teams fill every
            // remaining staff vacancy so league coaching quality holds up
            // across a 10-season career.
            refillAIStaffVacancies(
                career: career,
                teams: teams,
                modelContext: modelContext
            )

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

            // R30: an unanswered interview request expires here — the club
            // moved on, the coordinator stays (no hard feelings).
            if let request = career.pendingInterviewRequest {
                if let reqTeam = teams.first(where: { $0.id == request.requestingTeamID }),
                   !allCoaches.contains(where: { $0.teamID == reqTeam.id && $0.role == .headCoach }),
                   let newHC = CoachingEngine.generateCoachCandidates(role: .headCoach, count: 1).first {
                    newHC.teamID = reqTeam.id
                    newHC.hireSeasonYear = career.currentSeason
                    newHC.contractYearsRemaining = 4
                    modelContext.insert(newHC)
                    lastNewsItems.append(NewsItem(
                        headline: "\(reqTeam.fullName) name \(newHC.fullName) head coach",
                        body: "With their interview request for \(request.coachName) left unanswered, the \(reqTeam.fullName) have moved on and hired \(newHC.fullName) as their next head coach.",
                        category: .coachingChange,
                        week: 0,
                        season: career.currentSeason,
                        relatedTeamID: reqTeam.id,
                        sentiment: .neutral
                    ))
                }
                lastInboxMessages.append(InboxMessage(
                    sender: .leagueOffice,
                    subject: "Interview Window Closed: \(request.coachName)",
                    body: "The \(request.requestingTeamName) have withdrawn their interview request for \(request.coachName) and filled their head coach vacancy elsewhere. \(request.coachName) remains on your staff.",
                    date: "Offseason - Combine, Season \(career.currentSeason)",
                    category: .staffUpdate
                ))
                career.pendingInterviewRequest = nil
            }

            lastNewsItems.append(contentsOf: NewsGenerator.generateOffseasonNews(
                phase: .combine,
                career: career,
                teams: teams
            ))

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

            // R23 — Compensatory picks: the market has closed, settle the
            // departure ledger into extra round 3-7 picks for net FA losers.
            settleCompensatoryPicks(
                career: career,
                teams: teams,
                allPlayers: allPlayers,
                modelContext: modelContext
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
            // The draft order was prepared when this phase was ENTERED (see
            // `prepareDraftOrder` below) so the war room had real picks to
            // run on — here the concluded draft only emits its news.
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

            // UDFA signing: AI teams auto-sign ~12 UDFAs each, present pool to player.
            // R24: skipped entirely when the interactive Draft Day UDFA stage
            // already handled this season's undrafted market.
            if !currentDraftClass.isEmpty,
               !udfaStageCompletedSeasons.contains(career.currentSeason) {
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
            // (R22: holdout players skip camp entirely — no development).
            for team in teams {
                let teamPlayers = allPlayers.filter { $0.teamID == team.id && !$0.isHoldingOut }
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                _ = PlayerDevelopmentEngine.processOffseason(
                    players: teamPlayers,
                    coaches: teamCoaches
                )
            }

            // Note: processOffseason already calls applyAgeRegression which increments
            // player.age and player.yearsPro, so no separate age increment needed.

            // R32: holdouts skip camp DEVELOPMENT but still get a year older,
            // and unsigned free agents age too. Before this fix both groups
            // were frozen in time — they never regressed and never retired,
            // which slowly corrupted multi-season careers.
            for player in allPlayers where !player.isRetired {
                let agedByCamp = player.teamID != nil && !player.isHoldingOut
                if !agedByCamp {
                    PlayerDevelopmentEngine.applyAgeRegression(player)
                    player.fatigue = 0
                }
            }

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

            // R32: league-wide final cutdown — AI teams trim to the roster
            // ceiling when the user does theirs. Draft classes + UDFA waves
            // + FA signings add ~15-20 players/season and nothing ever cut
            // AI rosters before, so multi-season leagues ballooned past 90.
            trimAIRosters(career: career, teams: teams, allPlayers: allPlayers)

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

        // R32: the draft order must exist BEFORE the draft phase begins —
        // the war room reads persisted picks for the current season the
        // moment it opens. Previously the order was generated when LEAVING
        // the draft phase (and stamped with the season-cycle year), so from
        // season 2 onward the draft room found no picks, comp picks attached
        // after the fact, and the league never restocked through the draft.
        if nextPhase == .draft {
            prepareDraftOrder(
                career: career,
                teams: teams,
                allPlayers: allPlayers,
                modelContext: modelContext
            )
        }

        // Reset FA state when entering the free agency phase
        if nextPhase == .freeAgency {
            career.freeAgencyRound = 0
            career.freeAgencyStep = FreeAgencyStep.finalPush.rawValue
            career.faVisitsUsed = 0
            FASigningTracker.reset()

            // R23 — Legal tampering window: leak market projections and early
            // suitors for the top upcoming FAs before the market opens. The
            // rumors quote the same pricing/need model the market itself uses.
            let rumors = TamperingRumorEngine.generateRumors(
                allPlayers: allPlayers,
                allTeams: teams,
                userTeamID: career.teamID
            )
            if let digest = TamperingRumorEngine.inboxDigest(rumors: rumors, season: career.currentSeason) {
                lastInboxMessages.append(digest)
            }
            lastNewsItems.append(contentsOf: TamperingRumorEngine.newsItems(
                rumors: rumors,
                week: career.currentWeek,
                season: career.currentSeason
            ))
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

    // MARK: - Private: Draft Order Preparation (R32)

    /// Ensures the current season's draft has a full, persisted pick order the
    /// moment the `.draft` phase begins. Runs at the proDays → draft boundary.
    ///
    /// - Season 1 reuses the league-generation pool (the real first-round
    ///   order) — including any comp picks already slotted into it at the
    ///   close of free agency.
    /// - Season 2+ generates a fresh 224-pick order from the just-finished
    ///   season's standings and attaches comp picks stashed at FA close.
    ///
    /// The pool is exposed via `currentDraftPicks` and the final pre-draft
    /// mock projection is computed here so the war room, dashboards, and
    /// prospect boards all see the actual order before the first selection.
    private static func prepareDraftOrder(
        career: Career,
        teams: [Team],
        allPlayers: [Player],
        modelContext: ModelContext
    ) {
        let season = career.currentSeason
        let existingDescriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate<DraftPick> {
                $0.seasonYear == season && $0.isComplete == false
            }
        )
        var draftPicks = (try? modelContext.fetch(existingDescriptor)) ?? []

        if draftPicks.isEmpty {
            // Season 2+: build the order from the season that just ended.
            let allGames = fetchAllGamesForSeason(
                seasonYear: season,
                modelContext: modelContext
            )
            draftPicks = DraftEngine.generateDraftOrder(
                teams: teams,
                games: allGames,
                seasonYear: season
            )
            for pick in draftPicks {
                modelContext.insert(pick)
            }
        }

        // R23 — attach compensatory picks awarded at the close of free
        // agency (if they weren't already slotted into a persisted pool).
        let pendingComp = CompensatoryPickEngine.pendingAwards()
        if !pendingComp.isEmpty {
            var teamAbbrs: [UUID: String] = [:]
            for team in teams { teamAbbrs[team.id] = team.abbreviation }
            let compPicks = CompensatoryPickEngine.applyAwards(
                pendingComp,
                toPickPool: draftPicks,
                seasonYear: season,
                teamAbbrs: teamAbbrs
            )
            for pick in compPicks {
                modelContext.insert(pick)
            }
            draftPicks.append(contentsOf: compPicks)
            CompensatoryPickEngine.clearPendingAwards()
        }

        draftPicks.sort { $0.pickNumber < $1.pickNumber }
        currentDraftPicks = draftPicks

        // Pre-draft mock draft (final projection with the actual order).
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
    }

    // MARK: - Private: Compensatory Picks (R23)

    /// Settles the FA departure ledger into compensatory picks at the close of
    /// free agency. If an upcoming draft pool is already persisted (e.g. the
    /// league-generation pool for the first draft), the comp picks are slotted
    /// straight into it; otherwise they are stashed and attached when the
    /// draft order is generated. Emits an inbox message for the user's haul
    /// and a news item for the biggest league-wide winner.
    private static func settleCompensatoryPicks(
        career: Career,
        teams: [Team],
        allPlayers: [Player],
        modelContext: ModelContext
    ) {
        let departures = CompensatoryPickEngine.departures()
        guard !departures.isEmpty else { return }

        let awards = CompensatoryPickEngine.computeAwards(
            departures: departures,
            allPlayers: allPlayers,
            allTeams: teams
        )
        CompensatoryPickEngine.clearDepartures()
        guard !awards.isEmpty else {
            CompensatoryPickEngine.clearPendingAwards()
            return
        }

        var teamAbbrs: [UUID: String] = [:]
        for team in teams { teamAbbrs[team.id] = team.abbreviation }

        // Slot into an already-persisted upcoming pool when one exists;
        // otherwise leave the awards pending for draft-order generation.
        let season = career.currentSeason
        let poolDescriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate<DraftPick> { $0.seasonYear == season && $0.isComplete == false }
        )
        let existingPool = (try? modelContext.fetch(poolDescriptor)) ?? []
        if existingPool.count >= 32 {
            let compPicks = CompensatoryPickEngine.applyAwards(
                awards,
                toPickPool: existingPool,
                seasonYear: season,
                teamAbbrs: teamAbbrs
            )
            for pick in compPicks { modelContext.insert(pick) }
            CompensatoryPickEngine.clearPendingAwards()
        } else {
            CompensatoryPickEngine.stashPendingAwards(awards)
        }

        // Inbox: the user's own compensatory haul.
        if let userTeamID = career.teamID {
            let mine = awards.filter { $0.teamID == userTeamID }
            if !mine.isEmpty {
                let lines = mine.map { award in
                    "\u{2022} Round \(award.round) — for losing \(award.lostPlayerName) ($\(String(format: "%.1f", Double(award.lostPlayerSalary) / 1000.0))M/yr elsewhere)"
                }
                lastInboxMessages.append(InboxMessage(
                    sender: .leagueOffice,
                    subject: "Compensatory Picks Awarded",
                    body: """
                    The league has finalized compensatory selections for the upcoming draft. Based on your net free agency losses, you receive:

                    \(lines.joined(separator: "\n"))

                    Compensatory picks slot in at the end of their round.
                    """,
                    date: "Offseason - Free Agency, Season \(career.currentSeason)",
                    category: .leagueNotice
                ))
            }
        }

        // News: the biggest comp-pick winner league-wide.
        let byTeam = Dictionary(grouping: awards, by: { $0.teamID })
        if let (topTeamID, topAwards) = byTeam.max(by: { $0.value.count < $1.value.count }) {
            let abbr = teamAbbrs[topTeamID] ?? "???"
            let rounds = topAwards.map { "R\($0.round)" }.joined(separator: ", ")
            lastNewsItems.append(NewsItem(
                headline: "\(abbr) lead comp-pick haul with \(topAwards.count) extra selection\(topAwards.count == 1 ? "" : "s")",
                body: "The league finalized compensatory picks for the upcoming draft. \(abbr) top the list (\(rounds)) after their net free agency losses. \(awards.count) compensatory selection\(awards.count == 1 ? "" : "s") were awarded in total.",
                category: .draft,
                week: career.currentWeek,
                season: career.currentSeason,
                relatedTeamID: topTeamID,
                sentiment: .neutral
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
    ///
    /// R32: playoff games never touch these fields — `Team.wins/losses/ties`
    /// are the REGULAR-SEASON record that standings, budgets, and owner goals
    /// all read. Playoff outcomes live in the bracket games themselves.
    /// (Before R32 the postseason had no real Game rows, so this guard
    /// changes nothing for existing behavior.)
    static func updateTeamRecords(game: Game, teamsByID: [UUID: Team]) {
        guard !game.isPlayoff else { return }
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

    /// Distills the player's last game result into the concrete facts the
    /// weekly press conference can quote (final margin, sacks allowed, a
    /// 100-yard rusher). Returns nil when the player had no played game this
    /// week — the presser then falls back to its pre-R18 question selection.
    ///
    /// `PlayerGameStats` carries no team id, so team membership is resolved
    /// via the live rosters: every stat line whose player is NOT on the
    /// player's roster belongs to the opponent (both game rosters are fully
    /// covered by `result.playerStats`).
    private static func pressGameFacts(
        lastGameWon: Bool?,
        result: GameSimulator.GameResult?,
        playerTeamID: UUID,
        allPlayers: [Player],
        teamsByID: [UUID: Team],
        narrative: LeagueNarrativeState? = nil
    ) -> PressConferenceEngine.GameFacts? {
        guard let won = lastGameWon, let result else { return nil }

        let playerTeamPlayerIDs = Set(
            allPlayers.filter { $0.teamID == playerTeamID }.map(\.id)
        )
        guard !playerTeamPlayerIDs.isEmpty else { return nil }

        let margin = abs(result.homeScore - result.awayScore)

        // Sacks the player's line surrendered = opponent defenders' sacks.
        let sacksAllowed = Int(
            result.playerStats
                .filter { !playerTeamPlayerIDs.contains($0.playerID) }
                .reduce(0.0) { $0 + $1.sacks }
                .rounded()
        )

        let topRusher = result.playerStats
            .filter { playerTeamPlayerIDs.contains($0.playerID) && $0.rushingYards >= 100 }
            .max { $0.rushingYards < $1.rushingYards }

        // Division matchup (R19): the box score names both teams — when the
        // opponent shares the player's division, the presser gets the rivalry
        // variants of the win/loss questions.
        let opponentID = result.boxScore.home.teamID == playerTeamID
            ? result.boxScore.away.teamID
            : result.boxScore.home.teamID
        let divisionOpponentAbbr: String? = {
            guard let myTeam = teamsByID[playerTeamID],
                  let opponent = teamsByID[opponentID],
                  opponent.conference == myTeam.conference,
                  opponent.division == myTeam.division
            else { return nil }
            return opponent.abbreviation
        }()

        // R29: this week's power ranking + MVP-race hooks for the presser.
        let rankingEntry = narrative?.rankings.first { $0.teamID == playerTeamID }
        let mvpEntry = narrative?.mvpRace.enumerated().first { $0.element.teamID == playerTeamID }

        return PressConferenceEngine.GameFacts(
            won: won,
            margin: margin,
            sacksAllowed: sacksAllowed,
            hundredYardRusherName: topRusher?.playerName,
            hundredYardRusherYards: topRusher?.rushingYards ?? 0,
            divisionOpponentAbbr: divisionOpponentAbbr,
            powerRank: rankingEntry?.rank,
            powerRankMovement: rankingEntry?.movement ?? 0,
            mvpCandidateName: mvpEntry?.element.playerName,
            mvpCandidateRank: mvpEntry.map { $0.offset + 1 }
        )
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

    // MARK: - R30: Coaching Tree Alumni Evaluation

    /// Once per offseason: checks how the user's coaching-tree alumni fared at
    /// their new stops. An alumnus on a team that won 10+ games flips to
    /// "successful", which grows the tree's legacy score — and the user's own
    /// reputation gets a small bump (+1 per newly successful alumnus, max +2
    /// per season) with a news nod for the first one.
    private static func evaluateCoachingTreeAlumni(
        career: Career,
        teams: [Team],
        allCoaches: [Coach]
    ) {
        var tree = career.coachingTree
        guard !tree.alumni.isEmpty else { return }

        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        var reputationGain = 0
        var firstSuccess: (coachName: String, teamName: String, role: CoachRole)?

        for entry in tree.alumni where !entry.wasSuccessful {
            // Alumni are tracked by name snapshot — find them in the league.
            guard let coach = allCoaches.first(where: {
                      $0.fullName == entry.coachName && $0.teamID != nil && $0.teamID != career.teamID
                  }),
                  let team = coach.teamID.flatMap({ teamsByID[$0] })
            else { continue }

            // Success at the next stop: a clearly winning season.
            guard team.wins >= 10 else { continue }

            CoachRelationshipEngine.markCoachingTreeSuccess(
                tree: &tree.entries,
                coachName: entry.coachName,
                wasSuccessful: true
            )
            if reputationGain < 2 { reputationGain += 1 }
            if firstSuccess == nil {
                firstSuccess = (entry.coachName, team.fullName, coach.role)
            }
        }

        guard reputationGain > 0, let success = firstSuccess else {
            career.coachingTree = tree
            return
        }

        career.coachingTree = tree
        career.reputation = min(99, career.reputation + reputationGain)

        lastNewsItems.append(NewsItem(
            headline: "Coaching tree watch: \(success.coachName) thriving",
            body: "\(success.coachName), who cut their teeth on \(career.playerName)'s staff, just led the \(success.teamName) to a double-digit win season as \(success.role.displayName.lowercased()). Around the league, \(career.playerName)'s coaching tree keeps gaining respect.",
            category: .coachingChange,
            week: 0,
            season: career.currentSeason,
            sentiment: .positive
        ))
    }

    private static func fetchAllScouts(modelContext: ModelContext) -> [Scout] {
        let descriptor = FetchDescriptor<Scout>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Draft picks that haven't been used yet — the tradable pick pool (R21).
    private static func fetchActiveDraftPicks(modelContext: ModelContext) -> [DraftPick] {
        let descriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate { !$0.isComplete }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Private: Season Summary & Career Counters (R32)

    /// Writes the finished season into `career.seasonSummaries` (champion,
    /// user record, MVP) and increments the career-long counters. Runs during
    /// the `.superBowl` phase, right after the title game has been simulated
    /// and while the final records are still intact. Idempotent per season.
    private static func recordSeasonSummary(
        career: Career,
        teams: [Team],
        teamsByID: [UUID: Team],
        modelContext: ModelContext
    ) {
        let season = career.currentSeason
        guard !career.seasonSummaries.contains(where: { $0.season == season }) else { return }

        let seasonGames = fetchAllGamesForSeason(seasonYear: season, modelContext: modelContext)
        let playoffGames = seasonGames.filter { $0.isPlayoff }
        let superBowlGame = playoffGames.first { $0.week == 22 && $0.isPlayed }

        // Champion = Super Bowl winner; fallback (legacy edge) = best record.
        let championID: UUID? = superBowlGame?.winnerID
            ?? teams.max {
                ($0.wins, $1.losses) < ($1.wins, $0.losses)
            }?.id
        let championName = championID.flatMap { teamsByID[$0]?.fullName } ?? "Unknown"

        var userWins = 0, userLosses = 0, userTies = 0
        var madePlayoffs = false
        var wonChampionship = false
        if let userTeamID = career.teamID, let userTeam = teamsByID[userTeamID] {
            userWins = userTeam.wins
            userLosses = userTeam.losses
            userTies = userTeam.ties
            // Every bracket team plays at least one playoff game (the #1 seed
            // appears in the Divisional Round), so participation covers it.
            madePlayoffs = playoffGames.contains {
                $0.homeTeamID == userTeamID || $0.awayTeamID == userTeamID
            }
            wonChampionship = (championID == userTeamID)
        }

        let mvp = career.leagueNarrative?.mvpRace.first

        let summary = SeasonSummary(
            season: season,
            championTeamID: championID,
            championTeamName: championName,
            userWins: userWins,
            userLosses: userLosses,
            userTies: userTies,
            userMadePlayoffs: madePlayoffs,
            userWonChampionship: wonChampionship,
            mvpName: mvp?.playerName,
            mvpTeamAbbr: mvp?.teamAbbr
        )
        career.seasonSummaries = [summary] + career.seasonSummaries

        // Career-long counters (regular-season record only; the playoff
        // guard in `updateTeamRecords` keeps team W/L regular-season-pure).
        career.totalWins += userWins
        career.totalLosses += userLosses
        if madePlayoffs { career.playoffAppearances += 1 }
        if wonChampionship {
            career.championships += 1
            career.legacy.recordAchievement(LegacyTracker.LegacyAchievement(
                title: "Super Bowl Champion",
                description: "Won the Season \(season) championship.",
                points: 100,
                season: season
            ))
            lastInboxMessages.append(InboxMessage(
                sender: .leagueOffice,
                subject: "WORLD CHAMPIONS",
                body: "Your team has won the Super Bowl. The city is planning the parade — enjoy this one, coach. It goes on your legacy forever.",
                date: "Super Bowl, Season \(season)",
                category: .leagueNotice
            ))
        }

        // Championship headline for the league feed.
        if let championID, let champion = teamsByID[championID] {
            let scoreLine: String
            if let game = superBowlGame,
               let home = game.homeScore, let away = game.awayScore,
               let loserID = game.loserID,
               let loser = teamsByID[loserID] {
                scoreLine = "They defeated the \(loser.fullName) \(max(home, away))-\(min(home, away)) in the title game."
            } else {
                scoreLine = "They finished the year as the league's best team."
            }
            let mvpLine = mvp.map { " Season MVP honors went to \($0.playerName) (\($0.teamAbbr))." } ?? ""
            lastNewsItems.append(NewsItem(
                headline: "\(champion.fullName) win the Super Bowl",
                body: "The \(champion.fullName) are the Season \(season) champions. \(scoreLine)\(mvpLine)",
                category: .award,
                week: 22,
                season: season,
                relatedTeamID: championID,
                sentiment: wonChampionship ? .positive : .neutral
            ))
        }
    }

    // MARK: - Private: Player Retirements (R32)

    /// Once per offseason (`.coachingChanges`): rolls retirement for every
    /// non-retired player in the league, applies the departures, and produces
    /// the news/inbox/Hall of Fame output:
    /// - stars (career peak OVR ≥ 88) get a ceremony headline,
    /// - the user's own legends say farewell via the inbox (+ legacy credit),
    /// - HOF qualifiers form the annual induction class.
    private static func processPlayerRetirements(
        career: Career,
        teamsByID: [UUID: Team],
        allPlayers: [Player],
        modelContext: ModelContext
    ) {
        // Career-peak OVR per player from season-history snapshots.
        let historyRows = (try? modelContext.fetch(FetchDescriptor<PlayerSeasonHistory>())) ?? []
        var peakByID: [UUID: Int] = [:]
        for row in historyRows {
            peakByID[row.playerID] = max(peakByID[row.playerID] ?? 0, row.overallAtEndOfSeason)
        }

        let retirements = PlayerRetirementEngine.evaluateRetirements(
            allPlayers: allPlayers,
            peakOverallByPlayerID: peakByID
        )
        guard !retirements.isEmpty else { return }

        let season = career.currentSeason
        var inductees: [HallOfFameEntry] = []
        var starHeadlines = 0

        for retirement in retirements {
            let player = retirement.player
            let teamName = retirement.teamIDAtRetirement
                .flatMap { teamsByID[$0]?.fullName } ?? "Free Agent"
            let wasUserPlayer = career.teamID != nil
                && retirement.teamIDAtRetirement == career.teamID

            PlayerRetirementEngine.retire(retirement, teamsByID: teamsByID)

            // Ceremony headline for league-wide stars (cap 4 per offseason).
            if retirement.isStar && starHeadlines < 4 {
                starHeadlines += 1
                lastNewsItems.append(NewsItem(
                    headline: "\(player.fullName) retires after \(max(1, player.yearsPro)) seasons",
                    body: "One of the league's greats is calling it a career. \(player.fullName), the \(teamName == "Free Agent" ? "veteran" : teamName) \(player.position.rawValue) whose play peaked at a \(retirement.peakOverall) overall, announced his retirement today at age \(player.age). Teams around the league honored him with tributes\(retirement.isHallOfFamer ? " — a Hall of Fame induction awaits" : "").",
                    category: .retirement,
                    week: 0,
                    season: season,
                    relatedTeamID: retirement.teamIDAtRetirement,
                    relatedPlayerID: player.id,
                    sentiment: .neutral
                ))
            }

            // The user's own legend gets a personal farewell.
            if wasUserPlayer && (retirement.isStar || player.yearsPro >= 10) {
                lastInboxMessages.append(InboxMessage(
                    sender: .leagueOffice,
                    subject: "\(player.fullName) Announces Retirement",
                    body: "\(player.fullName) (\(player.position.rawValue), age \(player.age)) is hanging up his cleats after \(max(1, player.yearsPro)) pro seasons. He asked that the organization — and you personally — be thanked for the way his final chapter was handled. The locker room will feel his absence.\(retirement.isHallOfFamer ? "\n\nExpect the call from Canton: he retires as a Hall of Famer." : "")",
                    date: "Offseason - Coaching Changes, Season \(season)",
                    category: .leagueNotice
                ))
                career.legacy.recordAchievement(LegacyTracker.LegacyAchievement(
                    title: "A Legend Retires",
                    description: "\(player.fullName) played his final season on your roster.",
                    points: 5,
                    season: season
                ))
            }

            if retirement.isHallOfFamer {
                inductees.append(HallOfFameEntry(
                    playerName: player.fullName,
                    positionRaw: player.position.rawValue,
                    peakOverall: retirement.peakOverall,
                    finalAge: player.age,
                    seasonsPlayed: max(1, player.yearsPro),
                    inductionSeason: season,
                    retiredFromTeamName: teamName,
                    wasUserTeamPlayer: wasUserPlayer
                ))
            }
        }

        // Annual Hall of Fame induction class.
        if !inductees.isEmpty {
            career.hallOfFame = inductees + career.hallOfFame
            let names = inductees
                .map { "\($0.playerName) (\($0.positionRaw))" }
                .joined(separator: ", ")
            lastNewsItems.append(NewsItem(
                headline: "Hall of Fame Class of \(season) announced",
                body: "The league has announced this year's Hall of Fame induction class: \(names). The enshrinement ceremony will be held before the season opener.",
                category: .award,
                week: 0,
                season: season,
                sentiment: .positive
            ))
        }

        // Roundup so the wave of departures is visible in the feed.
        lastNewsItems.append(NewsItem(
            headline: "\(retirements.count) player\(retirements.count == 1 ? "" : "s") announce\(retirements.count == 1 ? "s" : "") retirement",
            body: "The annual wave of retirements has reshaped rosters across the league. Teams will look to free agency and the draft to fill the holes left behind.",
            category: .retirement,
            week: 0,
            season: season,
            sentiment: .neutral
        ))
    }

    // MARK: - Private: League Health (R32)

    /// Deletes stale rows a finished season leaves behind:
    /// - ALL `CollegeProspect` rows (the draft is over; next season's class
    ///   regenerates fresh — and the restart-restore path in ScoutingHubView
    ///   reads every persisted prospect, so stale rows would pollute it),
    /// - `Game` rows older than the just-finished season (~272/season).
    private static func purgeStaleSeasonData(career: Career, modelContext: ModelContext) {
        let prospects = (try? modelContext.fetch(FetchDescriptor<CollegeProspect>())) ?? []
        for prospect in prospects {
            modelContext.delete(prospect)
        }

        let cutoff = career.currentSeason - 1   // keep last season + the new one
        let oldGamesDescriptor = FetchDescriptor<Game>(
            predicate: #Predicate<Game> { $0.seasonYear < cutoff }
        )
        let oldGames = (try? modelContext.fetch(oldGamesDescriptor)) ?? []
        for game in oldGames {
            modelContext.delete(game)
        }
    }

    /// Roster floor for AI teams at season start: retirements + expiring
    /// contracts can shrink an AI roster below playable size over several
    /// seasons. Teams below 46 players sign veteran-minimum free agents at
    /// their top need positions; when the pool runs dry they sign generated
    /// street free agents so every team always fields a full lineup.
    private static func refillAIRosters(
        career: Career,
        teams: [Team],
        modelContext: ModelContext
    ) {
        let minimumRosterSize = 46
        let allPlayers = fetchAllPlayers(modelContext: modelContext)
        var freeAgentPool = allPlayers
            .filter { $0.teamID == nil && !$0.isRetired && !$0.isInjured }
            .sorted { $0.overall > $1.overall }

        for team in teams where team.id != career.teamID {
            var roster = allPlayers.filter { $0.teamID == team.id }
            guard roster.count < minimumRosterSize else { continue }

            while roster.count < minimumRosterSize {
                let needs = DraftEngine.topTeamNeeds(roster: roster, limit: 3)

                let signing: Player
                if let index = freeAgentPool.firstIndex(where: { needs.contains($0.position) }) {
                    signing = freeAgentPool.remove(at: index)
                } else if !freeAgentPool.isEmpty {
                    signing = freeAgentPool.removeFirst()
                } else {
                    // Pool dry — a street free agent reports for a tryout.
                    let position = needs.first ?? .WR
                    let generated = LeagueGenerator.generatePlayer(
                        position: position,
                        teamID: team.id,
                        depthIndex: 2
                    )
                    modelContext.insert(generated)
                    signing = generated
                }

                signing.teamID = team.id
                signing.contractYearsRemaining = Int.random(in: 1...2)
                signing.annualSalary = max(750, min(signing.annualSalary, 1_500))
                team.currentCapUsage += signing.annualSalary
                roster.append(signing)
            }
        }
    }

    /// R32: the AI side of final cutdown day. Every AI roster above the
    /// 53-man ceiling releases its lowest-rated players into the free-agent
    /// pool (mirroring the contract-expiry bookkeeping: cap freed, salary
    /// zeroed, no comp-pick credit — cuts never earn comp picks).
    private static func trimAIRosters(
        career: Career,
        teams: [Team],
        allPlayers: [Player]
    ) {
        let rosterCeiling = 53
        for team in teams where team.id != career.teamID {
            let roster = allPlayers
                .filter { $0.teamID == team.id && !$0.isRetired }
                .sorted { $0.overall > $1.overall }
            guard roster.count > rosterCeiling else { continue }

            for player in roster.suffix(roster.count - rosterCeiling) {
                team.currentCapUsage -= player.annualSalary
                player.teamID = nil
                player.annualSalary = 0
                player.contractYearsRemaining = 0
                player.isHoldingOut = false
                player.trainingFocusArea = nil
                player.trainingPosition = nil
            }
        }
    }

    /// AI teams refill EVERY vacant coaching role each offseason so league
    /// staffing doesn't erode across seasons (poaching/retirements/carousel
    /// moves used to leave permanent holes — only the user could hire, so by
    /// season 5+ AI player development quietly collapsed).
    private static func refillAIStaffVacancies(
        career: Career,
        teams: [Team],
        modelContext: ModelContext
    ) {
        // Re-fetch: the carousel above this call moved coaches around and
        // inserted brand-new ones.
        let coaches = fetchAllCoaches(modelContext: modelContext)

        for team in teams where team.id != career.teamID {
            let filledRoles = Set(coaches.filter { $0.teamID == team.id }.map(\.role))
            for role in CoachRole.allCases where !filledRoles.contains(role) {
                guard let hire = CoachingEngine.generateCoachCandidates(role: role, count: 1).first else {
                    continue
                }
                hire.teamID = team.id
                hire.hireSeasonYear = career.currentSeason
                hire.contractYearsRemaining = Int.random(in: 2...4)
                modelContext.insert(hire)
            }
        }
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

        for player in players where !existingPlayerIDs.contains(player.id) && !player.isRetired {
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
