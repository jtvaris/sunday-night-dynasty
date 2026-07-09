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

    // MARK: - Kickoffs

    /// Pre-drive kickoff descriptor for the live view: consumed by
    /// `CoachedGameView` to run the kickoff choreography before the first snap
    /// of a new drive. Purely presentational — the drive's start position has
    /// already been decided by the shared kickoff distribution.
    struct KickoffEvent: Equatable {
        /// The side that boots the ball (the team that just scored / opens the half).
        let kickingTeamIsHome: Bool
        /// The receiving team's drive start (yards from its own goal line).
        let startYardLine: Int
        /// True when the draw was a touchback (returner kneels in the end zone).
        let isTouchback: Bool
        /// True when the kick was housed for a return touchdown.
        let isReturnTouchdown: Bool
    }

    /// Set whenever a new drive begins with a kickoff (game start, after
    /// scores, second-half kick, OT kick). The view consumes it via
    /// ``clearPendingKickoff()`` before animating.
    @Published private(set) var pendingKickoff: KickoffEvent?

    func clearPendingKickoff() { pendingKickoff = nil }

    // MARK: - Timeouts

    /// Timeouts remaining per side: three per half, restocked at halftime.
    @Published private(set) var homeTimeouts: Int = 3
    @Published private(set) var awayTimeouts: Int = 3

    /// Set by ``useTimeout(home:)`` and consumed by the next ``step``: the
    /// timeout freezes the game clock, so that play's runoff is zeroed.
    private var timeoutClockStopPending = false

    /// Timeouts left for the side the user coaches (UI convenience).
    var playerTimeoutsRemaining: Int { playerTeamIsHome ? homeTimeouts : awayTimeouts }

    /// Burns one of the given side's timeouts to stop the clock: the next
    /// play consumes no game time. AI teams never call timeouts, so a fully
    /// nil-argument game remains identical to `GameSimulator.simulate`.
    /// - Returns: true when a timeout was actually available and used.
    @discardableResult
    func useTimeout(home: Bool) -> Bool {
        guard !isGameOver, !timeoutClockStopPending else { return false }
        if home {
            guard homeTimeouts > 0 else { return false }
            homeTimeouts -= 1
        } else {
            guard awayTimeouts > 0 else { return false }
            awayTimeouts -= 1
        }
        timeoutClockStopPending = true
        return true
    }

    // MARK: - Matchup Grades (live only)

    /// Individual matchup wins/losses per player, accumulated from
    /// ``lastMatchups`` every play (see ``step``). Purely presentational —
    /// never feeds back into the simulation, so auto-sim parity is intact.
    @Published private(set) var matchupWins: [UUID: Int] = [:]
    @Published private(set) var matchupLosses: [UUID: Int] = [:]

    /// One row of the end-of-game "Top performers" list.
    struct MatchupPerformer: Identifiable {
        let id: UUID
        let name: String
        let isHomeTeam: Bool
        let wins: Int
        let losses: Int
    }

    /// Players with the most individual matchup wins this game (ties broken
    /// by fewer losses). Empty until at least one battle has been resolved.
    func topPerformers(limit: Int = 3) -> [MatchupPerformer] {
        guard !matchupWins.isEmpty else { return [] }
        var lookup: [UUID: (name: String, isHome: Bool)] = [:]
        for unit in [homeOffenseUnit, homeDefenseUnit] {
            for player in unit.players { lookup[player.id] = (player.shortName, true) }
        }
        for unit in [awayOffenseUnit, awayDefenseUnit] {
            for player in unit.players { lookup[player.id] = (player.shortName, false) }
        }
        return matchupWins
            .compactMap { id, wins -> MatchupPerformer? in
                guard let info = lookup[id] else { return nil }
                return MatchupPerformer(
                    id: id, name: info.name, isHomeTeam: info.isHome,
                    wins: wins, losses: matchupLosses[id] ?? 0
                )
            }
            .sorted { ($0.wins, $1.losses) > ($1.wins, $0.losses) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Live Stat Leaders

    /// One statistical leader line for the live box score panel.
    struct StatLeader: Identifiable {
        let id: UUID
        let name: String
        /// Compact stat line, e.g. "18/25 · 245 YDS · 2 TD".
        let detail: String
    }

    /// Stats accumulate per completed drive (mirroring the quick sim), so
    /// these leaders reflect everything up to the current drive.
    func passingLeader(forHome: Bool) -> StatLeader? {
        teamStats(forHome: forHome)
            .filter { $0.attempts > 0 }
            .max { $0.passingYards < $1.passingYards }
            .map { s in
                var detail = "\(s.completions)/\(s.attempts) · \(s.passingYards) YDS"
                if s.passingTDs > 0 { detail += " · \(s.passingTDs) TD" }
                if s.interceptions > 0 { detail += " · \(s.interceptions) INT" }
                return StatLeader(id: s.playerID, name: shortName(s.playerName), detail: detail)
            }
    }

    func rushingLeader(forHome: Bool) -> StatLeader? {
        teamStats(forHome: forHome)
            .filter { $0.carries > 0 }
            .max { $0.rushingYards < $1.rushingYards }
            .map { s in
                var detail = "\(s.carries) CAR · \(s.rushingYards) YDS"
                if s.rushingTDs > 0 { detail += " · \(s.rushingTDs) TD" }
                return StatLeader(id: s.playerID, name: shortName(s.playerName), detail: detail)
            }
    }

    func receivingLeader(forHome: Bool) -> StatLeader? {
        teamStats(forHome: forHome)
            .filter { $0.receptions > 0 }
            .max { $0.receivingYards < $1.receivingYards }
            .map { s in
                var detail = "\(s.receptions) REC · \(s.receivingYards) YDS"
                if s.receivingTDs > 0 { detail += " · \(s.receivingTDs) TD" }
                return StatLeader(id: s.playerID, name: shortName(s.playerName), detail: detail)
            }
    }

    func sackLeader(forHome: Bool) -> StatLeader? {
        teamStats(forHome: forHome)
            .filter { $0.sacks > 0 }
            .max { $0.sacks < $1.sacks }
            .map { s in
                let count = s.sacks.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(s.sacks)) : String(format: "%.1f", s.sacks)
                return StatLeader(id: s.playerID, name: shortName(s.playerName),
                                  detail: "\(count) SACK\(s.sacks == 1 ? "" : "S") · \(s.tackles) TKL")
            }
    }

    /// Total offensive yards from completed drives (same accounting as
    /// `GameSimulator.buildTeamBoxScore` — scrimmage plays only, penalty
    /// walk-offs and special-teams yardage excluded).
    func totalYards(forHome: Bool) -> Int {
        let teamID = forHome ? homeTeamID : awayTeamID
        return allDrives
            .filter { $0.teamID == teamID }
            .reduce(0) { total, drive in
                total + drive.plays
                    .filter { ($0.playType == .pass || $0.playType == .run) && $0.outcome != .penalty }
                    .reduce(0) { $0 + $1.yardsGained }
            }
    }

    private func teamStats(forHome: Bool) -> [PlayerGameStats] {
        let ids = forHome ? homePlayerIDs : awayPlayerIDs
        return ids.compactMap { statsAccumulator[$0] }
    }

    /// "T. Hill" — mirrors `SimPlayer.shortName` for stat-line names.
    private func shortName(_ fullName: String) -> String {
        let parts = fullName.split(separator: " ")
        guard parts.count >= 2, let first = parts.first?.first else { return fullName }
        return "\(first). \(parts.dropFirst().joined(separator: " "))"
    }

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
    /// Roster membership for splitting the shared stats accumulator per team.
    private let homePlayerIDs: [UUID]
    private let awayPlayerIDs: [UUID]
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
        homePlayerIDs = homePlayers.map(\.id)
        awayPlayerIDs = awayPlayers.map(\.id)

        // Extract team schemes from the coaching staff, exactly like
        // GameSimulator.simulate.
        homeOffScheme = homeCoaches.first { $0.role == .offensiveCoordinator }?.offensiveScheme
        homeDefScheme = homeCoaches.first { $0.role == .defensiveCoordinator }?.defensiveScheme
        awayOffScheme = awayCoaches.first { $0.role == .offensiveCoordinator }?.offensiveScheme
        awayDefScheme = awayCoaches.first { $0.role == .defensiveCoordinator }?.defensiveScheme

        // Seed stat entries for every rostered player.
        GameSimulator.initializeStats(for: homePlayers, into: &statsAccumulator)
        GameSimulator.initializeStats(for: awayPlayers, into: &statsAccumulator)

        // Opening kickoff: away kicks to home; the start position comes from
        // the shared kickoff distribution (mirrors GameSimulator.simulate).
        let openingKick = GameSimulator.rollKickoff(allowReturnTouchdown: false)
        driveStartYardLine = openingKick.startingYardLine
        yardLine = openingKick.startingYardLine
        distance = min(10, 100 - openingKick.startingYardLine)
        pendingKickoff = KickoffEvent(
            kickingTeamIsHome: false,
            startYardLine: openingKick.startingYardLine,
            isTouchback: openingKick.isTouchback,
            isReturnTouchdown: false
        )
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
            let offenseUnit = currentOffenseUnit
            let defenseUnit = currentDefenseUnit
            lastMatchups = MatchupResolver.resolve(
                play: recordedPlay,
                offense: offenseUnit,
                defense: defenseUnit,
                offensiveScheme: homeHasPossession ? homeOffScheme : awayOffScheme,
                offensiveCall: offensiveCall
            )
            // Player grades: tally each named battle's winner and loser
            // (presentation only — the play outcome is already decided).
            if let events = lastMatchups?.events {
                for event in events {
                    let winnerID = event.offenseWon
                        ? event.offRole.map { offenseUnit[$0].id }
                        : event.defRole.map { defenseUnit[$0].id }
                    let loserID = event.offenseWon
                        ? event.defRole.map { defenseUnit[$0].id }
                        : event.offRole.map { offenseUnit[$0].id }
                    if let winnerID { matchupWins[winnerID, default: 0] += 1 }
                    if let loserID { matchupLosses[loserID, default: 0] += 1 }
                }
            }
        } else {
            lastMatchups = nil
        }

        // --- Consume clock (mirrors DriveSimulator.simulateDrive) ---
        // A pending timeout freezes the clock: this play's runoff is zeroed.
        var elapsed = DriveSimulator.clockConsumption(for: result)
        if timeoutClockStopPending {
            elapsed = 0
            timeoutClockStopPending = false
        }
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
        // The view animates this kickoff (when non-nil) before the next snap.
        var kickoffEvent: KickoffEvent? = next.kickoff.map { kick in
            KickoffEvent(
                kickingTeamIsHome: homeHasPossession,
                startYardLine: kick.startingYardLine,
                isTouchback: kick.isTouchback,
                isReturnTouchdown: false
            )
        }

        // Kickoff return touchdown: the receiving team houses the ensuing
        // kick (same distribution and bookkeeping as GameSimulator.simulate).
        // Only while the half is still alive — no kick after the clock expires.
        if let kick = next.kickoff, kick.isReturnTouchdown, timeRemaining > 0 {
            let returnTeamIsHome = nextHome
            scoreKickoffReturnTouchdown(returnTeamIsHome: returnTeamIsHome)
            // The housed kick is the one worth showing; the ensuing kickoff
            // hands the ball straight back to the team that originally scored.
            kickoffEvent = KickoffEvent(
                kickingTeamIsHome: !returnTeamIsHome,
                startYardLine: 100,
                isTouchback: false,
                isReturnTouchdown: true
            )
            let ensuing = GameSimulator.rollKickoff(allowReturnTouchdown: false)
            nextHome = !returnTeamIsHome
            nextYardLine = ensuing.startingYardLine
        }

        if timeRemaining <= 0 {
            if quarter >= 4 {
                // Regulation over: sudden-death OT if tied, otherwise final.
                if homeScore == awayScore {
                    startOvertime()
                } else {
                    pendingKickoff = nil
                    isGameOver = true
                }
                return
            }
            quarter += 1
            timeRemaining = GameSimulator.quarterDuration
            if quarter == 3 {
                // Halftime: both teams recover; home receives the second-half
                // kickoff (position from the shared kickoff distribution).
                // Timeouts restock — three per half.
                GameSimulator.applyHalftimeRecovery(players: &homePlayers)
                GameSimulator.applyHalftimeRecovery(players: &awayPlayers)
                homeTimeouts = 3
                awayTimeouts = 3
                timeoutClockStopPending = false
                nextHome = true
                let halfKick = GameSimulator.rollKickoff(allowReturnTouchdown: false)
                nextYardLine = halfKick.startingYardLine
                kickoffEvent = KickoffEvent(
                    kickingTeamIsHome: false,
                    startYardLine: halfKick.startingYardLine,
                    isTouchback: halfKick.isTouchback,
                    isReturnTouchdown: false
                )
            }
        }

        homeHasPossession = nextHome
        pendingKickoff = kickoffEvent
        beginDrive(at: nextYardLine)
    }

    /// Adds a synthetic one-play kickoff-return-touchdown drive to the books:
    /// score, quarter scores, play log, highlights, and momentum — mirroring
    /// the quick sim's bookkeeping for the same event.
    private func scoreKickoffReturnTouchdown(returnTeamIsHome: Bool) {
        driveNumber += 1
        let play = GameSimulator.kickoffReturnTouchdownPlay(
            quarter: quarter,
            timeRemaining: timeRemaining
        )
        let returnDrive = DriveResult(
            driveNumber: driveNumber,
            teamID: returnTeamIsHome ? homeTeamID : awayTeamID,
            startingYardLine: GameSimulator.kickoffTouchbackYardLine,
            plays: [play],
            result: .touchdown
        )
        allDrives.append(returnDrive)
        allHighlights.append(play)
        playLog.append(play)

        let quarterIndex = min(quarter - 1, homeQuarterScores.count - 1)
        if returnTeamIsHome {
            homeScore += play.pointsScored
            homeQuarterScores[quarterIndex] += play.pointsScored
        } else {
            awayScore += play.pointsScored
            awayQuarterScores[quarterIndex] += play.pointsScored
        }

        momentum = GameSimulator.updateMomentum(
            currentMomentum: momentum,
            drive: returnDrive,
            homeHasPossession: returnTeamIsHome
        )
    }

    /// Simple sudden death: first score wins; if the 10-minute period expires
    /// with the game still tied, it ends in a tie.
    private func endOvertimeDrive(_ drive: DriveResult) {
        if homeScore != awayScore || timeRemaining <= 0 {
            pendingKickoff = nil
            isGameOver = true
            return
        }
        let next = GameSimulator.determineNextPossession(
            afterDrive: drive,
            homeHasPossession: homeHasPossession,
            allowKickoffReturnTouchdown: false
        )
        homeHasPossession = next.homeHasPossession
        pendingKickoff = nil // sudden-death transitions play on without a kick
        beginDrive(at: next.startingYardLine)
    }

    private func startOvertime() {
        quarter = GameSimulator.overtimeQuarter
        timeRemaining = GameSimulator.overtimeDuration
        homeQuarterScores.append(0)
        awayQuarterScores.append(0)
        homeHasPossession = Bool.random() // OT coin toss
        let otKick = GameSimulator.rollKickoff(allowReturnTouchdown: false)
        pendingKickoff = KickoffEvent(
            kickingTeamIsHome: !homeHasPossession,
            startYardLine: otKick.startingYardLine,
            isTouchback: otKick.isTouchback,
            isReturnTouchdown: false
        )
        beginDrive(at: otKick.startingYardLine)
    }

    // MARK: - Onside Kick (player choice, live game only)

    /// True right after the player's team scored while trailing in the 4th
    /// quarter (or OT never applies — a score there ends the game): the window
    /// where the view offers an onside kick instead of the pending deep kick.
    var onsideKickAvailable: Bool {
        guard !isGameOver, quarter >= 4, currentDrivePlays.isEmpty else { return false }
        guard let kick = pendingKickoff, !kick.isReturnTouchdown else { return false }
        // The player's team must be the kicking team and still trailing.
        guard kick.kickingTeamIsHome == playerTeamIsHome else { return false }
        let playerScore = playerTeamIsHome ? homeScore : awayScore
        let opponentScore = playerTeamIsHome ? awayScore : homeScore
        return playerScore < opponentScore
    }

    /// Replaces the pending deep kickoff with an onside attempt: a recovery
    /// (~12%) keeps the ball with the player's team near midfield; a failure
    /// hands the receiving team a short field. Live game only — the quick sim
    /// never onsides. Because this replaces a player choice (never taken by
    /// the AI), nil-parameter parity with `GameSimulator.simulate` is intact.
    /// - Returns: true when the kicking team recovered.
    @discardableResult
    func attemptOnsideKick() -> Bool {
        guard onsideKickAvailable else { return false }
        pendingKickoff = nil
        let recovered = Double.random(in: 0..<1) < GameSimulator.onsideKickRecoveryChance
        if recovered {
            homeHasPossession = playerTeamIsHome
            driveStartYardLine = GameSimulator.onsideKickRecoveryYardLine
        } else {
            driveStartYardLine = GameSimulator.onsideKickFailStartYardLine
        }
        yardLine = driveStartYardLine
        down = 1
        distance = min(10, 100 - driveStartYardLine)
        currentDrivePlays = []
        moraleAppliedForCurrentDrive = false
        return recovered
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
