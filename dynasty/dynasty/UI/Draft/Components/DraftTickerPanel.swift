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
                    // Batch 2A: the story of the night. Runs on a position,
                    // slides and reaches have always been computed (and two of
                    // them persisted as `DraftEvent`s) — no view had ever read
                    // them, which is why this column sat empty between picks.
                    if !coordinator.storyFeed.isEmpty {
                        sectionLabel("LIVE FEED")
                        ForEach(coordinator.storyFeed.prefix(10)) { beat in
                            storyRow(beat)
                        }
                    }
                    // Wave 4: the league's trade wire. Every line here is a
                    // persisted `DraftEvent` of a trade kind — rows the game
                    // wrote and never showed anyone before (plan finding S6).
                    if !coordinator.tradeTicker.isEmpty {
                        sectionLabel("TRADE WIRE")
                        ForEach(coordinator.tradeTicker.prefix(6)) { line in
                            tradeRow(line)
                        }
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
        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.tight))
        .overlay(
            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
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

    // MARK: - Story feed

    private func storyRow(_ beat: DraftDayCoordinator.StoryBeat) -> some View {
        let style = storyStyle(beat.kind)
        return HStack(alignment: .top, spacing: DSSpacing.xs) {
            Image(systemName: style.icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(style.tint)
                .frame(width: 14)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(beat.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(beat.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let pickNumber = beat.pickNumber {
                Text("#\(pickNumber)")
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(style.tint.opacity(0.08))
        )
        .overlay(
            Rectangle()
                .fill(style.tint)
                .frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
        .accessibilityElement(children: .combine)
    }

    private func storyStyle(_ kind: DraftDayCoordinator.StoryBeat.Kind) -> (icon: String, tint: Color) {
        switch kind {
        case .steal: return ("sparkles", Color.draftStealGold)
        case .reach: return ("exclamationmark.triangle.fill", Color.warning)
        case .slide: return ("arrow.down.right", Color.accentBlue)
        case .run:   return ("flame.fill", Color.danger)
        case .round: return ("flag.checkered", Color.textSecondary)
        }
    }

    private func tradeRow(_ line: DraftDayCoordinator.TradeTickerLine) -> some View {
        let tint = line.involvesUser ? Color.draftStealGold : Color.accentBlue
        return HStack(alignment: .top, spacing: DSSpacing.xs) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(line.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(line.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, DSSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                        .strokeBorder(tint.opacity(0.45), lineWidth: 1)
                )
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
        // Five rows of "#16 MIA" told the user nothing he could act on. The
        // distance to each slot is what he is actually counting.
        let isUser = pick.currentTeamID == coordinator.userTeamID
        let away = pick.pickNumber - (coordinator.currentPick?.pickNumber ?? pick.pickNumber)
        return HStack(spacing: DSSpacing.xs) {
            Text("#\(pick.pickNumber)")
                .font(.caption.monospaced())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 32, alignment: .leading)
            Text(coordinator.teamsByID[pick.currentTeamID]?.abbreviation ?? "—")
                .font(.caption.weight(isUser ? .bold : .regular))
                .foregroundStyle(isUser ? Color.draftStealGold : Color.textTertiary)
                .frame(width: 36, alignment: .leading)
            Text(isUser ? "YOU'RE UP" : (away == 1 ? "next" : "in \(away)"))
                .font(.system(size: 10, weight: isUser ? .heavy : .regular))
                .foregroundStyle(isUser ? Color.draftStealGold : Color.textTertiary)
            Spacer()
            Text("Rd \(pick.round)")
                .font(.system(size: 10).monospaced())
                .foregroundStyle(Color.textTertiary.opacity(0.7))
        }
        .padding(.vertical, 2)
        .padding(.horizontal, DSSpacing.xs)
    }
}
