import SwiftUI
import SwiftData

struct CoachingStaffView: View {

    let career: Career
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var allCoaches: [Coach]
    @Query private var allScouts: [Scout]
    @Query private var allOwners: [Owner]

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

    /// The team's owner (for budget info).
    private var owner: Owner? {
        // Owner is stored on Team; find via allOwners matching our team
        // For now, use the first owner (single-team career)
        allOwners.first
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

    /// Whether the device is in iPad portrait (regular width) for 2-column layout.
    private var isIPadPortrait: Bool {
        horizontalSizeClass == .regular
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
        default:              return nil
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
            Image("BgLockerRoom2")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .opacity(0.12)
                .overlay(
                    LinearGradient(
                        colors: [Color.backgroundPrimary.opacity(0.6), Color.clear, Color.backgroundPrimary.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )

            List {
                // MARK: - Budget Header
                Section {
                    budgetHeaderView
                } header: {
                    Text("Staff Budget")
                }
                .listRowBackground(Color.backgroundSecondary)

                // Head Coach -- prominent card
                Section {
                    if career.role == .gmAndHeadCoach {
                        // Player IS the HC — show "You" card
                        playerAsHeadCoachRow
                    } else if let hc = headCoach {
                        NavigationLink {
                            CoachDetailView(coach: hc)
                        } label: {
                            HeadCoachCardView(coach: hc)
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

                if isIPadPortrait {
                    // MARK: - 2-Column Layout (iPad Portrait)
                    Section {
                        HStack(alignment: .top, spacing: 16) {
                            // Left column: Coordinators
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    Text("2")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(Color.backgroundPrimary)
                                        .frame(width: 18, height: 18)
                                        .background(Circle().fill(Color.accentGold))
                                    Text("Coordinators")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.textSecondary)
                                }
                                .padding(.bottom, 8)

                                let coordRoles: [CoachRole] = [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator]
                                ForEach(coordRoles, id: \.self) { role in
                                    if let coach = coaches.first(where: { $0.role == role }) {
                                        coachRowWithChemistry(coach: coach)
                                        Divider().padding(.vertical, 4)
                                    } else {
                                        vacantRow(role: role)
                                        Divider().padding(.vertical, 4)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)

                            Divider()

                            // Right column: Position Coaches
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(spacing: 6) {
                                    Text("3")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(Color.backgroundPrimary)
                                        .frame(width: 18, height: 18)
                                        .background(Circle().fill(Color.accentGold))
                                    Text("Position Coaches")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.textSecondary)
                                }
                                .padding(.bottom, 8)

                                let posRoles: [CoachRole] = [.qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach]
                                ForEach(posRoles, id: \.self) { role in
                                    if let coach = coaches.first(where: { $0.role == role }) {
                                        NavigationLink {
                                            CoachDetailView(coach: coach)
                                        } label: {
                                            CoachRowWithDescriptionView(coach: coach)
                                        }
                                        Divider().padding(.vertical, 4)
                                    } else {
                                        vacantRow(role: role)
                                        Divider().padding(.vertical, 4)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } header: {
                        Text("Coaching Staff")
                    }
                    .listRowBackground(Color.backgroundSecondary)
                } else {
                    // MARK: - Single-Column Layout (Compact)
                    // Coordinators
                    Section {
                        let coordRoles: [CoachRole] = [.offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator]
                        ForEach(Array(coordRoles.enumerated()), id: \.element) { _, role in
                            if let coach = coaches.first(where: { $0.role == role }) {
                                coachRowWithChemistry(coach: coach)
                            } else {
                                vacantRow(role: role)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text("2")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Color.backgroundPrimary)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.accentGold))
                            Text("Coordinators")
                        }
                    }
                    .listRowBackground(Color.backgroundSecondary)

                    // Position Coaches
                    Section {
                        let posRoles: [CoachRole] = [.qbCoach, .rbCoach, .wrCoach, .olCoach, .dlCoach, .lbCoach, .dbCoach, .strengthCoach]
                        ForEach(posRoles, id: \.self) { role in
                            if let coach = coaches.first(where: { $0.role == role }) {
                                NavigationLink {
                                    CoachDetailView(coach: coach)
                                } label: {
                                    CoachRowWithDescriptionView(coach: coach)
                                }
                            } else {
                                vacantRow(role: role)
                            }
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text("3")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(Color.backgroundPrimary)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.accentGold))
                            Text("Position Coaches")
                        }
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }

                // MARK: - Scouting Department
                Section {
                    // Chief Scout
                    if let chief = chiefScout {
                        scoutRow(scout: chief)
                    } else {
                        scoutVacantRow(role: .chiefScout)
                    }

                    // Regional Scouts (5 slots)
                    let regionalRoles: [ScoutRole] = [.regionalScout1, .regionalScout2, .regionalScout3, .regionalScout4, .regionalScout5]
                    ForEach(regionalRoles, id: \.self) { role in
                        if let scout = scouts.first(where: { $0.scoutRole == role }) {
                            scoutRow(scout: scout)
                        } else {
                            scoutVacantRow(role: role)
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("4")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Color.backgroundPrimary)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(Color.accentGold))
                        Text("Scouting Department")
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

    // MARK: - Budget Header

    @ViewBuilder
    private var budgetHeaderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Coaching Budget")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                    Text("$\(formatBudget(totalStaffSalaryUsed))M / $\(formatBudget(coachingBudget))M used")
                        .font(.caption)
                        .foregroundStyle(remainingBudget >= 0 ? Color.textSecondary : Color.danger)
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
        NavigationLink {
            CoachDetailView(coach: coach)
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
        if let teamID = career.teamID {
            NavigationLink {
                HireCoachView(role: .headCoach, teamID: teamID, remainingBudget: remainingBudget)
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
    }

    // MARK: - Vacant row

    @ViewBuilder
    private func vacantRow(role: CoachRole) -> some View {
        if let teamID = career.teamID {
            NavigationLink {
                HireCoachView(role: role, teamID: teamID, remainingBudget: remainingBudget)
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
                    }
                    Spacer()
                    Image(systemName: "plus.circle")
                        .foregroundStyle(Color.accentGold)
                }
                .padding(.vertical, 4)
            }
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
        if let teamID = career.teamID {
            NavigationLink {
                HireScoutView(scoutRole: role, teamID: teamID, remainingBudget: remainingBudget)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(role.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textTertiary)
                        Text("Vacant \u{2014} Tap to hire")
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

// MARK: - Head Coach Card (Prominent)

private struct HeadCoachCardView: View {
    let coach: Coach

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
        }
    }

    var badgeColor: Color {
        switch self {
        case .headCoach:               return .accentGold
        case .assistantHeadCoach:      return .accentGold.opacity(0.7)
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
    .modelContainer(for: [Career.self, Coach.self, Scout.self, Owner.self], inMemory: true)
}
