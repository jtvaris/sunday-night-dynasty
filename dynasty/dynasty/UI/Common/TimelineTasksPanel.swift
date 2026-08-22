import SwiftUI

/// A unified vertical Timeline+Tasks panel inspired by Football Manager's
/// Messages panel. Shows the current phase with its tasks expanded, plus the
/// next 2-3 upcoming phases with preview tasks, and an advance button.
/// Replaces the separate `phaseTasksSection` and advance button in the dashboard.
struct TimelineTasksPanel: View {

    let career: Career
    @Binding var tasks: [GameTask]
    let onTaskSelected: (TaskDestination) -> Void
    let onAdvance: () -> Void
    let canAdvance: Bool
    /// False while the user's own game for this week is still unplayed. Advance
    /// then renders as a secondary/outline button so the screen keeps exactly
    /// ONE gold call-to-action — the hero card's "Coach the Game". Advancing is
    /// still allowed (it sims the game), it just stops competing for the eye.
    var advanceIsPrimary: Bool = true

    /// A gate OTHER than the required-task list that is holding the advance
    /// (#154f). `nil` when the task list is the only thing in the way.
    ///
    /// The panel counts required tasks and nothing else, so when the caller
    /// blocked the advance for its own reason — a staff-budget overage, say —
    /// the banner printed the arithmetic it did know: "Complete 0 required tasks
    /// to advance", over a disabled button, with no hint anywhere that $49K of
    /// coaching salary was the actual problem. The caller passes the sentence it
    /// already shows in its own blocker banner, so the two cannot drift.
    var advanceBlocker: AdvanceBlocker? = nil

    // #158: `AdvanceBlocker` used to be declared here. It moved to
    // ``StaffLedger``'s file, because the Season Guide sheet has to draw the
    // same sentence and neither surface is allowed to author it — one gate,
    // one type, both readers.

    /// How many upcoming phases (beyond current) to show fully expanded.
    private let upcomingPhaseCount = 3

    /// Completed phases are collapsed behind one disclosure row by default.
    /// Expanded, twelve struck-through rows ate most of the sidebar in Week 1
    /// and pushed the live phase (the only actionable part) below the fold.
    @State private var showCompletedPhases = false

    // MARK: - Ordered Phases

    private static let orderedPhases: [SeasonPhase] = [
        .proBowl,
        .superBowl,
        .coachingChanges,
        .reviewRoster,
        .combine,
        .freeAgency,
        .proDays,
        .draft,
        .otas,
        .trainingCamp,
        .preseason,
        .rosterCuts,
        .regularSeason,
        .tradeDeadline,
        .playoffs
    ]

    private var currentIndex: Int {
        Self.orderedPhases.firstIndex(of: career.currentPhase) ?? 0
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            panelHeader
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // Scrollable phases list
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Past phases — one summary row, expandable on demand.
                    if !pastPhases.isEmpty {
                        completedPhasesDisclosure
                        if showCompletedPhases {
                            ForEach(pastPhases, id: \.phase) { entry in
                                pastPhaseRow(entry)
                            }
                        }
                    }

                    // Current phase (expanded with real tasks)
                    currentPhaseSection

                    // Advance button (full width within panel)
                    advanceSection
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 10)

                    // Upcoming phases (expanded with preview tasks)
                    ForEach(Array(upcomingPhaseTasks.enumerated()), id: \.element.phase) { index, entry in
                        upcomingPhaseSection(entry, isLast: index == upcomingPhaseTasks.count - 1)
                    }

                    // Remaining collapsed future phases
                    if remainingFutureCount > 0 {
                        remainingPhasesIndicator
                    }
                }
                .padding(.bottom, 16)
            }
        }
        .frame(minWidth: 300)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.clipboard.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentGold)

            Text("YOUR \(seasonLabel)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.accentGold)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()

            // Counts real steps only — the group banner is a label that ships
            // pre-`.done`, so including it read as "1/5 done" on a fresh week.
            // Shared with the Season Guide sheet (#134b): one function, one pair.
            let progress = Self.taskProgress(tasks)
            Text("\(progress.done)/\(progress.total)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var seasonLabel: String {
        let phase = career.currentPhase
        switch phase {
        case .regularSeason, .tradeDeadline, .playoffs, .superBowl:
            return "SEASON"
        default:
            return "OFFSEASON"
        }
    }

    // MARK: - Past Phases

    private var pastPhases: [(phase: SeasonPhase, name: String)] {
        guard currentIndex > 0 else { return [] }
        return (0..<currentIndex).map { i in
            let phase = Self.orderedPhases[i]
            return (phase, Self.phaseName(phase))
        }
    }

    /// Single collapsed row standing in for every completed phase, e.g.
    /// "Offseason complete (12)". Labelled after the group the finished phases
    /// belong to when they all share one, otherwise a neutral "Phases complete".
    private var completedPhasesDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCompletedPhases.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                VStack(spacing: 0) {
                    Color.clear.frame(width: 2, height: 6)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.success.opacity(0.7))
                    Rectangle()
                        .fill(Color.textTertiary.opacity(0.3))
                        .frame(width: 2, height: 6)
                }

                Text("\(completedPhasesLabel) (\(pastPhases.count))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                Image(systemName: showCompletedPhases ? "chevron.up" : "chevron.down")
                    .font(.system(size: DSType.Size.caption, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(completedPhasesLabel), \(pastPhases.count) phases")
        .accessibilityHint(showCompletedPhases ? "Collapse the completed list" : "Expand the completed list")
    }

    private var completedPhasesLabel: String {
        let groups = Set(pastPhases.map { $0.phase.group })
        // Once the games start, everything behind us is "the offseason" in the
        // way a coach means it — that reads better than listing four groups.
        if career.currentPhase.group == .regularSeason, !groups.contains(.regularSeason) {
            return "Offseason complete"
        }
        if groups.count == 1, let only = groups.first {
            return "\(only.displayName) complete"
        }
        return "Phases complete"
    }

    private func pastPhaseRow(_ entry: (phase: SeasonPhase, name: String)) -> some View {
        HStack(spacing: 10) {
            // Vertical timeline connector
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.textTertiary.opacity(0.3))
                    .frame(width: 2, height: 10)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiaryReadable)

                Rectangle()
                    .fill(Color.textTertiary.opacity(0.3))
                    .frame(width: 2, height: 10)
            }

            Text(entry.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .strikethrough(true, color: Color.textTertiary.opacity(0.5))

            Spacer()

            Text("Complete")
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .opacity(0.85)
    }

    // MARK: - Current Phase

    private var currentPhaseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phase header row
            HStack(spacing: 10) {
                // Timeline dot
                VStack(spacing: 0) {
                    if currentIndex > 0 {
                        Rectangle()
                            .fill(Color.accentGold.opacity(0.5))
                            .frame(width: 2, height: 8)
                    } else {
                        Color.clear.frame(width: 2, height: 8)
                    }

                    Circle()
                        .fill(Color.accentGold)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Image(systemName: Self.phaseIcon(career.currentPhase))
                                .font(.system(size: DSType.Size.micro, weight: .bold))
                                .foregroundStyle(Color.backgroundPrimary)
                        )

                    Rectangle()
                        .fill(Color.accentGold.opacity(0.5))
                        .frame(width: 2, height: 8)
                }

                Text(Self.phaseName(career.currentPhase))
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .textCase(.uppercase)

                Spacer()

                Text("NOW")
                    .font(.system(size: DSType.Size.caption, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentGold))

                Text(Self.phaseDate(career.currentPhase))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Group caption, replacing the "─ Regular Season ─" pseudo-task that
            // `TaskGenerator` pins to the top of every list. Rendered as a task
            // row it read as a struck-through step the user had somehow already
            // completed — and inside the TRADE DEADLINE / PLAYOFFS groups it
            // looked like a stray "Regular Season" item in the wrong phase.
            Text(groupCaption(for: career.currentPhase))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.leading, 30)
                .padding(.top, 4)

            // Task rows for current phase
            VStack(spacing: 0) {
                let actionable = Self.actionableTasks(tasks)
                // Required-first everywhere EXCEPT Review Roster (#132), where
                // the generator's own order is the meaningful one: that list
                // opens with "Check Salary Cap Outlook" because next year's cap
                // is the number every decision under it — which groups to grade
                // harshly, who to tag, who to let walk — is made against, and
                // sorting required-first dropped it to 4th, underneath the three
                // calls it exists to inform. Nothing about REQUIREDNESS changes:
                // the badge, the lock chain and `allRequiredComplete` all read
                // `isRequired`, never position.
                let ordered = career.currentPhase == .reviewRoster
                    ? actionable
                    : actionable.filter(\.isRequired) + actionable.filter { !$0.isRequired }

                let nextID = nextActionableTask?.id
                ForEach(ordered) { task in
                    currentTaskRow(task, isRequired: task.isRequired, isNext: task.id == nextID)
                }
            }
            .padding(.leading, 30) // Align with text after timeline dot
            .padding(.trailing, 10)
            .padding(.top, 4)
            .padding(.bottom, 4)
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentGold.opacity(0.04))
                .padding(.horizontal, 6)
        )
    }

    /// One task row.
    ///
    /// **#105 wave 2 (P4/P5).** Three things landed here at once, and they are
    /// the same change seen from three sides:
    ///
    /// 1. **The one "what's next" marker.** The dashboard used to carry three
    ///    of them — a gold-bordered Next Action hero card in the work column,
    ///    a "Next: … / Tap to start" button below this list, and an advance
    ///    readiness banner above it — all naming the same row, all recomputing
    ///    "which row is next" separately. `isNext` marks the row itself, which
    ///    is the only place the answer cannot drift from the list it describes.
    /// 2. **A cost→unlock line.** What the step is and what it gates, stated on
    ///    the row before the user commits to the trip. `task.description` is
    ///    the copy the generator already writes; it was previously visible only
    ///    inside the deleted hero card, i.e. for exactly one task at a time.
    /// 3. **A scoped secondary action.** The reference screen this particular
    ///    decision is made against (see `secondaryAction`) — the cap for money
    ///    calls, the board for draft calls — so the row does not need the hub
    ///    to grow another row of global chips to be useful.
    @ViewBuilder
    private func currentTaskRow(_ task: GameTask, isRequired: Bool, isNext: Bool) -> some View {
        let locked = isTaskLocked(task)
        let done = task.status == .done
        let secondary = locked || done ? nil : Self.secondaryAction(for: task.destination)

        VStack(alignment: .leading, spacing: 2) {
            Button {
                if !locked {
                    onTaskSelected(task.destination)
                }
            } label: {
                HStack(spacing: 8) {
                    // Status dot
                    taskStatusIcon(task, isRequired: isRequired, isLocked: locked)

                    // Task text. Baseline alignment keeps the status pill on the
                    // title's *first* line — centered, it floated mid-block on a
                    // title that wrapped, reading as if it belonged to neither line.
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(task.title)
                            .font(.system(size: DSType.Size.body, weight: done ? .regular : (locked ? .regular : .medium)))
                            .foregroundStyle(done ? Color.textTertiary : (locked ? Color.textTertiary : Color.textPrimary))
                            .strikethrough(done, color: Color.textTertiary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if isNext {
                            Text("NEXT")
                                .font(.system(size: DSType.Size.micro, weight: .black))
                                .foregroundStyle(Color.backgroundPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentGold))
                        }

                        if locked {
                            Text("Locked")
                                .font(.system(size: DSType.Size.micro, weight: .heavy))
                                .foregroundStyle(Color.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.backgroundTertiary))
                        } else if isRequired && !done {
                            Text("Required")
                                .font(.system(size: DSType.Size.micro, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.danger))
                        }
                    }

                    Spacer()

                    if !done && !locked {
                        Image(systemName: "chevron.right")
                            .font(.system(size: DSType.Size.caption, weight: .semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(locked)

            // Cost → unlock, with the scoped secondary sharing its line.
            //
            // Not drawn on a finished row: a struck-through title with a
            // paragraph under it is the shape of work still to do. One line
            // rather than two stacked blocks — a 300 pt rail holding seven
            // steps cannot afford a three-deck row, and the chip reads as
            // "…and here is the thing to read it against" beside the sentence
            // it belongs to.
            if !done {
                HStack(alignment: .top, spacing: 6) {
                    Text(detailLine(for: task, isRequired: isRequired, locked: locked))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 2)

                    if let secondary {
                        Button {
                            onTaskSelected(secondary.destination)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: secondary.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                Text(secondary.label)
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(Color.accentGold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().strokeBorder(Color.accentGold.opacity(0.35), lineWidth: 1)
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel("\(secondary.label), reference for \(task.title)")
                    }
                }
                .padding(.leading, 18)
                .padding(.trailing, 2)
                .padding(.bottom, 4)
            }
        }
        .opacity(done ? 0.55 : (locked ? 0.45 : 1.0))
    }

    /// The row's cost→unlock sentence (P4).
    ///
    /// The prefix is the price, `task.description` is what the step is for. A
    /// locked row names the step that opens it instead of leaving the user to
    /// work out which of the rows above it is the prerequisite — before this,
    /// "Locked" was the entire explanation.
    private func detailLine(for task: GameTask, isRequired: Bool, locked: Bool) -> String {
        if locked, let prereq = prerequisiteTitle(for: task) {
            return "Locked \u{00B7} finish \u{201C}\(prereq)\u{201D} first"
        }
        if locked {
            return "Locked \u{00B7} \(task.description)"
        }
        let prefix = isRequired ? "Required to advance" : "Optional"
        return "\(prefix) \u{00B7} \(task.description)"
    }

    /// Title of the step holding this one shut, when the combine chain is what
    /// is holding it. Mirrors `isTaskLocked`'s lookup, one link back.
    private func prerequisiteTitle(for task: GameTask) -> String? {
        let chain = TaskGenerator.combineChain
        guard let index = chain.firstIndex(of: task.matchKey), index > 0 else { return nil }
        return tasks.first { $0.matchKey == chain[index - 1] }?.title
    }

    /// The reference screen a given decision is made against.
    ///
    /// **Scoped, not global** (P5): the hub's quick-action bar answers "what
    /// can I open right now", and it is the wrong place for "what do I need
    /// open while I do THIS". A cut list is priced against the cap, a draft
    /// stage is read against the board, a game plan is set against the depth
    /// chart. One chip, never the row's own destination.
    static func secondaryAction(
        for destination: TaskDestination
    ) -> (label: String, icon: String, destination: TaskDestination)? {
        switch destination {
        // Money decisions → the cap sheet.
        case .rosterCuts, .rosterEvaluation, .franchiseTag, .freeAgency,
             .contractTimeline, .trades:
            return ("Cap", "dollarsign.circle", .capOverview)
        // Draft decisions → the club's own board.
        case .draft, .mockDraft, .classDepth, .filmStudy, .proDayTour,
             .workouts, .top30Visits, .personalWorkouts, .interviewReport:
            return ("Big Board", "list.bullet", .bigBoard)
        // Sunday decisions → the two sheets that feed each other.
        case .gamePlan:
            return ("Depth Chart", "list.number", .depthChart)
        case .gameWeekPrep:
            return ("Game Plan", "scope", .gamePlan)
        case .depthChart, .mentoring, .lockerRoom:
            return ("Roster", "person.3", .roster)
        // Camp decisions → the load the plan is spending.
        case .trainingPlan:
            return ("Workload", "heart.text.square", .workloadDashboard)
        // Scheme fit is read against the men who have to run it.
        case .coordinatorSchemes:
            return ("Roster", "person.3", .roster)
        default:
            return nil
        }
    }

    /// First incomplete required task that is also unlocked (no prerequisite
    /// blocking). **The one definition of "next" on this screen** — it marks
    /// its own row with the NEXT chip, and nothing else recomputes it.
    private var nextActionableTask: GameTask? {
        tasks.first { task in
            task.isRequired && task.status != .done && !isTaskLocked(task)
        }
    }

    /// The required row the advance banner names (#193).
    ///
    /// The NEXT row wherever one is startable — the same task the list already
    /// wears the NEXT chip on, so the banner and the row agree. When every
    /// remaining required row is locked behind a prerequisite there is no
    /// startable one, and the banner falls back to the first incomplete
    /// required task so it still says *something* the user can find in the list.
    private var blockingRequiredTask: GameTask? {
        nextActionableTask ?? TaskGenerator.firstIncompleteRequired(in: tasks)
    }

    /// Determines if a combine/proDays task is locked behind an unfinished prerequisite.
    private func isTaskLocked(_ task: GameTask) -> Bool {
        guard task.status == .todo, task.isRequired else { return false }
        // Combine sequential blocking
        let combineChain = TaskGenerator.combineChain
        if let taskIdx = combineChain.firstIndex(of: task.matchKey), taskIdx > 0 {
            let prereqTitle = combineChain[taskIdx - 1]
            if let prereq = tasks.first(where: { $0.matchKey == prereqTitle }), prereq.status != .done {
                return true
            }
        }
        return false
    }

    @ViewBuilder
    private func taskStatusIcon(_ task: GameTask, isRequired: Bool, isLocked: Bool = false) -> some View {
        if task.status == .done {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.success)
        } else if isLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)
        } else if task.status == .inProgress {
            Image(systemName: "circle.dotted")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentGold)
        } else if isRequired {
            Circle()
                .fill(Color.danger)
                .frame(width: 10, height: 10)
        } else {
            Circle()
                .strokeBorder(Color.textTertiary, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        }
    }

    // MARK: - Advance Section

    private var advanceSection: some View {
        VStack(spacing: 6) {
            if !canAdvance {
                let count = TaskGenerator.incompleteRequiredCount(in: tasks)
                VStack(alignment: .leading, spacing: 4) {
                    // Only claim the task list is the blocker when it actually
                    // is. A zero-count sentence over a disabled button is worse
                    // than silence — it sends the user hunting through a list
                    // where every row is already ticked (#154f).
                    //
                    // #193: and when it IS the blocker, it NAMES the row. The
                    // count alone stated the size of the problem and withheld
                    // its identity, so the user guessed — one reported case had
                    // him convinced the (optional) Big Board row was holding the
                    // draft shut while the actual gate was the salary cap. The
                    // name is the unlocked next row where there is one, so the
                    // banner never points at a step the user cannot start yet.
                    if count > 0, let blocking = blockingRequiredTask {
                        Label(
                            "Required: \(blocking.title)",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(Color.danger)
                        .fixedSize(horizontal: false, vertical: true)

                        if count > 1 {
                            Text("\(count - 1) more required task\(count == 2 ? "" : "s") after it.")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    if let blocker = advanceBlocker {
                        Label(blocker.title, systemImage: "exclamationmark.octagon.fill")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color.danger)
                        Text(blocker.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // The "Next: … / Tap to start" button that used to sit here
                    // is gone (#105 wave 2). It duplicated a row printed a few
                    // points above it, in the same panel, in the same scroll —
                    // and it was the third widget on the screen claiming to
                    // name the next move. The row wears the NEXT chip now.
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                guard canAdvance else { return }
                onAdvance()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: DSType.Size.body, weight: .bold))
                    Text(advanceButtonLabel)
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(advanceForeground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(advanceFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(
                                    isSecondaryAdvance ? Color.accentGold.opacity(0.55) : Color.clear,
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(
                            color: (canAdvance && advanceIsPrimary) ? Color.accentGold.opacity(0.3) : Color.clear,
                            radius: 8, x: 0, y: 2
                        )
                )
            }
            .disabled(!canAdvance)
            .animation(.spring(duration: 0.3), value: canAdvance)
            // A STABLE handle for the season's primary progression control.
            //
            // Its label changes every week ("Advance to Week 12", "Advance to
            // the Championship"), so any script that drives the game has to
            // match on a moving string. Worse, a QA pass this week recorded
            // "the week will not advance" as an app defect on two separate
            // careers before a coordinate tap disproved it — the semantic tap
            // resolves this control and does not actuate it. An identifier does
            // not fix that by itself, but it removes the guessing from the half
            // that IS in our control, and it is what the QA playbook asks for.
            .accessibilityIdentifier("tasks.advance")

            // Honest footnote for the secondary state: the user is one tap away
            // from having their own game played for them.
            if isSecondaryAdvance {
                Label("Your game is still unplayed — advancing sims it.",
                      systemImage: "info.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Advance is available but shouldn't wear the gold: the weekly game is
    /// still on the board and "Coach the Game" owns the primary slot.
    private var isSecondaryAdvance: Bool { canAdvance && !advanceIsPrimary }

    private var advanceFill: Color {
        guard canAdvance else { return Color.backgroundTertiary }
        return advanceIsPrimary ? Color.accentGold : Color.accentGold.opacity(0.10)
    }

    private var advanceForeground: Color {
        guard canAdvance else { return Color.textTertiary }
        return advanceIsPrimary ? Color.backgroundPrimary : Color.accentGold
    }

    private var advanceButtonLabel: String {
        let nextPhase = nextPhaseName
        switch career.currentPhase {
        case .regularSeason:
            return "Advance to Week \(career.currentWeek + 1)"
        case .playoffs:
            switch career.currentWeek {
            case 19: return "Advance to Divisional Round"
            case 20: return "Advance to Conference Championships"
            case 21: return "Advance to the Championship"
            default: return "Advance to Next Round"
            }
        case .tradeDeadline:
            return "Advance to Week \(career.currentWeek + 1)"
        default:
            return "Advance to \(nextPhase)"
        }
    }

    private var nextPhaseName: String {
        let nextIndex = currentIndex + 1
        guard nextIndex < Self.orderedPhases.count else {
            return Self.phaseName(Self.orderedPhases[0])
        }
        return Self.phaseName(Self.orderedPhases[nextIndex])
    }

    // MARK: - Upcoming Phases

    private var upcomingPhaseTasks: [(phase: SeasonPhase, name: String, date: String, tasks: [GameTask])] {
        var result: [(SeasonPhase, String, String, [GameTask])] = []

        for i in 1...upcomingPhaseCount {
            let nextIndex = currentIndex + i
            guard nextIndex < Self.orderedPhases.count else { break }
            let phase = Self.orderedPhases[nextIndex]
            let previewTasks = TaskGenerator.generateTasks(
                for: phase,
                career: career,
                team: nil,
                // NOT 53. This rail draws phases the club has not reached, and
                // a hardcoded legal roster made the camp cut-downs render as
                // already satisfied — "Cut to 75", ticked, in a preview of a
                // phase that has not happened. `nil` is the honest input: the
                // generator names the rung and leaves it unstarted (#205a §5.1).
                rosterCount: nil,
                hasPendingTradeOffers: false,
                hasHeadCoach: true,
                hasOC: true,
                hasDC: true,
                hasExpiringContracts: false,
                opponentName: nil,
                playoffRoundName: nil,
                hasScoutsAssigned: false,
                hasPendingEvents: false,
                ownerSatisfaction: 50
            )
            result.append((phase, Self.phaseName(phase), Self.phaseDate(phase), previewTasks))
        }

        return result
    }

    private func upcomingPhaseSection(_ entry: (phase: SeasonPhase, name: String, date: String, tasks: [GameTask]), isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phase header
            HStack(spacing: 10) {
                // Timeline connector
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.textTertiary.opacity(0.25))
                        .frame(width: 2, height: 8)

                    Circle()
                        .strokeBorder(Color.textTertiary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    if !isLast || remainingFutureCount > 0 {
                        Rectangle()
                            .fill(Color.textTertiary.opacity(0.25))
                            .frame(width: 2, height: 8)
                    } else {
                        Color.clear.frame(width: 2, height: 8)
                    }
                }

                Text(entry.name)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)

                Spacer()

                Text(entry.date)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            Text(groupCaption(for: entry.phase))
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.leading, 30)
                .padding(.top, 2)

            // Preview task rows (dimmed) — banner row stripped, see
            // `actionableTasks`.
            VStack(spacing: 0) {
                ForEach(Self.actionableTasks(entry.tasks)) { task in
                    previewTaskRow(task)
                }
            }
            .padding(.leading, 30)
            .padding(.trailing, 10)
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
        .opacity(0.55)
    }

    private func previewTaskRow(_ task: GameTask) -> some View {
        HStack(spacing: 8) {
            Circle()
                .strokeBorder(Color.textTertiary.opacity(0.5), lineWidth: 1)
                .frame(width: 9, height: 9)

            Text(task.title)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
    }

    // MARK: - Remaining Future Phases

    private var remainingFutureCount: Int {
        let shownUpTo = currentIndex + 1 + upcomingPhaseCount
        let total = Self.orderedPhases.count
        return max(0, total - shownUpTo)
    }

    private var remainingPhasesIndicator: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.textTertiary.opacity(0.15))
                    .frame(width: 2, height: 12)
                Circle()
                    .fill(Color.textTertiary.opacity(0.2))
                    .frame(width: 6, height: 6)
            }

            Text("+ \(remainingFutureCount) more phase\(remainingFutureCount == 1 ? "" : "s")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textTertiaryReadable)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: - Static Helpers

    /// Drops `TaskGenerator`'s read-only group-banner pseudo-task (title
    /// `"─ <Group> ─"`, always `.done`) from a task list. It is a label, not a
    /// step: the panel renders it as a caption instead — see `groupCaption`.
    static func actionableTasks(_ tasks: [GameTask]) -> [GameTask] {
        tasks.filter { !$0.title.hasPrefix("\u{2500}") }
    }

    /// **The one step counter (#134b).** Every "X/Y" the season guide prints —
    /// the rail's header pill, the Season Guide sheet's "X/Y tasks done" and the
    /// progress bar it fills — is this call and nothing else.
    ///
    /// It exists because the sheet and the rail each carried their own copy of
    /// "count the tasks", and the copies disagreed. The rail excluded
    /// `TaskGenerator`'s group banner — the read-only "─ Offseason ─" row that
    /// ships pre-`.done` — and the sheet counted it, so one six-step phase read
    /// `0/6` in the rail and `1/7` in the sheet at the same instant. The rail's
    /// denominator was the right one: the banner is a label the sheet does not
    /// even render as a card, so the sheet was counting a step it never showed,
    /// and counting it as already finished.
    ///
    /// Making both call `actionableTasks` first only made the two copies agree
    /// today. This is the seam that makes them the same number.
    static func taskProgress(_ tasks: [GameTask]) -> (done: Int, total: Int) {
        let steps = actionableTasks(tasks)
        return (steps.filter { $0.status == .done }.count, steps.count)
    }

    /// Caption under a phase header explaining what the phase's task list is.
    /// Regular-season groups repeat their list every week, which is exactly the
    /// thing the old "─ Regular Season ─" separator failed to say.
    private func groupCaption(for phase: SeasonPhase) -> String {
        switch phase.group {
        case .regularSeason:
            return "Weekly during regular season"
        default:
            let progress = phase.groupProgress
            return "\(phase.group.displayName) \u{00B7} step \(progress.current) of \(progress.total)"
        }
    }

    static func phaseName(_ phase: SeasonPhase) -> String {
        switch phase {
        case .superBowl:       return "The Championship"
        case .proBowl:         return "All-Star Game"
        case .coachingChanges: return "Coaching Changes"
        case .combine:         return "The Combine"
        case .freeAgency:      return "Free Agency"
        case .proDays:         return "Pro Days & Workouts"
        case .reviewRoster:    return "Review Roster"
        case .draft:           return "The Draft"
        case .otas:            return "OTAs"
        case .trainingCamp:    return "Training Camp"
        case .preseason:       return "Preseason"
        case .rosterCuts:      return "Roster Cuts"
        case .regularSeason:   return "Regular Season"
        case .tradeDeadline:   return "Trade Deadline"
        case .playoffs:        return "Playoffs"
        }
    }

    static func phaseDate(_ phase: SeasonPhase) -> String {
        switch phase {
        case .superBowl:       return "Feb"
        case .proBowl:         return "Feb"
        case .coachingChanges: return "Feb"
        case .combine:         return "Feb\u{2013}Mar"
        case .freeAgency:      return "Mar"
        case .proDays:         return "Apr"
        case .reviewRoster:    return "Feb"
        case .draft:           return "Apr"
        case .otas:            return "May"
        case .trainingCamp:    return "Jul\u{2013}Aug"
        case .preseason:       return "Aug"
        case .rosterCuts:      return "Aug"
        case .regularSeason:   return "Sep\u{2013}Jan"
        case .tradeDeadline:   return "Oct"
        case .playoffs:        return "Jan"
        }
    }

    static func phaseIcon(_ phase: SeasonPhase) -> String {
        switch phase {
        case .superBowl:       return "star.fill"
        case .proBowl:         return "star.circle.fill"
        case .coachingChanges: return "person.badge.key.fill"
        case .combine:         return "stopwatch.fill"
        case .freeAgency:      return "signature"
        case .proDays:         return "figure.run"
        case .reviewRoster:    return "chart.bar.doc.horizontal"
        case .draft:           return "list.clipboard.fill"
        case .otas:            return "figure.run"
        case .trainingCamp:    return "tent.fill"
        case .preseason:       return "football.fill"
        case .rosterCuts:      return "scissors"
        case .regularSeason:   return "sportscourt.fill"
        case .tradeDeadline:   return "arrow.left.arrow.right"
        case .playoffs:        return "trophy.fill"
        }
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var previewTasks: [GameTask] = TaskGenerator.generateTasks(
        for: .coachingChanges,
        career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
        team: nil,
        hasHeadCoach: false,
        hasOC: false,
        hasDC: true
    )

    TimelineTasksPanel(
        career: Career(playerName: "John Doe", role: .gm, capMode: .simple),
        tasks: $previewTasks,
        onTaskSelected: { _ in },
        onAdvance: {},
        canAdvance: false
    )
    .frame(width: 340, height: 600)
    .background(Color.backgroundPrimary)
}
