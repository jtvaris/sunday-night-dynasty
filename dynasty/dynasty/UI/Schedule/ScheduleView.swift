import SwiftUI
import SwiftData

/// Shared team-strength helper for matchup display.
///
/// Averaging the *entire* roster (incl. deep bench / practice squad) collapses
/// every team to ~70 OVR, so the color thresholds never fire and the badge
/// carries no matchup signal. Averaging the projected starters (top 22 by
/// overall ≈ 11 offense + 11 defense) restores a meaningful spread.
///
/// Rosters arrive as `teamID`-keyed player arrays, never as `Team.players`:
/// that relationship is a creation-time snapshot, so every badge on this
/// screen quietly described the league as it looked on day one — a traded,
/// signed, drafted or cut player was counted for the wrong club
/// (`docs/TRADE_OVERHAUL_PLAN.md` §4 S3 / §7.5).
enum TeamStrength {

    /// The slots that make up "the starting lineup": the depth chart's 12
    /// offensive and 10 defensive slots.
    ///
    /// Special teams are deliberately excluded. `K`/`P`/`LS`/`H` are not part
    /// of the 22 men who decide a matchup and their ratings sit in a different
    /// band — a long snapper's OVR is a grade on snapping —
    /// so folding them in drags every club down by a couple of points; `KR`/`PR`
    /// re-count a receiver or back who is already in the offensive eleven, so
    /// they double-weight one player. Averaging exactly these 22 slots also
    /// makes TEAM the honest weighted mean of the OFF and DEF pills shown
    /// beside it on the depth chart.
    static let lineupSlots: [DepthChartSlot] =
        DepthChartSlot.offenseSlots + DepthChartSlot.defenseSlots

    /// Mean OVR of the starters occupying `slots` in `chart`.
    /// Slots nobody fills (no fullback on the roster, a traded player still
    /// referenced by a stale saved chart) simply drop out of the average.
    static func ovr(chart: DepthChart, slots: [DepthChartSlot], lookup: [UUID: Player]) -> Int {
        let starters = slots
            .compactMap { chart.starter(for: $0) }
            .compactMap { lookup[$0] }
        guard !starters.isEmpty else { return 0 }
        return starters.reduce(0) { $0 + $1.overall } / starters.count
    }

    /// The lineup a roster implies when no chart has been saved — the SAME
    /// seeding `DepthChartView` shows on first open, so the number a rival's
    /// row quotes is the number his depth chart would show.
    static func lineup(of roster: [Player]) -> DepthChart {
        var chart = DepthChart()
        chart.autoGenerate(players: roster)
        return chart
    }

    static func lookup(_ roster: [Player]) -> [UUID: Player] {
        Dictionary(roster.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Starters OVR of ONE roster — THE team-strength number.
    ///
    /// Position-aware on purpose. The old "mean of the best 22 by overall"
    /// answered "how good are this club's 22 best athletes", which flatters a
    /// roster stacked at one position and ignores the hole at another: six
    /// good receivers counted six times over while the missing left tackle
    /// cost nothing. Averaging the lineup's 22 SLOTS prices the hole.
    ///
    /// - Parameter chart: The club's saved depth chart when one exists (the
    ///   user's team). Falls back to the auto-derived lineup when it is absent
    ///   or so stale that no slot resolves to a current player.
    static func startersOVR(_ roster: [Player], chart: DepthChart? = nil) -> Int {
        guard !roster.isEmpty else { return 0 }
        let table = lookup(roster)
        if let chart {
            let saved = ovr(chart: chart, slots: lineupSlots, lookup: table)
            if saved > 0 { return saved }
        }
        return ovr(chart: lineup(of: roster), slots: lineupSlots, lookup: table)
    }

    /// Starters OVR for every team in one pass, keyed by `teamID`. Feed it the
    /// league's players from a single fetch; the result is what the rows read,
    /// so no row ever touches a roster (or a query) itself.
    ///
    /// - Parameter charts: Saved depth charts by `teamID` — in practice only
    ///   the user's, since AI clubs never persist one.
    static func startersOVRByTeam(players: [Player], charts: [UUID: DepthChart] = [:]) -> [UUID: Int] {
        let rosters = Dictionary(grouping: players.filter { $0.teamID != nil }) { $0.teamID! }
        var result: [UUID: Int] = [:]
        result.reserveCapacity(rosters.count)
        for (teamID, roster) in rosters {
            result[teamID] = startersOVR(roster, chart: charts[teamID])
        }
        return result
    }

    /// The user's saved chart, decoded once per screen appearance. Every
    /// surface that quotes his team's OVR reads it through here so the depth
    /// chart he edited and the schedule row that judges him agree.
    static func savedCharts(for career: Career) -> [UUID: DepthChart] {
        guard let teamID = career.teamID,
              let data = career.depthChartData,
              let chart = try? JSONDecoder().decode(DepthChart.self, from: data)
        else { return [:] }
        return [teamID: chart]
    }

    /// League-wide mean of the starters OVR — the pivot the schedule badge
    /// colors hang off. Derived from the ``startersOVRByTeam(players:)`` index
    /// computed once per view appearance; don't recompute per row.
    static func leagueAverageStartersOVR(_ ovrByTeam: [UUID: Int]) -> Int {
        let values = ovrByTeam.values.filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / values.count
    }

    /// Team strength color for an OVR badge — the app-wide `Color.forRating`
    /// ladder, nothing bespoke.
    ///
    /// This used to color relative to the league mean (green above the pivot,
    /// red below) to squeeze signal out of the narrow ~75-78 starters band.
    /// It worked in isolation and broke everywhere else: Cleveland at 76 came
    /// up red here and blue on League Rosters, which reads as a data bug
    /// rather than a scale choice. Absolute wins — the same number is the same
    /// color on every screen. `leagueAverage` is kept in the signature so the
    /// pivot can come back as an opt-in later without re-threading the value
    /// through `GameRow` / the next-three rail.
    static func ovrColor(_ ovr: Int, leagueAverage: Int) -> Color {
        Color.forRating(ovr)
    }
}

struct ScheduleView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @Query private var allGamesUnscoped: [Game]
    @Query private var allTeamsUnscoped: [Team]

    // `@Query` cannot take a runtime predicate built from a stored property,
    // so the store-wide result is narrowed to THIS save here. Without it the
    // screen mixes two careers' populations into one list.
    private var allGames: [Game] { allGamesUnscoped.filter { $0.careerID == career.id } }
    private var allTeams: [Team] { allTeamsUnscoped.filter { $0.careerID == career.id } }

    @State private var selectedWeek: Int
    @State private var previewGame: Game?
    /// League mean of starters OVR — computed once when the view appears so
    /// the badge colors compare opponents against the actual league spread.
    @State private var leagueAvgOVR = 0
    /// Starters OVR per `teamID`, from ONE roster fetch per appearance (S3:
    /// rosters are queried by `teamID`, never read off `Team.players`). The
    /// rows only ever do a dictionary lookup.
    @State private var ovrByTeam: [UUID: Int] = [:]
    /// The user's saved depth chart, keyed by his `teamID`. Decoded once per
    /// appearance so his own OVR here is the one his depth chart screen shows.
    @State private var userCharts: [UUID: DepthChart] = [:]

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
                // Deliberately full-bleed rather than clamped to the 720pt card
                // measure below: at 720 only ~13 of the 18 week chips fit, so
                // the strip started scrolling and clipped a chip mid-glyph.
                // Seeing the whole season at once beats edge alignment here.
                weekSelector
                    .padding(.vertical, 12)
                    .background(Color.backgroundSecondary)

                if weekGames.isEmpty && nextThreePlayerGames.isEmpty {
                    emptyStateView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            if !nextThreePlayerGames.isEmpty {
                                nextGamesPreview
                            }

                            if !weekGames.isEmpty {
                                weekTable
                            } else {
                                emptyWeekInline
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: DSLayout.contentMeasure)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle("Week \(selectedWeek) Schedule")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            // One roster fetch per appearance, then pure lookups. Recomputed on
            // every appearance (not just the first) so a week advance, a trade
            // or a signing is reflected the next time the schedule opens.
            // Rostered players only — free agents and the retired archive (which
            // grows every season) never contribute to a team's OVR.
            let cid = career.id
            let descriptor = FetchDescriptor<Player>(
                predicate: #Predicate<Player> { $0.careerID == cid && $0.teamID != nil }
            )
            let players = (try? modelContext.fetch(descriptor)) ?? []
            userCharts = TeamStrength.savedCharts(for: career)
            ovrByTeam = TeamStrength.startersOVRByTeam(players: players, charts: userCharts)
            leagueAvgOVR = TeamStrength.leagueAverageStartersOVR(ovrByTeam)
        }
        .sheet(item: $previewGame) { game in
            GamePreviewSheet(
                game: game,
                teams: allTeams,
                playerTeamID: playerTeamID,
                teamRecords: teamRecords,
                userCharts: userCharts
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

    // MARK: - The Week's Table

    /// Wave 1b: one card, one header, N rows — the list standard (§2.2) rather
    /// than sixteen individual score cards. A week of football is a LIST of
    /// matchups, and every matchup carries the same four numbers, so the card
    /// stack was paying a full container per row to say what a column says.
    private var weekTable: some View {
        VStack(spacing: 0) {
            DSGroupRollup(
                title: "Week \(selectedWeek)",
                facts: weekFacts,
                tint: selectedWeek == career.currentWeek ? Color.accentGold : Color.textSecondary
            )
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(Color.backgroundTertiary.opacity(0.6))

            ScheduleHeaderRow()

            Divider().overlay(Color.surfaceBorder)

            ForEach(Array(weekGames.enumerated()), id: \.element.id) { index, game in
                GameRow(
                    game: game,
                    teams: allTeams,
                    playerTeamID: playerTeamID,
                    teamRecords: teamRecords,
                    leagueAvgOVR: leagueAvgOVR,
                    ovrByTeam: ovrByTeam
                )
                .contentShape(Rectangle())
                .onTapGesture { previewGame = game }

                if index < weekGames.count - 1 {
                    Divider()
                        .overlay(Color.surfaceBorder.opacity(0.5))
                        .padding(.horizontal, DSSpacing.md)
                }
            }
        }
        .cardBackground()
    }

    /// Pre-formatted rollup facts — `DSGroupRollup` does no arithmetic.
    private var weekFacts: [String] {
        var facts = ["\(weekGames.count) game\(weekGames.count == 1 ? "" : "s")"]
        if selectedWeek == career.currentWeek { facts.insert("Current week", at: 0) }
        let played = weekGames.filter(\.isPlayed).count
        if played > 0 { facts.append("\(played) final") }
        return facts
    }

    // MARK: - Next Games Preview

    /// The user's next three, at `glance` density: a rail, not a table. Same
    /// row component, one density down (§P3) — 32 pt instead of 44, no header,
    /// no portrait gutter.
    private var nextGamesPreview: some View {
        VStack(spacing: 0) {
            DSGroupRollup(
                title: "Next 3 Games",
                facts: ["Your schedule from week \(career.currentWeek)"],
                tint: Color.accentGold
            )
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .background(Color.backgroundTertiary.opacity(0.6))

            ForEach(Array(nextThreePlayerGames.enumerated()), id: \.element.id) { index, game in
                NextGameRow(
                    game: game,
                    teams: allTeams,
                    playerTeamID: playerTeamID,
                    teamRecords: teamRecords,
                    isCurrentWeek: game.week == career.currentWeek,
                    leagueAvgOVR: leagueAvgOVR,
                    ovrByTeam: ovrByTeam
                )
                .contentShape(Rectangle())
                .onTapGesture { previewGame = game }

                if index < nextThreePlayerGames.count - 1 {
                    Divider()
                        .overlay(Color.surfaceBorder.opacity(0.5))
                        .padding(.horizontal, DSSpacing.md)
                }
            }
        }
        .cardBackground()
    }

    // MARK: - Empty State

    /// `DSEmptyState` (§2.7): icon → title → what would fill this → the action
    /// that fills it. The fourth beat is the one the old label had no answer
    /// for — an empty week is almost always a week the user scrolled PAST, so
    /// the action is the way back to the one he is playing.
    private var emptyStateView: some View {
        VStack {
            Spacer(minLength: 0)
            DSEmptyState(
                density: .scan,
                icon: "calendar.badge.exclamationmark",
                title: "Nothing On In Week \(selectedWeek)",
                message: emptyWeekMessage,
                actions: jumpToCurrentWeekActions
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The same state one density down, because here it is a gap INSIDE a
    /// screen that already has content above it (the next-three rail).
    private var emptyWeekInline: some View {
        DSEmptyState(
            density: .glance,
            icon: "calendar.badge.exclamationmark",
            title: "No games in week \(selectedWeek)",
            message: emptyWeekMessage,
            actions: jumpToCurrentWeekActions
        )
    }

    private var emptyWeekMessage: String {
        selectedWeek == career.currentWeek
            ? "The league has not scheduled this week yet."
            : "Week \(selectedWeek) has no fixtures in this season's schedule."
    }

    private var jumpToCurrentWeekActions: [DSEmptyState.Action] {
        guard selectedWeek != career.currentWeek else { return [] }
        return [
            DSEmptyState.Action(
                title: "Go To Week \(career.currentWeek)",
                systemImage: "arrow.uturn.backward",
                isPrimary: true
            ) {
                withAnimation { selectedWeek = career.currentWeek }
            }
        ]
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
                .font(DSType.display(11, .semibold))
                .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textTertiary)
            Text("\(week)")
                .font(DSType.display(16, .bold))
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

// MARK: - Schedule Column Widths

/// Shared widths, read from `DSListColumn` so the schedule, the standings, the
/// roster and the board are one ladder (§2.2). Four cells, 128 pt total: the
/// away pair, then the home pair, mirrored around the score so the row reads in
/// the same order as the matchup line above it ("Philadelphia at Dallas").
private enum ScheduleColumn {
    /// A starters-OVR read.
    static let ovr    = DSListColumn.attribute  // 34
    /// A final score — three digits at the very most.
    static let score  = DSListColumn.tight      // 30
    /// `W12`, on the next-three rail.
    static let week   = DSListColumn.tight      // 30
    /// `3-1`, or `3-1-1` in a tie year.
    static let record = DSListColumn.label      // 48
}

// MARK: - Schedule Header Row

/// Built from `DSListHeaderRow`, so the header reserves exactly the slots the
/// row mounts (badge, no portrait, flexible identity) and cannot drift out of
/// register with the numbers underneath it.
private struct ScheduleHeaderRow: View {
    var body: some View {
        DSListHeaderRow(
            density: .scan,
            reservesBadge: true,
            badgeLabel: "AWAY",
            portraitWidth: 0,
            identityLabel: "MATCHUP"
        ) {
            Spacer(minLength: DSSpacing.xxs)
            // `A`/`H` rather than two columns both headed "OVR": §2.13's
            // column gate is about clipping, but a header that does not say
            // WHOSE number it labels is the same failure one step earlier.
            DSColumnHeader("A OVR", width: ScheduleColumn.ovr)
            DSColumnHeader("A PTS", width: ScheduleColumn.score)
            DSColumnHeader("H PTS", width: ScheduleColumn.score)
            DSColumnHeader("H OVR", width: ScheduleColumn.ovr)
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.xs)
    }
}

// MARK: - Next Game Row (glance density)

/// One of the user's next three, on the rail above the week's table.
///
/// Same component as the table row, one density down: `glance` is 32 pt with no
/// portrait gutter and a 12 pt name, which is the whole point of P3 — a rail and
/// a table are the same object at two declared sizes, not two hand-built cards.
private struct NextGameRow: View {
    let game: Game
    let teams: [Team]
    let playerTeamID: UUID?
    let teamRecords: [UUID: StandingsRecord]
    let isCurrentWeek: Bool
    let leagueAvgOVR: Int
    /// Starters OVR per `teamID`, resolved once by the parent (S3).
    let ovrByTeam: [UUID: Int]

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
        guard let oid = opponentID else { return 0 }
        return ovrByTeam[oid] ?? 0
    }

    var body: some View {
        DSListRow(
            density: .glance,
            badge: DSRowBadge(
                text: opponent?.abbreviation ?? "???",
                tint: TeamColors.color(for: opponent?.abbreviation ?? ""),
                accessibilityLabel: opponent?.fullName ?? "Opponent"
            ),
            portraitWidth: 0
        ) {
            EmptyView()
        } identity: {
            HStack(spacing: DSSpacing.xxs) {
                Text("\(isHome ? "vs" : "at") \(opponent?.city ?? "TBD")")
                    .font(DSType.text(DSListDensity.glance.nameSize, .semibold, prose: true))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if isCurrentWeek {
                    DSStatusPill(label: "Now", tone: .info, showsDot: false,
                                 spokenLabel: "This week")
                }
            }
        } columns: {
            Spacer(minLength: DSSpacing.xxs)

            Text("W\(game.week)")
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.textTertiary)
                .dsColumn(ScheduleColumn.week)

            ScheduleCells.ovrCell(opponentOVR, leagueAverage: leagueAvgOVR)

            Text(opponentRecord)
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.textSecondary)
                .dsColumn(ScheduleColumn.record)
        }
        .padding(.horizontal, DSSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Week \(game.week), \(isHome ? "home against" : "away at") "
            + "\(opponent?.fullName ?? "opponent"), \(opponentRecord)"
        )
    }
}

// MARK: - Shared Schedule Cells

/// The two cells both densities print, so the rail and the table cannot
/// disagree about what an OVR looks like.
private enum ScheduleCells {

    @ViewBuilder
    static func ovrCell(_ ovr: Int, leagueAverage: Int) -> some View {
        Group {
            if ovr > 0 {
                Text("\(ovr)")
                    .font(DSType.display(13, .bold))
                    .foregroundStyle(TeamStrength.ovrColor(ovr, leagueAverage: leagueAverage))
            } else {
                Text("\u{2014}")
                    .font(DSType.display(13, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .dsColumn(ScheduleColumn.ovr)
    }

    /// A score, or the reserved gap where one will be. An upcoming game keeps
    /// its column and prints a dash: the user scans the week for what has been
    /// played, and a missing cell is invisible while a dash is not.
    @ViewBuilder
    static func scoreCell(_ score: Int?, tint: Color) -> some View {
        Group {
            if let score {
                Text("\(score)")
                    .font(DSType.display(15, .heavy))
                    .foregroundStyle(tint)
            } else {
                Text("\u{2014}")
                    .font(DSType.display(13, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .dsColumn(ScheduleColumn.score)
    }
}

// MARK: - Game Row

/// One matchup in the week's table.
///
/// Wave 1b converts the score CARD to the list standard. What that changed:
///
///  1. The card's two 22 pt team blocks and 28 pt score became one 44 pt row
///     with a colour-chipped away badge, a matchup line and four fixed cells,
///     so a 16-game week is a table the eye can run down instead of sixteen
///     containers it has to re-enter.
///  2. The "YOUR GAME" banner became a reserved `YOURS` state slot. All three
///     slots — `YOURS` · `DIV` · `FINAL` — are drawn on every row, so the user
///     scans the column of gaps: which of these are mine, which are divisional,
///     which have been played (§2.2's load-bearing idea).
///  3. Every cell goes through `dsColumn`. The card had no fixed columns at
///     all, so "• OVR 76" and a three-digit score negotiated their own widths
///     row by row.
private struct GameRow: View {
    let game: Game
    let teams: [Team]
    let playerTeamID: UUID?
    let teamRecords: [UUID: StandingsRecord]
    let leagueAvgOVR: Int
    /// Starters OVR per `teamID`, resolved once by the parent (S3).
    let ovrByTeam: [UUID: Int]

    private var homeTeam: Team? { teams.first { $0.id == game.homeTeamID } }
    private var awayTeam: Team? { teams.first { $0.id == game.awayTeamID } }

    private var isPlayerGame: Bool {
        guard let pid = playerTeamID else { return false }
        return game.homeTeamID == pid || game.awayTeamID == pid
    }

    private var isDivisionGame: Bool {
        guard let home = homeTeam, let away = awayTeam else { return false }
        return home.conference == away.conference && home.division == away.division
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
        DSListRow(
            density: .scan,
            badge: DSRowBadge(
                text: awayTeam?.abbreviation ?? "???",
                tint: TeamColors.color(for: awayTeam?.abbreviation ?? ""),
                accessibilityLabel: awayTeam?.fullName ?? "Away team"
            ),
            portraitWidth: 0
        ) {
            EmptyView()
        } identity: {
            identityBlock
        } columns: {
            Spacer(minLength: DSSpacing.xxs)

            ScheduleCells.ovrCell(teamOVR(awayTeam), leagueAverage: leagueAvgOVR)
            ScheduleCells.scoreCell(game.awayScore, tint: scoreTint(for: game.awayTeamID))
            ScheduleCells.scoreCell(game.homeScore, tint: scoreTint(for: game.homeTeamID))
            ScheduleCells.ovrCell(teamOVR(homeTeam), leagueAverage: leagueAvgOVR)
        }
        .padding(.horizontal, DSSpacing.md)
        .background(rowTint)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Identity

    /// The matchup line, then the three reserved slots. The row owns the SLOT;
    /// this screen owns what goes in it.
    private var identityBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: DSSpacing.xxs) {
                Text(awayTeam?.city ?? "Away")
                    .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                    .foregroundStyle(Color.textPrimary)
                Text(recordString(for: awayTeam))
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textTertiary)
                Text("at")
                    .font(DSType.text(12, .regular, prose: true))
                    .foregroundStyle(Color.textTertiary)
                Text(homeTeam?.city ?? "Home")
                    .font(DSType.text(DSListDensity.scan.nameSize, .semibold, prose: true))
                    .foregroundStyle(Color.textPrimary)
                Text(recordString(for: homeTeam))
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .lineLimit(1)

            DSStateSlotRow(slots: gameSlots)
        }
    }

    /// The schedule's fixed slot set — `YOURS` · `DIV` · `FINAL` — chosen once
    /// for the list, never per row.
    private var gameSlots: [DSStateSlot] {
        [yoursSlot, divisionSlot, finalSlot]
    }

    private var yoursSlot: DSStateSlot {
        DSStateSlot(
            label: "YOURS",
            tone: isPlayerGame ? .info : .empty,
            spokenLabel: isPlayerGame ? "Your game" : "Not your game"
        )
    }

    private var divisionSlot: DSStateSlot {
        DSStateSlot(
            label: "DIV",
            tone: isDivisionGame ? .neutral : .empty,
            spokenLabel: isDivisionGame ? "Division game" : "Not a division game"
        )
    }

    /// Played or not — and, when it is the user's game, how it went. A
    /// non-player final is a fact with no verdict attached, so it stays neutral.
    private var finalSlot: DSStateSlot {
        guard game.isPlayed else {
            return DSStateSlot(label: "FINAL", tone: .empty,
                               spokenLabel: "Not played yet")
        }
        guard isPlayerGame else {
            return DSStateSlot(label: "FINAL", tone: .neutral, spokenLabel: "Final")
        }
        switch playerWon {
        case .some(true):
            return DSStateSlot(label: "FINAL", tone: .ok, value: "W", spokenLabel: "Final, you won")
        case .some(false):
            return DSStateSlot(label: "FINAL", tone: .bad, value: "L", spokenLabel: "Final, you lost")
        case .none:
            return DSStateSlot(label: "FINAL", tone: .warn, value: "T", spokenLabel: "Final, tied")
        }
    }

    // MARK: Cells

    private func teamOVR(_ team: Team?) -> Int {
        guard let team else { return 0 }
        return ovrByTeam[team.id] ?? 0
    }

    private func recordString(for team: Team?) -> String {
        guard let team, let rec = teamRecords[team.id] else { return "0-0" }
        if rec.ties > 0 { return "\(rec.wins)-\(rec.losses)-\(rec.ties)" }
        return "\(rec.wins)-\(rec.losses)"
    }

    private func scoreTint(for teamID: UUID) -> Color {
        guard game.isPlayed else { return Color.textTertiary }
        if game.winnerID == nil { return Color.warning }        // tie
        return game.winnerID == teamID ? Color.success : Color.textSecondary
    }

    /// The user's own games carry a tint rather than a banner — one row height
    /// for the whole table, and the `YOURS` slot says it in words for anyone
    /// who cannot read the wash.
    private var rowTint: Color {
        guard isPlayerGame else { return Color.clear }
        return game.isPlayed
            ? resultAccentColor.opacity(0.08)
            : Color.accentGold.opacity(0.07)
    }

    // MARK: Accessibility

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
    /// The user's saved depth chart by `teamID`, handed down by the parent so
    /// the preview quotes the same OVR the rest of the app does.
    var userCharts: [UUID: DepthChart] = [:]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Both squads for this matchup, keyed by `teamID` — ONE fetch when the
    /// sheet appears (S3: never `Team.players`, which is frozen at league
    /// creation). Both the OVR line and the key-player lists read it.
    @State private var rosters: [UUID: [Player]] = [:]

    private var homeTeam: Team? { teams.first { $0.id == game.homeTeamID } }
    private var awayTeam: Team? { teams.first { $0.id == game.awayTeamID } }

    private func teamOVR(_ team: Team?) -> Int {
        guard let team else { return 0 }
        return TeamStrength.startersOVR(rosters[team.id] ?? [], chart: userCharts[team.id])
    }

    private func loadRosters() {
        let homeID = game.homeTeamID
        let awayID = game.awayTeamID
        let descriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == homeID || $0.teamID == awayID }
        )
        let players = (try? modelContext.fetch(descriptor)) ?? []
        rosters = Dictionary(grouping: players.filter { $0.teamID != nil }) { $0.teamID! }
    }

    private func recordString(for team: Team?) -> String {
        guard let team, let rec = teamRecords[team.id] else { return "0-0" }
        if rec.ties > 0 { return "\(rec.wins)-\(rec.losses)-\(rec.ties)" }
        return "\(rec.wins)-\(rec.losses)"
    }

    /// Top 3 players by overall.
    private func keyPlayers(_ team: Team?) -> [Player] {
        guard let team else { return [] }
        return (rosters[team.id] ?? [])
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
            .onAppear { loadRosters() }
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
                .font(.system(size: DSType.Size.title1, weight: .heavy))
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
                .font(.system(size: DSType.Size.body, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer()
            Text("\(player.overall)")
                .font(.system(size: DSType.Size.body, weight: .heavy).monospacedDigit())
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
