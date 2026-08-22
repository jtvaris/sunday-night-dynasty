import Foundation
import SwiftData

// MARK: - Contract Year Detail

/// Breakdown of a single contract year for display purposes.
struct ContractYearDetail: Identifiable {
    let id = UUID()
    let yearNumber: Int          // 1-based year of the contract
    let baseSalary: Int          // In thousands
    let proratedBonus: Int       // In thousands (signing bonus / totalYears)
    let capHit: Int              // baseSalary + proratedBonus
    let deadCapIfCut: Int        // Remaining prorated bonus from this year onward
}

/// Detailed contract model used in realistic cap mode.
/// Tracks per-year base salaries, signing bonuses, guaranteed money,
/// void years, and franchise tag status.
@Model
final class Contract {

    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    #Index<Contract>([\.careerID])

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

    /// **Guaranteed base salary, year by year** — the half of `guaranteedMoney`
    /// that is not the signing bonus.
    ///
    /// Derived, not stored, and deliberately so: `guaranteedMoney` is already
    /// persisted and `ContractEngine.realisticGuaranteedMoney` already builds it
    /// as *`signingBonus` + the first N base salaries*, so the year map is
    /// recoverable exactly by walking the schedule and absorbing the pool from
    /// year one. A second stored column would be a migration, a second source of
    /// truth, and a chance for the two to disagree about the same deal.
    ///
    /// Guarantees run from the FRONT of a contract because that is the only
    /// place a club will write them: a guarantee in year four is a guarantee the
    /// club will never reach, and no agent counts one.
    var guaranteedBaseByYear: [Int] {
        guard totalYears > 0 else { return [] }
        var pool = Swift.max(0, guaranteedMoney - signingBonus)
        return (0..<totalYears).map { yearIndex in
            let base = yearIndex < baseSalary.count ? baseSalary[yearIndex] : 0
            let locked = Swift.min(pool, Swift.max(0, base))
            pool -= locked
            return locked
        }
    }

    /// **Dead cap if the player is cut right now** — remaining prorated signing
    /// bonus *plus the guaranteed base salary the club still owes him*.
    ///
    /// ## Why the second term exists (F-61)
    ///
    /// It did not until now: this returned the bonus acceleration alone, which
    /// meant `guaranteedMoney` was a number the game stored, displayed and
    /// negotiated over while changing nothing whatsoever. A 90 %-guaranteed deal
    /// and a 20 %-guaranteed deal at the same salary cost a club exactly the same
    /// to walk away from, so there was no reason for any GM — user or AI — to
    /// care which one he signed, and no way for a contract to be the thing that
    /// wrecks a franchise.
    ///
    /// A guarantee is precisely the promise that survives the club changing its
    /// mind. Charging it here is what turns guaranteed money into the mechanism
    /// that PRODUCES dead money, which is the coupling D2's per-year dead-money
    /// ledger was built for (`CapManagementEngine.bookDeadMoney`): a release with
    /// three or more years left now splits a charge that is finally large enough
    /// to hurt across two league years.
    ///
    /// **It decays, and fast.** Only guarantees from `currentYear` forward are
    /// owed — money already paid is not dead money. Because guarantees run from
    /// the front of the deal (see ``guaranteedBaseByYear``), the pain is
    /// concentrated in the first year or two and is gone by the middle of the
    /// contract. That is the real shape: the mistake you cannot escape is the one
    /// you made last winter, not the one you made three years ago.
    ///
    /// The result is bounded by the money actually left on the deal — a club can
    /// never owe more for cutting a man than for keeping him.
    var deadCap: Int {
        deadCapIfCut(atYear: currentYear)
    }

    /// The charge for releasing this man at the START of `yearIndex`.
    ///
    /// Split out of ``deadCap`` because ``yearlyBreakdown`` needs the same
    /// arithmetic for every year of the deal and used to spell its own copy of
    /// it — the exact class of drift where the contract card and the cut sheet
    /// quote different numbers for the same release.
    func deadCapIfCut(atYear yearIndex: Int) -> Int {
        guard totalYears > 0 else { return 0 }
        let year = Swift.max(0, Swift.min(yearIndex, totalYears))
        let proratedPerYear = signingBonus / totalYears
        let acceleratedBonus = proratedPerYear * (totalYears - year)
        let owedGuarantee = guaranteedBaseByYear.dropFirst(year).reduce(0, +)

        // Never more than what keeping him would have cost. Without this a
        // pathological row (a guarantee larger than the schedule that backs it,
        // which a hand-written or legacy contract can carry) would make cutting
        // strictly worse than paying, and `CapManagementEngine.tradeCapSplit`
        // would be clamping a number this type should never have produced.
        let remainingObligation = baseSalary.dropFirst(year).reduce(0, +) + acceleratedBonus
        return Swift.max(0, Swift.min(acceleratedBonus + owedGuarantee, remainingObligation))
    }

    /// Total contract value: sum of all base salaries + signing bonus.
    var totalValue: Int {
        baseSalary.reduce(0, +) + signingBonus
    }

    /// Full year-by-year breakdown of the contract for UI display.
    var yearlyBreakdown: [ContractYearDetail] {
        guard totalYears > 0 else { return [] }
        let proratedPerYear = signingBonus / totalYears

        return (0..<totalYears).map { yearIndex in
            let base = yearIndex < baseSalary.count ? baseSalary[yearIndex] : 0
            let yearCapHit = base + proratedPerYear

            return ContractYearDetail(
                yearNumber: yearIndex + 1,
                baseSalary: base,
                proratedBonus: proratedPerYear,
                capHit: yearCapHit,
                // One arithmetic, one place: the year-by-year card and the cut
                // sheet read the same guarantee-aware charge (F-61).
                deadCapIfCut: deadCapIfCut(atYear: yearIndex)
            )
        }
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

// MARK: - Contract Incentives (TODO §5.5)

/// A performance category a contract can put a bonus on.
///
/// Every case is backed by something the game actually records, so a clause can
/// never be un-gradeable: the production tiers read `SeasonStatLine` (the same
/// value type the live box score accumulates into and the career table renders),
/// availability reads the games counter, and the playoff clause reads whether
/// the player's postseason happened at all.
///
/// **Two categories are deliberately absent.** `snapsPlayed` and punting have no
/// box-score source in the sim (`PlayerGameStats` tracks neither — see
/// `SeasonStatLine`'s note), so a snap-count clause on a guard would grade off
/// synthesized numbers for the user's own roster and off nothing at all mid-season.
/// Linemen and punters get availability and the playoff berth instead, which is
/// what their real contracts lean on anyway.
enum IncentiveCategory: String, Codable, CaseIterable, Identifiable {
    /// Games active — the availability clause almost every real deal carries.
    case gamesPlayed
    case passYards
    case passTDs
    case rushYards
    case rushTDs
    case receptions
    case recYards
    case recTDs
    case tackles
    case sacks
    /// Interceptions CAUGHT (never picks thrown — no agent signs that clause).
    case interceptions
    case fieldGoals
    /// Binary: the team reached the postseason.
    case playoffBerth

    var id: String { rawValue }

    /// Label used on the clause row and in agent dialogue.
    var displayName: String {
        switch self {
        case .gamesPlayed:   return "Games Played"
        case .passYards:     return "Passing Yards"
        case .passTDs:       return "Passing TDs"
        case .rushYards:     return "Rushing Yards"
        case .rushTDs:       return "Rushing TDs"
        case .receptions:    return "Receptions"
        case .recYards:      return "Receiving Yards"
        case .recTDs:        return "Receiving TDs"
        case .tackles:       return "Tackles"
        case .sacks:         return "Sacks"
        case .interceptions: return "Interceptions"
        case .fieldGoals:    return "Field Goals Made"
        case .playoffBerth:  return "Playoff Berth"
        }
    }

    /// Compact label for the progress rows on the contract card.
    var shortName: String {
        switch self {
        case .gamesPlayed:   return "GP"
        case .passYards:     return "Pass Yds"
        case .passTDs:       return "Pass TD"
        case .rushYards:     return "Rush Yds"
        case .rushTDs:       return "Rush TD"
        case .receptions:    return "Rec"
        case .recYards:      return "Rec Yds"
        case .recTDs:        return "Rec TD"
        case .tackles:       return "Tkl"
        case .sacks:         return "Sacks"
        case .interceptions: return "INT"
        case .fieldGoals:    return "FG"
        case .playoffBerth:  return "Playoffs"
        }
    }

    /// True when the clause is a yes/no event rather than a counting tier.
    var isBinary: Bool { self == .playoffBerth }

    /// Half-sacks are real football; everything else counts in whole units.
    var allowsHalfSteps: Bool { self == .sacks }

    /// What the player has banked so far in this category.
    ///
    /// `gamesPlayed` and the playoff berth are not in `SeasonStatLine` (one is a
    /// counter on the roster row, the other is a fact about the team), so they
    /// are passed in rather than read out of the line.
    func achieved(line: SeasonStatLine, gamesPlayed: Int, reachedPlayoffs: Bool) -> Double {
        switch self {
        case .gamesPlayed:   return Double(gamesPlayed)
        case .passYards:     return Double(line.passYards)
        case .passTDs:       return Double(line.passTDs)
        case .rushYards:     return Double(line.rushYards)
        case .rushTDs:       return Double(line.rushTDs)
        case .receptions:    return Double(line.receptions)
        case .recYards:      return Double(line.recYards)
        case .recTDs:        return Double(line.recTDs)
        case .tackles:       return Double(line.tackles)
        case .sacks:         return line.sacks
        case .interceptions: return Double(line.defInts)
        case .fieldGoals:    return Double(line.fieldGoalsMade)
        case .playoffBerth:  return reachedPlayoffs ? 1 : 0
        }
    }

    /// Renders a threshold or a running total for display.
    func format(_ value: Double) -> String {
        if isBinary { return value >= 1 ? "Yes" : "No" }
        if allowsHalfSteps {
            return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
        }
        return String(Int(value.rounded()))
    }

    /// The clause menu a player at this position can actually be offered.
    /// Ordered most-negotiated first, because the offer builder shows the top
    /// three by default.
    static func menu(for position: Position) -> [IncentiveCategory] {
        switch position {
        case .QB:
            return [.passYards, .passTDs, .gamesPlayed, .playoffBerth]
        case .RB, .FB:
            return [.rushYards, .rushTDs, .receptions, .gamesPlayed, .playoffBerth]
        case .WR, .TE:
            return [.recYards, .receptions, .recTDs, .gamesPlayed, .playoffBerth]
        case .LT, .LG, .C, .RG, .RT:
            // No snap-count source in the sim — availability is the lineman's clause.
            return [.gamesPlayed, .playoffBerth]
        case .DE, .DT:
            return [.sacks, .tackles, .gamesPlayed, .playoffBerth]
        case .OLB, .MLB:
            return [.tackles, .sacks, .interceptions, .gamesPlayed, .playoffBerth]
        case .CB, .FS, .SS:
            // Tackles rather than pass breakups: the sim only credits a
            // deflection on a targeted throw, so a corner good enough to stop
            // being thrown at would be punished by his own clause.
            return [.interceptions, .tackles, .gamesPlayed, .playoffBerth]
        case .K:
            return [.fieldGoals, .gamesPlayed, .playoffBerth]
        case .P:
            return [.gamesPlayed, .playoffBerth]
        }
    }
}

/// One negotiated performance clause on a contract.
///
/// `id` is derived rather than stored so the value stays cleanly `Codable` and
/// two structurally identical clauses compare equal — a package never carries
/// the same category twice, which is what makes the category the identity.
struct ContractIncentive: Codable, Equatable, Identifiable {

    var category: IncentiveCategory

    /// The tier that has to be reached. Fractional only for sacks.
    var threshold: Double

    /// What it pays when earned, in thousands — the same unit as every other
    /// money field on a contract.
    var bonusK: Int

    var id: String { category.rawValue }

    init(category: IncentiveCategory, threshold: Double, bonusK: Int) {
        self.category = category
        self.threshold = threshold
        self.bonusK = max(0, bonusK)
    }

    /// One-line summary: "1,200 Rushing Yards — $600K".
    var summary: String {
        if category.isBinary {
            return "\(category.displayName) — \(Self.money(bonusK))"
        }
        return "\(category.format(threshold)) \(category.displayName) — \(Self.money(bonusK))"
    }

    static func money(_ thousands: Int) -> String {
        thousands >= 1_000
            ? String(format: "$%.1fM", Double(thousands) / 1_000.0)
            : "$\(thousands)K"
    }
}

/// How far along one clause is, for the contract card and the settlement.
struct IncentiveProgress: Identifiable {
    let incentive: ContractIncentive
    /// What the player has banked in the clause's category so far.
    let achieved: Double

    var id: String { incentive.id }
    var isEarned: Bool { achieved >= incentive.threshold }
    /// 0…1, clamped — the progress bar's width.
    var fraction: Double {
        guard incentive.threshold > 0 else { return isEarned ? 1 : 0 }
        return min(1.0, max(0.0, achieved / incentive.threshold))
    }
}

// MARK: - Incentive Package Store

/// Where a player's agreed incentive clauses live.
///
/// **Why not a column on `Contract`.** Detailed `Contract` rows only ever exist
/// in realistic cap mode — `FreeAgencyEngine.signFreeAgent` is the single place
/// that inserts one, and its `.simple` and `.sandbox` branches write the deal
/// straight onto `Player.contractYearsRemaining` / `annualSalary` instead. A
/// clause the user negotiated on the extension screen has to survive in every
/// mode, so hanging the package off a row that two thirds of saves never create
/// would have shipped a feature that silently does nothing in the default mode.
///
/// So the package rides in career-scoped `UserDefaults`, exactly like
/// `NegotiationLockRegistry` next door: no new SwiftData model, no schema
/// registration, no migration, and the same `careerID` namespacing every other
/// piece of career state got in the multi-save wave. One key per save holds a
/// `[playerID: [ContractIncentive]]` map.
enum ContractIncentiveRegistry {

    /// Base key — namespaced per save through `CareerScopedDefaults.key`, and
    /// listed in `CareerScopedDefaults.keys` so deleting a save purges it.
    static let defaultsKey = "contractIncentivePackages"

    // MARK: Reads

    /// The clauses on this player's current deal (empty when he has none).
    static func incentives(for player: Player) -> [ContractIncentive] {
        guard let careerID = player.careerID else { return [] }
        return map(careerID: careerID)[player.id.uuidString] ?? []
    }

    /// Whether the player is playing on any incentive at all — the cheap test
    /// the motivation link and the UI both start from.
    static func hasIncentives(for player: Player) -> Bool {
        !incentives(for: player).isEmpty
    }

    /// Every package in one save, keyed by `player.id.uuidString`.
    ///
    /// `incentives(for:)` decodes the whole table on every call, which is the
    /// right trade for a contract card and the wrong one for a league-wide pass:
    /// the rollover settlement walks ~2 000 players and only a handful of them
    /// ever carry a clause. It reads the table once through here and skips
    /// straight out when it comes back empty (the overwhelmingly common case —
    /// only the user negotiates clauses).
    static func allPackages(careerID: UUID) -> [String: [ContractIncentive]] {
        map(careerID: careerID)
    }

    // MARK: Writes

    /// Replaces the player's package. An empty array clears him out of the map
    /// rather than storing an empty entry.
    static func set(_ incentives: [ContractIncentive], for player: Player) {
        guard let careerID = player.careerID else { return }
        var table = map(careerID: careerID)
        if incentives.isEmpty {
            table.removeValue(forKey: player.id.uuidString)
        } else {
            table[player.id.uuidString] = incentives
        }
        write(table, careerID: careerID)
    }

    /// Drops the package — a cut, a trade to a club that did not take the
    /// clauses, or a contract that ran out.
    static func clear(for player: Player) {
        set([], for: player)
    }

    /// Drops every package in one save (paired with `CareerScopedDefaults.purge`).
    static func purge(careerID: UUID) {
        UserDefaults.standard.removeObject(
            forKey: CareerScopedDefaults.key(defaultsKey, careerID: careerID)
        )
    }

    // MARK: Storage

    private static func map(careerID: UUID) -> [String: [ContractIncentive]] {
        let key = CareerScopedDefaults.key(defaultsKey, careerID: careerID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let table = try? JSONDecoder().decode([String: [ContractIncentive]].self, from: data) else {
            return [:]
        }
        return table
    }

    private static func write(_ table: [String: [ContractIncentive]], careerID: UUID) {
        let key = CareerScopedDefaults.key(defaultsKey, careerID: careerID)
        guard let data = try? JSONEncoder().encode(table) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
