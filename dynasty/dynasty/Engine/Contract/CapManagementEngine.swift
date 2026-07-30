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

    /// Cap-mode-aware rollover. Sandbox returns 0 since the cap is not enforced.
    static func calculateCapRollover(team: Team, season: Int, capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return calculateCapRollover(team: team, season: season)
        case .sandbox:
            return 0
        }
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

        let salaryCap = team.salaryCap
        let lostValue = lostFreeAgents.reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1, salaryCap: salaryCap) }
        let gainedValue = gainedFreeAgents.reduce(0) { $0 + ContractEngine.estimateMarketValue(player: $1, salaryCap: salaryCap) }

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

    /// Cap-mode-aware dead cap. Sandbox always returns 0 — releases are free.
    static func calculateDeadCap(for contract: Contract, team: Team, capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return calculateDeadCap(for: contract, team: team)
        case .sandbox:
            return 0
        }
    }

    // MARK: - Trade Cap Split (Wave 1 — `docs/TRADE_OVERHAUL_PLAN.md`, finding S3)

    /// How one traded player's money divides between the two teams.
    ///
    /// Trades used to be free salary dumps: `TradeEngine.executeTrade` moved
    /// `annualSalary` 1:1, so a team could hand a bloated contract to the AI
    /// and pocket every dollar (plan finding S3). Real NFL rules — and the
    /// game's own cut path — say the signing-bonus proration cannot follow the
    /// player: it accelerates onto the team that paid it.
    struct TradeCapSplit {
        /// Signing-bonus acceleration the TRADING team keeps on its books,
        /// in thousands. Identical model to a release (`calculateDeadCap`).
        let deadCap: Int
        /// Cap hit the ACQUIRING team takes on, in thousands: the share of the
        /// player's base salary that is still UNPAID at the moment of the trade
        /// (see `leagueYearRemaining` — the whole base for an offseason deal,
        /// ~55 % of it at a Week 9 deadline).
        let salaryAssumed: Int
        /// This year's prorated bonus slice — the part that stays behind.
        let proratedPerYear: Int
        /// Base salary the TRADING team has already paid out this league year
        /// and therefore keeps on its own books, in thousands. Zero for any
        /// trade struck outside the regular season.
        let salaryRetained: Int

        /// Cap space the trading team actually frees up (can be negative when
        /// the acceleration is larger than the salary relief — a real and
        /// deliberately painful outcome for bonus-heavy deals).
        var traderRelief: Int { salaryAssumed + proratedPerYear - deadCap - salaryRetained }
    }

    // MARK: - League-year proration (task #26)

    /// Regular-season weeks in one league year.
    ///
    /// Local to the cap model on purpose: what proration needs is the LENGTH of
    /// the paid season, not the schedule (`ScheduleGenerator`'s copy is private
    /// to the scheduler and describes when games are played, not when money is
    /// earned). The two are the same number today and would stay in step by
    /// definition if the season were ever lengthened.
    static let regularSeasonWeeks = 18

    /// The share of the league year still ahead at `week` of `phase`, 0…1.
    ///
    /// NFL base salary is earned week by week: a club that acquires a player at
    /// the deadline is charged only the game checks he has left to collect, and
    /// the club that traded him keeps what it already paid. `tradeCapSplit`
    /// multiplies the base by this fraction, which is why a deadline rental is
    /// affordable to a team that could never carry the same contract in March.
    ///
    /// Bounds worth knowing: the trade window closes after
    /// `TradeValueEngine.deadlineWeek` (9 of 18), so an in-season trade can
    /// never carry a fraction below 10/18 ≈ 0.56 — the model is a discount of at
    /// most ~44 %, never a rounding-to-nothing. Every offseason phase returns
    /// 1.0: a March acquisition owes the whole season.
    ///
    /// PAIRED CHANGE STILL OPEN (handoff to the `TradeValueEngine` owner):
    /// `capDeltas` — and through it `validationErrors`, `canAbsorbExactly` and
    /// the Trade Center's cap preview — still calls `tradeCapSplit` without a
    /// fraction, i.e. it prices a deadline deal at full-season cost while
    /// execution now charges the prorated one. The divergence is in the SAFE
    /// direction (the preview is stricter than the outcome, so no illegal deal
    /// can slip through) but it is a divergence: pass
    /// `leagueYearRemaining(phase:week:)` there and the plan's 5 % AI market cap
    /// slack (`aiMarketCapSlackFraction`) can shrink or go away entirely.
    static func leagueYearRemaining(phase: SeasonPhase, week: Int) -> Double {
        switch phase {
        case .regularSeason, .tradeDeadline, .playoffs:
            let weeksLeft = regularSeasonWeeks - max(1, week) + 1
            let fraction = Double(weeksLeft) / Double(regularSeasonWeeks)
            return min(1.0, max(1.0 / Double(regularSeasonWeeks), fraction))
        default:
            return 1.0
        }
    }

    /// Splits a traded player's money the same way a release does.
    ///
    /// The dead-cap figure is exactly the cut path's: `Contract.deadCap`
    /// (remaining prorated bonus for every year still on the deal) when a
    /// detailed contract row exists, and `RosterCutEvaluator.deadCap` — the
    /// 15 %-of-salary-per-year proxy — when it does not. Most players have no
    /// `Contract` row (they are only minted for realistic-mode FA signings),
    /// so the proxy is the common path and must agree with what the cut screens
    /// already quote.
    ///
    /// The base salary the receiver assumes is derived from `player.annualSalary`
    /// rather than `Contract.baseSalary`, because `annualSalary` is the unit the
    /// rest of the game charges against `Team.currentCapUsage`; deriving the
    /// split from it keeps one cap unit and stops the two ledgers drifting.
    ///
    /// Sandbox keeps the old 1:1 behaviour: cap rules are off, so there is no
    /// dead money to eat and the receiver takes the full salary.
    ///
    /// ## Midseason proration (task #26)
    ///
    /// `leagueYearRemaining` is the share of the season still unpaid — 1.0
    /// everywhere except the regular season, where it is
    /// `leagueYearRemaining(phase:week:)`. The base salary splits on it:
    ///
    /// ```
    /// base            = annualSalary − proratedPerYear   (the bonus stays behind)
    /// salaryAssumed   = base × leagueYearRemaining       (buyer: the checks still to come)
    /// salaryRetained  = base − salaryAssumed             (seller: the checks already written)
    /// ```
    ///
    /// The two halves always sum back to `base`, so a trade moves cap charge
    /// between two clubs and never creates or destroys any. The model is the
    /// same shape as the dead-money math directly above it: money already spent
    /// stays with the club that spent it, money still owed follows the player.
    ///
    /// WHY it matters beyond realism: with the full-season charge, a deadline
    /// buyer had to fit twelve months of salary under a cap he had already spent
    /// ten months of — which is why the league market needed
    /// `TradeValueEngine.aiMarketCapSlackFraction` to function at all (1240 of
    /// 1530 candidate deals that had cleared both GMs' VALUE bars died on the
    /// cap check). At the Week 9 deadline the charge is now 10/18 of the base.
    ///
    /// `TradeEngine` writes `salaryAssumed` back into `player.annualSalary`
    /// (the cap ledger and the salary must agree within a league year), and
    /// records the full base in `Player.proratedFullBaseSalary` so
    /// `FreeAgencyEngine.executeNewLeagueYear` restores it at the rollover —
    /// a deadline acquisition is booked at his real number from the next
    /// league year on (task #45).
    static func tradeCapSplit(
        player: Player,
        contract: Contract?,
        capMode: CapMode,
        leagueYearRemaining: Double = 1.0
    ) -> TradeCapSplit {
        let salary = max(0, player.annualSalary)

        guard capMode != .sandbox else {
            return TradeCapSplit(
                deadCap: 0,
                salaryAssumed: salary,
                proratedPerYear: 0,
                salaryRetained: 0
            )
        }

        // Remaining years drive the acceleration, same as a mid-contract cut.
        let years: Int
        let rawDead: Int
        if let contract, contract.totalYears > 0 {
            years = max(1, contract.totalYears - contract.currentYear)
            // Exactly what `calculateDeadCap(for:team:)` returns for a release.
            rawDead = contract.deadCap
        } else {
            years = max(1, player.contractYearsRemaining)
            rawDead = RosterCutEvaluator.deadCap(player: player)
        }

        // Never let the accelerated bonus exceed the money actually left on the
        // deal — a runaway charge would make the AI market unsolvable.
        let deadCap = max(0, min(rawDead, salary * years))
        let proratedPerYear = deadCap / years

        let base = max(0, salary - proratedPerYear)
        let remaining = min(1.0, max(0.0, leagueYearRemaining))
        let assumed = Int((Double(base) * remaining).rounded())

        return TradeCapSplit(
            deadCap: deadCap,
            salaryAssumed: assumed,
            proratedPerYear: proratedPerYear,
            salaryRetained: base - assumed
        )
    }

    // MARK: - Cap Growth

    /// Grows the salary cap by the specified annual rate (default ~5% per year in the NFL).
    /// Updates both the team's `salaryCap` and adjusts `currentCapUsage` proportionally
    /// so that available space is preserved in relative terms.
    ///
    /// - Parameters:
    ///   - team: The team whose cap is being updated.
    ///   - growthRate: Fractional growth rate (e.g., 0.05 for 5%). Clamped to 0-0.25.
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

    /// Cap-mode-aware projection. Sandbox treats cap room as effectively
    /// unlimited so signing UIs never block on availability.
    static func projectedCapSpace(team: Team, rolloverAmount: Int, capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return projectedCapSpace(team: team, rolloverAmount: rolloverAmount)
        case .sandbox:
            return Int.max
        }
    }

    /// True if the team can afford a contract of `cost` thousand dollars under
    /// the active cap mode. Sandbox always returns `true`.
    static func canAfford(team: Team, cost: Int, capMode: CapMode) -> Bool {
        switch capMode {
        case .simple, .realistic:
            return team.availableCap >= cost
        case .sandbox:
            return true
        }
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

    /// Cap-mode-aware salary floor check. Sandbox always returns `true` — there
    /// is no minimum spend requirement when cap rules are off.
    static func isAboveSalaryFloor(team: Team, capMode: CapMode) -> Bool {
        switch capMode {
        case .simple, .realistic:
            return isAboveSalaryFloor(team: team)
        case .sandbox:
            return true
        }
    }

    /// The dollar amount (in thousands) the team must still spend to reach the salary floor.
    /// Returns 0 if the team is already above the floor.
    static func amountBelowFloor(team: Team) -> Int {
        let floorThreshold = Int(Double(team.salaryCap) * 0.89)
        let shortfall = floorThreshold - team.currentCapUsage
        return max(0, shortfall)
    }

    /// Cap-mode-aware version. Sandbox always returns 0.
    static func amountBelowFloor(team: Team, capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return amountBelowFloor(team: team)
        case .sandbox:
            return 0
        }
    }
}
