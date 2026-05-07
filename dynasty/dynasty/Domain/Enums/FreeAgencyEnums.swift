import Foundation

/// Heat tier for an individual free agent. Drives salary inflation and visual
/// urgency cues throughout the FA experience.
enum FrenzyHeatTier: String, Codable, CaseIterable {
    case cool, yellow, red, burning

    /// Multiplier applied to expected market salary based on bidding heat.
    var inflationModifier: Double {
        switch self {
        case .cool:    return 0.9
        case .yellow:  return 1.0
        case .red:     return 1.15
        case .burning: return 1.3
        }
    }

    /// Emoji used in tickers and badges.
    var emoji: String {
        switch self {
        case .cool:    return "\u{2744}\u{FE0F}"   // snowflake
        case .yellow:  return "\u{1F7E1}"           // yellow circle
        case .red:     return "\u{1F534}"           // red circle
        case .burning: return "\u{1F525}"           // fire
        }
    }
}

/// Hidden preference tags that influence how a free agent ranks competing offers.
/// At least one tag is generated per FA; multiple may apply.
enum PlayerPreferenceTag: String, Codable, CaseIterable {
    case contenderShot       // wants playoff team
    case maxMoney            // money-first
    case familyLocation      // wants specific region
    case warmClimate         // hates cold
    case startingRole        // must start
    case loyaltyToCoach      // reunion bonus
    case hometownReturn      // hometown bonus
}
