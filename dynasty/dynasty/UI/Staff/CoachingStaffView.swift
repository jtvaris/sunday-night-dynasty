import SwiftUI
import SwiftData

// MARK: - Staff Tab Selection

enum StaffTab: String, CaseIterable {
    case staff = "Staff"
    case schemes = "Schemes"
    case review = "Review"
}

// StaffNavDestination removed — replaced with separate state bindings to avoid
// SwiftUI navigationDestination(item:) confusion after dismiss/re-navigate cycles.

struct CoachingStaffView: View {

    let career: Career
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var allCoaches: [Coach]
    @Query private var allScouts: [Scout]
    @Query private var allOwners: [Owner]
    @Query private var allPlayers: [Player]
    @Query private var allTeams: [Team]

    // MARK: - Tab State (#107)
    @State private var selectedTab: StaffTab = .staff

    // MARK: - Hiring Confirmation State (#49)
    @State private var recentHireMessage: String?

    // Lock-in moved to Dashboard workflow (CoachingStaffReviewSheet)

    // MARK: - Scheme Selection State (#67)
    @State private var showOffensiveSchemeSelection: Bool = false
    @State private var showDefensiveSchemeSelection: Bool = false

    // MARK: - Collapsible Section State (#80)
    @State private var isCoordinatorsExpanded: Bool = true
    @State private var isPositionCoachesExpanded: Bool = true
    @State private var isMedicalExpanded: Bool = true
    @State private var isScoutingExpanded: Bool = true

    // MARK: - Navigation State (separate bindings — sheets for hire views, push for detail)
    @State private var hireCoachRole: CoachRole?      // Opens HireCoachView as sheet
    @State private var hireScoutRole: ScoutRole?       // Opens HireScoutView as sheet
    @State private var showHireScoutSheet = false       // Workaround for SwiftUI sheet(item:) stale data bug
    @State private var showHireCoachSheet = false       // Same workaround
    @State private var detailCoachID: UUID?            // Pushes CoachDetailView via navigationDestination

    /// Coaches filtered to this team, derived from @Query result.
    private var coaches: [Coach] {
        guard let teamID = career.teamID else { return [] }
        return allCoaches.filter { $0.teamID == teamID }
    }

    /// Scouts filtered to this team.
    private var scouts: [Scout] {
        guard let teamID = career.teamID else { return [] }
        return allScouts.filter { $0.teamID == teamID }
    }

    /// Players on this team's roster.
    private var rosterPlayers: [Player] {
        guard let teamID = career.teamID else { return [] }
        return allPlayers.filter { $0.teamID == teamID }
    }

    /// Offensive players on the roster.
    private var offensivePlayers: [Player] {
        rosterPlayers.filter { $0.position.side == .offense }
            .sorted { $0.position.rawValue < $1.position.rawValue }
    }

    /// Defensive players on the roster.
    private var defensivePlayers: [Player] {
        rosterPlayers.filter { $0.position.side == .defense }
            .sorted { $0.position.rawValue < $1.position.rawValue }
    }

    /// The team's owner (for budget info).
    private var owner: Owner? {
        // Owner is stored on Team; find via allOwners matching our team
        // For now, use the first owner (single-team career)
        allOwners.first
    }

    /// #267: The player's team (for wins/prestige data).
    private var team: Team? {
        guard let teamID = career.teamID else { return nil }
        return allTeams.first { $0.id == teamID }
    }

    // MARK: - Budget Calculations

    /// Total coaching salary currently committed (in thousands).
    private var totalCoachSalaryUsed: Int {
        coaches.reduce(0) { $0 + $1.salary }
    }

    /// Total scouting salary currently committed (in thousands).
    private var totalScoutSalaryUsed: Int {
        scouts.reduce(0) { $0 + $1.salary }
    }

    /// Total staff salary used (coaches + scouts).
    private var totalStaffSalaryUsed: Int {
        totalCoachSalaryUsed + totalScoutSalaryUsed
    }

    /// Coaching budget from the owner (in thousands).
    private var coachingBudget: Int {
        owner?.coachingBudget ?? 20_000
    }

    /// Remaining budget available for new hires.
    private var remainingBudget: Int {
        coachingBudget - totalStaffSalaryUsed
    }

    // MARK: - Grouped coaches

    private var headCoach: Coach? {
        coaches.first { $0.role == .headCoach }
    }

    private var assistantHeadCoach: Coach? {
        coaches.first { $0.role == .assistantHeadCoach }
    }

    private var coordinators: [Coach] {
        coaches.filter { [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator].contains($0.role) }
            .sorted { $0.role.sortOrder < $1.role.sortOrder }
    }

    private var positionCoaches: [Coach] {
        coaches.filter { [.qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach].contains($0.role) }
            .sorted { $0.role.sortOrder < $1.role.sortOrder }
    }

    // MARK: - Medical staff

    private var medicalStaff: [Coach] {
        coaches.filter { [.teamDoctor, .physio].contains($0.role) }
            .sorted { $0.role.sortOrder < $1.role.sortOrder }
    }

    // MARK: - Scouting department

    private var chiefScout: Scout? {
        scouts.first { $0.scoutRole == .chiefScout }
    }

    private var regionalScouts: [Scout] {
        scouts.filter { $0.scoutRole != .chiefScout }
            .sorted { $0.scoutRole.sortOrder < $1.scoutRole.sortOrder }
    }

    // MARK: - Vacant roles

    private var vacantCoachRoles: [CoachRole] {
        let filledRoles = Set(coaches.map { $0.role })
        var allRoles = CoachRole.allCases.filter { !filledRoles.contains($0) }
        // If GM+HC, the head coach slot is the player — not vacant
        if career.role == .gmAndHeadCoach {
            allRoles.removeAll { $0 == .headCoach }
        }
        return allRoles
    }

    private var vacantScoutRoles: [ScoutRole] {
        let filledRoles = Set(scouts.map { $0.scoutRole })
        return ScoutRole.allCases.filter { !filledRoles.contains($0) }
    }

    // MARK: - Hiring priority & budget helpers

    /// Whether the budget is over (negative remaining).
    private var isBudgetOverspent: Bool {
        remainingBudget < 0
    }

    /// Required roles that must be filled before locking in staff.
    private var requiredCoachRoles: [CoachRole] {
        if career.role == .gmAndHeadCoach {
            return [.offensiveCoordinator, .defensiveCoordinator]
        } else {
            return [.headCoach, .offensiveCoordinator, .defensiveCoordinator]
        }
    }

    /// Whether all required coaching positions are filled.
    private var allRequiredRolesFilled: Bool {
        let filledRoles = Set(coaches.map { $0.role })
        return requiredCoachRoles.allSatisfy { filledRoles.contains($0) }
    }

    /// Missing required roles for display in the warning.
    private var missingRequiredRoles: [CoachRole] {
        let filledRoles = Set(coaches.map { $0.role })
        return requiredCoachRoles.filter { !filledRoles.contains($0) }
    }

    /// Whether the device is in iPad portrait (regular width) for 2-column layout.
    private var isIPadPortrait: Bool {
        horizontalSizeClass == .regular
    }

    /// Whether the Schemes tab is available (requires at least one coordinator).
    private var isSchemesTabAvailable: Bool {
        coaches.contains(where: { $0.role == .offensiveCoordinator }) ||
        coaches.contains(where: { $0.role == .defensiveCoordinator })
    }

    /// Whether both offensive and defensive schemes have been set by coordinators.
    private var areSchemesSet: Bool {
        let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
        let dc = coaches.first(where: { $0.role == .defensiveCoordinator })
        return oc?.offensiveScheme != nil && dc?.defensiveScheme != nil
    }

    /// Whether the Review tab is available (requires at least one hire).
    private var isReviewTabAvailable: Bool {
        !coaches.isEmpty || !scouts.isEmpty
    }

    /// Priority level for a vacant coaching role.
    private enum HiringPriority {
        case high, recommended, normal

        var label: String {
            switch self {
            case .high:        return "High Priority"
            case .recommended: return "Recommended"
            case .normal:      return ""
            }
        }
    }

    private func hiringPriority(for role: CoachRole) -> HiringPriority {
        switch role {
        case .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
            return .high
        case .qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach:
            return .recommended
        case .teamDoctor, .physio:
            return .recommended
        default:
            return .normal
        }
    }

    /// Estimated salary range string for a vacant role.
    private func estimatedSalaryRange(for role: CoachRole) -> String {
        switch role {
        case .headCoach:
            return "~$3-8M/yr"
        case .assistantHeadCoach:
            return "~$1-3M/yr"
        case .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
            return "~$2-5M/yr"
        default:
            return "~$0.5-2M/yr"
        }
    }

    /// Minimum salary estimate (in thousands) for a vacant coaching role.
    private func estimatedMinimumSalary(for role: CoachRole) -> Int {
        switch role {
        case .headCoach:                                          return 3_000
        case .assistantHeadCoach:                                 return 1_000
        case .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator: return 2_000
        default:                                                  return 500
        }
    }

    /// Minimum salary estimate (in thousands) for a vacant scout role.
    private func estimatedMinimumScoutSalary(for role: ScoutRole) -> Int {
        switch role {
        case .chiefScout: return 200
        default:          return 80
        }
    }

    /// #155: Estimated minimum cost to fill all vacant positions.
    private var estimatedMinimumToFillAll: Int {
        let coachCost = vacantCoachRoles.reduce(0) { $0 + estimatedMinimumSalary(for: $1) }
        let scoutCost = vacantScoutRoles.reduce(0) { $0 + estimatedMinimumScoutSalary(for: $1) }
        return coachCost + scoutCost
    }

    /// Description of what position group a position coach improves.
    private func positionGroupBoost(for role: CoachRole) -> String? {
        switch role {
        case .qbCoach:        return "Improves QB development"
        case .rbCoach:        return "Improves RB development"
        case .wrCoach:        return "Improves WR development"
        case .olCoach:        return "Improves OL development"
        case .dlCoach:        return "Improves DL development"
        case .lbCoach:        return "Improves LB development"
        case .dbCoach:        return "Improves DB development"
        case .strengthCoach:  return "Improves conditioning & injury prevention"
        case .teamDoctor:     return "Reduces injury risk by up to 30%"
        case .physio:         return "Speeds recovery by up to 25%"
        default:              return nil
        }
    }

    /// Estimated salary range for a scout role.
    private func estimatedScoutSalaryRange(for role: ScoutRole) -> String {
        switch role {
        case .chiefScout:
            return "~$200-600K/yr"
        default:
            return "~$80-250K/yr"
        }
    }

    /// Hiring impact description for a scout role.
    private func scoutHiringImpact(for role: ScoutRole) -> String {
        switch role {
        case .chiefScout:
            return "+15% draft evaluation accuracy"
        default:
            return "+5% regional prospect coverage"
        }
    }

    /// Hiring priority for a scout role.
    private func scoutHiringPriority(for role: ScoutRole) -> HiringPriority {
        switch role {
        case .chiefScout: return .high
        default: return .recommended
        }
    }

    /// Hiring impact description for a coaching role (#51).
    private func hiringImpactDescription(for role: CoachRole) -> String? {
        switch role {
        case .offensiveCoordinator:    return "+12% offensive efficiency"
        case .defensiveCoordinator:    return "+12% defensive efficiency"
        case .specialTeamsCoordinator: return "+8% special teams performance"
        case .qbCoach:                 return "+10% QB development speed"
        case .rbCoach:                 return "+10% RB development speed"
        case .wrCoach:                 return "+10% WR development speed"
        case .olCoach:                 return "+10% OL development speed"
        case .dlCoach:                 return "+10% DL development speed"
        case .lbCoach:                 return "+10% LB development speed"
        case .dbCoach:                 return "+10% DB development speed"
        case .strengthCoach:           return "-15% injury risk across roster"
        case .teamDoctor:              return "-30% injury severity"
        case .physio:                  return "+25% recovery speed"
        case .assistantHeadCoach:      return "+5% staff chemistry bonus"
        case .headCoach:               return "+15% overall team performance"
        }
    }

    /// Suggestion for what coordinators complement a given coaching style.
    private func coordinatorComplementNote(for style: CoachingStyle) -> String {
        switch style {
        case .tactician:
            return "Pair with creative coordinators who can execute complex schemes"
        case .playersCoach:
            return "Pair with disciplined coordinators to balance player freedom"
        case .disciplinarian:
            return "Pair with adaptable coordinators who thrive in structured systems"
        case .innovator:
            return "Pair with experienced coordinators who can ground bold ideas"
        case .motivator:
            return "Pair with detail-oriented coordinators to complement big-picture leadership"
        }
    }

    // MARK: - Chemistry helpers

    /// Returns the chemistry score between the HC (or player-as-HC) and a given coach.
    private func chemistryWithHC(coach: Coach) -> Double? {
        if career.role == .gmAndHeadCoach {
            // Use the player's coaching style personality analog
            // Map coaching style to a personality archetype for chemistry calc
            let playerPersonality = coachingStylePersonality(career.coachingStyle)
            return CoachingEngine.coachChemistry(coachA: playerPersonality, coachB: coach.personality)
        } else if let hc = headCoach {
            return CoachingEngine.coachChemistry(coachA: hc.personality, coachB: coach.personality)
        }
        return nil
    }

    /// Maps a CoachingStyle to a PersonalityArchetype for chemistry calculations.
    private func coachingStylePersonality(_ style: CoachingStyle) -> PersonalityArchetype {
        switch style {
        case .tactician:      return .quietProfessional
        case .motivator:      return .fieryCompetitor
        case .playersCoach:   return .mentor
        case .innovator:      return .feelPlayer
        case .disciplinarian: return .steadyPerformer
        }
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            // Locker room background image with gradient overlay
            GeometryReader { geo in
                Image("BgLockerRoom2")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.12)
            }
            .ignoresSafeArea()
                .overlay(
                    LinearGradient(
                        colors: [Color.backgroundPrimary.opacity(0.6), Color.clear, Color.backgroundPrimary.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )

            VStack(spacing: 0) {
                // MARK: - Tab Bar (#107)
                staffTabBar

                // Tab content
                switch selectedTab {
                case .staff:
                    staffTabContent
                case .schemes:
                    schemesTabContent
                case .review:
                    reviewTabContent
                }
            }

            // MARK: - Hiring Confirmation Toast (#49)
            if let message = recentHireMessage {
                VStack {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.success)
                        Text(message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.success.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.success.opacity(0.4), lineWidth: 1)
                            )
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Spacer()
                }
            }
        }
        .navigationTitle("Coaching Staff")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Coach detail stays as navigation push (works correctly)
        .navigationDestination(item: $detailCoachID) { coachID in
            if let coach = allCoaches.first(where: { $0.id == coachID }) {
                CoachDetailView(coach: coach)
            }
        }
        // Hire Coach as SHEET — uses isPresented to avoid SwiftUI sheet(item:) stale data bug
        .sheet(isPresented: $showHireCoachSheet, onDismiss: { hireCoachRole = nil }) {
            if let role = hireCoachRole, let teamID = career.teamID {
                NavigationStack {
                    HireCoachView(
                        role: role,
                        teamID: teamID,
                        remainingBudget: remainingBudget,
                        teamBudget: coachingBudget,
                        teamWins: team?.wins ?? 8,
                        teamReputation: career.reputation,
                        onHired: { name, roleName in
                            showHireCoachSheet = false
                            showHiringConfirmation(coachName: name, roleName: roleName)
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showHireCoachSheet = false }
                                .foregroundStyle(Color.accentGold)
                        }
                    }
                }
            }
        }
        // Hire Scout as SHEET — same isPresented pattern
        .sheet(isPresented: $showHireScoutSheet, onDismiss: { hireScoutRole = nil }) {
            if let role = hireScoutRole, let teamID = career.teamID {
                NavigationStack {
                    HireScoutView(scoutRole: role, teamID: teamID, remainingBudget: remainingBudget, onHired: { name, roleName in
                        showHireScoutSheet = false
                        showHiringConfirmation(coachName: name, roleName: roleName)
                    })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showHireScoutSheet = false }
                                .foregroundStyle(Color.accentGold)
                        }
                    }
                }
            }
        }
        // Lock-in alerts moved to Dashboard workflow (CoachingStaffReviewSheet)
    }

    // MARK: - Tab Bar (#107)

    private var staffTabBar: some View {
        HStack(spacing: 0) {
            ForEach(StaffTab.allCases, id: \.self) { tab in
                let isLocked = (tab == .schemes && !isSchemesTabAvailable) ||
                               (tab == .review && !isReviewTabAvailable)
                let isSelected = selectedTab == tab

                Button {
                    if !isLocked {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    }
                } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 4) {
                            if isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9))
                            }
                            Text(tab.rawValue)
                                .font(.subheadline.weight(isSelected ? .bold : .medium))
                        }
                        .foregroundStyle(
                            isSelected ? Color.accentGold :
                            isLocked ? Color.textTertiary.opacity(0.5) :
                            Color.textSecondary
                        )

                        Rectangle()
                            .fill(isSelected ? Color.accentGold : Color.clear)
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isLocked ? 0.5 : 1.0)
                .accessibilityHint(isLocked ? "Hire coordinators to unlock" : "")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Staff Tab Content

    private var staffTabContent: some View {
        ZStack(alignment: .bottom) {
            List {
                // MARK: - Budget Header
                Section {
                    budgetHeaderView

                    // Over-budget warning banner
                    if isBudgetOverspent {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.danger)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Over Budget")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Color.danger)
                                Text("You are $\(formatBudget(abs(remainingBudget)))M over the coaching budget. Release staff or reduce salaries to proceed.")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.danger.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.danger.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                } header: {
                    Text("Staff Budget")
                }
                .listRowBackground(Color.backgroundSecondary)

                // Head Coach -- prominent card
                Section {
                    if career.role == .gmAndHeadCoach {
                        playerAsHeadCoachRow
                    } else if let hc = headCoach {
                        Button {
                            detailCoachID = hc.id
                        } label: {
                            HeadCoachCardView(coach: hc, menteeCount: coaches.filter { $0.mentorCoachID == hc.id }.count)
                        }
                    } else {
                        headCoachVacantRow
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("1")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Color.backgroundPrimary)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.accentGold))
                        Text("Head Coach")
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.backgroundSecondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.accentGold.opacity(0.4), lineWidth: 1.5)
                        )
                        .padding(2)
                )

                // Assistant Head Coach
                Section {
                    if let ahc = assistantHeadCoach {
                        coachRowWithChemistry(coach: ahc)
                    } else {
                        vacantRow(role: .assistantHeadCoach)
                    }
                } header: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentGold)
                        Text("Assistant Head Coach")
                    }
                }
                .listRowBackground(Color.backgroundSecondary)

                // MARK: - Coordinators (#80 collapsible)
                Section {
                    DisclosureGroup(isExpanded: $isCoordinatorsExpanded) {
                        let coordRoles: [CoachRole] = [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator]
                        ForEach(coordRoles, id: \.self) { role in
                            if let coach = coaches.first(where: { $0.role == role }) {
                                coachRowWithChemistry(coach: coach)
                            } else {
                                vacantRow(role: role)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("2")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Color.backgroundPrimary)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.accentGold))
                            Text("Coordinators")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            let filledCount = coaches.filter { [CoachRole.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator].contains($0.role) }.count
                            Text("\(filledCount)/3")
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(filledCount == 3 ? Color.success : Color.warning)
                        }
                    }
                    .tint(Color.accentGold)
                }
                .listRowBackground(Color.backgroundSecondary)

                // MARK: - Position Coaches (#50 compact grid, #80 collapsible)
                Section {
                    DisclosureGroup(isExpanded: $isPositionCoachesExpanded) {
                        let posRoles: [CoachRole] = [.qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach]
                        // #50: Compact 2-column grid of cards
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ], spacing: 10) {
                            ForEach(posRoles, id: \.self) { role in
                                if let coach = coaches.first(where: { $0.role == role }) {
                                    Button {
                                        detailCoachID = coach.id
                                    } label: {
                                        compactCoachCard(coach: coach)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    compactVacantCard(role: role)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } label: {
                        HStack(spacing: 6) {
                            Text("3")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Color.backgroundPrimary)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.accentGold))
                            Text("Position Coaches")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            let filledCount = positionCoaches.count
                            Text("\(filledCount)/8")
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(filledCount == 8 ? Color.success : Color.textTertiary)
                        }
                    }
                    .tint(Color.accentGold)
                }
                .listRowBackground(Color.backgroundSecondary)

                // MARK: - Medical & Scouting (#54 side-by-side on iPad, #80 collapsible)
                if isIPadPortrait {
                    Section {
                        HStack(alignment: .top, spacing: 16) {
                            // Left column: Medical Staff
                            VStack(alignment: .leading, spacing: 0) {
                                DisclosureGroup(isExpanded: $isMedicalExpanded) {
                                    let medRoles: [CoachRole] = [.teamDoctor, .physio]
                                    ForEach(medRoles, id: \.self) { role in
                                        if let coach = coaches.first(where: { $0.role == role }) {
                                            Button {
                                                detailCoachID = coach.id
                                            } label: {
                                                compactCoachCard(coach: coach)
                                            }
                                            .buttonStyle(.plain)
                                        } else {
                                            compactVacantCard(role: role)
                                        }
                                        if role != .physio {
                                            Divider().padding(.vertical, 4)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("4")
                                            .font(.system(size: 10, weight: .black))
                                            .foregroundStyle(Color.backgroundPrimary)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(Color.accentGold))
                                        Text("Medical Staff")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.textPrimary)
                                    }
                                }
                                .tint(Color.accentGold)
                            }
                            .frame(maxWidth: .infinity)

                            Divider()

                            // Right column: Scouting Department
                            VStack(alignment: .leading, spacing: 0) {
                                DisclosureGroup(isExpanded: $isScoutingExpanded) {
                                    if let chief = chiefScout {
                                        scoutRow(scout: chief)
                                    } else {
                                        scoutVacantRow(role: .chiefScout)
                                    }
                                    let regionalRoles: [ScoutRole] = [.regionalScout1, .regionalScout2, .regionalScout3, .regionalScout4, .regionalScout5]
                                    ForEach(regionalRoles, id: \.self) { role in
                                        if let scout = scouts.first(where: { $0.scoutRole == role }) {
                                            scoutRow(scout: scout)
                                        } else {
                                            scoutVacantRow(role: role)
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("5")
                                            .font(.system(size: 10, weight: .black))
                                            .foregroundStyle(Color.backgroundPrimary)
                                            .frame(width: 18, height: 18)
                                            .background(Circle().fill(Color.accentGold))
                                        Text("Scouting")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.textPrimary)
                                    }
                                }
                                .tint(Color.accentGold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } header: {
                        Text("Support Staff")
                    }
                    .listRowBackground(Color.backgroundSecondary)
                } else {
                    // MARK: - Medical Staff (single column, collapsible)
                    Section {
                        DisclosureGroup(isExpanded: $isMedicalExpanded) {
                            let medRoles: [CoachRole] = [.teamDoctor, .physio]
                            ForEach(medRoles, id: \.self) { role in
                                if let coach = coaches.first(where: { $0.role == role }) {
                                    Button {
                                        detailCoachID = coach.id
                                    } label: {
                                        compactCoachCard(coach: coach)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    compactVacantCard(role: role)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("4")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(Color.backgroundPrimary)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.accentGold))
                                Text("Medical Staff")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                        .tint(Color.accentGold)
                    }
                    .listRowBackground(Color.backgroundSecondary)

                    // MARK: - Scouting Department (single column, collapsible)
                    Section {
                        DisclosureGroup(isExpanded: $isScoutingExpanded) {
                            if let chief = chiefScout {
                                scoutRow(scout: chief)
                            } else {
                                scoutVacantRow(role: .chiefScout)
                            }
                            let regionalRoles: [ScoutRole] = [.regionalScout1, .regionalScout2, .regionalScout3, .regionalScout4, .regionalScout5]
                            ForEach(regionalRoles, id: \.self) { role in
                                if let scout = scouts.first(where: { $0.scoutRole == role }) {
                                    scoutRow(scout: scout)
                                } else {
                                    scoutVacantRow(role: role)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text("5")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(Color.backgroundPrimary)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(Color.accentGold))
                                Text("Scouting Department")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.textPrimary)
                            }
                        }
                        .tint(Color.accentGold)
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }

                // (Lock in button moved to Dashboard workflow)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)

            // Lock in button moved to Dashboard workflow (CoachingStaffReviewSheet)
        }
    }

    // MARK: - Schemes Tab Content (#107, #76)

    private var schemesTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Offensive Scheme Card
                offensiveSchemeCard

                // Offensive Roster Fit
                if let oc = coaches.first(where: { $0.role == .offensiveCoordinator }),
                   let scheme = oc.offensiveScheme {
                    schemeRosterFitSection(
                        title: "OFFENSIVE ROSTER FIT",
                        scheme: scheme.displayName,
                        coordinatorName: oc.fullName,
                        players: offensivePlayers,
                        offensiveScheme: scheme,
                        defensiveScheme: nil
                    )
                }

                // Defensive Scheme Card
                defensiveSchemeCard

                // Defensive Roster Fit
                if let dc = coaches.first(where: { $0.role == .defensiveCoordinator }),
                   let scheme = dc.defensiveScheme {
                    schemeRosterFitSection(
                        title: "DEFENSIVE ROSTER FIT",
                        scheme: scheme.displayName,
                        coordinatorName: dc.fullName,
                        players: defensivePlayers,
                        offensiveScheme: nil,
                        defensiveScheme: scheme
                    )
                }

                // Scheme Impact Info
                schemeImpactCard
            }
            .padding(16)
        }
        .sheet(isPresented: $showOffensiveSchemeSelection) {
            if let oc = coaches.first(where: { $0.role == .offensiveCoordinator }) {
                SchemeSelectionView(
                    coordinator: oc,
                    players: offensivePlayers,
                    isOffensive: true
                )
            }
        }
        .sheet(isPresented: $showDefensiveSchemeSelection) {
            if let dc = coaches.first(where: { $0.role == .defensiveCoordinator }) {
                SchemeSelectionView(
                    coordinator: dc,
                    players: defensivePlayers,
                    isOffensive: false
                )
            }
        }
    }

    // MARK: - Offensive Scheme Card

    private var offensiveSchemeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OFFENSIVE SCHEME")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            if let oc = coaches.first(where: { $0.role == .offensiveCoordinator }),
               let scheme = oc.offensiveScheme {
                HStack(spacing: 12) {
                    Image(systemName: "football.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentBlue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scheme.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Set by OC \(oc.fullName)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(offensiveSchemeDescription(scheme))
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Button {
                        showOffensiveSchemeSelection = true
                    } label: {
                        Text("Change")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.accentGold.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "football")
                        .font(.title2)
                        .foregroundStyle(Color.textTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No Offensive Scheme")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textTertiary)
                        Text("Hire an Offensive Coordinator to set your offensive scheme")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Defensive Scheme Card

    private var defensiveSchemeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEFENSIVE SCHEME")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            if let dc = coaches.first(where: { $0.role == .defensiveCoordinator }),
               let scheme = dc.defensiveScheme {
                HStack(spacing: 12) {
                    Image(systemName: "shield.fill")
                        .font(.title2)
                        .foregroundStyle(Color.danger)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scheme.displayName)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Set by DC \(dc.fullName)")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(defensiveSchemeDescription(scheme))
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Button {
                        showDefensiveSchemeSelection = true
                    } label: {
                        Text("Change")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.accentGold.opacity(0.5), lineWidth: 1)
                            )
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "shield")
                        .font(.title2)
                        .foregroundStyle(Color.textTertiary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("No Defensive Scheme")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textTertiary)
                        Text("Hire a Defensive Coordinator to set your defensive scheme")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Scheme Roster Fit Section

    private func schemeRosterFitSection(
        title: String,
        scheme: String,
        coordinatorName: String?,
        players: [Player],
        offensiveScheme: OffensiveScheme?,
        defensiveScheme: DefensiveScheme?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            if players.isEmpty {
                Text("No players on roster for this side of the ball.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
            } else {
                // Player fit bars
                ForEach(players.prefix(15), id: \.id) { player in
                    let fitScore = CoachingEngine.schemeFit(
                        player: player,
                        offensiveScheme: offensiveScheme,
                        defensiveScheme: defensiveScheme
                    )
                    let fitPercent = Int(fitScore * 100)
                    let fitColor = schemeFitColor(fitPercent)

                    HStack(spacing: 8) {
                        Text(player.position.rawValue)
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 28, alignment: .leading)

                        Text(player.fullName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.backgroundTertiary)
                                    .frame(height: 8)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(fitColor)
                                    .frame(width: max(0, geo.size.width * fitScore), height: 8)
                            }
                        }
                        .frame(width: 80, height: 8)

                        Text("\(fitPercent)%")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(fitColor)
                            .frame(width: 32, alignment: .trailing)
                    }
                }

                // Average fit
                Divider().overlay(Color.surfaceBorder)

                let avgFit = players.reduce(0.0) { sum, player in
                    sum + CoachingEngine.schemeFit(
                        player: player,
                        offensiveScheme: offensiveScheme,
                        defensiveScheme: defensiveScheme
                    )
                } / max(1.0, Double(players.count))
                let avgPercent = Int(avgFit * 100)
                let avgColor = schemeFitColor(avgPercent)

                HStack {
                    Text("Average Fit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(avgPercent)%")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(avgColor)
                    Text(schemeFitLabel(avgPercent))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(avgColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(avgColor.opacity(0.15))
                        )
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Scheme Impact Card

    private var schemeImpactCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SCHEME IMPACT")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            VStack(alignment: .leading, spacing: 6) {
                schemeImpactRow(
                    icon: "sportscourt.fill",
                    text: "Your offensive scheme affects play calling tendencies during games."
                )
                schemeImpactRow(
                    icon: "chart.line.uptrend.xyaxis",
                    text: "Players with high scheme fit perform better in game simulations."
                )
                schemeImpactRow(
                    icon: "arrow.up.forward.circle.fill",
                    text: "Players with high scheme fit develop faster in the offseason."
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private func schemeImpactRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.accentGold.opacity(0.7))
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Scheme Fit Helpers

    private func schemeFitColor(_ percent: Int) -> Color {
        if percent >= 80 { return Color.success }
        if percent >= 60 { return Color.accentGold }
        return Color.danger
    }

    private func schemeFitLabel(_ percent: Int) -> String {
        if percent >= 80 { return "Great" }
        if percent >= 60 { return "Good" }
        if percent >= 40 { return "Fair" }
        return "Poor"
    }

    // MARK: - Review Tab Content (#107)

    private var reviewTabContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Staff Overview
                VStack(alignment: .leading, spacing: 12) {
                    Text("STAFF OVERVIEW")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.accentGold)

                    HStack(spacing: 20) {
                        reviewStatBadge(value: "\(coaches.count)", label: "Coaches", color: .accentGold)
                        reviewStatBadge(value: "\(scouts.count)", label: "Scouts", color: .accentBlue)
                        reviewStatBadge(value: "\(vacantCoachRoles.count)", label: "Vacant", color: vacantCoachRoles.isEmpty ? .success : .warning)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()

                // Budget Summary
                VStack(alignment: .leading, spacing: 12) {
                    Text("BUDGET SUMMARY")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.accentGold)

                    HStack {
                        Text("Total Budget")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("$\(formatBudget(coachingBudget))M")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }

                    HStack {
                        Text("Coaching Salaries")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("$\(formatBudget(totalCoachSalaryUsed))M")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }

                    HStack {
                        Text("Scouting Salaries")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        Text("$\(formatBudget(totalScoutSalaryUsed))M")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                    }

                    Divider().overlay(Color.surfaceBorder)

                    HStack {
                        Text("Remaining")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Text("$\(formatBudget(remainingBudget))M")
                            .font(.headline.weight(.bold).monospacedDigit())
                            .foregroundStyle(remainingBudget >= 0 ? Color.success : Color.danger)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()

                // Staff Ratings
                VStack(alignment: .leading, spacing: 12) {
                    Text("STAFF RATINGS")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.accentGold)

                    if coaches.isEmpty {
                        Text("No coaching staff hired yet.")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        ForEach(coaches.sorted(by: { $0.role.sortOrder < $1.role.sortOrder })) { coach in
                            let ovr = coachOverall(coach)
                            HStack(spacing: 10) {
                                Text(coach.role.abbreviation)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.backgroundPrimary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(coach.role.badgeColor, in: RoundedRectangle(cornerRadius: 4))
                                    .frame(width: 36)

                                Text(coach.fullName)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textPrimary)
                                    .lineLimit(1)

                                Spacer()

                                Text("\(ovr)")
                                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                                    .foregroundStyle(Color.forRating(ovr))
                            }

                            if coach.id != coaches.sorted(by: { $0.role.sortOrder < $1.role.sortOrder }).last?.id {
                                Divider().overlay(Color.surfaceBorder.opacity(0.4))
                            }
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()

                // Readiness Check
                VStack(alignment: .leading, spacing: 12) {
                    Text("READINESS CHECK")
                        .font(.system(size: 11, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(Color.accentGold)

                    readinessRow(label: "Head Coach", filled: career.role == .gmAndHeadCoach || headCoach != nil)
                    readinessRow(label: "Offensive Coordinator", filled: coaches.contains(where: { $0.role == .offensiveCoordinator }))
                    readinessRow(label: "Defensive Coordinator", filled: coaches.contains(where: { $0.role == .defensiveCoordinator }))
                    readinessRow(label: "Special Teams Coordinator", filled: coaches.contains(where: { $0.role == .specialTeamsCoordinator }))
                    readinessRow(label: "Budget Within Limits", filled: !isBudgetOverspent)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
            }
            .padding(16)
        }
    }

    // Lock in staff button removed — now handled by CoachingStaffReviewSheet in Dashboard workflow

    // MARK: - Review Tab Helpers

    private func reviewStatBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .black).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(width: 72, height: 56)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func readinessRow(label: String, filled: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: filled ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(filled ? Color.success : Color.textTertiary)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(filled ? Color.textPrimary : Color.textTertiary)
            Spacer()
        }
    }

    private func coachOverall(_ coach: Coach) -> Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

    // MARK: - Scheme Descriptions

    private func offensiveSchemeDescription(_ scheme: OffensiveScheme) -> String {
        switch scheme {
        case .westCoast:  return "Short-to-intermediate passing with high-percentage throws and run-after-catch emphasis."
        case .airRaid:    return "Spread formations with four- and five-wide sets, emphasizing the vertical passing game."
        case .spread:     return "Space the field with spread formations, using both run and pass to exploit matchups."
        case .powerRun:   return "Downhill running attack with pulling guards and fullback leads."
        case .shanahan:   return "Outside zone running scheme with play-action boots and misdirection."
        case .proPassing: return "Pro-style balanced attack with multiple formations and under-center play-action."
        case .rpo:        return "Run-pass option plays that let the QB read the defense post-snap."
        case .option:     return "Triple-option and read-option concepts emphasizing athletic QBs."
        }
    }

    private func defensiveSchemeDescription(_ scheme: DefensiveScheme) -> String {
        switch scheme {
        case .base34:   return "3-4 base with versatile OLBs who can rush and drop into coverage."
        case .base43:   return "4-3 base with four down linemen generating the pass rush."
        case .cover3:   return "Cover 3 zone with three deep defenders and four underneath zones."
        case .pressMan: return "Aggressive press-man coverage at the line with tight man-to-man assignments."
        case .tampa2:   return "Tampa 2 zone with a fast MLB dropping into deep middle coverage."
        case .multiple: return "Multiple fronts and coverages that disguise the defense pre-snap."
        case .hybrid:   return "Hybrid defense blending 3-4 and 4-3 principles with positionless players."
        }
    }

    // MARK: - Hiring Toast Trigger (#49)

    /// Call this when returning from a hiring screen to show confirmation toast.
    func showHiringConfirmation(coachName: String, roleName: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            recentHireMessage = "\(coachName) hired as \(roleName)!"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation(.easeOut(duration: 0.4)) {
                recentHireMessage = nil
            }
        }
    }

    // MARK: - Budget Header

    /// Budget change from previous season (in thousands).
    private var budgetChange: Int? {
        guard let prev = owner?.previousCoachingBudget, prev > 0 else { return nil }
        return coachingBudget - prev
    }

    @ViewBuilder
    private var budgetHeaderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coaching Budget")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    HStack(spacing: 4) {
                        Text("$\(formatBudget(totalStaffSalaryUsed))M / $\(formatBudget(coachingBudget))M used")
                            .font(.caption)
                            .foregroundStyle(remainingBudget >= 0 ? Color.textSecondary : Color.danger)

                        // Show budget change from last season (#80)
                        if let change = budgetChange, change != 0 {
                            Text(change > 0 ? "(+$\(formatBudget(change))M)" : "(-$\(formatBudget(abs(change)))M)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(change > 0 ? Color.success : Color.danger)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(formatBudget(remainingBudget))M")
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(remainingBudget >= 0 ? Color.success : Color.danger)
                    Text("remaining")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.backgroundTertiary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(remainingBudget >= 0 ? Color.accentGold : Color.danger)
                        .frame(width: geo.size.width * min(1.0, Double(totalStaffSalaryUsed) / max(1.0, Double(coachingBudget))))
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
    }

    /// Formats a budget value (in thousands) to a display string like "25.0".
    private func formatBudget(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "%.1f", millions)
    }

    // MARK: - Player as HC row (GM+HC career)

    @ViewBuilder
    private var playerAsHeadCoachRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                // HC badge
                Text("HC")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("You")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.accentGold)
                        Text("(\(career.playerName))")
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                    }

                    HStack(spacing: 6) {
                        Text(career.coachingStyle.displayName)
                            .foregroundStyle(Color.accentBlue)
                        Text("\u{00B7}")
                        Text("GM & Head Coach")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .font(.caption)
                }

                Spacer()

                // Player avatar
                Image(career.avatarID)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.accentGold, lineWidth: 2))
            }

            Text("Sets the team's vision, manages coordinators, and makes key game-day decisions")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)

            // Fix #36: Coaching style bonus for player-as-HC
            HStack(spacing: 4) {
                Text("+\(career.coachingStyle.bonusValue) \(career.coachingStyle.bonusAttribute)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.success)
            }

            HStack(spacing: 4) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 9))
                Text(coordinatorComplementNote(for: career.coachingStyle))
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.accentGold.opacity(0.8))
        }
        .padding(.vertical, 6)
    }

    // MARK: - Coach Row with Chemistry Indicator

    @ViewBuilder
    private func coachRowWithChemistry(coach: Coach) -> some View {
        Button {
            detailCoachID = coach.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                CoachRowWithDescriptionView(coach: coach)

                // Chemistry indicator
                if let chemistry = chemistryWithHC(coach: coach) {
                    HStack(spacing: 4) {
                        Text(CoachingEngine.chemistrySymbol(score: chemistry))
                            .font(.caption)
                        Text(CoachingEngine.chemistryLabel(score: chemistry))
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(chemistryColor(for: chemistry))
                    .padding(.leading, 56) // align with name after badge
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compact Coach Card (#50)

    @ViewBuilder
    private func compactCoachCard(coach: Coach) -> some View {
        let keyAttr: (name: String, value: Int) = {
            switch coach.role {
            case .headCoach, .assistantHeadCoach, .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
                return ("PC", coach.playCalling)
            default:
                return ("Dev", coach.playerDevelopment)
            }
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(coach.role.abbreviation)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(coach.role.badgeColor, in: RoundedRectangle(cornerRadius: 3))

                Spacer()

                Text("\(keyAttr.value)")
                    .font(.system(size: 14, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(keyAttr.value))
            }

            HStack(spacing: 4) {
                Text(coach.fullName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                if coach.isInAdjustmentPeriod {
                    Text("Adjusting")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                }
            }

            HStack(spacing: 4) {
                Text("\(coach.yearsExperience)yr")
                    .font(.system(size: 9).monospacedDigit())
                Text("\u{00B7}")
                Text("$\(coach.salary)K")
                    .font(.system(size: 9).monospacedDigit())
            }
            .foregroundStyle(Color.textTertiary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.surfaceBorder.opacity(0.5), lineWidth: 1)
                )
        )
    }

    // MARK: - Compact Vacant Card (#50)

    @ViewBuilder
    private func compactVacantCard(role: CoachRole) -> some View {
        Button {
            hireCoachRole = role
            showHireCoachSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(role.abbreviation)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 3))

                    Spacer()

                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.accentGold)
                }

                Text(role.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)

                // #51: Impact hint in compact card
                if let impact = hiringImpactDescription(for: role) {
                    Text(impact)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.success)
                        .lineLimit(1)
                }

                Text(estimatedSalaryRange(for: role))
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentGold.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Returns a color based on the chemistry score.
    private func chemistryColor(for score: Double) -> Color {
        switch score {
        case 0.3...:   return .success
        case -0.29...0.29: return .warning
        default:        return .danger
        }
    }

    // MARK: - HC Vacant Row (prominent)

    @ViewBuilder
    private var headCoachVacantRow: some View {
        Button {
            hireCoachRole = .headCoach
        } label: {
                VStack(spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Head Coach")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(Color.textTertiary)
                            Text("Sets the team's vision, manages coordinators, and makes key game-day decisions")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentGold)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.caption)
                        Text("HIRE FIRST")
                            .font(.caption.weight(.heavy))
                            .tracking(1)
                    }
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.accentGold.opacity(0.12))
                    )
                }
                .padding(.vertical, 6)
            }
        }


    // MARK: - Vacant row

    @ViewBuilder
    private func vacantRow(role: CoachRole) -> some View {
        Button {
            hireCoachRole = role
            showHireCoachSheet = true
        } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(role.displayName)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.textTertiary)

                            // Fix #32: Hiring priority indicator
                            switch hiringPriority(for: role) {
                            case .high:
                                Text("High Priority")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.danger, in: Capsule())
                            case .recommended:
                                Text("Recommended")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Color.warning)
                            case .normal:
                                EmptyView()
                            }
                        }

                        Text("Vacant \u{2014} Tap to hire")
                            .font(.caption)
                            .foregroundStyle(Color.accentGold)

                        // Fix #35: Estimated salary range
                        Text(estimatedSalaryRange(for: role))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)

                        // Fix #32: Position group boost description
                        if let boost = positionGroupBoost(for: role) {
                            Text(boost)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.accentBlue.opacity(0.8))
                        }

                        // #51: Hiring impact on team performance
                        if let impact = hiringImpactDescription(for: role) {
                            HStack(spacing: 4) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.system(size: 8))
                                Text(impact)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(Color.success)
                        }
                    }
                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.accentGold)
                }
                .padding(.vertical, 4)
            }
        }

    // MARK: - Scout Row

    @ViewBuilder
    private func scoutRow(scout: Scout) -> some View {
        HStack(spacing: 12) {
            // Role badge
            Text(scout.scoutRole.abbreviation)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.backgroundPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(scout.scoutRole.isChief ? Color.accentGold : Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 4))
                .frame(width: 44)

            // Name + meta
            VStack(alignment: .leading, spacing: 2) {
                Text(scout.fullName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 6) {
                    Text("\(scout.experience) yr\(scout.experience == 1 ? "" : "s") exp")
                    if let spec = scout.positionSpecialization {
                        Text("\u{00B7}")
                        Text(spec.rawValue)
                            .foregroundStyle(Color.accentBlue)
                    }
                    Text("\u{00B7}")
                    Text("$\(scout.salary)K")
                        .foregroundStyle(Color.textTertiary)
                }
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            // Accuracy rating
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(scout.accuracy)")
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.forRating(scout.accuracy))
                Text("Accuracy")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Scout Vacant Row

    @ViewBuilder
    private func scoutVacantRow(role: ScoutRole) -> some View {
        Button {
            hireScoutRole = role
            showHireScoutSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(role.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textTertiary)

                        // #53: Priority badge consistent with coach vacant rows
                        switch scoutHiringPriority(for: role) {
                        case .high:
                            Text("High Priority")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.danger, in: Capsule())
                        case .recommended:
                            Text("Recommended")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.warning)
                        case .normal:
                            EmptyView()
                        }
                    }

                    Text("Vacant \u{2014} Tap to hire")
                        .font(.caption)
                        .foregroundStyle(Color.accentGold)

                    // #53: Salary range
                    Text(estimatedScoutSalaryRange(for: role))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)

                    // #53: Hiring impact
                    HStack(spacing: 4) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 8))
                        Text(scoutHiringImpact(for: role))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color.success)
                }
                Spacer()
                Image(systemName: "plus.circle")
                    .foregroundStyle(Color.accentGold)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Head Coach Card (Prominent)

private struct HeadCoachCardView: View {
    let coach: Coach
    var menteeCount: Int = 0

    private var schemeText: String? {
        if let o = coach.offensiveScheme { return o.displayName }
        if let d = coach.defensiveScheme { return d.displayName }
        return nil
    }

    /// The HC's strongest attribute and its value.
    private var topAttribute: (name: String, value: Int) {
        let attributes: [(String, Int)] = [
            ("Play Calling", coach.playCalling),
            ("Player Dev", coach.playerDevelopment),
            ("Game Planning", coach.gamePlanning),
            ("Motivation", coach.motivation),
            ("Adaptability", coach.adaptability),
            ("Discipline", coach.discipline)
        ]
        return attributes.max(by: { $0.1 < $1.1 }) ?? ("Play Calling", coach.playCalling)
    }

    /// Coordinator complement note based on HC personality.
    private var coordinatorNote: String {
        switch coach.personality {
        case .teamLeader:
            return "Pair with strong-willed coordinators who bring tactical depth"
        case .quietProfessional:
            return "Pair with creative coordinators who can execute complex schemes"
        case .fieryCompetitor:
            return "Pair with calm, detail-oriented coordinators for balance"
        case .mentor:
            return "Pair with disciplined coordinators to balance player freedom"
        case .steadyPerformer:
            return "Pair with innovative coordinators who push boundaries"
        case .feelPlayer:
            return "Pair with experienced coordinators who can ground bold ideas"
        case .loneWolf:
            return "Pair with collaborative coordinators who bridge communication gaps"
        case .dramaQueen:
            return "Pair with steady, low-drama coordinators for stability"
        case .classClown:
            return "Pair with structured coordinators to complement loose leadership"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                // HC badge -- larger
                Text("HC")
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(coach.fullName)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 6) {
                        Text("Age \(coach.age)")
                        Text("\u{00B7}")
                        Text("\(coach.yearsExperience) yr\(coach.yearsExperience == 1 ? "" : "s") exp")
                        if let scheme = schemeText {
                            Text("\u{00B7}")
                            Text(scheme)
                                .foregroundStyle(Color.accentBlue)
                        }
                        Text("\u{00B7}")
                        Text("$\(coach.salary)K/yr")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)

                    // Fix #36: Coaching style bonus
                    HStack(spacing: 4) {
                        Text("+\(topAttribute.value) \(topAttribute.name)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.success)
                        Text("\u{00B7}")
                            .foregroundStyle(Color.textTertiary)
                        Text(coach.personality.displayName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentBlue)
                    }
                }

                Spacer()

                // Play calling rating -- larger
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(coach.playCalling)")
                        .font(.system(size: 24, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color.forRating(coach.playCalling))
                    Text("Play Calling")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Role description
            Text("Sets the team's vision, manages coordinators, and makes key game-day decisions")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)

            // Fix #36: Coordinator complement note
            HStack(spacing: 4) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 9))
                Text(coordinatorNote)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(Color.accentGold.opacity(0.8))

            // Coaching Tree badge
            if menteeCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 9))
                    Text("Coaching Tree: \(menteeCount)")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Color.accentBlue)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(coach.fullName), Head Coach, age \(coach.age), Play Calling \(coach.playCalling)")
    }
}

// MARK: - Coach Row with Description

private struct CoachRowWithDescriptionView: View {
    let coach: Coach

    private var keyAttribute: (name: String, value: Int) {
        switch coach.role {
        case .headCoach, .assistantHeadCoach, .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
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

    /// The coach's primary strength -- highest attribute name.
    private var primaryStrength: String {
        let attributes: [(String, Int)] = [
            ("Play Calling", coach.playCalling),
            ("Player Dev", coach.playerDevelopment),
            ("Reputation", coach.reputation),
            ("Adaptability", coach.adaptability),
            ("Game Planning", coach.gamePlanning),
            ("Scouting", coach.scoutingAbility),
            ("Recruiting", coach.recruiting),
            ("Motivation", coach.motivation),
            ("Discipline", coach.discipline),
            ("Media", coach.mediaHandling),
            ("Negotiation", coach.contractNegotiation),
            ("Morale", coach.moraleInfluence)
        ]
        return attributes.max(by: { $0.1 < $1.1 })?.0 ?? "Play Calling"
    }

    /// Average of all coach attributes, used for mini star rating.
    private var averageAttribute: Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.reputation +
                  coach.adaptability + coach.gamePlanning + coach.scoutingAbility +
                  coach.recruiting + coach.motivation + coach.discipline +
                  coach.mediaHandling + coach.contractNegotiation + coach.moraleInfluence
        return sum / 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                        Text("\u{00B7}")
                        Text("\(coach.yearsExperience) yr\(coach.yearsExperience == 1 ? "" : "s") exp")
                        if let scheme = schemeText {
                            Text("\u{00B7}")
                            Text(scheme)
                                .foregroundStyle(Color.accentBlue)
                        }
                        Text("\u{00B7}")
                        Text("$\(coach.salary)K/yr")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.textSecondary)

                    // Mini star rating + primary strength
                    HStack(spacing: 6) {
                        Text(CoachingEngine.starString(for: averageAttribute))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentGold)
                        Text(primaryStrength)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }
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

            // Role description
            Text(coach.role.roleDescription)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(coach.fullName), \(coach.role.displayName), age \(coach.age), \(keyAttribute.name) \(keyAttribute.value)")
    }
}

// MARK: - Coach Row View

private struct CoachRowView: View {
    let coach: Coach

    /// The key attribute to surface depends on role tier.
    private var keyAttribute: (name: String, value: Int) {
        switch coach.role {
        case .headCoach, .assistantHeadCoach, .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator:
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
                    Text("\u{00B7}")
                    Text("\(coach.yearsExperience) yr\(coach.yearsExperience == 1 ? "" : "s") exp")
                    if let scheme = schemeText {
                        Text("\u{00B7}")
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
        case .assistantHeadCoach:      return "Assistant Head Coach"
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
        case .teamDoctor:              return "Team Doctor"
        case .physio:                  return "Physiotherapist"
        }
    }

    var abbreviation: String {
        switch self {
        case .headCoach:               return "HC"
        case .assistantHeadCoach:      return "AHC"
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
        case .teamDoctor:              return "DOC"
        case .physio:                  return "PHY"
        }
    }

    var sortOrder: Int {
        switch self {
        case .headCoach:               return 0
        case .assistantHeadCoach:      return 1
        case .offensiveCoordinator:    return 2
        case .defensiveCoordinator:    return 3
        case .specialTeamsCoordinator: return 4
        case .qbCoach:                 return 5
        case .rbCoach:                 return 6
        case .wrCoach:                 return 7
        case .olCoach:                 return 8
        case .dlCoach:                 return 9
        case .lbCoach:                 return 10
        case .dbCoach:                 return 11
        case .strengthCoach:           return 12
        case .teamDoctor:              return 13
        case .physio:                  return 14
        }
    }

    var roleDescription: String {
        switch self {
        case .headCoach:               return "Sets the team's vision, manages coordinators, and makes key game-day decisions"
        case .assistantHeadCoach:      return "Supports the HC, bridges communication between coordinators, and fills in on game day"
        case .offensiveCoordinator:    return "Manages the offense and calls plays"
        case .defensiveCoordinator:    return "Manages the defense and calls coverage schemes"
        case .specialTeamsCoordinator: return "Oversees kicking, punting, and return units"
        case .qbCoach:                 return "Develops quarterbacks and refines passing mechanics"
        case .rbCoach:                 return "Develops running backs and blocking technique"
        case .wrCoach:                 return "Develops receivers and route running"
        case .olCoach:                 return "Develops offensive linemen and pass protection"
        case .dlCoach:                 return "Develops defensive linemen and pass rush technique"
        case .lbCoach:                 return "Develops linebackers and run-fit assignments"
        case .dbCoach:                 return "Develops defensive backs and coverage skills"
        case .strengthCoach:           return "Manages conditioning, injury prevention, and recovery"
        case .teamDoctor:              return "Reduces injury risk and speeds diagnosis for faster return to play"
        case .physio:                  return "Speeds injury recovery and improves weekly fatigue management"
        }
    }

    var badgeColor: Color {
        switch self {
        case .headCoach:               return .accentGold
        case .assistantHeadCoach:      return .accentGold.opacity(0.7)
        case .offensiveCoordinator:    return .accentBlue
        case .defensiveCoordinator:    return .danger
        case .specialTeamsCoordinator: return .success
        case .teamDoctor, .physio:     return .accentBlue.opacity(0.7)
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
    .modelContainer(for: [Career.self, Coach.self, Scout.self, Owner.self, Player.self], inMemory: true)
}
