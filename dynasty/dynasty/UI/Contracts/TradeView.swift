import SwiftUI
import SwiftData

// MARK: - TradeView

struct TradeView: View {

    let career: Career

    /// R21: lets the shell surface completed-trade notices in the inbox.
    var onInboxMessage: ((InboxMessage) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext

    // MARK: Data
    @State private var playerTeam: Team?
    @State private var allTeams: [Team] = []
    @State private var allPlayers: [Player] = []
    @State private var allPicks: [DraftPick] = []

    // MARK: Propose Trade state
    @State private var selectedPartner: Team?
    @State private var mySelectedPlayers: Set<UUID> = []
    @State private var mySelectedPicks: Set<UUID> = []
    @State private var theirSelectedPlayers: Set<UUID> = []
    @State private var theirSelectedPicks: Set<UUID> = []

    // MARK: Incoming offers
    @State private var incomingOffers: [TradeProposal] = []

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
    }

    // MARK: - Trade Closed

    private var tradeClosedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundStyle(Color.textTertiary)
            Text("Trade Window Closed")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.textPrimary)
            Text("Trades are open during the offseason and the regular season through the Week \(TradeValueEngine.deadlineWeek) deadline. The window reopens after the season.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Propose Trade Section

    private var proposeSectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader(title: "Propose Trade", icon: "arrow.left.arrow.right")

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
                Divider().overlay(Color.surfaceBorder)
                proposeButton(partner: partner)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .cardBackground()
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
                        accentColor: accentColor
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
                    sublabel: "\(pick.seasonYear)",
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

    private func assetToggleRow(
        label: String,
        sublabel: String,
        valueLabel: String,
        isSelected: Bool,
        accentColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? accentColor : Color.textTertiary)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(sublabel)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
                Spacer()
                Text(valueLabel)
                    .font(.system(size: 10).weight(.semibold).monospacedDigit())
                    .foregroundStyle(isSelected ? accentColor : Color.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected
                          ? accentColor.opacity(0.12)
                          : Color.backgroundTertiary)
            )
        }
        .buttonStyle(.plain)
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
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentBlue)
                        .frame(width: geo.size.width * sendFraction)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentGold)
                        .frame(maxWidth: .infinity)
                }
                .frame(height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
            currentSeason: career.currentSeason
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

        return Button {
            submitProposal(partner: partner)
        } label: {
            Label("Propose Trade", systemImage: "arrow.left.arrow.right")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(hasAssets ? Color.backgroundPrimary : Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(hasAssets ? Color.accentGold : Color.backgroundTertiary)
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasAssets)
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
                        Text("AI offers arrive weekly during the regular season — contenders buy, rebuilders sell. New offers land in your inbox until the Week \(TradeValueEngine.deadlineWeek) deadline.")
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

    private func offerAssetColumn(
        title: String,
        playerIDs: [UUID],
        pickIDs: [UUID],
        valueLabel: String,
        accentColor: Color
    ) -> some View {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })

        let players = playerIDs.compactMap { playerLookup[$0] }
        let picks   = pickIDs.compactMap   { pickLookup[$0]   }

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(valueLabel)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(accentColor)
            }

            ForEach(players) { player in
                HStack(spacing: 6) {
                    Text(player.position.rawValue)
                        .font(.system(size: 9).weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(positionColor(player.position), in: RoundedRectangle(cornerRadius: 3))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.fullName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        Text("\(player.overall) OVR · Age \(player.age)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            ForEach(picks) { pick in
                HStack(spacing: 6) {
                    Text("PICK")
                        .font(.system(size: 9).weight(.bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 3))
                    Text(pickLabel(pick))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
            }

            if players.isEmpty && picks.isEmpty {
                Text("Nothing")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .font(.system(size: 13).weight(.bold))
                    .foregroundStyle(hasAssets ? willingness.color : Color.textTertiary)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(willingness.color.opacity(hasAssets ? 0.10 : 0.0))
        )
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

    // MARK: - Cap Impact

    @ViewBuilder
    private func capImpactSection(partner: Team) -> some View {
        if let myTeam = playerTeam {
            let impact = computeCapImpact(myTeam: myTeam, partner: partner)
            let hasAny = impact.yourDelta != 0 || impact.theirDelta != 0

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
                        delta: -impact.yourDelta
                    )
                    Divider().overlay(Color.surfaceBorder).frame(maxHeight: 70)
                    capImpactColumn(
                        teamLabel: partner.abbreviation,
                        beforeRoom: partner.salaryCap - partner.currentCapUsage,
                        afterRoom: (partner.salaryCap - partner.currentCapUsage) - impact.theirDelta,
                        delta: -impact.theirDelta
                    )
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
        delta: Int
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func computeCapImpact(myTeam: Team, partner: Team) -> (yourDelta: Int, theirDelta: Int) {
        // yourDelta = net cap added to your team (positive = more salary on books)
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let outgoingSalary = mySelectedPlayers
            .compactMap { playerLookup[$0]?.annualSalary }
            .reduce(0, +)
        let incomingSalary = theirSelectedPlayers
            .compactMap { playerLookup[$0]?.annualSalary }
            .reduce(0, +)
        let yourDelta = incomingSalary - outgoingSalary
        let theirDelta = outgoingSalary - incomingSalary
        return (yourDelta, theirDelta)
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

    private func wizardPickChip(pick: DraftPick, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(pickLabelShort(pick))
                    .font(.system(size: 11).weight(.bold))
                Text("\(PickValueChart.points(forPick: pick.pickNumber)) pts")
                    .font(.system(size: 9))
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
        let myValue = PickValueChart.points(forPick: myPick.pickNumber)
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
        let totalValue = suggestion.picks.reduce(0) { $0 + PickValueChart.points(forPick: $1.pickNumber) }
        let ratio: Double = myValue > 0 ? Double(totalValue) / Double(myValue) : 0
        let label = String(format: "%.0f%%", ratio * 100.0)

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(suggestion.picks) { p in
                    Text(pickLabelShort(p) + "  \(PickValueChart.points(forPick: p.pickNumber)) pts")
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
            .filter { PickValueChart.points(forPick: $0.pickNumber) > Int(Double(myPickValue) * 1.05) }
            .sorted { PickValueChart.points(forPick: $0.pickNumber) < PickValueChart.points(forPick: $1.pickNumber) }
            .prefix(3)
        for pick in betterPicks {
            results.append(WizardSuggestion(picks: [pick]))
        }
        return results
    }

    private func tradeDownSuggestions(myPickValue: Int, partnerPicks: [DraftPick]) -> [WizardSuggestion] {
        let lesser = partnerPicks
            .filter { PickValueChart.points(forPick: $0.pickNumber) < myPickValue }
            .sorted { PickValueChart.points(forPick: $0.pickNumber) > PickValueChart.points(forPick: $1.pickNumber) }

        guard !lesser.isEmpty else { return [] }

        var results: [WizardSuggestion] = []
        let lower = Int(Double(myPickValue) * 0.85)
        let upper = Int(Double(myPickValue) * 1.15)

        for i in 0..<lesser.count {
            let v1 = PickValueChart.points(forPick: lesser[i].pickNumber)
            if v1 >= lower && v1 <= upper {
                results.append(WizardSuggestion(picks: [lesser[i]]))
                if results.count >= 3 { return results }
            }
            for j in (i + 1)..<lesser.count {
                let v2 = v1 + PickValueChart.points(forPick: lesser[j].pickNumber)
                if v2 >= lower && v2 <= upper {
                    results.append(WizardSuggestion(picks: [lesser[i], lesser[j]]))
                    if results.count >= 3 { return results }
                }
                if lesser.count > j + 1 {
                    for k in (j + 1)..<lesser.count {
                        let v3 = v2 + PickValueChart.points(forPick: lesser[k].pickNumber)
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

    private func historyGradeColor(_ grade: String) -> Color {
        switch grade {
        case "A+", "A": return .success
        case "B": return .accentGold
        case "C": return .warning
        default: return .danger
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

    private func submitProposal(partner: Team) {
        guard let myTeam = playerTeam else { return }

        let proposal = TradeProposal(
            offeringTeamID: myTeam.id,
            receivingTeamID: partner.id,
            sendingPlayers: Array(mySelectedPlayers),
            receivingPlayers: Array(theirSelectedPlayers),
            sendingPicks: Array(mySelectedPicks),
            receivingPicks: Array(theirSelectedPicks)
        )

        // Hard validation first: roster sizes and salary cap (CapMode-aware).
        let blockers = TradeValueEngine.validationErrors(
            proposal: proposal,
            allPlayers: allPlayers,
            teams: allTeams,
            capMode: career.capMode
        )
        if !blockers.isEmpty {
            tradeResultMessage = "Trade blocked:\n" + blockers.joined(separator: "\n")
            resultIsSuccess = false
            showResultAlert = true
            return
        }

        // AI responds: accept ≥ 105 % of value, reject < 90 %, else counter.
        let response = TradeValueEngine.respond(
            to: proposal,
            aiTeam: partner,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: career.currentSeason
        )

        switch response {
        case .accepted:
            executeUserTrade(proposal, counterparty: partner, userIsOfferingTeam: true)
            tradeResultMessage = "\(partner.abbreviation) accepted the trade!"
            resultIsSuccess = true

        case .rejected(let reason):
            tradeResultMessage = reason
            resultIsSuccess = false

        case .countered(let counter, let message):
            // Pre-fill the builder with the counter so the user can accept it
            // by tapping Propose again, or keep tweaking.
            mySelectedPlayers = Set(counter.sendingPlayers)
            mySelectedPicks = Set(counter.sendingPicks)
            theirSelectedPlayers = Set(counter.receivingPlayers)
            theirSelectedPicks = Set(counter.receivingPicks)
            tradeResultMessage = "\(message)\n\nThe counter is loaded in the trade builder."
            resultIsSuccess = false
        }

        showResultAlert = true
    }

    /// Executes an agreed trade, persists it, and drops any pending offers
    /// that the roster/pick moves invalidated.
    private func executeUserTrade(
        _ proposal: TradeProposal,
        counterparty: Team,
        userIsOfferingTeam: Bool
    ) {
        // Capture history before mutating rosters so lookups still resolve.
        recordCompletedTrade(
            proposal: proposal,
            counterpartyAbbr: counterparty.abbreviation,
            userIsOfferingTeam: userIsOfferingTeam
        )
        TradeEngine.executeTrade(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks,
            modelContext: modelContext
        )
        // Any stored offers touching the moved assets are now void.
        career.pendingTradeOffers = career.pendingTradeOffers.filter {
            $0.id != proposal.id &&
            TradeValueEngine.isProposalStillValid($0, allPlayers: allPlayers, allPicks: allPicks)
        }
        try? modelContext.save()

        // Surface the completed deal in the inbox.
        onInboxMessage?(completedTradeInboxMessage(
            proposal: proposal,
            counterparty: counterparty,
            userIsOfferingTeam: userIsOfferingTeam
        ))

        clearSelections()
        selectedPartner = nil
        loadData()
    }

    private func acceptOffer(_ offer: TradeProposal) {
        guard let aiTeam = allTeams.first(where: { $0.id == offer.offeringTeamID }) else { return }

        let blockers = TradeValueEngine.validationErrors(
            proposal: offer,
            allPlayers: allPlayers,
            teams: allTeams,
            capMode: career.capMode
        )
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

    /// Loads an incoming offer into the propose builder so the user can
    /// rework the package and submit a modified version.
    private func negotiateOffer(_ offer: TradeProposal) {
        guard let aiTeam = allTeams.first(where: { $0.id == offer.offeringTeamID }) else { return }
        selectedPartner = aiTeam
        // In the stored offer the AI is the offering team; in the builder the
        // user is always the offering side, so the asset directions flip.
        mySelectedPlayers = Set(offer.receivingPlayers)
        mySelectedPicks = Set(offer.receivingPicks)
        theirSelectedPlayers = Set(offer.sendingPlayers)
        theirSelectedPicks = Set(offer.sendingPicks)
    }

    private func declineOffer(_ offer: TradeProposal) {
        incomingOffers.removeAll { $0.id == offer.id }
        career.pendingTradeOffers = career.pendingTradeOffers.filter { $0.id != offer.id }
        try? modelContext.save()
    }

    /// Inbox notice for a completed trade (both user-initiated and accepted
    /// incoming offers).
    private func completedTradeInboxMessage(
        proposal: TradeProposal,
        counterparty: Team,
        userIsOfferingTeam: Bool
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

            All roster and cap adjustments have been processed.
            """,
            date: "Week \(career.currentWeek), Season \(career.currentSeason)",
            category: .tradeOffer,
            actionDestination: .roster
        )
    }

    // MARK: - Data

    private func loadData() {
        let teamDescriptor = FetchDescriptor<Team>()
        allTeams = (try? modelContext.fetch(teamDescriptor)) ?? []

        if let teamID = career.teamID {
            playerTeam = allTeams.first { $0.id == teamID }
        }

        let playerDescriptor = FetchDescriptor<Player>()
        allPlayers = (try? modelContext.fetch(playerDescriptor)) ?? []

        let pickDescriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate { !$0.isComplete }
        )
        allPicks = (try? modelContext.fetch(pickDescriptor)) ?? []

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
        let suffix: String
        switch pick.round {
        case 1: suffix = "1st"
        case 2: suffix = "2nd"
        case 3: suffix = "3rd"
        default: suffix = "\(pick.round)th"
        }
        return "\(pick.seasonYear) \(suffix) Rd (#\(pick.pickNumber))"
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
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
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)

                // Comparison conclusion
                VStack(spacing: 1) {
                    Text("vs")
                        .font(.system(size: 9))
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
                        .font(.system(size: 9))
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

    private func rowGradeColor(_ grade: LetterGrade) -> Color {
        switch grade.rank {
        case 10...12: return .success
        case 7...9:   return .accentGold
        case 4...6:   return .warning
        case 2...3:   return .danger
        default:      return .danger
        }
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
        let suffix: String
        switch pick.round {
        case 1: suffix = "1st"
        case 2: suffix = "2nd"
        case 3: suffix = "3rd"
        default: suffix = "\(pick.round)th"
        }
        return "\(pick.seasonYear) \(suffix) (#\(pick.pickNumber))"
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

// MARK: - Preview

#Preview {
    NavigationStack {
        TradeView(career: Career(
            playerName: "Coach",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Player.self, Team.self, DraftPick.self], inMemory: true)
}
