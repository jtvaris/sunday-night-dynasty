import SwiftUI
import SwiftData

// MARK: - OwnerBudgetView (R31)

/// Unified staff budget view: the owner hands over one total envelope
/// (coaching + scouting + medical) and the coach decides how to split it.
/// Reallocations move money between the three pots in $250K steps; a pot can
/// never drop below the salaries already committed to it.
///
/// §5.4 adds the buildings underneath the people: a second, separate envelope
/// for the three facility tracks. It is deliberately NOT part of the staff
/// envelope — that money is committed to salaries, and a training complex
/// cannot be paid for by not paying the physio — so it has its own budget line
/// and saves on the spot rather than through the allocation button.
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

    // Facility tiers being edited (§5.4). Applied on the spot, not through the
    // staff-allocation save button.
    @State private var facilityLevels: FacilityEngine.Levels = .standard

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

                            facilitiesCard(owner)
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
                // Whose envelope this is — leading-edge portrait, like a coach row.
                PersonFaceView(owner: owner, size: .small)
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
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(Color.backgroundTertiary)
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
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
                .font(.system(size: DSType.Size.title2))
                .foregroundStyle(enabled ? Color.accentGold : Color.textTertiaryReadable)
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

    // MARK: - Facilities Card (§5.4)

    private func facilitiesCard(_ owner: Owner) -> some View {
        let upkeep = FacilityEngine.upkeep(levels: facilityLevels)
        let budget = FacilityEngine.annualBudget(owner: owner)
        let overBudget = upkeep > budget

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundStyle(Color.accentGold)
                Text("Facilities")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(formatMoney(upkeep)) / \(formatMoney(budget))")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(overBudget ? Color.danger : Color.success)
            }

            Text("A separate envelope from the staff budget — the owner funds the buildings, you decide which ones. League Standard is what everybody else has: it costs you nothing and buys you nothing.")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Color.surfaceBorder)

            ForEach(FacilityEngine.Track.allCases) { track in
                facilityRow(track, owner: owner)
            }

            Divider().overlay(Color.surfaceBorder)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "quote.opening")
                    .font(.caption2)
                    .foregroundStyle(Color.accentGold)
                Text(FacilityEngine.ownerMeetingLine(owner: owner))
                    .font(.caption.italic())
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .cardBackground()
    }

    private func facilityRow(_ track: FacilityEngine.Track, owner: Owner) -> some View {
        let tier = facilityLevels[track]
        let canUp = tier < FacilityEngine.maxTier
            && FacilityEngine.canAfford(owner: owner, track: track, tier: tier + 1)
        let canDown = tier > FacilityEngine.minTier

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: track.icon)
                    .foregroundStyle(Color.accentBlue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(FacilityEngine.tierName(tier)) · \(formatMoney(FacilityEngine.annualCost(tier: tier)))/yr")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()

                HStack(spacing: 10) {
                    stepperButton(system: "minus.circle.fill", enabled: canDown) {
                        setTier(track, to: tier - 1, owner: owner)
                    }
                    tierPips(tier)
                    stepperButton(system: "plus.circle.fill", enabled: canUp) {
                        setTier(track, to: tier + 1, owner: owner)
                    }
                }
            }

            Text("\(FacilityEngine.effectSummary(track: track, tier: tier)) · \(track.caption)")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundTertiary)
        )
    }

    /// Three pips, filled up to the current tier.
    private func tierPips(_ tier: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(FacilityEngine.minTier...FacilityEngine.maxTier, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(level <= tier ? Color.accentGold : Color.backgroundSecondary)
                    .frame(width: 14, height: 10)
            }
        }
        .frame(minWidth: 56)
        .accessibilityLabel("Tier \(tier) of \(FacilityEngine.maxTier)")
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

    /// §5.4: facility tiers apply immediately. There is nothing to reconcile
    /// the way the three staff pots have to be (they must sum to the envelope),
    /// so a confirm step would only be a second tap.
    private func setTier(_ track: FacilityEngine.Track, to tier: Int, owner: Owner) {
        var proposed = facilityLevels
        proposed[track] = tier
        // Never let a tap put the club over what the owner will fund.
        guard tier < facilityLevels[track]
            || FacilityEngine.upkeep(levels: proposed) <= FacilityEngine.annualBudget(owner: owner)
        else { return }

        facilityLevels = proposed
        FacilityEngine.apply(proposed, to: owner)
        try? modelContext.save()
    }

    // MARK: - Data

    private func loadData() {
        guard let teamID = career.teamID else { return }
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        team = try? modelContext.fetch(teamDesc).first
        owner = team?.owner
        guard let owner else { return }

        // §5.4: `Team.owner` has no inverse, so the owner row cannot name its
        // own club. Stamp it here for the user's franchise — the league-wide
        // pass does the other 31.
        if owner.teamID != teamID {
            owner.teamID = teamID
            FacilityEngine.invalidateCache()
        }
        facilityLevels = FacilityEngine.levels(for: owner)

        coachingAlloc = owner.coachingBudget
        scoutingAlloc = owner.scoutingBudget
        medicalAlloc = owner.medicalBudget
        totalEnvelope = coachingAlloc + scoutingAlloc + medicalAlloc

        // #133: the committed side is ONE computation, shared with the staff
        // screen and the dashboard tile. This screen used to carry its own
        // medical-role filter and its own per-ROW sum over an unscoped fetch —
        // so the pot floor it refuses to slide below could disagree with the
        // "used $x of $y" the Staff screen printed for the same three pots.
        let cid = career.id
        let coachDesc = FetchDescriptor<Coach>(
            predicate: #Predicate<Coach> { $0.careerID == cid && $0.teamID == teamID }
        )
        let coaches = (try? modelContext.fetch(coachDesc)) ?? []
        let scoutDesc = FetchDescriptor<Scout>(
            predicate: #Predicate<Scout> { $0.careerID == cid && $0.teamID == teamID }
        )
        let scouts = (try? modelContext.fetch(scoutDesc)) ?? []

        let ledger = StaffLedger(
            careerRole: career.role,
            coaches: coaches,
            scouts: scouts,
            owner: owner
        )
        committedCoaching = ledger.committedCoaching
        committedMedical = ledger.committedMedical
        committedScouting = ledger.committedScouting
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
