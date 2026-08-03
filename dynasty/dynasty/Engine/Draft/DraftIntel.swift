import Foundation

/// Player-facing knowledge layer for the draft.
///
/// `DraftIntel` exposes only what the user legitimately knows: a public rank
/// derived from the consensus board (scouted overall + media projection),
/// scout-confidence stars, position need scoring, and reach indicators. It does
/// NOT expose hidden information such as `truePotential`.
enum DraftIntel {

    // MARK: - Public board rank

    /// Builds a `[ProspectID: pickRank (1...N)]` map for the entire draft class.
    /// The rank reflects where each prospect *would* go if the board flowed
    /// strictly by consensus value — used for Steal / Reach calculations.
    ///
    /// Single consensus source: the scouted overall the league has landed on,
    /// broken by the media's projected round. `DraftIntel` used to apply its own
    /// positional-value table, which disagreed with the one `ScoutingEngine`
    /// used for `draftProjection` — Steal / Reach badges then contradicted the
    /// projection shown next to them on the same screen. Positional value is now
    /// baked into the class blueprint, so no multiplier belongs here at all.
    static func publicBoardRanks(for prospects: [CollegeProspect]) -> [UUID: Int] {
        let sorted = prospects.sorted { lhs, rhs in
            let lhsOverall = lhs.scoutedOverall ?? lhs.trueOverall
            let rhsOverall = rhs.scoutedOverall ?? rhs.trueOverall
            if lhsOverall != rhsOverall { return lhsOverall > rhsOverall }
            let lhsProjection = lhs.draftProjection ?? 8
            let rhsProjection = rhs.draftProjection ?? 8
            if lhsProjection != rhsProjection { return lhsProjection < rhsProjection }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var result: [UUID: Int] = [:]
        for (idx, prospect) in sorted.enumerated() {
            result[prospect.id] = idx + 1
        }
        return result
    }

    // MARK: - Scout confidence

    /// Returns 1...5 stars representing how confident the player can be in
    /// what the scouts have reported. In Vaihe 2 we approximate this from
    /// the depth of scouting reports + whether combine / interview / pro day
    /// happened. Vaihe 5 will integrate per-scout coverage more tightly.
    static func scoutConfidence(for prospect: CollegeProspect) -> Int {
        var score = 1
        if !prospect.scoutingReports.isEmpty { score += 1 }
        if prospect.scoutingReports.count >= 2 { score += 1 }
        if prospect.combineInvite { score += 1 }
        if prospect.interviewCompleted || prospect.proDayCompleted { score += 1 }
        return min(5, score)
    }

    // MARK: - Reach indicator

    enum ReachIndicator {
        case steal(delta: Int)
        case solid
        case reach(delta: Int)

        var label: String {
            switch self {
            case .steal(let d): return "STEAL +\(d)"
            case .solid:        return "SOLID"
            case .reach(let d): return "REACH \(d)"
            }
        }
    }

    /// Compares the prospect's public rank to the current pick number.
    /// `boardRanks` should come from `publicBoardRanks(for:)`.
    static func reachIndicator(
        prospectID: UUID,
        pickNumber: Int,
        boardRanks: [UUID: Int]
    ) -> ReachIndicator {
        guard let rank = boardRanks[prospectID] else { return .solid }
        let delta = pickNumber - rank
        if delta >= 4 { return .steal(delta: delta) }
        if delta <= -4 { return .reach(delta: delta) }
        return .solid
    }

    // MARK: - Consensus board (public information only)

    /// The `count` prospects the *media* rates highest.
    ///
    /// Deliberately NOT `publicBoardRanks`: that falls back to `trueOverall`
    /// for anyone the user has not scouted, which is fine for a Steal / Reach
    /// badge computed at pick time but would quietly leak hidden talent into a
    /// "how much of the top 100 have you covered?" statistic — the denominator
    /// would already know which unscouted men were good. Everything read here
    /// is published: the projected round, the latest mock's pick number, and
    /// whether the league invited him to Indianapolis.
    static func consensusTop(_ prospects: [CollegeProspect], count: Int) -> [CollegeProspect] {
        let sorted = prospects.sorted { lhs, rhs in
            let lhsMock = lhs.mockDraftPickNumber ?? Int.max
            let rhsMock = rhs.mockDraftPickNumber ?? Int.max
            if lhsMock != rhsMock { return lhsMock < rhsMock }
            let lhsRound = lhs.draftProjection ?? 9
            let rhsRound = rhs.draftProjection ?? 9
            if lhsRound != rhsRound { return lhsRound < rhsRound }
            if lhs.combineInvite != rhs.combineInvite { return lhs.combineInvite }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return Array(sorted.prefix(count))
    }

    // MARK: - Draft prep coverage

    /// How far along one prospect's evaluation is. Every case is a fact stored
    /// on the prospect — nothing here is inferred from a phase or a timer.
    struct PrepStatus {
        let reportCount: Int
        let isInterviewed: Bool
        /// The league measured him and the numbers reached your building.
        let hasMeasurables: Bool
        let hasProDay: Bool

        /// Nobody in the building has done a thing.
        var isUntouched: Bool {
            reportCount == 0 && !isInterviewed && !hasMeasurables && !hasProDay
        }

        /// Tape filed AND a meeting taken — the bar for "we know this man".
        var isWellScouted: Bool { reportCount >= 2 && isInterviewed }
    }

    static func prepStatus(for prospect: CollegeProspect) -> PrepStatus {
        PrepStatus(
            reportCount: prospect.scoutingReports.count,
            isInterviewed: prospect.interviewCompleted,
            hasMeasurables: prospect.fortyTime != nil,
            hasProDay: prospect.proDayCompleted
        )
    }

    /// Aggregate coverage of the consensus board's top slice.
    struct BoardCoverage {
        /// Size of the slice examined (may be < requested when the class is small).
        let sampleSize: Int
        /// How many of them carry at least one filed report.
        let scouted: Int
        /// How many of them your staff has interviewed.
        let interviewed: Int

        var scoutedPercent: Int {
            guard sampleSize > 0 else { return 0 }
            return Int((Double(scouted) / Double(sampleSize) * 100).rounded())
        }

        var interviewedPercent: Int {
            guard sampleSize > 0 else { return 0 }
            return Int((Double(interviewed) / Double(sampleSize) * 100).rounded())
        }
    }

    static func boardCoverage(prospects: [CollegeProspect], topCount: Int = 100) -> BoardCoverage {
        let slice = consensusTop(prospects, count: topCount)
        return BoardCoverage(
            sampleSize: slice.count,
            scouted: slice.filter { !$0.scoutingReports.isEmpty }.count,
            interviewed: slice.filter(\.interviewCompleted).count
        )
    }

    /// Coverage of one position group inside the consensus top slice — the
    /// input to "you have three picks and have filed on one linebacker".
    struct PositionCoverage: Identifiable {
        let position: Position
        let onBoard: Int
        let scouted: Int

        var id: String { position.rawValue }

        /// Thin means the group is a stated need and you have filed on fewer
        /// than two of the men the media rates inside it.
        var isThin: Bool { scouted < 2 && onBoard > 0 }
    }

    /// Scouting coverage for the team's top needs, restricted to the consensus
    /// top slice so a need is not declared "covered" by a seventh-round flier.
    static func needCoverage(
        prospects: [CollegeProspect],
        roster: [Player],
        topCount: Int = 100,
        needLimit: Int = 5
    ) -> [PositionCoverage] {
        let needs = DraftEngine.topTeamNeeds(roster: roster, limit: needLimit)
        guard !needs.isEmpty else { return [] }
        let slice = consensusTop(prospects, count: topCount)
        return needs.map { position in
            let group = slice.filter { $0.position == position }
            return PositionCoverage(
                position: position,
                onBoard: group.count,
                scouted: group.filter { !$0.scoutingReports.isEmpty }.count
            )
        }
    }

    // MARK: - Team needs

    /// Returns a `[Position: priority(0..1)]` map for the team.
    /// Highest-need position gets ~1.0, secondary needs scale down.
    static func teamNeedScores(roster: [Player]) -> [Position: Double] {
        let topNeeds = DraftEngine.topTeamNeeds(roster: roster, limit: 6)
        var scores: [Position: Double] = [:]
        for (idx, position) in topNeeds.enumerated() {
            scores[position] = max(0.3, 1.0 - Double(idx) * 0.15)
        }
        return scores
    }

}
