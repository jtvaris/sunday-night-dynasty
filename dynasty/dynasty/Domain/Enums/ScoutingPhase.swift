import Foundation

enum ScoutingPhase: String, Codable, CaseIterable {
    case collegeSeason    = "CollegeSeason"
    case seniorBowl       = "SeniorBowl"
    case combine          = "Combine"
    case proDay           = "ProDay"
    case personalWorkout  = "PersonalWorkout"

    var displayName: String {
        switch self {
        case .collegeSeason:   return "College Season"
        case .seniorBowl:      return "Senior Bowl"
        case .combine:         return "Combine"
        case .proDay:          return "Pro Day"
        case .personalWorkout: return "Personal Workout"
        }
    }

    var confidenceLevel: Double {
        switch self {
        case .collegeSeason:   return 0.4
        case .seniorBowl:      return 0.55
        case .combine:         return 0.7
        case .proDay:          return 0.75
        case .personalWorkout: return 0.9
        }
    }
}
