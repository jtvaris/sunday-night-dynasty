import Foundation

/// R40 — Fantasy Draft mode.
///
/// Pure logic for the career-creation fantasy draft: all 1,696 generated
/// players (32 teams × 53) enter one pool and every team re-drafts a 53-man
/// roster in snake order. The user drafts their own picks through the
/// interactive rounds; everything after that (and every AI pick) runs through
/// `aiPickIndex`, a need+value scorer modeled on R24's `DraftEngine.aiMakePick`
/// (weighted-random among the top of the need-adjusted board).
///
/// Contracts are regenerated OVR-based (`fantasyContract`) so the resulting
/// rosters stay compatible with every cap mode, then normalized per team to a
/// sane share of the cap.
enum FantasyDraftEngine {

    // MARK: - Constants

    /// Full roster size — also the number of snake rounds (32 picks each).
    static let rosterSize = 53

    /// The user drafts rounds 1...25 by hand; rounds 26...53 are auto-filled
    /// with the same AI need+value logic (53 interactive rounds would be an
    /// unreasonable UI marathon — documented in the round notes).
    static let interactiveRounds = 25

    /// Positional targets mirroring `LeagueGenerator.rosterBlueprint`
    /// (including the three extra-depth slots: WR 7, DE 5, CB 6). Sums to 53.
    static let targetCounts: [Position: Int] = [
        .QB: 3, .RB: 3, .FB: 1, .WR: 7, .TE: 3,
        .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 1,
        .DE: 5, .DT: 3, .OLB: 4, .MLB: 3,
        .CB: 6, .FS: 2, .SS: 2,
        .K: 1, .P: 1
    ]

    // MARK: - Pool Entry

    /// Lightweight scoring snapshot of a pool player. `Player.overall`
    /// recomputes weighted averages on every access, so the draft loop
    /// (~1.4M score evaluations) works off this frozen copy instead.
    struct PoolEntry: Identifiable, Equatable {
        let player: Player
        let name: String
        let position: Position
        let overall: Int
        let potential: Int
        let age: Int

        var id: UUID { player.id }

        init(player: Player) {
            self.player = player
            self.name = player.fullName
            self.position = player.position
            self.overall = player.overall
            self.potential = player.truePotential
            self.age = player.age
        }

        static func == (lhs: PoolEntry, rhs: PoolEntry) -> Bool {
            lhs.player.id == rhs.player.id
        }
    }

    // MARK: - Snake Order

    /// Team order for a given 1-based round: odd rounds use the base order,
    /// even rounds reverse it.
    static func order(forRound round: Int, baseOrder: [UUID]) -> [UUID] {
        round % 2 == 1 ? baseOrder : baseOrder.reversed()
    }

    // MARK: - Need + Value Scoring

    /// Positional draft-value weighting: QBs and premium positions rise,
    /// specialists and fullbacks sink toward the late rounds.
    static func positionValueMultiplier(_ position: Position) -> Double {
        switch position {
        case .QB:                return 1.15
        case .DE, .LT, .WR, .CB: return 1.05
        case .K, .P:             return 0.50
        case .FB:                return 0.60
        default:                 return 1.00
        }
    }

    /// Need multiplier from the blueprint deficit: unfilled positions score
    /// up to +40%; positions already at target are heavily discounted so a
    /// team never hoards one spot.
    static func needMultiplier(position: Position, rosterCounts: [Position: Int]) -> Double {
        let target = targetCounts[position] ?? 1
        let have = rosterCounts[position] ?? 0
        guard have < target else { return 0.2 }
        return 1.0 + 0.4 * Double(target - have) / Double(max(1, target))
    }

    /// Picks the pool index for an AI selection using need+value scoring and
    /// R24-style weighted randomness (board-topper ~65% of the time).
    /// Returns `nil` only for an empty pool.
    static func aiPickIndex(
        pool: [PoolEntry],
        rosterCounts: [Position: Int],
        round: Int
    ) -> Int? {
        guard !pool.isEmpty else { return nil }

        var scored: [(index: Int, score: Double)] = []
        scored.reserveCapacity(pool.count)

        for (index, entry) in pool.enumerated() {
            var score = Double(entry.overall)
            score *= positionValueMultiplier(entry.position)
            score *= needMultiplier(position: entry.position, rosterCounts: rosterCounts)
            // Ceiling matters a little (mirrors aiMakePick's potential bump).
            score += Double(entry.potential) * 0.10
            // Youth preference: post-prime players slide slightly.
            score -= Double(max(0, entry.age - 27)) * 0.8
            // QB premium when the QB room is still empty.
            if entry.position == .QB && (rosterCounts[.QB] ?? 0) == 0 && round <= 8 {
                score *= 1.10
            }
            scored.append((index, score))
        }

        let ranked = scored.sorted { $0.score > $1.score }
        let candidates = Array(ranked.prefix(4))
        let weights: [Double] = [0.65, 0.20, 0.10, 0.05]
        var roll = Double.random(in: 0..<1)
        for (offset, candidate) in candidates.enumerated() {
            roll -= weights[min(offset, weights.count - 1)]
            if roll < 0 { return candidate.index }
        }
        return candidates[0].index
    }

    // MARK: - Contracts

    /// OVR-based fantasy contract (salary in thousands). A 95+ OVR franchise
    /// QB lands near the real top of the market; depth bodies bottom out at
    /// the $750K minimum. Years follow age (young = longer deals).
    static func fantasyContract(
        overall: Int,
        age: Int,
        position: Position
    ) -> (salary: Int, years: Int) {
        let topOfMarket: Double
        switch position {
        case .QB:            topOfMarket = 55_000
        case .WR:            topOfMarket = 35_000
        case .DE:            topOfMarket = 33_000
        case .LT:            topOfMarket = 28_000
        case .OLB, .CB:      topOfMarket = 25_000
        case .RT, .DT:       topOfMarket = 22_000
        case .MLB:           topOfMarket = 20_000
        case .FS, .SS, .TE:  topOfMarket = 16_000
        case .LG, .RG, .C:   topOfMarket = 16_000
        case .RB:            topOfMarket = 14_000
        case .K, .P:         topOfMarket = 6_000
        case .FB:            topOfMarket = 4_000
        }

        // 55 OVR → minimum; 95 OVR → top of market. Power curve keeps the
        // middle class affordable so 53 contracts fit under the cap.
        let t = min(1.0, max(0.0, Double(overall - 55) / 40.0))
        let salary = max(750, Int(topOfMarket * pow(t, 1.8)))

        let years: Int
        switch age {
        case ..<26:   years = Int.random(in: 3...4)
        case 26...29: years = Int.random(in: 2...3)
        default:      years = Int.random(in: 1...2)
        }
        return (salary, years)
    }

    /// Scales a completed roster's salaries down when the OVR-based contracts
    /// overshoot the cap target, so every fantasy team starts cap-legal in
    /// simple/realistic cap modes. Never scales up (a cheap young roster is a
    /// legitimate outcome). Returns the final cap usage in thousands.
    @discardableResult
    static func normalizeSalaries(for players: [Player], cap: Int) -> Int {
        let target = Int(Double(cap) * Double.random(in: 0.86...0.93))
        let total = players.reduce(0) { $0 + $1.annualSalary }
        if total > target && total > 0 {
            let ratio = Double(target) / Double(total)
            for player in players {
                player.annualSalary = max(750, Int((Double(player.annualSalary) * ratio).rounded()))
            }
        }
        return players.reduce(0) { $0 + $1.annualSalary }
    }
}
