import SwiftUI
import SwiftData

struct CareerDashboardView: View {

    @Bindable var career: Career
    @Environment(\.modelContext) private var modelContext

    /// The team associated with this career, fetched on appear.
    @State private var team: Team?

    /// Players on the roster for this team.
    @State private var rosterCount: Int = 0

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
                }
                .padding(24)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadTeamData()
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
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .cardBackground()
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
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(Color.accentGold)
                    Text("Roster")
                        .foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("\(rosterCount) players")
                        .foregroundStyle(Color.textSecondary)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundTertiary)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .cardBackground()
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

    private func loadTeamData() {
        guard let teamID = career.teamID else { return }

        let descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(descriptor).first

        guard let fetchedTeamID = team?.id else { return }
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == fetchedTeamID })
        rosterCount = (try? modelContext.fetchCount(playerDescriptor)) ?? 0
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
