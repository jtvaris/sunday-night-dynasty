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

        // Before the position's decline window nobody walks away — the rare
        // early retirement is out of scope for the sim.
        //
        // The washout ("nobody signed him") is a SEPARATE pass with a separate
        // trigger point: see `evaluateWashouts`. It deliberately does not ride
        // along here, because this pass runs in `.coachingChanges` — three
        // phases BEFORE free agency opens — where `teamID == nil` still means
        // "his contract expired at week 18", not "the phone stopped ringing".
        guard yearsPastPeak >= 0 else { return 0.0 }

        // Base: 4% in the final peak year, then a steepening slope past it.
        //
        // Phase-2 calibration (plan §5 stage 5, `career` harness): at +12 %/yr
        // a 30-season league carried 9.4 % of its players at 33 or older and the
        // average drafted career ran 6.6 seasons, against
        // `DEVELOPMENT_NFL_REFERENCE.md` §8's "≤ ~2 % of players 33+" and
        // "drafted-player average ~5 yrs". Steepening the slope and adding the
        // hard mid-thirties term below is what actually cycles the league.
        var chance = 0.04 + Double(yearsPastPeak) * 0.19

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

        // The mid-thirties wall: careers end for reasons the peak-age window
        // does not capture (money, family, accumulated wear), which is why the
        // reference's age pyramid thins so hard after 32.
        if player.age >= 33 { chance += 0.10 }
        if player.age >= 35 { chance += 0.15 }

        // Age wall: 40+ almost always retires, 41 is the hard ceiling.
        if player.age >= 41 {
            chance = 1.0
        } else if player.age >= 40 {
            chance = max(chance, 0.85)
        }

        return min(1.0, chance)
    }

    // MARK: - Washout (plan §5 stage 6 — the turnover gate)

    /// Fallback replacement level, used when no league sample is available.
    static let washoutReplacementOverall = 72
    /// Where in the ROSTERED league's rating distribution replacement level
    /// sits. A 53-man roster's 30th percentile is roughly its 37th man — the
    /// point at which a club stops looking for a better body.
    ///
    /// This is a percentile and not a constant on purpose. A fixed bar is only
    /// correct for one league level: measured over `MultiSeasonSmokeTest` the
    /// shipped league's rating level rises through the first seasons, and a
    /// frozen 72 stops selecting anybody — the unsigned pool then grows every
    /// season (246 → 574 over five) while the rostered population ages, which
    /// is exactly the ratchet this term exists to prevent. "Replacement level"
    /// is by definition relative to the league.
    static let washoutReplacementPercentile = 0.30
    /// Sanity clamp on the sampled bar, so a freak league cannot make the term
    /// either toothless or a scythe.
    static let washoutReplacementBounds = 66...80
    /// Washout chance added per OVR point below replacement level.
    static let washoutChancePerPoint = 0.085
    /// Hard cap so even a 45-OVR body gets one more tryout cycle sometimes.
    static let washoutCeiling = 0.80

    /// Replacement level sampled off the rostered league (see
    /// `washoutReplacementPercentile`).
    static func replacementOverall(rostered: [Player]) -> Int {
        let ratings = rostered.map(\.overall).sorted()
        guard !ratings.isEmpty else { return washoutReplacementOverall }
        let index = min(
            ratings.count - 1,
            max(0, Int(Double(ratings.count) * washoutReplacementPercentile))
        )
        return min(
            washoutReplacementBounds.upperBound,
            max(washoutReplacementBounds.lowerBound, ratings[index])
        )
    }

    /// Annual "nobody signed him" probability for a player who is still out of
    /// the league once the free-agent market has closed.
    ///
    /// `DEVELOPMENT_NFL_REFERENCE.md` §8 puts league turnover at ~250-300
    /// players a year IN and the same number OUT — "retirements **and
    /// washouts**". Age-driven retirement supplies only ~150 of that, so
    /// without this term the surplus intake never leaves: measured over
    /// `MultiSeasonSmokeTest`, the unsigned pool grew ~120 rows every season
    /// (111 → 228 → 370 after three) and the league's average career ran far
    /// past the reference's ~3.3 years. The `career` harness has always modelled
    /// this — `reshapeRosters` retires anyone it cannot place — and this is the
    /// same rule inside the shipped engine.
    ///
    /// The replacement-level bar is what keeps it honest: a starter-quality
    /// veteran nobody signed is a free agent between contracts and has **zero**
    /// washout chance, and the odds only get real for the depth bodies the pool
    /// actually fills with. Rookies who have not played a season yet are exempt
    /// — a drafted player is under contract, and an undrafted one has not had
    /// his camp.
    ///
    /// **`teamID == nil` is only evidence of anything at the right moment.**
    /// `WeekAdvancer` clears the team of EVERY expiring contract in week 18, so
    /// at the `.coachingChanges` retirement pass a quarter of the league is
    /// technically unsigned — including the user's own players he intends to
    /// re-sign. This roll therefore runs in its own pass at the CLOSE of
    /// `.freeAgency` (`WeekAdvancer.processWashouts`), where an empty `teamID`
    /// really does mean the market passed on him.
    static func washoutProbability(player: Player, replacementOverall: Int) -> Double {
        // A franchise-tagged player is under team control for another year even
        // though the tag never re-stamps `teamID` — he is not on the market.
        guard !player.isFranchiseTagged else { return 0.0 }
        guard player.teamID == nil, player.yearsPro >= 1 else { return 0.0 }
        let deficit = replacementOverall - player.overall
        guard deficit > 0 else { return 0.0 }
        return min(washoutCeiling, Double(deficit) * washoutChancePerPoint)
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
        roll(
            allPlayers: allPlayers,
            peakOverallByPlayerID: peakOverallByPlayerID,
            probability: { retirementProbability(player: $0) }
        )
    }

    /// Rolls the washout ("nobody signed him") for every player who is still
    /// unsigned now that the free-agent market has closed.
    ///
    /// Runs as its own pass, at the END of the `.freeAgency` phase, for the
    /// reason spelled out on `washoutProbability`: at the `.coachingChanges`
    /// retirement pass an empty `teamID` only means the contract expired.
    ///
    /// - Parameters:
    ///   - allPlayers: Every player in the store (retired rows are skipped).
    ///   - rosteredPlayers: The signed population, used to sample replacement
    ///     level (see `replacementOverall(rostered:)`).
    static func evaluateWashouts(
        allPlayers: [Player],
        rosteredPlayers: [Player],
        peakOverallByPlayerID: [UUID: Int]
    ) -> [Retirement] {
        let bar = replacementOverall(rostered: rosteredPlayers)
        return roll(
            allPlayers: allPlayers,
            peakOverallByPlayerID: peakOverallByPlayerID,
            probability: { washoutProbability(player: $0, replacementOverall: bar) }
        )
    }

    /// Shared roll + `Retirement` snapshot for both passes.
    private static func roll(
        allPlayers: [Player],
        peakOverallByPlayerID: [UUID: Int],
        probability: (Player) -> Double
    ) -> [Retirement] {
        var retirements: [Retirement] = []

        for player in allPlayers where !player.isRetired {
            let chance = probability(player)
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

        // Phase 4 faces: hand the portrait back to the pool. `faceID` stays on
        // the row — career history, the retirement ceremony and the Hall of
        // Fame all still render his face — but a two-season cooldown has to
        // pass before anyone else can wear it. Both the retirement pass and the
        // free-agency washout pass land here, so this is the single release
        // point for a player leaving the league.
        FaceLibrary.shared.releaseFace(player.faceID)
    }
}
