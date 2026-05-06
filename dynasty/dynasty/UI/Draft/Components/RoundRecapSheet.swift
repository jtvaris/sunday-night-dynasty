import SwiftUI

/// Modal sheet shown between draft rounds. Surfaces:
///  - User's picks for the round (with grade chip + gem badge).
///  - Reputation deltas across the four actors + the current media narrative.
///  - The league's biggest steals of the round (top 3).
struct RoundRecapSheet: View {
    @ObservedObject var coordinator: DraftDayCoordinator
    let recap: RoundRecapData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("ROUND \(recap.round) RECAP")
                    .font(.largeTitle.weight(.heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(2)

                yourPicksSection
                reputationDeltasCard
                leagueStealsCard

                Button {
                    coordinator.dismissRoundRecap()
                } label: {
                    Text("Continue Draft")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.accentGold)
                .padding(.top, DSSpacing.sm)
            }
            .padding(DSSpacing.lg)
        }
        .background(Color.backgroundPrimary)
    }

    // MARK: - Your picks

    @ViewBuilder
    private var yourPicksSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Your Picks This Round")
            if recap.userPicks.isEmpty {
                Text("No picks this round")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .padding(DSSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()
            } else {
                VStack(spacing: DSSpacing.xs) {
                    ForEach(recap.userPicks) { row in
                        userPickRow(row)
                    }
                }
            }
        }
    }

    private func userPickRow(_ row: RoundRecapData.UserPickRow) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text("#\(row.pickNumber)")
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.playerName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    if row.isGem {
                        Text("💎")
                            .font(.caption)
                    }
                }
                Text(row.position.rawValue)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            gradeChip(row.publicGrade)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    // MARK: - Reputation deltas

    @ViewBuilder
    private var reputationDeltasCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Reputation Changes")
            VStack(spacing: DSSpacing.xs) {
                deltaRow(label: "Owner Trust", delta: recap.ownerTrustDelta)
                deltaRow(label: "Fan Mood", delta: recap.fanMoodDelta)
                deltaRow(label: "Locker Room", delta: recap.lockerRoomDelta)
                HStack {
                    Text("Media")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text(recap.mediaNarrative.headline)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                }
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity)
            .cardBackground()
        }
    }

    private func deltaRow(label: String, delta: Int) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(formattedDelta(delta))
                .font(.callout.weight(.bold))
                .foregroundStyle(deltaColor(delta))
        }
    }

    private func formattedDelta(_ delta: Int) -> String {
        if delta > 0 { return "+\(delta)" }
        if delta < 0 { return "\(delta)" }
        return "—"
    }

    private func deltaColor(_ delta: Int) -> Color {
        if delta > 0 { return Color.success }
        if delta < 0 { return Color.danger }
        return Color.textTertiary
    }

    // MARK: - League steals

    @ViewBuilder
    private var leagueStealsCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Steal Of The Round")
            if recap.topStealsOverall.isEmpty {
                Text("No notable steals this round")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .padding(DSSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardBackground()
            } else {
                VStack(spacing: DSSpacing.xs) {
                    ForEach(recap.topStealsOverall) { steal in
                        stealRow(steal)
                    }
                }
            }
        }
    }

    private func stealRow(_ steal: RoundRecapData.LeagueStealRow) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text("#\(steal.pickNumber)")
                .font(.callout.weight(.heavy))
                .foregroundStyle(Color.draftStealGold)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(steal.playerName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(steal.teamAbbrev)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Text("+\(steal.valueDelta)")
                .font(.callout.weight(.bold))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.draftStealGold.opacity(0.25))
                .foregroundStyle(Color.draftStealGold)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    // MARK: - Grade chip

    private func gradeChip(_ grade: PickGrade) -> some View {
        Text(grade.rawValue)
            .font(.caption.weight(.heavy))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(Color.textPrimary)
            .background(gradeColor(grade))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func gradeColor(_ grade: PickGrade) -> Color {
        switch grade {
        case .stealAPlus, .hofTrack: return Color.draftStealGold
        case .smartA:                return Color.success
        case .solid:                 return Color.draftSolidNeutral
        case .reach:                 return Color.warning
        case .bigReach:              return Color.draftReachRed
        }
    }
}
