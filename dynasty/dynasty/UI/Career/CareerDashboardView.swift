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
            Color.black.ignoresSafeArea()

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
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                Label(
                    career.role == .gm ? "General Manager" : "GM & Head Coach",
                    systemImage: career.role == .gm ? "briefcase.fill" : "sportscourt.fill"
                )

                Text("|")
                    .foregroundStyle(.gray.opacity(0.5))

                Text(career.playerName)
            }
            .font(.subheadline)
            .foregroundStyle(.gray)

            if let team {
                Text("\(team.conference.rawValue) \(team.division.rawValue)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(cardBackground)
    }

    // MARK: - Season Info Card

    private var seasonInfoCard: some View {
        VStack(spacing: 12) {
            Text("Season Overview")
                .font(.headline)
                .foregroundStyle(.white)

            Divider().overlay(Color.white.opacity(0.1))

            HStack(spacing: 0) {
                StatColumn(label: "Season", value: "\(career.currentSeason)")
                StatColumn(label: "Week", value: "\(career.currentWeek)")
                StatColumn(label: "Phase", value: phaseDisplayName(career.currentPhase))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Record Card

    private var recordCard: some View {
        VStack(spacing: 12) {
            Text("Team Record")
                .font(.headline)
                .foregroundStyle(.white)

            Divider().overlay(Color.white.opacity(0.1))

            HStack(spacing: 0) {
                StatColumn(label: "Record", value: team?.record ?? "0-0")
                StatColumn(label: "Roster", value: "\(rosterCount)")
                StatColumn(label: "Cap Mode", value: career.capMode == .simple ? "Simple" : "Realistic")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Navigation Card

    private var navigationCard: some View {
        VStack(spacing: 12) {
            Text("Front Office")
                .font(.headline)
                .foregroundStyle(.white)

            Divider().overlay(Color.white.opacity(0.1))

            NavigationLink {
                // Placeholder roster view
                ZStack {
                    Color.black.ignoresSafeArea()
                    Text("Roster - Coming Soon")
                        .font(.title2)
                        .foregroundStyle(.gray)
                }
                .navigationTitle("Roster")
                .toolbarColorScheme(.dark, for: .navigationBar)
            } label: {
                HStack {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.orange)
                    Text("Roster")
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(rosterCount) players")
                        .foregroundStyle(.gray)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(cardBackground)
    }

    // MARK: - Helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

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
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.gray)
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
