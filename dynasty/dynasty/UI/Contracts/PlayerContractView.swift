import SwiftUI
import SwiftData

struct PlayerContractView: View {

    @Bindable var player: Player
    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showCutAlert = false

    /// **The one sheet on this screen** (§2.8 + the house rule).
    ///
    /// The extension editor and the restructure quote were two
    /// `.sheet(isPresented:)` modifiers on the same node — the shape SwiftUI
    /// resolves by honouring one and dropping the other. They are peer
    /// side-tasks off the same actions list (edit a deal, take a quote), so they
    /// keep the same presentation weight and share one `.sheet(item:)` point.
    ///
    /// The pay-cut chat stays a `fullScreenCover` and that is deliberate: a
    /// negotiation has rounds, owns the screen and ends in a result, which is
    /// §2.8's definition of a process.
    private enum ContractSheet: String, Identifiable {
        /// #102 — the two cap-relief levers.
        case extend, restructure
        var id: String { rawValue }
    }

    @State private var activeSheet: ContractSheet?
    @State private var showPayCutChat = false
    @State private var team: Team?
    /// The club's roster, loaded alongside the club (#208 G1). The Cut button
    /// is a release door, and a release door has to be able to count the room
    /// it is about to empty — this screen had no roster in reach at all, which
    /// is how it shipped as one of the four ways to cut the last quarterback.
    @State private var roster: [Player] = []
    /// This player's detailed deal, when one exists. Realistic-mode signings
    /// mint a `Contract`; everyone else is priced off `annualSalary` by the
    /// engine's proxy.
    @State private var contract: Contract?

    /// Why the cut is closed, or `nil`. The engine owns the rule; this screen
    /// only renders its sentence.
    private var cutBlockReason: String? {
        guard let team else { return nil }
        return CapManagementEngine.releaseBlockReason(
            player: player,
            team: team,
            roster: roster
        )
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                playerOverviewSection
                currentContractSection
                marketValueSection
                if isOwnPlayer {
                    actionsSection
                }
                if career.capMode == .realistic {
                    realisticCapSection
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle(player.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadTeam() }
        .alert("Cut \(player.fullName)?", isPresented: $showCutAlert) {
            Button("Cut Player", role: .destructive) { cutPlayer() }
                .disabled(cutBlockReason != nil)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cutBlockReason ?? cutAlertMessage)
        }
        // The one sheet — see `ContractSheet`.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .extend:
                if let team {
                    NavigationStack {
                        ContractExtensionSheet(
                            player: player,
                            team: team,
                            capMode: career.capMode
                        )
                    }
                }
            case .restructure:
                RestructureQuoteSheet(
                    player: player,
                    quote: restructureQuote,
                    onConfirm: { applyRestructure() }
                )
            }
        }
        .fullScreenCover(isPresented: $showPayCutChat) {
            // The chat supplies its own "Close" toolbar item — the wrapper must
            // NOT add a second one.
            NavigationStack {
                ContractNegotiationView(
                    player: player,
                    negotiationType: .payCut,
                    teamCapSpace: max(0, team?.availableCap ?? 0),
                    onPayCutAgreed: { newSalary, moraleDelta in
                        applyPayCut(newSalary: newSalary, moraleDelta: moraleDelta)
                    }
                )
            }
        }
    }

    // MARK: - Sections

    private var playerOverviewSection: some View {
        Section("Player") {
            LabeledContent("Position") {
                positionBadge
            }
            LabeledContent("Age") {
                Text("\(player.age)")
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            LabeledContent("Overall") {
                Text("\(player.overall)")
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.forRating(player.overall))
            }
            .accessibilityLabel("Overall, \(player.overall)")
            LabeledContent("Experience") {
                Text(player.yearsPro == 0 ? "Rookie" : "\(player.yearsPro) yr\(player.yearsPro == 1 ? "" : "s") pro")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var currentContractSection: some View {
        Section("Current Contract") {
            LabeledContent("Annual Salary") {
                Text(formatMillions(player.annualSalary))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            LabeledContent("Years Remaining") {
                HStack(spacing: 6) {
                    Text("\(player.contractYearsRemaining)")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(yearsColor(player.contractYearsRemaining))
                    Text("year\(player.contractYearsRemaining == 1 ? "" : "s")")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            LabeledContent("Total Remaining") {
                Text(formatMillions(player.annualSalary * player.contractYearsRemaining))
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
            LabeledContent("Contract Status") {
                contractStatusLabel
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var marketValueSection: some View {
        Section("Market Value") {
            LabeledContent("Estimated Value") {
                Text(formatMillions(estimatedMarketValue))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            LabeledContent("Current vs. Market") {
                HStack(spacing: 6) {
                    Image(systemName: marketComparisonIcon)
                        .foregroundStyle(marketComparisonColor)
                    Text(marketComparisonLabel)
                        .foregroundStyle(marketComparisonColor)
                }
                .font(.subheadline)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var actionsSection: some View {
        Section("Actions") {
            // Every action below needs a club to act for; each engine call reads
            // `team` itself, so this is a presence gate rather than a binding.
            if team != nil {
                Button {
                    activeSheet = .extend
                } label: {
                    Label("Extend Contract", systemImage: "signature")
                        .foregroundStyle(Color.accentGold)
                }

                // #102 — the two cap-relief levers, on the screen that already
                // owns this man's contract. Same engines the Cap Compliance
                // workspace uses; this is the per-player door to them.
                if let quote = restructureQuote {
                    Button {
                        activeSheet = .restructure
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Restructure Contract", systemImage: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Color.accentGold)
                            Text("Frees \(formatMillions(quote.immediateRelief)) now, adds \(formatMillions(quote.proratedPerYear)) to each of the \(max(0, quote.yearsRemaining - 1)) years after this one")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }

                Button {
                    showPayCutChat = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Ask for Pay Cut", systemImage: "bubble.left.and.text.bubble.right")
                            .foregroundStyle(Color.accentBlue)
                        Text("His agent decides. A refusal is possible, and asking costs goodwill.")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                // #208 G1 — disabled with its reason under it, never a live
                // button beside a passive note. The reason is the engine's
                // sentence and it names the way out (sign or trade first).
                Button(role: .destructive) {
                    showCutAlert = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Cut Player", systemImage: "person.badge.minus")
                        if let reason = cutBlockReason {
                            Text(reason)
                                .font(.caption2)
                                .foregroundStyle(Color.warning)
                        }
                    }
                }
                .disabled(cutBlockReason != nil)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Cap Levers (#102)

    private var salaryCap: Int { team?.salaryCap ?? ContractEngine.openingSalaryCap }

    /// What a restructure would do to this deal, or `nil` when he is not a
    /// candidate. The engine is the authority; this screen only renders it.
    private var restructureQuote: ContractEngine.RestructureQuote? {
        ContractEngine.restructureQuote(
            player: player,
            contract: contract,
            capMode: career.capMode,
            salaryCap: salaryCap
        ).quote
    }

    private func applyRestructure() {
        ContractEngine.executeRestructure(
            player: player,
            team: team,
            contract: contract,
            capMode: career.capMode,
            salaryCap: salaryCap
        )
        try? modelContext.save()
        loadTeam()
    }

    /// Books an agreed pay cut through the engine that books pay cuts — see
    /// `CapComplianceView.applyPayCut` for why nothing is written here directly.
    private func applyPayCut(newSalary: Int, moraleDelta: Int) {
        ContractEngine.applyPayCut(
            player: player,
            team: team,
            contract: contract,
            capMode: career.capMode,
            salaryCap: salaryCap,
            newAnnualSalary: newSalary,
            moraleDelta: moraleDelta
        )
        try? modelContext.save()
        loadTeam()
    }

    private var realisticCapSection: some View {
        Section("Realistic Cap Details") {
            LabeledContent("Cap Hit") {
                Text(formatMillions(player.annualSalary))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            LabeledContent("Dead Cap (if cut)") {
                Text(formatMillions(deadCapIfCut))
                    .monospacedDigit()
                    .foregroundStyle(Color.danger)
            }
            LabeledContent("Guaranteed Remaining") {
                Text(formatMillions(guaranteedRemaining))
                    .monospacedDigit()
                    .foregroundStyle(Color.warning)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Computed Helpers

    private var isOwnPlayer: Bool {
        guard let teamID = career.teamID else { return false }
        return player.teamID == teamID
    }

    /// Market value — **`ContractEngine`, at the club's real cap** (task #87 / F4).
    ///
    /// This screen used to run a THIRD independent market formula:
    /// `overall² × its own position table` (QB 8.0, LT 4.5, WR/TE 3.5…), with no
    /// salary cap, no age curve and no vet-minimum floor. An 84-OVR quarterback
    /// priced at **$56.4M** here, ~$40M in `ContractEngine` and ~$34M in the
    /// now-deleted `PlayerValueEngine` — three numbers for one player, on three
    /// screens, in one build.
    private var estimatedMarketValue: Int {
        ContractEngine.estimateMarketValue(
            player: player,
            salaryCap: team?.salaryCap ?? ContractEngine.openingSalaryCap
        )
    }

    private var marketComparisonLabel: String {
        let diff = player.annualSalary - estimatedMarketValue
        let diffM = Double(abs(diff)) / 1000.0
        if abs(diff) < 500 {
            return "At market value"
        } else if diff > 0 {
            return String(format: "$%.1fM above market", diffM)
        } else {
            return String(format: "$%.1fM below market", diffM)
        }
    }

    private var marketComparisonIcon: String {
        let diff = player.annualSalary - estimatedMarketValue
        if abs(diff) < 500 { return "equal.circle.fill" }
        return diff > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill"
    }

    private var marketComparisonColor: Color {
        let diff = player.annualSalary - estimatedMarketValue
        if abs(diff) < 500 { return .textSecondary }
        // Overpaying is bad (danger), underpaying is good (success)
        return diff > 0 ? .danger : .success
    }

    /// The share of the league year still unpaid, for the release split (#26).
    private var leagueYearRemaining: Double {
        CapManagementEngine.leagueYearRemaining(
            phase: career.currentPhase,
            week: career.currentWeek
        )
    }

    /// The release priced by the one engine authority (#68). This screen used to
    /// quote 50 % of salary here and then book ZERO dead cap when the button was
    /// pressed — the number on screen and the number on the ledger were unrelated.
    private var releaseSplit: CapManagementEngine.ReleaseCapSplit {
        CapManagementEngine.releaseCapSplit(
            player: player,
            contract: contract,
            capMode: career.capMode,
            leagueYearRemaining: leagueYearRemaining
        )
    }

    private var deadCapIfCut: Int { releaseSplit.deadCap }

    /// Confirmation copy that quotes what the release actually does to the cap:
    /// the net saving, and the dead money that stays behind. The old line
    /// promised the whole salary back.
    private var cutAlertMessage: String {
        let split = releaseSplit
        let net = split.capSavings >= 0
            ? "free up \(formatMillions(split.capSavings)) in cap space"
            : "COST \(formatMillions(-split.capSavings)) in cap space"
        let dead = split.deadCap > 0
            ? " \(formatMillions(split.deadCap)) stays on the books as dead money."
            : ""
        return "This will release \(player.fullName) and \(net).\(dead) This action cannot be undone."
    }

    /// Simplified guaranteed remaining: decreases as years tick down
    private var guaranteedRemaining: Int {
        Int(Double(player.annualSalary * player.contractYearsRemaining) * 0.4)
    }

    private var contractStatusLabel: some View {
        switch player.contractYearsRemaining {
        case 3...:
            return Text("Locked In")
                .foregroundStyle(Color.success)
        case 2:
            return Text("Stable")
                .foregroundStyle(Color.textSecondary)
        case 1:
            return Text("Expiring Soon")
                .foregroundStyle(Color.warning)
        default:
            return Text("Free Agent")
                .foregroundStyle(Color.danger)
        }
    }

    private var positionBadge: some View {
        HStack(spacing: 6) {
            Text(player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(positionSideColor, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
            Text(player.position.side.rawValue)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var positionSideColor: Color {
        switch player.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    /// Contract runway is a countdown in years, not a rating — P7 rule 2, the
    /// status palette at a stated threshold. Twin of
    /// `CapOverviewView.yearsColor`; the same player must not read amber on one
    /// screen and gold on the other.
    private func yearsColor(_ years: Int) -> Color {
        if years >= 3 { return .forStatus(.ok) }      // comfortably under contract
        if years == 2 { return .forStatus(.neutral) } // no decision due yet
        if years == 1 { return .forStatus(.warn) }    // expiring — decide this year
        return .forStatus(.bad)                       // already off the books
    }

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    // MARK: - Actions

    private func loadTeam() {
        guard let teamID = career.teamID else { return }
        let descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(descriptor).first

        // #208 G1 — the room the Cut button is about to thin. Keyed on `teamID`
        // exactly like every other roster read in the app, so a man released
        // anywhere else drops out of this count the moment his `teamID` clears.
        let rosterDescriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == teamID }
        )
        roster = (try? modelContext.fetch(rosterDescriptor)) ?? []

        let playerID = player.id
        let contractDescriptor = FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.playerID == playerID }
        )
        contract = try? modelContext.fetch(contractDescriptor).first
    }

    private func cutPlayer() {
        guard let team else { return }
        // ONE authority (#68). The two lines this replaced handed back the FULL
        // salary and booked no dead money, so an in-season release was free and
        // the club's ledger drifted every time one happened.
        let split = CapManagementEngine.applyRelease(
            player: player,
            team: team,
            // #208 G1 — the roster loaded with the club, so the door checks the
            // same room this screen disabled its button on.
            authority: .club(roster: roster),
            contract: contract,
            capMode: career.capMode,
            leagueYearRemaining: leagueYearRemaining,
            careerID: career.id,
            // #188: the club walked away from a deal — the receipt says so on
            // the Cap screen's Dead Money card.
            reason: .contractRelease,
            seasonYear: career.currentSeason,
            modelContext: modelContext
        )
        // Refused: nothing was written, so there is nothing to save and no
        // reason to leave the screen — the disabled button and its reason are
        // still on it.
        guard !split.isRefused else { return }
        // Same sweep the other three release doors run: the man leaves the
        // saved depth chart with his contract, and the slot he vacated is
        // re-filled from behind him rather than reading empty until the next
        // advance refuses on it.
        DepthChart.reconcileSaved(
            career: career,
            roster: roster.filter { $0.teamID == team.id }
        )
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PlayerContractView(
            player: Player(
                firstName: "Patrick",
                lastName: "Mahomes",
                position: .QB,
                age: 28,
                yearsPro: 7,
                physical: PhysicalAttributes(
                    speed: 72, acceleration: 78, strength: 65,
                    agility: 80, stamina: 85, durability: 88
                ),
                mental: MentalAttributes(
                    awareness: 94, decisionMaking: 92, clutch: 96,
                    workEthic: 88, coachability: 82, leadership: 90
                ),
                positionAttributes: .quarterback(QBAttributes(
                    armStrength: 95, accuracyShort: 88, accuracyMid: 91,
                    accuracyDeep: 87, pocketPresence: 92, scrambling: 80
                )),
                personality: PlayerPersonality(archetype: .fieryCompetitor, motivation: .winning),
                contractYearsRemaining: 3,
                annualSalary: 45000
            ),
            career: Career(playerName: "Coach", role: .gm, capMode: .realistic)
        )
    }
    .modelContainer(for: [Career.self, Player.self, Team.self], inMemory: true)
}
