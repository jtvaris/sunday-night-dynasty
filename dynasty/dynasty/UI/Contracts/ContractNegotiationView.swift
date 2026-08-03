import SwiftUI
import SwiftData

// MARK: - Contract Negotiation (Contact Agent wave)
//
// A contract talk is a CONVERSATION, so this screen is a chat and nothing else.
//
// What changed and why:
//
// 1. ONE entry, everywhere. `ContactAgentEntry` is the only door in, and it
//    never reveals willingness — a hidden "Extend Contract" button used to tell
//    the user the answer before he asked the question. Everyone can be called.
//
// 2. The agent speaks first, in character. A client who will not talk says so
//    HERE, with a reason ("My client has no interest in negotiating with this
//    team right now — he hasn't taken a meaningful snap all year"), instead of
//    the flat system banner the freeze-out used to print. The thread stays
//    readable, and next league year opens a clean one.
//
// 3. Counters carry their number in the sentence. The offer composer is still
//    structured — years, salary, bonus, guarantees, clauses — but every reply
//    renders as speech, and the money in the speech is the money on the card
//    below it, because both come from the same engine offer.
//
// 4. Nothing auto-exits. Signing appends the agent's closing line, then an
//    inline signed card, and leaves a Done button. The user decides when the
//    conversation is over — the old sheet dismissed itself on the frame the
//    deal closed, so the line the agent said at the handshake was never read.
//
// 5. The tone of the close is written to the man. A smooth close at his number
//    is a small morale lift and a nudge toward `.driven`; a grinding close well
//    under his ask costs a few points of morale and leaves a "wants more" note
//    that the roster keeps showing.
//
// OWNERSHIP: this file writes copy and persists the transcript. Every number in
// it comes out of `ContractNegotiationEngine` — the opening demand, the
// counters, the accept/walk/break-off verdicts. Nothing here prices a contract.

struct ContractNegotiationView: View {

    let player: Player
    let negotiationType: NegotiationType
    let teamCapSpace: Int
    var onDealCompleted: ((NegotiationOffer) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    /// The persisted conversation. `nil` only before the first load pass.
    @State private var thread: NegotiationThread?
    @State private var season: Int = 0
    @State private var currentWeek: Int = 0
    @State private var team: Team?
    @State private var career: Career?
    /// `DraftReputation.ownerTrust` — a separate row, so it is fetched
    /// separately and defaults to the neutral 70 the row is created with.
    @State private var ownerTrust: Int = 70
    @State private var scrollTarget: UUID?
    @State private var showYearlyBreakdown = false
    @State private var didLoad = false

    // Offer builder state
    @State private var offerYears: Int = 2
    @State private var offerSalary: Int = 5000
    @State private var offerBonus: Int = 0
    @State private var offerGuaranteed: Int = 30

    // Incentive builder state (TODO §5.5).
    //
    // `incentiveMenu` holds the candidate clauses — position-appropriate, priced
    // off the agent's opening ask — and `enabledIncentiveIDs` says which of them
    // are actually on the offer. Splitting them keeps a clause's negotiated
    // threshold intact while the GM toggles it off and back on.
    @State private var incentiveMenu: [ContractIncentive] = []
    @State private var enabledIncentiveIDs: Set<String> = []
    @State private var showIncentives = false

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
                } else {
                    closingBar
                }
            }
        }
        .navigationTitle("Contact Agent")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .task { loadIfNeeded() }
    }

    /// Whether the composer stays on screen.
    ///
    /// `acceptsOffers`, not `isOpen`: a refusal keeps the composer, because a
    /// front office is always allowed to table another offer. What that costs is
    /// the engine's business (`ContractNegotiationEngine`'s pestering path) and
    /// the agent's to say out loud — it is not something this screen prevents by
    /// taking the buttons away.
    private var isNegotiationActive: Bool { thread?.status.acceptsOffers ?? false }

    /// The refusing thread, if this conversation is one. Drives the stance
    /// banner over the composer.
    private var refusalReason: AgentRefusalReason? {
        guard thread?.status == .refused else { return nil }
        return thread?.refusalReason
    }

    private var pesterCount: Int { thread?.pesterCount ?? 0 }

    // MARK: - Agent Identity

    /// Deterministic agent persona for this player (derived from player.id).
    private var agentPersona: AgentPersona { AgentPersona.forPlayer(id: player.id) }

    /// Deterministic agent name for this player.
    private var agentName: String { AgentPersona.agentName(for: player.id) }

    /// The character the persona speaks in.
    private var agentVoice: AgentVoice { agentPersona.voice(for: player.id) }

    /// Rounds the agent has left before his patience runs out. Presentation of
    /// the engine's own `ContractDemand.maxRounds` — a lowball that draws the
    /// insulted line burns one of these, which is what "the ask hardens" looks
    /// like from the GM's chair.
    private var roundsRemaining: Int {
        max(0, liveDemand.maxRounds - (thread?.round ?? 0))
    }

    /// The situation-driven character of this talk, if it has one — the engine's
    /// verdict, rendered as a chip. The chat never derives a stance of its own.
    private var stance: NegotiationStance? { liveDemand.stance }

    // **What this client is actually negotiating for** (#86) — the axis every
    // high-traffic line in the chat is written on — is deliberately NOT a
    // property here. `AgentDesire.primary` is called at each message site with
    // the demand THAT site is speaking about (the opening demand, the round's
    // graded demand, the demand the deal closed against), and it decodes
    // `Player.injuryHistory` from JSON, which is cheap once per message and
    // wasteful once per SwiftUI body pass.
    //
    // It is also not shown as a chip anywhere, on purpose: the user is meant to
    // work out what a man wants from how his agent talks, and a label over the
    // conversation would answer the question the conversation is asking.

    /// The line picker for one exchange.
    ///
    /// Seeded on the thread, the round and the site, so the same conversation
    /// says the same words on every re-open — and carrying the thread's
    /// `lastLineIndex` so it never says the same one twice running.
    private func selector(for thread: NegotiationThread, round: Int) -> DialogueSelector {
        DialogueSelector(threadID: thread.id, round: round, lastIndex: thread.lastLineIndex)
    }

    // MARK: - Economy Inputs
    //
    // Everything below is read from the world and handed to the engine. The
    // chat computes no money: it supplies the league's cap, the club's season
    // and the user's standing, and the demand model prices the man.

    /// The league's ACTUAL cap. Defaulting to 265 000 — which is what every
    /// call from this screen used to do — meant that by season 10 the agent
    /// quoted season-1 money while the free-agency screen and the AI market
    /// quoted the real number.
    private var salaryCap: Int { team?.salaryCap ?? ContractEngine.openingSalaryCap }

    private var capMode: CapMode { career?.capMode ?? .simple }

    /// What the league knows about this front office. Previously never
    /// constructed at all, so `gmAdjustment` was identically zero on every
    /// shipped negotiation and the whole five-line breakdown — plus the
    /// `NegotiationLedger` feeding it — was write-only.
    private var gmStanding: GMStanding {
        guard let career else { return .neutral }
        return GMStanding.from(career: career, ownerTrust: ownerTrust)
    }

    /// The club and the season, as the demand model reads them.
    private var negotiationSituation: NegotiationSituation {
        // "Contender" is `ContractNegotiationEngine.isContender` and nothing
        // else. It used to be an inline expression here, which meant this screen
        // owned a second definition of the word that the ring-chaser's exit
        // condition and the legacy veteran's discount would have had to agree
        // with by coincidence.
        ContractNegotiationEngine.situation(
            for: player,
            season: season,
            teamWins: team?.wins ?? 0,
            teamLosses: team?.losses ?? 0,
            weeksPlayed: currentWeek
        )
    }

    /// The agent's standing demand, priced for THIS club in THIS season with
    /// the lowballs this thread has already absorbed.
    private var liveDemand: ContractDemand {
        ContractNegotiationEngine.demand(
            player: player,
            negotiationType: negotiationType,
            salaryCap: salaryCap,
            situation: negotiationSituation,
            standing: gmStanding,
            insultCount: thread?.insultCount ?? 0
        )
    }

    // MARK: - Cap Gate

    /// The offer as the composer currently has it.
    private var builderOffer: NegotiationOffer {
        NegotiationOffer(
            years: offerYears,
            annualSalary: offerSalary,
            signingBonus: offerBonus,
            guaranteedPercent: offerGuaranteed,
            noTradeClause: false,
            incentives: activeIncentives
        )
    }

    /// What signing THIS deal would cost the club against the cap, net of what
    /// it is already carrying for the man. An extension replaces a salary that
    /// is already on the books; a free agent is a new charge in full.
    private func capCharge(for offer: NegotiationOffer) -> Int {
        negotiationType == .extend
            ? offer.annualCapHit - player.annualSalary
            : offer.annualCapHit
    }

    /// Whether the club can actually fit a deal. **This is the cap gate the
    /// chat never had** — `teamCapSpace` used to be threaded through four call
    /// sites into an engine parameter whose body ignored it, so a club with
    /// $2M of room could sign a $75M/yr quarterback in the composer.
    private func exceedsCap(_ offer: NegotiationOffer) -> Bool {
        guard capMode != .sandbox else { return false }
        return capCharge(for: offer) > teamCapSpace
    }

    private var builderExceedsCap: Bool { exceedsCap(builderOffer) }

    private var pendingOfferExceedsCap: Bool {
        guard let snapshot = thread?.pendingAgentOffer else { return false }
        return exceedsCap(snapshot.offer)
    }

    /// The bonus ceiling. Unbounded before, and because only `annualSalary` was
    /// ever written to the player, a $500K salary with a $200M bonus read as a
    /// $50.5M/yr offer to the agent and as the veteran minimum to the league.
    /// Half the deal's value is the outer edge of a real signing bonus.
    private var maxBonus: Int { max(bonusStep, offerSalary * max(1, offerYears)) }

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
                // Agent identity: who he is, how he bargains, how he talks.
                HStack(spacing: 6) {
                    Image(systemName: agentPersona.symbolName)
                        .font(.system(size: 10))
                        .foregroundStyle(personaColor)
                    Text("Agent: \(agentName)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Text(agentPersona.styleLabel)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(personaColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(personaColor.opacity(0.12), in: Capsule())
                    Text(agentVoice.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.backgroundTertiary, in: Capsule())
                }
                // The stance chip. Only shown when the engine says there IS one
                // — a normal negotiation is the overwhelming majority and must
                // not be dressed up as a story it isn't.
                if let stance {
                    Text(stance.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentBlue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentBlue.opacity(0.12), in: Capsule())
                }

                if refusalReason != nil {
                    // Patience is meaningless when he is not negotiating; what
                    // matters is how many times you have asked anyway.
                    Text(pesterCount == 0
                         ? agentPersona.styleDescription
                         : "\(agentPersona.styleDescription)  ·  \(pesterCount) offer\(pesterCount == 1 ? "" : "s") tabled since he declined")
                        .font(.caption2)
                        .foregroundStyle(pesterCount >= 2 ? Color.danger : Color.textTertiary)
                } else if isNegotiationActive {
                    Text("\(agentPersona.styleDescription)  ·  \(roundsRemaining) round\(roundsRemaining == 1 ? "" : "s") of patience left")
                        .font(.caption2)
                        .foregroundStyle(roundsRemaining <= 1 ? Color.warning : Color.textTertiary)
                } else {
                    Text(agentPersona.styleDescription)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
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
                    ForEach(thread?.messages ?? []) { message in
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
    private func chatBubble(for message: NegotiationThreadMessage) -> some View {
        if message.isSignedCard {
            signedCard(message)
        } else {
            switch message.sender {
            case .agent:  agentBubble(message)
            case .you:    gmBubble(message)
            case .system: systemBubble(message)
            }
        }
    }

    private func agentBubble(_ message: NegotiationThreadMessage) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(thread?.agentName ?? agentName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textTertiary)
                    if let tone = message.tone, let chip = toneChip(tone) {
                        Text(chip.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(chip.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(chip.color.opacity(0.14), in: Capsule())
                    }
                }

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let snapshot = message.offer {
                    offerCard(snapshot.offer, isAgent: true)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.backgroundSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                message.tone == .insulted ? Color.danger.opacity(0.45) : Color.surfaceBorder,
                                lineWidth: 1
                            )
                    )
            )
            .frame(maxWidth: 500, alignment: .leading)

            Spacer(minLength: 60)
        }
    }

    private func gmBubble(_ message: NegotiationThreadMessage) -> some View {
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
                    .fixedSize(horizontal: false, vertical: true)

                if let snapshot = message.offer {
                    offerCard(snapshot.offer, isAgent: false)
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

    private func systemBubble(_ message: NegotiationThreadMessage) -> some View {
        Text(message.text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
    }

    /// The receipt, rendered INSIDE the thread rather than as a screen the sheet
    /// jumps to — the conversation is the record, so the signature belongs in it.
    private func signedCard(_ message: NegotiationThreadMessage) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.success)
                Text("Contract Signed")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.success)
            }

            Text(message.text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let snapshot = message.offer {
                offerCard(snapshot.offer, isAgent: false)
            }
        }
        .padding(14)
        .frame(maxWidth: 500)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.success.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.success.opacity(0.35), lineWidth: 1)
                )
        )
        .frame(maxWidth: .infinity)
    }

    /// The badge on an agent line that names the tone it was said in. Only the
    /// two tones a GM needs to READ are chipped — the rest is in the wording.
    private func toneChip(_ tone: AgentToneKey) -> (label: String, color: Color)? {
        switch tone {
        case .insulted: return ("Ask hardened", .danger)
        case .refusing: return ("Refusing", .warning)
        case .eager:    return ("Ready to sign", .success)
        default:        return nil
        }
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

            // §5.5: clauses ride under the money so both bubbles show the same
            // deal the engine graded.
            if !offer.incentives.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(offer.incentives) { incentive in
                        HStack(spacing: 4) {
                            Image(systemName: "target")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.accentGold)
                            Text(incentive.summary)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    Text("Max \(formatMillions(offer.maxValue))")
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Closing Bar

    /// What replaces the composer once the conversation is over. Deliberately a
    /// button and not an automatic dismiss: whether the talk ended in a
    /// signature, a walk-out or a door closed in your face, the last thing the
    /// agent said is worth reading before the screen goes away.
    private var closingBar: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)

            if let note = thread?.lingeringNote {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.bubble.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.warning)
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            // `.refused` is deliberately absent: that thread keeps its composer
            // now, so it never reaches this bar. The only camp that genuinely
            // will not hear from you again this league year is the one that hung
            // up on a lowball.
            if thread?.status == .brokenOff {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)
                    Text("You can reach out again next league year.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 4)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentGold)
                    )
            }
            .accessibilityHint("Closes the conversation. The thread stays saved.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Offer Builder

    private var offerBuilder: some View {
        VStack(spacing: 12) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)

            // The stance banner. Shown ABOVE the composer rather than instead of
            // it: the user can still make the offer, and should — he just gets
            // to make it knowing what he is doing and what it will cost.
            refusalBanner

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
                        offerBonus = min(maxBonus, offerBonus + bonusStep)
                    }
                    .disabled(offerBonus >= maxBonus)
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

            // Performance clauses (TODO §5.5)
            incentiveSection

            // Yearly breakdown toggle
            yearlyBreakdownSection

            // Action buttons
            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.backgroundSecondary)
    }

    /// What his camp said, and the one thing that would change it.
    ///
    /// The exit condition is the whole reason this is a banner and not a locked
    /// door: a refusal the user cannot read is a wall, and a refusal that names
    /// its own exit is a puzzle. `neverSignsAtAnyPrice` gets the sharper framing
    /// because it is the only stance where tabling a better number is not a long
    /// shot but a category error.
    @ViewBuilder
    private var refusalBanner: some View {
        if let reason = refusalReason {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: reason.neverSignsAtAnyPrice
                          ? "nosign" : "hand.raised.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(reason.neverSignsAtAnyPrice ? Color.danger : Color.warning)
                    Text(reason.badgeLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(reason.neverSignsAtAnyPrice ? Color.danger : Color.warning)
                    Spacer()
                }
                Text(reason.exitCondition)
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(reason.neverSignsAtAnyPrice
                     ? "You can still table an offer. He will not read it as one — the ask hardens, and he hears about every call."
                     : "You can still table an offer. It will not be graded on the money, the ask hardens, and he hears about every call.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill((reason.neverSignsAtAnyPrice ? Color.danger : Color.warning).opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(
                                (reason.neverSignsAtAnyPrice ? Color.danger : Color.warning).opacity(0.30),
                                lineWidth: 1
                            )
                    )
            )
        }
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
        let offer = builderOffer
        let charge = capCharge(for: offer)

        return VStack(spacing: 4) {
            HStack {
                Text("Cap Hit: \(formatMillions(offer.annualCapHit))/yr")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
                Spacer()
                Text("Total: \(formatMillions(offer.totalValue))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }

            if capMode != .sandbox {
                HStack(spacing: 6) {
                    Image(systemName: builderExceedsCap ? "exclamationmark.triangle.fill" : "checkmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(builderExceedsCap ? Color.danger : Color.textTertiary)
                    Text(builderExceedsCap
                         ? "Over the cap by \(formatMillions(charge - teamCapSpace)) — free up room before you offer this."
                         : "Charges \(formatMillions(max(0, charge))) of your \(formatMillions(teamCapSpace)) in room.")
                        .font(.system(size: 10))
                        .foregroundStyle(builderExceedsCap ? Color.danger : Color.textTertiary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Incentive Section (TODO §5.5)

    /// The clauses currently ON the offer, in menu order.
    private var activeIncentives: [ContractIncentive] {
        incentiveMenu.filter { enabledIncentiveIDs.contains($0.id) }
    }

    /// What this agent will actually count the active clauses for, across the
    /// whole deal — the number that decides whether they close the gap.
    private var creditedIncentiveValue: Int {
        ContractEngine.creditedIncentiveValue(
            activeIncentives,
            player: player,
            persona: agentPersona,
            years: max(1, offerYears)
        )
    }

    private var incentiveSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showIncentives.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Performance Incentives")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    if !activeIncentives.isEmpty {
                        Text("\(activeIncentives.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentGold, in: Capsule())
                    }
                    Spacer()
                    Image(systemName: showIncentives ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .accessibilityHint(showIncentives ? "Collapse performance incentives" : "Expand performance incentives")

            if showIncentives {
                VStack(spacing: 8) {
                    if incentiveMenu.isEmpty {
                        Text("No clauses available for this position.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(incentiveMenu) { incentive in
                            incentiveRow(incentive)
                        }
                        incentiveFooter
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundPrimary.opacity(0.5))
                )
            }
        }
    }

    private func incentiveRow(_ incentive: ContractIncentive) -> some View {
        let isOn = enabledIncentiveIDs.contains(incentive.id)
        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button {
                    toggleIncentive(incentive)
                } label: {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(isOn ? Color.accentGold : Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isOn ? "Remove \(incentive.category.displayName) clause" : "Add \(incentive.category.displayName) clause")

                Text(incentive.category.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? Color.textPrimary : Color.textTertiary)

                Spacer()

                Text(ContractIncentive.money(incentive.bonusK))
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(isOn ? Color.accentGold : Color.textTertiary)
            }

            // Threshold dial. A binary clause (playoff berth) has nothing to
            // tune, so it shows its odds instead of a stepper.
            HStack(spacing: 10) {
                Text(incentive.category.isBinary ? "Reach the postseason" : "Tier")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                if !incentive.category.isBinary {
                    stepperButton(systemImage: "minus") { adjustThreshold(incentive, direction: -1) }
                        .disabled(!isOn)
                    Text(incentive.category.format(incentive.threshold))
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(isOn ? Color.textPrimary : Color.textTertiary)
                        .frame(minWidth: 46)
                    stepperButton(systemImage: "plus") { adjustThreshold(incentive, direction: 1) }
                        .disabled(!isOn)
                }

                Text(likelihoodLabel(for: incentive))
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .frame(minWidth: 56, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
    }

    private var incentiveFooter: some View {
        VStack(spacing: 4) {
            Divider().overlay(Color.surfaceBorder.opacity(0.5))
            HStack {
                Text("Max \(formatMillions(ContractEngine.maxSeasonIncentiveValue(activeIncentives)))/yr")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(agentPersona.styleLabel) credits \(formatMillions(creditedIncentiveValue))")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(personaColor)
            }
            // Says the rule out loud so the cap treatment is never a surprise.
            Text("Charged to the cap only when earned, at season end.")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func likelihoodLabel(for incentive: ContractIncentive) -> String {
        let p = ContractEngine.incentiveLikelihood(incentive, player: player)
        return "\(Int((p * 100).rounded()))% odds"
    }

    /// Step size for one tap on the threshold dial — big enough to matter on a
    /// yardage tier, exact on a counting one.
    private func thresholdStep(for category: IncentiveCategory) -> Double {
        switch category {
        case .passYards, .rushYards, .recYards: return 50
        case .sacks:                            return 0.5
        default:                                return 1
        }
    }

    private func adjustThreshold(_ incentive: ContractIncentive, direction: Double) {
        guard let index = incentiveMenu.firstIndex(where: { $0.id == incentive.id }) else { return }
        let step = thresholdStep(for: incentive.category)
        // Floor at one step: a clause worth nothing to reach is not a clause.
        let next = max(step, incentiveMenu[index].threshold + direction * step)
        incentiveMenu[index] = ContractIncentive(
            category: incentiveMenu[index].category,
            threshold: next,
            bonusK: incentiveMenu[index].bonusK
        )
    }

    private func toggleIncentive(_ incentive: ContractIncentive) {
        if enabledIncentiveIDs.contains(incentive.id) {
            enabledIncentiveIDs.remove(incentive.id)
        } else {
            enabledIncentiveIDs.insert(incentive.id)
        }
    }

    /// Folds clauses the agent wrote himself into the builder, so the GM can see
    /// (and keep) what he is about to accept.
    private func absorbAgentIncentives(_ incentives: [ContractIncentive]) {
        for incentive in incentives {
            if let index = incentiveMenu.firstIndex(where: { $0.id == incentive.id }) {
                incentiveMenu[index] = incentive
            } else {
                incentiveMenu.append(incentive)
            }
            enabledIncentiveIDs.insert(incentive.id)
        }
        if !incentives.isEmpty { showIncentives = true }
    }

    // MARK: - Yearly Breakdown Section

    private var yearlyBreakdownSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showYearlyBreakdown.toggle()
                }
            } label: {
                HStack {
                    Text("Yearly Breakdown")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Image(systemName: showYearlyBreakdown ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .accessibilityHint(showYearlyBreakdown ? "Collapse yearly breakdown" : "Expand yearly breakdown")

            if showYearlyBreakdown {
                let previewOffer = NegotiationOffer(
                    years: offerYears,
                    annualSalary: offerSalary,
                    signingBonus: offerBonus,
                    guaranteedPercent: offerGuaranteed,
                    noTradeClause: false
                )
                let breakdown = previewOffer.yearlyBreakdown(playerAge: player.age)

                VStack(spacing: 0) {
                    // Header row
                    HStack(spacing: 0) {
                        Text("Year")
                            .frame(width: 40, alignment: .leading)
                        Text("Base")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Bonus")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Cap Hit")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("Dead Cap")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 9).weight(.bold))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)

                    Divider().overlay(Color.surfaceBorder.opacity(0.5))

                    // Year rows
                    ForEach(breakdown) { year in
                        HStack(spacing: 0) {
                            Text("Yr \(year.yearNumber)")
                                .frame(width: 40, alignment: .leading)
                            Text(formatMillions(year.baseSalary))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(formatMillions(year.proratedBonus))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(formatMillions(year.capHit))
                                .foregroundStyle(Color.accentGold)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Text(formatMillions(year.deadCapIfCut))
                                .foregroundStyle(Color.danger.opacity(0.8))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .font(.system(size: 10).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                    }

                    Divider().overlay(Color.surfaceBorder.opacity(0.5))

                    // Totals row
                    HStack(spacing: 0) {
                        Text("Total")
                            .frame(width: 40, alignment: .leading)
                        Text(formatMillions(breakdown.reduce(0) { $0 + $1.baseSalary }))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatMillions(breakdown.reduce(0) { $0 + $1.proratedBonus }))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(formatMillions(breakdown.reduce(0) { $0 + $1.capHit }))
                            .foregroundStyle(Color.accentGold)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text("")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .font(.system(size: 10).weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundPrimary.opacity(0.5))
                )
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Counter Offer
            Button {
                submitCounterOffer()
            } label: {
                Text("Send Offer")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(builderExceedsCap ? Color.textTertiary : Color.accentGold)
                    )
            }
            .disabled(builderExceedsCap)
            .accessibilityHint(
                builderExceedsCap
                    ? "Disabled: the offer exceeds your available cap space."
                    : (refusalReason != nil
                       ? "Tables this package at a camp that has declined to negotiate. The ask hardens and he loses morale."
                       : "Sends this package to the agent.")
            )

            // Accept (only when agent has made an offer)
            if thread?.pendingAgentOffer != nil {
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
                                .fill(pendingOfferExceedsCap ? Color.textTertiary : Color.success)
                        )
                }
                .disabled(pendingOfferExceedsCap)
                .accessibilityHint(pendingOfferExceedsCap
                                   ? "Disabled: the agent's number exceeds your available cap space."
                                   : "Signs the agent's standing offer.")
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

    // MARK: - Load

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        loadContext()

        // An existing conversation from THIS league year is resumed verbatim —
        // EXCEPT a refusal the man has since changed his mind about. A stance is
        // a mood, and freezing the verdict in the transcript meant a player
        // whose morale climbed from 44 to 70 in week 8 still read "Not talking"
        // for the rest of the season, with no lever he could pull.
        if let existing = NegotiationThreadStore.liveThread(for: player, season: season) {
            let stanceLifted = existing.status == .refused
                && !NegotiationLockRegistry.isLocked(player.id)
                && !liveDemand.isRefusing
            if !stanceLifted {
                thread = existing
                restoreBuilder(from: existing)
                scrollTarget = existing.messages.last?.id
                return
            }
            // The door opened. **Continue the conversation rather than wiping
            // it**: this is the payoff for meeting the exit condition the banner
            // named — you started the winter being told no, you started him /
                // won games / gave him time, and now the same man is at the same
            // table. Opening a blank thread here (which is what shipped) threw
            // away the refusal, every offer tabled at it, and the entire reason
            // this moment means anything.
            reopenAfterStanceLift(existing)
            return
        }

        openNewThread()
    }

    /// Turns a refused thread back into a live negotiation, in place.
    ///
    /// The pestering history is deliberately KEPT — `insultCount` rides forward,
    /// so a GM who spent the autumn tabling offers at a man who kept saying no
    /// opens this conversation against a ratcheted ask. That is the cost of not
    /// listening, and it is not forgiven just because he is listening now.
    private func reopenAfterStanceLift(_ existing: NegotiationThread) {
        var live = existing
        // `generateOpeningDemand` cannot be used here: it opens at
        // `insultCount: 0`, which would hand the ask back at market and quietly
        // refund every offer tabled at the closed door. The demand model is
        // asked directly, with the count this thread actually carries.
        let opening = ContractNegotiationEngine.demand(
            player: player,
            negotiationType: negotiationType,
            salaryCap: salaryCap,
            situation: negotiationSituation,
            standing: gmStanding,
            insultCount: existing.insultCount ?? 0
        )
        let ask = opening.openingOffer
        let sel = selector(for: live, round: live.round)

        live.status = .open
        live.refusalReasonRaw = nil
        live.openingAsk = NegotiationOfferSnapshot(ask)
        live.pendingAgentOffer = NegotiationOfferSnapshot(ask)
        live.append(NegotiationThreadMessage(
            sender: .system,
            text: "\(live.agentName) called back — \(player.firstName)'s camp is willing to talk now.",
            round: live.round
        ))
        live.append(NegotiationThreadMessage(
            sender: .agent,
            text: openerText(demand: opening, ask: ask, sel: sel, isReopen: true),
            offer: NegotiationOfferSnapshot(ask),
            round: live.round,
            tone: opening.personaTone
        ))

        primeComposer(from: ask)
        commit(live, sel: sel)
    }

    /// Season, week, team and the user's standing — everything the demand model
    /// reads about the world, fetched once.
    private func loadContext() {
        guard let careerID = player.careerID else { return }
        if let found = (try? modelContext.fetch(FetchDescriptor<Career>()))?
            .first(where: { $0.id == careerID }) {
            career = found
            season = found.currentSeason
            currentWeek = found.currentWeek
        }
        if let teamID = player.teamID {
            team = (try? modelContext.fetch(FetchDescriptor<Team>()))?
                .first(where: { $0.id == teamID && $0.careerID == careerID })
        }
        // Owner trust lives on its own row; the most recent one wins, and its
        // absence means the owner has never reacted to anything — which must
        // cost nothing, hence `GMStanding`'s neutral 70.
        if let reputation = (try? modelContext.fetch(FetchDescriptor<DraftReputation>()))?
            .filter({ $0.careerID == careerID })
            .max(by: { $0.seasonYear < $1.seasonYear }) {
            ownerTrust = reputation.ownerTrust
        }

        #if DEBUG
        logStanceCensus(careerID: careerID)
        #endif
    }

    #if DEBUG
    /// One line, once per app run, measuring the rarity budget against the live
    /// league instead of against the arithmetic in `ContractNegotiationEngine`'s
    /// doc comments. Grep for `STANCE-CENSUS`.
    ///
    /// Opening a Contact Agent thread is the cheapest honest trigger available:
    /// the fetch is already warm here, the numbers only mean anything mid-season
    /// (the record-driven stances all gate on `weeksPlayed >= 6`), and it costs
    /// a shipped build exactly nothing.
    private static var stanceCensusLogged = false

    private func logStanceCensus(careerID: UUID) {
        guard !Self.stanceCensusLogged else { return }
        Self.stanceCensusLogged = true
        let teams = ((try? modelContext.fetch(FetchDescriptor<Team>())) ?? [])
            .filter { $0.careerID == careerID }
        let players = ((try? modelContext.fetch(FetchDescriptor<Player>())) ?? [])
            .filter { $0.careerID == careerID && $0.teamID != nil }
        var records: [UUID: (wins: Int, losses: Int)] = [:]
        for t in teams { records[t.id] = (wins: t.wins, losses: t.losses) }
        let census = ContractNegotiationEngine.stanceCensus(
            players: players,
            recordByTeamID: records,
            season: season,
            weeksPlayed: currentWeek
        )
        print("STANCE-CENSUS season=\(season) week=\(currentWeek) \(census.summary)")
    }
    #endif

    private func openNewThread() {
        var newThread = NegotiationThread(
            playerID: player.id,
            playerName: player.fullName,
            agentName: agentName,
            persona: agentPersona,
            typeRaw: negotiationType == .extend ? "extend" : "freeAgent",
            season: season
        )
        let sel = selector(for: newThread, round: 0)

        // 1. A hardliner who was lowballed earlier this offseason. The freeze-out
        //    is a REFUSAL like any other now — he says it himself instead of the
        //    screen printing a banner at the user.
        if NegotiationLockRegistry.isLocked(player.id) {
            newThread.append(NegotiationThreadMessage(
                sender: .agent,
                text: AgentDialogue.brokenOffLine(voice: agentVoice, ctx: baseContext(), sel: sel),
                round: 0,
                tone: .refusing
            ))
            newThread.status = .brokenOff
            commit(newThread, sel: sel)
            return
        }

        // 2. A client with no interest in this building right now.
        //
        //    The verdict comes from `ContractNegotiationEngine.refusalVerdict`
        //    via the demand model, NOT from `AgentRefusalReason.evaluate`
        //    directly. Calling the stance model straight was what made the
        //    engine's own second door — a mercenary who will not sign up to lose
        //    for a front office he does not rate — unreachable, and with it the
        //    "a bad GM gets more refusals" half of the feature. The demand model
        //    also owns the extension-only rule (a free agent taking meetings is
        //    by definition at the table).
        let opening = ContractNegotiationEngine.generateOpeningDemand(
            player: player,
            negotiationType: negotiationType,
            salaryCap: salaryCap,
            situation: negotiationSituation,
            standing: gmStanding
        )

        if opening.demand.isRefusing, let reason = opening.demand.refusalReason {
            newThread.append(NegotiationThreadMessage(
                sender: .agent,
                text: AgentDialogue.refusalLine(
                    voice: agentVoice, reason: reason, ctx: baseContext(), sel: sel
                ),
                round: 0,
                tone: .refusing
            ))
            newThread.status = .refused
            newThread.refusalReasonRaw = reason.rawValue
            // The composer survives a refusal, so it has to be primed for one
            // too. Without this the dials sat at the $5M default and the user's
            // first act of pestering was a lowball he never meant to make.
            primeComposer(from: opening.demand.openingOffer)
            // The ring-chaser does not merely decline — he asks out, publicly.
            // News plus a flag the trade AI reads, and nothing more: see
            // `TradeRequestRegistry` for why a request must never move a player
            // on its own.
            if reason == .ringChasing { fileTradeRequest() }
            commit(newThread, sel: sel)
            return
        }

        // 3. He'll talk. The engine prices the ask; the agent says it out loud.
        let ask = opening.offer

        newThread.openingAsk = NegotiationOfferSnapshot(ask)
        newThread.pendingAgentOffer = NegotiationOfferSnapshot(ask)
        newThread.append(NegotiationThreadMessage(
            sender: .agent,
            text: openerText(demand: opening.demand, ask: ask, sel: sel),
            offer: NegotiationOfferSnapshot(ask),
            round: 0,
            // The engine's own opening frame, not a second copy of the rule.
            tone: opening.demand.personaTone
        ))

        primeComposer(from: ask)
        commit(newThread, sel: sel)
    }

    /// The agent's opening line: hello, what his client is after, and the number
    /// it takes.
    ///
    /// Two branches. A client who won a prove-it bet opens by saying so, because
    /// the user WROTE that bet last winter and the mechanic is worthless if he
    /// cannot see it pay out. A client whose refusal has just lifted opens with
    /// the reopener, which is the same desire and the same number said by a man
    /// who was saying no last month.
    private func openerText(
        demand: ContractDemand,
        ask: NegotiationOffer,
        sel: DialogueSelector,
        isReopen: Bool = false
    ) -> String {
        let ctx = context(ask: ask)
        if demand.stance == .provenBet, !isReopen {
            return AgentDialogue.provenBetLine(voice: agentVoice, ctx: ctx, sel: sel)
        }
        let want = AgentDesire.primary(player: player, demand: demand)
        if isReopen {
            return AgentDialogue.reopener(voice: agentVoice, desire: want, ctx: ctx, sel: sel)
        }
        return AgentDialogue.opener(
            voice: agentVoice,
            desire: want,
            isExtension: negotiationType == .extend,
            ctx: ctx,
            sel: sel
        )
    }

    /// Pre-fills the composer slightly below the ask and prices the clause menu.
    private func primeComposer(from ask: NegotiationOffer) {
        offerYears = ask.years
        offerSalary = roundToStep(Int(Double(ask.annualSalary) * 0.85))
        offerBonus = roundToStep(Int(Double(ask.signingBonus) * 0.75))
        offerGuaranteed = max(0, ask.guaranteedPercent - 10)

        // §5.5: the clause menu is priced off the agent's ASK, not off the
        // pre-filled lowball, so the bonuses stay stable while the GM works the
        // salary dial. Every clause starts switched OFF.
        incentiveMenu = ContractEngine.suggestedIncentives(
            player: player,
            annualSalaryK: ask.annualSalary
        )
        enabledIncentiveIDs = []
    }

    // MARK: - Trade Request (ring-chaser)

    /// Files a public trade request: a news story and a flag, through the
    /// machinery that already exists.
    ///
    /// **Minimal on purpose.** `HoldoutEngine.forceTrade` is the precedent for
    /// "a player actually leaves", and it is a much heavier thing — a valuation,
    /// a partner, an executed `TradeRecord`, dead money. A REQUEST is the step
    /// before that: the league finds out, the trade AI starts treating him as
    /// available (`TradeValueEngine.saleCandidates`), and the decision about
    /// what to do next stays with the user, who is the one being asked. No new
    /// trade mechanics, and nothing here moves a player.
    private func fileTradeRequest() {
        guard let career, let team else { return }
        guard TradeRequestRegistry.record(playerID: player.id, season: season) else { return }
        career.newsLog.append(NewsItem(
            headline: "\(player.fullName) asks \(team.abbreviation) for a trade",
            body: "\(player.fullName)'s agent went public today, saying the \(player.position.rawValue) has told the club he wants to play for a contender. "
                + "\"This isn't about money,\" the agent said. \"He's given this building his best football and watched it go nowhere. He wants a chance to win.\" "
                + "The \(team.abbreviation) front office has not commented.",
            category: .trade,
            week: currentWeek,
            season: season,
            relatedTeamID: team.id,
            relatedPlayerID: player.id,
            sentiment: .negative
        ))
        try? modelContext.save()
    }

    /// Puts the composer back where a resumed conversation left it.
    private func restoreBuilder(from existing: NegotiationThread) {
        // A refused thread has neither a standing counter nor an opening ask —
        // nobody ever put a number on the table. It still has a live composer,
        // so it is primed off the demand model instead of left on the defaults.
        guard let reference = existing.pendingAgentOffer ?? existing.openingAsk else {
            if existing.status == .refused {
                primeComposer(from: liveDemand.openingOffer)
            }
            return
        }
        offerYears = reference.years
        offerSalary = roundToStep(Int(Double(reference.annualSalary) * 0.9))
        offerBonus = roundToStep(Int(Double(reference.signingBonus) * 0.8))
        offerGuaranteed = max(0, reference.guaranteedPercent - 5)

        if let ask = existing.openingAsk {
            incentiveMenu = ContractEngine.suggestedIncentives(
                player: player,
                annualSalaryK: ask.annualSalary
            )
        }
        enabledIncentiveIDs = []
        absorbAgentIncentives(reference.incentives)
    }

    // MARK: - Actions

    private func submitCounterOffer() {
        guard var live = thread, live.status.acceptsOffers else { return }

        // A refusing camp has no standing offer to counter, so this path forks
        // before the normal one: there is nothing to grade the money against
        // because the money was never the question.
        if live.status == .refused {
            pester(&live)
            return
        }

        guard live.isOpen, let askSnapshot = live.pendingAgentOffer else { return }
        let agentAsk = askSnapshot.offer

        let gmOffer = builderOffer
        // The cap gate. The button is disabled here too, so this is the belt to
        // that braces — but a negotiation is the one screen where "the club
        // cannot fit this" has to be unconditional.
        guard !exceedsCap(gmOffer) else { return }

        live.round += 1
        let round = live.round
        let sel = selector(for: live, round: round)

        live.append(NegotiationThreadMessage(
            sender: .you,
            text: AgentDialogue.gmOfferLine(round: round, playerFirst: player.firstName, sel: sel),
            offer: NegotiationOfferSnapshot(gmOffer),
            round: round
        ))

        // The engine decides — the verdict, the counter AND the tone it is
        // spoken in. Everything below only chooses the words.
        let result = ContractNegotiationEngine.evaluateCounterOffer(
            gmOffer: gmOffer,
            player: player,
            previousAgentOffer: agentAsk,
            roundNumber: round,
            negotiationType: negotiationType,
            salaryCap: salaryCap,
            situation: negotiationSituation,
            standing: gmStanding,
            insultCount: live.insultCount ?? 0
        )
        // Persisted so the patience cost of a lowball survives the round: the
        // demand is a pure function, so a count that lives only in this call is
        // a count that is always zero.
        live.insultCount = result.insultCount

        // What the CLIENT wants, graded off the demand this round produced —
        // every line below weaves it, so the user can read the man out of the
        // way his agent argues.
        let want = AgentDesire.primary(player: player, demand: result.demand)

        switch result.outcome {
        case .dealReached(let finalOffer):
            close(&live, with: finalOffer, round: round, demand: result.demand, sel: sel)

        case .negotiationsBrokenOff:
            live.append(NegotiationThreadMessage(
                sender: .agent,
                text: AgentDialogue.brokenOffLine(
                    voice: agentVoice, ctx: context(ask: agentAsk, gmOffer: gmOffer), sel: sel
                ),
                round: round,
                tone: .insulted
            ))
            live.status = .brokenOff
            live.pendingAgentOffer = nil
            NegotiationLockRegistry.lock(player.id)
            live.append(NegotiationThreadMessage(
                sender: .system,
                text: "\(live.agentName) has cut off contract talks for \(player.fullName) until next league year.",
                round: round
            ))

        case .playerWalked:
            live.append(NegotiationThreadMessage(
                sender: .agent,
                text: AgentDialogue.walkAwayLine(
                    voice: agentVoice,
                    ctx: context(ask: agentAsk, gmOffer: gmOffer), sel: sel
                ),
                round: round,
                tone: .hardline
            ))
            live.status = .playerWalked
            live.pendingAgentOffer = nil

        case .pending, .walkedAway:
            guard let counter = result.counterOffer else {
                // The engine kept talks open without a counter — nothing to say
                // that the transcript does not already show.
                break
            }
            // The engine's verdict, not a second opinion computed here.
            let tone = result.tone
            let ctx = context(ask: counter, gmOffer: gmOffer, rounds: round)
            let text: String = {
                // The one case the engine answers with structure rather than
                // money: the deal is too long for the man's body.
                if result.isYearsPushback {
                    return AgentDialogue.yearsPushbackLine(
                        voice: agentVoice,
                        age: player.age,
                        requestedYears: gmOffer.years,
                        maxYears: ContractNegotiationEngine.maxContractYears(forAge: player.age),
                        ctx: ctx,
                        sel: sel
                    )
                }
                return AgentDialogue.counterLine(
                    voice: agentVoice, desire: want, tone: tone, ctx: ctx, sel: sel
                )
            }()

            live.append(NegotiationThreadMessage(
                sender: .agent,
                text: text,
                offer: NegotiationOfferSnapshot(counter),
                round: round,
                tone: tone
            ))
            live.pendingAgentOffer = NegotiationOfferSnapshot(counter)
            absorbAgentIncentives(counter.incentives)
        }

        commit(live, sel: sel)
    }

    // MARK: - Pestering

    /// An offer tabled at a client who has already declined to negotiate.
    ///
    /// **This is a full mechanic, not a rejection message.** The engine grades
    /// nothing (the money was never the question), and the four things that
    /// happen instead are the four things that would actually happen: the
    /// standing ask ratchets 6 % (`respond`'s pestering path calls
    /// `ContractDemand.escalated`), the ledger books it as an insult so it rides
    /// into every future negotiation in the league, the man himself loses
    /// `pesterMoraleCost` morale because his agent tells him about the call, and
    /// the agent's answer gets sharper each time.
    ///
    /// The cap gate still applies. An offer the club cannot fit is not a
    /// legitimate way to annoy somebody.
    private func pester(_ live: inout NegotiationThread) {
        let gmOffer = builderOffer
        guard !exceedsCap(gmOffer) else { return }

        let attempt = (live.pesterCount ?? 0) + 1
        live.pesterCount = attempt
        live.round += 1
        let round = live.round
        let sel = selector(for: live, round: round)

        live.append(NegotiationThreadMessage(
            sender: .you,
            text: AgentDialogue.gmOfferLine(round: round, playerFirst: player.firstName, sel: sel),
            offer: NegotiationOfferSnapshot(gmOffer),
            round: round
        ))

        // The engine owns the consequence; this only chooses the words. Note
        // that `previousAgentOffer` is the GM's own offer here — a refusing camp
        // has no standing number, and `respond` short-circuits before it reads
        // one, so passing the offer back is honest rather than a placeholder.
        let result = ContractNegotiationEngine.evaluateCounterOffer(
            gmOffer: gmOffer,
            player: player,
            previousAgentOffer: gmOffer,
            roundNumber: round,
            negotiationType: negotiationType,
            salaryCap: salaryCap,
            situation: negotiationSituation,
            standing: gmStanding,
            insultCount: live.insultCount ?? 0
        )
        live.insultCount = result.insultCount

        let reason = live.refusalReason ?? .losingCulture
        live.append(NegotiationThreadMessage(
            sender: .agent,
            text: AgentDialogue.pesteringLine(
                voice: agentVoice,
                reason: reason,
                attempt: attempt,
                ctx: context(ask: gmOffer, gmOffer: gmOffer, rounds: round),
                sel: sel
            ),
            round: round,
            tone: .refusing
        ))

        // He hears about it. Small, and cumulative — which is the point.
        player.morale = max(1, min(100, player.morale - ContractNegotiationEngine.pesterMoraleCost))
        try? modelContext.save()

        // The third time, say out loud what has been happening to the price.
        if attempt >= 3 {
            live.append(NegotiationThreadMessage(
                sender: .system,
                text: "\(player.fullName)'s asking price has hardened \(attempt) times since his camp declined to negotiate.",
                round: round
            ))
        }

        commit(live, sel: sel)
    }

    private func acceptAgentOffer() {
        guard var live = thread, live.isOpen, let snapshot = live.pendingAgentOffer else { return }
        guard !exceedsCap(snapshot.offer) else { return }
        let round = live.round
        let sel = selector(for: live, round: round)

        live.append(NegotiationThreadMessage(
            sender: .you,
            text: "We accept your terms. Let's get it signed.",
            offer: snapshot,
            round: round
        ))
        // This path does NOT go through `respond`, so the ledger write that
        // lives there never fires — which is why the GM's negotiating
        // reputation could only ever get worse: every insult was recorded and
        // the most natural way to close a deal was not.
        close(&live, with: snapshot.offer, round: round, demand: liveDemand,
              sel: sel, recordToLedger: true)
        commit(live, sel: sel)
    }

    private func walkAway() {
        guard var live = thread, live.isOpen else { return }
        live.append(NegotiationThreadMessage(
            sender: .you,
            text: "We're going to pass. Thank you for your time.",
            round: live.round
        ))
        live.append(NegotiationThreadMessage(
            sender: .system,
            text: "You ended talks with \(player.fullName)'s camp.",
            round: live.round
        ))
        live.status = .walkedAway
        live.pendingAgentOffer = nil
        commit(live)
    }

    // MARK: - Close

    /// Signs the deal: the agent's closing line in the tone of the JOURNEY, the
    /// inline receipt, the clause commit, the host's contract write, and the
    /// morale/motivation consequence. No dismiss — that is the user's call.
    private func close(
        _ live: inout NegotiationThread,
        with offer: NegotiationOffer,
        round: Int,
        demand: ContractDemand,
        sel: DialogueSelector,
        recordToLedger: Bool = false
    ) {
        // ECONOMY owns the verdict; this file only decides how it is said and
        // what it does to the man.
        let openerPerYear = live.openingAsk.map { $0.offer.annualCapHit } ?? offer.annualCapHit
        let tone = ContractNegotiationEngine.closeTone(
            signedPerYear: offer.annualCapHit,
            openingAskPerYear: openerPerYear,
            rounds: round,
            demand: demand
        )
        if recordToLedger { NegotiationLedger.recordSigning(tone: tone) }
        let ctx = context(ask: offer, signed: offer, rounds: round)
        let want = AgentDesire.primary(player: player, demand: demand)

        live.append(NegotiationThreadMessage(
            sender: .agent,
            text: AgentDialogue.acceptLine(
                voice: agentVoice, desire: want, tone: tone, ctx: ctx, sel: sel
            ),
            round: round,
            tone: tone
        ))
        live.append(NegotiationThreadMessage(
            sender: .system,
            text: signedSummary(offer),
            offer: NegotiationOfferSnapshot(offer),
            round: round,
            isSignedCard: true
        ))

        live.status = .signed
        live.closeToneRaw = tone.rawValue
        live.pendingAgentOffer = nil

        // §5.5: the clauses ride onto the player here rather than in
        // `onDealCompleted` — four screens present this view and each applies
        // the money its own way, so a clause that only survived on some of those
        // paths would be worse than no clause at all.
        ContractIncentiveRegistry.set(offer.incentives, for: player)

        // The prove-it bet, booked and settled in the one place a contract is
        // actually signed.
        //
        // Booking it: a short deal to a client the engine graded prove-it IS the
        // bet, and next winter's demand model has no other way to know it
        // happened (see `ProveItRegistry`). Settling it: a man who just cashed a
        // proven bet has been paid for it, and leaving the flag standing would
        // charge the club the same premium every year forever.
        if demand.stance == .provenBet {
            ProveItRegistry.clear(playerID: player.id)
        } else if demand.isProveIt, offer.years <= 2 {
            ProveItRegistry.record(playerID: player.id, season: season)
        }
        // He signed. Whatever he was asking the league for, he is staying.
        TradeRequestRegistry.clear(playerID: player.id)

        if !live.moraleApplied {
            live.moraleApplied = true
            live.lingeringNote = applyCloseEffects(tone: tone, desire: want, ctx: ctx, sel: sel)
        }

        onDealCompleted?(offer)
    }

    /// Tone -> morale/motivation. Modest by design: a negotiation moves a man's
    /// head, it does not rebuild him.
    ///
    /// Returns the lingering note a begrudging close leaves behind, if any.
    @discardableResult
    private func applyCloseEffects(
        tone: AgentToneKey,
        desire: AgentDesire,
        ctx: AgentDialogue.Context,
        sel: DialogueSelector
    ) -> String? {
        var note: String?
        switch tone {
        case .eager:
            // Got his number, got it fast. Small lift, and he shows up with
            // something to prove rather than a cheque to cash.
            player.morale = max(1, min(100, player.morale + 5))
            if player.motivationState != .driven {
                player.motivationState = .driven
            }
        case .professional:
            player.morale = max(1, min(100, player.morale + 2))
        default:
            // Ground down below his ask. He signs, and he remembers.
            player.morale = max(1, min(100, player.morale - 4))
            note = AgentDialogue.lingeringNote(desire: desire, ctx: ctx, sel: sel)
        }
        try? modelContext.save()
        return note
    }

    // MARK: - Tone
    //
    // There is nothing here on purpose. Every tone in this screen —
    // the opener's, each counter's and the close's — is
    // `ContractNegotiationEngine`'s verdict, read off `ContractDemand`,
    // `ChatVerdict.tone` and `closeTone(signedPerYear:…)` respectively.
    //
    // The three functions that used to live here re-derived it from
    // `NegotiationOffer.totalValue` while the engine graded `annualCapHit`, and
    // the two metrics disagreed in both directions: a shorter, richer package
    // rendered as a red "Ask hardened" bubble on an offer the engine called
    // professional, and a longer, thinner one rendered green on a hardline
    // counter. The close was worse — it charged 4 points of morale and left a
    // grudge note for deals the engine graded delighted.

    // MARK: - Dialogue Context

    private func baseContext() -> AgentDialogue.Context {
        AgentDialogue.Context(
            playerFirst: player.firstName,
            playerFull: player.fullName,
            position: player.position.rawValue,
            // A noun phrase, so the free-agent fallback reads as English in the
            // same sentence the real club does — see `Context.team`.
            team: team.map { "the \($0.name)" } ?? "this club"
        )
    }

    /// Fills the line-pool context from offers the ENGINE produced, so the money
    /// in the sentence and the money on the card underneath are the same money.
    private func context(
        ask: NegotiationOffer,
        gmOffer: NegotiationOffer? = nil,
        signed: NegotiationOffer? = nil,
        rounds: Int = 0
    ) -> AgentDialogue.Context {
        var ctx = baseContext()
        ctx.askPerYear = formatMillions(ask.annualSalary)
        ctx.askTotal = formatMillions(ask.totalValue)
        ctx.askYears = ask.years
        if let gmOffer {
            ctx.offerPerYear = formatMillions(gmOffer.annualSalary)
        }
        if let signed {
            ctx.signedPerYear = formatMillions(signed.annualSalary)
            ctx.signedTotal = formatMillions(signed.totalValue)
            ctx.signedYears = signed.years
        }
        ctx.rounds = rounds
        return ctx
    }

    /// The receipt copy — names the clause ceiling when the deal has one, so the
    /// GM never signs clauses without seeing what they can cost.
    private func signedSummary(_ offer: NegotiationOffer) -> String {
        let base = "\(player.fullName) — \(offer.years) year\(offer.years == 1 ? "" : "s"), \(formatMillions(offer.totalValue)) total, \(offer.guaranteedPercent)% guaranteed."
        guard !offer.incentives.isEmpty else { return base }
        return base + " \(offer.incentives.count) performance clause\(offer.incentives.count == 1 ? "" : "s") take it to \(formatMillions(offer.maxValue)) if he hits them all."
    }

    // MARK: - Persistence

    /// Writes the thread to state AND to the save. Every mutation goes through
    /// here — a transcript that only exists in `@State` is the bug this wave
    /// was opened to fix.
    ///
    /// - Parameter sel: the picker that chose this exchange's lines, if any. Its
    ///   memory rides onto the thread here rather than at each call site, so a
    ///   new dialogue site cannot forget to persist its own no-repeat state.
    private func commit(_ updated: NegotiationThread, sel: DialogueSelector? = nil) {
        var updated = updated
        if let sel { updated.lastLineIndex = sel.lastIndex }
        thread = updated
        scrollTarget = updated.messages.last?.id
        if let careerID = player.careerID {
            NegotiationThreadStore.upsert(updated, careerID: careerID)
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

    /// Persona accent color for the agent chip.
    private var personaColor: Color {
        switch agentPersona {
        case .hardliner:   return .danger
        case .cooperative: return .success
        case .loyalist:    return .accentGold
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
