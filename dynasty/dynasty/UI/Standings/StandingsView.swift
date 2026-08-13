import SwiftUI
import SwiftData

struct StandingsView: View {

    let career: Career

    @Query private var allTeamsUnscoped: [Team]
    @Query private var allGamesUnscoped: [Game]

    // `@Query` cannot take a runtime predicate built from a stored property,
    // so the store-wide result is narrowed to THIS save here. Without it the
    // screen mixes two careers' populations into one list.
    private var allTeams: [Team] { allTeamsUnscoped.filter { $0.careerID == career.id } }
    private var allGames: [Game] { allGamesUnscoped.filter { $0.careerID == career.id } }

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

    /// Current run of results per team, e.g. `W3` / `L2` / `T1`.
    ///
    /// `StandingsRecord` stores no streak, but the games it is aggregated from
    /// do — and this uses the identical filter (`isPlayed && !isPlayoff`) the
    /// calculator uses, so STRK can never contradict the W-L-T beside it.
    private var streaks: [UUID: String] {
        var byTeam: [UUID: [(week: Int, outcome: Character)]] = [:]

        for game in seasonGames where game.isPlayed && !game.isPlayoff {
            guard let home = game.homeScore, let away = game.awayScore else { continue }
            let homeOutcome: Character = home > away ? "W" : (home < away ? "L" : "T")
            let awayOutcome: Character = home > away ? "L" : (home < away ? "W" : "T")
            byTeam[game.homeTeamID, default: []].append((game.week, homeOutcome))
            byTeam[game.awayTeamID, default: []].append((game.week, awayOutcome))
        }

        return byTeam.compactMapValues { results in
            let ordered = results.sorted { $0.week > $1.week }
            guard let latest = ordered.first?.outcome else { return nil }
            let run = ordered.prefix(while: { $0.outcome == latest }).count
            return "\(latest)\(run)"
        }
    }

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
                    // Same 800pt measure as the division tables below, so the
                    // picker's edges line up with the cards instead of running
                    // the full iPad width while the content sits inset.
                    .frame(maxWidth: DSLayout.wideMeasure)
                    .frame(maxWidth: .infinity)
                    .background(Color.backgroundSecondary)

                if allTeams.isEmpty {
                    emptyLeagueState
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            wildCardRaceBanner

                            // Derived once per render, not once per division.
                            let streaksByTeam = streaks

                            ForEach(Division.allCases, id: \.self) { division in
                                DivisionStandingsSection(
                                    conference: selectedConference,
                                    division: division,
                                    records: allRecords,
                                    teams: allTeams,
                                    playerTeamID: playerTeamID,
                                    conferenceRankings: conferenceRankings[selectedConference] ?? [],
                                    streaks: streaksByTeam,
                                    onTapRow: { detail in selectedRowDetail = detail }
                                )
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: DSLayout.wideMeasure)
                        .frame(maxWidth: .infinity)
                    }
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
        // Palette comes from DSAppearance.apply() at launch — setting the
        // appearance proxy from here (.onAppear) ran a frame too late and the
        // picker rendered in stock grey.
    }

    // MARK: - Empty State

    /// The one condition under which this screen has nothing to rank: no league
    /// in the save. `DSEmptyState` (§2.7) rather than a bare label, because the
    /// third beat — what would fill this — is the only useful thing to say here.
    private var emptyLeagueState: some View {
        VStack {
            Spacer(minLength: 0)
            DSEmptyState(
                density: .scan,
                icon: "tablecells",
                title: "No Standings Yet",
                message: "This save has no league loaded, so there is nothing to rank. Once a season starts, every division fills in after week one."
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .font(DSType.display(12, .heavy))
                        .tracking(0.8)
                        .foregroundStyle(info.tint)
                    Text(info.subtitle)
                        .font(DSType.text(12, .regular, prose: true))
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
    /// `teamID` → current streak string (`W3`), built once by the parent.
    let streaks: [UUID: String]
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
                    streak: streaks[record.teamID],
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

    /// Wave 1b: the division head is `DSGroupRollup` — the same object the Big
    /// Board's tier header and the roster's position group will use, so a
    /// division here and a tier there read at one weight (§2.2). The
    /// "tap for tiebreakers" hint becomes a rollup fact instead of a 9 pt
    /// label, which was three steps under the display floor.
    private var sectionHeader: some View {
        DSGroupRollup(
            title: "\(conference.rawValue) \(division.rawValue)",
            facts: ["Tap a row for tiebreakers"]
        )
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(Color.backgroundTertiary.opacity(0.6))
    }
}

// MARK: - Standings Column Widths

/// Shared column widths so the header and the rows can't drift apart.
///
/// Wave 1b re-bases them onto `DSListColumn` (`UI/Common/DSListRow.swift`) —
/// the same move `PlayerRowView.Column` made — so the standings table, the
/// roster and the Big Board read ONE ladder instead of three that happen to
/// agree. The names stay: a call site still asks for `pct`, not for `label`.
///
/// Total fixed width = 398 pt. With the row's leading slots (rank 24 + team
/// badge 36 + identity gap 6) and the 80 pt identity floor that is 544 pt
/// inside a table that caps at `DSLayout.wideMeasure`, so TEAM keeps every
/// remaining point.
private enum StandingsColumn {
    /// The playoff-seed pill, "#12" at most.
    static let seed   = DSListColumn.ovr        // 40
    static let wlt    = DSListColumn.tight      // 30
    static let pct    = DSListColumn.label      // 48
    /// Holds "2-1" and, in a tie year, "2-1-1".
    static let record = DSListColumn.tape       // 42
    /// The streak pill, "W3".
    static let streak = DSListColumn.attribute  // 34
    static let points = DSListColumn.attribute  // 34
    static let diff   = DSListColumn.value      // 34
}

// MARK: - Standings Header Row

/// Built from `DSListHeaderRow`, which reserves the SAME leading slots the row
/// mounts — rank gutter, team badge, no portrait — so the labels cannot end up
/// one column left of the numbers they describe (§2.2, the bug this component
/// exists to prevent, already documented twice in this codebase).
private struct StandingsHeaderRow: View {
    var body: some View {
        DSListHeaderRow(
            density: .scan,
            reservesRank: true,
            rankLabel: "#",
            reservesBadge: true,
            badgeLabel: "TM",
            // No faces on a standings table; the badge is the club.
            portraitWidth: 0,
            identityLabel: "TEAM"
        ) {
            Spacer(minLength: DSSpacing.xxs)
            // The old "CONF" header sat over a `#4` badge — that is a seed,
            // not a conference record, and it occupied the name a real
            // standings table needs for the conference W-L.
            DSColumnHeader("SEED", width: StandingsColumn.seed)
            DSColumnHeader("W",    width: StandingsColumn.wlt)
            DSColumnHeader("L",    width: StandingsColumn.wlt)
            DSColumnHeader("T",    width: StandingsColumn.wlt)
            DSColumnHeader("PCT",  width: StandingsColumn.pct)
            // Division and conference records decide seeding before point
            // differential does; both already lived in `StandingsRecord`,
            // visible only after tapping through to the tiebreaker sheet.
            DSColumnHeader("DIV",  width: StandingsColumn.record)
            DSColumnHeader("CONF", width: StandingsColumn.record)
            DSColumnHeader("STRK", width: StandingsColumn.streak)
            DSColumnHeader("PF",   width: StandingsColumn.points)
            DSColumnHeader("PA",   width: StandingsColumn.points)
            DSColumnHeader("DIFF", width: StandingsColumn.diff)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
    }
}

// MARK: - Standings Team Row

private struct StandingsTeamRow: View {
    let record: StandingsRecord
    let team: Team?
    let divisionRank: Int
    let conferenceRank: Int?
    /// `W3` / `L2` / `T1`, or nil before the team has played.
    let streak: String?
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

    private var divisionRecord: String {
        record.divisionTies > 0
            ? "\(record.divisionWins)-\(record.divisionLosses)-\(record.divisionTies)"
            : "\(record.divisionWins)-\(record.divisionLosses)"
    }

    private var conferenceRecord: String {
        record.conferenceTies > 0
            ? "\(record.conferenceWins)-\(record.conferenceLosses)-\(record.conferenceTies)"
            : "\(record.conferenceWins)-\(record.conferenceLosses)"
    }

    /// The seed pill's tone. THREE states, not four colours: in the field,
    /// on the bubble, out. The old ladder painted seeds 1–4 gold, which is a
    /// fourth job for gold (P7) AND a duplicate of the fact the rank slot
    /// already carries — a division leader is the row whose `#` is gold.
    private func seedTone(_ seed: Int) -> DSStatusPill.Tone {
        switch seed {
        case 1...7:  return .ok      // in the playoff field
        case 8...10: return .warn    // on the bubble
        default:     return .neutral // out, as things stand
        }
    }

    /// Green while winning, red while losing — the streak is the one column
    /// here that describes momentum rather than the season total.
    private var streakTone: DSStatusPill.Tone {
        guard let kind = streak?.first else { return .neutral }
        switch kind {
        case "W": return .ok
        case "L": return .bad
        default:  return .neutral
        }
    }

    /// Wave 1b: `DSListRow` at `scan` density (§2.2/§2.12), so a standings row
    /// is 44 pt like every other row in the app instead of the ~42 this table
    /// happened to measure.
    ///
    /// What moved, and nothing else:
    ///
    ///  1. The hand-drawn rank/crown became the reserved `DSRankSlot`, which is
    ///     a fixed two-row box — the crown and the digit were different heights
    ///     and swapped per row.
    ///  2. The 42 pt abbreviation cell became the row's BADGE slot, in the
    ///     club's colour, which is the same slot the roster gives the position.
    ///  3. Seed and streak became `DSStatusPill`s: both are states, and the
    ///     unset case (a club that has not played) is now a dashed, dimmed
    ///     marker holding its column rather than a bare em dash.
    ///  4. Every cell goes through `dsColumn`, which shrinks then clips.
    var body: some View {
        DSListRow(
            density: .scan,
            rank: DSRank(value: divisionRank, tint: isLeader ? Color.accentGold : nil),
            badge: DSRowBadge(
                text: team?.abbreviation ?? "???",
                tint: TeamColors.color(for: team?.abbreviation ?? ""),
                accessibilityLabel: team?.fullName ?? "Unknown team"
            ),
            portraitWidth: 0
        ) {
            EmptyView()
        } identity: {
            identityBlock
        } columns: {
            Spacer(minLength: DSSpacing.xxs)

            seedCell
            statCell("\(record.wins)",   width: StandingsColumn.wlt, color: Color.textPrimary)
            statCell("\(record.losses)", width: StandingsColumn.wlt, color: Color.textPrimary)
            statCell("\(record.ties)",   width: StandingsColumn.wlt, color: Color.textSecondary)
            statCell(pctFormatted,       width: StandingsColumn.pct, color: Color.textPrimary)
            recordCell(divisionRecord)
            recordCell(conferenceRecord)
            streakCell
            statCell("\(record.pointsFor)",     width: StandingsColumn.points, color: Color.textSecondary)
            statCell("\(record.pointsAgainst)", width: StandingsColumn.points, color: Color.textSecondary)
            statCell(diffFormatted,             width: StandingsColumn.diff,   color: diffColor)
        }
        .padding(.horizontal, DSSpacing.md)
        .background(
            isPlayerTeam
                ? Color.accentGold.opacity(0.07)
                : Color.clear
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    /// The one flexible column: the club, and whether it is yours.
    ///
    /// The team column ran ~600 pt wide holding a 3-letter code and nothing
    /// else. The full name fills that void and saves the reader translating
    /// "LAC" in their head; the abbreviation moved to the badge slot.
    private var identityBlock: some View {
        HStack(spacing: DSSpacing.xxs) {
            Text(team?.fullName ?? "Unknown")
                .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            if isPlayerTeam {
                DSStatusPill(label: "You", tone: .info, showsDot: false,
                             spokenLabel: "Your team")
            }
        }
    }

    private var seedCell: some View {
        Group {
            if let r = conferenceRank {
                DSStatusPill(label: "#\(r)", tone: seedTone(r), showsDot: false,
                             spokenLabel: "Conference seed \(r)")
            } else {
                DSStatusPill(label: "\u{2014}", tone: .empty, showsDot: false,
                             spokenLabel: "Not seeded yet")
            }
        }
        .dsColumn(StandingsColumn.seed)
    }

    private func statCell(_ value: String, width: CGFloat, color: Color) -> some View {
        Text(value)
            .font(DSType.display(13, .semibold))
            .foregroundStyle(color)
            .dsColumn(width)
    }

    /// Sub-records ride one step below the headline W-L-T: same column rhythm,
    /// lighter weight, so the eye still lands on the overall record first.
    private func recordCell(_ value: String) -> some View {
        Text(value)
            .font(DSType.display(12, .medium))
            .foregroundStyle(Color.textSecondary)
            .dsColumn(StandingsColumn.record)
    }

    private var streakCell: some View {
        Group {
            if let streak {
                DSStatusPill(label: streak, tone: streakTone, showsDot: false,
                             spokenLabel: "Streak \(streak)")
            } else {
                DSStatusPill(label: "\u{2014}", tone: .empty, showsDot: false,
                             spokenLabel: "No games played yet")
            }
        }
        .dsColumn(StandingsColumn.streak)
    }

    private var rowAccessibilityLabel: String {
        let name = team?.fullName ?? "Unknown team"
        let seedPart = conferenceRank.map { ", conference seed \($0)" } ?? ""
        let streakPart = streak.map { ", streak \($0)" } ?? ""
        return "\(name), division rank \(divisionRank)\(seedPart), " +
               "\(record.wins) wins, \(record.losses) losses, \(record.ties) ties, " +
               "division \(divisionRecord), conference \(conferenceRecord)\(streakPart), " +
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
                .font(.system(size: DSType.Size.title2, weight: .heavy))
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
                // "SEED", matching the table column — the table's DIV/CONF now
                // mean division/conference *records*, so a `#4` under a "CONF"
                // heading would read as a 4-something record here.
                rankBadge(label: "SEED", value: "#\(r)", tint: confRankColor(r))
            }
        }
    }

    /// P7 rule 2 names a seed as the textbook thing that gets NO rating
    /// colour — a #4 is not "a 4 out of 16". What a seed does carry is one
    /// stated threshold, and it is the only one the league actually enforces:
    /// `StandingsCalculator.playoffTeams` takes the top **7**.
    ///
    /// So: in the field, in the hunt, out. The four-band version this replaces
    /// split 1–4 from 5–7 with `accentGold`, which invented a "hosting a game"
    /// tier the bracket does not have (only the #1 seed gets a bye) and spent
    /// the hue P7 reserves for "primary/current" doing it.
    private func confRankColor(_ rank: Int) -> Color {
        if rank <= 7  { return .forStatus(.ok) }    // in the playoff field
        if rank <= 10 { return .forStatus(.warn) }  // in the hunt
        return Color.textTertiary                   // out
    }

    private func rankBadge(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: DSType.Size.caption, weight: .bold))
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
                    .font(.system(size: DSType.Size.body, weight: .semibold))
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
