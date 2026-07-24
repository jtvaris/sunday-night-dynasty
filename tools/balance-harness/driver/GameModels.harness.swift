import Foundation

// MARK: - SwiftData-model stubs (HARNESS-OWNED SCAFFOLDING)
//
// The shipped full-game pipeline — GameSimulator / DriveSimulator / CoachingModifiers,
// all synced VERBATIM (sha-verified) by sync_sources.sh — is written against three
// SwiftData `@Model` types (`Player`, `Team`, `Coach`) that cannot compile outside the
// iOS app (they pull in SwiftData, the whole Domain graph, etc.). None of those three
// carries any balance MATH: they are pure data holders. So the harness supplies its own
// plain shells exposing EXACTLY the members the synced engine reads — the same technique
// the existing `CoachingEngine` / `VersatilityDevelopmentEngine` stubs in
// SimPlayer.harness.swift use. Every tuning constant still flows from the verbatim
// engine sources; these stubs never touch a number.
//
// `Player` MUST be a reference type: `GameSimulator.finalizeGameResult` writes fatigue
// back through `let livePlayerByID: [UUID: Player]` via `dict[id]?.fatigue = …`, which
// only compiles (mutating through a `let` dictionary) when the value is a class.
//
// This file is copied verbatim into build/src/GameModels.swift on every sync and
// compiled alongside the engine sources.

/// Minimal mirror of the shipped `CoachRole` — only the four roles the sim's
/// coaching path (`CoachingModifiers.ratings`) actually inspects, plus a catch-all.
enum CoachRole {
    case headCoach
    case assistantHeadCoach
    case offensiveCoordinator
    case defensiveCoordinator
    case other
}

/// Data-holder for the handful of coach attributes `CoachingModifiers` consumes.
/// A grade-70 coach on every field produces ~zero coaching effect (each mechanic is
/// centered at 70), so neutral coaches can carry a scheme without moving the balance.
final class Coach {
    var role: CoachRole
    var offensiveScheme: OffensiveScheme?
    var defensiveScheme: DefensiveScheme?
    var playCalling: Int
    var adaptability: Int
    var gamePlanning: Int
    var discipline: Int
    var moraleInfluence: Int
    var motivation: Int
    var schemeExpertise: [String: Int]

    init(role: CoachRole,
         offensiveScheme: OffensiveScheme? = nil,
         defensiveScheme: DefensiveScheme? = nil,
         playCalling: Int = 70,
         adaptability: Int = 70,
         gamePlanning: Int = 70,
         discipline: Int = 70,
         moraleInfluence: Int = 70,
         motivation: Int = 70,
         schemeExpertise: [String: Int] = [:]) {
        self.role = role
        self.offensiveScheme = offensiveScheme
        self.defensiveScheme = defensiveScheme
        self.playCalling = playCalling
        self.adaptability = adaptability
        self.gamePlanning = gamePlanning
        self.discipline = discipline
        self.moraleInfluence = moraleInfluence
        self.motivation = motivation
        self.schemeExpertise = schemeExpertise
    }

    /// Matches the shipped `Coach.expertise(for:)` (baseline 20 for unknown schemes).
    func expertise(for scheme: String) -> Int { schemeExpertise[scheme] ?? 20 }
}

/// Reference-type player shell exposing exactly the members `SimPlayer.init(from:)`
/// reads plus `isHoldingOut` (roster filter) and the mutable `morale`/`fatigue` the
/// engine writes back. No SwiftData, no @Model — a throwaway per-game roster cell.
final class Player {
    let id: UUID
    var fullName: String
    var position: Position
    var physical: PhysicalAttributes
    var mental: MentalAttributes
    var positionAttributes: PositionAttributes
    var isMoodDependent: Bool
    var personalityArchetype: PersonalityArchetype
    var morale: Int
    var overall: Int
    var schemeFamiliarity: [String: Int]
    var fatigue: Int
    var isHoldingOut: Bool

    init(id: UUID = UUID(),
         fullName: String,
         position: Position,
         physical: PhysicalAttributes,
         mental: MentalAttributes,
         positionAttributes: PositionAttributes,
         isMoodDependent: Bool = false,
         personalityArchetype: PersonalityArchetype = .steadyPerformer,
         morale: Int = 70,
         overall: Int,
         schemeFamiliarity: [String: Int] = [:],
         fatigue: Int = 0,
         isHoldingOut: Bool = false) {
        self.id = id
        self.fullName = fullName
        self.position = position
        self.physical = physical
        self.mental = mental
        self.positionAttributes = positionAttributes
        self.isMoodDependent = isMoodDependent
        self.personalityArchetype = personalityArchetype
        self.morale = morale
        self.overall = overall
        self.schemeFamiliarity = schemeFamiliarity
        self.fatigue = fatigue
        self.isHoldingOut = isHoldingOut
    }
}

/// A team is just its roster + a stable id (the only two members the sim touches).
final class Team {
    let id: UUID
    var players: [Player]
    init(id: UUID = UUID(), players: [Player]) {
        self.id = id
        self.players = players
    }
}

// MARK: - SimPlayer.init(from:) — harness overload
//
// The repo `SimPlayer` builds from a SwiftData `@Model Player` via `init(from:)`; the
// harness never splices that initializer (it owns a plain memberwise init instead). But
// the synced `GameSimulator.simulate` calls `homeRoster.map(SimPlayer.init(from:))`, so
// the harness supplies its own overload against the stub `Player` above. It preserves
// the player's UUID (delegating through the memberwise init's `id:` seam) so heat
// attribution and the fatigue/morale write-back key correctly.
extension SimPlayer {
    init(from p: Player) {
        self.init(
            fullName: p.fullName,
            position: p.position,
            physical: p.physical,
            mental: p.mental,
            positionAttributes: p.positionAttributes,
            overall: p.overall,
            morale: p.morale,
            isMoodDependent: p.isMoodDependent,
            personalityArchetype: p.personalityArchetype,
            schemeFamiliarity: p.schemeFamiliarity,
            fatigue: p.fatigue,
            id: p.id
        )
    }
}
