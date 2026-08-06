import SwiftUI
import SwiftData

// MARK: - Private Workouts, as a batch instrument (#120)
//
// The workout stage shipped as a list with an Invite button welded onto every
// row: one tap, one man, one modal, thirty times over. That is the same defect
// the film-study stage had (#119), and the interview room never had it —
// bringing twelve men in is ONE decision a staff makes once, not twelve
// identical decisions made a row at a time, each silently spending a slot and
// each interrupting the list with a sheet nobody asked to open.
//
// This screen is the interview room's shape over the workout ration: pick the
// men, read what the batch will spend, run it once, read one report. The parts
// are deliberately the same parts `InterviewSelectionView` and
// `FilmStudySelectionView` use — the capsule action bar carrying Select All
// Recommended and Deselect All, the "N/M selected" progress line, one prominent
// run bar that states its own reason when it is dead, a ranked card report, and
// a steady state that is the saved report with NO call to action once the
// ration is spent (#118).
//
// ## One economy, unchanged
//
// `career.workoutsUsed` out of `DraftPrepProgress.workoutSlots` — the same
// counter the prospect card bills and the same one `DraftPrepProgress` reads to
// decide whether this stage is worked. Nothing about the price moved: a workout
// costs one slot and no money, the engine call is still
// `ScoutingEngine.conductPersonalWorkout`, and the mutation still goes through
// `DraftClassMutator`, once for the whole batch instead of once per man. The
// counter is incremented for men who ACTUALLY worked out — the loop can skip a
// man who has left the class — and never for a man who is merely selected.

/// The `.workouts` stage: a Big-Board-shaped list of men you can bring in for a
/// private session, and one report that says what the sessions bought.
///
/// **One economy.** `career.workoutsUsed` / `DraftPrepProgress.workoutSlots`,
/// the same counter the prospect card bills. The screen this replaces ran a
/// second, parallel workout economy: a
/// `@CareerScopedStorage("personalWorkoutsUsed")` counter capped at 10, spent
/// through `ScoutingEngine.attendProDay` — a whole-school pro day for the man's
/// college — while `ProspectDetailView` billed the same action to
/// `career.workoutsUsed` / 30 through `conductPersonalWorkout`. Two caps, two
/// engines, one feature (F7). Both the counter and the misuse are gone.
struct WorkoutsTabView: View {
    let career: Career
    let prospects: [CollegeProspect]
    let teamRoster: [Player]
    @Binding var positionFilter: ProspectPositionFilter
    /// Whether the club may work this stage, decided ONCE by
    /// ``DraftPrepProgress/canAct(_:)`` and handed down — the same predicate the
    /// hub's process bar draws this stage's puck from, so an `.open` cell can
    /// never lead to a screen of dead buttons.
    let canAct: Bool
    var onRefresh: () -> Void

    @Environment(\.modelContext) private var modelContext
    @CareerScopedStorage("prospectCustomBoard") private var prospectCustomBoardJSON: String = "[]"

    @State private var boardRanks: [UUID: Int] = [:]
    /// Fog-safe grade rank per prospect, computed once per refresh. Sorting on
    /// `ProspectFog.rank` directly would re-read the fog O(n log n) times per
    /// body evaluation — the same shape of mistake as F6, one layer up.
    @State private var fogRanks: [UUID: Int] = [:]
    @State private var teamNeeds: Set<Position> = []
    @State private var coaches: [Coach] = []
    @State private var candidates: [CollegeProspect] = []
    /// Every workout this club has filed this cycle, snapshotted at refresh.
    ///
    /// Rebuilt from the `.personalWorkout` reports stamped on the prospects
    /// rather than remembered from the run that produced them, so the report
    /// survives a tab switch and a relaunch exactly like the interview tab's
    /// saved report does. Cached in `@State` for the same reason `fogRanks` is:
    /// walking the class and its report arrays on every body evaluation is the
    /// mistake this file already carries a comment about.
    @State private var filedEntries: [WorkoutReportEntry] = []

    @State private var searchText = ""
    @State private var sort: WorkoutSort = .board
    @State private var boardOnly = true
    @State private var showAll = false

    // MARK: - Batch state

    @State private var selectedIDs: Set<UUID> = []
    /// The one sheet this screen can have open. See ``WorkoutsSheet``.
    @State private var activeSheet: WorkoutsSheet?
    /// Set when the user explicitly opens the filed report while slots remain.
    @State private var viewingFiledReport = false

    private static let rowsBeforeFold = 25

    enum WorkoutSort: String, CaseIterable, Identifiable {
        case board = "My board"
        case grade = "Grade"
        case position = "Position"
        var id: String { rawValue }
    }

    /// The screen's single sheet slot.
    ///
    /// An enum rather than a boolean even though there is one case today: the
    /// hub, the prospect card and the pro-day tour each shipped with two stacked
    /// `.sheet(isPresented:)` on one node, SwiftUI honoured only the last, and
    /// three separate buttons opened the wrong sheet or nothing at all. One
    /// `item:` slot makes "two sheets at once" unrepresentable.
    enum WorkoutsSheet: Identifiable {
        /// What a just-run batch of workouts found.
        case batchReport(WorkoutBatch)

        var id: String {
            switch self {
            case .batchReport: return "batchReport"
            }
        }
    }

    // MARK: - Stage

    private var stage: DraftPrepStep { career.prepStep }
    private var isStageLocked: Bool { !canAct }

    private var used: Int { career.workoutsUsed }
    private var remaining: Int { max(0, DraftPrepProgress.workoutSlots - used) }

    // MARK: - Rows

    private var filtered: [CollegeProspect] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return candidates.filter { prospect in
            guard positionFilter.matches(prospect.position) else { return false }
            guard !boardOnly || prospect.userMark.isBoardPositive else { return false }
            guard !query.isEmpty else { return true }
            return prospect.fullName.lowercased().contains(query)
                || prospect.college.lowercased().contains(query)
        }
    }

    private var sorted: [CollegeProspect] {
        switch sort {
        case .board:
            return filtered.sorted { a, b in
                let aRank = boardRanks[a.id] ?? Int.max
                let bRank = boardRanks[b.id] ?? Int.max
                if aRank != bRank { return aRank < bRank }
                return (fogRanks[a.id] ?? 0) > (fogRanks[b.id] ?? 0)
            }
        case .grade:
            return filtered.sorted { (fogRanks[$0.id] ?? 0) > (fogRanks[$1.id] ?? 0) }
        case .position:
            return filtered.sorted { a, b in
                a.position.rawValue == b.position.rawValue
                    ? (fogRanks[a.id] ?? 0) > (fogRanks[b.id] ?? 0)
                    : a.position.rawValue < b.position.rawValue
            }
        }
    }

    private var visible: [CollegeProspect] {
        showAll || !searchText.isEmpty ? sorted : Array(sorted.prefix(Self.rowsBeforeFold))
    }

    // MARK: - Selection maths
    //
    // One limit here, unlike film study's two: the workout costs a slot and no
    // money. The cap is therefore exactly the slots left in the cycle, and it
    // moves as the selection does — deselecting a man gives his slot back.

    /// The men the run bar would actually bring in, resolved from the UNFILTERED
    /// candidate pool rather than the visible list: a man selected before the
    /// user typed in the search box is still selected, and dropping him silently
    /// because a filter now hides him would spend a different batch than the one
    /// the button counted.
    private var selectedProspects: [CollegeProspect] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    private func canAdd(_ prospect: CollegeProspect) -> Bool {
        selectedIDs.count < remaining
    }

    private func toggle(_ prospect: CollegeProspect) {
        if selectedIDs.contains(prospect.id) {
            selectedIDs.remove(prospect.id)
        } else if canAdd(prospect) {
            selectedIDs.insert(prospect.id)
        }
    }

    /// Who "Select All Recommended" means on this screen.
    ///
    /// The tab already carried a notion of worth and it is the ONE mark: the
    /// board filter above the list keys off `userMark.isBoardPositive`, and the
    /// default "My board" sort orders by the user's own custom board. So the
    /// recommendation is *the men you have already called Elite or Target*, in
    /// whatever order the current sort is showing them — a private workout is
    /// the instrument you point at men you are already serious about, not a way
    /// to discover new ones.
    ///
    /// A board with no marks falls back to the men the user has RANKED (the
    /// custom board), because "the button did nothing" is the worse failure.
    /// With neither, the capsule does not appear at all rather than guessing
    /// from a list the user has never expressed an opinion about.
    private var recommendedProspects: [CollegeProspect] {
        let marked = sorted.filter { $0.userMark.isBoardPositive }
        if !marked.isEmpty { return marked }
        return sorted.filter { boardRanks[$0.id] != nil }
    }

    /// The capsule's visibility test alone. `recommendedProspects` re-sorts the
    /// class to answer it, and the header asks on every body pass — a full
    /// O(n log n) per checkbox tap for a yes/no (#120 review F8). Membership
    /// does not need order.
    private var hasRecommended: Bool {
        candidates.contains { $0.userMark.isBoardPositive || boardRanks[$0.id] != nil }
    }

    /// Fills the selection from `recommendedProspects`, in the list's own order,
    /// stopping at the remaining slots.
    private func selectAllRecommended() {
        let picks = recommendedProspects
            .filter { !selectedIDs.contains($0.id) }
            .prefix(max(0, remaining - selectedIDs.count))
        guard !picks.isEmpty else { return }

        let visibleIDs = Set(visible.map(\.id))
        for prospect in picks { selectedIDs.insert(prospect.id) }

        // A selected man the 25-row fold is hiding is a lie about what the run
        // bar will do, so filling the selection unfolds the list.
        if picks.contains(where: { !visibleIDs.contains($0.id) }) { showAll = true }
    }

    // MARK: - Gate
    //
    // Every blocked case carries the sentence the run bar prints. A dead control
    // that does not say why is the bug this whole wave exists to stop repeating.

    /// Why the batch cannot be run, or `nil` when it can.
    private var blockedReason: String? {
        if !canAct { return "Private workouts open at that stage" }
        if remaining == 0 {
            return "All \(DraftPrepProgress.workoutSlots) workout slots are spent this cycle"
        }
        if candidates.isEmpty { return "Nobody left to bring in" }
        if selectedIDs.isEmpty { return "Select Men to Bring In" }
        return nil
    }

    // MARK: - The room

    /// The eye the building puts on the whole batch.
    ///
    /// Best `scoutingAbility` on staff, because that is literally the number
    /// `ScoutingEngine.conductPersonalWorkout` reads to size the error bars. The
    /// report names him so the user knows whose read he is buying.
    private var leadEvaluator: Coach? {
        coaches.max { $0.scoutingAbility < $1.scoutingAbility }
    }

    /// "HC Bill Cowher" — `nil` until the staff has loaded, so the header does
    /// not flash a placeholder name.
    private var leadEvaluatorName: String? {
        leadEvaluator.map { "\($0.role.abbreviation) \($0.fullName)" }
    }

    /// "Private Workouts · 2027" — instrument plus season, so a report read back
    /// in April still says when the sessions happened.
    private var occasionLabel: String {
        "Private Workouts \u{00B7} " + String(career.currentSeason)
    }

    /// The filed workouts as one report payload.
    private var filedBatch: WorkoutBatch {
        WorkoutBatch(
            entries: filedEntries,
            staffName: leadEvaluatorName ?? "your coaching staff",
            occasion: occasionLabel,
            slotsUsed: used,
            slotsLeft: remaining
        )
    }

    // MARK: - Body

    var body: some View {
        Group {
            if isStageLocked {
                lockedState
            } else if viewingFiledReport && !filedEntries.isEmpty {
                // Explicitly requested while slots remain.
                savedReport(dismissTitle: "Back to the Invite List") {
                    viewingFiledReport = false
                    refresh()
                }
            } else if remaining == 0 && !filedEntries.isEmpty {
                // STEADY STATE. The ration is spent and the report IS this tab,
                // so there is no run bar and no "complete review" CTA:
                // dismissing would re-render this same screen, and a gold call
                // to action weeks after the stage closed reads as a required
                // action the user is failing (#118).
                savedReport(dismissTitle: nil, onDismiss: nil)
            } else {
                workoutList
            }
        }
        .task { refresh() }
        // ONE sheet modifier, over an `item:` slot.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case let .batchReport(batch):
                NavigationStack {
                    ZStack {
                        Color.backgroundPrimary.ignoresSafeArea()
                        WorkoutBatchReportView(batch: batch)
                    }
                    .navigationTitle("Workout Report")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarColorScheme(.dark, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { activeSheet = nil }
                        }
                    }
                }
            }
        }
    }

    private var lockedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 44))
                .foregroundStyle(Color.textTertiary)
            Text("Workouts Have Not Opened")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text("Private workouts run after the pro-day circuit \u{2014} you bring a man in once you know who is worth the trip. You are at: \(stage.displayName).")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The filed report, with the way back out under it.
    ///
    /// `dismissTitle` present = the user opened this himself and needs a door
    /// back to the list. Absent = this is the STEADY STATE and the report gets
    /// no bar of its own at all: the only remaining action is closing the stage,
    /// and the hub already pins `DraftPrepAdvanceBar` under this tab whenever it
    /// is the stage the club is standing in. A second gold bar saying the same
    /// thing is #118 wearing a different label.
    private func savedReport(dismissTitle: String?, onDismiss: (() -> Void)?) -> some View {
        VStack(spacing: 0) {
            WorkoutBatchReportView(batch: filedBatch, isSavedReport: true)

            if let dismissTitle, let onDismiss {
                Button(action: onDismiss) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text(dismissTitle)
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentBlue))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var workoutList: some View {
        List {
            controlsSection
            selectionSection
            rowsSection
            if canAct { advanceSection }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        // The run bar is pinned rather than scrolled: it carries the count the
        // user is building, and a total that scrolls away is a total he cannot
        // check while he is still picking.
        .safeAreaInset(edge: .bottom) { runBar }
    }

    // Explainer deleted: the hub pins ONE canonical `DraftPrepStageExplainer`
    // above every stage screen — what the stage reveals on a prospect, what it
    // costs, and its DONE / CURRENT / LOCKED state. A second hand-written
    // version inside the list said the same thing in different words and cost a
    // section of scroll.

    private var controlsSection: some View {
        Section {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                TextField("Search prospects or schools", text: $searchText)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }

            HStack(spacing: 10) {
                Toggle(isOn: $boardOnly) {
                    Text("Only men on my board")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .toggleStyle(.switch)
                .tint(Color.accentGold)

                Spacer()

                Menu {
                    ForEach(WorkoutSort.allCases) { option in
                        Button {
                            sort = option
                        } label: {
                            if sort == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption2)
                        Text(sort.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Color.accentBlue)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Selection bar
    //
    // The mass-selection row, in the same place and the same style as the
    // interview tab's and the film tab's. Bringing twelve men in one checkbox at
    // a time is the chore this screen exists to delete; leaving the SELECTION as
    // twelve taps would have moved the chore rather than removed it.

    private var selectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(selectedIDs.count)/\(remaining) selected")
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(selectedIDs.isEmpty ? Color.textSecondary : Color.textPrimary)

                    Spacer()

                    // Surfaces the workouts already filed so the stage's report
                    // can be read mid-cycle, before the slots run out.
                    if !filedEntries.isEmpty {
                        Button {
                            viewingFiledReport = true
                        } label: {
                            capsuleLabel(
                                "View Report (\(filedEntries.count))",
                                icon: "doc.text.magnifyingglass",
                                tint: Color.accentBlue
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if hasRecommended && remaining > 0 {
                        Button {
                            selectAllRecommended()
                        } label: {
                            capsuleLabel("Select All Recommended", icon: nil, tint: Color.accentGold)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Fills the selection from the men on your board until the slots run out")
                    }

                    if !selectedIDs.isEmpty {
                        Button {
                            selectedIDs.removeAll()
                        } label: {
                            capsuleLabel("Deselect All", icon: nil, tint: Color.textSecondary, muted: true)
                        }
                        .buttonStyle(.plain)
                    }
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.backgroundTertiary)
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(selectedIDs.isEmpty ? Color.textTertiary : Color.accentBlue)
                            .frame(
                                width: remaining > 0
                                    ? geo.size.width * CGFloat(selectedIDs.count) / CGFloat(remaining)
                                    : 0,
                                height: 6
                            )
                    }
                }
                .frame(height: 6)

                Text("NFL clubs bring in 15\u{2013}25 men for private work. A session costs a slot and no money.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.vertical, 2)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// The action-bar capsule, in the interview tab's exact dimensions.
    /// `muted` is the secondary treatment Deselect All wears there — a grey
    /// chip rather than a tinted one, so the two primary actions read first.
    private func capsuleLabel(_ text: String, icon: String?, tint: Color, muted: Bool = false) -> some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(muted ? Color.backgroundTertiary : tint.opacity(0.12)))
    }

    private var rowsSection: some View {
        Section {
            if visible.isEmpty {
                Text(boardOnly
                     ? "Nobody on your board is still un-worked. Turn off the board filter to see the rest of the class."
                     : "Nobody left to bring in.")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(visible) { prospect in
                    workoutRow(prospect)
                }
                if !showAll && searchText.isEmpty && sorted.count > Self.rowsBeforeFold {
                    Button { showAll = true } label: {
                        Text("Show all \(sorted.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Label("PRIVATE WORKOUTS", systemImage: "dumbbell.fill")
                    .foregroundStyle(Color.accentBlue)
                Spacer()
                Text("\(used) / \(DraftPrepProgress.workoutSlots) used \u{2022} \(remaining) left")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(remaining == 0 ? Color.danger : Color.textSecondary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// One selectable man.
    ///
    /// The row body is the selection toggle — the Invite button that used to sit
    /// on the trailing edge is gone, because the batch bar is the only thing
    /// that spends a slot now. The two controls the interview list keeps beside
    /// its checkbox are kept here for the same reason: the mark menu, so an
    /// opinion can be recorded without leaving the list, and a route to the
    /// man's card, so "who is this" does not cost the user his selection.
    private func workoutRow(_ prospect: CollegeProspect) -> some View {
        let read = ProspectFog.read(prospect)
        let isSelected = selectedIDs.contains(prospect.id)
        let selectable = isSelected || (canAct && canAdd(prospect))

        return HStack(spacing: 6) {
            ProspectMarkButton(
                prospect: prospect,
                onChange: { try? modelContext.save() }
            )
            .frame(width: 34)

            Button {
                toggle(prospect)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(isSelected ? Color.accentBlue : Color.textTertiary)
                        .frame(width: 20)

                    Text(boardRanks[prospect.id].map { "#\($0)" } ?? "--")
                        .font(.system(size: 10, weight: .heavy).monospacedDigit())
                        .foregroundStyle((boardRanks[prospect.id] ?? 999) <= 10 ? Color.accentGold : Color.textTertiary)
                        .frame(width: 26, alignment: .trailing)

                    Text(prospect.position.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 28, height: 18)
                        .background(positionColor(prospect.position), in: RoundedRectangle(cornerRadius: 3))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(prospect.fullName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                                .lineLimit(1)
                            if prospect.userMark != .none {
                                ProspectMarkChip(mark: prospect.userMark)
                            }
                        }
                        HStack(spacing: 6) {
                            Text(read.text)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(read.source.tint)
                            Text(prospect.college)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                            if teamNeeds.contains(prospect.position) {
                                Text("NEED")
                                    .font(.system(size: DSType.Size.micro, weight: .black))
                                    .foregroundStyle(Color.danger)
                            }
                            // A blocked row says WHY on the row rather than
                            // going quietly grey. (`!canAct` never reaches a
                            // row — the locked screen replaces the whole list
                            // — so the only reason left is the ration.)
                            if !selectable {
                                Text("No slots left in this batch")
                                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                                    .foregroundStyle(Color.warning)
                            }
                        }
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // NOT `.disabled` — a disabled Button stops consuming the touch,
            // and the tap falls through the List cell into the chevron's
            // NavigationLink: fill the last slot and every remaining row
            // becomes a surprise navigation push. The button stays live and
            // `toggle` refuses over-cap adds itself (#120 review F5).
            .opacity(selectable ? 1.0 : 0.55)
            .accessibilityLabel("\(prospect.fullName), \(prospect.position.rawValue), \(prospect.college)")
            .accessibilityValue(isSelected ? "Selected for a private workout" : read.accessibilityText)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])

            NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 24, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(prospect.fullName)'s card")
        }
        .padding(.vertical, 2)
        .contextMenu {
            ProspectGradeContextMenu(
                prospect: prospect,
                onChange: { try? modelContext.save() }
            )
        }
    }

    // MARK: - Run bar

    private var runBar: some View {
        let reason = blockedReason
        let blocked = reason != nil
        return Button {
            runBatch()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: canAct ? "dumbbell.fill" : "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(reason ?? "Run Private Workouts (\(selectedIDs.count))")
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(blocked ? Color.textTertiary : Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(blocked ? Color.backgroundTertiary.opacity(0.5) : Color.accentBlue)
            )
        }
        .disabled(blocked)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var advanceSection: some View {
        Section {
            advanceButton
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private var advanceButton: some View {
        Button { advanceStage() } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.backgroundPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(used > 0 ? "Done with the workouts" : "Skip the workouts")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.backgroundPrimary)
                    Text(used > 0
                         ? (used == 1 ? "1 man worked out for your staff" : "\(used) men worked out for your staff")
                         : "Nobody works out for your staff this cycle")
                        .font(.caption)
                        .foregroundStyle(Color.backgroundPrimary.opacity(0.8))
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.backgroundPrimary)
            }
            .padding(12)
            .background(Color.accentBlue, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    /// The batch: one pass through the chokepoint, billed once per man who
    /// actually worked out, persisted once at the end.
    ///
    /// The persistence is the single-invite path's, unchanged and done once
    /// instead of N times: `DraftClassMutator.mutate` writes the canonical class,
    /// calls `WeekAdvancer.persistDraftClass` and saves the context, and the
    /// slot counter is written straight after with its own `save()`. Both halves
    /// are load-bearing — without the mutator the sessions are forgotten on
    /// relaunch, and without the counter the ration never runs down.
    ///
    /// Every guard the run bar applied is re-applied here. The button is the UI;
    /// this is the ration, and `career.workoutsUsed` is evidence
    /// `DraftPrepProgress` reads to decide this stage is worked.
    private func runBatch() {
        guard canAct, blockedReason == nil else { return }

        // Re-clamped against the live counter: the slot ledger is shared state
        // the prospect card spends too, so the selection may have been sized
        // against a number that has since moved.
        let targets = Array(selectedProspects.prefix(remaining))
        guard !targets.isEmpty else { return }

        var entries: [WorkoutReportEntry] = []
        let applied = DraftClassMutator.mutate(modelContext) { klass in
            for target in targets {
                guard let index = klass.firstIndex(where: { $0.id == target.id }) else { continue }
                let prospect = klass[index]
                // The card's own workout button spends this same ration, and a
                // stale candidate list can still show a man it already worked
                // out. `conductPersonalWorkout` is not idempotent — a second
                // run files a second report and re-rolls his read — so the
                // gate predicate is re-asked HERE, where the money moves.
                guard !ScoutingEngine.hasWorkedOutPrivately(prospect) else { continue }
                let result = ScoutingEngine.conductPersonalWorkout(prospect: prospect, coaches: coaches)
                entries.append(WorkoutReportEntry(prospect: prospect, result: result))
            }
        }

        // `mutate` returns false when there is no class in memory. Nothing
        // happened, so nothing is charged and nothing is claimed.
        guard applied, !entries.isEmpty else { return }

        // ONE increment per session that actually ran — never per selection.
        career.workoutsUsed += entries.count
        try? modelContext.save()

        let batch = WorkoutBatch(
            entries: entries,
            staffName: leadEvaluatorName ?? "your coaching staff",
            occasion: occasionLabel,
            slotsUsed: career.workoutsUsed,
            slotsLeft: max(0, DraftPrepProgress.workoutSlots - career.workoutsUsed)
        )

        selectedIDs.removeAll()
        refresh()
        onRefresh()
        activeSheet = .batchReport(batch)
    }

    private func advanceStage() {
        guard canAct else { return }
        career.advancePrepStep(to: .mockOne)
        try? modelContext.save()
        onRefresh()
    }

    // MARK: - Refresh

    private func refresh() {
        let ids = (try? JSONDecoder().decode([String].self, from: Data(prospectCustomBoardJSON.utf8))) ?? []
        var ranks: [UUID: Int] = [:]
        ranks.reserveCapacity(ids.count)
        for (index, raw) in ids.enumerated() {
            if let uuid = UUID(uuidString: raw) { ranks[uuid] = index + 1 }
        }
        boardRanks = ranks
        teamNeeds = Set(DraftEngine.topTeamNeeds(roster: teamRoster, limit: 5))

        // The gate is "has this man already been worked out privately", and the
        // record of that is the filed `.personalWorkout` report — the same thing
        // the board's work-up column reads.
        //
        // It used to be `proDayCompleted`, which is wrong by construction now
        // that the stages are adjacent and forced: `attendProDay` flips that
        // flag for EVERY declared man at every focused school, so the tour
        // deleted its own targets out of the very next stage. Reserve five
        // schools, send the department out, advance to Workouts — and every man
        // the trip was for was missing from the list and greyed out on his card.
        candidates = prospects.filter {
            $0.isDeclaringForDraft && !ScoutingEngine.hasWorkedOutPrivately($0)
        }

        // A selection may not outlive the men in it: anyone worked out by this
        // batch (or from his own card) is no longer a candidate, and a stale ID
        // in the set would keep counting against the cap forever.
        let candidateIDs = Set(candidates.map(\.id))
        selectedIDs.formIntersection(candidateIDs)

        var fog: [UUID: Int] = [:]
        fog.reserveCapacity(candidates.count)
        for prospect in candidates { fog[prospect.id] = ProspectFog.rank(prospect) }
        fogRanks = fog

        // The receipt for a workout is the `.personalWorkout` report the session
        // files — the same predicate `hasWorkedOutPrivately` gates the candidate
        // list with, so a man is in exactly one of the two lists and never both.
        filedEntries = prospects.compactMap { prospect -> WorkoutReportEntry? in
            guard let report = prospect.scoutingReports.last(where: { $0.phase == .personalWorkout })
            else { return nil }
            return WorkoutReportEntry(filed: prospect, report: report)
        }

        if coaches.isEmpty, let teamID = career.teamID {
            let descriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
            coaches = (try? modelContext.fetch(descriptor)) ?? []
        }
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }
}

// MARK: - Report model
//
// Value types, deliberately. The report outlives the mutation that produced it,
// and holding `@Model` references across that boundary is how a result screen
// ends up re-reading a prospect who has moved on. Everything the report prints
// is snapshotted at the moment the session was filed.

/// One man's line in a workout report.
struct WorkoutReportEntry: Identifiable {
    let id = UUID()
    let prospectName: String
    let position: Position
    let college: String
    /// The band the user was looking at when he spent the slot. `nil` on a saved
    /// report — the previous band is not stored anywhere, and inventing one
    /// would be a fabrication dressed as intel.
    let bandBefore: GradeRange?
    let bandAfter: GradeRange?
    /// How he fits what the coordinators run.
    let schemeFitNote: String?
    /// The room's read on the man, when the staff got one (85 % of the time).
    let personalityNote: String?
    /// Position strengths and weaknesses the session surfaced.
    let impressions: [String]
    /// What is on his medical and his background — the same two lists the
    /// single-workout sheet has always shown under the session's own findings.
    let medicalConcerns: [String]
    let redFlags: [String]

    /// Ranking key: the post-workout band. Fog-safe by construction — a letter
    /// band, never a stored attribute.
    var rank: Int { bandAfter?.midGrade.rank ?? 0 }

    /// Whether the session visibly moved the band.
    var bandMoved: Bool {
        guard let before = bandBefore, let after = bandAfter else { return bandAfter != nil }
        return before != after
    }

    /// A session that just ran.
    init(prospect: CollegeProspect, result: ScoutingEngine.WorkoutResult) {
        self.prospectName = prospect.fullName
        self.position = prospect.position
        self.college = prospect.college
        self.bandBefore = result.gradeBefore
        self.bandAfter = result.gradeAfter
        self.schemeFitNote = Self.nonEmpty(result.schemeFitNote)
        self.personalityNote = Self.nonEmpty(result.personalityNote)
        self.impressions = result.impressions
        self.medicalConcerns = prospect.medicalConcerns ?? []
        self.redFlags = prospect.redFlags ?? []
    }

    /// A session filed earlier this cycle, rebuilt from its `.personalWorkout`
    /// report. The report merges the personality read and the scheme-fit note
    /// into one `personalityNotes` string, so the saved card prints them as the
    /// single line they were stored as rather than pretending to split them.
    init(filed prospect: CollegeProspect, report: ScoutingReport) {
        self.prospectName = prospect.fullName
        self.position = prospect.position
        self.college = prospect.college
        self.bandBefore = nil
        // Fogged, not stored: the widened band the rest of the app prints for
        // this man. The stored range reads more certain than the department is
        // — the exact drift CombineResultsView's GRD cell was fixed for.
        let read = ProspectFog.read(prospect)
        self.bandAfter = read.source == .scouts ? read.band : nil
        self.schemeFitNote = nil
        self.personalityNote = Self.nonEmpty(report.personalityNotes)
        self.impressions = [report.strengthNotes, report.weaknessNotes]
            .compactMap { Self.nonEmpty($0) }
        self.medicalConcerns = prospect.medicalConcerns ?? []
        self.redFlags = prospect.redFlags ?? []
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}

/// Everything one batch of private workouts (or one cycle of them) bought.
struct WorkoutBatch: Identifiable {
    let id = UUID()
    let entries: [WorkoutReportEntry]
    /// Whose eye the sessions were run under.
    let staffName: String
    /// "Private Workouts · 2027".
    let occasion: String
    /// Workout slots spent this cycle after the batch.
    let slotsUsed: Int
    /// Workout slots left in the cycle after the batch.
    let slotsLeft: Int
}

// MARK: - Batch report view

/// What the batch bought, ranked by the band each man came out with.
///
/// Built from `WorkoutResultSheet`'s parts — the before → after grade columns,
/// the bulleted "what the staff saw" list, the medical and flags labels — so one
/// workout and twelve workouts report in the same voice. Rendered inside a sheet
/// after a batch, and inline as the tab's steady state once the ration is spent.
struct WorkoutBatchReportView: View {
    let batch: WorkoutBatch
    /// `true` when this is the cycle's saved summary rather than a just-run
    /// batch. Suppresses the before → after row (there is no stored "before")
    /// and re-words the header.
    var isSavedReport: Bool = false

    private var rankedEntries: [WorkoutReportEntry] {
        batch.entries.sorted { $0.rank > $1.rank }
    }

    var body: some View {
        VStack(spacing: 0) {
            reportHeader
            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            ScrollView {
                LazyVStack(spacing: 12) {
                    summarySection
                    ForEach(Array(rankedEntries.enumerated()), id: \.element.id) { index, entry in
                        entryCard(entry, rank: index + 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    // MARK: - Header

    private var reportHeader: some View {
        HStack {
            Text(isSavedReport ? "WORKOUTS \u{2014} THIS CYCLE" : "WORKOUT REPORT")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.accentBlue)
                .tracking(0.5)

            Spacer()

            Text("\(batch.entries.count) workout\(batch.entries.count == 1 ? "" : "s") run")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SUMMARY")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.accentBlue)
                .tracking(0.5)

            HStack(spacing: 12) {
                summaryPill(
                    icon: "dumbbell.fill",
                    text: "\(batch.entries.count) worked out under \(batch.staffName)",
                    color: .accentBlue
                )
                summaryPill(icon: "calendar", text: batch.occasion, color: .textSecondary)
            }

            HStack(spacing: 12) {
                summaryPill(
                    icon: "gauge.with.dots.needle.33percent",
                    text: "\(batch.slotsUsed) of \(DraftPrepProgress.workoutSlots) slots used \u{2022} \(batch.slotsLeft) left",
                    color: batch.slotsLeft == 0 ? .danger : .textSecondary
                )
                if flaggedCount > 0 {
                    summaryPill(
                        icon: "exclamationmark.triangle.fill",
                        text: "\(flaggedCount) with medical or background notes",
                        color: .warning
                    )
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentBlue.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentBlue.opacity(0.2))
                )
        )
    }

    private var flaggedCount: Int {
        batch.entries.filter { !$0.medicalConcerns.isEmpty || !$0.redFlags.isEmpty }.count
    }

    private func summaryPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Card

    private func entryCard(_ entry: WorkoutReportEntry, rank: Int) -> some View {
        let isTop = rank == 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("#\(rank)")
                    .font(.system(size: 14, weight: .heavy).monospacedDigit())
                    .foregroundStyle(isTop ? Color.accentGold : Color.textTertiary)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.prospectName)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text(entry.position.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.accentBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentBlue.opacity(0.15)))
                    }
                    Text(entry.college)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer()

                VStack(spacing: 1) {
                    Text(entry.bandAfter?.displayText ?? "\u{2014}")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(gradeColor(entry.bandAfter))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Band")
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(width: 58)
            }

            // Before → after, the single-workout sheet's grade section in one
            // line. Suppressed on a saved report and on a man nobody had filed
            // on, so the row only appears when it has something true to say.
            if !isSavedReport, let after = entry.bandAfter {
                HStack(spacing: 6) {
                    Image(systemName: entry.bandBefore == nil
                          ? "eye.fill"
                          : (entry.bandMoved ? "arrow.triangle.branch" : "equal.circle"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Text(entry.bandBefore?.displayText ?? "No read")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: DSType.Size.micro))
                        .foregroundStyle(Color.textTertiary)
                    Text(after.displayText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(gradeColor(after))
                }
            }

            if let fit = entry.schemeFitNote {
                noteRow(icon: "square.grid.3x3.fill", tint: .accentBlue,
                        title: "Scheme fit", body: fit)
            }
            if let personality = entry.personalityNote {
                noteRow(icon: "person.fill", tint: .accentGold,
                        title: "The room", body: personality)
            }

            if !entry.impressions.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("What the staff saw")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(0.4)
                    ForEach(entry.impressions, id: \.self) { line in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                                .foregroundStyle(Color.accentBlue)
                                .padding(.top, 5)
                            Text(line)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
            }

            if !entry.medicalConcerns.isEmpty || !entry.redFlags.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.medicalConcerns, id: \.self) { concern in
                        Label(concern, systemImage: "cross.case.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.warning)
                    }
                    ForEach(entry.redFlags, id: \.self) { flag in
                        Label(flag, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.danger)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isTop ? Color.accentGold : Color.surfaceBorder.opacity(0.3),
                            lineWidth: isTop ? 1.5 : 0.5
                        )
                )
        )
    }

    private func noteRow(icon: String, tint: Color, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(tint)
                    .tracking(0.4)
            }
            Text(body)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The board's ONE grade colour ramp, so a B+ is the same blue here as on
    /// the roster and on the film-study report.
    private func gradeColor(_ band: GradeRange?) -> Color {
        guard let band else { return Color.textTertiary }
        return PositionGradeCalculator.gradeColorForLetter(band.midGrade.rawValue)
    }
}

// MARK: - Workout result sheet

/// What one slot bought, as a modal rather than the one-line `.alert` the old
/// screen showed. Kept for `ProspectDetailView`, which still runs the workout one
/// man at a time from his own card — this tab spends its ration in batches now
/// and reports through ``WorkoutBatchReportView``.
struct WorkoutResultSheet: View {
    let result: ScoutingEngine.WorkoutResult
    let prospect: CollegeProspect?
    let slotsUsed: Int
    let slotLimit: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                List {
                    gradeSection
                    if let note = result.personalityNote { readSection(title: "The room", body: note) }
                    readSection(title: "Scheme fit", body: result.schemeFitNote)
                    if !result.impressions.isEmpty { impressionsSection }
                    medicalSection
                    slotSection
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle(prospect?.fullName ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var gradeSection: some View {
        Section {
            HStack(spacing: 14) {
                gradeColumn("Before", text: result.gradeBefore?.displayText ?? "\u{2014}", tint: .textTertiary)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                gradeColumn("After", text: result.gradeAfter?.displayText ?? "\u{2014}", tint: .accentGold)
                Spacer()
            }
            .padding(.vertical, 4)
        } header: {
            Text("Grade band")
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func gradeColumn(_ label: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(text)
                .font(.title3.weight(.bold))
                .foregroundStyle(tint)
        }
    }

    private func readSection(title: String, body: String) -> some View {
        Section {
            Text(body)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        } header: {
            Text(title)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var impressionsSection: some View {
        Section {
            ForEach(result.impressions, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(Color.accentBlue)
                        .padding(.top, 5)
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(Color.textPrimary)
                }
            }
        } header: {
            Text("What the staff saw")
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    @ViewBuilder
    private var medicalSection: some View {
        let concerns = prospect?.medicalConcerns ?? []
        let flags = prospect?.redFlags ?? []
        Section {
            if concerns.isEmpty && flags.isEmpty {
                Text("Nothing new on the medical or the background.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            } else {
                ForEach(concerns, id: \.self) { concern in
                    Label(concern, systemImage: "cross.case.fill")
                        .font(.caption)
                        .foregroundStyle(Color.warning)
                }
                ForEach(flags, id: \.self) { flag in
                    Label(flag, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.danger)
                }
            }
        } header: {
            Text("Medical & flags")
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var slotSection: some View {
        Section {
            Text("\(slotsUsed) of \(slotLimit) workout slots used this cycle.")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Color.textTertiary)
        }
        .listRowBackground(Color.backgroundSecondary)
    }
}
