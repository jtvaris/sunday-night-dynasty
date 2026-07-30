import Foundation

enum PositionSide: String, Codable {
    case offense = "Offense"
    case defense = "Defense"
    case specialTeams = "Special Teams"
}

/// Shape of a position's post-peak decline (`DEVELOPMENT_NFL_REFERENCE.md` §1).
///
/// The deltas are applied to the single generic regression table in
/// `PlayerDevelopmentEngine.applyAgeRegression`, so the historical `standard`
/// behaviour is preserved byte-for-byte and only the two tails move.
enum DeclineProfile: String, Codable, CaseIterable {
    /// RB / CB — burst-dependent, falls off a cliff at ~27-29.
    case cliff
    /// The historical generic curve: WR, TE, EDGE, DT, LB, S, FB.
    case standard
    /// QB / OL / K / P — technique and processing hold the line for years.
    case glide

    /// Percentage points added to every regression *chance* band.
    var chanceDelta: Double {
        switch self {
        case .cliff:    return 0.15
        case .standard: return 0.0
        case .glide:    return -0.10
        }
    }

    /// Points added to the magnitude of each attribute loss (floored at 1).
    var magnitudeDelta: Int {
        switch self {
        case .cliff:    return 1
        case .standard: return 0
        case .glide:    return -1
        }
    }

    /// Whether the position keeps growing mentally while the body declines —
    /// the "processing keeps improving" exception (reference §1). True for the
    /// glide group, of which the QB is the archetype.
    var hasLateMentalGrowth: Bool { self == .glide }
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

    /// How this position ages once it is past its peak window
    /// (`docs/DEVELOPMENT_NFL_REFERENCE.md` §1, plan §2.8). Consumed by
    /// `PlayerDevelopmentEngine.applyAgeRegression`, which used one generic
    /// table for all 19 positions — so a 30-year-old corner decayed at exactly
    /// the rate of a 30-year-old left tackle, which is the opposite of what the
    /// PFF/EPA aging curves show.
    var declineProfile: DeclineProfile {
        switch self {
        // Sharpest cliffs in football: RB peak-season share falls 28→8.7 %,
        // 29→5.2 %; only 31 of 366 active DBs are 30+.
        case .RB, .CB:
            return .cliff
        // Technique and processing offset athletic loss; longest careers.
        case .QB, .LT, .LG, .C, .RG, .RT, .K, .P:
            return .glide
        // Everyone else decays at the historical generic rate.
        case .FB, .WR, .TE, .DE, .DT, .OLB, .MLB, .FS, .SS:
            return .standard
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
