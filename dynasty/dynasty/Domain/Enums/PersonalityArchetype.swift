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

    var displayName: String {
        switch self {
        case .teamLeader:        return "Team Leader"
        case .loneWolf:          return "Lone Wolf"
        case .feelPlayer:        return "Feel Player"
        case .steadyPerformer:   return "Steady Performer"
        case .dramaQueen:        return "Drama Queen"
        case .quietProfessional: return "Quiet Professional"
        case .mentor:            return "Mentor"
        case .fieryCompetitor:   return "Fiery Competitor"
        case .classClown:        return "Class Clown"
        }
    }

    /// #148: Short label for cramped table rows.
    var shortLabel: String {
        switch self {
        case .teamLeader:        return "Leader"
        case .loneWolf:          return "Lone Wolf"
        case .feelPlayer:        return "Feel"
        case .steadyPerformer:   return "Steady"
        case .dramaQueen:        return "Drama"
        case .quietProfessional: return "Quiet Pro"
        case .mentor:            return "Mentor"
        case .fieryCompetitor:   return "Fiery"
        case .classClown:        return "Clown"
        }
    }
}
