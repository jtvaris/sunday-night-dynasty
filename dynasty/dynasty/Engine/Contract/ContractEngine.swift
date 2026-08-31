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

    /// **A club's cap `seasonsAhead` league years from now — the league's ONE
    /// projection.**
    ///
    /// `Int(cap × (1 + capGrowthPerSeason)^n)` was hand-inlined in six places:
    /// the cap-outlook grid, the contract timeline, the dashboard's three-year
    /// tile, the tag screen, the roster evaluator and the negotiation composer.
    /// Six copies of one formula is six futures the moment one of them is
    /// edited, and #186 needed a seventh — inside the engine, where the cap gate
    /// now lives — which is the point at which a copy stops being tolerable.
    ///
    /// `seasonsAhead <= 0` returns the cap unchanged, so a caller does not have
    /// to branch on "is this year".
    static func projectedCap(_ salaryCap: Int, seasonsAhead: Int) -> Int {
        guard seasonsAhead > 0 else { return salaryCap }
        return Int(Double(salaryCap) * pow(1.0 + capGrowthPerSeason, Double(seasonsAhead)))
    }

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

    /// The quarterback scarcity floor — what a LEGITIMATE STARTER costs, over
    /// and above what the shared ladder charges for his rating (task #163).
    ///
    /// `marketBasePercent` is one table for twenty positions and it is convex by
    /// construction: the last five rating points cost more than the previous
    /// five, everywhere, for everyone. That is the right shape for the positions
    /// a club can replace. It is the wrong shape for the one it cannot.
    ///
    /// **What the real market pays.** Against the 2025 cap (~$279M) the men who
    /// hold the job are bunched at the top and the ladder between them is nearly
    /// flat: Prescott 21.5 %, Allen / Burrow / Love / Lawrence 19.7 %, Tagovailoa
    /// 19.0 %, Goff 19.0 %, Herbert 18.8 %, Hurts 18.3 %, Watson 16.5 %, Cousins
    /// 16.1 % — and then a cliff down to the bridge tier (Carr 13.4 %, Darnold
    /// 12.0 %, Mayfield 11.9 %). A proven starter who is plainly not the best
    /// quarterback alive still signs for ~$50-53M, because the club that lets him
    /// go is not choosing between him and a better one; it is choosing between
    /// him and not having one. That premium is paid for the SCARCITY of the job
    /// being filled at all, so it does NOT scale with quality the way every other
    /// position's pay does.
    ///
    /// **What the ladder charged.** At × 2.2 × `leagueAffordabilityScale` the
    /// shared curve read 85 → 10.9 %, 87 → 12.1 %, 89 → 14.5 %, 91 → 16.9 %,
    /// 92 → 18.1 % of cap. The 92+ tail was calibrated in task #82 and is right.
    /// The 85-91 band — an unambiguous franchise starter, the tier the list above
    /// is made of — sat ~25 % under its comps: an 89 asked $38.4M against a real
    /// $50-53M.
    ///
    /// **The shape.** This replaces the shared curve's 85→92 stretch with an S: a
    /// `blend` fraction of the way from the standard 85 price to the standard 92
    /// price. Both endpoints are READ from `marketBasePercent`, so the shoulder
    /// cannot drift from the table it hangs off, and neither endpoint moves —
    /// nothing below 85 and nothing at or above 92 changes, at quarterback or
    /// anywhere else. It is applied as a `max` floor in `estimateMarketValue`, so
    /// it can only ever RAISE a price: the ladder stays strictly monotone and an
    /// 89 ($45.0M) still cannot out-earn a 92 ($47.9M).
    ///
    /// **What it costs, and why that is forced.** The shoulder is CONCAVE, which
    /// the rest of the ladder is not. That is arithmetic, not sloppiness. With
    /// the 85 and 92 prices pinned, the highest an 89 can sit while the curve
    /// through them stays convex is the straight chord, (3·p85 + 4·p92)/7 = 9.089
    /// → **15.0 % of cap** ($39.7M) — barely half a point above what the convex
    /// table already charged. Every point above that has to be bought with
    /// concavity; buying it convexly instead means dragging 92 to ~21.6 % and 96
    /// to ~27.7 % ($73M), i.e. re-pricing the tail #82 calibrated and putting the
    /// top of this market above the top of the real one. The concavity is not a
    /// defect in the fit — it IS the fact being encoded: quarterback pay
    /// saturates, because past "he is a franchise quarterback" there is very
    /// little left to buy.
    ///
    /// At `openingSalaryCap` ($265M) the quarterback ladder now reads
    /// 85 $28.9M · 86 $31.7M · 87 $36.9M · 88 $42.2M · 89 $45.0M · 90 $46.7M ·
    /// 91 $47.5M · 92 $47.9M · 96 $60.8M. The inflection sits at 87-88, which is
    /// where the shared table's own comment puts "the second contract that resets
    /// a market" — the rating at which a club stops asking whether he is the
    /// answer.
    ///
    /// Returns 0 outside the shoulder, which is what makes `max` a no-op there.
    private static func quarterbackScarcityFloor(overall: Int) -> Double {
        // Fraction of the way from the standard 85 price to the standard 92
        // price, indexed by OVR 85...92. STRICTLY INCREASING (the ladder stays
        // monotone) and pinned at 0.00 / 1.00 (the endpoints do not move).
        //
        // The S is deliberate: convex to the inflection at 87-88 — the club is
        // still buying quality, and each point costs more than the last — then
        // concave above it, where it is buying a filled job and the remaining
        // rating points are nearly free. Any edit MUST keep the sequence
        // increasing and the endpoints at 0 and 1.
        let blend: [Double] = [
            0.00,  // 85 — the shared ladder's own price, untouched
            0.15,  // 86
            0.42,  // 87 — "top ~4 %", where the shared table says a market resets
            0.70,  // 88
            0.85,  // 89 — 17.0 % of cap, the tier the recalibration was aimed at
            0.94,  // 90
            0.98,  // 91
            1.00,  // 92 — the #82 tail's own price, untouched
        ]
        let band = 85...92
        guard band.contains(overall) else { return 0 }
        let low = marketBasePercent(overall: band.lowerBound)
        let high = marketBasePercent(overall: band.upperBound)
        return low + (high - low) * blend[overall - band.lowerBound]
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
        case .K, .P, .LS, .H:
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
        // The shared ladder's price for the rating, then the quarterback-only
        // scarcity shoulder over OVR 85-92 (task #163). `max` keeps it a FLOOR:
        // it can raise a quarterback's price inside the band and can do nothing
        // at all anywhere else, so no other position moves by a cent.
        var basePercent = marketBasePercent(overall: overall)
        if position == .QB {
            basePercent = Swift.max(basePercent, quarterbackScarcityFloor(overall: overall))
        }

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

    /// **The schedule a negotiated deal is actually written with** (#186).
    ///
    /// One function, because two things have to agree exactly or the gate is a
    /// liar: ``applyNegotiatedDeal``, which persists the schedule onto the
    /// `Contract` row, and `DealTargetYear.plan`, which reads year one off it to
    /// decide whether the deal can be tabled at all. They call this; neither
    /// builds a schedule of its own.
    ///
    /// **Neither shape is renormalised, so the schedule does NOT sum to
    /// `annualSalary × years`** — measured: a 2-year veteran deal pays 10.4 %
    /// over the negotiated total (1.15 + 1.15 × 0.92 = 2.208×), a 1-year 15 %
    /// over, a 6-year veteran deal 5.7 % under, and a 2-year deal for an
    /// under-28 12 % under. A caller must therefore price a deal off the
    /// schedule this returns; a flat "salary + bonus ÷ years" quoted as the cap
    /// hit is a different number from the one that gets booked.
    ///
    /// - Parameter firstYearCeiling: the most year one may cost in BASE salary.
    ///   Only the tag-and-extend passes one — see ``cappedFirstYear(_:ceiling:)``.
    static func negotiatedBaseSalaries(
        annualSalary: Int,
        years: Int,
        age: Int,
        firstYearCeiling: Int? = nil
    ) -> [Int] {
        let schedule = age < 28
            ? escalatingBaseSalaries(annualSalary: annualSalary, years: years)
            : frontLoadedBaseSalaries(annualSalary: annualSalary, years: years)
        guard let ceiling = firstYearCeiling else { return schedule }
        return cappedFirstYear(schedule, ceiling: ceiling)
    }

    /// Pushes whatever year one costs above `ceiling` into the later years,
    /// **preserving the schedule's total to the thousand**.
    ///
    /// This is how a real tag-and-extend is written. The club retires a franchise
    /// tag in order to get under it; a first year that costs MORE than the tag it
    /// replaced turns the mechanism upside down and no front office signs one.
    /// The excess is redistributed across the remaining years in proportion to
    /// what each already carried, so the shape of the deal survives and the money
    /// is deferred rather than forgiven — the player is owed every thousand he
    /// negotiated.
    ///
    /// The last year absorbs the rounding remainder, which is what makes the sum
    /// exact rather than approximately exact.
    ///
    /// A one-year deal has nowhere to push to and is returned untouched: there is
    /// no such thing as deferring money inside a single league year, and silently
    /// cutting the man's pay to fit a ceiling would be a worse answer than letting
    /// the gate refuse the deal.
    static func cappedFirstYear(_ schedule: [Int], ceiling: Int) -> [Int] {
        guard schedule.count > 1, let first = schedule.first else { return schedule }
        let target = Swift.max(minimumBaseSalary, ceiling)
        guard first > target else { return schedule }

        let laterTotal = schedule.dropFirst().reduce(0, +)
        guard laterTotal > 0 else { return schedule }

        let excess = first - target
        var out = schedule
        out[0] = target
        var distributed = 0
        for index in 1..<out.count {
            let share = index == out.count - 1
                ? excess - distributed
                : Int((Double(excess) * Double(schedule[index]) / Double(laterTotal)).rounded())
            out[index] += share
            distributed += share
        }
        return out
    }

    /// The floor both structure generators clamp a base salary to. Named here
    /// so ``cappedFirstYear(_:ceiling:)`` cannot drift from them.
    static let minimumBaseSalary = 500

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
    ///
    /// The league-neutral shape. Real clubs are not neutral about this — see
    /// ``clubGuaranteeLean(forTeam:)``, which is what the AI market applies on
    /// top of it, and ``guaranteeLeverage(_:)`` for the position half.
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

    // MARK: - Contract Structure: guarantees and term (F-61)
    //
    // ## What this section is
    //
    // A contract had exactly one negotiable dimension — the annual number.
    // `Contract.guaranteedMoney` was stored and displayed and read by nothing;
    // term was a club VETO (`ContractNegotiationEngine.maxContractYears`) rather
    // than a lever, so no GM ever bought a year to lower a cap hit and no agent
    // ever sold one. This section is the price list for the other two
    // dimensions, in one place, so the negotiation screen, the agent's grading
    // and the AI market cannot quote three different exchange rates.
    //
    // ## The one model everything below is derived from
    //
    // A dollar that is guaranteed is worth more than a dollar that is not,
    // because the second one only arrives if the club still wants him. Write the
    // survival probability of at-risk money as `s`; a deal with guarantee share
    // `g` is worth `g + (1 − g)·s` of its face value.
    //
    // `s ≈ 0.65`. Veteran multi-year deals are terminated early more often than
    // they are played out — in the NFL the median veteran contract ends about a
    // year short, and this league's own churn instrument (`ChurnDiag`) puts a
    // comparable share of signings back on the market before their term is up.
    // So `EV(g) = 0.65 + 0.35·g`, and `dEV/dg = 0.0035` **per point of
    // guarantee share**: that is the risk-neutral price of a guarantee, and
    // every constant below is a deliberate deviation from it.

    /// **What the GM gets back for guaranteeing MORE than the agent asked**, as
    /// a fraction of annual salary per point of guarantee share.
    ///
    /// 0.25 %/pt against the risk-neutral 0.35 %/pt derived above. Deliberately
    /// UNDER it: an agent does not sell his client's insurance at cost. The gap
    /// is what stops the lever being an exploit — the user can genuinely buy his
    /// cap number down with guarantees, and he pays a spread to do it.
    ///
    /// Trades against: raise it and guarantees become the cheapest way to sign
    /// anybody, which is the free lunch the ruling forbids; lower it and the
    /// lever stops being worth pulling, which is the state this replaces.
    static let guaranteeCreditPerPoint = 0.0025

    /// **What the GM pays for guaranteeing LESS than the agent asked**, same
    /// units.
    ///
    /// 0.40 %/pt, ABOVE the risk-neutral rate for the mirror reason: the agent
    /// is being asked to move risk onto his client and prices it as a seller,
    /// not as an actuary. The same asymmetry `GMAdjustment.bounds` documents —
    /// being good is worth less than being bad costs.
    ///
    /// The 0.25/0.40 spread is also the anti-round-trip property: strip twenty
    /// points of guarantee and put them back and the GM is 3 % of APY worse off
    /// than if he had never touched it. There is no free probe.
    ///
    /// This replaces a binary `guaranteeGap > 15 ? 0.96 : 1.0` step, which was
    /// the only guarantee arithmetic in the game: it charged a flat 4 % for any
    /// shortfall past fifteen points (so the sixteenth point and the sixtieth
    /// cost the same) and paid NOTHING for a guarantee above the ask, which is
    /// the direction a club actually uses.
    static let guaranteeChargePerPoint = 0.0040

    /// Ceiling on the whole guarantee term, either way, as a fraction of APY.
    ///
    /// 10 %. The bound is set by what else is already moving the number: the
    /// situation multiplier spans 0.72…1.50 and the GM-standing term −8/+15 %.
    /// A STRUCTURAL lever has to be smaller than the man and smaller than the
    /// front office, or the negotiation stops being about who he is. Ten per
    /// cent is roughly one tier-step of ``marketBasePercent`` — enough to close
    /// a real gap, never enough to buy a star at a role player's price.
    ///
    /// At the base rates this binds at 40 points of guarantee given (credit) or
    /// 25 points withheld (charge), before the position scalar.
    static let guaranteeSwingCap = 0.10

    /// **How hard THIS man bargains over guarantees**, as a scalar on both rates.
    ///
    /// Leverage and risk are two different things and this is the risk half. A
    /// player who expects to be cut values insurance more and will trade more
    /// annual salary for it; a player nobody releases for cap reasons barely
    /// prices it at all. Anchored on real cut exposure and career length rather
    /// than on money: running backs are released in their fourth year as a
    /// matter of routine, and quarterbacks are not released at all.
    ///
    /// Note this runs the OPPOSITE way to ``guaranteeLeverage(_:)``, and that is
    /// the point of having both. The quarterback gets the biggest guarantee in
    /// the league because he can demand it, and trades it away most cheaply
    /// because he needs it least. The back gets the smallest and defends it
    /// hardest. Collapse the two into one number and the market loses the thing
    /// that makes structure worth arguing about.
    static func guaranteeSensitivity(_ position: Position) -> Double {
        switch position {
        case .QB:                        return 0.75
        case .LT:                        return 0.90
        case .WR, .CB, .DE, .DT, .RT,
             .LG, .RG, .C:               return 1.00
        case .MLB, .OLB, .FS, .SS, .TE,
             .K, .P, .LS, .H:            return 1.15
        case .RB, .FB:                   return 1.35
        }
    }

    /// **What the market GRANTS this position at signing**, as a scalar on the
    /// guarantee share an agent opens by asking for.
    ///
    /// Real anchor, expressed the way clubs actually think about it — how many
    /// years of a deal are locked at signature:
    ///
    /// | tier | practical guaranteed years | share of a 4-year deal | scalar |
    /// |---|---|---|---|
    /// | franchise QB | ~3 | ~0.75 | 1.35 |
    /// | premium edge / LT / WR / CB | ~2 | ~0.50 | 1.10 |
    /// | the middle of the roster | ~1.5 | ~0.40 | 1.00 |
    /// | back / specialist | ~1 | ~0.25 | 0.70 |
    ///
    /// The scalars are those shares normalised on the middle rung, which is
    /// where ``ContractNegotiationEngine``'s overall-tier band was already
    /// calibrated — so this re-shapes the league's guarantee structure by
    /// position without moving its average.
    ///
    /// It is deliberately NOT ``positionMultiplier``: that ladder prices how
    /// much a man is paid, this one prices how much of it he is promised, and
    /// the two disagree most exactly where the real market is most interesting
    /// (a top guard is paid like a safety and guaranteed like one; a back is
    /// paid better than a safety and guaranteed far worse).
    static func guaranteeLeverage(_ position: Position) -> Double {
        switch position {
        case .QB:                        return 1.35
        case .DE, .LT, .WR, .CB:         return 1.10
        case .DT, .OLB, .MLB, .TE,
             .FS, .SS, .RT, .LG, .RG, .C: return 1.00
        case .RB, .FB, .K, .P, .LS, .H:  return 0.70
        }
    }

    /// **What an offer is WORTH per year given how much of it is guaranteed**,
    /// as a multiplier on the annual cap hit.
    ///
    /// The single conversion both sides of every negotiation read. Above 1.0 the
    /// GM guaranteed more than was asked and the agent will take less per year
    /// for it; below 1.0 he guaranteed less and the ask goes up.
    ///
    /// - Parameters:
    ///   - offered: guarantee share of the GM's offer, 0…100.
    ///   - asked: the share the agent's standing demand carries.
    static func guaranteeValueMultiplier(offered: Int, asked: Int, position: Position) -> Double {
        let gap = Double(offered - asked)
        guard gap != 0 else { return 1.0 }
        let sensitivity = guaranteeSensitivity(position)
        let rate = gap > 0 ? guaranteeCreditPerPoint : guaranteeChargePerPoint
        let raw = gap * rate * sensitivity
        return 1.0 + Swift.min(guaranteeSwingCap, Swift.max(-guaranteeSwingCap, raw))
    }

    /// **What one extra year of term is worth to the club**, as a fraction of
    /// annual salary.
    ///
    /// This is ``capGrowthPerSeason`` and it is not a coincidence: the cap grows
    /// 5-8 % a year, so a deal written at a FLAT annual number sheds that much
    /// of its cap-relative value every season it runs. A player who signs one
    /// more year at the same money hands the club exactly one year of cap
    /// growth, and that transfer is the entire reason real clubs buy term.
    /// Pricing it at anything else would either give the years away or make them
    /// unbuyable.
    static let termValuePerYear = capGrowthPerSeason

    /// **What one year SHORT of the agent's ask costs the club**, same units.
    ///
    /// 9 % — the 6.5 % of cap growth the player is giving up, plus ~2.5 points
    /// for the fact that a short deal is his bet and not the club's. A man told
    /// "we want to take a look at you first" is carrying the injury year
    /// himself, and he charges for it.
    ///
    /// Rejected: a symmetric 6.5 %. It made the prove-it deal free for the club
    /// — offer one year, pay one year's discount, re-sign at leisure — which is
    /// the exact mechanic ``ContractNegotiationEngine/provenBetPremium`` exists
    /// to protect, and it made shortening a deal the dominant move for every
    /// club with a cap problem.
    ///
    /// It does NOT apply to a prove-it client, who is buying the short term
    /// rather than suffering it (`proveItShortDealCredit` already pays him for
    /// it, and charging here as well would price the same year twice in opposite
    /// directions).
    static let termShortPremiumPerYear = 0.09

    /// Ceiling on the whole term adjustment, either way, as a fraction of APY.
    ///
    /// 13 % — two years of ``termValuePerYear``. Past two years beyond what he
    /// asked for, an agent stops trading: a man does not sell his thirties by
    /// the yard, and the age ceiling
    /// (`ContractNegotiationEngine.maxContractYears`) is a separate and harder
    /// veto that this must never look like a way around.
    static let termSwingCap = 0.13

    /// **What an offer is WORTH per year given its length**, as a multiplier on
    /// the annual cap hit.
    ///
    /// Above 1.0 the GM offered more years than the agent asked for — more total
    /// money and more security, so the agent will take less per year. Below 1.0
    /// he offered fewer.
    ///
    /// Note the mechanical half of the term lever is already in
    /// `NegotiationOffer.annualCapHit`: a longer deal prorates the signing bonus
    /// over more years and lowers the cap number by itself. This is the
    /// BEHAVIOURAL half — what the man on the other side of the table thinks
    /// about it — and the two compound, which is why real clubs lengthen deals.
    static func termValueMultiplier(offerYears: Int, askYears: Int, isProveIt: Bool) -> Double {
        let delta = Double(offerYears - askYears)
        guard delta != 0 else { return 1.0 }
        if delta < 0 {
            guard !isProveIt else { return 1.0 }
            let raw = delta * termShortPremiumPerYear
            return 1.0 + Swift.max(-termSwingCap, raw)
        }
        return 1.0 + Swift.min(termSwingCap, delta * termValuePerYear)
    }

    // MARK: - The clubs' own taste in structure (F-61 × D3)

    /// **How much of a deal THIS front office writes down**, as a scalar on the
    /// guarantee it would otherwise have offered.
    ///
    /// The house pattern is `FreeAgencyEngine.capReserve(forTeam:)`: one taste,
    /// four archetypes, keyed on `Team.id` through
    /// `TradeValueEngine.GMPersona.forTeam(id:)` so a franchise's GM behaves the
    /// same way in every session without a stored field.
    ///
    /// * **aggressive 1.30** — over-guarantees, and this is the whole point of
    ///   him. D3's refinement asks for franchise-altering blunders in the tail
    ///   rather than a wider Gaussian everywhere; too much guaranteed money on
    ///   the wrong man is the blunder real clubs actually make, and now that
    ///   `Contract.deadCap` charges guarantees and `CapManagementEngine`
    ///   carries the charge into next year, he can finally make it.
    /// * **analytics 0.72** — refuses guarantees on principle, which is why he
    ///   is the club that can absorb a deadline salary in November.
    /// * **oldSchool 1.05** — believes in rewarding his own men.
    /// * **balanced 1.00** — the control group.
    ///
    /// **The league average is deliberately left alone.** Weighted by the
    /// archetype frequencies in `GMPersona.forTeam` (oldSchool 26 %, balanced
    /// 34 %, analytics 20 %, aggressive 20 %) the mean is **1.017** — 1.7 % above
    /// neutral. What this changes is the SPREAD, not the level: the aggressive
    /// GM's mistakes cost 30 % more to escape and the analytics GM's cost 28 %
    /// less, while the league-wide dead-money bill D2 is measuring stays where
    /// the lead calibrated it. Raise the level here and you are retuning
    /// somebody else's ledger by accident.
    static func clubGuaranteeLean(forTeam teamID: UUID) -> Double {
        switch TradeValueEngine.GMPersona.forTeam(id: teamID).archetype {
        case .aggressive: return 1.30
        case .oldSchool:  return 1.05
        case .balanced:   return 1.00
        case .analytics:  return 0.72
        }
    }

    /// **How many extra years THIS front office buys**, as a delta on the term
    /// it would otherwise agree to.
    ///
    /// The mirror of ``clubGuaranteeLean(forTeam:)`` and the same four
    /// archetypes read the same way. The analytics GM buys term because
    /// ``termValuePerYear`` says a year is worth 6.5 % of the annual number and
    /// he is the one who has done that arithmetic; the aggressive GM shortens
    /// deals because he is paying for now and expects to be right about the man.
    ///
    /// **Not yet wired.** The AI free-agent market settles term at
    /// `FreeAgencyEngine.contractYearsCeiling` / `agreedYears`, in a file this
    /// wave does not own. The function ships with its derivation so the term
    /// half can be turned on in one line at that seam without re-deriving
    /// anything; the age ceiling must still bind after it, since a taste is not
    /// a licence to sign a 35-year-old for four years.
    static func clubTermLean(forTeam teamID: UUID) -> Int {
        switch TradeValueEngine.GMPersona.forTeam(id: teamID).archetype {
        case .analytics:  return 1
        case .oldSchool:  return 0
        case .balanced:   return 0
        case .aggressive: return -1
        }
    }

    /// **Dead money for a man with no detailed `Contract` row** — every player
    /// an AI club has ever signed.
    ///
    /// The AI free-agent market writes `Player.annualSalary` and
    /// `contractYearsRemaining` and nothing else (`ContractEngine.signPlayer` →
    /// `signPlayerSimple`); only the user's signings and negotiated deals get a
    /// `Contract` row. So the guarantee model above would have described the
    /// user's league and nobody else's, which is exactly the one-directional
    /// asymmetry the fix queue keeps finding.
    ///
    /// `RosterCutEvaluator.deadCap` was a flat **15 % of salary per remaining
    /// year** — a proxy for a prorated bonus, identical for all 32 clubs. This
    /// keeps that number as the league mean and applies the club's own
    /// ``clubGuaranteeLean(forTeam:)`` to it, so the aggressive GM's cuts cost
    /// **19.5 %/yr** and the analytics GM's **10.8 %/yr**. Same league bill,
    /// different clubs paying it — and a club whose GM guarantees everything now
    /// has a genuinely harder time getting out from under a bad signing, which
    /// is the whole of F-61 on the AI side.
    ///
    /// A player with no club is priced neutrally: there is no front office to
    /// have a taste.
    static let impliedGuaranteeRate = 0.15

    static func impliedDeadCap(player: Player) -> Int {
        let years = Swift.max(0, player.contractYearsRemaining)
        guard years > 0 else { return 0 }
        let lean = player.teamID.map { clubGuaranteeLean(forTeam: $0) } ?? 1.0
        let perYear = Double(player.annualSalary) * impliedGuaranteeRate * lean
        return Swift.max(0, Int(perYear) * years)
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
    ///
    /// **F-61 — the club's own taste in guarantees.** When no guarantee was
    /// negotiated, the neutral ``realisticGuaranteedMoney`` is scaled by
    /// ``clubGuaranteeLean(forTeam:)``: an aggressive front office writes 30 %
    /// more of the deal down, an analytics one 28 % less. Guarantees never touch
    /// `Contract.capHit` — only `Contract.deadCap` — so this cannot move a cap
    /// charge and therefore cannot drift from the quote ``projectedCapHit``
    /// holds (which builds this row against a throwaway `teamID` for exactly
    /// that reason, and reads only `capHit`).
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
        let guaranteed = negotiatedGuarantee ?? {
            let neutral = realisticGuaranteedMoney(
                baseSalaries: baseSalaries, signingBonus: signingBonus
            )
            // The bonus is guaranteed by construction — it is paid at signature.
            // Only the BASE half of the promise is the club's to have a taste
            // about, so the lean is applied to that and the bonus rides through
            // untouched. Bounded above by the schedule that backs it: a club
            // cannot guarantee money the contract does not contain.
            let base = Swift.max(0, neutral - signingBonus)
            let leaned = Int(Double(base) * clubGuaranteeLean(forTeam: teamID))
            return signingBonus + Swift.min(leaned, baseSalaries.reduce(0, +))
        }()

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
    /// **#186 — the deal is booked in the league year it charges.**
    ///
    /// The paragraph above describes what this used to be: whatever was agreed,
    /// charged to the open year, because `Player.annualSalary` is one flat number
    /// and there was nowhere else to put it. #127 documented that as residue and
    /// `ContractNegotiationView` grew a current-year gate to compensate, which is
    /// how the composer came to print *"Covers 2027–2030"* directly above
    /// *"over this year's cap by $6.1M"*.
    ///
    /// `DealTargetYear.plan` now decides which year the money lands in and this
    /// function books it there. Three shapes, three bookings:
    ///
    /// * **Tag replacement** — a settled franchise tag is retired and the deal's
    ///   first year IS the tag year, so the tag's charge comes off the open year
    ///   as the deal's goes on. The term does not stack on the tag either: a
    ///   four-year deal retiring a one-year tag is four league years.
    /// * **Deferred extension** — years added on top of a deal that is still
    ///   running. **The open year is not touched at all**: not `annualSalary`,
    ///   not `currentCapUsage`, not the `Contract` row, not the restructure
    ///   receipt, because none of those describe money the club owes before the
    ///   deal starts. The charge is parked on `CommittedCapLedger`'s forward
    ///   table — the #127 machinery the franchise tag already uses — and the
    ///   rollover that opens its binding season writes it onto the player
    ///   (`FreeAgencyEngine.settleFranchiseTags`).
    /// * **Current year** — a free agent, a re-sign, a reprice. Exactly what this
    ///   function always did.
    ///
    /// The clock is the one thing written immediately in all three, and it has to
    /// be: `contractYearsRemaining` is #89's single contract clock, it ticks once
    /// per rollover and nothing else advances it, so a deferred deal's years must
    /// be on it from the day it is signed or the rollovers between now and the
    /// binding season would tick a term that is not there yet.
    ///
    /// - Parameter existingContract: the player's detailed contract when the
    ///   caller already has it. Passing `nil` makes the function look one up
    ///   through `modelContext`; passing `nil` with no context means the deal is
    ///   booked on `annualSalary` alone, which is the simple-mode shape.
    /// - Parameter careerID: the save whose forward ledger a rescinded tag is
    ///   released from — and, for a deferred extension, whose forward ledger the
    ///   new money is parked on. `career.id`, matching every reader of that
    ///   table; `player.careerID` is only the fallback for a path with no
    ///   `Career` in hand, and a nil there books nothing at all.
    /// - Parameter currentSeason: `Career.currentSeason`, the year a deferred
    ///   deal's binding season is counted from. Optional only so the four
    ///   existing call sites keep compiling: when it is nil the function looks
    ///   the career up through `modelContext`, and a save it cannot find at all
    ///   falls back to charging the open year, which is the pre-#186 behaviour
    ///   and never loses money.
    /// - Parameter hasRolledOver: whether `executeNewLeagueYear` has already
    ///   opened the next league year — `career.lastRolloverSeason >= career.currentSeason`.
    ///   Read for you alongside the season when `currentSeason` is nil; only a
    ///   caller that passes the season by hand has to pass this too, and one
    ///   that passes neither gets the pre-rollover reading. It matters because
    ///   `currentSeason` is one behind the open league year for six offseason
    ///   phases, and a deferred extension planned off the stale number binds a
    ///   year early — onto the last year of the deal it is extending. See
    ///   ``DealTargetYear/openSeason(currentSeason:hasRolledOver:)``.
    @discardableResult
    static func applyNegotiatedDeal(
        player: Player,
        team: Team?,
        offer: NegotiationOffer,
        application: DealApplication,
        capMode: CapMode,
        careerID: UUID? = nil,
        currentSeason: Int? = nil,
        hasRolledOver: Bool = false,
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

        // Not `resolvedCareerID` — that one asserts in DEBUG on a miss, which is
        // right for a ledger WRITE and wrong for the reads below, which every
        // shape performs and most saves answer with nothing to do.
        let ledgerCareerID = careerID ?? player.careerID
        // The season AND which side of the league-year rollover it is on: the
        // two are one fact and are read together, because a binding year derived
        // from the season alone is a year out for most of the offseason (see
        // `DealTargetYear.openSeason`).
        let resolved = resolvedLeagueYear(ledgerCareerID, modelContext: modelContext)
        let season = currentSeason ?? resolved?.season
        let rolledOver = currentSeason == nil ? (resolved?.hasRolledOver ?? false) : hasRolledOver

        // **The plan, built before anything is written.** It reads the tag flag
        // and the forward table, both of which the rescind below destroys, so
        // the order is load-bearing rather than stylistic.
        let plan = DealTargetYear.plan(
            player: player,
            offer: offer,
            application: application,
            capMode: capMode,
            currentSeason: season ?? 0,
            hasRolledOver: rolledOver,
            careerID: ledgerCareerID,
            existingContract: contract
        )
        // No career and no season means no forward ledger to park money on, so
        // the deal is charged to the open year exactly as it was before #186.
        // Losing a deferral costs the club room it did not have to give up yet;
        // faking one would lose the money altogether, so the fallback is this way
        // round and not the other.
        let deferred = plan.booksForward && season != nil && ledgerCareerID != nil

        // What the club is carrying for this man RIGHT NOW, read with exactly
        // the precedence the cap screen reads it with, so the two can never
        // disagree about what a signing changed. For a settled tag that is the
        // TAG — `settleFranchiseTags` wrote it onto `annualSalary` and left the
        // stale `Contract` row of his old deal alone — which is why the plan
        // owns the choice rather than this line.
        //
        // A deferral that could not be booked forward is charged now, so it also
        // has to net what the club is already carrying — the plan puts 0 there
        // because in the binding year there would be nothing left to net.
        //
        // **A camp body is carrying nothing** (#205a, `OFFSEASON_ROSTER_PLAN.md`
        // §3.1). His minimum salary sits on his row but deliberately not on
        // `Team.currentCapUsage`, so netting against it would under-charge the
        // club by exactly that minimum for a man it has just decided to keep.
        // Signing a real deal is also what ends his camp: the flag clears here,
        // which keeps `settleCampBodies` from charging the club a second time
        // for him at cutdown.
        let wasCampBody = CampRosterEngine.isCampBody(player)
        CampRosterEngine.clearCampBodyStatus(player)
        let previousCharge = wasCampBody
            ? 0
            : (plan.booksForward && !deferred
                ? (contract?.capHit ?? player.annualSalary)
                : plan.replacedCharge)

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
        //
        // **#186: a deferred extension settles nothing**, because it ends
        // nothing. The receipt belongs to the deal that is still running and is
        // still being paid off it; the new years do not start until that deal is
        // over, by which point `executeNewLeagueYear`'s own carry tick has run
        // the receipt down to zero on its normal schedule. Accelerating it here
        // would charge the club dead money for a contract that has not been
        // replaced and is not going anywhere.
        let restructureSettlement = deferred ? 0 : max(0, player.restructureDeadMoney)
        if !deferred {
            player.restructureReliefK = 0
            player.restructureProrationK = 0
            player.restructureCarryYears = 0
        }

        // The tag is retired by the signature — see the doc above. BEFORE the
        // clock is written, because rescinding restores the year of control the
        // tag floored it at and an extension must add its years to the contract
        // the man actually had. The plan was built above it for the same reason
        // in reverse: it has to see the tag.
        if player.isFranchiseTagged {
            rescindFranchiseTagBooks(player: player, careerID: ledgerCareerID)
        }

        // Whatever he signs replaces the tag year he was playing out, so the
        // marker that made this a `.tagReplacement` goes with it — otherwise the
        // NEXT deal would be planned as one too and net a tag that is gone.
        player.franchiseTagSeason = 0

        // #89's one clock, written in every shape — see the doc above.
        player.contractYearsRemaining = plan.contractYears

        // **A deferred deal does not touch the open year.** `annualSalary` is
        // what the rollover's cap true-up sums, so writing the new rate now
        // would charge the club for a contract that has not started; the
        // forward ledger holds it until its binding season and
        // `settleFranchiseTags` writes it then.
        guard !deferred else {
            // The negotiated terms ride along, because the row is the only
            // record of this deal until it binds: `settleFranchiseTags` rewrites
            // the `Contract` from it, and a guarantee invented at settlement
            // would be a term nobody agreed to.
            CommittedCapLedger.commitForward(
                playerID: player.id,
                playerName: player.fullName,
                annualCapHit: offer.annualCapHit,
                baseSalary: offer.annualSalary,
                years: max(1, offer.years),
                bindingSeason: plan.startSeason,
                kind: .deferredDeal,
                guaranteedMoney: offer.guaranteedMoney,
                noTradeClause: offer.noTradeClause,
                careerID: ledgerCareerID
            )
            return 0
        }

        player.annualSalary = offer.annualCapHit

        // Rewrite the detailed contract in place (realistic mode only — the
        // other two modes have no `Contract` row to keep in step). The schedule
        // is `negotiatedBaseSalaries`', taken off the plan so the number the cap
        // gate refused or allowed is the number that gets written — including
        // the tag-and-extend ceiling, which is the whole reason a tagged man's
        // first year can land under the tag it retires.
        var newCharge = plan.firstYearCapHit
        if capMode == .realistic, let team, !plan.baseSalaries.isEmpty {
            let baseSalaries = plan.baseSalaries
            // The NEGOTIATED structure, not a fresh random draw: the bonus, the
            // guarantee and the no-trade clause were terms both sides agreed to.
            let guaranteed = offer.guaranteedMoney

            if let contract {
                contract.teamID = team.id
                contract.totalYears = plan.contractYears
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
                    totalYears: plan.contractYears,
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

        // The gate and the books have to agree to the thousand, or the composer
        // is allowing deals the ledger then refuses to carry. They are built
        // from one schedule, so this can only fire if somebody splits them again.
        #if DEBUG
        assert(
            plan.booksForward || capMode != .realistic || plan.baseSalaries.isEmpty
                || newCharge == plan.firstYearCapHit,
            "Booked charge \(newCharge) diverged from the gated charge \(plan.firstYearCapHit)"
        )
        #endif

        // Sandbox deliberately keeps no ledger — see `signPlayerSandbox`. The
        // restructure acceleration rides on the same line for the same reason it
        // rides on `applyRelease`'s: sandbox never booked the relief, so it must
        // never book the charge.
        if capMode != .sandbox, let team {
            team.currentCapUsage += newCharge - previousCharge + restructureSettlement
        }

        return newCharge
    }

    /// `Career.currentSeason` **and its rollover stamp** for a save, when the
    /// caller did not pass them.
    ///
    /// Both, in one fetch, because neither answers the question on its own: the
    /// counter says which season the career is playing and the stamp says
    /// whether the next league year's books are already open, and only the pair
    /// names the year a contract charges. See
    /// ``DealTargetYear/openSeason(currentSeason:hasRolledOver:)``.
    ///
    /// Deliberately silent about a miss: three of the four negotiation call
    /// sites hold a `Career` and will pass the year explicitly, and the fourth
    /// runs with a context that can find it. A save that can be found neither
    /// way is a harness or a preview, where charging the open year is both the
    /// old behaviour and the harmless one.
    private static func resolvedLeagueYear(
        _ careerID: UUID?,
        modelContext: ModelContext?
    ) -> (season: Int, hasRolledOver: Bool)? {
        guard let careerID, let modelContext else { return nil }
        let descriptor = FetchDescriptor<Career>(
            predicate: #Predicate<Career> { $0.id == careerID }
        )
        guard let career = try? modelContext.fetch(descriptor).first else { return nil }
        // The same test `WeekAdvancer` gates the compliance window with and
        // `FranchiseTagView` gates its re-sign `+1` with.
        return (career.currentSeason, career.lastRolloverSeason >= career.currentSeason)
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

    /// How many salaries each tag averages.
    ///
    /// The franchise tag has always taken the top 5. The transition tag takes
    /// the top 10, which is the whole of the difference between their prices:
    /// ranks 6-10 are by definition no dearer than ranks 1-5, so the transition
    /// number is at or below the franchise number at every position, and the gap
    /// between them is exactly how top-heavy that position's market is.
    static let franchiseTagPoolSize = 5
    static let transitionTagPoolSize = 10

    /// **The one average both tags are built from.**
    ///
    /// Two tags priced by two copies of "sort, take n, divide by what you got"
    /// is two prices that drift the first time one copy is touched, so there is
    /// one copy and the tag identity is the `count` passed into it. Divides by
    /// what the league could actually supply, not by `count` — a position with
    /// six salaried men in it has a real top-6 average and no honest way to
    /// invent four more.
    static func topSalaryAverage(_ topSalaries: [Int], count: Int) -> Int {
        guard count > 0 else { return 0 }
        let top = topSalaries.sorted(by: >).prefix(count)
        guard !top.isEmpty else { return 0 }
        return top.reduce(0, +) / top.count
    }

    /// Calculate the franchise-tag value for a position: the average of the
    /// top 5 salaries (in thousands) supplied for that position group.
    static func franchiseTagValue(position: Position, topSalaries: [Int]) -> Int {
        topSalaryAverage(topSalaries, count: franchiseTagPoolSize)
    }

    /// The transition-tag value for a position: the average of the top 10
    /// salaries (in thousands) supplied for that position group.
    ///
    /// Same function, same list, a wider slice of it — see ``topSalaryAverage``.
    static func transitionTagValue(position: Position, topSalaries: [Int]) -> Int {
        topSalaryAverage(topSalaries, count: transitionTagPoolSize)
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

    /// Cap-mode-aware TRANSITION-tag value, floored on the same share of the cap
    /// the franchise tag is floored on.
    ///
    /// The floor is deliberately the SAME number and not a cheaper one of its
    /// own. It is not a property of either tag — it is the minimum tender a club
    /// may put on a man at a position the league has barely paid anybody at, and
    /// inventing a second, lower floor would be a constant with nothing behind
    /// it. Where the floor binds, the two tags therefore cost the same, which is
    /// the honest answer: at such a position there is no top-heaviness for the
    /// wider slice to shave off.
    static func transitionTagValue(position: Position, topSalaries: [Int], capMode: CapMode, salaryCap: Int) -> Int {
        switch capMode {
        case .simple, .realistic:
            let value = transitionTagValue(position: position, topSalaries: topSalaries)
            return max(value, Int(franchiseTagFloorShare * Double(salaryCap)))
        case .sandbox:
            return 0
        }
    }

    /// The tag floor, as a share of the cap. `5_000 / 265_000` — the number both
    /// screens hardcoded, expressed so it grows with the league.
    static let franchiseTagFloorShare = 5_000.0 / Double(openingSalaryCap)

    /// What being tagged costs a player, in morale.
    ///
    /// One number for both tags, because it was one number before either name
    /// existed: `applyFranchiseTag` has always taken 10 (R22, "no player wants
    /// the tag") and the transition tag is the same insult — a one-year tender
    /// in place of the long deal he was playing for. It is named rather than
    /// written twice so the two tags cannot end up disagreeing about how much a
    /// man minds.
    static let tagMoraleCost = 10

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
        player.morale = Swift.max(0, player.morale - tagMoraleCost)

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
        player.morale = Swift.min(100, player.morale + tagMoraleCost)
    }

    // MARK: - Transition Tag

    /// **Apply the transition tag** — the same shape as ``applyFranchiseTag``,
    /// and different in exactly one thing that matters: it does not stop anyone
    /// else signing him.
    ///
    /// What the two share, and share deliberately:
    ///
    /// * the club's books are untouched. The tag is a decision about the league
    ///   year that has not opened; the money is a forward promise settled by
    ///   `FreeAgencyEngine.settleTransitionTags` at the rollover, exactly as the
    ///   franchise tag's is. Nothing here writes `annualSalary` or
    ///   `Team.currentCapUsage` — see the long note on `applyFranchiseTag` for
    ///   the bug that shape exists to prevent.
    /// * the contract clock is floored at 1 and the pre-tag value is stashed, so
    ///   ``removeTransitionTag`` is an exact undo rather than an approximate one.
    /// * ``tagMoraleCost``.
    ///
    /// What differs is the whole feature: the row this writes carries an
    /// OFFER SHEET slot. A rival club may put a contract in front of the tagged
    /// man (`FreeAgencyEngine.openTransitionOfferSheet`), and the club that
    /// tagged him then has one decision to make — match those terms, or lose him
    /// for nothing at the rollover. The franchise tag has no such slot, which is
    /// why the two cannot share a ledger row.
    ///
    /// **Not booked into `CommittedCapLedger`.** That table's `Kind` has two
    /// cases, `.franchiseTag` and `.deferredDeal`, and this promise is neither;
    /// filing it under either name would make `settleFranchiseTags` settle it as
    /// something it is not. It lives in ``TransitionTagLedger`` instead — see
    /// that type's note for what that costs.
    ///
    /// - Parameter tagValue: the price the user was quoted, from
    ///   ``transitionTagValue(position:topSalaries:capMode:salaryCap:)``. Stored,
    ///   not re-derived later, for the reason `settleFranchiseTags` documents at
    ///   length: a tag that settles dearer than the screen said is the dishonesty
    ///   the forward ledger exists to end.
    /// - Parameter bindingSeason: the league year the tag charges —
    ///   `career.currentSeason + 1`, the same arithmetic the franchise tag uses.
    static func applyTransitionTag(
        player: Player,
        tagValue: Int,
        position: Position,
        team: Team?,
        capMode: CapMode,
        bindingSeason: Int,
        careerID: UUID
    ) {
        _ = team      // The club's books are deliberately untouched.
        _ = capMode

        let priorYears = player.contractYearsRemaining
        player.contractYearsRemaining = Swift.max(1, player.contractYearsRemaining)
        player.morale = Swift.max(0, player.morale - tagMoraleCost)

        TransitionTagLedger.upsert(
            TransitionTagLedger.Tag(
                playerID: player.id,
                playerName: player.fullName,
                positionRaw: position.rawValue,
                price: Swift.max(0, tagValue),
                bindingSeason: bindingSeason,
                priorYears: priorYears < player.contractYearsRemaining ? priorYears : nil,
                canvassed: false,
                offer: nil,
                answer: nil
            ),
            careerID: careerID
        )
    }

    /// **Rescind the transition tag — the exact undo of ``applyTransitionTag``.**
    ///
    /// Gives back the flag, the morale and the one year of club control the tag
    /// floored the clock at, and nothing else, because nothing else was ever
    /// taken. A missing `priorYears` leaves the clock alone, which is the safe
    /// direction for the same reason `rescindFranchiseTagBooks` says it is: a
    /// rostered man under contract beats a rostered man stranded at 0 years.
    ///
    /// **It also tears up any offer sheet on him.** The sheet is a bid for a
    /// tagged player; withdraw the tag and there is nothing to bid on. This is
    /// the one thing the user can do that makes an outstanding match-or-lose
    /// decision go away, and it costs him the man at the rollover in the
    /// ordinary way — his deal expires and he reaches the market.
    static func removeTransitionTag(player: Player, team: Team?, capMode: CapMode, careerID: UUID) {
        _ = team
        _ = capMode
        guard let row = TransitionTagLedger.tag(playerID: player.id, careerID: careerID) else { return }

        if let priorYears = row.priorYears {
            player.contractYearsRemaining = priorYears
        }
        TransitionTagLedger.remove(playerID: player.id, careerID: careerID)
        player.morale = Swift.min(100, player.morale + tagMoraleCost)
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
        // Tag rows only, both times. A man who also holds a deferred extension
        // must not have its clock restored off a tag row, and must not have its
        // money released with one.
        let reservation = CommittedCapLedger.forwardCommitment(
            playerID: player.id,
            careerID: careerID,
            kind: .franchiseTag
        )
        player.isFranchiseTagged = false
        if let priorYears = reservation?.priorYears {
            player.contractYearsRemaining = priorYears
        }
        CommittedCapLedger.releaseForward(
            playerID: player.id,
            careerID: careerID,
            kind: .franchiseTag
        )
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
        // Neither collapses into a bigger group: the snap and the hold are the
        // only jobs those payloads describe, so each is its own premium.
        case .snapping(_):        return .LS
        case .holding(_):         return .H
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
        case .LS:                    return .LS
        case .H:                     return .H
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
    ///
    /// The menu is ordered by the man's own motivation, not by his position
    /// alone — see ``IncentiveCategory/menu(for:motivation:)`` for why a prefix
    /// of the flat position order made the playoff clause unofferable to the
    /// exact player it was written about.
    static func suggestedIncentives(
        player: Player,
        annualSalaryK: Int,
        limit: Int = 3
    ) -> [ContractIncentive] {
        guard annualSalaryK > 0, limit > 0 else { return [] }
        let menu = IncentiveCategory.menu(
            for: player.position,
            motivation: player.personality.motivation
        ).prefix(limit)

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

    /// How the player's OWN motivation weights one clause — the other half of
    /// the discount, and a different question from the agent's.
    ///
    /// ``personaIncentiveCredit`` asks *how much of this is real money?* This
    /// asks *is this the season I was going to play anyway?* A stats man handed
    /// a production tier is being paid for the thing he already gets out of bed
    /// for, so the clause costs him nothing he was not already doing and he
    /// counts it high. The same tier offered to a ring-chaser reads as being
    /// paid to pad, and he marks it down — which is why escalators are a poor
    /// way to close HIS gap, and a contender is the thing that closes it. That
    /// is the same shape `FreeAgencyEngine.loserTax` already gives him, reached
    /// from the other side of the table.
    ///
    /// **Money is deliberately the flat reference case.** A dollar is a dollar
    /// to him whatever it is written on, and the half of his position that
    /// wants it guaranteed instead is already the agent's job above.
    ///
    /// The table spans 0.85…1.30 across the whole motivation × category cross
    /// product, and it changes only what an offer is WORTH in the room: the
    /// settlement (``evaluateIncentives`` → `FreeAgencyEngine`) never reads it,
    /// so a clause that hits costs the club the same money whoever signed it.
    static func motivationIncentiveCredit(
        _ motivation: Motivation,
        category: IncentiveCategory
    ) -> Double {
        switch (motivation, category) {
        case (.money, _):               return 1.00

        case (.stats, .gamesPlayed),
             (.stats, .playoffBerth):   return 0.95
        case (.stats, _):               return 1.25

        case (.winning, .playoffBerth): return 1.30
        case (.winning, .gamesPlayed):  return 1.00
        case (.winning, _):             return 0.85

        case (.fame, .gamesPlayed):     return 0.95
        case (.fame, .playoffBerth):    return 1.05
        case (.fame, _):                return 1.15

        case (.loyalty, .gamesPlayed):  return 1.10
        case (.loyalty, .playoffBerth): return 1.05
        case (.loyalty, _):             return 1.00
        }
    }

    /// The package-level credit: the per-clause credits above, weighted by what
    /// each clause pays.
    ///
    /// Weighted by `bonusK` rather than by expected value on purpose. The
    /// alternative means spelling ``expectedSeasonIncentiveValue``'s likelihood
    /// loop a second time here, and two copies of one arithmetic is how the
    /// contract card and the cut sheet start quoting different numbers for the
    /// same deal. What each clause is written for is the honest weight anyway —
    /// he is looking at the offer sheet, not at a probability table.
    static func motivationIncentiveCredit(
        for player: Player,
        incentives: [ContractIncentive]
    ) -> Double {
        let total = Double(maxSeasonIncentiveValue(incentives))
        guard total > 0 else { return 1.0 }
        let motivation = player.personality.motivation
        let weighted = incentives.reduce(0.0) { sum, incentive in
            sum + Double(incentive.bonusK)
                * motivationIncentiveCredit(motivation, category: incentive.category)
        }
        return weighted / total
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
        // Two independent discounts, applied one after the other because they
        // are two different people's objections: the agent's read on whether
        // clause money is real money, then the client's on whether this is a
        // season he was going to play anyway.
        let clientCredit = motivationIncentiveCredit(for: player, incentives: incentives)
        return Int(
            (perSeason * personaIncentiveCredit(persona) * clientCredit * Double(years)).rounded()
        )
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

// MARK: - Transition Tag Ledger

/// **Where a transition tag lives** — the tag itself, the offer sheet a rival
/// club may put on it, and the one answer the tagging club owes.
///
/// ## Why this is a table of its own
///
/// The franchise tag needs two pieces of state and the game already has homes
/// for both: `Player.isFranchiseTagged` says the man is tagged, and a
/// `CommittedCapLedger` forward row says what the tag will cost when the league
/// year opens. The transition tag can borrow neither.
///
/// * `Player.isFranchiseTagged` means *franchise*-tagged and is read that way in
///   a dozen places — the expiry loop skips it, the trade market refuses to move
///   a man carrying it, the roster row draws a badge for it. Setting it for a
///   transition tag would make every one of those sentences false. `Player` is
///   a SwiftData model in `Domain/`, so a second flag is a schema change and is
///   NOT this lane's to make; see the hand-off note at the foot of this type.
/// * `CommittedCapLedger.Kind` has exactly two cases and this promise is neither
///   of them. Filing it as `.franchiseTag` would have `settleFranchiseTags`
///   settle it as a franchise tag; filing it as `.deferredDeal` would have that
///   function write a negotiated extension's `Contract` row over it. A name
///   already used for another quantity does not get reused.
///
/// And there is a third reason, which would hold even if the first two did not:
/// an offer sheet has a bidder, a price, a term and an answer, and no field on
/// `Reservation` carries any of them.
///
/// ## What it costs
///
/// The forward money in this table is invisible to the cap surfaces that read
/// `CommittedCapLedger.forwardCoverage` (`CapOverviewView`, `ContractTimelineView`).
/// `FranchiseTagView`'s own next-year banner reads this table directly and is
/// therefore right; the others understate next league year by the tag price of
/// any transition-tagged man, and treat him as an expiring contract worth
/// nothing. That is a real gap and it is written down rather than papered over:
/// closing it means one enum case (`CommittedCapLedger.Kind.transitionTag`) in a
/// file this lane does not own.
///
/// ## Determinism and scope
///
/// Career-scoped through `CareerScopedDefaults.key`, exactly like
/// `CommittedCapLedger`, so no save can read another's tags. The base key is not
/// yet on `CareerScopedDefaults.keys` — that file belongs to another lane, and
/// the precedent is `FranchiseTagView`'s own price-memory key, which is in the
/// same position. The only cost of the omission is that a deleted save leaves
/// one small blob behind; it belongs on the purge list.
enum TransitionTagLedger {

    // MARK: - Rows

    /// A rival club's contract offer to a transition-tagged player.
    ///
    /// Terms are the whole of it: matching means the tagging club takes on
    /// exactly these, which is what makes an offer sheet a weapon rather than a
    /// formality. Nothing in here is a share or a multiplier — the salary and
    /// the term are what `FreeAgencyEngine.openTransitionOfferSheet` drew, and
    /// they are stored so the settlement charges the number the user was shown.
    struct OfferSheet: Codable, Equatable {
        var teamID: UUID
        var teamAbbreviation: String
        /// Per year, in thousands — the unit every cap number in the game uses.
        var annualSalary: Int
        var years: Int
        /// The league year the sheet was filed in, for the same
        /// cannot-outlive-its-season reason `CommittedCapLedger.Reservation`
        /// carries one.
        var filedSeason: Int
    }

    /// The tagging club's answer to a sheet. Absent means UNANSWERED, and that
    /// is all it means — the settlement treats it as a decline because the
    /// alternative is a club that keeps a player by ignoring the post, but
    /// nothing else in the game reads a blank as a refusal.
    enum Answer: String, Codable {
        case matched
        case declined
    }

    /// One transition tag.
    struct Tag: Codable, Equatable, Identifiable {
        var playerID: UUID
        var playerName: String
        /// `Position.rawValue`. Stored as the raw string so a future position
        /// rename cannot make an old save's row undecodable.
        var positionRaw: String
        /// The tender, in thousands — the top-10 positional average the user was
        /// quoted, floored and cap-mode-aware.
        var price: Int
        var bindingSeason: Int
        /// `Player.contractYearsRemaining` before the tag floored it, when the
        /// tag RAISED it. See `ContractEngine.applyTransitionTag`.
        var priorYears: Int?
        /// Whether the market has had its one look at this man. The offer-sheet
        /// round is not re-run on every screen load: a club that passed has
        /// passed, and re-rolling until something lands would make the tag a
        /// slot machine the user could feed by reopening a screen.
        var canvassed: Bool
        var offer: OfferSheet?
        var answer: Answer?

        var id: UUID { playerID }

        var position: Position? { Position(rawValue: positionRaw) }

        /// A decision is outstanding while a sheet is on the table unanswered.
        var isDecisionOutstanding: Bool { offer != nil && answer == nil }

        /// Whether the man stays. No sheet, or a matched one.
        var isRetained: Bool { offer == nil || answer == .matched }

        /// What he is paid next league year if he stays, in thousands: the
        /// matched sheet's salary where there is one, the tender otherwise.
        var retainedSalary: Int {
            answer == .matched ? (offer?.annualSalary ?? price) : price
        }

        /// How many years of that. A tender is one year by definition; a matched
        /// sheet is however long the sheet was.
        var retainedYears: Int {
            answer == .matched ? max(1, offer?.years ?? 1) : 1
        }
    }

    // MARK: - Storage

    /// Base key — namespaced per save through `CareerScopedDefaults.key`.
    static let defaultsKey = "transitionTagCommitments"

    private static func storageKey(_ careerID: UUID) -> String {
        CareerScopedDefaults.key(defaultsKey, careerID: careerID)
    }

    private static func table(careerID: UUID) -> [String: Tag] {
        guard let data = UserDefaults.standard.data(forKey: storageKey(careerID)),
              let rows = try? JSONDecoder().decode([String: Tag].self, from: data)
        else { return [:] }
        return rows
    }

    private static func write(_ rows: [String: Tag], careerID: UUID) {
        let key = storageKey(careerID)
        guard !rows.isEmpty else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: - Reads

    /// Every transition tag this save holds, dearest first.
    static func tags(careerID: UUID?) -> [Tag] {
        guard let careerID else { return [] }
        return table(careerID: careerID).values.sorted { $0.price > $1.price }
    }

    /// This save's transition tag on one player, if any.
    static func tag(playerID: UUID, careerID: UUID?) -> Tag? {
        guard let careerID else { return nil }
        return table(careerID: careerID)[playerID.uuidString]
    }

    /// The men a rollover binding `bindingSeason` must not let the expiry loop
    /// touch — the transition tag's stand-in for `Player.isFranchiseTagged`.
    ///
    /// `<=` and not `==`, matching `CommittedCapLedger.consumeForward`: a row
    /// from a league year that somehow never got settled is settled late rather
    /// than leaving a man on the books forever.
    static func taggedPlayerIDs(careerID: UUID?, bindingSeason: Int) -> Set<UUID> {
        Set(tags(careerID: careerID).filter { $0.bindingSeason <= bindingSeason }.map(\.playerID))
    }

    /// Whether this save has a transition tag out. One per offseason, the same
    /// way the franchise tag is one per offseason.
    static func hasTagOutstanding(careerID: UUID?) -> Bool {
        !tags(careerID: careerID).isEmpty
    }

    // MARK: - Writes

    /// Records a tag, replacing whatever row that player already had.
    static func upsert(_ tag: Tag, careerID: UUID?) {
        guard let careerID else { return }
        var rows = table(careerID: careerID)
        rows[tag.playerID.uuidString] = tag
        write(rows, careerID: careerID)
    }

    static func remove(playerID: UUID, careerID: UUID?) {
        guard let careerID else { return }
        var rows = table(careerID: careerID)
        guard rows.removeValue(forKey: playerID.uuidString) != nil else { return }
        write(rows, careerID: careerID)
    }

    /// **Answers an outstanding offer sheet.**
    ///
    /// Records the decision and nothing else: matching does not move a dollar
    /// today, because the sheet — like the tender it was filed against — charges
    /// the league year that has not opened. `FreeAgencyEngine.settleTransitionTags`
    /// is where either answer becomes real.
    ///
    /// Refuses to answer a row with no sheet on it, and refuses to change an
    /// answer once given: a decision the user could flip until the rollover is
    /// not a decision, and "let him go" is the half of this feature that has to
    /// hurt.
    @discardableResult
    static func answer(_ answer: Answer, playerID: UUID, careerID: UUID?) -> Bool {
        guard let careerID, var row = tag(playerID: playerID, careerID: careerID),
              row.offer != nil, row.answer == nil
        else { return false }
        row.answer = answer
        upsert(row, careerID: careerID)
        return true
    }

    /// **The rollover's read.** Returns every tag binding at or before
    /// `bindingSeason` and REMOVES it in the same call.
    ///
    /// Read-and-delete rather than read-then-delete for the reason
    /// `CommittedCapLedger.consumeForward` gives: a caller that settled the rows
    /// and then failed to clear them would settle the same tag twice.
    @discardableResult
    static func consume(careerID: UUID?, bindingSeason: Int) -> [Tag] {
        guard let careerID else { return [] }
        let rows = table(careerID: careerID)
        let due = rows.values.filter { $0.bindingSeason <= bindingSeason }
        guard !due.isEmpty else { return [] }
        write(rows.filter { $0.value.bindingSeason > bindingSeason }, careerID: careerID)
        return due.sorted { $0.price > $1.price }
    }
}
