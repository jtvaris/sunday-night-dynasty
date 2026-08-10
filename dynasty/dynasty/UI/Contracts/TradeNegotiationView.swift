import SwiftUI
import SwiftData

// MARK: - Trade Negotiation View (Wave 3 — `docs/TRADE_OVERHAUL_PLAN.md` §6)
//
// The contract-negotiation experience, ported to trades.
//
// `ContractNegotiationView` already proved the shape: a persona header so the
// other side of the table is a PERSON, a chat transcript so the conversation has
// a memory, offer snapshots inside the bubbles, a round counter measured against
// that person's patience, and a break-off that costs something. Trades had none
// of it — "Negotiate" loaded the offer into the builder and walked away, and a
// counter arrived as an alert that overwrote the package with no record it ever
// happened (plan finding S7).
//
// The brain is entirely Wave 2's: every AI turn is `TradeValueEngine.respond`,
// which is the same call the Trade Center's preview verdict is derived from, so
// the transcript can never promise something the executed deal disagrees with
// (plan G7). Nothing here prices a deal, and nothing here executes one either —
// an agreed package is handed back to the Trade Center through `onDealAgreed`,
// which keeps `TradeView.executeUserTrade` the single execution path.
//
// ---------------------------------------------------------------------------
// #105 WAVE 3c — the port became a share.
//
// "The contract-negotiation experience, ported to trades" is what the header
// above has said since Wave 3 of the trade plan, and porting is exactly what
// went wrong: the two screens grew the same five parts twice and then drifted
// apart (bubbles clamped at 520 here and 500 there, a bare `720` measure here
// and none there, a tone chip there and none here). `NegotiationChat.swift` is
// now the single implementation of all of it, and this file supplies values to
// it. In the same pass:
//
//   * the GM's patience stopped being a bespoke dot-rail and became the round
//     band's `DSResourceMeter` — one meaning for a filled pip, app-wide;
//   * the three equal-weight buttons became one `DSActionBar` with one gold
//     primary and Walk Away separated as the destructive;
//   * `closedFooter`'s prose became a `DSResultSheet` at the moment the thread
//     closes, plus a read-only strip on re-entry;
//   * the toolbar "Close" became the one 44 pt X every negotiation now uses.
//
// **No trade logic moved.** Every `TradeValueEngine` call below keeps its
// arguments, its order and its `pricingWeek` / `pressureWeek` split.
struct TradeNegotiationView: View {

    let career: Career
    let partnerTeamID: UUID

    /// Resume a persisted thread. `nil` opens a new one from `seed`.
    var threadID: UUID? = nil
    /// Opening package for a NEW thread, always from the user's perspective
    /// (`offeringTeamID` is the user's team).
    var seed: TradeProposal? = nil
    /// The `career.pendingTradeOffers` row a new AI-initiated thread grew from.
    /// Its presence is what makes the thread "they called us".
    var sourceOfferID: UUID? = nil
    /// The AI's own rationale line, when the thread starts from an inbox offer.
    var openingLine: String? = nil

    /// The user agreed to this package — the Trade Center executes it. The
    /// thread rides along so the caller can file the deal under the right
    /// ledger kind (a call the AI made is not a proposal the user built).
    var onDealAgreed: ((TradeProposal, TradeNegotiationThread) -> Void)? = nil
    /// Thread-level mail (a GM ending the relationship).
    var onInboxMessage: ((InboxMessage) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: State

    @State private var thread: TradeNegotiationThread?
    @State private var allTeams: [Team] = []
    @State private var allPlayers: [Player] = []
    @State private var allPicks: [DraftPick] = []
    @State private var allContracts: [Contract] = []
    @State private var myTeam: Team?
    @State private var partner: Team?

    // Package editor selections — the live package between rounds.
    @State private var mySelectedPlayers: Set<UUID> = []
    @State private var mySelectedPicks: Set<UUID> = []
    @State private var theirSelectedPlayers: Set<UUID> = []
    @State private var theirSelectedPicks: Set<UUID> = []

    @State private var showEditor = false
    @State private var scrollTarget: UUID?
    @State private var didLoad = false

    // MARK: Result presentation (#105 Wave 3c)

    /// **The one sheet on this screen**, `.sheet(item:)`-driven. Two
    /// `.sheet(isPresented:)` modifiers in one hierarchy silently swallow one of
    /// the presentations, which this codebase has now shipped four times.
    @State private var outcome: NegotiationOutcome?

    /// The status the screen has already reacted to, so the result fires on a
    /// transition and never on arrival — re-opening a thread that broke off in
    /// week 3 must not throw a modal about it.
    @State private var lastSeenStatus: TradeThreadStatus?

    /// The calendar slot this conversation is PRICED at (task #150c).
    ///
    /// `TradeValueEngine.askNoise` re-draws a GM's hidden asking mood every week,
    /// by design — it stops the accept bar being solvable by arithmetic. Inside a
    /// LIVE conversation that same re-draw made an untouched package read "They
    /// like it" one week and "They're on the fence" the next, which reads as a
    /// bug however deterministic it is: the user changed nothing and the answer
    /// moved. Pinning every read in an open thread to the week it OPENED gives
    /// the GM one mood for one negotiation, and the mood still differs between
    /// GMs, between conversations and between league years. A fresh package (no
    /// thread yet) prices at today, which is the same number.
    private var pricingWeek: Int { thread?.openedWeek ?? career.currentWeek }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if let partner, myTeam != nil, thread != nil {
                VStack(spacing: 0) {
                    gmHeader(partner: partner)
                    roundBand(partner: partner)
                    NegotiationTranscript(lines: chatLines, scrollTarget: scrollTarget)
                    if isActive {
                        negotiationPanel(partner: partner)
                        commitBar
                    } else {
                        closeStrip
                    }
                }
            } else {
                ProgressView()
                    .tint(Color.accentGold)
            }
        }
        .navigationTitle("Trade Talks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // P5's corollary: one dismissal, one glyph, one place.
        .negotiationDismissButton(label: "Close these trade talks. The thread stays saved.") {
            dismiss()
        }
        // §2.6: the outcome is a result sheet, not prose swapped in under the
        // transcript where the user has to notice it.
        .sheet(item: $outcome) { result in
            DSResultSheet(
                tone: result.tone,
                eyebrow: "Trade talks",
                headline: result.headline,
                message: result.message,
                chips: result.chips,
                cost: result.cost,
                onContinue: {
                    outcome = nil
                    dismiss()
                }
            )
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            load()
        }
    }

    /// Talks accept another round only while the thread is open AND the league's
    /// trade window is. A thread that outlived the deadline is read-only history.
    private var isActive: Bool {
        guard let thread, thread.isOpen else { return false }
        return TradeValueEngine.isTradeWindowOpen(
            phase: career.currentPhase, week: career.currentWeek
        )
    }

    private var identity: TradeValueEngine.GMIdentity? {
        guard let partner else { return nil }
        return TradeValueEngine.gmIdentity(team: partner, season: career.currentSeason)
    }

    // MARK: - GM Header

    private func gmHeader(partner: Team) -> some View {
        let id = TradeValueEngine.gmIdentity(team: partner, season: career.currentSeason)
        let accent = personaColor(id.archetype)

        return NegotiationChatHeader(
            title: partner.fullName,
            identityChips: [
                .init(id: "gm", text: id.name, icon: id.symbolName, color: accent, style: .tinted),
                .init(id: "arch", text: id.archetypeLabel, color: accent, style: .tinted),
                // Public posture, not the hidden accept bar — decision §7.1.
                .init(id: "premium", text: "Opens ~\(id.askingPremiumPercent)% over", color: .textTertiaryReadable, style: .tinted)
            ],
            note: id.blurb,
            trailing: { EmptyView() },
            footer: { expiryChip }
        )
    }

    private var expiryChip: some View {
        let note = TradeWindowRules.expiryNote(
            phase: career.currentPhase, week: career.currentWeek
        )
        return HStack(spacing: DSSpacing.xxs) {
            Image(systemName: "clock.fill")
                .font(.system(size: 10, weight: .semibold))
            Text(note)
                .font(DSType.display(11, .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.warning)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, DSSpacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.warning.opacity(0.10))
        )
    }

    // MARK: - Round Band

    /// **The GM's patience, as the app's one process spine** (§2.1).
    ///
    /// It used to be a bespoke dot-rail beside a bare "Round 3" — two of the
    /// seven progress metaphors the band replaces, in one corner of one header.
    /// The numbers are unchanged: `GMIdentity.patience` is `GMPersona.maxRounds`
    /// and `strikes` is what `TradeTalkRegistry` has logged, so a filled pip is
    /// still one lowball this front office has already spent.
    @ViewBuilder
    private func roundBand(partner: Team) -> some View {
        let id = TradeValueEngine.gmIdentity(team: partner, season: career.currentSeason)
        let rounds = thread?.round ?? 0
        NegotiationRoundBand(
            used: rounds,
            // The ribbon grows with the conversation. A trade talk has no round
            // cap — only a LOWBALL cap — so drawing exactly `patience` slats
            // would show a fifth fair counter as "past the end".
            limit: max(id.patience, rounds),
            // …and the meter is the thing that actually runs out. A filled pip is
            // a strike this front office has already spent with this GM, across
            // every conversation of the league year, which is `TradeTalkRegistry`
            // and not this thread's round count.
            meter: DSResourceMeter(
                spent: min(id.strikes, id.patience),
                total: max(1, id.patience),
                unit: "patience"
            ),
            outcomes: roundOutcomes,
            isClosed: !isActive
        )
    }

    /// What each round put on the table, read off the transcript so the band can
    /// never quote a package the conversation does not contain.
    private var roundOutcomes: [Int: String] {
        var byRound: [Int: String] = [:]
        for message in thread?.messages ?? [] where message.sender == .you {
            guard let proposal = message.proposal else { continue }
            let out = proposal.sendingPlayers.count + proposal.sendingPicks.count
            let inc = proposal.receivingPlayers.count + proposal.receivingPicks.count
            byRound[message.round] = "\(out) out · \(inc) in"
        }
        return byRound
    }

    // MARK: - Transcript

    /// The persisted messages, mapped onto the shared line model.
    private var chatLines: [NegotiationChatLine] {
        (thread?.messages ?? []).map { message in
            NegotiationChatLine(
                id: message.id,
                side: side(for: message.sender),
                speaker: identity?.name ?? partner?.abbreviation ?? "GM",
                text: message.text,
                attachment: message.proposal.map { AnyView(snapshot($0)) }
            )
        }
    }

    private func side(for sender: TradeThreadSender) -> NegotiationChatSide {
        switch sender {
        case .gm:     return .them
        case .you:    return .you
        case .system: return .system
        }
    }

    /// The frozen package attached to one line — the same two-column widget the
    /// Trade Center's offer cards use.
    private func snapshot(_ proposal: TradeProposal) -> some View {
        let playerLookup = Dictionary(uniqueKeysWithValues: allPlayers.map { ($0.id, $0) })
        let pickLookup   = Dictionary(uniqueKeysWithValues: allPicks.map   { ($0.id, $0) })
        let values = TradeValueEngine.proposalValues(
            proposal: proposal,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: career.currentSeason
        )

        return TradeOfferSnapshotCard(
            sendPlayers: proposal.sendingPlayers.compactMap { playerLookup[$0] },
            sendPicks: proposal.sendingPicks.compactMap { pickLookup[$0] },
            receivePlayers: proposal.receivingPlayers.compactMap { playerLookup[$0] },
            receivePicks: proposal.receivingPicks.compactMap { pickLookup[$0] },
            sendValue: values.sendingValue,
            receiveValue: values.receivingValue
        )
    }

    // MARK: - Negotiation Panel

    private func negotiationPanel(partner: Team) -> some View {
        VStack(spacing: DSSpacing.xs) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)

            verdictRow(partner: partner)
            blockerRow(partner: partner)
            packageEditor(partner: partner)
            // The commit is the `DSActionBar` under this panel — §2.5's rule that
            // a screen commits in exactly one place.
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .frame(maxWidth: DSLayout.contentMeasure)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary)
    }

    /// Live read on the package currently in the editor, from the same 5-step
    /// verdict `respond` will use — so what the GM says next is never a surprise.
    private func verdictRow(partner: Team) -> some View {
        let proposal = builtProposal()
        let verdict = proposal.map {
            TradeValueEngine.partnerVerdict(
                proposal: $0,
                aiTeam: partner,
                allPlayers: allPlayers,
                allPicks: allPicks,
                currentSeason: career.currentSeason,
                contracts: allContracts,
                week: pricingWeek,
                standingCounter: thread?.pendingCounter
            )
        }
        let values = proposal.map {
            TradeValueEngine.proposalValues(
                proposal: $0,
                allPlayers: allPlayers,
                allPicks: allPicks,
                currentSeason: career.currentSeason
            )
        }

        return HStack(spacing: 10) {
            if let verdict {
                Label(verdict.label, systemImage: verdict.icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(verdictColor(verdict))
            }
            Spacer()
            if let values {
                Text("Send \(values.sendingValue) · Get \(values.receivingValue) pts")
                    .font(.system(size: 11).weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    /// What the league office would refuse. One `NegotiationNotice` — the same
    /// banner shape the contract chat draws a refusal and a pay-cut answer with.
    @ViewBuilder
    private func blockerRow(partner: Team) -> some View {
        let blockers = currentBlockers()
        if !blockers.isEmpty {
            NegotiationNotice(
                icon: "exclamationmark.triangle.fill",
                color: .dangerText,
                title: "The league office won't process this",
                message: blockers.joined(separator: " ")
            )
        }
    }

    // MARK: - Package Editor

    /// Reworking the package mid-conversation is the point: the user changes
    /// what is on the table WITHOUT losing the thread, which is exactly what the
    /// old builder-overwrite flow made impossible.
    private func packageEditor(partner: Team) -> some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showEditor.toggle() }
            } label: {
                HStack {
                    Text(showEditor ? "Hide package" : "Rework package")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(packageSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                    Image(systemName: showEditor ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            .accessibilityHint(showEditor ? "Collapse the package editor" : "Expand the package editor")

            if showEditor {
                ScrollView {
                    HStack(alignment: .top, spacing: 14) {
                        editorColumn(
                            title: "You send",
                            players: myPlayers,
                            picks: myPicks,
                            selectedPlayers: $mySelectedPlayers,
                            selectedPicks: $mySelectedPicks,
                            accentColor: Color.accentBlue
                        )
                        Divider().overlay(Color.surfaceBorder)
                        editorColumn(
                            title: "\(partner.abbreviation) send",
                            players: theirPlayers,
                            picks: theirPicks,
                            selectedPlayers: $theirSelectedPlayers,
                            selectedPicks: $theirSelectedPicks,
                            accentColor: Color.accentGold
                        )
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 260)
            }
        }
    }

    private func editorColumn(
        title: String,
        players: [Player],
        picks: [DraftPick],
        selectedPlayers: Binding<Set<UUID>>,
        selectedPicks: Binding<Set<UUID>>,
        accentColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)

            ForEach(players) { player in
                TradeAssetToggleRow(
                    label: player.fullName,
                    sublabel: "\(player.position.rawValue) · \(player.overall) OVR · Age \(player.age)",
                    valueLabel: "\(TradeValueEngine.playerTradeValue(player: player)) pts",
                    isSelected: selectedPlayers.wrappedValue.contains(player.id),
                    accentColor: accentColor,
                    // #141b: the same rule the Trade Center builder enforces —
                    // `TradeValueEngine.validationErrors` refuses a tagged man on
                    // either side, so he must not be checkable into a rework
                    // either.
                    blockedReason: player.isFranchiseTagged
                        ? "Franchise-tagged — can't be traded."
                        : nil
                ) {
                    toggle(id: player.id, in: selectedPlayers)
                }
            }

            ForEach(picks) { pick in
                TradeAssetToggleRow(
                    label: TradeAssetFormat.pickLabel(pick),
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    /// **The one place this screen commits** (§2.5). One gold primary, the live
    /// verdict as its explainer, Walk Away separated as the destructive.
    private var commitBar: some View {
        DSActionBar(
            explainer: .init(
                title: hasAssets ? "Table this package" : "Nothing on the table",
                message: commitExplainerMessage,
                isWarning: !hasAssets || !currentBlockers().isEmpty
            ),
            destructive: .init(
                title: "Walk Away",
                accessibilityLabel: "End these talks. No strike against the relationship.",
                handler: { walkAway() }
            ),
            secondary: acceptAction,
            primary: .init(
                title: thread?.round == 0 ? "Send Offer" : "Counter",
                isEnabled: hasAssets,
                accessibilityLabel: hasAssets
                    ? "Sends this package to the other front office."
                    : "Disabled: put at least one player or pick on the table first.",
                handler: {
                    if let thread, let proposal = builtProposal() {
                        sendOffer(proposal, on: thread)
                    }
                }
            )
        )
    }

    /// "Accept Theirs", but only while the other side has a package standing.
    private var acceptAction: DSActionBar.Action? {
        guard thread?.pendingCounter != nil else { return nil }
        return DSActionBar.Action(
            title: "Accept Theirs",
            accessibilityLabel: "Accept the package the other side has on the table.",
            handler: { acceptCounter() }
        )
    }

    /// What tabling this package does. The blockers win when there are any — the
    /// league office refusing is more urgent than what the GM thinks of it.
    private var commitExplainerMessage: String {
        guard hasAssets else {
            return "Tick at least one player or pick on either side before you call."
        }
        let blockers = currentBlockers()
        if !blockers.isEmpty { return blockers.joined(separator: " ") }
        return "Spends **one of \(identity?.patience ?? 0) rounds** of this GM's patience. A lowball costs a round whether or not he counters."
    }

    /// A finished conversation, on re-entry. No button: `DSResultSheet` gave the
    /// outcome when it happened, and the way out is the single X.
    private var closeStrip: some View {
        NegotiationCloseStrip(status: closeStatusLine)
    }

    private var closeStatusLine: String {
        guard let thread else { return "" }
        switch thread.status {
        case .agreed:     return "Terms are agreed. The league office files the trade when you close this screen."
        case .withdrawn:  return "You ended these talks. Start a fresh conversation from the Trade Center whenever you want."
        case .brokenOff:  return "\(identity?.name ?? "This GM") isn't taking your calls again until the new league year."
        case .expired:    return "This conversation expired with the trade window."
        case .open:       return "The trade window is closed. This conversation resumes when it reopens."
        }
    }

    // MARK: - Negotiation Turns

    /// One full round: the user's package goes on the table, the AI answers with
    /// the SAME call the Trade Center previews from.
    private func sendOffer(_ proposal: TradeProposal, on baseThread: TradeNegotiationThread) {
        guard let partner else { return }

        var updated = baseThread

        // Hard league rules first — a package the league office would refuse
        // never becomes a negotiating position.
        let blockers = validationErrors(for: proposal)
        if !blockers.isEmpty {
            append(
                .init(
                    sender: .system,
                    text: "The league office won't process that package: " + blockers.joined(separator: " "),
                    round: updated.round
                ),
                to: &updated
            )
            persist(updated)
            return
        }

        updated.round += 1
        updated.lastActivityWeek = career.currentWeek
        updated.proposal = proposal
        append(
            .init(
                sender: .you,
                text: updated.round == 1
                    ? "Here's what we're prepared to do."
                    : "We've reworked it. Take another look.",
                proposal: proposal,
                round: updated.round
            ),
            to: &updated
        )

        // Snapshot the relationship BEFORE the call so we can tell a GM who just
        // hung up for good from one who was already refusing to pick up.
        let before = TradeValueEngine.gmIdentity(team: partner, season: career.currentSeason)

        let response = TradeValueEngine.respond(
            to: proposal,
            aiTeam: partner,
            allPlayers: allPlayers,
            allPicks: allPicks,
            currentSeason: career.currentSeason,
            contracts: allContracts,
            // Task #150c: one asking mood per conversation — see `pricingWeek`.
            week: pricingWeek,
            // Task #36: the round the user's line just landed in drives the GM's
            // concession curve — his first counter holds near the opening ask,
            // every further one walks toward the bar he signs at.
            round: updated.round,
            // Task #150a: if this IS the package he demanded, he signs it.
            standingCounter: baseThread.pendingCounter,
            // Task #36: the pricing mood is frozen at `openedWeek`, but the
            // deadline is a fact about TODAY — a conversation started in week 3
            // and still live in week 9 is a deadline conversation.
            pressureWeek: career.currentWeek
        )

        switch response {
        case .accepted:
            updated.pendingCounter = nil
            append(
                .init(sender: .gm, text: acceptLine(), proposal: proposal, round: updated.round),
                to: &updated
            )
            append(
                .init(
                    sender: .system,
                    text: "Deal agreed with \(partner.abbreviation). Close this screen to file it with the league office.",
                    round: updated.round
                ),
                to: &updated
            )
            updated.status = .agreed
            persist(updated)
            // No auto-dismiss: a deal struck on the first call would otherwise
            // flash the conversation open and shut. The Trade Center executes on
            // dismiss, so the user reads the exchange and closes when ready —
            // the same rule `ContractNegotiationView` follows.
            onDealAgreed?(proposal, updated)

        case .rejected(let reason):
            append(.init(sender: .gm, text: reason, round: updated.round), to: &updated)
            // `respond` logs the strike itself; re-reading the registry is how we
            // learn whether that one ended the relationship.
            let after = TradeValueEngine.gmIdentity(team: partner, season: career.currentSeason)
            if !after.talksOpen {
                updated.status = .brokenOff
                append(
                    .init(sender: .system, text: breakOffLine(after, partner: partner), round: updated.round),
                    to: &updated
                )
                // Only the round that ACTUALLY ends the relationship is news —
                // re-dialling a GM who already stopped answering must not mail
                // the same break-off notice again.
                if before.talksOpen {
                    onInboxMessage?(InboxEngine.tradeTalksBrokenOffMessage(
                        gmName: after.name,
                        partnerName: partner.fullName,
                        partnerAbbr: partner.abbreviation,
                        dateString: InboxEngine.dateLabel(
                            week: career.currentWeek,
                            season: career.currentSeason,
                            phase: career.currentPhase
                        )
                    ))
                }
            }
            persist(updated)

        case .countered(let counter, let message):
            updated.pendingCounter = counter
            updated.proposal = counter
            append(
                .init(sender: .gm, text: message, proposal: counter, round: updated.round),
                to: &updated
            )
            persist(updated)
            // The counter becomes the live package — the user keeps editing from
            // where the other side left it instead of from scratch.
            applySelections(from: counter)
        }
    }

    private func acceptCounter() {
        guard var updated = thread, let counter = updated.pendingCounter, let partner else { return }

        let blockers = validationErrors(for: counter)
        if !blockers.isEmpty {
            append(
                .init(
                    sender: .system,
                    text: "That counter no longer clears league rules: " + blockers.joined(separator: " "),
                    round: updated.round
                ),
                to: &updated
            )
            persist(updated)
            return
        }

        updated.proposal = counter
        updated.pendingCounter = nil
        updated.lastActivityWeek = career.currentWeek
        append(
            .init(sender: .you, text: "We'll take that. Send the paperwork.", proposal: counter, round: updated.round),
            to: &updated
        )
        append(
            .init(
                sender: .system,
                text: "Deal agreed with \(partner.abbreviation). Close this screen to file it with the league office.",
                round: updated.round
            ),
            to: &updated
        )
        updated.status = .agreed
        persist(updated)
        onDealAgreed?(counter, updated)
    }

    private func walkAway() {
        guard var updated = thread, let partner else { return }
        append(
            .init(sender: .you, text: "We're going to pass. Appreciate the time.", round: updated.round),
            to: &updated
        )
        append(
            .init(
                sender: .system,
                text: "You ended talks with \(partner.abbreviation). No strike against the relationship — you can call back.",
                round: updated.round
            ),
            to: &updated
        )
        updated.status = .withdrawn
        persist(updated)
    }

    // MARK: - Copy

    private func acceptLine() -> String {
        guard let id = identity, let partner else { return "We have a deal." }
        switch id.archetype {
        case .oldSchool:
            return "That's how the chart works. \(partner.abbreviation) have a deal — nice doing business."
        case .balanced:
            return "That works for us. \(id.name) will sign it today."
        case .analytics:
            return "The math clears. \(partner.abbreviation) accept."
        case .aggressive:
            return "Done. \(id.name) doesn't sit on a deal he likes — let's get it filed."
        }
    }

    private func breakOffLine(_ id: TradeValueEngine.GMIdentity, partner: Team) -> String {
        switch id.archetype {
        case .oldSchool:
            return "\(id.name) hangs up for good. \(partner.abbreviation) won't take another call from this front office until the new league year."
        case .balanced:
            return "\(id.name) has heard enough. \(partner.abbreviation) are done talking trade with you this league year."
        case .analytics:
            return "\(id.name) closes the file. \(partner.abbreviation) stop returning your calls for the rest of the league year."
        case .aggressive:
            return "\(id.name) slams the phone down. \(partner.abbreviation) are out until the new league year."
        }
    }

    private func openingGMLine(partner: Team) -> String {
        let id = TradeValueEngine.gmIdentity(team: partner, season: career.currentSeason)
        return "\(id.name) is on the line for the \(partner.fullName). Here's what they're proposing."
    }

    // MARK: - Thread Plumbing

    private func append(_ message: TradeThreadMessage, to thread: inout TradeNegotiationThread) {
        thread.messages.append(message)
        scrollTarget = message.id
    }

    private func persist(_ updated: TradeNegotiationThread) {
        let previous = lastSeenStatus
        thread = updated
        career.upsertTradeThread(updated)
        try? modelContext.save()
        announce(status: updated.status, from: previous)
    }

    // MARK: - Result (#105 Wave 3c)

    /// Raises the result sheet on a TRANSITION only. `previous == nil` is the
    /// load pass, and a thread that broke off six weeks ago must not open with a
    /// modal about it.
    private func announce(status: TradeThreadStatus, from previous: TradeThreadStatus?) {
        lastSeenStatus = status
        guard let previous, previous != status, status != .open else { return }
        outcome = makeOutcome(for: status)
    }

    private func makeOutcome(for status: TradeThreadStatus) -> NegotiationOutcome {
        switch status {
        case .agreed:
            let proposal = thread?.proposal
            let values = proposal.map {
                TradeValueEngine.proposalValues(
                    proposal: $0,
                    allPlayers: allPlayers,
                    allPicks: allPicks,
                    currentSeason: career.currentSeason
                )
            }
            return NegotiationOutcome(
                tone: .good,
                headline: "Deal agreed with \(partner?.abbreviation ?? "them")",
                message: "\(identity?.name ?? "Their GM") signed off after \(thread?.round ?? 1) round\((thread?.round ?? 1) == 1 ? "" : "s").",
                // Counted off the AGREED package, not off the editor's ticks —
                // an accepted counter is the other side's package, and the
                // editor may still be showing what the user last built.
                chips: [
                    .init(
                        id: "out",
                        label: "You send",
                        value: "\((proposal?.sendingPlayers.count ?? 0) + (proposal?.sendingPicks.count ?? 0))",
                        context: values.map { "\($0.sendingValue) pts" }
                    ),
                    .init(
                        id: "in",
                        label: "You get",
                        value: "\((proposal?.receivingPlayers.count ?? 0) + (proposal?.receivingPicks.count ?? 0))",
                        context: values.map { "\($0.receivingValue) pts" }
                    )
                ],
                cost: "The league office files it when you continue. **`TradeView` executes** — nothing has moved yet."
            )

        case .brokenOff:
            return NegotiationOutcome(
                tone: .bad,
                headline: "\(identity?.name ?? "The GM") stopped answering",
                message: "\(partner?.abbreviation ?? "They") won't take another call from this front office until the new league year.",
                cost: "Every other club still answers. The strikes are logged against **this** relationship only."
            )

        case .withdrawn:
            return NegotiationOutcome(
                tone: .neutral,
                headline: "You ended the talks",
                message: "No strike against the relationship — you can call \(partner?.abbreviation ?? "them") back.",
                cost: "Nothing was traded, and the thread stays saved in the Trade Center."
            )

        case .expired:
            return NegotiationOutcome(
                tone: .bad,
                headline: "The window closed on this one",
                message: "The trade deadline passed with the package unsigned.",
                cost: "The conversation is history now. A new league year opens a fresh one."
            )

        case .open:
            return NegotiationOutcome(tone: .neutral, headline: "Talks continue")
        }
    }

    // MARK: - Data

    private func load() {
        let cid = career.id
        allTeams = (try? modelContext.fetch(
            FetchDescriptor<Team>(predicate: #Predicate { $0.careerID == cid })
        )) ?? []
        allPlayers = (try? modelContext.fetch(
            FetchDescriptor<Player>(predicate: #Predicate { $0.careerID == cid })
        )) ?? []
        allPicks = (try? modelContext.fetch(
            FetchDescriptor<DraftPick>(predicate: #Predicate { $0.careerID == cid && !$0.isComplete })
        )) ?? []
        allContracts = (try? modelContext.fetch(
            FetchDescriptor<Contract>(predicate: #Predicate { $0.careerID == cid })
        )) ?? []

        partner = allTeams.first { $0.id == partnerTeamID }
        if let teamID = career.teamID {
            myTeam = allTeams.first { $0.id == teamID }
        }
        guard let partner, myTeam != nil else { return }

        if let threadID, let existing = career.tradeThreads.first(where: { $0.id == threadID }) {
            thread = existing
            // Arrival, not a transition (#105 Wave 3c) — no result sheet for an
            // ending the user already read.
            lastSeenStatus = existing.status
            applySelections(from: existing.pendingCounter ?? existing.proposal)
            scrollTarget = existing.messages.last?.id
            return
        }

        guard let seed else { return }
        var fresh = TradeNegotiationThread(
            id: UUID(),
            partnerTeamID: partnerTeamID,
            season: career.currentSeason,
            openedWeek: career.currentWeek,
            proposal: seed,
            startedByAI: sourceOfferID != nil,
            sourceOfferID: sourceOfferID
        )
        applySelections(from: seed)

        if fresh.startedByAI {
            // They called us: the offer stands as-is until the user answers.
            fresh.pendingCounter = seed
            fresh.messages.append(TradeThreadMessage(
                sender: .gm,
                text: openingLine ?? openingGMLine(partner: partner),
                proposal: seed,
                round: 0
            ))
            persist(fresh)
            scrollTarget = fresh.messages.last?.id
        } else {
            // We called them: the package the user already built IS round one.
            persist(fresh)
            sendOffer(seed, on: fresh)
        }
    }

    private func applySelections(from proposal: TradeProposal) {
        mySelectedPlayers = Set(proposal.sendingPlayers)
        mySelectedPicks = Set(proposal.sendingPicks)
        theirSelectedPlayers = Set(proposal.receivingPlayers)
        theirSelectedPicks = Set(proposal.receivingPicks)
    }

    private func builtProposal() -> TradeProposal? {
        guard let myTeam, let partner, let thread else { return nil }
        return TradeProposal(
            id: thread.proposal.id,
            offeringTeamID: myTeam.id,
            receivingTeamID: partner.id,
            sendingPlayers: Array(mySelectedPlayers),
            receivingPlayers: Array(theirSelectedPlayers),
            sendingPicks: Array(mySelectedPicks),
            receivingPicks: Array(theirSelectedPicks)
        )
    }

    /// League rules for THIS window (task #25: the offseason carries 80-90
    /// players and empties below 40, so the in-season defaults are wrong there).
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

    private func currentBlockers() -> [String] {
        guard hasAssets, let proposal = builtProposal() else { return [] }
        return validationErrors(for: proposal)
    }

    // MARK: - Computed Helpers

    private var hasAssets: Bool {
        !mySelectedPlayers.isEmpty || !mySelectedPicks.isEmpty ||
        !theirSelectedPlayers.isEmpty || !theirSelectedPicks.isEmpty
    }

    private var packageSummary: String {
        let out = mySelectedPlayers.count + mySelectedPicks.count
        let inc = theirSelectedPlayers.count + theirSelectedPicks.count
        return "\(out) out · \(inc) in"
    }

    private var myPlayers: [Player] {
        guard let myTeam else { return [] }
        return allPlayers
            .filter { $0.teamID == myTeam.id }
            .sorted { $0.overall > $1.overall }
    }

    private var myPicks: [DraftPick] {
        guard let myTeam else { return [] }
        return allPicks
            .filter { $0.currentTeamID == myTeam.id }
            .sorted { $0.pickNumber < $1.pickNumber }
    }

    private var theirPlayers: [Player] {
        guard let partner else { return [] }
        return allPlayers
            .filter { $0.teamID == partner.id }
            .sorted { $0.overall > $1.overall }
    }

    private var theirPicks: [DraftPick] {
        guard let partner else { return [] }
        return allPicks
            .filter { $0.currentTeamID == partner.id }
            .sorted { $0.pickNumber < $1.pickNumber }
    }

    private func toggle(id: UUID, in binding: Binding<Set<UUID>>) {
        if binding.wrappedValue.contains(id) {
            binding.wrappedValue.remove(id)
        } else {
            binding.wrappedValue.insert(id)
        }
    }

    private func personaColor(_ archetype: TradeValueEngine.GMArchetype) -> Color {
        switch archetype {
        case .oldSchool:  return .accentBlue
        case .balanced:   return .textSecondary
        case .analytics:  return .success
        case .aggressive: return .danger
        }
    }

    private func verdictColor(_ verdict: TradeValueEngine.PartnerVerdict) -> Color {
        switch verdict {
        case .loveIt, .likeIt: return .success
        case .onTheFence:      return .warning
        case .wantMore:        return .warning
        case .hangUp:          return .danger
        }
    }
}
