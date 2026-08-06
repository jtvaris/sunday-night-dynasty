import Foundation
import SwiftData

/// Handles all contract operations for both simple and realistic salary-cap modes.
enum ContractEngine {

    // MARK: - The Cap

    /// **The league's opening salary cap, in thousands. One number, one place.**
    ///
    /// Task #87 found four of them shipping at once — `265_000` in a dozen engine
    /// defaults, `260_000` in two UI fallbacks and a cap-% pill, a `$285M → $310M`
    /// string literal on a live dashboard tile, and `$284.9M` in this file's own
    /// prose (which was season-TWO money, `265 × 1.075`, and therefore made every
    /// headline number in the #82 rationale one league-year ahead of what a save
    /// actually starts with). A cap is a money supply: four of them is four
    /// economies, and the screens quoted different prices for the same player.
    ///
    /// This is the definition. `Team.salaryCap` defaults to it, every engine
    /// entry point below takes the club's ACTUAL cap as a REQUIRED argument (so
    /// a missing one is a compile error rather than a silent season-one price on
    /// a season-ten save), and the only remaining defaults are on internal
    /// helpers that cannot reach a `Team`.
    static let openingSalaryCap = 265_000

    /// How much the cap grows in a league year. **The engine's own roll** —
    /// `FreeAgencyEngine`'s league-year rollover draws from exactly this range.
    ///
    /// Task #87 / F15: two screens used to project two different futures off two
    /// hand-typed constants (`RosterEvaluationView` × 1.05, `CapOverviewView`
    /// × 1.07), neither of which was the number the league actually rolls.
    static let capGrowthRange: ClosedRange<Double> = 0.05...0.08

    /// The midpoint of ``capGrowthRange``, for anything that has to project a
    /// single future rather than draw one: cap-outlook tiles, three-year
    /// projections, and the roster seeder's back-dating of an old contract to
    /// the smaller cap it was negotiated against.
    static let capGrowthPerSeason = (capGrowthRange.lowerBound + capGrowthRange.upperBound) / 2

    /// **The league minimum salary, in thousands.** `0.28 %` of the cap, never
    /// below `$750K`.
    ///
    /// The floor every price in the game bottoms out at: the free-agent market
    /// (`estimateMarketValue`), the negotiation engine, the rookie wage scale
    /// and the practice-squad poach all stop here. It shipped as the same
    /// hand-typed `max(Int(0.0028 * Double(cap)), 750)` in half a dozen files,
    /// which is how `PracticeSquadEngine.poachSalary` came to be a flat `795`
    /// while its own doc comment claimed to be quoting this formula (795 is
    /// `0.0030 × 265M`, the UDFA rate — the minimum at the opening cap is 750).
    ///
    /// One definition, cap-relative, so the floor grows with the money supply.
    ///
    /// `DraftEngine` keeps its own copy on purpose: those constants are synced
    /// VERBATIM into the balance harness (`tools/balance-harness/sync_sources.sh`
    /// dies if they move), so the draft's rookie floor must stay inline there.
    ///
    /// THIS definition is itself a harness anchor. `estimateMarketValue` — which
    /// `sync_sources.sh` slices verbatim into `ContractEngineExtract.swift` —
    /// ends by calling it, so the function has to travel with the formula or the
    /// generated extract fails to compile on the call. Renaming or moving it
    /// therefore means editing the anchor list in that script (it dies with a
    /// named message rather than emitting a broken extract).
    static func veteranMinimum(cap: Int) -> Int {
        max(Int(0.0028 * Double(cap)), 750)
    }

    // MARK: - Simple Mode

    /// Sign a player in simple cap mode by setting contract length, salary,
    /// assigning the team, and debiting cap space.
    static func signPlayerSimple(player: Player, years: Int, annualSalary: Int, team: Team) {
        player.contractYearsRemaining = years
        player.annualSalary = annualSalary
        player.teamID = team.id
        team.currentCapUsage += annualSalary
    }

    /// Cut a player in simple mode. Frees cap space and removes team assignment.
    ///
    /// The arithmetic lives in `CapManagementEngine.applyRelease` — the single
    /// release authority (task #68). This used to hand back the FULL salary and
    /// book no dead money at all, which is why in-season releases were free and
    /// the Dead Money card could never see a cut.
    static func cutPlayerSimple(player: Player, team: Team) {
        CapManagementEngine.applyRelease(player: player, team: team, capMode: .simple)
    }

    // MARK: - Sandbox Mode

    /// Sign a player in sandbox cap mode: roster is updated but no cap is debited.
    /// Annual salary is still recorded for UI/display, but the team's cap usage is left alone.
    static func signPlayerSandbox(player: Player, years: Int, annualSalary: Int, team: Team) {
        player.contractYearsRemaining = years
        player.annualSalary = annualSalary
        player.teamID = team.id
        // Intentionally no `team.currentCapUsage` mutation — sandbox ignores cap.
    }

    /// Cut a player in sandbox cap mode without touching cap usage.
    static func cutPlayerSandbox(player: Player) {
        player.teamID = nil
        player.contractYearsRemaining = 0
        player.annualSalary = 0
    }

    // MARK: - Cap-Mode-Aware Wrappers

    /// Sign a player using whichever pathway matches the active cap mode.
    /// Sandbox mode skips all cap accounting and contract bookkeeping.
    static func signPlayer(
        player: Player,
        years: Int,
        annualSalary: Int,
        team: Team,
        capMode: CapMode
    ) {
        switch capMode {
        case .simple, .realistic:
            // Both call paths debit cap usage by `annualSalary`. The realistic-mode
            // entry point that creates a full Contract object lives in
            // `FreeAgencyEngine.signFreeAgent`; this wrapper is for the simple
            // `Player.annualSalary`-only flow.
            signPlayerSimple(player: player, years: years, annualSalary: annualSalary, team: team)
        case .sandbox:
            signPlayerSandbox(player: player, years: years, annualSalary: annualSalary, team: team)
        }
    }

    /// Cut a player using the path that matches the active cap mode.
    /// Sandbox skips dead cap entirely; simple mode frees cap space.
    static func cutPlayer(player: Player, team: Team, capMode: CapMode) {
        CapManagementEngine.applyRelease(player: player, team: team, capMode: capMode)
    }

    /// Estimate the annual market value (in thousands) a player would command
    /// on the open market based on position, age, and overall rating.
    ///
    /// Values are expressed as a percentage of the salary cap, so they scale
    /// naturally as the cap grows each season. Callers pass the club's ACTUAL
    /// `salaryCap`; there is no default (see ``openingSalaryCap``).
    ///
    /// A player genuinely converted across position families still demands the
    /// money of the family he was built for — see ``bestPayingPosition`` for what
    /// "genuinely" now means and why it used to mean nothing.
    /// Base market value as a percentage of the salary cap, before the position
    /// multiplier and the age curve.
    ///
    /// **Re-derived in the P1 quality-pyramid wave (2026-07-30).** The old ladder
    /// was `95 / 90 / 80 / 70 / 60` with slopes `0.55 / 0.7 / 0.5 / 0.2 / 0.06`,
    /// anchored on a league whose mean OVR was 76.5. That league now averages
    /// **71.0** (`LeagueGenerator.targetQualityPyramid`), and OVR bands do not
    /// survive a level change: shipping the old ladder unchanged would have paid
    /// the *same* league **1.83 %** of cap per player instead of 2.92 % — a 37 %
    /// collapse in league-wide market value, which is the difference between a
    /// cap that binds and a cap that no team ever approaches.
    ///
    /// The re-derivation is **percentile-preserving**, so the money a player
    /// commands for a given standing in the league is unchanged. Each old
    /// boundary was mapped to the new OVR holding the same share of the league at
    /// or above it (measured over a 600-league Monte-Carlo of both generators):
    ///
    /// | old OVR | share ≥ | new OVR | share ≥ |
    /// |---|---|---|---|
    /// | 95 | 0.00 % | 94 | 0.20 % |
    /// | 90 | 3.26 % | 87 | 4.19 % |
    /// | 80 | 37.08 % | 74 | 39.22 % |
    /// | 70 | 79.68 % | 64 | 80.10 % |
    /// | 60 | 97.39 % | 54 | 97.66 % |
    ///
    /// The money at each anchor was then solved so the league-wide mean base
    /// percentage comes out at **2.919 %** — identical to what the old ladder paid
    /// the old league, to three decimals. The cap economy (bids, holdouts, cap
    /// health, owner budget) therefore sees the same pressure it was validated
    /// against.
    ///
    /// **It also fixes a monotonicity defect.** The old ladder was NOT increasing:
    /// an 89-OVR player commanded `3.0 + 9·0.5` = **7.50 %** of the cap and a
    /// 90-OVR player `6.0 + 0` = **6.00 %**, so getting better at exactly the
    /// wrong moment cut a player's market value by a fifth — and with it his
    /// contract demands, his trade value and his holdout threshold. Expressing the
    /// ladder as interpolated anchor points instead of independent tier formulas
    /// makes that class of bug unrepresentable.
    ///
    /// ## The top-tail recalibration (market-realism wave)
    ///
    /// The P1 ladder above was **percentile-preserving**, which is exactly what
    /// that wave needed and exactly why the top of the market stayed wrong: it
    /// carried forward a curve whose elite end was set before the modern QB
    /// market existed. Measured in the shipped game, the league's five best
    /// quarterbacks were paid **$33.4M–$45.6M** — 12.6-17.2 % of a $265M cap —
    /// against a real league where the top of the position sits at 18-22 % and
    /// the very top has passed $60M. A management game whose franchise
    /// quarterback is a rounding error against the cap has no cap decision in it.
    ///
    /// The fix moves ONLY the tail, and pays for it out of the upper middle:
    ///
    /// | OVR | old | new | Δ | what he is |
    /// |---|---|---|---|---|
    /// | ≤74 | — | — | **0.0 %** | the mass: depth, rotation, the starter line |
    /// | 80 | 5.046 | 4.750 | −5.9 % | good starter — the offset comes from here |
    /// | 84 | 6.277 | 6.236 | −0.7 % | crossover: the trim has run out |
    /// | 88 | 7.600 | 8.070 | +6.2 % | fringe All-Pro |
    /// | 92 | 9.200 | 10.950 | +19.0 % | the best player at his position |
    /// | 96 | 10.800 | 13.900 | +28.7 % | generational |
    ///
    /// **Aggregate spend is held flat on purpose** — it is the input the #53 /
    /// #27 economy calibration was solved against, and a market whose *level*
    /// moves invalidates the cap-room, FA-clearing and holdout thresholds
    /// together. Integrating the ladder over the league's own rating
    /// distribution: **−0.02 %** against `LeagueGenerator.targetQualityPyramid`
    /// (mean 71.0, sd 8.88, the league a save starts with) and **+0.56 %**
    /// against the career harness's 30-season equilibrium league (mean 70.7,
    /// measured histogram). Both are inside the run-to-run noise of the harness
    /// gates they protect.
    ///
    /// **Convexity fix (adversarial review).** The top anchor shipped at 13.60,
    /// which made the 92→96 segment slope 0.6625 against 0.7200 for 87→92 — the
    /// one place the ladder bent the wrong way, and it bent it at exactly the
    /// band this wave existed to fix. A rating point cost 8 % LESS at the very
    /// top than just below it, so "the last five points cost more than the
    /// previous five" was a claim the numbers did not support. 13.90 restores it
    /// (slope 0.7375 > 0.7200) and costs **+0.04 %** of league-wide market value
    /// — a quarter of one basis point of the aggregate the wave is holding flat,
    /// because 96+ is under half a percent of the league.
    ///
    /// **Why the offset is taken at 76-82 and nowhere else.** The 90+ band is
    /// 1.5 % of the league, so raising it a quarter costs only ~5 % of league
    /// market value — but that is still real money and it has to come from
    /// somewhere. Below OVR 74 is untouchable: those are minimum-salary and
    /// near-minimum deals whose *absolute* level the FA market's clearing
    /// behaviour depends on. The 76-82 shoulder is where the money is (it is the
    /// fattest part of the paid population) and where a 3-6 % trim is invisible
    /// in a single contract while being large enough to fund the tail. It also
    /// steepens the curve in the direction the real market has moved: the gap
    /// between a good starter and a great one has widened every CBA.
    ///
    /// At QB (× 2.2 × `leagueAffordabilityScale`) the tail now reads
    /// 88 → 13.3 %, 90 → 15.7 %, 92 → 18.1 %, 94 → 20.5 %, 96 → 22.9 % of cap.
    /// A 99 extrapolates to 16.11 (26.6 % at QB) — a rating no generated league
    /// has ever produced, and the 18.0 ceiling below it is once again a pure
    /// runaway guard rather than a number the top of the table actually hits.
    static func marketBasePercent(overall: Int) -> Double {
        // (OVR, % of cap). Strictly increasing in both coordinates, and
        // CONVEX — each segment's slope is steeper than the one before it, so
        // "the last five rating points cost more than the previous five" is a
        // property of the table rather than a coincidence of its numbers.
        //
        // Slopes, in order: 0.0600 / 0.2200 / 0.2583 / 0.3714 / 0.7200 / 0.7375.
        // Any edit to an anchor MUST keep that sequence increasing — see the
        // convexity note above for what it cost when 96 sat at 13.60.
        let anchors: [(ovr: Double, pct: Double)] = [
            (54, 0.40),   // depth / special teams — bottom ~2 % of the league below this
            (64, 1.00),   // rotational contributor
            (74, 3.20),   // starter-quality (DEVELOPMENT_NFL_REFERENCE §8's 75+ line)
            (80, 4.75),   // good starter — the shoulder the tail raise is funded from
            (87, 7.35),   // top ~4 % — the second contract that resets a market
            (92, 10.95),  // best-at-his-position (× QB 2.2 → 18 % of cap)
            (96, 13.90),  // generational: ~1 player a decade (× QB 2.2 → 23 % of cap)
        ]
        let o = Double(overall)
        // Fringe / practice-squad floor.
        guard o > anchors[0].ovr else { return 0.28 }
        for (lo, hi) in zip(anchors, anchors.dropFirst()) where o <= hi.ovr {
            return lo.pct + (hi.pct - lo.pct) * (o - lo.ovr) / (hi.ovr - lo.ovr)
        }
        // Above the top anchor, continue its slope. The ceiling is a guard on an
        // unbounded extrapolation, NOT a price: it must sit above what a 99
        // reaches, or the table silently stops being convex at the very top.
        let top = anchors[anchors.count - 1]
        let prev = anchors[anchors.count - 2]
        let slope = (top.pct - prev.pct) / (top.ovr - prev.ovr)
        return Swift.min(18.0, top.pct + slope * (o - top.ovr))
    }

    /// League affordability scalar — what makes the price ladder above a price
    /// ladder for THIS league rather than an unbounded one (task #27).
    ///
    /// `marketBasePercent` was solved for a shape (monotone, correctly ordered)
    /// and for continuity with the ladder it replaced, but never against a
    /// budget: a salary cap is a money supply, and the sum of what a league's
    /// players are "worth" has to be payable out of it. It was not. Measured
    /// over `MultiSeasonSmokeTest`, pricing every rostered player at market came
    /// to **150.7 % of the league's total cap** — a 53-man roster whose market
    /// price is half again what a club is allowed to spend. Two things followed,
    /// and both were logged as separate bugs before the cause was one number:
    ///
    /// 1. The free-agent market could not clear. Clubs bought the two or three
    ///    men they could afford and the rest of the pool fell through to
    ///    `WeekAdvancer.refillAIRosters`, which signs anybody at the veteran
    ///    minimum — so the league's middle class was bought at $750k.
    /// 2. Everything that reads a salary AGAINST market read it wrong. The
    ///    average player sat at 0.53 of "market", which is inside
    ///    `TradeValueEngine.contractMultiplier`'s bargain premium and past
    ///    `HoldoutEngine`'s underpaid trigger — league-wide, permanently.
    ///
    /// The target is derived from the roster the league actually fields. Of ~1 700
    /// rostered men, the ~45 % past their rookie deal take ~64 % of payroll; if a
    /// healthy payroll is ~92 % of the cap and those veterans are paid about what
    /// they are worth, veteran market value totals ~59 % of the cap, and the
    /// cheaper rookie-contract population adds ~44 % — call it **~105-115 % of
    /// cap in total**, the shape §8 describes, where rookie deals are the
    /// discount that makes a roster affordable at all.
    ///
    /// 0.75 × 150.7 % ≈ 113 %. The scalar is applied to the finished valuation
    /// rather than folded into the anchors so that `marketBasePercent`'s
    /// derivation table stays readable as what it is — the SHAPE of the market —
    /// and the level it is denominated in stays one auditable number.
    static let leagueAffordabilityScale = 0.75

    /// Position multiplier calibrated to real NFL 2026 pay scales.
    ///
    /// **ONE table (task #87 / F20).** This vector used to be written out twice —
    /// once inside `estimateMarketValue` and once, verbatim, inside
    /// `bestPayingPosition`'s `rank` closure — so "which position pays more" and
    /// "how much does that position pay" were two copies that had to be kept in
    /// sync by hand. They are now the same function, and the ranking question is
    /// literally a comparison of this table's own values.
    ///
    /// **The vector is now REACHABLE (task #87 / F2).** Before that wave six of
    /// these fifteen entries were dead code: every generation path in the game
    /// assigns attributes by position *group*, `naturalPositionForAttributes`
    /// maps each group to its premium position, and `bestPayingPosition` then
    /// upgraded unconditionally — so DT was paid DE's 1.25, RT/IOL were paid
    /// LT's 1.05, MLB was paid OLB's 1.00, S was paid CB's 0.95 and FB was paid
    /// RB's rate. Four of the five "overpaid position" verdicts in the #87 audit
    /// were that bug rather than this table. `bestPayingPosition` now gates the
    /// upgrade on a genuine cross-group position CHANGE, so the numbers below
    /// are the numbers that run.
    ///
    /// **As ratios to the quarterback** — which is all a multiplier vector means
    /// — the reachable table reproduces the modern market: QB 1.00,
    /// WR 0.59 (real ~0.58), EDGE 0.57 (~0.67), OT 0.48 (~0.47), CB 0.43 (~0.50),
    /// DT 0.45 (~0.45 — task #126; was 0.41), RT 0.39 (~0.38), MLB 0.36 (~0.35), S 0.34 (~0.35),
    /// TE 0.32 (~0.32), IOL 0.30 (~0.30), RB 0.27 (~0.30), K/P 0.11 (~0.10).
    ///
    /// **RB 0.45 → 0.60 (task #87 / F12).** At 0.45 the best running back in the
    /// world topped out at 4.7 % of the cap; the real top of that market is ~7 %
    /// (Barkley's 2025 APY against a $279M cap). RB is the one position the #82
    /// wave left genuinely underpriced rather than accidentally overpriced, and
    /// unlike the six above it needed a constant rather than a bug fix. 0.60
    /// puts a generational back at 6.3 % and a 92 at 4.9 % — devalued relative
    /// to a receiver, as the modern market has him, but no longer a rounding
    /// error against the cap.
    ///
    /// A multiplier is NOT a top-end lever: it scales a position's whole
    /// population, so it sets that position's SHARE OF PAYROLL. QB is 3/53 of a
    /// roster × 2.2 ≈ 13 % of the cap, which is exactly right and is the reason
    /// 2.2 must not move. Elite dollar targets are reached through
    /// `marketBasePercent`'s tail instead, and at the real season-one cap
    /// ($265M — see ``openingSalaryCap``) they land: at OVR 94-96 this pays
    /// EDGE $31.2M / WR $32.4M and CB $23.7M / LT $26.2M.
    static func positionMultiplier(_ position: Position) -> Double {
        switch position {
        case .QB:
            return 2.2    // Elite QBs: ~20%+ of cap
        case .WR:
            return 1.3    // WR1: ~11-13%
        case .DE:
            return 1.25   // Edge rushers: ~11-13%
        case .LT:
            return 1.05   // LT: ~8.5-10%
        case .OLB:
            return 1.0    // OLB: ~8-9%
        case .CB:
            return 0.95   // Top CB: ~8-9.5%
        case .DT:
            // ## Task #126 — raised to 1.0, and why it fits now
            //
            // Task #88a measured this gap and left it alone because correcting
            // it broke the cap sheet. Re-measured on the current tree it no
            // longer does, and the honest thing is to record both readings.
            //
            // The gap itself is unchanged and is the largest on the ladder: at
            // 0.9 an OVR-92 interior lineman cost 7.4 % of the cap and the
            // position took 7.55-7.77 % of league payroll, against 2023-25
            // interior resets (Chris Jones 11.4 % of the 2025 cap, Wilkins 9.8 %,
            // Quinnen Williams and Dexter Lawrence 8.8-9.4 %) that put the real
            // top-3 IDL average near 9.7 % — an implied multiplier of ~1.0.
            // Every other rung of the ladder was inside a point of its implied
            // value at the same measurement: WR 1.30 (1.28) · LT 1.05 (1.02) ·
            // CB 0.95 (0.90) · MLB 0.80 (0.76) · S 0.75 (0.70) · TE 0.70 (0.70).
            //
            // **What broke in #88a, and what it turned out to be.** The extra
            // market demand is paid out of a fixed club budget in the `career`
            // rig's `tickContracts`, which clips a deal that would take payroll
            // past 92 % of the cap — and the man who absorbs a clip is always
            // the most expensive one on the sheet. Assert 6.11e (franchise QBs
            // paid in [0.75, 1.15] of their own ask) therefore moved 0.823 →
            // 0.746 and failed. That was the whole failure: one Monte-Carlo run,
            // 21 points of headroom, and a mechanism that is arithmetically a
            // budget-crowding effect rather than a statement about DT.
            //
            // Re-measured at 1.0 on this tree (2026-08-06), three gates green:
            // 6.11e reads **0.798** and **0.828** over two runs against a
            // baseline of 0.819 — i.e. inside the run-to-run spread of the
            // unseeded rig, with 0.05-0.08 of margin under the 0.75 floor. DT
            // payroll share goes 7.77 % → 8.41 % and the DL group 18.1 % →
            // 18.8 %, both well clear of 6.11d's 30 % ceiling; 6.11b moves
            // 0.810 → 0.826 and 6.11c is unchanged at 0.750. `leaguegen` (19)
            // and `draftclass` (32) are unaffected and pass.
            //
            // The band was NOT loosened and no other multiplier was moved to pay
            // for this: the offsetting slack the task asked for turned out not to
            // be needed, because the crowding #88a measured was a fraction of a
            // percent of league-wide demand (DT is 7.8 % of payroll; +11 % on it
            // is +0.86 % of the total) landing on a rig whose equilibrium payroll
            // sits at 76-77 % of a 92 % ceiling. If a future wave does need the
            // slack, CB (0.95 vs implied 0.90) and the safeties (0.75 vs 0.70)
            // are where it is, and `leagueAffordabilityScale` is the one knob
            // that moves the LEVEL without disturbing the ladder's shape.
            //
            // The implied-multiplier readings above come from the `career`
            // equilibrium cap sheet (20 leagues x 30 seasons, ~33 900 rostered
            // slots), anchored on the one rung already calibrated — the
            // quarterback at 2.2, which the NFL pays ~21.5 % of the cap — with
            // every other position read off its own top-of-market share. MLB is
            // inside band and is unchanged; DT was the one real gap.
            return 1.0    // Interior DL: ~8-9.5% (NFL top-3 IDL ~9.7%)
        case .RT:
            return 0.85   // RT: ~7-8%
        case .MLB:
            return 0.8    // MLB: ~6-7%
        case .FS, .SS:
            return 0.75   // Safeties: ~5.5-7%
        case .TE:
            return 0.7    // TE: ~4.5-6%
        case .LG, .RG, .C:
            return 0.65   // Interior OL: ~4-5%
        case .RB:
            return 0.6    // RBs devalued but not free: ~4.5-6.5%
        case .FB:
            return 0.25   // FB: ~1-2%
        case .K, .P:
            return 0.25   // Specialists: ~1-2%
        }
    }

    /// Market value for a player, denominated in his club's ACTUAL cap.
    ///
    /// `salaryCap` is required on purpose (task #87 / F5): it used to default to
    /// the season-one 265 000, which on a season-ten save priced every player
    /// against a cap 40 % smaller than the one his salary was negotiated under.
    /// Two call sites were relying on that default and neither knew it.
    static func estimateMarketValue(player: Player, salaryCap: Int) -> Int {
        // Which position is he PAID as? His own, unless he has genuinely been
        // converted across position families — see `bestPayingPosition`.
        let natural = naturalPositionForAttributes(player.positionAttributes)
        let position = bestPayingPosition(
            current: player.position, natural: natural, physical: player.physical
        )
        return estimateMarketValue(
            overall: player.overall,
            position: position,
            age: player.age,
            salaryCap: salaryCap
        )
    }

    /// The market-value core, over plain values instead of a `Player`.
    ///
    /// Split out for the roster seeder (`LeagueGenerator.realisticSalary`), which
    /// has to price a man BEFORE the `Player` object exists and — more
    /// importantly — has to price the man he *was* when his current deal was
    /// signed: a lower rating, a younger age and a smaller cap. `position` is
    /// the position he is PAID as; the `Player` overload above resolves that
    /// through `bestPayingPosition` first.
    static func estimateMarketValue(
        overall: Int, position: Position, age: Int, salaryCap: Int
    ) -> Int {
        let basePercent = marketBasePercent(overall: overall)

        // Convert cap percentage to thousands, denominated in a league that can
        // afford its own roster (see `leagueAffordabilityScale`).
        var value = basePercent * positionMultiplier(position) * leagueAffordabilityScale
            * Double(salaryCap) / 100.0

        // Age adjustment: discount once the player is past peak years
        let peakRange = position.peakAgeRange
        if age > peakRange.upperBound {
            let yearsOver = age - peakRange.upperBound
            let agePenalty = 1.0 - (Double(yearsOver) * 0.10)
            value *= max(agePenalty, 0.3)
        } else if age < peakRange.lowerBound {
            // Young players on rookie-scale pay: slight discount for inexperience
            let yearsUnder = peakRange.lowerBound - age
            let youthDiscount = 1.0 - (Double(yearsUnder) * 0.05)
            value *= max(youthDiscount, 0.6)
        }

        // Floor: every player is worth at least the veteran minimum.
        return max(Int(value), veteranMinimum(cap: salaryCap))
    }

    // MARK: - Realistic Mode

    /// Create a fully detailed contract for realistic cap mode.
    static func createContract(
        playerID: UUID,
        teamID: UUID,
        years: Int,
        baseSalaries: [Int],
        signingBonus: Int,
        guaranteed: Int,
        noTrade: Bool
    ) -> Contract {
        Contract(
            playerID: playerID,
            teamID: teamID,
            totalYears: years,
            currentYear: 0,
            baseSalary: baseSalaries,
            signingBonus: signingBonus,
            guaranteedMoney: guaranteed,
            noTradeClause: noTrade
        )
    }

    // MARK: - Realistic Contract Structures

    /// Generates escalating base salaries for a young player's contract.
    /// Base salary increases ~5-10% per year, rewarding players who grow into the deal.
    static func escalatingBaseSalaries(annualSalary: Int, years: Int) -> [Int] {
        guard years > 0 else { return [] }
        // Start ~15% below the average and escalate ~7% per year
        let startBase = max(Int(Double(annualSalary) * 0.85), 500)
        return (0..<years).map { yearIndex in
            let escalation = pow(1.07, Double(yearIndex))
            return max(Int(Double(startBase) * escalation), 500)
        }
    }

    /// Generates front-loaded base salaries for a veteran's contract.
    /// Higher salary in early years, tapering off in later years.
    static func frontLoadedBaseSalaries(annualSalary: Int, years: Int) -> [Int] {
        guard years > 0 else { return [] }
        // Start 15% above the average, decrease ~8% per year
        let startBase = Int(Double(annualSalary) * 1.15)
        return (0..<years).map { yearIndex in
            let taper = pow(0.92, Double(yearIndex))
            return max(Int(Double(startBase) * taper), 500)
        }
    }

    /// The signing-bonus band for a salary level, as a `(low, span)` pair.
    ///
    /// Split out of ``realisticSigningBonus`` so the same three bands can be
    /// drawn from a **stable** draw as well as a random one. See
    /// ``signingBonus(annualSalary:draw:)`` for why that matters.
    /// - Big contracts (>= $10M/yr): 40-60 % of first year salary
    /// - Medium contracts ($3-10M/yr): 20-40 %
    /// - Small contracts (< $3M/yr): 10-20 %
    static func signingBonusBand(annualSalary: Int) -> (low: Double, span: Double) {
        if annualSalary >= 10_000 { return (0.40, 0.20) }
        if annualSalary >= 3_000  { return (0.20, 0.20) }
        return (0.10, 0.10)
    }

    /// A signing bonus from a caller-supplied 0…1 draw.
    ///
    /// **Why this exists.** `ContractDemand` is documented as deterministic —
    /// the ask must not move between two openings of the same conversation —
    /// but its opening offer used to build its bonus from
    /// ``realisticSigningBonus``, i.e. from `Double.random`. Since the agent
    /// grades every offer against `annualCapHit` (salary + bonus/years), the
    /// number the whole negotiation turns on was re-rolled ±2.3 % on every call
    /// that was not reading a persisted snapshot. Feeding a UUID-seeded draw in
    /// makes the ask deterministic all the way down.
    static func signingBonus(annualSalary: Int, draw: Double) -> Int {
        let band = signingBonusBand(annualSalary: annualSalary)
        let clamped = Swift.min(1.0, Swift.max(0.0, draw))
        return Int(Double(annualSalary) * (band.low + band.span * clamped))
    }

    /// Calculates a realistic signing bonus for a contract — the RANDOM draw,
    /// for the AI paths that write a contract once and never re-price it.
    /// Anything that must quote the same number twice uses
    /// ``signingBonus(annualSalary:draw:)`` instead.
    static func realisticSigningBonus(annualSalary: Int) -> Int {
        signingBonus(annualSalary: annualSalary, draw: Double.random(in: 0...1))
    }

    /// Calculates realistic guaranteed money for a contract.
    /// First 1-2 years fully guaranteed for big deals, less for smaller ones.
    static func realisticGuaranteedMoney(baseSalaries: [Int], signingBonus: Int) -> Int {
        guard !baseSalaries.isEmpty else { return signingBonus }
        let avgSalary = baseSalaries.reduce(0, +) / baseSalaries.count
        let guaranteedYears: Int
        if avgSalary >= 15_000 {
            guaranteedYears = min(2, baseSalaries.count)
        } else if avgSalary >= 5_000 {
            guaranteedYears = min(2, baseSalaries.count)
        } else {
            guaranteedYears = 1
        }
        let guaranteedBase = baseSalaries.prefix(guaranteedYears).reduce(0, +)
        return guaranteedBase + signingBonus
    }

    /// Build a complete realistic contract with escalating or front-loaded structure.
    /// - Young players (age < 28): escalating salary structure
    /// - Veteran players (age >= 28): front-loaded salary structure
    ///
    /// `signingBonus` and `guaranteedMoney` are `nil` for the AI market, which
    /// has no negotiated structure to carry and draws its own. **A deal that
    /// came out of a negotiation must pass both**: the bonus, the guarantee and
    /// the no-trade clause the agent demanded and the GM agreed to are terms of
    /// the contract, and re-drawing them here silently threw away the half of
    /// the deal that was not the salary.
    static func buildRealisticContract(
        playerID: UUID,
        teamID: UUID,
        annualSalary: Int,
        years: Int,
        playerAge: Int,
        noTrade: Bool = false,
        signingBonus negotiatedBonus: Int? = nil,
        guaranteedMoney negotiatedGuarantee: Int? = nil
    ) -> Contract {
        let baseSalaries: [Int]
        if playerAge < 28 {
            baseSalaries = escalatingBaseSalaries(annualSalary: annualSalary, years: years)
        } else {
            baseSalaries = frontLoadedBaseSalaries(annualSalary: annualSalary, years: years)
        }
        let signingBonus = negotiatedBonus ?? realisticSigningBonus(annualSalary: annualSalary)
        let guaranteed = negotiatedGuarantee
            ?? realisticGuaranteedMoney(baseSalaries: baseSalaries, signingBonus: signingBonus)

        return Contract(
            playerID: playerID,
            teamID: teamID,
            totalYears: years,
            currentYear: 0,
            baseSalary: baseSalaries,
            signingBonus: signingBonus,
            guaranteedMoney: guaranteed,
            noTradeClause: noTrade
        )
    }

    // MARK: - Projected Cap Charge (cap-compliance wave, #102 F5)

    /// The signing bonus a free-agent deal for this man will carry — **stable**,
    /// so the number a reservation holds and the number the contract charges are
    /// the same number.
    ///
    /// ``realisticSigningBonus`` rolls `Double.random` on every call, which is
    /// fine for a club that writes a deal once and never re-prices it and fatal
    /// for anything that has to QUOTE the deal before it exists. The bonus band
    /// is 20 points wide (40-60 % of first-year salary on a big contract), so a
    /// projection built from a second random draw could miss the real charge by
    /// a fifth of the bonus — which on a three-year deal is real money and, in
    /// the direction that matters, money the club promised and did not reserve.
    /// Seeded off the player id exactly like ``ContractDemand``'s ask (see
    /// ``signingBonus(annualSalary:draw:)``), the draw is a pure function of the
    /// man and the terms, and quote == charge by construction.
    static func stableSigningBonus(playerID: UUID, annualSalary: Int) -> Int {
        signingBonus(annualSalary: annualSalary, draw: stableUnitDraw(playerID))
    }

    /// **What a signing at these terms will actually charge the cap, per year.**
    ///
    /// The hole this closes (#102 F5): free agency reserved the SALARY while
    /// `FreeAgencyEngine.signFreeAgent` charged `Contract.capHit` — a realistic
    /// deal for a 28-year-old opens 15 % above the average
    /// (``frontLoadedBaseSalaries``) and carries a prorated signing bonus on top.
    /// Three $4M offers against $12M of room therefore reserved $12M and charged
    /// about $15M, walking the club straight through the door the reservation
    /// ledger exists to hold shut.
    ///
    /// **Not a second formula.** The projection is the contract: it calls
    /// ``buildRealisticContract`` — the function `signFreeAgent` writes the deal
    /// with — and reads `Contract.capHit` off the result. The row is never
    /// inserted into a `ModelContext`, so nothing is persisted; it exists for the
    /// length of this call purely so the quote cannot drift from the charge when
    /// the structure changes. Simple and sandbox charge the flat salary, which is
    /// what their signing paths do (`signPlayerSimple`, and sandbox's no-op).
    static func projectedCapHit(
        playerID: UUID,
        annualSalary: Int,
        years: Int,
        playerAge: Int,
        capMode: CapMode
    ) -> Int {
        let salary = Swift.max(0, annualSalary)
        guard capMode == .realistic else { return salary }
        let contract = buildRealisticContract(
            playerID: playerID,
            teamID: UUID(),
            annualSalary: salary,
            years: Swift.max(1, years),
            playerAge: playerAge,
            noTrade: false,
            signingBonus: stableSigningBonus(playerID: playerID, annualSalary: salary)
        )
        return contract.capHit
    }

    /// A deterministic 0…1 draw from a player id. FNV-1a over the uuid bytes,
    /// the same shape `ContractNegotiationEngine.unitDraw` uses for the agent's
    /// ask, kept here so this file's own pricing does not have to reach into the
    /// negotiation engine's private helpers.
    static func stableUnitDraw(_ id: UUID, salt: UInt64 = 0x5CA1) -> Double {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325 ^ salt
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        return Double(hash % 10_000) / 10_000.0
    }

    // MARK: - Negotiated Deal Execution

    /// What a signed negotiation does to the deal that was already there.
    enum DealApplication {
        /// Adds the new years on top of the existing contract (an extension).
        case extendExisting
        /// Replaces the contract outright (a re-sign of an expiring deal).
        case replaceContract
    }

    /// **The one place a negotiated contract is booked.**
    ///
    /// Four screens can close a `ContractNegotiationView` thread — player
    /// detail, the cap screen, the franchise-tag screen and Final Push — and
    /// before this each of them wrote its own two lines:
    ///
    /// ```swift
    /// player.contractYearsRemaining += offer.years
    /// player.annualSalary = offer.annualSalary
    /// ```
    ///
    /// Three consequences, all of them live bugs:
    ///
    /// 1. **`team.currentCapUsage` was never touched.** Sign a 96 OVR
    ///    quarterback at $55M/yr and the club's available cap did not move, so
    ///    it could then sign the rest of the league. On the cap screen the
    ///    derived dead-money residual (`currentCapUsage − Σ capHit`) went
    ///    NEGATIVE as a direct result of the signing and the card flipped to
    ///    "Ledger variance".
    /// 2. **The signing bonus was free money.** The agent grades
    ///    `annualCapHit` = salary + bonus/years, but only `annualSalary` was
    ///    ever written — so $500K salary plus a $200M bonus read as a $50.5M/yr
    ///    offer to the agent and as the veteran minimum to the league.
    /// 3. **A `Contract` row, where one existed, kept the OLD numbers**, so on
    ///    the one screen that reads contracts in preference to `annualSalary`
    ///    the raise never appeared at all.
    ///
    /// So: the charge is `annualCapHit`, the ledger is moved by the DIFFERENCE
    /// between the new charge and the one the club was already carrying, and the
    /// detailed contract is rewritten in place with the structure that was
    /// actually negotiated. `player.annualSalary` carries the full per-year cap
    /// number because that is what every other system in the game
    /// (`HoldoutEngine`, `TradeValueEngine`, the cap bars) reads it as.
    ///
    /// **A signed deal rescinds a franchise tag.** That is the NFL rule — the tag
    /// is a placeholder for the long-term contract, and agreeing the contract
    /// retires it — and without it the tag was live money the club paid twice.
    /// The flag survived the signing, so `FreeAgencyEngine.settleFranchiseTags`
    /// found him at the rollover and OVERWROTE the deal just agreed with the
    /// one-year tag number: the extension the user negotiated was destroyed
    /// between screens, and the forward reservation kept charging every cap
    /// projection in the meantime. Both are undone here, before the new deal is
    /// written, so the tag cannot outlive the signature.
    ///
    /// - Parameter existingContract: the player's detailed contract when the
    ///   caller already has it. Passing `nil` makes the function look one up
    ///   through `modelContext`; passing `nil` with no context means the deal is
    ///   booked on `annualSalary` alone, which is the simple-mode shape.
    /// - Parameter careerID: the save whose forward ledger a rescinded tag is
    ///   released from. `career.id`, matching every reader of that table;
    ///   `player.careerID` is only the fallback for a path with no `Career` in
    ///   hand, and a nil there releases nothing at all.
    @discardableResult
    static func applyNegotiatedDeal(
        player: Player,
        team: Team?,
        offer: NegotiationOffer,
        application: DealApplication,
        capMode: CapMode,
        careerID: UUID? = nil,
        existingContract: Contract? = nil,
        modelContext: ModelContext? = nil
    ) -> Int {
        let playerID = player.id
        let contract: Contract? = existingContract ?? {
            guard capMode == .realistic, let modelContext else { return nil }
            let descriptor = FetchDescriptor<Contract>(
                predicate: #Predicate<Contract> { $0.playerID == playerID }
            )
            return try? modelContext.fetch(descriptor).first
        }()

        // What the club is carrying for this man RIGHT NOW, read with exactly
        // the precedence the cap screen reads it with, so the two can never
        // disagree about what a signing changed.
        let previousCharge = contract?.capHit ?? player.annualSalary

        // **The restructure receipt is settled here** (#102 F6).
        //
        // Everything below rewrites `annualSalary`, `contractYearsRemaining` and
        // the `Contract` row, and the three restructure fields used to survive
        // all of it. Two live bugs came out of that, both of them free money in
        // the club's favour and both of them silent:
        //
        // 1. `FreeAgencyEngine.executeNewLeagueYear` does
        //    `annualSalary += restructureReliefK` at the next rollover, on
        //    WHATEVER salary the row is carrying by then. Extend a man who was
        //    restructured at $9.25M on a $15M deal and March books him at
        //    $26.2M — a raise nobody negotiated, charged against a contract that
        //    never contained the converted money.
        // 2. `restructureDeadMoney` kept accelerating a bonus the rewritten row
        //    no longer contains, so a later cut charged the club twice for it.
        //
        // The settlement is `applyRelease`'s: the unpaid proration accelerates
        // into THIS year's books as dead money. That is the NFL answer and it is
        // the honest one — the club converted base into bonus and owes the
        // converted money whether the man re-signs, is traded or is cut; only
        // the timing was ever in question. `restructureDeadMoney` is
        // `proration × carryYears`, i.e. the current year's slice plus every
        // remaining one, which is exactly what `previousCharge` is about to stop
        // charging: the slice is folded into `annualSalary` (and, where a row
        // exists, into `baseSalary[currentYear]` — see `executeRestructure`),
        // so removing the old charge and adding the acceleration nets the same
        // way a release does.
        let restructureSettlement = max(0, player.restructureDeadMoney)
        player.restructureReliefK = 0
        player.restructureProrationK = 0
        player.restructureCarryYears = 0

        // The tag is retired by the signature — see the doc above. BEFORE the
        // clock is written, because rescinding restores the year of control the
        // tag floored it at and an extension must add its years to the contract
        // the man actually had.
        if player.isFranchiseTagged {
            rescindFranchiseTagBooks(player: player, careerID: resolvedCareerID(careerID, player: player))
        }

        let years: Int = {
            switch application {
            case .extendExisting: return max(0, player.contractYearsRemaining) + offer.years
            case .replaceContract: return offer.years
            }
        }()

        player.contractYearsRemaining = years
        player.annualSalary = offer.annualCapHit

        // Rewrite the detailed contract in place (realistic mode only — the
        // other two modes have no `Contract` row to keep in step).
        var newCharge = player.annualSalary
        if capMode == .realistic, let team {
            let baseSalaries = player.age < 28
                ? escalatingBaseSalaries(annualSalary: offer.annualSalary, years: years)
                : frontLoadedBaseSalaries(annualSalary: offer.annualSalary, years: years)
            // The NEGOTIATED structure, not a fresh random draw: the bonus, the
            // guarantee and the no-trade clause were terms both sides agreed to.
            let guaranteed = offer.guaranteedMoney

            if let contract {
                contract.teamID = team.id
                contract.totalYears = years
                contract.currentYear = 0
                contract.baseSalary = baseSalaries
                contract.signingBonus = offer.signingBonus
                contract.guaranteedMoney = guaranteed
                contract.noTradeClause = offer.noTradeClause
                newCharge = contract.capHit
            } else if let modelContext {
                let created = Contract(
                    playerID: player.id,
                    teamID: team.id,
                    totalYears: years,
                    currentYear: 0,
                    baseSalary: baseSalaries,
                    signingBonus: offer.signingBonus,
                    guaranteedMoney: guaranteed,
                    noTradeClause: offer.noTradeClause
                )
                created.careerID = player.careerID ?? team.careerID
                modelContext.insert(created)
                newCharge = created.capHit
            }
        }

        // Sandbox deliberately keeps no ledger — see `signPlayerSandbox`. The
        // restructure acceleration rides on the same line for the same reason it
        // rides on `applyRelease`'s: sandbox never booked the relief, so it must
        // never book the charge.
        if capMode != .sandbox, let team {
            team.currentCapUsage += newCharge - previousCharge + restructureSettlement
        }

        return newCharge
    }

    // MARK: - Restructure (cap-compliance wave, REMEDIATION lever 2)
    //
    // DELETED here: `restructureContract(contract:)`. It converted 80 % of the
    // current base into bonus and returned a **value copy** of the row — no
    // caller, no cap ledger, no `Player`, no dead money, and since
    // `Contract.currentYear` never advances it prorated over the deal's original
    // length forever. The two functions below replace it: one prices the lever,
    // one applies it, and both book every consequence.

    /// The least number of contract years a restructure needs to be legal.
    ///
    /// Two, and the reason is arithmetic rather than taste: with one year left
    /// the proration has nowhere to go — `A / 1 = A` comes straight back onto
    /// this year's cap and the relief is exactly zero. Anything the UI let the
    /// user press in that state would be a button that does nothing.
    static let restructureMinimumYears = 2

    /// Morale the player gains from a restructure. Small and positive by
    /// design: the money is guaranteed earlier and none of it is lost, so an
    /// agent consents as a matter of routine — but it is still his club asking
    /// him for a favour, and the goodwill is worth something.
    static let restructureMoraleBonus = 2

    /// What a restructure would do, priced without doing it.
    struct RestructureQuote: Equatable {

        let playerID: UUID

        /// Base salary converted into signing bonus, in thousands (`A`).
        let convertedAmount: Int

        /// The per-year slice that conversion creates, in thousands (`A / N`).
        let proratedPerYear: Int

        /// Cap freed in the CURRENT league year, in thousands (`A − A/N`). This
        /// is the number the compliance workspace ranks levers by.
        let immediateRelief: Int

        /// Years still on the deal, from `Player.contractYearsRemaining` (`N`).
        let yearsRemaining: Int

        /// The club's charge for this man before the restructure.
        let currentCapHit: Int

        /// His charge for the rest of THIS league year afterwards.
        let newCapHit: Int

        /// His charge in every remaining year afterwards — the price of the
        /// relief, and the number that has to be on screen next to it.
        let futureYearCapHit: Int

        /// Dead money the restructure adds if he is released before the
        /// proration runs out (`A/N × N`). Booked through
        /// `Player.restructureDeadMoney` (task #68).
        let deadMoneyAdded: Int
    }

    /// Why a restructure is not on the table, phrased for the user.
    enum RestructureVerdict: Equatable {
        case available(RestructureQuote)
        case unavailable(String)

        var quote: RestructureQuote? {
            if case .available(let q) = self { return q }
            return nil
        }
    }

    /// Prices the restructure lever for one player.
    ///
    /// **The model.** A restructure converts base salary the club owes this year
    /// into signing bonus, and a signing bonus prorates evenly across the years
    /// still on the deal:
    ///
    /// ```
    /// A   = convertible base           (everything above the veteran minimum)
    /// N   = player.contractYearsRemaining
    /// p   = A / N                      this year's slice, and every later year's
    /// relief   = A − p                 cap freed NOW
    /// newHit   = capHit − relief       what he costs for the rest of this year
    /// laterHit = capHit + p            what he costs in each remaining year
    /// dead     = p × N                 acceleration if he is cut (task #68)
    /// ```
    ///
    /// The veteran minimum is the floor because a club cannot convert salary it
    /// is legally obliged to pay in cash — and because a player left at $0 base
    /// would read as unpaid on every screen in the game.
    ///
    /// **`N` comes from the player row, not from `Contract`.** `Contract.currentYear`
    /// is never advanced anywhere in the game, so a contract-derived "years left"
    /// would be the deal's original length in year four as surely as in year one,
    /// and the proration would be a fiction that got cheaper the longer you
    /// waited. `Player.contractYearsRemaining` is the authority the expiry loop
    /// itself decrements.
    ///
    /// - Parameter amount: convert less than the maximum. Clamped to
    ///   `0…convertible`; `nil` converts everything above the minimum, which is
    ///   what the compliance workspace wants when it is ranking levers by relief.
    static func restructureQuote(
        player: Player,
        contract: Contract?,
        capMode: CapMode,
        salaryCap: Int,
        amount: Int? = nil
    ) -> RestructureVerdict {

        guard capMode != .sandbox else {
            return .unavailable("The salary cap is off in Sandbox mode — there is nothing to restructure for.")
        }
        guard player.teamID != nil else {
            return .unavailable("\(player.fullName) is not under contract.")
        }

        let years = player.contractYearsRemaining
        guard years >= restructureMinimumYears else {
            return .unavailable(
                "\(player.fullName) has \(years == 1 ? "1 year" : "\(years) years") left. "
                + "A restructure needs at least \(restructureMinimumYears) years to prorate the money over."
            )
        }

        // The cap charge the club is carrying, read with the same precedence
        // `CapOverviewView.capHit(for:)` and `applyNegotiatedDeal` read it with,
        // so no two surfaces can disagree about what this man costs.
        let capHit = contract?.capHit ?? player.annualSalary

        // What can legally be moved: this year's BASE, less the league minimum.
        // With a detailed row that is the row's own number; without one (simple
        // mode, and every player the game never minted a `Contract` for) the
        // only base the game knows is `annualSalary`.
        let currentBase: Int = {
            guard let contract, contract.currentYear < contract.baseSalary.count else {
                return player.annualSalary
            }
            // Bounded by the cap UNIT. `Team.currentCapUsage` is charged in
            // `annualSalary` and rebuilt from it at every rollover (the task-#27
            // true-up), while the row's base is its own number; converting more
            // base than the salary carries would let `executeRestructure` clamp
            // `annualSalary` at zero and still credit the club the full relief —
            // cap room it was never charged, accepted as legal by the compliance
            // gate and taken back by the next true-up. Inert wherever the two
            // agree, which is every player with no `Contract` row. Unifying them
            // is task #87's work.
            return Swift.min(contract.baseSalary[contract.currentYear], Swift.max(0, player.annualSalary))
        }()

        let floor = veteranMinimum(cap: salaryCap)
        let convertible = max(0, currentBase - floor)
        guard convertible > 0 else {
            return .unavailable(
                "\(player.fullName) is already at the veteran minimum — there is no base salary left to convert."
            )
        }

        let converted = Swift.min(convertible, Swift.max(0, amount ?? convertible))
        guard converted > 0 else {
            return .unavailable("Nothing to convert.")
        }

        let prorated = converted / years
        let relief = converted - prorated
        guard relief > 0 else {
            return .unavailable("The amount is too small to free any cap this year.")
        }

        return .available(RestructureQuote(
            playerID: player.id,
            convertedAmount: converted,
            proratedPerYear: prorated,
            immediateRelief: relief,
            yearsRemaining: years,
            currentCapHit: capHit,
            newCapHit: capHit - relief,
            futureYearCapHit: capHit + prorated,
            deadMoneyAdded: prorated * years
        ))
    }

    /// Applies a restructure and books every consequence of it.
    ///
    /// Four ledgers move together, and the reason each one has to is spelled out
    /// because getting any of them wrong turns the lever into free money:
    ///
    /// 1. **`team.currentCapUsage −= relief`** — the club's books. This is the
    ///    point of the exercise.
    /// 2. **`player.annualSalary −= relief`** — the cap UNIT. `Team.currentCapUsage`
    ///    is charged in `annualSalary` and, crucially, REBUILT from it at every
    ///    league-year rollover (`FreeAgencyEngine.executeNewLeagueYear`'s task-#27
    ///    true-up). A restructure that moved only the team total would be undone
    ///    by the next March, and a restructure that moved only the salary would
    ///    free no cap this year.
    /// 3. **`contract.baseSalary[currentYear] −= relief`** where a detailed row
    ///    exists — so `Contract.capHit` moves by exactly what the ledger moved
    ///    by. `CapOverviewView` derives its Dead Money card from
    ///    `currentCapUsage − Σ capHit`; if the row did not follow, a restructure
    ///    would show up on that card as `relief` of phantom dead money.
    ///    Deliberately `−relief` and NOT `−converted` + `signingBonus += …`: the
    ///    row prorates its bonus over `totalYears`, and `totalYears ≠ N` for any
    ///    deal past its first season, so booking the conversion into the row's
    ///    own bonus field would charge a different number than the one the club
    ///    just saved. The economics live on the player row instead (4).
    /// 4. **`player.restructureReliefK / ProrationK / CarryYears`** — the receipt.
    ///    `restructureReliefK` is added back to `annualSalary` at the next
    ///    rollover (the relief was for ONE year, exactly like the #45 midseason
    ///    proration restore that sits beside it); `restructureProrationK` stays
    ///    folded into the salary for `restructureCarryYears` league years and is
    ///    charged as dead money by `CapManagementEngine.tradeCapSplit` if he is
    ///    cut first (task #68).
    ///
    /// **Consent is not rolled for.** A restructure gives the player the same
    /// money sooner and more of it guaranteed; no agent in football turns that
    /// down. The morale bump is the whole social cost, and making it
    /// deterministic keeps the compliance workspace's ranked lever list honest —
    /// a lever the user can be refused after pressing is not a plan.
    ///
    /// Returns the quote that was applied, or `nil` if the lever was not legal.
    @discardableResult
    static func executeRestructure(
        player: Player,
        team: Team?,
        contract: Contract?,
        capMode: CapMode,
        salaryCap: Int,
        amount: Int? = nil,
        moraleBonus: Int = restructureMoraleBonus
    ) -> RestructureQuote? {

        guard case .available(let quote) = restructureQuote(
            player: player,
            contract: contract,
            capMode: capMode,
            salaryCap: salaryCap,
            amount: amount
        ) else { return nil }

        let relief = quote.immediateRelief

        player.annualSalary = Swift.max(0, player.annualSalary - relief)
        team?.currentCapUsage = Swift.max(0, (team?.currentCapUsage ?? 0) - relief)

        if let contract, contract.currentYear < contract.baseSalary.count {
            var rows = contract.baseSalary
            rows[contract.currentYear] = Swift.max(0, rows[contract.currentYear] - relief)
            contract.baseSalary = rows
        }

        // The receipt. `+=` on the first two because a club can restructure the
        // same man twice in one league year (or in successive ones) and every
        // slice is still owed; `max` on the horizon because the LONGEST live
        // proration governs — erring toward charging a slice one year too long
        // rather than one year too short, which is the safe direction for a
        // ledger that gates the week advance.
        player.restructureReliefK += quote.convertedAmount
        player.restructureProrationK += quote.proratedPerYear
        player.restructureCarryYears = Swift.max(player.restructureCarryYears, quote.yearsRemaining)

        if moraleBonus != 0 {
            player.morale = Swift.max(1, Swift.min(100, player.morale + moraleBonus))
        }

        return quote
    }

    // MARK: - Pay Cut (cap-compliance wave, REMEDIATION lever 3)

    /// What a pay-cut ask would do, priced without asking.
    struct PayCutQuote: Equatable {
        let playerID: UUID
        /// The club's charge for this man today.
        let currentCapHit: Int
        /// What it would be after the cut.
        let proposedCapHit: Int
        /// Cap freed this year, in thousands. Never negative — a "cut" that
        /// pays more is a raise and belongs in the extension flow.
        let capSavings: Int
        /// 0…1 — how deep the ask is. The agent prices insult off this.
        let cutFraction: Double
        /// The floor the ask cannot go below.
        let veteranMinimum: Int
        /// Whether the proposal is legal at all (above the minimum, and a cut).
        let isValid: Bool
    }

    /// Prices a pay-cut proposal.
    ///
    /// The chat owns whether the player SAYS YES — persona, morale, standing and
    /// the dialogue library are `ContractNegotiationEngine`'s business. This
    /// function owns only what the money does, so both sides of that
    /// conversation are quoting the same arithmetic.
    static func payCutQuote(
        player: Player,
        contract: Contract?,
        capMode: CapMode,
        salaryCap: Int,
        proposedAnnualSalary: Int
    ) -> PayCutQuote {
        let capHit = contract?.capHit ?? player.annualSalary
        let floor = veteranMinimum(cap: salaryCap)
        let proposed = Swift.max(floor, proposedAnnualSalary)

        // **Savings are measured in the cap UNIT, the display in cap hit.**
        //
        // `contract.capHit` is base plus prorated bonus and is the honest answer
        // to "what does this man cost", which is what belongs on screen. But
        // `Team.currentCapUsage` is charged in `annualSalary` and REBUILT from
        // it at every league-year rollover (`FreeAgencyEngine.executeNewLeagueYear`'s
        // task-#27 true-up), and the two only coincide for a player with no
        // `Contract` row — the common case, since rows are minted only for
        // realistic-mode signings. Pricing the relief off the larger number
        // would credit the club cap it was never charged: `applyPayCut` clamps
        // `annualSalary` at zero while subtracting the full figure from the
        // team total, the compliance gate reads the club as legal, and the next
        // true-up takes it all back. `bookable` is the ceiling that cannot
        // happen, and it is inert wherever the two agree.
        //
        // It also makes this function agree with the Contact Agent chat, which
        // prices its dial and its verdict off `player.annualSalary` — one
        // conversation must not quote two different savings.
        //
        // Unifying the two salaries for real is task #87's work, not this call's.
        let bookable = Swift.max(0, player.annualSalary)
        let savings = Swift.max(0, Swift.min(capHit, bookable) - proposed)
        let fraction = capHit > 0 ? Double(savings) / Double(capHit) : 0

        return PayCutQuote(
            playerID: player.id,
            currentCapHit: capHit,
            proposedCapHit: capHit - savings,
            capSavings: savings,
            cutFraction: fraction,
            veteranMinimum: floor,
            isValid: capMode != .sandbox && savings > 0 && player.teamID != nil
        )
    }

    /// The morale hit a pay cut of this depth lands, before persona.
    ///
    /// Linear in the depth of the cut and capped at −20: a 10 % trim off a big
    /// number is a shrug (−2), halving a man's pay is a grievance (−10), and
    /// taking him to the minimum is the worst day of his professional life
    /// (−20). The Contact Agent chat scales this by persona and standing — it
    /// owns the SOCIAL half of the transaction — which is why this is a
    /// suggestion the caller may override rather than a value baked into
    /// ``applyPayCut``.
    static func payCutMoraleDelta(cutFraction: Double) -> Int {
        let clamped = Swift.min(1.0, Swift.max(0.0, cutFraction))
        return -Int((clamped * 20.0).rounded())
    }

    /// Applies an AGREED pay cut. **The one place a pay cut is booked.**
    ///
    /// Same four-ledger discipline as ``executeRestructure``: the team total,
    /// the salary the true-up rebuilds from, the detailed row's current-year
    /// base so `Contract.capHit` cannot drift from the ledger, and the morale
    /// consequence. Nothing is written unless the quote is valid, so a caller
    /// that forgot to check cannot half-apply a deal.
    ///
    /// Term is untouched by design: a pay cut moves money, not years. An ask
    /// that also changes the length of the deal is an EXTENSION and goes through
    /// `applyNegotiatedDeal`, which rewrites the whole structure.
    ///
    /// - Parameter moraleDelta: the persona-scaled consequence the chat decided
    ///   on. Defaults to ``payCutMoraleDelta(cutFraction:)`` for callers that
    ///   have no persona layer (the compliance workspace's plain ask).
    @discardableResult
    static func applyPayCut(
        player: Player,
        team: Team?,
        contract: Contract?,
        capMode: CapMode,
        salaryCap: Int,
        newAnnualSalary: Int,
        moraleDelta: Int? = nil
    ) -> PayCutQuote? {

        let quote = payCutQuote(
            player: player,
            contract: contract,
            capMode: capMode,
            salaryCap: salaryCap,
            proposedAnnualSalary: newAnnualSalary
        )
        guard quote.isValid else { return nil }

        // Already bounded by the cap unit — see `payCutQuote`.
        let savings = quote.capSavings

        player.annualSalary = Swift.max(0, player.annualSalary - savings)
        team?.currentCapUsage = Swift.max(0, (team?.currentCapUsage ?? 0) - savings)

        if let contract, contract.currentYear < contract.baseSalary.count {
            var rows = contract.baseSalary
            rows[contract.currentYear] = Swift.max(0, rows[contract.currentYear] - savings)
            contract.baseSalary = rows
            // A pay cut cannot leave a guarantee larger than the deal it sits
            // on — the player agreed to give the money up, guaranteed or not.
            contract.guaranteedMoney = Swift.min(contract.guaranteedMoney, contract.totalValue)
        }

        let delta = moraleDelta ?? payCutMoraleDelta(cutFraction: quote.cutFraction)
        if delta != 0 {
            player.morale = Swift.max(1, Swift.min(100, player.morale + delta))
        }

        return quote
    }

    /// Cut a player in realistic mode. Returns the dead-cap hit the team absorbs.
    /// - Parameters:
    ///   - contract: The player's current contract.
    ///   - team: The team releasing the player.
    ///   - postJune1: If `true`, the dead cap is split across two league years.
    /// - Returns: The dead-cap charge applied in the current year.
    static func cutPlayerRealistic(contract: Contract, team: Team, postJune1: Bool) -> Int {
        let totalDeadCap = contract.deadCap

        let currentYearHit: Int
        if postJune1, contract.totalYears > 0 {
            // Post-June 1: only one year's prorated bonus hits now;
            // the rest accelerates into next year's cap.
            let proratedPerYear = contract.signingBonus / contract.totalYears
            currentYearHit = proratedPerYear
        } else {
            currentYearHit = totalDeadCap
        }

        // Swap the full cap hit for the dead-cap charge
        team.currentCapUsage -= contract.capHit
        team.currentCapUsage += currentYearHit

        return currentYearHit
    }

    /// Cap-mode-aware realistic cut. Sandbox releases the player with zero dead
    /// cap and no cap mutation; realistic and simple defer to the existing path.
    static func cutPlayerRealistic(contract: Contract, team: Team, postJune1: Bool, capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return cutPlayerRealistic(contract: contract, team: team, postJune1: postJune1)
        case .sandbox:
            return 0
        }
    }

    // MARK: - Franchise Tag

    /// Calculate the franchise-tag value for a position: the average of the
    /// top 5 salaries (in thousands) supplied for that position group.
    static func franchiseTagValue(position: Position, topSalaries: [Int]) -> Int {
        let sorted = topSalaries.sorted(by: >)
        let topFive = Array(sorted.prefix(5))
        guard !topFive.isEmpty else { return 0 }
        return topFive.reduce(0, +) / topFive.count
    }

    /// Cap-mode-aware franchise-tag value, **floor included** (task #87 / F16).
    ///
    /// The floor used to be a hardcoded `max(value, 5_000)` written out twice, in
    /// `FranchiseTagView` and `FinalPushView` — two copies of a cap-INDEPENDENT
    /// number guarding a cap-relative one, so by season five the floor had
    /// quietly become a rounding error. It is now 1.9 % of the cap (5 000 ÷ 265
    /// 000, i.e. exactly what it has always been in season one) and it lives with
    /// the value it floors. `FranchiseTagView` also used to call the overload
    /// WITHOUT `capMode`, so a sandbox save was charged a real tag.
    static func franchiseTagValue(position: Position, topSalaries: [Int], capMode: CapMode, salaryCap: Int) -> Int {
        switch capMode {
        case .simple, .realistic:
            let value = franchiseTagValue(position: position, topSalaries: topSalaries)
            return max(value, Int(franchiseTagFloorShare * Double(salaryCap)))
        case .sandbox:
            return 0
        }
    }

    /// The tag floor, as a share of the cap. `5_000 / 265_000` — the number both
    /// screens hardcoded, expressed so it grows with the league.
    static let franchiseTagFloorShare = 5_000.0 / Double(openingSalaryCap)

    /// **Apply the franchise tag — a decision about NEXT league year** (#127).
    ///
    /// The bug this replaces, in the user's own numbers: a club with $27.4M of
    /// room tagged a quarterback earning $36.9M on the last year of his deal at
    /// a $32.8M tag, and the header went to **$31.4M** — the tag had *given the
    /// club back $4.0M*. The old body did
    ///
    /// ```swift
    /// player.contractYearsRemaining = 1
    /// player.annualSalary = tagValue
    /// team.currentCapUsage = team.currentCapUsage - previousSalary + tagValue + …
    /// ```
    ///
    /// i.e. it tore up a contract that is still running and charged next year's
    /// number against this year's books. Both halves are wrong in the same
    /// direction: **the tag is not a repricing of the current league year, it is
    /// a commitment for the one that has not started.** A tagged man plays out
    /// the season he is already being paid for; from the new league year his
    /// expired deal is replaced by the one-year tag.
    ///
    /// So this function no longer touches `annualSalary` and no longer touches
    /// `Team.currentCapUsage` at all. It flags the man — which is what makes
    /// `FreeAgencyEngine.executeNewLeagueYear`'s expiry loop skip him instead of
    /// putting him on the market — and books the tag number as a **forward
    /// commitment** binding `bindingSeason`. `FreeAgencyEngine.settleFranchiseTags`
    /// consumes it at the rollover, which is the moment the money becomes real.
    ///
    /// Sandbox is the same shape, with `tagValue` already 0 from
    /// ``franchiseTagValue(position:topSalaries:capMode:salaryCap:)`` — the mode
    /// switches the CAP off, not the year of team control, so the flag and the
    /// morale hit still land and the settlement writes a $0 tag.
    ///
    /// R22: no player wants the tag — it costs 10 morale.
    ///
    /// - Parameter bindingSeason: the league year the tag charges. Callers pass
    ///   `career.currentSeason + 1`: `WeekAdvancer` does not increment the year
    ///   until the roster-cuts → regular-season transition, so every offseason
    ///   phase of a given league year reads the same `currentSeason`, and the
    ///   year a tag decided in that offseason applies to is always the next one.
    /// - Parameter careerID: the save the forward ledger row belongs to, passed
    ///   explicitly because `Player.careerID` is optional and a nil there books
    ///   NOTHING — silently, and against a table every reader queries with
    ///   `career.id`. Callers all hold a `Career`; they pass its id.
    static func applyFranchiseTag(
        player: Player,
        tagValue: Int,
        team: Team?,
        capMode: CapMode,
        bindingSeason: Int,
        careerID: UUID
    ) {
        _ = team // The club's books are deliberately untouched — see the doc above.
        _ = capMode

        // A tagged man is under club control for the tag year. Normally he is
        // already at 1 (the tag screen only offers `contractYearsRemaining <= 1`)
        // and this is a no-op; the `max` only covers the man whose deal has
        // somehow already run to 0 while he is still on the roster, who would
        // otherwise be skipped by the expiry loop AND carry no year of control.
        // Never lowered: the clock is the rollover's business, not the tag's.
        //
        // Where it DOES raise the clock the pre-tag value is stashed on the
        // ledger row, because that is the only thing that makes
        // `removeFranchiseTag` an exact undo (F3): without it a rescinded tag
        // left a 0-year man sitting at 1.
        let priorYears = player.contractYearsRemaining
        player.contractYearsRemaining = Swift.max(1, player.contractYearsRemaining)
        player.isFranchiseTagged = true
        player.morale = Swift.max(0, player.morale - 10)

        // The restructure receipt is deliberately LEFT ALONE. It describes money
        // the club converted out of the salary it is still paying this year, and
        // this year is unchanged by tagging. `settleFranchiseTags` clears it at
        // the rollover — the same treatment the expiry loop gives a deal that
        // simply runs out, and correct for the same reason: the true-up rebuilds
        // every club's usage from rostered salaries, so an accelerated bonus ages
        // off with the league year that incurred it.
        CommittedCapLedger.commitForward(
            playerID: player.id,
            playerName: player.fullName,
            annualCapHit: Swift.max(0, tagValue),
            years: 1,
            priorYears: priorYears < player.contractYearsRemaining ? priorYears : nil,
            bindingSeason: bindingSeason,
            careerID: careerID
        )
    }

    // MARK: - FA Preview

    struct FAPreviewPlayer {
        let playerID: UUID
        let name: String
        let position: Position
        let overall: Int
        let age: Int
        let estimatedSalary: Int  // thousands
        let currentTeamAbbr: String
    }

    /// Preview the top free agents at a given position from other teams,
    /// so the player can compare during roster evaluation.
    static func previewFreeAgents(
        allPlayers: [Player],
        allTeams: [Team],
        playerTeamID: UUID,
        position: Position,
        salaryCap: Int,
        limit: Int = 5
    ) -> [FAPreviewPlayer] {
        allPlayers
            .filter { $0.teamID != playerTeamID
                  && $0.contractYearsRemaining <= 1
                  && $0.position == position }
            .sorted { $0.overall > $1.overall }
            .prefix(limit)
            .map { player in
                let teamAbbr = allTeams.first { $0.id == player.teamID }?.abbreviation ?? "FA"
                return FAPreviewPlayer(
                    playerID: player.id,
                    name: player.fullName,
                    position: player.position,
                    overall: player.overall,
                    age: player.age,
                    estimatedSalary: estimateMarketValue(player: player, salaryCap: salaryCap),
                    currentTeamAbbr: teamAbbr
                )
            }
    }

    /// Preview free agents for an array of positions (used for position groups).
    static func previewFreeAgentsForGroup(
        allPlayers: [Player],
        allTeams: [Team],
        playerTeamID: UUID,
        positions: [Position],
        salaryCap: Int,
        limit: Int = 5
    ) -> [FAPreviewPlayer] {
        allPlayers
            .filter { $0.teamID != playerTeamID
                  && $0.contractYearsRemaining <= 1
                  && positions.contains($0.position) }
            .sorted { $0.overall > $1.overall }
            .prefix(limit)
            .map { player in
                let teamAbbr = allTeams.first { $0.id == player.teamID }?.abbreviation ?? "FA"
                return FAPreviewPlayer(
                    playerID: player.id,
                    name: player.fullName,
                    position: player.position,
                    overall: player.overall,
                    age: player.age,
                    estimatedSalary: estimateMarketValue(player: player, salaryCap: salaryCap),
                    currentTeamAbbr: teamAbbr
                )
            }
    }

    /// **Rescind the tag — the exact undo of ``applyFranchiseTag``** (#127).
    ///
    /// The old body was not an undo of anything. Applying wrote
    /// `contractYearsRemaining = 1` and `annualSalary = tagValue`; removing wrote
    /// `contractYearsRemaining = 0` and `annualSalary = 0` and refunded the tag
    /// off the club's books — so a user who tagged a man and changed his mind
    /// thirty seconds later was left with a $0 player still sitting on his roster
    /// with no contract years, a state nothing else in the game produces. The
    /// asymmetry only existed because applying destroyed the contract in the
    /// first place.
    ///
    /// Now that applying touches neither the salary nor the cap, this has nothing
    /// to give back except the flag, the morale, the forward commitment — and the
    /// one year of club control the tag floors the contract clock at. The man
    /// goes back to being exactly what he was: a player in the last year of his
    /// deal, who reaches the market at the rollover.
    ///
    /// **The clock is only restored where applying moved it** (F3). `applyFranchiseTag`
    /// does `contractYearsRemaining = max(1, …)`, which is a no-op for the man
    /// the tag screen normally offers (already at 1) and a raise for the man
    /// whose deal has run to 0. The pre-tag value rides on the ledger row, so the
    /// undo can tell the two apart; a missing row (a save whose tag predates the
    /// forward table, or a flag some other engine set) leaves the clock alone,
    /// which is the safe direction — it keeps a rostered man under contract
    /// rather than stranding him at 0.
    ///
    /// R22: rescinding the tag gives back the 10 morale the tag cost.
    static func removeFranchiseTag(player: Player, team: Team?, capMode: CapMode, careerID: UUID) {
        _ = team
        _ = capMode
        guard player.isFranchiseTagged else { return }

        rescindFranchiseTagBooks(player: player, careerID: careerID)
        player.morale = Swift.min(100, player.morale + 10)
    }

    /// Takes a franchise tag off the club's books — the flag, the forward
    /// commitment and the year of control the tag floored the clock at — and
    /// nothing else.
    ///
    /// Shared by the two paths that end a tag, which differ only in what they owe
    /// the player. ``removeFranchiseTag`` hands the 10 morale back because the
    /// club changed its mind; ``applyNegotiatedDeal`` does not, because the man
    /// just signed the long-term deal the tag was standing in for and taking the
    /// tag's morale hit back would pay him twice.
    /// Which save a ledger write belongs to, preferring the id the caller threaded
    /// through.
    ///
    /// The forward table is read everywhere with `career.id`, so a write scoped by
    /// anything else lands in a namespace nobody queries. `Player.careerID` is
    /// optional and is nil often enough (any row a generator minted without
    /// stamping it) that trusting it silently books nothing — the failure this
    /// fallback is only a last resort for. Loud in DEBUG so a call site that
    /// forgot to pass `career.id` is found in the simulator rather than in a save.
    static func resolvedCareerID(_ careerID: UUID?, player: Player) -> UUID? {
        if let careerID { return careerID }
        #if DEBUG
        if player.careerID == nil {
            assertionFailure("Ledger write for \(player.fullName) has no careerID — pass career.id")
        }
        #endif
        return player.careerID
    }

    private static func rescindFranchiseTagBooks(player: Player, careerID: UUID?) {
        let reservation = CommittedCapLedger.forwardCommitment(playerID: player.id, careerID: careerID)
        player.isFranchiseTagged = false
        if let priorYears = reservation?.priorYears {
            player.contractYearsRemaining = priorYears
        }
        CommittedCapLedger.releaseForward(playerID: player.id, careerID: careerID)
    }

    // MARK: - Natural Position Helpers

    /// Derives the natural/primary position from a player's position attributes.
    /// This represents what position group the player was originally built for.
    static func naturalPositionForAttributes(_ attributes: PositionAttributes) -> Position {
        switch attributes {
        case .quarterback(_):     return .QB
        case .runningBack(_):     return .RB
        case .wideReceiver(_):    return .WR
        case .tightEnd(_):        return .TE
        case .offensiveLine(_):   return .LT   // Use LT as the premium OL position
        case .defensiveLine(_):   return .DE   // Use DE as the premium DL position
        case .linebacker(_):      return .OLB  // Use OLB as the premium LB position
        case .defensiveBack(_):   return .CB   // Use CB as the premium DB position
        case .kicking(_):         return .K
        }
    }

    /// The premium position `naturalPositionForAttributes` would return for a
    /// player *built for this position* — i.e. the position group's own top of
    /// the market.
    ///
    /// This is the inverse of the collapse above, and it exists to answer one
    /// question: is a listed position and an attribute-derived natural position
    /// the same BUILD, or two different ones? `.DT` and `.DE` both live in the
    /// `.defensiveLine` group, so a defensive tackle whose attributes come back
    /// `.DE` has not been converted from anything — that is just what the
    /// attribute model calls his group.
    static func attributeGroupPremium(for position: Position) -> Position {
        switch position {
        case .QB:                    return .QB
        case .RB, .FB:               return .RB
        case .WR:                    return .WR
        case .TE:                    return .TE
        case .LT, .LG, .C, .RG, .RT: return .LT
        case .DE, .DT:               return .DE
        case .OLB, .MLB:             return .OLB
        case .CB, .FS, .SS:          return .CB
        case .K, .P:                 return .K
        }
    }

    /// How well a body fits a position's build, in standard deviations of that
    /// position's own physical priors — 0 is the average man at that position,
    /// −1 is a full sigma light for it, averaged over the four discriminating
    /// attributes (stamina and durability are position-independent and carry no
    /// signal).
    ///
    /// The table is `PositionPhysicalProfile`'s, the same priors every generator
    /// draws bodies from, so this asks the question in exactly the units the
    /// bodies were made in and needs no constants of its own.
    static func physicalFitZ(_ physical: PhysicalAttributes, at position: Position) -> Double {
        let p = PositionPhysicalProfile.profile(for: position)
        let terms: [(Double, PositionPhysicalProfile.Prior)] = [
            (Double(physical.speed), p.speed),
            (Double(physical.acceleration), p.acceleration),
            (Double(physical.strength), p.strength),
            (Double(physical.agility), p.agility),
        ]
        let total = terms.reduce(0.0) { $0 + ($1.0 - $1.1.mean) / max(1.0, $1.1.sd) }
        return total / Double(terms.count)
    }

    /// A man is worth one sigma of slack against the build he wants to be PAID
    /// for. Tighter than this and a legitimate 3-4/4-3 conversion loses his edge
    /// money on a rounding error; looser and the clause stops doing any work at
    /// all, because every body in the game is drawn from *some* position's prior
    /// and the priors overlap.
    static let positionSwitchFitFloor = -1.0

    /// Returns the position a player is PAID as.
    ///
    /// **Rewritten in task #87 (F2). This used to be an unconditional upgrade,
    /// and it made a third of the position multiplier vector unreachable.**
    ///
    /// The intent has always been narrow and correct: a man who has been moved
    /// off the position he was built for still commands the market rate of the
    /// position he was built for. "A DE moved to DT still demands DE money."
    ///
    /// The implementation was not narrow at all. `naturalPositionForAttributes`
    /// does not return the position a player was built for — it returns his
    /// attribute GROUP's premium position, because the attribute model has one
    /// `.defensiveLine` shape and not separate DE and DT shapes. Every
    /// generation path in the game (`LeagueGenerator.randomPositionAttributes`,
    /// `DraftClassBuilder`, `TemplateAttributeSolver`) assigns attributes by
    /// group. So `natural` was ALWAYS the group premium, the old
    /// `rank(current) >= rank(natural)` test therefore ALWAYS upgraded, and six
    /// declared multipliers could never be reached by any player the game can
    /// produce: DT was paid DE's rate (+39 %), RT and IOL were paid LT's
    /// (+24 % / +62 %), MLB was paid OLB's (+25 %), the safeties were paid CB's
    /// (+27 %) and a fullback was paid a running back's (+80 %).
    ///
    /// Two conditions now gate the upgrade, and both are the question the intent
    /// was always asking:
    ///
    /// 1. **A real position change.** His listed position must belong to a
    ///    DIFFERENT attribute group than his attributes do
    ///    (`attributeGroupPremium(for: current) != natural`). A defensive end
    ///    listed at outside linebacker qualifies; a defensive tackle listed at
    ///    defensive tackle does not, and neither does a right guard, a middle
    ///    linebacker, a strong safety or a fullback.
    /// 2. **Attributes that actually support the switch.** His body must fit the
    ///    position he wants to be paid for to within ``positionSwitchFitFloor``
    ///    sigma of that position's own priors. This is what stops the group
    ///    premium being claimed by the group's non-premium build: a nose tackle
    ///    playing outside linebacker has `.defensiveLine` attributes and so
    ///    reads `natural == .DE`, but he is two sigma short of an edge rusher's
    ///    speed and does not get an edge rusher's money.
    ///
    /// Failing either test, a player is paid at the position he plays — which is
    /// the job he does, and which is what makes the six multipliers above real
    /// numbers instead of dead ones.
    static func bestPayingPosition(
        current: Position, natural: Position, physical: PhysicalAttributes
    ) -> Position {
        // Same build, differently listed — no premium, he is what he plays.
        guard attributeGroupPremium(for: current) != natural else { return current }
        // A change that costs him money is not a claim he would make.
        guard positionMultiplier(natural) > positionMultiplier(current) else { return current }
        // ...and the body has to back the claim up.
        guard physicalFitZ(physical, at: natural) >= positionSwitchFitFloor else { return current }
        return natural
    }

    // MARK: - Incentive Valuation (TODO §5.5)

    /// **Cap treatment, in one paragraph.** An incentive counts against the cap
    /// **when it is earned, at season end** — not when it is written, and never
    /// prorated. Real NFL accounting splits clauses into "likely to be earned"
    /// (charged up front, trued up the next league year) and "not likely to be
    /// earned" (charged only if hit); modelling both would need a second set of
    /// carry-forward columns on every team row to hold the true-up, for a
    /// distinction the player never sees. So every clause here behaves like an
    /// NLTBE clause: free until hit, then a one-time charge in the year it is
    /// hit. `suggestedIncentives` keeps the whole package inside
    /// ``incentivePackageCapFraction`` of the annual salary precisely so that
    /// "free until hit" cannot become a cap loophole worth exploiting.
    ///
    /// The charge itself is one line at rollover — see ``evaluateIncentives``.

    /// Ceiling on a whole package, as a fraction of the deal's annual salary.
    /// 15 % is the line above which incentives stop being a bridge across a
    /// negotiation gap and start being a way to sign a player the cap says you
    /// cannot afford.
    static let incentivePackageCapFraction = 0.15

    /// The tier a player of this rating is expected to be *arguing about* —
    /// reachable in a good season, missed in an ordinary one.
    ///
    /// Anchored at **OVR 74**, the starter line `marketBasePercent` already uses,
    /// with a per-point slope so the bar tracks the player rather than the
    /// position average. Because the bar is derived from his own rating, a
    /// clause left at par is roughly a coin flip for everybody; the negotiation
    /// dial is what moves it (see ``incentiveLikelihood``).
    static func parThreshold(for category: IncentiveCategory, overall: Int) -> Double {
        // Clamped so a 45-OVR camp body and a 99 do not produce absurd bars.
        let d = Double(max(-20, min(25, overall - 74)))

        func rounded(_ value: Double, to step: Double, floor: Double) -> Double {
            let clamped = Swift.max(floor, value)
            return (clamped / step).rounded() * step
        }

        switch category {
        case .gamesPlayed:
            // Availability, not production: 14 of 17 is the bar real deals use.
            return 14
        case .passYards:     return rounded(3_600 + 70 * d, to: 50, floor: 2_200)
        case .passTDs:       return rounded(24 + 0.7 * d, to: 1, floor: 14)
        case .rushYards:     return rounded(900 + 35 * d, to: 50, floor: 500)
        case .rushTDs:       return rounded(7 + 0.25 * d, to: 1, floor: 4)
        case .receptions:    return rounded(60 + 2.0 * d, to: 1, floor: 30)
        case .recYards:      return rounded(800 + 32 * d, to: 50, floor: 400)
        case .recTDs:        return rounded(5 + 0.3 * d, to: 1, floor: 3)
        case .tackles:       return rounded(75 + 2.2 * d, to: 5, floor: 40)
        case .sacks:         return rounded(6 + 0.45 * d, to: 0.5, floor: 3)
        case .interceptions: return rounded(2 + 0.15 * d, to: 1, floor: 1)
        case .fieldGoals:    return rounded(24 + 0.5 * d, to: 1, floor: 15)
        case .playoffBerth:  return 1
        }
    }

    /// Share of the annual salary one clause is worth at par.
    private static func incentiveWeight(_ category: IncentiveCategory) -> Double {
        switch category {
        case .gamesPlayed:  return 0.040   // availability money is cheap money
        case .playoffBerth: return 0.030   // team outcome, not his to control
        default:            return 0.055   // a production tier is the real prize
        }
    }

    /// A ready-made package to open the incentive conversation with: the top
    /// clauses from the player's position menu, each set at par and priced off
    /// the deal on the table, scaled down together if the total would break
    /// ``incentivePackageCapFraction``.
    static func suggestedIncentives(
        player: Player,
        annualSalaryK: Int,
        limit: Int = 3
    ) -> [ContractIncentive] {
        guard annualSalaryK > 0, limit > 0 else { return [] }
        let menu = IncentiveCategory.menu(for: player.position).prefix(limit)

        let raw: [ContractIncentive] = menu.map { category in
            let bonus = Double(annualSalaryK) * incentiveWeight(category)
            return ContractIncentive(
                category: category,
                threshold: parThreshold(for: category, overall: player.overall),
                bonusK: roundBonus(bonus)
            )
        }

        let ceiling = Int(Double(annualSalaryK) * incentivePackageCapFraction)
        let total = raw.reduce(0) { $0 + $1.bonusK }
        guard total > ceiling, total > 0 else { return raw }

        let scale = Double(ceiling) / Double(total)
        return raw.map {
            ContractIncentive(
                category: $0.category,
                threshold: $0.threshold,
                bonusK: roundBonus(Double($0.bonusK) * scale)
            )
        }
    }

    /// Bonus figures round to $50K and never fall under $100K — below that a
    /// clause is not worth the row it occupies in the offer sheet.
    private static func roundBonus(_ thousands: Double) -> Int {
        Swift.max(100, Int((thousands / 50).rounded()) * 50)
    }

    /// Probability the player clears this clause in a given season.
    ///
    /// A clause left at par is a coin flip by construction, so the number that
    /// actually moves is the GM's: dropping the bar below par makes the money
    /// close to guaranteed (and the agent values it as such), raising it turns
    /// the clause into a lottery ticket the agent all but ignores.
    static func incentiveLikelihood(_ incentive: ContractIncentive, player: Player) -> Double {
        let par = parThreshold(for: incentive.category, overall: player.overall)

        switch incentive.category {
        case .playoffBerth:
            // 12 clubs of 32 make the field; no dial to turn.
            return 0.38
        case .gamesPlayed:
            let durability = Double(player.physical.durability)
            var p = 0.55 + 0.003 * (durability - 70)
            p += 0.045 * (par - incentive.threshold)     // per game off the bar
            return clampProbability(p)
        default:
            guard par > 0 else { return 0 }
            let ratio = incentive.threshold / par
            var p = 0.45 + 0.55 * (1.0 - ratio)
            // Past his peak window the bar set off today's rating gets harder
            // every year — the same decline curve the market value already prices.
            let peak = player.position.peakAgeRange
            if player.age > peak.upperBound {
                p -= 0.03 * Double(player.age - peak.upperBound)
            }
            return clampProbability(p)
        }
    }

    private static func clampProbability(_ p: Double) -> Double {
        Swift.min(0.95, Swift.max(0.05, p))
    }

    /// Expected payout of a package for ONE season, in thousands.
    static func expectedSeasonIncentiveValue(
        _ incentives: [ContractIncentive],
        player: Player
    ) -> Int {
        Int(incentives.reduce(0.0) { total, incentive in
            total + incentiveLikelihood(incentive, player: player) * Double(incentive.bonusK)
        }.rounded())
    }

    /// How much of a clause's expected value an agent will actually count
    /// against the guaranteed ask.
    ///
    /// This is the persona's whole position on incentives. A hardliner is not
    /// being irrational at 0.35 — he is doing his job: a clause is money his
    /// client can be injured out of, benched out of, or schemed out of, and it
    /// pays nothing if the team collapses. A deal-maker takes it near face
    /// value because it closes deals. A loyalist sits between the two, trusting
    /// the building more than the paper.
    static func personaIncentiveCredit(_ persona: AgentPersona) -> Double {
        switch persona {
        case .hardliner:   return 0.35
        case .cooperative: return 0.85
        case .loyalist:    return 0.65
        }
    }

    /// What the agent adds to an offer's total for its incentives, across the
    /// whole contract — clauses reset every season, so the credit scales with
    /// the number of years on the deal.
    static func creditedIncentiveValue(
        _ incentives: [ContractIncentive],
        player: Player,
        persona: AgentPersona,
        years: Int
    ) -> Int {
        guard !incentives.isEmpty, years > 0 else { return 0 }
        let perSeason = Double(expectedSeasonIncentiveValue(incentives, player: player))
        return Int((perSeason * personaIncentiveCredit(persona) * Double(years)).rounded())
    }

    /// Maximum a package can pay in one season if every clause hits.
    static func maxSeasonIncentiveValue(_ incentives: [ContractIncentive]) -> Int {
        incentives.reduce(0) { $0 + $1.bonusK }
    }

    // MARK: - Incentive Progress & Settlement

    /// Result of grading one player's clauses against one season.
    struct IncentiveSettlement {
        let playerID: UUID
        let earned: [ContractIncentive]
        let missed: [ContractIncentive]

        /// Cap charge the club takes for this season, in thousands.
        var payoutK: Int { earned.reduce(0) { $0 + $1.bonusK } }

        /// True when the player carried no clauses at all — the common case,
        /// and the one the rollover path should skip in a single branch.
        var isEmpty: Bool { earned.isEmpty && missed.isEmpty }
    }

    /// Grades the season that just finished against the player's clauses.
    ///
    /// Pure: it reads the package and the history row and returns a verdict,
    /// mutating neither. Postseason participation is the playoff-berth test —
    /// `PlayerSeasonHistory.postGamesPlayed` is credited for every available
    /// player on a club that played a playoff game, which is exactly the fact
    /// the clause is written about.
    ///
    /// **WIRED — the rollover call.** `FreeAgencyEngine.executeNewLeagueYear`
    /// grades every live package through
    /// `evaluateSeasonIncentives(allPlayers:career:modelContext:)` at the top of
    /// the rollover (before the expiry loop empties `teamID`), and charges the
    /// earned total to each club right after the league-year cap true-up
    /// rebuilds `currentCapUsage` — earned = charged, once, and it ages off with
    /// the league year exactly like the dead money beside it.
    ///
    /// Nothing else has to change: the clauses stay on the deal for next season,
    /// and `ContractIncentiveRegistry.clear(for:)` is the call when the contract
    /// actually expires or the player is released.
    static func evaluateIncentives(player: Player, history: PlayerSeasonHistory) -> IncentiveSettlement {
        // A man nobody employs at season end collects nothing, whatever is still
        // written in his old package. This is also the safety net for the one
        // lifecycle hole below: a release does not currently clear the registry,
        // and without this an old clause could bill a club that cut him in
        // October. HANDOFF: the release and contract-expiry paths should call
        // `ContractIncentiveRegistry.clear(for:)` so the stale rows go away too.
        guard player.teamID != nil else {
            return IncentiveSettlement(playerID: player.id, earned: [], missed: [])
        }

        let progress = incentiveProgress(
            ContractIncentiveRegistry.incentives(for: player),
            line: history.statLine,
            gamesPlayed: history.gamesPlayed,
            reachedPlayoffs: history.postGamesPlayed > 0
        )
        return IncentiveSettlement(
            playerID: player.id,
            earned: progress.filter { $0.isEarned }.map(\.incentive),
            missed: progress.filter { !$0.isEarned }.map(\.incentive)
        )
    }

    /// Live, mid-season progress against the clauses the player is carrying —
    /// what the contract card renders. The playoff clause cannot be graded
    /// before the bracket exists, so it reads as "not yet" until the caller
    /// knows otherwise.
    static func liveIncentiveProgress(
        for player: Player,
        reachedPlayoffs: Bool = false
    ) -> [IncentiveProgress] {
        incentiveProgress(
            ContractIncentiveRegistry.incentives(for: player),
            line: player.seasonStatLine,
            gamesPlayed: player.gamesPlayedThisSeason,
            reachedPlayoffs: reachedPlayoffs
        )
    }

    /// Shared grader. Clauses whose category is not on the player's current
    /// position menu are still graded — a player who changed position keeps the
    /// deal he signed.
    static func incentiveProgress(
        _ incentives: [ContractIncentive],
        line: SeasonStatLine,
        gamesPlayed: Int,
        reachedPlayoffs: Bool
    ) -> [IncentiveProgress] {
        incentives.map { incentive in
            IncentiveProgress(
                incentive: incentive,
                achieved: incentive.category.achieved(
                    line: line,
                    gamesPlayed: gamesPlayed,
                    reachedPlayoffs: reachedPlayoffs
                )
            )
        }
    }
}
