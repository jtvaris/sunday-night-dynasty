import Foundation

// MARK: - Development Report (R26)

/// One week's player-development digest for the user's team: who improved
/// and why (training focus, mentorship, breakout), who is stalled and why
/// (holdout, injury, morale, age curve). Persisted on `Career` as JSON,
/// newest first, capped at the last 10 weeks.
struct DevelopmentReport: Codable, Identifiable {
    var id: UUID = UUID()
    let season: Int
    let week: Int
    var risers: [Entry] = []
    var breakouts: [Entry] = []
    var stalled: [Entry] = []
    var mentorships: [MentorLine] = []

    var isEmpty: Bool {
        risers.isEmpty && breakouts.isEmpty && stalled.isEmpty && mentorships.isEmpty
    }

    // MARK: Entry

    /// A single player line in the report.
    struct Entry: Codable, Identifiable {
        var id: UUID = UUID()
        let playerID: UUID
        let playerName: String
        let positionRaw: String
        /// Concrete change or status, e.g. "+1 Route Running" or
        /// "Holding out — development paused".
        let detail: String
        let reasonRaw: String

        var reason: Reason { Reason(rawValue: reasonRaw) ?? .focus }
    }

    // MARK: Mentor Line

    /// An active veteran → youngster pairing surfaced from the R25 system.
    struct MentorLine: Codable, Identifiable {
        var id: UUID = UUID()
        let mentorName: String
        let protegeName: String
        let positionRaw: String
        /// e.g. "+10% development speed"
        let boostText: String
    }

    // MARK: Reason

    /// Why a player appears in the report — drives the chip label/color.
    ///
    /// Phase 2 (`docs/PLAYER_DEVELOPMENT_OVERHAUL_PLAN.md` §2.10) adds the four
    /// realization-model reasons. Persisted rows decode through
    /// `Reason(rawValue:) ?? .focus`, so an old save that predates them is
    /// unaffected and a new case can never break an archived report.
    enum Reason: String, Codable {
        case focus, mentor, breakout, morale, holdout, injury, ageCurve
        /// Where his head is at going into the season (§2.3).
        case motivation
        /// "He is what he is" — two offseasons without a step forward (§2.5).
        case plateau
        /// The year 3-5 breakout a changed situation unlocked (§2.5).
        case lateBloomer
        /// Install year: the playbook changed under him (§2.9.2).
        case schemeChange

        var label: String {
            switch self {
            case .focus:        return String(localized: "Training Focus")
            case .mentor:       return String(localized: "Mentored")
            case .breakout:     return String(localized: "Breakout")
            case .morale:       return String(localized: "Morale")
            case .holdout:      return String(localized: "Holdout")
            case .injury:       return String(localized: "Injured")
            case .ageCurve:     return String(localized: "Age Curve")
            case .motivation:   return String(localized: "Motivation")
            case .plateau:      return String(localized: "Plateau")
            case .lateBloomer:  return String(localized: "Late Bloomer")
            case .schemeChange: return String(localized: "New Scheme")
            }
        }

        /// SF Symbol that replaces the section default where the section icon
        /// would misread the line: a plateau is not a fall, and an install year
        /// is not a slump. `nil` = keep the section's own icon.
        var iconOverride: String? {
            switch self {
            case .motivation:   return "brain.head.profile"
            case .plateau:      return "equal.circle.fill"
            case .lateBloomer:  return "sparkles"
            case .schemeChange: return "book.closed.fill"
            default:            return nil
            }
        }
    }
}
