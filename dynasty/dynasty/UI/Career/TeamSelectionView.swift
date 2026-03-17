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

            ScrollView {
                LazyVStack(spacing: 24) {
                    ForEach(teamsByConference, id: \.conference) { group in
                        // Conference header
                        Text(group.conference.rawValue)
                            .font(.system(size: 28, weight: .black))
                            .tracking(4)
                            .foregroundStyle(Color.accentGold)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                        ForEach(group.divisions, id: \.division) { divisionGroup in
                            VStack(alignment: .leading, spacing: 12) {
                                // Division header
                                HStack(spacing: 8) {
                                    Image(systemName: "football.fill")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentGold)
                                    Text(divisionGroup.division.rawValue)
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Color.accentGold)
                                }
                                .padding(.horizontal, 20)

                                ForEach(divisionGroup.teams, id: \.abbreviation) { team in
                                    Button {
                                        startCareer(with: team)
                                    } label: {
                                        TeamCardView(team: team)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 16)
                .frame(maxWidth: 800)
                .frame(maxWidth: .infinity)
            }
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
            IntroSequenceView(career: career)
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

        // Bug fix #2: Player's team starts with NO coaches — the wizard guides
        // them to hire staff first. Remove all coaches from the chosen team only.
        if let chosenTeamID = chosenTeam?.id {
            for coach in result.coaches where coach.teamID == chosenTeamID {
                coach.teamID = nil
            }
        }

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
        for pick in result.draftPicks {
            modelContext.insert(pick)
        }

        isLoading = false
        selectedCareer = career
    }
}

// MARK: - Team Card View

private struct TeamCardView: View {
    let team: NFLTeamDefinition

    private var preview: TeamPreview { team.preview }

    private var situationColor: Color {
        switch preview.situation {
        case "Rebuilding": return .accentBlue
        case "Rising":     return .success
        case "Contender":  return .accentGold
        case "Win Now":    return .warning
        case "Dynasty":    return .danger
        default:           return .textSecondary
        }
    }

    private var difficultyColor: Color {
        switch preview.difficulty {
        case 1, 2: return .success
        case 3:    return .accentGold
        case 4:    return .warning
        case 5:    return .danger
        default:   return .textSecondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            HStack(alignment: .top, spacing: 16) {
                // Left: Team identity
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(team.city) \(team.name)")
                        .font(.headline)
                        .foregroundStyle(Color.textPrimary)

                    Text("\(team.conference.rawValue) \(team.division.rawValue)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 8)

                // Center: Difficulty & Situation
                VStack(spacing: 6) {
                    // Difficulty stars
                    HStack(spacing: 2) {
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundStyle(star <= preview.difficulty ? difficultyColor : Color.textTertiary.opacity(0.4))
                        }
                    }

                    Text(preview.difficultyLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(difficultyColor)

                    // Situation badge
                    Text(preview.situation)
                        .font(.caption2.weight(.bold))
                        .textCase(.uppercase)
                        .foregroundStyle(situationColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(situationColor.opacity(0.15))
                        )
                }

                Spacer(minLength: 8)

                // Right: Owner expectations
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: preview.ownerPatienceIcon)
                            .font(.system(size: 11))
                            .foregroundStyle(ownerPatienceColor)
                        Text(preview.ownerPatience)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ownerPatienceColor)
                    }

                    Text("\(preview.patienceSeasons) season\(preview.patienceSeasons == 1 ? "" : "s") tolerance")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(16)

            // Market description
            Text(preview.marketDescription)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            // Divider
            Rectangle()
                .fill(Color.surfaceBorder)
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Bottom stats row
            HStack(spacing: 0) {
                StatPill(icon: "chart.bar.fill", label: "Roster OVR", value: "\(preview.estimatedOVR)", valueColor: Color.forRating(preview.estimatedOVR))
                StatPill(icon: "dollarsign.circle.fill", label: "Cap Space", value: "$\(preview.estimatedCapSpace)M", valueColor: preview.estimatedCapSpace > 30 ? .success : preview.estimatedCapSpace > 15 ? .accentGold : .warning)
                StatPill(icon: "doc.text.fill", label: "Draft Picks", value: "\(preview.estimatedDraftPicks)", valueColor: preview.estimatedDraftPicks >= 9 ? .success : preview.estimatedDraftPicks >= 7 ? .textPrimary : .warning)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .cardBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(team.city) \(team.name), \(preview.situation), difficulty \(preview.difficulty) of 5, \(preview.ownerPatience) owner")
    }

    private var ownerPatienceColor: Color {
        switch preview.ownerPatience {
        case "Very Patient": return .success
        case "Patient":      return .success.opacity(0.8)
        case "Moderate":     return .accentGold
        case "Demanding":    return .warning
        case "Win Now":      return .danger
        default:             return .textSecondary
        }
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let icon: String
    let label: String
    let value: String
    var valueColor: Color = .textPrimary

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
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
