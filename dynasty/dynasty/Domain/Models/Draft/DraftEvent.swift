import Foundation
import SwiftData

/// Persisted record of a single happening during the NFL Draft.
/// The full event log enables: post-draft replay, story-arc flashbacks
/// in later seasons, and ReAct-loop balance iteration with deterministic seeds.
@Model
final class DraftEvent {
    var id: UUID
    var draftYear: Int
    var sequence: Int
    var typeRaw: String
    var teamID: UUID?
    var pickNumber: Int?
    var round: Int?
    var prospectID: UUID?
    var payloadJSON: String?
    var timestamp: Date

    var type: DraftEventType {
        get { DraftEventType(rawValue: typeRaw) ?? .pickMade }
        set { typeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        draftYear: Int,
        sequence: Int,
        type: DraftEventType,
        teamID: UUID? = nil,
        pickNumber: Int? = nil,
        round: Int? = nil,
        prospectID: UUID? = nil,
        payloadJSON: String? = nil,
        timestamp: Date = .now
    ) {
        self.id = id
        self.draftYear = draftYear
        self.sequence = sequence
        self.typeRaw = type.rawValue
        self.teamID = teamID
        self.pickNumber = pickNumber
        self.round = round
        self.prospectID = prospectID
        self.payloadJSON = payloadJSON
        self.timestamp = timestamp
    }
}

enum DraftEventType: String, Codable, CaseIterable {
    case draftStarted
    case roundTransition
    case onTheClock
    case pickMade
    case clockExpired
    case tradeOffered
    case tradeAccepted
    case tradeDeclined
    case tradeExpired
    case bigDrop
    case positionRun
    case stealAlert
    case scoutInterrupt
    case mediaReaction
    case ownerReaction
    case lockerRoomReaction
    case fanReaction
    case draftCompleted
}
