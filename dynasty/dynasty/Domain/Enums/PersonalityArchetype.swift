import Foundation

enum PersonalityArchetype: String, Codable, CaseIterable {
    case teamLeader       = "TeamLeader"
    case loneWolf         = "LoneWolf"
    case feelPlayer       = "FeelPlayer"
    case steadyPerformer  = "SteadyPerformer"
    case dramaQueen       = "DramaQueen"
    case quietProfessional = "QuietProfessional"
    case mentor           = "Mentor"
    case fieryCompetitor  = "FieryCompetitor"
    case classClown       = "ClassClown"
}
