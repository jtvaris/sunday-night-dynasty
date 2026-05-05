import Foundation

/// Jimmy Johnson NFL Draft Pick Value Chart.
///
/// Each pick (1...224) maps to an integer point value used for trade evaluation.
/// The chart was originally devised by Jimmy Johnson in the 1990s and remains
/// the league's lingua franca for how teams compare picks across rounds.
///
/// Used by:
/// - Trade builder UI (`TradeView`) for showing pick worth.
/// - `TradeEvaluator` (added in Vaihe 3) for accept/decline/counter logic.
/// - `WarRoomPanel` for visualising the user's draft capital.
enum PickValueChart {

    /// Returns the Jimmy Johnson point value for a given overall pick number.
    /// Picks outside the 1...224 range fall back to 1.
    static func points(forPick pick: Int) -> Int {
        guard pick >= 1, pick <= 224 else { return 1 }
        return chart[pick - 1]
    }

    private static let chart: [Int] = [
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
        // Round 5 (129-160)
          42,   40,   39,   38,   37,   36,   35,   34,
          33,   32,   31,   30,   29,   28,   27,   26,
          25,   24,   23,   22,   21,   20,   19,   18,
          17,   16,   15,   14,   13,   12,   11,   10,
        // Round 6 (161-192)
           9,    9,    8,    8,    7,    7,    6,    6,
           6,    5,    5,    5,    4,    4,    4,    4,
           3,    3,    3,    3,    3,    3,    3,    3,
           2,    2,    2,    2,    2,    2,    2,    2,
        // Round 7 (193-224)
           2,    2,    2,    2,    2,    1,    1,    1,
           1,    1,    1,    1,    1,    1,    1,    1,
           1,    1,    1,    1,    1,    1,    1,    1,
           1,    1,    1,    1,    1,    1,    1,    1
    ]
}
