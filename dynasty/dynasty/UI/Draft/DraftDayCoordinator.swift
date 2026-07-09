import Foundation
import SwiftUI
import SwiftData
import Combine

/// Drives the new event-driven Draft Day experience.
///
/// Vaihe 1 surface: AI auto-picks with a clock countdown, user pick interrupts
/// flow, skip-to-my-pick / skip-to-next-event / pause / speed control. Trade
/// offers, reactions, and rich event types arrive in Vaihe 3.
@MainActor
final class DraftDayCoordinator: ObservableObject {

    // MARK: - Mode

    enum Mode: Equatable {
        case loading
        case preDraft
        case playing
        case paused
        case userPick
        case roundTransition(round: Int)
        case complete
    }

    // MARK: - Published state

    @Published private(set) var mode: Mode = .loading
    @Published private(set) var currentPickIndex: Int = 0
    @Published private(set) var clockSeconds: Int = 120
    @Published private(set) var speed: Double = 1.0
    @Published private(set) var picks: [DraftPick] = []
    @Published private(set) var availableProspects: [CollegeProspect] = []
    @Published private(set) var teamsByID: [UUID: Team] = [:]
    @Published private(set) var rosters: [UUID: [Player]] = [:]
    @Published private(set) var recentEvents: [PlannedDraftEvent] = []
    @Published private(set) var lastPickResult: PickResult?
    @Published private(set) var publicBoardRanks: [UUID: Int] = [:]
    @Published private(set) var teamNeedScores: [Position: Double] = [:]
    @Published private(set) var reputation: DraftReputation?
    @Published private(set) var pendingReactions: [ReactionsEngine.Reaction] = []
    @Published private(set) var pendingDrama: [DraftDramaEngine.DramaEvent] = []
    @Published private(set) var pendingRoundRecap: RoundRecapData?
    @Published private(set) var allPickResults: [PickResult] = []
    @Published private(set) var lastRoundShown: Int = 0

    // R24 — pick-swap trades (real DraftPick rows on both sides)
    @Published private(set) var pendingPickOffer: DraftDayTradeEngine.PickSwapOffer?
    @Published private(set) var tradeDownMessage: String?

    // R24 — UDFA stage after the final pick
    @Published private(set) var udfaPool: [CollegeProspect] = []
    @Published private(set) var signedUDFAProspectIDs: [UUID] = []
    @Published private(set) var udfaStageFinished = false
    @Published private(set) var udfaAISummary: String?
    let maxUDFASignings = 5

    /// One trade-down search per pick — prevents re-rolling the dice.
    private var tradeDownSearchedPickNumber: Int?

    /// User picks whose AI trade-up offer was declined — no nagging re-offers.
    private var declinedTradeUpPickNumbers: Set<Int> = []

    // MARK: - Reputation snapshot (used to compute round-recap deltas)

    private struct ReputationSnapshot {
        let ownerTrust: Int
        let fanMood: Int
        let lockerRoomMood: Int
        let narrative: MediaNarrative
    }

    private var roundStartReputationSnapshot: ReputationSnapshot?

    // MARK: - Dependencies

    private let career: Career
    private let modelContext: ModelContext
    private let recorder: DraftStoryRecorder
    private var clockTask: Task<Void, Never>?
    private var sequenceCounter: Int = 0

    // MARK: - Lifecycle

    init(career: Career, modelContext: ModelContext) {
        self.career = career
        self.modelContext = modelContext
        self.recorder = DraftStoryRecorder(modelContext: modelContext)
    }

    deinit {
        clockTask?.cancel()
    }

    // MARK: - Computed

    var currentPick: DraftPick? {
        guard currentPickIndex < picks.count else { return nil }
        return picks[currentPickIndex]
    }

    var draftYear: Int { career.currentSeason }

    var userTeamID: UUID? { career.teamID }

    var isUserOnClock: Bool {
        guard let pick = currentPick, let teamID = userTeamID else { return false }
        return pick.currentTeamID == teamID
    }

    var picksUntilUserPick: Int {
        guard let teamID = userTeamID else { return 0 }
        for offset in 0..<(picks.count - currentPickIndex) {
            if picks[currentPickIndex + offset].currentTeamID == teamID {
                return offset
            }
        }
        return -1
    }

    var userPicksRemaining: Int {
        guard let teamID = userTeamID else { return 0 }
        return picks[currentPickIndex...].filter { $0.currentTeamID == teamID }.count
    }

    var currentRound: Int {
        currentPick?.round ?? 1
    }

    // MARK: - Setup

    func loadData() async {
        let season = career.currentSeason
        let teamFetch = FetchDescriptor<Team>()
        let playerFetch = FetchDescriptor<Player>()
        let pickFetch = FetchDescriptor<DraftPick>(
            predicate: #Predicate { $0.seasonYear == season },
            sortBy: [SortDescriptor(\.pickNumber)]
        )

        let teams = (try? modelContext.fetch(teamFetch)) ?? []
        let allPlayers = (try? modelContext.fetch(playerFetch)) ?? []
        let persistedPicks = (try? modelContext.fetch(pickFetch)) ?? []

        // Picks: prefer in-memory (current cycle) but fall back to SwiftData
        // if the in-memory list is empty (e.g. fresh launch).
        let inMemoryPicks = WeekAdvancer.currentDraftPicks
            .filter { $0.seasonYear == season }
            .sorted { $0.pickNumber < $1.pickNumber }
        let draftPicks = !inMemoryPicks.isEmpty ? inMemoryPicks : persistedPicks

        // Prospects: SwiftData is the source of truth (preserves Scouting/Big Board
        // edits across app restarts). Fall back to in-memory only if SwiftData is
        // empty, and finally generate a fresh class on demand so the draft is
        // never blocked by missing scouting data.
        let inMemoryClass = WeekAdvancer.currentDraftClass
        let prospectFetch = FetchDescriptor<CollegeProspect>()
        let persistedClass = (try? modelContext.fetch(prospectFetch)) ?? []
        let draftClass: [CollegeProspect]
        if !persistedClass.isEmpty {
            draftClass = persistedClass
            WeekAdvancer.currentDraftClass = persistedClass
        } else if !inMemoryClass.isEmpty {
            draftClass = inMemoryClass
            // In-memory but never persisted — flush to SwiftData now.
            WeekAdvancer.persistDraftClass(inMemoryClass, to: modelContext)
        } else {
            let generated = ScoutingEngine.generateDraftClass()
            WeekAdvancer.currentDraftClass = generated
            WeekAdvancer.persistDraftClass(generated, to: modelContext)
            draftClass = generated
        }

        let draftedNames: Set<String> = Set(draftPicks.compactMap { $0.playerName })
        // Build the player-facing pool: declared, not already drafted by name
        // (across this and any earlier sessions persisted in SwiftData), and
        // deduplicated by UUID (SwiftData can carry stale dupes from earlier
        // generation cycles).
        var seenIDs = Set<UUID>()
        let availablePool = draftClass
            .filter { $0.isDeclaringForDraft }
            .filter { !draftedNames.contains("\($0.firstName) \($0.lastName)") }
            .filter { seenIDs.insert($0.id).inserted }

        self.teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        self.picks = draftPicks
        self.availableProspects = availablePool
        self.rosters = Dictionary(grouping: allPlayers, by: { $0.teamID ?? UUID() })

        // Compute public board ranks for the visible pool only — guarantees
        // contiguous 1..N rankings even when SwiftData carries leftover
        // already-drafted prospects from previous sessions.
        self.publicBoardRanks = DraftIntel.publicBoardRanks(for: availablePool)

        // Team needs for the user's roster — refreshes each time the user
        // makes a pick so the picture stays current.
        if let teamID = career.teamID {
            self.teamNeedScores = DraftIntel.teamNeedScores(roster: rosters[teamID] ?? [])
        }

        // Load or create the DraftReputation row for this season.
        let careerID = career.id
        let repFetch = FetchDescriptor<DraftReputation>(
            predicate: #Predicate { $0.seasonYear == season && $0.careerID == careerID }
        )
        if let existing = (try? modelContext.fetch(repFetch))?.first {
            self.reputation = existing
        } else {
            let fresh = DraftReputation(seasonYear: season, careerID: careerID)
            modelContext.insert(fresh)
            try? modelContext.save()
            self.reputation = fresh
        }

        // Skip ahead through picks already completed in a partially-played draft.
        if let firstUnfinished = picks.firstIndex(where: { !$0.isComplete }) {
            currentPickIndex = firstUnfinished
            mode = .preDraft
        } else {
            // No unfinished picks: either no draft data at all, or the draft
            // was already fully played — go straight to the UDFA stage
            // instead of replaying completed picks.
            currentPickIndex = picks.count
            udfaStageFinished = WeekAdvancer.udfaStageCompletedSeasons.contains(season)
            mode = .complete
            prepareUDFAStage()
        }
        clockSeconds = 120
    }

    // MARK: - Control

    func start() {
        guard mode == .preDraft else { return }
        recordEvent(type: .draftStarted)
        if let rep = reputation {
            roundStartReputationSnapshot = ReputationSnapshot(
                ownerTrust: rep.ownerTrust,
                fanMood: rep.fanMood,
                lockerRoomMood: rep.lockerRoomMood,
                narrative: rep.mediaNarrative
            )
        }
        announceCurrentRoundIfNeeded()
        beginCurrentPick()
    }

    func pause() {
        clockTask?.cancel()
        mode = .paused
    }

    func resume() {
        guard mode == .paused else { return }
        beginCurrentPick()
    }

    func setSpeed(_ newSpeed: Double) {
        speed = max(0.25, min(8.0, newSpeed))
    }

    func skipToMyPick() {
        guard userTeamID != nil else { return }
        clockTask?.cancel()
        autoAdvanceUntil { coordinator in
            coordinator.isUserOnClock || coordinator.mode == .complete
        }
    }

    func skipToNextEvent() {
        clockTask?.cancel()
        autoAdvanceUntil { coordinator in
            // Any "interesting" stop: own pick, big drop already recorded, end
            coordinator.isUserOnClock ||
            coordinator.mode == .complete ||
            coordinator.lastPickResult?.isBigDrop == true
        }
    }

    func skipToNextRound() {
        guard let pick = currentPick else { return }
        clockTask?.cancel()
        let targetRound = pick.round + 1
        autoAdvanceUntil { coordinator in
            (coordinator.currentPick?.round ?? 0) >= targetRound ||
            coordinator.isUserOnClock ||
            coordinator.mode == .complete
        }
    }

    // MARK: - User pick

    func selectProspect(_ prospect: CollegeProspect) {
        guard isUserOnClock, let pick = currentPick else { return }
        completePick(pick: pick, prospect: prospect, isUserPick: true)
        advance()
    }

    // MARK: - Trade offers (R24 — pick swaps on real DraftPick rows)

    /// Called by UI when the user accepts the pending pick-swap offer.
    /// Ownership flips on the real picks, so the draft continues in the
    /// correct order with the new owners on the clock.
    func acceptPickOffer() {
        guard let offer = pendingPickOffer, let teamID = userTeamID else { return }
        guard isOfferStillValid(offer) else {
            pendingPickOffer = nil
            return
        }
        for pick in offer.userGives {
            pick.currentTeamID = offer.partnerTeamID
            pick.teamAbbreviation = teamsByID[offer.partnerTeamID]?.abbreviation
        }
        for pick in offer.userGets {
            pick.currentTeamID = teamID
            pick.teamAbbreviation = teamsByID[teamID]?.abbreviation
        }
        recordEvent(
            type: .tradeAccepted,
            teamID: offer.partnerTeamID,
            pickNumber: offer.userGives.first?.pickNumber,
            round: offer.userGives.first?.round
        )
        try? modelContext.save()
        pendingPickOffer = nil
        tradeDownMessage = nil

        // If the pick on the clock just changed hands (trade down), restart
        // the pick flow so the AI partner goes on the clock immediately.
        if let current = currentPick, current.currentTeamID != teamID, mode == .userPick {
            beginCurrentPick()
        }
    }

    /// Called by UI when the user rejects the pending pick-swap offer.
    func declinePickOffer() {
        if let offer = pendingPickOffer {
            if let pickNumber = offer.userGives.first?.pickNumber {
                declinedTradeUpPickNumbers.insert(pickNumber)
            }
            recordEvent(
                type: .tradeDeclined,
                teamID: offer.partnerTeamID,
                pickNumber: offer.userGives.first?.pickNumber,
                round: nil
            )
        }
        pendingPickOffer = nil
    }

    /// User taps "Trade Down" while on the clock: search for a willing AI
    /// partner. One search per pick — if the league passes, that's the answer.
    func requestTradeDown() {
        guard isUserOnClock, let pick = currentPick, let teamID = userTeamID else { return }
        guard pendingPickOffer == nil else { return }
        if tradeDownSearchedPickNumber == pick.pickNumber {
            if tradeDownMessage == nil {
                tradeDownMessage = "You already shopped this pick — no new callers."
            }
            return
        }
        tradeDownSearchedPickNumber = pick.pickNumber

        if let offer = DraftDayTradeEngine.userTradeDownOffer(
            currentPick: pick,
            picks: picks,
            currentPickIndex: currentPickIndex,
            userTeamID: teamID,
            teamsByID: teamsByID,
            rosters: rosters,
            availableProspects: availableProspects,
            publicBoardRanks: publicBoardRanks,
            currentSeason: career.currentSeason
        ) {
            pendingPickOffer = offer
            tradeDownMessage = nil
            recordEvent(
                type: .tradeOffered,
                teamID: offer.partnerTeamID,
                pickNumber: pick.pickNumber,
                round: pick.round
            )
        } else {
            tradeDownMessage = "No teams are willing to move up to #\(pick.pickNumber) right now."
        }
    }

    /// Called from beginCurrentPick: when the user is 1-3 picks from the
    /// clock, an AI team may offer to trade up into the user's pick.
    private func considerAITradeUpOffer() {
        guard !isUserOnClock,
              pendingPickOffer == nil,
              let teamID = userTeamID else { return }
        let until = picksUntilUserPick
        guard until >= 1, until <= 3 else { return }
        // ~20 % gate per pick inside the window so offers stay meaningful.
        guard Int.random(in: 1...100) <= 20 else { return }
        guard let userPick = picks.dropFirst(currentPickIndex).first(where: { $0.currentTeamID == teamID }),
              !declinedTradeUpPickNumbers.contains(userPick.pickNumber) else { return }

        if let offer = DraftDayTradeEngine.aiTradeUpOffer(
            userPick: userPick,
            picks: picks,
            currentPickIndex: currentPickIndex,
            userTeamID: teamID,
            teamsByID: teamsByID,
            rosters: rosters,
            availableProspects: availableProspects,
            publicBoardRanks: publicBoardRanks,
            currentSeason: career.currentSeason
        ) {
            pendingPickOffer = offer
            recordEvent(
                type: .tradeOffered,
                teamID: offer.partnerTeamID,
                pickNumber: userPick.pickNumber,
                round: userPick.round
            )
        }
    }

    /// A pending offer survives only while every pick on both sides is still
    /// owned by the expected team and hasn't been used yet.
    private func isOfferStillValid(_ offer: DraftDayTradeEngine.PickSwapOffer) -> Bool {
        guard let teamID = userTeamID else { return false }
        let currentNumber = currentPick?.pickNumber ?? Int.max
        for pick in offer.userGives {
            guard pick.currentTeamID == teamID, !pick.isComplete,
                  pick.pickNumber >= currentNumber else { return false }
        }
        for pick in offer.userGets {
            guard pick.currentTeamID == offer.partnerTeamID, !pick.isComplete,
                  pick.pickNumber >= currentNumber else { return false }
        }
        return true
    }

    // MARK: - Internal pick flow

    private func beginCurrentPick() {
        guard let pick = currentPick else {
            completeDraft()
            return
        }

        recordEvent(
            type: .onTheClock,
            teamID: pick.currentTeamID,
            pickNumber: pick.pickNumber,
            round: pick.round
        )

        // Expire stale pick-swap offers (assets drafted or ownership moved).
        if let offer = pendingPickOffer, !isOfferStillValid(offer) {
            pendingPickOffer = nil
        }
        tradeDownMessage = nil

        considerAITradeUpOffer()

        if pick.currentTeamID == userTeamID {
            mode = .userPick
            clockSeconds = 120
            startClockLoop(forUser: true)
        } else {
            mode = .playing
            clockSeconds = 60
            startClockLoop(forUser: false)
        }
    }

    private func startClockLoop(forUser: Bool) {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                let nanos = UInt64(1_000_000_000.0 / max(0.1, self?.speed ?? 1.0))
                try? await Task.sleep(nanoseconds: nanos)
                guard let self else { return }
                if Task.isCancelled { return }
                self.tickClock(forUser: forUser)
            }
        }
    }

    private func tickClock(forUser: Bool) {
        clockSeconds = max(0, clockSeconds - 1)
        if clockSeconds == 0 {
            clockTask?.cancel()
            if forUser {
                // Owner override: AI picks for the user using BPA logic
                if let pick = currentPick,
                   let team = teamsByID[pick.currentTeamID] {
                    let roster = rosters[pick.currentTeamID] ?? []
                    let chosen = DraftEngine.aiMakePick(
                        team: team,
                        availableProspects: availableProspects,
                        teamRoster: roster
                    )
                    completePick(pick: pick, prospect: chosen, isUserPick: false, ownerOverride: true)
                    advance()
                }
            } else {
                aiMakePickForCurrent()
                advance()
            }
        }
    }

    private func aiMakePickForCurrent() {
        guard let pick = currentPick,
              let team = teamsByID[pick.currentTeamID],
              !availableProspects.isEmpty else { return }
        let roster = rosters[pick.currentTeamID] ?? []
        let chosen = DraftEngine.aiMakePick(
            team: team,
            availableProspects: availableProspects,
            teamRoster: roster
        )
        completePick(pick: pick, prospect: chosen, isUserPick: false)
    }

    private func completePick(
        pick: DraftPick,
        prospect: CollegeProspect,
        isUserPick: Bool,
        ownerOverride: Bool = false
    ) {
        // Convert prospect → Player
        let player = DraftEngine.convertToPlayer(
            prospect: prospect,
            teamID: pick.currentTeamID,
            pickNumber: pick.pickNumber
        )
        modelContext.insert(player)

        // Update DraftPick
        pick.playerID = player.id
        pick.playerName = "\(prospect.firstName) \(prospect.lastName)"
        pick.playerPosition = prospect.position.rawValue
        pick.playerCollege = prospect.college
        pick.scoutGrade = scoutGradeLabel(for: prospect)
        pick.teamAbbreviation = teamsByID[pick.currentTeamID]?.abbreviation
        pick.isComplete = true

        // Compute and persist Public Pick Grade
        let grade = computePickGrade(pick: pick, prospect: prospect)
        let pickGrade = DraftPickGrade(
            pickID: pick.id,
            draftYear: pick.seasonYear,
            pickNumber: pick.pickNumber,
            teamID: pick.currentTeamID,
            prospectID: prospect.id,
            playerID: player.id,
            publicGrade: grade.grade,
            publicValueDelta: grade.inputs.valueDelta,
            publicNeedScore: grade.inputs.needScore,
            publicSchemeFit: grade.inputs.schemeFit,
            publicOVR: grade.inputs.publicOVR,
            isGem: grade.isGemCandidate
        )
        modelContext.insert(pickGrade)

        // Update local state
        if let idx = availableProspects.firstIndex(where: { $0.id == prospect.id }) {
            availableProspects.remove(at: idx)
        }
        rosters[pick.currentTeamID, default: []].append(player)

        // Refresh team needs for the user after every pick (their or otherwise)
        // since AI picks may slot into shared positional needs and shift trades.
        if let userTeamID = userTeamID {
            self.teamNeedScores = DraftIntel.teamNeedScores(roster: rosters[userTeamID] ?? [])
        }

        // Record events
        recordEvent(
            type: .pickMade,
            teamID: pick.currentTeamID,
            pickNumber: pick.pickNumber,
            round: pick.round,
            prospectID: prospect.id
        )
        if grade.isGemCandidate {
            recordEvent(
                type: .stealAlert,
                teamID: pick.currentTeamID,
                pickNumber: pick.pickNumber,
                round: pick.round,
                prospectID: prospect.id
            )
        }

        let isBigDrop: Bool = {
            guard let projection = prospect.draftProjection, projection > 0 else { return false }
            return pick.pickNumber > projection + 8
        }()

        let result = PickResult(
            pickNumber: pick.pickNumber,
            round: pick.round,
            teamAbbrev: pick.teamAbbreviation ?? "—",
            playerName: pick.playerName ?? "—",
            position: prospect.position,
            grade: grade.grade,
            isGem: grade.isGemCandidate,
            isBigDrop: isBigDrop,
            isUserPick: isUserPick,
            ownerOverride: ownerOverride
        )
        lastPickResult = result
        allPickResults.append(result)

        // Reactions for the user's own picks (mechanical effects only)
        if isUserPick, let rep = reputation {
            let reactions = ReactionsEngine.reactions(to: result, isUserTeam: true)
            ReactionsEngine.apply(reactions, to: rep)
            ReactionsEngine.updateNarrative(rep, recentPicks: allPickResults.filter { $0.isUserPick })
            pendingReactions.append(contentsOf: reactions)
            for r in reactions {
                let type: DraftEventType = {
                    switch r.actor {
                    case .owner:      return .ownerReaction
                    case .media:      return .mediaReaction
                    case .lockerRoom: return .lockerRoomReaction
                    case .fans:       return .fanReaction
                    }
                }()
                recordEvent(type: type, teamID: pick.currentTeamID, pickNumber: pick.pickNumber, round: pick.round)
            }
        }
        if !isUserPick {
            // AI picks only get a single media reaction when the value delta is dramatic.
            // We never apply these to the user's DraftReputation — they exist purely for
            // UI flavour so the news-ticker stays alive between user picks.
            let aiReactions = ReactionsEngine.reactions(to: result, isUserTeam: false)
            let mediaOnly = aiReactions.filter { $0.actor == .media }
            pendingReactions.append(contentsOf: mediaOnly)
        }

        // Drama events trigger banners / overlays in the UI.
        let drama = DraftDramaEngine.dramaEventsFor(
            result: result,
            currentRound: pick.round,
            previousRound: pick.round,
            picksUntilUserPick: picksUntilUserPick,
            isFinalPick: pick.pickNumber == picks.last?.pickNumber
        )
        pendingDrama.append(contentsOf: drama)

        try? modelContext.save()
    }

    private func advance() {
        clockTask?.cancel()
        let previousRound = currentPick?.round ?? 1
        currentPickIndex += 1
        if currentPickIndex >= picks.count {
            completeDraft()
            return
        }
        let nextRound = currentPick?.round ?? 1
        if nextRound != previousRound {
            triggerRoundRecap(forRound: previousRound)
        }
        announceCurrentRoundIfNeeded()
        beginCurrentPick()
    }

    // MARK: - Draft completion + UDFA stage (R24)

    private func completeDraft() {
        clockTask?.cancel()
        pendingPickOffer = nil
        mode = .complete
        recordEvent(type: .draftCompleted)
        prepareUDFAStage()
    }

    /// Builds the undrafted pool from what's actually left on the board,
    /// sorted by the USER'S scouted grade (never the hidden OVR).
    private func prepareUDFAStage() {
        guard udfaPool.isEmpty else { return }
        udfaPool = availableProspects.sorted { a, b in
            let gradeA = a.effectiveOverallGrade?.midGrade.rank ?? 0
            let gradeB = b.effectiveOverallGrade?.midGrade.rank ?? 0
            if gradeA != gradeB { return gradeA > gradeB }
            return (publicBoardRanks[a.id] ?? 999) < (publicBoardRanks[b.id] ?? 999)
        }
    }

    /// Signs one UDFA to the user's team on a cheap 1-2 year deal (max 5).
    func signUDFA(_ prospect: CollegeProspect) {
        guard mode == .complete, !udfaStageFinished,
              let teamID = userTeamID,
              signedUDFAProspectIDs.count < maxUDFASignings,
              !signedUDFAProspectIDs.contains(prospect.id),
              udfaPool.contains(where: { $0.id == prospect.id }) else { return }

        let player = DraftEngine.convertUDFAToPlayer(prospect: prospect, teamID: teamID)
        modelContext.insert(player)
        rosters[teamID, default: []].append(player)
        signedUDFAProspectIDs.append(prospect.id)
        prospect.isDeclaringForDraft = false   // consumed from future UDFA pools
        if let team = teamsByID[teamID] {
            team.currentCapUsage += player.annualSalary
        }
        teamNeedScores = DraftIntel.teamNeedScores(roster: rosters[teamID] ?? [])
        try? modelContext.save()
    }

    /// Closes the UDFA window: AI teams round-robin the best remaining
    /// prospects (~10 each, mirroring the old OTAs bulk signing), everything
    /// processed here is marked so the OTAs fallback can't double-sign.
    func finishUDFASigning() {
        guard mode == .complete, !udfaStageFinished else { return }
        udfaStageFinished = true

        let remaining = udfaPool.filter { !signedUDFAProspectIDs.contains($0.id) }
        let aiTeams = teamsByID.values.filter { $0.id != userTeamID }.shuffled()
        var aiSignedCount = 0

        if !aiTeams.isEmpty {
            let perTeamCap = 10
            var signedPerTeam: [UUID: Int] = [:]
            var teamIndex = 0
            for prospect in remaining {
                // Find the next team that still has room.
                var assigned: Team?
                for _ in 0..<aiTeams.count {
                    let team = aiTeams[teamIndex % aiTeams.count]
                    teamIndex += 1
                    if signedPerTeam[team.id, default: 0] < perTeamCap {
                        assigned = team
                        break
                    }
                }
                guard let team = assigned else { break }   // every team is full
                let player = DraftEngine.convertUDFAToPlayer(prospect: prospect, teamID: team.id)
                modelContext.insert(player)
                rosters[team.id, default: []].append(player)
                team.currentCapUsage += player.annualSalary
                signedPerTeam[team.id, default: 0] += 1
                aiSignedCount += 1
                prospect.isDeclaringForDraft = false
            }
        }

        // Close the window for everyone left unsigned as well.
        for prospect in remaining where prospect.isDeclaringForDraft {
            prospect.isDeclaringForDraft = false
        }
        WeekAdvancer.udfaStageCompletedSeasons.insert(career.currentSeason)
        udfaAISummary = "League closed the UDFA market: \(aiSignedCount) undrafted players signed across \(aiTeams.count) teams."
        try? modelContext.save()
    }

    // MARK: - Reactions / Drama / Recap consumption

    /// UI calls this once it has shown the next pending reaction toast.
    func consumeOldestReaction() {
        guard !pendingReactions.isEmpty else { return }
        pendingReactions.removeFirst()
    }

    /// UI calls this once it has shown the next pending drama overlay.
    func consumeOldestDrama() {
        guard !pendingDrama.isEmpty else { return }
        pendingDrama.removeFirst()
    }

    /// UI calls this once the round recap card has been dismissed.
    func dismissRoundRecap() {
        pendingRoundRecap = nil
    }

    private func triggerRoundRecap(forRound round: Int) {
        guard let teamID = userTeamID, let rep = reputation else { return }
        // Build a synthetic "before" reputation from the snapshot so the
        // recap can compute meaningful round-over-round deltas.
        let beforeRep: DraftReputation? = {
            guard let snap = roundStartReputationSnapshot else { return nil }
            return DraftReputation(
                seasonYear: rep.seasonYear,
                careerID: rep.careerID,
                ownerTrust: snap.ownerTrust,
                fanMood: snap.fanMood,
                lockerRoomMood: snap.lockerRoomMood,
                mediaNarrative: snap.narrative
            )
        }()
        let recap = RoundRecapBuilder.build(
            round: round,
            allPickResults: allPickResults,
            userTeamID: teamID,
            beforeReputation: beforeRep,
            afterReputation: rep
        )
        pendingRoundRecap = recap
        lastRoundShown = round
        // Reset snapshot for next round
        roundStartReputationSnapshot = ReputationSnapshot(
            ownerTrust: rep.ownerTrust,
            fanMood: rep.fanMood,
            lockerRoomMood: rep.lockerRoomMood,
            narrative: rep.mediaNarrative
        )
    }

    private func autoAdvanceUntil(_ predicate: (DraftDayCoordinator) -> Bool) {
        // Process AI picks immediately (no clock). Stop when predicate met or
        // user pick reached.
        var safety = 0
        while !predicate(self) && currentPickIndex < picks.count {
            safety += 1
            if safety > picks.count + 5 { break }
            guard let pick = currentPick else { break }
            if pick.currentTeamID == userTeamID { break }
            // Capture round before pick
            let roundBefore = pick.round
            announceCurrentRoundIfNeeded()
            recordEvent(
                type: .onTheClock,
                teamID: pick.currentTeamID,
                pickNumber: pick.pickNumber,
                round: pick.round
            )
            aiMakePickForCurrent()
            currentPickIndex += 1
            // Check round transition AFTER advancing — keeps round-recap firing
            // even when the user skips through AI picks.
            let roundAfter = currentPick?.round ?? roundBefore
            if roundAfter != roundBefore {
                triggerRoundRecap(forRound: roundBefore)
            }
        }
        if currentPickIndex >= picks.count {
            completeDraft()
            return
        }
        // Resume normal flow at the stop point
        announceCurrentRoundIfNeeded()
        beginCurrentPick()
    }

    private func announceCurrentRoundIfNeeded() {
        guard let pick = currentPick else { return }
        // Check whether the previous completed pick was in a different round.
        let prevRound: Int? = currentPickIndex == 0
            ? nil
            : picks[currentPickIndex - 1].round
        if prevRound != pick.round {
            recordEvent(type: .roundTransition, round: pick.round)
        }
    }

    // MARK: - Pick Grade

    private struct GradeBundle {
        let grade: PickGrade
        let inputs: PickGradeCalculator.Inputs
        let isGemCandidate: Bool
    }

    private func computePickGrade(pick: DraftPick, prospect: CollegeProspect) -> GradeBundle {
        let bbRank = publicBoardRanks[prospect.id] ?? pick.pickNumber
        let valueDelta = pick.pickNumber - bbRank   // positive = drafted later than projected = steal

        let roster = rosters[pick.currentTeamID] ?? []
        let teamNeeds = DraftIntel.teamNeedScores(roster: roster)
        let needScore = teamNeeds[prospect.position] ?? 0.2

        let publicOVR = prospect.trueOverall  // V1: use true overall as visible OVR
        let schemeFit: Double = 0.6  // V1: placeholder; refined further with scheme data

        let inputs = PickGradeCalculator.Inputs(
            valueDelta: valueDelta,
            needScore: needScore,
            publicOVR: publicOVR,
            schemeFit: schemeFit
        )
        let output = PickGradeCalculator.compute(inputs)
        return GradeBundle(
            grade: output.grade,
            inputs: inputs,
            isGemCandidate: output.isGemCandidate
        )
    }

    private func scoutGradeLabel(for prospect: CollegeProspect) -> String {
        switch prospect.trueOverall {
        case 90...:   return "A+"
        case 84..<90: return "A"
        case 78..<84: return "B+"
        case 72..<78: return "B"
        case 66..<72: return "C+"
        case 60..<66: return "C"
        default:      return "D"
        }
    }

    // MARK: - Events

    private func recordEvent(
        type: DraftEventType,
        teamID: UUID? = nil,
        pickNumber: Int? = nil,
        round: Int? = nil,
        prospectID: UUID? = nil
    ) {
        sequenceCounter += 1
        let event = DraftEvent(
            draftYear: career.currentSeason,
            sequence: sequenceCounter,
            type: type,
            teamID: teamID,
            pickNumber: pickNumber,
            round: round,
            prospectID: prospectID
        )
        recorder.record(event)

        let planned = PlannedDraftEvent(
            sequence: sequenceCounter,
            type: type,
            teamID: teamID,
            pickNumber: pickNumber,
            round: round,
            prospectID: prospectID,
            metadata: .none
        )
        recentEvents.append(planned)
        if recentEvents.count > 50 {
            recentEvents.removeFirst(recentEvents.count - 50)
        }
    }
}

// MARK: - Pick Result

struct PickResult: Identifiable {
    let id = UUID()
    let pickNumber: Int
    let round: Int
    let teamAbbrev: String
    let playerName: String
    let position: Position
    let grade: PickGrade
    let isGem: Bool
    let isBigDrop: Bool
    let isUserPick: Bool
    let ownerOverride: Bool
}
