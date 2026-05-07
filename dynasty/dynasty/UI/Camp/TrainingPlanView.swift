import SwiftUI
import SwiftData

// MARK: - Training Plan View
//
// Phase 1 UI: GM allocates 100 focus points across Tactical / Physical /
// Technical for the upcoming camp / regular-season week. Below the sliders,
// a per-player workload list surfaces injury / burnout risk so the GM can
// see immediate consequences of a heavy-pads plan.

struct TrainingPlanView: View {

    let career: Career
    let roster: [Player]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Default to a balanced 34/33/33 split. Sum is force-rebalanced to 100
    // whenever a slider moves so the three values always sum to 100.
    @State private var tacticalPct: Int = 34
    @State private var physicalPct: Int = 33
    @State private var technicalPct: Int = 33

    /// Tracks the most-recently moved slider so the rebalance routine can
    /// distribute the delta across the *other* two sliders proportionally.
    @State private var lastEdited: Focus = .tactical

    @State private var didSave: Bool = false

    private enum Focus { case tactical, physical, technical }

    private enum Preset: String, CaseIterable, Identifiable {
        case balanced = "Balanced"
        case schemeHeavy = "Scheme Heavy"
        case campHard = "Camp Hard"
        case recovery = "Recovery Mode"

        var id: String { rawValue }

        var allocation: (tactical: Int, physical: Int, technical: Int) {
            switch self {
            case .balanced:    return (34, 33, 33)
            case .schemeHeavy: return (60, 20, 20)
            case .campHard:    return (20, 50, 30)
            case .recovery:    return (40, 15, 45)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DSSpacing.lg) {
                header

                presetRow

                slidersCard

                workloadList
            }
            .padding(DSSpacing.md)
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Training Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: save) {
                    Text(didSave ? "Saved" : "Save")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(didSave)
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: "Week \(career.currentWeek) Focus")
            Text("Distribute 100 points across the three focus areas. The split steers per-player attribute deltas this week.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(Preset.allCases) { preset in
                    Button {
                        applyPreset(preset)
                    } label: {
                        Text(preset.rawValue)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                    .fill(Color.backgroundTertiary)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                    .strokeBorder(Color.surfaceBorder, lineWidth: 1)
                            )
                            .foregroundStyle(Color.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var slidersCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            focusRow(
                label: "Tactical",
                blurb: "Scheme + film → awareness, decision-making",
                value: $tacticalPct,
                tint: Color.accentBlue,
                focus: .tactical
            )
            focusRow(
                label: "Physical",
                blurb: "S&C + conditioning → stamina, durability",
                value: $physicalPct,
                tint: Color.success,
                focus: .physical
            )
            focusRow(
                label: "Technical",
                blurb: "Drills + fundamentals → position skill",
                value: $technicalPct,
                tint: Color.accentGold,
                focus: .technical
            )

            HStack {
                Text("Total")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(tacticalPct + physicalPct + technicalPct)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(totalIs100 ? Color.success : Color.warning)
            }
            .padding(.top, 4)
        }
        .padding(DSSpacing.md)
        .cardBackground()
    }

    private func focusRow(
        label: String,
        blurb: String,
        value: Binding<Int>,
        tint: Color,
        focus: Focus
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text("\(value.wrappedValue)%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            Text(blurb)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { newValue in
                        lastEdited = focus
                        let v = Int(newValue.rounded())
                        value.wrappedValue = v
                        rebalance(after: focus)
                    }
                ),
                in: 0...100,
                step: 1
            )
            .tint(tint)
        }
    }

    private var workloadList: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            SectionHeaderText(title: "Per-Player Workload")
            if displayRoster.isEmpty {
                CompactEmptyStateView(
                    icon: "person.crop.circle.badge.questionmark",
                    message: "No active roster — sign players in Free Agency."
                )
            } else {
                ForEach(displayRoster, id: \.id) { player in
                    workloadRow(for: player)
                }
            }
        }
    }

    private func workloadRow(for player: Player) -> some View {
        HStack(spacing: DSSpacing.sm) {
            // Position badge
            Text(player.position.rawValue)
                .font(.caption2.weight(.bold))
                .frame(width: 32, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.backgroundTertiary)
                )
                .foregroundStyle(Color.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(player.fullName)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("OVR \(player.overall)")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            // Cumulative load meter
            VStack(alignment: .trailing, spacing: 2) {
                workloadMeter(load: player.cumulativeLoad, status: player.workloadStatus)
                Text("\(player.workloadStatus.emoji)  \(injuryRiskLabel(for: player))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(loadTint(for: player.workloadStatus))
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
        )
    }

    private func workloadMeter(load: Int, status: WorkloadStatus) -> some View {
        let clamped = max(0, min(100, load))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.backgroundTertiary)
                Capsule()
                    .fill(loadTint(for: status))
                    .frame(width: geo.size.width * CGFloat(clamped) / 100.0)
            }
        }
        .frame(height: 6)
    }

    // MARK: - Helpers

    /// Limit roster preview to first 30 to keep ScrollView responsive on iPad.
    private var displayRoster: [Player] {
        Array(roster.prefix(30))
    }

    private var totalIs100: Bool {
        tacticalPct + physicalPct + technicalPct == 100
    }

    private func loadTint(for status: WorkloadStatus) -> Color {
        switch status {
        case .underloaded: return Color.textTertiary
        case .healthy:     return Color.success
        case .overloaded:  return Color.warning
        case .burnedOut:   return Color.danger
        }
    }

    private func injuryRiskLabel(for player: Player) -> String {
        let basePct = 4
        let risk = Int(Double(basePct) * player.workloadStatus.injuryMultiplier)
        return "\(risk)% inj"
    }

    private func applyPreset(_ preset: Preset) {
        let alloc = preset.allocation
        tacticalPct = alloc.tactical
        physicalPct = alloc.physical
        technicalPct = alloc.technical
        didSave = false
    }

    /// Rebalances the two sliders that were *not* just edited so the total
    /// returns to exactly 100. Distributes the delta proportionally to the
    /// untouched sliders' current values to preserve their relative weight.
    private func rebalance(after focus: Focus) {
        didSave = false
        let total = tacticalPct + physicalPct + technicalPct
        let delta = total - 100
        guard delta != 0 else { return }

        switch focus {
        case .tactical:
            distribute(delta, into: (\TrainingPlanView.physicalPct, \TrainingPlanView.technicalPct))
        case .physical:
            distribute(delta, into: (\TrainingPlanView.tacticalPct, \TrainingPlanView.technicalPct))
        case .technical:
            distribute(delta, into: (\TrainingPlanView.tacticalPct, \TrainingPlanView.physicalPct))
        }
    }

    private func distribute(
        _ delta: Int,
        into pair: (ReferenceWritableKeyPath<TrainingPlanView, Int>, ReferenceWritableKeyPath<TrainingPlanView, Int>)
    ) {
        // SwiftUI structs are value types; resolve via local copies and write back.
        // We can't write through KeyPath on a struct cleanly, so do it manually.
        let aValue: Int
        let bValue: Int
        switch pair.0 {
        case \.tacticalPct:  aValue = tacticalPct
        case \.physicalPct:  aValue = physicalPct
        case \.technicalPct: aValue = technicalPct
        default: aValue = 0
        }
        switch pair.1 {
        case \.tacticalPct:  bValue = tacticalPct
        case \.physicalPct:  bValue = physicalPct
        case \.technicalPct: bValue = technicalPct
        default: bValue = 0
        }

        // If both are zero, just split evenly.
        let sum = max(1, aValue + bValue)
        let aShare = Int((Double(delta) * Double(aValue) / Double(sum)).rounded())
        let bShare = delta - aShare

        let newA = max(0, min(100, aValue - aShare))
        let newB = max(0, min(100, bValue - bShare))

        switch pair.0 {
        case \.tacticalPct:  tacticalPct = newA
        case \.physicalPct:  physicalPct = newA
        case \.technicalPct: technicalPct = newA
        default: break
        }
        switch pair.1 {
        case \.tacticalPct:  tacticalPct = newB
        case \.physicalPct:  physicalPct = newB
        case \.technicalPct: technicalPct = newB
        default: break
        }

        // Final correction in case rounding pushed the total off by 1.
        let drift = (tacticalPct + physicalPct + technicalPct) - 100
        if drift != 0 {
            switch focus(for: pair.0) {
            case .tactical:  tacticalPct -= drift
            case .physical:  physicalPct -= drift
            case .technical: technicalPct -= drift
            }
        }
    }

    private func focus(for keyPath: ReferenceWritableKeyPath<TrainingPlanView, Int>) -> Focus {
        switch keyPath {
        case \.tacticalPct: return .tactical
        case \.physicalPct: return .physical
        default: return .technical
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let teamID = career.teamID else { return }
        let plan = TrainingPlan(
            seasonYear: career.currentSeason,
            weekNumber: career.currentWeek,
            phaseRaw: career.currentPhase.rawValue,
            tacticalPct: tacticalPct,
            physicalPct: physicalPct,
            technicalPct: technicalPct,
            teamID: teamID
        )
        modelContext.insert(plan)
        try? modelContext.save()
        didSave = true
    }
}
