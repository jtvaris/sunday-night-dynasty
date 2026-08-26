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
    /// **Two defects were fixed here, in that order, and the second forced the
    /// numbers below to be re-measured.**
    ///
    /// 1. The shipped table put `.overloaded` at 80 and `.burnedOut` at 130 —
    ///    above the global ceiling the scheduler could reach at all. Both
    ///    states had probability zero for all 32 clubs, which made four
    ///    consumers dead code: `WorkloadStatus.injuryMultiplier`'s 1.6 and 2.5
    ///    rungs, `TrainingPlanEngine.burnedOutGainFactor`,
    ///    `CareerDashboardView`'s camp warning, and `TrainingPlanView`'s
    ///    "a player who reads Burnt takes only half of the week's gains".
    ///    `MedicalEngine.workloadRiskMultiplier` returned exactly 1.0 for every
    ///    player in the league, always — plan §2.9.6's "workload is cosmetic"
    ///    defect surviving the fix that was meant to end it.
    /// 2. `tickWeek` rounded both halves of every day to an integer before
    ///    subtracting them, so recovery (`rate · 10`) collapsed to whole points
    ///    and the strength coach's 1–99 rating had five reachable values.
    ///    Coaches twenty points apart ran an identical camp. Netting the week
    ///    once (see `tickWeek`) removed that lattice — and with it the anchors
    ///    the first fix had used, because the per-day rounding had been
    ///    rounding recovery UP (0.55 → 6) and therefore under-reporting load.
    ///
    /// The three thresholds are now anchored to the measured end-of-cycle
    /// distribution at the league-default recovery (`./run.sh lockerroom`,
    /// section B: mean 50.0, sd 9.8, p10 ≈ 37, p50 50, p90 64):
    ///
    ///  * **37** is that distribution's bottom decile, so `.underloaded` means
    ///    a man the camp genuinely under-worked rather than an artefact of
    ///    where the old lattice happened to put its rungs.
    ///  * **64** is its top decile, so `.overloaded` is the top tenth of a
    ///    normally-run camp while the median man stays `.healthy` — which is
    ///    what `MedicalEngine.workloadRiskMultiplier`'s comment says the
    ///    league-wide tick has to leave a default-intensity roster in.
    ///  * **73** is ≈ p99, so `.burnedOut` is genuinely rare at a default camp
    ///    (measured 1.2 %, about one man every other club) and is something the
    ///    user reaches by choosing to work his roster harder or by employing a
    ///    poor strength coach, not something the schedule hands him.
    ///
    /// The bands are a decile rule, not three tuned numbers: if the camp
    /// scheduler or `computeRecoveryRate` moves, re-run the scenario and
    /// re-read p10 / p90 / p99 off section B rather than nudging these.
    private static let underloadedMax = 37
    private static let healthyMax = 64
    private static let overloadedMax = 73

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

    /// The two per-day scales, named so `tickWeek` (which nets a whole week in
    /// one go) and `tickDay` (which files a row a day) cannot drift apart.
    static let dailyLoadAtFullIntensity = 18.0
    static let dailyRecoveryAtFullRate = 10.0

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
    /// One camp day for the USER's club, with its `WorkloadEvent` row.
    ///
    /// The seven days of a week must add up to exactly what `tickWeek` would
    /// have produced, because the two paths tick the same league: the user's
    /// own roster comes through here (`WeekAdvancer.applyCampWeeklyTick`) while
    /// the other 31 clubs go through `tickWeek`. When this rounded each day's
    /// load and recovery separately it produced a different — and coarser —
    /// distribution than the netted path, so the user's roster ran the camp the
    /// engine's own band table was NOT calibrated on. A player and an AI club
    /// with identical staff finished camp in different states.
    ///
    /// The day's delta is therefore taken as a difference of running totals:
    /// `round(weekNet · (d+1)/7) − round(weekNet · d/7)`. Each row stays a whole
    /// number, the seven telescope to exactly `round(weekNet)`, and that is the
    /// same integer `tickWeek` writes. `loadDelta` / `recoveryDelta` on the row
    /// keep their own honest per-day rounding — they are an audit trail, not
    /// the accumulator.
    static func tickDay(
        player: Player,
        intensity: Double,
        recoveryRate: Double,
        seasonYear: Int,
        weekNumber: Int,
        dayOfWeek: Int,
        modelContext: ModelContext
    ) {
        let day = max(0, min(6, dayOfWeek))
        let clampedIntensity = max(0.0, min(1.0, intensity))
        let clampedRecovery = max(0.0, min(1.0, recoveryRate))
        let staminaFactor = 1.0 - (Double(player.physical.stamina) / 99.0) * 0.4
        let dayLoad = clampedIntensity * dailyLoadAtFullIntensity * staminaFactor
        let dayRecovery = clampedRecovery * dailyRecoveryAtFullRate
        let weekNet = (dayLoad - dayRecovery) * 7.0

        // The telescoping difference — this day's share of the week's exact net.
        let upToToday = Int((weekNet * Double(day + 1) / 7.0).rounded())
        let upToYesterday = Int((weekNet * Double(day) / 7.0).rounded())
        let net = upToToday - upToYesterday

        let newLoad = max(0, min(absoluteCap, player.cumulativeLoad + net))
        player.cumulativeLoad = newLoad
        player.workloadStatus = classify(load: newLoad)

        let delta = (load: Int(dayLoad.rounded()), recovery: Int(dayRecovery.rounded()))

        let event = WorkloadEvent(
            playerID: player.id,
            seasonYear: seasonYear,
            dayOfWeek: day,
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
    /// A week of camp, netted ONCE.
    ///
    /// This used to call `applyDailyLoad` seven times, which rounded BOTH halves
    /// of each day to an integer before subtracting them. Recovery is
    /// `recoveryRate · 10`, so the strength coach's whole 1–99 rating collapsed
    /// into five reachable values (4, 5, 6, 7, 8 points a day) and coaches
    /// twenty points apart ran an identical camp: the harness's `lockerroom` B2
    /// sweep measured `playerDevelopment` 50, 60 and 70 all producing
    /// 12.7 / 74.3 / 11.4 / 1.6 across the bands with a mean exit load of 40.7,
    /// to the decimal. A rating that cannot change an outcome is not a rating.
    ///
    /// Netting the week in `Double` and rounding once keeps the same expected
    /// load — no per-day constant moved — and restores the resolution the coach
    /// rating was always supposed to buy. It also removes the step-7 lattice the
    /// band table was anchored to, which is why the thresholds were re-measured
    /// in the same pass.
    ///
    /// Deliberately the WEEK and not the day: a week is the unit the camp
    /// scheduler advances in (one `tickWeek` per phase), while `tickDay` keeps
    /// its per-day rounding because it files a `WorkloadEvent` row per day and
    /// those rows have to be whole numbers.
    static func tickWeek(
        player: Player,
        intensity: Double,
        recoveryRate: Double
    ) {
        let clampedIntensity = max(0.0, min(1.0, intensity))
        let clampedRecovery = max(0.0, min(1.0, recoveryRate))
        let staminaFactor = 1.0 - (Double(player.physical.stamina) / 99.0) * 0.4
        let weekLoad = clampedIntensity * dailyLoadAtFullIntensity * staminaFactor * 7.0
        let weekRecovery = clampedRecovery * dailyRecoveryAtFullRate * 7.0
        let net = Int((weekLoad - weekRecovery).rounded())
        let newLoad = max(0, min(absoluteCap, player.cumulativeLoad + net))
        player.cumulativeLoad = newLoad
        player.workloadStatus = classify(load: newLoad)
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
        let loadDelta = Int((clampedIntensity * dailyLoadAtFullIntensity * staminaFactor).rounded())

        // Recovery delta scales 0..10 per day. Trainer skill amplifies recovery.
        let recoveryDelta = Int((clampedRecovery * dailyRecoveryAtFullRate).rounded())

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
