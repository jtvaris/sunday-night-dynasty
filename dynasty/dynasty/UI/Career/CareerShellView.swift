import SwiftUI
import SwiftData

/// Outer container that holds the persistent TopNavigationBar,
/// the main NavigationStack content area, and the CalendarSidebarView.
/// Now integrates with `TaskGenerator` to drive the guided wizard/task system.
struct CareerShellView: View {

    @Bindable var career: Career

    /// Where the shell opens, when whatever presented it has already decided the
    /// player's first stop.
    ///
    /// The career intro's staff CTA hands over on `.hireHC` (#2959): the
    /// briefing's "0 / N filled" row can end the intro and put the player in the
    /// staff room, rather than naming a job it has no way to start. Routed
    /// through `handleTaskNavigation`, so the CTA lands on exactly the screen
    /// the "Hire Head Coach" task row lands on and the two cannot drift apart.
    /// `nil` opens the hub, which is how every other entry into the shell
    /// behaves.
    var openingRoute: TaskDestination? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - The two modal slots (#105 wave 5c, §2.8 + the recurring bug class)
    //
    // The shell used to mount **four separate `.sheet` modifiers and four
    // separate `.fullScreenCover` modifiers** on one view. That is the failure
    // this codebase has now been bitten by four times: sibling presentation
    // modifiers in a single hierarchy are not independent, and the loser of a
    // race is dismissed *silently* — no crash, no log, just a modal that never
    // appears or vanishes the instant it does. Every one of the workarounds
    // above (the `revealPresented` hold-back, the `!showWeeklyPressConference`
    // guard, the 0.4 s `asyncAfter`) was written to keep two of those eight
    // modifiers off each other.
    //
    // There is now **one sheet slot and one cover slot**, both `item`-driven.
    // Two things follow for free: a second presentation cannot appear while a
    // first is up (the enum holds one value), and handing the slot from one
    // modal to the next is an assignment in `onDismiss` rather than a timer.
    //
    // The payloads stay in their own `@State` — the enum is a tag, not a box —
    // because several of them are read by code that has nothing to do with
    // presentation (`pendingRoundResults` is assembled an advance early,
    // `pendingHoldout` gates re-detection).

    /// The one sheet slot: a short, cancellable side-task (§2.8's table).
    private enum ShellSheet: String, Identifiable {
        case calendar
        case voluntaryWorkout
        case ownerReview
        case holdout
        /// §2.6: the standard ending. A process that terminates in the shell
        /// puts its outcome here instead of inventing a fifth way to say "done".
        case result
        /// #200: app settings, opened from the top bar's gear. A side task in
        /// the purest sense — nothing in the career changes, and it ends by
        /// being closed. It takes the existing slot rather than a sixth
        /// `.sheet` modifier for the reason the whole comment above exists.
        case settings

        var id: String { rawValue }
    }

    /// The one cover slot: a *process* — it has steps, owns the screen, and
    /// ends in a result (§2.8's table).
    private enum ShellCover: String, Identifiable {
        case press
        case roundResults
        case rookieReveal
        case fired

        var id: String { rawValue }
    }

    @State private var shellSheet: ShellSheet?
    @State private var shellCover: ShellCover?

    /// The Season Guide's open height. Bound rather than left to SwiftUI, which
    /// picks the SMALLEST detent in the set: on a 13" iPad the sheet opened at
    /// `.medium` and cut the required-task row in half at the card's bottom
    /// edge, with the task list, the optional section and Advance all below the
    /// fold. Opens at `.large`; `.medium` stays draggable.
    @State private var calendarDetent: PresentationDetent = .large

    /// What was in the slot last, so the single `onDismiss` can tell which
    /// modal just left. `item`-driven presentation nils the binding *before*
    /// `onDismiss` runs, so the case has to be remembered on the way in.
    @State private var lastShellSheet: ShellSheet?
    @State private var lastShellCover: ShellCover?

    /// The week's voluntary-workout prompt, *queued* rather than written
    /// straight into the slot.
    ///
    /// An OTAs advance can raise a holdout dialog (or an owner review) in the
    /// same synchronous pass, and one slot holds one thing: assigning it twice
    /// meant the prompt was overwritten before SwiftUI ever presented it and
    /// the week's workout selection was silently never made. The request now
    /// outlives whatever else took the slot and is staged by
    /// `stageWorkoutPromptIfFree()` from the dismissal handlers.
    @State private var workoutPromptArmed = false

    /// The payload of the `.result` sheet — §2.6's one termination pattern.
    @State private var pendingResult: ShellResult?

    /// A shell-terminated process's outcome, in `DSResultSheet`'s own terms.
    struct ShellResult: Identifiable {
        let id = UUID()
        var tone: DSResultSheet.Tone = .neutral
        var eyebrow: String
        var headline: String
        var message: String?
        var chips: [DSResultSheet.Chip] = []
        var cost: String?
    }

    @State private var showQuitConfirmation = false
    @State private var team: Team?
    @State private var upcomingGames: [Game] = []

    /// **The one fixture every week-scoped label in the career reads** (#154).
    ///
    /// This week's game whether or not it has been played, falling back to the
    /// next one scheduled — exactly the pick `CareerDashboardView`'s hero card
    /// makes. `upcomingGames.first` is NOT that fixture: it only holds unplayed
    /// games, so the moment Sunday's result lands it jumps to next week's
    /// opponent. That is how one dashboard came to name three different clubs at
    /// once — hero "Week 16 · @ SF", Opponent Scout tile "Vs IND", task list
    /// "Set game plan for Seattle Evergreens".
    @State private var currentWeekGame: Game?
    @State private var allTeamsByID: [UUID: Team] = [:]

    /// The user's schedule for this season, keyed by week — the data behind the
    /// season week ladder (`SeasonWeekBandView`, P1's iteration-2 amendment).
    /// A week with no entry is a bye. Refilled by `loadShellData`, which is also
    /// the post-advance reload, so the ladder moves with the calendar.
    @State private var seasonFixtures: [Int: SeasonWeekBand.Fixture] = [:]

    /// Navigation path for bookmark quick-nav.
    @State private var navigationPath = NavigationPath()

    /// #37: set true when the Game Plan screen's "Start Game" button asks us to
    /// pop back to the dashboard and launch the coached game. The dashboard
    /// observes this and consumes it (see `launchCoachedGame`).
    @State private var requestCoachedLaunch = false

    /// The current list of tasks for the active phase, persisted across view
    /// updates. Regenerated when the phase changes.
    @State var currentTasks: [GameTask] = []

    /// Tracks the last phase we generated tasks for, so we can detect phase changes.
    @State private var lastGeneratedPhase: SeasonPhase?

    /// Tracks the week the list was generated for (#154).
    ///
    /// A phase alone is not enough identity for the regular season: it stays
    /// `.regularSeason` for eighteen weeks, so a list built once at kickoff went
    /// on naming Week 1's opponent — "Set game plan for Seattle Evergreens" over a
    /// Week 16 trip to San Francisco — until a phase flip happened to rebuild it.
    @State private var lastGeneratedWeek: Int?

    /// Accumulated inbox messages across all phase transitions, OLDEST FIRST.
    ///
    /// Wave 3: this is a mirror of `career.inbox`, not the storage. It used to
    /// be the only copy, which meant the whole mailbox died with the view — a
    /// draft-day trade notice generated inside the draft-room modal never
    /// reached it (task #19), and closing the career threw the rest away.
    @State var inboxMessages: [InboxMessage] = []

    /// Pending weekly press conference questions (shown after advancing a regular-season week).
    @State private var pendingPressQuestions: [PressQuestion]?
    /// #161: the engine context those questions were generated in.
    @State private var pendingPressContext: PressConferenceEngine.PressContext?

    /// #38 — Post-game round recap (this week's scores + power ranking + MVP
    /// race + storylines), assembled after each regular-season advance from
    /// existing state. Presented once per week, after any press conference,
    /// and always dismisses straight back to the dashboard.
    @State private var pendingRoundResults: RoundResultsView.Data?

    /// **The route a closing modal asked the shell to travel** (§2.8).
    ///
    /// Two of the shell's presentations end by sending the user somewhere: the
    /// round recap ("See standings" / "See news") and the calendar sheet (every
    /// task row). Both used to push straight from the button handler and then
    /// wrap the push in a 0.35 s `asyncAfter`, because a destination pushed
    /// while the modal is still on screen lands *behind* it and the timer was
    /// there to out-wait the dismissal animation — a guess that is too long on
    /// a fast device and too short on a loaded one.
    ///
    /// The route is recorded here instead and travelled from the presentation's
    /// `onDismiss`, which fires when the modal has actually gone. One slot is
    /// enough: the recap and the calendar can never be on screen together.
    @State private var pendingRoute: ShellDestination?

    /// **The calendar asked for a week advance as it closed** (§2.8, same rule
    /// as `pendingRoute`).
    ///
    /// The sheet's Advance button used to run `shellSheet = nil` and
    /// `performShellAdvance()` back to back in one runloop, and the advance
    /// re-stages the very slot that is mid-dismissal (`.ownerReview`,
    /// `.holdout`). `onChange` then recorded the INCOMING case in
    /// `lastShellSheet` before the calendar's `onDismiss` had run, so the
    /// handler tore down the modal that was arriving: the owner review was
    /// stamped acknowledged and shown blank, and a persisted holdout lost its
    /// only dialog. The request is recorded here and served from `onDismiss`,
    /// when the slot is genuinely free.
    @State private var pendingAdvanceAfterCalendar = false

    // FA Drama Phase 5 — Holdout dialog state.
    @State private var pendingHoldout: Holdout?
    @State private var pendingHoldoutPlayer: Player?
    @State private var pendingHoldoutMarketValue: Int = 0

    // R31 — Owner review sheet + firing screen state.
    @State private var pendingOwnerReview: OwnerPersonaEngine.OwnerSeasonReview?

    // Phase 4 faces — the full store-wide portrait reconciliation is a
    // once-per-opened-save job, not a per-advance one (see `loadFaceLibrary`).
    @State private var didReconcileFaces = false

    /// Set when `performShellAdvance` refuses to start the season on an
    /// over-limit roster. Presented as an alert, cleared on dismissal.
    @State private var pendingRosterLimit: WeekAdvancer.RosterLimitViolation?

    /// #158: the club's staff gate, refreshed alongside the task statuses.
    ///
    /// `performShellAdvance` refuses on it, and the predicate itself lives on
    /// ``StaffLedger/advanceBlocker(phase:)`` so the dashboard's own button
    /// reads the same one rather than a private copy that knew only about the
    /// budget — before that, the Season Guide sheet knew nothing about staff at
    /// all and called `performShellAdvance` straight past the dashboard's gate.
    /// Both Advance buttons are drawn from `advanceGateBlocker` below now, which
    /// folds this gate in as the first of four.
    @State private var staffAdvanceBlocker: AdvanceBlocker?

    /// #208g: the FIRST gate an advance would hit right now, staff included —
    /// the value both Advance buttons are drawn from.
    ///
    /// The staff blocker was the only refusal wired to the button, so a club
    /// with an empty starter slot, an over-limit roster or illegal books drew a
    /// solid-gold enabled CTA over a rail with every required row ticked, and
    /// only learned about the gate from the modal that landed after the tap.
    /// Refreshed by `refreshTaskCompletionStatus`, which is the one function
    /// that already runs on every screen entry, every advance and every task
    /// refresh. `performShellAdvance` still runs the gates itself: it is the
    /// authority, and each of its alerts carries copy and a deep link this
    /// one-line banner cannot.
    @State private var advanceGateBlocker: AdvanceBlocker?

    /// The blocker the sheet is refused with, if the user opened it right after
    /// an unrelated alert cleared. Presented as an alert from the sheet path.
    @State private var pendingStaffBlock: AdvanceBlocker?

    /// Set when `performShellAdvance` refuses to advance a club that is over the
    /// salary cap (#102, the GATE half of the cap-compliance design). Presented
    /// as an alert whose primary action deep-links to the workspace that fixes
    /// it, and cleared on dismissal — the violation is DERIVED on every advance,
    /// so nothing latches and getting legal is the only exit needed.
    @State private var pendingCapCompliance: WeekAdvancer.CapComplianceViolation?

    /// #205b — set when `performShellAdvance` refuses to leave `.preseason`
    /// with exhibitions still on the slate. Same shape as the two gates above,
    /// and derived on every advance from `PreseasonEngine.canLeavePreseason`,
    /// so nothing latches: playing the last game is the only exit it needs.
    @State private var pendingPreseasonSlate: PreseasonState?

    /// #208e — set when `performShellAdvance` refuses to leave an offseason
    /// phase with a starter slot standing empty.
    ///
    /// The QA run hit this as a club that could not advance and was never told
    /// which slot was the problem — the returner rows are two taps below the
    /// fold on a screen whose other twenty-two slots were full, so "find it"
    /// was the whole task. The gap therefore travels as the SLOTS, not as a
    /// boolean, and the alert reads them out by name.
    @State private var pendingDepthChartGap: DepthChartGap?

    /// The empty starter slots one advance is blocked on.
    struct DepthChartGap {
        /// Empty slots that the club could actually fill from its own roster,
        /// in `DepthChartSlot.allCases` order so the reading is stable.
        let slots: [DepthChartSlot]

        /// "Special Teams: Kick Returner unassigned" — the line the QA run asked
        /// for, one per slot, capped so a chart that was never touched cannot
        /// turn the alert into a wall of text.
        var lines: [String] {
            slots.prefix(4).map { "\($0.side.rawValue): \($0.displayName) unassigned" }
        }

        var overflow: Int { max(0, slots.count - 4) }
    }

    private var depthChartGapAlertBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingDepthChartGap != nil },
            set: { presented in
                if !presented { pendingDepthChartGap = nil }
            }
        )
    }

    /// Hoisted out of the `.alert` chain in `body`: inline, the binding closure
    /// plus the interpolated message pushed the shell's modifier stack past the
    /// type-checker's budget. Same semantics, one solver step each.
    private var preseasonSlateAlertBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingPreseasonSlate != nil },
            set: { presented in
                if !presented { pendingPreseasonSlate = nil }
            }
        )
    }

    /// Same hoist as `preseasonSlateAlertBinding`, for the same reason: four
    /// `.alert`s in one modifier chain, each carrying an inline `Binding`
    /// closure and an interpolated message, is what pushed the shell past the
    /// type-checker's budget. Semantics unchanged.
    private var staffBlockAlertBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingStaffBlock != nil },
            set: { presented in
                if !presented { pendingStaffBlock = nil }
            }
        )
    }

    private var rosterLimitAlertBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingRosterLimit != nil },
            set: { presented in
                if !presented { pendingRosterLimit = nil }
            }
        )
    }

    private var capComplianceAlertBinding: Binding<Bool> {
        Binding<Bool>(
            get: { pendingCapCompliance != nil },
            set: { presented in
                if !presented { pendingCapCompliance = nil }
            }
        )
    }

    /// Rung-aware copy: the gate now covers all three cut days, so a camp club
    /// held at 75 must not be told "the season opens with a 53-man active
    /// roster" — the deadline it is standing on is the one `CutDay.dueWhen`
    /// names.
    private static func rosterLimitMessage(for violation: WeekAdvancer.RosterLimitViolation) -> String {
        let count: Int = violation.rosterCount
        let title: String = violation.rung.slatTitle
        let due: String = violation.rung.dueWhen
        let excess: Int = violation.excess
        return "You're carrying \(count) players. \(title) is due \(due) — release \(excess) more before advancing."
    }

    private static func capComplianceMessage(for violation: WeekAdvancer.CapComplianceViolation) -> String {
        let overage: String = CommittedCapLedger.money(violation.overage)
        let lever: String = CommittedCapLedger.money(violation.bestLeverSavings)
        let opening: String = "Your club is \(overage) over the cap. "
        let middle: String = "Release, restructure or renegotiate until the books balance — no week can be "
        let close: String = "advanced while you are over. The largest single saving on your roster right now is \(lever)."
        return opening + middle + close
    }

    /// The phases the lineup gate is armed in — the offseason run where the
    /// chart is both written and broken. See the gate in `performShellAdvance`
    /// for why the regular season is deliberately not on this list.
    private static let lineupPhases: Set<SeasonPhase> = [
        .otas, .trainingCamp, .preseason, .rosterCuts
    ]

    /// #208e — the blocker that NAMES the slot.
    private static func depthChartGapMessage(for gap: DepthChartGap) -> String {
        let named: String = gap.lines.joined(separator: "\n")
        let more: String = gap.overflow > 0 ? "\n\u{2026} and \(gap.overflow) more." : ""
        let close: String = "\n\nFill & Advance puts the best available body in each one and carries on \u{2014} or open the depth chart and choose them yourself."
        return named + more + close
    }

    /// The empty starter slots this club could fill but has not.
    ///
    /// **Only ever the slots a body exists for.** A club with no kicker on the
    /// roster has a hole no amount of depth-chart work will close, and a gate
    /// with no key is a bricked save — the same anti-deadlock rule
    /// `userCapComplianceViolation` applies. A returner slot accepts anyone, so
    /// it is fillable as long as the club has a player at all, which is exactly
    /// why the KR gap the QA run found was both real and fixable.
    ///
    /// A slot pointing at a man who is no longer on the roster counts as empty:
    /// that is how the gap appears in the first place — the chart is written in
    /// OTAs and the cutdown then releases the man in it.
    ///
    /// "Fillable" is counted per ROOM, not per slot. `DepthChart.assign` pulls a
    /// man out of every other position slot when he takes one, so three WR slots
    /// need three receivers — a club carrying two can never close WR3, and
    /// reporting it would be the bricked save this rule is written to avoid.
    /// The returner slots are the deliberate exception in the model
    /// (`acceptsAnyPosition`): they take anybody and may double up, so one body
    /// on the roster makes both of them fillable.
    private static func depthChartGaps(chart: DepthChart, roster: [Player]) -> [DepthChartSlot] {
        let available = roster.filter { !$0.isRetired }
        guard !available.isEmpty else { return [] }
        let onRoster = Set(available.map(\.id))

        var bodiesByPosition: [Position: Int] = [:]
        for player in available {
            bodiesByPosition[player.position, default: 0] += 1
        }

        func isFilled(_ slot: DepthChartSlot) -> Bool {
            guard let starter = chart.starter(for: slot) else { return false }
            return onRoster.contains(starter)
        }

        // Slots already standing, per room — what is left over is what the club
        // can still cover.
        var spareByPosition: [Position: Int] = bodiesByPosition
        for slot in DepthChartSlot.allCases
        where !slot.acceptsAnyPosition && isFilled(slot) {
            spareByPosition[slot.basePosition, default: 0] -= 1
        }

        var gaps: [DepthChartSlot] = []
        for slot in DepthChartSlot.allCases where !isFilled(slot) {
            if slot.acceptsAnyPosition {
                gaps.append(slot)
                continue
            }
            let spare = spareByPosition[slot.basePosition] ?? 0
            guard spare > 0 else { continue }
            spareByPosition[slot.basePosition] = spare - 1
            gaps.append(slot)
        }
        return gaps
    }

    /// #208g — the non-staff gates as a one-line banner, asked BEFORE the tap.
    ///
    /// Same three prechecks `performShellAdvance` runs, in the same order, so
    /// the banner names the gate the tap would actually hit. Read-only by
    /// construction: the preseason gate is deliberately not here, because
    /// answering it means SEEDING the slate (`ensuredPreseasonState`) and a
    /// refresh must not write — and the unplayed slate is already a required
    /// row in the rail, which is the pre-tap refusal this wave is about.
    ///
    /// The roster the caller has already fetched is reused for the lineup check;
    /// the other two run their own cheap guarded prechecks.
    private func nonStaffAdvanceBlocker(roster: [Player]) -> AdvanceBlocker? {
        if let violation = WeekAdvancer.userRosterLimitViolation(
            career: career,
            modelContext: modelContext
        ) {
            return AdvanceBlocker(
                title: "Roster over the limit",
                detail: "\(violation.rosterCount) under contract — release \(violation.excess) more "
                    + "to reach \(violation.ceiling) before advancing."
            )
        }

        if let violation = WeekAdvancer.userCapComplianceViolation(
            career: career,
            modelContext: modelContext
        ) {
            return AdvanceBlocker(
                title: "Over the salary cap",
                detail: "\(CommittedCapLedger.money(violation.overage)) over. Release, restructure "
                    + "or renegotiate until the books balance."
            )
        }

        if Self.lineupPhases.contains(career.currentPhase),
           let data = career.depthChartData,
           let chart = try? JSONDecoder().decode(DepthChart.self, from: data) {
            let gaps = Self.depthChartGaps(chart: chart, roster: roster)
            if !gaps.isEmpty {
                let named = gaps.prefix(3).map(\.displayName).joined(separator: ", ")
                let more = gaps.count > 3 ? ", and \(gaps.count - 3) more" : ""
                let plural = gaps.count == 1 ? "" : "s"
                return AdvanceBlocker(
                    title: "Lineup incomplete",
                    detail: "\(gaps.count) starting slot\(plural) unassigned — \(named)\(more). "
                        + "Auto-Set fills every empty slot in one tap."
                )
            }
        }

        return nil
    }

    private static func preseasonSlateMessage(for state: PreseasonState?) -> String {
        let remaining: Int = PreseasonEngine.gamesRemaining(state)
        let plural: String = remaining == 1 ? "" : "s"
        let opening: String = "You have \(remaining) preseason game\(plural) left to play. "
        let body: String = "Final cuts are made on what these games show — the bubble has no film on it "
        let close: String = "until the slate is finished."
        return opening + body + close
    }

    /// TRACK B — the draft class the fog is about to come off, assembled when
    /// the calendar crosses into training camp (`WeekAdvancer` arms the
    /// once-per-season flag; this presents it). `nil` at every other moment.
    @State private var pendingRookieReveal: RookieClassReveal.Summary?

    /// Rival claims on the players the user just cut, collected at the
    /// cutdown → regular-season boundary. Drives `WaiverClaimsBanner`, which
    /// shipped in the binary with zero call sites — the claims themselves have
    /// always happened (`WaiverWireEngine` stamps `RosterCut.claimedByTeamID`),
    /// they were simply never told to the user.
    @State private var pendingWaiverClaims: [WaiverClaimsBanner.Claim] = []

    /// Whether the season week ladder is drawn.
    ///
    /// Two conditions, both P1:
    ///
    /// * **The calendar is in a season.** Weeks are the unit only once there are
    ///   weeks; in February the ordered thing is the offseason task list, which
    ///   the rail already draws. `.tradeDeadline` is a regular-season week
    ///   wearing a phase's name (#154), so it counts.
    /// * **The user is at the hub.** "A screen with no order gets no band" — the
    ///   roster is a set and the cap sheet is a ledger, and pinning the season
    ///   over them turns the band into decoration, which is the exact failure
    ///   the amendment names.
    private var showsSeasonBand: Bool {
        guard !career.isGameOver, navigationPath.isEmpty else { return false }
        switch career.currentPhase {
        case .regularSeason, .tradeDeadline, .playoffs: return true
        default: return false
        }
    }

    /// The shell's own chrome — top bar, week band, navigation stack, waiver
    /// overlay — split out of `body`.
    ///
    /// Purely a type-checker split, no behaviour change: with the stack, five
    /// alerts, the environment injection and the lifecycle/observer block all
    /// in one expression, the solver ran out of budget and reported "unable to
    /// type-check this expression in reasonable time" on an unrelated line
    /// inside the `.task` closure (multi-statement closures join the enclosing
    /// constraint system). Three declarations, three smaller problems.
    private var shellStack: some View {
        VStack(spacing: 0) {
            // Persistent top navigation bar
            TopNavigationBar(
                teamAbbreviation: team?.abbreviation ?? "???",
                teamName: team?.fullName ?? "No Team",
                pendingTaskCount: pendingTaskCount,
                // #158: the top bar is OUTSIDE the navigation stack, so this
                // sheet can be opened from a pushed screen — including the very
                // Staff screen that just filled the seat its advance gate is
                // refused on. Re-derive before presenting, or the sheet argues
                // with work the user did ten seconds ago.
                onCalendarTapped: {
                    refreshTaskCompletionStatus()
                    // Full height on EVERY open, not just the first. The detent
                    // is view state that outlives the sheet, so one drag down to
                    // `.medium` stuck for the rest of the career and every later
                    // open cut the required row in half again.
                    calendarDetent = .large
                    shellSheet = .calendar
                },
                onQuitTapped: { showQuitConfirmation = true },
                unreadInboxCount: inboxMessages.filter { !$0.isRead }.count,
                onInboxTapped: {
                    navigationPath = NavigationPath()
                    navigationPath.append(ShellDestination.inbox)
                },
                // #200: settings without leaving the career. Straight into the
                // one sheet slot — no state to prepare, and if something else
                // already holds the slot the gear is behind that modal anyway.
                onSettingsTapped: { shellSheet = .settings },
                onBookmarkTapped: { destination in
                    handleBookmarkNavigation(destination)
                }
            )

            // The season, as a WEEK ladder (P1's iteration-2 amendment, §2.1's
            // first scale). Shell chrome, under the top bar — see the header of
            // `SeasonWeekBand.swift` for why it is here and why it is drawn at
            // the hub only.
            //
            // The `Group` + scoped `animation` is there because the band leaves
            // on a push: an un-animated 70 pt layout jump underneath a sliding
            // navigation transition reads as a glitch. The animation is bound to
            // `showsSeasonBand` alone so it cannot leak into the content area.
            Group {
                if showsSeasonBand {
                    SeasonWeekBandView(
                        currentWeek: career.currentWeek,
                        inPlayoffs: career.currentPhase == .playoffs,
                        fixtures: seasonFixtures,
                        seasonYear: career.currentSeason
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: showsSeasonBand)

            // Main content area (timeline is inside CareerDashboardView)
            NavigationStack(path: $navigationPath) {
                CareerDashboardView(
                    career: career,
                    tasks: $currentTasks,
                    inboxMessages: inboxBinding,
                    onTaskSelected: { destination in
                        handleTaskNavigation(destination)
                    },
                    onAdvance: {
                        performShellAdvance()
                    },
                    // A coached game is the one way a week's result lands
                    // without an advance. The shell owns the week ladder, so it
                    // has to be told — see `reloadSeasonFixtures`.
                    onWeekResultRecorded: {
                        reloadSeasonFixtures()
                    },
                    launchCoachedGame: $requestCoachedLaunch,
                    // #208g: the lineup / roster / cap refusals this screen
                    // cannot see for itself, so the rail's gold CTA greys out
                    // and names the gate instead of throwing a modal after the
                    // tap.
                    shellAdvanceBlocker: advanceGateBlocker
                )
                    .onAppear {
                        // Refresh task completion when returning to the dashboard
                        // (e.g., after hiring coaches, signing players, etc.)
                        refreshTaskCompletionStatus()
                    }
                    .navigationDestination(for: ShellDestination.self) { dest in
                        destinationView(for: dest)
                    }
            }
            // Waiver results land over the content area — BELOW the persistent
            // top bar, which is why the overlay hangs off the stack and not off
            // the outer VStack. Self-dismisses after ~8s.
            .overlay(alignment: .top) {
                if !pendingWaiverClaims.isEmpty {
                    WaiverClaimsBanner(claims: pendingWaiverClaims) {
                        pendingWaiverClaims = []
                    }
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
                }
            }
        }
        .background(Color.backgroundPrimary)
        .navigationBarBackButtonHidden(true)
    }

    /// The three advance gates plus the quit confirmation, in the order they
    /// were applied inline. A function only so this group is its own
    /// type-checking problem — see `shellStack`.
    private func gateAlerts(_ content: some View) -> some View {
        content
        // #158 — the staff gate's voice. Same shape as the two gates below it:
        // `performShellAdvance` is a precheck, and a refusal the user cannot
        // read is a button that "just doesn't work".
        .alert(
            "Staff Not Ready",
            isPresented: staffBlockAlertBinding,
            presenting: pendingStaffBlock
        ) { _ in
            Button("Go to Staff") {
                pendingStaffBlock = nil
                navigationPath.append(ShellDestination.coachingStaff)
            }
            Button("Cancel", role: .cancel) { pendingStaffBlock = nil }
        } message: { blocker in
            Text(blocker.detail)
        }
        .alert(
            "Roster Over the Limit",
            isPresented: rosterLimitAlertBinding,
            presenting: pendingRosterLimit
        ) { violation in
            Button("Go to Cuts") {
                pendingRosterLimit = nil
                navigationPath.append(ShellDestination.rosterCuts)
            }
            Button("Cancel", role: .cancel) { pendingRosterLimit = nil }
        } message: { violation in
            Text(Self.rosterLimitMessage(for: violation))
        }
        // #102 — the cap gate. Same shape as the roster gate above and for the
        // same reason: the advance mutates a season's worth of state and cannot
        // report a refusal halfway through, so the refusal is a precheck and the
        // alert is its voice. "Fix the Cap" lands on the Cap Overview, whose
        // over-cap banner is the door to the compliance workspace.
        .alert(
            "Over the Salary Cap",
            isPresented: capComplianceAlertBinding,
            presenting: pendingCapCompliance
        ) { violation in
            Button("Fix the Cap") {
                pendingCapCompliance = nil
                navigationPath.append(ShellDestination.capOverview)
            }
            Button("Cancel", role: .cancel) { pendingCapCompliance = nil }
        } message: { violation in
            Text(Self.capComplianceMessage(for: violation))
        }
        // #208e — the lineup gate. Same family again, and the one thing it does
        // differently is the whole point of it: it names the slot. "Go to Depth
        // Chart" lands on the screen whose Auto-Set closes every gap at once.
        .alert(
            "Lineup Incomplete",
            isPresented: depthChartGapAlertBinding,
            presenting: pendingDepthChartGap
        ) { _ in
            Button("Fill & Advance") {
                pendingDepthChartGap = nil
                fillLineupGapsAndAdvance()
            }
            Button("Go to Depth Chart") {
                pendingDepthChartGap = nil
                navigationPath.append(ShellDestination.depthChart)
            }
            Button("Cancel", role: .cancel) { pendingDepthChartGap = nil }
        } message: { gap in
            Text(Self.depthChartGapMessage(for: gap))
        }
        // #205b — the preseason gate, third of the same family. "Play the
        // Games" pushes the slate itself; there is no other door to it.
        .alert(
            "Preseason Slate Unplayed",
            isPresented: preseasonSlateAlertBinding,
            presenting: pendingPreseasonSlate
        ) { _ in
            Button("Play the Games") {
                pendingPreseasonSlate = nil
                navigationPath.append(ShellDestination.preseason)
            }
            Button("Cancel", role: .cancel) { pendingPreseasonSlate = nil }
        } message: { state in
            Text(Self.preseasonSlateMessage(for: state))
        }
        .alert("Quit to Main Menu?", isPresented: $showQuitConfirmation) {
            Button("Quit", role: .destructive) {
                // Pop to root by dismissing
                if let window = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows.first {
                    window.rootViewController = UIHostingController(rootView:
                        ContentView()
                            .modelContainer(DataContainer.create())
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your progress is saved automatically.")
        }
    }

    var body: some View {
        gateAlerts(shellStack)
        // TRACK B: every roster surface under this shell reads the fog context
        // from the environment instead of having a `Career` threaded into it.
        // Applied OUTSIDE the presentation modifiers above on purpose — sheets
        // and full-screen covers inherit the environment of their ancestors, so
        // a rookie stays fogged inside the calendar sidebar and the player
        // sheets too.
        .environment(
            \.rookieFog,
            RookieFogContext(season: career.currentSeason, phase: career.currentPhase)
        )
        // The shell owns the BASE music context for as long as a career is
        // open: the draft room, the playoffs and the Championship each get their
        // own score, everything else gets the front-office bed. Screens that
        // want something different while they are on top push an override
        // instead (see `MusicDirector`), so nothing here has to know about
        // them. On dismiss the base goes back to the title theme.
        .onAppear {
            MusicDirector.shared.setBaseContext(.forPhase(career.currentPhase))
        }
        .onChange(of: career.currentPhase) { _, phase in
            MusicDirector.shared.setBaseContext(.forPhase(phase))
        }
        .onDisappear {
            MusicDirector.shared.setBaseContext(.menu)
        }
        .task {
            // Task #67: repair the position-battle rows the calendar-year stamp
            // left behind — duplicates from a detection pass that re-ran every
            // camp week, and unresolved rows stamped with a season this save is
            // no longer in. A no-op once the save is clean, so it is safe to run
            // on every open rather than needing a schema-version gate.
            PositionBattleTracker.cleanupLegacyBattles(career: career, modelContext: modelContext)
            loadShellData()
            // R31: a fired career only shows the final summary screen.
            if career.isGameOver {
                shellCover = .fired
            }
            // TRACK B: a reveal armed by an advance the user quit out of before
            // dismissing is still owed to him — present it on the next open.
            if !career.isGameOver {
                _ = presentRookieRevealIfArmed()
            }
            // The hand-off route, once the shell's own data is loaded so the
            // pushed screen reads a populated career. A fired career never
            // takes it — that path owns the whole screen.
            if let openingRoute, !career.isGameOver {
                handleTaskNavigation(openingRoute)
            }
        }
        .onChange(of: navigationPath) { _, _ in
            refreshTaskCompletionStatus()
            // Task #19: full-screen flows (the draft room above all) stage mail
            // on `WeekAdvancer.lastInboxMessages` while the shell is off screen,
            // and the next `advanceWeek` wipes that channel before the
            // phase/week observers below ever fire. Draining on every navigation
            // change collects it the moment the user comes back.
            collectInboxMessages()
        }
        .onChange(of: career.currentPhase) { _, newPhase in
            regenerateTasks(for: newPhase)
            collectInboxMessages()
            // QA-03: the schedule for a season is generated when that season
            // starts, which is ALWAYS after the shell opened — a career sitting
            // in the offseason has no `Game` rows for the year it is about to
            // play. `seasonFixtures` was loaded once at open and never again, so
            // the week ladder drew eighteen byes for the whole regular season
            // while the hero card, which reads a live query, named the real
            // opponent. Same bug class as #154, one screen further out.
            reloadSeasonFixtures()
        }
        .onChange(of: career.currentWeek) { _, _ in
            // #154: the weekly list names the week's opponent, and the phase
            // does not move between Week 1 and Week 18. Without this the game-plan
            // and week-prep rows kept pointing at whichever club was next when
            // the phase was last entered.
            regenerateTasks(for: career.currentPhase)
            refreshTaskCompletionStatus()
            collectInboxMessages()
            // ...and the ladder for the same reason: Sunday's result is written
            // by the advance that moved this week, so without a re-read the
            // slat the club just left keeps its unplayed face.
            reloadSeasonFixtures()
        }
        // ONE sheet slot and ONE cover slot (§2.8, and the sibling-modifier bug
        // class). `lastShellSheet` / `lastShellCover` are recorded on the way in
        // so the single `onDismiss` knows which modal it is closing.
        .onChange(of: shellSheet) { _, new in
            if let new { lastShellSheet = new }
        }
        .onChange(of: shellCover) { _, new in
            if let new { lastShellCover = new }
        }
        .sheet(item: $shellSheet, onDismiss: handleSheetDismiss) { slot in
            shellSheetContent(slot)
        }
        .fullScreenCover(item: $shellCover, onDismiss: handleCoverDismiss) { slot in
            shellCoverContent(slot)
        }
    }

    // MARK: - Modal slot content

    @ViewBuilder
    private func shellSheetContent(_ slot: ShellSheet) -> some View {
        switch slot {
        case .calendar:
            CalendarSidebarView(
                career: career,
                team: team,
                upcomingGames: upcomingGames,
                allTeams: allTeamsByID,
                tasks: $currentTasks,
                // The superset the hub's button reads (#208g) — the sheet's
                // Advance calls straight into `performShellAdvance`, so it has
                // to refuse on everything that call refuses on.
                advanceBlocker: advanceGateBlocker,
                onTaskSelected: { destination in
                    handleTaskNavigation(destination)
                },
                onAdvancePhase: {
                    // §2.8: the advance stages the NEXT modal, so it may not run
                    // in the same runloop as this dismissal — see
                    // `pendingAdvanceAfterCalendar`.
                    pendingAdvanceAfterCalendar = true
                    shellSheet = nil
                },
                onDismiss: { shellSheet = nil }
            )
            .presentationDetents([.large, .medium], selection: $calendarDetent)
            .presentationDragIndicator(.visible)

        case .voluntaryWorkout:
            VoluntaryWorkoutPrompt(career: career)

        case .ownerReview:
            // R31: end-of-season owner review (bonus / warning verdicts).
            if let review = pendingOwnerReview {
                OwnerSeasonReviewSheet(
                    review: review,
                    ownerName: team?.owner?.name ?? "The Owner",
                    teamName: team?.fullName ?? "your team",
                    owner: team?.owner,
                    context: OwnerSeasonReviewSheet.Context.build(
                        review: review,
                        career: career,
                        team: team
                    )
                )
            }

        case .holdout:
            if let holdout = pendingHoldout, let player = pendingHoldoutPlayer {
                HoldoutDialog(
                    holdout: holdout,
                    playerName: player.fullName,
                    position: player.position.rawValue,
                    currentSalary: player.annualSalary,
                    marketValue: pendingHoldoutMarketValue,
                    onResolve: { resolution in
                        resolveHoldout(holdout, player: player, resolution: resolution)
                    }
                )
            }

        case .result:
            // §2.6: the one termination pattern. It carries the ONLY commit on
            // the surface it covers — no second dismissal verb.
            if let result = pendingResult {
                DSResultSheet(
                    tone: result.tone,
                    eyebrow: result.eyebrow,
                    headline: result.headline,
                    message: result.message,
                    chips: result.chips,
                    cost: result.cost,
                    onContinue: { shellSheet = nil }
                )
                .interactiveDismissDisabled(true)
            }

        case .settings:
            // `.career` hides the two rows that only mean something on the
            // title screen (tutorial replay, save-data wipe); everything else —
            // audio, play clock, quarter reports — is exactly what a coach
            // wants to reach mid-week without abandoning the save.
            SettingsView(context: .career)
        }
    }

    @ViewBuilder
    private func shellCoverContent(_ slot: ShellCover) -> some View {
        switch slot {
        case .press:
            if let questions = pendingPressQuestions {
                WeeklyPressConferenceView(
                    questions: questions,
                    career: career,
                    context: pendingPressContext ?? .neutral,
                    // #177: the presser's standing strip and its summary both
                    // read the owner's satisfaction, and both were blank on the
                    // weekly path because this argument was never passed. Same
                    // `team?.owner` the owner review two cases up uses.
                    owner: team?.owner,
                    onComplete: { result in
                        applyPressConferenceEffects(result)
                        shellCover = nil
                    }
                )
            }

        case .roundResults:
            // #38: post-game round recap — dismisses straight to the dashboard,
            // or to the one reference destination the user picked out of it.
            //
            // §2.8: the recap is a *result* the user leaves, and standings/news
            // are *reference destinations* he pushes to. Those are two
            // presentations, and running them from one event made the push land
            // while the cover was still on screen — so both call sites had grown
            // a 0.35 s `asyncAfter` to out-wait the dismissal animation, a number
            // that is a guess on every device. The route is recorded instead and
            // travelled in `onDismiss`, which fires when the cover has gone.
            if let data = pendingRoundResults {
                RoundResultsView(
                    data: data,
                    onSeeStandings: { closeRoundResults(routingTo: .standings) },
                    onSeeNews: { closeRoundResults(routingTo: .news) },
                    onDismiss: { closeRoundResults(routingTo: nil) }
                )
            }

        case .rookieReveal:
            // TRACK B: "Rookies Report to Camp" — once per season, at the camp
            // boundary. The hand-off to the workout prompt happens in the cover's
            // `onDismiss`, not here: assigning the sheet slot from inside the
            // cover's own completion handler is exactly the race the single-slot
            // rewrite exists to remove.
            if let summary = pendingRookieReveal {
                RookieClassRevealView(summary: summary) {
                    RookieClassReveal.clear(careerID: career.id)
                    shellCover = nil
                }
            }

        case .fired:
            // R31: the owner pulled the trigger — career-over summary screen.
            FiredSummaryView(
                career: career,
                teamName: team?.fullName ?? "your team",
                ownerName: team?.owner?.name ?? "The owner",
                reviewSummary: career.ownerSeasonReview?.verdict == .fired
                    ? career.ownerSeasonReview?.summary
                    : nil
            )
        }
    }

    // MARK: - Modal slot dismissal
    //
    // One handler per slot, dispatching on what was last presented. Everything
    // that used to be a per-modifier `onDismiss` closure lives here, which is
    // also the only place a *second* modal is allowed to be staged — by then the
    // first has actually left the screen.

    private func handleSheetDismiss() {
        // Read and clear FIRST: the handler is allowed to stage the next modal,
        // and doing so re-arms `lastShellSheet` through `onChange`.
        let closed = lastShellSheet
        lastShellSheet = nil

        switch closed {
        case .calendar:
            travelPendingRoute()
            // The Advance button's request, served now that the sheet has
            // actually left the screen — the advance is allowed to stage the
            // next modal, and this is the one place where doing so is safe.
            if pendingAdvanceAfterCalendar {
                pendingAdvanceAfterCalendar = false
                performShellAdvance()
            }

        case .ownerReview:
            // Mark the review acknowledged so it only pops once.
            if var review = career.ownerSeasonReview, !review.acknowledged {
                review.acknowledged = true
                career.ownerSeasonReview = review
                try? modelContext.save()
            }
            pendingOwnerReview = nil

        case .holdout:
            pendingHoldout = nil
            pendingHoldoutPlayer = nil
            // §2.6: the holdout used to end by silently closing its own dialog —
            // a season's worth of contract change applied and nothing said about
            // it. It now ends the way every other process does.
            if pendingResult != nil { shellSheet = .result }

        case .result:
            pendingResult = nil

        case .voluntaryWorkout:
            // Asked and answered — drop any leftover request.
            workoutPromptArmed = false

        case .settings:
            // Nothing to reconcile: settings write straight to UserDefaults and
            // the audio directors reconcile themselves from that. It still has
            // to be listed — the switch is exhaustive on purpose, so a slot
            // added later cannot silently skip its own clean-up.
            break

        case .none:
            break
        }

        // The slot just came free: if the week's workout prompt was queued
        // behind whatever was in it, ask it now.
        stageWorkoutPromptIfFree()
    }

    private func handleCoverDismiss() {
        let closed = lastShellCover
        lastShellCover = nil

        switch closed {
        case .roundResults:
            travelPendingRoute()

        case .rookieReveal:
            pendingRookieReveal = nil
            // The reveal holds the screen across the camp boundary, so the
            // week's workout prompt is queued as it leaves — queued, not
            // assigned: the same advance may have put a holdout in the sheet
            // slot, and overwriting that is the bug this shape exists to stop.
            if career.currentPhase == .otas || career.currentPhase == .trainingCamp {
                workoutPromptArmed = true
            }

        case .press, .fired, .none:
            break
        }

        // #38: the recap chains off the DISMISSAL of whatever held the slot
        // ahead of it — normally the presser. Written once, at the bottom, so a
        // cover added later cannot swallow the week's recap the way the
        // completion-handler version did. `pendingRoundResults` is only ever
        // non-nil on a regular-season advance, so this is a no-op everywhere
        // else, and it never re-presents itself: `closeRoundResults` clears it.
        if closed != .roundResults,
           pendingRoundResults != nil,
           shellCover == nil,
           shellSheet == nil {
            shellCover = .roundResults
        }

        // Last, so the recap keeps first claim on the screen: a queued workout
        // prompt takes the sheet slot only if nothing else wanted it.
        stageWorkoutPromptIfFree()
    }

    /// Moves a queued voluntary-workout prompt into the sheet slot, but only
    /// when the slot is actually free — otherwise it stays queued and the next
    /// dismissal tries again. The request is dropped once the camp window has
    /// closed, so a prompt that never found a gap cannot resurface a phase
    /// later.
    private func stageWorkoutPromptIfFree() {
        guard workoutPromptArmed else { return }
        guard career.currentPhase == .otas || career.currentPhase == .trainingCamp else {
            workoutPromptArmed = false
            return
        }
        guard shellSheet == nil, shellCover == nil else { return }
        workoutPromptArmed = false
        shellSheet = .voluntaryWorkout
    }

    // MARK: - Holdout Helpers

    /// Resolves the holdout AND states the outcome (§2.6).
    ///
    /// Before this, the dialog applied a season's worth of contract and morale
    /// change and then simply closed — the user was returned to the dashboard
    /// with no statement of what the front office had just agreed to. The
    /// numbers are sampled either side of the mutation so the result sheet can
    /// show the delta rather than only the new value.
    private func resolveHoldout(
        _ holdout: Holdout,
        player: Player,
        resolution: HoldoutEngine.Resolution
    ) {
        let salaryBefore = player.annualSalary
        let yearsBefore = player.contractYearsRemaining
        let moraleBefore = player.morale

        // `.forceTrade` REALLY ships the man out (`HoldoutEngine.forceTrade`
        // executes a fair-value package through `TradeEngine.executeTrade`), and
        // `onForcedTrade` is the only channel that names the partner and the
        // return. Dropping it is how the sheet came to tell the user his star
        // reported back and was "still being shopped" on the one path that had
        // already traded him away.
        var forcedTrade: HoldoutEngine.ForcedTradeOutcome?
        let resolved = HoldoutEngine.resolveHoldout(
            holdout: holdout,
            resolution: resolution,
            player: player,
            modelContext: modelContext,
            onForcedTrade: { forcedTrade = $0 }
        )
        // R22: an extension really pays the player — otherwise the same star
        // would be flagged as underpaid again next offseason.
        if resolved {
            applyHoldoutResolutionEffects(resolution, player: player)
        }
        // After resolution, persist a storyline event for the inbox.
        if let teamID = career.teamID {
            let evt = FAStorylineEvent(
                seasonYear: career.currentSeason,
                type: .holdout,
                playerID: player.id,
                teamID: teamID,
                headline: "\(player.fullName) holdout resolved",
                body: "Front office took the \(resolutionLabel(resolution)) path."
            )
            evt.careerID = career.id
            modelContext.insert(evt)
            try? modelContext.save()
        }

        let salaryDelta = player.annualSalary - salaryBefore
        let moraleDelta = player.morale - moraleBefore

        // Non-nil only when the man was actually shipped out.
        var tradedPartner: String?
        if let forcedTrade, case let .traded(partnerAbbr, _) = forcedTrade {
            tradedPartner = partnerAbbr
        }

        var chips: [DSResultSheet.Chip] = []
        if let tradedPartner {
            // He is gone. What he earns and how many years he has left are
            // another club's business now — the figures that mean anything to
            // this front office are where he went and what came off the payroll.
            chips = [
                .init(
                    id: "partner",
                    label: "Traded to",
                    value: tradedPartner,
                    context: "\(player.position.rawValue) \u{00B7} \(player.overall) OVR"
                ),
                .init(
                    id: "payroll",
                    label: "Off the payroll",
                    value: CommittedCapLedger.money(salaryBefore),
                    context: "before dead money"
                )
            ]
        } else {
            chips = [
                .init(
                    id: "salary",
                    label: "Salary",
                    value: CommittedCapLedger.money(player.annualSalary),
                    // `money` prints its own minus sign, so a hard "+" prefix
                    // turned a pay CUT into "+-$4.2M".
                    context: salaryDelta == 0
                        ? "Unchanged"
                        : (salaryDelta > 0
                            ? "+\(CommittedCapLedger.money(salaryDelta))"
                            : CommittedCapLedger.money(salaryDelta)),
                    contextColor: salaryDelta == 0
                        ? .textTertiaryReadable
                        : (salaryDelta > 0 ? .alertOrange : .success)
                ),
                .init(
                    id: "years",
                    label: "Years left",
                    value: "\(player.contractYearsRemaining)",
                    context: player.contractYearsRemaining == yearsBefore
                        ? "Unchanged"
                        : "was \(yearsBefore)"
                )
            ]
            if moraleDelta != 0 {
                chips.append(
                    .init(
                        id: "morale",
                        label: "Morale",
                        value: "\(player.morale)",
                        context: "+\(moraleDelta)",
                        valueColor: Color.forRating(player.morale),
                        contextColor: .success
                    )
                )
            }
        }

        let headline: String
        let tone: DSResultSheet.Tone
        if !resolved {
            headline = "\(player.fullName) stays away"
            tone = .bad
        } else if let tradedPartner {
            // Not `.good`: the standoff ended, but the club lost the player.
            headline = "\(player.fullName) traded to \(tradedPartner)"
            tone = .neutral
        } else {
            headline = "\(player.fullName) reports back"
            tone = .good
        }

        pendingResult = ShellResult(
            tone: tone,
            eyebrow: "Holdout",
            headline: headline,
            message: resolved
                ? holdoutOutcomeMessage(resolution, player: player, forcedTrade: forcedTrade)
                : "The **\(resolutionLabel(resolution))** route did not settle it. He is still not in the building.",
            chips: resolved ? chips : [],
            cost: resolved
                ? holdoutCostLine(resolution, salaryDelta: salaryDelta, forcedTrade: forcedTrade)
                : nil
        )
    }

    /// The one-line prose the result sheet leads with, in the front office's
    /// own words rather than the engine's enum name.
    private func holdoutOutcomeMessage(
        _ resolution: HoldoutEngine.Resolution,
        player: Player,
        forcedTrade: HoldoutEngine.ForcedTradeOutcome?
    ) -> String {
        switch resolution {
        case .extend:
            return "You met the market on a new deal. **\(player.lastName)** is back at practice tomorrow."
        case .signingBonus:
            return "A one-off cheque bought peace for this year. The **base contract is unchanged**, so the grievance is deferred, not settled."
        case .mediation:
            return "The league mediator got him back in the building without money changing hands. **Goodwill only** — it will not hold twice."
        case .forceTrade:
            // The engine either found a buyer and executed the deal, or found
            // no market and left him on the roster. Those are opposite outcomes
            // and the sheet has to say which one happened. `nil` means the
            // engine never reported at all — read as "he is still here", the
            // conservative of the two.
            if let forcedTrade, case let .traded(partnerAbbr, returnDescription) = forcedTrade {
                return "The standoff is over and so is his time here: **\(partnerAbbr)** take him and his contract, and the return is \(returnDescription)."
            }
            return "No club would pay a fair price, so **he reports back** while the front office keeps shopping him. Any later deal goes through the **Trade Center**."
        }
    }

    /// §2.5's explainer line: what committing cost, beside the commit.
    private func holdoutCostLine(
        _ resolution: HoldoutEngine.Resolution,
        salaryDelta: Int,
        forcedTrade: HoldoutEngine.ForcedTradeOutcome?
    ) -> String {
        switch resolution {
        case .extend:
            // An "extension" can land at or below what he was already earning
            // (an expiring star qualifies with no market test at all), and a
            // raise and a saving are not the same sentence.
            if salaryDelta < 0 {
                return "Frees **\(CommittedCapLedger.money(-salaryDelta))** a year on the cap sheet and locks the years in."
            }
            if salaryDelta == 0 {
                return "No change to the annual number — the **years** are what you bought."
            }
            return "Adds **\(CommittedCapLedger.money(salaryDelta))** a year to the books and locks the years in."
        case .signingBonus:
            return "Cash out of the owner's pocket this year. **Nothing changes on the cap sheet.**"
        case .mediation:
            return "Costs nothing. **The pay gap is still there**, and so is next offseason."
        case .forceTrade:
            if let forcedTrade, case .traded = forcedTrade {
                return career.capMode == .sandbox
                    ? "The deal is done, and the standoff with it."
                    : "Whatever signing-bonus money is left on his deal accelerates onto your cap sheet as **dead money**."
            }
            return "Costs nothing today. You are now negotiating from a position everyone in the league can see."
        }
    }

    private func resolutionLabel(_ resolution: HoldoutEngine.Resolution) -> String {
        switch resolution {
        case .extend:        return "extension"
        case .signingBonus:  return "signing-bonus"
        case .forceTrade:    return "trade"
        case .mediation:     return "mediation"
        }
    }

    /// R22: applies the concrete contract effects of a holdout resolution so
    /// the underlying grievance is actually fixed (an unresolved pay gap would
    /// re-trigger the same drama next offseason).
    private func applyHoldoutResolutionEffects(_ resolution: HoldoutEngine.Resolution, player: Player) {
        // The league's ACTUAL cap. At the 265 000 default this screen priced a
        // holdout against season-1 money while the free-agency screen priced the
        // same man against the real cap — a gap that widens every league year.
        let market = ContractEngine.estimateMarketValue(
            player: player, salaryCap: team?.salaryCap ?? ContractEngine.openingSalaryCap
        )
        switch resolution {
        case .extend:
            // Market-rate extension: pay the player and add years.
            //
            // `max`, not a straight assignment: a star qualifies for a holdout
            // on an EXPIRING deal with no market test at all, so an ageing man
            // on a big contract can be worth less than he is paid — and the
            // "extension" he demanded then quietly CUT his pay, which no agent
            // would sign and which printed as a negative raise on the result
            // sheet. An extension never pays a player less than he already got.
            let newSalary = max(player.annualSalary, market)
            if career.capMode != .sandbox, let team {
                team.currentCapUsage += newSalary - player.annualSalary
            }
            player.annualSalary = newSalary
            player.contractYearsRemaining = max(player.contractYearsRemaining, 3)
            player.morale = min(100, player.morale + 10)
        case .signingBonus:
            // Stopgap money: happier, but the base contract stays as-is.
            player.morale = min(100, player.morale + 8)
        case .mediation:
            player.morale = min(100, player.morale + 5)
        case .forceTrade:
            // Nothing to apply here. `HoldoutEngine.forceTrade` has already
            // done the work inside `resolveHoldout`: it either executed a real
            // trade through `TradeEngine` (player moved, contract re-pointed,
            // dead money charged, `TradeRecord` written, league news posted) or
            // found no market and left him exactly where he was.
            break
        }
        try? modelContext.save()
    }

    /// FA Drama Phase 5 / R22: scan the user's roster when OTAs open for STAR
    /// players (OVR >= 85 or team top-3) who are expiring or clearly underpaid
    /// and may hold out. The player's agent persona drives the odds — a
    /// hardliner agent is far more likely to pull the trigger.
    @MainActor
    private func detectAndShowHoldout() {
        guard let teamID = career.teamID else { return }
        let roster = teamRoster
        guard !roster.isEmpty else { return }

        // Never stack a second holdout on top of an active one.
        let activeDescriptor = FetchDescriptor<Holdout>(
            predicate: #Predicate<Holdout> { $0.teamID == teamID && $0.resolvedAt == nil }
        )
        if let active = try? modelContext.fetch(activeDescriptor), !active.isEmpty { return }

        // Build per-player market value map.
        var marketValues: [UUID: Int] = [:]
        let cap = team?.salaryCap ?? ContractEngine.openingSalaryCap
        for p in roster {
            marketValues[p.id] = ContractEngine.estimateMarketValue(player: p, salaryCap: cap)
        }
        // D4-C — the club's season is now part of the read. A star on a losing
        // team applied exactly the same pressure as one on a winner; he now
        // becomes a candidate on the losing alone (`fedUp`) and his agent pulls
        // the trigger more readily (`walkoutChance`). Passing the record here is
        // the whole of the wiring: the magnitudes are all in `HoldoutEngine`.
        let record = (wins: team?.wins ?? 0, losses: team?.losses ?? 0)
        let candidates = HoldoutEngine.detectStarHoldoutCandidates(
            roster: roster,
            marketValues: marketValues,
            teamRecord: record
        )

        // Agent persona decides who actually walks out: hardliner 65%,
        // loyalist 30%, cooperative 15%, each scaled by how bad the season and
        // the mood have got. First candidate to pass rolls in.
        let star: Player? = candidates.first { candidate in
            let base: Int
            switch AgentPersona.forPlayer(id: candidate.id) {
            case .hardliner:   base = 65
            case .loyalist:    base = 30
            case .cooperative: base = 15
            }
            let chance = HoldoutEngine.walkoutChance(
                basePercent: base,
                frustration: HoldoutEngine.frustration(
                    wins: record.wins,
                    losses: record.losses,
                    morale: candidate.morale
                )
            )
            return Int.random(in: 1...100) <= chance
        }
        guard let first = star else { return }

        let market = marketValues[first.id] ?? first.annualSalary
        let delta = max(0, market - first.annualSalary)
        if let holdout = HoldoutEngine.startHoldout(
            player: first,
            teamID: teamID,
            subMarketDelta: delta,
            seasonYear: career.currentSeason,
            modelContext: modelContext
        ) {
            pendingHoldoutPlayer = first
            pendingHoldoutMarketValue = market
            pendingHoldout = holdout
            shellSheet = .holdout

            // Inbox drama: the agent fires the opening shot. APPENDED, not
            // inserted at 0 — the mailbox is stored oldest-first and `InboxView`
            // reverses it, so an inserted message read as the OLDEST mail in the
            // career and sank to the bottom of the list.
            let agentName = AgentPersona.agentName(for: first.id)
            inboxMessages.append(InboxMessage(
                sender: .playerAgent(name: agentName),
                subject: "\(first.fullName) is holding out",
                body: "Effective immediately, my client will not participate in team activities. He is making $\(first.annualSalary / 1000)M against a market value of $\(market / 1000)M. Until this organization shows it values him, he stays home. You know where to reach me.",
                date: "Offseason - OTAs, Season \(career.currentSeason)",
                category: .contractRequest,
                actionRequired: true,
                actionDestination: .roster
            ))
            persistInbox()
        }
    }

    // MARK: - Advance Week

    /// Performs the week/phase advance from the TimelineTasksPanel.
    private func performShellAdvance() {
        // #158 staff gate. The dashboard's Advance button already disables
        // itself on this value, and the Season Guide sheet now does too — but
        // the sheet calls straight in here, so the refusal has to live on the
        // path that actually mutates the calendar and not only on the two
        // buttons that lead to it. `advanceBlocker` is `.coachingChanges`-only
        // and clears the moment the seat is filled or the pot is back in the
        // black, so nothing can latch.
        if let blocker = staffAdvanceBlocker {
            pendingStaffBlock = blocker
            return
        }

        // Cut-ladder gate — all three rungs (75 / 65 / 53), not only the last.
        // `WeekAdvancer.trimAIRosters` enforces the ceiling for the other 31
        // clubs only: the user does his own cuts, and nothing checked that he
        // had. Refuse the advance rather than break camp — or open a season —
        // on an illegal roster; the letter makes the refusal findable
        // afterwards. The ceiling comes from `CutDay.rung(dueIn:)`, the same
        // authority the left rail's ladder row reads, so the panel and the gate
        // cannot disagree about what "over" means (#154f).
        if let violation = WeekAdvancer.userRosterLimitViolation(
            career: career,
            modelContext: modelContext
        ) {
            pendingRosterLimit = violation
            let letter = WeekAdvancer.rosterLimitInboxMessage(violation, season: career.currentSeason)
            if !inboxMessages.contains(where: { $0.subject == letter.subject }) {
                inboxMessages.append(letter)
                persistInbox()
            }
            return
        }

        // #102 cap gate. Refuse the advance while the club's books are illegal
        // inside the league's compliance window — the third pillar of the wave,
        // after PREVENTION (`CommittedCapLedger`) and REMEDIATION
        // (`CapComplianceView`). `userCapComplianceViolation` returns nil in
        // sandbox, outside the window, when compliant, and — the anti-deadlock
        // rule — when the club holds no lever that frees any cap at all, so a
        // save can never be bricked by this block.
        if let violation = WeekAdvancer.userCapComplianceViolation(
            career: career,
            modelContext: modelContext
        ) {
            pendingCapCompliance = violation
            let letter = WeekAdvancer.capComplianceInboxMessage(
                violation,
                season: career.currentSeason,
                phase: career.currentPhase
            )
            if !inboxMessages.contains(where: { $0.subject == letter.subject }) {
                inboxMessages.append(letter)
                persistInbox()
            }
            return
        }

        // #208e lineup gate. A club whose depth chart has an empty starter slot
        // could not advance and was never told which slot — the QA run spent the
        // block hunting for a Kick Returner two scroll positions below the fold.
        // The refusal now carries the slot names.
        //
        // Three things keep this narrow rather than a new rule:
        //
        // * **Offseason lineup phases only.** In the regular season the sim
        //   fields `WeekAdvancer.startingLineupIDs`, which is derived from the
        //   roster and not from the chart, so a hole there costs nothing and a
        //   gate would be pure friction. The hole MATTERS across the offseason,
        //   where the chart is what camp, the preseason slate and the cutdown
        //   all read the club's intentions from — and it is created there too,
        //   by releasing the man a slot points at.
        // * **A chart the user owns.** With `depthChartData == nil` nothing has
        //   ever been saved and every slot is "empty"; that state belongs to the
        //   required "Set depth chart" task, which already names itself in the
        //   rail. Gating it here would replace one pointer with twenty-six.
        // * **Fillable slots only.** `depthChartGaps` ignores a slot the club
        //   has no body for, so this can never brick a save — the same
        //   anti-deadlock rule the cap gate applies.
        if Self.lineupPhases.contains(career.currentPhase),
           let data = career.depthChartData,
           let chart = try? JSONDecoder().decode(DepthChart.self, from: data),
           let teamID = career.teamID {
            let descriptor = FetchDescriptor<Player>(
                predicate: #Predicate<Player> { $0.teamID == teamID }
            )
            let roster = (try? modelContext.fetch(descriptor)) ?? []
            let gaps = Self.depthChartGaps(chart: chart, roster: roster)
            if !gaps.isEmpty {
                pendingDepthChartGap = DepthChartGap(slots: gaps)
                return
            }
        }

        // #205b preseason gate. The exhibitions are the evidence the 53-man cut
        // is made on, so leaving `.preseason` with games unplayed skips the
        // whole wave: no familiarity banked, no preseason injuries, an empty
        // bubble table on the cut screen — and `PreseasonState.step` frozen on
        // `.plan(1)` for the season. The panel's Advance button already refuses
        // (the required slate row is not `.done`), but the Season Guide sheet
        // calls straight in here, exactly the hole #158 closed for the staff
        // gate.
        //
        // `ensuredPreseasonState()` SEEDS before asking: `canLeavePreseason(nil)`
        // is `true` by design, so gating on an unseeded blob would wave every
        // save through. A slate that cannot be drawn at all still passes, so
        // this can never brick a career.
        if career.currentPhase == .preseason {
            let slate = ensuredPreseasonState()
            if !PreseasonEngine.canLeavePreseason(slate) {
                pendingPreseasonSlate = slate
                let letter = PreseasonEngine.unplayedSlateInboxMessage(
                    slate,
                    season: career.currentSeason
                )
                if !inboxMessages.contains(where: { $0.subject == letter.subject }) {
                    inboxMessages.append(letter)
                    persistInbox()
                }
                return
            }
        }

        // #38: remember whether this was a regular-season game week — the round
        // recap only makes sense after one (power rankings are regular-season).
        // The deadline week is such a week: its phase is `.tradeDeadline`, but it
        // has a full slate and must still get its recap.
        let wasRegularSeason = career.currentPhase == .regularSeason
            || career.currentPhase == .tradeDeadline

        // Cutdown → season is the one advance that runs the waiver window
        // (`WeekAdvancer.processCampWaivers`), so it is the only one whose
        // results the banner has to report.
        let wasRosterCuts = career.currentPhase == .rosterCuts

        // Task #19: `advanceWeek` clears `lastInboxMessages` on entry. Anything
        // a modal flow staged there since the last drain — the draft room's
        // trade notices above all — has to be collected BEFORE that wipe.
        collectInboxMessages()

        PerfLog.time("advance_week") {
            WeekAdvancer.advanceWeek(career: career, modelContext: modelContext)
        }
        // WeekAdvancer never saves (caller's responsibility) — persist the
        // phase/week change immediately so a force-quit can't lose it.
        PerfLog.time("advance_save") { try? modelContext.save() }
        // Reload data so the dashboard picks up the new state
        PerfLog.time("shell_reload") { loadShellData() }

        // R31: the owner fired the coach (weekly collapse or end-of-season
        // review) — the career is over. Show the summary and stop here.
        if WeekAdvancer.wasFired {
            WeekAdvancer.wasFired = false
            career.isGameOver = true
            career.yearsFired += 1
            try? modelContext.save()
            shellCover = .fired
            return
        }

        // R31: fresh end-of-season owner review (non-firing verdicts) —
        // present the meeting sheet once.
        if let review = career.ownerSeasonReview,
           !review.acknowledged,
           review.verdict != .fired {
            pendingOwnerReview = review
            shellSheet = .ownerReview
        }

        // Waiver results: who claimed the men we let go.
        if wasRosterCuts && career.currentPhase == .regularSeason {
            let claims = collectWaiverClaims()
            if !claims.isEmpty {
                withAnimation(.easeOut(duration: 0.25)) {
                    pendingWaiverClaims = claims
                }
            }
        }

        // #38: assemble the post-game round recap (regular-season weeks only).
        // Built now from the fresh narrative/game state; presented after any
        // press conference so the flow reads game → presser → league recap.
        pendingRoundResults = wasRegularSeason ? buildRoundResults() : nil

        // Check for pending press conference
        if let questions = WeekAdvancer.pendingPressConference {
            pendingPressQuestions = questions
            pendingPressContext = WeekAdvancer.pendingPressContext
            shellCover = .press
            WeekAdvancer.pendingPressConference = nil
            WeekAdvancer.pendingPressContext = nil
        }

        // #38: no press conference intercepting the flow → show the recap now
        // (otherwise it is chained from the press conference's onComplete).
        if shellCover != .press {
            presentRoundResultsIfReady()
        }

        // TRACK B: the rookie class reports. Presented BEFORE the workout
        // prompt, and when it takes the screen the prompt is deferred to its
        // dismissal — two modals asking for the same slot in the same runloop
        // means one of them silently never appears.
        let revealPresented = presentRookieRevealIfArmed()

        // Camp Phase 1 wire-up: surface the per-week voluntary workout prompt
        // whenever the player has just stepped into an OTAs or Training Camp
        // week. The prompt itself persists the chosen workout flavor; engine
        // application is handled by VoluntaryWorkoutEngine on next tick.
        //
        // Queued, not assigned: the holdout scan below can want the same slot
        // in this same pass, and the last write would win with nothing to
        // re-arm the loser. `stageWorkoutPromptIfFree()` hands it the slot at
        // the end of the pass, or on the dismissal of whatever beat it there.
        if !revealPresented,
           career.currentPhase == .otas || career.currentPhase == .trainingCamp {
            workoutPromptArmed = true
        }

        // FA Drama Phase 5 / R22: when OTAs open, scan for star holdout
        // candidates (expiring or clearly underpaid) and surface a
        // HoldoutDialog if the agent pulls the trigger. One holdout max —
        // detection is skipped while another one is active.
        if career.currentPhase == .otas && pendingHoldout == nil {
            detectAndShowHoldout()
        }

        // Nothing else claimed the slot this pass → ask the prompt now.
        stageWorkoutPromptIfFree()
    }

    /// The lineup gate's one-tap exit: fill the empty starter slots and carry on
    /// with the advance the gap refused.
    ///
    /// `reconcileSaved` rather than `DepthChart.autoGenerate` — the alert names
    /// three slots and the user did not ask for the other twenty-three to be
    /// re-ordered behind his back. Reconcile fills exactly the empties, by the
    /// same spare-body accounting `depthChartGaps` flags them with, and leaves
    /// every standing slot alone.
    private func fillLineupGapsAndAdvance() {
        guard let teamID = career.teamID else { return }
        let descriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == teamID }
        )
        let roster = (try? modelContext.fetch(descriptor)) ?? []
        DepthChart.reconcileSaved(career: career, roster: roster)
        try? modelContext.save()

        // Off this runloop: the advance is allowed to stage the next modal (the
        // camp rookie reveal, the workout prompt, a holdout), and the alert this
        // button belongs to is still leaving the screen. Same reason
        // `pendingAdvanceAfterCalendar` waits for the sheet's dismissal.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            performShellAdvance()
        }
    }

    // MARK: - Rookie Class Reveal (TRACK B)

    /// Presents "Rookies Report to Camp" when `WeekAdvancer` armed it for this
    /// season and the club actually drafted somebody.
    ///
    /// - Returns: `true` when the modal was staged, so the caller can hold back
    ///   any other presentation for this runloop.
    @discardableResult
    private func presentRookieRevealIfArmed() -> Bool {
        // The cover slot holds one thing. If the presser already has it, leave
        // the armed flag alone rather than overwriting the modal in it — the
        // reveal is a once-per-season event and it will be picked up on the next
        // advance or on the next open of the save (see the `.task` above).
        guard shellCover == nil,
              pendingRookieReveal == nil,
              RookieClassReveal.pendingSeason(careerID: career.id) == career.currentSeason else {
            return false
        }
        guard let summary = buildRookieClassSummary() else {
            // Armed but nothing to show (every pick traded away) — consume the
            // flag rather than re-checking it on every advance for a year.
            RookieClassReveal.clear(careerID: career.id)
            return false
        }
        pendingRookieReveal = summary
        shellCover = .rookieReveal
        return true
    }

    /// The class itself, read off the rows that already exist: this season's
    /// rookies on the user's roster plus the press grades the draft room
    /// persisted for them.
    private func buildRookieClassSummary() -> RookieClassReveal.Summary? {
        guard let teamID = career.teamID, let playerTeam = team ?? allTeamsByID[teamID] else {
            return nil
        }
        let cid = career.id
        let season = career.currentSeason
        let gradeDescriptor = FetchDescriptor<DraftPickGrade>(
            predicate: #Predicate<DraftPickGrade> {
                $0.careerID == cid && $0.draftYear == season && $0.teamID == teamID
            }
        )
        let grades = (try? modelContext.fetch(gradeDescriptor)) ?? []

        return RookieClassReveal.build(
            season: season,
            teamID: teamID,
            teamName: playerTeam.fullName,
            teamAbbreviation: playerTeam.abbreviation,
            players: teamRoster,
            grades: grades
        )
    }

    // MARK: - Waiver Claims

    /// The cuts another club claimed in the 24h window that just closed.
    ///
    /// Read AFTER the advance, so `career.currentSeason` has already been bumped
    /// by `startNewSeason` — the `RosterCut` rows were written under the OLD
    /// year, which is why this keys on the newest season present rather than on
    /// the current one.
    private func collectWaiverClaims() -> [WaiverClaimsBanner.Claim] {
        guard let teamID = career.teamID else { return [] }
        let cid = career.id

        let cutsDescriptor = FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> {
                $0.careerID == cid && $0.teamID == teamID && $0.claimedByTeamID != nil
            }
        )
        let cuts = (try? modelContext.fetch(cutsDescriptor)) ?? []
        guard let latestSeason = cuts.map(\.seasonYear).max() else { return [] }
        let fresh = cuts.filter { $0.seasonYear == latestSeason }
        guard !fresh.isEmpty else { return [] }

        // One fetch for the claimed players rather than one per row.
        let claimedIDs = Set(fresh.map(\.playerID))
        let playerDescriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.careerID == cid }
        )
        let playersByID = Dictionary(
            uniqueKeysWithValues: ((try? modelContext.fetch(playerDescriptor)) ?? [])
                .filter { claimedIDs.contains($0.id) }
                .map { ($0.id, $0) }
        )

        return fresh.compactMap { cut in
            guard let player = playersByID[cut.playerID],
                  let claimingID = cut.claimedByTeamID else { return nil }
            return WaiverClaimsBanner.Claim(
                id: cut.id,
                playerName: player.fullName,
                claimingTeamAbbrev: allTeamsByID[claimingID]?.abbreviation ?? "???"
            )
        }
        .sorted { $0.playerName < $1.playerName }
    }

    // MARK: - Round Recap (#38)

    /// Closes the round recap, remembering where it was asked to go.
    ///
    /// The route is *recorded*, not travelled — see ``pendingRoute``.
    private func closeRoundResults(routingTo route: ShellDestination?) {
        pendingRoute = route
        shellCover = nil
        pendingRoundResults = nil
    }

    /// Runs the route a closing modal recorded, once that modal is off screen.
    /// A no-op when nothing asked to travel, which is the common case.
    private func travelPendingRoute() {
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        navigationPath = NavigationPath()
        navigationPath.append(route)
    }

    /// Presents the assembled round recap shortly after the current advance's
    /// transitions settle. Safe to call when nothing is pending — it no-ops.
    ///
    /// The delay here is NOT the presentation-conflict guard §2.8 retired: this
    /// call site sits inside `performShellAdvance`, mid-way through a runloop
    /// that has just rewritten a season's worth of state, and it is waiting for
    /// that churn rather than for another modal to leave. The presser path no
    /// longer comes through here at all — it chains off the cover's `onDismiss`.
    private func presentRoundResultsIfReady() {
        guard pendingRoundResults != nil, shellCover == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if pendingRoundResults != nil, shellCover == nil {
                shellCover = .roundResults
            }
        }
    }

    /// Assembles the post-game round recap purely from existing state: this
    /// week's played league games (`Game` rows), the freshly computed power
    /// rankings and MVP race (`LeagueNarrativeState`), and this week's storyline
    /// headlines (`Career.newsLog`). Returns `nil` when there's nothing to show.
    private func buildRoundResults() -> RoundResultsView.Data? {
        guard let narrative = career.leagueNarrative, !narrative.rankings.isEmpty else { return nil }
        let week = narrative.week
        let season = narrative.season
        guard week > 0 else { return nil }

        // This week's played, non-playoff league games.
        let cid = career.id
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate<Game> {
                $0.careerID == cid && $0.seasonYear == season && $0.week == week && $0.isPlayoff == false
            }
        )
        let games = ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.isPlayed }
        guard !games.isEmpty else { return nil }

        // Current power-rank lookup drives upset tagging.
        let rankByTeam = Dictionary(
            uniqueKeysWithValues: narrative.rankings.map { ($0.teamID, $0.rank) }
        )

        let lines: [RoundResultsView.GameLine] = games.compactMap { game in
            guard let home = game.homeScore, let away = game.awayScore,
                  let homeTeam = allTeamsByID[game.homeTeamID],
                  let awayTeam = allTeamsByID[game.awayTeamID] else { return nil }
            let isUser = game.homeTeamID == career.teamID || game.awayTeamID == career.teamID
            let margin = abs(home - away)
            var tag: RoundResultsView.GameLine.Tag?
            if let winnerID = game.winnerID, let loserID = game.loserID,
               let wRank = rankByTeam[winnerID], let lRank = rankByTeam[loserID],
               wRank - lRank >= 8, margin >= 3 {
                // A meaningfully lower-ranked team won — an upset.
                tag = .upset
            } else if margin >= 21 {
                tag = .blowout
            }
            return RoundResultsView.GameLine(
                id: game.id,
                awayAbbr: awayTeam.abbreviation,
                awayName: awayTeam.name,
                awayScore: away,
                homeAbbr: homeTeam.abbreviation,
                homeName: homeTeam.name,
                homeScore: home,
                isUserGame: isUser,
                tag: tag
            )
        }

        // User game first, then tagged games, then the rest (stable within groups).
        let ordered = lines.enumerated().sorted { a, b in
            func priority(_ g: RoundResultsView.GameLine) -> Int {
                if g.isUserGame { return 0 }
                if g.tag != nil { return 1 }
                return 2
            }
            let pa = priority(a.element), pb = priority(b.element)
            if pa != pb { return pa < pb }
            return a.offset < b.offset
        }.map { $0.element }

        // This week's storyline headlines — skip the redundant Power Rankings
        // recap item since the ranking section already covers it.
        let storylines = career.newsLog
            .filter { $0.season == season && $0.week == week }
            .filter { !$0.headline.localizedCaseInsensitiveContains("Power Rankings") }
            .prefix(3)

        // The MVP race only reads as meaningful once there's a body of work.
        let mvpRace = week >= 6 ? narrative.mvpRace : []

        return RoundResultsView.Data(
            week: week,
            season: season,
            games: ordered,
            rankings: narrative.rankings,
            mvpRace: mvpRace,
            storylines: Array(storylines),
            userTeamID: career.teamID
        )
    }

    // MARK: - Press Conference Effects

    /// Apply the effects from a weekly press conference result to career state.
    private func applyPressConferenceEffects(_ result: PressConferenceResult) {
        // #161: tone ledger + promise ledger, in the engine.
        PressConferenceEngine.commit(result: result, to: career)

        // Owner satisfaction (clamped 0-100, stored on Owner)
        if let ownerObj = team?.owner {
            ownerObj.satisfaction = min(100, max(0,
                ownerObj.satisfaction + result.totalEffects.ownerSatisfaction))
        }

        // Legacy points and media reputation (via LegacyTracker helper)
        career.legacy.applyPressConferenceResult(result, season: career.currentSeason)

        // The two numbers the podium printed biggest and booked nowhere: the
        // team-wide morale read lands on the user's roster and the fan read on
        // `Career.fanSupport`. Both are scaled inside the engine — a session
        // sums four ±20 answers, and `Player.morale` is a 0…100 stat the sim
        // reads directly.
        if let teamID = career.teamID {
            let descriptor = FetchDescriptor<Player>(
                predicate: #Predicate<Player> { $0.teamID == teamID }
            )
            let roster = (try? modelContext.fetch(descriptor)) ?? []
            PressConferenceEngine.applyRoomEffects(
                result: result,
                career: career,
                roster: roster
            )
        }

        // Save changes
        try? modelContext.save()
    }

    // MARK: - Navigation Destinations

    /// **One case per screen (#105 wave 2, P6).**
    ///
    /// The enum used to carry four aliases — `.cap`/`.capOverview` and
    /// `.prospectList`/`.bigBoard`/`.scouting` — three of which rendered the
    /// SAME view with a different `markTaskVisited` call inside. That is not a
    /// destination, it is a side effect wearing a destination's clothes: two
    /// routes to one screen make the navigation path's own value ambiguous, and
    /// the visited-marking they differed by belongs on the task, not the route.
    /// The tab a scouting route wants is carried by `scoutingPendingTab`
    /// (see `handleTaskNavigation`), which the hub resolves for every one of its
    /// eleven tabs — so a merged `.scouting` still lands on the right surface.
    ///
    /// `.hireHC` / `.hireOC` / `.hireDC` never existed here — they are
    /// `TaskDestination` cases, and contrary to the redesign brief they are NOT
    /// unreachable: `TaskGenerator.coachingChangesTasks` still emits all three
    /// (one per vacant seat). They map to `.coachingStaff` below and stay.
    enum ShellDestination: Hashable {
        case roster, schedule, standings, draft, scouting
        /// Wave 2 UX: the 32-roster league browser (`LeagueRostersView`).
        case leagueRosters
        case depthChart, gamePlan, coachingStaff, hireCoach
        case capOverview, freeAgency
        case contractTimeline, mentoring, trades, news
        /// F-51 — the league transaction wire over the `TradeRecord` ledger.
        /// Reached from the Trade Center rather than the bookmark strip: the
        /// strip is capped at seven on purpose (P6), and a wire is something a
        /// GM opens from the room where he trades.
        case transactions
        /// F-58 — the user's own shortlist of men he would move.
        case tradeBlock
        case ownerMeeting, lockerRoom, inbox, rosterEvaluation
        case franchiseTag
        case developmentReport
        // R32: League History & Hall of Fame
        case history
        // #40: Draft Report Card (hindsight draft-class grades)
        case draftReportCard
        // Camp destinations
        case trainingPlan, workloadDashboard, rosterCuts, gameWeekPrep
        /// #205b — the three-game preseason slate (`PreseasonView`). An
        /// in-phase step machine inside `.preseason`, the way `.freeAgency`
        /// hosts its five steps: no new `SeasonPhase` case, no new week.
        case preseason
    }

    @ViewBuilder
    private func destinationView(for destination: ShellDestination) -> some View {
        switch destination {
        case .roster:
            RosterViewWrapper(career: career)
                .onAppear {
                    markTaskVisited(for: .roster)
                    refreshTaskCompletionStatus()
                }
        case .schedule:
            ScheduleView(career: career)
                .onAppear {
                    markTaskVisited(for: .schedule)
                    refreshTaskCompletionStatus()
                }
        case .standings:
            StandingsView(career: career)
                .onAppear {
                    markTaskVisited(for: .standings)
                    refreshTaskCompletionStatus()
                }
        case .leagueRosters:
            // No `TaskDestination` case maps here yet (that enum is shared), so
            // this route is pushed directly — from the Roster toolbar and from
            // the Trade Center's "Scout league rosters" link.
            LeagueRostersView(career: career)
        case .draft:
            // The "Draft" nav entry is live-room-only DURING the draft phase.
            // Outside it, opening this route used to resume a stale war room —
            // a running 60-second pick clock in Week 1 of the regular season,
            // for a draft the sidebar already reported as Complete. Everywhere
            // else the destination is a read-only recap of the last draft plus
            // the club's upcoming draft capital.
            Group {
                if isDraftRoomLive {
                    DraftDayView(career: career)
                } else {
                    DraftRecapView(career: career)
                }
            }
            .onAppear {
                markTaskVisited(for: .draft)
                refreshTaskCompletionStatus()
            }
            .onDisappear {
                refreshTaskCompletionStatus()
            }
        case .scouting:
            ScoutingHubView(career: career)
            .onAppear {
                // The merged route (#105 wave 2): `.prospectList` and
                // `.bigBoard` used to be separate ShellDestinations whose only
                // difference from this one was which task they ticked. The
                // route is one screen, so it ticks all three task destinations
                // — otherwise merging the alias would silently stop completing
                // "Review the prospect list".
                markTaskVisited(for: .scouting)
                markTaskVisited(for: .prospectList)
                markTaskVisited(for: .bigBoard)
                refreshTaskCompletionStatus()
            }
        case .capOverview:
            CapOverviewView(career: career)
                .onAppear {
                    markTaskVisited(for: .capOverview)
                    refreshTaskCompletionStatus()
                }
        case .depthChart:
            DepthChartView(career: career)
                .onAppear {
                    markTaskVisited(for: .depthChart)
                    refreshTaskCompletionStatus()
                }
                .onDisappear {
                    refreshTaskCompletionStatus()
                }
        case .gamePlan:
            GamePlanView(
                gamePlan: gamePlanBinding,
                context: gamePlanContext,
                // #37: forward path into the game — only when there's actually
                // an unplayed player game this week to coach.
                onStartGame: canCoachThisWeek ? { launchCoachedGameFromPlan() } : nil,
                practice: gamePlanPracticeContext
            )
                .onAppear {
                    markTaskVisited(for: .gamePlan)
                    refreshTaskCompletionStatus()
                }
        case .coachingStaff, .hireCoach:
            CoachingStaffView(career: career)
            .onAppear {
                markTaskVisited(for: .coachingStaff)
                markTaskVisited(for: .hireCoach)
                refreshTaskCompletionStatus()
            }
            .onDisappear {
                refreshTaskCompletionStatus()
            }
        case .freeAgency:
            Group {
                switch FreeAgencyStep(rawValue: career.freeAgencyStep) {
                case .finalPush:
                    FinalPushView(career: career)
                case .newLeagueYear:
                    NewLeagueYearView(career: career)
                case .capReview:
                    CapComplianceView(career: career)
                case .signing:
                    FAWeeklyView(career: career)
                case .complete:
                    FACompleteView(career: career)
                default:
                    FinalPushView(career: career)
                }
            }
            .onAppear {
                markTaskVisited(for: .freeAgency)
                refreshTaskCompletionStatus()
            }
        case .contractTimeline:
            ContractTimelineView(career: career)
                .onAppear {
                    markTaskVisited(for: .contractTimeline)
                    refreshTaskCompletionStatus()
                }
        case .mentoring:
            MentoringView(career: career)
                .onAppear {
                    markTaskVisited(for: .mentoring)
                    refreshTaskCompletionStatus()
                }
        case .trades:
            TradeView(
                career: career,
                onInboxMessage: { message in
                    // Appended, not inserted at 0: the mailbox is oldest-first
                    // (`InboxView` reverses it for display), so a trade receipt
                    // inserted at the front sorted as the career's oldest mail.
                    inboxMessages.append(message)
                    persistInbox()
                }
            )
                .onAppear {
                    markTaskVisited(for: .trades)
                    refreshTaskCompletionStatus()
                }
        case .news:
            NewsView(career: career)
                .onAppear {
                    markTaskVisited(for: .news)
                    refreshTaskCompletionStatus()
                }
        case .ownerMeeting:
            OwnerMeetingView(career: career)
                .onAppear {
                    markTaskVisited(for: .ownerMeeting)
                    refreshTaskCompletionStatus()
                }
        case .lockerRoom:
            LockerRoomView(career: career)
                .onAppear {
                    markTaskVisited(for: .lockerRoom)
                    refreshTaskCompletionStatus()
                }
        case .inbox:
            InboxView(
                career: career,
                messages: inboxBinding,
                onNavigate: { destination in
                    handleTaskNavigation(destination)
                }
            )
        case .rosterEvaluation:
            RosterEvaluationView(career: career)
                .onAppear {
                    markTaskVisited(for: .rosterEvaluation)
                    refreshTaskCompletionStatus()
                }
        case .franchiseTag:
            FranchiseTagView(career: career)
                .onAppear {
                    markTaskVisited(for: .franchiseTag)
                    refreshTaskCompletionStatus()
                }
        case .developmentReport:
            DevelopmentReportView(career: career)
                .onAppear {
                    markTaskVisited(for: .developmentReport)
                    refreshTaskCompletionStatus()
                }
        case .tradeBlock:
            TradeBlockView(career: career)
        case .transactions:
            // No `markTaskVisited` — the wire is reference material, not a step
            // any task points at, which is the same shape `.history` and
            // `.draftReportCard` below already have.
            LeagueTransactionsView(career: career)
        case .history:
            LeagueHistoryView(career: career)
        case .draftReportCard:
            DraftClassReportView(career: career)
        case .trainingPlan:
            TrainingPlanView(career: career, roster: teamRoster)
                .onAppear {
                    markTaskVisited(for: .trainingPlan)
                    refreshTaskCompletionStatus()
                }
                .onDisappear {
                    refreshTaskCompletionStatus()
                }
        case .workloadDashboard:
            WorkloadDashboard(roster: workloadRankedRoster)
        case .rosterCuts:
            RosterCutView(career: career, roster: teamRoster)
        case .preseason:
            // The cut route is handed in rather than reached for: this view is
            // pushed onto the shell's own `navigationPath`, and the shell is
            // the only thing that owns it. One closure keeps `PreseasonView`
            // previewable and keeps this route to a single line of wiring.
            PreseasonView(
                career: career,
                roster: teamRoster,
                onOpenRosterCuts: { navigationPath.append(ShellDestination.rosterCuts) }
            )
            .onAppear {
                markTaskVisited(for: .preseason)
                refreshTaskCompletionStatus()
            }
            // The slate row ticks off the blob, and the blob only moves while
            // this screen is open — so the rail has to be re-derived on the way
            // out, the same way the draft room's does.
            .onDisappear {
                refreshTaskCompletionStatus()
            }
        case .gameWeekPrep:
            GameWeekPrepPicker(
                career: career,
                consecutiveOpponentWeeks: consecutiveOpponentPrepWeeks
            )
        }
    }

    // MARK: - Draft Routing

    /// `true` only while the club is actually on the draft calendar. The live
    /// war room (and its pick clock) must never be reachable outside it — see
    /// the `.draft` destination.
    private var isDraftRoomLive: Bool {
        career.currentPhase == .draft
    }

    // MARK: - Game Plan Helpers

    /// #37: true when the player has an unplayed game this week that can be
    /// coached live — mirrors the dashboard's Coach-the-Game availability so
    /// the Game Plan screen only offers "Start Game" when it will actually work.
    private var canCoachThisWeek: Bool {
        switch career.currentPhase {
        case .regularSeason, .tradeDeadline, .playoffs:
            return upcomingGames.contains { $0.week == career.currentWeek && !$0.isPlayed }
        default:
            return false
        }
    }

    /// #37: pop the Game Plan screen back to the dashboard, then ask the
    /// dashboard (owner of the coached-game cover) to launch the game. The
    /// plan auto-saves on every edit, so nothing else needs to persist here.
    private func launchCoachedGameFromPlan() {
        navigationPath = NavigationPath()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            requestCoachedLaunch = true
        }
    }

    /// Live binding between the Game Plan screen and the persisted career.
    /// Every slider drag / preset tap encodes to `career.gamePlanData`, saves
    /// the model context, and completes any "Set game plan…" task.
    private var gamePlanBinding: Binding<GamePlan> {
        Binding(
            get: { career.gamePlan },
            set: { newValue in
                career.gamePlan = newValue
                try? modelContext.save()
                markTaskCompleted(for: .gamePlan)
            }
        )
    }

    /// Situational context (week, opponent, OC scheme) for the Game Plan header
    /// and scouting panel. All fields degrade gracefully to nil.
    private var gamePlanContext: GamePlanView.Context {
        var ctx = GamePlanView.Context()

        // Week / playoff-round label — only meaningful in-season. Uses the
        // NEXT unplayed game's week so the label matches the opponent shown
        // (after this week's game is played, the plan targets next week).
        switch career.currentPhase {
        case .regularSeason, .tradeDeadline:
            let week = upcomingGames.first?.week ?? career.currentWeek
            ctx.weekLabel = "Week \(week)"
        case .playoffs:
            ctx.weekLabel = playoffRoundName
        default:
            ctx.weekLabel = nil
        }

        // OC's offensive scheme badge.
        if let teamID = career.teamID {
            let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
            let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
            ctx.schemeName = coaches
                .first { $0.role == .offensiveCoordinator }?
                .offensiveScheme?.displayName
        }

        // Opponent panel — next unplayed game for the user's team.
        if let teamID = career.teamID, let nextGame = upcomingGames.first {
            let opponentID = nextGame.homeTeamID == teamID ? nextGame.awayTeamID : nextGame.homeTeamID
            if let opponent = allTeamsByID[opponentID] {
                ctx.opponentName = opponent.fullName
                ctx.opponentRecord = opponent.record
                // S3 (TRADE_OVERHAUL_PLAN §4/§7.5): the opponent's roster comes
                // from one `teamID` fetch, shared by both defense readouts —
                // `Team.players` is a creation-time snapshot, so a team that
                // has traded/signed/cut anybody scouted wrong here.
                let opponentRoster = (try? modelContext.fetch(
                    FetchDescriptor<Player>(predicate: #Predicate<Player> { $0.teamID == opponentID })
                )) ?? []
                ctx.passDefense = Self.defenseStrength(roster: opponentRoster, positions: [.CB, .FS, .SS])
                ctx.runDefense = Self.defenseStrength(roster: opponentRoster, positions: [.DE, .DT, .MLB, .OLB])

                // R33: coordinator persona intel — the exact personas the
                // live game's AI will call with (deterministic derivation).
                let oppCoachDescriptor = FetchDescriptor<Coach>(
                    predicate: #Predicate { $0.teamID == opponentID }
                )
                let oppCoaches = (try? modelContext.fetch(oppCoachDescriptor)) ?? []
                ctx.opponentDCPersona = oppCoaches
                    .first { $0.role == .defensiveCoordinator }
                    .map({ DCPersona.derive(for: $0) })
                ctx.opponentOCPersona = oppCoaches
                    .first { $0.role == .offensiveCoordinator }
                    .map({ OCPersona.derive(for: $0) })
            }
        }

        // Round 4 (§6a): pre-game mental readiness for the user's key skill
        // players — one QB, one RB, the top three WRs, and the top TE by
        // overall. Derived through the very same `SimPlayer` the engine reads,
        // so the temperament and ego flags never drift from the live model, and
        // nothing new is persisted (morale/personality already live on Player).
        // S3: `teamRoster` is the `teamID` query (one fetch), not the stale
        // `Team.players` relationship — a player traded away or just signed
        // used to show up in, or be missing from, this readout.
        if team != nil {
            let roster = teamRoster
            let skillSlots: [(Position, Int)] = [(.QB, 1), (.RB, 1), (.WR, 3), (.TE, 1)]
            var readouts: [GamePlanView.MentalReadout] = []
            for (position, count) in skillSlots {
                let top = roster
                    .filter { $0.position == position }
                    .sorted { $0.overall > $1.overall }
                    .prefix(count)
                for player in top {
                    let snapshot = SimPlayer(from: player)
                    readouts.append(
                        GamePlanView.MentalReadout(
                            id: player.id,
                            name: player.fullName,
                            position: position,
                            temperament: snapshot.mentalTemperament,
                            morale: player.morale,
                            isEgoStar: snapshot.isEgoProne
                        )
                    )
                }
            }
            ctx.keyPlayerMentals = readouts
        }

        // #3245: the week's most versatile men, read straight off
        // `positionFamiliarity`. `conversionCommitFamiliarity` (50) is the bar —
        // the same number the development engine calls a committed conversion —
        // so the panel lists men who could genuinely cover a spot rather than
        // everyone who has ever taken a rep there. Nothing is persisted and
        // nothing is fed to the simulator: see `GamePlanView.Context.versatility`.
        if team != nil {
            let bar = VersatilityDevelopmentEngine.conversionCommitFamiliarity
            let readouts: [GamePlanView.VersatileReadout] = teamRoster
                .compactMap { player in
                    let alternates = Position.allCases
                        .filter { $0 != player.position && player.familiarity(at: $0) >= bar }
                        .map {
                            GamePlanView.VersatileReadout.Alternate(
                                position: $0,
                                familiarity: player.familiarity(at: $0)
                            )
                        }
                        .sorted { $0.familiarity > $1.familiarity }
                    guard !alternates.isEmpty else { return nil }
                    return GamePlanView.VersatileReadout(
                        id: player.id,
                        name: player.fullName,
                        position: player.position,
                        alternates: Array(alternates.prefix(3))
                    )
                }
                // Most useful first: the man who covers the most spots, then the
                // one who covers his best spot best, then by id so the order is
                // stable across redraws.
                .sorted {
                    if $0.alternates.count != $1.alternates.count {
                        return $0.alternates.count > $1.alternates.count
                    }
                    let lhs = $0.alternates.first?.familiarity ?? 0
                    let rhs = $1.alternates.first?.familiarity ?? 0
                    if lhs != rhs { return lhs > rhs }
                    return $0.id.uuidString < $1.id.uuidString
                }
            ctx.versatility = Array(readouts.prefix(5))
        }

        return ctx
    }

    /// R36: the practice-play card's data — current drill, banked weeks, and
    /// how fast the OC installs (expert = 1 week, otherwise 2). Selecting a
    /// play (or cancelling) persists straight onto the career.
    private var gamePlanPracticeContext: GamePlanView.PracticeContext? {
        guard let teamID = career.teamID else { return nil }
        let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
        let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
        let oc = coaches.first { $0.role == .offensiveCoordinator }
        let scheme = oc?.offensiveScheme
        let expertise = scheme.map { oc?.expertise(for: $0.rawValue) ?? 20 } ?? 20
        return GamePlanView.PracticeContext(
            scheme: scheme,
            currentPlay: career.weeklyPracticePlay,
            weeksDone: career.weeklyPracticeWeeksDone,
            weeksRequired: expertise >= 75 ? 1 : 2,
            installedThisSeason: career.bonusInstalledPlays,
            onSelect: { play in
                career.weeklyPracticePlay = play
                try? modelContext.save()
            }
        )
    }

    /// Buckets a defensive unit's average overall into weak / average / strong.
    /// Takes the roster (not the team) so the caller resolves it once by
    /// `teamID` — see the `Team.players` doc.
    private static func defenseStrength(
        roster: [Player],
        positions: Set<Position>
    ) -> GamePlanView.DefenseStrength? {
        let unit = roster.filter { positions.contains($0.position) }
        guard !unit.isEmpty else { return nil }
        let average = unit.reduce(0) { $0 + $1.overall } / unit.count
        switch average {
        case 78...:   return .strong
        case 70..<78: return .average
        default:      return .weak
        }
    }

    // MARK: - Camp Helpers

    /// Fetches the user's current roster (used by Camp views as a parameter).
    /// Returns an empty array when no team is assigned.
    private var teamRoster: [Player] {
        guard let teamID = career.teamID else { return [] }
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate<Player> { $0.teamID == teamID })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// `teamRoster` ordered the way the heat-map is read: heaviest load first,
    /// then the thinner durability margin.
    ///
    /// The fetch has no `sortBy`, so the grid drew 53 tiles in store order and
    /// the flagged men landed wherever the store happened to put them — nobody
    /// scans an unordered grid hunting for a red cell. `TrainingPlanView` learned
    /// this on the same roster and its `displayRoster` uses this exact
    /// comparator; sorting at the call site rather than in `teamRoster` keeps the
    /// cut sheet and the preseason slate on the order they each already impose.
    private var workloadRankedRoster: [Player] {
        teamRoster.sorted { lhs, rhs in
            if lhs.cumulativeLoad != rhs.cumulativeLoad {
                return lhs.cumulativeLoad > rhs.cumulativeLoad
            }
            return lhs.physical.durability < rhs.physical.durability
        }
    }

    /// The preseason slate, SEEDED — `nil` outside `.preseason` (#205b).
    ///
    /// Two consumers, one answer: the required "Play the preseason slate" row's
    /// completion and `performShellAdvance`'s refusal. Both have to ask about a
    /// blob that exists, because `PreseasonEngine.canLeavePreseason(nil)` is
    /// `true` on purpose (a save that never reached preseason cannot be held in
    /// it) — so gating on an unseeded save would let every career walk past the
    /// slate, which is the bug this closes rather than a new one.
    ///
    /// `PreseasonView.seedFlowIfNeeded` seeds the same way, and both go through
    /// `PreseasonEngine.openPreseasonIfNeeded`: a blob that still
    /// `matches(career:)` is handed back untouched, so whichever surface asks
    /// first draws the slate and the other reads it. The draw itself has exactly
    /// one implementation, in the engine.
    @discardableResult
    private func ensuredPreseasonState() -> PreseasonState? {
        guard career.currentPhase == .preseason else { return nil }
        let existing = career.preseasonState
        if let existing, existing.matches(career: career) { return existing }
        let cid = career.id
        let teams = (try? modelContext.fetch(
            FetchDescriptor<Team>(predicate: #Predicate<Team> { $0.careerID == cid })
        )) ?? []
        let state = PreseasonEngine.openPreseasonIfNeeded(
            existing: existing,
            career: career,
            teams: teams
        )
        career.preseasonState = state
        try? modelContext.save()
        return state
    }

    /// Counts how many consecutive prior weeks the user spent at >=70%
    /// opponent-specific prep — drives the GameWeekPrepPicker drift warning.
    private var consecutiveOpponentPrepWeeks: Int {
        guard let teamID = career.teamID else { return 0 }
        let season = career.currentSeason
        let descriptor = FetchDescriptor<OpponentPrepWeek>(
            predicate: #Predicate<OpponentPrepWeek> {
                $0.teamID == teamID && $0.seasonYear == season
            }
        )
        let prep = (try? modelContext.fetch(descriptor)) ?? []
        let sorted = prep.sorted { $0.weekNumber > $1.weekNumber }
        var streak = 0
        for week in sorted {
            if week.opponentPct >= 70 { streak += 1 } else { break }
        }
        return streak
    }

    // MARK: - Task Navigation

    /// Maps a `TaskDestination` to a `ShellDestination` and navigates there.
    func handleTaskNavigation(_ destination: TaskDestination) {
        let shellDest: ShellDestination
        switch destination {
        case .roster:             shellDest = .roster
        case .depthChart:         shellDest = .depthChart
        case .gamePlan:           shellDest = .gamePlan
        case .schedule:           shellDest = .schedule
        case .standings:          shellDest = .standings
        case .coachingStaff:      shellDest = .coachingStaff
        // #162. Same screen, different tab. The hint is the `scoutingPendingTab`
        // mechanism exactly: a career-scoped one-shot the destination view reads
        // and clears in its `.task`, so nothing has to be threaded through
        // `NavigationPath` and a hint left over from a cancelled navigation
        // cannot survive into the next visit.
        case .coachingStaffReview:
            CareerScopedDefaults.set("review", "coachingPendingTab")
            shellDest = .coachingStaff
        case .coordinatorSchemes:
            CareerScopedDefaults.set("schemes", "coachingPendingTab")
            shellDest = .coachingStaff
        case .hireCoach:          shellDest = .coachingStaff
        case .hireHC:             shellDest = .coachingStaff
        case .hireOC:             shellDest = .coachingStaff
        case .hireDC:             shellDest = .coachingStaff
        case .scouting:           shellDest = .scouting
        // The board is a TAB of the hub, not a screen of its own (#164/#165).
        // Both of these used to push their own ShellDestination, which rendered
        // the hub and then let it pick its own opening tab — so a task named
        // "Big Board" could land on the combine. The hint names the surface.
        case .prospectList, .bigBoard:
            CareerScopedDefaults.set("board", "scoutingPendingTab")
            shellDest = .scouting
        case .capOverview:        shellDest = .capOverview
        case .freeAgency:         shellDest = .freeAgency
        case .contractTimeline:   shellDest = .contractTimeline
        case .draft:              shellDest = .draft
        case .mentoring:          shellDest = .mentoring
        case .trades:             shellDest = .trades
        case .news:               shellDest = .news
        case .ownerMeeting:       shellDest = .ownerMeeting
        case .lockerRoom:         shellDest = .lockerRoom
        case .inbox:              shellDest = .inbox
        case .rosterEvaluation:   shellDest = .rosterEvaluation
        case .franchiseTag:       shellDest = .franchiseTag
        case .interviewReport:
            // Hint to ScoutingHubView to auto-select the Interviews tab so the
            // saved interview report is visible immediately.
            CareerScopedDefaults.set("interviews", "scoutingPendingTab")
            shellDest = .scouting
        // #105 wave 2: this was the one scouting deep link that pushed the hub
        // with NO hint at all, so "Schedule personal workouts" landed on
        // whatever tab the hub's own opening rule chose — the board, or a
        // combine screen reading "0 of 0 invited". It is the same room the
        // draft-prep `.workouts` stage names.
        case .personalWorkouts:
            CareerScopedDefaults.set("workouts", "scoutingPendingTab")
            shellDest = .scouting
        // Draft-prep stages (#103). Each lands in the scouting hub with a
        // pending-tab hint; the hub ignores a hint whose tab does not exist yet,
        // so a stage whose screen arrives in a later wave opens the hub rather
        // than a dead end.
        case .filmStudy:
            CareerScopedDefaults.set("film", "scoutingPendingTab")
            shellDest = .scouting
        case .proDayTour:
            CareerScopedDefaults.set("proDays", "scoutingPendingTab")
            shellDest = .scouting
        case .workouts:
            CareerScopedDefaults.set("workouts", "scoutingPendingTab")
            shellDest = .scouting
        case .top30Visits:
            CareerScopedDefaults.set("top30", "scoutingPendingTab")
            shellDest = .scouting
        case .mockDraft:
            CareerScopedDefaults.set("mockDraft", "scoutingPendingTab")
            shellDest = .scouting
        // #128. The January "Showcase & declarations" task. Without the hint
        // the hub opens on `currentStageTab`, which in `.reviewRoster` is the
        // combine — a screen with nothing in it until the league issues an
        // invite list, which it does not do until the combine window opens.
        case .classDepth:
            CareerScopedDefaults.set("classDepth", "scoutingPendingTab")
            shellDest = .scouting
        case .developmentReport:  shellDest = .developmentReport
        case .history:            shellDest = .history
        case .draftReportCard:    shellDest = .draftReportCard
        case .trainingPlan:        shellDest = .trainingPlan
        case .workloadDashboard:   shellDest = .workloadDashboard
        case .rosterCuts:          shellDest = .rosterCuts
        case .gameWeekPrep:        shellDest = .gameWeekPrep
        // #205b — the exhibition slate. Reached from the required camp task
        // row, from the hub's preseason hero card and from the league office's
        // letter when an advance is refused.
        case .preseason:           shellDest = .preseason
        }

        // §2.8: the calendar is a sheet and a task destination is a push, so the
        // two are handed off rather than fired together. With the calendar up
        // the route waits for its `onDismiss`; called from the dashboard's own
        // task rail there is no modal on screen and nothing to wait for, so the
        // push happens immediately instead of after a third of a second nobody
        // asked for.
        if shellSheet == .calendar {
            pendingRoute = shellDest
            shellSheet = nil
        } else {
            navigationPath = NavigationPath()
            navigationPath.append(shellDest)
        }
    }

    /// The cycle stamp every task write and read in this shell is filed under.
    private var taskCycle: String { TaskProgressStore.cycle(for: career) }

    /// Files the task list's current statuses so they survive a cold launch
    /// (#138a). Only the visit/complete states need this — every other
    /// completion is re-derived from the save by `refreshTaskCompletionStatus`
    /// — but recording all of them is free (`merge` never lowers a status and
    /// never writes when nothing moved) and it keeps one rule instead of two.
    private func persistTaskProgress() {
        var statuses: [String: TaskStatus] = [:]
        for task in currentTasks where task.status != .todo {
            // The group banner ships `.done` and is a label, not a step.
            guard !task.title.hasPrefix("\u{2500}") else { continue }
            // Draft-prep stages already have a durable authority of their own
            // (`DraftPrepProgress`, off per-cycle counters), and it is allowed to
            // pull a stage BACK to `.todo` when the club's reach no longer covers
            // it. A recorded `.done` here would out-rank that and re-open a
            // locked stage, so the store deliberately does not carry them.
            guard DraftPrepStep.stage(forTaskKey: task.matchKey) == nil else { continue }
            // Same reasoning for the cutdown rungs: the roster count is their
            // only authority and it can move in both directions inside one
            // phase. A recorded `.done` out-ranks a re-derivation, so a club
            // that claimed a man off waivers after making its 75 would come
            // back from a relaunch with a green rung over an illegal roster.
            guard TaskGenerator.cutLadderRung(forTaskKey: task.matchKey) == nil else { continue }
            statuses[task.matchKey] = task.status
        }
        TaskProgressStore.merge(statuses, in: taskCycle, season: career.currentSeason)
    }

    /// When a destination view appears, record that the player has been there.
    ///
    /// A task whose completion IS the visit (`completesOnVisit`) goes straight
    /// to `.done`; everything else records `.inProgress`, which is now purely
    /// cosmetic — the advance gate reads `.done` only (#138b). Both are written
    /// through ``TaskProgressStore`` so a relaunch does not undo them.
    private func markTaskVisited(for destination: TaskDestination) {
        var touched = false
        for index in currentTasks.indices {
            guard currentTasks[index].destination == destination,
                  currentTasks[index].status != .done else { continue }
            let visited: TaskStatus = currentTasks[index].completesOnVisit ? .done : .inProgress
            guard currentTasks[index].status != visited else { continue }
            currentTasks[index].status = visited
            touched = true
        }
        if touched { persistTaskProgress() }
    }

    /// How many men in THIS cycle's class the user has put a mark on.
    ///
    /// A `fetchCount`, not a fetch: this runs on every screen entry and every
    /// advance, and the class is ~350 rows. Scoped to the open save, which is
    /// also what scopes it to the cycle — `WeekAdvancer.purgeStaleSeasonData`
    /// deletes every `CollegeProspect` row when a season ends, so last spring's
    /// marks cannot tick this spring's row.
    private func markedProspectCount() -> Int {
        let cid = career.id
        let descriptor = FetchDescriptor<CollegeProspect>(
            predicate: #Predicate<CollegeProspect> {
                $0.careerID == cid && $0.userMarkTier != ""
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Mark a task as completed by its destination. Call this from specific
    /// view actions (e.g., after actually setting the depth chart, signing a
    /// player, completing the draft, etc.).
    func markTaskCompleted(for destination: TaskDestination) {
        var touched = false
        for index in currentTasks.indices {
            if currentTasks[index].destination == destination && currentTasks[index].status != .done {
                currentTasks[index].status = .done
                touched = true
            }
        }
        if touched { persistTaskProgress() }
    }

    // MARK: - Task Completion Refresh

    /// Checks actual game state against tasks and marks them done when the
    /// underlying condition is satisfied (e.g., coach hired, roster trimmed).
    ///
    /// IMPORTANT: Tasks should only auto-complete when a verifiable game-state
    /// condition is met (e.g., a coach was actually hired, the roster count
    /// dropped to 53). Merely visiting a screen should NOT auto-complete tasks.
    /// Phase transitions happen ONLY when the user taps the explicit "Advance"
    /// button, so we must not inflate task completion status here.
    func refreshTaskCompletionStatus() {
        guard let teamID = career.teamID else { return }

        // Ensure any pending inserts/updates are committed before querying
        try? modelContext.save()

        // Fetch current coaches. #133: scoped to the open save as well as the
        // club, exactly like the dashboard's and the Staff screen's fetches —
        // `teamID` alone is the same cross-save leak the tile was cured of.
        let cid = career.id
        let coachDescriptor = FetchDescriptor<Coach>(
            predicate: #Predicate<Coach> { $0.careerID == cid && $0.teamID == teamID }
        )
        let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []

        // #158: the staff gate the Season Guide sheet and `performShellAdvance`
        // both read. Built here because this is the one function that already
        // runs on every screen entry, every advance and every task refresh.
        let staffLedger = StaffLedger(
            careerRole: career.role,
            coaches: coaches,
            scouts: teamScouts(),
            owner: team?.owner
        )
        let staffBlocker = staffLedger.advanceBlocker(phase: career.currentPhase)
        staffAdvanceBlocker = staffBlocker

        let hasHC = staffLedger.filledCoachRoles.contains(.headCoach)
        let hasOC = staffLedger.filledCoachRoles.contains(.offensiveCoordinator)
        let hasDC = staffLedger.filledCoachRoles.contains(.defensiveCoordinator)

        // Fetch current roster
        let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
        let players = (try? modelContext.fetch(playerDescriptor)) ?? []
        let rosterCount = players.count

        // #208g: what the Advance buttons are drawn from. Staff first, then the
        // roster ceiling, the cap and the depth chart — the refusal order in
        // `performShellAdvance`, so the banner names the gate the tap would hit.
        advanceGateBlocker = staffBlocker ?? nonStaffAdvanceBlocker(roster: players)

        // Draft prep — ONE authority for every stage task (#104).
        //
        // Built once per refresh and consulted below instead of the per-stage
        // predicates this function used to carry. Those predicates were a second
        // copy of the hub's, keyed off different state, and the two disagreed in
        // both directions: "Choose pro-day schools" was completed from
        // `proDayCompleted` (an EXECUTION, written only after the tour has run)
        // while the hub's READY chip read reservations, and
        // "Order film study on your board" had no case here at all, so it could
        // never be completed by anything the user did. Same struct, same
        // numbers, one answer.
        let prepProgress = draftPrepProgress()

        // #138a — replay what this save has already recorded for THIS cycle
        // before deriving anything. The derivations below can only re-discover
        // completions the game world still carries (a coach was hired, a chart
        // was written); "the user opened this screen" leaves no such trace, so
        // without this replay a cold launch reopened finished tasks and re-locked
        // the phase advance behind them.
        let recorded = TaskProgressStore.statuses(in: taskCycle)
        if !recorded.isEmpty {
            for index in currentTasks.indices {
                let key = currentTasks[index].matchKey
                // Stage tasks answer to `DraftPrepProgress` alone — see
                // `persistTaskProgress`, which does not file them either.
                guard DraftPrepStep.stage(forTaskKey: key) == nil,
                      let saved = recorded[key] else { continue }
                // Raise only: a derivation below may legitimately push a task
                // further than the record goes.
                if saved == .done || (saved == .inProgress && currentTasks[index].status == .todo) {
                    currentTasks[index].status = saved
                }
            }
        }

        for index in currentTasks.indices {
            // The cutdown ladder (#205a §5.1) — the ONE row per camp phase that
            // answers to the roster count, and the only one in this function
            // that answers to it in BOTH directions.
            //
            // Handled ahead of the `.done` guard on purpose. A camp roster can
            // grow again after the rung is met — a waiver claim, a trade, a
            // signing — and a rung latched at `.done` would leave the rail's
            // banner silent and the Advance button live while
            // `WeekAdvancer.userRosterLimitViolation` refuses the advance with
            // an alert. That split (the panel not knowing what the gate knows)
            // is #154f, and the fix is that both read the same count.
            //
            // The counter on the title is re-stamped here for the same reason
            // the draft-prep counters are: the list is only rebuilt on a phase
            // or week change, and every offseason phase holds the week still,
            // so "Cut to 75 (80 currently)" would sit there all camp while the
            // user cut his way down to 75.
            // #205b — the preseason slate. Handled ahead of the `.done` guard
            // for the same reason the cut ladder is: the counter on the title
            // has to move as the games are played, and the list is only rebuilt
            // on a phase change, so a frozen title would read "(0/3 played)"
            // through the whole slate.
            //
            // Completion is the engine's own exit predicate, asked of a SEEDED
            // blob (`ensuredPreseasonState`), so this row and
            // `performShellAdvance` can never disagree — the split that made
            // #154f a bug. An undrawable slate (broken league, no opponents)
            // answers `true` and the row ticks: a phase nobody can leave is
            // worse than a phase nobody has to play.
            if currentTasks[index].matchKey == TaskGenerator.preseasonSlateTaskKey {
                let slate = ensuredPreseasonState()
                let played = slate?.results.count ?? 0
                let total = slate?.slate.count ?? 0
                currentTasks[index].title = TaskGenerator.preseasonSlateTitle(
                    gamesPlayed: played,
                    slateSize: total
                )
                if PreseasonEngine.canLeavePreseason(slate) {
                    currentTasks[index].status = .done
                } else {
                    currentTasks[index].status = played > 0 ? .inProgress : .todo
                }
                continue
            }

            // "Update Big Board" (#11). Handled ahead of the `.done` guard for
            // the same reason the two rows above are: the counter on the title
            // has to move as the user marks men, and the list is only rebuilt
            // on a phase change. Unmarking cannot un-tick it — the row is a
            // "you have started working the board" nudge, not a quota with a
            // gate behind it, and a task that flickers off is worse than one
            // that stays green.
            if currentTasks[index].matchKey == TaskGenerator.bigBoardTaskKey {
                let marked = markedProspectCount()
                currentTasks[index].title = TaskGenerator.bigBoardTitle(marked: marked)
                if marked >= TaskGenerator.bigBoardMarkThreshold {
                    currentTasks[index].status = .done
                } else if marked > 0, currentTasks[index].status == .todo {
                    currentTasks[index].status = .inProgress
                }
                continue
            }

            if let rung = TaskGenerator.cutLadderRung(forTaskKey: currentTasks[index].matchKey) {
                let over = rosterCount > rung.target
                currentTasks[index].title = TaskGenerator.cutLadderTitle(rung, rosterCount: rosterCount)
                currentTasks[index].status = over ? .todo : .done
                // …and `isRequired` with it. `rosterLadderTask` arms the row
                // with `isRequired: over > 0` at generation time, and the list
                // is only rebuilt on a phase or week change — so a club that
                // entered the phase already under the rung carried a row that
                // could never become required again. Re-stamping only `status`
                // left the row red and the counter at zero, which is the exact
                // panel/gate split the comment above claims to have closed:
                // `incompleteRequiredCount` filters on `isRequired && != .done`.
                currentTasks[index].isRequired = over
                continue
            }

            guard currentTasks[index].status != .done else { continue }
            let task = currentTasks[index]

            // Draft prep — stage-driven completion AND locking.
            //
            // `isSatisfied` completes it, `unlocked` locks it, and the counter is
            // re-stamped on the title every pass. The list itself is only rebuilt
            // on a PHASE change (`regenerateTasks` guards on
            // `lastGeneratedPhase`), so without this restamp the "(12/60
            // interviews)" the generator wrote at the top of the phase would sit
            // there unchanged all spring while the process bar counted up.
            if let stage = DraftPrepStep.stage(forTaskKey: task.matchKey) {
                let row = prepProgress[stage]
                currentTasks[index].title = (row.isCounted && row.done > 0)
                    ? "\(task.matchKey) (\(row.done)/\(row.total) \(row.unit))"
                    : task.matchKey
                if row.isSatisfied {
                    currentTasks[index].status = .done
                } else if !row.unlocked {
                    // Ahead of the club's reach: visiting the screen must not
                    // tick it off early.
                    currentTasks[index].status = .todo
                }
                continue
            }

            // Matched on `matchKey`, not on the raw title: several titles carry a
            // live progress counter ("… (12/60 done)") and an exact-title switch
            // silently stopped completing them the moment one appeared.
            switch task.matchKey {
            // Cap compliance — the cross-phase overlay `TaskGenerator
            // .capComplianceTasks` emits. It had no completion case at all,
            // which was survivable only while a mere visit satisfied the advance
            // gate: now that the gate reads `.done`, a REQUIRED row nothing can
            // tick is a phase nobody can leave.
            //
            // Delegated to the engine's own gate rather than to
            // `complianceStatus` alone, so the two cannot disagree. It returns
            // `nil` both when the books are legal and in the fully-guaranteed
            // corner where no lever exists — which is exactly the anti-deadlock
            // rule the advance already honours (`WeekAdvancer
            // .userCapComplianceViolation`), and the one case where leaving the
            // task open would strand the career.
            case "Get under the salary cap":
                let violation = WeekAdvancer.userCapComplianceViolation(
                    career: career,
                    modelContext: modelContext
                )
                if violation == nil {
                    currentTasks[index].status = .done
                }

            // Coaching Changes — verified by actual game state (coach exists)
            case "Hire Head Coach":
                if hasHC { currentTasks[index].status = .done }
            case "Hire Offensive Coordinator":
                if hasOC { currentTasks[index].status = .done }
            case "Hire Defensive Coordinator":
                if hasDC { currentTasks[index].status = .done }

            // The 53-man row used to be matched here by title substring. It is a
            // cut-ladder rung like the other two now, and all three are handled
            // above off `CutDay.target` — one authority for the whole ladder.

            // Review Roster tasks — check actual game state / user confirmations
            case "Review Position Group Grades":
                if CareerScopedDefaults.bool("rosterEvaluationConfirmed") {
                    currentTasks[index].status = .done
                }
            case "Analyze Contract Situations":
                if CareerScopedDefaults.bool("rosterEvaluationConfirmed") {
                    currentTasks[index].status = .done
                }
            case "Franchise Tag Decisions":
                // Complete if a franchise tag was applied OR the user confirmed evaluation
                let hasFranchiseTag = players.contains { $0.isFranchiseTagged }
                if hasFranchiseTag || CareerScopedDefaults.bool("franchiseTagVisited") {
                    currentTasks[index].status = .done
                }
            case "Check Salary Cap Outlook":
                // Auto-complete once visited — viewing cap data is the action
                if currentTasks[index].status == .inProgress {
                    currentTasks[index].status = .done
                }
            case "Set Roster Priorities":
                if let data = CareerScopedDefaults.string("rosterPriorities"),
                   !data.isEmpty, data != "{}" {
                    currentTasks[index].status = .done
                }

            // Combine — sequential task unlocking
            case "Send scouts to Combine":
                if CareerScopedDefaults.bool("scoutsSentToCombine") {
                    currentTasks[index].status = .done
                }

            // "Review Combine results" and "Conduct prospect interviews" used to
            // live here with hand-written predicates. They are `DraftPrepStep`
            // stages, so the block above owns them now — including the
            // combine-held test, which `DraftPrepProgress` folds into
            // `.combineReview`'s satisfaction.

            case "Review interview report":
                // Locked until interviews conducted
                let interviewsDone = currentTasks.first(where: { $0.matchKey == "Conduct prospect interviews" })?.status == .done
                if !interviewsDone {
                    currentTasks[index].status = .todo
                } else if CareerScopedDefaults.bool("interviewReportReviewed") {
                    // User opened/closed the InterviewReportView → report reviewed
                    currentTasks[index].status = .done
                } else if career.interviewsUsed >= 60 {
                    // Backstop for stuck saves: all 60 interviews used means the
                    // post-interview report was shown automatically; treat as reviewed.
                    CareerScopedDefaults.set(true, "interviewReportReviewed")
                    currentTasks[index].status = .done
                }

            // OTAs — verified by actual persisted game state
            case "Set depth chart":
                // Done once the user has saved a chart (edit or Auto-Set).
                // Deliberately does NOT require every slot filled — a roster
                // hole (e.g. no kicker) must never make the task impossible.
                if career.depthChartData != nil {
                    currentTasks[index].status = .done
                }

            // Game plan — done once the user has saved a plan at least once
            // (sliders or preset). Weekly "Set game plan for <opponent>" tasks
            // are completed in-session via markTaskCompleted(.gamePlan).
            case "Set game plan":
                if career.gamePlanData != nil {
                    currentTasks[index].status = .done
                }

            case "Set training focus":
                // Done once a TrainingPlan row exists for the current
                // (team, season, week, phase) key — i.e. the user hit Save.
                let season = career.currentSeason
                let week = career.currentWeek
                let phaseRaw = career.currentPhase.rawValue
                let planDescriptor = FetchDescriptor<TrainingPlan>(
                    predicate: #Predicate {
                        $0.teamID == teamID
                            && $0.seasonYear == season
                            && $0.weekNumber == week
                            && $0.phaseRaw == phaseRaw
                    }
                )
                if let count = try? modelContext.fetchCount(planDescriptor), count > 0 {
                    currentTasks[index].status = .done
                }

            // Draft — done when this season's draftees are on the roster, OR
            // when there is nothing left on the board for this club to use.
            //
            // The roster check alone made this REQUIRED gate unsatisfiable for a
            // GM who arrived at the draft holding no picks — traded them all,
            // or simply never had one in the round the generator gave him. He
            // drafted nobody, no rookie ever appeared, and the phase could not
            // be advanced from either surface: a dead career with no message
            // explaining why. Having no incomplete pick left IS a finished
            // draft, so it counts as one.
            case "Enter the Draft":
                if players.contains(where: { $0.draftPickNumber != nil && $0.yearsPro == 0 }) {
                    currentTasks[index].status = .done
                } else {
                    let draftSeason = career.currentSeason
                    let ownPicksDescriptor = FetchDescriptor<DraftPick>(
                        predicate: #Predicate<DraftPick> {
                            $0.currentTeamID == teamID
                                && $0.seasonYear == draftSeason
                                && $0.isComplete == false
                        }
                    )
                    let picksLeft = (try? modelContext.fetchCount(ownPicksDescriptor)) ?? 1
                    if picksLeft == 0 {
                        currentTasks[index].status = .done
                    }
                }

            // Pro Days — completion checks.
            //
            // "Choose pro-day schools" used to be completed here from
            // `proDayCompleted == true`, i.e. from the tour having RUN. The
            // stage asks the user to *reserve* schools and the tour is the
            // transition out of it, so the task could only tick after the stage
            // it belonged to had closed. `DraftPrepProgress` counts the
            // reservations (`scout.proDayColleges`) and the block above applies
            // it, so the row ticks when the user books a school.

            case "Review Pro Day results":
                // Done if visited scouting after pro days attended
                if currentTasks[index].status == .inProgress {
                    currentTasks[index].status = .done
                }

            // Free Agency — sequential task unlocking based on career.freeAgencyStep
            case "Final Push \u{2014} Re-sign or let walk":
                let step = FreeAgencyStep(rawValue: career.freeAgencyStep)
                if step != .finalPush {
                    currentTasks[index].status = .done
                }

            case "Start New League Year":
                let step = FreeAgencyStep(rawValue: career.freeAgencyStep)
                if step == .finalPush {
                    // Locked — Final Push not done yet
                    currentTasks[index].status = .todo
                } else if step != .newLeagueYear {
                    currentTasks[index].status = .done
                }

            case "Roster & Cap compliance":
                let step = FreeAgencyStep(rawValue: career.freeAgencyStep)
                if step == .finalPush || step == .newLeagueYear {
                    // Locked — previous steps not done
                    currentTasks[index].status = .todo
                } else if step != .capReview {
                    currentTasks[index].status = .done
                }

            case "Free agency signings":
                let step = FreeAgencyStep(rawValue: career.freeAgencyStep)
                if step == .finalPush || step == .newLeagueYear || step == .capReview {
                    // Locked — must complete cap review first
                    currentTasks[index].status = .todo
                } else if step == .complete {
                    currentTasks[index].status = .done
                }

            // All other tasks: do NOT auto-complete based on visit status.
            // The user must explicitly tap "Advance" to progress the phase.
            // Visiting a screen only marks the task as .inProgress (via
            // markTaskVisited), which gives visual feedback without
            // triggering phase advancement.
            default:
                break
            }
        }
    }

    // MARK: - Bookmark Navigation

    private func handleBookmarkNavigation(_ bookmark: TopNavigationBar.BookmarkDestination) {
        let dest: ShellDestination
        switch bookmark {
        // The hub IS the root of this stack (#105 wave 2, P6): it is a
        // bookmark like the other six, and "go to the hub" is "pop to root".
        // Returning early rather than pushing a `.hub` destination keeps one
        // dashboard instance alive instead of stacking a second copy of the
        // screen the user is already looking at.
        case .hub:
            navigationPath = NavigationPath()
            return
        case .roster:        dest = .roster
        case .draft:         dest = .draft
        case .scouting:      dest = .scouting
        case .cap:           dest = .capOverview
        case .coachingStaff: dest = .coachingStaff
        case .trades:        dest = .trades
        }
        // Reset to root then push the destination
        navigationPath = NavigationPath()
        navigationPath.append(dest)
    }

    // MARK: - Pending Task Count

    /// Badge count: number of incomplete required tasks.
    private var pendingTaskCount: Int {
        TaskGenerator.incompleteRequiredCount(in: currentTasks)
    }

    /// Derive the current playoff round name from the career week.
    /// Week mapping: 19 = Wild Card, 20 = Divisional, 21 = Conference Championships.
    private var playoffRoundName: String? {
        guard career.currentPhase == .playoffs else { return nil }
        switch career.currentWeek {
        case 19: return "Wild Card"
        case 20: return "Divisional Round"
        case 21: return "Conference Championships"
        default: return nil
        }
    }

    // MARK: - Task Generation

    /// Regenerate the task list for the given phase using current game state.
    ///
    /// Rebuilt on a phase change **or a week change**: several titles name the
    /// week's opponent, and in the regular season the phase does not move for
    /// eighteen of them (#154). Completion is not lost by the rebuild — the
    /// statuses are re-derived from the save and from ``TaskProgressStore``
    /// immediately afterwards, and the store is stamped per week, so the new
    /// week's list correctly opens fresh.
    private func regenerateTasks(for phase: SeasonPhase) {
        let week = career.currentWeek
        guard phase != lastGeneratedPhase || week != lastGeneratedWeek else { return }
        lastGeneratedPhase = phase
        lastGeneratedWeek = week

        let rosterCount: Int
        if let teamID = career.teamID {
            let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
            rosterCount = (try? modelContext.fetchCount(playerDescriptor)) ?? 53
        } else {
            rosterCount = 53
        }

        // R21: AI trade offers are persisted on the career (WeekAdvancer
        // generates them weekly; TradeView consumes/prunes them).
        let hasPendingTradeOffers = !career.pendingTradeOffers.isEmpty

        // Detect coaching vacancies. #133: same scoped fetch and same seat
        // reading as `refreshTaskCompletionStatus` — these two used to be
        // separate inline copies, and only one of them carried `careerID`.
        var hasHC = true
        var hasOC = true
        var hasDC = true
        if let teamID = career.teamID {
            let cid = career.id
            let coachDescriptor = FetchDescriptor<Coach>(
                predicate: #Predicate<Coach> { $0.careerID == cid && $0.teamID == teamID }
            )
            let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
            let filled = StaffLedger(
                careerRole: career.role,
                coaches: coaches,
                scouts: [],
                owner: nil
            ).filledCoachRoles
            hasHC = filled.contains(.headCoach)
            hasOC = filled.contains(.offensiveCoordinator)
            hasDC = filled.contains(.defensiveCoordinator)
        }

        // Check roster for players with 1 year or less remaining on contract
        let hasExpiringContracts: Bool = {
            guard let teamID = career.teamID else { return false }
            let playerDescriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.teamID == teamID })
            let players = (try? modelContext.fetch(playerDescriptor)) ?? []
            return players.contains { $0.contractYearsRemaining <= 1 }
        }()

        // Check if any scouts are assigned to the team
        let hasScoutsAssigned: Bool = {
            guard let teamID = career.teamID else { return false }
            let scoutDescriptor = FetchDescriptor<Scout>(predicate: #Predicate { $0.teamID == teamID })
            let count = (try? modelContext.fetchCount(scoutDescriptor)) ?? 0
            return count > 0
        }()
        let hasPendingEvents = !WeekAdvancer.lastEvents.isEmpty
        let ownerSatisfaction = team?.owner?.satisfaction ?? 50

        // Cycle progress the generator has always accepted and nobody ever
        // passed, so a save reopened mid-phase came back with every scouting
        // step at zero. `refreshTaskCompletionStatus` corrects the statuses a
        // moment later; these make the list correct on the FIRST frame, and put
        // the interview counter in the row title where the user can see it.
        let cid = career.id
        let draftSeason = career.currentSeason
        let proDayDone: Bool = {
            let descriptor = FetchDescriptor<CollegeProspect>(
                predicate: #Predicate { $0.careerID == cid && $0.proDayCompleted == true }
            )
            return ((try? modelContext.fetchCount(descriptor)) ?? 0) > 0
        }()
        let draftAlreadyRun: Bool = {
            guard let teamID = career.teamID else { return false }
            let descriptor = FetchDescriptor<DraftPick>(
                predicate: #Predicate<DraftPick> {
                    $0.currentTeamID == teamID
                        && $0.seasonYear == draftSeason
                        && $0.isComplete == false
                }
            )
            return ((try? modelContext.fetchCount(descriptor)) ?? 1) == 0
        }()

        // Determine opponent name for game-week phases. `currentWeekGame`, not
        // `upcomingGames.first`: the same fixture the hero card and the Opponent
        // Scout tile name, so the three cannot describe three different Sundays.
        var opponentName: String? = nil
        if let nextGame = currentWeekGame {
            let isHome = nextGame.homeTeamID == career.teamID
            let opponentID = isHome ? nextGame.awayTeamID : nextGame.homeTeamID
            opponentName = allTeamsByID[opponentID]?.fullName
        }

        currentTasks = TaskGenerator.generateTasks(
            for: phase,
            career: career,
            team: team,
            rosterCount: rosterCount,
            hasPendingTradeOffers: hasPendingTradeOffers,
            hasHeadCoach: hasHC,
            hasOC: hasOC,
            hasDC: hasDC,
            hasExpiringContracts: hasExpiringContracts,
            opponentName: opponentName,
            playoffRoundName: playoffRoundName,
            // QA 2026-08-22: a 4-13 club that missed the playoffs was still told
            // to "Prepare for Wild Card vs your opponent". `upcomingGames` holds
            // only UNPLAYED games at or after the current week, so it is empty
            // exactly when the club has nothing left to play — which is what the
            // postseason list needs to know.
            hasUpcomingGame: !upcomingGames.isEmpty,
            hasScoutsAssigned: hasScoutsAssigned,
            hasPendingEvents: hasPendingEvents,
            ownerSatisfaction: ownerSatisfaction,
            isDraftComplete: draftAlreadyRun,
            interviewsDone: career.interviewsUsed,
            allScoutsAssignedToProDays: proDayDone,
            prepProgress: draftPrepProgress()
        )
    }

    /// The draft-prep authority, built for the task list.
    ///
    /// `TaskGenerator` has taken a `prepProgress:` since #104 and **nothing in
    /// the app ever passed one**, so every per-stage completion and every live
    /// counter in that file was dead code: `progress?[step]` was always `nil`,
    /// every stage task shipped `.todo`, and the process bar and the left bar
    /// went on printing different answers for the same work — the exact split
    /// the struct exists to close.
    ///
    /// Cheap enough to build on every completion refresh: the draft class is
    /// already in memory (`WeekAdvancer.currentDraftClass`) and the only fetch
    /// is the club's own scouts, which the pro-day focus ledger lives on.
    private func draftPrepProgress() -> DraftPrepProgress {
        DraftPrepProgress(
            career: career,
            prospects: WeekAdvancer.currentDraftClass,
            scouts: teamScouts()
        )
    }

    /// The club's scouting department, scoped to the open save (#133).
    ///
    /// One fetch, two readers: the draft-prep authority and the staff ledger.
    /// Both used to spell it out inline, and one of them left the `careerID`
    /// clause off.
    private func teamScouts() -> [Scout] {
        guard let teamID = career.teamID else { return [] }
        let cid = career.id
        let descriptor = FetchDescriptor<Scout>(
            predicate: #Predicate<Scout> { $0.careerID == cid && $0.teamID == teamID }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Inbox Collection

    /// Binding that persists on write.
    ///
    /// `InboxView` marks a message read through this binding and
    /// `CareerDashboardView` reads from it; routing both through here means a
    /// read receipt survives the trip back to the dashboard, and a message a
    /// child view adds is save data the instant it appears.
    private var inboxBinding: Binding<[InboxMessage]> {
        Binding(
            get: { inboxMessages },
            set: { newValue in
                inboxMessages = newValue
                career.inbox = newValue
                try? modelContext.save()
            }
        )
    }

    /// Writes the current mailbox back to the career.
    private func persistInbox() {
        career.inbox = inboxMessages
        try? modelContext.save()
    }

    /// Drains newly generated inbox messages from the `WeekAdvancer` channel
    /// into the persisted mailbox.
    ///
    /// The channel itself is a process-global staging area that every producer
    /// (`WeekAdvancer`, `DraftDayCoordinator`, `TradeView` outside the shell)
    /// appends to; this is the only consumer. Called after each phase/week
    /// transition, on every navigation change, and immediately BEFORE an advance
    /// — `advanceWeek` clears the channel on entry, so anything staged since the
    /// last drain has to be collected first (task #19).
    func collectInboxMessages() {
        let newMessages = WeekAdvancer.lastInboxMessages
        guard !newMessages.isEmpty else { return }
        inboxMessages.append(contentsOf: newMessages)
        // Clear so we don't double-add on next read
        WeekAdvancer.lastInboxMessages = []
        persistInbox()
    }

    // MARK: - Data Loading

    /// Re-reads this season's schedule: `currentWeekGame`, `upcomingGames` and
    /// the week ladder's `seasonFixtures`.
    ///
    /// Split out of `loadShellData` because **a coached game never goes through
    /// an advance**. `CareerDashboardView.finishCoachedGame` persists the score
    /// and reloads its own state, and nothing told the shell — so the pinned
    /// ladder went on drawing Sunday's slat as an unplayed fixture ("@ PHI", no
    /// result line, no W/L tint) while the hero card above it already showed
    /// the win, and only the next Advance put them back in agreement. That
    /// disagreement between two week-scoped labels is exactly the bug class the
    /// band exists to make impossible (#154). One fetch of this season's games,
    /// so it is cheap enough to run every time a result is recorded.
    private func reloadSeasonFixtures() {
        guard let teamID = career.teamID else { return }
        let cid = career.id
        let seasonYear = career.currentSeason
        let gameDescriptor = FetchDescriptor<Game>(predicate: #Predicate {
            $0.careerID == cid && $0.seasonYear == seasonYear
        })
        let allGames = (try? modelContext.fetch(gameDescriptor)) ?? []

        let myGames = allGames.filter { $0.homeTeamID == teamID || $0.awayTeamID == teamID }
        upcomingGames = myGames
            .filter { !$0.isPlayed && $0.week >= career.currentWeek }
            .sorted { $0.week < $1.week }
        // This week's fixture whether or not it has been played; only once the
        // week itself is empty (a bye, or the schedule has run out) does the
        // next one on the card stand in. See `currentWeekGame`.
        currentWeekGame = myGames.first { $0.week == career.currentWeek } ?? upcomingGames.first

        // The season ladder (P1's week-ladder amendment). Built from the fetch
        // that is already in hand rather than from a second one, so the band
        // and the hero card can never name two different opponents — the class
        // of bug #154 was.
        // `uniquingKeysWith` rather than `uniqueKeysWithValues`: the latter traps
        // on a duplicate key, and one malformed schedule row would then take the
        // whole shell down on open. Two rows in one week is a data fault, not a
        // crash — keep the first and carry on.
        //
        // A `nil` abbreviation would read as a BYE, which a missing team row is
        // not, so an unresolvable opponent says "TBD" instead. The bye is the
        // week that has no row at all.
        seasonFixtures = Dictionary(
            myGames.map { game in
                let isHome = game.homeTeamID == teamID
                let opponentID = isHome ? game.awayTeamID : game.homeTeamID
                return (
                    game.week,
                    SeasonWeekBand.Fixture(
                        week: game.week,
                        opponentAbbreviation: allTeamsByID[opponentID]?.abbreviation ?? "TBD",
                        isHome: isHome,
                        ourScore: isHome ? game.homeScore : game.awayScore,
                        theirScore: isHome ? game.awayScore : game.homeScore
                    )
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func loadShellData() {
        // MULTI-SAVE ISOLATION — must run FIRST.
        //
        // 1. Adopt any legacy rows (`careerID == nil`) into the save they
        //    belong to. Every scoped fetch below filters on `careerID`, so an
        //    unadopted save would render as an empty league.
        // 2. Bind the engine's process-global statics (draft class, trade caps,
        //    `wasFired`) to THIS career, wiping whatever the previously opened
        //    save left behind.
        // 3. Hand the legacy un-suffixed AppStorage values (roster notes,
        //    prospect board) to this career's namespace, once.
        CareerScope.adoptLegacyRowsIfNeeded(context: modelContext)
        WeekAdvancer.bind(to: career)
        // `currentDraftClass` is a process static that `bind` just wiped, and
        // its only other writers are `advanceWeek` and the scouting hub's
        // load. A cold launch that lands on the DASHBOARD therefore drove the
        // "Path to the Draft" hero and the required-task chain off an EMPTY
        // class — 0% scouted, combine "Not read", and `canAdvance` false on
        // both advance buttons until the user happened to open Scouting.
        _ = WeekAdvancer.restoreDraftClassIfNeeded(career: career, modelContext: modelContext)
        CareerScopedDefaults.migrateGlobalKeys(into: career.id)
        #if DEBUG
        if ProcessInfo.processInfo.environment["CAREERID_AUDIT"] != nil {
            CareerScope.debugAuditCounts(context: modelContext, label: "open/\(career.playerName)")
        }
        #endif

        // Phase 4 faces: bind the library to THIS career and backfill anyone
        // still portrait-less. Done on shell load rather than only on the next
        // week advance so a legacy save shows real faces the moment it opens.
        loadFaceLibrary()

        guard let teamID = career.teamID else { return }

        // One-time data integrity pass: bring legacy `scoutGrade` and the new
        // `scoutedOverallGrade` into agreement on existing saves so every list
        // shows the same letter for the same prospect.
        syncProspectGrades()

        let cid = career.id
        let allTeamsDescriptor = FetchDescriptor<Team>(
            predicate: #Predicate { $0.careerID == cid }
        )
        let allTeams = (try? modelContext.fetch(allTeamsDescriptor)) ?? []
        allTeamsByID = Dictionary(uniqueKeysWithValues: allTeams.map { ($0.id, $0) })

        team = allTeamsByID[teamID]

        // The schedule: this week's fixture, the games still to come, and the
        // week ladder's slats. Its own function because a coached game has to
        // refresh it without reloading the whole shell (see below).
        reloadSeasonFixtures()

        // Generate tasks on initial load, then re-derive completion from
        // persisted game state so a relaunch doesn't reset finished tasks.
        regenerateTasks(for: career.currentPhase)
        refreshTaskCompletionStatus()

        // Wave 3: the mailbox is save data. Hydrate from the career first, then
        // drain anything a previous session staged on the `WeekAdvancer`
        // channel, and only generate a starter set when the career has genuinely
        // never received mail.
        if inboxMessages.isEmpty {
            inboxMessages = career.inbox
        }
        collectInboxMessages()

        if inboxMessages.isEmpty, let playerTeam = team {
            let coachDescriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
            let coaches = (try? modelContext.fetch(coachDescriptor)) ?? []
            // #3553: the scouting letters in the starter batch are signed by
            // the man in the chair, not by the office. Role is filtered in
            // Swift, as `CoachingStaffView` does — `#Predicate` on the enum
            // buys nothing on a table this small.
            let scoutDescriptor = FetchDescriptor<Scout>(predicate: #Predicate { $0.teamID == teamID })
            let scouts = (try? modelContext.fetch(scoutDescriptor)) ?? []
            let messages = InboxEngine.generatePhaseMessages(
                phase: career.currentPhase,
                career: career,
                team: playerTeam,
                coaches: coaches,
                owner: playerTeam.owner,
                chiefScout: scouts.first { $0.scoutRole == .chiefScout }
            )
            inboxMessages = messages
            persistInbox()
        }
    }

    /// Binds `FaceLibrary` to this career and backfills missing portraits.
    ///
    /// Mirrors `WeekAdvancer.backfillLegacyFaces` (which covers the advance
    /// path); running it here too means a save opened and browsed without ever
    /// advancing a week still renders faces.
    ///
    /// **Runs its fetches ONCE per opened save.** `loadShellData()` is also the
    /// post-advance reload (`Advance Week` → `shell_reload`), and the full
    /// reconciliation needs three unpredicated fetches — `Player` is the largest
    /// table in the store and grows monotonically (~13 k rows over a 30-season
    /// career, retired players kept for history). Repeating that on the main
    /// thread inside the button handler bought nothing: `WeekAdvancer` has
    /// already run the very same backfill during the advance, with the
    /// players/coaches it fetched for the sim. So later reloads only re-bind the
    /// library, which is a dictionary swap.
    private func loadFaceLibrary() {
        FaceLibrary.shared.activate(career: career)
        guard !didReconcileFaces else { return }
        didReconcileFaces = true

        // Scoped hard: `FaceLibrary.backfill` rebuilds `registry.inUse` from the
        // population it is handed and CLEARS the loser's faceID on collision, so
        // a store-wide array let career A's open rewrite career B's portraits —
        // and made the "living people vs. catalog size" capacity gate count two
        // leagues against one catalog, disabling collision repair entirely.
        let faceCareerID = career.id
        let players = (try? modelContext.fetch(FetchDescriptor<Player>(
            predicate: #Predicate { $0.careerID == faceCareerID }
        ))) ?? []
        let coaches = (try? modelContext.fetch(FetchDescriptor<Coach>(
            predicate: #Predicate { $0.careerID == faceCareerID }
        ))) ?? []
        WeekAdvancer.backfillLegacyFaces(career: career, players: players, coaches: coaches)

        // Prospects only ever hold a preview face, so they are handled apart
        // from the reserving backfill. New classes get theirs in
        // `DraftClassBuilder`, so this only covers rows that predate the field.
        let prospects = (try? modelContext.fetch(FetchDescriptor<CollegeProspect>(
            predicate: #Predicate { $0.careerID == faceCareerID }
        ))) ?? []
        for prospect in prospects where prospect.faceID == nil {
            prospect.faceID = FaceLibrary.shared.previewFace(
                personID: prospect.id, role: .player,
                age: prospect.age, position: prospect.position
            )
        }

        // Owners draw from their own 96-portrait pool, not the face library, and
        // are created exactly once per league — so unlike players and coaches they
        // need no per-advance pass, only this one-shot repair for careers that
        // predate `Owner.faceID` (`ExtrasCatalog.backfillOwnerFaces`).
        let owners = (try? modelContext.fetch(FetchDescriptor<Owner>(
            predicate: #Predicate { $0.careerID == faceCareerID }
        ))) ?? []
        ExtrasCatalog.shared.backfillOwnerFaces(owners)
    }

    /// Career-scoped flag holding the band-repair version this save has had run.
    /// Listed in `CareerScopedDefaults.keys` so deleting a save takes it along.
    private static let prospectBandRepairKey = "prospectBandRepairVersion"

    /// Bump to re-run the repair on saves that have already had the current one.
    private static let prospectBandRepairVersion = 1

    /// The honest stored band for a man NO report of this regime's backs.
    ///
    /// The inherited "Previous Staff" row is real paper, so it is worth exactly
    /// what one report is worth — `ProspectFog.firstReportBand`, ±2 grades,
    /// `reportCount` 1 — centred on the grade that row actually carries. A man
    /// with no report at all gets no stored band: `effectiveOverallGrade` and
    /// `ProspectFog.read` still derive a read from `scoutedOverall` on the fly,
    /// and deriving it is not the same as asserting it into the store.
    private func honestUnbackedBand(for prospect: CollegeProspect) -> GradeRange? {
        guard let inherited = prospect.scoutingReports
            .max(by: { $0.confidenceLevel < $1.confidenceLevel }) else { return nil }
        let centre = inherited.overallLetterGrade
            ?? LetterGrade.from(numericValue: inherited.overallGrade)
        return ProspectFog.firstReportBand(centredOn: centre)
    }

    /// Pins the legacy `scoutGrade` letter to the modern `scoutedOverallGrade`
    /// range — and REPAIRS the bands an earlier build of this same function
    /// fabricated.
    ///
    /// ## What it used to do, and why it corrupted saves
    ///
    /// The old pass back-filled `scoutedOverallGrade` from the legacy
    /// `scoutedOverall` using `GradeRange(grade:)` — a range whose `low == high`
    /// **and** whose `reportCount` is **3**, i.e. the store's way of saying
    /// "three reports have converged on exactly this letter".
    /// `ScoutingEngine.applyPreScoutedData` sets `scoutedOverall` on the top
    /// ~250 of every class at career creation, so the FIRST load of a brand new
    /// save wrote a maximum-confidence, zero-width band onto a third of the
    /// class off paper the user never ordered, and then persisted it.
    ///
    /// The second-order damage is worse than the display. With a band already
    /// stored, `ScoutingEngine.applyGradeBasedFields` takes the
    /// `GradeRange.incorporate(newGrade:)` branch instead of the first-report
    /// branch — and `incorporate` at `reportCount >= 3` collapses straight back
    /// to a single grade. A real report filed later could therefore NEVER open
    /// the band to the ±2 it is supposed to buy: every one of those men stayed
    /// pinned at pinpoint certainty for the life of the save, and the scouting
    /// economy's whole "each report narrows the range" promise was dead on
    /// arrival for exactly the men the user cares most about.
    ///
    /// ## What it does now
    ///
    /// * **It never invents a band.** Nothing needs one written to render a
    ///   read: `CollegeProspect.effectiveOverallGrade` derives one from
    ///   `scoutedOverall` on the fly, and `ProspectFog.read` widens it by
    ///   `DraftIntel.scoutConfidence` before anybody sees it.
    /// * **It repairs saves the old pass touched**, once. A prospect no report
    ///   of this regime's backs gets the honest band (`honestUnbackedBand`) or
    ///   no band at all.
    /// * **It never touches a band that has a backing report.** The gate is
    ///   `ProspectFog.hasOwnReport`, the same "scoutName != Previous Staff"
    ///   test the Film Study pill and the evaluation price ladder already use,
    ///   so a band three real reports converged on is left converged.
    ///
    /// Runs its repair ONCE per save, like `restoreDraftClassIfNeeded` and
    /// `loadFaceLibrary` beside it — `loadShellData()` is also the post-advance
    /// reload, and the repair is a full unpredicated walk of the class. The
    /// `scoutGrade` pin below stays idempotent and runs every load, as it did.
    private func syncProspectGrades() {
        let cid = career.id
        let prospects = (try? modelContext.fetch(FetchDescriptor<CollegeProspect>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        let repairedVersion: Int = CareerScopedDefaults.value(Self.prospectBandRepairKey) ?? 0
        let needsRepair = repairedVersion < Self.prospectBandRepairVersion
        var changed = 0

        for prospect in prospects {
            // 1. Repair: a persisted band with no work of this regime's behind
            //    it is not evidence, it is the old back-fill's fabrication.
            if needsRepair, !ProspectFog.hasOwnReport(prospect) {
                let honest = honestUnbackedBand(for: prospect)
                if prospect.scoutedOverallGrade != honest {
                    prospect.scoutedOverallGrade = honest
                    changed += 1
                }
            }

            // 2. Pin the legacy `scoutGrade` to the range's mid-grade so any
            //    older code path that still reads `scoutGrade` agrees with the UI.
            if let range = prospect.scoutedOverallGrade {
                let canonical = range.midGrade.rawValue
                if prospect.scoutGrade != canonical {
                    prospect.scoutGrade = canonical
                    changed += 1
                }
            }
        }

        if changed > 0 {
            try? modelContext.save()
        }
        // Stamp only when the walk saw the class. In-season the prospect rows
        // are purged until the next offseason regenerates them — stamping over
        // an empty fetch would burn the one repair shot on nothing.
        if needsRepair, !prospects.isEmpty {
            CareerScopedDefaults.set(Self.prospectBandRepairVersion, Self.prospectBandRepairKey)
        }
    }
}

#Preview {
    CareerShellView(career: Career(
        playerName: "John Doe",
        role: .gm,
        capMode: .simple
    ))
    .modelContainer(for: Career.self, inMemory: true)
}
