import Foundation
import SwiftData

/// Persistent draft reputation per career-season — tracks how the four
/// reaction actors (owner, media, locker room, fans) view the user's draft
/// performance.
///
/// Mutated by `ReactionsEngine` after each pick / trade. Read by the Round
/// Recap card, the post-draft summary, and downstream season effects (e.g.
/// owner trust feeding into job security).
@Model
final class DraftReputation {
    var id: UUID
    var seasonYear: Int
    var careerID: UUID

    var ownerTrust: Int          // 0..100, default 70
    var fanMood: Int             // 0..100, default 60
    var lockerRoomMood: Int      // 0..100, default 65
    var mediaNarrativeRaw: String  // raw value of MediaNarrative

    var mediaNarrative: MediaNarrative {
        get { MediaNarrative(rawValue: mediaNarrativeRaw) ?? .neutral }
        set { mediaNarrativeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        seasonYear: Int,
        careerID: UUID,
        ownerTrust: Int = 70,
        fanMood: Int = 60,
        lockerRoomMood: Int = 65,
        mediaNarrative: MediaNarrative = .neutral
    ) {
        self.id = id
        self.seasonYear = seasonYear
        self.careerID = careerID
        self.ownerTrust = ownerTrust
        self.fanMood = fanMood
        self.lockerRoomMood = lockerRoomMood
        self.mediaNarrativeRaw = mediaNarrative.rawValue
    }
}

/// Five rolling narratives the media can spin around the user's draft.
/// Selected by `ReactionsEngine.updateNarrative` based on cumulative pick
/// patterns.
enum MediaNarrative: String, Codable, CaseIterable {
    case conservative      // "playing it safe"
    case neutral
    case starHunter        // "swinging for the fences"
    case rebuilder         // "investing in the long term"
    case gambler           // "rolling the dice"

    var headline: String {
        switch self {
        case .conservative: return "Playing It Safe"
        case .neutral:      return "Steady Hand"
        case .starHunter:   return "Swinging For The Fences"
        case .rebuilder:    return "Investing In The Long Term"
        case .gambler:      return "Rolling The Dice"
        }
    }
}
