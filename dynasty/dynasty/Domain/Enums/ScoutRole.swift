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

    var displayName: String {
        switch self {
        case .chiefScout:     return "Chief Scout"
        case .regionalScout1: return "Regional Scout (East)"
        case .regionalScout2: return "Regional Scout (West)"
        case .regionalScout3: return "Regional Scout (South)"
        case .regionalScout4: return "Regional Scout (North)"
        case .regionalScout5: return "Regional Scout (Central)"
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
        }
    }

    /// Whether this is the chief scout (leader of the department).
    var isChief: Bool {
        self == .chiefScout
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
