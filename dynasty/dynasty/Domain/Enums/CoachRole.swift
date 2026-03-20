import Foundation

enum CoachRole: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }

    case headCoach               = "HeadCoach"
    case assistantHeadCoach      = "AssistantHeadCoach"
    case offensiveCoordinator    = "OffensiveCoordinator"
    case defensiveCoordinator    = "DefensiveCoordinator"
    case specialTeamsCoordinator = "SpecialTeamsCoordinator"
    case qbCoach                 = "QBCoach"
    case rbCoach                 = "RBCoach"
    case wrCoach                 = "WRCoach"
    case olCoach                 = "OLCoach"
    case dlCoach                 = "DLCoach"
    case lbCoach                 = "LBCoach"
    case dbCoach                 = "DBCoach"
    case strengthCoach           = "StrengthCoach"
    case teamDoctor              = "TeamDoctor"
    case physio                  = "Physio"

    /// Real NFL salary range for this role, in thousands per year.
    /// E.g. (min: 2000, max: 20000) means $2M–$20M.
    var salaryRange: (min: Int, avg: Int, max: Int) {
        switch self {
        case .headCoach:               return (min: 2_000, avg: 10_000, max: 20_000)
        case .assistantHeadCoach:      return (min: 800,   avg: 1_500,  max: 4_500)
        case .offensiveCoordinator:    return (min: 500,   avg: 1_500,  max: 6_000)
        case .defensiveCoordinator:    return (min: 500,   avg: 1_500,  max: 4_500)
        case .specialTeamsCoordinator: return (min: 400,   avg: 800,    max: 2_200)
        case .qbCoach:                 return (min: 250,   avg: 500,    max: 1_200)
        case .rbCoach:                 return (min: 150,   avg: 300,    max: 700)
        case .wrCoach:                 return (min: 200,   avg: 350,    max: 800)
        case .olCoach:                 return (min: 200,   avg: 400,    max: 1_000)
        case .dlCoach:                 return (min: 200,   avg: 400,    max: 1_000)
        case .lbCoach:                 return (min: 200,   avg: 350,    max: 800)
        case .dbCoach:                 return (min: 200,   avg: 350,    max: 800)
        case .strengthCoach:           return (min: 150,   avg: 300,    max: 700)
        case .teamDoctor:              return (min: 200,   avg: 400,    max: 800)
        case .physio:                  return (min: 150,   avg: 300,    max: 600)
        }
    }

    /// Attributes that grow fastest for this role (weighted 2x in XP distribution)
    var focusAttributes: [String] {
        switch self {
        case .headCoach:               return ["motivation", "discipline", "adaptability"]
        case .assistantHeadCoach:      return ["playerDevelopment", "motivation", "gamePlanning"]
        case .offensiveCoordinator:    return ["playCalling", "gamePlanning", "adaptability"]
        case .defensiveCoordinator:    return ["playCalling", "gamePlanning", "adaptability"]
        case .specialTeamsCoordinator: return ["playCalling", "discipline"]
        case .qbCoach:                 return ["playCalling", "playerDevelopment", "gamePlanning"]
        case .rbCoach, .wrCoach:       return ["playerDevelopment", "motivation"]
        case .olCoach, .dlCoach:       return ["playerDevelopment", "discipline"]
        case .lbCoach, .dbCoach:       return ["playerDevelopment", "gamePlanning"]
        case .strengthCoach:           return ["playerDevelopment", "discipline", "motivation"]
        case .teamDoctor, .physio:     return ["playerDevelopment"]
        }
    }

    /// Roles this coach can be promoted to
    var promotionTargets: [CoachRole] {
        switch self {
        case .qbCoach, .rbCoach, .wrCoach, .olCoach:
            return [.offensiveCoordinator]
        case .dlCoach, .lbCoach, .dbCoach:
            return [.defensiveCoordinator]
        case .strengthCoach:
            return [.specialTeamsCoordinator]
        case .offensiveCoordinator, .defensiveCoordinator:
            return [.assistantHeadCoach]
        case .specialTeamsCoordinator:
            return [.assistantHeadCoach]
        case .assistantHeadCoach:
            return [.headCoach]
        default:
            return []
        }
    }

    /// Roles this coach can be demoted to
    var demotionTargets: [CoachRole] {
        switch self {
        case .offensiveCoordinator:
            return [.qbCoach, .rbCoach, .wrCoach, .olCoach]
        case .defensiveCoordinator:
            return [.dlCoach, .lbCoach, .dbCoach]
        case .assistantHeadCoach:
            return [.offensiveCoordinator, .defensiveCoordinator]
        default:
            return []
        }
    }
}
