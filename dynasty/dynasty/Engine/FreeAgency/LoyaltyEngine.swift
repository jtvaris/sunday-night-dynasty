import Foundation

/// Computes loyalty discounts and let-walk media penalties for veteran free
/// agents who have spent multiple consecutive seasons on a single team
/// (FA Drama brief, B2).
///
/// Heuristics:
/// - 4+ seasons on the same team -> 10% discount  (factor 0.90).
/// - 6+ seasons on the same team -> 15% discount  (factor 0.85).
/// - Letting a 4+ year vet walk hits ownerTrust by -5 and fanMood by -10.
/// - 6+ year vet walking hits harder: ownerTrust -10, fanMood -15.
enum LoyaltyEngine {

    /// Minimum seasons on team to qualify for any loyalty discount.
    static let loyaltyThresholdYears: Int = 4

    /// Threshold for "legend" tier (deeper discount, harder media penalty).
    static let legendThresholdYears: Int = 6

    /// Returns a multiplicative discount factor on the player's asking price
    /// when re-signing a loyal vet on the same team.
    /// - 4-5 yrs same team -> 0.90
    /// - 6+ yrs same team  -> 0.85
    /// - otherwise         -> 1.0
    static func loyaltyDiscount(player: Player, currentTeamID: UUID?) -> Double {
        // Discount only applies to the team the player has been loyal *to*.
        guard let team = currentTeamID, player.teamID == team else { return 1.0 }
        if player.loyaltyYears >= legendThresholdYears { return 0.85 }
        if player.loyaltyYears >= loyaltyThresholdYears { return 0.90 }
        return 1.0
    }

    /// Owner trust + fan mood deltas applied when the team lets a loyal vet
    /// walk in free agency (i.e. doesn't re-sign).
    static func letWalkPenalty(player: Player) -> (ownerTrust: Int, fanMood: Int) {
        if player.loyaltyYears >= legendThresholdYears {
            return (ownerTrust: -10, fanMood: -15)
        }
        if player.loyaltyYears >= loyaltyThresholdYears {
            return (ownerTrust: -5, fanMood: -10)
        }
        return (ownerTrust: 0, fanMood: 0)
    }

    /// Builds a "disrespected legend" storyline event when a loyal vet walks.
    /// Returns `nil` when the player doesn't meet the loyalty threshold.
    static func generateLetWalkEvent(player: Player) -> FAStorylineEvent? {
        guard player.loyaltyYears >= loyaltyThresholdYears else { return nil }

        let isLegend = player.loyaltyYears >= legendThresholdYears
        let headline = isLegend
            ? "\(player.fullName): legendary run cut short"
            : "\(player.fullName) walks after \(player.loyaltyYears) years"
        let body = isLegend
            ? "Fans are stunned. \(player.loyaltyYears)-year vet \(player.lastName) hits the open market — front office takes the heat."
            : "After \(player.loyaltyYears) loyal seasons, the team passed on a hometown discount. The locker room is watching."

        let seasonYear = Calendar.current.component(.year, from: Date())
        return FAStorylineEvent(
            seasonYear: seasonYear,
            type: .loyaltyDiscount,
            playerID: player.id,
            teamID: player.teamID,
            headline: headline,
            body: body
        )
    }
}
