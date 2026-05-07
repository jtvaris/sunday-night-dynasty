import Foundation

/// Matches free agents against the coaching staff's prior coachee history to
/// surface "coach reunion" storylines (FA Drama brief, B3).
///
/// Heuristics:
/// - If any coach on the team has the FA in their `coacheePlayerIDs`, a reunion
///   is available.
/// - Reunion adds a 10% discount on the FA's asking price (factor 0.90) and a
///   morale-style loyalty bonus the engine layer can apply where useful
///   (returned as `0.20`, i.e. +20% loyalty).
@MainActor
enum CoachReunionMatcher {

    static let reunionDiscountFactor: Double = 0.90
    static let reunionLoyaltyBonusValue: Double = 0.20

    /// Returns true if any coach on this team previously coached the FA player.
    static func hasReunionAvailable(playerID: UUID, teamCoaches: [Coach]) -> Bool {
        return teamCoaches.contains { $0.coacheePlayerIDs.contains(playerID) }
    }

    /// Returns the first coach on the team who has previously coached this player,
    /// or `nil` if no reunion is available. Useful for storyline generation.
    static func reunionCoach(playerID: UUID, teamCoaches: [Coach]) -> Coach? {
        return teamCoaches.first(where: { $0.coacheePlayerIDs.contains(playerID) })
    }

    /// Discount factor when reunion is available. `0.90` (10% off) when matched, `1.0` otherwise.
    static func reunionDiscount(playerID: UUID, teamCoaches: [Coach]) -> Double {
        return hasReunionAvailable(playerID: playerID, teamCoaches: teamCoaches)
            ? reunionDiscountFactor
            : 1.0
    }

    /// Loyalty bonus added to the player when a reunion happens. `0.20` (+20%) on match,
    /// `0.0` otherwise.
    static func reunionLoyaltyBonus(playerID: UUID, teamCoaches: [Coach]) -> Double {
        return hasReunionAvailable(playerID: playerID, teamCoaches: teamCoaches)
            ? reunionLoyaltyBonusValue
            : 0.0
    }

    /// Generates a reunion storyline event for a signed FA + matched coach.
    static func generateReunionEvent(
        player: Player,
        coach: Coach,
        teamID: UUID
    ) -> FAStorylineEvent? {
        let headline = "\(player.lastName) reunites with Coach \(coach.lastName)"
        let body = "Familiar faces matter. \(player.fullName) signs to play under \(coach.fullName) again — chemistry expected from day one."
        let seasonYear = Calendar.current.component(.year, from: Date())
        return FAStorylineEvent(
            seasonYear: seasonYear,
            type: .coachReunion,
            playerID: player.id,
            teamID: teamID,
            headline: headline,
            body: body
        )
    }
}
