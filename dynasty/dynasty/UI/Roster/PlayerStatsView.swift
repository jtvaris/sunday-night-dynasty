import SwiftUI

// MARK: - Player Stats View

/// Comprehensive player statistics view showing season stats, career totals,
/// and a per-game log. Presented as a tab within PlayerDetailView.
struct PlayerStatsView: View {
    let player: Player
    let seasonStats: [PlayerGameStats]

    @State private var selectedTab: StatsTab = .season

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isWideLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                statsTabPicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                switch selectedTab {
                case .season:
                    seasonStatsContent
                case .career:
                    careerStatsContent
                case .gameLog:
                    gameLogContent
                }
            }
        }
        .navigationTitle("\(player.fullName) Stats")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Tab Picker

    private var statsTabPicker: some View {
        Picker("Stats Tab", selection: $selectedTab) {
            ForEach(StatsTab.allCases) { tab in
                Text(tab.label).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Season Stats

    private var seasonStatsContent: some View {
        let totals = aggregatedStats(from: seasonStats)
        let gamesPlayed = seasonStats.count

        return List {
            // Header
            Section {
                HStack(spacing: 16) {
                    statCircle(value: "\(gamesPlayed)", label: "GP", color: .accentGold)
                    statCircle(value: "\(player.overall)", label: "OVR", color: Color.forRating(player.overall))
                    statCircle(value: formIndicator.symbol, label: "Form", color: formIndicator.color)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.backgroundSecondary)

            // Position-specific season stats
            positionStatsSection(stats: totals, gamesPlayed: gamesPlayed, title: "Season Totals")
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    // MARK: - Career Stats

    private var careerStatsContent: some View {
        let totals = aggregatedStats(from: seasonStats)
        let gamesPlayed = seasonStats.count

        return List {
            Section {
                HStack(spacing: 16) {
                    statCircle(value: "\(player.yearsPro)", label: "Seasons", color: .accentGold)
                    statCircle(value: "\(gamesPlayed)", label: "Games", color: .accentBlue)
                    statCircle(value: "\(player.age)", label: "Age", color: .textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.backgroundSecondary)

            positionStatsSection(stats: totals, gamesPlayed: gamesPlayed, title: "Career Totals")

            if gamesPlayed > 0 {
                positionAveragesSection(stats: totals, gamesPlayed: gamesPlayed)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    // MARK: - Game Log

    private var gameLogContent: some View {
        List {
            if seasonStats.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "chart.bar.xaxis")
                                .font(.largeTitle)
                                .foregroundStyle(Color.textTertiary)
                            Text("No game data available")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 24)
                }
                .listRowBackground(Color.backgroundSecondary)
            } else {
                // Column header
                Section {
                    gameLogHeader
                } header: {
                    Text("Game Log")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                .listRowBackground(Color.backgroundSecondary)

                ForEach(Array(seasonStats.enumerated()), id: \.offset) { index, game in
                    Section {
                        gameLogRow(week: index + 1, stats: game)
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    // MARK: - Position-Specific Stats Sections

    @ViewBuilder
    private func positionStatsSection(stats: PlayerGameStats, gamesPlayed: Int, title: String) -> some View {
        switch player.position {
        case .QB:
            Section(title) {
                statRow("Completions/Attempts", value: "\(stats.completions)/\(stats.attempts)")
                statRow("Passing Yards", value: "\(stats.passingYards)")
                statRow("Passing TDs", value: "\(stats.passingTDs)", highlight: stats.passingTDs > 0)
                statRow("Interceptions", value: "\(stats.interceptions)", negative: stats.interceptions > 0)
                statRow("Passer Rating", value: String(format: "%.1f", stats.passerRating))
                if stats.carries > 0 {
                    statRow("Rush Yards", value: "\(stats.rushingYards)")
                    statRow("Rush TDs", value: "\(stats.rushingTDs)", highlight: stats.rushingTDs > 0)
                }
            }
            .listRowBackground(Color.backgroundSecondary)

        case .RB, .FB:
            Section(title) {
                statRow("Carries", value: "\(stats.carries)")
                statRow("Rushing Yards", value: "\(stats.rushingYards)")
                statRow("Rushing TDs", value: "\(stats.rushingTDs)", highlight: stats.rushingTDs > 0)
                statRow("Yards/Carry", value: String(format: "%.1f", stats.yardsPerCarry))
                if stats.receptions > 0 {
                    statRow("Receptions", value: "\(stats.receptions)")
                    statRow("Receiving Yards", value: "\(stats.receivingYards)")
                    statRow("Receiving TDs", value: "\(stats.receivingTDs)", highlight: stats.receivingTDs > 0)
                }
            }
            .listRowBackground(Color.backgroundSecondary)

        case .WR, .TE:
            Section(title) {
                statRow("Targets", value: "\(stats.targets)")
                statRow("Receptions", value: "\(stats.receptions)")
                statRow("Receiving Yards", value: "\(stats.receivingYards)")
                statRow("Receiving TDs", value: "\(stats.receivingTDs)", highlight: stats.receivingTDs > 0)
                statRow("Yards/Reception", value: String(format: "%.1f", stats.yardsPerReception))
                if stats.carries > 0 {
                    statRow("Rush Yards", value: "\(stats.rushingYards)")
                }
            }
            .listRowBackground(Color.backgroundSecondary)

        case .DE, .DT, .OLB, .MLB:
            Section(title) {
                statRow("Tackles", value: "\(stats.tackles)")
                statRow("Sacks", value: String(format: "%.1f", stats.sacks), highlight: stats.sacks > 0)
                statRow("Forced Fumbles", value: "\(stats.forcedFumbles)")
                statRow("Interceptions", value: "\(stats.interceptionsCaught)", highlight: stats.interceptionsCaught > 0)
            }
            .listRowBackground(Color.backgroundSecondary)

        case .CB, .FS, .SS:
            Section(title) {
                statRow("Tackles", value: "\(stats.tackles)")
                statRow("Interceptions", value: "\(stats.interceptionsCaught)", highlight: stats.interceptionsCaught > 0)
                statRow("Sacks", value: String(format: "%.1f", stats.sacks))
                statRow("Forced Fumbles", value: "\(stats.forcedFumbles)")
            }
            .listRowBackground(Color.backgroundSecondary)

        case .K, .P:
            Section(title) {
                statRow("FG Made/Attempted", value: "\(stats.fieldGoalsMade)/\(stats.fieldGoalsAttempted)")
                if stats.fieldGoalsAttempted > 0 {
                    let pct = Double(stats.fieldGoalsMade) / Double(stats.fieldGoalsAttempted) * 100.0
                    statRow("FG %", value: String(format: "%.1f%%", pct))
                }
            }
            .listRowBackground(Color.backgroundSecondary)

        default:
            // OL and other positions
            Section(title) {
                statRow("Games Played", value: "\(gamesPlayed)")
                if stats.tackles > 0 {
                    statRow("Tackles", value: "\(stats.tackles)")
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    @ViewBuilder
    private func positionAveragesSection(stats: PlayerGameStats, gamesPlayed: Int) -> some View {
        let gp = max(1.0, Double(gamesPlayed))

        Section("Per Game Averages") {
            switch player.position {
            case .QB:
                statRow("Pass Yds/G", value: String(format: "%.1f", Double(stats.passingYards) / gp))
                statRow("Pass TDs/G", value: String(format: "%.1f", Double(stats.passingTDs) / gp))

            case .RB, .FB:
                statRow("Rush Yds/G", value: String(format: "%.1f", Double(stats.rushingYards) / gp))
                statRow("Rush TDs/G", value: String(format: "%.1f", Double(stats.rushingTDs) / gp))
                if stats.receptions > 0 {
                    statRow("Rec Yds/G", value: String(format: "%.1f", Double(stats.receivingYards) / gp))
                }

            case .WR, .TE:
                statRow("Rec Yds/G", value: String(format: "%.1f", Double(stats.receivingYards) / gp))
                statRow("Rec TDs/G", value: String(format: "%.1f", Double(stats.receivingTDs) / gp))
                statRow("Targets/G", value: String(format: "%.1f", Double(stats.targets) / gp))

            case .DE, .DT, .OLB, .MLB, .CB, .FS, .SS:
                statRow("Tackles/G", value: String(format: "%.1f", Double(stats.tackles) / gp))
                statRow("Sacks/G", value: String(format: "%.2f", stats.sacks / gp))

            case .K, .P:
                statRow("FG/G", value: String(format: "%.1f", Double(stats.fieldGoalsMade) / gp))

            default:
                EmptyView()
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Game Log Components

    @ViewBuilder
    private var gameLogHeader: some View {
        HStack(spacing: 0) {
            Text("WK")
                .frame(width: 28, alignment: .center)
            positionGameLogHeaders
            Spacer()
        }
        .font(.caption2)
        .fontWeight(.bold)
        .foregroundStyle(Color.textTertiary)
    }

    @ViewBuilder
    private var positionGameLogHeaders: some View {
        switch player.position {
        case .QB:
            Group {
                Text("CMP").frame(width: 36, alignment: .center)
                Text("ATT").frame(width: 36, alignment: .center)
                Text("YDS").frame(width: 44, alignment: .center)
                Text("TD").frame(width: 28, alignment: .center)
                Text("INT").frame(width: 28, alignment: .center)
                Text("RTG").frame(width: 44, alignment: .center)
            }
        case .RB, .FB:
            Group {
                Text("CAR").frame(width: 36, alignment: .center)
                Text("YDS").frame(width: 44, alignment: .center)
                Text("TD").frame(width: 28, alignment: .center)
                Text("REC").frame(width: 36, alignment: .center)
                Text("R-YD").frame(width: 44, alignment: .center)
            }
        case .WR, .TE:
            Group {
                Text("TGT").frame(width: 36, alignment: .center)
                Text("REC").frame(width: 36, alignment: .center)
                Text("YDS").frame(width: 44, alignment: .center)
                Text("TD").frame(width: 28, alignment: .center)
                Text("Y/R").frame(width: 40, alignment: .center)
            }
        case .DE, .DT, .OLB, .MLB, .CB, .FS, .SS:
            Group {
                Text("TKL").frame(width: 36, alignment: .center)
                Text("SCK").frame(width: 36, alignment: .center)
                Text("FF").frame(width: 28, alignment: .center)
                Text("INT").frame(width: 28, alignment: .center)
            }
        case .K, .P:
            Group {
                Text("FGM").frame(width: 36, alignment: .center)
                Text("FGA").frame(width: 36, alignment: .center)
                Text("FG%").frame(width: 44, alignment: .center)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func gameLogRow(week: Int, stats: PlayerGameStats) -> some View {
        HStack(spacing: 0) {
            Text("\(week)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Color.accentGold)
                .frame(width: 28, alignment: .center)

            positionGameLogValues(stats: stats)
            Spacer()
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(Color.textPrimary)
    }

    @ViewBuilder
    private func positionGameLogValues(stats: PlayerGameStats) -> some View {
        switch player.position {
        case .QB:
            Group {
                Text("\(stats.completions)").frame(width: 36, alignment: .center)
                Text("\(stats.attempts)").frame(width: 36, alignment: .center)
                Text("\(stats.passingYards)").frame(width: 44, alignment: .center)
                Text("\(stats.passingTDs)")
                    .foregroundStyle(stats.passingTDs > 0 ? Color.success : Color.textPrimary)
                    .frame(width: 28, alignment: .center)
                Text("\(stats.interceptions)")
                    .foregroundStyle(stats.interceptions > 0 ? Color.danger : Color.textPrimary)
                    .frame(width: 28, alignment: .center)
                Text(String(format: "%.1f", stats.passerRating))
                    .foregroundStyle(Color.forRating(Int(stats.passerRating / 1.583)))
                    .frame(width: 44, alignment: .center)
            }
        case .RB, .FB:
            Group {
                Text("\(stats.carries)").frame(width: 36, alignment: .center)
                Text("\(stats.rushingYards)").frame(width: 44, alignment: .center)
                Text("\(stats.rushingTDs)")
                    .foregroundStyle(stats.rushingTDs > 0 ? Color.success : Color.textPrimary)
                    .frame(width: 28, alignment: .center)
                Text("\(stats.receptions)").frame(width: 36, alignment: .center)
                Text("\(stats.receivingYards)").frame(width: 44, alignment: .center)
            }
        case .WR, .TE:
            Group {
                Text("\(stats.targets)").frame(width: 36, alignment: .center)
                Text("\(stats.receptions)").frame(width: 36, alignment: .center)
                Text("\(stats.receivingYards)").frame(width: 44, alignment: .center)
                Text("\(stats.receivingTDs)")
                    .foregroundStyle(stats.receivingTDs > 0 ? Color.success : Color.textPrimary)
                    .frame(width: 28, alignment: .center)
                Text(String(format: "%.1f", stats.yardsPerReception)).frame(width: 40, alignment: .center)
            }
        case .DE, .DT, .OLB, .MLB, .CB, .FS, .SS:
            Group {
                Text("\(stats.tackles)").frame(width: 36, alignment: .center)
                Text(String(format: "%.1f", stats.sacks)).frame(width: 36, alignment: .center)
                Text("\(stats.forcedFumbles)").frame(width: 28, alignment: .center)
                Text("\(stats.interceptionsCaught)")
                    .foregroundStyle(stats.interceptionsCaught > 0 ? Color.success : Color.textPrimary)
                    .frame(width: 28, alignment: .center)
            }
        case .K, .P:
            Group {
                Text("\(stats.fieldGoalsMade)").frame(width: 36, alignment: .center)
                Text("\(stats.fieldGoalsAttempted)").frame(width: 36, alignment: .center)
                if stats.fieldGoalsAttempted > 0 {
                    let pct = Double(stats.fieldGoalsMade) / Double(stats.fieldGoalsAttempted) * 100.0
                    Text(String(format: "%.0f%%", pct)).frame(width: 44, alignment: .center)
                } else {
                    Text("-").frame(width: 44, alignment: .center)
                }
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Shared Components

    private func statCircle(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 52, height: 52)
                Text(value)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func statRow(_ label: String, value: String, highlight: Bool = false, negative: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(
                    negative ? Color.danger :
                    highlight ? Color.success :
                    Color.textPrimary
                )
        }
    }

    // MARK: - Aggregation

    private func aggregatedStats(from games: [PlayerGameStats]) -> PlayerGameStats {
        var total = PlayerGameStats(
            playerID: player.id,
            playerName: player.fullName,
            position: player.position
        )
        for game in games {
            total.passingYards += game.passingYards
            total.passingTDs += game.passingTDs
            total.interceptions += game.interceptions
            total.completions += game.completions
            total.attempts += game.attempts
            total.rushingYards += game.rushingYards
            total.rushingTDs += game.rushingTDs
            total.carries += game.carries
            total.receivingYards += game.receivingYards
            total.receivingTDs += game.receivingTDs
            total.receptions += game.receptions
            total.targets += game.targets
            total.tackles += game.tackles
            total.sacks += game.sacks
            total.forcedFumbles += game.forcedFumbles
            total.interceptionsCaught += game.interceptionsCaught
            total.fieldGoalsMade += game.fieldGoalsMade
            total.fieldGoalsAttempted += game.fieldGoalsAttempted
        }
        return total
    }

    // MARK: - Form Indicator

    private var formIndicator: (symbol: String, color: Color) {
        playerFormIndicator(for: player)
    }
}

// MARK: - Stats Tab Enum

enum StatsTab: String, CaseIterable, Identifiable {
    case season, career, gameLog

    var id: String { rawValue }

    var label: String {
        switch self {
        case .season:  return "Season"
        case .career:  return "Career"
        case .gameLog: return "Game Log"
        }
    }
}

// MARK: - Form Indicator Helper (shared)

/// Calculates a form/momentum indicator for a player based on morale and development phase.
/// Returns a symbol and color representing hot, steady, or cold form.
func playerFormIndicator(for player: Player) -> (symbol: String, color: Color) {
    // Use morale as primary form proxy
    let peak = player.position.peakAgeRange
    let developmentBonus: Int
    if player.age < peak.lowerBound {
        developmentBonus = 5  // Young players trending up
    } else if peak.contains(player.age) {
        developmentBonus = 3  // Prime players consistent
    } else {
        developmentBonus = -5 // Aging players trending down
    }

    let effectiveMorale = player.morale + developmentBonus
    let injuryPenalty = player.isInjured ? -15 : 0
    let formScore = effectiveMorale + injuryPenalty

    switch formScore {
    case 80...:
        return ("\u{2191}", .success)      // up arrow - hot
    case 60..<80:
        return ("\u{2192}", .accentGold)   // right arrow - steady
    default:
        return ("\u{2193}", .danger)       // down arrow - cold
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlayerStatsView(
            player: Player(
                firstName: "Patrick",
                lastName: "Mahomes",
                position: .QB,
                age: 28,
                yearsPro: 7,
                positionAttributes: .quarterback(QBAttributes(
                    armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                    accuracyDeep: 87, pocketPresence: 92, scrambling: 80
                )),
                personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                morale: 90, contractYearsRemaining: 3, annualSalary: 45000
            ),
            seasonStats: [
                PlayerGameStats(
                    playerID: UUID(), playerName: "Patrick Mahomes", position: .QB,
                    passingYards: 312, passingTDs: 3, interceptions: 1,
                    completions: 24, attempts: 35
                ),
                PlayerGameStats(
                    playerID: UUID(), playerName: "Patrick Mahomes", position: .QB,
                    passingYards: 289, passingTDs: 2, interceptions: 0,
                    completions: 22, attempts: 30, rushingYards: 18, carries: 3
                ),
            ]
        )
    }
}
