import SwiftUI
import SwiftData

// MARK: - OwnerBudgetView (R31)

/// Unified staff budget view: the owner hands over one total envelope
/// (coaching + scouting + medical) and the coach decides how to split it.
/// Reallocations move money between the three pots in $250K steps; a pot can
/// never drop below the salaries already committed to it.
struct OwnerBudgetView: View {

    let career: Career

    @Environment(\.modelContext) private var modelContext

    @State private var owner: Owner?
    @State private var team: Team?

    // Allocations being edited (in thousands).
    @State private var coachingAlloc: Int = 0
    @State private var scoutingAlloc: Int = 0
    @State private var medicalAlloc: Int = 0

    // Committed salaries per pot (in thousands).
    @State private var committedCoaching: Int = 0
    @State private var committedScouting: Int = 0
    @State private var committedMedical: Int = 0

    // Total envelope granted by the owner (fixed while editing).
    @State private var totalEnvelope: Int = 0

    @State private var showSavedConfirmation = false

    private let step = 250
    private let potFloor = 500

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            Group {
                if let owner {
                    ScrollView {
                        VStack(spacing: 20) {
                            envelopeCard(owner)

                            potCard(
                                title: "Coaching",
                                icon: "person.3.fill",
                                color: Color.accentGold,
                                allocation: $coachingAlloc,
                                committed: committedCoaching,
                                caption: "Head coach, coordinators, and position coaches."
                            )
                            potCard(
                                title: "Scouting",
                                icon: "binoculars.fill",
                                color: Color.accentBlue,
                                allocation: $scoutingAlloc,
                                committed: committedScouting,
                                caption: "Chief scout and regional scouting network."
                            )
                            potCard(
                                title: "Medical",
                                icon: "cross.case.fill",
                                color: Color.success,
                                allocation: $medicalAlloc,
                                committed: committedMedical,
                                caption: "Team doctor, physio, and head trainer."
                            )

                            unallocatedRow

                            saveButton

                            if showSavedConfirmation {
                                Label("Budget allocation saved", systemImage: "checkmark.circle.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.success)
                                    .transition(.opacity)
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 620)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    noOwnerState
                }
            }
        }
        .navigationTitle("Staff Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { loadData() }
    }

    // MARK: - Derived

    private var allocatedTotal: Int {
        coachingAlloc + scoutingAlloc + medicalAlloc
    }

    private var unallocated: Int {
        totalEnvelope - allocatedTotal
    }

    private var hasChanges: Bool {
        guard let owner else { return false }
        return coachingAlloc != owner.coachingBudget
            || scoutingAlloc != owner.scoutingBudget
            || medicalAlloc != owner.medicalBudget
    }

    // MARK: - Envelope Card

    private func envelopeCard(_ owner: Owner) -> some View {
        let archetype = OwnerPersonaEngine.OwnerArchetype.from(owner)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "envelope.badge.person.crop.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Owner's Envelope")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(formatMoney(totalEnvelope))
                    .font(.title3.weight(.black).monospacedDigit())
                    .foregroundStyle(Color.accentGold)
            }

            Divider().overlay(Color.surfaceBorder)

            HStack(spacing: 8) {
                Image(systemName: archetype.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.accentGold)
                Text("\(owner.name) \u{2022} \(archetype.displayName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
            }

            Text("The owner sets the total each offseason based on personality, market, and results. How you split it between coaching, scouting, and medical is up to you — hiring rooms only see their own pot.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .cardBackground()
    }

    // MARK: - Pot Card

    private func potCard(
        title: String,
        icon: String,
        color: Color,
        allocation: Binding<Int>,
        committed: Int,
        caption: String
    ) -> some View {
        let floor = max(committed, potFloor)
        let remaining = allocation.wrappedValue - committed

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text("\(title) Budget")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()

                // Stepper controls
                HStack(spacing: 10) {
                    stepperButton(system: "minus.circle.fill", enabled: allocation.wrappedValue - step >= floor) {
                        allocation.wrappedValue -= step
                    }
                    Text(formatMoney(allocation.wrappedValue))
                        .font(.headline.weight(.bold).monospacedDigit())
                        .foregroundStyle(color)
                        .frame(minWidth: 76)
                    stepperButton(system: "plus.circle.fill", enabled: unallocated >= step) {
                        allocation.wrappedValue += step
                    }
                }
            }

            // Usage bar: committed share of the allocation
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.backgroundTertiary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(remaining >= 0 ? color : Color.danger)
                        .frame(width: geo.size.width * min(1.0, Double(committed) / max(1.0, Double(allocation.wrappedValue))))
                }
            }
            .frame(height: 8)

            HStack {
                Text("\(formatMoney(committed)) committed")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(remaining >= 0 ? "\(formatMoney(remaining)) to spend" : "\(formatMoney(abs(remaining))) over")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(remaining >= 0 ? Color.success : Color.danger)
            }

            Text(caption)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(18)
        .cardBackground()
    }

    private func stepperButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 24))
                .foregroundStyle(enabled ? Color.accentGold : Color.textTertiary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Unallocated + Save

    private var unallocatedRow: some View {
        HStack {
            Image(systemName: unallocated == 0 ? "checkmark.seal.fill" : "tray.fill")
                .foregroundStyle(unallocated == 0 ? Color.success : Color.warning)
            Text(unallocated == 0 ? "Fully allocated" : "Unallocated")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(formatMoney(unallocated))
                .font(.headline.weight(.bold).monospacedDigit())
                .foregroundStyle(unallocated == 0 ? Color.success : Color.warning)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            (unallocated == 0 ? Color.success : Color.warning).opacity(0.4),
                            lineWidth: 1
                        )
                )
        )
    }

    private var saveButton: some View {
        Button {
            saveAllocation()
        } label: {
            Text("Save Allocation")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.backgroundPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    (hasChanges && unallocated == 0) ? Color.accentGold : Color.textTertiary.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 12)
                )
        }
        .buttonStyle(.plain)
        .disabled(!hasChanges || unallocated != 0)
    }

    // MARK: - No Owner State

    private var noOwnerState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)
            Text("No Budget Data")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
            Spacer()
        }
    }

    // MARK: - Actions

    private func saveAllocation() {
        guard let owner, unallocated == 0 else { return }
        owner.coachingBudget = coachingAlloc
        owner.scoutingBudget = scoutingAlloc
        owner.medicalBudget = medicalAlloc
        try? modelContext.save()

        withAnimation(.easeIn(duration: 0.2)) {
            showSavedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.4)) {
                showSavedConfirmation = false
            }
        }
    }

    // MARK: - Data

    private func loadData() {
        guard let teamID = career.teamID else { return }
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first
        owner = team?.owner
        guard let owner else { return }

        coachingAlloc = owner.coachingBudget
        scoutingAlloc = owner.scoutingBudget
        medicalAlloc = owner.medicalBudget
        totalEnvelope = coachingAlloc + scoutingAlloc + medicalAlloc

        let medicalRoles: Set<CoachRole> = [.teamDoctor, .physio, .headTrainer]
        let coachDesc = FetchDescriptor<Coach>(predicate: #Predicate<Coach> { $0.teamID == teamID })
        let coaches = (try? modelContext.fetch(coachDesc)) ?? []
        committedCoaching = coaches
            .filter { !medicalRoles.contains($0.role) }
            .reduce(0) { $0 + $1.salary }
        committedMedical = coaches
            .filter { medicalRoles.contains($0.role) }
            .reduce(0) { $0 + $1.salary }

        let scoutDesc = FetchDescriptor<Scout>(predicate: #Predicate<Scout> { $0.teamID == teamID })
        let scouts = (try? modelContext.fetch(scoutDesc)) ?? []
        committedScouting = scouts.reduce(0) { $0 + $1.salary }
    }

    // MARK: - Formatting

    private func formatMoney(_ thousands: Int) -> String {
        String(format: "$%.1fM", Double(thousands) / 1_000.0)
    }
}

// MARK: - Preview

#Preview {
    let career = Career(playerName: "Alex Reid", role: .gm, capMode: .simple)
    NavigationStack {
        OwnerBudgetView(career: career)
    }
    .modelContainer(for: [Career.self, Team.self, Owner.self, Coach.self, Scout.self], inMemory: true)
}
