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

/// Persistent storage for the GM's personal prospect grades and stars, in
/// `UserDefaults`, JSON-encoded and keyed by prospect UUID string.
///
/// ## Career scoping
///
/// The three keys this store owns are **career state, not app settings**: an "A+
/// / Top 5" on a prospect belongs to the save whose draft it was written in.
/// `CareerScopedDefaults` has listed them as scoped since the multi-save wave —
/// it purges them on delete and migrates the legacy globals into the adopting
/// career — but the store itself still read and wrote the *unsuffixed* keys via
/// `@AppStorage`, so none of that reached it. Two consequences, both live:
///
/// * a second career opened its Big Board already covered in the first career's
///   grades and stars (the ids never collide, but the board's "graded" filters,
///   counts and `originalBoardPositions` all did);
/// * worse, `migrateGlobalKeys` **moves** the global value to the scoped key and
///   deletes the global — so the first career the app opened after that wave
///   lost its board, because the store kept reading a key that had just been
///   emptied.
///
/// Hence the direct `UserDefaults` access below: `@AppStorage`'s key is fixed at
/// property-declaration time and the career is not known then. The key is
/// resolved per access from `WeekAdvancer.activeCareerID` — the same binding
/// every scoped SwiftData fetch keys on, so there is no second "which save is
/// open" notion to keep in sync. An unbound engine (previews, the moments before
/// the first `bind`) falls back to the unsuffixed key, which is also exactly
/// what `migrateGlobalKeys` reads.
///
/// `@AppStorage` in an `ObservableObject` never published anything anyway — it is
/// a `DynamicProperty`, which only does its work inside a `View` — so the views
/// have always refreshed off the explicit `objectWillChange.send()` calls, and
/// dropping it changes no update behaviour.
final class UserProspectGradeStore: ObservableObject {
    static let shared = UserProspectGradeStore()

    /// Base keys, all three of them already listed in `CareerScopedDefaults.keys`.
    private static let gradesKey = "userProspectGrades"
    private static let starsKey = "userProspectStars"
    private static let originalPositionsKey = "originalBoardPositions"

    /// The scoped key for the open career, or the bare key when no career is
    /// bound. Read at every access rather than cached: a career switch inside one
    /// launch has to be picked up without anyone remembering to notify the store.
    private func key(_ base: String) -> String {
        guard let careerID = WeekAdvancer.activeCareerID else { return base }
        return CareerScopedDefaults.key(base, careerID: careerID)
    }

    private func string(_ base: String, default fallback: String) -> String {
        UserDefaults.standard.string(forKey: key(base)) ?? fallback
    }

    private func setString(_ value: String, _ base: String) {
        UserDefaults.standard.set(value, forKey: key(base))
    }

    private var gradesJSON: String {
        get { string(Self.gradesKey, default: "{}") }
        set { setString(newValue, Self.gradesKey) }
    }

    private var starsJSON: String {
        get { string(Self.starsKey, default: "[]") }
        set { setString(newValue, Self.starsKey) }
    }

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

    private var originalBoardPositionsJSON: String {
        get { string(Self.originalPositionsKey, default: "{}") }
        set { setString(newValue, Self.originalPositionsKey) }
    }

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
