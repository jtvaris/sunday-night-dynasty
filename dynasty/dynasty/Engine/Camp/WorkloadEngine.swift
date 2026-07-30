import Foundation
import SwiftData

// MARK: - WorkloadEngine

/// Tracks per-player camp workload, classifies status (underloaded/healthy/overloaded/burnedOut),
/// and converts that into a daily injury-risk multiplier. Driven daily by the camp scheduler;
/// stays consistent across OTAs, full-pads camp, and preseason snaps.
@MainActor
enum WorkloadEngine {

    // MARK: - Constants

    /// Cumulative-load thresholds (matched to design heuristic).
    private static let underloadedMax = 30
    private static let healthyMax = 80
    private static let overloadedMax = 130

    /// Loose cap so cumulativeLoad cannot grow unbounded across many weeks.
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
