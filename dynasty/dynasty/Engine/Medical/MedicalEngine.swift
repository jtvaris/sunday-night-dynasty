import Foundation

/// Handles injury risk calculations, recovery time, and fatigue management
/// based on medical staff (Doctor and Physio) quality.
enum MedicalEngine {

    /// Calculate injury risk for a play. Returns an injury type if one occurs, nil otherwise.
    ///
    /// Base risk is 0.5% per play, modified by:
    /// - Player fatigue (fatigue 80+ doubles risk)
    /// - Player durability (higher durability reduces risk)
    /// - Team Doctor quality (up to 30% risk reduction)
    static func injuryCheck(
        player: Player,
        playType: PlayType,
        doctor: Coach?,
        physio: Coach?
    ) -> InjuryType? {
        // Base risk: 0.5% per play
        var risk = 0.005

        // Fatigue increases risk (fatigue 80+ = 2x risk)
        risk *= 1.0 + Double(max(0, player.fatigue - 50)) / 50.0

        // Player durability reduces risk
        risk *= 1.0 - Double(player.physical.durability) / 200.0

        // Doctor prevention bonus (0-30% reduction)
        if let doc = doctor {
            risk *= 1.0 - Double(doc.playerDevelopment) / 330.0
        }

        // Roll
        guard Double.random(in: 0...1) < risk else { return nil }

        // Random injury type
        return InjuryType.allCases.randomElement()!
    }

    /// Calculate recovery weeks, modified by medical staff quality.
    ///
    /// - Physio reduces recovery by up to 25%
    /// - Doctor reduces recovery by up to 15%
    static func recoveryWeeks(
        injury: InjuryType,
        physio: Coach?,
        doctor: Coach?
    ) -> Int {
        let base = Int.random(in: injury.baseRecoveryWeeks)

        var modifier = 1.0

        // Physio reduces recovery by up to 25%
        if let physio = physio {
            modifier -= Double(physio.playerDevelopment) / 400.0
        }

        // Doctor reduces by up to 15%
        if let doc = doctor {
            modifier -= Double(doc.playerDevelopment) / 660.0
        }

        return max(1, Int(Double(base) * modifier))
    }

    /// Weekly fatigue recovery amount, improved by physio quality.
    ///
    /// Base recovery is 15 fatigue points per week, with physio adding up to 10 extra.
    static func weeklyFatigueRecovery(player: Player, physio: Coach?) -> Int {
        var recovery = 15  // Base: recover 15 fatigue per week

        if let physio = physio {
            recovery += Int(Double(physio.playerDevelopment) / 10.0)  // Up to +10 extra
        }

        return recovery
    }

    /// Apply an injury to a player, setting all relevant properties.
    static func applyInjury(
        player: Player,
        injuryType: InjuryType,
        doctor: Coach?,
        physio: Coach?
    ) {
        let weeks = recoveryWeeks(injury: injuryType, physio: physio, doctor: doctor)
        player.isInjured = true
        player.injuryType = injuryType
        player.injuryWeeksRemaining = weeks
        player.injuryWeeksOriginal = weeks
    }

    /// Process weekly recovery for an injured player. Returns true if the player has recovered.
    static func processWeeklyRecovery(player: Player) -> Bool {
        guard player.isInjured else { return false }

        player.injuryWeeksRemaining -= 1

        if player.injuryWeeksRemaining <= 0 {
            player.isInjured = false
            player.injuryType = nil
            player.injuryWeeksRemaining = 0
            player.injuryWeeksOriginal = 0
            return true
        }

        return false
    }
}
