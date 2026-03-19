import SwiftUI
import SwiftData

struct TeamSelectionView: View {

    let playerName: String
    let avatarID: String
    let coachingStyle: CoachingStyle
    let selectedRole: CareerRole
    let selectedCapMode: CapMode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selectedCareer: Career?
    @State private var isLoading = false
    @State private var selectedConference: Conference = .AFC
    @State private var detailTeam: NFLTeamDefinition?
    @State private var situationFilter: String = "All"
    @State private var sortMode: TeamSortMode = .division

    private var isLandscape: Bool { verticalSizeClass == .compact }

    /// All 32 NFL teams from static data.
    private let allTeams = NFLTeamData.allTeams

    /// Available situation filters.
    private let situationOptions = ["All", "Rebuilding", "Rising", "Contender", "Win Now", "Dynasty"]

    /// Teams for the currently selected conference, filtered and grouped/sorted.
    private var divisionsForConference: [(division: Division, teams: [NFLTeamDefinition])] {
        let conferenceTeams = allTeams.filter { $0.conference == selectedConference }
        let filtered = situationFilter == "All"
            ? conferenceTeams
            : conferenceTeams.filter { $0.preview.situation == situationFilter }
        return Division.allCases.compactMap { division in
            let teams: [NFLTeamDefinition]
            let divTeams = filtered.filter { $0.division == division }
            switch sortMode {
            case .division:
                teams = divTeams.sorted { $0.city < $1.city }
            case .capSpace:
                teams = divTeams.sorted { $0.preview.estimatedCapSpace > $1.preview.estimatedCapSpace }
            case .difficulty:
                teams = divTeams.sorted { $0.preview.difficulty < $1.preview.difficulty }
            case .overall:
                teams = divTeams.sorted { $0.preview.estimatedOVR > $1.preview.estimatedOVR }
            }
            guard !teams.isEmpty else { return nil }
            return (division: division, teams: teams)
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            GeometryReader { geo in
                Image("BgStadiumNight")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.15)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Conference tab picker
                conferencePicker
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                // Filter/sort bar (#115)
                filterSortBar
                    .padding(.bottom, 8)

                // Compact table rows — all 16 teams with minimal scrolling
                ScrollView {
                    if isLandscape {
                        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(divisionsForConference, id: \.division) { group in
                                Section {
                                    ForEach(group.teams, id: \.abbreviation) { team in
                                        Button { detailTeam = team } label: {
                                            CompactTeamRow(team: team)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                } header: {
                                    divisionHeader(group.division.rawValue)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .frame(maxWidth: 1200)
                        .frame(maxWidth: .infinity)
                    } else {
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
                        .frame(maxWidth: 900)
                        .frame(maxWidth: .infinity)
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
        .fullScreenCover(item: $detailTeam) { team in
            NavigationStack {
                TeamDetailSheet(team: team) {
                    detailTeam = nil
                    startCareer(with: team)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { detailTeam = nil }
                            .foregroundStyle(Color.accentGold)
                    }
                }
                .toolbarColorScheme(.dark, for: .navigationBar)
            }
        }
        .navigationDestination(item: $selectedCareer) { career in
            IntroSequenceView(career: career)
        }
    }

    // MARK: - Filter/Sort Bar (#115)

    private var filterSortBar: some View {
        HStack(spacing: 12) {
            // Situation filter
            Menu {
                ForEach(situationOptions, id: \.self) { option in
                    Button {
                        situationFilter = option
                    } label: {
                        HStack {
                            Text(option)
                            if situationFilter == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .semibold))
                    Text(situationFilter == "All" ? "Filter" : situationFilter)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(situationFilter == "All" ? Color.textSecondary : Color.accentGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(situationFilter == "All" ? Color.backgroundSecondary : Color.accentGold.opacity(0.15))
                        .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 0.5))
                )
            }

            // Sort mode
            Menu {
                ForEach(TeamSortMode.allCases, id: \.self) { mode in
                    Button {
                        sortMode = mode
                    } label: {
                        HStack {
                            Text(mode.label)
                            if sortMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 11, weight: .semibold))
                    Text(sortMode.label)
                        .font(.system(size: 12, weight: .semibold))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(sortMode == .division ? Color.textSecondary : Color.accentGold)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(sortMode == .division ? Color.backgroundSecondary : Color.accentGold.opacity(0.15))
                        .overlay(Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 0.5))
                )
            }

            Spacer()
        }
        .padding(.horizontal, 16)
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
                        .contentShape(Rectangle())
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
        HStack(spacing: 10) {
            // Team logo placeholder (with lock overlay if locked)
            ZStack(alignment: .bottomTrailing) {
                TeamLogoPlaceholder(abbreviation: team.abbreviation, size: 36)

                if preview.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.backgroundPrimary)
                        .padding(3)
                        .background(Circle().fill(Color.textTertiary))
                        .offset(x: 4, y: 4)
                }
            }

            // Team name + city + record + QB (#113)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(team.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text(preview.lastSeasonRecord)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
                HStack(spacing: 6) {
                    Text(team.city)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                    Text("\u{2022}")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.textTertiary)
                    Text(preview.startingQBName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                    Text("\(preview.startingQBOverall)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(preview.startingQBOverall))
                }
            }
            .frame(minWidth: 130, alignment: .leading)

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

            // Cap + Budget combined column (#112, #114)
            VStack(spacing: 2) {
                HStack(spacing: 3) {
                    Text("CAP")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                    Text("$\(preview.estimatedCapSpace)M")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                        .foregroundStyle(preview.estimatedCapSpace > 30 ? Color.success : preview.estimatedCapSpace > 15 ? Color.accentGold : Color.warning)
                }
                HStack(spacing: 3) {
                    Text("STF")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                    Text("$\(preview.coachingBudget)M")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(preview.coachingBudget >= 18 ? Color.success : preview.coachingBudget >= 13 ? Color.accentGold : Color.warning)
                }
            }
            .frame(width: 64)

            // Owner patience icon + seasons (#112 widened)
            VStack(spacing: 1) {
                Image(systemName: preview.ownerPatienceIcon)
                    .font(.system(size: 12))
                    .foregroundStyle(ownerPatienceColor)
                Text("\(preview.patienceSeasons)yr")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: 42)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 16)
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
        .accessibilityLabel("\(team.city) \(team.name), \(preview.lastSeasonRecord), \(preview.situation), difficulty \(preview.difficulty) of 5, QB \(preview.startingQBName) \(preview.startingQBOverall) OVR\(preview.isLocked ? ", locked" : "")")
    }
}

// MARK: - Mini Team Card (fits 16 teams on screen)

private struct MiniTeamCard: View {
    let team: NFLTeamDefinition
    var height: CGFloat = 140
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
        VStack(spacing: 3) {
            // Logo
            TeamLogoPlaceholder(abbreviation: team.abbreviation, size: min(36, height * 0.28))

            // Name
            Text(team.name)
                .font(.system(size: min(13, height * 0.1), weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            // City
            Text(team.city)
                .font(.system(size: min(10, height * 0.07)))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            // Stars
            HStack(spacing: 1) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= preview.difficulty ? "star.fill" : "star")
                        .font(.system(size: min(7, height * 0.05)))
                        .foregroundStyle(star <= preview.difficulty ? Color.accentGold : Color.textTertiary)
                }
            }

            // Situation
            Text(preview.situation.uppercased())
                .font(.system(size: min(8, height * 0.06), weight: .bold))
                .foregroundStyle(situationColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.surfaceBorder, lineWidth: 0.5)
                )
        )
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
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isLandscape: Bool { verticalSizeClass == .compact }

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

            GeometryReader { geo in
                Image("BgLockerRoom2")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.15)
            }
            .ignoresSafeArea()

            GeometryReader { geometry in
                ScrollView {
                    if isLandscape {
                        landscapeDetailContent
                            .frame(minHeight: geometry.size.height)
                    } else {
                        portraitDetailContent
                            .frame(minHeight: geometry.size.height)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onSelect) {
                Text("SELECT THIS TEAM")
                    .font(.system(size: 16, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: 500)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentGold)
                    )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
            .background(Color.backgroundPrimary.opacity(0.95))
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

    // MARK: - Detail Header

    private var detailHeader: some View {
        VStack(spacing: 12) {
            TeamLogoPlaceholder(abbreviation: team.abbreviation, size: isLandscape ? 56 : 72)

            Text("\(team.city) \(team.name)")
                .font(.system(size: isLandscape ? 22 : 28, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            Text("\(team.conference.rawValue) \(team.division.rawValue)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textSecondary)

            Text("Last Season: \(preview.lastSeasonRecord)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.top, isLandscape ? 12 : 24)
    }

    // MARK: - Difficulty + Situation

    private var difficultySituationRow: some View {
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
    }

    // MARK: - Info Cards

    private var ownerExpectationsCard: some View {
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
    }

    private var marketMediaCard: some View {
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
    }

    private var statsRow: some View {
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
    }

    // MARK: - Starting QB Card

    private var startingQBCard: some View {
        VStack(spacing: 8) {
            sectionLabel("Starting Quarterback")

            HStack(spacing: 12) {
                Image(systemName: "figure.american.football")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.accentGold)

                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.startingQBName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("QB")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text("\(preview.startingQBOverall)")
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(Color.forRating(preview.startingQBOverall))
                    Text("OVR")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    // MARK: - Division Rivals Card

    private var divisionRivals: [NFLTeamDefinition] {
        NFLTeamData.allTeams.filter {
            $0.conference == team.conference
            && $0.division == team.division
            && $0.abbreviation != team.abbreviation
        }
    }

    private var divisionRivalsCard: some View {
        VStack(spacing: 8) {
            sectionLabel("Division Rivals")

            VStack(spacing: 6) {
                ForEach(divisionRivals, id: \.abbreviation) { rival in
                    let rivalPreview = rival.preview
                    HStack(spacing: 10) {
                        TeamLogoPlaceholder(abbreviation: rival.abbreviation, size: 28)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(rival.city) \(rival.name)")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.textPrimary)
                            Text(rivalPreview.lastSeasonRecord)
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }

                        Spacer()

                        Text(rivalPreview.situation.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.surfaceBorder)
                            )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardBackground()
    }

    private var coachingBudgetCard: some View {
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
    }

    // MARK: - Locked Team Banner

    @ViewBuilder
    private var lockedBanner: some View {
        if preview.isLocked {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.warning)
                Text("Complete one full season to unlock this team")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.warning.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.warning.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Portrait Layout

    private var portraitDetailContent: some View {
        VStack(spacing: 24) {
            detailHeader
            lockedBanner
            difficultySituationRow
            startingQBCard
            ownerExpectationsCard
            marketMediaCard
            statsRow
            coachingBudgetCard
            divisionRivalsCard
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: 600)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Landscape Layout

    private var landscapeDetailContent: some View {
        VStack(spacing: 16) {
            detailHeader
            lockedBanner
            difficultySituationRow

            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, spacing: 12) {
                startingQBCard
                ownerExpectationsCard
                marketMediaCard
                coachingBudgetCard
                statsRow
                divisionRivalsCard
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: 900)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Team Sort Mode (#115)

private enum TeamSortMode: String, CaseIterable {
    case division, capSpace, difficulty, overall

    var label: String {
        switch self {
        case .division:  return "Division"
        case .capSpace:  return "Cap Space"
        case .difficulty: return "Difficulty"
        case .overall:   return "Overall"
        }
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
