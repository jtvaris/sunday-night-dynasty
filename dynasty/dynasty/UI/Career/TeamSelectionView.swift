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
        case teamDetail(LeagueTeamDefinition)
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
    @State private var viewHeight: CGFloat = 0

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

    // MARK: - The random league, built at pick time

    /// The random league this screen is browsing, rolled BEFORE the list is
    /// drawn — and the very league the career starts from.
    ///
    /// This screen used to draw all 32 clubs from `LeagueTeamData`'s authored
    /// table and then generate a league inside `startCareer`, after the player
    /// had already committed. Every roster question the sheet wanted to answer
    /// — the strongest and weakest room, the names worth knowing, what the cap
    /// sheet actually looks like — had to be authored ahead of a roster that did
    /// not exist yet, and the generator was then asked to make the promise come
    /// true. The league now exists first, `TeamBrowseCatalog.generated(from:)`
    /// reads it, and `startCareer` has no generator call left to make a second
    /// one with.
    @State private var prepared: PreparedLeague?

    /// True only while `buildGeneratedLeague` is running. Separate from
    /// `isLoading` (which now covers career creation and nothing else) because
    /// the two say different things to the player.
    @State private var isBuildingLeague = false

    /// The un-persisted random league, and the career it belongs to.
    ///
    /// The `Career` is built here rather than in `startCareer` because every
    /// field it needs — name, avatar, style, role, cap mode, game mode,
    /// scenario, injury frequency — was collected on the identity page before
    /// this screen opened. Only `teamID` waits for the tap. It has to exist this
    /// early anyway: `FaceLibrary.beginNewCareer` binds the portrait registry to
    /// a career, and it must be bound before `generate` hands out any faces.
    private struct PreparedLeague {
        let career: Career
        let result: LeagueGenerator.GeneratedLeague
        let seasonHistory: [PlayerSeasonHistory]
    }

    /// Un-persisted league snapshot passed into the fantasy draft cover.
    private struct PendingFantasyDraft: Identifiable {
        let id = UUID()
        let career: Career
        let result: LeagueGenerator.GeneratedLeague
        let chosenTeamID: UUID
        /// Career-history rows from a template import, or the random league's
        /// synthesized backstory, held until the draft finishes and the graph is
        /// inserted.
        let seasonHistory: [PlayerSeasonHistory]
        /// Who was on which roster before the pool was emptied, and what each
        /// club's cap ledger read.
        ///
        /// Starting the draft strips all 32 rosters in place. That used to be
        /// harmless because a cancelled draft dropped a league nothing else
        /// held — `startCareer` rolled a fresh one on the next tap. The league
        /// is now rolled once, at the front of the screen, and the picker is
        /// still showing it: without this the player would cancel back to a list
        /// of clubs whose cards describe rosters the league no longer has, and
        /// then start a career with 32 empty teams. `restoreRosters` puts it
        /// back exactly as it was rather than re-rolling it, because re-rolling
        /// is the bug this screen exists to remove.
        let rostersBeforePool: [UUID: [Player]]
        let capUsageBeforePool: [UUID: Int]
    }

    /// iPad always reports .regular for both size classes, so orientation has to
    /// be measured. It used to be `viewWidth > 900`, which a 13-inch iPad
    /// satisfies in PORTRAIT (1032 pt) — the two-column branch then ran on a
    /// tall screen and left 40-45 % of it empty. Compare the two axes instead.
    private var isLandscape: Bool { viewWidth > viewHeight }

    /// The 32 franchises of the league being browsed.
    private var allTeams: [LeagueTeamDefinition] { catalog.teams }

    /// Available situation filters.
    private let situationOptions = ["All", "Rebuilding", "Rising", "Contender", "Win Now", "Dynasty"]

    /// Teams for the currently selected conference, filtered and grouped/sorted.
    private var divisionsForConference: [(division: Division, teams: [LeagueTeamDefinition])] {
        let conferenceTeams = allTeams.filter { $0.conference == selectedConference }
        let filtered = situationFilter == "All"
            ? conferenceTeams
            : conferenceTeams.filter { catalog.preview(for: $0).situation == situationFilter }
        return Division.allCases.compactMap { division in
            let teams: [LeagueTeamDefinition]
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
                columnHeaderBar
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
            // On the random path that now means "until the league has been
            // rolled", not "until a template has decoded" — a club cannot be
            // picked out of a list whose numbers are not yet the league's.
            .disabled(isLoading || isLoadingTemplate || isBuildingLeague)

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

            if isLoading || isLoadingTemplate || isBuildingLeague {
                ZStack {
                    Color.backgroundPrimary.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Color.accentBlue)
                        // Each label names the step that is actually running.
                        // "Generating League" has moved to the front of the
                        // screen because that is where the generating now
                        // happens; what is left after the tap is the template
                        // import (fixed leagues) or the insert into the store.
                        Text(loadingLabel)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
        }
        .task { await prepareLeagueSource() }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            viewWidth = newSize.width
            viewHeight = newSize.height
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
                        coachingStyle: coachingStyle,
                        setupSummary: setupSummary,
                        selectTitle: gameMode == .fantasyDraft ? "START FANTASY DRAFT" : "SELECT THIS TEAM",
                        gameMode: gameMode,
                        scenario: scenario
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
                    onCancel: {
                        restoreRosters(pending)
                        activeCover = nil
                    }
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
    private func teamRowButton(for team: LeagueTeamDefinition) -> some View {
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
                    .font(.system(size: DSType.Size.footnote))
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
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
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
            // Neutral ink. accentBlue is this screen's interactive colour — the
            // selected conference tab, the active filter chip — and the banner
            // is a caption with nothing to tap.
            .foregroundStyle(Color.textSecondary)
            .accessibilityElement(children: .combine)
        }
    }

    private func toggleCompare(_ team: LeagueTeamDefinition) {
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
            Text("OVR")
                .frame(width: 34, alignment: .trailing)
            Text("DIFFICULTY")
                .frame(width: 60, alignment: .trailing)
            Text("CAP / STAFF")
                .frame(width: 64, alignment: .center)
            Text("OWNER")
                .frame(width: 42, alignment: .center)
            Spacer().frame(width: 16) // matches chevron column
        }
        .font(DSType.display(DSType.Size.caption, .heavy))
        // Readability sweep: the tracking is what overflows the 60 pt
        // "DIFFICULTY" column, not the type size — 10 glyphs at 11 pt fit, the
        // 12 pt of letter-spacing on top of them do not. Halving the tracking
        // buys the width back at full size, and the scale floor is raised from
        // 0.7 (which bottomed out at 7.7 pt, under the legibility floor) to a
        // value that cannot take the label below 10 pt on any device.
        .tracking(0.6)
        // R39 device coverage: "DIFFICULTY" wrapped to "DIFFICULT/Y" inside
        // its 60 pt column on iPad mini — scale down instead of wrapping.
        .lineLimit(1)
        .minimumScaleFactor(0.92)
        .foregroundStyle(Color.textTertiary)
        .padding(.leading, 56) // skip past logo
    }

    /// The header as the list actually renders. Landscape puts two rows on every
    /// line, so one header labelled the right-hand column only; each branch also
    /// takes the same measure cap as the list beneath it, or the labels sit off
    /// the columns they name.
    @ViewBuilder
    private var columnHeaderBar: some View {
        VStack(spacing: 3) {
            if isLandscape {
                HStack(spacing: 12) {
                    columnHeaderRow
                    columnHeaderRow
                }
            } else {
                columnHeaderRow
            }

            // The owner column is a glyph and a year count, and nothing else on
            // the screen says what either of them measures.
            Text("OWNER = the owner's patience, and the seasons you get before the pressure mounts.")
                .font(DSType.text(DSType.Size.micro, .regular, prose: true))
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: isLandscape ? DSLayout.gridMeasure : DSLayout.wideMeasure)
        .frame(maxWidth: .infinity)
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
                        .font(.system(size: DSType.Size.caption, weight: .semibold))
                    Text(situationFilter == "All" ? "Filter" : situationFilter)
                        .font(DSType.text(DSType.Size.footnote, .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                }
                .foregroundStyle(situationFilter == "All" ? Color.textSecondary : Color.accentBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(situationFilter == "All" ? Color.backgroundSecondary : Color.accentBlue.opacity(0.15))
                        .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 0.5))
                )
                // The capsule is 26 pt tall; the target it hands the finger is
                // not allowed to be. Same trick the conference picker beside it
                // already uses — grow the hit area, leave the fill alone.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
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
                        .font(.system(size: DSType.Size.caption, weight: .semibold))
                    // Named as a sort order: a bare "Division" beside a glyph
                    // reads as a division filter to anyone seeing it once.
                    Text("Sort: \(sortMode.label)")
                        .font(DSType.text(DSType.Size.footnote, .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: DSType.Size.micro, weight: .bold))
                }
                .foregroundStyle(sortMode == .division ? Color.textSecondary : Color.accentBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(sortMode == .division ? Color.backgroundSecondary : Color.accentBlue.opacity(0.15))
                        .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 0.5))
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
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
                        .font(.system(size: DSType.Size.caption, weight: .semibold))
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
                .frame(minHeight: 44)
                .contentShape(Rectangle())
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
        // Leading, not centred: the picker is the only thing on the screen that
        // was not flush with the 16pt margin the title, the filter chips, the
        // column header and every row share.
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// What the blocking overlay is waiting on, in the player's words.
    private var loadingLabel: String {
        if isLoadingTemplate { return "Loading \(leagueSource.displayName) League..." }
        if isBuildingLeague  { return "Generating League..." }
        // Whatever is left after the tap: importing a fixed template, or
        // writing the already-built league into the save.
        return catalog.source.isTemplate ? "Building League..." : "Starting Career..."
    }

    /// Gets the league this screen browses ready — decode a fixed template, or
    /// roll the random one — before a single club is selectable.
    ///
    /// The template decode (1.5 MB publish / 2.6 MB dev) runs off the main actor
    /// so the picker never stalls mid-animation. A failure is not fatal: the
    /// screen falls back to the generated league, says so in the banner, and
    /// career creation follows `catalog.source` — never the requested source —
    /// so what gets persisted is always what was actually built.
    private func prepareLeagueSource() async {
        // Once, and once only. Rebuilding is the whole defect: the player would
        // be reading one league's rosters and starting another's.
        guard prepared == nil else { return }

        if let profile = leagueSource.templateProfile {
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
                return
            case .failure(let error):
                template = nil
                templateLoadError = error.localizedDescription
                // and fall through to the random league, which the banner names
            }
        }

        await buildGeneratedLeague()
    }

    /// Rolls the random league **before the list is drawn**.
    ///
    /// This is the refactor. Everything the sheet says about a club's roster now
    /// has a roster behind it (`TeamBrowseCatalog.generated(from:)` lists which
    /// figure comes from which function), and the graph built here is the graph
    /// `finalizeCareer` inserts — `startCareer` cannot roll a second one because
    /// it no longer calls the generator on this path at all.
    ///
    /// ## Why it runs on the main actor
    ///
    /// The target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so
    /// `LeagueGenerator`, every `@Model` it allocates and `FaceLibrary` are all
    /// main-actor isolated. There is no detached variant to reach for the way
    /// there is for the template decode above, whose `Task.detached` only has to
    /// carry a `Codable` struct across the boundary. Taking generation off the
    /// actor means marking the generator and the whole model layer it touches
    /// `nonisolated`, which is a change across a dozen files this work does not
    /// own — see the report's `needsDecision`.
    ///
    /// So it blocks, and it says so while it does. What this DOES change is
    /// where the block falls: the generation wait moves to the front of the
    /// screen, behind a spinner the player is already expecting, and what is
    /// left after the tap is the insert into the store, which was always there.
    ///
    /// ## How long it blocks for
    ///
    /// Measured rather than guessed, and measured on the SHIPPED functions
    /// rather than on a mirror of them: the three calls below were compiled out
    /// of this repo's own sources with `swiftc -O` into a command-line binary
    /// and run 15 times, on an 18-core Apple-silicon Mac, main-actor isolated
    /// exactly as here.
    ///
    /// | Call | p50 | range |
    /// |---|---|---|
    /// | `LeagueGenerator.generate` | 249 ms | 241-257 |
    /// | `LeagueGenerator.syntheticCareerHistory` | 51 ms | 49-52 |
    /// | `TeamBrowseCatalog.generated(from:)` | 90 ms | 88-92 |
    /// | **total, actor held** | **390 ms** | 380-398 |
    ///
    /// The first iteration in a cold process measured 380 ms, so there is no
    /// warm-up term to discount.
    ///
    /// **That is a Mac number and the app does not run on a Mac.** A device
    /// core is materially slower than a desktop one, so read 390 ms as a floor
    /// for iPhone/iPad rather than as the figure. The `PerfLog.time` calls in
    /// the body print the real one — `PERF|career_new_generateLeague|<ms>` on
    /// the console of a DEBUG build — and that is the number to trust when
    /// somebody has a device in hand.
    ///
    /// ## Whether that is acceptable
    ///
    /// The duration is: it is a single wait at the front of a screen the player
    /// has just navigated to, it is announced ("Generating League..."), it is
    /// paid exactly once per career, and it was always being paid — the
    /// refactor moved it from after the tap to before the list, it did not add
    /// it.
    ///
    /// The PRESENTATION of it is not, and this is the part worth fixing.
    /// Holding the main actor for 390 ms means the `ProgressView` in the
    /// overlay above does not animate for the whole of it: `Task.yield()` buys
    /// one frame — enough to get the overlay on screen — and then the spinner
    /// is frozen until the actor comes back. A stationary spinner reads as a
    /// hang, which is worse than a longer wait that visibly moves. The fix is
    /// the same one the doc above defers (get the generator off the main actor,
    /// which means `nonisolated` across the model layer) or a determinate
    /// progress bar the generator can tick, which needs the generator to report
    /// progress — both changes outside these files.
    private func buildGeneratedLeague() async {
        guard prepared == nil else { return }
        isBuildingLeague = true
        // Hand the actor back once before holding it for the duration, so
        // SwiftUI gets to process the `isBuildingLeague` change instead of
        // coalescing it with the work below. A yield rather than a timed guess;
        // it is the strongest thing available without moving the generator off
        // the actor, and it is not a guarantee that the frame has drawn.
        await Task.yield()

        let career = makeCareer()
        // Bind the portrait library to THIS career with an empty registry
        // before anybody is created, so every player and coach below is reserved
        // against it and nothing leaks in from a previously played save. It
        // moved here with the generation it has to precede.
        FaceLibrary.shared.beginNewCareer(career)

        // Measured, not estimated. `PerfLog` prints `PERF|<metric>|<ms>` in
        // DEBUG and compiles away entirely in Release, so the cost of the wait
        // this refactor moves to the front of the screen is a number anyone can
        // read off the console (`xcrun simctl launch --console-pty`) rather than
        // a claim in a comment. Two metrics, because the two halves are
        // independently large: 32 clubs × the 53-man `rosterBlueprint` and the
        // 16 seats in `coachingStaffRoles` for the roll, and up to
        // `backstorySeasonCap` synthesized seasons per player for the backstory.
        let result = PerfLog.time("career_new_generateLeague") {
            LeagueGenerator.generate(startYear: career.currentSeason)
        }
        // The generator rolls rosters but no past, so the career table (and
        // every engine that reads history) would open on a league where nobody
        // had played a game. Synthesize a backstory. It is built here rather
        // than at the tap for the same reason as the league: one wait, and
        // nothing at all is rolled after the player has chosen.
        let seasonHistory = PerfLog.time("career_new_backstory") {
            LeagueGenerator.syntheticCareerHistory(
                players: result.players, startYear: career.currentSeason
            )
        }

        career.leagueSource = .generated
        career.leagueID = result.league.id

        catalog = PerfLog.time("career_new_catalog") {
            TeamBrowseCatalog.generated(from: result)
        }
        prepared = PreparedLeague(
            career: career, result: result, seasonHistory: seasonHistory
        )
        isBuildingLeague = false
    }

    /// The career this screen is creating, before it knows which club.
    ///
    /// Every field here was collected on the identity page; only `teamID` and
    /// `leagueID` wait. Factored out because both league sources need one and
    /// they build it at different moments — the random league at `.task` time,
    /// so the generator has a career to reserve faces against, and the template
    /// import at the tap.
    private func makeCareer() -> Career {
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
        return career
    }

    // MARK: - Start Career

    private func startCareer(with teamDef: LeagueTeamDefinition) {
        isLoading = true

        // Fixed template vs. random roll.
        //
        // The random branch does not build anything: it takes the league the
        // picker has been browsing since `.task` ran. That is the point of the
        // whole refactor — there is no `LeagueGenerator.generate` call on this
        // path any more, so there is nothing here that could hand the player a
        // different league from the one whose cards he just read.
        //
        // The template branch still imports at the tap, and provably does not
        // need hoisting: `LeagueTemplateImporter` is seeded from the decoded
        // template's own `globalSeed`, and `TeamBrowseCatalog.template` derives
        // the cards from that same decoded value with the same helpers, so the
        // import is a function of the file the picker was already reading.
        // `leagueSource` is written inside the branch that actually ran, so the
        // persisted provenance can never claim a template the screen failed to
        // load.
        let career: Career
        let result: LeagueGenerator.GeneratedLeague
        let seasonHistory: [PlayerSeasonHistory]
        if catalog.source.isTemplate, let template {
            career = makeCareer()
            // Bind the portrait library to the new career with an EMPTY registry
            // BEFORE the league is built, so every player and coach created
            // below is reserved against this career and nothing leaks in from a
            // previously played one. (The random path did this in
            // `buildGeneratedLeague`, where its league is built.)
            FaceLibrary.shared.beginNewCareer(career)
            let imported = LeagueGenerator.generateFromTemplate(
                template, startYear: career.currentSeason
            )
            result = imported.generated
            seasonHistory = imported.seasonHistory
            career.leagueSource = catalog.source
            career.leagueID = result.league.id
        } else if let prepared {
            career = prepared.career
            result = prepared.result
            seasonHistory = prepared.seasonHistory
        } else {
            // Unreachable: the list is disabled until `prepared` is set. Bail
            // rather than quietly rolling a league nobody has seen.
            isLoading = false
            return
        }

        // Find the team matching the selected definition.
        let chosenTeam = result.teams.first { $0.abbreviation == teamDef.abbreviation }

        // The tripwire. `leagueID` was written when the league was BUILT — at
        // `.task` time on the random path — and `result` is the graph about to
        // be inserted. If a future edit reintroduces a post-selection
        // `LeagueGenerator.generate`, these two stop matching here.
        #if DEBUG
        assert(
            career.leagueID == result.league.id,
            "career-start is persisting a different league from the one the picker browsed"
        )
        // A scenario re-parametrizes the CHOSEN club, so it is the one thing on
        // this screen that cannot be applied before the tap. It also cannot
        // double-apply across a cancelled Fantasy Draft — the only way back into
        // this function — because `CareerSetup.scenario` is nil for
        // `.fantasyDraft`, making the two mutually exclusive.
        assert(
            scenario == nil || gameMode != .fantasyDraft,
            "a scenario and Fantasy Draft cannot both be set (CareerSetup.scenario is nil for .fantasyDraft)"
        )
        #endif

        career.teamID = chosenTeam?.id

        // R40 — scenario starts re-parametrize the generated league (roster
        // strength, owner traits, pick ownership, cap sheet) before insertion.
        //
        // THE ONE THING THIS SCREEN STILL CHANGES AFTER THE TAP, and the reason
        // `rosterPromisesHold` is false for a scenario. It does not roll a
        // second league — the assert above is what guarantees that, and it
        // holds for scenarios too — but it edits the chosen club inside the
        // league the picker was showing, which moves Roster OVR, Cap Space,
        // Draft Picks, the quarterback's rating, the star ratings, the room
        // grades and owner patience. It cannot be hoisted in front of the
        // picker, because "the chosen club" is what the tap decides. So the
        // sheet states the edits instead: `TeamDetailSheet.scenarioRewriteCard`
        // lists them for the club being opened, and `NewCareerView`'s scenario
        // cards carry the timing one screen earlier.
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
            // Photograph the league before emptying it — the picker is still
            // showing this exact graph, and a cancelled draft has to give it
            // back rather than get a re-roll. See `PendingFantasyDraft`.
            var rostersBeforePool: [UUID: [Player]] = [:]
            var capUsageBeforePool: [UUID: Int] = [:]
            for team in result.teams {
                rostersBeforePool[team.id] = team.players
                capUsageBeforePool[team.id] = team.currentCapUsage
            }
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
                seasonHistory: seasonHistory,
                rostersBeforePool: rostersBeforePool,
                capUsageBeforePool: capUsageBeforePool
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

    /// Puts the league back exactly as the picker showed it, after a cancelled
    /// Fantasy Draft.
    ///
    /// Not a re-roll and deliberately not one: the same `Player` and `Team`
    /// objects go back onto the same rosters with the same cap ledger, so the
    /// cards the player returns to describe the league he can still start.
    private func restoreRosters(_ pending: PendingFantasyDraft) {
        for team in pending.result.teams {
            let roster = pending.rostersBeforePool[team.id] ?? []
            for player in roster { player.teamID = team.id }
            team.players = roster
            team.currentCapUsage = pending.capUsageBeforePool[team.id] ?? 0
        }
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

        // F-56 — the declaration, and the scope it has to be written into.
        //
        // `FranchiseIdentityRegistry` writes through
        // `CareerScopedDefaults.scopedKey`, which resolves against
        // `WeekAdvancer.activeCareerID`. The reset directly above deliberately
        // clears that, and `CareerShellView` does not bind until the user has
        // already sat through the intro sequence — so without this line the
        // seed, and the press conference's amendment after it, would both land
        // on the bare un-suffixed key and be attributed to no save at all.
        //
        // Binding here is not a workaround, it is the truth: this career IS the
        // active one from the moment its league is in the store. The shell's own
        // `bind(to:)` becomes a no-op (it guards on the id), and the reset it
        // would otherwise have performed has just run.
        if let chosenTeamID {
            WeekAdvancer.bind(to: career)
            FranchiseIdentityDeclaration.declare(
                style: career.coachingStyle, teamID: chosenTeamID
            )
        }

        isLoading = false
        selectedCareer = career
    }
}

// MARK: - Identifiable conformance for sheet

extension LeagueTeamDefinition: Identifiable {
    var id: String { abbreviation }
}

// MARK: - Compact Team Row

/// The 3-tier situation ladder (persona audit): blue = building, green =
/// ascending, gold = competing. Amber and red stay reserved for warnings.
///
/// Declared at file scope because the LIST needs it now: the badge used to
/// exist only on the detail sheet and on the two card layouts nothing
/// instantiates, so the one place all 32 clubs are actually compared showed the
/// record and withheld the trajectory that explains it.
private func situationTint(_ situation: String) -> Color {
    switch situation {
    case "Rebuilding":                      return .accentBlue
    case "Rising":                          return .success
    case "Contender", "Win Now", "Dynasty": return .accentGold
    default:                                return .textSecondary
    }
}

private struct CompactTeamRow: View {
    let team: LeagueTeamDefinition
    /// Scouting numbers for the league being browsed — static table for a
    /// generated league, template-derived for a fixed one.
    let preview: TeamPreview
    var compareModeOn: Bool = false
    var isSelectedForCompare: Bool = false

    // NO STYLE MARK ON THIS ROW. `TeamPreview.styleFit` is stated on the detail
    // sheet's Coaching Style card and nowhere else, because that is the shape
    // the option chosen for it has: a field on `TeamPreview`, a matching rule
    // against the style already declared on the identity page, and no new
    // signal in this list. The row already carries logo, name, record,
    // situation, city, QB, OVR, stars, CAP/STF and OWNER; a tenth is a
    // column-layout call reserved to the owner, and a glyph in the name row is
    // still a tenth signal. It was added here once and is removed again — if it
    // is wanted on the row, it is asked for on the row.
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
                    .font(.system(size: DSType.Size.title3, weight: .semibold))
                    .foregroundStyle(isSelectedForCompare ? Color.accentBlue : Color.textTertiary)
                    .frame(width: 22)
            }

            // Team logo placeholder (with lock overlay if locked)
            ZStack(alignment: .bottomTrailing) {
                TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 36)

                if preview.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: DSType.Size.micro, weight: .bold))
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
                    // The record says where the club has been; the situation
                    // says where it is going, and 4-13 means something entirely
                    // different on a rebuild than it does on a Win Now club.
                    // Both belong on the row where the 32 are compared.
                    Text(preview.situation.uppercased())
                        .font(DSType.display(DSType.Size.micro, .bold))
                        .foregroundStyle(situationTint(preview.situation))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule().fill(situationTint(preview.situation).opacity(0.15))
                        )
                        .lineLimit(1)
                        .fixedSize()
                }
                HStack(spacing: 6) {
                    Text(team.city)
                        .font(DSType.text(DSType.Size.caption, .regular))
                        .foregroundStyle(Color.textSecondary)
                    Text("\u{2022}")
                        .font(DSType.text(DSType.Size.micro, .regular))
                        .foregroundStyle(Color.textTertiaryReadable)
                    // The two letters VoiceOver already gets. Without them a
                    // name and a number sit in the row with nothing saying
                    // whether 94 is a rating, a coach, or a jersey.
                    Text("QB")
                        .font(DSType.display(DSType.Size.micro, .bold))
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

            // Roster overall — the number the "Overall" sort orders by, and the
            // one figure that says how good the team is. The QB rating beside
            // the name is not a stand-in for it and can point the other way: the
            // cheapest club in the AFC fields a 78 QB in front of a 66 roster.
            Text("\(preview.estimatedOVR)")
                .font(DSType.display(DSType.Size.body, .black))
                .foregroundStyle(Color.forRating(preview.estimatedOVR))
                .frame(width: 34, alignment: .trailing)

            // Difficulty stars (single source-of-truth — tier label removed to
            // de-duplicate signal, per #117 polish). Monochrome: the count is
            // already the magnitude, and colouring it green→red put a second
            // meaning on the same amber the CAP/STF column uses two inches to
            // the right, with no key anywhere on the screen.
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(star <= preview.difficulty ? Color.textSecondary : Color.textTertiary.opacity(0.3))
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
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(ownerPatienceColor)
                Text("\(preview.patienceSeasons)yr")
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 42)

            if !compareModeOn {
                Image(systemName: "chevron.right")
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 16)
            } else {
                Color.clear.frame(width: 16)
            }
        }
        .padding(.horizontal, 10)
        // 8, not 6 — the CAP/STF stack is two 10-11 pt lines and at 6 they read
        // as one smudge. The list has the room.
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelectedForCompare ? Color.accentBlue.opacity(0.12) : Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelectedForCompare ? Color.accentBlue.opacity(0.7) : Color.surfaceBorder, lineWidth: isSelectedForCompare ? 1 : 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(team.city) \(team.name), \(preview.lastSeasonRecord), \(preview.situation), roster \(preview.estimatedOVR) OVR, difficulty \(preview.difficulty) of 5, QB \(preview.startingQBName) \(preview.startingQBOverall) OVR, \(preview.ownerPatience) owner, \(preview.patienceSeasons) seasons\(preview.isLocked ? ", locked" : "")\(compareModeOn ? (isSelectedForCompare ? ", selected for compare" : ", not selected") : "")")
    }
}

// MARK: - Mini Team Card (fits 16 teams on screen)

private struct MiniTeamCard: View {
    let team: LeagueTeamDefinition
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
                .font(.system(size: max(DSType.Size.footnote, min(DSType.Size.body, height * 0.1)), weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            // City
            Text(team.city)
                .font(.system(size: max(DSType.Size.caption, min(DSType.Size.footnote, height * 0.07))))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            // Stars
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                        .font(.system(size: max(DSType.Size.micro, min(DSType.Size.caption, height * 0.05))))
                        .foregroundStyle(star <= preview.difficulty ? Color.warning : Color.textTertiary)
                }
            }

            // Situation
            Text(preview.situation.uppercased())
                .font(.system(size: max(DSType.Size.micro, min(DSType.Size.caption, height * 0.06)), weight: .bold))
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
    let team: LeagueTeamDefinition
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
    let team: LeagueTeamDefinition
    /// The league being browsed — supplies this team's preview and its rivals.
    let catalog: TeamBrowseCatalog
    /// The style the user declared two screens ago, on NewCareerView's identity
    /// page. It is the ONLY playstyle preference the career records, so it is
    /// what a club is matched against here — the player is not asked twice.
    let coachingStyle: CoachingStyle
    /// R40 — one-line mode + league-settings recap above the confirm button.
    var setupSummary: String = ""
    /// R40 — confirm-button title (fantasy draft changes the next step).
    var selectTitle: String = "SELECT THIS TEAM"
    /// The mode the career will start in. Fantasy Draft dissolves every roster
    /// in the league the moment this sheet is confirmed, so the three cards
    /// that describe *this club's players* are suppressed for it — see
    /// `rosterPromisesHold`.
    var gameMode: CareerGameMode = .standard
    /// The scenario the career will start in, or `nil` for a plain career.
    ///
    /// It has to reach this sheet, and it did not. `CareerSetup.mode` returns
    /// `.standard` for all three scenario cards — `scenario` is the *other*
    /// half of the pair, and only `gameMode` was being passed down. So the
    /// sheet believed a Rebuild start was a plain Standard start, and stated
    /// this club's roster as settled fact when `CareerScenarioApplier` was
    /// about to rewrite it. See `rosterPromisesHold`.
    var scenario: CareerScenario? = nil
    let onSelect: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var viewWidth: CGFloat = 0
    @State private var viewHeight: CGFloat = 0

    private var isLandscape: Bool { viewWidth > 900 }

    private var preview: TeamPreview { catalog.preview(for: team) }

    private var situationColor: Color { Self.situationColor(for: preview.situation) }

    /// 3-tier color system (persona audit): blue = building, green = ascending,
    /// gold = competing. Amber/red stay reserved for warnings and dangers.
    /// Keyed by the string so the division-rival chips read off the same ladder.
    private static func situationColor(for situation: String) -> Color {
        switch situation {
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

    /// Who this club suits, on the same 1–2 / 4–5 bands `difficultyColor` and
    /// the star row already split on — no new threshold, and no verdict on the
    /// middle band, where "moderate" is the honest answer.
    ///
    /// A star count is a magnitude, not advice: nothing on the screen told a
    /// first-time player that two stars is where he should start, or warned a
    /// returning one that five is not a harder version of the same career.
    private var experienceRecommendation: (tag: String, detail: String, color: Color)? {
        switch preview.difficulty {
        case 1, 2:
            return (
                "GOOD FIRST CAREER",
                "Talent, cap room and picks to work with while you learn the systems.",
                .success
            )
        case 4, 5:
            return (
                "FOR VETERANS",
                "Thin on talent, cap room or picks — and the expectations arrive anyway.",
                .warning
            )
        default:
            return nil
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
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            viewWidth = newSize.width
            viewHeight = newSize.height
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

    private func detailStat(icon: String, label: String, value: String, valueColor: Color, anchor: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
                Text(label)
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(value)
                // Promoted: these three numbers are the core decision data (audit).
                .font(DSType.display(DSType.Size.title2, .black))
                .foregroundStyle(valueColor)
            Text(anchor)
                .font(DSType.display(DSType.Size.micro, .semibold))
                .foregroundStyle(Color.textTertiary)
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

            // The record alone never said whether 9-8 was a playoff year. It
            // is stated only where it is known: the fixed 2026 template carries
            // `madePlayoffs`/`playoffResult` for all 32 clubs, the generated
            // league carries no franchise history at all, and inventing one
            // there would be a lie about the roster the player is handed. So
            // the line simply gets longer when there is something true to add.
            Text(preview.lastSeasonPlayoffResult.map { "Last Season: \(preview.lastSeasonRecord) · \($0)" }
                 ?? "Last Season: \(preview.lastSeasonRecord)")
                .font(DSType.display(DSType.Size.body, .semibold))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, isLandscape ? 12 : 24)
    }

    // MARK: - Difficulty + Situation

    /// Where the two labels above this line come from, in the player's words.
    ///
    /// The sheet now mixes two kinds of fact on one card and had no way to tell
    /// them apart: `Roster OVR`, `Draft Picks`, the quarterback, the stars and
    /// the room grades are all read off a roster that exists, while these two —
    /// and owner patience, market copy, prestige, the coaching budget and last
    /// season's record with them — are authored per club in `LeagueTeamData`
    /// on the random league. Both readings are legitimate; presenting them in
    /// the same voice is not.
    private var difficultyProvenance: String {
        catalog.source.isTemplate
            ? String(localized: "Worked out from this club's roster against the league average, last season's record, and how patient the owner is.")
            : String(localized: "Authored labels for the franchise, not readings of this roster: they are the same for this club in every random league, however the roster below turns out.")
    }

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
                                .font(.system(size: DSType.Size.body))
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

            // One-line rationale so "Easy"/"Hard" isn't an unexplained verdict
            // (audit) — and, since the derivation wave, so the player can tell
            // these two apart from the three measured numbers under them.
            //
            // The sentence this replaces said "Difficulty weighs roster talent,
            // cap room, and draft capital." That was true of neither source.
            // Nothing weighs cap room or draft capital anywhere: on a template
            // `TeamBrowseCatalog.difficulty(patience:strength:leagueMean:wins:)`
            // starts from the owner-patience tier and adds a star for a roster
            // 2+ OVR above the league mean and a star for 12+ wins, and on the
            // random league there is no derivation at all — the value is the
            // authored `LeagueTeamData.previews[abbr].difficulty` integer, the
            // same one for this club in every league the generator ever rolls.
            Text(difficultyProvenance)
                .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // Who the club is for, not just how hard it is.
            if let recommendation = experienceRecommendation {
                VStack(spacing: 4) {
                    Text(recommendation.tag)
                        .font(DSType.display(DSType.Size.caption, .heavy))
                        .tracking(1.0)
                        .foregroundStyle(recommendation.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(recommendation.color.opacity(0.15))
                        )
                    Text(recommendation.detail)
                        .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(recommendation.tag). \(recommendation.detail)")
            }
        }
    }

    // MARK: - Info Cards

    private var ownerExpectationsCard: some View {
        VStack(spacing: 8) {
            // "Owner Patience", not "Owner Expectations": the tier word under it
            // is "Moderate" for half the league, and 250 pt up the screen the
            // difficulty tier says "Moderate" too. Naming the ladder is what
            // keeps the two apart.
            sectionLabel(String(localized: "Owner Patience"))

            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: preview.ownerPatienceIcon)
                        .font(.system(size: DSType.Size.body))
                        .foregroundStyle(ownerPatienceColor)
                    Text(preview.ownerPatience)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ownerPatienceColor)
                }

                Text("Gives you \(preview.patienceSeasons) season\(preview.patienceSeasons == 1 ? "" : "s") before the pressure mounts")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            // The tier and the season count both stopped short of the stake, so
            // "Demanding, 2 seasons" read as a difficulty flavour rather than a
            // clock. It is the hardest consequence the game has:
            // `OwnerSatisfactionEngine.checkFiring` rolls once satisfaction
            // falls through its patience-adjusted threshold, and the screen it
            // leads to (`FiredSummaryView`) marks the save `isGameOver` and
            // offers one button — Main Menu.
            Text("Let that patience run out and you are relieved of duty — the career ends there.")
                .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)

            // Found while tracing the scenario blocker, and it is the same
            // defect: the tier word and the season count are `LeagueTeamData`'s
            // authored franchise reputation, and the number the engine actually
            // fires you on is not derived from them on EITHER league source.
            // `LeagueGenerator.generateOwner` deals `owner.patience` with
            // `Int.random(in: 2...9)` (the template importer calls the same
            // function on its own seed), and `owner.patience` is what
            // `OwnerSatisfactionEngine` reads — once to scale every negative
            // satisfaction swing and again for the two firing thresholds. So
            // the card's ladder describes the club, not the man in the box.
            //
            // Stated rather than fixed: making the draw follow the authored tier
            // would move every club's firing threshold, which is a balance
            // change and not this wave's to make. See the report's `followUp`.
            DSDetailNote(
                text: String(localized: "The tier and the season count are the franchise's reputation, not this owner's own numbers — every owner in the league is dealt his patience when the league is built, and that hidden figure is what the firing check reads."),
                icon: "dice"
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    /// One number the media market really moves, with the direction it moves it.
    ///
    /// `higherIsBetter` is what keeps the two readings apart: a big market pulls
    /// free agents (good) and amplifies every bad week (bad), and both arrive as
    /// a multiplier above 1.0.
    private func marketEffect(
        icon: String,
        label: String,
        multiplier: Double,
        detail: String,
        higherIsBetter: Bool
    ) -> some View {
        let tone: Color
        if multiplier > 1.0 {
            tone = higherIsBetter ? .success : .warning
        } else if multiplier < 1.0 {
            tone = higherIsBetter ? .warning : .success
        } else {
            tone = .accentBlue
        }
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
                Text(label)
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(String(format: "×%.1f", multiplier))
                .font(DSType.display(DSType.Size.title3, .black))
                .foregroundStyle(tone)
            Text(detail)
                .font(DSType.display(DSType.Size.micro, .semibold))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var marketMediaCard: some View {
        VStack(spacing: 10) {
            sectionLabel(String(localized: "Market & Media"))

            Text(preview.marketDescription)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            // The market is not flavour — it is the only card on the sheet whose
            // mechanics were left entirely off it. `MediaMarket.freeAgentAttraction`
            // scales every free-agent interest score (FreeAgencyEngine), and
            // `mediaPressureMultiplier` scales every negative owner-satisfaction
            // swing (OwnerSatisfactionEngine) and the weekly event roll
            // (EventEngine). Print the two numbers beside the copy (audit).
            HStack(spacing: 12) {
                marketEffect(
                    icon: "person.badge.plus",
                    label: "Free Agents",
                    multiplier: team.mediaMarket.freeAgentAttraction,
                    detail: "pull on players you chase",
                    higherIsBetter: true
                )
                marketEffect(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "Media Pressure",
                    multiplier: team.mediaMarket.mediaPressureMultiplier,
                    detail: "owner damage when it goes wrong",
                    higherIsBetter: false
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    /// League means for the three headline numbers. The coaching-budget card has
    /// had its "League average: $NNM" line since an earlier audit; these three —
    /// the ones the career is actually chosen on — were printed bare, so "OVR 81"
    /// said nothing about whether 81 is a contender or the middle of the pack.
    private var leagueAverages: (ovr: Int, capSpace: Int, draftPicks: Int) {
        let previews = catalog.teams.map { catalog.preview(for: $0) }
        guard !previews.isEmpty else { return (0, 0, 0) }
        return (
            previews.reduce(0) { $0 + $1.estimatedOVR } / previews.count,
            previews.reduce(0) { $0 + $1.estimatedCapSpace } / previews.count,
            previews.reduce(0) { $0 + $1.estimatedDraftPicks } / previews.count
        )
    }

    /// The window a club's opening cap space can land in — in whole millions,
    /// and as the share of the cap its payroll is drawn from — derived from the
    /// two constants that actually decide it.
    ///
    /// Nothing here is typed out: `ContractEngine.openingSalaryCap` and
    /// `LeagueGenerator.rosterCapTargetBand` are the pair
    /// `LeagueGenerator.generateRoster` normalises every payroll onto, and
    /// reading them is what stops the sentence below from going stale the day
    /// either one is retuned — the failure this project keeps shipping is copy
    /// that quotes a constant somebody has since moved. The $750K minimum
    /// salary floor can lift a club's final payroll a little above its target,
    /// so the real low end is at or just under `low`.
    private static var capSpaceBand: (low: Int, high: Int, payrollLowPct: Int, payrollHighPct: Int) {
        let cap = ContractEngine.openingSalaryCap
        let payroll = LeagueGenerator.rosterCapTargetBand
        return (
            (cap - payroll.upperBound) / 1_000,
            (cap - payroll.lowerBound) / 1_000,
            payroll.lowerBound * 100 / cap,
            payroll.upperBound * 100 / cap
        )
    }

    /// The three headline numbers, and — new — where each of them comes from.
    ///
    /// Two of them are readings and the third is a die roll, and until now the
    /// card set all three in the same weight on the same row. `Roster OVR` is
    /// `RosterStrength.starterAverage` over the finished roster and
    /// `Draft Picks` is a count of real `DraftPick` rows, but `Cap Space` is
    /// the tail of `LeagueGenerator.generateRoster`'s last step: it scales the
    /// whole payroll onto `Int.random(in: rosterCapTargetBand)`, a fresh
    /// uniform draw per club with no team term in it at all. (The fixed
    /// templates are the same draw — `LeagueTemplateImporter.capTarget` reads
    /// the same band, seeded off the template's `globalSeed`, so it is stable
    /// per club rather than meaningful.) A player sorting the picker by Cap
    /// Space is sorting 32 dice, and nothing on the screen said so.
    private var statsRow: some View {
        let league = leagueAverages
        let band = Self.capSpaceBand
        return VStack(spacing: DSSpacing.xs) {
            HStack(spacing: 0) {
                detailStat(
                    icon: "chart.bar.fill",
                    label: "Roster OVR",
                    value: "\(preview.estimatedOVR)",
                    valueColor: Color.forRating(preview.estimatedOVR),
                    anchor: "League \(league.ovr)"
                )
                detailStat(
                    icon: "dollarsign.circle.fill",
                    label: "Cap Space",
                    value: "$\(preview.estimatedCapSpace)M",
                    valueColor: preview.estimatedCapSpace > 30 ? .success : preview.estimatedCapSpace > 15 ? .accentBlue : .warning,
                    anchor: "League $\(league.capSpace)M"
                )
                detailStat(
                    icon: "doc.text.fill",
                    label: "Draft Picks",
                    value: "\(preview.estimatedDraftPicks)",
                    // Middle band is accent blue, matching cap space — picks used to
                    // fall through to plain white, which read as "no opinion" beside
                    // two coloured figures on the same card.
                    valueColor: preview.estimatedDraftPicks >= 9 ? .success : preview.estimatedDraftPicks >= 7 ? .accentBlue : .warning,
                    anchor: "League \(league.draftPicks)"
                )
            }

            DSDetailNote(
                text: String(
                    format: String(localized: "Roster OVR and Draft Picks are read off this league's own rosters and pick board. Cap Space is not a franchise fact: each club's opening payroll is drawn at random from %d-%d %% of the $%dM cap, so the figure lands somewhere between $%dM and $%dM and says nothing about how the club has been run."),
                    band.payrollLowPct, band.payrollHighPct,
                    ContractEngine.openingSalaryCap / 1_000,
                    band.low, band.high
                ),
                icon: "dice"
            )
            .padding(.horizontal, DSSpacing.md)
        }
        .padding(.vertical, 14)
        .cardBackground()
    }

    // MARK: - Roster Promises

    /// Whether the three cards that describe THIS CLUB'S PLAYERS — the starting
    /// quarterback, the key players and the strongest/weakest room — still
    /// describe the league the player is about to start.
    ///
    /// They do in a plain Standard start — no scenario, no fantasy draft — and
    /// they no longer do it by keeping a promise. The
    /// three cards used to state authored values that `LeagueGenerator`
    /// `.generateRoster` then worked to make true — pinning the named men to
    /// their targets and running a capped repair loop until the strongest and
    /// weakest labels were earned. The random league is now built before this
    /// sheet is drawn, so `TeamBrowseCatalog.generated(from:)` reads all three
    /// straight off the finished roster: the quarterback is the man Auto-Set
    /// will start, the names are the three best players on the books, and the
    /// rooms are graded with the same call the roster screen grades with. On
    /// that path there is nothing left to keep — and ONLY on that path, which
    /// is the correction the next two sections make.
    ///
    /// They still do not hold in Fantasy Draft. Confirming this sheet in that
    /// mode hands every player in the league to `FantasyDraftEngine`, which
    /// pools all ~1 700 of them and re-drafts all 32 rosters from scratch — so
    /// the named quarterback will very likely be somebody else's, and the room
    /// the card calls strongest is decided at the draft board, not here.
    ///
    /// They do not hold in a SCENARIO start either, and the earlier draft of
    /// this comment said they did.
    ///
    /// The claim it made — "there is nothing left to keep" — was written from
    /// `gameMode` alone, and `CareerSetup.mode` returns `.standard` for Rebuild,
    /// Win Now and Cap Hell (only `CareerSetup.scenario` tells them apart). So
    /// the flag read `true` for all three and the sheet stated this club's
    /// quarterback, stars, rooms, OVR, cap space and pick count as settled.
    ///
    /// To be exact about what actually happens, because the report that raised
    /// this said a second league is generated after the tap and that is NOT
    /// what the code does: `startCareer` rolls nothing on the random path. It
    /// takes `prepared.result` — the league this sheet has been reading since
    /// `.task` — and the `#if DEBUG` tripwire beside it asserts the persisted
    /// `leagueID` is that league's. What it then does, for a scenario only, is
    /// call `CareerScenarioApplier.apply` on THIS ONE CLUB in that same league:
    ///
    /// * Rebuild — `shiftAttributes(of:by: -8)` on every man on the roster
    ///   (clamped 25...99), plus one extra pick in each of rounds 1-3 of the
    ///   upcoming draft taken from three other clubs.
    /// * Win Now — `+5` on the top 15 by `overall`, `+2...3` years of age on
    ///   the top 10, and this club's own round-1 and round-2 picks shipped out.
    /// * Cap Hell — `+3` on the top 12, every salary scaled until payroll is
    ///   105-108 % of the cap, and the ten biggest deals extended to 3-4 years.
    ///
    /// Every one of those moves a figure this sheet prints. So the cards are
    /// not suppressed — the roster they describe is real, it is this club's,
    /// and it is what the scenario is applied TO — but they are stamped
    /// "before the scenario" by `scenarioRewriteCard`, which states the three
    /// bullets above on screen. `NewCareerView`'s scenario cards say the same
    /// thing one screen earlier, where the choice is actually made.
    ///
    /// Bringing scenarios fully under the refactor is not possible on this
    /// screen: a scenario re-parametrizes the CHOSEN club, and which club that
    /// is, is the one thing the tap decides. Applying it to all 32 before the
    /// tap would be a different league, not an earlier one.
    ///
    /// Everything else on the sheet is a fact about the FRANCHISE — market,
    /// owner, budget, division, last season's record — and survives either way.
    /// (Owner patience is the exception a scenario also rewrites, and
    /// `scenarioRewriteCard` says so.)
    private var rosterPromisesHold: Bool { rosterSurvivesConfirmation && scenario == nil }

    /// Whether this club's generated players are still on this club's books
    /// after the tap. False only in Fantasy Draft, which empties all 32.
    ///
    /// Kept apart from `rosterPromisesHold` because the two questions have
    /// different answers for a scenario: the roster survives (so the cards are
    /// worth showing, and are what the scenario is applied to) but the figures
    /// on it do not (so they cannot be stated bare).
    private var rosterSurvivesConfirmation: Bool { gameMode != .fantasyDraft }

    /// The three roster cards, or nothing at all in a mode that is about to
    /// re-draft them. The sheet already names the mode in `setupSummary`
    /// directly above the confirm button, so their absence reads as "not
    /// decided yet" rather than as missing data.
    ///
    /// A scenario keeps all three and gains a header that says what is about to
    /// be done to them.
    @ViewBuilder
    private var rosterPromiseCards: some View {
        if rosterSurvivesConfirmation {
            scenarioRewriteCard
            startingQBCard
            keyPlayersCard
            groupStrengthCard
        }
    }

    // MARK: - Scenario Rewrite

    /// What the chosen scenario does to THIS club the moment the sheet is
    /// confirmed — the sentence the doc comment above owed the player.
    ///
    /// Every line is one operation in `CareerScenarioApplier`, quoted rather
    /// than characterised, so the card cannot drift from the code the way the
    /// "nothing left to keep" comment did. Nothing here is a projection: it
    /// does not say what the OVR becomes, because the sheet would have to
    /// re-derive `RosterStrength.starterAverage` over a roster that has not
    /// been shifted yet to know, and a re-derivation is exactly the kind of
    /// second answer this screen exists to remove.
    ///
    /// Built on `!rosterPromisesHold` rather than on `scenario != nil` even
    /// though the two are the same test inside `rosterPromiseCards`: the flag
    /// is the claim, and tying the disclosure to the flag is what stops the
    /// next person from flipping one without the other.
    @ViewBuilder
    private var scenarioRewriteCard: some View {
        if !rosterPromisesHold, let scenario {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                sectionLabel(String(localized: "Before the Scenario"))
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(String(
                    format: String(localized: "The roster numbers on this sheet describe the %@ as the league was generated. %@ rewrites this club — and only this club — when you confirm:"),
                    team.name, scenario.displayName
                ))
                .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(Self.scenarioEdits(scenario), id: \.self) { line in
                    HStack(alignment: .top, spacing: DSSpacing.xxs) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.warning)
                        Text(line)
                            .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DSDetailNote(
                    // "No other club's players", not "the other 31 clubs are
                    // untouched": Rebuild takes a pick each off three other
                    // franchises and Win Now hands two away, so pick OWNERSHIP
                    // does move. No other roster does, which is what makes the
                    // 32 cards still comparable.
                    text: String(localized: "No other club's players change — the one you pick is the one that changes — so the rest of the league still compares honestly."),
                    icon: "exclamationmark.triangle"
                )
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity)
            .cardBackground()
            .accessibilityElement(children: .combine)
        }
    }

    /// The scenario's edits, one line per operation in `CareerScenarioApplier`.
    ///
    /// Rebuild's extra picks are stated as a total because the arithmetic is
    /// closed: `LeagueGenerator.generateInitialDraftPicks` mints exactly one
    /// pick per club per round for `LeagueGenerator.roundsPerDraft` rounds, so
    /// a club walks in with 7 and `applyRebuild` adds one each in rounds 1-3.
    /// Win Now removes this club's rounds 1 and 2 from the same 7. Cap Hell
    /// touches no picks at all.
    private static func scenarioEdits(_ scenario: CareerScenario) -> [String] {
        switch scenario {
        case .rebuild:
            return [
                String(localized: "Every attribute of every man on the roster drops 8 points, so the Roster OVR on this sheet falls with it."),
                String(format: String(localized: "An extra first, second and third-round pick arrive from three other clubs: %d picks in the upcoming draft, not %d."), LeagueGenerator.roundsPerDraft + 3, LeagueGenerator.roundsPerDraft),
                String(localized: "Your owner's patience is rewritten to 8 or 9 out of 10 and he stops asking for a title, whatever the Owner Patience card on this sheet says."),
            ]
        case .winNow:
            return [
                String(localized: "The fifteen best players gain 5 points, and the ten best also age two or three years."),
                String(format: String(localized: "This club's own first and second-round picks are already spent: %d picks in the upcoming draft, not %d."), LeagueGenerator.roundsPerDraft - 2, LeagueGenerator.roundsPerDraft),
                String(localized: "Your owner's patience is rewritten to 2 or 3 out of 10 and he wants the title now, whatever the Owner Patience card on this sheet says."),
            ]
        case .capHell:
            return [
                String(localized: "The twelve best players gain 3 points."),
                String(localized: "Every salary on the roster is inflated until payroll sits at 105-108 % of the cap, so the cap space this sheet shows is gone and you start the career over the cap."),
                String(localized: "The ten biggest contracts are locked in for another three or four years."),
                String(localized: "Your owner's patience is rewritten to somewhere between 4 and 6 out of 10, whatever the Owner Patience card on this sheet says."),
            ]
        }
    }

    // MARK: - Starting QB Card

    private var startingQBCard: some View {
        VStack(spacing: 8) {
            sectionLabel(String(localized: "Starting Quarterback"))

            HStack(spacing: 12) {
                Image(systemName: "figure.american.football")
                    .font(.system(size: DSType.Size.title2))
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

    // MARK: - Key Players Card

    /// The two or three men worth knowing besides the quarterback. Empty on a
    /// source that has no opinion, and then the card is simply not built.
    @ViewBuilder
    private var keyPlayersCard: some View {
        if !preview.stars.isEmpty {
            VStack(spacing: DSSpacing.xs) {
                sectionLabel(String(localized: "Key Players"))

                VStack(spacing: DSSpacing.xs) {
                    ForEach(preview.stars, id: \.self) { star in
                        HStack(spacing: DSSpacing.sm) {
                            Text(star.position.rawValue)
                                .font(DSType.display(DSType.Size.caption, .heavy))
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 30, alignment: .leading)

                            Text(star.name)
                                .font(DSType.text(DSType.Size.body, .semibold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text("\(star.overall)")
                                .font(DSType.display(DSType.Size.callout, .black))
                                .foregroundStyle(Color.forRating(star.overall))
                            Text("OVR")
                                .font(DSType.display(DSType.Size.micro, .bold))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity)
            .cardBackground()
        }
    }

    // MARK: - Position Group Strengths Card

    /// The best and the worst room on the roster, as the league stands now.
    ///
    /// Shown whenever the roster survives the tap (`rosterSurvivesConfirmation`
    /// — i.e. every mode but Fantasy Draft), and true of the league the player
    /// is about to start whenever `rosterPromisesHold`. A scenario is the gap
    /// between those two: Win Now's +5 on the top 15 and Cap Hell's +3 on the
    /// top 12 land unevenly across the rooms and can swap which one grades
    /// highest, so `scenarioRewriteCard` sits above this card and says the
    /// ratings are about to move. The fixed template derives both halves from
    /// its real ratings, and the random league's generator builds a roster that
    /// backs the claim up rather than one that merely might. Both grade the
    /// defensive rooms under the club's OWN defensive scheme, because that is
    /// what the roster screen the player checks this against does.
    @ViewBuilder
    private var groupStrengthCard: some View {
        if !preview.strongestGroup.isEmpty, !preview.weakestGroup.isEmpty {
            VStack(spacing: DSSpacing.xs) {
                sectionLabel(String(localized: "Roster Shape"))

                HStack(spacing: DSSpacing.sm) {
                    groupStrengthTile(
                        icon: "arrow.up.circle.fill",
                        caption: String(localized: "Strongest Unit"),
                        group: preview.strongestGroup,
                        tint: Color.success
                    )
                    groupStrengthTile(
                        icon: "arrow.down.circle.fill",
                        caption: String(localized: "Weakest Unit"),
                        group: preview.weakestGroup,
                        tint: Color.warning
                    )
                }
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity)
            .cardBackground()
        }
    }

    private func groupStrengthTile(
        icon: String, caption: String, group: String, tint: Color
    ) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(tint)
                Text(caption)
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(group)
                .font(DSType.display(DSType.Size.title2, .black))
                .foregroundStyle(tint)
            Text(Self.groupDescription(group))
                .font(DSType.display(DSType.Size.micro, .semibold))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    /// Spells out the abbreviation the roster screen grades under, so the card
    /// reads on its own to a player who has not opened a depth chart yet.
    private static func groupDescription(_ group: String) -> String {
        switch group {
        case "QB": return String(localized: "Quarterback")
        case "RB": return String(localized: "Running Backs")
        case "WR": return String(localized: "Receivers")
        case "TE": return String(localized: "Tight Ends")
        case "OL": return String(localized: "Offensive Line")
        case "DL": return String(localized: "Defensive Line")
        case "LB": return String(localized: "Linebackers")
        case "DB": return String(localized: "Secondary")
        case "ST": return String(localized: "Special Teams")
        default:   return ""
        }
    }

    // MARK: - Division Rivals Card

    private var divisionRivals: [LeagueTeamDefinition] {
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

                        // Same ladder as this team's own chip two cards up — the
                        // card exists to answer "how tough is my division", and
                        // grey-on-grey made a rising rival look like a rebuilding one.
                        let rivalSituationColor = Self.situationColor(for: rivalPreview.situation)
                        Text(rivalPreview.situation.uppercased())
                            .font(DSType.display(DSType.Size.caption, .bold))
                            .foregroundStyle(rivalSituationColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(rivalSituationColor.opacity(0.15))
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
                    .font(.system(size: DSType.Size.callout))
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

    // MARK: - Year One

    /// What the first season looks like from this chair — and deliberately NOT
    /// a projected win total.
    ///
    /// Nothing in the engine projects a record before the season is simulated,
    /// so any figure here would be a formula invented for this one card, and a
    /// card that disagrees with the sim on the most important screen in the
    /// game is worse than a card that says less. Every line below is something
    /// already true of the club: last season as it actually ended, where the
    /// club says it is, how long the owner will wait, and what there is to
    /// spend. The closing note says the absence out loud, so it reads as a
    /// decision rather than as missing data.
    private var yearOneCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            sectionLabel(String(localized: "Year One"))
                .frame(maxWidth: .infinity, alignment: .leading)

            yearOneRow(
                label: String(localized: "Last season"),
                value: preview.lastSeasonPlayoffResult
                    .map { "\(preview.lastSeasonRecord) \u{00B7} \($0)" }
                    ?? preview.lastSeasonRecord,
                tint: .textPrimary
            )
            yearOneRow(
                label: String(localized: "Where the club is"),
                value: preview.situation,
                tint: situationColor
            )
            yearOneRow(
                label: String(localized: "Owner"),
                value: "\(preview.ownerPatience) \u{00B7} \(preview.patienceSeasons) season\(preview.patienceSeasons == 1 ? "" : "s")",
                tint: ownerPatienceColor
            )
            yearOneRow(
                label: String(localized: "Cap space"),
                value: "$\(preview.estimatedCapSpace)M",
                tint: preview.estimatedCapSpace > 30 ? .success : preview.estimatedCapSpace > 15 ? .accentBlue : .warning
            )

            DSDetailNote(
                // The "four facts" claim survives, but it owed the player one
                // more word about what KIND of fact each is. On the random
                // league not one of the four is read off a roster: the record,
                // the situation and the owner are `LeagueTeamData`'s authored
                // backstory (a freshly generated league has played no season)
                // and the cap space is `generateRoster`'s payroll draw. On a
                // template the first three are the file's own 2026 rows.
                text: catalog.source.isTemplate
                    ? String(localized: "Four facts, no forecast. The first three are this league's own 2026 rows; the cap space is the random opening payroll explained with the Cap Space figure. Nothing here projects a record — the game does not know what this team wins until the season is played.")
                    : String(localized: "Four facts, no forecast — and none of them a reading of the roster. The first three are the franchise's authored backstory, because a generated league has played no season yet, and the cap space is the random opening payroll explained with the Cap Space figure. Nothing here projects a record."),
                icon: "calendar"
            )
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private func yearOneRow(label: String, value: String, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
            Text(label)
                .font(DSType.text(DSType.Size.caption, .medium))
                .foregroundStyle(Color.textTertiary)
            Spacer(minLength: DSSpacing.xxs)
            Text(value)
                .font(DSType.display(DSType.Size.footnote, .bold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    // MARK: - Franchise Prestige

    /// What the badge carries before a down is played.
    ///
    /// A word and five pips, NOT a second star row: career difficulty already
    /// spends five stars further up the sheet and two five-of-something scales
    /// on one screen are read as the same scale. One tint for every tier for
    /// the same reason the difficulty stars are monochrome — prestige is not a
    /// good/bad axis, and the low tiers say so in as many words.
    private var franchisePrestigeCard: some View {
        VStack(spacing: DSSpacing.xs) {
            sectionLabel(String(localized: "Franchise Prestige"))

            Text(preview.prestigeLabel)
                .font(DSType.display(DSType.Size.title3, .black))
                .foregroundStyle(Color.accentGold)

            HStack(spacing: DSSpacing.xxs) {
                ForEach(1...5, id: \.self) { pip in
                    Image(systemName: pip <= preview.prestige ? "circle.fill" : "circle")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(pip <= preview.prestige
                                         ? Color.accentGold
                                         : Color.textTertiary.opacity(0.4))
                }
            }

            Text(preview.prestigeDetail)
                .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            DSDetailNote(
                text: String(localized: "Standing, not form: this is the history the badge carries, and no part of the season is simulated from it."),
                icon: "building.columns"
            )
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity)
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Franchise prestige, \(preview.prestigeLabel), \(preview.prestige) of 5. \(preview.prestigeDetail)")
    }

    // MARK: - Coaching Style Fit

    /// Whose house this is, against the style the user already declared.
    ///
    /// No second question is asked: `CoachingStyle` is the one playstyle the
    /// career records, so it is what the club is matched on. And no bonus is
    /// claimed for a match — nothing in the engine reads the pairing, and the
    /// copy is careful to say the difference costs nothing rather than let the
    /// player read a hidden penalty into it. What the note quotes instead is
    /// the market read `FranchiseIdentityDeclaration.declare` seeds from the
    /// style the moment this sheet is confirmed — that one is real, it writes
    /// `TradeValueEngine.FranchiseIdentityRegistry`, and `TradeReputationRegistry`
    /// moves the other 31 front offices off it from the user's first trade.
    ///
    /// NOT the "+`bonusValue` `bonusAttribute`" badge. That number has no
    /// computing function behind it: `CoachingStyle.bonusValue` is a flat 10 for
    /// all five styles, nothing in Engine/ reads `Career.coachingStyle`, and no
    /// coach attribute is ever adjusted by it. It ships on the staff screen as
    /// inherited copy; the team picker does not repeat it.
    private var styleFitCard: some View {
        let matches = preview.styleFit == coachingStyle
        return VStack(spacing: DSSpacing.xs) {
            sectionLabel(String(localized: "Coaching Style"))

            HStack(spacing: DSSpacing.sm) {
                styleTile(
                    caption: String(localized: "You declared"),
                    style: coachingStyle,
                    tint: .accentBlue
                )
                styleTile(
                    caption: String(localized: "This building runs on"),
                    style: preview.styleFit,
                    tint: matches ? .success : .textSecondary
                )
            }

            Text(matches
                 ? String(localized: "SAME SCHOOL")
                 : String(localized: "A DIFFERENT SCHOOL"))
                .font(DSType.display(DSType.Size.caption, .heavy))
                .tracking(1.0)
                .foregroundStyle(matches ? Color.success : Color.textSecondary)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(
                    Capsule().fill((matches ? Color.success : Color.textSecondary).opacity(0.15))
                )

            Text(matches
                 ? String(localized: "The way this club has been run is the way you say you run one.")
                 : String(localized: "This club has been run another way. Nothing stops you changing that, and nothing is docked for the difference."))
                .font(DSType.text(DSType.Size.caption, .regular, prose: true))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            DSDetailNote(
                text: String(localized: "The style you declared is the read the other 31 front offices price you against, wherever you go, until your own trades change their minds."),
                icon: coachingStyle.icon
            )
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private func styleTile(caption: String, style: CoachingStyle, tint: Color) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            Text(caption)
                .font(DSType.display(DSType.Size.micro, .semibold))
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
            Image(systemName: style.icon)
                .font(.system(size: DSType.Size.body))
                .foregroundStyle(tint)
            Text(style.displayName)
                .font(DSType.display(DSType.Size.caption, .bold))
                .foregroundStyle(tint)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Installed Scheme

    /// The two systems this club actually installs.
    ///
    /// Stated only because both league sources now really know them: the fixed
    /// template carries `staff.offScheme`/`defScheme` per club, and the random
    /// league stopped drawing them with `allCases.randomElement()` — the pair
    /// is authored in `LeagueTeamData` and `LeagueGenerator.generate` hires the
    /// head coach and both coordinators under it and builds the roster to the
    /// defence. Before that, nothing here could be said at all, which is why
    /// the card is guarded rather than defaulted: a source that states no
    /// scheme gets no card.
    ///
    /// WHAT THE NOTE MAY NOT PROMISE. This pair is a fact about the club as the
    /// generator built it, and about the other 31 clubs for the whole career —
    /// but NOT about the user's own staff. `finalizeCareer` strips the chosen
    /// club's coaches outright (`coach.teamID = nil`, deliberately: the wizard
    /// guides the hiring), and both paths onto this screen — the standard one
    /// and the fantasy-draft detour — funnel through it. `RosterViewWrapper`
    /// then finds no offensive coordinator, so its `offensiveScheme` stays nil
    /// and `RosterView.installedScheme(for:)` returns nil on every offensive
    /// row; and no defensive coordinator, so `defensiveScheme` holds its
    /// `.base43` default and the starter counts grade under a 4-3 whatever this
    /// card said. An earlier draft of the note claimed the roster screen's FIT
    /// column "rates every player against these two systems" — for the one club
    /// this sheet ever turns into a career, it does not. What survives the strip
    /// is the roster itself: `initializePlayerFamiliarity` seeds every man's
    /// day-one `schemeFamiliarity` off exactly these two on BOTH sources (the
    /// template importer calls the same function after `makeStaff`), and
    /// `generateRoster` is additionally built to this defence on the random
    /// one. The note claims the half that holds either way, and says plainly
    /// that the seats are empty from then on.
    @ViewBuilder
    private var installedSchemeCard: some View {
        if let offense = preview.offensiveScheme, let defense = preview.defensiveScheme {
            VStack(spacing: DSSpacing.xs) {
                sectionLabel(String(localized: "Installed Scheme"))

                HStack(spacing: DSSpacing.sm) {
                    schemeTile(
                        icon: "arrow.up.forward",
                        caption: String(localized: "Offense"),
                        name: offense.displayName
                    )
                    schemeTile(
                        icon: "shield.lefthalf.filled",
                        caption: String(localized: "Defense"),
                        name: defense.displayName
                    )
                }

                DSDetailNote(
                    // `rosterSurvivesConfirmation`, not `rosterPromisesHold`:
                    // a scenario shifts the ratings but installs no new scheme,
                    // so the first branch is still the true one for it. Reading
                    // the stricter flag here would have printed the fantasy-draft
                    // sentence — "a fantasy draft redeals every roster" — on a
                    // Rebuild start, which is the same class of defect as the
                    // one this wave is fixing.
                    text: rosterSurvivesConfirmation
                        ? String(localized: "The rooms in Roster Shape are graded under this club's own front — a 3-4 fields one nose tackle where a 4-3 fields two — and every man on the roster starts with his playbook knowledge seeded on these two systems. You take the job with the staff seats empty, so what your roster screen grades against from then on is the pair your own coordinators run.")
                        : String(localized: "This is what the building ran on before you arrived. A fantasy draft redeals every roster in the league, and you take the job with the staff seats empty, so the systems your club installs are the ones the coordinators you hire bring with them."),
                    icon: "list.clipboard"
                )
            }
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity)
            .cardBackground()
        }
    }

    private func schemeTile(icon: String, caption: String, name: String) -> some View {
        VStack(spacing: DSSpacing.xxs) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: icon)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
                Text(caption)
                    .font(DSType.display(DSType.Size.caption, .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(name)
                .font(DSType.display(DSType.Size.body, .black))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Locked Team Banner

    @ViewBuilder
    private var lockedBanner: some View {
        if preview.isLocked {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: DSType.Size.body))
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
            // What the first season is, stated in facts, directly under the
            // numbers it recaps.
            yearOneCard
            rosterPromiseCards
            installedSchemeCard
            styleFitCard
            ownerExpectationsCard
            franchisePrestigeCard
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
                yearOneCard
                rosterPromiseCards
                installedSchemeCard
                styleFitCard
                ownerExpectationsCard
                franchisePrestigeCard
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
    let teams: [LeagueTeamDefinition]
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
                                        .font(.system(size: DSType.Size.micro))
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
                // Outside the grid, not a row in it: the grid scrolls in both
                // axes and a full-width note inside it fights the horizontal
                // measure. As an inset it stays put under a table the player is
                // panning around.
                //
                // This screen exists to be read column-against-column, which is
                // exactly the reading two of its rows cannot bear. Difficulty is
                // `LeagueTeamData`'s authored integer on the random league (see
                // `TeamDetailSheet.difficultyProvenance`), and Cap Space is one
                // uniform draw per club from
                // `LeagueGenerator.rosterCapTargetBand` (see
                // `TeamDetailSheet.statsRow`). Every other row here is read off
                // the league. Saying so is cheaper than a player deciding a
                // franchise on a die roll.
                .safeAreaInset(edge: .bottom) {
                    DSDetailNote(
                        text: String(localized: "Difficulty is an authored label for the franchise and Cap Space is a random opening payroll — neither is a reading of the roster. The rest of these rows are."),
                        icon: "dice"
                    )
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.xs)
                    .background(Color.backgroundSecondary)
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

    private func comparisonRow<Content: View>(label: String, @ViewBuilder cell: @escaping (LeagueTeamDefinition) -> Content) -> some View {
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
