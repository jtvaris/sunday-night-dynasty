import Foundation

/// A baked, constant league snapshot produced by `tools/league-data/make_templates.py`
/// (`docs/REALISTIC_LEAGUE_PLAN.md` phase 3).
///
/// These are **plain `Codable` value types, deliberately NOT `@Model`**: the
/// template is read-only import data, not persistence. `LeagueTemplateImporter`
/// turns one of these into the SwiftData graph (`League` / `Team` / `Player` /
/// `Coach` / `DraftPick` / `PlayerSeasonHistory`) exactly once, at career
/// creation; nothing about the template survives into the save file.
///
/// Two profiles are baked from the same raw snapshot (`docs/ANONYMIZATION_SPEC.md`
/// §6.1) and share this one schema:
/// - `publish` — fictional players/coaches/team nicknames, OVR arcs only.
///   Bundled in **every** build.
/// - `dev` — real names throughout (players, coaches, club identities, owners)
///   plus exact stat lines. Bundled in **DEBUG only** (see
///   `LeagueTemplateLoader` for the mechanism).
///
/// Every field the transform emits is decoded except `calibration.teamOffsets`
/// (a heterogeneous `[[String, Double]]` JSON array that carries no runtime
/// meaning — the offsets are already baked into each `ratingTarget`).
///
/// `nonisolated` because the module defaults to `@MainActor` isolation, which
/// would isolate this type's `Decodable` conformance along with everything else:
/// a 2.6 MB decode could then only ever run ON the main actor. Read-only import
/// data has no business holding the UI, so the whole type opts out and a caller
/// is free to decode it from a background task.
nonisolated struct LeagueTemplate: Codable {

    // MARK: - Profile

    /// Which anonymization profile a template file was baked with.
    enum Profile: String, Codable, CaseIterable, Identifiable {
        /// `league_2026_publish.json` — ships in every build.
        case publish
        /// `league_2026_dev.json` — DEBUG builds only.
        case dev

        var id: String { rawValue }

        /// Bundle resource base name (no extension).
        var resourceName: String {
            switch self {
            case .publish: return "league_2026_publish"
            case .dev:     return "league_2026_dev"
            }
        }

        /// Label for the new-career league-source picker.
        var displayName: String {
            switch self {
            case .publish: return "Fixed 2026"
            case .dev:     return "Fixed 2026 (Dev)"
            }
        }
    }

    // MARK: - Header

    var schemaVersion: Int
    /// Seed the transform tool used. Every per-entity RNG in the importer is
    /// derived from this value, so one template always imports identically.
    var globalSeed: UInt64
    var generated: String
    /// Calendar year the snapshot describes (2026 — the first playable season).
    var leagueYear: Int
    var source: Source?
    /// Division name (e.g. `"AFC East"`) → team keys.
    var divisions: [String: [String]]
    /// Round-1 order by team key. Informational: the authoritative order is the
    /// `overallPick` on every `Pick` row.
    var draftOrder2026: [String]
    var calibration: Calibration?
    var profile: Profile
    var teams: [TeamTemplate]

    struct Source: Codable {
        var raw: String?
        var rawSchemaVersion: Int?
        var snapshotDate: String?
    }

    struct Calibration: Codable {
        var decision: String?
        var referenceSimReps: Int?
        var teamSpreadTarget: Double?
    }

    // MARK: - Team

    struct TeamTemplate: Codable {
        var identity: Identity
        var record2025: Record
        /// `"AFC"` / `"NFC"`.
        var conference: String
        /// `"East"` / `"North"` / `"South"` / `"West"`.
        var division: String
        /// Human label, e.g. `"Base 4-3 D"`. Informational; the playable scheme
        /// is `staff.defScheme`.
        var baseDefense: String?
        var picks2026: [Pick]
        var staff: Staff
        var players: [PlayerTemplate]
    }

    struct Identity: Codable {
        /// Key used inside the template (`"LA"` for the Los Angeles NFC club).
        var key: String
        /// Abbreviation the app's own `LeagueTeamData` uses (`"LAR"`).
        var appAbbr: String
        var city: String
        var nickname: String
        var fullName: String
        /// Principal owner baked into the template — **dev profile only**, and
        /// the one field the raw snapshot does not carry (it is a hand-kept
        /// table in `make_templates.py`). `nil` in the publish file, where
        /// `LeagueTemplateImporter` draws a fictional owner from
        /// `LeagueGenerator`'s blocklist-checked pools instead. QA gate 1
        /// asserts the publish identity has no such key at all.
        var ownerName: String?

        /// `"male"` / `"female"` — the real principal owner's gender, kept in
        /// BOTH profiles (unlike `ownerName`). Anonymizing a person's name does
        /// not require pretending every owner is a man, and the publish league
        /// would otherwise be all-male: its owners are drawn at import time, and
        /// the draw that would decide this cannot run on the seeded stream (see
        /// `LeagueGenerator.generateOwner`). So the template states it, exactly
        /// as it states the scheme a team really runs.
        ///
        /// `nil` only for a template baked before the field existed, which reads
        /// as male — the same convention as `Owner.gender` itself.
        var ownerGender: String?
    }

    struct Record: Codable {
        var wins: Int
        var losses: Int
        var ties: Int
        var madePlayoffs: Bool?
        var playoffResult: String?
    }

    // MARK: - Picks

    struct Pick: Codable {
        var round: Int
        var overallPick: Int
        /// Team key the pick originally belonged to — differs from the owning
        /// team when the pick was traded.
        var originalTeam: String
        /// `"standard"`, `"compensatory"`, or a resolution slot.
        var pickType: String?
        /// Ownership chain, already stripped of player names by the transform
        /// (`ANONYMIZATION_SPEC.md` §5): `"from SEA via JAX"`.
        var via: String?
    }

    // MARK: - Staff

    struct Staff: Codable {
        var hc: StaffMember?
        var oc: StaffMember?
        var dc: StaffMember?
        /// `OffensiveScheme.rawValue` — QA gate 2 verified all 32 decode.
        var offScheme: String?
        /// `DefensiveScheme.rawValue`.
        var defScheme: String?
    }

    struct StaffMember: Codable {
        var name: String
        /// Season the coach took the job (jittered ±1 in the publish profile).
        var sinceYear: Int?
        /// `"offense"` / `"defense"` / `"special"`.
        var background: String?
        /// Pre-assigned portrait id (`FaceLibrary`), unique across the whole
        /// template. See `PlayerTemplate.faceID` for why it is baked.
        var faceID: String?
    }

    // MARK: - Player

    struct PlayerTemplate: Codable {
        /// 16-hex-char stable id from the transform. Drives the per-player seed.
        var id: String
        var name: String
        var firstName: String?
        var lastName: String?
        /// `Position.rawValue`.
        var pos: String
        var jersey: Int?
        var age: Int
        var yearsPro: Int
        var college: String?
        var draftYear: Int?
        var draftRound: Int?
        /// Real overall pick — dev profile only (`null` in publish).
        var draftPick: Int?
        /// Fuzzed overall pick — publish profile only (`null` in dev).
        var fuzzedPick: Int?
        var heightIn: Int?
        var weightLb: Int?
        /// The OVR this player must end up with. The importer solves the game's
        /// own attributes to hit it exactly.
        var ratingTarget: Int
        /// Mean-zero integer tilts (±8) on the game's own position-attribute
        /// names — they shape the player without moving his overall.
        var areaHints: [String: Int]?
        /// Pre-solved ceiling (the phase-2 `veteranPotential` rule, applied by
        /// the transform).
        var potential: Int
        /// Raw role from the source data. Only a hint — see `role`.
        var roleHint: String?
        var depthRankHint: Int?
        /// Per-season editorial OVR arc, oldest first.
        var careerArc: [ArcRow]?
        /// Real per-season production. **dev profile only** — always `null` in
        /// the publish file (`ANONYMIZATION_SPEC.md` §3).
        var statLines: [StatLine]?
        var notes: [String]?
        /// 1-based depth-chart rank at this position, **re-derived from the
        /// ratings** by the transform (QA carry-in #1).
        var depthRank: Int?
        /// `"starter"` / `"rotation"` / `"backup"` / `"depth"`, also re-derived.
        var role: String?
        /// Pre-assigned portrait id from the face library (`face_01234`),
        /// unique across every person in the template.
        ///
        /// Baked by the transform rather than drawn at import because the
        /// runtime picker (`FaceLibrary.assignFace`) hashes the person's
        /// `UUID`, and the importer mints a fresh one on every import — a
        /// fixed league that picked at runtime would show different portraits
        /// each time it was created. `nil` only for a template baked before
        /// phase 4, which `FaceLibrary.backfill` then fills in.
        var faceID: String?

        /// Years left on this man's deal when the career opens.
        ///
        /// Baked by the transform rather than left to the import because a
        /// template row is read in places no import has happened yet — the
        /// pre-career team picker being the one that matters, which could not
        /// tell a prospective club's expiring stars from its signed ones.
        /// `make_templates.py::template_contract_years` replays the importer's
        /// OWN contract sub-stream to produce it, so this is the same number
        /// `LeagueGenerator.realisticContractYears` hands the player at import,
        /// not a second opinion. `nil` only for a template baked before this
        /// field existed, in which case the importer's draw stands alone.
        var contractYears: Int?

        /// Overall pick of record for whichever profile this row came from.
        var effectiveDraftPick: Int? { fuzzedPick ?? draftPick }

        /// 0-based depth index, the shape `LeagueGenerator` uses everywhere.
        var depthIndex: Int { max(0, (depthRank ?? 1) - 1) }
    }

    struct ArcRow: Codable {
        var year: Int
        /// Team key, or `nil` for a season not spent on an NFL roster.
        var team: String?
        var ovr: Int
        var role: String?
        /// Games played — dev profile only.
        var gp: Int?
        /// Games started — dev profile only.
        var gs: Int?
    }

    struct StatLine: Codable {
        var year: Int
        var team: String?
        var gp: Int?
        var gs: Int?
        var snapShare: Double?
        /// Position-family stat bag; integers arrive as whole doubles.
        ///
        /// The values are `Double?`, not `Double`: the source data carries
        /// explicit `null` for categories that were not tracked in a given
        /// season (penalties before the snap-count era, passer rating for a
        /// non-passer). Decoding them as non-optional made the whole dev
        /// template fail to load.
        var stats: [String: Double?]?

        /// Playoff production for the same season, in the same key bag
        /// (`make_templates.dev_statlines`). **Dev profile only**, and only on
        /// the seasons that actually reached the postseason — 2 279 of the
        /// 7 526 stat-line rows in `league_2026_dev.json`. `nil` everywhere
        /// else, including every row of the publish file (which ships no stat
        /// lines at all).
        var post: PostLine?

        /// A single stat, `nil` when absent or explicitly null.
        func stat(_ key: String) -> Double? {
            guard let value = stats?[key] else { return nil }
            return value
        }
    }

    /// One season's POSTSEASON production: `{gp, stats}`, where `stats` is the
    /// same position-family bag `StatLine.stats` uses (a QB's playoff line has
    /// `att`/`comp`/`yds`, a rusher's has `rushAtt`/`rushYds`, and so on).
    ///
    /// Deliberately the most forgiving type in the schema — see the lenient
    /// `init(from:)` below. The postseason bag is the newest thing the transform
    /// emits, and one odd row must never take the whole 2.6 MB template down
    /// with it.
    struct PostLine: Codable {
        /// Playoff games played.
        var gp: Int?
        /// Position-family stat bag, `Double?` for the same reason as
        /// `StatLine.stats`: the source carries explicit `null` for categories a
        /// season did not track.
        var stats: [String: Double?]?

        init(gp: Int? = nil, stats: [String: Double?]? = nil) {
            self.gp = gp
            self.stats = stats
        }

        /// A single stat, `nil` when absent or explicitly null.
        func stat(_ key: String) -> Double? {
            guard let value = stats?[key] else { return nil }
            return value
        }
    }
}

// MARK: - Lenient postseason decoding

extension LeagueTemplate.PostLine {

    private enum CodingKeys: String, CodingKey {
        case gp, stats
    }

    /// Never fails on a field: a `post` that is not an object at all, a `gp`
    /// that arrived as a string, or a stat bag with a surprise shape all decode
    /// to "no postseason recorded" instead of failing the enclosing template.
    ///
    /// Same double-unwrap trick as `SeasonStatLine.init(from:)` — `try?` wraps
    /// the already-optional `decodeIfPresent`, so a missing key and a type
    /// mismatch both fall through to `nil`.
    init(from decoder: Decoder) throws {
        self.init()
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        gp = (try? container.decodeIfPresent(Int.self, forKey: .gp)) ?? nil
        stats = (try? container.decodeIfPresent([String: Double?].self, forKey: .stats)) ?? nil
    }
}

// MARK: - Postseason convenience

extension LeagueTemplate.PostLine {

    /// The playoff bag wearing `StatLine`'s clothes, so postseason production
    /// folds into a `SeasonStatLine` through the importer's ONE key→category
    /// table (`LeagueTemplateImporter.statLine(from:)`) instead of a second copy
    /// of it that could drift.
    func asRegularShapedLine(year: Int) -> LeagueTemplate.StatLine {
        LeagueTemplate.StatLine(
            year: year,
            team: nil,
            gp: gp,
            gs: nil,
            snapShare: nil,
            stats: stats,
            post: nil
        )
    }
}

// MARK: - Convenience

extension LeagueTemplate {

    /// Total players across all 32 rosters.
    var playerCount: Int { teams.reduce(0) { $0 + $1.players.count } }

    /// Every 2026 pick in the template, paired with the team key that OWNS it.
    var allPicks: [(ownerKey: String, pick: Pick)] {
        teams.flatMap { team in
            team.picks2026.map { (team.identity.key, $0) }
        }
    }
}
