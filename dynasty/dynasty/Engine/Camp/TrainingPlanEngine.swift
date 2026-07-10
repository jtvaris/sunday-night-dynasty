import Foundation
import SwiftData

// MARK: - TrainingPlanEngine

/// Applies a per-week `TrainingPlan` focus distribution (tactical/physical/technical)
/// to per-player attribute deltas. Each focus area has a soft +0.6 attribute-point per
/// week ceiling at 100% allocation, capped by player potential.
@MainActor
enum TrainingPlanEngine {

    // MARK: - Public API

    /// Applies a training plan's focus distribution to per-player attribute deltas.
    /// Each focus area has a max +0.6 attr point per week (capped by player potential).
    static func applyWeekly(
        plan: TrainingPlan,
        roster: [Player],
        modelContext: ModelContext
    ) {
        guard !roster.isEmpty else { return }

        let tDelta = tacticalDelta(pct: plan.tacticalPct)
        let pDelta = physicalDelta(pct: plan.physicalPct)
        let kDelta = technicalDelta(pct: plan.technicalPct)

        for player in roster {
            // Skip injured / holding-out players entirely.
            guard !player.isInjured else { continue }

            // Per-player ceiling: scaled from truePotential (1-99); shared formula.
            let ceiling = PlayerDevelopmentEngine.developmentCeiling(for: player)

            // --- Tactical → mental.awareness, decisionMaking ---
            let tacticalRoll = rollPoints(delta: tDelta, ceiling: ceiling, current: player.mental.awareness)
            if tacticalRoll > 0 {
                player.mental.awareness = min(99, min(ceiling, player.mental.awareness + tacticalRoll))
            }
            let dmRoll = rollPoints(delta: tDelta * 0.7, ceiling: ceiling, current: player.mental.decisionMaking)
            if dmRoll > 0 {
                player.mental.decisionMaking = min(99, min(ceiling, player.mental.decisionMaking + dmRoll))
            }

            // --- Physical → physical.stamina, durability, speed cap ---
            let staminaRoll = rollPoints(delta: pDelta, ceiling: ceiling, current: player.physical.stamina)
            if staminaRoll > 0 {
                player.physical.stamina = min(99, min(ceiling, player.physical.stamina + staminaRoll))
            }
            let durRoll = rollPoints(delta: pDelta * 0.8, ceiling: ceiling, current: player.physical.durability)
            if durRoll > 0 {
                player.physical.durability = min(99, min(ceiling, player.physical.durability + durRoll))
            }

            // --- Technical → position-specific drills (apply via position attrs) ---
            applyTechnicalDelta(player: player, delta: kDelta, ceiling: ceiling)

            // --- Scheme knowledge bump from tactical work ---
            // Tactical focus also bumps the player's primary scheme (small).
            // Picks the top scheme already known so we don't pollute the dictionary.
            if let primary = player.schemeFamiliarity.max(by: { $0.value < $1.value })?.key {
                let bump = Int((tDelta * 1.5).rounded())
                if bump > 0 {
                    let cur = player.schemeFamiliarity[primary] ?? 0
                    player.schemeFamiliarity[primary] = min(100, cur + bump)
                }
            }
        }
    }

    /// Returns the rough development bucket for a given focus pct (0..100 → 0..0.6).
    static func tacticalDelta(pct: Int) -> Double {
        let clamped = max(0, min(100, pct))
        return Double(clamped) / 100.0 * 0.6
    }

    /// Returns the rough development bucket for a given focus pct (0..100 → 0..0.6).
    static func physicalDelta(pct: Int) -> Double {
        let clamped = max(0, min(100, pct))
        return Double(clamped) / 100.0 * 0.6
    }

    /// Returns the rough development bucket for a given focus pct (0..100 → 0..0.6).
    static func technicalDelta(pct: Int) -> Double {
        let clamped = max(0, min(100, pct))
        return Double(clamped) / 100.0 * 0.6
    }

    // MARK: - Private Helpers

    /// Probabilistic rounding of a fractional delta to an integer attribute bump.
    /// A delta of 0.6 over a week rolls a 60% chance of +1 each call.
    private static func rollPoints(delta: Double, ceiling: Int, current: Int) -> Int {
        guard current < ceiling, delta > 0 else { return 0 }
        let whole = Int(delta)
        let frac = delta - Double(whole)
        let extra = Double.random(in: 0.0..<1.0) < frac ? 1 : 0
        return whole + extra
    }

    /// Distributes technical-focus points across position-specific attributes.
    /// Falls through the `PositionAttributes` enum, bumping a single relevant skill.
    private static func applyTechnicalDelta(player: Player, delta: Double, ceiling: Int) {
        let bump = rollPoints(delta: delta, ceiling: ceiling, current: 0)
        guard bump > 0 else { return }
        let cap = min(99, ceiling)

        switch player.positionAttributes {
        case .quarterback(var qb):
            qb.accuracyShort = min(cap, qb.accuracyShort + bump)
            player.positionAttributes = .quarterback(qb)
        case .wideReceiver(var wr):
            wr.routeRunning = min(cap, wr.routeRunning + bump)
            player.positionAttributes = .wideReceiver(wr)
        case .runningBack(var rb):
            rb.vision = min(cap, rb.vision + bump)
            player.positionAttributes = .runningBack(rb)
        case .tightEnd(var te):
            te.routeRunning = min(cap, te.routeRunning + bump)
            player.positionAttributes = .tightEnd(te)
        case .offensiveLine(var ol):
            ol.passBlock = min(cap, ol.passBlock + bump)
            player.positionAttributes = .offensiveLine(ol)
        case .defensiveLine(var dl):
            dl.passRush = min(cap, dl.passRush + bump)
            player.positionAttributes = .defensiveLine(dl)
        case .linebacker(var lb):
            lb.tackling = min(cap, lb.tackling + bump)
            player.positionAttributes = .linebacker(lb)
        case .defensiveBack(var db):
            db.manCoverage = min(cap, db.manCoverage + bump)
            player.positionAttributes = .defensiveBack(db)
        case .kicking(var k):
            k.kickAccuracy = min(cap, k.kickAccuracy + bump)
            player.positionAttributes = .kicking(k)
        }
    }
}
