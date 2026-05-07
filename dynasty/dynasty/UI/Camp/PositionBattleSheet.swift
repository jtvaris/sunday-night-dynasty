import SwiftUI
import SwiftData

// MARK: - Position Battle Sheet
//
// Modal sheet that surfaces an active position battle: 2-3 players
// competing for a starting / depth-chart spot. Shows daily history,
// cumulative wins, and a force-resolve button.

struct PositionBattleSheet: View {

    let battle: PositionBattle
    let competitors: [Player]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    header
                    barChart
                    dailyHistory
                    Spacer(minLength: DSSpacing.lg)
                }
                .padding(DSSpacing.md)
            }
            .background(Color.backgroundPrimary.ignoresSafeArea())
            .navigationTitle("Position Battle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .destructive, action: forceResolve) {
                        Text("End battle now")
                            .font(.subheadline.weight(.semibold))
                    }
                    .disabled(battle.winnerID != nil)
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text(battle.positionRaw)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentGold)
                    )
                    .foregroundStyle(Color.backgroundPrimary)
                Text(headlineText)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
            }
            if let leaderID = battle.currentLeaderID,
               let leader = competitors.first(where: { $0.id == leaderID }) {
                Text("Current leader: \(leader.fullName)")
                    .font(.caption)
                    .foregroundStyle(Color.success)
            } else if battle.winnerID == nil {
                Text("No leader yet — battle just started.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            if let winnerID = battle.winnerID,
               let winner = competitors.first(where: { $0.id == winnerID }) {
                Text("Resolved: \(winner.fullName) wins the spot.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
            }
        }
    }

    private var headlineText: String {
        let names = competitors.map { $0.lastName }
        if names.count >= 2 {
            return "Battle: " + names.joined(separator: " vs ")
        } else {
            return "Battle"
        }
    }

    // MARK: - Bar chart

    private var barChart: some View {
        let totals = winsByCompetitor()
        let maxWins = max(1, totals.values.max() ?? 1)
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Cumulative Wins")
            ForEach(competitors, id: \.id) { player in
                let wins = totals[player.id] ?? 0
                HStack(spacing: DSSpacing.sm) {
                    Text(player.fullName)
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.backgroundTertiary)
                            Capsule()
                                .fill(player.id == battle.currentLeaderID ? Color.accentGold : Color.accentBlue)
                                .frame(width: geo.size.width * CGFloat(wins) / CGFloat(maxWins))
                        }
                    }
                    .frame(height: 12)
                    Text("\(wins)")
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 24, alignment: .trailing)
                }
            }
        }
        .padding(DSSpacing.md)
        .cardBackground()
    }

    // MARK: - Daily history

    private var dailyHistory: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Daily Results")
            let entries = decodedDailyResults()
            if entries.isEmpty {
                CompactEmptyStateView(
                    icon: "calendar.badge.clock",
                    message: "No daily results recorded yet."
                )
            } else {
                ForEach(Array(entries.enumerated()), id: \.offset) { idx, entry in
                    historyRow(day: entry.day, leaderID: entry.leaderID, idx: idx)
                }
            }
        }
        .padding(DSSpacing.md)
        .cardBackground()
    }

    private func historyRow(day: Int, leaderID: UUID, idx: Int) -> some View {
        let leader = competitors.first(where: { $0.id == leaderID })
        return HStack {
            Text("Day \(day + 1)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(leader?.fullName ?? "—")
                .font(.caption)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.success)
                .font(.caption)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(idx % 2 == 0 ? Color.backgroundSecondary : Color.backgroundTertiary.opacity(0.4))
        )
    }

    // MARK: - Helpers

    private struct DailyEntry: Codable {
        let day: Int
        let leaderID: UUID
    }

    private func decodedDailyResults() -> [DailyEntry] {
        guard let raw = battle.dailyResults,
              let data = raw.data(using: .utf8),
              let entries = try? JSONDecoder().decode([DailyEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.day < $1.day }
    }

    private func winsByCompetitor() -> [UUID: Int] {
        var totals: [UUID: Int] = [:]
        for c in competitors { totals[c.id] = 0 }
        for entry in decodedDailyResults() {
            totals[entry.leaderID, default: 0] += 1
        }
        return totals
    }

    private func forceResolve() {
        // Pick the competitor with the most cumulative wins.
        let totals = winsByCompetitor()
        let winnerID = totals.max(by: { $0.value < $1.value })?.key
            ?? battle.currentLeaderID
            ?? battle.competitorIDs.first
        battle.winnerID = winnerID
        battle.resolvedAt = Date()
        try? modelContext.save()
        dismiss()
    }
}
