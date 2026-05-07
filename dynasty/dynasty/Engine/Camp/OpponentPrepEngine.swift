import Foundation

// MARK: - OpponentPrepEngine

/// Translates a per-week game-prep slider (general vs. opponent-specific) into
/// in-game performance bonuses and a long-term attribute drift penalty.
/// 100% opponent prep → +20% audibles, +15% defensive read this game.
/// 3+ consecutive 100% opponent weeks → -1 OVR drift across the unit.
enum OpponentPrepEngine {

    // MARK: - Public API

    /// Returns this-game performance bonus tuple for the chosen opponent-prep ratio.
    /// `audibleBoost` and `defensiveReadBoost` are 0..1 multiplicative bonuses.
    static func gameBoost(prep: OpponentPrepWeek) -> (audibleBoost: Double, defensiveReadBoost: Double) {
        let opponentRatio = max(0.0, min(1.0, Double(prep.opponentPct) / 100.0))
        // 100% opponent => +20% audibles, +15% defensive read. Linear interpolation.
        let audibleBoost = 0.20 * opponentRatio
        let defReadBoost = 0.15 * opponentRatio
        return (audibleBoost: audibleBoost, defensiveReadBoost: defReadBoost)
    }

    /// Returns cumulative attribute drift penalty for over-focusing on opponent prep.
    /// 3+ consecutive 100% opponent weeks → -1 OVR drift across the unit.
    /// Penalty grows linearly past week 3 to a hard cap of -3 OVR.
    static func driftPenalty(consecutiveOpponentWeeks: Int) -> Int {
        guard consecutiveOpponentWeeks >= 3 else { return 0 }
        let extra = consecutiveOpponentWeeks - 2 // weeks past the safe two
        return -min(3, extra)
    }
}
