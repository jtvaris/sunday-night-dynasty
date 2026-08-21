import Foundation

// MARK: - Preseason State (#205b — OFFSEASON_ROSTER_PLAN §4.3)
//
// Three preseason games, persisted as ONE Codable blob on `Career`
// (`Career.preseasonData`), not as `Game` rows.
//
// ## Why a blob and not `Game` rows
//
// `Game` carries only `isPlayoff`, and `career.currentSeason` is still the
// *finished* year N throughout the whole offseason — the `+= 1` happens at the
// `rosterCuts → regularSeason` step. A preseason row at (season N, week 1-3,
// isPlayoff false) would therefore collide with season N's already-played weeks
// 1-3 and corrupt `StandingsCalculator`, the schedule screen and
// `MultiSeasonSmokeTest`. Sixteen `FetchDescriptor<Game>` sites read that table;
// none of them can see this file, by construction.
//
// So: zero new `@Model`s, zero SwiftData migration, one decode.
//
// ## Career scoping (invariant 6)
//
// The blob lives on the `Career` row, so it is career-scoped by construction.
// `careerID` is stamped anyway and checked by ``PreseasonState/matches(career:)``
// — a blob that survives a career switch through some future copy path must
// never be read as this career's preseason.
//
// ## What this file deliberately does NOT hold
//
// No contract state of any kind. Preseason ticks **nothing** on a deal — see the
// header of `PreseasonEngine` and invariant (1)/#89.

// MARK: - Policy

/// The coach's call before a preseason game: who dresses (#205b, plan §4.2).
///
/// The policy composes **which men dress**, because that is the only lever
/// `GameSimulator` actually has — it fields the best available man at each
/// position off the roster it is handed. Everything else (familiarity banked,
/// injury exposure) follows from the snap share that composition implies.
enum PreseasonPolicy: String, Codable, CaseIterable, Identifiable {
    /// Starters watch in a baseball cap. The bubble plays the whole game.
    case startersRest  = "StartersRest"
    /// The real-league default: the ones open the game, the bubble finishes it.
    case starterSeries = "StarterSeries"
    /// Everybody goes. Week 1 arrives with the playbook installed — if they
    /// all make it to Week 1.
    case fullTilt      = "FullTilt"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .startersRest:  return "Rest the Starters"
        case .starterSeries: return "Starter Series"
        case .fullTilt:      return "Full Tilt"
        }
    }

    /// The trade-off, stated in the row's own copy (plan §5). English only.
    var blurb: String {
        switch self {
        case .startersRest:
            return "Ones in caps. No injury risk and no install for your starters — the bubble plays four quarters and every rep is evidence for the cut."
        case .starterSeries:
            return "Ones open, bubble finishes. A partial install and a partial risk — the league-standard preseason."
        case .fullTilt:
            return "Everybody plays. The fastest playbook install in the game, paid for with a full game of injury exposure on your best men."
        }
    }

    /// Do the projected starters dress at all under this policy.
    var dressesStarters: Bool { self != .startersRest }
}

// MARK: - Step machine

/// Where the user is inside the single `.preseason` phase visit.
///
/// Same shape free agency already ships (`Career.freeAgencyRound` /
/// `freeAgencyStep` + `FAFlowBand`): three games are three **steps inside one
/// phase**, not three phases. That is the whole reason this wave needs no new
/// `SeasonPhase` case (invariant 2), no change to `phase(after:)` and no change
/// to `TaskProgressStore.cycle(season:phase:week:)` (invariant 4).
///
/// Encoded as `kind` + `gameIndex` rather than as an enum with associated
/// values: this is persisted JSON, and a flat rawValue pair is stable against
/// every future compiler-synthesised-Codable change.
nonisolated struct PreseasonStep: Codable, Equatable {

    enum Kind: String, Codable {
        /// Pick a policy for game `gameIndex`, then sim it.
        case plan
        /// Game `gameIndex` is played; its recap sheet is owed to the user.
        case recap
        /// All three games are played and acknowledged.
        case complete
    }

    var kind: Kind
    /// 1-based game number this step is about; `0` when `kind == .complete`.
    var gameIndex: Int

    static func plan(_ index: Int) -> PreseasonStep { PreseasonStep(kind: .plan, gameIndex: index) }
    static func recap(_ index: Int) -> PreseasonStep { PreseasonStep(kind: .recap, gameIndex: index) }
    static let complete = PreseasonStep(kind: .complete, gameIndex: 0)

    var isComplete: Bool { kind == .complete }
}

// MARK: - Slate

/// One exhibition on the user's three-game slate.
///
/// The slate is drawn once, when the phase opens, and then persisted — so the
/// opponents are stable across a re-entered phase and across a cold launch
/// without needing a seeded RNG. `id` is a stable per-game identity for the
/// UI's `ForEach` and for anything that later wants a deterministic per-game
/// draw off it.
nonisolated struct PreseasonMatchup: Codable, Identifiable, Equatable {
    var id: UUID
    /// 1-based.
    var gameIndex: Int
    var opponentTeamID: UUID
    /// Snapshotted for display so the recap never needs a `Team` fetch.
    var opponentAbbreviation: String
    var opponentName: String
    /// True when the user's club is the home team.
    var isHome: Bool

    init(
        id: UUID = UUID(),
        gameIndex: Int,
        opponentTeamID: UUID,
        opponentAbbreviation: String,
        opponentName: String,
        isHome: Bool
    ) {
        self.id = id
        self.gameIndex = gameIndex
        self.opponentTeamID = opponentTeamID
        self.opponentAbbreviation = opponentAbbreviation
        self.opponentName = opponentName
        self.isHome = isHome
    }
}

// MARK: - Result payload

/// An injury the exhibition cost, display-ready.
///
/// Name and position are snapshotted because the recap has to be able to name a
/// man the user cut two screens later.
nonisolated struct PreseasonInjury: Codable, Identifiable, Equatable {
    var playerID: UUID
    var playerName: String
    var position: Position
    /// `InjuryType.rawValue`.
    var injuryType: String
    var weeksOut: Int

    var id: UUID { playerID }
}

/// Scheme familiarity banked by one man in one exhibition.
///
/// An array of pairs rather than `[UUID: Int]`: `JSONEncoder` cannot write a
/// dictionary with non-`String` keys as an object, so it silently degrades to a
/// flat alternating array. Being explicit about the shape keeps the persisted
/// JSON readable and stable.
nonisolated struct PreseasonFamiliarityGain: Codable, Identifiable, Equatable {
    var playerID: UUID
    var playerName: String
    var position: Position
    var points: Int
    var scheme: String

    var id: UUID { playerID }
}

/// One score-only line from the rest of the league's exhibition slate.
nonisolated struct PreseasonScoreLine: Codable, Identifiable, Equatable {
    var id: UUID
    var homeTeamID: UUID
    var awayTeamID: UUID
    var homeAbbreviation: String
    var awayAbbreviation: String
    var homeScore: Int
    var awayScore: Int

    init(
        id: UUID = UUID(),
        homeTeamID: UUID,
        awayTeamID: UUID,
        homeAbbreviation: String,
        awayAbbreviation: String,
        homeScore: Int,
        awayScore: Int
    ) {
        self.id = id
        self.homeTeamID = homeTeamID
        self.awayTeamID = awayTeamID
        self.homeAbbreviation = homeAbbreviation
        self.awayAbbreviation = awayAbbreviation
        self.homeScore = homeScore
        self.awayScore = awayScore
    }
}

/// Everything one played exhibition leaves behind.
///
/// `userLines` is the user's own box score — `PlayerGameStats` is already a
/// plain `Codable` struct, not a `@Model`, so it persists into the blob as-is.
/// The other 15 games in the league are **score-only** (`leagueScoreboard`),
/// the same bargain the regular season and the postseason already strike: 31
/// full play-by-play sims per exhibition × 3 exhibitions is 93 extra sims an
/// offseason for numbers nobody box-scores (plan §4.3, risk R5).
/// (Not `Equatable`: `PlayerGameStats` is not, and a box score has no useful
/// equality anyway — identity is `gameIndex`.)
nonisolated struct PreseasonResult: Codable, Identifiable {
    /// 1-based.
    var gameIndex: Int
    var matchup: PreseasonMatchup
    /// The call the user actually made. Recorded HERE and nowhere else — one
    /// authority, so the recap and the state can never disagree about what he
    /// chose (plan §4.3 listed a parallel `policies` array; this drops it).
    var policy: PreseasonPolicy
    var userScore: Int
    var opponentScore: Int
    /// The user's box score. Bubble men included — they are the point.
    var userLines: [PlayerGameStats]
    /// The men who are NOT in the club's projected starting lineup, i.e. the
    /// cohort the 75 → 65 → 53 ladder is actually about.
    var bubblePlayerIDs: [UUID]
    /// The projected starting lineup this game was ACTUALLY played with —
    /// `WeekAdvancer.startingLineupIDs` over the men who were available that
    /// August afternoon. Recorded here because a recap is a historical record:
    /// re-deriving "who started" from today's roster mislabels a game played
    /// two exhibitions ago the moment anybody was hurt or holding out.
    /// Optional only so a blob written before this field existed still decodes
    /// (`Career.preseasonState` decodes with `try?` — a hard failure would wipe
    /// an in-flight slate); read it through ``starterIDs(fallback:)``.
    var starterPlayerIDs: [UUID]?
    var injuries: [PreseasonInjury]
    var familiarityGains: [PreseasonFamiliarityGain]
    var leagueScoreboard: [PreseasonScoreLine]

    var id: Int { gameIndex }

    // MARK: Derived (one authority for the recap sheet)

    /// The starter set this game must be judged by.
    ///
    /// The recorded set when there is one — the lineup the snaps, the
    /// familiarity and the injury rolls were actually charged against — and the
    /// caller's live projection only for a pre-existing blob that predates the
    /// field.
    func starterIDs(fallback: Set<UUID>) -> Set<UUID> {
        guard let starterPlayerIDs else { return fallback }
        return Set(starterPlayerIDs)
    }

    var didWin: Bool { userScore > opponentScore }
    var didTie: Bool { userScore == opponentScore }

    /// "34-17" from the user's point of view.
    var scoreline: String { "\(userScore)-\(opponentScore)" }

    /// "W", "L" or "T".
    var resultLetter: String { didTie ? "T" : (didWin ? "W" : "L") }

    /// The stat lines belonging to the bubble cohort — the evidence the cut is
    /// made on.
    var bubbleLines: [PlayerGameStats] {
        let bubble = Set(bubblePlayerIDs)
        return userLines.filter { bubble.contains($0.playerID) }
    }

    /// The bubble man who did the most with his snaps. Deliberately scored off
    /// production only (yards + 6 per TD + tackle/sack defensive credit), not
    /// off `overall` — the whole point of the exhibition is that it is evidence
    /// a rating does not already contain.
    var biggestRiser: PlayerGameStats? {
        guard let best = bubbleLines.max(by: { impactScore($0) < impactScore($1) }) else { return nil }
        return impactScore(best) > 0 ? best : nil
    }

    private func impactScore(_ line: PlayerGameStats) -> Double {
        Double(line.passingYards) * 0.04
            + Double(line.rushingYards) * 0.1
            + Double(line.receivingYards) * 0.1
            + Double(line.passingTDs + line.rushingTDs + line.receivingTDs) * 6.0
            - Double(line.interceptions) * 4.0
            + Double(line.tackles) * 0.8
            + line.sacks * 4.0
            + Double(line.interceptionsCaught) * 6.0
            + Double(line.forcedFumbles) * 4.0
            + Double(line.passDeflectionCount) * 1.5
            + Double(line.fieldGoalsMade) * 3.0
    }
}

// MARK: - State

/// The whole `.preseason` phase, in one decodable value.
nonisolated struct PreseasonState: Codable {

    /// Invariant (6): every piece of new data is career-stamped.
    var careerID: UUID
    /// The season the slate was drawn for. Still the *finished* year N — the
    /// season increment happens at the `rosterCuts → regularSeason` step.
    var season: Int
    var step: PreseasonStep
    var slate: [PreseasonMatchup]
    var results: [PreseasonResult]

    init(
        careerID: UUID,
        season: Int,
        step: PreseasonStep = .plan(1),
        slate: [PreseasonMatchup] = [],
        results: [PreseasonResult] = []
    ) {
        self.careerID = careerID
        self.season = season
        self.step = step
        self.slate = slate
        self.results = results
    }

    // MARK: Reads

    /// A stale blob (a different career, or last year's slate) must never be
    /// read as this preseason.
    func matches(career: Career) -> Bool {
        careerID == career.id && season == career.currentSeason
    }

    var isComplete: Bool { step.isComplete }

    /// The game the user is being asked to plan, if he is being asked.
    var pendingMatchup: PreseasonMatchup? {
        guard step.kind == .plan else { return nil }
        return matchup(at: step.gameIndex)
    }

    /// The result whose recap sheet is owed, if one is.
    var pendingRecap: PreseasonResult? {
        guard step.kind == .recap else { return nil }
        return result(at: step.gameIndex)
    }

    func matchup(at gameIndex: Int) -> PreseasonMatchup? {
        slate.first { $0.gameIndex == gameIndex }
    }

    func result(at gameIndex: Int) -> PreseasonResult? {
        results.first { $0.gameIndex == gameIndex }
    }

    /// W-L-T across the played slate, for the flow band.
    var record: (wins: Int, losses: Int, ties: Int) {
        var w = 0, l = 0, t = 0
        for result in results {
            if result.didTie { t += 1 } else if result.didWin { w += 1 } else { l += 1 }
        }
        return (w, l, t)
    }

    /// "1-1" / "2-0-1" — display voice for the band.
    var recordLine: String {
        let r = record
        return r.ties > 0 ? "\(r.wins)-\(r.losses)-\(r.ties)" : "\(r.wins)-\(r.losses)"
    }

    /// Everyone the slate has hurt so far, newest game last.
    var allInjuries: [PreseasonInjury] { results.flatMap(\.injuries) }
}
