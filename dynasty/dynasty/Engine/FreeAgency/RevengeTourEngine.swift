import Foundation
import SwiftData

/// Tracks "grudge" flags for players who were cut by a team and computes a
/// performance modifier when they later face that team. Mirrors the
/// "Revenge Tour" design from the FA Drama brief (B1).
///
/// Heuristics:
/// - A cut player carries the grudge for **2 seasons** after the cut.
/// - When facing the cutting team during the grudge window, the player gets a
///   **+5% performance** modifier (returned as `1.05`).
/// - Outside the grudge window or against any other team, the modifier is `1.0`.
@MainActor
enum RevengeTourEngine {

    /// Number of seasons the grudge persists after the cut.
    static let grudgeWindowSeasons: Int = 2

    /// Performance boost applied during the grudge window vs the cutting team.
    static let grudgePerformanceBoost: Double = 0.05

    /// Marks a player with a grudge flag against the team that cut them.
    /// Stamps both the team ID and the cut date so the grudge can age out.
    static func markCut(player: Player, byTeamID: UUID, modelContext: ModelContext) {
        player.cutByTeamID = byTeamID
        player.cutAt = Date()
        // Detach roster relationship — caller is responsible for clearing teamID
        // but we defensively reset it here so a marked-cut player isn't "owned".
        if player.teamID == byTeamID {
            player.teamID = nil
        }
        try? modelContext.save()
    }

    /// Returns `true` if the player still carries a live grudge against
    /// `opposingTeamID` during `currentSeason`.
    static func hasActiveGrudge(
        player: Player,
        opposingTeamID: UUID,
        currentSeason: Int
    ) -> Bool {
        guard let cutBy = player.cutByTeamID, cutBy == opposingTeamID,
              let cutAt = player.cutAt else { return false }

        let calendar = Calendar.current
        let cutSeason = calendar.component(.year, from: cutAt)
        return currentSeason - cutSeason < grudgeWindowSeasons
    }

    /// Returns a multiplicative performance modifier when a player faces their
    /// former cutting team. `1.05` during the 2-year grudge window, `1.0` otherwise.
    static func performanceModifier(
        player: Player,
        opposingTeamID: UUID,
        currentSeason: Int
    ) -> Double {
        guard hasActiveGrudge(
            player: player,
            opposingTeamID: opposingTeamID,
            currentSeason: currentSeason
        ) else { return 1.0 }
        return 1.0 + grudgePerformanceBoost
    }

    /// Generates a storyline event when a revenge tour kicks off (e.g. the player
    /// signs with a rival, or week-of game vs the cutting team).
    /// `signingTeamID` is optional — pass it on a signing event; pass `nil` for
    /// "playing against former team" events.
    static func generateRevengeEvent(
        player: Player,
        signingTeamID: UUID?,
        teamAbbrevs: [UUID: String]
    ) -> FAStorylineEvent? {
        guard let cutBy = player.cutByTeamID,
              let cutAt = player.cutAt else { return nil }

        let cutAbbrev = teamAbbrevs[cutBy] ?? "former team"

        let headline: String
        let body: String
        let teamID: UUID?
        if let signingID = signingTeamID {
            let signingAbbrev = teamAbbrevs[signingID] ?? "new team"
            headline = "\(player.fullName): Revenge Tour starts in \(signingAbbrev)"
            body = "After being cut by \(cutAbbrev), \(player.lastName) lands with \(signingAbbrev) and circles the schedule. Two-year grudge window in effect."
            teamID = signingID
        } else {
            headline = "\(player.fullName) eyes \(cutAbbrev) revenge"
            body = "The grudge from \(cutBy.uuidString.prefix(4)) hasn't cooled — expect a chip on the shoulder when these two meet."
            teamID = cutBy
        }

        let seasonYear = Calendar.current.component(.year, from: Date())
        _ = cutAt // stamp acknowledged
        return FAStorylineEvent(
            seasonYear: seasonYear,
            type: .revengeTour,
            playerID: player.id,
            teamID: teamID,
            headline: headline,
            body: body
        )
    }
}
