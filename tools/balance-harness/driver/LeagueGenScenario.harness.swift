import Foundation

// ============================================================================
// scenario `leaguegen` — the RANDOM league's t=0 quality pyramid
// ============================================================================
//
// Measures what `LeagueGenerator` actually hands a new save, against
// `docs/DEVELOPMENT_NFL_REFERENCE.md` §8's absolute quality bands.
//
// WHY THIS SCENARIO EXISTS. The P1 quality-pyramid wave (2026-07-30) recalibrated
// the generator's intake level and shape, and every constant it chose was fitted
// against the PYTHON MIRROR of the generator that lives in
// `tools/league-data/make_templates.py` (`reference_overall`). That mirror is not
// a convenience: the fixed-2026 template league is calibrated ONTO it, so if the
// mirror ever drifts from the Swift, both league sources go wrong at once and
// nothing else in the repo would notice. This scenario measures the same bands
// from the Swift side, so the two are pinned against each other.
//
// WHAT IS SHIPPED CODE HERE. Everything that decides a rating:
//   • `LeagueGenerator.ageLevelShift` / `talentLevelShift` / `veteranLevelShift`
//     / `positionAttributeRange` / `randomPositionAttributes` / `randomAge`
//     / `rosterBlueprint` / `veteranPotential` — awk-sliced verbatim from the
//     repo file by `sync_sources.sh` (see `LeagueGeneratorExtract.swift`).
//   • `PositionPhysicalProfile.sample` / `sampleMental` — verbatim repo file.
//   • `Player.overall` — the harness `Player` stub splices the repo's computed
//     property, so the 0.5/0.3/0.2 weighting is the shipped one.
//
// WHAT IS SCAFFOLDING. Only the six-line assembly that `generatePlayer` performs
// between those calls (draw an age, add the two level terms, hand the rounded
// shift to the position skills and the exact one to the priors). That ordering is
// asserted against the repo file by `sync_sources.sh`'s slice guards; if
// `generatePlayer` is restructured, this scenario has to be revisited — which is
// the same contract every other scenario in this harness carries.

// MARK: - §8 bands

/// `DEVELOPMENT_NFL_REFERENCE.md` §8, as the generator's t=0 targets. These are
/// the same bands `MultiSeasonSmokeTest.printPyramidDiagnostics` gates the live
/// app on, deliberately: the smoke test's season-0 line IS this population.
let lgBands: [(name: String, lo: Double, hi: Double, ref: String)] = [
    ("90+",   1.0,  2.5, "§8 1-2 % (25-35 blue chips)"),
    ("80+",  12.0, 19.0, "§8 12-16 %"),
    ("75+",  28.0, 40.0, "§8 30-40 % (starter-quality)"),
    ("sub65", 20.0, 28.0, "§8 ~25 % (depth / special teams)"),
]
/// The mean is DERIVED from the four shares, not prescribed by §8 — it is banded
/// only as a rail, and its centre is where the development stack's own 30-season
/// equilibrium sits (`career` scenario: 71.4). Generator and equilibrium have to
/// agree or the smoke test's OVR-drift gate measures the gap between them.
let lgMeanBand = (70.0, 72.2)
let lgSDBand = (8.2, 9.6)

/// The Python mirror's own measurement of the same population, for the pin.
/// Source: `tools/league-data/make_templates.py`, 400-league Monte-Carlo of
/// `reference_overall` (`blueprint_league_stats()`), 2026-07-30.
let lgMirror: (mean: Double, sd: Double, p90: Double, p80: Double, p75: Double, sub65: Double) =
    (71.00, 8.86, 1.7, 16.9, 34.8, 23.3)
/// How far the Swift may sit from the mirror before the two are considered
/// drifted. Both sides are Monte-Carlo, so this is sampling slack, not tolerance
/// for a real difference: at 400 leagues a 1.7 % share carries ~±0.15 pp.
let lgMirrorTolerance: (level: Double, share: Double) = (0.5, 1.5)

// MARK: - Scenario

func scenarioLeagueGen(_ flags: [String: String]) {
    let leagues = Int(flags["leagues"] ?? "") ?? 400
    print("===== SCENARIO leaguegen: \(leagues) x 53-man rosters from the SHIPPED LeagueGenerator =====")
    print("  rating path: LeagueGenerator (awk slice) + PositionPhysicalProfile (verbatim) + Player.overall (splice)")
    print("  target: DEVELOPMENT_NFL_REFERENCE §8 · pin: make_templates.py reference_overall")

    let t0 = Date()
    var overalls: [Double] = []
    var potentials: [Double] = []
    var ages: [Double] = []
    var byTier: [Int: [Double]] = [0: [], 1: [], 2: []]
    var rng = SystemRandomNumberGenerator()

    for _ in 0..<leagues {
        // `generateRoster` keeps a RUNNING per-position depth chart across the
        // whole blueprint, and the blueprint lists WR / DE / CB twice — a base
        // entry and an "extra depth" entry at the end. Counting inside each entry
        // instead would hand those three players a STARTER-tier draw; the mirror
        // pin caught exactly that (mean +0.79, 80+ +2.40) the first time this
        // scenario ran, which is what the pin is for.
        var depthChart: [Position: Int] = [:]
        for (position, count) in LeagueGenerator.rosterBlueprint {
            for _ in 0..<count {
                let rank = depthChart[position, default: 0]
                depthChart[position] = rank + 1
                let depthIndex = min(rank, 2)
                // --- the `generatePlayer` rating path -------------------------
                let age = LeagueGenerator.randomAge(for: position)
                let levelShift = LeagueGenerator.ageLevelShift(age: age, position: position)
                    + LeagueGenerator.talentLevelShift(depthIndex: depthIndex, using: &rng)
                let ageShift = Int(levelShift.rounded())
                let posAttrs = LeagueGenerator.randomPositionAttributes(
                    for: position, depthIndex: depthIndex, ageShift: ageShift
                )
                let physical = PositionPhysicalProfile.sample(
                    for: position,
                    levelShift: LeagueGenerator.veteranLevelShift(depthIndex: depthIndex) + levelShift
                )
                let mental = PositionPhysicalProfile.sampleMental(
                    for: position,
                    targetAverage: PositionPhysicalProfile.baseLevel
                        + LeagueGenerator.veteranLevelShift(depthIndex: depthIndex) + levelShift
                )
                // --- read the SHIPPED `Player.overall` -----------------------
                let probe = Player(
                    fullName: "probe",
                    position: position,
                    physical: physical,
                    mental: mental,
                    positionAttributes: posAttrs
                )
                let ovr = Double(probe.overall)
                overalls.append(ovr)
                byTier[depthIndex]?.append(ovr)
                ages.append(Double(age))
                potentials.append(Double(LeagueGenerator.veteranPotential(
                    overall: probe.overall, age: age, position: position, depthIndex: depthIndex
                )))
            }
        }
    }

    let n = Double(overalls.count)
    func share(_ predicate: (Double) -> Bool) -> Double {
        Double(overalls.filter(predicate).count) / n * 100
    }
    let mean = crMean(overalls)
    let sd = (overalls.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / n).squareRoot()
    let measured: [String: Double] = [
        "90+": share { $0 >= 90 }, "80+": share { $0 >= 80 },
        "75+": share { $0 >= 75 }, "sub65": share { $0 < 65 },
    ]

    print("")
    print("--- t=0 QUALITY PYRAMID ---------------------------------------------------")
    print(String(format: "  n=%.0f players (%d leagues)   runtime %.1fs",
                 n, leagues, Date().timeIntervalSince(t0)))
    print(String(format: "  mean %.2f [%.1f-%.1f]  sd %.2f [%.1f-%.1f]  median %.0f  min %.0f  max %.0f",
                 mean, lgMeanBand.0, lgMeanBand.1, sd, lgSDBand.0, lgSDBand.1,
                 crPct(overalls, 0.50), overalls.min() ?? 0, overalls.max() ?? 0))
    for b in lgBands {
        print(String(format: "  %-6@ %6.2f%%  band %.1f-%.1f   %@",
                     b.name, measured[b.name] ?? 0, b.lo, b.hi, b.ref))
    }
    print(String(format: "  blue chips (90+) in a 1696-man league: %.1f players [25-35]",
                 (measured["90+"] ?? 0) / 100.0 * 1696.0))
    print(String(format: "  depth tiers: idx0 %.2f  idx1 %.2f  idx2 %.2f   (starter / backup / depth)",
                 crMean(byTier[0] ?? []), crMean(byTier[1] ?? []), crMean(byTier[2] ?? [])))
    print(String(format: "  age: mean %.2f  median %.0f  33+ %.2f%%   |  veteranPotential: mean %.2f  headroom over OVR %+.2f",
                 crMean(ages), crPct(ages, 0.50),
                 Double(ages.filter { $0 >= 33 }.count) / n * 100,
                 crMean(potentials), crMean(potentials) - mean))
    var hist = "  histogram:"
    for lo in stride(from: 35, through: 95, by: 5) {
        let c = overalls.filter { $0 >= Double(lo) && $0 < Double(lo + 5) }.count
        hist += String(format: " %d-%d %.1f%% ", lo, lo + 4, Double(c) / n * 100)
    }
    print(hist)

    print("")
    print("--- PIN AGAINST THE PYTHON MIRROR ----------------------------------------")
    print("  make_templates.py `reference_overall` is what the FIXED-2026 template league")
    print("  is calibrated onto. If it drifts from the Swift, both league sources go wrong")
    print("  together and no other gate in the repo can see it.")
    print(String(format: "  %-8@ %8@ %8@ %8@", "metric", "swift", "mirror", "delta"))
    let pins: [(String, Double, Double, Double)] = [
        ("mean", mean, lgMirror.mean, lgMirrorTolerance.level),
        ("sd", sd, lgMirror.sd, lgMirrorTolerance.level),
        ("90+", measured["90+"] ?? 0, lgMirror.p90, lgMirrorTolerance.share),
        ("80+", measured["80+"] ?? 0, lgMirror.p80, lgMirrorTolerance.share),
        ("75+", measured["75+"] ?? 0, lgMirror.p75, lgMirrorTolerance.share),
        ("sub65", measured["sub65"] ?? 0, lgMirror.sub65, lgMirrorTolerance.share),
    ]
    for (name, sw, mi, tol) in pins {
        print(String(format: "  %-8@ %8.2f %8.2f %+8.2f   tol %.2f%@",
                     name, sw, mi, sw - mi, tol, abs(sw - mi) <= tol ? "" : "   <-- DRIFTED"))
    }

    let A = CRAsserts()
    for b in lgBands {
        let v = measured[b.name] ?? 0
        A.check("8.\(b.name)", v >= b.lo && v <= b.hi,
                String(format: "§8 %@ share in [%.1f,%.1f]%% (%.2f%%)", b.name, b.lo, b.hi, v))
    }
    A.check("8.mean", mean >= lgMeanBand.0 && mean <= lgMeanBand.1,
            String(format: "league mean in [%.1f,%.1f] (%.2f) — matches the dev stack's equilibrium 71.4",
                   lgMeanBand.0, lgMeanBand.1, mean))
    A.check("8.sd", sd >= lgSDBand.0 && sd <= lgSDBand.1,
            String(format: "league sd in [%.1f,%.1f] (%.2f)", lgSDBand.0, lgSDBand.1, sd))
    // Tier ordering: the pyramid must still be a pyramid.
    let t0m = crMean(byTier[0] ?? []), t1m = crMean(byTier[1] ?? []), t2m = crMean(byTier[2] ?? [])
    A.check("8.tiers", t0m > t1m && t1m > t2m,
            String(format: "depth tiers strictly ordered (%.2f > %.2f > %.2f)", t0m, t1m, t2m))
    // No unrostered bodies: the talent draw is truncated for exactly this reason.
    A.check("8.floor", (overalls.min() ?? 0) >= 35,
            String(format: "no player below OVR 35 (min %.0f) — talentLevelShift truncation holds",
                   overalls.min() ?? 0))
    // Generated veterans must NOT arrive with free catch-up room (the wave's fix).
    let headroom = crMean(potentials) - mean
    A.check("8.headroom", headroom <= 4.0,
            String(format: "mean veteranPotential headroom over OVR <= 4.0 (%.2f) — was 6-9 before the wave",
                   headroom))
    var drifted: [String] = []
    for (name, sw, mi, tol) in pins where abs(sw - mi) > tol {
        drifted.append(String(format: "%@ %+.2f", name, sw - mi))
    }
    A.check("8.mirror", drifted.isEmpty,
            drifted.isEmpty
              ? "Swift generator matches make_templates.py's mirror on every metric"
              : "MIRROR DRIFT: \(drifted.joined(separator: ", ")) — re-derive make_templates.py's constants")
    A.report()

    if A.failures > 0 {
        print("")
        print("LEAGUEGEN: FAILED (\(A.failures) assertion(s))")
        exit(1)
    }
    print("")
    print("LEAGUEGEN: OK")
}
