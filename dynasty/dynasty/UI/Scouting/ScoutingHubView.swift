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

    // NO `lastStageTab` (#164). It existed for exactly one consumer — the #130
    // switcher's stage segment, which had to decide WHICH stage room to offer in
    // its single slot, and offering the room the user was last working in was
    // the right answer for a one-slot control. The band is the stage navigation
    // now: all six rooms are on screen at all times, in order, each one tap, so
    // "walk back into the room I was in" needs no memory to remember it. The
    // state had no reader left, and dead `@State` is not something the compiler
    // warns about.

    /// The War Room surface to return to when the WAR ROOM slat is tapped (#165).
    ///
    /// The mirror image of the argument above, and the reason it is right here
    /// and was wrong there. The six stage rooms each own a slat, so the band
    /// remembers where the user was by SHOWING it; the five War Room surfaces
    /// share ONE slat, and a one-slot control that always dumps the user on the
    /// Big Board would make "look at the class-depth read, check a stage, come
    /// back" a three-tap round trip in the reference direction and a one-tap
    /// round trip in the stage direction. Big Board is the seed, per the landing
    /// rule; after that it is wherever the user last stood.
    @State private var lastWarRoomTab: ScoutingTab = .board

    /// True while the user is standing on a screen pushed out of the hub — a
    /// prospect card, a scout's page — rather than on the hub itself (#191).
    ///
    /// The hub stays alive underneath a push, and the model work done up there
    /// (a workout run from a prospect card moves `Career.prepStep`) reaches its
    /// observers all the same. Without this flag the tab auto-advance fired
    /// against a user who was not looking, and Back dropped him on a surface he
    /// had never opened. Cleared one run loop AFTER the hub reappears, because
    /// the `onChange` carrying the change made while away is delivered in the
    /// same update as `onAppear` and there is no ordering guarantee between the
    /// two — clearing it synchronously would re-open the race it closes.
    @State private var isAwayOnPushedScreen = false

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
        //
        // `.workouts` IS a prospect table and was missing from this list (#190).
        // `WorkoutsTabView` takes `$positionFilter` and filters its candidate
        // list on it — but the hub drew no chip row over that tab and the screen
        // hosts none of its own, so the shared binding narrowed the invite list
        // INVISIBLY: pick QB on the Big Board, walk into Private Workouts, and
        // the room is empty with no control anywhere on screen to say why or to
        // undo it. A filter with no visible control is not a filter, it is a
        // fault. (`.top30` and `.proDays` stay off the list on purpose: neither
        // screen reads the binding, so a chip row over them would be the mirror
        // fault — a control that does nothing.)
        case .board, .film, .combine, .classDepth, .workouts: return true
        default:                                              return false
        }
    }

    /// Whether the HUB draws the chip row, as opposed to the surface hosting it
    /// on its own table. See the layer-4 comment in ``processChrome`` — the Big
    /// Board takes it (`hostsPositionChips`), everything else leaves it here.
    private func hostsPositionFilterChips(progress: DraftPrepProgress) -> Bool {
        guard positionFilterAppliesToCurrentTab, selectedTab != .board else { return false }
        // `WorkoutsTabView` is the one surface here that REPLACES its table with
        // a lock panel when its stage is shut — off the same `canAct` the hub
        // hands it — and chips over a lock panel filter nothing. The film and
        // combine surfaces keep their tables (and want their filters) after
        // their own stage closes, so they are deliberately not gated.
        if selectedTab == .workouts { return progress.canAct(.workouts) }
        return true
    }

    // MARK: - Body
    //
    // ONE NAVIGATION ROW (#165).
    //
    //   1. the slat band          — THE WHOLE NAVIGATION. `[WAR ROOM]‖[1 COMBINE
    //                               REVIEW][2 INTERVIEWS][3 FILM STUDY][4 PRO DAY
    //                               FOCUS][5 PRIVATE WORKOUTS][6 TOP-30 VISITS]`.
    //                               Six numbered slats, one per room the club
    //                               works, each carrying its state and its own
    //                               count of work; and, before a wider seam, one
    //                               PLACE slat — unnumbered, stateless, outside
    //                               "STAGE N OF 6" and outside the meter. FULL
    //                               height on every hub surface, because it is
    //                               the navigation (see `isCompact` below)
    //   1a. the War Room tab row  — the five permanent destinations: Big Board ·
    //                               Class Depth · Draft Order · Mock Draft ·
    //                               Scout Team. Drawn directly under the band and
    //                               ONLY while the War Room slat is selected,
    //                               because only then are they the question. The
    //                               active tab's gold fill is that row's
    //                               current-marker
    //   2. Insights               — the surface's title bar, and behind its
    //                               chevron everything that used to stack above
    //                               the list: the stage explainer, the
    //                               "N % scouted · phase" strip, the Draft Prep
    //                               card, the combine's risers/fallers, the
    //                               class-depth declaration header
    //   3. the position chips     — directly on top of the table, so the shared
    //                               filter reads as part of the list's own
    //                               controls rather than as a third nav row
    //
    //   … then the surface, whose own controls (mode chips, search, sortable
    //   column labels) live in ITS pinned list header, and finally the action
    //   bar, which is a transition and not an insight and therefore never folds.
    //
    // What this replaced, twice over. #130's three-slot switcher hid five
    // permanent screens behind a chevron and gave the stage surface a slot that
    // changed its own label. #164 fixed the hiding by giving the stages a band
    // and the places a strip — and shipped TWO permanent, full-width navigation
    // rows stacked on every surface in the hub, with nothing anywhere saying how
    // the two related. They do not need to relate: they are one navigation. A
    // stage is a step in a process and a war-room screen is a place, and one
    // ribbon can carry both as long as the place is drawn as a place — no
    // number, no state, no gold, its own seam. That is `DSSlat.Role.place`.
    //
    // THE SELECTION MODEL IS `selectedTab`, STILL. There is no second piece of
    // state for "which slat is lit": `warRoomTabs.contains(selectedTab)` selects
    // the place slat, and `selectedTab.stage` selects a numbered one. The two
    // sets partition all eleven tabs, so the band always has exactly one
    // selection and it can never disagree with the screen underneath it.

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
                        .foregroundStyle(Color.textSecondary)
                }
            } else {
                loadedBody
            } // end else (not loading)
        }
        .navigationTitle("Scouting")
        // INLINE, unlike the rest of the app's pushed screens, and for a reason
        // this screen alone has: the shell's own nav strip already prints
        // "Scouting" a row above, and below the title sit the slat band AND the
        // tab's own header. A 44 pt large title repeating the word cost ~17 % of
        // the screen before anything specific to the surface — the band's lit
        // slat is what actually says where the user is standing.
        .navigationBarTitleDisplayMode(.inline)
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
        // Push / pop bookkeeping for `isAwayOnPushedScreen` (#191). `onDisappear`
        // on a stack root fires when a child is pushed over it, `onAppear` when
        // that child pops — the same pair `CareerDashboardView` uses to refresh
        // its staff tile on the way back.
        .onDisappear { isAwayOnPushedScreen = true }
        .onAppear {
            // See the property's doc comment for why this is deferred.
            DispatchQueue.main.async { isAwayOnPushedScreen = false }
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
                // TOTAL OVER ALL ELEVEN TABS (#165). Every `ScoutingTab` has a
                // hint string, plus the three legacy aliases, so no writer can
                // name a surface the hub cannot open. `default` stays — a hint
                // is untrusted input from a career-scoped default that can
                // outlive the build that wrote it.
                let hinted: ScoutingTab? = {
                    switch pending {
                    // --- the six stage rooms → their numbered slat's surface ---
                    // No longer phase-gated: an earlier stage is never shut, so
                    // a task that points at the interview room can always open
                    // it. Refusing the hint outside the combine is what made a
                    // REQUIRED task deep-link into nothing.
                    case "combine":    return .combine
                    case "interviews": return .interviews
                    case "film":       return .film
                    case "proDays":    return .proDays
                    case "workouts":   return .workouts
                    case "top30":      return .top30
                    // --- the five War Room tabs → the place slat + that tab ---
                    // `bigBoard` / `prospects` are the two legacy hints: the tab
                    // they named is one surface now, so both land on the board.
                    case "bigBoard", "prospects", "board": return .board
                    // #128. The January "Showcase & declarations" task used to
                    // land on `.combine`, which in `.reviewRoster` is a screen
                    // reading "0 of 0 prospects invited" — the league has not
                    // issued an invite list yet, and cannot have. It lands here.
                    case "classDepth": return .classDepth
                    case "scoutNotes": return .scoutNotes
                    case "mockDraft":  return .mockDraft
                    case "draftOrder": return .draftOrder
                    case "scouts":     return .scouts
                    // The Tools menu's sixth entry, folded into the draft-order
                    // surface's NEXT YEAR horizon by #164. A hint written by an
                    // older build (or left in a save's defaults by one) still
                    // names the screen the user asked for rather than nothing.
                    case "nextYear":   return .draftOrder
                    default:           return nil
                    }
                }()
                // Every stage room is reachable from the band and every War Room
                // surface from the band's place slat — nothing is behind a menu
                // and nothing is hidden — so a hint is simply obeyed. A War Room
                // hint selects the place slat implicitly: the band's selection is
                // read off `selectedTab`, and `onChange` seeds `lastWarRoomTab`
                // so walking out to a stage and back returns here.
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
                // Live work wins; otherwise the WAR ROOM SLAT, on the Big Board —
                // its first tab and the one surface that is always true (#164,
                // #165).
                //
                // "Live work" is still `Career.prepStep`'s room, and for the two
                // mock stages that room is the War Room's Mock Draft tab: an
                // unfiled mock IS the work in front of the club, and it is where
                // the stage's one act lives. So a mock landing selects the place
                // slat with the Mock Draft tab active, and the numbered run
                // stays exactly one tap away either way.
                let progress = prepProgress
                let current = progress.current
                selectedTab = (progress[current].unlocked && !progress[current].isSatisfied)
                    ? currentStageTab
                    : .board
            }
            isLoading = false
        }
        .onChange(of: selectedTab) { _, newTab in
            // Where the WAR ROOM slat goes back to (#165). Recorded here rather
            // than at the five tap sites, so a route into a reference surface
            // that does NOT come from the tab row — the action bar's "Open Mock
            // 1.0", a board empty-state CTA, the class-depth hand-off, a
            // deep-link hint — is remembered on exactly the same terms.
            if Self.warRoomTabs.contains(newTab) { lastWarRoomTab = newTab }
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
                surfaceKey: insightsSurfaceKey(newTab)
            )
            // Reviewing is opening the tab and finding numbers in it. It used to
            // additionally require that scouts had been sent, which made the
            // task uncompletable for a class the user chose to watch on
            // television — and permanently uncompletable when the combine had
            // never been run at all.
            if newTab == .combine && prospects.contains(where: { $0.fortyTime != nil }) {
                combineResultsReviewed = true
            }
            // NO INVISIBLE COMPLETIONS (P1, wave 0 of #105).
            //
            // The two mock stages used to complete HERE, on `newTab ==
            // .mockDraft`: opening the tab stamped the read and moved the
            // pipeline, so two of the spring's nine stages were satisfied by an
            // act the user never performed and never saw acknowledged. The stamp
            // is now `MockDraftView`'s "File this mock" primary — same key, same
            // season value, same forward move — so the required tasks, the
            // stage gates and `Career.derivedPrepStepFloor` all read exactly
            // what they read before, and the user has to mean it.
            //
            // See `mockFiling(_:)` and `fileMock(_:)`.
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
            // Never from a War Room tab. Those are places the user chose to
            // stand in — the board he is building, the mock he is reading — and
            // yanking him out of one because a background ledger moved the
            // pipeline is the same class of defect as a screen that deletes
            // itself. The band is one tap away when he wants the new room.
            //
            // AND NEVER WHILE THE HUB IS OFF SCREEN (#191). The rule above is
            // right and it was one case short: a *stage* room is a place the
            // user chose to stand in too, for exactly as long as he is standing
            // on a screen pushed out of it. Every instrument the pipeline moves
            // on can be run from the prospect card — a private workout, a film
            // order, an interview — so "open a man from Private Workouts, run
            // his workout, press Back" landed the user on a surface he never
            // asked for, and once the pipeline reaches `.ready` that surface is
            // the Big Board (`ScoutingTab.forStage(.ready)`), which is exactly
            // the report. A push is not a transition the user made through the
            // process; it is a detour he is coming back from, and he comes back
            // to the room he left. The band still carries the new room.
            guard !isAwayOnPushedScreen else { return }
            guard newStep != oldStep, !Self.warRoomTabs.contains(selectedTab) else { return }
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
            case .combineReport: CombineReportSheet(
                mentions: combineMedia,
                career: career,
                prospects: prospects,
                // The sheet's closing line is about the FILING, not the
                // headlines, and only the trip files anything.
                scoutsAttended: scoutsSentToCombine
            )
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
        // The trip's whole yield is `applyCombineScouting`, which opens with
        // `guard !scouts.isEmpty ... else { return 0 }`. Spending the flight to
        // buy zero reports is not a decision the user should be able to make by
        // accident, and the CTA is now drawn blocked for the same reason —
        // this guard is the belt to that braces, because the Scout Team tab
        // hands the same closure down.
        guard !scouts.isEmpty else { return }

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
        prospects.filter({ ProspectFog.hasOwnReport($0) }).count
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
        /// Men the club has actually had in a room this cycle.
        ///
        /// A SECOND KIND OF COVERAGE, and the hub needs it because `filed` is
        /// deaf to the biggest spend of the spring: an interview writes exact
        /// Football IQ and a handful of revealed bands onto a man without
        /// filing paper, so burning 53 of the 60 slots moves `percent` by
        /// nothing at all. Cheap on top of the walk above — `interviewCompleted`
        /// is a stored `Bool`, not a `Codable` decode.
        let met: Int
    }

    private func coverageReadout() -> CoverageReadout {
        let filed = scoutedCount
        let met = prospects.filter(\.interviewCompleted).count
        guard !prospects.isEmpty else { return CoverageReadout(filed: filed, percent: 0, met: met) }
        return CoverageReadout(
            filed: filed,
            percent: Int((Double(filed) / Double(prospects.count) * 100).rounded()),
            met: met
        )
    }

    private var phaseLabel: String {
        switch career.currentPhase {
        case .proBowl:          return "All-Star Game"
        case .superBowl:        return "The Championship"
        case .coachingChanges:  return "Coaching Changes"
        case .reviewRoster:     return "Review Roster"
        case .combine:          return "The Combine"
        case .freeAgency:       return "Free Agency"
        case .proDays:          return "Pro Days & Workouts"
        case .draft:            return "The Draft"
        case .otas:             return "OTAs"
        case .trainingCamp:     return "Training Camp"
        case .preseason:        return "Preseason"
        case .rosterCuts:       return "Roster Cuts"
        case .regularSeason:    return "Regular Season"
        case .tradeDeadline:    return "Trade Deadline"
        case .playoffs:         return "Playoffs"
        }
    }

    /// Takes the progress it is given rather than building its own: one
    /// `DraftPrepProgress` per body pass, and the gate can never disagree with
    /// the band drawn from the same value.
    private func stageGate(_ progress: DraftPrepProgress) -> ScoutingStageGate {
        ScoutingStageGate.make(progress: progress, career: career)
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

    // MARK: - Filing a mock (#105 wave 0 — P1, no invisible completions)

    /// The mock stage the Mock Draft screen can close right now, or `nil` when
    /// there is no honest one.
    ///
    /// The rule is the one the tab-open stamp used: whichever mock stage the club
    /// may ACT in, not only the one it is standing in — `reach` opens the next
    /// room as soon as the current stage is satisfied, so `.mockOne` and
    /// `.mockTwo` are both commonly actionable. The first unfiled one wins;
    /// with both filed the screen has nothing to offer and the band's `done`
    /// slat is what says so.
    /// The mock the club owes right now, or `nil`.
    ///
    /// **The one predicate for the whole mock obligation (#164).** With the two
    /// mock stages off the band, "there is a mock to file" has to be visible in
    /// three places at once — the War Room tab's needs-filing badge, the hub's
    /// action-bar explainer, and the Mock Draft screen's own filing bar — and
    /// three copies of a test that is `canAct && !isSatisfied` is exactly how the
    /// shipped build ended up with a REQUIRED task burning red over a stage the
    /// club had finished. One function, three readers.
    ///
    /// The rule is the one the tab-open stamp used: whichever mock stage the club
    /// may ACT in, not only the one it is standing in — `reach` opens the next
    /// room as soon as the current stage is satisfied, so `.mockOne` and
    /// `.mockTwo` are both commonly actionable. `canAct` is `Stage.unlocked`, so
    /// this is false outside the mock's calendar window, which is what makes the
    /// badge honest in February.
    private func pendingMock(_ progress: DraftPrepProgress) -> DraftPrepStep? {
        [DraftPrepStep.mockOne, .mockTwo]
            .first { progress.canAct($0) && !progress[$0].isSatisfied }
    }

    private func mockFiling(_ progress: DraftPrepProgress) -> MockDraftFiling? {
        guard let step = pendingMock(progress) else { return nil }
        return MockDraftFiling(
            stageName: step.displayName,
            explainer: step == .mockOne
                ? "Records that you have read where the league has your board, and moves the club to **Top-30 Visits**."
                : "Records your last read on the market. The draft room opens on the clock in **draft week**.",
            file: { fileMock(step) }
        )
    }

    /// Stamps the read and takes the forward step — **exactly what opening the
    /// tab used to do**, on a button the user pressed on purpose.
    ///
    /// Same two career-scoped keys (`DraftPrepProgress.Key.mockOneRead` /
    /// `.mockTwoRead`), same season value, same `advance(to:)` cap. So
    /// `DraftPrepProgress.satisfied(.mockOne/.mockTwo)`, the required tasks keyed
    /// on "Read the mock" / "Read the final mock", and
    /// `Career.derivedPrepStepFloor`'s evidence read are all unchanged — a filed
    /// mock satisfies precisely as the old stamp did.
    private func fileMock(_ step: DraftPrepStep) {
        switch step {
        case .mockOne: mockOneReadSeason = career.currentSeason
        case .mockTwo: finalMockReadSeason = career.currentSeason
        default:       return
        }
        // `.mockTwo` -> `.ready` is calendar-gated and `advance` refuses to cross
        // in March; recording the read is what matters, and it has already
        // happened above.
        if career.prepStep == step, let next = step.next { advance(to: next) }
    }

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

    // MARK: - The one navigation row (#164, unified #165)

    /// **The War Room** — the five permanent destinations, in row order.
    ///
    /// Not a pipeline and not a menu: the board you build, the class behind it,
    /// the order you pick in, the mock the league prints, and the department
    /// that does the work. Every one of them is a place you return to rather
    /// than a step you complete, which is exactly why none of them belongs on
    /// the band and why none of them may be hidden behind a chevron.
    ///
    /// `.classDepth` sits directly behind the board because it is the same class
    /// read one level up: the board is 350 rows of men, the depth screen is the
    /// nine sentences those rows add up to. It is the January landing surface for
    /// the declaration / Showcase task (#128), and it is open all year.
    /// `.scoutNotes` sits third because the row reads outward from the board:
    /// the 350 men you rank, the shape of the class behind them, what the
    /// department makes of both — then the order you pick in, the mock the
    /// league prints, and the staff who do the work.
    private static let warRoomTabs: [ScoutingTab] =
        [.board, .classDepth, .scoutNotes, .draftOrder, .mockDraft, .scouts]

    // NO `stageTabs` SET (#165). It existed to answer "is a stage surface
    // showing", and its one reader was the band's `isCompact`, which is gone —
    // the band is the navigation and is full-height everywhere. The complement
    // of `warRoomTabs` over the eleven tabs is the same answer, computed from
    // one list instead of two that could drift apart: a tab added to
    // `ScoutingTab` and to neither set used to be silently "a stage".

    /// The tab whose screen belongs to the stage the club is standing in.
    ///
    /// Not `selectedTab.stage`: the two mock stages route to `.mockDraft`, which
    /// is deliberately NOT stage-gated (four mocks print across the year and all
    /// of them are public the moment they publish), so it carries no `stage` of
    /// its own and the reverse lookup has to come from the step.
    private var currentStageTab: ScoutingTab { ScoutingTab.forStage(career.prepStep) }

    /// The stage the selected tab is showing, or `nil` on a War Room tab.
    ///
    /// One line now, and that is the point: with the mocks off the band there is
    /// no tab that is a reference surface AND a stage screen, so the band's
    /// selection is exactly "which slat's room is on screen".
    private var selectedStage: DraftPrepStep? { selectedTab.stage }

    /// Whether the band's WAR ROOM place slat is the selected one — and so
    /// whether the five-tab row is drawn beneath the band (#165).
    ///
    /// Derived, not stored. The eleven tabs partition into the five War Room
    /// surfaces and the six stage rooms, so `selectedTab` alone decides which
    /// slat is lit and whether the row is on screen; a second `@State` for it
    /// would be a second answer to a question that already has one.
    private var isWarRoomSelected: Bool { Self.warRoomTabs.contains(selectedTab) }

    /// "<career>-<tab>" — the Insights fold key for one surface of THIS save.
    ///
    /// **The career id is load-bearing.** `ScoutingInsightsDefaults.openKey` is
    /// plain `UserDefaults`, not `@CareerScopedStorage`, and it is not on
    /// `CareerScopedDefaults.keys` either — so deleting a save leaves the row
    /// behind and the next career would inherit it.
    ///
    /// This used to be a "<career>-<season>-<phase>" token, because the rule was
    /// "open once per surface per phase" and the token was what re-armed it; the
    /// career id got folded in to fix the leak (a new career in the same league
    /// year and phase read a MATCHING seen-token, spent a free expansion it
    /// never had, and fell through to the previous career's preference). #174
    /// deleted the free expansion — the block is shut until the user opens it —
    /// so there is nothing left to re-arm and the season/phase parts had no
    /// remaining job. The scoping moves onto the key itself, which is where it
    /// always belonged.
    private func insightsSurfaceKey(_ tab: ScoutingTab) -> String {
        "\(career.id.uuidString)-\(tab.rawValue)"
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

    // MARK: - The loaded hub
    //
    // ONE `DraftPrepProgress` PER BODY PASS. It walks a ~350-man draft class to
    // prove the combine was held, and this screen re-evaluates on every `@State`
    // touch — the chrome, the surface underneath and the action bar all need it,
    // and building it three times is three walks.

    private var loadedBody: some View {
        let progress = prepProgress
        let cells = bandCells(progress: progress)
        return VStack(spacing: 0) {
            processChrome(progress: progress, cells: cells)

            Divider()
                .overlay(Color.surfaceBorder)

            tabContent(progress: progress)

            // The transition. It used to be a 12 pt greyed button inside the
            // Big Board's scroll-away header — the single most important control
            // on the screen, parked where a 350-row list scrolled it out of
            // existence. It is NOT an insight and never folds: a requirement and
            // the button that satisfies it are the work.
            hubActionBar(progress: progress, cells: cells)
        }
    }

    /// The six slats, built once and read by the band, its head, its meter and
    /// the action bar's terminal test.
    private func bandCells(progress: DraftPrepProgress) -> [DraftPrepStageCell] {
        DraftPrepStageCell.bandSteps.enumerated().map { index, step in
            DraftPrepStageCell(
                step: step,
                displayIndex: index + 1,
                state: stageState(step, progress: progress),
                stage: progress[step]
            )
        }
    }

    // MARK: - Process chrome

    private func processChrome(
        progress: DraftPrepProgress,
        cells: [DraftPrepStageCell]
    ) -> some View {
        let stage = selectedStage
        let coverage = coverageReadout()
        let owedMock = pendingMock(progress)
        let owedMockText = owedMock.map { "\($0.displayName) has not been filed" } ?? ""
        let hostsChips = hostsPositionFilterChips(progress: progress)
        return VStack(spacing: 0) {
            // Layer 1: THE NAVIGATION. One row: the War Room place slat, a seam,
            // then the six rooms in calendar order, each carrying its state and
            // its own count of work, none ever hidden.
            //
            // ALWAYS FULL HEIGHT (#165). #164 demoted it to the compact ribbon on
            // a War Room tab, on the reasoning that the pipeline is context there
            // rather than the subject. That reasoning was sound while a second,
            // full-size strip sat above it carrying the navigation — it is not
            // now: this row IS the navigation on every surface in the hub, and a
            // navigation that shrinks 12 pt and drops its sub-captions depending
            // on which of its own destinations you picked is a control that
            // changes shape under the finger. `DSSlatBand.isCompact` stays in the
            // component for the consumers it was written for — a band that is
            // genuinely context on someone else's screen.
            DraftPrepProcessBar(
                cells: cells,
                selected: stage,
                // Counted off `cells`, which is the SIX rooms — the place slat
                // is not a working week and never appears in either number.
                headline: bandHeadline(cells: cells, selected: stage),
                meter: stageWeeks(cells: cells),
                isWarRoomSelected: isWarRoomSelected,
                // The obligation, one level up. `pendingMock` is the ONE
                // predicate (see its doc comment); the tab below and this dot are
                // two readers of it, not two tests.
                warRoomHasObligation: owedMock != nil,
                warRoomObligationText: owedMockText,
                onSelect: { selectStage($0) },
                onSelectWarRoom: { selectWarRoom() }
            )
            .padding(.horizontal, 12)
            .padding(.top, 2)
            .padding(.bottom, 8)

            // Layer 1a: what is INSIDE the War Room. Five destinations, named,
            // and on screen only while their slat is selected — the one moment
            // they are the question the user is asking. The gold fill marks the
            // active one, so on a stage surface (no row at all) the band's
            // current rule and the action bar's primary are the whole of the
            // screen's gold (P5).
            if isWarRoomSelected {
                ScoutingWarRoomTabs(
                    tabs: Self.warRoomTabs,
                    selected: selectedTab,
                    badgedTabs: owedMock == nil ? [] : [.mockDraft],
                    badgeAccessibilityText: owedMockText,
                    onSelect: { selectedTab = $0 }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            // Layer 2: the surface's title, and behind one chevron everything
            // that used to be stacked above the list unasked.
            ScoutingInsightsSection(
                surfaceKey: insightsSurfaceKey(selectedTab),
                title: selectedTab.label,
                icon: selectedTab.icon,
                stateChip: insightsStateChip(progress: progress),
                teaser: insightsTeaser(progress: progress, stage: stage, coverage: coverage),
                isExpanded: $insightsExpanded
            ) {
                insightsBody(progress: progress, stage: stage, coverage: coverage)
            }
            // A fresh instance per surface: `ScoutingInsightsSection` binds its
            // `@AppStorage` key at init, so without this the board's fold state
            // would follow the user onto the combine.
            .id(selectedTab.rawValue)
            .padding(.horizontal, 12)
            .padding(.bottom, hostsChips ? 6 : 8)

            // Layer 3: the shared filter, LAST, so it sits on the table rather
            // than between two blocks of prose. The table's own controls (mode
            // chips, search, sortable column labels) are pinned inside its list
            // header directly underneath, and the two read as one strip.
            //
            // The Big Board is the exception and hosts the row itself: it is the
            // one surface whose controls are a stack ABOVE its list rather than
            // inside its list header, so a chip row pinned here would be four
            // controls away from the table it filters (#142).
            if hostsChips {
                positionFilterChips
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
        }
    }

    // MARK: - The spring's arithmetic, computed once
    //
    // THE BAND HEAD, THE METER AND THE ACTION BAR READ THE SAME FUNCTIONS.
    // §2.13's arithmetic gate is the reason they are functions at all: the
    // shipped hub printed its stage count three times on one screen (the
    // switcher's subtitle, the metrics strip and the prep card's collapsed line)
    // and its progress as three different metaphors. Now the count is rendered
    // ONCE — here — and every other surface reads what this returns or says
    // nothing.
    //
    // The model: **the spring is six working weeks, and the week you are standing
    // in is already spent.** So `spent + left == 6` at every moment, the
    // brightest pip is the room you are in, and "Stage 4 of 6" over "4 spent ·
    // 2 left" is one claim stated twice rather than two claims that can drift.
    //
    // SIX, NOT NINE (#164). The meter used to count `DraftPrepStep.allCases`,
    // and with three of those steps off the band the pips and the slats stopped
    // being countable against each other — nine pips over six slats is precisely
    // the "same quantity, two renderings" defect §2.13 exists to stop. The
    // machine still has nine steps; the METER counts the rooms the band draws,
    // which is what the user can see.

    /// The stage the band draws as `current`, or `nil` — which happens two ways:
    /// outside the pre-draft window, where the pipeline has not started at all
    /// whatever `Career.prepStep`'s floor says, and while the club is standing in
    /// a mock, which has no slat.
    private func bandCurrentStep(cells: [DraftPrepStageCell]) -> DraftPrepStep? {
        cells.first(where: { $0.state == .current })?.step
    }

    /// The spring's six working weeks. A filled pip is a spent pip.
    ///
    /// Counted off the drawn slats rather than off `prepStep.order`, because the
    /// pointer can sit on a step that has no slat: standing in Mock 1.0 is five
    /// rooms behind you and one (Top-30) in front, and the meter has to read 5
    /// spent · 1 left rather than inventing a sixth spent week for a room nobody
    /// has walked into.
    private func stageWeeks(cells: [DraftPrepStageCell]) -> DSResourceMeter {
        let spent = cells.filter { $0.state == .done || $0.state == .current }.count
        return DSResourceMeter(
            spent: spent,
            total: DraftPrepStageCell.bandSteps.count,
            unit: "scouting weeks"
        )
    }

    /// WHERE THE CLUB STANDS, and — when they differ — WHICH ROOM IS ON SCREEN.
    ///
    /// The count is the club's position and stays that way: it is the same
    /// arithmetic the six pips beside it are drawn from, and a head that
    /// followed the selection would sit next to a meter that did not. But the
    /// two routinely disagree. `Career.prepStep` is a pointer the user advances
    /// by hand while `DraftPrepProgress.reach` opens the next room the moment
    /// this one is satisfied — so a combine review he has already read keeps the
    /// gold current rule while he selects the interview slat and spends
    /// stage-2 slots on the surface underneath. "Stage 1 of 6" over a screen
    /// that is entirely stage 2 is the one place the process prints its count
    /// naming a different room from the one the selection ring is on, one row
    /// below it. Naming the room on screen costs a clause and closes it.
    private func bandHeadline(cells: [DraftPrepStageCell], selected: DraftPrepStep?) -> String {
        let total = DraftPrepStageCell.bandSteps.count
        if let step = bandCurrentStep(cells: cells),
           let index = cells.firstIndex(where: { $0.step == step }) {
            let count = "Stage \(index + 1) of \(total)"
            guard let selected, selected != step,
                  cells.contains(where: { $0.step == selected })
            else { return count }
            return "\(count) \u{00B7} viewing \(selected.displayName)"
        }
        // No current room. Either every room is behind the club — the six-room
        // pipeline is settled and the head says so — or the calendar has not
        // opened the spring at all.
        if cells.allSatisfy({ $0.state == .done }) {
            return "Draft prep \u{00B7} \(total) of \(total) settled"
        }
        return "Draft prep \u{00B7} \(total) stages"
    }

    // MARK: - Insights composition (#130)

    /// Nothing. **Kept as a seam, deliberately empty.**
    ///
    /// It used to draw "STAGE 4 · CURRENT" — a third printing of the stage count
    /// and a second rendering of stage state, one row under a band whose whole
    /// job is to say both. Wave 0's rule is one stage-complete visual (the slat's
    /// `done` state) and one stage count (the band head), so the insights header
    /// is now the surface's title and nothing else.
    private func insightsStateChip(progress: DraftPrepProgress) -> String? { nil }

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
            // MET, NOT SCOUTED, and the board is where it belongs. "46 of 288
            // filed on" and "16 % scouted" are the same fact rendered twice —
            // 46/288 IS 16 % — so the spine of the hub was spending two of its
            // four clauses on one number and none on the one the interview room
            // moves. Reports are not the only intel the club buys.
            if coverage.met > 0 { parts.append("\(coverage.met) met") }
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
        // Not on the board: the fraction it opens with is this percentage, spelt
        // out. See the `.board` clause above.
        if selectedTab != .board { parts.append("\(coverage.percent)% scouted") }
        // ONE NAME PER ROOM. The phase clause says what week it is, which earns
        // a slot right up until it says the surface's own title back at it: the
        // pro-day surface ran "PRO DAYS · 0/25 focus slots · 16 % scouted ·
        // Pro Days & Workouts".
        if !phaseLabel.contains(selectedTab.label) { parts.append(phaseLabel) }
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
                    // ONE STAGE-COMPLETE VISUAL (#105 wave 0). An UNCOUNTED
                    // stage's counter is literally the word "Done" (or "Not
                    // read"), so this pill was a second done treatment printed
                    // one row under the band's done slat. A counted stage's
                    // counter is a real number and stays.
                    counterText: row.isCounted ? row.counter : nil,
                    lockReason: lockSentence(for: stage, row: row),
                    // The gate's requirement is a TARGET — "Open the Combine tab
                    // and read the numbers" — so it may only be printed over a
                    // stage that can actually be worked. A shut stage gets its
                    // lock sentence instead (#107).
                    requirement: (stage == progress.current && row.unlocked)
                        ? stageGate(progress).requirement
                        : "",
                    isWaitingOnCalendar: row.isCalendarLocked
                )
            }
            hubHeader(scoutedPercent: coverage.percent)
        }
    }

    /// The lock sentence the explainer prints — the engine's, except where the
    /// engine points at a stage that has no slat.
    ///
    /// `DraftPrepProgress` says "Finish or skip Mock 1.0 first." over a shut
    /// Top-30 room, and since #164 there is no Mock 1.0 slat to finish or skip:
    /// the mock is FILED, in the War Room. The band already rewrote its caption
    /// for exactly this reason (`DraftPrepStageCell.unlockCaption`); this is the
    /// same fact in the sentence the explainer has room for, so the two surfaces
    /// and the hub's action bar all describe one obligation one way. A calendar
    /// wait keeps the engine's sentence — it names a phase, not a room.
    private func lockSentence(for step: DraftPrepStep, row: DraftPrepProgress.Stage) -> String {
        let engineSentence = row.lockReason ?? ""
        guard !row.unlocked, !row.isCalendarLocked,
              let previous = step.previous,
              DraftPrepStageCell.mockSteps.contains(previous)
        else { return engineSentence }
        return "Opens after \(previous.displayName) is filed on the War Room's Mock Draft tab."
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

    /// Tapping the WAR ROOM slat (#165): the five-tab row appears under the band
    /// and the surface below it is the one the user last stood in — the Big
    /// Board on a fresh visit, per `lastWarRoomTab`.
    ///
    /// Note what this does NOT do: it does not clear the band's stage selection,
    /// because there is nothing to clear. The band's selection is `selectedTab`,
    /// and moving `selectedTab` into the War Room set moves the ring onto the
    /// place slat in the same pass. The gold current rule stays where it is —
    /// the club is still standing in the stage it was standing in, and the slat
    /// that says so is one tap away.
    private func selectWarRoom() {
        selectedTab = lastWarRoomTab
    }

    // MARK: - The hub's one commit surface (§2.5, P5)
    //
    // Three things can be true at the bottom of this hub, and exactly one of them
    // is drawn:
    //
    //   1. THE SPRING IS SETTLED — every working stage is behind the club. The
    //      bar is an explainer and nothing else: there is no button, because
    //      there is nothing left to press. (#164's "READY has no slat": the
    //      terminal state is a sentence, not a room.)
    //   2. THE PIPELINE IS BLOCKED ON A MOCK — the club is standing in Mock 1.0
    //      or the Final Mock and has not filed it. The mocks left the band, so
    //      this is where the obligation is stated, and the primary is the route
    //      to the tab that files it.
    //   3. THE CLUB MAY ADVANCE — the stage it is standing in is one the HUB owns
    //      the transition for. Explainer, one ghost skip, one gold primary.
    //
    // Otherwise: no bar. A `.open` stage's screen owns its own advance, and it
    // has to — for the pro-day tour the transition IS the batch action that
    // spends the focus-slot reservations, and two advance buttons over one
    // destructive transition is how a stray tap threw those reservations away in
    // the shipped build.

    @ViewBuilder
    private func hubActionBar(
        progress: DraftPrepProgress,
        cells: [DraftPrepStageCell]
    ) -> some View {
        // NEVER OVER THE MOCK DRAFT TAB. That screen draws its own `DSActionBar`
        // with the File primary (`mockFiling`), and two bars stacked would be two
        // gold primaries on one screen — the exact thing P5 forbids. On that tab
        // the filing bar IS the hub's commit.
        if selectedTab != .mockDraft {
            if allWorkingStagesSettled(progress) {
                draftReadyBar
            } else if let mock = blockingMock(progress) {
                mockBlockedBar(mock)
            } else if showsAdvanceBar(progress) {
                advanceBar(progress: progress, cells: cells)
            }
        }
    }

    /// Every stage that is WORK — the six rooms plus the two mocks — is settled.
    ///
    /// `.ready` is deliberately excluded: it is satisfied by `phase == .draft`,
    /// i.e. by the calendar rather than by the club, so including it would make
    /// this read false through the whole of March no matter how complete the
    /// spring was.
    private func allWorkingStagesSettled(_ progress: DraftPrepProgress) -> Bool {
        DraftPrepStep.allCases
            .filter { $0 != .ready }
            .allSatisfy { progress[$0].isSatisfied }
    }

    /// The mock the pipeline is actually stuck behind, as opposed to one that is
    /// merely available: `progress.current` is the pointer, so this is true only
    /// while nothing else can move until the mock is filed.
    private func blockingMock(_ progress: DraftPrepProgress) -> DraftPrepStep? {
        let step = progress.current
        guard DraftPrepStageCell.mockSteps.contains(step) else { return nil }
        let row = progress[step]
        guard row.unlocked, !row.isSatisfied else { return nil }
        return step
    }

    /// The terminal line. No buttons — the room opens on the league's clock.
    private var draftReadyBar: some View {
        DSActionBar(
            explainer: DSActionBar.Explainer(
                title: "Draft ready",
                message: career.currentPhase == .draft
                    ? "Every stage of the spring is settled and **the board is closed**. The room is open \u{2014} draft."
                    : "Every stage of the spring is settled and **the board is closed**. The draft room opens in **draft week**."
            )
        )
    }

    /// Stage blocked on an unfiled mock — stated here because the mock has no
    /// slat to state it on, and routed to the tab that files it.
    private func mockBlockedBar(_ step: DraftPrepStep) -> some View {
        // WHAT FILING ACTUALLY BUYS, per mock — the two are not the same promise.
        //
        // Mock 1.0 is a true gate: filing it opens Top-30 Visits, so naming the
        // room that is waiting is the honest sentence. The Final Mock is NOT —
        // `.mockTwo -> .ready` is calendar-gated (`ready.phase == .draft`) and
        // `advance(to:)` refuses the move in March, so "**Ready** stays shut
        // until the Final Mock is filed" promised a door that filing does not
        // open, and printed a machine-state name (`.ready`) that the user has no
        // room for on the band by design (#164).
        let message: String = {
            guard step != .mockTwo, let next = step.next else {
                return "Your last read on the market before the room opens in **draft week**. "
                    + "File it on the War Room's **Mock Draft** tab."
            }
            return "**\(next.displayName)** stays shut until \(step.displayName) is filed. "
                + "File it on the War Room's **Mock Draft** tab."
        }()
        return DSActionBar(
            explainer: DSActionBar.Explainer(
                title: "\(step.displayName) \u{2014} not filed",
                message: message,
                isWarning: true
            ),
            primary: DSActionBar.Action(
                title: "Open \(step.displayName)",
                accessibilityLabel: "Open the Mock Draft tab to file \(step.displayName)",
                handler: { selectedTab = .mockDraft }
            )
        )
    }

    /// Whether the hub owns the transition out of the stage the club is in.
    ///
    /// GATED ON THE SURFACE, and it has to be. #164 briefly dropped the
    /// `selectedTab == currentStageTab` guard on the theory that the hub's
    /// commit belongs to the club's position rather than to whichever screen is
    /// showing. Two things broke.
    ///
    /// 1. The bar's ghost is an IRREVERSIBLE skip — `advancePrepStep` never
    ///    lowers, so walking past interviews forfeits the ration for the spring.
    ///    Ungated, that ghost drew itself under the *combine* table when the
    ///    user tapped the done Combine slat to re-read the numbers: the screen
    ///    said one stage and the pinned bar spent another.
    /// 2. P5. On a War Room tab the strip's active-tab fill is the current
    ///    marker, and an advance bar there put a third gold fill (strip + band's
    ///    compact current rule + the bar's primary) on one screen, which this
    ///    hub's own chrome documents as impossible.
    ///
    /// The two bars that must follow the user everywhere — `draftReadyBar` and
    /// `mockBlockedBar` — stay global: neither carries a destructive control,
    /// and the whole point of taking the mocks off the band is that their
    /// obligation has to be stateable from wherever the user happens to be.
    private func showsAdvanceBar(_ progress: DraftPrepProgress) -> Bool {
        // Outside the pre-draft window there is nothing to advance INTO — a
        // disabled "Advance — Interviews" over a waiting screen reads as a
        // broken button, which is #107 verbatim. The stage slats and the
        // explainer already carry the "opens at the combine" message.
        guard career.currentPhase.prepCalendarRank > 0 else { return false }
        guard selectedTab == currentStageTab else { return false }
        if case .advance = stageGate(progress).action { return true }
        return false
    }

    /// The pinned transition for the stage the club is standing in.
    ///
    /// It used to be a bespoke bar with its own gold recipe and its own skip
    /// chip. On `DSActionBar` it is: an explainer stating what advancing does and
    /// what it costs, ONE ghost carrying the single skip the hub offers (labelled
    /// with what skipping forfeits), and ONE gold primary. A blocked commit
    /// swaps the explainer to its warn variant and states the reason, and the
    /// primary goes genuinely grey rather than dimmed gold.
    private func advanceBar(
        progress: DraftPrepProgress,
        cells: [DraftPrepStageCell]
    ) -> some View {
        let gate = stageGate(progress)
        // The SAME meter the band head is drawn from, so "2 left" in this
        // sentence and the unfilled pips two rows up are one number (§2.13).
        let weeks = stageWeeks(cells: cells)
        let nextName = gate.next?.displayName ?? "the draft room"
        let canCommit = gate.isComplete && !gate.isPhaseBlocked

        let message: String = {
            if gate.isPhaseBlocked { return gate.phaseBlockedReason }
            if !gate.isComplete { return gate.requirement }
            return "Closes **\(gate.step.displayName)** and opens **\(nextName)**. "
                + "Spends **1 of the \(weeks.left) scouting weeks** left in the spring."
        }()

        return DSActionBar(
            explainer: DSActionBar.Explainer(
                title: "Advance \u{2014} \(nextName)",
                message: message,
                isWarning: gate.isPhaseBlocked
            ),
            // THE HUB'S ONE SKIP. Every stage is skippable and none of them is
            // silently skippable, so the ghost says what walking past costs. The
            // in-surface skips (the pro-day tour's "or watch it on the feed", the
            // workout room's "done with the workouts") stay where they are —
            // those are their screens' own flow, and for the tour the transition
            // is destructive and lives behind that screen's confirmation.
            // NAMED, NOT DEICTIC. "Skip this stage" is only unambiguous while the
            // stage it means is the subject of the screen, and an irreversible
            // control cannot rest on that: the a11y label has always spelled the
            // name out, so the visible title says the same words rather than
            // telling sighted users less than VoiceOver users.
            ghost: gate.offersHeaderSkip && gate.next != nil
                ? DSActionBar.Action(
                    title: "Skip \(gate.step.displayName)",
                    caption: gate.skipCost,
                    accessibilityLabel: "Skip \(gate.step.displayName). \(gate.skipCost)",
                    handler: { if let next = gate.next { advance(to: next) } }
                )
                : nil,
            primary: DSActionBar.Action(
                title: gate.next == nil ? "The board is closed" : "Advance \u{2014} \(nextName)",
                isEnabled: canCommit && gate.next != nil,
                handler: { if let next = gate.next { advance(to: next) } }
            )
        )
    }

    // MARK: - Position Filter Chips (shared by Big Board / Prospects / Combine)

    /// The shared control, not a fourth copy of it.
    ///
    /// This used to be ~40 lines of chip drawing identical to
    /// `ProspectPositionChips` in `ProspectListControls.swift` — which was
    /// EXTRACTED FROM THIS PROPERTY so the pro-day and workout lists could wear
    /// the same row, and then left behind here. Two definitions of one control
    /// is how the hub ended up with three position filters in the first place.
    private var positionFilterChips: some View {
        ProspectPositionChips(selection: $positionFilter)
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

    /// Every stage screen's "may I act" is `DraftPrepProgress.canAct`, the same
    /// predicate the band draws its `.open` slat from — so a slat that invites a
    /// tap can never land on a screen whose buttons are dead. The value is the
    /// hub's one per-pass `DraftPrepProgress`, handed down rather than rebuilt.
    @ViewBuilder
    private func tabContent(progress: DraftPrepProgress) -> some View {
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
                // #142: the shared chip row belongs on the table here, under the
                // board's own strip, not above it. See `hostsPositionFilterChips`.
                hostsPositionChips: true,
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
                // #3424 — a door back into the report. It was raised once, from
                // inside `sendScoutsToCombine`, and could not be reopened; the
                // one thing it could not say at that moment was what the week
                // did to a Stock Faller's projected round, because the drift
                // that moves it fires when the club LEAVES the phase. Offered
                // whenever `combineMedia` has something in it — `loadData`
                // rebuilds it from what is stamped on the class, so this
                // survives a relaunch and outlives the phase.
                onOpenReport: combineMedia.isEmpty
                    ? nil
                    : { activeHubSheet = .combineReport },
                // The gate the CTA was missing: `applyCombineScouting` refuses
                // on an empty scout list, so at 0/8 seats the trip charges the
                // flight and files nothing.
                scoutCount: scouts.count,
                onHireScouts: { selectedTab = .scouts },
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
                // #137: the same row hand-off the Big Board has. One gate, the
                // hub's, applied identically wherever the menu is drawn.
                onInterview: interviewJump(progress),
                header: { EmptyView() }
            )
        case .interviews:
            InterviewSelectionView(
                career: career,
                canAct: progress.canAct(.interviews),
                focusProspectID: interviewFocusProspectID
            )
        case .mockDraft:
            MockDraftView(
                career: career,
                prospects: prospects,
                onInterview: interviewJump(progress),
                filing: mockFiling(progress)
            )
        case .draftOrder:
            // THE "NEXT YR" TOOL LIVES HERE NOW (#164). It was a sixth entry in
            // the Tools menu holding one screen — an early look at next year's
            // class — and that is not a tool, it is the *other year* of the one
            // question this surface already answers: what am I holding, and who
            // is coming. The horizon segment inside `DraftOrderView` picks the
            // year; `NEXT YEAR` draws next year's picks plus the early look.
            DraftOrderView(career: career, nextYearProspects: nextYearProspects)
        case .workouts:
            WorkoutsTabView(
                career: career,
                prospects: prospects,
                teamRoster: teamPlayers,
                positionFilter: $positionFilter,
                canAct: progress.canAct(.workouts),
                onRefresh: loadData,
                onInterview: interviewJump(progress)
            )
        case .top30:
            Top30VisitsView(
                career: career,
                scouts: scouts,
                prospects: prospects,
                teamRoster: teamPlayers,
                canAct: progress.canAct(.top30Visits),
                onRefresh: loadData,
                onInterview: interviewJump(progress)
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
        case .scoutNotes:
            // #174. The two blocks that used to be pinned above the Big Board's
            // 350 rows. They are DERIVED READS over the board, not the board, so
            // they get their own surface rather than the top third of the one
            // screen that is always true. `ScoutBoardReads` is the single walk
            // both this and the board's NEED chips are computed from — one
            // answer, so the notes and the rows can never disagree.
            ScoutNotesView(
                career: career,
                prospects: prospects,
                teamRoster: teamPlayers,
                onSwitchTab: { selectedTab = $0 },
                onInterview: interviewJump(progress)
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
                    // Born stamped (#145). `persistDraftClass` stamps
                    // `WeekAdvancer.activeCareerID` on the way into the store,
                    // which is a process static this heal path does not set and
                    // cannot see — every other generation site in the build
                    // passes the id it is holding, and a heal that ran against a
                    // stale static would hand this save's class to another
                    // career's `careerID` predicate.
                    WeekAdvancer.currentDraftClass = ScoutingEngine.generateDraftClass(careerID: career.id)
                    WeekAdvancer.draftClassGenerated = true
                    // The pre-scout freebie is a FIRST-SEASON inheritance: the
                    // previous regime's paper on the top ~250 of the class the
                    // user walks in on. This call was ungated under a comment
                    // that promised the gate, so a save that lost its class in
                    // year six — the very saves this branch exists to heal —
                    // regenerated it with a third of the board already scouted,
                    // free, by a staff that had not worked here for five years.
                    // Same test `WeekAdvancer` applies at the real call sites.
                    let isFirstSeason = career.totalWins == 0 && career.totalLosses == 0
                    if isFirstSeason {
                        ScoutingEngine.applyPreScoutedData(prospects: &WeekAdvancer.currentDraftClass)
                    }
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
    /// The class behind the names, so a mention is a route rather than a
    /// dead end. Every other list in the hub opens a prospect card on tap; this
    /// one named ten men in prose and offered `Done`.
    let career: Career
    let prospects: [CollegeProspect]
    /// Whether THIS club sent its department to Indianapolis.
    ///
    /// The report is a PUBLIC document and the sheet is offered either way:
    /// `generateCombineMedia` stamps the mentions inside `runLeagueCombine`,
    /// which holds the event for every club whether or not one bought the trip.
    /// The headlines, the projected rounds and the board slots below are all
    /// true for a club that watched it on television.
    ///
    /// The FILING is not public. `applyCombineScouting` — the fresh report, the
    /// narrower band, the updated letter — runs only inside
    /// `sendScoutsToCombine`, so the closing line claims work that a
    /// non-attending club never bought. Before the reopen door shipped the
    /// sheet was unreachable in that state and the claim could not be read;
    /// now it is one tap from the Combine tab, so it has to know which club it
    /// is talking to.
    let scoutsAttended: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let categories = ["Standout", "Stock Riser", "Stock Faller", "Surprise"]

    /// The user's own board slot per prospect, built ONCE for the sheet.
    ///
    /// `UserDraftBoard.slotMap` is the same "MY #N" the Big Board, the Mock
    /// Draft and the war room print, so a name in this report carries the slot
    /// the user will see when he goes and looks at it. Rebuilt per body pass it
    /// would walk the whole class for each of ten rows.
    private var boardSlots: [UUID: Int] { UserDraftBoard.slotMap(among: prospects) }

    private func mentionsFor(_ category: String) -> [ScoutingEngine.CombineMediaMention] {
        mentions.filter { $0.category == category }
    }

    /// The man a mention is about. A linear scan over ~350 for ten rows — a
    /// dictionary rebuilt per body pass would cost more than it saves.
    private func prospect(for mention: ScoutingEngine.CombineMediaMention) -> CollegeProspect? {
        prospects.first { $0.id == mention.prospectID }
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
                    // THE COUNT, NOT A SECOND TITLE. The hero here was a 40 pt
                    // "COMBINE REPORT" under a newspaper glyph, directly beneath
                    // a nav bar already reading Combine Report — ~230 pt of a
                    // sheet whose entire content is ten short lines, four of
                    // which reached the fold because of it.
                    Section {
                        Text("\(mentions.count) notable performances")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .listRowBackground(Color.clear)

                    ForEach(categories, id: \.self) { category in
                        let items = mentionsFor(category)
                        if !items.isEmpty {
                            Section {
                                ForEach(items, id: \.prospectID) { mention in
                                    // A man who is worth a headline is worth
                                    // opening. The fallback row is for a mention
                                    // the class no longer holds — a name with no
                                    // card behind it must not draw a chevron.
                                    if let prospect = prospect(for: mention) {
                                        NavigationLink(destination: ProspectDetailView(career: career, prospect: prospect)) {
                                            mentionRow(mention)
                                        }
                                        // THE INLINE ACT. The report named ten
                                        // men and the only thing a reader could
                                        // do about any of them was push into a
                                        // card and come back. The mark is the
                                        // one control every other prospect
                                        // surface puts on a row, and it is the
                                        // thing this sheet is for: you read
                                        // that he ran a 4.38, you put him on
                                        // your board, you carry on reading.
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            markSwipeButton(for: prospect)
                                        }
                                        .contextMenu {
                                            ProspectGradeContextMenu(
                                                prospect: prospect,
                                                onChange: { try? modelContext.save() }
                                            )
                                        }
                                    } else {
                                        mentionRow(mention)
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

                    // THE CLOSING LINE. The reports were filed and the board
                    // was rewritten BEFORE this sheet was raised
                    // (`applyCombineScouting` runs inside `sendScoutsToCombine`,
                    // the sheet is set on the line after), and nothing said so —
                    // so the one screen that proves the money bought something
                    // ended on a headline and a Done button, and a reader could
                    // reasonably close it believing he still had work to do.
                    Section {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: scoutsAttended ? "checkmark.seal.fill" : "tv")
                                .font(.caption)
                                .foregroundStyle(scoutsAttended ? Color.success : Color.textTertiary)
                            // Precise about WHAT was written. `applyCombineScouting`
                            // files a `.combine` report on every man the board
                            // tracks, which narrows his band and moves his
                            // grade; the media board's projected rounds are
                            // moved later, by the drift pass at the end of the
                            // phase. Claiming both here would be a promise the
                            // next screen contradicts.
                            //
                            // And precise about WHOSE board. See
                            // `scoutsAttended`: nothing above this line is
                            // gated on the trip, so the report is worth
                            // reading either way — but a club that stayed
                            // home has no fresh report, no narrower band and
                            // no new letter, and telling it "nothing here is
                            // waiting on you" would close the one screen that
                            // could still sell it the trip.
                            closingLine
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // #3424. The arrows only exist on a REOPENED report —
                        // the media board moves when the club leaves the
                        // combine, so during the week there is nothing to
                        // print — and this says precisely what they measure.
                        // The combine's drift and the mock re-read that follows
                        // it both land at that transition, so the honest claim
                        // is "the board has moved him", not "the drills did".
                        if hasProjectionMoves {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "arrow.left.arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentGold)
                                Text("An arrow on a round is where the media board had him when the combine opened against where it has him now. It is the board's move, not a grade of yours.")
                                    .font(.caption)
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            // The consensus board is a per-session cache and the row below
            // quotes the mock slot off it. Publishing it here means this sheet
            // answers the same as the Big Board whether or not the user has
            // opened that tab yet; the population is normalised inside, so
            // republishing it cannot narrow anyone else's board.
            .task { DraftIntel.refreshConsensusBoard(for: prospects) }
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

    /// What this club got out of the week, in one line.
    ///
    /// A `Text` rather than a `String`, and two whole literals rather than one
    /// interpolated: only a literal reaching `Text(LocalizedStringKey)` is
    /// extracted for translation, which is the same reason
    /// `CombineResultsView.sendScoutsSubtitle` is shaped this way.
    private var closingLine: Text {
        if scoutsAttended {
            return Text("These results are already on your Big Board \u{2014} every man you track has a fresh report, a narrower grade band and an updated letter. Nothing here is waiting on you.")
        }
        return Text("Your department stayed home, so nothing here was filed on your Big Board \u{2014} no new report, no narrower band, no new letter. These are the televised numbers and what the media made of them.")
    }

    /// The one row action: put him on the board, or take him off it.
    ///
    /// A full mark menu does not fit a swipe, and `ProspectGradeContextMenu` is
    /// already wired into the long-press for the men who want a tier. The swipe
    /// is the fast path — the same `.target` mark the Big Board's star writes.
    @ViewBuilder
    private func markSwipeButton(for prospect: CollegeProspect) -> some View {
        let isMarked = prospect.isMarked
        Button {
            // `setUserMark`, never a raw write to `userMarkTier`: it is what
            // mirrors the verdict onto `prospectFlag` and the star store, so a
            // mark made here is a mark the board and the war room can see.
            prospect.setUserMark(isMarked ? .none : .target)
            try? modelContext.save()
        } label: {
            Label(
                isMarked ? "Unmark" : "Mark",
                systemImage: isMarked ? "bookmark.slash.fill" : "bookmark.fill"
            )
        }
        .tint(isMarked ? Color.textTertiary : Color.accentGold)
    }

    /// The row: who he is, what was said, and WHERE HE SITS.
    ///
    /// It printed a position chip, a name and a headline — "Andre Bryant posts
    /// elite combine numbers across the board" — and nothing that answers the
    /// only question a GM has while reading it: does this man matter at my
    /// pick? Three facts close that, and all three are already loaded:
    ///
    /// * the club's own grade band, through the fog (`ScoutBoardReads
    ///   .gradeText`), so it prints "—" for a man nobody in the building has
    ///   filed on rather than inventing a letter for him;
    /// * the media's projected round, the public half;
    /// * the user's OWN board slot, off `UserDraftBoard.slotMap` — the same
    ///   number every other surface prints for him.
    private func mentionRow(_ mention: ScoutingEngine.CombineMediaMention) -> some View {
        // Named `matched` rather than `prospect`: a local of that name would
        // shadow the `prospect(for:)` lookup on the very line that calls it.
        let matched = prospect(for: mention)
        return HStack(spacing: 12) {
            Text(mention.position)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 32, height: 22)
                .background(Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DSCornerRadius.tight))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mention.prospectName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                    if let matched, matched.isMarked {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: DSType.Size.micro))
                            .foregroundStyle(Color.accentGold)
                    }
                }
                Text(mention.headline)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(2)
                if let matched {
                    contextLine(for: matched)
                }
            }
        }
    }

    /// Grade · projected round · your board slot · latest mock, in one line.
    ///
    /// The last two are what tie a headline to a DECISION. A riser is only news
    /// if he is a man you had at #7 and the mock now has going at #12; the
    /// report used to name him and leave the reader to go and look both numbers
    /// up on two other screens. `UserDraftBoard.slotMap` is the same "MY #N"
    /// every other surface prints, and `DraftIntel.consensusRank` is the market
    /// slot the board's VAL chip and the availability curve already read — so
    /// nothing here is a fifth opinion about the same man.
    private func contextLine(for prospect: CollegeProspect) -> some View {
        // Text off `ScoutBoardReads.gradeText` — the shared reader, so a man
        // nobody has filed on prints "—" here exactly as he does on Scout Notes
        // — and the TINT off the band's midpoint rather than off the string. A
        // band renders as "B-/A-", and colouring a string by its first letter
        // would tint that whole read by its worst end.
        let read = ProspectFog.read(prospect)
        let grade = ScoutBoardReads.gradeText(prospect)
        let gradeTint = read.band.map { Color.forGrade($0) } ?? Color.textTertiary
        let move = projectionMove(for: prospect)
        let round = prospect.draftProjection.map { "Rd \($0)" } ?? "\u{2014}"
        let slot = boardSlots[prospect.id].map { "your #\($0)" } ?? "not on your board"
        let mock = DraftIntel.consensusRank(for: prospect.id).map { "mock #\($0)" }
        return HStack(spacing: 5) {
            Text(grade)
                .font(.system(size: DSType.Size.caption, weight: .heavy))
                .foregroundStyle(grade == "\u{2014}" ? Color.textTertiary : gradeTint)
            contextDivider
            // #3424 — a Stock Faller row named a man and left his projection
            // alone, so the one number the headline was about was the one the
            // reader had to go and look up. When the board HAS moved him since
            // the combine opened, the cell prints the move rather than the
            // destination.
            if let move {
                Text("Rd \(move.from) \u{2192} Rd \(move.to)")
                    .font(.system(size: DSType.Size.caption, weight: .bold).monospacedDigit())
                    // A LOWER round number is better, so a fall is a rise in
                    // the integer — same direction test `ProjectionMove.isRise`
                    // makes.
                    .foregroundStyle(move.to < move.from ? Color.success : Color.danger)
            } else {
                Text(round)
                    .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
            }
            contextDivider
            Text(slot)
                .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                .foregroundStyle(Color.accentBlue)
            if let mock {
                contextDivider
                Text(mock)
                    .font(.system(size: DSType.Size.caption, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    /// Where the media had him when the combine opened, and where they have him
    /// now — `nil` while the two are the same, or before the snapshot exists.
    ///
    /// The pair is `preCombineProjection` (stamped at combine ENTRY, beside
    /// `preCombineGrade`, by `ScoutingEngine.runLeagueCombine`) against the
    /// live `draftProjection`. Both ends are numbers the simulation actually
    /// holds; nothing here is computed from a coefficient.
    ///
    /// It is a MOVE ON THE MEDIA BOARD SINCE THE COMBINE OPENED, which is what
    /// the footnote calls it, and deliberately not "what the combine cost him":
    /// the combine's own drift pass and the post-combine mock re-read both run
    /// when the club leaves the phase. Attributing the whole of it to the
    /// drills would be a claim the engine does not support.
    ///
    /// WINDOWED, because past a point that hedge stops being enough. The delta
    /// is only honest while everything inside it happened at the combine's
    /// departure — see `deltaIsStillTheCombine`.
    private func projectionMove(for prospect: CollegeProspect) -> (from: Int, to: Int)? {
        guard deltaIsStillTheCombine,
              let from = prospect.preCombineProjection,
              let to = prospect.draftProjection,
              from != to
        else { return nil }
        return (from, to)
    }

    /// Whether `preCombineProjection` → `draftProjection` is still a statement
    /// about the combine.
    ///
    /// `preCombineProjection` is stamped once, at combine ENTRY, and never
    /// restamped; `draftProjection` is then moved by six separate passes. Two
    /// of them fire as the club leaves `.combine` — the combine drift itself
    /// (`WeekAdvancer` at the `.combine` hook, maxShift 2) and the post-combine
    /// mock re-read (drift moment 2) — and those are the combine's own
    /// departure, which is what the footnote describes.
    ///
    /// The other four fire on ENTERING `.proDays` or later: the pro-day
    /// circuit's drift, mock moments 3 and 4, and `applyPreDraftAttrition`,
    /// which knocks a man down as many as three rounds for a spring injury. A
    /// report reopened from there prints a torn hamstring as a "Stock Faller"
    /// arrow in a sheet titled Combine Report — a number the reader would
    /// reasonably attribute to the drills, which is precisely the invented
    /// figure this cell exists to replace.
    ///
    /// So the arrow is drawn while it means what it says and withheld after,
    /// where the row falls back to the live projected round — a fact that is
    /// true in every phase. The whole delta is not recoverable here: that needs
    /// the combine drift's own `[ProjectionMove]` persisted at the phase
    /// transition, which is engine work (#3424).
    private var deltaIsStillTheCombine: Bool {
        switch career.currentPhase {
        case .combine, .freeAgency: return true
        default:                    return false
        }
    }

    /// True once at least one man on the report has moved — the footnote is
    /// drawn only then, so a report opened during the combine (when nothing has
    /// drifted yet) does not explain an arrow it is not showing.
    private var hasProjectionMoves: Bool {
        mentions.contains { mention in
            prospect(for: mention).flatMap { projectionMove(for: $0) } != nil
        }
    }

    private var contextDivider: some View {
        Text(verbatim: "\u{00B7}")
            .font(.system(size: DSType.Size.caption))
            .foregroundStyle(Color.textTertiary)
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
    /// What the department makes of the board (#174): the club's #1 hole, the
    /// best man on it, the best man anywhere, the depth behind each need, and
    /// where your #1 sits against the market. Derived reads, not the board —
    /// they were two unconditional blocks pinned above 350 rows, so the first
    /// prospect started below the fold on the one surface that is always true.
    case scoutNotes = "scoutNotes"
    case combine    = "combine"
    case film       = "film"
    case interviews = "interviews"
    case proDays    = "proDays"
    case workouts   = "workouts"
    case mockDraft  = "mockDraft"
    case top30      = "top30"
    case draftOrder = "draftOrder"
    case scouts     = "scouts"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .board:      return "Big Board"
        case .classDepth: return "Class Depth"
        case .scoutNotes: return "Scout Notes"
        case .combine:    return "Combine"
        case .film:       return "Film Study"
        case .interviews: return "Interviews"
        case .proDays:    return "Pro Days"
        case .workouts:   return "Workouts"
        case .mockDraft:  return "Mock Draft"
        case .top30:      return "Top-30"
        case .draftOrder: return "Draft Order"
        case .scouts:     return "Scout Team"
        }
    }

    var icon: String {
        switch self {
        case .board:      return "list.number"
        case .classDepth: return "chart.bar.fill"
        case .scoutNotes: return "note.text"
        case .combine:    return "figure.run"
        case .film:       return "film"
        case .interviews: return "bubble.left.and.bubble.right"
        case .proDays:    return "mappin.and.ellipse"
        case .workouts:   return "figure.strengthtraining.traditional"
        case .mockDraft:  return "doc.text"
        case .top30:      return "building.2"
        case .draftOrder: return "number.circle"
        case .scouts:     return "binoculars"
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
        case .board, .classDepth, .scoutNotes, .mockDraft, .draftOrder, .scouts:
            return nil
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
                            .font(.system(size: DSType.Size.hero))
                            .foregroundStyle(Color.textTertiary)
                        Text("Scout Staff Full")
                            .font(.system(size: DSType.Size.title2, weight: .bold))
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
