import SwiftUI
import SwiftData

// MARK: - League Rosters (Wave 2 UX — `docs/TRADE_OVERHAUL_PLAN.md` finding S8)

/// The league's 32 rosters, browsable.
///
/// WHY this screen exists: the user could see his own 53 players and a scouting
/// board of college prospects, and NOTHING else. The other 31 franchises were
/// abbreviations on a standings table — so "who has a spare tackle?" was a
/// question the game refused to answer, and the Trade Center's partner picker
/// asked the user to shop blind. Trades only become a real GM activity once the
/// market is visible, which is what this browser is: 32 rosters → one roster →
/// the standard player detail screen → a pre-filled trade proposal.
struct LeagueRostersView: View {

    let career: Career

    @Query private var allTeamsUnscoped: [Team]
    @Query private var allPlayersUnscoped: [Player]

    // `@Query` cannot take a runtime predicate built from a stored property,
    // so the store-wide result is narrowed to THIS save here. Without it the
    // screen mixes two careers' populations into one list.
    private var allTeams: [Team] { allTeamsUnscoped.filter { $0.careerID == career.id } }
    private var allPlayers: [Player] { allPlayersUnscoped.filter { $0.careerID == career.id } }

    /// `nil` until the user picks a side, so the screen opens on HIS conference
    /// (his division rivals are the rosters he cares about) without an init.
    @State private var pickedConference: Conference?

    // MARK: Player search (finding: "every CB 80+ with cap space")

    /// What the browser is showing. The 32-roster board answers "who's on that
    /// club"; it cannot answer "who in this league is a CB over 80" without the
    /// user opening all 32 and reading them, which is the query a GM actually
    /// has. `players` is that query.
    enum BrowseMode: String, CaseIterable, Identifiable {
        case teams = "Teams"
        case players = "Player Search"
        var id: String { rawValue }
    }

    @State private var mode: BrowseMode = .teams
    @State private var searchText: String = ""
    @State private var filterPosition: Position?
    @State private var minOVR: Int = 0
    @State private var maxAge: Int = 0            // 0 == any
    @State private var maxContractYears: Int = 0  // 0 == any
    @State private var expiringOnly: Bool = false

    /// Rows rendered at once. The filter itself is a single O(roster) pass over
    /// the population this screen ALREADY holds for the board (no extra fetch),
    /// but a 1 700-row `ForEach` inside a `ScrollView` builds every row eagerly,
    /// so the list is capped and the overflow is counted instead.
    private static let searchResultCap = 120

    /// The user's saved depth chart, keyed by his `teamID`. Decoded once per
    /// appearance rather than per row: his OWN row must quote the lineup he
    /// actually set, the other 31 fall back to the auto-derived one.
    @State private var userCharts: [UUID: DepthChart] = [:]

    private var conference: Conference {
        pickedConference
            ?? allTeams.first(where: { $0.id == career.teamID })?.conference
            ?? .AFC
    }

    // MARK: - Body

    /// One grouping pass, referenced once per body evaluation: four division
    /// sections each filtering ~2 000 players would be four full scans a redraw.
    private var rostersByTeam: [UUID: [Player]] {
        Dictionary(grouping: allPlayers.filter { $0.teamID != nil }, by: { $0.teamID! })
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            board(rosters: rostersByTeam)
        }
        .navigationTitle("League Rosters")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { userCharts = TeamStrength.savedCharts(for: career) }
    }

    private func board(rosters: [UUID: [Player]]) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                modePicker
                if mode == .teams {
                    conferencePicker
                }
            }
            .padding(16)
            // Same 820pt measure as the division cards below, so the
            // picker's edges line up with them instead of spanning the
            // full iPad width above inset content.
            .frame(maxWidth: DSLayout.wideMeasure)
            .frame(maxWidth: .infinity)
            .background(Color.backgroundSecondary)

            if mode == .teams {
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(Division.allCases, id: \.self) { division in
                            divisionSection(division, rosters: rosters)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: DSLayout.wideMeasure)
                    .frame(maxWidth: .infinity)
                }
            } else {
                playerSearch
            }
        }
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(BrowseMode.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .tint(Color.accentBlue)
    }

    private var conferencePicker: some View {
        Picker(
            "Conference",
            selection: Binding(
                get: { conference },
                set: { pickedConference = $0 }
            )
        ) {
            ForEach(Conference.allCases, id: \.self) { conference in
                Text(conference.rawValue).tag(conference)
            }
        }
        .pickerStyle(.segmented)
        .tint(Color.accentBlue)
    }

    // MARK: - Division Section

    private func divisionSection(_ division: Division, rosters: [UUID: [Player]]) -> some View {
        let teams = allTeams
            .filter { $0.conference == conference && $0.division == division }
            .sorted { lhs, rhs in
                if lhs.wins != rhs.wins { return lhs.wins > rhs.wins }
                if lhs.losses != rhs.losses { return lhs.losses < rhs.losses }
                return lhs.abbreviation < rhs.abbreviation
            }

        return VStack(alignment: .leading, spacing: 10) {
            Text("\(conference.rawValue) \(division.rawValue)")
                .font(.system(size: 12, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(Color.accentGold)

            ForEach(teams) { team in
                NavigationLink {
                    LeagueTeamRosterView(team: team, career: career)
                } label: {
                    teamRow(team, roster: rosters[team.id] ?? [])
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardBackground()
    }

    private func teamRow(_ team: Team, roster: [Player]) -> some View {
        let isUserTeam = team.id == career.teamID
        let strength = startingLineupOverall(roster, chart: userCharts[team.id])
        // The same need model the draft room and the one-team header already
        // use — a club's holes are what makes it a trade partner, and the board
        // is where you decide WHICH club to open. Two chips, not five: the row
        // is a shortlist cue, the roster screen is the detail.
        let needs = DraftEngine.topTeamNeeds(roster: roster, limit: 2)

        return HStack(spacing: 12) {
            Text(team.abbreviation)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 46)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(TeamColors.color(for: team.abbreviation))
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(team.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if isUserTeam {
                        Text("YOUR TEAM")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentGold, in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text("\(team.record) · \(roster.count) players · \(capLabel(team.availableCap)) cap space")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)

                    ForEach(needs, id: \.self) { position in
                        Text(position.rawValue)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.warning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.warning.opacity(0.15), in: Capsule())
                    }
                }
            }

            Spacer(minLength: 4)

            VStack(spacing: 0) {
                Text("\(strength)")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(strength))
                Text("OVR")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 36)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isUserTeam ? Color.accentGold.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - One Team's Roster

/// Another franchise's roster, rendered with the same `PlayerRowView` the user
/// sees on his own team so the comparison is apples to apples. Every row pushes
/// the standard `PlayerDetailView`, which is where the trade proposal starts.
struct LeagueTeamRosterView: View {

    let team: Team
    let career: Career

    @Query private var allPlayersUnscoped: [Player]

    // `@Query` cannot take a runtime predicate built from a stored property,
    // so the store-wide result is narrowed to THIS save here. Without it the
    // screen mixes two careers' populations into one list.
    private var allPlayers: [Player] { allPlayersUnscoped.filter { $0.careerID == career.id } }

    @State private var showTradeCenter = false
    /// The user's saved depth chart, decoded once rather than per body pass.
    @State private var userCharts: [UUID: DepthChart] = [:]

    private var roster: [Player] {
        allPlayers.filter { $0.teamID == team.id }
    }

    private var isUserTeam: Bool { team.id == career.teamID }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                headerSection

                ForEach(RosterView.allPositionGroups) { group in
                    let groupPlayers = roster
                        .filter { group.positions.contains($0.position) }
                        .sorted { $0.overall > $1.overall }
                    if !groupPlayers.isEmpty {
                        Section {
                            ForEach(groupPlayers) { player in
                                // Depth is derived from OVR order at the position
                                // (no depth chart exists for an AI team), which is
                                // what feeds the row's S/B/3 badge.
                                let atPosition = groupPlayers.filter { $0.position == player.position }
                                let starters = PositionGradeCalculator.idealStarterCounts[player.position] ?? 1
                                NavigationLink(destination: PlayerDetailView(player: player)) {
                                    PlayerRowView(
                                        player: player,
                                        depthIndex: atPosition.firstIndex(where: { $0.id == player.id }) ?? 0,
                                        analysisMode: .overview,
                                        positionGroupCount: atPosition.count,
                                        starterCountForPosition: starters,
                                        teamSalaryCap: team.salaryCap
                                    )
                                }
                            }
                        } header: {
                            HStack {
                                Text(group.name.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(0.8)
                                    .foregroundStyle(Color.textSecondary)
                                Spacer()
                                Text("\(groupPlayers.count)")
                                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                        .listRowBackground(Color.backgroundSecondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("\(team.abbreviation) Roster")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { userCharts = TeamStrength.savedCharts(for: career) }
        .toolbar {
            if !isUserTeam {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showTradeCenter = true
                    } label: {
                        Label("Trade", systemImage: "arrow.left.arrow.right")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showTradeCenter) {
            TradeCenterCover(
                career: career,
                prefill: TradeView.Prefill(partnerTeamID: team.id, targetPlayerIDs: [])
            )
        }
    }

    // MARK: Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(team.abbreviation)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 54)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(TeamColors.color(for: team.abbreviation))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(team.fullName)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                        Text("\(team.conference.rawValue) \(team.division.rawValue) · \(team.record)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                }

                HStack(spacing: 0) {
                    headerStat(
                        label: "Starters OVR",
                        value: "\(startingLineupOverall(roster, chart: userCharts[team.id]))"
                    )
                    headerStat(label: "Roster", value: "\(roster.count)")
                    headerStat(label: "Cap Space", value: capLabel(team.availableCap))
                }

                // Their holes, from the same need model the draft room uses —
                // this is what makes them a plausible trade partner for a
                // player the user is shopping.
                let needs = DraftEngine.topTeamNeeds(roster: roster, limit: 3)
                if !needs.isEmpty {
                    HStack(spacing: 6) {
                        Text("NEEDS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                        ForEach(needs, id: \.self) { position in
                            Text(position.rawValue)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.warning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.warning.opacity(0.15), in: Capsule())
                        }
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func headerStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - League Player Search

extension LeagueRostersView {

    /// Every player in the league who is NOT ours, narrowed by the filters.
    ///
    /// COST: one O(n) pass plus a sort over `allPlayers` — the array the board
    /// already derives from the screen's existing `@Query`, so no fetch is added
    /// and the SwiftData store is not touched again per keystroke. At 32 × ~53
    /// that is ~1 700 comparisons, and the result is capped at
    /// `searchResultCap` rows so the `ForEach` never builds a thousand views.
    private var searchResults: [Player] {
        let userTeamID = career.teamID
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let matches = allPlayers.filter { player in
            guard let teamID = player.teamID, teamID != userTeamID else { return false }
            if player.overall < minOVR { return false }
            if maxAge > 0 && player.age > maxAge { return false }
            if let filterPosition, player.position != filterPosition { return false }
            if maxContractYears > 0 && player.contractYearsRemaining > maxContractYears { return false }
            if expiringOnly && player.contractYearsRemaining > 1 { return false }
            if !needle.isEmpty && !player.fullName.lowercased().contains(needle) { return false }
            return true
        }

        return matches.sorted { $0.overall > $1.overall }
    }

    private var teamsByID: [UUID: Team] {
        Dictionary(uniqueKeysWithValues: allTeams.map { ($0.id, $0) })
    }

    private var playerSearch: some View {
        let results = searchResults
        let shown = Array(results.prefix(Self.searchResultCap))
        let lookup = teamsByID

        return VStack(spacing: 0) {
            searchControls

            if shown.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title)
                        .foregroundStyle(Color.textTertiary)
                    Text("No player in the league matches those filters.")
                        .font(.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        HStack {
                            Text(
                                results.count > shown.count
                                    ? "\(shown.count) of \(results.count) matches — narrow the filters to see the rest"
                                    : "\(results.count) match\(results.count == 1 ? "" : "es")"
                            )
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                            Spacer()
                        }
                        .padding(.bottom, 2)

                        ForEach(shown) { player in
                            NavigationLink {
                                PlayerDetailView(player: player)
                            } label: {
                                searchResultRow(player, team: player.teamID.flatMap { lookup[$0] })
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: DSLayout.wideMeasure)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var searchControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.footnote)
                    .foregroundStyle(Color.textTertiary)
                TextField("Search every roster in the league", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterMenu(
                        title: filterPosition?.rawValue ?? "Any POS",
                        isActive: filterPosition != nil
                    ) {
                        Button("Any position") { filterPosition = nil }
                        ForEach(Position.allCases, id: \.self) { position in
                            Button(position.rawValue) { filterPosition = position }
                        }
                    }

                    filterMenu(
                        title: minOVR > 0 ? "\(minOVR)+ OVR" : "Any OVR",
                        isActive: minOVR > 0
                    ) {
                        Button("Any OVR") { minOVR = 0 }
                        ForEach([60, 65, 70, 75, 80, 85, 90], id: \.self) { threshold in
                            Button("\(threshold)+ OVR") { minOVR = threshold }
                        }
                    }

                    filterMenu(
                        title: maxAge > 0 ? "\u{2264} \(maxAge)yr" : "Any age",
                        isActive: maxAge > 0
                    ) {
                        Button("Any age") { maxAge = 0 }
                        ForEach([24, 26, 28, 30, 32], id: \.self) { age in
                            Button("\(age) or younger") { maxAge = age }
                        }
                    }

                    filterMenu(
                        title: maxContractYears > 0 ? "\u{2264} \(maxContractYears)yr deal" : "Any deal",
                        isActive: maxContractYears > 0
                    ) {
                        Button("Any contract") { maxContractYears = 0 }
                        ForEach([1, 2, 3, 4], id: \.self) { years in
                            Button("\(years) year\(years == 1 ? "" : "s") or less") { maxContractYears = years }
                        }
                    }

                    Button {
                        expiringOnly.toggle()
                    } label: {
                        filterChipLabel(title: "Expiring", isActive: expiringOnly)
                    }
                    .buttonStyle(.plain)

                    if hasActiveFilters {
                        Button {
                            filterPosition = nil
                            minOVR = 0
                            maxAge = 0
                            maxContractYears = 0
                            expiringOnly = false
                            searchText = ""
                        } label: {
                            filterChipLabel(title: "Clear", isActive: false, systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: DSLayout.wideMeasure)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary)
    }

    private var hasActiveFilters: Bool {
        filterPosition != nil || minOVR > 0 || maxAge > 0
            || maxContractYears > 0 || expiringOnly || !searchText.isEmpty
    }

    private func filterMenu<Content: View>(
        title: String,
        isActive: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            filterChipLabel(title: title, isActive: isActive, systemImage: "chevron.down")
        }
    }

    private func filterChipLabel(
        title: String,
        isActive: Bool,
        systemImage: String? = nil
    ) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
            }
        }
        .foregroundStyle(isActive ? Color.backgroundPrimary : Color.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(isActive ? Color.accentGold : Color.backgroundTertiary)
        )
    }

    /// One hit. Carries the club, the rating, the age and the money — the four
    /// columns the "who can I get, and can they afford to move him" question
    /// needs before the detail screen is worth opening.
    private func searchResultRow(_ player: Player, team: Team?) -> some View {
        HStack(spacing: 10) {
            Text(team?.abbreviation ?? "FA")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 40)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(TeamColors.color(for: team?.abbreviation ?? ""))
                )

            Text(player.position.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentBlue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(searchRowSubtitle(player, team: team))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(spacing: 0) {
                Text("\(player.overall)")
                    .font(.callout.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(player.overall))
                Text("OVR")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 34)

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundTertiary)
        )
    }

    private func searchRowSubtitle(_ player: Player, team: Team?) -> String {
        var parts = [
            "Age \(player.age)",
            player.contractYearsRemaining <= 1
                ? "expiring"
                : "\(player.contractYearsRemaining)yr",
            capLabel(player.annualSalary),
        ]
        if let team {
            parts.append("\(team.abbreviation) \(capLabel(team.availableCap)) cap")
        }
        if player.isInjured {
            parts.append("INJ \(player.injuryWeeksRemaining)wk")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Trade Center Cover

/// `TradeView` in its own navigation stack, for the entry points that are not
/// the shell's Trade Center route (the league roster browser and the player
/// detail screen both present it modally over their own stack).
///
/// The shell route keeps its `onInboxMessage` hook; here there is no shell in
/// scope, so `TradeView` falls back to staging its receipt in
/// `WeekAdvancer.lastInboxMessages`, which the shell drains on the next
/// week/phase change.
struct TradeCenterCover: View {

    let career: Career
    var prefill: TradeView.Prefill? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TradeView(career: career, prefill: prefill)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Propose Trade Affordance

/// The "Trade For" button on `PlayerDetailView`.
///
/// Self-contained on purpose: it owns the career lookup, the visibility rule and
/// the presentation, so the detail screen only has to hand it a label. Visible
/// ONLY for a player on another club — a player on the user's own roster has no
/// partner to name yet (shopping your own players is the Trade Center's builder,
/// Wave 3's "shop players" flow).
///
/// The `hint` handed to the label is the honest replacement for the old
/// "~6 teams interested" teaser, which was a hardcoded curve over OVR and age
/// that never consulted a single roster.
struct ProposeTradeButton<Label: View>: View {

    let player: Player

    /// The league's players, passed in rather than re-queried: the detail screen
    /// already holds this fetch for its ranking context.
    let leaguePlayers: [Player]

    /// `(hint, openTradeCenter) -> Label` — the caller styles the button, this
    /// view supplies the copy and the action.
    @ViewBuilder var label: (String?, @escaping () -> Void) -> Label

    @Query private var allCareers: [Career]

    @State private var showTradeCenter = false

    /// The save this player belongs to. The row itself names it, so no career
    /// has to be threaded down here — and `allCareers.first` (which used to
    /// answer this) could pick the WRONG save once two exist.
    private var career: Career? { allCareers.first { $0.id == player.careerID } }

    var body: some View {
        if let career,
           let userTeamID = career.teamID,
           let partnerTeamID = player.teamID,
           partnerTeamID != userTeamID {
            label(fitHint(userTeamID: userTeamID)) { showTradeCenter = true }
                .fullScreenCover(isPresented: $showTradeCenter) {
                    TradeCenterCover(
                        career: career,
                        prefill: TradeView.Prefill(
                            partnerTeamID: partnerTeamID,
                            targetPlayerIDs: [player.id]
                        )
                    )
                }
        }
    }

    /// What this player would actually mean for OUR roster: a need filled, a
    /// measurable upgrade on the incumbent, or depth. Computed from public data
    /// (our roster + the shared need model), so it is true for every player.
    private func fitHint(userTeamID: UUID) -> String? {
        let myRoster = leaguePlayers.filter { $0.teamID == userTeamID }
        guard !myRoster.isEmpty else { return nil }

        let incumbent = myRoster
            .filter { $0.position == player.position }
            .max { $0.overall < $1.overall }

        if DraftEngine.topTeamNeeds(roster: myRoster, limit: 5).contains(player.position) {
            return "Fills our \(player.position.rawValue) need"
        }
        guard let incumbent else { return "No \(player.position.rawValue) on roster" }

        let delta = player.overall - incumbent.overall
        if delta >= 3 { return "+\(delta) over \(incumbent.lastName)" }
        if delta > 0  { return "Marginal upgrade (+\(delta))" }
        return "Depth behind \(incumbent.lastName)"
    }
}

// MARK: - Shared Formatting

/// Starting-lineup quality: the mean of the 22 men the lineup actually fields,
/// via `TeamStrength` — the one definition of a team's rating, shared with the
/// depth chart's TEAM pill and the schedule's opponent badge.
///
/// This used to be a private "best 22 by overall" average, which read 3-4
/// points higher than the depth chart for the same club because it never
/// priced a hole: a roster with six good receivers and no left tackle counted
/// the receivers six times and the missing tackle not at all.
private func startingLineupOverall(_ roster: [Player], chart: DepthChart? = nil) -> Int {
    TeamStrength.startersOVR(roster, chart: chart)
}

/// Cap figures are stored in thousands.
private func capLabel(_ thousands: Int) -> String {
    let millions = Double(thousands) / 1_000.0
    if abs(millions) >= 1.0 {
        return String(format: "$%.1fM", millions)
    }
    return "$\(thousands)K"
}
