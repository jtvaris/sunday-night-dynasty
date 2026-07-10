import Foundation

// MARK: - PlayerDevelopmentEngine

/// Stateless engine responsible for all player growth, regression, injuries, mentoring,
/// and offseason processing in Sunday Night Dynasty.
enum PlayerDevelopmentEngine {

    // MARK: - Development Ceiling (shared formula)

    /// Single source of truth for the attribute-development ceiling scaled
    /// from `truePotential` (1-99): `truePotential * 0.65 + 35`.
    /// A truePotential of 99 allows attributes up to 99; potential of 50
    /// caps around 67.
    ///
    /// Every development path (offseason growth here, the R26 weekly
    /// training-focus tick, and the camp `TrainingPlanEngine`) MUST use this
    /// helper so the formula cannot drift between copies.
    static func developmentCeiling(for player: Player) -> Int {
        Int(Double(player.truePotential) * 0.65 + 35.0)
    }

    // MARK: - 1. Offseason Development

    /// Develops a player's attributes during the offseason based on work ethic, coaching,
    /// playing time, age, and potential ceiling.
    ///
    /// - Parameters:
    ///   - player: The player to develop (mutated in place).
    ///   - coaches: The full coaching staff available to the player's team.
    ///   - playingTimeShare: 0.0-1.0 representing how much the player played last season.
    static func developPlayer(_ player: Player, coaches: [Coach], playingTimeShare: Double) {
        let peakRange = player.position.peakAgeRange

        // Players past their peak receive no development -- only regression (handled elsewhere).
        guard player.age <= peakRange.upperBound else { return }

        // --- Base development points ---
        // Work ethic: 0-3 pts (scaled from 1-99)
        let workEthicPts = Double(player.mental.workEthic - 1) / 98.0 * 3.0
        // Coachability: 0-2 pts
        let coachabilityPts = Double(player.mental.coachability - 1) / 98.0 * 2.0
        // Playing time: 0-3 pts
        let playingTimePts = min(1.0, max(0.0, playingTimeShare)) * 3.0

        var totalPoints = workEthicPts + coachabilityPts + playingTimePts

        // --- Coaching multiplier (4-layer hierarchy) ---
        // Find coaching chain for this player
        let hc = coaches.first { $0.role == .headCoach }
        let ahc = coaches.first { $0.role == .assistantHeadCoach }
        let coordinator = coaches.first { coach in
            (player.position.side == .offense && coach.role == .offensiveCoordinator) ||
            (player.position.side == .defense && coach.role == .defensiveCoordinator) ||
            (player.position.side == .specialTeams && coach.role == .specialTeamsCoordinator)
        }
        let positionCoach = coaches.first { coach in
            CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: player.position)
        }

        let coachBonus = CoachingEngine.hierarchicalDevelopmentBonus(
            headCoach: hc,
            assistantHC: ahc,
            coordinator: coordinator,
            positionCoach: positionCoach,
            player: player
        )
        totalPoints *= coachBonus

        // --- Strength coach bonus ---
        // Adds 0.5-1.0 extra points toward physical attributes.
        let strengthCoach = coaches.first { $0.role == .strengthCoach }
        let strengthBonus: Double
        if let sc = strengthCoach {
            // Scale bonus based on coach's playerDevelopment attribute (50 is average).
            strengthBonus = 0.5 + (Double(sc.playerDevelopment) / 99.0) * 0.5
        } else {
            strengthBonus = 0.0
        }

        // --- Age factor ---
        let ageFactor: Double
        if player.age < peakRange.lowerBound {
            ageFactor = 1.0       // Full development before peak
        } else {
            ageFactor = 0.5       // Half development at peak
        }

        totalPoints *= ageFactor

        // --- Rookie accelerated development ---
        // Rookies start at 60-90% of true attributes (Phase 4 scaling) so they
        // have significant room to grow toward their ceiling in their first years.
        let rookieMultiplier: Double
        switch player.yearsPro {
        case 0:  rookieMultiplier = 2.5  // First offseason — massive college-to-NFL growth
        case 1:  rookieMultiplier = 1.8  // Second year leap
        case 2:  rookieMultiplier = 1.3  // Still improving
        default: rookieMultiplier = 1.0  // Normal rate
        }
        totalPoints *= rookieMultiplier

        // --- Boom/Bust year-1 roll ---
        // For rookies (yearsPro == 0), a "realization" roll can dramatically alter
        // their first-year trajectory — breakout stars or year-1 struggles.
        enum RookieOutcome { case breakout, struggle, normal }
        let rookieOutcome: RookieOutcome
        if player.yearsPro == 0 {
            let roll = Double.random(in: 0.0..<1.0)
            if roll < 0.05 {
                rookieOutcome = .breakout
            } else if roll < 0.10 {
                rookieOutcome = .struggle
            } else {
                rookieOutcome = .normal
            }
        } else {
            rookieOutcome = .normal
        }

        switch rookieOutcome {
        case .breakout:
            // BREAKOUT — triple all development gains; player is immediately impactful
            totalPoints *= 3.0
        case .struggle:
            // STRUGGLE — zero development this offseason, -2 to all mental attributes
            totalPoints = 0
            let mentalPaths: [WritableKeyPath<MentalAttributes, Int>] = [
                \.awareness, \.decisionMaking, \.clutch, \.workEthic, \.coachability, \.leadership
            ]
            for kp in mentalPaths {
                player.mental[keyPath: kp] = max(1, player.mental[keyPath: kp] - 2)
            }
        case .normal:
            break
        }

        // --- Potential ceiling ---
        // Attribute ceiling scaled from truePotential (1-99); shared formula.
        let ceiling = developmentCeiling(for: player)

        // --- Distribute points across attributes ---
        // Young players: physical develops faster. Older players: mental develops faster.
        let physicalWeight: Double
        let mentalWeight: Double
        if player.age < peakRange.lowerBound {
            physicalWeight = 0.65
            mentalWeight = 0.35
        } else {
            physicalWeight = 0.35
            mentalWeight = 0.65
        }

        let physicalPoints = Int((totalPoints * physicalWeight + strengthBonus).rounded())
        let mentalPoints = Int((totalPoints * mentalWeight).rounded())

        // Distribute physical points randomly across physical attributes.
        distributePhysicalPoints(player: player, points: physicalPoints, ceiling: ceiling)

        // Distribute mental points randomly across mental attributes.
        distributeMentalPoints(player: player, points: mentalPoints, ceiling: ceiling)

        // --- Young-player catch-up growth (league OVR-drift calibration) ---
        // Rookies convert at 60-90 % of their college attributes, but the
        // point distribution above only ever touches physical/mental —
        // position skills (50 % of OVR) stayed frozen at the scaled-down
        // entry level. Measured result (R32 multi-season verify): draft
        // classes entered ~12 OVR below the veterans they replaced, matured
        // only ~+1 OVR/season, and the league decayed ~0.5 OVR/season.
        // Fix: for their first offseasons young players close a fraction of
        // the gap between each position skill / mental attribute and the
        // shared development ceiling — self-limiting (gap shrinks, ceiling
        // caps), stronger for better coaching, zero for a struggle-rookie.
        if rookieOutcome != .struggle {
            // NOTE: processOffseason ages players BEFORE developPlayer, so a
            // player in his first pro camp arrives here with yearsPro == 1 —
            // the table therefore covers yearsPro 1-4 (first four camps);
            // case 0 only guards direct un-aged call paths.
            // Calibration iteration 2 (measured): with the prospect-potential
            // lift in place (intake avgPot ≈ 70, leaguePot stable ≈ 75) the
            // original fractions 0.25/0.18/0.12/0.08 INFLATED the league
            // +1.6 OVR in 4 seasons — higher ceilings made the same fraction
            // worth more points. Trimmed ~25 % to hold 5-season drift in
            // |Δ| ≤ 1.5 while young classes still mature into starters.
            let catchUpFraction: Double
            switch player.yearsPro {
            case 0, 1: catchUpFraction = 0.19
            case 2:    catchUpFraction = 0.13
            case 3:    catchUpFraction = 0.09
            case 4:    catchUpFraction = 0.06
            default:   catchUpFraction = 0.0
            }
            if catchUpFraction > 0 {
                // Coaching quality sways the reps a little (±10 %).
                let coachFactor = min(1.1, max(0.9, coachBonus))
                applyCatchUpGrowth(
                    player: player,
                    fraction: catchUpFraction * coachFactor,
                    ceiling: ceiling
                )
            }
        }

        // --- Position Training (offseason = full intensity) ---
        if let trainingPos = player.trainingPosition, trainingPos != player.position {
            let posCoach = coaches.first { coach in
                CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: trainingPos)
            }
            let posGain = VersatilityDevelopmentEngine.trainPosition(
                player: player,
                targetPosition: trainingPos,
                positionCoach: posCoach,
                practiceIntensity: 1.0
            )
            let key = trainingPos.rawValue
            let current = player.positionFamiliarity[key] ?? 0
            let posCeiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: trainingPos)
            player.positionFamiliarity[key] = min(posCeiling, current + posGain)
        }

        // --- Scheme Learning (offseason = full intensity) ---
        let oc = coaches.first { $0.role == .offensiveCoordinator }
        let dc = coaches.first { $0.role == .defensiveCoordinator }

        if let offScheme = oc?.offensiveScheme, player.position.side == .offense {
            let gain = VersatilityDevelopmentEngine.learnScheme(
                player: player,
                scheme: offScheme.rawValue,
                coordinator: oc,
                practiceIntensity: 1.0
            )
            let current = player.schemeFamiliarity[offScheme.rawValue] ?? 0
            player.schemeFamiliarity[offScheme.rawValue] = min(100, current + gain)
        }

        if let defScheme = dc?.defensiveScheme, player.position.side == .defense {
            let gain = VersatilityDevelopmentEngine.learnScheme(
                player: player,
                scheme: defScheme.rawValue,
                coordinator: dc,
                practiceIntensity: 1.0
            )
            let current = player.schemeFamiliarity[defScheme.rawValue] ?? 0
            player.schemeFamiliarity[defScheme.rawValue] = min(100, current + gain)
        }
    }

    // MARK: - 2. In-Season Experience

    /// Applies small mental attribute gains from regular-season game experience.
    ///
    /// - Parameters:
    ///   - player: The player gaining experience.
    ///   - gamesPlayed: Number of games the player appeared in (0-17).
    ///   - gamesStarted: Number of games the player started (0-17).
    ///   - experienceBoost: R25 locker-room modifier — an active mentorship
    ///     speeds a young player's growth. Clamped to 0.9...1.1 (max ±10 %).
    static func applyGameExperience(
        _ player: Player,
        gamesPlayed: Int,
        gamesStarted: Int,
        experienceBoost: Double = 1.0
    ) {
        guard gamesPlayed > 0 else { return }

        // Rookies gain more from experience than veterans.
        let baseMultiplier: Double
        switch player.yearsPro {
        case 0:     baseMultiplier = 1.0
        case 1:     baseMultiplier = 0.7
        case 2...3: baseMultiplier = 0.4
        default:    baseMultiplier = 0.2
        }
        let experienceMultiplier = baseMultiplier * min(max(experienceBoost, 0.9), 1.1)

        // Base gain from games played and started (0.0-1.0 range).
        let gamesFactor = (Double(gamesPlayed) / 17.0) * 0.5 + (Double(gamesStarted) / 17.0) * 0.5

        // Awareness improvement (0-1 point).
        let awarenessGain = Int((gamesFactor * experienceMultiplier * 1.0).rounded())
        if awarenessGain > 0 {
            player.mental.awareness = min(99, player.mental.awareness + awarenessGain)
        }

        // Decision making improvement (0-1 point).
        let decisionGain = Int((gamesFactor * experienceMultiplier * 0.8).rounded())
        if decisionGain > 0 {
            player.mental.decisionMaking = min(99, player.mental.decisionMaking + decisionGain)
        }

        // Clutch: random chance of improvement if player was in close games.
        // Simplified: ~30% chance per season for active starters.
        if gamesStarted > 8 && Double.random(in: 0.0..<1.0) < 0.3 * experienceMultiplier {
            player.mental.clutch = min(99, player.mental.clutch + 1)
        }
    }

    // MARK: - 3. Age Regression

    /// Ages the player by one year, increments yearsPro, and applies age-based regression
    /// to physical (and eventually mental) attributes.
    ///
    /// - Parameter player: The player to age and potentially regress.
    static func applyAgeRegression(_ player: Player) {
        player.age += 1
        player.yearsPro += 1

        let peakRange = player.position.peakAgeRange
        let yearsPastPeak = player.age - peakRange.upperBound

        if yearsPastPeak < 0 {
            // Before peak: no regression.
            return
        }

        if yearsPastPeak == 0 {
            // At peak: 10% chance of -1 to 1-2 physical attributes.
            guard Double.random(in: 0.0..<1.0) < 0.10 else { return }
            let attributeCount = Int.random(in: 1...2)
            regressPhysicalAttributes(player: player, count: attributeCount, range: 1...1)
            return
        }

        if yearsPastPeak <= 3 {
            // 1-3 years past peak: 40% chance, physical attributes lose 1-3 points.
            guard Double.random(in: 0.0..<1.0) < 0.40 else { return }
            let attributeCount = Int.random(in: 2...4)
            regressPhysicalAttributes(player: player, count: attributeCount, range: 1...3)
        } else {
            // 4+ years past peak: 80% chance, physical lose 2-5 points, mental lose 1-2.
            if Double.random(in: 0.0..<1.0) < 0.80 {
                let physCount = Int.random(in: 3...6)
                regressPhysicalAttributes(player: player, count: physCount, range: 2...5)

                // Mental regression starts (but awareness and leadership are protected).
                let mentalCount = Int.random(in: 1...2)
                regressMentalAttributes(player: player, count: mentalCount, range: 1...2)
            }
        }

        // Durability specifically decreases with age, especially with injury history.
        if yearsPastPeak > 0 {
            let injuryPenalty = player.isInjured ? 2 : 0
            let durabilityLoss = Int.random(in: 0...1) + injuryPenalty
            if durabilityLoss > 0 {
                player.physical.durability = max(1, player.physical.durability - durabilityLoss)
            }
        }
    }

    // MARK: - 4. Mentor System

    /// Pairs eligible veteran mentors with rookies at the same position and applies
    /// mental attribute bonuses (or penalties for bad mentors).
    ///
    /// - Parameters:
    ///   - veterans: Veteran players on the team roster.
    ///   - rookies: Rookie players on the team roster.
    static func applyMentoring(veterans: [Player], rookies: [Player]) {
        for veteran in veterans {
            // Only mentors/team leaders with leadership > 75 can mentor positively.
            let isMentor = veteran.personality.isMentor && veteran.mental.leadership > 75

            // Bad mentors: dramaQueen or loneWolf with low leadership.
            let isBadMentor: Bool
            switch veteran.personality.archetype {
            case .dramaQueen:
                isBadMentor = true
            case .loneWolf:
                isBadMentor = veteran.mental.leadership < 50
            default:
                isBadMentor = false
            }

            guard isMentor || isBadMentor else { continue }

            // Find rookies at the same position.
            let eligibleRookies = rookies.filter { $0.position == veteran.position && $0.yearsPro <= 1 }
            guard !eligibleRookies.isEmpty else { continue }

            for rookie in eligibleRookies {
                if isBadMentor {
                    // Negative mentoring: -1 to -2 on 1-2 mental attributes.
                    let penaltyCount = Int.random(in: 1...2)
                    applyMentalBonus(player: rookie, totalPoints: -penaltyCount, range: -2...(-1))
                } else {
                    // Positive mentoring: +1 to +3 bonus to mental attributes.
                    // Mentor's coachability determines the magnitude.
                    let baseMentorBonus = Double(veteran.mental.coachability - 1) / 98.0
                    let bonusPoints = Int((baseMentorBonus * 3.0).rounded().clamped(to: 1...3))
                    applyMentalBonus(player: rookie, totalPoints: bonusPoints, range: 1...3)
                }
            }
        }
    }

    // MARK: - 5. Potential Realization

    /// Updates the player's effective development ceiling based on scheme fit, morale,
    /// and coaching quality.
    ///
    /// - Parameters:
    ///   - player: The player to evaluate.
    ///   - schemeFit: 0.0-1.0 indicating how well the player fits the team's scheme.
    ///   - moraleAverage: The player's average morale over the season (1-100).
    static func updatePotentialRealization(_ player: Player, schemeFit: Double, moraleAverage: Int) {
        // Scheme fit contribution: good fit (>0.7) raises ceiling, bad fit (<0.3) lowers it.
        let fitModifier: Int
        if schemeFit >= 0.8 {
            fitModifier = Int.random(in: 1...3)
        } else if schemeFit >= 0.6 {
            fitModifier = Int.random(in: 0...1)
        } else if schemeFit >= 0.4 {
            fitModifier = 0
        } else if schemeFit >= 0.2 {
            fitModifier = Int.random(in: -2...0)
        } else {
            fitModifier = Int.random(in: -3...(-1))
        }

        // Morale contribution: high morale + good fit boosts ceiling.
        let moraleModifier: Int
        if moraleAverage >= 80 {
            moraleModifier = Int.random(in: 1...2)
        } else if moraleAverage >= 60 {
            moraleModifier = 0
        } else if moraleAverage >= 40 {
            moraleModifier = Int.random(in: -1...0)
        } else {
            moraleModifier = Int.random(in: -2...(-1))
        }

        // Apply the combined modifier to truePotential (effective ceiling).
        let totalModifier = fitModifier + moraleModifier
        player.truePotential = max(1, min(99, player.truePotential + totalModifier))
    }

    // MARK: - 6. Injury System

    /// Processes an existing injury: decrements recovery time and handles healing.
    ///
    /// - Parameter player: The injured player to process.
    /// - Returns: `nil` if no change, or a description string if healed or permanent damage occurred.
    static func processInjury(_ player: Player) -> String? {
        guard player.isInjured else { return nil }

        player.injuryWeeksRemaining -= 1

        guard player.injuryWeeksRemaining <= 0 else { return nil }

        // Player has healed.
        player.isInjured = false
        player.injuryWeeksRemaining = 0

        // Small chance of permanent durability loss upon healing.
        let permanentDamageChance = 0.15
        if Double.random(in: 0.0..<1.0) < permanentDamageChance {
            let durabilityLoss = Int.random(in: 1...5)
            player.physical.durability = max(1, player.physical.durability - durabilityLoss)
            return "\(player.fullName) has healed but suffered permanent durability loss (-\(durabilityLoss))."
        }

        return "\(player.fullName) has fully recovered from injury."
    }

    /// Checks whether a player sustains an injury during a game.
    ///
    /// - Parameters:
    ///   - player: The player at risk of injury.
    ///   - playIntensity: 0.0-1.0 representing the contact level of the play.
    /// - Returns: `nil` if no injury, or a tuple with injury details.
    static func checkForInjury(
        _ player: Player,
        playIntensity: Double
    ) -> (injured: Bool, weeksOut: Int, description: String)? {
        // Base injury chance: ~2% per game.
        var injuryChance = 0.02

        // Durability modifier: high durability reduces risk.
        let durabilityFactor = (99.0 - Double(player.physical.durability)) / 99.0 * 0.03
        injuryChance += durabilityFactor

        // Fatigue modifier: high fatigue increases risk.
        let fatigueFactor = Double(player.fatigue) / 100.0 * 0.03
        injuryChance += fatigueFactor

        // Age modifier: older players are more fragile.
        let peakRange = player.position.peakAgeRange
        let yearsPastPeak = max(0, player.age - peakRange.upperBound)
        let ageFactor = Double(yearsPastPeak) * 0.005
        injuryChance += ageFactor

        // Play intensity modifier.
        injuryChance *= (0.5 + playIntensity * 0.5)

        guard Double.random(in: 0.0..<1.0) < injuryChance else { return nil }

        // Determine severity.
        let severityRoll = Double.random(in: 0.0..<1.0)
        let weeksOut: Int
        let description: String

        if severityRoll < 0.45 {
            // Minor: 1-2 weeks
            weeksOut = Int.random(in: 1...2)
            description = minorInjuryDescription(weeksOut: weeksOut)
        } else if severityRoll < 0.75 {
            // Moderate: 3-6 weeks
            weeksOut = Int.random(in: 3...6)
            description = moderateInjuryDescription(weeksOut: weeksOut)
        } else if severityRoll < 0.93 {
            // Major: 7-16 weeks
            weeksOut = Int.random(in: 7...16)
            description = majorInjuryDescription(weeksOut: weeksOut)
        } else {
            // Season-ending: 17+ weeks
            weeksOut = Int.random(in: 17...52)
            description = seasonEndingInjuryDescription(weeksOut: weeksOut)
        }

        // Apply the injury to the player.
        player.isInjured = true
        player.injuryWeeksRemaining = weeksOut

        return (injured: true, weeksOut: weeksOut, description: "\(description) (\(weeksOut) weeks)")
    }

    // MARK: - 7. Potential Assessment

    /// Converts a player's hidden `truePotential` into a verbal `PotentialLabel`,
    /// with noise that decreases over time and with better coaching.
    ///
    /// - Parameters:
    ///   - player: The player to evaluate.
    ///   - coachDevelopmentRating: The position/development coach's playerDevelopment attribute (1-99).
    ///   - yearsOnTeam: How many years the player has been on this team.
    /// - Returns: A `PotentialLabel` representing the coaching staff's best guess at the player's ceiling.
    static func assessPotential(player: Player, coachDevelopmentRating: Int, yearsOnTeam: Int) -> PotentialLabel {
        // Base noise level depends on how long the coaching staff has had to evaluate the player.
        var noise: Int
        switch yearsOnTeam {
        case 0:     noise = 2   // Just drafted/acquired — very inaccurate
        case 1:     noise = 1   // One year of observation
        default:    noise = 0   // Two+ years — accurate assessment
        }

        // Elite development coaches (rating >= 80) reduce noise by 1 level.
        if coachDevelopmentRating >= 80 {
            noise = max(0, noise - 1)
        }

        return PotentialLabel.from(potential: player.truePotential, noise: noise)
    }

    // MARK: - 8. Full Offseason Processing

    /// Runs the complete offseason pipeline for a roster of players: aging, development,
    /// injury processing, and mentoring.
    ///
    /// Retirement is NOT decided here — `PlayerRetirementEngine` handles it
    /// once per offseason in the `.coachingChanges` phase (R32), before free
    /// agency, so departures actually leave the league.
    ///
    /// - Parameters:
    ///   - players: All players on the team.
    ///   - coaches: The full coaching staff.
    /// - Returns: Array of descriptions for notable events (injury updates, etc.).
    @discardableResult
    static func processOffseason(players: [Player], coaches: [Coach]) -> [String] {
        var events: [String] = []

        // --- Age regression and development ---
        for player in players {
            applyAgeRegression(player)

            // Default playing time share based on age/yearsPro as a rough proxy.
            // In a full implementation this would come from actual season data.
            let estimatedPlayingTime = estimatePlayingTimeShare(player: player)
            developPlayer(player, coaches: coaches, playingTimeShare: estimatedPlayingTime)

            // Offseason injury processing (rare offseason injuries).
            if player.isInjured {
                if let result = processInjury(player) {
                    events.append(result)
                }
            }

            // Reset fatigue for the new season.
            player.fatigue = 0
        }

        // --- Mentoring ---
        let veterans = players.filter { $0.yearsPro >= 4 }
        let rookies = players.filter { $0.yearsPro <= 1 }
        applyMentoring(veterans: veterans, rookies: rookies)

        return events
    }
}

// MARK: - Private Helpers

private extension PlayerDevelopmentEngine {

    // MARK: Point Distribution

    /// Distributes development points randomly across a player's physical attributes,
    /// capped by the potential ceiling.
    static func distributePhysicalPoints(player: Player, points: Int, ceiling: Int) {
        guard points > 0 else { return }

        // All physical attribute key paths.
        let keyPaths: [WritableKeyPath<PhysicalAttributes, Int>] = [
            \.speed, \.acceleration, \.strength, \.agility, \.stamina, \.durability
        ]

        var remaining = points
        var shuffled = keyPaths.shuffled()

        while remaining > 0 && !shuffled.isEmpty {
            let kp = shuffled.removeFirst()
            let current = player.physical[keyPath: kp]
            guard current < ceiling else { continue }

            let gain = min(remaining, Int.random(in: 1...max(1, remaining)))
            let newValue = min(ceiling, min(99, current + gain))
            let actualGain = newValue - current
            player.physical[keyPath: kp] = newValue
            remaining -= actualGain
        }
    }

    /// Distributes development points randomly across a player's mental attributes,
    /// capped by the potential ceiling.
    static func distributeMentalPoints(player: Player, points: Int, ceiling: Int) {
        guard points > 0 else { return }

        let keyPaths: [WritableKeyPath<MentalAttributes, Int>] = [
            \.awareness, \.decisionMaking, \.clutch, \.workEthic, \.coachability, \.leadership
        ]

        var remaining = points
        var shuffled = keyPaths.shuffled()

        while remaining > 0 && !shuffled.isEmpty {
            let kp = shuffled.removeFirst()
            let current = player.mental[keyPath: kp]
            guard current < ceiling else { continue }

            let gain = min(remaining, Int.random(in: 1...max(1, remaining)))
            let newValue = min(ceiling, min(99, current + gain))
            let actualGain = newValue - current
            player.mental[keyPath: kp] = newValue
            remaining -= actualGain
        }
    }

    // MARK: Young-Player Catch-Up Growth

    /// Moves every position skill and mental attribute a fraction of the way
    /// toward the player's development ceiling (never past 99, never
    /// downward). Physical attributes are excluded: rookies convert with a
    /// +0.05 physical readiness bonus and already enter near-complete.
    static func applyCatchUpGrowth(player: Player, fraction: Double, ceiling: Int) {
        let cap = min(99, ceiling)

        func grown(_ value: Int) -> Int {
            guard value < cap else { return value }
            let gain = Int((Double(cap - value) * fraction).rounded())
            return min(cap, value + gain)
        }

        // Mental attributes (20 % of OVR) enter scaled-down too.
        let mentalPaths: [WritableKeyPath<MentalAttributes, Int>] = [
            \.awareness, \.decisionMaking, \.clutch, \.workEthic, \.coachability, \.leadership
        ]
        for kp in mentalPaths {
            player.mental[keyPath: kp] = grown(player.mental[keyPath: kp])
        }

        // Position skills (50 % of OVR) — the frozen component this fixes.
        switch player.positionAttributes {
        case .quarterback(var a):
            a.armStrength = grown(a.armStrength)
            a.accuracyShort = grown(a.accuracyShort)
            a.accuracyMid = grown(a.accuracyMid)
            a.accuracyDeep = grown(a.accuracyDeep)
            a.pocketPresence = grown(a.pocketPresence)
            a.scrambling = grown(a.scrambling)
            player.positionAttributes = .quarterback(a)
        case .runningBack(var a):
            a.vision = grown(a.vision)
            a.elusiveness = grown(a.elusiveness)
            a.breakTackle = grown(a.breakTackle)
            a.receiving = grown(a.receiving)
            player.positionAttributes = .runningBack(a)
        case .wideReceiver(var a):
            a.routeRunning = grown(a.routeRunning)
            a.catching = grown(a.catching)
            a.release = grown(a.release)
            a.spectacularCatch = grown(a.spectacularCatch)
            player.positionAttributes = .wideReceiver(a)
        case .tightEnd(var a):
            a.blocking = grown(a.blocking)
            a.catching = grown(a.catching)
            a.routeRunning = grown(a.routeRunning)
            a.speed = grown(a.speed)
            player.positionAttributes = .tightEnd(a)
        case .offensiveLine(var a):
            a.runBlock = grown(a.runBlock)
            a.passBlock = grown(a.passBlock)
            a.pull = grown(a.pull)
            a.anchor = grown(a.anchor)
            player.positionAttributes = .offensiveLine(a)
        case .defensiveLine(var a):
            a.passRush = grown(a.passRush)
            a.blockShedding = grown(a.blockShedding)
            a.powerMoves = grown(a.powerMoves)
            a.finesseMoves = grown(a.finesseMoves)
            player.positionAttributes = .defensiveLine(a)
        case .linebacker(var a):
            a.tackling = grown(a.tackling)
            a.zoneCoverage = grown(a.zoneCoverage)
            a.manCoverage = grown(a.manCoverage)
            a.blitzing = grown(a.blitzing)
            player.positionAttributes = .linebacker(a)
        case .defensiveBack(var a):
            a.manCoverage = grown(a.manCoverage)
            a.zoneCoverage = grown(a.zoneCoverage)
            a.press = grown(a.press)
            a.ballSkills = grown(a.ballSkills)
            player.positionAttributes = .defensiveBack(a)
        case .kicking(var a):
            a.kickPower = grown(a.kickPower)
            a.kickAccuracy = grown(a.kickAccuracy)
            player.positionAttributes = .kicking(a)
        }
    }

    // MARK: Regression

    /// Regresses random physical attributes. Speed and acceleration are targeted first.
    static func regressPhysicalAttributes(player: Player, count: Int, range: ClosedRange<Int>) {
        // Speed and acceleration regress first -- they appear at the front of the list.
        var keyPaths: [WritableKeyPath<PhysicalAttributes, Int>] = [
            \.speed, \.acceleration
        ]
        // Remaining attributes are shuffled and appended.
        var others: [WritableKeyPath<PhysicalAttributes, Int>] = [
            \.strength, \.agility, \.stamina
        ]
        others.shuffle()
        keyPaths.append(contentsOf: others)
        // Note: durability is handled separately in applyAgeRegression.

        for i in 0..<min(count, keyPaths.count) {
            let kp = keyPaths[i]
            let loss = Int.random(in: range)
            player.physical[keyPath: kp] = max(1, player.physical[keyPath: kp] - loss)
        }
    }

    /// Regresses random mental attributes. Awareness and leadership are protected (regress last).
    static func regressMentalAttributes(player: Player, count: Int, range: ClosedRange<Int>) {
        // These regress first (least protected).
        var keyPaths: [WritableKeyPath<MentalAttributes, Int>] = [
            \.clutch, \.decisionMaking, \.workEthic, \.coachability
        ]
        keyPaths.shuffle()
        // Awareness and leadership are appended last -- they regress only if count is very high.
        keyPaths.append(contentsOf: [\.awareness, \.leadership])

        for i in 0..<min(count, keyPaths.count) {
            let kp = keyPaths[i]
            let loss = Int.random(in: range)
            player.mental[keyPath: kp] = max(1, player.mental[keyPath: kp] - loss)
        }
    }

    // MARK: Mentoring Bonus Application

    /// Applies a set of mental attribute bonuses (positive or negative) to a player.
    static func applyMentalBonus(player: Player, totalPoints: Int, range: ClosedRange<Int>) {
        let keyPaths: [WritableKeyPath<MentalAttributes, Int>] = [
            \.awareness, \.decisionMaking, \.clutch, \.workEthic, \.coachability, \.leadership
        ]

        let count = abs(totalPoints)
        let shuffled = keyPaths.shuffled()

        for i in 0..<min(count, shuffled.count) {
            let kp = shuffled[i]
            let delta = Int.random(in: range)
            let current = player.mental[keyPath: kp]
            player.mental[keyPath: kp] = max(1, min(99, current + delta))
        }
    }

    // MARK: Injury Descriptions

    static func minorInjuryDescription(weeksOut: Int) -> String {
        let injuries = [
            "Sprained ankle", "Bruised ribs", "Mild hamstring strain",
            "Jammed finger", "Minor knee sprain", "Stinger"
        ]
        return injuries.randomElement()!
    }

    static func moderateInjuryDescription(weeksOut: Int) -> String {
        let injuries = [
            "High ankle sprain", "MCL sprain", "Separated shoulder",
            "Hamstring tear", "Fractured hand", "Calf strain"
        ]
        return injuries.randomElement()!
    }

    static func majorInjuryDescription(weeksOut: Int) -> String {
        let injuries = [
            "Torn ACL", "Broken collarbone", "Torn labrum",
            "Broken leg", "Lisfranc injury", "Torn pectoral"
        ]
        return injuries.randomElement()!
    }

    static func seasonEndingInjuryDescription(weeksOut: Int) -> String {
        let injuries = [
            "Torn Achilles", "Torn ACL + MCL", "Compound fracture",
            "Spinal contusion", "Torn ACL and meniscus", "Dislocated hip"
        ]
        return injuries.randomElement()!
    }

    // MARK: Playing Time Estimation

    /// Provides a rough playing time estimate for offseason processing when
    /// actual game data is not available.
    static func estimatePlayingTimeShare(player: Player) -> Double {
        // Younger, higher-rated players are assumed to have played more.
        let overallFactor = Double(player.overall) / 99.0
        let experienceFactor: Double
        switch player.yearsPro {
        case 0:      experienceFactor = 0.2   // Rookie, likely a backup
        case 1:      experienceFactor = 0.4
        case 2...4:  experienceFactor = 0.7
        default:     experienceFactor = 0.6   // Veterans vary
        }
        return min(1.0, (overallFactor * 0.6 + experienceFactor * 0.4))
    }
}

// MARK: - Clamping Helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
