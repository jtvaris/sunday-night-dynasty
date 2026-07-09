import Foundation

/// Defines the scouting department hierarchy.
enum ScoutRole: String, Codable, CaseIterable, Identifiable {
    var id: String { rawValue }

    case chiefScout      = "ChiefScout"
    case regionalScout1  = "RegionalScout1"
    case regionalScout2  = "RegionalScout2"
    case regionalScout3  = "RegionalScout3"
    case regionalScout4  = "RegionalScout4"
    case regionalScout5  = "RegionalScout5"
    case extraScout1     = "ExtraScout1"
    case extraScout2     = "ExtraScout2"

    var displayName: String {
        switch self {
        case .chiefScout:     return "Chief Scout"
        case .regionalScout1: return "Regional Scout (East)"
        case .regionalScout2: return "Regional Scout (West)"
        case .regionalScout3: return "Regional Scout (South)"
        case .regionalScout4: return "Regional Scout (North)"
        case .regionalScout5: return "Regional Scout (Central)"
        case .extraScout1:    return "Additional Scout 1"
        case .extraScout2:    return "Additional Scout 2"
        }
    }

    var abbreviation: String {
        switch self {
        case .chiefScout:     return "CS"
        case .regionalScout1: return "RE"
        case .regionalScout2: return "RW"
        case .regionalScout3: return "RS"
        case .regionalScout4: return "RN"
        case .regionalScout5: return "RC"
        case .extraScout1:    return "X1"
        case .extraScout2:    return "X2"
        }
    }

    var sortOrder: Int {
        switch self {
        case .chiefScout:     return 0
        case .regionalScout1: return 1
        case .regionalScout2: return 2
        case .regionalScout3: return 3
        case .regionalScout4: return 4
        case .regionalScout5: return 5
        case .extraScout1:    return 6
        case .extraScout2:    return 7
        }
    }

    var roleDescription: String {
        switch self {
        case .chiefScout:     return "Oversees the entire scouting department and sets evaluation priorities"
        case .regionalScout1: return "Covers the East region — ACC and Big East prospects"
        case .regionalScout2: return "Covers the West region — Pac-12 and Mountain West prospects"
        case .regionalScout3: return "Covers the South region — SEC and Sun Belt prospects"
        case .regionalScout4: return "Covers the North region — Big Ten and MAC prospects"
        case .regionalScout5: return "Covers the Central region — Big 12 and AAC prospects"
        case .extraScout1:    return "Additional scout for expanded coverage"
        case .extraScout2:    return "Additional scout for expanded coverage"
        }
    }

    /// Whether this is the chief scout (leader of the department).
    var isChief: Bool {
        self == .chiefScout
    }

    /// Whether this is an extra (7th or 8th) scout slot.
    var isExtra: Bool {
        self == .extraScout1 || self == .extraScout2
    }

    /// Maximum pro days this scout role can attend per year.
    var maxProDays: Int {
        switch self {
        case .chiefScout:                                       return 4
        case .regionalScout1, .regionalScout2, .regionalScout3,
             .regionalScout4, .regionalScout5:                  return 3
        case .extraScout1, .extraScout2:                        return 3
        }
    }
}

// MARK: - Scout Assignment Pool (R27)

/// The slice of the consensus draft board a scout is assigned to watch weekly.
/// Targeted prospects are evaluated more often and with a small accuracy edge.
enum ScoutAssignmentPool: String, Codable, CaseIterable, Identifiable {
    case top50   // concentrate on the consensus top 50
    case top150  // concentrate on the consensus top 150

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top50:  return "Top 50"
        case .top150: return "Top 150"
        }
    }

    var icon: String {
        switch self {
        case .top50:  return "star.circle"
        case .top150: return "list.star"
        }
    }

    /// How many prospects of the consensus board this pool covers.
    var boardSize: Int {
        switch self {
        case .top50:  return 50
        case .top150: return 150
        }
    }

    var poolDescription: String {
        switch self {
        case .top50:  return "Focuses weekly visits on consensus top-50 prospects"
        case .top150: return "Focuses weekly visits on consensus top-150 prospects"
        }
    }
}

// MARK: - Scout Focus Attribute

/// The attribute category a scout focuses on during evaluation.
enum ScoutFocusAttribute: String, Codable, CaseIterable, Identifiable {
    case physical   // reveals physical attributes faster
    case mental     // reveals mental attributes, football IQ faster
    case character  // reveals personality, character concerns faster

    var id: String { rawValue }

    var label: String {
        switch self {
        case .physical:  return "Physical"
        case .mental:    return "Mental"
        case .character: return "Character"
        }
    }

    var icon: String {
        switch self {
        case .physical:  return "figure.strengthtraining.traditional"
        case .mental:    return "brain.head.profile"
        case .character: return "person.fill.questionmark"
        }
    }
}
