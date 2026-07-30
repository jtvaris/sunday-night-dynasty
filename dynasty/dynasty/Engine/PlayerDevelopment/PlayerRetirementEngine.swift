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

        // Base: 4% in the final peak year, then a steepening slope past it.
        //
        // Phase-2 calibration (plan §5 stage 5, `career` harness): at +12 %/yr
        // a 30-season league carried 9.4 % of its players at 33 or older and the
        // average drafted career ran 6.6 seasons, against
        // `DEVELOPMENT_NFL_REFERENCE.md` §8's "≤ ~2 % of players 33+" and
        // "drafted-player average ~5 yrs". Steepening the slope and adding the
        // hard mid-thirties term below is what actually cycles the league.
        //
        // Before the position's decline window nobody walks away for FOOTBALL
        // reasons — the rare early retirement is out of scope for the sim — but
        // the calendar terms below still apply. See the wall note there.
        //
        // The washout ("nobody signed him") is a SEPARATE pass with a separate
        // trigger point: see `evaluateWashouts`. It deliberately does not ride
        // along here, because this pass runs in `.coachingChanges` — three
        // phases BEFORE free agency opens — where `teamID == nil` still means
        // "his contract expired at week 18", not "the phone stopped ringing".
        var chance = 0.0
        if yearsPastPeak >= 0 {
            chance = 0.04 + Double(yearsPastPeak) * 0.19

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
        }

        // The mid-thirties wall: careers end for reasons the peak-age window
        // does not capture (money, family, accumulated wear), which is why the
        // reference's age pyramid thins so hard after 32.
        //
        // **Task #28 — this used to sit behind `guard yearsPastPeak >= 0`, which
        // made it unreachable for exactly the positions it was written for.** A
        // quarterback peaks to 35 and a kicker to 38, so a 33-year-old at either
        // was still inside his window, took the early return, and carried a
        // retirement probability of precisely ZERO. Those two rooms are 128 of
        // the league's ~1 700 men and nothing could ever remove them: measured
        // over `MultiSeasonSmokeTest` the 33+ share climbed 0.5 % → 3.2 % → 5.3 %
        // across three seasons against §8's ≤ ~2 %, and the veterans it stacked
        // (yp8+ averaged 79.9 OVR) dragged the 80+ band out with them.
        //
        // The wall is a statement about the CALENDAR, not about the position's
        // peak, so it is now applied to everybody. A 33-year-old quarterback
        // inside his peak window faces 12 %/yr rather than 0 %; a 36-year-old
        // one, past it, faces 0.04 + 0.19 + 0.30 = 53 %.
        //
        // Rates re-derived in the same wave (was +0.10 / +0.15, and the 37 step
        // is new). The flat pair was solved against a curve that only the
        // early-decline positions ever reached; once the late-peak rooms are
        // inside the wall it has to carry them on its own, and at +0.12/+0.18 it
        // did not — the 33+ share still climbed 1.1 % → 1.9 % → 3.2 % → 5.0 %
        // over four measured seasons, with quarterbacks, offensive linemen and
        // specialists supplying 45 of the last 84.
        //
        // At these rates a 33-year-old faces 18 %/yr, a 35-year-old 43 % and a
        // 37-year-old 73 %, which leaves him ~2.2 further seasons on average —
        // the shape §8's pyramid describes, and still loose enough that a great
        // quarterback can play to 38.
        if player.age >= 33 { chance += 0.18 }
        if player.age >= 35 { chance += 0.25 }
        if player.age >= 37 { chance += 0.30 }

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

    /// Baseline "a full league year went by and nobody called" chance, before
    /// quality and age (task #32).
    ///
    /// The term used to be purely relative — only a player BELOW replacement
    /// level could ever wash out — which quietly made the unsigned pool a
    /// permanent reservoir of usable football players. Measured over
    /// `MultiSeasonSmokeTest`, it grew 230 → 336 → 394 → 497 across four seasons
    /// while every roster stayed at 53, and that reservoir is what inverted the
    /// §8 quality pyramid: free agency and `WeekAdvancer.refillAIRosters` both
    /// sign the BEST available body, so every season the league swapped its
    /// depth tier for somebody better out of the pool. The sub-65 share fell
    /// 25.8 % → 16.5 % and the 80+ share climbed 17.6 % → 22.4 % — not because
    /// players developed faster, but because the bottom of the league was being
    /// quietly filtered out of the rostered population the pyramid measures.
    ///
    /// §8 puts turnover at ~250-300 in and the same number out. The draft alone
    /// brings ~250 in, so "out" has to be a real number every year, and going
    /// unsigned through an entire market is the honest trigger for it.
    static let washoutBaseChance = 0.30

    /// How many OVR points above replacement level buy a player his way out of
    /// the base chance entirely. A man that much better than the last roster
    /// spot in the league is between contracts, not out of football.
    static let washoutQualityGrace = 8.0

    /// Age surcharges on an unsigned player. An unsigned 30-year-old is a
    /// depth signing waiting to happen; an unsigned 33-year-old is retired and
    /// has not said so yet.
    static let washoutAge30Chance = 0.10
    static let washoutAge33Chance = 0.20

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

        // Quality: below replacement level the odds climb per point, exactly as
        // before. Above it, the base fades out over `washoutQualityGrace` points
        // — the sliding version of the old "a good player never washes out",
        // which was true as an absolute and false as a model (see
        // `washoutBaseChance`).
        let deficit = replacementOverall - player.overall
        var chance: Double
        if deficit >= 0 {
            chance = washoutBaseChance + Double(deficit) * washoutChancePerPoint
        } else {
            let surplus = Double(-deficit)
            chance = washoutBaseChance * max(0.0, 1.0 - surplus / washoutQualityGrace)
        }

        // Age: the market's silence means something different at 31 than at 25.
        if player.age >= 33 {
            chance += washoutAge33Chance
        } else if player.age >= 30 {
            chance += washoutAge30Chance
        }

        return min(washoutCeiling, max(0.0, chance))
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
