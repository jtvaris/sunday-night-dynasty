import SwiftUI
import SwiftData

/// Shared team-strength helper for matchup display.
///
/// Averaging the *entire* roster (incl. deep bench / practice squad) collapses
/// every team to ~70 OVR, so the color thresholds never fire and the badge
/// carries no matchup signal. Averaging the projected starters (top 22 by
/// overall ≈ 11 offense + 11 defense) restores a meaningful spread.
enum TeamStrength {
    /// Number of starters approximated for the OVR average.
    private static let starterCount = 22

    static func startersOVR(_ team: Team?) -> Int {
        guard let team, !team.players.isEmpty else { return 0 }
        let starters = team.players
            .sorted { $0.overall > $1.overall }
            .prefix(starterCount)
        guard !starters.isEmpty else { return 0 }
        let total = starters.reduce(0) { $0 + $1.overall }
        return total / starters.count
    }

    /// League-wide mean of the starters OVR — the pivot the schedule badge
    /// colors hang off. Compute it once per view appearance (32 roster sorts)
    /// and pass it down; don't recompute per row.
    static func leagueAverageStartersOVR(_ teams: [Team]) -> Int {
        let values = teams.map { startersOVR($0) }.filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / values.count
    }

    /// Relative strength color. The league's starters OVR sits in a narrow
    /// band (~75-78), so the old absolute thresholds (80+/70-79/<70) parked
    /// every team in yellow and the badge carried no signal. Colors relative
    /// to the league mean instead: green = strong roster, red = weak roster,
    /// yellow = the league-average band. `leagueAverage` is the truncated
    /// integer mean (sits ~0.5 below the true mean), so the asymmetric +2/-1
    /// offsets land ≈ ±1.5 around the real average — with the observed
    /// spread that colors 78+ green and 75-and-under red.
    static func ovrColor(_ ovr: Int, leagueAverage: Int) -> Color {
        let pivot = leagueAverage > 0 ? leagueAverage : 76
        if ovr >= pivot + 2 { return Color.success }
        if ovr <= pivot - 1 { return Color.danger }
        return Color.warning
    }
}

struct ScheduleView: View {

    let career: Career

    @Query private var allGames: [Game]
    @Query private var allTeams: [Team]

    @State private var selectedWeek: Int
    @State private var previewGame: Game?
    /// League mean of starters OVR — computed once when the view appears so
    /// the badge colors compare opponents against the actual league spread.
    @State private var leagueAvgOVR = 0

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

    /// Up to 3 upcoming games for the player's team starting from the current week.
    private var nextThreePlayerGames: [Game] {
        guard let pid = playerTeamID else { return [] }
        return seasonGames
            .filter { ($0.homeTeamID == pid || $0.awayTeamID == pid) && !$0.isPlayed && $0.week >= career.currentWeek }
            .sorted { $0.week < $1.week }
            .prefix(3)
            .map { $0 }
    }

    private var teamRecords: [UUID: StandingsRecord] {
        let records = StandingsCalculator.calculate(games: seasonGames, teams: allTeams)
        return Dictionary(uniqueKeysWithValues: records.map { ($0.teamID, $0) })
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                weekSelector
                    .padding(.vertical, 12)
                    .background(Color.backgroundSecondary)

                if weekGames.isEmpty && nextThreePlayerGames.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if !nextThreePlayerGames.isEmpty {
                                nextGamesPreview
                                    .padding(.top, 4)
                            }

                            if !weekGames.isEmpty {
                                weekHeader
                                    .padding(.top, nextThreePlayerGames.isEmpty ? 0 : 8)

                                ForEach(weekGames) { game in
                                    GameCard(
                                        game: game,
                                        teams: allTeams,
                                        playerTeamID: playerTeamID,
                                        teamRecords: teamRecords,
                                        leagueAvgOVR: leagueAvgOVR
                                    )
                                    .onTapGesture { previewGame = game }
                                }
                            } else {
                                emptyWeekInline
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
        .onAppear {
            if leagueAvgOVR == 0 {
                leagueAvgOVR = TeamStrength.leagueAverageStartersOVR(allTeams)
            }
        }
        .sheet(item: $previewGame) { game in
            GamePreviewSheet(
                game: game,
                teams: allTeams,
                playerTeamID: playerTeamID,
                teamRecords: teamRecords
            )
        }
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

    // MARK: - Section Headers

    private var weekHeader: some View {
        HStack {
            Text("WEEK \(selectedWeek)")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color.textTertiary)
            if selectedWeek == career.currentWeek {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("CURRENT")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                }
                .foregroundStyle(Color.accentGold)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(Color.accentGold.opacity(0.15))
                )
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Next Games Preview

    private var nextGamesPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11, weight: .bold))
                Text("NEXT 3 GAMES")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                Spacer()
            }
            .foregroundStyle(Color.accentGold)
            .padding(.horizontal, 4)

            HStack(spacing: 8) {
                ForEach(nextThreePlayerGames) { game in
                    NextGamePill(
                        game: game,
                        teams: allTeams,
                        playerTeamID: playerTeamID,
                        teamRecords: teamRecords,
                        isCurrentWeek: game.week == career.currentWeek,
                        leagueAvgOVR: leagueAvgOVR
                    )
                    .onTapGesture { previewGame = game }
                }
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

    private var emptyWeekInline: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(Color.textTertiary)
            Text("No games scheduled for Week \(selectedWeek)")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
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
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textTertiary)
            Text("\(week)")
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(isSelected ? Color.backgroundPrimary : chipTextColor)
        }
        .frame(width: 44, height: 44)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentBlue : Color.backgroundTertiary)
                if isCurrent && !isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentGold, lineWidth: 2)
                }
            }
        )
        .overlay(alignment: .topTrailing) {
            if isCurrent {
                Image(systemName: "chevron.down.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentGold)
                    .background(
                        Circle().fill(isSelected ? Color.accentBlue : Color.backgroundTertiary)
                    )
                    .offset(x: 4, y: -4)
            }
        }
        .accessibilityLabel("Week \(week)\(isCurrent ? ", current week" : "")\(isSelected ? ", selected" : "")")
    }

    private var chipTextColor: Color {
        isCurrent ? Color.accentGold : Color.textSecondary
    }
}

// MARK: - Next Game Pill

private struct NextGamePill: View {
    let game: Game
    let teams: [Team]
    let playerTeamID: UUID?
    let teamRecords: [UUID: StandingsRecord]
    let isCurrentWeek: Bool
    let leagueAvgOVR: Int

    private var opponentID: UUID? {
        guard let pid = playerTeamID else { return nil }
        return game.homeTeamID == pid ? game.awayTeamID : game.homeTeamID
    }

    private var opponent: Team? { teams.first { $0.id == opponentID } }
    private var isHome: Bool {
        guard let pid = playerTeamID else { return false }
        return game.homeTeamID == pid
    }

    private var opponentRecord: String {
        guard let oid = opponentID, let rec = teamRecords[oid] else { return "0-0" }
        if rec.ties > 0 { return "\(rec.wins)-\(rec.losses)-\(rec.ties)" }
        return "\(rec.wins)-\(rec.losses)"
    }

    private var opponentOVR: Int {
        TeamStrength.startersOVR(opponent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("WK \(game.week)")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.textTertiary)
                if isCurrentWeek {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                }
                Spacer()
            }

            HStack(spacing: 4) {
                Text(isHome ? "vs" : "@")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                Text(opponent?.abbreviation ?? "???")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(Color.textPrimary)
            }

            HStack(spacing: 6) {
                if opponentOVR > 0 {
                    Text("OVR \(opponentOVR)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(ovrColor(opponentOVR))
                }
                Text(opponentRecord)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isCurrentWeek ? Color.accentGold.opacity(0.7) : Color.surfaceBorder,
                            lineWidth: isCurrentWeek ? 1.5 : 1
                        )
                )
        )
    }

    private func ovrColor(_ ovr: Int) -> Color {
        TeamStrength.ovrColor(ovr, leagueAverage: leagueAvgOVR)
    }
}

// MARK: - Game Card

private struct GameCard: View {
    let game: Game
    let teams: [Team]
    let playerTeamID: UUID?
    let teamRecords: [UUID: StandingsRecord]
    let leagueAvgOVR: Int

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
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text("YOUR GAME")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                    Spacer()
                    if game.isPlayed {
                        resultLabel
                    } else {
                        Text("TAP FOR PREVIEW")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Color.accentGold.opacity(0.8))
                    }
                }
                .foregroundStyle(isPlayerGame && game.isPlayed ? resultAccentColor : Color.accentGold)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
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
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(borderColor, lineWidth: isPlayerGame ? 1.5 : 1)
                )
        )
        .contentShape(Rectangle())
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
        let frameAlignment: Alignment = alignment == .leading ? .leading : .trailing
        return VStack(alignment: alignment, spacing: 4) {
            Text(team?.abbreviation ?? "???")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isWinner ? Color.success : Color.textPrimary)

            // Record + OVR context
            if let team {
                HStack(spacing: 6) {
                    if alignment == .trailing { Spacer(minLength: 0) }
                    Text(recordString(for: team))
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                    let ovr = teamOVR(team)
                    if ovr > 0 {
                        Text("• OVR \(ovr)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(ovrColor(ovr))
                    }
                    if alignment == .leading { Spacer(minLength: 0) }
                }
                Text(team.city)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            if let score {
                Text("\(score)")
                    .font(.system(size: 28, weight: .heavy).monospacedDigit())
                    .foregroundStyle(isWinner ? Color.success : isTie ? Color.warning : Color.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private func recordString(for team: Team) -> String {
        guard let rec = teamRecords[team.id] else { return "0-0" }
        if rec.ties > 0 { return "\(rec.wins)-\(rec.losses)-\(rec.ties)" }
        return "\(rec.wins)-\(rec.losses)"
    }

    private func teamOVR(_ team: Team) -> Int {
        TeamStrength.startersOVR(team)
    }

    private func ovrColor(_ ovr: Int) -> Color {
        TeamStrength.ovrColor(ovr, leagueAverage: leagueAvgOVR)
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

// MARK: - Game Preview Sheet

private struct GamePreviewSheet: View {
    let game: Game
    let teams: [Team]
    let playerTeamID: UUID?
    let teamRecords: [UUID: StandingsRecord]

    @Environment(\.dismiss) private var dismiss

    private var homeTeam: Team? { teams.first { $0.id == game.homeTeamID } }
    private var awayTeam: Team? { teams.first { $0.id == game.awayTeamID } }

    private func teamOVR(_ team: Team?) -> Int {
        TeamStrength.startersOVR(team)
    }

    private func recordString(for team: Team?) -> String {
        guard let team, let rec = teamRecords[team.id] else { return "0-0" }
        if rec.ties > 0 { return "\(rec.wins)-\(rec.losses)-\(rec.ties)" }
        return "\(rec.wins)-\(rec.losses)"
    }

    /// Top 3 players by overall.
    private func keyPlayers(_ team: Team?) -> [Player] {
        guard let team else { return [] }
        return team.players
            .sorted { $0.overall > $1.overall }
            .prefix(3)
            .map { $0 }
    }

    private var matchupAnalysis: String {
        let home = teamOVR(homeTeam)
        let away = teamOVR(awayTeam)
        guard home > 0, away > 0 else { return "Matchup data unavailable." }
        let diff = abs(home - away)
        let favored = home > away ? (homeTeam?.abbreviation ?? "Home") : (awayTeam?.abbreviation ?? "Away")
        switch diff {
        case 0...2:  return "Even matchup — slight edge to \(favored)."
        case 3...5:  return "\(favored) is favored by a small margin."
        case 6...9:  return "\(favored) holds a clear advantage on paper."
        default:     return "\(favored) is heavily favored."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    analysisSection
                    keyPlayersSection
                }
                .padding(20)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Week \(game.week) Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var headerSection: some View {
        HStack(spacing: 0) {
            teamColumn(awayTeam, alignment: .leading)
            VStack(spacing: 4) {
                Text("@")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                Text(game.isPlayed ? "FINAL" : "UPCOMING")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 64)
            teamColumn(homeTeam, alignment: .trailing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.backgroundSecondary)
        )
    }

    private func teamColumn(_ team: Team?, alignment: HorizontalAlignment) -> some View {
        let frameAlignment: Alignment = alignment == .leading ? .leading : .trailing
        return VStack(alignment: alignment, spacing: 4) {
            Text(team?.abbreviation ?? "???")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(team?.id == playerTeamID ? Color.accentGold : Color.textPrimary)
            Text(team?.fullName ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
            HStack(spacing: 6) {
                if alignment == .trailing { Spacer(minLength: 0) }
                Text(recordString(for: team))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                let ovr = teamOVR(team)
                if ovr > 0 {
                    Text("OVR \(ovr)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.accentBlue)
                }
                if alignment == .leading { Spacer(minLength: 0) }
            }
        }
        .frame(maxWidth: .infinity, alignment: frameAlignment)
    }

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("MATCHUP ANALYSIS")
            Text(matchupAnalysis)
                .font(.system(size: 14))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(Color.backgroundSecondary)
                )
        }
    }

    private var keyPlayersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("KEY PLAYERS")

            VStack(alignment: .leading, spacing: 6) {
                Text(awayTeam?.abbreviation ?? "Away")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.textTertiary)
                ForEach(keyPlayers(awayTeam), id: \.id) { player in
                    keyPlayerRow(player)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.backgroundSecondary))

            VStack(alignment: .leading, spacing: 6) {
                Text(homeTeam?.abbreviation ?? "Home")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.textTertiary)
                ForEach(keyPlayers(homeTeam), id: \.id) { player in
                    keyPlayerRow(player)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.backgroundSecondary))
        }
    }

    private func keyPlayerRow(_ player: Player) -> some View {
        HStack(spacing: 8) {
            Text(player.position.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 32, alignment: .leading)
            Text(player.fullName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(player.overall)")
                .font(.system(size: 13, weight: .heavy).monospacedDigit())
                .foregroundStyle(Color.accentBlue)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Color.textTertiary)
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
