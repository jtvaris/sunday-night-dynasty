import Foundation

// MARK: - Injury Record (R28)

/// One entry in a player's permanent injury history. Stored as a JSON-encoded
/// array in `Player.injuryHistoryData` (lightweight migration — optional Data).
struct InjuryRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// `InjuryType.rawValue` of the injury.
    var injuryTypeRaw: String
    /// Projected weeks out at the time of the injury.
    var weeksOut: Int
    /// Season year the injury happened in (0 = unknown, e.g. legacy data).
    var season: Int = 0
    /// Week of the season the injury happened in (0 = unknown).
    var week: Int = 0

    var injuryType: InjuryType? { InjuryType(rawValue: injuryTypeRaw) }

    /// Compact display like "Knee (MCL/ACL) — 6 wks, Wk 4 2027".
    var summary: String {
        var text = "\(injuryTypeRaw) — \(weeksOut) wk\(weeksOut == 1 ? "" : "s")"
        if season > 0 {
            text += week > 0 ? ", Wk \(week) \(season)" : ", \(season)"
        }
        return text
    }
}

// MARK: - Career totals

extension Collection where Element == InjuryRecord {

    /// **Weeks, deliberately — not games.**
    ///
    /// The player card showed per-injury summaries and a durability rating and
    /// nothing that added them up, so "Durability 83" had nothing to be measured
    /// against. This is that total.
    ///
    /// It counts `weeksOut`, the projection recorded at the moment of the
    /// injury, because that is the only quantity the history stores. A week of
    /// the regular season is a game, but a long lay-off can run past Week 18
    /// into an offseason nobody plays games in — so calling the sum "games
    /// missed" would over-count exactly the injuries that matter most. The
    /// honest headline is the one the data supports.
    var careerWeeksMissed: Int {
        reduce(0) { $0 + max(0, $1.weeksOut) }
    }
}

// MARK: - Rehab Status (R28)

/// Weekly rehab trajectory for an injured player, set by
/// `MedicalEngine.processWeeklyRehab`. Purely informational — the weeks
/// counter itself is the source of truth for availability.
enum RehabStatus: String, Codable, CaseIterable {
    case aheadOfSchedule = "AheadOfSchedule"
    case onTrack         = "OnTrack"
    case setback         = "Setback"

    var displayName: String {
        switch self {
        case .aheadOfSchedule: return "Ahead of schedule"
        case .onTrack:         return "On track"
        case .setback:         return "Setback"
        }
    }

    var icon: String {
        switch self {
        case .aheadOfSchedule: return "arrow.up.right.circle.fill"
        case .onTrack:         return "checkmark.circle"
        case .setback:         return "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Return Decision (R28)

/// A pending "rush back vs. hold out" call on a user-team player entering the
/// final week of rehab. Stored JSON-encoded on `Career`. Default (no action)
/// is always the safe path: the player simply completes rehab normally.
struct ReturnDecision: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var playerID: UUID
    var playerName: String
    var injuryTypeRaw: String
    var season: Int
    var week: Int
}
