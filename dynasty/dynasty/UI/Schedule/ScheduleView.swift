import SwiftUI
import SwiftData

struct ScheduleView: View {

    let career: Career

    @Query private var allGames: [Game]
    @Query private var allTeams: [Team]

    @State private var selectedWeek: Int

    // MARK: - Init

    init(career: Career) {
        self.career = career
        self._selectedWeek = State(initialValue: career.currentWeek)
    }

    // MARK: - Derived Data

    private var seasonGames: [Game] {
        allGames.filter { $0.seasonYear == career.currentSeason && !$0.isPlayoff }
    }

    private var weekGames: [Game] {
        seasonGames
            .filter { $0.week == selectedWeek }
            .sorted { gameSort($0, $1) }
    }

    private var playerTeamID: UUID? { career.teamID }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                weekSelector
                    .padding(.vertical, 12)
                    .background(Color.backgroundSecondary)

                if weekGames.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(weekGames) { game in
                                GameCard(
                                    game: game,
                                    teams: allTeams,
                                    playerTeamID: playerTeamID
                                )
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Week \(selectedWeek) Schedule")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Week Selector

    private var weekSelector: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(1...18, id: \.self) { week in
                        WeekChip(
                            week: week,
                            isSelected: selectedWeek == week,
                            isCurrent: career.currentWeek == week
                        )
                        .id(week)
                        .onTapGesture { selectedWeek = week }
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear {
                proxy.scrollTo(selectedWeek, anchor: .center)
            }
            .onChange(of: selectedWeek) { _, newWeek in
                withAnimation { proxy.scrollTo(newWeek, anchor: .center) }
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No games scheduled for Week \(selectedWeek)")
                .font(.headline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
    }

    // MARK: - Helpers

    /// Player's team games float to the top, then sort by week (for completeness).
    private func gameSort(_ a: Game, _ b: Game) -> Bool {
        guard let pid = playerTeamID else { return false }
        let aIsPlayer = a.homeTeamID == pid || a.awayTeamID == pid
        let bIsPlayer = b.homeTeamID == pid || b.awayTeamID == pid
        if aIsPlayer != bIsPlayer { return aIsPlayer }
        return false
    }
}

// MARK: - Week Chip

private struct WeekChip: View {
    let week: Int
    let isSelected: Bool
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text("WK")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textTertiary)
            Text("\(week)")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(isSelected ? Color.backgroundPrimary : chipTextColor)
        }
        .frame(width: 44, height: 44)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentGold : Color.backgroundTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isCurrent && !isSelected ? Color.accentGold.opacity(0.5) : Color.clear,
                            lineWidth: 1.5
                        )
                )
        )
        .accessibilityLabel("Week \(week)\(isCurrent ? ", current week" : "")\(isSelected ? ", selected" : "")")
    }

    private var chipTextColor: Color {
        isCurrent ? Color.accentGold : Color.textSecondary
    }
}

// MARK: - Game Card

private struct GameCard: View {
    let game: Game
    let teams: [Team]
    let playerTeamID: UUID?

    private var homeTeam: Team? { teams.first { $0.id == game.homeTeamID } }
    private var awayTeam: Team? { teams.first { $0.id == game.awayTeamID } }

    private var isPlayerGame: Bool {
        guard let pid = playerTeamID else { return false }
        return game.homeTeamID == pid || game.awayTeamID == pid
    }

    private var playerWon: Bool? {
        guard let pid = playerTeamID, game.isPlayed else { return nil }
        if game.winnerID == pid { return true }
        if game.loserID == pid { return false }
        return nil // tie
    }

    private var resultAccentColor: Color {
        switch playerWon {
        case .some(true):  return Color.success
        case .some(false): return Color.danger
        case .none:        return Color.textTertiary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar for player games
            if isPlayerGame {
                HStack {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("YOUR GAME")
                        .font(.system(size: 10, weight: .bold))
                    Spacer()
                    if game.isPlayed {
                        resultLabel
                    }
                }
                .foregroundStyle(isPlayerGame && game.isPlayed ? resultAccentColor : Color.accentGold)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    (isPlayerGame && game.isPlayed ? resultAccentColor : Color.accentGold)
                        .opacity(0.12)
                )
            }

            // Score row
            HStack(spacing: 0) {
                // Away side
                teamSide(
                    team: awayTeam,
                    score: game.awayScore,
                    isWinner: game.isPlayed && game.winnerID == game.awayTeamID,
                    isTie: game.isPlayed && game.winnerID == nil,
                    alignment: .leading
                )

                // Divider / @
                VStack(spacing: 4) {
                    if game.isPlayed {
                        Text("FINAL")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Text("@")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                        Text("UPCOMING")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .frame(width: 56)

                // Home side
                teamSide(
                    team: homeTeam,
                    score: game.homeScore,
                    isWinner: game.isPlayed && game.winnerID == game.homeTeamID,
                    isTie: game.isPlayed && game.winnerID == nil,
                    alignment: .trailing
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(borderColor, lineWidth: isPlayerGame ? 1.5 : 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Team Side

    private func teamSide(
        team: Team?,
        score: Int?,
        isWinner: Bool,
        isTie: Bool,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(team?.abbreviation ?? "???")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isWinner ? Color.accentGold : Color.textPrimary)

            Text(team?.city ?? "")
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            if let score {
                Text("\(score)")
                    .font(.system(size: 28, weight: .heavy).monospacedDigit())
                    .foregroundStyle(isWinner ? Color.accentGold : isTie ? Color.warning : Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    // MARK: - Result Label

    private var resultLabel: some View {
        Text(resultText)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(resultAccentColor)
    }

    private var resultText: String {
        switch playerWon {
        case .some(true):  return "WIN"
        case .some(false): return "LOSS"
        case .none:        return game.isPlayed ? "TIE" : ""
        }
    }

    // MARK: - Border Color

    private var borderColor: Color {
        if isPlayerGame {
            if game.isPlayed {
                return resultAccentColor.opacity(0.6)
            }
            return Color.accentGold.opacity(0.6)
        }
        return Color.surfaceBorder
    }

    // MARK: - Accessibility

    private var accessibilityDescription: String {
        let away = awayTeam?.fullName ?? "Away team"
        let home = homeTeam?.fullName ?? "Home team"
        if game.isPlayed, let hs = game.homeScore, let as_ = game.awayScore {
            return "\(away) \(as_), \(home) \(hs), final"
        }
        return "\(away) at \(home), upcoming"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScheduleView(career: Career(
            playerName: "Coach Smith",
            role: .gmAndHeadCoach,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Game.self, Team.self], inMemory: true)
}
