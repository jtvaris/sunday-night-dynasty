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
// Round-5 PARAMETERIZED scenarios (take `--flag value` args, not a name list;
// run on their own — never via `all` — see README "Round-5 full-game campaign"):
//   fullgame       complete games via the shipped GameSimulator/DriveSimulator
//                  pipeline; per-game box + N-game aggregates vs NFL bands + win split.
//                  fullgame --home-tier X --away-tier Y --n N [--home-override U=tier,…]
//                  [--home-asym elite-O/weak-D] [--archetypes sensitive|immune|mixed]
//                  [--fam 33|66|100] [--offense-style run-heavy|balanced|pass-heavy]
//                  [--seedable] [--seed N] [--detail]  (per-side --home-*/--away-* too)
//   positionsweep  one group swept {55,70,85,95} on an avg roster vs avg; win% + stat.
//                  positionsweep --group QB|RB|WR|TE|OL|DL|LB|CB|S --n N [--seedable]
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
// Round 4 (mental states) — builders + scenarios
// ============================================================================

/// MentalAttributes with awareness/DM/clutch all = c, so composureRating
/// (clutch·0.5 + DM·0.3 + awareness·0.2) collapses to exactly `c`.
func mentC(_ c: Int) -> MentalAttributes {
    MentalAttributes(awareness: c, decisionMaking: c, clutch: c, workEthic: 70, coachability: 70, leadership: 70)
}
/// SimPlayer with an explicit archetype / heat / composure (all attrs 70).
func mkM(_ n: String, _ p: Position, _ pa: PositionAttributes,
         arch: PersonalityArchetype = .steadyPerformer, heat: Double = 0, composure: Int = 70) -> SimPlayer {
    var sp = SimPlayer(fullName: n, position: p, physical: phys(70), mental: mentC(composure),
                       positionAttributes: pa, overall: 70, personalityArchetype: arch)
    sp.heat = heat
    return sp
}
/// 70-baseline offense with mental knobs. Receivers (WR/TE) share `recvArch`/
/// `recvHeat`; the RB and QB have their own. OL are neutral. `composure` applies
/// to every skill player. All attributes stay 70, so at heat 0 / composure 70
/// this is attribute-identical to `o70` (parity).
func offenseMental(recvArch: PersonalityArchetype = .fieryCompetitor, recvHeat: Double = 0,
                   qbArch: PersonalityArchetype = .steadyPerformer, qbHeat: Double = 0,
                   rbArch: PersonalityArchetype = .fieryCompetitor, rbHeat: Double = 0,
                   composure: Int = 70) -> [SimPlayer] {
    [ mkM("QB1", .QB, .quarterback(QBAttributes(armStrength:70,accuracyShort:70,accuracyMid:70,accuracyDeep:70,pocketPresence:70,scrambling:70)), arch: qbArch, heat: qbHeat, composure: composure),
      mkM("RB1", .RB, .runningBack(RBAttributes(vision:70,elusiveness:70,breakTackle:70,receiving:70)), arch: rbArch, heat: rbHeat, composure: composure),
      mkM("WR1", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), arch: recvArch, heat: recvHeat, composure: composure),
      mkM("WR2", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), arch: recvArch, heat: recvHeat, composure: composure),
      mkM("WR3", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), arch: recvArch, heat: recvHeat, composure: composure),
      mkM("TE1", .TE, .tightEnd(TEAttributes(blocking:70,catching:70,routeRunning:70,speed:70)), arch: recvArch, heat: recvHeat, composure: composure),
      mkM("LT1", .LT, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
      mkM("LG1", .LG, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
      mkM("C1",  .C,  .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
      mkM("RG1", .RG, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
      mkM("RT1", .RT, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))) ]
}

/// Completion% for a fully-specified situation (so leverage can be dialed).
func measurePassLev(_ call: OffensivePlayCall, off: [SimPlayer], def: [SimPlayer],
                    down: Int, dist: Int, q: Int, time: Int, yl: Int, scoreDiff: Int, n: Int) -> Double {
    var att = 0, comps = 0, i = 0
    while i < n { i += 1
        let r = PlaySimulator.simulatePlay(offensePlayers: off, defensePlayers: def, down: down, distance: dist,
            yardLine: yl, quarter: q, timeRemaining: time, momentum: 0, playNumber: 5, offensiveCall: call,
            defensivePackage: rp(), scoreDifferential: scoreDiff)
        switch r.outcome {
        case .completion, .touchdown: comps += 1; att += 1
        case .incompletion, .interception: att += 1
        default: break
        }
    }
    return pctf(comps, att)
}

// ---- heat-traj: HeatState trajectories per archetype class + feeder parity --
func scenarioHeatTraj() {
    print("===== SCENARIO heat-traj: HeatState trajectories per archetype class + feeder parity =====")
    let idS = UUID(), idN = UUID(), idI = UUID()
    let seq: [Double] = [HeatState.winStep, HeatState.winStep, HeatState.bigStep, -HeatState.lossStep,
                         -HeatState.turnoverStep, HeatState.winStep, HeatState.winStep, HeatState.bigStep]
    var hs = HeatState(), hn = HeatState(), hi = HeatState()
    var trajS: [Double] = [], trajI: [Double] = []
    for s in seq {
        hs.reward(idS, s, scaleEligible: true)   // form-sensitive → accumulates
        hn.reward(idN, s, scaleEligible: true)   // neutral        → accumulates identically
        hi.reward(idI, s, scaleEligible: false)  // form-immune    → never accumulates
        trajS.append(hs.value(idS)); trajI.append(hi.value(idI))
    }
    print("  sensitive traj: " + trajS.map { String(format: "%+.2f", $0) }.joined(separator: " "))
    print(String(format: "  sensitive == neutral (identical accumulation): %@  |Δ|=%.1e",
        abs(hs.value(idS) - hn.value(idN)) < 1e-12 ? "YES" : "NO", abs(hs.value(idS) - hn.value(idN))))
    print(String(format: "  immune stays FLAT 0.0: %@  (final immune heat=%.2f)",
        trajI.allSatisfy { $0 == 0 } ? "YES" : "NO", hi.value(idI)))
    var hc = HeatState(); for _ in 0..<10 { hc.reward(idS, HeatState.winStep, scaleEligible: true) }
    print(String(format: "  clamp: 10×winStep=%.2f (clamped to +1.00: %@)",
        hc.value(idS), hc.value(idS) <= 1.0 + 1e-9 ? "YES" : "NO"))
    var hd = HeatState(); hd.reward(idS, 0.90, scaleEligible: true)
    var decaySeq: [Double] = []
    for _ in 0..<6 { hd.decayAll(HeatState.decayPerDrive); decaySeq.append(hd.value(idS)) }
    print("  decay 0.90→ (×0.80/drive, snaps to 0 <0.02): " + decaySeq.map { String(format: "%.3f", $0) }.joined(separator: " "))
    // Feeder parity: LIVE and SIM feeders map each abstract battle outcome to the
    // SAME step (both reference HeatState.*), so an identical script → identical
    // heat, |Δ|=0 by construction.
    enum Ev { case won, lost, big, turnover }
    func step(_ e: Ev) -> Double {
        switch e { case .won: return HeatState.winStep; case .lost: return -HeatState.lossStep
                   case .big: return HeatState.bigStep; case .turnover: return -HeatState.turnoverStep } }
    let script: [Ev] = [.won,.lost,.big,.won,.turnover,.won,.big,.lost,.won,.won]
    let idL = UUID(), idM = UUID()
    var live = HeatState(), simh = HeatState()
    for e in script { live.reward(idL, step(e), scaleEligible: true); simh.reward(idM, step(e), scaleEligible: true) }
    print(String(format: "  FEEDER PARITY (same abstract script): live=%.4f sim=%.4f |Δ|=%.1e (must be 0)",
        live.value(idL), simh.value(idM), abs(live.value(idL) - simh.value(idM))))
}

// ---- heat-mag: modifier magnitudes at heat extremes -------------------------
func scenarioHeatMag() {
    print("===== SCENARIO heat-mag: mental modifier magnitudes at extremes (leverage 0) =====")
    // All receivers form-sensitive (whoever is targeted carries the heat); QB
    // immune (heatEffectScale 0) isolates the WR term. Own-25 early-down Q2 →
    // leverage 0 and composure 70 → composure contributes exactly 0.
    let base = measurePass(.slant, off: offenseMental(recvHeat: 0),    def: defense70, yl: 25, n: N)
    let hot  = measurePass(.slant, off: offenseMental(recvHeat: 1.0),  def: defense70, yl: 25, n: N)
    let cold = measurePass(.slant, off: offenseMental(recvHeat: -1.0), def: defense70, yl: 25, n: N)
    print(String(format: "  SHORT comp%%  cold(-1)=%.1f  neutral(0)=%.1f  hot(+1)=%.1f   Δhot=%+.1fpp Δcold=%+.1fpp  [hot band +4..+5, ~symmetric]",
        cold.comp, base.comp, hot.comp, hot.comp - base.comp, cold.comp - base.comp))
    let rBase = measureRun(.insideRun, off: offenseMental(rbHeat: 0),    def: defense70, yl: 25, n: N)
    let rHot  = measureRun(.insideRun, off: offenseMental(rbHeat: 1.0),  def: defense70, yl: 25, n: N)
    let rCold = measureRun(.insideRun, off: offenseMental(rbHeat: -1.0), def: defense70, yl: 25, n: N)
    print(String(format: "  RUN ypc      cold(-1)=%.2f  neutral(0)=%.2f  hot(+1)=%.2f   Δhot=%+.2f Δcold=%+.2f  [|Δ|<=~0.35]",
        rCold.ypc, rBase.ypc, rHot.ypc, rHot.ypc - rBase.ypc, rCold.ypc - rBase.ypc))
    // Immune archetype at full hot: heatEffectScale 0 → ZERO effect.
    let immHot = measurePass(.slant, off: offenseMental(recvArch: .steadyPerformer, recvHeat: 1.0), def: defense70, yl: 25, n: N)
    print(String(format: "  IMMUNE WR hot(+1) comp%%=%.1f vs neutral %.1f  Δ=%+.1fpp (must be ~0 — effectScale 0)",
        immHot.comp, base.comp, immHot.comp - base.comp))
}

// ---- composure-lev: composure × leverage grid + parity ----------------------
func scenarioComposureLev() {
    print("===== SCENARIO composure-lev: composure {45,70,90} × leverage {0,0.3,0.6,1.0} + parity =====")
    // Pure-function proof: leverageIndex buckets + composureSwing 70→0.
    let buckets: [(name: String, down: Int, dist: Int, q: Int, time: Int, yl: Int, sd: Int)] = [
        ("~0.0", 1, 10, 2, 450, 25,   0),   // neutral early down
        ("~0.3", 1, 10, 2, 450, 85,   0),   // red zone only
        ("~0.6", 1, 10, 2, 450, 85, -10),   // red zone + trailing 9+
        ("~1.0", 3,  8, 4, 450, 85,   0)]   // Q4 + red zone + 3rd&medium
    print("  leverageIndex per bucket:")
    for b in buckets {
        let L = PlaySimulator.leverageIndex(down: b.down, distance: b.dist, quarter: b.q,
                                            timeRemaining: b.time, yardLine: b.yl, scoreDifferential: b.sd)
        print(String(format: "    %@  down=%d dist=%d Q%d yl=%d sd=%d → L=%.2f", b.name, b.down, b.dist, b.q, b.yl, b.sd, L))
    }
    let probe45 = mkM("p", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), composure: 45)
    let probe70 = mkM("p", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), composure: 70)
    let probe90 = mkM("p", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), composure: 90)
    print(String(format: "  composureSwing @L=1.0: comp45=%+.1f comp70=%+.1f comp90=%+.1f  (70→0 parity: %@)",
        PlaySimulator.composureSwing(probe45, 1.0), PlaySimulator.composureSwing(probe70, 1.0),
        PlaySimulator.composureSwing(probe90, 1.0), PlaySimulator.composureSwing(probe70, 1.0) == 0 ? "YES" : "NO"))
    // Measured completion% grid comp[45/70/90] × leverage bucket. NOTE: a
    // composure-45 roster also carries lower awareness/DM (composureRating is
    // derived from them), which depresses the WHOLE column via the pre-existing
    // reading terms — a realistic entanglement, but it means the clean composure
    // signal is the CROSS-LEVERAGE trend within a fixed composure row, not the
    // vertical spread. The parity claim ("composure 70 → swing 0 at EVERY
    // leverage") reads off the comp70 row being FLAT across leverage.
    let comps = [45, 70, 90]
    var grid: [[Double]] = []
    for c in comps {
        var row: [Double] = []
        for b in buckets {
            row.append(measurePassLev(.slant, off: offenseMental(recvHeat: 0, composure: c), def: defense70,
                       down: b.down, dist: b.dist, q: b.q, time: b.time, yl: b.yl, scoreDiff: b.sd, n: N))
        }
        grid.append(row)
    }
    print("  SHORT comp% grid — rows = composure, cols = leverage bucket:")
    for (ci, c) in comps.enumerated() {
        print(String(format: "    comp%2d: ", c) + buckets.enumerated().map { (bi, b) in
            String(format: "L%@=%.1f", b.name, grid[ci][bi]) }.joined(separator: "  "))
    }
    // Parity: the comp70 row is flat across leverage (swing 0 everywhere). The
    // pure composureSwing(comp70)=+0.0 check above is the EXACT proof; this is a
    // measured confirmation, so the threshold tolerates per-cell sampling noise
    // (each cell ~±0.35pp SE → a ~1.5pp range across 4 cells is pure noise, and
    // it is dwarfed by the comp45/comp90 leverage trends below).
    let row70 = grid[1]
    let spread70 = row70.max()! - row70.min()!
    let flat70 = spread70 <= 2.0
    print(String(format: "  PARITY comp70 flat across leverage: %@  (spread=%.1fpp, ≤2.0 noise-tolerant; exact proof = swing 0.0 above)",
        flat70 ? "YES" : "NO", spread70))
    // Direction: as leverage rises, the shaky (comp45) SAGS, the poised (comp90)
    // RISES — each monotone in leverage, bounded by the caps.
    let row45 = grid[0], row90 = grid[2]
    let sags = row45.last! < row45.first! - 2.0
    let rises = row90.last! > row90.first! + 2.0
    print(String(format: "  DIRECTION comp45 L0→L1 %+.1fpp (sags: %@)   comp90 L0→L1 %+.1fpp (rises: %@)",
        row45.last! - row45.first!, sags ? "YES" : "NO",
        row90.last! - row90.first!, rises ? "YES" : "NO"))
}

// ---- mental-regression: round-4 PARITY GATE (subsumes regression) -----------
func scenarioMentalRegression() {
    print("===== SCENARIO mental-regression: round-4 PARITY GATE (heat=0, composure=70) =====")
    print("  Every player is heat=0 & composure=70, so every round-4 term is exactly 0.")
    // Neutral-parity spot check: default o70 vs a form-SENSITIVE roster with heat 0
    // & composure 70 — the archetype/heat machinery must contribute nothing.
    let a  = measurePass(.slant,    off: o70, def: defense70, yl: 25, n: N)
    let b  = measurePass(.slant,    off: offenseMental(recvHeat: 0, composure: 70), def: defense70, yl: 25, n: N)
    let ra = measureRun(.insideRun, off: o70, def: defense70, yl: 25, n: N)
    let rb = measureRun(.insideRun, off: offenseMental(rbHeat: 0, composure: 70), def: defense70, yl: 25, n: N)
    print(String(format: "  NEUTRAL PARITY  short comp%% default=%.1f sensitive-heat0=%.1f Δ=%+.2fpp (~0)  |  run ypc %.2f vs %.2f Δ=%+.2f (~0)",
        a.comp, b.comp, b.comp - a.comp, ra.ypc, rb.ypc, rb.ypc - ra.ypc))
    print("")
    scenarioRegression()
}

// ---- heat-dist: heat LIVE across drives — aggregate must not inflate --------
func scenarioHeatDist() {
    print("===== SCENARIO heat-dist: heat LIVE across drives (aggregate must not inflate) =====")
    // Mixed-archetype population, heat fed/stamped/decayed across a game's drives.
    // Heat is ~0-mean, so aggregate comp%/ypc must match the heat-OFF baseline
    // (an all-70 random-archetype roster with heat 0 is attribute-identical to o70).
    let archMix: [PersonalityArchetype] = [.fieryCompetitor, .feelPlayer, .dramaQueen, .classClown,
        .steadyPerformer, .quietProfessional, .teamLeader, .loneWolf, .mentor]
    func randOff() -> [SimPlayer] {
        func a() -> PersonalityArchetype { archMix.randomElement()! }
        return [ mkM("QB1", .QB, .quarterback(QBAttributes(armStrength:70,accuracyShort:70,accuracyMid:70,accuracyDeep:70,pocketPresence:70,scrambling:70)), arch: a()),
                 mkM("RB1", .RB, .runningBack(RBAttributes(vision:70,elusiveness:70,breakTackle:70,receiving:70)), arch: a()),
                 mkM("WR1", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), arch: a()),
                 mkM("WR2", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), arch: a()),
                 mkM("WR3", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), arch: a()),
                 mkM("TE1", .TE, .tightEnd(TEAttributes(blocking:70,catching:70,routeRunning:70,speed:70)), arch: a()),
                 mkM("LT1", .LT, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
                 mkM("LG1", .LG, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
                 mkM("C1",  .C,  .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
                 mkM("RG1", .RG, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
                 mkM("RT1", .RT, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))) ]
    }
    // A short mixed drive script (call, down, dist, yardLine).
    let script: [(OffensivePlayCall, Int, Int, Int)] = [
        (.insideRun,1,10,25),(.slant,2,7,32),(.outsideRun,1,10,40),(.dig,2,6,48),
        (.goRoute,3,7,52),(.counter,1,10,60),(.curl,2,5,66),(.toss,1,10,72)]
    func feed(_ r: PlayResult, into hs: inout HeatState, elig: (UUID) -> Bool) {
        let big = r.yardsGained >= 20
        switch r.outcome {
        case .touchdown: if let id = r.keyOffensePlayerID { hs.reward(id, HeatState.bigStep, scaleEligible: elig(id)) }
        case .completion: if let id = r.keyOffensePlayerID { hs.reward(id, big ? HeatState.bigStep : HeatState.winStep, scaleEligible: elig(id)) }
        case .rush: if let id = r.keyOffensePlayerID {   // bidirectional (mirrors GameSimulator.feedDriveHeat)
            if big { hs.reward(id, HeatState.bigStep, scaleEligible: elig(id)) }
            else if r.yardsGained >= 4 { hs.reward(id, HeatState.winStep, scaleEligible: elig(id)) }
            else if r.yardsGained <= 1 { hs.reward(id, -HeatState.lossStep, scaleEligible: elig(id)) } }
        case .incompletion:
            if r.wasDrop == true, let id = r.keyOffensePlayerID { hs.reward(id, -HeatState.lossStep, scaleEligible: elig(id)) }
            if r.passBreakup == true, let did = r.keyDefensePlayerID { hs.reward(did, HeatState.winStep, scaleEligible: elig(did)) }
        case .sack:
            if let id = r.keyOffensePlayerID { hs.reward(id, -HeatState.lossStep, scaleEligible: elig(id)) }
            if let did = r.keyDefensePlayerID { hs.reward(did, HeatState.bigStep, scaleEligible: elig(did)) }
        case .interception:
            if let id = r.keyOffensePlayerID { hs.reward(id, -HeatState.turnoverStep, scaleEligible: elig(id)) }
            if let did = r.keyDefensePlayerID { hs.reward(did, HeatState.bigStep, scaleEligible: elig(did)) }
        case .fumbleLost: if let id = r.keyOffensePlayerID { hs.reward(id, -HeatState.turnoverStep, scaleEligible: elig(id)) }
        default: break
        }
    }
    // Heat is per-GAME correlated (it accumulates across a game's drives), so the
    // drift-estimate variance scales with the number of independent GAMES, not
    // plays — use many games to stabilize the aggregate.
    let games = max(400, N / 40)
    let drivesPerGame = 12
    var onComp = 0, onAtt = 0, onRunY = 0, onRunN = 0
    for _ in 0..<games {
        let off0 = randOff()
        var hs = HeatState()
        var elig: [UUID: Bool] = [:]
        for p in off0 + defense70 { elig[p.id] = !p.personalityArchetype.isFormImmune }
        for _ in 0..<drivesPerGame {
            var off = off0
            for i in off.indices { off[i].heat = hs.value(off[i].id) }   // stamp
            for (call, dn, dist, yl) in script {
                let r = PlaySimulator.simulatePlay(offensePlayers: off, defensePlayers: defense70, down: dn,
                    distance: dist, yardLine: yl, quarter: 2, timeRemaining: 450, momentum: 0, playNumber: 5,
                    offensiveCall: call, defensivePackage: rp())
                if r.outcome == .penalty { continue }
                switch r.outcome {
                case .completion, .touchdown: onComp += 1; onAtt += 1
                case .incompletion, .interception: onAtt += 1
                default: break
                }
                if r.playType == .run { onRunY += r.yardsGained; onRunN += 1 }
                feed(r, into: &hs, elig: { elig[$0] ?? true })
            }
            hs.decayAll(HeatState.decayPerDrive)
        }
    }
    // Heat-OFF baseline over the identical script/volume (o70, heat always 0).
    var offComp = 0, offAtt = 0, offRunY = 0, offRunN = 0
    let totalDrives = games * drivesPerGame
    for _ in 0..<totalDrives {
        for (call, dn, dist, yl) in script {
            let r = PlaySimulator.simulatePlay(offensePlayers: o70, defensePlayers: defense70, down: dn,
                distance: dist, yardLine: yl, quarter: 2, timeRemaining: 450, momentum: 0, playNumber: 5,
                offensiveCall: call, defensivePackage: rp())
            if r.outcome == .penalty { continue }
            switch r.outcome {
            case .completion, .touchdown: offComp += 1; offAtt += 1
            case .incompletion, .interception: offAtt += 1
            default: break
            }
            if r.playType == .run { offRunY += r.yardsGained; offRunN += 1 }
        }
    }
    let onCompPct = pctf(onComp, onAtt), offCompPct = pctf(offComp, offAtt)
    let onYpc = Double(onRunY) / Double(max(1, onRunN)), offYpc = Double(offRunY) / Double(max(1, offRunN))
    print(String(format: "  games=%d drives=%d  HEAT-LIVE comp%%=%.2f ypc=%.2f  |  HEAT-OFF comp%%=%.2f ypc=%.2f",
        games, totalDrives, onCompPct, onYpc, offCompPct, offYpc))
    print(String(format: "  Δcomp%%=%+.2f (|Δ|<=~0.6)   Δypc=%+.2f (|Δ|<=~0.10)   — heat must NOT inflate aggregate",
        onCompPct - offCompPct, onYpc - offYpc))
}

// ============================================================================
// INDEPENDENT VERIFIER additions (round-4 audit) — new scenarios only; every
// pre-existing scenario above is untouched. These read the SAME synced,
// SHA-verified engine sources.
// ============================================================================

// ---- heat-ratio: form-sensitive vs neutral vs immune magnitude ratio --------
// Design: completion bump at full hot ∝ heatEffectScale (sensitive 1.0, neutral
// 0.60, immune 0.0). Archetype touches the pass composite ONLY through
// heatEffectScale, so same attrs + same heat, varying archetype, isolates the
// ratio. High N to resolve the small (few-pp) deltas cleanly.
func scenarioHeatRatio() {
    print("===== SCENARIO heat-ratio: sensitive vs NEUTRAL vs immune magnitude ratio =====")
    let bigN = max(N, 120000)
    func bump(_ arch: PersonalityArchetype) -> Double {
        let base = measurePass(.slant, off: offenseMental(recvArch: arch, recvHeat: 0),   def: defense70, yl: 25, n: bigN)
        let hot  = measurePass(.slant, off: offenseMental(recvArch: arch, recvHeat: 1.0), def: defense70, yl: 25, n: bigN)
        return hot.comp - base.comp
    }
    let dS = bump(.fieryCompetitor)   // form-sensitive → scale 1.0
    let dU = bump(.mentor)            // neutral        → scale 0.60
    let dI = bump(.steadyPerformer)   // form-immune    → scale 0.0
    print(String(format: "  Δcomp @hot(+1): sensitive=%+.2fpp  neutral=%+.2fpp  immune=%+.2fpp   (N=%d each cell)", dS, dU, dI, bigN))
    print(String(format: "  design scale: sensitive 1.0 / neutral 0.60 / immune 0.0 → expected +4.5 / +2.7 / +0.0 pp"))
    print(String(format: "  measured neutral/sensitive ratio=%.2f (design 0.60)  immune ~0: %@",
        dS != 0 ? dU / dS : 0, abs(dI) < 0.6 ? "YES" : "NO"))
}

// ---- macro: 200+ full-ish game sims — scoring distribution, heat-live vs off -
// A possession-model game engine over PlaySimulator.simulatePlay (the only
// resolvable path in the harness): realistic pass/run mix, first downs, FG range,
// punts, turnovers, TD=7 / FG=3. Two conditions over the identical volume:
//   • HEAT-LIVE  — per-game HeatState, stamped each drive, fed by the SIM feeder
//                  mapping (mirrors GameSimulator.feedDriveHeat), decayed.
//   • HEAT-OFF   — heat always 0 (attribute-identical rosters).
// Reports points/team/game mean + spread + NFL-plausible-band share, and the
// live-vs-off gap (must be ~0 → no heat-driven scoring inflation).
func scenarioMacro() {
    print("===== SCENARIO macro: 200+ full-ish game sims — scoring dist + heat-live vs off =====")
    let games = max(200, N / 100)
    let drivesPerGame = 22           // ~11 possessions/team
    let passMix: [OffensivePlayCall] = [.slant,.dig,.curl,.drag,.hitch,.quickOut,.stick,.goRoute,.post,.seam,.comeback,.screen]
    let runMix:  [OffensivePlayCall] = [.insideRun,.insideRun,.outsideRun,.counter,.draw,.toss,.dive]
    let archMix: [PersonalityArchetype] = [.fieryCompetitor, .feelPlayer, .dramaQueen, .classClown,
        .steadyPerformer, .quietProfessional, .teamLeader, .loneWolf, .mentor]
    func a() -> PersonalityArchetype { archMix.randomElement()! }
    func randOff() -> [SimPlayer] {
        [ mkM("QB1", .QB, .quarterback(QBAttributes(armStrength:70,accuracyShort:70,accuracyMid:70,accuracyDeep:70,pocketPresence:70,scrambling:70)), arch: a()),
          mkM("RB1", .RB, .runningBack(RBAttributes(vision:70,elusiveness:70,breakTackle:70,receiving:70)), arch: a()),
          mkM("WR1", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), arch: a()),
          mkM("WR2", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), arch: a()),
          mkM("WR3", .WR, .wideReceiver(WRAttributes(routeRunning:70,catching:70,release:70,spectacularCatch:70)), arch: a()),
          mkM("TE1", .TE, .tightEnd(TEAttributes(blocking:70,catching:70,routeRunning:70,speed:70)), arch: a()),
          mkM("LT1", .LT, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
          mkM("LG1", .LG, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
          mkM("C1",  .C,  .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
          mkM("RG1", .RG, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))),
          mkM("RT1", .RT, .offensiveLine(OLAttributes(runBlock:70,passBlock:70,pull:70,anchor:70))) ]
    }
    func randDef() -> [SimPlayer] {
        [ mkM("DE1", .DE, .defensiveLine(DLAttributes(passRush:70,blockShedding:70,powerMoves:70,finesseMoves:70)), arch: a()),
          mkM("DE2", .DE, .defensiveLine(DLAttributes(passRush:70,blockShedding:70,powerMoves:70,finesseMoves:70)), arch: a()),
          mkM("DT1", .DT, .defensiveLine(DLAttributes(passRush:70,blockShedding:70,powerMoves:70,finesseMoves:70)), arch: a()),
          mkM("DT2", .DT, .defensiveLine(DLAttributes(passRush:70,blockShedding:70,powerMoves:70,finesseMoves:70)), arch: a()),
          mkM("OLB1", .OLB, .linebacker(LBAttributes(tackling:70,zoneCoverage:70,manCoverage:70,blitzing:70)), arch: a()),
          mkM("OLB2", .OLB, .linebacker(LBAttributes(tackling:70,zoneCoverage:70,manCoverage:70,blitzing:70)), arch: a()),
          mkM("MLB1", .MLB, .linebacker(LBAttributes(tackling:70,zoneCoverage:70,manCoverage:70,blitzing:70)), arch: a()),
          mkM("CB1", .CB, .defensiveBack(DBAttributes(manCoverage:70,zoneCoverage:70,press:70,ballSkills:70)), arch: a()),
          mkM("CB2", .CB, .defensiveBack(DBAttributes(manCoverage:70,zoneCoverage:70,press:70,ballSkills:70)), arch: a()),
          mkM("FS1", .FS, .defensiveBack(DBAttributes(manCoverage:70,zoneCoverage:70,press:70,ballSkills:70)), arch: a()),
          mkM("SS1", .SS, .defensiveBack(DBAttributes(manCoverage:70,zoneCoverage:70,press:70,ballSkills:70)), arch: a()) ]
    }
    // SIM-feeder mapping (mirrors GameSimulator.feedDriveHeat) over one drive's plays.
    // Routes offense-key rewards to the possessing team's heat, defense-key rewards
    // to the defending team's heat — the same split GameSimulator's shared tracker
    // makes by unique player IDs. Bidirectional so a hot defense cools completions.
    func feedDrive(_ plays: [PlayResult], offHeat: inout HeatState, defHeat: inout HeatState, elig: (UUID) -> Bool) {
        for r in plays {
            let big = r.yardsGained >= 20
            switch r.outcome {
            case .touchdown: if let id = r.keyOffensePlayerID { offHeat.reward(id, HeatState.bigStep, scaleEligible: elig(id)) }
            case .completion: if let id = r.keyOffensePlayerID { offHeat.reward(id, big ? HeatState.bigStep : HeatState.winStep, scaleEligible: elig(id)) }
            case .rush: if let id = r.keyOffensePlayerID {
                if big { offHeat.reward(id, HeatState.bigStep, scaleEligible: elig(id)) }
                else if r.yardsGained >= 4 { offHeat.reward(id, HeatState.winStep, scaleEligible: elig(id)) }
                else if r.yardsGained <= 1 { offHeat.reward(id, -HeatState.lossStep, scaleEligible: elig(id)) } }
            case .incompletion:
                // ROUND-6 (mirror GameSimulator): bidirectional receiver heat — ANY
                // incompletion cools the target by lossStep (was drop-only), zeroing
                // the one-way completion ratchet. Breakup still credits the defender.
                if let id = r.keyOffensePlayerID { offHeat.reward(id, -HeatState.passMissStep, scaleEligible: elig(id)) }
                if r.passBreakup == true, let did = r.keyDefensePlayerID { defHeat.reward(did, HeatState.winStep, scaleEligible: elig(did)) }
            case .sack:
                if let id = r.keyOffensePlayerID { offHeat.reward(id, -HeatState.lossStep, scaleEligible: elig(id)) }
                if let did = r.keyDefensePlayerID { defHeat.reward(did, HeatState.bigStep, scaleEligible: elig(did)) }
            case .interception:
                if let id = r.keyOffensePlayerID { offHeat.reward(id, -HeatState.turnoverStep, scaleEligible: elig(id)) }
                if let did = r.keyDefensePlayerID { defHeat.reward(did, HeatState.bigStep, scaleEligible: elig(did)) }
            case .fumbleLost: if let id = r.keyOffensePlayerID { offHeat.reward(id, -HeatState.turnoverStep, scaleEligible: elig(id)) }
            default: break
            }
        }
    }
    func fgMakeProb(_ kickYds: Int) -> Double {
        switch kickYds { case ..<36: return 0.94; case ..<44: return 0.82; case ..<50: return 0.68; case ..<56: return 0.50; default: return 0.30 }
    }
    // Simulate one team's drive from `startYL` against the given defense; returns (points, plays[]).
    func simDrive(off: [SimPlayer], def: [SimPlayer], startYL: Int, quarter: Int, scoreDiff: Int) -> (pts: Int, plays: [PlayResult]) {
        var yardLine = startYL, down = 1, dist = 10, snaps = 0
        var plays: [PlayResult] = []
        while snaps < 22 {
            snaps += 1
            let longToGo = dist >= 7
            let passProb = down >= 3 ? (longToGo ? 0.85 : 0.55) : (down == 2 && longToGo ? 0.62 : 0.50)
            let isPass = Double.random(in: 0..<1) < passProb
            let call = isPass ? passMix.randomElement()! : runMix.randomElement()!
            let r = PlaySimulator.simulatePlay(offensePlayers: off, defensePlayers: def, down: down, distance: dist,
                yardLine: yardLine, quarter: quarter, timeRemaining: 450, momentum: 0, playNumber: snaps,
                offensiveCall: call, defensivePackage: rp(), scoreDifferential: scoreDiff)
            if r.outcome == .penalty { snaps -= 1; if snaps < 0 { snaps = 0 }; continue }
            plays.append(r)
            if r.isTurnover || r.outcome == .interception || r.outcome == .fumbleLost { return (0, plays) }
            yardLine += r.yardsGained
            if yardLine >= 100 { return (7, plays) }                 // TD + XP
            if yardLine < 1 { return (0, plays) }                    // backed up / safety-ish → punt-equiv
            if r.yardsGained >= dist {                               // first down
                down = 1; dist = min(10, 100 - yardLine)
            } else {
                down += 1; dist -= r.yardsGained
                if down > 4 { break }
            }
            if down == 4 {                                           // kick or punt on 4th
                let kickYds = (100 - yardLine) + 17
                if kickYds <= 55 { return (Double.random(in: 0..<1) < fgMakeProb(kickYds) ? 3 : 0, plays) }
                return (0, plays)                                    // punt
            }
        }
        return (0, plays)
    }
    func playGame(heatLive: Bool) -> (home: Int, away: Int, comp: (Int,Int), run: (Int,Int), ints: Int, att: Int) {
        let homeOff = randOff(), homeDef = randDef()
        let awayOff = randOff(), awayDef = randDef()
        // One heat tracker per team, spanning its FULL 22-man roster (offense +
        // defense), exactly like GameSimulator threads a per-team stamp off a
        // shared per-game HeatState.
        var homeHeat = HeatState(), awayHeat = HeatState()
        var elig: [UUID: Bool] = [:]
        for p in homeOff + homeDef + awayOff + awayDef { elig[p.id] = !p.personalityArchetype.isFormImmune }
        var hScore = 0, aScore = 0
        var comps = 0, atts = 0, runY = 0, runN = 0, ints = 0
        for d in 0..<drivesPerGame {
            let homeBall = d % 2 == 0
            let quarter = min(4, d / (drivesPerGame / 4) + 1)
            var off = homeBall ? homeOff : awayOff
            var def = homeBall ? awayDef : homeDef
            if heatLive {
                let offSrc = homeBall ? homeHeat : awayHeat      // possessing team
                let defSrc = homeBall ? awayHeat : homeHeat      // defending team
                for i in off.indices { off[i].heat = offSrc.value(off[i].id) }
                for i in def.indices { def[i].heat = defSrc.value(def[i].id) }
            }
            let scoreDiff = homeBall ? hScore - aScore : aScore - hScore
            let res = simDrive(off: off, def: def, startYL: 25, quarter: quarter, scoreDiff: scoreDiff)
            if homeBall { hScore += res.pts } else { aScore += res.pts }
            for r in res.plays {
                switch r.outcome {
                case .completion, .touchdown: comps += 1; atts += 1
                case .incompletion: atts += 1
                case .interception: atts += 1; ints += 1
                default: break
                }
                if r.playType == .run { runY += r.yardsGained; runN += 1 }
            }
            if heatLive {
                // offense-keys → possessing team's heat; defense-keys → defending team's.
                if homeBall { feedDrive(res.plays, offHeat: &homeHeat, defHeat: &awayHeat, elig: { elig[$0] ?? true }) }
                else        { feedDrive(res.plays, offHeat: &awayHeat, defHeat: &homeHeat, elig: { elig[$0] ?? true }) }
                homeHeat.decayAll(HeatState.decayPerDrive)   // one drive boundary → both
                awayHeat.decayAll(HeatState.decayPerDrive)   // teams decay once, as in the engine
            }
        }
        return (hScore, aScore, (comps, atts), (runY, runN), ints, atts)
    }
    func runCondition(heatLive: Bool) -> (mean: Double, sd: Double, lo: Int, hi: Int, bandPct: Double, comp: Double, ypc: Double, intPct: Double) {
        var teamPts: [Int] = []; teamPts.reserveCapacity(games * 2)
        var comps = 0, atts = 0, runY = 0, runN = 0, ints = 0
        for _ in 0..<games {
            let g = playGame(heatLive: heatLive)
            teamPts.append(g.home); teamPts.append(g.away)
            comps += g.comp.0; atts += g.comp.1; runY += g.run.0; runN += g.run.1; ints += g.ints
        }
        let n = Double(teamPts.count)
        let mean = Double(teamPts.reduce(0,+)) / n
        let varc = teamPts.reduce(0.0) { $0 + pow(Double($1) - mean, 2) } / n
        let band = teamPts.filter { $0 >= 10 && $0 <= 38 }.count
        return (mean, sqrt(varc), teamPts.min() ?? 0, teamPts.max() ?? 0, Double(band)/n*100,
                pctf(comps, atts), Double(runY)/Double(max(1,runN)), pctf(ints, atts))
    }
    let live = runCondition(heatLive: true)
    let off  = runCondition(heatLive: false)
    print(String(format: "  games=%d  team-seasons=%d per condition", games, games*2))
    print(String(format: "  HEAT-LIVE  pts/team/game mean=%.1f  sd=%.1f  [min %d, max %d]  10-38 band=%.0f%%  comp%%=%.1f ypc=%.2f INT%%=%.2f",
        live.mean, live.sd, live.lo, live.hi, live.bandPct, live.comp, live.ypc, live.intPct))
    print(String(format: "  HEAT-OFF   pts/team/game mean=%.1f  sd=%.1f  [min %d, max %d]  10-38 band=%.0f%%  comp%%=%.1f ypc=%.2f INT%%=%.2f",
        off.mean, off.sd, off.lo, off.hi, off.bandPct, off.comp, off.ypc, off.intPct))
    print(String(format: "  Δmean(live-off)=%+.2f pts (|Δ|<=~0.6 → no heat-driven scoring inflation)   Δcomp%%=%+.2f Δypc=%+.2f Δint%%=%+.2f",
        live.mean - off.mean, live.comp - off.comp, live.ypc - off.ypc, live.intPct - off.intPct))
    print(String(format: "  NFL sanity: mean 17-27 pts/team is realistic → mean %.1f %@",
        live.mean, (live.mean >= 15 && live.mean <= 30) ? "OK" : "OUT-OF-BAND"))
}

// ============================================================================
// ROUND 5 — FULL-GAME CAMPAIGN
// ============================================================================
// Runs COMPLETE games through the SHIPPED GameSimulator → DriveSimulator →
// PlaySimulator pipeline (all sha-verified verbatim sources) against generated
// tier rosters. Nothing here reimplements the game loop, box score, or heat
// feed — it drives the real engine and reads the real BoxScore. See README §
// "Round-5 full-game campaign".
// ============================================================================

// ---- Seedable harness RNG (roster generation only) --------------------------
// SplitMix64 gives reproducible ROSTER draws under --seedable. NOTE: the engine's
// play-by-play uses Swift's global (unseedable) RNG, so games still carry
// Monte-Carlo noise even when the rosters are fixed — that is unavoidable without
// touching the engine, and it is exactly why campaigns run N games and report bands.
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
var hrng = SplitMix64(seed: 0x5EED_1234_ABCD_0F01)
func seedRNG(_ f: [String: String]) {
    if f["seedable"] != nil {
        hrng = SplitMix64(seed: UInt64(f["seed"] ?? "") ?? 0x5EED_1234_ABCD_0F01)
    } else {
        var sys = SystemRandomNumberGenerator()
        hrng = SplitMix64(seed: sys.next())
    }
}

// ---- Named tiers ------------------------------------------------------------
// elite 88-95 · good 80-87 · avg 70-79 · weak 55-69 (a bare number ⇒ that exact grade).
func tierBand(_ name: String) -> ClosedRange<Int>? {
    switch name.lowercased() {
    case "elite":            return 88...95
    case "good":             return 80...87
    case "avg", "average":   return 70...79
    case "weak":             return 55...69
    default:                 if let n = Int(name) { return n...n }; return nil
    }
}

// ---- Roster layout: a full two-way 25-man squad -----------------------------
struct Slot { let name: String; let pos: Position; let unit: String; let idx: Int }
let rosterLayout: [Slot] = [
    Slot(name: "QB1", pos: .QB, unit: "QB", idx: 0),
    Slot(name: "RB1", pos: .RB, unit: "RB", idx: 0), Slot(name: "RB2", pos: .RB, unit: "RB", idx: 1),
    Slot(name: "WR1", pos: .WR, unit: "WR", idx: 0), Slot(name: "WR2", pos: .WR, unit: "WR", idx: 1), Slot(name: "WR3", pos: .WR, unit: "WR", idx: 2),
    Slot(name: "TE1", pos: .TE, unit: "TE", idx: 0),
    Slot(name: "LT", pos: .LT, unit: "OL", idx: 0), Slot(name: "LG", pos: .LG, unit: "OL", idx: 1), Slot(name: "C", pos: .C, unit: "OL", idx: 2),
    Slot(name: "RG", pos: .RG, unit: "OL", idx: 3), Slot(name: "RT", pos: .RT, unit: "OL", idx: 4),
    Slot(name: "DE1", pos: .DE, unit: "DL", idx: 0), Slot(name: "DE2", pos: .DE, unit: "DL", idx: 1),
    Slot(name: "DT1", pos: .DT, unit: "DL", idx: 2), Slot(name: "DT2", pos: .DT, unit: "DL", idx: 3),
    Slot(name: "OLB1", pos: .OLB, unit: "LB", idx: 0), Slot(name: "OLB2", pos: .OLB, unit: "LB", idx: 1), Slot(name: "MLB1", pos: .MLB, unit: "LB", idx: 2),
    Slot(name: "CB1", pos: .CB, unit: "CB", idx: 0), Slot(name: "CB2", pos: .CB, unit: "CB", idx: 1),
    Slot(name: "FS1", pos: .FS, unit: "S", idx: 0), Slot(name: "SS1", pos: .SS, unit: "S", idx: 1),
    Slot(name: "K1", pos: .K, unit: "K", idx: 0), Slot(name: "P1", pos: .P, unit: "P", idx: 0),
]
let unitOrder = ["QB", "RB", "WR", "TE", "OL", "DL", "LB", "CB", "S"]
func unitCount(_ u: String) -> Int { rosterLayout.filter { $0.unit == u.uppercased() }.count }

/// Position attributes with every rating pinned to a single grade `g` — so a
/// "tier-88" player is uniformly ~88 across his attribute cluster.
func posAttr(_ pos: Position, _ g: Int) -> PositionAttributes {
    switch pos {
    case .QB:                    return .quarterback(QBAttributes(armStrength: g, accuracyShort: g, accuracyMid: g, accuracyDeep: g, pocketPresence: g, scrambling: g))
    case .RB, .FB:               return .runningBack(RBAttributes(vision: g, elusiveness: g, breakTackle: g, receiving: g))
    case .WR:                    return .wideReceiver(WRAttributes(routeRunning: g, catching: g, release: g, spectacularCatch: g))
    case .TE:                    return .tightEnd(TEAttributes(blocking: g, catching: g, routeRunning: g, speed: g))
    case .LT, .LG, .C, .RG, .RT: return .offensiveLine(OLAttributes(runBlock: g, passBlock: g, pull: g, anchor: g))
    case .DE, .DT:               return .defensiveLine(DLAttributes(passRush: g, blockShedding: g, powerMoves: g, finesseMoves: g))
    case .OLB, .MLB:             return .linebacker(LBAttributes(tackling: g, zoneCoverage: g, manCoverage: g, blitzing: g))
    case .CB, .FS, .SS:          return .defensiveBack(DBAttributes(manCoverage: g, zoneCoverage: g, press: g, ballSkills: g))
    default:                     return .kicking(KickingAttributes(kickPower: g, kickAccuracy: g))
    }
}

let archMixFull: [PersonalityArchetype] = [.fieryCompetitor, .feelPlayer, .dramaQueen, .classClown,
    .steadyPerformer, .quietProfessional, .teamLeader, .loneWolf, .mentor]
func archetypeFor(_ mode: String) -> PersonalityArchetype {
    switch mode.lowercased() {
    case "sensitive": return .fieryCompetitor    // isFormSensitive, heatEffectScale 1.0
    case "immune":    return .steadyPerformer     // isFormImmune,    heatEffectScale 0.0
    default:          return archMixFull.randomElement(using: &hrng)!
    }
}
func planFor(_ style: String?) -> GamePlan? {
    guard let s = style?.lowercased() else { return nil }
    var gp = GamePlan.balanced
    switch s {
    case "run-heavy", "run":   gp.runPassRatio = 0.25
    case "pass-heavy", "pass": gp.runPassRatio = 0.75
    default:                   gp.runPassRatio = 0.50
    }
    return gp
}

// ---- Roster spec ------------------------------------------------------------
struct RosterSpec {
    var tier: String = "avg"
    var overrides: [String: (band: ClosedRange<Int>, count: Int)] = [:]
    var archetypes: String = "mixed"
    var fam: Int? = nil
    var style: String? = nil
}
func describe(_ s: RosterSpec) -> String {
    var parts = ["tier=\(s.tier)"]
    if !s.overrides.isEmpty {
        let ovs = unitOrder.compactMap { u -> String? in
            guard let o = s.overrides[u] else { return nil }
            let cnt = o.count < unitCount(u) ? "x\(o.count)" : ""
            return "\(u)=\(o.band.lowerBound == o.band.upperBound ? "\(o.band.lowerBound)" : "\(o.band.lowerBound)-\(o.band.upperBound)")\(cnt)"
        }
        parts.append("override[\(ovs.joined(separator: ","))]")
    }
    if s.archetypes != "mixed" { parts.append("arch=\(s.archetypes)") }
    if let f = s.fam { parts.append("fam=\(f)") }
    if let st = s.style { parts.append("style=\(st)") }
    return parts.joined(separator: " ")
}

/// Builds one team's roster (+ neutral scheme-carrying coaches when familiarity
/// is exercised, + a GamePlan when an offense style is set).
func buildRoster(_ spec: RosterSpec, side: String) -> (team: Team, coaches: [Coach], plan: GamePlan?) {
    let baseBand = tierBand(spec.tier) ?? 70...79
    let osKey = OffensiveScheme.westCoast.rawValue
    let dsKey = DefensiveScheme.cover3.rawValue
    var players: [Player] = []
    players.reserveCapacity(rosterLayout.count)
    for slot in rosterLayout {
        let band: ClosedRange<Int>
        if let o = spec.overrides[slot.unit], slot.idx < o.count { band = o.band } else { band = baseBand }
        let g = Int.random(in: band, using: &hrng)
        var fam: [String: Int] = [:]
        if let f = spec.fam { fam[osKey] = f; fam[dsKey] = f }
        players.append(Player(
            fullName: "\(side)-\(slot.name)", position: slot.pos,
            physical: PhysicalAttributes(speed: g, acceleration: g, strength: g, agility: g, stamina: 70, durability: 70),
            mental: MentalAttributes(awareness: g, decisionMaking: g, clutch: g, workEthic: 70, coachability: 70, leadership: 70),
            positionAttributes: posAttr(slot.pos, g),
            personalityArchetype: archetypeFor(spec.archetypes),
            overall: g, schemeFamiliarity: fam))
    }
    var coaches: [Coach] = []
    if spec.fam != nil {
        // Grade-70 neutral staff — carries the schemes so directFamiliarity /
        // scheme-fit fire, without any CoachingModifiers edge (every mechanic
        // is centered at 70 ⇒ ~0 effect).
        coaches = [Coach(role: .offensiveCoordinator, offensiveScheme: .westCoast),
                   Coach(role: .defensiveCoordinator, defensiveScheme: .cover3),
                   Coach(role: .headCoach)]
    }
    return (Team(players: players), coaches, planFor(spec.style))
}

// ---- Per-team box line extracted from a finished game -----------------------
struct TeamLine {
    var pts = 0, passYds = 0, rushYds = 0, totYds = 0, plays = 0, rushAtt = 0
    var sacks = 0, ints = 0, comps = 0, atts = 0, thirdC = 0, thirdA = 0
    var firstDowns = 0, passTD = 0, rushTD = 0, retTD = 0, turnovers = 0
    var compPct: Double { atts > 0 ? Double(comps) / Double(atts) * 100 : 0 }
    var thirdPct: Double { thirdA > 0 ? Double(thirdC) / Double(thirdA) * 100 : 0 }
    var netYPA: Double { (atts + sacks) > 0 ? Double(passYds) / Double(atts + sacks) : 0 }
    var ypc: Double { rushAtt > 0 ? Double(rushYds) / Double(rushAtt) : 0 }
}
func teamLine(_ box: TeamBoxScore, drives: [DriveResult], teamID: UUID) -> TeamLine {
    var L = TeamLine()
    L.pts = box.score; L.passYds = box.passingYards; L.rushYds = box.rushingYards
    L.totYds = box.totalYards; L.sacks = box.sacks; L.turnovers = box.turnovers
    L.thirdC = box.thirdDownConversions; L.thirdA = box.thirdDownAttempts; L.firstDowns = box.firstDowns
    for drive in drives where drive.teamID == teamID {
        for p in drive.plays {
            if p.outcome == .penalty { continue }
            if p.playType == .pass || p.playType == .run { L.plays += 1 }
            if p.playType == .run { L.rushAtt += 1 }
            switch p.outcome {
            case .completion:   L.comps += 1; L.atts += 1
            case .incompletion: L.atts += 1
            case .interception: L.atts += 1; L.ints += 1
            case .touchdown:
                if p.playType == .pass { L.comps += 1; L.atts += 1; L.passTD += 1 }
                else if p.playType == .run { L.rushTD += 1 }
                else if p.playType == .kickoff { L.retTD += 1 }
            default: break     // sacks (excluded from att), FG, punt, etc.
            }
        }
    }
    return L
}
func fmtLine(_ L: TeamLine) -> String {
    String(format: "%2dpt %3dyd(%3dp/%3dr) %2dpl %dsk %dint %.0f%%cmp %.1fnYPA %.1fypc %d/%d-3rd TD %dp/%dr%@",
        L.pts, L.totYds, L.passYds, L.rushYds, L.plays, L.sacks, L.ints, L.compPct,
        L.netYPA, L.ypc, L.thirdC, L.thirdA, L.passTD, L.rushTD, L.retTD > 0 ? "/\(L.retTD)ret" : "")
}

// ---- Aggregates -------------------------------------------------------------
func meanD(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
func sdD(_ xs: [Double]) -> Double {
    guard xs.count > 1 else { return 0 }
    let m = meanD(xs); return (xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count)).squareRoot()
}
func band(_ v: Double, _ lo: Double, _ hi: Double) -> String { (v >= lo && v <= hi) ? "OK " : "OUT" }

struct Aggregate {
    var lines: [TeamLine] = []
    var pts: [Double] { lines.map { Double($0.pts) } }
    var totYds: [Double] { lines.map { Double($0.totYds) } }
    var meanPts: Double { meanD(pts) }
    var meanPassYds: Double { meanD(lines.map { Double($0.passYds) }) }
    var meanRushYds: Double { meanD(lines.map { Double($0.rushYds) }) }
    var meanTotYds: Double { meanD(totYds) }
    var meanPlays: Double { meanD(lines.map { Double($0.plays) }) }
    var meanSacks: Double { meanD(lines.map { Double($0.sacks) }) }
    var meanInts: Double { meanD(lines.map { Double($0.ints) }) }
    var meanFirst: Double { meanD(lines.map { Double($0.firstDowns) }) }
    var meanPassTD: Double { meanD(lines.map { Double($0.passTD) }) }
    var meanRushTD: Double { meanD(lines.map { Double($0.rushTD) }) }
    // Pooled ratios (total/total) — avoids small-sample per-game ratio bias.
    var compPct: Double { let c = lines.reduce(0) { $0 + $1.comps }, a = lines.reduce(0) { $0 + $1.atts }; return a > 0 ? Double(c) / Double(a) * 100 : 0 }
    var thirdPct: Double { let c = lines.reduce(0) { $0 + $1.thirdC }, a = lines.reduce(0) { $0 + $1.thirdA }; return a > 0 ? Double(c) / Double(a) * 100 : 0 }
    var netYPA: Double { let y = lines.reduce(0) { $0 + $1.passYds }, a = lines.reduce(0) { $0 + $1.atts + $1.sacks }; return a > 0 ? Double(y) / Double(a) : 0 }
    var ypc: Double { let y = lines.reduce(0) { $0 + $1.rushYds }, a = lines.reduce(0) { $0 + $1.rushAtt }; return a > 0 ? Double(y) / Double(a) : 0 }
}

func printBandTable(_ a: Aggregate) {
    print("  --- per-team-per-game aggregate (both teams pooled, N×2 team-games) vs NFL bands ---")
    print(String(format: "    points     %6.1f  (sd %.1f, min %.0f max %.0f)   band 17-27   [%@]",
        a.meanPts, sdD(a.pts), a.pts.min() ?? 0, a.pts.max() ?? 0, band(a.meanPts, 17, 27)))
    print(String(format: "    total yds  %6.1f  (sd %.1f)                    band 300-400 [%@]", a.meanTotYds, sdD(a.totYds), band(a.meanTotYds, 300, 400)))
    print(String(format: "    pass yds   %6.1f                               band 200-250 [%@]", a.meanPassYds, band(a.meanPassYds, 200, 250)))
    print(String(format: "    rush yds   %6.1f                               band 100-130 [%@]", a.meanRushYds, band(a.meanRushYds, 100, 130)))
    print(String(format: "    plays      %6.1f                               band 58-68   [%@]", a.meanPlays, band(a.meanPlays, 58, 68)))
    print(String(format: "    sacks-took %6.2f                               band 2-3     [%@]", a.meanSacks, band(a.meanSacks, 2, 3)))
    print(String(format: "    INT thrown %6.2f                               band 0.7-1.3 [%@]", a.meanInts, band(a.meanInts, 0.7, 1.3)))
    print(String(format: "    completion %6.1f%%                              band 60-67   [%@]", a.compPct, band(a.compPct, 60, 67)))
    print(String(format: "    ypc        %6.2f                               band 3.9-4.6 [%@]", a.ypc, band(a.ypc, 3.9, 4.6)))
    print(String(format: "    net YPA    %6.2f                               band 5.9-7.5 [%@]", a.netYPA, band(a.netYPA, 5.9, 7.5)))
    print(String(format: "    3rd-down   %6.1f%%                              band 35-45   [%@]", a.thirdPct, band(a.thirdPct, 35, 45)))
    print(String(format: "    TD/team    %.2f pass + %.2f rush  first-downs %.1f", a.meanPassTD, a.meanRushTD, a.meanFirst))
}

// ---- fullgame scenario ------------------------------------------------------
func scenarioFullGame(_ f: [String: String]) {
    let n = Int(f["n"] ?? "") ?? 20
    seedRNG(f)
    let homeSpec = specFrom(f, side: "home")
    let awaySpec = specFrom(f, side: "away")
    print("===== SCENARIO fullgame: complete games via GameSimulator/DriveSimulator pipeline =====")
    print("  HOME: \(describe(homeSpec))")
    print("  AWAY: \(describe(awaySpec))")
    print("  games=\(n)  seedable=\(f["seedable"] != nil ? "rosters-fixed" : "no")  (engine play-by-play RNG is always stochastic)")
    var home = Aggregate(), away = Aggregate(), both = Aggregate()
    var homeWins = 0, awayWins = 0, ties = 0
    var margins: [Double] = []
    let detail = n <= 8 || f["detail"] != nil
    let t0 = Date()
    for i in 0..<n {
        let (ht, hc, hp) = buildRoster(homeSpec, side: "H")
        let (at, ac, ap) = buildRoster(awaySpec, side: "A")
        let r = GameSimulator.simulate(homeTeam: ht, awayTeam: at, homeCoaches: hc, awayCoaches: ac,
                                       homeGamePlan: hp, awayGamePlan: ap)
        let hl = teamLine(r.boxScore.home, drives: r.boxScore.drives, teamID: ht.id)
        let al = teamLine(r.boxScore.away, drives: r.boxScore.drives, teamID: at.id)
        home.lines.append(hl); away.lines.append(al); both.lines.append(hl); both.lines.append(al)
        margins.append(Double(r.homeScore - r.awayScore))
        if r.homeScore > r.awayScore { homeWins += 1 } else if r.awayScore > r.homeScore { awayWins += 1 } else { ties += 1 }
        if detail {
            print(String(format: "  G%02d  H %2d-%2d A  | H: %@ | A: %@", i + 1, r.homeScore, r.awayScore, fmtLine(hl), fmtLine(al)))
        }
    }
    let elapsed = Date().timeIntervalSince(t0)
    print("")
    printBandTable(both)
    let hp = Double(homeWins) / Double(n) * 100, apw = Double(awayWins) / Double(n) * 100, tp = Double(ties) / Double(n) * 100
    print(String(format: "  WIN SPLIT  home=%.1f%% away=%.1f%% tie=%.1f%%   home margin mean=%+.1f (sd %.1f)  home pts %.1f | away pts %.1f",
        hp, apw, tp, meanD(margins), sdD(margins), home.meanPts, away.meanPts))
    print(String(format: "  PER-SIDE   HOME off: passYds/g=%.0f netYPA=%.2f comp=%.1f%%  |  AWAY off: passYds/g=%.0f netYPA=%.2f comp=%.1f%%",
        home.meanPassYds, home.netYPA, home.compPct, away.meanPassYds, away.netYPA, away.compPct))
    print(String(format: "  RUNTIME  %d games in %.2fs = %.1f games/sec", n, elapsed, Double(n) / max(elapsed, 0.0001)))
}

// ---- positionsweep scenario -------------------------------------------------
func scenarioPositionSweep(_ f: [String: String]) {
    let group = (f["group"] ?? "QB").uppercased()
    let n = Int(f["n"] ?? "") ?? 20
    seedRNG(f)
    guard unitOrder.contains(group) else {
        FileHandle.standardError.write("positionsweep: unknown --group \(group); valid: \(unitOrder.joined(separator: "|"))\n".data(using: .utf8)!)
        exit(2)
    }
    print("===== SCENARIO positionsweep: group \(group) swept {55,70,85,95} on avg roster vs avg =====")
    print("  N=\(n) full games per point. Home sweeps \(group); away is straight avg. headline = the group's signal.")
    func headline(_ group: String, home: Aggregate, away: Aggregate) -> String {
        switch group {
        case "QB": return String(format: "home comp%%=%.1f  home netYPA=%.2f", home.compPct, home.netYPA)
        case "RB": return String(format: "home ypc=%.2f  rushYds/g=%.0f", home.ypc, home.meanRushYds)
        case "WR": return String(format: "home passYds/g=%.0f  comp%%=%.1f", home.meanPassYds, home.compPct)
        case "TE": return String(format: "home comp%%=%.1f  passYds/g=%.0f", home.compPct, home.meanPassYds)
        case "OL": return String(format: "home ypc=%.2f  sacks-allowed/g=%.2f", home.ypc, home.meanSacks)
        case "DL": return String(format: "sacks-made/g=%.2f (opp took)  opp ypc=%.2f", away.meanSacks, away.ypc)
        case "LB": return String(format: "opp ypc=%.2f  opp rushYds/g=%.0f", away.ypc, away.meanRushYds)
        case "CB": return String(format: "opp comp%%=%.1f  opp netYPA=%.2f", away.compPct, away.netYPA)
        case "S":  return String(format: "opp passYds/g=%.0f  opp comp%%=%.1f", away.meanPassYds, away.compPct)
        default:   return String(format: "home comp%%=%.1f", home.compPct)
        }
    }
    print(String(format: "  %-5@ | %-8@ | %-9@ | %-9@ | %@", "grade", "home-win%", "home-pts", "away-pts", "headline stat"))
    let t0 = Date(); var totalGames = 0
    for g in [55, 70, 85, 95] {
        var homeSpec = RosterSpec(); homeSpec.tier = "avg"; homeSpec.overrides[group] = (g...g, unitCount(group))
        var awaySpec = RosterSpec(); awaySpec.tier = "avg"
        var home = Aggregate(), away = Aggregate()
        var homeWins = 0
        for _ in 0..<n {
            let (ht, hc, hp) = buildRoster(homeSpec, side: "H")
            let (at, ac, ap) = buildRoster(awaySpec, side: "A")
            let r = GameSimulator.simulate(homeTeam: ht, awayTeam: at, homeCoaches: hc, awayCoaches: ac, homeGamePlan: hp, awayGamePlan: ap)
            home.lines.append(teamLine(r.boxScore.home, drives: r.boxScore.drives, teamID: ht.id))
            away.lines.append(teamLine(r.boxScore.away, drives: r.boxScore.drives, teamID: at.id))
            if r.homeScore > r.awayScore { homeWins += 1 }
            totalGames += 1
        }
        print(String(format: "  %-5d | %7.1f%% | %9.1f | %9.1f | %@",
            g, Double(homeWins) / Double(n) * 100, home.meanPts, away.meanPts, headline(group, home: home, away: away)))
    }
    let elapsed = Date().timeIntervalSince(t0)
    print(String(format: "  RUNTIME  %d games in %.2fs = %.1f games/sec", totalGames, elapsed, Double(totalGames) / max(elapsed, 0.0001)))
}

// ---- attribution scenario ---------------------------------------------------
// Decomposes the full-game net-YPA (~8.4) vs the per-play blend (~6.4) using the
// SHIPPED sim play-calling brain (GameSimulator's DriveSimulator loop). All-70
// rosters — byte-identical to the per-play calibration roster — so any gap is
// PURE play-selection (offensive call mix + pass-depth mix + defensive package).
func scenarioAttribution() {
    print("===== SCENARIO attribution: full-game net-YPA (~8.4) vs per-play blend (~6.4) decomposition =====")
    let off = offenseFor()        // all-70, identical to the per-play calibration roster
    let def = defenseFor()        // all-70
    let AN = max(N, 60000)
    let drives = Int(ProcessInfo.processInfo.environment["BH_DRIVES"] ?? "") ?? 12000

    // Mirror of PlaySimulator.choosePassDistance (for the realized depth mix).
    // Kept in sync with the engine: P0-1 pulled the deep share from ~24% to
    // ~10-12% (short 0.68/0.52/0.30, deep 0.08/0.12/0.26 by distance bucket).
    func depthProbs(_ distance: Int, _ yardLine: Int) -> (s: Double, m: Double, d: Double) {
        if 100 - yardLine <= 10 { return (1, 0, 0) }
        if distance <= 5  { return (0.68, 0.24, 0.08) }
        if distance <= 10 { return (0.52, 0.36, 0.12) }
        return (0.30, 0.44, 0.26)
    }
    func bandIdx(_ d: Int) -> Int { d <= 3 ? 0 : (d <= 6 ? 1 : (d <= 10 ? 2 : 3)) }

    // ---- (1) run real drives through the SHIPPED sim play-calling brain ----
    var passCt = Array(repeating: Array(repeating: 0, count: 4), count: 5)   // [down][band]
    var runCt  = Array(repeating: Array(repeating: 0, count: 4), count: 5)
    var gtY = 0, gtDrop = 0                                                  // ground-truth net-YPA
    var sMix = 0.0, mMix = 0.0, dMix = 0.0, passPlays = 0.0
    var earlyPass = 0, earlyTot = 0
    var thirdPass = 0, thirdTot = 0
    var samples: [(Int, Int, Int)] = []; samples.reserveCapacity(60000)
    let tid = UUID()
    for i in 0..<drives {
        var rk = AdaptiveOpponentAI.RunKeyState()
        let r = DriveSimulator.simulateDrive(
            offensePlayers: off, defensePlayers: def, startingYardLine: 25,
            driveNumber: i + 1, quarter: 1, timeRemaining: 900, momentum: 0,
            teamID: tid, runKeyState: &rk)
        for p in r.drive.plays {
            let bi = bandIdx(p.distance)
            let dn = min(max(p.down, 1), 4)
            if p.playType == .pass {
                passCt[dn][bi] += 1
                if p.outcome != .penalty { gtDrop += 1; gtY += p.yardsGained; samples.append((p.down, p.distance, p.yardLine)) }
                let pr = depthProbs(p.distance, p.yardLine)
                sMix += pr.s; mMix += pr.m; dMix += pr.d; passPlays += 1
                if dn <= 2 { earlyPass += 1; earlyTot += 1 }
                if dn == 3 { thirdPass += 1; thirdTot += 1 }
            } else if p.playType == .run {
                runCt[dn][bi] += 1
                if dn <= 2 { earlyTot += 1 }
                if dn == 3 { thirdTot += 1 }
            }
        }
    }
    let gtNet = Double(gtY) / Double(max(1, gtDrop))
    let totPass = passCt.flatMap { $0 }.reduce(0, +)
    let totRun  = runCt.flatMap { $0 }.reduce(0, +)
    let passRate = Double(totPass) / Double(max(1, totPass + totRun)) * 100
    let sShare = sMix / passPlays, mShare = mMix / passPlays, dShare = dMix / passPlays

    print(String(format: "  SIM brain over %d drives (all-70, gamePlan=nil balanced, defensivePackage=SITUATIONAL as the P0-1 DriveSimulator now wires it):", drives))
    print(String(format: "    overall pass rate = %.1f%% (NFL ~57-60%%)  early-down(1&2) pass = %.1f%% (NFL ~50%%)  3rd-down pass = %.1f%%",
        passRate, Double(earlyPass) / Double(max(1, earlyTot)) * 100, Double(thirdPass) / Double(max(1, thirdTot)) * 100))
    print("    pass% by down x distance-to-go band (blank = no snaps):")
    print("      down |   1-3     4-6    7-10     11+")
    for dn in 1...4 {
        var cells = ""
        for bi in 0..<4 {
            let pc = passCt[dn][bi], rc = runCt[dn][bi], tot = pc + rc
            cells += tot == 0 ? "     -  " : String(format: "  %5.0f%%", Double(pc) / Double(tot) * 100)
        }
        print(String(format: "      %4d |%@", dn, cells))
    }
    print(String(format: "    realized pass-DEPTH mix (choosePassDistance): short=%.0f%% mid=%.0f%% DEEP=%.0f%%  [per-play blend=45/40/15; NFL deep ~10-12%%]",
        sShare * 100, mShare * 100, dShare * 100))
    print(String(format: "    GROUND-TRUTH sim net-YPA (drive plays) = %.2f", gtNet))

    // ---- (2) per-depth net-YPA vs standard MIX and vs NIL package (mechanism) ----
    func measDepth(_ call: OffensivePlayCall, nilPkg: Bool) -> Double {
        var allY = 0, drop = 0, i = 0
        while i < AN { i += 1
            let r = PlaySimulator.simulatePlay(
                offensePlayers: off, defensePlayers: def, down: 1, distance: 10,
                yardLine: 25, quarter: 2, timeRemaining: 450, momentum: 0, playNumber: 5,
                offensiveCall: call, defensivePackage: nilPkg ? nil : rp())
            if r.outcome == .penalty { continue }
            drop += 1; allY += r.yardsGained
        }
        return Double(allY) / Double(max(1, drop))
    }
    let shMix = measDepth(.slant, nilPkg: false), mdMix = measDepth(.dig, nilPkg: false), dpMix = measDepth(.goRoute, nilPkg: false)
    let shNil = measDepth(.slant, nilPkg: true),  mdNil = measDepth(.dig, nilPkg: true),  dpNil = measDepth(.goRoute, nilPkg: true)
    print("")
    print("  per-depth net-YPA basis:  short   mid    deep")
    print(String(format: "    vs standard MIX rp():  %5.2f  %5.2f  %5.2f", shMix, mdMix, dpMix))
    print(String(format: "    vs NIL pkg (sim path): %5.2f  %5.2f  %5.2f", shNil, mdNil, dpNil))
    print(String(format: "    NIL package tax removed: short +%.2f  mid +%.2f  deep +%.2f  (mean coverage tax the sim skips)", shNil - shMix, mdNil - mdMix, dpNil - dpMix))

    // ---- (3) additive decomposition on the ACTUAL generic-pass engine path ----
    func genNet(_ pick: () -> (Int, Int, Int), _ pkg: () -> DefensivePackage?, _ n: Int) -> Double {
        var allY = 0, drop = 0, i = 0
        while i < n { i += 1
            let (dn, ds, yl) = pick()
            let r = PlaySimulator.simulatePlay(
                offensePlayers: off, defensePlayers: def, down: dn, distance: ds,
                yardLine: yl, quarter: 2, timeRemaining: 450, momentum: 0, playNumber: 5,
                forcedPlayType: .pass, defensivePackage: pkg())
            if r.outcome == .penalty { continue }
            drop += 1; allY += r.yardsGained
        }
        return Double(allY) / Double(max(1, drop))
    }
    let neutral: () -> (Int, Int, Int) = { (1, 10, 25) }
    let realized: () -> (Int, Int, Int) = { samples.isEmpty ? (1, 10, 25) : samples.randomElement()! }
    let mixPkg: () -> DefensivePackage? = { rp() }
    let nilPkg: () -> DefensivePackage? = { nil }

    let b0 = shMix * 0.45 + mdMix * 0.40 + dpMix * 0.15          // per-play blend anchor (~6.47)
    let gNeutralMix = genNet(neutral, mixPkg, AN)                 // generic path, neutral down, mix pkg
    let gRealMix    = genNet(realized, mixPkg, AN)                // + real passing-down distribution
    let gRealNil    = genNet(realized, nilPkg, AN)               // + nil package (the sim path) ~= gtNet

    print("")
    print("  DECOMPOSITION of the net-YPA gap (each step is a real engine measurement):")
    print(String(format: "    (B0) per-play blend  45/40/15 x per-depth(mix)                 = %6.2f", b0))
    print(String(format: "    (+)  generic-path + neutral-down depth (named->generic pass)   = %+6.2f   -> %.2f", gNeutralMix - b0, gNeutralMix))
    print(String(format: "    (+)  situational depth skew (neutral -> real passing downs)    = %+6.2f   -> %.2f", gRealMix - gNeutralMix, gRealMix))
    print(String(format: "    (+)  DEF-MIX delta (standard mix rp() -> NIL package)          = %+6.2f   -> %.2f", gRealNil - gRealMix, gRealNil))
    print(String(format: "    (=)  reconstructed full-game net-YPA                           = %6.2f   (drive ground truth %.2f)", gRealNil, gtNet))
    print(String(format: "    call-mix bucket (depth) = %+.2f | def-mix bucket (nil pkg) = %+.2f | residual/situational = %+.2f",
        (gNeutralMix - b0) + (gRealMix - gNeutralMix), gRealNil - gRealMix, gtNet - gRealNil))

    // ---- (4) end-to-end counterfactual: faithful drive loop (mirrors
    // DriveSimulator.simulateDrive, reusing its own static helpers) run with the
    // sim's NIL package vs the standard league mix wired in, to show the
    // downstream points / 3rd-down / net-YPA all move into band together.
    func simDriveCounterfactual(_ pkg: () -> DefensivePackage?, _ nDrives: Int) -> (pts: Double, third: Double, net: Double, plays: Double) {
        var totPts = 0, thirdC = 0, thirdA = 0, py = 0, drop = 0, playCt = 0, ndr = 0
        for i in 0..<nDrives {
            var rk = AdaptiveOpponentAI.RunKeyState()
            var down = 1, dist = 10, yl = 25, q = 1, t = 900, pn = 1
            if 100 - yl < 10 { dist = 100 - yl }
            ndr += 1
            loop: while true {
                if t <= 0 && DriveSimulator.shouldEndDrive(quarter: q) { break }
                let ki = rk.keyIntensity(down: down)
                let r = PlaySimulator.simulatePlay(
                    offensePlayers: off, defensePlayers: def, down: down, distance: dist,
                    yardLine: yl, quarter: q, timeRemaining: t, momentum: 0, playNumber: pn,
                    defensivePackage: pkg(), runKeyIntensity: ki)
                if r.playType == .run || r.playType == .pass { playCt += 1 }
                if r.playType == .pass && r.outcome != .penalty { drop += 1; py += r.yardsGained }
                if (r.playType == .run || r.playType == .pass) && down == 3 && r.outcome != .penalty {
                    thirdA += 1; if r.isFirstDown || r.outcome == .touchdown { thirdC += 1 }
                }
                if r.playType == .run || r.playType == .pass { rk.record(isRun: r.playType == .run, down: down) }
                t -= DriveSimulator.clockConsumption(for: r)
                if t <= 0 {
                    if DriveSimulator.shouldEndDrive(quarter: q) { break }
                    q += 1; t = 900
                }
                if r.outcome == .touchdown { totPts += 7; break }
                if r.outcome == .fieldGoalGood { totPts += 3; break }
                switch r.outcome {
                case .fieldGoalMissed, .interception, .fumbleLost, .punt, .touchback, .safety: break loop
                default: break
                }
                let adv = DriveSimulator.advanceDownAndDistance(playResult: r, currentDown: down, currentDistance: dist, currentYardLine: yl)
                down = adv.down; dist = adv.distance; yl = adv.yardLine
                if down > 4 { break }
                pn += 1
                if pn > 40 { break }
            }
        }
        return (Double(totPts) / Double(ndr), Double(thirdC) / Double(max(1, thirdA)) * 100,
                Double(py) / Double(max(1, drop)), Double(playCt) / Double(ndr))
    }
    let cfN = 12000
    let cfNil = simDriveCounterfactual({ nil }, cfN)
    let cfMix = simDriveCounterfactual({ rp() }, cfN)
    print("")
    print("  END-TO-END COUNTERFACTUAL (faithful drive loop; drives cross halves, so pts/drive is a within-run comparison):")
    print(String(format: "    sim path (NIL package):      net-YPA=%.2f  3rd-down=%.1f%%  pts/drive=%.2f  plays/drive=%.1f",
        cfNil.net, cfNil.third, cfNil.pts, cfNil.plays))
    print(String(format: "    FIX (standard league mix):   net-YPA=%.2f  3rd-down=%.1f%%  pts/drive=%.2f  plays/drive=%.1f",
        cfMix.net, cfMix.third, cfMix.pts, cfMix.plays))
    print(String(format: "    delta from wiring the package: net-YPA %+.2f  3rd-down %+.1fpp  pts/drive %+.1f%%",
        cfMix.net - cfNil.net, cfMix.third - cfNil.third, (cfMix.pts / cfNil.pts - 1) * 100))
}

// ---- Flag / spec parsing ----------------------------------------------------
func parseFlags(_ a: [String]) -> [String: String] {
    var d: [String: String] = [:]
    var i = 0
    while i < a.count {
        let t = a[i]
        guard t.hasPrefix("--") else { i += 1; continue }
        let key = String(t.dropFirst(2))
        if i + 1 < a.count && !a[i + 1].hasPrefix("--") { d[key] = a[i + 1]; i += 2 }
        else { d[key] = "true"; i += 1 }   // boolean flag, e.g. --seedable
    }
    return d
}
/// Parses "QB=95,OL=weak,CB=95x2" → unit → (band, count). Comma-separated (no
/// spaces — a single arg token). Tier is a name or a bare grade; optional `xN`
/// applies the override to only the first N players of the unit.
func parseOverrides(_ s: String) -> [String: (band: ClosedRange<Int>, count: Int)] {
    var ov: [String: (band: ClosedRange<Int>, count: Int)] = [:]
    for item in s.split(whereSeparator: { $0 == "," }) {
        let kv = item.split(separator: "=", maxSplits: 1)
        guard kv.count == 2 else { continue }
        let unit = kv[0].uppercased()
        var tierTok = String(kv[1]); var count = unitCount(unit)
        if let xr = tierTok.range(of: "x") {
            count = Int(tierTok[xr.upperBound...]) ?? count
            tierTok = String(tierTok[..<xr.lowerBound])
        }
        guard let b = tierBand(tierTok) else { continue }
        ov[unit] = (b, count)
    }
    return ov
}
/// Merges an asym preset like "elite-O/weak-D" (offense units elite, defense weak).
func mergeAsym(_ ov: inout [String: (band: ClosedRange<Int>, count: Int)], _ spec: String) {
    for part in spec.lowercased().split(whereSeparator: { $0 == "/" || $0 == "," }) {
        let comps = part.split(separator: "-").map(String.init)
        guard comps.count >= 2, let sideLetter = comps.last else { continue }
        let tierName = comps.dropLast().joined(separator: "-")
        guard let b = tierBand(tierName) else { continue }
        let units = sideLetter.hasPrefix("o") ? ["QB", "RB", "WR", "TE", "OL"] : ["DL", "LB", "CB", "S"]
        for u in units { ov[u] = (b, unitCount(u)) }
    }
}
func specFrom(_ f: [String: String], side: String) -> RosterSpec {
    var s = RosterSpec()
    s.tier = f["\(side)-tier"] ?? f["tier"] ?? "avg"
    var ov = parseOverrides(f["\(side)-override"] ?? f["override"] ?? "")
    if let asym = f["\(side)-asym"] ?? (side == "home" ? f["asym"] : nil) { mergeAsym(&ov, asym) }
    s.overrides = ov
    s.archetypes = f["\(side)-archetypes"] ?? f["archetypes"] ?? "mixed"
    s.fam = Int(f["\(side)-fam"] ?? f["fam"] ?? "")
    s.style = f["\(side)-offense-style"] ?? f["offense-style"]
    return s
}

// ============================================================================
// Dispatcher
// ============================================================================
let allScenarios = ["percall", "depth", "keyed-pa", "regression", "pass-talent", "run-talent", "familiarity", "stacking", "spam",
                    "heat-traj", "heat-mag", "composure-lev", "mental-regression", "heat-dist", "heat-ratio", "macro"]
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
    case "heat-traj":         scenarioHeatTraj()
    case "heat-mag":          scenarioHeatMag()
    case "composure-lev":     scenarioComposureLev()
    case "mental-regression": scenarioMentalRegression()
    case "heat-dist":         scenarioHeatDist()
    case "heat-ratio":        scenarioHeatRatio()
    case "macro":             scenarioMacro()
    case "attribution":       scenarioAttribution()
    default:
        FileHandle.standardError.write("unknown scenario: \(name)\n".data(using: .utf8)!)
        FileHandle.standardError.write("valid: \(allScenarios.joined(separator: ", ")), all\n".data(using: .utf8)!)
        exit(2)
    }
}

let args = Array(CommandLine.arguments.dropFirst())

func printHeader() {
    print("######################################################################")
    print("# BALANCE MEASUREMENT HARNESS  —  repo-literal engine  (N=\(N), GN=\(GN))")
    print(String(format: "# paKeyCompletion(1.0)=%.3f  paKeyBigPlay(1.0)=%.2f  (repo 0.035/2.0)",
        AdaptiveOpponentAI.paKeyCompletion(1.0), AdaptiveOpponentAI.paKeyBigPlay(1.0)))
    print("######################################################################")
}

// ---- blowoutprobe scenario (P0-2 compounding analysis) ----------------------
// Reconstructs the SCORE TRAJECTORY from the ordered drive stream (engine
// untouched) to quantify where the margin comes from: per-quarter cumulative
// margin, drives/team, and "garbage-time" points (points a team scores while
// already leading by >= gtLead BEFORE that drive). Evidences the missing
// score-aware/comeback feedback and sizes the tail-cap mechanism.
func scenarioBlowoutProbe(_ f: [String: String]) {
    let n = Int(f["n"] ?? "") ?? 300
    let gtLead = Int(f["gtlead"] ?? "") ?? 21
    let matchups: [(String, String)] = [
        ("avg", "avg"), ("good", "avg"), ("avg", "weak"),
        ("good", "weak"), ("elite", "avg"), ("elite", "weak"),
    ]
    print("===== SCENARIO blowoutprobe: score-trajectory / garbage-time (gtLead=\(gtLead)) =====")
    print(String(format: "  %-13@ | %-5@ | %-24@ | %-11@ | %@", "matchup", "drv/t",
        "cum margin Q1/Q2/Q3/Q4", "final marg", "leader GT-pts (share of margin)"))
    for (hT, aT) in matchups {
        seedRNG(f)
        var hSpec = RosterSpec(); hSpec.tier = hT
        var aSpec = RosterSpec(); aSpec.tier = aT
        var qMarg = [0.0, 0.0, 0.0, 0.0]          // cumulative home-away margin at end of each quarter
        var drivesPerTeam = 0.0
        var gtPts = 0.0                            // points scored by a team already up >= gtLead
        var finalMargAbs = 0.0
        for _ in 0..<n {
            let (ht, hc, hp) = buildRoster(hSpec, side: "H")
            let (at, ac, ap) = buildRoster(aSpec, side: "A")
            let r = GameSimulator.simulate(homeTeam: ht, awayTeam: at, homeCoaches: hc, awayCoaches: ac,
                                           homeGamePlan: hp, awayGamePlan: ap)
            // Walk the ordered drives, maintaining running score. Each drive's
            // points are attributed to its offense (covers TD/FG/XP/2pt; safeties
            // and return TDs are the rare exception and ignored for this proxy).
            var hs = 0, as_ = 0
            var qEnd = [0, 0, 0, 0]
            var driveCount = 0
            for d in r.boxScore.drives {
                let isHome = d.teamID == ht.id
                let leadBefore = isHome ? hs - as_ : as_ - hs
                let pts = d.plays.reduce(0) { $0 + $1.pointsScored }
                if pts > 0, leadBefore >= gtLead { gtPts += Double(pts) }
                if isHome { hs += pts } else { as_ += pts }
                // record cumulative margin snapshot at the quarter this drive ended
                let q = min((d.plays.last?.quarter ?? 1) - 1, 3)
                for qi in q..<4 { qEnd[qi] = hs - as_ }
                if d.plays.contains(where: { $0.playType == .run || $0.playType == .pass }) { driveCount += 1 }
            }
            for qi in 0..<4 { qMarg[qi] += Double(qEnd[qi]) }
            drivesPerTeam += Double(driveCount) / 2.0
            finalMargAbs += Double(abs(hs - as_))
        }
        let inv = 1.0 / Double(n)
        let fm = finalMargAbs * inv
        let gt = gtPts * inv
        let label = "\(hT) vs \(aT)".padding(toLength: 13, withPad: " ", startingAt: 0)
        print(String(format: "  %@ | %5.1f | %+6.1f %+6.1f %+6.1f %+6.1f | %+9.1f | %6.1f  (%.0f%%)",
            label, drivesPerTeam * inv,
            qMarg[0] * inv, qMarg[1] * inv, qMarg[2] * inv, qMarg[3] * inv,
            fm, gt, fm > 0 ? gt / fm * 100 : 0))
    }
}

// Parameterized round-5 scenarios consume `--flag value` args instead of a
// scenario-name list. They dispatch BEFORE the name-list path so every existing
// scenario keeps working exactly as before.
if let first = args.first, first == "fullgame" || first == "positionsweep" || first == "blowoutprobe" {
    let flags = parseFlags(Array(args.dropFirst()))
    printHeader()
    print("")
    if first == "fullgame" { scenarioFullGame(flags) }
    else if first == "blowoutprobe" { scenarioBlowoutProbe(flags) }
    else { scenarioPositionSweep(flags) }
    print("\nDONE.")
    exit(0)
}

let requested: [String]
if args.isEmpty {
    FileHandle.standardError.write("usage: harness <scenario> [scenario ...]\n".data(using: .utf8)!)
    FileHandle.standardError.write("scenarios: \(allScenarios.joined(separator: ", ")), all\n".data(using: .utf8)!)
    FileHandle.standardError.write("parameterized: fullgame --home-tier X --away-tier Y --n N [flags] | positionsweep --group G --n N\n".data(using: .utf8)!)
    exit(2)
} else if args.contains("all") {
    requested = allScenarios
} else {
    requested = args
}

printHeader()
for (i, name) in requested.enumerated() {
    print("")
    run(name)
    if i < requested.count - 1 { print("") }
}
print("\nDONE.")
