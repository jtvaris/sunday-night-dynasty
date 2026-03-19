import Foundation

// MARK: - Play Simulator

/// Simulates individual NFL plays using player attributes, game situation, and randomness.
enum PlaySimulator {

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
    static func simulatePlay(
        offensePlayers: [Player],
        defensePlayers: [Player],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        momentum: Double,
        playNumber: Int,
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil
    ) -> PlayResult {
        let playCall = decidePlayCall(
            down: down,
            distance: distance,
            yardLine: yardLine,
            quarter: quarter,
            timeRemaining: timeRemaining,
            offensiveScheme: offensiveScheme
        )

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
                defensiveScheme: defensiveScheme
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
                defensiveScheme: defensiveScheme
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
                playNumber: playNumber
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
                defensiveScheme: defensiveScheme
            )
        }
    }

    // MARK: - Play Call Decision

    /// Determines the type of play to call based on game situation.
    static func decidePlayCall(
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        offensiveScheme: OffensiveScheme? = nil
    ) -> PlayType {
        let yardsToEndzone = 100 - yardLine
        let isTwoMinuteDrill = quarter == 4 && timeRemaining <= 120
        let fieldGoalRange = yardsToEndzone <= 45

        // Scheme pass bias: shifts pass probability up (pass-heavy) or down (run-heavy)
        let schemePassBias: Double = {
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

        // 4th down decisions
        if down == 4 {
            // Go for it on 4th & short near the goal line
            if distance <= 2 && yardsToEndzone <= 5 {
                return coinFlip(0.5 + schemePassBias) ? .pass : .run
            }
            // Go for it in desperation (late game, trailing assumed from two-minute drill)
            if isTwoMinuteDrill && yardsToEndzone > 45 {
                return coinFlip(0.7 + schemePassBias * 0.5) ? .pass : .run
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
        offensePlayers: [Player],
        defensePlayers: [Player],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        momentum: Double,
        playNumber: Int,
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil
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
        let sackChance = max(0.05, min(0.35, 0.20 - protectionRating / 500.0))

        if randomChance(sackChance) {
            let sackYards = -Int.random(in: 3...8)
            let newYardLine = max(0, yardLine + sackYards)

            // Check for safety
            if newYardLine <= 0 {
                return PlayResult(
                    playNumber: playNumber,
                    quarter: quarter,
                    timeRemaining: timeRemaining,
                    down: down,
                    distance: distance,
                    yardLine: yardLine,
                    playType: .pass,
                    outcome: .safety,
                    yardsGained: sackYards,
                    description: "\(qb.fullName) is sacked in the end zone for a safety!",
                    isFirstDown: false,
                    isTurnover: false,
                    scoringPlay: true,
                    pointsScored: 2
                )
            }

            return PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .pass,
                outcome: .sack,
                yardsGained: sackYards,
                description: "\(qb.fullName) is sacked for a loss of \(abs(sackYards)) yards.",
                isFirstDown: false,
                isTurnover: false,
                scoringPlay: false,
                pointsScored: 0
            )
        }

        // --- Choose Target ---
        let receivers = eligibleReceivers(from: offensePlayers)
        guard let target = weightedReceiverSelection(receivers) else {
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
        let passDistance = choosePassDistance(distance: distance, yardLine: yardLine)
        let targetYards = passYardsForDistance(passDistance)

        // --- Accuracy & Completion Check ---
        let accuracyRating = qbAccuracyForDistance(qbAttrs, distance: passDistance)
        let receiverCatching = receiverCatchRating(for: target)
        let dbCoverage = averageAttribute(
            defensePlayers.filter { isDB($0) },
            extractor: { dbCoverageRating(for: $0) }
        )

        let completionBase = (Double(accuracyRating) * 0.4
                              + Double(receiverCatching) * 0.35
                              + Double(qb.mental.decisionMaking) * 0.1) / 100.0
        let coveragePenalty = Double(dbCoverage) / 200.0
        let completionChance = clamp(completionBase - coveragePenalty + momentumBoost, min: 0.15, max: 0.85)

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
            let defender = defensePlayers.filter { isDB($0) }.randomElement()
                ?? defensePlayers.first!
            return PlayResult(
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
                pointsScored: 0
            )
        }

        // --- Completion or Incompletion ---
        if randomChance(completionChance) {
            // Completed pass
            let yacBonus = yardsAfterCatch(for: target, momentum: momentum)
            var totalYards = targetYards + yacBonus

            // Apply scheme fit modifiers: offense fit boosts yards, defense fit reduces them
            let schemeYardAdjustment = Double(totalYards) * (offSchemeFit - defSchemeFit)
            totalYards += Int(schemeYardAdjustment.rounded())

            // Cap yards at endzone
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
                    playType: .pass,
                    outcome: .touchdown,
                    yardsGained: totalYards,
                    description: "\(qb.fullName) throws \(targetYards) yards to \(target.fullName) for a TOUCHDOWN!",
                    isFirstDown: true,
                    isTurnover: false,
                    scoringPlay: true,
                    pointsScored: 6
                )
            }

            // Prevent negative total from variance
            totalYards = max(totalYards, 0)
            let gainedFirstDown = totalYards >= distance

            return PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .pass,
                outcome: .completion,
                yardsGained: totalYards,
                description: completionDescription(
                    qb: qb, target: target, yards: totalYards, firstDown: gainedFirstDown
                ),
                isFirstDown: gainedFirstDown,
                isTurnover: false,
                scoringPlay: false,
                pointsScored: 0
            )
        } else {
            // Incomplete pass
            return PlayResult(
                playNumber: playNumber,
                quarter: quarter,
                timeRemaining: timeRemaining,
                down: down,
                distance: distance,
                yardLine: yardLine,
                playType: .pass,
                outcome: .incompletion,
                yardsGained: 0,
                description: "\(qb.fullName) throws incomplete intended for \(target.fullName).",
                isFirstDown: false,
                isTurnover: false,
                scoringPlay: false,
                pointsScored: 0
            )
        }
    }

    // MARK: - Run Play

    private static func simulateRunPlay(
        offensePlayers: [Player],
        defensePlayers: [Player],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        momentum: Double,
        playNumber: Int,
        offensiveScheme: OffensiveScheme? = nil,
        defensiveScheme: DefensiveScheme? = nil
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

        let blockingAdvantage = (olRunBlock - (dlBlockShed * 0.6 + lbTackling * 0.4)) / 100.0

        // --- Base Yards ---
        let baseYards = Double.random(in: 2.0...5.0)
        let visionBonus = Double(rbAttrs.vision) / 100.0 * 2.0
        let elusivenessBonus = Double(rbAttrs.elusiveness) / 100.0 * 1.5
        var totalYards = Int((baseYards + visionBonus + elusivenessBonus + blockingAdvantage * 3.0 + momentumBoost * 2.0).rounded())

        // Apply scheme fit modifiers: offense fit boosts yards, defense fit reduces them
        let schemeYardAdjustment = Double(totalYards) * (offSchemeFit - defSchemeFit)
        totalYards += Int(schemeYardAdjustment.rounded())

        // --- Breakaway Run Check ---
        let rbSpeed = Double(rb.physical.speed)
        let avgDBSpeed = averageAttribute(
            defensePlayers.filter { isDB($0) },
            extractor: { Double($0.physical.speed) }
        )
        let breakawayChance = max(0.0, (rbSpeed - avgDBSpeed) / 200.0 + 0.03)
        if randomChance(breakawayChance) {
            totalYards += Int.random(in: 15...45)
        }

        // --- Fumble Check ---
        // ~1% base, slightly lower with high break-tackle (implies ball security awareness)
        let fumbleChance = max(0.005, 0.01 - Double(rbAttrs.breakTackle) / 10000.0)
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
                pointsScored: 0
            )
        }

        // --- Negative Run / Tackle for Loss ---
        let tflChance = max(0.0, 0.08 - blockingAdvantage * 0.1)
        if totalYards <= 1 && randomChance(tflChance) {
            totalYards = -Int.random(in: 1...3)
        }

        // --- Safety Check ---
        let newYardLine = yardLine + totalYards
        if newYardLine <= 0 {
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
                description: "\(rb.fullName) is tackled in the end zone for a safety!",
                isFirstDown: false,
                isTurnover: false,
                scoringPlay: true,
                pointsScored: 2
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
                pointsScored: 6
            )
        }

        totalYards = max(totalYards, -(yardLine)) // Don't go past own endzone without safety
        let gainedFirstDown = totalYards >= distance

        return PlayResult(
            playNumber: playNumber,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .run,
            outcome: .rush,
            yardsGained: totalYards,
            description: rushDescription(rb: rb, yards: totalYards, firstDown: gainedFirstDown),
            isFirstDown: gainedFirstDown,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0
        )
    }

    // MARK: - Special Teams

    private static func simulatePunt(
        offensePlayers: [Player],
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

    private static func simulateFieldGoal(
        offensePlayers: [Player],
        down: Int,
        distance: Int,
        yardLine: Int,
        quarter: Int,
        timeRemaining: Int,
        playNumber: Int
    ) -> PlayResult {
        let kicker = offensePlayers.first(where: { $0.position == .K }) ?? offensePlayers.first!
        let fgDistance = 100 - yardLine + 17 // Snap + hold distance
        let kickerAccuracy = kickerAccuracyRating(for: kicker)

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
        let makeChance = clamp(baseMakeChance + accuracyModifier, min: 0.10, max: 0.98)

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
        offensePlayers: [Player],
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
        qb: Player,
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
        let speedBonus = Double(qb.physical.speed) / 100.0 * 2.0
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
                pointsScored: 6
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
            pointsScored: 0
        )
    }

    // MARK: - Extra Point & Two-Point Conversion

    /// Simulates an extra point attempt.
    static func simulateExtraPoint(
        offensePlayers: [Player],
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

    /// Simulates a two-point conversion attempt.
    static func simulateTwoPointConversion(
        offensePlayers: [Player],
        defensePlayers: [Player],
        quarter: Int,
        timeRemaining: Int,
        playNumber: Int
    ) -> PlayResult {
        // Treat as a single play from the 2-yard line
        let isPass = coinFlip(0.6)
        let qb = findQB(in: offensePlayers)

        // Simplified conversion check: ~48% success rate league average
        let offenseRating = averageAttribute(offensePlayers, extractor: { Double($0.overall) })
        let defenseRating = averageAttribute(defensePlayers, extractor: { Double($0.overall) })
        let advantage = (offenseRating - defenseRating) / 100.0
        let conversionChance = clamp(0.48 + advantage, min: 0.25, max: 0.70)
        let isGood = randomChance(conversionChance)

        let description: String
        if isPass {
            let target = eligibleReceivers(from: offensePlayers).randomElement()
            let targetName = target?.fullName ?? "a receiver"
            description = isGood
                ? "\(qb.fullName) throws to \(targetName) for the two-point conversion!"
                : "\(qb.fullName) throws to \(targetName), but the two-point conversion fails."
        } else {
            let rb = findRB(in: offensePlayers)
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
            pointsScored: isGood ? 2 : 0
        )
    }

    // MARK: - Player Finders

    private static func findQB(in players: [Player]) -> Player {
        players.first(where: { $0.position == .QB }) ?? players.first!
    }

    private static func findRB(in players: [Player]) -> Player {
        players.first(where: { $0.position == .RB })
            ?? players.first(where: { $0.position == .FB })
            ?? players.first!
    }

    private static func eligibleReceivers(from players: [Player]) -> [Player] {
        players.filter { [.WR, .TE, .RB].contains($0.position) }
    }

    // MARK: - Position Group Checks

    private static func isOL(_ player: Player) -> Bool {
        [Position.LT, .LG, .C, .RG, .RT].contains(player.position)
    }

    private static func isDL(_ player: Player) -> Bool {
        [Position.DE, .DT].contains(player.position)
    }

    private static func isLB(_ player: Player) -> Bool {
        [Position.OLB, .MLB].contains(player.position)
    }

    private static func isDB(_ player: Player) -> Bool {
        [Position.CB, .FS, .SS].contains(player.position)
    }

    // MARK: - Attribute Extractors

    private static func qbAttributes(for player: Player) -> QBAttributes {
        if case .quarterback(let attrs) = player.positionAttributes { return attrs }
        return QBAttributes(
            armStrength: 50, accuracyShort: 50, accuracyMid: 50,
            accuracyDeep: 50, pocketPresence: 50, scrambling: 50
        )
    }

    private static func rbAttributes(for player: Player) -> RBAttributes {
        if case .runningBack(let attrs) = player.positionAttributes { return attrs }
        return RBAttributes(vision: 50, elusiveness: 50, breakTackle: 50, receiving: 50)
    }

    private static func olPassBlockRating(for player: Player) -> Double {
        if case .offensiveLine(let attrs) = player.positionAttributes {
            return Double(attrs.passBlock)
        }
        return 50.0
    }

    private static func olRunBlockRating(for player: Player) -> Double {
        if case .offensiveLine(let attrs) = player.positionAttributes {
            return Double(attrs.runBlock)
        }
        return 50.0
    }

    private static func dlPassRushRating(for player: Player) -> Double {
        if case .defensiveLine(let attrs) = player.positionAttributes {
            return Double((attrs.passRush + attrs.powerMoves + attrs.finesseMoves) / 3)
        }
        return 50.0
    }

    private static func dlBlockSheddingRating(for player: Player) -> Double {
        if case .defensiveLine(let attrs) = player.positionAttributes {
            return Double(attrs.blockShedding)
        }
        return 50.0
    }

    private static func lbTacklingRating(for player: Player) -> Double {
        if case .linebacker(let attrs) = player.positionAttributes {
            return Double(attrs.tackling)
        }
        return 50.0
    }

    private static func lbBlitzRating(for player: Player) -> Double {
        if case .linebacker(let attrs) = player.positionAttributes {
            return Double(attrs.blitzing)
        }
        return 50.0
    }

    private static func dbCoverageRating(for player: Player) -> Double {
        if case .defensiveBack(let attrs) = player.positionAttributes {
            return Double((attrs.manCoverage + attrs.zoneCoverage) / 2)
        }
        return 50.0
    }

    private static func dbBallSkillsRating(for player: Player) -> Double {
        if case .defensiveBack(let attrs) = player.positionAttributes {
            return Double(attrs.ballSkills)
        }
        return 50.0
    }

    private static func receiverCatchRating(for player: Player) -> Double {
        switch player.positionAttributes {
        case .wideReceiver(let attrs):
            return Double((attrs.catching + attrs.routeRunning) / 2)
        case .tightEnd(let attrs):
            return Double((attrs.catching + attrs.routeRunning) / 2)
        case .runningBack(let attrs):
            return Double(attrs.receiving)
        default:
            return 40.0
        }
    }

    private static func receiverRouteWeight(for player: Player) -> Double {
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

    private static func kickerAccuracyRating(for player: Player) -> Int {
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

    private static func yardsAfterCatch(for player: Player, momentum: Double) -> Int {
        let speedFactor = Double(player.physical.speed) / 100.0
        let agilityFactor = Double(player.physical.agility) / 100.0
        let yacBase = (speedFactor + agilityFactor) * 3.0 + momentum * 1.0
        return max(0, Int(Double.random(in: -1.0...yacBase).rounded()))
    }

    /// Selects a receiver weighted by route running + catching ability.
    private static func weightedReceiverSelection(_ receivers: [Player]) -> Player? {
        guard !receivers.isEmpty else { return nil }
        let weights = receivers.map { receiverRouteWeight(for: $0) }
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

    private static func completionDescription(qb: Player, target: Player, yards: Int, firstDown: Bool) -> String {
        let firstDownText = firstDown ? " for a first down" : ""
        if yards >= 20 {
            return "\(qb.fullName) connects with \(target.fullName) for a \(yards)-yard gain\(firstDownText)!"
        }
        return "\(qb.fullName) throws \(yards) yards to \(target.fullName)\(firstDownText)."
    }

    private static func rushDescription(rb: Player, yards: Int, firstDown: Bool) -> String {
        let firstDownText = firstDown ? " for a first down" : ""
        if yards < 0 {
            return "\(rb.fullName) is stopped for a loss of \(abs(yards)) yards."
        }
        if yards == 0 {
            return "\(rb.fullName) is stopped for no gain."
        }
        if yards >= 15 {
            return "\(rb.fullName) breaks free for a \(yards)-yard run\(firstDownText)!"
        }
        return "\(rb.fullName) rushes for \(yards) yards\(firstDownText)."
    }

    // MARK: - Scheme Fit Helpers

    /// Calculates a scheme fit modifier for a group of players.
    /// Returns a value typically in the range -0.05 to +0.10, representing the
    /// percentage adjustment to yard calculations based on how well players fit their scheme.
    private static func schemeFitModifier(
        players: [Player],
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

    private static func averageAttribute(_ players: [Player], extractor: (Player) -> Double) -> Double {
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
