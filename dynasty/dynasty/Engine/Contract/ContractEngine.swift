import Foundation
import SwiftData

/// Handles all contract operations for both simple and realistic salary-cap modes.
enum ContractEngine {

    // MARK: - Simple Mode

    /// Sign a player in simple cap mode by setting contract length, salary,
    /// assigning the team, and debiting cap space.
    static func signPlayerSimple(player: Player, years: Int, annualSalary: Int, team: Team) {
        player.contractYearsRemaining = years
        player.annualSalary = annualSalary
        player.teamID = team.id
        team.currentCapUsage += annualSalary
    }

    /// Cut a player in simple mode. Frees cap space and removes team assignment.
    static func cutPlayerSimple(player: Player, team: Team) {
        team.currentCapUsage -= player.annualSalary
        player.teamID = nil
        player.contractYearsRemaining = 0
        player.annualSalary = 0
    }

    // MARK: - Sandbox Mode

    /// Sign a player in sandbox cap mode: roster is updated but no cap is debited.
    /// Annual salary is still recorded for UI/display, but the team's cap usage is left alone.
    static func signPlayerSandbox(player: Player, years: Int, annualSalary: Int, team: Team) {
        player.contractYearsRemaining = years
        player.annualSalary = annualSalary
        player.teamID = team.id
        // Intentionally no `team.currentCapUsage` mutation — sandbox ignores cap.
    }

    /// Cut a player in sandbox cap mode without touching cap usage.
    static func cutPlayerSandbox(player: Player) {
        player.teamID = nil
        player.contractYearsRemaining = 0
        player.annualSalary = 0
    }

    // MARK: - Cap-Mode-Aware Wrappers

    /// Sign a player using whichever pathway matches the active cap mode.
    /// Sandbox mode skips all cap accounting and contract bookkeeping.
    static func signPlayer(
        player: Player,
        years: Int,
        annualSalary: Int,
        team: Team,
        capMode: CapMode
    ) {
        switch capMode {
        case .simple, .realistic:
            // Both call paths debit cap usage by `annualSalary`. The realistic-mode
            // entry point that creates a full Contract object lives in
            // `FreeAgencyEngine.signFreeAgent`; this wrapper is for the simple
            // `Player.annualSalary`-only flow.
            signPlayerSimple(player: player, years: years, annualSalary: annualSalary, team: team)
        case .sandbox:
            signPlayerSandbox(player: player, years: years, annualSalary: annualSalary, team: team)
        }
    }

    /// Cut a player using the path that matches the active cap mode.
    /// Sandbox skips dead cap entirely; simple mode frees cap space.
    static func cutPlayer(player: Player, team: Team, capMode: CapMode) {
        switch capMode {
        case .simple, .realistic:
            cutPlayerSimple(player: player, team: team)
        case .sandbox:
            cutPlayerSandbox(player: player)
        }
    }

    /// Estimate the annual market value (in thousands) a player would command
    /// on the open market based on position, age, and overall rating.
    ///
    /// Values are expressed as a percentage of the salary cap, so they scale
    /// naturally as the cap grows each season. The default cap (265_000) matches
    /// the 2026 projection; callers should pass the team's actual `salaryCap`.
    ///
    /// Uses the player's natural position (derived from positionAttributes) for salary
    /// calculation. A player moved from DE to DT still demands DE money.
    static func estimateMarketValue(player: Player, salaryCap: Int = 265_000) -> Int {
        let overall = player.overall
        // Use the higher-paying position: current or natural (players demand pay
        // based on their best position — a DE moved to DT still demands DE money)
        let natural = naturalPositionForAttributes(player.positionAttributes)
        let position = bestPayingPosition(current: player.position, natural: natural)
        let age = player.age

        // Tiered base value as a percentage of the salary cap.
        // Steeper curve at elite level — reflecting how elite talent commands
        // exponentially more money in the real NFL.
        let normalizedOVR = Double(overall)
        let basePercent: Double
        if normalizedOVR >= 95 {
            // True elite: ~9.5% + 0.55% per OVR above 95 (× position → QB ~20%+)
            basePercent = 9.5 + (normalizedOVR - 95.0) * 0.55
        } else if normalizedOVR >= 90 {
            // Elite tier: ~6% + 0.7% per OVR above 90
            basePercent = 6.0 + (normalizedOVR - 90.0) * 0.7
        } else if normalizedOVR >= 80 {
            // Starter tier: ~3% + 0.5% per OVR above 80
            basePercent = 3.0 + (normalizedOVR - 80.0) * 0.5
        } else if normalizedOVR >= 70 {
            // Solid contributor: ~1% + 0.2% per OVR above 70
            basePercent = 1.0 + (normalizedOVR - 70.0) * 0.2
        } else if normalizedOVR >= 60 {
            // Depth/rotational: ~0.4% + 0.06% per OVR above 60
            basePercent = 0.4 + (normalizedOVR - 60.0) * 0.06
        } else {
            // Fringe / practice squad: ~0.28% (minimum)
            basePercent = 0.28
        }

        // Position multiplier calibrated to real NFL 2026 pay scales.
        let positionMultiplier: Double = {
            switch position {
            case .QB:
                return 2.2    // Elite QBs: ~20%+ of cap
            case .WR:
                return 1.3    // WR1: ~11-13%
            case .DE:
                return 1.25   // Edge rushers: ~11-13%
            case .LT:
                return 1.05   // LT: ~8.5-10%
            case .OLB:
                return 1.0    // OLB: ~8-9%
            case .CB:
                return 0.95   // Top CB: ~8-9.5%
            case .DT:
                return 0.9    // Interior DL: ~7-8.5%
            case .RT:
                return 0.85   // RT: ~7-8%
            case .MLB:
                return 0.8    // MLB: ~6-7%
            case .FS, .SS:
                return 0.75   // Safeties: ~5.5-7%
            case .TE:
                return 0.7    // TE: ~4.5-6%
            case .LG, .RG, .C:
                return 0.65   // Interior OL: ~4-5%
            case .RB:
                return 0.45   // RBs devalued: ~3-5%
            case .FB:
                return 0.25   // FB: ~1-2%
            case .K, .P:
                return 0.25   // Specialists: ~1-2%
            }
        }()

        // Convert cap percentage to thousands
        var value = basePercent * positionMultiplier * Double(salaryCap) / 100.0

        // Age adjustment: discount once the player is past peak years
        let peakRange = position.peakAgeRange
        if age > peakRange.upperBound {
            let yearsOver = age - peakRange.upperBound
            let agePenalty = 1.0 - (Double(yearsOver) * 0.10)
            value *= max(agePenalty, 0.3)
        } else if age < peakRange.lowerBound {
            // Young players on rookie-scale pay: slight discount for inexperience
            let yearsUnder = peakRange.lowerBound - age
            let youthDiscount = 1.0 - (Double(yearsUnder) * 0.05)
            value *= max(youthDiscount, 0.6)
        }

        // Floor: every player is worth at least the veteran minimum (~0.28% of cap)
        let minimum = max(Int(0.0028 * Double(salaryCap)), 750)
        return max(Int(value), minimum)
    }

    // MARK: - Realistic Mode

    /// Create a fully detailed contract for realistic cap mode.
    static func createContract(
        playerID: UUID,
        teamID: UUID,
        years: Int,
        baseSalaries: [Int],
        signingBonus: Int,
        guaranteed: Int,
        noTrade: Bool
    ) -> Contract {
        Contract(
            playerID: playerID,
            teamID: teamID,
            totalYears: years,
            currentYear: 0,
            baseSalary: baseSalaries,
            signingBonus: signingBonus,
            guaranteedMoney: guaranteed,
            noTradeClause: noTrade
        )
    }

    // MARK: - Realistic Contract Structures

    /// Generates escalating base salaries for a young player's contract.
    /// Base salary increases ~5-10% per year, rewarding players who grow into the deal.
    static func escalatingBaseSalaries(annualSalary: Int, years: Int) -> [Int] {
        guard years > 0 else { return [] }
        // Start ~15% below the average and escalate ~7% per year
        let startBase = max(Int(Double(annualSalary) * 0.85), 500)
        return (0..<years).map { yearIndex in
            let escalation = pow(1.07, Double(yearIndex))
            return max(Int(Double(startBase) * escalation), 500)
        }
    }

    /// Generates front-loaded base salaries for a veteran's contract.
    /// Higher salary in early years, tapering off in later years.
    static func frontLoadedBaseSalaries(annualSalary: Int, years: Int) -> [Int] {
        guard years > 0 else { return [] }
        // Start 15% above the average, decrease ~8% per year
        let startBase = Int(Double(annualSalary) * 1.15)
        return (0..<years).map { yearIndex in
            let taper = pow(0.92, Double(yearIndex))
            return max(Int(Double(startBase) * taper), 500)
        }
    }

    /// Calculates a realistic signing bonus for a contract.
    /// - Big contracts (>= $10M/yr): 40-60% of first year salary
    /// - Medium contracts ($3-10M/yr): 20-40% of first year salary
    /// - Small contracts (< $3M/yr): 10-20% of first year salary
    static func realisticSigningBonus(annualSalary: Int) -> Int {
        let bonusPercent: Double
        if annualSalary >= 10_000 {
            bonusPercent = Double.random(in: 0.40...0.60)
        } else if annualSalary >= 3_000 {
            bonusPercent = Double.random(in: 0.20...0.40)
        } else {
            bonusPercent = Double.random(in: 0.10...0.20)
        }
        return Int(Double(annualSalary) * bonusPercent)
    }

    /// Calculates realistic guaranteed money for a contract.
    /// First 1-2 years fully guaranteed for big deals, less for smaller ones.
    static func realisticGuaranteedMoney(baseSalaries: [Int], signingBonus: Int) -> Int {
        guard !baseSalaries.isEmpty else { return signingBonus }
        let avgSalary = baseSalaries.reduce(0, +) / baseSalaries.count
        let guaranteedYears: Int
        if avgSalary >= 15_000 {
            guaranteedYears = min(2, baseSalaries.count)
        } else if avgSalary >= 5_000 {
            guaranteedYears = min(2, baseSalaries.count)
        } else {
            guaranteedYears = 1
        }
        let guaranteedBase = baseSalaries.prefix(guaranteedYears).reduce(0, +)
        return guaranteedBase + signingBonus
    }

    /// Build a complete realistic contract with escalating or front-loaded structure.
    /// - Young players (age < 28): escalating salary structure
    /// - Veteran players (age >= 28): front-loaded salary structure
    static func buildRealisticContract(
        playerID: UUID,
        teamID: UUID,
        annualSalary: Int,
        years: Int,
        playerAge: Int,
        noTrade: Bool = false
    ) -> Contract {
        let baseSalaries: [Int]
        if playerAge < 28 {
            baseSalaries = escalatingBaseSalaries(annualSalary: annualSalary, years: years)
        } else {
            baseSalaries = frontLoadedBaseSalaries(annualSalary: annualSalary, years: years)
        }
        let signingBonus = realisticSigningBonus(annualSalary: annualSalary)
        let guaranteed = realisticGuaranteedMoney(baseSalaries: baseSalaries, signingBonus: signingBonus)

        return Contract(
            playerID: playerID,
            teamID: teamID,
            totalYears: years,
            currentYear: 0,
            baseSalary: baseSalaries,
            signingBonus: signingBonus,
            guaranteedMoney: guaranteed,
            noTradeClause: noTrade
        )
    }

    /// Restructure a contract by converting this year's base salary into
    /// signing bonus. Lowers the current cap hit but spreads cost to later years.
    /// Returns a new Contract value with updated figures.
    static func restructureContract(contract: Contract) -> Contract {
        guard contract.currentYear < contract.baseSalary.count else { return contract }

        let currentBase = contract.baseSalary[contract.currentYear]

        // Convert 80% of the current base salary to signing bonus
        let convertedAmount = Int(Double(currentBase) * 0.8)
        let remainingBase = currentBase - convertedAmount

        var updatedSalaries = contract.baseSalary
        updatedSalaries[contract.currentYear] = remainingBase

        let updatedBonus = contract.signingBonus + convertedAmount

        return Contract(
            id: contract.id,
            playerID: contract.playerID,
            teamID: contract.teamID,
            totalYears: contract.totalYears,
            currentYear: contract.currentYear,
            baseSalary: updatedSalaries,
            signingBonus: updatedBonus,
            guaranteedMoney: contract.guaranteedMoney,
            isVoidYears: contract.isVoidYears,
            voidYearsCount: contract.voidYearsCount,
            noTradeClause: contract.noTradeClause,
            franchiseTagged: contract.franchiseTagged
        )
    }

    /// Cut a player in realistic mode. Returns the dead-cap hit the team absorbs.
    /// - Parameters:
    ///   - contract: The player's current contract.
    ///   - team: The team releasing the player.
    ///   - postJune1: If `true`, the dead cap is split across two league years.
    /// - Returns: The dead-cap charge applied in the current year.
    static func cutPlayerRealistic(contract: Contract, team: Team, postJune1: Bool) -> Int {
        let totalDeadCap = contract.deadCap

        let currentYearHit: Int
        if postJune1, contract.totalYears > 0 {
            // Post-June 1: only one year's prorated bonus hits now;
            // the rest accelerates into next year's cap.
            let proratedPerYear = contract.signingBonus / contract.totalYears
            currentYearHit = proratedPerYear
        } else {
            currentYearHit = totalDeadCap
        }

        // Swap the full cap hit for the dead-cap charge
        team.currentCapUsage -= contract.capHit
        team.currentCapUsage += currentYearHit

        return currentYearHit
    }

    /// Cap-mode-aware realistic cut. Sandbox releases the player with zero dead
    /// cap and no cap mutation; realistic and simple defer to the existing path.
    static func cutPlayerRealistic(contract: Contract, team: Team, postJune1: Bool, capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return cutPlayerRealistic(contract: contract, team: team, postJune1: postJune1)
        case .sandbox:
            return 0
        }
    }

    // MARK: - Franchise Tag

    /// Calculate the franchise-tag value for a position: the average of the
    /// top 5 salaries (in thousands) supplied for that position group.
    static func franchiseTagValue(position: Position, topSalaries: [Int]) -> Int {
        let sorted = topSalaries.sorted(by: >)
        let topFive = Array(sorted.prefix(5))
        guard !topFive.isEmpty else { return 0 }
        return topFive.reduce(0, +) / topFive.count
    }

    /// Cap-mode-aware franchise-tag value. Sandbox returns `0` so the UI shows
    /// the tag as costing nothing and no cap accounting is needed.
    static func franchiseTagValue(position: Position, topSalaries: [Int], capMode: CapMode) -> Int {
        switch capMode {
        case .simple, .realistic:
            return franchiseTagValue(position: position, topSalaries: topSalaries)
        case .sandbox:
            return 0
        }
    }

    /// Apply franchise tag to a player. Sets their salary to the tag value
    /// and marks them as franchise-tagged for the season.
    static func applyFranchiseTag(
        player: Player,
        tagValue: Int,
        team: Team
    ) {
        let previousSalary = player.annualSalary

        player.contractYearsRemaining = 1
        player.annualSalary = tagValue
        player.isFranchiseTagged = true

        // Update team cap: remove old salary, add new tag salary
        team.currentCapUsage = team.currentCapUsage - previousSalary + tagValue
    }

    /// Cap-mode-aware franchise-tag application. In sandbox mode the tag is free
    /// and team cap is never touched — the player is just flagged as tagged for
    /// one extra year of team control.
    static func applyFranchiseTag(
        player: Player,
        tagValue: Int,
        team: Team,
        capMode: CapMode
    ) {
        switch capMode {
        case .simple, .realistic:
            applyFranchiseTag(player: player, tagValue: tagValue, team: team)
        case .sandbox:
            player.contractYearsRemaining = 1
            player.annualSalary = 0
            player.isFranchiseTagged = true
        }
    }

    // MARK: - FA Preview

    struct FAPreviewPlayer {
        let playerID: UUID
        let name: String
        let position: Position
        let overall: Int
        let age: Int
        let estimatedSalary: Int  // thousands
        let currentTeamAbbr: String
    }

    /// Preview the top free agents at a given position from other teams,
    /// so the player can compare during roster evaluation.
    static func previewFreeAgents(
        allPlayers: [Player],
        allTeams: [Team],
        playerTeamID: UUID,
        position: Position,
        salaryCap: Int = 265_000,
        limit: Int = 5
    ) -> [FAPreviewPlayer] {
        allPlayers
            .filter { $0.teamID != playerTeamID
                  && $0.contractYearsRemaining <= 1
                  && $0.position == position }
            .sorted { $0.overall > $1.overall }
            .prefix(limit)
            .map { player in
                let teamAbbr = allTeams.first { $0.id == player.teamID }?.abbreviation ?? "FA"
                return FAPreviewPlayer(
                    playerID: player.id,
                    name: player.fullName,
                    position: player.position,
                    overall: player.overall,
                    age: player.age,
                    estimatedSalary: estimateMarketValue(player: player, salaryCap: salaryCap),
                    currentTeamAbbr: teamAbbr
                )
            }
    }

    /// Preview free agents for an array of positions (used for position groups).
    static func previewFreeAgentsForGroup(
        allPlayers: [Player],
        allTeams: [Team],
        playerTeamID: UUID,
        positions: [Position],
        salaryCap: Int = 265_000,
        limit: Int = 5
    ) -> [FAPreviewPlayer] {
        allPlayers
            .filter { $0.teamID != playerTeamID
                  && $0.contractYearsRemaining <= 1
                  && positions.contains($0.position) }
            .sorted { $0.overall > $1.overall }
            .prefix(limit)
            .map { player in
                let teamAbbr = allTeams.first { $0.id == player.teamID }?.abbreviation ?? "FA"
                return FAPreviewPlayer(
                    playerID: player.id,
                    name: player.fullName,
                    position: player.position,
                    overall: player.overall,
                    age: player.age,
                    estimatedSalary: estimateMarketValue(player: player, salaryCap: salaryCap),
                    currentTeamAbbr: teamAbbr
                )
            }
    }

    /// Remove franchise tag from a player. Reverts them to an expiring contract.
    static func removeFranchiseTag(
        player: Player,
        team: Team
    ) {
        let tagSalary = player.annualSalary

        player.isFranchiseTagged = false
        player.contractYearsRemaining = 0
        player.annualSalary = 0

        // Free up the tag salary from team cap
        team.currentCapUsage -= tagSalary
    }

    /// Cap-mode-aware franchise tag removal. Sandbox skips cap refund logic.
    static func removeFranchiseTag(player: Player, team: Team, capMode: CapMode) {
        switch capMode {
        case .simple, .realistic:
            removeFranchiseTag(player: player, team: team)
        case .sandbox:
            player.isFranchiseTagged = false
            player.contractYearsRemaining = 0
            player.annualSalary = 0
        }
    }

    // MARK: - Natural Position Helpers

    /// Derives the natural/primary position from a player's position attributes.
    /// This represents what position group the player was originally built for.
    static func naturalPositionForAttributes(_ attributes: PositionAttributes) -> Position {
        switch attributes {
        case .quarterback(_):     return .QB
        case .runningBack(_):     return .RB
        case .wideReceiver(_):    return .WR
        case .tightEnd(_):        return .TE
        case .offensiveLine(_):   return .LT   // Use LT as the premium OL position
        case .defensiveLine(_):   return .DE   // Use DE as the premium DL position
        case .linebacker(_):      return .OLB  // Use OLB as the premium LB position
        case .defensiveBack(_):   return .CB   // Use CB as the premium DB position
        case .kicking(_):         return .K
        }
    }

    /// Returns whichever position commands more money on the market.
    /// Players demand pay based on their highest-value position.
    static func bestPayingPosition(current: Position, natural: Position) -> Position {
        // Use a simple ranking by position multiplier (higher = more expensive)
        let rank: (Position) -> Double = { pos in
            switch pos {
            case .QB:             return 2.2
            case .WR:             return 1.3
            case .DE:             return 1.25
            case .LT:             return 1.05
            case .OLB:            return 1.0
            case .CB:             return 0.95
            case .DT:             return 0.9
            case .RT:             return 0.85
            case .MLB:            return 0.8
            case .FS, .SS:        return 0.75
            case .TE:             return 0.7
            case .LG, .RG, .C:   return 0.65
            case .RB:             return 0.45
            case .FB:             return 0.25
            case .K, .P:         return 0.25
            }
        }
        return rank(current) >= rank(natural) ? current : natural
    }
}
