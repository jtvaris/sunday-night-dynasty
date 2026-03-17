import SwiftUI

// MARK: - GameSummaryView

/// Full post-game summary screen shown after a game concludes.
struct GameSummaryView: View {

    @Environment(\.dismiss) private var dismiss

    let boxScore: BoxScore
    let homeTeam: Team
    let awayTeam: Team
    let playerStats: [PlayerGameStats]

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                LazyVStack(spacing: 16) {
                    scoreHeaderCard
                    teamComparisonCard
                    topPerformersCard
                    highlightsCard
                    driveSummaryCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Game Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentGold)
            }
        }
    }

    // MARK: - Score Header Card

    private var scoreHeaderCard: some View {
        VStack(spacing: 16) {
            // FINAL badge
            Text("FINAL")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.accentGold)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.accentGold.opacity(0.15), in: Capsule())

            // Main scoreboard
            HStack(alignment: .center, spacing: 0) {
                // Away team
                teamScoreBlock(
                    abbreviation: awayTeam.abbreviation,
                    fullName: awayTeam.fullName,
                    score: boxScore.away.score,
                    isWinner: boxScore.away.score > boxScore.home.score,
                    alignment: .leading
                )

                // Divider dash
                Text("—")
                    .font(.system(size: 28, weight: .thin))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 40)

                // Home team
                teamScoreBlock(
                    abbreviation: homeTeam.abbreviation,
                    fullName: homeTeam.fullName,
                    score: boxScore.home.score,
                    isWinner: boxScore.home.score > boxScore.away.score,
                    alignment: .trailing
                )
            }

            Divider()
                .background(Color.surfaceBorder)

            // Quarter-by-quarter scores
            quarterScoresRow
        }
        .padding(20)
        .cardBackground()
    }

    private func teamScoreBlock(
        abbreviation: String,
        fullName: String,
        score: Int,
        isWinner: Bool,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(abbreviation)
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(isWinner ? Color.accentGold : Color.textPrimary)

            Text(fullName)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text("\(score)")
                .font(.system(size: 48, weight: .black).monospacedDigit())
                .foregroundStyle(isWinner ? Color.accentGold : Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private var quarterScoresRow: some View {
        let quarters = max(
            boxScore.away.quarterScores.count,
            boxScore.home.quarterScores.count
        )
        let hasOT = quarters > 4

        return HStack(spacing: 0) {
            // Header column
            VStack(alignment: .trailing, spacing: 6) {
                Text("")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 18)
                Text(awayTeam.abbreviation)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                Text(homeTeam.abbreviation)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(width: 44, alignment: .trailing)

            Spacer(minLength: 8)

            // Quarter columns
            ForEach(0..<quarters, id: \.self) { idx in
                VStack(spacing: 6) {
                    Text(idx < 4 ? "Q\(idx + 1)" : "OT")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(height: 18)
                    Text(quarterScore(scores: boxScore.away.quarterScores, index: idx))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text(quarterScore(scores: boxScore.home.quarterScores, index: idx))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                }
                .frame(maxWidth: .infinity)
            }

            // Final column
            Divider()
                .frame(height: 56)
                .background(Color.surfaceBorder)
                .padding(.horizontal, 6)

            VStack(spacing: 6) {
                Text("F")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .frame(height: 18)
                Text("\(boxScore.away.score)")
                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                    .foregroundStyle(boxScore.away.score > boxScore.home.score ? Color.accentGold : Color.textPrimary)
                Text("\(boxScore.home.score)")
                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                    .foregroundStyle(boxScore.home.score > boxScore.away.score ? Color.accentGold : Color.textPrimary)
            }
            .frame(width: 32)
        }
    }

    private func quarterScore(scores: [Int], index: Int) -> String {
        guard index < scores.count else { return "-" }
        return "\(scores[index])"
    }

    // MARK: - Team Comparison Card

    private var teamComparisonCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(title: "Team Stats", systemImage: "chart.bar.fill")

            VStack(spacing: 14) {
                StatComparisonRow(
                    label: "Total Yards",
                    awayValue: "\(boxScore.away.totalYards)",
                    homeValue: "\(boxScore.home.totalYards)",
                    awayRaw: Double(boxScore.away.totalYards),
                    homeRaw: Double(boxScore.home.totalYards)
                )
                StatComparisonRow(
                    label: "Passing Yards",
                    awayValue: "\(boxScore.away.passingYards)",
                    homeValue: "\(boxScore.home.passingYards)",
                    awayRaw: Double(boxScore.away.passingYards),
                    homeRaw: Double(boxScore.home.passingYards)
                )
                StatComparisonRow(
                    label: "Rushing Yards",
                    awayValue: "\(boxScore.away.rushingYards)",
                    homeValue: "\(boxScore.home.rushingYards)",
                    awayRaw: Double(boxScore.away.rushingYards),
                    homeRaw: Double(boxScore.home.rushingYards)
                )
                StatComparisonRow(
                    label: "First Downs",
                    awayValue: "\(boxScore.away.firstDowns)",
                    homeValue: "\(boxScore.home.firstDowns)",
                    awayRaw: Double(boxScore.away.firstDowns),
                    homeRaw: Double(boxScore.home.firstDowns)
                )
                StatComparisonRow(
                    label: "3rd Down %",
                    awayValue: thirdDownPct(boxScore.away),
                    homeValue: thirdDownPct(boxScore.home),
                    awayRaw: thirdDownRaw(boxScore.away),
                    homeRaw: thirdDownRaw(boxScore.home)
                )
                StatComparisonRow(
                    label: "Turnovers",
                    awayValue: "\(boxScore.away.turnovers)",
                    homeValue: "\(boxScore.home.turnovers)",
                    awayRaw: Double(boxScore.away.turnovers),
                    homeRaw: Double(boxScore.home.turnovers),
                    lowerIsBetter: true
                )
                StatComparisonRow(
                    label: "Sacks",
                    awayValue: "\(boxScore.away.sacks)",
                    homeValue: "\(boxScore.home.sacks)",
                    awayRaw: Double(boxScore.away.sacks),
                    homeRaw: Double(boxScore.home.sacks)
                )
                StatComparisonRow(
                    label: "Time of Possession",
                    awayValue: formatPossession(boxScore.away.timeOfPossession),
                    homeValue: formatPossession(boxScore.home.timeOfPossession),
                    awayRaw: Double(boxScore.away.timeOfPossession),
                    homeRaw: Double(boxScore.home.timeOfPossession)
                )
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func thirdDownPct(_ team: TeamBoxScore) -> String {
        guard team.thirdDownAttempts > 0 else { return "0%" }
        let pct = Int(round(Double(team.thirdDownConversions) / Double(team.thirdDownAttempts) * 100))
        return "\(team.thirdDownConversions)/\(team.thirdDownAttempts)"
    }

    private func thirdDownRaw(_ team: TeamBoxScore) -> Double {
        guard team.thirdDownAttempts > 0 else { return 0 }
        return Double(team.thirdDownConversions) / Double(team.thirdDownAttempts)
    }

    private func formatPossession(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Top Performers Card

    private var topPerformersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(title: "Top Performers", systemImage: "person.fill.checkmark")

            HStack(alignment: .top, spacing: 16) {
                // Away performers
                VStack(alignment: .leading, spacing: 10) {
                    Text(awayTeam.abbreviation)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.bottom, 2)

                    ForEach(topPerformers(for: boxScore.away.teamID)) { stat in
                        PlayerStatRow(stat: stat)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider()
                    .background(Color.surfaceBorder)

                // Home performers
                VStack(alignment: .leading, spacing: 10) {
                    Text(homeTeam.abbreviation)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.bottom, 2)

                    ForEach(topPerformers(for: boxScore.home.teamID)) { stat in
                        PlayerStatRow(stat: stat)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .cardBackground()
    }

    /// Returns up to 4 notable performers for a given team, sorted by role priority.
    private func topPerformers(for teamID: UUID) -> [PlayerGameStats] {
        // We don't have team membership in PlayerGameStats, so we split by halving the array.
        // Caller-supplied playerStats are assumed to be ordered [away players..., home players...].
        // Fall back to filtering by meaningful contribution since no teamID exists on PlayerGameStats.
        let candidates = playerStats.filter { stat in
            // Include only players with meaningful output
            stat.passingYards > 0 || stat.rushingYards > 0 ||
            stat.receivingYards > 0 || stat.tackles > 0 || stat.sacks > 0
        }

        // Split into two halves: first half = away, second half = home.
        let half = candidates.count / 2
        let pool: [PlayerGameStats]
        if teamID == boxScore.away.teamID {
            pool = Array(candidates.prefix(half == 0 ? candidates.count : half))
        } else {
            pool = Array(candidates.suffix(half == 0 ? candidates.count : half))
        }

        // Pick the best QB, RB, and top 1–2 receivers/pass-catchers from the pool.
        var result: [PlayerGameStats] = []

        if let qb = pool.filter({ $0.attempts > 0 }).max(by: { $0.passingYards < $1.passingYards }) {
            result.append(qb)
        }
        if let rb = pool.filter({ $0.carries > 0 }).max(by: { $0.rushingYards < $1.rushingYards }) {
            if !result.contains(where: { $0.id == rb.id }) { result.append(rb) }
        }
        let receivers = pool
            .filter { $0.receptions > 0 }
            .sorted { $0.receivingYards > $1.receivingYards }
            .prefix(2)
        for wr in receivers {
            if !result.contains(where: { $0.id == wr.id }) && result.count < 4 {
                result.append(wr)
            }
        }
        if result.count < 3, let defender = pool.filter({ $0.tackles > 0 || $0.sacks > 0 }).max(by: { $0.tackles < $1.tackles }) {
            if !result.contains(where: { $0.id == defender.id }) { result.append(defender) }
        }

        return Array(result.prefix(4))
    }

    // MARK: - Highlights Card

    private var highlightsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(title: "Highlights", systemImage: "star.fill")

            if boxScore.highlights.isEmpty {
                Text("No highlights recorded.")
                    .font(.subheadline)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(boxScore.highlights.enumerated()), id: \.offset) { idx, play in
                        HighlightRow(play: play)

                        if idx < boxScore.highlights.count - 1 {
                            Divider()
                                .background(Color.surfaceBorder)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Drive Summary Card

    private var driveSummaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Non-collapsible header row outside the DisclosureGroup
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.to.line")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                Text("Drive Summary")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(boxScore.drives.count) drives")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .background(Color.surfaceBorder)

            VStack(spacing: 0) {
                ForEach(Array(boxScore.drives.enumerated()), id: \.offset) { idx, drive in
                    DriveDisclosureRow(
                        drive: drive,
                        homeTeam: homeTeam,
                        awayTeam: awayTeam
                    )

                    if idx < boxScore.drives.count - 1 {
                        Divider()
                            .background(Color.surfaceBorder)
                            .padding(.leading, 20)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .cardBackground()
    }

    // MARK: - Helpers

    private func cardHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentGold)
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.textPrimary)
        }
    }
}

// MARK: - PlayerStatRow

private struct PlayerStatRow: View {
    let stat: PlayerGameStats

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Position badge
                Text(stat.position.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(positionColor, in: RoundedRectangle(cornerRadius: 3))

                Text(stat.playerName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
            }

            Text(statLine)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statLine: String {
        switch stat.position {
        case .QB:
            let rating = String(format: "%.1f", stat.passerRating)
            return "\(stat.completions)/\(stat.attempts), \(stat.passingYards) yds, \(stat.passingTDs) TD, \(stat.interceptions) INT · \(rating) RTG"
        case .RB, .FB:
            let ypc = String(format: "%.1f", stat.yardsPerCarry)
            var line = "\(stat.carries) car, \(stat.rushingYards) yds (\(ypc)/c), \(stat.rushingTDs) TD"
            if stat.receptions > 0 {
                line += " · \(stat.receptions) rec, \(stat.receivingYards) yds"
            }
            return line
        case .WR, .TE:
            let ypr = String(format: "%.1f", stat.yardsPerReception)
            return "\(stat.receptions)/\(stat.targets) rec, \(stat.receivingYards) yds (\(ypr)/r), \(stat.receivingTDs) TD"
        case .DE, .DT, .OLB, .MLB, .CB, .FS, .SS:
            var parts: [String] = []
            if stat.tackles > 0    { parts.append("\(stat.tackles) tkl") }
            if stat.sacks > 0      { parts.append(String(format: "%.1f sck", stat.sacks)) }
            if stat.interceptionsCaught > 0 { parts.append("\(stat.interceptionsCaught) INT") }
            return parts.joined(separator: ", ")
        case .K:
            return "\(stat.fieldGoalsMade)/\(stat.fieldGoalsAttempted) FG"
        default:
            return "\(stat.rushingYards + stat.receivingYards) yds"
        }
    }

    private var positionColor: Color {
        switch stat.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }
}

// MARK: - HighlightRow

private struct HighlightRow: View {
    let play: PlayResult

    private var accentColor: Color {
        if play.scoringPlay  { return .accentGold }
        if play.isTurnover   { return .danger     }
        if abs(play.yardsGained) >= 20 { return .accentBlue }
        return .textSecondary
    }

    private var quarterLabel: String {
        play.quarter <= 4 ? "Q\(play.quarter)" : "OT"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Quarter pill
            Text(quarterLabel)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(accentColor)
                .frame(width: 28, height: 20)
                .background(accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

            // Description
            Text(play.description)
                .font(.system(size: 14))
                .foregroundStyle(Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Yards badge (only for plays with notable yardage)
            if play.yardsGained != 0 {
                Text(yardsBadgeText)
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(quarterLabel): \(play.description), \(yardsBadgeText)")
    }

    private var yardsBadgeText: String {
        let y = play.yardsGained
        if play.scoringPlay && play.pointsScored > 0 {
            return "+\(play.pointsScored) pts"
        }
        return y >= 0 ? "+\(y) yds" : "\(y) yds"
    }
}

// MARK: - DriveDisclosureRow

private struct DriveDisclosureRow: View {
    let drive: DriveResult
    let homeTeam: Team
    let awayTeam: Team

    @State private var isExpanded = false

    private var teamAbbrev: String {
        drive.teamID == homeTeam.id ? homeTeam.abbreviation : awayTeam.abbreviation
    }

    private var resultColor: Color {
        switch drive.result {
        case .touchdown:                return .accentGold
        case .fieldGoal:                return .success
        case .turnover, .turnoverOnDowns: return .danger
        case .safety:                   return .warning
        case .punt, .endOfHalf, .endOfGame: return .textTertiary
        }
    }

    private var resultIcon: String {
        switch drive.result {
        case .touchdown:       return "trophy.fill"
        case .fieldGoal:       return "soccerball"
        case .turnover:        return "arrow.uturn.left.circle.fill"
        case .turnoverOnDowns: return "xmark.circle.fill"
        case .safety:          return "shield.fill"
        case .punt:            return "arrow.up.right"
        case .endOfHalf:       return "clock.fill"
        case .endOfGame:       return "flag.checkered"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary row — tappable to expand
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    // Drive number
                    Text("#\(drive.driveNumber)")
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 28, alignment: .leading)

                    // Team abbrev
                    Text(teamAbbrev)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 36, alignment: .leading)

                    // Result
                    HStack(spacing: 4) {
                        Image(systemName: resultIcon)
                            .font(.system(size: 10))
                        Text(drive.result.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(resultColor)

                    Spacer()

                    // Stats
                    HStack(spacing: 14) {
                        statPill(value: "\(drive.totalYards) yds", icon: nil)
                        statPill(value: "\(drive.totalPlays) plays", icon: nil)
                    }

                    // Chevron
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 18)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            // Expanded play-by-play
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.surfaceBorder)
                        .padding(.leading, 20)

                    ForEach(Array(drive.plays.enumerated()), id: \.offset) { idx, play in
                        PlayDescriptionRow(play: play)

                        if idx < drive.plays.count - 1 {
                            Divider()
                                .background(Color.surfaceBorder)
                                .padding(.leading, 56)
                        }
                    }
                }
                .background(Color.backgroundPrimary.opacity(0.4))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func statPill(value: String, icon: String?) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10)) }
            Text(value)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
    }
}

// MARK: - PlayDescriptionRow

private struct PlayDescriptionRow: View {
    let play: PlayResult

    private var downDistanceLabel: String {
        "\(ordinal(play.down)) & \(play.distance)"
    }

    private var accentColor: Color {
        if play.scoringPlay  { return .accentGold }
        if play.isTurnover   { return .danger     }
        if play.isFirstDown  { return .success    }
        return .textTertiary
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Down-and-distance pill
            Text(downDistanceLabel)
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(accentColor)
                .frame(width: 48, alignment: .trailing)
                .padding(.top, 2)

            // Description text
            Text(play.description)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Yards
            Text(play.yardsGained >= 0 ? "+\(play.yardsGained)" : "\(play.yardsGained)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(play.yardsGained > 0 ? Color.textPrimary : Color.danger)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        case 4: return "4th"
        default: return "\(n)th"
        }
    }
}

// MARK: - Preview

#Preview {
    let homeTeam = Team(
        name: "Chiefs",
        city: "Kansas City",
        abbreviation: "KC",
        conference: .AFC,
        division: .west,
        mediaMarket: .large
    )
    let awayTeam = Team(
        name: "Eagles",
        city: "Philadelphia",
        abbreviation: "PHI",
        conference: .NFC,
        division: .east,
        mediaMarket: .large
    )

    let samplePlay = PlayResult(
        playNumber: 1, quarter: 1, timeRemaining: 840,
        down: 1, distance: 10, yardLine: 25,
        playType: .pass, outcome: .touchdown,
        yardsGained: 35, description: "Mahomes throws 35 yards to Kelce for a TOUCHDOWN",
        isFirstDown: true, isTurnover: false, scoringPlay: true, pointsScored: 6
    )
    let turnoverPlay = PlayResult(
        playNumber: 2, quarter: 2, timeRemaining: 420,
        down: 2, distance: 8, yardLine: 40,
        playType: .pass, outcome: .interception,
        yardsGained: -5, description: "Hurts intercepted by Tyrann Mathieu at the 45",
        isFirstDown: false, isTurnover: true, scoringPlay: false, pointsScored: 0
    )
    let bigPlay = PlayResult(
        playNumber: 3, quarter: 3, timeRemaining: 600,
        down: 1, distance: 10, yardLine: 30,
        playType: .run, outcome: .rush,
        yardsGained: 24, description: "Miles Sanders rushes 24 yards to the KC 46",
        isFirstDown: true, isTurnover: false, scoringPlay: false, pointsScored: 0
    )

    let drive = DriveResult(
        driveNumber: 1,
        teamID: homeTeam.id,
        startingYardLine: 25,
        plays: [samplePlay, bigPlay],
        result: .touchdown
    )

    let boxScore = BoxScore(
        home: TeamBoxScore(
            teamID: homeTeam.id, score: 27,
            quarterScores: [7, 10, 3, 7],
            totalYards: 412, passingYards: 295, rushingYards: 117,
            firstDowns: 22, thirdDownConversions: 7, thirdDownAttempts: 14,
            turnovers: 0, sacks: 3, penalties: 5, penaltyYards: 45,
            timeOfPossession: 1966, drives: 12
        ),
        away: TeamBoxScore(
            teamID: awayTeam.id, score: 21,
            quarterScores: [7, 7, 0, 7],
            totalYards: 347, passingYards: 268, rushingYards: 79,
            firstDowns: 18, thirdDownConversions: 5, thirdDownAttempts: 13,
            turnovers: 2, sacks: 1, penalties: 7, penaltyYards: 62,
            timeOfPossession: 1634, drives: 11
        ),
        drives: [drive],
        highlights: [samplePlay, turnoverPlay, bigPlay]
    )

    let stats: [PlayerGameStats] = [
        PlayerGameStats(
            playerID: UUID(), playerName: "P. Mahomes", position: .QB,
            passingYards: 295, passingTDs: 3, interceptions: 0,
            completions: 24, attempts: 34
        ),
        PlayerGameStats(
            playerID: UUID(), playerName: "I. Pacheco", position: .RB,
            rushingYards: 117, rushingTDs: 1, carries: 22
        ),
        PlayerGameStats(
            playerID: UUID(), playerName: "J. Hurts", position: .QB,
            passingYards: 268, passingTDs: 2, interceptions: 2,
            completions: 21, attempts: 35
        ),
        PlayerGameStats(
            playerID: UUID(), playerName: "D. Smith", position: .WR,
            receivingYards: 112, receivingTDs: 1, receptions: 8, targets: 11
        )
    ]

    NavigationStack {
        GameSummaryView(
            boxScore: boxScore,
            homeTeam: homeTeam,
            awayTeam: awayTeam,
            playerStats: stats
        )
    }
}
