import Foundation

/// Per-club draft FOG: what one AI front office *thinks* a prospect is, as
/// opposed to what he is.
///
/// ## Why this exists
///
/// Before this file the AI draft scorer (`DraftEngine.aiMakePick`) read
/// `prospect.trueOverall` / `prospect.truePotential` straight off the model —
/// the ground truth the game itself uses to develop the player years later. All
/// 31 AI clubs therefore shared one perfect board, drafted it in near-lockstep,
/// and the user's entire scouting department was a machine for re-discovering
/// what every rival already knew. There were no busts, no steals, and no reason
/// to spend a scouting budget.
///
/// A club now sees `true + error`, where the error is:
/// - **deterministic** per `(team, prospect)` pair — the same front office
///   misjudges the same player the same way at pick 3 and at pick 190, and
///   across app launches, saves and re-entries into the draft room. Nothing is
///   stored: the draw is a pure function of the two UUIDs (the `AgentPersona` /
///   `GMPersona` trick — never `hashValue`, whose seed changes every launch);
/// - **persona-shaped** — σ comes from the club's `TradeValueEngine.GMPersona`
///   archetype, so the analytics shop that hoards draft capital is also the one
///   with the tightest board, and the old-school room that spends picks at
///   chart price is the one most likely to be wrong about who it spent them on;
/// - **fat-tailed** — ~7 % of pairs carry an extra ±8-14 misread on top of the
///   Gaussian. That tail, not σ, is what produces the top-10 bust and the
///   fifth-round steal; a pure Gaussian at σ ≈ 4.5 essentially never moves a
///   prospect 20 board slots.
///
/// ## What is deliberately NOT fogged
///
/// - the **user's** picks (he drafts off his own scouting reports — see
///   `ProspectFog` / `DraftIntel`);
/// - **trade** valuations. `DraftDayTradeEngine` prices PICKS off the Jimmy
///   Johnson chart and ranks the board off `publicBoardRanks` (consensus), so
///   the war-room market keeps working untouched and no hidden number leaks
///   into a trade quote;
/// - `draftProjection`, the public consensus slot. That is the market's opinion
///   and every club sees the same one — it is the anchor the private read
///   deviates FROM.
enum AIDraftPerception {

    // MARK: - Tuning

    /// σ of a club's read on a prospect's CURRENT level, in OVR points, by GM
    /// archetype.
    ///
    /// The analytics room is not "smarter", it is more disciplined: it grades
    /// off a process and lands near the truth. The old-school room falls in
    /// love with tape. `aggressive` sits between the two — he does not have a
    /// worse process than average, he simply cares less about the grade than
    /// about the splash.
    static func sigmaOverall(for archetype: TradeValueEngine.GMArchetype) -> Double {
        switch archetype {
        case .analytics:  return 3.0
        case .balanced:   return 4.5
        case .aggressive: return 5.0
        case .oldSchool:  return 6.0
        }
    }

    /// Ceilings are a longer projection than current level, so every club is
    /// worse at them by the same margin.
    static let potentialSigmaBonus = 1.0

    /// Share of `(team, prospect)` pairs that get a fat-tail misread. This is
    /// the STRANGER rate, carried onto `Lens` by `lens(forTeam:)`; a club looking
    /// at its own roster uses ``ownRosterFatTailRate``.
    static let fatTailRate = 0.07
    /// Magnitude band of that misread, in OVR points.
    static let fatTailMin = 8.0
    static let fatTailMax = 14.0

    /// How much of the current-level misread carries into the ceiling read.
    /// One scouting department watching one set of tape: a room that is high on
    /// a player tends to be high on both numbers, but not identically so.
    static let readCorrelation = 0.5

    /// Perceived values stay on the rating scale — a fat-tail miss must not
    /// produce a 104-OVR phantom that outranks every real prospect forever.
    static let perceivedFloor = 20.0
    static let perceivedCeiling = 99.0

    // MARK: - Lens

    /// One club's scouting lens: the σ pair its GM archetype implies.
    struct Lens {
        let teamID: UUID
        let archetype: TradeValueEngine.GMArchetype
        let sigmaOverall: Double
        /// Share of pairs this lens misreads catastrophically. On the lens
        /// rather than as a file-level constant because how often a room is
        /// COMPLETELY wrong depends on how well it knows the man — see
        /// ``ownRosterLens(forTeam:)``.
        let fatTailRate: Double
        var sigmaPotential: Double { sigmaOverall + potentialSigmaBonus }
    }

    /// The lens for one franchise looking at a STRANGER — a draft prospect, a
    /// free agent, anyone the club knows off tape and interviews.
    ///
    /// Cheap and pure — safe to call per prospect per pick, but `aiMakePick`
    /// hoists it out of the board loop anyway.
    static func lens(forTeam teamID: UUID) -> Lens {
        let archetype = TradeValueEngine.GMPersona.forTeam(id: teamID).archetype
        return Lens(
            teamID: teamID,
            archetype: archetype,
            sigmaOverall: sigmaOverall(for: archetype),
            fatTailRate: fatTailRate
        )
    }

    /// How much of the stranger-σ survives when the club is looking at a man on
    /// its OWN roster.
    ///
    /// D3 closes the development desk's `truePotential` read as "pure
    /// information unrealism" — but the honest correction is not to hand a club
    /// the draft's fog about its own third-year receiver. A front office sees
    /// its own players every day: in the building, in practice, in the training
    /// room, on its own coaches' reports. It is *better* at them than at
    /// anyone else and still not perfect, which is exactly why real clubs both
    /// extend the right man and hand a second contract to a player who never
    /// takes the step. At 0.45 the archetype spread lands at σ ≈ 1.4 (analytics)
    /// to 2.7 (old-school) on the ceiling read — a wrong-but-close ordering,
    /// not a blindfold.
    static let ownRosterSigmaScale = 0.45

    /// And it is rarer for a club to be catastrophically wrong about a man it
    /// employs — rarer, not impossible. This is the "we believed in him" bust,
    /// and D3(3) explicitly wants that tail to exist.
    static let ownRosterFatTailRate = 0.03

    // MARK: - Veterans (F-23 / D3 Option A)

    /// σ of a club's read on a VETERAN free agent, before the pairing cap below.
    ///
    /// Half the draft spread, and for a stated reason: a college prospect is
    /// projection off college tape, a veteran has years of professional film
    /// against professional opponents. Clubs are simply better at him. D3's
    /// Option A names 2.0 / 2.5 / 3.0 / 3.5 by archetype and that shape is kept
    /// here — the ORDER is the learnable part ("the old-school room is the one
    /// most likely to be wrong about a free agent").
    static func veteranSigmaUncapped(for archetype: TradeValueEngine.GMArchetype) -> Double {
        switch archetype {
        case .analytics:  return 2.0
        case .balanced:   return 2.5
        case .aggressive: return 3.0
        case .oldSchool:  return 3.5
        }
    }

    /// **The pairing, and the decision behind it.**
    ///
    /// D3 is explicit that fogging the AI alone is a gift — a club that misjudges
    /// free agents is a WEAKER bidder, and a weaker league accelerates exactly
    /// the rebuild F-23 is meant to make honest. It offers two ways to pay for
    /// it: a small user-side fog on free agents outside his division, or capping
    /// the AI σ at 2.0 "so the asymmetry stays small". It does not choose.
    ///
    /// This takes the cap, because the user-side fog is a much larger change than
    /// it sounds: every screen that prints a free agent's rating would have to
    /// print a fogged one, the number would stop meaning what it means everywhere
    /// else in the app, and it needs a scouting-spend mechanic to narrow. That is
    /// a feature, and it deserves to be built as one rather than smuggled in as
    /// the tail of a balance change. It is filed rather than skipped.
    ///
    /// The cap is applied as a SCALE, not a clamp: `2.0 / 3.5` scales the whole
    /// archetype table so the maximum lands on 2.0 and the clubs still differ
    /// from each other (1.14 / 1.43 / 1.71 / 2.00). A clamp would have flattened
    /// analytics, balanced and aggressive onto one number and thrown away the
    /// only property D3's Option A actually cares about — that the rooms are
    /// distinguishable and therefore learnable.
    static let veteranSigmaPairingScale = 2.0 / 3.5

    /// Share of `(team, veteran, season)` triples that get a fat-tail misread.
    ///
    /// Lower than the draft's 7 % — there is less to be catastrophically wrong
    /// about when a man has pro tape — but deliberately NOT zero and NOT scaled
    /// down with σ. This is the contract that eats a club for three years and the
    /// good player nobody would pay, which is D3(3)'s "big blunders are allowed"
    /// and the only part of this model that produces a story.
    static let veteranFatTailRate = 0.04

    /// The lens for one franchise looking at a veteran free agent.
    static func veteranLens(forTeam teamID: UUID) -> Lens {
        let archetype = TradeValueEngine.GMPersona.forTeam(id: teamID).archetype
        return Lens(
            teamID: teamID,
            archetype: archetype,
            sigmaOverall: veteranSigmaUncapped(for: archetype) * veteranSigmaPairingScale,
            fatTailRate: veteranFatTailRate
        )
    }

    /// A club's read on a veteran, **re-rolled every league year**.
    ///
    /// This is the one place the perception model is deliberately NOT
    /// pair-anchored. The draft fog is permanent on purpose: a front office
    /// misjudges a prospect the same way at pick 3 and pick 190 because it is the
    /// same evaluation of the same college tape. A veteran keeps PLAYING — a club
    /// that was wrong about him in 2028 has two more seasons of film by 2030, and
    /// should be able to be right about him. Mixing the season into the seed is
    /// what lets an opinion change without making it random within a year.
    static func veteranRead(
        teamID: UUID,
        playerID: UUID,
        season: Int,
        trueOverall: Int,
        truePotential: Int,
        lens: Lens? = nil
    ) -> Read {
        read(
            teamID: teamID,
            prospectID: playerID,
            trueOverall: trueOverall,
            truePotential: truePotential,
            lens: lens ?? veteranLens(forTeam: teamID),
            seedSalt: UInt64(bitPattern: Int64(season))
        )
    }

    /// The lens for one franchise looking at its OWN player.
    ///
    /// Same deterministic, persona-shaped machinery as ``lens(forTeam:)`` —
    /// the same room is wrong about the same man in the same direction all
    /// season, and an analytics shop is tighter than an old-school one — just
    /// narrowed for familiarity. See ``ownRosterSigmaScale``.
    static func ownRosterLens(forTeam teamID: UUID) -> Lens {
        let archetype = TradeValueEngine.GMPersona.forTeam(id: teamID).archetype
        return Lens(
            teamID: teamID,
            archetype: archetype,
            sigmaOverall: sigmaOverall(for: archetype) * ownRosterSigmaScale,
            fatTailRate: ownRosterFatTailRate
        )
    }

    // MARK: - Read

    /// One club's read on one prospect.
    struct Read {
        /// Perceived current level (the club's `trueOverall`).
        let overall: Double
        /// Perceived ceiling (the club's `truePotential`).
        let potential: Double
        /// Whether the fat tail fired for this pair — diagnostics only, never
        /// exposed to the user.
        let isFatTail: Bool
        /// Signed error on the current-level read, `perceived − true`.
        let overallError: Double
    }

    /// What `teamID`'s front office believes about `prospectID`.
    ///
    /// Deterministic: same inputs → same read, every call, every launch.
    /// - Parameter seedSalt: mixed into the pair seed so a caller can re-roll the
    ///   same pair on a schedule of its own. `0` (the default) is the permanent,
    ///   pair-anchored draft behaviour; `veteranRead` passes the league year.
    static func read(
        teamID: UUID,
        prospectID: UUID,
        trueOverall: Int,
        truePotential: Int,
        lens: Lens? = nil,
        seedSalt: UInt64 = 0
    ) -> Read {
        let l = lens ?? Self.lens(forTeam: teamID)
        var rng = SeededLeagueRandom(
            seed: saltedSeed(pairSeed(teamID: teamID, prospectID: prospectID), salt: seedSalt)
        )

        // Box-Muller off the repo RNG: two uniforms in, two independent
        // standard normals out. `u1` is floored away from 0 because log(0) is
        // −inf and SplitMix64 can legitimately return it.
        let u1 = max(1e-12, Double.random(in: 0..<1, using: &rng))
        let u2 = Double.random(in: 0..<1, using: &rng)
        let r = (-2.0 * log(u1)).squareRoot()
        let z0 = r * cos(2.0 * .pi * u2)
        let z1 = r * sin(2.0 * .pi * u2)

        // Correlated second draw — same room, same tape.
        let zPot = readCorrelation * z0
            + (1.0 - readCorrelation * readCorrelation).squareRoot() * z1

        var errOverall = z0 * l.sigmaOverall
        var errPotential = zPot * l.sigmaPotential

        // Fat tail: the whole point of the file. A club that is completely
        // wrong about a man is wrong about all of him, so the shift lands on
        // both numbers in the same direction.
        let tailRoll = Double.random(in: 0..<1, using: &rng)
        let isFatTail = tailRoll < l.fatTailRate
        if isFatTail {
            let magnitude = Double.random(in: fatTailMin...fatTailMax, using: &rng)
            let sign: Double = Double.random(in: 0..<1, using: &rng) < 0.5 ? -1.0 : 1.0
            errOverall += sign * magnitude
            errPotential += sign * magnitude
        }

        let perceivedOverall = clampToScale(Double(trueOverall) + errOverall)
        let perceivedPotential = max(
            perceivedOverall,
            clampToScale(Double(truePotential) + errPotential)
        )

        return Read(
            overall: perceivedOverall,
            potential: perceivedPotential,
            isFatTail: isFatTail,
            overallError: perceivedOverall - Double(trueOverall)
        )
    }

    // MARK: - Private

    private static func clampToScale(_ value: Double) -> Double {
        min(perceivedCeiling, max(perceivedFloor, value))
    }

    /// Stable 64-bit seed for one `(team, prospect)` pair.
    ///
    /// Both UUIDs are folded to two 64-bit words and XORed word-wise, then
    /// stirred with the SplitMix64 / xxHash constants so neighbouring pairs
    /// decorrelate. `hashValue` is deliberately not used: Swift's Hashable seed
    /// is randomized per process, which would re-roll every club's board on
    /// every app launch and break "the same GM always misjudges the same man".
    static func pairSeed(teamID: UUID, prospectID: UUID) -> UInt64 {
        let t = words(teamID)
        let p = words(prospectID)
        var s = (t.hi ^ p.hi) &* 0x9E37_79B9_7F4A_7C15
        s = (s ^ (s >> 29)) &+ ((t.lo ^ p.lo) &* 0xBF58_476D_1CE4_E5B9)
        s = (s ^ (s >> 32)) &* 0x94D0_49BB_1331_11EB
        return s == 0 ? 0x9E37_79B9_7F4A_7C15 : s
    }

    /// Mixes a salt into a pair seed without weakening it. `salt == 0` returns the
    /// seed untouched, so every existing pair-anchored read is bit-identical.
    private static func saltedSeed(_ seed: UInt64, salt: UInt64) -> UInt64 {
        guard salt != 0 else { return seed }
        var s = seed ^ (salt &* 0x9E37_79B9_7F4A_7C15)
        s = (s ^ (s >> 30)) &* 0xBF58_476D_1CE4_E5B9
        s = (s ^ (s >> 27)) &* 0x94D0_49BB_1331_11EB
        s = s ^ (s >> 31)
        return s == 0 ? 0x9E37_79B9_7F4A_7C15 : s
    }

    /// Packs a UUID's 16 raw bytes into two `UInt64` words.
    private static func words(_ id: UUID) -> (hi: UInt64, lo: UInt64) {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        var hi: UInt64 = 0
        var lo: UInt64 = 0
        for i in 0..<8 { hi = (hi << 8) | UInt64(bytes[i]) }
        for i in 8..<16 { lo = (lo << 8) | UInt64(bytes[i]) }
        return (hi, lo)
    }
}
