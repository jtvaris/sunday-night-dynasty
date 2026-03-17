import SwiftUI
import SwiftData

struct HireCoachView: View {

    let role: CoachRole
    let teamID: UUID
    let remainingBudget: Int

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [Coach] = []
    @State private var hiredCoachID: UUID?
    @State private var sortColumn: SortColumn = .reputation
    @State private var sortAscending: Bool = false
    @State private var selectedCandidate: Coach?

    // MARK: - Sort Column

    enum SortColumn: String, CaseIterable {
        case name       = "Name"
        case age        = "Age"
        case experience = "Exp"
        case scheme     = "Scheme"
        case play       = "Play"
        case dev        = "Dev"
        case game       = "Game"
        case scout      = "Scout"
        case recruit    = "Recruit"
        case salary     = "Salary"
        case reputation = "Rep"
    }

    // MARK: - Sorted Candidates

    private var sortedCandidates: [Coach] {
        let sorted: [Coach]
        switch sortColumn {
        case .name:       sorted = candidates.sorted { $0.lastName < $1.lastName }
        case .age:        sorted = candidates.sorted { $0.age < $1.age }
        case .experience: sorted = candidates.sorted { $0.yearsExperience > $1.yearsExperience }
        case .scheme:     sorted = candidates.sorted { schemeLabel($0) < schemeLabel($1) }
        case .play:       sorted = candidates.sorted { $0.playCalling > $1.playCalling }
        case .dev:        sorted = candidates.sorted { $0.playerDevelopment > $1.playerDevelopment }
        case .game:       sorted = candidates.sorted { $0.gamePlanning > $1.gamePlanning }
        case .scout:      sorted = candidates.sorted { $0.scoutingAbility > $1.scoutingAbility }
        case .recruit:    sorted = candidates.sorted { $0.recruiting > $1.recruiting }
        case .salary:     sorted = candidates.sorted { $0.salary < $1.salary }
        case .reputation: sorted = candidates.sorted { $0.reputation > $1.reputation }
        }
        return sortAscending ? sorted.reversed() : sorted
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                budgetHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.backgroundSecondary)

                Divider().overlay(Color.surfaceBorder)

                // Table header
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
            Text("\(candidates.count) candidates")
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Table Header

    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            headerButton("Name", column: .name, width: nil, alignment: .leading)
            headerButton("Age", column: .age, width: 34)
            headerButton("Exp", column: .experience, width: 34)
            headerButton("Scheme", column: .scheme, width: 62)
            starHeader("Play", column: .play)
            starHeader("Dev", column: .dev)
            starHeader("Game", column: .game)
            starHeader("Scout", column: .scout)
            starHeader("Recr", column: .recruit)
            headerButton("Salary", column: .salary, width: 56)
            // Action column
            Text("")
                .frame(width: 80)
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

    private func starHeader(_ title: String, column: SortColumn) -> some View {
        headerButton(title, column: column, width: 42)
    }

    // MARK: - Candidate Row

    private func candidateRow(_ candidate: Coach) -> some View {
        let isOverBudget = candidate.salary > remainingBudget
        let isHired = hiredCoachID == candidate.id

        return HStack(spacing: 0) {
            // Name
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.fullName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOverBudget ? Color.textTertiary : Color.textPrimary)
                    .lineLimit(1)
                Text(candidate.personality.displayName)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Age
            Text("\(candidate.age)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
                .frame(width: 34)

            // Experience
            Text("\(candidate.yearsExperience)")
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

            // Star ratings
            starCell(candidate.playCalling, width: 42)
            starCell(candidate.playerDevelopment, width: 42)
            starCell(candidate.gamePlanning, width: 42)
            starCell(candidate.scoutingAbility, width: 42)
            starCell(candidate.recruiting, width: 42)

            // Salary
            Text(salaryFormatted(candidate.salary))
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(isOverBudget ? Color.danger : Color.textSecondary)
                .frame(width: 56)

            // Action buttons
            HStack(spacing: 4) {
                Button {
                    selectedCandidate = candidate
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.accentBlue)
                }
                .buttonStyle(.plain)

                if isHired {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.success)
                } else if isOverBudget {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.danger.opacity(0.5))
                } else {
                    Button {
                        hire(candidate)
                    } label: {
                        Text("Hire")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(width: 80)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .opacity(isOverBudget ? 0.6 : 1.0)
        .background(isHired ? Color.success.opacity(0.06) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.fullName), age \(candidate.age), salary \(candidate.salary) thousand")
    }

    // MARK: - Star Cell

    private func starCell(_ value: Int, width: CGFloat) -> some View {
        Text(CoachingEngine.starString(for: value))
            .font(.system(size: 9))
            .foregroundStyle(Color.accentGold)
            .frame(width: width)
    }

    // MARK: - Helpers

    private func schemeLabel(_ coach: Coach) -> String {
        if let o = coach.offensiveScheme { return o.displayName }
        if let d = coach.defensiveScheme { return d.displayName }
        return "--"
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            dismiss()
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

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Profile header
                        profileHeader

                        // All attributes with star ratings and numeric values
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

            // Scheme + salary summary
            HStack(spacing: 12) {
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

    // MARK: - Attributes Card

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

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 8) {
                ForEach(attrs, id: \.0) { attr in
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attr.0)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.textSecondary)
                            Text(CoachingEngine.starString(for: attr.1))
                                .font(.system(size: 10))
                                .foregroundStyle(Color.accentGold)
                        }
                        Spacer()
                        Text("\(attr.1)")
                            .font(.system(size: 16, weight: .bold).monospacedDigit())
                            .foregroundStyle(Color.forRating(attr.1))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.backgroundTertiary.opacity(0.5))
                    )
                }
            }
        }
        .padding(16)
        .cardBackground()
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

            // Make Offer button
            if !isHired && negotiationResult?.accepted != true {
                Button {
                    makeOffer()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "handshake.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Make Offer")
                            .font(.headline.weight(.bold))
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
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
