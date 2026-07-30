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

    // MARK: - Scheme Change Consequences (plan §2.9.2)

    /// Extra practice intensity during a scheme install year. The staff spends
    /// the whole season teaching a system nobody in the building has run, so
    /// the reps that DO happen teach more (`DEVELOPMENT_NFL_REFERENCE.md` §5:
    /// offenses under a new OC underperform in year 1 and recover in year 2 —
    /// the tax is the lost familiarity, this is the catch-up).
    static let schemeInstallIntensityBonus = 1.25

    /// Points a scheme nobody on the staff runs any more loses each offseason.
    static let unusedSchemeDecayPerOffseason = 4

    /// Floor the decay stops at. A player never forgets a system completely —
    /// he keeps a working knowledge of it, which is what makes a reunion with an
    /// old coordinator worth something.
    ///
    /// The number is `PlaySimulator`'s **blown-assignment pivot** (`famBustPivot`
    /// = 55), and that coupling is the whole point. Below that pivot every snap
    /// rolls a bust chance and the completion channel is docked; at or above it
    /// a squad is parity-neutral. A floor of 35 — 20 points UNDER the pivot —
    /// meant that a club which parked a system for four or five offseasons and
    /// then re-hired the coordinator who ran it found the room *in the busting
    /// regime*, which is the opposite of the reunion this floor exists to
    /// reward. `learnScheme` then needs the better part of a decade to climb
    /// back out (in-season gains are ~1 point/season by the time familiarity
    /// reaches the high 40s). Rusty, not broken.
    static let unusedSchemeFloor = 55

    /// Ages out the schemes this player's team no longer runs (plan §2.9.2).
    ///
    /// Without this, `schemeFamiliarity` was a monotone ratchet: a journeyman
    /// accumulated 90+ in every system he ever touched, so scheme fit stopped
    /// discriminating between clubs entirely. Only values ABOVE the floor
    /// decay — the floor is never used to lift a low number.
    ///
    /// - Parameters:
    ///   - player: The player whose dictionary is aged (mutated in place).
    ///   - activeSchemes: The `rawValue`s his current staff actually runs.
    static func decayUnusedSchemes(player: Player, activeSchemes: Set<String>) {
        var familiarity = player.schemeFamiliarity
        var changed = false
        for (scheme, value) in familiarity where !activeSchemes.contains(scheme) {
            let decayed = max(unusedSchemeFloor, value - unusedSchemeDecayPerOffseason)
            if decayed != value {
                familiarity[scheme] = decayed
                changed = true
            }
        }
        if changed { player.schemeFamiliarity = familiarity }
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

        // How fast the player absorbs a playbook. This used to read
        // `awareness / 70`, but awareness is the in-sim game-IQ every
        // PlaySimulator formula depends on — `learning` is now the canonical
        // "picks up the install" stat (plan §3.3), leaving awareness pure.
        // The divisor is chosen so the change is level-neutral: league-typical
        // awareness ~69.5 gave 0.993, league-typical learning ~69.5 gives 1.069
        // (+7.7 %, inside the ±10 % class-average guard).
        learningRate *= Double(player.learning) / 65.0

        // Probabilistic rounding, not truncation-by-rounding. `Int(rounded())`
        // silently returns 0 for every fractional gain below 0.5, and the
        // in-season call (`practiceIntensity` 0.5) drops under that threshold
        // once familiarity passes the high 40s — so a squad learning a new
        // playbook STALLED at ~47, below `PlaySimulator`'s bust pivot of 55,
        // and could only crawl out at +1 per offseason camp. Rolling the
        // fraction keeps the designed per-season expectation while letting the
        // in-season reps keep counting. Mirrors
        // `PlayerDevelopmentEngine.applyGameExperience`.
        return max(0, PlayerDevelopmentEngine.probabilisticPoints(learningRate))
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

    /// SimPlayer overload used by the game-simulation hot path, where reading
    /// the SwiftData @Model per play is too slow.
    static func schemePerformanceModifier(player: SimPlayer, scheme: String) -> Double {
        let familiarity = Double(player.schemeFam(for: scheme))
        return 0.70 + (familiarity / 100.0) * 0.30
    }
}
