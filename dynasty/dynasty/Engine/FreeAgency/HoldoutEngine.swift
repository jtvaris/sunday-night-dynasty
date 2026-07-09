import Foundation
import SwiftData

/// Detects sub-market signed players and orchestrates holdout flow
/// (FA Drama brief, B6).
///
/// Heuristics:
/// - Holdout candidate: actual salary < market value * 0.85.
/// - Resolutions:
///   - `.extend`        : extend contract -> always succeeds (handled elsewhere).
///   - `.signingBonus`  : pay a one-time bonus -> always succeeds.
///   - `.forceTrade`    : capitulate, trade away -> resolves but with PR cost.
///   - `.mediation`     : 75% chance to resolve (random).
@MainActor
enum HoldoutEngine {

    /// Sub-market threshold: salary below 85% of estimated market value triggers holdout candidacy.
    static let subMarketThreshold: Double = 0.85

    /// Mediation success probability (0.0...1.0).
    static let mediationSuccessRate: Double = 0.75

    /// Holdout resolution path requested by the front office.
    enum Resolution {
        case extend
        case signingBonus
        case forceTrade
        case mediation
    }

    /// Detects players whose contracts are sub-market by 15%+.
    /// - Parameters:
    ///   - roster: The team's current roster.
    ///   - marketValues: Per-player estimated market value (in thousands).
    static func detectHoldoutCandidates(
        roster: [Player],
        marketValues: [UUID: Int]
    ) -> [Player] {
        return roster.filter { player in
            guard let market = marketValues[player.id], market > 0 else { return false }
            // Need at least 1 year remaining; expiring contracts go through normal FA.
            guard player.contractYearsRemaining > 0 else { return false }
            // Salary must be at least sub-market threshold below market.
            return Double(player.annualSalary) < Double(market) * subMarketThreshold
        }
    }

    /// R22: detects STAR players who may hold out at OTAs / start of season.
    ///
    /// A star is OVR >= 85 OR one of the team's top-3 players by overall.
    /// The star holds out when either:
    /// - the contract is expiring (exactly 1 year left), or
    /// - the player is clearly underpaid (salary < 85% of market) with 3+
    ///   years as a pro (players still on rookie deals accept them).
    /// Franchise-tagged players never hold out (the tag binds them) and a
    /// player already holding out is not detected twice.
    static func detectStarHoldoutCandidates(
        roster: [Player],
        marketValues: [UUID: Int]
    ) -> [Player] {
        let topThreeIDs = Set(
            roster.sorted { $0.overall > $1.overall }.prefix(3).map(\.id)
        )
        return roster
            .filter { player in
                guard !player.isFranchiseTagged, !player.isHoldingOut, !player.isInjured else { return false }
                guard let market = marketValues[player.id], market > 0 else { return false }

                let isStar = player.overall >= 85 || topThreeIDs.contains(player.id)
                guard isStar else { return false }

                let expiring = player.contractYearsRemaining == 1
                let underpaid = player.yearsPro >= 3
                    && player.contractYearsRemaining > 0
                    && Double(player.annualSalary) < Double(market) * subMarketThreshold
                return expiring || underpaid
            }
            // Biggest pay gap first — the angriest star leads the drama.
            .sorted {
                let gapA = (marketValues[$0.id] ?? 0) - $0.annualSalary
                let gapB = (marketValues[$1.id] ?? 0) - $1.annualSalary
                return gapA > gapB
            }
    }

    /// Initiates a holdout for a player. Returns the persisted Holdout record,
    /// or `nil` if a save error occurs. R22: flags the player as holding out
    /// so simulation, development and UI all see the same state.
    static func startHoldout(
        player: Player,
        teamID: UUID,
        subMarketDelta: Int,
        modelContext: ModelContext
    ) -> Holdout? {
        let holdout = Holdout(
            playerID: player.id,
            teamID: teamID,
            subMarketDelta: subMarketDelta
        )
        player.isHoldingOut = true
        modelContext.insert(holdout)
        do {
            try modelContext.save()
            return holdout
        } catch {
            player.isHoldingOut = false
            return nil
        }
    }

    /// Resolves a holdout and persists the outcome. Returns `true` on success.
    /// R22: pass the player so a successful resolution clears `isHoldingOut`.
    @discardableResult
    static func resolveHoldout(
        holdout: Holdout,
        resolution: Resolution,
        player: Player? = nil,
        modelContext: ModelContext
    ) -> Bool {
        let success: Bool
        let mappedResolution: HoldoutResolution

        switch resolution {
        case .extend:
            success = true
            mappedResolution = .extended
        case .signingBonus:
            success = true
            mappedResolution = .bonusGiven
        case .forceTrade:
            success = true
            mappedResolution = .traded
        case .mediation:
            success = Double.random(in: 0...1) < mediationSuccessRate
            mappedResolution = success ? .extended : .unresolved
        }

        if success {
            holdout.resolvedAt = Date()
            holdout.resolution = mappedResolution
            player?.isHoldingOut = false
        } else {
            holdout.resolution = .unresolved
        }

        try? modelContext.save()
        return success
    }
}
