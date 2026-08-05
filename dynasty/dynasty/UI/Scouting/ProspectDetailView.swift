import SwiftUI
import SwiftData

// MARK: - Scout evaluation economy
//
// "Send Scout to Evaluate" was the hole in the middle of the intel economy.
// The combine trip is priced ($300-620K out of the owner's scouting pot),
// interviews are rationed (60 a cycle, combine window only), private workouts
// are rationed (30), Top-30 visits are rationed (30) — and the one button that
// files an actual `ScoutingReport`, the thing `ProspectFog` reads to decide how
// much of a man the user is allowed to see, was free, unlimited and available
// in every phase of the calendar. Three taps on any prospect took
// `DraftIntel.scoutConfidence` to 5 and collapsed his band to a single letter,
// so nothing else in the economy had to be bought at all.
//
// It is now a rationed, priced, windowed action like the other four.

/// Prices and rations the per-prospect scouting evaluation.
enum ScoutEvaluationBudget {

    /// Evaluations the department can run in one draft cycle.
    ///
    /// Sized against the rest of the board: 60 interview slots and 30 workouts
    /// buy *depth* on men you already know, and 25 evaluations is what it takes
    /// to put a first report on a quarter of the consensus top 100. Covering
    /// the class is the combine trip's and the pro-day tour's job.
    static let slotsPerCycle = 25

    /// Reports one prospect may carry. The detail card has always drawn a
    /// "\(count)/3 scouts" confidence meter; nothing enforced it, so a fourth
    /// and fifth look were possible and simply invisible.
    static let maxReportsPerProspect = 3

    /// Phases in which the club may put a scout on a college prospect.
    ///
    /// The same window in which the hub considers a draft class to exist
    /// (`ScoutingHubView.loadData`), minus `.otas` — by OTAs the class has been
    /// drafted and evaluating it buys nothing.
    static func isWindowOpen(_ phase: SeasonPhase) -> Bool {
        switch phase {
        case .coachingChanges, .reviewRoster, .combine, .freeAgency, .proDays, .draft:
            return true
        default:
            return false
        }
    }

    /// One line of prose naming when the window reopens.
    ///
    /// The regular season is split on purpose. The class is generated in week 9,
    /// so from then on the board is real and readable — it is only the *paid*
    /// report that has to wait for the offseason. The old copy told a user
    /// staring at a full board in week 12 that "the class is off the board until
    /// next season", which is wrong twice over: the class is right there, and
    /// the window he is waiting for is nine weeks away, not a year.
    static func windowHint(for phase: SeasonPhase) -> String {
        switch phase {
        case .regularSeason, .tradeDeadline, .playoffs:
            return "Read-only until the season ends. Your department files its first paid reports at the coaching changes."
        case .otas, .trainingCamp, .preseason, .rosterCuts:
            return "This class has been drafted. The next one goes on the board in week \(TaskGenerator.draftClassOnBoardWeek)."
        default:
            return "Scouting opens with the coaching changes."
        }
    }

    /// Cost in thousands of the *next* report on a man who already carries
    /// `existingReports`.
    ///
    /// Rising, because that is where the exploit lived: the first look is a
    /// cheap tape grade, the third is a cross-check trip nobody runs on a man
    /// they are not seriously considering. Twenty-five slots at these prices is
    /// $500K-1.4M of a $4.0M pot depending on how deep the user doubles back —
    /// the same order as the combine trip, so the two compete for the money.
    static func cost(existingReports: Int) -> Int {
        switch existingReports {
        case 0:  return 20
        case 1:  return 35
        default: return 55
        }
    }

    /// The cycle-scoped read of a stored counter: a stamp from an earlier draft
    /// cycle reads as zero, so slots and spend reset with the new class instead
    /// of needing a hook in `WeekAdvancer`.
    static func thisCycle(_ stored: Int, stampedSeason: Int, currentSeason: Int) -> Int {
        stampedSeason == currentSeason ? stored : 0
    }
}

/// Why the evaluate button is (not) tappable. Every blocked case carries the
/// sentence the row prints — a disabled control that does not say why is the
/// bug this whole pass exists to stop repeating.
enum ScoutEvaluationAvailability {
    case available(cost: Int, slotsLeft: Int)
    case windowShut(hint: String)
    case noScouts
    case slotsSpent
    case reportsMaxed
    case cannotAfford(cost: Int, remaining: Int)

    var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

struct ProspectDetailView: View {
    let career: Career
    let prospect: CollegeProspect

    /// `true` when this card was opened from the war room while the draft clock
    /// is running (`LiveBigBoardPanel`, `PickSheetView`).
    ///
    /// The card is a READ on draft night. Every one of its priced, rationed
    /// actions is a spring action that mutates the man the user is about to
    /// pick: "Invite for Workout" rewrites his measurables and burns a slot,
    /// "Send Scout" files a report that moves his `ProspectFog` band and then
    /// re-persists the whole class onto the same `ModelContext` the clock task
    /// is writing — while `DraftDayCoordinator` holds cached `publicBoardRanks`
    /// / `userBoardRanks` / `availableProspects` that nothing invalidates, so
    /// the row and the number beside it would disagree for the rest of the
    /// round. `.draft` is inside all three spring windows
    /// (`ScoutEvaluationBudget.isWindowOpen`, `isWorkoutWindow`), which is
    /// correct for the scouting hub in draft WEEK and wrong for the clock.
    ///
    /// Marks and notes stay live: they are free, local to the user's own board
    /// and are the whole point of having the card on the clock.
    var isLiveDraftCard: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var scouts: [Scout] = []
    @State private var coaches: [Coach] = []
    /// The one sheet this card can have open. See ``CardSheet``.
    @State private var activeSheet: CardSheet?
    @State private var showInterviewResult = false
    @State private var interviewResult: (personality: PersonalityArchetype, footballIQ: Int, characterNotes: [String])?
    @State private var positionRank: Int?
    @State private var teamPlayers: [Player] = []
    /// The user's club, for the one thing this screen needs money for: pricing a
    /// rookie contract at the league's ACTUAL cap (task #87 / F17).
    @State private var userTeam: Team?
    /// Set by `performWorkout`; presents the shared `WorkoutResultSheet`.
    /// The owner's scouting pot in thousands, loaded with the scouts.
    @State private var scoutingBudget: Int = 4_000

    // MARK: - Evaluation ledger (career- and cycle-scoped)

    /// Evaluations run this cycle. Stored career-scoped like `combineTripSpend`
    /// rather than on `Career` so the three counters travel together and a
    /// deleted save purges them with everything else.
    @CareerScopedStorage("scoutEvaluationsUsed") private var evaluationsUsedStored: Int = 0
    /// Thousands of the scouting pot committed to evaluations this cycle.
    @CareerScopedStorage("scoutEvaluationSpend") private var evaluationSpendStored: Int = 0
    /// The season the two counters above belong to. A mismatch means a new
    /// draft class, and both read as zero.
    @CareerScopedStorage("scoutEvaluationCycle") private var evaluationCycleStored: Int = 0

    private var evaluationsUsed: Int {
        ScoutEvaluationBudget.thisCycle(
            evaluationsUsedStored,
            stampedSeason: evaluationCycleStored,
            currentSeason: career.currentSeason
        )
    }

    private var evaluationSpend: Int {
        ScoutEvaluationBudget.thisCycle(
            evaluationSpendStored,
            stampedSeason: evaluationCycleStored,
            currentSeason: career.currentSeason
        )
    }

    private var evaluationSlotsLeft: Int {
        max(0, ScoutEvaluationBudget.slotsPerCycle - evaluationsUsed)
    }

    // MARK: - Derived

    /// The user-facing overall grade, through `ProspectFog` so this card and the
    /// Big Board print the same band for the same man.
    ///
    /// Still `nil` for a prospect nobody has filed on — the header's "?" branch
    /// and the "vs Current Starter" fallback both key off that — but a scouted
    /// prospect now gets the *confidence-widened* band rather than the raw
    /// stored range. Reading `prospect.effectiveOverallGrade` straight made this
    /// screen the one place in the app that looked more certain than the scouts
    /// actually were.
    private var effectiveOverallGrade: GradeRange? {
        let read = ProspectFog.read(prospect)
        return read.source == .scouts ? read.band : nil
    }

    private var isScouted: Bool { prospect.scoutedOverall != nil }
    private var hasCombine: Bool {
        prospect.fortyTime != nil || prospect.benchPress != nil ||
        prospect.verticalJump != nil || prospect.broadJump != nil ||
        prospect.shuttleTime != nil || prospect.coneDrill != nil
    }
    private static let maxInterviews = 60
    private static let maxWorkouts = 30

    // MARK: - Phase gates
    //
    // These used to disagree with the hub that owns them. The Interviews tab is
    // visible in `.combine` AND `.proDays` (`ScoutingHubView.visibleTabs`), and
    // the Draft Prep card counts interview slots as live in both — but this card
    // accepted only `.combine`, so a user who followed the hub into pro days
    // found a prospect page with no interview button and no explanation. The
    // workout gate had the mirror-image bug: it accepted `.combine` and `.draft`
    // and refused `.proDays`, the phase named after the event. The hub is the
    // truth; both windows below are copied from it.

    /// `ScoutingHubView.visibleTabs` shows the Interviews tab exactly here.
    private var isInterviewWindow: Bool {
        guard !isLiveDraftCard else { return false }
        return career.currentPhase == .combine || career.currentPhase == .proDays
    }

    /// The workout LADDER, not a phase window (plan F3 / §5.2).
    ///
    /// This used to be a phase test that opened on the first day of the combine
    /// — the most rationed instrument in the pre-draft process was live before
    /// anybody had watched a single frame of tape, which is exactly backwards.
    /// The stage machine is the gate now: a private workout is available from
    /// the workout stage onward, and `WorkoutsTabView` reads the same line.
    private var isWorkoutWindow: Bool {
        guard !isLiveDraftCard else { return false }
        return career.prepStep.order >= DraftPrepStep.workouts.order
    }

    /// The one sentence every blocked action prints on draft night, so a
    /// greyed-out row on the clock still says why.
    private static let liveDraftHint = "The clock is running \u{2014} the board is a read tonight. Pre-draft work closed with the last pro day."

    private var canInterview: Bool {
        isInterviewWindow && !prospect.interviewCompleted && career.interviewsUsed < Self.maxInterviews
    }

    /// One man, one private workout. The record of it is the filed
    /// `.personalWorkout` report — NOT `proDayCompleted`, which the pro-day tour
    /// sets for every declared man at a focused school and which therefore
    /// blocked the workout stage on exactly the prospects the tour was for.
    /// `WorkoutsTabView` reads the same line.
    private var canWorkout: Bool {
        isWorkoutWindow
            && !ScoutingEngine.hasWorkedOutPrivately(prospect)
            && career.workoutsUsed < Self.maxWorkouts
    }

    // MARK: - Evaluation gate

    /// What is left of the owner's scouting pot: the same arithmetic
    /// `ScoutingHubView.remainingScoutingBudget` does, so the number quoted on
    /// this button matches the one on the hub's budget tile.
    private var remainingScoutingBudget: Int {
        let combineTripSpend: Int = CareerScopedDefaults.value("combineTripSpend") ?? 0
        return scoutingBudget
            - scouts.reduce(0) { $0 + $1.salary }
            - combineTripSpend
            - evaluationSpend
    }

    private var evaluationAvailability: ScoutEvaluationAvailability {
        guard !isLiveDraftCard else { return .windowShut(hint: Self.liveDraftHint) }
        guard ScoutEvaluationBudget.isWindowOpen(career.currentPhase) else {
            return .windowShut(hint: ScoutEvaluationBudget.windowHint(for: career.currentPhase))
        }
        guard !scouts.isEmpty else { return .noScouts }
        guard prospect.scoutingReports.count < ScoutEvaluationBudget.maxReportsPerProspect else {
            return .reportsMaxed
        }
        guard evaluationSlotsLeft > 0 else { return .slotsSpent }
        let cost = ScoutEvaluationBudget.cost(existingReports: prospect.scoutingReports.count)
        guard remainingScoutingBudget >= cost else {
            return .cannotAfford(cost: cost, remaining: remainingScoutingBudget)
        }
        return .available(cost: cost, slotsLeft: evaluationSlotsLeft)
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            List {
                headerSection
                myVerdictSection
                quickAssessmentRow
                if isScouted { scoutingReportSection }
                starterComparisonSection
                combineSection
                collegeProductionSummarySection
                positionSkillsSection
                draftSection
                characterFileSection
                riskFlagsSection
                if prospect.interviewCompleted { interviewResultsSection }
                teamInterestRow
                actionsSection
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .safeAreaInset(edge: .bottom) {
            actionButtonBar
        }
        .navigationTitle(prospect.fullName)
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            loadScouts(); loadCoaches(); loadPositionRank(); loadTeamPlayers()
            // The value row reads `DraftIntel.consensusRank`, a per-session
            // cache the scouting hub warms. A card reached straight from a
            // task list has not been through the hub, so warm it here too.
            if DraftIntel.consensusRank(for: prospect.id) == nil {
                DraftIntel.refreshConsensusBoard(for: WeekAdvancer.currentDraftClass)
            }
        }
        // ONE sheet modifier.
        //
        // This view carried THREE on the same node — two `.sheet(isPresented:)`
        // plus this `.sheet(item:)`. SwiftUI honours one per view and the last
        // written wins, so flipping `showSendScout` or `showMarkNote` presented
        // the WORKOUT-RESULT builder with no result: an empty card. The evaluate
        // button on a prospect's page opened nothing, which is the prospect-card
        // half of "film study could not be assigned to anyone" (B3), and the
        // note editor was dead the same way.
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .sendScout:
                SendScoutSheet(
                    prospect: prospect,
                    scouts: scouts,
                    scoutingPhase: currentScoutingPhase,
                    cost: ScoutEvaluationBudget.cost(existingReports: prospect.scoutingReports.count),
                    slotsLeft: evaluationSlotsLeft,
                    budgetRemaining: remainingScoutingBudget,
                    onFiled: { recordEvaluation(cost: $0) }
                )
            case .markNote:
                ProspectMarkNoteSheet(
                    prospectName: prospect.fullName,
                    initialNote: prospect.userMarkNote,
                    onSave: { note in
                        // Writing a note on an unmarked man puts him on the board
                        // rather than stranding the text on a prospect nothing tracks.
                        prospect.setUserMark(prospect.isMarked ? prospect.userMark : .target, note: note)
                        try? modelContext.save()
                        activeSheet = nil
                    },
                    onCancel: { activeSheet = nil }
                )
            case let .workoutResult(result):
                WorkoutResultSheet(
                    result: result,
                    prospect: prospect,
                    slotsUsed: career.workoutsUsed,
                    slotLimit: Self.maxWorkouts
                )
            }
        }
    }

    /// The card's single sheet slot — one enum makes "two sheets at once"
    /// unrepresentable instead of silently resolved in favour of whichever
    /// modifier happened to be written last.
    enum CardSheet: Identifiable {
        /// Put a scout on this man — the priced evaluation.
        case sendScout
        /// Edit the note attached to this man's board mark.
        case markNote
        /// The result of a private workout that just ran.
        case workoutResult(ScoutingEngine.WorkoutResult)

        var id: String {
            switch self {
            case .sendScout:     return "sendScout"
            case .markNote:      return "markNote"
            case .workoutResult: return "workoutResult"
            }
        }
    }

    // MARK: - My Verdict
    //
    // The deep dive used to end in a dead end: forty numbers, eight mental
    // grades, an interview transcript — and the only thing the user could
    // record about any of it was a single "Add to Board" star that three of the
    // four mark systems could not see. This is where the read becomes a verdict.

    @ViewBuilder
    private var myVerdictSection: some View {
        Section {
            ProspectMarkPicker(prospect: prospect) {
                try? modelContext.save()
            }
            .listRowBackground(Color.backgroundSecondary)

            Button {
                activeSheet = .markNote
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundStyle(Color.accentGold)
                        .padding(.top, 2)
                    if prospect.userMarkNote.isEmpty {
                        Text("Add a note \u{2014} why he is where he is on your board.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textTertiary)
                    } else {
                        Text(prospect.userMarkNote)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
            .listRowBackground(Color.backgroundSecondary)

            // What the market thinks versus what you graded him.
            if let read = ProspectFog.valueRead(
                for: prospect,
                marketRank: DraftIntel.consensusRank(for: prospect.id),
                myGrade: UserProspectGradeStore.shared.grade(for: prospect.id)
            ) {
                LabeledContent("Value vs My Grade") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(read.label)
                            .font(.body.weight(.bold))
                            .foregroundStyle(read.tint)
                        Text("market \u{2248} #\(read.marketRank) \u{00B7} you \u{2248} #\(read.impliedPick)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)
            }
        } header: {
            Text("My Verdict")
        }
    }

    // MARK: - Character & Medical File
    //
    // `DraftClassBuilder` has written `medicalConcerns` and `redFlags` into
    // every class since the generator overhaul and NO screen has ever rendered
    // either of them — a torn ACL and a failed drug test were data the game
    // knew and the user could not buy at any price. They are not free, though:
    // `ProspectFog.flagDisclosure` opens the file in three steps, so the count
    // appears once anybody has been near him and the contents only once the
    // work has actually been done.

    @ViewBuilder
    private var characterFileSection: some View {
        let medical = prospect.medicalConcerns ?? []
        let character = prospect.redFlags ?? []
        let total = medical.count + character.count
        let disclosure = ProspectFog.flagDisclosure(for: prospect, userTeamID: career.teamID)

        if disclosure != .hidden {
            Section("Medical & Character File") {
                switch disclosure {
                case .hidden:
                    EmptyView()

                case .count:
                    if total == 0 {
                        fileLine(
                            icon: "checkmark.seal",
                            tint: .textSecondary,
                            title: "Nothing flagged so far",
                            detail: ProspectFog.flagDisclosureHint(for: prospect)
                        )
                    } else {
                        fileLine(
                            icon: "lock.doc.fill",
                            tint: .warning,
                            title: "\(total) item\(total == 1 ? "" : "s") on file",
                            detail: ProspectFog.flagDisclosureHint(for: prospect)
                        )
                    }

                case .full:
                    if total == 0 {
                        fileLine(
                            icon: "checkmark.seal.fill",
                            tint: .success,
                            title: "Clean file",
                            detail: "No medical or character flags."
                        )
                    } else {
                        ForEach(medical, id: \.self) { concern in
                            fileLine(
                                icon: "cross.case.fill",
                                tint: .warning,
                                title: concern,
                                detail: "Medical"
                            )
                        }
                        ForEach(character, id: \.self) { flag in
                            fileLine(
                                icon: "exclamationmark.triangle.fill",
                                tint: .danger,
                                title: flag,
                                detail: "Character"
                            )
                        }
                    }
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    private func fileLine(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(detail): \(title)")
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            HStack(alignment: .top, spacing: 16) {
                // Portrait — a draft class is 350 faceless names, so the head
                // shot is the cheapest way to make one prospect memorable.
                PersonFaceView(prospect: prospect, size: .medium)

                // Position badge
                VStack {
                    Text(prospect.position.rawValue)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 54, height: 54)
                        .background(positionColor, in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(prospect.college)
                            .font(.headline)
                            .foregroundStyle(Color.textSecondary)

                        if let rank = positionRank {
                            Text("#\(rank) \(prospect.position.rawValue) in class")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(rank <= 3 ? Color.accentGold : Color.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill((rank <= 3 ? Color.accentGold : Color.textSecondary).opacity(0.15))
                                )
                        }
                    }

                    HStack(spacing: 16) {
                        ProspectInfoPill(label: "Age", value: "\(prospect.age)")
                        ProspectInfoPill(label: "Ht", value: heightLabel)
                        ProspectInfoPill(label: "Wt", value: "\(prospect.weight) lbs")
                    }
                }

                Spacer()

                if let gradeRange = effectiveOverallGrade {
                    VStack(spacing: 2) {
                        Text(gradeRange.displayText)
                            .font(.system(size: gradeRange.isSingleGrade ? 36 : 28, weight: .heavy))
                            .foregroundStyle(detailGradeColor(gradeRange.midGrade))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("Overall")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                        scoutConfidenceBadge

                        // Draft projection
                        if let rd = prospect.draftProjection {
                            Text("Rd \(rd)")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(projectionColor(rd))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(projectionColor(rd).opacity(0.15), in: Capsule())
                        }

                        // Potential assessment
                        potentialBadge
                    }
                } else {
                    VStack(spacing: 2) {
                        Text("?")
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundStyle(Color.textTertiary)
                        Text("Unscouted")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Scout Confidence Badge

    private var scoutConfidenceBadge: some View {
        let count = prospect.scoutReportCount
        let confidenceColor: Color
        let confidenceLabel: String
        switch count {
        case 0:  confidenceColor = .textTertiary; confidenceLabel = "Unscouted"
        case 1:  confidenceColor = .warning;      confidenceLabel = "Low"
        case 2:  confidenceColor = .accentBlue;   confidenceLabel = "Medium"
        default: confidenceColor = .success;      confidenceLabel = "High"
        }
        // The grade above is only as reliable as the number of scout visits behind
        // it — make that explicit so the user knows whether to trust it or send
        // more scouts.
        return HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(i < count ? confidenceColor : confidenceColor.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Text("\(confidenceLabel) confidence · \(count)/3 scouts")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(confidenceColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(confidenceColor.opacity(0.12), in: Capsule())
        .help("Grade reliability: \(confidenceLabel.lowercased()) — \(count) of 3 possible scout visits completed.")
    }

    // MARK: - Potential Badge

    private var potentialBadge: some View {
        let label = prospect.scoutedPotentialLabel ?? .unknown
        let color = potentialLabelColor(label)
        return Group {
            if label != .unknown {
                Text(label.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Quick Assessment Row

    @ViewBuilder
    private var quickAssessmentRow: some View {
        let risk = prospect.riskLevel
        let fit = evaluateSchemeFit()
        let readiness = ProspectReadinessBucket(readiness: prospect.nflReadiness)
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    // Risk badge
                    if risk != .unknown {
                        assessmentBadge(icon: risk.icon, label: risk.rawValue, color: risk.color)
                    }
                    // Scheme fit badge
                    if let fit {
                        assessmentBadge(icon: schemeFitIcon(fit), label: "Fit: \(fit)", color: schemeFitColor(fit))
                    }
                    // Athletic profile badge
                    if hasCombine {
                        assessmentBadge(icon: "figure.run", label: athleticProfileLabel, color: athleticProfileColor)
                    }
                    // Stock trajectory
                    let trajectory = prospect.stockTrajectory
                    if trajectory != .newOnBoard {
                        assessmentBadge(icon: trajectory.icon, label: trajectory.rawValue, color: trajectory.color)
                    }
                    // Draft value mismatch warning
                    if let proj = prospect.draftProjection, let ovr = prospect.scoutedOverall {
                        let projectedMinOvr = projectionMinOverall(proj)
                        if ovr < projectedMinOvr {
                            assessmentBadge(icon: "exclamationmark.triangle.fill", label: "Overdraft?", color: .danger)
                        }
                    }
                }

                // NFL readiness insight — how much of his talent lands on the
                // field in year one. Shown as a bucket, never as the raw hidden
                // number that drives the rookie conversion.
                HStack(spacing: 6) {
                    Image(systemName: readiness.icon)
                        .font(.caption2)
                        .foregroundStyle(readiness.color)
                    Text(readiness.label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(readiness.color)
                    Text(verbatim: "·")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    Text(readiness.detail)
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func assessmentBadge(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }

    /// Minimum expected OVR for a given draft round projection.
    ///
    /// Anchored to `DraftClassBuilder.talentTarget` at each band's *floor*
    /// (R1 78.9 · R2 75.0 · R3 72.5 · R4 70.7 · R5 69.2 · R6 67.5 · R7 64.8,
    /// the last two including the post-#224 taper) minus ~3 points, so the
    /// "Overdraft?" badge fires when the scouted grade is a full band or more
    /// below the projection instead of never. The old 70/60/50/40 cut points
    /// came from the pre-overhaul class, which spanned only overall 60–69 —
    /// against generator-v2 band means (R2 76.6, R7 66.1) they sat 13–29 points
    /// below any reachable scouting error.
    private func projectionMinOverall(_ round: Int) -> Int {
        switch round {
        case 1:  return 76
        case 2:  return 72
        case 3:  return 69
        case 4:  return 67
        case 5:  return 66
        case 6:  return 64
        default: return 62
        }
    }

    // MARK: - Athletic Profile

    private var athleticProfileLabel: String {
        let percentiles = [
            prospect.fortyTime.map { CombineBenchmarks.percentile(value: $0, benchmark: CombineBenchmarks.benchmarks(for: prospect.position).fortyYard) },
            prospect.benchPress.map { CombineBenchmarks.percentile(value: Double($0), benchmark: CombineBenchmarks.benchmarks(for: prospect.position).benchPress) },
            prospect.verticalJump.map { CombineBenchmarks.percentile(value: $0, benchmark: CombineBenchmarks.benchmarks(for: prospect.position).verticalJump) },
            prospect.broadJump.map { CombineBenchmarks.percentile(value: Double($0), benchmark: CombineBenchmarks.benchmarks(for: prospect.position).broadJump) },
            prospect.shuttleTime.map { CombineBenchmarks.percentile(value: $0, benchmark: CombineBenchmarks.benchmarks(for: prospect.position).shuttle) },
            prospect.coneDrill.map { CombineBenchmarks.percentile(value: $0, benchmark: CombineBenchmarks.benchmarks(for: prospect.position).threeCone) }
        ].compactMap { $0 }

        guard !percentiles.isEmpty else { return "No Data" }
        let avg = percentiles.reduce(0, +) / percentiles.count

        // Buckets track the distribution `CombineBenchmarks` actually produces.
        // `percentile(value:benchmark:)` interpolates linearly between anchors
        // at the 95th / 50th / 15th percentile, and those two segments have
        // different slopes per σ, so a symmetric draw lands with a median of 46
        // rather than 50. Measured over 60 classes (≈21 000 invitees) these cut
        // points give Elite 3.2 % · Above Average 15.2 % · Average 52.1 % ·
        // Below Average 26.0 % · Poor 3.5 %; the old 80/65/45/25 read 40 % of
        // every class as a below-average athlete.
        switch avg {
        case 78...: return "Elite"
        case 62..<78: return "Above Average"
        case 38..<62: return "Average"
        case 22..<38: return "Below Average"
        default: return "Poor"
        }
    }

    private var athleticProfileColor: Color {
        switch athleticProfileLabel {
        case "Elite": return .accentGold
        case "Above Average": return .success
        case "Average": return .accentBlue
        case "Below Average": return .warning
        default: return .danger
        }
    }

    private func riskExplanation(_ risk: ProspectRiskLevel) -> String {
        switch risk {
        case .safePick:
            return "Consistent evaluations and stable personality. Lower variance in scout reports."
        case .highCeiling:
            return "High upside with some uncertainty. Could outperform projection significantly."
        case .boomOrBust:
            return "Extreme variance between evaluations. Could be a star or a bust."
        case .unknown:
            return "Not enough data to evaluate risk profile."
        }
    }

    // MARK: - Starter Comparison Section

    @ViewBuilder
    private var starterComparisonSection: some View {
        if isScouted {
            let starters = teamPlayers
                .filter { $0.position == prospect.position }
                .sorted { $0.overall > $1.overall }
            if let starter = starters.first {
                Section("vs Current Starter") {
                    HStack(spacing: 12) {
                        // Prospect side — show grade range
                        VStack(spacing: 2) {
                            Text(prospect.fullName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            if let gr = effectiveOverallGrade {
                                Text(gr.displayText)
                                    .font(.title3.weight(.heavy))
                                    .foregroundStyle(detailGradeColor(gr.midGrade))
                            } else {
                                Text("?")
                                    .font(.title3.weight(.heavy))
                                    .foregroundStyle(Color.textTertiary)
                            }
                            Text("Prospect")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)

                        // Qualitative comparison
                        let diff = (prospect.scoutedOverall ?? 0) - starter.overall
                        let compLabel = starterComparisonLabel(diff)
                        let compColor = starterComparisonColor(diff)
                        VStack(spacing: 2) {
                            Text("vs")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                            Text(compLabel)
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(compColor)
                                .multilineTextAlignment(.center)
                        }

                        // Starter side — letter grade to match prospect
                        VStack(spacing: 2) {
                            Text(starter.fullName)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textPrimary)
                            let starterGrade = LetterGrade.from(numericValue: starter.overall)
                            Text(starterGrade.rawValue)
                                .font(.title3.weight(.heavy))
                                .foregroundStyle(detailGradeColor(starterGrade))
                            Text("Starter")
                                .font(.caption2)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.backgroundSecondary)
            } else {
                Section("vs Current Starter") {
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.badge.plus")
                            .font(.caption)
                            .foregroundStyle(Color.success)
                        Text("No \(prospect.position.rawValue) on roster \u{2014} immediate starter")
                            .font(.subheadline)
                            .foregroundStyle(Color.success)
                    }
                }
                .listRowBackground(Color.backgroundSecondary)
            }
        }
    }

    private func starterComparisonLabel(_ diff: Int) -> String {
        if diff >= 0 { return "Upgrade" }
        if diff > -5 { return "Close" }
        if diff > -12 { return "Development\nProject" }
        return "Long-term\nProject"
    }

    private func starterComparisonColor(_ diff: Int) -> Color {
        if diff > -3 { return .success }
        if diff > -8 { return .accentGold }
        if diff > -15 { return .warning }
        return .textSecondary
    }

    // MARK: - Team Interest Row

    @ViewBuilder
    private var teamInterestRow: some View {
        if !prospect.teamInterest.isEmpty {
            Section {
                HStack(spacing: 8) {
                    InterestBadge(level: prospect.interestLevel)
                    Text("\(prospect.teamInterest.count) team\(prospect.teamInterest.count == 1 ? "" : "s") interested")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    // MARK: - Combine Section

    private var combineSection: some View {
        Section("Physical Measurables") {
            // Athletic profile summary
            if hasCombine {
                HStack {
                    Text("Athletic Profile")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    Text(athleticProfileLabel)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(athleticProfileColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(athleticProfileColor.opacity(0.15), in: Capsule())
                }
            }

            let bm = CombineBenchmarks.benchmarks(for: prospect.position)
            let pos = prospect.position.rawValue
            // Same fog the Combine table reads: a club that stayed home gets the
            // televised numbers, rounded, with no percentile or record chase off
            // them. Tapping a row must not be a way around the decision.
            let fidelity = ProspectFog.combineFidelity(for: prospect)
            let precise = fidelity == .full

            if !precise && hasCombine {
                HStack(spacing: 6) {
                    Image(systemName: "tv")
                        .font(.caption2)
                    Text("Broadcast numbers \u{2014} approximate. Send scouts to the Combine for exact times.")
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.textTertiary)
            }

            CombineMeasurableRow(label: "40-Yard Dash",
                                 value: ProspectFog.fortyText(prospect.fortyTime, fidelity: fidelity, unit: " sec"),
                                 percentile: precise ? prospect.fortyTime.map { CombineBenchmarks.percentile(value: $0, benchmark: bm.fortyYard) } : nil,
                                 posLabel: pos,
                                 recordNote: precise ? prospect.fortyTime.flatMap { nearRecordNote(value: $0, record: CombineBenchmarks.records.fortyYard.value, name: CombineBenchmarks.records.fortyYard.name, lowerIsBetter: true, format: "%.2f") } : nil)

            CombineMeasurableRow(label: "Bench Press",
                                 value: ProspectFog.benchText(prospect.benchPress, fidelity: fidelity, unit: " reps"),
                                 percentile: precise ? prospect.benchPress.map { CombineBenchmarks.percentile(value: Double($0), benchmark: bm.benchPress) } : nil,
                                 posLabel: pos,
                                 recordNote: precise ? prospect.benchPress.flatMap { nearRecordNote(value: Double($0), record: Double(CombineBenchmarks.records.benchPress.value), name: CombineBenchmarks.records.benchPress.name, lowerIsBetter: false, format: "%.0f") } : nil)

            CombineMeasurableRow(label: "Vertical Jump",
                                 value: ProspectFog.verticalText(prospect.verticalJump, fidelity: fidelity, unit: " in"),
                                 percentile: precise ? prospect.verticalJump.map { CombineBenchmarks.percentile(value: $0, benchmark: bm.verticalJump) } : nil,
                                 posLabel: pos,
                                 recordNote: precise ? prospect.verticalJump.flatMap { nearRecordNote(value: $0, record: CombineBenchmarks.records.verticalJump.value, name: CombineBenchmarks.records.verticalJump.name, lowerIsBetter: false, format: "%.1f") } : nil)

            CombineMeasurableRow(label: "Broad Jump",
                                 value: ProspectFog.broadJumpText(prospect.broadJump, fidelity: fidelity, unit: " in"),
                                 percentile: precise ? prospect.broadJump.map { CombineBenchmarks.percentile(value: Double($0), benchmark: bm.broadJump) } : nil,
                                 posLabel: pos,
                                 recordNote: precise ? prospect.broadJump.flatMap { nearRecordNote(value: Double($0), record: Double(CombineBenchmarks.records.broadJump.value), name: CombineBenchmarks.records.broadJump.name, lowerIsBetter: false, format: "%.0f") } : nil)

            CombineMeasurableRow(label: "Shuttle",
                                 value: ProspectFog.agilityText(prospect.shuttleTime, fidelity: fidelity, unit: " sec"),
                                 percentile: precise ? prospect.shuttleTime.map { CombineBenchmarks.percentile(value: $0, benchmark: bm.shuttle) } : nil,
                                 posLabel: pos,
                                 recordNote: precise ? prospect.shuttleTime.flatMap { nearRecordNote(value: $0, record: CombineBenchmarks.records.shuttle.value, name: CombineBenchmarks.records.shuttle.name, lowerIsBetter: true, format: "%.2f") } : nil)

            CombineMeasurableRow(label: "3-Cone Drill",
                                 value: ProspectFog.agilityText(prospect.coneDrill, fidelity: fidelity, unit: " sec"),
                                 percentile: precise ? prospect.coneDrill.map { CombineBenchmarks.percentile(value: $0, benchmark: bm.threeCone) } : nil,
                                 posLabel: pos,
                                 recordNote: precise ? prospect.coneDrill.flatMap { nearRecordNote(value: $0, record: CombineBenchmarks.records.threeCone.value, name: CombineBenchmarks.records.threeCone.name, lowerIsBetter: true, format: "%.2f") } : nil)

            // Position drill grade
            if let drillGrade = ProspectFog.drillGradeText(prospect.positionDrillGrade, fidelity: fidelity) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Combine Drill Grade")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("One-shot \(prospect.position.rawValue) drill at the combine — separate from per-skill scouting below.")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                    Spacer()
                    Text(drillGrade)
                        .font(.title3.weight(.black))
                        .foregroundStyle(PositionGradeCalculator.gradeColorForLetter(drillGrade))
                    Image(systemName: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            if !hasCombine {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.textTertiary)
                    Text("Combine results pending")
                        .font(.subheadline)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// Returns a "Near record!" note if the value is within 5% of the all-time record.
    private func nearRecordNote(value: Double, record: Double, name: String, lowerIsBetter: Bool, format: String) -> String? {
        let threshold = record * 0.05
        let isNear: Bool
        if lowerIsBetter {
            isNear = value <= record + threshold
        } else {
            isNear = value >= record - threshold
        }
        guard isNear else { return nil }
        return "Near record! (\(String(format: format, record)) by \(name))"
    }

    // MARK: - Scouting Report Section

    @ViewBuilder
    private var scoutingReportSection: some View {
        Section("Scouting Report") {
            // Overall grade
            if let gradeRange = effectiveOverallGrade {
                LabeledContent("Overall Grade") {
                    Text(gradeRange.displayText)
                        .font(.body.weight(.bold))
                        .foregroundStyle(detailGradeColor(gradeRange.midGrade))
                }
            }

            // Potential
            if let potentialLabel = prospect.scoutedPotentialLabel {
                LabeledContent("Potential") {
                    Text(potentialLabel.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(potentialLabelColor(potentialLabel))
                }
            } else if let potential = prospect.scoutedPotential {
                let potentialGrade = LetterGrade.from(numericValue: potential)
                LabeledContent("Potential") {
                    Text(potentialGrade.rawValue)
                        .font(.body.weight(.bold))
                        .foregroundStyle(detailGradeColor(potentialGrade))
                }
            }

            if let grade = prospect.scoutGrade {
                LabeledContent("Scout Grade") {
                    Text(grade)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                }
            }

            if let personality = prospect.scoutedPersonality {
                LabeledContent("Personality") {
                    Text(personality.displayName)
                        .foregroundStyle(Color.textPrimary)
                }
            }

            // Mental grades — with fallback from trueMental
            mentalGradesGrid

            // Position grades — with fallback from truePositionAttributes
            positionGradesGrid

            // Status indicators
            HStack(spacing: 16) {
                StatusPill(label: "Interview", completed: prospect.interviewCompleted)
                StatusPill(label: "Pro Day",   completed: prospect.proDayCompleted)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// Mental grades grid with fallback from legacy numeric values.
    private var mentalGradesGrid: some View {
        // LRN = how fast he absorbs a playbook (drives scheme install speed).
        // CMP = competitiveness, how he answers adversity (plan §2.1).
        let mentalKeys = ["AWR", "DEC", "WRK", "CLT", "COA", "LDR", "LRN", "CMP"]
        let scoutedGrades = prospect.scoutedMentalGrades
        let hasAny = scoutedGrades != nil && !(scoutedGrades?.isEmpty ?? true)

        return Group {
            if hasAny {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mental Attributes")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                        ForEach(mentalKeys, id: \.self) { key in
                            if let gr = scoutedGrades?[key] {
                                gradeCell(key: key, grade: gr)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Position grades grid with fallback from legacy numeric values.
    private var positionGradesGrid: some View {
        let scoutedGrades = prospect.scoutedPositionGrades
        let hasAny = scoutedGrades != nil && !(scoutedGrades?.isEmpty ?? true)

        return Group {
            if hasAny {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Position Skills")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(scoutedGrades?.count ?? 4, 6)), spacing: 8) {
                        ForEach(Array((scoutedGrades ?? [:]).keys.sorted()), id: \.self) { key in
                            if let gr = scoutedGrades?[key] {
                                gradeCell(key: key, grade: gr)
                            }
                        }
                    }
                }
            }
        }
    }

    private func gradeCell(key: String, grade: GradeRange) -> some View {
        VStack(spacing: 2) {
            Text(grade.displayText)
                .font(.caption.weight(.bold))
                .foregroundStyle(detailGradeColor(grade.midGrade))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(detailGradeColor(grade.midGrade).opacity(0.12))
                )
            Text(key)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Interview Results Section (Task 16: Full interview results in prospect detail)

    /// Who ran the meeting and when, e.g. "HC Mike Dawson · Combine · 2027".
    /// Silent on a legacy interview taken before attribution was recorded —
    /// inventing a name would be worse than leaving the line off.
    private var interviewAttributionLine: String? {
        let who = prospect.interviewedByName
        let when = prospect.interviewedOnLabel
        switch (who, when) {
        case let (who?, when?): return "\(who) \u{00B7} \(when)"
        case let (who?, nil):   return who
        case let (nil, when?):  return when
        default:                return nil
        }
    }

    @ViewBuilder
    private var interviewResultsSection: some View {
        Section {
            // Header with interview grade
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.accentBlue)
                        Text("Interview")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color.textPrimary)
                    }
                    if let attribution = interviewAttributionLine {
                        Text(attribution)
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let iq = prospect.interviewFootballIQ {
                    // Overall interview grade
                    let grade = interviewGradeLetter(iq: iq, personality: prospect.scoutedPersonality)
                    Text(grade)
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(interviewDetailGradeColor(grade))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(interviewDetailGradeColor(grade).opacity(0.15))
                        )
                }
            }

            // Bust-risk delta card (replicated from InterviewSelectionView).
            // Shows pre- vs post-interview bust risk to give the user a single
            // glanceable decision-support number alongside the interview grade.
            if let iq = prospect.interviewFootballIQ {
                let baseRisk = estimateBustRiskPct(hasInterview: false)
                let postRisk = estimateBustRiskPct(
                    hasInterview: true,
                    iq: iq,
                    personality: prospect.scoutedPersonality,
                    hasOffField: prospect.interviewCharacterNotes?
                        .contains(where: { $0.contains("\u{1F6A9}") }) ?? false
                )
                if baseRisk != postRisk {
                    BustRiskDeltaCard(
                        label: "Bust risk",
                        before: baseRisk,
                        after: postRisk,
                        unit: "%",
                        direction: .lowerIsBetter,
                        trailingContext: "after interview",
                        prominent: true
                    )
                }
            }

            // Personality badge with colored background (Task 1)
            if let personality = prospect.scoutedPersonality {
                HStack {
                    Text("Personality")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "person.fill")
                            .font(.caption2)
                        Text(personality.displayName)
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(personalityDetailBadgeColor(personality))
                    )
                }
            }

            // Football IQ with letter grade (Task 2)
            if let iq = prospect.interviewFootballIQ {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Football IQ")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Text(footballIQGradeLetter(iq))
                                .font(.body.weight(.heavy))
                                .foregroundStyle(footballIQDetailColor(iq))
                            Text("(\(iq))")
                                .font(.caption.weight(.medium).monospacedDigit())
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                    Text("Affects scheme learning speed")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)

                    // The mental block the room bought. An interview writes
                    // AWR / LRN / CMP / LDR / WRK bands onto the prospect
                    // (`ScoutingEngine.revealMentalGradesFromInterview`), and
                    // before this row existed the only visible trace of sixty
                    // spent slots was the single number above.
                    interviewRevealedGradeRow

                    // Football IQ impact (Task 11)
                    if iq >= 85 {
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.success)
                            Text("High IQ = faster scheme learning, better decisions, fewer penalties")
                                .font(.caption2)
                                .foregroundStyle(Color.success)
                        }
                    } else if iq < 55 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Color.danger)
                            Text("Low IQ = slower scheme learning, more mental errors")
                                .font(.caption2)
                                .foregroundStyle(Color.danger)
                        }
                    }
                }
            }

            // Off-field / exemplary character indicators (Task 3: larger, more visible)
            if let notes = prospect.interviewCharacterNotes {
                let hasOffField = notes.contains(where: { $0.contains("\u{1F6A9}") })
                let hasExemplary = notes.contains(where: { $0.contains("\u{2705}") })

                if hasOffField {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.body)
                            .foregroundStyle(Color.danger)
                        Text("OFF-FIELD CONCERNS REPORTED")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Color.danger)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.danger.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.danger.opacity(0.3))
                            )
                    )
                }

                if hasExemplary {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.body)
                            .foregroundStyle(Color.success)
                        Text("EXEMPLARY CHARACTER")
                            .font(.subheadline.weight(.heavy))
                            .foregroundStyle(Color.success)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.success.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.success.opacity(0.3))
                            )
                    )
                }
            }

            // Red/green flags summary (Task 12)
            if let iq = prospect.interviewFootballIQ {
                let personality = prospect.scoutedPersonality
                let hasOffField = prospect.interviewCharacterNotes?.contains(where: { $0.contains("\u{1F6A9}") }) ?? false

                VStack(alignment: .leading, spacing: 4) {
                    // Green flags
                    if iq >= 75 {
                        interviewFlagRow(color: .success, text: "High Football IQ")
                    }
                    if let p = personality, p.tier == .positive {
                        interviewFlagRow(color: .success, text: p.displayName)
                    }
                    if !hasOffField {
                        interviewFlagRow(color: .success, text: "Clean record")
                    }

                    // Red flags
                    if hasOffField {
                        interviewFlagRow(color: .danger, text: "Off-field concerns")
                    }
                    if iq < 55 {
                        interviewFlagRow(color: .danger, text: "Low Football IQ")
                    }
                    if let p = personality, p.tier == .risky {
                        interviewFlagRow(color: .danger, text: p.displayName)
                    }
                }
            }

            // Character notes (excluding off-field/exemplary which are shown above)
            if let notes = prospect.interviewCharacterNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Character Notes")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    ForEach(notes.filter({ !$0.contains("\u{1F6A9}") && !$0.contains("\u{2705}") }), id: \.self) { note in
                        HStack(spacing: 6) {
                            Image(systemName: "quote.bubble.fill")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    /// The five mental attributes an interview is entitled to read, rendered as
    /// one compact band row. Keys and order match
    /// `ScoutingEngine.interviewRevealedMentalKeys`.
    @ViewBuilder
    private var interviewRevealedGradeRow: some View {
        let labels: [String: String] = [
            "AWR": "Awareness",
            "LRN": "Learning",
            "CMP": "Compete",
            "LDR": "Leadership",
            "WRK": "Work Ethic"
        ]
        let available = ScoutingEngine.interviewRevealedMentalKeys.compactMap { key -> (String, GradeRange)? in
            guard let grade = prospect.scoutedMentalGrades?[key] else { return nil }
            return (key, grade)
        }
        if !available.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("From the room")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
                    .textCase(.uppercase)
                HStack(spacing: 10) {
                    ForEach(available, id: \.0) { key, grade in
                        VStack(spacing: 2) {
                            Text(grade.displayText)
                                .font(.system(size: grade.isSingleGrade ? 15 : 12, weight: .heavy))
                                .foregroundStyle(detailGradeColor(grade.midGrade))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(labels[key] ?? key)
                                .font(.system(size: DSType.Size.micro, weight: .medium))
                                .foregroundStyle(Color.textTertiary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(detailGradeColor(grade.midGrade).opacity(0.10))
                        )
                    }
                }
                Text("A wider band means the interviewer was not sure. Compete drives how he answers a bad season; Learning drives how fast he picks up the playbook.")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
    }

    private func interviewFlagRow(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    private func interviewGradeLetter(iq: Int, personality: PersonalityArchetype?) -> String {
        var score = iq
        if let p = personality {
            score += p.interviewScoreContribution
        }
        if let notes = prospect.interviewCharacterNotes {
            if notes.contains(where: { $0.contains("\u{1F6A9}") }) { score -= 15 }
            if notes.contains(where: { $0.contains("\u{2705}") }) { score += 10 }
        }
        score = max(0, min(99, score))
        if score >= 85 { return "A" }
        if score >= 75 { return "B" }
        if score >= 65 { return "C" }
        if score >= 55 { return "D" }
        return "F"
    }

    private func interviewDetailGradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .accentGold
        case "B": return .success
        case "C": return .warning
        case "D": return .danger
        default:  return .danger
        }
    }

    private func personalityDetailBadgeColor(_ p: PersonalityArchetype) -> Color {
        switch p.tier {
        case .positive: return .success
        case .risky:    return .danger
        case .neutral:  return .warning.opacity(0.8)
        }
    }

    private func footballIQGradeLetter(_ iq: Int) -> String {
        if iq >= 85 { return "A" }
        if iq >= 75 { return "B" }
        if iq >= 65 { return "C" }
        if iq >= 55 { return "D" }
        return "F"
    }

    /// Unified onto `Color.forRating` — Football IQ is a 0–99 attribute like
    /// any other. (The old ladder's last two branches both returned `.danger`,
    /// so the 55 edge was dead code.)
    private func footballIQDetailColor(_ iq: Int) -> Color {
        Color.forRating(iq)
    }

    /// Estimate bust risk percentage. Mirrors the formula in
    /// `InterviewSelectionView.estimateBustRisk` so both views display
    /// consistent numbers for the same prospect.
    private func estimateBustRiskPct(
        hasInterview: Bool,
        iq: Int = 65,
        personality: PersonalityArchetype? = nil,
        hasOffField: Bool = false
    ) -> Int {
        var risk = 35

        if prospect.position == .QB { risk += 10 }
        else if prospect.position == .WR || prospect.position == .CB { risk += 5 }

        if prospect.age <= 20 { risk += 5 }

        if hasInterview {
            if iq >= 85 { risk -= 15 }
            else if iq >= 75 { risk -= 10 }
            else if iq >= 65 { risk -= 5 }
            else if iq < 50 { risk += 10 }

            if let p = personality {
                if p.tier == .positive { risk -= 5 }
                else if p.tier == .risky { risk += 5 }
            }

            if hasOffField { risk += 10 }
        }

        return max(5, min(80, risk))
    }

    // MARK: - College Production Section (Position Skills)

    /// Position-skill letter grades from scouting visits (per-attribute eyes-on
    /// evaluation). Distinct from "Position Drills" in the combine section, which
    /// is a one-shot combine snapshot.
    @ViewBuilder
    private var positionSkillsSection: some View {
        if isScouted {
            Section {
                collegeFlavorStats
            } header: {
                HStack(spacing: 4) {
                    Text("Position Skills")
                    Text("· per-attribute scouting grade")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .textCase(nil)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    /// Snapshot of college playing time + production. Generator v2 stores this
    /// as a noisy signal (`collegeProductionScore`) that correlates with — but
    /// does not reveal — the prospect's true grade.
    @ViewBuilder
    private var collegeProductionSummarySection: some View {
        Section("College Production") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    productionTile(label: "Years Started", value: "\(prospect.collegeYearsStarted)/4")
                    productionTile(
                        label: "Production",
                        value: prospect.collegeProductionTier.displayName,
                        color: prospect.collegeProductionTier.chipColor
                    )
                    if let level = prospect.collegeCompetitionLevel {
                        productionTile(label: String(localized: "Competition"), value: level.longName)
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text(prospect.collegeStatLine)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                }
                Text("Heavy starter snaps + strong production already factor into the prospect's grade and ceiling.")
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func productionTile(label: String, value: String, color: Color = .textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var collegeFlavorStats: some View {
        let posGrades = prospect.scoutedPositionGrades
        let fb = positionFallbackValues
        switch prospect.truePositionAttributes {
        case .quarterback:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Arm", key: "ARM", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Acc (S)", key: "SAc", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Acc (D)", key: "DAc", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Pocket", key: "PKT", grades: posGrades, fallback: fb)
            }
        case .wideReceiver:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Route", key: "RTE", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Catch", key: "CTH", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Release", key: "RLS", grades: posGrades, fallback: fb)
            }
        case .runningBack:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Vision", key: "VIS", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Elusiv", key: "ELU", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Recv", key: "RCV", grades: posGrades, fallback: fb)
            }
        case .defensiveBack:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Man", key: "MCV", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Zone", key: "ZCV", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Press", key: "PRS", grades: posGrades, fallback: fb)
            }
        case .linebacker:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Tackle", key: "TAK", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Zone", key: "ZCV", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Blitz", key: "BLZ", grades: posGrades, fallback: fb)
            }
        case .defensiveLine:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Pass Rush", key: "PRU", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Shed", key: "BSH", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Power", key: "PWR", grades: posGrades, fallback: fb)
            }
        case .offensiveLine:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Run Blk", key: "RBK", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Pass Blk", key: "PBK", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Anchor", key: "ANC", grades: posGrades, fallback: fb)
            }
        case .tightEnd:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Block", key: "BLK", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Catch", key: "CTH", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Route", key: "RTE", grades: posGrades, fallback: fb)
            }
        case .kicking:
            HStack(spacing: 14) {
                flavorGradeStat(label: "Power", key: "PWR", grades: posGrades, fallback: fb)
                flavorGradeStat(label: "Accuracy", key: "ACC", grades: posGrades, fallback: fb)
            }
        }
    }

    /// Builds a fallback dictionary mapping position skill keys to numeric values from truePositionAttributes.
    private var positionFallbackValues: [String: Int] {
        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            return ["ARM": qb.armStrength, "SAc": qb.accuracyShort, "DAc": qb.accuracyDeep,
                    "PKT": qb.pocketPresence, "MAc": qb.accuracyMid, "SCR": qb.scrambling]
        case .wideReceiver(let wr):
            return ["RTE": wr.routeRunning, "CTH": wr.catching, "RLS": wr.release]
        case .runningBack(let rb):
            return ["VIS": rb.vision, "ELU": rb.elusiveness, "RCV": rb.receiving, "BTK": rb.breakTackle]
        case .defensiveBack(let db):
            return ["MCV": db.manCoverage, "ZCV": db.zoneCoverage, "PRS": db.press, "BLS": db.ballSkills]
        case .linebacker(let lb):
            return ["TAK": lb.tackling, "ZCV": lb.zoneCoverage, "BLZ": lb.blitzing]
        case .defensiveLine(let dl):
            return ["PRU": dl.passRush, "BSH": dl.blockShedding, "PWR": dl.powerMoves, "FIN": dl.finesseMoves]
        case .offensiveLine(let ol):
            return ["RBK": ol.runBlock, "PBK": ol.passBlock, "ANC": ol.anchor, "PUL": ol.pull]
        case .tightEnd(let te):
            return ["BLK": te.blocking, "CTH": te.catching, "RTE": te.routeRunning, "SPD": te.speed]
        case .kicking(let k):
            return ["PWR": k.kickPower, "ACC": k.kickAccuracy]
        }
    }

    private func flavorGradeStat(label: String, key: String, grades: [String: GradeRange]?, fallback: [String: Int]) -> some View {
        VStack(spacing: 2) {
            if let gr = grades?[key] {
                Text(gr.displayText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(detailGradeColor(gr.midGrade))
            } else if let numVal = fallback[key] {
                let lg = LetterGrade.from(numericValue: numVal)
                Text(lg.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(detailGradeColor(lg))
            } else {
                Text("?")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Scheme Fit

    private func evaluateSchemeFit() -> String? {
        let oc = coaches.first(where: { $0.role == .offensiveCoordinator })
        let dc = coaches.first(where: { $0.role == .defensiveCoordinator })

        if prospect.position.side == .offense, let scheme = oc?.offensiveScheme {
            return offensiveSchemeFit(scheme: scheme)
        } else if prospect.position.side == .defense, let scheme = dc?.defensiveScheme {
            return defensiveSchemeFit(scheme: scheme)
        }
        return nil
    }

    private func offensiveSchemeFit(scheme: OffensiveScheme) -> String {
        var score = 0
        let physical = prospect.truePhysical

        switch prospect.truePositionAttributes {
        case .quarterback(let qb):
            switch scheme {
            case .airRaid, .spread:
                score = (qb.accuracyShort + qb.accuracyDeep + qb.armStrength) / 3
            case .westCoast, .proPassing:
                score = (qb.accuracyShort + qb.accuracyMid + qb.pocketPresence) / 3
            case .powerRun, .shanahan:
                score = (qb.pocketPresence + qb.scrambling + physical.strength) / 3
            case .rpo, .option:
                score = (qb.scrambling + physical.speed + qb.accuracyShort) / 3
            }
        case .wideReceiver(let wr):
            switch scheme {
            case .airRaid, .spread:
                score = (wr.routeRunning + wr.catching + physical.speed) / 3
            case .westCoast, .proPassing:
                score = (wr.routeRunning + wr.catching + wr.release) / 3
            case .powerRun, .shanahan:
                score = (physical.strength + wr.release + physical.speed) / 3
            default:
                score = (wr.routeRunning + wr.catching) / 2
            }
        case .runningBack(let rb):
            switch scheme {
            case .powerRun:
                score = (rb.breakTackle + rb.vision + physical.strength) / 3
            case .shanahan:
                score = (rb.vision + rb.elusiveness + physical.speed) / 3
            case .westCoast, .spread:
                score = (rb.receiving + rb.elusiveness + rb.vision) / 3
            default:
                score = (rb.vision + rb.elusiveness) / 2
            }
        case .offensiveLine(let ol):
            switch scheme {
            case .powerRun:
                score = (ol.runBlock + ol.anchor + physical.strength) / 3
            case .airRaid, .proPassing, .westCoast:
                score = (ol.passBlock + ol.anchor + physical.strength) / 3
            case .shanahan:
                score = (ol.pull + ol.runBlock + physical.agility) / 3
            default:
                score = (ol.runBlock + ol.passBlock) / 2
            }
        case .tightEnd(let te):
            switch scheme {
            case .airRaid, .spread, .westCoast:
                score = (te.catching + te.routeRunning + te.speed) / 3
            case .powerRun, .shanahan:
                score = (te.blocking + te.speed + physical.strength) / 3
            default:
                score = (te.catching + te.blocking) / 2
            }
        default:
            score = 65
        }
        return schemeFitLabel(score)
    }

    private func defensiveSchemeFit(scheme: DefensiveScheme) -> String {
        var score = 0
        let physical = prospect.truePhysical

        switch prospect.truePositionAttributes {
        case .defensiveBack(let db):
            switch scheme {
            case .pressMan:
                score = (db.manCoverage + db.press + physical.speed) / 3
            case .cover3, .tampa2:
                score = (db.zoneCoverage + db.ballSkills + physical.speed) / 3
            case .multiple, .hybrid:
                score = (db.manCoverage + db.zoneCoverage + db.press) / 3
            default:
                score = (db.manCoverage + db.zoneCoverage) / 2
            }
        case .linebacker(let lb):
            switch scheme {
            case .base34:
                score = (lb.tackling + lb.blitzing + physical.strength) / 3
            case .base43:
                score = (lb.tackling + lb.zoneCoverage + physical.speed) / 3
            case .tampa2:
                score = (lb.zoneCoverage + physical.speed + lb.tackling) / 3
            case .cover3:
                score = (lb.zoneCoverage + lb.tackling + physical.speed) / 3
            default:
                score = (lb.tackling + lb.zoneCoverage) / 2
            }
        case .defensiveLine(let dl):
            switch scheme {
            case .base43:
                score = (dl.passRush + dl.powerMoves + physical.strength) / 3
            case .base34:
                score = (dl.blockShedding + dl.powerMoves + physical.strength) / 3
            case .multiple, .hybrid:
                score = (dl.passRush + dl.finesseMoves + physical.agility) / 3
            default:
                score = (dl.passRush + dl.blockShedding) / 2
            }
        default:
            score = 65
        }
        return schemeFitLabel(score)
    }

    private func schemeFitLabel(_ score: Int) -> String {
        switch score {
        case 75...:  return "Good"
        case 55..<75: return "Fair"
        default:      return "Poor"
        }
    }

    private func schemeFitColor(_ fit: String) -> Color {
        switch fit {
        case "Good": return .success
        case "Fair": return .warning
        default:     return .danger
        }
    }

    private func schemeFitIcon(_ fit: String) -> String {
        switch fit {
        case "Good": return "checkmark.circle.fill"
        case "Fair": return "minus.circle.fill"
        default:     return "xmark.circle.fill"
        }
    }

    private func schemeFitExplanation(_ fit: String) -> String {
        switch fit {
        case "Good": return "Attributes align well with your coordinator's scheme."
        case "Fair": return "Decent fit but may need development in the scheme."
        default:     return "Skill set doesn't match scheme requirements well."
        }
    }

    // MARK: - Risk Flags Section

    /// Concerns your own work produced, as distinct from the medical/character
    /// FILE above it — that one is the league's paperwork, opened in three steps
    /// by `ProspectFog.flagDisclosure`; this one is what your interviewer and
    /// your scouts came back saying. Two sections both titled like red flags read
    /// as a duplicate, so the header names the source.
    @ViewBuilder
    private var riskFlagsSection: some View {
        let flags = collectRiskFlags()
        if !flags.isEmpty {
            Section("Scouting Concerns") {
                ForEach(flags, id: \.self) { flag in
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Color.danger)
                        Text(flag)
                            .font(.subheadline)
                            .foregroundStyle(Color.textPrimary)
                    }
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    private func collectRiskFlags() -> [String] {
        var flags: [String] = []

        if let iq = prospect.interviewFootballIQ, iq < 50 {
            flags.append("Low Football IQ (\(iq)) -- may struggle with complex playbook")
        }

        let concernWords = ["concern", "issue", "trouble", "red flag", "questionable",
                           "immature", "selfish", "lazy", "undisciplined", "attitude"]
        if let notes = prospect.interviewCharacterNotes {
            for note in notes {
                let lower = note.lowercased()
                if concernWords.contains(where: { lower.contains($0) }) {
                    flags.append("Character concern: \(note)")
                }
            }
        }

        // The last two read HIDDEN attributes (`truePhysical.durability`,
        // `trueMental.workEthic`) and were gated on nothing but "one report
        // exists" — a single cheap tape grade handed over a durability verdict
        // the medical file two sections up would not have disclosed. They are
        // the same class of information as the file, so they open on the same
        // authority: `ProspectFog.flagDisclosure` at `.full`, i.e. two reports,
        // a meeting, or a Top-30 visit.
        let disclosure = ProspectFog.flagDisclosure(for: prospect, userTeamID: career.teamID)
        if disclosure == .full {
            if prospect.truePhysical.durability < 50 {
                flags.append("Durability concern \u{2014} injury-prone profile")
            }
            if prospect.trueMental.workEthic < 45 {
                flags.append("Poor work ethic \u{2014} development may stall")
            }
        }

        return flags
    }

    // MARK: - Draft Section

    private var draftSection: some View {
        Section("Draft Information") {
            LabeledContent("Declaring for Draft") {
                Text(prospect.isDeclaringForDraft ? "Yes" : "No")
                    .foregroundStyle(prospect.isDeclaringForDraft ? Color.success : Color.textSecondary)
            }

            if let proj = prospect.draftProjection {
                LabeledContent("Draft Projection") {
                    Text("Round \(proj)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(projectionColor(proj))
                        .monospacedDigit()
                }
            } else {
                LabeledContent("Draft Projection") {
                    Text("Unknown")
                        .foregroundStyle(Color.textTertiary)
                }
            }

            // Rookie contract estimate
            if let proj = prospect.draftProjection {
                LabeledContent("Est. Rookie Deal") {
                    Text(rookieContractEstimate(round: proj))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.textSecondary)
                        .monospacedDigit()
                }
            }

            // Mock draft projection
            if let mockPick = prospect.mockDraftPickNumber,
               let mockTeam = prospect.mockDraftTeam {
                LabeledContent("Mock Draft") {
                    Text("Rd1 Pick #\(mockPick) — \(mockTeam)")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentGold)
                        .monospacedDigit()
                }
            }

            // Team interest indicator
            LabeledContent("Team Interest") {
                InterestBadge(level: prospect.interestLevel)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Actions Section

    /// The priced, rationed replacement for the old free "Send Scout to
    /// Evaluate" row. Always rendered, never silently missing: a blocked
    /// evaluation states its price, its slot count or its reason.
    @ViewBuilder
    private var evaluationRow: some View {
        let availability = evaluationAvailability
        let title = isScouted
            ? "Send Another Scout (\(currentScoutingPhase.displayName))"
            : "Send Scout to Evaluate"

        Button {
            activeSheet = .sendScout
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(availability.isAvailable ? Color.accentGold : Color.textTertiary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(availability.isAvailable ? Color.accentGold : Color.textSecondary)
                    Text(evaluationDetail(availability))
                        .font(.caption)
                        .foregroundStyle(evaluationDetailTint(availability))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Text("\(prospect.scoutingReports.count)/\(ScoutEvaluationBudget.maxReportsPerProspect)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .disabled(!availability.isAvailable)
        .accessibilityLabel("\(title). \(evaluationDetail(availability))")
    }

    private func evaluationDetail(_ availability: ScoutEvaluationAvailability) -> String {
        switch availability {
        case let .available(cost, slotsLeft):
            return "$\(cost)K \u{00B7} \(slotsLeft) of \(ScoutEvaluationBudget.slotsPerCycle) evaluations left this cycle"
        case let .windowShut(hint):
            return "Scouting window closed. \(hint)"
        case .noScouts:
            return "No scouts on staff \u{2014} hire one from the Scout Team tab."
        case .slotsSpent:
            return "All \(ScoutEvaluationBudget.slotsPerCycle) evaluations are spent. The combine trip and pro-day visits still add reports."
        case .reportsMaxed:
            return "Three reports filed \u{2014} your department has seen everything it is going to see."
        case let .cannotAfford(cost, remaining):
            return "Needs $\(cost)K \u{2014} only $\(remaining)K left in the scouting budget."
        }
    }

    private func evaluationDetailTint(_ availability: ScoutEvaluationAvailability) -> Color {
        switch availability {
        case .available:    return .textTertiary
        case .reportsMaxed: return .success
        case .cannotAfford, .slotsSpent, .noScouts: return .warning
        case .windowShut:   return .textTertiary
        }
    }

    private func completedActionRow(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.success)
                .font(.caption)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.success)
        }
    }

    private func blockedActionRow(icon: String, title: String, reason: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Color.textSecondary)
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), unavailable. \(reason)")
    }

    private var actionsSection: some View {
        Section {
            evaluationRow

            // Interview — combine and pro days, 60 a cycle.
            if prospect.interviewCompleted {
                completedActionRow("Interview completed")
            } else if canInterview {
                Button {
                    performInterview()
                } label: {
                    HStack {
                        Label("Conduct Interview", systemImage: "person.crop.circle.badge.questionmark")
                            .foregroundStyle(Color.accentBlue)
                        Spacer()
                        Text("Interviews: \(career.interviewsUsed)/\(Self.maxInterviews) used")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else {
                blockedActionRow(
                    icon: "person.crop.circle.badge.questionmark",
                    title: "Conduct Interview",
                    reason: isLiveDraftCard
                        ? Self.liveDraftHint
                        : isInterviewWindow
                            ? "All \(Self.maxInterviews) interview slots are spent for this cycle."
                            : "Interviews run at the combine and through pro days."
                )
            }

            // Private workout / pro day — 30 a cycle.
            if prospect.proDayCompleted {
                completedActionRow("Workout/Pro Day completed")
            } else if canWorkout {
                Button {
                    performWorkout()
                } label: {
                    HStack {
                        Label("Invite for Workout", systemImage: "figure.run")
                            .foregroundStyle(Color.accentBlue)
                        Spacer()
                        Text("Workouts: \(career.workoutsUsed)/\(Self.maxWorkouts) used")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            } else {
                blockedActionRow(
                    icon: "figure.run",
                    title: "Invite for Workout",
                    reason: isLiveDraftCard
                        ? Self.liveDraftHint
                        : isWorkoutWindow
                            ? "All \(Self.maxWorkouts) workout slots are spent for this cycle."
                            : "Available at the workout stage \u{2014} you are at \(career.prepStep.displayName)."
                )
            }

            if isScouted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.success)
                    Text("Scouted (\(prospect.scoutingReports.count) report\(prospect.scoutingReports.count == 1 ? "" : "s"))")
                        .foregroundStyle(Color.success)
                    // R27: attribution + accuracy indicator for the latest report
                    if let scoutedBy = prospect.latestScoutName {
                        Text("\u{00B7} latest by \(scoutedBy)\(prospect.latestReportConfidence.map { " (\(Int($0 * 100))% confidence)" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    // MARK: - Action Button Bar (#48)

    private var actionButtonBar: some View {
        HStack(spacing: 12) {
            // The ONE mark — primary CTA. This used to toggle `prospectFlag`
            // between must-have and none, which the star store, the watchlist
            // bookmark and the user grade all disagreed with.
            Menu {
                ProspectMarkMenu(
                    prospect: prospect,
                    onChange: { try? modelContext.save() },
                    onEditNote: { activeSheet = .markNote }
                )
            } label: {
                let mark = prospect.userMark
                Label(
                    mark == .none ? "Mark Prospect" : mark.label,
                    systemImage: mark == .none ? "circle.dashed" : mark.icon
                )
                .font(.body.weight(.bold))
                .foregroundStyle(mark == .none ? Color.textPrimary : mark.color)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(mark == .none ? Color.backgroundSecondary : mark.color.opacity(0.22))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            mark == .none ? Color.surfaceBorder : mark.color,
                            lineWidth: mark == .none ? 1 : 1.5
                        )
                )
            }
            .accessibilityLabel(
                prospect.isMarked
                    ? "Your mark: \(prospect.userMark.label). Change it"
                    : "Unmarked. Set your mark"
            )

            // Interview button — only during combine phase.
            if canInterview {
                Button {
                    performInterview()
                } label: {
                    Label("Interview", systemImage: "bubble.left.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(Color.accentBlue)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.accentBlue.opacity(0.18))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.accentBlue.opacity(0.5), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Helpers

    private var positionColor: Color {
        switch prospect.position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private var heightLabel: String {
        let feet = prospect.height / 12
        let inches = prospect.height % 12
        return "\(feet)'\(inches)\""
    }

    private func projectionColor(_ round: Int) -> Color {
        switch round {
        case 1:    return .accentGold
        case 2...3: return .success
        case 4...5: return .warning
        default:   return .textSecondary
        }
    }

    private func detailGradeColor(_ grade: LetterGrade) -> Color {
        // Aligned with the unified 5-tier palette so colors match across the app:
        // A+ → bright green, A/A- → green, B → blue, C → yellow, D/F → red.
        PositionGradeCalculator.gradeColorForLetter(grade.rawValue)
    }

    private func potentialLabelColor(_ label: PotentialLabel) -> Color {
        switch label {
        case .eliteCeiling:  return .accentGold
        case .highUpside:    return .success
        case .solidStarter:  return .accentBlue
        case .average:       return .warning
        case .limitedUpside: return .danger
        case .unknown:       return .textTertiary
        }
    }

    /// Rookie money for a projected round, **from `DraftEngine.rookieContract`**
    /// at the club's real cap (task #87 / F17).
    ///
    /// This was a hardcoded round→band table that never called the engine, so
    /// the number a user read on a prospect and the number the draft actually
    /// wrote him were unrelated — and the table never moved with the cap.
    private func rookieContractEstimate(round: Int) -> String {
        let cap = userTeam?.salaryCap ?? ContractEngine.openingSalaryCap
        let band = DraftEngine.rookieContractBand(round: round, salaryCap: cap)
        func money(_ k: Int) -> String {
            k >= 1_000 ? String(format: "$%.0fM", Double(k) / 1_000.0)
                       : String(format: "$%dK", k)
        }
        if band.low == band.high { return "~\(money(band.low)) / \(band.years)yr" }
        return "~\(money(band.low))-\(money(band.high)) / \(band.years)yr"
    }

    /// Maps the career's current season phase to a scouting phase for report generation.
    private var currentScoutingPhase: ScoutingPhase {
        switch career.currentPhase {
        case .combine:
            return .combine
        case .freeAgency, .proDays, .draft:
            return .proDay
        case .otas, .trainingCamp, .preseason, .rosterCuts:
            return .personalWorkout
        default:
            // Pre-combine phases: college season or senior bowl
            return .collegeSeason
        }
    }

    private func loadScouts() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<Scout>(predicate: #Predicate { $0.teamID == teamID })
        scouts = (try? modelContext.fetch(desc)) ?? []
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        scoutingBudget = (try? modelContext.fetch(teamDesc))?.first?.owner?.scoutingBudget ?? 4_000
    }

    /// Books one evaluation against the cycle's slots and the scouting pot.
    private func recordEvaluation(cost: Int) {
        let used = evaluationsUsed
        let spend = evaluationSpend
        evaluationCycleStored = career.currentSeason
        evaluationsUsedStored = used + 1
        evaluationSpendStored = spend + cost
        // The report itself is written onto the in-memory draft class; flush it
        // or the money is spent and the intel is forgotten on relaunch.
        WeekAdvancer.persistDraftClass(WeekAdvancer.currentDraftClass, to: modelContext)
        try? modelContext.save()
    }

    private func loadCoaches() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        coaches = (try? modelContext.fetch(desc)) ?? []
    }

    private func loadTeamPlayers() {
        guard let teamID = career.teamID else { return }
        let desc = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        teamPlayers = (try? modelContext.fetch(desc)) ?? []
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        userTeam = try? modelContext.fetch(teamDesc).first
    }

    private func loadPositionRank() {
        let cid = career.id
        let desc = FetchDescriptor<CollegeProspect>(predicate: #Predicate { $0.careerID == cid })
        guard let all = try? modelContext.fetch(desc) else { return }
        // Ranked by the FOGGED band, not by `scoutedOverall`: the badge sits
        // two inches under a grade the user reads as "B+", and a position rank
        // computed off the raw number would order the class by information the
        // screen is deliberately not showing him. Ties break on the stored
        // number, which is never printed.
        let ranked = all
            .filter { $0.position == prospect.position && $0.scoutedOverall != nil }
            .sorted {
                let a = ProspectFog.rank($0)
                let b = ProspectFog.rank($1)
                if a != b { return a > b }
                return ($0.scoutedOverall ?? 0) > ($1.scoutedOverall ?? 0)
            }
        if let idx = ranked.firstIndex(where: { $0.id == prospect.id }) {
            positionRank = idx + 1
        }
    }

    private func performInterview() {
        // Use best scout's personalityRead or HC's motivation as interviewer quality
        let interviewerQuality: Int
        let interviewerName: String
        if let bestScout = scouts.max(by: { $0.personalityRead < $1.personalityRead }) {
            interviewerQuality = bestScout.personalityRead
            interviewerName = "Scout \(bestScout.fullName)"
        } else if let hc = coaches.first(where: { $0.role == .headCoach }) {
            interviewerQuality = hc.motivation
            interviewerName = "HC \(hc.fullName)"
        } else {
            interviewerQuality = 50
            interviewerName = "Scouting Staff"
        }

        let result = ScoutingEngine.conductInterview(
            prospect: prospect,
            interviewerQuality: interviewerQuality,
            interviewerName: interviewerName,
            occasionLabel: interviewOccasionLabel
        )
        interviewResult = result
        career.interviewsUsed += 1
        // The interview writes revealed mental grade bands onto the prospect,
        // which lives in the in-memory draft class — flush it or the meeting is
        // forgotten on relaunch.
        WeekAdvancer.persistDraftClass(WeekAdvancer.currentDraftClass, to: modelContext)
        try? modelContext.save()
    }

    /// "Combine · 2027" — what the interview section prints under the header.
    private var interviewOccasionLabel: String {
        let phase: String
        switch career.currentPhase {
        case .combine:  phase = "Combine"
        case .proDays:  phase = "Pro Days"
        case .draft:    phase = "Draft Week"
        default:        phase = "Pre-Draft"
        }
        return "\(phase) \u{00B7} " + String(career.currentSeason)
    }

    /// Same chokepoint and same modal as `WorkoutsTabView` — a workout ordered
    /// from the card and a workout ordered from the workouts tab are one action
    /// with one economy (`career.workoutsUsed` / 30) and one engine.
    private func performWorkout() {
        guard canWorkout else { return }

        var result: ScoutingEngine.WorkoutResult?
        let applied = DraftClassMutator.mutate(modelContext) { klass in
            guard let idx = klass.firstIndex(where: { $0.id == prospect.id }) else { return }
            result = ScoutingEngine.conductPersonalWorkout(prospect: klass[idx], coaches: coaches)
        }
        guard applied, let result else { return }

        career.workoutsUsed += 1
        try? modelContext.save()
        activeSheet = .workoutResult(result)
    }
}

// MARK: - Supporting Views

private struct ProspectInfoPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

private struct MeasurableRow: View {
    let label: String
    let value: String?

    var body: some View {
        LabeledContent(label) {
            Text(value ?? "—")
                .font(.body.monospacedDigit())
                .foregroundStyle(value != nil ? Color.textPrimary : Color.textTertiary)
        }
    }
}

private struct CombineMeasurableRow: View {
    let label: String
    let value: String?
    let percentile: Int?
    let posLabel: String
    var recordNote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.body)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if let value {
                    HStack(spacing: 8) {
                        Text(value)
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Color.textPrimary)

                        if let pct = percentile {
                            Text("\(ordinal(pct)) %ile for \(posLabel)")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(percentileColor(pct))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(percentileColor(pct).opacity(0.15), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))
                        }
                    }
                } else {
                    Text("—")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(Color.textTertiary)
                }
            }

            if let note = recordNote {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.accentGold)
                    Text(note)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentGold)
                }
            }
        }
    }

    private func ordinal(_ n: Int) -> String {
        let suffix: String
        let ones = n % 10
        let tens = (n / 10) % 10
        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }

    private func percentileColor(_ pct: Int) -> Color {
        if pct >= 90 { return .accentGold }
        if pct >= 75 { return .success }
        if pct >= 50 { return .accentBlue }
        if pct >= 25 { return .warning }
        return .danger
    }
}

private struct StatusPill: View {
    let label: String
    let completed: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(completed ? Color.success : Color.textTertiary)
                .font(.subheadline)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(completed ? Color.textPrimary : Color.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(completed ? Color.success.opacity(0.15) : Color.backgroundTertiary)
        )
        .accessibilityLabel("\(label) \(completed ? "completed" : "not completed")")
    }
}

private struct InterestBadge: View {
    let level: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .foregroundStyle(badgeColor)
                .font(.caption)
            Text(level)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badgeColor)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(badgeColor.opacity(0.15))
        )
    }

    private var iconName: String {
        switch level {
        case "Hot":     return "flame.fill"
        case "Warm":    return "thermometer.medium"
        case "Cold":    return "thermometer.snowflake"
        default:        return "questionmark.circle"
        }
    }

    private var badgeColor: Color {
        switch level {
        case "Hot":     return .danger
        case "Warm":    return .warning
        case "Cold":    return .accentBlue
        default:        return .textTertiary
        }
    }
}

// MARK: - Send Scout Sheet

private struct SendScoutSheet: View {
    let prospect: CollegeProspect
    let scouts: [Scout]
    let scoutingPhase: ScoutingPhase
    /// Thousands this report costs — rising with the number already on file.
    let cost: Int
    let slotsLeft: Int
    let budgetRemaining: Int
    /// Books the slot and the money once the report is actually filed.
    let onFiled: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                if scouts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.textTertiary)
                        Text("No Scouts Available")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Hire scouts from the Scout Team tab.")
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            HStack(spacing: 8) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Color.accentBlue.opacity(0.6))
                                Text("Phase: \(scoutingPhase.displayName) (Confidence: \(Int(scoutingPhase.confidenceLevel * 100))%)")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "dollarsign.circle")
                                    .foregroundStyle(Color.accentGold.opacity(0.8))
                                Text("$\(cost)K of $\(budgetRemaining)K \u{00B7} \(slotsLeft) evaluation\(slotsLeft == 1 ? "" : "s") left this cycle")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .listRowBackground(Color.backgroundSecondary)

                        Section("Select a Scout") {
                            ForEach(scouts) { scout in
                                Button {
                                    sendScout(scout)
                                } label: {
                                    ScoutRowView(scout: scout)
                                }
                                .listRowBackground(Color.backgroundSecondary)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Send Scout to \(prospect.firstName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func sendScout(_ scout: Scout) {
        // Belt and braces: the row that opened this sheet is already gated, and
        // this re-reads the three things that CAN move while the sheet is open
        // — the report count, the cycle's slots and the pot. It deliberately
        // does not re-check the phase: the sheet has no `Career` to read one
        // from, and a phase cannot advance while it is presented.
        guard prospect.scoutingReports.count < ScoutEvaluationBudget.maxReportsPerProspect,
              slotsLeft > 0,
              budgetRemaining >= cost else {
            dismiss()
            return
        }
        let report = ScoutingEngine.generateScoutReport(
            scout: scout,
            prospect: prospect,
            phase: scoutingPhase
        )
        ScoutingEngine.applyReport(report: report, to: prospect)
        onFiled(cost)
        dismiss()
    }
}
