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
}
