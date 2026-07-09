import SwiftUI
import SwiftData

// MARK: - Position Filter

private enum FAPositionFilter: String, CaseIterable {
    case all  = "All"
    case qb   = "QB"
    case skill = "Skill"
    case ol   = "OL"
    case dl   = "DL"
    case lb   = "LB"
    case db   = "DB"
    case st   = "ST"

    /// Display label — adds clarification for the "Skill" group.
    var displayLabel: String {
        switch self {
        case .skill: return "Skill (WR/TE/RB)"
        default:     return rawValue
        }
    }

    func matches(_ position: Position) -> Bool {
        switch self {
        case .all:   return true
        case .qb:    return position == .QB
        case .skill: return [.RB, .FB, .WR, .TE].contains(position)
        case .ol:    return [.LT, .LG, .C, .RG, .RT].contains(position)
        case .dl:    return [.DE, .DT].contains(position)
        case .lb:    return [.OLB, .MLB].contains(position)
        case .db:    return [.CB, .FS, .SS].contains(position)
        case .st:    return [.K, .P].contains(position)
        }
    }
}

// MARK: - Sort Option

private enum FASortOption: String, CaseIterable {
    case overall       = "OVR"
    case age           = "Age"
    case salary        = "Salary"
    case position      = "Position"
    case interest      = "Interest"
    case schemeFit     = "Scheme"
}

// MARK: - Scheme Fit Level

private enum SchemeFitLevel: String {
    case good = "Good Fit"
    case ok   = "OK"
    case poor = "Poor Fit"

    var color: Color {
        switch self {
        case .good: return .success
        case .ok:   return .warning
        case .poor: return .danger
        }
    }

    var sortOrder: Int {
        switch self {
        case .good: return 0
        case .ok:   return 1
        case .poor: return 2
        }
    }
}

// MARK: - Position Need Level

private enum NeedLevel: String {
    case high = "High"
    case med  = "Med"
    case low  = "Low"
}

// MARK: - FreeAgencyView

struct FreeAgencyView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var allFreeAgents: [Player] = []
    @State private var freeAgentData: [UUID: FreeAgentInfo] = [:]
    @State private var team: Team?
    @State private var teamRoster: [Player] = []
    @State private var teamCoaches: [Coach] = []
    @State private var teamDraftPicks: [DraftPick] = []
    @State private var positionFilter: FAPositionFilter = .all
    @State private var sortOption: FASortOption = .overall
    @State private var selectedPlayer: Player?
    @State private var showNegotiationSheet = false
    @State private var targetedPlayerIDs: Set<UUID> = []
    @State private var isLoading: Bool = true

    /// The salary cap to use for market value estimates; updated when team is loaded.
    private var currentSalaryCap: Int {
        team?.salaryCap ?? 265_000
    }

    /// Current FA round from career state (1-6).
    private var currentRound: Int {
        max(1, career.freeAgencyRound)
    }

    /// Total FA rounds.
    private let totalRounds = 6

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentBlue)
                    Text("Loading Free Agency...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
            VStack(spacing: 0) {
                dayIndicator
                capBanner
                needsSummaryBar
                filterBar
                sortBar
                playerList
                if !targetedPlayerIDs.isEmpty {
                    targetsSummaryBar
                }
            }
            } // end else (not loading)
        }
        .navigationTitle("Free Agency")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadData()
            isLoading = false
        }
        .sheet(isPresented: $showNegotiationSheet) {
            if let player = selectedPlayer, let team {
                NavigationStack {
                    ContractExtensionSheet(
                        player: player,
                        team: team,
                        capMode: career.capMode
                    )
                }
            }
        }
    }

    // MARK: - Day Indicator

    private var dayIndicator: some View {
        HStack(spacing: 8) {
            Text(FreeAgencyStep.roundLabel(currentRound))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.textPrimary)

            Text("of \(totalRounds)")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)

            Spacer()

            // Dot indicators
            HStack(spacing: 4) {
                ForEach(1...totalRounds, id: \.self) { round in
                    Circle()
                        .fill(round <= currentRound ? Color.accentBlue : Color.backgroundTertiary)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Cap Banner

    private var capBanner: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Available Cap Space")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text(formatMillions(team?.availableCap ?? 0))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle((team?.availableCap ?? 0) >= 0 ? Color.success : Color.danger)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Free Agents")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text(formattedCount(filteredAndSorted.count))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Team Needs Summary Bar

    private var needsSummaryBar: some View {
        let needs = computeTeamNeeds()
        return Group {
            if !needs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Needs:")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.textSecondary)
                        ForEach(needs.prefix(6), id: \.position) { need in
                            HStack(spacing: 2) {
                                Text(need.position)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.textPrimary)
                                Text("(\(need.level.rawValue))")
                                    .font(.caption2)
                                    .foregroundStyle(needLevelColor(need.level))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.backgroundTertiary)
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
                .background(Color.backgroundSecondary)
                .overlay(
                    Rectangle()
                        .fill(Color.surfaceBorder)
                        .frame(height: 1),
                    alignment: .bottom
                )
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FAPositionFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    private func filterChip(_ filter: FAPositionFilter) -> some View {
        Button {
            positionFilter = filter
        } label: {
            Text(filter.displayLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(positionFilter == filter ? Color.backgroundPrimary : Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(positionFilter == filter ? Color.accentBlue : Color.backgroundTertiary)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sort Bar

    private var sortBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Text("Sort:")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.leading, 24)

                ForEach(FASortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                    } label: {
                        Text(option.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(sortOption == option ? Color.accentBlue : Color.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Player List

    private var playerList: some View {
        Group {
            if filteredAndSorted.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.textTertiary)
                    Text("No free agents available")
                        .font(.headline)
                        .foregroundStyle(Color.textSecondary)
                    Text("Check back after the season ends or adjust your filter.")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredAndSorted) { player in
                        Button {
                            selectedPlayer = player
                            showNegotiationSheet = true
                        } label: {
                            freeAgentRow(player)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(rowBackground(for: player))
                        .listRowSeparatorTint(Color.surfaceBorder)
                        .accessibilityHint("Tap to open contract negotiation")
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.plain)
            }
        }
    }

    // MARK: - Row Background (Task 5: visual hierarchy for top FAs)

    private func rowBackground(for player: Player) -> some View {
        let isTopFA = player.overall >= 75
        return HStack(spacing: 0) {
            if isTopFA {
                Rectangle()
                    .fill(Color.accentGold.opacity(0.6))
                    .frame(width: 3)
            }
            Rectangle()
                .fill(isTopFA ? Color.backgroundSecondary.opacity(1) : Color.backgroundSecondary)
        }
    }

    // MARK: - Free Agent Row

    private func freeAgentRow(_ player: Player) -> some View {
        let info = freeAgentData[player.id]
        let marketValue = ContractEngine.estimateMarketValue(player: player, salaryCap: currentSalaryCap)
        let starterComparison = computeStarterComparison(for: player)
        let schemeFit = computeSchemeFit(for: player)
        let ovrTrend = computeOVRTrend(for: player)
        let isTargeted = targetedPlayerIDs.contains(player.id)

        return VStack(alignment: .leading, spacing: 6) {
            // Main row
            HStack(spacing: 12) {
                // Position badge
                Text(player.position.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 34)
                    .padding(.vertical, 4)
                    .background(positionColor(player.position), in: RoundedRectangle(cornerRadius: 4))

                // Name + details
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(player.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        // Hot indicator (Task 5)
                        if let info, info.marketInterest >= 6 {
                            HStack(spacing: 2) {
                                Image(systemName: "flame.fill")
                                    .font(.system(size: 10))
                                Text("Hot")
                                    .font(.system(size: 9).weight(.bold))
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        Text("\u{2022}")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        // Contract length clarity (Task 6)
                        if let info {
                            Text("Wants: \(info.desiredYears)yr")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                }

                Spacer()

                // OVR + trend (Task 12)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 2) {
                        Text("\(player.overall)")
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.forRating(player.overall))
                        if let trend = ovrTrend {
                            Image(systemName: trend.iconName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(trend.color)
                        }
                    }
                    Text("OVR")
                        .font(.system(size: 9).weight(.medium))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(minWidth: 50)

                Divider()
                    .frame(height: 32)
                    .overlay(Color.surfaceBorder)

                // Estimated salary
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatMillions(marketValue))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                    Text("Est./yr")
                        .font(.system(size: 9).weight(.medium))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(minWidth: 60)

                // Target star (Task 14)
                Button {
                    toggleTarget(player.id)
                } label: {
                    Image(systemName: isTargeted ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundStyle(isTargeted ? Color.accentGold : Color.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isTargeted ? "Untarget \(player.fullName)" : "Target \(player.fullName)")
            }

            // Second row: badges and comparison info
            HStack(spacing: 6) {
                // Motivation badge (Task 3)
                motivationBadge(player.personality.motivation)

                // Scheme fit badge (Task 8)
                if let fit = schemeFit {
                    Text(fit.rawValue)
                        .font(.system(size: 10).weight(.bold))
                        .foregroundStyle(fit.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(fit.color.opacity(0.15))
                        )
                }

                // Starter comparison (Task 7)
                if let comparison = starterComparison {
                    Text(comparison.label)
                        .font(.system(size: 10).weight(.bold))
                        .foregroundStyle(comparison.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(comparison.color.opacity(0.15))
                        )
                }

                Spacer()

                // Competition indicator (Task 15)
                if let info {
                    competitionIndicator(info.marketInterest)
                }

                // Cap impact preview (Task 11): "Will use X% of cap"
                capImpactPctBadge(asking: marketValue)

                if let teamObj = team {
                    let capAfter = teamObj.availableCap - marketValue
                    Text("Cap after: \(formatMillions(capAfter))")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(capAfter >= 0 ? Color.textTertiary : Color.danger)
                }
            }

            // Rumor row (decision support)
            if let rumor = rumorText(for: player, info: freeAgentData[player.id]) {
                HStack(spacing: 4) {
                    Image(systemName: rumor.icon)
                        .font(.system(size: 8))
                    Text(rumor.text)
                        .font(.system(size: 9).italic())
                    Spacer()
                }
                .foregroundStyle(rumor.color)
            }

            // Third row: contract structure + draft alternative (Tasks 13, 16)
            HStack(spacing: 8) {
                // Contract structure hint (Task 16)
                if let info {
                    contractStructureHint(info)
                }

                Spacer()

                // Draft comparison hint (Task 13)
                if let draftHint = draftAlternativeHint(for: player) {
                    Text(draftHint)
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                        .italic()
                }
            }

            // Fourth row: vs Current Starter card (decision support)
            vsCurrentStarterCard(for: player)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - vs Current Starter Card (decision support — letter-grade comparison)

    @ViewBuilder
    private func vsCurrentStarterCard(for player: Player) -> some View {
        let starter = teamRoster
            .filter { $0.position == player.position }
            .max(by: { $0.overall < $1.overall })

        if let starter {
            let diff = player.overall - starter.overall
            let conclusion = starterConclusionLabel(diff)
            let conclusionColor = starterConclusionColor(diff)
            let faGrade = LetterGrade.from(numericValue: player.overall)
            let starterGrade = LetterGrade.from(numericValue: starter.overall)

            HStack(spacing: 10) {
                // Free agent side
                VStack(spacing: 1) {
                    Text(player.fullName)
                        .font(.system(size: 11).weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(faGrade.rawValue)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(rowGradeColor(faGrade))
                    Text("Free Agent")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)

                // Comparison conclusion
                VStack(spacing: 1) {
                    Text("vs")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                    Text(conclusion)
                        .font(.system(size: 11).weight(.heavy))
                        .foregroundStyle(conclusionColor)
                        .multilineTextAlignment(.center)
                }

                // Starter side
                VStack(spacing: 1) {
                    Text(starter.fullName)
                        .font(.system(size: 11).weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text(starterGrade.rawValue)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(rowGradeColor(starterGrade))
                    Text("Starter")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.backgroundTertiary.opacity(0.5))
            )
        } else {
            // No starter at this position — clear win
            HStack(spacing: 8) {
                Image(systemName: "person.fill.badge.plus")
                    .font(.caption)
                    .foregroundStyle(Color.success)
                Text("No \(player.position.rawValue) on roster — immediate starter")
                    .font(.system(size: 11).weight(.semibold))
                    .foregroundStyle(Color.success)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.success.opacity(0.1))
            )
        }
    }

    private func starterConclusionLabel(_ diff: Int) -> String {
        if diff >= 3 { return "Upgrade" }
        if diff >= -2 { return "Lateral" }
        return "Downgrade"
    }

    private func starterConclusionColor(_ diff: Int) -> Color {
        if diff >= 3 { return .success }
        if diff >= -2 { return .accentGold }
        return .textSecondary
    }

    private func rowGradeColor(_ grade: LetterGrade) -> Color {
        switch grade.rank {
        case 10...12: return .success
        case 7...9:   return .accentGold
        case 4...6:   return .warning
        case 2...3:   return .danger
        default:      return .danger
        }
    }

    // MARK: - Motivation Badge (Task 3)

    private func motivationBadge(_ motivation: Motivation) -> some View {
        let (label, color) = motivationDisplay(motivation)
        return Text(label)
            .font(.system(size: 10).weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.15))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
                    )
            )
    }

    private func motivationDisplay(_ motivation: Motivation) -> (String, Color) {
        switch motivation {
        case .money:   return ("Money",   .success)
        case .fame:    return ("Fame",    Color(red: 0.6, green: 0.4, blue: 0.9))  // purple
        case .winning: return ("Winning", .accentGold)
        case .loyalty: return ("Loyalty", .accentBlue)
        case .stats:   return ("Stats",   .orange)
        }
    }

    // MARK: - Competition Indicator (Task 15)

    private func competitionIndicator(_ interest: Int) -> some View {
        let text: String
        let color: Color
        switch interest {
        case 7...10:
            text = "\(interest) teams (bidding war!)"
            color = .danger
        case 5...6:
            text = "\(interest) teams interested"
            color = .warning
        case 3...4:
            text = "\(interest) teams interested"
            color = .textSecondary
        default:
            text = "\(interest) team\(interest == 1 ? "" : "s") interested"
            color = .textTertiary
        }

        return Text(text)
            .font(.system(size: 9).weight(interest >= 7 ? .bold : .medium))
            .foregroundStyle(color)
    }

    // MARK: - Cap Impact % Badge (Task 1: "Will use X% of cap")

    private func capImpactPctBadge(asking: Int) -> some View {
        // Use team salaryCap if available, else $260M baseline
        let cap = team?.salaryCap ?? 260_000
        let pct = cap > 0 ? Double(asking) / Double(cap) * 100 : 0
        let pctRounded = Int(pct.rounded())
        let color: Color = {
            if pct >= 12 { return .danger }
            if pct >= 7 { return .warning }
            return .textSecondary
        }()
        let labelText = pctRounded <= 0 ? "<1% of cap" : "\(pctRounded)% of cap"
        return Text(labelText)
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Rumor System (Task 2)

    private struct Rumor {
        let text: String
        let icon: String
        let color: Color
    }

    private func rumorText(for player: Player, info: FreeAgentInfo?) -> Rumor? {
        if player.personality.motivation == .loyalty {
            return Rumor(text: "Hometown discount possible", icon: "house.fill", color: .accentBlue)
        }
        if let info = info {
            if info.marketInterest >= 7 {
                return Rumor(text: "\(info.marketInterest) teams interested — bidding war", icon: "flame.fill", color: .danger)
            }
            if info.marketInterest >= 4 {
                return Rumor(text: "\(info.marketInterest) teams interested", icon: "person.3.fill", color: .warning)
            }
        }
        if player.personality.motivation == .money && player.overall >= 80 {
            return Rumor(text: "Wants top-of-market money", icon: "dollarsign.circle.fill", color: .accentGold)
        }
        if player.personality.motivation == .winning {
            return Rumor(text: "Will take less for a contender", icon: "trophy.fill", color: .success)
        }
        if player.age >= 32 {
            return Rumor(text: "Likely short prove-it deal", icon: "clock.fill", color: .textSecondary)
        }
        return nil
    }

    // MARK: - Contract Structure Hint (Task 16)

    @ViewBuilder
    private func contractStructureHint(_ info: FreeAgentInfo) -> some View {
        if info.desiredYears >= 4 {
            let estGuaranteed = Double(info.askingPrice * info.desiredYears) * 0.5
            Text("Mostly guaranteed \u{2022} ~\(formatMillions(Int(estGuaranteed))) gtd")
                .font(.system(size: 9))
                .foregroundStyle(Color.warning.opacity(0.8))
        } else if info.desiredYears >= 2 {
            let estGuaranteed = Double(info.askingPrice * info.desiredYears) * 0.35
            Text("~\(formatMillions(Int(estGuaranteed))) gtd")
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Filtering & Sorting

    private var filteredAndSorted: [Player] {
        let filtered = allFreeAgents.filter { positionFilter.matches($0.position) }
        switch sortOption {
        case .overall:
            return filtered.sorted { $0.overall > $1.overall }
        case .age:
            return filtered.sorted { $0.age < $1.age }
        case .salary:
            return filtered.sorted {
                ContractEngine.estimateMarketValue(player: $0, salaryCap: currentSalaryCap) >
                ContractEngine.estimateMarketValue(player: $1, salaryCap: currentSalaryCap)
            }
        case .position:
            return filtered.sorted { $0.position.rawValue < $1.position.rawValue }
        case .interest:
            return filtered.sorted {
                (freeAgentData[$0.id]?.marketInterest ?? 0) > (freeAgentData[$1.id]?.marketInterest ?? 0)
            }
        case .schemeFit:
            return filtered.sorted {
                (computeSchemeFit(for: $0)?.sortOrder ?? 3) < (computeSchemeFit(for: $1)?.sortOrder ?? 3)
            }
        }
    }

    // MARK: - Targets Summary Bar (Task 14)

    private var targetsSummaryBar: some View {
        let targeted = allFreeAgents.filter { targetedPlayerIDs.contains($0.id) }
        let totalSalary = targeted.reduce(0) {
            $0 + ContractEngine.estimateMarketValue(player: $1, salaryCap: currentSalaryCap)
        }
        let capRemaining = (team?.availableCap ?? 0) - totalSalary

        return HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentGold)

            Text("\(targeted.count) target\(targeted.count == 1 ? "" : "s") selected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textPrimary)

            Text("\u{2022}")
                .foregroundStyle(Color.textTertiary)

            Text("~\(formatMillions(totalSalary))/yr")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)

            Text("\u{2022}")
                .foregroundStyle(Color.textTertiary)

            Text("Cap remaining: \(formatMillions(capRemaining))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(capRemaining >= 0 ? Color.success : Color.danger)

            Spacer()

            Button {
                targetedPlayerIDs.removeAll()
            } label: {
                Text("Clear")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.backgroundSecondary)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Helpers

    private func loadData() {
        // Load free agents: contractYearsRemaining == 0 and no team
        var descriptor = FetchDescriptor<Player>(
            predicate: #Predicate { $0.contractYearsRemaining == 0 && $0.teamID == nil && $0.isRetired == false }
        )
        descriptor.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        allFreeAgents = (try? modelContext.fetch(descriptor)) ?? []

        // Load player's team for cap info
        guard let teamID = career.teamID else { return }
        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDescriptor).first

        // Load team roster for starter comparison
        let rosterDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        teamRoster = (try? modelContext.fetch(rosterDescriptor)) ?? []

        // Load team coaches for scheme fit
        let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        teamCoaches = (try? modelContext.fetch(coachDescriptor)) ?? []

        // Load team draft picks for draft alternative hints
        let currentSeason = career.currentSeason
        let pickDescriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate { $0.currentTeamID == teamID && $0.seasonYear == currentSeason && $0.isComplete == false }
        )
        teamDraftPicks = (try? modelContext.fetch(pickDescriptor)) ?? []

        // Generate FA market data
        let cap = team?.salaryCap ?? 265_000
        let market = FreeAgencyEngine.generateFreeAgentMarket(allPlayers: allFreeAgents, salaryCap: cap)
        for fa in market {
            freeAgentData[fa.player.id] = FreeAgentInfo(
                askingPrice: fa.askingPrice,
                desiredYears: fa.desiredYears,
                marketInterest: fa.marketInterest
            )
        }
    }

    // MARK: - Starter Comparison (Task 7)

    private struct StarterComparisonResult {
        let label: String
        let color: Color
    }

    private func computeStarterComparison(for player: Player) -> StarterComparisonResult? {
        let starter = teamRoster
            .filter { $0.position == player.position }
            .max(by: { $0.overall < $1.overall })

        guard let starter else { return StarterComparisonResult(label: "No starter", color: .accentBlue) }

        let diff = player.overall - starter.overall
        let label: String
        let color: Color

        if diff > 2 {
            label = "+\(diff) vs starter"
            color = .success
        } else if diff < -2 {
            label = "\(diff) vs starter"
            color = .danger
        } else {
            label = diff == 0 ? "= starter" : (diff > 0 ? "+\(diff) vs starter" : "\(diff) vs starter")
            color = .warning
        }

        return StarterComparisonResult(label: label, color: color)
    }

    // MARK: - Scheme Fit (Task 8)

    private func computeSchemeFit(for player: Player) -> SchemeFitLevel? {
        let position = player.position

        // Determine team's scheme from coaching staff
        if position.side == .offense {
            guard let oc = teamCoaches.first(where: { $0.role == .offensiveCoordinator }),
                  let scheme = oc.offensiveScheme else { return nil }
            let score = evaluatePlayerOffensiveFit(player: player, scheme: scheme)
            return schemeFitFromScore(score)
        } else if position.side == .defense {
            guard let dc = teamCoaches.first(where: { $0.role == .defensiveCoordinator }),
                  let scheme = dc.defensiveScheme else { return nil }
            let score = evaluatePlayerDefensiveFit(player: player, scheme: scheme)
            return schemeFitFromScore(score)
        }
        return nil
    }

    private func evaluatePlayerOffensiveFit(player: Player, scheme: OffensiveScheme) -> Int {
        var score = 0
        let physical = player.physical

        switch player.positionAttributes {
        case .quarterback(let qb):
            switch scheme {
            case .airRaid, .spread:
                score = (qb.accuracyShort + qb.accuracyDeep + qb.armStrength) / 3
            case .westCoast, .proPassing:
                score = (qb.accuracyShort + qb.accuracyMid + qb.pocketPresence) / 3
            case .powerRun, .shanahan:
                score = (qb.pocketPresence + qb.scrambling + physical.strength) / 3
            case .rpo, .option:
                score = (qb.scrambling + physical.speed + qb.accuracyShort) / 3
            }
        case .wideReceiver(let wr):
            switch scheme {
            case .airRaid, .spread:
                score = (wr.routeRunning + wr.catching + physical.speed) / 3
            case .westCoast, .proPassing:
                score = (wr.routeRunning + wr.catching + wr.release) / 3
            case .powerRun, .shanahan:
                score = (physical.strength + wr.release + physical.speed) / 3
            default:
                score = (wr.routeRunning + wr.catching) / 2
            }
        case .runningBack(let rb):
            switch scheme {
            case .powerRun:
                score = (rb.breakTackle + rb.vision + physical.strength) / 3
            case .shanahan:
                score = (rb.vision + rb.elusiveness + physical.speed) / 3
            case .westCoast, .spread:
                score = (rb.receiving + rb.elusiveness + rb.vision) / 3
            default:
                score = (rb.vision + rb.elusiveness) / 2
            }
        case .offensiveLine(let ol):
            switch scheme {
            case .powerRun:
                score = (ol.runBlock + ol.anchor + physical.strength) / 3
            case .airRaid, .proPassing, .westCoast:
                score = (ol.passBlock + ol.anchor + physical.strength) / 3
            case .shanahan:
                score = (ol.pull + ol.runBlock + physical.agility) / 3
            default:
                score = (ol.runBlock + ol.passBlock) / 2
            }
        case .tightEnd(let te):
            switch scheme {
            case .airRaid, .spread, .westCoast:
                score = (te.catching + te.routeRunning + te.speed) / 3
            case .powerRun, .shanahan:
                score = (te.blocking + te.speed + physical.strength) / 3
            default:
                score = (te.catching + te.blocking) / 2
            }
        default:
            score = 65
        }
        return score
    }

    private func evaluatePlayerDefensiveFit(player: Player, scheme: DefensiveScheme) -> Int {
        var score = 0
        let physical = player.physical

        switch player.positionAttributes {
        case .defensiveBack(let db):
            switch scheme {
            case .pressMan:
                score = (db.manCoverage + db.press + physical.speed) / 3
            case .cover3, .tampa2:
                score = (db.zoneCoverage + db.ballSkills + physical.speed) / 3
            case .multiple, .hybrid:
                score = (db.manCoverage + db.zoneCoverage + db.press) / 3
            default:
                score = (db.manCoverage + db.zoneCoverage) / 2
            }
        case .linebacker(let lb):
            switch scheme {
            case .base34:
                score = (lb.tackling + lb.blitzing + physical.strength) / 3
            case .base43:
                score = (lb.tackling + lb.zoneCoverage + physical.speed) / 3
            case .tampa2:
                score = (lb.zoneCoverage + physical.speed + lb.tackling) / 3
            case .cover3:
                score = (lb.zoneCoverage + lb.tackling + physical.speed) / 3
            default:
                score = (lb.tackling + lb.zoneCoverage) / 2
            }
        case .defensiveLine(let dl):
            switch scheme {
            case .base43:
                score = (dl.passRush + dl.powerMoves + physical.strength) / 3
            case .base34:
                score = (dl.blockShedding + dl.powerMoves + physical.strength) / 3
            case .multiple, .hybrid:
                score = (dl.passRush + dl.finesseMoves + physical.agility) / 3
            default:
                score = (dl.passRush + dl.blockShedding) / 2
            }
        default:
            score = 65
        }
        return score
    }

    private func schemeFitFromScore(_ score: Int) -> SchemeFitLevel {
        switch score {
        case 75...:   return .good
        case 55..<75: return .ok
        default:      return .poor
        }
    }

    // MARK: - OVR Trend (Task 12)

    private struct OVRTrend {
        let iconName: String
        let color: Color
    }

    private func computeOVRTrend(for player: Player) -> OVRTrend? {
        let peak = player.position.peakAgeRange
        if player.age > peak.upperBound {
            return OVRTrend(iconName: "arrow.down.right", color: .danger)
        } else if player.age < peak.lowerBound {
            return OVRTrend(iconName: "arrow.up.right", color: .success)
        } else {
            // In peak range, check if near the end
            if player.age >= peak.upperBound - 1 {
                return OVRTrend(iconName: "arrow.right", color: .warning)
            }
            return nil
        }
    }

    // MARK: - Draft Alternative Hint (Task 13)

    private func draftAlternativeHint(for player: Player) -> String? {
        let marketValue = ContractEngine.estimateMarketValue(player: player, salaryCap: currentSalaryCap)
        // Only show for expensive players (> $5M/yr)
        guard marketValue > 5000 else { return nil }

        // Check if team has draft picks that could address this position
        let posGroup = positionGroupName(player.position)
        let bestPick = teamDraftPicks
            .filter { !$0.isComplete }
            .sorted(by: { $0.pickNumber < $1.pickNumber })
            .first

        guard let pick = bestPick else { return nil }

        let roundLabel = "Rd \(pick.round)"
        return "Draft alt: ~\(roundLabel) \(posGroup) pick available"
    }

    // MARK: - Team Needs (Task 9)

    private struct PositionNeed: Identifiable {
        let id = UUID()
        let position: String
        let level: NeedLevel
    }

    private func computeTeamNeeds() -> [PositionNeed] {
        guard !teamRoster.isEmpty else { return [] }

        // Define ideal roster counts per position group
        let idealCounts: [(label: String, positions: [Position], ideal: Int)] = [
            ("QB", [.QB], 2),
            ("RB", [.RB, .FB], 3),
            ("WR", [.WR], 4),
            ("TE", [.TE], 2),
            ("OL", [.LT, .LG, .C, .RG, .RT], 8),
            ("DE", [.DE], 3),
            ("DT", [.DT], 3),
            ("LB", [.OLB, .MLB], 5),
            ("CB", [.CB], 4),
            ("S", [.FS, .SS], 3),
        ]

        var needs: [PositionNeed] = []

        for group in idealCounts {
            let count = teamRoster.filter { group.positions.contains($0.position) }.count
            let bestOVR = teamRoster
                .filter { group.positions.contains($0.position) }
                .map(\.overall)
                .max() ?? 0

            let deficit = group.ideal - count
            let qualityIssue = bestOVR < 70

            if deficit >= 2 || (deficit >= 1 && qualityIssue) {
                needs.append(PositionNeed(position: group.label, level: .high))
            } else if deficit >= 1 || qualityIssue {
                needs.append(PositionNeed(position: group.label, level: .med))
            } else if bestOVR < 78 {
                needs.append(PositionNeed(position: group.label, level: .low))
            }
        }

        // Sort by priority
        return needs.sorted { needPriority($0.level) > needPriority($1.level) }
    }

    private func needPriority(_ level: NeedLevel) -> Int {
        switch level {
        case .high: return 3
        case .med:  return 2
        case .low:  return 1
        }
    }

    private func needLevelColor(_ level: NeedLevel) -> Color {
        switch level {
        case .high: return .danger
        case .med:  return .warning
        case .low:  return .textSecondary
        }
    }

    // MARK: - Target Toggle (Task 14)

    private func toggleTarget(_ playerID: UUID) {
        if targetedPlayerIDs.contains(playerID) {
            targetedPlayerIDs.remove(playerID)
        } else {
            targetedPlayerIDs.insert(playerID)
        }
    }

    // MARK: - Formatting Helpers

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

    /// Format count with comma grouping (Task 1).
    private func formattedCount(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func positionGroupName(_ position: Position) -> String {
        switch position {
        case .QB: return "QB"
        case .RB, .FB: return "RB"
        case .WR: return "WR"
        case .TE: return "TE"
        case .LT, .LG, .C, .RG, .RT: return "OL"
        case .DE, .DT: return "DL"
        case .OLB, .MLB: return "LB"
        case .CB, .FS, .SS: return "DB"
        case .K, .P: return "ST"
        }
    }
}

// MARK: - Free Agent Info Cache

private struct FreeAgentInfo {
    let askingPrice: Int
    let desiredYears: Int
    let marketInterest: Int
}

// MARK: - Preview

#Preview {
    NavigationStack {
        FreeAgencyView(career: Career(
            playerName: "Coach",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Player.self, Team.self, Coach.self, DraftPick.self], inMemory: true)
}
