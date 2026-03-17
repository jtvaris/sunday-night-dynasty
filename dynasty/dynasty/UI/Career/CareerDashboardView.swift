import SwiftUI
import SwiftData

struct CareerDashboardView: View {

    @Bindable var career: Career
    @Environment(\.modelContext) private var modelContext

    /// The team associated with this career, fetched on appear.
    @State private var team: Team?

    /// Players on the roster for this team.
    @State private var rosterCount: Int = 0

    /// Coaches on staff for this team.
    @State private var coachCount: Int = 0

    /// Show game summary after advancing a week
    @State private var showGameSummary = false
    @State private var lastGameResult: GameSimulator.GameResult?
    @State private var lastHomeTeam: Team?
    @State private var lastAwayTeam: Team?

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // MARK: - Header Card
                    headerCard

                    // MARK: - Season Info
                    seasonInfoCard

                    // MARK: - Team Record
                    recordCard

                    // MARK: - Navigation
                    navigationCard

                    // MARK: - Advance Week
                    advanceWeekButton
                }
                .padding(24)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadTeamData()
        }
        .sheet(isPresented: $showGameSummary) {
            if let result = lastGameResult, let home = lastHomeTeam, let away = lastAwayTeam {
                NavigationStack {
                    GameSummaryView(
                        boxScore: result.boxScore,
                        homeTeam: home,
                        awayTeam: away,
                        playerStats: result.playerStats
                    )
                }
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        VStack(spacing: 8) {
            Text(team?.fullName ?? "No Team")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color.accentGold)

            HStack(spacing: 12) {
                Label(
                    career.role == .gm ? "General Manager" : "GM & Head Coach",
                    systemImage: career.role == .gm ? "briefcase.fill" : "sportscourt.fill"
                )

                Text("|")
                    .foregroundStyle(Color.textTertiary)

                Text(career.playerName)
            }
            .font(.subheadline)
            .foregroundStyle(Color.textSecondary)

            if let team {
                Text("\(team.conference.rawValue) \(team.division.rawValue)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.accentGold)
                    .padding(.top, 2)
            }

            if let owner = team?.owner {
                HStack(spacing: 6) {
                    Image(systemName: "building.2.fill")
                        .font(.caption2)
                    Text("Owner: \(owner.satisfaction)% satisfied")
                        .font(.caption)
                }
                .foregroundStyle(ownerSatisfactionIndicatorColor(owner.satisfaction))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(ownerSatisfactionIndicatorColor(owner.satisfaction).opacity(0.15))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardBackground()
    }

    private func ownerSatisfactionIndicatorColor(_ value: Int) -> Color {
        if value > 60  { return Color.success }
        if value >= 35 { return Color.warning }
        return Color.danger
    }

    // MARK: - Season Info Card

    private var seasonInfoCard: some View {
        VStack(spacing: 12) {
            Text("Season Overview")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                StatColumn(label: "Season", value: "\(career.currentSeason)")
                StatColumn(label: "Week", value: "\(career.currentWeek)")
                StatColumn(label: "Phase", value: phaseDisplayName(career.currentPhase))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
    }

    // MARK: - Record Card

    private var recordCard: some View {
        VStack(spacing: 12) {
            Text("Team Record")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 0) {
                StatColumn(label: "Record", value: team?.record ?? "0-0")
                StatColumn(label: "Roster", value: "\(rosterCount)")
                StatColumn(label: "Cap Mode", value: career.capMode == .simple ? "Simple" : "Realistic")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
    }

    // MARK: - Navigation Card

    private var navigationCard: some View {
        VStack(spacing: 12) {
            Text("Front Office")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)

            Divider().overlay(Color.surfaceBorder)

            NavigationLink {
                // Placeholder roster view
                ZStack {
                    Color.backgroundPrimary.ignoresSafeArea()
                    Text("Roster - Coming Soon")
                        .font(.title2)
                        .foregroundStyle(Color.textSecondary)
                }
                .navigationTitle("Roster")
                .toolbarColorScheme(.dark, for: .navigationBar)
            } label: {
                dashboardNavRow(
                    icon: "person.3.fill",
                    label: "Roster",
                    detail: "\(rosterCount) players"
                )
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            NavigationLink {
                ScheduleView(career: career)
            } label: {
                dashboardNavRow(
                    icon: "calendar",
                    label: "Schedule",
                    detail: "Week \(career.currentWeek)"
                )
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            NavigationLink {
                StandingsView(career: career)
            } label: {
                dashboardNavRow(
                    icon: "list.number",
                    label: "Standings",
                    detail: career.currentSeason.description
                )
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            NavigationLink {
                CoachingStaffView(career: career)
            } label: {
                dashboardNavRow(
                    icon: "person.2.fill",
                    label: "Coaching Staff",
                    detail: "\(coachCount) coaches"
                )
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            NavigationLink {
                CapOverviewView(career: career)
            } label: {
                dashboardNavRow(
                    icon: "dollarsign.circle.fill",
                    label: "Salary Cap",
                    detail: team.map { formatCapDetail($0.availableCap) } ?? "—"
                )
            }

            if career.currentPhase == .freeAgency {
                Divider().overlay(Color.surfaceBorder.opacity(0.5))

                NavigationLink {
                    FreeAgencyView(career: career)
                } label: {
                    dashboardNavRow(
                        icon: "person.badge.plus",
                        label: "Free Agency",
                        detail: "Active"
                    )
                }
            }

            if career.currentPhase == .draft {
                Divider().overlay(Color.surfaceBorder.opacity(0.5))

                NavigationLink {
                    DraftView(career: career)
                } label: {
                    dashboardNavRow(
                        icon: "list.clipboard.fill",
                        label: "NFL Draft",
                        detail: "Active"
                    )
                }
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            NavigationLink {
                ScoutingHubView(career: career)
            } label: {
                dashboardNavRow(
                    icon: "magnifyingglass",
                    label: "Scouting",
                    detail: phaseDisplayName(career.currentPhase)
                )
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            NavigationLink {
                NewsView(career: career)
            } label: {
                dashboardNavRow(
                    icon: "newspaper.fill",
                    label: "News",
                    detail: "Headlines"
                )
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.5))

            NavigationLink {
                OwnerMeetingView(career: career)
            } label: {
                dashboardNavRow(
                    icon: "building.2.fill",
                    label: "Owner",
                    detail: ownerSatisfactionDetail
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
    }

    /// Satisfaction percentage pulled from the team's owner, or a dash if unavailable.
    private var ownerSatisfactionDetail: String {
        guard let owner = team?.owner else { return "—" }
        return "\(owner.satisfaction)% satisfied"
    }

    private func formatCapDetail(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1000.0
        if abs(millions) >= 1.0 {
            return String(format: "$%.1fM avail", millions)
        } else {
            return "$\(thousands)K avail"
        }
    }

    // MARK: - Advance Week Button

    private var advanceWeekButton: some View {
        Button {
            let teamsByID = fetchTeamsByID()
            WeekAdvancer.advanceWeek(career: career, modelContext: modelContext)
            // Check if there was a play-by-play game result
            if let result = WeekAdvancer.lastPlayerGameResult,
               let home = teamsByID[result.boxScore.home.teamID],
               let away = teamsByID[result.boxScore.away.teamID] {
                lastGameResult = result
                lastHomeTeam = home
                lastAwayTeam = away
                showGameSummary = true
            }
            loadTeamData()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 16, weight: .bold))
                Text("Advance to Week \(career.currentWeek + 1)")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.accentGold)
                    .shadow(color: Color.accentGold.opacity(0.4), radius: 12, x: 0, y: 4)
            )
        }
        .accessibilityLabel("Advance to Week \(career.currentWeek + 1)")
    }

    // MARK: - Nav Row Helper

    private func dashboardNavRow(icon: String, label: String, detail: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Color.accentGold)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(detail)
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .foregroundStyle(Color.textTertiary)
                .font(.system(size: 13))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundTertiary)
        )
    }

    // MARK: - Helpers

    private func phaseDisplayName(_ phase: SeasonPhase) -> String {
        switch phase {
        case .superBowl:       return "Super Bowl"
        case .proBowl:         return "Pro Bowl"
        case .coachingChanges: return "Coaching"
        case .combine:         return "Combine"
        case .freeAgency:      return "Free Agency"
        case .draft:           return "Draft"
        case .otas:            return "OTAs"
        case .trainingCamp:    return "Camp"
        case .preseason:       return "Preseason"
        case .rosterCuts:      return "Roster Cuts"
        case .regularSeason:   return "Regular Season"
        case .tradeDeadline:   return "Trade Deadline"
        case .playoffs:        return "Playoffs"
        }
    }

    private func fetchTeamsByID() -> [UUID: Team] {
        let descriptor = FetchDescriptor<Team>()
        let teams = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
    }

    private func loadTeamData() {
        guard let teamID = career.teamID else { return }

        let descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(descriptor).first

        guard let fetchedTeamID = team?.id else { return }
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == fetchedTeamID })
        rosterCount = (try? modelContext.fetchCount(playerDescriptor)) ?? 0

        let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == fetchedTeamID })
        coachCount = (try? modelContext.fetchCount(coachDescriptor)) ?? 0
    }
}

// MARK: - Stat Column

private struct StatColumn: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

#Preview {
    NavigationStack {
        CareerDashboardView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: Career.self, inMemory: true)
}
