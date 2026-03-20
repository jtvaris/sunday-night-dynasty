import SwiftUI
import SwiftData

// MARK: - FranchiseTagView

struct FranchiseTagView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var team: Team?
    @State private var teamPlayers: [Player] = []
    @State private var allPlayers: [Player] = []
    @State private var showSkipConfirmation = false

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                if team != nil {
                    ScrollView {
                        VStack(spacing: 24) {
                            capBanner
                            tagRulesBanner
                            if !taggedPlayers.isEmpty {
                                taggedSection
                            }
                            expiringPlayersSection
                            skipTagButton
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
        .navigationTitle("Franchise Tag")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadData()
        }
        .alert("Skip Franchise Tag?", isPresented: $showSkipConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Skip", role: .destructive) {
                UserDefaults.standard.set(true, forKey: "franchiseTagVisited")
                dismiss()
            }
        } message: {
            Text("Are you sure? You won't be able to franchise tag any player this offseason.")
        }
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
                Text("Expiring Contracts")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Text("\(expiringPlayers.count)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.surfaceBorder, lineWidth: 1)
        )
    }

    // MARK: - Rules Banner

    private var tagRulesBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("Franchise Tag Rules")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("You can apply up to 1 franchise tag per season. Tagged players are kept at the average of the top 5 salaries at their position for one year.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.accentGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentGold.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Tagged Players Section

    private var taggedSection: some View {
        sectionCard(title: "Tagged Players", icon: "tag.fill") {
            VStack(spacing: 0) {
                ForEach(Array(taggedPlayers.enumerated()), id: \.element.id) { index, player in
                    taggedPlayerRow(player)
                    if index < taggedPlayers.count - 1 {
                        Divider()
                            .overlay(Color.surfaceBorder.opacity(0.5))
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    private func taggedPlayerRow(_ player: Player) -> some View {
        HStack(spacing: 12) {
            positionBadge(player.position)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("Age \(player.age)")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(player.overall) OVR")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.forRating(player.overall))
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatMillions(player.annualSalary))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
                Text("Tag Value")
                    .font(.system(size: 9).weight(.medium))
                    .foregroundStyle(Color.textTertiary)
            }

            Button {
                removeTag(from: player)
            } label: {
                Text("Remove")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.danger)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.danger.opacity(0.15), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.danger.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Expiring Players Section

    private var expiringPlayersSection: some View {
        sectionCard(title: "Expiring Contracts (\(expiringPlayers.count) players)", icon: "clock.badge.exclamationmark") {
            if expiringPlayers.isEmpty {
                emptyStateRow("No players with expiring contracts.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(expiringPlayers.enumerated()), id: \.element.id) { index, player in
                        expiringPlayerRow(player)
                        if index < expiringPlayers.count - 1 {
                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.5))
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }

    private func expiringPlayerRow(_ player: Player) -> some View {
        let tagCost = tagValue(for: player.position)
        let capAfterTag = (team?.availableCap ?? 0) - tagCost + player.annualSalary
        let recommendation = smartRecommendation(for: player)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                positionBadge(player.position)

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.fullName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        Text("Age \(player.age)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                        Text("\(player.overall) OVR")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.forRating(player.overall))
                        Text(formatMillions(player.annualSalary) + "/yr")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatMillions(tagCost))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                    Text("Tag Cost")
                        .font(.system(size: 9).weight(.medium))
                        .foregroundStyle(Color.textTertiary)
                }

                if hasUsedTag {
                    // Already used the tag — show disabled state
                    Text("Tag Used")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.backgroundTertiary, in: Capsule())
                } else {
                    Button {
                        applyTag(to: player, tagCost: tagCost)
                    } label: {
                        Text("Apply Tag")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentGold, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Recommendation
            HStack(spacing: 6) {
                Image(systemName: recommendation.icon)
                    .font(.caption)
                    .foregroundStyle(recommendation.color)
                Text(recommendation.text)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 46)

            // Cap impact
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text("Cap after tag: \(formatMillions(capAfterTag))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(capAfterTag >= 0 ? Color.textTertiary : Color.danger)
                if capAfterTag < 0 {
                    Text("OVER CAP")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.danger)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.danger.opacity(0.15), in: Capsule())
                }
            }
            .padding(.leading, 46)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Smart Recommendations

    private struct Recommendation {
        let text: String
        let icon: String
        let color: Color
    }

    private func smartRecommendation(for player: Player) -> Recommendation {
        let isPastPeak = player.age > player.position.peakAgeRange.upperBound

        if player.overall >= 85 {
            return Recommendation(
                text: "Elite player — strongly consider tagging.",
                icon: "star.fill",
                color: .accentGold
            )
        } else if isPastPeak {
            return Recommendation(
                text: "Aging veteran at \(player.age) — tag cost may not be worth it.",
                icon: "exclamationmark.triangle.fill",
                color: .warning
            )
        } else if player.overall < 75 {
            return Recommendation(
                text: "Role player — better to let walk and address in free agency.",
                icon: "arrow.right.circle.fill",
                color: .textTertiary
            )
        } else {
            return Recommendation(
                text: "Solid contributor — tag if you can't afford to lose him.",
                icon: "checkmark.circle.fill",
                color: .success
            )
        }
    }

    // MARK: - Section Card Shell

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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

    // MARK: - Skip Tag Button

    private var skipTagButton: some View {
        Button {
            showSkipConfirmation = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "forward.fill")
                    .font(.caption)
                Text("Skip — No Tag This Year")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Color.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Properties

    /// Players on the user's team with expiring contracts (not already tagged).
    private var expiringPlayers: [Player] {
        teamPlayers
            .filter { $0.contractYearsRemaining <= 1 && !$0.isFranchiseTagged }
            .sorted { $0.overall > $1.overall }
    }

    /// Players currently franchise-tagged on the user's team.
    private var taggedPlayers: [Player] {
        teamPlayers.filter { $0.isFranchiseTagged }
    }

    /// Whether the team has already used their franchise tag this season.
    private var hasUsedTag: Bool {
        !taggedPlayers.isEmpty
    }

    // MARK: - Tag Value Calculation

    private func tagValue(for position: Position) -> Int {
        let positionSalaries = allPlayers
            .filter { $0.position == position && $0.annualSalary > 0 }
            .map { $0.annualSalary }
        let value = ContractEngine.franchiseTagValue(position: position, topSalaries: positionSalaries)
        // Ensure a minimum tag value (league minimum floor)
        return max(value, 5_000)
    }

    // MARK: - Actions

    private func applyTag(to player: Player, tagCost: Int) {
        guard let team, !hasUsedTag else { return }

        ContractEngine.applyFranchiseTag(
            player: player,
            tagValue: tagCost,
            team: team
        )

        // Persist so CareerShellView picks up the change
        try? modelContext.save()
        UserDefaults.standard.set(true, forKey: "franchiseTagVisited")

        // Refresh local state
        loadData()
    }

    private func removeTag(from player: Player) {
        guard let team else { return }

        ContractEngine.removeFranchiseTag(
            player: player,
            team: team
        )

        // Persist so CareerShellView picks up the change
        try? modelContext.save()

        // Refresh local state
        loadData()
    }

    // MARK: - Helpers

    private func positionBadge(_ position: Position) -> some View {
        Text(position.rawValue)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 34)
            .padding(.vertical, 4)
            .background(positionSideColor(position), in: RoundedRectangle(cornerRadius: 4))
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

        guard let fetchedTeamID = team?.id else { return }
        var playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == fetchedTeamID }
        )
        playerDesc.sortBy = [SortDescriptor(\.annualSalary, order: .reverse)]
        teamPlayers = (try? modelContext.fetch(playerDesc)) ?? []

        // Fetch all players league-wide for tag value calculation
        let allDesc = FetchDescriptor<Player>()
        allPlayers = (try? modelContext.fetch(allDesc)) ?? []
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "Sam Greer", role: .gm, capMode: .simple)
    NavigationStack {
        FranchiseTagView(career: career)
    }
    .modelContainer(for: [Career.self, Team.self, Player.self], inMemory: true)
}
