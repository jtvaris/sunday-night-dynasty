import SwiftUI
import SwiftData

// MARK: - OwnerGoalsView

struct OwnerGoalsView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var team: Team?
    @State private var owner: Owner?
    @State private var goals: [SeasonGoal] = []

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                if let owner, let team {
                    ScrollView {
                        VStack(spacing: 20) {
                            ownerHeaderCard(owner: owner, team: team)

                            ForEach(sortedGoals) { goal in
                                goalCard(goal)
                            }

                            if isEndOfSeason {
                                seasonSummaryCard(team: team)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    loadingState
                }
            }
        }
        .navigationTitle("Season Goals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
    }

    // MARK: - Sorted Goals

    private var sortedGoals: [SeasonGoal] {
        let priorityOrder: [GoalPriority: Int] = [.primary: 0, .secondary: 1, .bonus: 2]
        return goals.sorted {
            (priorityOrder[$0.priority] ?? 99) < (priorityOrder[$1.priority] ?? 99)
        }
    }

    // MARK: - Owner Header Card

    private func ownerHeaderCard(owner: Owner, team: Team) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.backgroundTertiary)
                    .frame(width: 64, height: 64)
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentGold)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(owner.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text(team.fullName)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                Text("Season \(String(career.currentSeason)) Goals")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            VStack(spacing: 4) {
                Text("\(achievedCount)/\(goals.count)")
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .foregroundStyle(achievedCount == goals.count ? Color.accentGold : Color.textPrimary)
                Text("Achieved")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(minWidth: 60)
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Goal Card

    private func goalCard(_ goal: SeasonGoal) -> some View {
        VStack(alignment: .leading, spacing: 14) {

            // Header row: priority badge + title + status icon
            HStack(spacing: 10) {
                priorityBadge(goal.priority)

                Text(goal.title)
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                Spacer()

                goalStatusIcon(goal)
            }

            // Description
            Text(goal.description)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Progress bar (only for quantitative goals)
            if let target = goal.target {
                progressBar(progress: goal.progress, target: target, achieved: goal.isAchieved)

                HStack {
                    Text("\(goal.progress) of \(target)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(progressLabel(goal))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(goalStatusColor(goal))
                }
            } else {
                // Boolean goal — show status label only
                HStack {
                    Spacer()
                    Text(progressLabel(goal))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(goalStatusColor(goal))
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(goalBorderColor(goal), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Progress Bar

    private func progressBar(progress: Int, target: Int, achieved: Bool) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.backgroundTertiary)
                    .frame(height: 10)

                RoundedRectangle(cornerRadius: 6)
                    .fill(progressBarGradient(progress: progress, target: target, achieved: achieved))
                    .frame(
                        width: geo.size.width * min(CGFloat(progress) / CGFloat(max(target, 1)), 1.0),
                        height: 10
                    )
                    .animation(.easeOut(duration: 0.5), value: progress)
            }
        }
        .frame(height: 10)
    }

    private func progressBarGradient(progress: Int, target: Int, achieved: Bool) -> LinearGradient {
        let color: Color = achieved ? .accentGold : progressColor(progress: progress, target: target)
        return LinearGradient(
            colors: [color.opacity(0.7), color],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private func progressColor(progress: Int, target: Int) -> Color {
        guard target > 0 else { return .textTertiary }
        let ratio = Double(progress) / Double(target)
        if ratio >= 1.0  { return .accentGold }
        if ratio >= 0.6  { return .success }
        if ratio >= 0.35 { return .warning }
        return .danger
    }

    // MARK: - Priority Badge

    private func priorityBadge(_ priority: GoalPriority) -> some View {
        Text(priorityLabel(priority))
            .font(.caption2.weight(.bold))
            .foregroundStyle(priorityTextColor(priority))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(priorityColor(priority).opacity(0.2), in: Capsule())
            .overlay(Capsule().strokeBorder(priorityColor(priority).opacity(0.5), lineWidth: 1))
    }

    private func priorityLabel(_ priority: GoalPriority) -> String {
        switch priority {
        case .primary:   return "PRIMARY"
        case .secondary: return "SECONDARY"
        case .bonus:     return "BONUS"
        }
    }

    private func priorityColor(_ priority: GoalPriority) -> Color {
        switch priority {
        case .primary:   return .accentGold
        case .secondary: return .accentBlue
        case .bonus:     return .success
        }
    }

    private func priorityTextColor(_ priority: GoalPriority) -> Color {
        priorityColor(priority)
    }

    // MARK: - Goal Status

    private func goalStatusIcon(_ goal: SeasonGoal) -> some View {
        Group {
            if goal.isAchieved {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.accentGold)
                    .font(.system(size: 16))
            } else if goalIsFailed(goal) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.danger)
                    .font(.system(size: 16))
            } else if goalIsAtRisk(goal) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.warning)
                    .font(.system(size: 14))
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Color.success)
                    .font(.system(size: 16))
            }
        }
    }

    private func progressLabel(_ goal: SeasonGoal) -> String {
        if goal.isAchieved    { return "Achieved" }
        if goalIsFailed(goal) { return "Failed" }
        if goalIsAtRisk(goal) { return "At Risk" }
        return "On Track"
    }

    private func goalStatusColor(_ goal: SeasonGoal) -> Color {
        if goal.isAchieved    { return .accentGold }
        if goalIsFailed(goal) { return .danger }
        if goalIsAtRisk(goal) { return .warning }
        return .success
    }

    private func goalBorderColor(_ goal: SeasonGoal) -> Color {
        if goal.isAchieved    { return Color.accentGold.opacity(0.5) }
        if goalIsFailed(goal) { return Color.danger.opacity(0.4) }
        if goalIsAtRisk(goal) { return Color.warning.opacity(0.4) }
        return Color.surfaceBorder
    }

    /// Heuristic for "failed" — past midseason (week 12+) and less than 30% progress on a quant goal.
    private func goalIsFailed(_ goal: SeasonGoal) -> Bool {
        guard !goal.isAchieved else { return false }
        guard isEndOfSeason else { return false }
        return !goal.isAchieved
    }

    /// At risk: more than half of season gone and below 50% of target.
    private func goalIsAtRisk(_ goal: SeasonGoal) -> Bool {
        guard !goal.isAchieved else { return false }
        let week = career.currentWeek
        guard week >= 9 else { return false }
        if let target = goal.target, target > 0 {
            return Double(goal.progress) / Double(target) < 0.5
        }
        // Boolean goal with no progress past week 9
        return goal.progress == 0
    }

    // MARK: - Season Summary Card

    private func seasonSummaryCard(team: Team) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(Color.accentGold)
                Text("Season Summary")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
            }

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                summaryStatColumn(
                    label: "Goals Achieved",
                    value: "\(achievedCount)/\(goals.count)",
                    color: achievedCount == goals.count ? .accentGold : .textPrimary
                )
                summaryStatColumn(
                    label: "Final Record",
                    value: team.record,
                    color: team.wins >= team.losses ? .success : .danger
                )
                summaryStatColumn(
                    label: "Cap Used",
                    value: String(format: "%.0f%%", capUsagePct(team) * 100),
                    color: capUsagePct(team) > 0.95 ? .warning : .success
                )
            }

            Text(seasonSummaryText(team: team))
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundTertiary)
                )
        }
        .padding(20)
        .cardBackground()
    }

    private func summaryStatColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .tint(Color.accentGold)
                .scaleEffect(1.4)
            Text("Loading Goals…")
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
    }

    // MARK: - Helpers

    private var achievedCount: Int {
        goals.filter(\.isAchieved).count
    }

    private var isEndOfSeason: Bool {
        career.currentPhase == .superBowl || career.currentWeek >= 18
    }

    private func capUsagePct(_ team: Team) -> Double {
        guard team.salaryCap > 0 else { return 0 }
        return Double(team.currentCapUsage) / Double(team.salaryCap)
    }

    private func seasonSummaryText(team: Team) -> String {
        let achieved = achievedCount
        let total = goals.count
        let record = team.record

        if achieved == total {
            return "Outstanding season. Every goal was met. \(owner?.name ?? "The owner") is thrilled with this franchise's direction."
        } else if achieved >= total / 2 {
            return "A decent season — \(achieved) of \(total) goals achieved with a \(record) record. There is room for growth next year."
        } else {
            return "A disappointing campaign. Only \(achieved) of \(total) goals met and a final record of \(record). \(owner?.name ?? "The owner") expects more."
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first

        guard let fetchedTeam = team else { return }
        owner = fetchedTeam.owner

        guard let fetchedOwner = owner else { return }
        let generated = OwnerGoalsEngine.generateSeasonGoals(
            team: fetchedTeam,
            owner: fetchedOwner,
            career: career
        )
        goals = OwnerGoalsEngine.evaluateGoalProgress(
            goals: generated,
            team: fetchedTeam,
            career: career
        )
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "Chris Madden", role: .gm, capMode: .simple)
    NavigationStack {
        OwnerGoalsView(career: career)
    }
    .modelContainer(for: [Career.self, Team.self, Owner.self, Player.self], inMemory: true)
}
