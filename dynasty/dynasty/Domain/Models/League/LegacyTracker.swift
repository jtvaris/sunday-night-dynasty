import Foundation

struct LegacyTracker: Codable, Equatable {

    var totalPoints: Int
    var pressPromises: [PressPromise]
    var achievements: [LegacyAchievement]

    /// Media reputation on a scale from -100 (villain) to 100 (beloved).
    var mediaReputation: Int

    init(
        totalPoints: Int = 0,
        pressPromises: [PressPromise] = [],
        achievements: [LegacyAchievement] = [],
        mediaReputation: Int = 0
    ) {
        self.totalPoints = totalPoints
        self.pressPromises = pressPromises
        self.achievements = achievements
        self.mediaReputation = mediaReputation
    }

    // MARK: - Press Promise

    struct PressPromise: Codable, Identifiable, Equatable {
        let id: UUID
        let statement: String
        let season: Int
        var isDelivered: Bool?

        init(
            id: UUID = UUID(),
            statement: String,
            season: Int,
            isDelivered: Bool? = nil
        ) {
            self.id = id
            self.statement = statement
            self.season = season
            self.isDelivered = isDelivered
        }
    }

    // MARK: - Legacy Achievement

    struct LegacyAchievement: Codable, Identifiable, Equatable {
        let id: UUID
        let title: String
        let description: String
        let points: Int
        let season: Int

        init(
            id: UUID = UUID(),
            title: String,
            description: String,
            points: Int,
            season: Int
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.points = points
            self.season = season
        }
    }

    // MARK: - Mutating Helpers

    /// Apply the total effects from a press conference result.
    mutating func applyPressConferenceResult(_ result: PressConferenceResult, season: Int) {
        totalPoints += result.totalEffects.legacyPoints
        mediaReputation = max(-100, min(100, mediaReputation + result.totalEffects.mediaPerception))

        // Record promises with the correct season
        for promise in result.promises {
            pressPromises.append(PressPromise(
                statement: promise.statement,
                season: season
            ))
        }
    }

    /// Record a new achievement and add its points to the total.
    mutating func recordAchievement(_ achievement: LegacyAchievement) {
        achievements.append(achievement)
        totalPoints += achievement.points
    }

    // MARK: - Computed Properties

    /// A human-readable description of the current media reputation.
    var reputationLabel: String {
        switch mediaReputation {
        case 60...:     return "Media Darling"
        case 30..<60:   return "Well-Liked"
        case 10..<30:   return "Respected"
        case -10..<10:  return "Neutral"
        case -30 ..< -10: return "Scrutinized"
        case -60 ..< -30: return "Controversial"
        default:        return "Villain"
        }
    }

    /// Outstanding promises that have not yet been resolved.
    var pendingPromises: [PressPromise] {
        pressPromises.filter { $0.isDelivered == nil }
    }
}
