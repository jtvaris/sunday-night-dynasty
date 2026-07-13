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
        offenseIsAway: Bool = false
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
                weather: weather
            )
        }

        let hint = offensiveCall?.simulatorHint

        // --- Penalty check (scrimmage plays only, ~6% of snaps) ---
        // Rolled BEFORE the play resolves: a flag wipes the down out entirely.
        // Special teams (punt/FG) and clock plays are exempt to keep their
        // flows simple.
        if playCall == .pass || playCall == .run,
           randomChance(penaltyChance) {
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
                adjustments: adjustments
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
                defensivePackage: defensivePackage,
                weather: weather,
                adjustments: adjustments
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
                defensivePackage: defensivePackage,
                weather: weather,
                adjustments: adjustments
            )
        }
    }

    /// Maps an explicit offensive play call to the simulator's ``PlayType``.
    ///
    /// `.screen` is intentionally routed as a PASS: its hint carries
    /// `passDepth: .short` plus a high YAC multiplier, which models the
    /// screen game far better than the run path would.
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
    static func decidePlayCall(
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        offensiveScheme: OffensiveScheme? = nil,
        gamePlan: GamePlan? = nil,
        weather: GameWeather? = nil
    ) -> PlayType {
        let yardsToEndzone = 100 - yardLine
        let isTwoMinuteDrill = quarter == 4 && timeRemaining <= 120
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
        // pass probability by up to ±0.15 (runPassRatio 0 → -0.15, 1 → +0.15).
        // A balanced plan (0.5) contributes exactly 0, preserving old behavior.
        let planPassBias = ((gamePlan?.runPassRatio ?? 0.5) - 0.5) * 0.3

        // Weather run bias: in snow both AI coordinators lean on the ground
        // game — the pass probability drops by 0.08 across every situation.
        let weatherPassBias: Double = weather == .snow ? -0.08 : 0.0
        let schemePassBias = schemeOnlyPassBias + planPassBias + weatherPassBias

        // 4th down decisions
        if down == 4 {
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

        // Normal play calling by down and distance, with scheme bias applied
        switch down {
        case 1:
            return coinFlip(clamp(0.55 + schemePassBias, min: 0.25, max: 0.80)) ? .pass : .run
        case 2:
            if distance >= 7 {
                return coinFlip(clamp(0.65 + schemePassBias, min: 0.35, max: 0.85)) ? .pass : .run
            } else {
                return coinFlip(clamp(0.50 + schemePassBias, min: 0.25, max: 0.75)) ? .pass : .run
            }
        case 3:
            if distance <= 3 {
                return coinFlip(clamp(0.50 + schemePassBias, min: 0.25, max: 0.75)) ? .pass : .run
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
        adjustments: Adjustments? = nil
    ) -> PlayResult {
        let qb = findQB(in: offensePlayers)
        let qbAttrs = qbAttributes(for: qb)
        let momentumBoost = momentum * 0.05

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
            let biteChance = clamp(0.5 + (70.0 - boxAwareness) * paBiteAwarenessSlope,
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
        // Add LB blitz pressure
        let lbBlitz = averageAttribute(
            defensePlayers.filter { isLB($0) },
            extractor: { lbBlitzRating(for: $0) }
        ) * 0.3

        let protectionRating = (olPassBlock + momentumBoost * 100) - (dlPassRush + lbBlitz)
        var sackChance = max(0.05, min(0.35, 0.20 - protectionRating / 500.0))

        // Mech 2: a mobile, poised QB slides pressure and escapes the pocket —
        // scrambling + pocket presence buy him out of the sack. A statue QB
        // (below the 50/50 pivot) earns nothing. Shared, so quick sim and the
        // live engine get it identically.
        sackChance = max(0.02, sackChance - qbMobilitySackReduction(qbAttrs))

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
        let targetYards = passYardsForDistance(passDistance)

        // --- Accuracy & Openness Check ---
        // Mech 3: arm strength lifts the deep-ball accuracy (±cap points).
        var accuracyRating = qbAccuracyForDistance(qbAttrs, distance: passDistance)
        if passDistance == .deep {
            accuracyRating += armDeepAccuracyBonus(qbAttrs)
        }
        // #36B mech 3 (mental game): a low-composure QB's accuracy sags in the
        // big moment (Q4/OT or red zone). One lever — accuracyRating feeds both
        // the completion odds and the interception roll, so a rattled passer
        // both misses more AND forces a few more picks. High composure is
        // untouched here (the Q4 clutch boost in applyMoraleModifiers is the
        // up-side). Shared path → quick sim and the live engine get it alike.
        accuracyRating -= composurePenalty(for: qb, quarter: quarter, yardLine: yardLine)
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
        let opennessAttr = useSeparationOpenness
            ? receiverSeparationRating(for: target)
            : receiverCatchRating(for: target)
        let dbCoverage = averageAttribute(
            defensePlayers.filter { isDB($0) },
            extractor: { dbCoverageRating(for: $0) }
        )

        let completionBase = (accuracyRating * 0.4
                              + opennessAttr * 0.35
                              + Double(qb.mental.decisionMaking) * 0.1) / 100.0
        let coveragePenalty = Double(dbCoverage) / 200.0
        var completionChance = clamp(completionBase - coveragePenalty + momentumBoost, min: 0.15, max: 0.85)

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

        // Mech 4: WR release vs DB press on man-press SHORT throws (live games
        // only — quick sim passes no package, so it never fires there). A WR
        // who beats the jam gets a cleaner window; a good press corner erases
        // it. Near-zero mean (release ≈ press league-wide) so it never shifts
        // the completion rate — it only rewards the individual matchup.
        var wrPressActive = true
        #if DEBUG
        if debugNeutralWRPress { wrPressActive = false }
        #endif
        if wrPressActive, let package = defensivePackage,
           package.coverage == .manToMan, passDistance == .short {
            let press = averageAttribute(
                defensePlayers.filter { isDB($0) },
                extractor: { dbPressRating(for: $0) }
            )
            let release = receiverReleaseRating(for: target)
            let mod = clamp((release - press) / wrPressDivisor, min: -wrPressCap, max: wrPressCap)
            completionChance = clamp(completionChance + mod, min: 0.05, max: 0.95)
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

        // Halftime adjustment: schemed separation lifts the completion odds.
        if let adjustments, adjustments.completionBonus != 0 {
            completionChance = clamp(completionChance + adjustments.completionBonus, min: 0.05, max: 0.95)
        }

        // --- Interception Check ---
        let intChance = interceptionChance(
            accuracyRating: accuracyRating,
            dbBallSkills: averageAttribute(
                defensePlayers.filter { isDB($0) },
                extractor: { dbBallSkillsRating(for: $0) }
            ),
            passDistance: passDistance
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
        func makeCatch(contested: Bool) -> PlayResult {
            var yacBonus = contested ? 0 : yardsAfterCatch(for: target, momentum: momentum)
            // Play-call YAC shading (screens, flats, go routes) — clean catches only.
            if !contested, let hint = hint {
                yacBonus = max(0, Int((Double(yacBonus) * hint.yacMultiplier).rounded()))
            }
            var totalYards = targetYards + yacBonus

            // Apply scheme fit modifiers: offense fit boosts yards, defense fit reduces them
            let schemeYardAdjustment = Double(totalYards) * (offSchemeFit - defSchemeFit)
            totalYards += Int(schemeYardAdjustment.rounded())

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
            if randomChance(dropChance(for: target)) {
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
            if randomChance(contestedCatchChance(target: target, dbBallSkills: dbBallSkills)) {
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
                    text = pressureDescription(qb: qb, target: target, rusher: rusher)
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
                keyDefensePlayerID: breakupID
            )
            play.defenseBitOnFake = paBite
            play.passVelocityScale = velocityScale
            if wasBreakup {
                play.passBreakup = true
                play.defensiveHighlight = true
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
        defensivePackage: DefensivePackage? = nil,
        weather: GameWeather? = nil,
        adjustments: Adjustments? = nil
    ) -> PlayResult {
        let rb = findRB(in: offensePlayers)
        let rbAttrs = rbAttributes(for: rb)
        let momentumBoost = momentum * 0.05

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
        let olRunBlock = averageAttribute(
            offensePlayers.filter { isOL($0) },
            extractor: { olRunBlockRating(for: $0) }
        )
        let dlBlockShed = averageAttribute(
            defensePlayers.filter { isDL($0) },
            extractor: { dlBlockSheddingRating(for: $0) }
        )
        let lbTackling = averageAttribute(
            defensePlayers.filter { isLB($0) },
            extractor: { lbTacklingRating(for: $0) }
        )

        var blockingAdvantage = (olRunBlock - (dlBlockShed * 0.6 + lbTackling * 0.4)) / 100.0

        // Play-call gap bonus (interior power runs, QB sneak) shades blocking.
        if let hint = hint {
            blockingAdvantage += hint.runGapBonus
        }

        // --- Base Yards ---
        let baseYards = Double.random(in: 2.0...5.0)
        let visionBonus = Double(rbAttrs.vision) / 100.0 * 2.0
        let elusivenessBonus = Double(rbAttrs.elusiveness) / 100.0 * 1.5
        // Halftime adjustment: a run-first commitment adds expected yardage.
        let adjustmentYards = adjustments?.runYardageBonus ?? 0
        var totalYards = Int((baseYards + visionBonus + elusivenessBonus + blockingAdvantage * 3.0 + momentumBoost * 2.0 + adjustmentYards).rounded())

        // Apply scheme fit modifiers: offense fit boosts yards, defense fit reduces them
        let schemeYardAdjustment = Double(totalYards) * (offSchemeFit - defSchemeFit)
        totalYards += Int(schemeYardAdjustment.rounded())

        // Defensive package: run-stopping fronts subtract expected yardage.
        if let package = defensivePackage {
            totalYards -= Int((package.totalRunStopModifier * 6.0).rounded())
        }

        // --- Breakaway Run Check ---
        // R37: the carrier's VISION finds the crease. Vision + awareness
        // scale the breakaway odds around the 70-rated league mean, so the
        // league-wide rushing average holds while individual backs separate.
        // Mech 1: fatigue drags effective speed on the breakaway foot race.
        let rbSpeed = effectiveSpeed(rb)
        let avgDBSpeed = averageAttribute(
            defensePlayers.filter { isDB($0) },
            extractor: { effectiveSpeed($0) }
        )
        var visionActive = true
        #if DEBUG
        if debugNeutralCarrierVision { visionActive = false }
        #endif
        let carrierSight = Double(rbAttrs.vision) * 0.6 + Double(rb.mental.awareness) * 0.4
        var breakawayChance = max(0.0, (rbSpeed - avgDBSpeed) / 200.0 + 0.03)
        if visionActive {
            breakawayChance *= clamp(1.0 + (carrierSight - 70.0) * carrierVisionSlope,
                                     min: 0.6, max: 1.4)
        }
        // Snow: nobody outruns the pursuit on a buried track.
        if weather == .snow { breakawayChance *= 0.5 }
        if randomChance(breakawayChance) {
            totalYards += Int.random(in: 15...45)
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
            fumbleChance = clamp(0.005 - (security - 70.0) * ballSecuritySlope,
                                 min: 0.002, max: 0.008)
        } else {
            fumbleChance = max(0.005, 0.01 - Double(rbAttrs.breakTackle) / 10000.0)
        }
        // Rain/snow: the wet ball comes out more often.
        if weather == .rain || weather == .snow { fumbleChance += 0.005 }
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
            let rb = findRB(in: offensePlayers)
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

        if distance <= 5 {
            // Short yardage: favor short/mid
            let roll = Double.random(in: 0...1)
            if roll < 0.55 { return .short }
            if roll < 0.85 { return .mid }
            return .deep
        } else if distance <= 10 {
            let roll = Double.random(in: 0...1)
            if roll < 0.35 { return .short }
            if roll < 0.75 { return .mid }
            return .deep
        } else {
            // Long distance: favor mid/deep
            let roll = Double.random(in: 0...1)
            if roll < 0.15 { return .short }
            if roll < 0.55 { return .mid }
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
            return Int.random(in: 21...45)
        }
    }

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
        passDistance: PassDistance
    ) -> Double {
        let baseRate: Double
        switch passDistance {
        case .short: baseRate = 0.015
        case .mid:   baseRate = 0.025
        case .deep:  baseRate = 0.04
        }
        let accuracyMod = (70.0 - accuracyRating) / 1000.0
        let dbMod = (dbBallSkills - 50.0) / 500.0
        return clamp(baseRate + accuracyMod + dbMod, min: 0.005, max: 0.08)
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

    // MARK: - Mental-Game Tuning (#36B)

    /// Composure (mental mech 3): in a big moment a player whose composure
    /// (`SimPlayer.composureRating`) is below `composureThreshold` loses up to
    /// `composureCap` effective accuracy points, `composureSlope` per point of
    /// deficit. Small and downside-only — the poised are left to the existing
    /// Q4 clutch boost. Measured by the quick-sim gate (shared path).
    private static let composureThreshold = 60.0
    private static let composureSlope = 0.15
    private static let composureCap = 3.0

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

    /// Effective-accuracy sag from low composure in a pressure moment
    /// (mental mech 3). Zero unless it is a big moment — Q4/OT, or a red-zone
    /// snap in any quarter — and the passer's composure is below the
    /// threshold. Neutralized by the balance harness.
    static func composurePenalty(for player: SimPlayer, quarter: Int, yardLine: Int) -> Double {
        #if DEBUG
        if debugNeutralComposure { return 0 }
        #endif
        let bigMoment = quarter >= 4 || (100 - yardLine) <= 20
        guard bigMoment else { return 0 }
        let composure = player.composureRating
        guard composure < composureThreshold else { return 0 }
        return Swift.min(composureCap, (composureThreshold - composure) * composureSlope)
    }

    /// Drop probability on an open, catchable ball (mech 5).
    private static func dropChance(for target: SimPlayer) -> Double {
        let hands = receiverHandsRating(for: target)
        return clamp(dropBase - (hands - 70.0) * dropHandsSlope, min: dropMin, max: dropMax)
    }

    /// Contested-catch probability in tight coverage (mech 5).
    private static func contestedCatchChance(target: SimPlayer, dbBallSkills: Double) -> Double {
        let edge = receiverContestedRating(for: target) - dbBallSkills
        return clamp(contestedBase + edge / contestedDivisor, min: contestedMin, max: contestedMax)
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
    private static func pressureDescription(qb: SimPlayer, target: SimPlayer,
                                            rusher: SimPlayer) -> String {
        let pool = [
            "Under pressure from \(rusher.fullName), \(qb.fullName) throws it away.",
            "\(rusher.fullName) is in his face — \(qb.fullName)'s hurried throw falls incomplete.",
            "Flushed by \(rusher.fullName), \(qb.fullName) fires wide of \(target.fullName).",
        ]
        return pool.randomElement() ?? pool[0]
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

        // Apply scheme familiarity modifier: players who haven't learned the scheme perform worse
        let avgSchemeModifier = players.reduce(0.0) { sum, player in
            let schemeName: String?
            if player.position.side == .offense {
                schemeName = offensiveScheme?.rawValue
            } else {
                schemeName = defensiveScheme?.rawValue
            }
            let modifier = schemeName.map {
                VersatilityDevelopmentEngine.schemePerformanceModifier(player: player, scheme: $0)
            } ?? 1.0
            return sum + modifier
        } / Double(players.count)

        // Map 0.0-1.0 fit to a -0.05 to +0.10 modifier, then scale by scheme familiarity
        // 0.5 fit = 0.0 modifier (neutral), 1.0 fit = +0.10, 0.0 fit = -0.05
        return (avgFit - 0.5) * 0.2 * avgSchemeModifier
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
