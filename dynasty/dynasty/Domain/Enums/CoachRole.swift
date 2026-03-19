import Foundation

enum CoachRole: String, Codable, CaseIterable {
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
}
