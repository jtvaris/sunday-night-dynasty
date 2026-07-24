import Foundation

// ============================================================================
// BALANCE MEASUREMENT HARNESS — scenario-selectable driver
// ============================================================================
// Compiled against byte-verified repo engine sources (PlaySimulator / PlayCall /
// PlayResult / PlayerAttributes / the enum files / the SimPlayer computed-prop
// block, all synced by sync_sources.sh) plus AdaptiveOpponentAIExtract.swift —
// the AI Layer-A/B math sliced MECHANICALLY out of the shipped
// Engine/Match/AdaptiveOpponentAI.swift so EVERY balance constant is the repo
// literal (paKeyCompletion 0.035, paKeyBigPlay 2.0, …). See README.md for the
// stale-default incident that this design makes impossible by construction.
//
// Built WITHOUT -DDEBUG → release/shipping semantics (directFamiliarity, carrier
// vision, separation-openness, etc. all active — matches the shipped game).
//
// Usage:  harness <scenario> [scenario ...]
//   percall      per-call neutral run ypc (vs play-mix AND vs nil quick-sim)
//   depth        depth curve (short/mid/deep comp%) + per-depth sack/INT/net blend
//   keyed-pa     keyed PA-deep @70/95/55 netYPA (the stale-default probe)
//   regression   CATEGORY 1 — full NFL-band regression guard (1a–1h)
//   pass-talent  CATEGORY 2 — QBxWR completion grids, covering-CB axis, TE/RB paths
//   run-talent   CATEGORY 3 — RBxOL four cells + OL/front axes (user ordering)
//   familiarity  CATEGORY 4 — offense/defense scheme-familiarity sweeps + drive TD%
//   stacking     CATEGORY 5 — worst-case grand-cap floors (run/deep/short)
//   spam         degenerate spam-collapse + mixed-parity (memory ON vs OFF)
//   all          every scenario above
//
// Sample sizes: env BH_N (default 40000) per cell; BH_GN (default 24000) per grid
// cell. The default reproduces the round-3 verifier numbers (see README).
// ============================================================================

let N   = ProcessInfo.processInfo.environment["BH_N"].flatMap { Int($0) } ?? 40000
let GN  = ProcessInfo.processInfo.environment["BH_GN"].flatMap { Int($0) } ?? 24000
let tiers = [55, 70, 85, 95]

// ---------------------------------------------------------------------------
// Roster factories (league-average 70 baseline; parameterized by tier)
// ---------------------------------------------------------------------------
func pctf(_ a: Int, _ b: Int) -> Double { b == 0 ? 0 : Double(a) / Double(b) * 100 }
func phys(_ s: Int, str: Int = 70, acc: Int = 70, agi: Int = 70) -> PhysicalAttributes {
    PhysicalAttributes(speed: s, acceleration: acc, strength: str, agility: agi, stamina: 70, durability: 70)
}
func ment() -> MentalAttributes {
    MentalAttributes(awareness: 70, decisionMaking: 70, clutch: 70, workEthic: 70, coachability: 70, leadership: 70)
}
func mk(_ n: String, _ p: Position, _ spd: Int, _ pa: PositionAttributes, str: Int = 70, acc: Int = 70, agi: Int = 70,
        fam: [String: Int] = [:]) -> SimPlayer {
    SimPlayer(fullName: n, position: p, physical: phys(spd, str: str, acc: acc, agi: agi), mental: ment(),
              positionAttributes: pa, overall: 70, schemeFamiliarity: fam)
}

/// Offense parameterized by QB / WR / TE / RB / OL tier (deep-composite path).
func offenseFor(qb: Int = 70, wr: Int = 70, te: Int = 70, rb: Int = 70, ol: Int = 70, fam: [String: Int] = [:]) -> [SimPlayer] {
    [ mk("QB1", .QB, 70, .quarterback(QBAttributes(armStrength: qb, accuracyShort: qb, accuracyMid: qb, accuracyDeep: qb, pocketPresence: 70, scrambling: 70)), fam: fam),
      mk("RB1", .RB, rb, .runningBack(RBAttributes(vision: rb, elusiveness: rb, breakTackle: rb, receiving: rb)), str: rb, acc: rb, agi: rb, fam: fam),
      mk("WR1", .WR, wr, .wideReceiver(WRAttributes(routeRunning: wr, catching: wr, release: 70, spectacularCatch: wr)), fam: fam),
      mk("WR2", .WR, wr, .wideReceiver(WRAttributes(routeRunning: wr, catching: wr, release: 70, spectacularCatch: wr)), fam: fam),
      mk("WR3", .WR, wr, .wideReceiver(WRAttributes(routeRunning: wr, catching: wr, release: 70, spectacularCatch: wr)), fam: fam),
      mk("TE1", .TE, te, .tightEnd(TEAttributes(blocking: 70, catching: te, routeRunning: te, speed: te)), fam: fam),
      mk("LT1", .LT, 70, .offensiveLine(OLAttributes(runBlock: ol, passBlock: ol, pull: ol, anchor: ol)), str: ol, fam: fam),
      mk("LG1", .LG, 70, .offensiveLine(OLAttributes(runBlock: ol, passBlock: ol, pull: ol, anchor: ol)), str: ol, fam: fam),
      mk("C1",  .C,  70, .offensiveLine(OLAttributes(runBlock: ol, passBlock: ol, pull: ol, anchor: ol)), str: ol, fam: fam),
      mk("RG1", .RG, 70, .offensiveLine(OLAttributes(runBlock: ol, passBlock: ol, pull: ol, anchor: ol)), str: ol, fam: fam),
      mk("RT1", .RT, 70, .offensiveLine(OLAttributes(runBlock: ol, passBlock: ol, pull: ol, anchor: ol)), str: ol, fam: fam) ]
}
/// Defense parameterized by covering-CB / safety coverage, DB speed, and front.
func defenseFor(cbCov: Int = 70, dbCov: Int = 70, dbSpd: Int = 70, front: Int = 70, fam: [String: Int] = [:]) -> [SimPlayer] {
    [ mk("DE1", .DE, 70, .defensiveLine(DLAttributes(passRush: front, blockShedding: front, powerMoves: front, finesseMoves: front)), str: front, fam: fam),
      mk("DE2", .DE, 70, .defensiveLine(DLAttributes(passRush: front, blockShedding: front, powerMoves: front, finesseMoves: front)), str: front, fam: fam),
      mk("DT1", .DT, 70, .defensiveLine(DLAttributes(passRush: front, blockShedding: front, powerMoves: front, finesseMoves: front)), str: front, fam: fam),
      mk("DT2", .DT, 70, .defensiveLine(DLAttributes(passRush: front, blockShedding: front, powerMoves: front, finesseMoves: front)), str: front, fam: fam),
      mk("OLB1", .OLB, 70, .linebacker(LBAttributes(tackling: front, zoneCoverage: 70, manCoverage: 70, blitzing: 70)), fam: fam),
      mk("OLB2", .OLB, 70, .linebacker(LBAttributes(tackling: front, zoneCoverage: 70, manCoverage: 70, blitzing: 70)), fam: fam),
      mk("MLB1", .MLB, 70, .linebacker(LBAttributes(tackling: front, zoneCoverage: 70, manCoverage: 70, blitzing: 70)), fam: fam),
      mk("CB1", .CB, dbSpd, .defensiveBack(DBAttributes(manCoverage: cbCov, zoneCoverage: cbCov, press: 70, ballSkills: 70)), fam: fam),
      mk("CB2", .CB, dbSpd, .defensiveBack(DBAttributes(manCoverage: cbCov, zoneCoverage: cbCov, press: 70, ballSkills: 70)), fam: fam),
      mk("FS1", .FS, dbSpd, .defensiveBack(DBAttributes(manCoverage: dbCov, zoneCoverage: dbCov, press: 70, ballSkills: 70)), fam: fam),
      mk("SS1", .SS, dbSpd, .defensiveBack(DBAttributes(manCoverage: dbCov, zoneCoverage: dbCov, press: 70, ballSkills: 70)), fam: fam) ]
}
let defense70 = defenseFor()

// League-representative defensive play-call mix (matches the shipped AI base sheet).
let defenseMix: [(DefensivePackage, Int)] = [
    (DefensiveCall.cover3Base.package, 30), (DefensiveCall.cover2Shell.package, 15),
    (DefensiveCall.cover1.package, 12), (DefensiveCall.quarters.package, 10),
    (DefensiveCall.manFree.package, 10), (DefensiveCall.nickelPackage.package, 8),
    (DefensiveCall.lbFire.package, 8), (DefensiveCall.safetyBlitz.package, 4),
    (DefensiveCall.bearFront.package, 3)]
let mixExpanded = defenseMix.flatMap { Array(repeating: $0.0, count: $0.1) }
func rp() -> DefensivePackage { mixExpanded.randomElement()! }

// ---------------------------------------------------------------------------
// Play-Memory (Layer B) delta model — the VERBATIM mirror of LiveGameEngine.step
// Layer B (repo LiveGameEngine 1446-1508). Feeds the same pass/run/key SHIFTS the
// shipped coached path feeds into PlaySimulator.simulatePlay.
// ---------------------------------------------------------------------------
typealias PM = AdaptiveOpponentAI.PlayMemory
struct Deltas { var pass: (short: Double, mid: Double, deep: Double) = (0,0,0); var runYard = 0.0; var runStuff = 0.0; var key = 0.0 }
func deltas(for call: OffensivePlayCall, mem: PM, down: Int) -> Deltas {
    var d = Deltas()
    d.key = mem.keyIntensity(down: down)
    guard let concept = AdaptiveOpponentAI.concept(of: call) else { return d }
    let paKeyActive = d.key > 0 && (call.simulatorHint.isPlayAction || call.simulatorHint.passDepth == .deep)
    let catAnt = mem.anticipation(of: concept, down: down)
    let exact = mem.exactPunish(for: call)
    let open = mem.counterOpen(forCalled: concept, down: down, suppressDeepCounter: paKeyActive)
    if call.isPass || call == .screen {
        let malus = min(AdaptiveOpponentAI.catPassCompletionMalus * catAnt + exact.pass, AdaptiveOpponentAI.passTotalMalusCap)
        let net = -malus + open.pass
        switch concept {
        case .shortPass, .screen:    d.pass.short = net
        case .mediumPass:            d.pass.mid = net
        case .deepPass, .playAction: d.pass.deep = net
        default: break }
    } else {
        d.runYard = AdaptiveOpponentAI.catRunYardBite * catAnt + exact.runYard - open.run
        d.runStuff = AdaptiveOpponentAI.catRunStuffBonus * catAnt + exact.runStuff
    }
    return d
}
let P50 = AdaptiveOpponentAI.catPivot(thresholdOffset: 0, grade: 50)
let A50 = AdaptiveOpponentAI.catAlpha(thresholdOffset: 0, grade: 50)
func memAfter(_ calls: [(OffensivePlayCall, Int)]) -> PM {
    var m = PM(); m.catPivot = P50; m.catAlpha = A50; for (c, dn) in calls { m.record(call: c, down: dn) }; return m
}

// ---------------------------------------------------------------------------
// Measurement primitives
// ---------------------------------------------------------------------------
struct Stat { var comp = 0.0; var ev = 0.0; var td = 0.0; var int = 0.0; var sack = 0.0; var netYPA = 0.0; var att = 0; var comps = 0 }
func measurePass(_ call: OffensivePlayCall, off: [SimPlayer], def: [SimPlayer], yl: Int, n: Int,
                 key: Double = 0, offScheme: OffensiveScheme? = nil, defScheme: DefensiveScheme? = nil,
                 d: Deltas = Deltas(), fixedPkg: DefensivePackage? = nil) -> Stat {
    var caughtY = 0, caught = 0, att = 0, comps = 0, tds = 0, ints = 0, sacks = 0
    var allY = 0, dropbacks = 0
    var i = 0
    while i < n { i += 1
        let r = PlaySimulator.simulatePlay(
            offensePlayers: off, defensePlayers: def, down: 1, distance: 10,
            yardLine: yl, quarter: 2, timeRemaining: 450, momentum: 0, playNumber: 5,
            offensiveScheme: offScheme, defensiveScheme: defScheme,
            offensiveCall: call, defensivePackage: fixedPkg ?? rp(),
            runKeyIntensity: key == 0 ? d.key : key,
            passCompletionDelta: d.pass, runYardDelta: d.runYard, runStuffDelta: d.runStuff)
        if r.outcome == .penalty { continue }
        dropbacks += 1; allY += r.yardsGained
        switch r.outcome {
        case .completion, .touchdown:
            comps += 1; att += 1; caught += 1; caughtY += r.yardsGained
            if r.outcome == .touchdown { tds += 1 }
        case .incompletion: att += 1
        case .interception:  att += 1; ints += 1
        case .sack:          sacks += 1
        default: break
        }
    }
    var s = Stat()
    s.comp = pctf(comps, att); s.ev = Double(caughtY) / Double(max(1, caught))
    s.td = pctf(tds, att); s.int = pctf(ints, att)
    s.sack = pctf(sacks, dropbacks); s.netYPA = Double(allY) / Double(max(1, dropbacks))
    s.att = att; s.comps = comps
    return s
}
struct RunStat { var ypc = 0.0; var stuffRate = 0.0; var negRate = 0.0; var carries = 0 }
func measureRun(_ call: OffensivePlayCall, off: [SimPlayer], def: [SimPlayer], yl: Int, n: Int,
                key: Double = 0, offScheme: OffensiveScheme? = nil, defScheme: DefensiveScheme? = nil,
                d: Deltas = Deltas(), usePkg: Bool = true) -> RunStat {
    var ys = 0, carries = 0, stuffs = 0, negs = 0
    var i = 0
    while i < n { i += 1
        let r = PlaySimulator.simulatePlay(
            offensePlayers: off, defensePlayers: def, down: 1, distance: 10,
            yardLine: yl, quarter: 2, timeRemaining: 450, momentum: 0, playNumber: 5,
            offensiveScheme: offScheme, defensiveScheme: defScheme,
            offensiveCall: call, defensivePackage: usePkg ? rp() : nil,
            runKeyIntensity: key == 0 ? d.key : key,
            passCompletionDelta: d.pass, runYardDelta: d.runYard, runStuffDelta: d.runStuff)
        if r.playType != .run { continue }
        carries += 1; ys += r.yardsGained
        if r.yardsGained <= 1 { stuffs += 1 }
        if r.yardsGained < 0 { negs += 1 }
    }
    var s = RunStat()
    s.ypc = Double(ys) / Double(max(1, carries)); s.stuffRate = pctf(stuffs, carries)
    s.negRate = pctf(negs, carries); s.carries = carries
    return s
}

let o70 = offenseFor(qb: 70, wr: 70)

// ============================================================================
// SCENARIOS
// ============================================================================

// ---- percall: per-call neutral run ypc (vs mix AND vs nil quick-sim) --------
func scenarioPerCall() {
    print("===== SCENARIO percall: per-call neutral RUN ypc (vs mix AND vs nil quick-sim) =====")
    let runCallList: [(OffensivePlayCall, String)] = [
        (.insideRun, "insideRun"), (.outsideRun, "outsideRun"), (.counter, "counter"), (.draw, "draw"),
        (.dive, "dive"), (.toss, "toss"), (.jetSweep, "jetSweep"), (.qbSneak, "qbSneak")]
    for (c, name) in runCallList {
        let mix = measureRun(c, off: o70, def: defense70, yl: 25, n: N, usePkg: true)
        let nilp = measureRun(c, off: o70, def: defense70, yl: 25, n: N, usePkg: false)
        print(String(format: "    %-11@ vs-mix ypc=%.2f stuff=%.1f%%  |  quick-sim(nil) ypc=%.2f stuff=%.1f%%",
            name, mix.ypc, mix.stuffRate, nilp.ypc, nilp.stuffRate))
    }
    // NFL-realistic inside-heavy blend.
    let blendW: [(OffensivePlayCall, Double)] = [(.insideRun,0.50),(.outsideRun,0.18),(.counter,0.12),(.draw,0.08),(.dive,0.07),(.toss,0.05)]
    var bmix = 0.0, bnil = 0.0, bst = 0.0
    for (c, w) in blendW {
        let m = measureRun(c, off: o70, def: defense70, yl: 25, n: N, usePkg: true)
        let np = measureRun(c, off: o70, def: defense70, yl: 25, n: N, usePkg: false)
        bmix += m.ypc * w; bnil += np.ypc * w; bst += m.stuffRate * w
    }
    print(String(format: "    NFL-blend (inside-heavy)  vs-mix=%.2f  quick-sim(nil)=%.2f  stuff(mix)=%.1f%%  [band: inside 4.0-4.6, stuff 16-19%%]", bmix, bnil, bst))
}

// ---- depth: depth curve + per-depth sack/INT/net weighted blend -------------
func scenarioDepth() {
    print("===== SCENARIO depth: depth curve (short/mid/deep) + per-depth sack/INT/net blend =====")
    let sh = measurePass(.slant,   off: o70, def: defense70, yl: 25, n: N)
    let md = measurePass(.dig,     off: o70, def: defense70, yl: 25, n: N)
    let dp = measurePass(.goRoute, off: o70, def: defense70, yl: 25, n: N)
    let mono = sh.comp > md.comp && md.comp > dp.comp
    print(String(format: "    DEPTH CURVE comp%%  short=%.1f  mid=%.1f  deep=%.1f  monotone=%@  [short band 60-66]",
        sh.comp, md.comp, dp.comp, mono ? "YES" : "NO"))
    print(String(format: "    short(.slant) sack=%.1f%% int=%.2f%% comp=%.1f%% net=%.2f", sh.sack, sh.int, sh.comp, sh.netYPA))
    print(String(format: "    mid(.dig)     sack=%.1f%% int=%.2f%% comp=%.1f%% net=%.2f", md.sack, md.int, md.comp, md.netYPA))
    print(String(format: "    deep(.goRoute)sack=%.1f%% int=%.2f%% comp=%.1f%% net=%.2f", dp.sack, dp.int, dp.comp, dp.netYPA))
    let blendSack = sh.sack * 0.45 + md.sack * 0.40 + dp.sack * 0.15
    let blendInt  = sh.int * 0.45 + md.int * 0.40 + dp.int * 0.15
    let blendNet  = sh.netYPA * 0.45 + md.netYPA * 0.40 + dp.netYPA * 0.15
    print(String(format: "    WEIGHTED 45/40/15: sack=%.2f%% (<=8.7)  INT=%.2f%% (2.0-2.6)  net-YPA=%.2f (6.0-7.5)", blendSack, blendInt, blendNet))
}

// ---- keyed-pa: keyed PA-deep @70/95/55 (the stale-default probe) ------------
func scenarioKeyedPA() {
    print("===== SCENARIO keyed-pa: keyed PA-deep netYPA (repo paKey 0.035/2.0) =====")
    print(String(format: "    paKeyCompletion(1.0)=%.3f  paKeyBigPlay(1.0)=%.2f  (repo 0.035/2.0; stale trap was 0.18/8.0)",
        AdaptiveOpponentAI.paKeyCompletion(1.0), AdaptiveOpponentAI.paKeyBigPlay(1.0)))
    let keyed70 = measurePass(.playActionDeep, off: offenseFor(qb:70,wr:70), def: defense70, yl: 25, n: N, key: 1.0)
    let neut70  = measurePass(.playActionDeep, off: offenseFor(qb:70,wr:70), def: defense70, yl: 25, n: N, key: 0.0)
    let keyedEl = measurePass(.playActionDeep, off: offenseFor(qb:95,wr:95), def: defense70, yl: 25, n: N, key: 1.0)
    let neutEl  = measurePass(.playActionDeep, off: offenseFor(qb:95,wr:95), def: defense70, yl: 25, n: N, key: 0.0)
    let keyedWk = measurePass(.playActionDeep, off: offenseFor(qb:55,wr:55), def: defense70, yl: 25, n: N, key: 1.0)
    let neutWk  = measurePass(.playActionDeep, off: offenseFor(qb:55,wr:55), def: defense70, yl: 25, n: N, key: 0.0)
    print(String(format: "    KEYED PA-DEEP @70 netYPA=%.2f (neutral %.2f, +%.2f)  [band 9-12]",
        keyed70.netYPA, neut70.netYPA, keyed70.netYPA - neut70.netYPA))
    print(String(format: "    elite95 keyed=%.2f (+%.2f)  weak55 keyed=%.2f (+%.2f)  elite delta >> weak delta",
        keyedEl.netYPA, keyedEl.netYPA - neutEl.netYPA, keyedWk.netYPA, keyedWk.netYPA - neutWk.netYPA))
}

// ---- regression: CATEGORY 1 — full NFL-band regression guard ----------------
func scenarioRegression() {
    print("===== SCENARIO regression: CATEGORY 1 — NFL-band regression guard =====")
    // 1a. Blended run ypc + stuff tail.
    let runCalls: [(OffensivePlayCall, Double)] = [(.insideRun,0.40),(.outsideRun,0.20),(.counter,0.12),(.draw,0.10),(.dive,0.10),(.toss,0.08)]
    var blendYpc = 0.0, blendStuff = 0.0
    for (c, w) in runCalls {
        let rs = measureRun(c, off: o70, def: defense70, yl: 25, n: N)
        blendYpc += rs.ypc * w; blendStuff += rs.stuffRate * w
    }
    print(String(format: "1a. BLENDED RUN ypc=%.2f (band 4.0-4.6)   stuff(<=1yd) tail=%.1f%% (~15-19%%)", blendYpc, blendStuff))
    // 1b. Depth curve.
    let sShort = measurePass(.slant,   off: o70, def: defense70, yl: 25, n: N)
    let sMid   = measurePass(.dig,     off: o70, def: defense70, yl: 25, n: N)
    let sDeep  = measurePass(.goRoute, off: o70, def: defense70, yl: 25, n: N)
    let depthMono = sShort.comp > sMid.comp && sMid.comp > sDeep.comp
    print(String(format: "1b. DEPTH CURVE short=%.1f%% mid=%.1f%% deep=%.1f%%  monotone=%@ (short band 60-66)",
        sShort.comp, sMid.comp, sDeep.comp, depthMono ? "YES" : "NO"))
    // 1c/1d/1e. sack / INT / net-YPA (weighted 45/40/15 — the band-relevant blend).
    let blendNet  = sShort.netYPA*0.45 + sMid.netYPA*0.40 + sDeep.netYPA*0.15
    let blendSack = sShort.sack*0.45 + sMid.sack*0.40 + sDeep.sack*0.15
    let blendInt  = sShort.int*0.45 + sMid.int*0.40 + sDeep.int*0.15
    print(String(format: "1c. SACK%% (weighted 45/40/15)=%.1f%% (<=8.7)", blendSack))
    print(String(format: "1d. INT/att (blended)=%.2f%% (band 2.0-2.6)", blendInt))
    print(String(format: "1e. NET-YPA (blended 45/40/15)=%.2f (band 6.0-7.5)", blendNet))
    // 1f. Spam-collapse.
    func spamEV(_ call: OffensivePlayCall, reps: Int) -> Double {
        let mem = memAfter(Array(repeating: (call, 1), count: reps - 1))
        let d = deltas(for: call, mem: mem, down: 1)
        return measureRun(call, off: o70, def: defense70, yl: 25, n: N, d: d).ypc
    }
    let insideR1 = spamEV(.insideRun, reps: 1), insideR4 = spamEV(.insideRun, reps: 4)
    let tossR1 = spamEV(.toss, reps: 1), tossR4 = spamEV(.toss, reps: 4)
    print(String(format: "1f. SPAM-COLLAPSE inside r1=%.2f r4=%.2f (%.0f%% of r1, floor >=~1.8)  toss r1=%.2f r4=%.2f (%.0f%%)",
        insideR1, insideR4, insideR4/insideR1*100, tossR1, tossR4, tossR4/tossR1*100))
    // 1g. Deep tier matrix monotone + TD spread.
    print("1g. DEEP TIER MATRIX (.goRoute, DB70, own 25) comp%:")
    var compRows: [[Double]] = []
    for q in tiers {
        var crow: [Double] = []
        for w in tiers { crow.append(measurePass(.goRoute, off: offenseFor(qb:q,wr:w), def: defense70, yl: 25, n: GN).comp) }
        compRows.append(crow)
        print(String(format: "    QB%2d comp: ", q) + crow.map { String(format: "%6.1f", $0) }.joined())
    }
    var mono = true
    for r in 0..<tiers.count { for c in 1..<tiers.count { if compRows[r][c] + 1.0 < compRows[r][c-1] { mono = false } } }
    for c in 0..<tiers.count { for r in 1..<tiers.count { if compRows[r][c] + 1.0 < compRows[r-1][c] { mono = false } } }
    func tdRich(_ q: Int, _ w: Int) -> Double {
        var t = 0, a = 0
        for yl in [55, 65, 75] {
            let s = measurePass(.goRoute, off: offenseFor(qb:q,wr:w), def: defense70, yl: yl, n: GN/3)
            t += Int(s.td/100.0*Double(s.att) + 0.5); a += s.att
        }
        return pctf(t, a)
    }
    let tdElite = tdRich(95,95), tdWeak = tdRich(55,55)
    print(String(format: "    monotone(both axes)=%@   TD%%/att elite95=%.2f weak55=%.2f  spread=%.1fx (>=2x)",
        mono ? "YES" : "NO", tdElite, tdWeak, tdWeak > 0 ? tdElite/tdWeak : 99))
    // 1h. Keyed PA-deep @70.
    let keyed70 = measurePass(.playActionDeep, off: offenseFor(qb:70,wr:70), def: defense70, yl: 25, n: N, key: 1.0)
    let neut70  = measurePass(.playActionDeep, off: offenseFor(qb:70,wr:70), def: defense70, yl: 25, n: N, key: 0.0)
    print(String(format: "1h. KEYED PA-DEEP @70 netYPA=%.2f (neutral %.2f, +%.2f)  [band 9-12]",
        keyed70.netYPA, neut70.netYPA, keyed70.netYPA - neut70.netYPA))
}

// ---- pass-talent: CATEGORY 2 ------------------------------------------------
func scenarioPassTalent() {
    print("===== SCENARIO pass-talent: CATEGORY 2 — completion grids / CB axis / TE-RB paths =====")
    func grid(_ call: OffensivePlayCall, label: String) {
        print("2. \(label) comp% grid QB(rows)xWR(cols), DB70:")
        var rows: [[Double]] = []
        for q in tiers {
            var row: [Double] = []
            for w in tiers { row.append(measurePass(call, off: offenseFor(qb:q,wr:w), def: defense70, yl: 25, n: GN).comp) }
            rows.append(row)
            print(String(format: "    QB%2d: ", q) + row.map { String(format: "%6.1f", $0) }.joined())
        }
        var m = true
        for r in 0..<tiers.count { for c in 1..<tiers.count { if rows[r][c]+1.0 < rows[r][c-1] { m = false } } }
        for c in 0..<tiers.count { for r in 1..<tiers.count { if rows[r][c]+1.0 < rows[r-1][c] { m = false } } }
        let spread = rows[tiers.count-1][tiers.count-1] - rows[0][0]
        print(String(format: "    monotone(both)=%@  spread(95/95 - 55/55)=%.1f pts", m ? "YES" : "NO", spread))
    }
    grid(.slant, label: "SHORT (.slant)")
    grid(.dig,   label: "MID (.dig)")
    print("2b. COVERING-CB AXIS (offense 85/85 fixed; corners' coverage swept, safeties/LB=70):")
    for depth in [(OffensivePlayCall.slant,"short"),(.dig,"mid"),(.goRoute,"deep")] {
        let scrub = measurePass(depth.0, off: offenseFor(qb:85,wr:85), def: defenseFor(cbCov: 55), yl: 25, n: N)
        let avg   = measurePass(depth.0, off: offenseFor(qb:85,wr:85), def: defenseFor(cbCov: 70), yl: 25, n: N)
        let shut  = measurePass(depth.0, off: offenseFor(qb:85,wr:85), def: defenseFor(cbCov: 95), yl: 25, n: N)
        print(String(format: "    %-5@ CB55=%.1f%%  CB70=%.1f%%  CB95=%.1f%%   scrub-vs-shutdown Δ=%.1f pts",
            depth.1, scrub.comp, avg.comp, shut.comp, scrub.comp - shut.comp))
    }
    print("2c. TE/RB TARGET PATHS (raise the group; sanity monotone + non-degenerate):")
    for (call, pos) in [(OffensivePlayCall.seam,"TE seam"),(.stick,"TE/slot stick"),(.flat,"RB flat"),(.drag,"underneath drag")] {
        let lo = pos.hasPrefix("RB") ? measurePass(call, off: offenseFor(qb:70,wr:70,te:70,rb:55), def: defense70, yl: 25, n: N)
                                     : measurePass(call, off: offenseFor(qb:70,wr:70,te:55), def: defense70, yl: 25, n: N)
        let hi = pos.hasPrefix("RB") ? measurePass(call, off: offenseFor(qb:70,wr:70,te:70,rb:95), def: defense70, yl: 25, n: N)
                                     : measurePass(call, off: offenseFor(qb:70,wr:70,te:95), def: defense70, yl: 25, n: N)
        print(String(format: "    %-16@ tier55 comp=%.1f%% EV=%.1f | tier95 comp=%.1f%% EV=%.1f  Δcomp=%+.1f",
            pos, lo.comp, lo.ev, hi.comp, hi.ev, hi.comp - lo.comp))
    }
}

// ---- run-talent: CATEGORY 3 — RBxOL four cells + axes ------------------------
func scenarioRunTalent() {
    print("===== SCENARIO run-talent: CATEGORY 3 — RBxOL four cells + OL/front axes =====")
    let ELITE = 90, BAD = 50, AVG = 70
    func runYpc(rb: Int, ol: Int, front: Int) -> Double {
        measureRun(.insideRun, off: offenseFor(qb:70,wr:70,rb:rb,ol:ol), def: defenseFor(front: front), yl: 25, n: N).ypc
    }
    let cellA = runYpc(rb: ELITE, ol: BAD,   front: AVG)
    let cellB = runYpc(rb: BAD,   ol: ELITE, front: AVG)
    let cellC = runYpc(rb: ELITE, ol: ELITE, front: AVG)
    let cellA_ef = runYpc(rb: ELITE, ol: BAD,   front: ELITE)
    let cellB_ef = runYpc(rb: BAD,   ol: ELITE, front: ELITE)
    let cellC_ef = runYpc(rb: ELITE, ol: ELITE, front: ELITE)
    print("3a. THE FOUR CELLS (.insideRun, ypc):")
    print(String(format: "    eliteRB+badOL  = %.2f  (vs elite front %.2f)", cellA, cellA_ef))
    print(String(format: "    badRB+eliteOL  = %.2f  (vs elite front %.2f)", cellB, cellB_ef))
    print(String(format: "    elite+elite    = %.2f  (vs elite front %.2f)", cellC, cellC_ef))
    print(String(format: "    ORDER A<B<C: %@   |  elite front suppresses all: %@",
        (cellA < cellB && cellB < cellC) ? "YES" : "NO",
        (cellA_ef < cellA && cellB_ef < cellB && cellC_ef < cellC) ? "YES" : "NO"))
    print("3b. OL AXIS (RB70,front70):  " + [BAD,AVG,ELITE].map { String(format: "OL%d=%.2f", $0, runYpc(rb:70, ol:$0, front:70)) }.joined(separator: "  "))
    print("    FRONT AXIS (RB70,OL70):  " + [BAD,AVG,ELITE].map { String(format: "front%d=%.2f", $0, runYpc(rb:70, ol:70, front:$0)) }.joined(separator: "  "))
    let olMono = runYpc(rb:70,ol:BAD,front:70) < runYpc(rb:70,ol:AVG,front:70) && runYpc(rb:70,ol:AVG,front:70) < runYpc(rb:70,ol:ELITE,front:70)
    let frMono = runYpc(rb:70,ol:70,front:BAD) > runYpc(rb:70,ol:70,front:AVG) && runYpc(rb:70,ol:70,front:AVG) > runYpc(rb:70,ol:70,front:ELITE)
    print(String(format: "    OL monotone(up)=%@  FRONT monotone(down)=%@", olMono ? "YES" : "NO", frMono ? "YES" : "NO"))
}

// ---- familiarity: CATEGORY 4 — scheme familiarity sweeps + drive TD% --------
func scenarioFamiliarity() {
    print("===== SCENARIO familiarity: CATEGORY 4 — scheme-familiarity sweeps + drive TD% =====")
    let OS: OffensiveScheme = .westCoast
    let DS: DefensiveScheme = .cover3
    let sk = OS.rawValue
    func offFam(_ f: Int) -> [SimPlayer] { offenseFor(qb:70,wr:70, fam: [sk: f]) }
    func defFam(_ f: Int) -> [SimPlayer] { defenseFor(fam: [DS.rawValue: f]) }
    print("4a. OFFENSE FAMILIARITY SWEEP (scheme=\(sk), def neutral-nil → def side parity):")
    print("    fam |  pass comp% |  pass INT%  |  run ypc  | run stuff%")
    for f in [33, 66, 100] {
        let p = measurePass(.slant, off: offFam(f), def: defense70, yl: 25, n: N, offScheme: OS)
        let pm = measurePass(.dig, off: offFam(f), def: defense70, yl: 25, n: N, offScheme: OS)
        let rr = measureRun(.insideRun, off: offFam(f), def: defense70, yl: 25, n: N, offScheme: OS)
        print(String(format: "    %3d | short %.1f mid %.1f | %.2f | %.2f | %.1f%%", f, p.comp, pm.comp, p.int, rr.ypc, rr.stuffRate))
    }
    print("4b. DEFENSE FAMILIARITY SWEEP (def scheme=\(DS.rawValue); off neutral-nil):")
    print("    fam |  off pass comp%  (raw def coverage busts → MORE offense completions at low def-fam)")
    for f in [33, 66, 100] {
        let p = measurePass(.slant, off: o70, def: defFam(f), yl: 25, n: N, defScheme: DS)
        let pd = measurePass(.goRoute, off: o70, def: defFam(f), yl: 25, n: N, defScheme: DS)
        print(String(format: "    %3d | short %.1f  deep %.1f", f, p.comp, pd.comp))
    }
    func driveTDpct(offFamLvl: Int, drives: Int) -> Double {
        let off = offFam(offFamLvl)
        var tds = 0
        let mix: [OffensivePlayCall] = [.insideRun,.outsideRun,.counter,.slant,.dig,.curl,.drag,.goRoute,.stick,.draw,.toss,.hitch]
        var dr = 0
        while dr < drives { dr += 1
            var yardLine = 25, down = 1, dist = 10, plays = 0
            while plays < 25 {
                plays += 1
                let call = mix[(plays &* 7 &+ dr) % mix.count]
                let r = PlaySimulator.simulatePlay(offensePlayers: off, defensePlayers: defense70, down: down, distance: dist,
                    yardLine: yardLine, quarter: 2, timeRemaining: 450, momentum: 0, playNumber: plays,
                    offensiveScheme: OS, offensiveCall: call, defensivePackage: rp())
                if r.outcome == .penalty { continue }
                yardLine += r.yardsGained
                if yardLine >= 100 { tds += 1; break }
                if r.isTurnover || r.outcome == .interception || r.outcome == .fumbleLost { break }
                if yardLine <= 0 { break }
                if r.yardsGained >= dist { down = 1; dist = min(10, 100 - yardLine) }
                else { down += 1; dist -= r.yardsGained; if down > 4 { break } }
            }
        }
        return pctf(tds, drives)
    }
    let driveN = max(2000, N / 2)
    let td100 = driveTDpct(offFamLvl: 100, drives: driveN)
    let td66  = driveTDpct(offFamLvl: 66,  drives: driveN)
    let td33  = driveTDpct(offFamLvl: 33,  drives: driveN)
    print(String(format: "4c. DRIVE TD%%: fam100=%.1f%%  fam66=%.1f%%  fam33=%.1f%%   gap(100-33)=%.1f pts", td100, td66, td33, td100 - td33))
}

// ---- stacking: CATEGORY 5 — worst-case grand-cap floors ---------------------
func scenarioStacking() {
    print("===== SCENARIO stacking: CATEGORY 5 — worst-case grand-cap floors (even talent) =====")
    let OS: OffensiveScheme = .westCoast
    let sk = OS.rawValue
    func offFam(_ f: Int) -> [SimPlayer] { offenseFor(qb:70,wr:70, fam: [sk: f]) }
    // Worst-case RUN: spam inside + full macro key + fam20 bust, even 70 front.
    let spamMem = memAfter(Array(repeating: (OffensivePlayCall.insideRun, 1), count: 5))
    var dRun = deltas(for: .insideRun, mem: spamMem, down: 1)
    dRun.key = 1.0
    let stackRun = measureRun(.insideRun, off: offFam(20), def: defense70, yl: 25, n: N, key: 1.0, offScheme: OS, d: dRun)
    print(String(format: "5a. WORST-CASE RUN (spam+fullKey+fam20 bust, even 70 front): ypc=%.2f stuff=%.1f%% neg=%.1f%%",
        stackRun.ypc, stackRun.stuffRate, stackRun.negRate))
    print(String(format: "    runYardDelta=%.2f runStuffDelta=%.2f key=%.2f  (grandBiteCap=1.80 → floor must hold >=~1.8)",
        dRun.runYard, dRun.runStuff, dRun.key))
    // Worst-case DEEP: spam bomb + fam20.
    let spamBomb = memAfter(Array(repeating: (OffensivePlayCall.bomb, 1), count: 5))
    let dBomb = deltas(for: .bomb, mem: spamBomb, down: 1)
    let stackBomb = measurePass(.bomb, off: offFam(20), def: defense70, yl: 25, n: N, offScheme: OS, d: dBomb)
    print(String(format: "5b. WORST-CASE DEEP (spam bomb + fam20, even talent): comp=%.1f%% netYPA=%.2f pass.deepΔ=%.3f (cap 0.24)",
        stackBomb.comp, stackBomb.netYPA, dBomb.pass.deep))
    // Worst-case SHORT: spam slant + fam20.
    let spamSlant = memAfter(Array(repeating: (OffensivePlayCall.slant, 1), count: 5))
    let dSlant = deltas(for: .slant, mem: spamSlant, down: 1)
    let stackSlant = measurePass(.slant, off: offFam(20), def: defense70, yl: 25, n: N, offScheme: OS, d: dSlant)
    print(String(format: "5c. WORST-CASE SHORT (spam slant + fam20): comp=%.1f%% (must stay well above 0) pass.shortΔ=%.3f",
        stackSlant.comp, dSlant.pass.short))
}

// ---- spam: degenerate spam-collapse + mixed-parity (memory ON vs OFF) --------
func scenarioSpam() {
    print("===== SCENARIO spam: spam-collapse + mixed-parity (memory ON vs OFF) =====")
    func spamEV(_ call: OffensivePlayCall, reps: Int) -> Double {
        let mem = memAfter(Array(repeating: (call, 1), count: reps - 1))
        let d = deltas(for: call, mem: mem, down: 1)
        return measureRun(call, off: o70, def: defense70, yl: 25, n: N, d: d).ypc
    }
    let insideR1 = spamEV(.insideRun, reps: 1), insideR4 = spamEV(.insideRun, reps: 4)
    let tossR1 = spamEV(.toss, reps: 1), tossR4 = spamEV(.toss, reps: 4)
    print(String(format: "SPAM-COLLAPSE inside r1=%.2f r4=%.2f (%.0f%% of r1, target <=65%%, floor >=~1.8)  toss r1=%.2f r4=%.2f (%.0f%%)",
        insideR1, insideR4, insideR4/insideR1*100, tossR1, tossR4, tossR4/tossR1*100))
    // Mixed-parity: a varied 20-play script, memory ON vs OFF — the balanced-control guarantee.
    let script: [(OffensivePlayCall, Int, Int, Int)] = [
        (.insideRun,1,10,25),(.slant,2,6,30),(.outsideRun,1,10,38),(.curl,2,7,45),(.goRoute,3,7,48),(.counter,1,10,55),
        (.drag,2,5,60),(.dig,3,5,64),(.toss,1,10,70),(.seam,2,8,74),(.draw,1,10,40),(.quickOut,2,6,46),
        (.hitch,3,4,50),(.outsideRun,1,10,55),(.screen,2,7,60),(.post,3,6,63),(.insideRun,1,10,68),(.stick,2,5,72),
        (.comeback,3,5,75),(.jetSweep,1,10,30)]
    func runScript(memoryOn: Bool, cycles: Int) -> (ypc: Double, passEV: Double, maxShare: Double) {
        var m = PM(); m.catPivot = P50; m.catAlpha = A50
        var runY = 0, runN = 0, passY = 0, passDrop = 0; var maxShare = 0.0
        var c = 0
        while c < cycles { c += 1
            for (call, dn, dist, yl) in script {
                let d = memoryOn ? deltas(for: call, mem: m, down: dn) : Deltas()
                let r = PlaySimulator.simulatePlay(offensePlayers: o70, defensePlayers: defense70, down: dn, distance: dist,
                    yardLine: yl, quarter: 2, timeRemaining: 450, momentum: 0, playNumber: 5, offensiveCall: call,
                    defensivePackage: rp(), runKeyIntensity: d.key, passCompletionDelta: d.pass, runYardDelta: d.runYard, runStuffDelta: d.runStuff)
                if r.outcome != .penalty {
                    if r.playType == .run { runY += r.yardsGained; runN += 1 }
                    else if r.playType == .pass { passY += r.yardsGained; passDrop += 1 }
                }
                m.record(call: call, down: dn)
                for concept in AdaptiveOpponentAI.OffenseTendency.allCases { maxShare = max(maxShare, m.anticipation(of: concept, down: dn)) }
            }
        }
        return (Double(runY)/Double(max(1,runN)), Double(passY)/Double(max(1,passDrop)), maxShare)
    }
    let cycles = max(200, N / 30)
    let onR = runScript(memoryOn: true, cycles: cycles), offR = runScript(memoryOn: false, cycles: cycles)
    print(String(format: "MIXED-PARITY memory ON ypc=%.2f passEV=%.2f | OFF ypc=%.2f passEV=%.2f | Δypc=%+.2f ΔpassEV=%+.2f (|Δ|<=0.3) maxAnt=%.2f",
        onR.ypc, onR.passEV, offR.ypc, offR.passEV, onR.ypc - offR.ypc, onR.passEV - offR.passEV, onR.maxShare))
}

// ============================================================================
// Dispatcher
// ============================================================================
let allScenarios = ["percall", "depth", "keyed-pa", "regression", "pass-talent", "run-talent", "familiarity", "stacking", "spam"]
func run(_ name: String) {
    switch name {
    case "percall":     scenarioPerCall()
    case "depth":       scenarioDepth()
    case "keyed-pa":    scenarioKeyedPA()
    case "regression":  scenarioRegression()
    case "pass-talent": scenarioPassTalent()
    case "run-talent":  scenarioRunTalent()
    case "familiarity": scenarioFamiliarity()
    case "stacking":    scenarioStacking()
    case "spam":        scenarioSpam()
    default:
        FileHandle.standardError.write("unknown scenario: \(name)\n".data(using: .utf8)!)
        FileHandle.standardError.write("valid: \(allScenarios.joined(separator: ", ")), all\n".data(using: .utf8)!)
        exit(2)
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let requested: [String]
if args.isEmpty {
    FileHandle.standardError.write("usage: harness <scenario> [scenario ...]\n".data(using: .utf8)!)
    FileHandle.standardError.write("scenarios: \(allScenarios.joined(separator: ", ")), all\n".data(using: .utf8)!)
    exit(2)
} else if args.contains("all") {
    requested = allScenarios
} else {
    requested = args
}

print("######################################################################")
print("# BALANCE MEASUREMENT HARNESS  —  repo-literal engine  (N=\(N), GN=\(GN))")
print(String(format: "# paKeyCompletion(1.0)=%.3f  paKeyBigPlay(1.0)=%.2f  (repo 0.035/2.0)",
    AdaptiveOpponentAI.paKeyCompletion(1.0), AdaptiveOpponentAI.paKeyBigPlay(1.0)))
print("######################################################################")
for (i, name) in requested.enumerated() {
    print("")
    run(name)
    if i < requested.count - 1 { print("") }
}
print("\nDONE.")
