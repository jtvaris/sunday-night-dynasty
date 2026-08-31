import Foundation

nonisolated struct LegacyTracker: Codable, Equatable {

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

    nonisolated struct PressPromise: Codable, Identifiable, Equatable {
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

    nonisolated struct LegacyAchievement: Codable, Identifiable, Equatable {
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
    ///
    /// The reputation move goes through `adjustMediaReputation(by:)` rather than
    /// repeating the rails inline. This method used to carry its own copy of the
    /// −100…100 clamp, which meant two clamps on one field and two places to get
    /// the range wrong.
    mutating func applyPressConferenceResult(_ result: PressConferenceResult, season: Int) {
        totalPoints += result.totalEffects.legacyPoints
        adjustMediaReputation(by: result.totalEffects.mediaPerception)

        // Record promises with the correct season. #161: the authoritative
        // ledger (with kind, threshold and settlement) is
        // `Career.pressPromiseLedger`; this list stays the flat, display-only
        // history the legacy screens already read.
        for promise in result.promises {
            pressPromises.append(PressPromise(
                statement: promise.statement,
                season: season
            ))
        }
    }

    /// Move media reputation by `delta`, held to −100…100.
    ///
    /// **The only clamp on this field inside this type.** Both writers here go
    /// through it — `applyPressConferenceResult` and, from outside,
    /// `InboxEngine.applyReply` booking a media reply. Returns the movement that
    /// actually landed, which is 0 at either rail; a caller that reports a
    /// number to the user must report this one and not what it asked for.
    ///
    /// Two writers outside this type still clamp by hand rather than call it:
    /// `WeekAdvancer`'s promise settlement and `PressConferenceView`'s preview
    /// projection. Both are assignments to `career.legacy.mediaReputation` in
    /// files this change does not own.
    @discardableResult
    mutating func adjustMediaReputation(by delta: Int) -> Int {
        let before = mediaReputation
        mediaReputation = max(-100, min(100, before + delta))
        return mediaReputation - before
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
}
