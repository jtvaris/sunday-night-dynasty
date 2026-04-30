import Foundation
import SwiftData

/// Per-season snapshot of a player's career history. One record is created
/// per player per completed regular season, written by `WeekAdvancer` when
/// week 18 ends. Used by the Player Detail screen to show:
/// - Career trend (OVR over the last N seasons)
/// - Career stats table (per-season totals)
///
/// Stats fields are intentionally generic (`keyStat1/2/3`) so they can hold
/// position-appropriate totals decided by the UI/recorder. Today the recorder
/// only fills `overallAtEndOfSeason`, `gamesPlayed`, `age`, and `teamID`;
/// per-season aggregated stats are a follow-up because per-game `PlayerGameStats`
/// are not currently persisted across seasons.
@Model
final class PlayerSeasonHistory {
    var id: UUID
    var playerID: UUID

    /// Calendar season year this record describes (e.g. 2026).
    var season: Int

    /// Player's overall rating snapshot at the end of the season, before any
    /// offseason development/age regression has been applied.
    var overallAtEndOfSeason: Int

    /// Number of games the player appeared in this season. (Currently 0 —
    /// per-game appearances aren't tracked across the league. Reserved.)
    var gamesPlayed: Int

    /// Player's age during this season (snapshot — useful when age regression
    /// later modifies the live `Player.age`).
    var ageAtEndOfSeason: Int

    /// Team the player ended the season on (nil if unsigned/free agent).
    var teamID: UUID?

    /// Position-appropriate primary stat (e.g. passing yards for QB,
    /// rushing yards for RB, tackles for LB). 0 when not yet recorded.
    var keyStat1: Int

    /// Position-appropriate secondary stat (e.g. passing TDs, rushing TDs,
    /// sacks, INTs caught). 0 when not yet recorded.
    var keyStat2: Int

    /// Position-appropriate tertiary stat (e.g. INTs thrown, fumbles,
    /// forced fumbles, FG made). 0 when not yet recorded.
    var keyStat3: Int

    init(
        id: UUID = UUID(),
        playerID: UUID,
        season: Int,
        overallAtEndOfSeason: Int,
        gamesPlayed: Int = 0,
        ageAtEndOfSeason: Int,
        teamID: UUID? = nil,
        keyStat1: Int = 0,
        keyStat2: Int = 0,
        keyStat3: Int = 0
    ) {
        self.id = id
        self.playerID = playerID
        self.season = season
        self.overallAtEndOfSeason = overallAtEndOfSeason
        self.gamesPlayed = gamesPlayed
        self.ageAtEndOfSeason = ageAtEndOfSeason
        self.teamID = teamID
        self.keyStat1 = keyStat1
        self.keyStat2 = keyStat2
        self.keyStat3 = keyStat3
    }
}
