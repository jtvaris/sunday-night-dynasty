import Foundation

enum OffensiveScheme: String, Codable, CaseIterable {
    case westCoast  = "WestCoast"
    case airRaid    = "AirRaid"
    case spread     = "Spread"
    case powerRun   = "PowerRun"
    case shanahan   = "Shanahan"
    case proPassing = "ProPassing"
    case rpo        = "RPO"
    case option     = "Option"
}

enum DefensiveScheme: String, Codable, CaseIterable {
    case base34   = "Base34"
    case base43   = "Base43"
    case cover3   = "Cover3"
    case pressMan = "PressMan"
    case tampa2   = "Tampa2"
    case multiple = "Multiple"
    case hybrid   = "Hybrid"
}
