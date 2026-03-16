import Foundation

enum SeasonPhase: String, Codable, CaseIterable {
    case superBowl       = "SuperBowl"
    case proBowl         = "ProBowl"
    case coachingChanges = "CoachingChanges"
    case combine         = "Combine"
    case freeAgency      = "FreeAgency"
    case draft           = "Draft"
    case otas            = "OTAs"
    case trainingCamp    = "TrainingCamp"
    case preseason       = "Preseason"
    case rosterCuts      = "RosterCuts"
    case regularSeason   = "RegularSeason"
    case tradeDeadline   = "TradeDeadline"
    case playoffs        = "Playoffs"
}
