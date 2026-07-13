import Foundation

struct PlayResult: Codable {
    var playNumber: Int
    /// 1–4 for regulation quarters, 5 for overtime
    var quarter: Int
    /// Seconds remaining in the current quarter (max 900)
    var timeRemaining: Int
    var down: Int
    var distance: Int
    /// Field position expressed as yards from the offense's own end zone (0–100)
    var yardLine: Int
    var playType: PlayType
    var outcome: PlayOutcome
    /// Net yards gained on the play; may be negative
    var yardsGained: Int
    /// Human-readable description, e.g. "Brady throws 15 yards to Gronkowski for a first down"
    var description: String
    var isFirstDown: Bool
    var isTurnover: Bool
    var scoringPlay: Bool
    /// Points awarded on a scoring play (0, 2, 3, 6, or 7)
    var pointsScored: Int

    // Key-player attribution (optional; set by PlaySimulator so the live
    // match view can point at the exact players the sim used — ball carrier,
    // pass target, intercepting defender). Absent in older saved data.
    /// The offensive player the play ran through: rusher, scramble QB, or pass target.
    var keyOffensePlayerID: UUID? = nil
    /// The defensive player who decided the play: intercepting DB, named
    /// sacker, breakup DB, credited tackler, or penalty culprit.
    var keyDefensePlayerID: UUID? = nil

    // R37 player-IQ / defensive-commentary signals (all optional so older
    // encoded plays keep decoding; nil = pre-R37 behavior everywhere).
    /// Play action only: did the second level bite on the run fake? Drives
    /// the 3D linebacker choreography (they only step downhill when true).
    var defenseBitOnFake: Bool? = nil
    /// True when an incompletion was a named pass breakup — the credited
    /// defender (``keyDefensePlayerID``) earns a light PD stat.
    var passBreakup: Bool? = nil
    /// True for showcase defensive plays (big hit, breakup): the live feed
    /// paints the row from the defense's perspective.
    var defensiveHighlight: Bool? = nil
    /// Which team had the ball (stamped by the live engine only) so the
    /// feed can color defensive plays from the player's perspective.
    var offenseWasHome: Bool? = nil
}
