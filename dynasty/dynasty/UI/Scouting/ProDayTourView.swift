import SwiftUI
import SwiftData

// MARK: - Pro Day Tour

/// The `.proDayFocus` stage: pick the schools the department travels to, then
/// send it out ONCE.
///
/// Three things about this screen are deliberate (plan §5.5):
///
/// 1. **One execution path.** Assigning a school *reserves* a focus slot and
///    mutates nothing. The stage-advance button is the only thing that runs the
///    tour. The old screen ran `attendProDay` eagerly on assignment and then
///    offered a big gold "Send Scouts to Pro Days" button whose per-college
///    guard (`contains { !$0.proDayCompleted }`) was always false by the time it
///    was pressed — a no-op with a receipt (F5). It cannot come back: there is
///    no engine call on the assignment path any more.
/// 2. **Nothing decodes UserDefaults in a computed property.** The custom board
///    is decoded once per refresh into `boardRanks`, and the whole school list
///    is one pure `ScoutingEngine.proDaySchoolSummaries` pass held in `@State`
///    (F6). The old screen decoded a ~300-element JSON array and linear-scanned
///    it several thousand times per body evaluation.
/// 3. **Every mutation goes through `DraftClassMutator`.** The results have to
///    land on `WeekAdvancer.currentDraftClass` and in SwiftData or they do not
///    exist after a relaunch (F7).
struct ProDayTourView: View {
    let career: Career
    let scouts: [Scout]
    let prospects: [CollegeProspect]
    let teamRoster: [Player]
    /// Whether the club may work this stage, decided ONCE by
    /// ``DraftPrepProgress/canAct(_:)`` and handed down.
    ///
    /// It used to be derived here from `career.prepStep`, which is a floor and
    /// therefore says nothing reliable about what is workable: the screen shut
    /// itself the moment the phase floor moved the club past `.proDayFocus`
    /// (B1, "pro days completely unavailable — could not select schools at
    /// all") and stayed shut while the hub still offered the tab. The hub draws
    /// the stage's puck from the same predicate, so an inviting cell and a live
    /// screen are now the same fact.
    let canAct: Bool
    var onRefresh: () -> Void

    @Environment(\.modelContext) private var modelContext
    @CareerScopedStorage("prospectCustomBoard") private var prospectCustomBoardJSON: String = "[]"

    // MARK: - Cached derivations (F6)
    //
    // Every one of these is computed ONCE per refresh, never in a computed
    // property the body can touch. `refresh()` runs on `.task` and after any
    // action that can change what they hold.

    /// Prospect ID → 1-based rank on the user's custom board. One JSON decode.
    @State private var boardRanks: [UUID: Int] = [:]
    @State private var summaries: [ScoutingEngine.ProDaySchoolSummary] = []
    /// Schools whose pro day has already been run for us.
    @State private var visitedColleges: Set<String> = []
    /// Declared men per school, graded-sorted, for the expanded rows.
    @State private var prospectsByCollege: [String: [CollegeProspect]] = [:]
    /// Best man per school, for the "your #N ranked prospect" line.
    @State private var bestNameByCollege: [String: String] = [:]
    @State private var teamNeeds: Set<Position> = []

    // MARK: - Screen state

    @State private var expandedColleges: Set<String> = []
    /// The one sheet this screen can have open, and which school it is about.
    ///
    /// **This screen used to carry TWO `.sheet(isPresented:)` modifiers on the
    /// same view.** SwiftUI honours exactly one per view: the later modifier
    /// wins, so tapping Reserve flipped `showScoutSheet`, the runtime presented
    /// the OTHER sheet's builder, `focusCollege` was `nil`, its `if let` produced
    /// nothing — and the user got an empty grey card over the school list, with
    /// no scout picker and no way to book anybody.
    ///
    /// That is bug B1 exactly: *"pro days completely unavailable — could not
    /// select schools at all."* The stage was never the problem; the button
    /// opened a blank sheet. One `.sheet(item:)` over one enum makes the case
    /// unrepresentable.
    private enum ActiveSheet: Identifiable {
        /// Pick which scout travels to this school.
        case reserveScout(college: String)
        /// Pick a man at this school to mark as a target.
        case markTarget(college: String)

        var id: String {
            switch self {
            case let .reserveScout(college): return "scout:\(college)"
            case let .markTarget(college):   return "target:\(college)"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var tourResult: ProDayTourResult?
    @State private var showSkipConfirm = false
    @State private var showAllSchools = false

    private static let schoolsBeforeFold = 25

    // MARK: - Stage

    private var stage: DraftPrepStep { career.prepStep }
    private var isStageLocked: Bool { !canAct }

    // MARK: - Focus slots

    /// The limited resource. `Σ scout.maxProDays` — renamed in copy from
    /// "assignment capacity", because what the user is spending is attention,
    /// not travel budget.
    private var totalSlots: Int { scouts.reduce(0) { $0 + $1.maxProDays } }
    /// Reservations, not executions: a school in `proDayColleges` is a school
    /// the department is booked into.
    private var usedSlots: Int { scouts.reduce(0) { $0 + $1.proDayColleges.count } }
    private var slotsLeft: Int { max(0, totalSlots - usedSlots) }
    private var reservedColleges: [String] { scouts.flatMap { $0.proDayColleges } }
    private var hasRunTour: Bool { !visitedColleges.isEmpty }

    private var scoutsWithSlots: [Scout] {
        scouts.filter { $0.proDayColleges.count < $0.maxProDays }
    }

    private var recommended: [ScoutingEngine.ProDaySchoolSummary] {
        summaries.filter { !$0.isFocused && $0.relevance > 5 }.prefix(5).map { $0 }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if scouts.isEmpty {
                emptyState(
                    icon: "person.slash",
                    title: "No Scouts Available",
                    message: "Hire scouts before the circuit starts \u{2014} the department is what buys exact numbers."
                )
            } else if isStageLocked {
                emptyState(
                    icon: "lock.fill",
                    title: "Pro Days Have Not Opened",
                    message: "The circuit runs after the combine. You are at: \(stage.displayName)."
                )
            } else {
                tourList
            }
        }
        .task { refresh() }
        // ONE sheet modifier. Two of them on the same view is how Reserve came
        // to open an empty card (B1) — see `ActiveSheet`.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case let .reserveScout(college): scoutSheet(college: college)
            case let .markTarget(college):   focusSheet(college: college)
            }
        }
        .alert("Go in on tape?", isPresented: $showSkipConfirm) {
            Button("Skip the circuit", role: .destructive) { advanceStage(runTour: false) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your department stays home. You will read every pro day off the broadcast feed like the other 31 clubs \u{2014} no exact decimals, no filed reports, no disclosure.")
        }
    }

    private var tourList: some View {
        List {
            focusSlotGauge
            departmentSection
            if !recommended.isEmpty && canAct { recommendedSection }
            schoolsSection
            if let result = tourResult { resultsSection(result) }
            advanceSection
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    // MARK: - Banner (deleted)
    //
    // The "how the circuit works" banner and its CLOSED chip are now the hub's
    // one canonical `DraftPrepStageExplainer`, pinned above every stage screen
    // with the same shape and the same DONE / CURRENT / LOCKED chip. A second
    // hand-written version inside the list said the same thing in different
    // words and cost a section of scroll.

    // MARK: - Focus slots

    private var focusSlotGauge: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.title3)
                    .foregroundStyle(Color.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus slots")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text("\(usedSlots)/\(totalSlots) reserved \u{2022} \(scouts.count) scout\(scouts.count == 1 ? "" : "s")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                GeometryReader { geo in
                    let progress = totalSlots > 0 ? CGFloat(usedSlots) / CGFloat(totalSlots) : 0
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.backgroundTertiary)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(progress > 0.8 ? Color.danger : Color.accentGold)
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(width: 60, height: 6)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Department

    private var departmentSection: some View {
        Section {
            ForEach(scouts) { scout in
                scoutRow(scout)
            }
        } header: {
            HStack {
                Text("Your department")
                Spacer()
                Text("\(slotsLeft) slot\(slotsLeft == 1 ? "" : "s") left")
                    .font(.caption2)
                    .foregroundStyle(slotsLeft == 0 ? Color.danger : Color.textTertiary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func scoutRow(_ scout: Scout) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(scout.proDayColleges.count < scout.maxProDays ? Color.accentGold.opacity(0.15) : Color.backgroundTertiary)
                        .frame(width: 32, height: 32)
                    Image(systemName: specialtyIcon(for: scout))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(scout.proDayColleges.count < scout.maxProDays ? Color.accentGold : Color.textTertiary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(scout.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(scout.specialtyLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.accentBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentBlue.opacity(0.12), in: Capsule())
                    }
                    HStack(spacing: 6) {
                        Text("ACC \(scout.accuracy)")
                            .font(.caption2.monospacedDigit().weight(.medium))
                            .foregroundStyle(Color.forRating(scout.accuracy))
                        Text("\u{2022}")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                        Text("\(scout.proDayColleges.count)/\(scout.maxProDays) slots")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(scout.proDayColleges.count >= scout.maxProDays ? Color.danger : Color.textSecondary)
                    }
                }
                Spacer()
            }
            if !scout.proDayColleges.isEmpty {
                Text(scout.proDayColleges.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                    .padding(.leading, 42)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - Recommended

    private var recommendedSection: some View {
        Section {
            ForEach(recommended) { info in
                schoolRow(info, showWhy: true)
            }
            if slotsLeft > 0 && !hasRunTour {
                Button { reserveAllRecommended() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                        Text("Reserve all recommended")
                            .font(.caption.weight(.bold))
                        Spacer()
                        Text("\(min(slotsLeft, recommended.count)) slot\(min(slotsLeft, recommended.count) == 1 ? "" : "s")")
                            .font(.caption2)
                            .foregroundStyle(Color.backgroundPrimary.opacity(0.8))
                    }
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.accentGold, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        } header: {
            Label("Where your board is", systemImage: "star.circle.fill")
                .foregroundStyle(Color.accentGold)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Schools

    private var visibleSchools: [ScoutingEngine.ProDaySchoolSummary] {
        showAllSchools ? summaries : Array(summaries.prefix(Self.schoolsBeforeFold))
    }

    private var schoolsSection: some View {
        Section {
            ForEach(visibleSchools) { info in
                schoolRow(info, showWhy: false)
            }
            if !showAllSchools && summaries.count > Self.schoolsBeforeFold {
                Button {
                    showAllSchools = true
                } label: {
                    Text("Show all \(summaries.count) schools")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentBlue)
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text("Schools")
                Spacer()
                Text("\(summaries.count) with declared men")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    @ViewBuilder
    private func schoolRow(_ info: ScoutingEngine.ProDaySchoolSummary, showWhy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedColleges.contains(info.college) {
                        expandedColleges.remove(info.college)
                    } else {
                        expandedColleges.insert(info.college)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Image(systemName: expandedColleges.contains(info.college) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.textTertiary)
                            .frame(width: 14)
                        Text(info.college)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        schoolStatus(info)
                    }
                    countChips(info)
                        .padding(.leading, 22)
                    if showWhy, let name = bestNameByCollege[info.college] {
                        Text("Your best read here: \(name)")
                            .font(.caption2)
                            .foregroundStyle(Color.accentGold)
                            .padding(.leading, 22)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(expandedColleges.contains(info.college) ? "Collapse school" : "Expand school")

            if expandedColleges.contains(info.college) {
                expandedSchool(info)
            }
        }
        .padding(.vertical, 3)
    }

    /// `3 ELITE · 2 TGT · 2 NEED · 14 declared` — the whole reason to travel,
    /// read straight off the user's own board marks.
    ///
    /// `targetedCount` is `userMark.isBoardPositive`, which **includes** elite:
    /// printing both raw made a school with 3 elite and 2 targets read
    /// "3 ELITE · 5 TGT" — eight men where there are five. The chips partition
    /// the board-positive men; the relevance sort still uses the full
    /// `targeted` count (elite deliberately weighs twice there).
    private func countChips(_ info: ScoutingEngine.ProDaySchoolSummary) -> some View {
        let otherTargets = max(0, info.targetedCount - info.eliteCount)
        return HStack(spacing: 6) {
            if info.eliteCount > 0 {
                chip("\(info.eliteCount) ELITE", color: .accentGold)
            }
            if otherTargets > 0 {
                chip("\(otherTargets) TGT", color: .success)
            }
            if info.needCount > 0 {
                chip("\(info.needCount) NEED", color: .danger)
            }
            Text("\(info.declared) declared")
                .font(.system(size: 10))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private func schoolStatus(_ info: ScoutingEngine.ProDaySchoolSummary) -> some View {
        if visitedColleges.contains(info.college) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(Color.success)
                Text(info.focusedScoutName ?? "Visited")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.success)
            }
        } else if info.isFocused {
            HStack(spacing: 6) {
                Text("RESERVED")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentGold.opacity(0.14), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                if canAct {
                    Button { releaseFocus(college: info.college) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Release \(info.college)")
                }
            }
        } else if canAct && slotsLeft > 0 {
            Button {
                activeSheet = .reserveScout(college: info.college)
            } label: {
                Label("Reserve", systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentGold)
            }
            .buttonStyle(.plain)
        } else if canAct {
            Text("No slots left")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        } else {
            // The chain used to end here with NOTHING drawn: an unreserved
            // school on a shut stage got a blank action slot — no button, no
            // reason, just a row that ignored taps. A closed door has to look
            // like a door.
            Text("Stage closed")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }

    @ViewBuilder
    private func expandedSchool(_ info: ScoutingEngine.ProDaySchoolSummary) -> some View {
        Divider()
            .padding(.vertical, 4)
            .overlay(Color.surfaceBorder)

        ForEach(prospectsByCollege[info.college] ?? []) { prospect in
            prospectRow(prospect)
        }

        if canAct && (prospectsByCollege[info.college]?.count ?? 0) > 1 {
            HStack {
                Spacer()
                Button {
                    activeSheet = .markTarget(college: info.college)
                } label: {
                    Label("Mark a target here", systemImage: "target")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentBlue.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
    }

    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        let read = ProspectFog.read(prospect)
        return HStack(spacing: 8) {
            Text(boardRanks[prospect.id].map { "#\($0)" } ?? "--")
                .font(.system(size: 10, weight: .heavy).monospacedDigit())
                .foregroundStyle((boardRanks[prospect.id] ?? 999) <= 10 ? Color.accentGold : Color.textTertiary)
                .frame(width: 28, alignment: .trailing)

            Text(prospect.position.rawValue)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 28, height: 18)
                .background(positionColor(prospect.position), in: RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 1) {
                Text(prospect.fullName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(read.text)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(read.source.tint)
                    if prospect.proDayCompleted {
                        Text("PRO DAY")
                            .font(.system(size: DSType.Size.micro, weight: .black))
                            .foregroundStyle(Color.success)
                    }
                }
            }

            Spacer()

            if prospect.userMark != .none {
                ProspectMarkChip(mark: prospect.userMark)
            }
            if teamNeeds.contains(prospect.position) {
                Text("NEED")
                    .font(.system(size: DSType.Size.micro, weight: .black))
                    .foregroundStyle(Color.danger)
            }
        }
        .padding(.vertical, 2)
        .padding(.leading, 22)
    }

    // MARK: - Results

    private func resultsSection(_ result: ProDayTourResult) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(Color.success)
                    Text("The department filed")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.success)
                }
                Text("\(result.prospectsEvaluated) men seen at \(result.schools.count) school\(result.schools.count == 1 ? "" : "s"): \(result.schools.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                ForEach(result.findings, id: \.self) { finding in
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "star.fill")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.accentGold)
                        Text(finding)
                            .font(.caption2)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.success.opacity(0.08))
    }

    // MARK: - Advance

    @ViewBuilder
    private var advanceSection: some View {
        if canAct {
            Section {
                Button { advanceStage(runTour: true) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.backgroundPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Send the department out")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.backgroundPrimary)
                            Text(usedSlots == 0
                                 ? "Reserve at least one school first"
                                 : "\(usedSlots) school\(usedSlots == 1 ? "" : "s") \u{2014} runs the circuit and closes the stage")
                                .font(.caption)
                                .foregroundStyle(Color.backgroundPrimary.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color.backgroundPrimary)
                    }
                    .padding(12)
                    .background(usedSlots == 0 ? Color.backgroundTertiary : Color.accentGold,
                                in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(usedSlots == 0)

                Button { showSkipConfirm = true } label: {
                    Text("Or watch it on the feed \u{2014} skip the circuit")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
        }
    }

    // MARK: - Sheets

    /// Takes the college as an argument rather than reading `@State`: the enum
    /// carries it, so there is no window in which the sheet is presented and the
    /// school it is about is `nil`.
    private func scoutSheet(college: String) -> some View {
        ProDayFocusScoutSheet(
            college: college,
            scouts: scouts,
            prospects: prospectsByCollege[college] ?? [],
            bestMatch: bestScoutFor(college: college),
            onReserve: { scout in
                reserveFocus(scout: scout, college: college)
                activeSheet = nil
            },
            onCancel: { activeSheet = nil }
        )
    }

    private func focusSheet(college: String) -> some View {
        ProDayMarkTargetSheet(
            college: college,
            prospects: prospectsByCollege[college] ?? [],
            onSelect: { prospect in
                markTarget(prospect)
                activeSheet = nil
            },
            onCancel: { activeSheet = nil }
        )
    }

    // MARK: - Actions

    /// Reserves a focus slot. **Runs nothing.** The reservation ledger is
    /// `scout.proDayColleges`; `scout.proDaysAttended` stays untouched until the
    /// tour actually executes.
    private func reserveFocus(scout: Scout, college: String) {
        guard canAct else { return }
        guard scout.proDayColleges.count < scout.maxProDays else { return }
        guard !reservedColleges.contains(college) else { return }
        scout.proDayColleges.append(college)
        try? modelContext.save()
        refresh()
        onRefresh()
    }

    private func releaseFocus(college: String) {
        guard canAct, !visitedColleges.contains(college) else { return }
        for scout in scouts {
            scout.proDayColleges.removeAll { $0 == college }
        }
        try? modelContext.save()
        refresh()
        onRefresh()
    }

    private func reserveAllRecommended() {
        for info in recommended {
            guard slotsLeft > 0 else { break }
            guard !reservedColleges.contains(info.college) else { continue }
            let pool = prospectsByCollege[info.college] ?? []
            let topPosition = Dictionary(grouping: pool) { $0.position }
                .max { $0.value.count < $1.value.count }?.key
            let scout = scoutsWithSlots.first { $0.positionSpecialization == topPosition }
                ?? scoutsWithSlots.max { $0.accuracy < $1.accuracy }
            guard let scout else { break }
            reserveFocus(scout: scout, college: info.college)
        }
    }

    private func markTarget(_ prospect: CollegeProspect) {
        DraftClassMutator.mutate(modelContext) { klass in
            guard let idx = klass.firstIndex(where: { $0.id == prospect.id }) else { return }
            klass[idx].setUserMark(.target)
        }
        refresh()
        onRefresh()
    }

    /// The ONE execution path (F5) and the stage transition (§5.2) in one act.
    ///
    /// `runTour == false` is the explicit skip: the stage still closes, the
    /// circuit simply never happened.
    private func advanceStage(runTour: Bool) {
        guard canAct else { return }

        if runTour {
            var findings: [String] = []
            var schools: [String] = []
            var evaluated = 0

            let applied = DraftClassMutator.mutate(modelContext) { klass in
                for scout in scouts {
                    for college in scout.proDayColleges {
                        let needsRun = klass.contains {
                            $0.college == college && $0.isDeclaringForDraft && !$0.proDayCompleted
                        }
                        guard needsRun else { continue }
                        ScoutingEngine.attendProDay(scout: scout, college: college, prospects: &klass)
                        schools.append(college)
                    }
                }

                let visited = Set(schools)
                for prospect in klass where visited.contains(prospect.college) && prospect.isDeclaringForDraft {
                    evaluated += 1
                    if let ovr = prospect.scoutedOverall, ovr >= 80 {
                        findings.append("\(prospect.fullName) (\(prospect.position.rawValue)) tested well at \(prospect.college)")
                    }
                }
            }

            // A club with no class in memory did not run a tour, and must not be
            // told it did.
            guard applied else { return }

            tourResult = ProDayTourResult(
                schools: schools,
                prospectsEvaluated: evaluated,
                findings: Array(findings.prefix(5))
            )
        }

        career.advancePrepStep(to: .workouts)
        try? modelContext.save()
        refresh()
        onRefresh()
    }

    // MARK: - Refresh (the F6 fix)

    /// Rebuilds every cached derivation. Called from `.task` and after each
    /// action — never from a computed property, and never per row.
    private func refresh() {
        // ONE decode of the persisted custom board, straight into a rank map.
        // `BigBoardView.cachedCustomRankMap` solved this exact problem; this
        // screen never adopted it, which is what made it quadratic-ish (F6).
        let ids = (try? JSONDecoder().decode([String].self, from: Data(prospectCustomBoardJSON.utf8))) ?? []
        var ranks: [UUID: Int] = [:]
        ranks.reserveCapacity(ids.count)
        for (index, raw) in ids.enumerated() {
            if let uuid = UUID(uuidString: raw) { ranks[uuid] = index + 1 }
        }
        boardRanks = ranks

        teamNeeds = Set(DraftEngine.topTeamNeeds(roster: teamRoster, limit: 5))

        summaries = ScoutingEngine.proDaySchoolSummaries(
            prospects: prospects,
            scouts: scouts,
            teamNeeds: teamNeeds,
            boardRanks: ranks
        )

        var grouped: [String: [CollegeProspect]] = [:]
        var visited: Set<String> = []
        for prospect in prospects where prospect.isDeclaringForDraft {
            grouped[prospect.college, default: []].append(prospect)
            if prospect.proDayCompleted { visited.insert(prospect.college) }
        }
        for key in Array(grouped.keys) {
            grouped[key]?.sort { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
        }
        prospectsByCollege = grouped
        visitedColleges = visited

        var bestNames: [String: String] = [:]
        for summary in summaries {
            if let id = summary.bestProspectID,
               let match = grouped[summary.college]?.first(where: { $0.id == id }) {
                bestNames[summary.college] = match.fullName
            }
        }
        bestNameByCollege = bestNames
    }

    // MARK: - Helpers

    private func bestScoutFor(college: String) -> (scout: Scout, reason: String)? {
        let pool = prospectsByCollege[college] ?? []
        guard !pool.isEmpty else { return nil }
        let topPosition = Dictionary(grouping: pool) { $0.position }
            .max { $0.value.count < $1.value.count }?.key

        if let position = topPosition,
           let specialist = scoutsWithSlots.first(where: { $0.positionSpecialization == position }) {
            let best = pool.filter { $0.position == position }
                .max { ($0.scoutedOverall ?? 0) < ($1.scoutedOverall ?? 0) }
            return (specialist, "\(specialist.fullName) (\(position.rawValue) specialist) for \(best?.fullName ?? "the group")")
        }
        if let best = scoutsWithSlots.max(by: { $0.accuracy < $1.accuracy }) {
            return (best, "\(best.fullName) (highest accuracy: \(best.accuracy))")
        }
        return nil
    }

    private func specialtyIcon(for scout: Scout) -> String {
        if let position = scout.positionSpecialization {
            switch position.side {
            case .offense:      return "sportscourt.fill"
            case .defense:      return "shield.fill"
            case .specialTeams: return "figure.run"
            }
        }
        if let focus = scout.focusAttribute { return focus.icon }
        return scout.scoutRole.isChief ? "star.fill" : "binoculars.fill"
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Color.textTertiary)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Tour result

/// What the one execution produced, for the panel under the button.
struct ProDayTourResult {
    let schools: [String]
    let prospectsEvaluated: Int
    let findings: [String]
}

// MARK: - Reserve-a-scout sheet

private struct ProDayFocusScoutSheet: View {
    let college: String
    let scouts: [Scout]
    let prospects: [CollegeProspect]
    let bestMatch: (scout: Scout, reason: String)?
    let onReserve: (Scout) -> Void
    let onCancel: () -> Void

    @State private var selectedScoutID: UUID?

    private var sortedScouts: [Scout] {
        scouts.sorted { $0.scoutRole.sortOrder < $1.scoutRole.sortOrder }
    }

    private func isRecommended(_ scout: Scout) -> Bool {
        if bestMatch?.scout.id == scout.id { return true }
        guard let spec = scout.positionSpecialization else { return false }
        return prospects.contains { $0.position == spec }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                VStack(spacing: 0) {
                    List {
                        Section {
                            Text("Reserving a slot books this school for the circuit. Nothing runs until you send the department out.")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                            if let reason = bestMatch?.reason {
                                HStack(spacing: 4) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color.accentGold.opacity(0.8))
                                    Text(reason)
                                        .font(.caption2.italic())
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }
                        }
                        .listRowBackground(Color.backgroundSecondary)

                        Section("Pick a scout") {
                            ForEach(sortedScouts) { scout in
                                scoutRow(scout)
                            }
                        }

                        Section("\(college) prospects") {
                            ForEach(prospects) { prospect in
                                prospectRow(prospect)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)

                    Button {
                        if let id = selectedScoutID, let scout = scouts.first(where: { $0.id == id }) {
                            onReserve(scout)
                        }
                    } label: {
                        Text(selectedScoutID == nil ? "Select a scout" : "Reserve \(college)")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(selectedScoutID == nil ? Color.textTertiary : Color.backgroundPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedScoutID == nil ? Color.backgroundTertiary : Color.accentGold)
                            )
                    }
                    .disabled(selectedScoutID == nil)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("\(college) Pro Day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }

    private func scoutRow(_ scout: Scout) -> some View {
        let isFull = scout.proDayColleges.count >= scout.maxProDays
        return Button {
            if !isFull { selectedScoutID = scout.id }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedScoutID == scout.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selectedScoutID == scout.id ? Color.accentGold : Color.textTertiary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(scout.fullName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isFull ? Color.textTertiary : Color.textPrimary)
                        Text(scout.specialtyLabel)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(isFull ? Color.textTertiary : Color.accentBlue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentBlue.opacity(isFull ? 0.05 : 0.12), in: Capsule())
                        if isRecommended(scout) && !isFull {
                            Text("Recommended")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.success)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.success.opacity(0.12), in: Capsule())
                        }
                    }
                    HStack(spacing: 8) {
                        Text("Accuracy \(scout.accuracy)")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Color.forRating(scout.accuracy))
                        Text("\(scout.proDayColleges.count)/\(scout.maxProDays) slots")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isFull ? Color.danger : Color.textSecondary)
                    }
                }
                Spacer()
                if isFull {
                    Text("FULL")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.danger)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isFull)
        .opacity(isFull ? 0.5 : 1.0)
        .listRowBackground(Color.backgroundSecondary)
        .accessibilityLabel("\(scout.fullName)\(selectedScoutID == scout.id ? ", selected" : "")\(isFull ? ", no slots left" : "")")
    }

    private func prospectRow(_ prospect: CollegeProspect) -> some View {
        let read = ProspectFog.read(prospect)
        return HStack(spacing: 8) {
            Text(prospect.position.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 28, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(prospect.position.side == .offense ? Color.accentBlue.opacity(0.25) : Color.danger.opacity(0.25))
                )
            Text(prospect.fullName)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(read.text)
                .font(.caption.weight(.bold))
                .foregroundStyle(read.source.tint)
        }
        .listRowBackground(Color.backgroundSecondary)
    }
}

// MARK: - Mark-a-target sheet

/// Picks one man at a school and marks him `target` on the ONE mark system.
/// It used to write `prospectFlag` directly, which the star store and the
/// board's own bookmark set never saw.
private struct ProDayMarkTargetSheet: View {
    let college: String
    let prospects: [CollegeProspect]
    let onSelect: (CollegeProspect) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                List {
                    Section {
                        Text("Mark one man from \(college) as a target. The board, the prep card and the pro-day chips all read the same mark.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .listRowBackground(Color.backgroundSecondary)

                    Section("Prospects") {
                        ForEach(prospects) { prospect in
                            Button { onSelect(prospect) } label: {
                                HStack(spacing: 10) {
                                    Text(prospect.position.rawValue)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Color.textPrimary)
                                        .frame(width: 30, height: 20)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(prospect.position.side == .offense ? Color.accentBlue.opacity(0.25) : Color.danger.opacity(0.25))
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(prospect.fullName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Color.textPrimary)
                                        HStack(spacing: 6) {
                                            Text(ProspectFog.read(prospect).labelledText)
                                                .font(.caption2)
                                                .foregroundStyle(Color.textSecondary)
                                            ProspectMarkChip(mark: prospect.userMark)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.textTertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.backgroundSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Mark a target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
            }
        }
    }
}
