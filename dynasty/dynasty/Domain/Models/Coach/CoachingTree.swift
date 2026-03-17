import Foundation

// MARK: - CoachingTreeData

/// A Codable wrapper around the player's full coaching tree history.
///
/// Stored as a transformable property on `Career` so it persists across seasons.
/// Use `CoachRelationshipEngine` to mutate the `entries` array.
struct CoachingTreeData: Codable {

    /// All coaches who have worked under the player during their career.
    /// Includes both current staff members and departed/retired alumni.
    var entries: [CoachRelationshipEngine.CoachingTreeEntry]

    init(entries: [CoachRelationshipEngine.CoachingTreeEntry] = []) {
        self.entries = entries
    }

    // MARK: - Convenience Accessors

    /// Coaches who are no longer on staff (have a departure year).
    var alumni: [CoachRelationshipEngine.CoachingTreeEntry] {
        entries.filter { $0.yearLeft != nil }
    }

    /// Coaches who are currently on staff (no departure year recorded yet).
    var currentStaff: [CoachRelationshipEngine.CoachingTreeEntry] {
        entries.filter { $0.yearLeft == nil }
    }

    /// Alumni who departed for Head Coach positions.
    var headsCoachAlumni: [CoachRelationshipEngine.CoachingTreeEntry] {
        alumni.filter {
            $0.destination?.lowercased().contains("hc") == true ||
            $0.destination?.lowercased().contains("head coach") == true
        }
    }

    /// 0–100 legacy score calculated from the depth and success of the coaching tree.
    var legacyScore: Int {
        CoachRelationshipEngine.legacyScore(for: entries)
    }
}
