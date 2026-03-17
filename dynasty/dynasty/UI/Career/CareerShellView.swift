import SwiftUI
import SwiftData

/// Outer container that holds the persistent TopNavigationBar,
/// the main NavigationStack content area, and the CalendarSidebarView.
struct CareerShellView: View {

    @Bindable var career: Career
    @Environment(\.modelContext) private var modelContext

    @State private var showCalendar = false
    @State private var team: Team?
    @State private var upcomingGames: [Game] = []
    @State private var allTeamsByID: [UUID: Team] = [:]

    /// Navigation path for bookmark quick-nav.
    @State private var navigationPath = NavigationPath()

    var body: some View {
        VStack(spacing: 0) {
            // Persistent top navigation bar
            TopNavigationBar(
                teamAbbreviation: team?.abbreviation ?? "???",
                teamName: team?.fullName ?? "No Team",
                pendingTaskCount: pendingTaskCount,
                onCalendarTapped: { showCalendar = true },
                onBookmarkTapped: { destination in
                    handleBookmarkNavigation(destination)
                }
            )

            // Main content area
            NavigationStack(path: $navigationPath) {
                CareerDashboardView(career: career)
                    .navigationDestination(for: ShellDestination.self) { dest in
                        destinationView(for: dest)
                    }
            }
        }
        .background(Color.backgroundPrimary)
        .navigationBarBackButtonHidden(true)
        .task { loadShellData() }
        .sheet(isPresented: $showCalendar) {
            CalendarSidebarView(
                career: career,
                team: team,
                upcomingGames: upcomingGames,
                allTeams: allTeamsByID,
                onDismiss: { showCalendar = false }
            )
            .presentationDetents([.large, .medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Navigation Destinations

    enum ShellDestination: Hashable {
        case roster, schedule, standings, draft, scouting, cap
    }

    @ViewBuilder
    private func destinationView(for destination: ShellDestination) -> some View {
        switch destination {
        case .roster:
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                Text("Roster - Coming Soon")
                    .font(.title2)
                    .foregroundStyle(Color.textSecondary)
            }
            .navigationTitle("Roster")
            .toolbarColorScheme(.dark, for: .navigationBar)
        case .schedule:
            ScheduleView(career: career)
        case .standings:
            StandingsView(career: career)
        case .draft:
            DraftView(career: career)
        case .scouting:
            ScoutingHubView(career: career)
        case .cap:
            CapOverviewView(career: career)
        }
    }

    private func handleBookmarkNavigation(_ bookmark: TopNavigationBar.BookmarkDestination) {
        let dest: ShellDestination
        switch bookmark {
        case .roster:    dest = .roster
        case .schedule:  dest = .schedule
        case .standings: dest = .standings
        case .draft:     dest = .draft
        case .scouting:  dest = .scouting
        case .cap:       dest = .cap
        }
        // Reset to root then push the destination
        navigationPath = NavigationPath()
        navigationPath.append(dest)
    }

    // MARK: - Pending Task Count

    private var pendingTaskCount: Int {
        var count = 0

        if career.currentPhase == .regularSeason || career.currentPhase == .preseason {
            count += 1 // depth chart
        }
        if career.currentPhase == .combine || career.currentPhase == .otas {
            count += 1 // scouting
        }
        if career.currentPhase == .freeAgency {
            count += 1
        }
        if career.currentPhase == .draft {
            count += 1
        }
        if career.currentPhase == .regularSeason || career.currentPhase == .tradeDeadline {
            count += 1 // trades
        }
        if !WeekAdvancer.lastEvents.isEmpty {
            count += 1
        }
        if let owner = team?.owner, owner.satisfaction < 40 {
            count += 1
        }

        return count
    }

    // MARK: - Data Loading

    private func loadShellData() {
        guard let teamID = career.teamID else { return }

        let allTeamsDescriptor = FetchDescriptor<Team>()
        let allTeams = (try? modelContext.fetch(allTeamsDescriptor)) ?? []
        allTeamsByID = Dictionary(uniqueKeysWithValues: allTeams.map { ($0.id, $0) })

        team = allTeamsByID[teamID]

        let seasonYear = career.currentSeason
        let gameDescriptor = FetchDescriptor<Game>(predicate: #Predicate {
            $0.seasonYear == seasonYear
        })
        let allGames = (try? modelContext.fetch(gameDescriptor)) ?? []

        upcomingGames = allGames
            .filter { ($0.homeTeamID == teamID || $0.awayTeamID == teamID) && !$0.isPlayed && $0.week >= career.currentWeek }
            .sorted { $0.week < $1.week }
    }
}

#Preview {
    CareerShellView(career: Career(
        playerName: "John Doe",
        role: .gm,
        capMode: .simple
    ))
    .modelContainer(for: Career.self, inMemory: true)
}
