import SwiftUI
import SwiftData

// MARK: - Training Plan View
//
// Phase 1 UI: GM allocates 100 focus points across Tactical / Physical /
// Technical for the upcoming camp week. Below the sliders, a per-player
// workload list surfaces injury / burnout risk so the GM can see immediate
// consequences of a heavy-pads plan.
//
// **The editor is only an editor during a phase that runs a pass** — OTAs,
// training camp, preseason. Everywhere else it is a read-only record of the
// split that ran; see `planRunsThisPhase`.
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

    /// In the read-only case, the phase whose banked plan the sliders are
    /// showing — so the bar can name it instead of implying the split is one
    /// the GM could still commit.
    @State private var bankedPlanPhase: SeasonPhase?

    /// Which column the workload table is ordered by. Load descending is the
    /// default because the men this table exists to warn about have to be the
    /// men it shows.
    @State private var sort = DSSortState<SortKey>(key: .load)

    /// The workload rows are a plain `VStack` inside the page's `ScrollView`,
    /// so a 90-man camp roster would build every row up front. The preview stays
    /// capped until the GM asks for the rest.
    @State private var showAllWorkload: Bool = false

    private let workloadPreviewLimit = 30

    private enum Focus { case tactical, physical, technical }

    private enum SortKey: Hashable { case durability, stamina, age, load, injury }

    /// The presets name the SPLIT, never an intensity. "Camp Hard" and
    /// "Recovery Mode" used to sit here, and both promised a dial the model has
    /// no field for: a plan carries three percentages and nothing else, and
    /// camp load comes from `WorkloadEngine` at an intensity the phase sets. A
    /// 20/50/30 split is conditioning work; a 40/15/45 split is fundamentals.
    /// Neither rests anybody.
    private enum Preset: String, CaseIterable, Identifiable {
        case balanced = "Balanced"
        case schemeHeavy = "Scheme Heavy"
        case conditioning = "Conditioning"
        case fundamentals = "Fundamentals"

        var id: String { rawValue }

        var allocation: (tactical: Int, physical: Int, technical: Int) {
            switch self {
            case .balanced:     return (34, 33, 33)
            case .schemeHeavy:  return (60, 20, 20)
            case .conditioning: return (20, 50, 30)
            case .fundamentals: return (40, 15, 45)
            }
        }

        /// The split itself, in slider order. On the chip because four names
        /// cannot be compared without it — the alternative is tapping each one
        /// in turn and losing the split you were tuning.
        var splitText: String {
            let alloc = allocation
            return "\(alloc.tactical)/\(alloc.physical)/\(alloc.technical)"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    header

                    // Inert once the last camp tick has run: a slider that
                    // still moves is a slider that promises the movement goes
                    // somewhere. The workload table stays live — it is a read,
                    // and it is the one thing still worth reading here.
                    presetRow
                        .disabled(!planRunsThisPhase)

                    slidersCard
                        .disabled(!planRunsThisPhase)

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
    ///
    /// A phase that runs no development pass gets no button at all. It used to
    /// get a live gold one: during Roster Cuts the bar read "SAVE — ROSTER CUTS
    /// FOCUS / Banks 40/15/45 … for the Roster Cuts development pass", and
    /// there is no Roster Cuts development pass — `save()` stamped the row with
    /// the current phase and nothing ever fetched that key again. The screen
    /// confirmed "Plan saved" for a plan that could not run.
    private var commitBar: some View {
        DSActionBar(
            explainer: DSActionBar.Explainer(
                title: commitTitle,
                message: commitMessage,
                isWarning: !planRunsThisPhase || !totalIs100
            ),
            primary: planRunsThisPhase
                ? DSActionBar.Action(
                    title: didSave ? "Saved" : "Save plan",
                    isEnabled: !didSave && totalIs100,
                    handler: save
                )
                : nil
        )
    }

    private var commitTitle: String {
        if !planRunsThisPhase { return "Camp is spent" }
        return didSave ? "Plan saved" : "Save \u{2014} \(headerTitle)"
    }

    private var commitMessage: String {
        guard planRunsThisPhase else {
            let ran = bankedPlanPhase.map { "the split **\($0.displayName)** ran" }
                ?? "the balanced split the engine falls back to when nobody sets one"
            return "**\(career.currentPhase.displayName)** runs no development pass. Below is \(ran) \u{2014} the next plan you can set opens at **OTAs**."
        }
        guard totalIs100 else {
            return "The three focus areas have to add up to **100**. They currently make **\(tacticalPct + physicalPct + technicalPct)**."
        }
        let pass = career.currentPhase.displayName
        return didSave
            ? "This split is what the engine will run for the \(pass) development pass. Move a slider to change it."
            : "Banks **\(tacticalPct)/\(physicalPct)/\(technicalPct)** tactical, physical and technical for the \(pass) development pass."
    }

    // MARK: - Subviews

    /// True when this phase's weekly tick actually runs the plan.
    ///
    /// The saved row is keyed on the phase, and the only thing that ever reads
    /// one is `WeekAdvancer.applyCampWeeklyTick` — which fires from OTAs,
    /// training camp and preseason. Roster Cuts is the phase AFTER preseason,
    /// so by the time the GM reaches it every camp tick has already run; a plan
    /// banked there is a write with no reader. The whole screen turns read-only
    /// rather than pretending otherwise.
    private var planRunsThisPhase: Bool {
        TrainingPlanEngine.runsDevelopmentPass(in: career.currentPhase)
    }

    /// "Week 0" reads like a bug during the offseason, so the header names the
    /// phase. It needs no week number: the three phases that run a plan are one
    /// seven-day tick each, so the phase name identifies the pass exactly.
    private var headerTitle: String {
        planRunsThisPhase
            ? "\(career.currentPhase.displayName) Focus"
            : "Camp Training Closed"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            SectionHeaderText(title: headerTitle)
            Text(planRunsThisPhase
                 ? "Distribute 100 points across the three focus areas. The split steers per-player attribute deltas this week."
                 : "Camp is over for this season. The split below is the one the engine ran \u{2014} it is here to read, not to change.")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(Preset.allCases) { preset in
                    let isSelected = (activePreset == preset)
                    Button {
                        applyPreset(preset)
                    } label: {
                        VStack(spacing: 2) {  // ds-lint:allow(spacing) name-over-split lockup inside one chip
                            Text(preset.rawValue)
                                .font(.caption.weight(.semibold))
                            Text(preset.splitText)
                                .font(DSType.display(11, .semibold))
                                .opacity(0.75)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        // §2.12 has no exceptions: the chips measured ~24 pt,
                        // half of what the roster's own filter chips measure.
                        .frame(minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .fill(isSelected ? Color.accentGold : Color.backgroundTertiary)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .strokeBorder(isSelected ? Color.accentGold : Color.surfaceBorder, lineWidth: 1)
                        )
                        .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textPrimary)
                        .contentShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
        }
    }

    private var slidersCard: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            focusRow(
                label: "Tactical",
                blurb: "Scheme + film → awareness, decision-making",
                yield: tacticalYield,
                value: $tacticalPct,
                focus: .tactical
            )
            focusRow(
                label: "Physical",
                blurb: "S&C + conditioning → stamina, durability",
                yield: physicalYield,
                value: $physicalPct,
                focus: .physical
            )
            focusRow(
                label: "Technical",
                blurb: "Drills + fundamentals → position skill",
                yield: technicalYield,
                value: $technicalPct,
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

    /// One focus lane.
    ///
    /// **All three lanes are blue.** They shipped in `accentBlue` / `success` /
    /// `accentGold`, which are three *semantic* hues doing other jobs 500 px
    /// down the same scroll: green is the HEALTHY pill, and gold is the commit
    /// button — one degree of hue from the `warning` yellow the 60-69 rating
    /// band paints, so "press this" and "this player is mediocre" were the same
    /// colour on one screen. Blue is this app's informational / selected hue
    /// (the same rule `DSLensTabs` states), the lanes are told apart by their
    /// labels, and the one gold thing left in the card is the chip that is
    /// actually selected.
    private func focusRow(
        label: String,
        blurb: String,
        yield: String,
        value: Binding<Int>,
        focus: Focus
    ) -> some View {
        let tint = Color.accentBlue
        return VStack(alignment: .leading, spacing: 6) {
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
            Text(yield)
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Projected yield
    //
    // What a week of the current split actually buys, per player, taken from
    // `TrainingPlanEngine` rather than restated here. The chip row could not be
    // read without it: four names and four splits, and the whole row spans 0.84
    // to 0.95 attribute points a week — a 12 % spread that no amount of staring
    // at "60/20/20" reveals. The one genuine discontinuity is the scheme cliff,
    // which is why the tactical line names it in words instead of leaving a
    // min-maxer to find it by dragging the slider and watching a dictionary he
    // cannot see.

    private var tacticalYield: String {
        let awareness = TrainingPlanEngine.tacticalDelta(pct: tacticalPct)
        let decisions = awareness * TrainingPlanEngine.decisionMakingWeight
        let scheme = TrainingPlanEngine.schemeBump(pct: tacticalPct)
        let schemeText = scheme > 0
            ? "+\(scheme) scheme familiarity"
            : "no scheme work under \(TrainingPlanEngine.schemeBumpFloorPct)%"
        return "Per week: \(points(awareness)) awareness, \(points(decisions)) decision-making, \(schemeText)"
    }

    private var physicalYield: String {
        let stamina = TrainingPlanEngine.physicalDelta(pct: physicalPct)
        let durability = stamina * TrainingPlanEngine.durabilityWeight
        return "Per week: \(points(stamina)) stamina, \(points(durability)) durability"
    }

    private var technicalYield: String {
        "Per week: \(points(TrainingPlanEngine.technicalDelta(pct: technicalPct))) to one position skill"
    }

    /// A fractional attribute delta as the GM reads it. The engine rolls the
    /// fraction as a probability of a whole point, so "+0.34" is an expected
    /// value, not a promise of a third of a rating.
    private func points(_ value: Double) -> String {
        String(format: "+%.2f", value)
    }

    private var workloadList: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xs) {
                SectionHeaderText(title: "Per-Player Workload")
                Spacer(minLength: DSSpacing.xs)
                if !roster.isEmpty {
                    Text(workloadCountLabel)
                        .font(.caption2.weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            if displayRoster.isEmpty {
                DSEmptyState(
                    density: .glance,
                    icon: "person.crop.circle.badge.questionmark",
                    title: "No active roster",
                    message: "There is nobody to train. Sign players in Free Agency and the load table fills itself."
                )
            } else {
                // What this table decides on this screen: the split steers
                // attributes, camp intensity (a function of the phase) steers
                // the bars, and a burnt-out man absorbs half of what the plan
                // gives — which is the reason to read it before committing.
                Text("Load carried into this week — camp intensity sets it, not the split above. A player who reads Burnt takes only half of the week's gains. DUR is durability and STA stamina; INJ/100 is his chance of an injury over a hundred snaps, on the terms the match engine really rolls.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DSSpacing.xxs)

                // Header and rows read the same column constants (§2.2), so a
                // label can never sit one column left of the number it names.
                //
                // The numeric columns sort (`DSSortableColumnHeader`, the app's
                // existing pattern). Load descending stays the default — it is
                // what the table is FOR — but "the oldest men with the worst
                // durability" was a question 53 rows deep and unanswerable
                // without one.
                DSListHeaderRow(
                    reservesBadge: true,
                    // Same zero-width portrait slot the rows reserve — a header
                    // that keeps the default 36 pt gutter puts every label one
                    // column left of the numbers it describes.
                    portraitWidth: 0,
                    identityLabel: "PLAYER"
                ) {
                    DSSortableColumnHeader("DUR", key: .durability, sort: $sort, width: DSListColumn.attribute)
                    DSSortableColumnHeader("STA", key: .stamina, sort: $sort, width: DSListColumn.attribute)
                    DSSortableColumnHeader("AGE", key: .age, sort: $sort, width: DSListColumn.tight)
                    DSSortableColumnHeader("LOAD", key: .load, sort: $sort, width: loadColumnWidth)
                    DSColumnHeader("STATE", width: DSListColumn.state)
                    DSSortableColumnHeader("INJ/100", key: .injury, sort: $sort, width: DSListColumn.label)
                }
                .padding(.horizontal, DSSpacing.sm)

                ForEach(displayRoster, id: \.id) { player in
                    workloadRow(for: player)
                }

                if !showAllWorkload && roster.count > workloadPreviewLimit {
                    Button {
                        showAllWorkload = true
                    } label: {
                        Text("Show all \(roster.count)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.accentGold)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
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
                // Two of the inputs the INJ figure is computed FROM, plus the
                // age that decides how a heavy week reads. Without them the row
                // asked the GM to trust a risk he had no way to check, and left
                // most of its width empty doing it.
                ratingCell(player.physical.durability)
                    .dsColumn(DSListColumn.attribute)
                ratingCell(player.physical.stamina)
                    .dsColumn(DSListColumn.attribute)
                Text("\(player.age)")
                    .font(DSType.display(11, .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .dsColumn(DSListColumn.tight)
                loadCell(for: player)
                    .dsColumn(loadColumnWidth)
                DSStatusPill(
                    label: workloadLabel(for: player.workloadStatus),
                    tone: workloadTone(for: player.workloadStatus),
                    showsDot: false,
                    spokenLabel: "Workload \(workloadLabel(for: player.workloadStatus))"
                )
                .dsColumn(DSListColumn.state)
                injuryCell(for: player)
                    .dsColumn(DSListColumn.label)
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

    /// The load column: the integer, then the meter.
    ///
    /// The number is there because the meter alone could not answer the one
    /// question the column exists for. "How close is this man to Heavy" was a
    /// tap into the Workload Detail sheet, since the bar carried no axis, no
    /// tick and no figure — a HEALTHY pill at 60 % fill and a LIGHT pill at
    /// 20 % with nothing on the row saying where the boundary between them sat.
    private func loadCell(for player: Player) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Text("\(max(0, player.cumulativeLoad))")
                .font(DSType.display(11, .semibold))
                .foregroundStyle(Color.textSecondary)
                .monospacedDigit()
                .frame(width: 20, alignment: .trailing)
            workloadMeter(load: player.cumulativeLoad, status: player.workloadStatus)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camp load \(max(0, player.cumulativeLoad)) of \(WorkloadEngine.burnoutFloor)")
    }

    /// The bar fills at the load that makes a man Burnt, not at a round 100.
    /// The engine's whole reachable range is 0…70 (see the band derivation on
    /// `WorkloadEngine`), so dividing by 100 meant the bar could never pass
    /// two-thirds and a "Burnt" pill sat next to a meter that looked like it
    /// still had a third of the week left in it.
    ///
    /// The two notches are the Light→Healthy and Healthy→Heavy edges, so the
    /// pill's word and the bar's position are the same statement.
    private func workloadMeter(load: Int, status: WorkloadStatus) -> some View {
        let fullScale = max(1, WorkloadEngine.burnoutFloor)
        let clamped = max(0, min(fullScale, load))
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.backgroundTertiary)
                Capsule()
                    .fill(loadTint(for: status))
                    .frame(width: geo.size.width * CGFloat(clamped) / CGFloat(fullScale))
                ForEach(Self.loadBandEdges, id: \.self) { edge in
                    Rectangle()
                        .fill(Color.backgroundPrimary)
                        .frame(width: 1)
                        .offset(x: geo.size.width * CGFloat(edge) / CGFloat(fullScale))
                }
            }
        }
        .frame(height: 6)
    }

    /// The band edges the meter notches, read back out of the engine's own
    /// classifier rather than copied. `WorkloadEngine`'s thresholds are private
    /// and have already been re-measured once against the balance harness; a
    /// tick drawn from a literal here would be a tick that lies the next time
    /// they move.
    private static let loadBandEdges: [Int] = {
        let scale = max(1, WorkloadEngine.burnoutFloor)
        return (1..<scale).filter {
            WorkloadEngine.classify(load: $0) != WorkloadEngine.classify(load: $0 - 1)
        }
    }()

    /// Wide enough for the integer, the gap and a readable bar. Not `.leading`:
    /// it was the only leading-aligned column in an otherwise centred set, and
    /// `DSListRow` lays its columns out with zero gutter — so it abutted AGE on
    /// one side (7 pt between the two labels) and dumped all 93 pt of its slack
    /// on the other, which put the age number where it read as a label on the
    /// load meter.
    private let loadColumnWidth: CGFloat = 96

    // MARK: - Helpers

    /// The table's order. Load descending by default — the men this table
    /// exists to warn about have to be the men it shows, and it used to be
    /// `roster.prefix(30)` off an unsorted fetch, so on an 87-man camp roster
    /// the burnout could sit entirely inside the 57 rows that never rendered.
    ///
    /// Ties break on durability ascending in every column, not just load: when
    /// two men are level on the sorted figure, the thinner margin is the one
    /// worth reading first.
    private var displayRoster: [Player] {
        let ranked: [Player]
        switch sort.key {
        case .durability: ranked = ordered { Double($0.physical.durability) }
        case .stamina:    ranked = ordered { Double($0.physical.stamina) }
        case .age:        ranked = ordered { Double($0.age) }
        case .load:       ranked = ordered { Double($0.cumulativeLoad) }
        case .injury:
            // Computed once per player rather than once per comparison — the
            // risk resolves the club's medical wing, and a comparator is called
            // O(n log n) times.
            let risks = Dictionary(roster.map { ($0.id, injuryRiskPer100Snaps(for: $0)) }, uniquingKeysWith: { first, _ in first })
            ranked = ordered { risks[$0.id] ?? 0 }
        }
        return showAllWorkload ? ranked : Array(ranked.prefix(workloadPreviewLimit))
    }

    /// Ties break on durability, thinner margin first, in both directions:
    /// `dsSorted` reverses the whole comparator when a column runs descending,
    /// so the durability leg is written backwards there to survive the flip.
    /// Its own id tiebreak keeps the order total either way.
    private func ordered(by value: (Player) -> Double) -> [Player] {
        roster.dsSorted(sort.ascending, id: \.id) { lhs, rhs in
            let primary = dsCompare(value(lhs), value(rhs))
            guard primary == .orderedSame else { return primary }
            return sort.ascending
                ? dsCompare(lhs.physical.durability, rhs.physical.durability)
                : dsCompare(rhs.physical.durability, lhs.physical.durability)
        }
    }

    /// A truncated table has to say so, and say by what — and the "by what" is
    /// the live sort, so the label cannot claim load order while the GM is
    /// looking at an age sort.
    private var sortSummary: String {
        let column: String
        switch sort.key {
        case .durability: column = "DUR"
        case .stamina:    column = "STA"
        case .age:        column = "AGE"
        case .load:       column = "LOAD"
        case .injury:     column = "INJ"
        }
        return "\(column) \(sort.ascending ? "LOW FIRST" : "HIGH FIRST")"
    }

    private var workloadCountLabel: String {
        if showAllWorkload || roster.count <= workloadPreviewLimit {
            return "\(roster.count) PLAYERS · \(sortSummary)"
        }
        return "TOP \(workloadPreviewLimit) OF \(roster.count) BY \(sortSummary)"
    }

    private var totalIs100: Bool {
        tacticalPct + physicalPct + technicalPct == 100
    }

    /// The meter shares the pill's palette, so a row can never say "heavy" in
    /// orange next to a bar in yellow. `warning` moved to `alertOrange` for
    /// exactly this reason — P7's semantic hue separation. The risk figure used
    /// to borrow this too and no longer does; it has its own thresholds, on the
    /// note at `injuryTint`.
    private func loadTint(for status: WorkloadStatus) -> Color {
        Color.forStatus(workloadTone(for: status))
    }

    private func injuryCell(for player: Player) -> some View {
        let risk = injuryRiskPer100Snaps(for: player)
        return Text(String(format: "%.0f%%", risk))
            .font(DSType.display(11, .heavy))
            .foregroundStyle(injuryTint(for: risk))
            .accessibilityLabel(String(format: "Injury risk over a hundred snaps, %.0f percent", risk))
    }

    /// This player's chance of an injury over a hundred snaps.
    ///
    /// It used to be `WorkloadEngine.injuryRiskPct(baseRisk: 0.04)` — a base
    /// literal chosen in this view, and the only call site that function has in
    /// the app. Two things were wrong with it. Its durability term
    /// (`(99 − DUR)/99 × 0.4 + 1`, a 1.00–1.24 spread) is not the one the game
    /// rolls: `MedicalEngine.injuryCheck` weighs durability at `1 − DUR/200`,
    /// a 0.505–0.80 spread, nearly twice the leverage — so the column
    /// understated the single thing it existed to compare, and printed eleven
    /// values inside 0.3 of a point. And it had no period attached to a
    /// percentage: a camp week rolls no injury at all, so "4.6 %" answered a
    /// question the game never asks.
    ///
    /// A hundred snaps is the engine's own unit scaled to something a GM can
    /// hold — it rolls per play, and a hundred plays is about a game and a half
    /// for a starter. The base rate and the durability curve on the two lines
    /// below are the one copy this file makes of `MedicalEngine.injuryCheck`;
    /// fatigue, the camp-workload tax, the medical wing and the league's injury
    /// setting are all the engine's own values, called. Two terms are left out
    /// deliberately: the rush-back window needs the head trainer, and the
    /// weighted injury TYPE changes which injury, never how often.
    private func injuryRiskPer100Snaps(for player: Player) -> Double {
        var perSnap = 0.005 * career.injuryFrequency.riskMultiplier
        perSnap *= 1.0 + Double(max(0, player.fatigue - 50)) / 50.0
        perSnap *= 1.0 - Double(player.physical.durability) / 200.0
        perSnap *= MedicalEngine.workloadRiskMultiplier(player: player)
        perSnap *= MedicalEngine.facilityRiskMultiplier(player: player)
        let survivesAll = pow(1.0 - max(0.0, min(1.0, perSnap)), 100.0)
        return (1.0 - survivesAll) * 100.0
    }

    /// The risk gets its own thresholds, and not the pill's colour.
    ///
    /// It was tinted with `loadTint`, so the channel the eye reads first was
    /// the same green down all thirty rows while the numbers under it were not
    /// — the column read as noise beside the pill it was repeating. The rungs
    /// are anchored on what the formula can emit: a healthy camp spans roughly
    /// 22 % (a 99-durability body) to 33 % (the 40-durability floor), an
    /// overloaded man multiplies his per-snap odds by 1.6 and a burnt-out one
    /// by 2.5. Green is therefore a durable body, and orange and red are only
    /// reachable by working a man past healthy.
    private func injuryTint(for pct: Double) -> Color {  // ds-lint:allow(ratingfn) a probability, not a 0-99 rating — and high is BAD here, which inverts forRating
        switch pct {
        case ..<26:  return Color.success
        case ..<34:  return Color.warning
        case ..<45:  return Color.alertOrange
        default:     return Color.danger
        }
    }

    /// A 40-99 attribute in the row's numeric voice, on the same rating palette
    /// the OVR under the name uses.
    private func ratingCell(_ value: Int) -> some View {
        Text("\(value)")
            .font(DSType.display(11, .semibold))
            .foregroundStyle(Color.forRating(value))
    }

    /// Derived, never stored — dragging a slider one point off a preset drops
    /// the highlight on its own, so the chip row can never claim a split the
    /// sliders no longer hold.
    private var activePreset: Preset? {
        Preset.allCases.first { preset in
            let alloc = preset.allocation
            return alloc.tactical == tacticalPct
                && alloc.physical == physicalPct
                && alloc.technical == technicalPct
        }
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

    /// The last plan the engine actually ran this season.
    ///
    /// Ordered by phase, not by week: the three camp ticks sit one phase apart
    /// and `overallOrdinal` is what puts OTAs before camp before preseason. Any
    /// row stamped with a phase that runs no pass is skipped — those are the
    /// dead writes this screen used to make, and a save from an old build must
    /// not be shown as something that ran.
    private func fetchLastAppliedPlan() -> TrainingPlan? {
        guard let teamID = career.teamID else { return nil }
        let season = career.currentSeason
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> {
                $0.teamID == teamID && $0.seasonYear == season
            }
        )
        let plans = (try? modelContext.fetch(descriptor)) ?? []
        return plans
            .compactMap { plan -> (plan: TrainingPlan, phase: SeasonPhase)? in
                guard let phase = SeasonPhase(rawValue: plan.phaseRaw),
                      TrainingPlanEngine.runsDevelopmentPass(in: phase) else { return nil }
                return (plan, phase)
            }
            .max { $0.phase.overallOrdinal < $1.phase.overallOrdinal }
            .map(\.plan)
    }

    /// Seeds the sliders from the saved plan so the editor reflects what the
    /// engine will actually use (instead of always resetting to 34/33/33).
    ///
    /// Once camp is spent there is no plan for this phase to fetch — the key
    /// this screen would write is one nothing reads — so it shows the last
    /// split that DID run instead. Falling back to a fresh 34/33/33 there would
    /// be the same lie in a quieter voice: a split the GM never chose, printed
    /// as though it had happened.
    private func loadExistingPlan() {
        guard planRunsThisPhase else {
            guard let last = fetchLastAppliedPlan() else { return }
            seedSliders(from: last)
            bankedPlanPhase = SeasonPhase(rawValue: last.phaseRaw)
            return
        }
        guard let existing = fetchExistingPlan() else { return }
        seedSliders(from: existing)
        didSave = true
    }

    private func seedSliders(from plan: TrainingPlan) {
        tacticalPct = plan.tacticalPct
        physicalPct = plan.physicalPct
        technicalPct = plan.technicalPct
    }

    private func save() {
        // The bar offers no button outside a pass phase; this is the second
        // lock, so a future call site cannot reintroduce the dead write.
        guard planRunsThisPhase, let teamID = career.teamID else { return }
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
