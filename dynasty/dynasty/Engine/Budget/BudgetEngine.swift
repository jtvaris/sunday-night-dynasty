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

        let total = Double(baseBudget) * marketModifier * successModifier
        return max(12_000, Int(total))  // Floor of $12M
    }
}
