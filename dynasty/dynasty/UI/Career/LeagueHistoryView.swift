import SwiftUI
import SwiftData

/// R32 — League History & Hall of Fame.
///
/// Two sections driven entirely by Career-persisted data:
/// - **Season History**: one row per completed season (champion, the user's
///   record, playoff/title badges, MVP). Written by `WeekAdvancer` during the
///   `.superBowl` phase, capped at the last 20 seasons.
/// - **Hall of Fame**: retired legends inducted by `PlayerRetirementEngine`
///   each offseason, newest class first.
struct LeagueHistoryView: View {

    let career: Career

    private var summaries: [SeasonSummary] { career.seasonSummaries }
    private var inductees: [HallOfFameEntry] { career.hallOfFame }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                careerTotalsCard
                draftReportLink

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    SectionHeaderText(title: "Season History")
                    if summaries.isEmpty {
                        emptyCard(
                            icon: "calendar",
                            text: "No completed seasons yet. Finish a season and the champion, your record, and the MVP are recorded here."
                        )
                    } else {
                        VStack(spacing: DSSpacing.xs) {
                            ForEach(summaries) { summary in
                                seasonRow(summary)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    SectionHeaderText(title: "Hall of Fame")
                    if inductees.isEmpty {
                        emptyCard(
                            icon: "building.columns.fill",
                            text: "No inductees yet. Retiring legends — elite careers or sustained greatness — earn a bust in Canton."
                        )
                    } else {
                        VStack(spacing: DSSpacing.xs) {
                            ForEach(inductees) { entry in
                                hofRow(entry)
                            }
                        }
                    }
                }
            }
            .padding(DSSpacing.md)
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("League History")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Draft Report Card link

    /// #40 — entry point into the hindsight Draft Report Card. Placed here so
    /// the History screen (reachable from both the postseason and offseason
    /// quick-action bars) is a home for looking back at past draft classes.
    private var draftReportLink: some View {
        NavigationLink(value: CareerShellView.ShellDestination.draftReportCard) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "checklist")
                    .font(.title3)
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Draft Report Card")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("Hindsight grades for every past draft class")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(DSSpacing.sm)
            .cardBackground()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Career Totals

    private var careerTotalsCard: some View {
        HStack(spacing: DSSpacing.md) {
            totalStat(value: "\(career.totalWins)-\(career.totalLosses)", label: "Career Record")
            totalStat(value: "\(career.playoffAppearances)", label: "Playoff Berths")
            totalStat(value: "\(career.championships)", label: "Titles")
            totalStat(value: "\(inductees.count)", label: "HOF Inductees")
        }
        .frame(maxWidth: .infinity)
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    private func totalStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Season Row

    private func seasonRow(_ summary: SeasonSummary) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Text(String(summary.season))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.accentGold)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentGold)
                    Text(summary.championTeamName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
                if let mvp = summary.mvpName {
                    Text("MVP: \(mvp)\(summary.mvpTeamAbbr.map { " (\($0))" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DSSpacing.xs)

            VStack(alignment: .trailing, spacing: 2) {
                Text(summary.userRecordText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                if summary.userWonChampionship {
                    badge("CHAMPIONS", color: .accentGold)
                } else if summary.userMadePlayoffs {
                    badge("PLAYOFFS", color: .accentBlue)
                } else {
                    badge("MISSED", color: .textTertiary)
                }
            }
        }
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    // MARK: - HOF Row

    private func hofRow(_ entry: HallOfFameEntry) -> some View {
        HStack(spacing: DSSpacing.sm) {
            ZStack {
                Circle()
                    .fill(Color.accentGold.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentGold)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.playerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if entry.wasUserTeamPlayer {
                        badge("YOUR LEGEND", color: .success)
                    }
                }
                Text("\(entry.positionRaw) • \(entry.seasonsPlayed) seasons • retired \(String(entry.inductionSeason)) (\(entry.retiredFromTeamName))")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: DSSpacing.xs)

            VStack(spacing: 1) {
                Text("\(entry.peakOverall)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.forRating(entry.peakOverall))
                Text("PEAK")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(DSSpacing.sm)
        .cardBackground()
    }

    // MARK: - Bits

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.15))
            )
    }

    private func emptyCard(icon: String, text: String) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.textTertiary)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.sm)
        .cardBackground()
    }
}
