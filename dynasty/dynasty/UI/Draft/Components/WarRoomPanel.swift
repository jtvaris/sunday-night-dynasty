import SwiftUI

struct WarRoomPanel: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                pickValueCard
                scoutChatterCard
                tradeRadarCard
            }
            .padding(DSSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundSecondary)
    }

    private var pickValueCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Pick Value")
            if let pick = coordinator.currentPick {
                Text("Current: #\(pick.pickNumber) = \(PickValueChart.points(forPick: pick.pickNumber)) pts")
                    .font(.caption)
                    .foregroundStyle(Color.textPrimary)
            }
            if let nextUser = nextUserPick() {
                Text("Your next: #\(nextUser.pickNumber) = \(PickValueChart.points(forPick: nextUser.pickNumber)) pts")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            let totalUserValue = userTotalValue()
            Text("Your total capital: \(totalUserValue) pts")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private var scoutChatterCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Scout Chatter")
            Text(coordinator.isUserOnClock
                 ? "Your scouts are watching the board. Top BPA is your move — or trade out for capital."
                 : "Scout team is monitoring AI selections.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private var tradeRadarCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Trade Radar")
            Text("(Trade engine arrives in Vaihe 3)")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private func nextUserPick() -> DraftPick? {
        guard let teamID = coordinator.userTeamID else { return nil }
        return coordinator.picks
            .dropFirst(coordinator.currentPickIndex)
            .first { $0.currentTeamID == teamID }
    }

    private func userTotalValue() -> Int {
        guard let teamID = coordinator.userTeamID else { return 0 }
        return coordinator.picks
            .dropFirst(coordinator.currentPickIndex)
            .filter { $0.currentTeamID == teamID }
            .reduce(0) { $0 + PickValueChart.points(forPick: $1.pickNumber) }
    }
}
