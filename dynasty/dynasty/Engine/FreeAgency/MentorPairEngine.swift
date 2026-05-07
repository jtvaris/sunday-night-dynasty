import Foundation

/// Surfaces mentor-protégé pairings during free agency. Signing the veteran
/// mentor brings the rookie protégé in at a 15% discount (FA Drama brief, B5).
///
/// Heuristics:
/// - The veteran's `mentorOfPlayerID` points at the protégé player.
/// - Both must be eligible (i.e. on the FA list / unsigned).
enum MentorPairEngine {

    /// Discount factor on the protégé's contract when signing the mentor.
    static let protegéContractDiscount: Double = 0.85   // 15% off

    /// If signing this player would bring a mentor protégé, returns the protégé.
    /// Resolved via the player's `mentorOfPlayerID` field, looked up against `allFAs`.
    static func protegéFor(player: Player, allFAs: [Player]) -> Player? {
        guard let protegéID = player.mentorOfPlayerID else { return nil }
        return allFAs.first(where: { $0.id == protegéID })
    }

    /// Discount factor (0.85 = 15% off) on the protégé's contract.
    static func protegéDiscount() -> Double { protegéContractDiscount }

    /// Builds the mentor-pair storyline event.
    static func generateMentorPairEvent(
        mentor: Player,
        protégé: Player,
        teamID: UUID
    ) -> FAStorylineEvent? {
        let headline = "\(mentor.lastName) brings protégé \(protégé.lastName) along"
        let body = "Mentor-protégé pair signs together. \(mentor.fullName) negotiated a discount on \(protégé.fullName)'s deal as part of the package."
        let seasonYear = Calendar.current.component(.year, from: Date())
        return FAStorylineEvent(
            seasonYear: seasonYear,
            type: .mentorPair,
            playerID: mentor.id,
            teamID: teamID,
            headline: headline,
            body: body
        )
    }
}
