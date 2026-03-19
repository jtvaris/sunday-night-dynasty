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

    private static let quarterDuration = 900   // 15 minutes in seconds
    private static let totalRegulationQuarters = 4
    private static let overtimeQuarter = 5
    private static let overtimeDuration = 600  // 10 minutes
    private static let touchbackYardLine = 25
    private static let averagePuntDistance = 40
    private static let twoMinuteWarning = 120

    // Momentum constants
    private static let homeFieldMomentum: Double = 0.1
    private static let momentumDecayRate: Double = 0.10
    private static let momentumTD: Double = 0.15
    private static let momentumTurnover: Double = 0.20
    private static let momentumBigPlay: Double = 0.10
    private static let momentumSack: Double = 0.05

    // Fatigue constants
    private static let fatiguePerDriveStarter: Int = 3
    private static let fatigueRecoveryBench: Int = 2
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
    static func simulate(
        homeTeam: Team,
        awayTeam: Team,
        homeCoaches: [Coach] = [],
        awayCoaches: [Coach] = []
    ) -> GameResult {
        // -----------------------------------------------------------------
        // 1. Setup
        // -----------------------------------------------------------------
        let homePlayers = homeTeam.players
        let awayPlayers = awayTeam.players

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
        var startingYardLine = touchbackYardLine

        // Track total time of possession in seconds
        var homeTimeOfPossession = 0
        var awayTimeOfPossession = 0

        // -----------------------------------------------------------------
        // 2. Game Loop — Regulation
        // -----------------------------------------------------------------
        while quarter <= totalRegulationQuarters {
            driveNumber += 1

            let offensePlayers = homeHasPossession ? homePlayers : awayPlayers
            let defensePlayers = homeHasPossession ? awayPlayers : homePlayers

            // Apply morale / personality modifiers before the drive
            applyMoraleModifiers(
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                quarter: quarter
            )

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
                defensiveScheme: homeHasPossession ? awayDefScheme : homeDefScheme
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
            applyFatigue(
                starters: offensePlayers,
                bench: defensePlayers,
                fatigueIncrease: fatiguePerDriveStarter,
                fatigueRecovery: fatigueRecoveryBench
            )

            // -----------------------------------------------------------------
            // Halftime recovery between Q2 and Q3
            // -----------------------------------------------------------------
            if quarter == 3 && allDrives.last?.plays.last.map({ $0.quarter <= 2 }) == true {
                applyHalftimeRecovery(players: homePlayers)
                applyHalftimeRecovery(players: awayPlayers)
                // Home team receives second-half kickoff
                homeHasPossession = true
                startingYardLine = touchbackYardLine
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
            // Quarter management & two-minute warning
            // -----------------------------------------------------------------
            if timeRemaining <= 0 && quarter < totalRegulationQuarters {
                quarter += 1
                timeRemaining = quarterDuration
            }

            // End regulation if time expired in Q4
            if quarter > totalRegulationQuarters {
                break
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
                awayDefScheme: awayDefScheme
            )
            homeScore += otResult.homeOTPoints
            awayScore += otResult.awayOTPoints
            homeQuarterScores[4] = otResult.homeOTPoints
            awayQuarterScores[4] = otResult.awayOTPoints
        }

        // -----------------------------------------------------------------
        // 7. Build Box Score & Stats
        // -----------------------------------------------------------------
        let homeBoxScore = buildTeamBoxScore(
            teamID: homeTeam.id,
            score: homeScore,
            quarterScores: homeQuarterScores,
            drives: allDrives.filter { driveOwner($0, homeTeam: homeTeam) },
            timeOfPossession: homeTimeOfPossession
        )

        let awayBoxScore = buildTeamBoxScore(
            teamID: awayTeam.id,
            score: awayScore,
            quarterScores: awayQuarterScores,
            drives: allDrives.filter { driveOwner($0, awayTeam: awayTeam) },
            timeOfPossession: awayTimeOfPossession
        )

        let boxScore = BoxScore(
            home: homeBoxScore,
            away: awayBoxScore,
            drives: allDrives,
            highlights: allHighlights
        )

        let finalPlayerStats = Array(statsAccumulator.values)
        let mvp = determineMVP(from: finalPlayerStats)

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
        homePlayers: [Player],
        awayPlayers: [Player],
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
        awayDefScheme: DefensiveScheme? = nil
    ) -> OvertimeResult {
        var homeOTPoints = 0
        var awayOTPoints = 0
        var otTimeRemaining = overtimeDuration
        var homeHasPossession = Bool.random() // coin toss
        var firstPossessionComplete = false
        var secondPossessionComplete = false
        var startingYardLine = touchbackYardLine

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
                defensiveScheme: homeHasPossession ? awayDefScheme : homeDefScheme
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
                // Switch possession for second team's guaranteed possession
                let nextInfo = determineNextPossession(
                    afterDrive: drive,
                    homeHasPossession: homeHasPossession
                )
                homeHasPossession = nextInfo.homeHasPossession
                startingYardLine = touchbackYardLine // OT kickoff
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
                    homeHasPossession: homeHasPossession
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
                homeHasPossession: homeHasPossession
            )
            homeHasPossession = nextInfo.homeHasPossession
            startingYardLine = nextInfo.startingYardLine
        }

        return OvertimeResult(homeOTPoints: homeOTPoints, awayOTPoints: awayOTPoints)
    }

    // MARK: - Possession Management

    private struct NextPossession {
        let homeHasPossession: Bool
        let startingYardLine: Int
    }

    /// Determines which team gets the ball next and where on the field they
    /// start based on how the previous drive ended.
    private static func determineNextPossession(
        afterDrive drive: DriveResult,
        homeHasPossession: Bool
    ) -> NextPossession {
        let switchPossession = !homeHasPossession

        switch drive.result {
        case .touchdown, .fieldGoal:
            // Kickoff -> touchback
            return NextPossession(
                homeHasPossession: switchPossession,
                startingYardLine: touchbackYardLine
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
    private static func updateMomentum(
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
    /// - Note: These modifications are applied in-place before each drive and
    ///   are inherently transient because ``DriveSimulator`` reads current
    ///   attribute values at simulation time.
    private static func applyMoraleModifiers(
        offensePlayers: [Player],
        defensePlayers: [Player],
        quarter: Int
    ) {
        let allPlayers = offensePlayers + defensePlayers
        for player in allPlayers {
            // Mood-dependent players with low morale get a penalty
            if player.personality.isMoodDependent && player.morale < lowMoraleThreshold {
                let penalty = Int(Double(player.physical.speed) * moodDependentPenalty)
                player.physical.speed = max(1, player.physical.speed - penalty)
                player.physical.agility = max(1, player.physical.agility - penalty)
                player.mental.awareness = max(1, player.mental.awareness - penalty)
            }

            // Consistent players are unaffected by morale — no modification needed

            // Clutch matters more in Q4 and OT
            if quarter >= 4 {
                let clutchBonus = Int(
                    Double(player.mental.clutch) * (clutchQ4Multiplier - 1.0) / 100.0
                        * Double(player.physical.speed)
                )
                player.mental.decisionMaking = min(99, player.mental.decisionMaking + clutchBonus)
            }
        }
    }

    // MARK: - Fatigue

    /// Increments fatigue for players who just played and slightly recovers
    /// fatigue for bench/opposing-side players.
    private static func applyFatigue(
        starters: [Player],
        bench: [Player],
        fatigueIncrease: Int,
        fatigueRecovery: Int
    ) {
        for player in starters {
            player.fatigue = min(100, player.fatigue + fatigueIncrease)
        }
        for player in bench {
            player.fatigue = max(0, player.fatigue - fatigueRecovery)
        }
    }

    /// Reduces fatigue by 30% for all players during halftime.
    private static func applyHalftimeRecovery(players: [Player]) {
        for player in players {
            let reduction = Int(Double(player.fatigue) * halftimeFatigueReduction)
            player.fatigue = max(0, player.fatigue - reduction)
        }
    }

    // MARK: - Stats Initialization

    /// Seeds the accumulator dictionary with zeroed-out stats for every player.
    private static func initializeStats(
        for players: [Player],
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
    private static func accumulateStats(
        from drive: DriveResult,
        offensePlayers: [Player],
        defensePlayers: [Player],
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

        for play in drive.plays {
            switch play.outcome {
            case .completion:
                // QB passing stats
                if let qb = qb {
                    accumulator[qb.id]?.passingYards += play.yardsGained
                    accumulator[qb.id]?.attempts += 1
                    accumulator[qb.id]?.completions += 1
                }
                // Credit a receiver
                if let receiver = pickWeightedPlayer(from: receivers) {
                    accumulator[receiver.id]?.receivingYards += play.yardsGained
                    accumulator[receiver.id]?.receptions += 1
                    accumulator[receiver.id]?.targets += 1
                }

            case .incompletion:
                if let qb = qb {
                    accumulator[qb.id]?.attempts += 1
                }
                if let receiver = pickWeightedPlayer(from: receivers) {
                    accumulator[receiver.id]?.targets += 1
                }

            case .rush:
                if let rusher = pickWeightedPlayer(from: rbs) {
                    accumulator[rusher.id]?.rushingYards += play.yardsGained
                    accumulator[rusher.id]?.carries += 1
                }
                // Credit a defender with a tackle
                if let tackler = pickWeightedPlayer(from: linebackers + dLinemen) {
                    accumulator[tackler.id]?.tackles += 1
                }

            case .touchdown:
                // Determine if it was a passing or rushing TD based on play type
                if play.playType == .pass {
                    if let qb = qb {
                        accumulator[qb.id]?.passingTDs += 1
                        accumulator[qb.id]?.passingYards += play.yardsGained
                        accumulator[qb.id]?.attempts += 1
                        accumulator[qb.id]?.completions += 1
                    }
                    if let receiver = pickWeightedPlayer(from: receivers) {
                        accumulator[receiver.id]?.receivingTDs += 1
                        accumulator[receiver.id]?.receivingYards += play.yardsGained
                        accumulator[receiver.id]?.receptions += 1
                        accumulator[receiver.id]?.targets += 1
                    }
                } else {
                    if let rusher = pickWeightedPlayer(from: rbs) {
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
                if let db = pickWeightedPlayer(from: dBacks + linebackers) {
                    accumulator[db.id]?.interceptionsCaught += 1
                }

            case .fumble, .fumbleLost:
                if let ballCarrier = pickWeightedPlayer(from: rbs) {
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
    private static func pickWeightedPlayer(from players: [Player]) -> Player? {
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

    /// Checks whether a drive belongs to a given team based on the teamID.
    private static func driveOwner(_ drive: DriveResult, homeTeam: Team) -> Bool {
        drive.teamID == homeTeam.id
    }

    /// Overload for filtering away-team drives.
    private static func driveOwner(_ drive: DriveResult, awayTeam: Team) -> Bool {
        drive.teamID == awayTeam.id
    }

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
                totalYards += play.yardsGained

                switch play.playType {
                case .pass:
                    passingYards += play.yardsGained
                case .run:
                    rushingYards += play.yardsGained
                default:
                    break
                }

                if play.isFirstDown {
                    firstDowns += 1
                }

                // Track 3rd down efficiency
                if play.down == 3 {
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
