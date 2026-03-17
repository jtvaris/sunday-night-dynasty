import SwiftUI
import SwiftData

/// Slide-in sidebar showing the current date context, pending tasks,
/// upcoming schedule, and key season dates.
struct CalendarSidebarView: View {

    let career: Career
    let team: Team?
    let upcomingGames: [Game]
    let allTeams: [UUID: Team]
    let onDismiss: () -> Void

    // MARK: - Task Model

    struct PendingTask: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let destination: TaskDestination
    }

    enum TaskDestination {
        case roster, scouting, freeAgency, draft, trade, news, owner
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        currentDateSection
                        pendingTasksSection
                        upcomingScheduleSection
                        keyDatesSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Calendar & Tasks")
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

    // MARK: - Current Date Section

    private var currentDateSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundStyle(Color.accentGold)
                Text("Current Date")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }

            VStack(spacing: 6) {
                infoRow(label: "Season", value: "\(career.currentSeason)")
                infoRow(label: "Week", value: "\(career.currentWeek)")
                infoRow(label: "Phase", value: phaseDisplayName(career.currentPhase))
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Pending Tasks

    private var pendingTasks: [PendingTask] {
        var tasks: [PendingTask] = []

        // Always suggest depth chart during regular season / preseason
        if career.currentPhase == .regularSeason || career.currentPhase == .preseason {
            tasks.append(PendingTask(icon: "list.bullet.rectangle", title: "Set depth chart", destination: .roster))
        }

        // Scouting during combine / college phases
        if career.currentPhase == .combine || career.currentPhase == .otas {
            tasks.append(PendingTask(icon: "magnifyingglass", title: "Review scouting reports", destination: .scouting))
        }

        // Free agency
        if career.currentPhase == .freeAgency {
            tasks.append(PendingTask(icon: "person.badge.plus", title: "Sign free agents", destination: .freeAgency))
        }

        // Draft
        if career.currentPhase == .draft {
            tasks.append(PendingTask(icon: "list.clipboard.fill", title: "Prepare for draft", destination: .draft))
        }

        // Trade window open
        if career.currentPhase == .regularSeason || career.currentPhase == .tradeDeadline {
            tasks.append(PendingTask(icon: "arrow.left.arrow.right", title: "Review trade offers", destination: .trade))
        }

        // Events pending
        if !WeekAdvancer.lastEvents.isEmpty {
            let headline = WeekAdvancer.lastEvents.first?.headline ?? "event"
            tasks.append(PendingTask(icon: "exclamationmark.bubble.fill", title: "Handle event: \(headline)", destination: .news))
        }

        // Owner satisfaction low
        if let owner = team?.owner, owner.satisfaction < 40 {
            tasks.append(PendingTask(icon: "building.2.fill", title: "Owner meeting requested", destination: .owner))
        }

        return tasks
    }

    private var pendingTasksSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundStyle(Color.accentGold)
                Text("Pending Tasks")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
                if !pendingTasks.isEmpty {
                    Text("\(pendingTasks.count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.danger))
                }
            }

            if pendingTasks.isEmpty {
                Text("All caught up!")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(pendingTasks) { task in
                    HStack(spacing: 12) {
                        Image(systemName: task.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(Color.accentGold)
                            .frame(width: 24)
                        Text(task.title)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.backgroundTertiary)
                    )
                }
            }
        }
        .padding(16)
        .cardBackground()
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

    // MARK: - Key Dates

    private var keyDatesSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "flag.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Key Dates")
                    .font(.headline)
                    .foregroundStyle(Color.accentGold)
                Spacer()
            }

            VStack(spacing: 6) {
                keyDateRow(event: "Trade Deadline", phase: .tradeDeadline)
                keyDateRow(event: "Playoffs", phase: .playoffs)
                keyDateRow(event: "Super Bowl", phase: .superBowl)
                keyDateRow(event: "Free Agency", phase: .freeAgency)
                keyDateRow(event: "NFL Draft", phase: .draft)
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Helpers

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
        }
    }

    private func keyDateRow(event: String, phase: SeasonPhase) -> some View {
        HStack {
            let isCurrent = career.currentPhase == phase
            let isPast = Self.phaseOrder(phase) < Self.phaseOrder(career.currentPhase)

            Circle()
                .fill(isCurrent ? Color.accentGold : isPast ? Color.textTertiary : Color.backgroundTertiary)
                .frame(width: 8, height: 8)

            Text(event)
                .font(.subheadline)
                .foregroundStyle(isCurrent ? Color.accentGold : isPast ? Color.textTertiary : Color.textSecondary)

            Spacer()

            if isCurrent {
                Text("NOW")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(Color.accentGold)
            }
        }
        .padding(.vertical, 2)
    }

    private func phaseDisplayName(_ phase: SeasonPhase) -> String {
        switch phase {
        case .superBowl:       return "Super Bowl"
        case .proBowl:         return "Pro Bowl"
        case .coachingChanges: return "Coaching Changes"
        case .combine:         return "Combine"
        case .freeAgency:      return "Free Agency"
        case .draft:           return "Draft"
        case .otas:            return "OTAs"
        case .trainingCamp:    return "Training Camp"
        case .preseason:       return "Preseason"
        case .rosterCuts:      return "Roster Cuts"
        case .regularSeason:   return "Regular Season"
        case .tradeDeadline:   return "Trade Deadline"
        case .playoffs:        return "Playoffs"
        }
    }

    /// Rough ordering of phases within a season cycle for timeline display.
    static func phaseOrder(_ phase: SeasonPhase) -> Int {
        switch phase {
        case .preseason:       return 0
        case .rosterCuts:      return 1
        case .regularSeason:   return 2
        case .tradeDeadline:   return 3
        case .playoffs:        return 4
        case .superBowl:       return 5
        case .proBowl:         return 6
        case .coachingChanges: return 7
        case .combine:         return 8
        case .freeAgency:      return 9
        case .draft:           return 10
        case .otas:            return 11
        case .trainingCamp:    return 12
        }
    }
}

#Preview {
    CalendarSidebarView(
        career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
        team: nil,
        upcomingGames: [],
        allTeams: [:],
        onDismiss: {}
    )
}
