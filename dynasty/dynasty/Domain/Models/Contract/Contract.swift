import Foundation
import SwiftData

/// Detailed contract model used in realistic cap mode.
/// Tracks per-year base salaries, signing bonuses, guaranteed money,
/// void years, and franchise tag status.
@Model
final class Contract {

    var id: UUID
    var playerID: UUID
    var teamID: UUID

    /// Total number of years on the contract (excluding void years).
    var totalYears: Int

    /// Zero-based index of the current contract year.
    var currentYear: Int

    /// Base salary for each year of the contract, in thousands.
    /// The array count should equal `totalYears`.
    var baseSalary: [Int]

    /// Total signing bonus in thousands, prorated evenly across `totalYears`.
    var signingBonus: Int

    /// Total guaranteed money in thousands.
    var guaranteedMoney: Int

    /// Whether the contract includes void years used to spread cap hits.
    var isVoidYears: Bool

    /// Number of void years appended to the contract for cap proration.
    var voidYearsCount: Int

    /// Player cannot be traded without consent.
    var noTradeClause: Bool

    /// Player is playing under the franchise tag this season.
    var franchiseTagged: Bool

    // MARK: - Computed Properties

    /// Current-year cap hit: this year's base salary + prorated signing bonus.
    var capHit: Int {
        let base = currentYear < baseSalary.count ? baseSalary[currentYear] : 0
        let proratedBonus = totalYears > 0 ? signingBonus / totalYears : 0
        return base + proratedBonus
    }

    /// Dead cap if the player is cut: remaining prorated signing bonus
    /// for all future years (including the current year).
    var deadCap: Int {
        guard totalYears > 0 else { return 0 }
        let proratedPerYear = signingBonus / totalYears
        let remainingYears = totalYears - currentYear
        return proratedPerYear * remainingYears
    }

    /// Total contract value: sum of all base salaries + signing bonus.
    var totalValue: Int {
        baseSalary.reduce(0, +) + signingBonus
    }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        playerID: UUID,
        teamID: UUID,
        totalYears: Int,
        currentYear: Int = 0,
        baseSalary: [Int],
        signingBonus: Int = 0,
        guaranteedMoney: Int = 0,
        isVoidYears: Bool = false,
        voidYearsCount: Int = 0,
        noTradeClause: Bool = false,
        franchiseTagged: Bool = false
    ) {
        self.id = id
        self.playerID = playerID
        self.teamID = teamID
        self.totalYears = totalYears
        self.currentYear = currentYear
        self.baseSalary = baseSalary
        self.signingBonus = signingBonus
        self.guaranteedMoney = guaranteedMoney
        self.isVoidYears = isVoidYears
        self.voidYearsCount = voidYearsCount
        self.noTradeClause = noTradeClause
        self.franchiseTagged = franchiseTagged
    }
}
