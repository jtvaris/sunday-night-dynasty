import SwiftUI
import SwiftData

// MARK: - Top-30 Visits, as a batch instrument (#120)
//
// The visit book shipped as a list with an Invite button on every row: one tap,
// one man, one alert, thirty times over. A club does not decide its Top-30 one
// name at a time — it draws up a list of the men it wants in the building and
// sends the invitations out together — and the interview room already had the
// shape that says so.
//
// This screen is that shape over the visit ration: pick the guests, run the
// visits once, read one report. Same parts as `InterviewSelectionView` and
// `FilmStudySelectionView`: the capsule action bar carrying Select All
// Recommended and Deselect All, the "N/M selected" progress line, one prominent
// run bar that states its own reason when it is dead, a ranked card report, and
// a steady state that is the saved report with NO call to action once the
// ration is spent (#118).
//
// ## One economy, unchanged
//
// `career.top30VisitsUsed` out of `DraftPrepProgress.top30Slots`. The visit is
// still `ScoutingEngine.conductTop30Visit` — a deep interview, a focused workout
// and a medical, stamping `top30VisitedByTeams` so the man cannot be invited
// twice — and the mutation still goes through `DraftClassMutator`, once for the
// whole batch instead of once per guest. The counter is incremented for visits
// that ACTUALLY happened, never for a man who is merely selected.

/// The `.top30Visits` stage: bring men into the building.
///
/// This used to be a section buried inside the pro-day list, sharing one scroll
/// with the school circuit and the private workouts — three economies, three
/// clocks, one screen (F4). It is its own stage now, and it sits where the
/// chronology actually puts it: facility visits are the LAST instrument before
/// the draft, after the tour and after the workouts.
///
/// Same two structural rules as the tour screen: the board rank map is decoded
/// once into `@State`, and the visits themselves go through `DraftClassMutator`
/// so the interview, the medical and the revised football IQ survive a relaunch.
struct Top30VisitsView: View {
    let career: Career
    let scouts: [Scout]
    let prospects: [CollegeProspect]
    let teamRoster: [Player]
    /// Whether the club may work this stage, decided ONCE by
    /// ``DraftPrepProgress/canAct(_:)`` and handed down — the same predicate the
    /// hub's process bar draws this stage's puck from.
    let canAct: Bool
    var onRefresh: () -> Void
    /// Hands one man to the interview room (#137), exactly as the Big Board's
    /// rows do. Supplied by the hub only when the room is honestly open, so this
    /// list never has to know the interview economy; `nil` and the menu item is
    /// not drawn at all.
    var onInterview: ((CollegeProspect) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @CareerScopedStorage("prospectCustomBoard") private var prospectCustomBoardJSON: String = "[]"

    @State private var boardRanks: [UUID: Int] = [:]
    @State private var teamNeeds: Set<Position> = []
    @State private var candidates: [CollegeProspect] = []
    /// Every visit this club has hosted this cycle, snapshotted at refresh.
    ///
    /// Rebuilt from what the visit stamps on the prospect — this club's ID in
    /// `top30VisitedByTeams`, plus the interview and medical it wrote — rather
    /// than remembered from the run that produced it, so the report survives a
    /// tab switch and a relaunch like the interview tab's saved report does.
    @State private var filedVisits: [Top30ReportEntry] = []
    @State private var showAll = false
    @State private var searchText = ""

    // MARK: - Batch state

    @State private var selectedIDs: Set<UUID> = []
    /// The one sheet this screen can have open. See ``Top30Sheet``.
    @State private var activeSheet: Top30Sheet?
    /// Set when the user explicitly opens the filed report while slots remain.
    @State private var viewingFiledReport = false

    private static let candidatesBeforeFold = 20

    /// The screen's single sheet slot.
    ///
    /// An enum rather than a boolean even though there is one case today: the
    /// hub, the prospect card and the pro-day tour each shipped with two stacked
    /// `.sheet(isPresented:)` on one node, SwiftUI honoured only the last, and
    /// three separate buttons opened the wrong sheet or nothing at all. One
    /// `item:` slot makes "two sheets at once" unrepresentable.
    enum Top30Sheet: Identifiable {
        /// What a just-hosted batch of visits opened up.
        case batchReport(Top30Batch)

        var id: String {
            switch self {
            case .batchReport: return "batchReport"
            }
        }
    }

    // MARK: - Stage

    private var stage: DraftPrepStep { career.prepStep }
    private var isStageLocked: Bool { !canAct }

    private var used: Int { career.top30VisitsUsed }
    private var remaining: Int { max(0, DraftPrepProgress.top30Slots - used) }

    private var filtered: [CollegeProspect] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.fullName.lowercased().contains(query) || $0.college.lowercased().contains(query)
        }
    }

    private var visible: [CollegeProspect] {
        showAll || !searchText.isEmpty ? filtered : Array(filtered.prefix(Self.candidatesBeforeFold))
    }

    // MARK: - Selection maths
    //
    // One limit: the visit costs a slot and no money. The cap is the slots left
    // in the cycle, and it moves as the selection does — deselecting a man gives
    // his slot back.

    /// The men the run bar would actually invite, resolved from the UNFILTERED
    /// candidate pool rather than the visible list: a man selected before the
    /// user typed in the search box is still selected, and dropping him because
    /// a filter now hides him would host a different batch than the one the
    /// button counted.
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
    /// The candidate sort already encodes this club's own notion of worth, in
    /// this order: the ONE mark first (`userMark.isBoardPositive` — the men the
    /// user called Elite or Target), then team need, then his custom board rank,
    /// then the fogged band. So the recommendation is the marked men, in that
    /// same order — a facility visit is the last instrument before the draft and
    /// it is spent on men the club is already serious about.
    ///
    /// A board with no marks falls back to the men at a position the roster
    /// actually needs, because "the button did nothing" is the worse failure.
    /// With neither, the capsule does not appear rather than guessing from a
    /// list the user has never expressed an opinion about.
    private var recommendedProspects: [CollegeProspect] {
        let marked = filtered.filter { $0.userMark.isBoardPositive }
        if !marked.isEmpty { return marked }
        return filtered.filter { teamNeeds.contains($0.position) }
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

        // A selected man the 20-row fold is hiding is a lie about what the run
        // bar will do, so filling the selection unfolds the list.
        if picks.contains(where: { !visibleIDs.contains($0.id) }) { showAll = true }
    }

    // MARK: - Gate
    //
    // Every blocked case carries the sentence the run bar prints. A dead control
    // that does not say why is the bug this whole wave exists to stop repeating.

    /// Why the batch cannot be run, or `nil` when it can.
    private var blockedReason: String? {
        if !canAct { return "The visit book opens at that stage" }
        if career.teamID == nil { return "No club to host the visits" }
        if remaining == 0 {
            return "All \(DraftPrepProgress.top30Slots) visit slots are spent this cycle"
        }
        if candidates.isEmpty { return "Everybody worth a visit has already been in" }
        if selectedIDs.isEmpty { return "Select Men to Bring In" }
        return nil
    }

    // MARK: - The room

    /// The man whose read the visit is filed under, and how good the room is.
    ///
    /// Best accuracy on staff runs the interview; the quality the engine sizes
    /// its noise from is the DEPARTMENT average, because a facility visit is the
    /// whole building's day, not one scout's. Both numbers are the ones the
    /// single-invite path already used, kept verbatim.
    private var leadScout: Scout? {
        scouts.max { $0.accuracy < $1.accuracy }
    }

    private var interviewerQuality: Int {
        scouts.isEmpty ? 60 : scouts.reduce(0) { $0 + $1.accuracy } / scouts.count
    }

    private var interviewerName: String {
        leadScout.map { "Scout \($0.fullName)" } ?? "Scouting Staff"
    }

    /// "Top-30 Visit · 2027" — instrument plus season, so a report read back on
    /// draft night still says when the man was in the building.
    private var occasionLabel: String {
        "Top-30 Visit \u{00B7} " + String(career.currentSeason)
    }

    /// The filed visits as one report payload.
    private var filedBatch: Top30Batch {
        Top30Batch(
            entries: filedVisits,
            hostName: interviewerName,
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
            } else if viewingFiledReport && !filedVisits.isEmpty {
                // Explicitly requested while slots remain.
                savedReport(dismissTitle: "Back to the Visit List") {
                    viewingFiledReport = false
                    refresh()
                }
            } else if remaining == 0 && !filedVisits.isEmpty {
                // STEADY STATE. The ration is spent and the report IS this tab,
                // so there is no run bar and no "complete review" CTA:
                // dismissing would re-render this same screen, and a gold call
                // to action weeks after the stage closed reads as a required
                // action the user is failing (#118).
                savedReport(dismissTitle: nil, onDismiss: nil)
            } else {
                visitList
            }
        }
        .task { refresh() }
        // ONE sheet modifier, over an `item:` slot — the `.alert` this replaces
        // could show exactly one man's visit, which is why the screen could only
        // ever run one at a time.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case let .batchReport(batch):
                NavigationStack {
                    ZStack {
                        Color.backgroundPrimary.ignoresSafeArea()
                        Top30BatchReportView(batch: batch)
                    }
                    .navigationTitle("Visit Report")
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
            Image(systemName: "house.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(Color.textTertiary)
            Text("The Visit Book Is Not Open")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            // Same shared wait sentence the tour and the workout room print —
            // the visit book sits on the pro-day side of the calendar too, and
            // "You are at: Film Study." on its own never said which phase the
            // user was waiting on (#123).
            Text("Facility visits are the last instrument before the draft. \(DraftPrepProgress.screenLockMessage(for: .top30Visits, phase: career.currentPhase, current: stage))")
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
            Top30BatchReportView(batch: filedBatch, isSavedReport: true)

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
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentGold))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private var visitList: some View {
        List {
            searchSection
            selectionSection
            candidateSection
            if canAct { advanceSection }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        // The run bar is pinned rather than scrolled: it carries the count the
        // user is building, and a total that scrolls away is a total he cannot
        // check while he is still picking.
        .safeAreaInset(edge: .bottom) { runBar }
    }

    /// Inline search, matching `BigBoardView`'s bar rather than `.searchable`:
    /// this surface lives inside the hub's navigation stack, and a system search
    /// field would attach itself to the shell's navigation bar.
    private var searchSection: some View {
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
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // Explainer deleted: the hub pins ONE canonical `DraftPrepStageExplainer`
    // above every stage screen — what the stage reveals on a prospect, what it
    // costs, and its DONE / CURRENT / LOCKED state. A second hand-written
    // version inside the list said the same thing in different words and cost a
    // section of scroll.

    // MARK: - Selection bar
    //
    // The mass-selection row, in the same place and the same style as the
    // interview tab's and the film tab's. Drawing up a Top-30 one checkbox at a
    // time is the chore this screen exists to delete; leaving the SELECTION as
    // thirty taps would have moved the chore rather than removed it.

    private var selectionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(selectedIDs.count)/\(remaining) selected")
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(selectedIDs.isEmpty ? Color.textSecondary : Color.textPrimary)

                    Spacer()

                    // Surfaces the visits already hosted so the stage's report
                    // can be read mid-cycle, before the slots run out.
                    if !filedVisits.isEmpty {
                        Button {
                            viewingFiledReport = true
                        } label: {
                            capsuleLabel(
                                "View Report (\(filedVisits.count))",
                                icon: "doc.text.magnifyingglass",
                                tint: Color.accentGold
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !recommendedProspects.isEmpty && remaining > 0 {
                        Button {
                            selectAllRecommended()
                        } label: {
                            capsuleLabel("Select All Recommended", icon: nil, tint: Color.accentGold)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Fills the guest list from the men on your board until the slots run out")
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
                            .fill(selectedIDs.isEmpty ? Color.textTertiary : Color.accentGold)
                            .frame(
                                width: remaining > 0
                                    ? geo.size.width * CGFloat(selectedIDs.count) / CGFloat(remaining)
                                    : 0,
                                height: 6
                            )
                    }
                }
                .frame(height: 6)

                Text("A visit opens the medical, the character file and a revised football IQ. It costs a slot and no money.")
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

    private var candidateSection: some View {
        Section {
            if visible.isEmpty {
                Text(searchText.isEmpty
                     ? "Everybody worth a visit has already been in the building."
                     : "Nobody matches \u{201C}\(searchText)\u{201D}.")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(visible) { prospect in
                    candidateRow(prospect)
                }
                if !showAll && searchText.isEmpty && filtered.count > Self.candidatesBeforeFold {
                    Button { showAll = true } label: {
                        Text("Show all \(filtered.count) candidates")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Label("TOP-30 VISITS", systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(Color.accentGold)
                Spacer()
                Text("\(used) / \(DraftPrepProgress.top30Slots) used \u{2022} \(remaining) left")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(remaining == 0 ? Color.danger : Color.textSecondary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// One selectable guest.
    ///
    /// The row body is the selection toggle — the Invite button that used to sit
    /// on the trailing edge is gone, because the batch bar is the only thing
    /// that spends a slot now. The two controls the interview list keeps beside
    /// its checkbox are kept here for the same reason: the mark menu, so an
    /// opinion can be recorded without leaving the list, and a route to the
    /// man's card, so "who is this" does not cost the user his selection.
    private func candidateRow(_ prospect: CollegeProspect) -> some View {
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
                        .foregroundStyle(isSelected ? Color.accentGold : Color.textTertiary)
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
            .accessibilityValue(isSelected ? "Invited to the building" : read.accessibilityText)
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
                onChange: { try? modelContext.save() },
                onInterview: ProspectGradeContextMenu.interviewAction(
                    for: prospect,
                    jump: onInterview
                )
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
                Image(systemName: canAct ? "person.crop.circle.badge.checkmark" : "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                Text(reason ?? "Host Top-30 Visits (\(selectedIDs.count))")
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(blocked ? Color.textTertiary : Color.backgroundPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(blocked ? Color.backgroundTertiary.opacity(0.5) : Color.accentGold)
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
                    Text(used > 0 ? "Close the visit book" : "Skip the visits")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.backgroundPrimary)
                    Text(used > 0
                         ? (used == 1 ? "1 man came through the building" : "\(used) men came through the building")
                         : "You will draft on tape and other people's medicals")
                        .font(.caption)
                        .foregroundStyle(Color.backgroundPrimary.opacity(0.8))
                }
                Spacer()
                Image(systemName: "arrow.right.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.backgroundPrimary)
            }
            .padding(12)
            .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    /// The batch: one pass through the chokepoint, billed once per visit that
    /// actually happened, persisted once at the end.
    ///
    /// The persistence is the single-invite path's, unchanged and done once
    /// instead of N times: `DraftClassMutator.mutate` writes the canonical class,
    /// calls `WeekAdvancer.persistDraftClass` and saves the context, and the
    /// slot counter is written straight after with its own `save()`. Both halves
    /// are load-bearing — without the mutator the medicals and the revised
    /// football IQ are forgotten on relaunch, and without the counter the ration
    /// never runs down.
    ///
    /// Every guard the run bar applied is re-applied here. The button is the UI;
    /// this is the ration, and `career.top30VisitsUsed` is evidence
    /// `DraftPrepProgress` reads to decide this stage is worked.
    private func runBatch() {
        guard canAct, blockedReason == nil, let teamID = career.teamID else { return }

        // Re-clamped against the live counter: the slot ledger is shared state
        // other surfaces spend too, so the selection may have been sized against
        // a number that has since moved.
        let targets = Array(selectedProspects.prefix(remaining))
        guard !targets.isEmpty else { return }

        let quality = interviewerQuality
        let host = interviewerName
        let occasion = occasionLabel

        var entries: [Top30ReportEntry] = []
        let applied = DraftClassMutator.mutate(modelContext) { klass in
            for target in targets {
                guard let index = klass.firstIndex(where: { $0.id == target.id }) else { continue }
                // A stale candidate list can still show a man this building
                // already hosted — re-ask at the point the slot is charged.
                guard !klass[index].top30VisitedByTeams.contains(teamID) else { continue }
                let result = ScoutingEngine.conductTop30Visit(
                    prospect: &klass[index],
                    visitingTeamID: teamID,
                    interviewerQuality: quality,
                    interviewerName: host,
                    occasionLabel: occasion
                )
                entries.append(Top30ReportEntry(prospect: klass[index], result: result))
            }
        }

        // `mutate` returns false when there is no class in memory. Nothing
        // happened, so nothing is charged and nothing is claimed.
        guard applied, !entries.isEmpty else { return }

        // ONE increment per visit that actually happened — never per selection.
        career.top30VisitsUsed += entries.count
        try? modelContext.save()

        let batch = Top30Batch(
            entries: entries,
            hostName: host,
            occasion: occasion,
            slotsUsed: career.top30VisitsUsed,
            slotsLeft: max(0, DraftPrepProgress.top30Slots - career.top30VisitsUsed)
        )

        selectedIDs.removeAll()
        refresh()
        onRefresh()
        activeSheet = .batchReport(batch)
    }

    private func advanceStage() {
        guard canAct else { return }
        career.advancePrepStep(to: .mockTwo)
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

        let teamID = career.teamID
        candidates = prospects
            .filter { prospect in
                guard prospect.isDeclaringForDraft else { return false }
                guard let teamID else { return true }
                return !prospect.top30VisitedByTeams.contains(teamID)
            }
            .sorted { a, b in
                let aMark = a.userMark.isBoardPositive ? 1 : 0
                let bMark = b.userMark.isBoardPositive ? 1 : 0
                if aMark != bMark { return aMark > bMark }

                let aNeed = teamNeeds.contains(a.position) ? 1 : 0
                let bNeed = teamNeeds.contains(b.position) ? 1 : 0
                if aNeed != bNeed { return aNeed > bNeed }

                let aRank = ranks[a.id] ?? Int.max
                let bRank = ranks[b.id] ?? Int.max
                if aRank != bRank { return aRank < bRank }

                return ProspectFog.rank(a) > ProspectFog.rank(b)
            }

        // A selection may not outlive the men in it: anyone who has now been in
        // the building is no longer a candidate, and a stale ID in the set would
        // keep counting against the cap forever.
        let candidateIDs = Set(candidates.map(\.id))
        selectedIDs.formIntersection(candidateIDs)

        // The receipt for a visit is this club's ID on the man, which is exactly
        // what the candidate filter above excludes him for.
        if let teamID {
            filedVisits = prospects
                .filter { $0.top30VisitedByTeams.contains(teamID) }
                .map { Top30ReportEntry(filed: $0) }
        } else {
            filedVisits = []
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
// is snapshotted at the moment the visit happened.
//
// Every field below is either something `ScoutingEngine.conductTop30Visit`
// RETURNS or something it WROTE onto the man. Nothing is invented to fill a
// card, and no hidden attribute is read: `trueOverall`, `truePhysical` and the
// rest of the generator's numbers are not on this screen in any form.

/// One guest's line in a visit report.
struct Top30ReportEntry: Identifiable {
    let id = UUID()
    let prospectName: String
    let position: Position
    let college: String
    /// The fogged band, as context for the read — the visit files no scouting
    /// report, so this is the band the club already had, not one it just bought.
    let band: GradeRange?
    /// Football IQ the deep interview revised, 40..99.
    let footballIQ: Int?
    /// The personality the room read.
    let personality: PersonalityArchetype?
    /// Character and leadership notes from the interview.
    let characterNotes: [String]
    /// What the medical opened. On a just-hosted visit these are the concerns
    /// the exam SURFACED; on a saved report it is the whole file, because the
    /// engine merges the new findings into it and does not keep them apart.
    let medicalConcerns: [String]
    /// The background file as it stands.
    let redFlags: [String]
    /// What the focused workout showed.
    let workoutImpressions: [String]
    /// Team fit, 0..1. `nil` on a saved report — the score is returned to the
    /// caller and never stored, and inventing one would be a fabrication.
    let teamFit: Double?

    /// Ranking key. The visit's own verdict when it produced one, otherwise the
    /// band the club already had, so a saved list still comes out in an order
    /// that means something. Both are values this card prints, so ranking on
    /// them discloses nothing the user is not already reading.
    var rank: Int {
        if let teamFit { return 1_000 + Int((teamFit * 100).rounded()) }
        return band?.midGrade.rank ?? 0
    }

    /// Whether the visit turned anything up that should worry the club.
    var hasConcerns: Bool { !medicalConcerns.isEmpty || !redFlags.isEmpty }

    /// The band the rest of the app shows for this man — scout-sourced and
    /// confidence-widened, never the raw stored range.
    private static func foggedBand(_ prospect: CollegeProspect) -> GradeRange? {
        let read = ProspectFog.read(prospect)
        return read.source == .scouts ? read.band : nil
    }

    /// A visit that just happened.
    init(prospect: CollegeProspect, result: ScoutingEngine.Top30VisitResult) {
        self.prospectName = prospect.fullName
        self.position = prospect.position
        self.college = prospect.college
        // Fogged, not stored: the candidate row two taps earlier prints the
        // widened `ProspectFog.read` band, and a report card that prints the
        // narrower stored range makes the same screen disagree with itself.
        self.band = Self.foggedBand(prospect)
        self.footballIQ = result.footballIQRevised
        self.personality = prospect.scoutedPersonality
        self.characterNotes = result.interviewNotes
        self.medicalConcerns = result.medicalConcerns
        self.redFlags = prospect.redFlags ?? []
        self.workoutImpressions = result.workoutImpressions
        self.teamFit = result.teamFitScore
    }

    /// A visit hosted earlier this cycle, rebuilt from what it stamped on the
    /// man. The engine writes the interview, the personality and the medical
    /// onto the prospect; the workout impressions and the fit score are returned
    /// to the caller only, so a saved card is honest about not having them.
    init(filed prospect: CollegeProspect) {
        self.prospectName = prospect.fullName
        self.position = prospect.position
        self.college = prospect.college
        self.band = Self.foggedBand(prospect)
        self.footballIQ = prospect.interviewFootballIQ
        self.personality = prospect.scoutedPersonality
        self.characterNotes = prospect.interviewCharacterNotes ?? []
        self.medicalConcerns = prospect.medicalConcerns ?? []
        self.redFlags = prospect.redFlags ?? []
        self.workoutImpressions = []
        self.teamFit = nil
    }
}

/// Everything one batch of visits (or one cycle of them) opened up.
struct Top30Batch: Identifiable {
    let id = UUID()
    let entries: [Top30ReportEntry]
    /// Who ran the room.
    let hostName: String
    /// "Top-30 Visit · 2027".
    let occasion: String
    /// Visit slots spent this cycle after the batch.
    let slotsUsed: Int
    /// Visit slots left in the cycle after the batch.
    let slotsLeft: Int
}

// MARK: - Batch report view

/// What the visits opened, one card a guest.
///
/// Built from the same parts as the interview and film-study reports — summary
/// pills over ranked cards, tier-coloured value at the trailing edge, flags
/// called out in their own colours — so the three instruments report in one
/// voice. Rendered inside a sheet after a batch, and inline as the tab's steady
/// state once the ration is spent.
struct Top30BatchReportView: View {
    let batch: Top30Batch
    /// `true` when this is the cycle's saved summary rather than a just-hosted
    /// batch. Suppresses the fit score (it is not stored) and re-words the
    /// header and the medical line.
    var isSavedReport: Bool = false

    private var rankedEntries: [Top30ReportEntry] {
        batch.entries.sorted { $0.rank > $1.rank }
    }

    private var concernCount: Int { batch.entries.filter(\.hasConcerns).count }

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
            Text(isSavedReport ? "VISITS \u{2014} THIS CYCLE" : "VISIT REPORT")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(Color.accentGold)
                .tracking(0.5)

            Spacer()

            Text("\(batch.entries.count) visit\(batch.entries.count == 1 ? "" : "s") hosted")
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
                .foregroundStyle(Color.accentGold)
                .tracking(0.5)

            HStack(spacing: 12) {
                summaryPill(
                    icon: "person.crop.circle.badge.checkmark",
                    text: "\(batch.entries.count) in the building with \(batch.hostName)",
                    color: .accentGold
                )
                summaryPill(icon: "calendar", text: batch.occasion, color: .textSecondary)
            }

            HStack(spacing: 12) {
                summaryPill(
                    icon: "gauge.with.dots.needle.33percent",
                    text: "\(batch.slotsUsed) of \(DraftPrepProgress.top30Slots) slots used \u{2022} \(batch.slotsLeft) left",
                    color: batch.slotsLeft == 0 ? .danger : .textSecondary
                )
                summaryPill(
                    icon: concernCount > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                    text: concernCount > 0
                        ? "\(concernCount) with medical or background notes"
                        : "Nothing new on any medical",
                    color: concernCount > 0 ? .warning : .success
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentGold.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.accentGold.opacity(0.2))
                )
        )
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

    private func entryCard(_ entry: Top30ReportEntry, rank: Int) -> some View {
        let isTop = rank == 1
        let borderColor: Color = {
            if entry.hasConcerns { return Color.warning }
            if isTop { return Color.accentGold }
            return Color.surfaceBorder.opacity(0.3)
        }()

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
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentGold.opacity(0.15)))
                    }
                    HStack(spacing: 6) {
                        Text(entry.college)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                        Text("Band \(entry.band?.displayText ?? "\u{2014}")")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(gradeColor(entry.band))
                    }
                }

                Spacer()

                // The visit's own verdict at the trailing edge, where the
                // interview report puts its letter. Absent on a saved card,
                // because the score was never stored.
                if let fit = entry.teamFit {
                    VStack(spacing: 1) {
                        Text("\(Int((fit * 100).rounded()))%")
                            .font(.system(size: 20, weight: .heavy).monospacedDigit())
                            .foregroundStyle(fitColor(fit))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("Fit")
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .frame(width: 58)
                }
            }

            // What the deep interview revised.
            HStack(spacing: 10) {
                if let personality = entry.personality {
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                        Text(personality.displayName)
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(personalityColor(personality)))
                }

                if let iq = entry.footballIQ {
                    HStack(spacing: 4) {
                        Image(systemName: "brain.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(iqColor(iq))
                        Text("Football IQ: \(iq)")
                            .font(.system(size: 12, weight: .bold).monospacedDigit())
                            .foregroundStyle(iqColor(iq))
                    }
                }
            }

            // The medical. The engine only surfaces a concern on a quarter of
            // visits, and "nothing new" is a result the user paid a slot for —
            // so the line is printed either way rather than silently omitted.
            if entry.medicalConcerns.isEmpty {
                if !isSavedReport {
                    Label("Nothing new on the medical.", systemImage: "cross.case")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.success)
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isSavedReport ? "MEDICAL FILE" : "WHAT THE EXAM OPENED")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(0.4)
                    ForEach(entry.medicalConcerns, id: \.self) { concern in
                        Label(concern, systemImage: "cross.case.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.warning)
                    }
                }
            }

            if !entry.redFlags.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("BACKGROUND")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.textTertiary)
                        .tracking(0.4)
                    ForEach(entry.redFlags, id: \.self) { flag in
                        Label(flag, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.danger)
                    }
                }
            }

            if !entry.workoutImpressions.isEmpty {
                bulletBlock(title: "What the workout showed",
                            lines: entry.workoutImpressions,
                            tint: Color.accentBlue)
            }

            if !entry.characterNotes.isEmpty {
                bulletBlock(title: "The room", lines: entry.characterNotes, tint: Color.accentGold)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            borderColor,
                            lineWidth: (entry.hasConcerns || isTop) ? 1.5 : 0.5
                        )
                )
        )
    }

    private func bulletBlock(title: String, lines: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(Color.textTertiary)
                .tracking(0.4)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 5))
                        .foregroundStyle(tint)
                        .padding(.top, 5)
                    Text(line)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Helpers

    /// The board's ONE grade colour ramp, so a B+ is the same blue here as on
    /// the roster and on the film-study report.
    private func gradeColor(_ band: GradeRange?) -> Color {
        guard let band else { return Color.textTertiary }
        return PositionGradeCalculator.gradeColorForLetter(band.midGrade.rawValue)
    }

    /// Team fit is printed on this very row as a percentage, so it takes the
    /// shared percentage ladder. It used to run on private 75/55/40 bands with
    /// `accentGold` in the middle — the row therefore showed "62%" in the hue
    /// P7 reserves for "primary/current", two inches from a grade band that
    /// meant something else by the same colour.
    private func fitColor(_ fit: Double) -> Color {
        Color.forRating(Int((fit * 100).rounded()), scale: .percent)
    }

    /// Football IQ is a 0–99 player attribute — the plainest case there is for
    /// the shared ladder.
    private func iqColor(_ iq: Int) -> Color {
        Color.forRating(iq)
    }

    private func personalityColor(_ archetype: PersonalityArchetype) -> Color {
        switch archetype.tier {
        case .positive: return Color.success
        case .risky:    return Color.danger
        case .neutral:  return Color.warning.opacity(0.8)
        }
    }
}
