import SwiftUI
import SwiftData

// MARK: - Pro Day Tour

/// The `.proDayFocus` stage: pick the schools the department travels to, then
/// send it out ONCE.
///
/// Three things about this screen are deliberate (plan §5.5):
///
/// 1. **One execution path, run once.** Assigning a school *reserves* a focus
///    slot and mutates nothing. The stage-advance button is the only thing that
///    runs the tour. The old screen ran `attendProDay` eagerly on assignment and
///    then offered a big gold "Send Scouts to Pro Days" button whose per-college
///    guard (`contains { !$0.proDayCompleted }`) was always false by the time it
///    was pressed — a no-op with a receipt (F5).
///
///    **That header used to claim the shape could not come back. It had already
///    come back, one door further along (#189).** The screen's only gate was
///    `canAct`, and `canAct` is `DraftPrepProgress.canAct(.proDayFocus)`, which
///    deliberately keeps an EARLIER stage workable — so running the circuit and
///    advancing to `.workouts` left the gold CTA, the "skip the circuit" line
///    and every Reserve button exactly where they were. Pressing Send a second
///    time found every reserved school's men already `proDayCompleted`,
///    `needsRun` false for all of them, `schools` empty — the F5 no-op verbatim,
///    and worse than the original, because the empty run then *overwrote* the
///    real receipt with a blank one.
///
///    The gate is now `hasRunTour`, which is a fact about the circuit rather
///    than about the calendar: a filed receipt for this season, or a scout who
///    has actually attended (`proDaysAttended`, which only the tour writes).
///    Past it there is no Send button, no skip line, no Reserve, and
///    `advanceStage` refuses to write an empty receipt over a real one even if
///    something else calls it. It deliberately reads NOTHING off
///    `proDayCompleted`: the private-workout stage sets that flag too, and
///    while the gate consulted it, one workout at a school the club had merely
///    *booked* closed the circuit before the department ever left (#189b).
/// 1b. **The receipt outlives the view.** `tourResult` was `@State` and nothing
///    else, so the panel that says what the trip bought vanished on the first
///    tab switch and never came back — the one screen in the prep whose whole
///    output is a summary forgot it the moment you looked away. It is persisted
///    per career and stamped with the season (`ProDayTourReceiptStore`), so the
///    recap survives a tab change and a relaunch, and a new draft cycle starts
///    clean without a reset hook.
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
    /// Schools OUR department stood on this cycle, read off the filed receipt.
    /// Never derived from `proDayCompleted` — see `hasToured`.
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

    /// Did the department actually travel? A fact only the tour writes.
    ///
    /// **Never `proDayCompleted`, and never a reservation intersected with it.**
    /// `proDayCompleted` has three writers — `attendProDay`, the league circuit
    /// and `ScoutingEngine.conductPersonalWorkout` — and the private-workout
    /// writer lands on exactly the men this screen's user just reserved (marked,
    /// board-ranked men at the schools he booked). Intersecting the reservation
    /// ledger with it therefore does NOT narrow the question: one private
    /// workout at a reserved school closed this screen for the whole cycle, with
    /// the circuit never run and no longer runnable or skippable (#189b).
    ///
    /// `scout.proDaysAttended` is written by `ScoutingEngine.attendProDay` and
    /// nothing else, `advanceStage` below is its only caller, and `WeekAdvancer`
    /// zeroes it per cycle — so it means "our trip happened this cycle" and
    /// nothing else can forge it.
    private var hasToured: Bool { scouts.contains { $0.proDaysAttended > 0 } }

    /// **The one-shot fact.** The circuit runs once a cycle, and after it has
    /// run — or been explicitly skipped — this screen offers no way to run it
    /// again. `canAct` cannot answer this: it stays `true` for an earlier stage
    /// by design (see the type doc, point 1).
    ///
    /// Receipt or execution. The filed receipt comes first because it is the
    /// only marker that also covers the skip, where nothing at all was written
    /// to any prospect or scout.
    private var hasRunTour: Bool { tourResult != nil || hasToured }

    private var scoutsWithSlots: [Scout] {
        scouts.filter { $0.proDayColleges.count < $0.maxProDays }
    }

    /// The department in the order the decision uses: who can still be spent,
    /// best first. Insertion order answered a question nobody on this screen is
    /// asking — finding the men with a slot left meant reading all eight
    /// "n/3 slots" values.
    private var department: [Scout] {
        scouts.sorted { lhs, rhs in
            let lhsOpen = lhs.proDayColleges.count < lhs.maxProDays
            let rhsOpen = rhs.proDayColleges.count < rhs.maxProDays
            if lhsOpen != rhsOpen { return lhsOpen }
            if lhs.accuracy != rhs.accuracy { return lhs.accuracy > rhs.accuracy }
            return lhs.fullName < rhs.fullName
        }
    }

    /// **Reserving a school does not remove it from here.** It used to: the
    /// filter dropped focused schools, so booking Michigan State deleted its row
    /// and slid the next school up into the gap — a list of the same length,
    /// with nothing on screen saying a row had left rather than the order having
    /// changed. The only acknowledgement was a scout's subtitle further up. The
    /// booked school now stays where it was and wears the RESERVED chip
    /// `schoolStatus` already draws for it.
    private var recommended: [ScoutingEngine.ProDaySchoolSummary] {
        summaries.filter { $0.relevance > 5 }.prefix(5).map { $0 }
    }

    /// The recommended schools still worth a slot — what "Reserve all
    /// recommended" would actually book.
    private var unreservedRecommended: [ScoutingEngine.ProDaySchoolSummary] {
        recommended.filter { !$0.isFocused }
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
                    // One sentence, one source: `DraftPrepProgress` owns every
                    // "why is this shut" line in the prep. The hand-written one
                    // this replaces said "The circuit runs after the combine",
                    // which is true and useless — free agency runs between the
                    // two, so a user who advanced once found the tour still shut
                    // and no screen in the app naming the phase he was waiting
                    // on (#123).
                    message: DraftPrepProgress.screenLockMessage(
                        for: .proDayFocus,
                        phase: career.currentPhase,
                        current: stage
                    )
                )
            } else {
                tourList
            }
        }
        .task { refresh() }
        // ONE sheet modifier. Two of them on the same view is how Reserve came
        // to open an empty card (B1) — see `ActiveSheet`.
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case let .reserveScout(college): scoutSheet(college: college)
                case let .markTarget(college):   focusSheet(college: college)
                }
            }
            // This was the one sheet host in the app carrying no sizing
            // modifier, so it took the default iPad form size — ~564x636 pt.
            // The pinned "Select a scout" bar sliced the fifth scout's stat
            // line in half, three of eight scouts sat below the fold, and the
            // school's own prospect section was invisible: you chose who reads
            // the school without ever seeing who is at it.
            .presentationSizing(.page)
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
            // "Reserve all recommended" is an invitation to spend slots. Once
            // the department is home there is nothing left to spend them on,
            // and an invitation that leads nowhere is the bug class this whole
            // screen exists to close.
            if !recommended.isEmpty && canAct && !hasRunTour { recommendedSection }
            schoolsSection
            // A receipt with no schools on it is the skip, or a run that found
            // nothing to run. It closes the stage; it did not file a report,
            // and must not draw one (F5).
            if let result = tourResult, !result.schools.isEmpty { resultsSection(result) }
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

    /// Past tense once the trip has happened. "4/6 reserved" is a statement
    /// about a plan, and after the department is home there is no plan left for
    /// the user to read it as — the gauge went on describing an intention the
    /// screen had already spent.
    private var slotGaugeSubtitle: String {
        let scoutWord = scouts.count == 1 ? "scout" : "scouts"
        guard hasRunTour else {
            return "\(usedSlots)/\(totalSlots) reserved \u{2022} \(scouts.count) \(scoutWord)"
        }
        guard !(tourResult?.skipped ?? false) else {
            return "Nobody travelled \u{2022} \(scouts.count) \(scoutWord)"
        }
        let worked = schoolsWorked
        return "\(worked) school\(worked == 1 ? "" : "s") worked \u{2022} \(scouts.count) \(scoutWord)"
    }

    /// How many schools the department actually stood on: the filed receipt,
    /// which is the only place the trip itself is enumerated. A reservation can
    /// be edited and `proDayCompleted` has writers this trip never met, so
    /// neither may be counted here.
    private var schoolsWorked: Int {
        (tourResult?.skipped ?? false) ? 0 : (tourResult?.schools.count ?? 0)
    }

    /// "Focus slots" is a heading about a plan. After the act it has to name
    /// the act.
    private var slotGaugeTitle: String {
        guard hasRunTour else { return "Focus slots" }
        return (tourResult?.skipped ?? false) ? "Circuit skipped" : "Circuit spent"
    }

    private var focusSlotGauge: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "scope")
                    .font(.title3)
                    .foregroundStyle(Color.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(slotGaugeTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(slotGaugeSubtitle)
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
                            // NEVER `danger`. A nearly full bar is a department
                            // that has committed its scouts, which is the point
                            // of the stage — red said the user had done
                            // something wrong by using what he was given.
                            .fill(Color.accentGold)
                            .frame(width: geo.size.width * progress)
                    }
                }
                // 200 pt, not 60: the row has the width to spare and one slot
                // out of 25 is 2.4 pt on a 60 pt track — a tick the eye reads as
                // an empty bar, on the one control that has to show the first
                // reservation landing.
                .frame(width: 200, height: 6)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Department

    private var departmentSection: some View {
        Section {
            ForEach(department) { scout in
                scoutRow(scout)
            }
        } header: {
            HStack {
                Text("Your department")
                Spacer()
                Text(hasRunTour
                     ? "Circuit complete"
                     : "\(slotsLeft) slot\(slotsLeft == 1 ? "" : "s") left")
                    .font(.caption2)
                    .foregroundStyle(hasRunTour ? Color.success
                                     : (slotsLeft == 0 ? Color.danger : Color.textTertiary))
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
                        .font(.system(size: DSType.Size.body, weight: .semibold))
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
            if slotsLeft > 0 && !hasRunTour && !unreservedRecommended.isEmpty {
                Button { reserveAllRecommended() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "scope")
                        Text("Reserve all recommended")
                            .font(.caption.weight(.bold))
                        Spacer()
                        Text("\(min(slotsLeft, unreservedRecommended.count)) slot\(min(slotsLeft, unreservedRecommended.count) == 1 ? "" : "s")")
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
                            .font(.system(size: DSType.Size.micro, weight: .bold))
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
                .font(.system(size: DSType.Size.caption))
                .foregroundStyle(Color.textTertiary)
        }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: DSType.Size.micro, weight: .bold))
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
                    .font(.system(size: DSType.Size.caption, weight: .black))
                    .foregroundStyle(Color.accentGold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentGold.opacity(0.14), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                // Releasing a booking after the trip is over cannot un-book
                // anything — the X was still there, and it silently rewrote the
                // ledger the recap is read against.
                if canAct && !hasRunTour {
                    Button { releaseFocus(college: info.college) } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Release \(info.college)")
                }
            }
        } else if hasRunTour {
            // The circuit is behind the club and this school was not on it.
            Text("Not on the circuit")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
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
                .font(.system(size: DSType.Size.micro, weight: .heavy).monospacedDigit())
                .foregroundStyle((boardRanks[prospect.id] ?? 999) <= 10 ? Color.accentGold : Color.textTertiary)
                .frame(width: 28, alignment: .trailing)

            Text(prospect.position.rawValue)
                .font(.system(size: DSType.Size.micro, weight: .bold))
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
                        .font(.system(size: DSType.Size.caption, weight: .bold))
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

    /// The CTA, the skip line — or, once the circuit is behind the club, the
    /// closed state that replaces both.
    ///
    /// The `hasRunTour` branch comes FIRST and is not conditioned on `canAct`:
    /// `canAct` stays true for a stage the club has walked past, so gating this
    /// on it is precisely what left a live "Send the department out" over a
    /// department that was already home (#189, type doc point 1).
    @ViewBuilder
    private var advanceSection: some View {
        if hasRunTour {
            circuitClosedSection
        } else if canAct {
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

    /// What stands where the CTA was. A door that is shut still has to look
    /// like a door — the alternative (drawing nothing) is the blank action slot
    /// this screen already fixed once, in `schoolStatus`.
    private var circuitClosedSection: some View {
        let worked = schoolsWorked
        let skipped = tourResult?.skipped ?? false
        // Hoisted out of the `Text` so the branch is a plain `String` the type
        // checker settles in one step, rather than a nested ternary of
        // interpolated literals inside a `Text` initialiser.
        let closedLine: String = {
            if worked > 0 {
                return "The department is home from \(worked) school\(worked == 1 ? "" : "s"). The circuit runs once a cycle."
            }
            if skipped {
                return "You read this one off the broadcast feed \u{2014} the department stayed home."
            }
            return "Nothing came back from this circuit. It runs once a cycle."
        }()
        return Section {
            HStack(spacing: 10) {
                Image(systemName: worked > 0 ? "checkmark.seal.fill" : "tv")
                    .font(.title3)
                    .foregroundStyle(worked > 0 ? Color.success : Color.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Circuit complete")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    Text(closedLine)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.backgroundSecondary)
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
        // The stage is a *stage* to `canAct` but a one-shot *act* to the user.
        // Booking a school for a trip that already happened writes a
        // reservation nothing will ever honour.
        guard !hasRunTour else { return }
        guard scout.proDayColleges.count < scout.maxProDays else { return }
        guard !reservedColleges.contains(college) else { return }
        scout.proDayColleges.append(college)
        try? modelContext.save()
        refresh()
        onRefresh()
    }

    /// `!hasRunTour` is the whole guard: past the trip nothing may be released,
    /// and before it every reservation is still just a plan. The extra
    /// `!visitedColleges.contains(college)` this used to carry inherited the
    /// `proDayCompleted` false positive — a private workout at a booked school
    /// silently swallowed the release.
    private func releaseFocus(college: String) {
        guard canAct, !hasRunTour else { return }
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
            // Same pick the reserve sheet's tip makes, for the same reason: the
            // best specialist, then the best scout left.
            let specialists = topPosition.map { position in
                scoutsWithSlots.filter { $0.positionSpecialization == position }
            } ?? []
            let scout = specialists.max { $0.accuracy < $1.accuracy }
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
    /// circuit simply never happened. Both outcomes file a receipt, because the
    /// receipt is also the one-shot marker (`hasRunTour`) — a skip that left no
    /// trace let the user come back and send a department the alert had just
    /// promised would stay home.
    private func advanceStage(runTour: Bool) {
        guard canAct else { return }
        // Belt to `advanceSection`'s braces: nothing may run the circuit twice,
        // whatever route reaches this function.
        guard !hasRunTour else { return }

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

            fileReceipt(ProDayTourResult(
                season: career.currentSeason,
                skipped: false,
                schools: schools,
                prospectsEvaluated: evaluated,
                findings: Array(findings.prefix(5))
            ))
        } else {
            // The skip. An empty receipt: it closes the stage and says nothing
            // was filed, which is exactly what happened.
            fileReceipt(ProDayTourResult(
                season: career.currentSeason,
                skipped: true,
                schools: [],
                prospectsEvaluated: 0,
                findings: []
            ))
        }

        career.advancePrepStep(to: .workouts)
        try? modelContext.save()
        refresh()
        onRefresh()
    }

    /// Writes the receipt to `@State` and to the save, and mails the digest.
    ///
    /// **The guard is the point.** An empty receipt may never replace a real
    /// one. That is not hypothetical: the second press of the old CTA produced
    /// exactly this — a run in which every reserved school was already worked,
    /// so `schools` came back empty — and it blanked the panel that had just
    /// told the user what the trip bought.
    private func fileReceipt(_ receipt: ProDayTourResult) {
        if receipt.schools.isEmpty, let existing = tourResult, !existing.schools.isEmpty {
            return
        }
        tourResult = receipt
        ProDayTourReceiptStore.save(receipt)
        mailDigest(receipt)
    }

    /// The user's own circuit, in the inbox.
    ///
    /// The LEAGUE circuit already mails one (`InboxEngine.proDayCircuitMessage`,
    /// from `WeekAdvancer`) — the public numbers off the wire. The club's own
    /// trip, the expensive half, filed nothing anywhere: the only record it
    /// ever existed was a `@State` panel that died with the view. The two
    /// letters are deliberately different documents; this one is about what the
    /// department saw with its own eyes.
    private func mailDigest(_ receipt: ProDayTourResult) {
        guard let message = InboxEngine.proDayTourDigestMessage(
            schools: receipt.schools,
            prospectsEvaluated: receipt.prospectsEvaluated,
            findings: receipt.findings,
            dateString: InboxEngine.dateLabel(
                week: career.currentWeek,
                season: receipt.season,
                phase: career.currentPhase
            )
        ) else { return }

        // The process-global staging channel every out-of-shell producer posts
        // through; `CareerShellView.collectInboxMessages` drains it. Deduped
        // against both books so a re-file cannot mail the same letter twice.
        let alreadyFiled = career.inbox.contains { $0.subject == message.subject }
            || WeekAdvancer.lastInboxMessages.contains { $0.subject == message.subject }
        guard !alreadyFiled else { return }
        WeekAdvancer.lastInboxMessages.append(message)
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
        for prospect in prospects where prospect.isDeclaringForDraft {
            grouped[prospect.college, default: []].append(prospect)
        }
        for key in Array(grouped.keys) {
            grouped[key]?.sort { ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0) }
        }
        prospectsByCollege = grouped

        var bestNames: [String: String] = [:]
        for summary in summaries {
            if let id = summary.bestProspectID,
               let match = grouped[summary.college]?.first(where: { $0.id == id }) {
                bestNames[summary.college] = match.fullName
            }
        }
        bestNameByCollege = bestNames

        // The filed receipt is the source of truth for the recap, not `@State`.
        // Season-stamped, so the read comes back `nil` in the next draft cycle
        // and the screen opens clean without anybody remembering to reset it —
        // the same trick `Career.prepStep` uses.
        let receipt = ProDayTourReceiptStore.load(season: career.currentSeason) ?? tourResult
        if let receipt {
            tourResult = receipt
        }
        // …and the only enumeration of where the department stood. This used to
        // be every school with one `proDayCompleted` man, which a single private
        // workout at the next stage was enough to forge — the row then wore a
        // "Visited" seal for a trip nobody took and lost its Reserve button.
        let toured: [String] = (receipt?.skipped ?? true) ? [] : (receipt?.schools ?? [])
        visitedColleges = Set(toured)
    }

    // MARK: - Helpers

    private func bestScoutFor(college: String) -> (scout: Scout, reason: String)? {
        let pool = prospectsByCollege[college] ?? []
        guard !pool.isEmpty else { return nil }
        let topPosition = Dictionary(grouping: pool) { $0.position }
            .max { $0.value.count < $1.value.count }?.key

        // The BEST specialist, not the first one the array happens to hold. Two
        // men can carry the same specialisation, and picking by array order
        // recommended the less accurate of them over his own colleague.
        if let position = topPosition,
           let specialist = scoutsWithSlots
               .filter({ $0.positionSpecialization == position })
               .max(by: { $0.accuracy < $1.accuracy }) {
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
                .font(.system(size: DSType.Size.hero))
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
///
/// `Codable` and season-stamped because it is persisted: see
/// ``ProDayTourReceiptStore``. An **empty `schools`** is meaningful — it is the
/// skip, or a run that found nothing left to run — and every reader must treat
/// it as "the circuit is behind us and filed nothing", never as a report.
struct ProDayTourResult: Codable, Equatable {
    /// The draft cycle this receipt belongs to. A receipt from an earlier
    /// season reads as absent rather than as a tour this club just ran.
    let season: Int
    /// The user chose "watch it on the feed". Stored rather than inferred from
    /// an empty `schools`, because the two empty receipts mean different things
    /// to the reader: a skip is a decision, and a sent department that found
    /// nobody left to watch is an accident. Telling a club that travelled it
    /// stayed home is the same class of lie as a no-op with a receipt.
    let skipped: Bool
    let schools: [String]
    let prospectsEvaluated: Int
    let findings: [String]
}

// MARK: - Receipt store

/// The pro-day tour receipt, per career, per season.
///
/// `tourResult` was `@State` and nothing else, so the panel summarising the
/// single most expensive act of the stage survived exactly as long as the view
/// did: switching to the Big Board tab and back erased it, and so did a
/// relaunch. Nothing else in the app records that the club's own department
/// ever travelled — `proDayCompleted` is set by three different callers and
/// says nothing about who paid — so the recap was the whole record, and it was
/// the most volatile state in the screen.
enum ProDayTourReceiptStore {

    /// Listed in `CareerScopedDefaults.keys`, so a deleted save takes its
    /// receipt with it.
    static let defaultsKey = "proDayTourReceipt"

    /// The receipt for this cycle, or `nil` — including when the stored one
    /// belongs to a previous season, which is how the store expires without a
    /// rollover hook.
    static func load(season: Int) -> ProDayTourResult? {
        guard let json: String = CareerScopedDefaults.value(defaultsKey),
              let decoded = try? JSONDecoder().decode(ProDayTourResult.self, from: Data(json.utf8)),
              decoded.season == season
        else { return nil }
        return decoded
    }

    static func save(_ receipt: ProDayTourResult) {
        guard let data = try? JSONEncoder().encode(receipt) else { return }
        CareerScopedDefaults.set(String(decoding: data, as: UTF8.self), defaultsKey)
    }
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

    /// Recommended first, then by accuracy, with the men who have no slot left
    /// at the bottom. Role order put the two recommended scouts 1st and 5th
    /// with three rows the user cannot use between them, and left one of them
    /// under the pinned button bar.
    private var sortedScouts: [Scout] {
        scouts.sorted { lhs, rhs in
            let lhsFull = lhs.proDayColleges.count >= lhs.maxProDays
            let rhsFull = rhs.proDayColleges.count >= rhs.maxProDays
            if lhsFull != rhsFull { return rhsFull }
            let lhsRecommended = isRecommended(lhs)
            let rhsRecommended = isRecommended(rhs)
            if lhsRecommended != rhsRecommended { return lhsRecommended }
            if lhs.accuracy != rhs.accuracy { return lhs.accuracy > rhs.accuracy }
            return lhs.fullName < rhs.fullName
        }
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
                                        .font(.system(size: DSType.Size.micro))
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
                    .font(.system(size: DSType.Size.title3))
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
                                .font(.system(size: DSType.Size.caption, weight: .bold))
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
                        .font(.system(size: DSType.Size.caption, weight: .black))
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
                .font(.system(size: DSType.Size.micro, weight: .bold))
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
                                        .font(.system(size: DSType.Size.micro, weight: .bold))
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
