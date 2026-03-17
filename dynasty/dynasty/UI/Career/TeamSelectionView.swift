import SwiftUI
import SwiftData

struct TeamSelectionView: View {

    let playerName: String
    let avatarID: String
    let coachingStyle: CoachingStyle
    let selectedRole: CareerRole
    let selectedCapMode: CapMode

    @Environment(\.modelContext) private var modelContext
    @State private var selectedCareer: Career?
    @State private var isLoading = false
    @State private var selectedConference: Conference = .AFC
    @State private var detailTeam: NFLTeamDefinition?

    /// All 32 NFL teams from static data.
    private let allTeams = NFLTeamData.allTeams

    /// Teams for the currently selected conference, grouped by division.
    private var divisionsForConference: [(division: Division, teams: [NFLTeamDefinition])] {
        let conferenceTeams = allTeams.filter { $0.conference == selectedConference }
        return Division.allCases.map { division in
            let teams = conferenceTeams
                .filter { $0.division == division }
                .sorted { $0.city < $1.city }
            return (division: division, teams: teams)
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Conference tab picker
                conferencePicker
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Team list — adapts to orientation
                GeometryReader { geo in
                    let isLandscape = geo.size.width > geo.size.height

                    ScrollView {
                        if isLandscape {
                            // Landscape: 4-column grid
                            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
                            VStack(spacing: 16) {
                                ForEach(divisionsForConference, id: \.division) { group in
                                    divisionHeader(group.division.rawValue)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    LazyVGrid(columns: columns, spacing: 12) {
                                        ForEach(group.teams, id: \.abbreviation) { team in
                                            Button { detailTeam = team } label: {
                                                TeamGridCard(team: team)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .frame(maxWidth: 1200)
                            .frame(maxWidth: .infinity)
                        } else {
                            // Portrait: compact row list
                            VStack(spacing: 2) {
                                ForEach(divisionsForConference, id: \.division) { group in
                                    divisionHeader(group.division.rawValue)
                                    ForEach(group.teams, id: \.abbreviation) { team in
                                        Button { detailTeam = team } label: {
                                            CompactTeamRow(team: team)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                            .frame(maxWidth: 800)
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
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
        .sheet(item: $detailTeam) { team in
            TeamDetailSheet(team: team) {
                detailTeam = nil
                startCareer(with: team)
            }
        }
        .navigationDestination(item: $selectedCareer) { career in
            IntroSequenceView(career: career)
        }
    }

    // MARK: - Conference Picker

    private var conferencePicker: some View {
        HStack(spacing: 0) {
            ForEach(Conference.allCases, id: \.self) { conference in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedConference = conference
                    }
                } label: {
                    Text(conference.rawValue)
                        .font(.system(size: 16, weight: .bold))
                        .tracking(2)
                        .foregroundStyle(selectedConference == conference ? Color.backgroundPrimary : Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedConference == conference ? Color.accentGold : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .frame(maxWidth: 400)
    }

    // MARK: - Division Header

    private func divisionHeader(_ name: String) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.accentGold.opacity(0.4))
                .frame(height: 1)
            Text(name)
                .font(.system(size: 12, weight: .bold))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(Color.accentGold)
                .layoutPriority(1)
            Rectangle()
                .fill(Color.accentGold.opacity(0.4))
                .frame(height: 1)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }

    // MARK: - Start Career

    private func startCareer(with teamDef: NFLTeamDefinition) {
        isLoading = true

        let career = Career(
            playerName: playerName,
            avatarID: avatarID,
            coachingStyle: coachingStyle,
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

// MARK: - Identifiable conformance for sheet

extension NFLTeamDefinition: Identifiable {
    var id: String { abbreviation }
}

// MARK: - Compact Team Row

private struct CompactTeamRow: View {
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

    var body: some View {
        HStack(spacing: 12) {
            // Team logo placeholder
            TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 36)

            // Team name + city
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(team.city)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(minWidth: 90, alignment: .leading)

            Spacer(minLength: 4)

            // Difficulty stars
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                        .font(.system(size: 9))
                        .foregroundStyle(star <= preview.difficulty ? difficultyColor : Color.textTertiary.opacity(0.3))
                }
            }

            // Situation badge
            Text(preview.situation)
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(situationColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(situationColor.opacity(0.15))
                )
                .frame(minWidth: 75)

            // Cap space
            VStack(spacing: 1) {
                Text("Cap")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                Text("$\(preview.estimatedCapSpace)M")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(preview.estimatedCapSpace > 30 ? Color.success : preview.estimatedCapSpace > 15 ? Color.accentGold : Color.warning)
            }
            .frame(width: 44)

            // Owner patience icon + seasons
            VStack(spacing: 1) {
                Image(systemName: preview.ownerPatienceIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(ownerPatienceColor)
                Text("\(preview.patienceSeasons)yr")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 30)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 0.5)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(team.city) \(team.name), \(preview.situation), difficulty \(preview.difficulty) of 5")
    }
}

// MARK: - Team Grid Card (compact card for 2x2 / 4-column grid)

private struct TeamGridCard: View {
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

    var body: some View {
        VStack(spacing: 8) {
            // Logo + name
            TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 44)

            Text(team.name)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(team.city)
                .font(.system(size: 11))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            // Difficulty stars
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                        .font(.system(size: 8))
                        .foregroundStyle(star <= preview.difficulty ? Color.accentGold : Color.textTertiary)
                }
            }

            // Situation badge
            Text(preview.situation.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(situationColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule().fill(situationColor.opacity(0.15))
                )

            // Cap space
            Text("$\(preview.estimatedCapSpace)M cap")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Team Logo Placeholder

struct TeamLogoPlaceholder: View {
    let abbreviation: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(TeamColors.color(for: abbreviation))
            Text(abbreviation)
                .font(.system(size: size * 0.33, weight: .black))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Team Colors

enum TeamColors {
    static func color(for abbreviation: String) -> Color {
        switch abbreviation {
        // AFC East
        case "BUF": return Color(red: 0.00, green: 0.20, blue: 0.55)  // Bills blue
        case "MIA": return Color(red: 0.00, green: 0.55, blue: 0.55)  // Dolphins teal
        case "NE":  return Color(red: 0.00, green: 0.13, blue: 0.27)  // Patriots navy
        case "NYJ": return Color(red: 0.07, green: 0.31, blue: 0.17)  // Jets green

        // AFC North
        case "BAL": return Color(red: 0.14, green: 0.03, blue: 0.33)  // Ravens purple
        case "CIN": return Color(red: 0.98, green: 0.31, blue: 0.08)  // Bengals orange
        case "CLE": return Color(red: 0.80, green: 0.33, blue: 0.00)  // Browns orange
        case "PIT": return Color(red: 0.10, green: 0.10, blue: 0.10)  // Steelers black

        // AFC South
        case "HOU": return Color(red: 0.01, green: 0.08, blue: 0.25)  // Texans navy
        case "IND": return Color(red: 0.00, green: 0.17, blue: 0.53)  // Colts blue
        case "JAX": return Color(red: 0.00, green: 0.40, blue: 0.47)  // Jaguars teal
        case "TEN": return Color(red: 0.27, green: 0.46, blue: 0.70)  // Titans blue

        // AFC West
        case "DEN": return Color(red: 0.98, green: 0.31, blue: 0.08)  // Broncos orange
        case "KC":  return Color(red: 0.89, green: 0.09, blue: 0.14)  // Chiefs red
        case "LV":  return Color(red: 0.10, green: 0.10, blue: 0.10)  // Raiders black
        case "LAC": return Color(red: 0.00, green: 0.30, blue: 0.57)  // Chargers blue

        // NFC East
        case "DAL": return Color(red: 0.00, green: 0.21, blue: 0.47)  // Cowboys blue
        case "NYG": return Color(red: 0.01, green: 0.14, blue: 0.42)  // Giants blue
        case "PHI": return Color(red: 0.00, green: 0.30, blue: 0.22)  // Eagles green
        case "WAS": return Color(red: 0.39, green: 0.09, blue: 0.14)  // Commanders burgundy

        // NFC North
        case "CHI": return Color(red: 0.05, green: 0.13, blue: 0.24)  // Bears navy
        case "DET": return Color(red: 0.00, green: 0.42, blue: 0.69)  // Lions blue
        case "GB":  return Color(red: 0.12, green: 0.23, blue: 0.15)  // Packers green
        case "MIN": return Color(red: 0.31, green: 0.15, blue: 0.51)  // Vikings purple

        // NFC South
        case "ATL": return Color(red: 0.65, green: 0.07, blue: 0.11)  // Falcons red
        case "CAR": return Color(red: 0.00, green: 0.52, blue: 0.72)  // Panthers blue
        case "NO":  return Color(red: 0.82, green: 0.68, blue: 0.33)  // Saints gold
        case "TB":  return Color(red: 0.82, green: 0.10, blue: 0.11)  // Buccaneers red

        // NFC West
        case "ARI": return Color(red: 0.60, green: 0.09, blue: 0.16)  // Cardinals red
        case "LAR": return Color(red: 0.00, green: 0.21, blue: 0.53)  // Rams blue
        case "SF":  return Color(red: 0.67, green: 0.15, blue: 0.15)  // 49ers red
        case "SEA": return Color(red: 0.00, green: 0.13, blue: 0.26)  // Seahawks navy

        default:    return Color(red: 0.30, green: 0.30, blue: 0.35)
        }
    }
}

// MARK: - Team Detail Sheet

private struct TeamDetailSheet: View {
    let team: NFLTeamDefinition
    let onSelect: () -> Void

    @Environment(\.dismiss) private var dismiss

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

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    // Header: Logo + Name
                    VStack(spacing: 12) {
                        TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 72)

                        Text("\(team.city) \(team.name)")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Color.textPrimary)

                        Text("\(team.conference.rawValue) \(team.division.rawValue)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(.top, 24)

                    // Difficulty + Situation
                    HStack(spacing: 24) {
                        VStack(spacing: 6) {
                            HStack(spacing: 3) {
                                ForEach(1...5, id: \.self) { star in
                                    Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                                        .font(.system(size: 14))
                                        .foregroundStyle(star <= preview.difficulty ? difficultyColor : Color.textTertiary.opacity(0.4))
                                }
                            }
                            Text(preview.difficultyLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(difficultyColor)
                        }

                        Text(preview.situation)
                            .font(.system(size: 14, weight: .bold))
                            .textCase(.uppercase)
                            .foregroundStyle(situationColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(situationColor.opacity(0.15))
                            )
                    }

                    // Owner info
                    VStack(spacing: 8) {
                        sectionLabel("Owner Expectations")

                        HStack(spacing: 16) {
                            HStack(spacing: 6) {
                                Image(systemName: preview.ownerPatienceIcon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(ownerPatienceColor)
                                Text(preview.ownerPatience)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(ownerPatienceColor)
                            }

                            Text("\(preview.patienceSeasons) season\(preview.patienceSeasons == 1 ? "" : "s") tolerance")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .cardBackground()

                    // Market description
                    VStack(spacing: 8) {
                        sectionLabel("Market & Media")

                        Text(preview.marketDescription)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .cardBackground()

                    // Stats row
                    HStack(spacing: 0) {
                        detailStat(
                            icon: "chart.bar.fill",
                            label: "Roster OVR",
                            value: "\(preview.estimatedOVR)",
                            valueColor: Color.forRating(preview.estimatedOVR)
                        )
                        detailStat(
                            icon: "dollarsign.circle.fill",
                            label: "Cap Space",
                            value: "$\(preview.estimatedCapSpace)M",
                            valueColor: preview.estimatedCapSpace > 30 ? .success : preview.estimatedCapSpace > 15 ? .accentGold : .warning
                        )
                        detailStat(
                            icon: "doc.text.fill",
                            label: "Draft Picks",
                            value: "\(preview.estimatedDraftPicks)",
                            valueColor: preview.estimatedDraftPicks >= 9 ? .success : preview.estimatedDraftPicks >= 7 ? .textPrimary : .warning
                        )
                    }
                    .padding(.vertical, 14)
                    .cardBackground()

                    // Coaching budget row
                    VStack(spacing: 8) {
                        sectionLabel("Coaching Budget")

                        HStack(spacing: 8) {
                            Image(systemName: "dollarsign.square.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(preview.coachingBudget >= 18 ? Color.success : preview.coachingBudget >= 13 ? Color.accentGold : Color.warning)
                            Text("$\(preview.coachingBudget)M")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(preview.coachingBudget >= 18 ? Color.success : preview.coachingBudget >= 13 ? Color.accentGold : Color.warning)
                            Text("for coaching & scouting staff")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .cardBackground()

                    // Select button
                    // SELECT button is in safeAreaInset(edge: .bottom)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
                .frame(maxWidth: 600)
                .frame(maxWidth: .infinity)
            }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .safeAreaInset(edge: .bottom) {
            Button(action: onSelect) {
                Text("SELECT THIS TEAM")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentGold)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .background(Color.backgroundPrimary)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .textCase(.uppercase)
            .foregroundStyle(Color.accentGold)
    }

    private func detailStat(icon: String, label: String, value: String, valueColor: Color) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiary)
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TeamSelectionView(
            playerName: "John Doe",
            avatarID: "coach_m1",
            coachingStyle: .tactician,
            selectedRole: .gm,
            selectedCapMode: .simple
        )
    }
    .modelContainer(for: Career.self, inMemory: true)
}
