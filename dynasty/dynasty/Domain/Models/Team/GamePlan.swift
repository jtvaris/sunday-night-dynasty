import Foundation

/// A plain Codable value type that stores coaching philosophy sliders for a single game or season.
/// All values are normalised to the [0.0, 1.0] range.
struct GamePlan: Codable {

    // MARK: - Settings

    /// How aggressively the offense plays (0 = conservative, 1 = aggressive).
    var offensiveAggression: Double

    /// How aggressively the defense plays (0 = conservative, 1 = aggressive).
    var defensiveAggression: Double

    /// Mix of run vs. pass (0 = all run, 1 = all pass).
    var runPassRatio: Double

    /// How often the defense sends extra rushers (0 = never, 1 = always).
    var blitzFrequency: Double

    /// Willingness to go for it on fourth down (0 = always punt, 1 = always go for it).
    var fourthDownAggressiveness: Double

    // MARK: - Presets

    /// All sliders at 0.5 — a neutral, balanced game plan.
    static var balanced: GamePlan {
        GamePlan(
            offensiveAggression: 0.5,
            defensiveAggression: 0.5,
            runPassRatio: 0.5,
            blitzFrequency: 0.5,
            fourthDownAggressiveness: 0.5
        )
    }

    /// Low-risk, ball-control style.
    static var conservative: GamePlan {
        GamePlan(
            offensiveAggression: 0.15,
            defensiveAggression: 0.2,
            runPassRatio: 0.25,
            blitzFrequency: 0.15,
            fourthDownAggressiveness: 0.1
        )
    }

    /// High-risk, high-reward style designed to swing the game.
    static var aggressive: GamePlan {
        GamePlan(
            offensiveAggression: 0.85,
            defensiveAggression: 0.8,
            runPassRatio: 0.75,
            blitzFrequency: 0.8,
            fourthDownAggressiveness: 0.9
        )
    }

    // MARK: - Helpers

    /// Human-readable summary of the game plan's overall character.
    var styleSummary: String {
        let avg = (offensiveAggression + defensiveAggression + blitzFrequency + fourthDownAggressiveness) / 4.0
        switch avg {
        case 0.0..<0.3:  return "Conservative"
        case 0.3..<0.55: return "Balanced"
        case 0.55..<0.75: return "Aggressive"
        default:         return "All-Out Attack"
        }
    }

    /// Human-readable label for the run-pass split.
    var runPassLabel: String {
        switch runPassRatio {
        case 0.0..<0.25: return "Heavy Run"
        case 0.25..<0.45: return "Run-First"
        case 0.45..<0.55: return "Balanced"
        case 0.55..<0.75: return "Pass-First"
        default:          return "Heavy Pass"
        }
    }
}
