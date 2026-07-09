import Foundation
import Combine
import SwiftData

// MARK: - Live Game Engine

/// Play-by-play engine for live, coached games.
///
/// Runs the exact same simulation core as ``GameSimulator/simulate`` —
/// `PlaySimulator` for individual plays plus the shared `DriveSimulator` /
/// `GameSimulator` helpers for clock, down-and-distance, scoring, momentum,
/// fatigue, and stats — but advances one play at a time via ``step`` so the
/// UI can let the user call plays. A fully-AI game (every `step()` called
/// with nil arguments) is statistically identical to `GameSimulator.simulate`.
///
/// Thread model: `@MainActor` because it publishes UI state and holds live
/// SwiftData `Player` references for the end-of-game fatigue write-back.
@MainActor
final class LiveGameEngine: ObservableObject {

    // MARK: - Published Game State

    @Published private(set) var quarter: Int = 1
    /// Seconds remaining in the current quarter.
    @Published private(set) var timeRemaining: Int = GameSimulator.quarterDuration
    @Published private(set) var homeScore: Int = 0
    @Published private(set) var awayScore: Int = 0
    @Published private(set) var homeHasPossession: Bool = true
    @Published private(set) var down: Int = 1
    @Published private(set) var distance: Int = 10
    /// Field position as yards from the offense's own end zone (0–100).
    @Published private(set) var yardLine: Int = GameSimulator.touchbackYardLine
    @Published private(set) var driveNumber: Int = 1
    /// Every play of the game, in order.
    @Published private(set) var playLog: [PlayResult] = []
    /// Plays of the drive currently in progress.
    @Published private(set) var currentDrivePlays: [PlayResult] = []
    @Published private(set) var lastPlay: PlayResult?
    /// Player-vs-player battles resolved for the last play (nil for special teams).
    @Published private(set) var lastMatchups: PlayMatchups?
    @Published private(set) var isGameOver: Bool = false
    /// Per-quarter scoring (index 0–3 = Q1–Q4; index 4 = OT when played).
    @Published private(set) var homeQuarterScores: [Int] = [0, 0, 0, 0]
    @Published private(set) var awayQuarterScores: [Int] = [0, 0, 0, 0]

    /// True when the player's team currently has the ball.
    var playerIsOnOffense: Bool { playerTeamIsHome == homeHasPossession }

    // MARK: - Situation Helpers (UI)

    var isFourthDown: Bool { down == 4 }

    /// Field-goal attempt length in yards (line of scrimmage + 17 for snap/hold).
    var fieldGoalDistance: Int { 100 - yardLine + 17 }

    /// Whether a field goal is realistic from here (<= 45 yards to the end
    /// zone, same convention as `PlaySimulator.decidePlayCall`).
    var canAttemptFieldGoal: Bool { (100 - yardLine) <= 45 }

    /// Clock string like "14:05".
    var formattedClock: String {
        let t = max(0, timeRemaining)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    var possessionTeamID: UUID { homeHasPossession ? homeTeamID : awayTeamID }

    /// Starters currently on offense / defense (role-ordered).
    var currentOffenseUnit: FieldUnit { homeHasPossession ? homeOffenseUnit : awayOffenseUnit }
    var currentDefenseUnit: FieldUnit { homeHasPossession ? awayDefenseUnit : homeDefenseUnit }

    /// The offensive scheme of the team currently in possession (its playbook).
    var currentOffensiveScheme: OffensiveScheme? { homeHasPossession ? homeOffScheme : awayOffScheme }
    /// The player's own offensive/defensive schemes (for the call sheet UI).
    var playerOffensiveScheme: OffensiveScheme? { playerTeamIsHome ? homeOffScheme : awayOffScheme }
    var playerDefensiveScheme: DefensiveScheme? { playerTeamIsHome ? homeDefScheme : awayDefScheme }

    /// Average playbook familiarity (0–100) of the player's offensive starters.
    var playerPlaybookFamiliarity: Int {
        guard let scheme = playerOffensiveScheme else { return 100 }
        let unit = playerTeamIsHome ? homeOffenseUnit : awayOffenseUnit
        let total = unit.players.reduce(0) { $0 + $1.schemeFam(for: scheme.rawValue) }
        return total / max(1, unit.players.count)
    }

    /// Current momentum (-1 away … +1 home), for UI meters.
    var currentMomentum: Double { momentum }

    // MARK: - Immutable Setup

    let homeTeamID: UUID
    let awayTeamID: UUID
    let playerTeamIsHome: Bool

    private let homeOffScheme: OffensiveScheme?
    private let homeDefScheme: DefensiveScheme?
    private let awayOffScheme: OffensiveScheme?
    private let awayDefScheme: DefensiveScheme?
    private let audibleBoost: Double
    private let defReadBoost: Double

    // MARK: - Player Game Plan

    /// Hand-off slot for the user's saved ``GamePlan``. Set by the dashboard
    /// right before presenting the coached game; consumed (and cleared) in
    /// `init`. A static hand-off is used because `CoachedGameView` constructs
    /// this engine itself and its signature must stay untouched. Same pattern
    /// as `WeekAdvancer.lastPlayerGameResult`.
    static var pendingPlayerGamePlan: GamePlan?

    /// The user's game plan for this match, or `nil` (= no bias, today's
    /// behavior). Only ever applied to the PLAYER's team — AI play-calling
    /// for the opponent is never affected.
    private let playerGamePlan: GamePlan?

    // MARK: - Simulation State

    private var homePlayers: [SimPlayer]
    private var awayPlayers: [SimPlayer]
    /// Role-ordered starters for the 3D field and matchup attribution.
    let homeOffenseUnit: FieldUnit
    let homeDefenseUnit: FieldUnit
    let awayOffenseUnit: FieldUnit
    let awayDefenseUnit: FieldUnit
    private let livePlayerByID: [UUID: Player]
    private var momentum: Double = GameSimulator.homeFieldMomentum
    private var statsAccumulator: [UUID: PlayerGameStats] = [:]
    private var allDrives: [DriveResult] = []
    private var allHighlights: [PlayResult] = []
    private var homeTimeOfPossession = 0
    private var awayTimeOfPossession = 0
    private var driveStartYardLine: Int = GameSimulator.touchbackYardLine
    private var moraleAppliedForCurrentDrive = false

    private var isOvertime: Bool { quarter >= GameSimulator.overtimeQuarter }

    // MARK: - Init

    /// - Parameters:
    ///   - playerTeamIsHome: Which side the user coaches (drives `playerIsOnOffense`).
    ///   - audibleBoost: 0..0.20 opponent-prep offense boost for the player's team.
    ///   - defReadBoost: 0..0.15 opponent-prep defense boost for the player's team.
    init(
        homeTeam: Team,
        awayTeam: Team,
        homeCoaches: [Coach],
        awayCoaches: [Coach],
        playerTeamIsHome: Bool,
        audibleBoost: Double = 0,
        defReadBoost: Double = 0
    ) {
        homeTeamID = homeTeam.id
        awayTeamID = awayTeam.id
        self.playerTeamIsHome = playerTeamIsHome
        self.audibleBoost = max(0.0, min(0.20, audibleBoost))
        self.defReadBoost = max(0.0, min(0.15, defReadBoost))

        // Consume the game-plan hand-off (see `pendingPlayerGamePlan`).
        self.playerGamePlan = LiveGameEngine.pendingPlayerGamePlan
        LiveGameEngine.pendingPlayerGamePlan = nil

        // Snapshot both rosters into value types once (same rationale as
        // GameSimulator.simulate): reading SwiftData @Model properties in the
        // play-by-play hot path is far too slow. Live models are kept in a
        // lookup so fatigue can be written back after the game.
        let homeRoster = homeTeam.players
        let awayRoster = awayTeam.players
        homePlayers = homeRoster.map(SimPlayer.init(from:))
        awayPlayers = awayRoster.map(SimPlayer.init(from:))
        homeOffenseUnit = FieldUnit.offense(from: homePlayers)
        homeDefenseUnit = FieldUnit.defense(from: homePlayers)
        awayOffenseUnit = FieldUnit.offense(from: awayPlayers)
        awayDefenseUnit = FieldUnit.defense(from: awayPlayers)
        var lookup: [UUID: Player] = [:]
        for player in homeRoster { lookup[player.id] = player }
        for player in awayRoster { lookup[player.id] = player }
        livePlayerByID = lookup

        // Extract team schemes from the coaching staff, exactly like
        // GameSimulator.simulate.
        homeOffScheme = homeCoaches.first { $0.role == .offensiveCoordinator }?.offensiveScheme
        homeDefScheme = homeCoaches.first { $0.role == .defensiveCoordinator }?.defensiveScheme
        awayOffScheme = awayCoaches.first { $0.role == .offensiveCoordinator }?.offensiveScheme
        awayDefScheme = awayCoaches.first { $0.role == .defensiveCoordinator }?.defensiveScheme

        // Seed stat entries for every rostered player.
        GameSimulator.initializeStats(for: homePlayers, into: &statsAccumulator)
        GameSimulator.initializeStats(for: awayPlayers, into: &statsAccumulator)

        // Opening kickoff: home receives at the 25 (mirrors GameSimulator).
    }

    // MARK: - Step (one play)

    /// Runs exactly one play and advances all game state.
    ///
    /// - Parameters:
    ///   - offensiveCall: Explicit offensive call. `nil` lets the AI decide
    ///     via `PlaySimulator.decidePlayCall` (identical to auto-sim).
    ///   - forcedPlayType: Highest-precedence override, used for 4th-down
    ///     special-teams decisions (.punt / .fieldGoal / .kneel).
    ///   - defensivePackage: Explicit defensive call. `nil` = neutral defense.
    /// - Returns: The play that was run (also published as ``lastPlay``).
    @discardableResult
    func step(
        offensiveCall: OffensivePlayCall? = nil,
        forcedPlayType: PlayType? = nil,
        defensivePackage: DefensivePackage? = nil
    ) -> PlayResult {
        guard !isGameOver else {
            return lastPlay ?? gameOverPlaceholderPlay()
        }

        // GameSimulator applies morale/personality modifiers once per drive.
        if !moraleAppliedForCurrentDrive {
            GameSimulator.applyMoraleModifiers(players: &homePlayers, quarter: quarter)
            GameSimulator.applyMoraleModifiers(players: &awayPlayers, quarter: quarter)
            moraleAppliedForCurrentDrive = true
        }

        let offense = homeHasPossession ? homePlayers : awayPlayers
        let defense = homeHasPossession ? awayPlayers : homePlayers

        // Momentum is offense-relative in PlaySimulator; positive favors home.
        // Opponent-prep boosts shade momentum slightly toward the player's
        // team (GameSimulator applies these as a final-score nudge instead;
        // a live game must keep its displayed score truthful, so the boost is
        // folded into per-play momentum at conservative strength).
        var playMomentum = homeHasPossession ? momentum : -momentum
        if audibleBoost > 0 || defReadBoost > 0 {
            if playerIsOnOffense {
                playMomentum = min(1.0, playMomentum + audibleBoost * 0.5)
            } else {
                playMomentum = max(-1.0, playMomentum - defReadBoost * 0.5)
            }
        }

        let result = PlaySimulator.simulatePlay(
            offensePlayers: offense,
            defensePlayers: defense,
            down: down,
            distance: distance,
            yardLine: yardLine,
            quarter: quarter,
            timeRemaining: timeRemaining,
            momentum: playMomentum,
            playNumber: currentDrivePlays.count + 1,
            offensiveScheme: homeHasPossession ? homeOffScheme : awayOffScheme,
            defensiveScheme: homeHasPossession ? awayDefScheme : homeDefScheme,
            offensiveCall: offensiveCall,
            forcedPlayType: forcedPlayType,
            defensivePackage: defensivePackage,
            gamePlan: playerIsOnOffense ? playerGamePlan : nil
        )

        // Record the play with the clock state at the snap (mirrors DriveSimulator).
        var recordedPlay = result
        recordedPlay.quarter = quarter
        recordedPlay.timeRemaining = timeRemaining
        currentDrivePlays.append(recordedPlay)
        playLog.append(recordedPlay)
        lastPlay = recordedPlay

        // Attribute the play to individual matchup winners for the live view.
        if result.playType == .pass || result.playType == .run {
            lastMatchups = MatchupResolver.resolve(
                play: recordedPlay,
                offense: currentOffenseUnit,
                defense: currentDefenseUnit,
                offensiveScheme: homeHasPossession ? homeOffScheme : awayOffScheme,
                offensiveCall: offensiveCall
            )
        } else {
            lastMatchups = nil
        }

        // --- Consume clock (mirrors DriveSimulator.simulateDrive) ---
        let elapsed = DriveSimulator.clockConsumption(for: result)
        timeRemaining -= elapsed

        if timeRemaining <= 0 {
            let overflow = abs(timeRemaining)
            if DriveSimulator.shouldEndDrive(quarter: quarter) {
                // Q2 / Q4 / OT: the half or game segment ends here.
                timeRemaining = 0
                // The play itself may still have ended the drive (TD at the gun).
                if let driveEnd = immediateDriveEnd(for: result) {
                    finishDrive(driveEnd.drive)
                    return recordedPlay
                }
                let outcome: DriveOutcome = quarter == 2 ? .endOfHalf : .endOfGame
                finishDrive(makeDriveResult(outcome))
                return recordedPlay
            } else {
                // Quarter transition (Q1 -> Q2, Q3 -> Q4): drive continues.
                quarter += 1
                timeRemaining = GameSimulator.quarterDuration - overflow
            }
        }

        // --- Immediate drive-ending outcomes (score, turnover, punt, safety) ---
        if let driveEnd = immediateDriveEnd(for: result) {
            finishDrive(driveEnd.drive)
            return recordedPlay
        }

        // --- Down & distance ---
        let advanced = DriveSimulator.advanceDownAndDistance(
            playResult: result,
            currentDown: down,
            currentDistance: distance,
            currentYardLine: yardLine
        )
        down = advanced.down
        distance = advanced.distance
        yardLine = advanced.yardLine

        // --- Turnover on downs ---
        if down > 4 {
            finishDrive(makeDriveResult(.turnoverOnDowns))
            return recordedPlay
        }

        // Safety valve: prevent infinite drives (mirrors DriveSimulator's cap).
        if currentDrivePlays.count >= 40 {
            finishDrive(makeDriveResult(.punt))
        }

        return recordedPlay
    }

    // MARK: - AI Suggestions

    /// The play type the auto-sim AI would call in the current situation.
    /// When the PLAYER's team has the ball, the suggestion honors the user's
    /// saved game plan (run/pass mix, 4th-down aggressiveness).
    func aiOffensiveCallHint() -> PlayType {
        PlaySimulator.decidePlayCall(
            down: down,
            distance: distance,
            yardLine: yardLine,
            quarter: quarter,
            timeRemaining: timeRemaining,
            offensiveScheme: homeHasPossession ? homeOffScheme : awayOffScheme,
            gamePlan: playerIsOnOffense ? playerGamePlan : nil
        )
    }

    /// A simple situational defensive call for the AI (or as a user default).
    /// When suggesting for the PLAYER's defense, the user's game plan shades
    /// the blitz package: heavy blitz plans send pressure on standard downs,
    /// coverage-first plans call off the situational blitzes.
    func aiDefensivePackage() -> DefensivePackage {
        let yardsToEndzone = 100 - yardLine
        var package: DefensivePackage
        if yardsToEndzone <= 10 {
            // Red zone: sell out against the short field.
            package = DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .goalLine)
        } else if down == 3 && distance >= 7 {
            // 3rd & long: extra DBs and a pressure look.
            package = DefensivePackage(coverage: .cover4, blitz: .dbBlitz, front: .dime)
        } else if distance <= 2 {
            // Short yardage: stout base front.
            package = DefensivePackage(coverage: .cover2, blitz: .noBlitz, front: .base)
        } else {
            package = .standard // Cover 3, no blitz, base front
        }

        // Game-plan shading — only for the player's own defense.
        if !playerIsOnOffense, let plan = playerGamePlan {
            if plan.blitzFrequency > 0.65, package.blitz == .noBlitz, yardsToEndzone > 10 {
                package.blitz = .lbBlitz
            } else if plan.blitzFrequency < 0.25, package.blitz != .noBlitz {
                package.blitz = .noBlitz
            }
            if plan.defensiveAggression > 0.75, package.coverage == .cover3 {
                package.coverage = .manToMan
            }
        }
        return package
    }

    // MARK: - Auto-Sim

    /// Runs AI-vs-AI plays until the game ends (capped at 500 plays as a safety).
    func simToEnd() {
        var playCount = 0
        while !isGameOver && playCount < 500 {
            _ = step()
            playCount += 1
        }
        if !isGameOver {
            isGameOver = true // hard safety cap — should never trigger in practice
        }
    }

    // MARK: - Result & Persistence

    /// Assembles the final ``GameSimulator/GameResult`` (box score, player
    /// stats, MVP) and writes accumulated fatigue back to the live `Player`
    /// models, exactly like `GameSimulator.simulate` does at game end.
    func buildResult() -> GameSimulator.GameResult {
        GameSimulator.finalizeGameResult(
            homeTeamID: homeTeamID,
            awayTeamID: awayTeamID,
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

    /// Writes the final score to the `Game`, updates both teams' records, and
    /// stores the result in `WeekAdvancer.lastPlayerGameResult` so the weekly
    /// press conference / recap UI can pick it up after `advanceWeek`.
    func persist(to game: Game, context: ModelContext, teamsByID: [UUID: Team]) {
        let result = buildResult()
        game.homeScore = result.homeScore
        game.awayScore = result.awayScore
        WeekAdvancer.updateTeamRecords(game: game, teamsByID: teamsByID)
        WeekAdvancer.lastPlayerGameResult = result
        try? context.save()
    }

    // MARK: - Drive Lifecycle (private)

    /// Wraps `DriveSimulator.checkImmediateDriveEnd` with the engine's state.
    private func immediateDriveEnd(for result: PlayResult) -> DriveSimulator.DriveSimulationResult? {
        DriveSimulator.checkImmediateDriveEnd(
            result,
            plays: currentDrivePlays,
            driveNumber: driveNumber,
            teamID: possessionTeamID,
            startingYardLine: driveStartYardLine,
            quarter: quarter,
            time: timeRemaining
        )
    }

    private func makeDriveResult(_ outcome: DriveOutcome) -> DriveResult {
        DriveResult(
            driveNumber: driveNumber,
            teamID: possessionTeamID,
            startingYardLine: driveStartYardLine,
            plays: currentDrivePlays,
            result: outcome
        )
    }

    /// Per-drive bookkeeping — mirrors GameSimulator.simulate's drive loop
    /// (stats, time of possession, highlights, scoring incl. safety-to-defense,
    /// momentum, fatigue), then handles the possession/quarter transition.
    private func finishDrive(_ drive: DriveResult) {
        allDrives.append(drive)

        let offense = homeHasPossession ? homePlayers : awayPlayers
        let defense = homeHasPossession ? awayPlayers : homePlayers
        GameSimulator.accumulateStats(
            from: drive,
            offensePlayers: offense,
            defensePlayers: defense,
            into: &statsAccumulator
        )

        let driveTime = drive.timeConsumed
        if homeHasPossession {
            homeTimeOfPossession += driveTime
        } else {
            awayTimeOfPossession += driveTime
        }

        allHighlights.append(contentsOf: drive.plays.filter {
            $0.scoringPlay || $0.isTurnover || $0.yardsGained >= 20
        })

        // Score: drive points go to the possessing team; a safety is worth
        // +2 to the defense. Identical bookkeeping to GameSimulator.simulate.
        let quarterIndex = min(quarter - 1, homeQuarterScores.count - 1)
        let drivePoints = drive.plays.reduce(0) { $0 + $1.pointsScored }
        if drivePoints > 0 {
            if homeHasPossession {
                homeScore += drivePoints
                homeQuarterScores[quarterIndex] += drivePoints
            } else {
                awayScore += drivePoints
                awayQuarterScores[quarterIndex] += drivePoints
            }
        }
        if drive.result == .safety {
            if homeHasPossession {
                awayScore += 2
                awayQuarterScores[quarterIndex] += 2
            } else {
                homeScore += 2
                homeQuarterScores[quarterIndex] += 2
            }
        }

        momentum = GameSimulator.updateMomentum(
            currentMomentum: momentum,
            drive: drive,
            homeHasPossession: homeHasPossession
        )

        if homeHasPossession {
            GameSimulator.applyFatigue(
                starters: &homePlayers,
                bench: &awayPlayers,
                fatigueIncrease: GameSimulator.fatiguePerDriveStarter,
                fatigueRecovery: GameSimulator.fatigueRecoveryBench
            )
        } else {
            GameSimulator.applyFatigue(
                starters: &awayPlayers,
                bench: &homePlayers,
                fatigueIncrease: GameSimulator.fatiguePerDriveStarter,
                fatigueRecovery: GameSimulator.fatigueRecoveryBench
            )
        }

        if isOvertime {
            endOvertimeDrive(drive)
        } else {
            endRegulationDrive(drive)
        }
    }

    private func endRegulationDrive(_ drive: DriveResult) {
        let next = GameSimulator.determineNextPossession(
            afterDrive: drive,
            homeHasPossession: homeHasPossession
        )
        var nextHome = next.homeHasPossession
        var nextYardLine = next.startingYardLine

        if timeRemaining <= 0 {
            if quarter >= 4 {
                // Regulation over: sudden-death OT if tied, otherwise final.
                if homeScore == awayScore {
                    startOvertime()
                } else {
                    isGameOver = true
                }
                return
            }
            quarter += 1
            timeRemaining = GameSimulator.quarterDuration
            if quarter == 3 {
                // Halftime: both teams recover; home receives the second-half
                // kickoff at the 25.
                GameSimulator.applyHalftimeRecovery(players: &homePlayers)
                GameSimulator.applyHalftimeRecovery(players: &awayPlayers)
                nextHome = true
                nextYardLine = GameSimulator.touchbackYardLine
            }
        }

        homeHasPossession = nextHome
        beginDrive(at: nextYardLine)
    }

    /// Simple sudden death: first score wins; if the 10-minute period expires
    /// with the game still tied, it ends in a tie.
    private func endOvertimeDrive(_ drive: DriveResult) {
        if homeScore != awayScore || timeRemaining <= 0 {
            isGameOver = true
            return
        }
        let next = GameSimulator.determineNextPossession(
            afterDrive: drive,
            homeHasPossession: homeHasPossession
        )
        homeHasPossession = next.homeHasPossession
        beginDrive(at: next.startingYardLine)
    }

    private func startOvertime() {
        quarter = GameSimulator.overtimeQuarter
        timeRemaining = GameSimulator.overtimeDuration
        homeQuarterScores.append(0)
        awayQuarterScores.append(0)
        homeHasPossession = Bool.random() // OT coin toss
        beginDrive(at: GameSimulator.touchbackYardLine)
    }

    private func beginDrive(at startingYardLine: Int) {
        driveNumber += 1
        driveStartYardLine = max(1, min(99, startingYardLine))
        yardLine = driveStartYardLine
        down = 1
        // Cap first-down distance near the end zone (mirrors DriveSimulator).
        distance = min(10, 100 - driveStartYardLine)
        currentDrivePlays = []
        moraleAppliedForCurrentDrive = false
    }

    /// Returned by ``step`` only if it is called after the game has ended.
    private func gameOverPlaceholderPlay() -> PlayResult {
        PlayResult(
            playNumber: 0,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .kneel,
            outcome: .kneel,
            yardsGained: 0,
            description: "The game is over.",
            isFirstDown: false,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0
        )
    }
}
