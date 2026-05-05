import SwiftUI

struct DraftTickerPanel: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Draft Ticker")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSSpacing.xs) {
                    ForEach(completedPicks.reversed(), id: \.id) { pick in
                        completedPickRow(pick)
                    }
                    if let current = coordinator.currentPick {
                        liveRow(current)
                    }
                    ForEach(upcomingPicks, id: \.id) { pick in
                        upcomingRow(pick)
                    }
                }
                .padding(.vertical, DSSpacing.xs)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundSecondary)
    }

    private var completedPicks: [DraftPick] {
        Array(coordinator.picks.prefix(coordinator.currentPickIndex)).filter { $0.isComplete }
    }

    private var upcomingPicks: [DraftPick] {
        let remaining = coordinator.picks.dropFirst(coordinator.currentPickIndex + 1)
        return Array(remaining.prefix(5))
    }

    private func completedPickRow(_ pick: DraftPick) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text("#\(pick.pickNumber)")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 36, alignment: .leading)
            Text(pick.teamAbbreviation ?? "—")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 40, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(pick.playerName ?? "—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("\(pick.playerPosition ?? "") · \(pick.scoutGrade ?? "—")")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary.opacity(0.5))
        )
    }

    private func liveRow(_ pick: DraftPick) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text("⏱ #\(pick.pickNumber)")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(Color.draftStealGold)
            Text(coordinator.teamsByID[pick.currentTeamID]?.abbreviation ?? "—")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text(coordinator.isUserOnClock ? "YOUR PICK" : "ON THE CLOCK")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.draftStealGold)
            Spacer()
        }
        .padding(DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.draftStealGold.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(Color.draftStealGold, lineWidth: 1)
                )
        )
    }

    private func upcomingRow(_ pick: DraftPick) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text("#\(pick.pickNumber)")
                .font(.caption.monospaced())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 36, alignment: .leading)
            Text(coordinator.teamsByID[pick.currentTeamID]?.abbreviation ?? "—")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            if pick.currentTeamID == coordinator.userTeamID {
                Text("(yours)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.draftStealGold)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .padding(.horizontal, DSSpacing.xs)
    }
}
