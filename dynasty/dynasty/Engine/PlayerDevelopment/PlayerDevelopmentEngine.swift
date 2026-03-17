import Foundation

// MARK: - PlayerDevelopmentEngine

/// Stateless engine responsible for all player growth, regression, injuries, mentoring,
/// and offseason processing in Sunday Night Dynasty.
enum PlayerDevelopmentEngine {

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

        // --- Coaching multiplier ---
        // Find the matching position coach and apply the development bonus.
        let positionCoach = coaches.first { coach in
            CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: player.position)
        }
        if let positionCoach {
            let bonus = CoachingEngine.coachDevelopmentBonus(coach: positionCoach, player: player)
            totalPoints *= bonus
        }

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

        // --- Potential ceiling ---
        // Attribute ceiling scaled from truePotential (1-99).
        // A truePotential of 99 allows attributes up to 99; potential of 50 caps around 65.
        let ceiling = Int(Double(player.truePotential) * 0.65 + 35.0)

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
    }

    // MARK: - 2. In-Season Experience

    /// Applies small mental attribute gains from regular-season game experience.
    ///
    /// - Parameters:
    ///   - player: The player gaining experience.
    ///   - gamesPlayed: Number of games the player appeared in (0-17).
    ///   - gamesStarted: Number of games the player started (0-17).
    static func applyGameExperience(_ player: Player, gamesPlayed: Int, gamesStarted: Int) {
        guard gamesPlayed > 0 else { return }

        // Rookies gain more from experience than veterans.
        let experienceMultiplier: Double
        switch player.yearsPro {
        case 0:     experienceMultiplier = 1.0
        case 1:     experienceMultiplier = 0.7
        case 2...3: experienceMultiplier = 0.4
        default:    experienceMultiplier = 0.2
        }

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

    // MARK: - 7. Full Offseason Processing

    /// Runs the complete offseason pipeline for a roster of players: aging, development,
    /// injury processing, mentoring, and retirement evaluation.
    ///
    /// - Parameters:
    ///   - players: All players on the team.
    ///   - coaches: The full coaching staff.
    /// - Returns: Array of descriptions for notable events (retirements, injury updates, etc.).
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

        // --- Retirement evaluation ---
        for player in players {
            if shouldRetire(player: player) {
                events.append("\(player.fullName) (\(player.position.rawValue), age \(player.age)) has announced retirement.")
            }
        }

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

    // MARK: Retirement

    /// Determines whether a player should retire this offseason.
    /// Players 35+ with declining stats have increasing retirement chance.
    static func shouldRetire(player: Player) -> Bool {
        guard player.age >= 35 else { return false }

        // Base retirement chance increases with age beyond 35.
        let yearsOver35 = player.age - 35
        var retirementChance = Double(yearsOver35) * 0.12  // 12% per year over 35

        // Low overall rating increases retirement chance.
        if player.overall < 60 {
            retirementChance += 0.15
        } else if player.overall < 70 {
            retirementChance += 0.05
        }

        // Injuries make retirement more likely.
        if player.isInjured {
            retirementChance += 0.10
        }

        // Low durability suggests a body breaking down.
        if player.physical.durability < 50 {
            retirementChance += 0.10
        }

        // Kickers and punters can play longer.
        if player.position == .K || player.position == .P {
            retirementChance *= 0.5
        }

        return Double.random(in: 0.0..<1.0) < min(0.95, retirementChance)
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
