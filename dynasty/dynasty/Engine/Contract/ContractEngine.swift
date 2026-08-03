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
    /// DT 0.41 (~0.40), RT 0.39 (~0.38), MLB 0.36 (~0.35), S 0.34 (~0.35),
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
            return 0.9    // Interior DL: ~7-8.5%
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

        // Floor: every player is worth at least the veteran minimum (~0.28% of cap)
        let minimum = max(Int(0.0028 * Double(salaryCap)), 750)
        return max(Int(value), minimum)
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
    /// - Parameter existingContract: the player's detailed contract when the
    ///   caller already has it. Passing `nil` makes the function look one up
    ///   through `modelContext`; passing `nil` with no context means the deal is
    ///   booked on `annualSalary` alone, which is the simple-mode shape.
    @discardableResult
    static func applyNegotiatedDeal(
        player: Player,
        team: Team?,
        offer: NegotiationOffer,
        application: DealApplication,
        capMode: CapMode,
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

        // Sandbox deliberately keeps no ledger — see `signPlayerSandbox`.
        if capMode != .sandbox, let team {
            team.currentCapUsage += newCharge - previousCharge
        }

        return newCharge
    }

    /// Restructure a contract by converting this year's base salary into
    /// signing bonus. Lowers the current cap hit but spreads cost to later years.
    /// Returns a new Contract value with updated figures.
    static func restructureContract(contract: Contract) -> Contract {
        guard contract.currentYear < contract.baseSalary.count else { return contract }

        let currentBase = contract.baseSalary[contract.currentYear]

        // Convert 80% of the current base salary to signing bonus
        let convertedAmount = Int(Double(currentBase) * 0.8)
        let remainingBase = currentBase - convertedAmount

        var updatedSalaries = contract.baseSalary
        updatedSalaries[contract.currentYear] = remainingBase

        let updatedBonus = contract.signingBonus + convertedAmount

        return Contract(
            id: contract.id,
            playerID: contract.playerID,
            teamID: contract.teamID,
            totalYears: contract.totalYears,
            currentYear: contract.currentYear,
            baseSalary: updatedSalaries,
            signingBonus: updatedBonus,
            guaranteedMoney: contract.guaranteedMoney,
            isVoidYears: contract.isVoidYears,
            voidYearsCount: contract.voidYearsCount,
            noTradeClause: contract.noTradeClause,
            franchiseTagged: contract.franchiseTagged
        )
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

    /// Apply franchise tag to a player. Sets their salary to the tag value
    /// and marks them as franchise-tagged for the season.
    /// R22: no player wants the tag — it costs 10 morale.
    static func applyFranchiseTag(
        player: Player,
        tagValue: Int,
        team: Team
    ) {
        let previousSalary = player.annualSalary

        player.contractYearsRemaining = 1
        player.annualSalary = tagValue
        player.isFranchiseTagged = true
        player.morale = max(0, player.morale - 10)

        // Update team cap: remove old salary, add new tag salary
        team.currentCapUsage = team.currentCapUsage - previousSalary + tagValue
    }

    /// Cap-mode-aware franchise-tag application. In sandbox mode the tag is free
    /// and team cap is never touched — the player is just flagged as tagged for
    /// one extra year of team control.
    static func applyFranchiseTag(
        player: Player,
        tagValue: Int,
        team: Team,
        capMode: CapMode
    ) {
        switch capMode {
        case .simple, .realistic:
            applyFranchiseTag(player: player, tagValue: tagValue, team: team)
        case .sandbox:
            player.contractYearsRemaining = 1
            player.annualSalary = 0
            player.isFranchiseTagged = true
            player.morale = max(0, player.morale - 10)
        }
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

    /// Remove franchise tag from a player. Reverts them to an expiring contract.
    /// R22: rescinding the tag gives back the 10 morale the tag cost.
    static func removeFranchiseTag(
        player: Player,
        team: Team
    ) {
        let tagSalary = player.annualSalary

        player.isFranchiseTagged = false
        player.contractYearsRemaining = 0
        player.annualSalary = 0
        player.morale = min(100, player.morale + 10)

        // Free up the tag salary from team cap
        team.currentCapUsage -= tagSalary
    }

    /// Cap-mode-aware franchise tag removal. Sandbox skips cap refund logic.
    static func removeFranchiseTag(player: Player, team: Team, capMode: CapMode) {
        switch capMode {
        case .simple, .realistic:
            removeFranchiseTag(player: player, team: team)
        case .sandbox:
            player.isFranchiseTagged = false
            player.contractYearsRemaining = 0
            player.annualSalary = 0
            player.morale = min(100, player.morale + 10)
        }
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
