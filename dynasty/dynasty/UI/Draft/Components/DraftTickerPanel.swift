import SwiftUI

struct DraftTickerPanel: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Draft Ticker")

            latestPickHighlight

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DSSpacing.xs) {
                    if let current = coordinator.currentPick {
                        liveRow(current)
                    }
                    if !completedPicks.isEmpty {
                        sectionLabel("RECENT")
                        ForEach(completedPicks.reversed().prefix(8), id: \.id) { pick in
                            completedPickRow(pick)
                        }
                    }
                    if !upcomingPicks.isEmpty {
                        sectionLabel("UPCOMING")
                        ForEach(upcomingPicks, id: \.id) { pick in
                            upcomingRow(pick)
                        }
                    }
                }
                .padding(.vertical, DSSpacing.xs)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Latest Pick highlight

    @ViewBuilder
    private var latestPickHighlight: some View {
        if let r = coordinator.lastPickResult {
            VStack(alignment: .leading, spacing: 4) {
                Text("JUST PICKED")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.2)
                    .foregroundStyle(Color.draftStealGold)
                HStack {
                    Text("#\(r.pickNumber) \(r.teamAbbrev)")
                        .font(.caption.monospaced().weight(.bold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    gradeChip(r.grade)
                }
                Text(r.playerName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(r.position.rawValue)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(DSSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.card)
                    .fill(Color.backgroundTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCornerRadius.card)
                            .strokeBorder(
                                r.isGem ? Color.draftStealGold : Color.surfaceBorder,
                                lineWidth: r.isGem ? 2 : 1
                            )
                    )
            )
        }
    }

    private func gradeChip(_ grade: PickGrade) -> some View {
        let color = pickGradeColor(grade)
        return HStack(spacing: 4) {
            Text(grade.rawValue)
                .font(.caption.monospaced().weight(.heavy))
            Text(grade.qualifier)
                .font(.caption2.weight(.heavy))
                .tracking(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.30))
        .foregroundStyle(color)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(color.opacity(0.6), lineWidth: 1)
        )
    }

    private func pickGradeColor(_ grade: PickGrade) -> Color {
        switch grade {
        case .stealAPlus, .hofTrack, .smartA: return Color.draftStealGold
        case .solid:                          return Color.success
        case .reach:                          return Color.warning
        case .bigReach:                       return Color.danger
        }
    }

    // MARK: - Section label

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .tracking(1.0)
            .foregroundStyle(Color.textTertiary)
            .padding(.top, 2)
    }

    // MARK: - Data

    private var completedPicks: [DraftPick] {
        Array(coordinator.picks.prefix(coordinator.currentPickIndex)).filter { $0.isComplete }
    }

    private var upcomingPicks: [DraftPick] {
        let remaining = coordinator.picks.dropFirst(coordinator.currentPickIndex + 1)
        return Array(remaining.prefix(5))
    }

    // MARK: - Rows

    private func completedPickRow(_ pick: DraftPick) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Text("#\(pick.pickNumber)")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 32, alignment: .leading)
            Text(pick.teamAbbreviation ?? "—")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(pick.playerName ?? "—")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(pick.playerPosition ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }
            Spacer()
            gradeMiniChip(pick: pick)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary.opacity(0.5))
        )
    }

    private func gradeMiniChip(pick: DraftPick) -> some View {
        let label = pick.scoutGrade ?? "—"
        let color = scoutGradeColor(label)
        return Text(label)
            .font(.caption2.monospaced().weight(.heavy))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.30))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func scoutGradeColor(_ label: String) -> Color {
        switch label.first {
        case "A": return .draftStealGold
        case "B": return .success
        case "C": return .warning
        default:  return .danger
        }
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
                .frame(width: 32, alignment: .leading)
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
