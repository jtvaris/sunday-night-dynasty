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

    /// Estimate the annual market value (in thousands) a player would command
    /// on the open market based on position, age, and overall rating.
    static func estimateMarketValue(player: Player) -> Int {
        let overall = player.overall
        let position = player.position
        let age = player.age

        // Base value from overall rating (exponential curve rewards elite talent)
        var value: Double = pow(Double(overall) / 100.0, 2.5) * 30_000

        // Position multiplier: QBs get the largest premium
        let positionMultiplier: Double = {
            switch position {
            case .QB:
                return 1.8
            case .DE, .CB:
                return 1.3
            case .WR:
                return 1.25
            case .OLB:
                return 1.2
            case .LT:
                return 1.15
            case .DT, .FS, .SS:
                return 1.1
            case .TE, .MLB:
                return 1.05
            case .RB:
                return 0.9
            case .LG, .RG, .C, .RT:
                return 0.95
            case .FB:
                return 0.7
            case .K, .P:
                return 0.6
            }
        }()
        value *= positionMultiplier

        // Age adjustment: discount once the player is past peak years
        let peakRange = position.peakAgeRange
        if age > peakRange.upperBound {
            let yearsOver = age - peakRange.upperBound
            let agePenalty = 1.0 - (Double(yearsOver) * 0.08)
            value *= max(agePenalty, 0.3)
        } else if age < peakRange.lowerBound {
            // Young players on rookie-scale pay: slight discount for inexperience
            let yearsUnder = peakRange.lowerBound - age
            let youthDiscount = 1.0 - (Double(yearsUnder) * 0.04)
            value *= max(youthDiscount, 0.6)
        }

        // Floor: every player is worth at least the veteran minimum
        return max(Int(value), 750)
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

    // MARK: - Franchise Tag

    /// Calculate the franchise-tag value for a position: the average of the
    /// top 5 salaries (in thousands) supplied for that position group.
    static func franchiseTagValue(position: Position, topSalaries: [Int]) -> Int {
        let sorted = topSalaries.sorted(by: >)
        let topFive = Array(sorted.prefix(5))
        guard !topFive.isEmpty else { return 0 }
        return topFive.reduce(0, +) / topFive.count
    }
}
