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

    /// Personality tier for badge coloring: positive, risky, or neutral.
    var tier: PersonalityTier {
        switch self {
        case .teamLeader, .steadyPerformer, .quietProfessional, .mentor:
            return .positive
        case .dramaQueen, .fieryCompetitor:
            return .risky
        case .loneWolf, .feelPlayer, .classClown:
            return .neutral
        }
    }

    /// Personality score contribution for interview grading (-10 to +10).
    var interviewScoreContribution: Int {
        switch tier {
        case .positive: return 10
        case .neutral:  return 0
        case .risky:    return -10
        }
    }
}

enum PersonalityTier {
    case positive, neutral, risky
}
