import SwiftUI
import SwiftData

struct HireScoutView: View {

    let scoutRole: ScoutRole
    let teamID: UUID
    let remainingBudget: Int
    var onHired: ((String, String) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var candidates: [Scout] = []
    @State private var hiredScoutID: UUID?
    @State private var sortOption: SortOption = .accuracy
    @State private var showAffordableOnly: Bool = false

    enum SortOption: String, CaseIterable {
        case accuracy      = "Accuracy"
        case potential      = "Potential Read"
        case personality    = "Personality Read"
        case salary         = "Salary"
        case experience     = "Experience"
        case value          = "Value"
    }

    private var filteredCandidates: [Scout] {
        if showAffordableOnly {
            return candidates.filter { $0.salary <= remainingBudget }
        }
        return candidates
    }

    private var sortedCandidates: [Scout] {
        let list = filteredCandidates
        switch sortOption {
        case .accuracy:    return list.sorted { $0.accuracy > $1.accuracy }
        case .potential:   return list.sorted { $0.potentialRead > $1.potentialRead }
        case .personality: return list.sorted { $0.personalityRead > $1.personalityRead }
        case .salary:      return list.sorted { $0.salary < $1.salary }
        case .experience:  return list.sorted { $0.experience > $1.experience }
        case .value:       return list.sorted { scoutValueRatio($0) > scoutValueRatio($1) }
        }
    }

    /// Value ratio for scouts (accuracy-to-salary).
    private func scoutValueRatio(_ scout: Scout) -> Double {
        let avg = Double(scout.accuracy + scout.potentialRead + scout.personalityRead) / 3.0
        let salaryM = max(Double(scout.salary) / 1_000.0, 0.01)
        return avg / salaryM
    }

    /// Value label for a scout.
    private func scoutValueLabel(_ scout: Scout) -> (label: String, color: Color) {
        let ratio = scoutValueRatio(scout)
        if ratio >= 400 { return ("Great", .success) }
        if ratio >= 250 { return ("Good", .accentGold) }
        if ratio >= 150 { return ("Fair", .warning) }
        return ("Poor", .danger)
    }

    /// Top 3 scout IDs by accuracy.
    private var top3ScoutIDs: Set<UUID> {
        let byAcc = filteredCandidates.sorted { $0.accuracy > $1.accuracy }
        return Set(byAcc.prefix(3).map { $0.id })
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            // Background image with gradient overlay
            GeometryReader { geo in
                Image("BgCombine")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .opacity(0.12)
            }
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.backgroundPrimary.opacity(0.85),
                    Color.backgroundPrimary.opacity(0.5),
                    Color.backgroundPrimary.opacity(0.85)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Budget header (matching HireCoachView style)
                VStack(spacing: 8) {
                    Text(scoutRole.roleDescription)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

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

                        // Affordable-only toggle (matching HireCoachView)
                        Toggle(isOn: $showAffordableOnly) {
                            Text("Affordable")
                                .font(.caption2)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .toggleStyle(.switch)
                        .tint(Color.accentGold)
                        .fixedSize()

                        Spacer().frame(width: 12)

                        Picker("Sort", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.accentGold)

                        Spacer().frame(width: 12)

                        Text("\(filteredCandidates.count) candidates")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.backgroundSecondary)

                Divider().overlay(Color.surfaceBorder)

                // Candidate list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedCandidates) { candidate in
                            ScoutCandidateRow(
                                candidate: candidate,
                                isHired: hiredScoutID == candidate.id,
                                isOverBudget: candidate.salary > remainingBudget,
                                isTop3: top3ScoutIDs.contains(candidate.id),
                                valueLabel: scoutValueLabel(candidate)
                            ) {
                                hire(candidate)
                            }

                            Divider()
                                .overlay(Color.surfaceBorder.opacity(0.4))
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
        }
        .navigationTitle("Hire \(scoutRole.displayName)")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            if candidates.isEmpty {
                candidates = CoachingEngine.generateScoutCandidates(role: scoutRole, count: 20)
            }
        }
    }

    private func formatBudget(_ thousands: Int) -> String {
        let millions = Double(thousands) / 1_000.0
        return String(format: "%.1f", millions)
    }

    // MARK: - Hire Action

    private func hire(_ candidate: Scout) {
        guard candidate.salary <= remainingBudget else { return }

        // Remove any existing scout with the same role on this team
        let descriptor = FetchDescriptor<Scout>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        if let existing = try? modelContext.fetch(descriptor) {
            existing.filter { $0.scoutRole == scoutRole }.forEach { modelContext.delete($0) }
        }

        candidate.teamID = teamID
        modelContext.insert(candidate)
        hiredScoutID = candidate.id

        // Save context before dismissing so CoachingStaffView's @Query refreshes
        try? modelContext.save()

        let hiredName = candidate.fullName
        let hiredRole = scoutRole.displayName

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            onHired?(hiredName, hiredRole)
            dismiss()
        }
    }
}

// MARK: - Scout Candidate Row

private struct ScoutCandidateRow: View {
    let candidate: Scout
    let isHired: Bool
    let isOverBudget: Bool
    let isTop3: Bool
    let valueLabel: (label: String, color: Color)
    let onHire: () -> Void

    var body: some View {
        HStack(spacing: 0) {
                // Name + meta
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(candidate.fullName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(isOverBudget ? Color.textTertiary : Color.textPrimary)
                            .lineLimit(1)

                        // Top 3 badge
                        if isTop3 {
                            Text("TOP")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(Color.backgroundPrimary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    HStack(spacing: 6) {
                        Text("\(candidate.experience) yr\(candidate.experience == 1 ? "" : "s")")
                            .font(.system(size: 9).monospacedDigit())
                        if let spec = candidate.positionSpecialization {
                            Text(spec.rawValue)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.accentBlue)
                        }
                    }
                    .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Accuracy
                VStack(spacing: 2) {
                    Text("\(candidate.accuracy)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.forRating(candidate.accuracy))
                    Text("Acc")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(width: 36)

                // Potential Read
                VStack(spacing: 2) {
                    Text("\(candidate.potentialRead)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.forRating(candidate.potentialRead))
                    Text("Pot")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(width: 36)

                // Personality Read
                VStack(spacing: 2) {
                    Text("\(candidate.personalityRead)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.forRating(candidate.personalityRead))
                    Text("Pers")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(width: 36)

                // Salary
                Text("$\(candidate.salary)K")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(isOverBudget ? Color.danger : Color.textSecondary)
                    .frame(width: 52)

                // Value badge
                Text(valueLabel.label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(valueLabel.color)
                    .frame(width: 36)

                // Hire button / status indicator
                Group {
                    if isHired {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.success)
                            .frame(width: 30)
                    } else if isOverBudget {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.danger.opacity(0.5))
                            .frame(width: 30)
                    } else {
                        Button(action: onHire) {
                            Text("Hire")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.backgroundPrimary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(isOverBudget ? 0.6 : 1.0)
        .background(
            Group {
                if isHired {
                    Color.success.opacity(0.06)
                } else if isTop3 {
                    Color.accentGold.opacity(0.04)
                } else {
                    Color.clear
                }
            }
        )
        .overlay(alignment: .leading) {
            if isTop3 {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentGold)
                    .frame(width: 3)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HireScoutView(scoutRole: .chiefScout, teamID: UUID(), remainingBudget: 5_000)
    }
    .modelContainer(for: Scout.self, inMemory: true)
}
