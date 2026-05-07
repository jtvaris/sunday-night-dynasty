import Foundation
import SwiftData

/// Daily atomic record of a player's workload load/recovery delta.
/// Aggregated by `WorkloadEngine` to compute `cumulativeLoad` and classify status.
@Model
final class WorkloadEvent {
    var id: UUID
    var playerID: UUID
    var seasonYear: Int
    /// Day of the camp / season week, 0-6.
    var dayOfWeek: Int
    /// Positive integer for training intensity load.
    var loadDelta: Int
    /// Positive integer for recovery (e.g. off day, light walk-through).
    var recoveryDelta: Int
    var occurredAt: Date

    init(
        id: UUID = UUID(),
        playerID: UUID,
        seasonYear: Int,
        dayOfWeek: Int,
        loadDelta: Int,
        recoveryDelta: Int,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.playerID = playerID
        self.seasonYear = seasonYear
        self.dayOfWeek = dayOfWeek
        self.loadDelta = loadDelta
        self.recoveryDelta = recoveryDelta
        self.occurredAt = occurredAt
    }
}
