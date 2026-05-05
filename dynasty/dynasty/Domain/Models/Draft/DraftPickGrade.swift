import Foundation
import SwiftData

/// Two-tier grade for a completed draft pick.
/// `publicGrade` is computed immediately from visible info (BB rank, need, OVR, scheme).
/// `trueGrade` is filled in over the player's career by `CareerArcEngine`.
@Model
final class DraftPickGrade {
    var id: UUID
    var pickID: UUID
    var draftYear: Int
    var pickNumber: Int
    var teamID: UUID
    var prospectID: UUID
    var playerID: UUID?

    var publicGradeRaw: String
    var publicValueDelta: Int
    var publicNeedScore: Double
    var publicSchemeFit: Double
    var publicOVR: Int
    var publicGradedAt: Date

    var trueGradeRaw: String?
    var trueGradedAt: Date?
    var isGem: Bool
    var isBust: Bool

    var publicGrade: PickGrade {
        get { PickGrade(rawValue: publicGradeRaw) ?? .solid }
        set { publicGradeRaw = newValue.rawValue }
    }

    var trueGrade: PickGrade? {
        get { trueGradeRaw.flatMap(PickGrade.init(rawValue:)) }
        set {
            trueGradeRaw = newValue?.rawValue
            trueGradedAt = newValue == nil ? nil : .now
        }
    }

    init(
        id: UUID = UUID(),
        pickID: UUID,
        draftYear: Int,
        pickNumber: Int,
        teamID: UUID,
        prospectID: UUID,
        playerID: UUID? = nil,
        publicGrade: PickGrade,
        publicValueDelta: Int,
        publicNeedScore: Double,
        publicSchemeFit: Double,
        publicOVR: Int,
        isGem: Bool = false,
        isBust: Bool = false,
        publicGradedAt: Date = .now
    ) {
        self.id = id
        self.pickID = pickID
        self.draftYear = draftYear
        self.pickNumber = pickNumber
        self.teamID = teamID
        self.prospectID = prospectID
        self.playerID = playerID
        self.publicGradeRaw = publicGrade.rawValue
        self.publicValueDelta = publicValueDelta
        self.publicNeedScore = publicNeedScore
        self.publicSchemeFit = publicSchemeFit
        self.publicOVR = publicOVR
        self.publicGradedAt = publicGradedAt
        self.isGem = isGem
        self.isBust = isBust
    }
}

enum PickGrade: String, Codable, CaseIterable {
    case stealAPlus = "A+"   // A+ Steal: top BPA fell to user, hit a need
    case smartA     = "A"    // A Smart Pick: solid value + need fit
    case solid      = "B"    // B Solid: nothing wrong
    case reach      = "C"    // C Reach: noticeable rank/value mismatch
    case bigReach   = "D"    // D Big Reach: ignored need + bad value
    case hofTrack   = "A++"  // True-grade only: HOF trajectory (gem)

    /// Display label shown alongside the letter, e.g. "STEAL".
    var qualifier: String {
        switch self {
        case .stealAPlus: return "STEAL"
        case .smartA:     return "SMART PICK"
        case .solid:      return "SOLID"
        case .reach:      return "REACH"
        case .bigReach:   return "BIG REACH"
        case .hofTrack:   return "HOF TRACK"
        }
    }
}
