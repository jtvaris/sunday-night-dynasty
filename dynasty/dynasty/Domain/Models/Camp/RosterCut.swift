import Foundation
import SwiftData

/// Single player release recorded during one of the three roster cut days.
/// Cap-savings and dead-cap values are stored in thousands to match the rest of the project.
@Model
final class RosterCut {
    var id: UUID
    var playerID: UUID
    var teamID: UUID
    var seasonYear: Int
    /// Raw value of `CutDay`: cut90To75 / cut75To65 / cut65To53.
    var cutDayRaw: String
    /// Cap savings in thousands (e.g. 4500 = $4.5M).
    var capSavings: Int
    /// Dead cap (signing bonus acceleration) in thousands.
    var deadCap: Int
    /// Set if the player was claimed off waivers within 24h.
    var claimedByTeamID: UUID?
    /// Eligible for a 10-man practice squad spot (vested-vet rule etc.).
    var practiceSquadEligible: Bool
    var occurredAt: Date

    init(
        id: UUID = UUID(),
        playerID: UUID,
        teamID: UUID,
        seasonYear: Int,
        cutDayRaw: String,
        capSavings: Int,
        deadCap: Int,
        claimedByTeamID: UUID? = nil,
        practiceSquadEligible: Bool = false,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.playerID = playerID
        self.teamID = teamID
        self.seasonYear = seasonYear
        self.cutDayRaw = cutDayRaw
        self.capSavings = capSavings
        self.deadCap = deadCap
        self.claimedByTeamID = claimedByTeamID
        self.practiceSquadEligible = practiceSquadEligible
        self.occurredAt = occurredAt
    }

    var cutDay: CutDay {
        get { CutDay(rawValue: cutDayRaw) ?? .cut90To75 }
        set { cutDayRaw = newValue.rawValue }
    }
}
