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
