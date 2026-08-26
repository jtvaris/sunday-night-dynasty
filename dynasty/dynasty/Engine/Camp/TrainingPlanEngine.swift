import Foundation
import SwiftData

// MARK: - TrainingPlanEngine

/// Applies a per-week `TrainingPlan` focus distribution (tactical/physical/technical)
/// to per-player attribute deltas. Each focus area has a soft +0.6 attribute-point per
/// week ceiling at 100% allocation, capped by player potential.
@MainActor
enum TrainingPlanEngine {

    /// Share of a training week's gains a `.burnedOut` player still absorbs.
    static let burnedOutGainFactor = 0.5

    /// The secondary attribute in each lane moves at a fraction of the lane's
    /// headline rate. Named rather than written inline because the camp screen
    /// prints the projected weekly gain per attribute, and a rate the UI copies
    /// out of here as a literal is a rate that drifts the first time this moves.
    static let decisionMakingWeight = 0.7
    static let durabilityWeight = 0.8

    /// Scheme-familiarity points bought per unit of tactical delta.
    static let schemeBumpPerDelta = 1.5

    /// The phases whose weekly tick actually runs a plan.
    ///
    /// `WeekAdvancer.applyCampWeeklyTick` is the only caller of `applyWeekly`,
    /// and the advance calls it from the OTAs, training-camp and preseason
    /// steps and nowhere else. A `TrainingPlan` row stamped with any other
    /// phase is therefore written to a key nothing ever fetches — which is
    /// exactly what the camp screen used to let the GM do during Roster Cuts,
    /// under a bar promising a "Roster Cuts development pass". The screen asks
    /// this before it offers to bank one.
    static let developmentPassPhases: Set<SeasonPhase> = [.otas, .trainingCamp, .preseason]

    static func runsDevelopmentPass(in phase: SeasonPhase) -> Bool {
        developmentPassPhases.contains(phase)
    }

    // MARK: - Public API

    /// Applies a training plan's focus distribution to per-player attribute deltas.
    /// Each focus area has a max +0.6 attr point per week (capped by player potential).
    static func applyWeekly(
        plan: TrainingPlan,
        roster: [Player],
        modelContext: ModelContext
    ) {
        guard !roster.isEmpty else { return }

        let baseTacticalDelta = tacticalDelta(pct: plan.tacticalPct)
        let basePhysicalDelta = physicalDelta(pct: plan.physicalPct)
        let baseTechnicalDelta = technicalDelta(pct: plan.technicalPct)

        for player in roster {
            // Skip injured / holding-out players entirely.
            guard !player.isInjured else { continue }

            // Burnout tax (plan §2.9.6): a player the staff has run into the
            // ground gets half the value out of the week. Until phase 2 the
            // `.burnedOut` status multiplied nothing at all — the camp workload
            // slider had no downside, so the optimal play was always max
            // intensity. This is the other half of its teeth (the first is
            // `MedicalEngine.workloadRiskMultiplier`, which the weekly sim and
            // the live engine both apply league-wide).
            //
            // Scope note (plan §2.9.6 leaves the choice to the implementer):
            // this half is inherently user-only, because a training PLAN is a
            // user feature — AI clubs have none to over-crank. The injury half
            // is what makes the workload state cost the other 31 clubs too, and
            // that is the half that runs league-wide.
            let loadFactor = player.workloadStatus == .burnedOut ? burnedOutGainFactor : 1.0
            let tDelta = baseTacticalDelta * loadFactor
            let pDelta = basePhysicalDelta * loadFactor
            let kDelta = baseTechnicalDelta * loadFactor

            // Per-player ceiling: scaled from truePotential (1-99); shared formula.
            let ceiling = PlayerDevelopmentEngine.developmentCeiling(for: player)

            // --- Tactical → mental.awareness, decisionMaking ---
            let tacticalRoll = rollPoints(delta: tDelta, ceiling: ceiling, current: player.mental.awareness)
            if tacticalRoll > 0 {
                player.mental.awareness = min(99, min(ceiling, player.mental.awareness + tacticalRoll))
            }
            let dmRoll = rollPoints(delta: tDelta * decisionMakingWeight, ceiling: ceiling, current: player.mental.decisionMaking)
            if dmRoll > 0 {
                player.mental.decisionMaking = min(99, min(ceiling, player.mental.decisionMaking + dmRoll))
            }

            // --- Physical → physical.stamina, durability, speed cap ---
            let staminaRoll = rollPoints(delta: pDelta, ceiling: ceiling, current: player.physical.stamina)
            if staminaRoll > 0 {
                player.physical.stamina = min(99, min(ceiling, player.physical.stamina + staminaRoll))
            }
            let durRoll = rollPoints(delta: pDelta * durabilityWeight, ceiling: ceiling, current: player.physical.durability)
            if durRoll > 0 {
                player.physical.durability = min(99, min(ceiling, player.physical.durability + durRoll))
            }

            // --- Technical → position-specific drills (apply via position attrs) ---
            applyTechnicalDelta(player: player, delta: kDelta, ceiling: ceiling)

            // --- Scheme knowledge bump from tactical work ---
            // Tactical focus also bumps the player's primary scheme (small).
            // Picks the top scheme already known so we don't pollute the dictionary.
            if let primary = player.schemeFamiliarity.max(by: { $0.value < $1.value })?.key {
                let bump = Int((tDelta * schemeBumpPerDelta).rounded())
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

    /// Scheme-familiarity points a full week of tactical work buys at `pct`,
    /// before the burnout tax.
    static func schemeBump(pct: Int) -> Int {
        Int((tacticalDelta(pct: pct) * schemeBumpPerDelta).rounded())
    }

    /// The lowest tactical share that buys any scheme familiarity at all.
    ///
    /// `schemeBump` rounds to a whole point, so the lane has a cliff rather
    /// than a slope: below this every tactical split buys exactly zero scheme
    /// knowledge and above it every split buys one. Derived by scan instead of
    /// written down, because the camp screen prints the number — a min-maxer
    /// was otherwise left to find the edge by experiment, and a literal in the
    /// UI would go stale the moment `schemeBumpPerDelta` moved.
    static var schemeBumpFloorPct: Int {
        (0...100).first { schemeBump(pct: $0) > 0 } ?? 101
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
    ///
    /// **This lane used to be able to take a rating away.** It rolled its bump
    /// with `current: 0`, so `rollPoints`' ceiling gate — which the tactical and
    /// physical lanes clear honestly, with the player's real value — was true
    /// for everybody, and then it wrote `min(cap, attr + bump)`. For a player
    /// whose position attribute already sat above `developmentCeiling`, that
    /// `min` is a SUBTRACTION: the drill session set him down to his ceiling.
    /// Specialists were the reliable victims, because overall weights position
    /// skill at half and a kicker's physical and mental averages drag his OVR
    /// (and with it his veteran potential, and with that his ceiling) far below
    /// his kicking numbers. It fired on the seeded 34/33/33 plan too, so a GM
    /// who never opened this screen still lost kick accuracy in camp.
    ///
    /// Both halves of the fix matter: pass the real current value so the gate
    /// works, and floor the write at where the player already is so no future
    /// ceiling formula can turn training into a demotion.
    private static func applyTechnicalDelta(player: Player, delta: Double, ceiling: Int) {
        let cap = min(99, ceiling)

        switch player.positionAttributes {
        case .quarterback(var qb):
            guard let value = trained(qb.accuracyShort, delta: delta, ceiling: ceiling, cap: cap) else { return }
            qb.accuracyShort = value
            player.positionAttributes = .quarterback(qb)
        case .wideReceiver(var wr):
            guard let value = trained(wr.routeRunning, delta: delta, ceiling: ceiling, cap: cap) else { return }
            wr.routeRunning = value
            player.positionAttributes = .wideReceiver(wr)
        case .runningBack(var rb):
            guard let value = trained(rb.vision, delta: delta, ceiling: ceiling, cap: cap) else { return }
            rb.vision = value
            player.positionAttributes = .runningBack(rb)
        case .tightEnd(var te):
            guard let value = trained(te.routeRunning, delta: delta, ceiling: ceiling, cap: cap) else { return }
            te.routeRunning = value
            player.positionAttributes = .tightEnd(te)
        case .offensiveLine(var ol):
            guard let value = trained(ol.passBlock, delta: delta, ceiling: ceiling, cap: cap) else { return }
            ol.passBlock = value
            player.positionAttributes = .offensiveLine(ol)
        case .defensiveLine(var dl):
            guard let value = trained(dl.passRush, delta: delta, ceiling: ceiling, cap: cap) else { return }
            dl.passRush = value
            player.positionAttributes = .defensiveLine(dl)
        case .linebacker(var lb):
            guard let value = trained(lb.tackling, delta: delta, ceiling: ceiling, cap: cap) else { return }
            lb.tackling = value
            player.positionAttributes = .linebacker(lb)
        case .defensiveBack(var db):
            guard let value = trained(db.manCoverage, delta: delta, ceiling: ceiling, cap: cap) else { return }
            db.manCoverage = value
            player.positionAttributes = .defensiveBack(db)
        case .kicking(var k):
            guard let value = trained(k.kickAccuracy, delta: delta, ceiling: ceiling, cap: cap) else { return }
            k.kickAccuracy = value
            player.positionAttributes = .kicking(k)
        }
    }

    /// One position attribute through one training week, or `nil` when the week
    /// moved it nowhere — the caller then skips the write-back entirely, so a
    /// player the drills did nothing for is not dirtied in the store.
    ///
    /// It can never return less than it was handed. `max(current,)` is belt and
    /// braces over `rollPoints`' gate rather than live arithmetic, and it is
    /// there because the version without it was the subtraction described above.
    private static func trained(_ current: Int, delta: Double, ceiling: Int, cap: Int) -> Int? {
        let bump = rollPoints(delta: delta, ceiling: ceiling, current: current)
        guard bump > 0 else { return nil }
        let raised = max(current, min(cap, current + bump))
        return raised == current ? nil : raised
    }
}
