import SwiftUI
import SwiftData

// MARK: - DraftView

/// The main NFL Draft event screen.
/// Drives simulation: AI picks auto-advance with a brief delay; the player's pick
/// pauses and presents the selection sheet.
struct DraftView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: Draft State

    /// All picks for the current draft in order.
    @State private var allPicks: [DraftPick] = []
    /// Prospects still available (not yet drafted).
    @State private var availableProspects: [CollegeProspect] = []
    /// The player's team.
    @State private var playerTeam: Team?
    /// All teams keyed by ID for fast lookup.
    @State private var teamsByID: [UUID: Team] = [:]
    /// Coaching staff for the player's team.
    @State private var teamCoaches: [Coach] = []
    /// Current team needs (positions sorted by priority).
    @State private var teamNeeds: [Position] = []

    /// Index into allPicks indicating which pick is currently on the clock.
    @State private var currentPickIndex: Int = 0
    /// Whether the AI simulation timer is running.
    @State private var isSimulating: Bool = false
    /// Whether the player's selection sheet is presented.
    @State private var showSelectionSheet: Bool = false
    /// An incoming AI trade offer display model, if any.
    @State private var pendingTradeOffer: DraftTradeOfferDisplay?

    // MARK: Media & War Room State

    /// The latest media commentary to display as a toast.
    @State private var mediaToast: MediaToast?
    /// Whether the media toast is visible (for animation).
    @State private var showMediaToast: Bool = false
    /// Staff recommendations shown in the war room panel.
    @State private var staffRecommendations: [DraftEngine.StaffRecommendation] = []
    /// Whether the war room panel is expanded.
    @State private var showWarRoom: Bool = false
    /// The current round for round-transition banners.
    @State private var lastAnnouncedRound: Int = 0
    /// Whether the round transition banner is visible.
    @State private var showRoundBanner: Bool = false
    /// The round number to display in the banner.
    @State private var roundBannerNumber: Int = 1
    /// Whether to show the draft summary at the end.
    @State private var showDraftSummary: Bool = false
    /// Simulated on-the-clock countdown value.
    @State private var clockSeconds: Int = 120

    // MARK: - Computed

    private var currentPick: DraftPick? {
        guard currentPickIndex < allPicks.count else { return nil }
        return allPicks[currentPickIndex]
    }

    private var completedPicks: [DraftPick] {
        allPicks.prefix(currentPickIndex).reversed()
    }

    private var isPlayerTurn: Bool {
        guard let pick = currentPick, let teamID = career.teamID else { return false }
        return pick.currentTeamID == teamID
    }

    private var draftComplete: Bool {
        currentPickIndex >= allPicks.count
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if horizontalSizeClass == .regular {
                // iPad: side-by-side layout
                HStack(spacing: 0) {
                    mainColumn
                    Divider().overlay(Color.surfaceBorder)
                    rightSidebar
                        .frame(width: 320)
                }
            } else {
                mainColumn
            }

            // MARK: Round Transition Banner
            if showRoundBanner {
                roundTransitionBanner
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .zIndex(10)
            }

            // MARK: Media Toast Overlay
            if showMediaToast, let toast = mediaToast {
                VStack {
                    Spacer()
                    mediaToastView(toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }
                .zIndex(5)
            }
        }
        .navigationTitle("NFL Draft \(career.currentSeason)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarContent }
        .task { loadDraftData() }
        .sheet(isPresented: $showSelectionSheet) {
            if let pick = currentPick {
                DraftSelectionSheet(
                    career: career,
                    availableProspects: availableProspects,
                    pickNumber: pick.pickNumber,
                    round: pick.round,
                    onDraft: { prospect in
                        completePick(pick: pick, prospect: prospect)
                    }
                )
            }
        }
        .sheet(item: $pendingTradeOffer) { displayOffer in
            TradeOfferView(
                offer: displayOffer,
                onAccept: { acceptTradeOffer(displayOffer) },
                onDecline: { pendingTradeOffer = nil }
            )
        }
        .sheet(isPresented: $showDraftSummary) {
            draftSummarySheet
        }
    }

    // MARK: - Main Column

    private var mainColumn: some View {
        VStack(spacing: 0) {
            draftHeader
            onTheClockCard
            if isPlayerTurn && !staffRecommendations.isEmpty {
                warRoomPanel
            }
            Divider().overlay(Color.surfaceBorder)
            draftBoardScrollView
        }
    }

    // MARK: - Draft Header Bar

    private var draftHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("NFL DRAFT")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(2)
                if let pick = currentPick {
                    Text("Round \(pick.round)  ·  Pick \(pick.pickNumber) of \(allPicks.count)")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)
                        .monospacedDigit()
                } else if draftComplete {
                    Text("Draft Complete")
                        .font(.headline)
                        .foregroundStyle(Color.success)
                }
            }

            Spacer()

            // Progress indicator
            if !allPicks.isEmpty {
                let fraction = Double(currentPickIndex) / Double(allPicks.count)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(currentPickIndex) / \(allPicks.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .tint(Color.accentGold)
                        .frame(width: 100)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.accentGold)
                .frame(height: 2),
            alignment: .bottom
        )
    }

    // MARK: - On The Clock Card

    @ViewBuilder
    private var onTheClockCard: some View {
        if draftComplete {
            draftCompleteCard
        } else if let pick = currentPick {
            if isPlayerTurn {
                playerOnClockCard(pick: pick)
            } else {
                aiOnClockCard(pick: pick)
            }
        }
    }

    private var draftCompleteCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentGold)
            Text("The Draft is Complete!")
                .font(.title3.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text("Check your roster to see your new players.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            Button {
                showDraftSummary = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.clipboard.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("View Draft Summary")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(Color.backgroundPrimary)
                .padding(.horizontal, 20)
                .frame(minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentGold)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func playerOnClockCard(pick: DraftPick) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.accentGold)
                    .frame(width: 8, height: 8)
                Text("YOU'RE ON THE CLOCK")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(2)
                Circle()
                    .fill(Color.accentGold)
                    .frame(width: 8, height: 8)
            }

            HStack(spacing: 16) {
                Text("Round \(pick.round)  ·  Pick \(pick.pickNumber)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                // On-the-clock timer
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(clockSeconds <= 30 ? Color.danger : Color.accentGold)
                    Text(String(format: "%d:%02d", clockSeconds / 60, clockSeconds % 60))
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                        .foregroundStyle(clockSeconds <= 30 ? Color.danger : Color.accentGold)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundTertiary)
                )
                .onAppear { startClockTimer() }
            }

            HStack(spacing: 12) {
                Button {
                    showSelectionSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.clipboard.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Make Pick")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentGold)
                            .shadow(color: Color.accentGold.opacity(0.35), radius: 8, x: 0, y: 3)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    autoPickForPlayer(pick: pick)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.sparkles")
                            .font(.system(size: 14))
                        Text("Auto-Pick")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.backgroundTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            Color.backgroundSecondary
                .overlay(Color.accentGold.opacity(0.04))
        )
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func aiOnClockCard(pick: DraftPick) -> some View {
        HStack(spacing: 14) {
            Text(teamAbbreviation(for: pick.currentTeamID) ?? "???")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(Color.backgroundPrimary)
                .frame(width: 48, height: 48)
                .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text("On the Clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
                Text(teamName(for: pick.currentTeamID) ?? "Unknown Team")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Text("Round \(pick.round)  ·  Pick \(pick.pickNumber)")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
            }

            Spacer()

            if isSimulating {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.accentBlue)
                    .scaleEffect(0.85)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Draft Board

    private var draftBoardScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if completedPicks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.textTertiary)
                        Text("The draft hasn't started yet.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(completedPicks) { pick in
                        DraftPickCard(
                            pick: pick,
                            isPlayerTeam: pick.currentTeamID == career.teamID
                        )
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 12)
        }
    }

    // MARK: - Right Sidebar (iPad)

    /// Combined sidebar with Big Board and War Room tabs on iPad.
    private var rightSidebar: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                sidebarTab(title: "Big Board", icon: "list.star", isActive: !showWarRoom) {
                    showWarRoom = false
                }
                sidebarTab(title: "War Room", icon: "person.3.fill", isActive: showWarRoom) {
                    showWarRoom = true
                }
            }
            .background(Color.backgroundTertiary)
            .overlay(
                Rectangle()
                    .fill(Color.surfaceBorder)
                    .frame(height: 1),
                alignment: .bottom
            )

            if showWarRoom {
                warRoomSidebarContent
            } else {
                bigBoardContent
            }
        }
        .background(Color.backgroundSecondary)
    }

    private func sidebarTab(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(isActive ? Color.accentGold : Color.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                Rectangle()
                    .fill(isActive ? Color.accentGold : Color.clear)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// War room content for the iPad sidebar.
    private var warRoomSidebarContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                if staffRecommendations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.textTertiary)
                        Text(isPlayerTurn ? "Staff is analyzing..." : "Waiting for your pick...")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(staffRecommendations) { rec in
                        staffRecommendationCard(rec)
                    }
                }
            }
            .padding(12)
        }
    }

    private var bigBoardSidebar: some View {
        VStack(spacing: 0) {
            bigBoardHeader
            bigBoardContent
        }
        .background(Color.backgroundSecondary)
    }

    /// Big board content used both standalone and inside the tabbed sidebar.
    private var bigBoardContent: some View {
        let scoutedBoard = availableProspects
            .filter { $0.scoutedOverall != nil }
            .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }

        return Group {
            if scoutedBoard.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "list.star")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.textTertiary)
                    Text("No scouted prospects")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(scoutedBoard.prefix(50).enumerated()), id: \.element.id) { index, prospect in
                            sidebarProspectRow(rank: index + 1, prospect: prospect)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private var bigBoardHeader: some View {
        HStack {
            Text("Your Big Board")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.accentGold)
            Spacer()
            Text("\(availableProspects.filter { $0.scoutedOverall != nil }.count) left")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func sidebarProspectRow(rank: Int, prospect: CollegeProspect) -> some View {
        HStack(spacing: 8) {
            Text("\(rank)")
                .font(.system(size: 12, weight: .heavy).monospacedDigit())
                .foregroundStyle(rank == 1 ? Color.accentGold : Color.textTertiary)
                .frame(width: 24, alignment: .trailing)

            Text(prospect.position.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 32, height: 22)
                .background(positionColor(prospect.position), in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 2) {
                Text(prospect.fullName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(prospect.college)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            if let overall = prospect.scoutedOverall {
                Text("\(overall)")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(overall))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.backgroundPrimary.opacity(0.5))
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !draftComplete && !isPlayerTurn {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    simulateNextPick()
                } label: {
                    Label("Simulate Pick", systemImage: "forward.fill")
                }
                .disabled(isSimulating)
            }
        }
    }

    // MARK: - Simulation Logic

    /// Starts the AI auto-advance loop after each pick is resolved.
    private func advanceIfNeeded() {
        guard !draftComplete else {
            // Show draft summary automatically after a short delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                showDraftSummary = true
            }
            return
        }
        guard !isPlayerTurn else {
            // It's the player's turn — generate staff recommendations and check for trade.
            generateWarRoomRecommendations()
            considerAITradeOffer()
            return
        }
        staffRecommendations = []
        isSimulating = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            simulateNextPick()
        }
    }

    private func simulateNextPick() {
        guard let pick = currentPick, !isPlayerTurn else {
            isSimulating = false
            return
        }

        // Fetch the AI team's current roster for needs analysis
        let roster = fetchRoster(for: pick.currentTeamID)
        let team = teamsByID[pick.currentTeamID]

        guard !availableProspects.isEmpty else {
            isSimulating = false
            return
        }

        let chosen: CollegeProspect
        if let team {
            chosen = DraftEngine.aiMakePick(
                team: team,
                availableProspects: availableProspects,
                teamRoster: roster
            )
        } else {
            // Fallback: pick the highest true overall
            chosen = availableProspects.max(by: { $0.trueOverall < $1.trueOverall })!
        }

        completePick(pick: pick, prospect: chosen)
    }

    /// Resolves a single pick — marks it complete and removes the prospect from the available pool.
    private func completePick(pick: DraftPick, prospect: CollegeProspect) {
        // Determine team needs for the picking team.
        let pickingRoster = fetchRoster(for: pick.currentTeamID)
        let pickingNeeds = DraftEngine.topTeamNeeds(roster: pickingRoster)

        pick.playerID = prospect.id
        pick.playerName = prospect.fullName
        pick.playerPosition = prospect.position.rawValue
        pick.playerCollege = prospect.college
        pick.scoutGrade = prospect.scoutGrade
        pick.teamAbbreviation = teamAbbreviation(for: pick.currentTeamID)
        pick.isComplete = true

        // Generate media grade for this pick.
        let media = DraftEngine.generateMediaGrade(
            prospect: prospect,
            pickNumber: pick.pickNumber,
            teamNeeds: pickingNeeds
        )
        pick.mediaGrade = media.grade
        pick.mediaHeadline = media.headline
        pick.mediaComment = media.comment

        // Convert prospect to a Player and insert into the data store
        let player = DraftEngine.convertToPlayer(
            prospect: prospect,
            teamID: pick.currentTeamID,
            pickNumber: pick.pickNumber
        )
        modelContext.insert(player)

        // Remove from the available pool
        availableProspects.removeAll { $0.id == prospect.id }

        // Show media toast.
        let isPlayerPick = pick.currentTeamID == career.teamID
        showMediaCommentary(
            grade: media.grade,
            headline: media.headline,
            comment: media.comment,
            playerName: prospect.fullName,
            isPlayerPick: isPlayerPick
        )

        // Check for round transition.
        let previousRound = pick.round
        currentPickIndex += 1
        isSimulating = false

        // Reset clock for next player pick.
        clockSeconds = 120

        if let nextPick = currentPick, nextPick.round > previousRound {
            showRoundTransition(round: nextPick.round)
        } else {
            advanceIfNeeded()
        }

        // Refresh team needs after picking.
        if isPlayerPick {
            refreshTeamNeeds()
        }
    }

    /// Player hits "Auto-Pick" — engine selects best available for their needs.
    private func autoPickForPlayer(pick: DraftPick) {
        let roster = fetchRoster(for: pick.currentTeamID)
        let chosen: CollegeProspect
        if let team = playerTeam, !availableProspects.isEmpty {
            chosen = DraftEngine.aiMakePick(
                team: team,
                availableProspects: availableProspects,
                teamRoster: roster
            )
        } else if let first = availableProspects.first {
            chosen = first
        } else {
            return
        }
        completePick(pick: pick, prospect: chosen)
    }

    /// Checks whether the engine wants to generate an incoming trade offer.
    private func considerAITradeOffer() {
        guard let pick = currentPick else { return }
        let teams = Array(teamsByID.values)
        let engineOffers = DraftEngine.generateAITradeOffers(
            currentPick: pick,
            allPicks: allPicks,
            teams: teams
        )

        // Present only the first offer as a display model
        guard let engineOffer = engineOffers.first else { return }
        pendingTradeOffer = buildDisplayOffer(from: engineOffer)
    }

    /// Accepts a trade offer: reassigns pick ownership and saves changes.
    private func acceptTradeOffer(_ displayOffer: DraftTradeOfferDisplay) {
        let domainOffer = displayOffer.domainOffer

        // Transfer the requested picks to the offering team
        for pickID in domainOffer.picksReceiving {
            if let pick = allPicks.first(where: { $0.id == pickID }) {
                pick.currentTeamID = domainOffer.offeringTeamID
            }
        }
        // Transfer the offered picks to the player's team
        for pickID in domainOffer.picksSending {
            if let pick = allPicks.first(where: { $0.id == pickID }) {
                pick.currentTeamID = domainOffer.receivingTeamID
            }
        }

        pendingTradeOffer = nil
        // Re-evaluate — the player now owns a later pick, so advance AI picks
        advanceIfNeeded()
    }

    // MARK: - Data Loading

    private func loadDraftData() {
        let season = career.currentSeason

        var pickDesc = FetchDescriptor<DraftPick>(
            predicate: #Predicate { $0.seasonYear == season }
        )
        pickDesc.sortBy = [SortDescriptor(\.pickNumber)]
        allPicks = (try? modelContext.fetch(pickDesc)) ?? []

        // Resume from the first incomplete pick
        currentPickIndex = allPicks.firstIndex(where: { !$0.isComplete }) ?? allPicks.count

        // Prospects not yet linked to a completed pick
        let draftedIDs = Set(allPicks.compactMap { $0.playerID })
        var prospectDesc = FetchDescriptor<CollegeProspect>(
            predicate: #Predicate { $0.isDeclaringForDraft }
        )
        prospectDesc.sortBy = [SortDescriptor(\.lastName)]
        let allProspects = (try? modelContext.fetch(prospectDesc)) ?? []
        availableProspects = allProspects.filter { !draftedIDs.contains($0.id) }

        // Build team lookup
        let teams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []
        teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        if let teamID = career.teamID {
            playerTeam = teamsByID[teamID]

            // Load coaching staff
            let coachDesc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
            teamCoaches = (try? modelContext.fetch(coachDesc)) ?? []

            // Calculate initial team needs
            refreshTeamNeeds()
        }

        advanceIfNeeded()
    }

    // MARK: - Helpers

    private func fetchRoster(for teamID: UUID) -> [Player] {
        let desc = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        return (try? modelContext.fetch(desc)) ?? []
    }

    private func teamAbbreviation(for teamID: UUID?) -> String? {
        guard let teamID else { return nil }
        return teamsByID[teamID]?.abbreviation
    }

    private func teamName(for teamID: UUID?) -> String? {
        guard let teamID else { return nil }
        return teamsByID[teamID]?.fullName
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    /// Converts a domain `TradeOffer` to a `DraftTradeOfferDisplay` for the UI.
    private func buildDisplayOffer(from domainOffer: TradeOffer) -> DraftTradeOfferDisplay {
        let offeringTeam = teamsByID[domainOffer.offeringTeamID]

        let assetsOffered: [DraftTradeAsset] = domainOffer.picksSending.compactMap { pickID in
            guard let pick = allPicks.first(where: { $0.id == pickID }) else { return nil }
            let value = DraftEngine.pickValue(pick.pickNumber)
            return DraftTradeAsset(
                id: pick.id,
                label: "\(pick.seasonYear) Round \(pick.round) Pick",
                detail: "Pick #\(pick.pickNumber)  ·  \(value) pts",
                value: value
            )
        }

        let assetsRequested: [DraftTradeAsset] = domainOffer.picksReceiving.compactMap { pickID in
            guard let pick = allPicks.first(where: { $0.id == pickID }) else { return nil }
            let value = DraftEngine.pickValue(pick.pickNumber)
            return DraftTradeAsset(
                id: pick.id,
                label: "\(pick.seasonYear) Round \(pick.round) Pick",
                detail: "Pick #\(pick.pickNumber)  ·  \(value) pts",
                value: value
            )
        }

        return DraftTradeOfferDisplay(
            offeringTeamName: offeringTeam?.fullName ?? "Unknown Team",
            offeringTeamAbbreviation: offeringTeam?.abbreviation ?? "???",
            assetsOffered: assetsOffered,
            assetsRequested: assetsRequested,
            domainOffer: domainOffer
        )
    }

    // MARK: - War Room Panel

    /// Inline war room panel shown below the on-the-clock card when it's the player's turn.
    private var warRoomPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentGold)
                Text("WAR ROOM")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(1.5)
                Spacer()
                Text("\(staffRecommendations.count) suggestions")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(staffRecommendations) { rec in
                        staffRecommendationCard(rec)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .background(
            Color.backgroundSecondary
                .overlay(Color.accentGold.opacity(0.03))
        )
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func staffRecommendationCard(_ recommendation: DraftEngine.StaffRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: recommendation.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentGold)
                Text(recommendation.staffTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.accentGold)
            }
            Text(recommendation.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Media Commentary Toast

    private func mediaToastView(_ toast: MediaToast) -> some View {
        HStack(spacing: 12) {
            // Grade circle
            ZStack {
                Circle()
                    .fill(mediaGradeColor(toast.grade).opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(toast.grade)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(mediaGradeColor(toast.grade))
            }

            VStack(alignment: .leading, spacing: 3) {
                if toast.isPlayerPick {
                    Text("YOUR PICK")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.accentGold)
                        .tracking(1)
                }
                Text(toast.headline)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text(toast.comment)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "mic.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            toast.isPlayerPick ? Color.accentGold.opacity(0.5) : Color.surfaceBorder,
                            lineWidth: toast.isPlayerPick ? 1.5 : 1
                        )
                )
                .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 4)
        )
    }

    // MARK: - Round Transition Banner

    private var roundTransitionBanner: some View {
        VStack(spacing: 12) {
            Text("ROUND \(roundBannerNumber)")
                .font(.system(size: 36, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .tracking(4)
            Text("BEGINS")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .tracking(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundPrimary.opacity(0.92))
    }

    // MARK: - Draft Summary Sheet

    private var draftSummarySheet: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 8) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(Color.accentGold)
                            Text("Your Draft Class")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Color.textPrimary)

                            let playerPicks = allPicks.filter { $0.currentTeamID == career.teamID && $0.isComplete }
                            let avgGrade = averageGradeLabel(for: playerPicks)
                            Text("Overall Grade: \(avgGrade)")
                                .font(.headline)
                                .foregroundStyle(Color.accentGold)
                        }
                        .padding(.top, 8)

                        // Individual picks
                        let playerPicks = allPicks.filter { $0.currentTeamID == career.teamID && $0.isComplete }
                        ForEach(playerPicks) { pick in
                            draftSummaryRow(pick)
                        }

                        if playerPicks.isEmpty {
                            Text("No picks made.")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 600)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Draft Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showDraftSummary = false }
                }
            }
        }
    }

    private func draftSummaryRow(_ pick: DraftPick) -> some View {
        HStack(spacing: 14) {
            // Pick number
            VStack(spacing: 2) {
                Text("R\(pick.round)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                Text("#\(pick.pickNumber)")
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(pick.playerName ?? "Unknown")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 8) {
                    if let pos = pick.playerPosition {
                        Text(pos)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 4))
                    }
                    if let college = pick.playerCollege {
                        Text(college)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                if let headline = pick.mediaHeadline {
                    Text(headline)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                        .italic()
                }
            }

            Spacer()

            // Media grade
            if let grade = pick.mediaGrade {
                VStack(spacing: 2) {
                    Text(grade)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(mediaGradeColor(grade))
                    Text("GRADE")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(0.5)
                }
                .frame(width: 50)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Media & War Room Logic

    /// Shows a media toast that fades after a few seconds.
    private func showMediaCommentary(
        grade: String,
        headline: String,
        comment: String,
        playerName: String,
        isPlayerPick: Bool
    ) {
        let toast = MediaToast(
            grade: grade,
            headline: headline,
            comment: comment,
            playerName: playerName,
            isPlayerPick: isPlayerPick
        )
        mediaToast = toast

        withAnimation(.easeInOut(duration: 0.3)) {
            showMediaToast = true
        }

        // Auto-dismiss: longer for player picks.
        let delay: Double = isPlayerPick ? 5.0 : 3.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if self.mediaToast?.id == toast.id {
                withAnimation(.easeInOut(duration: 0.4)) {
                    showMediaToast = false
                }
            }
        }
    }

    /// Shows the round transition banner then continues simulation.
    private func showRoundTransition(round: Int) {
        roundBannerNumber = round
        withAnimation(.easeInOut(duration: 0.4)) {
            showRoundBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.4)) {
                showRoundBanner = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                advanceIfNeeded()
            }
        }
    }

    /// Generates coaching staff recommendations for the war room.
    private func generateWarRoomRecommendations() {
        staffRecommendations = DraftEngine.generateStaffRecommendations(
            availableProspects: availableProspects,
            teamNeeds: teamNeeds,
            coaches: teamCoaches
        )
    }

    /// Refreshes team needs based on current roster.
    private func refreshTeamNeeds() {
        guard let teamID = career.teamID else { return }
        let roster = fetchRoster(for: teamID)
        teamNeeds = DraftEngine.topTeamNeeds(roster: roster)
    }

    /// Starts the cosmetic on-the-clock countdown timer.
    private func startClockTimer() {
        clockSeconds = 120
        func tick() {
            guard isPlayerTurn && clockSeconds > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                guard self.isPlayerTurn else { return }
                self.clockSeconds -= 1
                tick()
            }
        }
        tick()
    }

    private func mediaGradeColor(_ grade: String) -> Color {
        switch grade {
        case "A+", "A":   return .success
        case "A-", "B+":  return .accentGold
        case "B", "B-":   return .warning
        default:          return .danger
        }
    }

    private func averageGradeLabel(for picks: [DraftPick]) -> String {
        let gradeScale = ["A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D", "F"]
        let grades = picks.compactMap(\.mediaGrade)
        guard !grades.isEmpty else { return "N/A" }
        let totalIndex = grades.reduce(0) { sum, grade in
            sum + (gradeScale.firstIndex(of: grade) ?? 4)
        }
        let avgIndex = min(gradeScale.count - 1, max(0, totalIndex / grades.count))
        return gradeScale[avgIndex]
    }
}

// MARK: - Media Toast Model

/// Lightweight model for the media commentary toast overlay.
struct MediaToast: Identifiable {
    let id = UUID()
    let grade: String
    let headline: String
    let comment: String
    let playerName: String
    let isPlayerPick: Bool
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DraftView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, DraftPick.self, CollegeProspect.self, Team.self, Player.self], inMemory: true)
}
