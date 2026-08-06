import Foundation
import SwiftData

/// Stateless engine responsible for advancing game state by one week,
/// simulating games, and managing season/phase transitions.
enum WeekAdvancer {

    // MARK: - Season Calendar

    /// The regular-season week the trade deadline falls on. Real NFL: the
    /// Tuesday after the week-9 games, i.e. just past the halfway mark of an
    /// 18-week season — the previous week 8 cut the market off too early
    /// (trade plan finding S2).
    ///
    /// This is the calendar authority: `.tradeDeadline` is the career's phase for
    /// the WHOLE of this week (set at the end of the previous advance, restored to
    /// `.regularSeason` once the deadline passes at the end of it), so the tasks,
    /// inbox letters and dashboard tile written for that phase are finally
    /// reachable. `TradeValueEngine.deadlineWeek` is the *window* rule
    /// (`isTradeWindowOpen`); reading it here keeps the calendar and the window
    /// on one authority — they drifted apart once already (8 vs 9) during the
    /// Wave 1 merge.
    static let tradeDeadlineWeek = TradeValueEngine.deadlineWeek

    /// The result of the last player team game simulation (available after advanceWeek)
    static var lastPlayerGameResult: GameSimulator.GameResult?

    /// Teams whose weekly injury roll is skipped on the next advance because
    /// their game was played live: `LiveGameEngine` already rolled per-play
    /// injury dice for both sides at the same aggregate probability, so
    /// rolling again here would double the live coach's injury rate.
    /// Set by `LiveGameEngine.persist`, cleared at the end of `advanceWeek`.
    static var liveGameInjuryTeamIDs: Set<UUID> = []

    // MARK: - Static Storage for UI Access

    /// News items generated during the most recent advance.
    static var lastNewsItems: [NewsItem] = []

    /// Game events generated during the most recent advance.
    static var lastEvents: [GameEvent] = []

    /// Inbox messages generated during the most recent phase transition.
    static var lastInboxMessages: [InboxMessage] = []

    /// Set to `true` when the owner fires the player after a satisfaction check.
    static var wasFired: Bool = false

    /// Press questions generated after the player's game, pending UI presentation.
    static var pendingPressConference: [PressQuestion]?

    /// Tracks whether a draft class has been generated for the current offseason cycle.
    static var draftClassGenerated: Bool = false

    /// The current draft class of college prospects (persists across offseason phases).
    static var currentDraftClass: [CollegeProspect] = []

    /// Draft picks generated for the current draft.
    static var currentDraftPicks: [DraftPick] = []

    /// Latest mock draft projection (generated at midseason, combine, and pre-draft).
    static var currentMockDraft: [ScoutingEngine.MockDraftPick] = []

    /// R24: seasons whose UDFA signing was already handled interactively at
    /// the end of Draft Day — the OTAs bulk-signing fallback must skip these.
    static var udfaStageCompletedSeasons: Set<Int> = []

    /// Wave 0 trade instrumentation (`docs/TRADE_OVERHAUL_PLAN.md` §6): how many
    /// AI-initiated weekly trade offers have actually reached the user's inbox
    /// since this process started.
    ///
    /// WHY a counter and not a `TradeRecord`: the ledger records EXECUTED
    /// trades, but the §5 band "AI offers reaching the user: 3-8/season" is
    /// about the phone ringing, accepted or not — and a headless harness never
    /// accepts anything. `career.pendingTradeOffers` cannot stand in for it:
    /// it is capped at 5, de-duplicated per team, and wiped at the deadline, so
    /// by season end it always reads 0. Monotonic; the smoke harness diffs it
    /// per season and resets it with the other statics at bootstrap.
    static var aiTradeOffersGenerated: Int = 0

    /// Of `aiTradeOffersGenerated`, how many arrived in an OFFSEASON window.
    /// Also monotonic: §5 bands the two halves of the league year separately
    /// (3-8 in-season + 2-5 offseason), so the smoke diff needs both totals to
    /// separate them. Wave 2.
    static var aiTradeOffersOffseasonGenerated: Int = 0

    /// In-season AI offers that have reached the user THIS season. Drives the
    /// hazard ramp's cap and pity floor (`TradeValueEngine.userOfferHazard`);
    /// reset in `startNewSeason`.
    static var aiOffersThisSeason: Int = 0

    /// AI offers that have reached the user in the CURRENT offseason cycle.
    /// Reset in `startNewSeason`, which fires immediately after the offseason
    /// ends — so between two kickoffs this counter sees exactly one offseason.
    static var aiOffersThisOffseason: Int = 0

    /// AI-vs-AI league trades completed this season between kickoff and the
    /// deadline. Feeds the deadline-week catch-up (a quiet October makes deadline
    /// day louder, which is also what the real league does) and the §5 in-season
    /// ceiling. Wave 2.
    static var leagueTradesThisSeason: Int = 0

    /// AI-vs-AI league trades completed in the current offseason cycle — the
    /// per-window catch-up and the §5 offseason ceiling read it.
    static var leagueTradesThisOffseason: Int = 0

    /// §5 ceilings, enforced here rather than inside the market so the bands are
    /// visible next to the calendar they apply to: 8-25 in-season player trades
    /// league-wide, 15-40 across the offseason.
    static let maxLeagueTradesInSeason = 24
    static let maxLeagueTradesOffseason = 38

    /// Historical mock draft snapshots, keyed by phase tag: `"Mid-Season"`,
    /// `"Combine"`, `"Post-Pro-Day"`, `"Pre-Draft"`. Each value is a copy of
    /// `currentMockDraft` taken right after that phase's mock was generated.
    ///
    /// Write through `recordMockDraftSnapshot` and never directly: since #103
    /// this dictionary is mirrored onto `Career.mockDraftHistoryData`, so a
    /// bare assignment here would be a snapshot that dies with the process and
    /// a `MockDraftView` that disagrees with itself after a relaunch.
    static var mockDraftHistory: [String: [ScoutingEngine.MockDraftPick]] = [:]

    /// `"season-phase"` keys the draft-cycle heartbeat has already been mailed
    /// for (task #78, finding S9). The offseason phase hooks can be re-entered —
    /// a save reloaded on a phase boundary runs them again — and a heartbeat is
    /// a note, not an event, so it must not stack duplicates in the inbox.
    static var draftCycleHeartbeatsSent: Set<String> = []

    // MARK: - Career switch reset

    /// The save this engine is currently bound to. **Every store-wide fetch in
    /// this file filters on it**, so two careers in one SwiftData store never
    /// see each other's teams, players, games or picks.
    ///
    /// `nil` means "not bound" — the scoped fetches then match only rows whose
    /// `careerID` is also `nil`, i.e. they come back empty. That is deliberate:
    /// an unbound engine doing nothing is a visible bug, an unbound engine
    /// simulating every career at once is a silent one.
    private(set) static var activeCareerID: UUID?

    /// Binds the engine to `career`. Switching saves also empties the
    /// process-global caches that belonged to the save being left.
    static func bind(to career: Career) {
        guard activeCareerID != career.id else { return }
        resetProcessStateForCareerSwitch()
        activeCareerID = career.id
    }

    /// Every static above is PROCESS-global, so without this a career switch
    /// (or a second `New Career` in the same launch) carried save A's draft
    /// class, UDFA completion set, trade-volume caps and `wasFired` flag into
    /// save B. Call on every career open and on career creation.
    ///
    /// This is the same reset `MultiSeasonSmokeTest` has always run at
    /// bootstrap — hoisted here so the app and the harness share one list and a
    /// newly added static cannot be reset in one place and forgotten in the other.
    static func resetProcessStateForCareerSwitch() {
        activeCareerID = nil
        lastPlayerGameResult = nil
        liveGameInjuryTeamIDs = []
        lastNewsItems = []
        lastEvents = []
        lastInboxMessages = []
        wasFired = false
        pendingPressConference = nil

        currentDraftClass = []
        currentDraftPicks = []
        currentMockDraft = []
        mockDraftHistory = [:]
        draftClassGenerated = false
        udfaStageCompletedSeasons = []
        draftCycleHeartbeatsSent = []
        // The published media board is process-global too — one more cache that
        // belonged to the save being left.
        DraftIntel.resetProcessState()

        // Trade counters: the monotonic pair the per-season diff reads, plus the
        // per-cycle pair `startNewSeason` maintains (season 1 never calls it, so a
        // second career in the same process would inherit the first one's totals
        // and start with the market's volume caps already spent).
        aiTradeOffersGenerated = 0
        aiTradeOffersOffseasonGenerated = 0
        aiOffersThisSeason = 0
        aiOffersThisOffseason = 0
        leagueTradesThisSeason = 0
        leagueTradesThisOffseason = 0
        TradeValueEngine.TradeTalkRegistry.reset()
        TradeValueEngine.funnel = TradeValueEngine.MarketFunnel()

        // Per-career ledgers held outside SwiftData — keyed by player/team ids
        // that only mean something inside one save.
        TrainingFocusEngine.resetProcessState()
        CompensatoryPickEngine.resetProcessState()
        NegotiationLockRegistry.reset()
        FASigningTracker.reset()
        // §5.1: the practice-squad poach warnings the user has open are keyed
        // by player id, so another save's window must not be inherited.
        PracticeSquadEngine.reset()
        PerfLog.resetProcessState()
    }

    // MARK: - Draft Class Persistence

    /// Inserts every prospect of the current draft class into the SwiftData
    /// context and persists the change. Safe to call repeatedly — `insert`
    /// is idempotent for managed instances and will register fresh ones so
    /// subsequent `save()` calls flush their property changes too.
    /// Re-seeds `currentDraftClass` from SwiftData when the process has lost it.
    ///
    /// **This is what stops the class being generated twice.** `currentDraftClass`
    /// and `draftClassGenerated` are process statics: they are correct for as long
    /// as the app stays alive, and empty the moment it is relaunched. Both
    /// generation sites are guarded by `!draftClassGenerated` only — so a cold
    /// launch anywhere between the week-9 generation and the draft itself would
    /// take that branch again and `persistDraftClass` would INSERT a second full
    /// class (it inserts, it never replaces). The save then carried ~700 prospect
    /// rows for one career, and every scouting report filed on the first class
    /// was stranded on rows no screen showed again — nothing deletes them until
    /// `purgeStaleSeasonData` a whole year later.
    ///
    /// Two screens already did this restore for themselves (`ScoutingHubView`,
    /// `DraftDayCoordinator`), which is exactly why the bug only showed up when
    /// the user advanced the calendar without opening either of them first.
    /// Hoisted here and called from `advanceWeek`, so the engine can no longer
    /// depend on a particular screen having been visited.
    ///
    /// Safe at any point in the calendar: prospect rows are purged wholesale at
    /// every season rollover (`startNewSeason` → `purgeStaleSeasonData`), so any
    /// row that exists belongs to the cycle currently in flight.
    ///
    /// - Returns: `true` when a class was restored from the store.
    @discardableResult
    @MainActor
    static func restoreDraftClassIfNeeded(career: Career, modelContext: ModelContext) -> Bool {
        guard !draftClassGenerated, currentDraftClass.isEmpty else { return false }
        let cid = career.id
        let stored = (try? modelContext.fetch(FetchDescriptor<CollegeProspect>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        guard !stored.isEmpty else { return false }
        currentDraftClass = stored
        draftClassGenerated = true
        return true
    }

    @MainActor
    static func persistDraftClass(_ prospects: [CollegeProspect], to context: ModelContext) {
        for prospect in prospects {
            prospect.careerID = activeCareerID
            context.insert(prospect)
        }
        try? context.save()
    }

    /// Writes `declarationStatusRaw` onto a class that went through the January
    /// window before the field existed (finding C5).
    ///
    /// Idempotent and free after the first call — `backfillDeclarationStatus`
    /// only touches rows whose status string is empty, and only for a class
    /// whose window has demonstrably closed.
    @MainActor
    static func healDeclarationStatus(career: Career, modelContext: ModelContext) {
        var klass = currentDraftClass
        let fromMemory = !klass.isEmpty
        if !fromMemory {
            let cid = activeCareerID
            klass = (try? modelContext.fetch(FetchDescriptor<CollegeProspect>(
                predicate: #Predicate { $0.careerID == cid }
            ))) ?? []
        }
        guard !klass.isEmpty else { return }
        guard ScoutingEngine.backfillDeclarationStatus(&klass) > 0 else { return }
        if fromMemory { currentDraftClass = klass }
        try? modelContext.save()
    }

    // MARK: - NFL Combine

    /// Phases in which a draft class exists and the combine has already been
    /// held (or is being held right now). Outside this window there is nothing
    /// to run: before it the class may not exist, after it the prospects have
    /// become players.
    private static let combineResultPhases: Set<SeasonPhase> = [
        .combine, .freeAgency, .proDays, .draft
    ]

    /// Makes sure the current draft class has been through the combine.
    ///
    /// The combine used to be generated by exactly one thing: the user pressing
    /// "Send Scouts to Combine" in the scouting hub, behind a
    /// `currentPhase == .combine` gate. Two ways to miss it, both permanent:
    /// advance past the phase without pressing it (the button is gone and
    /// nothing else ever writes a forty time), or reach season 2, where the
    /// career-scoped `scoutsSentToCombine` flag was still `true` from season 1
    /// so the button was replaced by a "results are in" banner for a class that
    /// had no results at all. Either way the Combine tab is empty for the rest
    /// of the cycle and there is no way back.
    ///
    /// Called from the phase transition (so it happens on schedule) and from the
    /// scouting hub's load (so a save already stuck past the combine heals the
    /// next time the user opens the screen). Idempotent — a class that has
    /// results is left exactly as it is.
    ///
    /// - Returns: `true` when this call ran the event.
    @discardableResult
    static func ensureCombineRun(career: Career, modelContext: ModelContext) -> Bool {
        guard combineResultPhases.contains(career.currentPhase) else { return false }
        guard !currentDraftClass.isEmpty else { return false }
        guard !currentDraftClass.contains(where: { $0.fortyTime != nil }) else { return false }

        // The drill-grade noise the class is evaluated under is your building's
        // read of it, so it scales with the staff doing the reading.
        let scoutingAbility: Int = {
            guard let teamID = career.teamID else { return 50 }
            let staff = (try? modelContext.fetch(FetchDescriptor<Coach>(
                predicate: #Predicate { $0.teamID == teamID }
            ))) ?? []
            guard !staff.isEmpty else { return 50 }
            return staff.reduce(0) { $0 + $1.scoutingAbility } / staff.count
        }()

        var klass = currentDraftClass
        guard ScoutingEngine.runLeagueCombine(
            prospects: &klass,
            scoutingAbility: scoutingAbility
        ) else { return false }

        currentDraftClass = klass
        persistDraftClass(klass, to: modelContext)
        return true
    }

    /// Opens a fresh combine window for the new cycle.
    ///
    /// These keys are career-scoped but NOT season-scoped, and nothing cleared
    /// them at rollover — which is why the send-scouts button never came back
    /// after season 1.
    ///
    /// `interviewReportReviewed` joined the list in #104 for the same reason,
    /// one stage further on: it was written once, in season 1, and never
    /// cleared, so from season 2 the REQUIRED "Review interview report" task
    /// auto-completed against a report for a draft class that no longer existed.
    /// Every key the prep reads is named in `DraftPrepProgress.Key`.
    private static func resetCombineWindow() {
        CareerScopedDefaults.set(false, DraftPrepProgress.Key.scoutsSentToCombine)
        CareerScopedDefaults.set(false, DraftPrepProgress.Key.combineResultsReviewed)
        CareerScopedDefaults.set(false, DraftPrepProgress.Key.interviewReportReviewed)
        CareerScopedDefaults.set(0, "combineTripSpend")
    }

    // MARK: - In-Flight Save Migration (plan §5)

    /// Regenerates a pre-overhaul draft class that is still sitting in an
    /// in-flight save.
    ///
    /// Classes stamped `generatorVersion < 2` came out of the old generator: the
    /// whole board compressed into a 60-69 overall band, QBs monopolising round 1,
    /// no `trueLearning` / `nflReadiness` / college-production data, and roughly
    /// three classes in ten with zero punters. None of that can be repaired in
    /// place, so a save that has **not yet run its draft** purges the class,
    /// regenerates it, and re-runs every cycle step the old class had already
    /// been through (pre-scout / combine / declarations / mock draft) so the
    /// board the user is looking at stays internally consistent — several of
    /// those steps belong to phases the migration can only fire *after*, and
    /// nothing else in the cycle would ever run them.
    /// Scouting progress on the old class is lost —
    /// acceptable, since the old class *is* the bug.
    ///
    /// If the draft already happened the prospects have become Players, so this
    /// deliberately does nothing. Prospects are purged wholesale at every season
    /// rollover (`purgeStaleSeasonData`), which makes this path short-lived by
    /// design.
    ///
    /// - Returns: `true` when a class was purged and regenerated.
    @discardableResult
    static func migrateLegacyDraftClassIfNeeded(
        career: Career,
        modelContext: ModelContext
    ) -> Bool {
        bind(to: career)
        // Field-level heal first, and OUTSIDE the version guard below: a class
        // can be current-generation and still be missing `declarationStatusRaw`,
        // because that field shipped after the generator version last moved.
        // Both screens that restore a class (`ScoutingHubView.loadData`,
        // `DraftDayCoordinator`) come through here, so this is the one hook.
        healDeclarationStatus(career: career, modelContext: modelContext)
        guard isBeforeThisCycleDraft(career: career, modelContext: modelContext) else {
            return false
        }

        // Prefer the in-memory cycle class; fall back to SwiftData for the
        // fresh-launch restore path, which has not populated it yet.
        var stored = currentDraftClass
        if stored.isEmpty {
            let cid = activeCareerID
            stored = (try? modelContext.fetch(FetchDescriptor<CollegeProspect>(
                predicate: #Predicate { $0.careerID == cid }
            ))) ?? []
        }
        guard stored.contains(where: {
            $0.generatorVersion < DraftClassBuilder.currentGeneratorVersion
        }) else { return false }

        // Remember how far through the scouting cycle the old class had come so
        // the replacement can be brought to the same point.
        let hadCombineResults = stored.contains { $0.fortyTime != nil }
        let hadScoutedGrades = stored.contains { $0.scoutedOverall != nil }
        // The declaration period (`.coachingChanges`) and the mock draft
        // (week 9 / `.combine` / `.freeAgency`) are cycle steps, not scouting
        // depth — and neither `.proDays` nor `.draft` re-runs them, so a class
        // migrated in those phases would never get them at all.
        let hadDeclarationTrim = stored.contains { !$0.isDeclaringForDraft }
        let hadMockDraft = stored.contains { $0.mockDraftPickNumber != nil }

        // Purge every persisted prospect row, not just the in-memory ones — the
        // restore paths read the whole table.
        let migrationCareerID = activeCareerID
        let persisted = (try? modelContext.fetch(FetchDescriptor<CollegeProspect>(
            predicate: #Predicate { $0.careerID == migrationCareerID }
        ))) ?? []
        for prospect in persisted {
            modelContext.delete(prospect)
        }
        currentDraftClass = []
        currentMockDraft = []
        mockDraftHistory = [:]
        // #103: every snapshot in the persisted history points at prospect IDs
        // that are being deleted on the line above, so the blob dies with them.
        career.mockDraftHistoryData = nil
        draftClassGenerated = false

        var regenerated = ScoutingEngine.generateDraftClass(careerID: career.id)
        let isFirstSeason = career.totalWins == 0 && career.totalLosses == 0
        if isFirstSeason || hadScoutedGrades {
            ScoutingEngine.applyPreScoutedData(prospects: &regenerated)
        }
        if hadCombineResults {
            ScoutingEngine.generateCombineResults(for: &regenerated)
        }
        // Without this every regenerated prospect keeps `isDeclaringForDraft`'s
        // model default of `true`, so all 350 declare instead of ~250 — the
        // board, pro days, top-30 visits, the war-room pool and the UDFA market
        // are all filtered on it, and underclassmen who should have withdrawn
        // stay draftable for the rest of the cycle.
        if hadDeclarationTrim {
            _ = ScoutingEngine.generateDeclarations(
                prospects: &regenerated,
                seed: ScoutingEngine.cycleSeed(
                    careerID: career.id,
                    season: career.currentSeason,
                    salt: ScoutingEngine.CycleSalt.declarations
                )
            )
        }
        // The mock is the only thing that writes `mockDraftPickNumber` /
        // `teamInterest`; a regenerated class carries neither until it is
        // re-run, and after `.freeAgency` nothing ever re-runs it.
        if hadMockDraft {
            let cid = career.id
            let teams = (try? modelContext.fetch(FetchDescriptor<Team>(
                predicate: #Predicate { $0.careerID == cid }
            ))) ?? []
            let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>(
                predicate: #Predicate { $0.careerID == cid }
            ))) ?? []
            let season = career.currentSeason
            var picks = currentDraftPicks
            if picks.isEmpty {
                let descriptor = FetchDescriptor<DraftPick>(
                    predicate: #Predicate<DraftPick> { $0.careerID == cid && $0.seasonYear == season }
                )
                picks = (try? modelContext.fetch(descriptor)) ?? []
            }
            if !teams.isEmpty, !picks.isEmpty {
                currentMockDraft = ScoutingEngine.generateMockDraft(
                    prospects: regenerated,
                    draftPicks: picks,
                    teams: teams,
                    players: allPlayers
                )
                ScoutingEngine.updateTeamInterest(
                    prospects: &regenerated,
                    teams: teams,
                    players: allPlayers
                )
                ScoutingEngine.applyMockDraftToProspects(
                    prospects: &regenerated,
                    mockDraft: currentMockDraft
                )
            }
        }

        currentDraftClass = regenerated
        draftClassGenerated = true
        persistDraftClass(regenerated, to: modelContext)
        return true
    }

    /// `true` while the current offseason cycle's draft has not produced a single
    /// completed pick. Picks are stamped with `career.currentSeason`, which only
    /// advances when the next regular season starts, so the season filter scopes
    /// the check to this cycle.
    private static func isBeforeThisCycleDraft(
        career: Career,
        modelContext: ModelContext
    ) -> Bool {
        switch career.currentPhase {
        case .otas, .trainingCamp, .preseason, .rosterCuts:
            return false        // this cycle's draft is already behind us
        default:
            break
        }

        let season = career.currentSeason
        let cid = career.id
        var descriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate<DraftPick> {
                $0.careerID == cid && $0.seasonYear == season && $0.isComplete
            }
        )
        descriptor.fetchLimit = 1
        let completed = (try? modelContext.fetch(descriptor)) ?? []
        return completed.isEmpty
    }

    /// Seeds `Player.learning` on rows created before that property existed.
    ///
    /// Legacy players carry `Player.defaultLearning` (55), which would install
    /// schemes ~15 % slower than the awareness term they were tuned against. The
    /// seeded value comes from the SHARED `MentalAttributeModel.learning`
    /// (phase-2 plan §2.2) — the same 0.40/0.60 blend the draft class and the
    /// veteran generator use, so a backfilled row is indistinguishable from a
    /// generated one — with the draw derived from the player's own UUID instead
    /// of the RNG. Every generator routes through `Player.storedLearning` (which
    /// never emits 55), so this pass provably touches each row at most once and
    /// always writes the same value.
    static func backfillLegacyLearning(players: [Player]) {
        for player in players where player.learning == Player.defaultLearning {
            player.learning = MentalAttributeModel.learning(
                awareness: player.mental.awareness,
                level: player.mental.average,
                seed: Int(player.id.uuid.15)
            )
        }
    }

    /// Seeds `Player.competitiveness` on rows created before that property
    /// existed (phase-2 plan §2.1).
    ///
    /// Same contract as `backfillLegacyLearning`: legacy rows sit on
    /// `Player.defaultCompetitiveness` (55), the seeded value is
    /// `0.45·workEthic + 0.25·clutch + 0.30·hash[30,85]` plus the personality
    /// shift, and `Player.storedCompetitiveness` never emits 55 — so the pass is
    /// deterministic AND idempotent. A DIFFERENT UUID byte than the learning
    /// backfill is read, so the two backfilled attributes stay uncorrelated.
    /// Clamped to 25...95: a backfilled veteran should not be handed the very
    /// top of the fighter scale by a hash.
    static func backfillLegacyCompetitiveness(players: [Player]) {
        for player in players where player.competitiveness == Player.defaultCompetitiveness {
            player.competitiveness = MentalAttributeModel.competitiveness(
                archetype: player.personality.archetype,
                workEthic: player.mental.workEthic,
                clutch: player.mental.clutch,
                seed: Int(player.id.uuid.14),
                bounds: 25...95
            )
        }
    }

    /// Phase 4 face backfill — same contract as the two backfills above, one
    /// level up: it also reconciles the career's in-use registry against the
    /// live population, so a face freed by a path that never called
    /// `FaceLibrary.releaseFace` still returns to circulation.
    ///
    /// Rows created before `faceID` existed (and template-imported leagues,
    /// which are built by `LeagueTemplateImporter` rather than the random
    /// generator) get their portrait here, on the first advance after loading.
    /// Idempotent: a second run assigns nothing.
    static func backfillLegacyFaces(career: Career, players: [Player], coaches: [Coach]) {
        FaceLibrary.shared.activate(career: career)
        FaceLibrary.shared.backfill(players: players, coaches: coaches)
    }

    // MARK: - Public API

    /// Advances the career state by exactly one week.
    ///
    /// Behavior depends on the current phase:
    /// - **.regularSeason / .tradeDeadline**: Simulates all unplayed games for the
    ///   current week, updates team records, increments the week counter, and
    ///   handles the trade deadline (week `tradeDeadlineWeek`, which the career
    ///   spends in the `.tradeDeadline` phase) and the transition to playoffs
    ///   after week 18. The deadline week is an ordinary game week — same games,
    ///   same practice/injury/XP passes — so it routes to the same function.
    /// - **.playoffs**: Advances through wild card (week 19) → divisional (week 20)
    ///   → conference championship (week 21) → super bowl (week 22), then
    ///   transitions to the `.proBowl` offseason phase.
    /// - **all other offseason phases**: Steps to the next phase in the calendar
    ///   order. When reaching `.regularSeason`, a new season is started via
    ///   `startNewSeason(career:teams:modelContext:)`.
    ///
    // MARK: - Roster-Limit Gate (user's club)

    /// The user's roster sitting above the active-roster ceiling on the eve of
    /// the season.
    ///
    /// WHY this exists: `trimAIRosters` cuts every club to 53 on cutdown day
    /// `where team.id != career.teamID` — deliberately, since the user does his
    /// own cuts — but NOTHING then checked that he did. A user who never opened
    /// the cut flow walked into week 1 with 63 men against the league's 53,
    /// carrying ten players no rule allowed and a cap sheet to match, and no
    /// screen said a word about it.
    struct RosterLimitViolation {
        let rosterCount: Int
        let ceiling: Int
        var excess: Int { max(0, rosterCount - ceiling) }
    }

    /// Read-only precheck for the shell to run BEFORE `advanceWeek`.
    ///
    /// Deliberately a query, not a gate inside the advance itself: the advance
    /// mutates a season's worth of state and has no way to report a refusal
    /// halfway through, so the decision belongs to the caller — the same shape
    /// as `TradeValueEngine.validationErrors`, which the Trade Center calls
    /// before it commits anything. Returns `nil` (advance freely) for every
    /// phase except the cutdown → regular-season step.
    static func userRosterLimitViolation(
        career: Career,
        modelContext: ModelContext
    ) -> RosterLimitViolation? {
        guard career.currentPhase == .rosterCuts,
              let teamID = career.teamID else { return nil }

        let descriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == teamID }
        )
        let count = (try? modelContext.fetchCount(descriptor)) ?? 0
        let ceiling = PracticeSquadEngine.activeRosterCeiling
        guard count > ceiling else { return nil }

        return RosterLimitViolation(rosterCount: count, ceiling: ceiling)
    }

    /// The league office's letter about it, so a blocked advance leaves a record
    /// in the mailbox rather than only a dismissed alert.
    static func rosterLimitInboxMessage(
        _ violation: RosterLimitViolation,
        season: Int
    ) -> InboxMessage {
        InboxMessage(
            sender: .leagueOffice,
            subject: "Roster not compliant — \(violation.rosterCount) under contract",
            body: "Your club is carrying \(violation.rosterCount) players against a "
                + "\(violation.ceiling)-man active roster. Release \(violation.excess) more "
                + "before the season opens; the league will not certify a week-1 roster over the limit.",
            date: "Roster Cuts, Season \(season)",
            category: .leagueNotice,
            actionRequired: true,
            actionDestination: .rosterCuts
        )
    }

    // MARK: - Cap Compliance Gate (cap-compliance wave)

    /// A club that is over the salary cap when the league is looking.
    ///
    /// The second half of the wave's design: prevention stops the user promising
    /// money he does not have (`CommittedCapLedger`), remediation gives him the
    /// levers to get back under (`CapManagementEngine.complianceLevers`), and
    /// this is the reason he has to use them. Without a gate, "you are $9M over
    /// the cap" is a colour on a card.
    struct CapComplianceViolation {
        /// How far over, in thousands.
        let overage: Int
        let salaryCap: Int
        let currentCapUsage: Int
        /// Whether any lever the club holds actually frees cap — see
        /// ``CapManagementEngine/canSelfHeal(_:)``. A violation is only ever
        /// RETURNED when this is true (the anti-deadlock rule), and it is
        /// carried so the caller can say so.
        let canSelfHeal: Bool
        /// The single biggest move available, in thousands — the workspace's
        /// headline ("the largest saving on your roster is $6.1M").
        let bestLeverSavings: Int
    }

    /// Read-only precheck for the shell to run BEFORE `advanceWeek`, exactly the
    /// shape of ``userRosterLimitViolation(career:modelContext:)`` next door and
    /// for the same reason: the advance mutates a season's worth of state and
    /// cannot report a refusal halfway through, so the decision belongs to the
    /// caller.
    ///
    /// Returns `nil` — advance freely — in every one of these cases:
    ///
    /// * **Sandbox.** The cap is switched off by definition; the mode exists so
    ///   a user can build any roster he likes, and a cap gate would be the one
    ///   rule it was supposed to remove.
    /// * **Outside the compliance window.** See
    ///   `CapManagementEngine.isComplianceWindow(phase:hasRolledOver:)`: before
    ///   the league year turns, the club is carrying last season's contracts
    ///   against last season's cap and the ONLY thing that fixes it is the
    ///   rollover — which is on the far side of the block. Gating there would be
    ///   a true deadlock rather than a task.
    /// * **Compliant.** Obviously.
    /// * **Nothing left to sell.** The club is over, but every release costs
    ///   more than it saves and nothing can be restructured. See
    ///   `CapManagementEngine.canSelfHeal` — a gate with no key is a bricked
    ///   save, and the rollover's true-up will resolve it in March.
    static func userCapComplianceViolation(
        career: Career,
        modelContext: ModelContext
    ) -> CapComplianceViolation? {

        let capMode = career.capMode
        guard capMode != .sandbox else { return nil }

        guard CapManagementEngine.isComplianceWindow(
            phase: career.currentPhase,
            hasRolledOver: career.lastRolloverSeason >= career.currentSeason
        ) else { return nil }

        guard let teamID = career.teamID else { return nil }
        let teamDescriptor = FetchDescriptor<Team>(
            predicate: #Predicate<Team> { $0.id == teamID }
        )
        guard let team = try? modelContext.fetch(teamDescriptor).first else { return nil }

        let status = CapManagementEngine.complianceStatus(team: team, capMode: capMode)
        guard !status.isCompliant else { return nil }

        // Only now — after the cheap guards — is it worth loading a roster.
        let rosterDescriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == teamID }
        )
        let roster = (try? modelContext.fetch(rosterDescriptor)) ?? []
        let contractDescriptor = FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.teamID == teamID }
        )
        let contracts = (try? modelContext.fetch(contractDescriptor)) ?? []
        let contractsByPlayer = Dictionary(
            contracts.map { ($0.playerID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let levers = CapManagementEngine.complianceLevers(
            players: roster,
            contractsByPlayer: contractsByPlayer,
            capMode: capMode,
            salaryCap: team.salaryCap,
            leagueYearRemaining: CapManagementEngine.leagueYearRemaining(
                phase: career.currentPhase,
                week: career.currentWeek
            )
        )

        guard CapManagementEngine.canSelfHeal(levers) else { return nil }

        return CapComplianceViolation(
            overage: status.overage,
            salaryCap: team.salaryCap,
            currentCapUsage: team.currentCapUsage,
            canSelfHeal: true,
            bestLeverSavings: CapManagementEngine.bestLeverSavings(levers)
        )
    }

    /// The league office's letter about the overage, so a blocked advance leaves
    /// a record in the mailbox rather than only a dismissed alert.
    static func capComplianceInboxMessage(
        _ violation: CapComplianceViolation,
        season: Int,
        phase: SeasonPhase
    ) -> InboxMessage {
        let over = CommittedCapLedger.money(violation.overage)
        let best = CommittedCapLedger.money(violation.bestLeverSavings)
        return InboxMessage(
            sender: .leagueOffice,
            subject: "Cap not compliant — \(over) over",
            body: "Your club's cap sheet shows \(CommittedCapLedger.money(violation.currentCapUsage)) "
                + "committed against a \(CommittedCapLedger.money(violation.salaryCap)) cap — \(over) over the limit. "
                + "Every club must be cap-compliant to conduct league business. "
                + "Release, restructure or renegotiate until you are under; the largest single saving "
                + "available on your roster right now is \(best). "
                + "No week may be advanced until the books balance.",
            date: "\(TaskGenerator.phaseInfo(for: phase).name), Season \(season)",
            category: .leagueNotice,
            actionRequired: true,
            actionDestination: .capOverview
        )
    }

    // MARK: - AI Cap Compliance Sweep (cap-compliance wave)

    /// Restructures any AI club that is over the cap back under it, once per
    /// advance.
    ///
    /// **Why it is not enough to do this in March.** `CapManagementEngine.selfHealCapCompliance`
    /// was wired into the league-year rollover only, which healed the books at
    /// the one moment of the year they were least likely to be broken — the
    /// rollover has just grown the cap, aged off dead money and emptied every
    /// expiring deal. What actually puts an AI club under water happens
    /// afterwards: the rookie class charged at the draft, a deadline rental
    /// restored to full base (#45), a fifth-year option, an incentive that hit.
    /// All of those sat illegal for a full league year, which the multi-season
    /// smoke reports as `diag capRoom underCap=31/32`.
    ///
    /// **Cheap by construction.** The only unconditional work is one `Team`
    /// fetch — already the smallest table in the store — and an integer test per
    /// club. A roster and its contracts are loaded ONLY for a club actually over
    /// the cap, which in a healthy league is no clubs at all.
    ///
    /// **The user's club is never touched.** Deciding which contract pays for an
    /// overage is the whole point of the compliance workspace; healing it for
    /// him would delete the decision and the gate that forces it.
    ///
    /// Restructure-only, for the reason `selfHealCapCompliance` documents at
    /// length: releases are roster churn, and churn is the calibrated quantity
    /// in task #53. A restructure moves money and nobody's job, and it stops at
    /// `availableCap == 0` — far below the AI free-agent reserve (#93), so it
    /// buys legality and never spending power.
    private static func sweepAICapCompliance(career: Career, modelContext: ModelContext) {
        let capMode = career.capMode
        guard capMode != .sandbox else { return }

        let teams = (try? modelContext.fetch(FetchDescriptor<Team>())) ?? []
        let overCap = teams.filter { $0.id != career.teamID && $0.availableCap < 0 }
        guard !overCap.isEmpty else { return }

        let overIDs = Set(overCap.map(\.id))
        let allPlayers = (try? modelContext.fetch(FetchDescriptor<Player>())) ?? []
        var rosterByTeam: [UUID: [Player]] = [:]
        for player in allPlayers {
            guard let teamID = player.teamID, overIDs.contains(teamID) else { continue }
            rosterByTeam[teamID, default: []].append(player)
        }

        let allContracts = (try? modelContext.fetch(FetchDescriptor<Contract>())) ?? []
        let contractsByPlayer = Dictionary(
            allContracts.map { ($0.playerID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for team in overCap {
            CapManagementEngine.selfHealCapCompliance(
                team: team,
                players: rosterByTeam[team.id] ?? [],
                contractsByPlayer: contractsByPlayer,
                capMode: capMode,
                salaryCap: team.salaryCap
            )
        }
    }

    /// - Parameters:
    ///   - career: The active `Career` object (mutated in place).
    ///   - modelContext: SwiftData context used to fetch and persist `Game` and `Team` objects.
    static func advanceWeek(career: Career, modelContext: ModelContext) {
        // Multi-save isolation: bind every store-wide fetch below to this save.
        bind(to: career)

        // Rehydrate the cycle's draft class BEFORE any phase hook can decide it
        // does not exist. `bind` above clears the statics on a career switch and
        // a cold launch starts with them empty, so without this the
        // `!draftClassGenerated` guards in the week-9 / coachingChanges /
        // combine hooks generate and INSERT a second class over the top of the
        // persisted one.
        restoreDraftClassIfNeeded(career: career, modelContext: modelContext)

        // Reset per-advance state
        lastNewsItems = []
        lastEvents = []
        lastInboxMessages = []
        wasFired = false
        pendingPressConference = nil

        switch career.currentPhase {

        case .regularSeason, .tradeDeadline:
            PerfLog.time("advance.regularSeason") {
                advanceRegularSeasonWeek(career: career, modelContext: modelContext)
            }

        case .playoffs:
            PerfLog.time("advance.playoffs") {
                advancePlayoffWeek(career: career, modelContext: modelContext)
            }

        default:
            PerfLog.time("advance.offseason.\(career.currentPhase.rawValue)") {
                advanceOffseasonPhase(career: career, modelContext: modelContext)
            }
        }

        // The live-game injury exemption never outlives the advance it was
        // registered for (consumed by the regular-season injury pass above).
        liveGameInjuryTeamIDs = []

        // Cap-compliance wave — the other 31 clubs settle their books, every
        // week. AFTER the phase hook above, because the hook is what puts them
        // over: a draft class charged in April, a deadline rental in November,
        // a fifth-year option, an incentive that landed.
        //
        // `FreeAgencyEngine.executeNewLeagueYear` already runs this pass at the
        // March rollover, and that was the ONLY place it ran — so anything
        // charged after March sat illegal until the following March, and the
        // smoke's `diag capRoom` duly reported clubs under water at season end.
        // The user is gated on his books EVERY week (`userCapComplianceViolation`);
        // the league cannot be checked once a year and still be the same league.
        sweepAICapCompliance(career: career, modelContext: modelContext)

        // R29: persist this advance's headlines (newest first) so the News
        // screen has real content that survives app restarts. `lastNewsItems`
        // stays available for same-advance consumers (owner satisfaction).
        if !lastNewsItems.isEmpty {
            career.newsLog = lastNewsItems + career.newsLog
        }
    }

    // MARK: - Score Simulation

    /// Generates a pair of realistic NFL final scores.
    ///
    /// Model:
    /// - Each side rolls a base number of touchdowns (0–5) and field goals (0–4).
    /// - TD = 7 points, FG = 3 points (simplified; no extra-point failures).
    /// - Home team receives a flat +3 point advantage on average.
    /// - Approximately 1 % of games end in a tie by forcing overtime parity.
    ///
    /// - Returns: A tuple `(home: Int, away: Int)` with each score ≥ 0.
    static func simulateGameScore() -> (home: Int, away: Int) {
        // ~1 % tie chance — resolve before computing independent scores.
        let tieRoll = Int.random(in: 1...100)
        if tieRoll == 1 {
            // Tied game: both teams land the same realistic score.
            let tiedScore = randomTeamScore(homeAdvantage: 0)
            return (tiedScore, tiedScore)
        }

        let homeScore = randomTeamScore(homeAdvantage: 3)
        let awayScore = randomTeamScore(homeAdvantage: 0)

        // Ensure no accidental tie outside the 1 % path.
        if homeScore == awayScore {
            // Break tie by giving home team one extra point (safety).
            return (homeScore + 1, awayScore)
        }

        return (homeScore, awayScore)
    }

    // MARK: - New Season Bootstrap

    /// Resets every team's record, generates a fresh schedule, and sets the
    /// career state to Week 1 of the regular season.
    ///
    /// All generated `Game` objects are inserted into `modelContext`. It is the
    /// caller's responsibility to save the context afterward.
    ///
    /// - Parameters:
    ///   - career: The active `Career` object (mutated in place).
    ///   - teams:  All 32 teams in the league.
    ///   - modelContext: SwiftData context used to insert the new games.
    static func startNewSeason(career: Career, teams: [Team], modelContext: ModelContext) {
        bind(to: career)
        // 0. Recalculate coaching budgets based on previous season performance (#80)
        for team in teams {
            if let owner = team.owner {
                let madePlayoffs = team.wins >= 9  // Approximate playoff threshold
                owner.previousCoachingBudget = owner.coachingBudget
                owner.coachingBudget = BudgetEngine.calculateBudget(
                    owner: owner,
                    team: team,
                    previousSeasonWins: team.wins,
                    madePlayoffs: madePlayoffs
                )
                // R27: recalculate the dedicated scouting department budget too
                owner.previousScoutingBudget = owner.scoutingBudget
                owner.scoutingBudget = BudgetEngine.calculateScoutingBudget(
                    owner: owner,
                    team: team,
                    previousSeasonWins: team.wins,
                    madePlayoffs: madePlayoffs
                )
                // R31: recalculate the dedicated medical department budget too
                owner.previousMedicalBudget = owner.medicalBudget
                owner.medicalBudget = BudgetEngine.calculateMedicalBudget(
                    owner: owner,
                    team: team,
                    previousSeasonWins: team.wins,
                    madePlayoffs: madePlayoffs
                )
            }
        }

        // 0-facilities. TODO §5.4: the annual facility pass, run once a season
        // right after the envelopes are recalculated above — the pass reads
        // `FacilityEngine.annualBudget`, which is a function of the owner's
        // spending willingness and mood, so it belongs with the rest of the
        // owner's money decisions. Every club first trims back to what its owner
        // will fund, then the 31 AI clubs spend what is left; the user's club is
        // skipped for upgrades because the facilities card is his lever. Without
        // this call no AI owner ever invests and the league never stratifies.
        FacilityEngine.processOffseasonInvestment(teams: teams, userTeamID: career.teamID)

        // 0a. R31: season-opening owner meeting for the user's team —
        // apply last review's bonus to the fresh envelope, generate this
        // season's tracked goals, and deliver the expectations message.
        if let userTeam = teams.first(where: { $0.id == career.teamID }),
           let owner = userTeam.owner {
            if let review = career.ownerSeasonReview,
               review.budgetBonusPct > 0,
               review.seasonYear == career.currentSeason - 1 {
                let bonus = 1.0 + review.budgetBonusPct
                owner.coachingBudget = Int(Double(owner.coachingBudget) * bonus)
                owner.scoutingBudget = Int(Double(owner.scoutingBudget) * bonus)
                owner.medicalBudget = Int(Double(owner.medicalBudget) * bonus)
            }

            let goals = OwnerGoalsEngine.generateSeasonGoals(
                team: userTeam,
                owner: owner,
                career: career
            )
            career.ownerSeasonGoals = goals
            // Whims from finished seasons are history now.
            career.ownerWhims = career.ownerWhims.filter { $0.seasonYear >= career.currentSeason }

            lastInboxMessages.append(OwnerPersonaEngine.seasonKickoffMessage(
                owner: owner,
                career: career,
                goals: goals
            ))
        }

        // 0b. Reset franchise tags from previous season
        let allPlayersForReset = fetchAllPlayers(modelContext: modelContext)
        for player in allPlayersForReset where player.isFranchiseTagged {
            player.isFranchiseTagged = false
        }

        // 0b-2. #33: clear the per-player games-played tally for EVERY player
        // (rostered, free agent, retired) so the new regular season starts from
        // zero. The prior season's value was already snapshotted into
        // PlayerSeasonHistory at week 18.
        for player in allPlayersForReset where player.gamesPlayedThisSeason != 0 {
            player.gamesPlayedThisSeason = 0
        }
        // #40: clear the per-player starts tally too (snapshotted at week 18).
        for player in allPlayersForReset where player.gamesStartedThisSeason != 0 {
            player.gamesStartedThisSeason = 0
        }
        // Career stats: same lifecycle for the accumulated season statline —
        // week 18 already snapshotted it into PlayerSeasonHistory.
        for player in allPlayersForReset where player.seasonStatLineData != nil {
            player.seasonStatLineData = nil
        }

        // 0c. R22: a new season reopens every negotiation an insulted agent
        // froze last offseason.
        NegotiationLockRegistry.reset()

        // 1. Snapshot the finished season's record, THEN reset it.
        //
        // Ordering is load-bearing: `lastSeasonWins/-Losses` (plan §2.3) must be
        // written from the live counters before they are zeroed, otherwise every
        // team reads as a 0-win collapse next offseason. Everything above this
        // point that consumes `team.wins` (the budget recalculations in step 0)
        // still sees the finished season, exactly as before.
        for team in teams {
            // A team with no games on the board never played a season — leave the
            // `-1` "unknown" sentinel rather than inventing an 0-win collapse.
            if team.wins + team.losses + team.ties > 0 {
                team.lastSeasonWins = team.wins
                team.lastSeasonLosses = team.losses
            }
            team.wins = 0
            team.losses = 0
            team.ties = 0
        }

        // 2. Generate a brand-new schedule for the upcoming season year.
        let newGames = ScheduleGenerator.generateSeason(
            teams: teams,
            seasonYear: career.currentSeason
        )

        // 3. Persist every game into the SwiftData store.
        for game in newGames {
            game.careerID = career.id
            modelContext.insert(game)
        }

        // 4. Update career state.
        let previousPhase = career.currentPhase
        career.currentPhase = .regularSeason
        career.currentWeek = 1
        emitGroupTransitionMessageIfNeeded(
            oldPhase: previousPhase,
            newPhase: .regularSeason,
            season: career.currentSeason
        )

        // 5. Reset draft class flag for the new offseason cycle.
        draftClassGenerated = false
        currentDraftClass = []
        currentDraftPicks = []
        currentMockDraft = []
        mockDraftHistory = [:]
        // #103: the persisted copy goes with it. The blob's season stamp would
        // already invalidate it (the season was incremented immediately above
        // this call), but leaving a dead 100 kB of last cycle's mocks on the
        // save to be re-read and discarded every launch is not a saving.
        career.mockDraftHistoryData = nil

        // 6. R21: stale trade offers never survive into a new season.
        career.pendingTradeOffers = []

        // 6a. Wave 2: the league year's trade counters and the GMs' memory of how
        // the user negotiated all reset at kickoff.
        //
        // Both offseason counters are zeroed HERE on purpose. The offseason of
        // cycle N runs after week 18 of season N and before this function turns
        // the year over, so resetting at kickoff means each pair of kickoffs
        // brackets exactly one offseason — the counters are never half a cycle
        // stale. (The smoke harness reads the MONOTONIC totals for its per-season
        // diff, so this reset cannot hide a season's volume from the diagnostics.)
        aiOffersThisSeason = 0
        aiOffersThisOffseason = 0
        leagueTradesThisSeason = 0
        leagueTradesThisOffseason = 0
        TradeValueEngine.TradeTalkRegistry.reset()

        // 6b. R28: return decisions are week-scoped calls — never carry them
        // into a new season (offseason rehab resolves the injuries anyway).
        career.pendingReturnDecisions = []

        // 6c. R32: scouting counters are per-draft-cycle allowances — they
        // were never reset before, so the user permanently ran out of
        // interviews/workouts/visits after season one.
        career.interviewsUsed = 0
        career.workoutsUsed = 0
        career.top30VisitsUsed = 0

        // 6c-1. The second workout economy that used to be reset here — a
        // `CareerScopedDefaults` counter capped at 10, spent by the pro-day
        // screen through `attendProDay` while the prospect card billed
        // `career.workoutsUsed` / 30 through `conductPersonalWorkout` — is gone
        // (plan F7). `career.workoutsUsed` above is the only workout allowance,
        // and it is already reset one line up.

        // 6c-2. R32: scouts' pro-day trip counters are per-cycle too (same
        // leak — `canAttendProDay` went permanently false after season one).
        for scout in fetchAllScouts(modelContext: modelContext) {
            scout.proDaysAttended = 0
            scout.proDayColleges = []
        }

        // 6d. R32: last season's owner demands were settled (the penalty was
        // applied at the rosterCuts → regularSeason boundary) — clear them so
        // stale demands don't linger in the UI. Fresh ones arrive at the next
        // reviewRoster phase.
        career.ownerDemands = []
        career.ownerDemandsAddressed = []

        // 7. R32: database hygiene — drop the concluded draft's prospect rows
        // (~350/season; the restart-restore path reads ALL persisted
        // prospects, so stale rows would pollute next season's board) and
        // games older than the season that just ended.
        purgeStaleSeasonData(career: career, modelContext: modelContext)

        // 8. R32: AI roster floor — teams that shrank below playable size
        // (retirements + expiries) re-sign veteran-minimum free agents by
        // need, or street free agents when the pool is dry.
        refillAIRosters(career: career, teams: teams, modelContext: modelContext)

        // 9. Plan finding S1: the pick horizon rolls with the calendar. The
        // draft one year out was consumed this offseason, so year N+3 is minted
        // now and the shelf holds three tradable future drafts again.
        ensureFuturePickHorizon(career: career, teams: teams, modelContext: modelContext)
    }

    // MARK: - Private: Per-team staff lookup (R39 perf)

    /// A team's medical staff, resolved once per advance.
    struct TeamMedicalStaff {
        var doctor: Coach?
        var physio: Coach?
        var trainer: Coach?
    }

    /// One pass over `coaches` → per-team doctor/physio/trainer. Keeps the
    /// original `allCoaches.first { … }` semantics: the FIRST coach of a role
    /// in array order wins, so results are bit-identical to the old scans.
    static func medicalStaffByTeam(coaches: [Coach]) -> [UUID: TeamMedicalStaff] {
        var map: [UUID: TeamMedicalStaff] = [:]
        for coach in coaches {
            guard let teamID = coach.teamID else { continue }
            switch coach.role {
            case .teamDoctor:
                if map[teamID, default: TeamMedicalStaff()].doctor == nil {
                    map[teamID, default: TeamMedicalStaff()].doctor = coach
                }
            case .physio:
                if map[teamID, default: TeamMedicalStaff()].physio == nil {
                    map[teamID, default: TeamMedicalStaff()].physio = coach
                }
            case .headTrainer:
                if map[teamID, default: TeamMedicalStaff()].trainer == nil {
                    map[teamID, default: TeamMedicalStaff()].trainer = coach
                }
            default:
                break
            }
        }
        return map
    }

    // MARK: - Private: Regular Season

    private static func advanceRegularSeasonWeek(career: Career, modelContext: ModelContext) {
        var perf = PerfLog.Lap("advance_regular")   // R39 breakdown
        let week = career.currentWeek
        let season = career.currentSeason

        // Camp Phase 1: apply opponent-prep drift penalty if user has been
        // over-focusing on opponent prep for 3+ consecutive weeks. The
        // gameBoost() side is consumed inside GameSimulator integration -- here
        // we only persist the long-term drift consequence (-1..-3 OVR) so it
        // survives across re-renders.
        if let teamID = career.teamID {
            applyOpponentPrepDrift(teamID: teamID, season: season, week: week, modelContext: modelContext)
        }

        // Fetch all unplayed regular-season games for this week.
        let unplayedGames = fetchUnplayedGames(
            week: week,
            seasonYear: season,
            isPlayoff: false,
            modelContext: modelContext
        )

        // Build a team lookup so we can update records efficiently.
        let teamsByID = fetchTeamsByID(modelContext: modelContext)
        let allPlayers = fetchAllPlayers(modelContext: modelContext)
        let allCoaches = fetchAllCoaches(modelContext: modelContext)

        // R39 perf: the fatigue/injury/XP passes below used to re-scan
        // `allCoaches`/`allPlayers` once per player (O(players × coaches) —
        // ~850k SwiftData attribute reads, ~1 s per advance). Group both by
        // team ONCE; every lookup keeps `.first`-scan semantics (same coach
        // wins when a team somehow has duplicates of a role).
        let medicalStaffByTeam = Self.medicalStaffByTeam(coaches: allCoaches)
        let coachesByTeam = Dictionary(grouping: allCoaches.filter { $0.teamID != nil },
                                       by: { $0.teamID! })
        let playersByTeam = Dictionary(grouping: allPlayers.filter { $0.teamID != nil },
                                       by: { $0.teamID! })
        perf.lap("fetch")

        // Plan §5 in-flight save migration: seed `learning` on pre-overhaul rows
        // and swap out a pre-overhaul draft class (the midseason class is
        // generated at week 9, well before any pick is made).
        backfillLegacyLearning(players: allPlayers)
        backfillLegacyCompetitiveness(players: allPlayers)
        backfillLegacyFaces(career: career, players: allPlayers, coaches: allCoaches)
        migrateLegacyDraftClassIfNeeded(career: career, modelContext: modelContext)
        // Trade plan finding S1: a save from before future picks existed would
        // keep an EMPTY tradable pick pool until its next season rollover — mint
        // the horizon here so the deadline market works on this season already.
        ensureFuturePickHorizon(
            career: career,
            teams: Array(teamsByID.values),
            modelContext: modelContext
        )

        // Simulate every unplayed game.
        // Player's team game uses full play-by-play simulation;
        // all other games use the fast random score generator.
        var playerGameResult: GameSimulator.GameResult?

        for game in unplayedGames {
            let isPlayerGame = (game.homeTeamID == career.teamID || game.awayTeamID == career.teamID)

            if isPlayerGame,
               let homeTeam = teamsByID[game.homeTeamID],
               let awayTeam = teamsByID[game.awayTeamID] {
                // Full play-by-play simulation for the player's game
                let homeCoaches = allCoaches.filter { $0.teamID == homeTeam.id }
                let awayCoaches = allCoaches.filter { $0.teamID == awayTeam.id }

                // Camp Phase 1: fetch this week's OpponentPrepWeek for the user
                // and convert it into a game-boost via OpponentPrepEngine. The
                // boost is applied to the user's team only — AI-vs-user games
                // still get the full play-by-play simulation but with the user
                // benefiting from their prep choice.
                let userTeamID = career.teamID
                var audibleBoost = 0.0
                var defReadBoost = 0.0
                if let userTeamID = userTeamID,
                   userTeamID == homeTeam.id || userTeamID == awayTeam.id {
                    let prepDescriptor = FetchDescriptor<OpponentPrepWeek>(
                        predicate: #Predicate<OpponentPrepWeek> {
                            $0.seasonYear == season
                                && $0.weekNumber == week
                                && $0.teamID == userTeamID
                        }
                    )
                    if let prep = (try? modelContext.fetch(prepDescriptor))?.first {
                        let boost = OpponentPrepEngine.gameBoost(prep: prep)
                        audibleBoost = boost.audibleBoost
                        defReadBoost = boost.defensiveReadBoost
                    }
                }

                // The user's saved game plan shades only the user's own
                // offense; the AI opponent always simulates with `nil` (today's
                // exact behavior). `savedGamePlan` is nil until the user has
                // touched the Game Plan screen at least once.
                let userPlan = career.savedGamePlan
                let result = GameSimulator.simulate(
                    homeTeam: homeTeam,
                    awayTeam: awayTeam,
                    homeCoaches: homeCoaches,
                    awayCoaches: awayCoaches,
                    audibleBoost: audibleBoost,
                    defReadBoost: defReadBoost,
                    boostedTeamID: userTeamID,
                    homeGamePlan: homeTeam.id == userTeamID ? userPlan : nil,
                    awayGamePlan: awayTeam.id == userTeamID ? userPlan : nil,
                    // Deterministic per-game weather — the live coached game
                    // derives the identical value from the same game id/week/
                    // home venue (dome home teams always play indoors/clear).
                    weather: GameWeather.forGame(id: game.id, week: game.week, homeTeamAbbreviation: homeTeam.abbreviation)
                )
                game.homeScore = result.homeScore
                game.awayScore = result.awayScore
                playerGameResult = result
            } else {
                let score = simulateGameScore()
                game.homeScore = score.home
                game.awayScore = score.away
            }

            updateTeamRecords(game: game, teamsByID: teamsByID)
        }
        perf.lap("games")

        // Career stats: the user's game is the only one that produces a real box
        // score (every other game is score-only), so fold it into the players'
        // running season lines. A game coached live via `LiveGameEngine` never
        // reaches this loop — that path accumulates inside `LiveGameEngine.persist`.
        if let result = playerGameResult {
            accumulateSeasonStats(result.playerStats, players: allPlayers)
        }

        // #33: per-player games-played bookkeeping. A player is credited an
        // appearance when his team plays a regular-season game this week and he
        // was AVAILABLE — on the active roster, healthy, not holding out, not
        // retired. This is the only participation signal available league-wide
        // (AI games are score-only; a real box score exists for the user's game
        // alone), so "available" is the documented definition of "played". The
        // running tally is snapshotted into `PlayerSeasonHistory.gamesPlayed`
        // at week 18 and reset in `startNewSeason`. We fetch ALL of this week's
        // regular-season games (not just `unplayedGames`) so a user game coached
        // live via `LiveGameEngine` — already played before this method runs —
        // still credits both rosters.
        let weekGamesForAttendance = fetchAllRegularSeasonGames(
            week: week,
            seasonYear: season,
            modelContext: modelContext
        )
        for game in weekGamesForAttendance {
            for teamID in [game.homeTeamID, game.awayTeamID] {
                let roster = playersByTeam[teamID] ?? []
                let available = roster.filter { !$0.isInjured && !$0.isHoldingOut && !$0.isRetired }
                // #40: derive this week's starters from the available roster,
                // mirroring the best-available lineup the sim would field.
                let starterIDs = startingLineupIDs(available: available)
                for player in available {
                    player.gamesPlayedThisSeason += 1
                    if starterIDs.contains(player.id) {
                        player.gamesStartedThisSeason += 1
                    }
                }
            }
        }
        perf.lap("attendance")

        // Store the latest player game result for UI to access.
        //
        // When the player's game was coached interactively (LiveGameEngine), it
        // was already played BEFORE advanceWeek: it never appears in
        // `unplayedGames`, so `playerGameResult` stays nil here. In that case
        // derive win/loss from the persisted game scores and keep whatever
        // result the live engine stored in `lastPlayerGameResult` (set by
        // `LiveGameEngine.persist`) for the press-conference context.
        var coachedGameWon: Bool?
        if playerGameResult != nil {
            lastPlayerGameResult = playerGameResult
        } else if let playerTeamID = career.teamID,
                  let coachedGame = fetchPlayedPlayerGame(
                      week: week,
                      seasonYear: season,
                      teamID: playerTeamID,
                      modelContext: modelContext
                  ),
                  let home = coachedGame.homeScore,
                  let away = coachedGame.awayScore {
            let isHome = coachedGame.homeTeamID == playerTeamID
            coachedGameWon = isHome ? home > away : away > home
            // lastPlayerGameResult stays as the live engine left it.
        } else {
            // Player genuinely had no played game this week.
            lastPlayerGameResult = nil
        }

        // R25: win/loss of the user's game this week — shared by the press
        // conference context and the locker-room pulse below.
        let userWonLastGame: Bool? = {
            if let coachedGameWon { return coachedGameWon }
            guard let result = playerGameResult, let playerTeamID = career.teamID else { return nil }
            if let game = unplayedGames.first(where: {
                $0.homeTeamID == playerTeamID || $0.awayTeamID == playerTeamID
            }) {
                let isHome = game.homeTeamID == playerTeamID
                return isHome ? result.homeScore > result.awayScore : result.awayScore > result.homeScore
            }
            return nil
        }()

        // Coach weekly XP
        if let playerTeamID = career.teamID {
            let teamCoaches = allCoaches.filter { $0.teamID == playerTeamID }
            let hc = teamCoaches.first { $0.role == .headCoach }
            let ahc = teamCoaches.first { $0.role == .assistantHeadCoach }
            let isPlayoff = career.currentPhase == .playoffs
            let playerTeamWon: Bool = {
                if let coachedGameWon { return coachedGameWon }
                guard let result = playerGameResult else { return false }
                if let game = unplayedGames.first(where: {
                    $0.homeTeamID == playerTeamID || $0.awayTeamID == playerTeamID
                }) {
                    let isHome = game.homeTeamID == playerTeamID
                    return isHome ? result.homeScore > result.awayScore : result.awayScore > result.homeScore
                }
                return false
            }()
            for coach in teamCoaches {
                CoachDevelopmentEngine.applyWeeklyXP(
                    coach: coach,
                    didWin: playerTeamWon,
                    isPlayoff: isPlayoff,
                    headCoach: hc,
                    assistantHC: ahc
                )
            }
        }

        // 0a. R29: league narrative — power rankings, MVP race, storyline
        // headlines (streaks, upsets, hot seats, division races, season arc).
        // Runs before the presser so this week's fresh ranking can be quoted.
        // Presentation only: reads results, never touches them.
        let seasonGames = fetchAllGamesForSeason(seasonYear: season, modelContext: modelContext)
        let narrativeUpdate = LeagueNarrativeEngine.updateWeekly(
            previousState: career.leagueNarrative,
            teams: Array(teamsByID.values),
            players: allPlayers,
            coaches: allCoaches,
            games: seasonGames,
            career: career,
            week: week,
            season: season
        )
        career.leagueNarrative = narrativeUpdate.state
        perf.lap("narrative")

        // 0. Generate weekly press conference questions
        if let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            let lastGameWon = userWonLastGame

            // Distill concrete facts from the played game (quick-simmed or
            // live-coached — both leave their result in lastPlayerGameResult)
            // so the presser can reference what actually happened.
            let gameFacts = pressGameFacts(
                lastGameWon: lastGameWon,
                result: lastPlayerGameResult,
                playerTeamID: playerTeamID,
                allPlayers: allPlayers,
                teamsByID: teamsByID,
                narrative: narrativeUpdate.state
            )

            pendingPressConference = PressConferenceEngine.generateWeeklyPressConference(
                career: career,
                team: playerTeam,
                lastGameResult: lastGameWon,
                week: week,
                facts: gameFacts
            )
        }

        // --- Engine integrations after game simulation ---

        let teams = Array(teamsByID.values)

        // 1. Generate weekly news
        lastNewsItems = NewsGenerator.generateWeeklyNews(
            teams: teams,
            players: allPlayers,
            career: career,
            week: week,
            season: season
        )

        // 1b. R29: storyline headlines from the narrative engine (power
        // rankings, streaks, upsets, MVP race, division races, hot seats).
        lastNewsItems.append(contentsOf: narrativeUpdate.news)

        // 2. Generate weekly events for the player's team
        if let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            lastEvents = EventEngine.generateWeeklyEvents(
                team: playerTeam,
                players: allPlayers,
                coaches: allCoaches,
                career: career
            )

            // 3. Update owner satisfaction
            if let owner = playerTeam.owner {
                OwnerSatisfactionEngine.updateSatisfaction(
                    owner: owner,
                    team: playerTeam,
                    career: career,
                    newsItems: lastNewsItems
                )

                // 4. Check if the owner fires the player.
                // R31: the shell now consumes this flag (career-over screen).
                // Grace period — no mid-season firing during the first season.
                if career.totalWins + career.totalLosses > 18 {
                    wasFired = OwnerSatisfactionEngine.checkFiring(owner: owner, career: career)
                }
            }

            // 4b. Generate weekly inbox messages.
            //
            // The deadline week asks for REGULAR-SEASON mail on purpose: its two
            // `.tradeDeadline` letters were already delivered when the phase was
            // entered (end of the previous advance), and `generatePhaseMessages`
            // documents itself as "the phase that just became active" — asking it
            // again here would repeat them a week late, after the deadline.
            let teamCoaches = allCoaches.filter { $0.teamID == playerTeamID }
            let mailPhase: SeasonPhase =
                career.currentPhase == .tradeDeadline ? .regularSeason : career.currentPhase
            lastInboxMessages = InboxEngine.generatePhaseMessages(
                phase: mailPhase,
                career: career,
                team: playerTeam,
                coaches: teamCoaches,
                owner: playerTeam.owner
            )

            // 4b-2. R31: Meddler owners fire off 1-2 "suggestions" a season.
            // The whim lands in the inbox; the user responds in Owner Relations.
            if let owner = playerTeam.owner,
               let whim = OwnerPersonaEngine.rollWhim(owner: owner, career: career, week: week) {
                career.ownerWhims = career.ownerWhims + [whim]
                lastInboxMessages.append(
                    OwnerPersonaEngine.whimInboxMessage(whim: whim, ownerName: owner.name)
                )
            }

            // 4c. Wave 2: the phone rings on a hazard ramp into the deadline
            // (decision §7.2 — 3-8 offers a season, back-loaded, plus 2-5 in the
            // offseason windows). The old rule was a flat 15 %/week over weeks
            // 1-8 ≈ 1.2 attempts a season with both productive branches dead
            // (finding S5), so the phone effectively never rang.
            //
            // `userOfferHazard` owns the curve, the cap and the pity floor; this
            // block owns the dice. Deadline week gets two rolls, and a club that
            // already has an offer on the table is excluded rather than allowed to
            // overwrite it.
            let offerWindow: TradeValueEngine.MarketWindow =
                week == tradeDeadlineWeek ? .deadline : .week(week)
            let hazard = TradeValueEngine.userOfferHazard(
                window: offerWindow, offersSoFar: aiOffersThisSeason
            )
            if week <= tradeDeadlineWeek, hazard.rolls > 0 {
                let activePicks = fetchActiveDraftPicks(modelContext: modelContext)
                // Contracts make the offer builder no-trade-clause-aware; without
                // them the Trade Center would veto on accept what the AI just
                // offered (preview ≢ outcome).
                let contractCareerID = activeCareerID
                let contracts = (try? modelContext.fetch(FetchDescriptor<Contract>(
                    predicate: #Predicate { $0.careerID == contractCareerID }
                ))) ?? []
                for _ in 0..<hazard.rolls {
                    guard aiOffersThisSeason < TradeValueEngine.maxInSeasonOffers else { break }
                    guard Int.random(in: 1...100) <= hazard.chancePercent else { continue }
                    let alreadyOffering = Set(career.pendingTradeOffers.map(\.offeringTeamID))
                    guard let offer = TradeValueEngine.generateAIOffer(
                        window: offerWindow,
                        userTeam: playerTeam,
                        allTeams: teams,
                        allPlayers: allPlayers,
                        allPicks: activePicks,
                        capMode: career.capMode,
                        currentSeason: season,
                        week: week,
                        contracts: contracts,
                        excludingTeamIDs: alreadyOffering
                    ) else { continue }

                    var pending = career.pendingTradeOffers
                    pending.removeAll { $0.offeringTeamID == offer.proposal.offeringTeamID }
                    pending.append(offer.proposal)
                    career.pendingTradeOffers = Array(pending.suffix(5))
                    aiTradeOffersGenerated += 1        // Wave 0 instrumentation
                    aiOffersThisSeason += 1
                    lastInboxMessages.append(
                        TradeValueEngine.offerInboxMessage(offer: offer, week: week, season: season)
                    )
                }
            }

            // 4c-2. Task #39: the GMs the user is ALREADY talking to work the
            // phones too. One move per open conversation per week — sweeten, walk
            // away, or (most weeks) sit tight.
            advanceOpenTradeThreads(
                career: career,
                teamsByID: teamsByID,
                allPlayers: allPlayers,
                week: week,
                season: season,
                modelContext: modelContext
            )
        }

        perf.lap("news_events_inbox")

        // 4d. R22: active holdout drama for the user's team — weekly morale
        // drain, agent escalation, and the player caving around week 3-4.
        if let playerTeamID = career.teamID {
            processHoldoutWeek(
                teamID: playerTeamID,
                allPlayers: allPlayers,
                week: week,
                season: season,
                salaryCap: teams.first(where: { $0.id == playerTeamID })?.salaryCap
                    ?? ContractEngine.openingSalaryCap,
                modelContext: modelContext
            )
        }

        // 4e. R25: locker room pulse — auto-resolve stale pending drama, then
        // roll a new personality-driven event (~25 % of weeks) for the user's
        // team. Choice events wait on the career; info events apply instantly.
        if let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            processLockerRoomWeek(
                career: career,
                team: playerTeam,
                allPlayers: allPlayers,
                allCoaches: allCoaches,
                wonLastGame: userWonLastGame,
                week: week,
                season: season
            )
        }

        perf.lap("holdout_lockerroom")

        // 4f. Phase 2 (plan §2.9.1): the weekly morale loop, activated.
        // `LockerRoomEngine.weeklyMoraleUpdate` was written but never called —
        // morale only ever moved through holdouts, tags and locker-room events,
        // so the designed "winning lifts the room, losing drains it" link did
        // not exist. It now runs league-wide (morale gates weekly training
        // gains and the §2.3 motivation triggers for all 32 clubs, not just the
        // user's) with the ±3 + reversion damping described on the engine.
        //
        // Only rosters that actually played are ticked — a bye week is not a
        // loss — and holdouts are skipped because `HoldoutEngine` owns their
        // morale while they are away from the facility.
        var weekResultByTeam: [UUID: Bool] = [:]
        for game in weekGamesForAttendance {
            guard let home = game.homeScore, let away = game.awayScore, home != away else { continue }
            weekResultByTeam[game.homeTeamID] = home > away
            weekResultByTeam[game.awayTeamID] = away > home
        }
        for (teamID, won) in weekResultByTeam {
            let roster = (playersByTeam[teamID] ?? []).filter { !$0.isHoldingOut && !$0.isRetired }
            guard !roster.isEmpty else { continue }
            LockerRoomEngine.weeklyMoraleUpdate(
                players: roster,
                wonLastGame: won,
                chemistry: LockerRoomEngine.chemistryScore(players: roster)
            )
        }

        perf.lap("morale")

        // 5. Apply fatigue changes for players who played this week
        // (R22: holdout players are away from the facility — no game fatigue).
        for player in allPlayers where player.teamID != nil && !player.isInjured && !player.isHoldingOut {
            let fatigueGain = Int.random(in: 3...8)
            player.fatigue = min(100, player.fatigue + fatigueGain)
        }

        // 5b. Apply fatigue recovery using MedicalEngine (physio improves recovery)
        for player in allPlayers {
            guard let teamID = player.teamID else { continue }
            let teamPhysio = medicalStaffByTeam[teamID]?.physio
            let recovery = MedicalEngine.weeklyFatigueRecovery(player: player, physio: teamPhysio)
            player.fatigue = max(0, player.fatigue - recovery)
        }

        // 6. Process injuries for players who played (medical staff reduces risk).
        //    Teams that played their game LIVE this week are exempt: the live
        //    engine already rolled per-play injury dice at the same aggregate
        //    rate (see LiveGameEngine.rollInjuries) — rolling here too would
        //    double the live coach's injury exposure.
        for player in allPlayers where player.teamID != nil && !player.isInjured && !player.isHoldingOut {
            guard let teamID = player.teamID else { continue }
            if liveGameInjuryTeamIDs.contains(teamID) { continue }
            let staff = medicalStaffByTeam[teamID]
            let teamDoctor = staff?.doctor
            let teamPhysio = staff?.physio
            let teamTrainer = staff?.trainer

            // Use MedicalEngine for injury check with medical staff awareness.
            // R40: the career's injury-frequency league setting scales (or
            // disables) the weekly roll; .normal = 1.0 = today's exact rates.
            if let injury = MedicalEngine.injuryCheck(
                player: player,
                playType: .run,  // Approximate — actual play type not tracked at weekly level
                doctor: teamDoctor,
                physio: teamPhysio,
                trainer: teamTrainer,
                frequencyMultiplier: career.injuryFrequency.riskMultiplier
            ) {
                MedicalEngine.applyInjury(
                    player: player,
                    injuryType: injury,
                    doctor: teamDoctor,
                    physio: teamPhysio,
                    season: season,
                    week: week
                )

                // R28: league star injuries make headlines.
                if player.overall >= 85, let teamID = player.teamID,
                   let team = teamsByID[teamID] {
                    lastNewsItems.append(NewsItem(
                        headline: "\(team.abbreviation) star \(player.fullName) suffers \(injury.rawValue.lowercased()) injury",
                        body: "\(team.fullName) \(player.position.rawValue) \(player.fullName) left this week's action with a \(injury.rawValue.lowercased()) injury and is expected to miss around \(player.injuryWeeksOriginal) week\(player.injuryWeeksOriginal == 1 ? "" : "s"). The medical staff has started his rehab program.",
                        category: .injury,
                        week: week,
                        season: season,
                        relatedTeamID: teamID,
                        relatedPlayerID: player.id,
                        sentiment: .negative
                    ))
                }
            }
        }

        // R28: tick down post-rush-back exposure windows (healthy players only).
        for player in allPlayers where player.rushBackWeeksRemaining > 0 && !player.isInjured {
            player.rushBackWeeksRemaining -= 1
        }

        // 7. Apply game experience, weighted by where each man sits on his club's
        // REAL depth chart (task #29).
        // (R22: holdout players don't play, so they earn no experience.)
        // R25: a young player with an active mentor in his position room
        // develops slightly faster (+10 % XP, league-wide and symmetric).
        // Plan §2.9.5: teams whose QB room actually develops the backup — a QB
        // coach rated 70+ (an active mentorship counts too, per player below).
        //
        // **This used to be a switch at `overall >= 60`**, which handed a full
        // starter's week to 90.6 % of the league — 24 men start a football game,
        // so the approximation was wrong by ~45 pp, and it was wrong in the
        // direction that inflates: the entire bench developed at a starter's
        // rate. `tools/balance-harness`'s `career` scenario has always fielded a
        // real lineup and sits at a flat equilibrium; the shipped league drifted
        // +1.55 OVR and 17.5 % → 21.3 % at 80+ over three smoke seasons. The gap
        // between the two was this line.
        //
        // `startingLineupIDs` is the same lineup the weekly starter tally and the
        // 3D matchup resolver use, so the man credited with a start here is the
        // man the simulator would field. Everyone behind him is graded by
        // `PlayerDevelopmentEngine.playingTimeRoles` onto §6's ladder.
        let clipboardTeamIDs = Set(
            allCoaches
                .filter { $0.role == .qbCoach && $0.playerDevelopment >= 70 }
                .compactMap(\.teamID)
        )
        let mentoredIDs = LockerRoomEngine.mentoredProtegeIDs(allPlayers: allPlayers)

        // Depth-chart roles, computed once per club off the men actually
        // available this week — an injured starter's snaps really do promote the
        // man behind him, which is where a backup's breakout season comes from.
        var playingTimeRoleByPlayer: [UUID: PlayerDevelopmentEngine.PlayingTimeRole] = [:]
        for (teamID, roster) in playersByTeam {
            _ = teamID
            let available = roster.filter { !$0.isInjured && !$0.isHoldingOut && !$0.isRetired }
            guard !available.isEmpty else { continue }
            let starterIDs = startingLineupIDs(available: available)
            let roles = PlayerDevelopmentEngine.playingTimeRoles(
                roster: available, starterIDs: starterIDs
            )
            playingTimeRoleByPlayer.merge(roles) { _, new in new }
        }

        // Task #51: `DevelopmentSourceDiag` books what this pass moves, so the
        // ~2 OVR the shipped pipeline develops over the balance harness can be
        // attributed to a pass instead of argued about.
        let xpPopulation = allPlayers.filter {
            $0.teamID != nil && !$0.isInjured && !$0.isHoldingOut
        }
        DevelopmentSourceDiag.measure(DevelopmentSourceDiag.gameXP, xpPopulation) {
            for player in xpPopulation {
                let isMentored = mentoredIDs.contains(player.id)
                let mentorBoost = isMentored ? 1.1 : 1.0
                let clipboardRoom = player.position == .QB
                    && (isMentored || clipboardTeamIDs.contains(player.teamID!))
                // A player with no computed role (roster snapshot missed him)
                // falls back to the practice floor rather than to a free start.
                let role = playingTimeRoleByPlayer[player.id] ?? .depth
                PlayerDevelopmentEngine.applyGameExperience(
                    player,
                    gamesPlayed: 1,
                    gamesStarted: role == .starter ? 1 : 0,
                    experienceBoost: mentorBoost,
                    clipboardRoom: clipboardRoom,
                    startCredit: role.startCreditShare
                )
            }
        }

        perf.lap("fatigue_injury_xp")

        // 7b. R26: weekly training-focus micro-development. Every team runs
        // the same tick; AI teams auto-focus their best young players so the
        // user gains no free edge. Gains are +1 attribute bumps capped by the
        // same potential ceiling the offseason development engine uses.
        var userFocusGains: [TrainingFocusEngine.FocusGain] = []
        var userBreakout: (player: Player, pointsGained: Int)?
        for team in teams {
            let roster = playersByTeam[team.id] ?? []
            guard !roster.isEmpty else { continue }

            if team.id != career.teamID {
                TrainingFocusEngine.autoAssignFocus(roster: roster)
            }
            let teamCoaches = coachesByTeam[team.id] ?? []
            var conversions: [VersatilityDevelopmentEngine.CompletedConversion] = []
            let gains = DevelopmentSourceDiag.measure(DevelopmentSourceDiag.focusTick, roster) {
                TrainingFocusEngine.applyWeeklyFocusTick(
                    roster: roster, coaches: teamCoaches, conversions: &conversions
                )
            }

            // §5.3: a completed conversion is a permanent change to a man's job
            // title — he trained across, banked the familiarity, and his
            // attribute block was rebuilt against the new spot. It was landing
            // silently. One headline per switch, league-wide, plus a note from
            // the staff when it is the user's own player.
            for conversion in conversions {
                lastNewsItems.append(NewsItem(
                    headline: "\(conversion.playerName) moves to \(conversion.to.rawValue)",
                    body: "\(team.fullName) have made it official: \(conversion.summary) "
                        + "The switch had been in the works since he started taking reps there.",
                    category: .playerPerformance,
                    week: week,
                    season: season,
                    relatedTeamID: team.id,
                    relatedPlayerID: conversion.playerID,
                    sentiment: conversion.overallAfter >= conversion.overallBefore ? .positive : .neutral
                ))
                if team.id == career.teamID {
                    lastInboxMessages.append(InboxMessage(
                        sender: .developmentStaff,
                        subject: "Position Change: \(conversion.playerName) is a \(conversion.to.rawValue)",
                        body: "\(conversion.summary)\n\nHe's learned the position well enough that we've "
                            + "moved him across for good — his depth-chart spot, his grades and his "
                            + "development from here all read against \(conversion.to.rawValue). "
                            + "He keeps what he knew at \(conversion.from.rawValue), so he's a genuine "
                            + "swing man if we ever need him back there.",
                        date: "Week \(week), Season \(season)",
                        category: .rosterAnalysis
                    ))
                }
            }

            // Rare breakout leap for a high-potential youngster (max 2/season/team).
            let breakout = DevelopmentSourceDiag.measure(DevelopmentSourceDiag.breakout, roster) {
                TrainingFocusEngine.rollBreakout(roster: roster, season: season, teamID: team.id)
            }
            if let breakout {
                lastNewsItems.append(NewsItem(
                    headline: "Breakout: \(breakout.player.fullName) has arrived",
                    body: "\(team.fullName) \(breakout.player.position.rawValue) \(breakout.player.fullName) has taken a massive leap in practice — coaches say the game has finally slowed down for the \(max(1, breakout.player.yearsPro))-year pro.",
                    category: .playerPerformance,
                    week: week,
                    season: season,
                    relatedTeamID: team.id,
                    relatedPlayerID: breakout.player.id,
                    sentiment: .positive
                ))
            }

            if team.id == career.teamID {
                userFocusGains = gains
                userBreakout = breakout
            }
        }

        // 7c. R26: assemble the weekly Development Report for the user's team
        // (focus gains, R25 mentor pairs, breakouts, stalled players) and
        // drop a digest in the inbox. The report screen keeps the last 10.
        if let playerTeamID = career.teamID {
            let userRoster = playersByTeam[playerTeamID] ?? []
            let report = DevelopmentReportBuilder.buildWeeklyReport(
                roster: userRoster,
                focusGains: userFocusGains,
                breakout: userBreakout,
                week: week,
                season: season
            )
            if !report.isEmpty {
                career.developmentReports = [report] + career.developmentReports
                let focusedCount = userRoster.filter { $0.trainingFocusArea != nil }.count
                lastInboxMessages.append(
                    DevelopmentReportBuilder.inboxMessage(report: report, focusedCount: focusedCount)
                )
            }
        }

        perf.lap("training_focus")

        // 8. Process existing injuries — R28 rehab with variance: the weekly
        // roll can land ahead of schedule, on track, or on a setback. Head
        // trainer skill shifts the odds (no trainer = neutral averages, so
        // quick-sim time-missed parity holds).
        var pendingDecisions = career.pendingReturnDecisions
        for player in allPlayers where player.isInjured {
            let teamTrainer = player.teamID.flatMap { medicalStaffByTeam[$0]?.trainer }
            let result = MedicalEngine.processWeeklyRehab(player: player, trainer: teamTrainer)

            guard player.teamID == career.teamID else { continue }

            // Inbox nudge on notable rehab swings for key players.
            let isNotable = player.overall >= 78 || player.injuryWeeksOriginal >= 4
            if !result.recovered, result.status != .onTrack, isNotable {
                let subject = result.status == .aheadOfSchedule
                    ? "\(player.lastName) ahead of schedule"
                    : "Setback in \(player.lastName)'s rehab"
                let body = result.status == .aheadOfSchedule
                    ? "\(player.fullName)'s \(player.injuryType?.rawValue.lowercased() ?? "injury") rehab is progressing faster than expected — the training staff now projects him back in \(player.injuryWeeksRemaining) week\(player.injuryWeeksRemaining == 1 ? "" : "s")."
                    : "\(player.fullName) had a setback in his \(player.injuryType?.rawValue.lowercased() ?? "injury") rehab this week. Current projection: \(player.injuryWeeksRemaining) week\(player.injuryWeeksRemaining == 1 ? "" : "s") until return."
                lastInboxMessages.append(InboxMessage(
                    sender: .developmentStaff,
                    subject: subject,
                    body: body,
                    date: "Week \(week), Season \(season)",
                    category: .playerIssue,
                    actionDestination: .roster
                ))
            }

            // R28: entering the final rehab week → offer the rush-back call.
            // Ignoring it is always safe (normal recovery next week). AI teams
            // never rush players back.
            if !result.recovered, player.injuryWeeksRemaining == 1,
               !pendingDecisions.contains(where: { $0.playerID == player.id }) {
                pendingDecisions.append(ReturnDecision(
                    playerID: player.id,
                    playerName: player.fullName,
                    injuryTypeRaw: player.injuryType?.rawValue ?? "Injury",
                    season: season,
                    week: week
                ))
                lastInboxMessages.append(InboxMessage(
                    sender: .developmentStaff,
                    subject: "\(player.lastName) nearly ready — return decision",
                    body: "\(player.fullName) (\(player.injuryType?.rawValue ?? "injury")) is one week from full clearance. He could be rushed back for this week's game, but the medical staff warns of elevated re-injury risk and a short conditioning dip. Holding him out one more week is the safe call.\n\nDecide in the Roster screen's Injury Report — if you do nothing, he completes rehab normally.",
                    date: "Week \(week), Season \(season)",
                    category: .playerIssue,
                    actionRequired: true,
                    actionDestination: .roster
                ))
            }
        }
        // Drop stale decisions (player recovered, was rushed back, or left the team).
        pendingDecisions.removeAll { decision in
            guard let player = allPlayers.first(where: { $0.id == decision.playerID }) else { return true }
            return !player.isInjured || player.teamID != career.teamID
        }
        career.pendingReturnDecisions = pendingDecisions

        perf.lap("rehab")

        // 8b. Weekly scheme learning and position training (during season, reduced intensity)
        for team in teams {
            let teamPlayers = playersByTeam[team.id] ?? []
            let teamCoaches = coachesByTeam[team.id] ?? []
            let oc = teamCoaches.first { $0.role == .offensiveCoordinator }
            let dc = teamCoaches.first { $0.role == .defensiveCoordinator }

            // Install year (plan §2.9.2): a team that changed systems this
            // offseason spends the WHOLE season installing, so its in-season
            // practice reps teach at ×1.25 too — not just camp.
            let schemeIntensity = team.schemeInstallSeason == season
                ? 0.5 * VersatilityDevelopmentEngine.schemeInstallIntensityBonus
                : 0.5

            // Anyone who arrived after camp — a trade, a street signing, a
            // promotion off the practice squad — has no dictionary entry for
            // this building's systems at all, and an absent key answers 0 to
            // every familiarity read in `PlaySimulator` (task #54). Idempotent,
            // so the 52 players who were already here cost one lookup each.
            let installedSchemes = Set([
                oc?.offensiveScheme?.rawValue, dc?.defensiveScheme?.rawValue,
            ].compactMap { $0 })

            for player in teamPlayers where !player.isInjured && !player.isHoldingOut {
                VersatilityDevelopmentEngine.seedActiveSchemes(
                    player: player, activeSchemes: installedSchemes
                )

                // Scheme learning (reduced intensity during season)
                if let offScheme = oc?.offensiveScheme, player.position.side == .offense {
                    let gain = VersatilityDevelopmentEngine.learnScheme(
                        player: player, scheme: offScheme.rawValue,
                        coordinator: oc, practiceIntensity: schemeIntensity
                    )
                    let key = offScheme.rawValue
                    player.schemeFamiliarity[key] = min(100, (player.schemeFamiliarity[key] ?? 0) + gain)
                }
                if let defScheme = dc?.defensiveScheme, player.position.side == .defense {
                    let gain = VersatilityDevelopmentEngine.learnScheme(
                        player: player, scheme: defScheme.rawValue,
                        coordinator: dc, practiceIntensity: schemeIntensity
                    )
                    let key = defScheme.rawValue
                    player.schemeFamiliarity[key] = min(100, (player.schemeFamiliarity[key] ?? 0) + gain)
                }

                // Position training (reduced during season)
                if let trainingPos = player.trainingPosition, trainingPos != player.position {
                    let posCoach = teamCoaches.first { coach in
                        CoachingEngine.positionRoleMatch(coachRole: coach.role, playerPosition: trainingPos)
                    }
                    let gain = VersatilityDevelopmentEngine.trainPosition(
                        player: player, targetPosition: trainingPos,
                        positionCoach: posCoach, practiceIntensity: 0.3
                    )
                    let key = trainingPos.rawValue
                    let ceiling = VersatilityDevelopmentEngine.versatilityCeiling(player: player, at: trainingPos)
                    player.positionFamiliarity[key] = min(ceiling, (player.positionFamiliarity[key] ?? 0) + gain)
                }
            }
        }

        // 8b2. R36: the week's practice play. Each week of reps banks one
        // practice week; the play installs into the season's call sheet after
        // 2 weeks — 1 when the OC is a true expert in his scheme (75+).
        if let practicePlay = career.weeklyPracticePlay, let teamID = career.teamID {
            let oc = allCoaches.first {
                $0.teamID == teamID && $0.role == .offensiveCoordinator
            }
            let expertise = oc?.offensiveScheme.map { oc?.expertise(for: $0.rawValue) ?? 20 } ?? 20
            let weeksRequired = expertise >= 75 ? 1 : 2
            career.weeklyPracticeWeeksDone += 1
            if career.weeklyPracticeWeeksDone >= weeksRequired {
                career.installPracticedPlay(practicePlay)
                lastInboxMessages.append(InboxMessage(
                    sender: .developmentStaff,
                    subject: "\(practicePlay.rawValue) is installed",
                    body: "The offense has \(practicePlay.rawValue) down cold after \(weeksRequired) week\(weeksRequired == 1 ? "" : "s") of practice reps\(weeksRequired == 1 ? " — your coordinator taught it in record time" : ""). It's on the call sheet for the rest of the season.",
                    date: "Week \(week), Season \(season)",
                    category: .gamePrep
                ))
            } else {
                lastInboxMessages.append(InboxMessage(
                    sender: .developmentStaff,
                    subject: "Practice report: \(practicePlay.rawValue)",
                    body: "The unit ran \(practicePlay.rawValue) all week. One more week of reps and it's installed.",
                    date: "Week \(week), Season \(season)",
                    category: .gamePrep
                ))
            }
        }

        perf.lap("scheme_learning")

        // 8c. Generate weekly scout reports for the player's team's scouting staff
        //
        // The class is generated at week 9 (below), so in practice this runs
        // weeks 10-18. Until R41 it changed grades on the board every single
        // week with ZERO notification — a season of regional scouting was
        // invisible unless the user happened to reopen the prospect list and
        // compare it against a memory of last week. The digest below is the
        // notification: ONE batched message per week, skipped entirely on a
        // week that produced nothing.
        if let playerTeamID = career.teamID, !currentDraftClass.isEmpty {
            let scouts = fetchAllScouts(modelContext: modelContext).filter {
                $0.teamID == playerTeamID
            }
            if !scouts.isEmpty {
                let before = ScoutingEngine.gradeSnapshot(currentDraftClass)
                let reports = ScoutingEngine.generateWeeklyReports(
                    scouts: scouts,
                    prospects: currentDraftClass,
                    week: week
                )
                ScoutingEngine.applyWeeklyReports(reports, to: &currentDraftClass)

                if let digest = ScoutingEngine.weeklyDigest(
                    prospects: currentDraftClass,
                    before: before,
                    week: week
                ) {
                    lastInboxMessages.append(InboxEngine.weeklyScoutingDigestMessage(
                        digest: digest,
                        season: season
                    ))
                }
            }
        }

        perf.lap("scouting")

        // --- §5.1 Practice squads: reps, rival interest, signings ---
        //
        // Runs on the roster the week just produced (post-injury, post-trade),
        // because that is what makes a poach a poach: a club loses a corner on
        // Sunday and signs somebody's squad corner on Tuesday. The pass is
        // disjoint from every other weekly pass above — squad players carry
        // `teamID == nil`, so the attendance tally, the game-experience pass and
        // the training-focus tick never see them, and this is the only place
        // they develop (`PracticeSquadEngine.applyPracticeReps`).
        //
        // The user's own squad is never raided without notice: a rival files
        // interest one week and signs the following week, which is the window
        // the "promote him first" mail is about.
        let squadWeek = PracticeSquadEngine.runWeeklyPass(
            career: career,
            teams: teams,
            allPlayers: allPlayers
        )
        for loss in squadWeek.userLosses {
            lastInboxMessages.append(InboxEngine.practiceSquadPoachedMessage(
                playerName: loss.playerName,
                position: loss.position.rawValue,
                suitorName: loss.toTeamName,
                suitorAbbr: loss.toAbbreviation,
                dateString: InboxEngine.dateLabel(week: week, season: season, phase: .regularSeason)
            ))
        }
        for warning in squadWeek.warnings {
            lastInboxMessages.append(InboxEngine.practiceSquadPoachWarningMessage(
                playerName: warning.playerName,
                position: warning.position.rawValue,
                suitorName: warning.suitorName,
                suitorAbbr: warning.suitorAbbreviation,
                dateString: InboxEngine.dateLabel(week: week, season: season, phase: .regularSeason)
            ))
        }
        perf.lap("practice_squad")

        // Advance the week counter.
        career.currentWeek += 1

        // Deadline week OPENS here: the week just advanced into is the deadline
        // week, so the career enters the `.tradeDeadline` phase and stays there
        // for the whole week. Trade plan finding S2 — this used to be tagged and
        // untagged on consecutive lines, which made the phase unobservable and
        // left its tasks, owner letter and dashboard tile permanently dead.
        //
        // The letters are delivered NOW, with this advance's other mail, so the
        // user reads "are we buyers or sellers?" while there is still a week to
        // act. (The deadline-week advance itself deliberately keeps generating
        // ordinary regular-season mail — see the `generatePhaseMessages` call
        // above — or these two would arrive again after the deadline had passed.)
        if career.currentWeek == tradeDeadlineWeek {
            career.currentPhase = .tradeDeadline
            if let playerTeamID = career.teamID,
               let playerTeam = teamsByID[playerTeamID] {
                lastInboxMessages.append(contentsOf: InboxEngine.generatePhaseMessages(
                    phase: .tradeDeadline,
                    career: career,
                    team: playerTeam,
                    coaches: allCoaches.filter { $0.teamID == playerTeamID },
                    owner: playerTeam.owner
                ))
            }
        }

        // Wave 2: the other 31 clubs do business with each other EVERY week, not
        // only on deadline day (finding S5: "the other 31 teams never trade with
        // each other, in any phase, ever"). Weeks 1-6 are nearly silent, 7-8 pick
        // up, deadline week below is the flurry — the §5 shape of "8-25 in-season
        // trades, ≥60 % of them in the last three pre-deadline weeks".
        if week < tradeDeadlineWeek {
            runLeagueMarketWindow(
                window: .week(week),
                career: career,
                teams: teams,
                teamsByID: teamsByID,
                allPlayers: allPlayers,
                week: week,
                modelContext: modelContext
            )
        }

        // Deadline week CLOSES here: the deadline passes once the week's games
        // are in the books (real NFL: the Tuesday after them). Runs on the week
        // number rather than the phase so an in-flight save that entered week
        // `tradeDeadlineWeek` under the old code still gets its deadline.
        if week == tradeDeadlineWeek {
            career.currentPhase = .regularSeason

            // Deadline drama at Wave 2 scale: 5-9 AI-vs-AI deals plus whatever
            // the rest of the season under-delivered (`leagueTradeTarget`'s
            // deficit), every one of them real players and picks through the same
            // valuation, validation, ledger and news path the user's own trades
            // use.
            let deadlineResult = runLeagueMarketWindow(
                window: .deadline,
                career: career,
                teams: teams,
                teamsByID: teamsByID,
                allPlayers: allPlayers,
                week: week,
                modelContext: modelContext
            )
            if !deadlineResult.summaries.isEmpty {
                lastInboxMessages.append(
                    TradeValueEngine.deadlineRoundupMessage(
                        trades: deadlineResult.summaries, week: week, season: season
                    )
                )
            }

            // Any offers the user sat on expire at the deadline — and now the
            // user is told so instead of watching them vanish (finding S2).
            let expiredOffers = career.pendingTradeOffers.count
            career.pendingTradeOffers = []
            if expiredOffers > 0 {
                lastInboxMessages.append(InboxEngine.tradeOffersExpiredMessage(
                    count: expiredOffers,
                    week: week,
                    season: season
                ))
            }
        }

        // 9b. Midseason mock draft at week 9 (generate draft class early for projections)
        if week == 9 {
            if !draftClassGenerated {
                currentDraftClass = ScoutingEngine.generateDraftClass(careerID: career.id)
                draftClassGenerated = true
                persistDraftClass(currentDraftClass, to: modelContext)
            }
            currentMockDraft = ScoutingEngine.generateMockDraft(
                prospects: currentDraftClass,
                draftPicks: currentDraftPicks,
                teams: teams,
                players: allPlayers
            )
            ScoutingEngine.updateTeamInterest(
                prospects: &currentDraftClass,
                teams: teams,
                players: allPlayers
            )
            ScoutingEngine.applyMockDraftToProspects(
                prospects: &currentDraftClass,
                mockDraft: currentMockDraft
            )
            recordMockDraftSnapshot("Mid-Season", career: career)

            // R41 drift moment 1 of 4. A regenerated mock is the market's own
            // re-read of the class; nudge the projections toward it so
            // `draftProjection` stops being a number stamped once at generation
            // and never touched again. Zero-sum and bounded to one round — see
            // `applyProjectionDrift`.
            applyMockDrift(career: career, moment: 1, modelContext: modelContext)
        }

        // 9. At season end (week 18): record season history snapshot per player,
        //    then decrement contract years and expire contracts.
        if week == 18 {
            recordSeasonHistory(
                players: allPlayers,
                season: season,
                userTeamID: career.teamID,
                modelContext: modelContext
            )

            // #23: the round career numbers the season just produced. Runs
            // immediately AFTER the snapshot on purpose — a crossing is measured
            // between last season's career total and this one's, and this
            // season's row has to exist for the "after" side to include it.
            announceCareerMilestones(
                career: career,
                season: season,
                allPlayers: allPlayers,
                teamsByID: teamsByID,
                modelContext: modelContext
            )

            // Phase 2 (plan §2.9.1): the season-end morale settlement — record,
            // chemistry, pay vs. market and contract runway, clamped to ±8 so it
            // reads as a verdict on the year rather than a second weekly loop.
            //
            // ORDERING: deliberately BEFORE the contract tick below. The
            // "upcoming free agency" clause keys on `contractYearsRemaining == 1`,
            // which right now means "his deal expires in a few weeks" — after the
            // decrement that same player is a free agent with no team and no
            // salary, and the pay-vs-market term would read as a 0-salary insult.
            for team in teamsByID.values {
                let roster = (playersByTeam[team.id] ?? [])
                    .filter { $0.teamID == team.id && !$0.isRetired }
                guard !roster.isEmpty else { continue }
                LockerRoomEngine.applyMoraleEffects(
                    players: roster,
                    teamWins: team.wins,
                    teamLosses: team.losses,
                    chemistry: LockerRoomEngine.chemistryScore(players: roster),
                    salaryCap: team.salaryCap
                )
            }

            // Task #89 — THE CONTRACT TICK USED TO HAPPEN HERE AS WELL.
            //
            // This block decremented every contract in the league and expired
            // the zeroes, and then `FreeAgencyEngine.executeNewLeagueYear` did
            // exactly the same thing again at the March rollover. Neither was
            // guarded, so **a contract lost two years per league year**: a
            // four-year rookie deal covered two seasons, a one-year veteran deal
            // expired before its owner played a snap of it, and a franchise tag
            // (which the rollover loop skips and this one did not) burned a year
            // it was never supposed to touch.
            //
            // The rollover is the correct home for the tick, and not only
            // because one of the two had to go. The league year is what a
            // contract is denominated in — players become free agents in March,
            // not in the last week of December — and `FreeAgencyStep` is built
            // around that: `finalPush` ("re-sign your own expiring players", and
            // now `resignAIOwnCore` for the other 31 clubs) has to run while
            // those men are still under contract to their own clubs.
            // `FinalPushView`'s own `contractYearsRemaining <= 1` fetch was
            // reading a roster this loop had already emptied, so the screen
            // offered the user next year's expiries and the men actually leaving
            // were gone before he saw them.
            //
            // What changes downstream: an expiring player now keeps his club and
            // his salary through `.coachingChanges` and `.reviewRoster` — so the
            // retirement wave says which club a man retired FROM instead of
            // calling every one of them a free agent — and joins the market at
            // the rollover, which is where `processWashouts`,
            // `settleCompensatoryPicks` and the cap true-up already expect him.
        }

        // Transition to playoffs once all 18 regular season weeks are done.
        if career.currentWeek > 18 {
            career.currentPhase = .playoffs
            career.currentWeek = 19   // Playoff week numbering starts at 19.

            // R32: stage the real wild-card bracket (playoff games used to be
            // phantom weeks with no Game rows — now the champion, the draft
            // order, and career history all read actual results).
            ensurePlayoffGames(forWeek: 19, career: career, modelContext: modelContext)

            // Tell the user where their season stands.
            if let userTeamID = career.teamID {
                let allSeasonGames = fetchAllGamesForSeason(seasonYear: season, modelContext: modelContext)
                let records = StandingsCalculator.calculate(
                    games: allSeasonGames,
                    teams: Array(teamsByID.values)
                )
                var userSeed: Int?
                for conference in Conference.allCases {
                    let seeds = StandingsCalculator.playoffTeams(
                        records: records,
                        teams: Array(teamsByID.values),
                        conference: conference
                    )
                    if let index = seeds.firstIndex(where: { $0.teamID == userTeamID }) {
                        userSeed = index + 1
                    }
                }
                if let seed = userSeed {
                    let byeText = seed == 1
                        ? "As the #1 seed you have a first-round bye — your run starts in the Divisional Round."
                        : "You enter the Wild Card round as the #\(seed) seed."
                    lastInboxMessages.append(InboxMessage(
                        sender: .leagueOffice,
                        subject: "Playoff Berth Clinched",
                        body: "Congratulations — your team is in the postseason. \(byeText)",
                        date: "Week 18, Season \(season)",
                        category: .leagueNotice
                    ))
                }
            }
        }

        perf.lap("transitions")
        perf.finish()
    }

    // MARK: - Private: Locker Room Pulse (R25)

    /// Weekly locker-room tick for the user's team.
    ///
    /// Explainable rules:
    /// - A pending choice event ignored for a full week resolves itself with
    ///   the passive option — not reacting IS a decision the room notices.
    /// - Only one open situation at a time; ~25 % of weeks roll a new event
    ///   from personalities, morale, and the latest result.
    /// - Every event lands in the inbox; choice events flag "action required"
    ///   and deep-link to the Locker Room screen.
    private static func processLockerRoomWeek(
        career: Career,
        team: Team,
        allPlayers: [Player],
        allCoaches: [Coach],
        wonLastGame: Bool?,
        week: Int,
        season: Int
    ) {
        let teamPlayers = allPlayers.filter { $0.teamID == team.id }
        guard !teamPlayers.isEmpty else { return }

        // 1. Stale pending event → passive option auto-applies.
        if let pending = career.pendingLockerRoomEvent,
           pending.season != season || pending.week < week {
            if let passive = pending.options.last {
                let resolved = LockerRoomEngine.resolve(
                    event: pending, option: passive, players: teamPlayers
                )
                appendLockerRoomLog(resolved, career: career)
            }
            career.pendingLockerRoomEvent = nil
        }

        // 2. Never stack two open situations.
        guard career.pendingLockerRoomEvent == nil else { return }

        // 3. Roll a new event (~25 % chance, inside the engine).
        guard let event = LockerRoomEngine.rollWeeklyEvent(
            players: teamPlayers,
            wonLastGame: wonLastGame,
            teamWins: team.wins,
            teamLosses: team.losses,
            week: week,
            season: season
        ) else { return }

        if event.requiresResponse {
            career.pendingLockerRoomEvent = event
        } else {
            appendLockerRoomLog(event, career: career)
        }

        // 4. Surface it in the inbox.
        let oc = allCoaches.first { $0.teamID == team.id && $0.role == .offensiveCoordinator }
        let dc = allCoaches.first { $0.teamID == team.id && $0.role == .defensiveCoordinator }
        let sender: MessageSender =
            oc.map { .offensiveCoordinator(name: $0.fullName) }
            ?? dc.map { .defensiveCoordinator(name: $0.fullName) }
            ?? .media(outlet: "Team Insider")
        let bodySuffix: String = event.requiresResponse
            ? "\n\nThe room is waiting to see how you handle this. Head to the Locker Room to respond."
            : (event.resolutionSummary.map { "\n\n\($0)" } ?? "")
        lastInboxMessages.append(InboxMessage(
            sender: sender,
            subject: event.title,
            body: event.detail + bodySuffix,
            date: "Week \(week), Season \(season)",
            category: .playerIssue,
            actionRequired: event.requiresResponse,
            actionDestination: .lockerRoom
        ))
    }

    /// Prepends a resolved event to the career's locker-room log (cap 12).
    static func appendLockerRoomLog(_ event: LockerRoomEvent, career: Career) {
        var log = career.lockerRoomLog
        log.removeAll { $0.id == event.id }
        log.insert(event, at: 0)
        career.lockerRoomLog = Array(log.prefix(12))
    }

    // MARK: - Private: Holdout Drama (R22)

    /// Weekly tick for any active (unresolved) holdout on the user's team.
    ///
    /// Explainable rules:
    /// - The holdout drags the locker room down: every teammate loses 1
    ///   morale per week, the holdout himself 2.
    /// - `weeksActive` counts regular-season weeks only. At week 3 there is
    ///   a 50% chance the player caves; by week 4 he always reports back
    ///   without a new deal (morale -10).
    /// - If the front office already fixed the money (salary at/above ~95%
    ///   of market, or 2+ contract years now remaining after an extension),
    ///   the holdout auto-resolves as a settlement.
    private static func processHoldoutWeek(
        teamID: UUID,
        allPlayers: [Player],
        week: Int,
        season: Int,
        salaryCap: Int,
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<Holdout>(
            predicate: #Predicate<Holdout> { $0.teamID == teamID && $0.resolvedAt == nil }
        )
        let activeHoldouts = (try? modelContext.fetch(descriptor)) ?? []
        guard !activeHoldouts.isEmpty else { return }

        let teamPlayers = allPlayers.filter { $0.teamID == teamID }

        for holdout in activeHoldouts {
            guard let player = teamPlayers.first(where: { $0.id == holdout.playerID }) else {
                // Player was traded or cut — the standoff is moot.
                holdout.resolvedAt = Date()
                holdout.resolution = .traded
                continue
            }

            // Keep the flag and the record in sync.
            if !player.isHoldingOut { player.isHoldingOut = true }

            // Settlement check: the front office already fixed the money.
            let market = ContractEngine.estimateMarketValue(player: player, salaryCap: salaryCap)
            let paidFairly = market > 0 && Double(player.annualSalary) >= Double(market) * 0.95
            if paidFairly || player.contractYearsRemaining >= 2 {
                player.isHoldingOut = false
                holdout.resolvedAt = Date()
                holdout.resolution = .extended
                lastInboxMessages.append(
                    holdoutSettledMessage(player: player, caved: false, week: week, season: season)
                )
                lastNewsItems.append(NewsItem(
                    headline: "\(player.fullName) holdout ends with new deal",
                    body: "\(player.fullName) is back in the building after the front office reworked his contract. Teammates welcomed the star back at practice.",
                    category: .contract,
                    week: week,
                    season: season,
                    relatedTeamID: teamID,
                    relatedPlayerID: player.id,
                    sentiment: .positive
                ))
                continue
            }

            holdout.weeksActive += 1

            // Locker-room distraction: teammates -1 morale, the holdout -2.
            for teammate in teamPlayers where teammate.id != player.id {
                teammate.morale = max(0, teammate.morale - 1)
            }
            player.morale = max(0, player.morale - 2)

            // Cave check: 50% at week 3, guaranteed at week 4.
            let caves = holdout.weeksActive >= 4 || (holdout.weeksActive == 3 && Bool.random())
            if caves {
                player.isHoldingOut = false
                player.morale = max(0, player.morale - 10)
                holdout.resolvedAt = Date()
                holdout.resolution = .playerCaved
                lastInboxMessages.append(
                    holdoutSettledMessage(player: player, caved: true, week: week, season: season)
                )
                lastNewsItems.append(NewsItem(
                    headline: "\(player.fullName) ends holdout without new deal",
                    body: "After \(holdout.weeksActive) weeks away, \(player.fullName) reported back without the contract he wanted. Sources say the star is deeply unhappy with how the standoff played out.",
                    category: .contract,
                    week: week,
                    season: season,
                    relatedTeamID: teamID,
                    relatedPlayerID: player.id,
                    sentiment: .negative
                ))
            } else {
                // Ongoing drama: the agent turns up the heat via the inbox.
                let agentName = AgentPersona.agentName(for: player.id)
                let demand = ContractEngine.estimateMarketValue(player: player, salaryCap: salaryCap)
                lastInboxMessages.append(InboxMessage(
                    sender: .playerAgent(name: agentName),
                    subject: "\(player.fullName) holdout — week \(holdout.weeksActive)",
                    body: "My client remains away from the team. He is worth $\(demand / 1000)M a year and the locker room knows it. Pay him what he has earned, or this drags on. The longer you wait, the worse it gets for everyone.",
                    date: "Week \(week), Season \(season)",
                    category: .contractRequest,
                    actionRequired: true,
                    actionDestination: .roster
                ))
            }
        }
    }

    /// Inbox message for a holdout that just ended (settlement or cave-in).
    private static func holdoutSettledMessage(
        player: Player,
        caved: Bool,
        week: Int,
        season: Int
    ) -> InboxMessage {
        let agentName = AgentPersona.agentName(for: player.id)
        if caved {
            return InboxMessage(
                sender: .playerAgent(name: agentName),
                subject: "\(player.fullName) reports back",
                body: "My client is ending his holdout and reporting to the team — not because this was resolved, but because he refuses to let his teammates down. Make no mistake: he has not forgotten how this was handled.",
                date: "Week \(week), Season \(season)",
                category: .playerIssue
            )
        }
        return InboxMessage(
            sender: .playerAgent(name: agentName),
            subject: "\(player.fullName) holdout resolved",
            body: "On behalf of my client: thank you for getting this done. \(player.firstName) is back in the building, fully committed, and ready to earn every dollar of the new deal.",
            date: "Week \(week), Season \(season)",
            category: .contractRequest
        )
    }

    // MARK: - Private: Playoffs

    /// Advances one playoff round.
    ///
    /// Week mapping (matches real NFL calendar):
    /// - 19 → Wild Card
    /// - 20 → Divisional Round
    /// - 21 → Conference Championships
    /// - 22 → Pro Bowl week (handled as offseason phase)
    /// - 23 → Super Bowl (handled as offseason phase)
    /// - After Conference Championships → Pro Bowl → Super Bowl → offseason
    private static func advancePlayoffWeek(career: Career, modelContext: ModelContext) {
        let week = career.currentWeek

        // R32: self-heal — make sure this round's bracket exists (covers
        // saves that entered the playoffs before real bracket games landed).
        ensurePlayoffGames(forWeek: week, career: career, modelContext: modelContext)

        // Simulate any unplayed playoff games for this week.
        let unplayedGames = fetchUnplayedGames(
            week: week,
            seasonYear: career.currentSeason,
            isPlayoff: true,
            modelContext: modelContext
        )

        let teamsByID = fetchTeamsByID(modelContext: modelContext)

        // #20: a playoff game the user COACHED is already on the board before
        // this method runs, exactly like a coached regular-season game. Detect
        // it here, before we play anything, so its box score can be folded into
        // the postseason columns below.
        let simulatedResult = playPlayoffGames(
            unplayedGames,
            career: career,
            teamsByID: teamsByID,
            modelContext: modelContext
        )

        // #20: fold this round into `PlayerSeasonHistory`'s postseason columns.
        // Week 18 already wrote every player's row, so the playoffs top up rows
        // that exist rather than creating any.
        recordPostseasonWeek(
            week: week,
            career: career,
            // A playoff game the user COACHED already wrote its own postseason
            // line in `LiveGameEngine.persist` (#41) — only the quick-simmed
            // result flows through here, so nothing can be counted twice.
            boxScore: simulatedResult?.playerStats ?? [],
            modelContext: modelContext
        )

        // R32: user's playoff exit is worth a note (win news comes via the
        // round staging below and the Super Bowl phase).
        if let userTeamID = career.teamID,
           let userGame = unplayedGames.first(where: {
               $0.homeTeamID == userTeamID || $0.awayTeamID == userTeamID
           }),
           let loser = userGame.loserID, loser == userTeamID,
           let winnerID = userGame.winnerID,
           let opponent = teamsByID[winnerID] {
            let roundName = week == 19 ? "Wild Card round" : (week == 20 ? "Divisional Round" : "Conference Championship")
            lastInboxMessages.append(InboxMessage(
                sender: .leagueOffice,
                subject: "Season Over: Eliminated in the \(roundName)",
                body: "The \(opponent.fullName) ended your playoff run \(max(userGame.homeScore ?? 0, userGame.awayScore ?? 0))-\(min(userGame.homeScore ?? 0, userGame.awayScore ?? 0)). Time to regroup — the offseason starts soon.",
                date: "Week \(week), Season \(career.currentSeason)",
                category: .leagueNotice
            ))
        }

        if week >= 21 {
            // R32: conference title games are decided — stage the Super Bowl
            // game so the `.superBowl` phase simulates a real matchup.
            ensurePlayoffGames(forWeek: 22, career: career, modelContext: modelContext)

            // Conference Championships complete → Pro Bowl week next.
            let oldPhase = career.currentPhase
            career.currentPhase = .proBowl
            emitGroupTransitionMessageIfNeeded(
                oldPhase: oldPhase,
                newPhase: .proBowl,
                season: career.currentSeason
            )
        } else {
            career.currentWeek += 1

            // R32: stage the next round from this round's winners so the
            // dashboard can show (and the user can coach) the upcoming game.
            ensurePlayoffGames(forWeek: career.currentWeek, career: career, modelContext: modelContext)
        }
    }

    // MARK: - Private: Playoff Bracket (R32)

    /// Creates the playoff games for one round when they don't exist yet.
    /// Idempotent per (season, week). Seeding uses the same
    /// `StandingsCalculator` rules as the standings screen:
    /// - Week 19 (Wild Card): per conference 2v7, 3v6, 4v5 — seed 1 has a bye.
    /// - Week 20 (Divisional): seed 1 + wild-card winners; best surviving
    ///   seed hosts the worst.
    /// - Week 21 (Conference Championship): divisional winners, better seed hosts.
    /// - Week 22 (Super Bowl): the two conference champions; the better
    ///   regular-season record is the designated "home" side (neutral site).
    ///
    /// If a previous round is missing (legacy saves mid-playoffs), the round
    /// falls back to the top seeds so the bracket always completes.
    private static func ensurePlayoffGames(
        forWeek week: Int,
        career: Career,
        modelContext: ModelContext
    ) {
        guard (19...22).contains(week) else { return }
        let season = career.currentSeason

        let cid = career.id
        let existingDescriptor = FetchDescriptor<Game>(
            predicate: #Predicate<Game> {
                $0.careerID == cid && $0.seasonYear == season && $0.week == week && $0.isPlayoff == true
            }
        )
        let existing = (try? modelContext.fetch(existingDescriptor)) ?? []
        guard existing.isEmpty else { return }

        let teams = fetchAllTeams(modelContext: modelContext)
        let seasonGames = fetchAllGamesForSeason(seasonYear: season, modelContext: modelContext)
        let records = StandingsCalculator.calculate(games: seasonGames, teams: teams)
        let playoffGames = seasonGames.filter { $0.isPlayoff }

        var newGames: [Game] = []
        // Conference champion (winner of week 21) per conference, for the SB.
        var conferenceChampions: [UUID] = []

        for conference in Conference.allCases {
            let seeds = StandingsCalculator.playoffTeams(
                records: records,
                teams: teams,
                conference: conference
            )
            guard seeds.count >= 7 else { continue }
            let seedRank: [UUID: Int] = Dictionary(
                uniqueKeysWithValues: seeds.enumerated().map { ($0.element.teamID, $0.offset) }
            )
            let conferenceTeamIDs = Set(seeds.map(\.teamID))

            /// Winners of the given playoff week belonging to this conference.
            func roundWinners(week: Int) -> [UUID] {
                playoffGames
                    .filter { $0.week == week && conferenceTeamIDs.contains($0.homeTeamID) }
                    .compactMap(\.winnerID)
            }
            /// Sorts surviving teams best seed first.
            func bySeed(_ ids: [UUID]) -> [UUID] {
                ids.sorted { (seedRank[$0] ?? 8) < (seedRank[$1] ?? 8) }
            }

            switch week {
            case 19:
                // 2v7, 3v6, 4v5 (0-based seed indices).
                for (home, away) in [(1, 6), (2, 5), (3, 4)] {
                    newGames.append(Game(
                        seasonYear: season, week: 19,
                        homeTeamID: seeds[home].teamID,
                        awayTeamID: seeds[away].teamID,
                        isPlayoff: true
                    ))
                }

            case 20:
                let wildCardWinners = roundWinners(week: 19)
                let alive: [UUID] = wildCardWinners.count == 3
                    ? bySeed([seeds[0].teamID] + wildCardWinners)
                    : seeds.prefix(4).map(\.teamID)   // legacy-save fallback
                guard alive.count >= 4 else { continue }
                newGames.append(Game(
                    seasonYear: season, week: 20,
                    homeTeamID: alive[0], awayTeamID: alive[3], isPlayoff: true
                ))
                newGames.append(Game(
                    seasonYear: season, week: 20,
                    homeTeamID: alive[1], awayTeamID: alive[2], isPlayoff: true
                ))

            case 21:
                let divisionalWinners = roundWinners(week: 20)
                let alive: [UUID] = divisionalWinners.count == 2
                    ? bySeed(divisionalWinners)
                    : seeds.prefix(2).map(\.teamID)   // legacy-save fallback
                guard alive.count >= 2 else { continue }
                newGames.append(Game(
                    seasonYear: season, week: 21,
                    homeTeamID: alive[0], awayTeamID: alive[1], isPlayoff: true
                ))

            case 22:
                let titleGameWinners = roundWinners(week: 21)
                if let champion = titleGameWinners.first {
                    conferenceChampions.append(champion)
                } else if let topSeed = seeds.first {
                    conferenceChampions.append(topSeed.teamID)   // fallback
                }

            default:
                break
            }
        }

        // Super Bowl: cross-conference — better regular-season record "hosts".
        if week == 22, conferenceChampions.count == 2 {
            let recordByID = Dictionary(uniqueKeysWithValues: records.map { ($0.teamID, $0) })
            let sorted = conferenceChampions.sorted {
                (recordByID[$0]?.winPercentage ?? 0) > (recordByID[$1]?.winPercentage ?? 0)
            }
            newGames.append(Game(
                seasonYear: season, week: 22,
                homeTeamID: sorted[0], awayTeamID: sorted[1], isPlayoff: true
            ))
        }

        for game in newGames {
            game.careerID = career.id
            modelContext.insert(game)
        }
    }

    // MARK: - Private: Offseason Phase Advancement

    /// Steps the career forward to the next offseason phase in calendar order.
    /// When the cycle reaches `.regularSeason`, a new season is bootstrapped.
    private static func advanceOffseasonPhase(career: Career, modelContext: ModelContext) {
        let currentPhase = career.currentPhase
        let nextPhase = phase(after: currentPhase)

        let teams = fetchAllTeams(modelContext: modelContext)
        let allPlayers = fetchAllPlayers(modelContext: modelContext)
        let allCoaches = fetchAllCoaches(modelContext: modelContext)
        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })

        // Plan §5 in-flight save migration. Runs BEFORE the phase switch so the
        // `!draftClassGenerated` generation guards below see the regenerated
        // class, and so a user entering the combine/pro-days/draft phases from an
        // old save gets a v2 board instead of the pre-overhaul one.
        backfillLegacyLearning(players: allPlayers)
        backfillLegacyCompetitiveness(players: allPlayers)
        backfillLegacyFaces(career: career, players: allPlayers, coaches: allCoaches)
        migrateLegacyDraftClassIfNeeded(career: career, modelContext: modelContext)
        // Same self-heal as the in-season path: the offseason trade windows read
        // the same pick pool (trade plan finding S1).
        ensureFuturePickHorizon(career: career, teams: teams, modelContext: modelContext)

        // --- Run engine logic for the CURRENT phase before transitioning ---
        switch currentPhase {

        case .superBowl:
            // Simulate the Super Bowl game (moved here from playoffs to support Pro Bowl week)
            let sbGames = fetchUnplayedGames(
                week: 22,
                seasonYear: career.currentSeason,
                isPlayoff: true,
                modelContext: modelContext
            )
            // #20: same treatment as every other playoff round — the user's own
            // final is play-by-play so it leaves a box score, the AI final stays
            // score-only, and a final he coached live is read back out of the
            // live engine's result.
            let sbSimulatedResult = playPlayoffGames(
                sbGames,
                career: career,
                teamsByID: teamsByID,
                modelContext: modelContext
            )
            for game in sbGames {
                updateTeamRecords(game: game, teamsByID: teamsByID)
            }
            recordPostseasonWeek(
                week: 22,
                career: career,
                boxScore: sbSimulatedResult?.playerStats ?? [],
                modelContext: modelContext
            )
            // The bracket is complete: model the playoff lines for the 13 clubs
            // the sim never box-scored, now that every game count is final.
            finalizePostseasonHistory(
                career: career,
                userTeamID: career.teamID,
                modelContext: modelContext
            )

            // Generate championship news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .superBowl,
                career: career,
                teams: teams
            )

            // R31: end-of-season owner review — goals vs results, verdict,
            // and consequences (bonus budget next season / warning / firing).
            // Runs here while the final records are still intact.
            if let playerTeamID = career.teamID,
               let playerTeam = teamsByID[playerTeamID],
               let owner = playerTeam.owner {
                // Old saves may predate persisted goals — fall back to the
                // same deterministic generation the Goals screen shows.
                let baseGoals = career.ownerSeasonGoals.isEmpty
                    ? OwnerGoalsEngine.generateSeasonGoals(team: playerTeam, owner: owner, career: career)
                    : career.ownerSeasonGoals
                let evaluated = OwnerGoalsEngine.evaluateGoalProgress(
                    goals: baseGoals,
                    team: playerTeam,
                    career: career
                )
                career.ownerSeasonGoals = evaluated

                let review = OwnerPersonaEngine.evaluateSeason(
                    owner: owner,
                    team: playerTeam,
                    career: career,
                    goals: evaluated
                )
                career.ownerSeasonReview = review
                lastInboxMessages.append(
                    OwnerPersonaEngine.reviewInboxMessage(review: review, ownerName: owner.name)
                )
                if review.verdict == .fired {
                    wasFired = true
                }
            }

            // R32: close the book on the season — champion, user record, and
            // MVP into career history; increment the career counters
            // (totalWins/playoffAppearances/championships) that the dashboard
            // and fired-summary screens read but nothing ever wrote before.
            recordSeasonSummary(
                career: career,
                teams: teams,
                teamsByID: teamsByID,
                modelContext: modelContext
            )

            // TODO §5.2: freeze the 32-club season row while the staff is still
            // the staff that coached it. Deliberately HERE and not in the
            // catch-up pass — `TeamSeasonArchiveBuilder.backfill` can recover
            // records and ratings from the game log, but coaches carry only
            // their current job, so an archive written after the carousel
            // credits last season to whoever holds the seat now. Idempotent per
            // (career, team, season): a re-entered phase is a fetch and a return.
            TeamSeasonArchiveBuilder.record(career: career, teams: teams, modelContext: modelContext)

        case .proBowl:
            // Simulate Pro Bowl game (AFC vs NFC, simple random result)
            let proBowlScore = simulateGameScore()
            let afcScore = proBowlScore.home
            let nfcScore = proBowlScore.away
            let afcWon = afcScore > nfcScore

            // Generate Pro Bowl selections — top-rated players from each conference
            var proBowlSelections: [String] = []
            if let playerTeamID = career.teamID,
               let playerTeam = teamsByID[playerTeamID] {
                let teamPlayers = allPlayers.filter { $0.teamID == playerTeamID }
                let proBowlers = teamPlayers
                    .sorted { $0.overall > $1.overall }
                    .prefix(3)
                for p in proBowlers {
                    proBowlSelections.append("\(p.firstName) \(p.lastName)")
                }

                // Generate inbox message about Pro Bowl selections
                let selectionsText = proBowlSelections.isEmpty
                    ? "None of your players were selected."
                    : "Pro Bowl selections: \(proBowlSelections.joined(separator: ", "))."
                let resultText = afcWon
                    ? "AFC won \(afcScore)-\(nfcScore)."
                    : "NFC won \(nfcScore)-\(afcScore)."

                let proBowlMessage = InboxMessage(
                    sender: .leagueOffice,
                    subject: "Pro Bowl Results",
                    body: "\(resultText) \(selectionsText)",
                    date: "Offseason - Pro Bowl, Season \(career.currentSeason)",
                    category: .leagueNotice
                )
                lastInboxMessages.append(proBowlMessage)
            }

            // Awards and Pro Bowl news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .proBowl,
                career: career,
                teams: teams
            )

            // Vaihe 5: Career arc evaluation — refresh trueGrade for every drafted
            // player and surface "Hidden Gem" flashbacks for the user's team.
            // Runs once per offseason at the proBowl → coachingChanges boundary.
            let gemFlashbacks = CareerArcEngine.evaluateAllDraftedPlayers(
                currentSeason: career.currentSeason,
                userTeamID: career.teamID,
                modelContext: modelContext
            )
            for flashback in gemFlashbacks {
                let body = """
                \(flashback.headline)

                Originally selected #\(flashback.draftPickNumber) in the \(flashback.draftYear) draft \
                with a Public Grade of \(flashback.publicGrade.rawValue), \(flashback.playerName) is \
                now grading out as a \(flashback.trueGrade.rawValue) (\(flashback.trueGrade.qualifier)) \
                pick — a true Hidden Gem.
                """
                let gemMessage = InboxMessage(
                    sender: .media(outlet: "NFL Network"),
                    subject: "Hidden Gem: \(flashback.playerName)",
                    body: body,
                    date: "Offseason - Pro Bowl, Season \(career.currentSeason)",
                    category: .scoutingReport
                )
                lastInboxMessages.append(gemMessage)
            }

        case .coachingChanges:
            var newMessages: [InboxMessage] = []

            // R32: the annual retirement wave — the offseason's first move,
            // before free agency, so departures actually leave the league
            // (rostered players, holdouts, AND unsigned free agents).
            // Star ceremonies, user-team farewells, and the Hall of Fame
            // induction class all come out of this pass.
            processPlayerRetirements(
                career: career,
                teamsByID: teamsByID,
                allPlayers: allPlayers,
                modelContext: modelContext
            )

            // Task #84: and once every couple of leagues-years, the door swings
            // the other way — a recently retired star un-retires to chase a ring
            // with a contender. Runs right after the wave so a man cannot retire
            // and un-retire in the same offseason (`seasonsAway >= 1`).
            processComeback(
                career: career,
                teams: teams,
                allPlayers: allPlayers,
                modelContext: modelContext
            )

            // Generate draft class early so prospects are visible during offseason
            if !draftClassGenerated {
                currentDraftClass = ScoutingEngine.generateDraftClass(careerID: career.id)
                draftClassGenerated = true
                // First season: apply pre-scouted data
                let totalWins = teams.reduce(0) { $0 + $1.wins }
                let totalLosses = teams.reduce(0) { $0 + $1.losses }
                if totalWins == 0 && totalLosses == 0 {
                    ScoutingEngine.applyPreScoutedData(prospects: &currentDraftClass)
                }
                persistDraftClass(currentDraftClass, to: modelContext)
            }

            // R30: Evaluate coaching-tree alumni against last season's results.
            // Alumni whose new teams won big flip to "successful" — the tree
            // grows the user's reputation (small legacy bonus, capped at +2).
            evaluateCoachingTreeAlumni(
                career: career,
                teams: teams,
                allCoaches: allCoaches
            )

            // R30: fresh offseason, fresh carousel feed.
            career.coachCarouselLog = []

            // Check coordinator poaching for all teams (legacy system)
            let coordinatorRoles: Set<CoachRole> = [
                .offensiveCoordinator, .defensiveCoordinator, .specialTeamsCoordinator
            ]
            for team in teams {
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                var poached = CoachingEngine.checkCoordinatorPoaching(
                    coaches: teamCoaches,
                    teamWins: team.wins
                )
                // R30: the user's coordinators only leave with the user's
                // consent (interview-request flow) — position coaches can
                // still be hired away silently.
                if team.id == career.teamID {
                    poached.removeAll { coordinatorRoles.contains($0.role) }
                }
                // Poached coaches leave the team
                for coach in poached {
                    if team.id == career.teamID {
                        var tree = career.coachingTree
                        CoachRelationshipEngine.recordDeparture(
                            tree: &tree.entries,
                            coach: coach,
                            event: "departed_other",
                            season: career.currentSeason,
                            destination: "Hired away by another organization"
                        )
                        career.coachingTree = tree
                    }
                    coach.teamID = nil
                    CoachChurnDiag.record(CoachChurnDiag.detached)
                }
            }

            // HC promotion poaching (NFL-realistic coordinator-to-HC pipeline).
            // R30: AI teams only — the user's coordinators go through the
            // interview-request flow instead of vanishing overnight.
            for team in teams where team.id != career.teamID {
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                let poached = CoachingEngine.checkHCPromotionPoaching(
                    coaches: teamCoaches,
                    teamWins: team.wins
                )
                for coach in poached {
                    coach.teamID = nil
                    CoachChurnDiag.record(CoachChurnDiag.detached)
                }
            }

            // Develop all coaches based on their team's performance
            for team in teams {
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                let hc = teamCoaches.first { $0.role == .headCoach }
                let ahc = teamCoaches.first { $0.role == .assistantHeadCoach }
                for coach in teamCoaches {
                    CoachingEngine.developCoach(coach, teamWins: team.wins, headCoach: hc, assistantHC: ahc)
                }
            }
            // Develop unattached coaches with neutral win total.
            //
            // `!isRetired` because "unattached" and "gone" are the same `teamID`:
            // without it every dead row in the store kept drawing a season of XP
            // and a birthday forever, so a man who retired at 65 in season 2 was
            // 71 by season 8, his aged portrait kept sliding in archived news,
            // and the pass below re-rolled his retirement every year.
            for coach in allCoaches where coach.teamID == nil && !coach.isRetired {
                CoachingEngine.developCoach(coach, teamWins: 8)
            }

            // Coach retirement (65+)
            for coach in allCoaches where coach.age >= 65 && !coach.isRetired {
                if CoachDevelopmentEngine.shouldRetire(coach: coach) {
                    // Generate retirement news if it's the player's team
                    if coach.teamID == career.teamID {
                        let message = InboxMessage(
                            sender: .leagueOffice,
                            subject: "\(coach.fullName) Announces Retirement",
                            body: "\(coach.fullName), your \(coach.role.rawValue), has announced their retirement after \(coach.yearsExperience) seasons in coaching. Their position is now vacant.",
                            date: "Offseason - Coaching Changes, Season \(career.currentSeason)",
                            category: .staffUpdate
                        )
                        newMessages.append(message)

                        // R30: retirements close out the coaching-tree entry.
                        var tree = career.coachingTree
                        CoachRelationshipEngine.recordDeparture(
                            tree: &tree.entries,
                            coach: coach,
                            event: "retired",
                            season: career.currentSeason
                        )
                        career.coachingTree = tree
                    }
                    coach.teamID = nil  // Remove from team
                    // Phase 4 faces: he is done coaching, so the portrait goes
                    // back to the pool (the row stays for the coaching tree and
                    // history, and still renders his face). `isRetired` is what
                    // keeps `FaceLibrary.backfill` from re-claiming it on the
                    // next advance — without it the coach half of the pool
                    // leaked a few hundred ids over a long career.
                    coach.isRetired = true
                    coach.departureReason = "retired"
                    FaceLibrary.shared.releaseFace(coach.faceID, heldBy: coach.id)
                    CoachChurnDiag.record(CoachChurnDiag.retiredAge)
                    CoachChurnDiag.record(CoachChurnDiag.detached)
                }
            }

            // MARK: R30 — Black Monday: the league-wide coaching carousel.
            // Struggling AI teams fire their HCs (record + R29 hot-seat data),
            // vacancies fill from rising coordinators and recycled HCs, and
            // the coordinator seats those promotions empty fill in a chain.
            let userTeamWins = teams.first { $0.id == career.teamID }?.wins ?? 0
            let carousel = CoachCarouselEngine.runBlackMonday(
                teams: teams,
                allCoaches: allCoaches,
                userTeamID: career.teamID,
                userTeamWins: userTeamWins,
                hotSeatTeamIDs: career.leagueNarrative?.hotSeatReported ?? [],
                season: career.currentSeason
            )
            for coach in carousel.newCoaches {
                coach.careerID = career.id
                modelContext.insert(coach)
            }
            lastNewsItems.append(contentsOf: carousel.news)
            career.coachCarouselLog = Array(carousel.moves.reversed()) + career.coachCarouselLog

            // R30: an AI team wants to interview one of the user's
            // coordinators for its HC vacancy — the user decides in the
            // Staff view (allow / block). Expires at the Combine if ignored.
            if let request = carousel.interviewRequest {
                career.pendingInterviewRequest = request
                newMessages.append(InboxMessage(
                    sender: .leagueOffice,
                    subject: "Interview Request: \(request.coachName)",
                    body: "The \(request.requestingTeamName) have requested permission to interview your \(request.coachRole.displayName.lowercased()) \(request.coachName) for their head coach vacancy. Your team's success has made your staff hot names around the league.\n\nGo to your Coaching Staff screen to allow or block the interview. If you allow it and \(request.coachName) is hired, they join your coaching tree — and you will receive a compensatory 3rd round draft pick.",
                    date: "Offseason - Coaching Changes, Season \(career.currentSeason)",
                    category: .staffUpdate,
                    actionRequired: true,
                    actionDestination: .coachingStaff
                ))
            }

            // R32: after the carousel has settled, AI teams fill every
            // remaining staff vacancy so league coaching quality holds up
            // across a 10-season career.
            refillAIStaffVacancies(
                career: career,
                teams: teams,
                modelContext: modelContext
            )

            // Task #96 — the profession's exit door, and the LAST hiring-related
            // pass of the offseason on purpose: everyone the carousel and the
            // refill above could place is already placed, so whoever is still
            // unattached here is genuinely out of work this year. A man who
            // stays out of work long enough takes the college job or the booth,
            // which is what stops the living-coach count (and with it the face
            // catalog) from growing forever.
            //
            // Re-fetched rather than reusing `allCoaches`: the two passes above
            // inserted rows that must be counted as EMPLOYED, not charged a year
            // on the bench for having existed for one line of code.
            CoachMarketEngine.settleUnemployment(
                coaches: fetchAllCoaches(modelContext: modelContext),
                season: career.currentSeason
            )

            // Increment scout seasonsInRole for familiarity bonus
            let allScouts = fetchAllScouts(modelContext: modelContext)
            for scout in allScouts {
                scout.seasonsInRole += 1
            }

            // Declaration period: underclassmen declare or withdraw from draft
            if !currentDraftClass.isEmpty {
                // A save that ran its window before `declarationStatusRaw`
                // existed hits the generator's idempotency guard below and
                // returns without writing anything, so heal it first.
                ScoutingEngine.backfillDeclarationStatus(&currentDraftClass)
                let declarationNews = ScoutingEngine.generateDeclarations(
                    prospects: &currentDraftClass,
                    seed: ScoutingEngine.cycleSeed(
                        careerID: career.id,
                        season: career.currentSeason,
                        salt: ScoutingEngine.CycleSalt.declarations
                    )
                )
                for item in declarationNews {
                    let sentiment: NewsSentiment = item.isDeclaration ? .neutral : .positive
                    let body: String
                    if item.isDeclaration {
                        body = "\(item.name) has officially declared for the upcoming NFL Draft, forgoing remaining college eligibility."
                    } else if item.isShock {
                        // R41: the annual shock. One name off the top of the
                        // PUBLIC board comes out every January and the round
                        // reshuffles behind him. The body says nothing the
                        // headline has not already said about his projection —
                        // the headline is phrased from his own `draftProjection`
                        // and this line must not contradict it.
                        body = "\(item.name) was one of the names at the top of this class and is not in this draft. Front offices that had spent the season building a plan around him are starting over, and the men behind him at the position just moved up."
                    } else {
                        body = "\(item.name) has decided to withdraw from the draft and return to college for another season."
                    }
                    lastNewsItems.append(NewsItem(
                        headline: item.headline,
                        body: body,
                        category: .draft,
                        week: 0,
                        season: career.currentSeason,
                        sentiment: item.isShock ? .negative : sentiment
                    ))
                }

                // R41 — Senior Bowl. Late January, after declarations (the
                // invite list is the declared senior board) and a month before
                // the combine. `ScoutingPhase.seniorBowl` has carried its 0.55
                // confidence level and its slot in the phase sort order since
                // the scouting system shipped; this is the event that finally
                // files one. Like the combine it is a league event, so it runs
                // whether or not this club sends staff — and it is idempotent,
                // so re-entering the phase cannot hold a second week.
                runSeniorBowlEvent(career: career, modelContext: modelContext)
            }

            // Finding S9 — the department checks in at every phase boundary.
            sendDraftCycleHeartbeat(career: career, phase: .coachingChanges)

            lastInboxMessages.append(contentsOf: newMessages)

            lastNewsItems.append(contentsOf: NewsGenerator.generateOffseasonNews(
                phase: .coachingChanges,
                career: career,
                teams: teams
            ))

        case .combine:
            // Generate draft class if not yet generated
            if !draftClassGenerated {
                currentDraftClass = ScoutingEngine.generateDraftClass(careerID: career.id)
                draftClassGenerated = true

                // First season: apply pre-scouted data from previous GM's staff
                let isFirstSeason = career.totalWins == 0 && career.totalLosses == 0
                if isFirstSeason {
                    ScoutingEngine.applyPreScoutedData(prospects: &currentDraftClass)
                }
                persistDraftClass(currentDraftClass, to: modelContext)
            }

            // Combine results are NOT auto-generated here — they should only be
            // generated when the user presses "Send Scouts to Combine" in ScoutingHubView.

            // R41 — the combine finally reaches the news feed.
            //
            // `generateCombineMedia` has always named real risers, fallers,
            // standouts and surprises and stamped them on the prospects, and the
            // feed showed three hardcoded headlines about players who did not
            // exist instead ("the consensus top quarterback", "a 280-pound
            // defensive tackle") — men with no name, no college and no row on
            // any board. The digest is rebuilt from what is stored on the class,
            // so these headlines always agree with the Combine screen.
            //
            // Order is load-bearing: the media read goes out, the drift moves
            // the board on it, and the mock is then regenerated against the
            // board as it now stands.
            let combineMentions = ScoutingEngine.combineMediaDigest(prospects: currentDraftClass)
            if !combineMentions.isEmpty {
                let invitees = currentDraftClass.filter { $0.combineInvite }.count
                lastNewsItems.append(contentsOf: NewsGenerator.combineMediaNews(
                    mentions: combineMentions,
                    inviteCount: invitees,
                    season: career.currentSeason
                ))
                if let digest = InboxEngine.combineMediaDigestMessage(
                    mentions: combineMentions,
                    dateString: InboxEngine.dateLabel(
                        week: 0, season: career.currentSeason, phase: .combine
                    )
                ) {
                    lastInboxMessages.append(digest)
                }
            }

            // The combine is the loudest information event of the cycle, so it
            // gets the big shove (up to 2 rounds, up to 18 riser/faller pairs)
            // where the four mock moments each get a nudge.
            if !currentDraftClass.isEmpty {
                let moves = ScoutingEngine.applyProjectionDrift(
                    prospects: &currentDraftClass,
                    pressure: ScoutingEngine.combinePressure(currentDraftClass),
                    maxShift: 2,
                    maxPairs: 18,
                    seed: ScoutingEngine.cycleSeed(
                        careerID: career.id,
                        season: career.currentSeason,
                        salt: ScoutingEngine.CycleSalt.combineDrift
                    )
                )
                if !moves.isEmpty {
                    lastNewsItems.append(contentsOf: NewsGenerator.projectionDriftNews(
                        moves: moves,
                        season: career.currentSeason
                    ))
                    persistDraftClass(currentDraftClass, to: modelContext)
                }
            }

            // Post-combine mock draft update
            currentMockDraft = ScoutingEngine.generateMockDraft(
                prospects: currentDraftClass,
                draftPicks: currentDraftPicks,
                teams: teams,
                players: allPlayers
            )
            ScoutingEngine.updateTeamInterest(
                prospects: &currentDraftClass,
                teams: teams,
                players: allPlayers
            )
            ScoutingEngine.applyMockDraftToProspects(
                prospects: &currentDraftClass,
                mockDraft: currentMockDraft
            )
            recordMockDraftSnapshot("Combine", career: career)

            // R41 drift moment 2 of 4.
            applyMockDrift(career: career, moment: 2, modelContext: modelContext)

            // Task #78 — the first character wave. The combine is where the
            // interviews happen and where the screenings are run, so it is
            // where the first off-field questions surface.
            applyCharacterFindingWave(
                career: career,
                pool: ScoutingEngine.combineCharacterFindings,
                salt: ScoutingEngine.CycleSalt.combineCharacter,
                phase: .combine,
                modelContext: modelContext
            )

            // R30: an unanswered interview request expires here — the club
            // moved on, the coordinator stays (no hard feelings).
            if let request = career.pendingInterviewRequest {
                if let reqTeam = teams.first(where: { $0.id == request.requestingTeamID }),
                   !allCoaches.contains(where: { $0.teamID == reqTeam.id && $0.role == .headCoach }),
                   let newHC = CoachingEngine.generateCoachCandidates(role: .headCoach, count: 1).first {
                    newHC.teamID = reqTeam.id
                    newHC.hireSeasonYear = career.currentSeason
                    newHC.contractYearsRemaining = 4
                    // Phase 4 faces: claim the candidate's preview portrait —
                    // they are in the league now (see `CoachCarouselEngine`).
                    // Gender-matched, or the claim's fast path would keep a
                    // wrong-gender preview id.
                    newHC.faceID = FaceLibrary.shared.claimFace(
                        newHC.faceID, personID: newHC.id,
                        role: .coach, age: newHC.age, position: nil,
                        gender: FacePersonGender(tag: newHC.gender)
                    )
                    newHC.careerID = career.id
                    modelContext.insert(newHC)
                    CoachChurnDiag.record(CoachChurnDiag.generated)
                    lastNewsItems.append(NewsItem(
                        headline: "\(reqTeam.fullName) name \(newHC.fullName) head coach",
                        body: "With their interview request for \(request.coachName) left unanswered, the \(reqTeam.fullName) have moved on and hired \(newHC.fullName) as their next head coach.",
                        category: .coachingChange,
                        week: 0,
                        season: career.currentSeason,
                        relatedTeamID: reqTeam.id,
                        sentiment: .neutral
                    ))
                }
                lastInboxMessages.append(InboxMessage(
                    sender: .leagueOffice,
                    subject: "Interview Window Closed: \(request.coachName)",
                    body: "The \(request.requestingTeamName) have withdrawn their interview request for \(request.coachName) and filled their head coach vacancy elsewhere. \(request.coachName) remains on your staff.",
                    date: "Offseason - Combine, Season \(career.currentSeason)",
                    category: .staffUpdate
                ))
                career.pendingInterviewRequest = nil
            }

            lastNewsItems.append(contentsOf: NewsGenerator.generateOffseasonNews(
                phase: .combine,
                career: career,
                teams: teams
            ))

            sendDraftCycleHeartbeat(career: career, phase: .combine)

        case .freeAgency:
            // FA engine logic (contract decrements, AI signings, cap growth)
            // is now handled step-by-step within the FA flow views:
            //   - executeNewLeagueYear (contracts + cap growth)
            //   - FAWeeklyView (player offers + AI round signings)
            //   - simulateRemainingFA (skip button)
            //
            // If the player skipped the FA phase, run the old logic as a
            // fallback.
            //
            // The test is "has the rollover happened for this league year", not
            // "is the flow still on its first screen". Those two agree for the
            // common case (never entered FA at all), but they came apart in one
            // real hole: `FinalPushView` sets the step to `.newLeagueYear` and
            // `NewLeagueYearView` is what actually runs the rollover, so a user
            // who left the flow between those two ran NO rollover and the old
            // step-only condition did not catch it — contracts never ticked,
            // nobody hit the market, and the offseason continued as if March had
            // not happened. `Career.lastRolloverSeason` makes the miss detectable
            // from the save, mirroring `restoreDraftClassIfNeeded`.
            //
            // Still gated on the step so a career that has demonstrably moved
            // PAST the rollover (`capReview`/`signing`/`complete`) is never
            // re-run, which is what keeps a save written before
            // `lastRolloverSeason` existed (stamp 0) from healing something that
            // already happened. `executeNewLeagueYear` carries its own guard on
            // top of this one.
            let rolloverPending = career.lastRolloverSeason < career.currentSeason
            let step = FreeAgencyStep(rawValue: career.freeAgencyStep)
            let beforeRollover = step == nil || step == .finalPush || step == .newLeagueYear
            if rolloverPending, beforeRollover {
                // Player never entered FA — auto-run everything
                let summary = FreeAgencyEngine.executeNewLeagueYear(
                    allPlayers: allPlayers,
                    allTeams: teams,
                    playerTeamID: career.teamID ?? UUID(),
                    modelContext: modelContext,
                    career: career
                )
                _ = summary
            }

            // Task #93 F9 — the market's mop-up, and the ONLY place the bulk
            // market is now run from this phase.
            //
            // It used to fire only inside the `rolloverPending` branch above,
            // i.e. only for a career that never opened the free-agency screens
            // at all. A career that PLAYED free agency therefore closed the
            // market after `FAWeeklyView`'s six rounds — whose final round has a
            // raw-60-OVR floor — so every free agent below 60 in the league went
            // the whole offseason without a single AI bid and was handed straight
            // to `processWashouts` below. That is a few hundred men a league
            // year, all of them the same shape (young, cheap, unproven), leaving
            // football for good because nobody was allowed to offer them a
            // minimum deal.
            //
            // Unconditional on the step, and idempotent through
            // `simulateRemainingFAOnce`'s per-league-year stamp: the fallback
            // above, `FAWeeklyView`'s Skip button and this call are three doors
            // into one market, and the stamp is what keeps them from opening it
            // more than once. The stamp lives on `Career` (not in a static
            // table) precisely because Skip → quit → relaunch → Advance Week
            // reaches this line in a brand-new process.
            FreeAgencyEngine.simulateRemainingFAOnce(
                allPlayers: allPlayers,
                allTeams: teams,
                playerTeamID: career.teamID,
                modelContext: modelContext,
                capMode: career.capMode,
                career: career
            )

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .freeAgency,
                career: career,
                teams: teams
            )

            // Phase 2 (plan §5 stage 6): the washout pass. The market has now
            // closed, so an empty `teamID` finally means what the term needs it
            // to mean — nobody signed him. Deliberately NOT part of the
            // `.coachingChanges` retirement wave three phases back: since task
            // #89 removed the duplicate week-18 contract tick, an expiring
            // player is still ON his club at that point and would not be seen as
            // unsigned at all; before it, he was sitting at `teamID == nil` and
            // would have been washed out before the market ever opened.
            processWashouts(
                career: career,
                allPlayers: allPlayers,
                modelContext: modelContext
            )

            // R23 — Compensatory picks: the market has closed, settle the
            // departure ledger into extra round 3-7 picks for net FA losers.
            settleCompensatoryPicks(
                career: career,
                teams: teams,
                allPlayers: allPlayers,
                modelContext: modelContext
            )

            // #103 §5.7: the post-FA mock used to be regenerated HERE, keyed
            // `"Post-FA"`, and it was the wrong side of the calendar. Moment 3
            // is the mock the league reads AFTER the pro-day circuit — a mock
            // that has not seen the campus numbers is a mock about February —
            // so the whole block moved down to the pro-days phase-ENTRY hook
            // (`if nextPhase == .proDays`, below the switch) and the key became
            // `"Post-Pro-Day"`. That hook fires in THIS same call, immediately
            // after this case: free agency has reshaped 32 rosters, so
            // `updateTeamInterest` is exactly as correct as it was; it now also
            // reads the circuit, which runs in the same hook a few lines above
            // it. The drift budget is unchanged: four moments, same salts, no
            // fifth mock — and the entry hook is a whole phase away from
            // MOMENT 4, which is the point.

            sendDraftCycleHeartbeat(career: career, phase: .freeAgency)

        case .proDays:
            // #103 §5.7 FIXUP — this case is deliberately empty.
            //
            // The switch runs the CURRENT phase's engine logic BEFORE the
            // transition, so a `case .proDays:` body executes at pro-days
            // EXIT — the same `advanceOffseasonPhase` call that enters
            // `.draft` and fires MOMENT 4 out of `prepareDraftOrder`. Holding
            // the circuit, the attrition pass, the AI Top-30 sweep and MOMENT
            // 3 here meant both public mocks landed in one week advance (the
            // Pre-Draft mock overwrote the Post-Pro-Day one milliseconds after
            // it was stored) and that NONE of the things the pro-day stages
            // ask the user to read existed while he was standing in the phase.
            //
            // The whole block therefore lives in the phase-ENTRY hook below
            // (`nextPhase == .proDays`). Nothing belongs at pro-days exit.
            break

        case .reviewRoster:
            // Reset roster evaluation flags for the new Review Roster phase
            CareerScopedDefaults.set(false, "rosterEvaluationConfirmed")
            CareerScopedDefaults.set(false, "franchiseTagVisited")

            // Generate owner demands based on weakest position groups (#248)
            if let playerTeamID = career.teamID,
               let playerTeam = teamsByID[playerTeamID],
               let owner = playerTeam.owner {
                let teamPlayers = allPlayers.filter { $0.teamID == playerTeamID }
                career.ownerDemands = generateOwnerDemands(
                    owner: owner,
                    players: teamPlayers
                )
                career.ownerDemandsAddressed = []
            }

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .reviewRoster,
                career: career,
                teams: teams
            )

        case .draft:
            // The draft order was prepared when this phase was ENTERED (see
            // `prepareDraftOrder` below) so the war room had real picks to
            // run on — here the concluded draft only emits its news.
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .draft,
                career: career,
                teams: teams
            )

            sendDraftCycleHeartbeat(career: career, phase: .draft)

        case .otas:
            // Camp Phase 1 hook-up: apply training plan + workload tick + battles
            // for the user's team during OTAs. AI teams skip the per-player tick
            // to keep WeekAdvancer fast — their development is handled in bulk
            // at the .trainingCamp boundary via PlayerDevelopmentEngine.
            applyCampWeeklyTick(career: career, phase: .otas, modelContext: modelContext, allPlayers: allPlayers)

            // UDFA signing: AI teams auto-sign ~12 UDFAs each, present pool to player.
            // R24: skipped entirely when the interactive Draft Day UDFA stage
            // already handled this season's undrafted market.
            if !currentDraftClass.isEmpty,
               !udfaStageCompletedSeasons.contains(career.currentSeason) {
                let udfaPool = ScoutingEngine.getUDFAPool(prospects: currentDraftClass)
                // Plan §2.9.8 (fixes defect #10): the order used to be the raw
                // team array — the same clubs picked first every single season —
                // and each of the 31 asked for 10-14 players from a pool that
                // was often ~28 deep, so the first two or three teams took
                // everything and the rest signed nobody. Shuffle the order and
                // ask for a fair share of what actually exists.
                let aiTeams = teams.filter { $0.id != career.teamID }.shuffled()
                let perTeamAsk = min(
                    4,
                    max(1, Int((Double(udfaPool.count) / 31.0).rounded(.up)))
                )

                var signedIDs = Set<UUID>()
                for team in aiTeams {
                    let available = udfaPool.filter { !signedIDs.contains($0.id) }
                    let toSign = Array(available.prefix(perTeamAsk))
                    let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                    for prospect in toSign {
                        signedIDs.insert(prospect.id)
                        // Convert prospect to player signed by this AI team.
                        // Routed through `convertUDFAToPlayer` so the bulk OTAs
                        // fallback applies the same rookie scaling as the
                        // interactive Draft Day UDFA stage — building the Player
                        // inline used to hand AI teams undrafted rookies at their
                        // FULL true attributes, i.e. better than every drafted
                        // rookie in the league.
                        let player = DraftEngine.convertUDFAToPlayer(
                            prospect: prospect,
                            teamID: team.id,
                            salaryCap: team.salaryCap
                        )
                        DraftEngine.initializeRookieFamiliarity(
                            player: player,
                            prospect: prospect,
                            coaches: teamCoaches,
                            isUndrafted: true
                        )
                        player.careerID = activeCareerID
                        modelContext.insert(player)
                        // Task #89: a signed UDFA is a cap liability like any
                        // other. This path used to insert him and never charge
                        // anybody, so ~150 league-wide deals were invisible on
                        // the books until the next league-year true-up.
                        team.currentCapUsage += player.annualSalary
                    }
                }

                // Generate inbox message about UDFA pool for the player's team
                let playerUDFAs = udfaPool.filter { !signedIDs.contains($0.id) }
                if !playerUDFAs.isEmpty, career.teamID != nil {
                    let topNames = playerUDFAs.prefix(5).map {
                        "\($0.fullName) (\($0.position.rawValue))"
                    }.joined(separator: ", ")
                    let message = InboxMessage(
                        sender: .scout(name: "Scouting Department"),
                        subject: "UDFA Prospects Available",
                        body: "There are \(playerUDFAs.count) undrafted free agents available for signing. Top prospects: \(topNames).",
                        date: "Offseason - OTAs, Season \(career.currentSeason)",
                        category: .staffUpdate
                    )
                    lastInboxMessages.append(message)
                }
            }

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .otas,
                career: career,
                teams: teams
            )

        case .trainingCamp:
            // Camp Phase 1 hook-up: per-week training plan + workload + battles
            // for the user's team. Full-pads camp = higher intensity baseline.
            applyCampWeeklyTick(career: career, phase: .trainingCamp, modelContext: modelContext, allPlayers: allPlayers)

            // Phase 2 (plan §2.9.2-3): the team-level environment — did a
            // coordinator swap the playbook this offseason, and has the staff
            // been together long enough for continuity to pay? This also ages
            // out the systems the building no longer runs, SEEDS the ones it has
            // just installed, and files the news story for an install year.
            //
            // Runs BEFORE `buildOffseasonInputs` (task #54): the scheme fit that
            // pass reports is a function of the familiarity dictionary, so the
            // dictionary has to describe the staff that will actually coach the
            // upcoming season before anybody reads a fit off it.
            let schemeChanges = applySchemeChanges(
                career: career,
                teams: teams,
                allPlayers: allPlayers,
                allCoaches: allCoaches
            )
            let teamEnvironments = schemeChanges.environments

            // Phase 2 (plan §2.3-§2.6): assemble the situational inputs the
            // realization model runs on — last season's record and
            // participation, the career trend, scheme fit, health flags —
            // ONCE for the whole league, then hand each team its slice.
            // `processOffseason` itself stays a pure function of its arguments;
            // every SwiftData fetch lives here.
            let offseasonInputs = buildOffseasonInputs(
                career: career,
                teamsByID: teamsByID,
                allPlayers: allPlayers,
                allCoaches: allCoaches,
                modelContext: modelContext
            )

            // Process offseason development for all teams
            // (R22: holdout players skip camp entirely — no development).
            // The realization verdicts come back through `onOutcome` so the
            // §2.10 narrative layer (camp development report, motivation and
            // late-bloomer stories) can be assembled without a second pass.
            // What the club has BUILT: a 0.92-1.08 development multiplier from
            // its training complex and recovery centre (`FacilityEngine`). One
            // fetch for the whole league — the pinned API takes a flat owner
            // list precisely so this does not become 32 round trips.
            let facilityCareerID = activeCareerID
            let facilityOwners = (try? modelContext.fetch(
                FetchDescriptor<Owner>(predicate: #Predicate { $0.careerID == facilityCareerID })
            )) ?? []

            var offseasonOutcomes: [PlayerDevelopmentEngine.OffseasonOutcome] = []
            for team in teams {
                let teamPlayers = allPlayers.filter { $0.teamID == team.id && !$0.isHoldingOut }
                let teamCoaches = allCoaches.filter { $0.teamID == team.id }
                // Task #51: this is the ONE development pass the balance
                // harness also runs, i.e. the control the weekly passes are
                // measured against — book it under its own source.
                DevelopmentSourceDiag.measure(DevelopmentSourceDiag.offseasonDevelop, teamPlayers) {
                    _ = PlayerDevelopmentEngine.processOffseason(
                        players: teamPlayers,
                        coaches: teamCoaches,
                        inputs: offseasonInputs,
                        environment: teamEnvironments[team.id] ?? PlayerDevelopmentEngine.TeamEnvironment(),
                        facilityMultiplier: FacilityEngine.developmentMultiplier(
                            teamID: team.id, owners: facilityOwners
                        ),
                        onOutcome: { offseasonOutcomes.append($0) }
                    )
                }
            }

            // Note: processOffseason already calls applyAgeRegression which increments
            // player.age and player.yearsPro, so no separate age increment needed.

            // R32: holdouts skip camp DEVELOPMENT but still get a year older,
            // and unsigned free agents age too. Before this fix both groups
            // were frozen in time — they never regressed and never retired,
            // which slowly corrupted multi-season careers.
            for player in allPlayers where !player.isRetired {
                let agedByCamp = player.teamID != nil && !player.isHoldingOut
                if !agedByCamp {
                    PlayerDevelopmentEngine.applyAgeRegression(player)
                    player.fatigue = 0
                }
            }

            // The camp edition of the Development Report for the user's team:
            // who showed up driven, who coasted after payday, who has settled
            // into his role, and who is behind a brand-new playbook (§2.10).
            if let playerTeamID = career.teamID {
                let userRoster = allPlayers.filter { $0.teamID == playerTeamID && !$0.isRetired }
                let campReport = DevelopmentReportBuilder.buildCampReport(
                    roster: userRoster,
                    outcomes: offseasonOutcomes.filter { $0.teamID == playerTeamID },
                    installedSchemes: schemeChanges.installs[playerTeamID] ?? [],
                    season: career.currentSeason
                )
                if !campReport.isEmpty {
                    career.developmentReports = [campReport] + career.developmentReports
                    let focusedCount = userRoster.filter { $0.trainingFocusArea != nil }.count
                    lastInboxMessages.append(
                        DevelopmentReportBuilder.inboxMessage(
                            report: campReport,
                            focusedCount: focusedCount
                        )
                    )
                }
            }

            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .trainingCamp,
                career: career,
                teams: teams
            )
            // Install-year stories (plan §2.9.2) — appended after the phase
            // news so the assignment above cannot swallow them.
            lastNewsItems.append(contentsOf: schemeChanges.news)
            // Motivation + late-bloomer stories (§2.10), same shape: the user's
            // own locker room always makes the feed, the rest of the league is
            // capped so camp week cannot become one long motivation column.
            lastNewsItems.append(contentsOf: motivationCampNews(
                outcomes: offseasonOutcomes,
                teamsByID: teamsByID,
                career: career
            ))

        case .preseason:
            // Camp Phase 1 hook-up: lighter intensity; preseason snaps drive perf.
            applyCampWeeklyTick(career: career, phase: .preseason, modelContext: modelContext, allPlayers: allPlayers)

            // Generate preseason news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .preseason,
                career: career,
                teams: teams
            )

        case .rosterCuts:
            // Camp Phase 1 hook-up: compute final camp grade for every player on the
            // user's team before they decide who to cut. AI teams skip the per-player
            // grade since the UI never surfaces them.
            applyCampGrades(career: career, modelContext: modelContext, allPlayers: allPlayers)

            // Resolve any open position battles -- the camp is over.
            let openBattles = fetchOpenPositionBattles(seasonYear: career.currentSeason, modelContext: modelContext)
            if !openBattles.isEmpty {
                PositionBattleTracker.resolveBattles(battles: openBattles, modelContext: modelContext)
            }

            // R32: league-wide final cutdown — AI teams trim to the roster
            // ceiling when the user does theirs. Draft classes + UDFA waves
            // + FA signings add ~15-20 players/season and nothing ever cut
            // AI rosters before, so multi-season leagues ballooned past 90.
            trimAIRosters(career: career, teams: teams, allPlayers: allPlayers)

            // Player handles manually — just generate phase news
            lastNewsItems = NewsGenerator.generateOffseasonNews(
                phase: .rosterCuts,
                career: career,
                teams: teams
            )

        default:
            break
        }

        // --- Wave 2: the offseason trade market ---
        // Runs AFTER the phase's own logic so it reads the roster the phase just
        // produced (post-FA signings, post-cutdown 53s) and appends to the news
        // list rather than being overwritten by it — several cases above ASSIGN
        // `lastNewsItems`. The draft phase is deliberately excluded: draft-weekend
        // pick swaps are Wave 4's business and run inside `DraftDayCoordinator`.
        let offseasonWindow = TradeValueEngine.MarketWindow.offseason(currentPhase)
        if offseasonWindow.isMarketWindow {
            runOffseasonTradeMarket(
                window: offseasonWindow,
                career: career,
                teams: teams,
                teamsByID: teamsByID,
                allPlayers: allPlayers,
                modelContext: modelContext
            )
        }

        // --- Apply owner demand consequences before season starts (#248) ---
        if nextPhase == .regularSeason {
            if let playerTeamID = career.teamID,
               let playerTeam = teamsByID[playerTeamID],
               let owner = playerTeam.owner {
                let unaddressed = career.ownerDemands.filter {
                    !career.ownerDemandsAddressed.contains($0)
                }
                if !unaddressed.isEmpty {
                    let penaltyPerDemand = owner.patience <= 3 ? 15 : 10
                    let totalPenalty = unaddressed.count * penaltyPerDemand
                    owner.satisfaction = max(0, owner.satisfaction - totalPenalty)

                    let demandList = unaddressed.joined(separator: ", ")
                    let message = InboxMessage(
                        sender: .owner(name: owner.name),
                        subject: "Unaddressed Roster Demands",
                        body: "I'm disappointed you didn't address the following: \(demandList). This is going to affect my confidence in your leadership. (-\(totalPenalty) satisfaction)",
                        date: "Season \(career.currentSeason)",
                        category: .ownerDirective
                    )
                    lastInboxMessages.append(message)
                }
            }
        }

        // --- Camp Phase 1: process waivers when leaving rosterCuts ---
        // Every cut player passes through 24h waivers before the season starts.
        // Worst-record teams get higher priority. Claims stamp the cut row.
        if currentPhase == .rosterCuts && nextPhase == .regularSeason {
            processCampWaivers(career: career, teams: teams, modelContext: modelContext)
        }

        // --- Transition to the next phase ---
        if nextPhase == .regularSeason {
            // Increment the season year before generating a new schedule.
            career.currentSeason += 1

            startNewSeason(career: career, teams: teams, modelContext: modelContext)

            // --- §5.1 Cutdown day: every club stocks its 16-man squad ---
            //
            // ORDERING is load-bearing and this is the only spot that satisfies
            // it. `startNewSeason` above runs `refillAIRosters`, which drains
            // the free-agent pool by the SAME `RosterValue.keepScore` order the
            // squad fill uses; run the fill first and the refill would strip
            // the best man off every squad seconds after it was assembled.
            // Running here also means the squads exist for week 1 — the poach
            // market opens with the season, as it does in the real league.
            if currentPhase == .rosterCuts {
                let squadSummary = PracticeSquadEngine.fillSquads(
                    career: career,
                    teams: teams,
                    allPlayers: fetchAllPlayers(modelContext: modelContext),
                    modelContext: modelContext
                )
                print("[PracticeSquad] cutdown fill: \(squadSummary.clubsFilled) clubs, "
                      + "\(squadSummary.totalSignings) signings "
                      + "(own cuts \(squadSummary.fromOwnCuts), street \(squadSummary.fromStreetFreeAgents), "
                      + "generated \(squadSummary.generated))")
            }

            // Generate schedule news for the new season
            let scheduleNews = NewsGenerator.generateOffseasonNews(
                phase: .regularSeason,
                career: career,
                teams: teams
            )
            lastNewsItems.append(contentsOf: scheduleNews)
        } else {
            career.currentPhase = nextPhase
            emitGroupTransitionMessageIfNeeded(
                oldPhase: currentPhase,
                newPhase: nextPhase,
                season: career.currentSeason
            )
        }

        // --- Draft-prep stage machine (#103) ---
        //
        // Three stamps, no reset hook. Entering the combine writes the first
        // stage with THIS cycle's season on it, which is also what makes the
        // pipeline reset: `Career.prepStep` reads a step stamped in an earlier
        // cycle as `.combineReview` on its own. The other two boundaries raise a
        // floor rather than override — a club that worked the stages forward
        // keeps its place, one that skipped them is carried to where the phase
        // says it must be. `career.currentPhase` is already `nextPhase` here,
        // which is what the accessor's floor reads.
        if nextPhase == .combine {
            career.prepStep = .combineReview
        } else if nextPhase == .proDays {
            career.advancePrepStep(to: .proDayFocus)
        } else if nextPhase == .draft {
            career.advancePrepStep(to: .ready)
        }

        // #104: crossing any prep boundary also PERSISTS whatever the accessor
        // was already returning — the phase floor and the evidence floor
        // (`Career.derivedPrepStepFloor`, built from the club's own per-cycle
        // ledgers). Reading through a floor forever is how a migrated save stays
        // migrated: it never writes, so the stored string keeps disagreeing with
        // the screen and any code that touches `draftPrepStep` directly reads a
        // stage the club left weeks ago. One idempotent write per boundary
        // settles it. `advancePrepStep` never lowers, so this cannot walk a club
        // backwards.
        if [.combine, .freeAgency, .proDays, .draft].contains(nextPhase) {
            career.advancePrepStep(to: career.prepStep)
        }

        // The combine is a league event on a fixed date, not a club decision:
        // open a fresh attendance window for this cycle and hold the event, so
        // the Combine tab has something in it whether or not this club sends
        // anybody. `ensureCombineRun` is idempotent and `career.currentPhase` is
        // already `nextPhase` by here, which is what its window guard reads.
        if nextPhase == .combine {
            resetCombineWindow()
            ensureCombineRun(career: career, modelContext: modelContext)
        }

        // --- The pro-day phase, run when the club ENTERS it (#103 §5.7) ---
        //
        // Everything below used to sit in `case .proDays:` of the switch above,
        // which runs the current phase's logic BEFORE the transition — i.e. at
        // pro-days EXIT, in the same call that enters `.draft` and fires the
        // Pre-Draft mock out of `prepareDraftOrder`. The two public mock
        // moments therefore landed in one week advance, and the circuit, the
        // attrition wave and the AI Top-30 sweep all published after the user
        // had already walked past the stages that exist to read them.
        //
        // Here it is still "after free agency has reshaped 32 rosters" (the
        // property MOMENT 3 depends on — `updateTeamInterest` reads the market's
        // output), and it is now also a whole phase before MOMENT 4.
        // `career.currentPhase` is already `nextPhase` at this point, so every
        // `phase: .proDays` label below still reads true.
        if nextPhase == .proDays {
            // Pro days phase — engine work happens in scouting UI
            lastNewsItems.append(contentsOf: NewsGenerator.generateOffseasonNews(
                phase: .proDays,
                career: career,
                teams: teams
            ))

            // Task #78 — the league pro-day circuit. Every school holds one,
            // and until now nothing in the app did: `simulateProDay` was
            // written, documented and never called, so the ~40 men the combine
            // sent home without a number carried empty cells to the draft and
            // this phase held exactly one event. The circuit fills the numbers
            // for everybody (public, broadcast precision) and the drift moves
            // the board on them; `attendProDay` still buys the decimals and the
            // filed report. Idempotent — the cohort it tests is the cohort it
            // empties.
            if !currentDraftClass.isEmpty,
               let circuit = ScoutingEngine.runLeagueProDays(prospects: &currentDraftClass) {
                lastNewsItems.append(contentsOf: NewsGenerator.proDayCircuitNews(
                    result: circuit,
                    season: career.currentSeason
                ))
                // A hand-timed number on a friendly surface is a nudge, not a
                // shove: two rounds of headroom like the combine, but far fewer
                // pairs, because only the late-testing cohort carries pressure.
                let moves = ScoutingEngine.applyProjectionDrift(
                    prospects: &currentDraftClass,
                    pressure: ScoutingEngine.proDayPressure(
                        currentDraftClass,
                        cohort: circuit.cohort
                    ),
                    maxShift: 2,
                    maxPairs: 12,
                    seed: ScoutingEngine.cycleSeed(
                        careerID: career.id,
                        season: career.currentSeason,
                        salt: ScoutingEngine.CycleSalt.proDayDrift
                    )
                )
                if !moves.isEmpty {
                    lastNewsItems.append(contentsOf: NewsGenerator.projectionDriftNews(
                        moves: moves,
                        season: career.currentSeason,
                        limit: 2
                    ))
                }
                if let message = InboxEngine.proDayCircuitMessage(
                    result: circuit,
                    moves: moves,
                    dateString: InboxEngine.dateLabel(
                        week: 0, season: career.currentSeason, phase: .proDays
                    )
                ) {
                    lastInboxMessages.append(message)
                }
                persistDraftClass(currentDraftClass, to: modelContext)
            }

            // Task #78 — the second character wave. March is when the
            // background checks come back.
            applyCharacterFindingWave(
                career: career,
                pool: ScoutingEngine.proDayCharacterFindings,
                salt: ScoutingEngine.CycleSalt.proDayCharacter,
                phase: .proDays,
                modelContext: modelContext
            )

            // R41 — pre-draft attrition. About 2 % of the declared class gets
            // hurt between the combine and the draft: a knee in a pro-day
            // drill, a labrum found on a recheck, a hamstring pulled running
            // for a stopwatch. It is the most reliable thing that happens to a
            // real class every spring, and this board used to be frozen from
            // February to April. Deterministic per (careerID, season) and
            // idempotent — re-entering the phase cannot injure a second wave.
            if !currentDraftClass.isEmpty {
                let setbacks = ScoutingEngine.applyPreDraftAttrition(
                    prospects: &currentDraftClass,
                    seed: ScoutingEngine.cycleSeed(
                        careerID: career.id,
                        season: career.currentSeason,
                        salt: ScoutingEngine.CycleSalt.proDayAttrition
                    )
                )
                if !setbacks.isEmpty {
                    lastNewsItems.append(contentsOf: NewsGenerator.preDraftInjuryNews(
                        setbacks: setbacks,
                        season: career.currentSeason
                    ))
                    if let message = InboxEngine.preDraftAttritionMessage(
                        setbacks: setbacks,
                        dateString: InboxEngine.dateLabel(
                            week: 0, season: career.currentSeason, phase: .proDays
                        )
                    ) {
                        lastInboxMessages.append(message)
                    }
                    persistDraftClass(currentDraftClass, to: modelContext)
                }
            }

            // #103 §5.8 — the other 31 clubs run their Top-30 lists too.
            runAITop30Visits(career: career, teams: teams, modelContext: modelContext)

            // #103 §5.7 — MOMENT 3, moved here from the end of `.freeAgency`,
            // and then (fixup) out of the `case .proDays:` EXIT hook into this
            // ENTRY hook, so that it is not fired in the same week advance as
            // MOMENT 4 and so that "Mock 1.0" exists for the whole spring the
            // `mockOne` stage asks the user to read it in.
            //
            // The mock the league actually argues about is the one that lands
            // after the campus circuit: the tour has just moved the board (the
            // late testers finally have numbers, the medical rechecks have run,
            // 2 % of the class is hurt), and free agency reshaped the 32 rosters
            // this mock reads needs off. Both halves of that are now behind us,
            // which is what makes this a *post-tour* mock rather than a
            // re-print of February. Key: `"Post-Pro-Day"`.
            //
            // Unlike the old `"Post-FA"` block this one is an EVENT — feed item
            // plus a personnel-director letter — and it is emitted exactly once
            // per cycle. The gate is the persisted history itself, not a
            // process static, so a save re-entering this phase after a relaunch
            // does not mail the same mock twice.
            if !currentDraftClass.isEmpty {
                restoreMockDraftHistory(from: career)
                let isRerun = mockDraftHistory["Post-Pro-Day"] != nil

                currentMockDraft = ScoutingEngine.generateMockDraft(
                    prospects: currentDraftClass,
                    draftPicks: currentDraftPicks,
                    teams: teams,
                    players: allPlayers
                )
                // Finding S8: this is the ONE moment in the cycle when 32
                // rosters have genuinely changed, and it was the one mock that
                // did not rebuild team interest — so the "Hot / Warm / Cold" a
                // user read on a prospect all spring was still keyed to the
                // depth charts as they stood before the market opened, and a
                // club that had just signed a starting corner was still shown
                // chasing corners.
                ScoutingEngine.updateTeamInterest(
                    prospects: &currentDraftClass,
                    teams: teams,
                    players: allPlayers
                )
                ScoutingEngine.applyMockDraftToProspects(
                    prospects: &currentDraftClass,
                    mockDraft: currentMockDraft
                )
                recordMockDraftSnapshot("Post-Pro-Day", career: career)

                if !isRerun {
                    emitMockDraftMoment(
                        snapshot: currentMockDraft,
                        label: "Mock 1.0",
                        career: career,
                        teams: teams,
                        phase: .proDays
                    )
                }

                // R41 drift moment 3 of 4.
                applyMockDrift(career: career, moment: 3, modelContext: modelContext)
            }

            sendDraftCycleHeartbeat(career: career, phase: .proDays)
        }

        // R32: the draft order must exist BEFORE the draft phase begins —
        // the war room reads persisted picks for the current season the
        // moment it opens. Previously the order was generated when LEAVING
        // the draft phase (and stamped with the season-cycle year), so from
        // season 2 onward the draft room found no picks, comp picks attached
        // after the fact, and the league never restocked through the draft.
        if nextPhase == .draft {
            prepareDraftOrder(
                career: career,
                teams: teams,
                allPlayers: allPlayers,
                modelContext: modelContext
            )
        }

        // Reset FA state when entering the free agency phase
        if nextPhase == .freeAgency {
            career.freeAgencyRound = 0
            career.freeAgencyStep = FreeAgencyStep.finalPush.rawValue
            career.faVisitsUsed = 0
            FASigningTracker.reset()

            // R23 — Legal tampering window: leak market projections and early
            // suitors for the top upcoming FAs before the market opens. The
            // rumors quote the same pricing/need model the market itself uses.
            let rumors = TamperingRumorEngine.generateRumors(
                allPlayers: allPlayers,
                allTeams: teams,
                userTeamID: career.teamID
            )
            if let digest = TamperingRumorEngine.inboxDigest(rumors: rumors, season: career.currentSeason) {
                lastInboxMessages.append(digest)
            }
            lastNewsItems.append(contentsOf: TamperingRumorEngine.newsItems(
                rumors: rumors,
                week: career.currentWeek,
                season: career.currentSeason
            ))
        }

        // --- TRACK B: the rookie class reports to camp ---
        //
        // ADDITIVE. Nothing above changes: the rookies became real `Player`
        // rows at the pick, and every engine has been reading their real
        // ratings since. Crossing INTO training camp is simply the moment the
        // user is allowed to see them (`RookieFog`), so this arms the
        // once-per-season reveal `CareerShellView` presents and files the press
        // grade with the news feed and the mailbox.
        if nextPhase == .trainingCamp,
           currentPhase != .trainingCamp,
           let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            let cid = career.id
            let draftYear = career.currentSeason
            let gradeDescriptor = FetchDescriptor<DraftPickGrade>(
                predicate: #Predicate<DraftPickGrade> {
                    $0.careerID == cid && $0.draftYear == draftYear && $0.teamID == playerTeamID
                }
            )
            let pickGrades = (try? modelContext.fetch(gradeDescriptor)) ?? []

            if let summary = RookieClassReveal.build(
                season: draftYear,
                teamID: playerTeamID,
                teamName: playerTeam.fullName,
                teamAbbreviation: playerTeam.abbreviation,
                players: allPlayers,
                grades: pickGrades
            ) {
                RookieClassReveal.arm(careerID: cid, season: draftYear)
                lastNewsItems.append(NewsGenerator.rookieClassGraded(
                    teamName: summary.teamName,
                    teamID: playerTeamID,
                    classGrade: summary.classGrade,
                    verdict: summary.verdict,
                    season: draftYear
                ))
                lastInboxMessages.append(NewsGenerator.rookieClassInboxMessage(
                    teamName: summary.teamName,
                    classGrade: summary.classGrade,
                    verdict: summary.verdict,
                    bestPickLine: summary.bestPickLine,
                    biggestReachLine: summary.biggestReachLine,
                    season: draftYear
                ))
            }
        }

        // --- Generate inbox messages for the new phase ---
        if let playerTeamID = career.teamID,
           let playerTeam = teamsByID[playerTeamID] {
            let teamCoaches = allCoaches.filter { $0.teamID == playerTeamID }
            lastInboxMessages.append(contentsOf: InboxEngine.generatePhaseMessages(
                phase: career.currentPhase,
                career: career,
                team: playerTeam,
                coaches: teamCoaches,
                owner: playerTeam.owner
            ))
        }
    }

    // MARK: - Private: Draft Order Preparation (R32)

    /// Ensures the current season's draft has a full, persisted pick order the
    /// moment the `.draft` phase begins. Runs at the proDays → draft boundary.
    ///
    /// - Season 1 reuses the league-generation pool (the real first-round
    ///   order) — including any comp picks already slotted into it at the
    ///   close of free agency.
    /// - Season 2+ ADOPTS the future-pick rows minted years earlier: they are
    ///   renumbered from the just-finished season's standings (see
    ///   `adoptFuturePicks`) instead of being replaced, because by now they may
    ///   have been traded. Comp picks stashed at FA close attach on top.
    /// - Only a pool that is missing entirely (a pre-future-picks save) is built
    ///   from scratch by `DraftEngine.generateDraftOrder`.
    ///
    /// The pool is exposed via `currentDraftPicks` and the final pre-draft
    /// mock projection is computed here so the war room, dashboards, and
    /// prospect boards all see the actual order before the first selection.
    private static func prepareDraftOrder(
        career: Career,
        teams: [Team],
        allPlayers: [Player],
        modelContext: ModelContext
    ) {
        let season = career.currentSeason
        let cid = career.id
        let existingDescriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate<DraftPick> {
                $0.careerID == cid && $0.seasonYear == season && $0.isComplete == false
            }
        )
        var draftPicks = (try? modelContext.fetch(existingDescriptor)) ?? []

        if draftPicks.isEmpty {
            // Legacy save (no future picks were ever minted): build the order
            // from the season that just ended.
            let allGames = fetchAllGamesForSeason(
                seasonYear: season,
                modelContext: modelContext
            )
            draftPicks = DraftEngine.generateDraftOrder(
                teams: teams,
                games: allGames,
                seasonYear: season
            )
            for pick in draftPicks {
                pick.careerID = cid
                modelContext.insert(pick)
            }
        } else if draftPicks.contains(where: { $0.isProvisionalOrder }) {
            // The normal path from season 2 on: this year's rows already exist
            // as projections (and some now belong to other teams).
            let allGames = fetchAllGamesForSeason(
                seasonYear: season,
                modelContext: modelContext
            )
            adoptFuturePicks(
                draftPicks,
                teams: teams,
                games: allGames
            )
        }

        // R23 — attach compensatory picks awarded at the close of free
        // agency (if they weren't already slotted into a persisted pool).
        let pendingComp = CompensatoryPickEngine.pendingAwards()
        if !pendingComp.isEmpty {
            var teamAbbrs: [UUID: String] = [:]
            for team in teams { teamAbbrs[team.id] = team.abbreviation }
            let compPicks = CompensatoryPickEngine.applyAwards(
                pendingComp,
                toPickPool: draftPicks,
                seasonYear: season,
                teamAbbrs: teamAbbrs
            )
            for pick in compPicks {
                pick.careerID = cid
                modelContext.insert(pick)
            }
            draftPicks.append(contentsOf: compPicks)
            CompensatoryPickEngine.clearPendingAwards()
        }

        draftPicks.sort { $0.pickNumber < $1.pickNumber }
        currentDraftPicks = draftPicks

        // Pre-draft mock draft (final projection with the actual order).
        currentMockDraft = ScoutingEngine.generateMockDraft(
            prospects: currentDraftClass,
            draftPicks: draftPicks,
            teams: teams,
            players: allPlayers
        )
        ScoutingEngine.updateTeamInterest(
            prospects: &currentDraftClass,
            teams: teams,
            players: allPlayers
        )
        ScoutingEngine.applyMockDraftToProspects(
            prospects: &currentDraftClass,
            mockDraft: currentMockDraft
        )
        restoreMockDraftHistory(from: career)
        let isRerun = mockDraftHistory["Pre-Draft"] != nil
        recordMockDraftSnapshot("Pre-Draft", career: career)

        // #103 §5.7 — MOMENT 4 is the cycle's second and LAST public mock, and
        // the last board event of any kind before the clock starts.
        if !isRerun {
            emitMockDraftMoment(
                snapshot: currentMockDraft,
                label: "Final Mock",
                career: career,
                teams: teams,
                phase: .draft
            )
        }

        // R41 drift moment 4 of 4 — the last board move before the clock starts.
        applyMockDrift(career: career, moment: 4, modelContext: modelContext)
    }

    // MARK: - Private: The Living Draft Market (R41)

    /// The nudge each of the four mock-draft regenerations applies to the media
    /// board.
    ///
    /// A regenerated mock is the market's own re-read of the class, so the
    /// projections move toward it — one round at most, at most eight riser /
    /// faller pairs, and always zero-sum (see
    /// `ScoutingEngine.applyProjectionDrift`: a man only climbs into a band by
    /// taking the slot of somebody leaving it, so the class-wide distribution of
    /// `draftProjection` is exactly preserved). That property is what makes this
    /// safe to run four times a cycle: `draftProjection` anchors AI perception
    /// and the rookie-band fallbacks, and no amount of drift can inflate the
    /// round-1 population.
    ///
    /// News is emitted from the two PUBLIC moments — 3 (Mock 1.0, after the
    /// pro-day circuit) and 4 (the final pre-draft board) — plus the combine's
    /// own separate drift at the `.combine` hook. Moments 1 and 2 move the board
    /// quietly, which is what a mock re-read that early is. The risers and
    /// fallers printed here are the movement half of the moment; the mock itself
    /// is announced by `emitMockDraftMoment` at the same hook (#103 §5.7).
    ///
    /// - Parameter moment: 1 = mid-season, 2 = combine, 3 = post-pro-day,
    ///   4 = pre-draft.
    private static func applyMockDrift(
        career: Career,
        moment: Int,
        modelContext: ModelContext
    ) {
        guard !currentDraftClass.isEmpty else { return }
        let moves = ScoutingEngine.applyProjectionDrift(
            prospects: &currentDraftClass,
            pressure: ScoutingEngine.mockConsensusPressure(currentDraftClass),
            maxShift: 1,
            maxPairs: 8,
            seed: ScoutingEngine.cycleSeed(
                careerID: career.id,
                season: career.currentSeason,
                salt: ScoutingEngine.CycleSalt.mockDrift &+ UInt64(moment)
            )
        )
        guard !moves.isEmpty else { return }
        if moment >= 3 {
            lastNewsItems.append(contentsOf: NewsGenerator.projectionDriftNews(
                moves: moves,
                season: career.currentSeason,
                limit: 2
            ))
        }
        persistDraftClass(currentDraftClass, to: modelContext)
    }

    // MARK: - Private: mock-draft moments + persistence (#103 §5.7)

    /// The club's own board, best man first.
    ///
    /// The Big Board's drag order (`prospectCustomBoard`) is a
    /// `@CareerScopedStorage` string owned by the UI layer, so the engine
    /// cannot read it — and should not: the drag order is *seeded* from these
    /// grades, so "our board" from an engine hook is the department's own
    /// grades, with the men it never graded behind them in consensus order.
    ///
    /// Returned whole rather than as a five-man slice: `NewsGenerator` /
    /// `InboxEngine` use the head for the disagreement lines and the rest as the
    /// name lookup for the picks they print.
    private static func clubBoardOrder() -> [CollegeProspect] {
        let graded = currentDraftClass
            .filter { $0.scoutedOverall != nil }
            .sorted {
                let a = $0.scoutedOverall ?? 0
                let b = $1.scoutedOverall ?? 0
                if a != b { return a > b }
                return $0.id.uuidString < $1.id.uuidString
            }
        let ungraded = currentDraftClass
            .filter { $0.scoutedOverall == nil }
            .sorted {
                let a = $0.draftProjection ?? 99
                let b = $1.draftProjection ?? 99
                if a != b { return a < b }
                return $0.id.uuidString < $1.id.uuidString
            }
        return graded + ungraded
    }

    /// Announces one mock-draft moment: a feed item and a letter from the
    /// personnel director. Called once per cycle per label.
    private static func emitMockDraftMoment(
        snapshot: [ScoutingEngine.MockDraftPick],
        label: String,
        career: Career,
        teams: [Team],
        phase: SeasonPhase
    ) {
        guard !snapshot.isEmpty else { return }
        let board = clubBoardOrder()

        lastNewsItems.append(contentsOf: NewsGenerator.mockDraftEvent(
            history: snapshot,
            label: label,
            userBoardTop: board,
            season: career.currentSeason
        ))

        // No club means no "our board" — a userless save still gets the feed
        // item, which is the public half of the moment.
        guard career.teamID != nil else { return }
        let abbreviation = teams.first { $0.id == career.teamID }?.abbreviation
        if let message = InboxEngine.mockDraftMessage(
            history: snapshot,
            label: label,
            userBoardTop: board,
            userTeamAbbreviation: abbreviation,
            dateString: InboxEngine.dateLabel(
                week: 0, season: career.currentSeason, phase: phase
            )
        ) {
            lastInboxMessages.append(message)
        }
    }

    /// Stores a snapshot under `tag` and serialises the whole history onto the
    /// save.
    ///
    /// `mockDraftHistory` is a process static: before #103 it was wiped by every
    /// app restart, so "compare Mock 1.0 with the final board" — the affordance
    /// the four snapshots exist for — could not survive a force-quit. The blob
    /// carries a season stamp because the history belongs to ONE draft cycle;
    /// a stamp from an earlier cycle reads as "no history", the same trick
    /// `Career.prepStep` uses, so no reset hook can be forgotten.
    private static func recordMockDraftSnapshot(_ tag: String, career: Career) {
        // Restore FIRST, always. A save relaunched mid-cycle reaches the combine
        // hook with a cold static and a blob that already holds "Mid-Season";
        // writing without merging would persist a one-key history and silently
        // drop the earlier snapshot. Free after the first call — the restore is
        // a no-op once the static is warm.
        restoreMockDraftHistory(from: career)
        mockDraftHistory[tag] = currentMockDraft
        persistMockDraftHistory(to: career)
    }

    /// One `ScoutingEngine.MockDraftPick` in a form `Codable` can carry.
    ///
    /// A mirror rather than a conformance on the engine type: `MockDraftPick`
    /// lives in `ScoutingEngine`, which this wave does not own, and Swift will
    /// not synthesise `Codable` for a struct from another file's extension
    /// anyway.
    private struct MockPickRecord: Codable {
        let pickNumber: Int
        let round: Int
        let prospectID: UUID
        let teamAbbreviation: String
        let teamID: UUID
        let teamNeeds: [Position]
        let pickRationale: String
        let mediaComment: String

        init(_ pick: ScoutingEngine.MockDraftPick) {
            pickNumber = pick.pickNumber
            round = pick.round
            prospectID = pick.prospectID
            teamAbbreviation = pick.teamAbbreviation
            teamID = pick.teamID
            teamNeeds = pick.teamNeeds
            pickRationale = pick.pickRationale
            mediaComment = pick.mediaComment
        }

        var pick: ScoutingEngine.MockDraftPick {
            ScoutingEngine.MockDraftPick(
                pickNumber: pickNumber,
                round: round,
                prospectID: prospectID,
                teamAbbreviation: teamAbbreviation,
                teamID: teamID,
                teamNeeds: teamNeeds,
                pickRationale: pickRationale,
                mediaComment: mediaComment
            )
        }
    }

    private struct MockHistoryBlob: Codable {
        let season: Int
        let snapshots: [String: [MockPickRecord]]
    }

    /// Writes `mockDraftHistory` onto `career.mockDraftHistoryData`.
    static func persistMockDraftHistory(to career: Career) {
        guard !mockDraftHistory.isEmpty else {
            career.mockDraftHistoryData = nil
            return
        }
        let blob = MockHistoryBlob(
            season: career.currentSeason,
            snapshots: mockDraftHistory.mapValues { $0.map(MockPickRecord.init) }
        )
        career.mockDraftHistoryData = try? JSONEncoder().encode(blob)
    }

    /// Reloads `mockDraftHistory` from the save when the process static is cold.
    ///
    /// Idempotent and cheap: does nothing once the static holds this cycle's
    /// snapshots, and drops a blob stamped with an earlier season on the floor
    /// rather than showing last year's mocks against this year's class.
    static func restoreMockDraftHistory(from career: Career) {
        guard mockDraftHistory.isEmpty,
              let data = career.mockDraftHistoryData,
              let blob = try? JSONDecoder().decode(MockHistoryBlob.self, from: data)
        else { return }
        guard blob.season == career.currentSeason else {
            career.mockDraftHistoryData = nil
            return
        }
        mockDraftHistory = blob.snapshots.mapValues { $0.map(\.pick) }
    }

    // MARK: - Private: AI Top-30 visits (#103 §5.8)

    /// Salt for the AI Top-30 pass. Lives here rather than in
    /// `ScoutingEngine.CycleSalt` because this wave does not own that file; the
    /// value is drawn from the same space and collides with nothing in it.
    private static let aiTop30Salt: UInt64 = 0x70_3070_A1_5F

    /// The other 31 clubs run their Top-30 lists too.
    ///
    /// `CollegeProspect.top30VisitedByTeams` was written by exactly one caller —
    /// `ScoutingEngine.conductTop30Visit`, i.e. the user — so the "who else is
    /// in on him" signal on a prospect card was structurally always "nobody".
    /// Each AI club now stamps ~30 IDs off ITS OWN `AIDraftPerception` board,
    /// which is the same lens its war room drafts from, so the clubs chasing a
    /// man are the clubs that actually rate him.
    ///
    /// This is flavour plus a real competition signal and **nothing else**: no
    /// interview is run, no report is filed, no attribute is touched, and
    /// `DraftEngine` never reads the field — AI draft quality is bit-identical.
    /// Deterministic per `(careerID, season)` and idempotent by construction
    /// (the append is guarded on membership).
    private static func runAITop30Visits(
        career: Career,
        teams: [Team],
        modelContext: ModelContext
    ) {
        guard !currentDraftClass.isEmpty else { return }
        let aiTeams = teams.filter { $0.id != career.teamID }
        guard !aiTeams.isEmpty else { return }

        let declared = currentDraftClass.filter { $0.isDeclaringForDraft }
        guard declared.count >= 30 else { return }

        // Cheap out if the pass already ran this cycle: every club stamps, so
        // one club's mark on one prospect is proof of the whole pass.
        let firstClub = aiTeams[0].id
        if declared.contains(where: { $0.top30VisitedByTeams.contains(firstClub) }) {
            return
        }

        var stamped = 0
        for team in aiTeams {
            let lens = AIDraftPerception.lens(forTeam: team.id)
            // The club's own board: perceived level and ceiling, weighted the
            // way a spring board is — the visit list is about who you might
            // take, and in April that is still mostly upside.
            let ranked = declared
                .map { prospect -> (prospect: CollegeProspect, score: Double) in
                    let read = AIDraftPerception.read(
                        teamID: team.id,
                        prospectID: prospect.id,
                        trueOverall: prospect.trueOverall,
                        truePotential: prospect.truePotential,
                        lens: lens
                    )
                    return (prospect, read.overall * 0.6 + read.potential * 0.4)
                }
                .sorted {
                    if $0.score != $1.score { return $0.score > $1.score }
                    return $0.prospect.id.uuidString < $1.prospect.id.uuidString
                }

            // 30 men out of the top 55 of that board: a real Top-30 list is not
            // simply the board's head — it is the head minus the men you are
            // certain about, plus the ones you need a second look at.
            var rng = SeededLeagueRandom(
                seed: AIDraftPerception.pairSeed(teamID: team.id, prospectID: career.id)
                    ^ ScoutingEngine.cycleSeed(
                        careerID: career.id,
                        season: career.currentSeason,
                        salt: aiTop30Salt
                    )
            )
            var pool = Array(ranked.prefix(55).map(\.prospect))
            pool.shuffle(using: &rng)
            for prospect in pool.prefix(30) where !prospect.top30VisitedByTeams.contains(team.id) {
                prospect.top30VisitedByTeams.append(team.id)
                stamped += 1
            }
        }

        guard stamped > 0 else { return }
        persistDraftClass(currentDraftClass, to: modelContext)
    }

    /// One mid-cycle character wave: 2-4 declared prospects pick up a new red
    /// flag, and the feed and the inbox both name them (task #78).
    ///
    /// The flag itself is never printed by either — it lands in `redFlags` and
    /// is disclosed through the existing `ProspectFog.flagDisclosure` ladder, so
    /// reading it still costs two reports, a meeting or a Top-30 visit.
    ///
    /// Deterministic per (careerID, season, salt) and idempotent per pool, so a
    /// re-entered phase cannot run a second wave off the same list.
    private static func applyCharacterFindingWave(
        career: Career,
        pool: [String],
        salt: UInt64,
        phase: SeasonPhase,
        modelContext: ModelContext
    ) {
        guard !currentDraftClass.isEmpty else { return }
        let findings = ScoutingEngine.applyCharacterFindings(
            prospects: &currentDraftClass,
            pool: pool,
            seed: ScoutingEngine.cycleSeed(
                careerID: career.id,
                season: career.currentSeason,
                salt: salt
            )
        )
        guard !findings.isEmpty else { return }

        lastNewsItems.append(contentsOf: NewsGenerator.characterFindingNews(
            findings: findings,
            season: career.currentSeason
        ))
        if let message = InboxEngine.characterFindingsMessage(
            findings: findings,
            dateString: InboxEngine.dateLabel(
                week: 0, season: career.currentSeason, phase: phase
            )
        ) {
            lastInboxMessages.append(message)
        }
        persistDraftClass(currentDraftClass, to: modelContext)
    }

    /// Mails the draft-cycle heartbeat for `phase`, once per season (finding S9).
    ///
    /// The offseason used to go quiet between the loud events; this is the
    /// scouting department checking in with real counts off the live class at
    /// every phase boundary, so the four months read as a season of work.
    private static func sendDraftCycleHeartbeat(career: Career, phase: SeasonPhase) {
        guard !currentDraftClass.isEmpty else { return }
        let key = "\(career.currentSeason)-\(phase.rawValue)"
        // The de-duplication has to survive a relaunch, because the thing it is
        // preventing does: `draftCycleHeartbeatsSent` is a process static, so a
        // user who quit the app and advanced the same boundary again got a
        // second identical letter in the inbox. The persisted set is the
        // authority; the static is just the hot path.
        let sent = draftCycleHeartbeatsSent.union(persistedHeartbeatKeys())
        guard !sent.contains(key) else { return }
        guard let message = InboxEngine.draftCycleHeartbeat(
            phase: phase,
            prospects: currentDraftClass,
            dateString: InboxEngine.dateLabel(
                week: 0, season: career.currentSeason, phase: phase
            )
        ) else { return }
        draftCycleHeartbeatsSent.insert(key)
        persistHeartbeatKeys(sent.union([key]))
        lastInboxMessages.append(message)
    }

    /// Heartbeat keys this save has already mailed, from `UserDefaults`.
    ///
    /// Stored as one pipe-joined string rather than an array so it travels
    /// through the same `CareerScopedDefaults` string accessor every other
    /// career-scoped flag uses (and is therefore purged with the save).
    private static func persistedHeartbeatKeys() -> Set<String> {
        guard let raw = CareerScopedDefaults.string("draftCycleHeartbeatsSent"), !raw.isEmpty else {
            return []
        }
        return Set(raw.split(separator: "|").map(String.init))
    }

    private static func persistHeartbeatKeys(_ keys: Set<String>) {
        CareerScopedDefaults.set(keys.sorted().joined(separator: "|"), "draftCycleHeartbeatsSent")
    }

    /// Holds the January all-star week and files what it produced.
    ///
    /// Called once, from the `.coachingChanges` hook right after declarations:
    /// the invite list IS the declared senior board, and the combine is still a
    /// month away. `ScoutingEngine.runSeniorBowl` is idempotent, so a save that
    /// re-enters the phase does not get a second week.
    private static func runSeniorBowlEvent(career: Career, modelContext: ModelContext) {
        let scouts: [Scout] = {
            guard let teamID = career.teamID else { return [] }
            return fetchAllScouts(modelContext: modelContext).filter { $0.teamID == teamID }
        }()

        guard let result = ScoutingEngine.runSeniorBowl(
            prospects: &currentDraftClass,
            scouts: scouts,
            seed: ScoutingEngine.cycleSeed(
                careerID: career.id,
                season: career.currentSeason,
                salt: ScoutingEngine.CycleSalt.seniorBowl
            )
        ) else { return }

        lastNewsItems.append(contentsOf: NewsGenerator.seniorBowlNews(
            result: result,
            season: career.currentSeason
        ))
        if let message = InboxEngine.seniorBowlDigestMessage(
            result: result,
            dateString: InboxEngine.dateLabel(
                week: 0, season: career.currentSeason, phase: .coachingChanges
            )
        ) {
            lastInboxMessages.append(message)
        }

        // The practice week moves stock like any other information event, and it
        // feeds the same zero-sum board the combine drift uses.
        let moves = ScoutingEngine.applyProjectionDrift(
            prospects: &currentDraftClass,
            pressure: result.pressure,
            maxShift: 1,
            maxPairs: 10,
            seed: ScoutingEngine.cycleSeed(
                careerID: career.id,
                season: career.currentSeason,
                salt: ScoutingEngine.CycleSalt.seniorBowl &+ 1
            )
        )
        if !moves.isEmpty {
            lastNewsItems.append(contentsOf: NewsGenerator.projectionDriftNews(
                moves: moves,
                season: career.currentSeason,
                limit: 2
            ))
        }

        persistDraftClass(currentDraftClass, to: modelContext)
    }

    // MARK: - Private: Future Draft Picks (plan finding S1)

    /// Turns this year's projected pick rows into the real board.
    ///
    /// The rows were minted 1-3 seasons ago at the midpoint of their round so they
    /// could be traded; now the standings that decide the slots exist. Each row is
    /// renumbered by the SLOT ITS ORIGINAL TEAM EARNED — `currentTeamID` is never
    /// touched, so a pick acquired in a trade lands where the team it came from
    /// finished and keeps rendering "via ABC". Rows that were never provisional
    /// (compensatory awards, which belong at the END of their round) keep that
    /// position and are numbered after the round's base picks.
    ///
    /// Mutates in place: these are the persisted rows, identity and all, which is
    /// the whole point — regenerating the board would orphan every traded pick.
    private static func adoptFuturePicks(
        _ picks: [DraftPick],
        teams: [Team],
        games: [Game]
    ) {
        let slotOrder = DraftEngine.draftSlotOrder(teams: teams, games: games)
        var slotByTeam: [UUID: Int] = [:]
        for (index, teamID) in slotOrder.enumerated() { slotByTeam[teamID] = index }
        // `TradeEngine.executeTrade` swaps `currentTeamID` but not the cached
        // abbreviation, so a pick that changed hands years ago would still carry
        // its old owner's tag into the war room. Re-stamp it here, once.
        var abbrByTeam: [UUID: String] = [:]
        for team in teams { abbrByTeam[team.id] = team.abbreviation }
        // A team missing from the standings (shouldn't happen) sorts last rather
        // than colliding with slot 0.
        let unknownSlot = slotOrder.count

        var overall = 1
        for round in 1...7 {
            let inRound = picks.filter { $0.round == round }
            let base = inRound
                .filter { $0.isProvisionalOrder }
                .sorted { lhs, rhs in
                    let ls = slotByTeam[lhs.originalTeamID] ?? unknownSlot
                    let rs = slotByTeam[rhs.originalTeamID] ?? unknownSlot
                    if ls != rs { return ls < rs }
                    // Two rows from the same original team (only possible if a
                    // trade duplicated ownership) — keep a stable, id-based order.
                    return lhs.id.uuidString < rhs.id.uuidString
                }
            let extras = inRound
                .filter { !$0.isProvisionalOrder }
                .sorted { $0.pickNumber < $1.pickNumber }

            for pick in base + extras {
                pick.pickNumber = overall
                pick.isProvisionalOrder = false
                if let abbr = abbrByTeam[pick.currentTeamID] {
                    pick.teamAbbreviation = abbr
                }
                overall += 1
            }
        }
    }

    /// Keeps three future drafts on the shelf at all times.
    ///
    /// Idempotent and self-healing: it mints only the years that have no rows at
    /// all, so calling it every advance costs three cheap count fetches, a save
    /// created before future picks existed grows its horizon the first time it
    /// advances, and the rollover (`startNewSeason`) simply adds year N+3.
    private static func ensureFuturePickHorizon(
        career: Career,
        teams: [Team],
        modelContext: ModelContext
    ) {
        guard teams.count >= 2 else { return }
        let season = career.currentSeason
        let cid = career.id
        for year in (season + 1)...(season + LeagueGenerator.futurePickHorizon) {
            var descriptor = FetchDescriptor<DraftPick>(
                predicate: #Predicate<DraftPick> { $0.careerID == cid && $0.seasonYear == year }
            )
            descriptor.fetchLimit = 1
            let existing = (try? modelContext.fetch(descriptor)) ?? []
            guard existing.isEmpty else { continue }
            for pick in LeagueGenerator.futureDraftPicks(
                teams: teams,
                afterSeason: year - 1,
                horizon: 1
            ) {
                pick.careerID = cid
                modelContext.insert(pick)
            }
        }
    }

    // MARK: - Private: Compensatory Picks (R23)

    /// Settles the FA departure ledger into compensatory picks at the close of
    /// free agency. If an upcoming draft pool is already persisted (e.g. the
    /// league-generation pool for the first draft), the comp picks are slotted
    /// straight into it; otherwise they are stashed and attached when the
    /// draft order is generated. Emits an inbox message for the user's haul
    /// and a news item for the biggest league-wide winner.
    private static func settleCompensatoryPicks(
        career: Career,
        teams: [Team],
        allPlayers: [Player],
        modelContext: ModelContext
    ) {
        let departures = CompensatoryPickEngine.departures()
        guard !departures.isEmpty else { return }

        let awards = CompensatoryPickEngine.computeAwards(
            departures: departures,
            allPlayers: allPlayers,
            allTeams: teams
        )
        CompensatoryPickEngine.clearDepartures()
        guard !awards.isEmpty else {
            CompensatoryPickEngine.clearPendingAwards()
            return
        }

        var teamAbbrs: [UUID: String] = [:]
        for team in teams { teamAbbrs[team.id] = team.abbreviation }

        // Slot into an already-persisted upcoming pool when one exists;
        // otherwise leave the awards pending for draft-order generation.
        let season = career.currentSeason
        let cid = career.id
        let poolDescriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate<DraftPick> {
                $0.careerID == cid && $0.seasonYear == season && $0.isComplete == false
            }
        )
        let existingPool = (try? modelContext.fetch(poolDescriptor)) ?? []
        // A pool whose order is still PROVISIONAL (future-pick rows whose year has
        // come up but whose slots resolve at the proDays → draft boundary) is not
        // something to slot into: `applyAwards` renumbers the whole pool
        // sequentially, and doing that to 32 identical midpoint numbers would
        // invent an order that `adoptFuturePicks` then overwrites anyway. Stash
        // instead — `prepareDraftOrder` attaches the awards right after adoption.
        if existingPool.count >= 32,
           !existingPool.contains(where: { $0.isProvisionalOrder }) {
            let compPicks = CompensatoryPickEngine.applyAwards(
                awards,
                toPickPool: existingPool,
                seasonYear: season,
                teamAbbrs: teamAbbrs
            )
            for pick in compPicks {
                pick.careerID = cid
                modelContext.insert(pick)
            }
            CompensatoryPickEngine.clearPendingAwards()
        } else {
            CompensatoryPickEngine.stashPendingAwards(awards)
        }

        // Inbox: the user's own compensatory haul.
        if let userTeamID = career.teamID {
            let mine = awards.filter { $0.teamID == userTeamID }
            if !mine.isEmpty {
                let lines = mine.map { award in
                    "\u{2022} Round \(award.round) — for losing \(award.lostPlayerName) ($\(String(format: "%.1f", Double(award.lostPlayerSalary) / 1000.0))M/yr elsewhere)"
                }
                lastInboxMessages.append(InboxMessage(
                    sender: .leagueOffice,
                    subject: "Compensatory Picks Awarded",
                    body: """
                    The league has finalized compensatory selections for the upcoming draft. Based on your net free agency losses, you receive:

                    \(lines.joined(separator: "\n"))

                    Compensatory picks slot in at the end of their round.
                    """,
                    date: "Offseason - Free Agency, Season \(career.currentSeason)",
                    category: .leagueNotice
                ))
            }
        }

        // News: the biggest comp-pick winner league-wide.
        let byTeam = Dictionary(grouping: awards, by: { $0.teamID })
        if let (topTeamID, topAwards) = byTeam.max(by: { $0.value.count < $1.value.count }) {
            let abbr = teamAbbrs[topTeamID] ?? "???"
            let rounds = topAwards.map { "R\($0.round)" }.joined(separator: ", ")
            lastNewsItems.append(NewsItem(
                headline: "\(abbr) lead comp-pick haul with \(topAwards.count) extra selection\(topAwards.count == 1 ? "" : "s")",
                body: "The league finalized compensatory picks for the upcoming draft. \(abbr) top the list (\(rounds)) after their net free agency losses. \(awards.count) compensatory selection\(awards.count == 1 ? "" : "s") were awarded in total.",
                category: .draft,
                week: career.currentWeek,
                season: career.currentSeason,
                relatedTeamID: topTeamID,
                sentiment: .neutral
            ))
        }
    }

    // MARK: - Private: Phase Group Transition Banner

    /// Emits an inbox message announcing a phase-group boundary crossing
    /// (e.g. Pre-Draft → Pre Season). The message is appended to
    /// `lastInboxMessages` and surfaced to the UI through the same channel
    /// as other phase-transition messages. No-op when the two phases share
    /// the same group.
    private static func emitGroupTransitionMessageIfNeeded(
        oldPhase: SeasonPhase,
        newPhase: SeasonPhase,
        season: Int
    ) {
        guard oldPhase.group != newPhase.group else { return }

        let group = newPhase.group
        let title: String
        let body: String

        switch group {
        case .postseason:
            title = "Postseason Begins"
            body = "Pro Bowl rosters announced. The hardware is being handed out."
        case .offseason:
            title = "Offseason Begins"
            body = "Time to evaluate. Coach contracts come due, the roster gets a fresh look."
        case .preDraft:
            title = "Pre-Draft Phase"
            body = "Scouts at the Combine. The road to draft night begins."
        case .preSeason:
            title = "Pre Season Begins"
            body = "OTAs open the doors. Training camp battles start. 90 \u{2192} 53."
        case .regularSeason:
            title = "Regular Season"
            body = "Lights on. Cuts settled. Time to play football."
        }

        let msg = InboxMessage(
            sender: .leagueOffice,
            subject: title,
            body: body,
            date: "Season \(season) — \(group.displayName)",
            category: .leagueNotice
        )
        lastInboxMessages.append(msg)
    }

    // MARK: - Private: Phase Ordering

    /// Returns the phase that immediately follows `phase` in the annual calendar.
    ///
    /// Full offseason → preseason chain (matches NFL calendar):
    /// playoffs → proBowl → superBowl → coachingChanges → reviewRoster → combine →
    /// freeAgency → draft → otas → trainingCamp → preseason → rosterCuts → regularSeason
    ///
    /// In-season transitions are handled by the regular-season / playoff
    /// logic and are not part of this chain.
    private static func phase(after phase: SeasonPhase) -> SeasonPhase {
        switch phase {
        case .proBowl:          return .superBowl
        case .superBowl:        return .coachingChanges
        case .coachingChanges:  return .reviewRoster
        case .reviewRoster:     return .combine
        case .combine:          return .freeAgency
        case .freeAgency:       return .proDays
        case .proDays:          return .draft
        case .draft:            return .otas
        case .otas:             return .trainingCamp
        case .trainingCamp:     return .preseason
        case .preseason:        return .rosterCuts
        case .rosterCuts:       return .regularSeason
        // These cases should be handled by their dedicated advance functions,
        // but return a sensible fallback to avoid unhandled switches.
        case .regularSeason:    return .playoffs
        case .tradeDeadline:    return .regularSeason
        case .playoffs:         return .proBowl
        }
    }

    // MARK: - Private: Team Record Updates

    /// Updates `Team.wins`/`losses`/`ties` from a played game's final score.
    /// Internal (not private) because it is shared with `LiveGameEngine.persist`.
    ///
    /// R32: playoff games never touch these fields — `Team.wins/losses/ties`
    /// are the REGULAR-SEASON record that standings, budgets, and owner goals
    /// all read. Playoff outcomes live in the bracket games themselves.
    /// (Before R32 the postseason had no real Game rows, so this guard
    /// changes nothing for existing behavior.)
    static func updateTeamRecords(game: Game, teamsByID: [UUID: Team]) {
        guard !game.isPlayoff else { return }
        guard let homeScore = game.homeScore,
              let awayScore = game.awayScore else { return }

        let homeTeam = teamsByID[game.homeTeamID]
        let awayTeam = teamsByID[game.awayTeamID]

        if homeScore > awayScore {
            homeTeam?.wins   += 1
            awayTeam?.losses += 1
        } else if awayScore > homeScore {
            awayTeam?.wins   += 1
            homeTeam?.losses += 1
        } else {
            homeTeam?.ties += 1
            awayTeam?.ties += 1
        }
    }

    // MARK: - Private: SwiftData Helpers

    private static func fetchUnplayedGames(
        week: Int,
        seasonYear: Int,
        isPlayoff: Bool,
        modelContext: ModelContext
    ) -> [Game] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { game in
                game.careerID == cid &&
                game.week == week &&
                game.seasonYear == seasonYear &&
                game.isPlayoff == isPlayoff &&
                game.homeScore == nil
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetches every regular-season game scheduled for the given week,
    /// regardless of whether it has been played yet. Used by the #33
    /// games-played bookkeeping so a live-coached user game (already played
    /// before `advanceWeek`) is credited alongside the AI-simmed games.
    private static func fetchAllRegularSeasonGames(
        week: Int,
        seasonYear: Int,
        modelContext: ModelContext
    ) -> [Game] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { game in
                game.careerID == cid &&
                game.week == week &&
                game.seasonYear == seasonYear &&
                game.isPlayoff == false
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetches the player team's already-played regular-season game for the
    /// given week, if any. Used to detect games coached interactively via
    /// `LiveGameEngine` (they are played before `advanceWeek` runs).
    private static func fetchPlayedPlayerGame(
        week: Int,
        seasonYear: Int,
        teamID: UUID,
        modelContext: ModelContext
    ) -> Game? {
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate<Game> { game in
                game.week == week &&
                game.seasonYear == seasonYear &&
                game.isPlayoff == false &&
                game.homeScore != nil &&
                (game.homeTeamID == teamID || game.awayTeamID == teamID)
            }
        )
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Distills the player's last game result into the concrete facts the
    /// weekly press conference can quote (final margin, sacks allowed, a
    /// 100-yard rusher). Returns nil when the player had no played game this
    /// week — the presser then falls back to its pre-R18 question selection.
    ///
    /// `PlayerGameStats` carries no team id, so team membership is resolved
    /// via the live rosters: every stat line whose player is NOT on the
    /// player's roster belongs to the opponent (both game rosters are fully
    /// covered by `result.playerStats`).
    private static func pressGameFacts(
        lastGameWon: Bool?,
        result: GameSimulator.GameResult?,
        playerTeamID: UUID,
        allPlayers: [Player],
        teamsByID: [UUID: Team],
        narrative: LeagueNarrativeState? = nil
    ) -> PressConferenceEngine.GameFacts? {
        guard let won = lastGameWon, let result else { return nil }

        let playerTeamPlayerIDs = Set(
            allPlayers.filter { $0.teamID == playerTeamID }.map(\.id)
        )
        guard !playerTeamPlayerIDs.isEmpty else { return nil }

        let margin = abs(result.homeScore - result.awayScore)

        // Sacks the player's line surrendered = opponent defenders' sacks.
        let sacksAllowed = Int(
            result.playerStats
                .filter { !playerTeamPlayerIDs.contains($0.playerID) }
                .reduce(0.0) { $0 + $1.sacks }
                .rounded()
        )

        let topRusher = result.playerStats
            .filter { playerTeamPlayerIDs.contains($0.playerID) && $0.rushingYards >= 100 }
            .max { $0.rushingYards < $1.rushingYards }

        // Division matchup (R19): the box score names both teams — when the
        // opponent shares the player's division, the presser gets the rivalry
        // variants of the win/loss questions.
        let opponentID = result.boxScore.home.teamID == playerTeamID
            ? result.boxScore.away.teamID
            : result.boxScore.home.teamID
        let divisionOpponentAbbr: String? = {
            guard let myTeam = teamsByID[playerTeamID],
                  let opponent = teamsByID[opponentID],
                  opponent.conference == myTeam.conference,
                  opponent.division == myTeam.division
            else { return nil }
            return opponent.abbreviation
        }()

        // R29: this week's power ranking + MVP-race hooks for the presser.
        let rankingEntry = narrative?.rankings.first { $0.teamID == playerTeamID }
        let mvpEntry = narrative?.mvpRace.enumerated().first { $0.element.teamID == playerTeamID }

        return PressConferenceEngine.GameFacts(
            won: won,
            margin: margin,
            sacksAllowed: sacksAllowed,
            hundredYardRusherName: topRusher?.playerName,
            hundredYardRusherYards: topRusher?.rushingYards ?? 0,
            divisionOpponentAbbr: divisionOpponentAbbr,
            powerRank: rankingEntry?.rank,
            powerRankMovement: rankingEntry?.movement ?? 0,
            mvpCandidateName: mvpEntry?.element.playerName,
            mvpCandidateRank: mvpEntry.map { $0.offset + 1 }
        )
    }

    private static func fetchTeamsByID(modelContext: ModelContext) -> [UUID: Team] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.careerID == cid })
        let teams = (try? modelContext.fetch(descriptor)) ?? []
        return Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
    }

    private static func fetchAllTeams(modelContext: ModelContext) -> [Team] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<Team>(predicate: #Predicate { $0.careerID == cid })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchAllPlayers(modelContext: ModelContext) -> [Player] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<Player>(predicate: #Predicate { $0.careerID == cid })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchAllCoaches(modelContext: ModelContext) -> [Coach] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<Coach>(predicate: #Predicate { $0.careerID == cid })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - R30: Coaching Tree Alumni Evaluation

    /// Once per offseason: checks how the user's coaching-tree alumni fared at
    /// their new stops. An alumnus on a team that won 10+ games flips to
    /// "successful", which grows the tree's legacy score — and the user's own
    /// reputation gets a small bump (+1 per newly successful alumnus, max +2
    /// per season) with a news nod for the first one.
    private static func evaluateCoachingTreeAlumni(
        career: Career,
        teams: [Team],
        allCoaches: [Coach]
    ) {
        var tree = career.coachingTree
        guard !tree.alumni.isEmpty else { return }

        let teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        var reputationGain = 0
        var firstSuccess: (coachName: String, teamName: String, role: CoachRole)?

        for entry in tree.alumni where !entry.wasSuccessful {
            // Alumni are tracked by name snapshot — find them in the league.
            guard let coach = allCoaches.first(where: {
                      $0.fullName == entry.coachName && $0.teamID != nil && $0.teamID != career.teamID
                  }),
                  let team = coach.teamID.flatMap({ teamsByID[$0] })
            else { continue }

            // Success at the next stop: a clearly winning season.
            guard team.wins >= 10 else { continue }

            CoachRelationshipEngine.markCoachingTreeSuccess(
                tree: &tree.entries,
                coachName: entry.coachName,
                wasSuccessful: true
            )
            if reputationGain < 2 { reputationGain += 1 }
            if firstSuccess == nil {
                firstSuccess = (entry.coachName, team.fullName, coach.role)
            }
        }

        guard reputationGain > 0, let success = firstSuccess else {
            career.coachingTree = tree
            return
        }

        career.coachingTree = tree
        career.reputation = min(99, career.reputation + reputationGain)

        lastNewsItems.append(NewsItem(
            headline: "Coaching tree watch: \(success.coachName) thriving",
            body: "\(success.coachName), who cut their teeth on \(career.playerName)'s staff, just led the \(success.teamName) to a double-digit win season as \(success.role.displayName.lowercased()). Around the league, \(career.playerName)'s coaching tree keeps gaining respect.",
            category: .coachingChange,
            week: 0,
            season: career.currentSeason,
            sentiment: .positive
        ))
    }

    private static func fetchAllScouts(modelContext: ModelContext) -> [Scout] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<Scout>(predicate: #Predicate { $0.careerID == cid })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Draft picks that haven't been used yet — the tradable pick pool (R21).
    private static func fetchActiveDraftPicks(modelContext: ModelContext) -> [DraftPick] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<DraftPick>(
            predicate: #Predicate { $0.careerID == cid && !$0.isComplete }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Private: Wave 2 Trade Market (docs/TRADE_OVERHAUL_PLAN.md §6)

    /// Runs one AI-vs-AI market window and routes its output into the same
    /// persistence every other league event already uses: `lastNewsItems` (which
    /// `advanceWeek` folds into the persisted `career.newsLog`) and
    /// `lastInboxMessages` (collected by `CareerShellView` after the advance).
    ///
    /// Every executed deal goes through `TradeNewsFactory.announce`, which is the
    /// user's standing Wave 2 requirement: nothing moves in this league without
    /// him being able to read about it, and anything that touches or should
    /// inform his club also lands in his inbox.
    @discardableResult
    private static func runLeagueMarketWindow(
        window: TradeValueEngine.MarketWindow,
        career: Career,
        teams: [Team],
        teamsByID: [UUID: Team],
        allPlayers: [Player],
        week: Int,
        modelContext: ModelContext
    ) -> TradeValueEngine.LeagueMarketResult {
        let target = leagueMarketTarget(window: window)
        guard target > 0 else { return TradeValueEngine.LeagueMarketResult() }

        let activePicks = fetchActiveDraftPicks(modelContext: modelContext)
        let result = TradeValueEngine.runLeagueMarketPass(
            window: window,
            targetCount: target,
            userTeamID: career.teamID,
            teams: teams,
            allPlayers: allPlayers,
            allPicks: activePicks,
            capMode: career.capMode,
            currentSeason: career.currentSeason,
            week: week,
            modelContext: modelContext
        )

        for record in result.records {
            let announcement = TradeNewsFactory.announce(
                record: record,
                teamsByID: teamsByID,
                userTeamID: career.teamID
            )
            lastNewsItems.append(announcement.news)
            if let inbox = announcement.inbox {
                lastInboxMessages.append(inbox)
            }
        }

        if window.isInSeason {
            leagueTradesThisSeason += result.count
        } else {
            leagueTradesThisOffseason += result.count
        }
        return result
    }

    /// Target deal count for one window: the market's own calendar shape
    /// (`TradeValueEngine.leagueTradeTarget`), clamped by the §5 ceilings and
    /// topped up by whatever the cycle owes.
    ///
    /// The catch-up matters more than it looks: a particular league year can have
    /// few willing sellers (everyone .500, nobody with cap room), and without it
    /// a quiet October would silently push the season under §5's 8-25 in-season
    /// band. With it, deadline day settles the account — which is also exactly
    /// what the real deadline is for.
    private static func leagueMarketTarget(window: TradeValueEngine.MarketWindow) -> Int {
        switch window {
        case .week:
            let headroom = maxLeagueTradesInSeason - leagueTradesThisSeason
            return max(0, min(headroom, TradeValueEngine.leagueTradeTarget(window: window)))

        case .deadline:
            // ≈7 deals is what weeks 1-8 are expected to produce between them.
            let deficit = max(0, 7 - leagueTradesThisSeason)
            let headroom = maxLeagueTradesInSeason - leagueTradesThisSeason
            return max(0, min(
                headroom,
                TradeValueEngine.leagueTradeTarget(window: window, deficit: deficit)
            ))

        case .offseason(let phase):
            // Cumulative expectation entering each window, so a slow post-season
            // is made up in March rather than lost. The order is the CALENDAR's
            // (`phase(after:)`): reviewRoster → freeAgency → proDays → draft →
            // otas → trainingCamp → preseason → rosterCuts, i.e. cut days are the
            // LAST window of the cycle and carry the final catch-up.
            let expectedBefore: Int
            switch phase {
            case .reviewRoster: expectedBefore = 0
            case .freeAgency:   expectedBefore = 6
            case .proDays:      expectedBefore = 13
            case .otas:         expectedBefore = 20
            case .rosterCuts:   expectedBefore = 26
            default:            return 0
            }
            let deficit = max(0, expectedBefore - leagueTradesThisOffseason)
            let headroom = maxLeagueTradesOffseason - leagueTradesThisOffseason
            return max(0, min(
                headroom,
                TradeValueEngine.leagueTradeTarget(window: window, deficit: deficit)
            ))
        }
    }

    /// The offseason half of the market (finding S5: "Offseason:
    /// `isTradeWindowOpen` says open, but nothing ever generates an offer").
    ///
    /// Two jobs per window: 2-5 AI calls to the user across the whole offseason
    /// (post-season retool talks, post-FA, pre-draft, cut days, OTAs) and the
    /// AI-vs-AI pass for the same window, which is where most of §5's 15-40
    /// offseason trades come from.
    private static func runOffseasonTradeMarket(
        window: TradeValueEngine.MarketWindow,
        career: Career,
        teams: [Team],
        teamsByID: [UUID: Team],
        allPlayers: [Player],
        modelContext: ModelContext
    ) {
        let season = career.currentSeason
        let week = career.currentWeek

        // 1. The user's phone.
        if let userTeamID = career.teamID, let userTeam = teamsByID[userTeamID] {
            let hazard = TradeValueEngine.userOfferHazard(
                window: window, offersSoFar: aiOffersThisOffseason
            )
            if hazard.rolls > 0 {
                let activePicks = fetchActiveDraftPicks(modelContext: modelContext)
                let contractCareerID = activeCareerID
                let contracts = (try? modelContext.fetch(FetchDescriptor<Contract>(
                    predicate: #Predicate { $0.careerID == contractCareerID }
                ))) ?? []
                for _ in 0..<hazard.rolls {
                    guard aiOffersThisOffseason < TradeValueEngine.maxOffseasonOffers else { break }
                    guard Int.random(in: 1...100) <= hazard.chancePercent else { continue }
                    let alreadyOffering = Set(career.pendingTradeOffers.map(\.offeringTeamID))
                    guard let offer = TradeValueEngine.generateAIOffer(
                        window: window,
                        userTeam: userTeam,
                        allTeams: teams,
                        allPlayers: allPlayers,
                        allPicks: activePicks,
                        capMode: career.capMode,
                        currentSeason: season,
                        week: week,
                        contracts: contracts,
                        excludingTeamIDs: alreadyOffering
                    ) else { continue }

                    var pending = career.pendingTradeOffers
                    pending.removeAll { $0.offeringTeamID == offer.proposal.offeringTeamID }
                    pending.append(offer.proposal)
                    career.pendingTradeOffers = Array(pending.suffix(5))
                    aiTradeOffersGenerated += 1
                    aiTradeOffersOffseasonGenerated += 1
                    aiOffersThisOffseason += 1
                    lastInboxMessages.append(
                        TradeValueEngine.offerInboxMessage(offer: offer, week: week, season: season)
                    )
                }
            }
        }

        // 2. The league's own business.
        runLeagueMarketWindow(
            window: window,
            career: career,
            teams: teams,
            teamsByID: teamsByID,
            allPlayers: allPlayers,
            week: week,
            modelContext: modelContext
        )
    }

    // MARK: - Private: Open Trade Threads (Wave 3 follow-up — task #39)

    /// Gives every open user conversation ONE AI move per week.
    ///
    /// WHY: Wave 3 made a trade negotiation a persisted thread that outlives the
    /// week advance, but only the user could ever move inside it — the GM sat
    /// exactly where the last tap left him for as long as the window stayed open,
    /// so a thread the user let breathe was indistinguishable from a dead one.
    /// A front office works the phones between games, and that is also what makes
    /// the persistence worth having: a package that was two points short in week
    /// 3 is worth re-reading in week 8, because the man on the other end has a
    /// deadline too.
    ///
    /// Three outcomes per thread, checked in this order:
    /// - WALK AWAY — the GM has stopped taking calls (the Wave 2 talk lock), or
    ///   the conversation has gone quiet for longer than his persona's patience.
    /// - SWEETEN — he re-prices the package one round further down his concession
    ///   curve (task #36), leaves a standing counter and mails a note.
    /// - HOLD — most weeks. Nothing is written, so the thread rolls again next
    ///   week.
    ///
    /// The one-move-per-thread-per-week cap is `lastActivityWeek < week`: a
    /// conversation the user worked THIS week is the user's turn, and a GM who
    /// has already moved this week is done until the next advance.
    ///
    /// In-season only, deliberately. The offseason market runs per PHASE, not per
    /// week (`runOffseasonTradeMarket` is handed a frozen `career.currentWeek`),
    /// so the week-based cap has nothing to bite on there; offseason threads keep
    /// waiting for the user exactly as before.
    @discardableResult
    private static func advanceOpenTradeThreads(
        career: Career,
        teamsByID: [UUID: Team],
        allPlayers: [Player],
        week: Int,
        season: Int,
        modelContext: ModelContext
    ) -> Int {
        let stored = career.tradeThreads
        let hasMovable = stored.contains {
            $0.status == .open && $0.season == season && $0.lastActivityWeek < week
        }
        guard hasMovable else { return 0 }
        guard TradeValueEngine.isTradeWindowOpen(
            phase: career.currentPhase, week: week
        ) else { return 0 }

        let activePicks = fetchActiveDraftPicks(modelContext: modelContext)
        let contractCareerID = activeCareerID
        let contracts = (try? modelContext.fetch(FetchDescriptor<Contract>(
            predicate: #Predicate { $0.careerID == contractCareerID }
        ))) ?? []
        let dateString = InboxEngine.dateLabel(
            week: week, season: season, phase: career.currentPhase
        )

        var threads = stored
        var moved = 0

        for (index, thread) in stored.enumerated() {
            guard thread.status == .open,
                  thread.season == season,
                  thread.lastActivityWeek < week else { continue }
            // A thread is always written from the user's chair, so the AI is the
            // receiving side — the shape `TradeValueEngine.respond` assumes.
            guard let partner = teamsByID[thread.partnerTeamID],
                  thread.proposal.receivingTeamID == thread.partnerTeamID else { continue }
            // A conversation whose assets have already moved belongs to the Trade
            // Center's reconcile pass (`loadThreads` expires it and mails the
            // receipt). Re-pricing it here would quote a package that no longer
            // exists.
            guard TradeValueEngine.isProposalStillValid(
                thread.proposal, allPlayers: allPlayers, allPicks: activePicks
            ) else { continue }

            let identity = TradeValueEngine.gmIdentity(team: partner, season: season)
            var updated = thread

            // 1a. He is not taking calls any more — the thread cannot just sit
            // there advertising a live conversation.
            if !identity.talksOpen {
                updated.status = .brokenOff
                updated.lastActivityWeek = week
                updated.messages.append(TradeThreadMessage(
                    sender: .system,
                    text: "\(identity.name) has stopped taking calls from this front office. These talks are over until the new league year.",
                    round: updated.round
                ))
                threads[index] = updated
                moved += 1
                continue
            }

            // 1b. Silence has a limit, and it is his patience — the same number
            // the negotiation header shows as rounds left.
            if week - thread.lastActivityWeek > identity.patience {
                updated.status = .expired
                updated.lastActivityWeek = week
                updated.messages.append(TradeThreadMessage(
                    sender: .system,
                    text: "\(identity.name) moved on — \(partner.abbreviation) have taken the package off the table.",
                    round: updated.round
                ))
                threads[index] = updated
                moved += 1
                lastInboxMessages.append(InboxMessage(
                    sender: .leagueOffice,
                    subject: "\(partner.abbreviation) walked away from the trade talks",
                    body: """
                    \(identity.name) called to say the \(partner.fullName) are done waiting on us. The package we were discussing is off the table.

                    Nothing stops us starting a fresh conversation with them — this one is closed.

                    NFL League Office
                    """,
                    date: dateString,
                    category: .tradeOffer,
                    actionDestination: .trades
                ))
                continue
            }

            // 2. Does he pick up the phone this week?
            guard Int.random(in: 1...100) <= comebackChance(
                identity: identity,
                silentWeeks: week - thread.lastActivityWeek,
                week: week
            ) else { continue }

            // `rememberLowballs: false`: this is the AI's own move on a package
            // the user is not re-sending. A strike here would punish him for
            // sitting still, and could lock a GM out over a conversation the user
            // never touched.
            let response = TradeValueEngine.respond(
                to: thread.proposal,
                aiTeam: partner,
                allPlayers: allPlayers,
                allPicks: activePicks,
                currentSeason: season,
                contracts: contracts,
                week: week,
                rememberLowballs: false,
                round: thread.round + 1
            )

            switch response {
            case .countered(let counter, let message):
                updated.round += 1
                updated.lastActivityWeek = week
                updated.pendingCounter = counter
                updated.proposal = counter
                updated.messages.append(TradeThreadMessage(
                    sender: .gm, text: message, proposal: counter, round: updated.round
                ))

            case .accepted:
                // The week moved the market his way (needs, stance, the weekly
                // asking noise) — the package on the table now clears his bar.
                updated.round += 1
                updated.lastActivityWeek = week
                updated.pendingCounter = thread.proposal
                updated.messages.append(TradeThreadMessage(
                    sender: .gm,
                    text: "\(identity.name) called back — \(partner.abbreviation) will sign the package exactly as it stands.",
                    proposal: thread.proposal,
                    round: updated.round
                ))

            case .rejected:
                // Nothing he can put together this week. The thread stays live
                // and rolls again after the next game.
                continue
            }

            threads[index] = updated
            moved += 1
            lastInboxMessages.append(InboxMessage(
                sender: .leagueOffice,
                subject: "\(partner.abbreviation) came back: new offer in your trade talks",
                body: """
                \(identity.name) called back about the deal we have been working with the \(partner.fullName).

                There is a fresh package waiting in the Trade Center — open the conversation to read what changed and answer him.

                NFL League Office
                """,
                date: dateString,
                category: .tradeOffer,
                actionDestination: .trades
            ))
        }

        guard moved > 0 else { return 0 }
        career.tradeThreads = threads
        return moved
    }

    /// Odds (percent) that a GM makes his own move in an open thread this week.
    ///
    /// Three pressures, all of them things the user can reason about: who the man
    /// is, how long the line has been quiet, and how close the deadline is. The
    /// deadline term is the loud one — it is worth nothing five weeks out and a
    /// full 30 points in deadline week, which is exactly the shape the rest of
    /// the market already ramps on (`TradeValueEngine.userOfferHazard`).
    private static func comebackChance(
        identity: TradeValueEngine.GMIdentity,
        silentWeeks: Int,
        week: Int
    ) -> Int {
        let base: Int
        switch identity.archetype {
        case .aggressive: base = 40      // works the phones for a living
        case .balanced:   base = 28
        case .oldSchool:  base = 22
        case .analytics:  base = 18      // will happily let it sit
        }
        let urgency = max(0, 30 - 6 * max(0, tradeDeadlineWeek - week))
        let staleness = 5 * max(0, silentWeeks - 1)
        return min(75, base + urgency + staleness)
    }

    // MARK: - Private: Season Summary & Career Counters (R32)

    /// Writes the finished season into `career.seasonSummaries` (champion,
    /// user record, MVP) and increments the career-long counters. Runs during
    /// the `.superBowl` phase, right after the title game has been simulated
    /// and while the final records are still intact. Idempotent per season.
    private static func recordSeasonSummary(
        career: Career,
        teams: [Team],
        teamsByID: [UUID: Team],
        modelContext: ModelContext
    ) {
        let season = career.currentSeason
        guard !career.seasonSummaries.contains(where: { $0.season == season }) else { return }

        let seasonGames = fetchAllGamesForSeason(seasonYear: season, modelContext: modelContext)
        let playoffGames = seasonGames.filter { $0.isPlayoff }
        let superBowlGame = playoffGames.first { $0.week == 22 && $0.isPlayed }

        // Champion = Super Bowl winner; fallback (legacy edge) = best record.
        let championID: UUID? = superBowlGame?.winnerID
            ?? teams.max {
                ($0.wins, $1.losses) < ($1.wins, $0.losses)
            }?.id
        let championName = championID.flatMap { teamsByID[$0]?.fullName } ?? "Unknown"

        var userWins = 0, userLosses = 0, userTies = 0
        var madePlayoffs = false
        var wonChampionship = false
        if let userTeamID = career.teamID, let userTeam = teamsByID[userTeamID] {
            userWins = userTeam.wins
            userLosses = userTeam.losses
            userTies = userTeam.ties
            // Every bracket team plays at least one playoff game (the #1 seed
            // appears in the Divisional Round), so participation covers it.
            madePlayoffs = playoffGames.contains {
                $0.homeTeamID == userTeamID || $0.awayTeamID == userTeamID
            }
            wonChampionship = (championID == userTeamID)
        }

        let mvp = career.leagueNarrative?.mvpRace.first

        let summary = SeasonSummary(
            season: season,
            championTeamID: championID,
            championTeamName: championName,
            userWins: userWins,
            userLosses: userLosses,
            userTies: userTies,
            userMadePlayoffs: madePlayoffs,
            userWonChampionship: wonChampionship,
            mvpName: mvp?.playerName,
            mvpTeamAbbr: mvp?.teamAbbr
        )
        career.seasonSummaries = [summary] + career.seasonSummaries

        // Career-long counters (regular-season record only; the playoff
        // guard in `updateTeamRecords` keeps team W/L regular-season-pure).
        career.totalWins += userWins
        career.totalLosses += userLosses
        if madePlayoffs { career.playoffAppearances += 1 }
        if wonChampionship {
            career.championships += 1
            career.legacy.recordAchievement(LegacyTracker.LegacyAchievement(
                title: "Super Bowl Champion",
                description: "Won the Season \(season) championship.",
                points: 100,
                season: season
            ))
            lastInboxMessages.append(InboxMessage(
                sender: .leagueOffice,
                subject: "WORLD CHAMPIONS",
                body: "Your team has won the Super Bowl. The city is planning the parade — enjoy this one, coach. It goes on your legacy forever.",
                date: "Super Bowl, Season \(season)",
                category: .leagueNotice
            ))
        }

        // Championship headline for the league feed.
        if let championID, let champion = teamsByID[championID] {
            let scoreLine: String
            if let game = superBowlGame,
               let home = game.homeScore, let away = game.awayScore,
               let loserID = game.loserID,
               let loser = teamsByID[loserID] {
                scoreLine = "They defeated the \(loser.fullName) \(max(home, away))-\(min(home, away)) in the title game."
            } else {
                scoreLine = "They finished the year as the league's best team."
            }
            let mvpLine = mvp.map { " Season MVP honors went to \($0.playerName) (\($0.teamAbbr))." } ?? ""
            lastNewsItems.append(NewsItem(
                headline: "\(champion.fullName) win the Super Bowl",
                body: "The \(champion.fullName) are the Season \(season) champions. \(scoreLine)\(mvpLine)",
                category: .award,
                week: 22,
                season: season,
                relatedTeamID: championID,
                sentiment: wonChampionship ? .positive : .neutral
            ))
        }
    }

    // MARK: - Private: Player Retirements (R32)

    /// Once per offseason (`.coachingChanges`): rolls retirement for every
    /// non-retired player in the league, applies the departures, and produces
    /// the news/inbox/Hall of Fame output:
    /// - stars (career peak OVR ≥ 88) get a ceremony headline,
    /// - the user's own legends say farewell via the inbox (+ legacy credit),
    /// - HOF qualifiers form the annual induction class.
    private static func processPlayerRetirements(
        career: Career,
        teamsByID: [UUID: Team],
        allPlayers: [Player],
        modelContext: ModelContext
    ) {
        // Career-peak OVR per player from season-history snapshots. #21: the same
        // rows carry the career PRODUCTION the induction now snapshots, so they
        // are kept grouped by player rather than reduced to a peak and thrown
        // away.
        let historyByPlayer = seasonHistoryByPlayer(
            careerID: activeCareerID,
            modelContext: modelContext
        )
        var peakByID: [UUID: Int] = [:]
        for (playerID, rows) in historyByPlayer {
            peakByID[playerID] = rows.map(\.overallAtEndOfSeason).max() ?? 0
        }

        // Task #84: the trophy case the "goes out on top" case reads. Rings are
        // derived, not stored — a player won a title in season S if the club he
        // finished S on is the club `recordSeasonSummary` wrote as that season's
        // champion. Elite seasons come off the same rows. Both are cheap folds
        // over history we already fetched, so nothing new is persisted and
        // nothing can drift out of sync with the record book.
        let championBySeason: [Int: UUID] = career.seasonSummaries.reduce(into: [:]) { map, summary in
            if let championID = summary.championTeamID { map[summary.season] = championID }
        }
        var trophyCases: [UUID: PlayerRetirementEngine.TrophyCase] = [:]
        for (playerID, rows) in historyByPlayer {
            var trophies = PlayerRetirementEngine.TrophyCase()
            for row in rows {
                if let teamID = row.teamID, championBySeason[row.season] == teamID {
                    trophies.rings += 1
                }
                if row.overallAtEndOfSeason >= PlayerRetirementEngine.starPeakOverall {
                    trophies.eliteSeasons += 1
                }
            }
            trophies.isHallOfFameTrack = PlayerRetirementEngine.qualifiesForHallOfFame(
                peakOverall: peakByID[playerID] ?? 0,
                seasonsPlayed: rows.count
            )
            trophyCases[playerID] = trophies
        }

        let specialSeed = PlayerRetirementEngine.specialCaseSeed(
            careerID: career.id,
            season: career.currentSeason
        )
        let retirements = PlayerRetirementEngine.evaluateRetirements(
            allPlayers: allPlayers,
            peakOverallByPlayerID: peakByID,
            special: PlayerRetirementEngine.SpecialCaseContext(
                isEnabled: true,
                seed: specialSeed,
                trophyCaseByPlayerID: trophyCases
            )
        )
        guard !retirements.isEmpty else { return }

        let season = career.currentSeason
        let dateString = InboxEngine.dateLabel(
            week: 0, season: season, phase: .coachingChanges
        )
        var inductees: [HallOfFameEntry] = []
        var starHeadlines = 0

        for retirement in retirements {
            let player = retirement.player
            let teamName = retirement.teamIDAtRetirement
                .flatMap { teamsByID[$0]?.fullName } ?? "Free Agent"
            let wasUserPlayer = career.teamID != nil
                && retirement.teamIDAtRetirement == career.teamID

            // #21: the career the ceremony is actually about. Every number below
            // is summed from this player's real persisted seasons — nothing here
            // is a rating standing in for production.
            let history = historyByPlayer[player.id] ?? []
            let facts = MilestoneTracker.careerFacts(history: history)
            let resume = facts.isEmpty
                ? nil
                : MilestoneTracker.hallOfFameSummary(position: player.position, facts: facts)

            ChurnDiag.record(ChurnDiag.retire, player)
            PlayerRetirementEngine.retire(retirement, teamsByID: teamsByID)

            // Task #84: the row remembers when and why. The comeback pass three
            // offseasons from now has no other way to ask either question.
            player.retirementSeason = season
            player.retirementCaseRaw = retirement.retirementCase.rawValue

            // Task #84: the two special cases REPLACE the generic ceremony for
            // the man they fired on — one departure, one headline. Everything
            // else about him (cap, Hall of Fame, roster spot) has already gone
            // through the ordinary path above.
            switch retirement.retirementCase {
            case .injuryToll:
                let weeksOut = player.injuryHistory.reduce(0) { $0 + $1.weeksOut }
                lastNewsItems.append(RetirementCaseNewsFactory.injuryToll(
                    player: player,
                    teamName: teamName == "Free Agent" ? nil : teamName,
                    peakOverall: retirement.peakOverall,
                    careerWeeksOut: weeksOut,
                    season: season,
                    teamID: retirement.teamIDAtRetirement
                ))
                if wasUserPlayer {
                    lastInboxMessages.append(InboxEngine.shockRetirementMessage(
                        playerName: player.fullName,
                        positionRaw: player.position.rawValue,
                        age: player.age,
                        seasonsPlayed: max(1, player.yearsPro),
                        careerWeeksOut: weeksOut,
                        dateString: dateString
                    ))
                }
            case .onTop:
                let rings = trophyCases[player.id]?.rings ?? 0
                lastNewsItems.append(RetirementCaseNewsFactory.onTop(
                    player: player,
                    teamName: teamName == "Free Agent" ? nil : teamName,
                    peakOverall: retirement.peakOverall,
                    rings: rings,
                    resume: resume,
                    season: season,
                    teamID: retirement.teamIDAtRetirement
                ))
                lastInboxMessages.append(InboxEngine.retiresOnTopMessage(
                    playerName: player.fullName,
                    positionRaw: player.position.rawValue,
                    age: player.age,
                    overall: player.overall,
                    rings: rings,
                    resume: resume,
                    dateString: dateString
                ))
            case .standard:
                break
            }

            // Ceremony headline for league-wide stars (cap 4 per offseason).
            if retirement.retirementCase == .standard, retirement.isStar, starHeadlines < 4 {
                starHeadlines += 1
                let production = resume.map { " He leaves with \($0)." } ?? ""
                lastNewsItems.append(NewsItem(
                    headline: "\(player.fullName) retires after \(max(1, player.yearsPro)) seasons",
                    body: "One of the league's greats is calling it a career. \(player.fullName), the \(teamName == "Free Agent" ? "veteran" : teamName) \(player.position.rawValue) whose play peaked at a \(retirement.peakOverall) overall, announced his retirement today at age \(player.age).\(production) Teams around the league honored him with tributes\(retirement.isHallOfFamer ? " — a Hall of Fame induction awaits" : "").",
                    category: .retirement,
                    week: 0,
                    season: season,
                    relatedTeamID: retirement.teamIDAtRetirement,
                    relatedPlayerID: player.id,
                    sentiment: .neutral
                ))
            }

            // The user's own legend gets a personal farewell. Task #84: not when
            // a special case already wrote him one — the shock letter and the
            // walk-off notice ARE the farewell, and two of them in the same
            // inbox reads like a bug.
            if wasUserPlayer, retirement.isStar || player.yearsPro >= 10 {
                if retirement.retirementCase == .standard {
                    let production = resume.map { "\n\nThe career line: \($0), across \(facts.seasons) seasons and \(facts.gamesPlayed) games." } ?? ""
                    lastInboxMessages.append(InboxMessage(
                        sender: .leagueOffice,
                        subject: "\(player.fullName) Announces Retirement",
                        body: "\(player.fullName) (\(player.position.rawValue), age \(player.age)) is hanging up his cleats after \(max(1, player.yearsPro)) pro seasons. He asked that the organization — and you personally — be thanked for the way his final chapter was handled. The locker room will feel his absence.\(production)\(retirement.isHallOfFamer ? "\n\nExpect the call from Canton: he retires as a Hall of Famer." : "")",
                        date: "Offseason - Coaching Changes, Season \(season)",
                        category: .leagueNotice
                    ))
                }
                // The legacy credit is about the CAREER, not the letter — it is
                // owed however the man left, so it stays outside the flavour gate.
                career.legacy.recordAchievement(LegacyTracker.LegacyAchievement(
                    title: "A Legend Retires",
                    description: "\(player.fullName) played his final season on your roster.",
                    points: 5,
                    season: season
                ))
            }

            if retirement.isHallOfFamer {
                inductees.append(HallOfFameEntry(
                    playerName: player.fullName,
                    positionRaw: player.position.rawValue,
                    peakOverall: retirement.peakOverall,
                    finalAge: player.age,
                    seasonsPlayed: max(1, player.yearsPro),
                    inductionSeason: season,
                    retiredFromTeamName: teamName,
                    wasUserTeamPlayer: wasUserPlayer,
                    faceID: player.faceID,
                    careerStatLine: history.isEmpty ? nil : MilestoneTracker.careerLine(history: history),
                    careerGamesPlayed: facts.isEmpty ? nil : facts.gamesPlayed,
                    careerResume: resume
                ))
            }
        }

        // Annual Hall of Fame induction class.
        if !inductees.isEmpty {
            career.hallOfFame = inductees + career.hallOfFame
            // #21: the class reads as a record book, not a name list — each bust
            // is introduced by the number that earned it.
            let names = inductees
                .map { entry in
                    entry.careerResume.map { "\(entry.playerName) (\(entry.positionRaw), \($0))" }
                        ?? "\(entry.playerName) (\(entry.positionRaw))"
                }
                .joined(separator: "; ")
            lastNewsItems.append(NewsItem(
                headline: "Hall of Fame Class of \(season) announced",
                body: "The league has announced this year's Hall of Fame induction class: \(names). The enshrinement ceremony will be held before the season opener.",
                category: .award,
                week: 0,
                season: season,
                sentiment: .positive
            ))
        }

        // Roundup so the wave of departures is visible in the feed.
        lastNewsItems.append(NewsItem(
            headline: "\(retirements.count) player\(retirements.count == 1 ? "" : "s") announce\(retirements.count == 1 ? "s" : "") retirement",
            body: "The annual wave of retirements has reshaped rosters across the league. Teams will look to free agency and the draft to fill the holes left behind.",
            category: .retirement,
            week: 0,
            season: season,
            sentiment: .neutral
        ))
    }

    /// Task #84, case 3: the rare un-retirement.
    ///
    /// Runs immediately after the retirement wave, in the same
    /// `.coachingChanges` phase, and is the only INFLOW in this file that is not
    /// a draft pick or a street signing. It is held to the same rarity
    /// discipline as the outflow cases: a seeded calendar gate that opens in
    /// under half of offseasons, AND a recently-retired star to open it for, AND
    /// a contender with a roster spot and the cap room to use it. Miss any one
    /// and the offseason is quiet, which is the common case.
    ///
    /// The user's club is deliberately NOT a destination. Every other signing
    /// path in this engine that touches the user's 53 asks him first; an AI
    /// pass that parked a legend and a $4M cap hit on his roster without a
    /// prompt would be the one thing about this feature he could not undo.
    private static func processComeback(
        career: Career,
        teams: [Team],
        allPlayers: [Player],
        modelContext: ModelContext
    ) {
        let season = career.currentSeason
        let seed = PlayerRetirementEngine.specialCaseSeed(careerID: career.id, season: season)
        guard PlayerRetirementEngine.comebackGateFires(seed: seed) else { return }

        // `team.wins` is still the season just played here — `startNewSeason`
        // does not reset records until the rosterCuts → regularSeason boundary
        // (see the ordering note on `lastSeasonRecord`).
        let contenders = teams
            .filter {
                $0.id != career.teamID
                    && $0.wins >= PlayerRetirementEngine.comebackContenderWins
            }
            .sorted { $0.wins == $1.wins ? $0.id.uuidString < $1.id.uuidString : $0.wins > $1.wins }
        guard !contenders.isEmpty else { return }

        let rosterCounts = allPlayers.reduce(into: [UUID: Int]()) { counts, player in
            if let teamID = player.teamID, !player.isRetired { counts[teamID, default: 0] += 1 }
        }
        guard let destination = contenders.first(where: {
            (rosterCounts[$0.id] ?? 0) < 53
                && $0.availableCap >= PlayerRetirementEngine.comebackSalary
        }) else { return }

        let historyByPlayer = seasonHistoryByPlayer(
            careerID: activeCareerID,
            modelContext: modelContext
        )
        let candidates = allPlayers.filter { player in
            guard player.retirementSeason > 0 else { return false }
            let peak = max(
                historyByPlayer[player.id]?.map(\.overallAtEndOfSeason).max() ?? 0,
                player.overall
            )
            let endedAs = player.retirementCaseRaw
                .flatMap { PlayerRetirementEngine.RetirementCase(rawValue: $0) } ?? .standard
            return PlayerRetirementEngine.isComebackCandidate(
                player: player,
                seasonsAway: season - player.retirementSeason,
                peakOverall: peak,
                retirementCase: endedAs
            )
        }
        // The best man available, UUID tie-break so the pick never depends on
        // fetch order.
        guard let returning = candidates.max(by: { a, b in
            let pa = max(historyByPlayer[a.id]?.map(\.overallAtEndOfSeason).max() ?? 0, a.overall)
            let pb = max(historyByPlayer[b.id]?.map(\.overallAtEndOfSeason).max() ?? 0, b.overall)
            if pa != pb { return pa < pb }
            return a.id.uuidString < b.id.uuidString
        }) else { return }

        let seasonsAway = season - returning.retirementSeason
        let overallLost = PlayerRetirementEngine.unretire(
            returning,
            seasonsAway: seasonsAway,
            teamID: destination.id
        )
        destination.currentCapUsage += returning.annualSalary

        // The row stops describing a retired man, and the free-agency layer
        // already knows what a returnee wants (`FAMilestone.comeback`: a
        // contender and a meaningful role, on one year).
        returning.retirementSeason = 0
        returning.retirementCaseRaw = nil
        returning.milestoneRaw = FAMilestone.comeback.rawValue

        lastNewsItems.append(RetirementCaseNewsFactory.comeback(
            player: returning,
            teamName: destination.fullName,
            teamWins: destination.wins,
            seasonsAway: seasonsAway,
            overallLost: overallLost,
            season: season,
            teamID: destination.id
        ))

        let userTeam = career.teamID.flatMap { id in teams.first { $0.id == id } }
        lastInboxMessages.append(InboxEngine.comebackMessage(
            playerName: returning.fullName,
            positionRaw: returning.position.rawValue,
            age: returning.age,
            teamName: destination.fullName,
            seasonsAway: seasonsAway,
            isDivisionRival: userTeam?.conference == destination.conference
                && userTeam?.division == destination.division,
            dateString: InboxEngine.dateLabel(
                week: 0, season: season, phase: .coachingChanges
            )
        ))
    }

    /// Phase 2 (plan §5 stage 6): the post-free-agency washout pass.
    ///
    /// Separate from `processPlayerRetirements` because it needs a different
    /// MOMENT, not a different formula — see `PlayerRetirementEngine`
    /// `washoutProbability`. Everybody rolled here is unsigned after the market
    /// closed, so there is no cap bookkeeping and no team farewell; the league
    /// simply stops carrying a body it has no room for. One quiet roundup line
    /// keeps the churn visible without competing with the retirement wave's
    /// ceremony headlines.
    private static func processWashouts(
        career: Career,
        allPlayers: [Player],
        modelContext: ModelContext
    ) {
        let rostered = allPlayers.filter { $0.teamID != nil && !$0.isRetired }
        guard !rostered.isEmpty else { return }

        // #21: grouped by player, not reduced to a peak — a bust that turns out
        // to be a Hall of Famer gets the same snapshotted career line as a legend
        // who retired on his own terms.
        let historyByPlayer = seasonHistoryByPlayer(
            careerID: activeCareerID,
            modelContext: modelContext
        )
        var peakByID: [UUID: Int] = [:]
        for (playerID, rows) in historyByPlayer {
            peakByID[playerID] = rows.map(\.overallAtEndOfSeason).max() ?? 0
        }

        let washouts = PlayerRetirementEngine.evaluateWashouts(
            allPlayers: allPlayers,
            rosteredPlayers: rostered,
            peakOverallByPlayerID: peakByID
        )
        guard !washouts.isEmpty else { return }

        var inductees: [HallOfFameEntry] = []
        for washout in washouts {
            let player = washout.player
            ChurnDiag.record(ChurnDiag.washout, player)
            PlayerRetirementEngine.retire(washout, teamsByID: [:])

            // A genuinely great career that ended on the scrap heap still gets
            // its bust — the induction rule is about the career, not the exit.
            if washout.isHallOfFamer {
                let history = historyByPlayer[player.id] ?? []
                let facts = MilestoneTracker.careerFacts(history: history)
                inductees.append(HallOfFameEntry(
                    playerName: player.fullName,
                    positionRaw: player.position.rawValue,
                    peakOverall: washout.peakOverall,
                    finalAge: player.age,
                    seasonsPlayed: max(1, player.yearsPro),
                    inductionSeason: career.currentSeason,
                    retiredFromTeamName: "Free Agent",
                    wasUserTeamPlayer: false,
                    faceID: player.faceID,
                    careerStatLine: history.isEmpty ? nil : MilestoneTracker.careerLine(history: history),
                    careerGamesPlayed: facts.isEmpty ? nil : facts.gamesPlayed,
                    careerResume: facts.isEmpty
                        ? nil
                        : MilestoneTracker.hallOfFameSummary(position: player.position, facts: facts)
                ))
            }
        }
        if !inductees.isEmpty {
            career.hallOfFame = inductees + career.hallOfFame
        }

        lastNewsItems.append(NewsItem(
            headline: "\(washouts.count) unsigned veterans call it a career",
            body: "With the market closed, \(washouts.count) free agents who never found a landing spot have stopped waiting for the phone to ring. Camp bodies and rotational depth make up the bulk of the group — the annual quiet half of league turnover.",
            category: .retirement,
            week: 0,
            season: career.currentSeason,
            sentiment: .neutral
        ))
    }

    // MARK: - Private: League Health (R32)

    /// Deletes stale rows a finished season leaves behind:
    /// - ALL `CollegeProspect` rows (the draft is over; next season's class
    ///   regenerates fresh — and the restart-restore path in ScoutingHubView
    ///   reads every persisted prospect, so stale rows would pollute it),
    /// - the user's own per-prospect scouting data in `CareerScopedDefaults`,
    ///   which is keyed by those same (now dead) uuids,
    /// - `Game` rows older than the just-finished season (~272/season).
    private static func purgeStaleSeasonData(career: Career, modelContext: ModelContext) {
        // Scoped hard: unscoped, these two sweeps deleted the OTHER save's
        // prospects and game history — data loss, not a display bug.
        let cid = career.id
        let prospects = (try? modelContext.fetch(FetchDescriptor<CollegeProspect>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        for prospect in prospects {
            modelContext.delete(prospect)
        }

        // Agent hygiene: the rows above are gone, so every watchlist entry,
        // scouting note, own assessment, personal grade, star and original board
        // slot the user wrote about them now points at nothing. Nothing pruned
        // those stores — only `BigBoardView.syncBoardOrder` pruned the board
        // ORDER, and only while that screen was open — so each concluded draft
        // cycle left up to ~350 dead uuids per store behind, forever. Pruned
        // here, in the one place the class is actually wiped, and expressed as
        // "keep what survives" so it stays correct if this sweep ever becomes
        // partial. Career-scoped: the other save's board is untouched.
        CareerScopedDefaults.pruneProspectUserData(keeping: [], careerID: cid)

        let cutoff = career.currentSeason - 1   // keep last season + the new one
        let oldGamesDescriptor = FetchDescriptor<Game>(
            predicate: #Predicate<Game> { $0.careerID == cid && $0.seasonYear < cutoff }
        )
        let oldGames = (try? modelContext.fetch(oldGamesDescriptor)) ?? []
        for game in oldGames {
            modelContext.delete(game)
        }
    }

    /// Roster floor for AI teams at season start: retirements + expiring
    /// contracts can shrink an AI roster below playable size over several
    /// seasons. Teams below 46 players sign veteran-minimum free agents at
    /// their top need positions; when the pool runs dry they sign generated
    /// street free agents so every team always fields a full lineup.
    private static func refillAIRosters(
        career: Career,
        teams: [Team],
        modelContext: ModelContext
    ) {
        // A full roster, not a skeleton one. `trimAIRosters` cuts to 53 while
        // this floor used to be 46, so every AI club settled at 46 and simply
        // never carried its bottom seven — the exact players a real roster is
        // padded with. Measured over `MultiSeasonSmokeTest` that left 224
        // league-wide spots empty, a free-agent pool of 800+ that nothing ever
        // drained, and a league average computed over only the good players
        // (plan §5 stage 6).
        let minimumRosterSize = 53
        let allPlayers = fetchAllPlayers(modelContext: modelContext)
        // Sorted by the SAME key cutdown day uses (`RosterValue.keepScore`), not
        // by raw `overall`. The two halves of roster management have to agree:
        // a club that just cut a 31-year-old journeyman on keepScore and then
        // re-signs him off the top of an `overall` sort has done nothing, and
        // league-wide that asymmetry is a one-way ratchet — every offseason the
        // oldest, highest-rated bodies get re-signed and the draft class that
        // replaced them goes back in the pool. Measured over
        // `MultiSeasonSmokeTest` (5 seasons) the yp0-3 share fell 52.5 % → 36.1 %
        // and the 33+ share rose 2.5 % → 8.8 %, against
        // `DEVELOPMENT_NFL_REFERENCE.md` §8's 45-55 % and ≤ 2 %.
        var freeAgentPool = allPlayers
            .filter { $0.teamID == nil && !$0.isRetired && !$0.isInjured }
            .sorted { RosterValue.keepScore($0) > RosterValue.keepScore($1) }

        for team in teams where team.id != career.teamID {
            var roster = allPlayers.filter { $0.teamID == team.id }
            guard roster.count < minimumRosterSize else { continue }

            while roster.count < minimumRosterSize {
                let needs = DraftEngine.topTeamNeeds(roster: roster, limit: 3)

                let signing: Player
                if let index = freeAgentPool.firstIndex(where: { needs.contains($0.position) }) {
                    signing = freeAgentPool.remove(at: index)
                    ChurnDiag.record(ChurnDiag.refill, signing)
                } else if !freeAgentPool.isEmpty {
                    signing = freeAgentPool.removeFirst()
                    ChurnDiag.record(ChurnDiag.refill, signing)
                } else {
                    // Pool dry — a street free agent reports for a tryout.
                    let position = needs.first ?? .WR
                    let generated = LeagueGenerator.generatePlayer(
                        position: position,
                        teamID: team.id,
                        depthIndex: 2
                    )
                    generated.careerID = activeCareerID
                    modelContext.insert(generated)
                    signing = generated
                    ChurnDiag.record(ChurnDiag.street, signing)
                }

                signing.teamID = team.id
                signing.contractYearsRemaining = Int.random(in: 1...2)
                signing.annualSalary = max(750, min(signing.annualSalary, 1_500))
                team.currentCapUsage += signing.annualSalary
                roster.append(signing)
            }
        }
    }

    /// R32: the AI side of final cutdown day. Every AI roster above the
    /// 53-man ceiling releases its lowest-rated players into the free-agent
    /// pool.
    ///
    /// **One release door** (#102 F8). This loop used to hand-roll the whole
    /// transaction — credit the full salary back, blank the row, clear the three
    /// restructure fields — which made it a SECOND definition of what cutting a
    /// man costs, and a cheaper one than the user's. `CapManagementEngine.applyRelease`
    /// books the signing-bonus acceleration (`tradeCapSplit`'s `deadCap`,
    /// including `Player.restructureDeadMoney`) against the club that paid it;
    /// this loop wiped that receipt without ever charging for it, so an AI front
    /// office could convert base salary into bonus in March and cut the man in
    /// August for free while the user's identical move cost him dead money. A
    /// lever that is free for 31 clubs and priced for one is not a lever, it is
    /// a handicap.
    ///
    /// Everything else `applyRelease` does — the §5.1 `cutByTeamID` / `cutAt`
    /// stamp the practice-squad refill and the Revenge Tour storyline read, the
    /// holdout and training-assignment clear — is exactly what this loop wrote
    /// by hand, so routing through it is field-for-field identical apart from
    /// the charge. `modelContext` is nil by the function's own documented
    /// contract for this path (AI cutdown), and `leagueYearRemaining` is the
    /// league's, so a cutdown-day release relieves the whole base the way an
    /// offseason release should.
    private static func trimAIRosters(
        career: Career,
        teams: [Team],
        allPlayers: [Player]
    ) {
        let rosterCeiling = 53
        let capMode = career.capMode
        let leagueYearRemaining = CapManagementEngine.leagueYearRemaining(
            phase: career.currentPhase,
            week: career.currentWeek
        )
        for team in teams where team.id != career.teamID {
            let roster = allPlayers
                .filter { $0.teamID == team.id && !$0.isRetired }
                .sorted { RosterValue.keepScore($0) > RosterValue.keepScore($1) }
            guard roster.count > rosterCeiling else { continue }

            for player in roster.suffix(roster.count - rosterCeiling) {
                ChurnDiag.record(ChurnDiag.cut, player)
                CapManagementEngine.applyRelease(
                    player: player,
                    team: team,
                    contract: nil,
                    capMode: capMode,
                    leagueYearRemaining: leagueYearRemaining,
                    careerID: career.id
                )
            }
        }
    }

    /// AI teams refill EVERY vacant coaching role each offseason so league
    /// staffing doesn't erode across seasons (poaching/retirements/carousel
    /// moves used to leave permanent holes — only the user could hire, so by
    /// season 5+ AI player development quietly collapsed).
    ///
    /// Task #96 — **the bench is asked first**. This loop used to invent a coach
    /// for every hole it found, which is what made the league's coach population
    /// grow without bound: the three detach passes above it hand ~90 men a season
    /// to unemployment (`checkCoordinatorPoaching` alone rolls against every
    /// non-HC seat on all 32 staffs) and this was the pass that replaced every one
    /// of them with a stranger. Same seats, same fill guarantee — the difference
    /// is that "hired away by another organization" now means somebody actually
    /// hired him. Generation stays as the fallback, so a role whose market is
    /// genuinely empty is still filled on this advance and no team is ever left
    /// short-staffed.
    private static func refillAIStaffVacancies(
        career: Career,
        teams: [Team],
        modelContext: ModelContext
    ) {
        // Re-fetch: the carousel above this call moved coaches around and
        // inserted brand-new ones.
        let coaches = fetchAllCoaches(modelContext: modelContext)
        let bench = CoachMarketEngine.availableBench(coaches)
        // A bench pick is not written to the store until it is assigned below,
        // and `bench` is a snapshot — without this, two clubs would both "hire"
        // the same unemployed man on the same advance.
        var claimed = Set<UUID>()

        // Fetch order is not a hiring order. This loop offers every vacancy the
        // best man on the bench, so iterating `teams` as they came out of the
        // store would give the earliest-indexed clubs first refusal on the whole
        // market EVERY offseason — over a long career that is a systematic staff
        // -quality gradient down the fetch order, with no gameplay meaning behind
        // it. (The carousel above already avoids this by sorting its vacancies on
        // attractiveness; a position-room opening has no such ordering, so the
        // honest answer is a coin toss.)
        for team in teams.shuffled() where team.id != career.teamID {
            let filledRoles = Set(coaches.filter { $0.teamID == team.id }.map(\.role))
            for role in CoachRole.allCases where !filledRoles.contains(role) {
                let hire: Coach
                if let recycled = CoachMarketEngine.hireFromBench(
                    role: role, bench: bench, excluding: claimed
                ) {
                    claimed.insert(recycled.id)
                    // A demoted coordinator or a promoted position coach takes
                    // the title of the seat he is filling — the staff screen
                    // reads roles, not résumés.
                    if recycled.role != role {
                        let previousRole = recycled.role
                        recycled.role = role
                        // ONLY a genuine step up the ladder starts an adjustment
                        // period. `isInAdjustmentPeriod` costs a season of AI
                        // player development (−0.05 HC / −0.03 coordinator in
                        // `CoachingEngine`, plus the scheme-continuity bonus),
                        // and this pass now moves ~90 men a season: stamping
                        // every seat change would have charged that penalty for
                        // lateral moves and demotions too, applying a new
                        // league-wide drag on development that the invented
                        // stranger this man replaces never paid.
                        if role.isPromotion(from: previousRole) {
                            recycled.promotedInSeason = career.currentSeason
                        }
                        // And the seat's pay. Without this a fired head coach
                        // taking a position-room job would carry his $16M salary
                        // into a $650k chair and quietly distort every staff-cost
                        // reading that sums the room.
                        recycled.salary = LeagueGenerator.salaryForCoach(
                            role: role,
                            ovr: CoachingEngine.coachOverallRating(recycled),
                            yearsExperience: recycled.yearsExperience
                        )
                    }
                    // He keeps the portrait he already holds: the reservation was
                    // never released (only a permanent exit does that), so there
                    // is nothing to re-claim.
                    hire = recycled
                    CoachChurnDiag.record(CoachChurnDiag.recycled)
                } else {
                    guard let generated = CoachingEngine.generateCoachCandidates(
                        role: role, count: 1
                    ).first else { continue }
                    // Phase 4 faces: this loop fills ~10 vacancies in one advance
                    // from the SAME registry state, and the preview portraits it
                    // starts from are non-reserving — so without claiming, two of
                    // the coaches inserted here can hash to the same free face and
                    // both keep it. Claim turns each pick into a reservation, so
                    // the next one draws from a shorter list.
                    generated.faceID = FaceLibrary.shared.claimFace(
                        generated.faceID, personID: generated.id,
                        role: .coach, age: generated.age, position: nil,
                        gender: FacePersonGender(tag: generated.gender)
                    )
                    generated.careerID = activeCareerID
                    modelContext.insert(generated)
                    hire = generated
                    CoachChurnDiag.record(CoachChurnDiag.generated)
                }

                hire.teamID = team.id
                hire.hireSeasonYear = career.currentSeason
                hire.contractYearsRemaining = Int.random(in: 2...4)
                hire.unemployedSeasons = 0
            }
        }
    }

    // MARK: - Private: Starting Lineup (#40)

    /// Returns the set of player IDs that make up a team's projected starting
    /// lineup for a week, given its AVAILABLE roster. Mirrors the best-available
    /// role selection used by `MatchupResolver.FieldUnit` (11 offense + 11
    /// defense) plus a kicker and punter, so the "started" tally matches who the
    /// simulator would actually field. Each slot picks the highest-overall
    /// available player at that position who has not already been slotted; a slot
    /// with no eligible player is simply left empty (unlike the 3D `FieldUnit`,
    /// which back-fills with an arbitrary body — we never credit a bogus start).
    ///
    /// This is the league-wide starter signal (AI games are score-only, so no
    /// real box score exists for 31 of 32 teams).
    static func startingLineupIDs(available: [Player]) -> Set<UUID> {
        var picked = Set<UUID>()

        /// Slots the best unused player from the first non-empty preference list.
        func fill(_ preferences: [Position]) {
            var choice: Player?
            for position in preferences {
                for player in available
                where player.position == position && !picked.contains(player.id) {
                    if choice == nil || player.overall > choice!.overall { choice = player }
                }
                if choice != nil { break }   // honor preference order (RB before FB, etc.)
            }
            if let choice { picked.insert(choice.id) }
        }

        // Offense — 11 starters.
        fill([.QB])
        fill([.RB, .FB])          // RB starts; FB only if no RB available
        fill([.LT]); fill([.LG]); fill([.C]); fill([.RG]); fill([.RT])
        fill([.WR]); fill([.WR]); fill([.WR])
        fill([.TE])

        // Defense — 11 starters.
        fill([.DE]); fill([.DT]); fill([.DT]); fill([.DE])
        fill([.OLB]); fill([.MLB, .OLB]); fill([.OLB, .MLB])
        fill([.CB]); fill([.CB])
        fill([.FS, .SS]); fill([.SS, .FS])

        // Specialists.
        fill([.K]); fill([.P])

        return picked
    }

    // MARK: - Private: Season History Recording

    /// Inserts a `PlayerSeasonHistory` snapshot for every player at season's end.
    /// Idempotent per (playerID, season) — re-running on the same season won't
    /// duplicate rows. Captures OVR/age before offseason development changes them.
    ///
    /// `gamesPlayed` is snapshotted from the player's live
    /// `gamesPlayedThisSeason` tally (#33), incremented each regular-season week
    /// the player was available. It is captured here at week 18 before
    /// `startNewSeason` resets the counter.
    ///
    /// ## Where the statline comes from
    ///
    /// Only the user's own games produce a box score — the other 31 teams are
    /// score-only — so the source depends on the player:
    ///
    /// - **User's team**: the numbers the sim really accumulated
    ///   (`Player.seasonStatLine`), zeros included; a scrub who never touched the
    ///   ball genuinely produced nothing and is not handed invented stats. The
    ///   two categories `PlayerGameStats` does not track at all — punting and
    ///   offensive snaps — are modelled even here, because there is no box-score
    ///   source for them anywhere.
    /// - **Everyone else**: modelled by `SeasonStatSynthesizer` from OVR,
    ///   position, GP/GS and age. A player traded away from the user's team
    ///   mid-season keeps the partial real line he earned.
    ///
    /// The postseason columns are left at zero here and topped up over weeks
    /// 19-22 (`recordPostseasonWeek`), because the playoffs have not been played
    /// yet when this runs.
    private static func recordSeasonHistory(
        players: [Player],
        season: Int,
        userTeamID: UUID?,
        modelContext: ModelContext
    ) {
        // Fetch any history rows already written for this season so we don't dupe.
        let cid = activeCareerID
        let existingDescriptor = FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate { $0.careerID == cid && $0.season == season }
        )
        let existing = (try? modelContext.fetch(existingDescriptor)) ?? []
        let existingPlayerIDs = Set(existing.map(\.playerID))
        var rng = SystemRandomNumberGenerator()

        for player in players where !existingPlayerIDs.contains(player.id) && !player.isRetired {
            var statLine = player.seasonStatLine
            // Either he played for the user (so his zeros are real zeros), or he
            // has a partial line from before a mid-season trade off the roster.
            let hasRealLine = (userTeamID != nil && player.teamID == userTeamID)
                || !statLine.isEmpty
            var needsSynthesis = !hasRealLine
            // The modelled line for this player, drawn at most once.
            func modelled() -> SeasonStatLine {
                SeasonStatSynthesizer.line(
                    position: player.position,
                    overall: player.overall,
                    gamesPlayed: player.gamesPlayedThisSeason,
                    gamesStarted: player.gamesStartedThisSeason,
                    age: player.age,
                    using: &rng
                )
            }
            if needsSynthesis {
                statLine = modelled()
            } else {
                switch player.position {
                case .P, .LT, .LG, .C, .RG, .RT:
                    let fill = modelled()
                    statLine.punts = fill.punts
                    statLine.puntAverage = fill.puntAverage
                    statLine.snapsPlayed = fill.snapsPlayed
                    needsSynthesis = true
                default:
                    break
                }
            }
            let entry = PlayerSeasonHistory(
                playerID: player.id,
                season: season,
                overallAtEndOfSeason: player.overall,
                gamesPlayed: player.gamesPlayedThisSeason,   // #33: real per-player appearances
                gamesStarted: player.gamesStartedThisSeason, // #40: real per-player starts
                ageAtEndOfSeason: player.age,
                teamID: player.teamID,
                position: player.position,
                statLine: statLine,
                statsAreSynthesized: needsSynthesis
            )
            entry.careerID = cid
            modelContext.insert(entry)
        }
    }

    /// Folds one game's box score into every listed player's running season line.
    ///
    /// Internal so `LiveGameEngine.persist` can use the same path for a coached
    /// game — the two are the only producers of a real box score in the whole
    /// league, and both must credit the same accumulator.
    static func accumulateSeasonStats(_ stats: [PlayerGameStats], players: [Player]) {
        guard !stats.isEmpty else { return }
        var playersByID: [UUID: Player] = [:]
        playersByID.reserveCapacity(players.count)
        for player in players { playersByID[player.id] = player }
        for line in stats {
            playersByID[line.playerID]?.accumulateSeasonStats(line)
        }
    }

    /// Every player's season rows for this save, keyed by player. One fetch for
    /// the whole league — the milestone and Hall-of-Fame passes each need a
    /// player's WHOLE career, and re-querying per player would be ~1 700 fetches.
    static func seasonHistoryByPlayer(
        careerID: UUID?,
        modelContext: ModelContext
    ) -> [UUID: [PlayerSeasonHistory]] {
        let rows = (try? modelContext.fetch(FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate { $0.careerID == careerID }
        ))) ?? []
        var byPlayer: [UUID: [PlayerSeasonHistory]] = [:]
        for row in rows { byPlayer[row.playerID, default: []].append(row) }
        return byPlayer
    }

    // MARK: - Private: Career Milestone News (#23)

    /// Announces the round career numbers the finished season produced.
    ///
    /// The milestones are read off `PlayerSeasonHistory` — the real persisted
    /// production, for every player in the league, not just the user's — which is
    /// the whole reason the career-stats wave exists. `MilestoneNewsFactory` owns
    /// the copy and the caps; this is the plumbing that hands it the history and
    /// posts the results to the two surfaces `WeekAdvancer` already publishes.
    private static func announceCareerMilestones(
        career: Career,
        season: Int,
        allPlayers: [Player],
        teamsByID: [UUID: Team],
        modelContext: ModelContext
    ) {
        let historyByPlayer = seasonHistoryByPlayer(
            careerID: career.id,
            modelContext: modelContext
        )
        guard !historyByPlayer.isEmpty else { return }

        let announcement = MilestoneNewsFactory.seasonMilestones(
            players: allPlayers,
            historyByPlayer: historyByPlayer,
            teamsByID: teamsByID,
            userTeamID: career.teamID,
            season: season
        )
        lastNewsItems.append(contentsOf: announcement.news)
        lastInboxMessages.append(contentsOf: announcement.inbox)
    }

    // MARK: - Private: Postseason Stat Accumulation (#20)

    /// How many times the play-by-play simulator is allowed to hand back a level
    /// playoff game before the round falls back to the score generator. A tie
    /// survives overtime in well under 1 % of games, so eight attempts is a
    /// safety net, not a loop.
    private static let playoffTieRetryLimit = 8

    /// Plays one round of playoff games and returns the USER's box score, if he
    /// was in it.
    ///
    /// The 31 AI games stay score-only (`simulateGameScore`), the same bargain
    /// the regular season strikes. The user's own game goes through the full
    /// play-by-play simulator instead, because the postseason columns need a real
    /// box score and his game is the only one in the league that can produce one
    /// — the identical reason `advanceRegularSeasonWeek` runs `GameSimulator` for
    /// exactly one game a week.
    ///
    /// A playoff game cannot end level: both paths re-roll until the scores
    /// differ, and the play-by-play path caps its retries so a pathological
    /// matchup degrades to a score-only result rather than spinning.
    @discardableResult
    private static func playPlayoffGames(
        _ games: [Game],
        career: Career,
        teamsByID: [UUID: Team],
        modelContext: ModelContext
    ) -> GameSimulator.GameResult? {
        guard !games.isEmpty else { return nil }
        var userResult: GameSimulator.GameResult?
        // Coaches are needed for the user's game alone — fetched at most once.
        var coachesCache: [Coach]?

        for game in games {
            let userTeamID = career.teamID
            let isUserGame = userTeamID != nil
                && (game.homeTeamID == userTeamID || game.awayTeamID == userTeamID)

            if isUserGame,
               let homeTeam = teamsByID[game.homeTeamID],
               let awayTeam = teamsByID[game.awayTeamID] {
                let coaches = coachesCache ?? fetchAllCoaches(modelContext: modelContext)
                coachesCache = coaches
                // The user's saved plan shades his own side only, exactly as in
                // the regular season. Opponent prep is deliberately NOT applied:
                // it is a weekly regular-season activity with no playoff week to
                // be earned in.
                let plan = career.savedGamePlan
                var decided: GameSimulator.GameResult?
                for _ in 0..<playoffTieRetryLimit {
                    let attempt = GameSimulator.simulate(
                        homeTeam: homeTeam,
                        awayTeam: awayTeam,
                        homeCoaches: coaches.filter { $0.teamID == homeTeam.id },
                        awayCoaches: coaches.filter { $0.teamID == awayTeam.id },
                        homeGamePlan: homeTeam.id == userTeamID ? plan : nil,
                        awayGamePlan: awayTeam.id == userTeamID ? plan : nil,
                        weather: GameWeather.forGame(
                            id: game.id,
                            week: game.week,
                            homeTeamAbbreviation: homeTeam.abbreviation
                        )
                    )
                    if attempt.homeScore != attempt.awayScore {
                        decided = attempt
                        break
                    }
                }
                if let decided {
                    game.homeScore = decided.homeScore
                    game.awayScore = decided.awayScore
                    userResult = decided
                    // The dashboard's post-advance summary sheet reads this. Left
                    // unset it would still hold the user's WEEK 18 game and show
                    // that instead — a stale regular-season box score under a
                    // playoff headline.
                    lastPlayerGameResult = decided
                    continue
                }
                // Fall through: a bracket that cannot name a winner is worse than
                // a round without a box score.
            }

            var score = simulateGameScore()
            // Playoff games cannot end in a tie — keep re-rolling until scores differ.
            while score.home == score.away {
                score = simulateGameScore()
            }
            game.homeScore = score.home
            game.awayScore = score.away

            // Note: no record update — playoff games don't touch W/L/T (R32).
        }

        return userResult
    }

    /// Folds one playoff round into the postseason columns of the season-history
    /// rows week 18 already wrote.
    ///
    /// Two independent halves, for the same reason the regular season splits
    /// them (#33):
    /// - **Appearances** are credited from the BRACKET — every available player
    ///   on a club that played this round gets a playoff game. This is the only
    ///   participation signal that covers all 14 playoff teams.
    /// - **Production** comes from the one real box score in the round, the
    ///   user's. Everyone else's line is modelled once the bracket is finished
    ///   (`finalizePostseasonHistory`), so a club's playoff numbers are drawn
    ///   from its final game count rather than re-rolled every round.
    ///
    /// Creates no rows: a player without a week-18 snapshot (retired mid-season,
    /// or a save that entered the playoffs before this existed) simply has no
    /// postseason to record.
    private static func recordPostseasonWeek(
        week: Int,
        career: Career,
        boxScore: [PlayerGameStats],
        modelContext: ModelContext
    ) {
        let season = career.currentSeason
        let playedGames = fetchAllPlayoffGames(
            week: week,
            seasonYear: season,
            modelContext: modelContext
        ).filter(\.isPlayed)
        guard !playedGames.isEmpty || !boxScore.isEmpty else { return }

        let historyByPlayer = postseasonHistoryByPlayer(season: season, modelContext: modelContext)
        guard !historyByPlayer.isEmpty else { return }

        // --- Appearances ---
        let allPlayers = fetchAllPlayers(modelContext: modelContext)
        let playersByTeam = Dictionary(grouping: allPlayers.filter { $0.teamID != nil },
                                       by: { $0.teamID! })
        for game in playedGames {
            for teamID in [game.homeTeamID, game.awayTeamID] {
                let available = (playersByTeam[teamID] ?? [])
                    .filter { !$0.isInjured && !$0.isHoldingOut && !$0.isRetired }
                for player in available {
                    historyByPlayer[player.id]?.postGamesPlayed += 1
                }
            }
        }

        // --- Production (user's game only) ---
        for line in boxScore {
            historyByPlayer[line.playerID]?.addPostseasonGame(line)
        }
    }

    /// Closes the postseason ledger for the season that just finished.
    ///
    /// Runs once the Super Bowl is on the board, which is the first moment every
    /// club's playoff game count is final. Two jobs:
    /// 1. **Model the 13 clubs the sim never box-scored.** Their line is drawn
    ///    from the same `SeasonStatSynthesizer` the regular season uses, at the
    ///    playoff workload — a two-game run produces two games' worth, not a
    ///    season's.
    /// 2. **Fill the categories no box score carries** for the user's own team:
    ///    punting and offensive snaps have no `PlayerGameStats` source anywhere,
    ///    so they are modelled even on a real line (identical to
    ///    `recordSeasonHistory`).
    ///
    /// Idempotent: a row that already carries a postseason line is left alone, so
    /// re-entering the phase cannot double up or re-roll a player's playoffs.
    private static func finalizePostseasonHistory(
        career: Career,
        userTeamID: UUID?,
        modelContext: ModelContext
    ) {
        let season = career.currentSeason
        let historyByPlayer = postseasonHistoryByPlayer(season: season, modelContext: modelContext)
        guard !historyByPlayer.isEmpty else { return }

        var rng = SystemRandomNumberGenerator()
        for row in historyByPlayer.values where row.postGamesPlayed > 0 {
            // Already closed on a previous pass — never re-roll a career.
            guard !row.postStatsAreSynthesized else { continue }
            guard let position = row.position else { continue }
            var line = row.postStatLine
            // Starts are not tracked in the playoffs; a club's postseason lineup
            // is its regular-season lineup, so his start RATE carries over.
            let startRate = row.gamesPlayed > 0
                ? Double(row.gamesStarted) / Double(row.gamesPlayed)
                : 0
            let postStarts = Int((Double(row.postGamesPlayed) * startRate).rounded())
            func modelled() -> SeasonStatLine {
                SeasonStatSynthesizer.line(
                    position: position,
                    overall: row.overallAtEndOfSeason,
                    gamesPlayed: row.postGamesPlayed,
                    gamesStarted: min(row.postGamesPlayed, postStarts),
                    age: row.ageAtEndOfSeason,
                    using: &rng
                )
            }

            // Exactly the rule `recordSeasonHistory` applies to the regular
            // season: either he played for the user (so his zeros are real
            // zeros), or he already carries a real line — which is true of the
            // user's OPPONENTS too, since a box score covers both rosters. Their
            // numbers must not be thrown away and re-rolled.
            let hasRealLine = (userTeamID != nil && row.teamID == userTeamID) || !line.isEmpty
            if !hasRealLine {
                row.postStatLine = modelled()
                row.postStatsAreSynthesized = true
                continue
            }
            // User's own club: real numbers, with the two unsourced categories
            // topped up once.
            switch position {
            case .P, .LT, .LG, .C, .RG, .RT:
                let fill = modelled()
                line.punts = fill.punts
                line.puntAverage = fill.puntAverage
                line.snapsPlayed = fill.snapsPlayed
                row.postStatLine = line
                row.postStatsAreSynthesized = true
            default:
                break
            }
        }
    }

    /// This season's history rows keyed by player. One fetch, one dictionary —
    /// the postseason passes touch every playoff roster and would otherwise
    /// re-scan ~1 700 rows per club.
    static func postseasonHistoryByPlayer(
        season: Int,
        modelContext: ModelContext
    ) -> [UUID: PlayerSeasonHistory] {
        let cid = activeCareerID
        let rows = (try? modelContext.fetch(FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate { $0.careerID == cid && $0.season == season }
        ))) ?? []
        var byPlayer: [UUID: PlayerSeasonHistory] = [:]
        byPlayer.reserveCapacity(rows.count)
        for row in rows { byPlayer[row.playerID] = row }
        return byPlayer
    }

    /// Every playoff game scheduled for one week, played or not — the postseason
    /// twin of `fetchAllRegularSeasonGames`, and needed for the same reason: a
    /// game the user coached live is already played when the week advances.
    private static func fetchAllPlayoffGames(
        week: Int,
        seasonYear: Int,
        modelContext: ModelContext
    ) -> [Game] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { game in
                game.careerID == cid &&
                game.week == week &&
                game.seasonYear == seasonYear &&
                game.isPlayoff == true
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private static func fetchAllGamesForSeason(
        seasonYear: Int,
        modelContext: ModelContext
    ) -> [Game] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<Game>(
            predicate: #Predicate { game in
                game.careerID == cid && game.seasonYear == seasonYear
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Private: Offseason Realization Inputs (plan §2.3-§2.6)

    /// Builds the per-player situational packet the phase-2 offseason pipeline
    /// runs on, for the whole league in one pass.
    ///
    /// `PlayerDevelopmentEngine` is deliberately kept free of SwiftData: every
    /// fetch (`PlayerSeasonHistory`, `Holdout`, playoff `Game` rows) happens
    /// here, once, and the engine receives plain values.
    ///
    /// Called from the `.trainingCamp` phase handler, i.e. BEFORE
    /// `processOffseason` ages anybody — so every field describes the season
    /// that just finished, which is exactly what the §2.3 triggers ask about.
    private static func buildOffseasonInputs(
        career: Career,
        teamsByID: [UUID: Team],
        allPlayers: [Player],
        allCoaches: [Coach],
        modelContext: ModelContext
    ) -> [UUID: PlayerDevelopmentEngine.OffseasonInputs] {
        let season = career.currentSeason

        // --- Season history, newest season first, per player ---
        let cid = career.id
        let historyRows = (try? modelContext.fetch(FetchDescriptor<PlayerSeasonHistory>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        var historyByPlayer: [UUID: [PlayerSeasonHistory]] = [:]
        for row in historyRows {
            historyByPlayer[row.playerID, default: []].append(row)
        }
        for key in historyByPlayer.keys {
            historyByPlayer[key]?.sort { $0.season > $1.season }
        }

        // --- Holdouts that were settled during THIS offseason ---
        // They cost the player camp reps, which is the §2.4 `health = 0.7`
        // gate. A player still holding out at camp is filtered out of
        // development entirely by the caller (R22), so he never reaches this.
        let holdoutRows = (try? modelContext.fetch(FetchDescriptor<Holdout>(
            predicate: #Predicate { $0.careerID == cid }
        ))) ?? []
        let lateResolvedHoldoutIDs = Set(
            holdoutRows
                .filter { $0.seasonYear == season && $0.resolvedAt != nil }
                .map(\.playerID)
        )

        // --- Playoff heartbreak: a conference-round or Super Bowl loss ---
        let heartbreakTeamIDs = playoffHeartbreakTeamIDs(season: season, modelContext: modelContext)

        var coachesByTeam: [UUID: [Coach]] = [:]
        for coach in allCoaches {
            guard let teamID = coach.teamID else { continue }
            coachesByTeam[teamID, default: []].append(coach)
        }

        var inputs: [UUID: PlayerDevelopmentEngine.OffseasonInputs] = [:]
        for player in allPlayers where !player.isRetired {
            var entry = PlayerDevelopmentEngine.OffseasonInputs()
            entry.salaryCap = player.teamID.flatMap { teamsByID[$0]?.salaryCap }
                ?? ContractEngine.openingSalaryCap
            let history = historyByPlayer[player.id] ?? []
            entry.latestOverall = history.first?.overallAtEndOfSeason
            if history.count >= 2 { entry.previousOverall = history[1].overallAtEndOfSeason }
            if history.count >= 3 { entry.overallTwoSeasonsAgo = history[2].overallAtEndOfSeason }

            // Participation. SNAPSHOT-VS-RESET ORDERING (verified): the week-18
            // snapshot writes `PlayerSeasonHistory` from the live counters, and
            // `startNewSeason` — which zeroes them — does not run until the
            // rosterCuts → regularSeason transition, i.e. AFTER this camp. Both
            // sources therefore hold the same finished season here; the
            // snapshot is preferred (it is the row every other consumer reads)
            // with the live counters as the fallback for a player who has no
            // row for this season yet.
            if let latest = history.first, latest.season == season {
                entry.gamesStarted = latest.gamesStarted
                entry.gamesPlayed = latest.gamesPlayed
            } else {
                entry.gamesStarted = player.gamesStartedThisSeason
                entry.gamesPlayed = player.gamesPlayedThisSeason
            }
            if history.count >= 2 {
                entry.previousGamesStarted = history[1].gamesStarted
                entry.previousGamesPlayed = history[1].gamesPlayed
            }

            entry.changedTeam = history.first.map { $0.teamID != player.teamID } ?? false

            // Tenure with the CURRENT club, for the §2.9.4 potential
            // assessment: consecutive completed seasons at the top of his
            // history that were spent here. `Player.loyaltyYears` looks like
            // the right field but nothing in the codebase ever writes it, so
            // reading it would have pinned every assessment at "just acquired"
            // noise forever.
            var tenure = 0
            for row in history {
                guard let teamID = player.teamID, row.teamID == teamID else { break }
                tenure += 1
            }
            entry.yearsOnTeam = tenure
            entry.missedCampFromHoldout = lateResolvedHoldoutIDs.contains(player.id)
            entry.majorInjuryLastSeason = player.injuryHistory.contains {
                $0.season == season && $0.weeksOut >= PlayerDevelopmentEngine.majorInjuryWeeks
            }

            if let teamID = player.teamID {
                entry.teamWins = lastCompletedSeasonWins(for: teamsByID[teamID])
                entry.playoffHeartbreak = heartbreakTeamIDs.contains(teamID)

                let staff = coachesByTeam[teamID] ?? []
                entry.headCoachMotivation = staff.first { $0.role == .headCoach }?.motivation
                entry.schemeFit = offseasonSchemeFit(player: player, staff: staff)
                DevelopmentSourceDiag.recordSchemeFit(entry.schemeFit)
                if let posCoach = staff.first(where: {
                    CoachingEngine.positionRoleMatch(coachRole: $0.role, playerPosition: player.position)
                }) {
                    // "The OL whisperer arrived": a position coach hired this
                    // offseason who can actually develop people is one of the
                    // §2.5 late-bloomer catalysts.
                    entry.newPositionCoach = posCoach.hireSeasonYear == season
                        && posCoach.playerDevelopment >= 65
                }
            }

            inputs[player.id] = entry
        }
        return inputs
    }

    // MARK: - Private: Scheme Change Consequences (plan §2.9.2-3)

    /// Detects this offseason's coordinator/scheme swaps, applies their
    /// consequences, and returns the per-team environment the camp development
    /// pass runs on.
    ///
    /// Plan §1.3 defect #4: `schemeFamiliarity` was a write-only ratchet. A club
    /// could fire its OC and hire a Vertical guru with zero cost to a roster
    /// that had spent four years learning West Coast, and the West Coast entry
    /// stayed at 95 forever. Three consequences, all here:
    ///
    /// 1. **News** — one story per changed unit, so the swap is visible.
    /// 2. **Install year** — `Team.schemeInstallSeason` marks the upcoming
    ///    season; camp and every in-season practice run `learnScheme` at ×1.25
    ///    (`DEVELOPMENT_NFL_REFERENCE.md` §5: year 1 is an install, year 2 is
    ///    the payoff).
    /// 3. **Decay** — schemes the current staff does not run lose 4 points a
    ///    year down to a floor of 35.
    ///
    /// Continuity (§2.9.3) falls out of the same comparison: a coordinator with
    /// `coordinatorContinuitySeasons`+ years in the building whose scheme did
    /// NOT change is the stability reward.
    ///
    /// Runs at the `.trainingCamp` phase, i.e. after the coaching carousel has
    /// settled, so the coordinators read here are the ones who will run the
    /// upcoming season.
    private static func applySchemeChanges(
        career: Career,
        teams: [Team],
        allPlayers: [Player],
        allCoaches: [Coach]
    ) -> (
        environments: [UUID: PlayerDevelopmentEngine.TeamEnvironment],
        news: [NewsItem],
        /// Scheme raw values installed this offseason, per team — the camp
        /// development report needs them to name the playbook the room is
        /// still learning (§2.10).
        installs: [UUID: [String]]
    ) {
        let season = career.currentSeason
        // Camp belongs to the offseason of the season that just finished; the
        // install applies to the one about to start (`startNewSeason` bumps
        // `currentSeason` at the rosterCuts → regularSeason boundary).
        let upcomingSeason = season + 1

        var coachesByTeam: [UUID: [Coach]] = [:]
        for coach in allCoaches {
            guard let teamID = coach.teamID else { continue }
            coachesByTeam[teamID, default: []].append(coach)
        }
        var playersByTeam: [UUID: [Player]] = [:]
        for player in allPlayers where player.teamID != nil && !player.isRetired {
            playersByTeam[player.teamID!, default: []].append(player)
        }

        var environments: [UUID: PlayerDevelopmentEngine.TeamEnvironment] = [:]
        // The user's own installs always make the feed; the rest of the league
        // is capped so a busy carousel year cannot bury every other headline
        // (same shape as the §2.10 cap on offseason motivation stories).
        var userNews: [NewsItem] = []
        var leagueNews: [NewsItem] = []
        var installs: [UUID: [String]] = [:]

        for team in teams {
            let staff = coachesByTeam[team.id] ?? []
            let oc = staff.first { $0.role == .offensiveCoordinator }
            let dc = staff.first { $0.role == .defensiveCoordinator }
            // Same resolution `offseasonSchemeFit` uses, so "what the club
            // installs" is one answer everywhere: the coordinator's system, or
            // the head coach's when that chair is empty.
            let offScheme = installedOffensiveScheme(staff: staff)?.rawValue
            let defScheme = installedDefensiveScheme(staff: staff)?.rawValue

            // A `nil` snapshot means "never recorded" (new league / legacy
            // save): record it, but never charge an install year for it.
            let offChanged = team.lastOffensiveSchemeRaw != nil
                && offScheme != nil
                && team.lastOffensiveSchemeRaw != offScheme
            let defChanged = team.lastDefensiveSchemeRaw != nil
                && defScheme != nil
                && team.lastDefensiveSchemeRaw != defScheme

            if let offScheme { team.lastOffensiveSchemeRaw = offScheme }
            if let defScheme { team.lastDefensiveSchemeRaw = defScheme }

            if offChanged || defChanged {
                team.schemeInstallSeason = upcomingSeason
            }
            let isUserTeam = team.id == career.teamID
            if offChanged, let offScheme {
                let item = schemeInstallNews(
                    team: team, coordinator: oc, schemeName: offScheme,
                    isOffense: true, season: season
                )
                if isUserTeam { userNews.append(item) } else { leagueNews.append(item) }
                installs[team.id, default: []].append(offScheme)
            }
            if defChanged, let defScheme {
                let item = schemeInstallNews(
                    team: team, coordinator: dc, schemeName: defScheme,
                    isOffense: false, season: season
                )
                if isUserTeam { userNews.append(item) } else { leagueNews.append(item) }
                installs[team.id, default: []].append(defScheme)
            }

            var environment = PlayerDevelopmentEngine.TeamEnvironment()
            if team.schemeInstallSeason == upcomingSeason {
                environment.schemeInstallMultiplier =
                    VersatilityDevelopmentEngine.schemeInstallIntensityBonus
            }
            environment.offensiveContinuity = hasContinuity(
                coordinator: oc, changedScheme: offChanged, season: season
            )
            environment.defensiveContinuity = hasContinuity(
                coordinator: dc, changedScheme: defChanged, season: season
            )
            environments[team.id] = environment

            // Age out the systems this staff no longer runs, and give the room an
            // honest starting point in the ones it does. The seed is what stops a
            // carousel year from reading as "nobody here has ever heard of
            // football" — an absent dictionary key answers 0, which used to be
            // the entire roster's scheme fit the morning after a swap (#54).
            let active = Set([offScheme, defScheme].compactMap { $0 })
            for player in playersByTeam[team.id] ?? [] {
                VersatilityDevelopmentEngine.decayUnusedSchemes(
                    player: player,
                    activeSchemes: active
                )
                VersatilityDevelopmentEngine.seedActiveSchemes(
                    player: player,
                    activeSchemes: active
                )
            }
        }

        return (environments, userNews + leagueNews.prefix(4), installs)
    }

    /// A coordinator earns the continuity bonus once he has been in the
    /// building `CoachingEngine.coordinatorContinuitySeasons` seasons AND has
    /// not just changed the playbook. `hireSeasonYear == 0` is the legacy
    /// "unknown hire date" sentinel — it never counts as tenure.
    private static func hasContinuity(
        coordinator: Coach?,
        changedScheme: Bool,
        season: Int
    ) -> Bool {
        guard let coordinator, !changedScheme, !coordinator.isInAdjustmentPeriod else { return false }
        guard coordinator.hireSeasonYear > 0 else { return false }
        let seasonsOnTeam = season - coordinator.hireSeasonYear
        return seasonsOnTeam >= CoachingEngine.coordinatorContinuitySeasons
    }

    /// The install-year story. One per changed unit, filed at camp.
    private static func schemeInstallNews(
        team: Team,
        coordinator: Coach?,
        schemeName: String,
        isOffense: Bool,
        season: Int
    ) -> NewsItem {
        let unit = isOffense ? "offense" : "defense"
        let coachName = coordinator?.fullName ?? "The new coordinator"
        let schemeName = DevelopmentReportBuilder.schemeDisplayName(schemeName)
        return NewsItem(
            headline: "\(team.abbreviation) install a new \(unit): \(schemeName)",
            body: "\(coachName) has torn up the \(team.fullName) \(unit) playbook and started again. Camp is wall-to-wall installs — the room will learn faster this year than any other, but until the new language is second nature the unit is playing a step slow.",
            category: .coachingChange,
            week: 0,
            season: season,
            relatedTeamID: team.id,
            sentiment: .neutral
        )
    }

    // MARK: - Camp Narrative (plan §2.10)

    /// How many motivation stories the rest of the league may contribute to a
    /// camp feed. The user's own room is never subject to the cap.
    private static let leagueMotivationStoryCap = 4

    /// How many late-bloomer stories the rest of the league may contribute.
    private static let leagueLateBloomerStoryCap = 2

    /// Camp-week stories from the realization pass (plan §2.10): the "best
    /// shape of his life" and "showed up heavy" columns, plus the late-bloomer
    /// breakout. Copy is archetype-flavored — a Fiery Competitor's offseason
    /// does not read like a Quiet Professional's.
    ///
    /// Selection: the user's team always makes the feed (his locker room is
    /// the story he is playing), the other 31 clubs are capped so camp week
    /// cannot turn into one long motivation column. Within each bucket the
    /// best players win the slot — a 58-OVR special-teamer's mindset is not
    /// news.
    private static func motivationCampNews(
        outcomes: [PlayerDevelopmentEngine.OffseasonOutcome],
        teamsByID: [UUID: Team],
        career: Career
    ) -> [NewsItem] {
        let season = career.currentSeason
        let userTeamID = career.teamID

        func rank(_ list: [PlayerDevelopmentEngine.OffseasonOutcome])
            -> [PlayerDevelopmentEngine.OffseasonOutcome] {
            list.sorted { $0.overallAfter > $1.overallAfter }
        }

        // --- Late bloomers first: the rarest and most interesting story ---
        let bloomers = outcomes.filter { $0.lateBloomerBreakout }
        let userBloomers = rank(bloomers.filter { $0.teamID == userTeamID && userTeamID != nil })
        let leagueBloomers = rank(bloomers.filter { $0.teamID != userTeamID })
            .prefix(leagueLateBloomerStoryCap)

        var items: [NewsItem] = []
        for outcome in userBloomers.prefix(2) + Array(leagueBloomers) {
            guard let team = outcome.teamID.flatMap({ teamsByID[$0] }) else { continue }
            items.append(lateBloomerNews(outcome: outcome, team: team, season: season))
        }

        // --- Motivation: driven and complacent/discouraged, big names only ---
        let notable = outcomes.filter {
            !$0.lateBloomerBreakout
                && $0.motivation != .focused
                && $0.overallAfter >= 70
        }
        let userNotable = rank(notable.filter { $0.teamID == userTeamID && userTeamID != nil })
        let leagueNotable = rank(notable.filter { $0.teamID != userTeamID })
            .prefix(leagueMotivationStoryCap)

        for outcome in userNotable.prefix(2) + Array(leagueNotable) {
            guard let team = outcome.teamID.flatMap({ teamsByID[$0] }) else { continue }
            items.append(motivationNews(outcome: outcome, team: team, season: season))
        }

        return items
    }

    /// One motivation column. The headline is the state, the body is the
    /// archetype's own voice.
    private static func motivationNews(
        outcome: PlayerDevelopmentEngine.OffseasonOutcome,
        team: Team,
        season: Int
    ) -> NewsItem {
        let name = outcome.playerName
        let position = outcome.position.rawValue
        let headline: String
        let body: String
        let sentiment: NewsSentiment

        switch outcome.motivation {
        case .driven:
            headline = "\(name) reports to camp in the best shape of his career"
            body = "\(team.fullName) \(position) \(name) has spent the offseason answering last season. \(drivenFlavor(for: outcome.archetype)) The staff expect the work to show up on tape."
            sentiment = .positive

        case .complacent:
            headline = "\(name) showed up heavy — \(team.abbreviation) staff not amused"
            body = "\(team.fullName) \(position) \(name) cashed his cheque and eased off. \(complacentFlavor(for: outcome.archetype)) Coaches have him on a short leash through camp."
            sentiment = .negative

        case .discouraged:
            headline = "\(name) is going through the motions in \(team.abbreviation) camp"
            body = "\(team.fullName) \(position) \(name) arrived checked out. \(discouragedFlavor(for: outcome.archetype)) Until something changes, his development has stalled."
            sentiment = .negative

        case .focused:
            headline = "\(name) reports on schedule for \(team.abbreviation) camp"
            body = "\(team.fullName) \(position) \(name) is going about his business — nothing more, nothing less."
            sentiment = .neutral
        }

        return NewsItem(
            headline: headline,
            body: body,
            category: .playerPerformance,
            week: 0,
            season: season,
            relatedTeamID: team.id,
            relatedPlayerID: outcome.playerID,
            sentiment: sentiment
        )
    }

    /// The year 3-5 breakout story (§2.5) — a career backup who finally put it
    /// together after a change of scheme, coach or situation.
    private static func lateBloomerNews(
        outcome: PlayerDevelopmentEngine.OffseasonOutcome,
        team: Team,
        season: Int
    ) -> NewsItem {
        let gain = outcome.overallDelta > 0 ? " (+\(outcome.overallDelta) OVR)" : ""
        return NewsItem(
            headline: "Late bloomer: \(outcome.playerName) has finally arrived",
            body: "\(team.fullName) \(outcome.position.rawValue) \(outcome.playerName) spent \(max(1, outcome.yearsPro)) seasons as a name on the depth chart. Something changed this offseason\(gain) — teammates say the game has slowed down for the \(outcome.age)-year-old, and the staff are suddenly planning around him.",
            category: .playerPerformance,
            week: 0,
            season: season,
            relatedTeamID: team.id,
            relatedPlayerID: outcome.playerID,
            sentiment: .positive
        )
    }

    private static func drivenFlavor(for archetype: PersonalityArchetype) -> String {
        switch archetype {
        case .fieryCompetitor:
            return "He has been the loudest voice in the building since February, and he is not hiding why."
        case .teamLeader:
            return "He organised the whole position group's offseason program and dragged the young players through it."
        case .quietProfessional, .steadyPerformer:
            return "No speeches, no posts — he simply never left the facility."
        case .mentor:
            return "He came back early to get the rookies up to speed, and put himself through the same work."
        case .loneWolf:
            return "He trained alone all offseason and turned up looking like a different athlete."
        case .dramaQueen:
            return "He made sure everyone heard about every rep, but the tape backs the noise up."
        case .feelPlayer:
            return "He says the game feels right again, and it shows in the way he is moving."
        case .classClown:
            return "The jokes are still there — so, for once, is the conditioning."
        }
    }

    private static func complacentFlavor(for archetype: PersonalityArchetype) -> String {
        switch archetype {
        case .fieryCompetitor, .teamLeader:
            return "Teammates are surprised: this is not the man who set the tone last year."
        case .quietProfessional, .steadyPerformer:
            return "Nothing dramatic — just a step slower in everything the staff time."
        case .mentor:
            return "The young players still get his time; the weight room no longer does."
        case .loneWolf:
            return "Nobody saw him all offseason, and it is showing."
        case .dramaQueen:
            return "The offseason content was excellent. The conditioning test was not."
        case .feelPlayer:
            return "He insists he plays his way into shape. The staff have heard it before."
        case .classClown:
            return "He is still the funniest man in the room, and now the heaviest."
        }
    }

    private static func discouragedFlavor(for archetype: PersonalityArchetype) -> String {
        switch archetype {
        case .fieryCompetitor:
            return "The fire that made him is being spent on the sideline, not the field."
        case .teamLeader, .mentor:
            return "The room has noticed the leader has stopped leading."
        case .quietProfessional, .steadyPerformer:
            return "He does the work and says nothing, but the edge is gone."
        case .loneWolf:
            return "He has withdrawn from the building entirely."
        case .dramaQueen:
            return "Every slight is public, and there have been plenty."
        case .feelPlayer:
            return "Confidence is his fuel and the tank is empty."
        case .classClown:
            return "Even the jokes have dried up."
        }
    }

    /// Wins from the season that just finished, for the §2.3 "team collapsed"
    /// trigger.
    ///
    /// ORDERING NOTE: `Team.lastSeasonWins` is written in `startNewSeason`,
    /// which runs at the rosterCuts → regularSeason boundary — i.e. AFTER the
    /// camp that reads this. During an offseason the live `wins`/`losses`
    /// counters still hold the finished season (nothing else resets them),
    /// while `lastSeasonWins` still holds the season BEFORE it. The live
    /// counters are therefore the correct source here, and the snapshot field
    /// is the fallback for the one case the live ones cannot cover: a team with
    /// no games on the board at all.
    private static func lastCompletedSeasonWins(for team: Team?) -> Int? {
        guard let team else { return nil }
        if team.wins + team.losses + team.ties > 0 { return team.wins }
        return team.hasLastSeasonRecord ? team.lastSeasonWins : nil
    }

    /// Teams that lost in the conference round (week 21) or the Super Bowl
    /// (week 22) — the §2.3 "playoff heartbreak" trigger, which reference §4
    /// describes as a team-wide offseason edge.
    ///
    /// `SeasonSummary` records only "made the playoffs" / "won it all", so the
    /// round is read off the actual playoff `Game` rows instead. Applies league
    /// wide rather than user-team-only: the AI clubs have the same bracket.
    private static func playoffHeartbreakTeamIDs(
        season: Int,
        modelContext: ModelContext
    ) -> Set<UUID> {
        let games = fetchAllGamesForSeason(seasonYear: season, modelContext: modelContext)
        var losers: Set<UUID> = []
        for game in games where game.isPlayoff && game.isPlayed && game.week >= 21 {
            guard let winner = game.winnerID else { continue }
            let loser = winner == game.homeTeamID ? game.awayTeamID : game.homeTeamID
            losers.insert(loser)
        }
        return losers
    }

    /// 0.0-1.0 fit between a player and what his building actually runs, for the
    /// §2.6 potential drift.
    ///
    /// Task #54 replaced a three-way pin with one real computation. The old
    /// version returned a hard-coded 0.5 for every rookie, every specialist and
    /// every club without a coordinator — about a fifth of the league — and
    /// `schemeFamiliarity / 100` for everyone else, which is a measure of tenure
    /// rather than of fit. The consequences were both visible on the smoke's
    /// `diag devsource` line: the median sat at EXACTLY 0.50 forever, and the
    /// mean slid 0.52 → 0.39 as the generator's 55-85 seed was replaced by
    /// intake that enters at 15-45 and by carousel years that dropped whole
    /// rosters onto an absent-key 0.
    ///
    /// `CoachingEngine.rosterSchemeFit` is now the single definition, shared
    /// byte-for-byte with `tools/balance-harness`.
    private static func offseasonSchemeFit(player: Player, staff: [Coach]) -> Double {
        CoachingEngine.rosterSchemeFit(
            player: player,
            offensiveScheme: installedOffensiveScheme(staff: staff),
            defensiveScheme: installedDefensiveScheme(staff: staff)
        )
    }

    /// The offensive system the building installs: the coordinator's, or the
    /// head coach's when the OC chair is empty or the OC is a defensive hire.
    /// A staff always runs SOMETHING; falling straight through to `nil` was
    /// another way the old fit landed on a neutral pin.
    private static func installedOffensiveScheme(staff: [Coach]) -> OffensiveScheme? {
        staff.first { $0.role == .offensiveCoordinator }?.offensiveScheme
            ?? staff.first { $0.role == .headCoach }?.offensiveScheme
            ?? staff.first { $0.role == .assistantHeadCoach }?.offensiveScheme
    }

    /// The defensive system the building installs (see `installedOffensiveScheme`).
    private static func installedDefensiveScheme(staff: [Coach]) -> DefensiveScheme? {
        staff.first { $0.role == .defensiveCoordinator }?.defensiveScheme
            ?? staff.first { $0.role == .headCoach }?.defensiveScheme
            ?? staff.first { $0.role == .assistantHeadCoach }?.defensiveScheme
    }

    // MARK: - Private: Owner Demand Generation (#248)

    /// Generates owner demands tied to actual roster needs (via `DraftEngine.topTeamNeeds`).
    /// Each demand is a single string that includes the weak area, a timeline, and the
    /// satisfaction consequence so the player knows exactly what's at stake.
    private static func generateOwnerDemands(owner: Owner, players: [Player]) -> [String] {
        guard !players.isEmpty else { return [] }

        // Build position-group OVR map so we can show "current ~64 OVR" context.
        let groupDefs: [(label: String, positions: [Position])] = [
            ("QB",  [.QB]),
            ("RB",  [.RB, .FB]),
            ("WR",  [.WR]),
            ("TE",  [.TE]),
            ("OL",  [.LT, .LG, .C, .RG, .RT]),
            ("DL",  [.DE, .DT]),
            ("LB",  [.OLB, .MLB]),
            ("DB",  [.CB, .FS, .SS]),
        ]
        var groupOVRByPosition: [Position: (label: String, avgOVR: Int)] = [:]
        for group in groupDefs {
            let groupPlayers = players.filter { group.positions.contains($0.position) }
            let avg = groupPlayers.isEmpty ? 0 : groupPlayers.map(\.overall).reduce(0, +) / groupPlayers.count
            for pos in group.positions {
                groupOVRByPosition[pos] = (group.label, avg)
            }
        }

        // Use DraftEngine's roster-need evaluator for priority order (matches scouting/draft logic).
        let needPositions = DraftEngine.topTeamNeeds(roster: players, limit: 5)

        // Determine demand count based on meddling.
        let demandCount: Int
        if owner.meddling >= 70 {
            demandCount = 3
        } else if owner.meddling >= 40 {
            demandCount = 2
        } else {
            demandCount = 1
        }

        // Penalty per ignored demand (mirrors application logic below).
        let penalty = owner.patience <= 3 ? 15 : 10

        var demands: [String] = []
        var seenLabels = Set<String>()

        for pos in needPositions {
            guard demands.count < demandCount else { break }
            guard let group = groupOVRByPosition[pos] else { continue }
            // Avoid duplicate position-group demands (e.g. multiple OL holes).
            guard !seenLabels.contains(group.label) else { continue }
            seenLabels.insert(group.label)

            let action: String
            let timeline: String

            // Low-meddling owners stay vague; mid/high meddling owners get specific.
            if owner.meddling < 30 {
                let side = group.label == "DL" || group.label == "LB" || group.label == "DB" ? "defense" : "offense"
                action = "Improve the \(side) (current \(group.label) avg \(group.avgOVR) OVR)"
                timeline = owner.prefersWinNow ? "before Week 1" : "this offseason"
            } else if owner.prefersWinNow {
                action = "Sign or trade for a starting-caliber \(group.label) (current avg \(group.avgOVR) OVR)"
                timeline = "before the season opener"
            } else {
                action = "Draft or develop a franchise \(group.label) (current avg \(group.avgOVR) OVR)"
                timeline = "by the end of the draft"
            }

            demands.append("\(action) — \(timeline). Ignoring costs -\(penalty) satisfaction.")
        }

        // Fallback: if we got no need positions (empty roster edge case), keep one vague demand.
        if demands.isEmpty {
            let fallback = owner.prefersWinNow ? "Make a splash signing this offseason" : "Build through the draft this offseason"
            demands.append("\(fallback) — by the season opener. Ignoring costs -\(penalty) satisfaction.")
        }

        return demands
    }

    // MARK: - Private: Score Generation Helpers

    /// Generates a single realistic team score.
    ///
    /// - Parameter homeAdvantage: Flat bonus added to the raw score (pass 0 for away teams).
    /// - Returns: A non-negative integer score.
    private static func randomTeamScore(homeAdvantage: Int) -> Int {
        // Touchdowns: weighted toward 2–4 TDs per game.
        // Distribution: 0 TD (rare), 1–2 (below average), 2–4 (typical), 5+ (blowout)
        let tdBucket = Int.random(in: 1...10)
        let touchdowns: Int
        switch tdBucket {
        case 1:        touchdowns = 0           // shutout / very low scoring
        case 2...3:    touchdowns = 1
        case 4...6:    touchdowns = 2
        case 7...8:    touchdowns = 3
        case 9:        touchdowns = 4
        case 10:       touchdowns = Int.random(in: 5...6)   // blowout
        default:       touchdowns = 2
        }

        // Field goals: 0–4, weighted toward 1–2.
        let fgBucket = Int.random(in: 1...8)
        let fieldGoals: Int
        switch fgBucket {
        case 1:        fieldGoals = 0
        case 2...4:    fieldGoals = 1
        case 5...7:    fieldGoals = 2
        case 8:        fieldGoals = Int.random(in: 3...4)
        default:       fieldGoals = 1
        }

        let raw = (touchdowns * 7) + (fieldGoals * 3) + homeAdvantage
        return max(0, raw)
    }

    // MARK: - Camp Phase 1 Hook-ups
    //
    // The functions below glue pre-built Camp engines into the offseason flow.
    // The training plan, position battles and Hard Knocks storylines run only
    // for the user's team to keep advanceWeek snappy — AI teams continue to use
    // the legacy `PlayerDevelopmentEngine.processOffseason` path.
    //
    // Phase 2 (plan §2.9.6) carves out ONE exception: the workload tick now
    // runs league-wide, because `WorkloadStatus` gained real consequences
    // (injury multiplier + halved training gains) and a status that exists for
    // one club out of 32 is a user-only tax. AI clubs get the cheap
    // `WorkloadEngine.tickWeek` (state, no per-day `WorkloadEvent` rows — see
    // the row-count measurement on that function); the user's team keeps the
    // full audit trail its camp dashboard reads.

    /// Applies a single weekly camp tick: training plan deltas + 7 days of
    /// workload + per-active-battle resolutions + a HardKnocks event burst.
    /// Phase intensity:
    ///   .otas         -> 0.45 (no pads)
    ///   .trainingCamp -> 0.85 (full pads)
    ///   .preseason    -> 0.55 (lighter; preseason snaps drive most signal)
    private static func applyCampWeeklyTick(
        career: Career,
        phase: SeasonPhase,
        modelContext: ModelContext,
        allPlayers: [Player]
    ) {
        let week = career.currentWeek
        let season = career.currentSeason

        // 0. A new camp cycle opens at OTAs: last year's accumulated load is
        //    history (plan §2.9.6 — `cumulativeLoad` had no reset anywhere and
        //    ratcheted across seasons).
        if phase == .otas {
            for player in allPlayers where player.cumulativeLoad != 0 {
                WorkloadEngine.resetCampLoad(player: player)
            }
        }

        // 0b. League-wide workload state (see the section note above). Runs for
        //     every rostered player EXCEPT the user's, whose per-day rows are
        //     written in step 2.
        applyAICampWorkload(career: career, phase: phase, allPlayers: allPlayers)

        guard let teamID = career.teamID else { return }
        let roster = allPlayers.filter { $0.teamID == teamID }
        guard !roster.isEmpty else { return }

        // 1. Apply the user's saved training plan for this week. If none exists,
        //    seed a balanced 34/33/33 plan so deltas still tick forward.
        let plan = fetchOrSeedTrainingPlan(
            teamID: teamID,
            season: season,
            week: week,
            phase: phase,
            modelContext: modelContext
        )
        DevelopmentSourceDiag.measure(DevelopmentSourceDiag.campTrainingPlan, roster) {
            TrainingPlanEngine.applyWeekly(plan: plan, roster: roster, modelContext: modelContext)
        }

        // 2. Tick 7 days of workload per player. Intensity scales with phase.
        //    Recovery rate is derived from the user team's strength coach (or
        //    physio as fallback). A 50-rated coach yields the legacy 0.55
        //    baseline; elite (99) coaches push toward 0.75; weak (1) coaches
        //    drop toward 0.40. See `computeRecoveryRate` for the mapping.
        let intensity = campIntensity(for: phase)
        let teamCoaches = fetchAllCoaches(modelContext: modelContext)
            .filter { $0.teamID == teamID }
        let recoveryRate = computeRecoveryRate(coaches: teamCoaches)
        for player in roster {
            for day in 0..<7 {
                WorkloadEngine.tickDay(
                    player: player,
                    intensity: intensity,
                    recoveryRate: recoveryRate,
                    seasonYear: season,
                    weekNumber: week,
                    dayOfWeek: day,
                    modelContext: modelContext
                )
            }
        }

        // 3. Detect/resolve position battles. Detection is genuinely idempotent
        //    now (task #67): the tracker skips any (career, season, position)
        //    that already has a row, and the season stamp it writes is
        //    `career.currentSeason` — the same key the fetch below uses. Both
        //    used to be false: the tracker stamped the real-world calendar year,
        //    so the "already open?" test matched nothing and a fresh set of
        //    battles was inserted every camp week.
        //
        //    Because it IS idempotent, it runs EVERY camp week rather than only
        //    when the season has no rows yet. The old `isEmpty` gate was the
        //    other half of the bug: a competition that only becomes detectable
        //    in week 2+ — the veteran signed after week 1, the starter who got
        //    hurt — was never detected at all, because week 1 had already put
        //    something in the table. Daily ticks fire 7x to mirror the workload
        //    week.
        //
        //    `career.id` is passed to BOTH calls on purpose: "has detection run?"
        //    and "what did detection write?" must be answered from one identity.
        //    The fetch used to read `WeekAdvancer.activeCareerID`, which `bind`
        //    keeps equal to `career.id` in the normal flow but which would
        //    silently resurrect the duplication bug if it were ever nil or stale
        //    at camp time.
        let detected = PositionBattleTracker.detectBattles(
            roster: roster,
            seasonYear: season,
            careerID: career.id,
            modelContext: modelContext
        )
        let seasonBattles = PositionBattleTracker.fetchSeasonBattles(
            careerID: career.id,
            seasonYear: season,
            modelContext: modelContext
        )
        // Union by id — a just-inserted row may or may not be visible to the
        // fetch before the context saves, and either way it must be ticked once.
        var openByID: [UUID: PositionBattle] = [:]
        for battle in detected + seasonBattles where battle.winnerID == nil {
            // Only tick battles whose competitors belong to the user's roster.
            let competitorSet = Set(battle.competitorIDs)
            guard roster.contains(where: { competitorSet.contains($0.id) }) else { continue }
            openByID[battle.id] = battle
        }
        let battles = Array(openByID.values)
        var rng = SystemRandomNumberGenerator()
        for battle in battles {
            for _ in 0..<7 {
                PositionBattleTracker.tickDay(battle: battle, rng: &rng, modelContext: modelContext)
            }
        }

        // 4. Hard Knocks storyline burst -- 1 burst per camp week for the user.
        let recentInjuries = roster.filter { $0.isInjured }
        let recentCutsDescriptor = FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> { $0.teamID == teamID && $0.seasonYear == season }
        )
        let recentCuts = (try? modelContext.fetch(recentCutsDescriptor)) ?? []
        HardKnocksNarrator.generateCampStorylines(
            battles: battles,
            recentInjuries: recentInjuries,
            recentCuts: recentCuts,
            roster: roster,
            modelContext: modelContext
        )
    }

    /// Camp workload intensity per offseason phase.
    ///   .otas         -> 0.45 (no pads)
    ///   .trainingCamp -> 0.85 (full pads)
    ///   .preseason    -> 0.55 (lighter; preseason snaps drive most signal)
    private static func campIntensity(for phase: SeasonPhase) -> Double {
        switch phase {
        case .otas:         return 0.45
        case .trainingCamp: return 0.85
        case .preseason:    return 0.55
        default:            return 0.5
        }
    }

    /// League-wide camp workload for every team the user does NOT run, at the
    /// same default intensity, using the row-free `WorkloadEngine.tickWeek`.
    ///
    /// AI clubs have no training plan and no saved recovery staff lookup worth
    /// a per-team fetch here, so they use the neutral 0.55 recovery baseline —
    /// the same number `computeRecoveryRate` returns for a team with no
    /// strength coach. The point is that a status EXISTS league-wide so the
    /// §2.9.6 injury multiplier and burnout tax are not a user-only penalty.
    private static func applyAICampWorkload(
        career: Career,
        phase: SeasonPhase,
        allPlayers: [Player]
    ) {
        let intensity = campIntensity(for: phase)
        for player in allPlayers {
            guard let playerTeamID = player.teamID, playerTeamID != career.teamID else { continue }
            guard !player.isRetired, !player.isHoldingOut else { continue }
            WorkloadEngine.tickWeek(player: player, intensity: intensity, recoveryRate: 0.55)
        }
    }

    /// Maps the user team's strength coach (or physio as fallback) onto a
    /// WorkloadEngine recovery rate in 0.40..0.75. The rating used is
    /// `playerDevelopment` because that's the strength coach's primary focus
    /// attribute (`CoachRole.strengthCoach.focusAttributes`).
    /// - A coach rated 50 → 0.575 (close to the legacy 0.55 baseline).
    /// - A coach rated 99 → 0.749 (elite recovery program).
    /// - No qualifying coach → 0.55 (legacy fallback).
    private static func computeRecoveryRate(coaches: [Coach]) -> Double {
        let strength = coaches.first { $0.role == .strengthCoach }
        let physio = coaches.first { $0.role == .physio }
        guard let primary = strength ?? physio else { return 0.55 }
        let rating = max(1, min(99, primary.playerDevelopment))
        // 1..99 → 0.40..0.75 linear.
        return 0.40 + (Double(rating - 1) / 98.0) * 0.35
    }

    /// Fetches a saved TrainingPlan for (team, season, week, phase) or returns
    /// a balanced fallback so the engine always has something to apply.
    private static func fetchOrSeedTrainingPlan(
        teamID: UUID,
        season: Int,
        week: Int,
        phase: SeasonPhase,
        modelContext: ModelContext
    ) -> TrainingPlan {
        let phaseRaw = phase.rawValue
        let descriptor = FetchDescriptor<TrainingPlan>(
            predicate: #Predicate<TrainingPlan> {
                $0.teamID == teamID
                    && $0.seasonYear == season
                    && $0.weekNumber == week
                    && $0.phaseRaw == phaseRaw
            }
        )
        if let saved = (try? modelContext.fetch(descriptor))?.first {
            return saved
        }
        // Ephemeral fallback — does not persist so the player's saved plan stays canonical.
        return TrainingPlan(
            seasonYear: season,
            weekNumber: week,
            phaseRaw: phaseRaw,
            tacticalPct: 34,
            physicalPct: 33,
            technicalPct: 33,
            teamID: teamID
        )
    }

    /// Fetches all unresolved position battles for the given season.
    private static func fetchOpenPositionBattles(
        seasonYear: Int,
        modelContext: ModelContext
    ) -> [PositionBattle] {
        let cid = activeCareerID
        let descriptor = FetchDescriptor<PositionBattle>(
            predicate: #Predicate<PositionBattle> {
                $0.careerID == cid && $0.seasonYear == seasonYear && $0.winnerID == nil
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // NOTE (task #67): there is deliberately no `fetchSeasonPositionBattles`
    // wrapper here. The camp tick calls `PositionBattleTracker.fetchSeasonBattles`
    // with `career.id` directly, so the identity it queries on and the identity
    // `detectBattles` stamps are the same value read from the same place. A
    // wrapper that sourced `activeCareerID` instead gave the two halves of one
    // question two different answers.

    /// End-of-camp grade computation for the user's roster. Uses an estimate
    /// of training pts (10 pts/week × weeks-in-camp) and preseason snaps from
    /// `PlayerSeasonHistory` if available -- TODO replace with real stat
    /// rollup once preseason GameSimulator persists snap counts.
    private static func applyCampGrades(
        career: Career,
        modelContext: ModelContext,
        allPlayers: [Player]
    ) {
        guard let teamID = career.teamID else { return }
        let roster = allPlayers.filter { $0.teamID == teamID }
        // Approximation: 3 weeks OTAs + 4 weeks camp + 2 weeks preseason = 9 weeks.
        // Scale per-player estimated training pts off cumulativeLoad as a proxy
        // for how engaged each player has been in camp activities.
        for player in roster {
            // Load 0..200 → trainingPts 0..30 (matches CampGradeEvaluator's cap).
            let trainingPts = min(30, max(0, player.cumulativeLoad / 6))
            // Snap volume estimate from yearsPro: vets coast (40 snaps), rooks
            // earn it (70 snaps). Real preseason stats override later.
            let estimatedSnaps = player.yearsPro >= 4 ? 35 : 60
            let perfFactor: Double = {
                // Weighted from current OVR — proxy until real preseason perf lands.
                let ovr = Double(player.overall)
                return min(1.0, max(0.2, ovr / 100.0))
            }()
            let grade = CampGradeEvaluator.computeGrade(
                player: player,
                trainingPts: trainingPts,
                preseasonSnaps: estimatedSnaps,
                preseasonAvgPerf: perfFactor
            )
            player.campGrade = grade
        }
    }

    /// Runs the 24h waiver window for every cut made this season for the user's
    /// team. Worst-record teams get higher claim priority.
    private static func processCampWaivers(
        career: Career,
        teams: [Team],
        modelContext: ModelContext
    ) {
        let season = career.currentSeason
        let cid = career.id
        let cutsDescriptor = FetchDescriptor<RosterCut>(
            predicate: #Predicate<RosterCut> {
                $0.careerID == cid && $0.seasonYear == season && $0.claimedByTeamID == nil
            }
        )
        let cuts = (try? modelContext.fetch(cutsDescriptor)) ?? []
        guard !cuts.isEmpty else { return }

        let teamRecords = teams.map { (teamID: $0.id, wins: $0.wins, losses: $0.losses) }
        _ = WaiverWireEngine.processWaivers(
            cuts: cuts,
            teamRecords: teamRecords,
            modelContext: modelContext
        )
    }

    /// Applies the long-term attribute drift penalty when the user has prepped
    /// opponent-heavy 3+ consecutive weeks. Penalty is a flat OVR drop applied
    /// to physical.stamina (proxy for unit-wide drift -- TODO: scope to the
    /// affected unit only when scheme-attribution lands).
    private static func applyOpponentPrepDrift(
        teamID: UUID,
        season: Int,
        week: Int,
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<OpponentPrepWeek>(
            predicate: #Predicate<OpponentPrepWeek> {
                $0.teamID == teamID && $0.seasonYear == season
            }
        )
        let prep = (try? modelContext.fetch(descriptor)) ?? []
        let recent = prep.sorted { $0.weekNumber > $1.weekNumber }
        var streak = 0
        for entry in recent where entry.weekNumber < week {
            if entry.opponentPct >= 70 { streak += 1 } else { break }
        }
        let penalty = OpponentPrepEngine.driftPenalty(consecutiveOpponentWeeks: streak)
        guard penalty < 0 else { return }

        // Apply -1..-3 to stamina across the user's roster as a unit-wide proxy.
        let playerDescriptor = FetchDescriptor<Player>(
            predicate: #Predicate<Player> { $0.teamID == teamID }
        )
        let roster = (try? modelContext.fetch(playerDescriptor)) ?? []
        for player in roster {
            player.physical.stamina = max(40, player.physical.stamina + penalty)
        }
    }
}
