import Foundation

// MARK: - Locker Room Event (R25)

/// A discrete locker-room happening generated during the regular season from
/// player personalities, morale, and recent results. Persisted as JSON on
/// `Career` — a rolling log of resolved events plus (at most) one pending
/// choice event awaiting the coach's response in the Locker Room screen.
struct LockerRoomEvent: Codable, Identifiable {

    enum Kind: String, Codable {
        /// A frustrated hothead blows up after a loss (choice event).
        case outburst
        /// A team leader calls a players-only meeting during a good stretch.
        case playersOnlyMeeting
        /// A veteran mentor takes a young player at his position under his wing.
        case mentorMoment
        /// Two stars in the same room without a clear pecking order (choice event).
        case starTension
        /// The class clown keeps the room loose after a rough result.
        case moodLift
    }

    let id: UUID
    let season: Int
    let week: Int
    let kind: Kind
    let title: String
    let detail: String
    /// Players directly involved — they receive the option's target morale delta.
    let playerIDs: [UUID]
    let playerNames: [String]
    /// Choices offered to the coach. Empty for informational events whose
    /// effect was applied the moment they were generated. By convention the
    /// LAST option is the passive one ("let it play out") — it is auto-applied
    /// if the coach ignores the situation for a full week.
    var options: [LockerRoomEventOption]
    /// Set once the event is resolved (option chosen or effect auto-applied).
    var resolutionSummary: String?

    /// True while a choice event still waits for the coach's decision.
    var requiresResponse: Bool { resolutionSummary == nil && !options.isEmpty }

    init(
        id: UUID = UUID(),
        season: Int,
        week: Int,
        kind: Kind,
        title: String,
        detail: String,
        playerIDs: [UUID] = [],
        playerNames: [String] = [],
        options: [LockerRoomEventOption] = [],
        resolutionSummary: String? = nil
    ) {
        self.id = id
        self.season = season
        self.week = week
        self.kind = kind
        self.title = title
        self.detail = detail
        self.playerIDs = playerIDs
        self.playerNames = playerNames
        self.options = options
        self.resolutionSummary = resolutionSummary
    }
}

// MARK: - Locker Room Event Option

/// One way the coach can respond to a pending locker-room event.
/// Morale deltas are intentionally small (within ±5) — locker-room drama
/// nudges the season, it never decides it.
struct LockerRoomEventOption: Codable, Identifiable {
    let id: UUID
    let label: String
    let detail: String
    /// Morale delta applied to the involved players (`LockerRoomEvent.playerIDs`).
    let targetMoraleDelta: Int
    /// Morale delta applied to the rest of the roster.
    let teamMoraleDelta: Int
    /// Text logged as the event's resolution after choosing this option.
    let outcomeSummary: String

    init(
        id: UUID = UUID(),
        label: String,
        detail: String,
        targetMoraleDelta: Int,
        teamMoraleDelta: Int,
        outcomeSummary: String
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.targetMoraleDelta = targetMoraleDelta
        self.teamMoraleDelta = teamMoraleDelta
        self.outcomeSummary = outcomeSummary
    }
}
