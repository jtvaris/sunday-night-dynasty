import Foundation
import SwiftData

// MARK: - RosterCutEvaluator

/// Recommends which players to cut for each of the three roster trim days
/// (90→75, 75→65, 65→53). Considers camp grade, OVR, age, contract, and
/// position-group depth. Surfaces practice-squad eligibility and per-cut
/// cap savings / dead cap impact.
@MainActor
enum RosterCutEvaluator {

    // MARK: - Public API

    /// Recommends cut candidates ordered worst-first.
    /// - Parameters:
    ///   - roster: Full team roster (90 / 75 / 65 player array).
    ///   - targetCount: Roster size to trim down to (75 / 65 / 53).
    ///   - modelContext: SwiftData context (used for contract lookups when present).
    /// - Returns: Array of `Player` objects in order of cut priority.
    static func recommendCuts(
        roster: [Player],
        targetCount: Int,
        modelContext: ModelContext
    ) -> [Player] {
        guard roster.count > targetCount else { return [] }

        let cutCount = roster.count - targetCount

        // Score each player on a "keep" axis. Lower score → higher cut priority.
        let scored: [(player: Player, keepScore: Double)] = roster.map { p in
            (player: p, keepScore: keepScore(for: p))
        }

        // Sort ascending by keepScore (worst first).
        let sorted = scored.sorted { $0.keepScore < $1.keepScore }

        // Apply a soft "preserve depth at thin positions" filter:
        // never cut so deep that a position group falls below 1.
        var planned: [Player] = []
        var remainingByPosition: [Position: Int] = [:]
        for p in roster {
            remainingByPosition[p.position, default: 0] += 1
        }

        for entry in sorted {
            guard planned.count < cutCount else { break }
            let pos = entry.player.position
            let remaining = remainingByPosition[pos] ?? 0
            // Never thin a position to below 1 — the UI can let the GM override.
            if remaining <= 1 { continue }
            planned.append(entry.player)
            remainingByPosition[pos] = remaining - 1
        }

        // If depth-protection blocked us from reaching cutCount, fall back to raw worst.
        if planned.count < cutCount {
            for entry in sorted where !planned.contains(where: { $0.id == entry.player.id }) {
                planned.append(entry.player)
                if planned.count >= cutCount { break }
            }
        }

        return planned
    }

    /// Cap savings if player is cut (in thousands).
    /// Falls back to `annualSalary - deadCap(player)` when no detailed contract is available.
    static func capSavings(player: Player) -> Int {
        let dead = deadCap(player: player)
        return max(0, player.annualSalary - dead)
    }

    /// Dead cap incurred (in thousands) — prorated bonus acceleration if cut now.
    /// In the absence of a Contract row, uses a heuristic based on years remaining.
    ///
    /// The heuristic itself moved to `ContractEngine.impliedDeadCap(player:)`
    /// with F-61, and this is now one line rather than two so that there is one
    /// place the AI league's guarantee exposure is derived. The 15 %-per-year
    /// proxy survives as the league MEAN; what it gained is the club's own taste
    /// in guarantees, so an aggressive front office cannot escape a bad signing
    /// as cheaply as an analytics one. See that function for the derivation.
    static func deadCap(player: Player) -> Int {
        ContractEngine.impliedDeadCap(player: player)
    }

    /// Practice-squad eligible? (rookie or <2 accrued seasons.)
    static func isPracticeSquadEligible(player: Player) -> Bool {
        return player.yearsPro <= 2
    }

    // MARK: - Positional integrity (#208a)
    //
    // `recommendCuts` above has always carried a depth guard — it refuses to
    // plan a cut that would empty a position group. It only ever governed the
    // RECOMMENDATION, though: the commit path took whatever the user had ticked
    // and released it, so a club could put all three of its quarterbacks,
    // starter included, on the same cut sheet and the only thing the confirm
    // dialog talked about was money. That is the hole this section closes, and
    // it does it by publishing the guard as a validator the UI can ask BEFORE it
    // commits, rather than by duplicating the rule inside a view.
    //
    // The AI's cut paths read the same floors (#208 G1): `WeekAdvancer.trimAIRosters`
    // and `PracticeSquadEngine.signToActiveRoster` filter their candidate lists
    // through `CapManagementEngine.releaseBlockReason` and skip to the next man
    // rather than refusing at the door — a league sweep that stalls would leave
    // 31 clubs over the ceiling for the rest of the save.

    /// Smallest number of bodies a club must keep at a position.
    ///
    /// **One source, not a second opinion.** The floor for every position is the
    /// same rule the trade validator's positional-integrity check applies
    /// (`TradeValueEngine.validationErrors`, 9a53918): a position that owns a
    /// starter slot in the base personnel must never reach zero. That check
    /// reads `TradeValueEngine.starterSlots`, and so does this one — a position
    /// added to (or dropped from) that table moves both rules together.
    ///
    /// The one position that asks for more than a body is **QB**, at two. A club
    /// that carries one quarterback has no football team the moment he is hurt,
    /// and unlike every other room there is no adjacent position that can cover
    /// the snap. Real clubs carry two into the season for exactly that reason.
    ///
    /// **The floors cannot deadlock the cutdown.** They sum to 20 across the 19
    /// positions (18 × 1 + QB's 2), and the lowest rung on the ladder is 53, so
    /// a club standing over any cut-day ceiling always holds at least 33 men who
    /// are free to go. A gate with no key is the one failure mode a guard like
    /// this must not have.
    ///
    /// **These are the floors for EVERY release** (#208 G1), not just the cut
    /// sheet: the player-detail cut, the contract screen and the cap-compliance
    /// lever all measure against this table through
    /// `CapManagementEngine.releaseBlockReason`. So a 53-man club with two
    /// quarterbacks cannot cut down to one in-season either — it signs or trades
    /// for the replacement FIRST, which is the order a real front office does it
    /// in and the order the block's own wording asks for.
    static func minimumCount(for position: Position) -> Int {
        guard (TradeValueEngine.starterSlots[position] ?? 0) >= 1 else { return 0 }
        return position == .QB ? 2 : 1
    }

    /// What a planned release does to one position room — the confirm dialog's
    /// line, and the row guard's reason in one value.
    struct PositionImpact: Identifiable, Equatable {
        let position: Position
        /// Bodies in the room before the release.
        let before: Int
        /// Bodies left after it.
        let after: Int
        /// Healthy bodies left after it.
        let healthyAfter: Int
        /// The floor this room has to clear — see ``minimumCount(for:)``.
        let minimum: Int

        var id: String { position.rawValue }

        /// The commit would leave this room short — on bodies, or on the one
        /// man who can actually play.
        var isViolation: Bool {
            after < minimum || (minimum >= 1 && healthyAfter < 1)
        }

        /// "QB 3 → 2" — the confirm dialog's per-room line.
        var line: String {
            "\(position.rawValue) \(before) \u{2192} \(after)"
        }
    }

    /// Every position the given release plan touches, worst first.
    ///
    /// `releasing` is a set of player IDs, so the caller can hand over a live
    /// selection without materialising a second roster array.
    static func positionImpacts(roster: [Player], releasing: Set<UUID>) -> [PositionImpact] {
        guard !releasing.isEmpty else { return [] }
        let active = roster.filter { !$0.isRetired }
        let touched = Set(active.filter { releasing.contains($0.id) }.map(\.position))
        guard !touched.isEmpty else { return [] }

        return touched
            .map { position -> PositionImpact in
                let room = active.filter { $0.position == position }
                let kept = room.filter { !releasing.contains($0.id) }
                return PositionImpact(
                    position: position,
                    before: room.count,
                    after: kept.count,
                    healthyAfter: kept.filter { !$0.isInjured }.count,
                    minimum: minimumCount(for: position)
                )
            }
            .sorted { lhs, rhs in
                if lhs.isViolation != rhs.isViolation { return lhs.isViolation }
                return lhs.position.rawValue < rhs.position.rawValue
            }
    }

    /// The rooms a plan would leave short. Empty means the commit is legal.
    static func integrityViolations(roster: [Player], releasing: Set<UUID>) -> [PositionImpact] {
        positionImpacts(roster: roster, releasing: releasing).filter(\.isViolation)
    }

    /// Why this man cannot be added to the cut sheet, or `nil` if he can.
    ///
    /// **Callers come through the door, not here** (#208 G1). This is the rule;
    /// `CapManagementEngine.releaseBlockReason` is the public spelling of it,
    /// and it is what the four release screens and `applyRelease` itself ask.
    /// The difference is only that the door normalises `roster` to the club's
    /// current members first — this function trusts what it is handed.
    ///
    /// Measured against the selection **as it already stands**, so the rooms
    /// close one man at a time as the user works down the list: with three
    /// quarterbacks and a floor of two, the first tick is free, the second locks
    /// the last two rows and says why.
    ///
    /// A man already on the sheet is never blocked — un-ticking him is how the
    /// user gets out of a corner, and a guard that refused that would be a trap.
    static func releaseBlockReason(
        player: Player,
        roster: [Player],
        alreadySelected: Set<UUID>
    ) -> String? {
        guard !alreadySelected.contains(player.id) else { return nil }
        let minimum = minimumCount(for: player.position)
        guard minimum >= 1 else { return nil }

        var planned = alreadySelected
        planned.insert(player.id)
        let room = roster.filter { $0.position == player.position && !$0.isRetired }
        let kept = room.filter { !planned.contains($0.id) }
        let healthy = kept.filter { !$0.isInjured }.count

        // The narrowest true statement first, and an EMPTY room is narrower than
        // a thin one: "last healthy QB" implies there are other quarterbacks in
        // the building, so it is the wrong sentence for the case QA actually
        // walked into, where this man is the only one there is. Once bodies do
        // remain, "last healthy" is the line that has to be said, because a room
        // that still has men in it looks safe.
        //
        // Every sentence ends in the WAY OUT, not in "cannot release". A blocked
        // control that only says no is the shape QA hit on the player-detail cut
        // — a passive note beside a live button — and the user's next question is
        // always "then what do I do". Sign one, or trade for one.
        if kept.isEmpty {
            return "Last \(player.position.rawValue) on the roster \u{2014} sign or trade for another first"
        }
        if healthy < 1 && !player.isInjured {
            return "Last healthy \(player.position.rawValue) \u{2014} sign or trade for another first"
        }
        if kept.count < minimum {
            return "You must carry \(minimum) \(player.position.rawValue)s \u{2014} sign or trade for another first"
        }
        return nil
    }

    // MARK: - Cut priority

    /// Composite "keep this player" score. Higher = safer; lower = closer to cut block.
    ///
    /// Published rather than private because the cut sheet orders its rows by
    /// it. A screen that asks the user to find the twelve worst men in 87
    /// unordered rows is asking him to hold the roster in his head while the
    /// answer sits one function away.
    static func keepScore(for player: Player) -> Double {
        // OVR contribution (0..50)
        let ovrScore = Double(player.overall) * 0.55

        // Camp grade contribution (-10..+15) — graded camp earns a small uplift.
        let gradeScore: Double
        switch player.campGrade {
        case .aPlus: gradeScore = 18.0
        case .a:     gradeScore = 12.0
        case .b:     gradeScore = 5.0
        case .c:     gradeScore = -2.0
        case .d:     gradeScore = -8.0
        case .f:     gradeScore = -12.0
        case nil:    gradeScore = 0.0
        }

        // Age penalty (older = lower keep score for borderline OVRs).
        let agePenalty: Double = {
            switch player.age {
            case ..<25:   return 4.0
            case 25..<29: return 2.0
            case 29..<32: return 0.0
            case 32..<35: return -3.0
            default:      return -7.0
            }
        }()

        // Contract pressure: large salary / high dead-cap → harder to cut.
        // We INVERT this — high salary REDUCES keepScore so big-money under-performers float to the top.
        // BUT a large dead-cap penalty pulls them back as "expensive to release".
        let salaryPenalty = -Double(player.annualSalary) / 5000.0   // -1 per $5M
        let deadCapShield = Double(deadCap(player: player)) / 4000.0 // +1 per $4M dead

        // Injury status drags keep score (you don't keep an injured #80 over a healthy #78).
        let injuryPenalty: Double = player.isInjured ? -6.0 : 0.0

        // Hold-out drama drag — defaults to 0; UI can lift this via personality archetype.
        let dramaPenalty: Double = player.personality.archetype == .dramaQueen ? -3.0 : 0.0

        return ovrScore + gradeScore + agePenalty + salaryPenalty + deadCapShield + injuryPenalty + dramaPenalty
    }
}
