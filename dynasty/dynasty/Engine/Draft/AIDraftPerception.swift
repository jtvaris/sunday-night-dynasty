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

    /// Share of `(team, prospect)` pairs that get a fat-tail misread.
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
        var sigmaPotential: Double { sigmaOverall + potentialSigmaBonus }
    }

    /// The lens for one franchise. Cheap and pure — safe to call per prospect
    /// per pick, but `aiMakePick` hoists it out of the board loop anyway.
    static func lens(forTeam teamID: UUID) -> Lens {
        let archetype = TradeValueEngine.GMPersona.forTeam(id: teamID).archetype
        return Lens(
            teamID: teamID,
            archetype: archetype,
            sigmaOverall: sigmaOverall(for: archetype)
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
    static func read(
        teamID: UUID,
        prospectID: UUID,
        trueOverall: Int,
        truePotential: Int,
        lens: Lens? = nil
    ) -> Read {
        let l = lens ?? Self.lens(forTeam: teamID)
        var rng = SeededLeagueRandom(seed: pairSeed(teamID: teamID, prospectID: prospectID))

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
        let isFatTail = tailRoll < fatTailRate
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
