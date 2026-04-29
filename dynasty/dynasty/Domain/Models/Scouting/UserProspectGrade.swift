import SwiftUI
import Combine

// MARK: - User Grade Enum

/// The GM's personal grade for a prospect, separate from scout evaluations.
enum UserGrade: String, CaseIterable, Codable, Identifiable {
    case top5       = "Top 5"
    case top10      = "Top 10"
    case firstRound = "1st Round"
    case round1_2   = "Rounds 1-2"
    case round2_3   = "Rounds 2-3"
    case dayThree   = "Day Three"
    case udfa       = "UDFA"

    var id: String { rawValue }

    /// Short label for compact badge display.
    var shortLabel: String {
        switch self {
        case .top5:       return "Top 5"
        case .top10:      return "Top 10"
        case .firstRound: return "Rd 1"
        case .round1_2:   return "Rd 1-2"
        case .round2_3:   return "Rd 2-3"
        case .dayThree:   return "Day 3"
        case .udfa:       return "UDFA"
        }
    }

    /// Badge color for the grade.
    var color: Color {
        switch self {
        case .top5, .top10:         return .success
        case .firstRound, .round1_2: return .accentGold
        case .round2_3:             return .yellow
        case .dayThree, .udfa:      return .textSecondary
        }
    }

    /// Whether this grade qualifies as "first round or better" for filtering.
    var isFirstRoundPlus: Bool {
        switch self {
        case .top5, .top10, .firstRound: return true
        default: return false
        }
    }

    /// Convert user grade to a letter grade string for display.
    var letterGrade: String {
        switch self {
        case .top5:       return "A+"
        case .top10:      return "A"
        case .firstRound: return "A-"
        case .round1_2:   return "B+"
        case .round2_3:   return "B"
        case .dayThree:   return "C+"
        case .udfa:       return "C"
        }
    }
}

// MARK: - User Prospect Grade Store

/// Persistent storage for the GM's personal prospect grades and stars using AppStorage/UserDefaults.
/// Uses JSON-encoded dictionaries keyed by prospect UUID string.
final class UserProspectGradeStore: ObservableObject {
    static let shared = UserProspectGradeStore()

    @AppStorage("userProspectGrades") private var gradesJSON: String = "{}"
    @AppStorage("userProspectStars") private var starsJSON: String = "[]"

    // MARK: - Grades

    private var grades: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: Data(gradesJSON.utf8))) ?? [:]
    }

    func grade(for prospectID: UUID) -> UserGrade? {
        guard let raw = grades[prospectID.uuidString] else { return nil }
        return UserGrade(rawValue: raw)
    }

    func setGrade(_ grade: UserGrade?, for prospectID: UUID) {
        var dict = grades
        if let grade {
            dict[prospectID.uuidString] = grade.rawValue
        } else {
            dict.removeValue(forKey: prospectID.uuidString)
        }
        if let data = try? JSONEncoder().encode(dict) {
            gradesJSON = String(data: data, encoding: .utf8) ?? "{}"
        }
        objectWillChange.send()
    }

    // MARK: - Stars

    private var stars: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(starsJSON.utf8))) ?? [])
    }

    func isStarred(_ prospectID: UUID) -> Bool {
        stars.contains(prospectID.uuidString)
    }

    func toggleStar(for prospectID: UUID) {
        var set = stars
        let key = prospectID.uuidString
        if set.contains(key) {
            set.remove(key)
        } else {
            set.insert(key)
        }
        if let data = try? JSONEncoder().encode(Array(set)) {
            starsJSON = String(data: data, encoding: .utf8) ?? "[]"
        }
        objectWillChange.send()
    }

    // MARK: - Original Board Positions

    @AppStorage("originalBoardPositions") private var originalBoardPositionsJSON: String = "{}"

    private var originalBoardPositions: [String: Int] {
        (try? JSONDecoder().decode([String: Int].self, from: Data(originalBoardPositionsJSON.utf8))) ?? [:]
    }

    /// Only sets if not already set (preserves first auto-rank).
    func setOriginalPosition(for prospectID: UUID, position: Int) {
        var dict = originalBoardPositions
        let key = prospectID.uuidString
        if dict[key] == nil {
            dict[key] = position
            if let data = try? JSONEncoder().encode(dict) {
                originalBoardPositionsJSON = String(data: data, encoding: .utf8) ?? "{}"
            }
        }
    }

    func getOriginalPosition(for prospectID: UUID) -> Int? {
        originalBoardPositions[prospectID.uuidString]
    }

    /// Clear all original positions (for when auto-rank is re-run).
    func clearOriginalPositions() {
        originalBoardPositionsJSON = "{}"
        objectWillChange.send()
    }

    // MARK: - Filtering Helpers

    func isFirstRoundPlus(_ prospectID: UUID) -> Bool {
        grade(for: prospectID)?.isFirstRoundPlus ?? false
    }
}
