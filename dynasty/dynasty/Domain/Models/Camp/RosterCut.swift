import Foundation
import SwiftData

/// Single player release recorded during one of the three roster cut days.
/// Cap-savings and dead-cap values are stored in thousands to match the rest of the project.
@Model
final class RosterCut {
    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    var playerID: UUID
    var teamID: UUID
    var seasonYear: Int
    /// Raw value of `CutDay`: cut90To75 / cut75To65 / cut65To53 — OR, for a
    /// release booked outside the camp ladder (#188), the raw value of
    /// ``ReleaseReason``. Every camp-ladder reader already guards with
    /// `CutDay(rawValue:)` and skips what it does not recognise, which is what
    /// keeps an in-season cut out of the cutdown counts and out of waivers.
    var cutDayRaw: String
    /// Why the man was let go, when the engine booked the receipt (#188).
    /// `nil` on rows written by the camp cutdown screen, whose reason is the
    /// cut day itself. Default-value stored property, never in `init` -> safe
    /// lightweight migration.
    var releaseReasonRaw: String? = nil
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

    /// True when this row is one of the three camp cutdown days, i.e. the only
    /// kind of release the waiver wire and the practice-squad "own cuts first"
    /// rule are allowed to act on. An in-season or cap-compliance release is a
    /// receipt for the Cap screen, nothing more.
    var isCampCutdown: Bool { CutDay(rawValue: cutDayRaw) != nil }

    /// The engine's reason, when one was recorded.
    var releaseReason: ReleaseReason? {
        releaseReasonRaw.flatMap(ReleaseReason.init(rawValue:))
    }
}

/// Why a release was booked, for the receipts `CapManagementEngine.applyRelease`
/// writes on every path that cuts a player with a `ModelContext` in hand (#188).
///
/// Kept out of `CutDay` on purpose: adding cases there would put in-season
/// releases into the camp cutdown ladder, the waiver pool and the practice-squad
/// keeper list, none of which they belong in.
enum ReleaseReason: String, Codable, CaseIterable {
    /// Cut from the player's own detail screen.
    case rosterMove
    /// Released from the contract screen (a deal the club walked away from).
    case contractRelease
    /// Cut to get back under the cap during the compliance flow.
    case capCompliance
    /// Booked by the camp cutdown screen through the engine.
    case campCut

    var label: String {
        switch self {
        case .rosterMove:      return "Roster move"
        case .contractRelease: return "Contract release"
        case .capCompliance:   return "Cap compliance"
        case .campCut:         return "Camp cut"
        }
    }
}
