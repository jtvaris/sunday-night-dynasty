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
    /// Personality archetype (#36B mental game): drives hot/cold form
    /// sensitivity, ego/frustration, and the temperament badge in the UI.
    let personalityArchetype: PersonalityArchetype
    /// Mutable so a one-time pre-game coaching morale bump (R40) can be applied
    /// to the snapshot without touching the live @Model player.
    var morale: Int
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
        personalityArchetype = player.personality.archetype
        morale = player.morale
        overall = player.overall
        schemeFamiliarity = player.schemeFamiliarity
        fatigue = player.fatigue
    }

    /// Mirrors `Player.schemeFam(for:)` — familiarity for a scheme (defaults to 0).
    func schemeFam(for scheme: String) -> Int {
        schemeFamiliarity[scheme] ?? 0
    }

    // MARK: - Mental Game (#36B)

    /// Poise under pressure (mech 3): clutch is the spine, decision making and
    /// awareness the supporting cast. Below `60` the player's effective
    /// accuracy sags in big moments (`PlaySimulator.composurePenalty`). The
    /// Q4 clutch BOOST (`GameSimulator.applyMoraleModifiers`) is the up-side
    /// complement — clutch lifts the poised, composure dings the shaky.
    var composureRating: Double {
        Double(mental.clutch) * 0.5
            + Double(mental.decisionMaking) * 0.3
            + Double(mental.awareness) * 0.2
    }

    /// Personalities that ride form hard (mech 1): a hot streak lifts them, a
    /// cold one drags them. Steady/quiet pros are immune; the rest are neutral.
    var isFormSensitive: Bool { personalityArchetype.isFormSensitive }

    /// A high-overall, me-first star at a touch position (mech 2): starves for
    /// the ball if he goes several offensive drives untargeted / uncarried.
    var isEgoProne: Bool {
        overall >= 85
            && personalityArchetype.isEgoArchetype
            && [Position.WR, .TE, .RB, .FB].contains(position)
    }

    /// The single temperament tag surfaced in the quarter report / Coach's
    /// Board so the coach can lead with personalities.
    var mentalTemperament: MentalTemperament {
        if isEgoProne { return .egoDriven }
        if personalityArchetype.isFormImmune { return .unflappable }
        if personalityArchetype.isFormSensitive { return .streaky }
        return .neutral
    }
}

/// Static temperament tag for the mental-game UI hints (#36B).
enum MentalTemperament {
    /// Star ego at a touch position — wants the ball, sulks without it.
    case egoDriven
    /// Rides hot/cold form hard.
    case streaky
    /// Consistent — unaffected by streaks (ice in the veins).
    case unflappable
    /// No notable temperament flag.
    case neutral
}
