import Foundation

// MARK: - Season Stat Synthesizer

/// Builds a plausible season stat line for a season that never ran through the
/// simulator.
///
/// ## Why this exists
///
/// Three whole categories of season have no box score to aggregate:
///
/// | Season | Why |
/// |---|---|
/// | Template career arcs (publish profile) | `ANONYMIZATION_SPEC.md` §3 ships `{year, team, ovr, role}` only — by design, no real production leaves the transform |
/// | Random-league backstory | the generated league has no past at all |
/// | AI teams in a live season | 31 of 32 games are score-only (`WeekAdvancer.simulateGameScore`) |
///
/// A career table that showed `0` for all of those would be worse than showing
/// nothing, so the numbers are modelled instead — from the only honest inputs
/// available: position, end-of-season OVR, playing time (GP/GS or the arc's role
/// label) and age.
///
/// ## Calibration
///
/// Every position has a rate curve keyed on OVR, interpolated linearly between
/// anchor points that were picked to land on real modern-NFL magnitudes at a
/// full 17-game workload. The anchors are deliberately conservative at the top:
/// a 74-OVR quarterback lands around 3,400 yards, not 5,500, and only a
/// 95-plus arm reaches the 4,700-yard MVP shape. Volume then scales with
/// *effective starts* — a start counts fully, a non-start appearance counts for
/// the fraction of the workload a rotational player at that position really
/// gets — and a mild age taper damps rookie and late-30s usage.
///
/// ## Determinism
///
/// Every draw goes through the caller's generator, in a fixed order, and the
/// synthesizer holds no state. `LeagueTemplateImporter` therefore passes its own
/// `SeededLeagueRandom` sub-stream and two imports of the same template stay
/// byte-identical (the TVAL determinism gate hashes the stat columns). The live
/// and random-league paths are under no such constraint and pass whatever
/// generator is convenient.
enum SeasonStatSynthesizer {

    // MARK: - Participation

    /// Games played / started for a season that carries a role label but no
    /// counters — i.e. the publish template, where `ArcRow.gp` / `.gs` are
    /// stripped by the `publish-ovr-arcs-only` gate.
    ///
    /// The bands are the inverse of the transform's own `season_role` thresholds
    /// (`make_templates.py`): a starter is a ≥ 0.6 start share, a rotation player
    /// gets 4+ starts, a backup dresses most weeks without starting, depth is a
    /// handful of appearances. `role` of `nil` falls back to reading the OVR.
    ///
    /// Kickers and punters are special-cased. The transform's role heuristic reads
    /// starts and snap share, neither of which a specialist has, so every kicker
    /// and punter in the template is labelled `"backup"` — while the dev profile's
    /// real counters put their median season at 16-17 games. A specialist who
    /// dresses plays; he just never "starts".
    static func participation<G: RandomNumberGenerator>(
        position: Position,
        role: String?,
        overall: Int,
        using rng: inout G
    ) -> (gamesPlayed: Int, gamesStarted: Int) {
        let label = role ?? inferredRole(overall: overall)
        if position == .K || position == .P {
            return label == "depth"
                ? (Int.random(in: 1...6, using: &rng), 0)
                : (Int.random(in: 14...17, using: &rng), 0)
        }
        switch label {
        case "starter":
            let gp = Int.random(in: 14...17, using: &rng)
            return (gp, max(0, gp - Int.random(in: 0...2, using: &rng)))
        case "rotation":
            let gp = Int.random(in: 12...17, using: &rng)
            return (gp, min(gp, Int.random(in: 3...8, using: &rng)))
        case "backup":
            let gp = Int.random(in: 7...16, using: &rng)
            return (gp, min(gp, Int.random(in: 0...2, using: &rng)))
        default:
            return (Int.random(in: 1...6, using: &rng), 0)
        }
    }

    /// Role label implied by an OVR when the source carries none.
    static func inferredRole(overall: Int) -> String {
        switch overall {
        case 75...:  return "starter"
        case 68..<75: return "rotation"
        case 58..<68: return "backup"
        default:      return "depth"
        }
    }

    // MARK: - Entry point

    /// A full synthesized line for one season.
    ///
    /// Callers use this only when there is nothing real to show
    /// (`SeasonStatLine.isEmpty`); a season the sim did record is never
    /// overwritten.
    ///
    /// - Parameters:
    ///   - position: drives which categories are populated at all.
    ///   - overall: end-of-season OVR — the quality driver.
    ///   - gamesPlayed: appearances. `0` returns an all-zero line.
    ///   - gamesStarted: starts, clamped to `gamesPlayed`.
    ///   - age: mild usage taper only (very young and very old players are used
    ///     a little less at the same rating).
    static func line<G: RandomNumberGenerator>(
        position: Position,
        overall: Int,
        gamesPlayed: Int,
        gamesStarted: Int,
        age: Int,
        using rng: inout G
    ) -> SeasonStatLine {
        var line = SeasonStatLine()
        let gp = max(0, gamesPlayed)
        guard gp > 0 else { return line }
        let gs = min(gp, max(0, gamesStarted))
        let ovr = min(99, max(40, overall))
        let taper = ageTaper(age: age, position: position)

        /// Starts-equivalent workload: a start is worth 1, an appearance off the
        /// bench is worth the share of the job a backup at this position sees.
        func effectiveStarts(benchShare: Double) -> Double {
            (Double(gs) + Double(gp - gs) * benchShare) * taper
        }

        switch position {
        case .QB:
            synthesizePassing(&line, ovr: ovr, starts: effectiveStarts(benchShare: 0.12), rng: &rng)

        case .RB, .FB:
            let volumeScale = position == .FB ? 0.30 : 1.0
            synthesizeRushing(
                &line, ovr: ovr,
                starts: effectiveStarts(benchShare: 0.35) * volumeScale,
                rng: &rng
            )
            synthesizeReceiving(
                &line, ovr: ovr,
                starts: effectiveStarts(benchShare: 0.35) * volumeScale,
                catchRate: backCatchRate, yardsPerCatch: backYardsPerCatch,
                yardsPerTD: 220, rng: &rng
            )

        case .WR:
            synthesizeReceiving(
                &line, ovr: ovr, starts: effectiveStarts(benchShare: 0.45),
                catchRate: wideoutCatchRate, yardsPerCatch: wideoutYardsPerCatch,
                yardsPerTD: interpolate(ovr, tdYardsWideout), rng: &rng
            )

        case .TE:
            synthesizeReceiving(
                &line, ovr: ovr, starts: effectiveStarts(benchShare: 0.45),
                catchRate: endCatchRate, yardsPerCatch: endYardsPerCatch,
                yardsPerTD: interpolate(ovr, tdYardsWideout) * 1.08, rng: &rng
            )

        case .LT, .LG, .C, .RG, .RT:
            // A starting lineman plays essentially every offensive snap; a
            // backup only spells and plays special teams.
            let snaps = Double(gs) * 66.0 + Double(gp - gs) * 18.0
            line.snapsPlayed = round(snaps * jitter(0.94...1.03, &rng))

        case .DE, .DT:
            let scale: (tackles: Double, sacks: Double) = position == .DE
                ? (1.0, 1.0)
                : (0.85, 0.55)
            synthesizeFrontSeven(
                &line, ovr: ovr, games: effectiveStarts(benchShare: 0.5),
                tackleCurve: edgeTackles, tackleScale: scale.tackles,
                sackScale: scale.sacks, interceptionScale: 0.25, rng: &rng
            )

        case .OLB:
            synthesizeFrontSeven(
                &line, ovr: ovr, games: effectiveStarts(benchShare: 0.5),
                tackleCurve: outsideLinebackerTackles, tackleScale: 1.0,
                sackScale: 0.60, interceptionScale: 0.9, rng: &rng
            )

        case .MLB:
            synthesizeFrontSeven(
                &line, ovr: ovr, games: effectiveStarts(benchShare: 0.5),
                tackleCurve: insideLinebackerTackles, tackleScale: 1.0,
                sackScale: 0.35, interceptionScale: 1.0, rng: &rng
            )

        case .CB:
            synthesizeSecondary(
                &line, ovr: ovr, games: effectiveStarts(benchShare: 0.5),
                tackleCurve: cornerTackles, interceptionScale: 1.0,
                deflectionScale: 1.0, rng: &rng
            )

        case .FS, .SS:
            synthesizeSecondary(
                &line, ovr: ovr, games: effectiveStarts(benchShare: 0.5),
                tackleCurve: position == .SS ? strongSafetyTackles : freeSafetyTackles,
                interceptionScale: 0.85, deflectionScale: 0.6, rng: &rng
            )

        case .K:
            let attempts = round(
                interpolate(ovr, kickerAttempts) * Double(gp) / 17.0 * jitter(0.85...1.15, &rng)
            )
            let rate = min(0.98, max(0.55, interpolate(ovr, kickerAccuracy) * jitter(0.96...1.04, &rng)))
            line.fieldGoalsAttempted = max(attempts, 0)
            line.fieldGoalsMade = min(line.fieldGoalsAttempted, round(Double(attempts) * rate))

        case .P:
            // Punt volume is a property of the offense, not the punter, so the
            // count barely moves with OVR; the average is where skill shows.
            line.punts = max(0, round(52.0 * Double(gp) / 17.0 * jitter(0.80...1.20, &rng)))
            line.puntAverage = (interpolate(ovr, punterAverage) * jitter(0.98...1.02, &rng) * 10).rounded() / 10
        }

        return line
    }

    // MARK: - Position families

    private static func synthesizePassing<G: RandomNumberGenerator>(
        _ line: inout SeasonStatLine, ovr: Int, starts: Double, rng: inout G
    ) {
        let yards = interpolate(ovr, passYardsPerStart) * starts * jitter(0.88...1.12, &rng)
        let attempts = yards / interpolate(ovr, yardsPerAttempt)
        line.passYards = round(yards)
        line.passTDs = round(attempts * interpolate(ovr, passTDRate) * jitter(0.85...1.15, &rng))
        line.passInts = round(attempts * interpolate(ovr, passIntRate) * jitter(0.80...1.25, &rng))
        // Scramble yardage: hugely player-dependent, so the jitter is wide.
        let scramble = interpolate(ovr, quarterbackRushYardsPerStart) * starts * jitter(0.40...1.80, &rng)
        line.rushYards = round(scramble)
        line.rushTDs = round(scramble / 95.0)
    }

    private static func synthesizeRushing<G: RandomNumberGenerator>(
        _ line: inout SeasonStatLine, ovr: Int, starts: Double, rng: inout G
    ) {
        let yards = interpolate(ovr, rushYardsPerStart) * starts * jitter(0.85...1.15, &rng)
        line.rushYards = round(yards)
        line.rushTDs = round(yards / interpolate(ovr, rushYardsPerTD))
    }

    private static func synthesizeReceiving<G: RandomNumberGenerator>(
        _ line: inout SeasonStatLine, ovr: Int, starts: Double,
        catchRate: [(Int, Double)], yardsPerCatch: [(Int, Double)],
        yardsPerTD: Double, rng: inout G
    ) {
        let catches = interpolate(ovr, catchRate) * starts * jitter(0.85...1.15, &rng)
        let yards = catches * interpolate(ovr, yardsPerCatch) * jitter(0.92...1.08, &rng)
        line.receptions = round(catches)
        line.recYards = round(yards)
        line.recTDs = round(yards / max(1, yardsPerTD))
    }

    private static func synthesizeFrontSeven<G: RandomNumberGenerator>(
        _ line: inout SeasonStatLine, ovr: Int, games: Double,
        tackleCurve: [(Int, Double)], tackleScale: Double,
        sackScale: Double, interceptionScale: Double, rng: inout G
    ) {
        line.tackles = round(interpolate(ovr, tackleCurve) * tackleScale * games * jitter(0.88...1.12, &rng))
        // Sacks are recorded in halves, so round to the nearest half.
        let sacks = interpolate(ovr, edgeSacks) * sackScale * games * jitter(0.70...1.35, &rng)
        line.sacks = (sacks * 2).rounded() / 2
        line.defInts = round(
            interpolate(ovr, defensiveInterceptions) * interceptionScale
            * games / 17.0 * jitter(0.40...1.70, &rng)
        )
        line.passesDefended = round(
            interpolate(ovr, passesDefendedCurve) * 0.35 * games / 17.0 * jitter(0.6...1.4, &rng)
        )
    }

    private static func synthesizeSecondary<G: RandomNumberGenerator>(
        _ line: inout SeasonStatLine, ovr: Int, games: Double,
        tackleCurve: [(Int, Double)], interceptionScale: Double,
        deflectionScale: Double, rng: inout G
    ) {
        line.tackles = round(interpolate(ovr, tackleCurve) * games * jitter(0.88...1.12, &rng))
        line.defInts = round(
            interpolate(ovr, defensiveInterceptions) * interceptionScale
            * games / 17.0 * jitter(0.50...1.60, &rng)
        )
        line.passesDefended = max(
            line.defInts,
            round(interpolate(ovr, passesDefendedCurve) * deflectionScale * games / 17.0 * jitter(0.75...1.25, &rng))
        )
        // Corners and safeties blitz occasionally; keep it to the odd half-sack.
        let sacks = interpolate(ovr, edgeSacks) * 0.10 * games * jitter(0.0...1.6, &rng)
        line.sacks = (sacks * 2).rounded() / 2
    }

    // MARK: - Rate curves (OVR → per-start / per-game / per-season rate)

    // Passing — a 17-start season lands at ~2,400 yds (50 OVR), ~3,400 (74),
    // ~4,250 (88), ~4,700 (95).
    private static let passYardsPerStart: [(Int, Double)] = [
        (40, 100), (55, 140), (65, 180), (75, 215), (85, 250), (95, 278), (99, 292)
    ]
    private static let yardsPerAttempt: [(Int, Double)] = [
        (40, 5.6), (70, 6.9), (85, 7.4), (99, 7.9)
    ]
    private static let passTDRate: [(Int, Double)] = [
        (40, 0.026), (60, 0.036), (75, 0.043), (88, 0.055), (99, 0.062)
    ]
    private static let passIntRate: [(Int, Double)] = [
        (40, 0.038), (60, 0.028), (75, 0.022), (88, 0.016), (99, 0.012)
    ]
    private static let quarterbackRushYardsPerStart: [(Int, Double)] = [
        (40, 3), (70, 8), (99, 14)
    ]

    // Rushing — a 17-start season lands at ~1,120 yds (74 OVR), ~1,530 (92).
    private static let rushYardsPerStart: [(Int, Double)] = [
        (40, 18), (55, 32), (65, 48), (75, 66), (85, 84), (92, 96), (99, 108)
    ]
    private static let rushYardsPerTD: [(Int, Double)] = [
        (40, 200), (65, 145), (85, 118), (99, 102)
    ]

    // Receiving.
    private static let wideoutCatchRate: [(Int, Double)] = [
        (40, 0.8), (55, 1.6), (65, 2.6), (75, 3.8), (85, 5.0), (92, 5.9), (99, 6.7)
    ]
    private static let wideoutYardsPerCatch: [(Int, Double)] = [
        (40, 9.5), (65, 11.5), (80, 13.0), (92, 14.2), (99, 15.0)
    ]
    private static let endCatchRate: [(Int, Double)] = [
        (40, 0.45), (55, 1.1), (65, 1.9), (75, 2.8), (85, 3.8), (92, 4.5), (99, 5.2)
    ]
    private static let endYardsPerCatch: [(Int, Double)] = [
        (40, 8.0), (65, 9.8), (80, 11.2), (92, 12.4), (99, 13.2)
    ]
    private static let backCatchRate: [(Int, Double)] = [
        (40, 0.35), (60, 1.0), (75, 1.9), (88, 2.9), (99, 3.6)
    ]
    private static let backYardsPerCatch: [(Int, Double)] = [
        (40, 5.5), (70, 7.5), (99, 9.5)
    ]
    private static let tdYardsWideout: [(Int, Double)] = [
        (40, 240), (70, 175), (88, 140), (99, 125)
    ]

    // Defense — per effective game.
    private static let edgeTackles: [(Int, Double)] = [
        (40, 0.7), (60, 1.6), (75, 2.6), (88, 3.4), (99, 4.0)
    ]
    private static let outsideLinebackerTackles: [(Int, Double)] = [
        (40, 1.1), (60, 2.4), (75, 4.0), (88, 5.4), (99, 6.4)
    ]
    private static let insideLinebackerTackles: [(Int, Double)] = [
        (40, 1.5), (60, 3.2), (75, 5.2), (88, 7.0), (99, 9.0)
    ]
    private static let cornerTackles: [(Int, Double)] = [
        (40, 0.9), (60, 2.0), (75, 3.0), (88, 3.8), (99, 4.4)
    ]
    private static let freeSafetyTackles: [(Int, Double)] = [
        (40, 1.2), (60, 2.8), (75, 4.2), (88, 5.4), (99, 6.2)
    ]
    private static let strongSafetyTackles: [(Int, Double)] = [
        (40, 1.3), (60, 3.0), (75, 4.6), (88, 5.9), (99, 6.8)
    ]
    private static let edgeSacks: [(Int, Double)] = [
        (40, 0.04), (60, 0.16), (75, 0.32), (85, 0.50), (92, 0.66), (99, 0.90)
    ]
    /// Season interceptions at a full 17-game workload.
    private static let defensiveInterceptions: [(Int, Double)] = [
        (40, 0.15), (60, 0.8), (75, 1.8), (88, 3.2), (99, 4.8)
    ]
    /// Season passes defended at a full 17-game workload (corner baseline).
    private static let passesDefendedCurve: [(Int, Double)] = [
        (40, 1.2), (60, 4.0), (75, 8.0), (88, 13.0), (99, 17.0)
    ]

    // Specialists.
    private static let kickerAttempts: [(Int, Double)] = [
        (40, 21), (60, 25), (75, 29), (88, 32), (99, 34)
    ]
    private static let kickerAccuracy: [(Int, Double)] = [
        (40, 0.66), (60, 0.75), (75, 0.83), (88, 0.89), (99, 0.94)
    ]
    private static let punterAverage: [(Int, Double)] = [
        (40, 40.0), (60, 43.0), (75, 45.5), (88, 47.5), (99, 49.5)
    ]

    // MARK: - Math helpers

    /// Piecewise-linear lookup over an OVR-keyed anchor table. Anchors are
    /// ascending; values outside the range clamp to the end anchors.
    private static func interpolate(_ ovr: Int, _ anchors: [(Int, Double)]) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if ovr <= first.0 { return first.1 }
        if ovr >= last.0 { return last.1 }
        for index in 1..<anchors.count {
            let (highOVR, highValue) = anchors[index]
            guard ovr <= highOVR else { continue }
            let (lowOVR, lowValue) = anchors[index - 1]
            let t = Double(ovr - lowOVR) / Double(highOVR - lowOVR)
            return lowValue + (highValue - lowValue) * t
        }
        return last.1
    }

    /// Usage taper: a 21-year-old and a 36-year-old at the same rating both see
    /// slightly less of the workload than a player in his prime window.
    private static func ageTaper(age: Int, position: Position) -> Double {
        let peak = position.peakAgeRange
        if age < peak.lowerBound - 2 { return 0.90 }
        if age < peak.lowerBound { return 0.96 }
        if age > peak.upperBound + 3 { return 0.92 }
        return 1.0
    }

    private static func jitter<G: RandomNumberGenerator>(
        _ range: ClosedRange<Double>, _ rng: inout G
    ) -> Double {
        Double.random(in: range, using: &rng)
    }

    /// Non-negative integer rounding — no synthesized stat is ever negative.
    private static func round(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return max(0, Int(value.rounded()))
    }
}
