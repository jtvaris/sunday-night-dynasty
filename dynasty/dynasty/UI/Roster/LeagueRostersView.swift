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
            conferencePicker
                .padding(16)
                // Same 820pt measure as the division cards below, so the
                // picker's edges line up with them instead of spanning the
                // full iPad width above inset content.
                .frame(maxWidth: DSLayout.wideMeasure)
                .frame(maxWidth: .infinity)
                .background(Color.backgroundSecondary)

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
        }
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
                Text("\(team.record) · \(roster.count) players · \(capLabel(team.availableCap)) cap space")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
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
