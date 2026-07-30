import Foundation

// MARK: - DevelopmentSourceDiag (task #51)

/// Per-source seasonal development ledger: WHICH pass moved the league's OVR.
///
/// The finding this exists for: at identical draft intake `tools/balance-harness`'s
/// `career` scenario settles at mean 70.7 / 80+ 15.9 %, while `MultiSeasonSmokeTest`
/// reached 71.9 / 22.0 % in four seasons and was still climbing. Both call the same
/// `PlayerDevelopmentEngine.processOffseason`, so the gap has to be in the passes
/// the harness does NOT model — and "has to be" is exactly the kind of reasoning
/// that has already cost this project two mis-aimed calibrations. So: measure.
///
/// Every instrumented pass is wrapped in `measure`, which snapshots the exact
/// (unrounded) overall and `truePotential` of the players it is handed, runs the
/// pass, and books the difference under a named source. `report` then prints one
/// line per season in LEAGUE-MEAN OVR POINTS, i.e. the units the pyramid gate is
/// stated in — a source worth "+0.4 mean OVR a season" is a source that moves the
/// gate, one worth "+0.01" is not, and no amount of plausible narrative about a
/// pass survives its own number.
///
/// Off by default: `MultiSeasonSmokeTest` turns it on, nothing else does. The
/// accumulator state is `#if DEBUG` only, so a Release build keeps just the
/// source names and a `measure` that is literally `body()`.
@MainActor
enum DevelopmentSourceDiag {

    // MARK: - Source names

    /// Camp development: `PlayerDevelopmentEngine.processOffseason` — the ONE
    /// pass the balance harness also runs, i.e. the control in this experiment.
    static let offseasonDevelop = "offseasonDevelop"
    /// The user team's weekly camp training plan (`TrainingPlanEngine.applyWeekly`).
    static let campTrainingPlan = "campTrainingPlan"
    /// League-wide weekly training focus (`TrainingFocusEngine.applyWeeklyFocusTick`).
    static let focusTick = "focusTick"
    /// League-wide weekly breakout roll (`TrainingFocusEngine.rollBreakout`).
    static let breakout = "breakout"
    /// League-wide weekly game experience (`PlayerDevelopmentEngine.applyGameExperience`).
    static let gameXP = "gameXP"

#if DEBUG

    private static let sourceOrder = [
        offseasonDevelop, campTrainingPlan, focusTick, breakout, gameXP,
    ]

    /// Master switch. `measure` is a straight pass-through while this is false,
    /// so the instrumented call sites cost one branch in a normal DEBUG run.
    static var isEnabled = false

    // MARK: - State

    private struct Bucket {
        var ovr = 0.0
        var potential = 0.0
        var movedPlayers = 0
    }

    private static var buckets: [String: Bucket] = [:]
    /// Scheme-fit values handed to `updatePotentialRealization` this season —
    /// the input whose distribution is the whole question (the harness draws it
    /// once from N(0.55, 0.18) per player and never moves it again).
    private static var schemeFitSamples: [Double] = []
    private static var beforeOVR: [UUID: Double] = [:]
    private static var beforePot: [UUID: Double] = [:]

    // MARK: - Measurement

    /// Runs `body`, booking every OVR / potential point it moved on `players`
    /// under `source`.
    @discardableResult
    static func measure<T>(
        _ source: String,
        _ players: [Player],
        _ body: () -> T
    ) -> T {
        guard isEnabled, !players.isEmpty else { return body() }

        beforeOVR.removeAll(keepingCapacity: true)
        beforePot.removeAll(keepingCapacity: true)
        for player in players {
            beforeOVR[player.id] = exactOverall(player)
            beforePot[player.id] = Double(player.truePotential)
        }

        let result = body()

        var bucket = buckets[source] ?? Bucket()
        for player in players {
            guard let priorOVR = beforeOVR[player.id],
                  let priorPot = beforePot[player.id] else { continue }
            let deltaOVR = exactOverall(player) - priorOVR
            let deltaPot = Double(player.truePotential) - priorPot
            if deltaOVR != 0 || deltaPot != 0 { bucket.movedPlayers += 1 }
            bucket.ovr += deltaOVR
            bucket.potential += deltaPot
        }
        buckets[source] = bucket
        return result
    }

    /// Records one scheme-fit input. Called from `WeekAdvancer.offseasonSchemeFit`.
    static func recordSchemeFit(_ fit: Double) {
        guard isEnabled else { return }
        schemeFitSamples.append(fit)
    }

    /// `Player.overall` without the final rounding. A whole league's worth of
    /// +0.3-point attribute nudges rounds away to nothing player-by-player and
    /// is precisely what this ledger is trying to see.
    static func exactOverall(_ player: Player) -> Double {
        player.positionAttributes.overall * 0.5
            + player.physical.average * 0.3
            + player.mental.average * 0.2
    }

    // MARK: - Reporting

    /// One line per season, in league-mean OVR points, then clears the ledger.
    /// `rosteredCount` is the divisor so the numbers are directly comparable
    /// with the `avgOVR` drift gate and the pyramid shares.
    static func report(seasonLabel: Int, rosteredCount: Int) -> String? {
        guard isEnabled, rosteredCount > 0 else { return nil }
        let n = Double(rosteredCount)

        var parts: [String] = []
        for source in sourceOrder {
            let bucket = buckets[source] ?? Bucket()
            parts.append(String(format: "%@=%+.3f", source, bucket.ovr / n))
        }
        // Potential is the OTHER half of the story: a pass can move nobody's
        // OVR this season and still raise every ceiling in the league, which
        // cashes out as OVR in every season after it.
        let potParts = sourceOrder.compactMap { source -> String? in
            let bucket = buckets[source] ?? Bucket()
            guard abs(bucket.potential) >= 0.5 else { return nil }
            return String(format: "%@=%+.3f", source, bucket.potential / n)
        }

        var line = "SMOKE: diag devsource season=\(seasonLabel) ovr/player: "
            + parts.joined(separator: " ")
        if !potParts.isEmpty {
            line += " | pot/player: " + potParts.joined(separator: " ")
        }
        if !schemeFitSamples.isEmpty {
            let sorted = schemeFitSamples.sorted()
            let mean = sorted.reduce(0, +) / Double(sorted.count)
            func pct(_ fraction: Double) -> Double {
                sorted[min(sorted.count - 1, max(0, Int(fraction * Double(sorted.count))))]
            }
            let topBucketShare = Double(sorted.filter { $0 >= 0.8 }.count)
                / Double(sorted.count) * 100
            line += String(
                format: " | schemeFit n=%d mean=%.2f p10=%.2f p50=%.2f p90=%.2f fit>=0.80=%.1f%%",
                sorted.count, mean, pct(0.10), pct(0.50), pct(0.90), topBucketShare
            )
        }

        buckets.removeAll(keepingCapacity: true)
        schemeFitSamples.removeAll(keepingCapacity: true)
        return line
    }

    /// Clears everything — a fresh smoke run must not inherit the previous one.
    static func reset() {
        buckets.removeAll()
        schemeFitSamples.removeAll()
        beforeOVR.removeAll()
        beforePot.removeAll()
    }

#else

    /// Release: the ledger does not exist, so the wrapper is the body.
    @inline(__always) @discardableResult
    static func measure<T>(
        _ source: String,
        _ players: [Player],
        _ body: () -> T
    ) -> T {
        body()
    }

    @inline(__always) static func recordSchemeFit(_ fit: Double) {}

#endif
}
