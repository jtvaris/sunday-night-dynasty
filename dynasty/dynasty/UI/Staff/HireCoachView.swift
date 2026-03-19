import SwiftUI
import SwiftData

struct HireCoachView: View {

    let role: CoachRole
    let teamID: UUID
    let remainingBudget: Int
    var onHired: ((String, String) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allCoaches: [Coach]

    @State private var candidates: [Coach] = []
    @State private var hiredCoachID: UUID?
    @State private var sortColumn: SortColumn = .ovr
    @State private var sortAscending: Bool = false
    @State private var selectedCandidate: Coach?
    @State private var showAffordableOnly: Bool = false

    /// The team's head coach, used to determine current team scheme for fit indicator.
    private var teamHeadCoach: Coach? {
        allCoaches.first { $0.teamID == teamID && $0.role == .headCoach }
    }

    // MARK: - Sort Column

    enum SortColumn: String, CaseIterable {
        case name    = "Name"
        case age     = "Age"
        case scheme  = "Scheme"
        case ovr     = "OVR"
        case play    = "Play"
        case dev     = "Dev"
        case game    = "Game"
        case salary  = "Salary"
    }

    // MARK: - Helpers

    private func coachOverall(_ coach: Coach) -> Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

    // MARK: - Filtered & Sorted Candidates

    private var filteredCandidates: [Coach] {
        if showAffordableOnly {
            return candidates.filter { $0.salary <= remainingBudget }
        }
        return candidates
    }

    private var sortedCandidates: [Coach] {
        let list = filteredCandidates
        let sorted: [Coach]
        switch sortColumn {
        case .name:    sorted = list.sorted { $0.lastName < $1.lastName }
        case .age:     sorted = list.sorted { $0.age < $1.age }
        case .scheme:  sorted = list.sorted { schemeLabel($0) < schemeLabel($1) }
        case .ovr:     sorted = list.sorted { coachOverall($0) > coachOverall($1) }
        case .play:    sorted = list.sorted { $0.playCalling > $1.playCalling }
        case .dev:     sorted = list.sorted { $0.playerDevelopment > $1.playerDevelopment }
        case .game:    sorted = list.sorted { $0.gamePlanning > $1.gamePlanning }
        case .salary:  sorted = list.sorted { $0.salary < $1.salary }
        }
        return sortAscending ? sorted.reversed() : sorted
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            GeometryReader { geo in
                Image("BgCoachStadium1")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.15)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [Color.backgroundPrimary.opacity(0.85), Color.backgroundPrimary.opacity(0.5), Color.backgroundPrimary.opacity(0.85)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Sticky budget header + filter
                budgetHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.backgroundSecondary)

                Divider().overlay(Color.surfaceBorder)

                // Sticky column headers
                tableHeaderRow
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.backgroundTertiary.opacity(0.6))

                Divider().overlay(Color.surfaceBorder)

                // Candidate rows
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedCandidates) { candidate in
                            candidateRow(candidate)

                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.4))
                                .padding(.horizontal, 12)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Hire \(role.displayName)")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if candidates.isEmpty {
                let count = Int.random(in: 20...30)
                candidates = CoachingEngine.generateCoachCandidates(role: role, count: count)
            }
        }
        .sheet(item: $selectedCandidate) { candidate in
            CandidateDetailSheet(
                candidate: candidate,
                remainingBudget: remainingBudget,
                isHired: hiredCoachID == candidate.id,
                onHire: { hire(candidate) }
            )
            // Fix #86: Make candidate profile sheet larger on iPad
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Budget Header

    private var budgetHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Budget Remaining")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                Text("$\(formatBudget(remainingBudget))M")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(remainingBudget > 0 ? Color.success : Color.danger)
            }
            Spacer()

            // Fix #39: Affordable-only toggle
            Toggle(isOn: $showAffordableOnly) {
                Text("Affordable")
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(Color.accentGold)
            .fixedSize()

            Spacer().frame(width: 16)

            Text("\(filteredCandidates.count) candidates")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Table Header (Fix #42: simplified columns — OVR + numeric skills)

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            headerButton("Name", column: .name, width: nil, alignment: .leading)
            headerButton("Age", column: .age, width: 34)
            headerButton("Scheme", column: .scheme, width: 62)
            // Fix #38: Scheme fit column header
            if teamHeadCoach != nil {
                Text("Fit")
                    .frame(width: 32)
            }
            headerButton("OVR", column: .ovr, width: 36)
            headerButton("Play", column: .play, width: 36)
            headerButton("Dev", column: .dev, width: 36)
            headerButton("Game", column: .game, width: 36)
            headerButton("Salary", column: .salary, width: 56)
            // Status column
            Text("")
                .frame(width: 30)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(Color.textTertiary)
    }

    private func headerButton(_ title: String, column: SortColumn, width: CGFloat?, alignment: Alignment = .center) -> some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = false
            }
        } label: {
            HStack(spacing: 2) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7))
                }
            }
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width)
        }
        .foregroundStyle(sortColumn == column ? Color.accentGold : Color.textTertiary)
    }

    // MARK: - Candidate Row (Fix #42: one star rating + numeric skill values)

    private func candidateRow(_ candidate: Coach) -> some View {
        let isOverBudget = candidate.salary > remainingBudget
        let isHired = hiredCoachID == candidate.id
        let ovr = coachOverall(candidate)

        return Button {
            selectedCandidate = candidate
        } label: {
            HStack(spacing: 0) {
                // Name
                VStack(alignment: .leading, spacing: 1) {
                    Text(candidate.fullName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isOverBudget ? Color.textTertiary : Color.textPrimary)
                        .lineLimit(1)
                    // One overall star rating
                    Text(CoachingEngine.starString(for: ovr))
                        .font(.system(size: 9))
                        .foregroundStyle(Color.accentGold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Age
                Text("\(candidate.age)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 34)

                // Scheme
                Text(schemeLabel(candidate))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.accentBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: 62)

                // Fix #38: Scheme fit indicator
                if teamHeadCoach != nil {
                    Group {
                        if let fit = schemeFit(for: candidate) {
                            Circle()
                                .fill(fit.color)
                                .frame(width: 8, height: 8)
                                .overlay(
                                    Circle()
                                        .strokeBorder(fit.color.opacity(0.5), lineWidth: 1)
                                )
                                .accessibilityLabel("Scheme fit: \(fit.label)")
                        } else {
                            Text("--")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    .frame(width: 32)
                }

                // OVR numeric
                Text("\(ovr)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.forRating(ovr))
                    .frame(width: 36)

                // Key skill numerics
                Text("\(candidate.playCalling)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.forRating(candidate.playCalling))
                    .frame(width: 36)

                Text("\(candidate.playerDevelopment)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.forRating(candidate.playerDevelopment))
                    .frame(width: 36)

                Text("\(candidate.gamePlanning)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.forRating(candidate.gamePlanning))
                    .frame(width: 36)

                // Salary
                Text(salaryFormatted(candidate.salary))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isOverBudget ? Color.danger : Color.textSecondary)
                    .frame(width: 56)

                // Status indicator
                Group {
                    if isHired {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.success)
                    } else if isOverBudget {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.danger.opacity(0.5))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .frame(width: 30)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isOverBudget ? 0.6 : 1.0)
        .background(isHired ? Color.success.opacity(0.06) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.fullName), age \(candidate.age), overall \(ovr), salary \(candidate.salary) thousand")
    }

    // MARK: - Helpers

    private func schemeLabel(_ coach: Coach) -> String {
        if let o = coach.offensiveScheme { return o.displayName }
        if let d = coach.defensiveScheme { return d.displayName }
        return "--"
    }

    // MARK: - Scheme Fit (Fix #38)

    /// Determines how well a candidate's scheme fits the team's current scheme (via HC).
    /// Returns (color, label) for the fit indicator.
    private func schemeFit(for candidate: Coach) -> (color: Color, label: String)? {
        guard let hc = teamHeadCoach else { return nil }

        // Compare offensive schemes
        if let candidateOff = candidate.offensiveScheme {
            if let hcOff = hc.offensiveScheme {
                if candidateOff == hcOff {
                    return (.success, "Great")
                }
                // Similar scheme families
                let passingSchemes: Set<OffensiveScheme> = [.westCoast, .airRaid, .proPassing, .spread]
                let runSchemes: Set<OffensiveScheme> = [.powerRun, .shanahan, .option, .rpo]
                if (passingSchemes.contains(candidateOff) && passingSchemes.contains(hcOff))
                    || (runSchemes.contains(candidateOff) && runSchemes.contains(hcOff)) {
                    return (.warning, "OK")
                }
                return (.danger, "Poor")
            }
            return nil // HC has no offensive scheme set
        }

        // Compare defensive schemes
        if let candidateDef = candidate.defensiveScheme {
            if let hcDef = hc.defensiveScheme {
                if candidateDef == hcDef {
                    return (.success, "Great")
                }
                // Similar scheme families
                let frontSchemes: Set<DefensiveScheme> = [.base34, .base43]
                let coverageSchemes: Set<DefensiveScheme> = [.cover3, .tampa2, .pressMan]
                let flexSchemes: Set<DefensiveScheme> = [.multiple, .hybrid]
                if (frontSchemes.contains(candidateDef) && frontSchemes.contains(hcDef))
                    || (coverageSchemes.contains(candidateDef) && coverageSchemes.contains(hcDef))
                    || (flexSchemes.contains(candidateDef) && flexSchemes.contains(hcDef)) {
                    return (.warning, "OK")
                }
                return (.danger, "Poor")
            }
            return nil // HC has no defensive scheme set
        }

        return nil
    }

    private func salaryFormatted(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "$%.1fM", millions)
    }

    private func formatBudget(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "%.1f", millions)
    }

    // MARK: - Hire Action

    private func hire(_ candidate: Coach) {
        guard candidate.salary <= remainingBudget else { return }

        let descriptor = FetchDescriptor<Coach>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        if let existing = try? modelContext.fetch(descriptor) {
            existing.filter { $0.role == role }.forEach { modelContext.delete($0) }
        }

        candidate.teamID = teamID
        modelContext.insert(candidate)
        hiredCoachID = candidate.id

        // Fix #88: Save context before dismissing so CoachingStaffView's @Query refreshes
        try? modelContext.save()

        // Fix #49: Notify parent about the hire for toast display
        let hiredName = candidate.fullName
        let hiredRole = role.displayName

        // Fix #87: Dismiss sheet first, then pop HireCoachView after sheet animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            selectedCandidate = nil  // Close the sheet
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onHired?(hiredName, hiredRole)
                dismiss()
            }
        }
    }
}

// MARK: - Candidate Detail / Negotiation Sheet

private struct CandidateDetailSheet: View {
    let candidate: Coach
    let remainingBudget: Int
    let isHired: Bool
    let onHire: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var proposedSalary: Double
    @State private var proposedYears: Int = 3
    @State private var negotiationResult: NegotiationResult?

    init(candidate: Coach, remainingBudget: Int, isHired: Bool, onHire: @escaping () -> Void) {
        self.candidate = candidate
        self.remainingBudget = remainingBudget
        self.isHired = isHired
        self.onHire = onHire
        self._proposedSalary = State(initialValue: Double(candidate.salary))
    }

    private var askingSalary: Double { Double(candidate.salary) }

    /// Chance the candidate rejects a below-asking offer (0.0 - 1.0).
    private var rejectionChance: Double {
        guard proposedSalary < askingSalary else { return 0.0 }
        let discount = (askingSalary - proposedSalary) / askingSalary
        // Up to 90% rejection at 50%+ discount
        return min(0.9, discount * 1.8)
    }

    private var isOverBudget: Bool {
        Int(proposedSalary) > remainingBudget
    }

    private func coachOverall(_ coach: Coach) -> Int {
        let sum = coach.playCalling + coach.playerDevelopment + coach.gamePlanning
            + coach.scoutingAbility + coach.recruiting + coach.motivation
            + coach.discipline + coach.adaptability + coach.mediaHandling
            + coach.contractNegotiation + coach.moraleInfluence + coach.reputation
        return sum / 12
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Profile header
                        profileHeader

                        // Fix #43: Prominent hire button at top of sheet
                        if !isHired && negotiationResult?.accepted != true {
                            quickHireButton
                        }

                        if isHired || negotiationResult?.accepted == true {
                            hiredBanner
                        }

                        // All attributes (Fix #47: use VStack instead of LazyVGrid)
                        attributesCard

                        // Background story
                        if !candidate.background.isEmpty {
                            backgroundCard
                        }

                        // Chemistry preview
                        chemistryCard

                        // Negotiation section
                        negotiationCard

                        Spacer(minLength: 20)
                    }
                    .padding(20)
                    .frame(maxWidth: 720)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Candidate Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 12) {
            // Name + role badge
            HStack(spacing: 10) {
                Text(candidate.role.abbreviation)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(candidate.role.badgeColor, in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.fullName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    HStack(spacing: 8) {
                        Text("Age \(candidate.age)")
                        Text("\u{00B7}")
                        Text("\(candidate.yearsExperience) yrs experience")
                        Text("\u{00B7}")
                        Text(candidate.personality.displayName)
                            .foregroundStyle(Color.accentBlue)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Overall rating + scheme + salary summary
            HStack(spacing: 12) {
                // Overall badge
                let ovr = coachOverall(candidate)
                VStack(spacing: 2) {
                    Text("\(ovr)")
                        .font(.system(size: 22, weight: .black).monospacedDigit())
                        .foregroundStyle(Color.forRating(ovr))
                    Text("OVR")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(width: 48, height: 48)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))

                if let off = candidate.offensiveScheme {
                    schemeTag(off.displayName, color: .accentBlue)
                }
                if let def = candidate.defensiveScheme {
                    schemeTag(def.displayName, color: .danger)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Asking Salary")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Text(salaryFormatted(candidate.salary))
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Quick Hire Button (Fix #43: prominent gold button at top)

    private var quickHireButton: some View {
        Button {
            // Use asking salary directly for quick hire
            proposedSalary = askingSalary
            proposedYears = 3
            makeOffer()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "handshake.fill")
                    .font(.system(size: 16, weight: .semibold))
                VStack(spacing: 2) {
                    Text("Offer Contract")
                        .font(.headline.weight(.bold))
                    Text("at asking salary \(salaryFormatted(candidate.salary))/yr")
                        .font(.caption2)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(candidate.salary > remainingBudget ? Color.backgroundTertiary : Color.accentGold)
            )
        }
        .disabled(candidate.salary > remainingBudget)
        .buttonStyle(.plain)
    }

    // MARK: - Hired Banner

    private var hiredBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.success)
            Text("Hired!")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.success)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.success.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.success.opacity(0.3), lineWidth: 1)
                )
        )
    }

    // MARK: - Attributes Card (Fix #47: VStack grid instead of LazyVGrid to prevent disappearing)

    private var attributesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ATTRIBUTES")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            let attrs: [(String, Int)] = [
                ("Play Calling", candidate.playCalling),
                ("Player Dev", candidate.playerDevelopment),
                ("Game Planning", candidate.gamePlanning),
                ("Scouting", candidate.scoutingAbility),
                ("Recruiting", candidate.recruiting),
                ("Motivation", candidate.motivation),
                ("Discipline", candidate.discipline),
                ("Adaptability", candidate.adaptability),
                ("Media", candidate.mediaHandling),
                ("Contract Neg.", candidate.contractNegotiation),
                ("Morale", candidate.moraleInfluence),
                ("Reputation", candidate.reputation),
            ]

            // Fix #47: Use plain VStack with manual two-column rows instead of LazyVGrid.
            VStack(spacing: 8) {
                ForEach(0..<(attrs.count / 2), id: \.self) { rowIndex in
                    let left = attrs[rowIndex * 2]
                    let right = attrs[rowIndex * 2 + 1]
                    HStack(spacing: 8) {
                        attributeCell(name: left.0, value: left.1)
                        attributeCell(name: right.0, value: right.1)
                    }
                }
            }
        }
        .padding(16)
        .cardBackground()
    }

    private func attributeCell(name: String, value: Int) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text("\(value)")
                .font(.system(size: 16, weight: .bold).monospacedDigit())
                .foregroundStyle(Color.forRating(value))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.backgroundTertiary.opacity(0.5))
        )
    }

    // MARK: - Background Card

    private var backgroundCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BACKGROUND")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            Text(candidate.background)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Chemistry Card

    private var chemistryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STAFF CHEMISTRY")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            Text("How this candidate fits with the existing coaching staff personality dynamics.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)

            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.accentBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Personality: \(candidate.personality.displayName)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textPrimary)
                    Text("Chemistry is evaluated against your head coach after hiring.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    // MARK: - Negotiation Card

    private var negotiationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("NEGOTIATE")
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(Color.accentGold)

            // Proposed salary slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Proposed Salary")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(salaryFormatted(Int(proposedSalary)))
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(isOverBudget ? Color.danger : Color.accentGold)
                }

                let minSalary = max(100, Double(candidate.salary) * 0.5)
                let maxSalary = Double(candidate.salary) * 1.3
                Slider(value: $proposedSalary, in: minSalary...maxSalary, step: 50)
                    .tint(Color.accentGold)

                HStack {
                    Text(salaryFormatted(Int(minSalary)))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text("Asking: \(salaryFormatted(candidate.salary))")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Text(salaryFormatted(Int(maxSalary)))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Contract years
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Contract Length")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text("\(proposedYears) year\(proposedYears == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                }
                Stepper("Years", value: $proposedYears, in: 1...5)
                    .labelsHidden()
            }

            // Rejection warning
            if rejectionChance > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(rejectionChance > 0.5 ? Color.danger : Color.warning)
                    Text("Rejection risk: \(Int(rejectionChance * 100))%")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(rejectionChance > 0.5 ? Color.danger : Color.warning)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill((rejectionChance > 0.5 ? Color.danger : Color.warning).opacity(0.1))
                )
            }

            if isOverBudget {
                HStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle.fill")
                        .foregroundStyle(Color.danger)
                    Text("Over budget")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.danger)
                }
            }

            // Negotiation result
            if let result = negotiationResult {
                HStack(spacing: 10) {
                    Image(systemName: result.accepted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(result.accepted ? Color.success : Color.danger)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.accepted ? "Offer Accepted!" : "Offer Rejected")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(result.accepted ? Color.success : Color.danger)
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill((result.accepted ? Color.success : Color.danger).opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder((result.accepted ? Color.success : Color.danger).opacity(0.3), lineWidth: 1)
                        )
                )
            }

            // Make Offer button (Fix #43: large gold button)
            if !isHired && negotiationResult?.accepted != true {
                Button {
                    makeOffer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "handshake.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Offer Contract")
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isOverBudget ? Color.backgroundTertiary : Color.accentGold)
                    )
                }
                .disabled(isOverBudget)
                .buttonStyle(.plain)
            }

            if isHired || negotiationResult?.accepted == true {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.success)
                    Text("Hired!")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(Color.success)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .cardBackground()
    }

    // MARK: - Offer Logic

    private func makeOffer() {
        let roll = Double.random(in: 0...1)
        let accepted = roll >= rejectionChance

        if accepted {
            negotiationResult = NegotiationResult(
                accepted: true,
                message: proposedSalary < askingSalary
                    ? "\(candidate.firstName) accepted your below-market offer of \(salaryFormatted(Int(proposedSalary)))/yr for \(proposedYears) years."
                    : "\(candidate.firstName) is pleased with the offer of \(salaryFormatted(Int(proposedSalary)))/yr for \(proposedYears) years."
            )
            // Update salary to negotiated amount before hiring
            candidate.salary = Int(proposedSalary)
            onHire()
        } else {
            negotiationResult = NegotiationResult(
                accepted: false,
                message: "\(candidate.firstName) turned down your offer. They feel \(salaryFormatted(candidate.salary)) is fair compensation. You can adjust your offer and try again."
            )
        }
    }

    // MARK: - Helpers

    private func salaryFormatted(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "$%.1fM", millions)
    }

    private func schemeTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Negotiation Result

private struct NegotiationResult {
    let accepted: Bool
    let message: String
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HireCoachView(role: .offensiveCoordinator, teamID: UUID(), remainingBudget: 15_000)
    }
    .modelContainer(for: Coach.self, inMemory: true)
}
