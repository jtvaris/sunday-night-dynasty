import Foundation

// MARK: - Sim Player

/// Value-type snapshot of a `Player` used by the play-by-play game simulation.
///
/// The simulators read player attributes thousands of times per game. Reading
/// them through the SwiftData `@Model` accessors is prohibitively slow (every
/// access goes through the persistence machinery), so `GameSimulator` snapshots
/// each roster into these plain structs once and runs the entire sim against
/// them. Each model property is read exactly once in `init(from:)`; only
/// fatigue is written back to the live model after the game completes.
struct SimPlayer {
    let id: UUID
    let fullName: String
    let position: Position
    var physical: PhysicalAttributes
    var mental: MentalAttributes
    let positionAttributes: PositionAttributes
    let isMoodDependent: Bool
    let morale: Int
    /// Precomputed `Player.overall` so the sim never re-derives it per read.
    let overall: Int
    let schemeFamiliarity: [String: Int]
    var fatigue: Int

    init(from player: Player) {
        id = player.id
        fullName = player.fullName
        position = player.position
        physical = player.physical
        mental = player.mental
        positionAttributes = player.positionAttributes
        isMoodDependent = player.personality.isMoodDependent
        morale = player.morale
        overall = player.overall
        schemeFamiliarity = player.schemeFamiliarity
        fatigue = player.fatigue
    }

    /// Mirrors `Player.schemeFam(for:)` — familiarity for a scheme (defaults to 0).
    func schemeFam(for scheme: String) -> Int {
        schemeFamiliarity[scheme] ?? 0
    }
}
