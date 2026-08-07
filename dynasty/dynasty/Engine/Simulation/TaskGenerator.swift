import Foundation

// MARK: - Game Task Model

/// A single actionable task displayed in the Calendar sidebar.
struct GameTask: Identifiable, Codable, Equatable {
    let id: UUID
    let phase: SeasonPhase
    /// Mutable so a live counter can be re-stamped in place ("… (12/60
    /// interviews)"). The list is only rebuilt on a PHASE change, so a title
    /// frozen at generation time meant the draft-prep counters in the left bar
    /// stopped moving the moment the user did any work. `matchKey` strips the
    /// suffix, so nothing that keys off a task is affected.
    var title: String
    let description: String
    let icon: String          // SF Symbol name
    let destination: TaskDestination
    let isRequired: Bool
    var status: TaskStatus
    let weekAvailable: Int?   // nil = available entire phase

    /// `true` when **opening the task's screen is the work** — "Check Salary Cap
    /// Outlook", "Review Position Group Grades", "Review Pro Day results".
    ///
    /// Declared on the task rather than inferred by the shell, because it is the
    /// generator that knows whether a row is asking for a decision or for a
    /// read. Before this, a visit only ever produced `.inProgress`, and the two
    /// halves of the app disagreed about what that meant: the advance gate
    /// treated it as satisfied while the row went on drawing the red "Required"
    /// pill and the rail counter went on excluding it (#138b). A read task now
    /// goes straight to `.done` on the visit — one state, one predicate, one
    /// thing the user sees.
    let completesOnVisit: Bool

    init(
        phase: SeasonPhase,
        title: String,
        description: String,
        icon: String,
        destination: TaskDestination,
        isRequired: Bool,
        status: TaskStatus = .todo,
        weekAvailable: Int? = nil,
        completesOnVisit: Bool = false
    ) {
        self.id = UUID()
        self.phase = phase
        self.title = title
        self.description = description
        self.icon = icon
        self.destination = destination
        self.isRequired = isRequired
        self.status = status
        self.weekAvailable = weekAvailable
        self.completesOnVisit = completesOnVisit
    }
}

enum TaskStatus: String, Codable {
    case todo
    case inProgress
    case done
}

// MARK: - Durable Task Progress (#138a)

/// The one part of a task's state **nothing in the game world can re-derive**:
/// that the user opened the screen the task pointed him at.
///
/// Every other completion in `CareerShellView.refreshTaskCompletionStatus` is
/// read back out of the save — a coach exists, a depth chart was written, the
/// franchise tag is on a player — so it survives a cold launch for free. A view
/// visit leaves no such trace. It lived only in the shell's `@State` task array,
/// which dies with the process, so quitting the app rolled "Check Salary Cap
/// Outlook", "Review Position Group Grades" and "Analyze Contract Situations"
/// back to untouched, dropped the rail counter and re-locked the phase advance
/// behind tasks the user had already done — while "Franchise Tag Decisions",
/// whose screen writes a scoped default, came back ticked.
///
/// Three properties, each of them a bug this codebase has already shipped once:
///
/// * **Career-scoped.** Written through `CareerScopedDefaults`, so a second save
///   cannot inherit the first one's ticked boxes, and deleting a save purges
///   them — the key is on `CareerScopedDefaults.keys`.
/// * **Cycle-stamped** with `season | phase | week`. Season 2's Review Roster
///   opens as untouched as season 1's did, and each regular-season week gets its
///   own row rather than inheriting Week 1's game plan.
/// * **Self-pruning.** Every write drops the cycles from earlier seasons, so a
///   thirty-season save does not carry thirty seasons of ticks.
enum TaskProgressStore {

    /// Unsuffixed key, as listed in `CareerScopedDefaults.keys`.
    static let defaultsKey = "taskProgress"

    // MARK: Cycle identity

    /// `"2027|reviewRoster|22"` — the identity of one pass through one phase.
    ///
    /// The week is part of it because `WeekAdvancer` only moves `currentWeek`
    /// inside the regular season and the playoffs; every offseason phase holds
    /// it still. So the stamp is stable exactly where a phase is one visit and
    /// changes exactly where the phase repeats itself week after week.
    static func cycle(season: Int, phase: SeasonPhase, week: Int) -> String {
        "\(season)|\(phase.rawValue)|\(week)"
    }

    static func cycle(for career: Career) -> String {
        cycle(season: career.currentSeason, phase: career.currentPhase, week: career.currentWeek)
    }

    // MARK: Read

    /// Statuses recorded for `cycle`, keyed by ``GameTask/matchKey``.
    static func statuses(in cycle: String) -> [String: TaskStatus] {
        (load()[cycle] ?? [:]).compactMapValues(TaskStatus.init(rawValue:))
    }

    // MARK: Write

    /// Files `statuses` against `cycle`, keeping only the open season's rows.
    ///
    /// **Never lowers a recorded status and never writes when nothing moved.**
    /// The call sites are `onAppear` handlers and the completion refresh, which
    /// run on every navigation; `CareerScopedDefaults.set` republishes to every
    /// view holding a scoped key, so a write per refresh would be a re-render
    /// per refresh.
    static func merge(_ statuses: [String: TaskStatus], in cycle: String, season: Int) {
        guard !statuses.isEmpty else { return }
        var all = load()
        var row = all[cycle] ?? [:]
        var changed = false
        for (key, status) in statuses {
            let existing = row[key].flatMap(TaskStatus.init(rawValue:))
            guard rank(status) > rank(existing) else { continue }
            row[key] = status.rawValue
            changed = true
        }
        guard changed else { return }
        all[cycle] = row
        // Anything stamped with another season is a concluded cycle.
        let prefix = "\(season)|"
        let pruned = all.filter { $0.key.hasPrefix(prefix) }
        save(pruned)
    }

    /// Files a single task's status. Convenience over ``merge(_:in:season:)``.
    static func record(_ status: TaskStatus, for matchKey: String, in cycle: String, season: Int) {
        merge([matchKey: status], in: cycle, season: season)
    }

    // MARK: Storage

    private static func rank(_ status: TaskStatus?) -> Int {
        switch status {
        case .none:       return 0
        case .todo:       return 1
        case .inProgress: return 2
        case .done:       return 3
        }
    }

    private static func load() -> [String: [String: String]] {
        guard let raw = CareerScopedDefaults.string(defaultsKey),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: Data(raw.utf8))
        else { return [:] }
        return decoded
    }

    private static func save(_ value: [String: [String: String]]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        CareerScopedDefaults.set(String(decoding: data, as: UTF8.self), defaultsKey)
    }
}

enum TaskDestination: String, Codable, CaseIterable {
    case roster
    case depthChart
    case gamePlan
    case schedule
    case standings
    case coachingStaff
    /// #162: the Coaching Changes staff read, landing on `CoachingStaffView`'s
    /// **Review** tab — the surface that actually carries the evaluation (staff
    /// overview, budget summary, every coach's overall, readiness check). The
    /// Staff tab is where a GM *changes* the staff; Review is where he reads it.
    case coachingStaffReview
    /// #162: the Coaching Changes scheme read, landing on the **Schemes** tab —
    /// the offensive/defensive scheme cards, the family trees and the two roster
    /// fit tables the task's own copy describes.
    ///
    /// Both of these open the same shell destination as `.coachingStaff`; they
    /// exist as separate cases because the destination is the ONLY thing the
    /// rail hands the shell, so tab-accurate routing has nowhere else to live.
    case coordinatorSchemes
    case hireCoach
    case hireHC
    case hireOC
    case hireDC
    case scouting
    case prospectList
    case bigBoard
    case capOverview
    case freeAgency
    case contractTimeline
    case draft
    case mentoring
    case trades
    case news
    case ownerMeeting
    case lockerRoom
    case inbox
    case rosterEvaluation
    case franchiseTag
    case interviewReport
    case personalWorkouts
    case developmentReport
    // MARK: Draft-prep stages (#103)
    /// TAPE — order film study on the board (spends evaluation slots).
    case filmStudy
    /// Choose the pro-day schools the department travels to.
    case proDayTour
    /// Private workouts with the coaching staff.
    case workouts
    /// Pre-draft facility visits.
    case top30Visits
    /// The mock-draft screen, as a league information event.
    case mockDraft
    /// #128: the draft class by position — declarations, the Senior Bowl, and
    /// how deep the DECLARED pool is at each group against the club's own holes.
    /// The January "read the reports" task used to point at `.scouting`, which
    /// opened the hub on the combine tab — a screen that in `.reviewRoster` reads
    /// "0 of 0 prospects invited" because the league has not issued an invite
    /// list yet and cannot have.
    case classDepth
    /// R32: League History & Hall of Fame screen.
    case history
    /// #40: Draft Report Card — hindsight draft-class grades.
    case draftReportCard
    // Camp destinations
    case trainingPlan
    case workloadDashboard
    case rosterCuts
    case gameWeekPrep
}

// MARK: - Task Generator

/// Stateless factory that produces phase-appropriate tasks based on career
/// and team state.
enum TaskGenerator {

    // MARK: - Phase Metadata

    struct PhaseInfo {
        let name: String
        let description: String
        let order: Int          // 1-based position in the season cycle
    }

    static let totalPhases = 15

    /// Regular-season week in which the college class first exists.
    /// `WeekAdvancer.advanceRegularSeasonWeek` generates and persists it here,
    /// alongside the midseason mock draft — nothing scouting-related can be
    /// shown to the user before it.
    static let draftClassOnBoardWeek = 9

    static func phaseInfo(for phase: SeasonPhase) -> PhaseInfo {
        switch phase {
        case .proBowl:
            return PhaseInfo(
                name: "Pro Bowl",
                description: "All-star festivities and end-of-season recognition.",
                order: 1
            )
        case .superBowl:
            return PhaseInfo(
                name: "Super Bowl",
                description: "The championship game caps off the season. Review results and league awards.",
                order: 2
            )
        case .coachingChanges:
            return PhaseInfo(
                name: "Coaching Changes",
                description: "Evaluate your coaching staff and fill any vacancies before the offseason ramps up.",
                order: 3
            )
        case .reviewRoster:
            return PhaseInfo(
                name: "Review Roster",
                description: "Evaluate your roster, apply franchise tags, and identify needs before free agency opens.",
                order: 4
            )
        case .combine:
            return PhaseInfo(
                name: "NFL Combine",
                description: "Prospects showcase their athletic ability. Scout, interview, and build your Big Board.",
                order: 5
            )
        case .freeAgency:
            return PhaseInfo(
                name: "Free Agency",
                description: "Re-sign your own players and pursue free agents to address roster needs.",
                order: 6
            )
        case .proDays:
            return PhaseInfo(
                name: "Pro Days & Workouts",
                description: "Attend college pro days and conduct private workouts before the draft.",
                order: 7
            )
        case .draft:
            return PhaseInfo(
                name: "NFL Draft",
                description: "Select the next generation of talent for your franchise.",
                order: 8
            )
        case .otas:
            return PhaseInfo(
                name: "OTAs",
                description: "Organize team activities, set your depth chart, and pair mentors with young players.",
                order: 9
            )
        case .trainingCamp:
            return PhaseInfo(
                name: "Training Camp",
                description: "Players compete for roster spots. Evaluate development and position battles.",
                order: 10
            )
        case .preseason:
            return PhaseInfo(
                name: "Preseason",
                description: "Exhibition games let you evaluate young talent before final roster decisions.",
                order: 11
            )
        case .rosterCuts:
            return PhaseInfo(
                name: "Roster Cuts",
                description: "Trim the roster to 53 players and set your practice squad.",
                order: 12
            )
        case .regularSeason:
            return PhaseInfo(
                name: "Regular Season",
                description: "Compete across 18 weeks for a playoff berth. Manage injuries, trades, and game plans.",
                order: 13
            )
        case .tradeDeadline:
            return PhaseInfo(
                name: "Trade Deadline",
                description: "Last chance to make trades this season. Buy or sell based on your record.",
                order: 14
            )
        case .playoffs:
            return PhaseInfo(
                name: "Playoffs",
                description: "Win or go home. Prepare your game plan and manage your roster for each round.",
                order: 15
            )
        }
    }

    // MARK: - Task Generation

    /// Generate a list of tasks for the given phase and game state.
    ///
    /// - Parameters:
    ///   - phase: The current season phase.
    ///   - career: The player's career model.
    ///   - team: The player's team (optional -- nil if not yet assigned).
    ///   - rosterCount: Number of players currently on the active roster.
    ///   - hasPendingTradeOffers: Whether unanswered trade offers exist.
    ///   - hasHeadCoach: Whether the team currently has a head coach.
    ///   - hasOC: Whether the team currently has an offensive coordinator.
    ///   - hasDC: Whether the team currently has a defensive coordinator.
    ///   - hasExpiringContracts: Whether any key players have expiring contracts.
    ///   - opponentName: The name of the next opponent (regular season / playoffs).
    ///   - playoffRoundName: The name of the current playoff round (e.g. "Divisional").
    ///   - hasScoutsAssigned: Whether any scouts are deployed on college scouting.
    ///   - hasPendingEvents: Whether there are unhandled game events / news items.
    ///   - ownerSatisfaction: The owner's current satisfaction rating.
    ///   - isDraftComplete: Whether the draft has already been completed this phase.
    /// - Returns: An ordered array of `GameTask` items.
    static func generateTasks(
        for phase: SeasonPhase,
        career: Career,
        team: Team?,
        rosterCount: Int = 53,
        hasPendingTradeOffers: Bool = false,
        hasHeadCoach: Bool = true,
        hasOC: Bool = true,
        hasDC: Bool = true,
        hasExpiringContracts: Bool = false,
        opponentName: String? = nil,
        playoffRoundName: String? = nil,
        hasScoutsAssigned: Bool = false,
        hasPendingEvents: Bool = false,
        ownerSatisfaction: Int = 50,
        isDraftComplete: Bool = false,
        interviewsDone: Int = 0,
        interviewsMax: Int = DraftPrepProgress.interviewSlots,
        allScoutsAssignedToProDays: Bool = false,
        prepProgress: DraftPrepProgress? = nil
    ) -> [GameTask] {
        let phaseTasks: [GameTask]
        switch phase {
        case .superBowl:
            phaseTasks = superBowlTasks()
        case .proBowl:
            phaseTasks = proBowlTasks()
        case .coachingChanges:
            phaseTasks = coachingChangesTasks(
                hasHeadCoach: hasHeadCoach,
                hasOC: hasOC,
                hasDC: hasDC,
                playerIsHC: career.role == .gmAndHeadCoach
            )
        case .combine:
            phaseTasks = combineTasks(
                interviewsDone: interviewsDone,
                interviewsMax: interviewsMax,
                prepProgress: prepProgress
            )
        case .freeAgency:
            phaseTasks = freeAgencyTasks(hasExpiringContracts: hasExpiringContracts)
        case .proDays:
            phaseTasks = proDaysTasks(
                allScoutsAssigned: allScoutsAssignedToProDays,
                prepProgress: prepProgress
            )
        case .reviewRoster:
            phaseTasks = reviewRosterTasks()
        case .draft:
            phaseTasks = draftTasks(isDraftComplete: isDraftComplete)
        case .otas:
            phaseTasks = otasTasks()
        case .trainingCamp:
            phaseTasks = trainingCampTasks()
        case .preseason:
            phaseTasks = preseasonTasks()
        case .rosterCuts:
            phaseTasks = rosterCutsTasks(rosterCount: rosterCount)
        case .regularSeason:
            phaseTasks = regularSeasonTasks(
                opponentName: opponentName,
                hasPendingTradeOffers: hasPendingTradeOffers,
                hasScoutsAssigned: hasScoutsAssigned,
                hasPendingEvents: hasPendingEvents,
                ownerSatisfaction: ownerSatisfaction,
                week: career.currentWeek
            )
        case .tradeDeadline:
            // The deadline week is still a game week — it has an opponent, a game
            // plan and an injury report like any other. Its own tasks are an
            // OVERLAY on the weekly list, not a replacement for it, or the user
            // would lose game prep on the week the phase finally became real.
            // `hasPendingTradeOffers: false` on the weekly half so the offers row
            // is emitted once, by the deadline half, whose copy carries the
            // urgency ("…that expire at the deadline").
            phaseTasks = regularSeasonTasks(
                opponentName: opponentName,
                hasPendingTradeOffers: false,
                hasScoutsAssigned: hasScoutsAssigned,
                hasPendingEvents: hasPendingEvents,
                ownerSatisfaction: ownerSatisfaction,
                week: career.currentWeek
            ) + tradeDeadlineTasks(hasPendingTradeOffers: hasPendingTradeOffers)
        case .playoffs:
            phaseTasks = playoffTasks(
                playoffRoundName: playoffRoundName,
                opponentName: opponentName
            )
        }

        // Read-only group-banner header row pinned to the top of every phase
        // task list. Marked `.done` so it visually reads as a label rather than
        // an actionable step. The destination falls through to the inbox so a
        // stray tap doesn't trap the user.
        let progress = phase.groupProgress
        let banner = GameTask(
            phase: phase,
            title: "\u{2500} \(phase.group.displayName) \u{2500}",
            description: "Phase \(progress.current) of \(progress.total) in the \(phase.group.displayName) group.",
            icon: phase.group.icon,
            destination: .inbox,
            isRequired: false,
            status: .done
        )
        return [banner] + capComplianceTasks(phase: phase, career: career, team: team) + phaseTasks
    }

    // MARK: - Cap Compliance (cap-compliance wave)

    /// The required task a club over the salary cap carries, in every phase the
    /// league is looking.
    ///
    /// **A cross-phase OVERLAY, not a phase task.** Being over the cap is not
    /// something that happens during free agency — it is a state of the club's
    /// books that persists until somebody fixes it, and the fix has to be
    /// reachable from wherever the user happens to be. So it is emitted
    /// alongside `phaseTasks` rather than inside any of them, and it sits
    /// directly under the group banner because a required task nobody scrolls to
    /// is a required task nobody does.
    ///
    /// **Derived from `team`, which the caller already passes.** Deliberately
    /// NOT a new `generateTasks` parameter: the shell would have to compute and
    /// thread the overage, and until it did the gate would exist in the engine
    /// and be invisible in the game. Reading it off `Team.availableCap` here
    /// means the task appears the moment the condition is true, in every save,
    /// with no call site changed.
    ///
    /// The task is shown whenever the club is over inside the window, INCLUDING
    /// the fully-guaranteed corner where `WeekAdvancer.userCapComplianceViolation`
    /// declines to block (see its anti-deadlock rule). Telling the user his books
    /// are illegal costs nothing; refusing to let him play does, so only the
    /// refusal is conditional on there being a way out.
    private static func capComplianceTasks(
        phase: SeasonPhase,
        career: Career,
        team: Team?
    ) -> [GameTask] {
        let status = CapManagementEngine.complianceStatus(team: team, capMode: career.capMode)
        guard !status.isCompliant else { return [] }
        guard CapManagementEngine.isComplianceWindow(
            phase: phase,
            hasRolledOver: career.lastRolloverSeason >= career.currentSeason
        ) else { return [] }

        let over = CommittedCapLedger.money(status.overage)
        return [
            GameTask(
                phase: phase,
                title: "Get under the salary cap",
                description: "Your club is \(over) over the cap. Release, restructure or "
                    + "renegotiate contracts until the books balance — no week can be "
                    + "advanced while you are over.",
                icon: "exclamationmark.triangle.fill",
                destination: .capOverview,
                isRequired: true
            )
        ]
    }

    // MARK: - Phase-Specific Task Lists

    private static func superBowlTasks() -> [GameTask] {
        [
            GameTask(
                phase: .superBowl,
                title: "Watch the Super Bowl results",
                description: "See which team won the championship and review the game recap.",
                icon: "trophy.fill",
                destination: .news,
                isRequired: false,
                status: .done  // auto-complete
            ),
            GameTask(
                phase: .superBowl,
                title: "Review league awards",
                description: "Check MVP, Offensive/Defensive Player of the Year, and other honors.",
                icon: "star.fill",
                destination: .news,
                isRequired: false,
                status: .done  // auto-complete
            ),
        ]
    }

    private static func proBowlTasks() -> [GameTask] {
        [
            GameTask(
                phase: .proBowl,
                title: "Review Pro Bowl selections",
                description: "See which of your players earned Pro Bowl honors.",
                icon: "star.circle.fill",
                destination: .roster,
                isRequired: false,
                status: .done  // auto-complete
            ),
        ]
    }

    private static func coachingChangesTasks(
        hasHeadCoach: Bool,
        hasOC: Bool,
        hasDC: Bool,
        playerIsHC: Bool = false
    ) -> [GameTask] {
        var tasks: [GameTask] = []

        // REQUIRED: individual coach hiring tasks
        // If player is GM+HC, they ARE the head coach — no need to hire one
        if !hasHeadCoach && !playerIsHC {
            tasks.append(GameTask(
                phase: .coachingChanges,
                title: "Hire Head Coach",
                description: "Your team has no head coach. Hire one before moving on.",
                icon: "person.badge.plus",
                destination: .hireHC,
                isRequired: true
            ))
        }

        if !hasOC {
            tasks.append(GameTask(
                phase: .coachingChanges,
                title: "Hire Offensive Coordinator",
                description: "Your team needs an offensive coordinator to run the offense.",
                icon: "person.badge.plus",
                destination: .hireOC,
                isRequired: true
            ))
        }

        if !hasDC {
            tasks.append(GameTask(
                phase: .coachingChanges,
                title: "Hire Defensive Coordinator",
                description: "Your team needs a defensive coordinator to run the defense.",
                icon: "person.badge.plus",
                destination: .hireDC,
                isRequired: true
            ))
        }

        // The two reads of the coaching screen. **Confirm-only (#162).**
        //
        // They used to point at the bare `.coachingStaff` destination, which had
        // two consequences and no upside. Routing: both rows opened the same
        // screen on whatever tab it happened to default to (`.staff`), so
        // "Review coordinator schemes" landed on the hiring list and the user had
        // to go find the schemes himself. Completion: `markTaskVisited` stamped
        // both `.inProgress` the moment the screen appeared — a state change the
        // user never asked for and which was worth nothing, because no case
        // anywhere could carry either row to `.done`. The rows could not be
        // ticked off by any action in the game.
        //
        // Each now points at its own tab and is closed by the explicit confirm
        // bar at the foot of that tab (`CoachingStaffView`), which files `.done`
        // against `TaskProgressStore` under the title below — the same durable,
        // career-scoped, cycle-stamped record #138a built, so a cold launch keeps
        // the tick. The P1 principle in one line: no invisible completions, and
        // no completion the user cannot see himself make.
        tasks.append(GameTask(
            phase: .coachingChanges,
            title: staffReviewTaskKey,
            description: "Evaluate your coordinators and position coaches, then confirm the review on the Review tab.",
            icon: "person.3.fill",
            destination: .coachingStaffReview,
            isRequired: false
        ))

        tasks.append(GameTask(
            phase: .coachingChanges,
            title: schemeReviewTaskKey,
            description: "Check offensive and defensive scheme fit with your roster, then confirm the review on the Schemes tab.",
            icon: "gearshape.2.fill",
            destination: .coordinatorSchemes,
            isRequired: false
        ))

        return tasks
    }

    /// The two Coaching Changes rows `CoachingStaffView` can close (#162).
    ///
    /// Declared here rather than typed out a second time in the view, for the
    /// reason `combineChain` was extracted: every completion check in this app
    /// keys off ``GameTask/matchKey``, so a confirm button filing a string the
    /// generator does not emit is a button that silently does nothing.
    static let staffReviewTaskKey = "Review coaching staff"
    static let schemeReviewTaskKey = "Review coordinator schemes"

    /// Decorates a ``DraftPrepStep``'s task with its live counter and completes
    /// it from ``DraftPrepProgress`` — the one authority on whether the stage's
    /// action has actually been performed (#104).
    ///
    /// The title always starts with `step.requiredTaskKey`, so `GameTask
    /// .matchKey` (which strips the ` (…)` suffix) keeps matching the stage
    /// table no matter what counter is appended.
    private static func stageTask(
        _ step: DraftPrepStep,
        description: String,
        icon: String,
        destination: TaskDestination,
        isRequired: Bool,
        progress: DraftPrepProgress?,
        fallbackCounter: String? = nil
    ) -> GameTask {
        let key = step.requiredTaskKey ?? step.displayName
        let row = progress?[step]
        let counter: String? = {
            if let row, row.isCounted, row.done > 0 { return "\(row.done)/\(row.total) \(row.unit)" }
            return progress == nil ? fallbackCounter : nil
        }()
        return GameTask(
            phase: step.phase,
            title: counter.map { "\(key) (\($0))" } ?? key,
            description: description,
            icon: icon,
            destination: destination,
            isRequired: isRequired,
            status: (row?.isSatisfied ?? false) ? .done : .todo
        )
    }

    private static func combineTasks(
        interviewsDone: Int = 0,
        interviewsMax: Int = DraftPrepProgress.interviewSlots,
        prepProgress: DraftPrepProgress? = nil
    ) -> [GameTask] {
        [
            // The combine trip. **Optional, deliberately (#104/B2.)**
            //
            // It was REQUIRED, and it is the one prep action the club can be
            // priced out of: the trip is bought out of the same scouting pot the
            // department's salaries have already drawn on, so a club that filled
            // all eight scout jobs could not afford the flight — and the red
            // "Required" chip therefore stayed on the timeline forever, with no
            // action anywhere in the app able to clear it.
            //
            // It also should never have been required. The combine is a league
            // event on a fixed date (`WeekAdvancer.ensureCombineRun`): sending
            // your own people buys PRECISION, not access, which is exactly why
            // "Review Combine results" below was de-gated from it. A GM who
            // watches it on television has a complete, if rounded, results sheet
            // and a perfectly playable spring.
            GameTask(
                phase: .combine,
                title: "Send scouts to Combine",
                description: "Buy exact times and filed reports in Indianapolis. Skip it and you read the same numbers off the broadcast, rounded.",
                icon: "binoculars.fill",
                destination: .scouting,
                isRequired: false
            ),
            // Stage 1: combineReview — REQUIRED. Satisfied by opening the tab on
            // a class that has numbers.
            stageTask(
                .combineReview,
                description: "Study 40-yard times, bench press, and drill results. Check media reactions.",
                icon: "chart.bar.fill",
                destination: .scouting,
                isRequired: true,
                progress: prepProgress
            ),
            // Optional: Update board between reviews
            GameTask(
                phase: .combine,
                title: "Update Big Board",
                description: "Rank prospects based on Combine performance and scouting reports.",
                icon: "list.number",
                destination: .bigBoard,
                isRequired: false
            ),
            // Stage 2: interviews — REQUIRED. **Now ahead of film study** (#104):
            // the widest, cheapest net comes first, and tape is ordered on the
            // men the room actually liked.
            stageTask(
                .interviews,
                description: "Select and interview up to \(interviewsMax) prospects. Reveals personality, football IQ, and character.",
                icon: "bubble.left.and.bubble.right.fill",
                destination: .scouting,
                isRequired: true,
                progress: prepProgress,
                fallbackCounter: interviewsDone > 0 ? "\(interviewsDone)/\(interviewsMax) interviews" : nil
            ),
            // REQUIRED — unlocks once interviews have been conducted.
            GameTask(
                phase: .combine,
                title: "Review interview report",
                description: "Review full interview report with grades, risk analysis, and scout recommendations.",
                icon: "doc.text.magnifyingglass",
                destination: .interviewReport,
                isRequired: true
            ),
            // Stage 3: filmStudy. The TAPE half of the evaluation ladder, funded
            // by the existing evaluation-slot economy — no new currency.
            //
            // Stays OPTIONAL: the stage spends money, and a club whose scouting
            // pot is gone must still be able to advance its offseason. It is
            // completable now (it never was — the shell's completion switch had
            // no case for it at all), because `DraftPrepProgress` satisfies it
            // at `filmStudyThreshold` reports filed.
            stageTask(
                .filmStudy,
                description: "Put the scouts on tape for the men at the top of your board. \(DraftPrepProgress.filmStudyThreshold) reports is a worked stage; each one costs an evaluation slot.",
                icon: "film.stack",
                destination: .filmStudy,
                isRequired: false,
                progress: prepProgress
            ),
        ]
    }

    private static func freeAgencyTasks(hasExpiringContracts: Bool) -> [GameTask] {
        [
            GameTask(
                phase: .freeAgency,
                title: "Final Push \u{2014} Re-sign or let walk",
                description: "Make final offers to your expiring players before the market opens.",
                icon: "arrow.triangle.2.circlepath",
                destination: .freeAgency,
                isRequired: true
            ),
            GameTask(
                phase: .freeAgency,
                title: "Start New League Year",
                description: "Advance contracts and open the free agent market.",
                icon: "calendar.badge.clock",
                destination: .freeAgency,
                isRequired: true
            ),
            GameTask(
                phase: .freeAgency,
                title: "Roster & Cap compliance",
                description: "Ensure your team is under the salary cap.",
                icon: "dollarsign.circle.fill",
                destination: .freeAgency,
                isRequired: true
            ),
            GameTask(
                phase: .freeAgency,
                title: "Free agency signings",
                description: "Browse the market and sign free agents over 6 rounds.",
                icon: "person.badge.plus",
                destination: .freeAgency,
                isRequired: true
            ),
        ]
    }

    private static func reviewRosterTasks() -> [GameTask] {
        [
            // Money first (#127): every decision below — which groups to grade
            // harshly, who to tag, who to let walk — is made AGAINST next
            // year's cap, so the outlook is the first thing a GM reads, not an
            // optional footnote after the tag is already applied.
            GameTask(
                phase: .reviewRoster,
                title: "Check Salary Cap Outlook",
                description: "Start here: next league year's cap, your projected space, and what free agency will cost. Every call below is made against this number.",
                icon: "chart.pie.fill",
                destination: .capOverview,
                isRequired: false,
                completesOnVisit: true
            ),
            // The two events that fired on the way INTO this phase, and which the
            // task list never mentioned: underclassmen declared for the draft
            // (the class the user has been scouting just changed shape) and the
            // Senior Bowl was played (a fresh report on every prospect who
            // attended). Both landed as news + inbox only, so a user working the
            // task list top-down never learned the board had moved.
            //
            // #128: the destination is `.classDepth`, not `.scouting`. Opening
            // the hub bare in `.reviewRoster` lands on the combine tab — the
            // stage the pipeline pointer sits at — and the combine has not been
            // held: `combineInvite` is stamped by `ScoutingEngine
            // .generateCombineResults`, which only runs once the combine window
            // opens, so the screen a REQUIRED-adjacent task handed the user read
            // "Combine Not Simulated / 0 of 0 prospects invited" over a class he
            // had scouted 83 % of. The depth screen is what this copy describes.
            GameTask(
                phase: .reviewRoster,
                title: "Read the Senior Bowl & declaration reports",
                description: "Underclassmen have declared and the Senior Bowl has been played. See how deep the class is now at every position \u{2014} it is not the one you scouted in the autumn.",
                icon: "chart.bar.doc.horizontal",
                destination: .classDepth,
                isRequired: false,
                completesOnVisit: true
            ),
            // Both of these are READS of the roster-evaluation screen, and both
            // are now completed by the visit (#138b). They used to wait on
            // `rosterEvaluationConfirmed` — a confirm button at the bottom of
            // that screen — while the advance gate counted the visit alone as
            // satisfaction, so the phase unlocked with two required rows still
            // wearing the red "Required" pill and missing from the rail counter.
            // The confirm button still completes them; it is no longer the only
            // thing that does.
            GameTask(
                phase: .reviewRoster,
                title: "Review Position Group Grades",
                description: "Check which position groups need depth and which are strengths.",
                icon: "chart.bar.doc.horizontal",
                destination: .rosterEvaluation,
                isRequired: true,
                completesOnVisit: true
            ),
            GameTask(
                phase: .reviewRoster,
                title: "Analyze Contract Situations",
                description: "Review expiring contracts, overpaid and underpaid players.",
                icon: "dollarsign.circle.fill",
                destination: .rosterEvaluation,
                isRequired: true,
                completesOnVisit: true
            ),
            GameTask(
                phase: .reviewRoster,
                title: "Franchise Tag Decisions",
                description: "Apply franchise tag to keep key players from hitting free agency.",
                icon: "tag.fill",
                destination: .franchiseTag,
                isRequired: true
            ),
            GameTask(
                phase: .reviewRoster,
                title: "Set Roster Priorities",
                description: "Identify your biggest needs heading into the draft.",
                icon: "list.bullet.clipboard.fill",
                destination: .rosterEvaluation,
                isRequired: false
            ),
        ]
    }

    /// The pro-day phase task list, keyed to the ``DraftPrepStep`` stages that
    /// run inside it (#103).
    ///
    /// Titles come from ``DraftPrepStep/requiredTaskKey`` so the stage machine
    /// and the task list cannot drift apart — the stage's advance button is
    /// gated on finding a task with exactly that `matchKey`.
    ///
    /// Only the two tasks that were required before this wave are required now.
    /// The new stage rows ship optional and Waves A/B promote them as their
    /// screens (and their skip buttons) land: a required task the user has no
    /// surface to satisfy would make the phase un-advanceable.
    private static func proDaysTasks(
        allScoutsAssigned: Bool = false,
        prepProgress: DraftPrepProgress? = nil
    ) -> [GameTask] {
        [
            // Stage: proDayFocus. Assigning a school reserves a focus slot;
            // nothing runs until the stage's advance button sends the
            // department out (that single execution path is Wave B).
            //
            // `allScoutsAssigned` is the pre-#104 fallback for callers that have
            // no progress to hand; when progress is present it is the authority,
            // and it counts RESERVATIONS (`scout.proDayColleges`) rather than
            // executions, so the task ticks the moment the user books a school.
            stageTask(
                .proDayFocus,
                description: "Every school holds a pro day and the numbers are public. Pick the ones worth the trip \u{2014} your staff buys exact times, a filed report and a closer look there.",
                icon: "figure.run",
                destination: .proDayTour,
                isRequired: true,
                progress: prepProgress
            ).completed(if: prepProgress == nil && allScoutsAssigned),
            GameTask(
                phase: .proDays,
                title: "Review Pro Day results",
                description: "Check pro day performances and compare to Combine results.",
                icon: "chart.bar.doc.horizontal.fill",
                destination: .scouting,
                isRequired: true,
                completesOnVisit: true
            ),
            // Stage: workouts.
            stageTask(
                .workouts,
                description: "Invite top prospects for private workouts with your coaching staff.",
                icon: "dumbbell.fill",
                destination: .workouts,
                isRequired: false,
                progress: prepProgress
            ),
            // Stage: mockOne — the post-tour mock, read as a league event.
            stageTask(
                .mockOne,
                description: "The first mock since the pro-day circuit. See where the league has your board \u{2014} and where it disagrees with you.",
                icon: "doc.text",
                destination: .mockDraft,
                isRequired: false,
                progress: prepProgress
            ),
            // Stage: top30Visits — facility visits, the last instrument before
            // the draft.
            stageTask(
                .top30Visits,
                description: "Bring prospects to the facility. Thirty visits, and the rest of the league is watching who walks in.",
                icon: "building.2.fill",
                destination: .top30Visits,
                isRequired: false,
                progress: prepProgress
            ),
            // Stage: mockTwo — the last board event before the draft.
            stageTask(
                .mockTwo,
                description: "The last mock before the draft. Compare it against Mock 1.0 and against your own board.",
                icon: "doc.text.fill",
                destination: .mockDraft,
                isRequired: false,
                progress: prepProgress
            ),
            GameTask(
                phase: .proDays,
                title: "Finalize Big Board",
                description: "Make your final prospect rankings before the draft.",
                icon: "list.number",
                destination: .bigBoard,
                isRequired: false
            ),
        ]
    }

    private static func draftTasks(isDraftComplete: Bool) -> [GameTask] {
        var tasks: [GameTask] = [
            // REQUIRED: enter the draft
            GameTask(
                phase: .draft,
                title: "Enter the Draft",
                description: "It's time to select the future of your franchise.",
                icon: "list.clipboard.fill",
                destination: .draft,
                isRequired: true,
                status: isDraftComplete ? .done : .todo
            ),
            // Optional
            GameTask(
                phase: .draft,
                title: "Finalize Big Board",
                description: "Make final adjustments to your prospect rankings before draft day.",
                icon: "list.number",
                destination: .bigBoard,
                isRequired: false
            ),
            GameTask(
                phase: .draft,
                title: "Review team needs",
                description: "Check your depth chart for positions that need reinforcements.",
                icon: "chart.bar.doc.horizontal",
                destination: .depthChart,
                isRequired: false
            ),
        ]

        return tasks
    }

    private static func otasTasks() -> [GameTask] {
        [
            // REQUIRED: set depth chart
            GameTask(
                phase: .otas,
                title: "Set depth chart",
                description: "Establish your starting lineup and backup order at every position.",
                icon: "list.bullet.rectangle.portrait.fill",
                destination: .depthChart,
                isRequired: true
            ),
            // REQUIRED: set training focus
            GameTask(
                phase: .otas,
                title: "Set training focus",
                description: "Allocate Tactical / Physical / Technical focus for the upcoming week.",
                icon: "figure.run.circle.fill",
                destination: .trainingPlan,
                isRequired: true
            ),
            // Optional
            GameTask(
                phase: .otas,
                title: "Set game plan",
                description: "Install your offensive and defensive schemes for the upcoming season.",
                icon: "sportscourt.fill",
                destination: .gamePlan,
                isRequired: false
            ),
            GameTask(
                phase: .otas,
                title: "Assign mentoring pairs",
                description: "Pair veteran leaders with young players to accelerate development.",
                icon: "person.2.wave.2.fill",
                destination: .mentoring,
                isRequired: false
            ),
            GameTask(
                phase: .otas,
                title: "Monitor workload",
                description: "Watch player camp load — overload risks injuries before camp even starts.",
                icon: "heart.text.square.fill",
                destination: .workloadDashboard,
                isRequired: false
            ),
        ]
    }

    private static func trainingCampTasks() -> [GameTask] {
        [
            // REQUIRED: set training focus per camp week
            GameTask(
                phase: .trainingCamp,
                title: "Set training focus",
                description: "Allocate Tactical / Physical / Technical focus for this camp week.",
                icon: "figure.run.circle.fill",
                destination: .trainingPlan,
                isRequired: true
            ),
            // Optional
            GameTask(
                phase: .trainingCamp,
                title: "Review camp grades",
                description: "See which players are earning roster spots based on camp performance.",
                icon: "graduationcap.fill",
                destination: .roster,
                isRequired: false
            ),
            GameTask(
                phase: .trainingCamp,
                title: "Resolve position battles",
                description: "Track daily winners in position competitions and lock in starters.",
                icon: "figure.wrestling",
                destination: .depthChart,
                isRequired: false
            ),
            GameTask(
                phase: .trainingCamp,
                title: "Monitor workload",
                description: "Heat-map of injury / burnout risk across the entire roster.",
                icon: "heart.text.square.fill",
                destination: .workloadDashboard,
                isRequired: false
            ),
            GameTask(
                phase: .trainingCamp,
                title: "Check preseason storylines",
                description: "Read the latest news about your team heading into the preseason.",
                icon: "newspaper.fill",
                destination: .news,
                isRequired: false
            ),
        ]
    }

    private static func preseasonTasks() -> [GameTask] {
        [
            // REQUIRED: training focus continues through preseason
            GameTask(
                phase: .preseason,
                title: "Set training focus",
                description: "Final preseason week — choose camp focus before final cuts.",
                icon: "figure.run.circle.fill",
                destination: .trainingPlan,
                isRequired: true
            ),
            GameTask(
                phase: .preseason,
                title: "Review preseason results",
                description: "Preseason games auto-simulate. Review results and stat lines.",
                icon: "play.rectangle.fill",
                destination: .schedule,
                isRequired: false,
                status: .done  // auto-simulated
            ),
            GameTask(
                phase: .preseason,
                title: "Finalize depth chart",
                description: "Lock in starters and backups before final roster cuts begin.",
                icon: "list.bullet.rectangle.portrait.fill",
                destination: .depthChart,
                isRequired: false
            ),
            GameTask(
                phase: .preseason,
                title: "Evaluate young players",
                description: "Check preseason performance of rookies and fringe roster players.",
                icon: "person.crop.rectangle.stack.fill",
                destination: .roster,
                isRequired: false
            ),
            GameTask(
                phase: .preseason,
                title: "Monitor workload",
                description: "Final check on player workload before the regular season grind.",
                icon: "heart.text.square.fill",
                destination: .workloadDashboard,
                isRequired: false
            ),
        ]
    }

    private static func rosterCutsTasks(rosterCount: Int) -> [GameTask] {
        let overLimit = rosterCount > 53
        var tasks: [GameTask] = [
            // REQUIRED only if over 53
            GameTask(
                phase: .rosterCuts,
                title: overLimit
                    ? "Finalize 53-man roster (\(rosterCount) currently)"
                    : "Roster is at 53 players",
                description: overLimit
                    ? "You must release \(rosterCount - 53) player(s) to reach the 53-man limit."
                    : "Your roster meets the 53-man requirement.",
                icon: "scissors",
                destination: .rosterCuts,
                isRequired: overLimit,
                status: overLimit ? .todo : .done
            ),
        ]

        // Camp-cut staging tasks. The 90→75 / 75→65 / 65→53 progression is the
        // canonical NFL flow; tasks deep-link into the multi-stage RosterCutView.
        tasks.append(GameTask(
            phase: .rosterCuts,
            title: "Cut to 75",
            description: "First wave of camp cuts. Trim the roster from 90 to 75 players.",
            icon: "scissors",
            destination: .rosterCuts,
            isRequired: false
        ))

        tasks.append(GameTask(
            phase: .rosterCuts,
            title: "Cut to 65",
            description: "Second wave of camp cuts. Trim the roster from 75 to 65 players.",
            icon: "scissors",
            destination: .rosterCuts,
            isRequired: false
        ))

        tasks.append(GameTask(
            phase: .rosterCuts,
            title: "Cut to 53",
            description: "Final wave — set your 53-man active roster.",
            icon: "scissors",
            destination: .rosterCuts,
            isRequired: false
        ))

        // §5.1: the squad is STOCKED automatically when this phase ends (own
        // cuts first, then street free agents) — the task is the heads-up that
        // it is about to exist and that rivals can raid it all season, not a
        // second selection screen on top of the cut flow above.
        tasks.append(GameTask(
            phase: .rosterCuts,
            title: "Flag practice-squad keepers",
            description: "Players you flag while cutting go to the 16-man practice squad when the season opens. They develop on scout-team reps — and any rival can sign them to its active roster.",
            icon: "person.3.sequence.fill",
            destination: .rosterCuts,
            isRequired: false
        ))

        return tasks
    }

    private static func regularSeasonTasks(
        opponentName: String?,
        hasPendingTradeOffers: Bool,
        hasScoutsAssigned: Bool,
        hasPendingEvents: Bool,
        ownerSatisfaction: Int,
        week: Int
    ) -> [GameTask] {
        // Regular season: no required tasks — advance always allowed
        var tasks: [GameTask] = []

        let opponent = opponentName ?? "your opponent"
        tasks.append(GameTask(
            phase: .regularSeason,
            title: "Set game plan for \(opponent)",
            description: "Choose your offensive and defensive strategy for this week's matchup.",
            icon: "sportscourt.fill",
            destination: .gamePlan,
            isRequired: false
        ))

        tasks.append(GameTask(
            phase: .regularSeason,
            title: "Tune week prep vs \(opponent)",
            description: "Balance general training vs opponent-specific prep — drives audible / read bonuses.",
            icon: "scope",
            destination: .gameWeekPrep,
            isRequired: false
        ))

        tasks.append(GameTask(
            phase: .regularSeason,
            title: "Review depth chart",
            description: "Make sure your best players are starting and backups are set.",
            icon: "list.bullet.rectangle.portrait.fill",
            destination: .depthChart,
            isRequired: false
        ))

        tasks.append(GameTask(
            phase: .regularSeason,
            title: "Check injury report",
            description: "Review player injuries and adjust your lineup if needed.",
            icon: "cross.case.fill",
            destination: .roster,
            isRequired: false
        ))

        // Week 9 is when the class is generated (`WeekAdvancer`, midseason mock).
        // Before that the scouting hub has an empty board, and this row sent the
        // user to it every week from opening day with a promise of "new reports"
        // that could not possibly exist yet.
        if hasScoutsAssigned && week >= Self.draftClassOnBoardWeek {
            tasks.append(GameTask(
                phase: .regularSeason,
                title: "Scout college prospects",
                description: "The college class is on the board. Your scouts have filed their first reports \u{2014} review the intel.",
                icon: "binoculars.fill",
                destination: .scouting,
                isRequired: false
            ))
        }

        if hasPendingTradeOffers {
            tasks.append(GameTask(
                phase: .regularSeason,
                title: "Review trade offers",
                description: "Other teams have proposed trades. Evaluate and respond.",
                icon: "arrow.left.arrow.right",
                destination: .trades,
                isRequired: false
            ))
        }

        if hasPendingEvents {
            tasks.append(GameTask(
                phase: .regularSeason,
                title: "Handle pending events",
                description: "Important events need your attention before advancing.",
                icon: "exclamationmark.bubble.fill",
                destination: .news,
                isRequired: false
            ))
        }

        if ownerSatisfaction < 40 {
            tasks.append(GameTask(
                phase: .regularSeason,
                title: "Owner meeting requested",
                description: "The owner is unhappy. Meet to discuss the team's direction.",
                icon: "building.2.fill",
                destination: .ownerMeeting,
                isRequired: false
            ))
        }

        return tasks
    }

    private static func tradeDeadlineTasks(hasPendingTradeOffers: Bool) -> [GameTask] {
        var tasks: [GameTask] = [
            GameTask(
                phase: .tradeDeadline,
                title: "Evaluate trade targets",
                description: "The deadline is approaching. Identify players who could help your team.",
                icon: "arrow.left.arrow.right",
                destination: .trades,
                isRequired: false
            ),
            GameTask(
                phase: .tradeDeadline,
                title: "Review roster and needs",
                description: "Decide whether to buy or sell at the deadline based on your record.",
                icon: "chart.bar.doc.horizontal",
                destination: .roster,
                isRequired: false
            ),
        ]

        if hasPendingTradeOffers {
            tasks.append(GameTask(
                phase: .tradeDeadline,
                title: "Respond to trade offers",
                description: "You have pending trade offers that expire at the deadline.",
                icon: "envelope.badge.fill",
                destination: .trades,
                isRequired: false
            ))
        }

        return tasks
    }

    private static func playoffTasks(
        playoffRoundName: String?,
        opponentName: String?
    ) -> [GameTask] {
        let round = playoffRoundName ?? "this round"
        let opponent = opponentName ?? "your opponent"

        return [
            GameTask(
                phase: .playoffs,
                title: "Prepare for \(round) vs \(opponent)",
                description: "Set your game plan for this win-or-go-home matchup.",
                icon: "sportscourt.fill",
                destination: .gamePlan,
                isRequired: false
            ),
            GameTask(
                phase: .playoffs,
                title: "Review matchups",
                description: "Compare your roster against the opponent's strengths and weaknesses.",
                icon: "person.2.fill",
                destination: .roster,
                isRequired: false
            ),
            GameTask(
                phase: .playoffs,
                title: "Check injury report",
                description: "Make sure your key players are healthy for the biggest stage.",
                icon: "cross.case.fill",
                destination: .roster,
                isRequired: false
            ),
        ]
    }

    // MARK: - Helpers

    /// Returns the count of required tasks that are not `.done`.
    ///
    /// **`.inProgress` no longer opens the gate (#138b).** It used to: a task
    /// was "started" the moment its screen appeared, and started was good enough
    /// to advance the phase. That put the gate and every visual in the app on
    /// two different predicates — the row kept its red "Required" pill and its
    /// dotted circle (both keyed on `.done`), the rail's "2/6" kept excluding
    /// it, and the phase unlocked anyway. Worse, `.inProgress` was pure view
    /// state, so a relaunch dropped it and re-locked a phase the user had
    /// already worked through (#138a).
    ///
    /// One predicate now: `.done`, which is durable
    /// (``TaskProgressStore``) and which the pill, the tick, the strikethrough
    /// and the counter already read. Tasks whose completion IS the visit carry
    /// ``GameTask/completesOnVisit`` and reach `.done` on the visit, so nothing
    /// that used to unlock by looking at a screen stopped unlocking.
    static func incompleteRequiredCount(in tasks: [GameTask]) -> Int {
        tasks.filter { $0.isRequired && $0.status != .done }.count
    }

    /// Returns true when every required task is `.done`. The user must still tap
    /// the explicit "Advance" button to transition phases -- this only controls
    /// whether the button is enabled.
    static func allRequiredComplete(in tasks: [GameTask]) -> Bool {
        incompleteRequiredCount(in: tasks) == 0
    }

    /// The combine's required steps, in the order they unlock. Each one is
    /// LOCKED until its predecessor is `.done`.
    ///
    /// Declared once here because three separate screens used to carry their own
    /// copy of this array (`TimelineTasksPanel.isTaskLocked`,
    /// `CareerDashboardView.isHeroTaskLocked`, and the shell's completion pass),
    /// and each compared against `task.title` — which the generator is free to
    /// decorate with a progress counter. Compare against `GameTask.matchKey`.
    ///
    /// **"Send scouts to Combine" is no longer the head of this chain (#104).**
    /// It used to be, and because the combine trip is bought out of a scouting
    /// pot the department's salaries have usually already emptied, a club that
    /// could not afford the flight had the ENTIRE combine phase locked behind a
    /// purchase it could never make: results unreviewable, interviews
    /// unreachable, the report unreadable, and a red "Required" chip with no
    /// action anywhere in the app able to clear it. The trip is optional
    /// precision (`combineTasks`), so it gates nothing.
    static let combineChain: [String] = [
        "Review Combine results",
        "Conduct prospect interviews",
        "Review interview report",
    ]

    /// The pre-draft pipeline's required task keys, in stage order (#103).
    ///
    /// Derived from ``DraftPrepStep/requiredTaskKey`` rather than typed out a
    /// second time — this is the same class of bug `combineChain` was extracted
    /// to kill, one step earlier: a chain that disagrees with the state machine
    /// it is supposed to describe. Compare against ``GameTask/matchKey``.
    static let draftPrepChain: [String] = DraftPrepStep.allCases.compactMap(\.requiredTaskKey)
}

// MARK: - Stable identity

extension GameTask {

    /// The task's identity for state matching, with any progress counter
    /// stripped: `"Conduct prospect interviews (12/60 done)"` → `"Conduct
    /// prospect interviews"`.
    ///
    /// Every "is this task done / is its prerequisite done" check in the app
    /// keys off the title, and several titles carry a live counter. Matching the
    /// decorated string meant that the moment a counter appeared the task could
    /// no longer be completed, and the step after it stayed locked forever — so
    /// the counters were simply never wired up. This is the seam that lets both
    /// things be true at once.
    var matchKey: String {
        guard let paren = title.range(of: " (") else { return title }
        return String(title[title.startIndex..<paren.lowerBound])
    }

    /// Returns this task marked `.done` when `condition` holds, unchanged
    /// otherwise. Lets a task literal stay a literal while a caller-supplied
    /// fallback predicate still completes it.
    func completed(if condition: Bool) -> GameTask {
        guard condition, status != .done else { return self }
        var copy = self
        copy.status = .done
        return copy
    }
}
