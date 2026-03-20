import SwiftUI
import SwiftData

// MARK: - Contract Offer

struct ContractOffer: Identifiable {
    let id = UUID()
    let playerID: UUID
    let salary: Int
    let years: Int
}

// MARK: - FAWeeklyView

struct FAWeeklyView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var allTeams: [Team] = []
    @State private var freeAgents: [FreeAgencyEngine.FreeAgent] = []
    @State private var myOffers: [UUID: ContractOffer] = [:]
    @State private var roundResults: RoundResults?
    @State private var showRoundSummary = false
    @State private var showSkipConfirm = false
    @State private var selectedFA: FreeAgencyEngine.FreeAgent?
    @State private var positionFilter: PositionFilter = .all

    // Position filter
    enum PositionFilter: String, CaseIterable {
        case all = "All"
        case qb = "QB"
        case skill = "Skill"
        case ol = "OL"
        case dl = "DL"
        case lb = "LB"
        case db = "DB"

        var positions: [Position]? {
            switch self {
            case .all:   return nil
            case .qb:    return [.QB]
            case .skill: return [.RB, .FB, .WR, .TE]
            case .ol:    return [.LT, .LG, .C, .RG, .RT]
            case .dl:    return [.DE, .DT]
            case .lb:    return [.OLB, .MLB]
            case .db:    return [.CB, .FS, .SS]
            }
        }
    }

    private var currentRound: Int { career.freeAgencyRound }
    private var roundLabel: String { FreeAgencyStep.roundLabel(currentRound) }
    private var visibility: AIVisibilityLevel { FreeAgencyStep.aiVisibility(currentRound) }

    private var filteredAgents: [FreeAgencyEngine.FreeAgent] {
        guard let positions = positionFilter.positions else { return freeAgents }
        return freeAgents.filter { positions.contains($0.player.position) }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if team != nil {
                VStack(spacing: 0) {
                    roundHeader
                    pendingOffersBar
                    positionFilterBar
                    freeAgentList
                    bottomBar
                }
            } else {
                ProgressView()
                    .tint(Color.accentGold)
            }
        }
        .navigationTitle("Free Agency")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
        .sheet(item: $selectedFA) { fa in
            if let team {
                FAOfferSheet(
                    player: fa.player,
                    career: career,
                    team: team,
                    marketValue: fa.askingPrice,
                    onSubmit: { salary, years in
                        myOffers[fa.player.id] = ContractOffer(
                            playerID: fa.player.id,
                            salary: salary,
                            years: years
                        )
                    }
                )
            }
        }
        .sheet(isPresented: $showRoundSummary) {
            if let results = roundResults {
                FARoundSummaryView(
                    results: results,
                    roundLabel: FreeAgencyStep.roundLabel(currentRound - 1),
                    nextRoundLabel: currentRound <= 6 ? FreeAgencyStep.roundLabel(currentRound) : "Complete",
                    onContinue: { showRoundSummary = false }
                )
            }
        }
        .alert("Skip Remaining Free Agency?", isPresented: $showSkipConfirm) {
            Button("Skip", role: .destructive) { skipRemainingFA() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("AI teams will sign remaining free agents based on their needs. You won't be able to make any more signings.")
        }
    }

    // MARK: - Round Header

    private var roundHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("FREE AGENCY")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.accentGold)
                Text(roundLabel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let team {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Cap Space")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                        Text(formatMillions(team.availableCap))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(team.availableCap > 0 ? Color.success : Color.danger)
                    }
                }
            }

            // Round dots
            HStack(spacing: 6) {
                ForEach(1...6, id: \.self) { round in
                    Circle()
                        .fill(round < currentRound ? Color.success :
                              round == currentRound ? Color.accentGold :
                              Color.backgroundTertiary)
                        .frame(width: 8, height: 8)
                    if round == 3 && round < 6 {
                        Rectangle()
                            .fill(Color.surfaceBorder)
                            .frame(width: 1, height: 12)
                    }
                }
                Spacer()
                Text("\(freeAgents.count) available")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Pending Offers Bar

    @ViewBuilder
    private var pendingOffersBar: some View {
        if !myOffers.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentGold)
                Text("\(myOffers.count) pending offer\(myOffers.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
                Spacer()
                let totalCost = myOffers.values.reduce(0) { $0 + $1.salary }
                Text("Total: \(formatMillions(totalCost))/yr")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentGold.opacity(0.08))
        }
    }

    // MARK: - Position Filter

    private var positionFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(PositionFilter.allCases, id: \.self) { filter in
                    Button {
                        positionFilter = filter
                    } label: {
                        Text(filter.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(positionFilter == filter ? Color.backgroundPrimary : Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                positionFilter == filter ? Color.accentGold : Color.backgroundTertiary,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Free Agent List

    private var freeAgentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(filteredAgents.enumerated()), id: \.element.player.id) { index, fa in
                    freeAgentRow(fa: fa)

                    if index < filteredAgents.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, 8)
                    }
                }

                if filteredAgents.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.slash")
                            .font(.title2)
                            .foregroundStyle(Color.textTertiary)
                        Text("No free agents available")
                            .font(.subheadline)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.vertical, 40)
                }
            }
        }
    }

    private func freeAgentRow(fa: FreeAgencyEngine.FreeAgent) -> some View {
        let hasOffer = myOffers[fa.player.id] != nil

        return Button {
            selectedFA = fa
        } label: {
            HStack(spacing: 10) {
                // Position badge
                Text(fa.player.position.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 30)
                    .padding(.vertical, 3)
                    .background(positionSideColor(fa.player.position), in: RoundedRectangle(cornerRadius: 4))

                // Player info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(fa.player.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                        if hasOffer {
                            Text("OFFER PENDING")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.accentGold)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentGold.opacity(0.15), in: Capsule())
                        }
                    }
                    HStack(spacing: 8) {
                        Text("\(fa.player.overall) OVR")
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.forRating(fa.player.overall))
                        Text("Age \(fa.player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        // AI interest with progressive visibility
                        aiInterestLabel(fa: fa)
                    }
                }

                Spacer()

                // Asking price
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatMillions(fa.askingPrice))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text("\(fa.desiredYears)yr")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(hasOffer ? Color.accentGold.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - AI Interest Label

    private func aiInterestLabel(fa: FreeAgencyEngine.FreeAgent) -> some View {
        let interest = fa.marketInterest
        guard interest > 0 else {
            return AnyView(EmptyView())
        }

        let text: String = {
            switch visibility {
            case .countOnly:
                return "\(interest) team\(interest == 1 ? "" : "s") interested"
            case .hints:
                let hint = interest >= 7 ? "A championship contender" : (interest >= 4 ? "Several teams" : "A team")
                return "\(hint) and \(max(interest - 1, 0)) other\(interest - 1 == 1 ? "" : "s") interested"
            case .partialNames:
                let sampleTeam = allTeams.filter { $0.id != team?.id }.randomElement()?.abbreviation ?? "???"
                return "\(sampleTeam) and \(max(interest - 1, 0)) other\(interest - 1 == 1 ? "" : "s")"
            case .fullNames:
                let otherTeams = allTeams.filter { $0.id != team?.id }.shuffled().prefix(min(interest, 3))
                let names = otherTeams.map(\.abbreviation).joined(separator: ", ")
                return names + (interest > 3 ? " +\(interest - 3) more" : "")
            }
        }()

        return AnyView(
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 8))
                Text(text)
                    .font(.system(size: 9))
            }
            .foregroundStyle(interest >= 7 ? Color.danger : (interest >= 4 ? Color.warning : Color.textTertiary))
        )
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                showSkipConfirm = true
            } label: {
                Text("Skip Remaining FA")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)

            Spacer()

            let nextLabel = currentRound < 6 ? FreeAgencyStep.roundLabel(currentRound + 1) : "Complete"
            Button {
                processRound()
            } label: {
                Text("Submit Offers \u{2192} \(nextLabel)")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.accentGold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Process Round

    private func processRound() {
        guard let team else { return }

        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []

        // Process player's offers
        var accepted: [(playerName: String, position: String, salary: Int, years: Int)] = []
        var rejected: [(playerName: String, position: String, reason: String, chosenTeam: String?, salary: Int?)] = []

        for (playerID, offer) in myOffers {
            guard let fa = freeAgents.first(where: { $0.player.id == playerID }) else { continue }
            let player = fa.player

            let ratio = Double(offer.salary) / Double(fa.askingPrice)
            let aggression = FreeAgencyStep.aiAggression(currentRound)

            // Player decision: compare offer vs asking price with motivation adjustments
            let motivationBonus: Double = {
                switch player.personality.motivation {
                case .loyalty:  return 0.15
                case .winning:  return career.totalWins >= 10 ? 0.10 : 0.0
                case .money:    return -0.05
                case .fame:     return 0.0
                case .stats:    return 0.0
                }
            }()

            let acceptThreshold = 0.85 - motivationBonus
            let aiCompetition = aggression * Double.random(in: 0.8...1.2)

            if ratio >= acceptThreshold && Double.random(in: 0...1) > aiCompetition * 0.3 {
                // Accepted!
                FreeAgencyEngine.signFreeAgent(
                    player: player,
                    team: team,
                    years: offer.years,
                    salary: offer.salary,
                    capMode: career.capMode,
                    modelContext: modelContext
                )
                accepted.append((
                    playerName: player.fullName,
                    position: player.position.rawValue,
                    salary: offer.salary,
                    years: offer.years
                ))
            } else {
                // Rejected
                let aiTeam = allTeams.filter { $0.id != team.id }.randomElement()
                let reason = rejectReason(player: player)
                rejected.append((
                    playerName: player.fullName,
                    position: player.position.rawValue,
                    reason: reason,
                    chosenTeam: aiTeam?.abbreviation,
                    salary: Int(Double(fa.askingPrice) * Double.random(in: 0.9...1.1))
                ))

                // AI signs the rejected player
                if let aiTeam, aiTeam.availableCap >= fa.askingPrice {
                    ContractEngine.signPlayerSimple(
                        player: player,
                        years: fa.desiredYears,
                        annualSalary: fa.askingPrice,
                        team: aiTeam
                    )
                }
            }
        }

        // AI signings for this round (players without our offers)
        let aiSignings = simulateAIRound(excludePlayerIDs: Set(myOffers.keys))

        // Generate media headlines
        let headlines = FreeAgencyEngine.generateHeadlines(
            signings: aiSignings,
            rejections: rejected.map { (playerName: $0.playerName, chosenTeam: $0.chosenTeam) },
            playerTeamAbbr: team.abbreviation,
            round: currentRound
        )

        // Build results
        roundResults = RoundResults(
            yourSignings: accepted,
            yourRejections: rejected,
            aiSignings: aiSignings,
            headlines: headlines,
            playersRemaining: freeAgents.filter { $0.player.teamID == nil }.count - accepted.count,
            capRemaining: team.availableCap
        )

        // Clear offers and advance round
        myOffers.removeAll()

        if currentRound >= 6 {
            career.freeAgencyStep = FreeAgencyStep.complete.rawValue
        } else {
            career.freeAgencyRound += 1
        }

        // Refresh free agents
        loadData()
        showRoundSummary = true
    }

    private func simulateAIRound(excludePlayerIDs: Set<UUID>) -> [(playerName: String, position: String, team: String, salary: Int)] {
        let aggression = FreeAgencyStep.aiAggression(currentRound)
        let roundFAs = freeAgents.filter { !excludePlayerIDs.contains($0.player.id) && $0.player.teamID == nil }

        // Target top players based on round
        let targetOVR: Int = {
            switch currentRound {
            case 1: return 85
            case 2: return 80
            case 3: return 75
            case 4: return 70
            case 5: return 65
            case 6: return 60
            default: return 60
            }
        }()

        let targets = roundFAs.filter { $0.player.overall >= targetOVR }
            .prefix(Int(Double(roundFAs.count) * aggression * 0.3))

        var signings: [(playerName: String, position: String, team: String, salary: Int)] = []

        for fa in targets {
            let eligibleTeams = allTeams
                .filter { $0.id != team?.id && $0.availableCap >= fa.askingPrice }
            guard let signingTeam = eligibleTeams.randomElement() else { continue }

            let salary = max(Int(Double(fa.askingPrice) * Double.random(in: 0.85...1.0)), 750)
            ContractEngine.signPlayerSimple(
                player: fa.player,
                years: fa.desiredYears,
                annualSalary: salary,
                team: signingTeam
            )

            signings.append((
                playerName: fa.player.fullName,
                position: fa.player.position.rawValue,
                team: signingTeam.abbreviation,
                salary: salary
            ))
        }

        return signings
    }

    // MARK: - Skip

    private func skipRemainingFA() {
        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []
        FreeAgencyEngine.simulateRemainingFA(
            allPlayers: allPlayers,
            allTeams: allTeams,
            playerTeamID: career.teamID,
            modelContext: modelContext
        )
        career.freeAgencyStep = FreeAgencyStep.complete.rawValue
    }

    // MARK: - Helpers

    private func rejectReason(player: Player) -> String {
        switch player.personality.motivation {
        case .money:   return "Chose a higher offer from another team"
        case .winning: return "Chose a championship contender"
        case .stats:   return "Chose a team offering a larger role"
        case .loyalty: return "Returned to familiar surroundings"
        case .fame:    return "Chose a big-market team for more exposure"
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
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        allTeams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []

        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []
        freeAgents = FreeAgencyEngine.generateFreeAgentMarket(allPlayers: allPlayers)
    }
}

// MARK: - FreeAgent Identifiable conformance

extension FreeAgencyEngine.FreeAgent: @retroactive Identifiable {
    var id: UUID { player.id }
}

// MARK: - Round Results

struct RoundResults {
    let yourSignings: [(playerName: String, position: String, salary: Int, years: Int)]
    let yourRejections: [(playerName: String, position: String, reason: String, chosenTeam: String?, salary: Int?)]
    let aiSignings: [(playerName: String, position: String, team: String, salary: Int)]
    let headlines: [String]
    let playersRemaining: Int
    let capRemaining: Int
}
