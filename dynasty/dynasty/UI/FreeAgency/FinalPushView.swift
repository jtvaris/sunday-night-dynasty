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
        let marketValue = ContractEngine.estimateMarketValue(player: player)
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
        if NegotiationLockRegistry.isLocked(player.id) {
            // R22: a hardliner agent froze talks earlier this offseason.
            HStack(spacing: 8) {
                Image(systemName: "phone.down.fill")
                    .foregroundStyle(Color.danger)
                Text("\(AgentPersona.agentName(for: player.id)) isn't returning your calls this offseason.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.danger)
                Spacer()
                Button {
                    decisions[player.id]?.status = .letWalk
                    applyLetWalkPenaltyIfNeeded(player: player)
                } label: {
                    Label("Let Walk", systemImage: "figure.walk.departure")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        } else {
            HStack(spacing: 12) {
                Button {
                    var state = PlayerDecisionState()
                    state.status = .offering(salary: marketValue, years: 2)
                    state.offerSalary = marketValue
                    state.offerYears = 2
                    decisions[player.id] = state
                } label: {
                    Label("Make Offer", systemImage: "signature")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
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
                    let response = Self.evaluateReSignOffer(
                        player: player,
                        offeredSalary: currentSalary,
                        offeredYears: currentYears,
                        marketValue: marketValue,
                        teamWins: career.totalWins,
                        teamReputation: career.reputation,
                        roundNumber: decisions[player.id]?.offerRounds ?? 1
                    )
                    if case .brokenOff = response {
                        // R22: hardliner freeze-out persists for the offseason.
                        NegotiationLockRegistry.lock(player.id)
                    }
                    decisions[player.id]?.status = .responded(response: response)
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
                            FreeAgencyEngine.signFreeAgent(
                                player: player,
                                team: team,
                                years: years,
                                salary: salary,
                                capMode: career.capMode,
                                modelContext: modelContext
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
                            FreeAgencyEngine.signFreeAgent(
                                player: player,
                                team: team,
                                years: counterYears,
                                salary: counterSalary,
                                capMode: career.capMode,
                                modelContext: modelContext
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

    static func evaluateReSignOffer(
        player: Player,
        offeredSalary: Int,
        offeredYears: Int,
        marketValue: Int,
        teamWins: Int,
        teamReputation: Int,
        roundNumber: Int = 1
    ) -> ReSignResponse {
        guard marketValue > 0 else { return .accepted }
        let ratio = Double(offeredSalary) / Double(marketValue)

        // R22: the agent persona shifts the bar and caps patience.
        let persona = AgentPersona.forPlayer(id: player.id)

        // R22: an insulting lowball to a hardliner kills talks for the offseason.
        if persona.breaksOffForSeason && ratio < 0.60 {
            return .brokenOff(
                reason: "That offer is an insult. \(player.firstName) is done talking to this front office until next year."
            )
        }

        // R22: agents have finite patience — past their limit they walk.
        if roundNumber > persona.maxRounds {
            return .rejected(
                reason: "We've gone back and forth enough. \(player.firstName) will test the open market."
            )
        }

        // Own team loyalty bonus
        let loyaltyBonus = 0.12

        // Motivation modifiers
        let motivationMod: Double = {
            switch player.personality.motivation {
            case .loyalty:  return 0.15
            case .money:    return -0.05
            case .winning:  return teamWins >= 10 ? 0.10 : -0.05
            case .fame:     return 0.0
            case .stats:    return 0.03
            }
        }()

        // Archetype modifiers
        let archetypeMod: Double = {
            switch player.personality.archetype {
            case .teamLeader, .mentor:      return 0.08
            case .quietProfessional:        return 0.05
            case .loneWolf, .dramaQueen:    return -0.05
            default:                        return 0.0
            }
        }()

        // R22: hardliner needs more, deal-maker/loyalist a bit less.
        let threshold = 0.80 - loyaltyBonus - motivationMod - archetypeMod
            + persona.reSignThresholdShift

        if ratio >= threshold {
            return .accepted
        } else if ratio >= threshold - 0.15 {
            let counterSalary = Int(Double(marketValue) * (threshold + 0.05))
            return .countered(
                salary: counterSalary,
                years: offeredYears,
                reason: counterReason(player: player, persona: persona)
            )
        } else {
            return .rejected(reason: rejectReason(player: player, offeredSalary: offeredSalary, marketValue: marketValue))
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

    private static func rejectReason(player: Player, offeredSalary: Int, marketValue: Int) -> String {
        switch player.personality.motivation {
        case .money:
            return "Wants to test the free agent market \u{2014} asking price is \(formatMillionsStatic(marketValue))"
        case .winning:
            return "Looking for a championship contender"
        case .stats:
            return "Wants a bigger role elsewhere"
        case .loyalty:
            return "Feels undervalued \u{2014} expected at least \(formatMillionsStatic(Int(Double(marketValue) * 0.9)))"
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
        UserDefaults.standard.set(true, forKey: "franchiseTagVisited")
        var state = decisions[player.id] ?? PlayerDecisionState()
        state.status = .tagged(salary: player.annualSalary)
        decisions[player.id] = state
    }

    // MARK: - Helpers

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
        allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []
        allTeams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []

        // R23: legal-tampering buzz — same pricing/need model the market uses.
        tamperingRumors = TamperingRumorEngine.generateRumors(
            allPlayers: allPlayers,
            allTeams: allTeams,
            userTeamID: career.teamID
        )
    }
}
