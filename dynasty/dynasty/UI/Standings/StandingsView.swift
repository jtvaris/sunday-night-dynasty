import SwiftUI
import SwiftData

struct StandingsView: View {

    let career: Career

    @Query private var allTeams: [Team]
    @Query private var allGames: [Game]

    @State private var selectedConference: Conference = .AFC
    @State private var selectedRowDetail: StandingsRowDetail?

    // MARK: - Derived

    private var seasonGames: [Game] {
        allGames.filter { $0.seasonYear == career.currentSeason }
    }

    private var allRecords: [StandingsRecord] {
        StandingsCalculator.calculate(games: seasonGames, teams: allTeams)
    }

    private var playerTeamID: UUID? { career.teamID }

    /// Conference standings keyed by team for quick conference-rank lookup.
    private var conferenceRankings: [Conference: [UUID]] {
        var result: [Conference: [UUID]] = [:]
        for conf in Conference.allCases {
            result[conf] = StandingsCalculator
                .conferenceStandings(records: allRecords, teams: allTeams, conference: conf)
                .map(\.teamID)
        }
        return result
    }

    /// Player team ranks: division and conference (1-based). Returns nil if not applicable.
    private var playerRanks: (division: Int, conference: Int)? {
        guard let pid = playerTeamID,
              let team = allTeams.first(where: { $0.id == pid }) else { return nil }
        let divStandings = StandingsCalculator.divisionStandings(
            records: allRecords,
            teams: allTeams,
            conference: team.conference,
            division: team.division
        )
        guard let divIdx = divStandings.firstIndex(where: { $0.teamID == pid }) else { return nil }
        let confList = conferenceRankings[team.conference] ?? []
        guard let confIdx = confList.firstIndex(of: pid) else { return nil }
        return (divIdx + 1, confIdx + 1)
    }

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
                        wildCardRaceBanner

                        ForEach(Division.allCases, id: \.self) { division in
                            DivisionStandingsSection(
                                conference: selectedConference,
                                division: division,
                                records: allRecords,
                                teams: allTeams,
                                playerTeamID: playerTeamID,
                                conferenceRankings: conferenceRankings[selectedConference] ?? [],
                                onTapRow: { detail in selectedRowDetail = detail }
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
        .sheet(item: $selectedRowDetail) { detail in
            StandingsRowDetailSheet(detail: detail)
        }
    }

    // MARK: - Conference Picker

    private var conferencePicker: some View {
        Picker("Conference", selection: $selectedConference) {
            ForEach(Conference.allCases, id: \.self) { conf in
                Text(conf.rawValue).tag(conf)
            }
        }
        .pickerStyle(.segmented)
        .tint(Color.accentBlue)
        // Force tab-style selection tint via UISegmentedControl appearance
        .onAppear { applySegmentAppearance() }
    }

    private func applySegmentAppearance() {
        let blue = UIColor(Color.accentBlue)
        let navy = UIColor(Color.backgroundPrimary)
        UISegmentedControl.appearance().selectedSegmentTintColor = blue
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: navy],
            for: .selected
        )
        UISegmentedControl.appearance().setTitleTextAttributes(
            [.foregroundColor: UIColor(Color.textSecondary)],
            for: .normal
        )
    }

    // MARK: - Wild Card Race Banner

    /// Shows a banner highlighting the player team's wild-card situation when relevant.
    @ViewBuilder
    private var wildCardRaceBanner: some View {
        if let pid = playerTeamID,
           let team = allTeams.first(where: { $0.id == pid }),
           team.conference == selectedConference,
           let info = wildCardInfo(forPlayerTeam: team) {

            HStack(spacing: 10) {
                Image(systemName: info.iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(info.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title)
                        .font(.system(size: 12, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(info.tint)
                    Text(info.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(info.tint.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(info.tint.opacity(0.4), lineWidth: 1)
                    )
            )
        }
    }

    private struct WildCardInfo {
        let title: String
        let subtitle: String
        let iconName: String
        let tint: Color
    }

    /// Returns a wild-card info struct when the player team is in or near the wild-card race.
    private func wildCardInfo(forPlayerTeam team: Team) -> WildCardInfo? {
        let confStandings = StandingsCalculator.conferenceStandings(
            records: allRecords,
            teams: allTeams,
            conference: team.conference
        )
        guard let pid = playerTeamID,
              let seedIdx = confStandings.firstIndex(where: { $0.teamID == pid }) else { return nil }
        let seed = seedIdx + 1

        // Skip if already a division leader (top 4) — those aren't wild cards.
        let divStandings = StandingsCalculator.divisionStandings(
            records: allRecords,
            teams: allTeams,
            conference: team.conference,
            division: team.division
        )
        let isDivisionLeader = divStandings.first?.teamID == pid

        // Total games played: only show if there's at least 4 games of context.
        let pRec = allRecords.first { $0.teamID == pid }
        let played = (pRec?.wins ?? 0) + (pRec?.losses ?? 0) + (pRec?.ties ?? 0)
        guard played >= 4 else { return nil }

        if isDivisionLeader {
            return WildCardInfo(
                title: "DIVISION LEADER",
                subtitle: "Currently the #\(seed) seed in the \(team.conference.rawValue).",
                iconName: "crown.fill",
                tint: Color.accentGold
            )
        }

        switch seed {
        case 5...7:
            return WildCardInfo(
                title: "IN THE WILD-CARD HUNT",
                subtitle: "Currently holding the #\(seed) seed in the \(team.conference.rawValue).",
                iconName: "flag.checkered",
                tint: Color.success
            )
        case 8...10:
            // Compute games behind seed 7
            let cutoffRec = confStandings.indices.contains(6) ? confStandings[6] : nil
            let gb = gamesBehind(team: pRec, leader: cutoffRec)
            let gbText = gb.map { "\(formatGB($0)) GB" } ?? "in the mix"
            return WildCardInfo(
                title: "ON THE BUBBLE",
                subtitle: "#\(seed) seed, \(gbText) of the final wild card.",
                iconName: "exclamationmark.triangle.fill",
                tint: Color.warning
            )
        default:
            return nil
        }
    }

    private func gamesBehind(team: StandingsRecord?, leader: StandingsRecord?) -> Double? {
        guard let team, let leader else { return nil }
        let lead = (Double(leader.wins) - Double(team.wins) + Double(team.losses) - Double(leader.losses)) / 2.0
        return max(lead, 0)
    }

    private func formatGB(_ value: Double) -> String {
        if value == 0 { return "0" }
        if value == value.rounded() { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }
}

// MARK: - Standings Row Detail

struct StandingsRowDetail: Identifiable {
    let id = UUID()
    let teamName: String
    let teamAbbr: String
    let record: StandingsRecord
    let conferenceRank: Int?
    let divisionRank: Int
}

// MARK: - Division Standings Section

private struct DivisionStandingsSection: View {
    let conference: Conference
    let division: Division
    let records: [StandingsRecord]
    let teams: [Team]
    let playerTeamID: UUID?
    let conferenceRankings: [UUID]
    let onTapRow: (StandingsRowDetail) -> Void

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
                let confRank = conferenceRankings.firstIndex(of: record.teamID).map { $0 + 1 }

                StandingsTeamRow(
                    record: record,
                    team: team,
                    divisionRank: index + 1,
                    conferenceRank: confRank,
                    isLeader: isLeader,
                    isPlayerTeam: isPlayerTeam
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    onTapRow(
                        StandingsRowDetail(
                            teamName: team?.fullName ?? "Unknown",
                            teamAbbr: team?.abbreviation ?? "???",
                            record: record,
                            conferenceRank: confRank,
                            divisionRank: index + 1
                        )
                    )
                }

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
                .foregroundStyle(Color.textSecondary)
                .tracking(1.5)
            Spacer()
            Text("TAP FOR TIEBREAKERS")
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color.textTertiary)
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

            columnHeader("CONF", width: 44)
            columnHeader("W",    width: 32)
            columnHeader("L",    width: 32)
            columnHeader("T",    width: 32)
            columnHeader("PCT",  width: 48)
            columnHeader("PF",   width: 48)
            columnHeader("PA",   width: 48)
            columnHeader("DIFF", width: 48)
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
    let divisionRank: Int
    let conferenceRank: Int?
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

    /// Conference rank badge — color-coded by playoff seeding.
    private var confRankColor: Color {
        guard let r = conferenceRank else { return Color.textTertiary }
        switch r {
        case 1...4:  return Color.accentGold     // division winners
        case 5...7:  return Color.success        // wild-card seeds
        case 8...10: return Color.warning        // bubble
        default:     return Color.textTertiary
        }
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
                    Text("\(divisionRank)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
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

            // Conference rank cell
            confRankCell

            // Stats columns
            statCell("\(record.wins)",        width: 32, color: Color.textPrimary)
            statCell("\(record.losses)",      width: 32, color: Color.textPrimary)
            statCell("\(record.ties)",        width: 32, color: Color.textSecondary)
            statCell(pctFormatted,            width: 48, color: Color.textPrimary)
            statCell("\(record.pointsFor)",   width: 48, color: Color.textSecondary)
            statCell("\(record.pointsAgainst)", width: 48, color: Color.textSecondary)
            statCell(diffFormatted,           width: 48, color: diffColor)
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

    private var confRankCell: some View {
        Group {
            if let r = conferenceRank {
                Text("#\(r)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(confRankColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(confRankColor.opacity(0.15))
                    )
            } else {
                Text("—")
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(width: 44, alignment: .trailing)
    }

    private func statCell(_ value: String, width: CGFloat, color: Color) -> some View {
        Text(value)
            .foregroundStyle(color)
            .frame(width: width, alignment: .trailing)
    }

    private var rowAccessibilityLabel: String {
        let name = team?.fullName ?? "Unknown team"
        let confPart = conferenceRank.map { ", conference rank \($0)" } ?? ""
        return "\(name), division rank \(divisionRank)\(confPart), \(record.wins) wins, \(record.losses) losses, \(record.ties) ties, " +
               "\(record.pointsFor) points for, \(record.pointsAgainst) points against"
    }
}

// MARK: - Tiebreaker Detail Sheet

private struct StandingsRowDetailSheet: View {
    let detail: StandingsRowDetail

    @Environment(\.dismiss) private var dismiss

    private var record: StandingsRecord { detail.record }

    private var pctFormatted: String {
        let pct = record.winPercentage
        if pct == 1.0 { return "1.000" }
        return String(format: ".%03d", Int((pct * 1000).rounded()))
    }

    private func pctString(_ pct: Double) -> String {
        if pct == 1.0 { return "1.000" }
        return String(format: ".%03d", Int((pct * 1000).rounded()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerRow
                    rankRow

                    sectionLabel("TIEBREAKERS")
                    tiebreakerCard

                    sectionLabel("SCORING")
                    scoringCard
                }
                .padding(20)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle(detail.teamAbbr)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var headerRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(detail.teamName)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Color.textPrimary)
            Text(recordString)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var recordString: String {
        if record.ties > 0 { return "\(record.wins)-\(record.losses)-\(record.ties) (\(pctFormatted))" }
        return "\(record.wins)-\(record.losses) (\(pctFormatted))"
    }

    private var rankRow: some View {
        HStack(spacing: 10) {
            rankBadge(label: "DIV", value: "#\(detail.divisionRank)", tint: Color.accentBlue)
            if let r = detail.conferenceRank {
                rankBadge(label: "CONF", value: "#\(r)", tint: confRankColor(r))
            }
        }
    }

    private func confRankColor(_ rank: Int) -> Color {
        switch rank {
        case 1...4:  return Color.accentGold
        case 5...7:  return Color.success
        case 8...10: return Color.warning
        default:     return Color.textTertiary
        }
    }

    private func rankBadge(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy).monospacedDigit())
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.4), lineWidth: 1))
        )
    }

    private var tiebreakerCard: some View {
        VStack(spacing: 0) {
            tiebreakerRow(
                rank: 1,
                title: "Overall Win %",
                value: pctString(record.winPercentage)
            )
            divider
            tiebreakerRow(
                rank: 2,
                title: "Division Win %",
                value: pctString(record.divisionWinPercentage),
                detail: record.divisionTies > 0
                    ? "\(record.divisionWins)-\(record.divisionLosses)-\(record.divisionTies)"
                    : "\(record.divisionWins)-\(record.divisionLosses)"
            )
            divider
            tiebreakerRow(
                rank: 3,
                title: "Conference Win %",
                value: pctString(record.conferenceWinPercentage),
                detail: record.conferenceTies > 0
                    ? "\(record.conferenceWins)-\(record.conferenceLosses)-\(record.conferenceTies)"
                    : "\(record.conferenceWins)-\(record.conferenceLosses)"
            )
            divider
            tiebreakerRow(
                rank: 4,
                title: "Point Differential",
                value: record.pointDifferential >= 0 ? "+\(record.pointDifferential)" : "\(record.pointDifferential)"
            )
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.backgroundSecondary)
        )
    }

    private var divider: some View {
        Divider().overlay(Color.surfaceBorder.opacity(0.5)).padding(.horizontal, 12)
    }

    private func tiebreakerRow(rank: Int, title: String, value: String, detail: String? = nil) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.backgroundTertiary))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var scoringCard: some View {
        HStack(spacing: 0) {
            scoringStat(label: "PF", value: "\(record.pointsFor)", color: Color.textPrimary)
            divVertical
            scoringStat(label: "PA", value: "\(record.pointsAgainst)", color: Color.textSecondary)
            divVertical
            scoringStat(
                label: "DIFF",
                value: record.pointDifferential >= 0 ? "+\(record.pointDifferential)" : "\(record.pointDifferential)",
                color: record.pointDifferential > 0 ? Color.success
                    : record.pointDifferential < 0 ? Color.danger
                    : Color.textSecondary
            )
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Color.backgroundSecondary)
        )
    }

    private var divVertical: some View {
        Rectangle().fill(Color.surfaceBorder.opacity(0.4)).frame(width: 1, height: 32)
    }

    private func scoringStat(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .heavy).monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(Color.textTertiary)
            .padding(.top, 4)
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
