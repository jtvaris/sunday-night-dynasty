import SwiftUI
import SwiftData

struct TeamSelectionView: View {

    let playerName: String
    let avatarID: String
    let selectedRole: CareerRole
    let selectedCapMode: CapMode

    @Environment(\.modelContext) private var modelContext
    @State private var selectedCareer: Career?
    @State private var isLoading = false

    /// All 32 NFL teams from static data.
    private let allTeams = NFLTeamData.allTeams

    /// Teams grouped by conference then division for sectioned display.
    private var teamsByConference: [(conference: Conference, divisions: [(division: Division, teams: [NFLTeamDefinition])])] {
        Conference.allCases.map { conference in
            let conferenceTeams = allTeams.filter { $0.conference == conference }
            let divisions = Division.allCases.map { division in
                let divisionTeams = conferenceTeams
                    .filter { $0.division == division }
                    .sorted { $0.city < $1.city }
                return (division: division, teams: divisionTeams)
            }
            return (conference: conference, divisions: divisions)
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                ForEach(teamsByConference, id: \.conference) { group in
                    ForEach(group.divisions, id: \.division) { divisionGroup in
                        Section {
                            ForEach(divisionGroup.teams, id: \.abbreviation) { team in
                                Button {
                                    startCareer(with: team)
                                } label: {
                                    TeamRowView(team: team)
                                }
                                .listRowBackground(Color.backgroundSecondary)
                            }
                        } header: {
                            Text("\(group.conference.rawValue) \(divisionGroup.division.rawValue)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.accentGold)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .disabled(isLoading)

            if isLoading {
                ZStack {
                    Color.backgroundPrimary.opacity(0.85).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(Color.accentGold)
                        Text("Generating League...")
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
        }
        .navigationTitle("Choose Your Team")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(item: $selectedCareer) { career in
            CareerDashboardView(career: career)
        }
    }

    // MARK: - Start Career

    private func startCareer(with teamDef: NFLTeamDefinition) {
        isLoading = true

        let career = Career(
            playerName: playerName,
            avatarID: avatarID,
            role: selectedRole,
            capMode: selectedCapMode
        )

        let result = LeagueGenerator.generate(startYear: career.currentSeason)

        // Find the team matching the selected definition.
        let chosenTeam = result.teams.first { $0.abbreviation == teamDef.abbreviation }

        career.leagueID = result.league.id
        career.teamID = chosenTeam?.id

        // Insert all generated objects into the model context.
        modelContext.insert(career)
        modelContext.insert(result.league)

        for team in result.teams {
            modelContext.insert(team)
        }
        for player in result.players {
            modelContext.insert(player)
        }
        for owner in result.owners {
            modelContext.insert(owner)
        }
        for coach in result.coaches {
            modelContext.insert(coach)
        }

        isLoading = false
        selectedCareer = career
    }
}

// MARK: - Team Row

private struct TeamRowView: View {
    let team: NFLTeamDefinition

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(team.city) \(team.name)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                Text(team.abbreviation)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            MarketBadge(market: team.mediaMarket)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(team.city) \(team.name), \(team.mediaMarket.rawValue) market")
    }
}

// MARK: - Market Badge

private struct MarketBadge: View {
    let market: MediaMarket

    private var color: Color {
        switch market {
        case .large:  return .accentGold
        case .medium: return .accentBlue
        case .small:  return .textTertiary
        }
    }

    var body: some View {
        Text(market.rawValue)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
            .accessibilityLabel("\(market.rawValue) market")
    }
}

#Preview {
    NavigationStack {
        TeamSelectionView(
            playerName: "John Doe",
            avatarID: "coach_m1",
            selectedRole: .gm,
            selectedCapMode: .simple
        )
    }
    .modelContainer(for: Career.self, inMemory: true)
}
