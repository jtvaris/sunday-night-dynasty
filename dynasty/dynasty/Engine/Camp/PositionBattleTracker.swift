import Foundation
import SwiftData

// MARK: - PositionBattleTracker

/// Detects and resolves per-position camp competitions. A "battle" exists wherever
/// 2-3 players are within striking distance for a starting / depth-chart spot.
/// Daily ticks roll for a winner, persisted as a JSON entry inside `dailyResults`.
@MainActor
enum PositionBattleTracker {

    // MARK: - Public API

    /// Auto-detects position battles based on depth chart proximity.
    /// Two or three players within ~5 OVR of each other at the same position
    /// qualify as a battle — they're competing for the same role.
    ///
    /// ## Season stamp (task #67)
    ///
    /// `seasonYear` is the CAREER's season and must be passed in. This used to
    /// read `Calendar.current.component(.year, from: .now)` — the real-world
    /// year — while every consumer (`WeekAdvancer.fetchOpenPositionBattles`,
    /// the end-of-camp resolve, the dashboard tile) queries on
    /// `career.currentSeason`. The two agree only in a save's first season and
    /// only while the device clock happens to sit on the same year; from season
    /// 2 on, the "is a battle already open?" query came back empty every camp
    /// week, so detection re-inserted the whole set of battles seven times a
    /// camp and none of them was ever resolvable.
    ///
    /// ## Idempotence
    ///
    /// The comment that used to sit on the call site claimed detection was
    /// idempotent; nothing enforced it. It now is: a battle is skipped when a
    /// row for the same `(careerID, seasonYear, position)` already exists —
    /// resolved or not — so calling this every camp week is a no-op after the
    /// first, and a battle that has already been decided is not silently
    /// re-opened.
    ///
    /// The identity is deliberately the POSITION and not the competitor set. A
    /// set-scoped key looks more precise and is the wrong answer here: camp
    /// roster churn (a cut, a signing, an injury) changes who the top three at a
    /// position are, so week 2's competitor set differs from week 1's and a
    /// set-scoped key would mint a SECOND open QB battle rather than recognise
    /// the same competition. One position, one camp, one battle — which is also
    /// what the dashboard tile and the end-of-camp resolve assume. The incumbent
    /// row keeps the competitor set it was opened with; that is the roster the
    /// competition actually started between.
    static func detectBattles(
        roster: [Player],
        seasonYear: Int,
        careerID: UUID?,
        modelContext: ModelContext
    ) -> [PositionBattle] {
        let grouped = Dictionary(grouping: roster) { $0.position }
        var battles: [PositionBattle] = []

        let existing = fetchSeasonBattles(
            careerID: careerID,
            seasonYear: seasonYear,
            modelContext: modelContext
        )
        var existingKeys = Set(existing.map { battleKey(for: $0) })

        for (position, players) in grouped {
            let sorted = players.sorted { $0.overall > $1.overall }
            guard sorted.count >= 2 else { continue }

            let leaderOVR = sorted[0].overall
            // Take the top player + everyone within 5 OVR (max 3 total).
            let competitors = sorted.prefix(3).filter { abs($0.overall - leaderOVR) <= 5 }
            guard competitors.count >= 2 else { continue }

            let competitorIDs = competitors.map(\.id)
            let key = battleKey(positionRaw: position.rawValue)
            guard !existingKeys.contains(key) else { continue }
            existingKeys.insert(key)

            let battle = PositionBattle(
                seasonYear: seasonYear,
                positionRaw: position.rawValue,
                competitorIDs: competitorIDs,
                currentLeaderID: competitorIDs.first
            )
            battle.careerID = careerID ?? competitors.first?.careerID
            modelContext.insert(battle)
            battles.append(battle)
        }
        return battles
    }

    /// Every battle row for one save-season, resolved or not — the set that
    /// makes detection idempotent.
    static func fetchSeasonBattles(
        careerID: UUID?,
        seasonYear: Int,
        modelContext: ModelContext
    ) -> [PositionBattle] {
        let descriptor = FetchDescriptor<PositionBattle>(
            predicate: #Predicate<PositionBattle> {
                $0.careerID == careerID && $0.seasonYear == seasonYear
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Identity

    /// Stable identity of a competition inside one save-season: the POSITION.
    ///
    /// Not the competitor set — see `detectBattles`. A set-scoped key cannot
    /// recognise the same competition across a roster change, and camp is
    /// precisely when rosters change, so it would leave exactly the duplicates
    /// this identity exists to prevent.
    private static func battleKey(positionRaw: String) -> String {
        positionRaw
    }

    private static func battleKey(for battle: PositionBattle) -> String {
        battleKey(positionRaw: battle.positionRaw)
    }

    // MARK: - Legacy Cleanup (task #67)

    /// Repairs the rows the calendar-year stamp left behind. Safe to call on
    /// every career load: it is a no-op once a save is clean.
    ///
    /// Two kinds of damage, both from the same root cause:
    ///
    /// 1. **Duplicates.** Detection re-ran every camp week, so the same
    ///    competition exists many times over for one season — and, once camp
    ///    roster churn moved the top three at a position, under DIFFERENT
    ///    competitor sets. The keeper is chosen per `(season, position)` for
    ///    that reason: the most-progressed row survives (resolved beats open;
    ///    more daily results beats fewer) and the rest are deleted, so a decided
    ///    battle is never traded for a blank copy of itself.
    /// 2. **Stale-year orphans.** Rows stamped with a season the save is no
    ///    longer in and never resolved. Nothing can resolve them any more —
    ///    the end-of-camp pass only looks at `career.currentSeason` — so they
    ///    would sit in the store forever. Resolved rows from past seasons are
    ///    kept: those are history.
    ///
    /// - Returns: how many rows were deleted, for the caller's log.
    @discardableResult
    static func cleanupLegacyBattles(career: Career, modelContext: ModelContext) -> Int {
        let cid = career.id
        let descriptor = FetchDescriptor<PositionBattle>(
            predicate: #Predicate<PositionBattle> { $0.careerID == cid }
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        guard !rows.isEmpty else { return 0 }

        var deleted = 0

        // 1. Dedupe within each (season, position, competitor set).
        var keeperByKey: [String: PositionBattle] = [:]
        for row in rows {
            let key = "\(row.seasonYear)|" + battleKey(for: row)
            guard let incumbent = keeperByKey[key] else {
                keeperByKey[key] = row
                continue
            }
            if moreProgressed(incumbent, row) {
                modelContext.delete(row)
            } else {
                keeperByKey[key] = row
                modelContext.delete(incumbent)
            }
            deleted += 1
        }

        // 2. Drop unresolved rows the engine can no longer reach.
        for row in keeperByKey.values
        where row.winnerID == nil && row.seasonYear != career.currentSeason {
            modelContext.delete(row)
            deleted += 1
        }

        if deleted > 0 {
            try? modelContext.save()
            print("[PositionBattle] cleanup removed \(deleted) duplicate/stale row(s)")
        }
        return deleted
    }

    /// True when `lhs` is the row worth keeping out of a duplicate pair.
    private static func moreProgressed(_ lhs: PositionBattle, _ rhs: PositionBattle) -> Bool {
        if (lhs.winnerID != nil) != (rhs.winnerID != nil) { return lhs.winnerID != nil }
        let lhsDays = decodeDailyResults(from: lhs.dailyResults).count
        let rhsDays = decodeDailyResults(from: rhs.dailyResults).count
        if lhsDays != rhsDays { return lhsDays > rhsDays }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    /// Daily resolve: bumps daily winner, persists to `battle.dailyResults` JSON.
    static func tickDay(
        battle: PositionBattle,
        rng: inout SystemRandomNumberGenerator,
        modelContext: ModelContext
    ) {
        guard battle.winnerID == nil, !battle.competitorIDs.isEmpty else { return }

        // Fetch competitor players to weight roll by current OVR.
        let competitorIDs = battle.competitorIDs
        let descriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { competitorIDs.contains($0.id) }
        )
        let players = (try? modelContext.fetch(descriptor)) ?? []
        guard !players.isEmpty else { return }

        // Weighted roll: each competitor's chance is proportional to OVR + camp roll.
        let weights = players.map { Double($0.overall) + Double.random(in: 0...8, using: &rng) }
        let total = weights.reduce(0, +)
        guard total > 0 else { return }

        var roll = Double.random(in: 0..<total, using: &rng)
        var winnerID: UUID = players[0].id
        for (i, w) in weights.enumerated() {
            if roll < w { winnerID = players[i].id; break }
            roll -= w
        }

        battle.currentLeaderID = winnerID

        // Append to dailyResults JSON: [{day,leaderID}, …]
        let existing = decodeDailyResults(from: battle.dailyResults)
        let nextDay = (existing.last?.day ?? -1) + 1
        let updated = existing + [DailyResultEntry(day: nextDay, leaderID: winnerID.uuidString)]
        battle.dailyResults = encodeDailyResults(updated)
    }

    /// End-of-camp resolution: picks winner from cumulative daily results.
    /// The competitor with the most daily wins gets the starting nod.
    static func resolveBattles(battles: [PositionBattle], modelContext: ModelContext) {
        for battle in battles where battle.winnerID == nil {
            let entries = decodeDailyResults(from: battle.dailyResults)
            guard !entries.isEmpty else {
                battle.winnerID = battle.currentLeaderID
                battle.resolvedAt = .now
                continue
            }
            // Tally daily wins
            let counts = Dictionary(grouping: entries, by: \.leaderID).mapValues(\.count)
            let topID = counts.max { $0.value < $1.value }?.key
            battle.winnerID = topID.flatMap(UUID.init(uuidString:)) ?? battle.currentLeaderID
            battle.resolvedAt = .now
        }
    }

    // MARK: - JSON Helpers

    private struct DailyResultEntry: Codable {
        let day: Int
        let leaderID: String
    }

    private static func decodeDailyResults(from json: String?) -> [DailyResultEntry] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([DailyResultEntry].self, from: data)) ?? []
    }

    private static func encodeDailyResults(_ entries: [DailyResultEntry]) -> String? {
        guard let data = try? JSONEncoder().encode(entries) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
