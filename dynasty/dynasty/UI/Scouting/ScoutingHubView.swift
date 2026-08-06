import SwiftUI
import SwiftData

struct ScoutingHubView: View {
    @Bindable var career: Career
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTab: ScoutingTab = .board
    @State private var scouts: [Scout] = []
    @State private var prospects: [CollegeProspect] = []
    @State private var teamPlayers: [Player] = []
    /// The hub's single sheet slot. See ``HubSheet``.
    @State private var activeHubSheet: HubSheet?
    @State private var nextYearProspects: [ScoutingEngine.NextYearProspect] = []
    @State private var combineMedia: [ScoutingEngine.CombineMediaMention] = []
    @CareerScopedStorage(DraftPrepProgress.Key.scoutsSentToCombine)
    private var scoutsSentToCombine = false
    @CareerScopedStorage(DraftPrepProgress.Key.combineResultsReviewed)
    private var combineResultsReviewed = false
    /// Scouting budget already committed to this cycle's combine trip, in
    /// thousands. Reset by `WeekAdvancer` when the combine window opens.
    @CareerScopedStorage("combineTripSpend") private var combineTripSpend: Int = 0
    @State private var isLoading: Bool = true

    /// One position filter for the whole hub.
    ///
    /// Each prospect screen used to own a private copy: the Prospects tab drew
    /// visible chips, the Big Board hid its own set in a `.principal` toolbar
    /// item that the large navigation title suppressed, and the Combine table
    /// had a third as a segmented picker. Tapping "QB" therefore filtered
    /// whichever screen happened to own the control you could see, and the
    /// filter evaporated on every tab switch. Now the chips live here and the
    /// three tables read this binding.
    @State private var positionFilter: ProspectPositionFilter = .all

    /// Whether the active surface's Insights block is open (#130).
    ///
    /// Owned here rather than by `ScoutingInsightsSection` because two surfaces
    /// keep insight blocks of their own *inside* their lists — the combine's
    /// risers/fallers rails and the class-depth declaration header — and those
    /// have to fold with the same one tap. The section resolves the value from
    /// its per-surface defaults on appear; the hub only relays it downward.
    @State private var insightsExpanded: Bool = false

    /// The last stage screen the user stood on, so the switcher's stage segment
    /// keeps showing the room he was working in when he steps onto the board or
    /// into a reference surface. Reset by nothing: walking back is one tap.
    @State private var lastStageTab: ScoutingTab?

    /// The man a board row sent to the interview room (#125), ticked on arrival
    /// and cleared the moment the user leaves the room — otherwise walking back
    /// in a week later would re-tick a name he never asked for again.
    @State private var interviewFocusProspectID: UUID?

    /// Read only to migrate the legacy bookmark set onto the unified mark.
    @CareerScopedStorage("prospectWatchlist") private var hubProspectWatchlistJSON: String = "[]"

    private var hubLegacyWatchlistIDs: Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: Data(hubProspectWatchlistJSON.utf8))) ?? [])
    }

    private let maxScouts = 8

    /// Tabs the shared position chips apply to. The others are not
    /// position-filtered lists, and a chip row above them would be a control
    /// that does nothing.
    private var positionFilterAppliesToCurrentTab: Bool {
        switch selectedTab {
        // `.classDepth` is not a prospect TABLE, but it is a per-position read
        // and the chips narrow it to one group exactly as they narrow the board.
        case .board, .film, .combine, .classDepth: return true
        default:                                   return false
        }
    }

    // MARK: - Body
    //
    // PROCESS VIEW, re-stacked (#130). Four layers of pinned chrome over one
    // surface, in this order and no other:
    //
    //   1. the surface switcher   — Big Board · the stage surface · Tools.
    //                               ONE control, three slots, the active one
    //                               loud by size AND fill
    //   2. the process bar        — the pipeline. Full size on a stage surface,
    //                               a demoted counter strip everywhere else
    //   3. Insights               — the surface's title bar, and behind its
    //                               chevron everything that used to stack above
    //                               the list: the stage explainer, the
    //                               "N % scouted · phase" strip, the Draft Prep
    //                               card, the combine's risers/fallers, the
    //                               class-depth declaration header
    //   4. the position chips     — directly on top of the table, so the shared
    //                               filter reads as part of the list's own
    //                               controls rather than as a fourth nav row
    //
    //   … then the surface, whose own controls (mode chips, search, sortable
    //   column labels) live in ITS pinned list header, and finally the advance
    //   bar, which is a transition and not an insight and therefore never folds.
    //
    // What all of this replaced, verbatim from the user: *"This area is really
    // really unclear and confusing — when is Big Board selected, when Combine
    // etc."* The shipped build answered that question with a hue change on one
    // capsule inside the second of four near-identical chip rows, and put ~350 pt
    // of explanation above a list whose first row is the point of the screen.

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()

            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                        .tint(Color.accentGold)
                    Text("Loading Scouting...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
            VStack(spacing: 0) {
                processChrome

                Divider()
                    .overlay(Color.surfaceBorder)

                tabContent

                // The transition. It used to be a 12 pt greyed button inside the
                // Big Board's scroll-away header — the single most important
                // control on the screen, parked where a 350-row list scrolled it
                // out of existence. It is NOT an insight and never folds: a
                // requirement and the button that satisfies it are the work, and
                // the whole of #130 is about telling the work apart from the
                // commentary on it.
                if showsAdvanceBar {
                    advanceBar
                }
            }
            } // end else (not loading)
        }
        .navigationTitle("Scouting")
        .navigationBarTitleDisplayMode(.large)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if scouts.count < maxScouts {
                    Button { activeHubSheet = .hireScout } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .tint(Color.accentGold)
                    .accessibilityLabel("Hire scout")
                }
            }
        }
        .task {
            loadData()
            // ONE mark system: fold the legacy star / flag / bookmark opinions
            // into `userMarkTier` at the hub, so every tab below (and the
            // combine trip's `trackedProspectIDs`) reads a migrated board.
            let migrated = CollegeProspect.migrateLegacyMarks(
                in: prospects,
                watchlistIDs: hubLegacyWatchlistIDs
            )
            if migrated > 0 { try? modelContext.save() }
            // Honor a pending tab hint set by CareerShellView when the user
            // tapped a task that should land them on a specific tab
            // (e.g. "Review interview report" → Interviews tab).
            if let pending = CareerScopedDefaults.string("scoutingPendingTab"),
               !pending.isEmpty {
                // `bigBoard` / `prospects` are the two legacy hints: the tab
                // they named is one surface now, so both land on the board.
                let hinted: ScoutingTab? = {
                    switch pending {
                    // No longer phase-gated: an earlier stage is never shut, so
                    // a task that points at the interview room can always open
                    // it. Refusing the hint outside the combine is what made a
                    // REQUIRED task deep-link into nothing.
                    case "interviews": return .interviews
                    case "combine":    return .combine
                    case "bigBoard", "prospects", "board": return .board
                    case "film":       return .film
                    case "proDays":    return .proDays
                    case "workouts":   return .workouts
                    case "top30":      return .top30
                    case "mockDraft":  return .mockDraft
                    // #128. The January "Senior Bowl & declarations" task used to
                    // land on `.combine`, which in `.reviewRoster` is a screen
                    // reading "0 of 0 prospects invited" — the league has not
                    // issued an invite list yet, and cannot have. It lands here.
                    case "classDepth": return .classDepth
                    default:           return nil
                    }
                }()
                // Every tab is reachable now — the process bar draws the locked
                // ones with the sentence that opens them instead of deleting
                // them — so a hint is simply obeyed.
                if let hinted { selectedTab = hinted }
                CareerScopedDefaults.remove("scoutingPendingTab")
            } else {
                // BOARD FIRST, UNLESS THERE IS WORK (#130). The hub used to open
                // on `currentStageTab` unconditionally, which is right only when
                // that stage can actually be worked: `Career.prepStep` is a
                // floor and never reads lower than `.combineReview`, so in
                // November the "process view" landed every visit on a combine
                // screen reading "0 of 0 prospects invited" — and the user's own
                // board, the one surface that is always true, took two taps.
                //
                // Live work wins; otherwise the board.
                let progress = prepProgress
                let current = progress.current
                selectedTab = (progress[current].unlocked && !progress[current].isSatisfied)
                    ? currentStageTab
                    : .board
            }
            if Self.stageTabs.contains(selectedTab) { lastStageTab = selectedTab }
            isLoading = false
        }
        .onChange(of: selectedTab) { _, newTab in
            // The switcher's stage segment follows the room the user was last
            // in, so stepping onto the board and back is one tap each way.
            if Self.stageTabs.contains(newTab) { lastStageTab = newTab }
            // A board row's interview hand-off is spent the moment the room is
            // built; leaving clears it so a later visit opens on a clean slate.
            if newTab != .interviews { interviewFocusProspectID = nil }
            // The fold state belongs to the SURFACE, but the flag is one piece of
            // hub state shared across all of them (two screens fold their own
            // blocks with it). `ScoutingInsightsSection` resolves the new
            // surface's value in its `onAppear`, one frame after this body pass,
            // so leaving the outgoing surface's value in place flashed the
            // incoming block open — or shut — for that frame. Seeded from the
            // same two keys the section reads.
            insightsExpanded = ScoutingInsightsDefaults.resolvedExpansion(
                surfaceKey: newTab.rawValue,
                phaseToken: insightsPhaseToken
            )
            // Reviewing is opening the tab and finding numbers in it. It used to
            // additionally require that scouts had been sent, which made the
            // task uncompletable for a class the user chose to watch on
            // television — and permanently uncompletable when the combine had
            // never been run at all.
            if newTab == .combine && prospects.contains(where: { $0.fortyTime != nil }) {
                combineResultsReviewed = true
            }
            // Both mock stages complete by being READ — there is nothing to buy
            // and nothing to run — so opening the tab IS the act, and the act is
            // RECORDED before the stage moves.
            //
            // Recording it matters more than moving: `.ready` is calendar-gated,
            // so `advance` correctly refuses to unlock the draft room in March,
            // and without the stamp the last stage of the spring was a button
            // that visibly did nothing, forever. Both stamps are read by
            // `DraftPrepProgress` and by `Career.derivedPrepStepFloor`, so they
            // are also what heals a save whose stage string is stale.
            if newTab == .mockDraft {
                // Stamp whichever mock the club may ACT in, not only the one it
                // is standing in. A mock stage the process bar draws `.open` —
                // the common case, since `reach` opens the next room as soon as
                // the current stage is satisfied — would otherwise be a room the
                // user walks into and out of with nothing recorded, and the
                // cell would still read "Not read" after he read it.
                let progress = prepProgress
                if progress.canAct(.mockOne) { mockOneReadSeason = career.currentSeason }
                if progress.canAct(.mockTwo) { finalMockReadSeason = career.currentSeason }
                switch career.prepStep {
                case .mockOne: advance(to: .top30Visits)
                case .mockTwo: advance(to: .ready)
                default:       break
                }
            }
        }
        .onChange(of: career.prepStep) { oldStep, newStep in
            // Advancing carries the user forward with the process rather than
            // leaving him on the stage he just finished. He can walk back into
            // it — every done stage stays open — but the default after a
            // transition is the work that is now in front of him.
            //
            // Observe the ACCESSOR, not `draftPrepStep`: a new cycle resets the
            // pipeline with no hook at all — it is `currentSeason` moving past
            // `draftPrepStepSeason` (and the phase floor moving with it) — so
            // watching the raw column missed every silent reset. `Career` is
            // `@Model`, so reading `prepStep` here tracks all four inputs.
            //
            // Never from a reference surface. `.mockOne` and `.mockTwo` both
            // transition the instant the Mock Draft tab opens, and that tab is
            // also a permanent reference screen: bouncing the user off it would
            // mean the one act the stage asks for — reading the mock — is the
            // one thing he never gets to do.
            guard newStep != oldStep, !Self.referenceTabs.contains(selectedTab) else { return }
            if selectedTab == ScoutingTab.forStage(oldStep) {
                selectedTab = ScoutingTab.forStage(newStep)
            }
        }
        // ONE sheet modifier for the whole hub.
        //
        // These were two stacked `.sheet(isPresented:)` on the same view, and
        // SwiftUI honours only the last: `showHireScout` flipped, and what the
        // runtime presented was the COMBINE REPORT builder — with no mentions,
        // so an empty card. "Hire Scout" was a button that opened nothing. Same
        // defect, same shape, as the pro-day Reserve button (B1).
        .sheet(item: $activeHubSheet, onDismiss: { loadData() }) { sheet in
            switch sheet {
            case .hireScout:     HireScoutSheet(career: career)
            case .combineReport: CombineReportSheet(mentions: combineMedia)
            }
        }
    }

    /// The one sheet the hub can have open. An enum rather than two booleans, so
    /// "two sheets presented at once" is unrepresentable rather than silently
    /// resolved in favour of whichever modifier was written last.
    enum HubSheet: String, Identifiable {
        case hireScout
        case combineReport
        var id: String { rawValue }
    }

    // MARK: - Combine Trip Economics

    /// Cost in thousands of sending the department to Indianapolis this cycle.
    private var combineTripCost: Int {
        ScoutingEngine.combineTripCost(scoutCount: scouts.count)
    }

    /// What is left of the owner's scouting pot after scout salaries and any
    /// discretionary spend already committed this cycle.
    ///
    /// Per-prospect evaluations are part of that spend now — see
    /// `ScoutEvaluationBudget` — so the tile on the Draft Prep card and the
    /// price quoted on a prospect's evaluate button are the same money.
    private var remainingScoutingBudget: Int {
        fetchScoutingBudget()
            - scouts.reduce(0) { $0 + $1.salary }
            - combineTripSpend
            - evaluationSpend
    }

    // MARK: - Evaluation ledger (mirrors `ProspectDetailView`)

    @CareerScopedStorage("scoutEvaluationsUsed") private var evaluationsUsedStored: Int = 0
    @CareerScopedStorage("scoutEvaluationSpend") private var evaluationSpendStored: Int = 0
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

    private var canAffordCombineTrip: Bool {
        remainingScoutingBudget >= combineTripCost
    }

    /// Prospects this club's board actually tracks — starred, flagged, or given
    /// a user grade. Only these get a combine report filed on them; a department
    /// week in Indianapolis does not re-scout all 330 invitees.
    private func trackedProspectIDs() -> Set<UUID> {
        let board = UserProspectGradeStore.shared
        var ids = Set<UUID>()
        for prospect in prospects {
            // ONE mark system, plus the user's own draft grade — a man you
            // graded is a man you are tracking even if you have not tiered him.
            if prospect.isMarked || board.grade(for: prospect.id) != nil {
                ids.insert(prospect.id)
            }
        }
        // A brand-new board tracks nobody, and "you sent scouts and nothing
        // happened" is the worse failure. Fall back to the top of the consensus
        // board so the trip always buys something.
        if ids.isEmpty {
            let fallback = prospects
                .filter { $0.combineInvite }
                .sorted { ($0.draftProjection ?? 99) < ($1.draftProjection ?? 99) }
                .prefix(25)
            ids.formUnion(fallback.map(\.id))
        }
        return ids
    }

    /// Buys full-fidelity combine measurables plus fresh reports on the board.
    ///
    /// The combine itself is no longer this button's job — `WeekAdvancer`
    /// holds the event when the phase opens (and `loadData` heals a save that
    /// missed it). What attending changes is what the user is allowed to *read*:
    /// exact times instead of the broadcast's rounded ones, position drill
    /// grades with their modifier, percentiles, and a `.combine` scouting report
    /// on every prospect the board tracks.
    private func sendScoutsToCombine() {
        guard career.currentPhase == .combine, !scoutsSentToCombine else { return }
        guard canAffordCombineTrip else { return }

        var draftClass = WeekAdvancer.currentDraftClass

        // Compute average scouting ability from coaching staff
        let staffScoutingAbility: Int = {
            guard let teamID = career.teamID else { return 50 }
            let desc = FetchDescriptor<Coach>(predicate: #Predicate { $0.teamID == teamID })
            let coaches = (try? modelContext.fetch(desc)) ?? []
            guard !coaches.isEmpty else { return 50 }
            let total = coaches.reduce(0) { $0 + $1.scoutingAbility }
            return total / coaches.count
        }()

        // Belt and braces: the phase hook has normally already run the event,
        // but a save that entered `.combine` before this shipped has not.
        ScoutingEngine.runLeagueCombine(prospects: &draftClass, scoutingAbility: staffScoutingAbility)

        _ = ScoutingEngine.applyCombineScouting(
            prospects: &draftClass,
            trackedIDs: trackedProspectIDs(),
            scouts: scouts
        )

        combineMedia = ScoutingEngine.combineMediaDigest(prospects: draftClass)
        WeekAdvancer.currentDraftClass = draftClass
        // Ensure prospects are tracked + flush combine results to SwiftData so
        // they survive an app restart (#data-flow-bug).
        WeekAdvancer.persistDraftClass(WeekAdvancer.currentDraftClass, to: modelContext)

        combineTripSpend += combineTripCost
        scoutsSentToCombine = true
        loadData()
        activeHubSheet = .combineReport
    }

    // MARK: - Stage machine + hub header data

    /// Prospects your building has actually filed on.
    ///
    /// Counted off filed reports rather than `scoutedOverall` so this header and
    /// the Draft Prep card underneath it mean the same thing by "scouted" — and
    /// off `ProspectFog.hasOwnReport` rather than `!scoutingReports.isEmpty`,
    /// because the second test counts the inherited "Previous Staff" baseline
    /// `ScoutingEngine.applyPreScoutedData` hands the top ~250 of every class.
    /// A brand new save therefore opened this header at ~88 % of the class
    /// "scouted" before the user had hired a scout, which is the exact opposite
    /// of what a coverage number is for.
    private var scoutedCount: Int {
        prospects.filter(ProspectFog.hasOwnReport).count
    }

    /// Filed reports and their share of the class, walked ONCE per chrome pass.
    ///
    /// Three call sites want this number now — the board segment's subtitle, the
    /// Insights teaser and the coverage strip inside the Insights body — and
    /// `scoutingReports` is a SwiftData `Codable` array, i.e. a decode per
    /// prospect per read. Three walks of a ~350-man class on every `@State`
    /// touch of a screen that owns a 350-row table is not a rounding error.
    private struct CoverageReadout {
        let filed: Int
        let percent: Int
    }

    private func coverageReadout() -> CoverageReadout {
        let filed = scoutedCount
        guard !prospects.isEmpty else { return CoverageReadout(filed: filed, percent: 0) }
        return CoverageReadout(
            filed: filed,
            percent: Int((Double(filed) / Double(prospects.count) * 100).rounded())
        )
    }

    private var phaseLabel: String {
        switch career.currentPhase {
        case .proBowl:          return "Pro Bowl"
        case .superBowl:        return "Super Bowl"
        case .coachingChanges:  return "Coaching Changes"
        case .reviewRoster:     return "Review Roster"
        case .combine:          return "NFL Combine"
        case .freeAgency:       return "Free Agency"
        case .proDays:          return "Pro Days & Workouts"
        case .draft:            return "NFL Draft"
        case .otas:             return "OTAs"
        case .trainingCamp:     return "Training Camp"
        case .preseason:        return "Preseason"
        case .rosterCuts:       return "Roster Cuts"
        case .regularSeason:    return "Regular Season"
        case .tradeDeadline:    return "Trade Deadline"
        case .playoffs:         return "Playoffs"
        }
    }

    private var stageGate: ScoutingStageGate {
        ScoutingStageGate.make(progress: prepProgress, career: career)
    }

    // MARK: - Final-mock read stamp
    //
    // `.mockTwo` is the one stage whose forward transition the CALENDAR owns:
    // `.ready` belongs to `.draft`, and the Final Mock itself is printed with
    // the draft order. Reading it is still an act, and without a record of it
    // the last stage of the spring was a button that did nothing visible, with
    // no chip, until the draft boundary silently cleared the stage. Same
    // cycle-stamp trick as the evaluation ledger — a stamp from an earlier
    // draft cycle reads as unread.

    @CareerScopedStorage(DraftPrepProgress.Key.mockOneRead)
    private var mockOneReadSeason: Int = 0

    @CareerScopedStorage(DraftPrepProgress.Key.mockTwoRead)
    private var finalMockReadSeason: Int = 0

    /// The coverage strip and the Draft Prep card.
    ///
    /// It used to be handed by closure into whichever surface owned the scroll,
    /// as that list's first section. #130 moved it into the hub's Insights block:
    /// both halves are *orientation*, read once a phase, and folding them behind
    /// the same chevron as the stage explainer is what lets a surface open on its
    /// own content. The list surfaces now receive `EmptyView`.
    private func hubHeader(scoutedPercent: Int) -> ScoutingHubHeader {
        ScoutingHubHeader(
            career: career,
            prospects: prospects,
            teamRoster: teamPlayers,
            scouts: scouts,
            scoutsSentToCombine: scoutsSentToCombine,
            scoutingBudgetRemaining: remainingScoutingBudget,
            evaluationsUsed: evaluationsUsed,
            scoutedPercent: scoutedPercent,
            phaseLabel: phaseLabel,
            onSelectTab: { selectedTab = $0 },
            onFilterPosition: { positionFilter = $0 }
        )
    }

    /// Writes the next step.
    ///
    /// Capped by the calendar: the stage machine may run ahead of the user's
    /// work (that is what a skip is) but never ahead of the season, or a club
    /// still in combine week would unlock the pro-day tour. `advancePrepStep`
    /// itself never lowers a step and re-stamps the cycle.
    private func advance(to step: DraftPrepStep) {
        // The cap is a CALENDAR comparison, so it has to use the calendar's
        // order. `SeasonPhase.allCases` is declaration order — `regularSeason`
        // sorts above `draft` in it — which made every stage skippable from
        // November. `prepCalendarRank` ranks only the four pre-draft phases and
        // puts everything else below the first stage.
        guard step.phase.prepCalendarRank <= career.currentPhase.prepCalendarRank else { return }
        career.advancePrepStep(to: step)
        try? modelContext.save()
    }

    // MARK: - Process view: stage cells, selection, transition

    /// The six surfaces that are not part of the pipeline. Always open, always
    /// in the same place, never mixed into the calendar strip.
    ///
    /// `.classDepth` sits directly behind the board because it is the same class
    /// read one level up: the board is 350 rows of men, the depth screen is the
    /// nine sentences those rows add up to. It is the January landing surface for
    /// the declaration / Senior Bowl task (#128), and — like every reference tab
    /// — it is open all year.
    private static let referenceTabs: [ScoutingTab] =
        [.board, .classDepth, .mockDraft, .draftOrder, .scouts, .nextYear]

    /// The reference surfaces the switcher parks behind the **Tools** menu —
    /// `referenceTabs` minus the board, which is a segment of its own (#130).
    ///
    /// The board is not one lookup among six. It is the club's own list, the one
    /// screen the user returns to between every instrument, and giving it a
    /// quarter of a scrolling capsule row next to "Next Yr" is what made the
    /// whole strip read as undifferentiated.
    private static let toolTabs: [ScoutingTab] =
        [.classDepth, .mockDraft, .draftOrder, .scouts, .nextYear]

    /// The tabs that are a pipeline stage's own screen.
    ///
    /// `.mockDraft` is in here as well as in `toolTabs`, and both are correct: it
    /// is a permanent reference screen AND the room stages 6 and 9 are worked in.
    /// The switcher resolves the overlap in favour of the stage segment, which is
    /// the reading that carries more information (a stage number and a state).
    private static let stageTabs: Set<ScoutingTab> =
        [.combine, .interviews, .film, .proDays, .workouts, .top30, .mockDraft]

    /// The tab whose screen belongs to the stage the club is standing in.
    ///
    /// Not `selectedTab.stage`: the two mock stages route to `.mockDraft`, which
    /// is deliberately NOT stage-gated (four mocks print across the year and all
    /// of them are public the moment they publish), so it carries no `stage` of
    /// its own and the reverse lookup has to come from the step.
    private var currentStageTab: ScoutingTab { ScoutingTab.forStage(career.prepStep) }

    /// The stage the selected tab is showing, or `nil` on a reference surface.
    private var selectedStage: DraftPrepStep? {
        // `.mockDraft` is a reference surface AND the screen for two stages. It
        // reads as a stage only while the club is standing in one of them.
        if selectedTab == .mockDraft {
            return [.mockOne, .mockTwo].contains(career.prepStep) ? career.prepStep : nil
        }
        return selectedTab.stage
    }

    // MARK: - Surface switcher wiring (#130)

    /// Whether the screen showing is a stage's own working surface.
    ///
    /// Drives the process bar's size: the pipeline is the SUBJECT here, so it
    /// gets its full cells. Everywhere else it is context and demotes.
    private var isOnStageSurface: Bool { Self.stageTabs.contains(selectedTab) }

    /// The tab the switcher's stage segment offers.
    ///
    /// The room the user is standing in, else the last room he was in, else the
    /// club's current stage. `.ready` routes to the board — which is already the
    /// first segment — so at the end of the pipeline the segment offers the final
    /// mock, the last thing the spring has to say.
    private var stageSegmentTab: ScoutingTab {
        if Self.stageTabs.contains(selectedTab) { return selectedTab }
        if let lastStageTab, Self.stageTabs.contains(lastStageTab) { return lastStageTab }
        let current = currentStageTab
        return current == .board ? .mockDraft : current
    }

    /// The stage the segment above is showing, for its number and its state.
    private var stageSegmentStep: DraftPrepStep {
        let tab = stageSegmentTab
        if let step = tab.stage { return step }
        // `.mockDraft` carries no `stage` of its own (four mocks print a year and
        // all of them are public), so the step comes off where the club stands.
        return [.mockOne, .mockTwo].contains(career.prepStep) ? career.prepStep : .mockOne
    }

    private var activeSurfaceSlot: ScoutingSurfaceSwitcher.Slot {
        if selectedTab == .board { return .board }
        if selectedTab == stageSegmentTab { return .stage }
        return .tools
    }

    /// "<season>-<phase>" — the token that re-arms one free Insights expansion.
    private var insightsPhaseToken: String {
        "\(career.currentSeason)-\(career.currentPhase.rawValue)"
    }

    // MARK: - Progress
    //
    // ONE authority. `DraftPrepProgress` owns every counter, every
    // "is this stage satisfied", and every lock sentence, and it is the same
    // struct the required-task chain reads — which is the whole point: the
    // shipped build had the hub's `ScoutingStageGate` holding one copy of those
    // predicates and `CareerShellView` holding another, keyed off different
    // state, and that split is what left "Send Scouts to Combine — Required"
    // burning red next to a department standing in Indianapolis.
    //
    // Built once per body pass rather than per call site: it walks a ~350-man
    // class to prove the combine was held, and this screen re-evaluates on every
    // `@State` touch.

    private var prepProgress: DraftPrepProgress {
        DraftPrepProgress(career: career, prospects: prospects, scouts: scouts)
    }

    /// How the process bar draws a stage.
    ///
    /// Keyed off what the club has DONE, never off where the pipeline pointer
    /// happens to sit. It used to be `step.order < current.order → .done`, and
    /// because `Career.prepStep` is a *floor* — it can be raised by the phase or
    /// by an unrelated ledger — that drew green checkmarks on stages whose own
    /// counter read "Not read" and whose required task was still red in the left
    /// bar. A tick is a claim about work; only `isSatisfied` may make it.
    private func stageState(
        _ step: DraftPrepStep,
        progress: DraftPrepProgress
    ) -> DraftPrepStageCell.State {
        // LOCKED WINS OVER CURRENT (#107). `prepStep` is a floor and it never
        // reads lower than `.combineReview`, so outside the pre-draft window
        // stage 1 is still "where the club stands" — and the bar drew it in
        // February with the gold puck and the "Not read" chip while the Combine
        // tab underneath read "0 of 0 prospects invited". Standing in a stage
        // and being able to work it are different claims; `unlocked` owns the
        // second one, and only the second one may be drawn as an invitation.
        //
        // Presentation only: `canAct` is untouched, and an EARLIER stage is
        // still never shut, so the B3 class stays closed.
        if step == progress.current {
            // A satisfied stage keeps its tick even when the calendar has shut
            // it — done work is a fact, not an invitation, and the lock glyph
            // over a finished stage reads as data loss.
            if !progress[step].unlocked && progress[step].isSatisfied { return .done }
            return progress[step].unlocked ? .current : .locked
        }
        if progress[step].isSatisfied { return .done }
        // Everything the club may work right now — the stages behind it, which
        // never shut, and the next room, which `reach` opens the moment the
        // current stage is satisfied. `.open` is a promise that the screen
        // underneath has live buttons, and `DraftPrepProgress.canAct` is the
        // same predicate those buttons read.
        return progress[step].unlocked ? .open : .locked
    }

    // MARK: - Process chrome
    //
    // Built as one function rather than inline in `body` so `DraftPrepProgress`
    // is constructed ONCE per pass — it walks the draft class, and this screen
    // re-evaluates on every `@State` touch.

    private var processChrome: some View {
        let progress = prepProgress
        let stage = selectedStage
        let segmentStep = stageSegmentStep
        let coverage = coverageReadout()
        return VStack(spacing: 0) {
            // Layer 1: WHERE AM I. One control, three slots, and the answer is
            // legible from across the room.
            ScoutingSurfaceSwitcher(
                boardSubtitle: boardSegmentSubtitle(coverage),
                stageTab: stageSegmentTab,
                stageSubtitle: stageSegmentSubtitle(step: segmentStep, progress: progress),
                stageState: stageState(segmentStep, progress: progress),
                stageIsWaiting: progress[segmentStep].isCalendarLocked,
                toolTabs: Self.toolTabs,
                selected: selectedTab,
                active: activeSurfaceSlot,
                onSelect: { selectedTab = $0 }
            )
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 8)

            // Layer 2: the pipeline. Every stage in calendar order, each carrying
            // its state and its own count of work, none ever hidden — but sized
            // for whether it is the subject of the screen or its context.
            DraftPrepProcessBar(
                cells: DraftPrepStep.allCases
                    .sorted { $0.order < $1.order }
                    .map { step in
                        DraftPrepStageCell(
                            step: step,
                            state: stageState(step, progress: progress),
                            stage: progress[step]
                        )
                    },
                selected: stage,
                isCompact: !isOnStageSurface,
                onSelect: { selectStage($0) }
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            // Layer 3: the surface's title, and behind one chevron everything
            // that used to be stacked above the list unasked.
            ScoutingInsightsSection(
                surfaceKey: selectedTab.rawValue,
                phaseToken: insightsPhaseToken,
                title: selectedTab.label,
                icon: selectedTab.icon,
                stateChip: insightsStateChip(progress: progress),
                stateChipTint: insightsStateChipTint(progress: progress),
                teaser: insightsTeaser(progress: progress, stage: stage, coverage: coverage),
                isExpanded: $insightsExpanded
            ) {
                insightsBody(progress: progress, stage: stage, coverage: coverage)
            }
            // A fresh instance per surface: `ScoutingInsightsSection` binds its
            // two `@AppStorage` keys at init, so without this the board's flags
            // would follow the user onto the combine.
            .id(selectedTab.rawValue)
            .padding(.horizontal, 12)
            .padding(.bottom, positionFilterAppliesToCurrentTab ? 6 : 8)

            // Layer 4: the shared filter, LAST, so it sits on the table rather
            // than between two blocks of prose. The table's own controls (mode
            // chips, search, sortable column labels) are pinned inside its list
            // header directly underneath, and the two read as one strip.
            if positionFilterAppliesToCurrentTab {
                positionFilterChips
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - Insights composition (#130)

    /// The stage segment's second line — where it sits in the pipeline and how
    /// much of it is done. The counter is `DraftPrepProgress`'s own string, so
    /// the segment, the process-bar cell and the required task in the left bar
    /// can never print three different numbers for one stage.
    private func stageSegmentSubtitle(step: DraftPrepStep, progress: DraftPrepProgress) -> String {
        let total = DraftPrepStep.allCases.count
        return "Stage \(step.order + 1) of \(total) \u{00B7} \(progress[step].counter)"
    }

    /// The board segment's second line — the size of the pool it holds.
    private func boardSegmentSubtitle(_ coverage: CoverageReadout) -> String {
        prospects.isEmpty
            ? "No class on the board yet"
            : "\(prospects.count) declared \u{00B7} \(coverage.percent)% scouted"
    }

    /// "STAGE 4 · CURRENT" over a stage surface, nothing over a reference one.
    private func insightsStateChip(progress: DraftPrepProgress) -> String? {
        guard let stage = selectedStage else { return nil }
        let word: String = {
            switch stageState(stage, progress: progress) {
            case .current: return "CURRENT"
            case .done:    return "DONE"
            case .open:    return "OPEN"
            case .locked:  return progress[stage].isCalendarLocked ? "WAITING" : "LOCKED"
            }
        }()
        return "STAGE \(stage.order + 1) \u{00B7} \(word)"
    }

    private func insightsStateChipTint(progress: DraftPrepProgress) -> Color {
        guard let stage = selectedStage else { return .accentGold }
        switch stageState(stage, progress: progress) {
        case .current: return .accentGold
        case .done:    return .success
        case .open:    return .accentBlue
        case .locked:  return .textTertiaryReadable
        }
    }

    /// The one line that has to survive the collapse.
    ///
    /// Whatever is most volatile about THIS surface first, then the two facts
    /// the old pinned metrics strip carried. Capped at four clauses: a teaser
    /// that wraps is a paragraph, and a paragraph is what we just folded away.
    private func insightsTeaser(
        progress: DraftPrepProgress,
        stage: DraftPrepStep?,
        coverage: CoverageReadout
    ) -> String {
        var parts: [String] = []
        switch selectedTab {
        case .combine:
            // The fidelity line used to be a chip inside the combine's own
            // header; it explains why a column reads "~4.5" instead of "4.53",
            // so it may not disappear behind a chevron.
            parts.append(scoutsSentToCombine ? "Scouts on site" : "Broadcast numbers")
            let movers = CombineMovers.counts(in: prospects)
            if movers.risers > 0 { parts.append("\(movers.risers) risers") }
            if movers.fallers > 0 { parts.append("\(movers.fallers) fallers") }
        case .classDepth:
            parts.append("\(prospects.count) declared")
        case .board:
            parts.append("\(coverage.filed) of \(prospects.count) filed on")
        default:
            break
        }
        // The stage counter stands down on the combine surface, which is the one
        // that can contribute three clauses of its own: with risers AND fallers
        // present the list ran fidelity · risers · fallers · counter · scouted% ·
        // phase, and `prefix(4)` then dropped the two facts this teaser exists to
        // keep. The counter is also the one clause the user can read elsewhere
        // without expanding anything — the stage segment's own subtitle prints
        // it, from the same `DraftPrepProgress`.
        if let stage, selectedTab != .combine { parts.append(progress[stage].counter) }
        parts.append("\(coverage.percent)% scouted")
        parts.append(phaseLabel)
        return parts.prefix(4).joined(separator: " \u{00B7} ")
    }

    /// Everything the hub itself folds away: what this stage buys and what it
    /// costs, the coverage strip, and the Draft Prep card.
    ///
    /// The two surface-specific blocks — the combine's risers/fallers rails and
    /// the class-depth declaration header — stay inside their own screens and
    /// fold on `insightsExpanded`, because both are computed from state those
    /// screens already hold and hoisting them would mean walking a 350-man class
    /// twice per body pass.
    @ViewBuilder
    private func insightsBody(
        progress: DraftPrepProgress,
        stage: DraftPrepStep?,
        coverage: CoverageReadout
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let stage {
                let row = progress[stage]
                DraftPrepStageExplainer(
                    step: stage,
                    state: stageState(stage, progress: progress),
                    counterText: row.counter,
                    lockReason: row.lockReason ?? "",
                    // The gate's requirement is a TARGET — "Open the Combine tab
                    // and read the numbers" — so it may only be printed over a
                    // stage that can actually be worked. A shut stage gets its
                    // lock sentence instead (#107).
                    requirement: (stage == progress.current && row.unlocked)
                        ? stageGate.requirement
                        : "",
                    isWaitingOnCalendar: row.isCalendarLocked
                )
            }
            hubHeader(scoutedPercent: coverage.percent)
        }
    }

    /// Selecting a stage cell selects that stage's screen.
    ///
    /// A locked stage is selectable on purpose. The shipped wizard *hid* every
    /// unreached stage, which is how "pro days completely unavailable" and "film
    /// study could not be assigned to anyone" both happened to the same user in
    /// the same hour: the screens were not broken, they had been deleted from
    /// under him with no trace and no explanation. Now they open, say what they
    /// are, and say what opens them.
    private func selectStage(_ step: DraftPrepStep) {
        selectedTab = ScoutingTab.forStage(step)
    }

    /// Whether the hub draws the transition itself.
    ///
    /// Only for the stages the HUB owns the transition for. A `.open` stage's
    /// screen owns its own advance — and it has to, because for the pro-day tour
    /// the transition IS the batch action that spends the focus-slot
    /// reservations. Two advance buttons over one destructive transition is how
    /// a stray tap threw those reservations away in the shipped build.
    private var showsAdvanceBar: Bool {
        guard selectedTab == currentStageTab else { return false }
        // Outside the pre-draft window there is nothing to advance INTO — a
        // disabled "Advance — Interviews" over a waiting screen reads as a
        // broken button, which is #107 verbatim. The stage cells and the
        // explainer already carry the "opens at the combine" message. The
        // phase rank IS the calendar lock for the current stage (a current
        // stage inside the window is always calendar-open), and testing it
        // here avoids building a second full DraftPrepProgress per body pass.
        guard career.currentPhase.prepCalendarRank > 0 else { return false }
        if case .advance = stageGate.action { return true }
        return false
    }

    /// The pinned transition for the stage the club is standing in.
    private var advanceBar: some View {
        let gate = stageGate
        return DraftPrepAdvanceBar(
            stepName: gate.step.displayName,
            nextName: gate.next?.displayName,
            requirement: gate.requirement,
            skipCost: gate.skipCost,
            isComplete: gate.isComplete,
            isBlocked: gate.isPhaseBlocked,
            blockedReason: gate.phaseBlockedReason,
            ownsTransition: true,
            onAdvance: { if let next = gate.next { advance(to: next) } },
            onSkip: { if let next = gate.next { advance(to: next) } },
            onOpen: { if case let .open(tab, _) = gate.action { selectedTab = tab } }
        )
    }

    // MARK: - Position Filter Chips (shared by Big Board / Prospects / Combine)

    private var positionFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(ProspectPositionFilter.allCases) { filter in
                    let isSelected = positionFilter == filter
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            positionFilter = filter
                        }
                    } label: {
                        Text(filter.label)
                            .font(.system(size: 12, weight: isSelected ? .heavy : .medium))
                            .foregroundStyle(isSelected ? Color.backgroundPrimary : Color.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                isSelected ? Color.accentBlue : Color.backgroundTertiary,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isSelected ? Color.clear : Color.surfaceBorder,
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(filter == .all
                                        ? "Show all positions"
                                        : "Filter to \(filter.label)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .mask(
            HStack(spacing: 0) {
                Color.white
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 20)
            }
        )
    }

    // MARK: - Tab Content

    /// The board's route into the interview room, or `nil` when there is no
    /// honest one (#125).
    ///
    /// The gate is the hub's, not the board's: `canAct` is the same predicate
    /// the room's own Conduct button reads, and the stage counter IS the 60-slot
    /// ration (`done`/`total` for `.interviews`). A board row therefore never
    /// offers a meeting the room would refuse, and nothing about the interview
    /// economy has to be restated on the board.
    private func interviewJump(_ progress: DraftPrepProgress) -> ((CollegeProspect) -> Void)? {
        let stage = progress[.interviews]
        guard stage.unlocked, stage.done < stage.total else { return nil }
        return { prospect in
            interviewFocusProspectID = prospect.id
            selectedTab = .interviews
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        // ONE progress value for the whole surface. Every stage screen's
        // "may I act" is `DraftPrepProgress.canAct`, the same predicate the
        // process bar draws its `.open` puck from — so a cell that invites a tap
        // can never land on a screen whose buttons are dead.
        let progress = prepProgress
        switch selectedTab {
        case .scouts:
            ScoutTeamView(
                scouts: scouts,
                canHire: scouts.count < maxScouts,
                career: career,
                scoutsSentToCombine: scoutsSentToCombine,
                prospects: prospects,
                scoutingBudget: fetchScoutingBudget(),
                combineTripSpend: combineTripSpend,
                evaluationSpend: evaluationSpend,
                canSendToCombine: career.currentPhase == .combine,
                onHire: { activeHubSheet = .hireScout },
                onFire: { fireScout($0) },
                onSendToCombine: { sendScoutsToCombine() }
            )
        case .board:
            BigBoardView(
                career: career,
                prospects: prospects,
                teamRoster: teamPlayers,
                scoutsSentToCombine: scoutsSentToCombine,
                // Empty-state CTAs need a way back into the hub's other tabs.
                onSwitchTab: { selectedTab = $0 },
                onInterview: interviewJump(progress),
                scoutCount: scouts.count,
                positionFilter: $positionFilter,
                // #130: the metrics strip and the prep card moved into the hub's
                // Insights block. The board's first row is a prospect again.
                header: { EmptyView() }
            )
        case .film:
            // The film-study stage screen is the BATCH ORDER surface (#119):
            // pick the men, read what the order costs, run it once, read the
            // report — the same shape the interview room has always had.
            //
            // It used to be the board alone, opened on the work-up columns with
            // a priced button welded onto every row. That is the right economy
            // in the wrong shape: ordering tape on fifteen men was fifteen taps
            // on fifteen rows of a 350-row table, each silently spending a slot
            // and a fee, with no running total and no report at the end.
            //
            // The board is NOT deleted — `DraftPrepStep.filmStudy.actionLabel`
            // promises ordering "on your board", and the work-up columns are the
            // read that says which men still need tape — it is the tab's second
            // surface, one tap away behind the header's Order / Board picker.
            FilmStudySelectionView(
                career: career,
                positionFilter: $positionFilter,
                // The ONE gate every stage screen asks, of the same struct the
                // process bar draws its `.open` puck from. Shut only while the
                // stage is LOCKED: `career.prepStep != .filmStudy` was the
                // shipped test and it is B3 exactly — the step is a floor, so a
                // save that reached the pro days had the film screen bolted shut
                // for the rest of the spring with a REQUIRED task pointing at it.
                canAct: progress.canAct(.filmStudy)
            ) {
                BigBoardView(
                    career: career,
                    prospects: prospects,
                    teamRoster: teamPlayers,
                    scoutsSentToCombine: scoutsSentToCombine,
                    onSwitchTab: { selectedTab = $0 },
                    onInterview: interviewJump(progress),
                    scoutCount: scouts.count,
                    positionFilter: $positionFilter,
                    initialAttributeTab: .workup,
                    isFilmStudy: true,
                    isStageClosed: !progress.canAct(.filmStudy),
                    header: { EmptyView() }
                )
            }
        case .combine:
            CombineResultsView(
                career: career,
                prospects: prospects,
                scoutsAttended: scoutsSentToCombine,
                tripCost: combineTripCost,
                // The trip is a one-phase window: offered inside `.combine`,
                // gone afterwards. The results themselves stay readable through
                // the draft either way.
                onSendScouts: (career.currentPhase == .combine && !scoutsSentToCombine)
                    ? { sendScoutsToCombine() }
                    : nil,
                canAffordTrip: canAffordCombineTrip,
                // #128 case D: before the league issues its invite list there is
                // literally nothing on this tab, and the class-depth read is what
                // a January user came for.
                onOpenClassDepth: { selectedTab = .classDepth },
                positionFilter: $positionFilter,
                // #130: the title block, the fidelity chip and the RISERS /
                // FALLERS rails belong to the hub's Insights block now and fold
                // with it. The send-scouts CTA never folds — it is a one-window
                // offer with money attached, not an insight.
                insightsExpanded: insightsExpanded,
                header: { EmptyView() }
            )
        case .interviews:
            InterviewSelectionView(
                career: career,
                canAct: progress.canAct(.interviews),
                focusProspectID: interviewFocusProspectID
            )
        case .mockDraft:
            MockDraftView(career: career, prospects: prospects)
        case .draftOrder:
            DraftOrderView(career: career)
        case .workouts:
            WorkoutsTabView(
                career: career,
                prospects: prospects,
                teamRoster: teamPlayers,
                positionFilter: $positionFilter,
                canAct: progress.canAct(.workouts),
                onRefresh: loadData
            )
        case .top30:
            Top30VisitsView(
                career: career,
                scouts: scouts,
                prospects: prospects,
                teamRoster: teamPlayers,
                canAct: progress.canAct(.top30Visits),
                onRefresh: loadData
            )
        case .proDays:
            // Wave B split `ProDayListView` into three stage screens. This case
            // routes the existing tab at the tour; the `.workouts` and `.top30`
            // tabs that carry `WorkoutsTabView` / `Top30VisitsView` are Wave A's
            // `ScoutingTab` rewrite.
            ProDayTourView(
                career: career,
                scouts: scouts,
                prospects: prospects,
                teamRoster: teamPlayers,
                canAct: progress.canAct(.proDayFocus),
                onRefresh: loadData
            )
        case .classDepth:
            // #128. `prospects` is already the DECLARED class (`loadData` filters
            // on `isDeclaringForDraft`), which is the whole point of the screen
            // after the January window — it re-filters anyway, so it stays honest
            // if it is ever hosted somewhere that does not.
            ClassDepthView(
                career: career,
                prospects: prospects,
                teamRoster: teamPlayers,
                positionFilter: $positionFilter,
                // #130: the declaration header is this surface's insight block
                // and folds with the hub's chevron.
                insightsExpanded: insightsExpanded,
                // A depth read is a scan. Tapping a group hands the user the
                // board with the shared chip already set to that group.
                onOpenBoard: { selectedTab = .board }
            )
        case .nextYear:
            NextYearClassPreview(career: career, prospects: nextYearProspects)
        }
    }

    // MARK: - Data

    private func loadData() {
        guard let teamID = career.teamID else { return }

        let scoutDesc = FetchDescriptor<Scout>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        scouts = (try? modelContext.fetch(scoutDesc)) ?? []

        // Plan §5: an in-flight save can be sitting on a pre-overhaul draft class.
        // Swap it out before anything reads the board (no-op once the draft ran).
        WeekAdvancer.migrateLegacyDraftClassIfNeeded(career: career, modelContext: modelContext)

        // Restore draft class on app restart: prefer SwiftData, then re-generate.
        if WeekAdvancer.currentDraftClass.isEmpty {
            let cid = career.id
            let prospectFetch = FetchDescriptor<CollegeProspect>(
                predicate: #Predicate { $0.careerID == cid }
            )
            let persisted = (try? modelContext.fetch(prospectFetch)) ?? []
            if !persisted.isEmpty {
                WeekAdvancer.currentDraftClass = persisted
                WeekAdvancer.draftClassGenerated = true
            } else {
                let validPhases: [SeasonPhase] = [.coachingChanges, .reviewRoster, .combine, .freeAgency, .proDays, .draft, .otas]
                if validPhases.contains(career.currentPhase) {
                    WeekAdvancer.currentDraftClass = ScoutingEngine.generateDraftClass()
                    WeekAdvancer.draftClassGenerated = true
                    // Apply pre-scouted data for first season
                    ScoutingEngine.applyPreScoutedData(prospects: &WeekAdvancer.currentDraftClass)
                    WeekAdvancer.persistDraftClass(WeekAdvancer.currentDraftClass, to: modelContext)
                }
            }
        }

        // Self-heal for saves that reached (or passed) the combine before the
        // phase hook existed: the event is held now so the Combine tab has
        // something in it. No-op once the class carries results.
        WeekAdvancer.ensureCombineRun(career: career, modelContext: modelContext)

        // Prospects live in WeekAdvancer.currentDraftClass (not persisted in SwiftData)
        let allProspects = WeekAdvancer.currentDraftClass
        prospects = allProspects.filter { $0.isDeclaringForDraft }

        let playerDesc = FetchDescriptor<Player>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        teamPlayers = (try? modelContext.fetch(playerDesc)) ?? []

        // Rebuilt from what is stamped on the prospects, so the combine report
        // sheet still opens after a relaunch or when the phase — rather than the
        // button — held the event.
        combineMedia = ScoutingEngine.combineMediaDigest(prospects: allProspects)

        if nextYearProspects.isEmpty {
            nextYearProspects = ScoutingEngine.generateNextYearPreview()
        }
    }

    /// R27: scouts draw from the owner's dedicated scouting budget.
    private func fetchScoutingBudget() -> Int {
        guard let teamID = career.teamID else { return 4_000 }
        let desc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        return (try? modelContext.fetch(desc))?.first?.owner?.scoutingBudget ?? 4_000
    }

    private func fireScout(_ scout: Scout) {
        modelContext.delete(scout)
        try? modelContext.save()
        loadData()
    }
}

// MARK: - Combine Report Sheet (#259)

private struct CombineReportSheet: View {
    let mentions: [ScoutingEngine.CombineMediaMention]
    @Environment(\.dismiss) private var dismiss

    private let categories = ["Standout", "Stock Riser", "Stock Faller", "Surprise"]

    private func mentionsFor(_ category: String) -> [ScoutingEngine.CombineMediaMention] {
        mentions.filter { $0.category == category }
    }

    private func categoryIcon(_ category: String) -> String {
        switch category {
        case "Standout":     return "star.fill"
        case "Stock Riser":  return "arrow.up.right.circle.fill"
        case "Stock Faller": return "arrow.down.right.circle.fill"
        case "Surprise":     return "exclamationmark.triangle.fill"
        default:             return "newspaper"
        }
    }

    private func categoryColor(_ category: String) -> Color {
        switch category {
        case "Standout":     return .accentGold
        case "Stock Riser":  return .success
        case "Stock Faller": return .danger
        case "Surprise":     return .accentBlue
        default:             return .textSecondary
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.backgroundPrimary.ignoresSafeArea()

                List {
                    // Header
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "newspaper.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.accentGold)
                            Text("NFL COMBINE REPORT")
                                .font(.title2.weight(.black))
                                .foregroundStyle(Color.textPrimary)
                            Text("\(mentions.count) notable performances")
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(Color.backgroundSecondary)

                    ForEach(categories, id: \.self) { category in
                        let items = mentionsFor(category)
                        if !items.isEmpty {
                            Section {
                                ForEach(items, id: \.prospectID) { mention in
                                    HStack(spacing: 12) {
                                        Text(mention.position)
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.textPrimary)
                                            .frame(width: 32, height: 22)
                                            .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(mention.prospectName)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(Color.textPrimary)
                                            Text(mention.headline)
                                                .font(.caption)
                                                .foregroundStyle(Color.textSecondary)
                                                .lineLimit(2)
                                        }
                                    }
                                }
                            } header: {
                                Label(category, systemImage: categoryIcon(category))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(categoryColor(category))
                                    .textCase(nil)
                            }
                            .listRowBackground(Color.backgroundSecondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Combine Report")
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

// MARK: - Tab Enum

/// The hub's tabs, in pipeline order.
///
/// `prospects` is gone: it rendered the same `[CollegeProspect]` as the board,
/// with the same attribute picker, and the board is the richer surface. Three
/// tabs arrived with the stage machine — `film`, `workouts`, `top30` — because
/// three instruments used to share one screen or live two taps inside a
/// prospect card.
///
/// Order here is the order the picker draws, and it is the order of the
/// pipeline: the spine first (board), then the stages, then the reference tabs.
enum ScoutingTab: String, CaseIterable, Identifiable {
    case board      = "board"
    /// The class one level up from the board: how deep the DECLARED pool is per
    /// position, by projected-round tier, against the club's own holes (#128).
    case classDepth = "classDepth"
    case combine    = "combine"
    case film       = "film"
    case interviews = "interviews"
    case proDays    = "proDays"
    case workouts   = "workouts"
    case mockDraft  = "mockDraft"
    case top30      = "top30"
    case draftOrder = "draftOrder"
    case scouts     = "scouts"
    case nextYear   = "nextYear"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .board:      return "Big Board"
        case .classDepth: return "Class Depth"
        case .combine:    return "Combine"
        case .film:       return "Film Study"
        case .interviews: return "Interviews"
        case .proDays:    return "Pro Days"
        case .workouts:   return "Workouts"
        case .mockDraft:  return "Mock Draft"
        case .top30:      return "Top-30"
        case .draftOrder: return "Draft Order"
        case .scouts:     return "Scout Team"
        case .nextYear:   return "Next Yr"
        }
    }

    var icon: String {
        switch self {
        case .board:      return "list.number"
        case .classDepth: return "chart.bar.fill"
        case .combine:    return "figure.run"
        case .film:       return "film"
        case .interviews: return "bubble.left.and.bubble.right"
        case .proDays:    return "mappin.and.ellipse"
        case .workouts:   return "figure.strengthtraining.traditional"
        case .mockDraft:  return "doc.text"
        case .top30:      return "building.2"
        case .draftOrder: return "number.circle"
        case .scouts:     return "binoculars"
        case .nextYear:   return "calendar.badge.clock"
        }
    }

    /// The stage this tab belongs to, or `nil` for a tab that is not part of the
    /// pipeline at all (the board, the draft order, the scout department and
    /// next year's class are reference surfaces and are always open).
    var stage: DraftPrepStep? {
        switch self {
        case .combine:    return .combineReview
        case .film:       return .filmStudy
        case .interviews: return .interviews
        case .proDays:    return .proDayFocus
        case .workouts:   return .workouts
        case .top30:      return .top30Visits
        // The mock is deliberately NOT stage-gated. `WeekAdvancer` runs four
        // mocks across the year — a mid-season one in week 9, one out of the
        // combine — and all of them are public information the moment they
        // publish. Two of the four are *stages* (§5.7), and those complete by
        // being read, which the hub handles when the tab is opened; hiding the
        // screen until then would put the autumn mocks behind a gate they were
        // never behind.
        case .board, .classDepth, .mockDraft, .draftOrder, .scouts, .nextYear:
            return nil
        }
    }

    /// Whether the tab owns priced or rationed actions. A passed stage whose tab
    /// has none of those (the mock) is simply a read and gets no "complete"
    /// chip — nothing about it closes.
    var hasStageActions: Bool {
        switch self {
        case .combine, .film, .interviews, .proDays, .workouts, .top30: return true
        default: return false
        }
    }

    /// The screen a stage of the pipeline lives on.
    ///
    /// The inverse of ``stage``, and it has to be written out rather than
    /// derived from it: two stages share the Mock Draft screen, and `.ready` has
    /// no screen of its own at all — the board is what a club with a closed book
    /// looks at while it waits for the clock.
    static func forStage(_ step: DraftPrepStep) -> ScoutingTab {
        switch step {
        case .combineReview: return .combine
        case .interviews:    return .interviews
        case .filmStudy:     return .film
        case .proDayFocus:   return .proDays
        case .workouts:      return .workouts
        case .mockOne:       return .mockDraft
        case .top30Visits:   return .top30
        case .mockTwo:       return .mockDraft
        case .ready:         return .board
        }
    }
}

// MARK: - Hire Scout Sheet (placeholder)

private struct HireScoutSheet: View {
    let career: Career
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Determine the next available scout role that isn't filled yet.
    private var nextAvailableRole: ScoutRole? {
        guard let teamID = career.teamID else { return ScoutRole.regionalScout1 }
        let descriptor = FetchDescriptor<Scout>(
            predicate: #Predicate { $0.teamID == teamID }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let filledRoles = Set(existing.map(\.scoutRole))
        return ScoutRole.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .first { !filledRoles.contains($0) }
    }

    /// R27: real remaining scouting budget (owner's scouting pot minus current
    /// scout salaries) instead of the old hardcoded placeholder.
    private var remainingScoutBudget: Int {
        guard let teamID = career.teamID else { return 4_000 }
        let teamDesc = FetchDescriptor<Team>(predicate: #Predicate { $0.id == teamID })
        let budget = (try? modelContext.fetch(teamDesc))?.first?.owner?.scoutingBudget ?? 4_000
        let scoutDesc = FetchDescriptor<Scout>(predicate: #Predicate { $0.teamID == teamID })
        let used = ((try? modelContext.fetch(scoutDesc)) ?? []).reduce(0) { $0 + $1.salary }
        return budget - used
    }

    var body: some View {
        NavigationStack {
            if let role = nextAvailableRole {
                HireScoutView(
                    scoutRole: role,
                    teamID: career.teamID ?? UUID(),
                    career: career,
                    remainingBudget: remainingScoutBudget,
                    poolSeed: career.teamID.map {
                        CoachingEngine.scoutPoolSeed(teamID: $0, role: role, season: career.currentSeason)
                    }
                ) { _, _ in
                    dismiss()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            } else {
                ZStack {
                    Color.backgroundPrimary.ignoresSafeArea()
                    VStack(spacing: 20) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.textTertiary)
                        Text("Scout Staff Full")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        Text("You have filled all 8 scout slots.")
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                }
                .navigationTitle("Hire Scout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
}

// MARK: - Next Year's Class Preview

struct NextYearClassPreview: View {
    let career: Career
    let prospects: [ScoutingEngine.NextYearProspect]

    var body: some View {
        List {
            Section {
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(Color.accentGold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Early Look \u{2014} \(String(career.currentSeason + 1)) Draft Class")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                        Text("Full scouting begins next season")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .listRowBackground(Color.backgroundSecondary)

            Section("Top Prospects") {
                ForEach(Array(prospects.enumerated()), id: \.element.id) { index, prospect in
                    nextYearProspectRow(rank: index + 1, prospect: prospect)
                }
            }
            .listRowBackground(Color.backgroundSecondary)
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private func nextYearProspectRow(rank: Int, prospect: ScoutingEngine.NextYearProspect) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.system(size: 14, weight: .heavy).monospacedDigit())
                .foregroundStyle(rank <= 3 ? Color.accentGold : Color.textTertiary)
                .frame(width: 28, alignment: .trailing)

            Text(prospect.position.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 32, height: 22)
                .background(positionColor(prospect.position), in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

            VStack(alignment: .leading, spacing: 2) {
                Text(prospect.fullName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(prospect.college)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                    Text(prospect.classYear)
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            Text(prospect.projectedGrade)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(projectedGradeColor(prospect.projectedGrade))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(projectedGradeColor(prospect.projectedGrade).opacity(0.12))
                )
        }
    }

    private func positionColor(_ position: Position) -> Color {
        switch position.side {
        case .offense:      return .accentBlue
        case .defense:      return .danger
        case .specialTeams: return .accentGold
        }
    }

    private func projectedGradeColor(_ grade: String) -> Color {
        switch grade {
        case "Top 10 Pick": return .accentGold
        case "1st Round":   return .success
        default:            return .textSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ScoutingHubView(career: Career(
            playerName: "John Doe",
            role: .gm,
            capMode: .simple
        ))
    }
    .modelContainer(for: [Career.self, Scout.self, CollegeProspect.self], inMemory: true)
}
