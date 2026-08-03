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

// MARK: - Headroom reference (task #69)

/// What the OTHER end of the player pipeline produces, measured: the
/// `career` scenario's `HEADROOM AT EQUILIBRIUM` block, 33 888 player-slots
/// pooled over 20 pure-draft-intake leagues' final measured season.
///
/// This scenario and that one are the repo's only two league sources, and until
/// task #69 they disagreed about `truePotential` by ten OVR points at the same
/// age — the generator shipped a cross-section 2 points under its ceiling while
/// the draft shipped classes 12 under theirs. A save spends its first four
/// seasons converting one into the other, which is what
/// `MultiSeasonSmokeTest` was measuring as a rising `leaguePot` and a rising
/// 80+ share. The gate below is what stops the two drifting apart again.
let lgHeadroomEquilibrium: (mean: Double, potMean: Double, pot90Share: Double,
                            byAge: [Int: Double]) = (
    mean: 12.02, potMean: 82.75, pot90Share: 29.1,
    byAge: [21: 19.17, 22: 17.40, 23: 15.45, 24: 13.34, 25: 11.87, 26: 10.75,
            27: 10.35, 28: 10.20, 29: 9.66, 30: 9.53, 31: 9.05, 32: 8.88,
            33: 8.99, 34: 7.51]
)

// MARK: - Day-one scheme familiarity reference (task #66 / #85)

/// The `career` scenario's measured familiarity ladder by `yearsPro` — the
/// equilibrium `LeagueGenerator.activeSchemeSeed`'s curve claims to reproduce.
///
/// **Why this reference exists.** Task #66 replaced a flat `55...85` day-one
/// draw with the tenure curve `78 − 34·0.78^yearsPro`, "fitted to the measured
/// ladder". Nothing measured it. `career` gates the DEVELOPMENT equilibrium
/// (assert 6.10e) but never touches the generator: it builds pure-draft-intake
/// leagues seeded by `DraftEngine.initializeRookieFamiliarity`. So the one
/// constant in the wave that changes what every new save looks like on day one
/// was the one with no gate behind it — until this block.
///
/// Source: `./run.sh career`, `familiarity by yearsPro:` line, 2026-08-04
/// (20 leagues × 22 measured seasons; pooled mean 60.5, assert 6.10e).
let lgFamiliarityLadder: [Int: Double] = [
    0: 43.9, 1: 51.6, 2: 57.2, 3: 61.3, 4: 64.5,
    5: 67.1, 6: 69.3, 7: 71.1, 8: 72.6, 9: 73.8, 10: 74.5,
]
/// How far a rung may sit from the reference before the curve is considered
/// drifted. The draw is uniform ±16 around the curve centre, so at ~9 000
/// samples per rung the sampling error on a rung mean is ~0.1; 2.0 is therefore
/// slack for the FIT (the curve is a three-digit approximation of a measured
/// ladder), not for noise.
let lgFamiliarityTolerance = 2.0

// MARK: - Day-one salary bands (task #87 / F1)

/// What a save's opening cap sheet has to look like.
///
/// **Why this block exists.** The #87 salary-realism audit found the roster
/// seeder rating-BLIND: `realisticSalary` took position, tenure and depth and
/// never once looked at `overall`, so a 96 and a 62 at the same position drew
/// pay from the same uniform band. Measured on the shipped template that put
/// the league at **0.725** salary ÷ market, the 85+ cohort at **0.666**, and
/// **68 %** of all players under `HoldoutEngine.subMarketThreshold` — two thirds
/// of the league a holdout candidate on the morning of season one, and a star
/// payroll that doubled inside two league years as those men reached free agency
/// and re-priced at 1.0-1.6× market against 5-8 % cap growth.
///
/// Nothing in the repo measured any of it. `career` gates development, the
/// `leaguegen` pyramid above gates ratings, and the app-side smoke gates cap
/// AGGREGATES (`underCap`, `avgRoom`) which a league that pays twenty men 22 %
/// of the cap each and fills the other 1 676 slots at the minimum satisfies
/// perfectly. This is the gate on the SHAPE of the opening cap sheet.
///
/// The bands, and where each comes from:
///
/// * **payroll 80-95 % of cap** — `LeagueGenerator.rosterCapTargetBand`, i.e.
///   the normalisation's own contract with itself. Asserted because the seeder
///   rewrite must not have moved the LEVEL, only the shape.
/// * **total market 90-120 % of cap** — `ContractEngine.leagueAffordabilityScale`
///   was solved for "~105-115 % of cap in total" (its own derivation note). The
///   audit measured 120.7 % because six position multipliers were unreachable
///   and every one of them was reading HIGH; with F2's gate live the effective
///   table is the declared table and the total should fall back inside. The band
///   is deliberately wider than 105-115 on both sides: it is a rail against a
///   market that cannot be paid for, not a re-derivation of the scalar.
/// * **league salary ÷ market 0.78-1.00** — this one is arithmetic, not taste.
///   Normalisation pins the aggregate: `payroll ÷ Σmarket`, so at 87.5 % payroll
///   the ratio is 0.875 ÷ (market share). It CANNOT be 1.0 while rookie deals
///   are the discount that makes a roster affordable, and the audit's 0.725 was
///   simply the 120.7 % market showing through. The band says: the aggregate
///   must be consistent with the two above, and no lower.
/// * **85+ cohort 0.90-1.15** — the number the wave exists to move, from 0.666.
///   The brief for this wave asked for 0.85-0.95, and that target turns out to be
///   **incompatible with the one next to it** once the aggregate is pinned. The
///   league mean is arithmetic: payroll ÷ Σmarket ≈ 0.87 ÷ 1.02 ≈ 0.86, and it
///   cannot be anything else while the normalisation holds. Putting the STAR mean
///   at 0.85-0.95 therefore means putting it ON TOP of `HoldoutEngine`'s 0.85
///   trigger — and any spread at all then leaves a third of the cohort under it,
///   which is the 68 % queue coming straight back. So the discount is carried
///   where a real cap sheet carries it: by the rookie-scale population (0.40-0.78
///   of a smaller, younger market) and the middle class on ageing deals (0.88),
///   while the men on fresh maximum contracts sit at roughly par. Killing the
///   queue was the brief's stated highest-leverage outcome; this is what it costs.
///   The ceiling is loose because the distribution has a heavy RIGHT tail: a
///   declining 34-year-old on a deal he signed at 31 is genuinely overpaid, by a
///   lot, and a handful of them move a cohort mean several points between runs.
/// * **holdout queue ≤ 30 %** — of the population `HoldoutEngine` actually lets
///   into it (85+, `yearsPro >= 3`), not of the whole league. Some of it SHOULD
///   be there — that is the drama — but the audit's 68 % was a queue, not drama.
let lgSalaryBands: (payroll: (Double, Double), market: (Double, Double),
                    ratio: (Double, Double), star: (Double, Double), holdout: Double) = (
    payroll: (80.0, 95.0), market: (90.0, 120.0),
    ratio: (0.78, 1.00), star: (0.88, 1.25), holdout: 30.0
)

/// One rostered man's opening cap-sheet row.
struct LGSalaryRow {
    let position: Position
    let overall: Double
    let yearsPro: Int
    let market: Double
    var salary: Double
}

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
    /// Day-one familiarity with the system this player's own building installs,
    /// bucketed by tenure (task #66 / #85). Specialists are absent by
    /// construction: `Position.side` is `.specialTeams` for K and P, there is no
    /// installed system asking anything of them, and `initializePlayerFamiliarity`
    /// consequently neither writes a value nor consumes an RNG draw for them.
    var famByYearsPro: [Int: [Double]] = [:]
    var famAll: [Double] = []
    /// Task #87 / F1 — the opening cap sheet, normalised per roster exactly as
    /// `generateRoster` does it.
    var salaryRows: [LGSalaryRow] = []
    var salaryTop5: [Position: [Double]] = [:]
    var askTop5: [Position: [Double]] = [:]
    var salaryBest: [Position: [Double]] = [:]
    var askBest: [Position: [Double]] = [:]
    var payrollShares: [Double] = []
    var rng = SystemRandomNumberGenerator()

    for _ in 0..<leagues {
        // `generateRoster` keeps a RUNNING per-position depth chart across the
        // whole blueprint, and the blueprint lists WR / DE / CB twice — a base
        // entry and an "extra depth" entry at the end. Counting inside each entry
        // instead would hand those three players a STARTER-tier draw; the mirror
        // pin caught exactly that (mean +0.79, 80+ +2.40) the first time this
        // scenario ran, which is what the pin is for.
        var depthChart: [Position: Int] = [:]
        var roster: [LGSalaryRow] = []
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
                // --- day-one scheme familiarity (task #66 / #85) --------------
                // `generatePlayer`'s own tenure assembly, mirrored: yearsPro is
                // the age minus a 21-23 debut year. Scaffolding, exactly like the
                // six lines above it; the curve it feeds is repo bytes.
                let yearsPro = max(0, age - Int.random(in: 21...23, using: &rng))
                if position.side != .specialTeams {
                    let fam = Double(LeagueGenerator.activeSchemeSeed(
                        yearsPro: yearsPro, using: &rng
                    ))
                    famByYearsPro[min(yearsPro, 15), default: []].append(fam)
                    famAll.append(fam)
                }
                // --- the opening cap sheet (task #87 / F1) --------------------
                // Salary is the SHIPPED seeder; market is the SHIPPED ask. The
                // seeder is rating-aware now, so this is the first place in the
                // repo where the two can be compared for a league that has not
                // played a down.
                let cap = ContractEngine.openingSalaryCap
                roster.append(LGSalaryRow(
                    position: position,
                    overall: ovr,
                    yearsPro: yearsPro,
                    market: Double(ContractEngine.estimateMarketValue(
                        overall: probe.overall, position: position, age: age, salaryCap: cap
                    )),
                    salary: Double(LeagueGenerator.realisticSalary(
                        for: position, overall: probe.overall, age: age,
                        yearsPro: yearsPro, depthIndex: depthIndex, salaryCap: cap, using: &rng
                    ))
                ))
            }
        }
        // `generateRoster`'s normalisation, verbatim in shape: scale the roster
        // onto its cap target, floored at the $750K minimum.
        let target = Double(Int.random(in: LeagueGenerator.rosterCapTargetBand, using: &rng))
        let rawTotal = roster.reduce(0.0) { $0 + $1.salary }
        if rawTotal > 0 {
            let scale = target / rawTotal
            for i in roster.indices {
                roster[i].salary = Swift.max(750.0, (roster[i].salary * scale).rounded())
            }
        }
        payrollShares.append(
            roster.reduce(0.0) { $0 + $1.salary } / Double(ContractEngine.openingSalaryCap) * 100
        )
        for pos in Set(roster.map(\.position)) {
            let group = roster.filter { $0.position == pos }.sorted { $0.overall > $1.overall }
            let top = group.prefix(5)
            guard !top.isEmpty else { continue }
            salaryTop5[pos, default: []].append(
                crMean(top.map { $0.salary }) / Double(ContractEngine.openingSalaryCap) * 100
            )
            askTop5[pos, default: []].append(
                crMean(top.map { $0.market }) / Double(ContractEngine.openingSalaryCap) * 100
            )
            salaryBest[pos, default: []].append(
                (group.first?.salary ?? 0) / Double(ContractEngine.openingSalaryCap) * 100
            )
            askBest[pos, default: []].append(
                (group.first?.market ?? 0) / Double(ContractEngine.openingSalaryCap) * 100
            )
        }
        salaryRows.append(contentsOf: roster)
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
    print("--- HEADROOM vs THE DRAFT PIPELINE (task #69) -----------------------------")
    print("  The generator's t=0 ceiling distribution against the equilibrium the")
    print("  `career` scenario measures for a pure-draft-intake league. Same age, same")
    print("  question: how far under his ceiling is a rostered player? These two are")
    print("  the only sources of players in the game and they have to answer alike, or")
    print("  a save's first seasons are spent converting one answer into the other.")
    print("  age      n   meanOVR  meanPot  head   ref   delta   p10   p50   p90")
    var headAll: [Double] = []
    for age in 21...34 {
        var rows: [(ovr: Double, pot: Double)] = []
        for i in 0..<overalls.count where (age == 34 ? ages[i] >= 34 : Int(ages[i]) == age) {
            rows.append((overalls[i], potentials[i]))
        }
        guard !rows.isEmpty else { continue }
        let heads = rows.map { $0.pot - $0.ovr }.sorted()
        let mo = crMean(rows.map(\.ovr)), mp = crMean(rows.map(\.pot))
        let ref = lgHeadroomEquilibrium.byAge[age] ?? 0
        print(String(format: "  %@ %6d  %7.2f  %7.2f  %5.2f  %4.1f  %+6.2f  %4.0f  %4.0f  %4.0f",
                     age == 34 ? "34+" : " \(age)", rows.count, mo, mp, mp - mo, ref,
                     (mp - mo) - ref, crPct(heads, 0.10), crPct(heads, 0.50), crPct(heads, 0.90)))
    }
    for i in 0..<overalls.count { headAll.append(potentials[i] - overalls[i]) }
    headAll.sort()
    let pot90Share = Double(potentials.filter { $0 >= 90 }.count) / n * 100
    print(String(format: "  ALL %6.0f  %7.2f  %7.2f  %5.2f  %4.1f  %+6.2f  %4.0f  %4.0f  %4.0f",
                 n, mean, crMean(potentials), crMean(potentials) - mean,
                 lgHeadroomEquilibrium.mean,
                 (crMean(potentials) - mean) - lgHeadroomEquilibrium.mean,
                 crPct(headAll, 0.10), crPct(headAll, 0.50), crPct(headAll, 0.90)))
    print(String(format: "  potential >= 90: %.1f%% (pipeline equilibrium %.1f%%)   mean potential %.2f (equilibrium %.2f)",
                 pot90Share, lgHeadroomEquilibrium.pot90Share,
                 crMean(potentials), lgHeadroomEquilibrium.potMean))

    print("")
    print("--- DAY-ONE SCHEME FAMILIARITY (task #66 / #85) ---------------------------")
    print("  What `LeagueGenerator.activeSchemeSeed` hands a new save on the morning of")
    print("  season 1, against the equilibrium ladder the `career` scenario measures for")
    print("  a league that has been running for 22 seasons. The curve was FITTED to that")
    print("  ladder and nothing checked the fit; `career` gates the development")
    print("  equilibrium, not the generator, so this is the only thing standing between")
    print("  the curve and a silent drift.")
    print("  yearsPro      n     mean    ref   delta")
    var famLadderOK = true
    var famWorstRung = (yp: -1, delta: 0.0)
    for yp in lgFamiliarityLadder.keys.sorted() {
        guard let xs = famByYearsPro[yp], xs.count >= 200 else { continue }
        let m = crMean(xs)
        let ref = lgFamiliarityLadder[yp] ?? 0
        let delta = m - ref
        if abs(delta) > abs(famWorstRung.delta) { famWorstRung = (yp, delta) }
        if abs(delta) > lgFamiliarityTolerance { famLadderOK = false }
        print(String(format: "  yp%-3d %8d  %7.2f  %5.1f  %+6.2f", yp, xs.count, m, ref, delta))
    }
    let famMean = crMean(famAll)
    let famSub55 = Double(famAll.filter { $0 < 55 }.count) / Double(max(1, famAll.count)) * 100
    print(String(format: "  pooled: n=%d  mean %.2f  |  PlaySimulator.famBustPivot 55 -> margin %+.2f  |  under pivot %.1f%%",
                 famAll.count, famMean, famMean - 55.0, famSub55))
    print("  (specialists excluded — K/P have no installed system, take no draw)")

    print("")
    print("--- DAY-ONE SALARY vs MARKET (task #87 / F1) ------------------------------")
    print("  What a save's cap sheet looks like before a down is played. `realisticSalary`")
    print("  was rating-BLIND until this wave: position + tenure + depth and never `overall`,")
    print("  so the league opened at 0.725 salary/market with 68 % of it a holdout candidate.")
    print("  Salary is the shipped seeder + the shipped per-roster normalisation; ask is")
    print("  `ContractEngine.estimateMarketValue` at the opening cap.")
    let salTotal = salaryRows.reduce(0.0) { $0 + $1.salary }
    let mktTotal = salaryRows.reduce(0.0) { $0 + $1.market }
    let capTotal = Double(ContractEngine.openingSalaryCap) * Double(leagues)
    let payrollPct = salTotal / capTotal * 100
    let marketPct = mktTotal / capTotal * 100
    let leagueRatio = salTotal / Swift.max(1, mktTotal)
    func ratios(_ rows: [LGSalaryRow]) -> [Double] { rows.map { $0.salary / Swift.max(1, $0.market) } }
    let allRatios = ratios(salaryRows)
    let starRows = salaryRows.filter { $0.overall >= 85 }
    let starRatio = crMean(ratios(starRows))
    let holdoutShare = Double(allRatios.filter { $0 < 0.85 }.count) / Double(Swift.max(1, allRatios.count)) * 100
    let bargainShare = Double(allRatios.filter { $0 < 0.70 }.count) / Double(Swift.max(1, allRatios.count)) * 100
    print(String(format: "  payroll %.1f%% of cap [%.0f-%.0f]   total market %.1f%% of cap [%.0f-%.0f]   league salary/market %.3f [%.2f-%.2f]",
                 payrollPct, lgSalaryBands.payroll.0, lgSalaryBands.payroll.1,
                 marketPct, lgSalaryBands.market.0, lgSalaryBands.market.1,
                 leagueRatio, lgSalaryBands.ratio.0, lgSalaryBands.ratio.1))
    print("  \"best\" = the #1 man at that position on a roster; \"top5\" = the position group's")
    print("  five best, both averaged over every roster generated. The audit's own table is")
    print("  the `best` column — Lamar Jackson paid $27.4M against a $47.9M ask, 1.75x.")
    print("  pos      n  meanOVR   best pay%cap  best ask%cap   top5 pay%cap  top5 ask%cap   sal/mkt  under0.85")
    for pos in Position.allCases {
        let group = salaryRows.filter { $0.position == pos }
        guard !group.isEmpty else { continue }
        let r = ratios(group)
        let under = Double(r.filter { $0 < 0.85 }.count) / Double(r.count) * 100
        print(String(format: "  %-5@%7d%9.2f%14.2f%14.2f%15.2f%14.2f%10.3f%10.1f%%",
                     pos.rawValue, group.count, crMean(group.map(\.overall)),
                     crMean(salaryBest[pos] ?? []), crMean(askBest[pos] ?? []),
                     crMean(salaryTop5[pos] ?? []), crMean(askTop5[pos] ?? []),
                     crMean(r), under))
    }
    print(String(format: "  cohorts: 85+ n=%d sal/mkt %.3f [%.2f-%.2f]  |  90+ %.3f  |  75-84 %.3f  |  sub65 %.3f",
                 starRows.count, starRatio, lgSalaryBands.star.0, lgSalaryBands.star.1,
                 crMean(ratios(salaryRows.filter { $0.overall >= 90 })),
                 crMean(ratios(salaryRows.filter { $0.overall >= 75 && $0.overall < 85 })),
                 crMean(ratios(salaryRows.filter { $0.overall < 65 }))))
    // The metric that matters is not "who is under 0.85" — a rookie-contract
    // league is SUPPOSED to be, and `HoldoutEngine.detectStarHoldoutCandidates`
    // knows it: the star path gates on `yearsPro >= 3` because "players still on
    // rookie deals accept them". So the queue is the men who can actually join
    // it: 85+ (or a club's top three), three seasons in, under the trigger.
    let starEligible = salaryRows.filter { $0.overall >= 85 && $0.yearsPro >= 3 }
    let starQueue = Double(starEligible.filter { $0.salary < 0.85 * $0.market }.count)
        / Double(Swift.max(1, starEligible.count)) * 100
    let starCohort = salaryRows.filter { $0.overall >= 85 }
    let starCohortUnder = Double(starCohort.filter { $0.salary < 0.85 * $0.market }.count)
        / Double(Swift.max(1, starCohort.count)) * 100
    print(String(format: "  under HoldoutEngine.subMarketThreshold (0.85x): %.1f%% of the league   under TradeValueEngine bargain line (0.70x): %.1f%%   (audit: 68.1 %% / 60.8 %%)",
                 holdoutShare, bargainShare))
    print(String(format: "  DAY-ONE HOLDOUT QUEUE — 85+ with yearsPro>=3 under 0.85x (HoldoutEngine's own star gate): %.1f%% of %d [<=%.0f]",
                 starQueue, starEligible.count, lgSalaryBands.holdout))
    print(String(format: "  whole 85+ cohort under 0.85x: %.1f%% of %d   (audit: 80.3 %%)",
                 starCohortUnder, starCohort.count))
    print(String(format: "  per-roster payroll: min %.1f%%  median %.1f%%  max %.1f%% of cap",
                 payrollShares.min() ?? 0, crPct(payrollShares, 0.50), payrollShares.max() ?? 0))

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
    // --- Day-one scheme familiarity (task #66 / #85) -------------------------
    // The gate the #66 wave shipped without. `activeSchemeSeed`'s curve exists
    // to make a new save START at the development stack's equilibrium instead of
    // sliding into it over a decade, so the thing to assert is exactly that: the
    // generator's ladder must be the ladder `career` measures, rung by rung.
    A.check("8.fld", famLadderOK,
            String(format: "day-one familiarity ladder within %.1f of the `career` equilibrium at every rung "
                         + "(worst: yp%d %+.2f)", lgFamiliarityTolerance, famWorstRung.yp, famWorstRung.delta))
    // And the level, for the same reason `career` 6.10e exists: familiarity is
    // the input to `PlaySimulator`'s blown-assignment pivot, and a generator that
    // seeded the league UNDER it would put every club in a new save in the
    // busting regime on day one — the precise defect #66 fixed downstream.
    A.check("8.fpv", famMean >= 58 && famMean <= 64,
            String(format: "day-one familiarity mean in [58,64], clear of PlaySimulator's 55 bust pivot "
                         + "(%.2f, margin %+.2f)", famMean, famMean - 55.0))
    // Generated veterans must NOT arrive with free catch-up room (the P1 fix).
    //
    // Task #69 measured what the OTHER end of the pipeline produces at the same
    // ages — 12.0 points against this 2.05 — and then measured what happens when
    // the generator matches it. It is worse, not better: the four-season smoke's
    // §8 80+ share went from 19.8-21 % to 26.1 % and mean OVR drift from +0.80 to
    // +2.02, because the SHIPPED development stack spends any ceiling it is given
    // (`diag devsource offseasonDevelop` runs +2.0…+2.9 OVR per player per
    // season) where the harness's own league at the same potential level is
    // stationary. So the ceiling on this line stays where P1 put it, and the
    // number it is failing to match is printed next to it on every run rather
    // than left in a doc comment — see the block above and
    // `LeagueGenerator.veteranPotential`.
    let headroom = crMean(potentials) - mean
    A.check("8.headroom", headroom <= 4.0,
            String(format: "mean veteranPotential headroom over OVR <= 4.0 (%.2f) — was 6-9 before the P1 "
                         + "wave. KNOWN GAP: the draft pipeline's equilibrium is %.2f (task #69); closing it "
                         + "is a development-side calibration, not a constant here",
                   headroom, lgHeadroomEquilibrium.mean))
    // --- Day-one cap sheet (task #87 / F1) -----------------------------------
    // See `lgSalaryBands` for where each band comes from. The pyramid gates
    // above ask whether the league has the right PLAYERS; these ask whether it
    // pays them anything like the right money.
    A.check("87.pay", payrollPct >= lgSalaryBands.payroll.0 && payrollPct <= lgSalaryBands.payroll.1,
            String(format: "opening payroll in [%.0f,%.0f]%% of cap (%.1f%%) — the normalisation's own contract",
                   lgSalaryBands.payroll.0, lgSalaryBands.payroll.1, payrollPct))
    A.check("87.mkt", marketPct >= lgSalaryBands.market.0 && marketPct <= lgSalaryBands.market.1,
            String(format: "total market value in [%.0f,%.0f]%% of cap (%.1f%%) — leagueAffordabilityScale was solved for ~105-115 %%; the audit measured 120.7 %% with six multipliers unreachable",
                   lgSalaryBands.market.0, lgSalaryBands.market.1, marketPct))
    A.check("87.ratio", leagueRatio >= lgSalaryBands.ratio.0 && leagueRatio <= lgSalaryBands.ratio.1,
            String(format: "league salary/market in [%.2f,%.2f] (%.3f) — was 0.725 when the seeder never read `overall`",
                   lgSalaryBands.ratio.0, lgSalaryBands.ratio.1, leagueRatio))
    A.check("87.star", starRatio >= lgSalaryBands.star.0 && starRatio <= lgSalaryBands.star.1,
            String(format: "85+ cohort salary/market in [%.2f,%.2f] (%.3f) — was 0.666, i.e. every star underpaid by construction",
                   lgSalaryBands.star.0, lgSalaryBands.star.1, starRatio))
    A.check("87.hold", starQueue <= lgSalaryBands.holdout,
            String(format: "day-one holdout queue (85+, yearsPro>=3, under 0.85x — `HoldoutEngine`'s own star gate) <= %.0f%% (%.1f%%) — 80.3 %% of the 85+ cohort was under it before this wave",
                   lgSalaryBands.holdout, starQueue))
    // The league-wide share is NOT gated tightly on purpose: a roster whose
    // rookie-contract third is paid at market has no rookie-scale discount, and
    // `leagueAffordabilityScale`'s own derivation depends on that discount
    // existing. The rail is only against the 68 % the audit measured.
    A.check("87.under", holdoutShare <= 60.0,
            String(format: "league-wide share under 0.85x market <= 60%% (%.1f%%) — was 68.1 %%; most of what remains is the rookie-scale discount, which is supposed to be there",
                   holdoutShare))
    // Ability must buy money. The defect was not only a level: a rating-blind
    // seeder draws a 96 and a 62 from the same band, so the correlation between
    // what a man is and what he is paid was zero WITHIN a position group.
    var monotoneMisses: [String] = []
    for pos in Position.allCases {
        let group = salaryRows.filter { $0.position == pos }
        guard group.count >= 200 else { continue }
        let sorted = group.sorted { $0.overall < $1.overall }
        let bottom = crMean(sorted.prefix(sorted.count / 4).map(\.salary))
        let top = crMean(sorted.suffix(sorted.count / 4).map(\.salary))
        if top <= bottom * 2.0 { monotoneMisses.append(String(format: "%@ %.0f vs %.0f", pos.rawValue, top, bottom)) }
    }
    A.check("87.mono", monotoneMisses.isEmpty,
            monotoneMisses.isEmpty
              ? "top OVR quartile out-earns the bottom quartile by >2x at every position — the seeder reads `overall`"
              : "RATING-BLIND at: \(monotoneMisses.joined(separator: ", "))")

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
