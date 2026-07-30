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

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if let partner, myTeam != nil, thread != nil {
                VStack(spacing: 0) {
                    gmHeader(partner: partner)
                    transcript
                    if isActive {
                        negotiationPanel(partner: partner)
                    } else {
                        closedFooter
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
                    .foregroundStyle(Color.textSecondary)
            }
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

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(partner.fullName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Image(systemName: id.symbolName)
                            .font(.system(size: 10))
                            .foregroundStyle(accent)
                        Text("GM: \(id.name)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.textSecondary)
                        Text(id.archetypeLabel)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.12), in: Capsule())
                    }

                    Text(id.blurb)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Round \(thread?.round ?? 0)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    patienceMeter(id)
                    Text("opens ~\(id.askingPremiumPercent)% over")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            expiryChip
        }
        .padding(16)
        .background(Color.backgroundSecondary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)
        }
    }

    /// Patience left before the freeze-out: one pip per lowball this GM will
    /// absorb, spent pips first. The clock the user is actually racing.
    private func patienceMeter(_ id: TradeValueEngine.GMIdentity) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<max(1, id.patience), id: \.self) { index in
                Circle()
                    .fill(index < id.strikes ? Color.danger : Color.success.opacity(0.75))
                    .frame(width: 7, height: 7)
            }
            Text("patience")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var expiryChip: some View {
        let note = TradeWindowRules.expiryNote(
            phase: career.currentPhase, week: career.currentWeek
        )
        return HStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .font(.system(size: 9))
            Text(note)
                .font(.system(size: 10, weight: .semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.warning)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.warning.opacity(0.10))
        )
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(thread?.messages ?? []) { message in
                        bubble(message)
                            .id(message.id)
                    }
                }
                .padding(16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
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

    @ViewBuilder
    private func bubble(_ message: TradeThreadMessage) -> some View {
        switch message.sender {
        case .gm:     gmBubble(message)
        case .you:    youBubble(message)
        case .system: systemBubble(message)
        }
    }

    private func gmBubble(_ message: TradeThreadMessage) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(identity?.name ?? partner?.abbreviation ?? "GM")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let proposal = message.proposal {
                    snapshot(proposal)
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
            .frame(maxWidth: 520, alignment: .leading)

            Spacer(minLength: 40)
        }
    }

    private func youBubble(_ message: TradeThreadMessage) -> some View {
        HStack(alignment: .top) {
            Spacer(minLength: 40)

            VStack(alignment: .leading, spacing: 6) {
                Text("You")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentGold.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text(message.text)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)

                if let proposal = message.proposal {
                    snapshot(proposal)
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
            .frame(maxWidth: 520, alignment: .trailing)
        }
    }

    private func systemBubble(_ message: TradeThreadMessage) -> some View {
        Text(message.text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
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
        VStack(spacing: 10) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)

            verdictRow(partner: partner)
            blockerRow(partner: partner)
            packageEditor(partner: partner)
            actionButtons
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 720)
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
                week: career.currentWeek
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

    @ViewBuilder
    private func blockerRow(partner: Team) -> some View {
        let blockers = currentBlockers()
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
                    accentColor: accentColor
                ) {
                    toggle(id: player.id, in: selectedPlayers)
                }
            }

            ForEach(picks) { pick in
                TradeAssetToggleRow(
                    label: TradeAssetFormat.pickLabel(pick),
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                if let thread, let proposal = builtProposal() {
                    sendOffer(proposal, on: thread)
                }
            } label: {
                Text(thread?.round == 0 ? "Send Offer" : "Counter")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(hasAssets ? Color.backgroundPrimary : Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(hasAssets ? Color.accentGold : Color.backgroundTertiary)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!hasAssets)

            if thread?.pendingCounter != nil {
                Button {
                    acceptCounter()
                } label: {
                    Text("Accept Theirs")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.success)
                        )
                }
                .buttonStyle(.plain)
            }

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
            .buttonStyle(.plain)
        }
    }

    private var closedFooter: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)
            Text(closedFooterText)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .background(Color.backgroundSecondary)
    }

    private var closedFooterText: String {
        guard let thread else { return "" }
        switch thread.status {
        case .agreed:     return "Terms are agreed. Close this screen and the league office files the trade."
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
            week: career.currentWeek,
            // Task #36: the round the user's line just landed in drives the GM's
            // concession curve — his first counter holds near the opening ask,
            // every further one walks toward the bar he signs at.
            round: updated.round
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
        thread = updated
        career.upsertTradeThread(updated)
        try? modelContext.save()
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
