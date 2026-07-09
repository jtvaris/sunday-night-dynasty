import Foundation

// MARK: - Game Simulator

/// Simulates a full NFL game between two teams and produces a detailed box score,
/// per-player statistics, and an MVP selection.
enum GameSimulator {

    // MARK: - Result Type

    struct GameResult {
        let homeScore: Int
        let awayScore: Int
        let boxScore: BoxScore
        let playerStats: [PlayerGameStats]
        /// Best performer of the game based on impact scoring.
        let mvp: PlayerGameStats?
    }

    // MARK: - Constants

    // Internal (not private) constants are shared with `LiveGameEngine`.
    static let quarterDuration = 900   // 15 minutes in seconds
    private static let totalRegulationQuarters = 4
    static let overtimeQuarter = 5
    static let overtimeDuration = 600  // 10 minutes
    static let touchbackYardLine = 25
    private static let averagePuntDistance = 40
    private static let twoMinuteWarning = 120

    // Kickoff constants (2024 dynamic-kickoff rule: touchbacks come out to the 30).
    static let kickoffTouchbackYardLine = 30
    private static let kickoffTouchbackChance = 0.55
    private static let kickoffReturnTouchdownChance = 0.02
    private static let kickoffReturnStartRange = 20...35

    // Onside kick constants (live-game player choice only; quick sim never onsides).
    static let onsideKickRecoveryChance = 0.12
    /// Where the kicking team takes over after a recovered onside kick.
    static let onsideKickRecoveryYardLine = 48
    /// Where the receiving team starts after a failed onside attempt (short field).
    static let onsideKickFailStartYardLine = 55

    // Momentum constants
    static let homeFieldMomentum: Double = 0.1
    private static let momentumDecayRate: Double = 0.10
    private static let momentumTD: Double = 0.15
    private static let momentumTurnover: Double = 0.20
    private static let momentumBigPlay: Double = 0.10
    private static let momentumSack: Double = 0.05

    // Fatigue constants
    static let fatiguePerDriveStarter: Int = 3
    static let fatigueRecoveryBench: Int = 2
    private static let halftimeFatigueReduction: Double = 0.30

    // Morale constants
    private static let moodDependentPenalty: Double = 0.05
    private static let clutchQ4Multiplier: Double = 1.5
    private static let lowMoraleThreshold: Int = 40

    // MARK: - Simulate

    /// Runs a full game simulation between the home and away teams.
    ///
    /// The simulator manages drive-level possession alternation, quarter and clock
    /// management, momentum shifts, fatigue accumulation, morale/personality modifiers,
    /// and optional overtime. After the game concludes it compiles a ``BoxScore``,
    /// per-player ``PlayerGameStats``, and selects an MVP.
    ///
    /// - Parameters:
    ///   - audibleBoost: 0..0.20 multiplicative bonus to the boosted team's offense
    ///     (applied as final-score amplification). Wired from `OpponentPrepEngine.gameBoost`.
    ///   - defReadBoost: 0..0.15 multiplicative bonus to the boosted team's defense
    ///     (applied as opponent-score dampener).
    ///   - boostedTeamID: The UUID of the team receiving the boost (typically the user's team).
    ///     Pass `nil` to disable boosts entirely.
    ///   - homeGamePlan: Optional coaching game plan applied to the HOME team's
    ///     offensive play-calling (run/pass mix, 4th-down aggressiveness).
    ///     `nil` = today's exact AI behavior. Typically only the user's team
    ///     gets a non-nil plan.
    ///   - awayGamePlan: Same, for the AWAY team.
    ///   - weather: Optional game weather (see ``GameWeather/forGame(id:week:)``).
    ///     The SAME condition is applied to both teams on every play, so the
    ///     effect is symmetric. `nil` = today's exact behavior (clear skies).
    static func simulate(
        homeTeam: Team,
        awayTeam: Team,
        homeCoaches: [Coach] = [],
        awayCoaches: [Coach] = [],
        audibleBoost: Double = 0,
        defReadBoost: Double = 0,
        boostedTeamID: UUID? = nil,
        homeGamePlan: GamePlan? = nil,
        awayGamePlan: GamePlan? = nil,
        weather: GameWeather? = nil
    ) -> GameResult {
        // -----------------------------------------------------------------
        // 1. Setup
        // -----------------------------------------------------------------
        // Snapshot both rosters into value types once. The play-by-play loop
        // reads attributes thousands of times, and every read of a SwiftData
        // @Model property is far too slow for that hot path. The live models
        // are kept in a lookup so fatigue can be written back after the sim.
        // R22: a player holding out over his contract does not suit up.
        let homeRoster = homeTeam.players.filter { !$0.isHoldingOut }
        let awayRoster = awayTeam.players.filter { !$0.isHoldingOut }
        var homePlayers = homeRoster.map(SimPlayer.init(from:))
        var awayPlayers = awayRoster.map(SimPlayer.init(from:))
        var livePlayerByID: [UUID: Player] = [:]
        for player in homeRoster { livePlayerByID[player.id] = player }
        for player in awayRoster { livePlayerByID[player.id] = player }

        // Extract team schemes from coaching staff
        let homeOC = homeCoaches.first { $0.role == .offensiveCoordinator }
        let homeDC = homeCoaches.first { $0.role == .defensiveCoordinator }
        let homeOffScheme = homeOC?.offensiveScheme
        let homeDefScheme = homeDC?.defensiveScheme

        let awayOC = awayCoaches.first { $0.role == .offensiveCoordinator }
        let awayDC = awayCoaches.first { $0.role == .defensiveCoordinator }
        let awayOffScheme = awayOC?.offensiveScheme
        let awayDefScheme = awayDC?.defensiveScheme

        var momentum: Double = homeFieldMomentum // slight home advantage
        var quarter = 1
        var timeRemaining = quarterDuration

        var homeScore = 0
        var awayScore = 0
        var homeQuarterScores = [0, 0, 0, 0] // Q1-Q4 (index 0-3)
        var awayQuarterScores = [0, 0, 0, 0]

        var allDrives: [DriveResult] = []
        var allHighlights: [PlayResult] = []
        var statsAccumulator: [UUID: PlayerGameStats] = [:]

        // Seed stat entries for every rostered player
        initializeStats(for: homePlayers, into: &statsAccumulator)
        initializeStats(for: awayPlayers, into: &statsAccumulator)

        var driveNumber = 0

        // Away team kicks off to start the game; home receives second-half kickoff.
        var homeHasPossession = true // home receives opening kickoff
        var startingYardLine = kickoffStartYardLine() // opening kickoff draw

        // Track total time of possession in seconds
        var homeTimeOfPossession = 0
        var awayTimeOfPossession = 0

        // -----------------------------------------------------------------
        // 2. Game Loop — Regulation
        // -----------------------------------------------------------------
        while quarter <= totalRegulationQuarters {
            driveNumber += 1

            // Apply morale / personality modifiers before the drive.
            // Mutating the snapshots (rather than the live @Model players, as the
            // old code did) also fixes a latent bug where these "transient"
            // modifiers permanently degraded the live models across games.
            applyMoraleModifiers(players: &homePlayers, quarter: quarter)
            applyMoraleModifiers(players: &awayPlayers, quarter: quarter)

            let offensePlayers = homeHasPossession ? homePlayers : awayPlayers
            let defensePlayers = homeHasPossession ? awayPlayers : homePlayers

            // Simulate the drive via DriveSimulator (created in parallel)
            let offenseTeamID = homeHasPossession ? homeTeam.id : awayTeam.id
            let driveResult = DriveSimulator.simulateDrive(
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                startingYardLine: startingYardLine,
                driveNumber: driveNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                momentum: homeHasPossession ? momentum : -momentum,
                teamID: offenseTeamID,
                offensiveScheme: homeHasPossession ? homeOffScheme : awayOffScheme,
                defensiveScheme: homeHasPossession ? awayDefScheme : homeDefScheme,
                gamePlan: homeHasPossession ? homeGamePlan : awayGamePlan,
                weather: weather
            )

            let drive = driveResult.drive
            quarter = driveResult.endQuarter
            timeRemaining = driveResult.endTime

            allDrives.append(drive)

            // Accumulate player stats from the drive's plays
            accumulateStats(
                from: drive,
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                into: &statsAccumulator
            )

            // Track time of possession
            let driveTime = drive.timeConsumed
            if homeHasPossession {
                homeTimeOfPossession += driveTime
            } else {
                awayTimeOfPossession += driveTime
            }

            // Collect highlights
            let driveHighlights = drive.plays.filter { play in
                play.scoringPlay || play.isTurnover || play.yardsGained >= 20
            }
            allHighlights.append(contentsOf: driveHighlights)

            // -----------------------------------------------------------------
            // Score tracking
            // -----------------------------------------------------------------
            let drivePoints = drive.plays.reduce(0) { $0 + $1.pointsScored }
            if drivePoints > 0 {
                let qi = min(quarter - 1, 3) // clamp to Q4 index for regulation
                if homeHasPossession {
                    homeScore += drivePoints
                    homeQuarterScores[qi] += drivePoints
                } else {
                    awayScore += drivePoints
                    awayQuarterScores[qi] += drivePoints
                }
            }

            // Safety scores points for the *defense*
            if drive.result == .safety {
                let qi = min(quarter - 1, 3)
                if homeHasPossession {
                    // Defense (away) gets 2 points
                    awayScore += 2
                    awayQuarterScores[qi] += 2
                } else {
                    homeScore += 2
                    homeQuarterScores[qi] += 2
                }
            }

            // -----------------------------------------------------------------
            // Momentum update
            // -----------------------------------------------------------------
            momentum = updateMomentum(
                currentMomentum: momentum,
                drive: drive,
                homeHasPossession: homeHasPossession
            )

            // -----------------------------------------------------------------
            // Fatigue
            // -----------------------------------------------------------------
            if homeHasPossession {
                applyFatigue(
                    starters: &homePlayers,
                    bench: &awayPlayers,
                    fatigueIncrease: fatiguePerDriveStarter,
                    fatigueRecovery: fatigueRecoveryBench
                )
            } else {
                applyFatigue(
                    starters: &awayPlayers,
                    bench: &homePlayers,
                    fatigueIncrease: fatiguePerDriveStarter,
                    fatigueRecovery: fatigueRecoveryBench
                )
            }

            // -----------------------------------------------------------------
            // Halftime recovery between Q2 and Q3
            // -----------------------------------------------------------------
            if quarter == 3 && allDrives.last?.plays.last.map({ $0.quarter <= 2 }) == true {
                applyHalftimeRecovery(players: &homePlayers)
                applyHalftimeRecovery(players: &awayPlayers)
                // Home team receives second-half kickoff
                homeHasPossession = true
                startingYardLine = kickoffStartYardLine()
                continue
            }

            // -----------------------------------------------------------------
            // Next possession setup
            // -----------------------------------------------------------------
            let nextPossessionInfo = determineNextPossession(
                afterDrive: drive,
                homeHasPossession: homeHasPossession
            )
            homeHasPossession = nextPossessionInfo.homeHasPossession
            startingYardLine = nextPossessionInfo.startingYardLine

            // -----------------------------------------------------------------
            // Kickoff return touchdown (~2% of post-score kicks): the receiving
            // team houses it. Only while the half is still alive — a kick can't
            // happen after the clock has expired.
            // -----------------------------------------------------------------
            if let kick = nextPossessionInfo.kickoff, kick.isReturnTouchdown, timeRemaining > 0 {
                driveNumber += 1
                let returnTeamIsHome = homeHasPossession
                let returnPlay = kickoffReturnTouchdownPlay(
                    quarter: quarter,
                    timeRemaining: timeRemaining
                )
                let returnDrive = DriveResult(
                    driveNumber: driveNumber,
                    teamID: returnTeamIsHome ? homeTeam.id : awayTeam.id,
                    startingYardLine: kick.startingYardLine,
                    plays: [returnPlay],
                    result: .touchdown
                )
                allDrives.append(returnDrive)
                allHighlights.append(returnPlay)

                let qi = min(quarter - 1, 3)
                if returnTeamIsHome {
                    homeScore += returnPlay.pointsScored
                    homeQuarterScores[qi] += returnPlay.pointsScored
                } else {
                    awayScore += returnPlay.pointsScored
                    awayQuarterScores[qi] += returnPlay.pointsScored
                }

                momentum = updateMomentum(
                    currentMomentum: momentum,
                    drive: returnDrive,
                    homeHasPossession: returnTeamIsHome
                )

                // Ensuing kickoff goes back to the team that originally scored.
                homeHasPossession = !returnTeamIsHome
                startingYardLine = kickoffStartYardLine()
            }

            // -----------------------------------------------------------------
            // Quarter management & two-minute warning
            // -----------------------------------------------------------------
            if timeRemaining <= 0 {
                // Q4 expiry must break here: quarter never exceeds
                // totalRegulationQuarters, so a `quarter > total` check can
                // never fire and the loop would spin on zero-length drives.
                if quarter >= totalRegulationQuarters {
                    break
                }
                quarter += 1
                timeRemaining = quarterDuration
            }
        }

        // -----------------------------------------------------------------
        // 6. Overtime (if tied)
        // -----------------------------------------------------------------
        var overtimePlayed = false
        if homeScore == awayScore {
            overtimePlayed = true
            homeQuarterScores.append(0)
            awayQuarterScores.append(0)

            let otResult = simulateOvertime(
                homeTeam: homeTeam,
                awayTeam: awayTeam,
                homePlayers: homePlayers,
                awayPlayers: awayPlayers,
                driveNumber: &driveNumber,
                momentum: &momentum,
                statsAccumulator: &statsAccumulator,
                allDrives: &allDrives,
                allHighlights: &allHighlights,
                homeTimeOfPossession: &homeTimeOfPossession,
                awayTimeOfPossession: &awayTimeOfPossession,
                homeOffScheme: homeOffScheme,
                homeDefScheme: homeDefScheme,
                awayOffScheme: awayOffScheme,
                awayDefScheme: awayDefScheme,
                homeGamePlan: homeGamePlan,
                awayGamePlan: awayGamePlan,
                weather: weather
            )
            homeScore += otResult.homeOTPoints
            awayScore += otResult.awayOTPoints
            homeQuarterScores[4] = otResult.homeOTPoints
            awayQuarterScores[4] = otResult.awayOTPoints
        }

        // -----------------------------------------------------------------
        // 6b. Apply OpponentPrepEngine game boost (Camp Phase 1 wire-up)
        // -----------------------------------------------------------------
        // The boost is applied as a final-score nudge rather than threading
        // multipliers through every PlaySimulator call. audibleBoost (0..0.20)
        // amplifies the boosted team's own scoring; defReadBoost (0..0.15)
        // dampens the opponent's. Half-strength (×0.5) is intentional —
        // a 100% opponent-prep week shifts the final by ~+10% offense /
        // -7.5% defense, matching the design intent without runaway scoring.
        if let boostedID = boostedTeamID, (audibleBoost > 0 || defReadBoost > 0) {
            let audibleMult = 1.0 + (max(0.0, min(0.20, audibleBoost)) * 0.5)
            let defReadMult = 1.0 - (max(0.0, min(0.15, defReadBoost)) * 0.5)
            if boostedID == homeTeam.id {
                homeScore = Int((Double(homeScore) * audibleMult).rounded())
                awayScore = max(0, Int((Double(awayScore) * defReadMult).rounded()))
            } else if boostedID == awayTeam.id {
                awayScore = Int((Double(awayScore) * audibleMult).rounded())
                homeScore = max(0, Int((Double(homeScore) * defReadMult).rounded()))
            }
        }

        // -----------------------------------------------------------------
        // 7. Build Box Score & Stats
        // -----------------------------------------------------------------
        return finalizeGameResult(
            homeTeamID: homeTeam.id,
            awayTeamID: awayTeam.id,
            homeScore: homeScore,
            awayScore: awayScore,
            homeQuarterScores: homeQuarterScores,
            awayQuarterScores: awayQuarterScores,
            drives: allDrives,
            highlights: allHighlights,
            homeTimeOfPossession: homeTimeOfPossession,
            awayTimeOfPossession: awayTimeOfPossession,
            statsAccumulator: statsAccumulator,
            homePlayers: homePlayers,
            awayPlayers: awayPlayers,
            livePlayerByID: livePlayerByID
        )
    }

    #if DEBUG
    // MARK: - Debug Balance Harness

    /// One-off balance measurement: runs `n` AI-vs-AI games between two
    /// generic generated rosters and prints scoring/yardage distributions to
    /// the console, plus a schedule-integrity check over several seasons.
    /// Call temporarily from app launch, read the output via
    /// `simctl launch --console-pty`, then REMOVE the call — never ship it.
    static func debugSimulate(n: Int) {
        let generated = LeagueGenerator.generate(startYear: 2025)
        let teams = generated.teams
        guard teams.count >= 2 else {
            print("DEBUG-SIM: league generation failed")
            return
        }
        // Two mid-table teams, no coaches (neutral schemes), no boosts.
        let home = teams[10]
        let away = teams[21]

        var points: [Double] = []
        var yards: [Double] = []
        var penaltiesPerGame: [Double] = []
        var margins: [Double] = []
        for _ in 0..<n {
            let result = simulate(homeTeam: home, awayTeam: away)
            points.append(Double(result.homeScore))
            points.append(Double(result.awayScore))
            yards.append(Double(result.boxScore.home.totalYards))
            yards.append(Double(result.boxScore.away.totalYards))
            penaltiesPerGame.append(Double(result.boxScore.home.penalties + result.boxScore.away.penalties))
            margins.append(Double(abs(result.homeScore - result.awayScore)))
        }

        func stats(_ values: [Double]) -> (mean: Double, std: Double, min: Double, max: Double) {
            guard !values.isEmpty else { return (0, 0, 0, 0) }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            return (mean, variance.squareRoot(), values.min() ?? 0, values.max() ?? 0)
        }

        let p = stats(points)
        let y = stats(yards)
        let pen = stats(penaltiesPerGame)
        let m = stats(margins)
        print(String(format: "DEBUG-SIM: games=%d", n))
        print(String(format: "DEBUG-SIM: points/team mean=%.1f std=%.1f min=%.0f max=%.0f", p.mean, p.std, p.min, p.max))
        print(String(format: "DEBUG-SIM: yards/team  mean=%.0f std=%.0f min=%.0f max=%.0f", y.mean, y.std, y.min, y.max))
        print(String(format: "DEBUG-SIM: penalties/game mean=%.1f", pen.mean))
        print(String(format: "DEBUG-SIM: score margin mean=%.1f", m.mean))

        // Schedule integrity: several season years through the generator.
        var scheduleOK = true
        for year in 2025...2032 {
            let games = ScheduleGenerator.generateSeason(teams: teams, seasonYear: year)
            let issues = ScheduleGenerator.validate(games: games, teams: teams)
            if games.count != 272 || !issues.isEmpty {
                scheduleOK = false
                print("DEBUG-SIM: schedule \(year) games=\(games.count) issues=\(issues.prefix(6))")
            }
        }
        print("DEBUG-SIM: schedule integrity 2025-2032 \(scheduleOK ? "OK — every team exactly 1 bye" : "FAILED")")
    }
    #endif

    // MARK: - Result Finalization

    /// Assembles the final ``GameResult`` (box scores, per-player stats, MVP)
    /// from accumulated simulation state and writes fatigue back to the live
    /// `Player` models — the only sim-side player mutation that is meant to
    /// persist beyond the game. Shared with `LiveGameEngine.buildResult()`.
    static func finalizeGameResult(
        homeTeamID: UUID,
        awayTeamID: UUID,
        homeScore: Int,
        awayScore: Int,
        homeQuarterScores: [Int],
        awayQuarterScores: [Int],
        drives: [DriveResult],
        highlights: [PlayResult],
        homeTimeOfPossession: Int,
        awayTimeOfPossession: Int,
        statsAccumulator: [UUID: PlayerGameStats],
        homePlayers: [SimPlayer],
        awayPlayers: [SimPlayer],
        livePlayerByID: [UUID: Player]
    ) -> GameResult {
        let homeBoxScore = buildTeamBoxScore(
            teamID: homeTeamID,
            score: homeScore,
            quarterScores: homeQuarterScores,
            drives: drives.filter { $0.teamID == homeTeamID },
            timeOfPossession: homeTimeOfPossession
        )

        let awayBoxScore = buildTeamBoxScore(
            teamID: awayTeamID,
            score: awayScore,
            quarterScores: awayQuarterScores,
            drives: drives.filter { $0.teamID == awayTeamID },
            timeOfPossession: awayTimeOfPossession
        )

        let boxScore = BoxScore(
            home: homeBoxScore,
            away: awayBoxScore,
            drives: drives,
            highlights: highlights
        )

        let finalPlayerStats = Array(statsAccumulator.values)
        let mvp = determineMVP(from: finalPlayerStats)

        // Write accumulated fatigue back to the live models — the only sim-side
        // player mutation that is meant to persist beyond this game.
        for simPlayer in homePlayers {
            livePlayerByID[simPlayer.id]?.fatigue = simPlayer.fatigue
        }
        for simPlayer in awayPlayers {
            livePlayerByID[simPlayer.id]?.fatigue = simPlayer.fatigue
        }

        return GameResult(
            homeScore: homeScore,
            awayScore: awayScore,
            boxScore: boxScore,
            playerStats: finalPlayerStats,
            mvp: mvp
        )
    }

    // MARK: - Overtime

    private struct OvertimeResult {
        let homeOTPoints: Int
        let awayOTPoints: Int
    }

    /// Simulates a single overtime period. Each team receives one guaranteed
    /// possession (unless the first team scores a TD). If still tied after
    /// both possessions, subsequent scores win immediately. The period is
    /// capped at ``overtimeDuration`` seconds and may end in a tie.
    private static func simulateOvertime(
        homeTeam: Team,
        awayTeam: Team,
        homePlayers: [SimPlayer],
        awayPlayers: [SimPlayer],
        driveNumber: inout Int,
        momentum: inout Double,
        statsAccumulator: inout [UUID: PlayerGameStats],
        allDrives: inout [DriveResult],
        allHighlights: inout [PlayResult],
        homeTimeOfPossession: inout Int,
        awayTimeOfPossession: inout Int,
        homeOffScheme: OffensiveScheme? = nil,
        homeDefScheme: DefensiveScheme? = nil,
        awayOffScheme: OffensiveScheme? = nil,
        awayDefScheme: DefensiveScheme? = nil,
        homeGamePlan: GamePlan? = nil,
        awayGamePlan: GamePlan? = nil,
        weather: GameWeather? = nil
    ) -> OvertimeResult {
        var homeOTPoints = 0
        var awayOTPoints = 0
        var otTimeRemaining = overtimeDuration
        var homeHasPossession = Bool.random() // coin toss
        var firstPossessionComplete = false
        var secondPossessionComplete = false
        var startingYardLine = kickoffStartYardLine() // OT kickoff draw

        while otTimeRemaining > 0 {
            driveNumber += 1

            let offensePlayers = homeHasPossession ? homePlayers : awayPlayers
            let defensePlayers = homeHasPossession ? awayPlayers : homePlayers

            let otOffenseTeamID = homeHasPossession ? homeTeam.id : awayTeam.id
            let driveResult = DriveSimulator.simulateDrive(
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                startingYardLine: startingYardLine,
                driveNumber: driveNumber,
                quarter: overtimeQuarter,
                timeRemaining: otTimeRemaining,
                momentum: homeHasPossession ? momentum : -momentum,
                teamID: otOffenseTeamID,
                offensiveScheme: homeHasPossession ? homeOffScheme : awayOffScheme,
                defensiveScheme: homeHasPossession ? awayDefScheme : homeDefScheme,
                gamePlan: homeHasPossession ? homeGamePlan : awayGamePlan,
                weather: weather
            )

            let drive = driveResult.drive
            otTimeRemaining = driveResult.endTime

            allDrives.append(drive)
            accumulateStats(
                from: drive,
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                into: &statsAccumulator
            )

            let driveTime = drive.timeConsumed
            if homeHasPossession {
                homeTimeOfPossession += driveTime
            } else {
                awayTimeOfPossession += driveTime
            }

            let driveHighlights = drive.plays.filter { $0.scoringPlay || $0.isTurnover || $0.yardsGained >= 20 }
            allHighlights.append(contentsOf: driveHighlights)

            let drivePoints = drive.plays.reduce(0) { $0 + $1.pointsScored }
            if homeHasPossession {
                homeOTPoints += drivePoints
            } else {
                awayOTPoints += drivePoints
            }

            // Safety: defense scores
            if drive.result == .safety {
                if homeHasPossession {
                    awayOTPoints += 2
                } else {
                    homeOTPoints += 2
                }
            }

            momentum = updateMomentum(
                currentMomentum: momentum,
                drive: drive,
                homeHasPossession: homeHasPossession
            )

            // OT rules: first team scores a TD -> game over
            if !firstPossessionComplete && drive.result == .touchdown {
                break
            }

            if !firstPossessionComplete {
                firstPossessionComplete = true
                // Switch possession for the second team's guaranteed possession.
                // Scoring drives hand the ball over via a kickoff draw; punts
                // and turnovers use the actual field position (housed returns
                // are not modeled in OT).
                let nextInfo = determineNextPossession(
                    afterDrive: drive,
                    homeHasPossession: homeHasPossession,
                    allowKickoffReturnTouchdown: false
                )
                homeHasPossession = nextInfo.homeHasPossession
                startingYardLine = nextInfo.startingYardLine
                continue
            }

            if !secondPossessionComplete {
                secondPossessionComplete = true
                // If scores differ after both possessions, game over
                if homeOTPoints != awayOTPoints {
                    break
                }
                // Still tied: next score wins
                let nextInfo = determineNextPossession(
                    afterDrive: drive,
                    homeHasPossession: homeHasPossession,
                    allowKickoffReturnTouchdown: false
                )
                homeHasPossession = nextInfo.homeHasPossession
                startingYardLine = nextInfo.startingYardLine
                continue
            }

            // Sudden death: any score wins
            if homeOTPoints != awayOTPoints {
                break
            }

            let nextInfo = determineNextPossession(
                afterDrive: drive,
                homeHasPossession: homeHasPossession,
                allowKickoffReturnTouchdown: false
            )
            homeHasPossession = nextInfo.homeHasPossession
            startingYardLine = nextInfo.startingYardLine
        }

        return OvertimeResult(homeOTPoints: homeOTPoints, awayOTPoints: awayOTPoints)
    }

    // MARK: - Kickoffs

    /// Outcome of one kickoff, drawn from the shared distribution so quick sim
    /// and the live engine stay statistically identical.
    struct KickoffResult {
        /// Receiving team's drive start (yards from its own goal line).
        let startingYardLine: Int
        /// True when the kick sailed for a touchback (2024 rule: out to the 30).
        let isTouchback: Bool
        /// True when the return went all the way — the receiving team scores.
        let isReturnTouchdown: Bool
    }

    /// Rolls one kickoff: ~2% housed return (when allowed), ~55% touchback to
    /// the 30, otherwise a return out to the 20–35.
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func rollKickoff(allowReturnTouchdown: Bool = true) -> KickoffResult {
        if allowReturnTouchdown && Double.random(in: 0..<1) < kickoffReturnTouchdownChance {
            return KickoffResult(
                startingYardLine: kickoffTouchbackYardLine,
                isTouchback: false,
                isReturnTouchdown: true
            )
        }
        if Double.random(in: 0..<1) < kickoffTouchbackChance {
            return KickoffResult(
                startingYardLine: kickoffTouchbackYardLine,
                isTouchback: true,
                isReturnTouchdown: false
            )
        }
        return KickoffResult(
            startingYardLine: Int.random(in: kickoffReturnStartRange),
            isTouchback: false,
            isReturnTouchdown: false
        )
    }

    /// Convenience draw for kickoffs where a housed return isn't modeled
    /// (opening kick, second-half kick, overtime kick): position only.
    static func kickoffStartYardLine() -> Int {
        rollKickoff(allowReturnTouchdown: false).startingYardLine
    }

    /// Synthetic play describing a kickoff returned for a touchdown. Return
    /// yards are intentionally NOT counted as offensive yards (yardsGained 0)
    /// so team total-yardage stays a scrimmage stat; TDs are worth 6 in this
    /// sim (extra points are not modeled anywhere).
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func kickoffReturnTouchdownPlay(quarter: Int, timeRemaining: Int) -> PlayResult {
        PlayResult(
            playNumber: 1,
            quarter: quarter,
            timeRemaining: max(timeRemaining, 0),
            down: 0,
            distance: 0,
            yardLine: 0,
            playType: .kickoff,
            outcome: .touchdown,
            yardsGained: 0,
            description: "The kickoff is returned ALL THE WAY for a touchdown!",
            isFirstDown: false,
            isTurnover: false,
            scoringPlay: true,
            pointsScored: 6
        )
    }

    // MARK: - Possession Management

    /// Next-possession descriptor. Internal because it is shared with `LiveGameEngine`.
    struct NextPossession {
        let homeHasPossession: Bool
        let startingYardLine: Int
        /// Kickoff detail when the possession change came via a kickoff
        /// (touchdown/field-goal drives); nil for punts, turnovers, etc.
        var kickoff: KickoffResult? = nil
    }

    /// Determines which team gets the ball next and where on the field they
    /// start based on how the previous drive ended.
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    /// - Parameter allowKickoffReturnTouchdown: pass false in contexts where a
    ///   housed kickoff can't be represented (overtime possession rules).
    static func determineNextPossession(
        afterDrive drive: DriveResult,
        homeHasPossession: Bool,
        allowKickoffReturnTouchdown: Bool = true
    ) -> NextPossession {
        let switchPossession = !homeHasPossession

        switch drive.result {
        case .touchdown, .fieldGoal:
            // Kickoff: the receiving team's start is drawn from the shared
            // kickoff distribution (touchback / return / housed return).
            let kick = rollKickoff(allowReturnTouchdown: allowKickoffReturnTouchdown)
            return NextPossession(
                homeHasPossession: switchPossession,
                startingYardLine: kick.startingYardLine,
                kickoff: kick
            )

        case .punt:
            // Opponent receives the punt ~40 yards downfield from where the punter kicked
            let lastPlay = drive.plays.last
            let puntFrom = lastPlay?.yardLine ?? 30
            // Punt lands ~40 yards downfield; clamp to valid range
            let landingSpot = min(100 - puntFrom + averagePuntDistance, 80)
            let opponentYardLine = max(100 - (puntFrom + averagePuntDistance), 20)
            return NextPossession(
                homeHasPossession: switchPossession,
                startingYardLine: max(opponentYardLine, touchbackYardLine)
            )

        case .turnover, .turnoverOnDowns:
            // Opponent gets ball at the spot of the turnover
            let lastPlay = drive.plays.last
            let turnoverSpot = lastPlay?.yardLine ?? 50
            // Convert: offense was at `turnoverSpot` from their end zone,
            // so opponent starts at (100 - turnoverSpot) from their own end zone
            let opponentYardLine = 100 - turnoverSpot
            return NextPossession(
                homeHasPossession: switchPossession,
                startingYardLine: max(min(opponentYardLine, 99), 1)
            )

        case .safety:
            // Free kick after safety; receiving team usually starts around the 40
            return NextPossession(
                homeHasPossession: switchPossession,
                startingYardLine: 40
            )

        case .endOfHalf, .endOfGame:
            // Possession resets at the start of next period
            return NextPossession(
                homeHasPossession: switchPossession,
                startingYardLine: touchbackYardLine
            )
        }
    }

    // MARK: - Momentum

    /// Applies momentum decay and shifts based on the outcome of the completed drive.
    /// Positive momentum favors the home team; negative favors the away team.
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func updateMomentum(
        currentMomentum: Double,
        drive: DriveResult,
        homeHasPossession: Bool
    ) -> Double {
        var m = currentMomentum

        // Decay toward neutral
        m *= (1.0 - momentumDecayRate)

        let direction: Double = homeHasPossession ? 1.0 : -1.0

        // Shift based on drive outcome
        switch drive.result {
        case .touchdown:
            m += momentumTD * direction
        case .turnover, .turnoverOnDowns:
            // Turnover hurts the offense -> momentum shifts to defense
            m -= momentumTurnover * direction
        case .safety:
            m -= momentumTurnover * direction
        default:
            break
        }

        // Check for big plays and sacks within the drive
        for play in drive.plays {
            if play.yardsGained >= 20 && !play.isTurnover {
                m += momentumBigPlay * direction
            }
            if play.outcome == .sack {
                // Sack benefits the defense
                m -= momentumSack * direction
            }
        }

        // Clamp to [-1, 1]
        return max(-1.0, min(1.0, m))
    }

    // MARK: - Morale / Personality Modifiers

    /// Applies temporary attribute modifications based on player personality
    /// and morale state. Mood-dependent players with low morale suffer a penalty,
    /// while clutch attributes are amplified in the fourth quarter.
    ///
    /// - Note: These modifications mutate the ``SimPlayer`` snapshots only, so
    ///   they are truly transient. (The pre-snapshot code mutated the live
    ///   @Model players here, permanently degrading them across games.)
    ///
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func applyMoraleModifiers(
        players: inout [SimPlayer],
        quarter: Int
    ) {
        for i in players.indices {
            // Mood-dependent players with low morale get a penalty
            if players[i].isMoodDependent && players[i].morale < lowMoraleThreshold {
                let penalty = Int(Double(players[i].physical.speed) * moodDependentPenalty)
                players[i].physical.speed = max(1, players[i].physical.speed - penalty)
                players[i].physical.agility = max(1, players[i].physical.agility - penalty)
                players[i].mental.awareness = max(1, players[i].mental.awareness - penalty)
            }

            // Consistent players are unaffected by morale — no modification needed

            // Clutch matters more in Q4 and OT
            if quarter >= 4 {
                let clutchBonus = Int(
                    Double(players[i].mental.clutch) * (clutchQ4Multiplier - 1.0) / 100.0
                        * Double(players[i].physical.speed)
                )
                players[i].mental.decisionMaking = min(99, players[i].mental.decisionMaking + clutchBonus)
            }
        }
    }

    // MARK: - Fatigue

    /// Increments fatigue for players who just played and slightly recovers
    /// fatigue for bench/opposing-side players.
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func applyFatigue(
        starters: inout [SimPlayer],
        bench: inout [SimPlayer],
        fatigueIncrease: Int,
        fatigueRecovery: Int
    ) {
        for i in starters.indices {
            starters[i].fatigue = min(100, starters[i].fatigue + fatigueIncrease)
        }
        for i in bench.indices {
            bench[i].fatigue = max(0, bench[i].fatigue - fatigueRecovery)
        }
    }

    /// Reduces fatigue by 30% for all players during halftime.
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func applyHalftimeRecovery(players: inout [SimPlayer]) {
        for i in players.indices {
            let reduction = Int(Double(players[i].fatigue) * halftimeFatigueReduction)
            players[i].fatigue = max(0, players[i].fatigue - reduction)
        }
    }

    // MARK: - Stats Initialization

    /// Seeds the accumulator dictionary with zeroed-out stats for every player.
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func initializeStats(
        for players: [SimPlayer],
        into accumulator: inout [UUID: PlayerGameStats]
    ) {
        for player in players {
            accumulator[player.id] = PlayerGameStats(
                playerID: player.id,
                playerName: player.fullName,
                position: player.position
            )
        }
    }

    // MARK: - Stats Accumulation

    /// Iterates over every play in a completed drive and credits the appropriate
    /// offensive and defensive players with the corresponding statistics.
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func accumulateStats(
        from drive: DriveResult,
        offensePlayers: [SimPlayer],
        defensePlayers: [SimPlayer],
        into accumulator: inout [UUID: PlayerGameStats]
    ) {
        let qb = offensePlayers.first { $0.position == .QB }
        let rbs = offensePlayers.filter { $0.position == .RB || $0.position == .FB }
        let receivers = offensePlayers.filter {
            $0.position == .WR || $0.position == .TE || $0.position == .RB
        }
        let dLinemen = defensePlayers.filter { $0.position == .DE || $0.position == .DT }
        let dBacks = defensePlayers.filter {
            $0.position == .CB || $0.position == .FS || $0.position == .SS
        }
        let linebackers = defensePlayers.filter {
            $0.position == .MLB || $0.position == .OLB
        }
        let kicker = offensePlayers.first { $0.position == .K }

        // The sim names the exact target/carrier on most plays
        // (keyOffensePlayerID); crediting HIM keeps the box score aligned
        // with the play-by-play text and the players shown on the 3D field.
        // Plays without attribution fall back to the old weighted pick.
        func credited(_ id: UUID?, roster: [SimPlayer], fallback group: [SimPlayer]) -> SimPlayer? {
            if let id, let named = roster.first(where: { $0.id == id }) { return named }
            return pickWeightedPlayer(from: group)
        }

        for play in drive.plays {
            switch play.outcome {
            case .completion:
                // QB passing stats
                if let qb = qb {
                    accumulator[qb.id]?.passingYards += play.yardsGained
                    accumulator[qb.id]?.attempts += 1
                    accumulator[qb.id]?.completions += 1
                }
                // Credit the targeted receiver
                if let receiver = credited(play.keyOffensePlayerID, roster: offensePlayers, fallback: receivers) {
                    accumulator[receiver.id]?.receivingYards += play.yardsGained
                    accumulator[receiver.id]?.receptions += 1
                    accumulator[receiver.id]?.targets += 1
                }

            case .incompletion:
                if let qb = qb {
                    accumulator[qb.id]?.attempts += 1
                }
                if let receiver = credited(play.keyOffensePlayerID, roster: offensePlayers, fallback: receivers) {
                    accumulator[receiver.id]?.targets += 1
                }

            case .rush:
                // keyOffensePlayerID also covers QB scrambles, so the yards
                // land on the scrambler instead of a random back.
                if let rusher = credited(play.keyOffensePlayerID, roster: offensePlayers, fallback: rbs) {
                    accumulator[rusher.id]?.rushingYards += play.yardsGained
                    accumulator[rusher.id]?.carries += 1
                }
                // Credit a defender with a tackle
                if let tackler = pickWeightedPlayer(from: linebackers + dLinemen) {
                    accumulator[tackler.id]?.tackles += 1
                }

            case .touchdown:
                // Kickoff-return TDs are synthetic special-teams plays — skip
                // the QB/RB attribution meant for scrimmage touchdowns.
                if play.playType == .kickoff { break }
                // Determine if it was a passing or rushing TD based on play type
                if play.playType == .pass {
                    if let qb = qb {
                        accumulator[qb.id]?.passingTDs += 1
                        accumulator[qb.id]?.passingYards += play.yardsGained
                        accumulator[qb.id]?.attempts += 1
                        accumulator[qb.id]?.completions += 1
                    }
                    if let receiver = credited(play.keyOffensePlayerID, roster: offensePlayers, fallback: receivers) {
                        accumulator[receiver.id]?.receivingTDs += 1
                        accumulator[receiver.id]?.receivingYards += play.yardsGained
                        accumulator[receiver.id]?.receptions += 1
                        accumulator[receiver.id]?.targets += 1
                    }
                } else {
                    if let rusher = credited(play.keyOffensePlayerID, roster: offensePlayers, fallback: rbs) {
                        accumulator[rusher.id]?.rushingTDs += 1
                        accumulator[rusher.id]?.rushingYards += play.yardsGained
                        accumulator[rusher.id]?.carries += 1
                    }
                }

            case .sack:
                if let qb = qb {
                    accumulator[qb.id]?.passingYards += play.yardsGained // negative
                    accumulator[qb.id]?.attempts += 1
                }
                if let dLineman = pickWeightedPlayer(from: dLinemen + linebackers) {
                    accumulator[dLineman.id]?.sacks += 0.5
                    accumulator[dLineman.id]?.tackles += 1
                }

            case .interception:
                if let qb = qb {
                    accumulator[qb.id]?.interceptions += 1
                    accumulator[qb.id]?.attempts += 1
                }
                if let db = credited(play.keyDefensePlayerID, roster: defensePlayers, fallback: dBacks + linebackers) {
                    accumulator[db.id]?.interceptionsCaught += 1
                }

            case .fumble, .fumbleLost:
                if let ballCarrier = credited(play.keyOffensePlayerID, roster: offensePlayers, fallback: rbs) {
                    accumulator[ballCarrier.id]?.carries += 1
                    accumulator[ballCarrier.id]?.rushingYards += play.yardsGained
                }
                if play.outcome == .fumbleLost {
                    if let defender = pickWeightedPlayer(from: dLinemen + linebackers) {
                        accumulator[defender.id]?.forcedFumbles += 1
                        accumulator[defender.id]?.tackles += 1
                    }
                }

            case .fieldGoalGood:
                if let kicker = kicker {
                    accumulator[kicker.id]?.fieldGoalsMade += 1
                    accumulator[kicker.id]?.fieldGoalsAttempted += 1
                }

            case .fieldGoalMissed:
                if let kicker = kicker {
                    accumulator[kicker.id]?.fieldGoalsAttempted += 1
                }

            case .punt, .touchback, .kneel, .spike, .penalty,
                 .extraPointGood, .extraPointMissed,
                 .twoPointGood, .twoPointFailed, .safety:
                // Minimal stat tracking for these outcomes
                break
            }
        }
    }

    /// Selects a player from the array with slight randomness so that touches
    /// are distributed realistically rather than always going to the first player.
    private static func pickWeightedPlayer(from players: [SimPlayer]) -> SimPlayer? {
        guard !players.isEmpty else { return nil }
        // Weight by overall rating with randomness
        let weights = players.map { Double($0.overall) + Double.random(in: 0...20) }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return players.first }

        let roll = Double.random(in: 0..<totalWeight)
        var cumulative = 0.0
        for (index, weight) in weights.enumerated() {
            cumulative += weight
            if roll < cumulative {
                return players[index]
            }
        }
        return players.last
    }

    // MARK: - Box Score Building

    /// Compiles a ``TeamBoxScore`` from the raw drive and play data for one team.
    private static func buildTeamBoxScore(
        teamID: UUID,
        score: Int,
        quarterScores: [Int],
        drives: [DriveResult],
        timeOfPossession: Int
    ) -> TeamBoxScore {
        var totalYards = 0
        var passingYards = 0
        var rushingYards = 0
        var firstDowns = 0
        var thirdDownConversions = 0
        var thirdDownAttempts = 0
        var turnovers = 0
        var sacks = 0
        var penalties = 0
        var penaltyYards = 0

        for drive in drives {
            for play in drive.plays {
                // Team yardage is a SCRIMMAGE stat: pass and run plays only.
                // (Punts used to leak their 35-55 net yards into totalYards,
                // inflating team totals by ~200 per game.) Penalty walk-offs
                // only count toward the penalties/penaltyYards tallies below.
                if play.outcome != .penalty {
                    switch play.playType {
                    case .pass:
                        totalYards += play.yardsGained
                        passingYards += play.yardsGained
                    case .run:
                        totalYards += play.yardsGained
                        rushingYards += play.yardsGained
                    default:
                        break
                    }
                }

                if play.isFirstDown {
                    firstDowns += 1
                }

                // Track 3rd down efficiency. Penalty no-plays replay the down,
                // so they charge no attempt (NFL accounting).
                if play.down == 3 && play.outcome != .penalty {
                    thirdDownAttempts += 1
                    if play.isFirstDown || play.scoringPlay {
                        thirdDownConversions += 1
                    }
                }

                if play.isTurnover {
                    turnovers += 1
                }

                if play.outcome == .sack {
                    sacks += 1
                }

                if play.outcome == .penalty {
                    penalties += 1
                    penaltyYards += abs(play.yardsGained)
                }
            }
        }

        return TeamBoxScore(
            teamID: teamID,
            score: score,
            quarterScores: quarterScores,
            totalYards: totalYards,
            passingYards: passingYards,
            rushingYards: rushingYards,
            firstDowns: firstDowns,
            thirdDownConversions: thirdDownConversions,
            thirdDownAttempts: thirdDownAttempts,
            turnovers: turnovers,
            sacks: sacks,
            penalties: penalties,
            penaltyYards: penaltyYards,
            timeOfPossession: timeOfPossession,
            drives: drives.count
        )
    }

    // MARK: - MVP Selection

    /// Determines the Most Valuable Player by computing an impact score for
    /// each player that weighs touchdowns, total yardage, turnovers created,
    /// and key defensive plays.
    private static func determineMVP(from stats: [PlayerGameStats]) -> PlayerGameStats? {
        guard !stats.isEmpty else { return nil }

        return stats.max { a, b in
            impactScore(for: a) < impactScore(for: b)
        }
    }

    /// Calculates a single numeric impact score for MVP comparison.
    ///
    /// Scoring weights:
    /// - Passing TD: 6 points
    /// - Rushing/Receiving TD: 8 points
    /// - Total yards (passing, rushing, receiving): 0.04 per yard
    /// - Interceptions caught: 8 points each
    /// - Sacks: 4 points each
    /// - Forced fumbles: 6 points each
    /// - Turnovers thrown (INTs): -5 points each
    /// - Field goals made: 3 points each
    private static func impactScore(for stats: PlayerGameStats) -> Double {
        var score = 0.0

        // Offensive production
        score += Double(stats.passingTDs) * 6.0
        score += Double(stats.rushingTDs) * 8.0
        score += Double(stats.receivingTDs) * 8.0
        score += Double(stats.passingYards + stats.rushingYards + stats.receivingYards) * 0.04

        // Defensive impact
        score += Double(stats.interceptionsCaught) * 8.0
        score += stats.sacks * 4.0
        score += Double(stats.forcedFumbles) * 6.0

        // Penalties for turnovers
        score -= Double(stats.interceptions) * 5.0

        // Kicking
        score += Double(stats.fieldGoalsMade) * 3.0

        return score
    }
}
