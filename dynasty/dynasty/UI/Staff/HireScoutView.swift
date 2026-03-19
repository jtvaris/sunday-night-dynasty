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

    enum SortOption: String, CaseIterable {
        case accuracy      = "Accuracy"
        case potential      = "Potential Read"
        case personality    = "Personality Read"
        case salary         = "Salary"
        case experience     = "Experience"
    }

    private var sortedCandidates: [Scout] {
        switch sortOption {
        case .accuracy:    return candidates.sorted { $0.accuracy > $1.accuracy }
        case .potential:   return candidates.sorted { $0.potentialRead > $1.potentialRead }
        case .personality: return candidates.sorted { $0.personalityRead > $1.personalityRead }
        case .salary:      return candidates.sorted { $0.salary < $1.salary }
        case .experience:  return candidates.sorted { $0.experience > $1.experience }
        }
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
                    Color.backgroundPrimary.opacity(0.6),
                    Color.backgroundPrimary.opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            List {
                Section {
                    ForEach(sortedCandidates) { candidate in
                        ScoutCandidateRow(
                            candidate: candidate,
                            isHired: hiredScoutID == candidate.id,
                            isOverBudget: candidate.salary > remainingBudget
                        ) {
                            hire(candidate)
                        }
                    }
                } header: {
                    Text("\(candidates.count) Available Candidates")
                } footer: {
                    Text("Select a scout to add them to your scouting department.")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                .listRowBackground(Color.backgroundSecondary)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .top) {
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
                        Picker("Sort", selection: $sortOption) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Color.accentGold)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial)
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
    let onHire: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: name + salary + hire button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.fullName)
                        .font(.headline)
                        .foregroundStyle(isOverBudget ? Color.textTertiary : Color.textPrimary)

                    HStack(spacing: 6) {
                        Text("\(candidate.experience) yr\(candidate.experience == 1 ? "" : "s") exp")
                        if let spec = candidate.positionSpecialization {
                            Text("\u{00B7}")
                            Text("Specializes: \(spec.rawValue)")
                                .foregroundStyle(Color.accentBlue)
                        }
                        Text("\u{00B7}")
                        Text("$\(candidate.salary)K/yr")
                            .foregroundStyle(isOverBudget ? Color.danger : Color.accentGold)
                            .fontWeight(.semibold)
                    }
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                Button(action: onHire) {
                    if isHired {
                        Label("Hired", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.success)
                    } else if isOverBudget {
                        Text("Over Budget")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.danger)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("Hire")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.backgroundPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .disabled(isHired || isOverBudget)
                .animation(.easeInOut(duration: 0.2), value: isHired)
            }

            // Star ratings
            HStack(spacing: 0) {
                starCell(label: "Accuracy", value: candidate.accuracy)
                starCell(label: "Potential Read", value: candidate.potentialRead)
                starCell(label: "Personality", value: candidate.personalityRead)
            }
            .opacity(isOverBudget ? 0.5 : 1.0)
        }
        .padding(.vertical, 6)
        .opacity(isOverBudget ? 0.7 : 1.0)
    }

    private func starCell(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text(CoachingEngine.starString(for: value))
                .font(.system(size: 10))
                .foregroundStyle(Color.accentGold)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(Color.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        HireScoutView(scoutRole: .chiefScout, teamID: UUID(), remainingBudget: 5_000)
    }
    .modelContainer(for: Scout.self, inMemory: true)
}
