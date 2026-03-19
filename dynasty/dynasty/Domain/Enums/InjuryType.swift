import Foundation

enum InjuryType: String, Codable, CaseIterable {
    case hamstring = "Hamstring"
    case ankle = "Ankle Sprain"
    case knee = "Knee (MCL/ACL)"
    case shoulder = "Shoulder"
    case concussion = "Concussion"
    case back = "Back"
    case foot = "Foot"
    case groin = "Groin"
    case wrist = "Wrist/Hand"
    case ribs = "Ribs"

    var baseRecoveryWeeks: ClosedRange<Int> {
        switch self {
        case .hamstring:   return 1...4
        case .ankle:       return 1...6
        case .knee:        return 4...16
        case .shoulder:    return 2...8
        case .concussion:  return 1...3
        case .back:        return 2...6
        case .foot:        return 2...8
        case .groin:       return 1...4
        case .wrist:       return 1...4
        case .ribs:        return 1...4
        }
    }

    /// Severity on a 1-5 scale.
    var severity: Int {
        switch self {
        case .concussion, .hamstring, .groin, .wrist: return 1
        case .ankle, .back, .foot, .ribs:             return 2
        case .shoulder:                                return 3
        case .knee:                                    return 4
        }
    }
}
