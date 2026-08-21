import Foundation

// `DraftEventEngine` used to live here: 229 lines of pre-built event stream with
// zero callers, whose own header said "⚠️ NOT WIRED". Deleted by F-67. Its one
// asset — the position-RUN detector at its old `:170-180`, three picks in a row
// at the same position — was harvested first and now lives where it can decide
// something, as `DraftEngine.aiMakePick`'s `runWindow` / `runThreshold` (F-27).
// The engine's own version only *announced* runs to a stream nobody consumed.
//
// `PlannedDraftEvent` stays because it is genuinely live: `DraftDayCoordinator`
// builds and publishes it (`recentEvents`) for the draft room's ticker.

/// Lightweight, in-memory representation of a planned draft event.
/// (Persisted form is `DraftEvent` — `DraftDayCoordinator` converts when consuming.)
struct PlannedDraftEvent {
    let sequence: Int
    let type: DraftEventType
    let teamID: UUID?
    let pickNumber: Int?
    let round: Int?
    /// Convenience accessor for `pickMade` / `bigDrop` — duplicated from metadata for ergonomic access.
    let prospectID: UUID?
    let metadata: Metadata

    enum Metadata {
        case none
        case pick(prospectID: UUID, isPlayerTeam: Bool)
        case bigDrop(prospectID: UUID, expectedPick: Int, actualPick: Int)
        case positionRun(position: String, count: Int)
        case round(roundNumber: Int)
    }
}
