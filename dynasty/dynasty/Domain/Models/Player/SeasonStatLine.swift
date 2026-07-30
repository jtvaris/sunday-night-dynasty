import Foundation

/// One player's production over one regular season, in the categories the game
/// is actually able to show on a career table.
///
/// The same value type serves all three producers, which is the point:
/// 1. **Live seasons** — accumulated week by week from the coached/simulated
///    box score into `Player.seasonStatLine`, then snapshotted at week 18.
/// 2. **Synthesis** — `SeasonStatSynthesizer` builds a plausible line from
///    (position, OVR, role/GP/GS, age) for every season that never ran through
///    the sim: template career arcs, the random league's backstory, and the
///    31 AI teams whose games are score-only.
/// 3. **Dev template** — folded straight out of `LeagueTemplate.StatLine`, where
///    the real per-season numbers are shipped verbatim.
///
/// Only the categories with a home in the UI live here. Punting and offensive
/// snaps have no box-score source in the sim (`PlayerGameStats` tracks neither),
/// so those two are always synthesized — see `SeasonStatSynthesizer`.
///
/// `Codable` and **decode-lenient**: `init(from:)` reads every key with
/// `decodeIfPresent`, so a line encoded by an older build (or a future one with
/// extra keys) keeps decoding after a category is added or dropped.
struct SeasonStatLine: Codable, Equatable {

    // MARK: - Passing

    var passYards: Int = 0
    var passTDs: Int = 0
    /// Interceptions THROWN. Defensive picks live in `defInts`.
    var passInts: Int = 0

    // MARK: - Rushing

    var rushYards: Int = 0
    var rushTDs: Int = 0

    // MARK: - Receiving

    var receptions: Int = 0
    var recYards: Int = 0
    var recTDs: Int = 0

    // MARK: - Defense

    var tackles: Int = 0
    /// Half-sacks are real football, so this stays fractional.
    var sacks: Double = 0
    /// Interceptions CAUGHT.
    var defInts: Int = 0
    /// Passes defended / broken up in coverage.
    var passesDefended: Int = 0

    // MARK: - Kicking & punting

    var fieldGoalsMade: Int = 0
    var fieldGoalsAttempted: Int = 0
    var punts: Int = 0
    /// Gross punt average in yards.
    var puntAverage: Double = 0

    // MARK: - Line play

    /// Offensive snaps played — the only volume stat an interior lineman has.
    var snapsPlayed: Int = 0

    init() {}
}

// MARK: - Lenient decoding

extension SeasonStatLine {

    private enum CodingKeys: String, CodingKey {
        case passYards, passTDs, passInts
        case rushYards, rushTDs
        case receptions, recYards, recTDs
        case tackles, sacks, defInts, passesDefended
        case fieldGoalsMade, fieldGoalsAttempted, punts, puntAverage
        case snapsPlayed
    }

    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Double-unwrap: `try?` wraps the already-optional `decodeIfPresent`,
        // so a missing key and a type mismatch both fall through to zero.
        func int(_ key: CodingKeys) -> Int {
            ((try? container.decodeIfPresent(Int.self, forKey: key)) ?? nil) ?? 0
        }
        func double(_ key: CodingKeys) -> Double {
            ((try? container.decodeIfPresent(Double.self, forKey: key)) ?? nil) ?? 0
        }
        passYards = int(.passYards)
        passTDs = int(.passTDs)
        passInts = int(.passInts)
        rushYards = int(.rushYards)
        rushTDs = int(.rushTDs)
        receptions = int(.receptions)
        recYards = int(.recYards)
        recTDs = int(.recTDs)
        tackles = int(.tackles)
        sacks = double(.sacks)
        defInts = int(.defInts)
        passesDefended = int(.passesDefended)
        fieldGoalsMade = int(.fieldGoalsMade)
        fieldGoalsAttempted = int(.fieldGoalsAttempted)
        punts = int(.punts)
        puntAverage = double(.puntAverage)
        snapsPlayed = int(.snapsPlayed)
    }
}

// MARK: - Accumulation

extension SeasonStatLine {

    /// True when nothing at all was recorded — the signal the recorder uses to
    /// decide "this player's season needs synthesizing instead".
    var isEmpty: Bool { self == SeasonStatLine() }

    /// Folds one game's box-score line into the season totals.
    ///
    /// `PlayerGameStats` has no punting and no snap counts, so `punts`,
    /// `puntAverage` and `snapsPlayed` are deliberately left untouched here.
    mutating func add(_ game: PlayerGameStats) {
        passYards += game.passingYards
        passTDs += game.passingTDs
        passInts += game.interceptions
        rushYards += game.rushingYards
        rushTDs += game.rushingTDs
        receptions += game.receptions
        recYards += game.receivingYards
        recTDs += game.receivingTDs
        tackles += game.tackles
        sacks += game.sacks
        defInts += game.interceptionsCaught
        passesDefended += game.passDeflectionCount
        fieldGoalsMade += game.fieldGoalsMade
        fieldGoalsAttempted += game.fieldGoalsAttempted
    }
}

// MARK: - Legacy key-stat slots

extension SeasonStatLine {

    /// The three generic `PlayerSeasonHistory.keyStat1/2/3` slots for
    /// `position`, kept in step with the typed columns.
    ///
    /// The slots predate the typed columns and are still what the determinism
    /// fingerprint hashes (`LeagueTemplateValidation.historyFingerprints`), so
    /// they are derived rather than dropped. The triple tracks the categories the
    /// career table renders for the position, minus anything that lives on the
    /// history row rather than in the line (a lineman's games started), so the
    /// legacy slots can never drift out of step with the typed columns.
    func legacyKeyStats(for position: Position) -> (Int, Int, Int) {
        switch position {
        case .QB:                    return (passYards, passTDs, passInts)
        case .RB, .FB:               return (rushYards, rushTDs, receptions)
        case .WR, .TE:               return (receptions, recYards, recTDs)
        case .LT, .LG, .C, .RG, .RT: return (snapsPlayed, 0, 0)
        case .DE, .DT:               return (tackles, Int(sacks.rounded()), 0)
        case .OLB, .MLB:             return (tackles, Int(sacks.rounded()), defInts)
        case .CB, .FS, .SS:          return (tackles, defInts, passesDefended)
        case .K:                     return (fieldGoalsMade, fieldGoalsAttempted, 0)
        case .P:                     return (punts, Int(puntAverage.rounded()), 0)
        }
    }
}
