import Foundation
import SwiftData

enum FAStorylineEventType: String, Codable, CaseIterable {
    case revengeTour, loyaltyDiscount, coachReunion, hometown, mentorPair, holdout, milestone, community
}

@Model
final class FAStorylineEvent {
    var id: UUID
    var seasonYear: Int
    var typeRaw: String
    var playerID: UUID?
    var teamID: UUID?
    var headline: String
    var body: String
    var occurredAt: Date

    var type: FAStorylineEventType {
        get { FAStorylineEventType(rawValue: typeRaw) ?? .community }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        seasonYear: Int,
        type: FAStorylineEventType,
        playerID: UUID? = nil,
        teamID: UUID? = nil,
        headline: String,
        body: String,
        occurredAt: Date = Date()
    ) {
        self.id = id
        self.seasonYear = seasonYear
        self.typeRaw = type.rawValue
        self.playerID = playerID
        self.teamID = teamID
        self.headline = headline
        self.body = body
        self.occurredAt = occurredAt
    }
}
