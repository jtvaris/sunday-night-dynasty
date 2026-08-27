import SwiftUI
import SwiftData

/// A unified vertical Timeline+Tasks panel inspired by Football Manager's
/// Messages panel. Shows the current phase with its tasks expanded, plus the
/// next 2-3 upcoming phases with preview tasks, and an advance button.
/// Replaces the separate `phaseTasksSection` and advance button in the dashboard.
struct TimelineTasksPanel: View {

    @Environment(\.modelContext) private var modelContext

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

    // MARK: - The rail's measurements
    //
    // Three numbers, declared once, because every row in this panel is measured
    // against them and they used to be typed in per row: the gutter shipped as
    // 14 on the header, 14 on a phase row, 12 on the advance block and 6 on the
    // wash behind the live phase, and the task list was indented by a flat 30 pt
    // that matched none of them. The result was a column whose left edge moved
    // four times between the top of the panel and the bottom of one phase.

    /// The panel's width wherever it is mounted, and the width it lays itself
    /// out for. Shared with the hub so the column and its contents cannot
    /// disagree — at 280 the longest real task title ("Set game plan for your
    /// opponent") wrapped, which made the list scan ragged.
    static let railWidth: CGFloat = 300

    /// The one horizontal gutter. Every row in the panel starts here.
    private static let gutter: CGFloat = DSSpacing.sm

    /// The timeline spine: the dot column's width plus the gap after it.
    ///
    /// Fixed rather than derived from each row's own glyph, because the glyphs
    /// differ — an 18 pt live dot, a 16 pt future ring, a 14 pt check — and a
    /// column sized by its content put three phase names on three different
    /// left edges. Every dot column takes `dotColumn` and every block of text
    /// under a phase is indented by the whole spine, so the task titles line up
    /// under the phase title instead of landing 10 pt to the right of it.
    private static let dotColumn: CGFloat = 18
    private static let spine: CGFloat = dotColumn + DSSpacing.xs

    /// Where any text nested under a phase header begins.
    private static let nestedIndent: CGFloat = gutter + spine

    /// A task row's leading status-mark column. Same reason as `dotColumn`: the
    /// four marks are a 14 pt check, an 11 pt padlock and two 10 pt discs, so a
    /// column sized by its content walked the task titles back and forth by 4 pt
    /// from row to row down a list where every title starts with a verb.
    private static let statusColumn: CGFloat = 14

    /// Completed phases are collapsed behind one disclosure row by default.
    /// Expanded, twelve struck-through rows ate most of the sidebar in Week 1
    /// and pushed the live phase (the only actionable part) below the fold.
    @State private var showCompletedPhases = false

    /// The postseason field, rebuilt by ``reloadPostseasonIfNeeded()``. `nil`
    /// outside the postseason, which is also when nothing is fetched for it.
    @State private var postseason: PostseasonBracket?

    /// The ``postseasonReloadKey`` the value above was built from. Empty until
    /// the first load, which no real key can be.
    @State private var loadedPostseasonKey = ""

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

    /// **Three decks, and the middle one is the only one that scrolls.**
    ///
    /// The advance button used to sit inside the scroll, between the live phase
    /// and the previews of the phases after it. A game week's list is six rows
    /// deep and every unfinished row carries a four-line sentence under it, so
    /// on a 1032 pt portrait iPad the season's primary progression control — and
    /// the footnote that says advancing will sim the user's own game — were
    /// below the fold on the screen the player spends the season in. The panel's
    /// own header comment already called that button "the one unmissable thing"
    /// in the column, and a QA pass twice recorded "the week will not advance"
    /// against a control that was simply off screen.
    ///
    /// The list keeps everything it had, in the order it had it; only the button
    /// left the scroll. The previews and the bracket sit under where it used to
    /// be, which is where they were.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            panelHeader
                .padding(.horizontal, Self.gutter)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.xs)

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

                    // Upcoming phases (expanded with preview tasks)
                    ForEach(Array(upcomingPhaseTasks.enumerated()), id: \.element.phase) { index, entry in
                        upcomingPhaseSection(entry, isLast: index == upcomingPhaseTasks.count - 1)
                    }

                    // Remaining collapsed future phases
                    if remainingFutureCount > 0 {
                        remainingPhasesIndicator
                    }

                    // The bracket — the rail's second panel, and the only place
                    // in the app the postseason field is drawn at all. Nil in
                    // every other phase, which is the whole of its cost then.
                    if let postseason {
                        postseasonSection(postseason)
                    }
                }
                .padding(.top, DSSpacing.xs)
                .padding(.bottom, DSSpacing.md)
            }

            Divider().overlay(Color.surfaceBorder.opacity(0.6))

            // The commit, pinned. Always the last thing down the column and
            // always on screen, whatever the list above it is doing.
            //
            // Painted on the PAGE colour rather than the rail's card surface,
            // which is what makes it a footer bar instead of a button floating
            // at the bottom of a void. On a 1376 pt portrait iPad a short phase
            // list leaves several hundred points between the last row and this
            // deck; recessed and ruled off, that gap reads as "the list ended",
            // which is what it is.
            advanceSection
                .padding(.horizontal, Self.gutter)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.sm)
                .frame(maxWidth: .infinity)
                .background(Color.backgroundPrimary)
        }
        .frame(minWidth: Self.railWidth)
        .background(Color.backgroundSecondary)
        // Two doors into one loader: the first mount (and any change made while
        // the rail was off screen) and the change made while it is on it.
        .onAppear { reloadPostseasonIfNeeded() }
        .onChange(of: postseasonReloadKey) { _, _ in reloadPostseasonIfNeeded() }
    }

    // MARK: - Panel Header

    private var panelHeader: some View {
        HStack(spacing: DSSpacing.xs) {
            // Grey, not gold. This is a standing label — it says the same word
            // all season — and it was the first of ten gold objects down a
            // column whose one unmissable thing is meant to be the advance
            // button. Gold is reserved for the live phase and the button.
            Image(systemName: "list.clipboard.fill")
                .font(.system(size: DSType.Size.body, weight: .semibold))
                .foregroundStyle(Color.textSecondary)

            Text("YOUR \(seasonLabel)")
                .font(.system(size: DSType.Size.body, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)

            Spacer()

            // Counts real steps only — the group banner is a label that ships
            // pre-`.done`, so including it read as "1/5 done" on a fresh week.
            // Shared with the Season Guide sheet (#134b): one function, one pair.
            //
            // The unit is spelled out because a bare "4/6" set against the words
            // YOUR OFFSEASON reads as four phases of six — and the same rail
            // says the offseason is fifteen phases, with a "step 2 of 2" caption
            // three rows down for good measure. Three unlabelled fractions in
            // one column is two too many.
            //
            // A phase with no required step is counted as "optional" instead:
            // the regular-season list is all-optional by design, so its pill sat
            // at "0/6" for seventeen straight weeks with nothing wrong, which is
            // the one message a progress counter must never send.
            let progress = Self.taskProgress(tasks)
            let anyRequired = Self.actionableTasks(tasks).contains { $0.isRequired }
            Text("\(progress.done)/\(progress.total) \(anyRequired ? "tasks" : "optional")")
                .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
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

    /// Every phase behind the current one.
    ///
    /// `orderedPhases` is a cycle written out flat, cut just after the
    /// Championship because that is where a dynasty year starts — which makes
    /// the two postseason phases read as "already behind you" from every row in
    /// the list. From the PLAYOFFS they are not: the engine's chain is playoffs
    /// → All-Star Game → Championship, so the rail was reporting "Phases
    /// complete (14)" directly above a button offering to advance to the
    /// Championship, counting the two rounds the club is still trying to reach.
    private var pastPhases: [(phase: SeasonPhase, name: String)] {
        guard currentIndex > 0 else { return [] }
        let postseasonStillAhead = career.currentPhase == .playoffs
        return (0..<currentIndex).compactMap { i -> (phase: SeasonPhase, name: String)? in
            let phase = Self.orderedPhases[i]
            if postseasonStillAhead, phase.group == .postseason { return nil }
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
            HStack(spacing: DSSpacing.xs) {
                VStack(spacing: 0) {
                    Color.clear.frame(width: 2, height: 6)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: DSType.Size.body))
                        .foregroundStyle(Color.success.opacity(0.7))
                    Rectangle()
                        .fill(Color.textTertiary.opacity(0.3))
                        .frame(width: 2, height: 6)
                }
                .frame(width: Self.dotColumn)

                Text("\(completedPhasesLabel) (\(pastPhases.count))")
                    .font(.system(size: DSType.Size.footnote, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                Image(systemName: showCompletedPhases ? "chevron.up" : "chevron.down")
                    .font(.system(size: DSType.Size.caption, weight: .bold))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, Self.gutter)
            .padding(.vertical, DSSpacing.xs)
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
        // Naming the group is only honest from OUTSIDE it. Standing in the
        // Championship, with "POSTSEASON · STEP 2 OF 2" printed one row below,
        // the rail was calling the postseason complete because the All-Star
        // Game behind it was the only finished phase.
        if groups.count == 1, let only = groups.first, only != career.currentPhase.group {
            return "\(only.displayName) complete"
        }
        return "Phases complete"
    }

    private func pastPhaseRow(_ entry: (phase: SeasonPhase, name: String)) -> some View {
        HStack(spacing: DSSpacing.xs) {
            // Vertical timeline connector
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.textTertiary.opacity(0.3))
                    .frame(width: 2, height: 10)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: DSType.Size.body))
                    .foregroundStyle(Color.textTertiaryReadable)

                Rectangle()
                    .fill(Color.textTertiary.opacity(0.3))
                    .frame(width: 2, height: 10)
            }
            .frame(width: Self.dotColumn)

            Text(entry.name)
                .font(.system(size: DSType.Size.footnote, weight: .medium))
                .foregroundStyle(Color.textTertiary)
                .strikethrough(true, color: Color.textTertiary.opacity(0.5))

            Spacer()

            Text("Complete")
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.textTertiaryReadable)
        }
        .padding(.horizontal, Self.gutter)
        .padding(.vertical, 2)  // ds-lint:allow(spacing) struck-through history: a collapsed list of twelve rows, not a list of steps
        .opacity(0.85)
    }

    // MARK: - Current Phase

    private var currentPhaseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phase header row
            HStack(spacing: DSSpacing.xs) {
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
                        .frame(width: Self.dotColumn, height: Self.dotColumn)
                        .overlay(
                            Image(systemName: Self.phaseIcon(career.currentPhase))
                                .font(.system(size: DSType.Size.micro, weight: .bold))
                                .foregroundStyle(Color.backgroundPrimary)
                        )

                    Rectangle()
                        .fill(Color.accentGold.opacity(0.5))
                        .frame(width: 2, height: 8)
                }
                .frame(width: Self.dotColumn)

                Text(currentPhaseTitle)
                    .font(.system(size: DSType.Size.body, weight: .heavy))
                    .foregroundStyle(Color.accentGold)
                    .textCase(.uppercase)

                Spacer()

                Text("NOW")
                    .font(.system(size: DSType.Size.caption, weight: .black))
                    .foregroundStyle(Color.backgroundPrimary)
                    .padding(.horizontal, DSSpacing.xxs)
                    .padding(.vertical, 2)  // ds-lint:allow(spacing) the NOW pill must not grow the phase row
                    .background(Capsule().fill(Color.accentGold))

                Text(Self.phaseDate(career.currentPhase))
                    .font(.system(size: DSType.Size.caption, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, Self.gutter)
            .padding(.top, DSSpacing.xs)

            // Group caption, replacing the "─ Regular Season ─" pseudo-task that
            // `TaskGenerator` pins to the top of every list. Rendered as a task
            // row it read as a struck-through step the user had somehow already
            // completed — and inside the TRADE DEADLINE / PLAYOFFS groups it
            // looked like a stray "Regular Season" item in the wrong phase.
            Text(groupCaption(for: career.currentPhase))
                .font(.system(size: DSType.Size.micro, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.leading, Self.nestedIndent)
                .padding(.top, DSSpacing.xxs)

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
            // The whole spine: the list hangs off the phase title's own left
            // edge. The flat 30 it replaces sat 8 pt short of that and 9 pt wide
            // of the connector line, so the block belonged to neither.
            //
            // It costs the titles 8 pt of measure and buys back 2 on the
            // trailing side — a net 6 of ~212, at `lineLimit(3)`, where the
            // overflow is a wrap and not a clip.
            .padding(.leading, Self.nestedIndent)
            .padding(.trailing, DSSpacing.xs)
            .padding(.top, DSSpacing.xxs)
            .padding(.bottom, DSSpacing.xxs)
        }
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.accentGold.opacity(0.04))
                .padding(.horizontal, DSSpacing.xxs)
        )
    }

    /// **What the live row is called** — the WEEK during the season, the round
    /// in the bracket, the phase everywhere else.
    ///
    /// `SeasonPhase.regularSeason` covers eighteen weeks and five months, so the
    /// header over a list of week-scoped steps ("Set game plan for Seattle")
    /// read "REGULAR SEASON · SEP–DEC" from kickoff to New Year — a label that
    /// never moved above a list that changed every week. The unit the player
    /// lives in is the week, which is the same ruling the season band is built
    /// on, so the rail names it too.
    ///
    /// The round name is `SeasonWeekBand`'s, not a second opinion: the band's
    /// postseason tail and this header would otherwise disagree about January,
    /// one saying DIVISIONAL and the other PLAYOFFS. `.tradeDeadline` keeps its
    /// own name — it is one week, and its name is the only thing that makes it
    /// different from the week before it.
    private var currentPhaseTitle: String {
        switch career.currentPhase {
        case .regularSeason: return "Week \(career.currentWeek)"
        case .playoffs:      return SeasonWeekBand.playoffRoundName(week: career.currentWeek)
        default:             return Self.phaseName(career.currentPhase)
        }
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
                HStack(spacing: DSSpacing.xs) {
                    // Status dot
                    taskStatusIcon(task, isRequired: isRequired, isLocked: locked)

                    // Task text. Baseline alignment keeps the status pill on the
                    // title's *first* line — centered, it floated mid-block on a
                    // title that wrapped, reading as if it belonged to neither line.
                    HStack(alignment: .firstTextBaseline, spacing: DSSpacing.xxs) {
                        Text(task.title)
                            .font(.system(size: DSType.Size.body, weight: done ? .regular : (locked ? .regular : .medium)))
                            .foregroundStyle(done ? Color.textTertiary : (locked ? Color.textTertiary : Color.textPrimary))
                            .strikethrough(done, color: Color.textTertiary)
                            .lineLimit(3)
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
                        } else if isRequired && !done && !isNext {
                            // Not on the NEXT row. `nextActionableTask` only
                            // ever picks a required task, so the two capsules
                            // always arrived together — and two of them plus a
                            // chevron left "Review Position Group Grades" about
                            // 85 pt to wrap into, which printed the one row the
                            // user MUST act on as "Review Position Grou…" while
                            // the banner below it spelled the name in full. The
                            // requirement is still stated on the row: the
                            // sentence underneath opens "Required to advance".
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
                // 6 not 5: with the sentence underneath, the tappable band
                // measures ~34 pt. §2.12's 44 pt row is still not met and cannot
                // be met here without pushing two steps of a six-step week off
                // the fold — reaching it needs the detail sentence to become a
                // disclosure, which is a behaviour change, not a padding change.
                .padding(.vertical, DSSpacing.xxs + 2)
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
                HStack(alignment: .top, spacing: DSSpacing.xxs) {
                    // Four, not two. Several of these sentences END on the one
                    // clause that makes them actionable — "…then confirm the
                    // review on the Schemes tab" — and at two lines a 300 pt
                    // rail cut exactly that half off, on the rows whose whole
                    // job was naming the tab that closes the task. A row whose
                    // sentence is short still draws one line; only the long
                    // ones grow.
                    Text(detailLine(for: task, isRequired: isRequired, locked: locked))
                        .font(.system(size: DSType.Size.micro, weight: .medium))
                        .foregroundStyle(Color.textTertiaryReadable)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 2)

                    // **Grey, not gold.** The chip is the row's SECONDARY move
                    // by definition — the reference screen the decision is made
                    // against, never the decision — and a six-step week drew six
                    // of them in the same hue as the one control the column
                    // exists to sell. Gold is left to three things down this
                    // rail: where the club is standing, the NEXT step, and the
                    // advance. The chip keeps its outline, which is what says it
                    // is a control at all.
                    if let secondary {
                        Button {
                            onTaskSelected(secondary.destination)
                        } label: {
                            HStack(spacing: 3) {  // ds-lint:allow(spacing) glyph-to-word inside a 20 pt chip
                                Image(systemName: secondary.icon)
                                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                                Text(secondary.label)
                                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                            }
                            .foregroundStyle(Color.textSecondary)
                            .padding(.horizontal, DSSpacing.xs)
                            .padding(.vertical, DSSpacing.xxs)
                            .background(
                                Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 1)
                            )
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .accessibilityLabel("\(secondary.label), reference for \(task.title)")
                    }
                }
                .padding(.leading, Self.statusColumn + DSSpacing.xs)
                .padding(.trailing, 2)
                .padding(.bottom, DSSpacing.xxs)
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
        Group {
            if task.status == .done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: DSType.Size.body))
                    .foregroundStyle(Color.success)
            } else if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: DSType.Size.caption))
                    .foregroundStyle(Color.textTertiary)
            } else if task.status == .inProgress {
                Image(systemName: "circle.dotted")
                    .font(.system(size: DSType.Size.body))
                    .foregroundStyle(Color.accentGold)
            } else if isRequired {
                Circle()
                    .fill(Color.danger)
                    .frame(width: 10, height: 10)  // ds-lint:allow(spacing) status disc, sized against the 14 pt check beside it
            } else {
                Circle()
                    .strokeBorder(Color.textTertiary, lineWidth: 1.5)
                    .frame(width: 10, height: 10)  // ds-lint:allow(spacing) status disc, sized against the 14 pt check beside it
            }
        }
        .frame(width: Self.statusColumn)
    }

    // MARK: - Advance Section

    private var advanceSection: some View {
        VStack(spacing: DSSpacing.xs) {
            if !canAdvance {
                let count = TaskGenerator.incompleteRequiredCount(in: tasks)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
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
                        .font(.system(size: DSType.Size.footnote, weight: .heavy))
                        .foregroundStyle(Color.dangerText)
                        .fixedSize(horizontal: false, vertical: true)

                        if count > 1 {
                            Text("\(count - 1) more required task\(count == 2 ? "" : "s") after it.")
                                .font(.system(size: DSType.Size.caption))
                                .foregroundStyle(Color.textSecondary)
                        }
                    }

                    if let blocker = advanceBlocker {
                        Label(blocker.title, systemImage: "exclamationmark.octagon.fill")
                            .font(.system(size: DSType.Size.footnote, weight: .heavy))
                            .foregroundStyle(Color.dangerText)
                        Text(blocker.detail)
                            .font(.system(size: DSType.Size.caption))
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
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: DSType.Size.body, weight: .bold))
                    Text(advanceButtonLabel)
                        .font(.system(size: DSType.Size.body, weight: .bold))
                }
                .foregroundStyle(advanceForeground)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: DSCornerRadius.card)
                        .fill(advanceFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: DSCornerRadius.card)
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
            //
            // `textSecondary` at the 11 pt caption step, not 10 pt tertiary. It
            // is the whole answer to "what happens if I skip this", it sits
            // directly under the control that does it, and it was drawn in the
            // dimmest ink on the screen — quieter than the struck-through list
            // of phases that finished months ago.
            if isSecondaryAdvance {
                Label("Your game is still unplayed — advancing sims it.",
                      systemImage: "info.circle")
                    .font(.system(size: DSType.Size.caption, weight: .medium))
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Advance is available but shouldn't wear the gold: the weekly game is
    /// still on the board and "Coach the Game" owns the primary slot.
    private var isSecondaryAdvance: Bool { canAdvance && !advanceIsPrimary }

    /// `controlDisabled`, not `backgroundTertiary`: §2.12 names one fill for a
    /// genuinely disabled control and this is it. The difference is the whole
    /// point of the token — `backgroundTertiary` is two steps up from the footer
    /// deck it now sits on and reads as a live control at a glance, while
    /// `controlDisabled` barely lifts off it. Pinned, this button is on screen
    /// for the whole of a blocked phase, so looking disabled is most of its job.
    private var advanceFill: Color {
        guard canAdvance else { return Color.controlDisabled }
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

    /// The phases the rail draws under the advance button as still ahead.
    ///
    /// Everywhere except the playoffs this is simply the next three rows of
    /// `orderedPhases`. **From the PLAYOFFS it is the wrap-around**, and it
    /// exists because `pastPhases` already refuses to call the All-Star Game and
    /// the Championship complete while the club is still trying to reach them.
    /// Without the wrap those two phases were drawn NOWHERE: excluded from
    /// "Phases complete (14)" and never listed as upcoming, so the column that
    /// promises to show the season had a hole exactly where the season's last
    /// two weeks live — under an advance button whose own label offers to move
    /// the club to the Championship.
    ///
    /// Only the postseason group wraps. Running the modulo out to three phases
    /// would put COACHING CHANGES under the button while the collapsed row
    /// above went on counting it as complete: the same phase in two places,
    /// which is the bug the exclusion was written to fix.
    private var upcomingPhases: [SeasonPhase] {
        if career.currentPhase == .playoffs {
            return SeasonPhaseGroup.postseason.subPhases
        }
        let start = currentIndex + 1
        let end = min(start + upcomingPhaseCount, Self.orderedPhases.count)
        guard start < end else { return [] }
        return Array(Self.orderedPhases[start..<end])
    }

    private var upcomingPhaseTasks: [(phase: SeasonPhase, name: String, date: String, tasks: [GameTask])] {
        var result: [(SeasonPhase, String, String, [GameTask])] = []

        // Inside the regular-season group a preview earns its rows by being what
        // the phase ADDS. The deadline week's list is deliberately an OVERLAY on
        // the weekly one (`TaskGenerator`), which is right while the deadline is
        // live and wrong in a preview: the rail printed "Review depth chart" and
        // "Check injury report" under REGULAR SEASON, again under TRADE DEADLINE
        // and again under PLAYOFFS, three headers in one column. Every other
        // group's phases carry their own lists and are previewed whole.
        var shown: Set<String> = career.currentPhase.group == .regularSeason
            ? Set(Self.actionableTasks(tasks).map(\.matchKey))
            : []

        for phase in upcomingPhases {
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
            var preview = Self.actionableTasks(previewTasks)
            if phase.group == .regularSeason {
                preview = preview.filter { !shown.contains($0.matchKey) }
                shown.formUnion(preview.map(\.matchKey))
            }
            result.append((phase, Self.phaseName(phase), Self.phaseDate(phase), preview))
        }

        return result
    }

    private func upcomingPhaseSection(_ entry: (phase: SeasonPhase, name: String, date: String, tasks: [GameTask]), isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Phase header
            HStack(spacing: DSSpacing.xs) {
                // Timeline connector
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.textTertiary.opacity(0.25))
                        .frame(width: 2, height: 8)

                    Circle()
                        .strokeBorder(Color.textTertiary.opacity(0.4), lineWidth: 1.5)
                        .frame(width: 16, height: 16)  // ds-lint:allow(spacing) hollow future ring, one point inside the live dot

                    if !isLast || remainingFutureCount > 0 {
                        Rectangle()
                            .fill(Color.textTertiary.opacity(0.25))
                            .frame(width: 2, height: 8)
                    } else {
                        Color.clear.frame(width: 2, height: 8)
                    }
                }
                .frame(width: Self.dotColumn)

                Text(entry.name)
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)

                Spacer()

                Text(entry.date)
                    .font(.system(size: DSType.Size.caption, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            .padding(.horizontal, Self.gutter)
            .padding(.top, DSSpacing.xs)

            Text(groupCaption(for: entry.phase))
                .font(.system(size: DSType.Size.caption, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .textCase(.uppercase)
                .tracking(0.4)
                .padding(.leading, Self.nestedIndent)
                .padding(.top, 2)

            // Preview task rows (dimmed) — banner row stripped, see
            // `actionableTasks`.
            VStack(alignment: .leading, spacing: 0) {
                let preview = Self.actionableTasks(entry.tasks)
                if preview.isEmpty {
                    // **Says why it is empty.** Inside the regular-season group
                    // a preview is deliberately only what the phase ADDS to the
                    // weekly list (see `upcomingPhaseTasks`), and a deadline week
                    // that adds nothing left a header, a caption and then a gap —
                    // which reads as a list that failed to load rather than as a
                    // week that asks for the same seven things this one does.
                    Text(emptyPreviewLine(for: entry.phase))
                        .font(.system(size: DSType.Size.footnote))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, DSSpacing.xxs)
                } else {
                    ForEach(preview) { task in
                        previewTaskRow(task)
                    }
                }
            }
            .padding(.leading, Self.nestedIndent)
            .padding(.trailing, DSSpacing.xs)
            .padding(.top, 2)
            .padding(.bottom, 2)
        }
        .opacity(0.55)
    }

    /// Why an upcoming phase drew no preview rows.
    private func emptyPreviewLine(for phase: SeasonPhase) -> String {
        phase.group == .regularSeason
            ? "Same weekly list \u{2014} nothing new to prepare"
            : "No steps to preview yet"
    }

    private func previewTaskRow(_ task: GameTask) -> some View {
        HStack(spacing: DSSpacing.xs) {
            Circle()
                .strokeBorder(Color.textTertiary.opacity(0.5), lineWidth: 1)
                .frame(width: 9, height: 9)  // ds-lint:allow(spacing) preview disc, one step under the live list's 10 pt
                .frame(width: Self.statusColumn)

            // Two lines: at one, a 300 pt rail was clipping four characters off
            // "Read the Showcase & declaration report" — a preview row that
            // costs a second line only when the title actually needs one.
            Text(task.title)
                .font(.system(size: DSType.Size.footnote, weight: .regular))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.vertical, 3)  // ds-lint:allow(spacing) dimmed preview: half the live row's rhythm, on purpose
    }

    // MARK: - Remaining Future Phases

    private var remainingFutureCount: Int {
        let shownUpTo = currentIndex + 1 + upcomingPhaseCount
        let total = Self.orderedPhases.count
        return max(0, total - shownUpTo)
    }

    private var remainingPhasesIndicator: some View {
        HStack(spacing: DSSpacing.xs) {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.textTertiary.opacity(0.15))
                    .frame(width: 2, height: 12)
                Circle()
                    .fill(Color.textTertiary.opacity(0.2))
                    .frame(width: 6, height: 6)  // ds-lint:allow(spacing) the spine's terminal dot, smallest mark on the rail
            }
            .frame(width: Self.dotColumn)

            Text("+ \(remainingFutureCount) more phase\(remainingFutureCount == 1 ? "" : "s")")
                .font(.system(size: DSType.Size.caption, weight: .medium))
                .foregroundStyle(Color.textTertiaryReadable)

            Spacer()
        }
        .padding(.horizontal, Self.gutter)
        .padding(.top, DSSpacing.xs)
    }

    // MARK: - Postseason Bracket
    //
    // The rail's second panel. It exists because of what the first one runs out
    // of: at the playoffs the timeline is standing on the LAST row of
    // `orderedPhases`, its phase list is three optional tasks long, and the
    // advance button lands around 45% of the way down a portrait iPad. The
    // bottom half of the column was empty for the four most consequential weeks
    // of the year.
    //
    // What fills it is the one thing the app models and never draws. The
    // bracket is real — `WeekAdvancer.ensurePlayoffGames` stages it as `Game`
    // rows a round at a time — but no screen shows it: `ScheduleView` filters
    // `!isPlayoff` out of its slate, `StandingsView` draws a seed ladder rather
    // than pairings, and the dashboard's own playoffs hero card names the user's
    // round, seed and opponent and then hands off with a "View Bracket" link
    // that opens the standings table.
    //
    // So this panel deliberately does NOT restate the hero card. No "your
    // seed", no "your matchup", no opponent dossier — the seed and the matchup
    // are the hero card's job (#105 wave 2: one widget per fact), and the
    // opponent's scouting readout is the Game Plan screen's, which the live
    // phase's own first task links to. What is left is the part nobody owns:
    // the whole field, both conferences, who is left, and where the user's own
    // game sits inside it.

    /// True while there is a bracket to draw: the three rounds of `.playoffs`,
    /// plus the All-Star and Championship weeks, where the final is staged and
    /// the rest of the field is settled history.
    private var postseasonIsLive: Bool {
        career.currentPhase == .playoffs || career.currentPhase.group == .postseason
    }

    /// Everything that can change what the bracket says.
    ///
    /// The week and the phase cover the advance, which is what plays a round.
    /// `advanceIsPrimary` covers the other door: it is the dashboard's "your own
    /// game for this week is still unplayed", so it flips the moment the user
    /// COACHES a playoff game — the one way a score reaches the board without
    /// the calendar moving. Without it the rail would draw the user's own game
    /// as unstarted while the hero card six inches to its right printed the
    /// final score, which is the #154 bug class exactly.
    private var postseasonReloadKey: String {
        "\(career.currentSeason)-\(career.currentWeek)-\(career.currentPhase.rawValue)-\(advanceIsPrimary)"
    }

    /// Rebuilds ``postseason`` — **once per change, never per body pass and
    /// never on a bare re-appearance.**
    ///
    /// Seeding walks a full season of games through `StandingsCalculator`, and
    /// this panel redraws every time a task is ticked. The key check is what
    /// makes `.onAppear` safe to attach: the rail re-appears on every pop back
    /// from a pushed screen, and a 280-row fetch on the main thread during a
    /// pop animation is the jank the dashboard's own `refreshStaffTile` exists
    /// to avoid. Nothing the user can do from another screen moves the
    /// bracket, so an unchanged key is an unchanged answer.
    ///
    /// Outside the postseason the whole thing costs one enum comparison.
    private func reloadPostseasonIfNeeded() {
        let key = postseasonReloadKey
        guard key != loadedPostseasonKey else { return }
        loadedPostseasonKey = key

        guard postseasonIsLive else {
            postseason = nil
            return
        }
        let cid = career.id
        let season = career.currentSeason
        // ONE fetch for both halves of the answer. Seeding is a regular-season
        // question and `StandingsCalculator.calculate` drops the bracket rows
        // itself — and the rows it drops are the pairings, so fetching the
        // season whole is cheaper than fetching it twice with two predicates.
        let gameDescriptor = FetchDescriptor<Game>(predicate: #Predicate<Game> {
            $0.careerID == cid && $0.seasonYear == season
        })
        let games = (try? modelContext.fetch(gameDescriptor)) ?? []
        let teamDescriptor = FetchDescriptor<Team>(predicate: #Predicate<Team> {
            $0.careerID == cid
        })
        let teams = (try? modelContext.fetch(teamDescriptor)) ?? []
        postseason = PostseasonBracket.build(
            games: games,
            teams: teams,
            userTeamID: career.teamID
        )
    }

    private func postseasonSection(_ bracket: PostseasonBracket) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .overlay(Color.surfaceBorder.opacity(0.6))
                .padding(.top, DSSpacing.md)

            // Deliberately the same object as `panelHeader`: two panels stacked
            // in one 300 pt rail only read as siblings if their headers do.
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: DSType.Size.body, weight: .semibold))
                    .foregroundStyle(Color.textSecondary)

                Text("THE BRACKET")
                    .font(.system(size: DSType.Size.body, weight: .bold))
                    .foregroundStyle(Color.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                // The unit is spelled out for the reason the task counter's is
                // (see `panelHeader`): a bare figure in a column that also
                // prints seeds and scores is a number with no noun.
                Text("\(bracket.clubsLeft) alive")
                    .font(.system(size: DSType.Size.caption, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, Self.gutter)
            .padding(.top, DSSpacing.sm)

            // Drawn only when the user is OUT — see `PostseasonBracket.userLine`.
            if let line = bracket.userLine {
                Text(line)
                    .font(.system(size: DSType.Size.micro, weight: .semibold))
                    .foregroundStyle(Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .padding(.horizontal, Self.gutter)
                    .padding(.top, 3)
            }

            ForEach(bracket.rounds) { round in
                bracketRoundSection(round)
            }

            // The panel's one exit. Same shape as a task row's scoped secondary
            // chip: the bracket says who is playing, the table says why they are
            // seeded where they are.
            HStack {
                Spacer()
                Button {
                    onTaskSelected(.standings)
                } label: {
                    HStack(spacing: 3) {  // ds-lint:allow(spacing) glyph-to-word inside a 20 pt chip
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                        Text("Full standings")
                            .font(.system(size: DSType.Size.micro, weight: .semibold))
                    }
                    .foregroundStyle(Color.textSecondary)
                    .padding(.horizontal, DSSpacing.xs)
                    .padding(.vertical, DSSpacing.xxs)
                    .background(
                        Capsule().strokeBorder(Color.surfaceBorder, lineWidth: 1)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Full standings, with conference seeding")
            }
            .padding(.horizontal, Self.gutter)
            .padding(.top, DSSpacing.xs)
        }
    }

    private func bracketRoundSection(_ round: PostseasonBracket.Round) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Round header, ruled off to the panel edge so four rounds read as
            // four bands rather than as one list of twelve games.
            HStack(spacing: 8) {
                // `SeasonWeekBand` already names these four weeks for the shell's
                // week ladder. Borrowed rather than re-tabled: the ladder and the
                // bracket are two views of one postseason and must not drift.
                Text(SeasonWeekBand.playoffRoundName(week: round.week))
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
                    .foregroundStyle(round.isStaged ? Color.textSecondary : Color.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Rectangle()
                    .fill(Color.surfaceBorder)
                    .frame(height: 1)
            }
            .padding(.top, 10)

            if round.isStaged {
                ForEach(round.groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        if let conference = group.conference {
                            Text(conference.rawValue)
                                .font(.system(size: DSType.Size.micro, weight: .bold))
                                .foregroundStyle(Color.textTertiaryReadable)
                                .tracking(0.4)
                        }
                        ForEach(group.matchups) { matchup in
                            bracketMatchupCard(matchup)
                        }
                    }
                    .padding(.top, 6)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // The clubs that are already through. Only the #1 seed sits
                    // out a round, so this is at most one line per conference —
                    // and it is the half of an unplayed round that IS knowable.
                    if !round.byes.isEmpty {
                        VStack(spacing: 3) {
                            ForEach(round.byes) { side in
                                bracketSideRow(side, isDimmed: false, badge: "BYE")
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                                .fill(Color.backgroundPrimary.opacity(0.5))
                        )
                    }

                    if let note = round.pendingNote {
                        Text(note)
                            .font(.system(size: DSType.Size.micro, weight: .medium))
                            .foregroundStyle(Color.textTertiaryReadable)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, Self.gutter)
    }

    private func bracketMatchupCard(_ matchup: PostseasonBracket.Matchup) -> some View {
        VStack(spacing: 3) {
            bracketSideRow(matchup.home, isDimmed: matchup.isPlayed && !matchup.home.isWinner)
            bracketSideRow(matchup.away, isDimmed: matchup.isPlayed && !matchup.away.isWinner)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: DSCornerRadius.inline)
                .fill(Color.backgroundPrimary.opacity(0.5))
        )
        .overlay(alignment: .leading) {
            // The user's own game, marked once. A gold rule rather than gold
            // text on both lines: the panel header's rule is that gold belongs
            // to the live phase and the advance button, and one 2 pt bar is the
            // smallest thing that can say "this one is yours" without joining
            // the competition for the eye.
            if matchup.involvesUser {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentGold)
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(matchup.spokenLabel)
    }

    /// One club on one line: seed, code, nickname, record, and either the score
    /// or a badge.
    private func bracketSideRow(
        _ side: PostseasonBracket.Side,
        isDimmed: Bool,
        badge: String? = nil
    ) -> some View {
        // Hoisted out of the view builder: three nested ternaries inside
        // `.foregroundStyle` is the shape that makes the type checker crawl.
        let primaryInk: Color = isDimmed ? .textTertiary : .textPrimary
        let codeInk: Color = side.isUser ? .accentGold : primaryInk
        let nameInk: Color = isDimmed ? .textTertiary : .textSecondary

        return HStack(spacing: 6) {
            // No tone on the seed. `StandingsView` paints one because its ladder
            // holds all 16 clubs in a conference and the pill states a threshold
            // — top 7 are in. Every club on this panel cleared that threshold by
            // being here, so the number is an ordinal and nothing else.
            Text(side.seed.map { "#\($0)" } ?? "\u{2014}")
                .font(DSType.display(DSType.Size.micro, .heavy))
                .foregroundStyle(Color.textTertiaryReadable)
                .frame(width: 22, alignment: .leading)

            Text(side.abbreviation)
                .font(DSType.display(DSType.Size.footnote, .bold))
                .foregroundStyle(codeInk)
                .frame(width: 34, alignment: .leading)

            Text(side.nickname)
                .font(.system(size: DSType.Size.caption, weight: .medium))
                .foregroundStyle(nameInk)
                .lineLimit(1)

            Spacer(minLength: 4)

            // The regular-season record, which is the only thing that separates
            // two unplayed names on a card the user has no other read on.
            Text(side.record)
                .font(.system(size: DSType.Size.micro, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.textTertiaryReadable)

            if let score = side.score {
                Text("\(score)")
                    .font(.system(size: DSType.Size.footnote, weight: side.isWinner ? .heavy : .medium).monospacedDigit())
                    .foregroundStyle(primaryInk)
                    .frame(width: 26, alignment: .trailing)
            } else if let badge {
                Text(badge)
                    .font(.system(size: DSType.Size.micro, weight: .heavy))
                    .foregroundStyle(Color.textTertiaryReadable)
                    .frame(width: 26, alignment: .trailing)
            }
        }
        .opacity(isDimmed ? 0.75 : 1)
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
        // Switched on the PHASE, not its group. `SeasonPhase.group` files the
        // playoffs under `.regularSeason` alongside the weekly phases, so a
        // group-level switch printed "WEEKLY DURING REGULAR SEASON" under a
        // PLAYOFFS header in January — a caption that was wrong twice in five
        // words. The playoff list does repeat, just per round rather than per
        // week, and what it repeats for is worth saying.
        switch phase {
        case .regularSeason, .tradeDeadline:
            return "Weekly during regular season"
        case .playoffs:
            return "Each playoff round \u{00B7} win or go home"
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
        // The rail is read top to bottom as a calendar, so these have to climb.
        // They did not: REGULAR SEASON ran "Sep–Jan" over TRADE DEADLINE "Oct"
        // over PLAYOFFS "Jan", i.e. the row below started inside the row above
        // and the row below that repeated its last month. The season now stops
        // short of the postseason's month, and the deadline — which is genuinely
        // a single week INSIDE the season above it, not a month beside it — says
        // so in the panel's own regular-season unit. `deadlineWeek` because the
        // month was wrong too: week 9 falls in November.
        case .regularSeason:   return "Sep\u{2013}Dec"
        case .tradeDeadline:   return "Wk \(TradeValueEngine.deadlineWeek)"
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

// MARK: - Postseason Bracket Model

/// The postseason reduced to what a 300 pt rail can draw.
///
/// Built once per load by `TimelineTasksPanel.reloadPostseason()` and held in
/// `@State` — never assembled inside `body`, because the seeding pass it opens
/// with reads a whole season of games.
///
/// The seeds are `StandingsCalculator.playoffTeams`, i.e. the same call
/// `WeekAdvancer.ensurePlayoffGames` staged the bracket FROM. That is the point:
/// a panel that derived seeding its own way could print "#5 at #4" over a
/// pairing the engine had staged the other way round, and the two would both be
/// telling the truth about different arithmetic.
private struct PostseasonBracket {

    /// One club on one line of the bracket.
    struct Side: Identifiable {
        /// The team id — a club appears at most once per round.
        let id: UUID
        let abbreviation: String
        let nickname: String
        /// Regular-season record. Playoff results never touch `Team.wins`
        /// (R32), so this stays the seeding record all postseason.
        let record: String
        /// 1…7 in its own conference. `nil` only for a club the seeding pass
        /// cannot place — the same legacy-save case `ensurePlayoffGames` falls
        /// back on rather than refusing to stage a round.
        let seed: Int?
        let score: Int?
        let isWinner: Bool
        let isUser: Bool
    }

    struct Matchup: Identifiable {
        /// The `Game` id.
        let id: UUID
        /// `nil` for the Championship — the one cross-conference game.
        let conference: Conference?
        let home: Side
        let away: Side
        let isPlayed: Bool

        var involvesUser: Bool { home.isUser || away.isUser }

        /// The seed this pairing sorts on: brackets read best-seed-first.
        var bestSeed: Int { min(home.seed ?? 99, away.seed ?? 99) }

        /// VoiceOver reads the card as one sentence — two names, two seeds and
        /// the result — rather than as eight unlabelled fragments.
        var spokenLabel: String {
            func phrase(_ side: Side) -> String {
                let seed = side.seed.map { "seed \($0) " } ?? ""
                let score = side.score.map { ", \($0)" } ?? ""
                return "\(seed)\(side.nickname)\(score)"
            }
            let pairing = "\(phrase(home)) versus \(phrase(away))"
            guard isPlayed else { return pairing }
            if home.isWinner { return "\(pairing). \(home.nickname) win." }
            if away.isWinner { return "\(pairing). \(away.nickname) win." }
            return "\(pairing). Tied."
        }
    }

    /// One conference's half of a round. The Championship is the group with no
    /// conference.
    struct ConferenceGroup: Identifiable {
        let conference: Conference?
        let matchups: [Matchup]

        var id: String { conference?.rawValue ?? "final" }
    }

    struct Round: Identifiable {
        /// 19…22, the weeks `WeekAdvancer.ensurePlayoffGames` stages.
        let week: Int
        let groups: [ConferenceGroup]
        /// Clubs already through with nobody to play yet — the #1 seeds during
        /// Wild Card weekend. Only ever non-empty on an unstaged round.
        let byes: [Side]
        /// What decides this round, drawn while it has no games.
        let pendingNote: String?

        var id: Int { week }
        var isStaged: Bool { !groups.isEmpty }
    }

    let rounds: [Round]
    /// Seeded clubs that have not lost a playoff game.
    let clubsLeft: Int
    /// The user's standing in the field — **only when they are not in it.**
    ///
    /// A club still alive is already marked, on its own card, by the gold rule;
    /// saying "you are the #2 seed" as well would be a third copy of a fact the
    /// hero card also prints. What the highlight cannot express is its own
    /// absence, so the two out-states get a line and the live one does not.
    let userLine: String?

    // MARK: Build

    static func build(games: [Game], teams: [Team], userTeamID: UUID?) -> PostseasonBracket? {
        guard !teams.isEmpty else { return nil }

        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        let records = StandingsCalculator.calculate(games: games, teams: teams)

        var seedByTeam: [UUID: Int] = [:]
        var topSeedByConference: [Conference: UUID] = [:]
        for conference in Conference.allCases {
            let seeded = StandingsCalculator.playoffTeams(
                records: records,
                teams: teams,
                conference: conference
            )
            for (index, record) in seeded.enumerated() {
                seedByTeam[record.teamID] = index + 1
            }
            topSeedByConference[conference] = seeded.first?.teamID
        }
        // A league whose seeding cannot be computed has no bracket to draw, and
        // an empty panel is better than one full of em dashes.
        guard !seedByTeam.isEmpty else { return nil }

        let playoffGames = games.filter(\.isPlayoff)
        let eliminated = Set(playoffGames.compactMap(\.loserID))

        func makeSide(_ teamID: UUID, score: Int?, isWinner: Bool) -> Side? {
            guard let team = teamsByID[teamID] else { return nil }
            return Side(
                id: teamID,
                abbreviation: team.abbreviation,
                nickname: team.name,
                record: team.record,
                seed: seedByTeam[teamID],
                score: score,
                isWinner: isWinner,
                isUser: teamID == userTeamID
            )
        }

        // The user's conference leads every round, because the half of the
        // bracket he can still be in is the half he is reading for.
        let userConference = userTeamID.flatMap { teamsByID[$0]?.conference }
        let orderedConferences: [Conference] = {
            guard let userConference else { return Conference.allCases }
            return [userConference] + Conference.allCases.filter { $0 != userConference }
        }()

        var rounds: [Round] = []
        for week in 19...22 {
            var matchups: [Matchup] = []
            for game in playoffGames where game.week == week {
                guard
                    let home = makeSide(
                        game.homeTeamID,
                        score: game.homeScore,
                        isWinner: game.winnerID == game.homeTeamID
                    ),
                    let away = makeSide(
                        game.awayTeamID,
                        score: game.awayScore,
                        isWinner: game.winnerID == game.awayTeamID
                    )
                else { continue }

                let homeConference = teamsByID[game.homeTeamID]?.conference
                let awayConference = teamsByID[game.awayTeamID]?.conference
                matchups.append(Matchup(
                    id: game.id,
                    conference: homeConference == awayConference ? homeConference : nil,
                    home: home,
                    away: away,
                    isPlayed: game.isPlayed
                ))
            }
            matchups.sort { $0.bestSeed < $1.bestSeed }

            var groups: [ConferenceGroup] = []
            for conference in orderedConferences {
                let inConference = matchups.filter { $0.conference == conference }
                if !inConference.isEmpty {
                    groups.append(ConferenceGroup(conference: conference, matchups: inConference))
                }
            }
            let crossConference = matchups.filter { $0.conference == nil }
            if !crossConference.isEmpty {
                groups.append(ConferenceGroup(conference: nil, matchups: crossConference))
            }

            // Only the Divisional round has a knowable half before it is staged:
            // the two #1 seeds are already in it, which is what their bye IS.
            var byes: [Side] = []
            if groups.isEmpty, week == 20 {
                byes = orderedConferences.compactMap { conference in
                    guard let teamID = topSeedByConference[conference] else { return nil }
                    return makeSide(teamID, score: nil, isWinner: false)
                }
            }

            rounds.append(Round(
                week: week,
                groups: groups,
                byes: byes,
                pendingNote: groups.isEmpty ? pendingNote(week: week) : nil
            ))
        }

        let userSeed = userTeamID.flatMap { seedByTeam[$0] }
        let userExitWeek = userTeamID.flatMap { teamID in
            playoffGames.first { $0.loserID == teamID }?.week
        }
        let userLine: String? = {
            guard userTeamID != nil else { return nil }
            if let userExitWeek {
                return "Eliminated \u{00B7} \(SeasonWeekBand.playoffRoundName(week: userExitWeek))"
            }
            return userSeed == nil ? "Your club is not in the field" : nil
        }()

        return PostseasonBracket(
            rounds: rounds,
            clubsLeft: max(0, seedByTeam.count - eliminated.count),
            userLine: userLine
        )
    }

    /// What an unstaged round is waiting on. Phrased as the rule that fills it,
    /// not as "TBD" — the rule is the part the user can plan against.
    private static func pendingNote(week: Int) -> String {
        switch week {
        // Week 19 is staged by the advance that ENTERS the playoffs, so this
        // line only ever reaches a save that crossed into the postseason before
        // the bracket was persisted (R32). `advancePlayoffWeek` self-heals it.
        case 19:  return "Bracket not staged \u{2014} the next advance sets it."
        case 20:  return "The three Wild Card winners join the top seed in each conference."
        case 21:  return "The Divisional winners meet, better seed at home."
        default:  return "The two conference champions meet."
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
    // The bracket panel reads the store through `@Environment(\.modelContext)`.
    // The preview stands in `.coachingChanges`, so it never fetches — but the
    // environment has to resolve for the view to build at all.
    .modelContainer(for: [Career.self, Game.self, Team.self], inMemory: true)
}
