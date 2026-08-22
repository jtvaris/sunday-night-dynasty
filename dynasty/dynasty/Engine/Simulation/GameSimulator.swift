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
    // The two-minute warning now lives on `DriveSimulator.twoMinuteWarning`,
    // next to the clock loop that finally reads it. It sat here for the life of
    // the engine, declared and read by nothing, standing in for a stoppage that
    // was not modelled (F-40).

    // Kickoff constants (2024 dynamic-kickoff rule: touchbacks come out to the 30).
    static let kickoffTouchbackYardLine = 30
    private static let kickoffTouchbackChance = 0.55
    private static let kickoffReturnTouchdownChance = 0.02
    private static let kickoffReturnStartRange = 20...35

    // Onside kick constants. F-39 made the quick sim onside too, so this rate is
    // no longer a player-only number.
    //
    /// Recovery rate on an onside kick. Was 0.12 — roughly **twice** the real
    /// league figure, which ran 8.7 % across 2018-2023 and has fallen since the
    /// alignment rules tightened (4.23 % in 2023, 6.45 % in 2024). Lowered to
    /// 0.08 BEFORE giving the AI the capability, so the AI is not handed a
    /// mechanic that pays double what it should.
    ///
    /// Trades against: how often a trailing team steals a possession, and
    /// therefore comeback frequency. At 0.12 a two-score deficit inside two
    /// minutes was a live proposition; at 0.08 it is the long shot it is in
    /// reality, and the decision to try one costs field position ~92 % of the
    /// time.
    static let onsideKickRecoveryChance = 0.08
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

    /// Timeouts each club gets per half (F-39). The real number, and the reason
    /// it is per HALF rather than per game: an unused first-half timeout does not
    /// carry, so a trailing team's endgame budget is always three regardless of
    /// what it spent before the break.
    static let timeoutsPerHalf = 3

    /// Timeouts a club gets in overtime — two, not three. The real rule, and it
    /// matters here because the period is short enough that a third would let a
    /// trailing team stop the clock on almost every snap it faced.
    static let overtimeTimeouts = 2

    // Fatigue constants
    static let fatiguePerDriveStarter: Int = 3
    static let fatigueRecoveryBench: Int = 2
    private static let halftimeFatigueReduction: Double = 0.30

    // Morale constants
    private static let moodDependentPenalty: Double = 0.05
    private static let clutchQ4Multiplier: Double = 1.5
    private static let lowMoraleThreshold: Int = 40

    // Round 4 (mental states): drives an ego-prone star may go untouched before
    // his pressing folds into heat (§4). Mirrors the live engine's threshold.
    private static let egoFrustrationDrives = 3

    // MARK: - Simulate

    /// Runs a full game simulation between the home and away teams.
    ///
    /// The simulator manages drive-level possession alternation, quarter and clock
    /// management, momentum shifts, fatigue accumulation, morale/personality modifiers,
    /// and optional overtime. After the game concludes it compiles a ``BoxScore``,
    /// per-player ``PlayerGameStats``, and selects an MVP.
    ///
    /// - Parameters:
    ///   - prepFocusDelta: What the club at `prepTeamID` chose to do with its
    ///     week, as a signed shift on ``OpponentPrep``'s 0…1 focus scale
    ///     (−0.5 … +0.5, `0` = whatever its staff would have done anyway).
    ///     This is the ONLY caller-supplied half of opponent prep; the base
    ///     focus for all 32 clubs is derived below from the staff each one
    ///     already employs, so a club with no row is prepared, not absent.
    ///     See ``OpponentPrep`` for the magnitude argument and for what the
    ///     `×1.10` / `×0.925` post-game score edit this replaced was worth.
    ///   - prepTeamID: Which club that delta belongs to. `nil` = neither, which
    ///     is every AI-vs-AI game and every harness run.
    ///   - homeGamePlan: Optional coaching game plan applied to the HOME team's
    ///     offensive play-calling (run/pass mix, 4th-down aggressiveness).
    ///     Typically only the user's team gets a non-nil plan; F-17 fills `nil`
    ///     with the club head coach's ``HCPersona/gamePlan``, so an AI club now
    ///     brings its own 4th-down tolerance instead of the structural `nil`
    ///     that made `decidePlayCall`'s plan branches unreachable for all 31.
    ///   - awayGamePlan: Same, for the AWAY team.
    ///   - weather: Optional game weather (see ``GameWeather/forGame(id:week:)``).
    ///     The SAME condition is applied to both teams on every play, so the
    ///     effect is symmetric. `nil` = today's exact behavior (clear skies).
    ///   - homeRosterOverride: Exactly who dresses for the HOME team. `nil` =
    ///     today's exact behavior, the club's whole `currentRoster()`.
    ///     Passed by `PreseasonEngine` (#205b), where a coach's preseason
    ///     policy — rest the starters, a starter series, full tilt — IS the
    ///     decision about who suits up, and where an injured man genuinely does
    ///     not dress (the regular-season path leaves that simplification alone
    ///     rather than changing what a shipped season simulates).
    ///     The holdout filter below still applies on top of an override, so no
    ///     caller can accidentally dress a man who is refusing to report.
    ///   - awayRosterOverride: Same, for the AWAY team.
    static func simulate(
        homeTeam: Team,
        awayTeam: Team,
        homeCoaches: [Coach] = [],
        awayCoaches: [Coach] = [],
        prepFocusDelta: Double = 0,
        prepTeamID: UUID? = nil,
        homeGamePlan: GamePlan? = nil,
        awayGamePlan: GamePlan? = nil,
        weather: GameWeather? = nil,
        homeRosterOverride: [Player]? = nil,
        awayRosterOverride: [Player]? = nil
    ) -> GameResult {
        // -----------------------------------------------------------------
        // 1. Setup
        // -----------------------------------------------------------------
        // Snapshot both rosters into value types once. The play-by-play loop
        // reads attributes thousands of times, and every read of a SwiftData
        // @Model property is far too slow for that hot path. The live models
        // are kept in a lookup so fatigue can be written back after the sim.
        // R22: a player holding out over his contract does not suit up.
        // S3 (TRADE_OVERHAUL_PLAN §4/§7.5): the roster comes from the `teamID`
        // query, never `Team.players` — that relationship is a creation-time
        // snapshot, so a traded / signed / drafted / cut player used to suit up
        // for the wrong team here. Two fetches per GAME (this is the per-game
        // setup, outside the play-by-play loop).
        // #205b: `homeRosterOverride` / `awayRosterOverride` name exactly who
        // dresses. `nil` — every caller that existed before preseason — keeps
        // the `teamID` query as the only source of a roster.
        // F-18: `MedicalEngine.dressed` is the ONE definition of who suits up —
        // holdouts and the injured alike. This line used to filter holdouts
        // only, which is why an injured starter took every snap; see that
        // helper for the full chain and why the fix lives there.
        let homeRoster = MedicalEngine.dressed(homeRosterOverride ?? homeTeam.currentRoster())
        let awayRoster = MedicalEngine.dressed(awayRosterOverride ?? awayTeam.currentRoster())
        var homePlayers = homeRoster.map({ SimPlayer(from: $0) })
        var awayPlayers = awayRoster.map({ SimPlayer(from: $0) })
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

        // F-17: the head coach's persona fills the `gamePlan` slot for any club
        // the caller did not supply a plan for — i.e. every AI club, which until
        // now went into every game with `nil` and therefore could not reach
        // either of `decidePlayCall`'s two 4th-down plan branches. A caller-
        // supplied plan (the user's saved Game Plan) always wins: the persona is
        // the AI's substitute for a man at the Week Prep screen, not an override
        // of one.
        let homeHC = HCPersona.derive(
            headCoach: homeCoaches.first { $0.role == .headCoach }, teamID: homeTeam.id)
        let awayHC = HCPersona.derive(
            headCoach: awayCoaches.first { $0.role == .headCoach }, teamID: awayTeam.id)
        let homePlan = homeGamePlan ?? homeHC.gamePlan
        let awayPlan = awayGamePlan ?? awayHC.gamePlan

        // R40: coaching staffs turn into small, bounded efficiency nudges via
        // the shared `CoachingModifiers` helper — the identical path the live
        // engine uses, so quick sim and the 3D game never diverge. A team with
        // no coordinators produces neutral ratings, preserving the pre-R40
        // (coach-blind) behavior exactly. Computed once per game.
        let homeRatings = CoachingModifiers.ratings(from: homeCoaches)
        let awayRatings = CoachingModifiers.ratings(from: awayCoaches)
        // Per-possession offense edge (offense OC/plan/scheme vs the defending
        // DC/plan/scheme; discipline scales the offense's own flags/fumbles).
        let homeCoachAdj = CoachingModifiers.offenseAdjustments(offense: homeRatings, defense: awayRatings)
        let awayCoachAdj = CoachingModifiers.offenseAdjustments(offense: awayRatings, defense: homeRatings)

        // D1 / F-16 — OPPONENT PREP, threaded.
        //
        // This used to be §6b at the bottom of this function: a multiplier on
        // the FINAL SCORE, ×1.10 on the user's points and ×0.925 on the rival's,
        // worth +4.2 points of margin a game ≈ +2.1 wins a season, and only ever
        // the user's because `OpponentPrepWeek`'s single construction site
        // hard-codes the career's own club. It now composes into the SAME
        // `PlaySimulator.Adjustments` channel the coaching staff moves, at a
        // fifth of the size, for all 32 clubs. See ``OpponentPrep``.
        //
        // Both halves are here because prep is a contest between two staffs: a
        // club's own audible edge lifts its offense, and its defensive read
        // lands on the OTHER club's offense adjustments. Two average staffs
        // cancel to exactly zero, and a game with no coaches on either side —
        // every balance-harness roster — produces `nil` from both helpers and
        // therefore the identical pre-D1 numbers.
        let homeFocus = OpponentPrep.clampFocus(
            OpponentPrep.staffFocus(gamePlanning: homeRatings.gamePlanning)
                + (prepTeamID == homeTeam.id ? prepFocusDelta : 0))
        let awayFocus = OpponentPrep.clampFocus(
            OpponentPrep.staffFocus(gamePlanning: awayRatings.gamePlanning)
                + (prepTeamID == awayTeam.id ? prepFocusDelta : 0))
        let homeOffenseAdj = CoachingModifiers.combine(
            homeCoachAdj, prepAdjustments(own: homeFocus, opposing: awayFocus))
        let awayOffenseAdj = CoachingModifiers.combine(
            awayCoachAdj, prepAdjustments(own: awayFocus, opposing: homeFocus))
        // Pre-game morale: a strong staff (morale-influence + HC motivation)
        // lifts the room so fewer mood-dependent players dip under the penalty
        // line. Snapshot-only — the live @Model players are never touched.
        applyCoachMoraleBump(players: &homePlayers, bump: CoachingModifiers.moraleBump(homeRatings))
        applyCoachMoraleBump(players: &awayPlayers, bump: CoachingModifiers.moraleBump(awayRatings))

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

        // Layer A: per-game run-key state for each offense — threaded through
        // every drive so the defense's read of that offense's run tendency
        // persists across the whole game (AI-vs-AI box scores regress a run-
        // heavy offense to NFL-realistic rushing, same component as coached).
        var homeOffenseRunKey = AdaptiveOpponentAI.RunKeyState()
        var awayOffenseRunKey = AdaptiveOpponentAI.RunKeyState()

        // F-39: three timeouts a side, reset at the half exactly as the rules
        // say. Owned here because a timeout survives a change of possession and
        // `DriveSimulator` only ever sees one drive at a time.
        var homeTimeouts = timeoutsPerHalf
        var awayTimeouts = timeoutsPerHalf

        // Round 4 (mental states): per-game hot/cold FORM, the SAME `HeatState`
        // component the live engine runs — here fed coarsely, once per drive,
        // from the returned `PlayResult` stream (§1b). Threaded across the whole
        // game so a streak builds and decays, then written back to morale at the
        // whistle (§5). Empty ⇒ every stamped heat is 0 ⇒ parity.
        var gameHeat = HeatState()
        // Round 4 (§4): the cheap SIM ego analogue — drives since an ego-prone
        // star last had a touch. At the frustration threshold his pressing is
        // folded through the heat channel (no separate attribute path, no UI).
        var simEgoNoTouch: [UUID: Int] = [:]

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

            // Round 4 (mental states): STAMP the per-drive heat onto the snapshots
            // (absolute set, so it never compounds with the in-place morale
            // mutation above). The stamped copy rides into DriveSimulator by value.
            stampHeat(&homePlayers, from: gameHeat)
            stampHeat(&awayPlayers, from: gameHeat)

            let offensePlayers = homeHasPossession ? homePlayers : awayPlayers
            let defensePlayers = homeHasPossession ? awayPlayers : homePlayers

            // Simulate the drive via DriveSimulator (created in parallel)
            let offenseTeamID = homeHasPossession ? homeTeam.id : awayTeam.id
            // Layer A: pass the ball-carrier's run-key state as `inout`. Swift
            // can't take `&` of a ternary, so copy the value struct out, thread
            // it, and write it back — the read persists across drives.
            var driveRunKey = homeHasPossession ? homeOffenseRunKey : awayOffenseRunKey
            // F-39: the DEFENDING club's timeouts are the ones this drive can
            // spend. Same copy-thread-write-back shape as the run-key state above,
            // and for the same reason — Swift cannot take `&` of a ternary.
            var driveDefenseTimeouts = homeHasPossession ? awayTimeouts : homeTimeouts
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
                gamePlan: homeHasPossession ? homePlan : awayPlan,
                weather: weather,
                offenseIsAway: !homeHasPossession,
                adjustments: homeHasPossession ? homeOffenseAdj : awayOffenseAdj,
                // Round 4: offense-relative margin at drive start (running score,
                // before this drive's points) for the leverage index.
                scoreDifferential: homeHasPossession ? homeScore - awayScore : awayScore - homeScore,
                runKeyState: &driveRunKey,
                // F-17/F-39: the head coach with the ball is the one who has to
                // remember to take the knee.
                clockErrorRate: (homeHasPossession ? homeHC : awayHC).clockErrorRate,
                defenseTimeouts: &driveDefenseTimeouts
            )
            if homeHasPossession { homeOffenseRunKey = driveRunKey }
            else { awayOffenseRunKey = driveRunKey }
            if homeHasPossession { awayTimeouts = driveDefenseTimeouts }
            else { homeTimeouts = driveDefenseTimeouts }

            var drive = driveResult.drive
            quarter = driveResult.endQuarter
            timeRemaining = driveResult.endTime

            // Point-after try: a touchdown drive gets its untimed conversion
            // snap (XP or two — the shared chart decides) appended before the
            // drive is booked, so the try's points ride the same
            // drive-points bookkeeping as the six.
            if drive.result == .touchdown,
               let td = drive.plays.last, td.outcome == .touchdown {
                let offenseScoreAfterTD = (homeHasPossession ? homeScore : awayScore) + td.pointsScored
                let defenseScore = homeHasPossession ? awayScore : homeScore
                let tryPlay = rollPointAfterTry(
                    offensePlayers: offensePlayers,
                    defensePlayers: defensePlayers,
                    scoreDiffAfterTD: offenseScoreAfterTD - defenseScore,
                    quarter: quarter,
                    timeRemaining: timeRemaining,
                    playNumber: drive.plays.count + 1
                )
                drive.plays.append(tryPlay)
            }

            allDrives.append(drive)

            // Round 4 (mental states): fold this drive's PlayResult stream into
            // the shared HeatState (coarse per-drive sim feed, §1b), run the cheap
            // ego analogue for the offense that just possessed (§4), then decay
            // every player toward neutral at the drive boundary.
            feedDriveHeat(from: drive, offense: offensePlayers, defense: defensePlayers,
                          into: &gameHeat)
            let touchedThisDrive = Set(drive.plays.compactMap { $0.keyOffensePlayerID })
            for p in offensePlayers where p.isEgoProne {
                let eligible = !p.personalityArchetype.isFormImmune
                if touchedThisDrive.contains(p.id) {
                    let wasFrustrated = (simEgoNoTouch[p.id] ?? 0) >= egoFrustrationDrives
                    simEgoNoTouch[p.id] = 0
                    if wasFrustrated { gameHeat.reward(p.id, HeatState.winStep, scaleEligible: eligible) }
                } else {
                    let count = (simEgoNoTouch[p.id] ?? 0) + 1
                    simEgoNoTouch[p.id] = count
                    if count >= egoFrustrationDrives {
                        gameHeat.reward(p.id, -HeatState.egoFrustrationHeat, scaleEligible: eligible)
                    }
                }
            }
            gameHeat.decayAll(HeatState.decayPerDrive)

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

            // Collect highlights (extra points are scoring plays but not
            // highlight-reel material; two-point tries stay in).
            let driveHighlights = drive.plays.filter { play in
                (play.scoringPlay && play.playType != .extraPoint)
                    || play.isTurnover || play.yardsGained >= 20
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
                // F-39: timeouts do not carry across the half.
                homeTimeouts = timeoutsPerHalf
                awayTimeouts = timeoutsPerHalf
                // Home team receives second-half kickoff
                homeHasPossession = true
                startingYardLine = kickoffStartYardLine()
                continue
            }

            // -----------------------------------------------------------------
            // Next possession setup
            // -----------------------------------------------------------------
            let kickingTeamIsHome = homeHasPossession
            let nextPossessionInfo = determineNextPossession(
                afterDrive: drive,
                homeHasPossession: homeHasPossession
            )
            homeHasPossession = nextPossessionInfo.homeHasPossession
            startingYardLine = nextPossessionInfo.startingYardLine

            // F-39 ONSIDE KICK. The club that just scored and is STILL behind
            // late tries to keep the ball. Handled here rather than inside
            // `determineNextPossession` because that helper is shared with the
            // live engine and knows nothing about the score or the clock, and
            // teaching it both would couple two engines through a third concern.
            //
            // The failure to try is the persona's, not a coin flip: a `punter`
            // head coach kicks it deep and takes his chances on a stop about a
            // third of the time, which is a real and recognisable way to lose a
            // football game.
            var onsideAttempted = false
            if nextPossessionInfo.kickoff != nil, timeRemaining > 0 {
                let kickingHC = kickingTeamIsHome ? homeHC : awayHC
                let kickingMargin = kickingTeamIsHome ? homeScore - awayScore : awayScore - homeScore
                if shouldAttemptOnside(margin: kickingMargin, quarter: quarter,
                                       timeRemaining: timeRemaining),
                   Double.random(in: 0..<1) >= kickingHC.clockErrorRate {
                    onsideAttempted = true
                    if Double.random(in: 0..<1) < onsideKickRecoveryChance {
                        homeHasPossession = kickingTeamIsHome
                        startingYardLine = onsideKickRecoveryYardLine
                    } else {
                        homeHasPossession = !kickingTeamIsHome
                        startingYardLine = onsideKickFailStartYardLine
                    }
                }
            }

            // -----------------------------------------------------------------
            // Kickoff return touchdown (~2% of post-score kicks): the receiving
            // team houses it. Only while the half is still alive — a kick can't
            // happen after the clock has expired.
            // -----------------------------------------------------------------
            // An onside kick that has already been resolved cannot also be housed
            // by the deep-return draw, hence the `!onsideAttempted` guard.
            if let kick = nextPossessionInfo.kickoff, kick.isReturnTouchdown,
               timeRemaining > 0, !onsideAttempted {
                driveNumber += 1
                let returnTeamIsHome = homeHasPossession
                let returnPlay = kickoffReturnTouchdownPlay(
                    quarter: quarter,
                    timeRemaining: timeRemaining
                )
                var returnDrive = DriveResult(
                    driveNumber: driveNumber,
                    teamID: returnTeamIsHome ? homeTeam.id : awayTeam.id,
                    startingYardLine: kick.startingYardLine,
                    plays: [returnPlay],
                    result: .touchdown
                )
                // The housed return earns its point-after try too.
                let returnScoreAfterTD = (returnTeamIsHome ? homeScore : awayScore) + returnPlay.pointsScored
                let returnDefScore = returnTeamIsHome ? awayScore : homeScore
                let returnTry = rollPointAfterTry(
                    offensePlayers: returnTeamIsHome ? homePlayers : awayPlayers,
                    defensePlayers: returnTeamIsHome ? awayPlayers : homePlayers,
                    scoreDiffAfterTD: returnScoreAfterTD - returnDefScore,
                    quarter: quarter,
                    timeRemaining: timeRemaining,
                    playNumber: 2
                )
                returnDrive.plays.append(returnTry)
                allDrives.append(returnDrive)
                allHighlights.append(returnPlay)

                let returnPoints = returnDrive.plays.reduce(0) { $0 + $1.pointsScored }
                let qi = min(quarter - 1, 3)
                if returnTeamIsHome {
                    homeScore += returnPoints
                    homeQuarterScores[qi] += returnPoints
                } else {
                    awayScore += returnPoints
                    awayQuarterScores[qi] += returnPoints
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
        // Overtime needs no flag of its own: the fifth `quarterScores` entry
        // appended here IS the record of it (`BoxScore.quarterScores`).
        if homeScore == awayScore {
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
                homeGamePlan: homePlan,
                awayGamePlan: awayPlan,
                weather: weather,
                homeOffenseAdj: homeOffenseAdj,
                awayOffenseAdj: awayOffenseAdj,
                homeScoreAtRegulation: homeScore,
                awayScoreAtRegulation: awayScore,
                homeClockErrorRate: homeHC.clockErrorRate,
                awayClockErrorRate: awayHC.clockErrorRate
            )
            homeScore += otResult.homeOTPoints
            awayScore += otResult.awayOTPoints
            homeQuarterScores[4] = otResult.homeOTPoints
            awayQuarterScores[4] = otResult.awayOTPoints
        }

        // §6b — the opponent-prep score multiplier — is DELETED, not moved.
        // It ran here, after the whistle, editing the scoreboard: see the prep
        // block in section 1 for what replaced it and why.

        // -----------------------------------------------------------------
        // 6c. Round 4 (§5): end-of-game heat → morale write-back
        // -----------------------------------------------------------------
        // Reuses the exact `livePlayerByID` seam the fatigue write-back uses
        // (both teams). A hot game (heat ≥ +0.5) nudges morale +2, a cold one
        // (≤ −0.5) −2, clamped 1…100. No schema change — `Player.morale` is
        // already persisted. Mostly a no-op (heat sits near 0), a small,
        // thematically-correct streak echo when a player ran hot or cold.
        for roster in [homePlayers, awayPlayers] {
            for sp in roster {
                guard let live = livePlayerByID[sp.id] else { continue }
                let h = gameHeat.value(sp.id)
                if h >= HeatState.hotThreshold {
                    live.morale = max(1, min(100, live.morale + HeatState.moraleNudge))
                } else if h <= HeatState.coldThreshold {
                    live.morale = max(1, min(100, live.morale - HeatState.moraleNudge))
                }
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
        // S3: rosters by `teamID`, not `Team.players` (see the `Team.players`
        // doc). This league only lives in memory, so the index is built once
        // from the generation result instead of a context fetch.
        let homeRoster = generated.players.filter { $0.teamID == home.id }
        let awayRoster = generated.players.filter { $0.teamID == away.id }

        func stats(_ values: [Double]) -> (mean: Double, std: Double, min: Double, max: Double) {
            guard !values.isEmpty else { return (0, 0, 0, 0) }
            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            return (mean, variance.squareRoot(), values.min() ?? 0, values.max() ?? 0)
        }

        /// One measurement pass over the SAME two rosters. R36 runs it twice
        /// — awareness targeting off, then on — for a paired comparison
        /// (league generation is unseeded, so separate launches don't compare).
        func measure(label: String, fatiguePreload: Int? = nil) {
            var points: [Double] = []
            var yards: [Double] = []
            var penaltiesPerGame: [Double] = []
            var sacksPerGame: [Double] = []
            var turnoversPerGame: [Double] = []
            var margins: [Double] = []
            var completions = 0
            var attempts = 0
            for _ in 0..<n {
                // R38 fatigue gate: preload every player to a tired baseline so
                // the fatigue mechanic (only bites above 70) actually fires —
                // fresh generated leagues never cross the threshold in one game.
                if let f = fatiguePreload {
                    for p in homeRoster { p.fatigue = f }
                    for p in awayRoster { p.fatigue = f }
                }
                let result = simulate(homeTeam: home, awayTeam: away)
                points.append(Double(result.homeScore))
                points.append(Double(result.awayScore))
                yards.append(Double(result.boxScore.home.totalYards))
                yards.append(Double(result.boxScore.away.totalYards))
                penaltiesPerGame.append(Double(result.boxScore.home.penalties + result.boxScore.away.penalties))
                sacksPerGame.append(Double(result.boxScore.home.sacks + result.boxScore.away.sacks))
                turnoversPerGame.append(Double(result.boxScore.home.turnovers + result.boxScore.away.turnovers))
                margins.append(Double(abs(result.homeScore - result.awayScore)))
                for stats in result.playerStats {
                    completions += stats.completions
                    attempts += stats.attempts
                }
            }
            let p = stats(points)
            let y = stats(yards)
            let pen = stats(penaltiesPerGame)
            let sck = stats(sacksPerGame)
            let tos = stats(turnoversPerGame)
            let m = stats(margins)
            print(String(format: "DEBUG-SIM[%@]: games=%d", label, n))
            print(String(format: "DEBUG-SIM[%@]: points/team mean=%.1f std=%.1f min=%.0f max=%.0f", label, p.mean, p.std, p.min, p.max))
            print(String(format: "DEBUG-SIM[%@]: yards/team  mean=%.0f std=%.0f min=%.0f max=%.0f", label, y.mean, y.std, y.min, y.max))
            print(String(format: "DEBUG-SIM[%@]: penalties/game mean=%.1f sacks/game mean=%.1f turnovers/game mean=%.2f", label, pen.mean, sck.mean, tos.mean))
            print(String(format: "DEBUG-SIM[%@]: score margin mean=%.1f", label, m.mean))
            let completionPct = attempts > 0 ? Double(completions) / Double(attempts) * 100 : 0
            print(String(format: "DEBUG-SIM[%@]: completion%%  %.1f (%d/%d)", label, completionPct, completions, attempts))
        }

        // R37 gate: each player-IQ mechanic measured in isolation over the
        // SAME league (paired). "pre" = shipped pre-R37 behavior (R36
        // awareness targeting stays ON throughout — it shipped already).
        func setNeutral(vision: Bool, security: Bool, intCredit: Bool) {
            PlaySimulator.debugNeutralCarrierVision = vision
            PlaySimulator.debugNeutralBallSecurity = security
            PlaySimulator.debugNeutralINTCredit = intCredit
        }
        setNeutral(vision: true, security: true, intCredit: true)
        measure(label: "pre")
        setNeutral(vision: false, security: true, intCredit: true)
        measure(label: "vision")
        setNeutral(vision: true, security: false, intCredit: true)
        measure(label: "security")
        setNeutral(vision: true, security: true, intCredit: false)
        measure(label: "intcredit")
        setNeutral(vision: false, security: false, intCredit: false)
        measure(label: "all-on")

        // R37 play-action micro-harness: PA never occurs in the quick sim
        // (it needs an explicit live call), so its gate is measured directly:
        // repeated 1st-and-10 playActionDeep snaps, bite roll OFF vs ON,
        // same two rosters. The relative effect must stay inside ±10%.
        let paOffense = homeRoster.filter { !$0.isHoldingOut }.map({ SimPlayer(from: $0) })
        let paDefense = awayRoster.filter { !$0.isHoldingOut }.map({ SimPlayer(from: $0) })
        func measurePlayAction(label: String, snaps: Int = 4000) {
            var totalYards = 0
            var completions = 0
            var attempts = 0
            for _ in 0..<snaps {
                let play = PlaySimulator.simulatePlay(
                    offensePlayers: paOffense,
                    defensePlayers: paDefense,
                    down: 1, distance: 10, yardLine: 35,
                    quarter: 2, timeRemaining: 600,
                    momentum: 0, playNumber: 1,
                    offensiveCall: .playActionDeep
                )
                switch play.outcome {
                case .completion, .touchdown:
                    completions += 1; attempts += 1; totalYards += play.yardsGained
                case .incompletion, .interception:
                    attempts += 1
                default:
                    break // sacks/penalties: not a thrown ball
                }
            }
            let compPct = attempts > 0 ? Double(completions) / Double(attempts) * 100 : 0
            let avgYards = Double(totalYards) / Double(snaps)
            print(String(format: "DEBUG-SIM[PA-%@]: snaps=%d comp%%=%.1f yards/snap=%.2f",
                         label, snaps, compPct, avgYards))
        }
        PlaySimulator.debugNeutralPlayActionRead = true
        measurePlayAction(label: "off")
        PlaySimulator.debugNeutralPlayActionRead = false
        measurePlayAction(label: "on")

        // -----------------------------------------------------------------
        // R38 attribute-gap gate: each mechanic isolated over the SAME league
        // (paired). R37 mechanics stay ON (shipped). Baseline "r38-pre" has
        // every R38 mechanic neutralized; each pass toggles exactly one.
        // -----------------------------------------------------------------
        func setR38(fatigue: Bool, qbMob: Bool, arm: Bool, wrPress: Bool,
                    contested: Bool, homeAway: Bool) {
            PlaySimulator.debugNeutralFatiguePerf = fatigue
            PlaySimulator.debugNeutralQBMobilitySack = qbMob
            PlaySimulator.debugNeutralArmStrength = arm
            PlaySimulator.debugNeutralWRPress = wrPress
            PlaySimulator.debugNeutralContestedDrop = contested
            PlaySimulator.debugNeutralHomeAwayPenalty = homeAway
        }
        // Keep R37 mechanics ON (shipped) throughout the R38 gate.
        setNeutral(vision: false, security: false, intCredit: false)

        setR38(fatigue: true, qbMob: true, arm: true, wrPress: true, contested: true, homeAway: true)
        measure(label: "r38-pre")
        setR38(fatigue: true, qbMob: false, arm: true, wrPress: true, contested: true, homeAway: true)
        measure(label: "qbmob")          // mech 2: QB mobility → sacks
        setR38(fatigue: true, qbMob: true, arm: false, wrPress: true, contested: true, homeAway: true)
        measure(label: "arm")            // mech 3: arm strength → deep accuracy
        setR38(fatigue: true, qbMob: true, arm: true, wrPress: true, contested: false, homeAway: true)
        measure(label: "contested")      // mech 5: contested / drop
        setR38(fatigue: true, qbMob: true, arm: true, wrPress: true, contested: true, homeAway: false)
        measure(label: "homeaway")       // mech 6: penalties/game must match r38-pre

        // Mech 1: fatigue → performance. Preload every player to 80 so the
        // above-70 penalty actually fires; both teams tire symmetrically.
        setR38(fatigue: true, qbMob: true, arm: true, wrPress: true, contested: true, homeAway: true)
        measure(label: "fatigue-off", fatiguePreload: 80)
        setR38(fatigue: false, qbMob: true, arm: true, wrPress: true, contested: true, homeAway: true)
        measure(label: "fatigue-on", fatiguePreload: 80)

        // Everything on together (realism sanity check).
        setR38(fatigue: false, qbMob: false, arm: false, wrPress: false, contested: false, homeAway: false)
        measure(label: "r38-all")

        // -----------------------------------------------------------------
        // #36B mental-game gate: composure is the ONLY mental mechanic on the
        // shared quick-sim path (hot-streak (mech 1) and ego (mech 2) are
        // live-only — they never fire in this AI-vs-AI quick sim). Paired,
        // all R38 mechanics ON, composure OFF then ON. Gate: points ±1.5 /
        // comp% ±2 / sacks ±1 / TO ±0.4 — the Q4/red-zone accuracy sag on
        // low-composure QBs must not move the league aggregate.
        // -----------------------------------------------------------------
        PlaySimulator.debugNeutralComposure = true
        measure(label: "composure-off")
        PlaySimulator.debugNeutralComposure = false
        measure(label: "composure-on")

        // Mech 4: WR release vs DB press — live-only (needs a man-press
        // package, which the quick sim never sends), so measured directly:
        // repeated SHORT snaps vs a Man-Press look, off vs on. Near-zero mean.
        let pressOffense = homeRoster.filter { !$0.isHoldingOut }.map({ SimPlayer(from: $0) })
        let pressDefense = awayRoster.filter { !$0.isHoldingOut }.map({ SimPlayer(from: $0) })
        let manPress = DefensiveCall.manPress.package
        func measurePress(label: String, snaps: Int = 6000) {
            var completions = 0
            var attempts = 0
            for _ in 0..<snaps {
                let play = PlaySimulator.simulatePlay(
                    offensePlayers: pressOffense,
                    defensePlayers: pressDefense,
                    down: 1, distance: 10, yardLine: 35,
                    quarter: 2, timeRemaining: 600,
                    momentum: 0, playNumber: 1,
                    offensiveCall: .slant,           // short pass
                    defensivePackage: manPress
                )
                switch play.outcome {
                case .completion, .touchdown: completions += 1; attempts += 1
                case .incompletion, .interception: attempts += 1
                default: break
                }
            }
            let compPct = attempts > 0 ? Double(completions) / Double(attempts) * 100 : 0
            print(String(format: "DEBUG-SIM[PRESS-%@]: snaps=%d comp%%=%.1f", label, snaps, compPct))
        }
        setR38(fatigue: true, qbMob: true, arm: true, wrPress: true, contested: true, homeAway: true)
        measurePress(label: "off")
        setR38(fatigue: true, qbMob: true, arm: true, wrPress: false, contested: true, homeAway: true)
        measurePress(label: "on")

        // Restore all R38 mechanics to their shipped (active) state.
        setR38(fatigue: false, qbMob: false, arm: false, wrPress: false, contested: false, homeAway: false)

        // -----------------------------------------------------------------
        // R39 attribute-gap gate: each ATTRIBUTE isolated over the SAME league
        // (paired). All R37/R38/#36B mechanics stay ON (shipped). Baseline
        // "r39-pre" neutralizes every R39 attribute; each pass activates one.
        // Gate: points ±1.5 / comp% ±2 / sacks ±1 / TO ±0.4. The live-only
        // sub-connections (accel release 1b, strength press-jam 2c) fire only
        // vs a man-press package, so they are measured with the PRESS
        // micro-harness below, not the AI-vs-AI quick sim.
        // -----------------------------------------------------------------
        func setR39(accel: Bool, strength: Bool, agility: Bool, decision: Bool) {
            PlaySimulator.debugNeutralAcceleration = accel
            PlaySimulator.debugNeutralStrength = strength
            PlaySimulator.debugNeutralAgility = agility
            PlaySimulator.debugNeutralDecision = decision
        }
        setR39(accel: true, strength: true, agility: true, decision: true)
        measure(label: "r39-pre")
        setR39(accel: false, strength: true, agility: true, decision: true)
        measure(label: "r39-accel")    // mech 1a DL pass rush + 1c RB run burst
        setR39(accel: true, strength: false, agility: true, decision: true)
        measure(label: "r39-strength") // mech 2a trench + 2b break-tackle
        setR39(accel: true, strength: true, agility: false, decision: true)
        measure(label: "r39-agility")  // mech 3 RB juke + WR separation
        setR39(accel: true, strength: true, agility: true, decision: false)
        measure(label: "r39-decision") // mech 4 turnover risk + reading swap
        setR39(accel: false, strength: false, agility: false, decision: false)
        measure(label: "r39-all")

        // R39 live-only press micro-harness: accel release (1b) + strength
        // press-jam (2c) fire only vs man-press. Paired off vs on; near-zero
        // mean, so comp% must barely move. R38 wrPress stays active throughout.
        setR39(accel: true, strength: true, agility: true, decision: true)
        measurePress(label: "r39off")
        setR39(accel: false, strength: true, agility: true, decision: true)
        measurePress(label: "r39accelrel")  // mech 1b
        setR39(accel: true, strength: false, agility: true, decision: true)
        measurePress(label: "r39strjam")    // mech 2c

        // Restore R39 to shipped (active) state.
        setR39(accel: false, strength: false, agility: false, decision: false)

        // -----------------------------------------------------------------
        // R40 coaching-gap gate: each COACH mechanic isolated over the SAME
        // league (paired), all prior mechanics ON (shipped). Unlike the player
        // gates, coach effects need coaches — so a STRONG home staff plays a
        // WEAK away staff. That asymmetry is intentional: the aggregate points/
        // comp%/sacks/TO (over BOTH teams) must hold (roughly zero-sum), while
        // the home win% and signed margin RISE — the "better-coached team wins
        // a little more" signal. Baseline "r40-pre" neutralizes all six coach
        // mechanics (identical to today's coach-blind sim); each pass turns on
        // exactly one. Gate: points ±1.5 / comp% ±2 / sacks ±1 / TO ±0.4.
        // -----------------------------------------------------------------
        func makeStaff(strong: Bool) -> [Coach] {
            let g = strong
            let hc = Coach(firstName: "H", lastName: g ? "Strong" : "Weak", age: 50,
                           role: .headCoach,
                           gamePlanning: g ? 88 : 55,
                           motivation: g ? 90 : 55,
                           discipline: g ? 90 : 55,
                           moraleInfluence: g ? 88 : 55)
            let oc = Coach(firstName: "O", lastName: g ? "Strong" : "Weak", age: 45,
                           role: .offensiveCoordinator,
                           offensiveScheme: .westCoast,
                           playCalling: g ? 90 : 56,
                           adaptability: g ? 84 : 58,
                           gamePlanning: g ? 84 : 55)
            oc.schemeExpertise = [OffensiveScheme.westCoast.rawValue: g ? 94 : 55]
            let dc = Coach(firstName: "D", lastName: g ? "Strong" : "Weak", age: 45,
                           role: .defensiveCoordinator,
                           defensiveScheme: .pressMan,
                           playCalling: g ? 88 : 56,
                           adaptability: g ? 82 : 58,
                           gamePlanning: g ? 82 : 55)
            dc.schemeExpertise = [DefensiveScheme.pressMan.rawValue: g ? 92 : 55]
            return [hc, oc, dc]
        }
        let strongStaff = makeStaff(strong: true)
        let weakStaff = makeStaff(strong: false)

        func setR40(coord: Bool, plan: Bool, scheme: Bool, disc: Bool, morale: Bool, motiv: Bool) {
            CoachingModifiers.debugNeutralCoordinator = coord
            CoachingModifiers.debugNeutralGamePlanning = plan
            CoachingModifiers.debugNeutralSchemeExpertise = scheme
            CoachingModifiers.debugNeutralDiscipline = disc
            CoachingModifiers.debugNeutralMoraleInfluence = morale
            CoachingModifiers.debugNeutralMotivation = motiv
        }

        func measureCoach(label: String) {
            var points: [Double] = []
            var penaltiesPerGame: [Double] = []
            var sacksPerGame: [Double] = []
            var turnoversPerGame: [Double] = []
            var completions = 0
            var attempts = 0
            var homeWins = 0
            var signedMargin = 0.0
            for _ in 0..<n {
                let result = simulate(homeTeam: home, awayTeam: away,
                                      homeCoaches: strongStaff, awayCoaches: weakStaff)
                points.append(Double(result.homeScore))
                points.append(Double(result.awayScore))
                penaltiesPerGame.append(Double(result.boxScore.home.penalties + result.boxScore.away.penalties))
                sacksPerGame.append(Double(result.boxScore.home.sacks + result.boxScore.away.sacks))
                turnoversPerGame.append(Double(result.boxScore.home.turnovers + result.boxScore.away.turnovers))
                if result.homeScore > result.awayScore { homeWins += 1 }
                signedMargin += Double(result.homeScore - result.awayScore)
                for s in result.playerStats { completions += s.completions; attempts += s.attempts }
            }
            let p = stats(points)
            let pen = stats(penaltiesPerGame)
            let sck = stats(sacksPerGame)
            let tos = stats(turnoversPerGame)
            let compPct = attempts > 0 ? Double(completions) / Double(attempts) * 100 : 0
            print(String(format: "DEBUG-SIM[%@]: points/team mean=%.1f | comp%%=%.1f | sacks/g=%.1f | TO/g=%.2f | pen/g=%.1f | HOMEwin%%=%.0f margin=%+.1f",
                         label, p.mean, compPct, sck.mean, tos.mean, pen.mean,
                         Double(homeWins) / Double(n) * 100, signedMargin / Double(n)))
        }

        setR40(coord: true, plan: true, scheme: true, disc: true, morale: true, motiv: true)
        measureCoach(label: "r40-pre")
        setR40(coord: false, plan: true, scheme: true, disc: true, morale: true, motiv: true)
        measureCoach(label: "r40-coord")   // mech 1 OC/DC completion+run
        setR40(coord: true, plan: false, scheme: true, disc: true, morale: true, motiv: true)
        measureCoach(label: "r40-plan")    // mech 2 game planning
        setR40(coord: true, plan: true, scheme: false, disc: true, morale: true, motiv: true)
        measureCoach(label: "r40-scheme")  // mech 6 scheme expertise
        setR40(coord: true, plan: true, scheme: true, disc: false, morale: true, motiv: true)
        measureCoach(label: "r40-disc")    // mech 4 discipline penalties/fumbles
        setR40(coord: true, plan: true, scheme: true, disc: true, morale: false, motiv: true)
        measureCoach(label: "r40-morale")  // mech 3 morale influence
        setR40(coord: true, plan: true, scheme: true, disc: true, morale: true, motiv: false)
        measureCoach(label: "r40-motiv")   // mech 5 HC motivation
        setR40(coord: false, plan: false, scheme: false, disc: false, morale: false, motiv: false)
        measureCoach(label: "r40-all")

        // Restore R40 to shipped (active) state.
        setR40(coord: false, plan: false, scheme: false, disc: false, morale: false, motiv: false)

        // -----------------------------------------------------------------
        // R41 scheme-familiarity gate: the DIRECT (fit-independent) "% learned"
        // term. Both teams run identical mid staff (westCoast/pressMan) with
        // ALL coach mechanics neutralized, so the ONLY difference is how well
        // each squad has learned the playbook: HOME = well-drilled (95%),
        // AWAY = still learning (40%). Turning the term ON must let the drilled
        // team out-gain / out-score the learners (HOMEwin% & margin RISE) while
        // the AGGREGATE over both teams holds (points ±1.5 / comp% ±2 /
        // sacks ±1 / TO ±0.4). This also proves familiarity now bites at a
        // neutral scheme fit, not only through the fit deviation.
        setR40(coord: true, plan: true, scheme: true, disc: true, morale: true, motiv: true)
        let midStaff = makeStaff(strong: false)
        func setSchemeFam(_ roster: [Player], off: Int, def: Int) {
            for p in roster {
                p.schemeFamiliarity[OffensiveScheme.westCoast.rawValue] = off
                p.schemeFamiliarity[DefensiveScheme.pressMan.rawValue] = def
            }
        }
        setSchemeFam(homeRoster, off: 95, def: 95)
        setSchemeFam(awayRoster, off: 40, def: 40)

        func measureFam(label: String) {
            var homePts: [Double] = []
            var awayPts: [Double] = []
            var allPts: [Double] = []
            var homeYds: [Double] = []
            var awayYds: [Double] = []
            var sacksPerGame: [Double] = []
            var turnoversPerGame: [Double] = []
            var completions = 0
            var attempts = 0
            var homeWins = 0
            var signedMargin = 0.0
            for _ in 0..<n {
                let r = simulate(homeTeam: home, awayTeam: away,
                                 homeCoaches: midStaff, awayCoaches: midStaff)
                homePts.append(Double(r.homeScore)); awayPts.append(Double(r.awayScore))
                allPts.append(Double(r.homeScore)); allPts.append(Double(r.awayScore))
                homeYds.append(Double(r.boxScore.home.totalYards))
                awayYds.append(Double(r.boxScore.away.totalYards))
                sacksPerGame.append(Double(r.boxScore.home.sacks + r.boxScore.away.sacks))
                turnoversPerGame.append(Double(r.boxScore.home.turnovers + r.boxScore.away.turnovers))
                if r.homeScore > r.awayScore { homeWins += 1 }
                signedMargin += Double(r.homeScore - r.awayScore)
                for s in r.playerStats { completions += s.completions; attempts += s.attempts }
            }
            let compPct = attempts > 0 ? Double(completions) / Double(attempts) * 100 : 0
            print(String(format: "DEBUG-SIM[%@]: HI-pts=%.1f LO-pts=%.1f AGG-pts=%.1f | HI-yds=%.0f LO-yds=%.0f | comp%%=%.1f | sacks/g=%.1f | TO/g=%.2f | HOMEwin%%=%.0f margin=%+.1f",
                         label,
                         stats(homePts).mean, stats(awayPts).mean, stats(allPts).mean,
                         stats(homeYds).mean, stats(awayYds).mean,
                         compPct, stats(sacksPerGame).mean, stats(turnoversPerGame).mean,
                         Double(homeWins) / Double(n) * 100, signedMargin / Double(n)))
        }
        PlaySimulator.debugNeutralSchemeFamiliarity = true
        measureFam(label: "r41-off")
        PlaySimulator.debugNeutralSchemeFamiliarity = false
        measureFam(label: "r41-on")
        // Restore shipped state + coach mechanics.
        PlaySimulator.debugNeutralSchemeFamiliarity = false
        setR40(coord: false, plan: false, scheme: false, disc: false, morale: false, motiv: false)

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
        weather: GameWeather? = nil,
        homeOffenseAdj: PlaySimulator.Adjustments? = nil,
        awayOffenseAdj: PlaySimulator.Adjustments? = nil,
        // F-43: the score at the end of regulation. Overtime called
        // `simulateDrive` with no `scoreDifferential` at all, so every
        // game-management branch in `decidePlayCall` — the mgmt pass bias, the
        // two-minute gate, the 4th-down late-lead return — and `leverageIndex`'s
        // trailing term were ALL inert for the whole period. A team that had just
        // conceded a field goal on the opening possession played the next drive
        // as though the game were still tied, which is the one situation in
        // football where the margin decides literally every call.
        homeScoreAtRegulation: Int = 0,
        awayScoreAtRegulation: Int = 0,
        // F-17/F-39: the two head coaches' clock-error rates, so the victory
        // formation is available in overtime too.
        homeClockErrorRate: Double = 0,
        awayClockErrorRate: Double = 0
    ) -> OvertimeResult {
        var homeOTPoints = 0
        var awayOTPoints = 0
        var otTimeRemaining = overtimeDuration
        var homeHasPossession = Bool.random() // coin toss
        var firstPossessionComplete = false
        var secondPossessionComplete = false
        var startingYardLine = kickoffStartYardLine() // OT kickoff draw

        // Layer A: run-key state per offense for the overtime period.
        var homeOffenseRunKey = AdaptiveOpponentAI.RunKeyState()
        var awayOffenseRunKey = AdaptiveOpponentAI.RunKeyState()
        // F-39: overtime gets its own two timeouts a side (the real rule), not a
        // third full set.
        var homeOTTimeouts = overtimeTimeouts
        var awayOTTimeouts = overtimeTimeouts

        while otTimeRemaining > 0 {
            driveNumber += 1

            let offensePlayers = homeHasPossession ? homePlayers : awayPlayers
            let defensePlayers = homeHasPossession ? awayPlayers : homePlayers

            let otOffenseTeamID = homeHasPossession ? homeTeam.id : awayTeam.id
            var driveRunKey = homeHasPossession ? homeOffenseRunKey : awayOffenseRunKey
            // F-39: a fresh set of timeouts for the overtime period, per the rules.
            var driveDefenseTimeouts = homeHasPossession ? awayOTTimeouts : homeOTTimeouts
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
                weather: weather,
                offenseIsAway: !homeHasPossession,
                adjustments: homeHasPossession ? homeOffenseAdj : awayOffenseAdj,
                // F-43: the LIVE margin, recomputed each drive from the
                // regulation score plus whatever overtime has already produced.
                scoreDifferential: homeHasPossession
                    ? (homeScoreAtRegulation + homeOTPoints) - (awayScoreAtRegulation + awayOTPoints)
                    : (awayScoreAtRegulation + awayOTPoints) - (homeScoreAtRegulation + homeOTPoints),
                runKeyState: &driveRunKey,
                clockErrorRate: homeHasPossession ? homeClockErrorRate : awayClockErrorRate,
                defenseTimeouts: &driveDefenseTimeouts
            )
            if homeHasPossession { homeOffenseRunKey = driveRunKey }
            else { awayOffenseRunKey = driveRunKey }
            if homeHasPossession { awayOTTimeouts = driveDefenseTimeouts }
            else { homeOTTimeouts = driveDefenseTimeouts }

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

    /// F-39: whether the club that just scored should try to keep the ball.
    ///
    /// The quick sim never onsided — the constant's own comment said so — which
    /// meant a trailing AI down 5 with 0:40 left ALWAYS kicked deep and handed
    /// the game over. This is the real decision rule and nothing more: a
    /// one-possession deficit inside two minutes, or any deficit at all once
    /// there is no time to get a stop and a drive.
    ///
    /// - Parameter margin: the KICKING team's score margin, after its own score.
    ///   Negative means it is still behind, which is the only case that matters.
    static func shouldAttemptOnside(margin: Int, quarter: Int, timeRemaining: Int) -> Bool {
        guard quarter >= 4, margin < 0 else { return false }
        if timeRemaining <= 30 { return true }
        return timeRemaining <= 120 && margin >= -8
    }

    /// Synthetic play describing a kickoff returned for a touchdown. Return
    /// yards are intentionally NOT counted as offensive yards (yardsGained 0)
    /// so team total-yardage stays a scrimmage stat. The TD is worth 6; the
    /// point-after try is rolled separately by the caller (``rollPointAfterTry``).
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

    // MARK: - Point-After Try (XP / two-point conversion)

    /// Shared two-point decision chart (quick-sim AI, live AI, and both
    /// teams in fully simulated finishes). Kick the extra point for three
    /// quarters; from late in the game on, go for two when the score
    /// difference AFTER the touchdown's six points is one the classic
    /// analytics chart converts — down 2 (tie it), down 5 (one FG game),
    /// down 8/16 (one/two-score game with the 2), down 11/13, up 1 (make it
    /// a field-goal-proof +3), up 5 (+7).
    static func shouldGoForTwo(scoreDiffAfterTD: Int, quarter: Int, timeRemaining: Int) -> Bool {
        let lateGame = quarter >= 4 || (quarter == 3 && timeRemaining <= 120)
        guard lateGame else { return false }
        switch scoreDiffAfterTD {
        case -16, -13, -11, -8, -5, -2, 1, 5: return true
        default: return false
        }
    }

    /// Rolls the untimed try after a touchdown: the shared chart picks kick
    /// vs two (unless `forceTwoPoint` overrides it — the live player's own
    /// choice), then the shared play simulators resolve the attempt. Used by
    /// the quick sim and `LiveGameEngine` so both paths stay statistically
    /// identical; call/package biases only ever arrive from live games.
    static func rollPointAfterTry(
        offensePlayers: [SimPlayer],
        defensePlayers: [SimPlayer],
        scoreDiffAfterTD: Int,
        quarter: Int,
        timeRemaining: Int,
        playNumber: Int,
        forceTwoPoint: Bool? = nil,
        offensiveCall: OffensivePlayCall? = nil,
        defensivePackage: DefensivePackage? = nil
    ) -> PlayResult {
        let goForTwo = forceTwoPoint ?? shouldGoForTwo(
            scoreDiffAfterTD: scoreDiffAfterTD,
            quarter: quarter,
            timeRemaining: timeRemaining
        )
        var play: PlayResult
        if goForTwo {
            play = PlaySimulator.simulateTwoPointConversion(
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                quarter: quarter,
                timeRemaining: max(timeRemaining, 0),
                playNumber: playNumber,
                offensiveCall: offensiveCall,
                defensivePackage: defensivePackage
            )
        } else {
            play = PlaySimulator.simulateExtraPoint(
                offensePlayers: offensePlayers,
                quarter: quarter,
                timeRemaining: max(timeRemaining, 0),
                yardLine: 98,
                playNumber: playNumber
            )
        }
        play.quarter = quarter
        play.timeRemaining = max(timeRemaining, 0)
        return play
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
            // F-41. Two defects met here, and the second is the worse one.
            //
            // (1) `PlaySimulator.simulatePunt` resolves a real punt with a real
            // net distance, and this site threw it away and substituted a flat
            // `averagePuntDistance = 40` — so every punt in every quick-sim game
            // was worth exactly 40 yards of field position no matter who kicked
            // it or what the play said happened. Punter rating could not matter
            // because the number it produced was discarded one function later.
            //
            // (2) The old floor was `max(opponentYardLine, touchbackYardLine)`,
            // which handed the receiving team the 25 as a MINIMUM. A punt could
            // therefore never pin anyone inside their own 25 — the entire point
            // of a good punt, and the reason field position is a phase of the
            // game. The touchback floor now applies only when the play actually
            // was a touchback, which is a state the punt already reports.
            let lastPlay = drive.plays.last
            let puntFrom = lastPlay?.yardLine ?? 30
            if lastPlay?.outcome == .touchback {
                return NextPossession(
                    homeHasPossession: switchPossession,
                    startingYardLine: touchbackYardLine
                )
            }
            let net = (lastPlay?.playType == .punt) ? (lastPlay?.yardsGained ?? averagePuntDistance)
                                                    : averagePuntDistance
            let opponentYardLine = 100 - (puntFrom + net)
            return NextPossession(
                homeHasPossession: switchPossession,
                startingYardLine: max(1, min(99, opponentYardLine))
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

    /// R40: applies a one-time pre-game morale delta to the snapshot roster
    /// (a strong coaching staff lifts the room, a weak one drags it). Mutates
    /// the `SimPlayer` snapshots only — never the live @Model players. Shared
    /// with `LiveGameEngine` so both paths get the identical bump.
    static func applyCoachMoraleBump(players: inout [SimPlayer], bump: Int) {
        guard bump != 0 else { return }
        for i in players.indices {
            players[i].morale = Swift.max(0, Swift.min(100, players[i].morale + bump))
        }
    }

    /// D1 / F-16: one club's opponent-prep contribution to its OWN offense's
    /// per-play adjustments — its audible edge minus what the defense across the
    /// field has prepared for it.
    ///
    /// Returns `nil` when the two staffs cancel, which is the common case and is
    /// what keeps the no-coach path (`gamePlanning == nil` on both sides)
    /// byte-identical to the pre-D1 engine: `CoachingModifiers.combine` passes a
    /// `nil` straight through, so a neutral game never even allocates an
    /// `Adjustments`.
    ///
    /// Shared by both teams and both directions, so the offense's gain and the
    /// defense's suppression can never be tuned apart by accident.
    static func prepAdjustments(own: Double, opposing: Double) -> PlaySimulator.Adjustments? {
        let mine = OpponentPrep.offenseEdge(focus: own)
        let theirs = OpponentPrep.defenseEdge(focus: opposing)
        let completion = mine.completion + theirs.completion
        let run = mine.run + theirs.run
        guard completion != 0 || run != 0 else { return nil }
        var adj = PlaySimulator.Adjustments()
        adj.completionBonus = completion
        adj.runYardageBonus = run
        return adj
    }

    // MARK: - Mental Game (round 4 — hot/cold FORM)

    /// Absolute-sets each snapshot's `heat` from the tracker — never an
    /// increment, so it is safe to call every drive on top of the in-place
    /// morale mutation `applyMoraleModifiers` performs. Empty tracker ⇒ heat 0
    /// everywhere ⇒ parity.
    static func stampHeat(_ players: inout [SimPlayer], from heat: HeatState) {
        for i in players.indices {
            players[i].heat = heat.value(players[i].id)
        }
    }

    /// Coarse per-drive SIM heat feed (§1b): maps the drive's `PlayResult`
    /// stream onto the shared `HeatState` via the SAME step constants the live
    /// battle feed uses (so an identical signal ⇒ identical heat). The
    /// `keyOffensePlayerID` / `keyDefensePlayerID` attribution the sim already
    /// stamped is the input. Documented asymmetry: the sim credits the DEFENSE
    /// mostly on its WINS (breakup / INT / sack), rarely the beaten cover DB on a
    /// completion, so sim DB cool-down is signal-limited — the live
    /// MatchupResolver, which resolves both sides of every battle, carries fully
    /// bidirectional DB heat. Same component, intentionally richer live feed.
    static func feedDriveHeat(from drive: DriveResult, offense: [SimPlayer],
                              defense: [SimPlayer], into heat: inout HeatState) {
        var eligible: [UUID: Bool] = [:]
        for p in offense { eligible[p.id] = !p.personalityArchetype.isFormImmune }
        for p in defense { eligible[p.id] = !p.personalityArchetype.isFormImmune }
        func elig(_ id: UUID) -> Bool { eligible[id] ?? true }

        for play in drive.plays {
            let big = play.yardsGained >= 20
            switch play.outcome {
            case .touchdown:
                if let id = play.keyOffensePlayerID {
                    heat.reward(id, HeatState.bigStep, scaleEligible: elig(id))
                }
            case .completion:
                if let id = play.keyOffensePlayerID {
                    heat.reward(id, big ? HeatState.bigStep : HeatState.winStep, scaleEligible: elig(id))
                }
            case .rush:
                // BIDIRECTIONAL so sim run heat is ~0-mean in aggregate (mirrors
                // the live path's per-battle win/loss, and keeps a productive back
                // from PINNING hot): a chunk carry heats him, a stuffed one cools
                // him, the middle band is a push. FINAL-POLISH (item 1, EV lean):
                // the old ≥4 / ≤1 lines were NOT balanced — at the 70-tier
                // calibration point the per-team-game run-yield median is ~5, so ≥4
                // captured ~77 % of carries while ≤1 captured only ~16 %. That
                // lopsided warm ratchet drifted the RB's heat up (+0.05 ypc live-vs-
                // off every seed → a +0.3-pt macro scoring lean). Re-centered on the
                // median: a real chunk (≥6) heats, a poor carry (≤3) cools, 4-5 is
                // the push. This lands the sim run feed at ~0-mean (chunk share ~42 %,
                // stuff share ~23 % — the residual keeps a genuinely dominant back
                // warming, which is intended, while zeroing the aggregate drift).
                // ≥20 still books the bigStep chunk accent.
                if let id = play.keyOffensePlayerID {
                    if big {
                        heat.reward(id, HeatState.bigStep, scaleEligible: elig(id))
                    } else if play.yardsGained >= 6 {
                        heat.reward(id, HeatState.winStep, scaleEligible: elig(id))
                    } else if play.yardsGained <= 3 {
                        heat.reward(id, -HeatState.lossStep, scaleEligible: elig(id))
                    }
                }
            case .incompletion:
                // ROUND-6 (zero the heat EV lean): a completion WARMS the target, so
                // an incompletion must COOL him — otherwise receiver heat is a one-way
                // ratchet (only completions/drops ever moved it) that drifts the
                // aggregate completion, and thus scoring, upward (macro Δmean +0.62).
                // Now BIDIRECTIONAL like the run feed: any incompletion — a drop OR a
                // covered/overthrown miss — cools the target by `lossStep` (a drop is
                // no longer singled out), so the pass feed is ~0-mean by construction
                // while every rep still moves heat (variance preserved). A coverage
                // BREAKUP additionally credits the defender (his win).
                if let id = play.keyOffensePlayerID {
                    heat.reward(id, -HeatState.passMissStep, scaleEligible: elig(id))
                }
                if play.passBreakup == true, let did = play.keyDefensePlayerID {
                    heat.reward(did, HeatState.winStep, scaleEligible: elig(did))
                }
            case .sack:
                if let id = play.keyOffensePlayerID {
                    heat.reward(id, -HeatState.lossStep, scaleEligible: elig(id))
                }
                if let did = play.keyDefensePlayerID {
                    heat.reward(did, HeatState.bigStep, scaleEligible: elig(did))
                }
            case .interception:
                if let id = play.keyOffensePlayerID {
                    heat.reward(id, -HeatState.turnoverStep, scaleEligible: elig(id))
                }
                if let did = play.keyDefensePlayerID {
                    heat.reward(did, HeatState.bigStep, scaleEligible: elig(did))
                }
            case .fumbleLost:
                if let id = play.keyOffensePlayerID {
                    heat.reward(id, -HeatState.turnoverStep, scaleEligible: elig(id))
                }
            default:
                break
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
        // #149: the passer and the kicker are the men the play-by-play actually
        // featured, i.e. the BEST at the position — never `first`.
        //
        // `PlaySimulator.findQB` and `FieldUnit.offense` both say it out loud:
        // "roster order is arbitrary". These arrays come from an unsorted
        // SwiftData fetch (`Team.currentRoster()`), so `first { $0.position == .QB }`
        // could be the third-stringer — and then every passing yard, touchdown
        // and interception in the game landed on a man who never took a snap,
        // while rushing/receiving/defense (credited from the sim's own named
        // `keyOffensePlayerID` / `keyDefensePlayerID`) stayed correct. That is
        // exactly the split seen in the postseason columns: QB GP 2 / 0 yards
        // next to a full RB line.
        let qb = startingPlayer(at: .QB, in: offensePlayers)
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
        let kicker = startingPlayer(at: .K, in: offensePlayers)

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
                // R37: a named breakup earns the light PD stat — the same
                // defender the play-by-play text credits.
                if play.passBreakup == true,
                   let db = credited(play.keyDefensePlayerID, roster: defensePlayers, fallback: dBacks) {
                    let current = accumulator[db.id]?.passDeflectionCount ?? 0
                    accumulator[db.id]?.passDeflections = current + 1
                }

            case .rush:
                // keyOffensePlayerID also covers QB scrambles, so the yards
                // land on the scrambler instead of a random back.
                if let rusher = credited(play.keyOffensePlayerID, roster: offensePlayers, fallback: rbs) {
                    accumulator[rusher.id]?.rushingYards += play.yardsGained
                    accumulator[rusher.id]?.carries += 1
                }
                // Credit the tackle to the defender the sim NAMED (R37) so
                // the feed line and the box score agree; unnamed tackles
                // fall back to the old weighted pick.
                if let tackler = credited(play.keyDefensePlayerID, roster: defensePlayers, fallback: linebackers + dLinemen) {
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
                // R37: the sim names the sacker (keyDefensePlayerID) — he
                // gets the FULL sack, matching the play-by-play line. The
                // unnamed fallback keeps the old half-sack convention.
                if let named = play.keyDefensePlayerID,
                   let sacker = defensePlayers.first(where: { $0.id == named }) {
                    accumulator[sacker.id]?.sacks += 1.0
                    accumulator[sacker.id]?.tackles += 1
                } else if let dLineman = pickWeightedPlayer(from: dLinemen + linebackers) {
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

    /// The man the play-by-play treats as the starter at `position`: best
    /// overall, exactly the rule `PlaySimulator.findQB` and `FieldUnit.offense`
    /// apply when they decide who is on the field. Box-score credit for a
    /// position the sim does not name per play (the passer, the kicker) has to
    /// use the SAME rule, or the stat line and the play feed describe two
    /// different players (#149).
    static func startingPlayer(at position: Position, in players: [SimPlayer]) -> SimPlayer? {
        players.filter { $0.position == position }.max { $0.overall < $1.overall }
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
