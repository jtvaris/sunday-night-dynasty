import Foundation
import SwiftData

enum HoldoutResolution: String, Codable, CaseIterable {
    case extended, bonusGiven, traded, unresolved
}

@Model
final class Holdout {
    var id: UUID
    var playerID: UUID
    var teamID: UUID
    var startedAt: Date
    var resolvedAt: Date?
    var resolutionRaw: String?
    var subMarketDelta: Int       // thousands; how far below market

    var resolution: HoldoutResolution? {
        get {
            guard let raw = resolutionRaw else { return nil }
            return HoldoutResolution(rawValue: raw)
        }
        set { resolutionRaw = newValue?.rawValue }
    }

    init(
        id: UUID = UUID(),
        playerID: UUID,
        teamID: UUID,
        startedAt: Date = Date(),
        resolvedAt: Date? = nil,
        resolution: HoldoutResolution? = nil,
        subMarketDelta: Int = 0
    ) {
        self.id = id
        self.playerID = playerID
        self.teamID = teamID
        self.startedAt = startedAt
        self.resolvedAt = resolvedAt
        self.resolutionRaw = resolution?.rawValue
        self.subMarketDelta = subMarketDelta
    }
}
