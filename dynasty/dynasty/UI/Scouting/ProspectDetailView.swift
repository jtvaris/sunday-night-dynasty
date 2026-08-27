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

    /// The scout name `applyPreScoutedData` stamps on the baseline report the
    /// top of every class inherits at career creation. Paper the user never
    /// ordered, and it must not move his prices or his caps.
    static let inheritedScoutName = ProspectFog.inheritedScoutName

    /// Reports that count against `maxReportsPerProspect` and the price
    /// ladder: the ones THIS regime bought. The inherited baseline is excluded
    /// — it priced the class's best men at the top tier before the user had
    /// spent a dollar (#122: a $271K pot bought five reports, because every
    /// interesting man opened at the third-look price).
    static func chargeableReports(_ prospect: CollegeProspect) -> Int {
        prospect.scoutingReports.filter { $0.scoutName != inheritedScoutName }.count
    }

    /// Cost in thousands of the *next* report on a man who already carries
    /// `existingReports` CHARGEABLE ones (`chargeableReports`).
    ///
    /// Rising, because that is where the exploit lived: the first look is a
    /// cheap tape grade, the third is a cross-check trip nobody runs on a man
    /// they are not seriously considering. The ladder is sized against the
    /// DISCRETIONARY scouting pot — what is left after scout salaries and the
    /// combine trip, in practice $300-600K — so first looks at $15K make the
    /// 25-slot promise reachable instead of theoretical (#122: the old
    /// 20/35/55K ladder, priced off ALL reports including the inherited one,
    /// bought a $271K pot five reports).
    static func cost(existingReports: Int) -> Int {
        switch existingReports {
        case 0:  return 15
        case 1:  return 25
        default: return 40
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

/// What the war room hands the prospect card when it opens one on draft night
/// (#196b).
///
/// The card used to be reachable on the clock only as an iPad form sheet — a
/// small centred panel with a `Close` button — while the actual selection lived
/// in a second, competing modal ("Make Your Pick"). One man, two surfaces, and
/// the one with the whole scouting file on it was the one that could not draft
/// him. This is the other half of the fix: the card is the full screen, and the
/// commit is on it.
///
/// Deliberately three fields and no coordinator reference. `ProspectDetailView`
/// is the scouting hub's screen first; giving it a `DraftDayCoordinator` would
/// couple every spring surface to the draft room. The room keeps its own state
/// and hands the card a slot number and two closures.
struct ProspectDraftContext {
    /// The slot the user is on the clock with, or `nil` when somebody else is at
    /// the podium. Read live: the room re-evaluates the cover's content as the
    /// clock ticks, so a card left open through an expiry loses its gold CTA
    /// rather than offering a pick that `selectProspect` would silently refuse.
    var pickNumber: Int?
    /// Set when the man himself is gone — another club filed on him while this
    /// card was open. Read live for the same reason `pickNumber` is: the cover
    /// holds one captured prospect and the room keeps drafting behind it. When
    /// it is non-nil there is no primary, and the bar says WHY in his own terms
    /// rather than falling back to the generic off-the-clock hint.
    var unavailableReason: String? = nil
    /// Hands the card in. Only called while `pickNumber != nil`.
    var onDraft: () -> Void
    /// Back to the board. A full-screen cover has no swipe-to-dismiss, so the
    /// card owns its own exit — and the exit is always the draft, never the hub.
    var onBack: () -> Void
}

struct ProspectDetailView: View {
    let career: Career
    let prospect: CollegeProspect

    /// `true` when this card was opened from the war room while the draft clock
    /// is running (`LiveBigBoardPanel`).
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

    /// Non-nil when the war room opened this card (#196b). It is what turns the
    /// read into a decision: see ``ProspectDraftContext`` and `draftActionBar`.
    var draftContext: ProspectDraftContext? = nil

    @Environment(\.modelContext) private var modelContext
    @State private var scouts: [Scout] = []
    @State private var coaches: [Coach] = []
    /// The one sheet this card can have open. See ``CardSheet``.
    @State private var activeSheet: CardSheet?
    /// A film-study result waiting for the scout picker to finish dismissing
    /// (#117) — presented from the sheet's `onDismiss`, never mid-transition.
    @State private var pendingFilmResult: FilmStudyOutcome?
    /// The page's scroll proxy, captured inside `ScrollViewReader` so the MEET
    /// slot can jump to the Interview card (#180). A `ScrollViewProxy` is only
    /// vended inside the reader's closure, and the slot that uses it is built
    /// four view layers down.
    @State private var scrollProxy: ScrollViewProxy?
    @State private var showInterviewResult = false
    @State private var interviewResult: (personality: PersonalityArchetype, footballIQ: Int, characterNotes: [String])?
    @State private var positionRank: Int?
    @State private var teamPlayers: [Player] = []
    /// Unsigned players in THIS save — the other way to fill the hole this
    /// prospect would fill. The comparison card measured him against the club's
    /// own starter and nothing else, which answers "is he an upgrade" but never
    /// "is he an upgrade you have to spend a pick on".
    @State private var freeAgentPool: [Player] = []
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

    /// Whether this building has a scout read on him at all — the gate on the
    /// Scouting Report section, the starter comparison, and the wording of the
    /// evaluation row.
    ///
    /// Routed through `ProspectFog` rather than reading `scoutedOverall != nil`:
    /// the fog is the one authority on whether there is a scout read to show,
    /// and every list on the way to this card has already been ported to it. The
    /// raw field says "the generator ranked him top-250", which is a different
    /// question that happens to have the same answer in season 1 and a
    /// different one from season 2 on.
    private var isScouted: Bool { ProspectFog.read(prospect).source == .scouts }
    private var hasCombine: Bool {
        prospect.fortyTime != nil || prospect.benchPress != nil ||
        prospect.verticalJump != nil || prospect.broadJump != nil ||
        prospect.shuttleTime != nil || prospect.coneDrill != nil
    }
    private static let maxInterviews = 60
    /// #fleet review F19c: the ration is `DraftPrepProgress`', not this card's.
    /// A hard 30 here is a fourth copy of a number the prep machine, the
    /// workout room and the process bar all already count against.
    private static let maxWorkouts = DraftPrepProgress.workoutSlots

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
        guard ScoutEvaluationBudget.chargeableReports(prospect) < ScoutEvaluationBudget.maxReportsPerProspect else {
            return .reportsMaxed
        }
        guard evaluationSlotsLeft > 0 else { return .slotsSpent }
        let cost = ScoutEvaluationBudget.cost(existingReports: ScoutEvaluationBudget.chargeableReports(prospect))
        guard remainingScoutingBudget >= cost else {
            return .cannotAfford(cost: cost, remaining: remainingScoutingBudget)
        }
        return .available(cost: cost, slotsLeft: evaluationSlotsLeft)
    }

    /// The scroll id the Interview card carries, and the MEET slot's target.
    private static let interviewAnchor = "prospect.interview"

    var body: some View {
        // The reader wraps the page rather than living inside it: `DSDetailPage`
        // owns the `ScrollView`, and it is shared with the player and coach
        // cards, so the anchor this screen needs cannot be installed there.
        ScrollViewReader { proxy in
            page.onAppear { scrollProxy = proxy }
        }
    }

    private var page: some View {
        DSDetailPage {
            prospectHero
        } cards: {
            DSDetailColumns {
                // LEAD — your read and the decision it feeds.
                // `myVerdictCard` is this screen's subject (§2.11).
                myVerdictCard
                quickAssessmentCard
                starterComparisonCard
                draftCard
            } middle: {
                // MIDDLE — what your department has actually bought.
                //
                // FOG GATE, moved verbatim: the report block renders only when
                // `ProspectFog.read(prospect).source == .scouts`. Everything
                // inside it is already fogged per key by
                // `ProspectFog.AttributeDisclosure`; this outer gate is what
                // keeps an unscouted man from showing a grade block at all.
                if isScouted { scoutingReportCard }
                if prospect.interviewCompleted {
                    interviewResultsCard.id(Self.interviewAnchor)
                }
                characterFileCard
                riskFlagsCard
                instrumentsCard
            } trail: {
                // TRAIL — what the outside world can see.
                combineCard
                collegeProductionCard
                teamInterestCard
            }
        }
        .safeAreaInset(edge: .bottom) {
            prospectActionBar
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
        .sheet(item: $activeSheet, onDismiss: {
            // The film-study result presents AFTER the scout picker closes —
            // swapping the item while a sheet is up glitches the transition,
            // and the interview/workout pattern the user knows is
            // pick → sheet closes → results open.
            if let outcome = pendingFilmResult {
                pendingFilmResult = nil
                activeSheet = .filmResult(outcome)
            }
        }) { sheet in
            switch sheet {
            case .sendScout:
                SendScoutSheet(
                    prospect: prospect,
                    scouts: scouts,
                    scoutingPhase: currentScoutingPhase,
                    cost: ScoutEvaluationBudget.cost(existingReports: ScoutEvaluationBudget.chargeableReports(prospect)),
                    slotsLeft: evaluationSlotsLeft,
                    budgetRemaining: remainingScoutingBudget,
                    onFiled: { cost, outcome in
                        recordEvaluation(cost: cost)
                        pendingFilmResult = outcome
                    }
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
            case let .filmResult(outcome):
                FilmStudyResultSheet(
                    outcome: outcome,
                    prospect: prospect,
                    slotsLeft: evaluationSlotsLeft
                )
            case .filmRecord:
                // The FILM slot reopening a report filed earlier. `gradeBefore`
                // is `nil` on purpose: the band the user was looking at before
                // that report landed is not stored anywhere, and inventing one
                // would be a fabrication dressed as intel (the same rule
                // `WorkoutReportEntry.init(filed:report:)` follows).
                if let report = latestOwnFilmReport {
                    FilmStudyResultSheet(
                        outcome: FilmStudyOutcome(
                            report: report,
                            gradeBefore: nil,
                            gradeAfter: effectiveOverallGrade
                        ),
                        prospect: prospect,
                        slotsLeft: evaluationSlotsLeft
                    )
                }
            case .workoutRecord:
                if let report = latestWorkoutReport {
                    ProspectWorkoutRecordSheet(
                        entry: WorkoutReportEntry(filed: prospect, report: report),
                        staffName: report.scoutName,
                        occasion: "Private workout \u{00B7} \(career.currentSeason)",
                        slotsUsed: career.workoutsUsed,
                        slotsLeft: max(0, Self.maxWorkouts - career.workoutsUsed)
                    )
                }
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
        /// The report a film-study order just filed (#117) — the same
        /// pick-then-see-the-result shape the interview and workout have,
        /// instead of the sheet closing on a silently narrower band.
        case filmResult(FilmStudyOutcome)
        /// A report filed EARLIER, reopened from the FILM slot (#180). Carries
        /// no payload: the report is read off the prospect at present time, so
        /// the slot cannot hand the sheet a stale copy of it.
        case filmRecord
        /// The private-workout session, reopened from the WORK slot.
        case workoutRecord

        var id: String {
            switch self {
            case .sendScout:     return "sendScout"
            case .markNote:      return "markNote"
            case .workoutResult: return "workoutResult"
            case .filmResult:    return "filmResult"
            case .filmRecord:    return "filmRecord"
            case .workoutRecord: return "workoutRecord"
            }
        }
    }

    /// What one film-study order bought, captured around `applyReport` so the
    /// result sheet can show the band move the money paid for.
    struct FilmStudyOutcome: Identifiable {
        let id = UUID()
        let report: ScoutingReport
        let gradeBefore: GradeRange?
        let gradeAfter: GradeRange?
    }

    // MARK: - My Verdict
    //
    // The deep dive used to end in a dead end: forty numbers, eight mental
    // grades, an interview transcript — and the only thing the user could
    // record about any of it was a single "Add to Board" star that three of the
    // four mark systems could not see. This is where the read becomes a verdict.

    @ViewBuilder
    private var myVerdictCard: some View {
        DSDetailCard(
            "My Verdict",
            icon: "star.circle.fill",
            // NOTE-CENTRED (#192). The tier buttons that used to open this card
            // moved into the hero's mark lane, where they are one tap from the
            // name and the grade instead of a card down the column. Two controls
            // writing one piece of state is the duplication §2.13 forbids, and
            // the copy of it that lost is the one further from the subject.
            explainer: "The mark is in the header \u{2014} it is what the war room sorts by on draft night. This is why.",
            isSubject: true
        ) {
            Button {
                activeSheet = .markNote
            } label: {
                HStack(alignment: .top, spacing: DSSpacing.xs) {
                    Image(systemName: "note.text")
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.accentGold)
                        .padding(.top, 2)
                    if prospect.userMarkNote.isEmpty {
                        Text("Add a note \u{2014} why he is where he is on your board.")
                            .font(.system(size: DSType.Size.body))
                            .foregroundStyle(Color.textTertiaryReadable)
                    } else {
                        Text(prospect.userMarkNote)
                            .font(.system(size: DSType.Size.body))
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // What the market thinks versus what you graded him.
            if let read = ProspectFog.valueRead(
                for: prospect,
                marketRank: DraftIntel.consensusRank(for: prospect.id),
                myGrade: UserProspectGradeStore.shared.grade(for: prospect.id)
            ) {
                Divider().overlay(Color.surfaceBorder)
                DSDetailRow(label: "Value vs My Grade") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(read.label)
                            .font(.system(size: DSType.Size.body, weight: .bold))
                            .foregroundStyle(read.tint)
                        Text("market \u{2248} #\(read.marketRank) \u{00B7} you \u{2248} #\(read.impliedPick)")
                            .font(.system(size: DSType.Size.caption).monospacedDigit())
                            .foregroundStyle(Color.textTertiaryReadable)
                    }
                }
            }
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
    private var characterFileCard: some View {
        let medical = prospect.medicalConcerns ?? []
        let character = prospect.redFlags ?? []
        let total = medical.count + character.count
        let disclosure = ProspectFog.flagDisclosure(for: prospect, userTeamID: career.teamID)

        if disclosure != .hidden {
            DSDetailCard(
                "Medical & Character File",
                icon: "cross.case",
                explainer: "The league's paperwork. It opens in three steps \u{2014} the count appears once anybody has been near him, the contents only once the work is done."
            ) {
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

    // MARK: - Hero

    private var prospectHero: some View {
        DSDetailHero {
            HStack(alignment: .top, spacing: DSSpacing.md) {
                // Portrait — a draft class is 350 faceless names, so the head
                // shot is the cheapest way to make one prospect memorable.
                PersonFaceView(prospect: prospect, size: .medium)

                // Position badge
                VStack {
                    Text(prospect.position.rawValue)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 54, height: 54)
                        .background(positionColor, in: RoundedRectangle(cornerRadius: DSCornerRadius.card))
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
                                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                                        .fill((rank <= 3 ? Color.accentGold : Color.textSecondary).opacity(0.15))
                                )
                        }
                    }

                    HStack(spacing: 16) {
                        ProspectInfoPill(label: "Age", value: "\(prospect.age)")
                        ProspectInfoPill(label: "Ht", value: heightLabel)
                        ProspectInfoPill(label: "Wt", value: "\(prospect.weight) lbs")
                    }

                    // The verdict, in the lane the hero was already reserving
                    // (#192). See `heroMarkLane` — the grade column on the right
                    // is ~50 pt taller than this one, so the strip lands in dead
                    // space rather than pushing the page down.
                    heroMarkLane
                        .frame(maxWidth: 440)
                        .padding(.top, DSSpacing.xxs)
                }
                // The lane is the one flexible thing in this row, and the
                // `Spacer` below is the other: without a priority the HStack
                // splits the free width evenly between them and the four
                // buttons come out half-size in a narrow (split-view) column.
                // The identity block asks first; the spacer takes what is left.
                .layoutPriority(1)

                Spacer(minLength: DSSpacing.xs)

                if let gradeRange = effectiveOverallGrade {
                    VStack(spacing: 2) {
                        Text(gradeRange.displayText)
                            .font(.system(size: gradeRange.isSingleGrade ? DSType.Size.display : DSType.Size.title1, weight: .heavy))
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
                            .font(.system(size: DSType.Size.display, weight: .heavy))
                            .foregroundStyle(Color.textTertiary)
                        Text("Unscouted")
                            .font(.caption2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
        }
    }

    // MARK: - Mark lane (#192)

    /// **The four marks, as buttons, in the hero.**
    ///
    /// The mark used to be TWO controls for one piece of state: a floating
    /// `Mark` menu in the action bar's bottom-left gutter — two taps to set a
    /// tier, and a menu is a control that hides its own options — plus a
    /// duplicate four-button picker inside `My Verdict`, a card away down the
    /// lead column. The verdict is the first thing a user forms on this screen
    /// and the only thing the war room sorts by on the clock, so the control
    /// belongs with the identity block and the grade: one tap per tier, the
    /// live one lit, all four always visible.
    ///
    /// **Not gold, on purpose.** Gold is the commit CTA's fill — the action
    /// bar's primary is the screen's one gold button, and P5 allows exactly one.
    /// A mark is free, local, reversible and stays live on draft night when
    /// every priced action is shut, so the active tier is a *washed* chip in the
    /// tier's own colour with a coloured rule around it, never a filled button.
    /// `.elite`'s tier colour IS `accentGold` (it is gold on every board row and
    /// chip in the app, and that identity is not this screen's to break), so the
    /// wash is what keeps it from reading as a second CTA.
    private var heroMarkLane: some View {
        HStack(spacing: DSSpacing.xs) {
            ForEach(ProspectMarkTier.choices) { tier in
                markLaneButton(tier)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your mark")
    }

    private func markLaneButton(_ tier: ProspectMarkTier) -> some View {
        let isSelected = prospect.userMark == tier
        return Button {
            // Tapping the live tier clears it — the same toggle `ProspectMarkMenu`
            // and every row control use, so the mark can be undone where it was
            // set rather than only from a menu's "Clear Mark".
            prospect.setUserMark(isSelected ? .none : tier)
            try? modelContext.save()
        } label: {
            HStack(spacing: DSSpacing.xxs) {
                Image(systemName: tier.icon)
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                Text(tier.label)
                    .font(.system(size: DSType.Size.footnote, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? tier.color : Color.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .fill(isSelected ? tier.color.opacity(0.16) : Color.backgroundTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                    .strokeBorder(
                        isSelected ? tier.color : Color.surfaceBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tier.label): \(tier.blurb)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Scout Confidence Badge

    /// The three dots under the hero grade: how many looks of YOUR OWN are
    /// behind the band above them.
    ///
    /// Counted on `ProspectFog.ownReportCount` (#184). The retired
    /// `scoutReportCount` was the raw `scoutingReports.count`, which includes
    /// the `Previous Staff`
    /// row `applyPreScoutedData` stamps on the top of every class — so a save
    /// on its first day showed one lit dot and "Low confidence · 1/3 scouts"
    /// on 250 men nobody in the building had watched, and the denominator was
    /// wrong too: three is `ScoutEvaluationBudget.maxReportsPerProspect`, a cap
    /// on reports the user PAYS for, and the inherited row does not count
    /// against it (`chargeableReports`). One counter, one meaning.
    private var scoutConfidenceBadge: some View {
        let count = ProspectFog.ownReportCount(prospect)
        let confidenceColor: Color
        let confidenceLabel: String
        switch count {
        case 0:  confidenceColor = .textTertiary; confidenceLabel = "Unscouted"
        case 1:  confidenceColor = .warning;      confidenceLabel = "Low"
        case 2:  confidenceColor = .accentBlue;   confidenceLabel = "Medium"
        default: confidenceColor = .success;      confidenceLabel = "High"
        }
        let cap = ScoutEvaluationBudget.maxReportsPerProspect
        return HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<cap, id: \.self) { i in
                    Circle()
                        .fill(i < count ? confidenceColor : confidenceColor.opacity(0.3))
                        .frame(width: 6, height: 6)
                }
            }
            Text("\(confidenceLabel) confidence \u{00B7} \(count)/\(cap) reports")
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(confidenceColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(confidenceColor.opacity(0.12), in: Capsule())
        .help("Grade reliability: \(confidenceLabel.lowercased()) \u{2014} \(count) of \(cap) reports your department has filed on him.")
    }

    // MARK: - Potential Badge

    private var potentialBadge: some View {
        let label = prospect.scoutedPotentialLabel ?? .unknown
        let color = potentialLabelColor(label)
        return Group {
            if label != .unknown {
                Text(label.rawValue)
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Quick Assessment Row

    @ViewBuilder
    private var quickAssessmentCard: some View {
        let risk = prospect.riskLevel
        let fit = evaluateSchemeFit()
        let readiness = ProspectReadinessBucket(readiness: prospect.nflReadiness)
        DSDetailCard(
            "Quick Assessment",
            icon: "gauge.with.dots.needle.bottom.50percent",
            explainer: "The five one-glance reads: risk profile, scheme fit, athletic profile, where his stock is going, and how much of him plays in year one."
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                HStack(spacing: 8) {
                    // Risk badge. The sentence under it is the one thing this
                    // pill was missing everywhere it appears: a red BOOM/BUST
                    // on the club's own #1 reads as a verdict on the player
                    // until something says it is a spread between reports.
                    if risk != .unknown {
                        assessmentBadge(icon: risk.icon, label: risk.rawValue, color: risk.color)
                            .help(riskExplanation(risk))
                            .accessibilityHint(riskExplanation(risk))
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

    /// One sentence per risk level, owned by ``ProspectRiskBadge`` so the pill
    /// on a board row and the badge on this card cannot explain themselves
    /// differently. This used to hold the only copy of the text and had no
    /// call sites at all.
    private func riskExplanation(_ risk: ProspectRiskLevel) -> String {
        ProspectRiskBadge.explanation(risk)
    }

    // MARK: - Starter Comparison Section

    @ViewBuilder
    private var starterComparisonCard: some View {
        if isScouted {
            let starters = teamPlayers
                .filter { $0.position == prospect.position }
                .sorted { $0.overall > $1.overall }
            if let starter = starters.first {
                DSDetailCard(
                    "vs Current Starter",
                    icon: "arrow.left.arrow.right",
                    explainer: "Both sides on the same letter ladder \u{2014} his fogged band against the man he would be replacing, and against the best man at the position still unsigned."
                ) {
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

                        // Qualitative comparison, off the SAME band printed two
                        // inches to the left. It used to subtract the raw
                        // `scoutedOverall`, which is sharper than the fogged
                        // band beside it — so a card showing "B-/A-" could
                        // still label the gap from a number the user is not
                        // entitled to. No band, no verdict.
                        let diff = effectiveOverallGrade
                            .map { ProspectFog.approximateValue(of: $0.midGrade) - starter.overall } ?? 0
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

                    bestFreeAgentRow
                }
            } else {
                DSDetailCard("vs Current Starter", icon: "arrow.left.arrow.right") {
                    HStack(spacing: DSSpacing.xs) {
                        Image(systemName: "person.fill.badge.plus")
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.success)
                        Text("No \(prospect.position.rawValue) on roster \u{2014} immediate starter")
                            .font(.system(size: DSType.Size.body))
                            .foregroundStyle(Color.success)
                    }
                }
            }
        }
    }

    /// The other way to fill the hole: the best UNSIGNED player at the position.
    ///
    /// The card compared a prospect against the club's own best man and stopped
    /// there, which answers "is he an upgrade" but never the question a GM
    /// actually has in front of him in March — "is he an upgrade I have to
    /// spend a first-round pick on, when there is a 79 sitting in free agency".
    /// Same letter ladder as the two columns above it, same `LetterGrade.from`
    /// the starter side uses, so all three grades on this card are one claim.
    @ViewBuilder
    private var bestFreeAgentRow: some View {
        let best = freeAgentPool
            .filter { $0.position == prospect.position }
            .max { $0.overall < $1.overall }
        Divider().overlay(Color.surfaceBorder)
        if let best {
            let faGrade = LetterGrade.from(numericValue: best.overall)
            let diff = effectiveOverallGrade
                .map { ProspectFog.approximateValue(of: $0.midGrade) - best.overall } ?? 0
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "figure.stand")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.accentBlue)
                Text("Best free agent: \(best.fullName), age \(best.age)")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DSSpacing.xxs)
                Text(faGrade.rawValue)
                    .font(.system(size: DSType.Size.body, weight: .heavy))
                    .foregroundStyle(detailGradeColor(faGrade))
                Text(starterComparisonLabel(diff).replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: DSType.Size.caption, weight: .bold))
                    .foregroundStyle(starterComparisonColor(diff))
            }
        } else {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "figure.stand")
                    .font(.system(size: DSType.Size.footnote))
                    .foregroundStyle(Color.textTertiary)
                Text("No \(prospect.position.rawValue) on the free-agent market \u{2014} the draft is the only door.")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiaryReadable)
            }
        }
    }

    /// The verdict on prospect-vs-starter, as ONE thing.
    ///
    /// This was two functions over the same `diff` with **different cut
    /// points** — the label flipped to "Close" at -5 while the colour stayed
    /// green until -3 and turned gold until -8 — so a card could print
    /// "Development Project" in the same green as "Upgrade". One ladder, one
    /// switch, and it is not a rating ladder (a delta between two grades is not
    /// a 0–99 read), so it does not go through `Color.forRating`.
    private enum StarterVerdict {
        case upgrade, close, developmentProject, longTermProject

        init(diff: Int) {
            switch diff {
            case 0...:      self = .upgrade
            case -4...(-1): self = .close
            case -11...(-5): self = .developmentProject
            default:        self = .longTermProject
            }
        }

        var label: String {
            switch self {
            case .upgrade:            return "Upgrade"
            case .close:              return "Close"
            case .developmentProject: return "Development\nProject"
            case .longTermProject:    return "Long-term\nProject"
            }
        }

        var tint: Color {
            switch self {
            case .upgrade:            return .success
            case .close:              return .accentBlue
            case .developmentProject: return .warning
            case .longTermProject:    return .textSecondary
            }
        }
    }

    private func starterComparisonLabel(_ diff: Int) -> String {
        StarterVerdict(diff: diff).label
    }

    private func starterComparisonColor(_ diff: Int) -> Color {
        StarterVerdict(diff: diff).tint
    }

    // MARK: - Team Interest Row

    @ViewBuilder
    private var teamInterestCard: some View {
        if !prospect.teamInterest.isEmpty {
            DSDetailCard(
                "League Interest",
                icon: "person.3",
                explainer: "How many other war rooms have shown their hand on him. It moves where he goes, not how good he is."
            ) {
                HStack(spacing: DSSpacing.xs) {
                    InterestBadge(level: prospect.interestLevel)
                    Text("\(prospect.teamInterest.count) team\(prospect.teamInterest.count == 1 ? "" : "s") interested")
                        .font(.system(size: DSType.Size.body))
                        .foregroundStyle(Color.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Combine Section

    private var combineCard: some View {
        DSDetailCard(
            "Physical Measurables",
            icon: "figure.run",
            explainer: "Combine and pro-day numbers. Exact times need scouts in the building \u{2014} otherwise these are the broadcast figures, rounded."
        ) {
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
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "clock")
                        .foregroundStyle(Color.textTertiaryReadable)
                    Text("Combine results pending")
                        .font(.system(size: DSType.Size.body))
                        .foregroundStyle(Color.textTertiaryReadable)
                }
            }
        }
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

    /// **Fog-critical.** Every read below goes through `ProspectFog` /
    /// `ProspectFog.AttributeDisclosure`; the card gate itself is
    /// `if isScouted` at the call site. Nothing here reads
    /// `trueOverall` / `truePhysical` / `trueAttributes`, and wave 4 moved the
    /// block without touching a single one of those ports.
    @ViewBuilder
    private var scoutingReportCard: some View {
        DSDetailCard(
            "Scouting Report",
            icon: "doc.text.magnifyingglass",
            explainer: "What your department has filed. A locked key is one nobody has bought yet \u{2014} the pills at the bottom say which instruments you have spent."
        ) {
            // Overall grade
            if let gradeRange = effectiveOverallGrade {
                DSDetailRow(label: "Overall Grade") {
                    Text(gradeRange.displayText)
                        .font(.system(size: DSType.Size.body, weight: .bold))
                        .foregroundStyle(detailGradeColor(gradeRange.midGrade))
                }
            }

            // Potential
            if let potentialLabel = prospect.scoutedPotentialLabel {
                DSDetailRow(label: "Potential") {
                    Text(potentialLabel.rawValue)
                        .font(.system(size: DSType.Size.body, weight: .semibold))
                        .foregroundStyle(potentialLabelColor(potentialLabel))
                }
            } else if let potential = prospect.scoutedPotential,
                      ProspectFog.hasOwnReport(prospect) {
                // Legacy fallback, for saves whose reports predate
                // `potentialLabel`. Gated on work of THIS regime's: the only
                // other writer of `scoutedPotential` is
                // `ScoutingEngine.applyPreScoutedData`, which guesses the top 50
                // of the class within ±8 of the truth — and this row renders it
                // as one exact letter, with no band and no attribution. That is
                // the previous staff's guess printed as your department's
                // finding.
                let potentialGrade = LetterGrade.from(numericValue: potential)
                DSDetailRow(label: "Potential") {
                    Text(potentialGrade.rawValue)
                        .font(.system(size: DSType.Size.body, weight: .bold))
                        .foregroundStyle(detailGradeColor(potentialGrade))
                }
            }

            // The legacy "Scout Grade" row is gone: `syncProspectGrades` pins
            // it to the band's midpoint on every load, so it printed a pinpoint
            // letter beside the fogged range above — one exact answer the range
            // exists to withhold, and for an inherited-only prospect it dressed
            // the previous regime's guess as this department's.

            // Personality has two writers — a meeting (`conductInterview`) and a
            // report that came back with a personality read (`applyReport`) — and
            // they are not equally good. Naming the instrument is the difference
            // between a read the user knows to discount and a fact he cannot.
            if let personality = prospect.scoutedPersonality {
                DSDetailRow(label: "Personality") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(personality.displayName)
                            .font(.system(size: DSType.Size.body, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text(personalityAttribution)
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textTertiaryReadable)
                    }
                }
                // What the archetype BUYS. The name and a tier colour were the
                // whole read: "Mentor" told the user nothing about whether it
                // was worth a round. One sentence, off the enum, so the roster
                // card and this one cannot describe the same trait differently.
                Text(personality.effectSummary)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Both grids draw every key, revealed or not, and name what bought
            // the ones that are lit — see `ProspectFog.AttributeDisclosure`.
            mentalGradesGrid

            positionGradesGrid

            // The instrument strip — ONE reserved slot per tool the spring
            // offers, so the card answers "what have I run on this man" in a
            // glance (#117: it used to show two of the five and the user
            // reasonably read that as the complete list).
            ProspectInstrumentStrip(slots: instrumentSlots)
        }
    }

    // MARK: - Personality attribution (#185)

    /// Names the instrument that produced the personality currently on the card.
    ///
    /// It reads the stored provenance (`scoutedPersonalitySource`, written only
    /// by `ScoutingEngine.recordPersonalityRead`) rather than guessing from
    /// flags. The guess it replaces — "interviewCompleted ? your interview :
    /// hasOwnReport ? scouts : consensus" — was wrong in both directions: a
    /// report filed AFTER the meeting used to be credited to the meeting, and
    /// an interview read on a man your department had also filmed could be
    /// re-attributed to the film. Naming the wrong instrument is worse than
    /// naming none, because the whole point of the label is to tell the user
    /// how much to discount the read.
    ///
    /// `nil` provenance is the league's read: either nothing has looked at him
    /// yet beyond the inherited board, or the row predates the field.
    private var personalityAttribution: String {
        (prospect.scoutedPersonalitySource ?? .leagueConsensus).attributionLabel
    }

    // MARK: - Instrument slots (#180)

    /// The five pre-draft instruments as fixed state slots.
    ///
    /// This was five `StatusPill`s ("Film Study", "Interview", "Pro Day",
    /// "Workout", "Top-30 Visit") in a plain `HStack`: ~600 pt of pill in the
    /// ~305 pt middle column, so at three columns every label broke
    /// letter-by-letter and the row rendered as five vertical alphabet columns.
    /// It is the shared `DSStatusPill` vocabulary now — 4-letter idents, a
    /// dashed reserved slot for work nobody has done (§2.2: the HOLE is what
    /// the user scans for), and a strip that wraps whole pills.
    ///
    /// Film and Workout are derived from the report ledger rather than from a
    /// flag: a workout has no flag of its own (it files a `.personalWorkout`
    /// report AND sets `proDayCompleted`, see #115), and the pre-scout
    /// `Previous Staff` freebie must not light Film Study for work this regime
    /// never ordered.
    ///
    /// The three instruments that keep a card are also the way back to it —
    /// see ``ProspectInstrumentStrip`` for why those look different.
    private var instrumentSlots: [ProspectInstrumentSlot] {
        // Film reports only — `ownReportCount` also counts the private
        // workout's `.personalWorkout` row, which has its own slot two along.
        let filmReports = prospect.scoutingReports.filter {
            $0.scoutName != ProspectFog.inheritedScoutName && $0.phase != .personalWorkout
        }.count
        // A filed report grades EVERY key (`applyGradeBasedFields`), so this is
        // the honest yield of the film work rather than a slice of it.
        let bands = ProspectFog.mentalDisclosure(prospect).grades.count
            + ProspectFog.positionSkillDisclosure(prospect).grades.count

        return [
            ProspectInstrumentSlot(
                ident: "FILM",
                name: "Film study",
                isSet: latestOwnFilmReport != nil,
                yield: bands > 0
                    ? "\(filmReports) report\(filmReports == 1 ? "" : "s") \u{2192} \(bands) bands"
                    : "\(filmReports) report\(filmReports == 1 ? "" : "s") filed",
                open: latestOwnFilmReport == nil ? nil : { activeSheet = .filmRecord }
            ),
            ProspectInstrumentSlot(
                ident: "MEET",
                name: "Interview",
                isSet: prospect.interviewCompleted,
                yield: prospect.interviewFootballIQ.map { "IQ \($0) + personality" } ?? "meeting held",
                open: prospect.interviewCompleted ? { scrollToInterview() } : nil
            ),
            ProspectInstrumentSlot(
                ident: "PRO DAY",
                name: "Pro day",
                isSet: prospect.proDayCompleted,
                yield: "measurables verified",
                open: nil
            ),
            ProspectInstrumentSlot(
                ident: "WORK",
                name: "Private workout",
                isSet: latestWorkoutReport != nil,
                yield: "session on file",
                open: latestWorkoutReport == nil ? nil : { activeSheet = .workoutRecord }
            ),
            ProspectInstrumentSlot(
                ident: "T30",
                name: "Top-30 visit",
                isSet: hasTop30Visit,
                yield: "medical + character file open",
                open: nil
            ),
        ]
    }

    /// The most recent tape report THIS regime ordered — what the FILM slot
    /// reports and reopens. The inherited `Previous Staff` rows and the
    /// workout's own report are both excluded: the first is not this
    /// building's work, the second has its own slot.
    private var latestOwnFilmReport: ScoutingReport? {
        prospect.scoutingReports.last {
            $0.scoutName != ProspectFog.inheritedScoutName && $0.phase != .personalWorkout
        }
    }

    /// A private workout files a `.personalWorkout` report rather than setting
    /// a flag of its own (see #115) — the ledger is the truth here.
    private var latestWorkoutReport: ScoutingReport? {
        prospect.scoutingReports.last { $0.phase == .personalWorkout }
    }

    /// The MEET slot's destination. The meeting's result is a whole card on
    /// this page rather than a sheet, so the slot takes the user to it instead
    /// of opening a second copy of it in a modal.
    private func scrollToInterview() {
        withAnimation(.easeInOut(duration: 0.25)) {
            scrollProxy?.scrollTo(Self.interviewAnchor, anchor: .top)
        }
    }

    /// Facility visits are recorded per club, so the pill answers for THIS
    /// building, not for the league.
    private var hasTop30Visit: Bool {
        guard let teamID = career.teamID else { return false }
        return prospect.top30VisitedByTeams.contains(teamID)
    }

    /// The mental block, drawn against the instruments that write it.
    ///
    /// Every key is rendered whether or not it has been bought: a key nobody has
    /// worked is a DARK cell, not an absent one. Silently dropping the unbought
    /// keys is what put a full eight-grade row directly above two empty
    /// "Interview" / "Pro Day" chips and made the card look like it was printing
    /// the generator's hidden numbers — the grades were honest (a filed report
    /// grades all eight), but nothing on the card said which instrument had paid
    /// for them. `ProspectFog.mentalDisclosure` is the authority on both halves.
    ///
    /// LRN = how fast he absorbs a playbook (drives scheme install speed).
    /// CMP = competitiveness, how he answers adversity (plan §2.1).
    private var mentalGradesGrid: some View {
        let disclosure = ProspectFog.mentalDisclosure(prospect)
        let unread = disclosure.unread(of: ProspectFog.mentalKeys)

        return VStack(alignment: .leading, spacing: 6) {
            gradeBlockHeader(title: "Mental Attributes", attribution: disclosure.attribution)

            if disclosure.hasAny {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                    ForEach(ProspectFog.mentalKeys, id: \.self) { key in
                        if let gr = disclosure[key] {
                            gradeCell(key: key, grade: gr)
                        } else {
                            lockedGradeCell(key: key)
                        }
                    }
                }
                if !unread.isEmpty {
                    gradeBlockFootnote(ProspectFog.mentalUnlockHint(forUnread: unread))
                }
            } else {
                gradeBlockEmptyState(
                    "No mental read yet. A scouting report grades all eight; an interview reads the five a meeting can answer."
                )
            }
        }
    }

    /// The position-skill block. Same rules as the mental block, against its own
    /// instrument: only a filed report writes these, so an interview never lights
    /// a cell here and the hint never offers one.
    private var positionGradesGrid: some View {
        let disclosure = ProspectFog.positionSkillDisclosure(prospect)
        let keys = ProspectFog.positionSkillKeys(for: prospect)
        let unread = disclosure.unread(of: keys)

        return VStack(alignment: .leading, spacing: 6) {
            gradeBlockHeader(title: "Position Skills", attribution: disclosure.attribution)

            if disclosure.hasAny {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(keys.count, 6)),
                    spacing: 8
                ) {
                    ForEach(keys, id: \.self) { key in
                        if let gr = disclosure[key] {
                            gradeCell(key: key, grade: gr)
                        } else {
                            lockedGradeCell(key: key)
                        }
                    }
                }
                if !unread.isEmpty {
                    gradeBlockFootnote(ProspectFog.positionSkillUnlockHint)
                }
            } else {
                gradeBlockEmptyState(
                    "No skill grades yet. Send a scout \u{2014} any filed report grades every \(prospect.position.rawValue) skill."
                )
            }
        }
    }

    /// Block title plus the one line naming what paid for what is under it.
    private func gradeBlockHeader(title: String, attribution: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
            if let attribution {
                Text(attribution)
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(Color.accentGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
    }

    private func gradeBlockFootnote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Color.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func gradeBlockEmptyState(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "eye.slash")
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 1)
            Text(text)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// An attribute nobody has worked. Deliberately shaped like `gradeCell` so
    /// the grid reads as one row of eight with holes in it, rather than a short
    /// row that hides how much of the man is still unknown.
    private func lockedGradeCell(key: String) -> some View {
        VStack(spacing: 2) {
            Text("\u{2014}")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
                        .fill(Color.textTertiary.opacity(0.06))
                )
            // The KEY is the information in a locked cell — it names which of
            // the eight attributes is still unread. At 60 % tertiary it was the
            // faintest text on the card; `textTertiaryReadable` keeps it quiet
            // against the filled cells beside it without going under AA.
            Text(key)
                .font(.caption2)
                .foregroundStyle(Color.textTertiaryReadable)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(key) not read yet")
    }

    private func gradeCell(key: String, grade: GradeRange) -> some View {
        VStack(spacing: 2) {
            Text(grade.displayText)
                .font(.caption.weight(.bold))
                .foregroundStyle(detailGradeColor(grade.midGrade))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.tight)
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
    private var interviewResultsCard: some View {
        DSDetailCard(
            "Interview",
            icon: "bubble.left.and.bubble.right",
            explainer: "What the meeting bought: a football-IQ read, a personality, and five mental keys nothing else on this page can unlock."
        ) {
            // Who ran it, and the grade it produced. The card's own
            // `SectionHeaderText` already says "Interview" — the inner title
            // that used to sit here said it a second time, in a third type
            // voice, 4 pt below the first.
            HStack {
                if let attribution = interviewAttributionLine {
                    Text(attribution)
                        .font(.system(size: DSType.Size.caption))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .lineLimit(1)
                }
                Spacer(minLength: DSSpacing.xxs)
                if let iq = prospect.interviewFootballIQ {
                    // Overall interview grade
                    let grade = interviewGradeLetter(iq: iq, personality: prospect.scoutedPersonality)
                    Text(grade)
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(interviewDetailGradeColor(grade))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
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

            // Personality badge with colored background (Task 1).
            //
            // The attribution under it comes from the SAME stored provenance as
            // the Scouting Report card's (#185). It is not decoration on this
            // card either: the badge shows whatever read is currently on file,
            // and on a man who was interviewed the meeting is only usually the
            // instrument behind it — a misread meeting writes nothing onto a
            // card that already carries a report's read, and a legacy save
            // carries no provenance at all. The line says which of those it is.
            if let personality = prospect.scoutedPersonality {
                HStack(alignment: .firstTextBaseline) {
                    Text("Personality")
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
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
                        Text(personalityAttribution)
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textTertiaryReadable)
                    }
                }
                Text(personality.effectSummary)
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .fixedSize(horizontal: false, vertical: true)
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
                    Text(InterviewResult.installSpeedHint(iq: iq))
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
                                .foregroundStyle(Color.dangerText)
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
                            .foregroundStyle(Color.dangerText)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .fill(Color.danger.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
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
                        RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                            .fill(Color.success.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: DSCornerRadius.inline)
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
                                .font(.system(size: DSType.Size.body))
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                }
            }
        }
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
                                .font(.system(size: grade.isSingleGrade ? DSType.Size.callout : DSType.Size.footnote, weight: .heavy))
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
                            RoundedRectangle(cornerRadius: DSCornerRadius.tight)
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
        // The app's ONE grade ladder — see `InterviewResult.interviewGrade`.
        // A private four-cut here printed "B" for a man the board next door
        // called "B-", off the same number.
        return PositionGradeCalculator.letterGrade(for: score)
    }

    /// The interview block's letters read the ONE ladder. Its own switch shifted
    /// the whole scale one rung warm — A gold, B green — so the same letter on
    /// the same man was a different colour on the card than in the room that
    /// produced it, and D shared F's red.
    private func interviewDetailGradeColor(_ grade: String) -> Color {
        Color.forGrade(grade)
    }

    private func personalityDetailBadgeColor(_ p: PersonalityArchetype) -> Color {
        switch p.tier {
        case .positive: return .success
        case .risky:    return .danger
        case .neutral:  return .warning.opacity(0.8)
        }
    }

    private func footballIQGradeLetter(_ iq: Int) -> String {
        PositionGradeCalculator.letterGrade(for: iq)
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

    // MARK: - College Production Section
    //
    // A SECOND "Position Skills" section used to live here, and it was the one
    // real truth leak on this card. `flavorGradeStat` fell back to
    // `positionFallbackValues` — letter grades taken straight off
    // `prospect.truePositionAttributes`, the hidden generator block — whenever
    // the scouted band for a key was missing, and the section was gated on
    // `isScouted` (`scoutedOverall != nil`), which `ScoutingEngine.applyPreScoutedData`
    // sets for the top 250 of every class WITHOUT writing a single band. Every
    // one of those men printed his true skill letters to a user who had never
    // filed a report. Three of its keys ("SAc", "DAc", "TAK") could never match
    // what the engine writes ("SAC", "DAC", "TKL") either, so a fully scouted
    // quarterback or linebacker took the truth path as well.
    //
    // It is gone rather than patched: `positionGradesGrid` in the Scouting
    // Report section renders the same data for EVERY key of the position, dark
    // where the work has not been done, attributed where it has.

    /// Snapshot of college playing time + production. Generator v2 stores this
    /// as a noisy signal (`collegeProductionScore`) that correlates with — but
    /// does not reveal — the prospect's true grade.
    ///
    /// TWO POPULATIONS, TWO PRESENTATIONS (#181). ~5 % of a class never got on
    /// the field, and `DraftClassBuilder.applyBuriedUsage` derives their
    /// production score from SNAPS and from nothing else — over that slice
    /// `corr(production, trueOverall)` is ~0 by construction. So the tier those
    /// men carry is not a weak verdict on their football, it is not a verdict
    /// at all, and printing "Below Avg" beside 89 snaps was the card asserting
    /// a quality judgment the engine never made. The buried card reads the
    /// burial narrative instead, a neutral **Limited sample** chip in a tint
    /// deliberately outside the grade palette, and a footnote that says the
    /// tape is thin rather than that the player is.
    ///
    /// FOG. Everything on this card is public record and renders identically
    /// for the gem and for the genuine backup: the reason string is generated
    /// from competition level and starts, never from ability; the chip is one
    /// chip for the whole cohort; and no line here narrows toward whether the
    /// man behind the thin tape is worth a pick. Finding that out is what
    /// instruments are for — which is the entire point of the mechanic.
    @ViewBuilder
    private var collegeProductionCard: some View {
        let isBuried = prospect.hasLimitedCollegeSample
        DSDetailCard(
            "College Production",
            icon: "chart.bar.xaxis",
            explainer: "A noisy public signal. It correlates with his grade; it does not reveal it."
        ) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                // The narrative hook. Without it "89 snaps" reads as one thing
                // only — bad player — and the whole buried cohort collapses
                // into noise the user learns to skip.
                if let narrative = burialNarrative {
                    HStack(alignment: .top, spacing: DSSpacing.xxs) {
                        Image(systemName: "text.quote")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.textTertiaryReadable)
                        Text(narrative)
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }

                HStack(spacing: 16) {
                    productionTile(label: "Years Started", value: "\(prospect.collegeYearsStarted)/4")
                    if isBuried {
                        productionTile(
                            label: "Production",
                            value: String(localized: "Limited sample"),
                            color: Self.limitedSampleTint,
                            asChip: true
                        )
                    } else {
                        productionTile(
                            label: "Production",
                            value: prospect.collegeProductionTier.displayName,
                            color: prospect.collegeProductionTier.chipColor
                        )
                    }
                    if let level = prospect.collegeCompetitionLevel {
                        productionTile(label: String(localized: "Competition"), value: level.longName)
                    }
                }

                // The qualifier is load-bearing: the same row of numbers means
                // "his best year" for a receiver and "everything he ever did"
                // for a tackle, and an unlabelled line let the user read a
                // four-year lineman's career starts as a single season.
                VStack(alignment: .leading, spacing: 2) {
                    Text(statLineQualifier.uppercased())
                        .font(.system(size: DSType.Size.micro, weight: .semibold))
                        .foregroundStyle(Color.textTertiaryReadable)
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                        Text(prospect.collegeStatLine)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                DSDetailNote(text: productionFootnote)
            }
        }
    }

    /// Tint for the **Limited sample** chip. Slate, and deliberately not a
    /// member of the grade ladder (`Color.forGrade`: elite green / success /
    /// accent blue / warning / alert orange / danger) — the chip states that
    /// the record is thin, and any verdict colour would put back the quality
    /// judgment the chip exists to remove.
    private static let limitedSampleTint = Color.textTertiaryReadable

    /// The burial reason as a sentence, or `nil` for a prospect who played.
    ///
    /// `collegeBurialReason` is stored as a lower-case fragment ("sat behind a
    /// first-round pick") so a board row can quote it inline; the card is the
    /// one place it stands alone, so it is capitalised and stopped here rather
    /// than in the generator.
    private var burialNarrative: String? {
        let reason = prospect.collegeBurialReason
        guard !reason.isEmpty else { return nil }
        return reason.prefix(1).uppercased() + String(reason.dropFirst()) + "."
    }

    /// What span of football the stat line covers.
    ///
    /// `CollegeProspect.statLine` renders per-season RATES for every position
    /// except the offensive line, whose line leads with cumulative career
    /// starts; a buried prospect's usage line is the snaps of his last season.
    private var statLineQualifier: String {
        if prospect.hasLimitedCollegeSample { return String(localized: "Last season") }
        switch prospect.position {
        case .LT, .LG, .C, .RG, .RT: return String(localized: "Career")
        default:                     return String(localized: "Best season")
        }
    }

    /// The footnote under the numbers.
    ///
    /// The line it replaces ("...already factor into his grade and his
    /// ceiling") was false in the direction that matters: production is a
    /// SIGNAL generated alongside the grade, not an input to it, and reading it
    /// as an input invites the user to double-count the same evidence. It also
    /// printed under a man who had never started a game, congratulating him on
    /// heavy starter snaps.
    private var productionFootnote: String {
        if prospect.hasLimitedCollegeSample {
            return String(localized: "Barely saw the field \u{2014} the tape is thin by design.")
        }
        let tier = prospect.collegeProductionTier
        if prospect.collegeYearsStarted >= 3, tier == .elite || tier == .aboveAvg {
            return String(localized: "Heavy starter snaps and strong production \u{2014} as deep a college record as this board carries.")
        }
        return String(localized: "Public record of what he did in college. What it is worth in the pro game is your department's call.")
    }

    /// One production/competition figure.
    ///
    /// `asChip` wraps the value in a capsule instead of tinting bare text, so a
    /// non-verdict value cannot be mistaken for a tier read in a colour nobody
    /// recognises.
    private func productionTile(
        label: String,
        value: String,
        color: Color = .textPrimary,
        asChip: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            if asChip {
                Text(value)
                    .font(.system(size: DSType.Size.caption, weight: .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(color.opacity(0.15))
                            .overlay(Capsule().strokeBorder(color.opacity(0.35)))
                    )
            } else {
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.inline))
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
    private var riskFlagsCard: some View {
        let flags = collectRiskFlags()
        if !flags.isEmpty {
            DSDetailCard(
                "Scouting Concerns",
                icon: "exclamationmark.triangle",
                explainer: "What YOUR people came back saying \u{2014} distinct from the league's medical and character file, which is its own card."
            ) {
                ForEach(flags, id: \.self) { flag in
                    HStack(alignment: .top, spacing: DSSpacing.xs) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: DSType.Size.footnote))
                            .foregroundStyle(Color.danger)
                        Text(flag)
                            .font(.system(size: DSType.Size.body))
                            .foregroundStyle(Color.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
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

    private var draftCard: some View {
        DSDetailCard(
            "Draft Information",
            icon: "list.number",
            explainer: "Where the league expects him to go, and what that slot costs the cap."
        ) {
            onTheClockValueRow

            DSDetailRow(
                "Declaring for Draft",
                prospect.isDeclaringForDraft ? "Yes" : "No",
                tint: prospect.isDeclaringForDraft ? .success : .textSecondary
            )

            if let proj = prospect.draftProjection {
                DSDetailRow("Draft Projection", "Round \(proj)", tint: projectionColor(proj))
                // Rookie money for that slot, at the club's real cap.
                DSDetailRow("Est. Rookie Deal", rookieContractEstimate(round: proj), tint: .textSecondary)
            } else {
                DSDetailRow("Draft Projection", "Unknown", tint: .textTertiaryReadable, weight: .regular)
            }

            // Mock draft projection
            if let mockPick = prospect.mockDraftPickNumber,
               let mockTeam = prospect.mockDraftTeam {
                DSDetailRow("Mock Draft", "Rd1 Pick #\(mockPick) — \(mockTeam)", tint: .accentGold)
            }

            DSDetailRow(label: "Team Interest") {
                InterestBadge(level: prospect.interestLevel)
            }
        }
    }

    /// The one read the retired pick sheet had that this card did not: **is he
    /// worth THIS slot?** (#196b/#197.)
    ///
    /// The sheet printed a value chip on every row and the card printed none,
    /// so moving the commit onto the card would have moved the decision away
    /// from the number it is made against. Same helper the coordinator grades
    /// the finished pick with — `DraftIntel.pickValueDelta` — so the sentence
    /// the user reads before the pick and the grade he is given after it cannot
    /// disagree.
    ///
    /// Deliberately the VALUE read only, not the sheet's full STEAL/HOF-TRACK
    /// chip: that one takes a team-need score and a scheme fit the card has no
    /// access to, and a grade computed from defaults would be a fabrication
    /// dressed as intel.
    @ViewBuilder
    private var onTheClockValueRow: some View {
        if let pick = draftContext?.pickNumber {
            let delta = DraftIntel.pickValueDelta(
                for: prospect,
                pickNumber: pick,
                consensusRank: DraftIntel.consensusRank(for: prospect.id)
            )
            DSDetailRow(
                "At Your Pick #\(pick)",
                pickValueLabel(delta),
                tint: pickValueTint(delta)
            )
        }
    }

    /// Positive is value (the board had him gone by now), negative is a reach.
    /// The ±4 dead band is the same one the war room's row chips used.
    private func pickValueLabel(_ delta: Int) -> String {
        if delta >= 4 { return "Value \u{00B7} +\(delta) vs the board" }
        if delta <= -4 { return "Reach \u{00B7} \(delta) vs the board" }
        return "Fair value at this slot"
    }

    private func pickValueTint(_ delta: Int) -> Color {
        if delta >= 4 { return .draftStealGold }
        if delta <= -4 { return .warning }
        return .textSecondary
    }

    // MARK: - Actions Section

    /// The priced, rationed replacement for the old free "Send Scout to
    /// Evaluate" row. Always rendered, never silently missing: a blocked
    /// evaluation states its price, its slot count or its reason.
    @ViewBuilder
    private var evaluationRow: some View {
        let availability = evaluationAvailability
        // "Film study" is what the wizard stage, the required task and the
        // TAPE column all call this — the row used to say "Send Scout to
        // Evaluate" and the user could not find where film study was done.
        let title = isScouted
            ? "Order Another Report (\(currentScoutingPhase.displayName))"
            : "Order Film Study"

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
                Text("\(ScoutEvaluationBudget.chargeableReports(prospect))/\(ScoutEvaluationBudget.maxReportsPerProspect)")
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

    /// The instrument ledger: every pre-draft tool the spring offers, live or
    /// blocked, each one stating its price or its reason.
    ///
    /// The *live* ones are also on the action bar (§2.5) — deliberately. The
    /// bar is where you spend; this card is where you read what is left and
    /// why the rest is shut.
    private var instrumentsCard: some View {
        DSDetailCard(
            "Instruments",
            icon: "wrench.and.screwdriver",
            explainer: "Film study, an interview and a private workout are the three things you can buy on this man. Each is rationed, and a shut one says what shut it."
        ) {
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

            // "Scouted (N reports)" counts reports THIS regime ordered. Off
            // `scoutingReports.count` it counted the inherited "Previous Staff"
            // freebie too, so a brand new save's top 250 all opened with a green
            // tick and "Scouted (1 report)" against work nobody had done —
            // beside a Film Study pill that correctly read dark.
            let ownReports = ProspectFog.ownReportCount(prospect)
            if ownReports > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.success)
                    Text("Scouted (\(ownReports) report\(ownReports == 1 ? "" : "s"))")
                        .foregroundStyle(Color.success)
                    // R27: attribution + accuracy indicator for the latest report
                    if let scoutedBy = prospect.latestScoutName {
                        Text("\u{00B7} latest by \(scoutedBy)\(prospect.latestReportConfidence.map { " (\(Int($0 * 100))% confidence)" } ?? "")")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                // EVERY report, not just the last one.
                //
                // `ScoutEvaluationBudget.maxReportsPerProspect` is 3 and the
                // card surfaced exactly one: the aggregate count above plus the
                // latest scout's name, with the FILM slot reopening that same
                // single report. Two men in the building can and do come back
                // with different letters on the same prospect — that
                // disagreement is what the second and third report are FOR —
                // and until this block it was data the save carried and no
                // screen ever showed.
                let ledger = ownReportLedger
                if ledger.count > 1 {
                    VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                        ForEach(Array(ledger.enumerated()), id: \.offset) { _, entry in
                            HStack(spacing: 6) {
                                Text(entry.grade)
                                    .font(.system(size: DSType.Size.caption, weight: .heavy))
                                    // The dash is not a grade, so it does not
                                    // get a grade's colour — `Color.forGrade`
                                    // would drop it into F's red.
                                    .foregroundStyle(
                                        entry.grade == "\u{2014}"
                                            ? Color.textTertiary
                                            : Color.forGrade(entry.grade)
                                    )
                                    .frame(width: 26, alignment: .leading)
                                Text(entry.scoutName)
                                    .font(.system(size: DSType.Size.caption))
                                    .foregroundStyle(Color.textSecondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(entry.occasion)
                                    .font(.system(size: DSType.Size.caption))
                                    .foregroundStyle(Color.textTertiaryReadable)
                            }
                        }
                        Text("Your department does not agree with itself for free \u{2014} a wider spread here is why the band above is wide.")
                            .font(.system(size: DSType.Size.caption))
                            .foregroundStyle(Color.textTertiaryReadable)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, 2)
                }
            }
        }
    }

    /// One row per report THIS regime has filed, oldest first.
    ///
    /// The inherited "Previous Staff" baseline is excluded for the same reason
    /// `ownReportCount` excludes it: it is not this building's opinion. A report
    /// with no letter on it (an older save, filed before the grade-based system)
    /// prints an em dash rather than a number reverse-engineered off
    /// `overallGrade`, which is the raw scouted integer the fog exists to hold
    /// back.
    private var ownReportLedger: [(scoutName: String, grade: String, occasion: String)] {
        prospect.scoutingReports
            .filter { $0.scoutName != ProspectFog.inheritedScoutName }
            .map {
                (
                    scoutName: $0.scoutName,
                    grade: $0.overallLetterGrade?.rawValue ?? "\u{2014}",
                    occasion: $0.phase.displayName
                )
            }
    }

    // MARK: - Action Button Bar (#48)

    /// **The one commit surface** (§2.5, P5).
    ///
    /// Was a bespoke `HStack` on `.ultraThinMaterial` with four hand-rolled
    /// 52 pt capsules in two private recipes — the fourth hand-rolled button
    /// style in a file that already had `DSActionBar` available. The set of
    /// actions is unchanged: the mark is still the primary and still a `Menu`,
    /// and one CTA appears per instrument whose window is open right now.
    ///
    /// The bar carries no mark control of its own (#192). It used to host a
    /// floating `Mark` menu in a strip above the commits — a *third* place to
    /// state one opinion, two taps deep, in the corner of the screen furthest
    /// from the man it was about. The tiers are buttons in the hero now
    /// (`heroMarkLane`); what stays here is the STATUS the strip was really
    /// providing — the explainer's `UNMARKED` / `YOUR MARK` rule, which reads
    /// off the same `prospect.userMark` and therefore updates the moment a
    /// header button is tapped.
    @ViewBuilder
    private var prospectActionBar: some View {
        if let draft = draftContext {
            draftActionBar(draft)
        } else {
            springActionBar
        }
    }

    /// **Draft night's bar** (#196b). The card is the room's decision surface
    /// now, so the bar carries the decision:
    ///
    ///   ON THE CLOCK ... the gold `Draft him — Pick #N`. This is the screen's
    ///                    one gold fill; every spring commit is closed tonight
    ///                    (`isLiveDraftCard`), so nothing competes for it.
    ///   OFF THE BOARD .. no primary either, and the reason named: a card left
    ///                    open across the pick that took him would otherwise
    ///                    re-light its gold CTA the moment the user's turn came
    ///                    around and commit a man who is already signed.
    ///   OTHERWISE ...... no primary at all. A gold button on a card opened
    ///                    while another club is at the podium would be a commit
    ///                    the engine refuses — `selectProspect` guards on
    ///                    `isUserOnClock` — i.e. the dead-primary defect §2.5
    ///                    exists to stop.
    ///
    /// `Back to the draft` is a secondary in both stances and is never absent:
    /// a full-screen cover has no swipe-to-dismiss, and the way back is always
    /// the board, never the hub the card is pushed from in the spring.
    private func draftActionBar(_ draft: ProspectDraftContext) -> some View {
        DSActionBar(
            explainer: .init(
                title: draft.unavailableReason != nil
                    ? "Off the board"
                    : draft.pickNumber.map { "You are on the clock \u{2014} #\($0)" }
                        ?? "Draft night",
                message: draft.unavailableReason
                    ?? (draft.pickNumber != nil
                        ? "Hand this card in and **\(prospect.fullName)** is yours. The clock is still running behind this screen."
                        : Self.liveDraftHint),
                isWarning: draft.pickNumber == nil
            ),
            secondary: .init(
                title: "Back to the draft",
                handler: draft.onBack
            ),
            primary: draft.pickNumber.map { pick in
                DSActionBar.Action(
                    title: "Draft him \u{2014} Pick #\(pick)",
                    caption: "\(prospect.position.rawValue) \u{00B7} \(prospect.college)",
                    accessibilityLabel: "Draft \(prospect.fullName) with pick number \(pick)",
                    handler: draft.onDraft
                )
            }
        )
    }

    private var springActionBar: some View {
        DSActionBar(
            explainer: .init(
                title: prospect.isMarked ? "Your mark" : "Unmarked",
                message: markExplainer,
                isWarning: isLiveDraftCard
            ),
            ghost: canWorkout ? .init(title: "Workout", handler: { performWorkout() }) : nil,
            secondary: canInterview ? .init(title: "Interview", handler: { performInterview() }) : nil,
            primary: evaluationAvailability.isAvailable
                ? .init(
                    title: isScouted ? "Order Another Report" : "Order Film Study",
                    caption: evaluationCostCaption,
                    handler: { activeSheet = .sendScout }
                  )
                : nil
        )
    }

    /// What the bar's explainer says. On draft night it is the blocked-commit
    /// form: orange rule, and the reason spelled out (§2.12).
    private var markExplainer: String {
        if isLiveDraftCard { return Self.liveDraftHint }
        if prospect.isMarked {
            return "**\(prospect.userMark.label)** on your board\(prospect.userMarkNote.isEmpty ? "" : " \u{00B7} note attached")."
        }
        return "He is not on your board yet \u{2014} pick a tier in the header. A mark is what the war room sorts by on the clock."
    }

    /// "$450K · 4 of 6 evaluations left" — the two numbers the commit spends,
    /// quoted from the same `ScoutEvaluationBudget` the Instruments card reads
    /// so the bar and the card cannot disagree (§2.13, arithmetic gate).
    private var evaluationCostCaption: String? {
        guard case let .available(cost, slotsLeft) = evaluationAvailability else { return nil }
        return "$\(cost)K \u{00B7} \(slotsLeft) of \(ScoutEvaluationBudget.slotsPerCycle) left"
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

    /// A draft ROUND is a slot, not a rating: there is no 0–99 read to
    /// hand `Color.forRating`, and rounds run the wrong way (1 is best). The
    /// lint pragma is the sanctioned form for exactly this case.
    private func projectionColor(_ round: Int) -> Color { // ds-lint:allow(ratingfn)
        switch round {
        case 1:    return .accentGold
        case 2...3: return .success
        case 4...5: return .warning
        default:   return .textSecondary
        }
    }

    private func detailGradeColor(_ grade: LetterGrade) -> Color {
        Color.forGrade(grade)
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

        // The OTHER way to fill the hole. Scoped to this save (`careerID`) as
        // well as to "unsigned", because `teamID == nil` on its own is every
        // free agent in every career on the device.
        let cid = career.id
        let faDesc = FetchDescriptor<Player>(
            predicate: #Predicate<Player> {
                $0.careerID == cid && $0.teamID == nil && !$0.isRetired
            }
        )
        freeAgentPool = (try? modelContext.fetch(faDesc)) ?? []
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

    /// A combine percentile is a 0–100 read like any other, so it goes
    /// through the shared ladder rather than a sixth bespoke one (§4 wave 4).
    /// The old ladder put 90+ in gold, which is a *fourth* job for the colour
    /// P5 reserves for the primary action.
    private func percentileColor(_ pct: Int) -> Color {
        Color.forRating(pct, scale: .percent)
    }
}

// MARK: - Instrument strip (#180)

/// One pre-draft instrument's reserved slot on the prospect card.
private struct ProspectInstrumentSlot: Identifiable {
    /// The 3-7 character ident the pill prints. Short by contract — §2.2's
    /// worked example is a 87 pt word painted over its neighbour in a 66 pt
    /// column.
    let ident: String
    /// What VoiceOver and the yield line call it.
    let name: String
    /// Has this instrument been run on this man by THIS building?
    let isSet: Bool
    /// What it bought, in four or five words. Only rendered when `isSet`.
    let yield: String?
    /// Reopens what it bought. `nil` for the two instruments that keep no card
    /// of their own — a pro day and a Top-30 visit change what the rest of the
    /// page is allowed to show rather than producing a document.
    let open: (() -> Void)?

    var id: String { ident }
}

/// The reserved row of instrument slots, plus one line naming what the run
/// ones actually bought.
///
/// `DSStatusPill` is deliberately flat and inert in every state — its own
/// documentation says "anything raised is interactive; this never is", after an
/// iteration shipped a static chip and a tappable one that looked identical.
/// So a slot the user can act on is NOT a differently-tinted pill: it is the
/// pill plus a chevron, in a button, and the pill inside it keeps the same
/// vocabulary as the four that do nothing.
private struct ProspectInstrumentStrip: View {
    let slots: [ProspectInstrumentSlot]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Whole pills wrap, never letters. `DSStatusPill` fixes its own
            // horizontal size, so an over-full `HStack` does not compress —
            // it overflows, which is exactly the defect this replaces.
            ViewThatFits(in: .horizontal) {
                strip([slots])
                strip([Array(slots.prefix(3)), Array(slots.dropFirst(3))])
                strip(slots.map { [$0] })
            }

            Text(yieldLine ?? "No instrument has been run on him yet.")
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(yieldLine == nil ? Color.textTertiaryReadable : Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(yieldLine.map { "What your work bought: \($0)" }
                    ?? "No instrument has been run on him yet")
        }
    }

    private func strip(_ rows: [[ProspectInstrumentSlot]]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row) { pill($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func pill(_ slot: ProspectInstrumentSlot) -> some View {
        if slot.isSet, let open = slot.open {
            Button(action: open) {
                HStack(spacing: 2) {
                    DSStatusPill(label: slot.ident, tone: .ok, showsDot: false)
                    Image(systemName: "chevron.right")
                        .font(.system(size: DSType.Size.micro, weight: .heavy))
                        .foregroundStyle(Color.success)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(slot.name), done\(slot.yield.map { ", \($0)" } ?? "")")
            .accessibilityHint("Opens what it bought")
        } else {
            DSStatusPill(
                label: slot.ident,
                tone: slot.isSet ? .ok : .empty,
                showsDot: false,
                spokenLabel: slot.isSet
                    ? "\(slot.name), done\(slot.yield.map { ", \($0)" } ?? "")"
                    : "\(slot.name), not done"
            )
        }
    }

    /// "FILM 2 reports → 12 bands · MEET IQ 84 + personality". The idents
    /// repeat so the line reads against the strip above it rather than asking
    /// the user to hold five positions in his head.
    private var yieldLine: String? {
        let parts = slots.compactMap { slot -> String? in
            guard slot.isSet, let yield = slot.yield else { return nil }
            return "\(slot.ident) \(yield)"
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  \u{00B7}  ")
    }
}

// MARK: - Workout record sheet

/// The private-workout session, reopened from the WORK slot.
///
/// Renders through `WorkoutBatchReportView` in its saved-report mode — the same
/// card the workouts tab prints for a session filed earlier this cycle, so one
/// workout reads the same wherever the user opens it. `isSavedReport` is what
/// suppresses the before → after grade row: the pre-workout band is not stored.
private struct ProspectWorkoutRecordSheet: View {
    let entry: WorkoutReportEntry
    let staffName: String
    let occasion: String
    let slotsUsed: Int
    let slotsLeft: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                WorkoutBatchReportView(
                    batch: WorkoutBatch(
                        entries: [entry],
                        staffName: staffName,
                        occasion: occasion,
                        slotsUsed: slotsUsed,
                        slotsLeft: slotsLeft
                    ),
                    isSavedReport: true
                )
            }
            .navigationTitle(entry.prospectName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
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
    /// Called with the spend and what it bought, so the card can charge the
    /// ledger and then show the result the way the interview does (#117).
    let onFiled: (Int, ProspectDetailView.FilmStudyOutcome) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                if scouts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: DSType.Size.hero))
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
        guard ScoutEvaluationBudget.chargeableReports(prospect) < ScoutEvaluationBudget.maxReportsPerProspect,
              slotsLeft > 0,
              budgetRemaining >= cost else {
            dismiss()
            return
        }
        // Band before/after around the apply, so the result sheet can show
        // what the order actually bought (#117) — same shape as the workout.
        let before = prospect.effectiveOverallGrade
        let report = ScoutingEngine.generateScoutReport(
            scout: scout,
            prospect: prospect,
            phase: scoutingPhase
        )
        ScoutingEngine.applyReport(report: report, to: prospect)
        let outcome = ProspectDetailView.FilmStudyOutcome(
            report: report,
            gradeBefore: before,
            gradeAfter: prospect.effectiveOverallGrade
        )
        onFiled(cost, outcome)
        dismiss()
    }
}

// MARK: - Film Study Result Sheet (#117)

/// What the report said, shown the moment it is filed — the interview and the
/// workout both end in a result sheet, and film study ended in a silent
/// dismiss that left the user hunting the card for what changed.
private struct FilmStudyResultSheet: View {
    let outcome: ProspectDetailView.FilmStudyOutcome
    let prospect: CollegeProspect
    let slotsLeft: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()
                List {
                    filedBySection
                    gradeSection
                    if let strengths = nonEmpty(outcome.report.strengthNotes) {
                        readSection(title: "What the tape showed", body: strengths)
                    }
                    if let weaknesses = nonEmpty(outcome.report.weaknessNotes) {
                        readSection(title: "Where he gets beaten", body: weaknesses)
                    }
                    if let personality = nonEmpty(outcome.report.personalityNotes) {
                        readSection(title: "The person", body: personality)
                    }
                    slotSection
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle(prospect.fullName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var filedBySection: some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(Color.accentGold)
                Text("Report filed by \(outcome.report.scoutName) \u{00B7} \(Int(outcome.report.confidenceLevel * 100))% confidence")
                    .font(.subheadline)
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private var gradeSection: some View {
        Section {
            HStack(spacing: 14) {
                gradeColumn("Before", text: outcome.gradeBefore?.displayText ?? "\u{2014}", tint: .textTertiary)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                gradeColumn("After", text: outcome.gradeAfter?.displayText ?? "\u{2014}", tint: .accentGold)
                Spacer()
            }
            .padding(.vertical, 4)
        } header: {
            Text("Grade band")
        } footer: {
            Text("A filed report grades all eight mental bands and every \(prospect.position.rawValue) skill \u{2014} the card below is already updated.")
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

    private var slotSection: some View {
        Section {
            HStack {
                Text("Reports on file")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text("\(ScoutEvaluationBudget.chargeableReports(prospect))/\(ScoutEvaluationBudget.maxReportsPerProspect) \u{00B7} \(slotsLeft) evaluation\(slotsLeft == 1 ? "" : "s") left this cycle")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .listRowBackground(Color.backgroundSecondary)
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
