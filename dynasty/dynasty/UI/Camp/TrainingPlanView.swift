import SwiftUI
import SwiftData

// MARK: - Training Plan View
//
// Phase 1 UI: GM allocates 100 focus points across Tactical / Physical /
// Technical for the upcoming camp / regular-season week. Below the sliders,
// a per-player workload list surfaces injury / burnout risk so the GM can
// see immediate consequences of a heavy-pads plan.
//
// Wave 5b brings it onto the standard (UI_REDESIGN_VISION §2.2 / §2.5 / §2.7):
//
//  * **The commit came out of the toolbar.** P5 is categorical — "toolbars stop
//    carrying commits entirely" — and this one was worse than most, because the
//    thing being committed is a 100-point split the user has just spent a
//    minute tuning and the button that banks it was a `.subheadline` word in
//    the navigation bar. It is a `DSActionBar` now, pinned, with the explainer
//    saying which week the plan applies to and what it steers.
//  * **The workload list is a `DSListRow`.** It was a hand-drawn row with its
//    own position badge, its own 6 pt meter and a status told in EMOJI — 🔥 and
//    💀 — which §2.12 rules out by name, and which VoiceOver reads as "fire".
//    The status is a `DSStatusPill` now and the risk is a column.
//  * The empty roster is a `DSEmptyState` with the action that fills it.

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
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    header

                    presetRow

                    slidersCard

                    workloadList
                }
                .padding(DSSpacing.md)
            }
            commitBar
        }
        .background(Color.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("Training Plan")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadExistingPlan)
    }

    /// §2.5: the commit lives at the foot of the surface, with the line that
    /// says what it does. A split that does not add up to 100 is a blocked
    /// commit, and §2.12 asks a blocked commit to state the reason rather than
    /// present a dead grey button.
    private var commitBar: some View {
        DSActionBar(
            explainer: DSActionBar.Explainer(
                title: didSave ? "Plan saved" : "Save \u{2014} \(headerTitle)",
                message: totalIs100
                    ? (didSave
                        ? "This split is what the engine will run this week. Move a slider to change it."
                        : "Banks **\(tacticalPct)/\(physicalPct)/\(technicalPct)** tactical, physical and technical for this week's development pass.")
                    : "The three focus areas have to add up to **100**. They currently make **\(tacticalPct + physicalPct + technicalPct)**.",
                isWarning: !totalIs100
            ),
            primary: DSActionBar.Action(
                title: didSave ? "Saved" : "Save plan",
                isEnabled: !didSave && totalIs100,
                handler: save
            )
        )
    }

    // MARK: - Subviews

    /// "Week 0" reads like a bug during the offseason — use the phase name
    /// until the regular season gives weeks real meaning.
    private var headerTitle: String {
        switch career.currentPhase {
        case .regularSeason, .tradeDeadline, .playoffs:
            return "Week \(max(1, career.currentWeek)) Focus"
        default:
            break
        }
        return "\(career.currentPhase.displayName) Focus"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: headerTitle)
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
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            SectionHeaderText(title: "Per-Player Workload")
            if displayRoster.isEmpty {
                DSEmptyState(
                    density: .glance,
                    icon: "person.crop.circle.badge.questionmark",
                    title: "No active roster",
                    message: "There is nobody to train. Sign players in Free Agency and the load table fills itself."
                )
            } else {
                // Header and rows read the same column constants (§2.2), so a
                // label can never sit one column left of the number it names.
                DSListHeaderRow(
                    reservesBadge: true,
                    // Same zero-width portrait slot the rows reserve — a header
                    // that keeps the default 36 pt gutter puts every label one
                    // column left of the numbers it describes.
                    portraitWidth: 0,
                    identityLabel: "PLAYER"
                ) {
                    DSColumnHeader("LOAD", width: 96, alignment: .leading)
                    DSColumnHeader("STATE", width: DSListColumn.state)
                    DSColumnHeader("INJ", width: DSListColumn.tight)
                }
                .padding(.horizontal, DSSpacing.sm)

                ForEach(displayRoster, id: \.id) { player in
                    workloadRow(for: player)
                }
            }
        }
    }

    private func workloadRow(for player: Player) -> some View {
        DSListRow(
            badge: DSRowBadge(
                text: player.position.rawValue,
                tint: Color.backgroundTertiary,
                accessibilityLabel: player.position.rawValue
            ),
            portraitWidth: 0,
            portrait: { EmptyView() },
            identity: {
                VStack(alignment: .leading, spacing: 2) {  // ds-lint:allow(spacing) name-over-meta lockup inside one row
                    Text(player.fullName)
                        .font(DSType.text(DSType.Size.body, .semibold, prose: true))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    Text("OVR \(player.overall)")
                        .font(DSType.display(11, .semibold))
                        .foregroundStyle(Color.forRating(player.overall))
                }
            },
            columns: {
                workloadMeter(load: player.cumulativeLoad, status: player.workloadStatus)
                    .dsColumn(96, alignment: .leading)
                DSStatusPill(
                    label: workloadLabel(for: player.workloadStatus),
                    tone: workloadTone(for: player.workloadStatus),
                    showsDot: false,
                    spokenLabel: "Workload \(workloadLabel(for: player.workloadStatus))"
                )
                .dsColumn(DSListColumn.state)
                Text(injuryRiskLabel(for: player))
                    .font(DSType.display(11, .heavy))
                    .foregroundStyle(loadTint(for: player.workloadStatus))
                    .dsColumn(DSListColumn.tight)
            }
        )
        .padding(.horizontal, DSSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundSecondary)
        )
    }

    /// The status as a WORD. The model still exposes an `emoji` for the
    /// heat-map dashboards; a row that a screen reader has to speak does not
    /// get to say "fire" and "skull" (§2.12).
    private func workloadLabel(for status: WorkloadStatus) -> String {
        switch status {
        case .underloaded: return "Light"
        case .healthy:     return "Healthy"
        case .overloaded:  return "Heavy"
        case .burnedOut:   return "Burnt"
        }
    }

    private func workloadTone(for status: WorkloadStatus) -> DSStatusPill.Tone {
        switch status {
        case .underloaded: return .neutral
        case .healthy:     return .ok
        case .overloaded:  return .warn
        case .burnedOut:   return .bad
        }
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

    /// The meter and the risk figure share the pill's palette, so a row can
    /// never say "heavy" in orange next to a bar in yellow. `warning` moved to
    /// `alertOrange` for exactly this reason — P7's semantic hue separation.
    private func loadTint(for status: WorkloadStatus) -> Color {
        Color.forStatus(workloadTone(for: status))
    }

    private func injuryRiskLabel(for player: Player) -> String {
        // Use the real engine formula (durability + workload status) instead
        // of a flat base — otherwise every player reads an identical "4% inj".
        let risk = WorkloadEngine.injuryRiskPct(player: player, baseRisk: 0.04)
        return "\(Int(risk.rounded()))% inj"
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

    /// Fetches the already-saved plan for the current (team, season, week,
    /// phase) key, if any. Shared by load-back and upsert-save.
    private func fetchExistingPlan() -> TrainingPlan? {
        guard let teamID = career.teamID else { return nil }
        let season = career.currentSeason
        let week = career.currentWeek
        let phaseRaw = career.currentPhase.rawValue
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate {
                $0.teamID == teamID
                    && $0.seasonYear == season
                    && $0.weekNumber == week
                    && $0.phaseRaw == phaseRaw
            }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Seeds the sliders from the saved plan so the editor reflects what the
    /// engine will actually use (instead of always resetting to 34/33/33).
    private func loadExistingPlan() {
        guard let existing = fetchExistingPlan() else { return }
        tacticalPct = existing.tacticalPct
        physicalPct = existing.physicalPct
        technicalPct = existing.technicalPct
        didSave = true
    }

    private func save() {
        guard let teamID = career.teamID else { return }
        if let existing = fetchExistingPlan() {
            existing.tacticalPct = tacticalPct
            existing.physicalPct = physicalPct
            existing.technicalPct = technicalPct
        } else {
            let plan = TrainingPlan(
                seasonYear: career.currentSeason,
                weekNumber: career.currentWeek,
                phaseRaw: career.currentPhase.rawValue,
                tacticalPct: tacticalPct,
                physicalPct: physicalPct,
                technicalPct: technicalPct,
                teamID: teamID
            )
            plan.careerID = career.id
            modelContext.insert(plan)
        }
        try? modelContext.save()
        didSave = true
    }
}
