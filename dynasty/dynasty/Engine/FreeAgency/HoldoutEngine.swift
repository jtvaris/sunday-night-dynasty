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

    /// Initiates a holdout for a player. Returns the persisted Holdout record,
    /// or `nil` if a save error occurs.
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
        modelContext.insert(holdout)
        do {
            try modelContext.save()
            return holdout
        } catch {
            return nil
        }
    }

    /// Resolves a holdout and persists the outcome. Returns `true` on success.
    @discardableResult
    static func resolveHoldout(
        holdout: Holdout,
        resolution: Resolution,
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
        } else {
            holdout.resolution = .unresolved
        }

        try? modelContext.save()
        return success
    }
}
