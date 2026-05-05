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

        // Prospects: prefer in-memory (live cycle); fall back to SwiftData; finally
        // generate a fresh class on demand so the draft is never blocked by
        // missing scouting data.
        let inMemoryClass = WeekAdvancer.currentDraftClass
        let prospectFetch = FetchDescriptor<CollegeProspect>()
        let persistedClass = (try? modelContext.fetch(prospectFetch)) ?? []
        let draftClass: [CollegeProspect]
        if !inMemoryClass.isEmpty {
            draftClass = inMemoryClass
        } else if !persistedClass.isEmpty {
            draftClass = persistedClass
        } else {
            let generated = ScoutingEngine.generateDraftClass()
            WeekAdvancer.currentDraftClass = generated
            draftClass = generated
        }

        let draftedNames: Set<String> = Set(draftPicks.compactMap { $0.playerName })
        self.teamsByID = Dictionary(uniqueKeysWithValues: teams.map { ($0.id, $0) })
        self.picks = draftPicks
        self.availableProspects = draftClass.filter { prospect in
            !draftedNames.contains("\(prospect.firstName) \(prospect.lastName)")
        }
        self.rosters = Dictionary(grouping: allPlayers, by: { $0.teamID ?? UUID() })

        // Skip ahead through picks already completed in a partially-played draft.
        if let firstUnfinished = picks.firstIndex(where: { !$0.isComplete }) {
            currentPickIndex = firstUnfinished
        } else {
            currentPickIndex = 0
        }

        mode = picks.isEmpty ? .complete : .preDraft
        clockSeconds = 120
    }

    // MARK: - Control

    func start() {
        guard mode == .preDraft else { return }
        recordEvent(type: .draftStarted)
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

    // MARK: - Internal pick flow

    private func beginCurrentPick() {
        guard let pick = currentPick else {
            mode = .complete
            recordEvent(type: .draftCompleted)
            return
        }

        recordEvent(
            type: .onTheClock,
            teamID: pick.currentTeamID,
            pickNumber: pick.pickNumber,
            round: pick.round
        )

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

        lastPickResult = PickResult(
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

        try? modelContext.save()
    }

    private func advance() {
        clockTask?.cancel()
        currentPickIndex += 1
        if currentPickIndex >= picks.count {
            mode = .complete
            recordEvent(type: .draftCompleted)
            return
        }
        announceCurrentRoundIfNeeded()
        beginCurrentPick()
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
            // immediate AI pick
            announceCurrentRoundIfNeeded()
            recordEvent(
                type: .onTheClock,
                teamID: pick.currentTeamID,
                pickNumber: pick.pickNumber,
                round: pick.round
            )
            aiMakePickForCurrent()
            currentPickIndex += 1
        }
        if currentPickIndex >= picks.count {
            mode = .complete
            recordEvent(type: .draftCompleted)
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
        let bbRank = prospect.draftProjection ?? pick.pickNumber
        let valueDelta = pick.pickNumber - bbRank   // positive = drafted later than projected = steal

        let roster = rosters[pick.currentTeamID] ?? []
        let topNeeds = DraftEngine.topTeamNeeds(roster: roster, limit: 5)
        let needScore: Double = {
            if let idx = topNeeds.firstIndex(of: prospect.position) {
                return max(0.3, 1.0 - Double(idx) * 0.15)
            }
            return 0.2
        }()

        let publicOVR = prospect.trueOverall  // V1: use true overall as visible OVR
        let schemeFit: Double = 0.6  // V1: placeholder; refined in Vaihe 2 with DraftIntel

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
