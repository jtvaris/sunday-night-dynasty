import SwiftUI
import SwiftData

// MARK: - TradeView

struct TradeView: View {

    let career: Career

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

            if career.currentPhase == .tradeDeadline ||
               career.currentPhase == .regularSeason {
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
            Text("Trades are only available during the Regular Season and up to the Trade Deadline.")
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
                        sublabel: "\(player.position.rawValue) · \(player.overall) OVR",
                        valueLabel: formatMillions(ContractEngine.estimateMarketValue(player: player)),
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
                    valueLabel: "\(DraftEngine.pickValue(pick.pickNumber))",
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
                fairnessLabel(sending: sending, receiving: receiving)
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
                Label(formatMillions(sending), systemImage: "arrow.up.right")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.accentBlue)
                Spacer()
                Label(formatMillions(receiving), systemImage: "arrow.down.left")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }
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
                        Text("Advance weeks during the regular season to receive AI trade proposals.")
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
        let values = TradeEngine.evaluateTradeValue(
            proposal: offer,
            allPlayers: allPlayers,
            allPicks: allPicks
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
                    valueLabel: formatMillions(youSend),
                    accentColor: Color.danger
                )
                Divider().overlay(Color.surfaceBorder).frame(maxHeight: 200)
                offerAssetColumn(
                    title: "You Receive",
                    playerIDs: offer.sendingPlayers,
                    pickIDs: offer.sendingPicks,
                    valueLabel: formatMillions(youReceive),
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
        let values = currentProposalValues
        let hasAssets = !mySelectedPlayers.isEmpty || !mySelectedPicks.isEmpty ||
                        !theirSelectedPlayers.isEmpty || !theirSelectedPicks.isEmpty

        let willingness = aiWillingnessForCurrentProposal(partner: partner)

        HStack(spacing: 10) {
            Image(systemName: willingness.icon)
                .foregroundStyle(willingness.color)
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Willingness")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Text(hasAssets ? willingness.label : "Select assets to gauge interest")
                    .font(.system(size: 13).weight(.bold))
                    .foregroundStyle(hasAssets ? willingness.color : Color.textTertiary)
            }
            Spacer()
            if hasAssets, values.receivingValue > 0 {
                let ratio = Double(values.sendingValue) / Double(max(values.receivingValue, 1))
                Text(String(format: "%.0f%%", ratio * 100.0))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(willingness.color.opacity(hasAssets ? 0.10 : 0.0))
        )
    }

    private func aiWillingnessForCurrentProposal(partner: Team) -> (label: String, icon: String, color: Color) {
        guard let myTeam = playerTeam else {
            return ("Rejects", "xmark.circle.fill", Color.danger)
        }
        let proposal = TradeProposal(
            offeringTeamID: myTeam.id,
            receivingTeamID: partner.id,
            sendingPlayers: Array(mySelectedPlayers),
            receivingPlayers: Array(theirSelectedPlayers),
            sendingPicks: Array(mySelectedPicks),
            receivingPicks: Array(theirSelectedPicks)
        )
        let values = TradeEngine.evaluateTradeValue(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks
        )

        // From AI's perspective: AI gives proposal.receivingValue, gets proposal.sendingValue
        let aiGives    = values.receivingValue
        let aiReceives = values.sendingValue

        if aiGives <= 0 && aiReceives <= 0 {
            return ("Rejects", "xmark.circle.fill", Color.danger)
        }
        if aiGives <= 0 {
            return ("Likely accepts", "checkmark.circle.fill", Color.success)
        }

        let ratio = Double(aiReceives) / Double(aiGives)
        if ratio >= 0.95 {
            return ("Likely accepts", "checkmark.circle.fill", Color.success)
        } else if ratio >= 0.80 {
            return ("Will counter", "arrow.left.arrow.right.circle.fill", Color.warning)
        } else {
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
                Text("\(DraftEngine.pickValue(pick.pickNumber)) pts")
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
        let myValue = DraftEngine.pickValue(myPick.pickNumber)
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
        let totalValue = suggestion.picks.reduce(0) { $0 + DraftEngine.pickValue($1.pickNumber) }
        let ratio: Double = myValue > 0 ? Double(totalValue) / Double(myValue) : 0
        let label = String(format: "%.0f%%", ratio * 100.0)

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(suggestion.picks) { p in
                    Text(pickLabelShort(p) + "  \(DraftEngine.pickValue(p.pickNumber)) pts")
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
            .filter { DraftEngine.pickValue($0.pickNumber) > Int(Double(myPickValue) * 1.05) }
            .sorted { DraftEngine.pickValue($0.pickNumber) < DraftEngine.pickValue($1.pickNumber) }
            .prefix(3)
        for pick in betterPicks {
            results.append(WizardSuggestion(picks: [pick]))
        }
        return results
    }

    private func tradeDownSuggestions(myPickValue: Int, partnerPicks: [DraftPick]) -> [WizardSuggestion] {
        let lesser = partnerPicks
            .filter { DraftEngine.pickValue($0.pickNumber) < myPickValue }
            .sorted { DraftEngine.pickValue($0.pickNumber) > DraftEngine.pickValue($1.pickNumber) }

        guard !lesser.isEmpty else { return [] }

        var results: [WizardSuggestion] = []
        let lower = Int(Double(myPickValue) * 0.85)
        let upper = Int(Double(myPickValue) * 1.15)

        for i in 0..<lesser.count {
            let v1 = DraftEngine.pickValue(lesser[i].pickNumber)
            if v1 >= lower && v1 <= upper {
                results.append(WizardSuggestion(picks: [lesser[i]]))
                if results.count >= 3 { return results }
            }
            for j in (i + 1)..<lesser.count {
                let v2 = v1 + DraftEngine.pickValue(lesser[j].pickNumber)
                if v2 >= lower && v2 <= upper {
                    results.append(WizardSuggestion(picks: [lesser[i], lesser[j]]))
                    if results.count >= 3 { return results }
                }
                if lesser.count > j + 1 {
                    for k in (j + 1)..<lesser.count {
                        let v3 = v2 + DraftEngine.pickValue(lesser[k].pickNumber)
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
                Text("Sent \(formatMillions(entry.sentValue))")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Color.accentBlue)
                Text("Got \(formatMillions(entry.receivedValue))")
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
        let values = TradeEngine.evaluateTradeValue(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks
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

        let accepted = TradeEngine.aiWouldAccept(
            proposal: proposal,
            aiTeam: partner,
            allPlayers: allPlayers,
            allPicks: allPicks
        )

        if accepted {
            // Capture history before mutating roster
            recordCompletedTrade(
                proposal: proposal,
                counterpartyAbbr: partner.abbreviation,
                userIsOfferingTeam: true
            )
            TradeEngine.executeTrade(
                proposal: proposal,
                allPlayers: allPlayers,
                allPicks: allPicks,
                modelContext: modelContext
            )
            clearSelections()
            selectedPartner = nil
            loadData()
            tradeResultMessage = "\(partner.abbreviation) accepted the trade!"
            resultIsSuccess = true
        } else {
            tradeResultMessage = "\(partner.abbreviation) declined the trade."
            resultIsSuccess = false
        }

        showResultAlert = true
    }

    private func acceptOffer(_ offer: TradeProposal) {
        let teamName = allTeams.first(where: { $0.id == offer.offeringTeamID })?.abbreviation ?? "AI"
        // Record before executing so lookups still resolve
        recordCompletedTrade(
            proposal: offer,
            counterpartyAbbr: teamName,
            userIsOfferingTeam: false
        )
        TradeEngine.executeTrade(
            proposal: offer,
            allPlayers: allPlayers,
            allPicks: allPicks,
            modelContext: modelContext
        )
        incomingOffers.removeAll { $0.id == offer.id }
        loadData()
        tradeResultMessage = "Trade with \(teamName) completed!"
        resultIsSuccess = true
        showResultAlert = true
    }

    private func declineOffer(_ offer: TradeProposal) {
        incomingOffers.removeAll { $0.id == offer.id }
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

        // Generate incoming offers if we have none and trading is open
        if incomingOffers.isEmpty,
           let myTeam = playerTeam,
           career.currentPhase == .regularSeason || career.currentPhase == .tradeDeadline {
            incomingOffers = TradeEngine.generateAITradeOffers(
                forTeam: myTeam,
                allTeams: allTeams,
                allPlayers: allPlayers,
                allPicks: allPicks
            )
        }
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
        return TradeEngine.evaluateTradeValue(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks
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
            let v = ContractEngine.estimateMarketValue(player: p)
            yourLines.append(BreakdownLine(
                label: p.fullName,
                detail: "\(p.position.rawValue) · \(p.overall) OVR · Age \(p.age)",
                value: v
            ))
        }
        for id in mySelectedPicks {
            guard let pick = pickLookup[id] else { continue }
            let v = DraftEngine.pickValue(pick.pickNumber)
            yourLines.append(BreakdownLine(
                label: pickLabelShort(pick),
                detail: "Pick chart value",
                value: v
            ))
        }

        var theirLines: [BreakdownLine] = []
        for id in theirSelectedPlayers {
            guard let p = playerLookup[id] else { continue }
            let v = ContractEngine.estimateMarketValue(player: p)
            theirLines.append(BreakdownLine(
                label: p.fullName,
                detail: "\(p.position.rawValue) · \(p.overall) OVR · Age \(p.age)",
                value: v
            ))
        }
        for id in theirSelectedPicks {
            guard let pick = pickLookup[id] else { continue }
            let v = DraftEngine.pickValue(pick.pickNumber)
            theirLines.append(BreakdownLine(
                label: pickLabelShort(pick),
                detail: "Pick chart value",
                value: v
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
