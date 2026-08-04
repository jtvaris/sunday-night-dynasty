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

    /// WHY a career ended — the story the news feed tells about a departure.
    ///
    /// Task #84. These are **classifications, not extra retirement rolls**: the
    /// hazard above decides who leaves, and this decides how it reads. See
    /// `classifySpecialCases` for the invariance argument that keeps the
    /// aggregate rate (and with it the a33+ / pyramid calibration) untouched.
    enum RetirementCase: String {
        /// The ordinary path: age, decline, or the market moving on.
        case standard
        /// The Luck case — a body that ran out of road in the middle of a prime
        /// career. Swapped 1:1 against an ordinary retirement, never added.
        case injuryToll
        /// The Donald case — an elite with a full trophy case who walks while
        /// still playing at 90+ rather than declining into the sunset. Pure
        /// relabelling of a man who was already retiring.
        case onTop
    }

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
        /// The flavour the news feed reads (task #84). `var` because the Donald
        /// case relabels an already-decided retirement in place; defaulted so
        /// every existing construction site is unchanged.
        var retirementCase: RetirementCase = .standard
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
    ///
    /// Task #53 raised both (was 0.10 / 0.20). The washout pass is the league's
    /// only real exit besides age retirement, and it was selecting the wrong
    /// men: measured over a 4-season smoke it removed 863 players a year at a
    /// mean age of **25.6**, because the flat `washoutBaseChance` dominated
    /// these surcharges for everybody the market had passed over. An exit door
    /// whose median user is 25 does not thin a 33+ tail, and the 33+ share drifted
    /// +1.7 pp over four seasons while it ran.
    ///
    /// The 27 step is new, and it is the one that reaches the men the §8 80+
    /// band is actually about. The league's excess quality does not sit in its
    /// 33-year-olds — task #53's churn ledger cleared that tail in one wave —
    /// it sits in a 690-man bulge of 26-to-30-year-olds averaging 76 OVR, four
    /// to seven years into careers that nothing removes them from. Age
    /// retirement cannot reach them (they are years short of their position's
    /// decline window) and the quality terms above cannot either (they are well
    /// clear of replacement level). The market passing on a 28-year-old is the
    /// only signal the league has about that man, and 7 %/yr is what it is
    /// worth: small enough that a good player between contracts still comes
    /// back, large enough that the bulge drains instead of compounding.
    static let washoutAge27Chance = 0.07
    static let washoutAge30Chance = 0.16
    static let washoutAge33Chance = 0.32

    /// The second-contract cliff, in years of pro service.
    ///
    /// Age and service are not the same fact and the league's shape needs both.
    /// Task #53's cohort ledger measured a 711-man bulge at four-to-seven years
    /// pro — 42 % of the league, averaging 76 OVR — against a generator
    /// cross-section that carries 29 % there. The generator's league drops
    /// steeply after year three because that is what the NFL does: a drafted
    /// career averages ~5 seasons (`DEVELOPMENT_NFL_REFERENCE.md` §8), which
    /// means most men do not get a third contract. The simulated league had no
    /// such cliff at all — a man who survived his rookie deal was in for life,
    /// because every removal term keyed on age or on rating and he was young
    /// enough and good enough for both.
    ///
    /// So: a man the market has passed over who is already four years in is not
    /// waiting for a better offer, he is being replaced by a cheaper version of
    /// himself. Ramped rather than stepped because the cliff is a slope in the
    /// real data, and capped because a genuinely good player is not finished at
    /// nine years — at that point the age terms above have him anyway.
    static let washoutServiceFrom = 4
    static let washoutServicePerYear = 0.045
    static let washoutServiceCap = 0.20

    /// Years of pro service over which untapped ceiling still buys a man
    /// another camp, and how much of that ceiling counts.
    ///
    /// The other half of the same finding. `washoutProbability` graded a player
    /// purely on where his CURRENT rating sat against replacement level, so a
    /// 23-year-old former fourth-rounder at 62 OVR with an 80 ceiling faced the
    /// same odds as a 29-year-old journeyman at 62 who is exactly what he will
    /// always be. Clubs do not treat those two men alike — the young one is a
    /// camp arm, a practice-squad body, a tryout in August — and the league's
    /// own cutdown day already says so (`RosterValue.upsidePremium`, 0.45 over
    /// three years). This is that rule applied to the exit door, expressed in
    /// the same "OVR points against replacement" currency the quality grace
    /// above already uses, so it fades a young prospect out of the base chance
    /// instead of bolting on a second exemption.
    ///
    /// Deliberately the same 3-year window and a SMALLER credit than the
    /// cutdown's 0.45: a man the market has already passed over is a worse bet
    /// than one still on a 53, so his ceiling has to be worth less here than it
    /// is there. Measured down from 0.50 — at half a point per point of
    /// headroom the pass preserved so many developmental prospects that the
    /// league's first-three-years share sat at 57-60 % through the middle
    /// seasons against §8's 45-55 %, i.e. it fixed one end of the age pyramid
    /// by breaking the other.
    static let washoutUpsideYears = 3
    static let washoutUpsideCredit = 0.28

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
        // Task #53: a developmental player is graded on what he might still be,
        // not only on what he is today — see `washoutUpsideYears`. Folding the
        // credit into the rating the deficit is measured from means a young man
        // with a real ceiling fades out through the SAME quality grace an
        // established starter does, rather than through a parallel exemption.
        var effectiveOverall = Double(player.overall)
        if player.yearsPro <= washoutUpsideYears {
            effectiveOverall += Double(max(0, player.truePotential - player.overall))
                * washoutUpsideCredit
        }

        let deficit = Double(replacementOverall) - effectiveOverall
        var chance: Double
        if deficit >= 0 {
            chance = washoutBaseChance + deficit * washoutChancePerPoint
        } else {
            let surplus = -deficit
            chance = washoutBaseChance * max(0.0, 1.0 - surplus / washoutQualityGrace)
        }

        // Age: the market's silence means something different at 31 than at 25.
        if player.age >= 33 {
            chance += washoutAge33Chance
        } else if player.age >= 30 {
            chance += washoutAge30Chance
        } else if player.age >= 27 {
            chance += washoutAge27Chance
        }

        // Service: the second-contract cliff (see `washoutServiceFrom`).
        chance += min(
            washoutServiceCap,
            Double(max(0, player.yearsPro - washoutServiceFrom)) * washoutServicePerYear
        )

        return min(washoutCeiling, max(0.0, chance))
    }

    // MARK: - Hall of Fame

    /// A retiring player is inducted when his career peak was truly elite,
    /// or near-elite sustained over a long career.
    static func qualifiesForHallOfFame(peakOverall: Int, seasonsPlayed: Int) -> Bool {
        if peakOverall >= 92 { return true }
        return peakOverall >= 88 && seasonsPlayed >= 8
    }

    // MARK: - Special cases (task #84)
    //
    // ============================================================================
    // THE INVARIANCE CONTRACT
    // ============================================================================
    // The retirement hazard above is CALIBRATED — the `career` harness asserts
    // the 33+ age share, the roster mean age, the drafted-career length and the
    // whole §8 quality pyramid against it, and a retirement wave that got even a
    // couple of percent heavier would move all four. So the two "special"
    // retirements below are forbidden from adding a single departure:
    //
    //   • DONALD (`.onTop`) is a **relabel**. It never touches membership: it
    //     reads the list the hazard already produced and renames at most two of
    //     its members. Aggregate rate delta: exactly zero, by construction.
    //
    //   • LUCK (`.injuryToll`) is a **1:1 swap**. When its gate fires it adds
    //     one prime-age man to the list AND removes one — so |retirements| is
    //     bit-for-bit what the hazard produced, in every realization, not merely
    //     in expectation. The removed man is the MARGINAL one (lowest
    //     `retirementProbability` in the list, UUID tie-break), which is also the
    //     equal-probability match the swap asks for: the Luck candidate is by
    //     eligibility a man the hazard scores at or near 0 (he is inside his
    //     position's peak window and under 33), so the nearest slot in the list
    //     is its smallest. Read as a story: one man's body gives out, and the
    //     one veteran who was closest to a coin flip decides to run it back.
    //
    // The residual effect is therefore not on the RATE but on WHICH man leaves,
    // at ≤ `luckGateThousandths`/1000 events per league-season — 0.4/season
    // against ~150 retirements, i.e. ≤0.3 % of the wave, and only when a
    // qualified candidate exists at all. Against the pyramid's 33+ share that is
    // ~0.01 pp of drift, three orders of magnitude inside the ±1.5 pp budget.
    //
    // Everything here is seeded from (careerID, season), never from
    // `Double.random`: a shock retirement that re-rolled every time the offseason
    // was recomputed would be a bug the player could see.
    // ============================================================================

    /// What the trophy case has to hold before "he walked away on top" is a
    /// story rather than a coincidence. Assembled by the caller from league
    /// history (rings) and season history (elite seasons) — the engine stays a
    /// pure function of its arguments and the balance harness stays buildable.
    struct TrophyCase {
        /// Championships won while on the roster of the title team.
        var rings: Int = 0
        /// Seasons finished at or above `starPeakOverall`.
        var eliteSeasons: Int = 0
        /// Already clears the induction bar on career peak alone.
        var isHallOfFameTrack: Bool = false

        /// A résumé with nothing left to prove.
        var isFull: Bool {
            rings >= 1
                && (isHallOfFameTrack
                    || eliteSeasons >= PlayerRetirementEngine.onTopMinEliteSeasons)
        }
    }

    /// The context the special cases need and a `Player` row cannot carry.
    ///
    /// Defaulted to DISABLED so `evaluateRetirements(allPlayers:peakOverallByPlayerID:)`
    /// keeps its old two-argument shape and old behaviour for any caller that
    /// does not opt in.
    struct SpecialCaseContext {
        var isEnabled: Bool = false
        /// SplitMix seed derived from (careerID, season) — see `specialCaseSeed`.
        var seed: UInt64 = 0
        /// Résumé per player. Empty is legal: the Donald case simply finds
        /// nobody eligible, which is the correct answer for a league with no
        /// recorded history yet.
        var trophyCaseByPlayerID: [UUID: TrophyCase] = [:]

        static let disabled = SpecialCaseContext()
    }

    // MARK: Luck case constants

    /// How often the shock retirement is even ALLOWED to happen, in thousandths
    /// of a league-season. 400 = it clears the calendar gate in 2 seasons out of
    /// 5, and a qualified candidate then has to exist on top of that — so the
    /// realized rate is at most ~1 per 2.5 seasons and usually rarer.
    static let luckGateThousandths = 400
    /// Major injuries (6+ weeks) that have to be behind him.
    static let luckMinMajorInjuries = 3
    /// Total career weeks lost to injury — roughly two full seasons of football.
    static let luckMinCareerWeeksOut = 30
    /// A body that has stopped holding up.
    static let luckMaxDurability = 58
    /// Enough of a career that walking away is a loss to the league.
    static let luckMinYearsPro = 4
    static let luckMinAge = 25

    /// Is this man a candidate for the shock retirement?
    ///
    /// Deliberately requires him to be INSIDE his position's peak window and
    /// under the mid-thirties wall — i.e. exactly where `retirementProbability`
    /// scores him at or near zero. That is what makes it a shock rather than an
    /// early draw from the age curve, and it is also why the swap partner below
    /// is the list's minimum: his own hazard is the smallest number in the room.
    static func isInjuryTollCandidate(_ player: Player) -> Bool {
        guard !player.isRetired else { return false }
        guard player.age >= luckMinAge, player.yearsPro >= luckMinYearsPro else { return false }
        guard player.age <= player.position.peakAgeRange.upperBound, player.age < 33 else {
            return false
        }

        // Non-mercenary: the man who is in it for the cheque or the spotlight
        // plays the deal out and lets the club release him. The one who walks
        // in his prime is the one football was never a transaction for.
        let motivation = player.personality.motivation
        guard motivation != .money, motivation != .fame else { return false }

        // Durability before the history reads: `injuryHistory` decodes JSON off
        // the row on every access, and this filter runs over the whole league.
        guard player.physical.durability <= luckMaxDurability else { return false }

        let records = player.injuryHistory
        let major = records.filter { $0.weeksOut >= 6 }.count
        let weeksOut = records.reduce(0) { $0 + $1.weeksOut }
        return major >= luckMinMajorInjuries && weeksOut >= luckMinCareerWeeksOut
    }

    /// How heavy the toll is, for picking the single worst-off candidate.
    static func injuryTollBurden(_ player: Player) -> Int {
        let records = player.injuryHistory
        let weeksOut = records.reduce(0) { $0 + $1.weeksOut }
        let major = records.filter { $0.weeksOut >= 6 }.count
        return weeksOut + major * 6 + max(0, 60 - player.physical.durability)
    }

    // MARK: Donald case constants

    /// Hard ceiling on "goes out on top" stories per offseason, league-wide.
    static let onTopMaxPerSeason = 2
    static let onTopMinAge = 30
    /// Still elite at the moment he walks — this is the whole point of the case.
    static let onTopMinOverall = 90
    /// Elite seasons that stand in for a Hall of Fame track when the peak alone
    /// does not clear the induction bar.
    static let onTopMinEliteSeasons = 4
    /// Even a man with the full résumé usually just fades. Percent of eligible
    /// elites who actually get the "walked away on top" framing.
    static let onTopGatePercent = 60

    // MARK: Deterministic seeding

    /// (careerID, season) → the stream every special case draws from. FNV-1a over
    /// the UUID bytes, stirred with the SplitMix64 constant — the same shape
    /// `ScoutingEngine` and `LeagueTemplateImporter` already use.
    static func specialCaseSeed(careerID: UUID, season: Int) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: careerID.uuid) { raw in
            for byte in raw {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
        }
        return hash ^ (UInt64(bitPattern: Int64(season)) &* 0x9E37_79B9_7F4A_7C15)
    }

    /// SplitMix64 finalizer — the whole generator, since every gate here needs
    /// exactly one draw.
    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A stable per-player salt, so a given man's gate answers the same way for
    /// a given season no matter what order the league is iterated in.
    private static func playerSalt(_ id: UUID) -> UInt64 {
        var hash: UInt64 = 0x84222325_cbf29ce4
        withUnsafeBytes(of: id.uuid) { raw in
            for byte in raw {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
        }
        return hash
    }

    // MARK: Classification

    /// Turns the hazard's verdict into the hazard's verdict PLUS a story.
    ///
    /// Order is load-bearing: the Luck swap runs first (it changes membership by
    /// +1/−1), then the Donald relabel reads the final list. See the invariance
    /// contract at the top of this section.
    static func classifySpecialCases(
        retirements: [Retirement],
        allPlayers: [Player],
        peakOverallByPlayerID: [UUID: Int],
        special: SpecialCaseContext
    ) -> [Retirement] {
        guard special.isEnabled, !retirements.isEmpty else { return retirements }
        var result = retirements

        // ---- 1. LUCK: the 1:1 swap -----------------------------------------
        if mix(special.seed &+ 0x4C55_434B) % 1000 < UInt64(luckGateThousandths) {
            let retiringIDs = Set(result.map { $0.player.id })
            let candidates = allPlayers
                .filter { !retiringIDs.contains($0.id) && isInjuryTollCandidate($0) }

            // Worst toll wins; UUID breaks ties so the pick never depends on
            // fetch order.
            let chosen = candidates.max { a, b in
                let ba = injuryTollBurden(a), bb = injuryTollBurden(b)
                if ba != bb { return ba < bb }
                return a.id.uuidString < b.id.uuidString
            }

            // The partner: the most marginal retirement on the board. `min` over
            // the SAME hazard the list was built from, UUID tie-break.
            let partnerIndex = result.indices.min { a, b in
                let pa = retirementProbability(player: result[a].player)
                let pb = retirementProbability(player: result[b].player)
                if pa != pb { return pa < pb }
                return result[a].player.id.uuidString < result[b].player.id.uuidString
            }

            // Both halves or neither — a Luck retirement with nothing to swap
            // against would be exactly the extra roll this design forbids.
            if let chosen, let partnerIndex {
                result.remove(at: partnerIndex)
                result.append(snapshot(
                    player: chosen,
                    peakOverallByPlayerID: peakOverallByPlayerID,
                    retirementCase: .injuryToll
                ))
            }
        }

        // ---- 2. DONALD: the relabel ----------------------------------------
        let eligible = result.indices.filter { index in
            // Never relabel a man the Luck case already claimed: the two stories
            // are mutually exclusive, and "goes out on top" is the wrong caption
            // on a career a body ended.
            guard result[index].retirementCase == .standard else { return false }
            let player = result[index].player
            guard player.age >= onTopMinAge, player.overall >= onTopMinOverall else { return false }
            guard let trophies = special.trophyCaseByPlayerID[player.id], trophies.isFull else {
                return false
            }
            return mix(special.seed &+ playerSalt(player.id)) % 100 < UInt64(onTopGatePercent)
        }
        .sorted { a, b in
            let pa = result[a], pb = result[b]
            if pa.peakOverall != pb.peakOverall { return pa.peakOverall > pb.peakOverall }
            return pa.player.id.uuidString < pb.player.id.uuidString
        }

        for index in eligible.prefix(onTopMaxPerSeason) {
            result[index].retirementCase = .onTop
        }

        return result
    }

    // MARK: - Comeback (task #84, case 3)
    //
    // The one door that swings the other way. It is NOT part of the invariance
    // contract above — an un-retirement is an INFLOW, and the calibrated numbers
    // are about outflow — but it is held to the same rarity discipline, because
    // a league where legends routinely un-retire is a league with no stakes.
    //
    // Feasibility note (why this is implementable at all): `retire` never
    // deletes the `Player` row, it flags it (`isRetired = true`) and hands back
    // the face. Every attribute, every history row and the face itself are still
    // there, so bringing a man back is a flag flip plus an honest ageing pass —
    // no reconstruction from Hall of Fame snapshots required.

    /// Thousandths of a league-season in which the comeback gate opens at all.
    /// 450 with a candidate AND a contender-with-room both required on top puts
    /// the realized rate at roughly one per two seasons, often none.
    static let comebackGateThousandths = 450
    /// He has to still be recognisably the same player — two seasons away, no
    /// more. Season 3 is a different man.
    static let comebackMaxSeasonsAway = 2
    /// Only a genuine star is worth a roster spot and a ring-chasing headline.
    static let comebackMinPeakOverall = 88
    static let comebackMaxAge = 38
    /// What "contender" means: a real playoff team from the season just played.
    static let comebackContenderWins = 11
    /// A one-year, prove-it deal, in thousands — comfortably inside any
    /// contender's cap room and never a franchise-altering commitment.
    static let comebackSalary = 4_000

    /// Does the calendar even allow a comeback this offseason?
    static func comebackGateFires(seed: UInt64) -> Bool {
        mix(seed &+ 0x434F_4D45) % 1000 < UInt64(comebackGateThousandths)
    }

    /// Is this retired man a plausible returnee?
    ///
    /// - Parameters:
    ///   - seasonsAway: Seasons between his retirement and this offseason.
    ///   - peakOverall: Career peak from `PlayerSeasonHistory`.
    ///   - retirementCase: The Luck case never comes back. His body is the whole
    ///     reason he left, and undoing that would make the shock meaningless.
    static func isComebackCandidate(
        player: Player,
        seasonsAway: Int,
        peakOverall: Int,
        retirementCase: RetirementCase
    ) -> Bool {
        guard player.isRetired, player.teamID == nil else { return false }
        guard retirementCase != .injuryToll else { return false }
        guard seasonsAway >= 1, seasonsAway <= comebackMaxSeasonsAway else { return false }
        guard peakOverall >= comebackMinPeakOverall else { return false }
        return player.age + seasonsAway <= comebackMaxAge
    }

    /// Brings a retired player back onto a roster at an age- and rust-appropriate
    /// rating, and returns the OVR he lost while he was gone.
    ///
    /// The ageing half is the SHIPPED decline curve, not a bespoke penalty: one
    /// `applyAgeRegression` per season away, then the service credit those calls
    /// added is taken back off, because sitting on a couch is not a pro season.
    /// The rust on top is the part ageing does not model — a man who has not been
    /// hit since his last game is not in football shape, and it costs him
    /// conditioning and sharpness before it costs him talent.
    @discardableResult
    static func unretire(
        _ player: Player,
        seasonsAway: Int,
        teamID: UUID
    ) -> Int {
        let before = player.overall

        for _ in 0..<max(0, seasonsAway) {
            PlayerDevelopmentEngine.applyAgeRegression(player)
        }
        // He aged; he did not accrue service. Hand the years back.
        player.yearsPro = max(0, player.yearsPro - max(0, seasonsAway))

        let rust = 2 * max(1, seasonsAway)
        player.physical.speed = max(1, player.physical.speed - rust)
        player.physical.acceleration = max(1, player.physical.acceleration - rust)
        player.physical.agility = max(1, player.physical.agility - rust)
        player.physical.stamina = max(1, player.physical.stamina - rust)
        player.mental.awareness = max(1, player.mental.awareness - rust / 2)

        player.isRetired = false
        player.teamID = teamID
        player.contractYearsRemaining = 1
        player.annualSalary = comebackSalary
        player.isHoldingOut = false
        player.isFranchiseTagged = false
        player.isInjured = false
        player.injuryWeeksRemaining = 0
        player.injuryType = nil
        player.rehabStatus = nil
        player.rushBackWeeksRemaining = 0
        player.fatigue = 0
        player.loyaltyYears = 0
        player.gamesPlayedThisSeason = 0
        player.gamesStartedThisSeason = 0

        // `retire` handed his portrait back to the pool with a two-season
        // cooldown. He is a person again, so he takes it back — and if the
        // cooldown already let somebody else have it, the library re-draws.
        player.faceID = FaceLibrary.shared.claimFace(
            player.faceID,
            personID: player.id,
            role: .player,
            age: player.age,
            position: player.position
        ) ?? player.faceID

        return max(0, before - player.overall)
    }

    // MARK: - Evaluation

    /// Rolls retirement for every eligible player and returns the decided
    /// retirements (no mutation yet — call `retire(_:teamsByID:)` per result).
    ///
    /// - Parameters:
    ///   - allPlayers: Every player in the store (retired rows are skipped).
    ///   - peakOverallByPlayerID: Max end-of-season OVR per player from
    ///     `PlayerSeasonHistory` (missing entries fall back to current OVR).
    ///   - special: Task #84's story layer. Defaulted to `.disabled`, and even
    ///     when enabled it cannot change how many men retire — see the
    ///     invariance contract above `classifySpecialCases`.
    static func evaluateRetirements(
        allPlayers: [Player],
        peakOverallByPlayerID: [UUID: Int],
        special: SpecialCaseContext = .disabled
    ) -> [Retirement] {
        let decided = roll(
            allPlayers: allPlayers,
            peakOverallByPlayerID: peakOverallByPlayerID,
            probability: { retirementProbability(player: $0) }
        )
        return classifySpecialCases(
            retirements: decided,
            allPlayers: allPlayers,
            peakOverallByPlayerID: peakOverallByPlayerID,
            special: special
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

            retirements.append(snapshot(
                player: player,
                peakOverallByPlayerID: peakOverallByPlayerID,
                retirementCase: .standard
            ))
        }

        return retirements
    }

    /// The career facts a departure carries, frozen at decision time. Shared so
    /// the Luck case's man is snapshotted by exactly the same rule as everybody
    /// the hazard picked — including the Hall of Fame test, which a prime-career
    /// legend forced out by his body can absolutely still pass.
    private static func snapshot(
        player: Player,
        peakOverallByPlayerID: [UUID: Int],
        retirementCase: RetirementCase
    ) -> Retirement {
        let peak = max(peakOverallByPlayerID[player.id] ?? 0, player.overall)
        return Retirement(
            player: player,
            peakOverall: peak,
            isStar: peak >= starPeakOverall,
            isHallOfFamer: qualifiesForHallOfFame(
                peakOverall: peak,
                seasonsPlayed: player.yearsPro
            ),
            teamIDAtRetirement: player.teamID,
            retirementCase: retirementCase
        )
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
        FaceLibrary.shared.releaseFace(player.faceID, heldBy: player.id)
    }
}
