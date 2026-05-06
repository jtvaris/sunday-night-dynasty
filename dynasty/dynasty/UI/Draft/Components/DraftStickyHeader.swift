import SwiftUI

struct DraftStickyHeader: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Text("ROUND \(coordinator.currentRound) — Pick \(roundRelativePick()) / 32  ·  Overall \(coordinator.currentPick?.pickNumber ?? 0)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                clockBadge
            }
            HStack {
                onTheClockText
                Spacer()
                userNextPickInfo
            }
            if !coordinator.teamNeedScores.isEmpty {
                teamNeedsStrip
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.backgroundSecondary)
        .overlay(Rectangle().fill(Color.surfaceBorder).frame(height: 1), alignment: .bottom)
    }

    private var userNextPickInfo: some View {
        let picksAway = coordinator.picksUntilUserPick
        let pulse = picksAway > 0 && picksAway <= 3
        return Text("Your next pick: #\(nextUserPickNumber()) (\(picksAway) picks away) • \(coordinator.userPicksRemaining) remaining")
            .font(.caption.weight(pulse ? .bold : .regular))
            .foregroundStyle(pulse ? Color.draftStealGold : Color.textTertiary)
    }

    private var teamNeedsStrip: some View {
        let needs = coordinator.teamNeedScores
            .sorted { $0.value > $1.value }
            .prefix(5)
        return HStack(spacing: 6) {
            Text("NEEDS")
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Color.accentGold)
                .tracking(0.8)
            ForEach(Array(needs), id: \.key) { entry in
                Text(entry.key.rawValue)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.draftStealGold.opacity(needIntensity(entry.value)))
                    )
            }
            Spacer()
        }
    }

    private func needIntensity(_ score: Double) -> Double {
        // 0.30 → 0.10, 1.0 → 0.40
        return max(0.08, min(0.42, (score - 0.2) * 0.55))
    }

    private func roundRelativePick() -> Int {
        guard let pick = coordinator.currentPick else { return 0 }
        return pick.pickNumber - (pick.round - 1) * 32
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
