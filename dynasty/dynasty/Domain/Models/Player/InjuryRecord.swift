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
