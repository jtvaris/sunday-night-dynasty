import Foundation

enum PositionSide: String, Codable {
    case offense = "Offense"
    case defense = "Defense"
    case specialTeams = "Special Teams"
}

enum Position: String, Codable, CaseIterable, Identifiable {
    case QB = "QB"
    case RB = "RB"
    case FB = "FB"
    case WR = "WR"
    case TE = "TE"
    case LT = "LT"
    case LG = "LG"
    case C  = "C"
    case RG = "RG"
    case RT = "RT"
    case DE  = "DE"
    case DT  = "DT"
    case OLB = "OLB"
    case MLB = "MLB"
    case CB  = "CB"
    case FS  = "FS"
    case SS  = "SS"
    case K   = "K"
    case P   = "P"

    var id: String { rawValue }

    var side: PositionSide {
        switch self {
        case .QB, .RB, .FB, .WR, .TE, .LT, .LG, .C, .RG, .RT:
            return .offense
        case .DE, .DT, .OLB, .MLB, .CB, .FS, .SS:
            return .defense
        case .K, .P:
            return .specialTeams
        }
    }

    var peakAgeRange: ClosedRange<Int> {
        switch self {
        case .QB:
            return 28...35
        case .RB, .FB:
            return 24...28
        case .WR:
            return 26...31
        case .TE:
            return 26...31
        case .LT, .LG, .C, .RG, .RT:
            return 26...32
        case .DE, .DT:
            return 26...31
        case .OLB, .MLB:
            return 25...30
        case .CB:
            return 25...30
        case .FS, .SS:
            return 26...31
        case .K, .P:
            return 28...38
        }
    }
}
