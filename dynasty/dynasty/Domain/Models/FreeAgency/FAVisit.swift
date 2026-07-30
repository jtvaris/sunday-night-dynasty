import Foundation
import SwiftData

enum FAVisitStatus: String, Codable, CaseIterable {
    case active, expired, converted, cancelled
}

@Model
final class FAVisit {
    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    var playerID: UUID
    var teamID: UUID
    var seasonYear: Int
    var startedAt: Date
    var expiresAt: Date          // 24h or 48h after start
    var statusRaw: String

    var status: FAVisitStatus {
        get { FAVisitStatus(rawValue: statusRaw) ?? .active }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        playerID: UUID,
        teamID: UUID,
        seasonYear: Int,
        startedAt: Date = Date(),
        expiresAt: Date,
        status: FAVisitStatus = .active
    ) {
        self.id = id
        self.playerID = playerID
        self.teamID = teamID
        self.seasonYear = seasonYear
        self.startedAt = startedAt
        self.expiresAt = expiresAt
        self.statusRaw = status.rawValue
    }
}
