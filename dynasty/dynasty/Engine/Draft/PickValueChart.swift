import Foundation

/// Jimmy Johnson NFL Draft Pick Value Chart.
///
/// Each pick (1...224) maps to a point value used for trade evaluation.
/// The chart was originally devised by Jimmy Johnson in the 1990s and remains
/// the league's lingua franca for how teams compare picks across rounds.
///
/// Used by:
/// - Trade builder UI (`TradeView`) for showing pick worth.
/// - `TradeValueEngine` for every accept/decline/counter decision.
/// - `WarRoomPanel` for visualising the user's draft capital.
///
/// # F-09 — the tail was not Jimmy Johnson, it was a cliff
///
/// The table shipped byte-faithful for picks 1-129 and then collapsed. Measured
/// cell by cell against the real chart: pick 160 was **10** against a real
/// **27.4**, pick 190 was **2** against **15.4**, pick 200 was **1** against
/// **11.4**, pick 210 was **1** against **7.4**, and picks 198-224 were all
/// `1`. Round totals: R5 **817** vs ~1 096, R6 **137** vs ~678, R7 **37** vs
/// ~298. Rounds 6 and 7 — 64 of 224 picks, **29 % of the league's draft
/// inventory by count** — were worth 174 points combined, less than one 68-OVR
/// backup. In the tail the game's chart was 11× steeper than the steepest
/// published chart in existence, including the one it claimed to be.
///
/// The consequence was structural, not cosmetic: nothing below round 4 could
/// transact. A Day-3 pick could not close a gap, could not sweeten a package
/// and could not be the return in a small deal — which is where roughly half of
/// all real in-season trades settle. Every valuation in the game is quoted
/// through this table, so this repair moves every trade in the game and is the
/// first thing in the trade wave to land.
///
/// **Why the values are `Double` now.** The real chart steps 0.5/pick through
/// round 5 and 0.4/pick from there. Rounding those to `Int` gives ties — pick
/// 133 and pick 132 would both read 40 — and a tie means swapping two adjacent
/// picks is free, which is exactly the kind of costless move the trade wave is
/// removing elsewhere. `value(forPick:)` is therefore the precise accessor every
/// engine prices through; `points(forPick:)` keeps the rounded integer the UI
/// has always displayed. Rejected alternative: scaling the whole table by 10 and
/// staying integral — it would have re-quoted every number the player reads
/// (a 3 000-point first becomes 30 000) for no gain.
enum PickValueChart {

    /// Precise Jimmy Johnson value for an overall pick number.
    ///
    /// This is the arithmetic accessor: anything that multiplies, discounts or
    /// sums pick value uses it, because the tail's real steps are fractional.
    /// Picks outside the 1...224 range fall back to the chart's floor.
    static func value(forPick pick: Int) -> Double {
        guard pick >= 1, pick <= 224 else { return floorValue }
        return chart[pick - 1]
    }

    /// Rounded point value for a given overall pick number — the number the war
    /// room, the Trade Center and the draft-order screen have always printed.
    /// Picks outside the 1...224 range fall back to the chart's floor.
    static func points(forPick pick: Int) -> Int {
        Int(value(forPick: pick).rounded())
    }

    /// What a pick outside the chart is worth. `2` rather than `1`: the real
    /// chart's last cell is 2.0, and a compensatory pick past #224 is not worth
    /// less than the last pick of the seventh round.
    private static let floorValue = 2.0

    private static let chart: [Double] = [
        // Round 1 (1-32)
        3000, 2600, 2200, 1800, 1700, 1600, 1500, 1400,
        1350, 1300, 1250, 1200, 1150, 1100, 1050, 1000,
         950,  900,  875,  850,  800,  780,  760,  740,
         720,  700,  680,  660,  640,  620,  600,  590,
        // Round 2 (33-64)
         580,  560,  550,  540,  530,  520,  510,  500,
         490,  480,  470,  460,  450,  440,  430,  420,
         410,  400,  390,  380,  370,  360,  350,  340,
         330,  320,  310,  300,  292,  284,  276,  270,
        // Round 3 (65-96)
         265,  260,  255,  250,  245,  240,  235,  230,
         225,  220,  215,  210,  205,  200,  196,  192,
         188,  184,  180,  176,  172,  168,  164,  160,
         156,  152,  148,  144,  140,  136,  132,  128,
        // Round 4 (97-128)
         124,  120,  116,  112,  108,  104,  100,   96,
          92,   88,   86,   84,   82,   80,   78,   76,
          74,   72,   70,   68,   66,   64,   62,   60,
          58,   56,   54,   52,   50,   48,   46,   44,
        // Round 5 (129-160) — real total ≈ 1 094 (was 817).
        // Four whole-point steps off the back of round 4, then the 0.5/pick
        // glide the real chart runs to the end of the round. Pick 129 is the
        // one cell corrected inside the "faithful" region: it shipped as 42,
        // which both breaks the 44 → 43 step down from pick 128 and would tie
        // with the repaired 130.
          43.0, 42.0, 41.0, 40.0, 39.5, 39.0, 38.5, 38.0,
          37.5, 37.0, 36.5, 36.0, 35.5, 35.0, 34.5, 34.0,
          33.5, 33.0, 32.6, 32.2, 31.8, 31.4, 31.0, 30.6,
          30.2, 29.8, 29.4, 29.0, 28.6, 28.2, 27.8, 27.4,
        // Round 6 (161-192) — real total ≈ 666 (was 137).
        // A flat 0.4/pick glide, which is what the published chart does from
        // here down. This is the round that makes a small deal constructible:
        // a sixth is now worth ~15-27 points instead of 2-9, i.e. enough to be
        // the difference between two fifths rather than a rounding error.
          27.0, 26.6, 26.2, 25.8, 25.4, 25.0, 24.6, 24.2,
          23.8, 23.4, 23.0, 22.6, 22.2, 21.8, 21.4, 21.0,
          20.6, 20.2, 19.8, 19.4, 19.0, 18.6, 18.2, 17.8,
          17.4, 17.0, 16.6, 16.2, 15.8, 15.4, 15.0, 14.6,
        // Round 7 (193-224) — real total ≈ 256 (was 37).
        // Same 0.4/pick glide. The last cell is 2.0, not the 1.8 the glide
        // would give: the published chart floors there, and so does this one.
          14.2, 13.8, 13.4, 13.0, 12.6, 12.2, 11.8, 11.4,
          11.0, 10.6, 10.2,  9.8,  9.4,  9.0,  8.6,  8.2,
           7.8,  7.4,  7.0,  6.6,  6.2,  5.8,  5.4,  5.0,
           4.6,  4.2,  3.8,  3.4,  3.0,  2.6,  2.2,  2.0
    ]
}
