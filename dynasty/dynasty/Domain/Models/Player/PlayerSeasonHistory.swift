import Foundation
import SwiftData

/// Per-season snapshot of a player's career history. One record is created
/// per player per completed regular season, written by `WeekAdvancer` when
/// week 18 ends — plus one per career-arc year at template import, and one per
/// backstory year for a randomly generated league. Used by the Player Detail
/// screen's "Career Stats by Season" table and by the development / retirement /
/// draft-grade engines.
///
/// ## Stats storage
///
/// The three original `keyStat1/2/3` slots were too narrow for a real career
/// table (GP plus three or four position-appropriate categories), so the
/// per-category totals live in typed columns instead — every one an optional
/// stored property with an inline default, i.e. a lightweight SwiftData
/// migration, exactly like `gamesStarted` before them. `keyStat1/2/3` are kept
/// and derived from the typed columns: they are still what the template
/// determinism fingerprint hashes, and deriving them means the legacy slots can
/// never drift out of step with what the UI shows.
///
/// Read and write the whole line through ``statLine`` rather than the individual
/// columns; ``positionRaw`` makes the row self-describing so the categories are
/// interpretable without joining back to `Player` (the same reason
/// `HallOfFameEntry` snapshots its own position).
///
/// The POSTSEASON line is a separate blob (``postStatLine``, #20) rather than a
/// second set of typed columns — see the note at its declaration. Nothing folds
/// it into the regular-season totals: a career table, a milestone and a Hall of
/// Fame résumé all mean the regular season when they say "career".
@Model
final class PlayerSeasonHistory {
    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    #Index<PlayerSeasonHistory>([\.careerID])

    var playerID: UUID

    /// Calendar season year this record describes (e.g. 2026).
    var season: Int

    /// Player's overall rating snapshot at the end of the season, before any
    /// offseason development/age regression has been applied.
    var overallAtEndOfSeason: Int

    /// Number of regular-season games the player appeared in this season (#33).
    /// Snapshotted from `Player.gamesPlayedThisSeason` at week 18: a player is
    /// credited an appearance each week his team plays and he is available
    /// (active roster, healthy, not holding out, not retired).
    var gamesPlayed: Int

    /// Number of regular-season games the player STARTED this season (#40).
    /// Snapshotted from `Player.gamesStartedThisSeason` at week 18: a player is
    /// credited a start each week he is in his team's projected starting lineup
    /// (top of the depth chart at his position among available teammates).
    /// Always ≤ `gamesPlayed`. 0 for legacy rows written before #40.
    /// Optional stored property with a default → safe lightweight migration.
    var gamesStarted: Int = 0

    /// Player's age during this season (snapshot — useful when age regression
    /// later modifies the live `Player.age`).
    var ageAtEndOfSeason: Int

    /// Team the player ended the season on (nil if unsigned/free agent).
    var teamID: UUID?

    /// `Position.rawValue` the player held this season — snapshotted so the stat
    /// columns stay interpretable if he later changes position (or if the
    /// `Player` row is ever pruned). Empty string on rows written before the
    /// career-stats wave. Default → lightweight migration.
    var positionRaw: String = ""

    // MARK: - Season stat line
    //
    // Typed per-category totals. All default to 0 → lightweight migration.
    // Populate via `statLine`, never field by field: the setter also refreshes
    // the derived `keyStat1/2/3` slots.

    var passYards: Int = 0
    var passTDs: Int = 0
    /// Interceptions THROWN (see `defInts` for picks caught).
    var passInts: Int = 0
    var rushYards: Int = 0
    var rushTDs: Int = 0
    var receptions: Int = 0
    var recYards: Int = 0
    var recTDs: Int = 0
    var tackles: Int = 0
    /// Fractional — half-sacks are real football.
    var sacks: Double = 0
    /// Interceptions CAUGHT.
    var defInts: Int = 0
    var passesDefended: Int = 0
    var fieldGoalsMade: Int = 0
    var fieldGoalsAttempted: Int = 0
    var punts: Int = 0
    /// Gross punt average in yards.
    var puntAverage: Double = 0
    /// Offensive snaps — the only volume stat an interior lineman has.
    var snapsPlayed: Int = 0

    /// True when the line was modelled by `SeasonStatSynthesizer` rather than
    /// accumulated from a real box score. Every season before the career started
    /// is synthesized, as is every AI team's season (their games are
    /// score-only). Provenance only — nothing branches on it today.
    var statsAreSynthesized: Bool = false

    // MARK: - Postseason line (#20)
    //
    // The playoffs are a SEPARATE line, never folded into the regular-season
    // columns: no record book mixes the two, and the career table renders them
    // as a sub-row under the season they belong to.
    //
    // Shape differs from the regular season on purpose. Up there the categories
    // are typed columns because the legacy `keyStat1/2/3` slots are derived from
    // them; down here nothing is derived, the line is written and read whole, and
    // seventeen more columns on a row that already has twenty-five buys nothing.
    // So the postseason line rides as one JSON blob — the same shape
    // `Player.seasonStatLineData` already uses for the live accumulator, and
    // decode-lenient for free through `SeasonStatLine.init(from:)`.
    //
    // All three are default-value stored properties → lightweight migration; a
    // row written before the playoffs were persisted reads as "no postseason".

    /// Playoff games this player appeared in, credited the same way as
    /// `gamesPlayed`: one per playoff game his team played while he was
    /// available. `0` means he watched the postseason (or there wasn't one).
    var postGamesPlayed: Int = 0

    /// JSON-encoded ``SeasonStatLine`` for the postseason. `nil` until a playoff
    /// box score (or a template `post` bag) has been folded in — read it through
    /// ``postStatLine``, never directly.
    var postStatLineData: Data? = nil

    /// True when the postseason line was modelled by `SeasonStatSynthesizer`
    /// rather than accumulated from a real box score — which is every playoff
    /// team but the user's, since AI playoff games are score-only. Provenance
    /// only, same as `statsAreSynthesized`.
    var postStatsAreSynthesized: Bool = false

    /// Playoff games a REAL box score was folded in for (#156).
    ///
    /// The distinction `postStatLine.isEmpty` cannot make: "the sim never box-
    /// scored this man" and "the sim box-scored him and he did nothing" both
    /// read as an empty line, so `finalizePostseasonHistory` treated a genuine
    /// 0-yard playoff game from a user's OPPONENT as missing data and replaced
    /// it with invented numbers. Incremented only by ``addPostseasonGame``, so
    /// `> 0` means the numbers in ``postStatLine`` — zeros included — are real.
    ///
    /// Default-valued stored property → lightweight migration; rows written
    /// before this existed read as 0 and fall back to the old `isEmpty` test.
    var postBoxScoreGames: Int = 0

    // MARK: - Legacy generic slots

    /// Position-appropriate primary stat, derived from the typed columns by
    /// `SeasonStatLine.legacyKeyStats(for:)`. Retained because the template
    /// determinism fingerprint hashes it.
    var keyStat1: Int

    /// Position-appropriate secondary stat — see `keyStat1`.
    var keyStat2: Int

    /// Position-appropriate tertiary stat — see `keyStat1`.
    var keyStat3: Int

    init(
        id: UUID = UUID(),
        playerID: UUID,
        season: Int,
        overallAtEndOfSeason: Int,
        gamesPlayed: Int = 0,
        gamesStarted: Int = 0,
        ageAtEndOfSeason: Int,
        teamID: UUID? = nil,
        position: Position? = nil,
        statLine: SeasonStatLine = SeasonStatLine(),
        statsAreSynthesized: Bool = false
    ) {
        self.id = id
        self.playerID = playerID
        self.season = season
        self.overallAtEndOfSeason = overallAtEndOfSeason
        self.gamesPlayed = gamesPlayed
        self.gamesStarted = gamesStarted
        self.ageAtEndOfSeason = ageAtEndOfSeason
        self.teamID = teamID
        self.positionRaw = position?.rawValue ?? ""
        self.statsAreSynthesized = statsAreSynthesized

        self.passYards = statLine.passYards
        self.passTDs = statLine.passTDs
        self.passInts = statLine.passInts
        self.rushYards = statLine.rushYards
        self.rushTDs = statLine.rushTDs
        self.receptions = statLine.receptions
        self.recYards = statLine.recYards
        self.recTDs = statLine.recTDs
        self.tackles = statLine.tackles
        self.sacks = statLine.sacks
        self.defInts = statLine.defInts
        self.passesDefended = statLine.passesDefended
        self.fieldGoalsMade = statLine.fieldGoalsMade
        self.fieldGoalsAttempted = statLine.fieldGoalsAttempted
        self.punts = statLine.punts
        self.puntAverage = statLine.puntAverage
        self.snapsPlayed = statLine.snapsPlayed

        let legacy = position.map { statLine.legacyKeyStats(for: $0) } ?? (0, 0, 0)
        self.keyStat1 = legacy.0
        self.keyStat2 = legacy.1
        self.keyStat3 = legacy.2
    }
}

// MARK: - Stat line bridge

extension PlayerSeasonHistory {

    /// The position this row was recorded at, or `nil` on a row written before
    /// the position snapshot existed (callers fall back to `Player.position`).
    var position: Position? {
        positionRaw.isEmpty ? nil : Position(rawValue: positionRaw)
    }

    /// The whole season line as one value. The setter also refreshes the derived
    /// `keyStat1/2/3` slots, so it is the only correct way to overwrite stats
    /// after the row exists.
    var statLine: SeasonStatLine {
        get {
            var line = SeasonStatLine()
            line.passYards = passYards
            line.passTDs = passTDs
            line.passInts = passInts
            line.rushYards = rushYards
            line.rushTDs = rushTDs
            line.receptions = receptions
            line.recYards = recYards
            line.recTDs = recTDs
            line.tackles = tackles
            line.sacks = sacks
            line.defInts = defInts
            line.passesDefended = passesDefended
            line.fieldGoalsMade = fieldGoalsMade
            line.fieldGoalsAttempted = fieldGoalsAttempted
            line.punts = punts
            line.puntAverage = puntAverage
            line.snapsPlayed = snapsPlayed
            return line
        }
        set {
            passYards = newValue.passYards
            passTDs = newValue.passTDs
            passInts = newValue.passInts
            rushYards = newValue.rushYards
            rushTDs = newValue.rushTDs
            receptions = newValue.receptions
            recYards = newValue.recYards
            recTDs = newValue.recTDs
            tackles = newValue.tackles
            sacks = newValue.sacks
            defInts = newValue.defInts
            passesDefended = newValue.passesDefended
            fieldGoalsMade = newValue.fieldGoalsMade
            fieldGoalsAttempted = newValue.fieldGoalsAttempted
            punts = newValue.punts
            puntAverage = newValue.puntAverage
            snapsPlayed = newValue.snapsPlayed

            let legacy = position.map { newValue.legacyKeyStats(for: $0) } ?? (0, 0, 0)
            keyStat1 = legacy.0
            keyStat2 = legacy.1
            keyStat3 = legacy.2
        }
    }
}

// MARK: - Postseason bridge (#20)

extension PlayerSeasonHistory {

    /// The playoff line as one value. Decoding failure and "never written" are
    /// the same answer — an empty line — which is what makes the blob safe to
    /// widen later (`SeasonStatLine.init(from:)` reads every key with
    /// `decodeIfPresent`).
    ///
    /// Unlike ``statLine`` this setter derives nothing: the legacy `keyStat1/2/3`
    /// slots are a REGULAR-season summary and folding playoffs into them would
    /// silently change what the template determinism fingerprint hashes.
    var postStatLine: SeasonStatLine {
        get {
            guard let data = postStatLineData,
                  let line = try? JSONDecoder().decode(SeasonStatLine.self, from: data) else {
                return SeasonStatLine()
            }
            return line
        }
        set {
            postStatLineData = try? JSONEncoder().encode(newValue)
        }
    }

    /// True when this season had a postseason worth rendering. Games alone are
    /// enough: a lineman's playoff run is real even though the box score the sim
    /// keeps has no category for it.
    var hasPostseason: Bool {
        postGamesPlayed > 0 || !postStatLine.isEmpty
    }

    /// Folds one playoff box-score line into the postseason totals.
    ///
    /// Does NOT touch ``postGamesPlayed``: appearances are credited from the
    /// bracket itself (every available player on a team that played this round),
    /// which covers the 31 clubs whose playoff games are score-only. A box score
    /// exists for the user's game alone, so tying the two together would leave
    /// the rest of the league at zero playoff games.
    func addPostseasonGame(_ game: PlayerGameStats) {
        var line = postStatLine
        line.add(game)
        postStatLine = line
        // #156: the provenance marker. A real line of zeros must survive
        // `finalizePostseasonHistory`, and only this counter can tell it apart
        // from a line that was never written.
        postBoxScoreGames += 1
    }
}
