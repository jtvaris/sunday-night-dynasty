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
    enum Reason: String, Codable {
        case focus, mentor, breakout, morale, holdout, injury, ageCurve

        var label: String {
            switch self {
            case .focus:    return "Training Focus"
            case .mentor:   return "Mentored"
            case .breakout: return "Breakout"
            case .morale:   return "Morale"
            case .holdout:  return "Holdout"
            case .injury:   return "Injured"
            case .ageCurve: return "Age Curve"
            }
        }
    }
}
