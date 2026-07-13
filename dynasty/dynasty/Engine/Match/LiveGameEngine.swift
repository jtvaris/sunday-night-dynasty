import Foundation
import Combine
import SwiftData

// MARK: - Halftime Adjustment

/// The coach's one halftime tweak, applied to the PLAYER team's offensive
/// plays for the entire second half. Deliberately small (±5%-class effects) —
/// a nudge, not a cheat code. AI teams never pick one, so nil-argument
/// auto-sim parity with `GameSimulator.simulate` is intact.
enum HalftimeAdjustment: String, CaseIterable, Identifiable {
    case tightenProtection = "Tighten Pass Protection"
    case attackCorners = "Attack Their Corners"
    case commitToRun = "Commit to the Run"

    var id: String { rawValue }

    /// One-line coach-speak sell for the halftime card.
    var blurb: String {
        switch self {
        case .tightenProtection: return "Keep a back in to chip — fewer sacks on dropbacks."
        case .attackCorners:     return "Motion and stacked releases — better completion odds."
        case .commitToRun:       return "Double teams, downhill tracks — extra yards on the ground."
        }
    }

    var symbolName: String {
        switch self {
        case .tightenProtection: return "shield.lefthalf.filled"
        case .attackCorners:     return "arrow.up.right.circle.fill"
        case .commitToRun:       return "figure.run"
        }
    }

    /// The concrete simulator tweak this choice buys.
    var simAdjustments: PlaySimulator.Adjustments {
        switch self {
        case .tightenProtection: return PlaySimulator.Adjustments(sackChanceReduction: 0.05)
        case .attackCorners:     return PlaySimulator.Adjustments(completionBonus: 0.03)
        case .commitToRun:       return PlaySimulator.Adjustments(runYardageBonus: 0.5)
        }
    }
}

// MARK: - Position Groups

/// Coarse position groups for in-game player management: substitutions are
/// only legal within a group, and the management sheet sections by them.
enum LineupGroup: String, CaseIterable, Identifiable {
    case quarterbacks = "QB"
    case backfield = "RB"
    case receivers = "WR"
    case tightEnds = "TE"
    case offensiveLine = "OL"
    case defensiveLine = "DL"
    case linebackers = "LB"
    case secondary = "DB"
    case specialists = "ST"

    var id: String { rawValue }

    init(of position: Position) {
        switch position {
        case .QB:                    self = .quarterbacks
        case .RB, .FB:               self = .backfield
        case .WR:                    self = .receivers
        case .TE:                    self = .tightEnds
        case .LT, .LG, .C, .RG, .RT: self = .offensiveLine
        case .DE, .DT:               self = .defensiveLine
        case .OLB, .MLB:             self = .linebackers
        case .CB, .FS, .SS:          self = .secondary
        case .K, .P:                 self = .specialists
        }
    }

    /// Section header for the management sheet.
    var sectionTitle: String {
        switch self {
        case .quarterbacks:  return "QUARTERBACKS"
        case .backfield:     return "BACKFIELD"
        case .receivers:     return "RECEIVERS"
        case .tightEnds:     return "TIGHT ENDS"
        case .offensiveLine: return "OFFENSIVE LINE"
        case .defensiveLine: return "DEFENSIVE LINE"
        case .linebackers:   return "LINEBACKERS"
        case .secondary:     return "SECONDARY"
        case .specialists:   return "SPECIALISTS"
        }
    }
}

// MARK: - Live Game Engine

/// Play-by-play engine for live, coached games.
///
/// Runs the exact same simulation core as ``GameSimulator/simulate`` —
/// `PlaySimulator` for individual plays plus the shared `DriveSimulator` /
/// `GameSimulator` helpers for clock, down-and-distance, scoring, momentum,
/// fatigue, and stats — but advances one play at a time via ``step`` so the
/// UI can let the user call plays. A fully-AI game (every `step()` called
/// with nil arguments) is statistically identical to `GameSimulator.simulate`,
/// with one deliberate exception: live games roll per-play injuries (the
/// quick sim rolls the same aggregate injury chance once per week in
/// `WeekAdvancer` instead — which skips both live teams so the totals match;
/// see ``rollInjuries(for:)``).
///
/// Thread model: `@MainActor` because it publishes UI state and holds live
/// SwiftData `Player` references for the end-of-game fatigue write-back.
@MainActor
final class LiveGameEngine: ObservableObject {

    // MARK: - Published Game State

    @Published private(set) var quarter: Int = 1
    /// Seconds remaining in the current quarter.
    @Published private(set) var timeRemaining: Int = GameSimulator.quarterDuration
    @Published private(set) var homeScore: Int = 0
    @Published private(set) var awayScore: Int = 0
    @Published private(set) var homeHasPossession: Bool = true
    @Published private(set) var down: Int = 1
    @Published private(set) var distance: Int = 10
    /// Field position as yards from the offense's own end zone (0–100).
    @Published private(set) var yardLine: Int = GameSimulator.touchbackYardLine
    @Published private(set) var driveNumber: Int = 1
    /// Every play of the game, in order.
    @Published private(set) var playLog: [PlayResult] = []
    /// Plays of the drive currently in progress.
    @Published private(set) var currentDrivePlays: [PlayResult] = []
    @Published private(set) var lastPlay: PlayResult?
    /// Player-vs-player battles resolved for the last play (nil for special teams).
    @Published private(set) var lastMatchups: PlayMatchups?
    @Published private(set) var isGameOver: Bool = false
    /// Per-quarter scoring (index 0–3 = Q1–Q4; index 4 = OT when played).
    @Published private(set) var homeQuarterScores: [Int] = [0, 0, 0, 0]
    @Published private(set) var awayQuarterScores: [Int] = [0, 0, 0, 0]

    // MARK: - Kickoffs

    /// Pre-drive kickoff descriptor for the live view: consumed by
    /// `CoachedGameView` to run the kickoff choreography before the first snap
    /// of a new drive. Purely presentational — the drive's start position has
    /// already been decided by the shared kickoff distribution.
    struct KickoffEvent: Equatable {
        /// The side that boots the ball (the team that just scored / opens the half).
        let kickingTeamIsHome: Bool
        /// The receiving team's drive start (yards from its own goal line).
        let startYardLine: Int
        /// True when the draw was a touchback (returner kneels in the end zone).
        let isTouchback: Bool
        /// True when the kick was housed for a return touchdown.
        let isReturnTouchdown: Bool
    }

    /// Set whenever a new drive begins with a kickoff (game start, after
    /// scores, second-half kick, OT kick). The view consumes it via
    /// ``clearPendingKickoff()`` before animating.
    @Published private(set) var pendingKickoff: KickoffEvent?

    func clearPendingKickoff() { pendingKickoff = nil }

    // MARK: - Timeouts

    /// Timeouts remaining per side: three per half, restocked at halftime.
    @Published private(set) var homeTimeouts: Int = 3
    @Published private(set) var awayTimeouts: Int = 3

    /// Set by ``useTimeout(home:)`` and consumed by the next ``step``: the
    /// timeout freezes the game clock, so that play's runoff is zeroed.
    private var timeoutClockStopPending = false

    /// Timeouts left for the side the user coaches (UI convenience).
    var playerTimeoutsRemaining: Int { playerTeamIsHome ? homeTimeouts : awayTimeouts }

    /// Burns one of the given side's timeouts to stop the clock: the next
    /// play consumes no game time. AI teams never call timeouts, so a fully
    /// nil-argument game remains identical to `GameSimulator.simulate`.
    /// - Returns: true when a timeout was actually available and used.
    @discardableResult
    func useTimeout(home: Bool) -> Bool {
        guard !isGameOver, !timeoutClockStopPending else { return false }
        if home {
            guard homeTimeouts > 0 else { return false }
            homeTimeouts -= 1
        } else {
            guard awayTimeouts > 0 else { return false }
            awayTimeouts -= 1
        }
        timeoutClockStopPending = true
        return true
    }

    // MARK: - Halftime (live only)

    /// Raised exactly once, when Q2 expires and the engine crosses into Q3.
    /// The live view pauses on it to show the halftime report; the engine
    /// itself never blocks on the flag, so a fully-AI game (`simToEnd` /
    /// nil-argument steps) plays straight through — parity intact.
    @Published private(set) var halftimePending = false

    /// The coach's chosen second-half tweak (player's team offense only).
    /// Applied by ``step`` to every player-team play from Q3 on.
    @Published private(set) var halftimeAdjustment: HalftimeAdjustment?

    /// Every individual battle line from the first half (capped at 30), for
    /// the halftime report. Purely presentational.
    private(set) var firstHalfMatchupEvents: [PlayMatchups.Event] = []

    private static let firstHalfMatchupEventCap = 30

    /// The most notable first-half battles for the halftime card: star turns
    /// first, scheme busts second, then the most decisive regular wins.
    func topFirstHalfMatchupEvents(limit: Int = 3) -> [PlayMatchups.Event] {
        func rank(_ kind: PlayMatchups.Event.Kind) -> Int {
            switch kind {
            case .star: return 0
            case .bust: return 1
            default:    return 2
            }
        }
        return firstHalfMatchupEvents
            .sorted {
                (rank($0.kind), -$0.magnitude) < (rank($1.kind), -$1.magnitude)
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Closes the halftime report and locks in the coach's second-half tweak
    /// (`nil` = ride with the current plan).
    func resolveHalftime(choosing adjustment: HalftimeAdjustment?) {
        halftimeAdjustment = adjustment
        halftimePending = false
    }

    // MARK: - Matchup Grades (live only)

    /// Individual matchup wins/losses per player, accumulated from
    /// ``lastMatchups`` every play (see ``step``). Purely presentational —
    /// never feeds back into the simulation, so auto-sim parity is intact.
    @Published private(set) var matchupWins: [UUID: Int] = [:]
    @Published private(set) var matchupLosses: [UUID: Int] = [:]

    /// One row of the end-of-game "Top performers" list.
    struct MatchupPerformer: Identifiable {
        let id: UUID
        let name: String
        let isHomeTeam: Bool
        let wins: Int
        let losses: Int
    }

    /// Players with the most individual matchup wins this game (ties broken
    /// by fewer losses). Empty until at least one battle has been resolved.
    /// Names come from the full rosters (not the field units) so a player who
    /// left the game injured still appears with his tally.
    func topPerformers(limit: Int = 3) -> [MatchupPerformer] {
        guard !matchupWins.isEmpty else { return [] }
        var lookup: [UUID: (name: String, isHome: Bool)] = [:]
        for player in homePlayers { lookup[player.id] = (player.shortName, true) }
        for player in awayPlayers { lookup[player.id] = (player.shortName, false) }
        return matchupWins
            .compactMap { id, wins -> MatchupPerformer? in
                guard let info = lookup[id] else { return nil }
                return MatchupPerformer(
                    id: id, name: info.name, isHomeTeam: info.isHome,
                    wins: wins, losses: matchupLosses[id] ?? 0
                )
            }
            .sorted { ($0.wins, $1.losses) > ($1.wins, $0.losses) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Category Matchups & Day Grades (live only)

    /// The skill category a matchup battle was fought in. Derived from the
    /// participant's role slot plus the play type — the exact attribution
    /// `MatchupResolver` already made when it picked the event's offRole /
    /// defRole (no new resolver). Purely presentational.
    enum MatchupCategory: String, CaseIterable, Identifiable {
        case passProtection = "Pass Pro"
        case runBlocking = "Run Block"
        case receiving = "Routes & Catch"
        case ballCarrying = "Ball Carry"
        case passRush = "Pass Rush"
        case runDefense = "Run Defense"
        case coverage = "Coverage"

        var id: String { rawValue }
    }

    /// One player's win/loss count in a single battle category.
    struct CategoryTally: Equatable {
        var wins = 0
        var losses = 0

        mutating func record(win: Bool) {
            if win { wins += 1 } else { losses += 1 }
        }
    }

    /// Per-player, per-category battle record — the categorized companion of
    /// ``matchupWins``/``matchupLosses``, tallied from the same events in the
    /// same place in ``step``. Never feeds back into the simulation.
    @Published private(set) var categoryTallies: [UUID: [MatchupCategory: CategoryTally]] = [:]

    /// The battle category an OFFENSIVE role slot fights in on a play type.
    /// Role contract: 0=QB 1=RB 2–6=OL 7–9=WR 10=TE.
    static func offenseCategory(role: Int, playType: PlayType) -> MatchupCategory {
        switch role {
        case 2...6:  return playType == .run ? .runBlocking : .passProtection
        case 7...10: return .receiving
        default:     return playType == .run ? .ballCarrying : .receiving // QB scramble / RB checkdown
        }
    }

    /// The battle category a DEFENSIVE role slot fights in on a play type.
    /// Role contract: 0–3=DL 4–6=LB 7–8=CB 9–10=S.
    static func defenseCategory(role: Int, playType: PlayType) -> MatchupCategory {
        if playType == .run { return .runDefense }
        return role <= 3 ? .passRush : .coverage
    }

    /// The categories a position is graded on — shown on the Coach's Board
    /// even at 0-0 so the coach knows what to look for.
    static func relevantCategories(for position: Position) -> [MatchupCategory] {
        switch position {
        case .QB:                    return [.ballCarrying]
        case .RB, .FB:               return [.ballCarrying, .receiving]
        case .WR, .TE:               return [.receiving]
        case .LT, .LG, .C, .RG, .RT: return [.passProtection, .runBlocking]
        case .DE, .DT:               return [.passRush, .runDefense]
        case .OLB, .MLB:             return [.runDefense, .coverage, .passRush]
        case .CB, .FS, .SS:          return [.coverage, .runDefense]
        case .K, .P:                 return []
        }
    }

    /// One category row for the Coach's Board panel.
    struct CategoryLine: Identifiable {
        let category: MatchupCategory
        let wins: Int
        let losses: Int
        var id: String { category.rawValue }
    }

    /// The player's battle record split by category: his role's relevant
    /// categories first (always present, 0-0 when unfought), then any other
    /// category he actually has tallies in (e.g. an OL flagged on a bust).
    func categoryLines(for playerID: UUID, position: Position) -> [CategoryLine] {
        let tallies = categoryTallies[playerID] ?? [:]
        let relevant = LiveGameEngine.relevantCategories(for: position)
        var lines = relevant.map { category -> CategoryLine in
            let tally = tallies[category] ?? CategoryTally()
            return CategoryLine(category: category, wins: tally.wins, losses: tally.losses)
        }
        for category in MatchupCategory.allCases where !relevant.contains(category) {
            if let tally = tallies[category] {
                lines.append(CategoryLine(category: category, wins: tally.wins, losses: tally.losses))
            }
        }
        return lines
    }

    // Day-grade extras tallied per play in ``step`` (presentation only):
    // 20+ yard gains by the ball's key man, turnovers charged to him, sacks
    // hung on the QB who took them, and missed reads (a clearly open man
    // went unthrown on a failed/short dropback — see MatchupResolver's
    // qbMissedOpenMan) charged to the QB.
    private var bigPlayCounts: [UUID: Int] = [:]
    private var turnoverCounts: [UUID: Int] = [:]
    private var sackTakenCounts: [UUID: Int] = [:]
    private var missedReadCounts: [UUID: Int] = [:]

    /// Grade snapshots for the Board's trend arrow: `gradeSnapshots` holds
    /// the player-team grades as of the drive BEFORE last, so the trend
    /// reflects roughly the last drive's worth of battles and stats.
    private var gradeSnapshots: [UUID: Int] = [:]
    private var lastDriveGrades: [UUID: Int] = [:]

    /// The player's day grade, 0–100. Purely presentational — the sim never
    /// reads it. Base 60, shifted by role-weighted matchup wins/losses
    /// (trench work weighs heavier, pass pro most of all — OL have no
    /// counting stats) and headline stat events: TDs +6, sacks made +4,
    /// 20+ yard plays +2, INTs thrown / fumbles lost −8, sacks taken −2,
    /// missed reads (open man unthrown on a failed dropback) −1.5.
    /// Stats accumulate per completed drive; battles update per play.
    func playerGameGrade(_ playerID: UUID) -> Int {
        var score = 60.0
        if let tallies = categoryTallies[playerID] {
            for (category, tally) in tallies {
                let winWeight: Double
                let lossWeight: Double
                switch category {
                case .passProtection: winWeight = 3.5; lossWeight = 3.0
                case .runBlocking:    winWeight = 3.25; lossWeight = 2.75
                default:              winWeight = 3.0; lossWeight = 2.5
                }
                score += Double(tally.wins) * winWeight
                score -= Double(tally.losses) * lossWeight
            }
        }
        if let s = statsAccumulator[playerID] {
            score += Double(s.passingTDs + s.rushingTDs + s.receivingTDs) * 6
            score += s.sacks * 4
            score += Double(s.interceptionsCaught) * 6
            score -= Double(s.interceptions) * 8
        }
        score += Double(bigPlayCounts[playerID] ?? 0) * 2
        score -= Double(turnoverCounts[playerID] ?? 0) * 8
        score -= Double(sackTakenCounts[playerID] ?? 0) * 2
        score -= Double(missedReadCounts[playerID] ?? 0) * 1.5
        return max(0, min(100, Int(score.rounded())))
    }

    /// Grade movement since the drive before last: positive = trending up.
    func gradeTrend(_ playerID: UUID) -> Int {
        playerGameGrade(playerID) - (gradeSnapshots[playerID] ?? 60)
    }

    /// Player-team grades right now (drive-end snapshot for ``gradeTrend``).
    private func playerTeamGrades() -> [UUID: Int] {
        let ids = playerTeamIsHome ? homePlayerIDs : awayPlayerIDs
        var grades: [UUID: Int] = [:]
        for id in ids { grades[id] = playerGameGrade(id) }
        return grades
    }

    /// Personality archetype from the live model (Board display only).
    func personalityArchetype(for playerID: UUID) -> PersonalityArchetype? {
        livePlayerByID[playerID]?.personality.archetype
    }

    /// True when the player was knocked out of THIS game.
    func wentDownThisGame(_ playerID: UUID) -> Bool {
        injuredPlayerIDs.contains(playerID)
    }

    /// Roster players of a position group lost to injury during this game —
    /// shown greyed on the Board's bench with an OUT badge.
    func injuredPlayers(forHome: Bool, position group: LineupGroup) -> [SimPlayer] {
        let roster = forHome ? homePlayers : awayPlayers
        return roster.filter {
            LineupGroup(of: $0.position) == group && injuredPlayerIDs.contains($0.id)
        }
    }

    // MARK: - Milestones (live only)

    /// A statistical milestone crossed during this game, e.g. a back clearing
    /// 100 rushing yards. Purely presentational — `CoachedGameView` shows a
    /// gold banner; the simulation never reads it (auto-sim parity intact).
    struct MilestoneEvent: Equatable, Identifiable {
        let id = UUID()
        /// "MILESTONE: M. Dixon — 100 rushing yards"
        let text: String
    }

    /// Milestones crossed when the last completed drive's stats were
    /// accumulated (stats update per drive, so drive granularity is the
    /// finest the engine can truthfully announce).
    @Published private(set) var lastMilestones: [MilestoneEvent] = []

    /// "playerID|kind" keys already announced, so each milestone fires once.
    private var announcedMilestones: Set<String> = []

    /// Yardage lines worth a broadcast banner.
    private static let rushingMilestoneYards = 100
    private static let receivingMilestoneYards = 100
    private static let passingMilestoneYards = 300

    /// Scans the accumulated stats for newly crossed 100-yard rushing /
    /// receiving and 300-yard passing lines and publishes them (once each).
    private func publishMilestones() {
        var events: [MilestoneEvent] = []
        for stats in statsAccumulator.values {
            if stats.rushingYards >= LiveGameEngine.rushingMilestoneYards {
                appendMilestone(stats, kind: "rush",
                                label: "\(LiveGameEngine.rushingMilestoneYards) rushing yards",
                                into: &events)
            }
            if stats.receivingYards >= LiveGameEngine.receivingMilestoneYards {
                appendMilestone(stats, kind: "recv",
                                label: "\(LiveGameEngine.receivingMilestoneYards) receiving yards",
                                into: &events)
            }
            if stats.passingYards >= LiveGameEngine.passingMilestoneYards {
                appendMilestone(stats, kind: "pass",
                                label: "\(LiveGameEngine.passingMilestoneYards) passing yards",
                                into: &events)
            }
        }
        if !events.isEmpty { lastMilestones = events }
    }

    private func appendMilestone(
        _ stats: PlayerGameStats,
        kind: String,
        label: String,
        into events: inout [MilestoneEvent]
    ) {
        let key = "\(stats.playerID.uuidString)|\(kind)"
        guard !announcedMilestones.contains(key) else { return }
        announcedMilestones.insert(key)
        events.append(MilestoneEvent(
            text: "MILESTONE: \(shortName(stats.playerName)) — \(label)"
        ))
    }

    // MARK: - Injuries & Rotation (live only)

    /// A player knocked out of the live game. Published so the view can show
    /// the red injury banner and leave his figure on the turf.
    struct LiveInjuryEvent: Equatable, Identifiable {
        let id = UUID()
        let playerID: UUID
        /// "T. Hill"
        let playerName: String
        /// Position abbreviation, e.g. "WR".
        let position: String
        let isHomeTeam: Bool
        /// 3D field node (home 0–10, away 11–21) if he was one of the 22 on
        /// the field when it happened; nil when the sim used a player who was
        /// not part of the on-field unit.
        let nodeIndex: Int?
        let injuryType: InjuryType
    }

    /// A fatigue substitution on the player's team ("Fresh legs: RB2 in").
    struct RotationEvent: Equatable {
        let inName: String
        let outName: String
    }

    /// Injuries that happened on the play just stepped (usually empty,
    /// occasionally one; carrier and tackler can in theory both go down).
    @Published private(set) var lastPlayInjuries: [LiveInjuryEvent] = []

    /// The most recent fatigue substitution on the player's team.
    @Published private(set) var lastRotation: RotationEvent?

    /// Base injury chance per contact involvement (carrier or tackler).
    /// Calibrated against the quick sim: the weekly roll gives every rostered
    /// player a 0.5% base chance (`MedicalEngine.injuryCheck`), i.e. ~0.26
    /// expected injuries per 53-man team-week before modifiers. A live game
    /// produces ~45 carrier + ~45 tackler contacts per team, so 0.3% per
    /// involvement lands on the same expected total. `WeekAdvancer` skips the
    /// weekly roll for both live teams (see `liveGameInjuryTeamIDs`) so the
    /// live path is never double-counted.
    private static let perPlayInjuryRisk = 0.003

    /// RB1 sits for the next drive once his fatigue crosses this line
    /// (and a meaningfully fresher backup exists).
    private static let rbRotationFatigueThreshold = 75

    /// Players lost to injury during this game (excluded from the sim and
    /// the field units; written back to the live models in ``persist``).
    private var injuredPlayerIDs: Set<UUID> = []
    /// Injuries to persist at game end, with team side for staff lookup.
    private var gameInjuries: [(playerID: UUID, type: InjuryType, isHomeTeam: Bool)] = []
    /// The player-team RB currently resting on the bench (fatigue rotation).
    private var restingRBID: UUID?

    /// Everyone unavailable for the next snap.
    private var sidelinedIDs: Set<UUID> {
        var ids = injuredPlayerIDs.union(manuallyBenchedIDs)
        if let restingRBID { ids.insert(restingRBID) }
        return ids
    }

    // MARK: - In-Game Management (live only)

    /// A coach-ordered substitution waiting for the whistle. Queued by
    /// ``substitute(benchPlayerID:forFieldPlayerID:)`` and realized at the
    /// next dead ball (the end of the next completed play), through the same
    /// field-unit replacement mechanism injuries and fatigue rotation use —
    /// the formation's jersey numbers update automatically on the next lineup.
    struct PendingSubstitution: Equatable, Identifiable {
        let id = UUID()
        let benchPlayerID: UUID
        let fieldPlayerID: UUID
        /// "J. Cook"
        let benchName: String
        let fieldName: String
        /// Which of the player's units the swap targets.
        let isOffenseUnit: Bool
        /// Role slot (choreographer contract) at queue time — informational;
        /// the slot is re-resolved when the swap is applied.
        let role: Int
    }

    /// Substitutions queued by the coach, cleared as they land at the next
    /// dead ball. PLAYER's team only — the AI opponent never substitutes, so
    /// nil-argument auto-sim parity with `GameSimulator.simulate` is intact.
    @Published private(set) var pendingSubstitutions: [PendingSubstitution] = []

    /// Players the coach has pulled to the bench: excluded from the sim and
    /// the field units until subbed back in (or freed by ``releaseManualBenchIfNeeded()``).
    private var manuallyBenchedIDs: Set<UUID> = []
    /// Coach-picked starters per offensive/defensive role slot, re-applied on
    /// every field-unit rebuild so injuries and rotation don't erase them.
    private var manualOffenseOverrides: [Int: UUID] = [:]
    private var manualDefenseOverrides: [Int: UUID] = [:]
    /// Bench players hidden from the play simulation because the coach has
    /// hand-picked the starter in their position group: keeps the sim's
    /// best-at-position picks (QB, RB, pass targets) aligned with the men
    /// actually on the field. Empty unless a manual substitution is active,
    /// so a game without subs is untouched.
    private var overrideShadowedIDs: Set<UUID> = []

    /// The player's own units (UI convenience).
    var playerOffenseUnit: FieldUnit { playerTeamIsHome ? homeOffenseUnit : awayOffenseUnit }
    var playerDefenseUnit: FieldUnit { playerTeamIsHome ? homeDefenseUnit : awayDefenseUnit }

    /// Healthy roster players of a position group who are NOT currently in
    /// either of the team's field units — the substitution candidates,
    /// best first. A player brought on for an injured or rotated starter is
    /// on the field (FieldUnit is the truth), so he is correctly absent here.
    func benchPlayers(forHome: Bool, position group: LineupGroup) -> [SimPlayer] {
        let roster = forHome ? homePlayers : awayPlayers
        let offense = forHome ? homeOffenseUnit : awayOffenseUnit
        let defense = forHome ? homeDefenseUnit : awayDefenseUnit
        var onField = Set(offense.players.map(\.id))
        onField.formUnion(defense.players.map(\.id))
        return roster
            .filter {
                LineupGroup(of: $0.position) == group
                    && !onField.contains($0.id)
                    && !injuredPlayerIDs.contains($0.id)
            }
            .sorted { $0.overall > $1.overall }
    }

    /// Queues a substitution on the PLAYER's team: the bench player takes the
    /// field player's slot at the next whistle. Validates that both men share
    /// a position group and that the bench player is healthy and actually off
    /// the field. A new order for the same slot (or the same entrant)
    /// replaces the previously queued one.
    /// - Returns: true when the substitution was accepted and queued.
    @discardableResult
    func substitute(benchPlayerID: UUID, forFieldPlayerID fieldPlayerID: UUID) -> Bool {
        guard !isGameOver else { return false }
        let roster = playerTeamIsHome ? homePlayers : awayPlayers
        guard let benchPlayer = roster.first(where: { $0.id == benchPlayerID }),
              !injuredPlayerIDs.contains(benchPlayerID) else { return false }

        let offense = playerOffenseUnit
        let defense = playerDefenseUnit
        guard offense.role(of: benchPlayerID) == nil,
              defense.role(of: benchPlayerID) == nil else { return false }

        let isOffenseUnit: Bool
        let role: Int
        let fieldPlayer: SimPlayer
        if let r = offense.role(of: fieldPlayerID) {
            isOffenseUnit = true; role = r; fieldPlayer = offense[r]
        } else if let r = defense.role(of: fieldPlayerID) {
            isOffenseUnit = false; role = r; fieldPlayer = defense[r]
        } else {
            return false
        }
        guard LineupGroup(of: benchPlayer.position) == LineupGroup(of: fieldPlayer.position) else {
            return false
        }

        pendingSubstitutions.removeAll {
            $0.fieldPlayerID == fieldPlayerID || $0.benchPlayerID == benchPlayerID
        }
        pendingSubstitutions.append(PendingSubstitution(
            benchPlayerID: benchPlayerID,
            fieldPlayerID: fieldPlayerID,
            benchName: benchPlayer.shortName,
            fieldName: fieldPlayer.shortName,
            isOffenseUnit: isOffenseUnit,
            role: role
        ))
        return true
    }

    /// Withdraws a queued substitution before it lands.
    func cancelSubstitution(_ id: UUID) {
        pendingSubstitutions.removeAll { $0.id == id }
    }

    /// One player's live game line for the management sheet.
    struct LivePlayerLine {
        let playerID: UUID
        let fatigue: Int
        let morale: Int
        let matchupWins: Int
        let matchupLosses: Int
        /// Accumulated box-score line ("4 CAR · 22 YDS"); empty until he has one.
        let statLine: String
    }

    /// Live stats/condition for a player on the PLAYER's team (nil otherwise).
    /// Stats accumulate per completed drive, mirroring the quick sim; fatigue
    /// is always current. Purely presentational.
    func liveLine(for playerID: UUID) -> LivePlayerLine? {
        let roster = playerTeamIsHome ? homePlayers : awayPlayers
        guard let player = roster.first(where: { $0.id == playerID }) else { return nil }
        return LivePlayerLine(
            playerID: playerID,
            fatigue: player.fatigue,
            morale: player.morale,
            matchupWins: matchupWins[playerID] ?? 0,
            matchupLosses: matchupLosses[playerID] ?? 0,
            statLine: statsAccumulator[playerID].map(LiveGameEngine.compactStatLine) ?? ""
        )
    }

    /// "12/18 · 145 YDS · 1 TD | 3 CAR · 12 YDS" — only the categories he has.
    private static func compactStatLine(_ s: PlayerGameStats) -> String {
        var parts: [String] = []
        if s.attempts > 0 {
            var line = "\(s.completions)/\(s.attempts) · \(s.passingYards) YDS"
            if s.passingTDs > 0 { line += " · \(s.passingTDs) TD" }
            if s.interceptions > 0 { line += " · \(s.interceptions) INT" }
            parts.append(line)
        }
        if s.carries > 0 {
            var line = "\(s.carries) CAR · \(s.rushingYards) YDS"
            if s.rushingTDs > 0 { line += " · \(s.rushingTDs) TD" }
            parts.append(line)
        }
        if s.receptions > 0 || s.targets > 0 {
            var line = "\(s.receptions) REC · \(s.receivingYards) YDS"
            if s.receivingTDs > 0 { line += " · \(s.receivingTDs) TD" }
            parts.append(line)
        }
        if s.tackles > 0 || s.sacks > 0 || s.passDeflectionCount > 0 {
            var defenseBits: [String] = []
            if s.tackles > 0 { defenseBits.append("\(s.tackles) TKL") }
            if s.sacks > 0 {
                let count = s.sacks.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(s.sacks)) : String(format: "%.1f", s.sacks)
                defenseBits.append("\(count) SACK\(s.sacks == 1 ? "" : "S")")
            }
            if s.passDeflectionCount > 0 { defenseBits.append("\(s.passDeflectionCount) PD") }
            parts.append(defenseBits.joined(separator: " · "))
        }
        return parts.joined(separator: " | ")
    }

    // MARK: - Live Stat Leaders

    /// One statistical leader line for the live box score panel.
    struct StatLeader: Identifiable {
        let id: UUID
        let name: String
        /// Compact stat line, e.g. "18/25 · 245 YDS · 2 TD".
        let detail: String
    }

    /// Stats accumulate per completed drive (mirroring the quick sim), so
    /// these leaders reflect everything up to the current drive.
    func passingLeader(forHome: Bool) -> StatLeader? {
        teamStats(forHome: forHome)
            .filter { $0.attempts > 0 }
            .max { $0.passingYards < $1.passingYards }
            .map { s in
                var detail = "\(s.completions)/\(s.attempts) · \(s.passingYards) YDS"
                if s.passingTDs > 0 { detail += " · \(s.passingTDs) TD" }
                if s.interceptions > 0 { detail += " · \(s.interceptions) INT" }
                return StatLeader(id: s.playerID, name: shortName(s.playerName), detail: detail)
            }
    }

    func rushingLeader(forHome: Bool) -> StatLeader? {
        teamStats(forHome: forHome)
            .filter { $0.carries > 0 }
            .max { $0.rushingYards < $1.rushingYards }
            .map { s in
                var detail = "\(s.carries) CAR · \(s.rushingYards) YDS"
                if s.rushingTDs > 0 { detail += " · \(s.rushingTDs) TD" }
                return StatLeader(id: s.playerID, name: shortName(s.playerName), detail: detail)
            }
    }

    func receivingLeader(forHome: Bool) -> StatLeader? {
        teamStats(forHome: forHome)
            .filter { $0.receptions > 0 }
            .max { $0.receivingYards < $1.receivingYards }
            .map { s in
                var detail = "\(s.receptions) REC · \(s.receivingYards) YDS"
                if s.receivingTDs > 0 { detail += " · \(s.receivingTDs) TD" }
                return StatLeader(id: s.playerID, name: shortName(s.playerName), detail: detail)
            }
    }

    func sackLeader(forHome: Bool) -> StatLeader? {
        teamStats(forHome: forHome)
            .filter { $0.sacks > 0 }
            .max { $0.sacks < $1.sacks }
            .map { s in
                let count = s.sacks.truncatingRemainder(dividingBy: 1) == 0
                    ? String(Int(s.sacks)) : String(format: "%.1f", s.sacks)
                return StatLeader(id: s.playerID, name: shortName(s.playerName),
                                  detail: "\(count) SACK\(s.sacks == 1 ? "" : "S") · \(s.tackles) TKL")
            }
    }

    /// Total offensive yards from completed drives (same accounting as
    /// `GameSimulator.buildTeamBoxScore` — scrimmage plays only, penalty
    /// walk-offs and special-teams yardage excluded).
    func totalYards(forHome: Bool) -> Int {
        let teamID = forHome ? homeTeamID : awayTeamID
        return allDrives
            .filter { $0.teamID == teamID }
            .reduce(0) { total, drive in
                total + drive.plays
                    .filter { ($0.playType == .pass || $0.playType == .run) && $0.outcome != .penalty }
                    .reduce(0) { $0 + $1.yardsGained }
            }
    }

    private func teamStats(forHome: Bool) -> [PlayerGameStats] {
        let ids = forHome ? homePlayerIDs : awayPlayerIDs
        return ids.compactMap { statsAccumulator[$0] }
    }

    /// "T. Hill" — mirrors `SimPlayer.shortName` for stat-line names.
    private func shortName(_ fullName: String) -> String {
        let parts = fullName.split(separator: " ")
        guard parts.count >= 2, let first = parts.first?.first else { return fullName }
        return "\(first). \(parts.dropFirst().joined(separator: " "))"
    }

    /// True when the player's team currently has the ball.
    var playerIsOnOffense: Bool { playerTeamIsHome == homeHasPossession }

    // MARK: - Situation Helpers (UI)

    var isFourthDown: Bool { down == 4 }

    /// Field-goal attempt length in yards (line of scrimmage + 17 for snap/hold).
    var fieldGoalDistance: Int { 100 - yardLine + 17 }

    /// Whether a field goal is realistic from here (<= 45 yards to the end
    /// zone, same convention as `PlaySimulator.decidePlayCall`).
    var canAttemptFieldGoal: Bool { (100 - yardLine) <= 45 }

    /// Clock string like "14:05".
    var formattedClock: String {
        let t = max(0, timeRemaining)
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    var possessionTeamID: UUID { homeHasPossession ? homeTeamID : awayTeamID }

    /// Starters currently on offense / defense (role-ordered).
    var currentOffenseUnit: FieldUnit { homeHasPossession ? homeOffenseUnit : awayOffenseUnit }
    var currentDefenseUnit: FieldUnit { homeHasPossession ? awayDefenseUnit : homeDefenseUnit }

    /// The offensive scheme of the team currently in possession (its playbook).
    var currentOffensiveScheme: OffensiveScheme? { homeHasPossession ? homeOffScheme : awayOffScheme }
    /// The player's own offensive/defensive schemes (for the call sheet UI).
    var playerOffensiveScheme: OffensiveScheme? { playerTeamIsHome ? homeOffScheme : awayOffScheme }
    var playerDefensiveScheme: DefensiveScheme? { playerTeamIsHome ? homeDefScheme : awayDefScheme }

    /// Average playbook familiarity (0–100) of the player's offensive starters.
    var playerPlaybookFamiliarity: Int {
        guard let scheme = playerOffensiveScheme else { return 100 }
        let unit = playerTeamIsHome ? homeOffenseUnit : awayOffenseUnit
        let total = unit.players.reduce(0) { $0 + $1.schemeFam(for: scheme.rawValue) }
        return total / max(1, unit.players.count)
    }

    /// Current momentum (-1 away … +1 home), for UI meters.
    var currentMomentum: Double { momentum }

    // MARK: - Adaptive Opponent AI (live only)

    /// Broadcast-style intel line published when the AI opponent locks onto
    /// (or shifts) a read of the player's tendencies — "CHI is keying on the
    /// inside run". Rate-limited to ~1 per 2 minutes of game time. Purely
    /// presentational; the counter-calls themselves flow through
    /// ``aiDefensivePackage()`` / ``aiOffensiveCall()``.
    struct AdaptationHint: Equatable, Identifiable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var lastAdaptationHint: AdaptationHint?

    /// The player's recorded call history for this game (see
    /// ``AdaptiveOpponentAI/Tracker``). Fills only from explicit live calls
    /// passed to ``step`` — a nil-argument game never records, so quick-sim
    /// parity is intact.
    private var tendencyTracker = AdaptiveOpponentAI.Tracker()

    /// The tendency the AI DEFENSE is currently keying on (player attacks).
    private var activeDefenseRead: AdaptiveOpponentAI.OffenseTendency?
    /// The tendency the AI OFFENSE is currently exploiting (player defends).
    private var activeOffenseRead: AdaptiveOpponentAI.DefenseTendency?
    /// Counter calls rolled once per snap (at the end of the previous
    /// ``step``), so the pre-snap preview and the actual play always agree.
    private var pendingDefenseCounter: DefensivePackage?
    private var pendingOffenseCounter: OffensivePlayCall?
    /// Absolute game second of the last published hint (rate limiting).
    private var lastHintGameSecond: Int?
    private static let hintCooldownSeconds = 120

    /// Opponent coordinator grades — how fast and hard the AI counters
    /// (see `AdaptiveOpponentAI.scaledThreshold` / `counterShare`).
    private let opponentDCGrade: Int
    private let opponentOCGrade: Int
    /// Opponent abbreviation for the intel lines ("CHI is keying on ...").
    private let opponentAbbreviation: String

    // MARK: - Coordinator Personas (R33, live only)

    /// The opponent coordinators' play-calling personas (deterministic from
    /// scheme + Coach id — see `CoordinatorPersona.swift`). They shade the
    /// AI's BASE calls (`aiDefensivePackage` / `aiOffensiveCall`) and scale
    /// the adaptive core's thresholds/counter shares. No coordinator on the
    /// roster = `.balanced` = today's exact behavior.
    private let opponentDCPersona: DCPersona
    private let opponentOCPersona: OCPersona

    /// Persona-shaded base defense pre-rolled for the NEXT snap (same
    /// once-per-snap contract as the counters, so every `aiDefensivePackage`
    /// call this snap agrees). `nil` = unshaded base.
    private var pendingPersonaDefense: DefensivePackage?
    /// OC-persona signature play pre-rolled for the NEXT AI offensive snap.
    private var pendingSignatureCall: OffensivePlayCall?

    // MARK: - Player Coordinators (#26, live only, presentation)

    /// The PLAYER's own coordinators — they make the pre-snap recommendation
    /// shown in the call sheet. Deterministic from the same scheme + Coach-id
    /// derivation the opponent personas use, so a given staff always advises
    /// the same way. A vacant seat falls back to `.balanced` / grade 50.
    private let playerOCPersona: OCPersona
    private let playerDCPersona: DCPersona
    private let playerOCGrade: Int
    private let playerDCGrade: Int
    /// Coordinator display names for the recommendation bubble ("S. McVay").
    let playerOCName: String
    let playerDCName: String

    /// Rolling window of the opponent offense's recent scrimmage play types
    /// (run/pass), newest last — feeds the DC recommendation's reasoning. Only
    /// grows while the player is on defense; see `opponentRunLean`.
    private var opponentPlayTypes: [PlayType] = []

    // MARK: - Immutable Setup

    let homeTeamID: UUID
    let awayTeamID: UUID
    let playerTeamIsHome: Bool

    private let homeOffScheme: OffensiveScheme?
    private let homeDefScheme: DefensiveScheme?
    private let awayOffScheme: OffensiveScheme?
    private let awayDefScheme: DefensiveScheme?
    private let audibleBoost: Double
    private let defReadBoost: Double
    /// Game weather, applied identically to both teams on every play (same
    /// value the quick sim would use for this game). `nil` = clear skies =
    /// today's exact behavior.
    let weather: GameWeather?

    // MARK: - Player Game Plan

    /// Hand-off slot for the user's saved ``GamePlan``. Set by the dashboard
    /// right before presenting the coached game; consumed (and cleared) in
    /// `init`. A static hand-off is used because `CoachedGameView` constructs
    /// this engine itself and its signature must stay untouched. Same pattern
    /// as `WeekAdvancer.lastPlayerGameResult`.
    static var pendingPlayerGamePlan: GamePlan?

    /// The user's game plan for this match, or `nil` (= no bias, today's
    /// behavior). Only ever applied to the PLAYER's team — AI play-calling
    /// for the opponent is never affected.
    private let playerGamePlan: GamePlan?

    // MARK: - Practiced Playbook Additions (R36)

    /// Plays the user's team installed through weekly practice this season,
    /// on top of the scheme playbook. Empty = today's exact behavior. They
    /// only widen the PLAYER's own call sheet — the AI never reads them.
    let playerBonusPlays: Set<OffensivePlayCall>

    /// Whether the given play is on the player's installed call sheet: in
    /// the scheme playbook, or added through weekly practice (R36).
    func playerHasInstalled(_ play: OffensivePlayCall) -> Bool {
        play.isInPlaybook(of: playerOffensiveScheme) || playerBonusPlays.contains(play)
    }

    // MARK: - Simulation State

    private var homePlayers: [SimPlayer]
    private var awayPlayers: [SimPlayer]
    /// Role-ordered starters for the 3D field and matchup attribution.
    /// Published because injuries and fatigue rotation swap players mid-game
    /// (the view's next formation move picks up the new jersey numbers).
    @Published private(set) var homeOffenseUnit: FieldUnit
    @Published private(set) var homeDefenseUnit: FieldUnit
    @Published private(set) var awayOffenseUnit: FieldUnit
    @Published private(set) var awayDefenseUnit: FieldUnit
    /// Medical staff per side — shapes live injury risk exactly like the
    /// quick sim's weekly `MedicalEngine.injuryCheck`, and recovery weeks at
    /// the end-of-game write-back.
    private let homeDoctor: Coach?
    private let homePhysio: Coach?
    private let awayDoctor: Coach?
    private let awayPhysio: Coach?
    private let livePlayerByID: [UUID: Player]
    /// Roster membership for splitting the shared stats accumulator per team.
    private let homePlayerIDs: [UUID]
    private let awayPlayerIDs: [UUID]
    private var momentum: Double = GameSimulator.homeFieldMomentum
    private var statsAccumulator: [UUID: PlayerGameStats] = [:]
    private var allDrives: [DriveResult] = []
    private var allHighlights: [PlayResult] = []
    private var homeTimeOfPossession = 0
    private var awayTimeOfPossession = 0
    private var driveStartYardLine: Int = GameSimulator.touchbackYardLine
    private var moraleAppliedForCurrentDrive = false

    private var isOvertime: Bool { quarter >= GameSimulator.overtimeQuarter }

    // MARK: - Init

    /// - Parameters:
    ///   - playerTeamIsHome: Which side the user coaches (drives `playerIsOnOffense`).
    ///   - audibleBoost: 0..0.20 opponent-prep offense boost for the player's team.
    ///   - defReadBoost: 0..0.15 opponent-prep defense boost for the player's team.
    ///   - weather: Optional game weather (``GameWeather/forGame(id:week:)``).
    ///     `nil` = clear = today's exact behavior.
    init(
        homeTeam: Team,
        awayTeam: Team,
        homeCoaches: [Coach],
        awayCoaches: [Coach],
        playerTeamIsHome: Bool,
        audibleBoost: Double = 0,
        defReadBoost: Double = 0,
        weather: GameWeather? = nil,
        playerBonusPlays: Set<OffensivePlayCall> = []
    ) {
        homeTeamID = homeTeam.id
        awayTeamID = awayTeam.id
        self.playerTeamIsHome = playerTeamIsHome
        self.audibleBoost = max(0.0, min(0.20, audibleBoost))
        self.defReadBoost = max(0.0, min(0.15, defReadBoost))
        self.weather = weather
        self.playerBonusPlays = playerBonusPlays

        // Consume the game-plan hand-off (see `pendingPlayerGamePlan`).
        self.playerGamePlan = LiveGameEngine.pendingPlayerGamePlan
        LiveGameEngine.pendingPlayerGamePlan = nil

        // Snapshot both rosters into value types once (same rationale as
        // GameSimulator.simulate): reading SwiftData @Model properties in the
        // play-by-play hot path is far too slow. Live models are kept in a
        // lookup so fatigue can be written back after the game.
        // R22: a player holding out over his contract does not suit up.
        let homeRoster = homeTeam.players.filter { !$0.isHoldingOut }
        let awayRoster = awayTeam.players.filter { !$0.isHoldingOut }
        homePlayers = homeRoster.map(SimPlayer.init(from:))
        awayPlayers = awayRoster.map(SimPlayer.init(from:))
        homeOffenseUnit = FieldUnit.offense(from: homePlayers)
        homeDefenseUnit = FieldUnit.defense(from: homePlayers)
        awayOffenseUnit = FieldUnit.offense(from: awayPlayers)
        awayDefenseUnit = FieldUnit.defense(from: awayPlayers)
        var lookup: [UUID: Player] = [:]
        for player in homeRoster { lookup[player.id] = player }
        for player in awayRoster { lookup[player.id] = player }
        livePlayerByID = lookup
        homePlayerIDs = homePlayers.map(\.id)
        awayPlayerIDs = awayPlayers.map(\.id)

        // Extract team schemes from the coaching staff, exactly like
        // GameSimulator.simulate.
        homeOffScheme = homeCoaches.first { $0.role == .offensiveCoordinator }?.offensiveScheme
        homeDefScheme = homeCoaches.first { $0.role == .defensiveCoordinator }?.defensiveScheme
        awayOffScheme = awayCoaches.first { $0.role == .offensiveCoordinator }?.offensiveScheme
        awayDefScheme = awayCoaches.first { $0.role == .defensiveCoordinator }?.defensiveScheme

        // Adaptive opponent AI: the OPPONENT's coordinators decide how fast
        // and hard the AI counters the player's tendencies. Grade blends
        // play-calling with adaptability; 50 = league-average fallback.
        let opponentCoaches = playerTeamIsHome ? awayCoaches : homeCoaches
        opponentDCGrade = opponentCoaches.first { $0.role == .defensiveCoordinator }
            .map { ($0.playCalling + $0.adaptability) / 2 } ?? 50
        opponentOCGrade = opponentCoaches.first { $0.role == .offensiveCoordinator }
            .map { ($0.playCalling + $0.adaptability) / 2 } ?? 50
        opponentAbbreviation = playerTeamIsHome ? awayTeam.abbreviation : homeTeam.abbreviation

        // R33: coordinator personas — deterministic from the opponent's DC/OC
        // (scheme + Coach id). No coordinator = balanced = today's behavior.
        opponentDCPersona = opponentCoaches.first { $0.role == .defensiveCoordinator }
            .map(DCPersona.derive(for:)) ?? .balanced
        opponentOCPersona = opponentCoaches.first { $0.role == .offensiveCoordinator }
            .map(OCPersona.derive(for:)) ?? .balanced

        // #26: the PLAYER's own coordinators drive the pre-snap recommendation.
        // Same derivation as the opponent personas; grade blends play-calling
        // with adaptability (a sharper coordinator gives a more specific read).
        let playerCoaches = playerTeamIsHome ? homeCoaches : awayCoaches
        let playerOC = playerCoaches.first { $0.role == .offensiveCoordinator }
        let playerDC = playerCoaches.first { $0.role == .defensiveCoordinator }
        playerOCPersona = playerOC.map(OCPersona.derive(for:)) ?? .balanced
        playerDCPersona = playerDC.map(DCPersona.derive(for:)) ?? .balanced
        playerOCGrade = playerOC.map { ($0.playCalling + $0.adaptability) / 2 } ?? 50
        playerDCGrade = playerDC.map { ($0.playCalling + $0.adaptability) / 2 } ?? 50
        playerOCName = playerOC.map(LiveGameEngine.coordShortName) ?? "OC"
        playerDCName = playerDC.map(LiveGameEngine.coordShortName) ?? "DC"

        // Medical staff for live injury risk/recovery (mirrors WeekAdvancer's
        // per-team doctor/physio lookup for the weekly roll).
        homeDoctor = homeCoaches.first { $0.role == .teamDoctor }
        homePhysio = homeCoaches.first { $0.role == .physio }
        awayDoctor = awayCoaches.first { $0.role == .teamDoctor }
        awayPhysio = awayCoaches.first { $0.role == .physio }

        // Seed stat entries for every rostered player.
        GameSimulator.initializeStats(for: homePlayers, into: &statsAccumulator)
        GameSimulator.initializeStats(for: awayPlayers, into: &statsAccumulator)

        // Opening kickoff: away kicks to home; the start position comes from
        // the shared kickoff distribution (mirrors GameSimulator.simulate).
        let openingKick = GameSimulator.rollKickoff(allowReturnTouchdown: false)
        driveStartYardLine = openingKick.startingYardLine
        yardLine = openingKick.startingYardLine
        distance = min(10, 100 - openingKick.startingYardLine)
        pendingKickoff = KickoffEvent(
            kickingTeamIsHome: false,
            startYardLine: openingKick.startingYardLine,
            isTouchback: openingKick.isTouchback,
            isReturnTouchdown: false
        )

        // R33: pre-kickoff booth intel on the opponent's coordinators —
        // feed-only lines (playNumber 0), fixed strings, no RNG, so both
        // auto-sim parity and the once-per-snap counter contract hold.
        postFeedNote(opponentDCPersona.broadcastIntro(abbr: opponentAbbreviation))
        postFeedNote(opponentOCPersona.broadcastIntro(abbr: opponentAbbreviation))
    }

    // MARK: - Step (one play)

    /// Runs exactly one play and advances all game state.
    ///
    /// - Parameters:
    ///   - offensiveCall: Explicit offensive call. `nil` lets the AI decide
    ///     via `PlaySimulator.decidePlayCall` (identical to auto-sim).
    ///   - forcedPlayType: Highest-precedence override, used for 4th-down
    ///     special-teams decisions (.punt / .fieldGoal / .kneel).
    ///   - defensivePackage: Explicit defensive call. `nil` = neutral defense.
    /// - Returns: The play that was run (also published as ``lastPlay``).
    @discardableResult
    func step(
        offensiveCall: OffensivePlayCall? = nil,
        forcedPlayType: PlayType? = nil,
        defensivePackage: DefensivePackage? = nil
    ) -> PlayResult {
        guard !isGameOver else {
            return lastPlay ?? gameOverPlaceholderPlay()
        }

        // A pending point-after try resolves before anything else can snap:
        // the shared chart decides here, so a fully nil-argument game rolls
        // exactly the same tries the quick sim does (parity intact). The
        // live view calls ``attemptConversion`` directly for player choices.
        if pendingConversion != nil {
            return attemptConversion(defensivePackage: defensivePackage)
        }

        // Coach-ordered substitutions land at the whistle: applied after this
        // play has fully resolved (dead ball), never mid-play. A no-op when
        // nothing is queued, so auto-sim parity is intact.
        defer { applyPendingSubstitutions() }

        // Adaptive opponent AI: re-read the player's tendencies and roll the
        // NEXT snap's counter calls once this play (and any drive/possession
        // bookkeeping) has fully resolved. A no-op until the player's
        // explicit calls have filled the tracker — nil-argument parity intact.
        defer { updateAdaptationState() }

        lastPlayInjuries = []

        // GameSimulator applies morale/personality modifiers once per drive.
        if !moraleAppliedForCurrentDrive {
            GameSimulator.applyMoraleModifiers(players: &homePlayers, quarter: quarter)
            GameSimulator.applyMoraleModifiers(players: &awayPlayers, quarter: quarter)
            moraleAppliedForCurrentDrive = true
        }

        // Injured (and fatigue-rested or manually benched) players are off
        // the board: the sim picks its QB/RB/targets from the remaining
        // roster, so the replacement genuinely plays. With nobody sidelined
        // these are the full rosters — identical to GameSimulator.simulate.
        let offense = simAvailablePlayers(isHome: homeHasPossession)
        let defense = simAvailablePlayers(isHome: !homeHasPossession)

        // Momentum is offense-relative in PlaySimulator; positive favors home.
        // Opponent-prep boosts shade momentum slightly toward the player's
        // team (GameSimulator applies these as a final-score nudge instead;
        // a live game must keep its displayed score truthful, so the boost is
        // folded into per-play momentum at conservative strength).
        var playMomentum = homeHasPossession ? momentum : -momentum
        if audibleBoost > 0 || defReadBoost > 0 {
            if playerIsOnOffense {
                playMomentum = min(1.0, playMomentum + audibleBoost * 0.5)
            } else {
                playMomentum = max(-1.0, playMomentum - defReadBoost * 0.5)
            }
        }

        let result = PlaySimulator.simulatePlay(
            offensePlayers: offense,
            defensePlayers: defense,
            down: down,
            distance: distance,
            yardLine: yardLine,
            quarter: quarter,
            timeRemaining: timeRemaining,
            momentum: playMomentum,
            playNumber: currentDrivePlays.count + 1,
            offensiveScheme: homeHasPossession ? homeOffScheme : awayOffScheme,
            defensiveScheme: homeHasPossession ? awayDefScheme : homeDefScheme,
            offensiveCall: offensiveCall,
            forcedPlayType: forcedPlayType,
            defensivePackage: defensivePackage,
            gamePlan: playerIsOnOffense ? playerGamePlan : nil,
            weather: weather,
            // Halftime adjustment: player's team offense only, second half only.
            adjustments: (quarter >= 3 && playerIsOnOffense) ? halftimeAdjustment?.simAdjustments : nil
        )

        // Adaptive opponent AI: log the PLAYER's explicit call for tendency
        // tracking (scrimmage snaps only — the intent counts even when a
        // flag wipes the down out). AI-side calls are never recorded.
        if result.playType == .pass || result.playType == .run {
            if playerIsOnOffense {
                if let call = offensiveCall { tendencyTracker.recordOffense(call) }
            } else {
                if let package = defensivePackage { tendencyTracker.recordDefense(package) }
                // #26: opponent-offense run/pass window, feeding the DC
                // recommendation bubble ("they've leaned on the run — load the
                // box"). Presentation-only: records a value already resolved,
                // rolls no RNG, and never changes a result — parity intact.
                opponentPlayTypes.append(result.playType)
                if opponentPlayTypes.count > 8 { opponentPlayTypes.removeFirst() }
            }
        }

        // Record the play with the clock state at the snap (mirrors DriveSimulator).
        var recordedPlay = result
        recordedPlay.quarter = quarter
        recordedPlay.timeRemaining = timeRemaining
        // R37: stamp possession so the feed can color defensive plays from
        // the player's perspective (a sack BY his defense reads positive).
        recordedPlay.offenseWasHome = homeHasPossession
        currentDrivePlays.append(recordedPlay)
        playLog.append(recordedPlay)
        lastPlay = recordedPlay

        // Attribute the play to individual matchup winners for the live view.
        if result.playType == .pass || result.playType == .run {
            let offenseUnit = currentOffenseUnit
            let defenseUnit = currentDefenseUnit
            lastMatchups = MatchupResolver.resolve(
                play: recordedPlay,
                offense: offenseUnit,
                defense: defenseUnit,
                offensiveScheme: homeHasPossession ? homeOffScheme : awayOffScheme,
                offensiveCall: offensiveCall
            )
            // First-half battle lines feed the halftime report (capped).
            if recordedPlay.quarter <= 2, let events = lastMatchups?.events, !events.isEmpty {
                let room = LiveGameEngine.firstHalfMatchupEventCap - firstHalfMatchupEvents.count
                if room > 0 {
                    firstHalfMatchupEvents.append(contentsOf: events.prefix(room))
                }
            }
            // Player grades: tally each named battle's winner and loser
            // (presentation only — the play outcome is already decided),
            // plus the per-category record for the Coach's Board. The
            // category derives from the participant's own role slot and the
            // play type — the same attribution MatchupResolver already made.
            if let events = lastMatchups?.events {
                for event in events {
                    if let offRole = event.offRole {
                        let id = offenseUnit[offRole].id
                        if event.offenseWon {
                            matchupWins[id, default: 0] += 1
                        } else {
                            matchupLosses[id, default: 0] += 1
                        }
                        let category = LiveGameEngine.offenseCategory(
                            role: offRole, playType: recordedPlay.playType
                        )
                        categoryTallies[id, default: [:]][category, default: CategoryTally()]
                            .record(win: event.offenseWon)
                    }
                    if let defRole = event.defRole {
                        let id = defenseUnit[defRole].id
                        if event.offenseWon {
                            matchupLosses[id, default: 0] += 1
                        } else {
                            matchupWins[id, default: 0] += 1
                        }
                        let category = LiveGameEngine.defenseCategory(
                            role: defRole, playType: recordedPlay.playType
                        )
                        categoryTallies[id, default: [:]][category, default: CategoryTally()]
                            .record(win: !event.offenseWon)
                    }
                }
            }
            // Day-grade extras (presentation only): 20+ yard plays credit
            // the ball's key man, lost fumbles are charged to him, and a
            // sack counts against the QB who took it.
            if recordedPlay.yardsGained >= 20, let keyID = recordedPlay.keyOffensePlayerID {
                bigPlayCounts[keyID, default: 0] += 1
            }
            if recordedPlay.outcome == .fumbleLost, let keyID = recordedPlay.keyOffensePlayerID {
                turnoverCounts[keyID, default: 0] += 1
            }
            if recordedPlay.outcome == .sack {
                sackTakenCounts[offenseUnit[0].id, default: 0] += 1
            }
            // Missed read: a clearly open man went unthrown on a failed or
            // short dropback — small QB grade ding (presentation only; the
            // feed line comes from the same matchup event).
            if lastMatchups?.qbMissedOpenMan == true {
                missedReadCounts[offenseUnit[0].id, default: 0] += 1
            }
        } else {
            lastMatchups = nil
        }

        // Per-play injury dice for the contact participants (live-game
        // counterpart of the quick sim's weekly roll — see rollInjuries).
        rollInjuries(for: recordedPlay)

        // --- Consume clock (mirrors DriveSimulator.simulateDrive) ---
        // A pending timeout freezes the clock: this play's runoff is zeroed.
        var elapsed = DriveSimulator.clockConsumption(for: result)
        if timeoutClockStopPending {
            elapsed = 0
            timeoutClockStopPending = false
        }
        timeRemaining -= elapsed

        if timeRemaining <= 0 {
            let overflow = abs(timeRemaining)
            if DriveSimulator.shouldEndDrive(quarter: quarter) {
                // Q2 / Q4 / OT: the half or game segment ends here.
                timeRemaining = 0
                // The play itself may still have ended the drive (TD at the
                // gun — which still earns its untimed point-after try).
                if let driveEnd = immediateDriveEnd(for: result) {
                    finishOrHoldDrive(driveEnd.drive, after: result)
                    return recordedPlay
                }
                let outcome: DriveOutcome = quarter == 2 ? .endOfHalf : .endOfGame
                finishDrive(makeDriveResult(outcome))
                return recordedPlay
            } else {
                // Quarter transition (Q1 -> Q2, Q3 -> Q4): drive continues.
                quarter += 1
                timeRemaining = GameSimulator.quarterDuration - overflow
            }
        }

        // --- Immediate drive-ending outcomes (score, turnover, punt, safety) ---
        if let driveEnd = immediateDriveEnd(for: result) {
            finishOrHoldDrive(driveEnd.drive, after: result)
            return recordedPlay
        }

        // --- Down & distance ---
        let advanced = DriveSimulator.advanceDownAndDistance(
            playResult: result,
            currentDown: down,
            currentDistance: distance,
            currentYardLine: yardLine
        )
        down = advanced.down
        distance = advanced.distance
        yardLine = advanced.yardLine

        // --- Turnover on downs ---
        if down > 4 {
            finishDrive(makeDriveResult(.turnoverOnDowns))
            return recordedPlay
        }

        // Safety valve: prevent infinite drives (mirrors DriveSimulator's cap).
        if currentDrivePlays.count >= 40 {
            finishDrive(makeDriveResult(.punt))
        }

        return recordedPlay
    }

    // MARK: - AI Suggestions

    /// The play type the auto-sim AI would call in the current situation.
    /// When the PLAYER's team has the ball, the suggestion honors the user's
    /// saved game plan (run/pass mix, 4th-down aggressiveness).
    func aiOffensiveCallHint() -> PlayType {
        PlaySimulator.decidePlayCall(
            down: down,
            distance: distance,
            yardLine: yardLine,
            quarter: quarter,
            timeRemaining: timeRemaining,
            offensiveScheme: homeHasPossession ? homeOffScheme : awayOffScheme,
            gamePlan: playerIsOnOffense ? playerGamePlan : nil,
            weather: weather
        )
    }

    /// A simple situational defensive call for the AI (or as a user default).
    /// When suggesting for the PLAYER's defense, the user's game plan shades
    /// the blitz package: heavy blitz plans send pressure on standard downs,
    /// coverage-first plans call off the situational blitzes.
    func aiDefensivePackage() -> DefensivePackage {
        let yardsToEndzone = 100 - yardLine
        var package = baseDefensivePackage()

        if playerIsOnOffense, yardsToEndzone > 10, package.coverage != .prevent {
            // R33: DC-persona shading of the base fabric (aggressive blitzes
            // standard downs, conservative calls pressure off, exotic mixes
            // in Double A-Gap / Zone Blitz / Bear). Pre-rolled once per snap
            // (see updateAdaptationState) so every preview agrees. Never the
            // red-zone sellout or the late-lead prevent shell.
            if let shaded = pendingPersonaDefense {
                package = shaded
            }
            // Adaptive counter (AI defense vs the PLAYER's offense, live
            // only): when the player's calls have shown a clear tendency,
            // the pre-rolled counter replaces the (persona-shaded) base pick.
            if let counter = pendingDefenseCounter {
                package = counter
            }
        }

        // Game-plan shading — only for the player's own defense.
        if !playerIsOnOffense, let plan = playerGamePlan {
            if plan.blitzFrequency > 0.65, package.blitz == .noBlitz,
               yardsToEndzone > 10, package.coverage != .prevent {
                // The heaviest blitz plans send both backers up the middle.
                package.blitz = plan.blitzFrequency > 0.85 ? .doubleAGap : .lbBlitz
            } else if plan.blitzFrequency < 0.25, package.blitz != .noBlitz {
                package.blitz = .noBlitz
            }
            if plan.defensiveAggression > 0.75, package.coverage == .cover3 {
                package.coverage = .manToMan
            }
        }
        return package
    }

    /// The purely situational base package (today's exact logic) — shared by
    /// the live pick and the persona pre-roll so both see the same fabric.
    private func baseDefensivePackage() -> DefensivePackage {
        let yardsToEndzone = 100 - yardLine
        // Score margin from the DEFENSE's perspective (positive = leading).
        let defenseLeadsBy = homeHasPossession ? awayScore - homeScore : homeScore - awayScore
        if yardsToEndzone <= 10 {
            // Red zone: sell out against the short field.
            return DefensivePackage(coverage: .manToMan, blitz: .noBlitz, front: .goalLine)
        } else if quarter >= 4 && timeRemaining <= 240
                    && defenseLeadsBy > 0 && defenseLeadsBy <= 16
                    && yardsToEndzone > 25 {
            // Protecting a late lead: prevent shell — concede the checkdown,
            // never the bomb.
            return DefensivePackage(coverage: .prevent, blitz: .noBlitz, front: .dime)
        } else if down == 3 && distance >= 7 {
            // 3rd & long: extra DBs and a pressure look.
            return DefensivePackage(coverage: .cover4, blitz: .dbBlitz, front: .dime)
        } else if distance <= 2 {
            // Short yardage: crowd the box with the bear front.
            return DefensivePackage(coverage: .cover1, blitz: .noBlitz, front: .bear)
        } else {
            return .standard // Cover 3, no blitz, base front
        }
    }

    /// The AI's adaptive offensive call for the next snap (player defends,
    /// live only). Returns the pre-rolled counter play when the player's
    /// defensive tendencies triggered one, else the OC persona's pre-rolled
    /// signature call (R33), `nil` otherwise — and `nil` keeps today's base
    /// behavior exactly (`PlaySimulator.decidePlayCall`).
    /// Never fires on 4th down: punt/FG decisions stay with the base logic.
    func aiOffensiveCall() -> OffensivePlayCall? {
        guard !isGameOver, !playerIsOnOffense, down <= 3 else { return nil }
        return pendingOffenseCounter ?? pendingSignatureCall
    }

    // MARK: - Adaptive Opponent AI (private)

    /// Re-reads the player's tendencies after each step and rolls the NEXT
    /// snap's counter calls. Publishes an intel line when the AI's read
    /// first activates or shifts (rate-limited). With an empty tracker
    /// (nil-argument games) this resolves to no-ops and consumes no RNG.
    private func updateAdaptationState() {
        guard !isGameOver else { return }

        // AI DEFENSE reads the player's offense. The DC persona (R33) shades
        // how fast it keys and how hard it counters.
        let dcThreshold = AdaptiveOpponentAI.scaledThreshold(
            base: AdaptiveOpponentAI.offenseCategoryBaseThreshold,
            coordinatorGrade: opponentDCGrade
        ) + opponentDCPersona.thresholdOffset
        if let read = tendencyTracker.dominantOffenseTendency(threshold: dcThreshold) {
            if read != activeDefenseRead {
                activeDefenseRead = read
                emitAdaptationHint(
                    AdaptiveOpponentAI.defenseKeyHint(
                        for: read,
                        opponentAbbr: opponentAbbreviation,
                        persona: opponentDCPersona
                    )
                )
            }
            let share = min(
                AdaptiveOpponentAI.maxCounterShare,
                max(0.10, AdaptiveOpponentAI.counterShare(coordinatorGrade: opponentDCGrade)
                        * opponentDCPersona.counterShareMultiplier)
            )
            if Double.random(in: 0..<1) < share {
                // R33 over-reaction: an aggressive DC sometimes counters a
                // tendency that isn't the real one — the wrong package's
                // modifiers then work FOR the player.
                var counterRead = read
                if opponentDCPersona.misreadChance > 0,
                   Double.random(in: 0..<1) < opponentDCPersona.misreadChance,
                   let wrong = AdaptiveOpponentAI.OffenseTendency.allCases
                       .filter({ $0 != read }).randomElement() {
                    counterRead = wrong
                }
                pendingDefenseCounter = AdaptiveOpponentAI.defensiveCounter(
                    for: counterRead,
                    scheme: playerTeamIsHome ? awayDefScheme : homeDefScheme
                )
            } else {
                pendingDefenseCounter = nil
            }
        } else {
            activeDefenseRead = nil
            pendingDefenseCounter = nil
        }

        // AI OFFENSE reads the player's defense — OC persona shades the
        // trigger threshold and counter share mildly (identity > adaptation).
        if let read = tendencyTracker.dominantDefenseTendency(
            coordinatorGrade: opponentOCGrade,
            thresholdOffset: opponentOCPersona.adaptThresholdOffset
        ) {
            if read != activeOffenseRead {
                activeOffenseRead = read
                let qbName = (playerTeamIsHome ? awayOffenseUnit : homeOffenseUnit)[0].shortName
                emitAdaptationHint(
                    AdaptiveOpponentAI.offenseAdjustHint(
                        for: read,
                        qbName: qbName,
                        persona: opponentOCPersona
                    )
                )
            }
            let share = min(
                AdaptiveOpponentAI.maxCounterShare,
                max(0.10, AdaptiveOpponentAI.counterShare(coordinatorGrade: opponentOCGrade)
                        * opponentOCPersona.counterShareMultiplier)
            )
            pendingOffenseCounter = Double.random(in: 0..<1) < share
                ? AdaptiveOpponentAI.offensiveCounter(
                    for: read,
                    scheme: playerTeamIsHome ? awayOffScheme : homeOffScheme,
                    distance: distance,
                    yardsToEndzone: 100 - yardLine
                )
                : nil
        } else {
            activeOffenseRead = nil
            pendingOffenseCounter = nil
        }

        // R33: persona pre-rolls for the NEXT snap. Gated on the tracker
        // having at least one explicit player call, so a fully nil-argument
        // game (auto-sim) still consumes no RNG here — parity intact. The
        // situation (down/distance/possession) is already the next snap's.
        guard !tendencyTracker.isEmpty else {
            pendingPersonaDefense = nil
            pendingSignatureCall = nil
            return
        }

        // DC persona shades the base defense the AI would otherwise call
        // (never the red-zone sellout or the prevent shell).
        if playerIsOnOffense {
            let base = baseDefensivePackage()
            pendingPersonaDefense = (100 - yardLine > 10 && base.coverage != .prevent)
                ? opponentDCPersona.shadedDefense(
                    base: base,
                    distance: distance,
                    scheme: playerTeamIsHome ? awayDefScheme : homeDefScheme
                )
                : nil
        } else {
            pendingPersonaDefense = nil
        }

        // OC persona rolls a signature identity call when no counter is
        // pending (counters keep priority — a read beats an identity).
        pendingSignatureCall = (!playerIsOnOffense && down <= 3 && pendingOffenseCounter == nil)
            ? opponentOCPersona.rollSignatureCall(
                distance: distance,
                yardsToEndzone: 100 - yardLine,
                scheme: playerTeamIsHome ? awayOffScheme : homeOffScheme
            )
            : nil
    }

    // MARK: - Opponent Audibles (R36, live only, presentation only)

    /// When the AI's pre-rolled tendency counter is live for this snap, the
    /// coordinator occasionally sells it as a line-of-scrimmage audible — a
    /// feed line only. The counter itself (already folded into
    /// `aiDefensivePackage()` / `aiOffensiveCall()`) is untouched, so this
    /// changes nothing about the play; it just tells the story at the line.
    /// Aggressive DCs check more often. Call once per snap from the live
    /// view, right before the step; never fires in nil-argument games.
    func opponentAudibleFeedNote() -> String? {
        guard !isGameOver else { return nil }
        if playerIsOnOffense {
            guard pendingDefenseCounter != nil else { return nil }
            let chance: Double
            switch opponentDCPersona {
            case .aggressive:   chance = 0.35
            case .exotic:       chance = 0.25
            case .balanced:     chance = 0.15
            case .conservative: chance = 0.08
            }
            guard Double.random(in: 0..<1) < chance else { return nil }
            let text = "Audible — \(opponentAbbreviation) rotates the shell at the line"
            postFeedNote(text)
            return text
        } else {
            guard pendingOffenseCounter != nil else { return nil }
            guard Double.random(in: 0..<1) < 0.20 else { return nil }
            let qbName = (playerTeamIsHome ? awayOffenseUnit : homeOffenseUnit)[0].shortName
            let text = "Audible — \(qbName) changes the call at the line"
            postFeedNote(text)
            return text
        }
    }

    // MARK: - Coordinator Recommendations (#26, live only, presentation)
    //
    // The PLAYER's own OC/DC pre-select a call on the sheet and explain it in
    // a speech bubble. The recommendation reuses the SAME situational logic
    // the auto-sim leans on (run/pass by down & distance + scheme + game plan
    // + weather, mirroring `PlaySimulator.decidePlayCall`; the defense mirrors
    // `baseDefensivePackage`), resolved DETERMINISTICALLY — no live RNG — so a
    // given situation always yields the same call and the bubble text always
    // matches the highlighted card. Coordinator quality shades the read:
    // a sharp (high grade / scheme-fit persona) coordinator gives a specific,
    // film-room reason and higher confidence; a weak one stays generic. The
    // player's own play-calling is never forced — this only pre-selects.

    /// How strongly the coordinator backs his pick — drives the small pip in
    /// the bubble. `.high` reads on a clear spot with a sharp coordinator.
    enum RecommendationConfidence: Int, Comparable {
        case low = 1, medium = 2, high = 3
        static func < (l: RecommendationConfidence, r: RecommendationConfidence) -> Bool {
            l.rawValue < r.rawValue
        }
        /// Filled pips out of three.
        var pips: Int { rawValue }
    }

    /// The offensive coordinator's pre-snap recommendation. `reason` is
    /// English-only by design (coach-speak); the UI chrome around it localizes.
    struct OffensiveRecommendation: Equatable {
        let call: OffensivePlayCall
        let reason: String
        let coordinatorName: String
        let confidence: RecommendationConfidence
    }

    /// The defensive coordinator's pre-snap recommendation (English `reason`).
    struct DefensiveRecommendation: Equatable {
        let call: DefensiveCall
        let reason: String
        let coordinatorName: String
        let confidence: RecommendationConfidence
    }

    /// Immutable snapshot of the decision context a recommendation reasons
    /// over. Built from live state by ``currentSituation`` so the recommend
    /// methods stay deterministic and unit-testable.
    struct CoordinatorSituation: Equatable {
        let down: Int
        let distance: Int
        /// Yards from the possessing team's own goal line (0–100).
        let yardLine: Int
        let quarter: Int
        let timeRemaining: Int
        /// Score margin from the PLAYER's perspective (+ = leading).
        let scoreMargin: Int
        let weather: GameWeather?

        var yardsToEndzone: Int { 100 - yardLine }
        var isGoalToGo: Bool { yardsToEndzone <= distance }
        var isRedZone: Bool { yardsToEndzone <= 20 }
        var isBackedUp: Bool { yardLine <= 12 }
        var isShortYardage: Bool { distance <= 2 }
        var isLongYardage: Bool { distance >= 8 }
        var isFourthDown: Bool { down == 4 }
        /// Final two minutes of a half.
        var isTwoMinute: Bool { (quarter == 2 || quarter >= 4) && timeRemaining <= 120 }
        var isLate: Bool { quarter >= 4 && timeRemaining <= 300 }
        var trailing: Bool { scoreMargin < 0 }
        var leading: Bool { scoreMargin > 0 }
    }

    /// Live decision context for the recommendation engine.
    var currentSituation: CoordinatorSituation {
        CoordinatorSituation(
            down: down, distance: distance, yardLine: yardLine,
            quarter: quarter, timeRemaining: timeRemaining,
            scoreMargin: playerScoreMargin, weather: weather
        )
    }

    /// Player-team score minus opponent score.
    var playerScoreMargin: Int {
        (playerTeamIsHome ? homeScore : awayScore) - (playerTeamIsHome ? awayScore : homeScore)
    }

    /// The opponent offense's recent run/pass lean, or `nil` until it has
    /// shown a few snaps. `true` = run-leaning, `false` = pass-leaning.
    private var opponentRunLean: Bool? {
        let recent = Array(opponentPlayTypes.suffix(4))
        guard recent.count >= 3 else { return nil }
        let runs = recent.filter { $0 == .run }.count
        if runs >= 3 { return true }
        if recent.count - runs >= 3 { return false }
        return nil
    }

    // MARK: Offensive recommendation

    /// The offensive coordinator's deterministic pre-snap recommendation. See
    /// the section header for the reuse/determinism contract.
    func recommendedOffensiveCall(_ s: CoordinatorSituation) -> OffensiveRecommendation {
        let persona = playerOCPersona
        let grade = playerOCGrade

        // --- Run vs pass lean (mirrors decidePlayCall, resolved at 0.5) ---
        var passLean: Double
        if s.isTwoMinute && (s.trailing || s.scoreMargin == 0) {
            passLean = 0.88
        } else {
            switch s.down {
            case 1: passLean = 0.52
            case 2: passLean = s.distance >= 7 ? 0.66 : 0.48
            case 3, 4:
                if s.distance <= 2 { passLean = 0.42 }
                else if s.distance >= 7 { passLean = 0.82 }
                else { passLean = 0.64 }
            default: passLean = 0.5
            }
        }
        passLean += offensiveSchemePassBias(playerOffensiveScheme)
        passLean += ((playerGamePlan?.runPassRatio ?? 0.5) - 0.5) * 0.3   // R12 game plan
        switch s.weather {
        case .snow: passLean -= 0.08
        case .wind: passLean -= 0.05
        case .rain: passLean -= 0.03
        default: break
        }
        // Protecting a late lead on a manageable down: bleed clock on the run.
        if s.isLate && s.leading && !s.isLongYardage { passLean -= 0.12 }
        // Backed up against our own goal: favor the safe, ball-secure call.
        if s.isBackedUp && !s.isTwoMinute { passLean -= 0.10 }
        var wantsPass = passLean >= 0.5

        // --- Counter the AI defense's read (a sharp OC earns this) ---
        var counteredRead: AdaptiveOpponentAI.OffenseTendency? = nil
        var preferPlayAction = false
        if grade >= 62, let read = activeDefenseRead {
            counteredRead = read
            switch read {
            case .insideRun, .outsideRun:
                wantsPass = true; preferPlayAction = true       // shot off the run key
            case .screen:
                wantsPass = true                                 // go over the top
            case .shortPass, .mediumPass, .deepPass, .playAction:
                wantsPass = false                                // they sit on the pass — run it
            }
        }

        let call: OffensivePlayCall = wantsPass
            ? recommendedPassCall(s, persona: persona, playAction: preferPlayAction)
            : recommendedRunCall(s, persona: persona)

        // Clarity of the spot governs the confidence pip.
        let clear = s.isFourthDown || (s.down == 3 && s.isLongYardage)
            || s.isShortYardage || s.isTwoMinute || s.isRedZone || s.isBackedUp
            || (s.isLate && s.leading)
        let confidence: RecommendationConfidence
        if grade < 50 { confidence = .low }
        else if clear || counteredRead != nil { confidence = grade >= 62 ? .high : .medium }
        else { confidence = grade >= 60 ? .medium : .low }

        return OffensiveRecommendation(
            call: call,
            reason: offenseReason(s, persona: persona, wantsPass: wantsPass,
                                  counteredRead: counteredRead, grade: grade),
            coordinatorName: playerOCName,
            confidence: confidence
        )
    }

    /// Pass-probability bias per scheme — same weights as `decidePlayCall`.
    private func offensiveSchemePassBias(_ scheme: OffensiveScheme?) -> Double {
        switch scheme {
        case .airRaid:    return 0.15
        case .proPassing: return 0.10
        case .westCoast:  return 0.08
        case .spread:     return 0.05
        case .rpo:        return 0.0
        case .shanahan:   return -0.10
        case .option:     return -0.12
        case .powerRun:   return -0.15
        case nil:         return 0.0
        }
    }

    /// Deterministic run pick: first installed play off the persona's ordered
    /// preference for the situation (short yardage / goal line come first).
    private func recommendedRunCall(_ s: CoordinatorSituation, persona: OCPersona) -> OffensivePlayCall {
        if s.distance <= 1 || (s.isGoalToGo && s.yardsToEndzone <= 2) {
            for c: OffensivePlayCall in [.qbSneak, .dive, .insideRun] where playerHasInstalled(c) { return c }
        }
        let order: [OffensivePlayCall]
        switch persona {
        case .groundAndPound: order = [.insideRun, .counter, .toss, .outsideRun, .dive, .draw]
        case .airRaid:        order = [.draw, .screen, .insideRun, .toss]
        case .westCoast:      order = [.outsideRun, .toss, .insideRun, .screen, .counter]
        case .balanced:       order = [.insideRun, .outsideRun, .counter, .toss, .draw]
        }
        for c in order where playerHasInstalled(c) { return c }
        return firstInstalledOffense(category: "Run") ?? .insideRun
    }

    /// Deterministic pass pick: depth from distance/field, persona-ordered.
    /// Never a deep shot inside the red zone (collapses to a timing throw).
    private func recommendedPassCall(_ s: CoordinatorSituation, persona: OCPersona, playAction: Bool) -> OffensivePlayCall {
        if playAction, s.yardsToEndzone >= 22, playerHasInstalled(.playActionDeep) {
            return .playActionDeep
        }
        var depth: Int  // 0 short, 1 medium, 2 deep
        if s.distance <= 4 { depth = 0 } else if s.distance <= 9 { depth = 1 } else { depth = 2 }
        if s.isRedZone { depth = 0 }                       // no verticals near the goal
        if s.isBackedUp { depth = 0 }                      // protect the ball in our own end
        if s.isTwoMinute { depth = min(depth, 1) }         // move the ball, not a bomb
        let order: [OffensivePlayCall]
        switch (persona, depth) {
        case (.airRaid, 0):        order = [.slant, .mesh, .stick, .quickOut]
        case (.airRaid, 1):        order = [.seam, .dig, .cross, .curl]
        case (.airRaid, _):        order = [.post, .corner, .goRoute, .flood]
        case (.westCoast, 0):      order = [.slant, .quickOut, .drag, .stick, .flat, .hitch]
        case (.westCoast, 1):      order = [.curl, .drag, .dig, .stick]
        case (.westCoast, _):      order = [.corner, .post, .flood, .goRoute]
        case (.groundAndPound, 0): order = [.slant, .stick, .flat, .quickOut]
        case (.groundAndPound, 1): order = [.dig, .curl, .drag]
        case (.groundAndPound, _): order = [.post, .corner, .goRoute]
        case (_, 0):               order = [.slant, .quickOut, .hitch, .stick]
        case (_, 1):               order = [.curl, .dig, .comeback, .seam]
        default:                   order = [.post, .corner, .goRoute, .flood]
        }
        for c in order where playerHasInstalled(c) { return c }
        let cat = depth == 0 ? "Short Pass" : (depth == 1 ? "Medium Pass" : "Deep Pass")
        return firstInstalledOffense(category: cat)
            ?? OffensivePlayCall.allCases.first { $0.isPass && $0 != .spike && playerHasInstalled($0) }
            ?? .slant
    }

    private func firstInstalledOffense(category: String) -> OffensivePlayCall? {
        OffensivePlayCall.allCases.first { $0.category == category && playerHasInstalled($0) }
    }

    private func downLabel(_ d: Int) -> String {
        switch d { case 1: return "1st"; case 2: return "2nd"; case 3: return "3rd"; default: return "4th" }
    }

    /// One-line OC reasoning, sharpening with coordinator grade.
    private func offenseReason(
        _ s: CoordinatorSituation, persona: OCPersona,
        wantsPass: Bool, counteredRead: AdaptiveOpponentAI.OffenseTendency?, grade: Int
    ) -> String {
        // Weak staff: gist only, no film-room detail.
        guard grade >= 52 else {
            return wantsPass ? "Let's throw it here and move the chains."
                             : "Keep it on the ground and stay on schedule."
        }
        let sharp = grade >= 68

        // 1) Countering the AI defense's read (the sharpest read there is).
        if let read = counteredRead {
            switch read {
            case .insideRun, .outsideRun:
                return "They've loaded the box on our run — hit them with play-action off it."
            case .screen:
                return "They're jumping our screens — take the top off with a shot downfield."
            case .shortPass, .mediumPass, .deepPass, .playAction:
                return "They're sitting on the pass — hand it off and make them tackle."
            }
        }

        // 2) Situation lines.
        if s.isFourthDown {
            return wantsPass
                ? "4th & \(s.distance) — we're going for it, take the sure completion at the sticks."
                : "4th & \(s.distance) — lean on the big people and go get it."
        }
        if s.isTwoMinute && (s.trailing || s.scoreMargin == 0) {
            return "Two-minute drill — quick game to move the chains and manage the clock."
        }
        if s.isLate && s.leading && !wantsPass {
            return "We're ahead late — bleed the clock, keep it on the ground and make them use timeouts."
        }
        if s.down == 3 && s.isLongYardage {
            let tail = sharp && persona == .airRaid ? " Let it rip."
                : (sharp ? " Get it out before their rush gets home." : "")
            return "3rd & long — protect the QB and throw past the sticks.\(tail)"
        }
        if (s.down == 3 || s.down == 2) && s.isShortYardage {
            return "\(downLabel(s.down)) & \(s.distance) — short yardage, lean on them and move the chains."
        }
        if s.isRedZone {
            return wantsPass
                ? "Red zone — tight windows, take the high-percentage throw and live for the next down."
                : "Red zone — pound it in behind our front, no wasted motion."
        }
        if s.isBackedUp {
            return "Backed up on our own goal — safe call, protect the football, no short field for them."
        }
        if let w = s.weather, (w == .snow || w == .wind), !wantsPass {
            return "\(w == .snow ? "Snow's" : "Wind's") a factor — keep it on the ground and stay sound."
        }

        // 3) Persona-flavored default.
        if sharp {
            switch persona {
            case .airRaid:
                return wantsPass ? "Let's push the ball down the field and stress their coverage."
                                 : "Even the Air Raid runs it here to keep them honest."
            case .westCoast:
                return wantsPass ? "Rhythm throw on time — take the easy completion, stay on schedule."
                                 : "Get the back to the edge and let him work in space."
            case .groundAndPound:
                return wantsPass ? "Play off the run — they're crowding the box, make them pay over the top."
                                 : "Downhill run — this is our football, wear them down."
            case .balanced:
                return wantsPass ? "Take what the coverage gives — clean throw, stay ahead of the chains."
                                 : "Sound run to stay on schedule."
            }
        }
        return wantsPass ? "Good down to throw — stay on schedule."
                         : "Run it here and keep us on schedule."
    }

    // MARK: Defensive recommendation

    /// The defensive coordinator's deterministic pre-snap recommendation.
    /// Mirrors `baseDefensivePackage`'s situational branches as a NAMED call,
    /// shaded by the DC persona and the opponent's recent run/pass lean.
    func recommendedDefensiveCall(_ s: CoordinatorSituation) -> DefensiveRecommendation {
        let persona = playerDCPersona
        let grade = playerDCGrade
        var call = baseDefensiveRecommendation(s)
        call = shadeDefensiveRecommendation(call, s: s, persona: persona, grade: grade)
        call = installedDefensiveEquivalent(call)

        let clear = s.yardsToEndzone <= 10 || (s.down == 3 && s.distance >= 7)
            || s.distance <= 2 || call == .prevent
            || (grade >= 60 && opponentRunLean != nil)
        let confidence: RecommendationConfidence
        if grade < 50 { confidence = .low }
        else if clear { confidence = grade >= 62 ? .high : .medium }
        else { confidence = grade >= 60 ? .medium : .low }

        return DefensiveRecommendation(
            call: call,
            reason: defenseReason(s, persona: persona, call: call, grade: grade),
            coordinatorName: playerDCName,
            confidence: confidence
        )
    }

    /// Situational base call (mirrors `baseDefensivePackage`'s branch order).
    private func baseDefensiveRecommendation(_ s: CoordinatorSituation) -> DefensiveCall {
        if s.yardsToEndzone <= 10 { return .goalLineD }
        if s.isLate && s.leading && s.scoreMargin <= 16 && s.yardsToEndzone > 25 { return .prevent }
        if s.down == 3 && s.distance >= 7 { return .dimePackage }
        if s.distance <= 2 { return .bearFront }
        return .cover3Base
    }

    /// Persona + opponent-tendency shading (deterministic — no live RNG).
    /// Never overrides the goal-line sellout or the late-lead prevent shell.
    private func shadeDefensiveRecommendation(
        _ base: DefensiveCall, s: CoordinatorSituation, persona: DCPersona, grade: Int
    ) -> DefensiveCall {
        if base == .goalLineD || base == .prevent { return base }
        // A sharp DC that has read the opponent's lean adjusts the front.
        if grade >= 60, let runLean = opponentRunLean {
            if runLean, s.distance <= 6, base != .bearFront {
                return persona == .aggressive ? .doubleAGap : .bearFront
            }
            if !runLean, s.distance >= 5 {
                return persona == .conservative ? .cover2Shell
                    : (persona == .aggressive ? .cornerBlitz : .nickelPackage)
            }
        }
        switch persona {
        case .aggressive:
            if base == .dimePackage { return .cornerBlitz }
            if base == .cover3Base  { return s.distance >= 5 ? .lbFire : .manPress }
            if base == .bearFront   { return .doubleAGap }
            return base
        case .conservative:
            if base == .dimePackage { return .quarters }
            if base == .cover3Base  { return .cover2Shell }
            return base
        case .exotic:
            if base == .dimePackage { return .zoneBlitz }
            if base == .cover3Base  { return s.distance >= 5 ? .zoneBlitz : .cover3Base }
            if base == .bearFront   { return .doubleAGap }
            return base
        case .balanced:
            return base
        }
    }

    /// Keep the recommended call inside the coached team's playbook, preserving
    /// its INTENT: a scheme that lacks the ideal call still gets a sound one of
    /// the same character (a run-stop for a run-stop, extra DBs for extra DBs)
    /// rather than a generic zone. Cover 3 is installed by every scheme, so the
    /// chain always resolves.
    private func installedDefensiveEquivalent(_ call: DefensiveCall) -> DefensiveCall {
        for candidate in defensiveFallbackChain(for: call)
        where candidate.isInPlaybook(of: playerDefensiveScheme) {
            return candidate
        }
        return .cover3Base
    }

    /// Intent-preserving fallback order (most-preferred first, always ending at
    /// the universally installed Cover 3).
    private func defensiveFallbackChain(for call: DefensiveCall) -> [DefensiveCall] {
        switch call {
        case .bearFront:     return [.bearFront, .goalLineD, .cover1, .cover3Base]
        case .goalLineD:     return [.goalLineD, .bearFront, .cover1, .cover3Base]
        case .doubleAGap:    return [.doubleAGap, .lbFire, .cornerBlitz, .safetyBlitz, .cover1, .cover3Base]
        case .lbFire:        return [.lbFire, .zoneBlitz, .doubleAGap, .cornerBlitz, .cover3Base]
        case .cornerBlitz:   return [.cornerBlitz, .safetyBlitz, .lbFire, .manPress, .cover3Base]
        case .zoneBlitz:     return [.zoneBlitz, .lbFire, .cover2Shell, .cover3Base]
        case .manPress:      return [.manPress, .manFree, .cover1, .cover3Base]
        case .cover2Shell:   return [.cover2Shell, .quarters, .cover3Base]
        case .quarters:      return [.quarters, .cover4Match, .cover2Shell, .dimePackage, .cover3Base]
        case .dimePackage:   return [.dimePackage, .nickelPackage, .quarters, .cover4Match, .cover3Base]
        case .nickelPackage: return [.nickelPackage, .dimePackage, .cover3Base]
        case .prevent:       return [.prevent, .quarters, .cover4Match, .cover2Shell, .cover3Base]
        default:             return [call, .cover3Base]
        }
    }

    /// One-line DC reasoning, sharpening with coordinator grade.
    private func defenseReason(
        _ s: CoordinatorSituation, persona: DCPersona, call: DefensiveCall, grade: Int
    ) -> String {
        guard grade >= 52 else {
            return "Line up sound and rally to the ball."
        }
        let sharp = grade >= 68

        // Read the opponent's tendency first (a sharp DC earns this).
        if grade >= 60, let runLean = opponentRunLean {
            if runLean, s.distance <= 6 {
                return "They've leaned on the run — load the box and make them throw it."
            }
            if !runLean, s.distance >= 5 {
                return persona == .aggressive
                    ? "They've been throwing it — bring pressure and make the QB uncomfortable."
                    : "They've been throwing it — drop an extra DB and take away the windows."
            }
        }
        if call == .goalLineD || s.yardsToEndzone <= 10 {
            return "Goal line — stack the front, sell out to stop the run, no easy walk-in."
        }
        if call == .prevent {
            return "Protecting the lead — keep everything in front, never give up the big one."
        }
        if s.down == 3 && s.distance >= 7 {
            let tail = sharp && persona == .aggressive ? " Send the house."
                : (sharp ? " Get after the passer." : "")
            return "3rd & long — they have to throw, squeeze the sticks and rally up.\(tail)"
        }
        if s.distance <= 2 {
            return "Short yardage — crowd the line, this is where we stone the run."
        }
        if sharp {
            switch persona {
            case .aggressive:   return "Bring the heat — put their protection on its heels."
            case .conservative: return "Play it sound — keep it in front and tackle well."
            case .exotic:       return "Give them a look they haven't seen — disguise it, rotate late."
            case .balanced:     return "Sound call for the down — force them to earn it."
            }
        }
        return "Sound defense for the down — make them drive the length of the field."
    }

    /// "S. McVay" — coordinator name for the recommendation bubble.
    private static func coordShortName(_ coach: Coach) -> String {
        let initial = coach.firstName.first.map { "\($0). " } ?? ""
        return initial + coach.lastName
    }

    /// Publishes an adaptation intel line (overlay + mini feed), at most one
    /// per ~2 minutes of game time so the broadcast never spams.
    private func emitAdaptationHint(_ text: String) {
        let now = elapsedGameSeconds
        if let last = lastHintGameSecond, now - last < LiveGameEngine.hintCooldownSeconds {
            return
        }
        lastHintGameSecond = now
        lastAdaptationHint = AdaptationHint(text: text)
        // Feed-only line for the broadcast ticker — same mechanism as the
        // substitution notes: playLog only, never the drive/stats.
        postFeedNote(text)
    }

    /// Appends a feed-only line to the broadcast ticker (playNumber 0 —
    /// never part of any drive, the stats, or the clock), e.g. the play
    /// clock's "Delay — J. Love checks into Inside Run". Same mechanism as
    /// the substitution/intel notes; UI-triggered only, so nil-argument
    /// parity with `GameSimulator.simulate` is untouched.
    func postFeedNote(_ text: String) {
        playLog.append(PlayResult(
            playNumber: 0,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .kneel,
            outcome: .kneel,
            yardsGained: 0,
            description: text,
            isFirstDown: false,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0
        ))
    }

    /// Absolute game seconds elapsed (Q1 kickoff = 0). Close enough in OT
    /// for hint rate-limiting purposes.
    private var elapsedGameSeconds: Int {
        let quarterLen = GameSimulator.quarterDuration
        let intoQuarter = quarterLen - max(0, min(quarterLen, timeRemaining))
        return (min(quarter, 5) - 1) * quarterLen + intoQuarter
    }

    // MARK: - Auto-Sim

    /// Runs AI-vs-AI plays until the game ends (capped at 500 plays as a safety).
    func simToEnd() {
        var playCount = 0
        while !isGameOver && playCount < 500 {
            _ = step()
            playCount += 1
        }
        if !isGameOver {
            isGameOver = true // hard safety cap — should never trigger in practice
        }
        // A sim-to-final blows straight through the break — never leave a
        // stale halftime flag for the view to trip on.
        halftimePending = false
    }

    // MARK: - Result & Persistence

    /// Assembles the final ``GameSimulator/GameResult`` (box score, player
    /// stats, MVP) and writes accumulated fatigue back to the live `Player`
    /// models, exactly like `GameSimulator.simulate` does at game end.
    func buildResult() -> GameSimulator.GameResult {
        GameSimulator.finalizeGameResult(
            homeTeamID: homeTeamID,
            awayTeamID: awayTeamID,
            homeScore: homeScore,
            awayScore: awayScore,
            homeQuarterScores: homeQuarterScores,
            awayQuarterScores: awayQuarterScores,
            drives: allDrives,
            highlights: allHighlights,
            homeTimeOfPossession: homeTimeOfPossession,
            awayTimeOfPossession: awayTimeOfPossession,
            statsAccumulator: statsAccumulator,
            homePlayers: homePlayers,
            awayPlayers: awayPlayers,
            livePlayerByID: livePlayerByID
        )
    }

    /// Writes the final score to the `Game`, updates both teams' records, and
    /// stores the result in `WeekAdvancer.lastPlayerGameResult` so the weekly
    /// press conference / recap UI can pick it up after `advanceWeek`.
    ///
    /// Also writes any live-game injuries back to the SwiftData players with
    /// the exact mechanism the weekly sim uses (`MedicalEngine.applyInjury`),
    /// and registers both teams so `WeekAdvancer` skips their weekly injury
    /// roll this advance — the live game already rolled those dice play by
    /// play, at the same aggregate probability.
    func persist(to game: Game, context: ModelContext, teamsByID: [UUID: Team]) {
        let result = buildResult()
        game.homeScore = result.homeScore
        game.awayScore = result.awayScore
        WeekAdvancer.updateTeamRecords(game: game, teamsByID: teamsByID)
        WeekAdvancer.lastPlayerGameResult = result

        // Matchup-driven morale: the player's best battle winners come out of
        // a coached game buoyed; players who kept losing their one-on-ones
        // take a small hit. Player's team only — the AI opponent (and every
        // quick-simmed team) is untouched.
        applyMatchupMorale()

        for injury in gameInjuries {
            guard let livePlayer = livePlayerByID[injury.playerID], !livePlayer.isInjured else { continue }
            MedicalEngine.applyInjury(
                player: livePlayer,
                injuryType: injury.type,
                doctor: injury.isHomeTeam ? homeDoctor : awayDoctor,
                physio: injury.isHomeTeam ? homePhysio : awayPhysio
            )
        }
        WeekAdvancer.liveGameInjuryTeamIDs = [homeTeamID, awayTeamID]

        try? context.save()
    }

    /// R18: end-of-game morale write-back from the individual matchup tallies
    /// (see ``matchupWins``/``matchupLosses``). The top-3 battle winners on
    /// the PLAYER's team gain +3 morale (clamped 1...100, same bounds as
    /// `LockerRoomEngine`); teammates who collected 2+ battle losses without
    /// at least as many wins lose 1. `PlayerDevelopmentEngine` exposes no
    /// per-game XP tick (`applyGameExperience` rounds to zero for a single
    /// game), so morale is the whole effect. Called once from ``persist``,
    /// which only runs for the user's own coached games.
    private func applyMatchupMorale() {
        let playerIDs = Set(playerTeamIsHome ? homePlayerIDs : awayPlayerIDs)

        let winners = matchupWins
            .filter { playerIDs.contains($0.key) && $0.value > 0 }
            .map { (id: $0.key, wins: $0.value, losses: matchupLosses[$0.key] ?? 0) }
            .sorted { ($0.wins, $1.losses) > ($1.wins, $0.losses) }
            .prefix(3)

        var boosted: Set<UUID> = []
        for winner in winners {
            guard let live = livePlayerByID[winner.id] else { continue }
            live.morale = max(1, min(100, live.morale + 3))
            boosted.insert(winner.id)
        }

        for id in playerIDs where !boosted.contains(id) {
            let losses = matchupLosses[id] ?? 0
            let wins = matchupWins[id] ?? 0
            guard losses >= 2, losses > wins, let live = livePlayerByID[id] else { continue }
            live.morale = max(1, min(100, live.morale - 1))
        }
    }

    // MARK: - Injuries & Rotation (private)

    /// Roster minus everyone sidelined (injured or resting). Falls back to
    /// the full roster if exclusions would leave fewer than 11 players.
    private func availablePlayers(isHome: Bool) -> [SimPlayer] {
        let roster = isHome ? homePlayers : awayPlayers
        let sidelined = sidelinedIDs
        guard !sidelined.isEmpty else { return roster }
        let filtered = roster.filter { !sidelined.contains($0.id) }
        return filtered.count >= 11 ? filtered : roster
    }

    /// The roster slice handed to the play simulator: available players minus
    /// any bench players shadowed by a manual substitution (player team only)
    /// — keeps the sim's best-at-position picks aligned with the field units.
    /// Identical to ``availablePlayers(isHome:)`` when no manual sub is active.
    private func simAvailablePlayers(isHome: Bool) -> [SimPlayer] {
        let base = availablePlayers(isHome: isHome)
        guard isHome == playerTeamIsHome, !overrideShadowedIDs.isEmpty else { return base }
        let filtered = base.filter { !overrideShadowedIDs.contains($0.id) }
        return filtered.count >= 11 ? filtered : base
    }

    /// Rebuilds all four field units from the current available rosters —
    /// the same best-at-position pick used at kickoff, so an injured or
    /// resting starter is replaced by the next-best player at his spot —
    /// then re-applies the coach's manual substitutions to the player's units.
    private func rebuildFieldUnits() {
        let home = availablePlayers(isHome: true)
        let away = availablePlayers(isHome: false)
        var homeOff = FieldUnit.offense(from: home)
        var homeDef = FieldUnit.defense(from: home)
        var awayOff = FieldUnit.offense(from: away)
        var awayDef = FieldUnit.defense(from: away)
        if playerTeamIsHome {
            homeOff = applyingManualOverrides(to: homeOff, overrides: &manualOffenseOverrides, roster: home)
            homeDef = applyingManualOverrides(to: homeDef, overrides: &manualDefenseOverrides, roster: home)
        } else {
            awayOff = applyingManualOverrides(to: awayOff, overrides: &manualOffenseOverrides, roster: away)
            awayDef = applyingManualOverrides(to: awayDef, overrides: &manualDefenseOverrides, roster: away)
        }
        homeOffenseUnit = homeOff
        homeDefenseUnit = homeDef
        awayOffenseUnit = awayOff
        awayDefenseUnit = awayDef
        refreshOverrideShadow()
    }

    // MARK: - In-Game Management (private)

    /// Realizes queued substitutions at the dead ball after a completed play:
    /// drops any overtaken by events (the man already left injured, or the
    /// entrant got hurt), swaps the rest into the field units through the
    /// standard rebuild, and posts a feed line per swap.
    private func applyPendingSubstitutions() {
        guard !pendingSubstitutions.isEmpty else { return }
        guard !isGameOver else {
            pendingSubstitutions = []
            return
        }
        var applied = false
        for sub in pendingSubstitutions {
            guard !injuredPlayerIDs.contains(sub.benchPlayerID) else { continue }
            let unit = sub.isOffenseUnit ? playerOffenseUnit : playerDefenseUnit
            guard let role = unit.role(of: sub.fieldPlayerID) else { continue }
            manuallyBenchedIDs.remove(sub.benchPlayerID)
            manuallyBenchedIDs.insert(sub.fieldPlayerID)
            if sub.isOffenseUnit {
                manualOffenseOverrides[role] = sub.benchPlayerID
            } else {
                manualDefenseOverrides[role] = sub.benchPlayerID
            }
            appendSubstitutionFeedLine(inName: sub.benchName, outName: sub.fieldName)
            applied = true
        }
        pendingSubstitutions = []
        if applied { rebuildFieldUnits() }
    }

    /// Swaps the coach's hand-picked starters into their role slots after an
    /// automatic rebuild. Overrides whose player is hurt (or gone) are
    /// dropped — the rebuild's best-at-position pick already filled the hole,
    /// so the FieldUnit stays the single source of truth for who is on field.
    private func applyingManualOverrides(
        to unit: FieldUnit,
        overrides: inout [Int: UUID],
        roster: [SimPlayer]
    ) -> FieldUnit {
        guard !overrides.isEmpty else { return unit }
        var players = unit.players
        for (role, playerID) in overrides {
            guard players.indices.contains(role),
                  !injuredPlayerIDs.contains(playerID),
                  let player = roster.first(where: { $0.id == playerID }) else {
                overrides[role] = nil
                continue
            }
            if let existing = players.firstIndex(where: { $0.id == playerID }) {
                // The auto-build already fielded him elsewhere: swap so he
                // mans the coach's chosen slot instead of appearing twice.
                if existing != role { players.swapAt(existing, role) }
            } else {
                players[role] = player
            }
        }
        return FieldUnit(players: players)
    }

    /// Recomputes ``overrideShadowedIDs`` from the active manual overrides:
    /// every player-team bench player in a manually-managed position group.
    private func refreshOverrideShadow() {
        overrideShadowedIDs = []
        guard !manualOffenseOverrides.isEmpty || !manualDefenseOverrides.isEmpty else { return }
        let roster = playerTeamIsHome ? homePlayers : awayPlayers
        let overrideIDs = Set(manualOffenseOverrides.values).union(manualDefenseOverrides.values)
        let managedGroups = Set(
            roster.filter { overrideIDs.contains($0.id) }.map { LineupGroup(of: $0.position) }
        )
        guard !managedGroups.isEmpty else { return }
        var onField = Set(playerOffenseUnit.players.map(\.id))
        onField.formUnion(playerDefenseUnit.players.map(\.id))
        overrideShadowedIDs = Set(
            roster
                .filter { managedGroups.contains(LineupGroup(of: $0.position)) && !onField.contains($0.id) }
                .map(\.id)
        )
    }

    /// Frees manually benched players when injuries leave nobody else healthy
    /// at their position — a bench order can't strand a unit shorthanded
    /// (same safety valve as the resting RB's forced re-entry).
    private func releaseManualBenchIfNeeded() {
        guard !manuallyBenchedIDs.isEmpty else { return }
        let roster = playerTeamIsHome ? homePlayers : awayPlayers
        for benchedID in Array(manuallyBenchedIDs) {
            guard let benched = roster.first(where: { $0.id == benchedID }) else { continue }
            let hasHealthyAlternative = roster.contains {
                $0.id != benchedID
                    && $0.position == benched.position
                    && !injuredPlayerIDs.contains($0.id)
            }
            if !hasHealthyAlternative { manuallyBenchedIDs.remove(benchedID) }
        }
    }

    /// Feed-only line ("Sub: X in for Y"): appended to the play log for the
    /// mini feed, never to the drive — no effect on stats or the box score.
    private func appendSubstitutionFeedLine(inName: String, outName: String) {
        playLog.append(PlayResult(
            playNumber: 0,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .kneel,
            outcome: .kneel,
            yardsGained: 0,
            description: "Sub: \(inName) in for \(outName)",
            isFirstDown: false,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0
        ))
    }

    /// Rolls injury dice for the play's contact participants: the ball
    /// carrier (rusher, receiver, or sacked QB) and one tackler.
    ///
    /// This replaces the quick sim's weekly injury roll for both live teams
    /// (`WeekAdvancer` skips them via `liveGameInjuryTeamIDs`), at the same
    /// aggregate probability — live coaching never costs extra injuries.
    private func rollInjuries(for play: PlayResult) {
        guard play.playType == .pass || play.playType == .run else { return }

        // Contact plays only. Touchdowns injure the carrier at most (nobody
        // made the tackle); incompletions/penalties/kneels are contact-free.
        let carrierContact: Bool
        var tacklerRole: Int?
        switch play.outcome {
        case .rush, .fumble, .fumbleLost, .safety:
            carrierContact = true
            tacklerRole = Int.random(in: 0...6) // front seven brings him down
        case .sack:
            carrierContact = true
            tacklerRole = Int.random(in: 0...3)
        case .completion:
            carrierContact = true
            tacklerRole = Int.random(in: 4...10)
        case .touchdown:
            carrierContact = true
            tacklerRole = nil
        default:
            carrierContact = false
            tacklerRole = nil
        }
        guard carrierContact else { return }

        let offenseIsHome = homeHasPossession
        let offenseUnit = currentOffenseUnit
        let defenseUnit = currentDefenseUnit

        if let carrierID = play.keyOffensePlayerID {
            checkInjury(
                playerID: carrierID,
                unitRole: offenseUnit.role(of: carrierID),
                isHomeTeam: offenseIsHome
            )
        }
        if let tacklerRole {
            checkInjury(
                playerID: defenseUnit[tacklerRole].id,
                unitRole: tacklerRole,
                isHomeTeam: !offenseIsHome
            )
        }
    }

    /// One involvement's injury check — same modifier shape as
    /// `MedicalEngine.injuryCheck` (fatigue, durability, team doctor), scaled
    /// to per-play size. On a hit: the player is pulled from the sim and his
    /// field unit, and the event is published for the view.
    private func checkInjury(playerID: UUID, unitRole: Int?, isHomeTeam: Bool) {
        guard !injuredPlayerIDs.contains(playerID) else { return }
        let roster = isHomeTeam ? homePlayers : awayPlayers
        guard let player = roster.first(where: { $0.id == playerID }) else { return }
        // Never bench a team below a full 11 (absurd-roster safety valve).
        let teamInjured = roster.reduce(0) { $0 + (injuredPlayerIDs.contains($1.id) ? 1 : 0) }
        guard roster.count - teamInjured > 12 else { return }

        var risk = LiveGameEngine.perPlayInjuryRisk
        risk *= 1.0 + Double(max(0, player.fatigue - 50)) / 50.0
        risk *= 1.0 - Double(player.physical.durability) / 200.0
        if let doctor = isHomeTeam ? homeDoctor : awayDoctor {
            risk *= 1.0 - Double(doctor.playerDevelopment) / 330.0
        }
        guard Double.random(in: 0...1) < risk else { return }

        let injuryType = InjuryType.allCases.randomElement()!
        injuredPlayerIDs.insert(playerID)
        gameInjuries.append((playerID: playerID, type: injuryType, isHomeTeam: isHomeTeam))

        // Node contract: home figures 0–10, away 11–21, role-ordered.
        let nodeIndex = unitRole.map { (isHomeTeam ? 0 : 11) + $0 }
        lastPlayInjuries.append(LiveInjuryEvent(
            playerID: playerID,
            playerName: player.shortName,
            position: player.position.rawValue,
            isHomeTeam: isHomeTeam,
            nodeIndex: nodeIndex,
            injuryType: injuryType
        ))

        // If the resting RB is the only body left at his spot, he re-enters.
        if restingRBID != nil {
            let healthyRBs = (playerTeamIsHome ? homePlayers : awayPlayers)
                .filter { $0.position == .RB && !injuredPlayerIDs.contains($0.id) }
            if healthyRBs.count < 2 { restingRBID = nil }
        }
        // Same safety for coach-ordered benchings: the last healthy man at a
        // position cannot stay benched.
        releaseManualBenchIfNeeded()
        rebuildFieldUnits()
    }

    /// Fatigue rotation, player's team only (an AI game must stay identical
    /// to the quick sim): once the starting RB crosses the fatigue threshold
    /// and a meaningfully fresher backup exists, the backup takes the next
    /// drive; the starter returns when he is the fresher option again
    /// (e.g. after halftime recovery).
    private func updateRBRotation() {
        // Once the coach has manually subbed the RB slot he runs the
        // backfield himself — the auto-rotation stands down.
        guard manualOffenseOverrides[1] == nil else {
            if restingRBID != nil { restingRBID = nil }
            return
        }
        let roster = playerTeamIsHome ? homePlayers : awayPlayers
        let healthyRBs = roster
            .filter {
                $0.position == .RB && !injuredPlayerIDs.contains($0.id)
                    && !manuallyBenchedIDs.contains($0.id)
            }
            .sorted { $0.overall > $1.overall }
        guard healthyRBs.count >= 2 else {
            if restingRBID != nil { restingRBID = nil; rebuildFieldUnits() }
            return
        }
        let starter = healthyRBs[0]
        let backup = healthyRBs[1]

        if let restingID = restingRBID {
            guard restingID == starter.id else {
                restingRBID = nil
                rebuildFieldUnits()
                return
            }
            // Return once the starter is clearly fresher than the backup or
            // has recovered well below the rotation line.
            if starter.fatigue + 10 <= backup.fatigue
                || starter.fatigue < LiveGameEngine.rbRotationFatigueThreshold - 20 {
                restingRBID = nil
                rebuildFieldUnits()
            }
        } else if starter.fatigue >= LiveGameEngine.rbRotationFatigueThreshold,
                  backup.fatigue <= starter.fatigue - 10 {
            restingRBID = starter.id
            lastRotation = RotationEvent(inName: backup.shortName, outName: starter.shortName)
            rebuildFieldUnits()
        }
    }

    // MARK: - Drive Lifecycle (private)

    /// Wraps `DriveSimulator.checkImmediateDriveEnd` with the engine's state.
    private func immediateDriveEnd(for result: PlayResult) -> DriveSimulator.DriveSimulationResult? {
        DriveSimulator.checkImmediateDriveEnd(
            result,
            plays: currentDrivePlays,
            driveNumber: driveNumber,
            teamID: possessionTeamID,
            startingYardLine: driveStartYardLine,
            quarter: quarter,
            time: timeRemaining
        )
    }

    private func makeDriveResult(_ outcome: DriveOutcome) -> DriveResult {
        DriveResult(
            driveNumber: driveNumber,
            teamID: possessionTeamID,
            startingYardLine: driveStartYardLine,
            plays: currentDrivePlays,
            result: outcome
        )
    }

    /// Per-drive bookkeeping — mirrors GameSimulator.simulate's drive loop
    /// (stats, time of possession, highlights, scoring incl. safety-to-defense,
    /// momentum, fatigue), then handles the possession/quarter transition.
    /// - Parameter scoreAlreadyBooked: true for a touchdown drive that was
    ///   held open for its point-after try — its points (6 + the try) were
    ///   booked play by play, so the drive-points sum must not book again.
    private func finishDrive(_ drive: DriveResult, scoreAlreadyBooked: Bool = false) {
        allDrives.append(drive)

        let offense = homeHasPossession ? homePlayers : awayPlayers
        let defense = homeHasPossession ? awayPlayers : homePlayers
        GameSimulator.accumulateStats(
            from: drive,
            offensePlayers: offense,
            defensePlayers: defense,
            into: &statsAccumulator
        )
        // Milestone banners ride the same per-drive stat granularity.
        publishMilestones()

        // Day-grade trend snapshots (Coach's Board): the trend arrow compares
        // the live grade against the drive-before-last, so it reads as
        // "recent form", not "since kickoff". Player's team only — the
        // grades are never shown for the AI opponent.
        gradeSnapshots = lastDriveGrades
        lastDriveGrades = playerTeamGrades()

        let driveTime = drive.timeConsumed
        if homeHasPossession {
            homeTimeOfPossession += driveTime
        } else {
            awayTimeOfPossession += driveTime
        }

        allHighlights.append(contentsOf: drive.plays.filter {
            ($0.scoringPlay && $0.playType != .extraPoint)
                || $0.isTurnover || $0.yardsGained >= 20
        })

        // Score: drive points go to the possessing team; a safety is worth
        // +2 to the defense. Identical bookkeeping to GameSimulator.simulate.
        // A touchdown drive held open for its try booked everything play by
        // play already (`scoreAlreadyBooked`).
        if !scoreAlreadyBooked {
            let drivePoints = drive.plays.reduce(0) { $0 + $1.pointsScored }
            bookPoints(drivePoints, forHome: homeHasPossession)
            if drive.result == .safety {
                bookPoints(2, forHome: !homeHasPossession)
            }
        }

        momentum = GameSimulator.updateMomentum(
            currentMomentum: momentum,
            drive: drive,
            homeHasPossession: homeHasPossession
        )

        if homeHasPossession {
            GameSimulator.applyFatigue(
                starters: &homePlayers,
                bench: &awayPlayers,
                fatigueIncrease: GameSimulator.fatiguePerDriveStarter,
                fatigueRecovery: GameSimulator.fatigueRecoveryBench
            )
        } else {
            GameSimulator.applyFatigue(
                starters: &awayPlayers,
                bench: &homePlayers,
                fatigueIncrease: GameSimulator.fatiguePerDriveStarter,
                fatigueRecovery: GameSimulator.fatigueRecoveryBench
            )
        }

        if isOvertime {
            endOvertimeDrive(drive)
        } else {
            endRegulationDrive(drive)
        }
    }

    private func endRegulationDrive(_ drive: DriveResult) {
        let next = GameSimulator.determineNextPossession(
            afterDrive: drive,
            homeHasPossession: homeHasPossession
        )
        var nextHome = next.homeHasPossession
        var nextYardLine = next.startingYardLine
        // The view animates this kickoff (when non-nil) before the next snap.
        var kickoffEvent: KickoffEvent? = next.kickoff.map { kick in
            KickoffEvent(
                kickingTeamIsHome: homeHasPossession,
                startYardLine: kick.startingYardLine,
                isTouchback: kick.isTouchback,
                isReturnTouchdown: false
            )
        }

        // Kickoff return touchdown: the receiving team houses the ensuing
        // kick (same distribution and bookkeeping as GameSimulator.simulate).
        // Only while the half is still alive — no kick after the clock expires.
        if let kick = next.kickoff, kick.isReturnTouchdown, timeRemaining > 0 {
            let returnTeamIsHome = nextHome
            scoreKickoffReturnTouchdown(returnTeamIsHome: returnTeamIsHome)
            // The housed kick is the one worth showing; the ensuing kickoff
            // hands the ball straight back to the team that originally scored.
            kickoffEvent = KickoffEvent(
                kickingTeamIsHome: !returnTeamIsHome,
                startYardLine: 100,
                isTouchback: false,
                isReturnTouchdown: true
            )
            let ensuing = GameSimulator.rollKickoff(allowReturnTouchdown: false)
            nextHome = !returnTeamIsHome
            nextYardLine = ensuing.startingYardLine
        }

        if timeRemaining <= 0 {
            if quarter >= 4 {
                // Regulation over: sudden-death OT if tied, otherwise final.
                if homeScore == awayScore {
                    startOvertime()
                } else {
                    pendingKickoff = nil
                    isGameOver = true
                }
                return
            }
            quarter += 1
            timeRemaining = GameSimulator.quarterDuration
            if quarter == 3 {
                // Halftime: both teams recover; home receives the second-half
                // kickoff (position from the shared kickoff distribution).
                // Timeouts restock — three per half.
                GameSimulator.applyHalftimeRecovery(players: &homePlayers)
                GameSimulator.applyHalftimeRecovery(players: &awayPlayers)
                homeTimeouts = 3
                awayTimeouts = 3
                timeoutClockStopPending = false
                // The live view pauses here for the halftime report; the
                // engine itself plays on regardless (auto-sim parity).
                halftimePending = true
                nextHome = true
                let halfKick = GameSimulator.rollKickoff(allowReturnTouchdown: false)
                nextYardLine = halfKick.startingYardLine
                kickoffEvent = KickoffEvent(
                    kickingTeamIsHome: false,
                    startYardLine: halfKick.startingYardLine,
                    isTouchback: halfKick.isTouchback,
                    isReturnTouchdown: false
                )
            }
        }

        homeHasPossession = nextHome
        pendingKickoff = kickoffEvent
        beginDrive(at: nextYardLine)
    }

    /// Adds a synthetic one-play kickoff-return-touchdown drive to the books:
    /// score, quarter scores, play log, highlights, and momentum — mirroring
    /// the quick sim's bookkeeping for the same event.
    private func scoreKickoffReturnTouchdown(returnTeamIsHome: Bool) {
        driveNumber += 1
        let play = GameSimulator.kickoffReturnTouchdownPlay(
            quarter: quarter,
            timeRemaining: timeRemaining
        )
        // The housed return earns its point-after try too — auto-resolved
        // via the shared chart (mirrors the quick sim; no live choreography,
        // the feed line and score tell the story).
        let scoreAfterTD = (returnTeamIsHome ? homeScore : awayScore) + play.pointsScored
        let opponentScore = returnTeamIsHome ? awayScore : homeScore
        let tryPlay = GameSimulator.rollPointAfterTry(
            offensePlayers: simAvailablePlayers(isHome: returnTeamIsHome),
            defensePlayers: simAvailablePlayers(isHome: !returnTeamIsHome),
            scoreDiffAfterTD: scoreAfterTD - opponentScore,
            quarter: quarter,
            timeRemaining: timeRemaining,
            playNumber: 2
        )
        let returnDrive = DriveResult(
            driveNumber: driveNumber,
            teamID: returnTeamIsHome ? homeTeamID : awayTeamID,
            startingYardLine: GameSimulator.kickoffTouchbackYardLine,
            plays: [play, tryPlay],
            result: .touchdown
        )
        allDrives.append(returnDrive)
        allHighlights.append(play)
        playLog.append(play)
        playLog.append(tryPlay)

        bookPoints(play.pointsScored + tryPlay.pointsScored, forHome: returnTeamIsHome)

        momentum = GameSimulator.updateMomentum(
            currentMomentum: momentum,
            drive: returnDrive,
            homeHasPossession: returnTeamIsHome
        )
    }

    /// Simple sudden death: first score wins; if the 10-minute period expires
    /// with the game still tied, it ends in a tie.
    private func endOvertimeDrive(_ drive: DriveResult) {
        if homeScore != awayScore || timeRemaining <= 0 {
            pendingKickoff = nil
            isGameOver = true
            return
        }
        let next = GameSimulator.determineNextPossession(
            afterDrive: drive,
            homeHasPossession: homeHasPossession,
            allowKickoffReturnTouchdown: false
        )
        homeHasPossession = next.homeHasPossession
        pendingKickoff = nil // sudden-death transitions play on without a kick
        beginDrive(at: next.startingYardLine)
    }

    private func startOvertime() {
        quarter = GameSimulator.overtimeQuarter
        timeRemaining = GameSimulator.overtimeDuration
        homeQuarterScores.append(0)
        awayQuarterScores.append(0)
        homeHasPossession = Bool.random() // OT coin toss
        let otKick = GameSimulator.rollKickoff(allowReturnTouchdown: false)
        pendingKickoff = KickoffEvent(
            kickingTeamIsHome: !homeHasPossession,
            startYardLine: otKick.startingYardLine,
            isTouchback: otKick.isTouchback,
            isReturnTouchdown: false
        )
        beginDrive(at: otKick.startingYardLine)
    }

    // MARK: - Onside Kick (player choice, live game only)

    /// True right after the player's team scored while trailing in the 4th
    /// quarter (or OT never applies — a score there ends the game): the window
    /// where the view offers an onside kick instead of the pending deep kick.
    var onsideKickAvailable: Bool {
        guard !isGameOver, quarter >= 4, currentDrivePlays.isEmpty else { return false }
        guard let kick = pendingKickoff, !kick.isReturnTouchdown else { return false }
        // The player's team must be the kicking team and still trailing.
        guard kick.kickingTeamIsHome == playerTeamIsHome else { return false }
        let playerScore = playerTeamIsHome ? homeScore : awayScore
        let opponentScore = playerTeamIsHome ? awayScore : homeScore
        return playerScore < opponentScore
    }

    /// Replaces the pending deep kickoff with an onside attempt: a recovery
    /// (~12%) keeps the ball with the player's team near midfield; a failure
    /// hands the receiving team a short field. Live game only — the quick sim
    /// never onsides. Because this replaces a player choice (never taken by
    /// the AI), nil-parameter parity with `GameSimulator.simulate` is intact.
    /// - Returns: true when the kicking team recovered.
    @discardableResult
    func attemptOnsideKick() -> Bool {
        guard onsideKickAvailable else { return false }
        pendingKickoff = nil
        let recovered = Double.random(in: 0..<1) < GameSimulator.onsideKickRecoveryChance
        if recovered {
            homeHasPossession = playerTeamIsHome
            driveStartYardLine = GameSimulator.onsideKickRecoveryYardLine
        } else {
            driveStartYardLine = GameSimulator.onsideKickFailStartYardLine
        }
        yardLine = driveStartYardLine
        down = 1
        distance = min(10, 100 - driveStartYardLine)
        currentDrivePlays = []
        moraleAppliedForCurrentDrive = false
        return recovered
    }

    // MARK: - Point-After Try (XP / two-point conversion)

    /// Set when a scrimmage touchdown has just been scored in regulation:
    /// the six points are already on the board, the touchdown drive is held
    /// open, and the ensuing kickoff waits for ``attemptConversion``.
    struct PendingConversion: Equatable {
        /// The side that scored and now attempts the try.
        let scoringTeamIsHome: Bool
    }

    @Published private(set) var pendingConversion: PendingConversion?
    /// The touchdown drive held open while the try is pending.
    private var pendingConversionDrive: DriveResult?

    /// True when the PLAYER's team attempts the pending try — drives the
    /// XP / two-point choice panel (the AI resolves from the shared chart).
    var playerAttemptsConversion: Bool {
        pendingConversion?.scoringTeamIsHome == playerTeamIsHome
    }

    /// What the shared decision chart calls for the pending try. Used for
    /// AI teams (and both teams in fully simulated finishes) — identical to
    /// the quick sim's `GameSimulator.shouldGoForTwo`.
    var chartCallsForTwo: Bool {
        guard let pending = pendingConversion else { return false }
        let scoringScore = pending.scoringTeamIsHome ? homeScore : awayScore
        let opponentScore = pending.scoringTeamIsHome ? awayScore : homeScore
        return GameSimulator.shouldGoForTwo(
            scoreDiffAfterTD: scoringScore - opponentScore,
            quarter: quarter,
            timeRemaining: timeRemaining
        )
    }

    /// Resolves the pending point-after try. `goForTwo == nil` lets the
    /// shared chart decide (AI teams and sim-to-final — quick-sim parity);
    /// the player's explicit choice passes true/false. A two-point try is
    /// one real snap from the 2, biased by the offensive call and defensive
    /// package like any other play; the extra point is the kicker's near-
    /// automatic boot. Tries are untimed (no clock runoff). The touchdown
    /// drive then closes normally — kickoff and possession flip included.
    @discardableResult
    func attemptConversion(
        goForTwo: Bool? = nil,
        offensiveCall: OffensivePlayCall? = nil,
        defensivePackage: DefensivePackage? = nil
    ) -> PlayResult {
        guard !isGameOver, let pending = pendingConversion,
              var drive = pendingConversionDrive else {
            return lastPlay ?? gameOverPlaceholderPlay()
        }
        let scoringIsHome = pending.scoringTeamIsHome
        let scoringScore = scoringIsHome ? homeScore : awayScore
        let opponentScore = scoringIsHome ? awayScore : homeScore

        let play = GameSimulator.rollPointAfterTry(
            offensePlayers: simAvailablePlayers(isHome: scoringIsHome),
            defensePlayers: simAvailablePlayers(isHome: !scoringIsHome),
            scoreDiffAfterTD: scoringScore - opponentScore,
            quarter: quarter,
            timeRemaining: timeRemaining,
            playNumber: drive.plays.count + 1,
            forceTwoPoint: goForTwo,
            offensiveCall: offensiveCall,
            defensivePackage: defensivePackage
        )

        drive.plays.append(play)
        currentDrivePlays.append(play)
        playLog.append(play)
        lastPlay = play
        lastMatchups = nil
        lastPlayInjuries = []

        // The try's points land now; the touchdown's six were booked when
        // the drive was held open, so finishDrive must not book either again.
        bookPoints(play.pointsScored, forHome: scoringIsHome)

        pendingConversion = nil
        pendingConversionDrive = nil
        finishDrive(drive, scoreAlreadyBooked: true)
        return play
    }

    /// Closes a finished drive — EXCEPT a regulation touchdown, which books
    /// its six points immediately but holds the drive open for the untimed
    /// point-after try (see ``attemptConversion``). Overtime is sudden death
    /// here, so six points already settle it and the try is skipped — the
    /// quick sim's OT likewise never needs a conversion to break a tie.
    private func finishOrHoldDrive(_ drive: DriveResult, after play: PlayResult) {
        guard drive.result == .touchdown, play.outcome == .touchdown, !isOvertime else {
            finishDrive(drive)
            return
        }
        bookPoints(play.pointsScored, forHome: homeHasPossession)
        pendingConversionDrive = drive
        pendingConversion = PendingConversion(scoringTeamIsHome: homeHasPossession)
        // Present the try from the 2-yard line, goal to go.
        yardLine = 98
        down = 1
        distance = 2
    }

    /// Adds points to one side's total and the current quarter line.
    private func bookPoints(_ points: Int, forHome: Bool) {
        guard points > 0 else { return }
        let quarterIndex = min(quarter - 1, homeQuarterScores.count - 1)
        if forHome {
            homeScore += points
            homeQuarterScores[quarterIndex] += points
        } else {
            awayScore += points
            awayQuarterScores[quarterIndex] += points
        }
    }

    private func beginDrive(at startingYardLine: Int) {
        driveNumber += 1
        driveStartYardLine = max(1, min(99, startingYardLine))
        yardLine = driveStartYardLine
        down = 1
        // Cap first-down distance near the end zone (mirrors DriveSimulator).
        distance = min(10, 100 - driveStartYardLine)
        currentDrivePlays = []
        moraleAppliedForCurrentDrive = false
        // Fatigue rotation is decided between drives (player's team only).
        updateRBRotation()
    }

    /// Returned by ``step`` only if it is called after the game has ended.
    private func gameOverPlaceholderPlay() -> PlayResult {
        PlayResult(
            playNumber: 0,
            quarter: quarter,
            timeRemaining: timeRemaining,
            down: down,
            distance: distance,
            yardLine: yardLine,
            playType: .kneel,
            outcome: .kneel,
            yardsGained: 0,
            description: "The game is over.",
            isFirstDown: false,
            isTurnover: false,
            scoringPlay: false,
            pointsScored: 0
        )
    }
}
