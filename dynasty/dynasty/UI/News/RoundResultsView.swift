import SwiftUI

/// #38 — Post-game round recap overlay.
///
/// A dismissable, presentation-only summary shown once after each regular-season
/// week is advanced. It stitches together data that already exists on the career
/// (no parallel systems): this week's league-wide scores (from `Game` rows), the
/// freshly computed power rankings and MVP race (`LeagueNarrativeState`), and a
/// couple of storyline headlines (`Career.newsLog`).
///
/// It never blocks the flow: the primary "Continue" button — and the top-right
/// close control — dismiss straight back to the dashboard (see the #37 lesson on
/// navigation dead-ends). Optional links jump to the full Standings / News views.
struct RoundResultsView: View {

    // MARK: - Data

    /// One league game from the recapped week, snapshotted for display.
    struct GameLine: Identifiable {
        let id: UUID
        let awayAbbr: String
        let awayName: String
        let awayScore: Int
        let homeAbbr: String
        let homeName: String
        let homeScore: Int
        let isUserGame: Bool
        let tag: Tag?

        enum Tag {
            case blowout
            case upset

            var label: String {
                switch self {
                case .blowout: return String(localized: "BLOWOUT")
                case .upset:   return String(localized: "UPSET")
                }
            }

            var color: Color {
                switch self {
                case .blowout: return Color.warning
                case .upset:   return Color(red: 0.6, green: 0.45, blue: 0.9)
                }
            }
        }

        var awayWon: Bool { awayScore > homeScore }
        var homeWon: Bool { homeScore > awayScore }
    }

    /// Everything the recap needs, assembled by the caller from existing state.
    struct Data: Identifiable {
        let id = UUID()
        let week: Int
        let season: Int
        let games: [GameLine]
        let rankings: [PowerRankingEntry]
        let mvpRace: [MVPCandidate]
        let storylines: [NewsItem]
        let userTeamID: UUID?
    }

    let data: Data
    var onSeeStandings: (() -> Void)?
    var onSeeNews: (() -> Void)?
    let onDismiss: () -> Void

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        scoresSection
                        if !data.rankings.isEmpty {
                            powerRankingSection
                        }
                        if !data.mvpRace.isEmpty {
                            mvpSection
                        }
                        if !data.storylines.isEmpty {
                            storylinesSection
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
                footer
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Week \(data.week) Recap"))
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Color.textPrimary)
                Text(String(localized: "Around the league · Season \(data.season)"))
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close recap"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.surfaceBorder)
        }
    }

    // MARK: - Scores

    private var scoresSection: some View {
        sectionCard(
            title: String(localized: "This Week's Results"),
            icon: "sportscourt.fill",
            iconColor: Color.accentBlue,
            trailing: "\(data.games.count) \(data.games.count == 1 ? String(localized: "game") : String(localized: "games"))"
        ) {
            VStack(spacing: 8) {
                ForEach(data.games) { game in
                    scoreRow(game)
                }
            }
        }
    }

    private func scoreRow(_ game: GameLine) -> some View {
        HStack(spacing: 10) {
            teamScore(abbr: game.awayAbbr, score: game.awayScore, won: game.awayWon, isUser: game.isUserGame)
            Text("@")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textTertiary)
            teamScore(abbr: game.homeAbbr, score: game.homeScore, won: game.homeWon, isUser: game.isUserGame)

            Spacer(minLength: 4)

            if let tag = game.tag {
                Text(tag.label)
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(tag.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().stroke(tag.color.opacity(0.6), lineWidth: 1)
                    )
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(game.isUserGame ? Color.accentGold.opacity(0.12) : Color.backgroundTertiary.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            game.isUserGame ? Color.accentGold.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
    }

    private func teamScore(abbr: String, score: Int, won: Bool, isUser: Bool) -> some View {
        HStack(spacing: 6) {
            Text(abbr)
                .font(.subheadline.weight(won ? .heavy : .medium))
                .foregroundStyle(isUser ? Color.accentGold : (won ? Color.textPrimary : Color.textSecondary))
                .frame(width: 42, alignment: .leading)
            Text("\(score)")
                .font(.subheadline.weight(won ? .heavy : .regular))
                .monospacedDigit()
                .foregroundStyle(won ? Color.textPrimary : Color.textTertiary)
                .frame(width: 26, alignment: .trailing)
        }
    }

    // MARK: - Power Ranking

    /// Top-10 always; the user's team is appended when it sits below the line.
    private var visibleRankings: [PowerRankingEntry] {
        let topTen = Array(data.rankings.prefix(10))
        guard let userTeamID = data.userTeamID,
              let userEntry = data.rankings.first(where: { $0.teamID == userTeamID }),
              userEntry.rank > 10 else {
            return topTen
        }
        return topTen + [userEntry]
    }

    private var userBelowLine: Bool {
        guard let userTeamID = data.userTeamID,
              let userEntry = data.rankings.first(where: { $0.teamID == userTeamID }) else {
            return false
        }
        return userEntry.rank > 10
    }

    private var powerRankingSection: some View {
        sectionCard(
            title: String(localized: "Power Rankings"),
            icon: "list.number",
            iconColor: Color.accentBlue,
            trailing: String(localized: "Top 10")
        ) {
            VStack(spacing: 6) {
                ForEach(visibleRankings) { entry in
                    if userBelowLine && entry.teamID == data.userTeamID {
                        HStack {
                            Image(systemName: "ellipsis")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                        }
                        .padding(.leading, 12)
                    }
                    rankingRow(entry)
                }
            }
        }
    }

    private func rankingRow(_ entry: PowerRankingEntry) -> some View {
        let isUserTeam = entry.teamID == data.userTeamID
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(entry.rank)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(entry.rank <= 3 ? Color.accentGold : Color.textSecondary)
                .frame(width: 24, alignment: .trailing)

            movementBadge(entry.movement)
                .frame(width: 34, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.teamAbbr)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isUserTeam ? Color.accentGold : Color.textPrimary)
                    Text(entry.teamName)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                    Text(entry.record)
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.textTertiary)
                }
                Text(entry.blurb)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isUserTeam ? Color.accentGold.opacity(0.12) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isUserTeam ? Color.accentGold.opacity(0.45) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
    }

    @ViewBuilder
    private func movementBadge(_ movement: Int) -> some View {
        if movement > 0 {
            HStack(spacing: 2) {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("\(movement)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.success)
            .accessibilityLabel(String(localized: "Up \(movement) spots"))
        } else if movement < 0 {
            HStack(spacing: 2) {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("\(-movement)")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(Color.danger)
            .accessibilityLabel(String(localized: "Down \(-movement) spots"))
        } else {
            Text("—")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.textTertiary)
                .accessibilityLabel(String(localized: "No movement"))
        }
    }

    // MARK: - MVP Race

    private var mvpLeaderPoints: Double {
        max(data.mvpRace.map(\.points).max() ?? 1, 1)
    }

    private var mvpSection: some View {
        sectionCard(
            title: String(localized: "MVP Race"),
            icon: "trophy.fill",
            iconColor: Color.accentGold,
            trailing: nil
        ) {
            VStack(spacing: 10) {
                ForEach(Array(data.mvpRace.prefix(3).enumerated()), id: \.element.id) { index, candidate in
                    mvpRow(candidate, position: index + 1)
                }
            }
        }
    }

    private func mvpRow(_ candidate: MVPCandidate, position: Int) -> some View {
        let isUserTeam = candidate.teamID != nil && candidate.teamID == data.userTeamID
        let share = candidate.points / mvpLeaderPoints
        return HStack(spacing: 10) {
            Text("\(position)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(position == 1 ? Color.accentGold : Color.textSecondary)
                .frame(width: 18, alignment: .trailing)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(candidate.playerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isUserTeam ? Color.accentGold : Color.textPrimary)
                        .lineLimit(1)
                    Text("\(candidate.positionRaw) · \(candidate.teamAbbr)")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.backgroundTertiary)
                        Capsule()
                            .fill(position == 1 ? Color.accentGold : Color.accentBlue)
                            .frame(width: max(8, geo.size.width * share))
                    }
                }
                .frame(height: 5)
            }
        }
    }

    // MARK: - Storylines

    private var storylinesSection: some View {
        sectionCard(
            title: String(localized: "Storylines"),
            icon: "newspaper.fill",
            iconColor: Color.textSecondary,
            trailing: nil
        ) {
            VStack(spacing: 12) {
                ForEach(data.storylines) { item in
                    storylineRow(item)
                }
            }
        }
    }

    private func storylineRow(_ item: NewsItem) -> some View {
        let isMyTeam = item.relatedTeamID != nil && item.relatedTeamID == data.userTeamID
        return HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(item.sentiment.color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.headline)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isMyTeam ? Color.accentGold : Color.textPrimary)
                    .multilineTextAlignment(.leading)
                Text(item.body)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Button(action: onDismiss) {
                Text(String(localized: "Continue"))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.accentGold)
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                if let onSeeStandings {
                    linkButton(String(localized: "Full Standings"), icon: "list.bullet.rectangle", action: onSeeStandings)
                }
                if let onSeeNews {
                    linkButton(String(localized: "League News"), icon: "newspaper", action: onSeeNews)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .top) {
            Divider().overlay(Color.surfaceBorder)
        }
    }

    private func linkButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.accentBlue)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section Card

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        trailing: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.textTertiary)
                }
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }
}
