import SwiftUI
import SwiftData

// MARK: - FA Signing Tracker

/// Tracks actual FA signings via UserDefaults for FACompleteView.
enum FASigningTracker {
    private static let key = "faSigningIDs"
    private static let lostKey = "faLostPlayerIDs"
    private static let preCapKey = "faPreCapUsage"
    private static let preOVRKey = "faPreRosterOVR"
    private static let preStarterGapsKey = "faPreStarterGaps"
    private static let baseSalaryCapKey = "faBaseSalaryCap"

    static func trackSigning(_ playerID: UUID) {
        var ids = getSigningIDs()
        ids.insert(playerID)
        let strings = ids.map(\.uuidString)
        UserDefaults.standard.set(strings, forKey: key)
    }

    static func getSigningIDs() -> Set<UUID> {
        let strings = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    // MARK: - Lost Players

    static func trackLostPlayers(_ playerIDs: [UUID]) {
        let strings = playerIDs.map(\.uuidString)
        UserDefaults.standard.set(strings, forKey: lostKey)
    }

    static func getLostPlayerIDs() -> [UUID] {
        let strings = UserDefaults.standard.stringArray(forKey: lostKey) ?? []
        return strings.compactMap { UUID(uuidString: $0) }
    }

    // MARK: - Pre-FA Snapshot

    static func savePreFASnapshot(capUsage: Int, rosterOVR: Int, starterGaps: Int, baseSalaryCap: Int) {
        UserDefaults.standard.set(capUsage, forKey: preCapKey)
        UserDefaults.standard.set(rosterOVR, forKey: preOVRKey)
        UserDefaults.standard.set(starterGaps, forKey: preStarterGapsKey)
        UserDefaults.standard.set(baseSalaryCap, forKey: baseSalaryCapKey)
    }

    static func getPreFACapUsage() -> Int {
        UserDefaults.standard.integer(forKey: preCapKey)
    }

    static func getPreFARosterOVR() -> Int {
        UserDefaults.standard.integer(forKey: preOVRKey)
    }

    static func getPreFAStarterGaps() -> Int {
        UserDefaults.standard.integer(forKey: preStarterGapsKey)
    }

    static func getBaseSalaryCap() -> Int {
        let val = UserDefaults.standard.integer(forKey: baseSalaryCapKey)
        return val > 0 ? val : 265_000
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: lostKey)
        UserDefaults.standard.removeObject(forKey: preCapKey)
        UserDefaults.standard.removeObject(forKey: preOVRKey)
        UserDefaults.standard.removeObject(forKey: preStarterGapsKey)
        UserDefaults.standard.removeObject(forKey: baseSalaryCapKey)
    }
}

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
    @State private var biddingUpdates: [FreeAgencyEngine.BiddingUpdate] = []
    @State private var showBiddingUpdates = false
    @State private var instantSigningMessage: String?
    @State private var showInstantSigning = false
    @State private var allPlayers: [Player] = []

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
                    biddingUpdatesBar
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
                        // Check for instant signing (big overpay on Day 1)
                        let instantResult = FreeAgencyEngine.checkInstantSigning(
                            offeredSalary: salary,
                            askingPrice: fa.askingPrice,
                            round: currentRound
                        )

                        switch instantResult {
                        case .signedImmediately, .coinFlipSigned:
                            // Player signs immediately -- too good to refuse
                            FreeAgencyEngine.signFreeAgent(
                                player: fa.player,
                                team: team,
                                years: years,
                                salary: salary,
                                capMode: career.capMode,
                                modelContext: modelContext
                            )
                            FASigningTracker.trackSigning(fa.player.id)
                            let salaryStr = formatMillions(salary)
                            instantSigningMessage = "\(fa.player.fullName) signed immediately for \(salaryStr)/yr x \(years)yr! The offer was too good to refuse."
                            showInstantSigning = true
                            loadData()

                        case .goesToMarket:
                            // Normal offer, goes to bidding process
                            myOffers[fa.player.id] = ContractOffer(
                                playerID: fa.player.id,
                                salary: salary,
                                years: years
                            )
                        }
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
        .alert("Instant Signing!", isPresented: $showInstantSigning) {
            Button("OK") { instantSigningMessage = nil }
        } message: {
            Text(instantSigningMessage ?? "")
        }
    }

    // MARK: - Round Header

    /// Phase metadata for the progression indicator.
    private struct PhaseInfo {
        let label: String
        let description: String
        let isFrenzy: Bool
    }

    private func phaseInfo(for round: Int) -> PhaseInfo {
        switch round {
        case 1: return PhaseInfo(label: "Day 1", description: "Frenzy: top FAs sign fast", isFrenzy: true)
        case 2: return PhaseInfo(label: "Day 2", description: "Frenzy: bidding wars peak", isFrenzy: true)
        case 3: return PhaseInfo(label: "Day 3", description: "Mid-tier FAs settle", isFrenzy: false)
        case 4: return PhaseInfo(label: "Week 2", description: "Bargains begin to appear", isFrenzy: false)
        case 5: return PhaseInfo(label: "Week 3", description: "Late market: depth signings", isFrenzy: false)
        case 6: return PhaseInfo(label: "Week 4", description: "Final round: cleanup signings", isFrenzy: false)
        default: return PhaseInfo(label: "Complete", description: "FA closed", isFrenzy: false)
        }
    }

    private var roundHeader: some View {
        let phase = phaseInfo(for: currentRound)

        return VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("FREE AGENCY")
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color.accentGold)
                Text(roundLabel)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                if phase.isFrenzy {
                    Text("FRENZY")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.danger, in: Capsule())
                }
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

            // Phase description
            HStack(spacing: 6) {
                Image(systemName: phase.isFrenzy ? "flame.fill" : "calendar")
                    .font(.system(size: 9))
                    .foregroundStyle(phase.isFrenzy ? Color.danger : Color.textTertiary)
                Text(phase.description)
                    .font(.system(size: 10).italic())
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }

            // Phase progression bar with labels
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(1...6, id: \.self) { round in
                        let isPast = round < currentRound
                        let isCurrent = round == currentRound
                        VStack(spacing: 3) {
                            Circle()
                                .fill(isPast ? Color.success :
                                      isCurrent ? Color.accentGold :
                                      Color.backgroundTertiary)
                                .frame(width: isCurrent ? 10 : 8, height: isCurrent ? 10 : 8)
                                .overlay(
                                    Circle()
                                        .strokeBorder(isCurrent ? Color.accentGold.opacity(0.4) : Color.clear, lineWidth: 2)
                                        .frame(width: 16, height: 16)
                                )
                            Text(phaseInfo(for: round).label)
                                .font(.system(size: 8).weight(isCurrent ? .bold : .regular))
                                .foregroundStyle(isCurrent ? Color.accentGold :
                                                 isPast ? Color.textSecondary :
                                                 Color.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)

                        if round < 6 {
                            Rectangle()
                                .fill(round < currentRound ? Color.success.opacity(0.5) : Color.surfaceBorder)
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                                .offset(y: -8)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Text("\(freeAgents.count) available")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Bidding Updates Bar

    @ViewBuilder
    private var biddingUpdatesBar: some View {
        if !biddingUpdates.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "megaphone.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentGold)
                    Text("BIDDING UPDATES")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Color.accentGold)
                    Spacer()
                    Button {
                        biddingUpdates.removeAll()
                    } label: {
                        Text("Dismiss")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)

                ForEach(biddingUpdates, id: \.playerID) { update in
                    biddingUpdateRow(update)
                }
            }
            .background(Color.backgroundSecondary)
            .overlay(
                Rectangle()
                    .fill(Color.accentGold.opacity(0.3))
                    .frame(height: 1),
                alignment: .bottom
            )
        }
    }

    private func biddingUpdateRow(_ update: FreeAgencyEngine.BiddingUpdate) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(update.position)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 26)
                    .padding(.vertical, 2)
                    .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 3))
                Text(update.playerName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if update.isBiddingWar {
                    Text("BIDDING WAR")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.danger, in: Capsule())
                }
                Spacer()
                Text("\(update.totalBidders) bidder\(update.totalBidders == 1 ? "" : "s")")
                    .font(.system(size: 9))
                    .foregroundStyle(update.totalBidders >= 4 ? Color.danger : Color.textTertiary)
            }

            HStack(spacing: 12) {
                Text("Your offer: \(formatMillions(update.yourOffer))/yr")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(Color.accentGold)

                if let highest = update.highestCompetingOffer, let teamAbbr = update.highestCompetingTeam {
                    Text("Highest: ~\(formatMillions(highest))/yr from \(teamAbbr)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(Color.warning)
                }
            }

            HStack(spacing: 8) {
                let leaningColor: Color = {
                    switch update.playerLeaning {
                    case .strongInterest, .prefersYou: return .success
                    case .undecided: return .warning
                    case .leaningAway: return .danger
                    }
                }()
                Image(systemName: leaningIcon(update.playerLeaning))
                    .font(.system(size: 8))
                    .foregroundStyle(leaningColor)
                Text(update.playerLeaning.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(leaningColor)

                Spacer()

                // Action buttons
                Button {
                    // Raise offer: reopen offer sheet
                    if let fa = freeAgents.first(where: { $0.player.id == update.playerID }) {
                        selectedFA = fa
                    }
                } label: {
                    Text("Raise Offer")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.accentGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentGold.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    // Withdraw offer
                    myOffers.removeValue(forKey: update.playerID)
                    biddingUpdates.removeAll { $0.playerID == update.playerID }
                } label: {
                    Text("Withdraw")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.danger)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.danger.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentGold.opacity(0.03))
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder.opacity(0.3))
                .frame(height: 1),
            alignment: .top
        )
    }

    private func leaningIcon(_ leaning: FreeAgencyEngine.PlayerLeaning) -> String {
        switch leaning {
        case .strongInterest: return "hand.thumbsup.fill"
        case .prefersYou:     return "arrow.right"
        case .undecided:      return "questionmark.circle"
        case .leaningAway:    return "arrow.left"
        }
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
            VStack(alignment: .leading, spacing: 4) {
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
                            motivationBadge(fa.player.personality.motivation)
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

                // Cap impact preview + rumor row (decision support)
                HStack(spacing: 6) {
                    capImpactBadge(asking: fa.askingPrice)
                    if let rumor = rumorText(for: fa) {
                        HStack(spacing: 3) {
                            Image(systemName: rumor.icon)
                                .font(.system(size: 8))
                            Text(rumor.text)
                                .font(.system(size: 9).italic())
                        }
                        .foregroundStyle(rumor.color)
                    }
                    Spacer()
                }
                .padding(.leading, 40) // align with player info
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(hasOffer ? Color.accentGold.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cap Impact Badge (preview)

    private func capImpactBadge(asking: Int) -> some View {
        // Base on team salaryCap if available, else $260M baseline
        let cap = team?.salaryCap ?? 260_000
        let pct = cap > 0 ? Double(asking) / Double(cap) * 100 : 0
        let pctRounded = Int(pct.rounded())
        let color: Color = {
            if pct >= 12 { return .danger }
            if pct >= 7 { return .warning }
            return .textSecondary
        }()
        let labelText = pctRounded <= 0 ? "<1% of cap" : "Will use \(pctRounded)% of cap"
        return Text(labelText)
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Rumor System

    private struct Rumor {
        let text: String
        let icon: String
        let color: Color
    }

    private func rumorText(for fa: FreeAgencyEngine.FreeAgent) -> Rumor? {
        // Pick a single rumor in priority order (most signal first)
        // 1. Loyalty motivation -> hometown discount
        if fa.player.personality.motivation == .loyalty {
            return Rumor(text: "Hometown discount possible", icon: "house.fill", color: .accentBlue)
        }
        // 2. Heavy market interest -> bidding war chatter
        if fa.marketInterest >= 7 {
            return Rumor(text: "\(fa.marketInterest) teams interested — bidding war", icon: "flame.fill", color: .danger)
        }
        if fa.marketInterest >= 4 {
            return Rumor(text: "\(fa.marketInterest) teams interested", icon: "person.3.fill", color: .warning)
        }
        // 3. Money motivation -> wants top dollar
        if fa.player.personality.motivation == .money && fa.askingPrice > 8_000 {
            return Rumor(text: "Wants top-of-market money", icon: "dollarsign.circle.fill", color: .accentGold)
        }
        // 4. Winning motivation -> contender discount
        if fa.player.personality.motivation == .winning {
            return Rumor(text: "Will take less for a contender", icon: "trophy.fill", color: .success)
        }
        // 5. Aging veteran -> short deal likely
        if fa.player.age >= 32 && fa.desiredYears <= 2 {
            return Rumor(text: "Likely short prove-it deal", icon: "clock.fill", color: .textSecondary)
        }
        return nil
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

        // Generate AI bids for all free agents this round (need-based)
        var aiBids = FreeAgencyEngine.generateAIOffers(
            freeAgents: freeAgents,
            round: currentRound,
            allTeams: allTeams,
            allPlayers: allPlayers.isEmpty ? nil : allPlayers,
            playerTeamID: career.teamID
        )

        // Process bidding wars (4+ teams on same player)
        let biddingWarInfos = FreeAgencyEngine.processBiddingWars(
            aiBids: &aiBids,
            freeAgents: freeAgents,
            allTeams: allTeams
        )

        // Process player's offers using resolvePlayerDecision
        var accepted: [(playerName: String, position: String, salary: Int, years: Int)] = []
        var rejected: [(playerName: String, position: String, reason: String, chosenTeam: String?, salary: Int?)] = []
        var shoppingAround: [(playerName: String, position: String)] = []

        for (playerID, offer) in myOffers {
            guard let fa = freeAgents.first(where: { $0.player.id == playerID }) else { continue }
            let player = fa.player

            let playerBids = aiBids[player.id] ?? []
            let decision = FreeAgencyEngine.resolvePlayerDecision(
                player: player,
                playerOffer: (salary: offer.salary, years: offer.years),
                aiBids: playerBids,
                round: currentRound,
                allTeams: allTeams
            )

            if decision.shoppingAround {
                // Player wants to see more offers -- keep the offer active
                shoppingAround.append((
                    playerName: player.fullName,
                    position: player.position.rawValue
                ))
                // Don't remove from myOffers -- carry forward
                continue
            }

            if decision.accepted {
                // Signed with us
                FreeAgencyEngine.signFreeAgent(
                    player: player,
                    team: team,
                    years: offer.years,
                    salary: offer.salary,
                    capMode: career.capMode,
                    modelContext: modelContext
                )
                FASigningTracker.trackSigning(player.id)
                accepted.append((
                    playerName: player.fullName,
                    position: player.position.rawValue,
                    salary: offer.salary,
                    years: offer.years
                ))
            } else {
                // Rejected -- chose another team
                rejected.append((
                    playerName: player.fullName,
                    position: player.position.rawValue,
                    reason: decision.reason,
                    chosenTeam: decision.chosenTeamName,
                    salary: decision.salary
                ))

                // AI signs the rejected player to their chosen team
                if let chosenID = decision.chosenTeamID,
                   let aiTeam = allTeams.first(where: { $0.id == chosenID }),
                   aiTeam.availableCap >= (decision.salary ?? fa.askingPrice) {
                    ContractEngine.signPlayerSimple(
                        player: player,
                        years: decision.years ?? fa.desiredYears,
                        annualSalary: decision.salary ?? fa.askingPrice,
                        team: aiTeam
                    )
                }
            }
        }

        // Remove signed/rejected players from offers; keep shopping-around offers
        let shoppingIDs = Set(shoppingAround.map { _ -> UUID? in nil }) // we keep all myOffers for shopping players
        for (playerID, _) in myOffers {
            let isShoppingAround = freeAgents
                .first(where: { $0.player.id == playerID })
                .map { fa in shoppingAround.contains(where: { $0.playerName == fa.player.fullName }) } ?? false
            if !isShoppingAround {
                myOffers.removeValue(forKey: playerID)
            }
        }

        // Generate bidding updates for remaining offers (players still shopping)
        let offerTuples = myOffers.mapValues { offer in (salary: offer.salary, years: offer.years) }
        biddingUpdates = FreeAgencyEngine.generateBiddingUpdates(
            myOffers: offerTuples,
            aiBids: aiBids,
            freeAgents: freeAgents,
            playerTeamID: career.teamID
        )

        // AI signings for this round (players without our offers)
        let aiSignings = simulateAIRound(excludePlayerIDs: Set(myOffers.keys), aiBids: aiBids)

        // Generate media headlines (with bidding war info)
        let headlines = FreeAgencyEngine.generateHeadlines(
            signings: aiSignings,
            rejections: rejected.map { (playerName: $0.playerName, chosenTeam: $0.chosenTeam) },
            biddingWars: biddingWarInfos,
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
            capRemaining: team.availableCap,
            biddingWars: biddingWarInfos,
            shoppingAround: shoppingAround,
            biddingUpdates: biddingUpdates
        )

        if currentRound >= 6 {
            career.freeAgencyStep = FreeAgencyStep.complete.rawValue
        } else {
            career.freeAgencyRound += 1
        }

        // Refresh free agents
        loadData()
        showRoundSummary = true
    }

    private func simulateAIRound(excludePlayerIDs: Set<UUID>, aiBids: [UUID: [FreeAgencyEngine.AIBid]]) -> [(playerName: String, position: String, team: String, salary: Int)] {
        let roundFAs = freeAgents.filter { !excludePlayerIDs.contains($0.player.id) && $0.player.teamID == nil }

        var signings: [(playerName: String, position: String, team: String, salary: Int)] = []

        for fa in roundFAs {
            // Use AI bids generated by generateAIOffers
            guard let bids = aiBids[fa.player.id], !bids.isEmpty else { continue }

            // Resolve which team wins -- player decides among AI offers only
            let decision = FreeAgencyEngine.resolvePlayerDecision(
                player: fa.player,
                playerOffer: nil,
                aiBids: bids,
                round: currentRound,
                allTeams: allTeams
            )

            if let chosenID = decision.chosenTeamID,
               let signingTeam = allTeams.first(where: { $0.id == chosenID }),
               let salary = decision.salary {
                ContractEngine.signPlayerSimple(
                    player: fa.player,
                    years: decision.years ?? fa.desiredYears,
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

        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 7))
            Text(label)
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(Color.accentGold.opacity(0.8))
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Color.accentGold.opacity(0.1), in: Capsule())
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

        allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []
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
    var biddingWars: [FreeAgencyEngine.BiddingWarInfo] = []
    var shoppingAround: [(playerName: String, position: String)] = []
    var biddingUpdates: [FreeAgencyEngine.BiddingUpdate] = []
}
