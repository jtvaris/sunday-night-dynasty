import SwiftUI

struct ContractNegotiationView: View {

    let player: Player
    let negotiationType: NegotiationType
    let teamCapSpace: Int
    var onDealCompleted: ((NegotiationOffer) -> Void)?

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var messages: [NegotiationMessage] = []
    @State private var currentOffer: NegotiationOffer = NegotiationOffer(
        years: 2, annualSalary: 5000, signingBonus: 0, guaranteedPercent: 30, noTradeClause: false
    )
    @State private var latestAgentOffer: NegotiationOffer?
    @State private var outcome: NegotiationOutcome = .pending
    @State private var roundNumber: Int = 0
    @State private var scrollTarget: UUID?

    // Offer builder state
    @State private var offerYears: Int = 2
    @State private var offerSalary: Int = 5000
    @State private var offerBonus: Int = 0
    @State private var offerGuaranteed: Int = 30

    private let salaryStep = 500
    private let bonusStep = 500
    private let guaranteedStep = 5
    private let minSalary = 500
    private let maxSalary = 75_000

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                playerHeader
                chatArea
                if isNegotiationActive {
                    offerBuilder
                }
            }
        }
        .navigationTitle("Contract Negotiation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .onAppear { startNegotiation() }
    }

    private var isNegotiationActive: Bool {
        if case .pending = outcome { return true }
        return false
    }

    // MARK: - Player Header

    private var playerHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.fullName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                HStack(spacing: 8) {
                    Text(player.position.rawValue)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(positionSideColor, in: RoundedRectangle(cornerRadius: 4))
                    Text("Age \(player.age)")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Text("\(formatMillions(player.annualSalary))/yr")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                    if player.contractYearsRemaining > 0 {
                        Text("\(player.contractYearsRemaining)yr left")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(player.overall)")
                    .font(.system(size: 36, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(player.overall))
                Text("OVR")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(16)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)
        }
    }

    // MARK: - Chat Area

    private var chatArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        chatBubble(for: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: scrollTarget) { _, target in
                if let target {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Chat Bubble

    @ViewBuilder
    private func chatBubble(for message: NegotiationMessage) -> some View {
        switch message.sender {
        case .agent:
            agentBubble(message)
        case .gm:
            gmBubble(message)
        case .system:
            systemBubble(message)
        }
    }

    private func agentBubble(_ message: NegotiationMessage) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Agent")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)

                if let offer = message.offer {
                    offerCard(offer, isAgent: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
            )
            .frame(maxWidth: 500, alignment: .leading)

            Spacer(minLength: 60)
        }
    }

    private func gmBubble(_ message: NegotiationMessage) -> some View {
        HStack(alignment: .top) {
            Spacer(minLength: 60)

            VStack(alignment: .trailing, spacing: 6) {
                Text("You")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentGold.opacity(0.7))

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.trailing)

                if let offer = message.offer {
                    offerCard(offer, isAgent: false)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentGold.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentGold.opacity(0.25), lineWidth: 1)
                    )
            )
            .frame(maxWidth: 500, alignment: .trailing)
        }
    }

    private func systemBubble(_ message: NegotiationMessage) -> some View {
        Text(message.text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    // MARK: - Offer Card (inside bubble)

    private func offerCard(_ offer: NegotiationOffer, isAgent: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                offerStat("Years", "\(offer.years)")
                offerStat("Salary", formatMillions(offer.annualSalary))
                offerStat("Bonus", formatMillions(offer.signingBonus))
                offerStat("Gtd", "\(offer.guaranteedPercent)%")
            }

            HStack(spacing: 16) {
                Text("Total: \(formatMillions(offer.totalValue))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(isAgent ? Color.textPrimary : Color.accentGold)
                Text("Cap Hit: \(formatMillions(offer.annualCapHit))/yr")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundPrimary.opacity(0.5))
        )
    }

    private func offerStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Offer Builder

    private var offerBuilder: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)

            VStack(spacing: 10) {
                // Years
                builderRow(label: "Years", value: "\(offerYears) yr\(offerYears == 1 ? "" : "s")") {
                    stepperButton(systemImage: "minus") { if offerYears > 1 { offerYears -= 1 } }
                        .disabled(offerYears <= 1)
                } plus: {
                    stepperButton(systemImage: "plus") { if offerYears < 6 { offerYears += 1 } }
                        .disabled(offerYears >= 6)
                }

                // Salary
                builderRow(label: "Salary", value: formatMillions(offerSalary), valueColor: .accentGold) {
                    stepperButton(systemImage: "minus") {
                        if offerSalary > minSalary { offerSalary -= salaryStep }
                    }
                    .disabled(offerSalary <= minSalary)
                } plus: {
                    stepperButton(systemImage: "plus") {
                        if offerSalary < maxSalary { offerSalary += salaryStep }
                    }
                    .disabled(offerSalary >= maxSalary)
                }

                // Signing bonus
                builderRow(label: "Bonus", value: formatMillions(offerBonus)) {
                    stepperButton(systemImage: "minus") {
                        if offerBonus >= bonusStep { offerBonus -= bonusStep }
                    }
                    .disabled(offerBonus <= 0)
                } plus: {
                    stepperButton(systemImage: "plus") {
                        offerBonus += bonusStep
                    }
                }

                // Guaranteed %
                builderRow(label: "Guaranteed", value: "\(offerGuaranteed)%") {
                    stepperButton(systemImage: "minus") {
                        if offerGuaranteed > 0 { offerGuaranteed -= guaranteedStep }
                    }
                    .disabled(offerGuaranteed <= 0)
                } plus: {
                    stepperButton(systemImage: "plus") {
                        if offerGuaranteed < 100 { offerGuaranteed += guaranteedStep }
                    }
                    .disabled(offerGuaranteed >= 100)
                }
            }

            // Cap impact preview
            capPreview

            // Action buttons
            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.backgroundSecondary)
    }

    private func builderRow(
        label: String,
        value: String,
        valueColor: Color = .textPrimary,
        @ViewBuilder minus: () -> some View,
        @ViewBuilder plus: () -> some View
    ) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .frame(width: 90, alignment: .leading)

            Spacer()

            HStack(spacing: 12) {
                minus()
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(valueColor)
                    .frame(minWidth: 64, alignment: .center)
                plus()
            }
        }
    }

    private var capPreview: some View {
        let capHit = offerYears > 0 ? offerSalary + offerBonus / offerYears : offerSalary
        let totalValue = offerSalary * offerYears + offerBonus

        return HStack {
            Text("Cap Hit: \(formatMillions(capHit))/yr")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.accentGold)
            Spacer()
            Text("Total: \(formatMillions(totalValue))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 4)
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Counter Offer
            Button {
                submitCounterOffer()
            } label: {
                Text("Counter Offer")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentGold)
                    )
            }

            // Accept (only when agent has made an offer)
            if latestAgentOffer != nil {
                Button {
                    acceptAgentOffer()
                } label: {
                    Text("Accept")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.success)
                        )
                }
            }

            // Walk away
            Button {
                walkAway()
            } label: {
                Text("Walk Away")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.danger.opacity(0.5), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Actions

    private func startNegotiation() {
        let result = ContractNegotiationEngine.generateOpeningDemand(
            player: player,
            negotiationType: negotiationType,
            teamCapSpace: teamCapSpace
        )

        let agentMessage = NegotiationMessage(
            sender: .agent,
            text: result.message,
            offer: result.offer
        )
        messages.append(agentMessage)
        latestAgentOffer = result.offer
        scrollTarget = agentMessage.id

        // Pre-fill GM offer slightly below agent's ask
        let agentOffer = result.offer
        offerYears = agentOffer.years
        offerSalary = roundToStep(Int(Double(agentOffer.annualSalary) * 0.85))
        offerBonus = roundToStep(Int(Double(agentOffer.signingBonus) * 0.75))
        offerGuaranteed = max(0, agentOffer.guaranteedPercent - 10)
    }

    private func submitCounterOffer() {
        roundNumber += 1

        let gmOffer = NegotiationOffer(
            years: offerYears,
            annualSalary: offerSalary,
            signingBonus: offerBonus,
            guaranteedPercent: offerGuaranteed,
            noTradeClause: false
        )

        // Add GM message
        let gmMessage = NegotiationMessage(
            sender: .gm,
            text: roundNumber == 1
                ? "Here's our opening offer for \(player.firstName)."
                : "We've adjusted the numbers. Take a look.",
            offer: gmOffer
        )
        messages.append(gmMessage)
        scrollTarget = gmMessage.id

        guard let agentAsk = latestAgentOffer else { return }

        // Evaluate
        let result = ContractNegotiationEngine.evaluateCounterOffer(
            gmOffer: gmOffer,
            player: player,
            previousAgentOffer: agentAsk,
            roundNumber: roundNumber,
            negotiationType: negotiationType
        )

        // Add agent response after a brief delay for readability
        let agentMessage = NegotiationMessage(
            sender: .agent,
            text: result.message,
            offer: result.counterOffer
        )
        messages.append(agentMessage)

        if let counter = result.counterOffer {
            latestAgentOffer = counter
        }

        outcome = result.outcome
        scrollTarget = agentMessage.id

        // Handle terminal states
        switch result.outcome {
        case .dealReached(let finalOffer):
            let sysMsg = NegotiationMessage(
                sender: .system,
                text: "Deal reached! \(player.fullName) signed for \(formatMillions(finalOffer.totalValue)) over \(finalOffer.years) years.",
                offer: nil
            )
            messages.append(sysMsg)
            scrollTarget = sysMsg.id
            onDealCompleted?(finalOffer)

        case .playerWalked:
            let sysMsg = NegotiationMessage(
                sender: .system,
                text: "\(player.fullName)'s agent has ended negotiations.",
                offer: nil
            )
            messages.append(sysMsg)
            scrollTarget = sysMsg.id

        default:
            break
        }
    }

    private func acceptAgentOffer() {
        guard let agentOffer = latestAgentOffer else { return }

        let gmMsg = NegotiationMessage(
            sender: .gm,
            text: "We accept your terms. Let's get this done.",
            offer: agentOffer
        )
        messages.append(gmMsg)

        let sysMsg = NegotiationMessage(
            sender: .system,
            text: "Deal reached! \(player.fullName) signed for \(formatMillions(agentOffer.totalValue)) over \(agentOffer.years) years.",
            offer: nil
        )
        messages.append(sysMsg)

        outcome = .dealReached(agentOffer)
        scrollTarget = sysMsg.id
        onDealCompleted?(agentOffer)
    }

    private func walkAway() {
        let gmMsg = NegotiationMessage(
            sender: .gm,
            text: "We're going to pass. Thank you for your time.",
            offer: nil
        )
        messages.append(gmMsg)

        let sysMsg = NegotiationMessage(
            sender: .system,
            text: "You ended negotiations with \(player.fullName)'s agent.",
            offer: nil
        )
        messages.append(sysMsg)

        outcome = .walkedAway
        scrollTarget = sysMsg.id

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }

    // MARK: - Helpers

    private var positionSideColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func stepperButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 28, height: 28)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func roundToStep(_ value: Int) -> Int {
        let rounded = (value / salaryStep) * salaryStep
        return max(minSalary, min(maxSalary, rounded))
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        }
        return "$\(thousands)K"
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ContractNegotiationView(
            player: Player(
                firstName: "Justin",
                lastName: "Jefferson",
                position: .WR,
                age: 25,
                yearsPro: 4,
                physical: PhysicalAttributes(
                    speed: 92, acceleration: 90, strength: 65,
                    agility: 88, stamina: 82, durability: 80
                ),
                mental: MentalAttributes(
                    awareness: 88, decisionMaking: 85, clutch: 82,
                    workEthic: 90, coachability: 85, leadership: 78
                ),
                positionAttributes: .wideReceiver(WRAttributes(
                    routeRunning: 94, catching: 92, release: 88,
                    spectacularCatch: 85
                )),
                personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .money),
                contractYearsRemaining: 1,
                annualSalary: 18000
            ),
            negotiationType: .extend,
            teamCapSpace: 45_000
        )
    }
}
