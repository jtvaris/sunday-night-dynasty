import Foundation

enum PlayType: String, Codable {
    case run = "Run"
    case pass = "Pass"
    case punt = "Punt"
    case fieldGoal = "Field Goal"
    case kickoff = "Kickoff"
    case extraPoint = "Extra Point"
    case twoPointConversion = "Two Point Conversion"
    case kneel = "Kneel"
    case spike = "Spike"
}

enum PlayOutcome: String, Codable {
    case completion = "Completion"
    case incompletion = "Incompletion"
    case rush = "Rush"
    case sack = "Sack"
    case interception = "Interception"
    case fumble = "Fumble"
    case fumbleLost = "Fumble Lost"
    case touchdown = "Touchdown"
    case fieldGoalGood = "Field Goal Good"
    case fieldGoalMissed = "Field Goal Missed"
    case extraPointGood = "XP Good"
    case extraPointMissed = "XP Missed"
    case twoPointGood = "2PT Good"
    case twoPointFailed = "2PT Failed"
    case punt = "Punt"
    case touchback = "Touchback"
    case safety = "Safety"
    case penalty = "Penalty"
    case kneel = "Kneel"
    case spike = "Spike"
}
