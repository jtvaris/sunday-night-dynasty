import SwiftUI
import SwiftData

struct StandingsView: View {

    let career: Career

    @Query private var allTeams: [Team]
    @Query private var allGames: [Game]

    @State private var selectedConference: Conference = .AFC

    // MARK: - Derived

    private var seasonGames: [Game] {
        allGames.filter { $0.seasonYear == career.currentSeason }
    }

    private var allRecords: [StandingsRecord] {
        StandingsCalculator.calculate(games: seasonGames, teams: allTeams)
    }

    private var playerTeamID: UUID? { career.teamID }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                conferencePicker
                    .padding(16)
                    .background(Color.backgroundSecondary)

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(Division.allCases, id: \.self) { division in
                            DivisionStandingsSection(
                                conference: selectedConference,
                                division: division,
                                records: allRecords,
                                teams: allTeams,
                                playerTeamID: playerTeamID
                            )
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 800)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Standings")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Conference Picker

    private var conferencePicker: some View {
        Picker("Conference", selection: $selectedConference) {
            ForEach(Conference.allCases, id: \.self) { conf in
                Text(conf.rawValue).tag(conf)
            }
        }
        .pickerStyle(.segmented)
        .tint(Color.accentGold)
        // Force gold selection tint via UISegmentedControl appearance
        .onAppear { applyGoldSegmentAppearance() }
    }

    private func applyGoldSegmentAppearance() {
        let gold = UIColor(Color.accentGold)
        let navy = UIColor(Color.backgroundPrimary)
        UISegmentedControl.appearance().selectedSegmentTintColor = gold
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: navy],
            for: .selected
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor(Color.textSecondary)],
            for: .normal
        )
    }
}

// MARK: - Division Standings Section

private struct DivisionStandingsSection: View {
    let conference: Conference
    let division: Division
    let records: [StandingsRecord]
    let teams: [Team]
    let playerTeamID: UUID?

    private var sortedRecords: [StandingsRecord] {
        StandingsCalculator.divisionStandings(
            records: records,
            teams: teams,
            conference: conference,
            division: division
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            sectionHeader

            // Column header
            StandingsHeaderRow()

            Divider()
                .overlay(Color.surfaceBorder)

            // Team rows
            ForEach(Array(sortedRecords.enumerated()), id: \.element.id) { index, record in
                let team = teams.first { $0.id == record.teamID }
                let isLeader = index == 0
                let isPlayerTeam = record.teamID == playerTeamID

                StandingsTeamRow(
                    record: record,
                    team: team,
                    isLeader: isLeader,
                    isPlayerTeam: isPlayerTeam
                )

                if index < sortedRecords.count - 1 {
                    Divider()
                        .overlay(Color.surfaceBorder.opacity(0.5))
                        .padding(.horizontal, 16)
                }
            }
        }
        .cardBackground()
    }

    private var sectionHeader: some View {
        HStack {
            Text("\(conference.rawValue) \(division.rawValue.uppercased())")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.accentGold)
                .tracking(1.5)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.backgroundTertiary.opacity(0.6))
    }
}

// MARK: - Standings Header Row

private struct StandingsHeaderRow: View {
    var body: some View {
        HStack(spacing: 0) {
            // Team column
            Text("TEAM")
                .frame(maxWidth: .infinity, alignment: .leading)

            columnHeader("W",    width: 36)
            columnHeader("L",    width: 36)
            columnHeader("T",    width: 36)
            columnHeader("PCT",  width: 52)
            columnHeader("PF",   width: 52)
            columnHeader("PA",   width: 52)
            columnHeader("DIFF", width: 52)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.textTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .tracking(0.5)
    }

    private func columnHeader(_ label: String, width: CGFloat) -> some View {
        Text(label)
            .frame(width: width, alignment: .trailing)
    }
}

// MARK: - Standings Team Row

private struct StandingsTeamRow: View {
    let record: StandingsRecord
    let team: Team?
    let isLeader: Bool
    let isPlayerTeam: Bool

    private var diffColor: Color {
        if record.pointDifferential > 0 { return Color.success }
        if record.pointDifferential < 0 { return Color.danger }
        return Color.textSecondary
    }

    private var pctFormatted: String {
        let pct = record.winPercentage
        if pct == 1.0 { return "1.000" }
        return String(format: ".%03d", Int((pct * 1000).rounded()))
    }

    private var diffFormatted: String {
        let d = record.pointDifferential
        if d > 0 { return "+\(d)" }
        return "\(d)"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Team name column
            HStack(spacing: 8) {
                if isLeader {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentGold)
                        .frame(width: 12)
                } else {
                    Spacer()
                        .frame(width: 12)
                }

                Text(team?.abbreviation ?? "???")
                    .font(.system(size: 14, weight: isLeader ? .heavy : .semibold))
                    .foregroundStyle(isLeader ? Color.accentGold : Color.textPrimary)

                if isPlayerTeam {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentGold.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Stats columns
            statCell("\(record.wins)",        width: 36, color: Color.textPrimary)
            statCell("\(record.losses)",      width: 36, color: Color.textPrimary)
            statCell("\(record.ties)",        width: 36, color: Color.textSecondary)
            statCell(pctFormatted,            width: 52, color: Color.textPrimary)
            statCell("\(record.pointsFor)",   width: 52, color: Color.textSecondary)
            statCell("\(record.pointsAgainst)", width: 52, color: Color.textSecondary)
            statCell(diffFormatted,           width: 52, color: diffColor)
        }
        .font(.system(size: 14).monospacedDigit())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            isPlayerTeam
                ? Color.accentGold.opacity(0.07)
                : Color.clear
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private func statCell(_ value: String, width: CGFloat, color: Color) -> some View {
        Text(value)
            .foregroundStyle(color)
            .frame(width: width, alignment: .trailing)
    }

    private var rowAccessibilityLabel: String {
        let name = team?.fullName ?? "Unknown team"
        return "\(name), \(record.wins) wins, \(record.losses) losses, \(record.ties) ties, " +
               "\(record.pointsFor) points for, \(record.pointsAgainst) points against"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        StandingsView(career: Career(
            playerName: "Coach Smith",
            role: .gmAndHeadCoach,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Team.self, Game.self], inMemory: true)
}
