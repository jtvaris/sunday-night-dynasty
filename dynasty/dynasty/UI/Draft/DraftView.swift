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

    /// Index into allPicks indicating which pick is currently on the clock.
    @State private var currentPickIndex: Int = 0
    /// Whether the AI simulation timer is running.
    @State private var isSimulating: Bool = false
    /// Whether the player's selection sheet is presented.
    @State private var showSelectionSheet: Bool = false
    /// An incoming AI trade offer display model, if any.
    @State private var pendingTradeOffer: DraftTradeOfferDisplay?

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
                    bigBoardSidebar
                        .frame(width: 320)
                }
            } else {
                mainColumn
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
    }

    // MARK: - Main Column

    private var mainColumn: some View {
        VStack(spacing: 0) {
            draftHeader
            onTheClockCard
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

            Text("Round \(pick.round)  ·  Pick \(pick.pickNumber)")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.textPrimary)

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

    // MARK: - Big Board Sidebar (iPad)

    private var bigBoardSidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader

            let scoutedBoard = availableProspects
                .filter { $0.scoutedOverall != nil }
                .sorted { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }

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
        .background(Color.backgroundSecondary)
    }

    private var sidebarHeader: some View {
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
        .background(Color.backgroundTertiary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
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
        guard !draftComplete else { return }
        guard !isPlayerTurn else {
            // It's the player's turn — check for incoming trade offer first
            considerAITradeOffer()
            return
        }
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
        pick.playerID = prospect.id
        pick.playerName = prospect.fullName
        pick.playerPosition = prospect.position.rawValue
        pick.playerCollege = prospect.college
        pick.scoutGrade = prospect.scoutGrade
        pick.teamAbbreviation = teamAbbreviation(for: pick.currentTeamID)
        pick.isComplete = true

        // Convert prospect to a Player and insert into the data store
        let player = DraftEngine.convertToPlayer(
            prospect: prospect,
            teamID: pick.currentTeamID,
            pickNumber: pick.pickNumber
        )
        modelContext.insert(player)

        // Remove from the available pool
        availableProspects.removeAll { $0.id == prospect.id }

        currentPickIndex += 1
        isSimulating = false

        advanceIfNeeded()
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
