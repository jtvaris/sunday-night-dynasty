import Foundation

/// Handles coach XP accumulation, attribute growth, aging, retirement, and potential.
enum CoachDevelopmentEngine {

    // MARK: - Potential Generation

    /// Generate potential for a new coach based on age bracket.
    static func generatePotential(forAge age: Int) -> Int {
        switch age {
        case ...30:   return Int.random(in: 40...99)
        case 31...40: return Int.random(in: 45...90)
        case 41...50: return Int.random(in: 50...80)
        case 51...60: return Int.random(in: 40...70)
        default:      return Int.random(in: 30...60)
        }
    }

    // MARK: - Weekly XP

    /// Apply XP from a single game week.
    static func applyWeeklyXP(
        coach: Coach,
        didWin: Bool,
        isPlayoff: Bool,
        headCoach: Coach?,
        assistantHC: Coach?
    ) {
        var xp = 5  // Base weekly XP
        if didWin { xp += 3 }
        else { xp += 1 }
        if isPlayoff { xp += 8 }

        // HC mentoring multiplier (0.6x–1.5x) — PRIMARY LEVER
        let hcMultiplier: Double
        if let hc = headCoach, hc.id != coach.id {
            let leadership = Double(hc.motivation + hc.playerDevelopment) / 2.0
            hcMultiplier = 0.6 + (leadership - 30.0) / 60.0 * 0.9
        } else {
            hcMultiplier = 1.0  // HC doesn't mentor themselves
        }

        // AHC secondary bonus (0–20%)
        var ahcBonus = 0.0
        if let ahc = assistantHC, ahc.id != coach.id {
            ahcBonus = Double(ahc.playerDevelopment - 50) / 50.0 * 0.20
        }

        let totalMultiplier = max(0.3, hcMultiplier + ahcBonus)
        coach.currentXP += Int(Double(xp) * totalMultiplier)
    }

    // MARK: - Seasonal Development

    /// End-of-season: convert XP to attribute growth, apply aging, check retirement.
    static func applySeasonalDevelopment(
        coach: Coach,
        teamWins: Int,
        madePlayoffs: Bool,
        wonSuperBowl: Bool,
        headCoach: Coach?,
        assistantHC: Coach?
    ) {
        // 1. Add seasonal XP bonuses
        var seasonXP = 20  // Base
        if teamWins >= 9 { seasonXP += 15 }
        if madePlayoffs { seasonXP += 20 }
        if teamWins >= 12 { seasonXP += 30 }  // Conference championship caliber
        if wonSuperBowl { seasonXP += 60 }

        // HC multiplier on seasonal XP too
        let hcMult: Double
        if let hc = headCoach, hc.id != coach.id {
            let leadership = Double(hc.motivation + hc.playerDevelopment) / 2.0
            hcMult = 0.6 + (leadership - 30.0) / 60.0 * 0.9
        } else {
            hcMult = 1.0
        }
        coach.currentXP += Int(Double(seasonXP) * hcMult)

        // 2. Convert accumulated XP to attribute growth
        convertXPToGrowth(coach: coach)

        // 3. Age-based decline
        applyAgingDecline(coach: coach)

        // 4. Age the coach
        coach.age += 1
        coach.yearsExperience += 1

        // 5. Reputation based on wins (keep existing logic)
        applyReputationChange(coach: coach, teamWins: teamWins)

        // 6. Clear adjustment period if promoted 1+ seasons ago
        coach.promotedInSeason = nil

        // 7. Reset XP for next season
        coach.currentXP = 0
    }

    // MARK: - XP to Attribute Conversion

    private static func convertXPToGrowth(coach: Coach) {
        let ceiling = coach.attributeCeiling
        var remainingXP = coach.currentXP
        let focusAttrs = coach.role.focusAttributes

        // All 12 attribute names
        let allAttrs = [
            "playCalling", "playerDevelopment", "reputation", "adaptability",
            "gamePlanning", "scoutingAbility", "recruiting", "motivation",
            "discipline", "mediaHandling", "contractNegotiation", "moraleInfluence"
        ]

        // Build weighted pool: focus attributes get 2x weight
        var pool: [String] = []
        for attr in allAttrs {
            pool.append(attr)
            if focusAttrs.contains(attr) {
                pool.append(attr)  // Double weight
            }
        }

        // Attempt to spend XP on random attributes
        var attempts = 0
        while remainingXP > 0 && attempts < 20 {
            attempts += 1
            let attr = pool.randomElement()!
            let currentValue = coach.attributeValue(named: attr)

            guard currentValue < ceiling else { continue }

            let cost = 25 + Int(Double(currentValue) * 0.5)
            guard remainingXP >= cost else { break }

            remainingXP -= cost
            coach.setAttributeValue(named: attr, value: min(ceiling, currentValue + 1))
        }
    }

    // MARK: - Aging Decline

    static func applyAgingDecline(coach: Coach) {
        let age = coach.age
        guard age >= 50 else { return }

        let declineChance: Double
        let maxDecline: Int
        switch age {
        case 50...55: declineChance = 0.10; maxDecline = 1
        case 56...60: declineChance = 0.25; maxDecline = 2
        case 61...65: declineChance = 0.40; maxDecline = 2
        default:      declineChance = 0.60; maxDecline = 3
        }

        if Double.random(in: 0...1) < declineChance {
            let decline = Int.random(in: 1...maxDecline)
            coach.adaptability = max(1, coach.adaptability - decline)
            if age >= 56 {
                coach.playCalling = max(1, coach.playCalling - Int.random(in: 0...1))
            }
            if age >= 61 {
                coach.gamePlanning = max(1, coach.gamePlanning - Int.random(in: 0...1))
            }
        }
    }

    // MARK: - Retirement

    static func shouldRetire(coach: Coach) -> Bool {
        guard coach.age >= 65 else { return false }
        let baseChance = Double(coach.age - 64) * 0.15
        let reputationModifier = coach.reputation >= 80 ? 0.5 : 1.0
        return Double.random(in: 0...1) < (baseChance * reputationModifier)
    }

    // MARK: - Reputation

    private static func applyReputationChange(coach: Coach, teamWins: Int) {
        let change: Int
        switch teamWins {
        case 14...17: change = Int.random(in: 3...6)
        case 11...13: change = Int.random(in: 1...3)
        case 8...10:  change = Int.random(in: -1...1)
        case 5...7:   change = Int.random(in: -3...(-1))
        default:      change = Int.random(in: -6...(-3))
        }
        coach.reputation = min(99, max(1, coach.reputation + change))
    }

    // MARK: - Mentor Assignment

    static func setMentor(coach: Coach, headCoach: Coach?, teamName: String, season: Int) {
        guard let hc = headCoach, hc.id != coach.id else { return }
        if coach.mentorCoachID == nil {
            coach.mentorCoachID = hc.id
            coach.mentorshipOrigin = "\(season) \(teamName)"
        }
    }
}
