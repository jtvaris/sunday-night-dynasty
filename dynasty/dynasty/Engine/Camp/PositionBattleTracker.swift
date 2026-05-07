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
    static func detectBattles(roster: [Player], modelContext: ModelContext) -> [PositionBattle] {
        let grouped = Dictionary(grouping: roster) { $0.position }
        var battles: [PositionBattle] = []
        let seasonYear = Calendar.current.component(.year, from: .now)

        for (position, players) in grouped {
            let sorted = players.sorted { $0.overall > $1.overall }
            guard sorted.count >= 2 else { continue }

            let leaderOVR = sorted[0].overall
            // Take the top player + everyone within 5 OVR (max 3 total).
            let competitors = sorted.prefix(3).filter { abs($0.overall - leaderOVR) <= 5 }
            guard competitors.count >= 2 else { continue }

            let battle = PositionBattle(
                seasonYear: seasonYear,
                positionRaw: position.rawValue,
                competitorIDs: competitors.map(\.id),
                currentLeaderID: competitors.first?.id
            )
            modelContext.insert(battle)
            battles.append(battle)
        }
        return battles
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
