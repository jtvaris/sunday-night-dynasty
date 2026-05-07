import Foundation
import SwiftData

/// Computes "frenzy heat" tier per free agent based on the volume of competing
/// offers and visits. Heat drives salary inflation in the bidding market.
///
/// Heuristic (from FA Drama design brief, A2):
/// - count <= 2 → cool       (-10% salary inflation)
/// - count 3-5 → yellow      ( 0% inflation)
/// - count 6-9 → red         (+15% inflation)
/// - count >= 10  OR (count >= 6 AND active visit) → burning (+30% inflation)
@MainActor
enum BiddingHeatEngine {

    /// Computes heat tier for a free agent based on bidding activity.
    /// - Parameters:
    ///   - playerID: Player whose heat we are computing.
    ///   - currentDay: Current FA cycle day (1-N). Heat softens late in cycle if no new entrants.
    ///   - bids: All FABids in the system (we'll filter to this player).
    ///   - visits: All FAVisits in the system (we'll filter to this player).
    static func computeHeat(
        playerID: UUID,
        currentDay: Int,
        bids: [FABid],
        visits: [FAVisit]
    ) -> FrenzyHeatTier {
        let playerBids = bids.filter { $0.playerID == playerID && $0.status != .expired }
        let uniqueBidderCount = Set(playerBids.map { $0.teamID }).count

        let activeVisitsForPlayer = visits.filter {
            $0.playerID == playerID && $0.status == .active
        }
        let hasActiveVisit = !activeVisitsForPlayer.isEmpty

        // Late-cycle dampening: after day 5, drop one tier if no fresh activity
        // (no bid in the last 24h). Keeps heat from staying burning forever.
        let now = Date()
        let recentBids = playerBids.filter {
            now.timeIntervalSince($0.submittedAt) <= 24 * 60 * 60
        }
        let isStale = currentDay > 5 && recentBids.isEmpty && !hasActiveVisit

        // Base tier from bidder count
        var tier: FrenzyHeatTier
        switch uniqueBidderCount {
        case ...2:
            tier = .cool
        case 3...5:
            tier = .yellow
        case 6...9:
            tier = .red
        default: // >= 10
            tier = .burning
        }

        // Bump to burning when 6+ teams chase a player who has an active visit
        if uniqueBidderCount >= 6 && hasActiveVisit {
            tier = .burning
        }

        // Late-cycle decay
        if isStale {
            tier = decay(tier)
        }

        return tier
    }

    /// Returns the inflation factor for a given heat tier.
    /// Pulled from `FrenzyHeatTier.inflationModifier` (defined in Domain layer).
    static func inflationFactor(for tier: FrenzyHeatTier) -> Double {
        tier.inflationModifier
    }

    // MARK: - Private

    private static func decay(_ tier: FrenzyHeatTier) -> FrenzyHeatTier {
        switch tier {
        case .burning: return .red
        case .red:     return .yellow
        case .yellow:  return .cool
        case .cool:    return .cool
        }
    }
}
