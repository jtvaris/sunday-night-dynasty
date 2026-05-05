import SwiftUI

struct DraftStickyHeader: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text("ROUND \(coordinator.currentRound) — Pick \(coordinator.currentPick?.pickNumber ?? 0) of \(coordinator.picks.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                clockBadge
            }
            HStack {
                onTheClockText
                Spacer()
                Text("Your next pick: #\(nextUserPickNumber()) (\(coordinator.picksUntilUserPick) picks away) • \(coordinator.userPicksRemaining) remaining")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .overlay(Rectangle().fill(Color.surfaceBorder).frame(height: 1), alignment: .bottom)
    }

    private var onTheClockText: some View {
        Group {
            if let pick = coordinator.currentPick,
               let team = coordinator.teamsByID[pick.currentTeamID] {
                if coordinator.isUserOnClock {
                    Text("YOU ARE ON THE CLOCK")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Color.draftStealGold)
                } else {
                    Text("ON THE CLOCK: \(team.fullName)")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                }
            } else {
                Text("DRAFT")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
            }
        }
    }

    private var clockBadge: some View {
        let urgent = coordinator.clockSeconds <= 30
        return Text("⏱ \(coordinator.clockSeconds)s")
            .font(.system(.title3, design: .monospaced).weight(.bold))
            .foregroundStyle(urgent ? Color.draftClockUrgent : Color.textPrimary)
    }

    private func nextUserPickNumber() -> Int {
        guard let teamID = coordinator.userTeamID else { return 0 }
        return coordinator.picks
            .dropFirst(coordinator.currentPickIndex)
            .first(where: { $0.currentTeamID == teamID })?.pickNumber ?? 0
    }
}
