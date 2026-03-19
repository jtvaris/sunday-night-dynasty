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
}
