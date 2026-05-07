import SwiftUI
import SwiftData

/// The central task manager sidebar. Shows the current phase, a guided task
/// list (like an RPG quest log), upcoming games, and season timeline.
/// Powered by `TaskGenerator` for phase-aware, contextual task lists.
struct CalendarSidebarView: View {

    let career: Career
    let team: Team?
    let upcomingGames: [Game]
    let allTeams: [UUID: Team]
    @Binding var tasks: [GameTask]
    let onTaskSelected: (TaskDestination) -> Void
    let onAdvancePhase: () -> Void
    let onDismiss: () -> Void

    // MARK: - Group Timeline State

    @State private var expandedGroups: Set<SeasonPhaseGroup> = []

    // MARK: - Derived State

    private var phaseInfo: TaskGenerator.PhaseInfo {
        TaskGenerator.phaseInfo(for: career.currentPhase)
    }

    private var requiredTasks: [GameTask] {
        tasks.filter { $0.isRequired }
    }

    private var optionalTasks: [GameTask] {
        tasks.filter { !$0.isRequired }
    }

    private var incompleteRequiredCount: Int {
        TaskGenerator.incompleteRequiredCount(in: tasks)
    }

    private var canAdvance: Bool {
        TaskGenerator.allRequiredComplete(in: tasks)
    }

    private var completedCount: Int {
        tasks.filter { $0.status == .done }.count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        phaseHeaderSection
                        if !requiredTasks.isEmpty {
                            taskSection(title: "Required", tasks: requiredTasks, isRequired: true)
                        }
                        if !optionalTasks.isEmpty {
                            taskSection(title: "Optional", tasks: optionalTasks, isRequired: false)
                        }
                        upcomingScheduleSection
                        seasonTimelineSection
                        advanceButton
                    }
                    .padding(20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Season Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
    }

    // MARK: - Phase Header

    private var phaseHeaderSection: some View {
        VStack(spacing: 12) {
            // Phase name — large, gold
            Text(phaseInfo.name)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.accentGold)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Season & week context
            HStack(spacing: 16) {
                Label("Season \(String(career.currentSeason))", systemImage: "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                Label("Week \(career.currentWeek)", systemImage: "clock")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }

            // Phase description
            Text(phaseInfo.description)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Progress bar: phase X of Y + task completion
            HStack {
                Text("Phase \(phaseInfo.order) of \(TaskGenerator.totalPhases)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textTertiary)
                Spacer()
                Text("\(completedCount)/\(tasks.count) tasks done")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(completedCount == tasks.count ? Color.accentGold : Color.textTertiary)
            }

            // Phase progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundTertiary)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentGold)
                        .frame(
                            width: tasks.isEmpty ? 0 : geo.size.width * CGFloat(completedCount) / CGFloat(tasks.count),
                            height: 6
                        )
                        .animation(.easeInOut(duration: 0.3), value: completedCount)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Task Sections

    private func taskSection(title: String, tasks sectionTasks: [GameTask], isRequired: Bool) -> some View {
        VStack(spacing: 10) {
            // Section header
            HStack {
                Image(systemName: isRequired ? "exclamationmark.triangle.fill" : "checklist")
                    .foregroundStyle(isRequired ? Color.accentGold : Color.textSecondary)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isRequired ? Color.accentGold : Color.textSecondary)
                Spacer()

                let incomplete = sectionTasks.filter { $0.status != .done }.count
                if incomplete > 0 {
                    Text("\(incomplete)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(isRequired ? Color.danger : Color.textTertiary))
                }
            }

            // Task cards
            ForEach(sectionTasks) { task in
                taskCard(task, isRequired: isRequired)
            }
        }
        .padding(16)
        .cardBackground()
    }

    private func taskCard(_ task: GameTask, isRequired: Bool) -> some View {
        Button {
            markInProgress(task)
            onTaskSelected(task.destination)
        } label: {
            HStack(spacing: 12) {
                // Status indicator
                taskStatusIcon(task)

                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(task.status == .done ? Color.textTertiary : Color.textPrimary)
                        .strikethrough(task.status == .done, color: Color.textTertiary)
                    Text(task.description)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }

                Spacer()

                // Navigation chevron (hidden when done)
                if task.status != .done {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isRequired && task.status != .done ? Color.accentGold.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(task.status == .done ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: task.status)
    }

    @ViewBuilder
    private func taskStatusIcon(_ task: GameTask) -> some View {
        ZStack {
            switch task.status {
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentGold)
            case .inProgress:
                Image(systemName: task.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentGold)
                    .frame(width: 20, height: 20)
            case .todo:
                Image(systemName: task.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 20, height: 20)
            }
        }
        .frame(width: 24)
    }

    // MARK: - Upcoming Schedule

    private var upcomingScheduleSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "sportscourt.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Upcoming Games")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }

            if upcomingGames.isEmpty {
                Text("No upcoming games")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(upcomingGames.prefix(3)) { game in
                    HStack {
                        let isHome = game.homeTeamID == career.teamID
                        let opponentID = isHome ? game.awayTeamID : game.homeTeamID
                        let opponentName = allTeams[opponentID]?.abbreviation ?? "???"
                        let prefix = isHome ? "vs" : "@"

                        Text("Wk \(game.week)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.textSecondary)
                            .frame(width: 44, alignment: .leading)

                        Text("\(prefix) \(opponentName)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textPrimary)

                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Season Timeline (Grouped)

    private var seasonTimelineSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Season Timeline")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }

            VStack(spacing: 0) {
                ForEach(SeasonPhaseGroup.allCases, id: \.self) { group in
                    groupSection(group)
                }
            }
        }
        .padding(16)
        .cardBackground()
        .onAppear {
            // Auto-expand the group containing the current phase the first time
            // the sidebar appears.
            if expandedGroups.isEmpty {
                expandedGroups.insert(career.currentPhase.group)
            }
        }
    }

    @ViewBuilder
    private func groupSection(_ group: SeasonPhaseGroup) -> some View {
        let isCurrentGroup = career.currentPhase.group == group
        let isExpanded = expandedGroups.contains(group)

        VStack(spacing: 0) {
            // Group header (collapsible)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded { expandedGroups.remove(group) }
                    else { expandedGroups.insert(group) }
                }
            } label: {
                HStack(spacing: DSSpacing.sm) {
                    Image(systemName: group.icon)
                        .foregroundStyle(isCurrentGroup ? Color.draftStealGold : Color.textSecondary)
                    Text(group.displayName.uppercased())
                        .font(.subheadline.weight(.heavy))
                        .tracking(0.8)
                        .foregroundStyle(isCurrentGroup ? Color.draftStealGold : Color.textPrimary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.vertical, DSSpacing.sm)
                .padding(.horizontal, DSSpacing.md)
            }
            .buttonStyle(.plain)

            // Sub-phases (when expanded)
            if isExpanded {
                ForEach(group.subPhases, id: \.self) { phase in
                    subPhaseRow(phase)
                }
            }
        }
        .background(isCurrentGroup ? Color.draftStealGold.opacity(0.05) : Color.clear)
        .overlay(
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    @ViewBuilder
    private func subPhaseRow(_ phase: SeasonPhase) -> some View {
        let status = phaseStatus(phase)
        HStack(spacing: DSSpacing.sm) {
            statusDot(status)
            Text(phaseLabel(phase))
                .font(.caption)
                .foregroundStyle(status == .current ? Color.textPrimary : Color.textSecondary)
                .fontWeight(status == .current ? .semibold : .regular)
            Spacer()
            if status == .current {
                Text("NOW")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.draftStealGold))
            } else if status == .done {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(Color.success)
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, DSSpacing.lg)
        .padding(.trailing, DSSpacing.md)
        .background(status == .current ? Color.draftStealGold.opacity(0.10) : Color.clear)
    }

    private enum PhaseStatus { case done, current, upcoming }

    private func phaseStatus(_ phase: SeasonPhase) -> PhaseStatus {
        if phase == career.currentPhase { return .current }
        let curIndex = SeasonPhase.allCases.firstIndex(of: career.currentPhase) ?? 0
        let phaseIndex = SeasonPhase.allCases.firstIndex(of: phase) ?? 0
        return phaseIndex < curIndex ? .done : .upcoming
    }

    private func statusDot(_ status: PhaseStatus) -> some View {
        Circle()
            .fill(status == .done ? Color.success : status == .current ? Color.draftStealGold : Color.textTertiary)
            .frame(width: 8, height: 8)
    }

    private func phaseLabel(_ phase: SeasonPhase) -> String {
        switch phase {
        case .proBowl:          return "Pro Bowl"
        case .superBowl:        return "Super Bowl"
        case .coachingChanges:  return "Coaching Changes"
        case .reviewRoster:     return "Roster Review"
        case .combine:          return "NFL Combine"
        case .freeAgency:       return "Free Agency"
        case .proDays:          return "Pro Days"
        case .draft:            return "NFL Draft"
        case .otas:             return "OTAs"
        case .trainingCamp:     return "Training Camp"
        case .preseason:        return "Preseason Games"
        case .rosterCuts:       return "Roster Cuts"
        case .regularSeason:    return "Regular Season"
        case .tradeDeadline:    return "Trade Deadline"
        case .playoffs:         return "Playoffs"
        }
    }

    // MARK: - Advance Button

    private var advanceButton: some View {
        VStack(spacing: 8) {
            if !canAdvance {
                Label(
                    "\(incompleteRequiredCount) required task\(incompleteRequiredCount == 1 ? "" : "s") remaining",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.accentGold)
            }

            Button {
                onAdvancePhase()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Advance to Next Phase")
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(canAdvance ? Color.accentGold : Color.backgroundTertiary)
                )
                .foregroundStyle(canAdvance ? Color.backgroundPrimary : Color.textTertiary)
            }
            .disabled(!canAdvance)
            .animation(.spring(duration: 0.3), value: canAdvance)
        }
    }

    // MARK: - Task Mutation

    private func markInProgress(_ task: GameTask) {
        guard task.status == .todo else { return }
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].status = .inProgress
        }
    }

}

#Preview {
    @Previewable @State var previewTasks: [GameTask] = TaskGenerator.generateTasks(
        for: .freeAgency,
        career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
        team: nil,
        hasExpiringContracts: true
    )

    CalendarSidebarView(
        career: {
            let c = Career(playerName: "John Doe", role: .gm, capMode: .simple)
            c.currentPhase = .freeAgency
            return c
        }(),
        team: nil,
        upcomingGames: [],
        allTeams: [:],
        tasks: $previewTasks,
        onTaskSelected: { _ in },
        onAdvancePhase: {},
        onDismiss: {}
    )
}
