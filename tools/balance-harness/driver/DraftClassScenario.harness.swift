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
                drillGrade: p.positionDrillGrade))
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
        }
        if tiersSeen.count < 4 { tierMissingClasses += 1 }

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
    for pos in Position.allCases where pos != .K && pos != .P {
        let f = fortyByPos[pos] ?? []
        guard !f.isEmpty else { continue }
        let ref = ScoutingEngine.CombineDrillTable.drills(for: pos).forty.mean
        let delta = dcMean(f) - ref
        let corr = dcCorr(speedByPos[pos] ?? [], f)
        if abs(delta) > abs(worstFortyDelta) { worstFortyDelta = delta; worstFortyPos = pos.rawValue }
        // Want every position at <= -0.6, so the LEAST negative one is the worst.
        if corr > worstCorr { worstCorr = corr; worstCorrPos = pos.rawValue }
        print(String(format: "  %-5@ %5.1f %5d   %6.3f  %6.3f  %+7.3f      %+6.2f        %.2f",
                     pos.rawValue, dcMean(countByPosition[pos] ?? []), f.count,
                     dcMean(f), ref, delta, corr, dcMean(aGradesByPos[pos] ?? [])))
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
    print(String(format: "  production: mean %.1f  corr(production, trueOverall) %.3f  [0.45-0.75]  classes missing a tier: %d",
                 dcMean(prodAll), dcCorr(prodAll, ovrAll), tierMissingClasses))
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
    A.check("7.7a", abs(worstFortyDelta) <= 0.05,
            String(format: "every position's 40-yd mean within +-0.05s of its reference (worst %@ %+.3f)",
                   worstFortyPos, worstFortyDelta))
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
    let prodCorr = dcCorr(prodAll, ovrAll)
    A.check("7.9a", prodCorr >= 0.45 && prodCorr <= 0.75,
            String(format: "corr(production, trueOverall) in [0.45,0.75] (%.3f)", prodCorr))
    A.check("7.9b", tierMissingClasses == 0,
            "all four production tiers occur in every class (\(tierMissingClasses) classes missing one)")

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
