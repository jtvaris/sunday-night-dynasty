import SwiftUI
import SwiftData

// MARK: - DraftView

/// The main NFL Draft event screen.
/// Drives simulation: AI picks auto-advance with a brief delay; the player's pick
/// pauses and presents the selection sheet.
struct DraftView: View {

    /// Tabs for the right-side sidebar shown on iPad.
    enum SidebarTab: String, CaseIterable {
        case bigBoard, history, warRoom
    }

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
    /// Currently active right-sidebar tab on iPad.
    @State private var activeSidebarTab: SidebarTab = .bigBoard
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
    /// Fan reactions (social media feed) after each player pick.
    @State private var fanReactions: [String] = []
    /// Whether the fan reactions panel is visible.
    @State private var showFanReactions: Bool = false
    /// Whether the "YOUR PICK" badge / on-clock card is currently pulsing.
    @State private var isPulsing: Bool = false
    /// Whether a slide-in trade-offer banner is currently visible.
    @State private var showTradeOfferBanner: Bool = false
    /// Whether the trade-offer modal sheet is presented (separate from the banner).
    @State private var showTradeOfferSheet: Bool = false

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

            // MARK: Trade Offer Slide-in Banner
            if showTradeOfferBanner, let offer = pendingTradeOffer {
                VStack {
                    tradeOfferBanner(offer)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    Spacer()
                }
                .zIndex(8)
            }
        }
        .navigationTitle("NFL Draft \(career.currentSeason)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarContent }
        .task { loadDraftData() }
        .onAppear { startPulse() }
        .sheet(isPresented: $showSelectionSheet) {
            if let pick = currentPick {
                DraftSelectionSheet(
                    career: career,
                    availableProspects: availableProspects,
                    pickNumber: pick.pickNumber,
                    round: pick.round,
                    teamNeeds: teamNeeds,
                    teamCoaches: teamCoaches,
                    onDraft: { prospect in
                        completePick(pick: pick, prospect: prospect)
                    }
                )
            }
        }
        .sheet(isPresented: $showTradeOfferSheet) {
            if let displayOffer = pendingTradeOffer {
                TradeOfferView(
                    offer: displayOffer,
                    availableProspects: availableProspects,
                    teamNeeds: teamNeeds,
                    onAccept: { acceptTradeOffer(displayOffer) },
                    onDecline: { dismissTradeOffer() }
                )
            }
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
            if !teamNeeds.isEmpty {
                teamNeedsStrip
            }
            if isPlayerTurn {
                pickRecommendationsPanel
            }
            if isPlayerTurn && !staffRecommendations.isEmpty {
                warRoomPanel
            }
            if horizontalSizeClass != .regular && showFanReactions && !fanReactions.isEmpty {
                fanReactionsFeed
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            Divider().overlay(Color.surfaceBorder)
            draftBoardScrollView
        }
    }

    // MARK: - Team Needs Strip

    /// Compact pills showing top positional needs, with green checkmarks for addressed needs.
    private var teamNeedsStrip: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Text("TEAM NEEDS")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(1.5)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(teamNeeds.prefix(5).enumerated()), id: \.element) { index, position in
                            let addressed = isNeedAddressed(position)
                            HStack(spacing: 4) {
                                if addressed {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color.success)
                                }
                                Text("\(index + 1). \(position.rawValue)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(addressed ? Color.success : Color.textPrimary)
                                Text("(\(needGradeLabel(position)))")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(addressed ? Color.success.opacity(0.7) : Color.textTertiary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(addressed ? Color.success.opacity(0.12) : Color.backgroundTertiary)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(addressed ? Color.success.opacity(0.3) : Color.surfaceBorder, lineWidth: 1)
                                    )
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.backgroundSecondary)
            .overlay(
                Rectangle()
                    .fill(Color.surfaceBorder)
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    /// Whether a need position was addressed by drafting a player at that position.
    private func isNeedAddressed(_ position: Position) -> Bool {
        guard let teamID = career.teamID else { return false }
        let playerPicks = allPicks.filter { $0.currentTeamID == teamID && $0.isComplete }
        return playerPicks.contains { $0.playerPosition == position.rawValue }
    }

    /// Returns a letter grade for the roster at the given position.
    private func needGradeLabel(_ position: Position) -> String {
        guard let teamID = career.teamID else { return "?" }
        let roster = fetchRoster(for: teamID)
        let posPlayers = roster.filter { $0.position == position }
        guard !posPlayers.isEmpty else { return "F" }
        let avg = posPlayers.map(\.overall).reduce(0, +) / posPlayers.count
        switch avg {
        case 85...:  return "A"
        case 80..<85: return "B+"
        case 75..<80: return "B"
        case 70..<75: return "C+"
        case 65..<70: return "C"
        case 60..<65: return "C-"
        case 55..<60: return "D"
        default:      return "F"
        }
    }

    // MARK: - Draft Header Bar

    private var draftHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("NFL DRAFT")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(Color.textSecondary)
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
                        .tint(Color.accentBlue)
                        .frame(width: 100)
                }
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
        let clockColor: Color = clockSeconds <= 30 ? Color.danger : Color.accentGold

        return VStack(spacing: 16) {
            // Pulsing "YOUR PICK" header.
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.accentGold)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isPulsing ? 1.4 : 1.0)
                    .opacity(isPulsing ? 0.5 : 1.0)
                Text("YOU'RE ON THE CLOCK")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .tracking(2.5)
                Circle()
                    .fill(Color.accentGold)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isPulsing ? 1.4 : 1.0)
                    .opacity(isPulsing ? 0.5 : 1.0)
            }

            // Hero row: team logo · big countdown · pick info
            HStack(alignment: .center, spacing: 18) {
                // Team "logo" tile
                if let teamID = career.teamID {
                    Text(teamAbbreviation(for: teamID) ?? "—")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(width: 64, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.accentGold)
                                .shadow(color: Color.accentGold.opacity(0.4), radius: 8, x: 0, y: 3)
                        )
                }

                // Big countdown clock
                VStack(spacing: 2) {
                    Text(String(format: "%d:%02d", clockSeconds / 60, clockSeconds % 60))
                        .font(.system(size: 44, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(clockColor)
                        .scaleEffect(clockSeconds <= 30 && isPulsing ? 1.05 : 1.0)
                    Text("ON THE CLOCK")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(2)
                }
                .frame(maxWidth: .infinity)
                .onAppear { startClockTimer() }

                // Pick info
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ROUND \(pick.round)")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(1.5)
                    Text("#\(pick.pickNumber)")
                        .font(.system(size: 28, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text("of \(allPicks.count)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .monospacedDigit()
                }
            }

            // Action buttons
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
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
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
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
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
            ZStack {
                Color.backgroundSecondary
                LinearGradient(
                    colors: [Color.accentGold.opacity(0.08), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .overlay(
            Rectangle()
                .fill(Color.accentGold.opacity(0.6))
                .frame(height: 2),
            alignment: .top
        )
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
        .onAppear { startPulse() }
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

    /// Combined sidebar with Big Board, History, and War Room tabs on iPad.
    private var rightSidebar: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                sidebarTab(title: "Big Board", icon: "list.star", isActive: activeSidebarTab == .bigBoard) {
                    activeSidebarTab = .bigBoard
                }
                sidebarTab(title: "History", icon: "clock.arrow.circlepath", isActive: activeSidebarTab == .history) {
                    activeSidebarTab = .history
                }
                sidebarTab(title: "War Room", icon: "person.3.fill", isActive: activeSidebarTab == .warRoom) {
                    activeSidebarTab = .warRoom
                }
            }
            .background(Color.backgroundTertiary)
            .overlay(
                Rectangle()
                    .fill(Color.surfaceBorder)
                    .frame(height: 1),
                alignment: .bottom
            )

            switch activeSidebarTab {
            case .bigBoard:
                bigBoardContent
            case .history:
                pickHistorySidebarContent
            case .warRoom:
                warRoomSidebarContent
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
            .foregroundStyle(isActive ? Color.accentBlue : Color.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                Rectangle()
                    .fill(isActive ? Color.accentBlue : Color.clear)
                    .frame(height: 2),
                alignment: .bottom
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// Pick history sidebar content — scrollable list of every completed pick with media grade.
    private var pickHistorySidebarContent: some View {
        let picks = allPicks.prefix(currentPickIndex)

        return Group {
            if picks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.textTertiary)
                    Text("No picks yet")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Picks 1–\(currentPickIndex)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("\(currentPickIndex)/\(allPicks.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider().overlay(Color.surfaceBorder)

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(picks)) { pick in
                                pickHistoryRow(pick)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                    }
                }
            }
        }
    }

    private func pickHistoryRow(_ pick: DraftPick) -> some View {
        let isPlayerTeam = pick.currentTeamID == career.teamID

        return HStack(spacing: 8) {
            // Pick number
            VStack(spacing: 0) {
                Text("R\(pick.round)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                Text("#\(pick.pickNumber)")
                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                    .foregroundStyle(isPlayerTeam ? Color.accentGold : Color.textPrimary)
            }
            .frame(width: 30)

            // Team abbreviation
            Text(pick.teamAbbreviation ?? teamAbbreviation(for: pick.currentTeamID) ?? "—")
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 32, height: 22)
                .background(
                    (isPlayerTeam ? Color.accentGold : Color.accentBlue),
                    in: RoundedRectangle(cornerRadius: 4)
                )

            // Player info
            VStack(alignment: .leading, spacing: 2) {
                if pick.isComplete {
                    Text(pick.playerName ?? "—")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let pos = pick.playerPosition {
                            Text(pos)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.textTertiary)
                        }
                        if let college = pick.playerCollege {
                            Text("·")
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                            Text(college)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                        }
                    }
                } else {
                    Text("Pending")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                        .italic()
                }
            }

            Spacer(minLength: 4)

            // Media grade pill
            if let grade = pick.mediaGrade {
                Text(grade)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(mediaGradeColor(grade))
                    .frame(minWidth: 26, minHeight: 22)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(mediaGradeColor(grade).opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(mediaGradeColor(grade).opacity(0.4), lineWidth: 1)
                            )
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isPlayerTeam ? Color.accentGold.opacity(0.08) : Color.backgroundPrimary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isPlayerTeam ? Color.accentGold.opacity(0.3) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
    }

    /// War room content for the iPad sidebar.
    private var warRoomSidebarContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                if staffRecommendations.isEmpty && fanReactions.isEmpty {
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

                // Fan Reactions Feed
                if !fanReactions.isEmpty {
                    fanReactionsFeed
                }
            }
            .padding(12)
        }
    }

    // MARK: - Fan Reactions Feed

    /// Social media feed shown in the war room after the player's picks.
    private var fanReactionsFeed: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentBlue)
                Text("FAN REACTIONS")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.accentBlue)
                    .tracking(1.5)
                Spacer()
            }
            .padding(.bottom, 4)

            ForEach(Array(fanReactions.enumerated()), id: \.offset) { index, reaction in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(fanAvatarColor(index))
                        .frame(width: 24, height: 24)
                        .overlay(
                            Text(fanHandle(index).prefix(1).uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.backgroundPrimary)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(fanHandle(index))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                        Text(reaction)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)

                if index < fanReactions.count - 1 {
                    Divider().overlay(Color.surfaceBorder.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
    }

    private func fanAvatarColor(_ index: Int) -> Color {
        let colors: [Color] = [.accentBlue, .accentGold, .success, .danger, .warning]
        return colors[index % colors.count]
    }

    private func fanHandle(_ index: Int) -> String {
        let handles = ["GridironFan42", "DraftNerd88", "NFLHotTakes", "PickMaster", "CheeseheadLarry"]
        return handles[index % handles.count]
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
                .foregroundStyle(Color.textPrimary)
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
            // Generate fan reactions for the player's pick
            fanReactions = DraftEngine.generateFanReaction(
                prospect: prospect,
                pickNumber: pick.pickNumber,
                teamNeeds: pickingNeeds,
                gmName: career.playerName
            )
            showFanReactions = true
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

        // Present only the first offer as a display model — surface as a slide-in banner.
        guard let engineOffer = engineOffers.first else { return }
        pendingTradeOffer = buildDisplayOffer(from: engineOffer)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
            showTradeOfferBanner = true
        }
    }

    /// Dismisses the slide-in trade-offer banner and clears any pending offer.
    private func dismissTradeOffer() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showTradeOfferBanner = false
        }
        showTradeOfferSheet = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pendingTradeOffer = nil
        }
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

        showTradeOfferSheet = false
        withAnimation(.easeInOut(duration: 0.25)) {
            showTradeOfferBanner = false
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

    // MARK: - Top Pick Recommendations

    /// A lightweight recommendation shown to the player when on the clock — combines big board with team needs.
    private struct PickRecommendation: Identifiable {
        let id = UUID()
        let prospect: CollegeProspect
        let rationale: String
        let badge: String
    }

    /// Computes the top-3 pick recommendations using the big board (scoutedOverall) and current team needs.
    private var topPickRecommendations: [PickRecommendation] {
        let scouted = availableProspects.filter { $0.scoutedOverall != nil }
        guard !scouted.isEmpty else { return [] }

        let needsSet = Set(teamNeeds.prefix(5))

        // Score each prospect: scouted overall + need bonus.
        let scored: [(CollegeProspect, Int, Bool)] = scouted.map { prospect in
            let base = prospect.scoutedOverall ?? 0
            let needsMatch = needsSet.contains(prospect.position)
            let needBonus = needsMatch ? 8 : 0
            return (prospect, base + needBonus, needsMatch)
        }

        let sorted = scored.sorted { $0.1 > $1.1 }
        let topThree = sorted.prefix(3)

        return topThree.enumerated().map { index, tuple in
            let (prospect, _, needsMatch) = tuple
            let badge: String
            let rationale: String
            switch index {
            case 0:
                badge = "BEST PICK"
                if needsMatch {
                    rationale = "Top of your board and fills your #\(needRank(prospect.position)) need at \(prospect.position.rawValue)."
                } else {
                    rationale = "Highest-graded player on your board — too good to pass on."
                }
            case 1:
                badge = "NEED FIT"
                if needsMatch {
                    rationale = "Strong value at \(prospect.position.rawValue), one of your top roster needs."
                } else {
                    rationale = "Premium talent on the board behind your top option."
                }
            default:
                badge = "VALUE"
                if needsMatch {
                    rationale = "Solid \(prospect.position.rawValue) prospect that addresses a real gap."
                } else {
                    rationale = "Best player available — long-term ceiling pick."
                }
            }
            return PickRecommendation(prospect: prospect, rationale: rationale, badge: badge)
        }
    }

    /// Returns the 1-indexed rank of a position in `teamNeeds`, or 0 if absent.
    private func needRank(_ position: Position) -> Int {
        (teamNeeds.firstIndex(of: position) ?? -1) + 1
    }

    /// Panel showing the top 3 recommended picks with one-line rationale.
    @ViewBuilder
    private var pickRecommendationsPanel: some View {
        let recs = topPickRecommendations
        if !recs.isEmpty {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentGold)
                    Text("RECOMMENDED PICKS")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.accentGold)
                        .tracking(1.5)
                    Spacer()
                    Text("BIG BOARD + NEEDS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(recs.enumerated()), id: \.element.id) { index, rec in
                            recommendationCard(rec, rank: index + 1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }
            .background(Color.backgroundSecondary)
            .overlay(
                Rectangle()
                    .fill(Color.surfaceBorder)
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    private func recommendationCard(_ rec: PickRecommendation, rank: Int) -> some View {
        let badgeColor: Color = rank == 1 ? .accentGold : (rank == 2 ? .accentBlue : .textSecondary)

        return Button {
            showSelectionSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("#\(rank)")
                        .font(.system(size: 11, weight: .heavy).monospacedDigit())
                        .foregroundStyle(badgeColor)
                    Text(rec.badge)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(badgeColor)
                        .tracking(1.2)
                    Spacer(minLength: 0)
                    if let overall = rec.prospect.scoutedOverall {
                        Text("\(overall)")
                            .font(.system(size: 13, weight: .heavy).monospacedDigit())
                            .foregroundStyle(Color.forRating(overall))
                    }
                }

                HStack(spacing: 6) {
                    Text(rec.prospect.position.rawValue)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(positionColor(rec.prospect.position), in: RoundedRectangle(cornerRadius: 3))
                    Text(rec.prospect.fullName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }

                Text(rec.rationale)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(width: 260, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.backgroundTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(badgeColor.opacity(rank == 1 ? 0.55 : 0.25), lineWidth: rank == 1 ? 1.5 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trade Offer Slide-in Banner

    /// Compact slide-in banner shown when an AI team sends a trade offer. Tapping it opens the full sheet.
    private func tradeOfferBanner(_ offer: DraftTradeOfferDisplay) -> some View {
        HStack(spacing: 12) {
            // Team logo tile
            Text(offer.offeringTeamAbbreviation)
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(Color.backgroundPrimary)
                .frame(width: 40, height: 40)
                .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentBlue)
                    Text("INCOMING TRADE OFFER")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.accentBlue)
                        .tracking(1.5)
                }
                Text(offer.offeringTeamName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("Tap to review · \(offer.assetsOffered.count) for \(offer.assetsRequested.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Review button
            Button {
                showTradeOfferSheet = true
            } label: {
                Text("Review")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            // Dismiss button
            Button {
                dismissTradeOffer()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.accentBlue.opacity(0.6), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 4)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            showTradeOfferSheet = true
        }
    }

    // MARK: - War Room Panel

    /// Inline war room panel shown below the on-the-clock card when it's the player's turn.
    private var warRoomPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                Text("WAR ROOM")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
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
        .background(Color.backgroundSecondary)
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
                    .foregroundStyle(Color.accentBlue)
                Text(recommendation.staffTitle)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
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
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.accentGold)
                            .frame(width: 6, height: 6)
                            .scaleEffect(isPulsing ? 1.4 : 1.0)
                            .opacity(isPulsing ? 0.5 : 1.0)
                        Text("YOUR PICK")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.accentGold)
                            .tracking(1)
                    }
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
                    let playerPicks = allPicks.filter { $0.currentTeamID == career.teamID && $0.isComplete }
                    let avgGrade = averageGradeLabel(for: playerPicks)

                    VStack(spacing: 24) {
                        // Hero overall-grade card
                        draftSummaryHeroCard(grade: avgGrade, playerPicks: playerPicks)

                        // Pick-by-pick breakdown
                        if !playerPicks.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 6) {
                                    Image(systemName: "list.clipboard.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Color.textTertiary)
                                    Text("PICK-BY-PICK BREAKDOWN")
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundStyle(Color.textTertiary)
                                        .tracking(1.5)
                                    Spacer()
                                    Text("\(playerPicks.count) picks")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Color.textTertiary)
                                }
                                .padding(.horizontal, 4)

                                VStack(spacing: 10) {
                                    ForEach(playerPicks) { pick in
                                        draftSummaryRow(pick)
                                    }
                                }
                            }
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color.textTertiary)
                                Text("No picks made.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            .padding(.top, 40)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 640)
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

    /// Hero card showing the overall draft grade prominently along with pick stats.
    private func draftSummaryHeroCard(grade: String, playerPicks: [DraftPick]) -> some View {
        let gradeColor = mediaGradeColor(grade)

        let gradeDistribution: [(String, Int)] = {
            let grades = playerPicks.compactMap(\.mediaGrade)
            let buckets: [String] = ["A", "B", "C", "D", "F"]
            return buckets.map { letter in
                (letter, grades.filter { $0.hasPrefix(letter) }.count)
            }
        }()

        return VStack(spacing: 18) {
            // Trophy + heading
            VStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentGold)
                Text("YOUR DRAFT CLASS")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.textTertiary)
                    .tracking(2)
                Text(career.currentSeason.description)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .monospacedDigit()
            }

            // Big grade circle
            ZStack {
                Circle()
                    .fill(gradeColor.opacity(0.12))
                    .frame(width: 140, height: 140)
                Circle()
                    .strokeBorder(gradeColor.opacity(0.45), lineWidth: 3)
                    .frame(width: 140, height: 140)
                VStack(spacing: 2) {
                    Text(grade)
                        .font(.system(size: 56, weight: .heavy, design: .rounded))
                        .foregroundStyle(gradeColor)
                    Text("OVERALL")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(2)
                }
            }

            // Stats row
            HStack(spacing: 0) {
                heroStat(label: "PICKS", value: "\(playerPicks.count)")
                Divider().frame(height: 32).overlay(Color.surfaceBorder)
                heroStat(label: "BEST", value: bestGradeLabel(for: playerPicks))
                Divider().frame(height: 32).overlay(Color.surfaceBorder)
                heroStat(label: "AVG", value: grade)
            }

            // Grade distribution
            if !playerPicks.isEmpty {
                HStack(spacing: 8) {
                    ForEach(gradeDistribution, id: \.0) { letter, count in
                        VStack(spacing: 4) {
                            Text("\(count)")
                                .font(.system(size: 16, weight: .heavy).monospacedDigit())
                                .foregroundStyle(count > 0 ? letterColor(letter) : Color.textTertiary)
                            Text(letter)
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Color.textTertiary)
                                .tracking(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(count > 0 ? letterColor(letter).opacity(0.12) : Color.backgroundTertiary)
                        )
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(gradeColor.opacity(0.35), lineWidth: 1.5)
                )
        )
    }

    private func heroStat(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color.textTertiary)
                .tracking(1.5)
        }
        .frame(maxWidth: .infinity)
    }

    private func letterColor(_ letter: String) -> Color {
        switch letter {
        case "A": return .success
        case "B": return .accentBlue
        case "C": return .accentGold
        case "D": return .warning
        default:  return .danger
        }
    }

    private func bestGradeLabel(for picks: [DraftPick]) -> String {
        let gradeScale = ["A+", "A", "A-", "B+", "B", "B-", "C+", "C", "C-", "D", "F"]
        let grades = picks.compactMap(\.mediaGrade)
        guard !grades.isEmpty else { return "—" }
        let best = grades.min { lhs, rhs in
            (gradeScale.firstIndex(of: lhs) ?? 99) < (gradeScale.firstIndex(of: rhs) ?? 99)
        }
        return best ?? "—"
    }

    private func draftSummaryRow(_ pick: DraftPick) -> some View {
        let gradeColor = pick.mediaGrade.map { mediaGradeColor($0) } ?? Color.textTertiary

        return HStack(spacing: 14) {
            // Pick number
            VStack(spacing: 2) {
                Text("R\(pick.round)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                Text("#\(pick.pickNumber)")
                    .font(.system(size: 16, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
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
                            .lineLimit(1)
                    }
                }
                if let headline = pick.mediaHeadline {
                    Text(headline)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                        .italic()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            // Media grade — bold circle.
            if let grade = pick.mediaGrade {
                ZStack {
                    Circle()
                        .fill(gradeColor.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Circle()
                        .strokeBorder(gradeColor.opacity(0.5), lineWidth: 1.5)
                        .frame(width: 52, height: 52)
                    Text(grade)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(gradeColor)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(gradeColor.opacity(0.3), lineWidth: 1)
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

    /// Starts (or restarts) a continuous pulse animation used by the YOUR PICK badge / chip.
    private func startPulse() {
        isPulsing = false
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            isPulsing = true
        }
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
        case "A+", "A", "A-":  return .success
        case "B+", "B", "B-":  return .accentBlue
        case "C+", "C", "C-":  return .accentGold
        case "D+", "D", "D-":  return .warning
        default:                return .danger
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
