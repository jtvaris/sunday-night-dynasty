import Foundation
import SwiftData

// MARK: - WaiverWireEngine

/// Runs the 24h post-cut waiver window. Every cut player passes through waivers;
/// teams claim by priority order (worst-record first, ascending). Each cut becomes
/// at most one claim — the winning team is recorded on `RosterCut.claimedByTeamID`.
@MainActor
enum WaiverWireEngine {

    // MARK: - Types

    struct WaiverClaim {
        let cutPlayerID: UUID
        let claimingTeamID: UUID
        let priority: Int
    }

    // MARK: - Public API

    /// Detects which cut players will be claimed in 24h waiver window.
    /// Worst-record teams get higher priority (lower priority integer).
    static func processWaivers(
        cuts: [RosterCut],
        teamRecords: [(teamID: UUID, wins: Int, losses: Int)],
        modelContext: ModelContext
    ) -> [WaiverClaim] {
        guard !cuts.isEmpty, !teamRecords.isEmpty else { return [] }

        // Compute waiver priority list: worst record first.
        // Ties broken by losses-desc then teamID for determinism.
        let priorityOrder = teamRecords
            .sorted { lhs, rhs in
                if lhs.wins != rhs.wins { return lhs.wins < rhs.wins }
                if lhs.losses != rhs.losses { return lhs.losses > rhs.losses }
                return lhs.teamID.uuidString < rhs.teamID.uuidString
            }

        // Precompute priority index lookup
        var priorityForTeam: [UUID: Int] = [:]
        for (idx, entry) in priorityOrder.enumerated() {
            priorityForTeam[entry.teamID] = idx
        }

        // Fetch all cut players so we can rate them.
        let cutPlayerIDs = cuts.map(\.playerID)
        let playerDescriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { cutPlayerIDs.contains($0.id) }
        )
        let players = (try? modelContext.fetch(playerDescriptor)) ?? []
        let playerByID: [UUID: Player] = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })

        var claims: [WaiverClaim] = []

        // For each cut, walk the priority order. First team that "wants" the player wins.
        for cut in cuts where cut.claimedByTeamID == nil {
            guard let player = playerByID[cut.playerID] else { continue }
            let interestThreshold = waiverInterestThreshold(for: player)

            for (idx, entry) in priorityOrder.enumerated() {
                // The cutting team can't reclaim its own cut.
                if entry.teamID == cut.teamID { continue }

                // Does this team "want" the player? Use OVR floor + a deterministic hash roll
                // so the result is stable across reruns of the same waiver window.
                let interest = teamInterest(player: player, teamID: entry.teamID)
                guard interest >= interestThreshold else { continue }

                cut.claimedByTeamID = entry.teamID
                claims.append(WaiverClaim(
                    cutPlayerID: player.id,
                    claimingTeamID: entry.teamID,
                    priority: idx
                ))

                // Also stamp the player so downstream FA / Revenge-Tour systems work.
                player.cutByTeamID = cut.teamID
                player.cutAt = .now
                break
            }
        }

        // Set priority for claims (already filled).
        return claims.sorted { $0.priority < $1.priority }
    }

    // MARK: - Heuristics

    /// OVR floor a player must clear for at least one team to claim.
    private static func waiverInterestThreshold(for player: Player) -> Double {
        // Veterans (3+ years) need a higher OVR to be claimed (younger players preferred).
        let baseFloor: Double = player.yearsPro >= 3 ? 70.0 : 60.0
        // Injured players are claimed less often — raise the bar.
        let injuryBump: Double = player.isInjured ? 8.0 : 0.0
        return baseFloor + injuryBump
    }

    /// Team-interest score on this specific player. Stable per (player, team) pair.
    private static func teamInterest(player: Player, teamID: UUID) -> Double {
        // OVR + deterministic per-(player,team) jitter so different teams favor different players.
        let jitter = Double(abs(player.id.hashValue ^ teamID.hashValue) % 17) - 8.0
        return Double(player.overall) + jitter
    }
}
