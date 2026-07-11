import SceneKit

// MARK: - Recorded Play (R35: replays & highlights)

/// One finished play captured for replay. The choreography is a
/// deterministic step list, so a replay is nothing more than restaging the
/// pre-snap picture and running the exact same steps through the same scene
/// under a different camera — this struct carries everything that restage
/// needs, plus the presentation copy for the title plate.
///
/// Pure value type, view-side only: the engine, the game clock and the sim
/// distributions never see it.
struct RecordedPlay {
    /// Engine play number — keeps the highlight reel chronological after
    /// the score-based selection re-orders candidates.
    let sequence: Int
    /// The full deterministic timeline the live play ran.
    let steps: [FootballFieldScene.PlayStep]

    // Pre-snap restage — the same arguments the live snap fed the scene.
    let formationHome: [(x: Float, z: Float, number: Int)]
    let formationAway: [(x: Float, z: Float, number: Int)]
    let stancesHome: [Int: FootballFieldScene.Stance]
    let stancesAway: [Int: FootballFieldScene.Stance]
    let bodyTypesHome: [Int: FootballFieldScene.BodyType]
    let bodyTypesAway: [Int: FootballFieldScene.BodyType]
    /// World Z of the line of scrimmage on the recorded snap.
    let losZ: Float
    /// World Z of the first-down stripe (nil = goal to go).
    let firstDownZ: Float?
    /// +1 when the offense drove toward +Z on the recorded snap.
    let direction: Float

    /// Ended in six — the replay defaults to the end zone angle.
    let isTouchdown: Bool
    /// Scene node index (0-21) of the defense's key man on the play — the
    /// isolation camera's subject. Nil when no defender was named.
    let keyDefenderNode: Int?
    /// Title plate copy, e.g. "Q2 — M. Dixon 34 yd TD".
    let title: String
    /// Highlight-reel weight; 0 = routine play (recent-buffer only).
    let highlightScore: Int
}
