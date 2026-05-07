import Foundation

/// Computes city-loyalty / season-ticket bonuses for "civic face" free agents
/// and emits community-event storylines (FA Drama brief, B8).
///
/// `Player.civicTier` is an integer 0-3:
/// - 0: no special civic engagement
/// - 1: known charitable presence -> small bump
/// - 2: prominent community face   -> moderate bump
/// - 3: top-tier civic icon        -> headline-level bump
enum CommunityImpactEngine {

    /// Lookup of civic tier -> (fanMood delta, season ticket sales delta).
    /// Ticket sales are in raw seat counts (0-1000) per the design intent.
    private static let tierBonuses: [Int: (fanMood: Int, ticketSales: Int)] = [
        0: (0, 0),
        1: (3, 250),
        2: (6, 600),
        3: (10, 1000)
    ]

    /// Returns the (fanMood, ticketSales) bonus pair when a civic-tagged player signs.
    /// Out-of-range tiers clamp to 0...3.
    static func civicTierBonus(player: Player) -> (fanMood: Int, ticketSales: Int) {
        let tier = max(0, min(3, player.civicTier))
        return tierBonuses[tier] ?? (0, 0)
    }

    /// Generates a community-event storyline (typically the press release / charity announcement).
    /// Returns `nil` for civicTier 0 since there's nothing newsworthy.
    static func generateCommunityEvent(
        player: Player,
        teamID: UUID,
        cityName: String
    ) -> FAStorylineEvent? {
        let tier = max(0, min(3, player.civicTier))
        guard tier > 0 else { return nil }

        let headline: String
        let body: String
        switch tier {
        case 1:
            headline = "\(player.lastName) joins \(cityName) — pledges youth camp"
            body = "Local roots matter. \(player.fullName) plans a youth football camp in \(cityName) next offseason."
        case 2:
            headline = "\(player.fullName) becomes a \(cityName) civic face"
            body = "Charity dinners, school visits, neighborhood appearances. \(player.lastName) is doubling down on \(cityName)."
        default: // tier 3
            headline = "\(player.fullName) signs with \(cityName) — community icon"
            body = "Beyond the field: \(player.lastName) launches a \(cityName) foundation. Season-ticket inquiries surge."
        }

        let seasonYear = Calendar.current.component(.year, from: Date())
        return FAStorylineEvent(
            seasonYear: seasonYear,
            type: .community,
            playerID: player.id,
            teamID: teamID,
            headline: headline,
            body: body
        )
    }
}
