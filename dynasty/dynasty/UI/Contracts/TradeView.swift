import SwiftUI
import SwiftData

// MARK: - TradeView

struct TradeView: View {

    let career: Career

    /// R21: lets the shell surface completed-trade notices in the inbox.
    var onInboxMessage: ((InboxMessage) -> Void)? = nil

    /// Opens the builder already pointed at a partner (and optionally at players
    /// of theirs the user came here to ask about). Wave 2 UX: "Trade For" on
    /// `PlayerDetailView` and the Trade button in the league roster browser both
    /// arrive with the deal half-written instead of dropping the user on an
    /// empty 31-team picker (plan finding S8).
    var prefill: Prefill? = nil

    /// Partner + targets to preselect. `Equatable` so the apply-once guard can
    /// be reasoned about in one place.
    struct Prefill: Equatable {
        let partnerTeamID: UUID
        let targetPlayerIDs: [UUID]
        /// F-58: the mirror direction. When the user arrives from the shopping
        /// poll he is not asking about one of THEIR men, he is offering one of
        /// his own — so his column arrives ticked instead of theirs. Empty for
        /// every "Trade For" entry point, which is why it is defaulted.
        var offeredPlayerIDs: [UUID] = []

        init(partnerTeamID: UUID, targetPlayerIDs: [UUID], offeredPlayerIDs: [UUID] = []) {
            self.partnerTeamID = partnerTeamID
            self.targetPlayerIDs = targetPlayerIDs
            self.offeredPlayerIDs = offeredPlayerIDs
        }
    }

    @Environment(\.modelContext) private var modelContext

    // MARK: Data
    @State private var playerTeam: Team?
    @State private var allTeams: [Team] = []
    @State private var allPlayers: [Player] = []
    @State private var allPicks: [DraftPick] = []
    /// Detailed contracts, for the Wave 1 cap-truth rules: dead money on trades
    /// and no-trade-clause vetoes both live on the `Contract` row.
    @State private var allContracts: [Contract] = []

    // MARK: Propose Trade state
    @State private var selectedPartner: Team?
    @State private var mySelectedPlayers: Set<UUID> = []
    @State private var mySelectedPicks: Set<UUID> = []
    @State private var theirSelectedPlayers: Set<UUID> = []
    @State private var theirSelectedPicks: Set<UUID> = []

    // MARK: Incoming offers
    @State private var incomingOffers: [TradeProposal] = []

    // MARK: Negotiations (Wave 3)
    /// The conversation currently on screen. `nil` = nobody is on the phone.
    @State private var activeNegotiation: NegotiationRoute?
    /// A package the negotiation screen agreed to, waiting for the cover to
    /// finish dismissing so the result alert lands on the Trade Center rather
    /// than behind a disappearing modal.
    @State private var pendingAgreedDeal: (proposal: TradeProposal, startedByAI: Bool)?
    /// Live threads, newest first (mirror of `career.tradeThreads`).
    @State private var threads: [TradeNegotiationThread] = []

    // MARK: Feedback
    @State private var tradeResultMessage: String?
    @State private var showResultAlert = false
    @State private var resultIsSuccess = false

    // MARK: UI toggles
    @State private var showValueBreakdown = false

    // MARK: Trade history (session, this season)
    @State private var tradeHistory: [CompletedTrade] = []

    // MARK: Picks-only wizard
    @State private var wizardPickID: UUID?
    @State private var wizardPartnerID: UUID?

    /// A `prefill` is a starting position, not a lock: it is applied on the first
    /// load only, so `loadData()` after an executed trade doesn't re-tick a
    /// player the user just acquired (or just decided against).
    @State private var didApplyPrefill = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if TradeValueEngine.isTradeWindowOpen(
                phase: career.currentPhase,
                week: career.currentWeek
            ) {
                ScrollView {
                    VStack(spacing: 24) {
                        proposeSectionCard
                        openNegotiationsCard
                        pickWizardCard
                        incomingSectionCard
                        tradeHistoryCard
                    }
                    .padding(24)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            } else {
                tradeClosedView
            }
        }
        .navigationTitle("Trade Center")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
        .alert(tradeResultMessage ?? "", isPresented: $showResultAlert) {
            Button("OK", role: .cancel) {}
        }
        // Wave 3: the conversation. `TradeNegotiationView` supplies its own
        // "Close" toolbar item, so the wrapper must NOT add a second one.
        .fullScreenCover(item: $activeNegotiation, onDismiss: negotiationDismissed) { route in
            NavigationStack {
                TradeNegotiationView(
                    career: career,
                    partnerTeamID: route.partnerTeamID,
                    threadID: route.threadID,
                    seed: route.seed,
                    sourceOfferID: route.sourceOfferID,
                    openingLine: route.openingLine,
                    onDealAgreed: { proposal, thread in
                        pendingAgreedDeal = (proposal, thread.startedByAI)
                    },
                    onInboxMessage: { message in
                        deliver(message)
                    }
                )
            }
        }
    }

    // MARK: - Trade Closed

    private var tradeClosedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: DSType.Size.hero))
                .foregroundStyle(Color.textTertiary)
            Text("Trade Window Closed")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text("Trades are open during the offseason and the regular season through the Week \(TradeValueEngine.deadlineWeek) deadline. The window reopens after the season.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Scouting the league is never out of season, even when dealing is.
            leagueRostersLink
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - League Rosters Link

    /// Entry into the 32-roster browser. "Who has what?" is the first question of
    /// any trade, and the Trade Center used to have no answer to it — the partner
    /// picker was 31 abbreviations (plan finding S8).
    private var leagueRostersLink: some View {
        NavigationLink {
            LeagueRostersView(career: career)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentBlue)
                Text("Browse league rosters")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentBlue)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentBlue.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Propose Trade Section

    private var proposeSectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Propose Trade", icon: "arrow.left.arrow.right")

            leagueRostersLink

            // Partner picker
            partnerPicker

            if let partner = selectedPartner {
                Divider().overlay(Color.surfaceBorder)
                assetsGrid(partner: partner)
                Divider().overlay(Color.surfaceBorder)
                valueMeter
                valueBreakdownSection(partner: partner)
                Divider().overlay(Color.surfaceBorder)
                aiWillingnessRow(partner: partner)
                Divider().overlay(Color.surfaceBorder)
                capImpactSection(partner: partner)
                hardBlockersRow(partner: partner)
                Divider().overlay(Color.surfaceBorder)
                proposeButton(partner: partner)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardBackground()
    }

    // MARK: - Open Negotiations (Wave 3)

    /// Conversations already in progress. A trade talk is not a modal that ends
    /// when you close it — an offer can sit on a desk for weeks, so the threads
    /// live on `Career` and get their own shelf here.
    @ViewBuilder
    private var openNegotiationsCard: some View {
        let live = threads.filter { $0.status == .open }
        if !live.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(title: "Open Negotiations", icon: "bubble.left.and.bubble.right.fill")

                ForEach(live) { thread in
                    negotiationRow(thread)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .cardBackground()
        }
    }

    private func negotiationRow(_ thread: TradeNegotiationThread) -> some View {
        let partner = allTeams.first { $0.id == thread.partnerTeamID }
        let identity = partner.map {
            TradeValueEngine.gmIdentity(team: $0, season: career.currentSeason)
        }

        return Button {
            activeNegotiation = NegotiationRoute(
                partnerTeamID: thread.partnerTeamID,
                threadID: thread.id
            )
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(partner?.abbreviation ?? "???")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentGold, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                    if let identity {
                        Text(identity.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(identity.archetypeLabel)
                            .font(.system(size: DSType.Size.caption, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Text("Round \(thread.round)")
                        .font(.system(size: 10).weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textTertiary)
                }

                Text(thread.lastLine)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: DSType.Size.micro))
                    Text(TradeWindowRules.expiryNote(
                        phase: career.currentPhase, week: career.currentWeek
                    ))
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    if thread.pendingCounter != nil {
                        Text("· their counter is on the table")
                            .font(.system(size: DSType.Size.caption, weight: .semibold))
                            .foregroundStyle(Color.success)
                    }
                    Spacer()
                }
                .foregroundStyle(Color.warning)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.backgroundTertiary)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Partner Picker

    private var partnerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Trade Partner")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(otherTeams) { team in
                        Button {
                            if selectedPartner?.id == team.id {
                                selectedPartner = nil
                                clearSelections()
                            } else {
                                selectedPartner = team
                                clearSelections()
                            }
                        } label: {
                            Text(team.abbreviation)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(
                                    selectedPartner?.id == team.id
                                        ? Color.backgroundPrimary
                                        : Color.textSecondary
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(
                                            selectedPartner?.id == team.id
                                                ? Color.accentGold
                                                : Color.backgroundTertiary
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Assets Grid

    private func assetsGrid(partner: Team) -> some View {
        HStack(alignment: .top, spacing: 16) {
            assetColumn(
                title: "Your Assets",
                players: myPlayers,
                picks: myPicks,
                selectedPlayers: $mySelectedPlayers,
                selectedPicks: $mySelectedPicks,
                accentColor: Color.accentBlue,
                isTradeTargets: false
            )
            Divider()
                .overlay(Color.surfaceBorder)
                .frame(maxHeight: 600)
            assetColumn(
                title: "\(partner.abbreviation) Assets",
                players: theirPlayers(partner: partner),
                picks: theirPicks(partner: partner),
                selectedPlayers: $theirSelectedPlayers,
                selectedPicks: $theirSelectedPicks,
                accentColor: Color.accentGold,
                isTradeTargets: true
            )
        }
    }

    private func assetColumn(
        title: String,
        players: [Player],
        picks: [DraftPick],
        selectedPlayers: Binding<Set<UUID>>,
        selectedPicks: Binding<Set<UUID>>,
        accentColor: Color,
        isTradeTargets: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            // Players
            ForEach(players) { player in
                VStack(alignment: .leading, spacing: 6) {
                    assetToggleRow(
                        label: player.fullName,
                        sublabel: "\(player.position.rawValue) · \(player.overall) OVR · Age \(player.age)",
                        valueLabel: "\(TradeValueEngine.playerTradeValue(player: player)) pts",
                        isSelected: selectedPlayers.wrappedValue.contains(player.id),
                        accentColor: accentColor,
                        blockedReason: untradeableReason(for: player)
                    ) {
                        toggle(id: player.id, in: selectedPlayers)
                    }

                    // Show "vs Current Starter" card for selected trade targets
                    if isTradeTargets && selectedPlayers.wrappedValue.contains(player.id) {
                        vsCurrentStarterCard(for: player)
                    }
                }
            }

            // Picks
            ForEach(picks) { pick in
                assetToggleRow(
                    label: pickLabel(pick),
                    sublabel: "\(pick.displayDraftYear)",   // #152: class year
                    valueLabel: "\(TradeValueEngine.pickTradeValue(pick: pick, currentSeason: career.currentSeason)) pts",
                    isSelected: selectedPicks.wrappedValue.contains(pick.id),
                    accentColor: accentColor
                ) {
                    toggle(id: pick.id, in: selectedPicks)
                }
            }

            if players.isEmpty && picks.isEmpty {
                Text("No assets")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Thin wrapper over the shared row (`TradeAssetViews`), which the Wave 3
    /// mid-negotiation package editor also draws.
    private func assetToggleRow(
        label: String,
        sublabel: String,
        valueLabel: String,
        isSelected: Bool,
        accentColor: Color,
        blockedReason: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        TradeAssetToggleRow(
            label: label,
            sublabel: sublabel,
            valueLabel: valueLabel,
            isSelected: isSelected,
            accentColor: accentColor,
            blockedReason: blockedReason,
            action: action
        )
    }

    /// Asset-intrinsic league rules that refuse a player at SELECTION time
    /// (#141b), i.e. the subset of `TradeValueEngine.validationErrors` that
    /// depends on nothing but the man himself.
    ///
    /// The tag is the only one today: `validationErrors` refuses a tagged man on
    /// either side of any package, so letting him be checked into "You Send"
    /// only to fail at Propose was a dead end the UI could have named up front.
    /// Injuries and no-trade clauses stay in `hardBlockersRow` on purpose — the
    /// first clears with time and the second depends on which club is calling,
    /// so neither is a property of the row.
    private func untradeableReason(for player: Player) -> String? {
        player.isFranchiseTagged
            ? "Franchise-tagged — can't be traded."
            : nil
    }

    // MARK: Value Meter

    private var valueMeter: some View {
        let values = currentProposalValues
        let sending = values.sendingValue
        let receiving = values.receivingValue
        let total = sending + receiving
        let sendFraction: Double = total > 0 ? Double(sending) / Double(total) : 0.5

        return VStack(spacing: 8) {
            HStack {
                Text("Trade Value")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                if let partner = selectedPartner {
                    partnerVerdictLabel(partner: partner)
                }
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(Color.accentBlue)
                        .frame(width: geo.size.width * sendFraction)
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(Color.accentGold)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            }
            .frame(height: 10)

            HStack {
                Label("You send \(sending) pts", systemImage: "arrow.up.right")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.accentBlue)
                Spacer()
                Label("You get \(receiving) pts", systemImage: "arrow.down.left")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }
        }
    }

    /// 5-step verdict from the partner's need-adjusted perspective — no exact
    /// numbers, just how the other GM feels about the deal.
    private func partnerVerdictLabel(partner: Team) -> some View {
        let verdict = currentPartnerVerdict(partner: partner)
        return Label(verdict.label, systemImage: verdict.icon)
            .font(.caption.weight(.bold))
            .foregroundStyle(verdictColor(verdict))
    }

    private func currentPartnerVerdict(partner: Team) -> TradeValueEngine.PartnerVerdict {
        guard let myTeam = playerTeam else { return .hangUp }
        let proposal = TradeProposal(
            offeringTeamID: myTeam.id,
            receivingTeamID: partner.id,
            sendingPlayers: Array(mySelectedPlayers),
            receivingPlayers: Array(theirSelectedPlayers),
            sendingPicks: Array(mySelectedPicks),
            receivingPicks: Array(theirSelectedPicks)
        )
        return TradeValueEngine.partnerVerdict(
            proposal: proposal,
            aiTeam: partner,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: career.currentSeason,
            contracts: allContracts,
            week: career.currentWeek
        )
    }

    private func verdictColor(_ verdict: TradeValueEngine.PartnerVerdict) -> Color {
        switch verdict {
        case .loveIt:     return .success
        case .likeIt:     return .success
        case .onTheFence: return .warning
        case .wantMore:   return .warning
        case .hangUp:     return .danger
        }
    }

    private func fairnessLabel(sending: Int, receiving: Int) -> some View {
        let ratio: Double = receiving > 0 ? Double(sending) / Double(receiving) : 1.0
        let text: String
        let color: Color
        if ratio >= 0.9 && ratio <= 1.1 {
            text = "Fair"
            color = Color.success
        } else if ratio > 1.1 {
            text = "You Overpay"
            color = Color.warning
        } else {
            text = "You Win"
            color = Color.accentGold
        }
        return Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(color)
    }

    // MARK: Propose Button

    private func proposeButton(partner: Team) -> some View {
        let hasAssets = !mySelectedPlayers.isEmpty || !mySelectedPicks.isEmpty ||
                        !theirSelectedPlayers.isEmpty || !theirSelectedPicks.isEmpty
        // #141b: `hardBlockersRow` above already prints, in red, every reason
        // the league office would refuse this package — but the button under it
        // stayed full-opacity gold, so the screen said "no" and "go" at once.
        // A live blocker now greys the button out; `startNegotiation` keeps its
        // own guard because a blocker can appear between render and tap.
        let isBlocked = !currentBlockers(partner: partner).isEmpty
        let canPropose = hasAssets && !isBlocked

        return Button {
            startNegotiation(partner: partner)
        } label: {
            Label(
                isBlocked ? "Trade Blocked" : "Propose Trade",
                systemImage: isBlocked ? "exclamationmark.triangle.fill" : "bubble.left.and.bubble.right.fill"
            )
                .font(.system(size: DSType.Size.callout, weight: .bold))
                .foregroundStyle(canPropose ? Color.backgroundPrimary : Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canPropose ? Color.accentGold : Color.backgroundTertiary)
                )
        }
        .buttonStyle(.plain)
        .disabled(!canPropose)
    }

    // MARK: - Incoming Offers Section

    private var incomingSectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Incoming Offers", icon: "tray.fill")

            if incomingOffers.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.textTertiary)
                        Text("No incoming offers")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        // F-69: the old line said offers arrive "weekly during
                        // the regular season", full stop, and the league market
                        // has run in five OFFSEASON windows since Wave 2
                        // (`MarketWindow.offseason`, driven from
                        // `WeekAdvancer.runLeagueMarketWindow`). A user who read
                        // this and then put the phone down at the deadline was
                        // told the wrong thing by his own screen.
                        Text("AI offers arrive weekly during the regular season — contenders buy, rebuilders sell — through the Week \(TradeValueEngine.deadlineWeek) deadline. The phone rings in the offseason too: the league trades again after the season, around free agency, before and after the draft, and on cut days.")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                ForEach(incomingOffers) { offer in
                    incomingOfferCard(offer)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardBackground()
    }

    private func incomingOfferCard(_ offer: TradeProposal) -> some View {
        let aiTeamName = allTeams.first(where: { $0.id == offer.offeringTeamID })?.abbreviation ?? "AI"
        let values = TradeValueEngine.proposalValues(
            proposal: offer,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: career.currentSeason
        )
        // From user's perspective: "receiving" side is what AI sends (proposal.sendingPlayers/Picks)
        let youReceive = values.sendingValue
        let youSend    = values.receivingValue

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(aiTeamName) Offer")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                fairnessLabel(sending: youSend, receiving: youReceive)
            }

            HStack(alignment: .top, spacing: 16) {
                offerAssetColumn(
                    title: "You Send",
                    playerIDs: offer.receivingPlayers,
                    pickIDs: offer.receivingPicks,
                    valueLabel: "\(youSend) pts",
                    accentColor: Color.danger
                )
                Divider().overlay(Color.surfaceBorder).frame(maxHeight: 200)
                offerAssetColumn(
                    title: "You Receive",
                    playerIDs: offer.sendingPlayers,
                    pickIDs: offer.sendingPicks,
                    valueLabel: "\(youReceive) pts",
                    accentColor: Color.success
                )
            }

            HStack(spacing: 12) {
                Button {
                    acceptOffer(offer)
                } label: {
                    Label("Accept", systemImage: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.success))
                }
                .buttonStyle(.plain)

                Button {
                    negotiateOffer(offer)
                } label: {
                    Label("Negotiate", systemImage: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.accentGold, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    declineOffer(offer)
                } label: {
                    Label("Decline", systemImage: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.danger)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.danger, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundTertiary)
        )
    }

    /// One side of an incoming offer. The layout moved to `TradeAssetViews` in
    /// Wave 3 so a package quoted inside a negotiation transcript reads exactly
    /// like the same package quoted here.
    private func offerAssetColumn(
        title: String,
        playerIDs: [UUID],
        pickIDs: [UUID],
        valueLabel: String,
        accentColor: Color
    ) -> some View {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        return TradeAssetColumn(
            title: title,
            players: playerIDs.compactMap { playerLookup[$0] },
            picks: pickIDs.compactMap { pickLookup[$0] },
            valueLabel: valueLabel,
            accentColor: accentColor
        )
    }

    // MARK: - Value Breakdown

    @ViewBuilder
    private func valueBreakdownSection(partner: Team) -> some View {
        let lines = currentProposalBreakdown(partner: partner)
        let hasAny = !lines.yourLines.isEmpty || !lines.theirLines.isEmpty
        if hasAny {
            DisclosureGroup(isExpanded: $showValueBreakdown) {
                VStack(alignment: .leading, spacing: 10) {
                    breakdownColumn(
                        title: "You Send",
                        items: lines.yourLines,
                        accentColor: Color.accentBlue
                    )
                    breakdownColumn(
                        title: "You Receive",
                        items: lines.theirLines,
                        accentColor: Color.accentGold
                    )
                    Divider().overlay(Color.surfaceBorder)
                    HStack {
                        Text("Net to you")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        let net = lines.theirTotal - lines.yourTotal
                        Text(net >= 0 ? "+\(net)" : "−\(abs(net))")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(net >= 0 ? Color.success : Color.danger)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Text("Value Breakdown")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
            }
            .tint(Color.textSecondary)
        }
    }

    private func breakdownColumn(
        title: String,
        items: [BreakdownLine],
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.system(size: 11).weight(.bold))
                    .foregroundStyle(accentColor)
                Spacer()
                Text("Total \(items.reduce(0) { $0 + $1.value })")
                    .font(.system(size: 11).weight(.bold).monospacedDigit())
                    .foregroundStyle(accentColor)
            }
            if items.isEmpty {
                Text("Nothing selected")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            } else {
                ForEach(items) { line in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line.label)
                                .font(.system(size: 11).weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text(line.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                        Text("\(line.value)")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundSecondary)
        )
    }

    // MARK: - AI Willingness

    @ViewBuilder
    private func aiWillingnessRow(partner: Team) -> some View {
        let hasAssets = !mySelectedPlayers.isEmpty || !mySelectedPicks.isEmpty ||
                        !theirSelectedPlayers.isEmpty || !theirSelectedPicks.isEmpty

        let willingness = aiWillingnessForCurrentProposal(partner: partner)

        HStack(spacing: 10) {
            Image(systemName: willingness.icon)
                .foregroundStyle(willingness.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(partner.abbreviation) Front Office")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text(hasAssets ? willingness.label : "Select assets to gauge interest")
                    .font(.system(size: DSType.Size.body).weight(.bold))
                    .foregroundStyle(hasAssets ? willingness.color : Color.textTertiary)
                if hasAssets, let ask = askingPriceHint(partner: partner) {
                    Text(ask)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                dossierLine(partner: partner)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(willingness.color.opacity(hasAssets ? 0.10 : 0.0))
        )
    }

    /// D7-A / D1, made visible.
    ///
    /// Two facts the user could not previously discover, and both of them price
    /// his trades:
    ///
    /// * **How well his organisation reads this GM.** The fog is symmetric — the
    ///   club on the other end has the same kind of file on him — so showing him
    ///   his own side of it is what stops the model from being a private
    ///   advantage handed to the AI. It also gives "trade with the same club
    ///   twice" a legible payoff.
    /// * **What the league has decided about HIM.** D1's ruling is that refusal
    ///   must bite and be visibly priced rather than capped by a rule. A
    ///   surcharge nobody can see is just a number that makes the game feel
    ///   arbitrary; this is the sentence that turns it into a consequence he can
    ///   trace back to the lowballs he sent in September.
    ///
    /// It stays out of the hidden half: no chart lean, no accept bar, no asking
    /// noise. Confidence and reputation are things a front office genuinely
    /// knows about itself.
    @ViewBuilder
    private func dossierLine(partner: Team) -> some View {
        let identity = TradeValueEngine.gmIdentity(
            team: partner, season: career.currentSeason, userTeamID: career.teamID
        )
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: DSType.Size.micro))
                Text(identity.dossierContacts > 0
                     ? "\(identity.dossierLabel) — \(identity.dossierContacts) deal\(identity.dossierContacts == 1 ? "" : "s") on file"
                     : identity.dossierLabel)
                    .font(.system(size: DSType.Size.micro))
            }
            .foregroundStyle(Color.textTertiary)

            if let read = identity.leagueRead {
                HStack(spacing: DSSpacing.xxs) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: DSType.Size.micro))
                    Text("Around the league: \(read)")
                        .font(.system(size: DSType.Size.micro))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.top, DSSpacing.xxs)
    }

    /// What the other GM is asking for, in words instead of point totals.
    ///
    /// Derived from the same 5-step verdict the response uses, so it can never
    /// contradict the outcome. Wave 3 named the man and quoted his OPENING
    /// posture (`GMIdentity.askingPremiumPercent`) — the handoff the Wave 2
    /// comment here asked for. The hidden half stays hidden: the accept bar, the
    /// weekly asking noise and the chart lean are still nowhere on screen.
    private func askingPriceHint(partner: Team) -> String? {
        let identity = TradeValueEngine.gmIdentity(
            team: partner, season: career.currentSeason, userTeamID: career.teamID
        )
        let opener = "\(identity.name) (\(identity.archetypeLabel)) opens about \(identity.askingPremiumPercent)% over what he sends."

        guard identity.talksOpen else {
            return "\(identity.name) has stopped taking your calls this league year."
        }

        switch currentPartnerVerdict(partner: partner) {
        case .loveIt:
            return "\(opener) He would sign this today."
        case .likeIt:
            return "\(opener) His ask is met — expect a yes."
        case .onTheFence:
            return "\(opener) Close: a late-round pick or a rotational player gets it over the line."
        case .wantMore:
            return "\(opener) He wants a real piece added — a starter or early-round capital."
        case .hangUp:
            // #151: a hang-up has two directions and they need opposite words.
            // The usual one is a lowball — his ask really is above the table. The
            // other is an overpay so lopsided that the package decay and the
            // roster-spot charge eat it: sixteen bodies for one man reads as an
            // insult from the AI's chair while the user is watching himself push
            // thirty times the chart value across the desk. Telling him his offer
            // is too SMALL at that moment is simply a lie, so the branch is
            // chosen by the sign of the gap the screen is already showing.
            return "\(opener) \(hangUpDetail(partner: partner))"
        }
    }

    /// The second half of a hang-up line, chosen by which way the value gap runs.
    private func hangUpDetail(partner: Team) -> String {
        guard let myTeam = playerTeam else {
            return "Not a conversation yet: his ask is far above what is on the table."
        }
        let proposal = TradeProposal(
            offeringTeamID: myTeam.id,
            receivingTeamID: partner.id,
            sendingPlayers: Array(mySelectedPlayers),
            receivingPlayers: Array(theirSelectedPlayers),
            sendingPicks: Array(mySelectedPicks),
            receivingPicks: Array(theirSelectedPicks)
        )
        // F-07 has a third reason to hang up and it is not about this GM at all:
        // the league office's own chart band. Preview ≡ outcome means the hint
        // has to say so in the same words `respond` will, or the user reads
        // "his ask is above the table" and then gets refused for a rule.
        if let unfair = TradeValueEngine.chartFairnessBlocker(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: career.currentSeason,
            betweenAIClubs: false
        ) {
            return unfair
        }
        let raw = TradeValueEngine.proposalValues(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: career.currentSeason
        )
        guard TradeValueEngine.isSuspiciousOverpay(proposal: proposal, raw: raw) else {
            return "Not a conversation yet: his ask is far above what is on the table."
        }
        if mySelectedPlayers.count - theirSelectedPlayers.count >= 3 {
            return "Not a conversation: that is far more than he asked for, and he has nowhere to put that many bodies."
        }
        return "Not a conversation: that is far more than he asked for, and a package that lopsided makes him wonder what he is missing."
    }

    /// Willingness preview derived from the same 5-step verdict the AI uses
    /// to respond, so the preview always matches the actual outcome:
    /// love/like → accepts, on the fence → counters, want more/hang up → rejects.
    private func aiWillingnessForCurrentProposal(partner: Team) -> (label: String, icon: String, color: Color) {
        switch currentPartnerVerdict(partner: partner) {
        case .loveIt, .likeIt:
            return ("Would accept", "checkmark.circle.fill", Color.success)
        case .onTheFence:
            return ("Will counter", "arrow.left.arrow.right.circle.fill", Color.warning)
        case .wantMore, .hangUp:
            return ("Rejects", "xmark.circle.fill", Color.danger)
        }
    }

    // MARK: - Hard Blockers

    /// League rules that will refuse this package — no-trade clauses, injured
    /// players, roster bounds, the cap — shown live instead of only in the
    /// alert after tapping Propose, so the preview equals the outcome
    /// (`docs/TRADE_OVERHAUL_PLAN.md` G7).
    @ViewBuilder
    private func hardBlockersRow(partner: Team) -> some View {
        let blockers = currentBlockers(partner: partner)
        if !blockers.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(blockers, id: \.self) { blocker in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.danger)
                        Text(blocker)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.danger.opacity(0.10))
            )
        }
    }

    private func currentBlockers(partner: Team) -> [String] {
        guard let myTeam = playerTeam else { return [] }
        let hasAssets = !mySelectedPlayers.isEmpty || !mySelectedPicks.isEmpty ||
                        !theirSelectedPlayers.isEmpty || !theirSelectedPicks.isEmpty
        guard hasAssets else { return [] }

        return validationErrors(for: TradeProposal(
            offeringTeamID: myTeam.id,
            receivingTeamID: partner.id,
            sendingPlayers: Array(mySelectedPlayers),
            receivingPlayers: Array(theirSelectedPlayers),
            sendingPicks: Array(mySelectedPicks),
            receivingPicks: Array(theirSelectedPicks)
        ))
    }

    // MARK: - Cap Impact

    @ViewBuilder
    private func capImpactSection(partner: Team) -> some View {
        if let myTeam = playerTeam {
            let impact = computeCapImpact(myTeam: myTeam, partner: partner)
            let hasAny = impact.yourDelta != 0 || impact.theirDelta != 0
                || impact.yourDeadCap != 0 || impact.theirDeadCap != 0

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(Color.accentGold)
                    Text("Cap Impact")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    capImpactColumn(
                        teamLabel: myTeam.abbreviation,
                        beforeRoom: myTeam.salaryCap - myTeam.currentCapUsage,
                        afterRoom: (myTeam.salaryCap - myTeam.currentCapUsage) - impact.yourDelta,
                        delta: -impact.yourDelta,
                        deadCap: impact.yourDeadCap
                    )
                    Divider().overlay(Color.surfaceBorder).frame(maxHeight: 70)
                    capImpactColumn(
                        teamLabel: partner.abbreviation,
                        beforeRoom: partner.salaryCap - partner.currentCapUsage,
                        afterRoom: (partner.salaryCap - partner.currentCapUsage) - impact.theirDelta,
                        delta: -impact.theirDelta,
                        deadCap: impact.theirDeadCap
                    )
                }

                // Wave 1 cap truth: trades are no longer free salary dumps. The
                // signing-bonus proration accelerates onto whoever paid it, so
                // the money you keep for a player you just traded needs to be
                // on screen BEFORE you tap Propose.
                if impact.yourDeadCap > 0 || impact.theirDeadCap > 0 {
                    Text("Dead money stays with the team trading the player away — his bonus proration can't follow him.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !hasAny {
                    Text("No salary changes hands.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    private func capImpactColumn(
        teamLabel: String,
        beforeRoom: Int,
        afterRoom: Int,
        delta: Int,
        deadCap: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(teamLabel)
                .font(.system(size: 11).weight(.bold))
                .foregroundStyle(Color.textPrimary)
            HStack {
                Text("Before:")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(formatMillions(beforeRoom))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            HStack {
                Text("After:")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text(formatMillions(afterRoom))
                    .font(.system(size: 11).weight(.semibold).monospacedDigit())
                    .foregroundStyle(afterRoom < 0 ? Color.danger : Color.textPrimary)
            }
            HStack {
                Text("Δ")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                let prefix: String = delta == 0 ? "" : (delta > 0 ? "+" : "−")
                Text("\(prefix)\(formatMillions(abs(delta)))")
                    .font(.system(size: 11).weight(.bold).monospacedDigit())
                    .foregroundStyle(delta > 0 ? Color.success : (delta < 0 ? Color.warning : Color.textTertiary))
            }
            if deadCap > 0 {
                HStack {
                    Text("Dead:")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text(formatMillions(deadCap))
                        .font(.system(size: 11).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.danger)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Cap consequences of the current builder selection, using the exact split
    /// `TradeEngine.executeTrade` will apply: the team trading a player away
    /// keeps his accelerated signing bonus as dead money, the other team is
    /// charged base salary only.
    private func computeCapImpact(
        myTeam: Team,
        partner: Team
    ) -> (yourDelta: Int, theirDelta: Int, yourDeadCap: Int, theirDeadCap: Int) {
        // yourDelta = net cap added to your team (positive = more salary on books)
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let outgoing = mySelectedPlayers.compactMap { playerLookup[$0] }
        let incoming = theirSelectedPlayers.compactMap { playerLookup[$0] }

        let remaining = CapManagementEngine.leagueYearRemaining(
            phase: career.currentPhase, week: career.currentWeek
        )
        let mine = TradeValueEngine.capDeltas(
            for: outgoing, contracts: allContracts, capMode: career.capMode,
            leagueYearRemaining: remaining
        )
        let theirs = TradeValueEngine.capDeltas(
            for: incoming, contracts: allContracts, capMode: career.capMode,
            leagueYearRemaining: remaining
        )

        let yourDelta  = theirs.assumed - mine.oldHit + mine.deadCap
        let theirDelta = mine.assumed - theirs.oldHit + theirs.deadCap
        return (yourDelta, theirDelta, mine.deadCap, theirs.deadCap)
    }

    // MARK: - Picks-Only Wizard

    private var pickWizardCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Pick Trade Simulator", icon: "wand.and.stars")

            Text("Choose one of your picks and a partner team — see Trade Up / Trade Down packages from their available picks.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)

            wizardPickPicker
            wizardPartnerPicker

            if let myPick = wizardSelectedPick, let partner = wizardSelectedPartner {
                Divider().overlay(Color.surfaceBorder)
                wizardSuggestions(myPick: myPick, partner: partner)
            } else {
                HStack {
                    Spacer()
                    Text("Pick a draft pick and a partner team.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardBackground()
    }

    private var wizardPickPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your Pick")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            if myPicks.isEmpty {
                Text("You have no draft picks.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(myPicks) { pick in
                            wizardPickChip(pick: pick, isSelected: wizardPickID == pick.id) {
                                wizardPickID = (wizardPickID == pick.id) ? nil : pick.id
                            }
                        }
                    }
                }
            }
        }
    }

    /// What the trade WIZARD is allowed to call a pick worth.
    ///
    /// ## QA 2026-08-22: the wizard was quoting a different currency
    ///
    /// Every number in the wizard came from `PickValueChart.points(forPick:)` —
    /// the raw Jimmy Johnson chart — while the engine that actually accepts or
    /// rejects the deal prices through `TradeValueEngine.pickTradeValue`, which
    /// compounds `futurePickDiscountPerYear` (0.6) per year out. So the asset
    /// board listed a 2028, 2029, 2030 and 2031 first at **1 000 pts each**,
    /// identical, when the engine valued them 600 / 360 / 216 / 130.
    ///
    /// Both sides of the wizard's ratio used the raw chart, so a same-year swap
    /// looked right by accident. The moment the two sides are different years —
    /// which is the entire point of a trade-up or trade-down wizard — it
    /// recommended deals the engine considers robbery, and printed a
    /// reassuring "100 %" over them.
    ///
    /// One function, so the suggestion engine, the chips and the ratio cannot
    /// drift apart again.
    private func wizardPickPoints(_ pick: DraftPick) -> Int {
        TradeValueEngine.pickTradeValue(pick: pick, currentSeason: career.currentSeason)
    }

    private func wizardPickChip(pick: DraftPick, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(pickLabelShort(pick))
                    .font(.system(size: 11).weight(.bold))
                Text("\(wizardPickPoints(pick)) pts")
                    .font(.system(size: DSType.Size.caption))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentGold : Color.backgroundTertiary)
            )
        }
        .buttonStyle(.plain)
    }

    private var wizardPartnerPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Partner Team")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(otherTeams) { team in
                        Button {
                            wizardPartnerID = (wizardPartnerID == team.id) ? nil : team.id
                        } label: {
                            Text(team.abbreviation)
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .foregroundStyle(
                                    wizardPartnerID == team.id
                                        ? Color.backgroundPrimary
                                        : Color.textSecondary
                                )
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(wizardPartnerID == team.id ? Color.accentBlue : Color.backgroundTertiary)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wizardSuggestions(myPick: DraftPick, partner: Team) -> some View {
        let myValue = wizardPickPoints(myPick)
        let partnerPicks = theirPicks(partner: partner)

        let upSuggestions = tradeUpSuggestions(myPickValue: myValue, partnerPicks: partnerPicks)
        let downSuggestions = tradeDownSuggestions(myPickValue: myValue, partnerPicks: partnerPicks)

        VStack(alignment: .leading, spacing: 14) {
            // Trade Up
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .foregroundStyle(Color.success)
                    Text("Trade Up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.success)
                    Spacer()
                    Text("Get a better pick")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
                if upSuggestions.isEmpty {
                    Text("No realistic trade-up packages available.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    ForEach(Array(upSuggestions.enumerated()), id: \.offset) { _, sug in
                        wizardSuggestionRow(suggestion: sug, myValue: myValue, accent: Color.success)
                    }
                }
            }

            // Trade Down
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.circle.fill")
                        .foregroundStyle(Color.accentBlue)
                    Text("Trade Down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentBlue)
                    Spacer()
                    Text("Acquire extra picks")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
                if downSuggestions.isEmpty {
                    Text("No realistic trade-down packages available.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                } else {
                    ForEach(Array(downSuggestions.enumerated()), id: \.offset) { _, sug in
                        wizardSuggestionRow(suggestion: sug, myValue: myValue, accent: Color.accentBlue)
                    }
                }
            }
        }
    }

    private func wizardSuggestionRow(suggestion: WizardSuggestion, myValue: Int, accent: Color) -> some View {
        let totalValue = suggestion.picks.reduce(0) { $0 + wizardPickPoints($1) }
        let ratio: Double = myValue > 0 ? Double(totalValue) / Double(myValue) : 0
        let label = String(format: "%.0f%%", ratio * 100.0)

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(suggestion.picks) { p in
                    Text(pickLabelShort(p) + "  \(wizardPickPoints(p)) pts")
                        .font(.system(size: 11).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(totalValue) pts")
                    .font(.system(size: 11).weight(.bold).monospacedDigit())
                    .foregroundStyle(accent)
                Text(label)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundTertiary)
        )
    }

    private func tradeUpSuggestions(myPickValue: Int, partnerPicks: [DraftPick]) -> [WizardSuggestion] {
        var results: [WizardSuggestion] = []
        let betterPicks = partnerPicks
            .filter { wizardPickPoints($0) > Int(Double(myPickValue) * 1.05) }
            .sorted { wizardPickPoints($0) < wizardPickPoints($1) }
            .prefix(3)
        for pick in betterPicks {
            results.append(WizardSuggestion(picks: [pick]))
        }
        return results
    }

    private func tradeDownSuggestions(myPickValue: Int, partnerPicks: [DraftPick]) -> [WizardSuggestion] {
        let lesser = partnerPicks
            .filter { wizardPickPoints($0) < myPickValue }
            .sorted { wizardPickPoints($0) > wizardPickPoints($1) }

        guard !lesser.isEmpty else { return [] }

        var results: [WizardSuggestion] = []
        let lower = Int(Double(myPickValue) * 0.85)
        let upper = Int(Double(myPickValue) * 1.15)

        for i in 0..<lesser.count {
            let v1 = wizardPickPoints(lesser[i])
            if v1 >= lower && v1 <= upper {
                results.append(WizardSuggestion(picks: [lesser[i]]))
                if results.count >= 3 { return results }
            }
            for j in (i + 1)..<lesser.count {
                let v2 = v1 + wizardPickPoints(lesser[j])
                if v2 >= lower && v2 <= upper {
                    results.append(WizardSuggestion(picks: [lesser[i], lesser[j]]))
                    if results.count >= 3 { return results }
                }
                if lesser.count > j + 1 {
                    for k in (j + 1)..<lesser.count {
                        let v3 = v2 + wizardPickPoints(lesser[k])
                        if v3 >= lower && v3 <= upper {
                            results.append(WizardSuggestion(picks: [lesser[i], lesser[j], lesser[k]]))
                            if results.count >= 3 { return results }
                        }
                    }
                }
            }
        }
        return Array(results.prefix(3))
    }

    private var wizardSelectedPick: DraftPick? {
        guard let id = wizardPickID else { return nil }
        return myPicks.first { $0.id == id }
    }

    private var wizardSelectedPartner: Team? {
        guard let id = wizardPartnerID else { return nil }
        return allTeams.first { $0.id == id }
    }

    // MARK: - Trade History

    private var tradeHistoryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(title: "Trade History (\(career.currentSeason))", icon: "clock.arrow.circlepath")

            // F-51: this card is THIS season and THIS club, which is the right
            // scope for "what have I done lately" and the wrong one for "what
            // did the other 31 do". The wire is the other question, and it reads
            // the same ledger.
            shelfLink(
                destination: .transactions,
                icon: "list.bullet.rectangle",
                title: "League transaction wire",
                caption: "every deal, every club, every season"
            )

            // F-58: the standing version of "who wants my backup tight end?".
            // The builder above is partner-first and cannot answer it.
            shelfLink(
                destination: .tradeBlock,
                icon: "tray.full",
                title: "Trade block",
                caption: TradeBlockStore.shared.count == 0
                    ? "nobody listed"
                    : "\(TradeBlockStore.shared.count) listed"
            )

            if tradeHistory.isEmpty {
                HStack {
                    Spacer()
                    Text("No trades completed yet this season.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .padding(.vertical, 12)
            } else {
                ForEach(tradeHistory) { entry in
                    tradeHistoryRow(entry)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardBackground()
    }

    /// A row that leaves this screen for a related one. Two of them sit above
    /// the season's history: the league-wide wire (F-51) and the block (F-58).
    private func shelfLink(
        destination: CareerShellView.ShellDestination,
        icon: String,
        title: String,
        caption: String
    ) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                Text(title)
                    .font(DSType.text(DSType.Size.body, .semibold))
                Spacer()
                Text(caption)
                    .font(DSType.text(DSType.Size.caption, .medium, prose: true))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: DSType.Size.caption, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
            }
            .foregroundStyle(Color.accentBlue)
            .padding(.horizontal, DSSpacing.sm)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(Color.backgroundTertiary)
            )
        }
        .buttonStyle(.plain)
    }

    private func tradeHistoryRow(_ entry: CompletedTrade) -> some View {
        HStack(spacing: 10) {
            Text(entry.grade)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(historyGradeColor(entry.grade))
                .frame(width: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text("with \(entry.counterpartyAbbr)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(entry.headline)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("Sent \(entry.sentValue) pts")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.accentBlue)
                Text("Got \(entry.receivedValue) pts")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundTertiary)
        )
    }

    /// The trade ledger's letters read the ONE ladder. Its own switch painted B
    /// gold and folded `A+` in with `A`, so the best trade this screen can grade
    /// looked no different from a merely good one and a `D` looked like an `F`.
    private func historyGradeColor(_ grade: String) -> Color {
        Color.forGrade(grade)
    }

    /// Loads this season's completed trades from the LEDGER (F-50).
    ///
    /// The card was titled "Trade History (2029)" and backed by view-instance
    /// `@State` populated only during this instance's lifetime: close the Trade
    /// Center, reopen it, and a season of trading read "No trades completed yet
    /// this season" — while the real archive sat unread three files away.
    /// `TradeRecord` has been written at every execution site since Wave 0 and
    /// its only reader in the whole binary was the DEBUG-only smoke test, which
    /// also left `TradeRecordKind.label` ("Your proposal" / "Incoming offer" /
    /// "League deal") as dead copy.
    ///
    /// The rows carry everything `CompletedTrade` holds, from the user's chair:
    /// he is the row's INITIATOR when he built the deal and the PARTNER when a
    /// club called him, and the sent/received summaries flip with him.
    private func loadTradeHistory() {
        let cid = career.id
        let season = career.currentSeason
        let userTeamID = career.teamID
        let descriptor = FetchDescriptor<TradeRecord>(
            predicate: #Predicate { $0.careerID == cid && $0.season == season },
            sortBy: [SortDescriptor(\TradeRecord.week, order: .reverse)]
        )
        let rows = (try? modelContext.fetch(descriptor)) ?? []
        let abbrByID = Dictionary(uniqueKeysWithValues: allTeams.map { ($0.id, $0.abbreviation) })

        tradeHistory = rows.compactMap { row -> CompletedTrade? in
            guard let userTeamID else { return nil }
            let userInitiated = row.initiatorTeamID == userTeamID
            let userInvolved = userInitiated || row.partnerTeamID == userTeamID
            guard userInvolved else { return nil }

            let counterpartyID = userInitiated ? row.partnerTeamID : row.initiatorTeamID
            let sent = userInitiated ? row.sentValue : row.receivedValue
            let received = userInitiated ? row.receivedValue : row.sentValue
            let sentText = userInitiated ? row.sentSummary : row.receivedSummary
            let gotText = userInitiated ? row.receivedSummary : row.sentSummary

            return CompletedTrade(
                counterpartyAbbr: abbrByID[counterpartyID] ?? "???",
                sentValue: sent,
                receivedValue: received,
                grade: gradeForTrade(sent: sent, received: received),
                headline: "\(row.kind.label) · Sent: \(sentText.isEmpty ? "—" : sentText)  |  Got: \(gotText.isEmpty ? "—" : gotText)"
            )
        }
    }

    private func recordCompletedTrade(
        proposal: TradeProposal,
        counterpartyAbbr: String,
        userIsOfferingTeam: Bool
    ) {
        let values = TradeValueEngine.proposalValues(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: career.currentSeason
        )
        // From user's perspective:
        //  if user is the offering team:    user sends sendingValue,   gets receivingValue
        //  if offer came FROM AI to user:   user sends receivingValue, gets sendingValue
        let userSent     = userIsOfferingTeam ? values.sendingValue   : values.receivingValue
        let userReceived = userIsOfferingTeam ? values.receivingValue : values.sendingValue

        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        let outgoingPlayerIDs = userIsOfferingTeam ? proposal.sendingPlayers   : proposal.receivingPlayers
        let outgoingPickIDs   = userIsOfferingTeam ? proposal.sendingPicks     : proposal.receivingPicks
        let incomingPlayerIDs = userIsOfferingTeam ? proposal.receivingPlayers : proposal.sendingPlayers
        let incomingPickIDs   = userIsOfferingTeam ? proposal.receivingPicks   : proposal.sendingPicks

        let outNames = outgoingPlayerIDs.compactMap { playerLookup[$0]?.fullName } +
                       outgoingPickIDs.compactMap { pickLookup[$0].map { pickLabelShort($0) } }
        let inNames  = incomingPlayerIDs.compactMap { playerLookup[$0]?.fullName } +
                       incomingPickIDs.compactMap { pickLookup[$0].map { pickLabelShort($0) } }

        let headline = "Sent: \(outNames.isEmpty ? "—" : outNames.joined(separator: ", "))  |  Got: \(inNames.isEmpty ? "—" : inNames.joined(separator: ", "))"

        let entry = CompletedTrade(
            counterpartyAbbr: counterpartyAbbr,
            sentValue: userSent,
            receivedValue: userReceived,
            grade: gradeForTrade(sent: userSent, received: userReceived),
            headline: headline
        )
        // Optimistic insert so the card updates before the fetch: `loadData()`
        // re-reads the ledger a moment later (F-50) and the row is replaced by
        // its persisted twin.
        tradeHistory.insert(entry, at: 0)
    }

    private func gradeForTrade(sent: Int, received: Int) -> String {
        guard sent > 0 else { return received > 0 ? "A+" : "C" }
        let ratio = Double(received) / Double(sent)
        if ratio >= 1.20 { return "A+" }
        if ratio >= 1.05 { return "A" }
        if ratio >= 0.90 { return "B" }
        if ratio >= 0.75 { return "C" }
        return "D"
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentGold)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Actions

    /// Wave 3: Propose no longer fires a one-shot alert — it picks up the phone.
    ///
    /// The old flow evaluated once, printed the verdict in an alert and, on a
    /// counter, silently overwrote the builder with the AI's package. Nothing
    /// remembered that a conversation had happened (plan finding S7), so
    /// "negotiating" was really just re-proposing from scratch every time. The
    /// package the user built is now round one of a persisted thread, and every
    /// AI turn inside it is the same `TradeValueEngine.respond` this used to
    /// call — the brain is unchanged, the memory is new.
    private func startNegotiation(partner: Team) {
        guard let myTeam = playerTeam else { return }

        let proposal = TradeProposal(
            offeringTeamID: myTeam.id,
            receivingTeamID: partner.id,
            sendingPlayers: Array(mySelectedPlayers),
            receivingPlayers: Array(theirSelectedPlayers),
            sendingPicks: Array(mySelectedPicks),
            receivingPicks: Array(theirSelectedPicks)
        )

        // Hard validation still fires here, so a package the league office would
        // refuse never becomes a phone call.
        let blockers = validationErrors(for: proposal)
        if !blockers.isEmpty {
            tradeResultMessage = "Trade blocked:\n" + blockers.joined(separator: "\n")
            resultIsSuccess = false
            showResultAlert = true
            return
        }

        // One conversation per GM. If talks with this club are already open, the
        // builder's package doesn't start a second thread — it re-enters the
        // existing one, where the package editor is a rework away.
        if let existing = threads.first(where: { $0.partnerTeamID == partner.id && $0.status == .open }) {
            activeNegotiation = NegotiationRoute(
                partnerTeamID: partner.id,
                threadID: existing.id
            )
            return
        }

        activeNegotiation = NegotiationRoute(
            partnerTeamID: partner.id,
            seed: proposal
        )
    }

    /// Cleanup after the negotiation cover closes: refresh the thread shelf
    /// (rounds happened in there) and execute any package the conversation
    /// agreed to.
    private func negotiationDismissed() {
        loadThreads()
        executeAgreedDeal()
    }

    /// Executes the package a negotiation agreed to, once its cover has
    /// finished dismissing (so the receipt alert lands on the Trade Center).
    ///
    /// Deliberately routed through the same `executeUserTrade` the incoming-offer
    /// Accept button uses: one execution path means one ledger row, one news
    /// item and one inbox receipt, however the deal was struck.
    private func executeAgreedDeal() {
        guard let agreed = pendingAgreedDeal else { return }
        pendingAgreedDeal = nil

        // A negotiated proposal always has the user's team on the offering side,
        // so the asset directions are fixed; only the LEDGER kind depends on who
        // picked up the phone first.
        guard let counterparty = allTeams.first(where: { $0.id == agreed.proposal.receivingTeamID }) else { return }

        let blockers = validationErrors(for: agreed.proposal)
        if !blockers.isEmpty {
            tradeResultMessage = "Trade blocked:\n" + blockers.joined(separator: "\n")
            resultIsSuccess = false
            showResultAlert = true
            return
        }

        executeUserTrade(
            agreed.proposal,
            counterparty: counterparty,
            userIsOfferingTeam: true,
            ledgerKind: agreed.startedByAI ? .aiWeeklyOffer : .userProposal
        )
        tradeResultMessage = "\(counterparty.abbreviation) signed off — trade complete!"
        resultIsSuccess = true
        showResultAlert = true
    }

    /// Roster/cap/clause blockers for THIS market window.
    ///
    /// Task #25: every user-facing call used to take `validationErrors`' in-season
    /// defaults (ceiling 75, floor 40) all year round. In the offseason those are
    /// not rules — a club legitimately carries 80-90 players between the draft
    /// and cutdown day and empties into the low 30s before free agency — so the
    /// Trade Center vetoed deals the AI-vs-AI market next door executed happily.
    private func validationErrors(for proposal: TradeProposal) -> [String] {
        let bounds = TradeWindowRules.rosterBounds(
            phase: career.currentPhase, week: career.currentWeek
        )
        return TradeValueEngine.validationErrors(
            proposal: proposal,
            allPlayers: allPlayers,
            teams: allTeams,
            capMode: career.capMode,
            contracts: allContracts,
            leagueYearRemaining: CapManagementEngine.leagueYearRemaining(
                phase: career.currentPhase, week: career.currentWeek
            ),
            rosterCeiling: bounds.ceiling,
            rosterFloor: bounds.floor
        )
    }

    /// Routes a message to the shell's inbox, or stages it on the
    /// `WeekAdvancer` channel when this screen is presented outside the shell.
    private func deliver(_ message: InboxMessage) {
        if let onInboxMessage {
            onInboxMessage(message)
        } else {
            WeekAdvancer.lastInboxMessages.append(message)
        }
    }

    /// Executes an agreed trade, persists it, and drops any pending offers
    /// that the roster/pick moves invalidated.
    private func executeUserTrade(
        _ proposal: TradeProposal,
        counterparty: Team,
        userIsOfferingTeam: Bool,
        /// Overrides the kind derived from `userIsOfferingTeam`. A Wave 3
        /// negotiation always puts the user on the offering side of the
        /// proposal, so the direction flag can no longer answer "who called
        /// first?" on its own.
        ledgerKind: TradeRecordKind? = nil
    ) {
        // Capture history before mutating rosters so lookups still resolve.
        recordCompletedTrade(
            proposal: proposal,
            counterpartyAbbr: counterparty.abbreviation,
            userIsOfferingTeam: userIsOfferingTeam
        )
        // F-57: the depth chart BEFORE the deal, so the receipt can name what
        // the deal stripped. It has to be measured here, before `executeTrade`
        // moves anybody.
        let needsBefore = TradeValueEngine.needProfile(
            roster: allPlayers.filter { $0.teamID == career.teamID && !$0.isRetired }
        )
        // Wave 0 ledger: `.userProposal` when the user built the deal, and
        // `.aiWeeklyOffer` when the user accepted an AI-initiated offer — the
        // two are counted separately so "does the phone ever ring?" (finding
        // S5) can be measured. `TradeEngine.executeTrade` writes the row.
        let capOutcome = TradeEngine.executeTrade(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks,
            capMode: career.capMode,
            ledger: TradeLedger.Context(
                kind: ledgerKind ?? (userIsOfferingTeam ? .userProposal : .aiWeeklyOffer),
                season: career.currentSeason,
                week: career.currentWeek,
                phase: career.currentPhase
            ),
            modelContext: modelContext
        )
        // Any stored offers touching the moved assets are now void.
        career.pendingTradeOffers = career.pendingTradeOffers.filter {
            $0.id != proposal.id &&
            TradeValueEngine.isProposalStillValid($0, allPlayers: allPlayers, allPicks: allPicks)
        }
        try? modelContext.save()

        let holesOpened = rosterHolesOpened(before: needsBefore)

        // Wave 2: the league hears about it. `TradeNewsFactory` reads the ledger
        // row `executeTrade` just wrote, so a deal the user made and a deal two
        // AI teams made read identically in the feed. The factory's inbox
        // variant is dropped here on purpose — the receipt below is the same
        // message plus the dead-money line, which only this call site knows.
        announceExecutedTrade(record: capOutcome.record)

        // Surface the completed deal in the inbox, dead money included — the
        // user needs to see the bill for the players he just shipped out — and
        // now the depth holes it opened (F-57).
        let receipt = completedTradeInboxMessage(
            proposal: proposal,
            counterparty: counterparty,
            userIsOfferingTeam: userIsOfferingTeam,
            deadCapLine: capOutcome.deadCapLine(userIsOfferingTeam: userIsOfferingTeam),
            holesLine: holesOpened
        )
        // Presented outside the shell (league roster browser, player detail),
        // `deliver` stages the receipt on the `WeekAdvancer` channel the shell
        // drains, so it is delayed rather than lost.
        deliver(receipt)

        clearSelections()
        selectedPartner = nil
        loadData()
    }

    /// Severity at which a position group stops being thin and starts being a
    /// hole worth putting in a receipt.
    ///
    /// Trades against: a receipt that names something real, versus one that
    /// cries wolf every time a backup changes address. 0.30 is the same number
    /// `buildPayment`'s needs-swap uses for "a starter slot he is currently
    /// covering below replacement level", so the line the user reads and the
    /// hole the AI market is willing to pay a premium to fill are the same hole.
    private static let holeSeverity = 0.30

    /// F-57: names any position the executed deal pushed past `holeSeverity`.
    ///
    /// No message, tile, badge or news item ever told the user a trade opened a
    /// depth hole. `validationErrors` refuses the extreme case — a squad left
    /// without a single centre — and said nothing at all about going from three
    /// corners to two. This is the missing middle, and it is what turns "cap
    /// adjustments have been processed" into a consequence.
    private func rosterHolesOpened(before: TradeValueEngine.NeedProfile) -> String? {
        let after = TradeValueEngine.needProfile(
            roster: allPlayers.filter { $0.teamID == career.teamID && !$0.isRetired }
        )
        let crossed = Position.allCases.filter { position in
            before.severity(position) < Self.holeSeverity
                && after.severity(position) >= Self.holeSeverity
        }
        guard !crossed.isEmpty else { return nil }
        let named = crossed
            .sorted { after.severity($0) > after.severity($1) }
            .map { "\($0.rawValue) (now starting \(after.starterOVR[$0] ?? 0) OVR)" }
        return named.count == 1
            ? "That deal left us thin at \(named[0]). Expect the question at the podium."
            : "That deal left us thin at \(named.joined(separator: ", ")). Expect the question at the podium."
    }

    /// Writes the league news item for a trade that just executed.
    private func announceExecutedTrade(record: TradeRecord?) {
        guard let record else { return }
        let teamsByID = Dictionary(uniqueKeysWithValues: allTeams.map { ($0.id, $0) })
        let announcement = TradeNewsFactory.announce(
            record: record,
            teamsByID: teamsByID,
            userTeamID: career.teamID
        )
        career.postNews(announcement.news)
        try? modelContext.save()
    }

    private func acceptOffer(_ offer: TradeProposal) {
        guard let aiTeam = allTeams.first(where: { $0.id == offer.offeringTeamID }) else { return }

        let blockers = validationErrors(for: offer)
        if !blockers.isEmpty {
            tradeResultMessage = "Trade blocked:\n" + blockers.joined(separator: "\n")
            resultIsSuccess = false
            showResultAlert = true
            return
        }

        executeUserTrade(offer, counterparty: aiTeam, userIsOfferingTeam: false)
        tradeResultMessage = "Trade with \(aiTeam.abbreviation) completed!"
        resultIsSuccess = true
        showResultAlert = true
    }

    /// Wave 3: "Negotiate" finally negotiates.
    ///
    /// It used to dump the offer into the builder and leave — the user was on
    /// his own, with no record that a GM had ever called. Now it opens (or
    /// re-enters) the thread with that club, seeded with their package, so the
    /// counter-offer machinery answers in the same conversation.
    private func negotiateOffer(_ offer: TradeProposal) {
        guard let aiTeam = allTeams.first(where: { $0.id == offer.offeringTeamID }),
              let myTeam = playerTeam else { return }

        if let existing = threads.first(where: { $0.sourceOfferID == offer.id && $0.status == .open })
            ?? threads.first(where: { $0.partnerTeamID == aiTeam.id && $0.status == .open }) {
            activeNegotiation = NegotiationRoute(
                partnerTeamID: aiTeam.id,
                threadID: existing.id
            )
            return
        }

        // In the stored offer the AI is the offering team; a thread is always
        // written from the user's chair, so the asset directions flip. The
        // proposal keeps the OFFER's id so accepting it prunes the same row from
        // `career.pendingTradeOffers`.
        let seed = TradeProposal(
            id: offer.id,
            offeringTeamID: myTeam.id,
            receivingTeamID: aiTeam.id,
            sendingPlayers: offer.receivingPlayers,
            receivingPlayers: offer.sendingPlayers,
            sendingPicks: offer.receivingPicks,
            receivingPicks: offer.sendingPicks
        )
        activeNegotiation = NegotiationRoute(
            partnerTeamID: aiTeam.id,
            seed: seed,
            sourceOfferID: offer.id
        )
    }

    private func declineOffer(_ offer: TradeProposal) {
        incomingOffers.removeAll { $0.id == offer.id }
        career.pendingTradeOffers = career.pendingTradeOffers.filter { $0.id != offer.id }
        // Declining also ends any conversation that grew out of this offer —
        // otherwise the thread shelf keeps advertising a dead deal.
        career.tradeThreads = career.tradeThreads.map { thread in
            guard thread.sourceOfferID == offer.id, thread.status == .open else { return thread }
            var closed = thread
            closed.status = .withdrawn
            return closed
        }
        threads = career.tradeThreads
        try? modelContext.save()
    }

    /// Inbox notice for a completed trade (both user-initiated and accepted
    /// incoming offers).
    ///
    /// F-49: the dead-money sentence is no longer written here. It comes from
    /// `TradeEngine.TradeCapOutcome.deadCapLine`, in the engine layer that
    /// computes the number, so the draft room quotes the identical line instead
    /// of the silent "roster and cap adjustments have been processed" the shared
    /// factory used to hand it.
    private func completedTradeInboxMessage(
        proposal: TradeProposal,
        counterparty: Team,
        userIsOfferingTeam: Bool,
        deadCapLine: String?,
        /// F-57: positions the deal pushed past `holeSeverity`, or `nil`.
        holesLine: String?
    ) -> InboxMessage {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        let outgoingPlayerIDs = userIsOfferingTeam ? proposal.sendingPlayers   : proposal.receivingPlayers
        let outgoingPickIDs   = userIsOfferingTeam ? proposal.sendingPicks     : proposal.receivingPicks
        let incomingPlayerIDs = userIsOfferingTeam ? proposal.receivingPlayers : proposal.sendingPlayers
        let incomingPickIDs   = userIsOfferingTeam ? proposal.receivingPicks   : proposal.sendingPicks

        let outNames = outgoingPlayerIDs.compactMap { playerLookup[$0]?.fullName } +
                       outgoingPickIDs.compactMap { pickLookup[$0].map { pickLabelShort($0) } }
        let inNames  = incomingPlayerIDs.compactMap { playerLookup[$0]?.fullName } +
                       incomingPickIDs.compactMap { pickLookup[$0].map { pickLabelShort($0) } }

        return InboxMessage(
            sender: .leagueOffice,
            subject: "Trade completed with \(counterparty.abbreviation)",
            body: """
            The league office has approved your trade with \(counterparty.fullName).

            You receive: \(inNames.isEmpty ? "—" : inNames.joined(separator: ", "))
            You send: \(outNames.isEmpty ? "—" : outNames.joined(separator: ", "))
            \(deadCapLine.map { $0 + "\n" } ?? "")\(holesLine.map { $0 + "\n" } ?? "")
            All roster and cap adjustments have been processed.
            """,
            date: "Week \(career.currentWeek), Season \(career.currentSeason)",
            category: .tradeOffer,
            actionDestination: .roster
        )
    }

    // MARK: - Data

    private func loadData() {
        let cid = career.id
        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.careerID == cid })
        allTeams = (try? modelContext.fetch(teamDescriptor)) ?? []

        if let teamID = career.teamID {
            playerTeam = allTeams.first { $0.id == teamID }
        }

        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.careerID == cid })
        allPlayers = (try? modelContext.fetch(playerDescriptor)) ?? []

        let pickDescriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate { $0.careerID == cid && !$0.isComplete }
        )
        allPicks = (try? modelContext.fetch(pickDescriptor)) ?? []

        allContracts = (try? modelContext.fetch(FetchDescriptor<Contract>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []

        // R21: incoming offers are persisted on the career (generated weekly
        // by WeekAdvancer). Show only offers whose assets are still where the
        // offer assumes them to be, and prune the rest from storage.
        let stored = career.pendingTradeOffers
        let valid = stored.filter {
            TradeValueEngine.isProposalStillValid($0, allPlayers: allPlayers, allPicks: allPicks)
        }
        if valid.count != stored.count {
            career.pendingTradeOffers = valid
            try? modelContext.save()
        }
        incomingOffers = valid

        loadTradeHistory()
        loadThreads()
        applyPrefillIfNeeded()
    }

    /// Hydrates the negotiation shelf and closes out conversations that reality
    /// has overtaken.
    ///
    /// A thread dies when its league year ends (`TradeTalkRegistry` resets every
    /// February, so the GM on the other end is a different negotiator), when the
    /// trade window shuts under it, or when one of its assets has moved — the
    /// same staleness rule `isProposalStillValid` applies to stored offers. The
    /// user gets a receipt rather than a silent disappearance.
    private func loadThreads() {
        let stored = career.tradeThreads
        guard !stored.isEmpty else {
            threads = []
            return
        }

        let windowOpen = TradeValueEngine.isTradeWindowOpen(
            phase: career.currentPhase, week: career.currentWeek
        )
        var expiredCount = 0
        let reconciled: [TradeNegotiationThread] = stored.map { thread in
            guard thread.status == .open else { return thread }
            let stale = thread.season != career.currentSeason
                || !windowOpen
                || !TradeValueEngine.isProposalStillValid(
                    thread.proposal, allPlayers: allPlayers, allPicks: allPicks
                )
            guard stale else { return thread }
            expiredCount += 1
            var closed = thread
            closed.status = .expired
            return closed
        }

        // Drop terminal threads from previous league years entirely — the shelf
        // is a working desk, not an archive (`TradeRecord` is the archive).
        let kept = reconciled.filter {
            $0.season == career.currentSeason || $0.status == .open
        }

        if expiredCount > 0 || kept.count != stored.count {
            career.tradeThreads = kept
            try? modelContext.save()
        }
        threads = kept

        if expiredCount > 0 {
            deliver(InboxEngine.tradeNegotiationsExpiredMessage(
                count: expiredCount,
                dateString: InboxEngine.dateLabel(
                    week: career.currentWeek,
                    season: career.currentSeason,
                    phase: career.currentPhase
                )
            ))
        }
    }

    /// Points the builder at the partner the caller arrived with and ticks the
    /// players they asked about. Runs once (see `didApplyPrefill`).
    private func applyPrefillIfNeeded() {
        guard !didApplyPrefill, let prefill else { return }
        didApplyPrefill = true
        guard let partner = allTeams.first(where: { $0.id == prefill.partnerTeamID }),
              partner.id != playerTeam?.id
        else { return }
        selectedPartner = partner
        // Only targets still on that roster — an offer built from a stale detail
        // screen must not silently include a player who was already traded away.
        let onRoster = Set(allPlayers.filter { $0.teamID == partner.id }.map(\.id))
        theirSelectedPlayers = Set(prefill.targetPlayerIDs.filter { onRoster.contains($0) })
        // F-58: the same staleness guard on our own side. A man shopped from a
        // detail screen and then traded elsewhere must not reappear ticked in a
        // package we no longer own him for.
        let ourRoster = Set(allPlayers.filter { $0.teamID == career.teamID }.map(\.id))
        mySelectedPlayers = Set(prefill.offeredPlayerIDs.filter { ourRoster.contains($0) })
    }

    // MARK: - Computed Helpers

    private var otherTeams: [Team] {
        allTeams
            .filter { $0.id != playerTeam?.id }
            .sorted { $0.abbreviation < $1.abbreviation }
    }

    private var myPlayers: [Player] {
        guard let myTeam = playerTeam else { return [] }
        return allPlayers
            .filter { $0.teamID == myTeam.id }
            .sorted { $0.overall > $1.overall }
    }

    private var myPicks: [DraftPick] {
        guard let myTeam = playerTeam else { return [] }
        return allPicks
            .filter { $0.currentTeamID == myTeam.id }
            .sorted { $0.pickNumber < $1.pickNumber }
    }

    private func theirPlayers(partner: Team) -> [Player] {
        allPlayers
            .filter { $0.teamID == partner.id }
            .sorted { $0.overall > $1.overall }
    }

    private func theirPicks(partner: Team) -> [DraftPick] {
        allPicks
            .filter { $0.currentTeamID == partner.id }
            .sorted { $0.pickNumber < $1.pickNumber }
    }

    private var currentProposalValues: (sendingValue: Int, receivingValue: Int) {
        guard let myTeam = playerTeam, let partner = selectedPartner else {
            return (0, 0)
        }
        let proposal = TradeProposal(
            offeringTeamID: myTeam.id,
            receivingTeamID: partner.id,
            sendingPlayers: Array(mySelectedPlayers),
            receivingPlayers: Array(theirSelectedPlayers),
            sendingPicks: Array(mySelectedPicks),
            receivingPicks: Array(theirSelectedPicks)
        )
        return TradeValueEngine.proposalValues(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: career.currentSeason
        )
    }

    // MARK: - UI Helpers

    private func toggle(id: UUID, in binding: Binding<Set<UUID>>) {
        if binding.wrappedValue.contains(id) {
            binding.wrappedValue.remove(id)
        } else {
            binding.wrappedValue.insert(id)
        }
    }

    private func clearSelections() {
        mySelectedPlayers = []
        mySelectedPicks = []
        theirSelectedPlayers = []
        theirSelectedPicks = []
    }

    private func pickLabel(_ pick: DraftPick) -> String {
        TradeAssetFormat.pickLabel(pick)
    }

    private func positionColor(_ position: Position) -> Color {
        TradeAssetFormat.positionColor(position)
    }

    // MARK: - vs Current Starter Card (decision support — letter-grade comparison)

    @ViewBuilder
    private func vsCurrentStarterCard(for target: Player) -> some View {
        let starter = myPlayers
            .filter { $0.position == target.position && $0.id != target.id }
            .max(by: { $0.overall < $1.overall })

        if let starter {
            let diff = target.overall - starter.overall
            let conclusion = starterConclusionLabel(diff)
            let conclusionColor = starterConclusionColor(diff)
            let targetGrade = LetterGrade.from(numericValue: target.overall)
            let starterGrade = LetterGrade.from(numericValue: starter.overall)

            HStack(spacing: 8) {
                // Trade target side
                VStack(spacing: 1) {
                    Text(target.fullName)
                        .font(.system(size: 10).weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(targetGrade.rawValue)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(rowGradeColor(targetGrade))
                    Text("Target")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)

                // Comparison conclusion
                VStack(spacing: 1) {
                    Text("vs")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textTertiary)
                    Text(conclusion)
                        .font(.system(size: 10).weight(.heavy))
                        .foregroundStyle(conclusionColor)
                        .multilineTextAlignment(.center)
                }

                // Current starter side
                VStack(spacing: 1) {
                    Text(starter.fullName)
                        .font(.system(size: 10).weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(starterGrade.rawValue)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(rowGradeColor(starterGrade))
                    Text("Starter")
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.backgroundSecondary)
            )
        } else {
            HStack(spacing: 8) {
                Image(systemName: "person.fill.badge.plus")
                    .font(.caption)
                    .foregroundStyle(Color.success)
                Text("No \(target.position.rawValue) on roster — immediate starter")
                    .font(.system(size: 10).weight(.semibold))
                    .foregroundStyle(Color.success)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.success.opacity(0.1))
            )
        }
    }

    private func starterConclusionLabel(_ diff: Int) -> String {
        if diff >= 3 { return "Upgrade" }
        if diff >= -2 { return "Lateral" }
        return "Downgrade"
    }

    private func starterConclusionColor(_ diff: Int) -> Color {
        if diff >= 3 { return .success }
        if diff >= -2 { return .accentGold }
        return .textSecondary
    }

    /// The upgrade comparison's letters read the ONE ladder. Ranking by
    /// `LetterGrade.rank` gave the B tier gold where every roster and board
    /// screen paints it blue, and dropped D in with F.
    private func rowGradeColor(_ grade: LetterGrade) -> Color {
        Color.forGrade(grade)
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    // MARK: - Breakdown helpers

    private func pickLabelShort(_ pick: DraftPick) -> String {
        TradeAssetFormat.pickLabelShort(pick)
    }

    private func currentProposalBreakdown(partner: Team) -> ProposalBreakdown {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        var yourLines: [BreakdownLine] = []
        for id in mySelectedPlayers {
            guard let p = playerLookup[id] else { continue }
            yourLines.append(BreakdownLine(
                label: p.fullName,
                detail: playerValueDetail(p),
                value: TradeValueEngine.playerTradeValue(player: p)
            ))
        }
        for id in mySelectedPicks {
            guard let pick = pickLookup[id] else { continue }
            yourLines.append(BreakdownLine(
                label: pickLabelShort(pick),
                detail: pickValueDetail(pick),
                value: TradeValueEngine.pickTradeValue(pick: pick, currentSeason: career.currentSeason)
            ))
        }

        var theirLines: [BreakdownLine] = []
        for id in theirSelectedPlayers {
            guard let p = playerLookup[id] else { continue }
            theirLines.append(BreakdownLine(
                label: p.fullName,
                detail: playerValueDetail(p),
                value: TradeValueEngine.playerTradeValue(player: p)
            ))
        }
        for id in theirSelectedPicks {
            guard let pick = pickLookup[id] else { continue }
            theirLines.append(BreakdownLine(
                label: pickLabelShort(pick),
                detail: pickValueDetail(pick),
                value: TradeValueEngine.pickTradeValue(pick: pick, currentSeason: career.currentSeason)
            ))
        }

        let yourTotal = yourLines.reduce(0) { $0 + $1.value }
        let theirTotal = theirLines.reduce(0) { $0 + $1.value }
        return ProposalBreakdown(
            yourLines: yourLines,
            theirLines: theirLines,
            yourTotal: yourTotal,
            theirTotal: theirTotal
        )
    }

    /// Explains which value-curve factors drive a player's trade value.
    private func playerValueDetail(_ player: Player) -> String {
        var parts = ["\(player.position.rawValue) · \(player.overall) OVR · Age \(player.age)"]
        let ageMult = TradeValueEngine.ageMultiplier(age: player.age, position: player.position)
        if ageMult < 0.85 { parts.append("aging") }
        else if ageMult > 1.0 { parts.append("young upside") }
        let contractMult = TradeValueEngine.contractMultiplier(player: player)
        if contractMult > 1.05 { parts.append("bargain contract") }
        else if player.contractYearsRemaining <= 1 { parts.append("expiring deal") }
        else if contractMult < 0.9 { parts.append("pricey contract") }
        return parts.joined(separator: " · ")
    }

    private func pickValueDetail(_ pick: DraftPick) -> String {
        pick.seasonYear > career.currentSeason
            ? "Pick chart value · future-year discount"
            : "Pick chart value"
    }
}

// MARK: - Local Helper Types

private struct BreakdownLine: Identifiable {
    let id = UUID()
    let label: String
    let detail: String
    let value: Int
}

private struct ProposalBreakdown {
    let yourLines: [BreakdownLine]
    let theirLines: [BreakdownLine]
    let yourTotal: Int
    let theirTotal: Int
}

private struct CompletedTrade: Identifiable {
    let id = UUID()
    let counterpartyAbbr: String
    let sentValue: Int
    let receivedValue: Int
    let grade: String
    let headline: String
}

private struct WizardSuggestion {
    let picks: [DraftPick]
}

/// What the negotiation cover needs to know: which club, and whether we are
/// resuming a persisted thread or opening a new one from a package.
private struct NegotiationRoute: Identifiable {
    let id = UUID()
    let partnerTeamID: UUID
    var threadID: UUID? = nil
    var seed: TradeProposal? = nil
    var sourceOfferID: UUID? = nil
    var openingLine: String? = nil
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TradeView(career: Career(
            playerName: "Coach",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(
        for: [Career.self, Player.self, Team.self, DraftPick.self, TradeRecord.self],
        inMemory: true
    )
}
