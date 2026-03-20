import Foundation

enum SeasonPhase: String, Codable, CaseIterable {
    case proBowl         = "ProBowl"
    case superBowl       = "SuperBowl"
    case coachingChanges = "CoachingChanges"
    case reviewRoster    = "ReviewRoster"
    case combine         = "Combine"
    case freeAgency      = "FreeAgency"
    case proDays         = "ProDays"
    case draft           = "Draft"
    case otas            = "OTAs"
    case trainingCamp    = "TrainingCamp"
    case preseason       = "Preseason"
    case rosterCuts      = "RosterCuts"
    case regularSeason   = "RegularSeason"
    case tradeDeadline   = "TradeDeadline"
    case playoffs        = "Playoffs"
}
