import Foundation

// MARK: - Drive Simulator

/// Simulates an entire offensive drive from start to conclusion.
enum DriveSimulator {

    /// Result bundle returned after a drive completes.
    struct DriveSimulationResult {
        let drive: DriveResult
        let endQuarter: Int
        let endTime: Int
        let momentumShift: Double
    }

    // MARK: - Public API

    /// Simulates a full drive and returns the result along with updated game clock state.
    /// - Parameters:
    ///   - offensePlayers: The offensive team's players.
    ///   - defensePlayers: The defensive team's players.
    ///   - startingYardLine: Yards from the offense's own end zone (0-100).
    ///   - driveNumber: Sequential drive number in the game.
    ///   - quarter: Current quarter at the start of the drive.
    ///   - timeRemaining: Seconds remaining in the quarter at drive start.
    ///   - momentum: Current momentum value from -1.0 to 1.0.
    ///   - teamID: The UUID of the offensive team.
    ///   - gamePlan: Optional coaching game plan for the OFFENSE — shades the
    ///     AI play-calling in `PlaySimulator`. `nil` = today's exact behavior.
    ///   - weather: Optional game weather forwarded to every play.
    ///     `nil` = today's exact behavior.
    static func simulateDrive(
        offensePlayers: [SimPlayer],
        defensePlayers: [SimPlayer],
        startingYardLine: Int,
        driveNumber: Int,
        quarter: Int,
        timeRemaining: Int,
        momentum: Double,
        teamID: UUID,
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil,
        gamePlan: GamePlan? = nil,
        weather: GameWeather? = nil,
        offenseIsAway: Bool = false,
        adjustments: PlaySimulator.Adjustments? = nil,
        // Round 4 (mental states): the OFFENSE-RELATIVE score margin at drive
        // start, forwarded to every snap so `leverageIndex` can add the
        // trailing-big pressure. Default 0 → parity (every existing call-site and
        // the all-70 harness are byte-identical).
        scoreDifferential: Int = 0,
        // Layer A: the ball-carrier team's per-game run-key EWMA, owned by
        // `GameSimulator` and threaded across all of its drives so the defense's
        // read persists snap-to-snap and drive-to-drive (the same component the
        // coached path runs). `inout` — read `keyIntensity` before each snap,
        // `record` the resolved play type after.
        runKeyState: inout AdaptiveOpponentAI.RunKeyState,
        // F-39: the OFFENSE head coach's `HCPersona.clockErrorRate`, gating his
        // failure to take the knee. 0 = he never botches it, which is the old
        // behaviour once `.kneel` is reachable at all.
        clockErrorRate: Double = 0,
        // F-39: the DEFENCE's remaining timeouts, owned by `GameSimulator` and
        // threaded here as `inout` because this loop is where they get spent — a
        // trailing defence burns them to stop the clock while the leading offense
        // has the ball, which is the only thing a timeout is for in a sim with no
        // injuries to ice. All six went unused in every simulated game before
        // this, while real timeouts roughly double the snaps a trailing team gets
        // on its last drive.
        defenseTimeouts: inout Int
    ) -> DriveSimulationResult {
        var plays: [PlayResult] = []
        var currentDown = 1
        var currentDistance = 10
        var currentYardLine = startingYardLine
        var currentQuarter = quarter
        var currentTime = timeRemaining
        var playNumber = 1

        // Cap first-down distance if near endzone
        if 100 - currentYardLine < 10 {
            currentDistance = 100 - currentYardLine
        }

        while true {
            // --- Time Expiration Check ---
            if isHalfOrGameOver(quarter: currentQuarter, time: currentTime) {
                let outcome = driveOutcomeForTimeExpiry(quarter: currentQuarter)
                let driveResult = DriveResult(
                    driveNumber: driveNumber,
                    teamID: teamID,
                    startingYardLine: startingYardLine,
                    plays: plays,
                    result: outcome
                )
                return DriveSimulationResult(
                    drive: driveResult,
                    endQuarter: currentQuarter,
                    endTime: 0,
                    momentumShift: 0.0
                )
            }

            // Layer A: read the defense's key intensity BEFORE the snap, off the
            // run share built up to this point. Same lever the coached path uses.
            let currentKeyIntensity = runKeyState.keyIntensity(down: currentDown)

            // P0-1: dial up a real defensive package for THIS snap — the SAME
            // situational brain the coached `LiveGameEngine` runs (shared via
            // `situationalDefensivePackage`). Before this the sim path passed a
            // nil package on every snap, skipping the ~0.12 coverage tax the
            // per-play completion/net-YPA bands are calibrated against, which is
            // the entire full-game passing/scoring inflation. `.standard`
            // (Cover 3 / no blitz / base) is the neutral league-average fallback.
            let defensivePackage = situationalDefensivePackage(
                yardLine: currentYardLine,
                quarter: currentQuarter,
                timeRemaining: currentTime,
                down: currentDown,
                distance: currentDistance,
                // scoreDifferential is offense-relative; the defense leads by its
                // negation. (0 at drive start in OT / the all-70 harness ⇒ the
                // late-lead prevent shell simply never fires.)
                defenseLeadsBy: -scoreDifferential
            ) ?? .standard

            // --- Simulate Play ---
            let result = PlaySimulator.simulatePlay(
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                down: currentDown,
                distance: currentDistance,
                yardLine: currentYardLine,
                quarter: currentQuarter,
                timeRemaining: currentTime,
                momentum: momentum,
                playNumber: playNumber,
                offensiveScheme: offensiveScheme,
                defensiveScheme: defensiveScheme,
                defensivePackage: defensivePackage,
                gamePlan: gamePlan,
                weather: weather,
                adjustments: adjustments,
                offenseIsAway: offenseIsAway,
                runKeyIntensity: currentKeyIntensity,
                scoreDifferential: scoreDifferential,
                // F-42: this club's own field-goal range, from its own kicker.
                kickerRangeYards: PlaySimulator.fieldGoalRangeYards(
                    for: PlaySimulator.findKicker(in: offensePlayers)),
                // F-39: the head coach's chance of botching the victory formation,
                // and whether the defence can still stop the clock if he takes it.
                clockErrorRate: clockErrorRate,
                defenseTimeoutsRemaining: defenseTimeouts
            )

            // Store the play with current clock values
            var recordedPlay = result
            recordedPlay.quarter = currentQuarter
            recordedPlay.timeRemaining = currentTime
            plays.append(recordedPlay)

            // Layer A: fold the resolved scrimmage snap into the key EWMA (on the
            // down it was called on). Special-teams / clock plays don't count as
            // a run/pass tendency, so only run & pass update the read.
            // ROUND-6: a team protecting a multi-score lead late is run-leaning to
            // BLEED THE CLOCK (game management), not showing a schematic tendency —
            // folding those clock-kill runs into the EWMA spuriously "keys" an
            // otherwise-balanced offense and drags the equal-tier ypc below band. Skip
            // recording in that game-management window (mirrors `decidePlayCall`'s
            // `lateGame && scoreDifferential >= gameMgmtLeadPts`, 7), so the read
            // reflects only the COMPETITIVE run/pass tendency the defense keys on.
            let inClockKillWindow = currentQuarter >= 3 && scoreDifferential >= 7
            if !inClockKillWindow, result.playType == .run || result.playType == .pass {
                runKeyState.record(isRun: result.playType == .run, down: currentDown)
            }

            // --- Consume Clock ---
            // F-66: inside two minutes the snap knows the situation, so the
            // hurry-up tempo and the out-of-bounds stoppage can fire; everywhere
            // else `clockConsumption` sees the same flat draws it always did.
            // The two-minute warning is applied on top, by `applyClock`.
            var elapsed = clockConsumption(
                for: result,
                context: ClockContext(
                    quarter: currentQuarter,
                    timeRemaining: currentTime,
                    scoreDifferential: scoreDifferential
                )
            )

            // F-39 TIMEOUTS. `DriveSimulator` had no timeout concept at all, so
            // all six went unused in every simulated game — while in a real one
            // they roughly double the snaps a trailing team gets on its last
            // drive, and are most of the reason a two-score deficit inside two
            // minutes is survivable at all.
            //
            // The rule is the one a real staff follows and nothing more: I am
            // behind, the opponent has the ball, the clock is running, and it is
            // late. The trailing DEFENCE spends; the offense's own timeouts are
            // deliberately NOT modelled, because an offense with the ball can
            // already stop its own clock by throwing it away or getting out of
            // bounds — both of which F-66 now models — so giving it a timeout
            // too would be a second lever pulling the same direction.
            //
            // Charged before the clock is applied rather than refunded after:
            // refunding would push the clock back above the two-minute warning
            // and let that stoppage fire a second time in the same quarter.
            if currentQuarter == 4,
               isEndgameWindow(quarter: currentQuarter, timeRemaining: currentTime),
               defenseTimeouts > 0,
               scoreDifferential > 0,                 // the DEFENCE is the one behind
               scoreDifferential <= 16,               // and still within reach
               elapsed >= 20 {                        // the clock was actually running
                defenseTimeouts -= 1
                elapsed = Int.random(in: 4...8)       // only the snap itself
            }

            currentTime = applyClock(elapsed: elapsed, to: currentTime, quarter: currentQuarter)

            // Handle quarter transition
            if currentTime <= 0 {
                let overflow = abs(currentTime)
                if shouldEndDrive(quarter: currentQuarter) {
                    currentTime = 0
                    // Check if this play ended the drive anyway
                    if let driveEnd = checkImmediateDriveEnd(result, plays: plays, driveNumber: driveNumber, teamID: teamID, startingYardLine: startingYardLine, quarter: currentQuarter, time: currentTime) {
                        return driveEnd
                    }
                    // Time expired at end of half/game
                    let outcome = driveOutcomeForTimeExpiry(quarter: currentQuarter)
                    let driveResult = DriveResult(
                        driveNumber: driveNumber,
                        teamID: teamID,
                        startingYardLine: startingYardLine,
                        plays: plays,
                        result: outcome
                    )
                    return DriveSimulationResult(
                        drive: driveResult,
                        endQuarter: currentQuarter,
                        endTime: 0,
                        momentumShift: 0.0
                    )
                } else {
                    // Quarter transition (Q1->Q2, Q3->Q4) — drive continues
                    currentQuarter += 1
                    currentTime = 900 - overflow
                }
            }

            // --- Check for Immediate Drive-Ending Outcomes ---
            if let driveEnd = checkImmediateDriveEnd(result, plays: plays, driveNumber: driveNumber, teamID: teamID, startingYardLine: startingYardLine, quarter: currentQuarter, time: currentTime) {
                return driveEnd
            }

            // --- Update Down & Distance ---
            let advanceResult = advanceDownAndDistance(
                playResult: result,
                currentDown: currentDown,
                currentDistance: currentDistance,
                currentYardLine: currentYardLine
            )

            currentDown = advanceResult.down
            currentDistance = advanceResult.distance
            currentYardLine = advanceResult.yardLine

            // --- Turnover on Downs ---
            if currentDown > 4 {
                let driveResult = DriveResult(
                    driveNumber: driveNumber,
                    teamID: teamID,
                    startingYardLine: startingYardLine,
                    plays: plays,
                    result: .turnoverOnDowns
                )
                return DriveSimulationResult(
                    drive: driveResult,
                    endQuarter: currentQuarter,
                    endTime: max(currentTime, 0),
                    momentumShift: -0.1
                )
            }

            playNumber += 1

            // Safety valve: prevent infinite drives
            if playNumber > 40 {
                let driveResult = DriveResult(
                    driveNumber: driveNumber,
                    teamID: teamID,
                    startingYardLine: startingYardLine,
                    plays: plays,
                    result: .punt
                )
                return DriveSimulationResult(
                    drive: driveResult,
                    endQuarter: currentQuarter,
                    endTime: max(currentTime, 0),
                    momentumShift: 0.0
                )
            }
        }
    }

    // MARK: - Defensive Play-Calling (shared with LiveGameEngine)

    /// The purely situational defensive package for a snap — the ONE defensive
    /// brain shared by the auto-sim (this loop) and the coached
    /// `LiveGameEngine.baseDefensivePackage()`, so the two engines can never
    /// drift apart. Returns `nil` when no higher-priority situational shell
    /// applies; the caller then falls back to ``DefensivePackage/standard``
    /// (Cover 3 / no blitz / base) — the neutral league-average look whose
    /// ~0.12 total coverage tax the per-play bands are calibrated against.
    ///
    /// The live engine's two extra branches (a Bear front once it has KEYED the
    /// player's run tendency, a Cover 2 shell once it has keyed the deep game)
    /// are intentionally OMITTED here: both depend on `PlayMemory`, a live-only
    /// read that fills solely from the human's calls and never applies to an
    /// AI-vs-AI auto-sim. Everything else is branch-for-branch identical.
    ///
    /// - Parameter defenseLeadsBy: score margin from the DEFENSE's perspective
    ///   (positive ⇒ the defending team leads). Drives only the late-lead
    ///   prevent shell; `0` keeps every other branch untouched.
    static func situationalDefensivePackage(
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        down: Int,
        distance: Int,
        defenseLeadsBy: Int
    ) -> DefensivePackage? {
        let yardsToEndzone = 100 - yardLine
        if yardsToEndzone <= 10 {
            // Red zone: sell out against the short field.
            return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .goalLine)
        } else if quarter >= 4 && timeRemaining <= 240
                    && defenseLeadsBy > 0 && defenseLeadsBy <= 16
                    && yardsToEndzone > 25 {
            // Protecting a late lead: prevent shell — concede the checkdown,
            // never the bomb.
            return DefensivePackage(coverage: .prevent, blitz: .noBlitz, front: .dime)
        } else if down == 3 && distance >= 7 {
            // 3rd & long: quarters coverage out of a dime personnel — take away
            // the sticks, rush four. P0-1: this was a cover4 + DB-BLITZ look, but
            // on the pass-heaviest down the blitz tripped the engine's LB-blitz
            // phantom-rush term and over-produced sacks league-wide. Dropping the
            // blitz (rush four, quarters behind it) removes the phantom and its
            // −pressure trims the sack rate back into band, while the tighter
            // quarters shell keeps 3rd-&-long conversions suppressed.
            return DefensivePackage(coverage: .cover4, blitz: .noBlitz, front: .dime)
        } else if distance <= 2 {
            // Short yardage: crowd the box with the bear front.
            return DefensivePackage(coverage: .cover1, blitz: .noBlitz, front: .bear)
        } else if yardsToEndzone <= PlaySimulator.redZoneYards {
            // F-44 RED ZONE. The sheet already had a goal-line sellout inside the
            // 10; the real red zone starts at the 20 and changes the defence from
            // there. With the end zone as a twelfth defender there is no deep
            // route to protect, so help coverage is wasted and the call is man
            // out of base personnel — matchups decide, which is why red-zone
            // defence is a personnel argument in the first place.
            //
            // Placed LAST on purpose. Third-and-long is still third-and-long from
            // the 18: a real defence plays its dime quarters there, not red-zone
            // man, and short yardage still gets the Bear front. Putting this
            // branch above them would have swallowed both, which is the mistake
            // that made "the red zone starts at the 10" look survivable.
            return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .base)
        }
        return nil
    }

    // MARK: - Down & Distance Management

    /// Down/distance/field-position triple after a play. Shared with `LiveGameEngine`.
    struct DownDistanceState {
        let down: Int
        let distance: Int
        let yardLine: Int
    }

    /// Advances down, distance, and yard line based on a play's result.
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func advanceDownAndDistance(
        playResult: PlayResult,
        currentDown: Int,
        currentDistance: Int,
        currentYardLine: Int
    ) -> DownDistanceState {
        let newYardLine = max(1, min(99, currentYardLine + playResult.yardsGained))

        if playResult.isFirstDown {
            let yardsToEndzone = 100 - newYardLine
            return DownDistanceState(
                down: 1,
                distance: min(10, yardsToEndzone),
                yardLine: newYardLine
            )
        }

        // Penalties never consume a down: the yardage is walked off and the
        // SAME down is replayed. (Defensive flags whose yardage reaches the
        // line to gain arrive here with isFirstDown already set and take the
        // branch above instead.)
        if playResult.outcome == .penalty {
            return DownDistanceState(
                down: currentDown,
                distance: max(1, currentDistance - playResult.yardsGained),
                yardLine: newYardLine
            )
        }

        let newDistance = max(1, currentDistance - playResult.yardsGained)
        return DownDistanceState(
            down: currentDown + 1,
            distance: newDistance,
            yardLine: newYardLine
        )
    }

    // MARK: - Drive End Checks

    /// Returns a DriveSimulationResult if the play immediately ends the drive, nil otherwise.
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func checkImmediateDriveEnd(
        _ result: PlayResult,
        plays: [PlayResult],
        driveNumber: Int,
        teamID: UUID,
        startingYardLine: Int,
        quarter: Int,
        time: Int
    ) -> DriveSimulationResult? {
        switch result.outcome {
        case .touchdown:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .touchdown
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: 0.1
            )

        case .fieldGoalGood:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .fieldGoal
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: 0.05
            )

        case .fieldGoalMissed:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .turnover
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: -0.05
            )

        case .interception, .fumbleLost:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .turnover
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: -0.1
            )

        case .punt, .touchback:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .punt
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: 0.0
            )

        case .safety:
            let driveResult = DriveResult(
                driveNumber: driveNumber,
                teamID: teamID,
                startingYardLine: startingYardLine,
                plays: plays,
                result: .safety
            )
            return DriveSimulationResult(
                drive: driveResult,
                endQuarter: quarter,
                endTime: max(time, 0),
                momentumShift: -0.15
            )

        default:
            return nil
        }
    }

    // MARK: - Clock Management

    // MARK: Endgame clock (F-66)

    // The clock model is broadly right in the mean — plays per game measures 66.2
    // against a 58-68 band — and F-66 is deliberately scoped to the ENDGAME only
    // for exactly that reason. The ruling is explicit: the flat per-play duration
    // draw stays as it is, because making it situational everywhere would
    // recalibrate plays-per-game, and plays-per-game is a banded harness number
    // that nothing else in this wave is allowed to move. So every rule below is
    // gated on a two-minute window, where the missing stoppages decide games
    // rather than shift a season aggregate.

    /// The half's automatic stoppage, in seconds remaining. Wired into the drive
    /// loop by F-66; it had been declared on `GameSimulator` and read by nothing
    /// anywhere in the repo, standing in for a stoppage that was not modelled.
    static let twoMinuteWarning = 120

    /// Seconds a hurry-up snap consumes, against the 25-40 s huddle draw. Real
    /// no-huddle offenses run 15-22 s between snaps; this band sits above that
    /// because the number here is snap-to-snap INCLUDING the play itself, and
    /// because the two cheapest hurry-up outcomes — an incompletion and a ball
    /// carried out of bounds — are already priced separately below and would
    /// otherwise be counted twice.
    ///
    /// Trades against: plays per game, and it is the most expensive of the four
    /// endgame rules. Measured on `fullgame --home-tier 80 --away-tier 78
    /// --n 800`: at 19-27 it alone was worth +1.3 plays and took the pooled
    /// figure to 68.4, one snap OUT of the 58-68 band. 22-30 is the widest band
    /// that still reads as a genuine tempo change (mean 26 s against the huddle's
    /// 32.5) while leaving room for the other three.
    private static let hurryUpClockRange = 22...30

    /// Seconds a snap consumes when the offense is protecting a lead inside two
    /// minutes — the play clock milked to about :01 before the ball is snapped.
    /// This is F-66's fourth named gap, the missing 40-second play clock, and it
    /// is the exact mirror of the hurry-up above: the same two minutes look
    /// completely different depending on which team has the ball, and modelling
    /// only the trailing half would have made the endgame uniformly faster than
    /// a real one.
    ///
    /// Trades against: plays per game, downwards, and it is the reason the three
    /// stoppages above fit inside the 58-68 band at all. Measured: the leading
    /// team's bleed is worth about −1.1 plays a game against the hurry-up's
    /// +1.3, so the endgame gets its real shape without the game getting longer.
    private static let clockBleedRange = 34...45

    /// Chance a completion or run inside the two-minute window ends out of
    /// bounds and stops the clock. Real completions go out of bounds ~10-12 % of
    /// the time, and while a trailing offense working the sideline on purpose is
    /// higher than that, 0.10 is where the play-count budget landed: measured at
    /// 0.15 this rule was worth +0.4 plays a game on its own.
    ///
    /// Trades against: how much clock a trailing team can preserve. Set to 0 and
    /// the two-minute drill can only stop its own clock by FAILING — an
    /// incompletion — which makes yards and time a trade real offenses do not
    /// face. Set it near 1 and the clock stops being a constraint at all.
    private static let outOfBoundsChance = 0.10

    /// Whether a snap is being played inside a half's endgame window — the only
    /// place any of F-66's rules apply. Overtime is excluded deliberately: the
    /// NFL runs no two-minute warning in OT, and the sudden-death shape means a
    /// trailing team in the engine's sense does not exist there.
    static func isEndgameWindow(quarter: Int, timeRemaining: Int) -> Bool {
        (quarter == 2 || quarter == 4) && timeRemaining <= twoMinuteWarning
    }

    /// The situational context an endgame snap's clock consumption depends on.
    /// `nil` at the call site reproduces the pre-F-66 behaviour exactly, which is
    /// what keeps `LiveGameEngine`'s own clock — and every non-endgame snap in
    /// this loop — byte-identical.
    struct ClockContext {
        let quarter: Int
        let timeRemaining: Int
        /// Offense-relative margin (+ = the team with the ball is ahead).
        let scoreDifferential: Int
    }

    /// Calculates seconds consumed by a play.
    /// Incomplete passes and spikes stop the clock (less time consumed).
    /// Run plays and completions keep the clock running.
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    ///
    /// - Parameter context: endgame situation for F-66's hurry-up tempo and
    ///   out-of-bounds stoppage. `nil` — every caller that existed before F-66 —
    ///   keeps the flat draws untouched.
    static func clockConsumption(for play: PlayResult, context: ClockContext? = nil) -> Int {
        switch play.outcome {
        case .incompletion:
            // Clock stops on incompletion: just the play itself
            return Int.random(in: 4...8)
        case .spike:
            return 3
        case .kneel:
            return 40
        case .punt, .touchback:
            return Int.random(in: 5...10)
        case .penalty:
            // The clock stops while the flag is sorted out; only the aborted
            // snap's few seconds elapse.
            return Int.random(in: 4...8)
        case .fieldGoalGood, .fieldGoalMissed:
            return Int.random(in: 5...8)
        case .touchdown:
            return Int.random(in: 5...10)
        case .interception, .fumbleLost:
            return Int.random(in: 5...10)
        case .safety:
            return Int.random(in: 5...10)
        default:
            // Completions, rushes, sacks — clock keeps running.
            //
            // F-66, and ONLY inside a two-minute window. Two real stoppages the
            // model had neither of:
            //
            //  • Out of bounds. A completion (or a run) that gets to the sideline
            //    stops the clock dead. Without it a trailing team's only way to
            //    stop its own clock was an incompletion, i.e. a failed play —
            //    which made the two-minute drill a choice between gaining yards
            //    and keeping time, a trade real offenses do not face.
            //  • Hurry-up. A no-huddle offense snaps it in ~15-22 s, not 25-40.
            //    A trailing team therefore gets roughly double the snaps out of
            //    the same clock, which is the single biggest reason real
            //    comebacks happen and the engine's did not.
            //
            // A sack is excluded from the out-of-bounds branch: a quarterback put
            // on the ground behind the line has not got to the sideline, and
            // treating it as a stoppage would remove the drive-killing cost of a
            // sack in exactly the situation where it hurts most.
            guard let context,
                  isEndgameWindow(quarter: context.quarter, timeRemaining: context.timeRemaining)
            else { return Int.random(in: 25...40) }
            if play.outcome != .sack, Double.random(in: 0..<1) < outOfBoundsChance {
                return Int.random(in: 4...8)
            }
            // Hurry-up is a TRAILING (or tied) team's tempo. A team protecting a
            // lead huddles up and bleeds it — the existing game-management bias
            // already makes it run the ball, and speeding that up would hand the
            // leader a faster way to end the game, which is backwards.
            if context.scoreDifferential <= 0 { return Int.random(in: hurryUpClockRange) }
            // Protecting a lead: milk the play clock. The leading team's job in
            // the last two minutes is to make the clock run, and a snap taken at
            // :01 costs the defence far more than the flat huddle draw admits.
            return Int.random(in: clockBleedRange)
        }
    }

    /// Applies a play's elapsed time to the game clock, honouring the automatic
    /// two-minute warning (F-66 / F-40).
    ///
    /// The warning was a dead constant: `GameSimulator.twoMinuteWarning = 120`
    /// was declared and read nowhere, so a play that started at 2:04 and ran 35
    /// seconds simply took the half to 1:29 and the stoppage that every real
    /// endgame is built around did not exist. Clamping to the warning preserves
    /// the clock instead, which is worth roughly one extra snap per half to
    /// whichever team needs it.
    ///
    /// The `> twoMinuteWarning` guard means this can fire at most once per
    /// quarter without any "already fired" bookkeeping: once the clock has been
    /// clamped to exactly 120 it can never again be above it.
    static func applyClock(elapsed: Int, to timeRemaining: Int, quarter: Int) -> Int {
        guard quarter == 2 || quarter == 4,
              timeRemaining > twoMinuteWarning,
              timeRemaining - elapsed < twoMinuteWarning
        else { return timeRemaining - elapsed }
        return twoMinuteWarning
    }

    // MARK: - Time Helpers

    /// Determines if the current quarter ends the half or game (Q2, Q4, or OT).
    /// Internal (not private) because it is shared with `LiveGameEngine`.
    static func shouldEndDrive(quarter: Int) -> Bool {
        quarter == 2 || quarter >= 4
    }

    /// Checks if time has fully expired for a half-ending or game-ending quarter.
    private static func isHalfOrGameOver(quarter: Int, time: Int) -> Bool {
        time <= 0 && shouldEndDrive(quarter: quarter)
    }

    /// Returns the appropriate drive outcome when time expires.
    private static func driveOutcomeForTimeExpiry(quarter: Int) -> DriveOutcome {
        if quarter == 2 {
            return .endOfHalf
        }
        return .endOfGame
    }
}
