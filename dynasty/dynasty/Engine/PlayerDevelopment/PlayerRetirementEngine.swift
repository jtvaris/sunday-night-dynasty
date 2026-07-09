import Foundation

// MARK: - PlayerRetirementEngine (R32)

/// Stateless engine that decides which players hang up their cleats each
/// offseason and applies the retirement to the league state.
///
/// Runs once per offseason in the `.coachingChanges` phase (before free
/// agency, matching the real NFL calendar) over EVERY non-retired player —
/// rostered veterans, holdouts, and unsigned free agents alike — so nobody
/// plays forever and the FA pool doesn't fill with ageless veterans.
///
/// Explainable model:
/// - The base chance is driven by how far past the POSITION's peak-age
///   window the player is (RBs face the cliff around 29, QBs closer to 36,
///   using the same `Position.peakAgeRange` the development/regression
///   engines already use — no parallel aging curve).
/// - Fading play (low current OVR), a long R28 injury history, a currently
///   rehabbing injury, and a broken-down body (low durability) all push a
///   player toward retirement.
/// - Kickers and punters hang on roughly twice as long.
/// - Nobody plays past 41: the age wall guarantees the league keeps cycling.
enum PlayerRetirementEngine {

    // MARK: - Types

    /// One retirement decided this offseason, with the career facts needed
    /// for news / Hall of Fame processing snapshotted at decision time.
    struct Retirement {
        let player: Player
        /// Best end-of-season OVR across the career (falls back to current).
        let peakOverall: Int
        /// League-wide star: gets a ceremony headline (peak OVR >= 88).
        let isStar: Bool
        /// Hall of Fame induction (see `qualifiesForHallOfFame`).
        let isHallOfFamer: Bool
        /// Team the player retired from (nil = unsigned free agent).
        let teamIDAtRetirement: UUID?
    }

    /// Peak OVR that makes a retirement a league-wide "star" story.
    static let starPeakOverall = 88

    // MARK: - Probability

    /// Annual retirement probability for one player (0...0.97).
    static func retirementProbability(player: Player) -> Double {
        let peakRange = player.position.peakAgeRange
        let yearsPastPeak = player.age - peakRange.upperBound

        // Before the position's decline window nobody walks away
        // (the rare early retirement is out of scope for the sim).
        guard yearsPastPeak >= 0 else { return 0.0 }

        // Base: 4% in the final peak year, +12% per year past it.
        var chance = 0.04 + Double(yearsPastPeak) * 0.12

        // Fading play: the league has moved on.
        if player.overall < 60 {
            chance += 0.20
        } else if player.overall < 68 {
            chance += 0.08
        }

        // R28 injury history: every major injury (6+ weeks) leaves a mark.
        let majorInjuries = player.injuryHistory.filter { $0.weeksOut >= 6 }.count
        chance += Double(min(majorInjuries, 4)) * 0.05

        // Currently rehabbing into the offseason.
        if player.isInjured { chance += 0.10 }

        // Body breaking down.
        if player.physical.durability < 50 { chance += 0.08 }

        // Kickers and punters age gracefully.
        if player.position == .K || player.position == .P {
            chance *= 0.5
        }

        // Age wall: 40+ almost always retires, 41 is the hard ceiling.
        if player.age >= 41 {
            chance = 1.0
        } else if player.age >= 40 {
            chance = max(chance, 0.85)
        }

        return min(1.0, chance)
    }

    // MARK: - Hall of Fame

    /// A retiring player is inducted when his career peak was truly elite,
    /// or near-elite sustained over a long career.
    static func qualifiesForHallOfFame(peakOverall: Int, seasonsPlayed: Int) -> Bool {
        if peakOverall >= 92 { return true }
        return peakOverall >= 88 && seasonsPlayed >= 8
    }

    // MARK: - Evaluation

    /// Rolls retirement for every eligible player and returns the decided
    /// retirements (no mutation yet — call `retire(_:teamsByID:)` per result).
    ///
    /// - Parameters:
    ///   - allPlayers: Every player in the store (retired rows are skipped).
    ///   - peakOverallByPlayerID: Max end-of-season OVR per player from
    ///     `PlayerSeasonHistory` (missing entries fall back to current OVR).
    static func evaluateRetirements(
        allPlayers: [Player],
        peakOverallByPlayerID: [UUID: Int]
    ) -> [Retirement] {
        var retirements: [Retirement] = []

        for player in allPlayers where !player.isRetired {
            let chance = retirementProbability(player: player)
            guard chance > 0, Double.random(in: 0.0..<1.0) < chance else { continue }

            let peak = max(peakOverallByPlayerID[player.id] ?? 0, player.overall)
            retirements.append(Retirement(
                player: player,
                peakOverall: peak,
                isStar: peak >= starPeakOverall,
                isHallOfFamer: qualifiesForHallOfFame(
                    peakOverall: peak,
                    seasonsPlayed: player.yearsPro
                ),
                teamIDAtRetirement: player.teamID
            ))
        }

        return retirements
    }

    // MARK: - Application

    /// Applies one retirement: frees the roster spot and cap space, clears
    /// every transient flag, and marks the player retired. The Player row is
    /// kept (career history / HOF views read it) but every pool filter
    /// excludes `isRetired` players.
    static func retire(_ retirement: Retirement, teamsByID: [UUID: Team]) {
        let player = retirement.player

        if let teamID = player.teamID, let team = teamsByID[teamID] {
            team.currentCapUsage -= player.annualSalary
        }

        player.isRetired = true
        player.teamID = nil
        player.annualSalary = 0
        player.contractYearsRemaining = 0
        player.isFranchiseTagged = false
        player.isHoldingOut = false
        player.trainingFocusArea = nil
        player.trainingPosition = nil

        // Close out any open injury — the career is over, so the weekly
        // rehab loop and return-decision flow must never pick him up again.
        player.isInjured = false
        player.injuryWeeksRemaining = 0
        player.injuryType = nil
        player.rehabStatus = nil
        player.rushBackWeeksRemaining = 0
        player.fatigue = 0
    }
}
