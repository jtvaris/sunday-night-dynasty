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

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

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

    /// The career season this standoff belongs to (`career.currentSeason` when
    /// it started). Holdouts begin at OTAs and the season counter only advances
    /// when the next regular season kicks off, so a holdout started in an
    /// offseason carries the year of the season that just finished — the same
    /// value the following `.trainingCamp` reads.
    ///
    /// Phase 2 (plan §2.4/§2.9.7) needs it: a player whose holdout was settled
    /// LATE still missed camp reps and takes a 0.7 health gate that offseason,
    /// and without a season stamp a resolved standoff from three years ago
    /// would look identical to this one. `startedAt` is wall-clock and cannot
    /// answer the question. `0` = unknown (legacy row) and never matches a real
    /// season. Default-value stored property → safe lightweight migration.
    var seasonYear: Int = 0

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
