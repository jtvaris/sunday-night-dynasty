import Foundation

enum MediaMarket: String, Codable, CaseIterable {
    case small  = "Small"
    case medium = "Medium"
    case large  = "Large"

    var mediaPressureMultiplier: Double {
        switch self {
        case .small:  return 0.7
        case .medium: return 1.0
        case .large:  return 1.5
        }
    }

    var freeAgentAttraction: Double {
        switch self {
        case .small:  return 0.8
        case .medium: return 1.0
        case .large:  return 1.3
        }
    }
}
