import Foundation
import SwiftData

/// Daily atomic record of a player's workload load/recovery delta.
/// Aggregated by `WorkloadEngine` to compute `cumulativeLoad` and classify status.
@Model
final class WorkloadEvent {
    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    #Index<WorkloadEvent>([\.careerID])

    var playerID: UUID
    var seasonYear: Int
    /// Day of the camp / season week, 0-6.
    var dayOfWeek: Int

    /// The GAME week this day belongs to (`Career.currentWeek`).
    ///
    /// `seasonYear` + `dayOfWeek` alone could not place a row on the calendar —
    /// and until phase 2 both were stamped from `Calendar.current`, i.e. the
    /// real-world clock of whoever was playing (plan §2.9.6). `0` is the
    /// "unknown week" default legacy rows keep. Default-value stored property,
    /// never in `init` → safe lightweight migration.
    var weekNumber: Int = 0
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
