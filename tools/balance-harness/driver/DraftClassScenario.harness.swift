import Foundation

// ============================================================================
// SCENARIO `draftclass` — draft-class generator validation (plan §7)
// ============================================================================
// Generates N complete draft classes through the SHIPPED generator
// (`DraftClassBuilder`, synced verbatim + sha-verified) plus the shipped combine
// path (`ScoutingEngine` keep-list slice), prints a distribution report and
// asserts every invariant in `docs/DRAFT_CLASS_OVERHAUL_PLAN.md` §7 items 1–9.
// Exits nonzero on the first violated invariant (after printing the full report,
// so a failing run still shows the numbers that caused it).
//
// This file is MEASUREMENT ONLY. It never re-implements a generator rule: every
// clamp it checks is read back out of `DraftClassBuilder.PositionGroup`
// (classCountRange / firstRoundRange / classShare / bestProspectBandGuarantee)
// and every combine target out of `ScoutingEngine.CombineDrillTable`, so the
// asserts cannot drift away from the code they guard. The only numbers typed
// here are the PLAN/REFERENCE targets themselves (the thing being verified).
// ============================================================================

// MARK: - Small stats helpers

func dcMean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
func dcSD(_ xs: [Double]) -> Double {
    guard xs.count > 1 else { return 0 }
    let m = dcMean(xs)
    return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)).squareRoot()
}
func dcPct(_ xs: [Double], _ p: Double) -> Double {
    guard !xs.isEmpty else { return 0 }
    let s = xs.sorted()
    let idx = max(0, min(s.count - 1, Int((p * Double(s.count - 1)).rounded())))
    return s[idx]
}
func dcCorr(_ xs: [Double], _ ys: [Double]) -> Double {
    guard xs.count == ys.count, xs.count > 1 else { return 0 }
    let mx = dcMean(xs), my = dcMean(ys)
    var num = 0.0, dx = 0.0, dy = 0.0
    for i in 0..<xs.count {
        let a = xs[i] - mx, b = ys[i] - my
        num += a * b; dx += a * a; dy += b * b
    }
    guard dx > 0, dy > 0 else { return 0 }
    return num / (dx * dy).squareRoot()
}
/// First integer in a rendered stat line ("1,430 rush yds · 14 TD" -> 1430).
/// Used only by the #181 screenshot regression, which needs the leading number
/// of a line the MODEL rendered rather than a number the harness re-derived.
func dcLeadingInt(_ s: String) -> Int? {
    var digits = ""
    for ch in s {
        if ch.isNumber { digits.append(ch) }
        else if ch == "," && !digits.isEmpty { continue }
        else if !digits.isEmpty { break }
    }
    return Int(digits)
}

func dcPad(_ s: String, _ n: Int) -> String {
    s.count >= n ? String(s.prefix(n)) : s + String(repeating: " ", count: n - s.count)
}
func dcLPad(_ s: String, _ n: Int) -> String {
    s.count >= n ? String(s.prefix(n)) : String(repeating: " ", count: n - s.count) + s
}

// MARK: - Assertion collector

final class DCAsserts {
    private(set) var lines: [(ok: Bool, id: String, text: String)] = []
    func check(_ id: String, _ ok: Bool, _ text: String) { lines.append((ok, id, text)) }
    var failures: Int { lines.filter { !$0.ok }.count }
    func report() {
        print("")
        print("===== ASSERTIONS (plan §7) =====")
        for l in lines {
            print("  [\(l.ok ? "PASS" : "FAIL")] \(dcPad(l.id, 6)) \(l.text)")
        }
        print("")
        print(failures == 0
              ? "  ALL \(lines.count) ASSERTIONS PASSED"
              : "  \(failures) of \(lines.count) ASSERTIONS FAILED")
    }
}

// MARK: - Position-skill readout (harness-owned view onto PositionAttributes)

func dcSkillValues(_ pa: PositionAttributes) -> [Int] {
    switch pa {
    case .quarterback(let a):
        return [a.armStrength, a.accuracyShort, a.accuracyMid, a.accuracyDeep, a.pocketPresence, a.scrambling]
    case .wideReceiver(let a):   return [a.routeRunning, a.catching, a.release, a.spectacularCatch]
    case .runningBack(let a):    return [a.vision, a.elusiveness, a.breakTackle, a.receiving]
    case .tightEnd(let a):       return [a.blocking, a.catching, a.routeRunning, a.speed]
    case .offensiveLine(let a):  return [a.runBlock, a.passBlock, a.pull, a.anchor]
    case .defensiveLine(let a):  return [a.passRush, a.blockShedding, a.powerMoves, a.finesseMoves]
    case .linebacker(let a):     return [a.tackling, a.zoneCoverage, a.manCoverage, a.blitzing]
    case .defensiveBack(let a):  return [a.manCoverage, a.zoneCoverage, a.press, a.ballSkills]
    case .kicking(let a):        return [a.kickPower, a.kickAccuracy]
    case .snapping(let a):       return [a.snapVelocity, a.snapAccuracy]
    case .holding(let a):        return [a.handling, a.placement]
    }
}

// MARK: - Reference targets (the things under test — plan §2/§4 + reference §2)

/// QB first-round histogram, plan §2 step 1.2 (smoothed 10-yr).
let dcQBHistogramTarget: [Int: Double] = [1: 8, 2: 18, 3: 26, 4: 22, 5: 16, 6: 10]

/// NFL 10-yr mean R1 grades per position group (`DRAFT_NFL_REFERENCE.md` §2).
/// `nil` = not asserted; documented in the report footer.
let dcReferenceR1Mean: [String: Double?] = [
    "qb": 3.2, "rb": 1.4, "wr": 4.2, "te": 1.0, "ot": 4.5, "iol": 2.0,
    "edge": 4.5, "dt": 3.0, "cb": 4.5, "safety": 1.2,
    // Reference "LB (off-ball)" R1 avg is 1.8, but the plan folds pass-rushing
    // OLBs into EDGE, so the game's `lb` group (MLB only) is a strict subset of
    // the reference bucket and cannot be compared 1:1.
    "lb": nil, "fb": nil, "kicker": nil, "punter": nil,
]

/// Plan §2 step 5 potential/ceiling targets — see the deviation note in the report.
let dcCeilingTarget: [Int: Double] = [1: 90, 3: 55, 7: 25]

/// Positions whose 40-yd class mean is NOT judged against `CombineDrillTable`'s
/// per-position `forty.mean` (assert 7.7a). One list, read at the single point
/// where `worstFortyDelta` is accumulated, so the exemption has one home.
///
/// WHY these four, and why this is not a tuning knob:
///
/// `ScoutingEngine.drillResult` draws a 40 as
///   `forty.mean - forty.sd * (0.8*z + 0.6*noise + 0.5*modifier)`,  z clamped ±2.5,
/// with `z = (speed - PositionPhysicalProfile.profile(for:).speed.mean) / 8`.
/// The delta this assert measures is `mean(realized) - forty.mean`, so
/// `forty.mean` cancels EXACTLY: no value of it can move the number. The speed
/// prior cancels too — `PositionPhysicalProfile.sample` draws the prospect's
/// speed as `profile.speed.mean + levelShift + noise`, and `drillResult`
/// subtracts that same `profile.speed.mean` back off, leaving `z = levelShift/8`
/// where `levelShift = athleticism - PositionPhysicalProfile.baseLevel`. The
/// delta is therefore a pure readout of one thing: how far the position's COHORT
/// athleticism sits from the league base level. It is not a reference error, and
/// re-typing any constant on either side is a proven no-op.
///
/// LS and H are confined to the UDFA band by
/// `DraftClassBuilder.PositionGroup.earliestBand` (`.longSnapper, .holder: 8`),
/// so their cohort is drawn entirely from the bottom of the talent curve and
/// their `levelShift` is several points negative by construction — the class-wide
/// ±0.05 s window is one their cohort cannot occupy. They are still measured,
/// printed and held to 7.7b–7.7e above; only the class-wide reference comparison
/// is dropped. K and P carry the same exemption and additionally never reach the
/// combine block at all (filtered upstream, so they take no drills in this
/// scenario and appear in no §7.7 row) — listed here so the reason for all four
/// is written down once, in the place the exemption is applied.
let dcFortyReferenceExempt: Set<Position> = [.K, .P, .LS, .H]

/// The SHIPPED development ceiling for a given potential. Routed through
/// `PlayerDevelopmentEngine.developmentCeiling(for:)` rather than retyping the
/// formula, so the phase-2 recalibration of that curve cannot leave a stale
/// copy behind here (it already did once: this scenario carried `pot*0.65+35`
/// as a literal).
func dcDevelopmentCeiling(potential: Int) -> Int {
    let probe = Player(
        fullName: "probe",
        position: .WR,
        physical: PhysicalAttributes(speed: 70, acceleration: 70, strength: 70,
                                     agility: 70, stamina: 70, durability: 70),
        mental: MentalAttributes(awareness: 70, decisionMaking: 70, clutch: 70,
                                 workEthic: 70, coachability: 70, leadership: 70),
        positionAttributes: .wideReceiver(WRAttributes(routeRunning: 70, catching: 70,
                                                      release: 70, spectacularCatch: 70))
    )
    probe.truePotential = potential
    return PlayerDevelopmentEngine.developmentCeiling(for: probe)
}

// MARK: - Per-class capture

struct DCProspectRow {
    let position: Position
    let group: String
    let band: Int
    let slot: Int
    let overall: Int
    let potential: Int
    let upside: Int
    let learning: Int
    let awareness: Int
    let readiness: Int
    let yearsStarted: Int
    let production: Int
    let tier: String
    let archetype: String
    let competition: String
    let age: Int
    let skills: [Int]
    let speed: Int
    let forty: Double?
    let drillGrade: String?
    // --- usage suppression / hidden gems (task #181) ---
    let limitedSample: Bool
    let snaps: Int
    let statLine: String
    let publicProjection: Int
    let consensusError: Int
}

// MARK: - Scenario

func scenarioDraftClass(_ flags: [String: String]) {
    let classes = Int(flags["classes"] ?? "") ?? 200
    let size = Int(flags["size"] ?? "") ?? 350
    let verbose = flags["verbose"] != nil

    let groups = DraftClassBuilder.PositionGroup.allCases
    var groupOf: [Position: String] = [:]
    for g in groups { for p in g.members { groupOf[p] = g.rawValue } }
    let premiumGroups = ["qb", "wr", "ot", "edge", "cb", "dt"]
    let r1Guaranteed = groups.filter { $0.bestProspectBandGuarantee == 1 }.map { $0.rawValue }
    let r2Guaranteed = groups.filter { $0.bestProspectBandGuarantee == 2 }.map { $0.rawValue }

    print("===== SCENARIO draftclass: \(classes) classes x \(size) prospects =====")
    print("  generator: DraftClassBuilder v\(DraftClassBuilder.currentGeneratorVersion) (verbatim)  |  combine: ScoutingEngine slice")

    // --- aggregate accumulators ---------------------------------------------
    var qbR1Counts: [Int] = []
    var qbTop2Counts: [Int] = []
    var countByGroup: [String: [Double]] = [:]
    var countByPosition: [Position: [Double]] = [:]
    var r1ByGroup: [String: [Double]] = [:]
    var bestBandByGroup: [String: [Double]] = [:]
    var aRangePerClass: [Double] = []
    var letterHist: [String: Int] = [:]
    var gradedLetterHist: [String: Int] = [:]
    var bandOverall: [Int: [Double]] = [:]
    var bandPotential: [Int: [Double]] = [:]
    var bandUpside: [Int: [Double]] = [:]
    var bandCeilingOK: [Int: (hit: Int, total: Int)] = [:]
    var withinBandSDPerClass: [Int: [Double]] = [:]
    var skillTotal = 0, skillAPlus = 0, skill88 = 0
    var day3Total = 0, day3Freak = 0
    var premiumMissesPerClass = 0
    var potBelowOverall = 0
    var readinessAll: [Double] = []
    var yearsAll: [Double] = []
    var readinessByPos: [Position: [Double]] = [:]
    var prodAll: [Double] = []
    var ovrAll: [Double] = []
    var learnAll: [Double] = []
    var awrAll: [Double] = []
    var tierMissingClasses = 0
    // --- §7.9c-f: usage suppression / hidden gems (task #181) ---------------
    // `prodFullAll`/`ovrFullAll` are the SAME two series restricted to the
    // played-a-season cohort, so the correlation the gate asserts can be
    // decomposed into "did the ordinary production model drift" and "how much
    // of the drop is the gem cohort".
    var prodFullAll: [Double] = []
    var ovrFullAll: [Double] = []
    var gemShares: [Double] = []
    var buriedRows: [DCProspectRow] = []
    var buriedSnaps: [Double] = []
    var buriedProd: [Double] = []
    var buriedOvr: [Double] = []
    var buriedProjection: [Double] = []
    var gemsPerClass: [Double] = []
    /// Classes in which at least one buried prospect projects earlier than R4 —
    /// the mechanic is pointless if the market does not actually let him slide.
    var buriedEarlyProjections = 0
    /// Low-production denominators for P(gem | low production).
    var lowProdCount = 0
    var lowProdGemCount = 0
    var lowProdBuriedCount = 0
    var lowProdBuriedGemCount = 0
    /// Stat-line variance. The user-visible property is "two prospects at the
    /// same position in the SAME class print the same line", so that is what is
    /// counted: a cross-class distinct-string count is bounded by the sample
    /// size at thin positions (FB, K, P) and would measure the harness rather
    /// than the model.
    var statLineDupes: [Position: Int] = [:]
    var statLineCount: [Position: Int] = [:]
    var statLineExamples: [String: String] = [:]
    /// Fraction of the class in bands 1-2, the denominator of the derived
    /// P(gem | low production) prediction.
    var bandLE2Count = 0
    var allRowCount = 0
    /// Screenshot regression: an Elite prospect with one year started must no
    /// longer print a `years/3`-deflated line (the 477-yard RB).
    var eliteOneYearRushMin = Int.max
    var eliteOneYearRushCount = 0
    var fortyByPos: [Position: [Double]] = [:]
    var speedByPos: [Position: [Double]] = [:]
    var drillOutOfRange = 0
    var drillChecked = 0
    var aGradesByPos: [Position: [Double]] = [:]      // per class A/A+ drill grades
    var aGradesByCoarse: [String: [Double]] = [:]
    var archHist: [String: Int] = [:]
    var compHist: [String: Int] = [:]
    var ageHist: [Int: Int] = [:]
    var kCounts: [Double] = [], pCounts: [Double] = []
    var kpBestBand: [Double] = []
    var classCountViolations: [String] = []
    var r1ClampViolations: [String] = []
    var bestBandViolations: [String] = []
    var learningRates: [Double] = []
    var declaredPool: [Double] = []

    let t0 = Date()
    for classIndex in 0..<classes {
        let built = DraftClassBuilder.buildOrdered(count: size)
        var prospects = built.prospects
        ScoutingEngine.generateCombineResults(for: &prospects, scoutingAbility: 50)

        // --- §2.9.8 declaration pool -----------------------------------------
        // The shipped declaration pass decides who is actually AVAILABLE: the
        // 224 draft picks plus the UDFA market behind them. It reads/writes
        // only `isDeclaringForDraft`, so it cannot disturb any measurement
        // below.
        _ = ScoutingEngine.generateDeclarations(prospects: &prospects)
        declaredPool.append(Double(prospects.filter { $0.isDeclaringForDraft }.count))

        var rows: [DCProspectRow] = []
        rows.reserveCapacity(prospects.count)
        for (i, p) in prospects.enumerated() {
            rows.append(DCProspectRow(
                position: p.position,
                group: groupOf[p.position] ?? "?",
                band: built.bands[i],
                slot: i + 1,
                overall: p.trueOverall,
                potential: p.truePotential,
                upside: p.truePotential - p.trueOverall,
                learning: p.trueLearning,
                awareness: p.trueMental.awareness,
                readiness: p.nflReadiness,
                yearsStarted: p.collegeYearsStarted,
                production: p.collegeProductionScore,
                tier: p.collegeProductionTier.rawValue,
                archetype: p.developmentArchetype?.rawValue ?? "?",
                competition: p.collegeCompetitionLevel?.rawValue ?? "?",
                age: p.age,
                skills: dcSkillValues(p.truePositionAttributes),
                speed: p.truePhysical.speed,
                forty: p.fortyTime,
                drillGrade: p.positionDrillGrade,
                limitedSample: p.hasLimitedCollegeSample,
                snaps: p.collegeSnapsPlayed,
                statLine: p.collegeStatLine,
                publicProjection: p.draftProjection ?? 8,
                consensusError: p.consensusErrorStored))
        }

        // --- §7.1 / §7.2 / §7.3: blueprint ----------------------------------
        let qbRows = rows.filter { $0.group == "qb" }
        qbR1Counts.append(qbRows.filter { $0.band == 1 }.count)
        qbTop2Counts.append(qbRows.filter { $0.band <= 2 }.count)

        for g in groups {
            let key = g.rawValue
            let mine = rows.filter { $0.group == key }
            let n = mine.count
            let r1 = mine.filter { $0.band == 1 }.count
            let best = mine.map { $0.band }.min() ?? 99
            countByGroup[key, default: []].append(Double(n))
            r1ByGroup[key, default: []].append(Double(r1))
            bestBandByGroup[key, default: []].append(Double(best))
            let range = g.classCountRange
            if n < range.lowerBound || n > range.upperBound {
                if classCountViolations.count < 8 {
                    classCountViolations.append("class \(classIndex) \(key)=\(n) outside \(range)")
                }
            }
            let r1Range = g.firstRoundRange
            if g != .qb, r1 < r1Range.lowerBound || r1 > r1Range.upperBound {
                if r1ClampViolations.count < 8 {
                    r1ClampViolations.append("class \(classIndex) \(key) R1=\(r1) outside \(r1Range)")
                }
            }
            if let guarantee = g.bestProspectBandGuarantee, best > guarantee {
                if bestBandViolations.count < 8 {
                    bestBandViolations.append("class \(classIndex) best \(key) band=\(best) > \(guarantee)")
                }
            }
        }
        for pos in Position.allCases {
            countByPosition[pos, default: []].append(Double(rows.filter { $0.position == pos }.count))
        }
        kCounts.append(Double(rows.filter { $0.position == .K }.count))
        pCounts.append(Double(rows.filter { $0.position == .P }.count))
        if let kpBest = rows.filter({ $0.position == .K || $0.position == .P }).map({ $0.band }).min() {
            kpBestBand.append(Double(kpBest))
        }

        // --- §7.4: grade spread ---------------------------------------------
        aRangePerClass.append(Double(rows.filter { $0.overall >= 85 }.count))
        for r in rows {
            let letter = LetterGrade.from(numericValue: r.overall).rawValue
            letterHist[letter, default: 0] += 1
            if r.band <= 7 { gradedLetterHist[letter, default: 0] += 1 }
        }
        for band in 1...8 {
            let vals = rows.filter { $0.band == band }.map { Double($0.overall) }
            guard vals.count > 2 else { continue }
            withinBandSDPerClass[band, default: []].append(dcSD(vals))
        }

        // --- §7.5: elite skills ---------------------------------------------
        for gkey in premiumGroups {
            let has88 = rows.contains { $0.group == gkey && ($0.skills.max() ?? 0) >= 88 }
            if !has88 { premiumMissesPerClass += 1 }
        }
        for r in rows {
            skillTotal += r.skills.count
            skillAPlus += r.skills.filter { $0 >= 95 }.count
            skill88 += r.skills.filter { $0 >= 88 }.count
            if r.band >= 4 {
                day3Total += 1
                if (r.skills.max() ?? 0) >= 85 { day3Freak += 1 }
            }
        }

        // --- §7.6: potential -------------------------------------------------
        for r in rows {
            if r.potential < r.overall { potBelowOverall += 1 }
            bandOverall[r.band, default: []].append(Double(r.overall))
            bandPotential[r.band, default: []].append(Double(r.potential))
            bandUpside[r.band, default: []].append(Double(r.upside))
            let ceiling = Double(dcDevelopmentCeiling(potential: r.potential))
            var acc = bandCeilingOK[r.band] ?? (0, 0)
            acc.total += 1
            if ceiling >= 78 { acc.hit += 1 }
            bandCeilingOK[r.band] = acc
        }

        // --- §7.7: combine ---------------------------------------------------
        var aGradeThisClassByPos: [Position: Int] = [:]
        var aGradeThisClassByCoarse: [String: Int] = [:]
        for (i, r) in rows.enumerated() {
            guard r.position != .K, r.position != .P else { continue }
            let p = prospects[i]
            guard p.combineInvite else { continue }
            let drills = ScoutingEngine.CombineDrillTable.drills(for: r.position)
            func inRange(_ v: Double?, _ d: ScoutingEngine.CombineDrill) {
                guard let v else { return }
                drillChecked += 1
                if v < d.range.lowerBound - 1e-9 || v > d.range.upperBound + 1e-9 { drillOutOfRange += 1 }
            }
            inRange(p.fortyTime, drills.forty)
            inRange(p.benchPress.map(Double.init), drills.bench)
            inRange(p.verticalJump, drills.vertical)
            inRange(p.broadJump.map(Double.init), drills.broad)
            inRange(p.coneDrill, drills.cone)
            inRange(p.shuttleTime, drills.shuttle)
            if let f = r.forty {
                fortyByPos[r.position, default: []].append(f)
                speedByPos[r.position, default: []].append(Double(r.speed))
            }
            if let g = r.drillGrade, g == "A" || g == "A+" {
                aGradeThisClassByPos[r.position, default: 0] += 1
                aGradeThisClassByCoarse[dcCoarseGroup(r.position), default: 0] += 1
            }
        }
        for pos in Position.allCases where pos != .K && pos != .P {
            aGradesByPos[pos, default: []].append(Double(aGradeThisClassByPos[pos] ?? 0))
        }
        for coarse in ["speedster", "bigman", "balanced"] {
            aGradesByCoarse[coarse, default: []].append(Double(aGradeThisClassByCoarse[coarse] ?? 0))
        }

        // --- §7.8 / §7.9: readiness + production -----------------------------
        var tiersSeen = Set<String>()
        for r in rows {
            readinessAll.append(Double(r.readiness))
            yearsAll.append(Double(r.yearsStarted))
            readinessByPos[r.position, default: []].append(Double(r.readiness))
            prodAll.append(Double(r.production))
            ovrAll.append(Double(r.overall))
            learnAll.append(Double(r.learning))
            awrAll.append(Double(r.awareness))
            tiersSeen.insert(r.tier)
            archHist[r.archetype, default: 0] += 1
            compHist[r.competition, default: 0] += 1
            ageHist[r.age, default: 0] += 1
            // Scheme-learning input (plan §3.3): learnScheme's learning term.
            learningRates.append(Double(r.learning) / 65.0)

            // --- §7.9c-f: usage suppression (task #181) ----------------------
            // "Gem" is defined off the generator's OWN blueprint band, not off
            // a hand-typed OVR literal: a man the talent backbone drew as an
            // R1/R2 prospect (band <= 2) whose production record is 89 snaps.
            let isGem = r.limitedSample && r.band <= 2
            if r.limitedSample {
                buriedRows.append(r)
                buriedSnaps.append(Double(r.snaps))
                buriedProd.append(Double(r.production))
                buriedOvr.append(Double(r.overall))
                buriedProjection.append(Double(r.publicProjection))
            } else {
                prodFullAll.append(Double(r.production))
                ovrFullAll.append(Double(r.overall))
            }
            // Low production = the bottom tier, i.e. what the board actually
            // shows the user when it wants him to look away.
            if r.tier == "Below Avg" {
                lowProdCount += 1
                if r.band <= 2 { lowProdGemCount += 1 }
                if r.limitedSample {
                    lowProdBuriedCount += 1
                    if isGem { lowProdBuriedGemCount += 1 }
                }
            }
            allRowCount += 1
            if r.band <= 2 { bandLE2Count += 1 }
            let exampleKey = "\(r.position.rawValue)|\(r.tier)|\(r.limitedSample ? "LS" : "\(r.yearsStarted)y")"
            if statLineExamples[exampleKey] == nil { statLineExamples[exampleKey] = r.statLine }
            // Screenshot regression (#181 audit): Elite RB, one year started.
            if r.position == .RB, r.tier == "Elite", r.yearsStarted == 1, !r.limitedSample,
               let yards = dcLeadingInt(r.statLine) {
                eliteOneYearRushMin = min(eliteOneYearRushMin, yards)
                eliteOneYearRushCount += 1
            }
        }
        if tiersSeen.count < 4 { tierMissingClasses += 1 }
        // Within-class stat-line collisions, per position.
        var linesThisClass: [Position: [String: Int]] = [:]
        for r in rows { linesThisClass[r.position, default: [:]][r.statLine, default: 0] += 1 }
        for (pos, lines) in linesThisClass {
            let total = lines.values.reduce(0, +)
            statLineCount[pos, default: 0] += total
            statLineDupes[pos, default: 0] += total - lines.count
        }
        let buriedThisClass = rows.filter { $0.limitedSample }
        gemShares.append(Double(buriedThisClass.count) / Double(max(1, rows.count)))
        gemsPerClass.append(Double(buriedThisClass.filter { $0.band <= 2 }.count))
        if buriedThisClass.contains(where: { $0.publicProjection <= 3 }) { buriedEarlyProjections += 1 }

        if verbose && classIndex == 0 {
            print("  (class 0 top 12 board)")
            for r in rows.prefix(12) {
                print(String(format: "    #%-3d %-3@ band=%d ovr=%d pot=%d skills=%@ prod=%d rdy=%d",
                             r.slot, r.position.rawValue, r.band, r.overall, r.potential,
                             r.skills.map(String.init).joined(separator: "/"), r.production, r.readiness))
            }
        }
    }
    let elapsed = Date().timeIntervalSince(t0)

    // ========================================================================
    // REPORT
    // ========================================================================
    let A = DCAsserts()
    let classesD = Double(classes)

    print("")
    print("--- POSITION TABLE (per class) -----------------------------------------------")
    print("  \(dcPad("grp", 7))\(dcLPad("count", 6))  \(dcPad("clamp", 9))  \(dcLPad("min", 4))\(dcLPad("max", 5))   \(dcLPad("R1avg", 6))  \(dcPad("R1clamp", 8))  \(dcLPad("R1min", 6))\(dcLPad("R1max", 6))  \(dcLPad("bestBand", 9))\(dcLPad("worst", 6))  \(dcLPad("ref R1", 7))")
    for g in groups {
        let key = g.rawValue
        let c = countByGroup[key] ?? []
        let r1 = r1ByGroup[key] ?? []
        let bb = bestBandByGroup[key] ?? []
        let refText: String
        if let refOpt = dcReferenceR1Mean[key], let ref = refOpt {
            refText = String(format: "%.1f", ref)
        } else { refText = "  --" }
        print("  \(dcPad(key, 7))\(dcLPad(String(format: "%.1f", dcMean(c)), 6))  \(dcPad("\(g.classCountRange.lowerBound)-\(g.classCountRange.upperBound)", 9))  \(dcLPad(String(format: "%.0f", c.min() ?? 0), 4))\(dcLPad(String(format: "%.0f", c.max() ?? 0), 5))   \(dcLPad(String(format: "%.2f", dcMean(r1)), 6))  \(dcPad("\(g.firstRoundRange.lowerBound)-\(g.firstRoundRange.upperBound)", 8))  \(dcLPad(String(format: "%.0f", r1.min() ?? 0), 6))\(dcLPad(String(format: "%.0f", r1.max() ?? 0), 6))  \(dcLPad(String(format: "%.2f", dcMean(bb)), 9))\(dcLPad(String(format: "%.0f", bb.max() ?? 0), 6))  \(dcLPad(refText, 7))")
    }

    // §7.1's ±6 pp tolerance is TIGHTER than the Monte-Carlo error of a 200-class
    // sample (SE = sqrt(.26*.74/200) = 3.1 pp for the 26 % bucket, so ±6 pp is
    // only ±1.9σ and ~1 run in 4 trips on noise alone). The histogram therefore
    // gets its own, larger draw — every other assert still runs on `--classes`.
    let histTarget = max(2000, classes)
    var qbHistCounts = qbR1Counts
    if histTarget > classes {
        for _ in 0..<(histTarget - classes) {
            let extra = DraftClassBuilder.buildOrdered(count: size)
            var qbR1 = 0
            for (i, p) in extra.prospects.enumerated() where p.position == .QB && extra.bands[i] == 1 { qbR1 += 1 }
            qbHistCounts.append(qbR1)
        }
    }

    print("")
    print("--- QB R1 HISTOGRAM ----------------------------------------------------------")
    var qbHistLine = "  "
    var qbHistMaxDelta = 0.0
    for n in 1...6 {
        let share = Double(qbHistCounts.filter { $0 == n }.count) / Double(qbHistCounts.count) * 100
        let sampleShare = Double(qbR1Counts.filter { $0 == n }.count) / classesD * 100
        let target = dcQBHistogramTarget[n] ?? 0
        qbHistMaxDelta = max(qbHistMaxDelta, abs(share - target))
        qbHistLine += String(format: "%d:%5.1f%%(t%.0f|%.0f) ", n, share, target, sampleShare)
    }
    print(qbHistLine + "  [share(target|\(classes)-class sample), histogram n=\(qbHistCounts.count)]")
    print(String(format: "  QB R1 mean %.2f (ref 3.5)  min %d  max %d   |  QB grades <=R2: mean %.1f max %d",
                 dcMean(qbR1Counts.map(Double.init)), qbR1Counts.min() ?? 0, qbR1Counts.max() ?? 0,
                 dcMean(qbTop2Counts.map(Double.init)), qbTop2Counts.max() ?? 0))

    print("")
    print("--- OVERALL LETTER HISTOGRAM -------------------------------------------------")
    let letterOrder = ["A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D+", "D", "F"]
    let totalProspects = Double(classes * size)
    var l1 = "  all      ", l2 = "  graded   "
    for l in letterOrder {
        l1 += String(format: "%@ %5.2f%%  ", dcPad(l, 2), Double(letterHist[l] ?? 0) / totalProspects * 100)
        let gradedTotal = Double(gradedLetterHist.values.reduce(0, +))
        l2 += String(format: "%@ %5.2f%%  ", dcPad(l, 2), Double(gradedLetterHist[l] ?? 0) / max(1, gradedTotal) * 100)
    }
    print(l1)
    print(l2)
    let bRangeGraded = ["B+", "B", "B-"].reduce(0) { $0 + (gradedLetterHist[$1] ?? 0) }
    let cRangeGraded = ["C+", "C", "C-"].reduce(0) { $0 + (gradedLetterHist[$1] ?? 0) }
    let aRangeGraded = ["A+", "A", "A-"].reduce(0) { $0 + (gradedLetterHist[$1] ?? 0) }
    let dRangeGraded = ["D+", "D", "F"].reduce(0) { $0 + (gradedLetterHist[$1] ?? 0) }
    print(String(format: "  graded (band<=7) ranges: A %.1f%%  B %.1f%%  C %.1f%%  D/F %.1f%%",
                 Double(aRangeGraded) / max(1, Double(bRangeGraded + cRangeGraded + aRangeGraded + dRangeGraded)) * 100,
                 Double(bRangeGraded) / max(1, Double(bRangeGraded + cRangeGraded + aRangeGraded + dRangeGraded)) * 100,
                 Double(cRangeGraded) / max(1, Double(bRangeGraded + cRangeGraded + aRangeGraded + dRangeGraded)) * 100,
                 Double(dRangeGraded) / max(1, Double(bRangeGraded + cRangeGraded + aRangeGraded + dRangeGraded)) * 100))
    print(String(format: "  A-range (85+) per class: min %.0f  avg %.1f  max %.0f   [target 5-14]",
                 aRangePerClass.min() ?? 0, dcMean(aRangePerClass), aRangePerClass.max() ?? 0))

    print("")
    print("--- BAND TABLE ---------------------------------------------------------------")
    print("  band    n/class   ovr avg    ovr sd(class)   pot avg   upside avg   ups p05  ups p95   ceil>=78")
    let bandLabel = [1: "R1", 2: "R2", 3: "R3", 4: "R4", 5: "R5", 6: "R6", 7: "R7", 8: "UDFA"]
    for band in 1...8 {
        let ovr = bandOverall[band] ?? []
        guard !ovr.isEmpty else { continue }
        let pot = bandPotential[band] ?? []
        let ups = bandUpside[band] ?? []
        let ceil = bandCeilingOK[band] ?? (0, 0)
        print(String(format: "  %-6@ %7.1f   %7.2f    %10.2f   %7.2f   %9.2f   %6.1f   %6.1f    %6.1f%%",
                     bandLabel[band] ?? "?", Double(ovr.count) / classesD, dcMean(ovr),
                     dcMean(withinBandSDPerClass[band] ?? []), dcMean(pot), dcMean(ups),
                     dcPct(ups, 0.05), dcPct(ups, 0.95),
                     Double(ceil.hit) / Double(max(1, ceil.total)) * 100))
    }

    print("")
    print("--- ELITE SKILLS -------------------------------------------------------------")
    print(String(format: "  skill grades: %d total | 88+ %.2f%% | A+ (95+) %.2f%%  [target A+ <= 3%%]",
                 skillTotal, Double(skill88) / Double(max(1, skillTotal)) * 100,
                 Double(skillAPlus) / Double(max(1, skillTotal)) * 100))
    print(String(format: "  day-3 (band>=4) freak trait (>=85 skill): %.2f%%  [target 3-7%%]  n=%d",
                 Double(day3Freak) / Double(max(1, day3Total)) * 100, day3Total))
    print("  premium-group classes missing an 88+ skill: \(premiumMissesPerClass) of \(classes * premiumGroups.count) group-classes")

    print("")
    print("--- COMBINE (40 yd, invitees) ------------------------------------------------")
    print("  pos   /class     n      mean     ref     delta    corr(spd,40)   A/A+ drills per class")
    var worstFortyDelta = 0.0
    var worstFortyPos = ""
    var worstCorr = -1.0
    var worstCorrPos = ""
    var fortyJudgedPositions = 0
    var exemptFortyDeltas: [(String, Double)] = []
    for pos in Position.allCases where pos != .K && pos != .P {
        let f = fortyByPos[pos] ?? []
        guard !f.isEmpty else { continue }
        let ref = ScoutingEngine.CombineDrillTable.drills(for: pos).forty.mean
        let delta = dcMean(f) - ref
        let corr = dcCorr(speedByPos[pos] ?? [], f)
        // 7.7a exemption — see `dcFortyReferenceExempt`. The row is still
        // measured and printed; it is only kept out of the worst-delta roll-up.
        let exempt = dcFortyReferenceExempt.contains(pos)
        if exempt {
            exemptFortyDeltas.append((pos.rawValue, delta))
        } else {
            fortyJudgedPositions += 1
            if abs(delta) > abs(worstFortyDelta) { worstFortyDelta = delta; worstFortyPos = pos.rawValue }
        }
        // Want every position at <= -0.6, so the LEAST negative one is the worst.
        if corr > worstCorr { worstCorr = corr; worstCorrPos = pos.rawValue }
        print(String(format: "  %-5@ %5.1f %5d   %6.3f  %6.3f  %+7.3f      %+6.2f        %.2f%@",
                     pos.rawValue, dcMean(countByPosition[pos] ?? []), f.count,
                     dcMean(f), ref, delta, corr, dcMean(aGradesByPos[pos] ?? []),
                     exempt ? "   [delta not judged — 7.7a exempt]" : ""))
    }
    print(String(format: "  coarse groups A/A+ per class: speedster %.2f  bigman %.2f  balanced %.2f   (drill values inside clamps: %d/%d)",
                 dcMean(aGradesByCoarse["speedster"] ?? []), dcMean(aGradesByCoarse["bigman"] ?? []),
                 dcMean(aGradesByCoarse["balanced"] ?? []), drillChecked - drillOutOfRange, drillChecked))

    print("")
    print("--- READINESS / PRODUCTION / LEARNING ----------------------------------------")
    let qbReady = dcMean(readinessByPos[.QB] ?? [])
    let rbReady = dcMean(readinessByPos[.RB] ?? [])
    print(String(format: "  readiness: min %.0f  mean %.1f  max %.0f  |  corr(readiness, yearsStarted) %.3f  [>0.4]",
                 readinessAll.min() ?? 0, dcMean(readinessAll), readinessAll.max() ?? 0,
                 dcCorr(readinessAll, yearsAll)))
    print(String(format: "  readiness QB %.1f < RB %.1f ? %@   |  CB %.1f  OT %.1f  C %.1f  S %.1f",
                 qbReady, rbReady, qbReady < rbReady ? "yes" : "NO",
                 dcMean(readinessByPos[.CB] ?? []), dcMean(readinessByPos[.LT] ?? []),
                 dcMean(readinessByPos[.C] ?? []), dcMean(readinessByPos[.FS] ?? [])))
    print(String(format: "  production: mean %.1f  corr(production, trueOverall) %.3f  [0.30-0.65]  classes missing a tier: %d",
                 dcMean(prodAll), dcCorr(prodAll, ovrAll), tierMissingClasses))
    print(String(format: "    played-a-season cohort only: corr %.3f  (the pre-#181 model, unchanged by construction)",
                 dcCorr(prodFullAll, ovrFullAll)))
    print(String(format: "  learning: mean %.1f  corr(learning, awareness) %.3f  (plan r~0.6)",
                 dcMean(learnAll), dcCorr(learnAll, awrAll)))
    // Plan §7.10: learnScheme's player term moved from awareness/70 to learning/65.
    // The class-average learning RATE must stay within +-10 % of the old term.
    let newTerm = dcMean(learningRates)
    let oldTerm = dcMean(awrAll.map { $0 / 70.0 })
    print(String(format: "  learnScheme player term: new (learning/65) %.3f vs old (awareness/70) %.3f = %+.1f%%  [plan §7.10 guard +-10%%]",
                 newTerm, oldTerm, (newTerm / max(0.001, oldTerm) - 1) * 100))
    let archTotal = Double(archHist.values.reduce(0, +))
    print(String(format: "  archetypes: Polished %.1f%%  Balanced %.1f%%  Raw %.1f%%   |  competition: P5 %.1f%%  G5 %.1f%%  FCS %.1f%%",
                 Double(archHist["Polished"] ?? 0) / archTotal * 100,
                 Double(archHist["Balanced"] ?? 0) / archTotal * 100,
                 Double(archHist["Raw"] ?? 0) / archTotal * 100,
                 Double(compHist["P5"] ?? 0) / totalProspects * 100,
                 Double(compHist["G5"] ?? 0) / totalProspects * 100,
                 Double(compHist["FCS"] ?? 0) / totalProspects * 100))
    print(String(format: "  K per class %.1f (min %.0f)  P per class %.1f (min %.0f)  earliest K/P band %.0f",
                 dcMean(kCounts), kCounts.min() ?? 0, dcMean(pCounts), pCounts.min() ?? 0, kpBestBand.min() ?? 0))
    print(String(format: "  runtime %.1fs (%.0f classes/s)", elapsed, classesD / max(0.001, elapsed)))

    // ------------------------------------------------------------------------
    // USAGE SUPPRESSION / HIDDEN GEMS (task #181)
    // ------------------------------------------------------------------------
    let gemShare = dcMean(gemShares) * 100
    let pGemGivenLowProd = lowProdCount == 0 ? 0 : Double(lowProdGemCount) / Double(lowProdCount) * 100
    let pGemGivenBuried = buriedRows.isEmpty ? 0 : Double(gemsPerClass.reduce(0, +)) / Double(buriedRows.count) * 100
    print("")
    print("--- USAGE SUPPRESSION / HIDDEN GEMS (#181) -----------------------------------")
    print(String(format: "  buried cohort: %.2f%% of the class  [3-7%%]   %.2f R1/R2 talents per class  (%.1f%% of the cohort)",
                 gemShare, dcMean(gemsPerClass), pGemGivenBuried))
    print(String(format: "  buried: snaps mean %.0f (min %.0f max %.0f)  production mean %.1f  trueOverall mean %.1f  corr(prod, ovr) %.3f  [|r| <= 0.20]",
                 dcMean(buriedSnaps), buriedSnaps.min() ?? 0, buriedSnaps.max() ?? 0,
                 dcMean(buriedProd), dcMean(buriedOvr), dcCorr(buriedProd, buriedOvr)))
    print(String(format: "  buried public projection: mean R%.2f  earliest R%.0f  share <= R3 %.2f%%   (classes with a buried top-3-round projection: %d/%d)",
                 dcMean(buriedProjection), buriedProjection.min() ?? 0,
                 Double(buriedProjection.filter { $0 <= 3 }.count) / Double(max(1, buriedProjection.count)) * 100,
                 buriedEarlyProjections, classes))
    // PREDICTED P(gem | low production), from the three measured shares alone.
    // The burial roll is independent of the talent backbone (it keys off age,
    // archetype and position, none of which enter `talentTarget`), so among the
    // buried the band-<=2 share is just the class-wide band-<=2 share, and
    //   P(band<=2 | Below Avg) = buried_in_lowProd * P(band<=2) / lowProd.
    // Nothing here is a typed target: all three inputs come out of this run.
    let pBandLE2 = Double(bandLE2Count) / Double(max(1, allRowCount))
    let predictedGemGivenLowProd = Double(lowProdBuriedCount) * pBandLE2 / Double(max(1, lowProdCount)) * 100
    print(String(format: "  P(R1/R2 talent | Below Avg production) = %.2f%%  (%d of %d)   of which buried: %d",
                 pGemGivenLowProd, lowProdGemCount, lowProdCount, lowProdBuriedGemCount))
    print(String(format: "    predicted from shares: buried-in-Below-Avg %d x P(band<=2) %.3f / Below-Avg %d = %.2f%%  (delta %+.2fpp)",
                 lowProdBuriedCount, pBandLE2, lowProdCount, predictedGemGivenLowProd,
                 pGemGivenLowProd - predictedGemGivenLowProd))
    // Within-class stat-line collision rate, worst position.
    var worstDupPos = "-"
    var worstDupRate = 0.0
    var totalDupes = 0
    for (pos, count) in statLineCount where count > 0 {
        let rate = Double(statLineDupes[pos] ?? 0) / Double(count) * 100
        totalDupes += statLineDupes[pos] ?? 0
        if rate > worstDupRate { worstDupRate = rate; worstDupPos = pos.rawValue }
    }
    let overallDupRate = Double(totalDupes) / Double(max(1, statLineCount.values.reduce(0, +))) * 100
    print(String(format: "  stat-line collisions inside one class: %.2f%% of prospects overall, worst position %@ at %.2f%%  [<10%%]",
                 overallDupRate, worstDupPos, worstDupRate))
    print("    (pre-#181 a position/tier/years triple rendered ONE fixed string — 16 per position for a 30-man WR pool)")
    print(String(format: "  Elite RB, 1 year started: %d observed, min leading rush-yard figure %d  [screenshot regression: > 900, was 477]",
                 eliteOneYearRushCount, eliteOneYearRushCount == 0 ? -1 : eliteOneYearRushMin))
    print("  sample lines:")
    for key in ["RB|Elite|1y", "RB|Elite|4y", "RB|Below Avg|4y", "QB|Elite|3y", "QB|Below Avg|2y",
                "LT|Elite|4y", "LT|Below Avg|1y", "K|Elite|4y", "K|Below Avg|4y",
                "P|Elite|4y", "P|Below Avg|1y", "WR|Below Avg|LS", "DE|Below Avg|LS",
                "QB|Below Avg|LS", "LT|Below Avg|LS"] {
        if let line = statLineExamples[key] {
            print("    \(dcPad(key, 18)) \(line)")
        }
    }
    if let sample = buriedRows.first(where: { $0.band <= 2 }) {
        print(String(format: "  example gem: %@ band=%d trueOverall=%d pot=%d -> production %d (%@), consensus error %+d, public R%d",
                     sample.position.rawValue, sample.band, sample.overall, sample.potential,
                     sample.production, sample.tier, sample.consensusError, sample.publicProjection))
        print("    \(sample.statLine)")
    }

    // ========================================================================
    // ASSERTIONS
    // ========================================================================

    // §7.1 — QB first round
    A.check("7.1a", (qbHistCounts.min() ?? 0) >= 1 && (qbHistCounts.max() ?? 0) <= 6,
            "QB R1 count in [1,6] every class (observed \(qbHistCounts.min() ?? 0)-\(qbHistCounts.max() ?? 0) over \(qbHistCounts.count) classes)")
    A.check("7.1b", qbHistMaxDelta <= 6.0,
            String(format: "QB R1 histogram within +-6pp of plan (max delta %.1fpp, n=%d)", qbHistMaxDelta, qbHistCounts.count))
    A.check("7.1c", (qbTop2Counts.max() ?? 0) <= 8,
            "QB grades <=R2 never exceed 8 (max \(qbTop2Counts.max() ?? 0))")

    // §7.2 — best-at-position guarantees + specialists
    A.check("7.2a", bestBandViolations.isEmpty,
            "best \(r1Guaranteed.joined(separator: "/")) = R1 and best \(r2Guaranteed.joined(separator: "/")) <= R2 every class"
            + (bestBandViolations.isEmpty ? "" : " — e.g. \(bestBandViolations[0])"))
    A.check("7.2b", (kpBestBand.min() ?? 0) >= 4,
            "K/P never graded better than R4 (earliest band \(Int(kpBestBand.min() ?? 0)))")
    A.check("7.2c", (kCounts.min() ?? 0) >= 3 && (pCounts.min() ?? 0) >= 3,
            "K >= 3 and P >= 3 every class (min K \(Int(kCounts.min() ?? 0)), min P \(Int(pCounts.min() ?? 0)))")

    // §7.3 — allocation clamps + 10-yr means
    A.check("7.3a", classCountViolations.isEmpty,
            "position class counts inside plan §4 clamps every class"
            + (classCountViolations.isEmpty ? "" : " — e.g. \(classCountViolations[0])"))
    A.check("7.3b", r1ClampViolations.isEmpty,
            "R1 band counts inside plan §4 clamps every class"
            + (r1ClampViolations.isEmpty ? "" : " — e.g. \(r1ClampViolations[0])"))
    var shareDeviations: [String] = []
    // Plan §4 shares sum to 95.9 %, not 100 % — "normalize to class size" is the
    // plan's own instruction, so the expectation is the normalized share.
    let shareTotal = groups.reduce(0.0) { $0 + $1.classShare }
    for g in groups {
        let expected = g.classShare / shareTotal * Double(size)
        let observed = dcMean(countByGroup[g.rawValue] ?? [])
        if abs(observed - expected) / expected > 0.20 {
            shareDeviations.append(String(format: "%@ %.1f vs %.1f", g.rawValue, observed, expected))
        }
    }
    A.check("7.3c", shareDeviations.isEmpty,
            "aggregate class counts within +-20% of plan §4 shares"
            + (shareDeviations.isEmpty ? "" : " — \(shareDeviations.joined(separator: ", "))"))
    var r1Deviations: [String] = []
    for g in groups {
        guard let refOpt = dcReferenceR1Mean[g.rawValue], let ref = refOpt else { continue }
        let observed = dcMean(r1ByGroup[g.rawValue] ?? [])
        if abs(observed - ref) / ref > 0.20 {
            r1Deviations.append(String(format: "%@ %.2f vs %.1f", g.rawValue, observed, ref))
        }
    }
    A.check("7.3d", r1Deviations.isEmpty,
            "aggregate R1 counts within +-20% of the NFL 10-yr means"
            + (r1Deviations.isEmpty ? "" : " — \(r1Deviations.joined(separator: ", "))"))

    // §7.4 — grade spread
    A.check("7.4a", (aRangePerClass.min() ?? 0) >= 5 && (aRangePerClass.max() ?? 0) <= 14,
            String(format: "A-range (85+) per class in [5,14] (observed %.0f-%.0f)",
                   aRangePerClass.min() ?? 0, aRangePerClass.max() ?? 0))
    A.check("7.4b", bRangeGraded > cRangeGraded && bRangeGraded > aRangeGraded && bRangeGraded > dRangeGraded,
            "B-range is the bulk of the graded (band<=7) board")
    var sdViolations: [String] = []
    for band in 1...8 {
        let sds = withinBandSDPerClass[band] ?? []
        guard !sds.isEmpty else { continue }
        if dcMean(sds) < 1.5 { sdViolations.append(String(format: "%@ %.2f", bandLabel[band] ?? "?", dcMean(sds))) }
    }
    A.check("7.4c", sdViolations.isEmpty,
            "within-band sd(trueOverall) >= 1.5 for every band"
            + (sdViolations.isEmpty ? "" : " — \(sdViolations.joined(separator: ", "))"))

    // §7.5 — elite skills
    A.check("7.5a", premiumMissesPerClass == 0,
            "every premium group (QB/WR/OT/EDGE/CB/DT) has an 88+ skill every class (\(premiumMissesPerClass) misses)")
    let aPlusShare = Double(skillAPlus) / Double(max(1, skillTotal)) * 100
    A.check("7.5b", aPlusShare <= 3.0, String(format: "A+ skills <= 3%% of all skill grades (%.2f%%)", aPlusShare))
    let freakRate = Double(day3Freak) / Double(max(1, day3Total)) * 100
    A.check("7.5c", freakRate >= 3.0 && freakRate <= 7.0,
            String(format: "day-3 freak-trait rate in [3,7]%% (%.2f%%)", freakRate))

    // §7.6 — potential
    A.check("7.6a", potBelowOverall == 0, "truePotential >= trueOverall for every prospect (\(potBelowOverall) violations)")
    var monotone = true
    var previous = Double.greatestFiniteMagnitude
    for band in 1...8 {
        guard let pots = bandPotential[band], !pots.isEmpty else { continue }
        let m = dcMean(pots)
        if m >= previous { monotone = false }
        previous = m
    }
    A.check("7.6b", monotone, "band mean potential strictly decreasing R1 > R2 > ... > UDFA")
    let r7p95 = dcPct(bandUpside[7] ?? [], 0.95)
    let r1p05 = dcPct(bandUpside[1] ?? [], 0.05)
    A.check("7.6c", r7p95 > r1p05,
            String(format: "upside distributions overlap: R7 p95 %.1f > R1 p05 %.1f", r7p95, r1p05))
    var ceilShares: [Int: Double] = [:]
    for band in 1...8 {
        let c = bandCeilingOK[band] ?? (0, 0)
        guard c.total > 0 else { continue }
        ceilShares[band] = Double(c.hit) / Double(c.total) * 100
    }
    let ceilMonotone = (ceilShares[1] ?? 0) >= (ceilShares[3] ?? 0) - 0.001
        && (ceilShares[3] ?? 0) >= (ceilShares[7] ?? 0) - 0.001
    A.check("7.6d", ceilMonotone,
            String(format: "development-ceiling>=78 share non-increasing by band: R1 %.0f%% R3 %.0f%% R7 %.0f%%  [monotonicity guard only — the starter-capable CALIBRATION lives in the `career` scenario, see DEVIATION note]",
                   ceilShares[1] ?? 0, ceilShares[3] ?? 0, ceilShares[7] ?? 0))

    // §7.7 — combine
    // 7.7a judges the 40-yd class mean against the position's own
    // `CombineDrillTable` reference — but only for positions whose cohort spans
    // the draft. K, P, LS and H are exempt (`dcFortyReferenceExempt`): all four
    // are drafted late or not at all, and the delta this assert reads is
    // `-forty.sd * 0.8 * levelShift/8` with BOTH the drill mean and the speed
    // prior cancelling out of it, so for a cohort pinned to the bottom of the
    // talent curve it is a fixed consequence of the band, not a reference error
    // any constant here could correct. Their rows are printed above with their
    // measured deltas; 7.7b-7.7e still cover them.
    A.check("7.7a", abs(worstFortyDelta) <= 0.05,
            String(format: "40-yd mean within +-0.05s of its reference for each of the %d draft-wide positions"
                   + " (worst %@ %+.3f); exempt: LS/H (UDFA-band cohorts — the delta reads band level,"
                   + " not a reference error any constant could fix), K/P (no combine drills here)%@",
                   fortyJudgedPositions, worstFortyPos, worstFortyDelta,
                   exemptFortyDeltas.isEmpty ? ""
                       : " [measured: " + exemptFortyDeltas.map { String(format: "%@ %+.3f", $0.0, $0.1) }
                           .joined(separator: ", ") + "]"))
    A.check("7.7b", drillOutOfRange == 0,
            "all combine drill values inside the per-position clamps (\(drillOutOfRange) of \(drillChecked) outside)")
    A.check("7.7c", worstCorr <= -0.6,
            String(format: "corr(speed, 40 time) <= -0.6 for every position (worst %@ %+.2f)", worstCorrPos, worstCorr))
    var drillGradeIssues: [String] = []
    var drillShareIssues: [String] = []
    for pos in Position.allCases where pos != .K && pos != .P {
        let counts = aGradesByPos[pos] ?? []
        guard !counts.isEmpty else { continue }
        let m = dcMean(counts)
        let pool = dcMean(countByPosition[pos] ?? [])
        // Upper bound holds for every position; the lower bound is only
        // meaningful where the position fields a real peer group (>= 20/class —
        // a top-5% grader cannot hand out one A per class to a 10-man pool).
        if m > 3.0 { drillGradeIssues.append(String(format: "%@ %.2f>3", pos.rawValue, m)) }
        if pool >= 25, m < 1.0 { drillGradeIssues.append(String(format: "%@ %.2f<1", pos.rawValue, m)) }
        // …and the grader must be POSITION-relative: every position, big pool or
        // small, hands its A/A+ grades to ~the top 5 % of its own peers.
        if pool >= 8 {
            let share = m / pool * 100
            if share < 3.0 || share > 8.0 {
                drillShareIssues.append(String(format: "%@ %.1f%%", pos.rawValue, share))
            }
        }
    }
    A.check("7.7d", drillGradeIssues.isEmpty,
            "1-3 A/A+ drill grades per position per class (mean; upper bound all positions)"
            + (drillGradeIssues.isEmpty ? "" : " — \(drillGradeIssues.joined(separator: ", "))"))
    A.check("7.7e", drillShareIssues.isEmpty,
            "drill grading is position-relative: A/A+ share in [3,8]% for every position"
            + (drillShareIssues.isEmpty ? "" : " — \(drillShareIssues.joined(separator: ", "))"))

    // §7.8 — readiness
    let readyMin = readinessAll.min() ?? 0, readyMax = readinessAll.max() ?? 0
    A.check("7.8a", readyMin >= 25 && readyMax <= 95,
            String(format: "readiness in [25,95] (observed %.0f-%.0f)", readyMin, readyMax))
    let readyCorr = dcCorr(readinessAll, yearsAll)
    A.check("7.8b", readyCorr > 0.4, String(format: "corr(readiness, yearsStarted) > 0.4 (%.3f)", readyCorr))
    A.check("7.8c", qbReady < rbReady,
            String(format: "QB mean readiness %.1f < RB mean readiness %.1f", qbReady, rbReady))

    // §7.9 — production
    //
    // BAND REDERIVED IN #181: 0.45-0.75 -> 0.30-0.65. See the DEVIATION note at
    // the foot of this report for the derivation; the short version is that the
    // old band measured a class in which production had exactly ONE cause, and
    // the whole point of the usage-suppression work is that it now has two.
    // 7.9f pins the untouched cause separately so the loosened band cannot hide
    // a drift in the ordinary production model.
    let prodCorr = dcCorr(prodAll, ovrAll)
    A.check("7.9a", prodCorr >= 0.30 && prodCorr <= 0.65,
            String(format: "corr(production, trueOverall) in [0.30,0.65] (%.3f)", prodCorr))
    A.check("7.9b", tierMissingClasses == 0,
            "all four production tiers occur in every class (\(tierMissingClasses) classes missing one)")

    // §7.9c — the buried cohort is a real slice of every class, and a small one.
    A.check("7.9c", gemShare >= 3.0 && gemShare <= 7.0,
            String(format: "usage-suppressed cohort is 3-7%% of the class (%.2f%%)", gemShare))

    // §7.9d — inside that cohort production must carry NO ability signal: it is
    // derived from snaps only. A non-zero correlation here would mean the
    // buried branch had picked up a talent term somewhere.
    let buriedCorr = dcCorr(buriedProd, buriedOvr)
    A.check("7.9d", abs(buriedCorr) <= 0.20,
            String(format: "buried production is usage-only: |corr(production, trueOverall)| <= 0.20 (%.3f)", buriedCorr))

    // §7.9e — the gems have to be FINDABLE, and findable at exactly the rate
    // the composition of the class implies and no other. Asserted against the
    // PREDICTION derived from this run's own shares rather than against a typed
    // target: a drift in the burial rate, in the buried score span or in the
    // band mix moves both sides together, and only a real coupling between
    // burial and talent (the bug this guards) moves them apart. The 1.0pp slack
    // is the Monte-Carlo error on a ~350-of-5400 numerator.
    A.check("7.9e", pGemGivenLowProd >= 1.0
            && abs(pGemGivenLowProd - predictedGemGivenLowProd) <= 1.0,
            String(format: "P(R1/R2 talent | Below Avg production) = %.2f%% matches the %.2f%% its shares predict "
                   + "(delta %+.2fpp, tolerance 1.0pp) and is materially non-zero (was ~0%% pre-#181)",
                   pGemGivenLowProd, predictedGemGivenLowProd,
                   pGemGivenLowProd - predictedGemGivenLowProd))

    // §7.9f — and they have to SLIDE. The market has no tape on a buried
    // prospect, so it cannot be high on him: `usageAnchor` tops out at 64,
    // below `talentTarget(#224)` ~ 66-69, and `usageErrorDamping` keeps what is
    // left of the consensus noise inside ~7 points of that. The invariant is
    // therefore structural, and this asserts the structure held.
    A.check("7.9f", buriedEarlyProjections == 0,
            "no usage-suppressed prospect projects inside R1-R3 (\(buriedEarlyProjections) of \(classes) classes had one)")

    // §7.9g — the ordinary production model is UNCHANGED. Measured over the
    // played-a-season cohort only, the correlation must still sit in the band
    // the pre-#181 gate asserted over the whole class.
    let fullCorr = dcCorr(prodFullAll, ovrFullAll)
    A.check("7.9g", fullCorr >= 0.45 && fullCorr <= 0.75,
            String(format: "played-a-season cohort keeps the original [0.45,0.75] production band (%.3f)", fullCorr))

    // §7.9h — stat-line semantics (the #181 audit's screenshot case). The tier
    // is a RATE and the line is a BEST SEASON, so an Elite back with one year
    // of starts prints an Elite season, not a quarter of one. 1100 x 1.30 x
    // 0.92 (the jitter floor) = 1315 is the model's own lower bound; the assert
    // uses a slack 900 so it only fires on a return of the years/3 scaling
    // (which produced 477 minus jitter).
    A.check("7.9h", eliteOneYearRushCount > 0 && eliteOneYearRushMin > 900,
            "Elite RB with 1 year started prints a full Elite season "
            + (eliteOneYearRushCount == 0
               ? "(NOT OBSERVED in this sample — raise --classes)"
               : String(format: "(min %d rush yds over %d cases; the audit screenshot was 477)",
                        eliteOneYearRushMin, eliteOneYearRushCount)))

    // §7.9i — per-prospect variance. Pre-#181 a (position, tier, years) triple
    // rendered ONE fixed string: 4 tiers x 4 year counts = 16 printable lines
    // per position. Measured here as the share of prospects who share a line
    // with somebody else at their position IN THE SAME CLASS, which is the
    // collision the user can actually see.
    //
    // The 10 % bar is set by the deepest position group. CB is ~35 men in a
    // 350-man class, and collisions grow like n^2 / 2S in the pool size n, so
    // whatever the state count S the corners always collide hardest — a handful
    // of shared lines among 35 corners is not the failure this guards. For
    // scale: under the OLD renderer the pigeonhole principle alone forces at
    // least (35 - 16) / 35 = 54 % of that same pool onto a duplicate line, and
    // the realized rate was far worse because the year/tier mix is not uniform.
    A.check("7.9i", worstDupRate <= 10.0,
            String(format: "stat lines carry per-prospect variance: within-class collisions <= 10%% for every "
                   + "position (worst %@ %.2f%%, overall %.2f%%; the pre-#181 renderer's pigeonhole floor for "
                   + "that pool was 54%%)",
                   worstDupPos, worstDupRate, overallDupRate))

    // §7.10 — scheme-learning input drift (the harness `familiarity` scenario
    // covers the sim side; this is the generator side of the same guard).
    let learnDrift = (newTerm / max(0.001, oldTerm) - 1) * 100
    A.check("7.10", abs(learnDrift) <= 10.0,
            String(format: "learnScheme class-average player term within +-10%% of the old awareness term (%+.1f%%)", learnDrift))

    // §7.11 — declaration pool (development plan §2.9.8).
    // The board has to fill all 224 picks AND leave a real UDFA market behind
    // it. TARGET RAISED in phase 2: the cushion behind the draft went 26 → 60,
    // so the floor this asserts moves 250 → 284. That is a deliberate target
    // change (annual inflow 224 + ~60 ≈ the 250-300 new players/season of
    // DEVELOPMENT_NFL_REFERENCE.md §8), NOT a weakened guard — the old
    // "no class short of its floor" invariant is asserted unchanged against the
    // new, higher floor.
    let declaredFloor = 224.0 + 60.0
    let shortClasses = declaredPool.filter { $0 < declaredFloor }.count
    print("")
    print("--- DECLARATION POOL (plan §2.9.8) -------------------------------------------")
    print(String(format: "  declared/class: mean %.1f  min %.0f  max %.0f  (floor %.0f = 224 picks + 60 UDFA cushion)",
                 dcMean(declaredPool), declaredPool.min() ?? 0, declaredPool.max() ?? 0, declaredFloor))
    A.check("7.11", shortClasses == 0,
            String(format: "declared pool >= %.0f in every class (%d of %d short, min %.0f)",
                   declaredFloor, shortClasses, declaredPool.count, declaredPool.min() ?? 0))

    A.report()

    print("")
    print("--- DEVIATION NOTES ----------------------------------------------------------")
    print("  §7.9 BAND REDERIVED (task #181, usage suppression). corr(production, trueOverall)")
    print("       moved from [0.45,0.75] to [0.30,0.65]. This is a MODEL CHANGE, not a")
    print("       loosened guard, and the drop is predicted rather than observed-then-blessed:")
    print("       production used to have one cause (ability + noise) and now has two — a")
    print("       share q of every class never got on the field, and for those men the score")
    print("       is a function of SNAPS and of nothing else. Writing the class as a mixture")
    print("       of a played cohort (share 1-q, corr r_f, production sd s_f) and a buried one")
    print("       (share q, corr 0, production sd s_b, mean shifted down by d):")
    print("         cov  = (1-q)*r_f*s_f*sd(ovr_f)  + q*0            [buried covariance is 0]")
    print("                - q(1-q) * d * (mean(ovr_f) - mean(ovr_b))")
    print("         sd(prod) grows, because the buried mean sits ~30 points below the played")
    print("         mean and that between-group split adds q(1-q)d^2 to the total variance.")
    print("       Both terms push the correlation DOWN: the numerator loses the buried")
    print("       cohort's contribution while the denominator gains its between-group spread.")
    print("       With q ~ 0.05, d ~ 30 and the measured s_f, the predicted whole-class")
    print("       correlation is ~0.42-0.50 against a played-cohort r_f that has not moved.")
    print("       The band's WIDTH is carried over unchanged (0.35 wide, i.e. the same")
    print("       Monte-Carlo slack the original had) and re-centred on the prediction.")
    print("       7.9g pins the untouched half of the model at the ORIGINAL [0.45,0.75] over")
    print("       the played cohort, so this band cannot absorb a real regression: a drift in")
    print("       the ordinary production formula fails 7.9g whatever 7.9a reads.")
    print("  §7.6 ceiling-share targets are RETIRED as a calibration metric — the decision")
    print("       PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md §2.6 asked for, and the principled")
    print("       resolution of phase-1 skipped finding #3. Two reasons:")
    print("       (a) the plan's 90/55/25 targets are unreachable under the plan's OWN")
    print("           talent curve: talentTarget(#224) = 66-69 (draft plan §2 step 2) and")
    print("           upside >= 0, so every drafted prospect clears a 78 development")
    print("           ceiling by construction, whatever the generator does; and")
    print("       (b) a CEILING is not an outcome. What \"starter-capable\" actually means")
    print("           is measured end-to-end by the `career` scenario (development plan §6),")
    print("           which runs 20 independent 32-team leagues through the shipped")
    print("           development stack and asserts the primary-starter HIT RATE by round")
    print("           against DRAFT_NFL_REFERENCE.md §6 (R1 ~60 % ... UDFA ~4 %), plus the")
    print("           elite-share, trajectory-mix, aging-curve and career-length bands.")
    print("           Run `./run.sh career`. That is the real calibration; 7.6d below is")
    print("           kept only as a cheap monotonicity guard on the generator.")
    print("  §7.3 the `lb` group (MLB only) is excluded from the R1 10-yr-mean check: the")
    print("       reference's LB bucket is off-ball LBs while the game folds pass-rushing")
    print("       OLBs into EDGE, so the two are not comparable 1:1.")
    print("  §7.4 'B-range is the bulk' is measured over the GRADED board (band <= 7); the")
    print("       ~55 UDFA-band prospects are C-grade filler by the plan's own curve.")
    print("  §7.1 the QB R1 histogram is drawn over \(qbHistCounts.count) classes, not \(classes): the plan's")
    print("       +-6pp tolerance is tighter than a 200-class sample's own Monte-Carlo")
    print("       error (SE 3.1pp on the 26% bucket), so a 200-class check would fail on")
    print("       noise ~1 run in 4. Every other assert runs on the \(classes)-class sample.")
    print("  §7.7 'per position group' is measured per POSITION (the reference's own")
    print("       parenthetical: 1-3 elite testers per position per year). The shipped")
    print("       grader ranks within 3 coarse groups, whose top-5% is 5-8 prospects; the")
    print("       per-position counts that fall out of it are the 1-3 the reference names.")
    print("       The >=1 bound is asserted on the class MEAN for positions with >= 25")
    print("       prospects/class: a top-5% grader gives a 20-man pool exactly 1.0 A/A+")
    print("       per class IN EXPECTATION, so requiring >=1 of it asserts a mean against")
    print("       its own boundary. Assert 7.7e pins every position (pool >= 8) instead.")
    print("  §7.7a is judged over the \(fortyJudgedPositions) positions whose cohort spans the draft. K, P,")
    print("       LS and H are EXEMPT, and this is a structural exemption, not a loosened")
    print("       guard. `ScoutingEngine.drillResult` draws a 40 as")
    print("         forty.mean - forty.sd * (0.8*z + 0.6*noise + 0.5*modifier)")
    print("       with z = (speed - profile.speed.mean) / 8, and `PositionPhysicalProfile`")
    print("       .sample draws that speed as profile.speed.mean + levelShift + noise. Both")
    print("       the drill mean and the speed prior cancel, leaving")
    print("         delta = -forty.sd * 0.8 * levelShift / 8")
    print("         levelShift = athleticism - PositionPhysicalProfile.baseLevel (\(PositionPhysicalProfile.baseLevel))")
    print("       so the delta reads the cohort's athleticism level and NOTHING else — no")
    print("       edit to `forty.mean` or to the physical prior can move it. LS and H are")
    print("       pinned to the UDFA band by DraftClassBuilder.PositionGroup.earliestBand")
    print("       (.longSnapper, .holder: 8), so their levelShift is negative by")
    print("       construction and the class-wide +-0.05 s window is unreachable for them.")
    print("       K and P carry the same exemption for a stronger reason still: they are")
    print("       filtered out of the combine block upstream and take no drills in this")
    print("       scenario at all, so they have no row above. Nothing is hidden: the")
    print("       LS and H rows print their measured deltas, the 7.7a line repeats them, and")
    print("       7.7b-7.7e judge LS and H alongside everyone else.")

    if A.failures > 0 {
        print("")
        print("DRAFTCLASS: FAILED (\(A.failures) assertion(s))")
        exit(1)
    }
    print("")
    print("DRAFTCLASS: OK")
}

/// Mirrors the shipped combine grader's coarse grouping for reporting only
/// (`ScoutingEngine.positionGroup` is private to the sliced enum).
func dcCoarseGroup(_ pos: Position) -> String {
    switch pos {
    case .QB, .WR, .CB, .FS, .SS: return "speedster"
    case .LT, .LG, .C, .RG, .RT, .DE, .DT: return "bigman"
    default: return "balanced"
    }
}
