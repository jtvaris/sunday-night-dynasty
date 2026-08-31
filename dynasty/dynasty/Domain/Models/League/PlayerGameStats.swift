import Foundation

nonisolated struct PlayerGameStats: Codable, Identifiable {
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
    /// Passes broken up in coverage (R37). Optional so any previously
    /// encoded stat lines keep decoding; read through ``passDeflectionCount``.
    var passDeflections: Int? = nil

    /// Convenience accessor for the optional PD tally.
    var passDeflectionCount: Int { passDeflections ?? 0 }

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

    // MARK: - Coverage

    /// Whether an all-zero line at this position means "did nothing" or "was
    /// never counted".
    ///
    /// Every column above is a ball-touch, a defensive event or a field goal.
    /// There is nothing here an offensive lineman or a punter can register — no
    /// snaps, no blocks, no pressures allowed, no punts, no gross average — so
    /// those men come back empty from a game they played every down of.
    ///
    /// That is a fact about THIS type, which is why it is stated here instead of
    /// being re-derived by each reader. `PreseasonEngine.CampCase.read` counts
    /// opportunities off these same columns and returns `.quiet` at zero, and a
    /// screen that prints that verdict without asking here ends up saying "did
    /// not factor" about a left tackle who started three exhibitions — five of
    /// the sixteen rows visible on the cut sheet, seventeen of the 53-man
    /// roster. Ask before turning an empty line into a judgement.
    ///
    /// Exhaustive rather than a `default` on purpose: a new position has to be
    /// classified by whoever adds it. The durable fix is a column rather than a
    /// list — one measurable event per blind position — at which point entries
    /// move to the `true` side as they are covered.
    static func measures(_ position: Position) -> Bool {
        switch position {
        case .LT, .LG, .C, .RG, .RT, .P, .LS, .H:
            return false
        case .QB, .RB, .FB, .WR, .TE, .DE, .DT, .OLB, .MLB, .CB, .FS, .SS, .K:
            return true
        }
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
