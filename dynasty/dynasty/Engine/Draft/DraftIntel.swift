import Foundation

/// Player-facing knowledge layer for the draft.
///
/// `DraftIntel` exposes only what the user legitimately knows: a public rank
/// derived from the consensus board (composite of trueOverall × positional
/// value), scout-confidence stars, position need scoring, and reach
/// indicators. It does NOT expose hidden information such as `truePotential`.
enum DraftIntel {

    // MARK: - Public board rank

    /// Builds a `[ProspectID: pickRank (1...N)]` map for the entire draft class.
    /// The rank reflects where each prospect *would* go if the board flowed
    /// strictly by consensus value — used for Steal / Reach calculations.
    static func publicBoardRanks(for prospects: [CollegeProspect]) -> [UUID: Int] {
        let sorted = prospects.sorted { lhs, rhs in
            score(of: lhs) > score(of: rhs)
        }
        var result: [UUID: Int] = [:]
        for (idx, prospect) in sorted.enumerated() {
            result[prospect.id] = idx + 1
        }
        return result
    }

    private static func score(of prospect: CollegeProspect) -> Double {
        Double(prospect.trueOverall) * positionalDraftValue(for: prospect.position)
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

    // MARK: - Positional draft value

    /// Premium positions (QB, EDGE, LT, CB, WR) carry a boost so consensus
    /// rankings push them up the board. Lower-value positions (P, K, FB) are
    /// pushed down. These weights mirror the values used by `ScoutingEngine`
    /// when assigning `draftProjection`, keeping the player-visible board
    /// consistent with the league's perceived position value.
    static func positionalDraftValue(for position: Position) -> Double {
        switch position {
        case .QB:                            return 1.30
        case .DE, .OLB:                      return 1.10  // EDGE
        case .LT, .RT:                       return 1.05
        case .CB, .WR:                       return 1.00
        case .FS, .SS, .DT, .TE, .MLB:       return 0.85
        case .RB, .C, .LG, .RG:              return 0.70
        case .FB:                            return 0.30
        case .K, .P:                         return 0.20
        }
    }
}
