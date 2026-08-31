import Foundation

// ============================================================================
// CoachedGameScenario — per-game scoring in a COACHED sim-to-final
// ============================================================================
//
// WHAT WAS MISSING: every scoring measurement this rig has ever taken came out
// of `GameSimulator.simulate`, the QUICK sim. The game the user actually plays
// runs `LiveGameEngine`, and its "sim to final" button is `simToEnd()` — a loop
// over `step()` behind a 500-play safety cap with no score check at all. On top
// of that the coached path carries two things the quick sim does not: the
// opponent-prep boosts `audibleBoost` (clamped 0…0.20 at construction) and
// `defReadBoost` (clamped 0…0.15), folded into per-play momentum at half
// strength. So a 60-21 coached blowout had nothing to be compared against —
// not a distribution, not a ceiling, not even the quick sim.
//
// WHAT THIS MEASURES (nothing here re-implements anything):
//
//   1. The per-team scoring DISTRIBUTION of a coached sim-to-final, pooled over
//      matchups, with the tail (p90 / p99 / max) reported rather than the mean,
//      because a guard rail is a tail question.
//   2. The same distribution from `GameSimulator.simulate` on the same rosters,
//      as the reference. `LiveGameEngine`'s own header claims a fully-AI live
//      game is statistically identical to the quick sim; that claim is now a
//      gate instead of a comment.
//   3. A prep-boost SWEEP that walks the requested boosts past their clamp.
//      The scenario never re-types 0.20 / 0.15 — it asks for more than that and
//      measures whether the scoring stops moving, which is what a binding clamp
//      looks like from outside. (sync_sources.sh §10c separately fails the build
//      if either clamp line leaves the repo.)
//
// EVERY ENGINE NUMBER IS A REPO BYTE. `LiveGameEngineExtract.swift` is the
// shipped file minus its post-whistle SwiftData write-back; the clamps, the
// half-strength momentum fold, the per-play injury roll and the 500-play cap are
// all guarded byte-for-byte by sync_sources.sh.

/// One finished game, reduced to the figures a guard rail would be written
/// against. Every field is read straight off the engine that produced it.
struct CoachedGameLine {
    /// Points scored by the side the user coaches (`playerTeamIsHome == true`).
    var playerPts = 0
    /// Points scored by the AI opponent.
    var oppPts = 0
    /// `LiveGameEngine.playLog.count` — how close the game came to the
    /// 500-play safety cap in `simToEnd()`. Zero for a quick-sim reference row,
    /// which has no play log of its own.
    var loggedPlays = 0
    /// Final quarter reached; > 4 means the game went to overtime.
    var finalQuarter = 0
    /// Drives in the finished box score, both sides — the possession count that
    /// separates "more chances" from "more points per chance". Read off
    /// `BoxScore.drives`, which both paths assemble the same way
    /// (`GameSimulator.finalizeGameResult`).
    var drives = 0
    /// Run + pass snaps across those drives (penalties excluded, as in
    /// `teamLine`), so a possession-count difference can be told apart from a
    /// longer-drive difference.
    var scrimmagePlays = 0

    var combined: Int { playerPts + oppPts }
    var absMargin: Int { abs(playerPts - oppPts) }
    /// Whichever side won — the figure a "no team may score more than X" rail
    /// would actually be written against.
    var winnerPts: Int { Swift.max(playerPts, oppPts) }
}

/// Pooled statistics over a cell of games. Mean/sd/percentiles all come from
/// `meanD` / `sdD` / `lrPct`, the same aggregates every other scenario uses.
struct CoachedGameCell {
    var lines: [CoachedGameLine] = []

    /// Both sides pooled — 2 team-games per game, the same convention
    /// `printBandTable` uses for the quick sim.
    var teamPts: [Double] { lines.flatMap { [Double($0.playerPts), Double($0.oppPts)] } }
    var winnerPts: [Double] { lines.map { Double($0.winnerPts) } }
    var combined: [Double] { lines.map { Double($0.combined) } }
    var margins: [Double] { lines.map { Double($0.absMargin) } }
    var maxLoggedPlays: Int { lines.map(\.loggedPlays).max() ?? 0 }
    var overtimeGames: Int { lines.filter { $0.finalQuarter > 4 }.count }
    var drives: [Double] { lines.map { Double($0.drives) } }
    var scrimmagePlays: [Double] { lines.map { Double($0.scrimmagePlays) } }
    /// Points per drive, pooled (total points ÷ total drives) rather than
    /// averaged per game, so a short game does not weigh as much as a long one.
    var pointsPerDrive: Double {
        let pts = lines.reduce(0) { $0 + $1.combined }
        let drv = lines.reduce(0) { $0 + $1.drives }
        return drv > 0 ? Double(pts) / Double(drv) : 0
    }

    /// Share of GAMES in which either side reached `pts` points.
    func shareReaching(_ pts: Int) -> Double {
        lrShare(lines.filter { $0.winnerPts >= pts }.count, lines.count)
    }
    /// Share of GAMES decided by `pts` or more.
    func shareMarginAtLeast(_ pts: Int) -> Double {
        lrShare(lines.filter { $0.absMargin >= pts }.count, lines.count)
    }
}

/// One row of the prep-boost sweep. The two boosts are what the scenario ASKS
/// `LiveGameEngine` for; the engine clamps them in its own init, which is the
/// whole point of walking the request past the ceiling.
struct CoachedPrepStep {
    let label: String
    let requestedAudible: Double
    let requestedDefRead: Double
}

/// Builds one coached game, runs the shipped sim-to-final, and reads the result
/// off the engine. The user coaches the HOME side, so the prep boosts land
/// there — exactly as they do when the dashboard hands the boosts to
/// `CoachedGameView`.
@MainActor
func cgPlayCoachedGame(
    homeSpec: RosterSpec,
    awaySpec: RosterSpec,
    audible: Double,
    defRead: Double
) -> CoachedGameLine {
    let (ht, hc, _) = buildRoster(homeSpec, side: "H")
    let (at, ac, _) = buildRoster(awaySpec, side: "A")
    // No game plan hand-off: the dashboard sets this static right before it
    // presents the coached game, and a stale one would bias the next cell.
    LiveGameEngine.pendingPlayerGamePlan = nil
    let engine = LiveGameEngine(
        homeTeam: ht,
        awayTeam: at,
        homeCoaches: hc,
        awayCoaches: ac,
        playerTeamIsHome: true,
        audibleBoost: audible,
        defReadBoost: defRead
    )
    engine.simToEnd()
    var line = CoachedGameLine()
    line.playerPts = engine.homeScore
    line.oppPts = engine.awayScore
    line.loggedPlays = engine.playLog.count
    line.finalQuarter = engine.quarter
    // `buildResult()` is the same `GameSimulator.finalizeGameResult` the quick
    // sim ends on, so the two paths' box scores are counted by one function.
    cgFillDrives(&line, drives: engine.buildResult().boxScore.drives)
    return line
}

/// Counts possessions and scrimmage snaps off a finished box score. Shared by
/// both paths so the comparison can never be an artefact of counting them two
/// different ways.
func cgFillDrives(_ line: inout CoachedGameLine, drives: [DriveResult]) {
    line.drives = drives.count
    line.scrimmagePlays = drives.reduce(0) { total, drive in
        total + drive.plays.filter { $0.playType == .pass || $0.playType == .run }.count
    }
}

/// The quick-sim reference on the same rosters. `GameSimulator.simulate` has no
/// play log and no prep boosts, so those two fields stay at their zero defaults
/// and the report never prints a play count for a reference row.
func cgPlayQuickGame(homeSpec: RosterSpec, awaySpec: RosterSpec) -> CoachedGameLine {
    let (ht, hc, hp) = buildRoster(homeSpec, side: "H")
    let (at, ac, ap) = buildRoster(awaySpec, side: "A")
    let r = GameSimulator.simulate(homeTeam: ht, awayTeam: at,
                                   homeCoaches: hc, awayCoaches: ac,
                                   homeGamePlan: hp, awayGamePlan: ap)
    var line = CoachedGameLine()
    line.playerPts = r.homeScore
    line.oppPts = r.awayScore
    cgFillDrives(&line, drives: r.boxScore.drives)
    return line
}

func cgSpec(_ tier: String) -> RosterSpec {
    var s = RosterSpec()
    s.tier = tier
    return s
}

/// `%.1f` with a fixed width, so the sweep table lines up without `%-N@`
/// (which does not pad on Darwin).
func cgCell(_ cell: CoachedGameCell) -> String {
    String(format: "%5.1f %4.1f %5.0f %5.0f %5.0f",
           meanD(cell.teamPts), sdD(cell.teamPts),
           lrPct(cell.teamPts, 90), lrPct(cell.teamPts, 99), cell.teamPts.max() ?? 0)
}

@MainActor
func scenarioCoachedGame(_ f: [String: String]) {
    let n = Int(f["n"] ?? "") ?? 200
    let A = LRAsserts()
    seedRNG(f)

    let matchups: [(String, String)] = [
        ("avg", "avg"), ("good", "avg"), ("good", "weak"), ("elite", "weak")
    ]
    // The sweep deliberately walks PAST the shipped ceiling. `over` asks for
    // double the clamp on both boosts; if the clamp binds, `max` and `over`
    // measure the same game.
    let prepSteps = [
        CoachedPrepStep(label: "none", requestedAudible: 0.00, requestedDefRead: 0.000),
        CoachedPrepStep(label: "half", requestedAudible: 0.10, requestedDefRead: 0.075),
        CoachedPrepStep(label: "max",  requestedAudible: 0.20, requestedDefRead: 0.150),
        CoachedPrepStep(label: "over", requestedAudible: 0.40, requestedDefRead: 0.300)
    ]

    print("===== SCENARIO coachedgame: per-game scoring in a COACHED sim-to-final =====")
    print("  engine:  LiveGameEngine.simToEnd() (awk strip of persist(); every constant a repo byte)")
    print("  ref:     GameSimulator.simulate() on the same rosters — the quick sim this rig already measures")
    print("  n=\(n) games per cell · \(matchups.count) matchups × \(prepSteps.count) prep steps + \(matchups.count) reference cells")
    print("  seedable=\(f["seedable"] != nil ? "rosters-fixed" : "no")  (engine play-by-play RNG is always stochastic)")
    print("")

    let t0 = Date()

    // ------------------------------------------------------------------------
    // A. Quick-sim reference, per matchup
    // ------------------------------------------------------------------------
    var quickByMatchup: [String: CoachedGameCell] = [:]
    var quickAll = CoachedGameCell()
    for (h, a) in matchups {
        var cell = CoachedGameCell()
        for _ in 0..<n { cell.lines.append(cgPlayQuickGame(homeSpec: cgSpec(h), awaySpec: cgSpec(a))) }
        quickByMatchup["\(h)/\(a)"] = cell
        quickAll.lines.append(contentsOf: cell.lines)
    }

    // ------------------------------------------------------------------------
    // B. Coached sim-to-final, per matchup × prep step
    // ------------------------------------------------------------------------
    var coached: [String: CoachedGameCell] = [:]
    var coachedByPrep: [String: CoachedGameCell] = [:]
    var coachedAll = CoachedGameCell()
    for (h, a) in matchups {
        for step in prepSteps {
            var cell = CoachedGameCell()
            for _ in 0..<n {
                cell.lines.append(cgPlayCoachedGame(
                    homeSpec: cgSpec(h), awaySpec: cgSpec(a),
                    audible: step.requestedAudible, defRead: step.requestedDefRead))
            }
            coached["\(h)/\(a)|\(step.label)"] = cell
            coachedByPrep[step.label, default: CoachedGameCell()].lines.append(contentsOf: cell.lines)
            coachedAll.lines.append(contentsOf: cell.lines)
        }
    }

    // ------------------------------------------------------------------------
    // C. Report — per-team points, pooled over both sides of each game
    // ------------------------------------------------------------------------
    print("  --- per-TEAM points per game (both sides pooled, \(n)×2 team-games per cell) ---")
    print("  \(lrPad("matchup", 12)) \(lrPad("prep", 6))  mean   sd   p90   p99   max")
    for (h, a) in matchups {
        let key = "\(h)/\(a)"
        if let q = quickByMatchup[key] {
            print("  \(lrPad(key, 12)) \(lrPad("QUICK", 6))  " + cgCell(q))
        }
        for step in prepSteps {
            guard let cell = coached["\(key)|\(step.label)"] else { continue }
            let tag = String(format: "%@(%.2f/%.3f)", step.label, step.requestedAudible, step.requestedDefRead)
            print("  \(lrPad("", 12)) \(lrPad(step.label, 6))  " + cgCell(cell) + "   requested \(tag)")
        }
    }

    // ------------------------------------------------------------------------
    // D. The tail — what a guard rail would actually be written against
    // ------------------------------------------------------------------------
    print("")
    print("  --- the TAIL, pooled over every matchup (\(coachedAll.lines.count) coached games) ---")
    print(String(format: "    winning team's points   mean %.1f  p90 %.0f  p99 %.0f  max %.0f",
                 meanD(coachedAll.winnerPts), lrPct(coachedAll.winnerPts, 90),
                 lrPct(coachedAll.winnerPts, 99), coachedAll.winnerPts.max() ?? 0))
    print(String(format: "    combined points         mean %.1f  p90 %.0f  p99 %.0f  max %.0f",
                 meanD(coachedAll.combined), lrPct(coachedAll.combined, 90),
                 lrPct(coachedAll.combined, 99), coachedAll.combined.max() ?? 0))
    print(String(format: "    margin of victory       mean %.1f  p90 %.0f  p99 %.0f  max %.0f",
                 meanD(coachedAll.margins), lrPct(coachedAll.margins, 90),
                 lrPct(coachedAll.margins, 99), coachedAll.margins.max() ?? 0))
    print(String(format: "    quick-sim reference     winner mean %.1f  p99 %.0f  max %.0f   |   margin mean %.1f  p99 %.0f  max %.0f",
                 meanD(quickAll.winnerPts), lrPct(quickAll.winnerPts, 99), quickAll.winnerPts.max() ?? 0,
                 meanD(quickAll.margins), lrPct(quickAll.margins, 99), quickAll.margins.max() ?? 0))
    print("")
    print("  --- how often a coached game reaches a headline scoreline ---")
    print("  \(lrPad("threshold", 22)) coached %   quick %")
    for pts in [40, 45, 50, 56, 60] {
        print(String(format: "  %@ %8.2f %9.2f", lrPad("winner scores \(pts)+", 22),
                     coachedAll.shareReaching(pts), quickAll.shareReaching(pts)))
    }
    for marg in [28, 35, 39] {
        print(String(format: "  %@ %8.2f %9.2f", lrPad("margin \(marg)+", 22),
                     coachedAll.shareMarginAtLeast(marg), quickAll.shareMarginAtLeast(marg)))
    }

    // ------------------------------------------------------------------------
    // D2. WHERE the coached path differs from the quick sim
    // ------------------------------------------------------------------------
    // `LiveGameEngine`'s header promises a nil-argument live game is
    // statistically identical to `GameSimulator.simulate`, and `simToEnd()` is
    // exactly such a game. This block exists so a gap in that promise can be
    // ATTRIBUTED — more possessions, longer possessions, or more points out of
    // each one — rather than merely noticed.
    let coachedNoPrepCell = coachedByPrep["none"] ?? CoachedGameCell()
    print("")
    print("  --- PARITY CHECK: coached (no prep) vs quick sim, on identical roster specs ---")
    print("  LiveGameEngine's header claims a nil-argument live game is statistically identical to")
    print("  GameSimulator.simulate. simToEnd() IS such a game, so any delta below is a real divergence.")
    print("  \(lrPad("", 24)) coached    quick    delta")
    func cgCompare(_ label: String, _ a: Double, _ b: Double) {
        print(String(format: "  %@ %7.2f  %7.2f  %+7.2f", lrPad(label, 24), a, b, a - b))
    }
    cgCompare("points / team-game", meanD(coachedNoPrepCell.teamPts), meanD(quickAll.teamPts))
    cgCompare("drives / game", meanD(coachedNoPrepCell.drives), meanD(quickAll.drives))
    cgCompare("scrimmage plays / game", meanD(coachedNoPrepCell.scrimmagePlays), meanD(quickAll.scrimmagePlays))
    cgCompare("plays / drive", meanD(coachedNoPrepCell.scrimmagePlays) / Swift.max(1, meanD(coachedNoPrepCell.drives)),
              meanD(quickAll.scrimmagePlays) / Swift.max(1, meanD(quickAll.drives)))
    cgCompare("points / drive", coachedNoPrepCell.pointsPerDrive, quickAll.pointsPerDrive)
    // Attribute the points delta between the two channels that can produce it,
    // rather than asserting which one did. `pointsPerDrive × drives` is the
    // whole of a team-game's points, so holding one factor at the quick sim's
    // value and moving the other splits the gap exactly.
    let driveDelta = (meanD(coachedNoPrepCell.drives) - meanD(quickAll.drives)) * quickAll.pointsPerDrive / 2
    let rateDelta = (coachedNoPrepCell.pointsPerDrive - quickAll.pointsPerDrive) * meanD(coachedNoPrepCell.drives) / 2
    print(String(format: "  attribution of the %+.2f pts/team-game: %+.2f from possession count, %+.2f from conversion rate",
                 driveDelta + rateDelta, driveDelta, rateDelta))

    // ------------------------------------------------------------------------
    // E. Does the prep clamp bind? — the sweep, pooled over matchups
    // ------------------------------------------------------------------------
    print("")
    print("  --- prep-boost sweep, pooled over every matchup (the PLAYER's side only) ---")
    print("  the request walks past the shipped clamp; a binding clamp shows up as `max` and `over` agreeing")
    print("  \(lrPad("prep", 6)) \(lrPad("requested", 16))  player pts   opp pts   margin(player-opp)")
    for step in prepSteps {
        guard let cell = coachedByPrep[step.label] else { continue }
        let playerPts = cell.lines.map { Double($0.playerPts) }
        let oppPts = cell.lines.map { Double($0.oppPts) }
        let signed = cell.lines.map { Double($0.playerPts - $0.oppPts) }
        print(String(format: "  %@ %@  %6.2f      %6.2f      %+6.2f",
                     lrPad(step.label, 6),
                     lrPad(String(format: "%.2f / %.3f", step.requestedAudible, step.requestedDefRead), 16),
                     meanD(playerPts), meanD(oppPts), meanD(signed)))
    }

    // ------------------------------------------------------------------------
    // F. The safety cap in simToEnd()
    // ------------------------------------------------------------------------
    let maxPlays = coachedAll.maxLoggedPlays
    let overtimes = coachedAll.overtimeGames
    print("")
    print(String(format: "  --- simToEnd() safety cap: longest play log %d of the 500-play limit · %d overtime games (%.2f %%)",
                 maxPlays, overtimes, lrShare(overtimes, coachedAll.lines.count)))

    // ------------------------------------------------------------------------
    // Hard gates
    // ------------------------------------------------------------------------
    // Every threshold below was set FROM the numbers this scenario produced on
    // its first full run (`--n 400`, 6 400 coached games against 1 600 quick-sim
    // reference games), never ahead of it. They are deliberately LOOSE, the same
    // way the `lockerroom` gates are: this scenario's job is to REPORT the
    // coached distribution, and the printed tables above carry the tighter
    // expectations. A gate here fires only when the coached path moves past
    // where it was measured — including the one place it was already wrong.
    let coachedNoPrep = coachedNoPrepCell
    let coachedMax = coachedByPrep["max"] ?? CoachedGameCell()
    let coachedOver = coachedByPrep["over"] ?? CoachedGameCell()

    // CG-1: THE DEFECT THIS SCENARIO FOUND. `LiveGameEngine`'s own header
    // promises a nil-argument live game is statistically identical to
    // `GameSimulator.simulate`, and `simToEnd()` is exactly such a game. It is
    // not: the first run measured +6.85 points per team-game, all of it in
    // points-per-drive (the coached path takes FEWER possessions). The gate
    // records that divergence at 9.0 so it cannot grow unnoticed while the
    // product call on it is outstanding — it is not an endorsement of 6.85.
    let parityGap = abs(meanD(coachedNoPrep.teamPts) - meanD(quickAll.teamPts))
    A.check("CG-1", parityGap <= 9.0,
        String(format: "coached-at-zero-prep per-team points %.2f vs quick sim %.2f — gap %.2f (<= 9.0)",
               meanD(coachedNoPrep.teamPts), meanD(quickAll.teamPts), parityGap)
        + " — parity is what the engine's header claims; the first run measured a +6.85 divergence and this rail only stops it growing")

    // CG-2: the prep clamp binds. Asking for double the ceiling bought 0.12 of
    // a point over asking for the ceiling — noise. This is the rail that keeps
    // the clamp honest without this file ever naming 0.20 / 0.15.
    let clampGap = abs(meanD(coachedMax.teamPts) - meanD(coachedOver.teamPts))
    A.check("CG-2", clampGap <= 1.5,
        String(format: "prep saturates: max-request %.2f vs double-the-clamp request %.2f — gap %.2f (<= 1.5; measured 0.12)",
               meanD(coachedMax.teamPts), meanD(coachedOver.teamPts), clampGap))

    // CG-3: prep is a nudge, not a cheat code. At the ceiling it moved the
    // player's own scoring by -0.06 points per game, i.e. not at all.
    let prepLift = meanD(coachedMax.lines.map { Double($0.playerPts) })
        - meanD(coachedNoPrep.lines.map { Double($0.playerPts) })
    A.check("CG-3", prepLift <= 3.0,
        String(format: "max prep buys the player %+.2f points per game (<= 3.0 — measured -0.06, so the boosts are not what makes a coached game high-scoring)", prepLift))

    // CG-4: THE SCORING RAIL this item was opened for. 60-21 was the scoreline
    // that prompted it, so the rail is on the WINNER's score — the half a cap
    // would clamp. Measured p99 60, max 80; the gate sits at 66.
    let winnerP99 = lrPct(coachedAll.winnerPts, 99)
    A.check("CG-4", winnerP99 <= 66,
        String(format: "p99 of the winning team's score %.0f (<= 66; measured 60)", winnerP99))

    // CG-5: and the 60-point game itself has to stay a tail event rather than a
    // regular occurrence. Measured 1.03 % of coached games.
    let sixtyShare = coachedAll.shareReaching(60)
    A.check("CG-5", sixtyShare <= 2.5,
        String(format: "%.2f %% of coached games see a team reach 60 points (<= 2.50 %%; measured 1.03 %%)", sixtyShare))

    // CG-6: the other half of a 60-21 — the margin. Measured p99 53, max 70.
    let marginP99 = lrPct(coachedAll.margins, 99)
    A.check("CG-6", marginP99 <= 62,
        String(format: "p99 margin of victory %.0f (<= 62; measured 53)", marginP99))

    // CG-7: simToEnd()'s 500-play cap is a safety valve, not a game length. If
    // a real game ever reaches it the final score is a truncation artefact.
    // The longest log measured was 195 plays.
    A.check("CG-7", maxPlays < 500,
        "longest coached play log \(maxPlays) plays (< 500 — the simToEnd safety cap never truncated a game; measured 195)")

    A.report()
    print(String(format: "\n  elapsed %.1fs", Date().timeIntervalSince(t0)))
    if A.failures > 0 { exit(1) }
}
