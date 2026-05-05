import Foundation
import SwiftData

/// Tracks the unfolding career story for a drafted player, used to surface
/// gem/bust flashbacks across seasons.
///
/// Updated by `CareerArcEngine` (added in Vaihe 5) at offseason boundaries
/// based on accumulated stats, milestones (Pro Bowl, All-Pro, extension), and
/// negative events (cut before contract end).
@Model
final class CareerArcState {
    var id: UUID
    var playerID: UUID
    var draftYear: Int
    var draftPickNumber: Int

    var milestoneFlagsRaw: Int           // bitmask of CareerMilestone
    var probowlCount: Int
    var allProCount: Int
    var startSeasons: Int
    var contractExtended: Bool
    var cutBeforeContractEnd: Bool

    var lastEvaluatedSeason: Int?
    var currentArcTagRaw: String?

    var milestones: Set<CareerMilestone> {
        get {
            CareerMilestone.allCases.filter { milestoneFlagsRaw & $0.bit != 0 }.reduce(into: []) { $0.insert($1) }
        }
        set {
            milestoneFlagsRaw = newValue.reduce(0) { $0 | $1.bit }
        }
    }

    var currentArcTag: CareerArcTag? {
        get { currentArcTagRaw.flatMap(CareerArcTag.init(rawValue:)) }
        set { currentArcTagRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        playerID: UUID,
        draftYear: Int,
        draftPickNumber: Int
    ) {
        self.id = id
        self.playerID = playerID
        self.draftYear = draftYear
        self.draftPickNumber = draftPickNumber
        self.milestoneFlagsRaw = 0
        self.probowlCount = 0
        self.allProCount = 0
        self.startSeasons = 0
        self.contractExtended = false
        self.cutBeforeContractEnd = false
    }
}

enum CareerMilestone: String, Codable, CaseIterable {
    case rookieOfYear
    case proBowl
    case allPro
    case contractExtension
    case probowlMVP
    case bustEvent

    var bit: Int { 1 << (CareerMilestone.allCases.firstIndex(of: self) ?? 0) }
}

enum CareerArcTag: String, Codable, CaseIterable {
    case sleeper           // gem candidate, low public grade, rising true grade
    case homeRun           // gem confirmed
    case earlyContributor  // rookie season impact
    case slowBurn          // year 2-3 jump
    case anchor            // long-term starter
    case bust              // failed to live up
    case journeyman
    case neutral
}
