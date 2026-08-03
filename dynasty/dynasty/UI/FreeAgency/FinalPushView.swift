import SwiftUI
import SwiftData

// MARK: - Re-Sign Response

enum ReSignResponse {
    case accepted
    case countered(salary: Int, years: Int, reason: String)
    case rejected(reason: String)
    /// R22: a hardliner agent was insulted — talks are dead for the offseason.
    case brokenOff(reason: String)
}

// MARK: - FinalPushView

struct FinalPushView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var expiringPlayers: [Player] = []
    @State private var allPlayers: [Player] = []
    @State private var allTeams: [Team] = []
    @State private var decisions: [UUID: PlayerDecisionState] = [:]
    @State private var showLeagueYearConfirm = false
    /// R23 — legal-tampering rumors for the top upcoming FAs (league-wide).
    @State private var tamperingRumors: [TamperingRumorEngine.TamperingRumor] = []

    /// The player whose agent is on the phone. Non-nil while the Contact Agent
    /// thread is open.
    @State private var negotiationPlayer: Player?

    /// `DraftReputation.ownerTrust` — one of the five inputs to the GM factor.
    @State private var ownerTrust: Int = 70

    // MARK: - Economy Inputs
    //
    // Quick Offer and Contact Agent are two doors into ONE demand model, so
    // both have to hand it the same world.

    private var gmStanding: GMStanding {
        GMStanding.from(career: career, ownerTrust: ownerTrust)
    }

    /// The club and the season the demand model reads. Final Push runs after
    /// the season, so the record is the one just completed.
    private func reSignSituation(for player: Player) -> NegotiationSituation {
        let wins = team?.wins ?? 0
        let losses = team?.losses ?? 0
        // "Contender" comes from `ContractNegotiationEngine.isContender` (the
        // default when the parameter is omitted) rather than being spelled out
        // here — this screen used to carry its own copy of the threshold, which
        // meant the ring-chaser's exit condition and this screen agreed only by
        // coincidence.
        return ContractNegotiationEngine.situation(
            for: player,
            season: career.currentSeason,
            teamWins: wins,
            teamLosses: losses,
            weeksPlayed: max(wins + losses, career.currentWeek)
        )
    }

    struct PlayerDecisionState {
        enum Status {
            case pending
            case offering(salary: Int, years: Int)
            case responded(response: ReSignResponse)
            case reSignedAccepted
            case letWalk
            /// R22: kept for one year via the franchise tag.
            case tagged(salary: Int)
        }
        var status: Status = .pending
        var offerSalary: Int = 0
        var offerYears: Int = 2
        /// R22: how many offers the GM has submitted (agents have finite patience).
        var offerRounds: Int = 0
        /// The agent's STANDING number in this quick-offer conversation. Every
        /// grade is measured against it rather than against raw market value —
        /// that is what makes this button and the Contact Agent button next to
        /// it negotiate against the same price.
        var standingAsk: NegotiationOfferSnapshot?
        /// Lowballs absorbed, so the insult ratchet and the patience cost work
        /// here exactly as they do in the chat.
        var insultCount: Int = 0
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if let team {
                ScrollView {
                    VStack(spacing: 24) {
                        headerCard(team: team)

                        if !tamperingRumors.isEmpty {
                            tamperingBuzzCard
                        }

                        if expiringPlayers.isEmpty {
                            noExpiringCard
                        } else {
                            ForEach(expiringPlayers, id: \.id) { player in
                                expiringPlayerCard(player: player, team: team)
                            }
                        }

                        startLeagueYearButton
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ProgressView()
                    .tint(Color.accentGold)
            }
        }
        .navigationTitle("Final Push")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
        .alert("Start New League Year?", isPresented: $showLeagueYearConfirm) {
            Button("Start New League Year") { advanceToLeagueYear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            let undecided = expiringPlayers.filter { decisions[$0.id]?.status == nil || isPending($0.id) }.count
            Text(undecided > 0
                 ? "\(undecided) undecided player\(undecided == 1 ? "" : "s") will hit the open market."
                 : "All decisions made. Proceed to advance contracts.")
        }
        .fullScreenCover(item: $negotiationPlayer) { player in
            // ContractNegotiationView supplies its own "Close" toolbar item, so
            // the wrapper must NOT add a second one.
            NavigationStack {
                ContractNegotiationView(
                    player: player,
                    negotiationType: .extend,
                    teamCapSpace: max(0, team?.availableCap ?? 0),
                    onDealCompleted: { offer in
                        guard let team else { return }
                        // The same execution path the Quick Offer flow uses, so
                        // a deal struck in the chat lands on the cap and the
                        // roster identically — and, unlike `signFreeAgent`,
                        // this one has room for the structure that was actually
                        // negotiated (bonus, guarantee, no-trade clause) instead
                        // of drawing a fresh random bonus and hardcoding
                        // `noTrade: false`.
                        ContractEngine.applyNegotiatedDeal(
                            player: player,
                            team: team,
                            offer: offer,
                            application: .replaceContract,
                            capMode: career.capMode,
                            modelContext: modelContext
                        )
                        try? modelContext.save()
                        FASigningTracker.trackSigning(player.id)
                        generateStorylinesForSigning(player: player, team: team)
                        decisions[player.id, default: PlayerDecisionState()].status = .reSignedAccepted
                        // No dismiss — the thread shows the signed card and the
                        // user closes it with Done.
                    }
                )
            }
        }
    }

    // MARK: - Header

    private func headerCard(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: 15))
                Text("Final Push \u{2014} Re-sign or Let Walk")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Text("Make final offers to your expiring players before the market opens. Compare with the best available free agents at each position.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)

            HStack(spacing: 20) {
                statPill(label: "Expiring", value: "\(expiringPlayers.count)", color: .warning)
                statPill(label: "Cap Space", value: formatMillions(team.availableCap), color: team.availableCap > 0 ? .success : .danger)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - R23: Legal Tampering Buzz

    /// Pre-market intel: projected prices and early suitors for the top
    /// upcoming FAs, quoted from the same model the live market uses. Own
    /// expiring players are flagged — this is the last exclusive window.
    private var tamperingBuzzCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(Color.warning)
                    .font(.system(size: 14))
                Text("Legal Tampering Buzz")
                    .font(.headline)
                    .foregroundStyle(Color.warning)
                Spacer()
                Text("LEAGUE SOURCES")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            Text("Numbers already leaking ahead of the market. Names flagged in gold are YOUR expiring players — this is your last exclusive shot at them.")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                ForEach(tamperingRumors) { rumor in
                    tamperingRumorRow(rumor)
                    if rumor.id != tamperingRumors.last?.id {
                        Divider().overlay(Color.surfaceBorder.opacity(0.5))
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    private func tamperingRumorRow(_ rumor: TamperingRumorEngine.TamperingRumor) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(rumor.position)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 28)
                    .padding(.vertical, 2)
                    .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 3))
                Text(rumor.playerName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rumor.isOwnPlayer ? Color.accentGold : Color.textPrimary)
                    .lineLimit(1)
                if rumor.isOwnPlayer {
                    Text("YOURS")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentGold, in: Capsule())
                }
                Text("\(rumor.overall) OVR")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.forRating(rumor.overall))
                Spacer()
                Text("~\(formatMillions(rumor.projectedSalary))/yr")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.warning)
            }
            HStack(spacing: 6) {
                if rumor.suitorAbbrs.isEmpty {
                    Text("Market still forming")
                        .font(.system(size: 9).italic())
                        .foregroundStyle(Color.textTertiary)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 7))
                        Text("\(rumor.suitorAbbrs.joined(separator: ", ")) circling")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(Color.danger)
                }
                Text("\u{2022} \(TamperingRumorEngine.motivationBlurb(rumor.motivation))")
                    .font(.system(size: 9).italic())
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - No Expiring

    private var noExpiringCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.success)
            Text("No Expiring Contracts")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text("All your players are under contract. Proceed to start the new league year.")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
        .overlay(RoundedRectangle(cornerRadius: DSCornerRadius.card).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Expiring Player Card

    private func expiringPlayerCard(player: Player, team: Team) -> some View {
        let state = decisions[player.id] ?? PlayerDecisionState()
        // The league's ACTUAL cap, not the 265 000 default. Two screens quoting
        // two different market values for the same man — and diverging further
        // every year the cap compounds — is the bug this argument closes.
        let marketValue = ContractEngine.estimateMarketValue(player: player, salaryCap: team.salaryCap)
        let faAlternatives = ContractEngine.previewFreeAgents(
            allPlayers: allPlayers,
            allTeams: allTeams,
            playerTeamID: career.teamID ?? UUID(),
            position: player.position,
            limit: 3
        )

        return VStack(alignment: .leading, spacing: 0) {
            // Player header
            HStack(spacing: 12) {
                Text(player.position.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 34)
                    .padding(.vertical, 4)
                    .background(positionSideColor(player.position), in: RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 8) {
                        Text("\(player.overall) OVR")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.forRating(player.overall))
                        Text("Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(formatMillions(player.annualSalary) + "/yr")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                        motivationBadge(player.personality.motivation)
                    }
                    // R22: agent identity + negotiation style
                    agentBadge(for: player)
                }

                Spacer()

                Text("~\(formatMillions(marketValue))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentBlue)
                Text("MKT")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.accentBlue.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            // FA alternatives column
            if !faAlternatives.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption2)
                            .foregroundStyle(Color.accentBlue)
                        Text("Top FA alternatives:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentBlue)
                    }

                    ForEach(faAlternatives, id: \.playerID) { fa in
                        HStack(spacing: 8) {
                            Text(fa.name)
                                .font(.caption)
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            Text("(\(fa.currentTeamAbbr))")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Spacer()
                            Text("\(fa.overall) OVR")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Color.forRating(fa.overall))
                            Text("~\(formatMillions(fa.estimatedSalary))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.backgroundTertiary.opacity(0.3))

                Divider().overlay(Color.surfaceBorder.opacity(0.5))
            }

            // Action area based on state
            actionArea(player: player, state: state, marketValue: marketValue)
        }
        .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.surfaceBorder, lineWidth: 1))
    }

    // MARK: - Action Area

    @ViewBuilder
    private func actionArea(player: Player, state: PlayerDecisionState, marketValue: Int) -> some View {
        switch state.status {
        case .pending:
            pendingActions(player: player, marketValue: marketValue)

        case .offering(let salary, let years):
            offeringView(player: player, salary: salary, years: years, marketValue: marketValue)

        case .responded(let response):
            responseView(player: player, response: response, marketValue: marketValue)

        case .reSignedAccepted:
            resolvedBadge(text: "Re-signed", icon: "checkmark.circle.fill", color: .success)

        case .letWalk:
            resolvedBadge(text: "Will hit free agency", icon: "figure.walk.departure", color: .textTertiary)

        case .tagged(let salary):
            resolvedBadge(
                text: "Franchise tagged — 1 yr, \(formatMillions(salary))",
                icon: "tag.fill",
                color: .accentGold
            )
        }
    }

    @ViewBuilder
    private func pendingActions(player: Player, marketValue: Int) -> some View {
        // R22: a hardliner agent who was insulted earlier this offseason still
        // refuses to do business — but the ROW does not announce it, in ANY
        // form. Before this wave it printed "isn't returning your calls" right
        // here; then it merely hid the gold Quick Offer button on exactly the
        // frozen rows, which is the same leak one control over. Every row now
        // carries the identical pair of buttons and the agent says it himself,
        // in character, when you contact him — or when you submit the offer.
        HStack(spacing: 12) {
            Button {
                negotiationPlayer = player
            } label: {
                Label(ContactAgentEntry.title, systemImage: ContactAgentEntry.icon)
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentBlue)

            Button {
                var state = PlayerDecisionState()
                state.status = .offering(salary: marketValue, years: 2)
                state.offerSalary = marketValue
                state.offerYears = 2
                decisions[player.id] = state
            } label: {
                Label("Quick Offer", systemImage: "signature")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(Color.accentGold)

            // R22: franchise tag straight from the re-sign flow (1 per offseason).
            if !hasUsedFranchiseTag {
                Button {
                    applyFranchiseTag(to: player)
                } label: {
                    Label("Tag (\(formatMillions(franchiseTagValue(for: player.position))))", systemImage: "tag")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(Color.accentGold)
            }

            Button {
                var state = PlayerDecisionState()
                state.status = .letWalk
                decisions[player.id] = state
                applyLetWalkPenaltyIfNeeded(player: player)
            } label: {
                Label("Let Walk", systemImage: "figure.walk.departure")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func offeringView(player: Player, salary: Int, years: Int, marketValue: Int) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Offer:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)

                Stepper("\(years)yr", value: Binding(
                    get: { decisions[player.id]?.offerYears ?? years },
                    set: { newVal in
                        decisions[player.id]?.offerYears = newVal
                        decisions[player.id]?.status = .offering(salary: decisions[player.id]?.offerSalary ?? salary, years: newVal)
                    }
                ), in: 1...5)
                .font(.caption.weight(.semibold).monospacedDigit())

                Spacer()

                Text(formatMillions(salary) + "/yr")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }

            // Salary slider
            HStack(spacing: 8) {
                Text(formatMillions(500))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                Slider(
                    value: Binding(
                        get: { Double(decisions[player.id]?.offerSalary ?? salary) },
                        set: { newVal in
                            let rounded = Int((newVal / 500).rounded()) * 500
                            decisions[player.id]?.offerSalary = rounded
                            decisions[player.id]?.status = .offering(salary: rounded, years: decisions[player.id]?.offerYears ?? years)
                        }
                    ),
                    in: 500...75000,
                    step: 500
                )
                .tint(Color.accentGold)
                Text(formatMillions(75000))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }

            HStack(spacing: 12) {
                Button("Submit Offer") {
                    let currentSalary = decisions[player.id]?.offerSalary ?? salary
                    let currentYears = decisions[player.id]?.offerYears ?? years
                    decisions[player.id]?.offerRounds += 1
                    let outcome = Self.evaluateReSignOffer(
                        player: player,
                        offeredSalary: currentSalary,
                        offeredYears: currentYears,
                        salaryCap: team?.salaryCap ?? 265_000,
                        situation: reSignSituation(for: player),
                        standing: gmStanding,
                        standingAsk: decisions[player.id]?.standingAsk?.offer,
                        roundNumber: decisions[player.id]?.offerRounds ?? 1,
                        insultCount: decisions[player.id]?.insultCount ?? 0
                    )
                    if case .brokenOff = outcome.response {
                        // R22: hardliner freeze-out persists for the offseason.
                        NegotiationLockRegistry.lock(player.id)
                    }
                    // Pestering costs the man morale here exactly as it does in
                    // the chat: the ask ratcheted inside `evaluateReSignOffer`,
                    // and the engine cannot reach the player row to do the rest.
                    // Detected by the count moving on a REJECTED offer — the
                    // only way that happens is the refusal path.
                    if case .rejected = outcome.response,
                       outcome.insultCount > (decisions[player.id]?.insultCount ?? 0) {
                        player.morale = max(1, min(100,
                            player.morale - ContractNegotiationEngine.pesterMoraleCost))
                    }
                    decisions[player.id]?.insultCount = outcome.insultCount
                    if let counter = outcome.standingAsk {
                        decisions[player.id]?.standingAsk = NegotiationOfferSnapshot(counter)
                    }
                    decisions[player.id]?.status = .responded(response: outcome.response)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentGold)
                .font(.caption.weight(.semibold))

                Button("Cancel") {
                    decisions[player.id]?.status = .pending
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func responseView(player: Player, response: ReSignResponse, marketValue: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch response {
            case .accepted:
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.success)
                    Text("\(player.fullName) accepted your offer!")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.success)
                }
                HStack(spacing: 12) {
                    Button("Finalize") {
                        if let team {
                            let salary = decisions[player.id]?.offerSalary ?? marketValue
                            let years = decisions[player.id]?.offerYears ?? 2
                            finalizeReSign(
                                player: player,
                                team: team,
                                salary: salary,
                                years: years
                            )
                            FASigningTracker.trackSigning(player.id)
                            generateStorylinesForSigning(player: player, team: team)
                            decisions[player.id]?.status = .reSignedAccepted
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.success)
                    .font(.caption.weight(.semibold))
                }

            case .countered(let counterSalary, let counterYears, let reason):
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Color.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(player.fullName): \"\(reason)\"")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.warning)
                        Text("Counter: \(formatMillions(counterSalary))/yr \u{00B7} \(counterYears) years")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                HStack(spacing: 12) {
                    Button("Accept Counter") {
                        if let team {
                            finalizeReSign(
                                player: player,
                                team: team,
                                salary: counterSalary,
                                years: counterYears
                            )
                            FASigningTracker.trackSigning(player.id)
                            generateStorylinesForSigning(player: player, team: team)
                            decisions[player.id]?.status = .reSignedAccepted
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.accentGold)
                    .font(.caption.weight(.semibold))

                    Button("Revise") {
                        decisions[player.id]?.offerSalary = counterSalary
                        decisions[player.id]?.offerYears = counterYears
                        decisions[player.id]?.status = .offering(salary: counterSalary, years: counterYears)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))

                    Button("Let Walk") {
                        decisions[player.id]?.status = .letWalk
                        applyLetWalkPenaltyIfNeeded(player: player)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
                }

            case .rejected(let reason):
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(player.fullName) declined")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.danger)
                        Text("\"\(reason)\"")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .italic()
                    }
                }
                Button("Understood") {
                    decisions[player.id]?.status = .letWalk
                    applyLetWalkPenaltyIfNeeded(player: player)
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))

            case .brokenOff(let reason):
                // R22: hardliner agent cut off talks for the offseason.
                HStack(spacing: 8) {
                    Image(systemName: "phone.down.fill")
                        .foregroundStyle(Color.danger)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(AgentPersona.agentName(for: player.id)) ended all talks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.danger)
                        Text("\"\(reason)\"")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                            .italic()
                    }
                }
                Button("Understood") {
                    decisions[player.id]?.status = .letWalk
                    applyLetWalkPenaltyIfNeeded(player: player)
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func resolvedBadge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Start League Year Button

    private var startLeagueYearButton: some View {
        VStack(spacing: 8) {
            Button {
                showLeagueYearConfirm = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3)
                    Text("START NEW LEAGUE YEAR")
                        .font(.headline)
                }
                .foregroundStyle(Color.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Text("All remaining undecided players will hit the open market")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Re-Sign Evaluation Logic

    /// One graded quick offer, plus the conversation state that has to survive
    /// to the next one.
    struct ReSignOutcome {
        let response: ReSignResponse
        /// The agent's number after this round — what the NEXT offer is graded
        /// against.
        let standingAsk: NegotiationOffer?
        let insultCount: Int
    }

    /// **Quick Offer, graded by the demand model.**
    ///
    /// This used to be a third, independent price function living in a View:
    /// a threshold of `0.80 − 0.12 loyalty − motivationMod − archetypeMod +
    /// persona.reSignThresholdShift` applied to `offeredSalary / marketValue`.
    /// It knew nothing of the agent's floor, the insult ratchet, patience, the
    /// GM's standing, the tag, a holdout, or the theatre in an opening ask — and
    /// it disagreed violently with the button beside it. A cooperative,
    /// loyalty-motivated team leader accepted at **0.40 of market** through
    /// Quick Offer while the Contact Agent thread on the same row would not sign
    /// him below ~0.73. Two buttons, one player, 1.8× apart.
    ///
    /// It also had no concept of refusal, so a player whose agent "won't take
    /// the call" signed through the control next to the one that said so.
    ///
    /// Everything numeric now comes from `ContractNegotiationEngine`; this
    /// function only translates the engine's verdict into the four states this
    /// screen renders.
    static func evaluateReSignOffer(
        player: Player,
        offeredSalary: Int,
        offeredYears: Int,
        salaryCap: Int,
        situation: NegotiationSituation,
        standing: GMStanding,
        standingAsk: NegotiationOffer?,
        roundNumber: Int = 1,
        insultCount: Int = 0
    ) -> ReSignOutcome {
        // The freeze-out is a first-class outcome here too, not a hidden button.
        if NegotiationLockRegistry.isLocked(player.id) {
            return ReSignOutcome(
                response: .brokenOff(
                    reason: "\(AgentPersona.agentName(for: player.id)) isn't taking calls about \(player.firstName) until next league year."
                ),
                standingAsk: standingAsk,
                insultCount: insultCount
            )
        }

        let demand = ContractNegotiationEngine.demand(
            player: player,
            negotiationType: .extend,
            salaryCap: salaryCap,
            situation: situation,
            standing: standing,
            insultCount: insultCount
        )

        if demand.isRefusing {
            // **Pestering, Quick-Offer edition.** Same rule as the chat: the
            // door being shut does not stop the club offering, and the offer
            // does not stop the door being shut. `respond` books the insult and
            // ratchets the ask, and the count rides back out so the NEXT Quick
            // Offer is graded against the hardened number — which is the only
            // thing that makes repeated pushing cost anything on this screen.
            let response = ContractNegotiationEngine.respond(
                gmOffer: NegotiationOffer(
                    years: offeredYears,
                    annualSalary: offeredSalary,
                    signingBonus: 0,
                    guaranteedPercent: 0,
                    noTradeClause: false
                ),
                player: player,
                demand: demand,
                previousAgentOffer: standingAsk ?? demand.openingOffer,
                roundNumber: roundNumber
            )
            return ReSignOutcome(
                response: .rejected(reason: refusalReason(player: player, reason: demand.refusalReason)),
                standingAsk: standingAsk,
                insultCount: response.demand.insultCount
            )
        }

        let ask = standingAsk ?? demand.openingOffer
        let gmOffer = NegotiationOffer(
            years: offeredYears,
            annualSalary: offeredSalary,
            signingBonus: 0,
            guaranteedPercent: ask.guaranteedPercent,
            noTradeClause: false
        )

        let result = ContractNegotiationEngine.respond(
            gmOffer: gmOffer,
            player: player,
            demand: demand,
            previousAgentOffer: ask,
            roundNumber: roundNumber
        )

        let persona = demand.persona

        switch result.outcome {
        case .dealReached:
            return ReSignOutcome(response: .accepted, standingAsk: ask, insultCount: result.demand.insultCount)

        case .negotiationsBrokenOff:
            return ReSignOutcome(
                response: .brokenOff(
                    reason: "That offer is an insult. \(player.firstName) is done talking to this front office until next year."
                ),
                standingAsk: ask,
                insultCount: result.demand.insultCount
            )

        case .playerWalked:
            return ReSignOutcome(
                response: .rejected(
                    reason: rejectReason(player: player, askPerYear: ask.annualCapHit)
                ),
                standingAsk: ask,
                insultCount: result.demand.insultCount
            )

        case .pending, .walkedAway:
            guard let counter = result.counterOffer else {
                return ReSignOutcome(
                    response: .rejected(
                        reason: rejectReason(player: player, askPerYear: ask.annualCapHit)
                    ),
                    standingAsk: ask,
                    insultCount: result.demand.insultCount
                )
            }
            return ReSignOutcome(
                response: .countered(
                    salary: counter.annualCapHit,
                    years: counter.years,
                    reason: result.isYearsPushback
                        ? "At \(player.age), \(player.firstName) won't sign a \(offeredYears)-year deal"
                        : counterReason(player: player, persona: persona)
                ),
                standingAsk: counter,
                insultCount: result.demand.insultCount
            )
        }
    }

    /// The refusal, in this screen's shorter voice. The wording is the chat
    /// layer's; the verdict behind it is the engine's.
    private static func refusalReason(player: Player, reason: AgentRefusalReason?) -> String {
        guard let reason else { return "\(player.firstName)'s camp isn't negotiating right now" }
        switch reason {
        case .benched:
            return "He hasn't taken a meaningful snap all year \u{2014} his camp won't discuss an extension"
        case .losingCulture:
            return "He has no interest in signing up for another rebuild"
        case .wantsOut:
            return "\(player.firstName) has already decided he wants out"
        case .ridingIntoRetirement:
            return "He's weighing retirement and won't commit to a new deal"
        case .ringChasing:
            // Says "not the money" explicitly. On a screen whose whole idiom is
            // "offer more", a refusal that does not close the door on money is
            // read as a hard negotiation and answered with a bigger number.
            return "He wants to play for a contender \u{2014} no offer changes that while this team is going nowhere"
        }
    }

    private static func counterReason(player: Player, persona: AgentPersona) -> String {
        // R22: the agent's persona colors the justification.
        switch persona {
        case .hardliner:
            return "\(player.firstName) wants starter money \u{2014} this is the number"
        case .loyalist:
            return "He took a discount to stay \u{2014} meet us halfway"
        case .cooperative:
            switch player.personality.motivation {
            case .money:   return "Wants more money \u{2014} feels undervalued"
            case .winning: return "Needs assurance this team can compete"
            case .stats:   return "Wants a bigger role guarantee"
            case .loyalty: return "Willing to stay, but needs fair compensation"
            case .fame:    return "Looking for a market-value deal"
            }
        }
    }

    /// `askPerYear` is the AGENT'S standing number, which is what he actually
    /// walked away from — quoting raw market value here would name a price
    /// neither side was arguing about.
    private static func rejectReason(player: Player, askPerYear: Int) -> String {
        switch player.personality.motivation {
        case .money:
            return "Wants to test the free agent market \u{2014} asking price is \(formatMillionsStatic(askPerYear))"
        case .winning:
            return "Looking for a championship contender"
        case .stats:
            return "Wants a bigger role elsewhere"
        case .loyalty:
            return "Feels undervalued \u{2014} expected at least \(formatMillionsStatic(Int(Double(askPerYear) * 0.9)))"
        case .fame:
            return "Seeking a big-market team for more exposure"
        }
    }

    // MARK: - Agent Persona (R22)

    /// Compact agent chip: name + deterministic negotiation style.
    private func agentBadge(for player: Player) -> some View {
        let persona = AgentPersona.forPlayer(id: player.id)
        let color: Color = {
            switch persona {
            case .hardliner:   return .danger
            case .cooperative: return .success
            case .loyalist:    return .accentGold
            }
        }()
        return HStack(spacing: 4) {
            Image(systemName: persona.symbolName)
                .font(.system(size: 8))
            Text("Agent: \(AgentPersona.agentName(for: player.id))")
                .font(.system(size: 9, weight: .semibold))
            Text(persona.styleLabel)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(color.opacity(0.9))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.1), in: Capsule())
    }

    // MARK: - Franchise Tag (R22)

    /// Whether any player on the user's team already carries this season's tag.
    private var hasUsedFranchiseTag: Bool {
        guard let teamID = career.teamID else { return false }
        return allPlayers.contains { $0.teamID == teamID && $0.isFranchiseTagged }
            || expiringPlayers.contains { $0.isFranchiseTagged }
    }

    /// Tag cost for a position: average of the league's top-5 salaries there.
    private func franchiseTagValue(for position: Position) -> Int {
        let positionSalaries = allPlayers
            .filter { $0.position == position && $0.annualSalary > 0 }
            .map { $0.annualSalary }
        let value = ContractEngine.franchiseTagValue(
            position: position,
            topSalaries: positionSalaries,
            capMode: career.capMode
        )
        return career.capMode == .sandbox ? value : max(value, 5_000)
    }

    /// Applies the franchise tag to an expiring player straight from the
    /// re-sign flow. Player stays for 1 year at the tag number (morale -10
    /// is applied inside ContractEngine — nobody wants the tag).
    private func applyFranchiseTag(to player: Player) {
        guard let team, !hasUsedFranchiseTag else { return }
        let tagCost = franchiseTagValue(for: player.position)
        ContractEngine.applyFranchiseTag(
            player: player,
            tagValue: tagCost,
            team: team,
            capMode: career.capMode
        )
        try? modelContext.save()
        // Deliberately does NOT set `franchiseTagVisited`. That flag means "the
        // user has been through the tag screen in THIS Review Roster phase" and
        // it is only cleared when Review Roster is left — so setting it here, a
        // phase later in free agency, silently pre-ticked next cycle's
        // "Franchise Tag Decisions" task before the user had seen it. The tag
        // itself is the evidence the task checks for anyway.
        var state = decisions[player.id] ?? PlayerDecisionState()
        state.status = .tagged(salary: player.annualSalary)
        decisions[player.id] = state
    }

    // MARK: - Helpers

    /// Books a Quick Offer re-sign. `signFreeAgent` is the wrong tool for a man
    /// who is ALREADY on the roster: it charges the club the full new cap hit
    /// without crediting the salary the club was already carrying, and in
    /// realistic mode it inserts a second `Contract` row alongside the live one.
    private func finalizeReSign(player: Player, team: Team, salary: Int, years: Int) {
        let offer = NegotiationOffer(
            years: years,
            annualSalary: salary,
            signingBonus: 0,
            guaranteedPercent: 0,
            noTradeClause: false
        )
        ContractEngine.applyNegotiatedDeal(
            player: player,
            team: team,
            offer: offer,
            application: .replaceContract,
            capMode: career.capMode,
            modelContext: modelContext
        )
        try? modelContext.save()
    }

    private func isPending(_ playerID: UUID) -> Bool {
        guard let state = decisions[playerID] else { return true }
        if case .pending = state.status { return true }
        return false
    }

    private func motivationBadge(_ motivation: Motivation) -> some View {
        let (icon, label): (String, String) = {
            switch motivation {
            case .money:   return ("dollarsign.circle", "Money")
            case .winning: return ("trophy", "Winning")
            case .stats:   return ("chart.bar", "Stats")
            case .loyalty: return ("heart", "Loyalty")
            case .fame:    return ("star", "Fame")
            }
        }()

        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(label)
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(Color.accentGold.opacity(0.8))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.accentGold.opacity(0.1), in: Capsule())
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func formatMillions(_ thousands: Int) -> String {
        Self.formatMillionsStatic(thousands)
    }

    private static func formatMillionsStatic(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    private func advanceToLeagueYear() {
        career.freeAgencyStep = FreeAgencyStep.newLeagueYear.rawValue
    }

    // MARK: - FA Drama Storyline + Penalty Wire-up

    /// Generates FA Drama storyline events (revenge / loyalty / coach reunion / hometown /
    /// mentor pair / community / milestone) for a re-signed player.
    private func generateStorylinesForSigning(player: Player, team: Team) {
        let teamID = team.id
        let coachDesc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        let teamCoaches = (try? modelContext.fetch(coachDesc)) ?? []

        var teamAbbrevs: [UUID: String] = [:]
        for t in allTeams { teamAbbrevs[t.id] = t.abbreviation }

        let unsignedFAs = allPlayers.filter { $0.teamID == nil && !$0.isRetired }

        FreeAgencyEngine.generateStorylineEventsForSigning(
            player: player,
            signingTeam: team,
            teamCoaches: teamCoaches,
            teamRegion: nil,
            teamAbbrevs: teamAbbrevs,
            allFAs: unsignedFAs,
            modelContext: modelContext
        )
    }

    /// FA Drama: applies the loyalty let-walk media penalty when a 4+ year vet
    /// is allowed to hit the open market. Persists a "disrespected legend"
    /// FAStorylineEvent and tweaks owner satisfaction + career reputation.
    private func applyLetWalkPenaltyIfNeeded(player: Player) {
        guard player.loyaltyYears >= LoyaltyEngine.loyaltyThresholdYears else { return }

        let penalty = LoyaltyEngine.letWalkPenalty(player: player)

        if let owner = team?.owner {
            owner.satisfaction = max(0, min(100, owner.satisfaction + penalty.ownerTrust))
        }
        // Fan mood penalty leaks into the career reputation.
        career.reputation = max(0, min(100, career.reputation + penalty.fanMood / 2))

        if let evt = LoyaltyEngine.generateLetWalkEvent(player: player) {
            evt.careerID = career.id
            modelContext.insert(evt)
        }
        try? modelContext.save()
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        guard let fetchedTeamID = team?.id else { return }

        // Expiring players on this team
        var playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == fetchedTeamID && $0.contractYearsRemaining <= 1 }
        )
        playerDesc.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        expiringPlayers = (try? modelContext.fetch(playerDesc)) ?? []

        // Initialize decisions
        for player in expiringPlayers where decisions[player.id] == nil {
            decisions[player.id] = PlayerDecisionState()
        }

        // All players + teams for FA preview
        let cid = career.id
        allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        allTeams = (try? modelContext.fetch(FetchDescriptor<Team>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []

        // Owner trust — one of the five GM-standing inputs the demand model
        // reads. Absent means the owner has never reacted to anything, which
        // must cost nothing: `GMStanding`'s neutral is 70, not 50.
        if let reputation = (try? modelContext.fetch(FetchDescriptor<DraftReputation>(
            predicate: #Predicate { $0.careerID == cid }
        )))?.max(by: { $0.seasonYear < $1.seasonYear }) {
            ownerTrust = reputation.ownerTrust
        }

        // R23: legal-tampering buzz — same pricing/need model the market uses.
        tamperingRumors = TamperingRumorEngine.generateRumors(
            allPlayers: allPlayers,
            allTeams: allTeams,
            userTeamID: career.teamID
        )
    }
}
