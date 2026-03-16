import Foundation

struct PlayerPersonality: Codable, Equatable {
    var archetype: PersonalityArchetype
    var motivation: Motivation

    var isDramaticInMedia: Bool {
        archetype == .dramaQueen || archetype == .fieryCompetitor
    }

    var isMentor: Bool {
        archetype == .mentor || archetype == .teamLeader
    }

    var isMoodDependent: Bool {
        archetype == .feelPlayer || archetype == .dramaQueen
    }

    var isConsistent: Bool {
        archetype == .steadyPerformer || archetype == .quietProfessional
    }
}
