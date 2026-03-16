import Foundation

enum DriveOutcome: String, Codable {
    case touchdown = "Touchdown"
    case fieldGoal = "Field Goal"
    case punt = "Punt"
    case turnover = "Turnover"
    case turnoverOnDowns = "Turnover on Downs"
    case safety = "Safety"
    case endOfHalf = "End of Half"
    case endOfGame = "End of Game"
}

struct DriveResult: Codable {
    var driveNumber: Int
    var teamID: UUID
    /// Field position at the start of the drive (yards from own end zone, 0–100)
    var startingYardLine: Int
    var plays: [PlayResult]
    var result: DriveOutcome

    /// Net yards gained across all plays in the drive
    var totalYards: Int {
        plays.reduce(0) { $0 + $1.yardsGained }
    }

    /// Total number of plays run during the drive
    var totalPlays: Int {
        plays.count
    }

    /// Total clock time consumed by the drive in seconds
    var timeConsumed: Int {
        guard let first = plays.first, let last = plays.last else { return 0 }
        let quarterDiff = (last.quarter - first.quarter) * 900
        let timeDiff = first.timeRemaining - last.timeRemaining
        return quarterDiff + timeDiff
    }
}
