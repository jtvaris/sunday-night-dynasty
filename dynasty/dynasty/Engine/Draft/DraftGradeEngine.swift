import Foundation
import SwiftData

/// #40 Draft-outcome grading. A HINDSIGHT evaluation of how a drafted player has
/// panned out RELATIVE TO HIS DRAFT ROUND — the opposite of the draft-day
/// `PickGrade`/`DraftPickGrade` value read. A 7th-round pick who became a starter
/// is an A+; a 1st-round pick riding the bench is a bust. Purely analytical:
/// it never mutates simulation state and persists nothing.
///
/// Inputs are what the league actually records for every team (AI games are
/// score-only, so no per-position box score exists league-wide):
///   • career starts   — `Player.gamesStartedThisSeason` + Σ history `gamesStarted` (#40)
///   • career games     — `Player.gamesPlayedThisSeason`  + Σ history `gamesPlayed`  (#33)
///   • OVR development   — peak OVR vs rookie-year OVR
///   • longevity         — pro seasons played
/// Per-position statline totals (yards/TD/sacks) are intentionally NOT part of
/// the model: `PlayerSeasonHistory.keyStat1/2/3` stay 0 because per-game stats
/// aren't persisted for the 31 AI teams. Starts + games + OVR growth are the
/// documented production basis, exactly as the #40 fallback allows.
enum DraftGradeEngine {

    // MARK: - Result types

    /// Per-player hindsight grade.
    struct PlayerGrade: Identifiable {
        var id: UUID { playerID }
        let playerID: UUID
        let pickNumber: Int
        let round: Int
        /// Letter grade A+ … F.
        let letter: String
        /// Production ÷ round expectation. 1.0 = exactly met the bar for the round.
        let ratio: Double
        let careerStarts: Int
        let careerGames: Int
        let peakOVR: Int
        /// Peak OVR minus rookie-year OVR (never negative).
        let ovrDevelopment: Int
        /// Met or beat the expectation for his round (or became a real late-round starter).
        let isHit: Bool
        /// Early pick (rounds 1-3) who flopped once matured.
        let isBust: Bool
        /// Fewer than 2 pro seasons — the verdict is still forming; treat leniently.
        let isProvisional: Bool
        /// One-line human-readable verdict.
        let summary: String
    }

    /// Team draft-class grade for a single draft year.
    struct ClassGrade {
        let season: Int
        let teamID: UUID
        /// Pick-value-weighted class letter (early picks weigh more).
        let letter: String
        let weightedRatio: Double
        /// Per-pick grades, ordered by overall pick number.
        let picks: [PlayerGrade]
        /// Highest ratio — the class's best value.
        let bestPickID: UUID?
        /// Biggest disappointment relative to round (early misses prioritized).
        let biggestMissID: UUID?
    }

    // MARK: - Tunables

    /// Expected career "value points" for a pick, by round. A player who clears
    /// this bar grades ≈ B+; one who doubles it approaches A+.
    private static let roundExpectation: [Int: Double] = [
        1: 42, 2: 32, 3: 25, 4: 19, 5: 14, 6: 10, 7: 7,
    ]

    /// OVR at/below which a player provides no positive "value points".
    private static let replacementOVR = 55.0

    // MARK: - Per-player grade

    /// Grades a single drafted player from his live row + season history.
    /// Returns `nil` for players with no draft provenance (UDFAs / legacy).
    static func grade(for player: Player, history: [PlayerSeasonHistory]) -> PlayerGrade? {
        guard let pick = player.draftPickNumber else { return nil }
        let round = player.draftRound ?? DraftEngine.roundForPick(pick)

        let sorted = history.sorted { $0.season < $1.season }
        let careerStarts = player.gamesStartedThisSeason + sorted.reduce(0) { $0 + $1.gamesStarted }
        let careerGames = player.gamesPlayedThisSeason + sorted.reduce(0) { $0 + $1.gamesPlayed }

        // Active pro seasons: prefer the live yearsPro, but never under-count the
        // recorded history (a traded/cut player keeps his rows).
        let seasonsPlayed = max(1, max(player.yearsPro, sorted.count))

        let peakOVR = max(player.overall, sorted.map(\.overallAtEndOfSeason).max() ?? 0)
        // Rookie-year OVR ≈ earliest recorded season; fall back to current OVR.
        let rookieOVR = sorted.first?.overallAtEndOfSeason ?? player.overall
        let ovrDevelopment = max(0, peakOVR - rookieOVR)

        let startsPerSeason = Double(careerStarts) / Double(seasonsPlayed)

        // Career value in points (round-independent, absolute production).
        let ovrPoints = max(0.0, Double(peakOVR) - replacementOVR)   // 90 OVR → 35
        let startPoints = startsPerSeason * 1.6                       // 15 starts/yr → 24
        let developmentPoints = Double(ovrDevelopment) * 0.4         // +20 OVR growth → 8
        let value = ovrPoints + startPoints + developmentPoints

        // Rookies need time: scale the bar down until the player has ~4 seasons,
        // so a Day-1 rookie is never branded a bust before he's had a chance.
        let maturity = min(1.0, Double(seasonsPlayed) / 4.0)
        let baseExpectation = roundExpectation[round] ?? 7.0
        let expectation = max(1.0, baseExpectation * maturity)
        let ratio = value / expectation

        let isProvisional = seasonsPlayed < 2
        let isLateRoundStarter = round >= 4 && startsPerSeason >= 8.0
        let isHit = ratio >= 1.0 || isLateRoundStarter
        let isBust = round <= 3 && !isProvisional && ratio < 0.40

        let letter = letterForRatio(ratio)
        let summary = makeSummary(
            round: round, letter: letter, isHit: isHit, isBust: isBust,
            isProvisional: isProvisional, careerStarts: careerStarts,
            peakOVR: peakOVR, seasonsPlayed: seasonsPlayed
        )

        return PlayerGrade(
            playerID: player.id, pickNumber: pick, round: round, letter: letter,
            ratio: ratio, careerStarts: careerStarts, careerGames: careerGames,
            peakOVR: peakOVR, ovrDevelopment: ovrDevelopment,
            isHit: isHit, isBust: isBust, isProvisional: isProvisional, summary: summary
        )
    }

    // MARK: - Team class grade

    /// Grades a team's full draft class for one season. Pass the players drafted
    /// by `teamID` in `season` (matched on `draftedByTeamID`/`draftSeason`) and a
    /// map from player id → that player's season history.
    static func classGrade(
        season: Int,
        teamID: UUID,
        players: [Player],
        historyByPlayer: [UUID: [PlayerSeasonHistory]]
    ) -> ClassGrade? {
        let picks = players
            .compactMap { grade(for: $0, history: historyByPlayer[$0.id] ?? []) }
            .sorted { $0.pickNumber < $1.pickNumber }
        guard !picks.isEmpty else { return nil }

        // Pick-value-weighted class ratio — early picks dominate the class grade.
        var weightSum = 0.0
        var weightedRatioSum = 0.0
        for p in picks {
            let w = Double(max(1, DraftEngine.pickValue(p.pickNumber)))
            weightSum += w
            weightedRatioSum += p.ratio * w
        }
        let weightedRatio = weightSum > 0 ? weightedRatioSum / weightSum : 0
        let letter = letterForRatio(weightedRatio)

        let bestPickID = picks.max { $0.ratio < $1.ratio }?.playerID

        // Biggest miss: prefer a matured early-round flop; else the lowest ratio.
        let earlyMisses = picks.filter { $0.round <= 3 && !$0.isProvisional }
        let biggestMissID = (earlyMisses.min { $0.ratio < $1.ratio }
            ?? picks.filter { !$0.isProvisional }.min { $0.ratio < $1.ratio }
            ?? picks.min { $0.ratio < $1.ratio })?.playerID

        return ClassGrade(
            season: season, teamID: teamID, letter: letter, weightedRatio: weightedRatio,
            picks: picks, bestPickID: bestPickID, biggestMissID: biggestMissID
        )
    }

    /// Convenience: fetch a team's draft class + histories from the store and grade it.
    static func classGrade(
        season: Int,
        teamID: UUID,
        modelContext: ModelContext
    ) -> ClassGrade? {
        let playerFetch = FetchDescriptor<Player>(
            predicate: #Predicate {
                $0.draftedByTeamID == teamID && $0.draftSeason == season
            }
        )
        let players = (try? modelContext.fetch(playerFetch)) ?? []
        guard !players.isEmpty else { return nil }

        var historyByPlayer: [UUID: [PlayerSeasonHistory]] = [:]
        for player in players {
            let pid = player.id
            let hFetch = FetchDescriptor<PlayerSeasonHistory>(
                predicate: #Predicate { $0.playerID == pid }
            )
            historyByPlayer[pid] = (try? modelContext.fetch(hFetch)) ?? []
        }
        return classGrade(
            season: season, teamID: teamID,
            players: players, historyByPlayer: historyByPlayer
        )
    }

    // MARK: - Grade scale

    /// Maps a production/expectation ratio to a letter grade (A+ … F).
    static func letterForRatio(_ ratio: Double) -> String {
        switch ratio {
        case 1.55...:      return "A+"
        case 1.30..<1.55:  return "A"
        case 1.12..<1.30:  return "A-"
        case 1.00..<1.12:  return "B+"
        case 0.88..<1.00:  return "B"
        case 0.75..<0.88:  return "B-"
        case 0.62..<0.75:  return "C+"
        case 0.50..<0.62:  return "C"
        case 0.40..<0.50:  return "C-"
        case 0.28..<0.40:  return "D"
        default:           return "F"
        }
    }

    // MARK: - Private

    private static func makeSummary(
        round: Int, letter: String, isHit: Bool, isBust: Bool,
        isProvisional: Bool, careerStarts: Int, peakOVR: Int, seasonsPlayed: Int
    ) -> String {
        if isProvisional {
            return "Round \(round) pick — too early to judge (\(seasonsPlayed)-yr sample)."
        }
        if isBust {
            return "Round \(round) bust — \(careerStarts) career starts, peaked at \(peakOVR) OVR."
        }
        if isHit && round >= 4 {
            return "Round \(round) steal — \(careerStarts) starts, \(peakOVR) OVR ceiling."
        }
        if isHit {
            return "Round \(round) hit — \(careerStarts) starts, \(peakOVR) OVR."
        }
        return "Round \(round) pick — below the bar (\(careerStarts) starts, \(peakOVR) OVR)."
    }
}
