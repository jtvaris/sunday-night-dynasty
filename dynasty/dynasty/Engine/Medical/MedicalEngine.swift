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
    /// - R28: an active rush-back window multiplies risk (head trainer dampens it)
    ///
    /// R28 parity note: baseline incidence is unchanged — the only rate change
    /// is the opt-in rush-back multiplier, and injury-type selection is now
    /// weighted toward body parts the player has hurt before (recurrence),
    /// which redistributes types without changing how often injuries happen.
    static func injuryCheck(
        player: Player,
        playType: PlayType,
        doctor: Coach?,
        physio: Coach?,
        trainer: Coach? = nil
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

        // R28: rushing back early carries elevated re-injury risk for a
        // couple of weeks. A good head trainer manages the ramp-up.
        if player.rushBackWeeksRemaining > 0 {
            risk *= rushBackRiskMultiplier(trainer: trainer)
        }

        // Roll
        guard Double.random(in: 0...1) < risk else { return nil }

        // R28: weighted injury type — previously injured body parts are more
        // likely to flare up again (recurrence), same total incidence.
        return weightedInjuryType(for: player)
    }

    /// R28: re-injury risk multiplier during the post-rush-back window.
    /// Base ×1.5; a top head trainer brings it down to ~×1.1.
    static func rushBackRiskMultiplier(trainer: Coach?) -> Double {
        let skill = Double(trainer?.playerDevelopment ?? 0)
        return max(1.1, 1.5 - skill / 250.0)
    }

    /// R28: picks an injury type weighted by the player's history — each prior
    /// occurrence of a type adds +60% weight (capped at 2.5× per type), so
    /// recurring hamstrings/knees become that player's signature problem.
    private static func weightedInjuryType(for player: Player) -> InjuryType {
        let history = player.injuryHistory
        guard !history.isEmpty else { return InjuryType.allCases.randomElement()! }

        let weights: [(InjuryType, Double)] = InjuryType.allCases.map { type in
            let prior = history.filter { $0.injuryTypeRaw == type.rawValue }.count
            return (type, min(2.5, 1.0 + 0.6 * Double(prior)))
        }
        let total = weights.reduce(0) { $0 + $1.1 }
        var roll = Double.random(in: 0..<total)
        for (type, weight) in weights {
            roll -= weight
            if roll < 0 { return type }
        }
        return weights.last!.0
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
    ///
    /// R28: also appends a permanent `InjuryRecord` to the player's history
    /// (season/week 0 = unknown context, e.g. live games), starts rehab
    /// tracking, and — rarely — erodes durability when the same body part
    /// keeps breaking down (max -2 per injury, recurrence only).
    static func applyInjury(
        player: Player,
        injuryType: InjuryType,
        doctor: Coach?,
        physio: Coach?,
        season: Int = 0,
        week: Int = 0
    ) {
        let weeks = recoveryWeeks(injury: injuryType, physio: physio, doctor: doctor)
        let priorSameType = player.priorInjuryCount(of: injuryType)

        player.isInjured = true
        player.injuryType = injuryType
        player.injuryWeeksRemaining = weeks
        player.injuryWeeksOriginal = weeks
        player.rehabStatus = .onTrack
        // A fresh injury supersedes any rush-back exposure window.
        player.rushBackWeeksRemaining = 0

        // Permanent history entry.
        var history = player.injuryHistory
        history.append(InjuryRecord(
            injuryTypeRaw: injuryType.rawValue,
            weeksOut: weeks,
            season: season,
            week: week
        ))
        player.injuryHistory = history

        // R28: recurring injuries chip away at durability — deliberately rare
        // and small so the league doesn't decay (25% chance, -1; -2 only for
        // severe repeats, ~6% of recurrences).
        if priorSameType >= 1 {
            let roll = Double.random(in: 0...1)
            if roll < 0.25 {
                let loss = (injuryType.severity >= 4 && roll < 0.06) ? 2 : 1
                player.physical.durability = max(1, player.physical.durability - loss)
            }
        }
    }

    /// Process weekly recovery for an injured player. Returns true if the player has recovered.
    ///
    /// Legacy deterministic path (1 week per week, no variance). Prefer
    /// `processWeeklyRehab(player:trainer:)` which adds rehab variance.
    static func processWeeklyRecovery(player: Player) -> Bool {
        guard player.isInjured else { return false }

        player.injuryWeeksRemaining -= 1

        if player.injuryWeeksRemaining <= 0 {
            clearInjury(player: player)
            return true
        }

        return false
    }

    // MARK: - R28: Rehab Variance

    /// The result of one week of rehab.
    struct RehabResult {
        let status: RehabStatus
        let recovered: Bool
    }

    /// Process one week of rehab with variance. The weekly roll lands on
    /// ahead-of-schedule (-2 weeks), on-track (-1 week) or setback (no
    /// progress, sometimes +1 week back). Head trainer skill shifts the odds:
    ///
    /// - No trainer: 10% ahead / 80% on track / 10% setback → expected
    ///   progress ≈ 1.0 week/week, i.e. same average as the legacy path.
    /// - Elite trainer (99): ~20% ahead / ~4% setback → faster average rehab.
    ///
    /// Returns the rolled status and whether the player fully recovered.
    static func processWeeklyRehab(player: Player, trainer: Coach?) -> RehabResult {
        guard player.isInjured else { return RehabResult(status: .onTrack, recovered: false) }

        let skill = Double(trainer?.playerDevelopment ?? 0)
        let aheadChance = 0.10 + skill * 0.001      // 10% … ~20%
        let setbackChance = max(0.04, 0.10 - skill * 0.0006) // 10% … ~4%

        let roll = Double.random(in: 0...1)
        let status: RehabStatus

        if roll < aheadChance {
            status = .aheadOfSchedule
            player.injuryWeeksRemaining -= 2
        } else if roll > 1.0 - setbackChance {
            status = .setback
            // Most setbacks just stall progress; ~30% lose a week outright,
            // never beyond the original prognosis.
            if Double.random(in: 0...1) < 0.30,
               player.injuryWeeksRemaining < player.injuryWeeksOriginal {
                player.injuryWeeksRemaining += 1
            }
        } else {
            status = .onTrack
            player.injuryWeeksRemaining -= 1
        }

        player.rehabStatus = status

        if player.injuryWeeksRemaining <= 0 {
            clearInjury(player: player)
            return RehabResult(status: status, recovered: true)
        }
        return RehabResult(status: status, recovered: false)
    }

    /// R28: player returns one week early ("rush back"). Clears the injury
    /// immediately but opens a 2-week elevated re-injury window (see
    /// `injuryCheck`) and adds a short-term conditioning hit via fatigue.
    static func rushBack(player: Player) {
        guard player.isInjured else { return }
        clearInjury(player: player)
        player.rushBackWeeksRemaining = 2
        player.fatigue = min(100, player.fatigue + 15)
    }

    /// Clears all current-injury state (history remains).
    private static func clearInjury(player: Player) {
        player.isInjured = false
        player.injuryType = nil
        player.injuryWeeksRemaining = 0
        player.injuryWeeksOriginal = 0
        player.rehabStatusRaw = nil
    }
}
