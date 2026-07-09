import Foundation
import SwiftData

enum HoldoutResolution: String, Codable, CaseIterable {
    case extended, bonusGiven, traded, unresolved
    /// R22: the player gave up and reported back without a new deal (~week 3-4).
    case playerCaved
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

    /// R22: number of regular-season weeks the holdout has been active.
    /// Drives the "player caves around week 3-4" mechanic.
    /// Default-value stored property → safe lightweight migration.
    var weeksActive: Int = 0

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
