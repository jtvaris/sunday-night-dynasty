import SwiftUI

// MARK: - Career Stat Aggregation (shared by both stat surfaces)

/// Career-level folding of `SeasonStatLine`s, shared by `PlayerStatsView` and
/// `PlayerDetailView` so the two can never disagree about a career total.
enum CareerStatTotals {

    /// Sums season lines into one career line.
    ///
    /// Every category is additive except `puntAverage`, which is a RATE:
    /// averaging averages would let a 4-punt season outweigh an 80-punt one, so
    /// it is re-derived from punt-weighted yardage.
    static func sum<S: Sequence>(_ lines: S) -> SeasonStatLine where S.Element == SeasonStatLine {
        var total = SeasonStatLine()
        var puntYards = 0.0
        for line in lines {
            total.passYards += line.passYards
            total.passTDs += line.passTDs
            total.passInts += line.passInts
            total.rushYards += line.rushYards
            total.rushTDs += line.rushTDs
            total.receptions += line.receptions
            total.recYards += line.recYards
            total.recTDs += line.recTDs
            total.tackles += line.tackles
            total.sacks += line.sacks
            total.defInts += line.defInts
            total.passesDefended += line.passesDefended
            total.fieldGoalsMade += line.fieldGoalsMade
            total.fieldGoalsAttempted += line.fieldGoalsAttempted
            total.punts += line.punts
            total.snapsPlayed += line.snapsPlayed
            puntYards += Double(line.punts) * line.puntAverage
        }
        total.puntAverage = total.punts > 0 ? puntYards / Double(total.punts) : 0
        return total
    }
}

// MARK: - Career Table Row

/// One rendered row of a career table. Four kinds share the layout so the
/// season, the season in progress, its playoff sub-line and the career summary
/// all line up under the same column widths.
struct CareerSeasonRow: Identifiable {

    enum Kind {
        /// A finished regular season (`PlayerSeasonHistory`).
        case season
        /// The season being played right now (`Player.seasonStatLine`).
        case inProgress
        /// Playoff production for the season directly above it.
        case postseason
        /// Sum of every regular-season row in the table.
        case careerTotal
    }

    let id: String
    let kind: Kind
    /// Left-hand label: the year, `"Playoffs"`, or `"CAREER"`.
    let label: String
    /// `nil` on the rows where an age would be meaningless (playoffs, career).
    let age: Int?
    /// End-of-season overall — career peak on the summary row, `nil` on a
    /// playoff sub-row.
    let overall: Int?
    let gamesPlayed: Int
    let gamesStarted: Int
    let line: SeasonStatLine

    /// True when the row records a season the player never spent on a roster —
    /// a real gap in the career, which renders as dashes rather than zeros.
    var isEmptySeason: Bool { kind == .season && gamesPlayed == 0 }
}

// MARK: - Career Table Columns

/// One numeric column of a career table. `width` is fixed so the header and the
/// body rows can never drift apart; the whole set has to fit iPhone portrait
/// (~300 pt of content), which is why nobody gets more than four.
struct CareerStatColumn: Identifiable {
    let header: String
    let width: CGFloat
    /// Renders in the "good thing happened" tint (TDs, sacks, picks).
    let isPositive: Bool
    let value: (CareerSeasonRow) -> String

    var id: String { header }

    init(
        _ header: String,
        width: CGFloat,
        isPositive: Bool = false,
        value: @escaping (CareerSeasonRow) -> String
    ) {
        self.header = header
        self.width = width
        self.isPositive = isPositive
        self.value = value
    }
}

enum CareerStatColumns {

    /// The three-to-four categories that actually matter for a position.
    ///
    /// Keyed on the player's CURRENT position so one table has one column set —
    /// a history row's own `positionRaw` records what he played that year for
    /// engines and Hall-of-Fame snapshots, but mixing column sets mid-table
    /// would be unreadable.
    static func forPosition(_ position: Position) -> [CareerStatColumn] {
        switch position {
        case .QB:
            return [
                CareerStatColumn("YDS", width: 48) { "\($0.line.passYards)" },
                CareerStatColumn("TD", width: 30, isPositive: true) { "\($0.line.passTDs)" },
                CareerStatColumn("INT", width: 32) { "\($0.line.passInts)" },
            ]
        case .RB, .FB:
            return [
                CareerStatColumn("YDS", width: 46) { "\($0.line.rushYards)" },
                CareerStatColumn("TD", width: 30, isPositive: true) { "\($0.line.rushTDs)" },
                CareerStatColumn("REC", width: 34) { "\($0.line.receptions)" },
            ]
        case .WR, .TE:
            return [
                CareerStatColumn("REC", width: 34) { "\($0.line.receptions)" },
                CareerStatColumn("YDS", width: 46) { "\($0.line.recYards)" },
                CareerStatColumn("TD", width: 30, isPositive: true) { "\($0.line.recTDs)" },
            ]
        case .LT, .LG, .C, .RG, .RT:
            // A lineman has no counting stats — starts and snaps are the whole
            // production record the game can honestly show.
            return [
                CareerStatColumn("GS", width: 32) { "\($0.gamesStarted)" },
                CareerStatColumn("SNAP", width: 46) { "\($0.line.snapsPlayed)" },
            ]
        case .DE, .DT:
            return [
                CareerStatColumn("TKL", width: 36) { "\($0.line.tackles)" },
                CareerStatColumn("SACK", width: 42, isPositive: true) {
                    String(format: "%.1f", $0.line.sacks)
                },
            ]
        case .OLB, .MLB:
            return [
                CareerStatColumn("TKL", width: 36) { "\($0.line.tackles)" },
                CareerStatColumn("SACK", width: 42, isPositive: true) {
                    String(format: "%.1f", $0.line.sacks)
                },
                CareerStatColumn("INT", width: 30, isPositive: true) { "\($0.line.defInts)" },
            ]
        case .CB, .FS, .SS:
            return [
                CareerStatColumn("TKL", width: 36) { "\($0.line.tackles)" },
                CareerStatColumn("INT", width: 30, isPositive: true) { "\($0.line.defInts)" },
                CareerStatColumn("PD", width: 30) { "\($0.line.passesDefended)" },
            ]
        case .K:
            return [
                CareerStatColumn("FGM", width: 36, isPositive: true) { "\($0.line.fieldGoalsMade)" },
                CareerStatColumn("FGA", width: 36) { "\($0.line.fieldGoalsAttempted)" },
                CareerStatColumn("FG%", width: 42) { row in
                    guard row.line.fieldGoalsAttempted > 0 else { return "-" }
                    let pct = Double(row.line.fieldGoalsMade)
                        / Double(row.line.fieldGoalsAttempted) * 100
                    return String(format: "%.0f%%", pct)
                },
            ]
        case .P:
            return [
                CareerStatColumn("PUNT", width: 44) { "\($0.line.punts)" },
                CareerStatColumn("AVG", width: 42) { String(format: "%.1f", $0.line.puntAverage) },
            ]
        }
    }
}

// MARK: - Career Table Builder

/// Turns the two real stat sources into display rows.
///
/// The sources are `Player.seasonStatLine` (the season in progress, accumulated
/// week by week) and `PlayerSeasonHistory` (one row per finished season). The
/// week-18 snapshot writes the history row BEFORE the offseason clears the live
/// accumulator, so for a few phases both exist for the same year — hence the
/// `currentSeason` guard: a year that already has a history row is never also
/// counted from the live line.
enum CareerTableBuilder {

    /// Display rows, newest first, with the career summary last.
    ///
    /// - Parameters:
    ///   - history: This player's rows in any order (sorted here).
    ///   - currentSeason: The league's current season, or `nil` when the caller
    ///     has no career context (then the live line is only used if the player
    ///     has no history at all).
    ///   - postseason: Playoff production by season — dev-template only today
    ///     (see `DevPostseasonStats`), empty everywhere else.
    static func rows(
        player: Player,
        history: [PlayerSeasonHistory],
        currentSeason: Int?,
        postseason: [Int: LeagueTemplate.PostLine] = [:]
    ) -> [CareerSeasonRow] {
        let finished = history
            .filter { entry in currentSeason.map { entry.season <= $0 } ?? true }
            .sorted { $0.season > $1.season }
        let hasSnapshotForCurrentSeason = currentSeason.map { season in
            finished.contains { $0.season == season }
        } ?? !history.isEmpty

        var rows: [CareerSeasonRow] = []

        // The season in progress, when week 18 has not snapshotted it yet.
        let liveLine = player.seasonStatLine
        if !hasSnapshotForCurrentSeason,
           player.gamesPlayedThisSeason > 0 || !liveLine.isEmpty {
            let label = currentSeason.map { "\(String($0))*" } ?? "This season*"
            rows.append(CareerSeasonRow(
                id: "live",
                kind: .inProgress,
                label: label,
                age: player.age,
                overall: player.overall,
                gamesPlayed: player.gamesPlayedThisSeason,
                gamesStarted: player.gamesStartedThisSeason,
                line: liveLine
            ))
        }

        for entry in finished {
            rows.append(CareerSeasonRow(
                id: entry.id.uuidString,
                kind: .season,
                label: String(entry.season),
                age: entry.ageAtEndOfSeason,
                overall: entry.overallAtEndOfSeason,
                gamesPlayed: entry.gamesPlayed,
                gamesStarted: entry.gamesStarted,
                line: entry.statLine
            ))
            // Playoff sub-row, directly under the season it belongs to.
            if let post = postseason[entry.season], let row = postseasonRow(
                season: entry.season, post: post
            ) {
                rows.append(row)
            }
        }

        // Career summary: the regular-season rows above it, nothing else. The
        // playoff sub-rows are deliberately excluded — a career total that
        // silently mixed the two would not match any real record book.
        let counted = rows.filter { $0.kind != .postseason }
        guard !counted.isEmpty else { return rows }
        let totals = CareerStatTotals.sum(counted.map(\.line))
        rows.append(CareerSeasonRow(
            id: "career-total",
            kind: .careerTotal,
            label: "CAREER",
            age: nil,
            overall: counted.compactMap(\.overall).max(),
            gamesPlayed: counted.reduce(0) { $0 + $1.gamesPlayed },
            gamesStarted: counted.reduce(0) { $0 + $1.gamesStarted },
            line: totals
        ))
        return rows
    }

    /// A playoff sub-row, or `nil` when the postseason bag holds nothing worth
    /// a line of its own.
    private static func postseasonRow(
        season: Int,
        post: LeagueTemplate.PostLine
    ) -> CareerSeasonRow? {
        // Fold through the importer's single key→category table rather than a
        // second copy of it.
        let line = LeagueTemplateImporter.statLine(from: post.asRegularShapedLine(year: season))
        let games = post.gp ?? 0
        guard games > 0 || !line.isEmpty else { return nil }
        return CareerSeasonRow(
            id: "post-\(season)",
            kind: .postseason,
            label: "Playoffs",
            age: nil,
            overall: nil,
            gamesPlayed: games,
            gamesStarted: 0,
            line: line
        )
    }
}

// MARK: - Career Table View

/// The per-season career table, shared by `PlayerDetailView`'s section and
/// `PlayerStatsView`'s "By Season" tab.
///
/// `spacing: 0` throughout: the fixed column widths ARE the layout budget, so
/// the default HStack gutter would silently overflow on iPhone portrait.
struct CareerStatTable: View {
    let position: Position
    let rows: [CareerSeasonRow]

    private var columns: [CareerStatColumn] { CareerStatColumns.forPosition(position) }

    var body: some View {
        VStack(spacing: 6) {
            headerRow
            ForEach(rows) { row in
                if row.kind == .careerTotal {
                    Divider().overlay(Color.surfaceBorder)
                }
                bodyRow(row)
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            headerCell("SEASON")
                .frame(maxWidth: .infinity, alignment: .leading)
            headerCell("AGE").frame(width: 32, alignment: .trailing)
            headerCell("OVR").frame(width: 38, alignment: .trailing)
            headerCell("GP").frame(width: 32, alignment: .trailing)
            ForEach(columns) { column in
                headerCell(column.header)
                    .frame(width: column.width, alignment: .trailing)
            }
        }
    }

    private func headerCell(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            // textTertiary fails WCAG AA on the card surface (DSTokens §contrast),
            // so column labels use the readable muted token instead.
            .foregroundStyle(Color.textTertiaryReadable)
    }

    private func bodyRow(_ row: CareerSeasonRow) -> some View {
        // A season not spent on an NFL roster is a real gap, not a zero line.
        let played = !row.isEmptySeason
        let isSummary = row.kind == .careerTotal
        return HStack(spacing: 0) {
            Text(row.label)
                .font(isSummary
                      ? .caption.weight(.bold).monospacedDigit()
                      : .caption.monospacedDigit())
                .foregroundStyle(labelColor(row))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.age.map { "\($0)" } ?? "")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32, alignment: .trailing)
            Text(row.overall.map { "\($0)" } ?? "")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(row.overall.map { Color.forRating($0) } ?? Color.textSecondary)
                .frame(width: 38, alignment: .trailing)
            Text("\(row.gamesPlayed)")
                .font(isSummary
                      ? .caption.weight(.semibold).monospacedDigit()
                      : .caption.monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 32, alignment: .trailing)
            ForEach(columns) { column in
                let text = played ? column.value(row) : "-"
                Text(text)
                    .font(isSummary
                          ? .caption.weight(.semibold).monospacedDigit()
                          : .caption.monospacedDigit())
                    .foregroundStyle(
                        !played ? Color.textTertiaryReadable :
                        column.isPositive && text != "0" && text != "0.0" ? Color.success :
                        Color.textPrimary
                    )
                    .frame(width: column.width, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func labelColor(_ row: CareerSeasonRow) -> Color {
        switch row.kind {
        case .season:      return .textPrimary
        case .inProgress:  return .accentGold
        case .postseason:  return .textTertiaryReadable
        case .careerTotal: return .textPrimary
        }
    }
}

// MARK: - Dev Postseason Bridge

#if DEBUG
/// Playoff production for the fixed-2026 **dev** league, read straight out of
/// the bundled template.
///
/// Why the template and not the store: `PlayerSeasonHistory` has no postseason
/// columns, so the import drops the `post` bag it decodes (`LeagueTemplate.
/// PostLine`). Until those columns exist the career table borrows the numbers
/// from the very file the league was imported from, matched on name + position.
/// That match is safe by construction: real names only ever appear in the dev
/// template, so a publish or generated league finds nothing and the sub-rows
/// simply do not appear.
///
/// DEBUG-only for the same reason as everything else that can name the dev
/// profile (see `LeagueTemplateLoader`'s bundling contract). The 2.6 MB decode
/// runs at most once per app launch, off the main actor.
@MainActor
enum DevPostseasonStats {

    /// `name|POS` → season → playoff line. `nil` until the first load.
    private static var index: [String: [Int: LeagueTemplate.PostLine]]?

    /// Playoff seasons for one player, `[:]` when this build or this league has
    /// none.
    static func lines(for player: Player) async -> [Int: LeagueTemplate.PostLine] {
        let key = LeagueTemplate.postseasonKey(
            name: player.fullName, position: player.position.rawValue
        )
        if index == nil {
            index = await Task.detached(priority: .utility) { buildIndex() }.value
        }
        return index?[key] ?? [:]
    }

    /// Decodes the dev template and reduces it to the postseason map. Runs off
    /// the main actor; touches nothing but the bundle.
    ///
    /// Locates the file itself rather than going through `LeagueTemplateLoader`:
    /// the module defaults to `@MainActor` isolation, so the loader's entry
    /// points are main-actor-bound, and the entire point here is to keep the
    /// 2.6 MB decode OFF the main actor. The resource name still comes from
    /// `Profile`, and the flat bundle lookup is the one that fires for the
    /// synchronized Resources group (see the loader's bundling contract). A
    /// stripped build that carries no dev template simply gets an empty map.
    nonisolated private static func buildIndex() -> [String: [Int: LeagueTemplate.PostLine]] {
        guard let url = Bundle.main.url(
            forResource: LeagueTemplate.Profile.dev.resourceName, withExtension: "json"
        ) else { return [:] }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let template = try? JSONDecoder().decode(LeagueTemplate.self, from: data)
        else { return [:] }
        return template.postseasonLinesByPlayer()
    }
}
#endif

// MARK: - Player Stats View

/// Comprehensive player statistics: the season in progress, career totals, and
/// the per-season table.
///
/// ## Data sources
///
/// There are exactly two, and neither is a per-game log:
/// - `Player.seasonStatLine` — the season in progress, accumulated week by week
///   from the box score and snapshotted into history at week 18.
/// - `PlayerSeasonHistory` — one row per finished season, handed in by
///   `PlayerDetailView`, which already queries the store.
///
/// This view previously took `[PlayerGameStats]`, which no call site ever
/// supplied: all three tabs rendered zeros for every player in the game. Per-game
/// lines are not persisted anywhere, so the old "Game Log" tab is now
/// "By Season" — the same table `PlayerDetailView` shows, which is production
/// the game really has.
struct PlayerStatsView: View {
    let player: Player

    /// Finished-season rows for this player, any order.
    var history: [PlayerSeasonHistory] = []

    /// The season the league is playing right now. Distinguishes the row week 18
    /// already snapshotted from the one still accumulating, so nothing is
    /// counted twice.
    var currentSeason: Int? = nil

    /// Regular-season week (0 = offseason), used only to word the empty state.
    var currentWeek: Int? = nil

    /// Playoff production by season — dev template only for now.
    var postseason: [Int: LeagueTemplate.PostLine] = [:]

    @State private var selectedTab: StatsTab = .season

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
                case .bySeason:
                    bySeasonContent
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

    // MARK: - Resolved Sources

    /// The finished snapshot for the current season, if week 18 already wrote it.
    private var currentSeasonRow: PlayerSeasonHistory? {
        guard let currentSeason else { return nil }
        return history.last { $0.season == currentSeason }
    }

    /// This season's line: the closed snapshot when it exists, otherwise the
    /// live accumulator.
    private var seasonLine: SeasonStatLine {
        currentSeasonRow?.statLine ?? player.seasonStatLine
    }

    private var seasonGamesPlayed: Int {
        currentSeasonRow?.gamesPlayed ?? player.gamesPlayedThisSeason
    }

    private var seasonGamesStarted: Int {
        currentSeasonRow?.gamesStarted ?? player.gamesStartedThisSeason
    }

    private var careerRows: [CareerSeasonRow] {
        CareerTableBuilder.rows(
            player: player,
            history: history,
            currentSeason: currentSeason,
            postseason: postseason
        )
    }

    private var seasonLabel: String {
        currentSeason.map { "\(String($0)) Season" } ?? "This Season"
    }

    /// Nothing to show: no appearances AND an all-zero line. Distinguished from
    /// "played and produced nothing", which is a real stat line and renders as
    /// zeros.
    private var seasonIsEmpty: Bool {
        seasonGamesPlayed == 0 && seasonLine.isEmpty
    }

    // MARK: - Season Stats

    private var seasonStatsContent: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    statCircle(value: "\(seasonGamesPlayed)", label: "GP", color: .accentGold)
                    statCircle(value: "\(seasonGamesStarted)", label: "GS", color: .accentBlue)
                    statCircle(
                        value: "\(player.overall)", label: "OVR",
                        color: Color.forRating(player.overall)
                    )
                    statCircle(
                        value: formIndicator.symbol, label: "Form",
                        color: formIndicator.color
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.backgroundSecondary)

            if seasonIsEmpty {
                Section {
                    EmptyStateView(
                        icon: "chart.bar.xaxis",
                        title: "No stats recorded",
                        message: seasonEmptyMessage
                    )
                }
                .listRowBackground(Color.backgroundSecondary)
            } else {
                positionStatsSection(
                    line: seasonLine,
                    gamesPlayed: seasonGamesPlayed,
                    gamesStarted: seasonGamesStarted,
                    title: seasonLabel
                )
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    /// Says WHY there is nothing, so an offseason zero doesn't read as a bug.
    private var seasonEmptyMessage: String {
        if let week = currentWeek, week == 0 {
            return "The season hasn't kicked off yet. Production shows up here once week 1 is played."
        }
        if player.isRetired {
            return "\(player.lastName) is retired — his career record is on the Career tab."
        }
        return "\(player.lastName) has not appeared in a game this season."
    }

    // MARK: - Career Stats

    private var careerStatsContent: some View {
        let rows = careerRows
        let total = rows.first { $0.kind == .careerTotal }
        let seasonsPlayed = rows.filter {
            $0.kind != .careerTotal && $0.kind != .postseason && $0.gamesPlayed > 0
        }.count

        return List {
            Section {
                HStack(spacing: 16) {
                    // Seasons he actually appeared in — `yearsPro` counts years on
                    // a roster, which is a different (and often larger) number.
                    statCircle(
                        value: "\(seasonsPlayed)", label: "Seasons",
                        color: .accentGold
                    )
                    statCircle(
                        value: "\(total?.gamesPlayed ?? 0)", label: "Games",
                        color: .accentBlue
                    )
                    statCircle(
                        value: "\(total?.overall ?? player.overall)", label: "Peak",
                        color: Color.forRating(total?.overall ?? player.overall)
                    )
                    statCircle(value: "\(player.age)", label: "Age", color: .textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.backgroundSecondary)

            if let total {
                positionStatsSection(
                    line: total.line,
                    gamesPlayed: total.gamesPlayed,
                    gamesStarted: total.gamesStarted,
                    title: "Career Totals"
                )

                if total.gamesPlayed > 0 {
                    positionAveragesSection(line: total.line, gamesPlayed: total.gamesPlayed)
                }
            } else {
                Section {
                    EmptyStateView(
                        icon: "clock.arrow.circlepath",
                        title: "No career record yet",
                        message: "A rookie has no seasons behind him. His first finished season lands here at the end of the year."
                    )
                }
                .listRowBackground(Color.backgroundSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    // MARK: - By Season

    private var bySeasonContent: some View {
        let rows = careerRows

        return List {
            if rows.isEmpty {
                Section {
                    EmptyStateView(
                        icon: "table",
                        title: "No seasons to show",
                        message: "Once this player finishes a season, every year of his career appears here."
                    )
                }
                .listRowBackground(Color.backgroundSecondary)
            } else {
                Section {
                    CareerStatTable(position: player.position, rows: rows)
                        .padding(.vertical, 4)
                } footer: {
                    Text(bySeasonFooter(rows: rows))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiaryReadable)
                }
                .listRowBackground(Color.backgroundSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private func bySeasonFooter(rows: [CareerSeasonRow]) -> String {
        var parts: [String] = []
        if rows.contains(where: { $0.kind == .inProgress }) {
            parts.append("* season in progress")
        }
        if rows.contains(where: { $0.kind == .postseason }) {
            parts.append("playoff lines are listed separately and are not in the career total")
        }
        return parts.isEmpty
            ? "Regular-season production. A dash marks a year not spent on an NFL roster."
            : parts.joined(separator: " · ")
    }

    // MARK: - Position-Specific Stats Sections

    /// Only the categories `SeasonStatLine` really carries. Attempts,
    /// completions, targets, carries and forced fumbles are box-score-only
    /// (`PlayerGameStats`) and are not accumulated across a season, so nothing
    /// here pretends to derive a passer rating or a yards-per-carry.
    @ViewBuilder
    private func positionStatsSection(
        line: SeasonStatLine,
        gamesPlayed: Int,
        gamesStarted: Int,
        title: String
    ) -> some View {
        switch player.position {
        case .QB:
            Section(title) {
                statRow("Games Played / Started", value: "\(gamesPlayed) / \(gamesStarted)")
                statRow("Passing Yards", value: "\(line.passYards)")
                statRow("Passing TDs", value: "\(line.passTDs)", highlight: line.passTDs > 0)
                statRow("Interceptions", value: "\(line.passInts)", negative: line.passInts > 0)
                if line.rushYards != 0 || line.rushTDs > 0 {
                    statRow("Rush Yards", value: "\(line.rushYards)")
                    statRow("Rush TDs", value: "\(line.rushTDs)", highlight: line.rushTDs > 0)
                }
            }
            .listRowBackground(Color.backgroundSecondary)

        case .RB, .FB:
            Section(title) {
                statRow("Games Played / Started", value: "\(gamesPlayed) / \(gamesStarted)")
                statRow("Rushing Yards", value: "\(line.rushYards)")
                statRow("Rushing TDs", value: "\(line.rushTDs)", highlight: line.rushTDs > 0)
                if line.receptions > 0 {
                    statRow("Receptions", value: "\(line.receptions)")
                    statRow("Receiving Yards", value: "\(line.recYards)")
                    statRow("Receiving TDs", value: "\(line.recTDs)", highlight: line.recTDs > 0)
                }
            }
            .listRowBackground(Color.backgroundSecondary)

        case .WR, .TE:
            Section(title) {
                statRow("Games Played / Started", value: "\(gamesPlayed) / \(gamesStarted)")
                statRow("Receptions", value: "\(line.receptions)")
                statRow("Receiving Yards", value: "\(line.recYards)")
                statRow("Receiving TDs", value: "\(line.recTDs)", highlight: line.recTDs > 0)
                if line.receptions > 0 {
                    statRow(
                        "Yards/Reception",
                        value: String(format: "%.1f", Double(line.recYards) / Double(line.receptions))
                    )
                }
                if line.rushYards != 0 {
                    statRow("Rush Yards", value: "\(line.rushYards)")
                }
            }
            .listRowBackground(Color.backgroundSecondary)

        case .LT, .LG, .C, .RG, .RT:
            Section(title) {
                statRow("Games Played / Started", value: "\(gamesPlayed) / \(gamesStarted)")
                statRow("Snaps Played", value: "\(line.snapsPlayed)")
            }
            .listRowBackground(Color.backgroundSecondary)

        case .DE, .DT, .OLB, .MLB:
            Section(title) {
                statRow("Games Played / Started", value: "\(gamesPlayed) / \(gamesStarted)")
                statRow("Tackles", value: "\(line.tackles)")
                statRow("Sacks", value: String(format: "%.1f", line.sacks), highlight: line.sacks > 0)
                statRow("Interceptions", value: "\(line.defInts)", highlight: line.defInts > 0)
                statRow("Passes Defended", value: "\(line.passesDefended)")
            }
            .listRowBackground(Color.backgroundSecondary)

        case .CB, .FS, .SS:
            Section(title) {
                statRow("Games Played / Started", value: "\(gamesPlayed) / \(gamesStarted)")
                statRow("Tackles", value: "\(line.tackles)")
                statRow("Interceptions", value: "\(line.defInts)", highlight: line.defInts > 0)
                statRow("Passes Defended", value: "\(line.passesDefended)")
                if line.sacks > 0 {
                    statRow("Sacks", value: String(format: "%.1f", line.sacks), highlight: true)
                }
            }
            .listRowBackground(Color.backgroundSecondary)

        case .K:
            Section(title) {
                statRow("Games Played", value: "\(gamesPlayed)")
                statRow("FG Made/Attempted", value: "\(line.fieldGoalsMade)/\(line.fieldGoalsAttempted)")
                if line.fieldGoalsAttempted > 0 {
                    let pct = Double(line.fieldGoalsMade) / Double(line.fieldGoalsAttempted) * 100.0
                    statRow("FG %", value: String(format: "%.1f%%", pct))
                }
            }
            .listRowBackground(Color.backgroundSecondary)

        case .P:
            Section(title) {
                statRow("Games Played", value: "\(gamesPlayed)")
                statRow("Punts", value: "\(line.punts)")
                statRow("Punt Average", value: String(format: "%.1f", line.puntAverage))
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    @ViewBuilder
    private func positionAveragesSection(line: SeasonStatLine, gamesPlayed: Int) -> some View {
        let gp = max(1.0, Double(gamesPlayed))

        Section("Per Game Averages") {
            switch player.position {
            case .QB:
                statRow("Pass Yds/G", value: String(format: "%.1f", Double(line.passYards) / gp))
                statRow("Pass TDs/G", value: String(format: "%.2f", Double(line.passTDs) / gp))

            case .RB, .FB:
                statRow("Rush Yds/G", value: String(format: "%.1f", Double(line.rushYards) / gp))
                statRow("Rush TDs/G", value: String(format: "%.2f", Double(line.rushTDs) / gp))
                if line.receptions > 0 {
                    statRow("Rec Yds/G", value: String(format: "%.1f", Double(line.recYards) / gp))
                }

            case .WR, .TE:
                statRow("Rec/G", value: String(format: "%.1f", Double(line.receptions) / gp))
                statRow("Rec Yds/G", value: String(format: "%.1f", Double(line.recYards) / gp))
                statRow("Rec TDs/G", value: String(format: "%.2f", Double(line.recTDs) / gp))

            case .LT, .LG, .C, .RG, .RT:
                statRow("Snaps/G", value: String(format: "%.1f", Double(line.snapsPlayed) / gp))

            case .DE, .DT, .OLB, .MLB, .CB, .FS, .SS:
                statRow("Tackles/G", value: String(format: "%.1f", Double(line.tackles) / gp))
                statRow("Sacks/G", value: String(format: "%.2f", line.sacks / gp))

            case .K:
                statRow("FG Made/G", value: String(format: "%.1f", Double(line.fieldGoalsMade) / gp))

            case .P:
                statRow("Punts/G", value: String(format: "%.1f", Double(line.punts) / gp))
            }
        }
        .listRowBackground(Color.backgroundSecondary)
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

    // MARK: - Form Indicator

    private var formIndicator: (symbol: String, color: Color) {
        playerFormIndicator(for: player)
    }
}

// MARK: - Stats Tab Enum

enum StatsTab: String, CaseIterable, Identifiable {
    case season, career, bySeason

    var id: String { rawValue }

    var label: String {
        switch self {
        case .season:   return "Season"
        case .career:   return "Career"
        case .bySeason: return "By Season"
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
            currentSeason: 2026,
            currentWeek: 8
        )
    }
}
