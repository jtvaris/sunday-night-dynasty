import Foundation

/// Calculates dynamic coaching budgets based on owner spending willingness,
/// media market size, and season performance.
enum BudgetEngine {

    /// Recalculate coaching budget for a new season.
    ///
    /// Budget formula:
    /// - Base from spending willingness: $15M-$55M
    /// - Market size modifier: +10% large, 0% medium, -10% small
    /// - Success modifier: playoff teams get +15%, winning records +8%, losing records -5% to -10%
    ///
    /// - Returns: New coaching budget in thousands (e.g. 25000 = $25M). Floor of $12M.
    static func calculateBudget(
        owner: Owner,
        team: Team,
        previousSeasonWins: Int,
        madePlayoffs: Bool
    ) -> Int {
        // Base from spending willingness: $15M-$55M
        // Low spender (20) -> ~$23M, average (50) -> ~$35M, high spender (95) -> ~$53M
        let baseBudget = 15_000 + Int(Double(owner.spendingWillingness) / 99.0 * 40_000.0)

        // Market size modifier: +10% large, 0% medium, -10% small
        let marketModifier: Double = {
            switch team.mediaMarket {
            case .large:  return 1.10
            case .medium: return 1.0
            case .small:  return 0.90
            }
        }()

        // Success modifier: winning → owner spends more
        let successModifier: Double = {
            if madePlayoffs { return 1.15 }
            if previousSeasonWins >= 10 { return 1.08 }
            if previousSeasonWins >= 7 { return 1.0 }
            if previousSeasonWins >= 4 { return 0.95 }
            return 0.90  // Bad season = budget cut
        }()

        // R31: owner archetype opens or tightens the wallet (±10-15%)
        let personaModifier = OwnerPersonaEngine.OwnerArchetype.from(owner).budgetMultiplier

        let total = Double(baseBudget) * marketModifier * successModifier * personaModifier
        return max(12_000, Int(total))  // Floor of $12M
    }

    // MARK: - Scouting Budget (R27)

    /// Recalculate the dedicated scouting department budget for a new season.
    ///
    /// Uses the same shape as the coaching budget but a much smaller pot:
    /// - Base from spending willingness: $2M-$6M
    /// - Market size modifier: ±10%
    /// - Success modifier: 0.90-1.15
    ///
    /// - Returns: New scouting budget in thousands (e.g. 4000 = $4M). Floor of $1.5M.
    static func calculateScoutingBudget(
        owner: Owner,
        team: Team,
        previousSeasonWins: Int,
        madePlayoffs: Bool
    ) -> Int {
        let baseBudget = defaultScoutingBudget(spendingWillingness: owner.spendingWillingness)

        let marketModifier: Double = {
            switch team.mediaMarket {
            case .large:  return 1.10
            case .medium: return 1.0
            case .small:  return 0.90
            }
        }()

        let successModifier: Double = {
            if madePlayoffs { return 1.15 }
            if previousSeasonWins >= 10 { return 1.08 }
            if previousSeasonWins >= 7 { return 1.0 }
            if previousSeasonWins >= 4 { return 0.95 }
            return 0.90
        }()

        // R31: owner archetype opens or tightens the wallet
        let personaModifier = OwnerPersonaEngine.OwnerArchetype.from(owner).budgetMultiplier

        let total = Double(baseBudget) * marketModifier * successModifier * personaModifier
        return max(1_500, Int(total))  // Floor of $1.5M
    }

    /// Baseline scouting budget in thousands derived from owner spending willingness.
    /// Low spender (20) → ~$2.8M, average (50) → ~$4M, big spender (95) → ~$5.8M.
    static func defaultScoutingBudget(spendingWillingness: Int) -> Int {
        2_000 + Int(Double(spendingWillingness) / 99.0 * 4_000.0)
    }

    // MARK: - Medical Budget (R31)

    /// Recalculate the dedicated medical department budget for a new season.
    /// Same shape as the other pots, smallest envelope:
    /// - Base from spending willingness: $1.5M-$4M
    /// - Market size modifier: ±10%
    /// - Success modifier: 0.90-1.15
    /// - Archetype modifier: 0.85-1.10
    ///
    /// - Returns: New medical budget in thousands (e.g. 2500 = $2.5M). Floor of $1.2M.
    static func calculateMedicalBudget(
        owner: Owner,
        team: Team,
        previousSeasonWins: Int,
        madePlayoffs: Bool
    ) -> Int {
        let baseBudget = defaultMedicalBudget(spendingWillingness: owner.spendingWillingness)

        let marketModifier: Double = {
            switch team.mediaMarket {
            case .large:  return 1.10
            case .medium: return 1.0
            case .small:  return 0.90
            }
        }()

        let successModifier: Double = {
            if madePlayoffs { return 1.15 }
            if previousSeasonWins >= 10 { return 1.08 }
            if previousSeasonWins >= 7 { return 1.0 }
            if previousSeasonWins >= 4 { return 0.95 }
            return 0.90
        }()

        let personaModifier = OwnerPersonaEngine.OwnerArchetype.from(owner).budgetMultiplier

        let total = Double(baseBudget) * marketModifier * successModifier * personaModifier
        return max(1_200, Int(total))  // Floor of $1.2M
    }

    /// Baseline medical budget in thousands derived from owner spending willingness.
    /// Low spender (20) → ~$2.0M, average (50) → ~$2.8M, big spender (95) → ~$3.9M.
    static func defaultMedicalBudget(spendingWillingness: Int) -> Int {
        1_500 + Int(Double(spendingWillingness) / 99.0 * 2_500.0)
    }
}
