import Foundation

enum FreeAgencyStep: String, Codable {
    case finalPush     = "FinalPush"      // Re-sign own players
    case newLeagueYear = "NewLeagueYear"  // Transition (automatic)
    case capReview     = "CapReview"       // Must get under cap
    case signing       = "Signing"         // FA rounds 1-6
    case complete      = "Complete"        // Done, can advance

    /// Human-readable round label.
    static func roundLabel(_ round: Int) -> String {
        switch round {
        case 1: return "Day 1"
        case 2: return "Day 2"
        case 3: return "Day 3"
        case 4: return "Week 2"
        case 5: return "Week 3"
        case 6: return "Week 4"
        default: return "Complete"
        }
    }

    /// How aggressive AI teams are in this round (1.0 = very, 0.2 = passive).
    static func aiAggression(_ round: Int) -> Double {
        switch round {
        case 1: return 1.0
        case 2: return 0.85
        case 3: return 0.7
        case 4: return 0.5
        case 5: return 0.35
        case 6: return 0.2
        default: return 0.1
        }
    }

    /// How much AI team info is revealed to the player.
    static func aiVisibility(_ round: Int) -> AIVisibilityLevel {
        switch round {
        case 1, 2: return .countOnly
        case 3:    return .hints
        case 4:    return .partialNames
        case 5, 6: return .fullNames
        default:   return .countOnly
        }
    }
}

enum AIVisibilityLevel {
    case countOnly      // "5 teams interested"
    case hints          // "A contender is interested"
    case partialNames   // "KC and 2 others"
    case fullNames      // "KC, SF, DAL interested"
}
