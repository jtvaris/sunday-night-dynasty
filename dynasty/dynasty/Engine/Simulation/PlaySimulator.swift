import Foundation

// MARK: - Play Simulator

/// Simulates individual NFL plays using player attributes, game situation, and randomness.
enum PlaySimulator {

    // MARK: - Live Coaching Adjustments

    /// Small live-game coaching tweaks (halftime adjustments). Applied on top
    /// of the normal odds. `nil` — the default everywhere — reproduces today's
    /// behavior exactly, so quick-sim / auto-sim parity is untouched.
    struct Adjustments {
        /// Subtracted from the sack probability (pass-protection emphasis).
        var sackChanceReduction: Double = 0
        /// Added to the completion probability (attack-the-corners emphasis).
        var completionBonus: Double = 0
        /// Added to expected rushing yards before the roll is rounded.
        var runYardageBonus: Double = 0
        /// Multiplies the pre-snap penalty-flag chance for this offense
        /// (R40 discipline). `1.0` = today's exact behavior.
        var penaltyChanceScale: Double = 1.0
        /// Multiplies the ball-carrier fumble chance for this offense
        /// (R40 discipline). `1.0` = today's exact behavior.
        var fumbleChanceScale: Double = 1.0
    }

    // MARK: - Public API

    /// Simulates a single play and returns the result.
    /// - Parameters:
    ///   - offensePlayers: All offensive players on the field.
    ///   - defensePlayers: All defensive players on the field.
    ///   - down: Current down (1-4).
    ///   - distance: Yards needed for a first down.
    ///   - yardLine: Field position as yards from own end zone (0-100).
    ///   - quarter: Current quarter (1-4, 5 for OT).
    ///   - timeRemaining: Seconds left in the current quarter.
    ///   - momentum: Team momentum from -1.0 (defense) to 1.0 (offense).
    ///   - playNumber: Sequential play number within the drive.
    ///   - offensiveCall: Optional explicit play call (live coached games). When
    ///     non-nil the play type is derived from the call instead of
    ///     ``decidePlayCall`` and its ``OffensivePlayCall/SimulatorHint`` shades
    ///     the pass/run probabilities. `nil` preserves today's AI behavior exactly.
    ///   - forcedPlayType: Highest-precedence play type override. Used by the
    ///     live engine for 4th-down decisions (.punt / .fieldGoal / .kneel),
    ///     which are not `OffensivePlayCall` cases.
    ///   - defensivePackage: Optional defensive call (live coached games). Its
    ///     aggregate modifiers adjust completion, sack, and run-yardage odds.
    ///     `nil` preserves today's behavior exactly.
    ///   - gamePlan: Optional coaching game plan for the OFFENSE. Shades the
    ///     AI's run/pass mix and 4th-down aggressiveness inside
    ///     ``decidePlayCall``. `nil` preserves today's behavior exactly.
    ///   - weather: Optional game weather. `nil` (or `.clear`) preserves
    ///     today's behavior exactly. Rain/snow slick the ball (completions,
    ///     fumbles, kicks); snow also kills breakaways and biases play-calling
    ///     toward the run; wind knocks down deep passes and long field goals.
    ///   - adjustments: Optional live coaching tweaks (halftime adjustments)
    ///     for the OFFENSE. `nil` preserves today's behavior exactly.
    static func simulatePlay(
        offensePlayers: [SimPlayer],
        defensePlayers: [SimPlayer],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        momentum: Double,
        playNumber: Int,
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil,
        offensiveCall: OffensivePlayCall? = nil,
        forcedPlayType: PlayType? = nil,
        defensivePackage: DefensivePackage? = nil,
        gamePlan: GamePlan? = nil,
        weather: GameWeather? = nil,
        adjustments: Adjustments? = nil,
        offenseIsAway: Bool = false,
        // Layer A: how hard the defense is keying THIS offense's run tendency
        // (0…1, from `AdaptiveOpponentAI.RunKeyState.keyIntensity`). 0 = no key,
        // which is mean-neutral everywhere — a nil-argument / quick-sim snap is
        // byte-for-byte identical to today. Drives the run yard-bite + stuff
        // bonus (A2) and the play-action / deep punish (A3).
        runKeyIntensity: Double = 0,
        // Layer B (PLAY-MEMORY, coached path): signed probability/value SHIFTS
        // the live engine folds in from the category / exact-call / counter read
        // of the PLAYER's called concept. ALL default to identity (0) so every
        // nil-argument / quick-sim / sim-path snap is byte-identical to today —
        // these add ZERO RNG draws, they only move existing shift sites.
        //   • passCompletionDelta — per-depth completion shift (already net-signed
        //     and malus-capped by the engine), applied at the depth curve.
        //   • runYardDelta — extra run yard bite (folded into `runStopBite`,
        //     combined with runKey's bite under `runGrandBiteCap`).
        //   • runStuffDelta — extra stuff probability (folded into `stuffChance`).
        passCompletionDelta: (short: Double, mid: Double, deep: Double) = (0, 0, 0),
        runYardDelta: Double = 0,
        runStuffDelta: Double = 0,
        // Round 4 (mental states): the OFFENSE-RELATIVE score margin, used only
        // to build the situational `leverageIndex` that scales composure. 0 →
        // no trailing-leverage contribution, which (with composure 70 / heat 0)
        // is mean-neutral everywhere — a nil-argument / quick-sim snap is
        // byte-for-byte identical to today.
        scoreDifferential: Int = 0
    ) -> PlayResult {
        let playCall: PlayType
        if let forced = forcedPlayType {
            playCall = forced
        } else if let call = offensiveCall {
            playCall = playType(for: call)
        } else {
            playCall = decidePlayCall(
                down: down,
                distance: distance,
                yardLine: yardLine,
                quarter: quarter,
                timeRemaining: timeRemaining,
                offensiveScheme: offensiveScheme,
                gamePlan: gamePlan,
                weather: weather,
                scoreDifferential: scoreDifferential
            )
        }

        let hint = offensiveCall?.simulatorHint

        // --- Penalty check (scrimmage plays only, ~6% of snaps) ---
        // Rolled BEFORE the play resolves: a flag wipes the down out entirely.
        // Special teams (punt/FG) and clock plays are exempt to keep their
        // flows simple. R40: a disciplined coaching staff scales this offense's
        // flag frequency down (scale 1.0 = today's exact behavior).
        let scaledPenaltyChance = penaltyChance * (adjustments?.penaltyChanceScale ?? 1.0)
        if playCall == .pass || playCall == .run,
           randomChance(scaledPenaltyChance) {
            return rollPenalty(
                playCall: playCall,
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                down: down,
                distance: distance,
                yardLine: yardLine,
                quarter: quarter,
                timeRemaining: timeRemaining,
                playNumber: playNumber,
                offenseIsAway: offenseIsAway
            )
        }

        switch playCall {
        case .pass:
            return simulatePassPlay(
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                down: down,
                distance: distance,
                yardLine: yardLine,
                quarter: quarter,
                timeRemaining: timeRemaining,
                momentum: momentum,
                playNumber: playNumber,
                offensiveScheme: offensiveScheme,
                defensiveScheme: defensiveScheme,
                hint: hint,
                defensivePackage: defensivePackage,
                weather: weather,
                adjustments: adjustments,
                runKeyIntensity: runKeyIntensity,
                passCompletionDelta: passCompletionDelta,
                scoreDifferential: scoreDifferential
            )
        case .run:
            return simulateRunPlay(
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                down: down,
                distance: distance,
                yardLine: yardLine,
                quarter: quarter,
                timeRemaining: timeRemaining,
                momentum: momentum,
                playNumber: playNumber,
                offensiveScheme: offensiveScheme,
                defensiveScheme: defensiveScheme,
                hint: hint,
                call: offensiveCall,
                defensivePackage: defensivePackage,
                weather: weather,
                adjustments: adjustments,
                runKeyIntensity: runKeyIntensity,
                runYardDelta: runYardDelta,
                runStuffDelta: runStuffDelta,
                scoreDifferential: scoreDifferential
            )
        case .punt:
            return simulatePunt(
                offensePlayers: offensePlayers,
                down: down,
                distance: distance,
                yardLine: yardLine,
                quarter: quarter,
                timeRemaining: timeRemaining,
                playNumber: playNumber
            )
        case .fieldGoal:
            return simulateFieldGoal(
                offensePlayers: offensePlayers,
                down: down,
                distance: distance,
                yardLine: yardLine,
                quarter: quarter,
                timeRemaining: timeRemaining,
                playNumber: playNumber,
                weather: weather
            )
        case .kneel:
            return simulateKneel(
                offensePlayers: offensePlayers,
                down: down,
                distance: distance,
                yardLine: yardLine,
                quarter: quarter,
                timeRemaining: timeRemaining,
                playNumber: playNumber
            )
        case .spike:
            return simulateSpike(
                down: down,
                distance: distance,
                yardLine: yardLine,
                quarter: quarter,
                timeRemaining: timeRemaining,
                playNumber: playNumber
            )
        default:
            // Fallback to a run play for any unhandled special play type
            return simulateRunPlay(
                offensePlayers: offensePlayers,
                defensePlayers: defensePlayers,
                down: down,
                distance: distance,
                yardLine: yardLine,
                quarter: quarter,
                timeRemaining: timeRemaining,
                momentum: momentum,
                playNumber: playNumber,
                offensiveScheme: offensiveScheme,
                defensiveScheme: defensiveScheme,
                hint: hint,
                call: offensiveCall,
                defensivePackage: defensivePackage,
                weather: weather,
                adjustments: adjustments,
                runKeyIntensity: runKeyIntensity,
                runYardDelta: runYardDelta,
                runStuffDelta: runStuffDelta,
                scoreDifferential: scoreDifferential
            )
        }
    }

    /// Maps an explicit offensive play call to the simulator's ``PlayType`` —
    /// the QUICK-SIM ABSTRACTION of the call, and the only thing about a play
    /// call that `GameSimulator` could ever observe.
    ///
    /// The whole 65-play call sheet collapses to exactly three outcomes here:
    ///
    /// * `.run`   — every carry: the gap/zone runs, the QB-conflict runs
    ///              (`zoneRead`, `qbDraw`, `speedOption`), the sneaks.
    /// * `.pass`  — every drop-back, screen, RPO, play-action and `hailMary`.
    ///              RPOs resolve on the pass path by design: the engine has no
    ///              give/pull mechanic, so the "give" side of the read is
    ///              represented by the same formation family's zone runs, which
    ///              the coach reaches through the audible strip.
    /// * `.spike` / `.kneel` — the two clock plays. The expansion adds none.
    ///
    /// `.screen` is the one legacy inconsistency: it reports `isRun == true`
    /// but is routed as a PASS, because its hint carries `passDepth: .short`
    /// plus a high YAC multiplier, which models the screen game far better than
    /// the run path would. The NEWER screens are honest passes (`isPass`), so
    /// they need no special case here.
    ///
    /// `GameSimulator.simulate` passes `offensiveCall: nil` on every scrimmage
    /// snap, so no expansion play ever reaches season simulation, the balance
    /// harness or `MultiSeasonSmokeTest`. The only two call-aware quick-sim
    /// sites are the DEBUG micro-harnesses (`.playActionDeep`, `.slant`), both
    /// of which name pre-existing calls and are untouched.
    static func playType(for call: OffensivePlayCall) -> PlayType {
        switch call {
        case .spike:  return .spike
        case .kneel:  return .kneel
        case .screen: return .pass
        default:      return call.isRun ? .run : .pass
        }
    }

    // MARK: - Play Call Decision

    /// Determines the type of play to call based on game situation.
    ///
    /// - Parameter gamePlan: Optional coaching game plan for the offense.
    ///   `runPassRatio` shifts the pass probability (±0.15 at the extremes)
    ///   and `fourthDownAggressiveness` widens/narrows the go-for-it window.
    ///   `nil` — or a fully balanced plan — reproduces today's behavior exactly.
    /// - Parameter weather: Optional game weather. Snow shifts the play mix
    ///   toward the run (pass probability -0.08); other conditions and `nil`
    ///   leave the call untouched.
    // P0-2 game-management levers. A lead of >= `LeadPts` late shifts the run/pass
    // mix by `BiasSlope` per point beyond the threshold, capped at `BiasCap`.
    private static let gameMgmtLeadPts  = 7      // one-score-plus trigger
    private static let gameMgmtBiasSlope = 0.030 // pass-bias shift per point past the trigger
    private static let gameMgmtBiasCap   = 0.40  // max run-lean (leader) / pass-lean (trailer)
    static func decidePlayCall(
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        offensiveScheme: OffensiveScheme? = nil,
        gamePlan: GamePlan? = nil,
        weather: GameWeather? = nil,
        // P0-2: offense-relative score margin (+ = offense leading). 0 → every
        // score-aware term below is inert, so quick sim / early-game / competitive
        // snaps are byte-identical to today.
        scoreDifferential: Int = 0
    ) -> PlayType {
        let yardsToEndzone = 100 - yardLine
        // P0-2 GAME MANAGEMENT (garbage time / comeback). The single biggest driver
        // of the runaway margin is that play-calling is score-BLIND: a team up 40
        // keeps its two-minute drill and 55% pass rate, trading fast incompletion-
        // stopped possessions instead of bleeding the clock, so the blowout
        // compounds linearly to the whistle. Real coaches manage the score:
        //   • protecting a multi-score lead late → run-heavy (clock drains, ~30-40s
        //     vs an incompletion's ~6s → FEWER possessions → the margin stops
        //     growing and possession-inflation is removed);
        //   • trailing late → pass-heavy + hurry (the comeback attempt, which adds
        //     upset variance).
        // Gated on `lateGame` AND a multi-score gap, so a close or early game — and
        // every equal-talent matchup — never triggers it (parity preserved).
        let lateGame = quarter >= 3   // whole second half
        let mgmtPassBias: Double = {
            guard lateGame else { return 0 }
            let d = Double(scoreDifferential)
            let trig = Double(gameMgmtLeadPts)
            if d >= trig { return -min(gameMgmtBiasCap, gameMgmtBiasSlope * (d - trig + 1)) }
            if d <= -trig { return  min(gameMgmtBiasCap, gameMgmtBiasSlope * (-d - trig + 1)) }
            return 0
        }()
        // A comfortable late lead suppresses the hurry-up: bleed the clock, don't
        // trade snaps. The drill still fires for a tied/trailing/one-score offense.
        let isTwoMinuteDrill = quarter == 4 && timeRemaining <= 120
            && scoreDifferential < gameMgmtLeadPts
        let fieldGoalRange = yardsToEndzone <= 45

        // Scheme pass bias: shifts pass probability up (pass-heavy) or down (run-heavy)
        let schemeOnlyPassBias: Double = {
            guard let scheme = offensiveScheme else { return 0.0 }
            switch scheme {
            case .airRaid:    return 0.15   // Heavy pass
            case .proPassing: return 0.10   // Pass-leaning
            case .westCoast:  return 0.08   // Pass-leaning
            case .spread:     return 0.05   // Slight pass
            case .rpo:        return 0.0    // Balanced
            case .shanahan:   return -0.10  // Run-leaning
            case .option:     return -0.12  // Run-leaning
            case .powerRun:   return -0.15  // Heavy run
            }
        }()

        // Game-plan pass bias: the user's Play Calling Mix slider shifts the
        // pass probability. ROUND-6 raised the slope 0.3 → 0.60 to restore the
        // run-heavy adaptation penalty. FINAL-POLISH (item 2): 0.60 still under-
        // produced — a "run-heavy" plan (runPassRatio 0.25) called only ~53 % of
        // its snaps on the ground (~0.585 early-down share), barely over
        // RunKeyState.keyPivot (0.55, keyIntensity ~0.18), so the defense keyed it
        // only weakly and the penalty leaned on the P0-1 opportunity-cost alone.
        // The KNOB — not the punishment — was diluted (the sane-mix P0-1 trim lifted
        // BALANCED's own early-down run share, compressing the styles together). Fixed
        // by steepening ONLY the run side: runPassRatio < 0.5 uses slope 1.00 so a
        // run-heavy plan calls a genuinely run-heavy ~61 % scrimmage sequence (up from
        // the diluted ~53 %; early-down ~0.68, clearly past keyPivot ⇒ the defense keys
        // and its ground game collapses to ~2.9 ypc, restoring a ~68 % HFA-neutral
        // balanced-beats-run-heavy penalty — in the 60-70 % target). The pass side
        // stays at the round-5-safe 0.60 so a pass-heavy plan's scoring is NOT
        // re-inflated (the asymmetry is the whole point). Held at 1.00, not higher: at
        // 1.10-1.20 the steep keyIntensity ramp near-full-keys the ~63 % sequence and
        // over-corrects the penalty past 70 %. A balanced plan (0.5) contributes
        // EXACTLY 0, so every nil-gameplan / equal-tier path is byte-unchanged — only
        // a styled plan moves.
        let planRatioDelta = (gamePlan?.runPassRatio ?? 0.5) - 0.5
        let planPassBias = planRatioDelta * (planRatioDelta < 0 ? 1.00 : 0.60)

        // Weather run bias: in snow both AI coordinators lean on the ground
        // game — the pass probability drops by 0.08 across every situation.
        let weatherPassBias: Double = weather == .snow ? -0.08 : 0.0
        let schemePassBias = schemeOnlyPassBias + planPassBias + weatherPassBias + mgmtPassBias

        // 4th down decisions
        if down == 4 {
            // P0-2: a team protecting a multi-score lead late never gambles on 4th
            // down — take the FG in range, otherwise punt and make them drive the
            // length of the field. (Goal-line 4th-and-1 for the lead still resolves
            // below; this only removes the low-percentage gambles that pad blowouts.)
            if lateGame && scoreDifferential >= gameMgmtLeadPts {
                if fieldGoalRange { return .fieldGoal }
                return .punt
            }
            // Very conservative plans (< 0.35) kick/punt even on 4th & short —
            // except in a late-game desperation drive, where punting the ball
            // away would be indefensible.
            if let plan = gamePlan, plan.fourthDownAggressiveness < 0.35 {
                if isTwoMinuteDrill && yardsToEndzone > 45 {
                    return coinFlip(0.7 + schemePassBias * 0.5) ? .pass : .run
                }
                if fieldGoalRange { return .fieldGoal }
                return .punt
            }
            // Go for it on 4th & short near the goal line
            if distance <= 2 && yardsToEndzone <= 5 {
                return coinFlip(0.5 + schemePassBias) ? .pass : .run
            }
            // Go for it in desperation (late game, trailing assumed from two-minute drill)
            if isTwoMinuteDrill && yardsToEndzone > 45 {
                return coinFlip(0.7 + schemePassBias * 0.5) ? .pass : .run
            }
            // Aggressive plans (> 0.65) also go for it on 4th & 3-or-less
            // once past midfield instead of settling for a punt / long FG.
            if let plan = gamePlan, plan.fourthDownAggressiveness > 0.65,
               distance <= 3, yardLine >= 50 {
                return coinFlip(clamp(0.55 + schemePassBias, min: 0.25, max: 0.80)) ? .pass : .run
            }
            // Field goal if in range
            if fieldGoalRange {
                return .fieldGoal
            }
            // Punt otherwise
            return .punt
        }

        // Two-minute drill: heavily favor passing (scheme has reduced impact)
        if isTwoMinuteDrill {
            return coinFlip(clamp(0.85 + schemePassBias * 0.3, min: 0.70, max: 0.95)) ? .pass : .run
        }

        // Normal play calling by down and distance, with scheme bias applied.
        // P0-1 (secondary): early-down pass weights were ~6pp above the NFL
        // (1st-down 0.55, 3rd-&-short 0.50) which — once the defensive coverage
        // tax was restored — left too many drop-backs, over-producing sacks
        // (absolute count) and holding rushing below the band. Trimmed to NFL-
        // sane (1st-down 0.50, 3rd-&-short 0.42). Named play-calls / the per-play
        // FIXED-BASELINE bands force their play type and never reach this switch.
        switch down {
        case 1:
            return coinFlip(clamp(0.50 + schemePassBias, min: 0.25, max: 0.80)) ? .pass : .run
        case 2:
            if distance >= 7 {
                return coinFlip(clamp(0.65 + schemePassBias, min: 0.35, max: 0.85)) ? .pass : .run
            } else {
                return coinFlip(clamp(0.50 + schemePassBias, min: 0.25, max: 0.75)) ? .pass : .run
            }
        case 3:
            if distance <= 3 {
                return coinFlip(clamp(0.42 + schemePassBias, min: 0.25, max: 0.75)) ? .pass : .run
            } else if distance >= 7 {
                return coinFlip(clamp(0.80 + schemePassBias * 0.5, min: 0.60, max: 0.95)) ? .pass : .run
            } else {
                return coinFlip(clamp(0.65 + schemePassBias, min: 0.35, max: 0.85)) ? .pass : .run
            }
        default:
            return coinFlip(clamp(0.55 + schemePassBias, min: 0.25, max: 0.80)) ? .pass : .run
        }
    }

    // MARK: - Pass Play

    private static func simulatePassPlay(
        offensePlayers: [SimPlayer],
        defensePlayers: [SimPlayer],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        momentum: Double,
        playNumber: Int,
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil,
        hint: OffensivePlayCall.SimulatorHint? = nil,
        defensivePackage: DefensivePackage? = nil,
        weather: GameWeather? = nil,
        adjustments: Adjustments? = nil,
        runKeyIntensity: Double = 0,
        // Layer B (PLAY-MEMORY): per-depth completion shift, already net-signed
        // and malus-capped by the engine. (0,0,0) = identity → parity intact.
        passCompletionDelta: (short: Double, mid: Double, deep: Double) = (0, 0, 0),
        // Round 4 (mental states): offense-relative score margin for leverage.
        // 0 = parity.
        scoreDifferential: Int = 0
    ) -> PlayResult {
        let qb = findQB(in: offensePlayers)
        let qbAttrs = qbAttributes(for: qb)
        let momentumBoost = momentum * 0.05
        // P0-2: team-breadth diminishing-returns scale, computed once and applied to
        // EVERY talent-differential channel below (sack, QB completion, matchup/deep
        // edges, INT). 1.0 at parity / single-unit mismatch; shrinks on a whole-team
        // mismatch. Scaling one channel is not enough — the talent signal is spread
        // across all of them, so the compression must be comprehensive to bite.
        // Garbage-time damp folds in here: a team already up multi-scores late coasts
        // (backups, vanilla calls, prevent looks the other way), so LESS of its talent
        // edge is deployed — capping the tail through the same plumbing.
        var edgeScale = edgeCompressionScale(offense: offensePlayers, defense: defensePlayers)
        edgeScale *= garbageEdgeFactor(scoreDifferential: scoreDifferential, quarter: quarter,
                                       timeRemaining: timeRemaining)

        // Scheme fit modifiers: offensive scheme boosts/penalizes yards, defensive scheme reduces them
        let offSchemeFit = schemeFitModifier(
            players: offensePlayers,
            offensiveScheme: offensiveScheme,
            defensiveScheme: nil
        )
        let defSchemeFit = schemeFitModifier(
            players: defensePlayers,
            offensiveScheme: nil,
            defensiveScheme: defensiveScheme
        )

        // --- Play-Action Read (R37, live calls only) ---
        // The fake's value depends on the second level's football IQ: a
        // low-awareness box bites downhill (the deep shot opens), a veteran
        // box passes it off (the window shrinks). Rolled once per snap; the
        // result also drives the 3D linebacker choreography via
        // `PlayResult.defenseBitOnFake`. Nil hint (all quick sims) = never.
        var paBite: Bool? = nil
        var paBiteActive = hint?.isPlayAction == true
        #if DEBUG
        if debugNeutralPlayActionRead { paBiteActive = false }
        #endif
        if paBiteActive {
            let boxAwareness = averageAttribute(
                defensePlayers.filter { isLB($0) || $0.position == .SS || $0.position == .FS },
                extractor: { Double($0.mental.awareness) }
            )
            // A3 (Layer A RPS): an over-committed, run-keyed box bites the fake
            // far harder — the whole point of play-action is to punish a defense
            // that has sold out to stop the run. Push the bite probability up by
            // the key intensity (base 0.5 → ~0.9 at full key). 0 intensity = the
            // old symmetric ~50% bite, so an un-keyed defense is unchanged.
            let biteChance = clamp(0.5 + (70.0 - boxAwareness) * paBiteAwarenessSlope
                                   + runKeyIntensity * 0.4,
                                   min: 0.05, max: 0.95)
            paBite = randomChance(biteChance)
        }

        // --- Pass Protection Check ---
        let olPassBlock = averageAttribute(
            offensePlayers.filter { isOL($0) },
            extractor: { olPassBlockRating(for: $0) }
        )
        let dlPassRush = averageAttribute(
            defensePlayers.filter { isDL($0) },
            extractor: { dlPassRushRating(for: $0) }
        )
        // Add LB blitz pressure — B3a: ONLY when the defense actually blitzed.
        // A no-blitz front (or the nil quick-sim package) previously levied a
        // phantom ~21-pt rush term on EVERY dropback, which is the bulk of the
        // ~24% baseline sack rate. Gate it on a real blitz call so base fronts
        // don't send a phantom rusher.
        let isBlitzing = defensivePackage.map { $0.blitz != .noBlitz } ?? false
        let lbBlitz = averageAttribute(
            defensePlayers.filter { isLB($0) },
            extractor: { lbBlitzRating(for: $0) }
        ) * 0.3 * (isBlitzing ? 1.0 : 0.0)

        // P0-2: compress the OL−DL talent net (momentum / blitz stay full-weight).
        let protectionRating = (olPassBlock - dlPassRush) * edgeScale + momentumBoost * 100 - lbBlitz
        // B3b: re-base the sack curve. base 0.20→0.07 (equal-talent no-blitz ≈7%),
        // floor 0.05→0.02 (a clean pocket can be near-sackless). Ceiling unchanged.
        var sackChance = max(0.02, min(0.35, 0.07 - protectionRating / 500.0))

        // Mech 2: a mobile, poised QB slides pressure and escapes the pocket —
        // scrambling + pocket presence buy him out of the sack. A statue QB
        // (below the 50/50 pivot) earns nothing. Shared, so quick sim and the
        // live engine get it identically.
        sackChance = max(0.02, sackChance - qbMobilitySackReduction(qbAttrs))

        // R39 trench matchup (mech 2a strength + mech 1a acceleration): a
        // stronger OL holds the pocket (−sack); a quicker DL first step off the
        // snap gets home faster (+sack). Both differentials are near-zero mean
        // league-wide (see `relativeAcceleration`), so the league sack rate holds
        // while the individual trench matchup separates. Shared path →
        // quick sim and the live engine get it identically.
        let olLinemen = offensePlayers.filter { isOL($0) }
        let dlLinemen = defensePlayers.filter { isDL($0) }
        let olStrength = averageAttribute(olLinemen, extractor: { relativeStrength($0) })
        let dlStrength = averageAttribute(dlLinemen, extractor: { relativeStrength($0) })
        let olAccel = averageAttribute(olLinemen, extractor: { relativeAcceleration($0) })
        let dlAccel = averageAttribute(dlLinemen, extractor: { relativeAcceleration($0) })
        sackChance = clamp(sackChance
                           - strengthTrenchSackReduction(olStrength: olStrength, dlStrength: dlStrength)
                           + accelPassRushBonus(dlAccel: dlAccel, olAccel: olAccel),
                           min: 0.02, max: 0.60)

        // Live play-call adjustments (nil hint + nil package = identical to today):
        // quick-timing throws pick up the blitz; blitz packages add pressure.
        if hint != nil || defensivePackage != nil {
            let blitzPickup = (hint?.blitzPickupBonus ?? 0) * 0.15
            let extraPressure = defensivePackage?.totalPressureModifier ?? 0
            sackChance = clamp(sackChance - blitzPickup + extraPressure, min: 0.02, max: 0.60)
        }

        // Halftime adjustment: extra protection emphasis keeps the QB clean.
        if let adjustments, adjustments.sackChanceReduction != 0 {
            sackChance = clamp(sackChance - adjustments.sackChanceReduction, min: 0.02, max: 0.60)
        }

        if randomChance(sackChance) {
            let sackYards = -Int.random(in: 3...8)
            let newYardLine = max(0, yardLine + sackYards)

            // R37: name the man who got home — the description, box score,
            // and the 3D pocket collapse all point at the same rusher.
            let sacker = weightedPickBy(passRushPool(defensePlayers)) {
                let score = passRushScore($0)
                return score * score
            }

            // Check for safety
            if newYardLine <= 0 {
                var play = PlayResult(
                    playNumber: playNumber,
                    quarter: quarter,
                    timeRemaining: timeRemaining,
                    down: down,
                    distance: distance,
                    yardLine: yardLine,
                    playType: .pass,
                    outcome: .safety,
                    yardsGained: sackYards,
                    description: sacker.map {
                        "\(qb.fullName) is sacked in the end zone by \($0.fullName) for a safety!"
                    } ?? "\(qb.fullName) is sacked in the end zone for a safety!",
                    isFirstDown: false,
                    isTurnover: false,
                    scoringPlay: true,
                    pointsScored: 2,
                    keyOffensePlayerID: qb.id,
                    keyDefensePlayerID: sacker?.id
                )
                play.defenseBitOnFake = paBite
                return play
            }

            var play = PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .pass,
                outcome: .sack,
                yardsGained: sackYards,
                description: sackDescription(qb: qb, sacker: sacker, yards: abs(sackYards)),
                isFirstDown: false,
                isTurnover: false,
                scoringPlay: false,
                pointsScored: 0,
                keyOffensePlayerID: qb.id,
                keyDefensePlayerID: sacker?.id
            )
            play.defenseBitOnFake = paBite
            return play
        }

        // --- Choose Target ---
        let receivers = eligibleReceivers(from: offensePlayers)
        guard let target = weightedReceiverSelection(receivers, qb: qb) else {
            // No eligible receivers; QB scrambles
            return simulateQBScramble(
                qb: qb,
                qbAttrs: qbAttrs,
                down: down,
                distance: distance,
                yardLine: yardLine,
                quarter: quarter,
                timeRemaining: timeRemaining,
                momentum: momentum,
                playNumber: playNumber
            )
        }

        // --- Pass Distance ---
        // An explicit play call fixes the depth; otherwise roll it as before.
        let passDistance: PassDistance
        switch hint?.passDepth {
        case .short:  passDistance = .short
        case .medium: passDistance = .mid
        case .deep:   passDistance = .deep
        case nil:     passDistance = choosePassDistance(distance: distance, yardLine: yardLine)
        }
        // A0 (Balance R3): the assigned cover defender for THIS target + how
        // man-oriented the called shell is. Computed once; feeds the deep
        // composite (A1-deep), the short/mid matchup edge (A1), and the INT
        // ball-hawk blend (A2-pass). At all-70 the assigned man == the unit
        // average == 70, so every blend collapses to today's value (parity).
        let coverManWeight = coverageManWeight(defensivePackage)
        let coverMan = coverAssignment(for: target, offense: offensePlayers,
                                       defense: defensePlayers, package: defensivePackage)

        // DEEP-TALENT: the deep composite edge (offense deep-threat − DB deep
        // defense), 0-centered at all-70. Drives the deep completion, the deep
        // air-yards ride, and the keyed-punish scaler below. Computed once;
        // only READ on the .deep branch, so short/mid are byte-untouched.
        let deepEdge = deepCompositeEdge(qb: qb, target: target, defensePlayers: defensePlayers,
                                         coverMan: coverMan, manWeight: coverManWeight) * edgeScale
        var targetYards = passYardsForDistance(passDistance)
        if passDistance == .deep {
            // Composite air ride: an elite duo pushes the bomb deeper (bigger
            // house calls), a weak one is floored. Re-centers neutral deep EV.
            targetYards = max(deepAirFloor,
                              targetYards + Int((deepEdge * deepAirSlope).rounded()))
        }

        // A3 (Layer A RPS punish): the SAME key intensity that suppresses the
        // run REWARDS the shot plays that punish an over-committed box — a
        // play-action call or a straight deep shot. This closes the RPS
        // triangle: keying the run hard opens the deep ball, so run-keying is a
        // real trade, not a blind nerf. Gated on the shot plays only (and on a
        // live/simmed key), so a balanced offense — which never builds key
        // intensity — is untouched. DEEP-TALENT rebase: the keyed bonus scales
        // with `deepPunishScale` (the deep composite), so an elite deep duo
        // torches a stacked box, a 70/70 duo only nicks it, and a weak duo
        // cannot. `paKeyAirBonus` rides into the caught-ball yardage below; the
        // completion bump is applied after the PA swing.
        let paPunishActive = runKeyIntensity > 0
            && (hint?.isPlayAction == true || passDistance == .deep)
        let deepPunishScale = clamp(1.0 + deepEdge * deepPunishEdgeSlope,
                                    min: deepPunishScaleMin, max: deepPunishScaleMax)
        let paKeyAirBonus = paPunishActive
            ? Int((AdaptiveOpponentAI.paKeyBigPlay(runKeyIntensity) * deepPunishScale).rounded())
            : 0

        // Round 4 (mental states): the situational leverage index for THIS snap
        // (Q4/OT, red zone, 3rd/4th-and-medium, two-minute, trailing big).
        // 0 on a neutral early-down snap → composure inert (parity). Scales the
        // composure swing on QB accuracy (below) and the mental completion delta.
        let lev = leverageIndex(down: down, distance: distance, quarter: quarter,
                                timeRemaining: timeRemaining, yardLine: yardLine,
                                scoreDifferential: scoreDifferential)

        // --- Accuracy & Openness Check ---
        // Mech 3: arm strength lifts the deep-ball accuracy (±cap points).
        var accuracyRating = qbAccuracyForDistance(qbAttrs, distance: passDistance)
        if passDistance == .deep {
            accuracyRating += armDeepAccuracyBonus(qbAttrs)
        }
        // Round 4 (mental states): composure is now a two-sided SWING scaled by
        // the situational leverage, replacing the old downside-only Q4/red-zone
        // penalty. accuracyRating feeds both the completion odds (short/mid, via
        // qbBase) and the interception roll, so a rattled passer both misses more
        // AND forces a few more picks (the preserved two-for-one); a clutch passer
        // gets the mirror up-side (the old Q4 clutch boost in applyMoraleModifiers
        // stays the separate baseline modulator). Composure 70 @ any leverage →
        // swing 0 → byte-identical to today. Shared path → quick sim and the live
        // engine get it alike.
        accuracyRating += composureSwing(qb, lev) * composureAccuracyGain
        // Mech 3 (presentation): the 3D flight-speed multiplier for this QB.
        let velocityScale = armVelocityScale(qbAttrs)

        // Mech 5: getting OPEN is route work — the openness roll uses
        // separation (route running), not hands. Hands come back in the catch
        // phase below (drop when open, contested grab when covered). The
        // debug-neutral switch restores the pre-R38 catching-blended openness
        // exactly, so the balance harness can isolate this mechanic.
        var useSeparationOpenness = true
        #if DEBUG
        if debugNeutralContestedDrop { useSeparationOpenness = false }
        #endif
        var opennessAttr = useSeparationOpenness
            ? receiverSeparationRating(for: target)
            : receiverCatchRating(for: target)
        // R39 mech 3 (agility): a receiver's change-of-direction wins a step of
        // separation on his route (WR/TE). Centered at the 70 mean → comp% holds.
        opennessAttr += agilitySeparationBonus(for: target)
        let dbCoverage = averageAttribute(
            defensePlayers.filter { isDB($0) },
            extractor: { dbCoverageRating(for: $0) }
        )

        // A0/A1 (Balance R3): the assigned-cover blend + the WR-vs-assignedCB
        // matchup edge. `coverBlend` is the DB unit coverage blended toward the
        // assigned man by the shell's man-weight; at all-70 both are 70, so the
        // blend is 70 and the edge is 0 (neutral parity). The edge carries the
        // WR route quality vs the ACTUAL cover man — a shutdown CB1 on WR1 bites,
        // an LB-covered TE/RB opens up (LB coverage ≪ CB coverage).
        let coverBlend = dbCoverage * (1.0 - coverManWeight) + coverMan.coverage * coverManWeight
        var matchupEdge = opennessAttr - coverBlend
        matchupEdge = clamp(matchupEdge, min: -matchupEdgeCapRaw, max: matchupEdgeCapRaw) * edgeScale

        // A1b (Balance R3): a small bounded matchup air ride for short/mid — an
        // elite duo pushes the catch a hair deeper than YAC alone, a mismatch
        // shortens it. Floored per depth; deep keeps its own (larger) ride above.
        if passDistance != .deep {
            targetYards = max(shortMidAirFloor(passDistance),
                              targetYards + Int((matchupEdge * shortMidAirSlope).rounded()))
        }

        // A1 (Balance R3): short/mid completion = base + QB (accuracy + reading)
        // + the matchup edge, mirroring the shipped deep composite (base +
        // asymmetric edge). The WR quality lives in the EDGE (not a saturating
        // additive base), so the duel is not swallowed behind an elite QB; the QB
        // lives in its own 70-centered term. .deep is byte-unchanged (its own
        // composite). The grand soft-cap is applied once at the very end, after
        // every downstream completion mod (replacing the old hard 0.15…0.85 wall).
        // Round 4 (mental states): the ONE bounded mental completion term, folded
        // in BESIDE momentumBoost so it composes through the same clamp/soft-cap
        // stack. It is heat (form) + composure (poise), each per-player:
        //   • a HOT WR wins more 50/50s (target.heat, full points);
        //   • a hot QB is dialed in (qb.heat, smaller);
        //   • a hot CB tightens the window (−coverMan.heat) — the DB's heat IS his
        //     coverage effect, so no separate coverage-composite edit;
        //   • composure adds the poise swing (target + half the QB), leverage-scaled.
        // Every term is `heat * points * heatEffectScale`, so heat 0 (or an immune
        // archetype) and composure 70 ⇒ 0 (parity). The sum is clamped to its own
        // dedicated grand cap, a third lane parallel to the play-memory malus cap
        // and the defensive-bite cap — stacking is intended, each independently
        // bounded, and short/mid additionally sit under `softCapCompletion`.
        let composureTerm = (composureSwing(target, lev)
                             + 0.5 * composureSwing(qb, lev)) * composureSwingSlope
        let heatShortMidTerm = target.heat * heatPassCompletionPoints * target.heatEffectScale
            + qb.heat * heatQBCompletionPoints * qb.heatEffectScale
            - coverMan.heatContribution * heatDBCompletionPoints
        let heatDeepTerm = target.heat * heatDeepCompletionPoints * target.heatEffectScale
            + qb.heat * heatDeepCompletionPoints * qb.heatEffectScale
        let mentalPassDelta = clamp(heatShortMidTerm + composureTerm,
                                    min: -mentalCompletionCap, max: mentalCompletionCap)
        let mentalDeepDelta = clamp(heatDeepTerm + composureTerm,
                                    min: -mentalCompletionCap, max: mentalCompletionCap)

        var completionChance: Double
        switch passDistance {
        case .short, .mid:
            let base70 = passDistance == .short ? shortBaseCompletion : midBaseCompletion
            let qbBase = base70
                + (accuracyRating - 70.0) * qbAccCompSlope * edgeScale
                + (completionReadingAttr(for: qb) - 70.0) * qbReadCompSlope * edgeScale
            completionChance = qbBase + matchupEdgeCompletion(matchupEdge) + momentumBoost + mentalPassDelta
        case .deep:
            completionChance = clamp(deepBaseCompletion + deepEdgeCompletion(deepEdge) + momentumBoost + mentalDeepDelta,
                                     min: 0.05, max: 0.90)
        }

        // Layer B (PLAY-MEMORY): the depth-matched completion shift from the
        // coached read (category malus + exact-call malus − counter-open bonus,
        // pre-summed and clamped by `passTotalMalusCap` in the engine). Identity
        // (0) for a mixed caller and for every quick-sim / sim snap, so parity
        // holds. Sits right on the depth curve so it composes with B5.
        let memPassDelta: Double
        switch passDistance {
        case .short: memPassDelta = passCompletionDelta.short
        case .mid:   memPassDelta = passCompletionDelta.mid
        case .deep:  memPassDelta = passCompletionDelta.deep
        }
        if memPassDelta != 0 {
            completionChance = clamp(completionChance + memPassDelta, min: 0.05, max: 0.95)
        }

        // Defensive package: tighter coverage shaves the completion odds.
        if let package = defensivePackage {
            completionChance = clamp(completionChance - package.totalCoverageModifier, min: 0.05, max: 0.95)

            // Depth-shaded shells (live games only): a prevent look takes
            // away the deep shot but hands the checkdown out for free.
            let depthShade: Double
            switch passDistance {
            case .deep:  depthShade = package.totalDeepCoverageModifier
            case .short: depthShade = package.totalShortCoverageModifier
            case .mid:   depthShade = 0
            }
            if depthShade != 0 {
                completionChance = clamp(completionChance - depthShade, min: 0.05, max: 0.95)
            }
        }

        // ROUND-6 weak-floor taper: partially offset P0-1's flat de-inflation for a
        // below-average MATCHUP (warm) / relax the elite tail (cool). Keyed on the
        // combined on-field mean overall; exactly 0 in the calibrated [70,85] middle,
        // so the all-70 probe, the avg/good tiers, and every mismatch that averages
        // into the middle are byte-untouched. Applied AFTER the coverage tax (it is
        // relief FROM that tax) and before the soft cap, so a warmed weak completion
        // still rides the same ceiling curve. The one-tier UNDERDOG relief (item 2)
        // rides alongside it, keyed on the SIGNED gap; both share the two team means.
        let offMeanOverall = averageAttribute(offensePlayers, extractor: { Double($0.overall) })
        let defMeanOverall = averageAttribute(defensePlayers, extractor: { Double($0.overall) })
        let floorComp = floorTaperCompletion(combinedMean: (offMeanOverall + defMeanOverall) / 2.0)
            + underdogReliefCompletion(offenseMean: offMeanOverall, defenseMean: defMeanOverall)
        if floorComp != 0 {
            completionChance = clamp(completionChance + floorComp, min: 0.05, max: 0.95)
        }
        // Item 3: situational 3rd-down stiffening — trims good/elite 3rd-down
        // conversion (≤47) without touching general scoring. Byte-zero at all-70 /
        // avg / weak (combined ≤ 80) and off 3rd down, so per-play parity holds.
        if down == 3 {
            let cm3 = (offMeanOverall + defMeanOverall) / 2.0
            if cm3 > thirdDownPivot {
                let cool = Swift.min(thirdDownStiffenCap, (cm3 - thirdDownPivot) * thirdDownStiffen)
                completionChance = clamp(completionChance - cool, min: 0.05, max: 0.95)
            }
        }

        // Mech 4: WR release vs DB press on man-press SHORT throws (live games
        // only — quick sim passes no package, so it never fires there). A WR
        // who beats the jam gets a cleaner window; a good press corner erases
        // it. Near-zero mean (release ≈ press league-wide) so it never shifts
        // the completion rate — it only rewards the individual matchup.
        // `isManCoverage` (not an identity check on `.manToMan`) so the new
        // zero-help man shell gets the same press/release treatment; the new
        // ZONE shells (tampa2/cover6) correctly stay out of this branch.
        if let package = defensivePackage,
           package.coverage.isManCoverage, passDistance == .short {
            let dbs = defensePlayers.filter { isDB($0) }
            let press = averageAttribute(dbs, extractor: { dbPressRating(for: $0) })

            // R38 mech 4: release TECHNIQUE vs press technique.
            var wrPressActive = true
            #if DEBUG
            if debugNeutralWRPress { wrPressActive = false }
            #endif
            if wrPressActive {
                let release = receiverReleaseRating(for: target)
                let mod = clamp((release - press) / wrPressDivisor, min: -wrPressCap, max: wrPressCap)
                completionChance = clamp(completionChance + mod, min: 0.05, max: 0.95)
            }

            // R39 mech 1b: the WR's BURST off the jam (acceleration) vs the
            // corner's burst. Near-zero mean — rewards the individual matchup.
            let releaseBurst = accelReleaseBonus(
                wrAccel: relativeAcceleration(target),
                cbAccel: averageAttribute(dbs, extractor: { relativeAcceleration($0) })
            )
            if releaseBurst != 0 {
                completionChance = clamp(completionChance + releaseBurst, min: 0.05, max: 0.95)
            }

            // R39 mech 2c: the corner's physical JAM (strength) disrupts the
            // release. Near-zero mean.
            let jam = strengthPressDisruption(
                cbStrength: averageAttribute(dbs, extractor: { relativeStrength($0) }),
                wrStrength: relativeStrength(target)
            )
            if jam != 0 {
                completionChance = clamp(completionChance - jam, min: 0.05, max: 0.95)
            }
        }

        // Weather: a wet ball slips through hands (rain/snow), and gusts
        // knock down the deep ball (wind). nil/.clear = today's odds exactly.
        switch weather {
        case .rain, .snow:
            completionChance = clamp(completionChance - 0.05, min: 0.05, max: 0.95)
        case .wind where passDistance == .deep:
            completionChance = clamp(completionChance - 0.08, min: 0.05, max: 0.95)
        default:
            break
        }

        // Play action (R37): a box that bit on the fake vacates the middle —
        // the window opens; a box that stayed home squeezes it. Symmetric
        // swing (±paBiteCompletionSwing) so a league-average box (bite ~50%)
        // leaves the play's expected value unchanged.
        if let paBite {
            let swing = paBite ? paBiteCompletionSwing : -paBiteCompletionSwing
            completionChance = clamp(completionChance + swing, min: 0.05, max: 0.95)
        }

        // A3 (Layer A RPS punish): a run-keyed box has vacated the deep third —
        // the shot play completes more often (up to +0.18 at full key) on top of
        // the extra air yards (`paKeyAirBonus`). Only the shot plays, only vs a
        // keyed defense; an un-keyed snap (intensity 0) adds exactly nothing.
        if paPunishActive {
            completionChance = clamp(
                completionChance + AdaptiveOpponentAI.paKeyCompletion(runKeyIntensity) * deepPunishScale,
                min: 0.05, max: 0.95)
        }

        // Halftime adjustment: schemed separation lifts the completion odds.
        if let adjustments, adjustments.completionBonus != 0 {
            completionChance = clamp(completionChance + adjustments.completionBonus, min: 0.05, max: 0.95)
        }

        // B1 (Balance R3): the SCHEME-FAMILIARITY completion shift. A well-drilled
        // offense executes the concept a beat cleaner (the window opens → more
        // catches); a raw one plays a step slow. The defense's own knowledge
        // shrinks that window. `famCurve` pivots at the seeded-league mean (70), so
        // a neutral matchup adds exactly 0 (parity); a nil scheme (quick sim /
        // neutral harness) collapses both sides to the pivot → 0. Player-only
        // channel (coachExpertise nil); the coordinator's own completion edge stays
        // the separate mech-6 lane. Applied to every depth, before the soft-cap.
        let offFam = effectiveSquadFam(offensePlayers, scheme: offensiveScheme?.rawValue)
        let defFam = effectiveSquadFam(defensePlayers, scheme: defensiveScheme?.rawValue)
        let famShift = famCurve(offFam) - famCurve(defFam)
        if famShift != 0 {
            completionChance = clamp(completionChance + famShift, min: 0.05, max: 0.95)
        }

        // A1 (Balance R3): the grand soft-cap for short/mid — the single ceiling,
        // applied ONCE after every downstream completion mod. Linear below the
        // knee (neutral is untouched), exponential approach to the ceiling above
        // (elite duos climb without the old hard 0.85 wall). Deep owns its own
        // ceiling upstream, so it is left exactly as today.
        if passDistance != .deep {
            completionChance = softCapCompletion(completionChance)
        }

        // B2 (Balance R3): the BLOWN-ASSIGNMENT bust — the true negative play that
        // makes low familiarity BITE beyond the completion shift. Weighted to the
        // ball-carrier's OWN familiarity (the guy running the route busts it, not
        // the team mean). Pivot 55 < the seeded mean → a neutral squad NEVER busts,
        // and the `> 0` guard means the roll draws NO RNG at neutral (byte-parity).
        //   • OFFENSE bust → a forced incompletion (miscommunication / bad timing),
        //     pre-empting the INT + catch rolls ("still learning the playbook").
        //   • DEFENSE bust → a blown coverage: the target comes wide open, forcing a
        //     clean completion (pre-empts the pick — nobody was there to catch it).
        let offBustChance = familiarityBustChance(carrier: target, squad: offensePlayers,
                                                  scheme: offensiveScheme?.rawValue)
        if offBustChance > 0, randomChance(offBustChance) {
            var play = PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .pass,
                outcome: .incompletion,
                yardsGained: 0,
                description: "\(qb.fullName) and \(target.fullName) aren't on the same page — the timing's off, incomplete.",
                isFirstDown: false,
                isTurnover: false,
                scoringPlay: false,
                pointsScored: 0,
                keyOffensePlayerID: target.id
            )
            play.defenseBitOnFake = paBite
            play.passVelocityScale = velocityScale
            // Choreography surface (additive, no sim effect): the man who blew it
            // is the target whose familiarity drove the roll — the 3D field breaks
            // HIS route off early and lets the ball go where it should have been.
            play.bustKind = .route
            play.bustPlayerID = target.id
            return play
        }
        let defBustChance = squadBustChance(defensePlayers, scheme: defensiveScheme?.rawValue)
        if defBustChance > 0, randomChance(defBustChance) {
            // Blown coverage — the receiver is uncovered, so it is a clean grab,
            // but bounded (round-5 P1): a coverage bust is a chunk gain, not a free
            // deep TD. `famDefBustYardCap` mirrors the offense bust's 0-yard floor.
            var play = makeCatch(contested: false, yardCap: famDefBustYardCap)
            // Squad-wide roll — the sim names no defender, so the choreographer
            // stages the man the coverage assignment already penalizes (the
            // target's cover man). No player id here on purpose.
            play.bustKind = .coverage
            return play
        }

        // --- Interception Check ---
        // A2-pass (Balance R3): blend the DB unit ball-skills toward the ASSIGNED
        // cover man so a ball-hawk CB1 on WR1 adds real INT risk on that target;
        // an LB-covered TE/RB (nil assignedBallSkills) falls back to the unit
        // value. At all-70 the assigned man == unit == 70 → parity holds.
        let dbUnitBallSkills = averageAttribute(
            defensePlayers.filter { isDB($0) },
            extractor: { dbBallSkillsRating(for: $0) }
        )
        let dbBallSkillsBlended = coverMan.ballSkills.map {
            dbUnitBallSkills * (1.0 - coverManWeight) + $0 * coverManWeight
        } ?? dbUnitBallSkills
        let intChance = interceptionChance(
            accuracyRating: accuracyRating,
            dbBallSkills: dbBallSkillsBlended,
            passDistance: passDistance,
            decisionMaking: qb.mental.decisionMaking,
            pressure: sackChance,
            edgeScale: edgeScale
        )

        if randomChance(intChance) {
            // Credit a ball-hawking starter, not a random 4th-string DB —
            // the live match view shows the top DBs on the field.
            // R37: the catch-vs-knockdown call goes to the DB whose HEAD and
            // HANDS earn it — awareness (route recognition) + ball skills
            // weighted, so the smart safety picks it more often. The total
            // INT rate (`intChance`, rolled above) is untouched; only the
            // per-player credit distribution moves.
            let dbs = defensePlayers.filter { isDB($0) }
            let defender: SimPlayer
            var useIQCredit = true
            #if DEBUG
            if debugNeutralINTCredit { useIQCredit = false }
            #endif
            if useIQCredit {
                let ranked = dbs.sorted { intCreditScore($0) > intCreditScore($1) }
                defender = weightedPickBy(Array(ranked.prefix(5))) {
                    let score = intCreditScore($0)
                    return score * score
                } ?? defensePlayers.first!
            } else {
                defender = dbs
                    .sorted { dbBallSkillsRating(for: $0) > dbBallSkillsRating(for: $1) }
                    .prefix(4).randomElement() ?? defensePlayers.first!
            }
            var play = PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .pass,
                outcome: .interception,
                yardsGained: 0,
                description: "\(qb.fullName) is intercepted by \(defender.fullName)!",
                isFirstDown: false,
                isTurnover: true,
                scoringPlay: false,
                pointsScored: 0,
                keyOffensePlayerID: target.id,
                keyDefensePlayerID: defender.id
            )
            play.defenseBitOnFake = paBite
            play.defensiveHighlight = true
            play.passVelocityScale = velocityScale
            return play
        }

        // --- Catch phase (R38 mech 5) ---
        // Builds the caught-ball result. A contested grab is a rare win in
        // traffic — caught at the catch point and tackled immediately (no YAC).
        func makeCatch(contested: Bool, yardCap: Int? = nil) -> PlayResult {
            var yacBonus = contested ? 0 : yardsAfterCatch(for: target, momentum: momentum)
            // Play-call YAC shading (screens, flats, go routes) — clean catches only.
            if !contested, let hint = hint {
                yacBonus = max(0, Int((Double(yacBonus) * hint.yacMultiplier).rounded()))
            }
            // A3 (Layer A): a run-keyed box that got beaten over the top gives up
            // extra air yards on the shot play (0 unless the punish is active).
            var totalYards = targetYards + yacBonus + paKeyAirBonus

            // Apply scheme fit modifiers: offense fit boosts yards, defense fit reduces them
            let schemeYardAdjustment = Double(totalYards) * (offSchemeFit - defSchemeFit)
            totalYards += Int(schemeYardAdjustment.rounded())

            // B2 (round-5 P1): OUTCOME cap for the defensive coverage-bust — the
            // symmetric bound to the offense bust's fixed 0-yard incompletion. A
            // blown coverage yields an easy pitch-and-catch chunk, NOT an uncapped
            // walk-in deep bomb; without this the bust leaked ~500 pass-yds/g to a
            // low-fam defense. nil (every other catch path) is unbounded as before.
            if let yardCap { totalYards = Swift.min(totalYards, yardCap) }

            // Cap yards at endzone
            let yardsToEndzone = 100 - yardLine
            if totalYards >= yardsToEndzone {
                totalYards = yardsToEndzone
                var play = PlayResult(
                    playNumber: playNumber,
                    quarter: quarter,
                    timeRemaining: timeRemaining,
                    down: down,
                    distance: distance,
                    yardLine: yardLine,
                    playType: .pass,
                    outcome: .touchdown,
                    yardsGained: totalYards,
                    description: contested
                        ? "\(qb.fullName) throws it up and \(target.fullName) comes down with it in traffic for a TOUCHDOWN!"
                        : "\(qb.fullName) throws \(targetYards) yards to \(target.fullName) for a TOUCHDOWN!",
                    isFirstDown: true,
                    isTurnover: false,
                    scoringPlay: true,
                    pointsScored: 6,
                    keyOffensePlayerID: target.id
                )
                play.defenseBitOnFake = paBite
                play.passVelocityScale = velocityScale
                if contested { play.contestedCatch = true }
                return play
            }

            // Prevent negative total from variance
            totalYards = max(totalYards, 0)
            let gainedFirstDown = totalYards >= distance

            var play = PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .pass,
                outcome: .completion,
                yardsGained: totalYards,
                description: contested
                    ? contestedCatchDescription(qb: qb, target: target, yards: totalYards, firstDown: gainedFirstDown)
                    : completionDescription(qb: qb, target: target, yards: totalYards, firstDown: gainedFirstDown),
                isFirstDown: gainedFirstDown,
                isTurnover: false,
                scoringPlay: false,
                pointsScored: 0,
                keyOffensePlayerID: target.id
            )
            play.defenseBitOnFake = paBite
            play.passVelocityScale = velocityScale
            if contested { play.contestedCatch = true }
            return play
        }

        // Mech 5: split the old single completion roll into (a) getting open,
        // then (b) the catch. Open balls are dropped at a hands-scaled rate;
        // covered balls are occasionally won on a contested grab. Calibrated so
        // the league completion % holds. The debug-neutral switch restores the
        // exact pre-R38 single-roll behavior.
        var contestedDropActive = true
        #if DEBUG
        if debugNeutralContestedDrop { contestedDropActive = false }
        #endif

        let gotOpen = randomChance(completionChance)

        if !contestedDropActive {
            // Pre-R38: open == completion; covered == incompletion.
            if gotOpen { return makeCatch(contested: false) }
        } else if gotOpen {
            // Open, on-target ball — the hands decide.
            if randomChance(dropChance(for: target, edgeScale: edgeScale)) {
                var play = PlayResult(
                    playNumber: playNumber,
                    quarter: quarter,
                    timeRemaining: timeRemaining,
                    down: down,
                    distance: distance,
                    yardLine: yardLine,
                    playType: .pass,
                    outcome: .incompletion,
                    yardsGained: 0,
                    description: dropDescription(qb: qb, target: target),
                    isFirstDown: false,
                    isTurnover: false,
                    scoringPlay: false,
                    pointsScored: 0,
                    keyOffensePlayerID: target.id
                )
                play.defenseBitOnFake = paBite
                play.wasDrop = true
                play.passVelocityScale = velocityScale
                return play
            }
            return makeCatch(contested: false)
        } else {
            // Covered — a rare contested grab still comes down with it.
            let dbBallSkills = averageAttribute(
                defensePlayers.filter { isDB($0) },
                extractor: { dbBallSkillsRating(for: $0) }
            )
            if randomChance(contestedCatchChance(target: target, dbBallSkills: dbBallSkills, edgeScale: edgeScale)) {
                return makeCatch(contested: true)
            }
        }

        // --- Incompletion (covered, no contested win) ---
        do {
            // Incomplete pass — R37 defensive commentary decides the credit:
            // 1) a coverage win becomes a NAMED breakup (light PD stat and a
            //    feed accent), 2) a heavy rush becomes pressure credit on the
            //    hurried throw, 3) a plain miss draws from a variation pool.
            // None of this touches the completion roll above — text and
            // attribution only.
            var text = "\(qb.fullName) throws incomplete intended for \(target.fullName)."
            var breakupID: UUID? = nil
            var wasBreakup = false
            // FIX-2: surface the pressure branch as structured metadata (the
            // rusher the sim already picked, and whether the chosen line was a
            // deliberate throwaway). No new RNG — the flags only record the
            // branch already taken and the already-picked rusher.
            var pressuredRusherID: UUID? = nil
            var wasPressure = false
            var wasThrowawayThrow = false
            let breakupChance = clamp(0.22 + (dbCoverage - 60.0) / 250.0, min: 0.10, max: 0.40)
            if randomChance(breakupChance) {
                // The breakup goes to a coverage man on the field — coverage
                // skill + awareness weighted, same IQ logic as the pick.
                if let defender = weightedPickBy(startingDBs(defensePlayers), weight: {
                    dbCoverageRating(for: $0) * 0.6 + Double($0.mental.awareness) * 0.4
                }) {
                    wasBreakup = true
                    breakupID = defender.id
                    text = breakupDescription(qb: qb, target: target, defender: defender)
                }
            } else if randomChance(min(sackChance * 1.6, 0.35)) {
                // The rush forced the ball out early — credit the man in the
                // QB's face (no sack, no stat, just the broadcast note).
                if let rusher = weightedPickBy(passRushPool(defensePlayers), weight: {
                    let score = passRushScore($0)
                    return score * score
                }) {
                    let pressure = pressureDescription(qb: qb, target: target, rusher: rusher)
                    text = pressure.text
                    wasPressure = true
                    pressuredRusherID = rusher.id
                    wasThrowawayThrow = pressure.isThrowaway
                }
            } else if randomChance(0.35) {
                text = incompletionVariant(qb: qb, target: target)
            }
            var play = PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .pass,
                outcome: .incompletion,
                yardsGained: 0,
                description: text,
                isFirstDown: false,
                isTurnover: false,
                scoringPlay: false,
                pointsScored: 0,
                keyOffensePlayerID: target.id,
                keyDefensePlayerID: breakupID ?? pressuredRusherID
            )
            play.defenseBitOnFake = paBite
            play.passVelocityScale = velocityScale
            if wasBreakup {
                play.passBreakup = true
                play.defensiveHighlight = true
            }
            // FIX-2: the rush forced this ball out. Stat-safe — GameSimulator
            // credits an incompletion PD only when passBreakup == true (not set
            // here), so the captured rusher id adds no box-score stat.
            if wasPressure {
                play.pressured = true
                play.wasThrowaway = wasThrowawayThrow
            }
            return play
        }
    }

    // MARK: - Run Play

    private static func simulateRunPlay(
        offensePlayers: [SimPlayer],
        defensePlayers: [SimPlayer],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        momentum: Double,
        playNumber: Int,
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil,
        hint: OffensivePlayCall.SimulatorHint? = nil,
        // The dialed call, when a coach dialed one — it names the DESIGNED
        // ball-carrier (a keeper is the QB's, an end around the receiver's).
        // nil (quick sim / season sim) → the back, exactly as before.
        call: OffensivePlayCall? = nil,
        defensivePackage: DefensivePackage? = nil,
        weather: GameWeather? = nil,
        adjustments: Adjustments? = nil,
        runKeyIntensity: Double = 0,
        // Layer B (PLAY-MEMORY): extra run bite (yards) + stuff probability from
        // the coached sub-concept / exact-call read. Both 0 = identity → parity.
        runYardDelta: Double = 0,
        runStuffDelta: Double = 0,
        // Round 4 (mental states): offense-relative score margin for leverage.
        // 0 = parity.
        scoreDifferential: Int = 0
    ) -> PlayResult {
        // The man the DESIGN gives it to. Everything below — the yard math, the
        // fumble roll, the play-by-play line, `keyOffensePlayerID` (and through
        // it the box score, the feed and the 3D carrier) — rides this one
        // binding, so a QB sneak is the quarterback's carry and an end around
        // is the receiver's, instead of the back silently collecting stats for
        // a run the coach watched somebody else make.
        let rb = designedCarrier(call: call, in: offensePlayers)
        let rbAttrs = rbAttributes(for: rb)
        let momentumBoost = momentum * 0.05
        // P0-2: team-breadth diminishing-returns scale + garbage-time damp (see
        // simulatePassPlay).
        var edgeScale = edgeCompressionScale(offense: offensePlayers, defense: defensePlayers)
        edgeScale *= garbageEdgeFactor(scoreDifferential: scoreDifferential, quarter: quarter,
                                       timeRemaining: timeRemaining)
        // Fatigue-adjusted carrier speed — used by the edge-crease term (below)
        // and the breakaway foot race (further down); computed once.
        let rbSpeed = effectiveSpeed(rb)

        // Round 4 (mental states): the carrier-only mental run bonus (yards), heat
        // (form) + composure (poise), leverage-scaled. Ball-carrier ONLY — there
        // is deliberately no defensive run heat, keeping the tight inside/edge/stuff
        // bands off the razor's edge. rb.heat 0 (or immune) and composure 70 ⇒ 0
        // (parity). Bounded by its own dedicated grand cap.
        let runLev = leverageIndex(down: down, distance: distance, quarter: quarter,
                                   timeRemaining: timeRemaining, yardLine: yardLine,
                                   scoreDifferential: scoreDifferential)
        let mentalRunBonus = clamp(
            rb.heat * heatRunYardPoints * rb.heatEffectScale
                + composureSwing(rb, runLev) * composureRunSlope,
            min: -mentalRunYardCap, max: mentalRunYardCap)

        // Scheme fit modifiers
        let offSchemeFit = schemeFitModifier(
            players: offensePlayers,
            offensiveScheme: offensiveScheme,
            defensiveScheme: nil
        )
        let defSchemeFit = schemeFitModifier(
            players: defensePlayers,
            offensiveScheme: nil,
            defensiveScheme: defensiveScheme
        )

        // --- Run Blocking vs Defensive Front ---
        // B7: average the trench over the STARTING units (best-per-spot), not the
        // whole roster. A deep OL bench inflated the OL run-block mean vs a thinner
        // DL bench (OL≈78 vs DL≈69 on real depth charts), handing the offense a free
        // ~+0.27 yд/run blueprint bias. On the field only the starters block.
        let olRunBlock = averageAttribute(
            startingOL(offensePlayers),
            extractor: { olRunBlockRating(for: $0) }
        )
        let dlBlockShed = averageAttribute(
            startingDL(defensePlayers),
            extractor: { dlBlockSheddingRating(for: $0) }
        )
        let lbTackling = averageAttribute(
            startingLBs(defensePlayers),
            extractor: { lbTacklingRating(for: $0) }
        )

        let trenchBase = (olRunBlock - (dlBlockShed * 0.6 + lbTackling * 0.4)) / 100.0

        // R39 mech 2a (strength trench, run side): a stronger OL moves the DL
        // off the ball. Near-zero mean → the league rushing average holds.
        let strengthCrease = strengthTrenchRunBonus(
            olStrength: averageAttribute(offensePlayers.filter { isOL($0) },
                                         extractor: { relativeStrength($0) }),
            dlStrength: averageAttribute(defensePlayers.filter { isDL($0) },
                                         extractor: { relativeStrength($0) })
        )

        // A2-run (Balance R3): `creaseQuality` is the pure OL-vs-front crease
        // (trench + strength), 0-centered at neutral OL and INDEPENDENT of the
        // play-design gap bonus — so a bad line reads as a bad crease on every
        // play type (an inside run's +0.15 gap bonus no longer masks a poor OL).
        // This is what GATES the breakaway (a burner still needs a hole). The
        // gap bonus rides only into the YARD LEVER via `blockingAdvantage`.
        let creaseQuality = trenchBase + strengthCrease

        var blockingAdvantage = creaseQuality
        // Play-call gap bonus (interior power runs, QB sneak) shades blocking.
        if let hint = hint {
            blockingAdvantage += hint.runGapBonus
        }
        // P0-2: team-breadth diminishing-returns on the run yard lever (breakaway /
        // edge gates keep the raw crease, so single-unit OL signatures survive).
        blockingAdvantage *= edgeScale

        // --- Base Yards ---
        // B1c (harness-dialed): the design's start point 0.5…5.5 (mean 3.0)
        // under-shot — with the centered bonuses (B1a/b) and the 15% negative
        // stuff tail (B1d) it produced only ~3.1 ypc and, because base 0.5
        // rounds to 0/1, inflated the ≤1-yд stuff share to ~30%. The harness
        // dialed the band to 2.0…6.5 (mean 4.25): the floor of 2.0 keeps every
        // non-stuffed carry ≥2 yд (so ≤1-yд stuffs come only from the B1d roll,
        // ~15%), and the higher mean lands the blended run at ~4.3 ypc — both in
        // the NFL band. (Design authorized: "B1c … start points — the harness
        // dials them to the target bands.")
        // A2-run (Balance R3): the OL crease is now the dominant yard lever
        // (`runBlockYardGain` below), so the RNG base band is trimmed to hold the
        // neutral (all-70) mean while the raised lever + crease-gated breakaway
        // give elite OL real yards even behind an average back (fixing the
        // elite-RB-beats-elite-OL inversion). Dial-authorized start point.
        let baseYards = Double.random(in: 2.1...6.4)
        // B1a/B1b: center the vision & elusiveness contributions on the 70-rated
        // league mean. Previously vision/100·2 (+1.4@70) and elusiveness/100·1.5
        // (+1.05@70) stacked an unconditional ~+2.5-yard floor onto every carry;
        // centered on 70 they add 0 at the mean and only separate above/below it.
        let visionBonus = (Double(rbAttrs.vision) - 70.0) / 100.0 * 2.0
        let elusivenessBonus = (Double(rbAttrs.elusiveness) - 70.0) / 100.0 * 1.5
        // R39 carrier bursts — three distinct, non-overlapping athletic traits,
        // each centered at the 70-rated mean so the league rushing average holds
        // while athletic backs separate from plodders:
        //   mech 1c — acceleration: the BURST through the hole (straight-line)
        //   mech 2b — strength + break-tackle: yards THROUGH contact
        //   mech 3  — agility: the open-field JUKE (change of direction)
        let carrierBurst = accelBurstBonus(for: rb)
            + breakTackleBonus(for: rb, attrs: rbAttrs)
            + agilityJukeBonus(for: rb)
        // Halftime adjustment: a run-first commitment adds expected yardage.
        let adjustmentYards = adjustments?.runYardageBonus ?? 0
        // A2-run-edge (Balance R3 fix): perimeter runs (stretch/toss/jet) lost
        // their old RB-speed contribution in the round-3 crease rebalance, which
        // dropped them well below the league edge-run average. Give it back as an
        // EDGE-CREASE term — extra perimeter yards that still GATE on the blocking
        // crease (`creaseQuality`, the same pure-OL lever the breakaway gates on,
        // 0-centered at neutral OL) with the back's SPEED as a multiplier ON that
        // crease. A burner turns a SEALED edge into chunk yards, but a burner
        // behind a BEATEN edge (bad OL → creaseQuality < 0) gets almost nothing —
        // so raw RB speed can never again swamp the OL (it is a multiplier on the
        // crease, not a free breakaway race). `edgeFactor` is 0 for every interior
        // run, so inside runs, the RB×OL ordering cells and the stuff tail are
        // byte-unchanged; this term folds in BEFORE the stuff roll, so a stuffed
        // edge run correctly discards it. Added inside the single rounding.
        let edgeContribution: Double = {
            let edgeFactor = hint?.edgeFactor ?? 0
            guard edgeFactor > 0 else { return 0 }
            let edgeSpeed = clamp(1.0 + (rbSpeed - 70.0) * edgeSpeedSlope,
                                  min: edgeSpeedMin, max: edgeSpeedMax)
            let edgeGate = clamp(1.0 + creaseQuality * edgeCreaseSlope,
                                 min: edgeCreaseMin, max: edgeCreaseMax)
            return edgeBaseYards * edgeFactor * edgeSpeed * edgeGate
        }()
        // P0-2: the 0-centered carrier bonuses (vision / elusiveness / burst) are
        // talent deviations too, so they ride the same team-breadth compression.
        let carrierTalent = (visionBonus + elusivenessBonus + carrierBurst) * edgeScale
        // ROUND-6 weak-floor taper: a per-carry yard warm for a below-average MATCHUP
        // (a weak run game is starved at low talent) / a trim for the elite tail; 0 in
        // the calibrated [70,85] middle, so the all-70 run bands and every mismatch are
        // untouched. A stuffed carry (below) overrides totalYards, so it never un-stuffs.
        let floorRun = floorTaperRunYards(combinedMean: combinedFieldMean(offense: offensePlayers, defense: defensePlayers))
        var totalYards = Int((baseYards + carrierTalent + blockingAdvantage * runBlockYardGain + edgeContribution + momentumBoost * 2.0 + adjustmentYards + mentalRunBonus + floorRun).rounded())

        // Apply scheme fit modifiers: offense fit boosts yards, defense fit reduces them
        let schemeYardAdjustment = Double(totalYards) * (offSchemeFit - defSchemeFit)
        totalYards += Int(schemeYardAdjustment.rounded())

        // Defensive package: run-stopping fronts subtract expected yardage.
        // B2b: accumulate the bite in Double at scale 15.0 (was Int(runStop·6.0),
        // which topped out at ~−1 yд and truncated), rounded once to the carry
        // total — a committed front now actually costs yards: bear 0.14·15≈2.1,
        // goalLine 0.18·15≈2.7. (The Double `runStopBite` is where Layer A folds
        // in `runKeyYardBite(intensity)` before the single rounding.)
        // A2 (Layer A): the always-on run-key yard bite. A defense that has
        // keyed this offense's run tendency shaves the mean by up to ~1.1 yд
        // (scaled by intensity), accumulated in the SAME Double as the called
        // front's run-stop bite and rounded ONCE. This is the mechanically
        // effective adaptation — it bites every keyed snap, not just the rare
        // counter package. At 0 intensity it is exactly 0 (nothing changes).
        // A2 + Layer B: the ADAPTIVE bite is runKey's macro yard-bite PLUS the
        // PLAY-MEMORY sub-concept/exact bite (`runYardDelta`, which counter-open
        // can push negative to LEAN OFF). Their sum is capped by `runGrandBiteCap`
        // — the single fairness gate that keeps a triple-stacked (runKey +
        // category + exact) spammed run a LEAN, never a wall (spammed inside run
        // stays ≥ ~2.2 ypc). The called front's run-stop bite is added AFTER the
        // cap (a defense that also DIALS UP a run front is a separate lever). At
        // runKeyIntensity 0 and runYardDelta 0 this equals runKey's ≤1.1 bite,
        // which is < the 1.8 cap → byte-identical to today (parity intact).
        var adaptiveBite = AdaptiveOpponentAI.runKeyYardBite(runKeyIntensity) + runYardDelta
        adaptiveBite = Swift.min(adaptiveBite, AdaptiveOpponentAI.runGrandBiteCap)
        var runStopBite = adaptiveBite
        if let package = defensivePackage {
            runStopBite += package.totalRunStopModifier * 15.0
        }
        if runStopBite != 0 {
            totalYards -= Int(runStopBite.rounded())
        }

        // B1d: negative-tail stuff roll — restores the NFL ~16-19% stuffed-run
        // rate the old hard positive floor had deleted. Equal talent
        // (dlBlockShed ≈ olRunBlock) ≈ 15%; a dominant front pushes toward the
        // 0.40 cap, a dominant OL toward the 0.04 floor. On a stuff the carry is
        // blown up for a loss-to-short-gain and the breakaway foot race is
        // skipped (you don't house a run you were stuffed on).
        // A2 (Layer A): a keyed defense also generates more stuffs — up to
        // +0.08 probability at full key. Combined with the yard bite, a fully
        // keyed front turns the ~4.3-ypc neutral run into ~2.85 ypc (harness-
        // measured, mid of the 2.5–3.5 band), regressing an all-run offense
        // within ~6 carries as the design requires.
        // Layer B: the coached read adds its own stuff probability (`runStuffDelta`,
        // category + exact) on TOP of runKey's macro stuff bonus; the existing
        // 0.04…0.40 clamp bounds the total. 0 = identity → parity.
        // B2 (Balance R3): the run-side blown-assignment bust folds in here — a
        // missed blocking assignment on a raw offense is a TFL. Weighted to the
        // carrier's OWN scheme familiarity (pivot 55), so a neutral squad adds 0
        // (parity, no new RNG draw) and a raw offense gets stuffed a little more.
        let famRunBust = familiarityBustChance(carrier: rb, squad: offensePlayers,
                                               scheme: offensiveScheme?.rawValue)
        let stuffChance = clamp(0.15 + (dlBlockShed - olRunBlock) / 300.0 * edgeScale
                                + AdaptiveOpponentAI.runKeyStuffBonus(runKeyIntensity)
                                + runStuffDelta
                                + famRunBust,
                                min: 0.04, max: 0.40)
        var runWasStuffed = false
        if randomChance(stuffChance) {
            totalYards = Int.random(in: -3...1)
            runWasStuffed = true
        }
        // Choreography surface (additive, no sim effect): when the carry was
        // stuffed, was the FAMILIARITY term what actually stuffed it?
        //
        // `famRunBust` is one additive slice of `stuffChance` (base front edge
        // + run key + coached read + bust). Conditional attribution: given that
        // a stuff happened, the probability the bust slice is what caused it is
        // exactly `famRunBust / stuffChance` — so rolling that share stamps the
        // blown-block visual at the sim's TRUE bust rate. (Stamping every stuff
        // with famRunBust > 0, as the first cut did, showed a whiffed blocker on
        // ~every stuffed run of any sub-55-familiarity offense, while the bust
        // term itself was worth a percent or two of the ~18% stuff rate — the
        // ordinary "the DL just won" stuff must stay ordinary.) Clamped at 1 for
        // the corner where `stuffChance`'s own 0.04 floor binds below the slice.
        //
        // Determinism: the extra draw happens ONLY inside the stuffed branch and
        // ONLY when the bust term was live at all (famRunBust > 0 — a neutral
        // squad, or a nil scheme, is 0 and draws nothing), which is exactly the
        // set of snaps the old code stamped. Every other path keeps its RNG
        // stream byte-for-byte.
        var runBustBlockerID: UUID? = nil
        if runWasStuffed, famRunBust > 0,
           randomChance(Swift.min(famRunBust / Swift.max(stuffChance, 0.0001), 1.0)) {
            // The blown assignment is the weakest run blocker on the field — the
            // 3D field whiffs HIM and lets his man through untouched.
            runBustBlockerID = startingOL(offensePlayers)
                .min(by: { olRunBlockRating(for: $0) < olRunBlockRating(for: $1) })?.id
        }

        // --- Breakaway Run Check ---
        // R37: the carrier's VISION finds the crease. Vision + awareness
        // scale the breakaway odds around the 70-rated league mean, so the
        // league-wide rushing average holds while individual backs separate.
        // Mech 1: fatigue drags effective speed on the breakaway foot race
        // (rbSpeed computed once up top).
        let avgDBSpeed = averageAttribute(
            defensePlayers.filter { isDB($0) },
            extractor: { effectiveSpeed($0) }
        )
        var visionActive = true
        #if DEBUG
        if debugNeutralCarrierVision { visionActive = false }
        #endif
        let carrierSight = Double(rbAttrs.vision) * 0.6 + Double(rb.mental.awareness) * 0.4
        // P0-2: the carrier-vs-secondary speed differential is 0-centered, so it
        // rides `edgeScale`; the 0.03 league base and the crease/vision GATES below
        // stay raw (a single burner on an even roster ⇒ team gap ≈ 0 ⇒ scale ≈ 1).
        var breakawayChance = max(0.0, (rbSpeed - avgDBSpeed) / 200.0 * edgeScale + 0.03)
        if visionActive {
            breakawayChance *= clamp(1.0 + (carrierSight - 70.0) * carrierVisionSlope,
                                     min: 0.6, max: 1.4)
        }
        // A2-run (Balance R3): the OL crease GATES the breakaway probability — a
        // burner without a hole rarely breaks one. Capped at 1.0 (an elite crease
        // does not INFLATE the odds — that would compound with a fast back into an
        // unbounded ceiling); it only SUPPRESSES a bad crease. Keyed on the pure
        // `creaseQuality` (0 at neutral OL → parity), not the gap-shaded blocking.
        breakawayChance *= clamp(1.0 + creaseQuality * breakawayCreaseSlope,
                                 min: breakawayCreaseMin, max: breakawayCreaseMax)
        // Round 4 (mental states): a hot back hits the hole with conviction — a
        // tightly-bounded nudge on breakaway CHANCE (never magnitude), so the
        // ±0.35-yд mean bonus above stays the only yardage lever. rb.heat 0 (or
        // immune) ⇒ ×1.0 (parity).
        breakawayChance *= clamp(1.0 + rb.heat * heatBreakawaySlope * rb.heatEffectScale,
                                 min: 0.90, max: 1.10)
        // Snow: nobody outruns the pursuit on a buried track.
        if weather == .snow { breakawayChance *= 0.5 }
        // B1d: a stuffed carry never breaks away.
        if !runWasStuffed && randomChance(breakawayChance) {
            // A2-run: the crease also GATES the breakaway MAGNITUDE — a breakaway
            // behind a bad line is a short chunk, behind an elite line a house
            // call. `breakawayMagCenter` (<1) globally trims the raw 15…45 chunk
            // so an elite RB's houses do not blow past the band; the crease then
            // rides it up (elite line) or down (bad line).
            let creaseMag = clamp(breakawayMagCenter + creaseQuality * creaseYardSlope,
                                  min: breakawayYardMin, max: breakawayYardMax)
            totalYards += Int((Double.random(in: 15...45) * creaseMag).rounded())
        }

        // --- Fumble Check ---
        // R37: ball security is a skill — break-tackle (strength through
        // contact) + awareness (knowing when to cover up) move the ~0.5%
        // per-carry base. A 70-rated carrier reproduces the old rate exactly,
        // so the league fumble frequency is unchanged.
        var securityActive = true
        #if DEBUG
        if debugNeutralBallSecurity { securityActive = false }
        #endif
        var fumbleChance: Double
        if securityActive {
            let security = Double(rbAttrs.breakTackle) * 0.5 + Double(rb.mental.awareness) * 0.5
            // P0-2: the ball-security deviation from the 70 mean is 0-centered → rides `edgeScale`.
            fumbleChance = clamp(0.005 - (security - 70.0) * ballSecuritySlope * edgeScale,
                                 min: 0.002, max: 0.008)
        } else {
            fumbleChance = max(0.005, 0.01 - Double(rbAttrs.breakTackle) / 10000.0)
        }
        // Rain/snow: the wet ball comes out more often.
        if weather == .rain || weather == .snow { fumbleChance += 0.005 }
        // R40: a disciplined coaching staff scales this offense's fumble
        // frequency down (scale 1.0 = today's exact behavior).
        fumbleChance *= (adjustments?.fumbleChanceScale ?? 1.0)
        if randomChance(fumbleChance) {
            let fumbleLost = coinFlip(0.5)
            return PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .run,
                outcome: fumbleLost ? .fumbleLost : .fumble,
                yardsGained: max(totalYards, 0),
                description: "\(rb.fullName) rushes for \(max(totalYards, 0)) yards and FUMBLES! \(fumbleLost ? "Recovered by the defense!" : "Offense recovers.")",
                isFirstDown: false,
                isTurnover: fumbleLost,
                scoringPlay: false,
                pointsScored: 0,
                keyOffensePlayerID: rb.id
            )
        }

        // --- Negative Run / Tackle for Loss ---
        // A sharp-eyed back also avoids running into the pile (R37).
        var tflChance = max(0.0, 0.08 - blockingAdvantage * 0.1)
        if visionActive {
            tflChance *= clamp(1.0 - (carrierSight - 70.0) * 0.005, min: 0.65, max: 1.35)
        }
        if totalYards <= 1 && randomChance(tflChance) {
            totalYards = -Int.random(in: 1...3)
        }

        // --- Safety Check ---
        let newYardLine = yardLine + totalYards
        if newYardLine <= 0 {
            let tackler = stuffTackler(defensePlayers)
            return PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .run,
                outcome: .safety,
                yardsGained: totalYards,
                description: tackler.map {
                    "\(rb.fullName) is tackled in the end zone by \($0.fullName) for a safety!"
                } ?? "\(rb.fullName) is tackled in the end zone for a safety!",
                isFirstDown: false,
                isTurnover: false,
                scoringPlay: true,
                pointsScored: 2,
                keyOffensePlayerID: rb.id,
                keyDefensePlayerID: tackler?.id
            )
        }

        // --- Touchdown Check ---
        let yardsToEndzone = 100 - yardLine
        if totalYards >= yardsToEndzone {
            totalYards = yardsToEndzone
            return PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .run,
                outcome: .touchdown,
                yardsGained: totalYards,
                description: "\(rb.fullName) rushes \(totalYards) yards for a TOUCHDOWN!",
                isFirstDown: true,
                isTurnover: false,
                scoringPlay: true,
                pointsScored: 6,
                keyOffensePlayerID: rb.id
            )
        }

        totalYards = max(totalYards, -(yardLine)) // Don't go past own endzone without safety
        let gainedFirstDown = totalYards >= distance

        // --- R37: name the tackle (~half of run rows, weighted toward the
        // plays that mean something: TFLs always, stuffs and breakaways run
        // down from behind usually, routine gains occasionally). The named
        // tackler also carries the box-score tackle credit.
        var tackler: SimPlayer? = nil
        var bigHit = false
        if totalYards < 0 {
            tackler = stuffTackler(defensePlayers)
        } else if totalYards <= 1 {
            if randomChance(0.7) { tackler = stuffTackler(defensePlayers) }
        } else if totalYards >= 15 {
            if randomChance(0.8) { tackler = chaseTackler(defensePlayers) }
        } else if randomChance(0.35) {
            tackler = pursuitTackler(defensePlayers)
            // A thumper occasionally detonates on the carrier near the line.
            if let hitman = tackler, totalYards <= 6,
               Double(hitman.physical.strength) >= 80 || lbTacklingRating(for: hitman) >= 85,
               randomChance(0.15) {
                bigHit = true
            }
        }

        var play = PlayResult(
            playNumber: playNumber,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .run,
            outcome: .rush,
            yardsGained: totalYards,
            description: rushDescription(rb: rb, yards: totalYards, firstDown: gainedFirstDown,
                                         tackler: tackler, bigHit: bigHit),
            isFirstDown: gainedFirstDown,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0,
            keyOffensePlayerID: rb.id,
            keyDefensePlayerID: tackler?.id
        )
        if bigHit { play.defensiveHighlight = true }
        if let runBustBlockerID {
            play.bustKind = .block
            play.bustPlayerID = runBustBlockerID
        }
        return play
    }

    // MARK: - Penalties

    /// Chance any scrimmage snap draws a flag (~6%, close to NFL's rate of
    /// accepted penalties per play).
    private static let penaltyChance = 0.06

    /// The flags the sim models, with relative frequency inside the 6%.
    private enum PenaltyKind: CaseIterable {
        case offensiveHolding    // -10, replay the down
        case falseStart          // -5 pre-snap, replay the down
        case defensiveOffside    // +5 pre-snap, replay the down (can convert by yardage)
        case defensivePassInterference // spot foul (~15), automatic first down

        var weight: Double {
            switch self {
            case .offensiveHolding:            return 0.35
            case .falseStart:                  return 0.25
            case .defensiveOffside:            return 0.25
            case .defensivePassInterference:   return 0.15
            }
        }
    }

    /// Builds a penalty play: no down is consumed (the down is replayed with
    /// adjusted distance), except defensive flags whose yardage reaches the
    /// line to gain — those convert, and DPI is an automatic first down.
    ///
    /// R37: the CULPRIT is named. The overall flag frequency (~6% of snaps,
    /// rolled by the caller) never changes — only who the laundry lands on:
    /// low-discipline (awareness + decision making) and tired players draw
    /// more flags, and holding skews toward linemen losing their reps.
    private static func rollPenalty(
        playCall: PlayType,
        offensePlayers: [SimPlayer],
        defensePlayers: [SimPlayer],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        playNumber: Int,
        offenseIsAway: Bool = false
    ) -> PlayResult {
        // Weighted draw; DPI only exists on called pass plays.
        var candidates = PenaltyKind.allCases
        if playCall != .pass {
            candidates.removeAll { $0 == .defensivePassInterference }
        }
        // Mech 6: on the road the crowd noise jumps the false-start SHARE of
        // the offense's flags (+20% relative). The overall flag frequency was
        // already rolled by the caller — this only re-slices WHICH flag lands,
        // so the home team's share of false starts falls to match. No OVR bonus
        // and no change to the total penalty rate.
        var awayFalseStart = offenseIsAway
        #if DEBUG
        if debugNeutralHomeAwayPenalty { awayFalseStart = false }
        #endif
        func weight(_ k: PenaltyKind) -> Double {
            (awayFalseStart && k == .falseStart) ? k.weight * awayFalseStartBoost : k.weight
        }
        let totalWeight = candidates.reduce(0.0) { $0 + weight($1) }
        var roll = Double.random(in: 0..<totalWeight)
        var kind = candidates[0]
        for candidate in candidates {
            roll -= weight(candidate)
            if roll <= 0 { kind = candidate; break }
        }

        /// "#72 T. Boyd" — feed-style culprit tag.
        func tag(_ p: SimPlayer) -> String { "#\(p.displayNumber) \(p.shortName)" }

        // Effective yardage is pre-clamped to the field so down-and-distance
        // bookkeeping never needs to undo an over-long walk-off.
        let yards: Int
        let description: String
        var isFirstDown = false
        var keyOffenseID: UUID? = nil
        var keyDefenseID: UUID? = nil
        switch kind {
        case .offensiveHolding:
            // Holding is a losing blocker's flag: weak blocking for THIS play
            // type, low discipline, and fatigue all raise a lineman's share.
            let culprit = weightedPickBy(startingOL(offensePlayers)) { p in
                let block = playCall == .pass ? olPassBlockRating(for: p) : olRunBlockRating(for: p)
                return max(5.0, 115.0 - block * 0.6 - disciplineRating(p) * 0.4)
                    * (1.0 + Double(p.fatigue) / 150.0)
            }
            keyOffenseID = culprit?.id
            yards = -min(10, yardLine - 1)
            description = culprit.map { "FLAG — Holding on \(tag($0)), 10-yard penalty." }
                ?? "FLAG — Holding on the offense, 10-yard penalty."
        case .falseStart:
            let culprit = indisciplineWeightedPick(from: startingOL(offensePlayers))
            keyOffenseID = culprit?.id
            yards = -min(5, yardLine - 1)
            description = culprit.map { "FLAG — False start on \(tag($0)), 5-yard penalty." }
                ?? "FLAG — False start, 5-yard penalty."
        case .defensiveOffside:
            let culprit = indisciplineWeightedPick(from: startingDL(defensePlayers))
            keyDefenseID = culprit?.id
            yards = min(5, 99 - yardLine)
            isFirstDown = yards >= distance
            description = culprit.map { "FLAG — Offside on \(tag($0)), 5-yard penalty." }
                ?? "FLAG — Defensive offside, 5-yard penalty."
        case .defensivePassInterference:
            let culprit = indisciplineWeightedPick(from: startingDBs(defensePlayers))
            keyDefenseID = culprit?.id
            yards = min(15, 99 - yardLine)
            isFirstDown = true
            description = culprit.map {
                "FLAG — Pass interference on \(tag($0)), \(yards) yards to the spot. Automatic first down."
            } ?? "FLAG — Pass interference on the defense, \(yards) yards to the spot. Automatic first down."
        }

        return PlayResult(
            playNumber: playNumber,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: playCall,
            outcome: .penalty,
            yardsGained: yards,
            description: description,
            isFirstDown: isFirstDown,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0,
            keyOffensePlayerID: keyOffenseID,
            keyDefensePlayerID: keyDefenseID
        )
    }

    // MARK: - Special Teams

    private static func simulatePunt(
        offensePlayers: [SimPlayer],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        playNumber: Int
    ) -> PlayResult {
        let punter = offensePlayers.first(where: { $0.position == .P }) ?? offensePlayers.first!
        let puntDistance = Int.random(in: 35...55)
        let netYards = min(puntDistance, 100 - yardLine) // Can't punt past the endzone

        let isTouchback = yardLine + netYards >= 100

        return PlayResult(
            playNumber: playNumber,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .punt,
            outcome: isTouchback ? .touchback : .punt,
            yardsGained: netYards,
            description: isTouchback
                ? "\(punter.fullName) punts into the end zone for a touchback."
                : "\(punter.fullName) punts \(netYards) yards.",
            isFirstDown: false,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0
        )
    }

    /// Chance a field-goal try is blocked outright at the line (~2.5%).
    private static let fieldGoalBlockChance = 0.025

    private static func simulateFieldGoal(
        offensePlayers: [SimPlayer],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        playNumber: Int,
        weather: GameWeather? = nil
    ) -> PlayResult {
        let kicker = offensePlayers.first(where: { $0.position == .K }) ?? offensePlayers.first!
        let fgDistance = 100 - yardLine + 17 // Snap + hold distance
        let kickerAccuracy = kickerAccuracyRating(for: kicker)

        // A hand gets in the way before accuracy ever matters.
        if randomChance(fieldGoalBlockChance) {
            return PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .fieldGoal,
                outcome: .fieldGoalMissed,
                yardsGained: 0,
                description: "The kick is BLOCKED! \(kicker.fullName)'s \(fgDistance)-yard attempt is swatted down at the line.",
                isFirstDown: false,
                isTurnover: true,
                scoringPlay: false,
                pointsScored: 0
            )
        }

        // Base accuracy drops with distance
        let baseMakeChance: Double
        switch fgDistance {
        case 0...30:
            baseMakeChance = 0.95
        case 31...40:
            baseMakeChance = 0.85
        case 41...50:
            baseMakeChance = 0.70
        case 51...55:
            baseMakeChance = 0.50
        default:
            baseMakeChance = 0.30
        }

        let accuracyModifier = (Double(kickerAccuracy) - 70.0) / 200.0
        var makeChance = clamp(baseMakeChance + accuracyModifier, min: 0.10, max: 0.98)

        // Weather: rain/snow slick the hold and plant foot; wind punishes
        // long tries (45+ yards). nil/.clear keeps today's odds exactly.
        switch weather {
        case .rain, .snow:
            makeChance = clamp(makeChance - 0.05, min: 0.05, max: 0.98)
        case .wind where fgDistance > 45:
            makeChance = clamp(makeChance - 0.10, min: 0.05, max: 0.98)
        default:
            break
        }

        let isGood = randomChance(makeChance)

        return PlayResult(
            playNumber: playNumber,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .fieldGoal,
            outcome: isGood ? .fieldGoalGood : .fieldGoalMissed,
            yardsGained: 0,
            description: isGood
                ? "\(kicker.fullName) kicks a \(fgDistance)-yard field goal. It's GOOD!"
                : "\(kicker.fullName) misses a \(fgDistance)-yard field goal attempt.",
            isFirstDown: false,
            isTurnover: !isGood,
            scoringPlay: isGood,
            pointsScored: isGood ? 3 : 0
        )
    }

    private static func simulateKneel(
        offensePlayers: [SimPlayer],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        playNumber: Int
    ) -> PlayResult {
        let qb = findQB(in: offensePlayers)
        return PlayResult(
            playNumber: playNumber,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .kneel,
            outcome: .kneel,
            yardsGained: -1,
            description: "\(qb.fullName) takes a knee.",
            isFirstDown: false,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0
        )
    }

    private static func simulateSpike(
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        playNumber: Int
    ) -> PlayResult {
        PlayResult(
            playNumber: playNumber,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .spike,
            outcome: .spike,
            yardsGained: 0,
            description: "Quarterback spikes the ball to stop the clock.",
            isFirstDown: false,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0
        )
    }

    // MARK: - QB Scramble (fallback when no receivers found)

    private static func simulateQBScramble(
        qb: SimPlayer,
        qbAttrs: QBAttributes,
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        momentum: Double,
        playNumber: Int
    ) -> PlayResult {
        let scramblingBonus = Double(qbAttrs.scrambling) / 100.0 * 4.0
        let speedBonus = effectiveSpeed(qb) / 100.0 * 2.0
        var yards = Int((Double.random(in: 1.0...4.0) + scramblingBonus + speedBonus).rounded())

        let yardsToEndzone = 100 - yardLine
        if yards >= yardsToEndzone {
            yards = yardsToEndzone
            return PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .run,
                outcome: .touchdown,
                yardsGained: yards,
                description: "\(qb.fullName) scrambles \(yards) yards for a TOUCHDOWN!",
                isFirstDown: true,
                isTurnover: false,
                scoringPlay: true,
                pointsScored: 6,
                keyOffensePlayerID: qb.id
            )
        }

        let gainedFirstDown = yards >= distance
        return PlayResult(
            playNumber: playNumber,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .run,
            outcome: .rush,
            yardsGained: yards,
            description: "\(qb.fullName) scrambles for \(yards) yards\(gainedFirstDown ? " for a first down" : "").",
            isFirstDown: gainedFirstDown,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0,
            keyOffensePlayerID: qb.id
        )
    }

    // MARK: - Extra Point & Two-Point Conversion

    /// Simulates an extra point attempt.
    static func simulateExtraPoint(
        offensePlayers: [SimPlayer],
        quarter: Int,
        timeRemaining: Int,
        yardLine: Int,
        playNumber: Int
    ) -> PlayResult {
        let kicker = offensePlayers.first(where: { $0.position == .K }) ?? offensePlayers.first!
        let accuracy = kickerAccuracyRating(for: kicker)
        let makeChance = clamp(0.90 + Double(accuracy - 70) / 300.0, min: 0.80, max: 0.99)
        let isGood = randomChance(makeChance)

        return PlayResult(
            playNumber: playNumber,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: 0,
            distance: 0,
            yardLine: 98, // 2-yard line for PAT
            playType: .extraPoint,
            outcome: isGood ? .extraPointGood : .extraPointMissed,
            yardsGained: 0,
            description: isGood
                ? "\(kicker.fullName) kicks the extra point. Good!"
                : "\(kicker.fullName) misses the extra point!",
            isFirstDown: false,
            isTurnover: false,
            scoringPlay: isGood,
            pointsScored: isGood ? 1 : 0
        )
    }

    /// Simulates a two-point conversion attempt: one snap from the 2-yard
    /// line, ~47% baseline success shaded by overall team quality and — in
    /// live coached games — by the actual offensive call and defensive
    /// package (the same modifier families every goal-line snap uses).
    /// Nil call/package reproduces the neutral quick-sim roll exactly.
    static func simulateTwoPointConversion(
        offensePlayers: [SimPlayer],
        defensePlayers: [SimPlayer],
        quarter: Int,
        timeRemaining: Int,
        playNumber: Int,
        offensiveCall: OffensivePlayCall? = nil,
        defensivePackage: DefensivePackage? = nil
    ) -> PlayResult {
        // Honor an explicit call; the AI leans pass (~60/40) from the 2.
        let isPass = offensiveCall.map { !$0.isRun } ?? coinFlip(0.6)
        let qb = findQB(in: offensePlayers)

        // Baseline ~47% (league average), shaded by the overall matchup.
        let offenseRating = averageAttribute(offensePlayers, extractor: { Double($0.overall) })
        let defenseRating = averageAttribute(defensePlayers, extractor: { Double($0.overall) })
        let advantage = (offenseRating - defenseRating) / 100.0
        var conversionChance = 0.47 + advantage

        // Live-game shading: on the short field a pass try meets coverage
        // and pressure, a run try meets the run-stop wall; the called play's
        // hint credits quick timing (pass) or interior push (run).
        if isPass {
            if let package = defensivePackage {
                conversionChance -= (package.totalCoverageModifier
                                     + package.totalShortCoverageModifier) * 0.5
                conversionChance -= package.totalPressureModifier * 0.3
            }
            if let hint = offensiveCall?.simulatorHint {
                conversionChance += hint.blitzPickupBonus * 0.2
            }
        } else {
            if let package = defensivePackage {
                conversionChance -= package.totalRunStopModifier * 0.5
            }
            if let hint = offensiveCall?.simulatorHint {
                conversionChance += hint.runGapBonus * 0.3
            }
        }
        let isGood = randomChance(clamp(conversionChance, min: 0.20, max: 0.75))

        let description: String
        var keyPlayerID: UUID?
        if isPass {
            let target = eligibleReceivers(from: offensePlayers).randomElement()
            let targetName = target?.fullName ?? "a receiver"
            keyPlayerID = target?.id
            description = isGood
                ? "\(qb.fullName) throws to \(targetName) for the two-point conversion!"
                : "\(qb.fullName) throws to \(targetName), but the two-point conversion fails."
        } else {
            // Same designed-carrier rule as the scrimmage run path: a two-point
            // sneak is the quarterback's, not a back's (the 3D field hands it to
            // him either way, so the credit and the line have to agree).
            let rb = designedCarrier(call: offensiveCall, in: offensePlayers)
            keyPlayerID = rb.id
            description = isGood
                ? "\(rb.fullName) punches it in for the two-point conversion!"
                : "\(rb.fullName) is stopped short on the two-point conversion attempt."
        }

        return PlayResult(
            playNumber: playNumber,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: 0,
            distance: 0,
            yardLine: 98,
            playType: .twoPointConversion,
            outcome: isGood ? .twoPointGood : .twoPointFailed,
            yardsGained: 0,
            description: description,
            isFirstDown: false,
            isTurnover: false,
            scoringPlay: isGood,
            pointsScored: isGood ? 2 : 0,
            keyOffensePlayerID: keyPlayerID
        )
    }

    // MARK: - Player Finders

    // The best player at the position acts as the starter — roster order is
    // arbitrary, and play descriptions should feature QB1, not the 3rd string.
    private static func findQB(in players: [SimPlayer]) -> SimPlayer {
        players.filter { $0.position == .QB }.max(by: { $0.overall < $1.overall })
            ?? players.first!
    }

    private static func findRB(in players: [SimPlayer]) -> SimPlayer {
        let backs = players.filter { $0.position == .RB }
        if let best = backs.max(by: { $0.overall < $1.overall }) { return best }
        return players.first(where: { $0.position == .FB }) ?? players.first!
    }

    /// The X receiver — the man `FieldUnit.offense` seats at role 7, so an
    /// end-around's credited rusher IS the player the 3D field runs.
    private static func findWR(in players: [SimPlayer]) -> SimPlayer? {
        players.filter { $0.position == .WR }.max(by: { $0.overall < $1.overall })
    }

    /// The ball-carrier the CALL designs the run for (`OffensivePlayCall
    /// .designedRusher`): the quarterback on a sneak/push/QB draw/speed option,
    /// the X receiver on an end around, the back on everything else.
    ///
    /// The starters picked here mirror `FieldUnit.offense`'s role order (best
    /// QB = role 0, best WR = role 7, `findRB` = role 1), which is what keeps
    /// the credited rusher, the play-by-play line and the man carrying the ball
    /// on the 3D field the same person. A nil call — quick sim, season sim, the
    /// balance harness — always resolves to the back, so those paths are
    /// byte-identical to before.
    private static func designedCarrier(call: OffensivePlayCall?,
                                        in players: [SimPlayer]) -> SimPlayer {
        switch call?.designedRusher {
        case .quarterback: return findQB(in: players)
        case .receiver:    return findWR(in: players) ?? findRB(in: players)
        case .back, nil:   return findRB(in: players)
        }
    }

    private static func eligibleReceivers(from players: [SimPlayer]) -> [SimPlayer] {
        players.filter { [.WR, .TE, .RB].contains($0.position) }
    }

    // MARK: - Position Group Checks

    private static func isOL(_ player: SimPlayer) -> Bool {
        [Position.LT, .LG, .C, .RG, .RT].contains(player.position)
    }

    private static func isDL(_ player: SimPlayer) -> Bool {
        [Position.DE, .DT].contains(player.position)
    }

    private static func isLB(_ player: SimPlayer) -> Bool {
        [Position.OLB, .MLB].contains(player.position)
    }

    private static func isDB(_ player: SimPlayer) -> Bool {
        [Position.CB, .FS, .SS].contains(player.position)
    }

    // MARK: - Attribute Extractors

    private static func qbAttributes(for player: SimPlayer) -> QBAttributes {
        if case .quarterback(let attrs) = player.positionAttributes { return attrs }
        return QBAttributes(
            armStrength: 50, accuracyShort: 50, accuracyMid: 50,
            accuracyDeep: 50, pocketPresence: 50, scrambling: 50
        )
    }

    private static func rbAttributes(for player: SimPlayer) -> RBAttributes {
        if case .runningBack(let attrs) = player.positionAttributes { return attrs }
        return RBAttributes(vision: 50, elusiveness: 50, breakTackle: 50, receiving: 50)
    }

    private static func olPassBlockRating(for player: SimPlayer) -> Double {
        if case .offensiveLine(let attrs) = player.positionAttributes {
            return Double(attrs.passBlock)
        }
        return 50.0
    }

    private static func olRunBlockRating(for player: SimPlayer) -> Double {
        if case .offensiveLine(let attrs) = player.positionAttributes {
            return Double(attrs.runBlock)
        }
        return 50.0
    }

    private static func dlPassRushRating(for player: SimPlayer) -> Double {
        if case .defensiveLine(let attrs) = player.positionAttributes {
            // Mech 1: fatigue drags the effective pass rush.
            return Double((attrs.passRush + attrs.powerMoves + attrs.finesseMoves) / 3)
                - fatiguePenalty(player.fatigue)
        }
        return 50.0
    }

    private static func dlBlockSheddingRating(for player: SimPlayer) -> Double {
        if case .defensiveLine(let attrs) = player.positionAttributes {
            // Mech 1: fatigue drags the effective block shed.
            return Double(attrs.blockShedding) - fatiguePenalty(player.fatigue)
        }
        return 50.0
    }

    private static func lbTacklingRating(for player: SimPlayer) -> Double {
        if case .linebacker(let attrs) = player.positionAttributes {
            return Double(attrs.tackling)
        }
        return 50.0
    }

    private static func lbBlitzRating(for player: SimPlayer) -> Double {
        if case .linebacker(let attrs) = player.positionAttributes {
            return Double(attrs.blitzing)
        }
        return 50.0
    }

    private static func dbCoverageRating(for player: SimPlayer) -> Double {
        if case .defensiveBack(let attrs) = player.positionAttributes {
            // Mech 1: fatigue drags the effective coverage.
            return Double((attrs.manCoverage + attrs.zoneCoverage) / 2)
                - fatiguePenalty(player.fatigue)
        }
        return 50.0
    }

    private static func dbBallSkillsRating(for player: SimPlayer) -> Double {
        if case .defensiveBack(let attrs) = player.positionAttributes {
            return Double(attrs.ballSkills)
        }
        return 50.0
    }

    private static func receiverCatchRating(for player: SimPlayer) -> Double {
        // Mech 1: fatigue drags the effective get-open rating (route legs).
        let drag = fatiguePenalty(player.fatigue)
        switch player.positionAttributes {
        case .wideReceiver(let attrs):
            return Double((attrs.catching + attrs.routeRunning) / 2) - drag
        case .tightEnd(let attrs):
            return Double((attrs.catching + attrs.routeRunning) / 2) - drag
        case .runningBack(let attrs):
            return Double(attrs.receiving) - drag
        default:
            return 40.0
        }
    }

    private static func receiverRouteWeight(for player: SimPlayer) -> Double {
        switch player.positionAttributes {
        case .wideReceiver(let attrs):
            return Double(attrs.routeRunning + attrs.catching) / 2.0
        case .tightEnd(let attrs):
            return Double(attrs.catching + attrs.routeRunning) / 2.0
        case .runningBack(let attrs):
            return Double(attrs.receiving) * 0.6
        default:
            return 20.0
        }
    }

    private static func kickerAccuracyRating(for player: SimPlayer) -> Int {
        if case .kicking(let attrs) = player.positionAttributes {
            return attrs.kickAccuracy
        }
        return 70
    }

    // MARK: - Pass Helpers

    private enum PassDistance {
        case short  // 0-10 yards
        case mid    // 11-20 yards
        case deep   // 21+ yards
    }

    private static func choosePassDistance(distance: Int, yardLine: Int) -> PassDistance {
        let yardsToEndzone = 100 - yardLine

        // If close to the endzone, favor shorter passes
        if yardsToEndzone <= 10 { return .short }

        // P0-1 (secondary): pull the realized deep-shot share from ~24% down to
        // ~12% (NFL is ~10-12%). The old mix fired a bomb on nearly a quarter of
        // generic drop-backs — with the newly-restored coverage tax that both
        // dragged pooled completion below the band (deep balls miss more) and
        // over-inflated pass yards / sack exposure (deep drops hold longer).
        // Named play-calls (the FIXED-BASELINE `depth` band) bypass this helper,
        // so those anchors are untouched; only the generic AI drop-back shifts.
        if distance <= 5 {
            // Short yardage: favor short/mid
            let roll = Double.random(in: 0...1)
            if roll < 0.68 { return .short }
            if roll < 0.92 { return .mid }
            return .deep
        } else if distance <= 10 {
            let roll = Double.random(in: 0...1)
            if roll < 0.52 { return .short }
            if roll < 0.88 { return .mid }
            return .deep
        } else {
            // Long distance: favor mid/deep
            let roll = Double.random(in: 0...1)
            if roll < 0.30 { return .short }
            if roll < 0.74 { return .mid }
            return .deep
        }
    }

    private static func passYardsForDistance(_ passDistance: PassDistance) -> Int {
        switch passDistance {
        case .short:
            return Int.random(in: 2...10)
        case .mid:
            return Int.random(in: 11...20)
        case .deep:
            // DEEP-TALENT air-yards re-center: the neutral bomb band drops from
            // 21...45 (mean 33) to 20...30 (mean 25). The composite air ride in
            // simulatePassPlay then adds Int(deepEdge*deepAirSlope) on top, so an
            // elite duo restores the big-play reach while neutral deep EV falls
            // from ~14 to ~8.5.
            return Int.random(in: 20...30)
        }
    }

    // MARK: - DEEP-TALENT (composite-owned deep ball)
    //
    // A dedicated deep completion + air path that fully replaces the generic
    // completion weighting for passDistance == .deep ONLY. Short/mid pipeline is
    // byte-untouched. The composite is 0-centered at all-70, so a neutral matchup
    // reproduces the re-centered deep bands and elite/weak duos separate cleanly
    // and monotonically in BOTH the QB and WR axes.

    private static let deepBaseCompletion = 0.53   // 70/70 vs-mix lands ~38%
    private static let deepCompSlopeUp   = 0.0060  // edge >= 0 (elite ceiling ~55%)
    private static let deepCompSlopeDown = 0.0095  // edge <  0 (weak floor drops harder)
    private static let deepAirSlope      = 0.30    // composite air ride (elite +~7 air)
    private static let deepAirFloor      = 15
    private static let deepPunishEdgeSlope = 0.03  // keyed-punish composite scaler slope
    private static let deepPunishScaleMin  = 0.30
    private static let deepPunishScaleMax  = 2.50

    /// Asymmetric deep-edge → completion shift (single symmetric slope cannot hit
    /// both the elite ceiling and the weak floor because the edges are asymmetric,
    /// +25 elite vs −15 weak — the split IS the mechanism).
    private static func deepEdgeCompletion(_ deepEdge: Double) -> Double {
        deepEdge >= 0 ? deepEdge * deepCompSlopeUp : deepEdge * deepCompSlopeDown
    }

    /// QB deep component: deep accuracy weighted a hair over arm strength.
    private static func qbDeepRating(_ attrs: QBAttributes) -> Double {
        Double(attrs.accuracyDeep) * 0.55 + Double(attrs.armStrength) * 0.45
    }

    /// Receiver deep-threat: speed-led. There is no WR "deep" attr, so the deep
    /// threat is shared speed + route running + spectacular catch (TE/RB fall
    /// back on receiving/route in place of the missing spectacular-catch attr;
    /// their low speed attr gates blocking TEs out of the deep game).
    private static func receiverDeepThreatRating(for player: SimPlayer) -> Double {
        switch player.positionAttributes {
        case .wideReceiver(let a):
            return Double(player.physical.speed) * 0.50 + Double(a.routeRunning) * 0.30 + Double(a.spectacularCatch) * 0.20
        case .tightEnd(let a):
            return Double(player.physical.speed) * 0.50 + Double(a.routeRunning) * 0.50
        case .runningBack(let a):
            return Double(player.physical.speed) * 0.50 + Double(a.receiving) * 0.50
        default:
            return Double(player.physical.speed)
        }
    }

    /// Deep composite edge = offense deep threat − DB deep defense, 0-centered at
    /// all-70. +25 for an elite 95/95 duo vs a 70 secondary; −15 for a weak 55/55.
    /// A1-deep (Balance R3): the DB unit deep defense is blended toward the
    /// ASSIGNED cover man on this target (`coverMan`/`manWeight`), so a shutdown
    /// CB1 erases WR1 even on the bomb. At all-70 the assigned man == the unit
    /// average == 70, so `defDeep` is byte-unchanged and neutral parity holds.
    private static func deepCompositeEdge(qb: SimPlayer, target: SimPlayer, defensePlayers: [SimPlayer],
                                          coverMan: CoverMatch, manWeight: Double) -> Double {
        let qbDeep = qbDeepRating(qbAttributes(for: qb))
        let wrDeep = receiverDeepThreatRating(for: target)
        let offDeep = qbDeep * 0.55 + wrDeep * 0.45   // QB weighted a hair over WR
        let dbs = defensePlayers.filter { isDB($0) }
        let dbCov = averageAttribute(dbs, extractor: { dbCoverageRating(for: $0) })
        let dbSpd = averageAttribute(dbs, extractor: { effectiveSpeed($0) })
        let defDeepUnit = dbCov * 0.55 + dbSpd * 0.45
        let assignedDeep = coverMan.coverage * 0.55 + coverMan.speed * 0.45
        let defDeep = defDeepUnit * (1.0 - manWeight) + assignedDeep * manWeight
        return offDeep - defDeep
    }

    // MARK: - UNIFIED MATCHUP (Balance R3, Part A)
    //
    // A shared assigned-cover pairing + a base+QB+matchup-edge completion for
    // short/mid that mirrors the shipped deep composite. Every term is 0-centered
    // at all-70 (the assigned defender == the unit average == 70 there), so a
    // neutral matchup is byte-near-identical to today and talent only widens the
    // spread. Rebuilt inside the sim from the flat defense array — no FieldUnit
    // threading, no caller edits, no save-schema change.

    /// The cover defender the sim duels on a given target: the matchup-appropriate
    /// coverage rating, the defender's effective speed (deep blend), and — only
    /// when the assigned man is a DB — his ball-skills (INT blend).
    struct CoverMatch {
        let coverage: Double
        let speed: Double
        let ballSkills: Double?
        /// Round 4 (mental states): the assigned cover man's hot/cold FORM
        /// contribution, already `heat × heatEffectScale`. 0 for the neutral /
        /// unit-help fallback (no individualized man) ⇒ the DB heat term vanishes
        /// (parity). A hot CB tightens the window; a cold one loosens it.
        var heatContribution: Double = 0
    }

    /// A linebacker's coverage rating (man+zone)/2 — the TE/RB-vs-LB mismatch
    /// lever (LB coverage ≪ CB coverage, so a TE/RB on a cover-LB pays off).
    private static func lbCoverageRating(for player: SimPlayer) -> Double {
        if case .linebacker(let a) = player.positionAttributes {
            return Double((a.manCoverage + a.zoneCoverage) / 2)
        }
        return 50.0
    }

    /// How man-oriented the called shell is: how much the pairing is
    /// individualized (assigned man) vs blended into unit help. A nil package
    /// (quick sim / neutral harness) uses the mixed-shell base weight.
    private static let baseZoneManWeight = 0.55
    private static func coverageManWeight(_ package: DefensivePackage?) -> Double {
        guard let package = package else { return baseZoneManWeight }
        switch package.coverage {
        // Zero help behind it: every defender is locked on a man, so the
        // individual WR-vs-CB matchup decides more of the snap than in any
        // other shell.
        case .cover0:          return 0.95
        case .manToMan:        return 0.90
        case .cover1:          return 0.80
        case .cover2, .cover4: return 0.45
        case .cover6:          return 0.42   // split-field zone, quarters-ish
        case .cover3:          return 0.40
        case .tampa2:          return 0.35   // deepest zone commitment in the game
        case .prevent:         return 0.30
        default:               return baseZoneManWeight
        }
    }

    /// The assigned cover defender for THIS target, mirroring `FieldUnit`+`coverFor`:
    /// the target's rank within its position group (by overall) picks the
    /// correspondingly-ranked defender. WR1→CB1, WR2→CB2, slot→nickel CB (if the
    /// front fields one) else better safety, TE→max-cover of {best cover LB,
    /// better S}, RB→2nd LB.
    private static func coverAssignment(for target: SimPlayer, offense: [SimPlayer],
                                        defense: [SimPlayer], package: DefensivePackage?) -> CoverMatch {
        let neutral = CoverMatch(coverage: 70, speed: 70, ballSkills: nil)
        let cbs = defense.filter { $0.position == .CB }.sorted { $0.overall > $1.overall }
        let safeties = defense.filter { $0.position == .FS || $0.position == .SS }
        let lbs = defense.filter { isLB($0) }.sorted { $0.overall > $1.overall }
        func dbMatch(_ p: SimPlayer) -> CoverMatch {
            CoverMatch(coverage: dbCoverageRating(for: p), speed: effectiveSpeed(p),
                       ballSkills: dbBallSkillsRating(for: p),
                       heatContribution: p.heat * p.heatEffectScale)
        }
        func lbMatch(_ p: SimPlayer) -> CoverMatch {
            CoverMatch(coverage: lbCoverageRating(for: p), speed: effectiveSpeed(p), ballSkills: nil,
                       heatContribution: p.heat * p.heatEffectScale)
        }
        func betterSafety() -> SimPlayer? {
            safeties.max(by: { dbCoverageRating(for: $0) < dbCoverageRating(for: $1) })
        }
        switch target.position {
        case .WR:
            let wrs = offense.filter { $0.position == .WR }.sorted { $0.overall > $1.overall }
            let rank = wrs.firstIndex(where: { $0.id == target.id }) ?? 0
            if rank <= 1, cbs.count > rank { return dbMatch(cbs[rank]) }
            // Slot (rank 2+): the sub-package corner if the front fields one,
            // else the better safety rolls down over the slot. Big nickel is a
            // five-DB front too — it just spends the fifth on a safety.
            let nickelDime = package.map {
                $0.front == .nickel || $0.front == .bigNickel || $0.front == .dime
            } ?? false
            if nickelDime, cbs.count > 2 { return dbMatch(cbs[2]) }
            if let s = betterSafety() { return dbMatch(s) }
            if let cb = cbs.first { return dbMatch(cb) }
            return neutral
        case .TE:
            let bestCoverLB = lbs.max(by: { lbCoverageRating(for: $0) < lbCoverageRating(for: $1) })
            let s = betterSafety()
            let lbCov = bestCoverLB.map { lbCoverageRating(for: $0) } ?? -1
            let sCov = s.map { dbCoverageRating(for: $0) } ?? -1
            if sCov >= lbCov, let s = s { return dbMatch(s) }
            if let lb = bestCoverLB { return lbMatch(lb) }
            if let s = s { return dbMatch(s) }
            return neutral
        case .RB, .FB:
            if lbs.count >= 2 { return lbMatch(lbs[1]) }
            if let lb = lbs.first { return lbMatch(lb) }
            return neutral
        default:
            return neutral
        }
    }

    // Short/mid completion composite constants (Balance R3, Part A / A1). All
    // 0-centered at 70, dial-authorized. `shortBaseCompletion`/`midBaseCompletion`
    // anchor the neutral (all-70 vs the standard mix) completion; the QB terms and
    // the matchup edge add 0 at 70v70.
    private static let shortBaseCompletion = 0.77
    private static let midBaseCompletion   = 0.71
    private static let qbAccCompSlope      = 0.0045
    private static let qbReadCompSlope     = 0.0015
    private static let coverEdgeSlopeUp    = 0.0050  // WR wins the matchup
    private static let coverEdgeSlopeDown  = 0.0075  // CB wins (steeper — shutdown bites)
    private static let matchupEdgeCapRaw   = 30.0    // raw edge clamp (±) before slope
    private static let shortMidAirSlope    = 0.06    // bounded short/mid matchup air ride

    // ---- P0-2 COMPRESSION: team-breadth talent-curve flattening on composite edges ----
    // WHY team-breadth, not per-play magnitude: a shutdown CB and a uniform 2-tier
    // roster produce a SIMILAR per-snap edge, so a knee on the per-play edge cannot
    // tell them apart — it would flatten the shutdown corner while barely denting
    // the blowout. The determinism is a BREADTH phenomenon: every unit is mismatched
    // at once and the small per-snap edges compound across ~130 plays. So the scale
    // keys on the TEAM-AGGREGATE talent gap (mean offense overall − mean defense
    // overall) and multiplies EVERY 0-centered talent channel (sack, completion,
    // matchup, deep, INT, drops, contested, run block, carrier, stuff, breakaway,
    // fumble — comprehensive, because the talent signal is spread across all of them).
    //
    // SHAPE — a monotone-DECREASING ramp, NOT a saturating soft-knee. Measured surface
    // (constant-edgeScale sweep, N=800/cell, joint with P0-1's de-inflated base):
    //   • the whole tier ladder lands on target at a floor scale ≈ 0.085 (1-tier
    //     69-75% / +6-7, 2-tier 86-89% / +11-13, 3-tier 93% / +15 — never 100%);
    //   • BUT single-unit signatures live at small team gaps — a shutdown-CB pair
    //     moves the team mean only ≈3 pts, an elite OL (5 of 12) ≈7 — so the scale
    //     must stay ≈1 there. A soft-knee is structurally unable to do both: it is
    //     monotone-INCREASING, so it cannot give scale≈0.9 at gap 3 AND ≈0.08 at
    //     gap 9. A smoothstep ramp (1.0 below `teamEdgeFull`, floor above
    //     `teamEdgeCrush`) can: parity + shutdown-CB + every per-play tier-matrix
    //     cell (only 1-2 units elevated ⇒ gap ≤ ~4) sit in the flat 1.0 zone and
    //     are byte-untouched; a whole-roster mismatch sits at the floor and is
    //     crushed. (The elite-OL fullgame at gap ≈7 straddles the ramp and is
    //     partially damped — an inherent limit of keying on the team aggregate.)
    // The scale is a positive multiplier, so it preserves the SIGN and RANK of every
    // edge ⇒ per-play monotonicity and tier ORDERING survive; only the magnitude bends.
    private static let teamEdgeFull  = 3.5     // |team gap| at/below which scale = 1.0 (single-unit + matrix-cell safe zone)
    private static let teamEdgeCrush = 9.0     // |team gap| at/above which scale = floor (uniform-tier zone)
    private static let teamEdgeFloor = 0.085   // residual edge deployed on a full-team mismatch
    /// Talent-curve compression scale (∈ [floor, 1]) on the per-play composite edges,
    /// from the team-aggregate offense−defense overall gap. 1.0 at parity / single-unit
    /// (small gap); ramps down to `teamEdgeFloor` as the whole roster out-classes the
    /// opponent. Symmetric in the sign of the gap (weak-offense penalties compress too).
    static func edgeCompressionScale(offense: [SimPlayer], defense: [SimPlayer]) -> Double {
        let a = abs(averageAttribute(offense, extractor: { Double($0.overall) })
                  - averageAttribute(defense, extractor: { Double($0.overall) }))
        if a <= teamEdgeFull  { return 1.0 }
        if a >= teamEdgeCrush { return teamEdgeFloor }
        let t = (a - teamEdgeFull) / (teamEdgeCrush - teamEdgeFull)
        let s = t * t * (3.0 - 2.0 * t)                  // smoothstep (C¹, monotone)
        return 1.0 - (1.0 - teamEdgeFloor) * s
    }

    // ---- ROUND-6 WEAK-FLOOR TAPER: talent-scaled relief for the P0-1 de-inflation ----
    // WHY: P0-1's full-game de-inflation (the restored ~0.13 coverage tax + the
    // early-down pass-weight and deep-share trims) is a roughly-FLAT downshift, so it
    // over-cools a BELOW-average offense — whose completion sits on the steep part of
    // the scoring curve — far more than an average one. That dropped the whole weak
    // tier below the NFL bad-team floor (weak-weak pts 14 / comp 51.5 / ypc 3.29 /
    // nYPA 5.28 / 3rd 34.7, all OUT-lo), the one Medium item gating HEALTHY.
    //
    // WHAT: restore a talent-scaled fraction of that efficiency for a weak offense
    // (a WARM below `floorWarmPivot`), and — symmetrically, from the top — trim the
    // un-compressed equal-tier elite tail (a COOL above `ceilCoolPivot`). Together
    // they flatten the too-steep equal-tier efficiency slope from BOTH ends
    // (weak cold ⇄ elite hot) with a single principled surface.
    //
    // KEYED on the COMBINED on-field talent — the mean of the offense's and the
    // defense's mean overall — i.e. how far THIS matchup as a whole sits from the 70
    // calibration mean. This is deliberately combined, not offense-only: the equal-tier
    // slope is the target, and a weak-vs-weak game (combined ~62) or an elite-vs-elite
    // game (combined ~91) sits at an extreme and is bent, whereas a MISMATCH averages
    // out into the [70,85] dead zone (elite-vs-weak combined ~77, good-vs-weak ~73) and
    // is left byte-untouched — so the whole P0-2 mismatch ladder (win% + margin, the
    // never-100 tail) is preserved intact. Keying on offense-only instead would fire
    // the warm on the underdog AND the cool on the favorite in the SAME mismatch,
    // double-compressing and collapsing the ladder. A single elevated UNIT barely moves
    // either team mean, so single-unit signatures and the per-play FIXED BASELINE are
    // untouched — same whole-roster philosophy as P0-2's `edgeScale`.
    //
    // FIXED-BASELINE / calibration SAFETY: BOTH terms are exactly ZERO across the
    // whole calibrated [floorWarmPivot, ceilCoolPivot] = [70, 85] band. The all-70
    // per-play probe (combined mean == 70), the avg tier, and the good tier therefore
    // see byte-zero adjustment; only the weak and elite EQUAL-tier extremes bend.
    private static let floorWarmPivot   = 70.0   // no warm at/above the all-70 calibration mean
    private static let floorWarmComp    = 0.0100 // completion restored per overall-pt below the pivot (item 3: 0.0082→0.0100, restores weak-weak pts to the 17 floor 5ae0989 raised, after item-1's correct heat de-inflation lowered it)
    private static let floorWarmRun     = 0.076  // run yd/carry restored per overall-pt below the pivot (item 3: 0.058→0.076, weak-tier ypc floor back to ~3.64 ≥3.6 + weak-weak pts back into band after item-1 RB-heat de-inflation nudged ypc to ~3.52 / pts to 16.6)
    private static let floorWarmCompCap = 0.11
    private static let floorWarmRunCap  = 0.62
    private static let ceilCoolPivot    = 85.0   // relax the un-compressed elite tail above this
    private static let ceilCoolComp     = 0.006  // completion trimmed per overall-pt above the pivot
    private static let ceilCoolRun      = 0.028  // run yd/carry trimmed per overall-pt above the pivot
    private static let ceilCoolCompCap  = 0.055
    private static let ceilCoolRunCap   = 0.28

    // ---- ITEM 3: SITUATIONAL 3rd-DOWN STIFFENING (good/elite convert too often) ----
    // Good- and elite-tier EQUAL games convert 3rd downs ~49-51 % (over the ~44 % NFL
    // norm) purely as a downstream effect of their high per-play efficiency — there is
    // no 3rd-down-specific lever, so the general taper can't reach it without nerfing
    // their (in-band) overall comp/ypc/points. This is a small, talent-scaled completion
    // cool that fires ONLY on 3rd down and ONLY when the COMBINED on-field mean clears
    // `thirdDownPivot` (80) — so good (~83.5) and elite (~91.5) are trimmed while avg
    // (~74.5), weak (~62), the all-70 per-play probe (70), and every mismatch that
    // averages below 80 are BYTE-ZERO. It shaves the pass-conversion rate on the down
    // that decides drives, dropping 3rd-down to ≤47 without moving general scoring below
    // band (a converted-3rd is only ~1-2 pts of the drive's EV).
    private static let thirdDownPivot     = 80.0
    private static let thirdDownStiffen   = 0.013  // completion cooled per combined-pt above the pivot, on 3rd down
    private static let thirdDownStiffenCap = 0.105

    /// Combined on-field mean overall = (mean offense overall + mean defense overall)
    /// / 2 — how far this whole matchup sits from the 70 calibration mean.
    static func combinedFieldMean(offense: [SimPlayer], defense: [SimPlayer]) -> Double {
        (averageAttribute(offense, extractor: { Double($0.overall) })
         + averageAttribute(defense, extractor: { Double($0.overall) })) / 2.0
    }

    /// Talent-scaled completion adjustment: a WARM (>0) for a weak matchup (combined
    /// mean < 70), a COOL (<0) for an elite matchup (combined mean > 85), and exactly
    /// 0 across the calibrated [70,85] middle (so the all-70 probe / avg / good / every
    /// mismatch that averages into the middle are untouched).
    static func floorTaperCompletion(combinedMean m: Double) -> Double {
        if m < floorWarmPivot { return  Swift.min(floorWarmCompCap, (floorWarmPivot - m) * floorWarmComp) }
        if m > ceilCoolPivot  { return -Swift.min(ceilCoolCompCap,  (m - ceilCoolPivot)  * ceilCoolComp) }
        return 0
    }

    /// Talent-scaled per-carry run-yard adjustment, same weak-warm / elite-cool
    /// surface as ``floorTaperCompletion`` and likewise 0 in the calibrated middle.
    static func floorTaperRunYards(combinedMean m: Double) -> Double {
        if m < floorWarmPivot { return  Swift.min(floorWarmRunCap, (floorWarmPivot - m) * floorWarmRun) }
        if m > ceilCoolPivot  { return -Swift.min(ceilCoolRunCap,  (m - ceilCoolPivot)  * ceilCoolRun) }
        return 0
    }

    // ---- ONE-TIER UNDERDOG RELIEF (item 2: avg-vs-weak runs +3 hot) ----
    // A ONE-tier underdog is over-compressed specifically because the weak band is
    // WIDE (55-69): a "weak" team means ~62 vs a "avg" team's ~74.5, a ~12.5 team gap
    // that is larger than good-vs-avg's ~9, so avg-vs-weak plays hotter than the other
    // one-tier rungs (~78% vs the 66-75 band). The combined-keyed floor taper cannot
    // fix it — it warms BOTH offenses equally in that game, leaving the margin intact.
    // This adds a small completion relief to the UNDERDOG only (the offense whose team
    // is weaker than the defense it faces), keyed on the SIGNED talent gap (defense −
    // offense) — a continuous principled quantity, the signed mirror of P0-2's |gap|
    // `edgeScale`, NOT a per-tier lookup. A trapezoid on the gap: a `gapMin` deadzone
    // (so a single elevated defensive UNIT — a shutdown-CB pair moves the team gap only
    // ~2 — never triggers it, protecting single-unit signatures), a ramp to full at a
    // one-tier `gapPeak`, and a fade to 0 by a two-tier `gapZero` (so good-vs-weak /
    // elite-vs-weak / every 2-3-tier rung is byte-untouched). 0 at parity ⇒ equal-tier
    // games and the all-70 probe (gap 0) are untouched.
    private static let underdogGapMin  = 4.0    // deadzone: below this the gap is single-unit noise
    private static let underdogGapPeak = 11.0   // one-tier team gap → full relief (ramp end)
    // ITEM 3: full-relief PLATEAU end. The avg-vs-weak gap is ~12.5 (the weak band 55-69
    // is wide, so its mean ~62 vs avg ~74.5), which sat PAST the old single-point peak
    // (11) on the fade-out ramp — getting only ~0.81 of the relief and leaving avg-weak
    // ~1pp hot (76.1). Widening the peak to a plateau [11,13] gives that wide-band
    // one-tier rung its FULL relief (→ ≤75) while the true one-tier rungs good-avg (gap
    // ~9) and elite-good (~8) stay on the untouched ramp — a surgical fix, not a global
    // relief bump.
    private static let underdogGapPlateau = 13.0
    private static let underdogGapZero = 19.0   // two-tier team gap → relief gone
    private static let underdogReliefComp = 0.045 // completion relief at the one-tier peak

    /// Completion relief for a one-tier underdog offense (0 unless the defense out-rates
    /// the offense by a one-tier-ish team gap). See the block comment above.
    static func underdogReliefCompletion(offenseMean o: Double, defenseMean d: Double) -> Double {
        let gap = d - o                          // > 0 ⇒ this offense is the underdog
        if gap <= underdogGapMin || gap >= underdogGapZero { return 0 }
        let t: Double
        if gap <= underdogGapPeak {
            t = (gap - underdogGapMin) / (underdogGapPeak - underdogGapMin)      // ramp in
        } else if gap <= underdogGapPlateau {
            t = 1.0                                                              // full-relief plateau
        } else {
            t = (underdogGapZero - gap) / (underdogGapZero - underdogGapPlateau) // fade out
        }
        return underdogReliefComp * Swift.max(0.0, t)
    }

    // Garbage-time edge damp: a team protecting a multi-score lead late deploys less
    // of its talent edge (backups in, vanilla play-calls, sit-on-the-lead) → its
    // scoring efficiency regresses toward neutral, capping the runaway margin from
    // the top. Keyed on the OFFENSE-relative score margin + clock: 1.0 (inert) until
    // late AND leading by `gtLeadPts`, then multiplies the edge scale down toward
    // `gtEdgeFloor`. Trailing / close / early ⇒ 1.0, so competitive games and equal
    // talent are byte-identical.
    private static let gtLeadPts   = 10     // multi-score lead that triggers coasting
    private static let gtEdgeDamp  = 0.055  // edge-scale reduction per point past the trigger
    private static let gtEdgeFloor = 0.35   // never fully erase the edge (still a pro offense)
    private static func garbageEdgeFactor(scoreDifferential: Int, quarter: Int, timeRemaining: Int) -> Double {
        let late = quarter >= 4 || (quarter == 3 && timeRemaining <= 420)  // Q4 or last 7 min of Q3
        guard late, scoreDifferential >= gtLeadPts else { return 1.0 }
        return max(gtEdgeFloor, 1.0 - gtEdgeDamp * Double(scoreDifferential - gtLeadPts + 1))
    }

    /// Asymmetric matchup-edge → completion shift (mirrors `deepEdgeCompletion`).
    private static func matchupEdgeCompletion(_ edge: Double) -> Double {
        edge >= 0 ? edge * coverEdgeSlopeUp : edge * coverEdgeSlopeDown
    }

    /// Per-depth minimum air yards (the short/mid ride floor).
    private static func shortMidAirFloor(_ d: PassDistance) -> Int {
        switch d {
        case .short: return 2
        case .mid:   return 11
        case .deep:  return deepAirFloor
        }
    }

    // Short/mid grand soft-cap: linear below the knee, exponential approach to
    // the ceiling above — replaces the old hard 0.85 clamp so an elite duo climbs
    // toward the ceiling without the brick wall that flattened the top.
    private static let shortMidCompFloor = 0.08
    private static let shortMidCompKnee  = 0.72
    private static let shortMidCompCeil  = 0.92
    private static func softCapCompletion(_ x: Double) -> Double {
        if x <= shortMidCompFloor { return shortMidCompFloor }
        if x <= shortMidCompKnee { return x }
        let span = shortMidCompCeil - shortMidCompKnee
        let over = x - shortMidCompKnee
        return shortMidCompKnee + span * (1.0 - exp(-over / span))
    }

    // Run crease-gate constants (Balance R3, Part A / A2-run). The OL crease both
    // yields yards (the raised lever) and gates the back's big play (probability
    // AND magnitude), fixing the elite-RB-beats-elite-OL inversion. All gates are
    // centered at blockingAdvantage 0 (neutral no-op → parity), dial-authorized.
    private static let runBlockYardGain      = 6.8   // OL crease yards (was 3.0) — the dominant OL lever
    private static let breakawayCreaseSlope  = 3.5   // breakaway-probability gate steepness (bad crease bites)
    private static let breakawayCreaseMin    = 0.20  // bad crease floors the odds here
    private static let breakawayCreaseMax    = 1.0   // no upward boost (avoids the runaway ceiling)
    private static let breakawayMagCenter    = 0.45  // global breakaway-magnitude trim (elite houses stay in band)
    private static let creaseYardSlope       = 1.2   // breakaway-magnitude gate steepness
    private static let breakawayYardMin      = 0.20
    private static let breakawayYardMax      = 0.30

    // Edge-crease constants (Balance R3 fix / A2-run-edge). Perimeter runs recover
    // their RB-speed contribution as extra edge yards = edgeBaseYards · edgeFactor ·
    // edgeSpeed · edgeGate. edgeSpeed (RB wheels) and edgeGate (OL crease) are both
    // 1.0 at neutral (70 speed, 0 crease) → the term is a flat edge bonus at neutral
    // and 0 for interior runs; the gate collapses it behind a beaten edge so speed
    // never swamps blocking. Dial-authorized.
    private static let edgeBaseYards         = 1.6   // neutral edge yards at edgeFactor 1.0
    private static let edgeSpeedSlope        = 0.010 // RB speed → edge multiplier (speed 90 ≈ 1.20×)
    private static let edgeSpeedMin          = 0.65  // a plodder still gets some edge behind a sealed line
    private static let edgeSpeedMax          = 1.40  // burner cap (no runaway)
    private static let edgeCreaseSlope       = 2.5   // OL crease → edge gate steepness
    private static let edgeCreaseMin         = 0.15  // a beaten edge nearly erases the term (RB speed can't save it)
    private static let edgeCreaseMax         = 1.50  // an elite seal opens the lane (capped)

    private static func qbAccuracyForDistance(_ attrs: QBAttributes, distance: PassDistance) -> Double {
        switch distance {
        case .short: return Double(attrs.accuracyShort)
        case .mid:   return Double(attrs.accuracyMid)
        case .deep:  return Double(attrs.accuracyDeep)
        }
    }

    private static func interceptionChance(
        accuracyRating: Double,
        dbBallSkills: Double,
        passDistance: PassDistance,
        decisionMaking: Int,
        pressure: Double,
        // P0-2: team-breadth compression (1.0 at parity / single-unit). The INT
        // talent net is a 0-centered differential channel just like completion /
        // matchup, so it rides the same scale — a whole-roster mismatch no longer
        // forces the drive-killing +2.8%/throw pick storm that collapsed the weak
        // offense's scoring. At parity edgeScale=1.0 ⇒ the INT band is byte-identical;
        // a lone ball-hawk CB keeps team gap ≈ 0 ⇒ scale ≈ 1 ⇒ its picks survive.
        edgeScale: Double = 1.0
    ) -> Double {
        let baseRate: Double
        switch passDistance {
        case .short: baseRate = 0.015
        case .mid:   baseRate = 0.025
        case .deep:  baseRate = 0.04
        }
        let accuracyMod = (70.0 - accuracyRating) / 1000.0
        // B6: pivot the DB ball-skills contribution on the 70 mean (was 50).
        // At the mean DB (≈70) this is 0, so INT falls back to the base rates
        // (1.5/2.5/4.0%), blending ~2.3% — the old pivot at 50 added ~+0.04 on
        // every throw, roughly doubling the pick rate.
        let dbMod = (dbBallSkills - 70.0) / 500.0
        // Mech 4: decision-making risk, amplified by pass-rush pressure. Widens
        // the clamp ceiling slightly so a reckless QB flushed from the pocket
        // can actually reach the higher risk; centered at 70 → mean-neutral.
        let riskMod = decisionRiskBonus(decisionMaking: decisionMaking, pressure: pressure)
        // P0-2: compress the whole 0-centered talent net; baseRate (the league
        // floor) is untouched, so equal talent still blends ~2.3%.
        return clamp(baseRate + (accuracyMod + dbMod + riskMod) * edgeScale, min: 0.005, max: 0.10)
    }

    private static func yardsAfterCatch(for player: SimPlayer, momentum: Double) -> Int {
        // Mech 1: fatigue drags effective speed on the run after the catch.
        let speedFactor = effectiveSpeed(player) / 100.0
        let agilityFactor = Double(player.physical.agility) / 100.0
        let yacBase = (speedFactor + agilityFactor) * 3.0 + momentum * 1.0
        return max(0, Int(Double.random(in: -1.0...yacBase).rounded()))
    }

    /// Share of pass targets funneled to the primary target group (the
    /// "field 11": top-3 WRs + best TE + best RB). The live 3D view and the
    /// play feed both feature these starters, so concentrating the sim's
    /// targets on them keeps the names on the field, in the feed, and in the
    /// box score pointing at the same players.
    private static let primaryTargetShare = 0.85

    /// The starters who soak up the vast majority of targets: the three best
    /// WRs plus the best TE and the best RB (by overall).
    private static func primaryTargets(among receivers: [SimPlayer]) -> Set<UUID> {
        var ids: Set<UUID> = []
        let topWRs = receivers
            .filter { $0.position == .WR }
            .sorted { $0.overall > $1.overall }
            .prefix(3)
        for wr in topWRs { ids.insert(wr.id) }
        if let te = receivers.filter({ $0.position == .TE }).max(by: { $0.overall < $1.overall }) {
            ids.insert(te.id)
        }
        if let rb = receivers.filter({ $0.position == .RB }).max(by: { $0.overall < $1.overall }) {
            ids.insert(rb.id)
        }
        return ids
    }

    /// R36: how strongly the QB's AWARENESS bends target selection toward
    /// the best separators. The route-weight exponent is
    /// `1 + (awareness - 70) * slope`: an aware QB (99) sharpens the weights
    /// (gamma ≈ 1.23 — finds the open man), a low-awareness QB (40) flattens
    /// them (gamma ≈ 0.76 — sprays the ball around). Awareness 70 = exactly
    /// today's distribution. Measured with `GameSimulator.debugSimulate`:
    /// points/team and completion % must stay inside ±1.5 pts / ±2 %-pts.
    private static let qbAwarenessTargetSlope = 0.008

    #if DEBUG
    /// Balance-harness switch: `GameSimulator.debugSimulate` measures the
    /// awareness targeting ON vs OFF over the SAME generated league (paired
    /// comparison — league generation is unseeded, so separate app launches
    /// can't be compared). Never set outside the debug harness.
    static var debugNeutralAwarenessTargeting = false

    // R37 balance-harness switches — one per player-IQ mechanic so each is
    // measured in isolation over the same league (paired comparison).
    /// True = skip the play-action box-awareness bite roll (mechanic 2).
    static var debugNeutralPlayActionRead = false
    /// True = old INT credit (top-4 ball skills, uniform) (mechanic 3).
    static var debugNeutralINTCredit = false
    /// True = no vision scaling on breakaway/TFL odds (mechanic 4).
    static var debugNeutralCarrierVision = false
    /// True = old flat fumble formula (mechanic 5).
    static var debugNeutralBallSecurity = false

    // R38 attribute-gap balance-harness switches — one per mechanic so each
    // is measured in isolation over the same league (paired comparison).
    /// True = no fatigue penalty on effective physical attributes (mech 1).
    static var debugNeutralFatiguePerf = false
    /// True = no QB mobility/pocket-presence sack avoidance (mech 2).
    static var debugNeutralQBMobilitySack = false
    /// True = no arm-strength deep-accuracy / velocity support (mech 3).
    static var debugNeutralArmStrength = false
    /// True = no WR-release-vs-DB-press short-throw modifier (mech 4).
    static var debugNeutralWRPress = false
    /// True = old single-roll completion (no drop / contested split) (mech 5).
    static var debugNeutralContestedDrop = false
    /// True = no away-team false-start guilt boost (mech 6).
    static var debugNeutralHomeAwayPenalty = false

    // #36B mental-game balance-harness switch. Composure is the ONLY mental
    // mechanic on the shared quick-sim path (hot-streak and ego are live-only,
    // see LiveGameEngine), so it is the only one the quick-sim gate measures.
    /// True = no composure pressure penalty on QB accuracy (mental mech 3).
    static var debugNeutralComposure = false

    // R39 attribute-gap balance-harness switches — one per ATTRIBUTE (each
    // bundles that attribute's sub-connections) so it is measured in isolation
    // over the SAME league (paired comparison).
    /// True = neutralize ACCELERATION: DL first-step pass rush (1a), WR release
    /// burst vs press (1b, live), RB burst through the hole (1c).
    static var debugNeutralAcceleration = false
    /// True = neutralize STRENGTH: OL/DL trench win (2a), break-tackle through
    /// contact (2b), CB press-jam (2c, live).
    static var debugNeutralStrength = false
    /// True = neutralize AGILITY: RB open-field juke (3) + WR route separation.
    static var debugNeutralAgility = false
    /// True = neutralize DECISIONMAKING risk role: restores the pre-R39
    /// decisionMaking→completion term and drops the turnover-risk term (4).
    static var debugNeutralDecision = false

    // R41 scheme-familiarity balance-harness switch. Neutralizes ONLY the new
    // DIRECT familiarity term (the fit-scaled multiplier that shipped earlier
    // stays active). Measured asymmetrically: a high-familiarity squad vs a
    // low-familiarity squad — the well-drilled team should out-gain the one
    // still learning the playbook, while the aggregate holds.
    /// True = drop the fit-independent familiarity yardage term (R41).
    static var debugNeutralSchemeFamiliarity = false
    #endif

    // MARK: - Player IQ Tuning (R37)

    /// Bite-probability slope per awareness point below/above 70 for the
    /// play-action read: a 40-awareness box bites ~95% of fakes, a
    /// 99-awareness box ~5% (clamped).
    private static let paBiteAwarenessSlope = 0.02
    /// Completion-chance swing when the box bites (+) or stays home (−).
    /// Symmetric, so a league-average box leaves PA expected value flat.
    private static let paBiteCompletionSwing = 0.06
    /// Breakaway-odds multiplier slope per point of carrier sight
    /// (vision 60% + awareness 40%) around the 70-rated league mean.
    private static let carrierVisionSlope = 0.008
    /// Fumble-chance reduction per point of ball security
    /// (break-tackle 50% + awareness 50%) above the 70-rated mean.
    private static let ballSecuritySlope = 0.00004

    // MARK: - Attribute-Gap Tuning (R38)

    /// Fatigue drag (mech 1): once fatigue crosses 70 the effective physical
    /// rating drops by `(fatigue-70) * slope`, capped at `-cap` points.
    /// A 100-fatigue player loses ~4.5 (below the cap) — bounded, symmetric
    /// (both sides tire), so team scoring stays flat while tired starters
    /// individually fade. Applied inside the shared rating extractors so quick
    /// sim and the live engine get it identically.
    private static let fatiguePerfThreshold = 70.0
    // Trimmed from the 0.15/6 spec after the balance gate: under a preloaded
    // tired league the 0.15 slope dragged sacks −1.6/game (>±1). 0.10/5 keeps
    // the stress-test sacks delta inside ±1 while still fading tired starters.
    private static let fatiguePerfSlope = 0.10
    private static let fatiguePerfCap = 5.0

    /// QB sack avoidance (mech 2): a mobile QB with pocket feel slides pressure.
    /// `(scrambling + pocketPresence - 100) / divisor`, clamped to 0…0.05, is
    /// SUBTRACTED from the sack chance. The task's /2000 spec assumes a
    /// realistic ~5 sacks/game; this harness runs ~20/game (weak generated
    /// OLs), which quadruples the absolute delta, so the gate pushed the
    /// divisor to 7000 to land sacks/game inside ±1 (−2.2 → ~−1.0).
    private static var qbMobilitySackDivisor = 7000.0
    private static let qbMobilitySackCap = 0.05

    /// Arm strength (mech 3): deep-ball accuracy support, `(arm-70)/25` points
    /// clamped to ±3, added to the deep accuracy rating only.
    private static let armDeepAccuracyDivisor = 25.0
    private static let armDeepAccuracyCap = 3.0
    /// Presentational flight-speed multiplier: ±15% across the 40–99 range.
    private static let armVelocitySlope = 0.005

    /// WR release vs DB press (mech 4): on man-press short throws only,
    /// `(release - press)/500` clamped to ±0.04 shifts the completion odds.
    /// Live games only (quick sim passes no package), and near-zero mean.
    private static let wrPressDivisor = 500.0
    private static let wrPressCap = 0.04

    /// Drop / contested-catch model (mech 5). Open receivers drop catchable
    /// balls at ~2–4% (hands-scaled); covered receivers occasionally win a
    /// contested grab. Calibrated so total completion % holds inside ±2.
    private static let dropBase = 0.035
    private static let dropHandsSlope = 0.0006
    private static let dropMin = 0.02
    private static let dropMax = 0.05
    // contestedBase trimmed 0.05 → 0.03 by the gate: in this harness's low
    // (~25%) base-completion league the huge "covered" fraction makes contested
    // grabs over-add completions; 0.03 keeps total comp-% inside ±2 with margin.
    private static let contestedBase = 0.03
    private static let contestedDivisor = 700.0
    private static let contestedMin = 0.01
    private static let contestedMax = 0.14

    // MARK: - Attribute-Gap Tuning (R39)

    // Mech 1a — DL first step (acceleration) vs OL kick-slide closing the
    // pocket. (avgDLAccel − avgOLAccel)/divisor ADDED to sack chance, ±cap.
    // League accel means are equal, so the mean edge ≈ 0 and the sack rate holds.
    private static let accelPassRushDivisor = 900.0
    private static let accelPassRushCap = 0.02
    // Mech 1b — WR burst off the jam vs the corner's burst, man-press SHORT
    // throws only (live). (wrAccel − cbAccel)/divisor, ±cap. Near-zero mean.
    private static let accelReleaseDivisor = 700.0
    private static let accelReleaseCap = 0.03
    // Mech 1c — RB burst through the hole (straight-line). (accel−70)/100·scale
    // added to run yards; centered → the league rushing average holds.
    private static let accelBurstScale = 1.2

    // Mech 2a — trench STRENGTH. Pass pro: (olStr−dlStr)/divisor SUBTRACTED from
    // sack chance, ±cap. Run: (olStr−dlStr)/100·weight added to blockingAdvantage.
    private static let strengthTrenchSackDivisor = 1100.0
    private static let strengthTrenchSackCap = 0.02
    // Trimmed 0.35 → 0.22 by the gate: at n=100 the strength attribute's
    // isolated points delta hit +1.7 (>±1.5) because starters rate above the
    // 70 center, so the run-side bonuses add net yards; the lighter weight lands
    // it inside ±1.5.
    private static let strengthTrenchRunWeight = 0.22
    // Mech 2b — break-tackle through contact: (breakPower−70)/100·scale added to
    // run yards, breakPower = strength·0.5 + breakTackle·0.5. Centered.
    // Trimmed 1.3 → 0.9 with the trench weight for the same gate breach.
    private static let breakTackleContactScale = 0.9
    // Mech 2c — the corner's physical jam (strength) disrupts the release,
    // man-press SHORT throws only (live). (cbStr − wrStr)/divisor SUBTRACTED
    // from completion, ±cap. Near-zero mean.
    private static let strengthPressDivisor = 800.0
    private static let strengthPressCap = 0.025

    // Mech 3 — AGILITY (change of direction, distinct from acceleration's
    // straight-line burst). RB open-field juke: (agility−70)/100·scale added to
    // run yards (centered). WR route separation: (agility−70)·slope added to the
    // openness rating (centered → comp% holds).
    private static let agilityJukeScale = 1.2
    private static let agilitySeparationSlope = 0.12

    // Mech 4 — DECISIONMAKING as turnover RISK (awareness owns coverage
    // reading; see completionReadingAttr). (70 − decisionMaking)·slope, amplified
    // by pass-rush pressure, added to the interception chance. Centered at 70 →
    // the league turnover rate holds; the reckless force picks under duress, the
    // careful protect the ball.
    // Trimmed 0.00035/2.0 → 0.00016/1.0 by the gate: the Q4 clutch boost
    // (applyMoraleModifiers) inflates decisionMaking toward 99 in the fourth
    // quarter, so a 70-centered risk term skews strongly negative there and
    // dropped league turnovers −0.67/game (>±0.4). The lighter slope/gain keep
    // a reckless passer forcing picks under pressure while landing the aggregate
    // inside ±0.4.
    private static let decisionIntSlope = 0.00016
    private static let decisionPressureGain = 1.0

    // MARK: - Mental-Game Tuning (#36B + round 4)

    // Round 4 (mental states). The old downside-only composure penalty
    // (`composureThreshold`/`composureSlope`/`composureCap`) is RETIRED — it is
    // subsumed by the two-sided, leverage-scaled `composureSwing` below. All
    // magnitudes are 70-centered / heat-zero-neutral, so a composure-70 / heat-0
    // roster reproduces pre-round-4 behavior byte-for-byte.

    // -- Leverage index weights (situational pressure, clamped to [0,1]) --
    /// Q4 / OT.
    private static let leverageQ4 = 0.40
    /// Red zone (inside the 20).
    private static let leverageRedZone = 0.30
    /// 3rd/4th-and-medium-or-more.
    private static let leverageThirdMedium = 0.30
    /// Two-minute (end of half or game).
    private static let leverageTwoMinute = 0.30
    /// Trailing by 9+.
    private static let leverageTrailing = 0.30

    // -- Composure swing (poise, both-sided) --
    /// League-mean composure — the swing pivot, so aggregate ~0.
    private static let composureNeutral = 70.0
    /// Accuracy points per unit swing on the QB (composure 40 @ full leverage →
    /// −3.0 acc, matching the old cap; composure 90 → +2.0).
    private static let composureAccuracyGain = 0.10
    /// Completion-probability slope per unit swing (composure 45 @ full leverage
    /// → −0.045 comp; 90 → +0.036).
    private static let composureSwingSlope = 0.0018
    /// Run-yard slope per unit swing (composure 45 @ full leverage → −0.30 yд).
    private static let composureRunSlope = 0.012

    // -- Heat (hot/cold FORM) effect magnitudes --
    /// Full-hot sensitive WR: +4.5pp completion (a 50% ball → ~54.5%).
    private static let heatPassCompletionPoints = 0.045
    /// Hot QB is dialed in — a smaller completion lane.
    private static let heatQBCompletionPoints = 0.020
    /// Hot CB tightens the window (subtracted from completion).
    private static let heatDBCompletionPoints = 0.030
    /// Deep is rarer / higher-variance, so a smaller per-player deep lane.
    private static let heatDeepCompletionPoints = 0.030
    /// ±0.25 yд/carry at full heat. Trimmed from the design's 0.35 after the
    /// `heat-dist` full-game gate: a net-positive offense keeps its back warm
    /// most of the game, so 0.35 nudged aggregate rushing ~+0.15 (over the tight
    /// edge 4.0-4.1 band); 0.25 lands the live-heat aggregate drift ≤ ~0.10 while
    /// keeping the effect visible.
    private static let heatRunYardPoints = 0.25
    /// Breakaway-CHANCE multiplier slope (×[0.90, 1.10]). Trimmed with the yard
    /// points for the same aggregate reason.
    private static let heatBreakawaySlope = 0.10

    // -- Dedicated grand caps (a THIRD lane, parallel to the play-memory malus
    //    cap and the defensive-bite cap — each independently bounded) --
    /// Cap on the summed pass mental delta (heat + composure).
    private static let mentalCompletionCap = 0.10
    /// Cap on the summed run mental yardage (heat + composure).
    private static let mentalRunYardCap = 0.60

    /// Away false-start guilt boost (mech 6): the crowd noise on the road
    /// jumps the false-start SHARE of the offense's flags by +20% (relative);
    /// the overall flag frequency is untouched (rolled by the caller), so the
    /// home team's share falls to match.
    private static let awayFalseStartBoost = 1.2

    // MARK: - Attribute-Gap Helpers (R38)

    /// Effective-rating drag from fatigue (mech 1). Zero at/under the
    /// threshold; grows linearly, capped. Neutralized by the balance harness.
    private static func fatiguePenalty(_ fatigue: Int) -> Double {
        #if DEBUG
        if debugNeutralFatiguePerf { return 0 }
        #endif
        guard Double(fatigue) > fatiguePerfThreshold else { return 0 }
        return Swift.min(fatiguePerfCap, (Double(fatigue) - fatiguePerfThreshold) * fatiguePerfSlope)
    }

    /// A player's effective speed after fatigue drag.
    private static func effectiveSpeed(_ p: SimPlayer) -> Double {
        Swift.max(1.0, Double(p.physical.speed) - fatiguePenalty(p.fatigue))
    }

    /// Sack-chance reduction earned by a mobile, poised QB (mech 2).
    private static func qbMobilitySackReduction(_ attrs: QBAttributes) -> Double {
        #if DEBUG
        if debugNeutralQBMobilitySack { return 0 }
        #endif
        let raw = (Double(attrs.scrambling) + Double(attrs.pocketPresence) - 100.0) / qbMobilitySackDivisor
        return clamp(raw, min: 0, max: qbMobilitySackCap)
    }

    /// Deep-accuracy bonus from arm strength (mech 3), ±cap points.
    private static func armDeepAccuracyBonus(_ attrs: QBAttributes) -> Double {
        #if DEBUG
        if debugNeutralArmStrength { return 0 }
        #endif
        return clamp(Double(attrs.armStrength - 70) / armDeepAccuracyDivisor,
                     min: -armDeepAccuracyCap, max: armDeepAccuracyCap)
    }

    /// Presentational flight-speed multiplier from arm strength (mech 3).
    private static func armVelocityScale(_ attrs: QBAttributes) -> Double {
        #if DEBUG
        if debugNeutralArmStrength { return 1.0 }
        #endif
        return clamp(1.0 + Double(attrs.armStrength - 70) * armVelocitySlope, min: 0.85, max: 1.15)
    }

    /// A receiver's SEPARATION rating (mech 5): getting open is route work,
    /// not hands. Replaces the catching-blended rating in the openness roll.
    /// Mech 1: fatigue drags the route legs here too.
    private static func receiverSeparationRating(for player: SimPlayer) -> Double {
        let drag = fatiguePenalty(player.fatigue)
        switch player.positionAttributes {
        case .wideReceiver(let a): return Double(a.routeRunning) - drag
        case .tightEnd(let a):     return Double(a.routeRunning) - drag
        case .runningBack(let a):  return Double(a.receiving) - drag
        default:                   return 40.0
        }
    }

    /// A receiver's HANDS rating (mech 5): drives the drop roll on open balls.
    private static func receiverHandsRating(for player: SimPlayer) -> Double {
        switch player.positionAttributes {
        case .wideReceiver(let a): return Double(a.catching)
        case .tightEnd(let a):     return Double(a.catching)
        case .runningBack(let a):  return Double(a.receiving)
        default:                   return 40.0
        }
    }

    /// A receiver's CONTESTED-catch rating (mech 5): spectacular catch + hands
    /// for winning the ball in traffic.
    private static func receiverContestedRating(for player: SimPlayer) -> Double {
        switch player.positionAttributes {
        case .wideReceiver(let a): return Double(a.spectacularCatch) * 0.5 + Double(a.catching) * 0.5
        case .tightEnd(let a):     return Double(a.catching)
        case .runningBack(let a):  return Double(a.receiving)
        default:                   return 40.0
        }
    }

    /// A receiver's RELEASE rating vs press (mech 4).
    private static func receiverReleaseRating(for player: SimPlayer) -> Double {
        switch player.positionAttributes {
        case .wideReceiver(let a): return Double(a.release)
        case .tightEnd(let a):     return Double(a.routeRunning)   // no press-release attr
        case .runningBack(let a):  return Double(a.receiving)
        default:                   return 50.0
        }
    }

    /// A defensive back's PRESS rating (mech 4), fatigue-dragged.
    private static func dbPressRating(for player: SimPlayer) -> Double {
        if case .defensiveBack(let attrs) = player.positionAttributes {
            return Swift.max(1.0, Double(attrs.press) - fatiguePenalty(player.fatigue))
        }
        return 50.0
    }

    // MARK: - Position-Normalised Physicals (R39 gap terms)

    /// The rating the R39 attribute-gap terms are centred on.
    private static let physicalPivot = 70.0

    /// A physical attribute measured against the player's OWN position prior,
    /// re-based on `physicalPivot`.
    ///
    /// Every R39 gap mechanic is documented as "near-zero mean league-wide".
    /// That held while `PhysicalAttributes.random()` gave every position the
    /// same uniform 40…99 draw, so a raw DL-minus-OL difference really did
    /// average 0. Rosters now come from the shared `PositionPhysicalProfile`
    /// table, where the field units are NOT symmetric: the starting front's
    /// acceleration priors are DE 76 / DT 62 against LT 52 / LG-C-RG 50 / RT 52,
    /// a permanent **+18** edge that pins `accelPassRushBonus` on its +0.02 cap
    /// on essentially every snap for every team — ~+2 pp of league sack rate on
    /// top of a base tuned to ≈7 %, and zero of the per-matchup separation the
    /// term exists for.
    ///
    /// Comparing each unit against its own prior restores both properties: a
    /// front that is quick *for a front* still beats a line that is slow *for a
    /// line*, and a league-average matchup nets exactly zero. Absolute physicals
    /// stay absolute everywhere else (breakaway speed, YAC, coverage closing
    /// speed) — only these centred/differential terms are normalised.
    ///
    /// AGILITY is deliberately left raw: `agilityJukeBonus` /
    /// `agilitySeparationBonus` share their input with `yardsAfterCatch`, which
    /// reads agility on the absolute scale (a fast, shifty receiver really does
    /// run away from people after the catch). The residual is a ~+0.14 ypc lean
    /// from the RB agility prior of 82 against the terms' 70 centre, which lands
    /// the blended run inside its 4.0–4.6 band either way; splitting the two
    /// readings needs a separate agility pass, not a normalisation here.
    private static func relativeAcceleration(_ p: SimPlayer) -> Double {
        Double(p.physical.acceleration)
            - PositionPhysicalProfile.profile(for: p.position).acceleration.mean
            + physicalPivot
    }

    /// Position-normalised strength — see `relativeAcceleration`.
    /// (OL priors average 85.2 against a DL front's 82.5, so the raw trench
    /// strength differential also carries a standing bias.)
    private static func relativeStrength(_ p: SimPlayer) -> Double {
        Double(p.physical.strength)
            - PositionPhysicalProfile.profile(for: p.position).strength.mean
            + physicalPivot
    }

    // MARK: - Attribute-Gap Helpers (R39)

    /// Sack-chance INCREASE from a quicker DL first step (acceleration) beating
    /// the OL off the snap (mech 1a). Near-zero mean → league sack rate holds.
    private static func accelPassRushBonus(dlAccel: Double, olAccel: Double) -> Double {
        #if DEBUG
        if debugNeutralAcceleration { return 0 }
        #endif
        return clamp((dlAccel - olAccel) / accelPassRushDivisor,
                     min: -accelPassRushCap, max: accelPassRushCap)
    }

    /// Completion swing from the WR's burst off the jam vs the corner's burst,
    /// man-press short throws only (mech 1b, live). Near-zero mean.
    private static func accelReleaseBonus(wrAccel: Double, cbAccel: Double) -> Double {
        #if DEBUG
        if debugNeutralAcceleration { return 0 }
        #endif
        return clamp((wrAccel - cbAccel) / accelReleaseDivisor,
                     min: -accelReleaseCap, max: accelReleaseCap)
    }

    /// Run-yardage burst through the hole from acceleration (mech 1c), centered.
    private static func accelBurstBonus(for rb: SimPlayer) -> Double {
        #if DEBUG
        if debugNeutralAcceleration { return 0 }
        #endif
        return (relativeAcceleration(rb) - physicalPivot) / 100.0 * accelBurstScale
    }

    /// Sack-chance REDUCTION from a stronger OL holding the pocket (mech 2a).
    private static func strengthTrenchSackReduction(olStrength: Double, dlStrength: Double) -> Double {
        #if DEBUG
        if debugNeutralStrength { return 0 }
        #endif
        return clamp((olStrength - dlStrength) / strengthTrenchSackDivisor,
                     min: -strengthTrenchSackCap, max: strengthTrenchSackCap)
    }

    /// Run blocking-advantage bump from OL strength moving the DL (mech 2a, run).
    private static func strengthTrenchRunBonus(olStrength: Double, dlStrength: Double) -> Double {
        #if DEBUG
        if debugNeutralStrength { return 0 }
        #endif
        return (olStrength - dlStrength) / 100.0 * strengthTrenchRunWeight
    }

    /// Run-yardage bump from breaking arm tackles through contact (mech 2b),
    /// breakPower = physical strength 50% + break-tackle 50%. Centered.
    private static func breakTackleBonus(for rb: SimPlayer, attrs: RBAttributes) -> Double {
        #if DEBUG
        if debugNeutralStrength { return 0 }
        #endif
        let breakPower = relativeStrength(rb) * 0.5 + Double(attrs.breakTackle) * 0.5
        return (breakPower - 70.0) / 100.0 * breakTackleContactScale
    }

    /// Completion REDUCTION from the corner's physical jam (strength) disrupting
    /// the release, man-press short throws only (mech 2c, live). Near-zero mean.
    private static func strengthPressDisruption(cbStrength: Double, wrStrength: Double) -> Double {
        #if DEBUG
        if debugNeutralStrength { return 0 }
        #endif
        return clamp((cbStrength - wrStrength) / strengthPressDivisor,
                     min: -strengthPressCap, max: strengthPressCap)
    }

    /// Run-yardage bump from the open-field juke (agility, change of direction —
    /// distinct from acceleration's straight-line burst) (mech 3). Centered.
    private static func agilityJukeBonus(for rb: SimPlayer) -> Double {
        #if DEBUG
        if debugNeutralAgility { return 0 }
        #endif
        return (Double(rb.physical.agility) - 70.0) / 100.0 * agilityJukeScale
    }

    /// Openness bump from a receiver's change-of-direction winning a step of
    /// route separation (mech 3, WR/TE only). Centered at 70 → comp% holds.
    private static func agilitySeparationBonus(for player: SimPlayer) -> Double {
        #if DEBUG
        if debugNeutralAgility { return 0 }
        #endif
        switch player.positionAttributes {
        case .wideReceiver, .tightEnd:
            return (Double(player.physical.agility) - 70.0) * agilitySeparationSlope
        default:
            return 0
        }
    }

    /// The QB attribute that drives the "reading the coverage" contribution to
    /// completion (mech 4 de-overlap): AWARENESS when the decision mechanic is
    /// active (awareness owns recognition, decisionMaking owns risk), the legacy
    /// decisionMaking when neutralized — for the paired balance gate.
    private static func completionReadingAttr(for qb: SimPlayer) -> Double {
        #if DEBUG
        if debugNeutralDecision { return Double(qb.mental.decisionMaking) }
        #endif
        return Double(qb.mental.awareness)
    }

    /// Interception-chance ADD from throwing risk (mech 4): a reckless
    /// decision-maker forces picks, amplified by pass-rush pressure; the careful
    /// protect the ball. Centered at 70 → league turnover rate holds.
    private static func decisionRiskBonus(decisionMaking: Int, pressure: Double) -> Double {
        #if DEBUG
        if debugNeutralDecision { return 0 }
        #endif
        return (70.0 - Double(decisionMaking)) * decisionIntSlope
            * (1.0 + pressure * decisionPressureGain)
    }

    /// Round 4 (mental states): the situational LEVERAGE of a snap, `[0, 1]`.
    /// Neutral early-down snaps score 0 → composure inert (parity with the old
    /// "big moment only", generalized). Shared by both engines through the same
    /// `simulatePlay` entry, so composure behaves identically live and in sim.
    static func leverageIndex(down: Int, distance: Int, quarter: Int,
                              timeRemaining: Int, yardLine: Int,
                              scoreDifferential: Int) -> Double {
        var L = 0.0
        if quarter >= 4 { L += leverageQ4 }                                  // Q4/OT
        if (100 - yardLine) <= 20 { L += leverageRedZone }                   // red zone
        if down >= 3 && distance >= 4 { L += leverageThirdMedium }           // 3rd/4th & medium+
        if timeRemaining <= 120 && (quarter == 2 || quarter >= 4) {          // two-minute
            L += leverageTwoMinute
        }
        if scoreDifferential <= -9 { L += leverageTrailing }                 // trailing by 9+
        return Swift.min(1.0, L)
    }

    /// Round 4 (mental states): the two-sided composure swing for a player at a
    /// given leverage. `(composure − 70) × leverage` — the poised rise in the
    /// moment, the shaky sag. Composure 70 (or leverage 0) ⇒ 0, so a neutral
    /// snap and the all-70 harness are byte-identical to pre-round-4. The
    /// balance-harness debug gate rides on the swing (replacing the retired
    /// `composurePenalty` gate).
    static func composureSwing(_ player: SimPlayer, _ leverage: Double) -> Double {
        #if DEBUG
        if debugNeutralComposure { return 0 }
        #endif
        return (player.composureRating - composureNeutral) * leverage
    }

    /// Drop probability on an open, catchable ball (mech 5).
    /// P0-2: the hands deviation from the 70 mean is a 0-centered talent channel,
    /// so it rides the team-breadth `edgeScale` (1.0 at parity / single-unit).
    private static func dropChance(for target: SimPlayer, edgeScale: Double = 1.0) -> Double {
        let hands = receiverHandsRating(for: target)
        return clamp(dropBase - (hands - 70.0) * dropHandsSlope * edgeScale, min: dropMin, max: dropMax)
    }

    /// Contested-catch probability in tight coverage (mech 5).
    /// P0-2: the receiver-vs-DB contested edge is 0-centered, so it rides `edgeScale`.
    private static func contestedCatchChance(target: SimPlayer, dbBallSkills: Double, edgeScale: Double = 1.0) -> Double {
        let edge = receiverContestedRating(for: target) - dbBallSkills
        return clamp(contestedBase + edge * edgeScale / contestedDivisor, min: contestedMin, max: contestedMax)
    }

    // MARK: - Player IQ Helpers (R37)

    /// Discipline proxy: how rarely a player beats himself. Awareness reads
    /// the snap count and the situation; decision making avoids the dumb grab.
    private static func disciplineRating(_ p: SimPlayer) -> Double {
        Double(p.mental.awareness + p.mental.decisionMaking) / 2.0
    }

    /// Weighted pick where the WEIGHT GROWS as discipline falls, and tired
    /// players jump earlier / grab more — the penalty-culprit draw.
    private static func indisciplineWeightedPick(from players: [SimPlayer]) -> SimPlayer? {
        weightedPickBy(players) { p in
            max(5.0, 105.0 - disciplineRating(p)) * (1.0 + Double(p.fatigue) / 150.0)
        }
    }

    /// Generic roulette pick over arbitrary non-negative weights.
    private static func weightedPickBy(
        _ players: [SimPlayer], weight: (SimPlayer) -> Double
    ) -> SimPlayer? {
        guard !players.isEmpty else { return nil }
        let weights = players.map { max(0.001, weight($0)) }
        var roll = Double.random(in: 0..<weights.reduce(0, +))
        for (index, w) in weights.enumerated() {
            roll -= w
            if roll <= 0 { return players[index] }
        }
        return players.last
    }

    // Starter pools mirroring `FieldUnit`'s best-by-position picks, so the
    // names the sim credits are the players the live 3D field is showing.

    /// The five starting linemen (best per OL spot).
    private static func startingOL(_ players: [SimPlayer]) -> [SimPlayer] {
        var starters: [SimPlayer] = []
        for position in [Position.LT, .LG, .C, .RG, .RT] {
            if let best = players.filter({ $0.position == position })
                .max(by: { $0.overall < $1.overall }) {
                starters.append(best)
            }
        }
        return starters.isEmpty ? players.filter { isOL($0) } : starters
    }

    /// The starting front four (top-2 DE + top-2 DT by overall).
    private static func startingDL(_ players: [SimPlayer]) -> [SimPlayer] {
        let ends = players.filter { $0.position == .DE }
            .sorted { $0.overall > $1.overall }.prefix(2)
        let tackles = players.filter { $0.position == .DT }
            .sorted { $0.overall > $1.overall }.prefix(2)
        let unit = Array(ends) + Array(tackles)
        return unit.isEmpty ? players.filter { isDL($0) } : unit
    }

    /// The starting linebacker trio (top-3 by overall).
    private static func startingLBs(_ players: [SimPlayer]) -> [SimPlayer] {
        Array(players.filter { isLB($0) }.sorted { $0.overall > $1.overall }.prefix(3))
    }

    /// The starting secondary (top-2 CB + top-2 S by overall).
    private static func startingDBs(_ players: [SimPlayer]) -> [SimPlayer] {
        let corners = players.filter { $0.position == .CB }
            .sorted { $0.overall > $1.overall }.prefix(2)
        let safeties = players.filter { $0.position == .FS || $0.position == .SS }
            .sorted { $0.overall > $1.overall }.prefix(2)
        let unit = Array(corners) + Array(safeties)
        return unit.isEmpty ? players.filter { isDB($0) } : unit
    }

    /// Everyone who can plausibly get home on a dropback: the front four
    /// plus the blitzing backers.
    private static func passRushPool(_ players: [SimPlayer]) -> [SimPlayer] {
        startingDL(players) + startingLBs(players)
    }

    /// Pass-rush credit score: DL by rush moves, LB discounted (they only
    /// come on a blitz).
    private static func passRushScore(_ p: SimPlayer) -> Double {
        isDL(p) ? dlPassRushRating(for: p) : lbBlitzRating(for: p) * 0.55
    }

    /// Interception-credit score: hands + head (ball skills 55%, awareness
    /// 45%) — the smart safety picks it more often (R37, mechanic 3).
    private static func intCreditScore(_ p: SimPlayer) -> Double {
        dbBallSkillsRating(for: p) * 0.55 + Double(p.mental.awareness) * 0.45
    }

    /// Tackler at/behind the line: block-shedders and downhill backers.
    private static func stuffTackler(_ players: [SimPlayer]) -> SimPlayer? {
        weightedPickBy(startingDL(players) + startingLBs(players)) { p in
            let score = isDL(p) ? dlBlockSheddingRating(for: p) : lbTacklingRating(for: p)
            return score * score
        }
    }

    /// Open-field chase-down on a breakaway: the secondary, by wheels.
    private static func chaseTackler(_ players: [SimPlayer]) -> SimPlayer? {
        weightedPickBy(startingDBs(players)) { effectiveSpeed($0) }
    }

    /// Routine-gain tackler: backers first, linemen in pursuit.
    private static func pursuitTackler(_ players: [SimPlayer]) -> SimPlayer? {
        weightedPickBy(startingLBs(players) + startingDL(players)) { p in
            let score = isLB(p) ? lbTacklingRating(for: p)
                : dlBlockSheddingRating(for: p) * 0.7
            return score * score
        }
    }

    /// Selects a pass target: ~85% of throws go to the primary group (top-3
    /// WR + best TE + best RB), the rest to depth receivers. Within each
    /// group the pick is weighted by route running + catching ability,
    /// sharpened or flattened by the QB's awareness (R36).
    private static func weightedReceiverSelection(
        _ receivers: [SimPlayer], qb: SimPlayer? = nil
    ) -> SimPlayer? {
        guard !receivers.isEmpty else { return nil }

        let primaryIDs = primaryTargets(among: receivers)
        let primary = receivers.filter { primaryIDs.contains($0.id) }
        let depth = receivers.filter { !primaryIDs.contains($0.id) }

        // Roll which group gets the target; fall back to whichever is
        // non-empty so tiny rosters keep working.
        let pool: [SimPlayer]
        if depth.isEmpty || (!primary.isEmpty && Double.random(in: 0..<1) < primaryTargetShare) {
            pool = primary.isEmpty ? receivers : primary
        } else {
            pool = depth
        }

        var gamma = qb.map { 1.0 + (Double($0.mental.awareness) - 70.0) * qbAwarenessTargetSlope }
        #if DEBUG
        if debugNeutralAwarenessTargeting { gamma = nil }
        #endif
        return weightedPick(from: pool, gamma: gamma) ?? receivers.randomElement()
    }

    /// Route-weight roulette pick within one group of receivers. `gamma`
    /// exponentiates the weights (QB awareness, R36); nil or 1.0 = the
    /// baseline distribution exactly.
    private static func weightedPick(from receivers: [SimPlayer],
                                     gamma: Double? = nil) -> SimPlayer? {
        guard !receivers.isEmpty else { return nil }
        var weights = receivers.map { receiverRouteWeight(for: $0) }
        if let gamma, gamma != 1.0 {
            weights = weights.map { pow(max($0, 0), gamma) }
        }
        let totalWeight = weights.reduce(0, +)
        guard totalWeight > 0 else { return receivers.randomElement() }

        var roll = Double.random(in: 0..<totalWeight)
        for (index, weight) in weights.enumerated() {
            roll -= weight
            if roll <= 0 {
                return receivers[index]
            }
        }
        return receivers.last
    }

    // MARK: - Description Generators

    private static func completionDescription(qb: SimPlayer, target: SimPlayer, yards: Int, firstDown: Bool) -> String {
        let firstDownText = firstDown ? " for a first down" : ""
        if yards >= 20 {
            return "\(qb.fullName) connects with \(target.fullName) for a \(yards)-yard gain\(firstDownText)!"
        }
        return "\(qb.fullName) throws \(yards) yards to \(target.fullName)\(firstDownText)."
    }

    /// Rush line. R37: when a tackler is credited he is NAMED, with the
    /// phrasing keyed to the play's shape (TFL / stuff / chase-down / big
    /// hit / routine gain). Nil tackler reproduces the classic lines.
    private static func rushDescription(rb: SimPlayer, yards: Int, firstDown: Bool,
                                        tackler: SimPlayer? = nil, bigHit: Bool = false) -> String {
        let firstDownText = firstDown ? " for a first down" : ""
        if yards < 0 {
            if let tackler {
                return "\(rb.fullName) is dropped for a loss of \(abs(yards)) by \(tackler.fullName)."
            }
            return "\(rb.fullName) is stopped for a loss of \(abs(yards)) yards."
        }
        if yards == 0 {
            if let tackler {
                return "\(rb.fullName) is stuffed at the line by \(tackler.fullName)."
            }
            return "\(rb.fullName) is stopped for no gain."
        }
        if yards == 1, let tackler {
            return "\(rb.fullName) squeezes out a yard before \(tackler.fullName) shuts the door\(firstDownText)."
        }
        if yards >= 15 {
            if let tackler {
                return "\(rb.fullName) breaks free for a \(yards)-yard run\(firstDownText) — finally run down in the open field by \(tackler.fullName)!"
            }
            return "\(rb.fullName) breaks free for a \(yards)-yard run\(firstDownText)!"
        }
        if bigHit, let tackler {
            return "\(tackler.fullName) lays the wood on \(rb.fullName) after a \(yards)-yard gain\(firstDownText)!"
        }
        if let tackler {
            return "\(rb.fullName) rushes for \(yards) yards\(firstDownText) — brought down by \(tackler.fullName)."
        }
        return "\(rb.fullName) rushes for \(yards) yards\(firstDownText)."
    }

    /// Sack line naming the credited rusher (nil = classic line).
    private static func sackDescription(qb: SimPlayer, sacker: SimPlayer?, yards: Int) -> String {
        guard let sacker else {
            return "\(qb.fullName) is sacked for a loss of \(yards) yards."
        }
        let pool = [
            "\(qb.fullName) is sacked by \(sacker.fullName) for a loss of \(yards) yards.",
            "\(sacker.fullName) gets home and drops \(qb.fullName) for a loss of \(yards).",
            "\(sacker.fullName) collapses the pocket and buries \(qb.fullName) — sack for -\(yards).",
        ]
        return pool.randomElement() ?? pool[0]
    }

    /// Named pass-breakup line (variation pool).
    private static func breakupDescription(qb: SimPlayer, target: SimPlayer,
                                           defender: SimPlayer) -> String {
        let pool = [
            "\(qb.fullName)'s pass to \(target.fullName) is broken up by \(defender.fullName).",
            "Diving breakup by \(defender.fullName) — incomplete intended for \(target.fullName).",
            "\(defender.fullName) gets a hand in and knocks it away from \(target.fullName).",
            "\(defender.fullName) blankets \(target.fullName) and swats it down at the catch point.",
        ]
        return pool.randomElement() ?? pool[0]
    }

    /// Hurried-throw line crediting the rusher who forced it (no sack, no stat).
    /// Returns the chosen line AND whether it was a deliberate throwaway (pool
    /// index 0 "throws it away" or 2 "fires wide" — off-target on purpose; index
    /// 1 "hurried throw" is a contested near-miss). Derived from the SAME single
    /// `randomElement()` draw so the RNG stream is unchanged (FIX-2).
    private static func pressureDescription(qb: SimPlayer, target: SimPlayer,
                                            rusher: SimPlayer)
        -> (text: String, isThrowaway: Bool) {
        let pool = [
            "Under pressure from \(rusher.fullName), \(qb.fullName) throws it away.",
            "\(rusher.fullName) is in his face — \(qb.fullName)'s hurried throw falls incomplete.",
            "Flushed by \(rusher.fullName), \(qb.fullName) fires wide of \(target.fullName).",
        ]
        let chosen = pool.randomElement() ?? pool[0]
        let isThrowaway = (chosen == pool[0] || chosen == pool[2])
        return (chosen, isThrowaway)
    }

    /// Dropped-pass line (R38 mech 5): the receiver got open and the throw
    /// was there — the hands failed. Distinct from a coverage breakup.
    private static func dropDescription(qb: SimPlayer, target: SimPlayer) -> String {
        let pool = [
            "\(target.fullName) gets open but DROPS the pass from \(qb.fullName).",
            "Right on the money from \(qb.fullName) — but \(target.fullName) can't hang on. Dropped.",
            "\(target.fullName) has it hit his hands and drops it — a costly miss.",
        ]
        return pool.randomElement() ?? pool[0]
    }

    /// Contested-grab line (R38 mech 5): a rare catch won in tight coverage.
    private static func contestedCatchDescription(qb: SimPlayer, target: SimPlayer,
                                                  yards: Int, firstDown: Bool) -> String {
        let firstDownText = firstDown ? " for a first down" : ""
        let pool = [
            "\(qb.fullName) throws it up and \(target.fullName) rips it away in coverage — \(yards)-yard grab\(firstDownText)!",
            "SPECTACULAR catch by \(target.fullName) over the defender for \(yards) yards\(firstDownText)!",
            "\(target.fullName) wins the contested ball in traffic — \(yards) yards\(firstDownText).",
        ]
        return pool.randomElement() ?? pool[0]
    }

    /// Plain-miss variation pool (no defensive credit).
    private static func incompletionVariant(qb: SimPlayer, target: SimPlayer) -> String {
        let pool = [
            "\(qb.fullName) sails it high — incomplete intended for \(target.fullName).",
            "\(target.fullName) can't haul it in — the pass falls incomplete.",
            "\(qb.fullName)'s throw skips off the turf in front of \(target.fullName).",
        ]
        return pool.randomElement() ?? pool[0]
    }

    // MARK: - Scheme Fit Helpers

    /// Calculates a scheme fit modifier for a group of players.
    /// Returns a value typically in the range -0.05 to +0.10, representing the
    /// percentage adjustment to yard calculations based on how well players fit their scheme.
    private static func schemeFitModifier(
        players: [SimPlayer],
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> Double {
        guard offensiveScheme != nil || defensiveScheme != nil else { return 0.0 }
        guard !players.isEmpty else { return 0.0 }

        let avgFit = players.reduce(0.0) { sum, player in
            sum + CoachingEngine.schemeFit(
                player: player,
                offensiveScheme: offensiveScheme,
                defensiveScheme: defensiveScheme
            )
        } / Double(players.count)

        // Scheme familiarity, resolved once per player into the raw 0-100
        // "% learned" and the 0.70-1.0 performance multiplier.
        func schemeName(for player: SimPlayer) -> String? {
            player.position.side == .offense ? offensiveScheme?.rawValue
                                             : defensiveScheme?.rawValue
        }

        // Fit-scaled multiplier (shipped): players who haven't learned the
        // scheme convert their scheme FIT into yards less fully.
        let avgSchemeModifier = players.reduce(0.0) { sum, player in
            let modifier = schemeName(for: player).map {
                VersatilityDevelopmentEngine.schemePerformanceModifier(player: player, scheme: $0)
            } ?? 1.0
            return sum + modifier
        } / Double(players.count)

        // Raw average "% learned" for the DIRECT term below.
        let avgFamiliarity = players.reduce(0.0) { sum, player in
            let fam = schemeName(for: player)
                .map { Double(player.schemeFam(for: $0)) } ?? familiarityNeutralPivot
            return sum + fam
        } / Double(players.count)

        // R41 — DIRECT familiarity effect, INDEPENDENT of scheme fit. A squad
        // still learning the playbook (low % learned) plays a beat slow / a
        // step off and loses a little yardage regardless of how well it fits
        // the scheme on paper; a well-drilled squad (high %) gets a small edge.
        // This is what makes "% LEARNED" matter at a neutral 0.5 fit, where the
        // multiplier term above collapses to zero.
        var directFamiliarity = 0.0
        #if DEBUG
        if !debugNeutralSchemeFamiliarity {
            directFamiliarity = clamp(
                (avgFamiliarity - familiarityNeutralPivot) * familiarityDirectGain,
                min: -familiarityDirectCap, max: familiarityDirectCap
            )
        }
        #else
        directFamiliarity = clamp(
            (avgFamiliarity - familiarityNeutralPivot) * familiarityDirectGain,
            min: -familiarityDirectCap, max: familiarityDirectCap
        )
        #endif

        // Map 0.0-1.0 fit to a -0.05 to +0.10 modifier, scale by scheme
        // familiarity, then add the fit-independent familiarity term.
        // 0.5 fit = 0.0 (multiplier part neutral), 1.0 fit = +0.10, 0.0 = -0.05.
        return (avgFit - 0.5) * 0.2 * avgSchemeModifier + directFamiliarity
    }

    // R41 direct-familiarity tuning. Pivot 70 matches the league-seeded scheme
    // familiarity mean (starters seed 55-85), so an average squad is neutral;
    // below → a small yardage penalty, above → a small bonus. Gain/cap keep the
    // total swing tangible (~±2.4% at the extremes) but inside the balance gates.
    private static let familiarityNeutralPivot = 70.0
    private static let familiarityDirectGain = 0.0010  // compressed from 0.0016 (round-5 P1) — this yards channel compounds into the fam win-gap
    private static let familiarityDirectCap = 0.024    // compressed from 0.04 (round-5 P1)

    // MARK: - SCHEME-FAMILIARITY LAYER (Balance R3, Part B)
    //
    // A completion-side shift (B1) + a real blown-assignment bust (B2) that make
    // 100%-vs-33% scheme familiarity VISIBLE on the box score (more/fewer catches,
    // visible negative plays), where the shipped R41 channel was yards-only and
    // invisible in the 55-85 seed band. Both channels pivot at the seeded-league
    // mean (famCurve at 70, the bust at 55 < mean), so a neutral squad is
    // parity-safe by construction — famShift is 0 and the guarded bust never rolls
    // (no RNG draw). Threads the SHARED PlaySimulator path, so it shows on both the
    // coached (LiveGameEngine) and simmed (Game/DriveSimulator) games. The legacy
    // `schemeYardAdjustment` / `directFamiliarity` yard channel (B3) is left intact.

    // B1 — completion shift. `famCurve` is 0 at the pivot (70) → parity; a
    // well-drilled squad earns a small execution bonus, a raw one is docked
    // harder (asymmetric down-slope), each side grand-bounded.
    private static let famUpSlope   = 0.0007   // fam100 → +0.021 comp (UP side kept — fam100 must stay clearly better)
    private static let famDownSlope = 0.00045  // fam66 → -0.0018, fam33 → -0.0167 (pre-cap) — compressed from 0.0025; the DOWN side was the over-punishing cliff (round-5 P1)
    private static let famUpCap     = 0.021
    private static let famDownCap   = -0.02    // compressed from -0.11 so a low-fam squad is docked, not gutted (round-5 P1)
    // Optional coach blend (design B1): effectiveSquadFam = player*0.7 + coach*0.3.
    // `coachExpertise` nil = player-only (the shipping default; the coordinator's
    // own completion channel stays the separate mech-6 lane, no double-count).
    private static let famCoachPlayerWeight = 0.7
    private static let famCoachExpertWeight = 0.3

    // B2 — blown-assignment bust. Pivot 55 < the seeded mean 70 → a neutral squad
    // NEVER busts (parity); a raw squad coughs up the occasional forced negative
    // play. Weighted to the ball-carrier's OWN familiarity (the guy running the
    // route / carrying the ball busts it — fixes team-mean dilution).
    private static let famBustPivot       = 55.0
    private static let famBustSlope       = 0.0013  // fam33 → ~2.9%, fam20 → ~4.6% — compressed from 0.0027 (round-5 P1)
    private static let famBustCap         = 0.05     // symmetric hard cap on BOTH bust sides, halved from 0.10 (round-5 P1)
    private static let famBustOwnWeight   = 0.6
    private static let famBustSquadWeight = 0.4
    // Yardage bound on the DEFENSE coverage-bust catch — the symmetric analog of
    // the OFFENSE bust's fixed 0-yard incompletion. A blown coverage is an easy
    // chunk (a first-down-ish pitch-and-catch), never an uncapped deep bomb; this
    // is the "cap the defensive bust term" fix (round-5 P1). Deep busts were the
    // ~500-pass-yd leak; short/mid busts already land under it (no-op there).
    private static let famDefBustYardCap  = 18

    /// B1: familiarity → completion shift. 0 at the neutral pivot (70) → parity;
    /// asymmetric (a raw squad is docked harder than a drilled one is rewarded),
    /// each side grand-bounded.
    private static func famCurve(_ f: Double) -> Double {
        let d = f - familiarityNeutralPivot
        return d >= 0 ? Swift.min(d * famUpSlope, famUpCap)
                      : Swift.max(d * famDownSlope, famDownCap)
    }

    /// The squad's average scheme familiarity against its called scheme, blended
    /// toward the coordinator's expertise. A nil scheme (quick sim / neutral
    /// harness) collapses to the pivot → famCurve 0 (parity). A nil coach
    /// expertise (the shipping player-only path) uses player familiarity alone.
    private static func effectiveSquadFam(_ players: [SimPlayer], scheme: String?,
                                          coachExpertise: Double? = nil) -> Double {
        guard let scheme = scheme, !players.isEmpty else { return familiarityNeutralPivot }
        let playerAvg = players.map { Double($0.schemeFam(for: scheme)) }
            .reduce(0, +) / Double(players.count)
        guard let coach = coachExpertise else { return playerAvg }
        return playerAvg * famCoachPlayerWeight + coach * famCoachExpertWeight
    }

    /// B2: an effective familiarity → bust probability. 0 at fam ≥ pivot (55) → a
    /// neutral squad never busts (parity).
    private static func bustChance(forEffectiveFam eff: Double) -> Double {
        clamp((famBustPivot - eff) * famBustSlope, min: 0, max: famBustCap)
    }

    /// B2 (offense / carrier side): the blown-assignment bust for a specific
    /// ball-carrier, weighted to his OWN scheme familiarity with squad dilution.
    /// A nil scheme → 0 (parity, no RNG draw at the guarded call site).
    private static func familiarityBustChance(carrier: SimPlayer, squad: [SimPlayer],
                                              scheme: String?) -> Double {
        guard let scheme = scheme else { return 0 }
        let own = Double(carrier.schemeFam(for: scheme))
        let squadAvg = squad.isEmpty ? own
            : squad.map { Double($0.schemeFam(for: scheme)) }.reduce(0, +) / Double(squad.count)
        let eff = own * famBustOwnWeight + squadAvg * famBustSquadWeight
        return bustChance(forEffectiveFam: eff)
    }

    /// B2 (defense side): a blown-coverage bust from the defense's squad-wide
    /// scheme familiarity — a raw coverage unit occasionally hands over a clean
    /// catch. A nil scheme → 0 (parity).
    private static func squadBustChance(_ players: [SimPlayer], scheme: String?) -> Double {
        guard let scheme = scheme, !players.isEmpty else { return 0 }
        let avg = players.map { Double($0.schemeFam(for: scheme)) }
            .reduce(0, +) / Double(players.count)
        return bustChance(forEffectiveFam: avg)
    }

    // MARK: - Utility Functions

    private static func averageAttribute(_ players: [SimPlayer], extractor: (SimPlayer) -> Double) -> Double {
        guard !players.isEmpty else { return 50.0 }
        return players.map(extractor).reduce(0, +) / Double(players.count)
    }

    private static func coinFlip(_ probability: Double) -> Bool {
        Double.random(in: 0...1) < probability
    }

    private static func randomChance(_ probability: Double) -> Bool {
        Double.random(in: 0...1) < probability
    }

    private static func clamp(_ value: Double, min minVal: Double, max maxVal: Double) -> Double {
        Swift.min(maxVal, Swift.max(minVal, value))
    }
}
