import Foundation
import SwiftData

// MARK: - Coach Season History

/// One completed season for ONE coach — the club he was at, the seat he held,
/// and the record that club finished with while he held it.
///
/// ## Why this table exists
///
/// A `Coach` row carries only his CURRENT job: `teamID`, `role`, `hireSeasonYear`,
/// `yearsExperience`. That is enough to say "OC, 11 years in the game" and
/// nothing else — the moment a man is fired, poached or promoted, every trace of
/// where he had been is overwritten. So the candidate card in `HireCoachView`
/// has always had to *derive* a plausible past out of age and years and a hash
/// of the coach's id, and it says so: that card is titled EXPERIENCE, not career
/// history, precisely because there was no career history to show.
///
/// This is the missing book. One row per (coach, season) for **every** employed
/// coach in the league, written at the season rollover, kept forever.
///
/// ## Everything here is a snapshot of something already derived
///
/// The record is not recomputed here and is not read off `Team`. It is copied
/// from that season's `TeamSeasonArchive` row, which is itself derived from the
/// game log through `StandingsCalculator`. That is deliberate: a coach's line
/// and his club's line come out of one number, so the coach card and the League
/// History screen can never disagree about what 2029 in Cleveland was.
///
/// `teamAbbr` / `teamName` / `coachName` are stored rather than joined, for the
/// same reason `TeamSeasonArchive` and `HallOfFameEntry` store theirs: the row
/// has to render after a relocation, after the man retires, and after the seat
/// has changed hands twice.
///
/// ## What it deliberately does NOT claim
///
/// `wins` / `losses` / `ties` are the CLUB's record that season, for the seat
/// this man occupied. They are not "his" wins in any sense the sim can defend —
/// a receivers coach did not go 12-5, his employer did. Every caption that
/// renders these numbers has to say so, and `CoachCareerHistoryCard` does.
@Model
final class CoachSeasonHistory {

    var id: UUID

    /// The save slot (``Career.id``) this row belongs to. `nil` marks a legacy
    /// row written before multi-save isolation existed; `CareerScope.adopt`
    /// stamps those on first launch. Default-value stored property, never in
    /// `init` -> safe lightweight migration.
    var careerID: UUID? = nil

    #Index<CoachSeasonHistory>([\.careerID])

    /// The man. `Coach.id` — the row it points at is kept forever, retired or
    /// not, so this never dangles for a coach the league still remembers.
    var coachID: UUID

    /// Calendar season year (e.g. 2026), matching `TeamSeasonArchive.season`.
    var season: Int

    // MARK: - Identity snapshot

    /// Name as it read that season.
    var coachName: String

    /// The club he was at. Matches `TeamSeasonArchive.teamID` for the same season.
    var teamID: UUID
    var teamAbbr: String
    /// City + nickname as it read that season.
    var teamName: String

    // MARK: - The seat

    /// Raw `CoachRole` — the chair he sat in that season, not the one he holds
    /// now. This is the whole point of the table: a man who is a head coach
    /// today has rows that say OC, and rows before those that say QB coach.
    var roleRaw: String

    // MARK: - The club's record, that season

    var wins: Int
    var losses: Int
    var ties: Int

    /// Raw `PlayoffResult`, copied from the same season's `TeamSeasonArchive`.
    var playoffResultRaw: String

    // MARK: - Computed

    /// `nil` for a raw value no build understands — a role removed from the
    /// enum, which the migration policy forbids, or a corrupted row. The UI
    /// falls back to the stored string rather than inventing a seat.
    var role: CoachRole? { CoachRole(rawValue: roleRaw) }

    var playoffResult: PlayoffResult { PlayoffResult(rawValue: playoffResultRaw) ?? .missed }

    /// `W-L`, or `W-L-T` when the season actually had a tie in it. Same rule as
    /// `TeamSeasonArchive.recordText` and `StandingsRecord`.
    var recordText: String {
        ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
    }

    var gamesPlayed: Int { wins + losses + ties }

    /// Ties count as half a win, same as `StandingsRecord` and
    /// `TeamSeasonArchive.winPercentage`.
    var winPercentage: Double {
        guard gamesPlayed > 0 else { return 0 }
        return (Double(wins) + Double(ties) * 0.5) / Double(gamesPlayed)
    }

    var wonTitle: Bool { playoffResult == .champion }

    var madePlayoffs: Bool { playoffResult.madePlayoffs }

    // MARK: - Init

    init(
        id: UUID = UUID(),
        coachID: UUID,
        season: Int,
        coachName: String,
        teamID: UUID,
        teamAbbr: String,
        teamName: String,
        role: CoachRole,
        wins: Int,
        losses: Int,
        ties: Int,
        playoffResult: PlayoffResult
    ) {
        self.id = id
        self.coachID = coachID
        self.season = season
        self.coachName = coachName
        self.teamID = teamID
        self.teamAbbr = teamAbbr
        self.teamName = teamName
        self.roleRaw = role.rawValue
        self.wins = wins
        self.losses = losses
        self.ties = ties
        self.playoffResultRaw = playoffResult.rawValue
    }
}

// MARK: - Career Record

/// The totals a pile of ``CoachSeasonHistory`` rows adds up to.
///
/// A plain value type with no opinions in it: every field is a count or a sum
/// over the rows it was built from, so anything printed on screen can be traced
/// straight back to a season row and from there to a `TeamSeasonArchive` row.
/// Nothing here is estimated, projected or smoothed.
struct CoachCareerRecord {

    /// How many completed seasons are on the books.
    var seasons: Int
    /// Distinct clubs across those seasons.
    var clubs: Int
    /// Earliest and latest season with a row.
    var firstSeason: Int
    var lastSeason: Int

    var wins: Int
    var losses: Int
    var ties: Int

    /// Seasons whose club won the championship while he was on the staff.
    var titles: Int
    /// Seasons whose club reached the bracket at all.
    var playoffSeasons: Int

    var games: Int { wins + losses + ties }

    var recordText: String {
        ties > 0 ? "\(wins)-\(losses)-\(ties)" : "\(wins)-\(losses)"
    }

    /// Ties as half a win — the same denominator every record in the app uses.
    var winPercentage: Double {
        guard games > 0 else { return 0 }
        return (Double(wins) + Double(ties) * 0.5) / Double(games)
    }

    /// `.612`, the way a win rate is written on a football page.
    var winPercentageText: String {
        String(format: "%.3f", winPercentage)
    }

    /// Sums a set of season rows. `nil` when there is nothing on the books —
    /// the caller must show "no completed seasons" rather than a row of zeroes,
    /// because 0-0 and "we never recorded it" are different statements.
    static func total(_ rows: [CoachSeasonHistory]) -> CoachCareerRecord? {
        guard !rows.isEmpty else { return nil }
        var record = CoachCareerRecord(
            seasons: rows.count,
            clubs: Set(rows.map(\.teamID)).count,
            firstSeason: rows.map(\.season).min() ?? 0,
            lastSeason: rows.map(\.season).max() ?? 0,
            wins: 0, losses: 0, ties: 0,
            titles: 0, playoffSeasons: 0
        )
        for row in rows {
            record.wins += row.wins
            record.losses += row.losses
            record.ties += row.ties
            if row.wonTitle { record.titles += 1 }
            if row.madePlayoffs { record.playoffSeasons += 1 }
        }
        return record
    }
}

// MARK: - Coach Season History Builder

/// Writes and reads ``CoachSeasonHistory``.
///
/// ## Where the write happens, and why only there
///
/// ``record(career:modelContext:season:)`` runs at the season rollover, in
/// `WeekAdvancer`'s `.superBowl` phase, immediately after
/// `TeamSeasonArchiveBuilder.record` — it reads the rows that call just wrote.
/// That is the one moment when both halves of the row are simultaneously true:
/// the club's finished record exists, and every coach still holds the job he
/// held all season. One phase later the carousel fires men, poaches
/// coordinators and promotes assistants, and the seat is no longer evidence of
/// anything.
///
/// ## There is no backfill, and there cannot be one
///
/// `TeamSeasonArchiveBuilder` can catch up on a season it missed, because
/// records and ratings survive in the game log and the player snapshots. This
/// table cannot: a coach row remembers only his current employer, so a catch-up
/// pass would credit 2029 in Cleveland to whoever is sitting there in 2032. A
/// save that predates this table therefore starts its coaching book at its next
/// rollover, and the card says as much instead of reconstructing a past.
enum CoachSeasonHistoryBuilder {

    // MARK: - Pure derivation

    /// Builds one row per employed coach from the season's archive rows.
    /// PURE: touches no context, inserts nothing, reads nothing global.
    ///
    /// - Parameters:
    ///   - season: The season year being recorded.
    ///   - archives: That season's `TeamSeasonArchive` rows — the source of
    ///     every record on every row this returns.
    ///   - coaches: The coach table as it stood when the season ended.
    /// - Returns: unattached rows (the caller inserts and stamps them). A coach
    ///   with no club, or at a club with no archive row, produces nothing:
    ///   there is no record to attribute to him.
    static func build(
        season: Int,
        archives: [TeamSeasonArchive],
        coaches: [Coach]
    ) -> [CoachSeasonHistory] {
        guard !archives.isEmpty else { return [] }
        let archiveByTeam = Dictionary(
            archives.filter { $0.season == season }.map { ($0.teamID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !archiveByTeam.isEmpty else { return [] }

        return coaches.compactMap { coach in
            guard let teamID = coach.teamID, let archive = archiveByTeam[teamID] else { return nil }
            return CoachSeasonHistory(
                coachID: coach.id,
                season: season,
                coachName: coach.fullName,
                teamID: teamID,
                teamAbbr: archive.teamAbbr,
                teamName: archive.teamName,
                role: coach.role,
                wins: archive.wins,
                losses: archive.losses,
                ties: archive.ties,
                playoffResult: archive.playoffResult
            )
        }
    }

    // MARK: - Persistence

    /// Records `season` (defaults to the career's current one) exactly once.
    /// Idempotent per (career, season): a second call is a count and a return,
    /// so a re-entered rollover phase cannot double a coach's career.
    ///
    /// - Returns: how many rows were written — 0 when the season is already on
    ///   the books, or when it has no `TeamSeasonArchive` rows yet (which is
    ///   also what happens when the season's game log is incomplete, because
    ///   that is the condition under which the archive declines to write).
    @discardableResult
    static func record(
        career: Career,
        modelContext: ModelContext,
        season: Int? = nil
    ) -> Int {
        let year = season ?? career.currentSeason
        let cid = career.id

        // Save before reading. The call immediately before this one at the
        // rollover is `TeamSeasonArchiveBuilder.record`, whose 32 rows are
        // still pending inserts, and a pending insert is not visible to the
        // next `fetch` — `LeagueHistoryView.loadArchives` saves explicitly for
        // exactly this reason, having found the alternative renders an empty
        // archive on the screen that just built it. Without this, the coaching
        // book would be silently empty for the whole of season one and would
        // only ever record from the SECOND rollover onwards.
        try? modelContext.save()

        guard !isRecorded(careerID: cid, season: year, modelContext: modelContext) else { return 0 }

        let archives = fetchArchives(careerID: cid, season: year, modelContext: modelContext)
        let coaches = fetchCoaches(careerID: cid, modelContext: modelContext)
        let rows = build(season: year, archives: archives, coaches: coaches)
        guard !rows.isEmpty else { return 0 }

        for row in rows {
            CareerScope.stamp(row, careerID: cid)
            modelContext.insert(row)
        }
        return rows.count
    }

    // MARK: - Reads

    /// One man's book, newest season first.
    static func history(
        careerID: UUID,
        coachID: UUID,
        modelContext: ModelContext
    ) -> [CoachSeasonHistory] {
        let descriptor = FetchDescriptor<CoachSeasonHistory>(
            predicate: #Predicate<CoachSeasonHistory> {
                $0.careerID == careerID && $0.coachID == coachID
            },
            sortBy: [SortDescriptor(\.season, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Private: fetches

    private static func isRecorded(careerID: UUID, season: Int, modelContext: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<CoachSeasonHistory>(
            predicate: #Predicate<CoachSeasonHistory> {
                $0.careerID == careerID && $0.season == season
            }
        )
        return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
    }

    private static func fetchArchives(
        careerID: UUID,
        season: Int,
        modelContext: ModelContext
    ) -> [TeamSeasonArchive] {
        let descriptor = FetchDescriptor<TeamSeasonArchive>(
            predicate: #Predicate<TeamSeasonArchive> {
                $0.careerID == careerID && $0.season == season
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchCoaches(careerID: UUID, modelContext: ModelContext) -> [Coach] {
        let descriptor = FetchDescriptor<Coach>(
            predicate: #Predicate<Coach> { $0.careerID == careerID }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}
