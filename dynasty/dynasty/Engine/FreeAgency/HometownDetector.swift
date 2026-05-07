import Foundation

/// Maps US states to NFL geographic regions and computes "hometown hero"
/// storyline matches (FA Drama brief, B4).
///
/// Heuristics:
/// - 4 regions: Northeast / South / Midwest / West.
/// - When the FA's hometown state lies in the team's region, apply a 5% asking
///   price discount (factor `0.95`).
enum HometownDetector {

    /// Discount factor applied when the team's region matches the FA's hometown state.
    static let hometownDiscountFactor: Double = 0.95

    /// Static state -> region map. Covers the ~25 US states that produce the
    /// vast majority of NFL talent. States not in this map return `nil`,
    /// meaning "no clean regional fit" and disabling the bonus.
    private static let stateRegions: [String: String] = [
        // West
        "California": "West", "Oregon": "West", "Washington": "West",
        "Nevada": "West", "Arizona": "West", "Colorado": "West",
        "Utah": "West", "Hawaii": "West",
        // South
        "Texas": "South", "Florida": "South", "Georgia": "South",
        "Louisiana": "South", "Alabama": "South", "Mississippi": "South",
        "Tennessee": "South", "South Carolina": "South",
        "North Carolina": "South", "Arkansas": "South", "Oklahoma": "South",
        "Virginia": "South",
        // Northeast
        "New York": "Northeast", "Massachusetts": "Northeast",
        "Pennsylvania": "Northeast", "New Jersey": "Northeast",
        "Connecticut": "Northeast", "Maryland": "Northeast",
        "Maine": "Northeast", "New Hampshire": "Northeast",
        // Midwest
        "Ohio": "Midwest", "Michigan": "Midwest", "Illinois": "Midwest",
        "Wisconsin": "Midwest", "Indiana": "Midwest", "Minnesota": "Midwest",
        "Missouri": "Midwest", "Iowa": "Midwest", "Kansas": "Midwest",
        "Nebraska": "Midwest"
    ]

    /// Resolves the NFL geographic region for a state name.
    static func region(for state: String?) -> String? {
        guard let state = state else { return nil }
        return stateRegions[state]
    }

    /// Returns true if a player's hometown state matches the team's region.
    static func isHometown(
        player: Player,
        teamRegion: String?
    ) -> Bool {
        guard let teamRegion = teamRegion,
              let playerRegion = region(for: player.hometownState) else { return false }
        return teamRegion == playerRegion
    }

    /// Discount factor (0.95 = 5% off) when team is FA's hometown region.
    static func hometownDiscount(
        player: Player,
        teamRegion: String?
    ) -> Double {
        return isHometown(player: player, teamRegion: teamRegion)
            ? hometownDiscountFactor
            : 1.0
    }

    /// Generates a "hometown hero" storyline event for the press conference.
    static func generateHometownEvent(
        player: Player,
        teamID: UUID,
        teamRegion: String
    ) -> FAStorylineEvent? {
        guard isHometown(player: player, teamRegion: teamRegion) else { return nil }
        let stateLabel = player.hometownState ?? "the region"
        let headline = "\(player.fullName) comes home to play in the \(teamRegion)"
        let body = "Born in \(stateLabel), \(player.lastName) inks a hometown deal. Local-press storylines write themselves."
        let seasonYear = Calendar.current.component(.year, from: Date())
        return FAStorylineEvent(
            seasonYear: seasonYear,
            type: .hometown,
            playerID: player.id,
            teamID: teamID,
            headline: headline,
            body: body
        )
    }
}
