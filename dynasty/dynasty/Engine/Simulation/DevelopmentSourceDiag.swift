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

// MARK: - ChurnDiag (task #53)

/// Per-stage seasonal ROSTER-CHURN ledger: WHO left the league, who came back,
/// and what they looked like.
///
/// `DevelopmentSourceDiag` closed the first half of the drift question — every
/// weekly development pass sums to +0.07 mean OVR a season, so nobody is
/// developing the league into its §8 band misses. That leaves composition, and
/// composition is a FUNNEL: contracts expire, clubs cut, the market re-signs
/// some of them, the rest wash out, the draft brings a class in. Each of those
/// stages selects on something, and the league's steady state is whatever
/// survives all five.
///
/// The failure mode this exists to catch is an ASYMMETRIC pair of stages —
/// `WeekAdvancer.trimAIRosters` cutting on `RosterValue.keepScore` (which
/// discounts age hard) while `FreeAgencyEngine.simulateAIFreeAgency` signs on
/// raw `overall` (which does not discount it at all). Both stages look sane
/// alone; together they are a one-way ratchet that trades young depth for old
/// quality every league year, and no single-stage reading can see it. Hence one
/// line with EVERY stage on it, in the same four numbers (n, mean OVR, mean
/// age, mean yearsPro), so the asymmetry is a column comparison rather than an
/// argument.
///
/// Off by default; only `MultiSeasonSmokeTest` turns it on. `#if DEBUG` only —
/// a Release build keeps the stage names and an empty `record`.
@MainActor
enum ChurnDiag {

    // MARK: - Stage names

    /// Contract ran out at the league-year rollover (`executeNewLeagueYear`).
    /// The funnel's DENOMINATOR: everyone below either came back or did not.
    static let expire = "expire"
    /// Age/decline retirement pass (`.coachingChanges`).
    static let retire = "retire"
    /// Unsigned after the market closed (`processWashouts`).
    static let washout = "washout"
    /// Released at final cutdowns (`trimAIRosters` + the harness's user stand-in).
    static let cut = "cut"
    /// Signed out of the pool by the AI free-agent market.
    static let faSign = "faSign"
    /// Signed out of the pool by the roster floor (`refillAIRosters`).
    static let refill = "refill"
    /// Generated on the spot because the pool was dry — inflow from nowhere.
    static let street = "street"

#if DEBUG

    private static let stageOrder = [
        expire, retire, washout, cut, faSign, refill, street,
    ]

    /// Master switch. `record` is a no-op while this is false.
    static var isEnabled = false

    private struct Bucket {
        var n = 0
        var ovr = 0
        var age = 0
        var yearsPro = 0
    }

    private static var buckets: [String: Bucket] = [:]

    // MARK: - Recording

    static func record(_ stage: String, _ player: Player) {
        guard isEnabled else { return }
        var bucket = buckets[stage] ?? Bucket()
        bucket.n += 1
        bucket.ovr += player.overall
        bucket.age += player.age
        bucket.yearsPro += player.yearsPro
        buckets[stage] = bucket
    }

    // MARK: - Reporting

    /// One line per season, then clears the ledger. `poolLeft` is the unsigned,
    /// unretired residue the season ends with — the men the funnel neither
    /// re-signed nor removed.
    static func report(seasonLabel: Int, pool: [Player]) -> String? {
        guard isEnabled else { return nil }
        var parts: [String] = []
        for stage in stageOrder {
            let bucket = buckets[stage] ?? Bucket()
            guard bucket.n > 0 else {
                parts.append("\(stage)=0")
                continue
            }
            let n = Double(bucket.n)
            parts.append(String(
                format: "%@=%d/ovr%.1f/age%.1f/yp%.1f",
                stage, bucket.n,
                Double(bucket.ovr) / n, Double(bucket.age) / n, Double(bucket.yearsPro) / n
            ))
        }
        var line = "SMOKE: diag churn season=\(seasonLabel) " + parts.joined(separator: " ")
        if !pool.isEmpty {
            let n = Double(pool.count)
            line += String(
                format: " | poolLeft=%d/ovr%.1f/age%.1f/yp%.1f",
                pool.count,
                Double(pool.reduce(0) { $0 + $1.overall }) / n,
                Double(pool.reduce(0) { $0 + $1.age }) / n,
                Double(pool.reduce(0) { $0 + $1.yearsPro }) / n
            )
        }
        buckets.removeAll(keepingCapacity: true)
        return line
    }

    static func reset() { buckets.removeAll() }

#else

    @inline(__always) static func record(_ stage: String, _ player: Player) {}

#endif
}
