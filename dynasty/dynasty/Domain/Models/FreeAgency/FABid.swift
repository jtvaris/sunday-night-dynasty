import Foundation
import SwiftData

enum FABidPhase: String, Codable, CaseIterable {
    case morning, afternoon, evening
}

enum FABidStatus: String, Codable, CaseIterable {
    case pending, accepted, countered, expired, outbid
}

@Model
final class FABid {
    var id: UUID
    var playerID: UUID
    var teamID: UUID
    var seasonYear: Int
    var dayNumber: Int
    var phaseRaw: String
    var years: Int
    var baseSalary: Int        // thousands
    var signingBonus: Int      // thousands
    var guaranteed: Int        // thousands
    var statusRaw: String
    var submittedAt: Date
    var expiresAt: Date?

    var phase: FABidPhase {
        get { FABidPhase(rawValue: phaseRaw) ?? .morning }
        set { phaseRaw = newValue.rawValue }
    }

    var status: FABidStatus {
        get { FABidStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        playerID: UUID,
        teamID: UUID,
        seasonYear: Int,
        dayNumber: Int = 1,
        phase: FABidPhase = .morning,
        years: Int = 1,
        baseSalary: Int = 0,
        signingBonus: Int = 0,
        guaranteed: Int = 0,
        status: FABidStatus = .pending,
        submittedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.playerID = playerID
        self.teamID = teamID
        self.seasonYear = seasonYear
        self.dayNumber = dayNumber
        self.phaseRaw = phase.rawValue
        self.years = years
        self.baseSalary = baseSalary
        self.signingBonus = signingBonus
        self.guaranteed = guaranteed
        self.statusRaw = status.rawValue
        self.submittedAt = submittedAt
        self.expiresAt = expiresAt
    }
}
