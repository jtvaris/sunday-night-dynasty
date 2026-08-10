import SwiftUI
import SwiftData

struct TeamSelectionView: View {

    let playerName: String
    let avatarID: String
    let coachingStyle: CoachingStyle
    let selectedRole: CareerRole
    let selectedCapMode: CapMode

    // R40 — Game modes & custom league settings. Defaults preserve the
    // pre-R40 call shape (standard career, normal injury rates).
    var gameMode: CareerGameMode = .standard
    var scenario: CareerScenario? = nil
    var injuryFrequency: InjuryFrequency = .normal

    /// Which league to browse and start (realistic-league phase 3). The default
    /// keeps every existing call site on the classic random path.
    var leagueSource: LeagueSource = .generated

    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selectedCareer: Career?
    @State private var isLoading = false
    @State private var selectedConference: Conference = .AFC
    /// **The one cover slot.** Two sibling `.fullScreenCover` modifiers on one
    /// node cannot both win: the loser of a same-transaction race is dropped
    /// silently. One `item`-driven slot makes the exclusion structural, and the
    /// pending draft rides in the enum rather than in a second `@State` that has
    /// to be timed against the first.
    private enum ActiveCover: Identifiable {
        case teamDetail(NFLTeamDefinition)
        case fantasyDraft(PendingFantasyDraft)

        var id: String {
            switch self {
            case .teamDetail(let team):   return "team-\(team.abbreviation)"
            case .fantasyDraft(let p):    return "fantasy-\(p.id)"
            }
        }
    }

    @State private var activeCover: ActiveCover?
    /// The draft staged by `startCareer` while the detail cover is still on
    /// screen. Handed to the slot from the cover's own `onDismiss`.
    @State private var stagedFantasy: PendingFantasyDraft?
    @State private var situationFilter: String = "All"
    @State private var sortMode: TeamSortMode = .division
    @State private var viewWidth: CGFloat = 0

    // Compare mode (#117 polish): user picks 2-4 teams to compare side-by-side.
    @State private var compareModeOn: Bool = false
    @State private var selectedForCompare: Set<String> = []
    @State private var showCompareSheet: Bool = false

    // R40 — Fantasy Draft hand-off: the generated league waits here (nothing
    // inserted into the model context yet) while the draft screen runs.

    // MARK: - League source state (phase 3)

    /// The team list being browsed. Starts on the static table and is replaced
    /// once a chosen template has decoded.
    @State private var catalog: TeamBrowseCatalog = .generated
    /// The decoded template, kept so career creation imports the very file the
    /// picker was browsing instead of decoding 1.5 MB of JSON a second time.
    @State private var template: LeagueTemplate? = nil
    @State private var isLoadingTemplate = false
    /// Set when a template could not be loaded; the screen then falls back to
    /// the generated league and says so rather than dead-ending.
    @State private var templateLoadError: String? = nil

    /// Un-persisted league snapshot passed into the fantasy draft cover.
    private struct PendingFantasyDraft: Identifiable {
        let id = UUID()
        let career: Career
        let result: LeagueGenerator.GeneratedLeague
        let chosenTeamID: UUID
        /// Career-history rows from a template import (empty for random leagues),
        /// held until the draft finishes and the graph is inserted.
        let seasonHistory: [PlayerSeasonHistory]
    }

    /// iPad always reports .regular for both size classes, so use actual width
    private var isLandscape: Bool { viewWidth > 900 }

    /// The 32 franchises of the league being browsed.
    private var allTeams: [NFLTeamDefinition] { catalog.teams }

    /// Available situation filters.
    private let situationOptions = ["All", "Rebuilding", "Rising", "Contender", "Win Now", "Dynasty"]

    /// Teams for the currently selected conference, filtered and grouped/sorted.
    private var divisionsForConference: [(division: Division, teams: [NFLTeamDefinition])] {
        let conferenceTeams = allTeams.filter { $0.conference == selectedConference }
        let filtered = situationFilter == "All"
            ? conferenceTeams
            : conferenceTeams.filter { catalog.preview(for: $0).situation == situationFilter }
        return Division.allCases.compactMap { division in
            let teams: [NFLTeamDefinition]
            let divTeams = filtered.filter { $0.division == division }
            switch sortMode {
            case .division:
                teams = divTeams.sorted { $0.city < $1.city }
            case .capSpace:
                teams = divTeams.sorted { catalog.preview(for: $0).estimatedCapSpace > catalog.preview(for: $1).estimatedCapSpace }
            case .difficulty:
                teams = divTeams.sorted { catalog.preview(for: $0).difficulty < catalog.preview(for: $1).difficulty }
            case .overall:
                teams = divTeams.sorted { catalog.preview(for: $0).estimatedOVR > catalog.preview(for: $1).estimatedOVR }
            case .wins:
                teams = divTeams.sorted { catalog.preview(for: $0).lastSeasonWins > catalog.preview(for: $1).lastSeasonWins }
            }
            guard !teams.isEmpty else { return nil }
            return (division: division, teams: teams)
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            // Stadium hero photo — clipped to top hero band only so it doesn't
            // bleed beneath the team list. (#117 polish)
            VStack(spacing: 0) {
                GeometryReader { geo in
                    Image("BgStadiumNight")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .overlay(
                            LinearGradient(
                                colors: [.clear, Color.backgroundPrimary.opacity(0.85), Color.backgroundPrimary],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(0.35)
                }
                .frame(height: 180)
                .clipped()
                Spacer(minLength: 0)
            }
            .ignoresSafeArea(edges: .top)

            VStack(spacing: 0) {
                // Which league these 32 teams belong to (phase 3).
                leagueSourceBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Conference tab picker
                conferencePicker
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                // Filter/sort bar (#115) + Compare toggle
                filterSortBar
                    .padding(.bottom, 6)

                // Column header row — labels otherwise-mystery numeric columns
                columnHeaderRow
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)

                // Compact table rows — all 16 teams with minimal scrolling
                ScrollView {
                    if isLandscape {
                        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(divisionsForConference, id: \.division) { group in
                                Section {
                                    ForEach(group.teams, id: \.abbreviation) { team in
                                        teamRowButton(for: team)
                                    }
                                } header: {
                                    divisionHeader(group.division.rawValue)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .frame(maxWidth: DSLayout.gridMeasure)
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(divisionsForConference, id: \.division) { group in
                                divisionHeader(group.division.rawValue)
                                ForEach(group.teams, id: \.abbreviation) { team in
                                    teamRowButton(for: team)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .frame(maxWidth: DSLayout.wideMeasure)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            // Nothing is selectable until the chosen league is ready to browse.
            .disabled(isLoading || isLoadingTemplate)

            // Floating "Compare (n)" button when compare mode is active
            if compareModeOn && selectedForCompare.count >= 2 {
                VStack {
                    Spacer()
                    // §2.8: another hand-rolled gold capsule, retired. It is
                    // still the one gold fill on this surface — it only exists
                    // while compare mode has two teams picked.
                    Button {
                        showCompareSheet = true
                    } label: {
                        Label(
                            "Compare (\(selectedForCompare.count))",
                            systemImage: "rectangle.split.3x1.fill"
                        )
                    }
                    .buttonStyle(.dsPrimary)
                    .dsElevation(.card)
                    .padding(.bottom, DSSpacing.lg)
                }
            }

            if isLoading || isLoadingTemplate {
                ZStack {
                    Color.backgroundPrimary.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Color.accentBlue)
                        Text(isLoadingTemplate
                             ? "Loading \(leagueSource.displayName) League..."
                             : (catalog.source.isTemplate ? "Building League..." : "Generating League..."))
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
        }
        .task { await prepareLeagueSource() }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            viewWidth = newWidth
        }
        .navigationTitle("Choose Your Team")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // ONE cover slot (§2.8 and the sibling-modifier bug class). The detail
        // sheet and the Fantasy Draft used to be two `.fullScreenCover` modifiers
        // on this node, and the second could only be raised from inside the
        // first's dismissal — which is why `startCareer` carried a 0.55 s
        // `asyncAfter` before staging the draft. One slot, and the hand-off is an
        // assignment in `onDismiss` that runs when the cover has actually gone.
        .fullScreenCover(item: $activeCover, onDismiss: handleCoverDismiss) { cover in
            switch cover {
            case .teamDetail(let team):
                NavigationStack {
                    TeamDetailSheet(
                        team: team,
                        catalog: catalog,
                        setupSummary: setupSummary,
                        selectTitle: gameMode == .fantasyDraft ? "START FANTASY DRAFT" : "SELECT THIS TEAM"
                    ) {
                        activeCover = nil
                        startCareer(with: team)
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back") { activeCover = nil }
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .toolbarColorScheme(.dark, for: .navigationBar)
                }

            // R40 — Fantasy Draft runs before anything is persisted; cancelling
            // abandons the un-inserted league and returns to team selection.
            case .fantasyDraft(let pending):
                FantasyDraftView(
                    teams: pending.result.teams,
                    userTeamID: pending.chosenTeamID,
                    poolPlayers: pending.result.players,
                    onComplete: { rosters in
                        completeFantasyDraft(pending: pending, rosters: rosters)
                    },
                    onCancel: { activeCover = nil }
                )
            }
        }
        .navigationDestination(item: $selectedCareer) { career in
            IntroSequenceView(career: career)
        }
        .sheet(isPresented: $showCompareSheet) {
            CompareTeamsSheet(
                teams: allTeams.filter { selectedForCompare.contains($0.abbreviation) },
                catalog: catalog
            )
        }
    }

    /// Hands the cover slot from the team-detail sheet to the Fantasy Draft,
    /// once the first is off screen.
    private func handleCoverDismiss() {
        // CONSUMED, not merely read: this handler also runs when the draft cover
        // itself closes, and a staged value left behind would re-present the
        // draft the user just cancelled — forever.
        guard let pending = stagedFantasy else { return }
        stagedFantasy = nil
        activeCover = .fantasyDraft(pending)
    }

    // MARK: - Row builder (handles compare-mode tap behavior)

    @ViewBuilder
    private func teamRowButton(for team: NFLTeamDefinition) -> some View {
        Button {
            if compareModeOn {
                toggleCompare(team)
            } else {
                activeCover = .teamDetail(team)
            }
        } label: {
            CompactTeamRow(
                team: team,
                preview: catalog.preview(for: team),
                compareModeOn: compareModeOn,
                isSelectedForCompare: selectedForCompare.contains(team.abbreviation)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - League Source Banner (phase 3)

    /// Names the league being browsed, and explains the fallback when a fixed
    /// template could not be loaded.
    @ViewBuilder
    private var leagueSourceBanner: some View {
        if let templateLoadError {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(leagueSource.displayName) league unavailable — starting a Generated league instead.")
                        .font(DSType.text(DSType.Size.footnote, .semibold, prose: true))
                        .foregroundStyle(Color.textPrimary)
                    Text(templateLoadError)
                        .font(DSType.text(DSType.Size.micro, .regular, prose: true))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.warning.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.warning.opacity(0.3), lineWidth: 1)
                    )
            )
        } else {
            // The requested source, not the catalog's: during the template
            // decode the catalog is still the static one, and the banner should
            // already name the league the screen is about to show.
            HStack(spacing: 6) {
                Image(systemName: leagueSource.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(leagueSource.summaryLabel)
                    .font(DSType.display(DSType.Size.footnote, .bold))
                    .tracking(0.5)
                Text(leagueSource.isTemplate
                     ? "Real 2025 records and rosters"
                     : "Freshly rolled rosters")
                    .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                    .foregroundStyle(Color.textTertiary)
                Spacer(minLength: 0)
            }
            .foregroundStyle(leagueSource.isTemplate ? Color.accentGold : Color.accentBlue)
            .accessibilityElement(children: .combine)
        }
    }

    private func toggleCompare(_ team: NFLTeamDefinition) {
        let abbr = team.abbreviation
        if selectedForCompare.contains(abbr) {
            selectedForCompare.remove(abbr)
        } else if selectedForCompare.count < 4 {
            selectedForCompare.insert(abbr)
        }
    }

    // MARK: - Column Header Row (#117 polish)
    /// Lightweight column labels so the numeric columns aren't ambiguous.
    private var columnHeaderRow: some View {
        HStack(spacing: 10) {
            // Aligns with logo + name+QB column on the left of CompactTeamRow.
            Text("TEAM")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("DIFFICULTY")
                .frame(width: 60, alignment: .trailing)
            Text("CAP / STAFF")
                .frame(width: 64, alignment: .center)
            Text("OWNER")
                .frame(width: 42, alignment: .center)
            Spacer().frame(width: 16) // matches chevron column
        }
        .font(DSType.display(DSType.Size.caption, .heavy))
        .tracking(1.2)
        // R39 device coverage: "DIFFICULTY" wrapped to "DIFFICULT/Y" inside
        // its 60 pt column on iPad mini — scale down instead of wrapping.
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundStyle(Color.textTertiary)
        .padding(.leading, 56) // skip past logo
    }

    // MARK: - Filter/Sort Bar (#115)

    private var filterSortBar: some View {
        HStack(spacing: 12) {
            // Situation filter
            Menu {
                ForEach(situationOptions, id: \.self) { option in
                    Button {
                        situationFilter = option
                    } label: {
                        HStack {
                            Text(option)
                            if situationFilter == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .semibold))
                    Text(situationFilter == "All" ? "Filter" : situationFilter)
                        .font(DSType.text(DSType.Size.footnote, .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(situationFilter == "All" ? Color.textSecondary : Color.accentBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(situationFilter == "All" ? Color.backgroundSecondary : Color.accentBlue.opacity(0.15))
                        .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 0.5))
                )
            }

            // Sort mode
            Menu {
                ForEach(TeamSortMode.allCases, id: \.self) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        HStack {
                            Text(mode.label)
                            if sortMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                    Text(sortMode.label)
                        .font(DSType.text(DSType.Size.footnote, .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(sortMode == .division ? Color.textSecondary : Color.accentBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(sortMode == .division ? Color.backgroundSecondary : Color.accentBlue.opacity(0.15))
                        .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 0.5))
                )
            }

            Spacer()

            // Compare-mode toggle (#117 polish)
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    compareModeOn.toggle()
                    if !compareModeOn {
                        selectedForCompare.removeAll()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: compareModeOn ? "checkmark.square.fill" : "square.grid.2x2")
                        .font(.system(size: 11, weight: .semibold))
                    Text(compareModeOn ? "Compare On" : "Compare")
                        .font(DSType.text(DSType.Size.footnote, .semibold))
                }
                .foregroundStyle(compareModeOn ? Color.accentBlue : Color.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(compareModeOn ? Color.accentBlue.opacity(0.15) : Color.backgroundSecondary)
                        .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(compareModeOn ? "Compare mode on" : "Enter compare mode")
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Conference Picker

    private var conferencePicker: some View {
        HStack(spacing: 0) {
            ForEach(Conference.allCases, id: \.self) { conference in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedConference = conference
                    }
                } label: {
                    // Team-count chip beside the conference name (persona audit).
                    HStack(spacing: 6) {
                        Text(conference.rawValue)
                            .font(DSType.display(DSType.Size.callout, .black))
                            .tracking(2)
                        Text("\(allTeams.filter { $0.conference == conference }.count)")
                            .font(DSType.display(DSType.Size.caption, .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(selectedConference == conference ? Color.white.opacity(0.28) : Color.backgroundTertiary)
                            )
                    }
                    .foregroundStyle(selectedConference == conference ? Color.backgroundPrimary : Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedConference == conference ? Color.accentBlue : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .frame(maxWidth: 400)
    }

    // MARK: - Division Header

    private func divisionHeader(_ name: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)
            Text(name)
                .font(DSType.display(DSType.Size.footnote, .bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Color.textSecondary)
                .layoutPriority(1)
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Setup Summary (R40)

    /// One-line recap of the chosen mode + league settings, shown on the
    /// team confirmation sheet so the final step confirms the full setup.
    private var setupSummary: String {
        var parts: [String] = []
        parts.append(catalog.source.summaryLabel)
        switch gameMode {
        case .standard:
            parts.append(scenario.map { "\($0.displayName) Scenario" } ?? "Standard Career")
        case .fantasyDraft:
            parts.append("Fantasy Draft")
        }
        parts.append("\(selectedCapMode.rawValue) Cap")
        parts.append(injuryFrequency == .off ? "Injuries Off" : "\(injuryFrequency.displayName) Injuries")
        return parts.joined(separator: " \u{2022} ")
    }

    // MARK: - League Source (phase 3)

    /// Decodes the chosen fixed template, once, before the list is browsable.
    ///
    /// The decode (1.5 MB publish / 2.6 MB dev) runs off the main actor so the
    /// picker never stalls mid-animation. A failure is not fatal: the screen
    /// falls back to the generated league, says so in the banner, and career
    /// creation follows `catalog.source` — never the requested source — so what
    /// gets persisted is always what was actually built.
    private func prepareLeagueSource() async {
        guard let profile = leagueSource.templateProfile else {
            catalog = .generated
            return
        }
        // Already decoded (the view can re-appear after the detail cover).
        guard template == nil else { return }

        isLoadingTemplate = true
        let outcome: Result<LeagueTemplate, Error> = await Task.detached(priority: .userInitiated) {
            Result { try LeagueTemplateLoader.load(profile) }
        }.value
        isLoadingTemplate = false

        switch outcome {
        case .success(let loaded):
            template = loaded
            catalog = .template(loaded, source: leagueSource)
            templateLoadError = nil
        case .failure(let error):
            template = nil
            catalog = .generated
            templateLoadError = error.localizedDescription
        }
    }

    // MARK: - Start Career

    private func startCareer(with teamDef: NFLTeamDefinition) {
        isLoading = true

        let career = Career(
            playerName: playerName,
            avatarID: avatarID,
            coachingStyle: coachingStyle,
            role: selectedRole,
            capMode: selectedCapMode
        )
        // R40 — persist the game mode & custom league settings.
        career.gameMode = gameMode
        career.scenario = scenario
        career.injuryFrequency = injuryFrequency

        // Phase 4 faces: bind the library to the new career with an EMPTY
        // registry BEFORE the league is built, so every player and coach
        // created below is reserved against this career and nothing leaks in
        // from a previously played one.
        FaceLibrary.shared.beginNewCareer(career)

        // Fixed template vs. random roll. Either way the whole graph is built
        // here and inserted here only: a template career is imported exactly
        // once and then lives in the save file like any other, so nothing is
        // regenerated on later launches. `leagueSource` is written inside the
        // branch that actually ran, so the persisted provenance can never claim
        // a template the screen failed to load.
        let result: LeagueGenerator.GeneratedLeague
        let seasonHistory: [PlayerSeasonHistory]
        if catalog.source.isTemplate, let template {
            let imported = LeagueGenerator.generateFromTemplate(
                template, startYear: career.currentSeason
            )
            result = imported.generated
            seasonHistory = imported.seasonHistory
            career.leagueSource = catalog.source
        } else {
            result = LeagueGenerator.generate(startYear: career.currentSeason)
            // The generator rolls rosters but no past, so the career table (and
            // every engine that reads history) would open on a league where
            // nobody had played a game. Synthesize a backstory instead.
            seasonHistory = LeagueGenerator.syntheticCareerHistory(
                players: result.players, startYear: career.currentSeason
            )
            career.leagueSource = .generated
        }

        // Find the team matching the selected definition.
        let chosenTeam = result.teams.first { $0.abbreviation == teamDef.abbreviation }

        career.leagueID = result.league.id
        career.teamID = chosenTeam?.id

        // R40 — scenario starts re-parametrize the generated league (roster
        // strength, owner traits, pick ownership, cap sheet) before insertion.
        if let scenario, let chosenTeam, let owner = chosenTeam.owner {
            CareerScenarioApplier.apply(
                scenario,
                chosenTeam: chosenTeam,
                owner: owner,
                teamPlayers: result.players.filter { $0.teamID == chosenTeam.id },
                draftPicks: result.draftPicks,
                allTeams: result.teams
            )
        }

        // R40 — Fantasy Draft: pool every player and run the draft screen
        // before anything is persisted. Standard mode finalizes immediately.
        if gameMode == .fantasyDraft, let chosenTeam {
            for player in result.players { player.teamID = nil }
            for team in result.teams {
                team.players = []
                team.currentCapUsage = 0
            }
            isLoading = false
            let pending = PendingFantasyDraft(
                career: career,
                result: result,
                chosenTeamID: chosenTeam.id,
                seasonHistory: seasonHistory
            )
            // The detail cover is on its way out; the slot is handed over in
            // `handleCoverDismiss`, which fires once it has actually gone. No
            // timer — the 0.55 s guess this replaces was too long on a fast
            // device and too short on a loaded one.
            stagedFantasy = pending
            return
        }

        finalizeCareer(
            career: career,
            result: result,
            chosenTeamID: chosenTeam?.id,
            seasonHistory: seasonHistory
        )
    }

    /// R40 — Fantasy Draft completion: assign rosters, regenerate OVR-based
    /// contracts (cap-mode compatible), then persist the league as usual.
    private func completeFantasyDraft(pending: PendingFantasyDraft, rosters: [UUID: [Player]]) {
        for team in pending.result.teams {
            let drafted = rosters[team.id] ?? []
            for player in drafted {
                player.teamID = team.id
                let contract = FantasyDraftEngine.fantasyContract(
                    overall: player.overall,
                    age: player.age,
                    position: player.position
                )
                player.annualSalary = contract.salary
                player.contractYearsRemaining = contract.years
            }
            team.players = drafted
            team.currentCapUsage = FantasyDraftEngine.normalizeSalaries(
                for: drafted,
                cap: team.salaryCap
            )
        }

        stagedFantasy = nil
        activeCover = nil
        finalizeCareer(
            career: pending.career,
            result: pending.result,
            chosenTeamID: pending.chosenTeamID,
            seasonHistory: pending.seasonHistory
        )
    }

    /// Shared tail of career creation: strips the user team's coaching staff
    /// (the wizard guides hiring), inserts the whole generated graph, resets
    /// per-career flags, and navigates to the intro sequence.
    private func finalizeCareer(
        career: Career,
        result: LeagueGenerator.GeneratedLeague,
        chosenTeamID: UUID?,
        seasonHistory: [PlayerSeasonHistory] = []
    ) {
        // Bug fix #2: Player's team starts with NO coaches — the wizard guides
        // them to hire staff first. Remove all coaches from the chosen team only.
        if let chosenTeamID {
            for coach in result.coaches where coach.teamID == chosenTeamID {
                coach.teamID = nil
            }
        }

        // Phase 4 faces: the random generator already assigned inside
        // `LeagueGenerator.generate`; this idempotent pass is what gives a
        // TEMPLATE-imported league its portraits (and covers the fantasy-draft
        // detour, which re-enters here after the draft screen).
        FaceLibrary.shared.backfill(players: result.players, coaches: result.coaches)
        #if DEBUG
        // Uniqueness gate on the league that is about to be persisted — this is
        // the one call site both league sources (and the fantasy-draft detour)
        // funnel through, so it covers the template import too.
        FaceLibrary.shared.debugAuditActiveFaces(
            players: result.players,
            coaches: result.coaches,
            label: "career-start/\(career.leagueSource.rawValue)"
        )
        #endif

        // MULTI-SAVE ISOLATION: every row this career owns is stamped with the
        // career's id BEFORE it reaches the store. This is the single funnel all
        // three creation paths (generated league, template import, fantasy-draft
        // detour) pass through, so nothing can enter unscoped.
        let careerID = career.id
        career.schemaBackfillVersion = CareerScope.currentBackfillVersion
        CareerScope.stamp(result.league, careerID: careerID)
        CareerScope.stamp(result.teams, careerID: careerID)
        CareerScope.stamp(result.players, careerID: careerID)
        CareerScope.stamp(result.owners, careerID: careerID)
        CareerScope.stamp(result.coaches, careerID: careerID)
        CareerScope.stamp(result.draftPicks, careerID: careerID)
        CareerScope.stamp(seasonHistory, careerID: careerID)

        // Insert all generated objects into the model context.
        modelContext.insert(career)
        modelContext.insert(result.league)

        for team in result.teams {
            modelContext.insert(team)
        }
        for player in result.players {
            modelContext.insert(player)
        }
        for owner in result.owners {
            modelContext.insert(owner)
        }
        for coach in result.coaches {
            modelContext.insert(coach)
        }
        for pick in result.draftPicks {
            modelContext.insert(pick)
        }
        // Template leagues arrive with career history: the per-season OVR arcs
        // the transform baked, so player cards and HOF logic have a past from
        // day one. Empty for a generated league.
        for history in seasonHistory {
            modelContext.insert(history)
        }

        // Career-state AppStorage is namespaced per save (see
        // `CareerScopedDefaults`), so a brand-new career simply starts from an
        // empty namespace — the old global reset would have wiped the OTHER
        // save's roster notes and prospect board.
        CareerScopedDefaults.purge(careerID: careerID)
        // Process-global engine caches (draft class, trade caps, wasFired, …)
        // belong to whichever career last ran; a new save must not inherit them.
        WeekAdvancer.resetProcessStateForCareerSwitch()

        isLoading = false
        selectedCareer = career
    }
}

// MARK: - Identifiable conformance for sheet

extension NFLTeamDefinition: Identifiable {
    var id: String { abbreviation }
}

// MARK: - Compact Team Row

private struct CompactTeamRow: View {
    let team: NFLTeamDefinition
    /// Scouting numbers for the league being browsed — static table for a
    /// generated league, template-derived for a fixed one.
    let preview: TeamPreview
    var compareModeOn: Bool = false
    var isSelectedForCompare: Bool = false

    private var difficultyColor: Color {
        switch preview.difficulty {
        case 1, 2: return .success
        case 3:    return .accentBlue
        case 4:    return .warning
        case 5:    return .danger
        default:   return .textSecondary
        }
    }

    private var ownerPatienceColor: Color {
        switch preview.ownerPatience {
        case "Very Patient": return .success
        case "Patient":      return .success.opacity(0.8)
        case "Moderate":     return .accentBlue
        case "Demanding":    return .warning
        case "Win Now":      return .danger
        default:             return .textSecondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // Compare-mode checkbox (replaces chevron affordance during compare).
            if compareModeOn {
                Image(systemName: isSelectedForCompare ? "checkmark.square.fill" : "square")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelectedForCompare ? Color.accentBlue : Color.textTertiary)
                    .frame(width: 22)
            }

            // Team logo placeholder (with lock overlay if locked)
            ZStack(alignment: .bottomTrailing) {
                TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 36)

                if preview.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(3)
                        .background(Circle().fill(Color.textTertiary))
                        .offset(x: 4, y: 4)
                }
            }

            // Team name + city + record + QB (#113)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(team.name)
                        .font(DSType.text(DSType.Size.body, .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(preview.lastSeasonRecord)
                        .font(DSType.display(DSType.Size.caption, .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                HStack(spacing: 6) {
                    Text(team.city)
                        .font(DSType.text(DSType.Size.caption, .regular))
                        .foregroundStyle(Color.textSecondary)
                    Text("\u{2022}")
                        .font(DSType.text(DSType.Size.micro, .regular))
                        .foregroundStyle(Color.textTertiaryReadable)
                    Text(preview.startingQBName)
                        .font(DSType.text(DSType.Size.micro, .medium))
                        .foregroundStyle(Color.textSecondary)
                    Text("\(preview.startingQBOverall)")
                        .font(DSType.display(DSType.Size.micro, .bold))
                        .foregroundStyle(Color.forRating(preview.startingQBOverall))
                }
            }
            .frame(minWidth: 130, alignment: .leading)

            Spacer(minLength: 4)

            // Difficulty stars (single source-of-truth — tier label removed to
            // de-duplicate signal, per #117 polish).
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundStyle(star <= preview.difficulty ? difficultyColor : Color.textTertiary.opacity(0.3))
                }
            }
            .frame(width: 60, alignment: .trailing)

            // Cap + Coaching budget combined column (#112, #114)
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Text("CAP")
                        .font(DSType.display(DSType.Size.micro, .bold))
                        .foregroundStyle(Color.textTertiaryReadable)
                    Text("$\(preview.estimatedCapSpace)M")
                        .font(DSType.display(DSType.Size.caption, .bold))
                        .foregroundStyle(preview.estimatedCapSpace > 30 ? Color.success : preview.estimatedCapSpace > 15 ? Color.accentBlue : Color.warning)
                }
                HStack(spacing: 3) {
                    Text("STF")
                        .font(DSType.display(DSType.Size.micro, .bold))
                        .foregroundStyle(Color.textTertiaryReadable)
                    Text("$\(preview.coachingBudget)M")
                        .font(DSType.display(DSType.Size.micro, .semibold))
                        .foregroundStyle(preview.coachingBudget >= 40 ? Color.success : preview.coachingBudget >= 30 ? Color.accentBlue : Color.warning)
                }
            }
            .frame(width: 64)

            // Owner patience icon + seasons (#112 widened)
            VStack(spacing: 1) {
                Image(systemName: preview.ownerPatienceIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(ownerPatienceColor)
                Text("\(preview.patienceSeasons)yr")
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 42)

            if !compareModeOn {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 16)
            } else {
                Color.clear.frame(width: 16)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelectedForCompare ? Color.accentBlue.opacity(0.12) : Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelectedForCompare ? Color.accentBlue.opacity(0.7) : Color.surfaceBorder, lineWidth: isSelectedForCompare ? 1 : 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(team.city) \(team.name), \(preview.lastSeasonRecord), \(preview.situation), difficulty \(preview.difficulty) of 5, QB \(preview.startingQBName) \(preview.startingQBOverall) OVR\(preview.isLocked ? ", locked" : "")\(compareModeOn ? (isSelectedForCompare ? ", selected for compare" : ", not selected") : "")")
    }
}

// MARK: - Mini Team Card (fits 16 teams on screen)

private struct MiniTeamCard: View {
    let team: NFLTeamDefinition
    var height: CGFloat = 140
    private var preview: TeamPreview { team.preview }

    private var situationColor: Color {
        // 3-tier color system (persona audit): blue = building, green = ascending,
        // gold = competing. Amber/red stay reserved for warnings and dangers.
        switch preview.situation {
        case "Rebuilding":                      return .accentBlue
        case "Rising":                          return .success
        case "Contender", "Win Now", "Dynasty": return .accentGold
        default:                                return .textSecondary
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            // Logo
            TeamLogoPlaceholder(abbreviation: team.abbreviation, size: min(36, height * 0.28))

            // Name
            Text(team.name)
                .font(.system(size: min(13, height * 0.1), weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            // City
            Text(team.city)
                .font(.system(size: min(10, height * 0.07)))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            // Stars
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                        .font(.system(size: min(7, height * 0.05)))
                        .foregroundStyle(star <= preview.difficulty ? Color.warning : Color.textTertiary)
                }
            }

            // Situation
            Text(preview.situation.uppercased())
                .font(.system(size: min(8, height * 0.06), weight: .bold))
                .foregroundStyle(situationColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Team Grid Card (compact card for 2x2 / 4-column grid)

private struct TeamGridCard: View {
    let team: NFLTeamDefinition
    private var preview: TeamPreview { team.preview }

    private var situationColor: Color {
        // 3-tier color system (persona audit): blue = building, green = ascending,
        // gold = competing. Amber/red stay reserved for warnings and dangers.
        switch preview.situation {
        case "Rebuilding":                      return .accentBlue
        case "Rising":                          return .success
        case "Contender", "Win Now", "Dynasty": return .accentGold
        default:                                return .textSecondary
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Logo + name
            TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 44)

            Text(team.name)
                .font(DSType.text(DSType.Size.body, .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(team.city)
                .font(DSType.text(DSType.Size.caption, .regular))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            // Difficulty stars
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(star <= preview.difficulty ? Color.warning : Color.textTertiary)
                }
            }

            // Situation badge
            Text(preview.situation.uppercased())
                .font(DSType.display(DSType.Size.caption, .bold))
                .tracking(0.5)
                .foregroundStyle(situationColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(situationColor.opacity(0.15))
                )

            // Cap space
            Text("$\(preview.estimatedCapSpace)M cap")
                .font(DSType.display(DSType.Size.micro, .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(DSSpacing.sm)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.card)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Team Logo Placeholder

struct TeamLogoPlaceholder: View {
    let abbreviation: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(TeamColors.color(for: abbreviation))
            Text(abbreviation)
                .font(.system(size: size * 0.33, weight: .black))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Team Colors

enum TeamColors {
    static func color(for abbreviation: String) -> Color {
        switch abbreviation {
        // AFC East
        case "BUF": return Color(red: 0.00, green: 0.20, blue: 0.55)  // Bills blue
        case "MIA": return Color(red: 0.00, green: 0.55, blue: 0.55)  // Dolphins teal
        case "NE":  return Color(red: 0.00, green: 0.13, blue: 0.27)  // Patriots navy
        case "NYJ": return Color(red: 0.07, green: 0.31, blue: 0.17)  // Jets green

        // AFC North
        case "BAL": return Color(red: 0.14, green: 0.03, blue: 0.33)  // Ravens purple
        case "CIN": return Color(red: 0.98, green: 0.31, blue: 0.08)  // Bengals orange
        case "CLE": return Color(red: 0.80, green: 0.33, blue: 0.00)  // Browns orange
        case "PIT": return Color(red: 0.10, green: 0.10, blue: 0.10)  // Steelers black

        // AFC South
        case "HOU": return Color(red: 0.01, green: 0.08, blue: 0.25)  // Texans navy
        case "IND": return Color(red: 0.00, green: 0.17, blue: 0.53)  // Colts blue
        case "JAX": return Color(red: 0.00, green: 0.40, blue: 0.47)  // Jaguars teal
        case "TEN": return Color(red: 0.27, green: 0.46, blue: 0.70)  // Titans blue

        // AFC West
        case "DEN": return Color(red: 0.98, green: 0.31, blue: 0.08)  // Broncos orange
        case "KC":  return Color(red: 0.89, green: 0.09, blue: 0.14)  // Chiefs red
        case "LV":  return Color(red: 0.10, green: 0.10, blue: 0.10)  // Raiders black
        case "LAC": return Color(red: 0.00, green: 0.30, blue: 0.57)  // Chargers blue

        // NFC East
        case "DAL": return Color(red: 0.00, green: 0.21, blue: 0.47)  // Cowboys blue
        case "NYG": return Color(red: 0.01, green: 0.14, blue: 0.42)  // Giants blue
        case "PHI": return Color(red: 0.00, green: 0.30, blue: 0.22)  // Eagles green
        case "WAS": return Color(red: 0.39, green: 0.09, blue: 0.14)  // Commanders burgundy

        // NFC North
        case "CHI": return Color(red: 0.05, green: 0.13, blue: 0.24)  // Bears navy
        case "DET": return Color(red: 0.00, green: 0.42, blue: 0.69)  // Lions blue
        case "GB":  return Color(red: 0.12, green: 0.23, blue: 0.15)  // Packers green
        case "MIN": return Color(red: 0.31, green: 0.15, blue: 0.51)  // Vikings purple

        // NFC South
        case "ATL": return Color(red: 0.65, green: 0.07, blue: 0.11)  // Falcons red
        case "CAR": return Color(red: 0.00, green: 0.52, blue: 0.72)  // Panthers blue
        case "NO":  return Color(red: 0.82, green: 0.68, blue: 0.33)  // Saints gold
        case "TB":  return Color(red: 0.82, green: 0.10, blue: 0.11)  // Buccaneers red

        // NFC West
        case "ARI": return Color(red: 0.60, green: 0.09, blue: 0.16)  // Cardinals red
        case "LAR": return Color(red: 0.00, green: 0.21, blue: 0.53)  // Rams blue
        case "SF":  return Color(red: 0.67, green: 0.15, blue: 0.15)  // 49ers red
        case "SEA": return Color(red: 0.00, green: 0.13, blue: 0.26)  // Seahawks navy

        default:    return Color(red: 0.30, green: 0.30, blue: 0.35)
        }
    }
}

// MARK: - Team Detail Sheet

private struct TeamDetailSheet: View {
    let team: NFLTeamDefinition
    /// The league being browsed — supplies this team's preview and its rivals.
    let catalog: TeamBrowseCatalog
    /// R40 — one-line mode + league-settings recap above the confirm button.
    var setupSummary: String = ""
    /// R40 — confirm-button title (fantasy draft changes the next step).
    var selectTitle: String = "SELECT THIS TEAM"
    let onSelect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewWidth: CGFloat = 0

    private var isLandscape: Bool { viewWidth > 900 }

    private var preview: TeamPreview { catalog.preview(for: team) }

    private var situationColor: Color {
        // 3-tier color system (persona audit): blue = building, green = ascending,
        // gold = competing. Amber/red stay reserved for warnings and dangers.
        switch preview.situation {
        case "Rebuilding":                      return .accentBlue
        case "Rising":                          return .success
        case "Contender", "Win Now", "Dynasty": return .accentGold
        default:                                return .textSecondary
        }
    }

    private var difficultyColor: Color {
        switch preview.difficulty {
        case 1, 2: return .success
        case 3:    return .accentBlue
        case 4:    return .warning
        case 5:    return .danger
        default:   return .textSecondary
        }
    }

    private var ownerPatienceColor: Color {
        switch preview.ownerPatience {
        case "Very Patient": return .success
        case "Patient":      return .success.opacity(0.8)
        case "Moderate":     return .accentBlue
        case "Demanding":    return .warning
        case "Win Now":      return .danger
        default:             return .textSecondary
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            GeometryReader { geo in
                Image("BgLockerRoom2")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.15)
            }
            .ignoresSafeArea()

            ScrollView {
                if isLandscape {
                    landscapeDetailContent
                } else {
                    portraitDetailContent
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newWidth in
            viewWidth = newWidth
        }
        // §2.5: the commit surface. This was a full-width gold slab with its own
        // `cornerRadius: 12` recipe — the third hand-copy of the same button —
        // sitting under a centred grey recap line that had no visible connection
        // to it. `DSActionBar` says the same two things in the app's own grammar:
        // the R40 setup recap becomes the explainer that states what committing
        // does, and the commit itself is the one gold fill on the screen.
        .safeAreaInset(edge: .bottom) {
            DSActionBar(
                explainer: setupSummary.isEmpty
                    ? nil
                    : .init(title: "Starting this career", message: setupSummary),
                primary: .init(title: selectTitle, handler: onSelect)
            )
        }
    }

    /// §2.9: section heads are uppercase, tracked, 11 pt — and `textSecondary`,
    /// never gold.
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(DSType.display(DSType.Size.caption, .heavy))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(Color.textSecondary)
    }

    private func detailStat(icon: String, label: String, value: String, valueColor: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                Text(label)
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(value)
                // Promoted: these three numbers are the core decision data (audit).
                .font(DSType.display(DSType.Size.title2, .black))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Detail Header

    private var detailHeader: some View {
        VStack(spacing: 12) {
            // Framed logo — subtle plate + ring + shadow so the team identity
            // anchors the screen instead of sinking into the background (audit).
            TeamLogoPlaceholder(abbreviation: team.abbreviation, size: isLandscape ? 56 : 72)
                .padding(7)
                .background(Circle().fill(Color.backgroundSecondary))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.45), radius: 10, y: 4)

            Text("\(team.city) \(team.name)")
                .font(DSType.display(isLandscape ? DSType.Size.title2 : DSType.Size.title1, .black))
                .foregroundStyle(Color.textPrimary)

            Text("\(team.conference.rawValue) \(team.division.rawValue)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textSecondary)

            Text("Last Season: \(preview.lastSeasonRecord)")
                .font(DSType.display(DSType.Size.body, .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.top, isLandscape ? 12 : 24)
    }

    // MARK: - Difficulty + Situation

    private var difficultySituationRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 24) {
                VStack(spacing: 6) {
                    // Scale label so the stars aren't mistaken for talent/prestige (audit).
                    Text("CAREER DIFFICULTY")
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .tracking(1.2)
                        .foregroundStyle(Color.textTertiary)
                    HStack(spacing: 3) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                                .font(.system(size: 14))
                                .foregroundStyle(star <= preview.difficulty ? difficultyColor : Color.textTertiary.opacity(0.4))
                        }
                    }
                    Text(preview.difficultyLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(difficultyColor)
                }

                Text(preview.situation)
                    .font(DSType.display(DSType.Size.body, .bold))
                    .textCase(.uppercase)
                    .foregroundStyle(situationColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(situationColor.opacity(0.15))
                    )
            }

            // One-line rationale so "Easy"/"Hard" isn't an unexplained verdict (audit).
            Text("Difficulty weighs roster talent, cap room, and draft capital.")
                .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Info Cards

    private var ownerExpectationsCard: some View {
        VStack(spacing: 8) {
            sectionLabel(String(localized: "Owner Expectations"))

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: preview.ownerPatienceIcon)
                        .font(.system(size: 14))
                        .foregroundStyle(ownerPatienceColor)
                    Text(preview.ownerPatience)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ownerPatienceColor)
                }

                Text("\(preview.patienceSeasons) season\(preview.patienceSeasons == 1 ? "" : "s") tolerance")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private var marketMediaCard: some View {
        VStack(spacing: 8) {
            sectionLabel(String(localized: "Market & Media"))

            Text(preview.marketDescription)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private var statsRow: some View {
        HStack(spacing: 0) {
            detailStat(
                icon: "chart.bar.fill",
                label: "Roster OVR",
                value: "\(preview.estimatedOVR)",
                valueColor: Color.forRating(preview.estimatedOVR)
            )
            detailStat(
                icon: "dollarsign.circle.fill",
                label: "Cap Space",
                value: "$\(preview.estimatedCapSpace)M",
                valueColor: preview.estimatedCapSpace > 30 ? .success : preview.estimatedCapSpace > 15 ? .accentBlue : .warning
            )
            detailStat(
                icon: "doc.text.fill",
                label: "Draft Picks",
                value: "\(preview.estimatedDraftPicks)",
                valueColor: preview.estimatedDraftPicks >= 9 ? .success : preview.estimatedDraftPicks >= 7 ? .textPrimary : .warning
            )
        }
        .padding(.vertical, 14)
        .cardBackground()
    }

    // MARK: - Starting QB Card

    private var startingQBCard: some View {
        VStack(spacing: 8) {
            sectionLabel(String(localized: "Starting Quarterback"))

            HStack(spacing: 12) {
                Image(systemName: "figure.american.football")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.startingQBName)
                        .font(DSType.text(DSType.Size.callout, .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("QB")
                        .font(DSType.display(DSType.Size.caption, .semibold))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(preview.startingQBOverall)")
                        .font(DSType.display(DSType.Size.title2, .black))
                        .foregroundStyle(Color.forRating(preview.startingQBOverall))
                    Text("OVR")
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    // MARK: - Division Rivals Card

    private var divisionRivals: [NFLTeamDefinition] {
        catalog.divisionRivals(of: team)
    }

    private var divisionRivalsCard: some View {
        VStack(spacing: 8) {
            sectionLabel(String(localized: "Division Rivals"))

            VStack(spacing: 6) {
                ForEach(divisionRivals, id: \.abbreviation) { rival in
                    let rivalPreview = catalog.preview(for: rival)
                    HStack(spacing: 10) {
                        TeamLogoPlaceholder(abbreviation: rival.abbreviation, size: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(rival.city) \(rival.name)")
                                .font(DSType.text(DSType.Size.body, .semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text(rivalPreview.lastSeasonRecord)
                                .font(DSType.display(DSType.Size.caption, .semibold))
                                .foregroundStyle(Color.textTertiary)
                        }

                        Spacer()

                        // Rival roster strength — makes the card read as "how tough
                        // is my division" instead of filler (audit).
                        VStack(spacing: 1) {
                            Text("\(rivalPreview.estimatedOVR)")
                                .font(DSType.display(DSType.Size.body, .black))
                                .foregroundStyle(Color.forRating(rivalPreview.estimatedOVR))
                            Text("OVR")
                                .font(DSType.display(DSType.Size.micro, .bold))
                                .foregroundStyle(Color.textTertiary)
                        }

                        Text(rivalPreview.situation.uppercased())
                            .font(DSType.display(DSType.Size.caption, .bold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.surfaceBorder)
                            )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    /// League-average coaching budget across the 32 teams of the league being
    /// browsed — gives the raw "$NNM" figure a comparison anchor (audit).
    private var leagueAvgCoachingBudget: Int {
        catalog.averageCoachingBudget
    }

    private var coachingBudgetCard: some View {
        VStack(spacing: 8) {
            sectionLabel(String(localized: "Coaching Budget"))

            HStack(spacing: 8) {
                Image(systemName: "dollarsign.square.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(preview.coachingBudget >= 40 ? Color.success : preview.coachingBudget >= 30 ? Color.accentBlue : Color.warning)
                Text("$\(preview.coachingBudget)M")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(preview.coachingBudget >= 40 ? Color.success : preview.coachingBudget >= 30 ? Color.accentBlue : Color.warning)
                Text("for coaching & scouting staff")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            Text("League average: $\(leagueAvgCoachingBudget)M")
                .font(DSType.display(DSType.Size.caption, .semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    // MARK: - Locked Team Banner

    @ViewBuilder
    private var lockedBanner: some View {
        if preview.isLocked {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.warning)
                Text("Complete one full season to unlock this team")
                    .font(DSType.text(DSType.Size.footnote, .medium, prose: true))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.warning.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.warning.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Portrait Layout

    private var portraitDetailContent: some View {
        VStack(spacing: 24) {
            detailHeader
            lockedBanner
            difficultySituationRow
            // Franchise vitals promoted directly under the header — the three
            // most decision-critical numbers read first (audit).
            statsRow
            startingQBCard
            ownerExpectationsCard
            marketMediaCard
            coachingBudgetCard
            divisionRivalsCard
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Landscape Layout

    private var landscapeDetailContent: some View {
        VStack(spacing: 16) {
            detailHeader
            lockedBanner
            difficultySituationRow

            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                // Franchise vitals first — most decision-critical numbers (audit).
                statsRow
                startingQBCard
                ownerExpectationsCard
                marketMediaCard
                coachingBudgetCard
                divisionRivalsCard
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: DSLayout.wideMeasure)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Team Sort Mode (#115)

private enum TeamSortMode: String, CaseIterable {
    case division, capSpace, difficulty, overall, wins

    var label: String {
        switch self {
        case .division:  return "Division"
        case .capSpace:  return "Cap Space"
        case .difficulty: return "Difficulty"
        case .overall:   return "Overall"
        case .wins:      return "Wins"
        }
    }
}

// MARK: - Compare Teams Sheet (#117 polish)

private struct CompareTeamsSheet: View {
    let teams: [NFLTeamDefinition]
    /// The league being compared — supplies each column's preview numbers.
    let catalog: TeamBrowseCatalog

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header row: team logos + names
                        HStack(alignment: .top, spacing: 0) {
                            rowLabel("")
                            ForEach(teams, id: \.abbreviation) { team in
                                VStack(spacing: 6) {
                                    TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 44)
                                    Text(team.name)
                                        .font(DSType.text(DSType.Size.body, .bold))
                                        .foregroundStyle(Color.textPrimary)
                                        .lineLimit(1)
                                    Text(team.city)
                                        .font(DSType.text(DSType.Size.micro, .regular))
                                        .foregroundStyle(Color.textSecondary)
                                        .lineLimit(1)
                                }
                                .frame(width: 130)
                                .padding(.vertical, 12)
                            }
                        }
                        .padding(.horizontal, 16)
                        .background(Color.backgroundSecondary)

                        Divider()

                        comparisonRow(label: "Difficulty") { team in
                            HStack(spacing: 1) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= catalog.preview(for: team).difficulty ? "star.fill" : "star")
                                        .font(.system(size: 9))
                                        .foregroundStyle(star <= catalog.preview(for: team).difficulty ? Color.warning : Color.textTertiary.opacity(0.4))
                                }
                            }
                        }

                        comparisonRow(label: "Situation") { team in
                            Text(catalog.preview(for: team).situation.uppercased())
                                .font(DSType.display(DSType.Size.micro, .bold))
                                .foregroundStyle(Color.textPrimary)
                        }

                        comparisonRow(label: "Last Season") { team in
                            Text(catalog.preview(for: team).lastSeasonRecord)
                                .font(DSType.display(DSType.Size.body, .semibold))
                                .foregroundStyle(Color.textPrimary)
                        }

                        comparisonRow(label: "Roster OVR") { team in
                            Text("\(catalog.preview(for: team).estimatedOVR)")
                                .font(DSType.display(DSType.Size.body, .black))
                                .foregroundStyle(Color.forRating(catalog.preview(for: team).estimatedOVR))
                        }

                        comparisonRow(label: "Cap Space") { team in
                            Text("$\(catalog.preview(for: team).estimatedCapSpace)M")
                                .font(DSType.display(DSType.Size.body, .bold))
                                .foregroundStyle(catalog.preview(for: team).estimatedCapSpace > 30 ? Color.success : catalog.preview(for: team).estimatedCapSpace > 15 ? Color.accentBlue : Color.warning)
                        }

                        comparisonRow(label: "Coaching Budget") { team in
                            Text("$\(catalog.preview(for: team).coachingBudget)M")
                                .font(DSType.display(DSType.Size.body, .semibold))
                                .foregroundStyle(catalog.preview(for: team).coachingBudget >= 40 ? Color.success : catalog.preview(for: team).coachingBudget >= 30 ? Color.accentBlue : Color.warning)
                        }

                        comparisonRow(label: "Draft Picks") { team in
                            Text("\(catalog.preview(for: team).estimatedDraftPicks)")
                                .font(DSType.display(DSType.Size.body, .semibold))
                                .foregroundStyle(Color.textPrimary)
                        }

                        comparisonRow(label: "Owner Patience") { team in
                            VStack(spacing: 2) {
                                Text(catalog.preview(for: team).ownerPatience)
                                    .font(DSType.text(DSType.Size.caption, .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                Text("\(catalog.preview(for: team).patienceSeasons)yr")
                                    .font(DSType.display(DSType.Size.micro, .semibold))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }

                        comparisonRow(label: "Starting QB") { team in
                            VStack(spacing: 2) {
                                Text(catalog.preview(for: team).startingQBName)
                                    .font(DSType.text(DSType.Size.caption, .semibold))
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)
                                Text("\(catalog.preview(for: team).startingQBOverall) OVR")
                                    .font(DSType.display(DSType.Size.micro, .bold))
                                    .foregroundStyle(Color.forRating(catalog.preview(for: team).startingQBOverall))
                            }
                        }

                        comparisonRow(label: "Market") { team in
                            Text(team.mediaMarket.rawValue)
                                .font(DSType.text(DSType.Size.caption, .medium))
                                .foregroundStyle(Color.textPrimary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Compare Teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.textPrimary)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text)
            .font(DSType.display(DSType.Size.caption, .heavy))
            .tracking(1.0)
            .textCase(.uppercase)
            .foregroundStyle(Color.textTertiary)
            .frame(width: 130, alignment: .leading)
    }

    private func comparisonRow<Content: View>(label: String, @ViewBuilder cell: @escaping (NFLTeamDefinition) -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                rowLabel(label)
                ForEach(teams, id: \.abbreviation) { team in
                    cell(team)
                        .frame(width: 130)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 16)
            Divider().opacity(0.4)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TeamSelectionView(
            playerName: "John Doe",
            // A photographed id from the shipping pool (`UserPortrait.all`).
            // The old `"coach_m1"` here was one of the 20 hand-drawn portraits
            // the avatar overhaul deleted — `UserPortraitView` still *resolves*
            // a legacy id from an old save, but nothing new should mint one.
            avatarID: "avatar_00000",
            coachingStyle: .tactician,
            selectedRole: .gm,
            selectedCapMode: .simple
        )
    }
    .modelContainer(for: Career.self, inMemory: true)
}
