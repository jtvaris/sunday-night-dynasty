import Foundation

// MARK: - Cap Management Engine

/// Handles advanced salary cap operations: rollover, compensatory picks,
/// contract year processing, and annual cap growth.
enum CapManagementEngine {

    // MARK: - Cap Rollover

    /// Calculates how much unused cap space rolls over into the next season.
    /// Per NFL rules, up to 20% of the total salary cap can carry forward.
    ///
    /// - Parameters:
    ///   - team: The team whose cap space is being evaluated.
    ///   - season: The season year (used for logging/display purposes).
    /// - Returns: The rollover amount in thousands of dollars.
    static func calculateCapRollover(team: Team, season: Int) -> Int {
        let unusedCap = team.salaryCap - team.currentCapUsage
        guard unusedCap > 0 else { return 0 }

        // NFL cap rollover is capped at 20% of the current year's cap
        let maxRollover = Int(Double(team.salaryCap) * 0.20)
        return min(unusedCap, maxRollover)
    }

    // MARK: - Compensatory Picks

    /// Awards compensatory draft picks to teams that lost more valuable free agents
    /// than they signed. Picks are in rounds 3 through 7, based on the value delta
    /// between departed and acquired free agents.
    ///
    /// - Parameters:
    ///   - team: The team receiving comp pick consideration.
    ///   - lostFreeAgents: Players who left this team in free agency.
    ///   - gainedFreeAgents: Players this team signed in free agency.
    /// - Returns: An array of compensatory `DraftPick` objects, empty if no comp picks awarded.
    static func processCompensatoryPicks(
        team: Team,
        lostFreeAgents: [Player],
        gainedFreeAgents: [Player]
    ) -> [DraftPick] {

        let lostValue = lostFreeAgents.reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1) }
        let gainedValue = gainedFreeAgents.reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1) }

        let valueDelta = lostValue - gainedValue
        guard valueDelta > 0 else { return [] }

        // Number of comp picks scales with how much value was lost
        // Each threshold of $5M in lost value earns one pick (max 4 picks per season)
        let numPicks = min(valueDelta / 5_000, 4)
        guard numPicks > 0 else { return [] }

        var picks: [DraftPick] = []

        for i in 0..<numPicks {
            // First comp pick is a 3rd-round caliber pick; subsequent picks step down in round
            // Rounds 3, 4, 5, 6, 7 — capped at round 7
            let round = min(3 + i, 7)
            let pick = DraftPick(
                seasonYear: 0, // Caller should set the correct season year
                round: round,
                pickNumber: 33 + (i * 10), // Estimated late pick number within the round
                originalTeamID: team.id,
                currentTeamID: team.id
            )
            picks.append(pick)
        }

        return picks
    }

    // MARK: - Contract Year Processing

    /// Advances all player contracts by one year. Players whose contracts expire
    /// (contractYearsRemaining reaches 0) become free agents by clearing their team
    /// assignment. Any corresponding `Contract` objects should be updated or removed
    /// by the caller after computing dead cap impacts.
    ///
    /// - Parameters:
    ///   - players: All players on the team's roster.
    ///   - team: The team whose roster is being processed.
    static func processContractYear(players: [Player], team: Team) {
        for player in players {
            guard player.teamID == team.id else { continue }

            // Decrement contract length
            player.contractYearsRemaining -= 1

            if player.contractYearsRemaining <= 0 {
                // Player becomes an unrestricted free agent
                player.contractYearsRemaining = 0
                player.teamID = nil

                // Remove salary from cap (the player is no longer under contract)
                team.currentCapUsage = max(0, team.currentCapUsage - player.annualSalary)
                player.annualSalary = 0
            }
        }
    }

    /// Calculates dead cap charge when a player is cut mid-contract.
    /// Dead cap = remaining prorated signing bonus + any guaranteed base salaries.
    ///
    /// - Parameters:
    ///   - contract: The player's detailed contract.
    ///   - team: The team cutting the player.
    /// - Returns: Dead cap charge in thousands of dollars for the current year.
    static func calculateDeadCap(for contract: Contract, team: Team) -> Int {
        // Delegate to the Contract model's own deadCap computed property
        return contract.deadCap
    }

    // MARK: - Cap Growth

    /// Grows the salary cap by the specified annual rate (default ~5% per year in the NFL).
    /// Updates both the team's `salaryCap` and adjusts `currentCapUsage` proportionally
    /// so that available space is preserved in relative terms.
    ///
    /// - Parameters:
    ///   - team: The team whose cap is being updated.
    ///   - growthRate: Fractional growth rate (e.g., 0.05 for 5%). Clamped to 0–0.25.
    static func applyCapGrowth(team: Team, growthRate: Double) {
        let clampedRate = max(0.0, min(0.25, growthRate))
        let oldCap = team.salaryCap
        let newCap = Int(Double(oldCap) * (1.0 + clampedRate))
        team.salaryCap = newCap

        // Cap usage stays the same in absolute terms — the extra headroom is the growth benefit
        // (No adjustment to currentCapUsage needed; the difference is new free space.)
    }

    // MARK: - Cap Space Projection

    /// Projects available cap space after applying the rollover from the previous season.
    ///
    /// - Parameters:
    ///   - team: The team to project for.
    ///   - rolloverAmount: Cap space carried over from the prior year (in thousands).
    /// - Returns: Projected available cap space including rollover.
    static func projectedCapSpace(team: Team, rolloverAmount: Int) -> Int {
        return team.availableCap + rolloverAmount
    }

    // MARK: - Minimum Salary Floor

    /// Estimates whether the team is meeting the NFL's minimum salary spending requirement
    /// (typically 89% of the cap must be spent over a rolling two-year period).
    ///
    /// - Parameter team: The team to evaluate.
    /// - Returns: `true` if the team appears to be meeting the floor; `false` if at risk.
    static func isAboveSalaryFloor(team: Team) -> Bool {
        let floorThreshold = Int(Double(team.salaryCap) * 0.89)
        return team.currentCapUsage >= floorThreshold
    }

    /// The dollar amount (in thousands) the team must still spend to reach the salary floor.
    /// Returns 0 if the team is already above the floor.
    static func amountBelowFloor(team: Team) -> Int {
        let floorThreshold = Int(Double(team.salaryCap) * 0.89)
        let shortfall = floorThreshold - team.currentCapUsage
        return max(0, shortfall)
    }
}
