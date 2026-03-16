import Foundation

struct PlayerGameStats: Codable, Identifiable {
    var id: UUID { playerID }

    var playerID: UUID
    var playerName: String
    var position: Position

    // MARK: - Passing
    var passingYards: Int
    var passingTDs: Int
    var interceptions: Int
    var completions: Int
    var attempts: Int

    // MARK: - Rushing
    var rushingYards: Int
    var rushingTDs: Int
    var carries: Int

    // MARK: - Receiving
    var receivingYards: Int
    var receivingTDs: Int
    var receptions: Int
    var targets: Int

    // MARK: - Defense
    var tackles: Int
    var sacks: Double
    var forcedFumbles: Int
    var interceptionsCaught: Int

    // MARK: - Kicking
    var fieldGoalsMade: Int
    var fieldGoalsAttempted: Int

    // MARK: - Computed

    /// NFL passer rating (0–158.3). Returns 0 when no pass attempts have been recorded.
    var passerRating: Double {
        guard attempts > 0 else { return 0.0 }
        let a = min(max(((Double(completions) / Double(attempts)) - 0.3) * 5.0, 0.0), 2.375)
        let b = min(max(((Double(passingYards) / Double(attempts)) - 3.0) * 0.25, 0.0), 2.375)
        let c = min(max((Double(passingTDs) / Double(attempts)) * 20.0, 0.0), 2.375)
        let d = min(max(2.375 - ((Double(interceptions) / Double(attempts)) * 25.0), 0.0), 2.375)
        return ((a + b + c + d) / 6.0) * 100.0
    }

    /// Yards gained per rushing attempt. Returns 0 when no carries have been recorded.
    var yardsPerCarry: Double {
        guard carries > 0 else { return 0.0 }
        return Double(rushingYards) / Double(carries)
    }

    /// Yards gained per reception. Returns 0 when no receptions have been recorded.
    var yardsPerReception: Double {
        guard receptions > 0 else { return 0.0 }
        return Double(receivingYards) / Double(receptions)
    }

    // MARK: - Init

    init(
        playerID: UUID,
        playerName: String,
        position: Position,
        passingYards: Int = 0,
        passingTDs: Int = 0,
        interceptions: Int = 0,
        completions: Int = 0,
        attempts: Int = 0,
        rushingYards: Int = 0,
        rushingTDs: Int = 0,
        carries: Int = 0,
        receivingYards: Int = 0,
        receivingTDs: Int = 0,
        receptions: Int = 0,
        targets: Int = 0,
        tackles: Int = 0,
        sacks: Double = 0.0,
        forcedFumbles: Int = 0,
        interceptionsCaught: Int = 0,
        fieldGoalsMade: Int = 0,
        fieldGoalsAttempted: Int = 0
    ) {
        self.playerID = playerID
        self.playerName = playerName
        self.position = position
        self.passingYards = passingYards
        self.passingTDs = passingTDs
        self.interceptions = interceptions
        self.completions = completions
        self.attempts = attempts
        self.rushingYards = rushingYards
        self.rushingTDs = rushingTDs
        self.carries = carries
        self.receivingYards = receivingYards
        self.receivingTDs = receivingTDs
        self.receptions = receptions
        self.targets = targets
        self.tackles = tackles
        self.sacks = sacks
        self.forcedFumbles = forcedFumbles
        self.interceptionsCaught = interceptionsCaught
        self.fieldGoalsMade = fieldGoalsMade
        self.fieldGoalsAttempted = fieldGoalsAttempted
    }
}
