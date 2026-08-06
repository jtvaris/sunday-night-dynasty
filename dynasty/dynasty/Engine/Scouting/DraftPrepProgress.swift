import Foundation

// MARK: - Draft Prep Progress (#104)

/// The single authority on **how far through each pre-draft stage this club is**.
///
/// One struct, built once per screen refresh, that answers the three questions
/// the process view, the task list and the stage banners were each answering
/// separately (and disagreeing about):
///
/// 1. **How much is done in this stage?** `done` / `total`, in the stage's own
///    unit — 12/60 interviews, 6/25 reports, 4/25 focus slots, 2/30 workouts.
/// 2. **Is the stage's required task satisfied?** `isSatisfied`, which is the
///    ONE predicate the required-task chain, the stage's READY chip and the
///    advance button all read. Before this, `ScoutingStageGate.make` held one
///    copy and `CareerShellView`'s completion switch held another, keyed off
///    different state — which is how "Send Scouts to Combine — Required" stayed
///    red forever while the department was standing in Indianapolis.
/// 3. **Can the club act in this stage right now?** `unlocked`, which is
///    calendar AND pipeline: a stage in a phase the season has not reached is
///    shut, and so is a stage beyond the club's reach — but an EARLIER stage is
///    never shut. That last clause is the film-study bug: the old
///    `isStageClosed: prepStep.order > filmStudy.order` disabled every order
///    button the moment the phase floor moved the club to `.proDayFocus`, which
///    for an in-flight save happened before the stage had ever been openable.
///
/// ## Reach — why the next stage opens on its own
///
/// `reach` is the club's stage **plus one when that stage is satisfied**. Doing
/// the work opens the next room; the explicit Advance button is for *skipping*,
/// not for progressing. The old shape made the advance button the only door, it
/// lived in a scroll-away header, and a user who never found it could not reach
/// the interviews surface a REQUIRED task was pointing him at.
///
/// The pipeline then closes the loop by itself: acting in the newly-opened
/// stage moves `Career.prepStep`'s evidence floor onto it, so the stage machine
/// follows the user rather than the other way round.
struct DraftPrepProgress {

    // MARK: - Rations
    //
    // The cycle allowances, declared once. Four screens each carried their own
    // `private let maxInterviews = 60`.

    /// Interview slots per draft cycle (`career.interviewsUsed`).
    static let interviewSlots = 60
    /// Private workout slots per cycle (`career.workoutsUsed`).
    static let workoutSlots = 30
    /// Top-30 facility visits per cycle (`career.top30VisitsUsed`).
    static let top30Slots = 30
    /// Reports the film-study stage wants filed before it counts as *worked*
    /// rather than skipped. The stage's budget is `ScoutEvaluationBudget
    /// .slotsPerCycle`; this is the bar, not the cap.
    static let filmStudyThreshold = 8

    // MARK: - Scoped keys
    //
    // Every career-scoped key the prep reads, named ONCE. A required task that
    // is completed from key A while the screen writes key B is the bug class
    // this block exists to close.

    enum Key {
        /// Set when the department's combine trip is bought and sent.
        static let scoutsSentToCombine = "scoutsSentToCombine"
        /// Set when the user opens the Combine tab on a class that has numbers.
        static let combineResultsReviewed = "combineResultsReviewed"
        /// Set when the post-interview report sheet has been read.
        static let interviewReportReviewed = "interviewReportReviewed"
        /// Evaluation ledger (`ScoutEvaluationBudget`), cycle-stamped.
        static let evaluationsUsed = "scoutEvaluationsUsed"
        static let evaluationCycle = "scoutEvaluationCycle"
        /// Season stamp for "Mock 1.0 has been read". Season-stamped rather than
        /// boolean so it resets with the cycle and needs no hook.
        static let mockOneRead = "draftPrepMockOneRead"
        /// Season stamp for "the final mock has been read".
        static let mockTwoRead = "draftPrepFinalMockRead"
    }

    // MARK: - Per-stage row

    struct Stage: Identifiable, Equatable {
        let step: DraftPrepStep
        /// Units of work completed in this stage's own currency.
        let done: Int
        /// The stage's ration. `1` for the stages that are a read, not a spend.
        let total: Int
        /// `true` when the club may act in this stage right now.
        let unlocked: Bool
        /// `true` when the SEASON is what shuts this stage: the phase it belongs
        /// to has not arrived, so no amount of work opens it and nothing on its
        /// screen can be acted on.
        ///
        /// The distinction the presentation needs and `unlocked` alone cannot
        /// make. A pipeline-locked stage is a room you have not walked into yet
        /// — finish the one in front of you and it opens. A calendar-locked
        /// stage is a room that does not exist this week, and the events it
        /// reads from (the combine, the mocks) are LEAGUE events run by the
        /// phase hook, not by a button anywhere on this screen. Drawing the two
        /// the same way is #107: a February hub telling a club to go read
        /// numbers from a combine that has not been held.
        let isCalendarLocked: Bool
        /// `true` when the stage's required task is satisfied.
        let isSatisfied: Bool
        /// `false` for the read-only stages (combine review, the two mocks,
        /// ready) whose "counter" is a yes/no, so the process view can draw a
        /// tick instead of "1/1".
        let isCounted: Bool
        /// Plural noun for the counter: "interviews", "reports", "slots".
        let unit: String
        /// Why the stage is shut, when it is. `nil` while unlocked.
        let lockReason: String?

        var id: String { step.rawValue }

        /// "30/60 interviews" — the process view's stage-tab counter.
        ///
        /// A stage the season has not reached says WHEN it opens instead. Its
        /// counter is not the useful thing to say about it: "Not read" is a
        /// chore the user is being told he is failing at, over a combine that
        /// nobody has held yet, with no control anywhere that holds it. Work
        /// already banked still reads as done — a tick is a claim about work,
        /// and the work happened.
        var counter: String {
            if isCalendarLocked && !isSatisfied { return waitLabel }
            return isCounted ? "\(done)/\(total) \(unit)" : (isSatisfied ? "Done" : "Not read")
        }

        /// "Combine week" — WHEN a calendar-locked stage opens, in place of a
        /// counter, short enough for the process bar's 92 pt cell.
        ///
        /// Two rules, both learned from a shipped build:
        ///
        /// * **It names the phase that has to pass, not the stage.** "Opens at
        ///   pro days" over the pro-day cell said only that the pro days open
        ///   when the pro days open. The fact a user in combine week actually
        ///   needs is that FREE AGENCY comes first — `prepCalendarRank` is
        ///   combine 1, free agency 2, pro days 3, so the circuit is two phase
        ///   advances away, not one (#123).
        /// * **It fits the cell.** The bar draws this at micro size under
        ///   `lineLimit(1)` + `minimumScaleFactor(0.75)`, so past ~14 characters
        ///   it shrinks to unreadable. The sentence version lives in
        ///   ``lockReason`` / ``DraftPrepProgress/opensSentence(for:)``, which
        ///   the stage explainer has room for.
        ///
        /// One table, read by both the bar's sub-label and ``counter``, so the
        /// strip and the Draft Prep card cannot describe the same wait with two
        /// different sentences.
        var waitLabel: String {
            switch step.phase {
            case .combine:  return "Combine week"
            case .proDays:  return "After FA"
            case .draft:    return "Draft week"
            default:        return "Not scheduled"
            }
        }

        /// 0…1 for a progress bar. A satisfied uncounted stage reads full.
        var fraction: Double {
            guard isCounted else { return isSatisfied ? 1 : 0 }
            guard total > 0 else { return 0 }
            return min(1, Double(done) / Double(total))
        }
    }

    // MARK: - State

    /// The stage the club is standing in (`Career.prepStep`).
    let current: DraftPrepStep
    /// The furthest stage the club may work in — `current`, plus one when
    /// `current` is satisfied and the calendar allows it.
    let reach: DraftPrepStep
    /// Every stage, in pipeline order.
    let stages: [Stage]

    // MARK: - Build

    /// - Parameters:
    ///   - career: the open save. Supplies the stage, the phase and the three
    ///     per-cycle counters.
    ///   - prospects: this cycle's class — used to prove the combine was
    ///     actually held before its review can be called done.
    ///   - scouts: the department. Supplies the pro-day focus-slot ledger
    ///     (`scout.proDayColleges` reservations against `scout.maxProDays`).
    init(career: Career, prospects: [CollegeProspect], scouts: [Scout]) {
        let step = career.prepStep
        let phase = career.currentPhase
        let season = career.currentSeason

        // --- Raw counters -------------------------------------------------

        let combineHeld = prospects.contains { $0.fortyTime != nil }
        let combineReviewed = CareerScopedDefaults.bool(Key.combineResultsReviewed) && combineHeld
        let interviewsDone = max(0, career.interviewsUsed)
        let reportsFiled = DraftPrepProgress.filmReportsFiled(career: career)
        let slotsReserved = scouts.reduce(0) { $0 + $1.proDayColleges.count }
        let slotsTotal = scouts.reduce(0) { $0 + $1.maxProDays }
        let workoutsDone = max(0, career.workoutsUsed)
        let visitsDone = max(0, career.top30VisitsUsed)
        let mockOneRead = (CareerScopedDefaults.value(Key.mockOneRead) as Int?) == season
        let mockTwoRead = (CareerScopedDefaults.value(Key.mockTwoRead) as Int?) == season

        func satisfied(_ s: DraftPrepStep) -> Bool {
            switch s {
            case .combineReview: return combineReviewed
            case .interviews:    return interviewsDone > 0
            case .filmStudy:     return reportsFiled >= DraftPrepProgress.filmStudyThreshold
            case .proDayFocus:   return slotsReserved > 0
            case .workouts:      return workoutsDone > 0
            case .mockOne:       return mockOneRead
            case .top30Visits:   return visitsDone > 0
            case .mockTwo:       return mockTwoRead
            case .ready:         return phase == .draft
            }
        }

        // --- Reach --------------------------------------------------------
        //
        // The next stage opens as soon as this one is satisfied, but never
        // across a phase boundary the season has not crossed.
        let calendarRank = phase.prepCalendarRank
        let reached: DraftPrepStep = {
            guard satisfied(step), let next = step.next else { return step }
            guard next.phase.prepCalendarRank <= calendarRank else { return step }
            return next
        }()

        self.current = step
        self.reach = reached
        self.stages = DraftPrepStep.allCases
            .sorted { $0.order < $1.order }
            .map { s in
                let calendarOpen = calendarRank > 0 && s.phase.prepCalendarRank <= calendarRank
                let pipelineOpen = s.order <= reached.order
                let unlocked = calendarOpen && pipelineOpen
                let lockReason: String? = {
                    if unlocked { return nil }
                    if !calendarOpen {
                        // Outside the four pre-draft phases the pipeline has not
                        // started AT ALL, and that is a different sentence from
                        // "the next room is not open yet" — see
                        // ``calendarClosedReason``.
                        if calendarRank == 0 {
                            return DraftPrepProgress.calendarClosedReason(for: s)
                        }
                        return DraftPrepProgress.opensSentence(for: s)
                    }
                    guard let previous = s.previous else { return "Not open yet." }
                    return "Finish or skip \(previous.displayName) first."
                }()

                let done: Int, total: Int, counted: Bool, unit: String
                switch s {
                case .combineReview:
                    done = combineReviewed ? 1 : 0; total = 1; counted = false; unit = "read"
                case .interviews:
                    done = interviewsDone
                    total = DraftPrepProgress.interviewSlots
                    counted = true; unit = "interviews"
                case .filmStudy:
                    done = reportsFiled
                    total = ScoutEvaluationBudget.slotsPerCycle
                    counted = true; unit = "reports"
                case .proDayFocus:
                    done = slotsReserved; total = slotsTotal; counted = true; unit = "focus slots"
                case .workouts:
                    done = workoutsDone
                    total = DraftPrepProgress.workoutSlots
                    counted = true; unit = "workouts"
                case .mockOne:
                    done = mockOneRead ? 1 : 0; total = 1; counted = false; unit = "read"
                case .top30Visits:
                    done = visitsDone
                    total = DraftPrepProgress.top30Slots
                    counted = true; unit = "visits"
                case .mockTwo:
                    done = mockTwoRead ? 1 : 0; total = 1; counted = false; unit = "read"
                case .ready:
                    done = phase == .draft ? 1 : 0; total = 1; counted = false; unit = "open"
                }

                return Stage(
                    step: s,
                    done: done,
                    total: total,
                    unlocked: unlocked,
                    isCalendarLocked: !calendarOpen,
                    isSatisfied: satisfied(s),
                    isCounted: counted,
                    unit: unit,
                    lockReason: lockReason
                )
            }
    }

    // MARK: - Calendar copy

    /// What a stage says when the pre-draft calendar has not opened AT ALL —
    /// `prepCalendarRank == 0`, i.e. a February career or any week of the
    /// autumn.
    ///
    /// Kept apart from the in-window sentences because the situation differs in
    /// kind. In combine week "The pro-day circuit opens after free agency." is a
    /// note about a room further down the corridor, and the club is standing in
    /// one. Outside the window the club is between nothing: the building is
    /// shut, and the events these stages read from are league events the phase
    /// hook runs on its own.
    ///
    /// So the copy has to do two jobs the old one-clause version did neither of:
    /// say that the event has not happened, and say that nothing on this screen
    /// makes it happen — advance the calendar. #107 is a user reading "Read
    /// Indianapolis before you spend a dollar" over "0 of 0 prospects invited",
    /// hunting for the control that sends them.
    static func calendarClosedReason(for step: DraftPrepStep) -> String {
        switch step {
        case .combineReview:
            return "The combine has not been held yet \u{2014} it runs automatically when the Combine phase begins. Advance the calendar to get there."
        case .interviews, .filmStudy:
            return "The pre-draft window has not opened. This stage starts in combine week \u{2014} advance the calendar to get there."
        case .proDayFocus, .workouts, .mockOne, .top30Visits, .mockTwo:
            return "The pre-draft window has not opened. The pro-day circuit opens after free agency \u{2014} advance the calendar to get there."
        case .ready:
            return "The draft room opens in draft week."
        }
    }

    /// **WHEN a stage's phase arrives, in one sentence.** The one place the app
    /// is allowed to answer "why is this shut?" with a date.
    ///
    /// The pro-day answer is the whole point of this table. Every surface used
    /// to say some version of *"after the combine"* / *"when the pro-day circuit
    /// does"*, and both are useless to the user standing in combine week: free
    /// agency runs between the two (`SeasonPhase.prepCalendarRank` — combine 1,
    /// free agency 2, pro days 3), so a club that advances once lands in the
    /// market with the circuit still bolted shut. Naming free agency is the only
    /// version of the sentence that tells him how far away it is (#123).
    static func opensSentence(for step: DraftPrepStep) -> String {
        switch step.phase {
        case .combine:  return "Opens at the combine."
        case .proDays:  return "The pro-day circuit opens after free agency."
        case .draft:    return "The draft room opens in draft week."
        default:        return "Not yet on the calendar."
        }
    }

    /// The sentence a stage SCREEN prints over its lock — the pro-day tour, the
    /// workout room, the visit book.
    ///
    /// Built from the two facts every stage screen already has to hand (the
    /// club's phase and the stage it is standing in) and from the same table the
    /// process bar reads, so the strip, the explainer and the locked screen
    /// cannot tell three stories about one wait.
    ///
    /// The two locks get different sentences because they ask for different
    /// things. A CALENDAR lock is a phase the user has to advance out of, so it
    /// names the phase he is in — printing his prep STAGE there is what shipped,
    /// and "You are at: Film Study" over a pro-day screen answers a question
    /// nobody asked. A PIPELINE lock is a stage in front of him, so it names
    /// that instead: the calendar has nothing left to say about it.
    static func screenLockMessage(
        for step: DraftPrepStep,
        phase: SeasonPhase,
        current: DraftPrepStep
    ) -> String {
        // #fleet review F10: outside the four pre-draft phases entirely, the
        // in-window sentence is wrong in kind — "opens after free agency" over a
        // week-12 screen names a phase that is a whole calendar away, while the
        // stage explainer beside it (built from ``calendarClosedReason``) says
        // the window has not opened at all. Same table, same answer, both places.
        if phase.prepCalendarRank == 0 {
            return "\(calendarClosedReason(for: step)) You are at: \(phase.displayName)."
        }
        let calendarLocked = phase.prepCalendarRank < step.phase.prepCalendarRank
        guard calendarLocked else {
            return "You are at: \(current.displayName) \u{2014} finish or skip it and this opens."
        }
        return "\(opensSentence(for: step)) You are at: \(phase.displayName)."
    }

    // MARK: - Lookup

    subscript(step: DraftPrepStep) -> Stage {
        stages.first { $0.step == step }
            // `stages` is built from `allCases`, so this is unreachable; the
            // fallback exists so no call site has to unwrap.
            ?? Stage(step: step, done: 0, total: 1, unlocked: false,
                     isCalendarLocked: false, isSatisfied: false,
                     isCounted: false, unit: "", lockReason: "Not open yet.")
    }

    /// The stage's counter as a bare tuple, or `nil` for the stages whose
    /// progress is a read rather than a spend (`isCounted == false`).
    ///
    /// The one call the process bar and the stage explainers make, so both draw
    /// the same "12/60 interviews" from the same arithmetic.
    func count(for step: DraftPrepStep) -> (done: Int, total: Int, unit: String)? {
        let row = self[step]
        guard row.isCounted else { return nil }
        return (row.done, row.total, row.unit)
    }

    /// The stage row a ``GameTask`` belongs to, matched on `GameTask.matchKey`.
    func stage(forTaskKey key: String) -> Stage? {
        DraftPrepStep.stage(forTaskKey: key).map { self[$0] }
    }

    /// **The one gate every stage screen asks.** `true` when the club may spend
    /// this stage's currency right now.
    ///
    /// It is exactly ``Stage/unlocked`` — deliberately, and the whole of the
    /// original bug report lives in that word "exactly":
    ///
    /// * an EARLIER stage stays actionable. `prepStep` is a floor over the
    ///   phase, so a save that walked into `.proDays` was jumped to
    ///   `.proDayFocus` and every combine screen behind it went read-only. That
    ///   is B3 verbatim — "film study could not be assigned to anyone" — and
    ///   the rations are per-cycle counters, so nothing needs a stage to police
    ///   them: running out of interview slots is the limit, not the calendar.
    /// * the NEXT stage is actionable the moment this one is satisfied
    ///   (``reach``), so the encouraging `.open` cell in the process bar leads
    ///   to a screen whose buttons work. Drawing an open stage over a dead
    ///   screen is the same bug with better typography.
    ///
    /// Acting in an open stage can never skip unworked work: `reach` only moves
    /// past `current` when `current` is satisfied.
    func canAct(_ step: DraftPrepStep) -> Bool { self[step].unlocked }

    /// **The required-task authority.** `true` when the action a stage's task
    /// asks for has actually been performed.
    func isSatisfied(taskKey: String) -> Bool {
        stage(forTaskKey: taskKey)?.isSatisfied ?? false
    }

    /// Stages whose work is behind the club — the "4 of 9 done" headline.
    var satisfiedStageCount: Int { stages.filter(\.isSatisfied).count }

    /// "Interviews — 30/60 interviews", for the process view's current-stage line.
    var headline: String {
        let row = self[current]
        return "\(current.displayName) \u{2014} \(row.counter)"
    }

    // MARK: - Shared reads

    /// Film-study reports filed **this cycle**.
    ///
    /// The ledger is `ScoutEvaluationBudget`'s: film study does not have a
    /// currency of its own, it spends evaluation slots. Read through
    /// `thisCycle` so a stamp from an earlier draft reads as zero — the same
    /// trick `Career.prepStep` uses, and the reason there is no reset hook.
    static func filmReportsFiled(career: Career) -> Int {
        ScoutEvaluationBudget.thisCycle(
            CareerScopedDefaults.value(Key.evaluationsUsed) ?? 0,
            stampedSeason: CareerScopedDefaults.value(Key.evaluationCycle) ?? 0,
            currentSeason: career.currentSeason
        )
    }
}
