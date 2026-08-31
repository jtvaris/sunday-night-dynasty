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
    /// (including its one extra-depth slot, the nickel corner: CB 6). Sums to 53.
    static let targetCounts: [Position: Int] = [
        .QB: 3, .RB: 3, .FB: 1, .WR: 6, .TE: 3,
        .LT: 2, .LG: 2, .C: 2, .RG: 2, .RT: 1,
        .DE: 4, .DT: 3, .OLB: 4, .MLB: 3,
        .CB: 6, .FS: 2, .SS: 2,
        .K: 1, .P: 1, .LS: 1, .H: 1
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
    ///
    /// ## A FOURTH copy of the positional-value table, now derived (F-30/F-71)
    ///
    /// This was a hand-written five-branch table — the fourth independent
    /// spelling of one idea, after `ContractEngine.positionMultiplier` (the
    /// authoritative one), `DraftEngine.teamNeedComponents` and
    /// `FreeAgencyEngine.holePriority`. Its own drift was the same shape as the
    /// two F-30 caught: it paid a corner the same 1.05 as a left tackle and put
    /// a right tackle at 1.00, flat with a guard.
    ///
    /// It now reads `DraftEngine.draftPositionalWeight`, so there is one source
    /// of truth and the inversion cannot come back. The shape is preserved
    /// rather than adopted wholesale: this scorer MULTIPLIES a 40-99 rating,
    /// where the draft board ADDS rating points, so a 0.3...1.6 weight applied
    /// as a factor would not tilt a pool, it would replace it (the mistake
    /// `DraftEngine.aiMakePick`'s own "why the score is a SUM" note records).
    /// ``positionValueTilt`` compresses the shared weight around 1.0 to the
    /// same ±15 % span the hand-written table had.
    static func positionValueMultiplier(_ position: Position) -> Double {
        // The specialist discount survives as a NAMED carve-out, exactly as it
        // does in `aiMakePick`. `ContractEngine` pays a kicker and a fullback
        // the same 0.25, so the shared table cannot tell them apart — and in a
        // 53-round snake that matters, because a kicker is not competing with a
        // guard for a roster spot and must not be taken like one.
        guard position != .K, position != .P else { return specialistMultiplier }
        let weight = DraftEngine.draftPositionalWeight(position)
        return 1.0 + (weight - positionValuePivot) * positionValueTilt
    }

    /// What a kicker or a punter is worth on the fantasy board. Unchanged from
    /// the hand-written table it replaces — it trades "every club fields a
    /// specialist" against "no club spends a useful round on one", and 0.50 has
    /// always put both in the last handful of rounds.
    private static let specialistMultiplier = 0.50

    /// The weight that maps to a neutral ×1.0 here — the league's modal
    /// position on `DraftEngine.draftPositionalWeight`'s scale, and the same
    /// pivot `aiMakePick` subtracts.
    private static let positionValuePivot = 0.8

    /// How much of the shared positional table this scorer expresses.
    ///
    /// Trades positional realism against the fantasy pool staying a *pool*: the
    /// shared weight spans 0.3...1.6, so at 0.19 a quarterback comes out at
    /// ×1.15 and a fullback at ×0.90 — the span the hand-written table had, and
    /// the span 53 snake rounds can absorb. A full-strength tilt here would have
    /// all 32 clubs spending their first four rounds on the same five positions
    /// and nobody able to field a kicker.
    private static let positionValueTilt = 0.19

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
    ///
    /// ## THE SECOND DRAFT BRAIN, AND WHY IT STAYS SECOND (F-71)
    ///
    /// The other one is `DraftEngine.aiMakePick`. The audit asks whether these
    /// should be folded together, because a second scorer "modeled on" the first
    /// is a second scorer that can drift — and it had already drifted, in the
    /// positional table above.
    ///
    /// They stay separate, deliberately, and here is the reason so the next
    /// audit does not re-open it:
    ///
    /// - **Different population.** `aiMakePick` scores `CollegeProspect`s —
    ///   men nobody has seen play a professional snap. This scores `Player`s
    ///   with league tape behind them. That is why there is no fog here and
    ///   must not be: `AIDraftPerception` models a *scouting* error, and there
    ///   is nothing to scout about a man every club in the league has played
    ///   against.
    /// - **No public board.** `aiMakePick`'s single largest term is the media
    ///   consensus anchor (`consensusPullPoints`), and a fantasy re-draft has
    ///   no mock, no projected round and no media. Half the scorer would be
    ///   dead weight.
    /// - **Different shape of decision.** Seven rounds against fifty-three.
    ///   Round 40 of a snake is roster construction, not talent evaluation,
    ///   which is why `needMultiplier` here discounts a filled position to 0.2
    ///   — something that would be badly wrong on a draft board.
    ///
    /// What IS shared is the one thing that was genuinely duplicated: the
    /// positional-value table, now derived from
    /// `DraftEngine.draftPositionalWeight` by ``positionValueMultiplier``. The
    /// F-26 through F-31 wave therefore reaches this brain where it should (the
    /// value ladder) and not where it should not (fog, consensus, round scale).
    ///
    /// House taste (`GMTaste`) is also deliberately absent: it is drawn from a
    /// team UUID, and a fantasy draft runs at CAREER CREATION, before the user
    /// has a franchise identity to be read against or a league to learn one in.
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
        // One specialist rung, the one that already exists. The snapper and the
        // holder are priced with the kicker and the punter everywhere else in
        // the market (`ContractEngine.positionMultiplier`), and a rung of their
        // own here would be a number nothing else in the game agrees with.
        case .K, .P, .LS, .H: topOfMarket = 6_000
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
