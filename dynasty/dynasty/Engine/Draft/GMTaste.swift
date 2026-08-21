import Foundation

/// Per-club draft TASTE: what one front office systematically over- and
/// under-values, as opposed to what it misjudges.
///
/// ## Why this exists, and why it is not more noise
///
/// `AIDraftPerception` already gives every club a private, wrong board. What it
/// does not give any club is a *reason* to be wrong in the same direction twice.
/// Its error is zero-mean and symmetric by construction, so 32 rooms come out
/// of it slightly worse than the user and indistinguishable from each other —
/// the exact failure `docs/AI_DESIGN_DECISIONS.md` D3 rejects as Option B
/// ("the option that looks like the goal and is not"). Measured before this
/// file: the only thing separating one AI board from another was the σ of its
/// GM archetype, 3.0 to 6.0 OVR, and nobody in the league was *systematically*
/// wrong about anything.
///
/// A real scouting department has a philosophy. It is the reason a club drafts
/// the same kind of player for a decade, the reason a coordinator's arrival
/// changes what a war room argues about, and the reason a rival's board is
/// worth studying at all. D3's refinement states the requirement directly: the
/// AI *plans*, and errors come from a bad philosophy rather than from a die
/// rolled at the moment of decision.
///
/// So each club draws **two** permanent tastes from its UUID and keeps them for
/// the life of the league. They are:
///
/// - **deterministic** — a pure function of the team id, like
///   `AIDraftPerception.pairSeed` and `TradeValueEngine.GMPersona.forTeam`, and
///   for the same reason: `hashValue`'s seed is randomised per process, so a
///   league's identities would re-roll on every launch and "Denver always
///   overpays for size" would never become a true sentence;
/// - **public in their inputs** — every field read below is one the user can
///   read too (combine numbers, college production, competition level,
///   disclosed flags, age, position). No taste reads `trueOverall`,
///   `truePotential` or `truePhysical`. A taste is an OPINION about visible
///   evidence, which is what makes it learnable; a taste computed from hidden
///   truth would just be a second fog;
/// - **bounded** — the sum of a club's two tastes is capped at
///   ``houseCap`` = 4.0 OVR points. That number is the whole design: 2-4 points
///   is one letter grade and ~15-27 slots of round-1 consensus movement —
///   enough that a user who watches four drafts can name it, never enough that
///   he can solve it. A taste strong enough to be a formula is a bug, not a
///   stronger flavour.
///
/// ## What was tried and rejected
///
/// - **Scheme fit (`+2.5` on an OC/DC-matching prospect)**, which
///   `docs/AI_FIX_QUEUE.md` F-26 lists as one of the six. Cut: `aiMakePick`
///   receives no scheme channel, `Team` carries only a *last camp* snapshot,
///   and `ProspectSchemeFitHelper` is not staged in the balance harness — so
///   the taste would have cost a new argument, a new harness stage and a stub
///   field, and would then have been unmeasurable in the one scenario that can
///   see the draft. ``Taste/productionHawk`` replaces it and buys more: it is
///   the direct opposite pole of ``Taste/traitsOverTape``, so the league now
///   contains rooms that argue with each other about the same man for a reason
///   a fan would recognise.
/// - **Reading `truePhysical` for the traits taste**, which is what F-26's
///   `+0.4 × (physicalScore − 70)` literally says. Rejected as a fog breach:
///   `truePhysical` is the ground truth the game develops the player from.
///   ``athleticZ(_:)`` measures the man against his own position's published
///   combine table instead, which is both honest and closer to what "traits
///   over tape" means in a real building — the club falls in love with the
///   *testing*, and the testing is only correlated with the player.
/// - **Letting the quarterback be a favoured or disfavoured position group.**
///   He already carries two dedicated terms in `aiMakePick`
///   (`quarterbackPremium` and F-27's position-run jump); a third would make
///   one club's board unrecognisable rather than distinctive.
///
/// ## The asymmetry in ``Taste/characterHawk``, stated rather than hidden
///
/// The character taste reads `CollegeProspect.redFlags` directly. The user
/// reaches the same field through `ProspectFog.flagDisclosure`, which costs him
/// scouting work. That is a real asymmetry and it is deliberate: the flags in
/// that array are the ones that have *broken* (see
/// `ScoutingEngine.applyCharacterFindings` — "real character intel breaks in
/// February and March"), i.e. league-wide knowledge, and every club is assumed
/// to run the background check its own building exists to run. It is bounded to
/// one field, it fires on ~6 % of a class, and it moves the board for the ~1 in
/// 3 clubs that drew the taste.
enum GMTaste {

    // MARK: - The six tastes

    /// One permanent house preference. Two per club, drawn from the team UUID.
    ///
    /// Six rather than four so that with 32 clubs and two draws each, every
    /// taste lands on ~10-11 franchises — common enough that a user meets it,
    /// rare enough that meeting it means something.
    enum Taste: String, CaseIterable {
        /// Falls in love with the workout. Scores the prospect's combine
        /// numbers against his own position's published table.
        case traitsOverTape
        /// The opposite pole: believes the tape and the box score. Scores
        /// college production against the class's own centre.
        ///
        /// Note that this taste is mildly *correct* on average — production
        /// correlates 0.30-0.65 with `trueOverall` by the `draftclass` gate's
        /// own §7.9 band — and it is meant to be. It pays for that in the one
        /// place it matters: `DraftClassBuilder`'s buried-usage cohort (~4-6 %
        /// of every class, whose production measures snaps and nothing else)
        /// is invisible to it, so a production room systematically passes on
        /// exactly the hidden gems a traits room chases.
        case productionHawk
        /// Loves one position group, is cool on another. The "Denver always
        /// overpays for size" taste, and the most legible of the six because a
        /// user can read it straight off a draft ticker.
        case positionBias
        /// Will not spend early on a man who played nobody.
        case smallSchoolAversion
        /// Takes a disclosed character finding off the board rather than
        /// discounting it.
        case characterHawk
        /// Wants the 21-year-old. A fifth-year senior loses real ground.
        case ageHawk
    }

    /// The position groups ``Taste/positionBias`` draws from.
    ///
    /// Quarterback is deliberately absent — see the type doc. Specialists are
    /// absent because `aiMakePick`'s `specialistDiscount` already makes the
    /// league's one emphatic positional statement about them, and a house
    /// taste on top of a -8.0 would be inaudible.
    enum PositionGroup: String, CaseIterable {
        case backfield        // RB, FB
        case receivers        // WR, TE
        case offensiveLine    // LT, LG, C, RG, RT
        case defensiveLine    // DE, DT
        case linebackers      // OLB, MLB
        case secondary        // CB, FS, SS

        static func of(_ position: Position) -> PositionGroup? {
            switch position {
            case .RB, .FB:                  return .backfield
            case .WR, .TE:                  return .receivers
            case .LT, .LG, .C, .RG, .RT:    return .offensiveLine
            case .DE, .DT:                  return .defensiveLine
            case .OLB, .MLB:                return .linebackers
            case .CB, .FS, .SS:             return .secondary
            case .QB, .K, .P:               return nil
            }
        }
    }

    // MARK: - Tuning
    //
    // Every constant below is in OVR points on the draft board, the same
    // currency `aiMakePick` scores in, and every one of them trades the same
    // thing against the same thing: LEGIBILITY (can the user name this club's
    // habit after four drafts?) against SOLVABILITY (can he price it exactly?).
    // The band the design fixes is 2-4 points — one letter grade — and
    // `houseCap` is what enforces it on a club that drew two loud tastes.

    /// Hard ceiling on the ABSOLUTE SUM of a club's two tastes.
    ///
    /// Trades character against exploitability. At 4.0 a house preference is
    /// worth ~27 slots of round-1 board movement (the consensus anchor's
    /// derivative at slot 16 is -0.146 points/slot, so 1 OVR ≈ 6.8 slots) —
    /// a visible, learnable habit. Raise it and a club stops drafting a
    /// position group entirely, which is the specific failure F-26's own risk
    /// note names; lower it and the taste disappears under
    /// `AIDraftPerception`'s σ 3.0-6.0 fog and nothing is learnable at all.
    static let houseCap = 4.0

    /// Board points per standard deviation of position-relative combine
    /// testing, for ``Taste/traitsOverTape``.
    ///
    /// Trades the size of the traits room's signature against how often it
    /// saturates. At 2.4 the term hits its ±3.0 clamp at 1.25σ, so roughly the
    /// top and bottom decile of testers get the full statement and everyone in
    /// between gets a graded one — a room that likes athletes, not a room that
    /// only sees athletes.
    static let traitsPointsPerSigma = 2.4

    /// Board points per standard deviation of class-relative college
    /// production, for ``Taste/productionHawk``. Matched to
    /// ``traitsPointsPerSigma`` on purpose: the two poles of the same argument
    /// should be the same size, or the league has a right answer.
    static let productionPointsPerSigma = 2.4

    /// Clamp on either of the two z-scored tastes above, before ``houseCap``.
    /// Keeps a three-sigma combine freak from being worth a whole letter grade
    /// on his own.
    static let zTasteClamp = 3.0

    /// ``Taste/positionBias``: what the favoured group is worth.
    ///
    /// Deliberately asymmetric with ``positionBiasAgainst``. A front office
    /// that *loves* a group acts on it; one that is cool on a group merely
    /// takes the other man when it is close. Making the two equal produced a
    /// club with two blind spots rather than one identity.
    static let positionBiasFor = 3.0
    /// What the disfavoured group is worth. Half the favoured magnitude — see
    /// ``positionBiasFor``.
    static let positionBiasAgainst = -1.5

    /// ``Taste/smallSchoolAversion``, by the level of competition he faced.
    ///
    /// Graded rather than the flat -2.0 F-26 proposes, because the real
    /// aversion is graded: a Group-of-Five starter is a known quantity with a
    /// discount, an FCS prospect is an argument. The FCS rung keeps F-26's
    /// magnitude so the taste's ceiling is unchanged.
    static let smallSchoolFCSPenalty = -2.0
    /// The milder rung — see ``smallSchoolFCSPenalty``.
    static let smallSchoolG5Penalty = -1.0

    /// ``Taste/characterHawk``: what one disclosed red flag costs on this
    /// club's board. Capped at one flag's worth however many he carries —
    /// -4.0 is already the top of the 2-4 band, and a second flag doubling it
    /// would put the taste outside the design's own bound.
    static let characterFlagPenalty = -4.0

    /// ``Taste/ageHawk``: board points per year of age over 21.
    ///
    /// Trades the age room's signature against how many men it can even
    /// consider. At -1.2 a 24-year-old fifth-year senior loses 3.6 points and
    /// a 22-year-old loses 1.2, which reorders the margins of the board
    /// without emptying it. `ageHawkFloor` stops a 26-year-old JUCO transfer
    /// from being unpickable.
    static let agePointsPerYearOver21 = -1.2
    /// Floor on the age term — see ``agePointsPerYearOver21``.
    static let ageHawkFloor = -3.6
    /// The age below which the hawk has no opinion. 21 is a true junior; the
    /// class's own senior line is `CollegeProspect.seniorAge` (22).
    static let ageHawkPivot = 21

    // MARK: - House

    /// One franchise's permanent draft identity.
    struct House {
        let teamID: UUID
        /// Exactly two, always distinct.
        let tastes: [Taste]
        /// Meaningful only when ``tastes`` contains ``Taste/positionBias``.
        let favoured: PositionGroup
        /// Ditto, and never equal to ``favoured``.
        let disfavoured: PositionGroup

        func has(_ taste: Taste) -> Bool { tastes.contains(taste) }

        /// A one-line description of the house, in the vocabulary a war room
        /// would use. Not rendered anywhere yet — it exists so that a scouting
        /// surface that wants to sell "what this club likes" has one spelling
        /// to use rather than inventing a second.
        var blurb: String {
            tastes.map { taste in
                switch taste {
                case .traitsOverTape:      return "chases testing numbers"
                case .productionHawk:      return "drafts production"
                case .positionBias:        return "spends on \(favoured.rawValue), not \(disfavoured.rawValue)"
                case .smallSchoolAversion: return "wants the big-school man"
                case .characterHawk:       return "takes flagged prospects off the board"
                case .ageHawk:             return "wants them young"
                }
            }.joined(separator: "; ")
        }
    }

    /// The permanent house for one franchise. Cheap and pure — safe to call per
    /// pick, but `aiMakePick` hoists it out of the board loop anyway.
    static func house(forTeam teamID: UUID) -> House {
        let all = Taste.allCases
        // Two distinct draws without a rejection loop: the second index is an
        // offset in 1..<count from the first, so it can never collide and stays
        // uniform over the remaining five.
        let first = Int(dice(teamID, byteOffset: 5) % UInt64(all.count))
        let step = 1 + Int(dice(teamID, byteOffset: 13) % UInt64(all.count - 1))
        let second = (first + step) % all.count

        let groups = PositionGroup.allCases
        let favouredIndex = Int(dice(teamID, byteOffset: 2) % UInt64(groups.count))
        let groupStep = 1 + Int(dice(teamID, byteOffset: 10) % UInt64(groups.count - 1))
        let disfavouredIndex = (favouredIndex + groupStep) % groups.count

        return House(
            teamID: teamID,
            tastes: [all[first], all[second]],
            favoured: groups[favouredIndex],
            disfavoured: groups[disfavouredIndex]
        )
    }

    // MARK: - Board context

    /// The class-relative centre ``Taste/productionHawk`` scores against.
    ///
    /// Computed off the board that is actually left rather than off a constant,
    /// so the taste stays a *relative* preference all the way into round 7,
    /// where the whole remaining pool grades below the class mean and a fixed
    /// pivot would turn the taste into a flat penalty on everybody.
    struct BoardContext {
        let meanProduction: Double
        let sdProduction: Double

        /// Fallback σ when the remaining board is degenerate (one man left, or
        /// every man carrying the same score). Half of the generator's own
        /// σ = 7 production noise, which is the smallest spread a real board
        /// ever shows.
        static let minimumProductionSigma = 3.5

        init(board: [CollegeProspect]) {
            guard !board.isEmpty else {
                meanProduction = 0
                sdProduction = Self.minimumProductionSigma
                return
            }
            let scores = board.map { Double($0.collegeProductionScore) }
            let mean = scores.reduce(0, +) / Double(scores.count)
            let variance = scores.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) } / Double(scores.count)
            meanProduction = mean
            sdProduction = max(Self.minimumProductionSigma, variance.squareRoot())
        }
    }

    // MARK: - Adjustment

    /// What `house` adds to (or takes off) this prospect's board score, in OVR
    /// points, bounded by ``houseCap``.
    ///
    /// Additive and in rating points for the same reason every other term in
    /// `aiMakePick` is: a multiplier on a 40-99 rating does not tilt a board,
    /// it replaces it (see that function's "why the score is a SUM" note).
    static func boardAdjustment(
        prospect: CollegeProspect,
        house: House,
        context: BoardContext
    ) -> Double {
        var total = 0.0
        for taste in house.tastes {
            switch taste {
            case .traitsOverTape:
                if let z = athleticZ(prospect) {
                    total += clampTaste(traitsPointsPerSigma * z)
                }
            case .productionHawk:
                let z = (Double(prospect.collegeProductionScore) - context.meanProduction)
                    / context.sdProduction
                total += clampTaste(productionPointsPerSigma * z)
            case .positionBias:
                if let group = PositionGroup.of(prospect.position) {
                    if group == house.favoured { total += positionBiasFor }
                    if group == house.disfavoured { total += positionBiasAgainst }
                }
            case .smallSchoolAversion:
                switch prospect.collegeCompetitionLevel {
                case .fcs:         total += smallSchoolFCSPenalty
                case .groupOfFive: total += smallSchoolG5Penalty
                default:           break
                }
            case .characterHawk:
                if !(prospect.redFlags ?? []).isEmpty { total += characterFlagPenalty }
            case .ageHawk:
                let over = Double(max(0, prospect.age - ageHawkPivot))
                total += max(ageHawkFloor, agePointsPerYearOver21 * over)
            }
        }
        return min(houseCap, max(-houseCap, total))
    }

    // MARK: - Athletic testing

    /// How this man tested against HIS OWN POSITION, in standard deviations,
    /// or `nil` when he never tested.
    ///
    /// Reads `ScoutingEngine.CombineDrillTable` — the same per-position mean/σ
    /// the combine itself was drawn from and the same table the `draftclass`
    /// gate verifies byte-identical against the repo — so "one sigma of speed"
    /// means the same thing here as it does on the combine screen. A drill
    /// where lower is better (the forty, the cone, the shuttle) has its z
    /// negated, so a positive z always means "better athlete".
    ///
    /// `nil` for an untested man is deliberate and is not a zero: a club that
    /// chases workout numbers has nothing to chase on a prospect who never got
    /// a combine invite and never posted a pro-day number, and giving him the
    /// class average would quietly make the taste an invitation bonus.
    static func athleticZ(_ prospect: CollegeProspect) -> Double? {
        let drills = ScoutingEngine.CombineDrillTable.drills(for: prospect.position)
        var zs: [Double] = []
        func add(_ value: Double?, _ drill: ScoutingEngine.CombineDrill) {
            guard let value, drill.sd > 0 else { return }
            let z = (value - drill.mean) / drill.sd
            zs.append(drill.lowerIsBetter ? -z : z)
        }
        add(prospect.fortyTime, drills.forty)
        add(prospect.benchPress.map(Double.init), drills.bench)
        add(prospect.verticalJump, drills.vertical)
        add(prospect.broadJump.map(Double.init), drills.broad)
        add(prospect.coneDrill, drills.cone)
        add(prospect.shuttleTime, drills.shuttle)
        guard !zs.isEmpty else { return nil }
        return zs.reduce(0, +) / Double(zs.count)
    }

    // MARK: - Private

    private static func clampTaste(_ value: Double) -> Double {
        min(zTasteClamp, max(-zTasteClamp, value))
    }

    /// Eight of a UUID's bytes as a `UInt64`, starting at `byteOffset` and
    /// wrapping.
    ///
    /// The same construction `TradeValueEngine.GMPersona.forTeam` uses (whose
    /// own copy is private) and for the same reason `AIDraftPerception.pairSeed`
    /// avoids `hashValue`: Swift's `Hashable` seed is randomised per process, so
    /// a league's identities would be re-drawn on every launch. Distinct
    /// `byteOffset`s here also keep the two taste draws decorrelated from the GM
    /// archetype draw at offset 8 — a club can be an analytics shop that chases
    /// testing numbers, which is a real and slightly contradictory front office.
    private static func dice(_ id: UUID, byteOffset: Int) -> UInt64 {
        let b = id.uuid
        let bytes = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
                     b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15]
        var value: UInt64 = 0
        for i in 0..<8 {
            value = (value << 8) | UInt64(bytes[(byteOffset + i) % 16])
        }
        return value
    }
}
