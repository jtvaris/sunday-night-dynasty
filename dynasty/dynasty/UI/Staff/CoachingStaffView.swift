import SwiftUI
import SwiftData

struct CoachingStaffView: View {

    let career: Career
    @Environment(\.modelContext) private var modelContext
    @Query private var allCoaches: [Coach]

    /// Coaches filtered to this team, derived from @Query result.
    private var coaches: [Coach] {
        guard let teamID = career.teamID else { return [] }
        return allCoaches.filter { $0.teamID == teamID }
    }

    // MARK: - Grouped coaches

    private var headCoach: Coach? {
        coaches.first { $0.role == .headCoach }
    }

    private var coordinators: [Coach] {
        coaches.filter { [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator].contains($0.role) }
            .sorted { $0.role.sortOrder < $1.role.sortOrder }
    }

    private var positionCoaches: [Coach] {
        coaches.filter { [.qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach].contains($0.role) }
            .sorted { $0.role.sortOrder < $1.role.sortOrder }
    }

    // MARK: - Vacant roles

    private var vacantRoles: [CoachRole] {
        let filledRoles = Set(coaches.map { $0.role })
        return CoachRole.allCases.filter { !filledRoles.contains($0) }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                // Head Coach
                Section("Head Coach") {
                    if let hc = headCoach {
                        NavigationLink {
                            CoachDetailView(coach: hc)
                        } label: {
                            CoachRowView(coach: hc)
                        }
                    } else {
                        vacantRow(role: .headCoach)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                // Coordinators
                Section("Coordinators") {
                    let coordRoles: [CoachRole] = [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator]
                    ForEach(coordRoles, id: \.self) { role in
                        if let coach = coaches.first(where: { $0.role == role }) {
                            NavigationLink {
                                CoachDetailView(coach: coach)
                            } label: {
                                CoachRowView(coach: coach)
                            }
                        } else {
                            vacantRow(role: role)
                        }
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                // Position Coaches
                Section("Position Coaches") {
                    let posRoles: [CoachRole] = [.qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach]
                    ForEach(posRoles, id: \.self) { role in
                        if let coach = coaches.first(where: { $0.role == role }) {
                            NavigationLink {
                                CoachDetailView(coach: coach)
                            } label: {
                                CoachRowView(coach: coach)
                            }
                        } else {
                            vacantRow(role: role)
                        }
                    }
                }
                .listRowBackground(Color.backgroundSecondary)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Coaching Staff")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    // MARK: - Vacant row

    @ViewBuilder
    private func vacantRow(role: CoachRole) -> some View {
        if let teamID = career.teamID {
            NavigationLink {
                HireCoachView(role: role, teamID: teamID)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(role.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textTertiary)
                        Text("Vacant — Tap to hire")
                            .font(.caption)
                            .foregroundStyle(Color.accentGold)
                    }
                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.accentGold)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Coach Row View

private struct CoachRowView: View {
    let coach: Coach

    /// The key attribute to surface depends on role tier.
    private var keyAttribute: (name: String, value: Int) {
        switch coach.role {
        case .headCoach, .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
            return ("Play Calling", coach.playCalling)
        default:
            return ("Development", coach.playerDevelopment)
        }
    }

    private var schemeText: String? {
        if let o = coach.offensiveScheme { return o.displayName }
        if let d = coach.defensiveScheme { return d.displayName }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            // Role badge
            Text(coach.role.abbreviation)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.backgroundPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(coach.role.badgeColor, in: RoundedRectangle(cornerRadius: 4))
                .frame(width: 44)

            // Name + meta
            VStack(alignment: .leading, spacing: 2) {
                Text(coach.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 6) {
                    Text("Age \(coach.age)")
                    Text("·")
                    Text("\(coach.yearsExperience) yr\(coach.yearsExperience == 1 ? "" : "s") exp")
                    if let scheme = schemeText {
                        Text("·")
                        Text(scheme)
                            .foregroundStyle(Color.accentBlue)
                    }
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            // Key attribute
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(keyAttribute.value)")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(keyAttribute.value))
                Text(keyAttribute.name)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(coach.fullName), \(coach.role.displayName), age \(coach.age), \(keyAttribute.name) \(keyAttribute.value)")
    }
}

// MARK: - CoachRole helpers

extension CoachRole {
    var displayName: String {
        switch self {
        case .headCoach:               return "Head Coach"
        case .offensiveCoordinator:    return "Offensive Coordinator"
        case .defensiveCoordinator:    return "Defensive Coordinator"
        case .specialTeamsCoordinator: return "Special Teams Coordinator"
        case .qbCoach:                 return "QB Coach"
        case .rbCoach:                 return "RB Coach"
        case .wrCoach:                 return "WR Coach"
        case .olCoach:                 return "OL Coach"
        case .dlCoach:                 return "DL Coach"
        case .lbCoach:                 return "LB Coach"
        case .dbCoach:                 return "DB Coach"
        case .strengthCoach:           return "Strength & Conditioning"
        }
    }

    var abbreviation: String {
        switch self {
        case .headCoach:               return "HC"
        case .offensiveCoordinator:    return "OC"
        case .defensiveCoordinator:    return "DC"
        case .specialTeamsCoordinator: return "STC"
        case .qbCoach:                 return "QB"
        case .rbCoach:                 return "RB"
        case .wrCoach:                 return "WR"
        case .olCoach:                 return "OL"
        case .dlCoach:                 return "DL"
        case .lbCoach:                 return "LB"
        case .dbCoach:                 return "DB"
        case .strengthCoach:           return "S&C"
        }
    }

    var sortOrder: Int {
        switch self {
        case .headCoach:               return 0
        case .offensiveCoordinator:    return 1
        case .defensiveCoordinator:    return 2
        case .specialTeamsCoordinator: return 3
        case .qbCoach:                 return 4
        case .rbCoach:                 return 5
        case .wrCoach:                 return 6
        case .olCoach:                 return 7
        case .dlCoach:                 return 8
        case .lbCoach:                 return 9
        case .dbCoach:                 return 10
        case .strengthCoach:           return 11
        }
    }

    var badgeColor: Color {
        switch self {
        case .headCoach:               return .accentGold
        case .offensiveCoordinator:    return .accentBlue
        case .defensiveCoordinator:    return .danger
        case .specialTeamsCoordinator: return .success
        default:                       return .backgroundTertiary
        }
    }
}

// MARK: - Scheme display helpers

extension OffensiveScheme {
    var displayName: String {
        switch self {
        case .westCoast:  return "West Coast"
        case .airRaid:    return "Air Raid"
        case .spread:     return "Spread"
        case .powerRun:   return "Power Run"
        case .shanahan:   return "Shanahan"
        case .proPassing: return "Pro Passing"
        case .rpo:        return "RPO"
        case .option:     return "Option"
        }
    }
}

extension DefensiveScheme {
    var displayName: String {
        switch self {
        case .base34:   return "3-4 Base"
        case .base43:   return "4-3 Base"
        case .cover3:   return "Cover 3"
        case .pressMan: return "Press Man"
        case .tampa2:   return "Tampa 2"
        case .multiple: return "Multiple"
        case .hybrid:   return "Hybrid"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CoachingStaffView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Coach.self], inMemory: true)
}
