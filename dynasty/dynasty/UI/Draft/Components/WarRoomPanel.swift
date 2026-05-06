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
            SectionHeaderText(title: "Your Draft Capital")
            ForEach(userRemainingPicks, id: \.id) { pick in
                HStack {
                    Text("Rd \(pick.round) · #\(pick.pickNumber)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(PickValueChart.points(forPick: pick.pickNumber)) pts")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(Color.accentGold)
                }
            }
            Divider().overlay(Color.surfaceBorder).padding(.vertical, 2)
            HStack {
                Text("Total")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(userTotalValue()) pts")
                    .font(.caption.monospaced().weight(.heavy))
                    .foregroundStyle(Color.draftStealGold)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private var scoutChatterCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Scout Chatter")
            Text(scoutChatter)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private var scoutChatter: String {
        if coordinator.isUserOnClock {
            let topNeed = coordinator.teamNeedScores.max { $0.value < $1.value }?.key.rawValue ?? "depth"
            return "You're on the clock. Need: \(topNeed). Best available is sitting on the board — take the value or trade down for capital."
        }
        if let result = coordinator.lastPickResult {
            switch result.grade {
            case .stealAPlus, .hofTrack:
                return "\(result.teamAbbrev) just stole \(result.playerName) at #\(result.pickNumber). The board is shifting."
            case .reach, .bigReach:
                return "\(result.teamAbbrev) reached on \(result.playerName) at #\(result.pickNumber). Better names still on the board."
            default:
                return "\(result.teamAbbrev) goes \(result.position.rawValue) with \(result.playerName) at #\(result.pickNumber)."
            }
        }
        let picksAway = coordinator.picksUntilUserPick
        if picksAway > 0 && picksAway <= 3 {
            return "Get ready — your pick comes up in \(picksAway). Targets you've starred should still be on the board."
        }
        return "Scout team is monitoring AI selections — flag anything unusual."
    }

    private var userRemainingPicks: [DraftPick] {
        guard let teamID = coordinator.userTeamID else { return [] }
        return coordinator.picks
            .dropFirst(coordinator.currentPickIndex)
            .filter { $0.currentTeamID == teamID }
            .map { $0 }
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
