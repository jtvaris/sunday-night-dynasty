import SwiftUI
import SwiftData

// MARK: - Position Group Definition

private struct PositionGroup: Identifiable {
    let id: String
    let label: String
    let positions: [Position]

    static let allGroups: [PositionGroup] = [
        PositionGroup(id: "QB",  label: "QB",  positions: [.QB]),
        PositionGroup(id: "RB",  label: "RB",  positions: [.RB, .FB]),
        PositionGroup(id: "WR",  label: "WR",  positions: [.WR]),
        PositionGroup(id: "TE",  label: "TE",  positions: [.TE]),
        PositionGroup(id: "OL",  label: "OL",  positions: [.LT, .LG, .C, .RG, .RT]),
        PositionGroup(id: "DL",  label: "DL",  positions: [.DE, .DT]),
        PositionGroup(id: "LB",  label: "LB",  positions: [.OLB, .MLB]),
        PositionGroup(id: "DB",  label: "DB",  positions: [.CB, .FS, .SS]),
        PositionGroup(id: "ST",  label: "ST",  positions: [.K, .P]),
    ]
}

// MARK: - Key Decision

private struct KeyDecision: Identifiable {
    enum DecisionType {
        case expiringContract, overpaid, underpaid, agingVeteran
    }
    let id: UUID
    let player: Player
    let type: DecisionType
    let recommendation: String
}

// MARK: - RosterEvaluationView

struct RosterEvaluationView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var players: [Player] = []

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                if team != nil {
                    ScrollView {
                        VStack(spacing: 24) {
                            positionGradesSection
                            keyDecisionsSection
                            strengthsWeaknessesSection
                            capOutlookSection
                        }
                        .padding(24)
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ProgressView()
                        .tint(Color.accentGold)
                        .padding(.top, 80)
                }
            }
        }
        .navigationTitle("Roster Evaluation")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
    }

    // MARK: - Section 1: Position Group Grades

    private var positionGradesSection: some View {
        sectionCard(title: "Position Group Grades", icon: "chart.bar.doc.horizontal") {
            VStack(spacing: 0) {
                // Column headers
                HStack {
                    Text("Group")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 44, alignment: .leading)
                    Text("Avg OVR")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 64, alignment: .center)
                    Text("Grade")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 44, alignment: .center)
                    Text("Depth")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 80, alignment: .center)
                    Spacer()
                    Text("Need")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                Divider().overlay(Color.surfaceBorder)

                ForEach(Array(PositionGroup.allGroups.enumerated()), id: \.element.id) { index, group in
                    positionGroupRow(group: group)

                    if index < PositionGroup.allGroups.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    private func positionGroupRow(group: PositionGroup) -> some View {
        let groupPlayers = players.filter { group.positions.contains($0.position) }
        let avgOvr = averageOverall(groupPlayers)
        let grade = letterGrade(avgOvr)
        let depth = groupPlayers.count
        let isBiggestNeed = biggestNeedGroup?.id == group.id

        return HStack(alignment: .center) {
            // Group label
            Text(group.label)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 44, alignment: .leading)

            // Avg overall
            Text(groupPlayers.isEmpty ? "—" : "\(avgOvr)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(groupPlayers.isEmpty ? Color.textTertiary : Color.forRating(avgOvr))
                .frame(width: 64, alignment: .center)

            // Grade badge
            Text(grade.letter)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(grade.color)
                .frame(width: 28)
                .padding(.vertical, 3)
                .background(grade.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 44)

            // Depth pill
            depthPill(count: depth, group: group)
                .frame(width: 80)

            Spacer()

            // Biggest need indicator
            if isBiggestNeed {
                Label("Need", systemImage: "exclamationmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.danger)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isBiggestNeed ? Color.danger.opacity(0.05) : Color.clear)
    }

    private func depthPill(count: Int, group: PositionGroup) -> some View {
        let minPlayers = group.positions.count   // at minimum 1 per position in group
        let isDeep     = count >= minPlayers + 2
        let isThin     = count == minPlayers || count == minPlayers + 1
        let isCritical = count < minPlayers

        let color: Color = isCritical ? .danger : (isThin ? .warning : .success)
        let label = isCritical ? "Critical" : (isThin ? "Thin" : "Deep")

        return HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(count == 0 ? "Empty" : "\(count) — \(label)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(color)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        // Suppress unused-variable warning
        .accessibilityLabel("\(count) players, \(label)")
        .onChange(of: isDeep) { _ in }
    }

    // MARK: - Section 2: Key Decisions

    private var keyDecisionsSection: some View {
        sectionCard(title: "Key Decisions", icon: "checklist.unchecked") {
            let decisions = buildKeyDecisions()

            if decisions.isEmpty {
                emptyStateRow("No pressing decisions at this time.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(decisions.enumerated()), id: \.element.id) { index, decision in
                        keyDecisionRow(decision)
                        if index < decisions.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }

    private func keyDecisionRow(_ decision: KeyDecision) -> some View {
        HStack(spacing: 12) {
            // Position badge
            Text(decision.player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34)
                .padding(.vertical, 4)
                .background(positionSideColor(decision.player.position), in: RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(decision.player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    decisionTypeBadge(decision.type)
                }
                Text(decision.recommendation)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(decision.player.overall) OVR")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.forRating(decision.player.overall))
                Text(formatMillions(decision.player.annualSalary))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func decisionTypeBadge(_ type: KeyDecision.DecisionType) -> some View {
        let (label, color): (String, Color) = {
            switch type {
            case .expiringContract: return ("EXPIRING", .warning)
            case .overpaid:         return ("OVERPAID", .danger)
            case .underpaid:        return ("UNDERPAID", .success)
            case .agingVeteran:     return ("AGING", .textTertiary)
            }
        }()

        return Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
    }

    // MARK: - Section 3: Strengths & Weaknesses

    private var strengthsWeaknessesSection: some View {
        sectionCard(title: "Roster Strengths & Weaknesses", icon: "chart.xyaxis.line") {
            VStack(spacing: 16) {
                // Top 5
                groupBlock(title: "Top 5 Players", icon: "star.fill", iconColor: .accentGold) {
                    VStack(spacing: 0) {
                        ForEach(Array(top5Players.enumerated()), id: \.element.id) { index, player in
                            playerSnapshotRow(player: player, rank: index + 1)
                            if index < top5Players.count - 1 {
                                Divider().overlay(Color.surfaceBorder.opacity(0.4)).padding(.horizontal, 8)
                            }
                        }
                    }
                }

                Divider().overlay(Color.surfaceBorder)

                // Bottom 5 starters
                groupBlock(title: "Bottom 5 Starters", icon: "arrow.down.circle.fill", iconColor: .danger) {
                    VStack(spacing: 0) {
                        ForEach(Array(bottom5Starters.enumerated()), id: \.element.id) { index, player in
                            playerSnapshotRow(player: player, rank: nil)
                            if index < bottom5Starters.count - 1 {
                                Divider().overlay(Color.surfaceBorder.opacity(0.4)).padding(.horizontal, 8)
                            }
                        }
                    }
                }

                Divider().overlay(Color.surfaceBorder)

                // Biggest need callout
                if let needGroup = biggestNeedGroup {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Biggest Need: \(needGroup.label)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text("The \(needGroup.label) group is the weakest on the roster. Prioritize this position in free agency or the draft.")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .background(Color.warning.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.warning.opacity(0.3), lineWidth: 1))
                }
            }
        }
    }

    private func groupBlock<Content: View>(
        title: String,
        icon: String,
        iconColor: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .font(.subheadline)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
            }
            content()
        }
    }

    private func playerSnapshotRow(player: Player, rank: Int?) -> some View {
        HStack(spacing: 10) {
            if let rank {
                Text("#\(rank)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 26, alignment: .trailing)
            } else {
                Spacer().frame(width: 26)
            }

            Text(player.position.rawValue)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 34)
                .padding(.vertical, 3)
                .background(positionSideColor(player.position), in: RoundedRectangle(cornerRadius: 4))

            Text(player.fullName)
                .font(.subheadline)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Spacer()

            Text("\(player.overall)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.forRating(player.overall))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Section 4: Cap Outlook

    private var capOutlookSection: some View {
        sectionCard(title: "Cap Outlook", icon: "dollarsign.circle.fill") {
            guard let team else {
                return AnyView(emptyStateRow("No cap data available."))
            }

            let expiringCap = expiringContractCapRelief
            let projectedUsage = max(0, team.currentCapUsage - expiringCap)
            let projectedSpace  = team.salaryCap - projectedUsage

            return AnyView(
                VStack(spacing: 16) {
                    // Four stat columns
                    HStack(spacing: 0) {
                        capStatColumn(label: "Total Cap",    value: formatMillions(team.salaryCap),      color: .accentGold)
                        capStatColumn(label: "Used",         value: formatMillions(team.currentCapUsage), color: capUsageColor(team))
                        capStatColumn(label: "Available",    value: formatMillions(team.availableCap),    color: team.availableCap >= 0 ? .success : .danger)
                        capStatColumn(label: "Dead Cap Est.", value: formatMillions(estimatedDeadCap),    color: estimatedDeadCap > 5_000 ? .danger : .textSecondary)
                    }

                    Divider().overlay(Color.surfaceBorder)

                    // Projected cap after expiring contracts
                    projectedCapRow(
                        label: "Expiring Contracts Relief",
                        value: "+\(formatMillions(expiringCap))",
                        color: .success
                    )
                    projectedCapRow(
                        label: "Projected Cap After Expirations",
                        value: formatMillions(projectedUsage),
                        color: .textPrimary
                    )
                    projectedCapRow(
                        label: "Projected FA Budget",
                        value: formatMillions(projectedSpace),
                        color: projectedSpace > 20_000 ? .success : (projectedSpace > 5_000 ? .accentGold : .danger)
                    )

                    Divider().overlay(Color.surfaceBorder)

                    // Cap bar
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Cap Usage")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            Spacer()
                            Text(String(format: "%.1f%%", capPct(team) * 100))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(capUsageColor(team))
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 10)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(capBarGradient(team))
                                    .frame(width: geo.size.width * min(capPct(team), 1.0), height: 10)
                            }
                        }
                        .frame(height: 10)
                    }
                }
            )
        }
    }

    private func capStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func projectedCapRow(label: String, value: String, color: Color) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    // MARK: - Section Card Shell

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Gold header
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: 15))
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.accentGold.opacity(0.08))

            Divider().overlay(Color.surfaceBorder)

            content()
                .padding(.vertical, 8)
        }
        .cardBackground()
    }

    private func emptyStateRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.textTertiary)
            .padding(20)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Computed Roster Properties

    private var top5Players: [Player] {
        players.sorted { $0.overall > $1.overall }.prefix(5).map { $0 }
    }

    /// Starters: the best-rated player at each individual starting position.
    private var startersByPosition: [Player] {
        let positionOrder: [Position] = [
            .QB, .RB, .WR, .WR, .TE,
            .LT, .LG, .C, .RG, .RT,
            .DE, .DT, .DT, .DE,
            .OLB, .MLB, .MLB, .OLB,
            .CB, .CB, .FS, .SS,
            .K, .P
        ]
        var result: [Player] = []
        var used = Set<UUID>()

        for pos in positionOrder {
            if let starter = players
                .filter({ $0.position == pos && !used.contains($0.id) })
                .sorted(by: { $0.overall > $1.overall })
                .first {
                result.append(starter)
                used.insert(starter.id)
            }
        }
        return result
    }

    private var bottom5Starters: [Player] {
        startersByPosition
            .sorted { $0.overall < $1.overall }
            .prefix(5)
            .map { $0 }
    }

    private var biggestNeedGroup: PositionGroup? {
        PositionGroup.allGroups.min(by: { a, b in
            averageOverall(players.filter { a.positions.contains($0.position) })
            < averageOverall(players.filter { b.positions.contains($0.position) })
        })
    }

    // MARK: - Key Decision Builder

    private func buildKeyDecisions() -> [KeyDecision] {
        var decisions: [KeyDecision] = []

        for player in players {
            let marketValue = ContractEngine.estimateMarketValue(player: player)
            let salary = player.annualSalary
            let isPastPeak = player.age > player.position.peakAgeRange.upperBound

            // Expiring contracts
            if player.contractYearsRemaining <= 1 {
                let rec = expiringRecommendation(player: player, marketValue: marketValue)
                decisions.append(KeyDecision(
                    id: player.id,
                    player: player,
                    type: .expiringContract,
                    recommendation: rec
                ))
            }
            // Overpaid: salary is more than 30% above market value
            else if salary > Int(Double(marketValue) * 1.3) {
                let excess = formatMillions(salary - marketValue)
                decisions.append(KeyDecision(
                    id: player.id,
                    player: player,
                    type: .overpaid,
                    recommendation: "Paying \(excess) above market value. Consider restructuring or cutting."
                ))
            }
            // Underpaid: market value more than 40% above salary — trade/holdout risk
            else if marketValue > Int(Double(salary) * 1.4) && player.contractYearsRemaining <= 2 {
                let upside = formatMillions(marketValue - salary)
                decisions.append(KeyDecision(
                    id: player.id,
                    player: player,
                    type: .underpaid,
                    recommendation: "Worth \(upside) more than current deal. Extension risk — act before he walks."
                ))
            }
            // Aging veteran: past peak, still on a meaningful salary
            else if isPastPeak && salary > 3_000 && player.overall < 75 {
                let yearsOver = player.age - player.position.peakAgeRange.upperBound
                decisions.append(KeyDecision(
                    id: player.id,
                    player: player,
                    type: .agingVeteran,
                    recommendation: "\(yearsOver) year\(yearsOver == 1 ? "" : "s") past peak age. Declining production — evaluate before committing long-term."
                ))
            }
        }

        // Sort: expiring first, then overpaid, underpaid, aging
        let order: [KeyDecision.DecisionType: Int] = [
            .expiringContract: 0, .overpaid: 1, .underpaid: 2, .agingVeteran: 3
        ]
        return decisions
            .sorted { (order[$0.type] ?? 99) < (order[$1.type] ?? 99) }
            .prefix(12)
            .map { $0 }
    }

    private func expiringRecommendation(player: Player, marketValue: Int) -> String {
        let isPastPeak = player.age > player.position.peakAgeRange.upperBound
        if player.overall >= 80 && !isPastPeak {
            return "Elite player still in his prime. Prioritize extension before free agency."
        } else if player.overall >= 70 && !isPastPeak {
            return "Solid contributor with value. Re-sign at or slightly above market."
        } else if isPastPeak || player.overall < 65 {
            return "Declining output relative to cost. Consider letting him walk."
        } else {
            return "Franchise tag is an option to buy time before committing long-term."
        }
    }

    // MARK: - Cap Helpers

    private var expiringContractCapRelief: Int {
        players
            .filter { $0.contractYearsRemaining <= 1 }
            .reduce(0) { $0 + $1.annualSalary }
    }

    private var estimatedDeadCap: Int {
        // Approximate: players past peak and below 70 OVR who could be cut
        players
            .filter { $0.age > $0.position.peakAgeRange.upperBound && $0.overall < 70 && $0.contractYearsRemaining > 1 }
            .reduce(0) { $0 + $1.annualSalary / 2 }   // rough dead-cap estimate
    }

    private func capPct(_ team: Team) -> Double {
        guard team.salaryCap > 0 else { return 0 }
        return Double(team.currentCapUsage) / Double(team.salaryCap)
    }

    private func capUsageColor(_ team: Team) -> Color {
        let pct = capPct(team)
        if pct > 1.0 { return .danger }
        if pct > 0.9 { return .warning }
        return .textSecondary
    }

    private func capBarGradient(_ team: Team) -> LinearGradient {
        let pct = capPct(team)
        let color: Color = pct > 1.0 ? .danger : (pct > 0.9 ? .warning : .accentGold)
        return LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Grade Helpers

    private struct GradeInfo {
        let letter: String
        let color: Color
    }

    private func letterGrade(_ avg: Int) -> GradeInfo {
        switch avg {
        case 85...: return GradeInfo(letter: "A", color: .success)
        case 75..<85: return GradeInfo(letter: "B", color: .accentGold)
        case 65..<75: return GradeInfo(letter: "C", color: .warning)
        case 55..<65: return GradeInfo(letter: "D", color: .danger)
        default:      return GradeInfo(letter: "F", color: .danger)
        }
    }

    private func averageOverall(_ group: [Player]) -> Int {
        guard !group.isEmpty else { return 0 }
        return group.reduce(0) { $0 + $1.overall } / group.count
    }

    // MARK: - Formatting Helpers

    private func formatMillions(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if millions >= 1.0 {
            return String(format: "$%.1fM", millions)
        } else {
            return "$\(thousands)K"
        }
    }

    private func positionSideColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        guard let fetchedTeamID = team?.id else { return }
        var playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == fetchedTeamID }
        )
        playerDesc.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        players = (try? modelContext.fetch(playerDesc)) ?? []
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "Sam Greer", role: .gm, capMode: .simple)
    NavigationStack {
        RosterEvaluationView(career: career)
    }
    .modelContainer(for: [Career.self, Team.self, Player.self, Owner.self], inMemory: true)
}
