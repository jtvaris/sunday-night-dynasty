import Foundation
import SwiftData

// MARK: - WorkloadEngine

/// Tracks per-player camp workload, classifies status (underloaded/healthy/overloaded/burnedOut),
/// and converts that into a daily injury-risk multiplier. Driven daily by the camp scheduler;
/// stays consistent across OTAs, full-pads camp, and preseason snaps.
@MainActor
enum WorkloadEngine {

    // MARK: - Constants

    /// Cumulative-load bands, MEASURED against what the camp scheduler can
    /// actually emit rather than against the 0…200 the cap implies.
    ///
    /// The camp cycle is exactly 21 days. `WeekAdvancer.advanceOffseasonPhase`
    /// runs `applyCampWeeklyTick` once per camp phase and then advances the
    /// phase unconditionally, so OTAs / trainingCamp / preseason are one 7-day
    /// tick each, opening from the zero `resetCampLoad` writes at OTAs.
    ///
    /// A day's net is `round(intensity · 18 · staminaFactor) − round(recoveryRate · 10)`
    /// — two independently rounded integers — so reachable loads form a lattice
    /// of step 7 and the recovery term collapses to whole points.
    /// `computeRecoveryRate` documents a 0.40…0.75 band, but `playerDevelopment`
    /// is one of `CoachRole.focusAttributes` for both `.strengthCoach` and
    /// `.physio`, so `CoachingEngine` always draws it from the GOOD range
    /// (60…88 across budget/standard/premium clubs). That leaves exactly two
    /// recovery deltas in the shipped game — 6 (every AI club's hard-coded
    /// 0.55, the no-coach fallback, and a 60–70 coach) and 7 (a 71–88 coach) —
    /// and therefore two end-of-cycle lattices:
    ///
    ///     recovery delta 6 → {21, 28, 35, 42, 49, 56, 63, 70}  median 42, p90 56
    ///     recovery delta 7 → { 7, 14, 21, 28, 35, 42, 49}      median 28
    ///
    /// The shipped table put `.overloaded` at 80 and `.burnedOut` at 130 — 10
    /// and 60 points ABOVE the global ceiling of 70. Both states had
    /// probability zero for all 32 clubs, which made four consumers dead code:
    /// `WorkloadStatus.injuryMultiplier`'s 1.6 and 2.5 rungs,
    /// `TrainingPlanEngine.burnedOutGainFactor`, `CareerDashboardView`'s
    /// `.overloaded || .burnedOut` camp warning, and `TrainingPlanView`'s own
    /// "a player who reads Burnt takes only half of the week's gains".
    /// `MedicalEngine.workloadRiskMultiplier` returned exactly 1.0 for every
    /// player in the league, always — i.e. plan §2.9.6's "workload is cosmetic"
    /// defect was still cosmetic after the fix that was meant to end it.
    ///
    /// The two upper bands are therefore anchored to the lattice they have to
    /// live on:
    ///
    ///  * **56** is the measured p90 of a default-intensity club's end-of-cycle
    ///    load, so `.overloaded` is the top decile of a normally-run camp while
    ///    the median man (42) stays `.healthy` — which is exactly what
    ///    `MedicalEngine.workloadRiskMultiplier`'s comment says the league-wide
    ///    tick has to leave a default-intensity roster in.
    ///  * **63** is the second-highest rung of that same lattice, so
    ///    `.burnedOut` means a man carrying one of the two heaviest camps the
    ///    scheduler can deliver: ~0.4 % of a roster, roughly one player every
    ///    other club per camp.
    ///
    /// `underloadedMax` is deliberately unchanged: it is the one threshold that
    /// already sat inside the reachable range (it separates 21 and 28 from the
    /// rest of the camp week).
    private static let underloadedMax = 30
    private static let healthyMax = 56
    private static let overloadedMax = 63

    /// The load at which a player reads `.burnedOut`, i.e. the top of the
    /// meaningful range. Exposed because the camp UI's load meter uses it as
    /// its full scale — a full bar and a "Burnt" pill have to be the same
    /// event, and a bar that divides by a number the engine cannot emit reads
    /// as headroom the player does not have.
    static let burnoutFloor = overloadedMax

    /// Runaway guard only. Since plan §2.9.6 added `resetCampLoad` at OTAs the
    /// counter cannot ratchet across seasons, and the 21-day cycle tops out at
    /// 70 (88 if the user stacks every voluntary off-day practice, which adds
    /// `injuryRiskBoost * 2` per attendee), so this never engages. Left at 200
    /// because `VoluntaryWorkoutEngine` clamps to the same literal; the two
    /// have to move together, and neither is reachable.
    private static let absoluteCap = 200

    // MARK: - Public API

    /// Updates a player's `cumulativeLoad` given today's training intensity (0..1)
    /// and the strength coach's recovery rate (0..1).
    /// Persists a `WorkloadEvent` row for the day.
    ///
    /// - Parameters:
    ///   - seasonYear: the GAME's season (`Career.currentSeason`). Plan §2.9.6:
    ///     this used to stamp `Calendar.current` — the player's wall clock — so
    ///     every row in a 20-season dynasty carried 2026 (or whatever year the
    ///     save happened to be played in) and the audit trail could never be
    ///     filtered by in-game season.
    ///   - weekNumber: the GAME week (`Career.currentWeek`) this camp day sits in.
    ///   - dayOfWeek: 0-6 within the camp week, from the caller's day loop
    ///     (the wall-clock weekday it replaced had no relationship to the camp
    ///     day being simulated).
    static func tickDay(
        player: Player,
        intensity: Double,
        recoveryRate: Double,
        seasonYear: Int,
        weekNumber: Int,
        dayOfWeek: Int,
        modelContext: ModelContext
    ) {
        let delta = applyDailyLoad(player: player, intensity: intensity, recoveryRate: recoveryRate)

        let event = WorkloadEvent(
            playerID: player.id,
            seasonYear: seasonYear,
            dayOfWeek: max(0, min(6, dayOfWeek)),
            loadDelta: delta.load,
            recoveryDelta: delta.recovery
        )
        // Default-value property → set after construction, never through the
        // initializer (the project's @Model migration convention).
        event.weekNumber = weekNumber
        event.careerID = player.careerID
        modelContext.insert(event)
    }

    /// Seven days of load in one call, WITHOUT the per-day `WorkloadEvent` rows.
    ///
    /// Plan §2.9.6 asks for league-wide workload statuses so the injury
    /// multiplier and the burnout training tax mean something for all 32 clubs,
    /// and leaves the persistence choice to the implementer. MEASUREMENT (row
    /// arithmetic, the only cost that scales): the per-day audit trail is
    /// 53 players × 7 days = 371 inserted rows per team per camp week. Ticking
    /// the other 31 clubs the same way is +11 501 rows per camp week and
    /// ~34 500 per season — permanent store growth, and nothing ever prunes
    /// them. The arithmetic itself is ~11.5 k trivial float ops, i.e. free.
    ///
    /// To be exact about what those rows are worth today: **no screen reads
    /// them.** `WorkloadEvent` has zero fetch sites in the app — the camp
    /// dashboard (`WorkloadDashboard`) renders the live `cumulativeLoad` /
    /// `workloadStatus` fields off the `Player` row, not the per-day log. The
    /// rows are a season/week-stamped audit trail kept for the user's own club
    /// (plan §2.9.6 fixed their stamping); until something surfaces them, that
    /// only strengthens the case for not writing 34 500 of them a season for
    /// the 31 clubs the user never inspects.
    ///
    /// So: AI teams get the state (cheap, and genuinely consumed — the
    /// `MedicalEngine` injury multiplier and the `TrainingPlanEngine` burnout
    /// tax both read `workloadStatus`), the user's team additionally keeps the
    /// per-day trail.
    static func tickWeek(
        player: Player,
        intensity: Double,
        recoveryRate: Double
    ) {
        for _ in 0..<7 {
            _ = applyDailyLoad(player: player, intensity: intensity, recoveryRate: recoveryRate)
        }
    }

    /// Clears a player's accumulated camp load. Called when a new camp cycle
    /// opens (plan §2.9.6): `cumulativeLoad` is a per-camp counter, but nothing
    /// ever reset it, so it ratcheted ~+40 points a season across the OTAs →
    /// camp → preseason ticks and every roster in the league would have aged
    /// into `.burnedOut` within a few seasons. Harmless while the status
    /// multiplied nothing; a league-wide injury and training tax once it does.
    static func resetCampLoad(player: Player) {
        player.cumulativeLoad = 0
        player.workloadStatus = classify(load: 0)
    }

    /// Shared per-day load math. Returns the two deltas so `tickDay` can log them.
    @discardableResult
    private static func applyDailyLoad(
        player: Player,
        intensity: Double,
        recoveryRate: Double
    ) -> (load: Int, recovery: Int) {
        let clampedIntensity = max(0.0, min(1.0, intensity))
        let clampedRecovery = max(0.0, min(1.0, recoveryRate))

        // Load delta scales 0..18 per day at full intensity. Stamina partly absorbs load.
        let staminaFactor = 1.0 - (Double(player.physical.stamina) / 99.0) * 0.4
        let loadDelta = Int((clampedIntensity * 18.0 * staminaFactor).rounded())

        // Recovery delta scales 0..10 per day. Trainer skill amplifies recovery.
        let recoveryDelta = Int((clampedRecovery * 10.0).rounded())

        let net = loadDelta - recoveryDelta
        let newLoad = max(0, min(absoluteCap, player.cumulativeLoad + net))
        player.cumulativeLoad = newLoad
        player.workloadStatus = classify(load: newLoad)

        return (loadDelta, recoveryDelta)
    }

    /// Classifies workload status from `cumulativeLoad` thresholds.
    static func classify(load: Int) -> WorkloadStatus {
        switch load {
        case ..<underloadedMax:                 return .underloaded
        case underloadedMax..<healthyMax:       return .healthy
        case healthyMax..<overloadedMax:        return .overloaded
        default:                                 return .burnedOut
        }
    }

    /// Returns daily injury risk percentage (0..100) for a player given their workload
    /// status + base risk (0..1). Stacks the status multiplier on top of the player's
    /// inherent durability factor.
    static func injuryRiskPct(player: Player, baseRisk: Double) -> Double {
        let status = player.workloadStatus
        let durabilityFactor = (99.0 - Double(player.physical.durability)) / 99.0 * 0.4 + 1.0
        let combined = baseRisk * status.injuryMultiplier * durabilityFactor
        return min(100.0, combined * 100.0)
    }
}
