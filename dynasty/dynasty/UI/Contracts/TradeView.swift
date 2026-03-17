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

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if career.currentPhase == .tradeDeadline ||
               career.currentPhase == .regularSeason {
                ScrollView {
                    VStack(spacing: 24) {
                        proposeSectionCard
                        incomingSectionCard
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
                accentColor: Color.accentBlue
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
                accentColor: Color.accentGold
            )
        }
    }

    private func assetColumn(
        title: String,
        players: [Player],
        picks: [DraftPick],
        selectedPlayers: Binding<Set<UUID>>,
        selectedPicks: Binding<Set<UUID>>,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            // Players
            ForEach(players) { player in
                assetToggleRow(
                    label: player.fullName,
                    sublabel: "\(player.position.rawValue) · \(player.overall) OVR",
                    valueLabel: formatMillions(ContractEngine.estimateMarketValue(player: player)),
                    isSelected: selectedPlayers.wrappedValue.contains(player.id),
                    accentColor: accentColor
                ) {
                    toggle(id: player.id, in: selectedPlayers)
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
        TradeEngine.executeTrade(
            proposal: offer,
            allPlayers: allPlayers,
            allPicks: allPicks,
            modelContext: modelContext
        )
        incomingOffers.removeAll { $0.id == offer.id }
        loadData()
        let teamName = allTeams.first(where: { $0.id == offer.offeringTeamID })?.abbreviation ?? "AI"
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

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }
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
