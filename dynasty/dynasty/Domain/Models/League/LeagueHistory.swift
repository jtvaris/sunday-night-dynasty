import Foundation

// MARK: - League History (R32)

/// One completed season's summary, stored JSON-encoded on `Career`
/// (`leagueHistoryData`, newest first, capped at 20 seasons).
/// Written by `WeekAdvancer` during the `.superBowl` phase while the final
/// records are still intact.
struct SeasonSummary: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Calendar season year (e.g. 2026).
    var season: Int
    /// League champion (Super Bowl winner). Nil only for legacy edge cases.
    var championTeamID: UUID?
    var championTeamName: String
    /// The user's team regular-season record.
    var userWins: Int
    var userLosses: Int
    var userTies: Int
    /// Whether the user's team was in the 14-team playoff bracket.
    var userMadePlayoffs: Bool
    /// Whether the user's team won the championship.
    var userWonChampionship: Bool
    /// Regular-season MVP (top of the R29 MVP race), if tracked.
    var mvpName: String?
    var mvpTeamAbbr: String?

    var userRecordText: String {
        userTies > 0 ? "\(userWins)-\(userLosses)-\(userTies)" : "\(userWins)-\(userLosses)"
    }
}

// MARK: - Hall of Fame (R32)

/// A retired legend inducted into the Hall of Fame. Stored JSON-encoded on
/// `Career` (`hallOfFameData`, newest induction class first).
/// Career facts are snapshotted at induction so the entry stays valid even
/// if the underlying `Player` row is ever pruned.
struct HallOfFameEntry: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var playerName: String
    var positionRaw: String
    /// Best end-of-season overall across the career (from PlayerSeasonHistory).
    var peakOverall: Int
    /// Age at retirement.
    var finalAge: Int
    /// Pro seasons played at retirement.
    var seasonsPlayed: Int
    /// Season the player was inducted (= retirement offseason).
    var inductionSeason: Int
    /// Team the player retired from ("Free Agent" when unsigned).
    var retiredFromTeamName: String
    /// True when the player retired off the user's roster.
    var wasUserTeamPlayer: Bool
}
