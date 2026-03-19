import Foundation

// MARK: - VersatilityDevelopmentEngine

/// Stateless engine responsible for developing player position versatility
/// and scheme familiarity over time. Works alongside PlayerDevelopmentEngine.
enum VersatilityDevelopmentEngine {

    // MARK: - Position Training

    /// Develop a player's alternate position familiarity.
    /// Returns the familiarity points gained this cycle.
    ///
    /// - Parameters:
    ///   - player: The player training at the new position.
    ///   - targetPosition: The alternate position being trained.
    ///   - positionCoach: The position coach for the target position group (if any).
    ///   - practiceIntensity: 0.5 during season, 1.0 during offseason.
    /// - Returns: Points gained (0+).
    static func trainPosition(
        player: Player,
        targetPosition: Position,
        positionCoach: Coach?,
        practiceIntensity: Double = 1.0
    ) -> Int {
        // Base learning rate: 1-3 points per cycle
        var learningRate: Double = 2.0

        // Player coachability affects learning speed
        learningRate *= Double(player.mental.coachability) / 70.0

        // Coach teaching ability (playerDevelopment attribute)
        if let coach = positionCoach {
            learningRate *= Double(coach.playerDevelopment) / 60.0
        }

        // VersatilityEngine ceiling limits how far this player can go
        let ceiling = versatilityCeiling(player: player, at: targetPosition)
        let current = player.familiarity(at: targetPosition)

        // Diminishing returns as approaching ceiling
        let headroom = Double(ceiling - current) / Double(max(1, ceiling))
        learningRate *= max(0.1, headroom)

        // Practice intensity (season vs offseason)
        learningRate *= practiceIntensity

        // Age penalty (older players learn slower)
        if player.age > 30 { learningRate *= 0.7 }
        else if player.age > 28 { learningRate *= 0.85 }

        return max(0, Int(learningRate.rounded()))
    }

    /// The maximum familiarity a player can reach at a given position,
    /// based on their physical attributes and VersatilityEngine rating.
    static func versatilityCeiling(player: Player, at position: Position) -> Int {
        let rating = VersatilityEngine.rate(player: player, at: position)
        switch rating {
        case .natural:      return 100
        case .accomplished: return 85
        case .competent:    return 65
        case .unconvincing: return 40
        case .unqualified:  return 15
        }
    }

    // MARK: - Scheme Learning

    /// Develop a player's scheme familiarity.
    /// Returns the familiarity points gained this cycle.
    ///
    /// - Parameters:
    ///   - player: The player learning the scheme.
    ///   - scheme: The scheme rawValue being learned (e.g., "WestCoast").
    ///   - coordinator: The coordinator teaching this scheme (if any).
    ///   - practiceIntensity: 0.5 during season, 1.0 during offseason.
    /// - Returns: Points gained (0+).
    static func learnScheme(
        player: Player,
        scheme: String,
        coordinator: Coach?,
        practiceIntensity: Double = 1.0
    ) -> Int {
        var learningRate: Double = 1.5

        // Player coachability
        learningRate *= Double(player.mental.coachability) / 70.0

        // Coach's expertise IN THIS SPECIFIC SCHEME drives teaching quality
        if let coord = coordinator {
            let expertise = Double(coord.expertise(for: scheme))
            learningRate *= expertise / 60.0

            // Coach's playerDevelopment = general teaching ability
            learningRate *= Double(coord.playerDevelopment) / 70.0
        }

        // Diminishing returns near 100
        let current = Double(player.schemeFam(for: scheme))
        let headroom = (100.0 - current) / 100.0
        learningRate *= max(0.1, headroom)

        // Practice intensity
        learningRate *= practiceIntensity

        // Player awareness helps scheme comprehension
        learningRate *= Double(player.mental.awareness) / 70.0

        return max(0, Int(learningRate.rounded()))
    }

    // MARK: - Game Performance Impact

    /// Returns a 0.65-1.0 modifier for how well a player performs at a
    /// non-primary position during a game.
    ///
    /// - 100 familiarity = 1.0 (full performance)
    /// - 50 familiarity  = 0.825 (17.5% penalty)
    /// - 0 familiarity   = 0.65 (35% penalty)
    static func positionPerformanceModifier(player: Player, playingAt position: Position) -> Double {
        let familiarity = Double(player.familiarity(at: position))
        return 0.65 + (familiarity / 100.0) * 0.35
    }

    /// Returns a 0.70-1.0 modifier for how well a player performs in
    /// a specific scheme during a game.
    ///
    /// - 100 familiarity = 1.0
    /// - 50 familiarity  = 0.85
    /// - 0 familiarity   = 0.70
    static func schemePerformanceModifier(player: Player, scheme: String) -> Double {
        let familiarity = Double(player.schemeFam(for: scheme))
        return 0.70 + (familiarity / 100.0) * 0.30
    }
}
