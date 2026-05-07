import Foundation
import SwiftData

/// GM-requested team workout. Outcome is computed by `VoluntaryWorkoutEngine`
/// based on personality mix and workout type.
@Model
final class VoluntaryWorkout {
    var id: UUID
    var seasonYear: Int
    var weekNumber: Int
    /// Raw value of `VoluntaryWorkoutType`.
    var typeRaw: String
    /// 0–100. Percentage of roster that actually participated.
    var participationPct: Int
    /// Scheme-knowledge bump applied to attendees.
    var schemeBonus: Int
    /// Locker-room delta (positive or negative).
    var lockerRoomDelta: Int
    /// Extra injury-risk percentage applied for the week.
    var injuryRiskBoost: Int
    var teamID: UUID

    init(
        id: UUID = UUID(),
        seasonYear: Int,
        weekNumber: Int,
        typeRaw: String,
        participationPct: Int,
        schemeBonus: Int,
        lockerRoomDelta: Int,
        injuryRiskBoost: Int,
        teamID: UUID
    ) {
        self.id = id
        self.seasonYear = seasonYear
        self.weekNumber = weekNumber
        self.typeRaw = typeRaw
        self.participationPct = participationPct
        self.schemeBonus = schemeBonus
        self.lockerRoomDelta = lockerRoomDelta
        self.injuryRiskBoost = injuryRiskBoost
        self.teamID = teamID
    }

    var type: VoluntaryWorkoutType {
        get { VoluntaryWorkoutType(rawValue: typeRaw) ?? .voluntaryOTAs }
        set { typeRaw = newValue.rawValue }
    }
}
