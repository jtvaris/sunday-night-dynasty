import SwiftUI

/// A unified vertical Timeline+Tasks panel inspired by Football Manager's
/// Messages panel. Shows the current phase with its tasks expanded, plus the
/// next 2-3 upcoming phases with preview tasks, and an advance button.
/// Replaces the separate `phaseTasksSection` and advance button in the dashboard.
struct TimelineTasksPanel: View {

    let career: Career
    @Binding var tasks: [GameTask]
    let onTaskSelected: (TaskDestination) -> Void
    let onAdvance: () -> Void
    let canAdvance: Bool

    /// How many upcoming phases (beyond current) to show fully expanded.
    private let upcomingPhaseCount = 3

    // MARK: - Ordered Phases

    private static let orderedPhases: [SeasonPhase] = [
        .superBowl,
        .proBowl,
        .coachingChanges,
        .combine,
        .freeAgency,
        .draft,
        .otas,
        .trainingCamp,
        .preseason,
        .rosterCuts,
        .regularSeason,
        .tradeDeadline,
        .playoffs
    ]

    private var currentIndex: Int {
        Self.orderedPhases.firstIndex(of: career.currentPhase) ?? 0
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            panelHeader
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // Scrollable phases list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Past phases (collapsed)
                    ForEach(pastPhases, id: \.phase) { entry in
                        pastPhaseRow(entry)
                    }

                    // Current phase (expanded with real tasks)
                    currentPhaseSection

                    // Advance button
                    advanceSection
                        .padding(.horizontal, 14)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                    // Upcoming phases (expanded with preview tasks)
                    ForEach(Array(upcomingPhaseTasks.enumerated()), id: \.element.phase) { index, entry in
                        upcomingPhaseSection(entry, isLast: index == upcomingPhaseTasks.count - 1)
                    }

                    // Remaining collapsed future phases
                    if remainingFutureCount > 0 {
                        remainingPhasesIndicator
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .background(Color.backgroundSecondary)
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.clipboard.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentGold)

            Text("YOUR \(seasonLabel)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.accentGold)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()

            let doneCount = tasks.filter { $0.status == .done }.count
            Text("\(doneCount)/\(tasks.count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var seasonLabel: String {
        let phase = career.currentPhase
        switch phase {
        case .regularSeason, .tradeDeadline, .playoffs, .superBowl:
            return "SEASON"
        default:
            return "OFFSEASON"
        }
    }

    // MARK: - Past Phases

    private var pastPhases: [(phase: SeasonPhase, name: String)] {
        guard currentIndex > 0 else { return [] }
        return (0..<currentIndex).map { i in
            let phase = Self.orderedPhases[i]
            return (phase, Self.phaseName(phase))
        }
    }

    private func pastPhaseRow(_ entry: (phase: SeasonPhase, name: String)) -> some View {
        HStack(spacing: 10) {
            // Vertical timeline connector
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.textTertiary.opacity(0.3))
                    .frame(width: 2, height: 10)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary.opacity(0.5))

                Rectangle()
                    .fill(Color.textTertiary.opacity(0.3))
                    .frame(width: 2, height: 10)
            }

            Text(entry.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .strikethrough(true, color: Color.textTertiary.opacity(0.5))

            Spacer()

            Text("Complete")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textTertiary.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .opacity(0.6)
    }

    // MARK: - Current Phase

    private var currentPhaseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phase header row
            HStack(spacing: 10) {
                // Timeline dot
                VStack(spacing: 0) {
                    if currentIndex > 0 {
                        Rectangle()
                            .fill(Color.accentGold.opacity(0.5))
                            .frame(width: 2, height: 8)
                    } else {
                        Color.clear.frame(width: 2, height: 8)
                    }

                    Circle()
                        .fill(Color.accentGold)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: Self.phaseIcon(career.currentPhase))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.backgroundPrimary)
                        )

                    Rectangle()
                        .fill(Color.accentGold.opacity(0.5))
                        .frame(width: 2, height: 8)
                }

                Text(Self.phaseName(career.currentPhase))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .textCase(.uppercase)

                Spacer()

                Text("NOW")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentGold))

                Text(Self.phaseDate(career.currentPhase))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Task rows for current phase
            VStack(spacing: 0) {
                let required = tasks.filter { $0.isRequired }
                let optional = tasks.filter { !$0.isRequired }

                ForEach(required) { task in
                    currentTaskRow(task, isRequired: true)
                }

                ForEach(optional) { task in
                    currentTaskRow(task, isRequired: false)
                }
            }
            .padding(.leading, 36) // Align with text after timeline dot
            .padding(.trailing, 14)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentGold.opacity(0.04))
                .padding(.horizontal, 6)
        )
    }

    private func currentTaskRow(_ task: GameTask, isRequired: Bool) -> some View {
        Button {
            onTaskSelected(task.destination)
        } label: {
            HStack(spacing: 8) {
                // Status dot
                taskStatusIcon(task, isRequired: isRequired)

                // Task text
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(task.title)
                            .font(.system(size: 13, weight: task.status == .done ? .regular : .medium))
                            .foregroundStyle(task.status == .done ? Color.textTertiary : Color.textPrimary)
                            .strikethrough(task.status == .done, color: Color.textTertiary)
                            .lineLimit(1)

                        if isRequired && task.status != .done {
                            Text("Required")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.danger))
                        }
                    }
                }

                Spacer()

                if task.status != .done {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(task.status == .done ? 0.55 : 1.0)
    }

    @ViewBuilder
    private func taskStatusIcon(_ task: GameTask, isRequired: Bool) -> some View {
        if task.status == .done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.success)
        } else if task.status == .inProgress {
            Image(systemName: "circle.dotted")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentGold)
        } else if isRequired {
            Circle()
                .fill(Color.danger)
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .strokeBorder(Color.textTertiary, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Advance Section

    private var advanceSection: some View {
        VStack(spacing: 6) {
            if !canAdvance {
                let count = TaskGenerator.incompleteRequiredCount(in: tasks)
                Label(
                    "Complete \(count) required task\(count == 1 ? "" : "s") to advance",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.danger)
            }

            Button {
                guard canAdvance else { return }
                onAdvance()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 13, weight: .bold))
                    Text(advanceButtonLabel)
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(canAdvance ? Color.backgroundPrimary : Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(canAdvance ? Color.accentGold : Color.backgroundTertiary)
                        .shadow(
                            color: canAdvance ? Color.accentGold.opacity(0.3) : Color.clear,
                            radius: 8, x: 0, y: 2
                        )
                )
            }
            .disabled(!canAdvance)
            .animation(.spring(duration: 0.3), value: canAdvance)
        }
    }

    private var advanceButtonLabel: String {
        let nextPhase = nextPhaseName
        switch career.currentPhase {
        case .regularSeason:
            return "Advance to Week \(career.currentWeek + 1)"
        case .playoffs:
            switch career.currentWeek {
            case 19: return "Advance to Divisional Round"
            case 20: return "Advance to Conference Championships"
            case 21: return "Advance to Super Bowl"
            default: return "Advance to Next Round"
            }
        case .tradeDeadline:
            return "Advance to Week \(career.currentWeek + 1)"
        default:
            return "Advance to \(nextPhase)"
        }
    }

    private var nextPhaseName: String {
        let nextIndex = currentIndex + 1
        guard nextIndex < Self.orderedPhases.count else {
            return Self.phaseName(Self.orderedPhases[0])
        }
        return Self.phaseName(Self.orderedPhases[nextIndex])
    }

    // MARK: - Upcoming Phases

    private var upcomingPhaseTasks: [(phase: SeasonPhase, name: String, date: String, tasks: [GameTask])] {
        var result: [(SeasonPhase, String, String, [GameTask])] = []

        for i in 1...upcomingPhaseCount {
            let nextIndex = currentIndex + i
            guard nextIndex < Self.orderedPhases.count else { break }
            let phase = Self.orderedPhases[nextIndex]
            let previewTasks = TaskGenerator.generateTasks(
                for: phase,
                career: career,
                team: nil,
                rosterCount: 53,
                hasPendingTradeOffers: false,
                hasHeadCoach: true,
                hasOC: true,
                hasDC: true,
                hasExpiringContracts: false,
                opponentName: nil,
                playoffRoundName: nil,
                hasScoutsAssigned: false,
                hasPendingEvents: false,
                ownerSatisfaction: 50
            )
            result.append((phase, Self.phaseName(phase), Self.phaseDate(phase), previewTasks))
        }

        return result
    }

    private func upcomingPhaseSection(_ entry: (phase: SeasonPhase, name: String, date: String, tasks: [GameTask]), isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phase header
            HStack(spacing: 10) {
                // Timeline connector
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.textTertiary.opacity(0.25))
                        .frame(width: 2, height: 8)

                    Circle()
                        .strokeBorder(Color.textTertiary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    if !isLast || remainingFutureCount > 0 {
                        Rectangle()
                            .fill(Color.textTertiary.opacity(0.25))
                            .frame(width: 2, height: 8)
                    } else {
                        Color.clear.frame(width: 2, height: 8)
                    }
                }

                Text(entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)

                Spacer()

                Text(entry.date)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            // Preview task rows (dimmed)
            VStack(spacing: 0) {
                ForEach(entry.tasks) { task in
                    previewTaskRow(task)
                }
            }
            .padding(.leading, 36)
            .padding(.trailing, 14)
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
        .opacity(0.55)
    }

    private func previewTaskRow(_ task: GameTask) -> some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(Color.textTertiary.opacity(0.5), lineWidth: 1)
                .frame(width: 9, height: 9)

            Text(task.title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Remaining Future Phases

    private var remainingFutureCount: Int {
        let shownUpTo = currentIndex + 1 + upcomingPhaseCount
        let total = Self.orderedPhases.count
        return max(0, total - shownUpTo)
    }

    private var remainingPhasesIndicator: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.textTertiary.opacity(0.15))
                    .frame(width: 2, height: 12)
                Circle()
                    .fill(Color.textTertiary.opacity(0.2))
                    .frame(width: 6, height: 6)
            }

            Text("+ \(remainingFutureCount) more phase\(remainingFutureCount == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textTertiary.opacity(0.5))

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: - Static Helpers

    static func phaseName(_ phase: SeasonPhase) -> String {
        switch phase {
        case .superBowl:       return "Super Bowl"
        case .proBowl:         return "Pro Bowl"
        case .coachingChanges: return "Coaching Changes"
        case .combine:         return "NFL Combine"
        case .freeAgency:      return "Free Agency"
        case .draft:           return "NFL Draft"
        case .otas:            return "OTAs"
        case .trainingCamp:    return "Training Camp"
        case .preseason:       return "Preseason"
        case .rosterCuts:      return "Roster Cuts"
        case .regularSeason:   return "Regular Season"
        case .tradeDeadline:   return "Trade Deadline"
        case .playoffs:        return "Playoffs"
        }
    }

    static func phaseDate(_ phase: SeasonPhase) -> String {
        switch phase {
        case .superBowl:       return "Feb"
        case .proBowl:         return "Feb"
        case .coachingChanges: return "Feb"
        case .combine:         return "Feb\u{2013}Mar"
        case .freeAgency:      return "Mar"
        case .draft:           return "Apr"
        case .otas:            return "May"
        case .trainingCamp:    return "Jul\u{2013}Aug"
        case .preseason:       return "Aug"
        case .rosterCuts:      return "Aug"
        case .regularSeason:   return "Sep\u{2013}Jan"
        case .tradeDeadline:   return "Oct"
        case .playoffs:        return "Jan"
        }
    }

    static func phaseIcon(_ phase: SeasonPhase) -> String {
        switch phase {
        case .superBowl:       return "star.fill"
        case .proBowl:         return "star.circle.fill"
        case .coachingChanges: return "person.badge.key.fill"
        case .combine:         return "stopwatch.fill"
        case .freeAgency:      return "signature"
        case .draft:           return "list.clipboard.fill"
        case .otas:            return "figure.run"
        case .trainingCamp:    return "tent.fill"
        case .preseason:       return "football.fill"
        case .rosterCuts:      return "scissors"
        case .regularSeason:   return "sportscourt.fill"
        case .tradeDeadline:   return "arrow.left.arrow.right"
        case .playoffs:        return "trophy.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var previewTasks: [GameTask] = TaskGenerator.generateTasks(
        for: .coachingChanges,
        career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
        team: nil,
        hasHeadCoach: false,
        hasOC: false,
        hasDC: true
    )

    TimelineTasksPanel(
        career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
        tasks: $previewTasks,
        onTaskSelected: { _ in },
        onAdvance: {},
        canAdvance: false
    )
    .frame(width: 340, height: 600)
    .background(Color.backgroundPrimary)
}
