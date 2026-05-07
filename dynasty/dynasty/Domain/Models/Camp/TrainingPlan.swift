import Foundation
import SwiftData

/// Per-week training focus allocation set by the GM.
/// The three pct values should sum to 100 and steer per-player attribute deltas
/// inside `TrainingPlanEngine`.
@Model
final class TrainingPlan {
    var id: UUID
    var seasonYear: Int
    var weekNumber: Int
    /// Raw value of `SeasonPhase` (e.g. "OTAs", "TrainingCamp", "RegularSeason").
    var phaseRaw: String
    var tacticalPct: Int
    var physicalPct: Int
    var technicalPct: Int
    var teamID: UUID

    init(
        id: UUID = UUID(),
        seasonYear: Int,
        weekNumber: Int,
        phaseRaw: String,
        tacticalPct: Int,
        physicalPct: Int,
        technicalPct: Int,
        teamID: UUID
    ) {
        self.id = id
        self.seasonYear = seasonYear
        self.weekNumber = weekNumber
        self.phaseRaw = phaseRaw
        self.tacticalPct = tacticalPct
        self.physicalPct = physicalPct
        self.technicalPct = technicalPct
        self.teamID = teamID
    }

    /// Convenience accessor to the typed phase enum (falls back to OTAs if raw is unknown).
    var phase: SeasonPhase {
        get { SeasonPhase(rawValue: phaseRaw) ?? .otas }
        set { phaseRaw = newValue.rawValue }
    }
}
