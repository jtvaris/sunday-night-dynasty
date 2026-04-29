import Foundation

/// Computes a realistic, NFL-calibrated estimated market value for a player and
/// compares it against the player's actual salary.
///
/// All monetary values are expressed in thousands of dollars to stay consistent
/// with `Player.annualSalary` (e.g. `30_000` represents $30M / year).
///
/// The formula is intentionally simple but tuned so that:
///   - An 80 OVR QB at peak age lands near the $20M/year mark.
///   - Elite players (90+ OVR) scale into franchise-QB territory.
///   - Below-replacement players collapse toward the rookie-minimum floor.
enum PlayerValueEngine {

    // MARK: - Public API

    /// Estimated annual market value in thousands of dollars.
    /// E.g. `30_000` represents $30M.
    static func estimatedMarketValue(for player: Player) -> Int {
        let ovrFactor = ovrFactor(for: player.overall)
        let positionMultiplier = positionMultiplier(for: player.position)
        let ageMultiplier = ageMultiplier(for: player)

        // Reference baseline: an 80 OVR QB at peak age ~ $20M/year.
        let baseValue = 20_000.0
        let raw = baseValue * ovrFactor * positionMultiplier * ageMultiplier

        // Floor at $750K (roughly the league rookie minimum).
        return max(750, Int(raw.rounded()))
    }

    /// Compares the player's actual salary against the estimated market value.
    /// - bargain:    market value substantially exceeds salary (>1.3x)
    /// - fairValue:  salary is within ~25% of market value
    /// - overpaid:   salary substantially exceeds market value
    static func marketAssessment(for player: Player) -> MarketValueAssessment {
        let market = estimatedMarketValue(for: player)
        let salary = player.annualSalary

        // No salary on file (e.g. unsigned rookie) — treat as bargain so the UI
        // surfaces the upside, mirroring the previous PlayerDetailView behavior.
        guard salary > 0 else { return .bargain }

        let ratio = Double(market) / Double(salary)
        if ratio > 1.3 {
            return .bargain
        } else if ratio > 0.8 {
            return .fairValue
        } else {
            return .overpaid
        }
    }

    // MARK: - OVR Curve

    /// Exponential OVR curve: elite players are far above mid-tier players,
    /// while sub-75 OVR players drop quickly toward the floor.
    ///
    /// Anchor: at OVR 75, factor is `1.0`. At OVR 84, factor ≈ `1.69`.
    /// At OVR 95, factor ≈ `2.93`.
    private static func ovrFactor(for overall: Int) -> Double {
        let clamped = max(40, min(99, overall))
        return pow(Double(clamped) / 75.0, 4.5)
    }

    // MARK: - Position Multipliers

    /// Position multipliers vs the QB baseline (1.0). Approximates real-world
    /// NFL positional pay scarcity (QBs and edge rushers paid most, FB/K/P least).
    private static func positionMultiplier(for position: Position) -> Double {
        switch position {
        case .QB:                   return 1.00
        case .LT:                   return 0.55
        case .RT:                   return 0.45
        case .WR:                   return 0.60
        case .DE:                   return 0.60
        case .CB:                   return 0.55
        case .DT:                   return 0.45
        case .OLB:                  return 0.45
        case .TE:                   return 0.35
        case .MLB:                  return 0.35
        case .FS, .SS:              return 0.35
        case .LG, .C, .RG:          return 0.35
        case .RB:                   return 0.32
        case .FB:                   return 0.12
        case .K, .P:                return 0.12
        }
    }

    // MARK: - Age Multipliers

    /// Age multiplier relative to the position's peak window.
    /// Pre-peak players are slightly discounted (still developing).
    /// In-peak players hit full value. Post-peak declines accelerate.
    private static func ageMultiplier(for player: Player) -> Double {
        let peak = player.position.peakAgeRange
        let age = player.age

        if peak.contains(age) {
            return 1.00
        }

        if age < peak.lowerBound {
            return 0.85
        }

        // Past peak — value drops based on years over the upper bound.
        let yearsOver = age - peak.upperBound
        switch yearsOver {
        case 1...2: return 0.85
        case 3...4: return 0.65
        case 5...6: return 0.50
        default:    return 0.40
        }
    }
}
