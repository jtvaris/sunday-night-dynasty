import SwiftUI
import SwiftData

struct PlayerContractView: View {

    @Bindable var player: Player
    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showExtensionSheet = false
    @State private var showCutAlert = false
    @State private var team: Team?

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
        .sheet(isPresented: $showExtensionSheet) {
            if let team {
                NavigationStack {
                    ContractExtensionSheet(
                        player: player,
                        team: team,
                        capMode: career.capMode
                    )
                }
            }
        }
        .alert("Cut \(player.fullName)?", isPresented: $showCutAlert) {
            Button("Cut Player", role: .destructive) { cutPlayer() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will release \(player.fullName) and free up \(formatMillions(player.annualSalary)) in cap space. This action cannot be undone.")
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
                    .foregroundStyle(Color.accentGold)
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
            if let team {
                Button {
                    showExtensionSheet = true
                } label: {
                    Label("Extend Contract", systemImage: "signature")
                        .foregroundStyle(Color.accentGold)
                }

                Button(role: .destructive) {
                    showCutAlert = true
                } label: {
                    Label("Cut Player", systemImage: "person.badge.minus")
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
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

    /// Market value estimate: overall * position multiplier (in thousands)
    private var estimatedMarketValue: Int {
        let base = Double(player.overall) * Double(player.overall) * positionMultiplier
        return max(500, Int(base))
    }

    private var positionMultiplier: Double {
        switch player.position {
        case .QB:          return 8.0
        case .LT:          return 4.5
        case .WR, .TE:     return 3.5
        case .RB:          return 2.5
        case .DE, .DT:     return 3.5
        case .CB:          return 3.0
        case .OLB, .MLB:   return 2.8
        case .FS, .SS:     return 2.5
        case .FB, .LG, .C, .RG, .RT: return 2.2
        case .K, .P:       return 0.8
        }
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

    /// Simplified dead cap: 50% of remaining guaranteed value
    private var deadCapIfCut: Int {
        Int(Double(player.annualSalary) * 0.5)
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
                .foregroundStyle(Color.accentGold)
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
                .background(positionSideColor, in: RoundedRectangle(cornerRadius: 4))
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

    private func yearsColor(_ years: Int) -> Color {
        switch years {
        case 3...: return .success
        case 2:    return .accentGold
        case 1:    return .warning
        default:   return .danger
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

    // MARK: - Actions

    private func loadTeam() {
        guard let teamID = career.teamID else { return }
        let descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(descriptor).first
    }

    private func cutPlayer() {
        guard let team else { return }
        // Release the player: remove team association, zero out contract
        team.currentCapUsage = max(0, team.currentCapUsage - player.annualSalary)
        player.teamID = nil
        player.contractYearsRemaining = 0
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
